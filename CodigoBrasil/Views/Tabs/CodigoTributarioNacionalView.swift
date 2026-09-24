import SwiftUI

/// Tela de navegação do Código Tributário Nacional — mesma experiência dos outros códigos
/// (lista agrupada, busca, favoritar), sem o seletor Texto Permanente/ADCT, que não existe
/// nessa lei.
struct CodigoTributarioNacionalView: View {
    /// Identifica o livro (também usado pela Biblioteca para saber se está baixado).
    static let slug = "codigo-tributario-nacional-1966"
    /// Título do livro (também usado pela busca da Biblioteca).
    static let titulo = "Código Tributário Nacional"

    var body: some View {
        LeiArtigosView(leiSlug: Self.slug, titulo: Self.titulo)
    }
}

#Preview {
    NavigationStack {
        CodigoTributarioNacionalView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
    .environment(ArmazenamentoOffline())
}
