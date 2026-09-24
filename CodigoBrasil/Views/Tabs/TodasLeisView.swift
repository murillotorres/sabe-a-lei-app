import SwiftUI

struct TodasLeisView: View {
    var body: some View {
        ContentUnavailableView(
            "Todas as Leis",
            systemImage: "list.bullet.rectangle.portrait.fill",
            description: Text("Em breve.")
        )
        .navigationTitle("Todas as Leis")
    }
}

#Preview {
    NavigationStack {
        TodasLeisView()
    }
}
