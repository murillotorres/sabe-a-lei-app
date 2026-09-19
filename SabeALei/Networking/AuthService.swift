import Foundation

struct RegisterRequest: Encodable {
    let name: String
    let email: String
    let password: String
}

struct LoginRequest: Encodable {
    let email: String
    let password: String
}

struct AuthResponse: Decodable {
    let token: String
    let user: User
}

struct MeResponse: Decodable {
    let user: User
}

enum AuthService {
    static func register(name: String, email: String, password: String) async throws -> AuthResponse {
        try await APIClient.shared.post(
            "/auth/register",
            body: RegisterRequest(name: name, email: email, password: password)
        )
    }

    static func login(email: String, password: String) async throws -> AuthResponse {
        try await APIClient.shared.post(
            "/auth/login",
            body: LoginRequest(email: email, password: password)
        )
    }

    static func me(token: String) async throws -> MeResponse {
        try await APIClient.shared.get("/auth/me", token: token)
    }
}
