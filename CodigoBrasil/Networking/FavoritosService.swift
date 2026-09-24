import Foundation

private struct CriarFavoritoRequest: Encodable {
    let artigoId: Int
    let dispositivoId: Int?
}

enum FavoritosService {
    static func listar(token: String) async throws -> FavoritosResponse {
        try await APIClient.shared.get("/favoritos", token: token)
    }

    static func criar(artigoId: Int, dispositivoId: Int?, token: String) async throws -> FavoritoResponse {
        try await APIClient.shared.post(
            "/favoritos",
            body: CriarFavoritoRequest(artigoId: artigoId, dispositivoId: dispositivoId),
            token: token
        )
    }

    static func remover(id: Int, token: String) async throws {
        let _: OkResponse = try await APIClient.shared.delete("/favoritos/\(id)", token: token)
    }
}
