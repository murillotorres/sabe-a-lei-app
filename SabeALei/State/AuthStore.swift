import Observation

@MainActor
@Observable
final class AuthStore {
    private(set) var currentUser: User?
    private(set) var isLoading = false
    var errorMessage: String?

    var isAuthenticated: Bool { currentUser != nil }

    private var token: String? {
        didSet {
            if let token {
                KeychainStore.saveToken(token)
            } else {
                KeychainStore.deleteToken()
            }
        }
    }

    func restoreSession() async {
        guard let savedToken = KeychainStore.loadToken() else { return }

        isLoading = true
        defer { isLoading = false }

        do {
            let response = try await AuthService.me(token: savedToken)
            token = savedToken
            currentUser = response.user
        } catch {
            KeychainStore.deleteToken()
        }
    }

    func register(name: String, email: String, password: String) async {
        await perform {
            let response = try await AuthService.register(name: name, email: email, password: password)
            self.token = response.token
            self.currentUser = response.user
        }
    }

    func login(email: String, password: String) async {
        await perform {
            let response = try await AuthService.login(email: email, password: password)
            self.token = response.token
            self.currentUser = response.user
        }
    }

    func logout() {
        token = nil
        currentUser = nil
    }

    private func perform(_ action: () async throws -> Void) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            try await action()
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Não foi possível completar a solicitação."
        }
    }
}
