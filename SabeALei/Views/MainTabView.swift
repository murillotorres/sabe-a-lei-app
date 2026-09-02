import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            PrincipalView()
                .tabItem {
                    Label("Principal", systemImage: "house.fill")
                }

            ConstituicaoView()
                .tabItem {
                    Label("Constituição", systemImage: "building.columns.fill")
                }

            CodigosView()
                .tabItem {
                    Label("Códigos", systemImage: "books.vertical.fill")
                }

            EstatutosView()
                .tabItem {
                    Label("Estatutos", systemImage: "doc.text.fill")
                }

            TodasLeisView()
                .tabItem {
                    Label("Todas as Leis", systemImage: "list.bullet.rectangle.portrait.fill")
                }
        }
    }
}

#Preview {
    MainTabView()
}
