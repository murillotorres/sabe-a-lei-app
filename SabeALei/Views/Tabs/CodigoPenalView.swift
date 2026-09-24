import SwiftUI

/// Tela de navegação do Código Penal — mesma experiência da Constituição e do
/// Código Civil (lista agrupada, busca, favoritar), sem o seletor Texto
/// Permanente/ADCT, que não existe nessa lei.
struct CodigoPenalView: View {
    /// Identifica o livro (também usado pela Biblioteca para saber se está baixado).
    static let slug = "codigo-penal-1940"

    var body: some View {
        LeiArtigosView(leiSlug: Self.slug, titulo: "Código Penal")
    }
}

#Preview {
    NavigationStack {
        CodigoPenalView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
}
