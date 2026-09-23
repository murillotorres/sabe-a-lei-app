import SwiftUI

/// Tela com todos os artigos/parágrafos favoritados pelo usuário logado.
/// A lista em si já vive em `FavoritosStore`, mantida sincronizada pelo
/// `MainTabView` — aqui só exibimos o que já está carregado.
struct FavoritosView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(FavoritosStore.self) private var favoritosStore
    @State private var isPresentingAuth = false

    var body: some View {
        Group {
            if !authStore.isAuthenticated {
                ContentUnavailableView {
                    Label("Entre para ver seus favoritos", systemImage: "star")
                } actions: {
                    Button("Entrar ou criar conta") {
                        isPresentingAuth = true
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else if favoritosStore.isLoading && favoritosStore.favoritos.isEmpty {
                ProgressView()
            } else if favoritosStore.favoritos.isEmpty {
                ContentUnavailableView(
                    "Nenhum favorito ainda",
                    systemImage: "star",
                    description: Text("Toque na estrela de um artigo para favoritá-lo.")
                )
            } else {
                List {
                    ForEach(favoritosStore.favoritos) { favorito in
                        NavigationLink {
                            ArtigoDetailView(artigoId: favorito.artigo.id, resumo: favorito.artigo)
                        } label: {
                            FavoritoRowView(favorito: favorito)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Favoritos")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isPresentingAuth) {
            AuthView()
        }
    }
}

/// Uma linha de favorito: o artigo (título + caput) e, se for um parágrafo
/// favoritado (não o artigo inteiro), o mesmo destaque amarelo usado na busca.
private struct FavoritoRowView: View {
    let favorito: Favorito

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(favorito.artigo.titulo)
                    .font(.headline)
                    .foregroundStyle(.tint)
                if favorito.artigo.revogado {
                    Text("Revogado")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            Text(favorito.artigo.caput)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(favorito.dispositivo == nil ? 4 : 2)

            if let dispositivo = favorito.dispositivo {
                TrechoCorrespondenteView(
                    trecho: TrechoCorrespondente(tipo: dispositivo.tipo, rotulo: dispositivo.rotulo, texto: dispositivo.texto)
                )
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        FavoritosView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
}
