import SwiftUI

/// Tela de navegação do Código de Processo Civil — mesma experiência da
/// Constituição e dos outros códigos (lista agrupada, busca, favoritar), sem
/// o seletor Texto Permanente/ADCT, que não existe nessa lei.
struct CodigoProcessoCivilView: View {
    var body: some View {
        LeiArtigosView(leiSlug: "codigo-processo-civil-2015", titulo: "Código de Processo Civil")
    }
}

#Preview {
    NavigationStack {
        CodigoProcessoCivilView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
}
