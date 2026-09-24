import SwiftUI

/// Tela de navegação do Código de Processo Civil — mesma experiência da
/// Constituição e dos outros códigos (lista agrupada, busca, favoritar), sem
/// o seletor Texto Permanente/ADCT, que não existe nessa lei.
struct CodigoProcessoCivilView: View {
    /// Identifica o livro (também usado pela Biblioteca para saber se está baixado).
    static let slug = "codigo-processo-civil-2015"
    /// Título do livro (também usado pela busca da Biblioteca).
    static let titulo = "Código de Processo Civil"

    var body: some View {
        LeiArtigosView(leiSlug: Self.slug, titulo: Self.titulo)
    }
}

#Preview {
    NavigationStack {
        CodigoProcessoCivilView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
}
