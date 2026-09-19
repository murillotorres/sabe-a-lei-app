import Foundation

struct Categoria: Codable, Identifiable, Equatable {
    let id: Int
    let slug: String
    let nome: String
}

struct Lei: Codable, Identifiable, Equatable {
    let id: Int
    let categoriaId: Int?
    let slug: String
    let titulo: String
    let descricao: String?
    let fonteUrl: String?
}

enum ParteConstitucional: String, Codable, CaseIterable {
    case permanente
    case adct

    var titulo: String {
        switch self {
        case .permanente: return "Texto Permanente"
        case .adct: return "ADCT"
        }
    }
}

struct Artigo: Codable, Identifiable, Equatable {
    let id: Int
    let parte: String
    let numero: String
    let tituloEstrutural: String?
    let capituloEstrutural: String?
    let secaoEstrutural: String?
    let subsecaoEstrutural: String?
    let caput: String
    let revogado: Bool
    let ordem: Int
    let leiSlug: String?
    let leiTitulo: String?
    /// Presente só em resultados de busca por texto: o dispositivo (parágrafo/
    /// inciso/alínea) do artigo em que as palavras buscadas foram encontradas.
    let trechoCorrespondente: TrechoCorrespondente?

    var titulo: String {
        numero == "Preâmbulo" ? "Preâmbulo" : "Art. \(numero)"
    }

    /// Agrupamento estrutural (Título > Capítulo > Seção) usado como cabeçalho de seção nas listas.
    var grupoEstrutural: String? {
        let partes = [tituloEstrutural, capituloEstrutural, secaoEstrutural, subsecaoEstrutural].compactMap { $0 }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }
}

struct TrechoCorrespondente: Codable, Equatable {
    let tipo: String
    let rotulo: String
    let texto: String
}

struct ArtigoDispositivo: Codable, Identifiable, Equatable {
    let id: Int
    let parentId: Int?
    let tipo: String
    let rotulo: String
    let texto: String
    let nivel: Int
    let revogado: Bool
    let ordem: Int
}

struct ArtigosResponse: Decodable {
    let lei: Lei
    let parte: String
    let artigos: [Artigo]
}

struct ArtigoDetalheResponse: Decodable {
    let artigo: Artigo
    let dispositivos: [ArtigoDispositivo]
}

struct CategoriasResponse: Decodable {
    let categorias: [Categoria]
}

struct LeisResponse: Decodable {
    let leis: [Lei]
}
