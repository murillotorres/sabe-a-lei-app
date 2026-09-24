import SwiftUI

struct MainTabView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(FavoritosStore.self) private var favoritosStore

    var body: some View {
        TabView {
            PrincipalView()
                .tabItem {
                    Label("Principal", systemImage: "house.fill")
                }

            // BibliotecaView não tem NavigationStack próprio (também é empilhada
            // a partir do card na Principal), então precisa de um aqui como raiz da aba.
            NavigationStack {
                BibliotecaView()
            }
            .tabItem {
                Label("Biblioteca", systemImage: "books.vertical.fill")
            }

            BuscarView()
                .tabItem {
                    Label("Buscar", systemImage: "magnifyingglass")
                }

            PerfilView()
                .tabItem {
                    Label("Perfil", systemImage: "person.crop.circle.fill")
                }
        }
        .task(id: authStore.currentUser?.id) {
            if let token = authStore.token {
                await favoritosStore.carregar(token: token)
            } else {
                favoritosStore.limpar()
            }
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthStore())
        .environment(FavoritosStore())
        .environment(ArmazenamentoOffline())
}
