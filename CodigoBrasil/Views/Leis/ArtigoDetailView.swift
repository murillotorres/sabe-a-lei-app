import SwiftUI

/// Tela de um artigo: o caput em destaque e, abaixo, cada parágrafo/inciso/alínea
/// que o complementa exibido em seu próprio card, indentado conforme a hierarquia.
struct ArtigoDetailView: View {
    let artigoId: Int
    /// Dados já conhecidos da listagem, usados para exibir algo enquanto o detalhe carrega.
    var resumo: Artigo?
    /// Livro do artigo. Quem abre pela lista do livro informa (os artigos de lá
    /// não trazem o slug); da busca e dos favoritos sai do próprio artigo.
    var livro: Livro?
    /// Aberto a partir da lista do próprio livro: ir ao livro completo é só voltar.
    var abertoPeloLivro = false
    /// Grifo ou anotação a mostrar ao abrir (vindo de "Minhas anotações").
    var foco: FocoNoArtigo?

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore
    @Environment(FavoritosStore.self) private var favoritosStore
    @Environment(EstudosStore.self) private var estudos

    @State private var artigo: Artigo?
    @State private var blocos: [BlocoDispositivo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    /// Resultado da busca neste artigo — calculado uma vez, depois do atraso
    /// da digitação, e não a cada vez que a tela é redesenhada.
    @State private var busca = ResultadoNoArtigo(consulta: "", blocos: [], sugestao: nil)
    @State private var isTogglingFavorito = false
    @State private var isPresentingAuth = false
    @State private var isMostrandoLivro = false
    /// Textos do artigo com as chaves que ancoram os grifos (montados no load).
    @State private var textosAncoraveis: [TextoAncoravel] = []
    @State private var versaoDoLivro: String?
    @State private var edicao: EdicaoDeNota?
    @State private var comparando: Grifo?
    @State private var pedindoLogin = false
    @State private var destaque: UUID?
    @State private var focoAplicado = false

    private var artigoAtual: Artigo? { artigo ?? resumo }

    private var livroAtual: Livro? { livro ?? Livro.porSlug(artigoAtual?.leiSlug) }

    /// Volta pro livro se veio dele; senão abre o livro por cima.
    private func abrirLivro() {
        if abertoPeloLivro {
            dismiss()
        } else {
            isMostrandoLivro = true
        }
    }

    /// Filtra e reordena os cards por compatibilidade com a busca — mesmo
    /// critério usado na busca geral da Constituição (quantas palavras batem,
    /// priorizando as que aparecem mais próximas umas das outras), só que
    /// aplicado apenas ao conteúdo deste artigo, já carregado localmente. Cada
    /// card é pontuado pelo texto todo (parágrafo/inciso + suas alíneas).
    /// Palavra que não aparece em nenhum card é completada ou corrigida pelo
    /// vocabulário do próprio artigo (`CorrecaoDeBusca`) — a consulta corrigida
    /// vai em `sugestao`.
    private func buscarNoArtigo(_ consulta: String) -> ResultadoNoArtigo {
        var tokens = BuscaTexto.tokenizar(consulta)
        guard !tokens.isEmpty else { return ResultadoNoArtigo(consulta: consulta, blocos: blocos, sugestao: nil) }

        var sugestao: String?
        var alternativas: [String: [String]] = [:]
        let textos = blocos.map { BuscaTexto.normalizar($0.textoCompleto) }
        if let ajuste = CorrecaoDeBusca.ajustarConsulta(
            tokens,
            textos: { [artigoAtual?.caput ?? ""] + blocos.map(\.textoCompleto) },
            aparece: { token in
                guard let regex = BuscaTexto.compilar([token]).first ?? nil else { return true }
                return textos.contains { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
            }
        ) {
            tokens = ajuste.tokens
            alternativas = ajuste.alternativas
            sugestao = ajuste.sugestao
        }

        let regexes = BuscaTexto.compilar(tokens, extras: alternativas)
        let encontrados = zip(blocos, textos)
            .map { ($0, BuscaTexto.pontuarNormalizado($1, tokens: tokens, regexes: regexes)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        return ResultadoNoArtigo(consulta: consulta, blocos: encontrados, sugestao: sugestao)
    }

    /// Espera a digitação parar (`BuscaTexto.atrasoDaDigitacao`) e busca.
    /// Campo vazio volta ao artigo inteiro na hora.
    private func atualizarBusca() async {
        let consulta = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !consulta.isEmpty else {
            busca = ResultadoNoArtigo(consulta: "", blocos: [], sugestao: nil)
            return
        }

        do {
            try await Task.sleep(for: BuscaTexto.atrasoDaDigitacao)
        } catch {
            return
        }
        busca = buscarNoArtigo(consulta)
    }

    /// "Artigo 13", ou "Preâmbulo" no único caso em que o artigo não tem número.
    private var tituloGrande: String {
        guard let numero = artigoAtual?.numero else { return "Artigo" }
        return numero == "Preâmbulo" ? "Preâmbulo" : "Artigo \(numero)"
    }

    private var isFavorito: Bool {
        favoritosStore.estaFavoritado(artigoId: artigoId, dispositivoId: nil)
    }

    /// Menu de ações da barra, no estilo do app Mensagens. Nenhum `.buttonStyle`
    /// de propósito: dentro de um `ToolbarItem` o sistema já desenha o vidro
    /// sozinho (igual ao botão voltar) — só o artigo inteiro pode ser favoritado.
    private var menuDeAcoes: some View {
        Menu {
            if let livroAtual {
                Button(action: abrirLivro) {
                    Label(livroAtual.tituloDoLivroCompleto, systemImage: livroAtual.icone)
                }
            }
            Button {
                exigirLogin { edicao = .geral(nil) }
            } label: {
                Label("Adicionar anotação", systemImage: "note.text.badge.plus")
            }
            Button(action: alternarFavorito) {
                if isFavorito {
                    Label("Remover dos favoritos", systemImage: "star.slash")
                } else {
                    Label("Adicionar aos favoritos", systemImage: "star")
                }
            }
            .disabled(isTogglingFavorito)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Opções do artigo")
    }

    /// Título no centro da barra: "Artigo 2" (com uma estrela discreta se for
    /// favorito) e, embaixo, o livro ("Constituição Federal").
    private var tituloDaBarra: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Text(tituloGrande)
                    .font(.headline)
                if isFavorito {
                    Image(systemName: "star.fill")
                        .imageScale(.small)
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favorito")
                }
            }
            if let nome = livroAtual?.nomeCompleto {
                Text(nome)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func alternarFavorito() {
        // Sem sessão a estrela continua visível — tocar nela convida a entrar.
        guard let token = authStore.token else {
            isPresentingAuth = true
            return
        }
        isTogglingFavorito = true
        Task {
            await favoritosStore.alternar(artigoId: artigoId, dispositivoId: nil, token: token)
            isTogglingFavorito = false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // O subtítulo fica logo abaixo da barra de navegação (onde está o
            // título), centralizado e fixo — não rola junto com o conteúdo.
            if let rubrica = artigoAtual?.rubrica {
                Text(rubrica)
                    .fonteDoLivro(.title3, peso: .bold)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    // Negativo de propósito: a barra de navegação já reserva uma
                    // folga abaixo do título, e somada ao padding normal deixava
                    // um vão grande entre título e subtítulo. Como o padding
                    // negativo encolhe o layout, o conteúdo sobe junto e a
                    // distância até o primeiro card não muda.
                    .padding(.top, -14)
                    .padding(.bottom, 8)
            }

            let resolucao = resolverGrifos()
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let artigoAtual {
                        ArtigoCaputCardView(artigo: artigoAtual, grifos: resolucao.grifos)
                            .id(Self.idDoCaput)
                    }

                    if isLoading && artigo == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else {
                        let buscando = !busca.consulta.isEmpty
                        if buscando && busca.blocos.isEmpty {
                            ContentUnavailableView.search(text: busca.consulta)
                                .padding(.top, 24)
                        } else {
                            if let sugestao = busca.sugestao {
                                SugestaoDeBuscaView(sugestao: sugestao, margem: 4)
                            }
                            ForEach(buscando ? busca.blocos : blocos) { bloco in
                                DispositivoCardView(bloco: bloco, destacado: buscando, grifos: resolucao.grifos)
                                    .id(Self.idDoCard(bloco.id))
                            }
                            if !buscando {
                                secoesDeEstudo(alterados: resolucao.alterados)
                            }
                            if !buscando, let livroAtual {
                                LivroCompletoButton(livro: livroAtual, action: abrirLivro)
                                    .padding(.top, 12)
                            }
                        }
                    }
                }
                .padding()
            }
            .task(id: artigo?.id) { await aplicarFoco(proxy) }
            }
        }
        .background(Color(.systemGroupedBackground))
        // Título nativo, centralizado na barra, na mesma linha do botão voltar.
        .navigationTitle(tituloGrande)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isMostrandoLivro) {
            livroAtual?.destino
        }
        // Sem a barra de tabs nesta tela: o rodapé é da busca.
        .toolbar(.hidden, for: .tabBar)
        // Busca nativa. A partir do iOS 26 o item de busca vai para a barra
        // inferior (Liquid Glass do sistema); antes disso fica no topo.
        .searchable(text: $searchText, prompt: "Buscar neste artigo")
        .naoEsconderBarraNaBusca()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                menuDeAcoes
            }
            // O `navigationTitle` continua valendo pro botão voltar da tela seguinte.
            ToolbarItem(placement: .principal) {
                tituloDaBarra
            }
            if #available(iOS 26.0, *) {
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
        }
        .sheet(isPresented: $isPresentingAuth) {
            AuthView()
        }
        .sheet(isPresented: $pedindoLogin) {
            SalveSeusEstudosView()
        }
        .sheet(item: $edicao) { edicao in
            editorDeNota(edicao)
        }
        .sheet(item: $comparando) { grifo in
            ComparacaoDeTextoView(
                trecho: grifo.trecho, textoAnterior: grifo.textoOriginal,
                textoAtual: textosPorChave[grifo.dispositivoChave]?.texto
            )
        }
        .task { await load() }
        // Refaz quando o texto muda ou quando o artigo termina de carregar.
        .task(id: ChaveDaBusca(texto: searchText, blocos: blocos.count)) {
            await atualizarBusca()
        }
    }

    // MARK: Grifos e anotações

    private static let idDoCaput = "caput"
    private static let idDasAnotacoes = "anotacoes"
    private static func idDoCard(_ blocoId: Int) -> String { "dispositivo-\(blocoId)" }

    /// Antes do detalhe carregar, só o caput (do resumo) é ancorável.
    private var textosPorChave: [String: TextoAncoravel] {
        let lista = textosAncoraveis.isEmpty
            ? Ancoragem.textos(caput: artigoAtual?.caput ?? "", dispositivos: [])
            : textosAncoraveis
        return Dictionary(lista.map { ($0.chave, $0) }, uniquingKeysWith: { primeiro, _ in primeiro })
    }

    private var resumoEstudado: ResumoDoArtigoEstudado? {
        artigoAtual.map { ResumoDoArtigoEstudado($0, leiSlug: livroAtual?.slug) }
    }

    /// Grifar e anotar são só para quem tem conta — sem login, nada é gravado.
    private func exigirLogin(_ acao: () -> Void) {
        guard authStore.isAuthenticated else {
            pedindoLogin = true
            return
        }
        acao()
    }

    /// Localiza cada grifo do artigo no texto atual. Os que não se acham mais
    /// (a lei mudou o trecho) só são apontados depois do artigo completo carregar.
    private func resolverGrifos() -> (grifos: GrifosDoArtigo, alterados: [Grifo]) {
        let textos = textosPorChave
        var marcas: [String: [MarcaNoTexto]] = [:]
        var alterados: [Grifo] = []
        for grifo in estudos.grifos(doArtigo: artigoId) {
            switch Ancoragem.localizar(grifo, em: textos) {
            case .encontrado(let intervalo):
                marcas[grifo.dispositivoChave, default: []].append(MarcaNoTexto(
                    id: grifo.id, intervalo: intervalo, cor: grifo.cor,
                    temNota: estudos.nota(doGrifo: grifo.id) != nil
                ))
            case .alterado:
                if artigo != nil { alterados.append(grifo) }
            }
        }
        let chaves = Dictionary(
            textos.values.compactMap { texto in texto.dispositivoId.map { ($0, texto.chave) } },
            uniquingKeysWith: { primeiro, _ in primeiro }
        )
        let grifos = GrifosDoArtigo(marcas: marcas, chavePorDispositivo: chaves, destaque: destaque) { chave in
            acoes(paraChave: chave)
        }
        return (grifos, alterados)
    }

    private func acoes(paraChave chave: String) -> AcoesDoTexto {
        AcoesDoTexto(
            grifar: { intervalo, cor in
                exigirLogin {
                    guard let alvo = textosPorChave[chave] else { return }
                    estudos.marcar(
                        trecho: intervalo, em: alvo, artigoId: artigoId, cor: cor,
                        versao: versaoDoLivro, artigo: resumoEstudado
                    )
                }
            },
            anotar: { intervalo in
                exigirLogin { edicao = .novoTrecho(chave: chave, intervalo: intervalo) }
            },
            abrirNota: { grifoId in edicao = .grifo(grifoId) },
            alterarCor: { grifoId, cor in estudos.alterarCor(grifoId, para: cor) },
            removerGrifo: { grifoId in estudos.removerGrifo(grifoId) },
            removerNota: { grifoId in
                if let nota = estudos.nota(doGrifo: grifoId) { estudos.removerNota(nota.id) }
            }
        )
    }

    @ViewBuilder
    private func editorDeNota(_ edicao: EdicaoDeNota) -> some View {
        switch edicao {
        case .novoTrecho(let chave, let intervalo):
            let alvo = textosPorChave[chave]
            NotaEditorView(
                titulo: "Nova nota",
                trecho: alvo.map { ($0.texto as NSString).substring(with: intervalo) }
            ) { texto in
                guard let alvo, !texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                let grifo = estudos.marcar(
                    trecho: intervalo, em: alvo, artigoId: artigoId, cor: nil,
                    versao: versaoDoLivro, artigo: resumoEstudado
                )
                estudos.salvarNota(texto, notaId: nil, grifoId: grifo.id, artigoId: artigoId, artigo: resumoEstudado)
            }
        case .grifo(let grifoId):
            let nota = estudos.nota(doGrifo: grifoId)
            NotaEditorView(
                titulo: nota == nil ? "Nova nota" : "Nota",
                trecho: estudos.grifos[grifoId]?.trecho,
                textoInicial: nota?.conteudo ?? "",
                excluir: nota.map { nota in { estudos.removerNota(nota.id) } }
            ) { texto in
                estudos.salvarNota(texto, notaId: nota?.id, grifoId: grifoId, artigoId: artigoId, artigo: resumoEstudado)
            }
        case .geral(let notaId):
            let nota = notaId.flatMap { estudos.anotacoes[$0] }
            NotaEditorView(
                titulo: "\(resumoEstudado?.titulo ?? tituloGrande)",
                textoInicial: nota?.conteudo ?? "",
                excluir: nota.map { nota in { estudos.removerNota(nota.id) } }
            ) { texto in
                estudos.salvarNota(texto, notaId: nota?.id, grifoId: nil, artigoId: artigoId, artigo: resumoEstudado)
            }
        }
    }

    /// Fim do artigo: as anotações do artigo inteiro e os grifos cujo trecho
    /// mudou numa atualização da lei. Nada aparece se não houver nenhum.
    @ViewBuilder
    private func secoesDeEstudo(alterados: [Grifo]) -> some View {
        let gerais = estudos.anotacoesGerais(doArtigo: artigoId)
        if !gerais.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(gerais) { nota in
                    Button {
                        edicao = .geral(nota.id)
                    } label: {
                        AnotacaoGeralCardView(nota: nota)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 12)
            .id(Self.idDasAnotacoes)
        }
        ForEach(alterados) { grifo in
            TrechoAlteradoCardView(
                grifo: grifo,
                nota: estudos.nota(doGrifo: grifo.id),
                comparar: { comparando = grifo },
                abrirNota: { edicao = .grifo(grifo.id) },
                remover: { estudos.excluirGrifo(grifo.id) }
            )
            .id(grifo.id.uuidString)
        }
    }

    /// Chegando de "Minhas anotações": rola até o trecho e o destaca por um instante.
    private func aplicarFoco(_ proxy: ScrollViewProxy) async {
        guard let foco, !focoAplicado, artigo != nil else { return }
        focoAplicado = true

        var alvo: String?
        var grifoId: UUID?
        switch foco {
        case .grifo(let id):
            grifoId = id
        case .anotacao(let id):
            if let nota = estudos.anotacoes[id] {
                if let id = nota.grifoId { grifoId = id } else { alvo = Self.idDasAnotacoes }
            }
        }
        if let grifoId, let grifo = estudos.grifos[grifoId] {
            switch Ancoragem.localizar(grifo, em: textosPorChave) {
            case .encontrado:
                alvo = idDoCard(chave: grifo.dispositivoChave)
                destaque = grifoId
            case .alterado:
                alvo = grifoId.uuidString
            }
        }
        guard let alvo else { return }

        // Espera os cards aparecerem antes de rolar.
        try? await Task.sleep(for: .milliseconds(300))
        withAnimation { proxy.scrollTo(alvo, anchor: .center) }
        try? await Task.sleep(for: .seconds(2.5))
        withAnimation { destaque = nil }
    }

    /// Card onde está o texto da chave (alíneas ficam dentro do card do inciso/parágrafo).
    private func idDoCard(chave: String) -> String {
        guard let dispositivoId = textosPorChave[chave]?.dispositivoId else { return Self.idDoCaput }
        let bloco = blocos.first { bloco in
            bloco.principal.id == dispositivoId || bloco.subitens.contains { $0.id == dispositivoId }
        }
        return bloco.map { Self.idDoCard($0.id) } ?? Self.idDoCaput
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await RepositorioDeLivros.detalhe(artigoId: artigoId)
            artigo = response.artigo
            blocos = BlocoDispositivo.agrupar(response.dispositivos)
            textosAncoraveis = Ancoragem.textos(caput: response.artigo.caput, dispositivos: response.dispositivos)
            if let slug = livroAtual?.slug {
                versaoDoLivro = await LocalBookStore.shared.resumo(slug)?.versao
            }
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Não foi possível completar a solicitação."
        }
    }
}

private struct ArtigoCaputCardView: View {
    let artigo: Artigo
    var grifos = GrifosDoArtigo()

    var body: some View {
        // Sem o "Art. N" aqui: o número já é o título da barra de navegação.
        VStack(alignment: .leading, spacing: 8) {
            if artigo.revogado {
                SeloRevogadoView()
            }
            grifos.texto(artigo.caput, chave: Ancoragem.chaveDoCaput, estilo: .body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Um card da tela do artigo: um parágrafo ou inciso e, dentro dele, as
/// alíneas (e itens) que o detalham — esses não ganham card próprio.
struct BlocoDispositivo: Identifiable, Equatable {
    let principal: ArtigoDispositivo
    private(set) var subitens: [ArtigoDispositivo]

    var id: Int { principal.id }

    /// Todo o texto que o card mostra — é sobre ele que a busca pontua.
    var textoCompleto: String {
        ([principal.texto] + subitens.map(\.texto)).joined(separator: " ")
    }

    /// Agrupa os dispositivos (já em ordem de leitura): cada parágrafo ou inciso
    /// abre um card, e o que vem depois dele (alíneas, itens) entra nesse card.
    static func agrupar(_ dispositivos: [ArtigoDispositivo]) -> [BlocoDispositivo] {
        var blocos: [BlocoDispositivo] = []
        for dispositivo in dispositivos {
            let abreCard = dispositivo.tipo == "paragrafo" || dispositivo.tipo == "inciso"
            if !abreCard, !blocos.isEmpty {
                blocos[blocos.count - 1].subitens.append(dispositivo)
            } else {
                blocos.append(BlocoDispositivo(principal: dispositivo, subitens: []))
            }
        }
        return blocos
    }
}

/// Card de parágrafo/inciso: o tipo em letras pequenas com a bolinha do número
/// logo abaixo, à esquerda; o texto à direita, seguido da lista de alíneas
/// (bolinhas amarelas) quando houver. Indentado conforme o nível de aninhamento.
struct DispositivoCardView: View {
    let bloco: BlocoDispositivo
    /// true quando este card é resultado de uma busca dentro do artigo — pinta
    /// o fundo de amarelo, no mesmo estilo do trecho destacado na busca geral.
    var destacado: Bool = false
    var grifos = GrifosDoArtigo()

    /// 9 pt no tamanho de texto padrão; continua acompanhando o Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var fonteDoTipo: CGFloat = 9

    private var dispositivo: ArtigoDispositivo { bloco.principal }

    /// Rótulo pequeno do tipo do dispositivo ("PARÁGRAFO", "INCISO").
    private func cabecalho(_ texto: String, linhas: Int = 1) -> some View {
        Text(texto)
            .font(.system(size: fonteDoTipo, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .multilineTextAlignment(.center)
            .lineLimit(linhas)
            .minimumScaleFactor(0.7)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                if dispositivo.ehParagrafoUnico {
                    // Sem número pra mostrar: só o rótulo, em duas linhas, sem bolinha.
                    cabecalho("Parágrafo\núnico", linhas: 2)
                } else {
                    if let tipo = dispositivo.nomeDoTipo {
                        cabecalho(tipo)
                    }
                    MarcadorView(
                        texto: dispositivo.rotuloCompacto,
                        cor: dispositivo.cor,
                        corDoTexto: dispositivo.corDoTexto
                    )
                }
            }
            .frame(width: 60)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    grifos.texto(dispositivo.texto, chave: grifos.chavePorDispositivo[dispositivo.id], estilo: .subheadline)
                    if dispositivo.revogado {
                        SeloRevogadoView()
                    }
                }

                ForEach(bloco.subitens) { subitem in
                    SubitemView(subitem: subitem, nivelDoCard: dispositivo.nivel, grifos: grifos)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            destacado ? Color.yellow.opacity(0.25) : Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(destacado ? Color.yellow.opacity(0.5) : .clear, lineWidth: 1)
        )
        .padding(.leading, CGFloat(max(0, dispositivo.nivel - 1)) * 20)
        .opacity(dispositivo.revogado ? 0.6 : 1)
    }
}

/// Uma alínea (ou item) dentro do card do parágrafo/inciso: bolinha com a letra
/// e o texto ao lado, em formato de lista.
private struct SubitemView: View {
    let subitem: ArtigoDispositivo
    /// Nível do parágrafo/inciso dono do card — itens mais fundos que as alíneas
    /// (filhos delas) ganham um recuo a mais.
    let nivelDoCard: Int
    var grifos = GrifosDoArtigo()

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            MarcadorView(
                texto: subitem.rotuloCompacto,
                cor: subitem.cor,
                corDoTexto: subitem.corDoTexto,
                lado: 26,
                fonte: .caption2.bold()
            )
            VStack(alignment: .leading, spacing: 4) {
                grifos.texto(subitem.texto, chave: grifos.chavePorDispositivo[subitem.id], estilo: .subheadline)
                if subitem.revogado {
                    SeloRevogadoView()
                }
            }
            .padding(.top, 3)
        }
        .padding(.leading, CGFloat(max(0, subitem.nivel - nivelDoCard - 1)) * 16)
        .opacity(subitem.revogado ? 0.6 : 1)
    }
}

/// Bolinha com o rótulo do dispositivo (§ 1º, I, a...). Quando o texto é mais
/// largo que um círculo (números romanos longos, "Único"), estica em pílula.
private struct MarcadorView: View {
    let texto: String
    let cor: Color
    var corDoTexto: Color = .white
    var lado: CGFloat = 36
    var fonte: Font = .caption.bold()

    var body: some View {
        Text(texto)
            .font(fonte)
            .foregroundStyle(corDoTexto)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .frame(minWidth: lado, minHeight: lado)
            .background(cor, in: Capsule())
    }
}

/// Fim do artigo: leva ao livro inteiro ("Constituição Completa").
private struct LivroCompletoButton: View {
    let livro: Livro
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: livro.icone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(livro.cor, in: RoundedRectangle(cornerRadius: 8))
                Text(livro.tituloDoLivroCompleto)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct SeloRevogadoView: View {
    var body: some View {
        Text("Revogado")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red.opacity(0.15), in: Capsule())
            .foregroundStyle(.red)
    }
}

private extension ArtigoDispositivo {
    /// Cabeçalho pequeno acima da bolinha. Alíneas e itens não têm: ficam
    /// dentro do card do parágrafo/inciso, só com a bolinha.
    var nomeDoTipo: String? {
        switch tipo {
        case "paragrafo": return "Parágrafo"
        case "inciso": return "Inciso"
        default: return nil
        }
    }

    /// "Parágrafo único" não tem número: o card mostra só o rótulo, sem bolinha.
    var ehParagrafoUnico: Bool {
        tipo == "paragrafo"
            && rotulo.range(of: "único", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// O que vai dentro da bolinha: "Parágrafo 1º" perde o "Parágrafo " (o
    /// cabeçalho acima já diz) e "a)" vira "a".
    var rotuloCompacto: String {
        var rotulo = self.rotulo
        if tipo == "paragrafo",
           let prefixo = rotulo.range(of: "parágrafo ", options: [.anchored, .caseInsensitive, .diacriticInsensitive]) {
            rotulo.removeSubrange(rotulo.startIndex..<prefixo.upperBound)
            rotulo = rotulo.prefix(1).uppercased() + rotulo.dropFirst()
        }
        if tipo == "alinea", rotulo.hasSuffix(")") {
            rotulo.removeLast()
        }
        return rotulo
    }

    var cor: Color {
        switch tipo {
        case "paragrafo": return .blue
        case "inciso": return .teal
        case "alinea": return .yellow
        default: return .secondary
        }
    }

    /// Texto branco em cima do amarelo não tem contraste — só ele muda.
    var corDoTexto: Color {
        tipo == "alinea" ? .black : .white
    }
}

private extension View {
    /// Por padrão o sistema esconde a barra de navegação inteira (botão voltar e
    /// título) quando a busca ganha foco. Isso mantém o cabeçalho na tela.
    /// Só existe a partir do iOS 17.1.
    @ViewBuilder
    func naoEsconderBarraNaBusca() -> some View {
        if #available(iOS 17.1, *) {
            self.searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            self
        }
    }
}

#Preview {
    NavigationStack {
        ArtigoDetailView(
            artigoId: 6,
            resumo: Artigo(
                id: 6, parte: "permanente", numero: "5",
                tituloEstrutural: "Título II", capituloEstrutural: "Capítulo I",
                secaoEstrutural: nil, subsecaoEstrutural: nil,
                descricaoEstrutural: "Do crime", rubrica: "Relação de causalidade",
                caput: "Todos são iguais perante a lei...",
                revogado: false, ordem: 5, leiSlug: nil, leiTitulo: nil,
                trechoCorrespondente: nil
            )
        )
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
    .environment(EstudosStore())
}

/// Resultado de uma busca dentro do artigo.
private struct ResultadoNoArtigo {
    let consulta: String
    let blocos: [BlocoDispositivo]
    let sugestao: String?
}

private struct ChaveDaBusca: Equatable {
    let texto: String
    let blocos: Int
}

/// Grifo ou anotação a mostrar quando o artigo abre.
enum FocoNoArtigo: Hashable {
    case grifo(UUID)
    case anotacao(UUID)
}

/// Qual nota está sendo escrita/editada.
private enum EdicaoDeNota: Identifiable {
    /// Nota num trecho ainda sem marca: o trecho (sem cor) nasce ao salvar.
    case novoTrecho(chave: String, intervalo: NSRange)
    /// Nota (nova ou existente) de um trecho já marcado.
    case grifo(UUID)
    /// Anotação do artigo inteiro; nil = nova.
    case geral(UUID?)

    var id: String {
        switch self {
        case .novoTrecho(let chave, let intervalo): "trecho-\(chave)-\(intervalo.location)-\(intervalo.length)"
        case .grifo(let id): "grifo-\(id)"
        case .geral(let id): "geral-\(id?.uuidString ?? "nova")"
        }
    }
}

/// O que os cards precisam para desenhar e editar os grifos.
struct GrifosDoArtigo {
    var marcas: [String: [MarcaNoTexto]] = [:]
    /// Chave de ancoragem de cada dispositivo (ver `Ancoragem`).
    var chavePorDispositivo: [Int: String] = [:]
    var destaque: UUID?
    var acoes: ((String) -> AcoesDoTexto)?

    /// Texto grifável de um dispositivo. Sem chave (artigo ainda carregando),
    /// o texto aparece sem ações.
    @MainActor
    func texto(_ texto: String, chave: String?, estilo: UIFont.TextStyle) -> some View {
        TextoGrifavel(
            texto: texto, estilo: estilo,
            marcas: chave.flatMap { marcas[$0] } ?? [],
            destaque: destaque,
            acoes: chave.flatMap { chave in acoes?(chave) }
        )
    }
}

/// Anotação do artigo inteiro, no fim do artigo. Tocar abre para editar.
private struct AnotacaoGeralCardView: View {
    let nota: Anotacao

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Minha anotação", systemImage: "note.text")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            Text(nota.conteudo)
                .fonteDoLivro(.subheadline)
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Um grifo cujo trecho a lei alterou. Não é movido sozinho para outro texto:
/// fica aqui, com o aviso, até o usuário comparar e decidir.
private struct TrechoAlteradoCardView: View {
    let grifo: Grifo
    let nota: Anotacao?
    let comparar: () -> Void
    let abrirNota: () -> Void
    let remover: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Este trecho foi alterado desde que você fez esta anotação.", systemImage: "exclamationmark.triangle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.orange)
            HStack(alignment: .top, spacing: 8) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(grifo.cor?.cor ?? Color.secondary)
                    .frame(width: 4)
                Text("“\(grifo.trecho)”")
                    .fonteDoLivro(.subheadline)
                    .foregroundStyle(.secondary)
                    .strikethrough()
            }
            .fixedSize(horizontal: false, vertical: true)
            if let nota {
                Text("Minha nota: \(nota.conteudo)")
                    .font(.subheadline)
            }
            HStack(spacing: 16) {
                Button("Texto anterior e atual", action: comparar)
                if nota != nil {
                    Button("Ver nota", action: abrirNota)
                }
                Spacer()
                Button("Remover", role: .destructive, action: remover)
            }
            .font(.subheadline)
            .buttonStyle(.borderless)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}
