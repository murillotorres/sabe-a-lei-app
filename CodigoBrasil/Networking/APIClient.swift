import Foundation

struct APIClient {
    static let shared = APIClient()

    private let session: URLSession
    /// Sessão do trabalho de fundo (offline/sincronização): serviço de rede
    /// `.background` (o sistema a coloca atrás do tráfego da interface), uma
    /// conexão por host e espera pela conexão em vez de falhar na hora.
    private let sessaoDeFundo: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session

        let configuracaoDeFundo = URLSessionConfiguration.default
        configuracaoDeFundo.networkServiceType = .background
        configuracaoDeFundo.waitsForConnectivity = true
        configuracaoDeFundo.timeoutIntervalForResource = 120
        configuracaoDeFundo.httpMaximumConnectionsPerHost = 1
        self.sessaoDeFundo = URLSession(configuration: configuracaoDeFundo)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        // A API espera e devolve tudo em camelCase (ver Request::input em
        // FavoritoController, por ex.) — sem conversão, igual ao decoder.
        self.encoder = JSONEncoder()
    }

    func get<Response: Decodable>(
        _ path: String,
        query: [String: String] = [:],
        token: String? = nil,
        prioridade: PrioridadeDeRede = .alta
    ) async throws -> Response {
        try await send(
            path: path, method: "GET", body: Optional<EmptyBody>.none,
            query: query, token: token, prioridade: prioridade
        )
    }

    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        token: String? = nil
    ) async throws -> Response {
        try await send(path: path, method: "POST", body: body, token: token)
    }

    func delete<Response: Decodable>(
        _ path: String,
        token: String? = nil
    ) async throws -> Response {
        try await send(path: path, method: "DELETE", body: Optional<EmptyBody>.none, token: token)
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?,
        query: [String: String] = [:],
        token: String?,
        prioridade: PrioridadeDeRede = .alta
    ) async throws -> Response {
        var url = APIConfig.baseURL.appending(path: path)
        if !query.isEmpty {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
            url = components?.url ?? url
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await executar(request, prioridade: prioridade)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = (try? decoder.decode(APIErrorBody.self, from: data))?.error ?? "Erro inesperado."
            throw APIError.server(message: message, status: httpResponse.statusCode)
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIError.decoding
        }
    }
}

extension APIClient {
    /// Requisição de prioridade alta passa direto (e avisa `AtividadeDeRede`);
    /// a de prioridade baixa espera a rede ficar ociosa e usa a sessão de fundo.
    fileprivate func executar(_ request: URLRequest, prioridade: PrioridadeDeRede) async throws -> (Data, URLResponse) {
        switch prioridade {
        case .alta:
            await AtividadeDeRede.shared.altaIniciou()
            do {
                let resultado = try await session.data(for: request)
                await AtividadeDeRede.shared.altaTerminou()
                return resultado
            } catch {
                await AtividadeDeRede.shared.altaTerminou()
                throw error
            }
        case .baixa:
            try await AtividadeDeRede.shared.aguardarOciosa()
            var requisicaoDeFundo = request
            requisicaoDeFundo.networkServiceType = .background
            return try await sessaoDeFundo.data(for: requisicaoDeFundo)
        }
    }
}

private struct EmptyBody: Encodable {}

private struct APIErrorBody: Decodable {
    let error: String
}
