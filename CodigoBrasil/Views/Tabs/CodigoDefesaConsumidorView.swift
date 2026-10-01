import SwiftUI

/// Tela de navegação do Código de Defesa do Consumidor — mesma experiência dos outros códigos (lista
/// agrupada, busca, favoritar), sem o seletor Texto Permanente/ADCT, que não existe nessa
/// lei.
struct CodigoDefesaConsumidorView: View {
    /// Identifica o livro (também usado pela Biblioteca para saber se está baixado).
    static let slug = "codigo-defesa-consumidor-1990"
    /// Título do livro (também usado pela busca da Biblioteca).
    static let titulo = "Código de Defesa do Consumidor"

    var body: some View {
        LeiArtigosView(leiSlug: Self.slug, titulo: Self.titulo)
    }
}

#Preview {
    NavigationStack {
        CodigoDefesaConsumidorView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
    .environment(ArmazenamentoOffline())
}
