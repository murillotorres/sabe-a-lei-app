import SwiftUI

/// Tela de navegação do Código de Processo Penal Militar — mesma experiência dos outros códigos (lista
/// agrupada, busca, favoritar), sem o seletor Texto Permanente/ADCT, que não existe nessa
/// lei.
struct CodigoProcessoPenalMilitarView: View {
    /// Identifica o livro (também usado pela Biblioteca para saber se está baixado).
    static let slug = "codigo-processo-penal-militar-1969"
    /// Título do livro (também usado pela busca da Biblioteca).
    static let titulo = "Código de Processo Penal Militar"

    var body: some View {
        LeiArtigosView(leiSlug: Self.slug, titulo: Self.titulo)
    }
}

#Preview {
    NavigationStack {
        CodigoProcessoPenalMilitarView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
    .environment(ArmazenamentoOffline())
}
