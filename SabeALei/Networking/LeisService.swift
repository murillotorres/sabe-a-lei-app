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

    static func artigos(leiSlug: String, parte: ParteConstitucional, busca: String? = nil) async throws -> ArtigosResponse {
        var query = ["parte": parte.rawValue]
        if let busca, !busca.isEmpty {
            query["q"] = busca
        }
        return try await APIClient.shared.get("/leis/\(leiSlug)/artigos", query: query)
    }

    static func artigo(id: Int) async throws -> ArtigoDetalheResponse {
        try await APIClient.shared.get("/artigos/\(id)")
    }
}
