import SwiftUI

/// Tela de navegação do Código Penal — mesma experiência da Constituição e do
/// Código Civil (lista agrupada, busca, favoritar), sem o seletor Texto
/// Permanente/ADCT, que não existe nessa lei.
struct CodigoPenalView: View {
    var body: some View {
        LeiArtigosView(leiSlug: "codigo-penal-1940", titulo: "Código Penal")
    }
}

#Preview {
    NavigationStack {
        CodigoPenalView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
}
