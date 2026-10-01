import SwiftUI

/// Tela de navegação do Código Penal Militar — mesma experiência dos outros códigos (lista
/// agrupada, busca, favoritar), sem o seletor Texto Permanente/ADCT, que não existe nessa
/// lei.
struct CodigoPenalMilitarView: View {
    /// Identifica o livro (também usado pela Biblioteca para saber se está baixado).
    static let slug = "codigo-penal-militar-1969"
    /// Título do livro (também usado pela busca da Biblioteca).
    static let titulo = "Código Penal Militar"

    var body: some View {
        LeiArtigosView(leiSlug: Self.slug, titulo: Self.titulo)
    }
}

#Preview {
    NavigationStack {
        CodigoPenalMilitarView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
    .environment(ArmazenamentoOffline())
}
