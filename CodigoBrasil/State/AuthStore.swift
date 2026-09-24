import Observation

@MainActor
@Observable
final class AuthStore {
    private(set) var currentUser: User? {
        didSet {
            if let currentUser {
                UsuarioCache.salvar(currentUser)
            } else {
                UsuarioCache.limpar()
            }
        }
    }

    private(set) var isLoading = false
    var errorMessage: String?

    var isAuthenticated: Bool { currentUser != nil }

    private(set) var token: String? {
        didSet {
            if let token {
                KeychainStore.saveToken(token)
            } else {
                KeychainStore.deleteToken()
            }
        }
    }

    /// Restaura a sessão salva. Mostra na hora o que já se sabe localmente
    /// (funciona sem internet) e só desloga de verdade se o servidor
    /// responder dizendo que o token não vale mais — um erro de rede não
    /// deve tirar o usuário logado, só um token efetivamente inválido/expirado.
    func restoreSession() async {
        guard let savedToken = KeychainStore.loadToken() else { return }

        token = savedToken
        currentUser = UsuarioCache.carregar()

        isLoading = true
        defer { isLoading = false }

        do {
            currentUser = try await AuthService.me(token: savedToken).user
        } catch let error as APIError {
            if case .server(_, 401) = error {
                logout()
            }
        } catch {
            // Sem internet, timeout etc. — mantém a sessão com os dados em
            // cache e tenta atualizar de novo na próxima abertura do app.
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
