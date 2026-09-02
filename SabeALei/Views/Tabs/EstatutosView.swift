import SwiftUI

struct EstatutosView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Estatutos",
                systemImage: "doc.text.fill",
                description: Text("Em breve.")
            )
            .navigationTitle("Estatutos")
        }
    }
}

#Preview {
    EstatutosView()
}
