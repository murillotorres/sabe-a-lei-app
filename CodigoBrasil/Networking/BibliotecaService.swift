import Foundation

/// Endpoints do armazenamento offline. Todos de prioridade baixa: são trabalho
/// de fundo e esperam as requisições da tela (ver `AtividadeDeRede`).
enum BibliotecaService {
    /// Quantos artigos vêm por página no download de um livro (o servidor limita a 100).
    static let artigosPorPagina = 100

    /// Versão de cada livro publicado. Minúsculo: é o que se consulta ao abrir o app.
    static func manifesto() async throws -> ManifestoResponse {
        try await APIClient.shared.get("/biblioteca/manifesto", prioridade: .baixa)
    }

    /// Uma página do livro completo (artigos já com seus dispositivos).
    static func conteudo(leiSlug: String, deslocamento: Int) async throws -> ConteudoLivroResponse {
        try await APIClient.shared.get(
            "/leis/\(leiSlug)/conteudo",
            query: ["limit": String(artigosPorPagina), "offset": String(deslocamento)],
            prioridade: .baixa
        )
    }

    /// O que mudou desde a versão `de` até a última publicada.
    static func atualizacoes(leiSlug: String, de versao: String) async throws -> AtualizacoesResponse {
        try await APIClient.shared.get("/leis/\(leiSlug)/atualizacoes", query: ["de": versao], prioridade: .baixa)
    }
}
