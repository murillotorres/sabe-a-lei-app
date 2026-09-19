import SwiftUI

private let constituicaoSlug = "constituicao-federal-1988"

struct ConstituicaoView: View {
    @State private var parte: ParteConstitucional = .permanente
    @State private var artigos: [Artigo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedParte: ParteConstitucional?

    @State private var isSearching = false
    @State private var searchText = ""
    @State private var searchResults: [Artigo] = []
    @State private var isSearchingRemote = false
    @FocusState private var searchFieldFocused: Bool

    private var displayedArtigos: [Artigo] {
        guard !searchText.isEmpty else { return artigos }

        // "5", "art 5", "art. 5" ou "a5" busca o artigo específico, não um texto solto.
        if let numero = Self.numeroReferenciado(searchText) {
            return artigos.filter { $0.numero == numero }
        }

        // Texto solto: busca no servidor, que olha também o conteúdo dos
        // dispositivos (parágrafos/incisos/alíneas), não só o caput.
        return searchResults
    }

    /// Reconhece referências a um artigo específico ("5", "art5", "art 5", "art. 5",
    /// "a5", "103-A"...) e devolve o número normalizado, ou `nil` se o texto não for isso.
    private static func numeroReferenciado(_ texto: String) -> String? {
        let trimmed = texto.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        guard let match = trimmed.wholeMatch(of: /(?:art\.?|a\.?)?\s*(\d+)(?:-([a-zA-Z]))?/.ignoresCase()) else {
            return nil
        }

        let numero = String(match.1)
        guard let letra = match.2 else { return numero }
        return "\(numero)-\(letra.uppercased())"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header

                Picker("Parte", selection: $parte) {
                    ForEach(ParteConstitucional.allCases, id: \.self) { parte in
                        Text(parte.titulo).tag(parte)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                content
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .task(id: parte) {
                await load()
            }
            .task(id: "\(parte.rawValue)|\(searchText)") {
                await search()
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 12) {
            if isSearching {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Buscar por número ou texto...", text: $searchText)
                        .focused($searchFieldFocused)
                        .submitLabel(.search)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(8)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))

                Button("Cancelar") {
                    withAnimation {
                        isSearching = false
                        searchFieldFocused = false
                    }
                    searchText = ""
                }
            } else {
                Text("Constituição")
                    .font(.largeTitle.bold())
                Spacer()
                Button {
                    withAnimation {
                        isSearching = true
                    }
                    searchFieldFocused = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                }
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .animation(.default, value: isSearching)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && loadedParte != parte {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Não foi possível carregar", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Tentar novamente") {
                    Task { await load(force: true) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if isSearchingRemote && searchResults.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !searchText.isEmpty && displayedArtigos.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ArtigoListView(artigos: displayedArtigos)
        }
    }

    /// Busca no servidor com debounce: só dispara a requisição depois que o
    /// usuário pausa a digitação, e descarta o resultado se o texto já tiver
    /// mudado (ou virado uma referência a artigo) nesse meio-tempo.
    private func search() async {
        guard !searchText.isEmpty, Self.numeroReferenciado(searchText) == nil else {
            searchResults = []
            isSearchingRemote = false
            return
        }

        do {
            try await Task.sleep(nanoseconds: 300_000_000)
        } catch {
            return
        }

        isSearchingRemote = true

        let resultado: [Artigo]
        do {
            let response = try await LeisService.artigos(leiSlug: constituicaoSlug, parte: parte, busca: searchText)
            resultado = response.artigos
        } catch {
            resultado = []
        }

        guard !Task.isCancelled else { return }
        searchResults = resultado
        isSearchingRemote = false
    }

    private func load(force: Bool = false) async {
        if !force && loadedParte == parte { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await LeisService.artigos(leiSlug: constituicaoSlug, parte: parte)
            artigos = response.artigos
            loadedParte = parte
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Não foi possível completar a solicitação."
        }
    }
}

/// Lista os artigos em cards, agrupados pelo título/capítulo/seção estrutural quando disponível.
struct ArtigoListView: View {
    let artigos: [Artigo]

    private var grupos: [(titulo: String?, artigos: [Artigo])] {
        var result: [(titulo: String?, artigos: [Artigo])] = []
        for artigo in artigos {
            if !result.isEmpty && result[result.count - 1].titulo == artigo.grupoEstrutural {
                result[result.count - 1].artigos.append(artigo)
            } else {
                result.append((artigo.grupoEstrutural, [artigo]))
            }
        }
        return result
    }

    var body: some View {
        List {
            ForEach(Array(grupos.enumerated()), id: \.offset) { _, grupo in
                Section {
                    ForEach(grupo.artigos) { artigo in
                        NavigationLink {
                            ArtigoDetailView(artigoId: artigo.id, resumo: artigo)
                        } label: {
                            ArtigoCardView(artigo: artigo)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } header: {
                    if let titulo = grupo.titulo {
                        Text(titulo)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

struct ArtigoCardView: View {
    let artigo: Artigo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(artigo.titulo)
                    .font(.headline)
                    .foregroundStyle(.tint)
                if artigo.revogado {
                    Text("Revogado")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            Text(artigo.caput)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ConstituicaoView()
}
