import Foundation

enum LeisService {
    static func categorias() async throws -> [Categoria] {
        let response: CategoriasResponse = try await APIClient.shared.get("/categorias")
        return response.categorias
    }

    static func leis(categoria: String) async throws -> [Lei] {
        let response: LeisResponse = try await APIClient.shared.get("/leis", query: ["categoria": categoria])
        return response.leis
    }

    /// Artigos de uma lei. Sem `limite`, vem o livro inteiro; com `limite`, só
    /// essa "página" a partir de `deslocamento` (ver `ArtigosResponse.paginacao`).
    /// `numero` traz só o artigo com esse número. `busca` sempre olha o livro
    /// inteiro e não é paginada.
    static func artigos(
        leiSlug: String,
        parte: ParteConstitucional,
        busca: String? = nil,
        numero: String? = nil,
        limite: Int? = nil,
        deslocamento: Int = 0
    ) async throws -> ArtigosResponse {
        var query = ["parte": parte.rawValue]
        if let busca, !busca.isEmpty {
            query["q"] = busca
        }
        if let numero {
            query["numero"] = numero
        }
        if let limite {
            query["limit"] = String(limite)
            query["offset"] = String(deslocamento)
        }
        return try await APIClient.shared.get("/leis/\(leiSlug)/artigos", query: query)
    }

    static func artigo(id: Int) async throws -> ArtigoDetalheResponse {
        try await APIClient.shared.get("/artigos/\(id)")
    }

    /// Busca em todas as leis cadastradas (aba Buscar), não só numa lei específica.
    static func buscarGlobal(query: String) async throws -> [Artigo] {
        guard !query.isEmpty else { return [] }
        let response: BuscaResponse = try await APIClient.shared.get("/busca", query: ["q": query])
        return response.artigos
    }
}
