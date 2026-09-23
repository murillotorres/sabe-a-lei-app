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
