import CryptoKit
import Foundation

// MARK: - Configuração

/// O que o app guarda no aparelho para uso offline (Perfil › Armazenamento).
///
/// Cada modo é um caso novo aqui — o resto do app só pergunta `permiteBaixar`.
/// Ex.: futuramente `.bibliotecaInteira` ou `.selecionados`.
enum ModoDeArmazenamento: String, CaseIterable, Identifiable, Sendable {
    /// Nada fica salvo: o app carrega tudo pela API, como sempre.
    case nenhum
    /// Cada livro aberto é baixado por inteiro em segundo plano e passa a
    /// abrir do aparelho.
    case conformeUso

    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .nenhum: return "Não armazenar nenhum livro"
        case .conformeUso: return "Armazenar conforme o meu uso"
        }
    }

    var descricao: String {
        switch self {
        case .nenhum:
            return "Os livros são carregados pela internet a cada uso. Nada fica salvo no aparelho."
        case .conformeUso:
            return "Os livros que você abre são baixados em segundo plano e passam a abrir na hora, mesmo sem internet. Só eles são atualizados."
        }
    }

    /// Este modo baixa livros quando o usuário os abre?
    var permiteBaixar: Bool { self == .conformeUso }

    // Sem nada configurado, ninguém tem downloads automáticos: quem quer o
    // offline escolhe em Perfil › Armazenamento.
    static let padrao: ModoDeArmazenamento = .nenhum

    private static let chave = "armazenamento.modo"

    static var salvo: ModoDeArmazenamento {
        get { UserDefaults.standard.string(forKey: chave).flatMap(Self.init(rawValue:)) ?? padrao }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: chave) }
    }
}

// MARK: - Estado (o que a interface pode mostrar)

enum EstadoDoDownload: String, Codable, Sendable {
    case notDownloaded
    case downloading
    case downloaded
    case updating
    case failed
}

/// Situação de um livro no armazenamento offline. `failed` com `versaoLocal`
/// preenchida significa "erro ao atualizar": a cópia anterior segue utilizável.
struct EstadoOffline: Equatable, Sendable {
    var status: EstadoDoDownload = .notDownloaded
    var versaoLocal: String?
    var baixadoEm: Date?
    var verificadoEm: Date?
    var ultimoErro: String?
    var tamanhoEmBytes: Int?

    var disponivelOffline: Bool { versaoLocal != nil }
}

// MARK: - Respostas da API

struct ManifestoResponse: Decodable, Sendable {
    let livros: [LivroDoManifesto]
}

/// Uma linha do manifesto (ou o cabeçalho de `ConteudoLivroResponse`): só o
/// necessário para saber se o livro local está desatualizado.
struct LivroDoManifesto: Decodable, Equatable, Sendable {
    let id: String
    let titulo: String
    let versao: String
    let checksum: String
    let totalDeArtigos: Int
}

struct ConteudoLivroResponse: Decodable, Sendable {
    let lei: Lei
    let livro: LivroDoManifesto
    let artigos: [ArtigoOffline]
    let paginacao: Paginacao
}

enum TipoDeMudanca: String, Codable, Sendable {
    case insert
    case update
    case delete
}

struct MudancaDoLivro: Decodable, Sendable {
    let tipo: TipoDeMudanca
    let parte: String
    let numero: String
    /// Conteúdo atual do artigo — presente em `insert` e `update`.
    let artigo: ArtigoOffline?
}

struct AtualizacoesResponse: Decodable, Sendable {
    let livro: String
    let deVersao: String
    let paraVersao: String?
    let checksum: String?
    /// O servidor não consegue (ou não vale a pena) montar um delta: baixe o livro inteiro.
    let requerDownloadCompleto: Bool
    let mudancas: [MudancaDoLivro]
}

// MARK: - Livro salvo no aparelho

/// Um artigo com tudo que a tela dele precisa (caput + dispositivos) e o hash
/// do conteúdo calculado pelo servidor. Reaproveita `Artigo` e
/// `ArtigoDispositivo` — o JSON é o do artigo com dois campos a mais.
struct ArtigoOffline: Codable, Equatable, Sendable {
    let artigo: Artigo
    let dispositivos: [ArtigoDispositivo]
    let hash: String

    private enum Chaves: String, CodingKey {
        case hash
        case dispositivos
    }

    init(artigo: Artigo, dispositivos: [ArtigoDispositivo], hash: String) {
        self.artigo = artigo
        self.dispositivos = dispositivos
        self.hash = hash
    }

    init(from decoder: Decoder) throws {
        artigo = try Artigo(from: decoder)
        let container = try decoder.container(keyedBy: Chaves.self)
        hash = try container.decode(String.self, forKey: .hash)
        dispositivos = try container.decode([ArtigoDispositivo].self, forKey: .dispositivos)
    }

    func encode(to encoder: Encoder) throws {
        try artigo.encode(to: encoder)
        var container = encoder.container(keyedBy: Chaves.self)
        try container.encode(hash, forKey: .hash)
        try container.encode(dispositivos, forKey: .dispositivos)
    }

    /// Chave natural do artigo no livro. É por ela — não pelo id — que as
    /// atualizações dizem o que mudou.
    var chave: String { "\(artigo.parte)|\(artigo.numero)" }
}

/// Um livro completo e íntegro, gravado em um único arquivo. A versão e o
/// checksum ficam junto do conteúdo de propósito: trocar o arquivo (escrita
/// atômica) confirma conteúdo e versão no mesmo instante — nunca há um sem o outro.
struct LivroOffline: Codable, Sendable {
    let versao: String
    let checksum: String
    let baixadoEm: Date
    let lei: Lei
    /// Sempre em ordem de leitura (parte, ordem).
    let artigos: [ArtigoOffline]

    var id: String { lei.slug }

    /// Ordem de leitura, a mesma usada pelo servidor para calcular o checksum.
    static func ordenados(_ artigos: [ArtigoOffline]) -> [ArtigoOffline] {
        artigos.sorted { a, b in
            if a.artigo.parte != b.artigo.parte { return a.artigo.parte < b.artigo.parte }
            if a.artigo.ordem != b.artigo.ordem { return a.artigo.ordem < b.artigo.ordem }
            return a.artigo.numero < b.artigo.numero
        }
    }

    /// SHA-256 do livro: um hash por artigo (`parte|ordem|numero|hash`) na ordem
    /// de leitura. É recalculado a partir do que está no aparelho e comparado
    /// com o do servidor — a mesma fórmula de `ConteudoOffline::checksumDoLivro`
    /// no backend, que precisa continuar idêntica.
    static func checksum(de artigos: [ArtigoOffline]) -> String {
        let linhas = ordenados(artigos).map {
            "\($0.artigo.parte)|\($0.artigo.ordem)|\($0.artigo.numero)|\($0.hash)"
        }
        let digest = SHA256.hash(data: Data(linhas.joined(separator: "\n").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// O checksum guardado bate com o conteúdo que está no arquivo?
    var estaConsistente: Bool {
        !artigos.isEmpty && Self.checksum(de: artigos) == checksum
    }

    /// Aplica as mudanças de uma atualização e devolve o livro novo. Não altera
    /// `self`: se algo não bater (mudança sem conteúdo, checksum diferente do
    /// esperado), lança e a cópia atual continua intacta.
    func aplicando(_ mudancas: [MudancaDoLivro], versao: String, checksumEsperado: String) throws -> LivroOffline {
        var porChave = Dictionary(artigos.map { ($0.chave, $0) }, uniquingKeysWith: { atual, _ in atual })

        for mudanca in mudancas {
            let chave = "\(mudanca.parte)|\(mudanca.numero)"
            switch mudanca.tipo {
            case .delete:
                porChave[chave] = nil
            case .insert, .update:
                guard let artigo = mudanca.artigo else { throw ErroDeSincronizacao.mudancaSemConteudo(chave) }
                porChave[chave] = artigo
            }
        }

        let resultado = Self.ordenados(Array(porChave.values))
        guard Self.checksum(de: resultado) == checksumEsperado else {
            throw ErroDeSincronizacao.checksumDivergente
        }

        return LivroOffline(versao: versao, checksum: checksumEsperado, baixadoEm: baixadoEm, lei: lei, artigos: resultado)
    }
}

// MARK: - Erros

enum ErroDeSincronizacao: Error, Equatable {
    /// A versão do livro mudou enquanto ele era baixado por páginas.
    case versaoMudouNoMeio
    case contagemDivergente
    case checksumDivergente
    case mudancaSemConteudo(String)
}
