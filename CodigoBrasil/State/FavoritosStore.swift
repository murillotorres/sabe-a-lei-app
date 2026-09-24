import Observation

/// Favoritos do usuário logado. Recarregado a cada login/logout pela tela que
/// os exibe; `alternar` é chamado a partir de qualquer botão de favoritar
/// (artigo ou parágrafo) espalhado pelo app.
@MainActor
@Observable
final class FavoritosStore {
    private(set) var favoritos: [Favorito] = []
    private(set) var isLoading = false
    var errorMessage: String?

    func carregar(token: String) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            favoritos = try await FavoritosService.listar(token: token).favoritos
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Não foi possível completar a solicitação."
        }
    }

    func limpar() {
        favoritos = []
    }

    func estaFavoritado(artigoId: Int, dispositivoId: Int?) -> Bool {
        favoritos.contains { $0.artigo.id == artigoId && $0.dispositivo?.id == dispositivoId }
    }

    func alternar(artigoId: Int, dispositivoId: Int?, token: String) async {
        errorMessage = nil

        if let favorito = favoritos.first(where: { $0.artigo.id == artigoId && $0.dispositivo?.id == dispositivoId }) {
            do {
                try await FavoritosService.remover(id: favorito.id, token: token)
                favoritos.removeAll { $0.id == favorito.id }
            } catch let error as APIError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = "Não foi possível completar a solicitação."
            }
            return
        }

        do {
            let novo = try await FavoritosService.criar(artigoId: artigoId, dispositivoId: dispositivoId, token: token)
            favoritos.insert(novo.favorito, at: 0)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Não foi possível completar a solicitação."
        }
    }
}
