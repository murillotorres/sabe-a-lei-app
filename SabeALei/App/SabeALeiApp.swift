import SwiftUI

@main
struct SabeALeiApp: App {
    @State private var authStore = AuthStore()
    @State private var favoritosStore = FavoritosStore()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(authStore)
                .environment(favoritosStore)
                .task {
                    await authStore.restoreSession()
                }
        }
    }
}
