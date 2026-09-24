import SwiftUI

/// Tela de navegação do Código Eleitoral — mesma experiência dos outros códigos (lista
/// agrupada, busca, favoritar), sem o seletor Texto Permanente/ADCT, que não existe nessa
/// lei.
struct CodigoEleitoralView: View {
    /// Identifica o livro (também usado pela Biblioteca para saber se está baixado).
    static let slug = "codigo-eleitoral-1965"
    /// Título do livro (também usado pela busca da Biblioteca).
    static let titulo = "Código Eleitoral"

    var body: some View {
        LeiArtigosView(leiSlug: Self.slug, titulo: Self.titulo)
    }
}

#Preview {
    NavigationStack {
        CodigoEleitoralView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
    .environment(ArmazenamentoOffline())
}
