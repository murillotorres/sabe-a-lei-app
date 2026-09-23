import SwiftUI

@main
struct SabeALeiApp: App {
    @State private var authStore = AuthStore()
    @State private var favoritosStore = FavoritosStore()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(authStore)
                .environment(favoritosStore)
                .task {
                    await authStore.restoreSession()
                }
        }
        .onChange(of: scenePhase, initial: true) { _, fase in
            // O primeiro teclado do processo é caro de carregar; paga isso agora,
            // com o app parado, e não no primeiro toque na busca.
            if fase == .active { TecladoPreAquecido.agendar() }
        }
    }
}
