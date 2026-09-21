import SwiftUI

struct PerfilView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var isPresentingAuth = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.secondary)

                        if let user = authStore.currentUser {
                            Text(user.name)
                                .font(.title3.bold())
                            Text(user.email)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Você não está logado")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                if authStore.isAuthenticated {
                    Section {
                        NavigationLink {
                            FavoritosView()
                        } label: {
                            Label("Favoritos", systemImage: "star.fill")
                        }
                    }

                    Section {
                        Button("Sair", role: .destructive) {
                            authStore.logout()
                        }
                    }
                } else {
                    Section {
                        Button {
                            isPresentingAuth = true
                        } label: {
                            Label("Entrar ou criar conta", systemImage: "person.crop.circle")
                        }
                    }
                }
            }
            .navigationTitle("Perfil")
            .sheet(isPresented: $isPresentingAuth) {
                AuthView()
            }
        }
    }
}

#Preview {
    PerfilView()
        .environment(AuthStore())
        .environment(FavoritosStore())
}
