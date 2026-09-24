import SwiftUI

/// Busca em toda a biblioteca (qualquer lei cadastrada, não só a Constituição),
/// usando o endpoint /busca. Hoje só a Constituição tem conteúdo carregado,
/// mas o resultado já mostra de qual lei cada artigo vem.
struct BuscarView: View {
    @State private var query = ""
    @State private var resultados: [Artigo] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            Group {
                if query.isEmpty {
                    ContentUnavailableView(
                        "Buscar",
                        systemImage: "magnifyingglass",
                        description: Text("Digite um termo para encontrar artigos em qualquer lei da biblioteca.")
                    )
                } else if isSearching && resultados.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if resultados.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ResultadosBuscaView(artigos: resultados)
                }
            }
            .navigationTitle("Buscar")
            .searchable(text: $query, prompt: "Buscar em toda a biblioteca")
            .task(id: query) {
                await buscar()
            }
        }
    }

    /// Mesmo debounce da busca dentro da Constituição: espera o usuário parar
    /// de digitar antes de bater no servidor.
    private func buscar() async {
        guard !query.isEmpty else {
            resultados = []
            isSearching = false
            return
        }

        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return
        }

        isSearching = true

        let encontrados: [Artigo]
        do {
            encontrados = try await LeisService.buscarGlobal(query: query)
        } catch {
            encontrados = []
        }

        guard !Task.isCancelled else { return }
        resultados = encontrados
        isSearching = false
    }
}

/// Lista de resultados — cada card mostra de qual lei veio, já que a busca
/// global (ao contrário da busca dentro de um artigo) pode achar em qualquer uma.
private struct ResultadosBuscaView: View {
    let artigos: [Artigo]

    @State private var artigoIdSelecionado: Int?

    var body: some View {
        List(artigos) { artigo in
            Button {
                artigoIdSelecionado = artigo.id
            } label: {
                ArtigoCardView(artigo: artigo, mostrarLei: true)
            }
            .buttonStyle(.plain)
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        }
        .listStyle(.plain)
        .navigationDestination(item: $artigoIdSelecionado) { id in
            if let artigo = artigos.first(where: { $0.id == id }) {
                ArtigoDetailView(artigoId: id, resumo: artigo)
            }
        }
    }
}

#Preview {
    BuscarView()
        .environment(AuthStore())
        .environment(FavoritosStore())
}
