import Foundation

/// Versão enxuta do dispositivo favoritado — só o que a tela de favoritos
/// precisa mostrar (o artigo já traz o resto do contexto).
struct FavoritoDispositivo: Codable, Identifiable, Equatable {
    let id: Int
    let tipo: String
    let rotulo: String
    let texto: String
}

/// Um artigo inteiro (dispositivo nulo) ou um parágrafo específico favoritado
/// pelo usuário logado.
struct Favorito: Codable, Identifiable, Equatable {
    let id: Int
    let artigo: Artigo
    let dispositivo: FavoritoDispositivo?
}

struct FavoritosResponse: Decodable {
    let favoritos: [Favorito]
}

struct FavoritoResponse: Decodable {
    let favorito: Favorito
}

struct OkResponse: Decodable {
    let ok: Bool
}
