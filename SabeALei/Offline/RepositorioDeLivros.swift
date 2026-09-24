import Foundation

/// De onde vem o conteúdo de um livro: do aparelho, se existe uma cópia local
/// completa e íntegra; senão, da API — exatamente como era antes do offline.
///
/// As telas falam só com este repositório. Com a cópia local ele responde na
/// hora e sem nenhuma requisição (páginas, busca por número, busca por texto,
/// detalhe do artigo); sem ela, delega ao `LeisService`.
enum RepositorioDeLivros {
    static func pagina(
        leiSlug: String, parte: ParteConstitucional, limite: Int, deslocamento: Int
    ) async throws -> ArtigosResponse {
        if let local = await LocalBookStore.shared.pagina(leiSlug, parte: parte.rawValue, limite: limite, deslocamento: deslocamento) {
            return ArtigosResponse(
                lei: local.lei, parte: parte.rawValue, artigos: local.artigos,
                paginacao: Paginacao(limit: limite, offset: deslocamento, temMais: local.temMais)
            )
        }

        return try await LeisService.artigos(leiSlug: leiSlug, parte: parte, limite: limite, deslocamento: deslocamento)
    }

    /// O artigo com esse número exato, em todo o livro (não só no que já foi carregado na lista).
    static func porNumero(leiSlug: String, parte: ParteConstitucional, numero: String) async throws -> [Artigo] {
        if let local = await LocalBookStore.shared.porNumero(leiSlug, parte: parte.rawValue, numero: numero) {
            return local
        }

        return try await LeisService.artigos(leiSlug: leiSlug, parte: parte, numero: numero).artigos
    }

    static func buscarTexto(leiSlug: String, parte: ParteConstitucional, consulta: String) async throws -> [Artigo] {
        if let local = await LocalBookStore.shared.buscarTexto(leiSlug, parte: parte.rawValue, consulta: consulta) {
            return local
        }

        return try await LeisService.artigos(leiSlug: leiSlug, parte: parte, busca: consulta).artigos
    }

    /// O artigo com seus dispositivos. Procura nos livros salvos antes de ir à API.
    static func detalhe(artigoId: Int) async throws -> ArtigoDetalheResponse {
        if let local = await LocalBookStore.shared.detalhe(artigoId: artigoId) {
            return ArtigoDetalheResponse(artigo: local.artigo, dispositivos: local.dispositivos)
        }

        return try await LeisService.artigo(id: artigoId)
    }
}
