import Foundation

/// Últimas buscas da aba Buscar, cada uma com o último resultado que teve —
/// tocar numa busca recente mostra a lista na hora (mesmo sem internet) e ela
/// se atualiza em seguida. Fica só no aparelho, num JSON em Application Support.
///
/// Uma busca entra no histórico quando o usuário a confirma (tecla buscar) ou
/// toca num resultado — não a cada letra digitada, senão "hom", "homic"… também
/// entrariam.
@MainActor
@Observable
final class HistoricoDeBuscas {
    struct Entrada: Codable, Identifiable, Equatable {
        let consulta: String
        /// `nil` enquanto a busca ainda não teve resposta do servidor.
        var resposta: BuscaResponse?

        var id: String { consulta }
    }

    static let limite = 10

    private(set) var entradas: [Entrada] = []
    private var carregado = false
    /// Última gravação em andamento — a próxima espera por ela, senão uma
    /// versão antiga poderia terminar depois e sobrescrever a nova.
    @ObservationIgnored private var gravacao: Task<Void, Never>?

    private nonisolated static let arquivo = URL.applicationSupportDirectory.appending(path: "historico-de-buscas.json")

    /// Lê o arquivo fora da MainActor. Só na primeira chamada.
    func carregar() async {
        guard !carregado else { return }
        carregado = true

        let lidas = await Task.detached(priority: .userInitiated) { () -> [Entrada] in
            guard let dados = try? Data(contentsOf: Self.arquivo) else { return [] }
            return (try? JSONDecoder().decode([Entrada].self, from: dados)) ?? []
        }.value

        // Algo registrado antes de o arquivo terminar de carregar fica na frente.
        let novas = entradas
        entradas = novas + lidas.filter { lida in !novas.contains { Self.mesmaConsulta($0.consulta, lida.consulta) } }
        entradas = Array(entradas.prefix(Self.limite))
    }

    func resposta(para consulta: String) -> BuscaResponse? {
        entradas.first { Self.mesmaConsulta($0.consulta, consulta) }?.resposta
    }

    /// Põe a busca no topo. Sem `resposta`, mantém a que já estava guardada.
    func registrar(_ consulta: String, resposta: BuscaResponse?) {
        let anterior = entradas.first { Self.mesmaConsulta($0.consulta, consulta) }
        entradas.removeAll { Self.mesmaConsulta($0.consulta, consulta) }
        entradas.insert(Entrada(consulta: consulta, resposta: resposta ?? anterior?.resposta), at: 0)
        entradas = Array(entradas.prefix(Self.limite))
        salvar()
    }

    /// Guarda o resultado mais novo de uma busca que já está no histórico, sem
    /// mudar a ordem. Busca fora do histórico é ignorada.
    func atualizar(_ consulta: String, resposta: BuscaResponse) {
        guard let indice = entradas.firstIndex(where: { Self.mesmaConsulta($0.consulta, consulta) }),
              entradas[indice].resposta != resposta else { return }
        entradas[indice].resposta = resposta
        salvar()
    }

    func remover(em posicoes: IndexSet) {
        entradas.remove(atOffsets: posicoes)
        salvar()
    }

    func limpar() {
        entradas = []
        salvar()
    }

    /// "Homicídio" e "homicidio" são a mesma busca.
    private static func mesmaConsulta(_ a: String, _ b: String) -> Bool {
        BuscaTexto.normalizar(a) == BuscaTexto.normalizar(b)
    }

    private func salvar() {
        let entradas = entradas
        let anterior = gravacao
        gravacao = Task.detached(priority: .utility) {
            await anterior?.value
            guard let dados = try? JSONEncoder().encode(entradas) else { return }
            try? FileManager.default.createDirectory(at: URL.applicationSupportDirectory, withIntermediateDirectories: true)
            try? dados.write(to: Self.arquivo, options: .atomic)
        }
    }
}
