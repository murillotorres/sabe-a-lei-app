import SwiftUI

struct AuthView: View {
    private enum Mode: String, CaseIterable {
        case login = "Entrar"
        case register = "Criar conta"
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore
    @State private var mode: Mode = .login

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Modo", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                switch mode {
                case .login:
                    LoginForm()
                case .register:
                    RegisterForm()
                }
            }
            .navigationTitle(mode.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fechar") { dismiss() }
                }
            }
            .onChange(of: authStore.isAuthenticated) { _, isAuthenticated in
                if isAuthenticated { dismiss() }
            }
            .onChange(of: mode) {
                authStore.errorMessage = nil
            }
        }
    }
}

#Preview {
    AuthView()
        .environment(AuthStore())
}
