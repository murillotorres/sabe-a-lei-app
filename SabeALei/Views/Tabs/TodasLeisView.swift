import SwiftUI

struct TodasLeisView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Todas as Leis",
                systemImage: "list.bullet.rectangle.portrait.fill",
                description: Text("Em breve.")
            )
            .navigationTitle("Todas as Leis")
        }
    }
}

#Preview {
    TodasLeisView()
}
