import SwiftUI

/// Tela de navegação do Código Civil — mesma experiência da Constituição
/// (lista agrupada, busca, favoritar), só sem o seletor Texto Permanente/ADCT,
/// que não existe nessa lei (é tudo uma "parte" só).
struct CodigoCivilView: View {
    /// Identifica o livro (também usado pela Biblioteca para saber se está baixado).
    static let slug = "codigo-civil-2002"
    /// Título do livro (também usado pela busca da Biblioteca).
    static let titulo = "Código Civil"

    var body: some View {
        LeiArtigosView(leiSlug: Self.slug, titulo: Self.titulo)
    }
}

#Preview {
    NavigationStack {
        CodigoCivilView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
}
