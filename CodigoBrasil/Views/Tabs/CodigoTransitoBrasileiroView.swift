import SwiftUI

/// Tela de navegação do Código de Trânsito Brasileiro — mesma experiência dos outros códigos (lista
/// agrupada, busca, favoritar), sem o seletor Texto Permanente/ADCT, que não existe nessa
/// lei.
struct CodigoTransitoBrasileiroView: View {
    /// Identifica o livro (também usado pela Biblioteca para saber se está baixado).
    static let slug = "codigo-transito-brasileiro-1997"
    /// Título do livro (também usado pela busca da Biblioteca).
    static let titulo = "Código de Trânsito Brasileiro"

    var body: some View {
        LeiArtigosView(leiSlug: Self.slug, titulo: Self.titulo)
    }
}

#Preview {
    NavigationStack {
        CodigoTransitoBrasileiroView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
    .environment(ArmazenamentoOffline())
}
