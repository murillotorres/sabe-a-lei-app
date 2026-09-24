import Foundation

/// Prioridade de uma requisição. `alta` é tudo que a tela que o usuário está
/// vendo precisa; `baixa` é trabalho de fundo (armazenamento offline,
/// verificação de atualizações) e nunca deve competir com a `alta`.
enum PrioridadeDeRede: Sendable {
    case alta
    case baixa
}

/// Controle de quem está usando a rede agora. Requisições de prioridade alta se
/// registram aqui; as de prioridade baixa só começam quando não há nenhuma em
/// andamento e a rede ficou quieta por uma pequena folga (a tela costuma
/// encadear pedidos, e esperar a folga evita entrar no meio de uma sequência).
actor AtividadeDeRede {
    static let shared = AtividadeDeRede()

    private var altasEmAndamento = 0
    private var ultimaAtividade: ContinuousClock.Instant = .now - .seconds(60)

    func altaIniciou() {
        altasEmAndamento += 1
        ultimaAtividade = .now
    }

    func altaTerminou() {
        altasEmAndamento = max(0, altasEmAndamento - 1)
        ultimaAtividade = .now
    }

    /// Suspende até a rede ficar ociosa. Lança `CancellationError` se a tarefa
    /// que espera for cancelada. Só uma checagem curta enquanto espera — não é
    /// um relógio de sincronização, e sem tarefa de fundo pendente não roda nada.
    func aguardarOciosa(folga: Duration = .seconds(1)) async throws {
        while altasEmAndamento > 0 || ContinuousClock.now - ultimaAtividade < folga {
            try await Task.sleep(for: .milliseconds(250))
        }
    }
}
