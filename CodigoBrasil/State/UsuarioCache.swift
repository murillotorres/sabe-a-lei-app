import Foundation

/// Última foto conhecida do usuário logado, em UserDefaults — ao contrário do
/// token (Keychain), não é segredo. Permite restaurar a sessão (nome, etc.)
/// e liberar as áreas exclusivas do app mesmo com o aparelho sem internet.
enum UsuarioCache {
    private static let chave = "usuarioEmCache"

    static func salvar(_ usuario: User) {
        guard let dados = try? JSONEncoder().encode(usuario) else { return }
        UserDefaults.standard.set(dados, forKey: chave)
    }

    static func carregar() -> User? {
        guard let dados = UserDefaults.standard.data(forKey: chave) else { return nil }
        return try? JSONDecoder().decode(User.self, from: dados)
    }

    static func limpar() {
        UserDefaults.standard.removeObject(forKey: chave)
    }
}
