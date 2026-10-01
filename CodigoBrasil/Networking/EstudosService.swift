import Foundation

/// Grifos e anotações: uma chamada só, que envia as alterações do aparelho e
/// traz as do servidor desde a revisão `desde` (ver `EstudosStore`).
enum EstudosService {
    static func sincronizar(_ corpo: SincronizacaoDeEstudos, token: String) async throws -> RespostaDaSincronizacao {
        try await APIClient.shared.post(
            "/estudos/sync", body: corpo, token: token, prioridade: .baixa,
            codificador: codificador, decodificador: decodificador
        )
    }

    /// Datas em ISO 8601 com milissegundos, nos dois sentidos — é com elas que o
    /// servidor decide qual alteração vence. Também usados no arquivo local.
    static let codificador: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { data, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(data))
        }
        return encoder
    }()

    static let decodificador: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let texto = try decoder.singleValueContainer().decode(String.self)
            let comFracao = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            if let data = try? comFracao.parse(texto) { return data }
            return try Date.ISO8601FormatStyle().parse(texto)
        }
        return decoder
    }()
}
