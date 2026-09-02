import SwiftUI

struct ConstituicaoView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Constituição",
                systemImage: "building.columns.fill",
                description: Text("Em breve.")
            )
            .navigationTitle("Constituição")
        }
    }
}

#Preview {
    ConstituicaoView()
}
