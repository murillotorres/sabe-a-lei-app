import SwiftUI

struct PrincipalView: View {
    @Environment(AuthStore.self) private var authStore
    @State private var isPresentingAuth = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Sabe a Lei")
                    .font(.largeTitle.bold())
                Text("Vade mecum digital")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                accountSection
                    .padding(.top, 24)

                Spacer()
            }
            .padding()
            .navigationTitle("Principal")
            .sheet(isPresented: $isPresentingAuth) {
                AuthView()
            }
        }
    }

    @ViewBuilder
    private var accountSection: some View {
        if let user = authStore.currentUser {
            VStack(spacing: 8) {
                Text("Olá, \(user.name)!")
                    .font(.headline)
                Button("Sair", role: .destructive) {
                    authStore.logout()
                }
            }
        } else {
            VStack(spacing: 12) {
                Text("Entre para acessar áreas exclusivas do app.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    isPresentingAuth = true
                } label: {
                    Label("Entrar ou criar conta", systemImage: "person.crop.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal)
        }
    }
}

#Preview {
    PrincipalView()
        .environment(AuthStore())
}
