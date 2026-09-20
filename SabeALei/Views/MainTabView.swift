import SwiftUI

/// Identifica cada aba, pra permitir pular pra uma delas por código (ex.: o
/// card "Constituição" na home) sem depender de índices soltos.
enum AbaPrincipal: Hashable {
    case principal
    case constituicao
    case codigos
    case estatutos
    case todasAsLeis
}

struct MainTabView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(FavoritosStore.self) private var favoritosStore
    @State private var abaSelecionada: AbaPrincipal = .principal

    var body: some View {
        TabView(selection: $abaSelecionada) {
            PrincipalView(abaSelecionada: $abaSelecionada)
                .tabItem {
                    Label("Principal", systemImage: "house.fill")
                }
                .tag(AbaPrincipal.principal)

            ConstituicaoView()
                .tabItem {
                    Label("Constituição", systemImage: "building.columns.fill")
                }
                .tag(AbaPrincipal.constituicao)

            CodigosView()
                .tabItem {
                    Label("Códigos", systemImage: "books.vertical.fill")
                }
                .tag(AbaPrincipal.codigos)

            EstatutosView()
                .tabItem {
                    Label("Estatutos", systemImage: "doc.text.fill")
                }
                .tag(AbaPrincipal.estatutos)

            TodasLeisView()
                .tabItem {
                    Label("Todas as Leis", systemImage: "list.bullet.rectangle.portrait.fill")
                }
                .tag(AbaPrincipal.todasAsLeis)
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
}
