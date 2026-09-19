import SwiftUI

/// Tela de um artigo: o caput em destaque e, abaixo, cada parágrafo/inciso/alínea
/// que o complementa exibido em seu próprio card, indentado conforme a hierarquia.
struct ArtigoDetailView: View {
    let artigoId: Int
    /// Dados já conhecidos da listagem, usados para exibir algo enquanto o detalhe carrega.
    var resumo: Artigo?

    @State private var artigo: Artigo?
    @State private var dispositivos: [ArtigoDispositivo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""

    private var artigoAtual: Artigo? { artigo ?? resumo }

    /// Filtra e reordena os dispositivos por compatibilidade com a busca —
    /// mesmo critério usado na busca geral da Constituição (quantas palavras
    /// batem, priorizando as que aparecem mais próximas umas das outras),
    /// só que aplicado apenas ao conteúdo deste artigo, já carregado localmente.
    private var dispositivosFiltrados: [ArtigoDispositivo] {
        guard !searchText.isEmpty else { return dispositivos }

        let tokens = BuscaTexto.tokenizar(searchText)
        guard !tokens.isEmpty else { return dispositivos }

        return dispositivos
            .map { ($0, BuscaTexto.pontuar($0.texto, tokens: tokens)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
    }

    var body: some View {
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
                } else if !searchText.isEmpty && dispositivosFiltrados.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .padding(.top, 24)
                } else {
                    ForEach(dispositivosFiltrados) { dispositivo in
                        DispositivoCardView(dispositivo: dispositivo, destacado: !searchText.isEmpty)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(artigoAtual?.titulo ?? "Artigo")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: "Buscar neste artigo")
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await LeisService.artigo(id: artigoId)
            artigo = response.artigo
            dispositivos = response.dispositivos
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(artigo.titulo)
                    .font(.title3.bold())
                if artigo.revogado {
                    Text("Revogado")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
            Text(artigo.caput)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Um card por parágrafo/inciso/alínea/item, indentado conforme o nível de aninhamento.
struct DispositivoCardView: View {
    let dispositivo: ArtigoDispositivo
    /// true quando este card é resultado de uma busca dentro do artigo — pinta
    /// o fundo de amarelo, no mesmo estilo do trecho destacado na busca geral.
    var destacado: Bool = false

    private var accentColor: Color {
        switch dispositivo.tipo {
        case "paragrafo": return .blue
        case "inciso": return .teal
        case "alinea": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(dispositivo.rotulo)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accentColor, in: Capsule())
                .fixedSize()

            VStack(alignment: .leading, spacing: 6) {
                Text(dispositivo.texto)
                    .font(.subheadline)
                if dispositivo.revogado {
                    Text("Revogado")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
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

#Preview {
    NavigationStack {
        ArtigoDetailView(
            artigoId: 6,
            resumo: Artigo(
                id: 6, parte: "permanente", numero: "5",
                tituloEstrutural: "Título II", capituloEstrutural: "Capítulo I",
                secaoEstrutural: nil, subsecaoEstrutural: nil,
                caput: "Todos são iguais perante a lei...",
                revogado: false, ordem: 5, leiSlug: nil, leiTitulo: nil,
                trechoCorrespondente: nil
            )
        )
    }
}
