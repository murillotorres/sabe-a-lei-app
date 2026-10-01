import Foundation
import Network
import Observation

/// Grifos e anotações do usuário logado.
///
/// Tudo é gravado primeiro no aparelho (um arquivo por usuário em
/// `Application Support/Estudos/`) e entra numa fila de pendências; a fila é
/// enviada ao servidor assim que possível — logo depois de cada alteração, ao
/// voltar a internet e ao abrir o app. Sem conexão, nada se perde: as
/// alterações continuam pendentes no arquivo, inclusive depois do logout (o
/// usuário é avisado antes de sair).
///
/// Os ids são UUIDs gerados aqui, então reenviar uma alteração nunca duplica.
@MainActor
@Observable
final class EstudosStore {
    /// Inclui os excluídos ainda não enviados (`excluido == true`) — as
    /// consultas abaixo já os ignoram.
    private(set) var grifos: [UUID: Grifo] = [:]
    private(set) var anotacoes: [UUID: Anotacao] = [:]
    private(set) var sincronizando = false
    /// A última sincronização falhou (sem internet, servidor indisponível...).
    private(set) var ultimaFalhou = false

    private var pendentesGrifos: Set<UUID> = []
    private var pendentesAnotacoes: Set<UUID> = []
    private var revisao = 0
    private var usuarioId: Int?
    private var token: String?
    private var precisaDeOutra = false
    private var sincronizacaoAgendada: Task<Void, Never>?
    private let monitorDeRede = NWPathMonitor()

    /// Quantos registros ainda não chegaram ao servidor.
    var quantidadeDePendencias: Int { pendentesGrifos.count + pendentesAnotacoes.count }

    init() {
        monitorDeRede.pathUpdateHandler = { [weak self] caminho in
            guard caminho.status == .satisfied else { return }
            Task { @MainActor in
                guard let self, self.quantidadeDePendencias > 0 else { return }
                await self.sincronizar()
            }
        }
        monitorDeRede.start(queue: DispatchQueue(label: "EstudosStore.rede"))
    }

    // MARK: Consultas

    var grifosAtivos: [Grifo] { grifos.values.filter { !$0.excluido } }
    var anotacoesAtivas: [Anotacao] { anotacoes.values.filter { !$0.excluido } }

    func grifos(doArtigo artigoId: Int) -> [Grifo] {
        grifosAtivos.filter { $0.artigoId == artigoId }.sorted { $0.criadoEm < $1.criadoEm }
    }

    /// Anotações do artigo inteiro (sem trecho), da mais antiga para a mais nova.
    func anotacoesGerais(doArtigo artigoId: Int) -> [Anotacao] {
        anotacoesAtivas.filter { $0.artigoId == artigoId && $0.grifoId == nil }.sorted { $0.criadoEm < $1.criadoEm }
    }

    /// A nota de um trecho. Se dois aparelhos criaram uma cada offline, vale a mais recente.
    func nota(doGrifo grifoId: UUID) -> Anotacao? {
        anotacoesAtivas.filter { $0.grifoId == grifoId }.max { $0.alteradoEm < $1.alteradoEm }
    }

    // MARK: Sessão

    /// Carrega a cópia local do usuário (na hora, sem rede) e dispara a
    /// sincronização sem esperar por ela — sem conexão, ela pode levar minutos.
    func entrar(usuarioId: Int, token: String) {
        if self.usuarioId != usuarioId {
            limparMemoria()
            self.usuarioId = usuarioId
            carregarDoDisco()
        }
        self.token = token
        Task { await sincronizar() }
    }

    /// Logout: some da memória, mas o arquivo fica — pendências incluídas — e
    /// volta quando o mesmo usuário entrar de novo.
    func sair() {
        sincronizacaoAgendada?.cancel()
        limparMemoria()
        usuarioId = nil
        token = nil
    }

    func aoFicarAtivo() {
        guard token != nil else { return }
        Task { await sincronizar() }
    }

    private func limparMemoria() {
        grifos = [:]
        anotacoes = [:]
        pendentesGrifos = []
        pendentesAnotacoes = []
        revisao = 0
        ultimaFalhou = false
    }

    // MARK: Alterações

    /// Grifa (ou, sem cor, só marca para uma nota) um trecho de um dispositivo.
    @discardableResult
    func marcar(
        trecho intervalo: NSRange, em alvo: TextoAncoravel, artigoId: Int,
        cor: CorDoGrifo?, versao: String?, artigo: ResumoDoArtigoEstudado?
    ) -> Grifo {
        let ns = alvo.texto as NSString
        let (prefixo, sufixo) = Ancoragem.contexto(de: intervalo, em: alvo.texto)
        let agora = Date()
        let grifo = Grifo(
            id: UUID(), artigoId: artigoId, dispositivoId: alvo.dispositivoId,
            dispositivoChave: alvo.chave, dispositivoOrdem: alvo.ordem,
            trecho: ns.substring(with: intervalo), prefixo: prefixo, sufixo: sufixo,
            inicio: intervalo.location, fim: NSMaxRange(intervalo), textoOriginal: alvo.texto,
            cor: cor, versao: versao, criadoEm: agora, alteradoEm: agora, excluido: false, artigo: artigo
        )
        gravar(grifo)
        return grifo
    }

    func alterarCor(_ grifoId: UUID, para cor: CorDoGrifo) {
        guard var grifo = grifos[grifoId], !grifo.excluido else { return }
        grifo.cor = cor
        grifo.alteradoEm = Date()
        gravar(grifo)
    }

    /// Tira o grifo. Se o trecho tem nota, ele continua sublinhado com a nota;
    /// senão, deixa de existir.
    func removerGrifo(_ grifoId: UUID) {
        guard var grifo = grifos[grifoId], !grifo.excluido else { return }
        if nota(doGrifo: grifoId) != nil {
            grifo.cor = nil
            grifo.alteradoEm = Date()
            gravar(grifo)
        } else {
            excluirGrifo(grifoId)
        }
    }

    /// Exclui o trecho e as notas dele.
    func excluirGrifo(_ grifoId: UUID) {
        guard var grifo = grifos[grifoId] else { return }
        let agora = Date()
        grifo.excluido = true
        grifo.alteradoEm = agora
        gravar(grifo, salvarAgora: false)
        for var nota in anotacoesAtivas where nota.grifoId == grifoId {
            nota.excluido = true
            nota.alteradoEm = agora
            gravar(nota, salvarAgora: false)
        }
        salvarNoDisco()
    }

    /// Cria ou atualiza uma anotação. Texto vazio apaga a anotação existente.
    func salvarNota(
        _ conteudo: String, notaId: UUID?, grifoId: UUID?, artigoId: Int, artigo: ResumoDoArtigoEstudado?
    ) {
        let texto = conteudo.trimmingCharacters(in: .whitespacesAndNewlines)
        if let notaId, var existente = anotacoes[notaId], !existente.excluido {
            guard !texto.isEmpty else { return removerNota(notaId) }
            guard existente.conteudo != texto else { return }
            existente.conteudo = texto
            existente.alteradoEm = Date()
            if existente.artigo == nil { existente.artigo = artigo }
            gravar(existente)
            return
        }
        guard !texto.isEmpty else { return }
        let agora = Date()
        gravar(Anotacao(
            id: UUID(), artigoId: artigoId, grifoId: grifoId, conteudo: texto,
            criadoEm: agora, alteradoEm: agora, excluido: false, artigo: artigo
        ))
    }

    /// Apaga a nota. Um trecho sem cor existia só por causa dela e sai junto.
    func removerNota(_ notaId: UUID) {
        guard var nota = anotacoes[notaId], !nota.excluido else { return }
        nota.excluido = true
        nota.alteradoEm = Date()
        gravar(nota)
        if let grifoId = nota.grifoId, let grifo = grifos[grifoId], !grifo.excluido,
           grifo.cor == nil, self.nota(doGrifo: grifoId) == nil {
            excluirGrifo(grifoId)
        }
    }

    private func gravar(_ grifo: Grifo, salvarAgora: Bool = true) {
        grifos[grifo.id] = grifo
        pendentesGrifos.insert(grifo.id)
        if salvarAgora { salvarNoDisco() }
        agendarSincronizacao()
    }

    private func gravar(_ nota: Anotacao, salvarAgora: Bool = true) {
        anotacoes[nota.id] = nota
        pendentesAnotacoes.insert(nota.id)
        if salvarAgora { salvarNoDisco() }
        agendarSincronizacao()
    }

    // MARK: Sincronização

    /// Junta alterações seguidas (trocar de cor várias vezes) num envio só.
    private func agendarSincronizacao() {
        sincronizacaoAgendada?.cancel()
        sincronizacaoAgendada = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await sincronizar()
        }
    }

    private static let tamanhoDoLote = 200

    func sincronizar() async {
        guard let token, let usuarioId else { return }
        if sincronizando {
            precisaDeOutra = true
            return
        }
        sincronizando = true
        defer { sincronizando = false }

        repeat {
            precisaDeOutra = false
            do {
                // Em lotes; cada resposta também traz o que mudou no servidor.
                repeat {
                    let loteGrifos = Array(pendentesGrifos.prefix(Self.tamanhoDoLote)).compactMap { grifos[$0] }
                    let loteNotas = Array(pendentesAnotacoes.prefix(Self.tamanhoDoLote)).compactMap { anotacoes[$0] }
                    let corpo = SincronizacaoDeEstudos(desde: revisao, grifos: loteGrifos, anotacoes: loteNotas)
                    let resposta = try await EstudosService.sincronizar(corpo, token: token)
                    // Logout ou troca de conta durante a requisição: descarta.
                    guard self.usuarioId == usuarioId else { return }
                    aplicar(resposta, enviadosGrifos: loteGrifos, enviadasNotas: loteNotas)
                    if loteGrifos.isEmpty && loteNotas.isEmpty { break }
                } while quantidadeDePendencias > 0
                ultimaFalhou = false
            } catch {
                // Sem internet, 503 (migration ainda não aplicada), sessão expirada:
                // as pendências continuam no arquivo e vão na próxima tentativa.
                ultimaFalhou = true
                return
            }
        } while precisaDeOutra
    }

    private func aplicar(_ resposta: RespostaDaSincronizacao, enviadosGrifos: [Grifo], enviadasNotas: [Anotacao]) {
        let versaoEnviadaG = Dictionary(enviadosGrifos.map { ($0.id, $0.alteradoEm) }, uniquingKeysWith: { a, _ in a })
        let versaoEnviadaN = Dictionary(enviadasNotas.map { ($0.id, $0.alteradoEm) }, uniquingKeysWith: { a, _ in a })

        // Enviado e não alterado de novo durante a requisição: deixa de estar pendente.
        for (id, data) in versaoEnviadaG where grifos[id]?.alteradoEm == data { pendentesGrifos.remove(id) }
        for (id, data) in versaoEnviadaN where anotacoes[id]?.alteradoEm == data { pendentesAnotacoes.remove(id) }

        // Rejeitado pelo servidor (artigo inexistente, dado inválido): nunca vai sincronizar.
        let rejeitados = Set(resposta.rejeitados.compactMap { UUID(uuidString: $0) })
        for id in rejeitados {
            pendentesGrifos.remove(id)
            pendentesAnotacoes.remove(id)
            grifos[id] = nil
            anotacoes[id] = nil
        }

        if resposta.completo {
            let vindosG = Set(resposta.grifos.map(\.id))
            let vindasN = Set(resposta.anotacoes.map(\.id))
            grifos = grifos.filter { vindosG.contains($0.key) || pendentesGrifos.contains($0.key) }
            anotacoes = anotacoes.filter { vindasN.contains($0.key) || pendentesAnotacoes.contains($0.key) }
        }

        // O que veio do servidor substitui a cópia local — a não ser que a local
        // tenha uma alteração ainda não enviada.
        for var grifo in resposta.grifos where !pendentesGrifos.contains(grifo.id) {
            if grifo.excluido {
                grifos[grifo.id] = nil
            } else {
                if grifo.artigo == nil { grifo.artigo = grifos[grifo.id]?.artigo }
                grifos[grifo.id] = grifo
            }
        }
        for var nota in resposta.anotacoes where !pendentesAnotacoes.contains(nota.id) {
            if nota.excluido {
                anotacoes[nota.id] = nil
            } else {
                if nota.artigo == nil { nota.artigo = anotacoes[nota.id]?.artigo }
                anotacoes[nota.id] = nota
            }
        }

        // Excluídos já confirmados não precisam mais ficar guardados.
        grifos = grifos.filter { !$0.value.excluido || pendentesGrifos.contains($0.key) }
        anotacoes = anotacoes.filter { !$0.value.excluido || pendentesAnotacoes.contains($0.key) }

        revisao = resposta.revisao
        salvarNoDisco()
    }

    // MARK: Disco

    private struct Arquivo: Codable {
        var revisao: Int
        var grifos: [Grifo]
        var anotacoes: [Anotacao]
        var pendentesGrifos: [UUID]
        var pendentesAnotacoes: [UUID]
    }

    private static let diretorio = URL.applicationSupportDirectory.appending(path: "Estudos", directoryHint: .isDirectory)

    private var urlDoArquivo: URL? {
        usuarioId.map { Self.diretorio.appending(path: "usuario-\($0).json") }
    }

    /// Os mesmos da API: as datas precisam manter os milissegundos, que decidem conflitos.
    private static var encoder: JSONEncoder { EstudosService.codificador }
    private static var decoder: JSONDecoder { EstudosService.decodificador }

    private func carregarDoDisco() {
        guard let url = urlDoArquivo, let dados = try? Data(contentsOf: url),
              let arquivo = try? Self.decoder.decode(Arquivo.self, from: dados) else { return }
        revisao = arquivo.revisao
        grifos = Dictionary(arquivo.grifos.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        anotacoes = Dictionary(arquivo.anotacoes.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        pendentesGrifos = Set(arquivo.pendentesGrifos)
        pendentesAnotacoes = Set(arquivo.pendentesAnotacoes)
    }

    /// Escrita atômica: ou fica o arquivo novo inteiro, ou o anterior.
    private func salvarNoDisco() {
        guard let url = urlDoArquivo else { return }
        let arquivo = Arquivo(
            revisao: revisao, grifos: Array(grifos.values), anotacoes: Array(anotacoes.values),
            pendentesGrifos: Array(pendentesGrifos), pendentesAnotacoes: Array(pendentesAnotacoes)
        )
        do {
            try FileManager.default.createDirectory(at: Self.diretorio, withIntermediateDirectories: true)
            try Self.encoder.encode(arquivo).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            ultimaFalhou = true
        }
    }
}
