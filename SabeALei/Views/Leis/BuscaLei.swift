import Foundation
import OSLog

/// Artigos consecutivos que compartilham o mesmo cabeçalho estrutural
/// (Parte · Título · Capítulo…), já prontos pra renderização — a lista não
/// precisa reagrupar nada dentro do `body`.
struct GrupoArtigos: Identifiable, Equatable, Sendable {
    /// Id do primeiro artigo do grupo: estável entre renderizações (ao contrário
    /// de um índice) e único, já que um artigo só pertence a um grupo.
    let id: Int
    let titulo: String?
    let descricao: String?
    let artigos: [Artigo]
}

/// Consulta dentro do livro aberto. Tudo aqui é puro e `nonisolated`: as
/// funções `async` rodam no executor global (`@concurrent`), então filtrar e
/// agrupar não ocupa a MainActor — só o resultado pronto volta pra ela.
enum BuscaLei {
    /// Reconhece referências a um artigo específico ("5", "art5", "art 5", "art. 5",
    /// "a5", "103-A"...) e devolve o número normalizado, ou `nil` se o texto não for isso.
    static func numeroReferenciado(_ texto: String) -> String? {
        let trimmed = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let match = trimmed.wholeMatch(of: /(?:art\.?|a\.?)?\s*(\d+)(?:-([a-zA-Z]))?/.ignoresCase()) else {
            return nil
        }

        let numero = String(match.1)
        guard let letra = match.2 else { return numero }
        return "\(numero)-\(letra.uppercased())"
    }

    /// Agrupa o livro (ou um resultado de busca) pelo cabeçalho estrutural.
    @concurrent
    static func agrupar(_ artigos: [Artigo]) async -> [GrupoArtigos] {
        montarGrupos(artigos)
    }

    /// Consulta por número de artigo — só olha os artigos do livro aberto.
    @concurrent
    static func porNumero(_ numero: String, em artigos: [Artigo]) async -> [GrupoArtigos] {
        montarGrupos(artigos.filter { $0.numero == numero })
    }

    private static func montarGrupos(_ artigos: [Artigo]) -> [GrupoArtigos] {
        guard !artigos.isEmpty else { return [] }

        var grupos: [GrupoArtigos] = []
        var inicio = 0
        // `grupoEstrutural` monta uma string a cada chamada — calculado uma vez por artigo.
        var tituloAtual = artigos[0].grupoEstrutural

        for indice in 1..<artigos.count {
            let titulo = artigos[indice].grupoEstrutural
            guard titulo != tituloAtual else { continue }

            grupos.append(GrupoArtigos(
                id: artigos[inicio].id,
                titulo: tituloAtual,
                descricao: artigos[inicio].descricaoEstrutural,
                artigos: Array(artigos[inicio..<indice])
            ))
            inicio = indice
            tituloAtual = titulo
        }

        grupos.append(GrupoArtigos(
            id: artigos[inicio].id,
            titulo: tituloAtual,
            descricao: artigos[inicio].descricaoEstrutural,
            artigos: Array(artigos[inicio...])
        ))
        return grupos
    }
}

/// Pontuação de compatibilidade de um texto com as palavras buscadas — mesma
/// lógica usada no backend para a busca geral (ver `Artigo::pontuar` na API).
/// Serve tanto à busca dentro de um artigo quanto à busca dentro de um livro
/// salvo no aparelho (`BuscaLocal`).
enum BuscaTexto {
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

    /// Uma regex por palavra, compilada uma vez — pontuar muitos textos com a
    /// mesma consulta (um livro inteiro) não deve recompilar tudo a cada texto.
    static func compilar(_ tokens: [String]) -> [NSRegularExpression?] {
        tokens.map { try? NSRegularExpression(pattern: "\\b\(NSRegularExpression.escapedPattern(for: $0))\\b") }
    }

    static func pontuar(_ texto: String, tokens: [String]) -> Int {
        pontuarNormalizado(normalizar(texto), tokens: tokens, regexes: compilar(tokens))
    }

    /// Como `pontuar`, para um texto que já foi normalizado e regexes já compiladas.
    static func pontuarNormalizado(_ textoNormalizado: String, tokens: [String], regexes: [NSRegularExpression?]) -> Int {
        guard !tokens.isEmpty else { return 0 }
        let range = NSRange(textoNormalizado.startIndex..., in: textoNormalizado)

        // O servidor mede posições em bytes UTF-8; o NSRegularExpression, em unidades
        // UTF-16. Só difere em texto com caracteres fora do ASCII (º, §, aspas...) —
        // converte nesses casos pra a "janela" entre as palavras, e portanto a ordem
        // dos resultados, ser a mesma da API.
        let mapaParaUTF8 = textoNormalizado.utf8.count == textoNormalizado.utf16.count
            ? nil : mapaDeUTF16ParaUTF8(textoNormalizado)

        var posicoesPorToken: [Int: [Int]] = [:]
        for (indice, regex) in regexes.enumerated() {
            guard let regex else { continue }

            let posicoes = regex.matches(in: textoNormalizado, range: range).map { resultado in
                mapaParaUTF8?[resultado.range.location] ?? resultado.range.location
            }
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

    /// `mapa[posição UTF-16] = posição em bytes UTF-8` do mesmo caractere.
    private static func mapaDeUTF16ParaUTF8(_ texto: String) -> [Int] {
        var mapa: [Int] = []
        mapa.reserveCapacity(texto.utf16.count + 1)

        var bytes = 0
        for escalar in texto.unicodeScalars {
            for _ in 0..<escalar.utf16.count { mapa.append(bytes) }
            bytes += escalar.utf8.count
        }
        mapa.append(bytes)
        return mapa
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

#if DEBUG
import UIKit

/// Medições da abertura e do uso da busca — só em DEBUG. Ajudam a ver onde o
/// tempo vai (ver o relatório Fence-hang): toque → campo inserido → foco
/// solicitado → teclado. Filtrar no Console por subsystem
/// `com.murillotorres.sabealei`, category `Busca`.
@MainActor
enum BuscaMetricas {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SabeALei", category: "Busca")
    private static var toque: ContinuousClock.Instant?

    private static var observadoresDoTeclado: [any NSObjectProtocol] = []

    static func toqueNoBotao() {
        toque = .now
        logger.debug("[busca] toque no botão de pesquisa")
        observarTecladoUmaVez()
    }

    static func campoInserido() { marcar("campo inserido na hierarquia") }
    static func focoSolicitado() { marcar("foco solicitado") }
    static func tecladoVaiAparecer() { marcar("teclado vai aparecer") }
    static func tecladoApareceu() { marcar("teclado apareceu") }

    static func buscaExecutada(origem: String, consulta: String, pesquisados: Int, resultados: Int, duracao: Duration) {
        logger.debug("[busca] \(origem) \"\(consulta)\": \(pesquisados) artigo(s) no livro → \(resultados) resultado(s) em \(milissegundos(duracao), format: .fixed(precision: 1)) ms")
    }

    /// Quanto a main thread ficou ocupada carregando o teclado no pré-aquecimento
    /// (`TecladoPreAquecido`) — o custo que antes caía na abertura da busca.
    static func tecladoPreAquecido(duracao: Duration) {
        logger.debug("[busca] teclado pré-aquecido após o lançamento: main thread ocupada por \(milissegundos(duracao), format: .fixed(precision: 1)) ms")
    }

    private static func marcar(_ evento: String) {
        guard let toque else { return }
        logger.debug("[busca] \(evento) — +\(milissegundos(.now - toque), format: .fixed(precision: 1)) ms após o toque")
    }

    private static func milissegundos(_ duracao: Duration) -> Double {
        let componentes = duracao.components
        return Double(componentes.seconds) * 1000 + Double(componentes.attoseconds) / 1e15
    }

    /// Observers de disparo único: registrados no toque, saem depois do
    /// `keyboardDidShow` (ou no próximo toque, se o teclado nunca subir).
    private static func observarTecladoUmaVez() {
        removerObservadoresDoTeclado()
        let centro = NotificationCenter.default
        observadoresDoTeclado = [
            centro.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { tecladoVaiAparecer() }
            },
            centro.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    tecladoApareceu()
                    removerObservadoresDoTeclado()
                }
            },
        ]
    }

    private static func removerObservadoresDoTeclado() {
        observadoresDoTeclado.forEach(NotificationCenter.default.removeObserver)
        observadoresDoTeclado = []
    }
}
#else
@MainActor
enum BuscaMetricas {
    static func toqueNoBotao() {}
    static func campoInserido() {}
    static func focoSolicitado() {}
    static func buscaExecutada(origem: String, consulta: String, pesquisados: Int, resultados: Int, duracao: Duration) {}
    static func tecladoPreAquecido(duracao: Duration) {}
}
#endif
