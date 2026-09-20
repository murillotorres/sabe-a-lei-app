import SwiftUI

struct PrincipalView: View {
    @Environment(AuthStore.self) private var authStore
    @Binding var abaSelecionada: AbaPrincipal
    @State private var isPresentingAuth = false

    private let colunas = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
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
                    }

                    LazyVGrid(columns: colunas, spacing: 12) {
                        // Pula pra aba Constituição em vez de empilhar a tela aqui:
                        // ConstituicaoView já tem seu próprio NavigationStack, e o
                        // SwiftUI não suporta aninhar um NavigationStack dentro do outro.
                        Button {
                            abaSelecionada = .constituicao
                        } label: {
                            HomeCardView(titulo: "Constituição", icone: "building.columns.fill", cor: .blue)
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            FavoritosView()
                        } label: {
                            HomeCardView(titulo: "Favoritos", icone: "star.fill", cor: .yellow)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
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

/// Atalho da home em formato de card — ícone + título, mesmo estilo pros
/// vários destinos (Constituição, Favoritos, e o que mais entrar depois).
private struct HomeCardView: View {
    let titulo: String
    let icone: String
    var cor: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: icone)
                .font(.title2)
                .foregroundStyle(cor)
            Text(titulo)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

#Preview {
    PrincipalView(abaSelecionada: .constant(.principal))
        .environment(AuthStore())
        .environment(FavoritosStore())
}
