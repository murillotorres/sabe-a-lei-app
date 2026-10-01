import Foundation

/// Cores de grifo disponíveis. O valor bruto é o que a API guarda.
enum CorDoGrifo: String, Codable, CaseIterable, Identifiable, Sendable {
    case amarelo, verde, azul, vermelho, roxo

    var id: Self { self }

    var nome: String {
        switch self {
        case .amarelo: "Amarelo"
        case .verde: "Verde"
        case .azul: "Azul"
        case .vermelho: "Vermelho"
        case .roxo: "Roxo"
        }
    }
}

/// Onde fica o artigo de um grifo/anotação — o bastante para "Minhas anotações"
/// mostrar e ordenar o registro sem abrir o artigo.
struct ResumoDoArtigoEstudado: Codable, Equatable, Sendable {
    var leiSlug: String?
    var parte: String
    var numero: String
    var rubrica: String?
    var ordem: Int

    init(leiSlug: String?, parte: String, numero: String, rubrica: String?, ordem: Int) {
        self.leiSlug = leiSlug
        self.parte = parte
        self.numero = numero
        self.rubrica = rubrica
        self.ordem = ordem
    }

    init(_ artigo: Artigo, leiSlug: String?) {
        self.init(
            leiSlug: leiSlug ?? artigo.leiSlug, parte: artigo.parte, numero: artigo.numero,
            rubrica: artigo.rubrica, ordem: artigo.ordem
        )
    }

    /// "Art. 25 — Legítima defesa".
    var titulo: String {
        let base = numero == "Preâmbulo" ? "Preâmbulo" : "Art. \(numero)"
        let adct = parte == ParteConstitucional.adct.rawValue ? " (ADCT)" : ""
        guard let rubrica, !rubrica.isEmpty else { return base + adct }
        return "\(base)\(adct) — \(rubrica)"
    }
}

/// Um trecho marcado dentro de um dispositivo do artigo. `cor` nula = trecho
/// sem grifo, só sublinhado porque tem uma nota.
///
/// A âncora não depende só das posições: `dispositivoChave` é a chave natural
/// do dispositivo no artigo (ver `Ancoragem`), e o trecho, o contexto antes e
/// depois e o texto inteiro do dispositivo na criação permitem reencontrá-lo — ou
/// avisar que mudou — depois de uma atualização da lei.
struct Grifo: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let artigoId: Int
    var dispositivoId: Int?
    let dispositivoChave: String
    var dispositivoOrdem: Int
    let trecho: String
    let prefixo: String
    let sufixo: String
    /// Posições em UTF-16 (as do `NSString`) dentro do texto do dispositivo.
    let inicio: Int
    let fim: Int
    let textoOriginal: String
    var cor: CorDoGrifo?
    var versao: String?
    let criadoEm: Date
    var alteradoEm: Date
    var excluido: Bool
    var artigo: ResumoDoArtigoEstudado?
}

/// Anotação do usuário: de um trecho (`grifoId`) ou do artigo inteiro (`grifoId` nulo).
struct Anotacao: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let artigoId: Int
    let grifoId: UUID?
    var conteudo: String
    let criadoEm: Date
    var alteradoEm: Date
    var excluido: Bool
    var artigo: ResumoDoArtigoEstudado?
}

/// Corpo e resposta de `POST /estudos/sync`.
struct SincronizacaoDeEstudos: Encodable {
    let desde: Int
    let grifos: [Grifo]
    let anotacoes: [Anotacao]
}

struct RespostaDaSincronizacao: Decodable {
    let revisao: Int
    /// A resposta traz tudo (primeira carga, ou o servidor não conhece a
    /// revisão do app): o que não veio e não está pendente deixa de existir.
    let completo: Bool
    let grifos: [Grifo]
    let anotacoes: [Anotacao]
    let rejeitados: [String]
}
