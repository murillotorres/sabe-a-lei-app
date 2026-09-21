import SwiftUI

/// Hub com todas as leis do app — Constituição, Código Civil, Códigos,
/// Estatutos e a listagem geral. Ponto único de entrada pro conteúdo, no
/// lugar das abas separadas que existiam antes.
struct BibliotecaView: View {
    private let colunas = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: colunas, spacing: 12) {
                NavigationLink {
                    ConstituicaoView()
                } label: {
                    HomeCardView(titulo: "Constituição", icone: "building.columns.fill", cor: .blue)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CodigoCivilView()
                } label: {
                    HomeCardView(titulo: "Código Civil", icone: "building.2.fill", cor: .indigo)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CodigosView()
                } label: {
                    HomeCardView(titulo: "Códigos", icone: "books.vertical.fill", cor: .orange)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    EstatutosView()
                } label: {
                    HomeCardView(titulo: "Estatutos", icone: "doc.text.fill", cor: .teal)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    TodasLeisView()
                } label: {
                    HomeCardView(titulo: "Todas as Leis", icone: "list.bullet.rectangle.portrait.fill", cor: .purple)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Biblioteca")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        BibliotecaView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
}
