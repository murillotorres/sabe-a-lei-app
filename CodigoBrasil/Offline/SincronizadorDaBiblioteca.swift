import Foundation

/// Baixa e mantém atualizados os livros offline. É o único lugar que escreve
/// no `LocalBookStore`.
///
/// Trabalha em uma fila serial (um trabalho por vez, nunca dezenas de
/// requisições em paralelo) e só usa requisições de prioridade baixa, que
/// esperam a rede ficar ociosa — nada aqui atrapalha a tela. Três operações:
///
/// - **baixar**: o livro inteiro, por páginas; só é gravado depois de completo e
///   com o checksum conferido;
/// - **verificar**: consulta o manifesto (uma requisição minúscula) e atualiza só
///   os livros que já estão salvos e cuja versão mudou;
/// - **atualizar**: aplica o delta da versão local até a mais nova; se o delta
///   não for possível ou falhar, baixa o livro inteiro. Em qualquer falha a cópia
///   anterior continua valendo.
actor SincronizadorDaBiblioteca {
    static let shared = SincronizadorDaBiblioteca()

    private enum Trabalho: Equatable {
        case baixar(String)
        case verificar
    }

    /// Depois de uma falha, não insiste no mesmo livro por este tempo (evita laço
    /// de tentativas quando a rede ou o servidor estão ruins).
    private static let esperaAposFalha: TimeInterval = 300

    /// Uma publicação no meio de um download obriga a recomeçar; desiste depois disso.
    private static let recomecosPermitidos = 2

    private let loja: LocalBookStore

    /// A configuração é a fonte da verdade: trocar para "não armazenar" vale na
    /// hora, mesmo para um download que já esteja rodando (ele não grava).
    private var modoPermiteBaixar: Bool { ModoDeArmazenamento.salvo.permiteBaixar }

    private var fila: [Trabalho] = []
    private var operario: Task<Void, Never>?
    private var emAndamento: Trabalho?
    private var transitorio: [String: EstadoDoDownload] = [:]
    private var naoTentarAte: [String: Date] = [:]
    private var observador: (@Sendable (String, EstadoOffline) -> Void)?

    init(loja: LocalBookStore = .shared) {
        self.loja = loja
    }

    // MARK: Interface

    /// Quem quiser acompanhar o estado dos livros (a camada de UI) se registra aqui.
    func observar(_ observador: @escaping @Sendable (String, EstadoOffline) -> Void) {
        self.observador = observador
    }

    func estadosArmazenados() async -> [String: EstadoOffline] {
        var estados: [String: EstadoOffline] = [:]
        for id in await loja.idsArmazenados() {
            estados[id] = await estado(de: id)
        }
        return estados
    }

    /// Pede o download completo de um livro (chamado quando o usuário o abre).
    /// Não faz nada se ele já está salvo, já está na fila ou falhou há pouco.
    func solicitarDownload(_ id: String) {
        let trabalho = Trabalho.baixar(id)
        guard modoPermiteBaixar, emAndamento != trabalho, !fila.contains(trabalho) else { return }
        if let espera = naoTentarAte[id], espera > Date() { return }

        fila.append(trabalho)
        iniciarOperario()
    }

    /// Pede a verificação de atualizações dos livros salvos.
    func solicitarVerificacao() {
        guard modoPermiteBaixar, emAndamento != .verificar, !fila.contains(.verificar) else { return }

        fila.append(.verificar)
        iniciarOperario()
    }

    /// Interrompe tudo. Retorna quando nenhum trabalho está mais em execução —
    /// só então é seguro apagar os arquivos.
    func cancelarTudo() async {
        fila.removeAll()
        operario?.cancel()
        await operario?.value
        operario = nil
        emAndamento = nil
        transitorio.removeAll()
        naoTentarAte.removeAll()
    }

    // MARK: Fila

    private func iniciarOperario() {
        guard operario == nil else { return }
        operario = Task(priority: .utility) { await self.processarFila() }
    }

    private func processarFila() async {
        while !Task.isCancelled, !fila.isEmpty {
            let trabalho = fila.removeFirst()
            emAndamento = trabalho

            switch trabalho {
            case .baixar(let id): await baixarSeNecessario(id)
            case .verificar: await verificarBiblioteca()
            }

            emAndamento = nil
        }
        operario = nil
    }

    // MARK: Download

    private func baixarSeNecessario(_ id: String) async {
        // Já disponível offline: nada a fazer (é o caso de quase toda abertura de livro).
        guard await loja.livro(id) == nil else { return }

        LogOffline.offline("Starting download: \(id)")
        await mudarStatus(id, .downloading)

        do {
            let livro = try await baixarLivroInteiro(id)
            try Task.checkCancellation()
            guard modoPermiteBaixar else { throw CancellationError() }
            try await loja.salvar(livro)
            await registrarSucesso(id)
            LogOffline.offline("Download complete: \(id) v\(livro.versao)")
        } catch {
            await registrarFalha(id, error)
        }

        await mudarStatus(id, nil)
    }

    /// Baixa o livro por páginas e só o devolve completo e conferido: contagem
    /// de artigos e checksum iguais aos que o servidor anunciou. Nada é gravado aqui.
    private func baixarLivroInteiro(_ id: String) async throws -> LivroOffline {
        var recomecos = 0
        while true {
            do {
                return try await baixarUmaVez(id)
            } catch ErroDeSincronizacao.versaoMudouNoMeio where recomecos < Self.recomecosPermitidos {
                recomecos += 1
                LogOffline.offline("\(id) changed while downloading — restarting")
            }
        }
    }

    private func baixarUmaVez(_ id: String) async throws -> LivroOffline {
        var artigos: [ArtigoOffline] = []
        var cabecalho: (livro: LivroDoManifesto, lei: Lei)?
        var deslocamento = 0

        while true {
            try Task.checkCancellation()
            let pagina = try await BibliotecaService.conteudo(leiSlug: id, deslocamento: deslocamento)

            if let cabecalho {
                // Uma nova versão publicada no meio do download misturaria conteúdos de versões diferentes.
                guard pagina.livro.versao == cabecalho.livro.versao, pagina.livro.checksum == cabecalho.livro.checksum else {
                    throw ErroDeSincronizacao.versaoMudouNoMeio
                }
            } else {
                cabecalho = (pagina.livro, pagina.lei)
            }

            artigos += pagina.artigos
            LogOffline.detalhe("\(id): \(artigos.count)/\(pagina.livro.totalDeArtigos) articles")

            guard pagina.paginacao.temMais, !pagina.artigos.isEmpty else { break }
            deslocamento += pagina.artigos.count
        }

        guard let cabecalho else { throw ErroDeSincronizacao.contagemDivergente }

        let ordenados = LivroOffline.ordenados(artigos)
        guard ordenados.count == cabecalho.livro.totalDeArtigos else { throw ErroDeSincronizacao.contagemDivergente }
        guard LivroOffline.checksum(de: ordenados) == cabecalho.livro.checksum else { throw ErroDeSincronizacao.checksumDivergente }

        return LivroOffline(
            versao: cabecalho.livro.versao, checksum: cabecalho.livro.checksum,
            baixadoEm: Date(), lei: cabecalho.lei, artigos: ordenados
        )
    }

    // MARK: Atualização

    private func verificarBiblioteca() async {
        LogOffline.sync("Checking library manifest")

        let ids = await loja.idsArmazenados()
        guard !ids.isEmpty else {
            LogOffline.sync("No stored books — nothing to check")
            return
        }

        let manifesto: ManifestoResponse
        do {
            manifesto = try await BibliotecaService.manifesto()
        } catch {
            // Sem internet (ou servidor sem offline): os livros locais seguem valendo, tenta na próxima.
            LogOffline.sync("Manifest unavailable: \(error.localizedDescription)")
            return
        }

        let remotos = Dictionary(manifesto.livros.map { ($0.id, $0) }, uniquingKeysWith: { primeiro, _ in primeiro })

        // Só os livros que já estão no aparelho — a biblioteca inteira nunca é baixada.
        for id in ids {
            guard !Task.isCancelled else { return }

            guard let remoto = remotos[id] else {
                LogOffline.sync("\(id) not in manifest — keeping local copy")
                continue
            }
            await atualizarSeNecessario(id, remoto: remoto)
        }
    }

    private func atualizarSeNecessario(_ id: String, remoto: LivroDoManifesto) async {
        guard let local = await loja.livro(id) else { return }

        await loja.atualizarEstado(id) { $0.verificadoEm = Date() }
        LogOffline.sync("\(id) local=\(local.versao) remote=\(remoto.versao)")

        guard local.versao != remoto.versao || local.checksum != remoto.checksum else {
            await publicar(id)
            return
        }

        if let espera = naoTentarAte[id], espera > Date() { return }

        await mudarStatus(id, .updating)

        do {
            let novo: LivroOffline
            if local.versao == remoto.versao {
                // Mesma versão, conteúdo diferente do publicado: cópia inconsistente. Prioriza a consistência.
                LogOffline.sync("\(id) content differs at v\(local.versao) — full download")
                novo = try await baixarLivroInteiro(id)
            } else {
                novo = try await atualizarIncrementalmente(local)
            }

            try Task.checkCancellation()
            guard modoPermiteBaixar else { throw CancellationError() }
            try await loja.salvar(novo)
            await registrarSucesso(id)
            LogOffline.sync("\(id) updated to \(novo.versao)")
        } catch {
            // A cópia anterior continua no disco e utilizável.
            await registrarFalha(id, error)
        }

        await mudarStatus(id, nil)
    }

    /// Aplica só o que mudou. Sem delta viável, ou se aplicá-lo der errado,
    /// cai para o download completo — consistência acima de insistir no incremental.
    private func atualizarIncrementalmente(_ local: LivroOffline) async throws -> LivroOffline {
        let id = local.id

        let resposta: AtualizacoesResponse
        do {
            resposta = try await BibliotecaService.atualizacoes(leiSlug: id, de: local.versao)
        } catch let erro as APIError {
            LogOffline.sync("\(id) updates endpoint failed (\(erro.localizedDescription)) — full download")
            return try await baixarLivroInteiro(id)
        }

        guard !resposta.requerDownloadCompleto,
              resposta.deVersao == local.versao,
              let versao = resposta.paraVersao,
              let checksum = resposta.checksum
        else {
            LogOffline.sync("\(id) has no usable delta from v\(local.versao) — full download")
            return try await baixarLivroInteiro(id)
        }

        LogOffline.sync("Applying \(resposta.mudancas.count) changes")

        do {
            return try local.aplicando(resposta.mudancas, versao: versao, checksumEsperado: checksum)
        } catch {
            LogOffline.sync("\(id) delta did not apply (\(error)) — full download")
            return try await baixarLivroInteiro(id)
        }
    }

    // MARK: Estado

    private func mudarStatus(_ id: String, _ status: EstadoDoDownload?) async {
        transitorio[id] = status
        await publicar(id)
    }

    private func registrarSucesso(_ id: String) async {
        naoTentarAte[id] = nil
        await loja.atualizarEstado(id) {
            $0.ultimoErro = nil
            $0.verificadoEm = Date()
        }
    }

    private func registrarFalha(_ id: String, _ erro: Error) async {
        // Cancelar (troca de modo, app encerrando) não é falha.
        if erro is CancellationError || (erro as? URLError)?.code == .cancelled {
            LogOffline.offline("Cancelled: \(id)")
            return
        }

        LogOffline.offline("Failed: \(id) — \(erro.localizedDescription)")
        naoTentarAte[id] = Date().addingTimeInterval(Self.esperaAposFalha)
        await loja.atualizarEstado(id) { $0.ultimoErro = erro.localizedDescription }
    }

    private func estado(de id: String) async -> EstadoOffline {
        let resumo = await loja.resumo(id)
        let persistido = await loja.estadoPersistido(id)

        var estado = EstadoOffline()
        estado.versaoLocal = resumo?.versao
        estado.baixadoEm = resumo?.baixadoEm
        estado.tamanhoEmBytes = resumo?.tamanhoEmBytes
        estado.verificadoEm = persistido.verificadoEm
        estado.ultimoErro = persistido.ultimoErro
        estado.status = transitorio[id]
            ?? (persistido.ultimoErro != nil ? .failed : (resumo != nil ? .downloaded : .notDownloaded))
        return estado
    }

    private func publicar(_ id: String) async {
        observador?(id, await estado(de: id))
    }
}
