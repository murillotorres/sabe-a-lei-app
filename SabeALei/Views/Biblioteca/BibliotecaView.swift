import SwiftUI

/// Hub com todas as leis do app. Ponto único de entrada pro conteúdo, no
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
                    CodigoPenalView()
                } label: {
                    HomeCardView(titulo: "Código Penal", icone: "exclamationmark.shield.fill", cor: .red)
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CodigoProcessoCivilView()
                } label: {
                    HomeCardView(titulo: "Processo Civil", icone: "list.bullet.clipboard.fill", cor: .green)
                }
                .buttonStyle(.plain)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Biblioteca Jurídica")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        BibliotecaView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
}
