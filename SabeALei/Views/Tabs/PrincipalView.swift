import SwiftUI

struct PrincipalView: View {
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
                    }

                    LazyVGrid(columns: colunas, spacing: 12) {
                        NavigationLink {
                            ConstituicaoView()
                        } label: {
                            HomeCardView(titulo: "Constituição", icone: "building.columns.fill", cor: .blue)
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            BibliotecaView()
                        } label: {
                            HomeCardView(titulo: "Biblioteca", icone: "books.vertical.fill", cor: .indigo)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Principal")
        }
    }
}

/// Atalho em formato de card — ícone + título, mesmo estilo em toda tela que
/// funcione como um hub de navegação (Principal, Biblioteca...).
struct HomeCardView: View {
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
    PrincipalView()
        .environment(AuthStore())
        .environment(FavoritosStore())
}
