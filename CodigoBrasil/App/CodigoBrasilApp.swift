import SwiftUI

@main
struct CodigoBrasilApp: App {
    @State private var authStore = AuthStore()
    @State private var favoritosStore = FavoritosStore()
    @State private var armazenamento = ArmazenamentoOffline()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(authStore)
                .environment(favoritosStore)
                .environment(armazenamento)
                .task {
                    await authStore.restoreSession()
                }
        }
        .onChange(of: scenePhase, initial: true) { _, fase in
            // O primeiro teclado do processo é caro de carregar; paga isso agora,
            // com o app parado, e não no primeiro toque na busca.
            if fase == .active {
                TecladoPreAquecido.agendar()
                // Verifica atualizações dos livros offline em segundo plano — nunca segura a interface.
                armazenamento.aoFicarAtivo()
            }
        }
    }
}
