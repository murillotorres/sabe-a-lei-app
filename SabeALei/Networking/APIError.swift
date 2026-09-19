import Foundation

enum APIError: LocalizedError {
    case invalidResponse
    case server(message: String, status: Int)
    case decoding

    var errorDescription: String? {
        switch self {
        case .invalidResponse, .decoding:
            return "Não foi possível completar a solicitação. Tente novamente."
        case .server(let message, _):
            return message
        }
    }
}
