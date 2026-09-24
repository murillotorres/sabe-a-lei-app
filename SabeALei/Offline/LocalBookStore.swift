import Foundation

/// Persistência dos livros offline: um arquivo JSON por livro, em
/// `Application Support/OfflineLibrary/`.
///
/// Tudo que pertence ao armazenamento offline mora nessa pasta e só nela —
/// `removerTudo()` apaga exatamente essa pasta, nunca dados do usuário
/// (favoritos, sessão, preferências ficam em outros lugares).
///
/// Garantias:
/// - a escrita de um livro é atômica (arquivo temporário + troca), então uma
///   cópia parcial nunca aparece — ou existe o livro completo, ou o anterior;
/// - um arquivo que não decodifica, ou cujo checksum não bate, é descartado.
///
/// Os livros abertos ficam em memória (decodificar um livro grande leva algumas
/// dezenas de milissegundos; acontece uma vez por execução).
actor LocalBookStore {
    static let shared = LocalBookStore()

    struct Resumo: Sendable {
        let versao: String
        let checksum: String
        let baixadoEm: Date
        let tamanhoEmBytes: Int
    }

    /// O que se guarda sobre um livro além do próprio conteúdo. Não é essencial:
    /// se o arquivo se perder, só se perde a data da última verificação.
    struct EstadoPersistido: Codable, Sendable, Equatable {
        var verificadoEm: Date?
        var ultimoErro: String?
    }

    /// Textos normalizados (sem acento, minúsculos) para a busca local, alinhados
    /// a `livro.artigos`. Montado na primeira busca de cada livro.
    struct IndiceDeBusca: Sendable {
        let artigos: [String]
        let dispositivos: [[String]]
    }

    private struct LivroEmMemoria {
        let livro: LivroOffline
        let indicePorId: [Int: Int]
        let tamanhoEmBytes: Int
        var indiceDeBusca: IndiceDeBusca?
    }

    private let diretorio: URL
    private var cache: [String: LivroEmMemoria] = [:]
    private var estados: [String: EstadoPersistido]?

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    init(diretorio: URL = LocalBookStore.diretorioPadrao()) {
        self.diretorio = diretorio
    }

    static func diretorioPadrao() -> URL {
        URL.applicationSupportDirectory.appending(path: "OfflineLibrary", directoryHint: .isDirectory)
    }

    // MARK: Livros

    /// Ids (slugs) dos livros com cópia local — nomes de arquivo, sem decodificar nada.
    func idsArmazenados() -> [String] {
        let arquivos = (try? FileManager.default.contentsOfDirectory(at: diretorio, includingPropertiesForKeys: nil)) ?? []
        return arquivos
            .filter { $0.pathExtension == "json" && $0.lastPathComponent != Self.nomeDoArquivoDeEstado }
            .map { $0.deletingPathExtension().lastPathComponent }
            .sorted()
    }

    /// A cópia local completa e íntegra do livro, ou `nil`.
    func livro(_ id: String) -> LivroOffline? {
        emMemoria(id)?.livro
    }

    func resumo(_ id: String) -> Resumo? {
        guard let entrada = emMemoria(id) else { return nil }
        return Resumo(
            versao: entrada.livro.versao, checksum: entrada.livro.checksum,
            baixadoEm: entrada.livro.baixadoEm, tamanhoEmBytes: entrada.tamanhoEmBytes
        )
    }

    /// Grava o livro. Só é chamado com o livro já validado por inteiro — o
    /// arquivo antigo, se houver, é substituído de uma vez.
    func salvar(_ livro: LivroOffline) throws {
        guard Self.idValido(livro.id) else { throw CocoaError(.fileWriteInvalidFileName) }

        try FileManager.default.createDirectory(at: diretorio, withIntermediateDirectories: true)
        excluirPastaDoBackup()

        let dados = try encoder.encode(livro)
        try dados.write(to: urlDoLivro(livro.id), options: .atomic)
        cache[livro.id] = Self.montar(livro, tamanhoEmBytes: dados.count)
    }

    func remover(_ id: String) {
        cache[id] = nil
        guard Self.idValido(id) else { return }
        try? FileManager.default.removeItem(at: urlDoLivro(id))
    }

    /// Apaga TUDO do armazenamento offline: a pasta `OfflineLibrary` e nada além.
    func removerTudo() {
        cache.removeAll()
        estados = [:]
        try? FileManager.default.removeItem(at: diretorio)
        LogOffline.offline("Removed all offline books")
    }

    /// O artigo (com dispositivos) de qualquer livro armazenado, pelo id.
    func detalhe(artigoId: Int) -> ArtigoOffline? {
        for id in idsArmazenados() {
            if let entrada = emMemoria(id), let posicao = entrada.indicePorId[artigoId] {
                return entrada.livro.artigos[posicao]
            }
        }
        return nil
    }

    /// Uma "página" do livro, no mesmo formato da API paginada.
    func pagina(_ id: String, parte: String, limite: Int, deslocamento: Int) -> (lei: Lei, artigos: [Artigo], temMais: Bool)? {
        guard let entrada = emMemoria(id) else { return nil }

        let daParte = entrada.livro.artigos.filter { $0.artigo.parte == parte }
        let inicio = min(deslocamento, daParte.count)
        let fim = min(inicio + limite, daParte.count)

        return (entrada.livro.lei, daParte[inicio..<fim].map(\.artigo), fim < daParte.count)
    }

    /// Artigos do livro com esse número exato.
    func porNumero(_ id: String, parte: String, numero: String) -> [Artigo]? {
        guard let entrada = emMemoria(id) else { return nil }

        return entrada.livro.artigos
            .filter { $0.artigo.parte == parte && $0.artigo.numero == numero }
            .map(\.artigo)
    }

    /// Busca por texto dentro do livro, com o mesmo critério de relevância da API.
    func buscarTexto(_ id: String, parte: String, consulta: String) -> [Artigo]? {
        guard var entrada = emMemoria(id) else { return nil }

        if entrada.indiceDeBusca == nil {
            entrada.indiceDeBusca = BuscaLocal.montarIndice(entrada.livro)
            cache[id] = entrada
        }

        return BuscaLocal.buscar(entrada.livro, indice: entrada.indiceDeBusca!, parte: parte, consulta: consulta)
    }

    // MARK: Estado

    func estadoPersistido(_ id: String) -> EstadoPersistido {
        carregarEstados()[id] ?? EstadoPersistido()
    }

    func atualizarEstado(_ id: String, _ alteracao: (inout EstadoPersistido) -> Void) {
        var todos = carregarEstados()
        var estado = todos[id] ?? EstadoPersistido()
        alteracao(&estado)
        todos[id] = estado
        estados = todos

        guard let dados = try? encoder.encode(todos) else { return }
        try? FileManager.default.createDirectory(at: diretorio, withIntermediateDirectories: true)
        try? dados.write(to: urlDoEstado, options: .atomic)
    }

    // MARK: Interno

    private static let nomeDoArquivoDeEstado = "estado.json"

    /// Ids vêm do servidor e viram nome de arquivo: só letras, números e hífen.
    private static func idValido(_ id: String) -> Bool {
        !id.isEmpty && id.allSatisfy { ($0.isASCII && ($0.isLetter || $0.isNumber)) || $0 == "-" }
    }

    private func urlDoLivro(_ id: String) -> URL {
        diretorio.appending(path: "\(id).json")
    }

    private var urlDoEstado: URL {
        diretorio.appending(path: Self.nomeDoArquivoDeEstado)
    }

    private func carregarEstados() -> [String: EstadoPersistido] {
        if let estados { return estados }

        let lidos = (try? Data(contentsOf: urlDoEstado)).flatMap { try? decoder.decode([String: EstadoPersistido].self, from: $0) } ?? [:]
        estados = lidos
        return lidos
    }

    private func emMemoria(_ id: String) -> LivroEmMemoria? {
        if let entrada = cache[id] { return entrada }
        guard Self.idValido(id), let dados = try? Data(contentsOf: urlDoLivro(id)) else { return nil }

        guard let livro = try? decoder.decode(LivroOffline.self, from: dados), livro.id == id, livro.estaConsistente else {
            // Arquivo corrompido: melhor descartar e baixar de novo do que exibir dados duvidosos.
            LogOffline.offline("Discarding invalid local copy: \(id)")
            try? FileManager.default.removeItem(at: urlDoLivro(id))
            return nil
        }

        let entrada = Self.montar(livro, tamanhoEmBytes: dados.count)
        cache[id] = entrada
        return entrada
    }

    private static func montar(_ livro: LivroOffline, tamanhoEmBytes: Int) -> LivroEmMemoria {
        let indice = Dictionary(
            livro.artigos.enumerated().map { ($0.element.artigo.id, $0.offset) },
            uniquingKeysWith: { primeiro, _ in primeiro }
        )
        return LivroEmMemoria(livro: livro, indicePorId: indice, tamanhoEmBytes: tamanhoEmBytes, indiceDeBusca: nil)
    }

    /// Conteúdo re-baixável não precisa ir para o backup do iCloud/iTunes.
    private func excluirPastaDoBackup() {
        var pasta = diretorio
        var valores = URLResourceValues()
        valores.isExcludedFromBackup = true
        try? pasta.setResourceValues(valores)
    }
}
