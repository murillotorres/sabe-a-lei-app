import SwiftUI

struct CodigosView: View {
    var body: some View {
        ContentUnavailableView(
            "Códigos",
            systemImage: "books.vertical.fill",
            description: Text("Em breve.")
        )
        .navigationTitle("Códigos")
    }
}

#Preview {
    NavigationStack {
        CodigosView()
    }
}
