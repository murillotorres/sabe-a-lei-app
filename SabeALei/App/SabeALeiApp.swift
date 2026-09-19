import SwiftUI

@main
struct SabeALeiApp: App {
    @State private var authStore = AuthStore()

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(authStore)
                .task {
                    await authStore.restoreSession()
                }
        }
    }
}
