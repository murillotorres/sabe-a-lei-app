import SwiftUI

/// Tela de um artigo: o caput em destaque e, abaixo, cada parágrafo/inciso/alínea
/// que o complementa exibido em seu próprio card, indentado conforme a hierarquia.
struct ArtigoDetailView: View {
    let artigoId: Int
    /// Dados já conhecidos da listagem, usados para exibir algo enquanto o detalhe carrega.
    var resumo: Artigo?

    @Environment(AuthStore.self) private var authStore
    @Environment(FavoritosStore.self) private var favoritosStore

    @State private var artigo: Artigo?
    @State private var blocos: [BlocoDispositivo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isTogglingFavorito = false

    private var artigoAtual: Artigo? { artigo ?? resumo }

    /// Filtra e reordena os cards por compatibilidade com a busca — mesmo
    /// critério usado na busca geral da Constituição (quantas palavras batem,
    /// priorizando as que aparecem mais próximas umas das outras), só que
    /// aplicado apenas ao conteúdo deste artigo, já carregado localmente. Cada
    /// card é pontuado pelo texto todo (parágrafo/inciso + suas alíneas).
    private var blocosFiltrados: [BlocoDispositivo] {
        guard !searchText.isEmpty else { return blocos }

        let tokens = BuscaTexto.tokenizar(searchText)
        guard !tokens.isEmpty else { return blocos }

        return blocos
            .map { ($0, BuscaTexto.pontuar($0.textoCompleto, tokens: tokens)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    /// "Artigo 13", ou "Preâmbulo" no único caso em que o artigo não tem número.
    private var tituloGrande: String {
        guard let numero = artigoAtual?.numero else { return "Artigo" }
        return numero == "Preâmbulo" ? "Preâmbulo" : "Artigo \(numero)"
    }

    private var isFavorito: Bool {
        favoritosStore.estaFavoritado(artigoId: artigoId, dispositivoId: nil)
    }

    /// Estrela da barra de navegação. Nenhum `.buttonStyle` de propósito: dentro
    /// de um `ToolbarItem` o sistema já desenha o vidro sozinho (igual ao botão
    /// voltar) — só o artigo inteiro pode ser favoritado.
    private var botaoFavorito: some View {
        Button(action: alternarFavorito) {
            Image(systemName: isFavorito ? "star.fill" : "star")
                .foregroundStyle(isFavorito ? .yellow : .primary)
        }
        .disabled(isTogglingFavorito)
        .accessibilityLabel(isFavorito ? "Remover dos favoritos" : "Favoritar")
    }

    private func alternarFavorito() {
        guard let token = authStore.token else { return }
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
                    .font(.title3.bold())
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

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let artigoAtual {
                        ArtigoCaputCardView(artigo: artigoAtual)
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
                    } else if !searchText.isEmpty && blocosFiltrados.isEmpty {
                        ContentUnavailableView.search(text: searchText)
                            .padding(.top, 24)
                    } else {
                        ForEach(blocosFiltrados) { bloco in
                            DispositivoCardView(bloco: bloco, destacado: !searchText.isEmpty)
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        // Título nativo, centralizado na barra, na mesma linha do botão voltar.
        .navigationTitle(tituloGrande)
        .navigationBarTitleDisplayMode(.inline)
        // Sem a barra de tabs nesta tela: o rodapé é da busca.
        .toolbar(.hidden, for: .tabBar)
        // Busca nativa. A partir do iOS 26 o item de busca vai para a barra
        // inferior (Liquid Glass do sistema); antes disso fica no topo.
        .searchable(text: $searchText, prompt: "Buscar neste artigo")
        .naoEsconderBarraNaBusca()
        .toolbar {
            if authStore.isAuthenticated {
                ToolbarItem(placement: .topBarTrailing) {
                    botaoFavorito
                }
            }
            if #available(iOS 26.0, *) {
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await LeisService.artigo(id: artigoId)
            artigo = response.artigo
            blocos = BlocoDispositivo.agrupar(response.dispositivos)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Não foi possível completar a solicitação."
        }
    }
}

private struct ArtigoCaputCardView: View {
    let artigo: Artigo

    var body: some View {
        // Sem o "Art. N" aqui: o número já é o título da barra de navegação.
        VStack(alignment: .leading, spacing: 8) {
            if artigo.revogado {
                SeloRevogadoView()
            }
            Text(artigo.caput)
                .font(.body)
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

    /// 9 pt no tamanho de texto padrão; continua acompanhando o Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var fonteDoTipo: CGFloat = 9

    private var dispositivo: ArtigoDispositivo { bloco.principal }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                if let tipo = dispositivo.nomeDoTipo {
                    Text(tipo)
                        .font(.system(size: fonteDoTipo, weight: .bold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                MarcadorView(
                    texto: dispositivo.rotuloCompacto,
                    cor: dispositivo.cor,
                    corDoTexto: dispositivo.corDoTexto
                )
            }
            .frame(width: 60)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dispositivo.texto)
                        .font(.subheadline)
                    if dispositivo.revogado {
                        SeloRevogadoView()
                    }
                }

                ForEach(bloco.subitens) { subitem in
                    SubitemView(subitem: subitem, nivelDoCard: dispositivo.nivel)
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
                Text(subitem.texto)
                    .font(.subheadline)
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

    /// O que vai dentro da bolinha: "Parágrafo único" vira "Único" (o
    /// cabeçalho acima já diz "Parágrafo") e "a)" vira "a".
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

/// Pontuação de compatibilidade de um texto com as palavras buscadas — mesma
/// lógica usada no backend para a busca geral da Constituição (ver
/// `Artigo::pontuar` na API), reaproveitada aqui em Swift porque os
/// dispositivos do artigo já estão todos carregados no dispositivo do usuário.
private enum BuscaTexto {
    static func normalizar(_ texto: String) -> String {
        texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    static func tokenizar(_ consulta: String) -> [String] {
        let normalizado = normalizar(consulta).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizado.isEmpty else { return [] }

        var vistos = Set<String>()
        return normalizado
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { vistos.insert($0).inserted }
    }

    static func pontuar(_ texto: String, tokens: [String]) -> Int {
        guard !tokens.isEmpty else { return 0 }
        let textoNormalizado = normalizar(texto)
        let range = NSRange(textoNormalizado.startIndex..., in: textoNormalizado)

        var posicoesPorToken: [Int: [Int]] = [:]
        for (indice, token) in tokens.enumerated() {
            guard let regex = try? NSRegularExpression(
                pattern: "\\b\(NSRegularExpression.escapedPattern(for: token))\\b"
            ) else { continue }

            let posicoes = regex.matches(in: textoNormalizado, range: range).map(\.range.location)
            if !posicoes.isEmpty {
                posicoesPorToken[indice] = posicoes
            }
        }

        let tokensEncontrados = posicoesPorToken.count
        guard tokensEncontrados > 0 else { return 0 }

        let totalOcorrencias = posicoesPorToken.values.reduce(0) { $0 + $1.count }
        var pontuacao = tokensEncontrados * 100_000 + min(totalOcorrencias, 50)

        if tokensEncontrados == tokens.count, let janela = menorJanela(posicoesPorToken) {
            pontuacao += max(0, 50_000 - janela)
        }

        return pontuacao
    }

    /// Menor trecho que contém pelo menos uma ocorrência de cada palavra —
    /// janela deslizante sobre as posições ordenadas de todos os tokens.
    private static func menorJanela(_ posicoesPorToken: [Int: [Int]]) -> Int? {
        var eventos: [(posicao: Int, token: Int)] = []
        for (token, posicoes) in posicoesPorToken {
            eventos.append(contentsOf: posicoes.map { (posicao: $0, token: token) })
        }
        eventos.sort { $0.posicao < $1.posicao }

        let totalTokens = posicoesPorToken.count
        var contagem: [Int: Int] = [:]
        var distintos = 0
        var menor: Int?
        var esquerda = 0

        for (posicao, token) in eventos {
            contagem[token, default: 0] += 1
            if contagem[token] == 1 { distintos += 1 }

            while distintos == totalTokens {
                let janela = posicao - eventos[esquerda].posicao
                menor = min(menor ?? janela, janela)

                let tokenEsquerda = eventos[esquerda].token
                contagem[tokenEsquerda]! -= 1
                if contagem[tokenEsquerda] == 0 { distintos -= 1 }
                esquerda += 1
            }
        }

        return menor
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
}
