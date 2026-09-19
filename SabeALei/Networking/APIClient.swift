import Foundation

struct APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        self.decoder = decoder

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        self.encoder = encoder
    }

    func get<Response: Decodable>(
        _ path: String,
        query: [String: String] = [:],
        token: String? = nil
    ) async throws -> Response {
        try await send(path: path, method: "GET", body: Optional<EmptyBody>.none, query: query, token: token)
    }

    func post<Body: Encodable, Response: Decodable>(
        _ path: String,
        body: Body,
        token: String? = nil
    ) async throws -> Response {
        try await send(path: path, method: "POST", body: body, token: token)
    }

    private func send<Body: Encodable, Response: Decodable>(
        path: String,
        method: String,
        body: Body?,
        query: [String: String] = [:],
        token: String?
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

        let (data, response) = try await session.data(for: request)

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

private struct EmptyBody: Encodable {}

private struct APIErrorBody: Decodable {
    let error: String
}
