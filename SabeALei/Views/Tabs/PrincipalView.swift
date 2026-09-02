import SwiftUI

struct PrincipalView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "book.closed.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("Sabe a Lei")
                    .font(.largeTitle.bold())
                Text("Vade mecum digital")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .navigationTitle("Principal")
        }
    }
}

#Preview {
    PrincipalView()
}
