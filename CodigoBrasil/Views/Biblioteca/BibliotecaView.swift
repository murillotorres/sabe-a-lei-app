import SwiftUI

/// Hub com todas as leis do app. Ponto único de entrada pro conteúdo, no
/// lugar das abas separadas que existiam antes.
struct BibliotecaView: View {
    @Environment(ArmazenamentoOffline.self) private var armazenamento

    private let colunas = [GridItem(.flexible()), GridItem(.flexible())]

    /// O livro está salvo no aparelho e disponível offline?
    private func baixado(_ slug: String) -> Bool {
        armazenamento.estado(de: slug).disponivelOffline
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: colunas, spacing: 12) {
                NavigationLink {
                    ConstituicaoView()
                } label: {
                    HomeCardView(titulo: "Constituição", icone: "building.columns.fill", cor: .blue, baixado: baixado(ConstituicaoView.slug))
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CodigoCivilView()
                } label: {
                    HomeCardView(titulo: "Código Civil", icone: "building.2.fill", cor: .indigo, baixado: baixado(CodigoCivilView.slug))
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CodigoPenalView()
                } label: {
                    HomeCardView(titulo: "Código Penal", icone: "exclamationmark.shield.fill", cor: .red, baixado: baixado(CodigoPenalView.slug))
                }
                .buttonStyle(.plain)

                NavigationLink {
                    CodigoProcessoCivilView()
                } label: {
                    HomeCardView(titulo: "Processo Civil", icone: "list.bullet.clipboard.fill", cor: .green, baixado: baixado(CodigoProcessoCivilView.slug))
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
    .environment(ArmazenamentoOffline())
}
