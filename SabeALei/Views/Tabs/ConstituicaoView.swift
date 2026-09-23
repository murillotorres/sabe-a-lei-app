import SwiftUI

struct ConstituicaoView: View {
    var body: some View {
        LeiArtigosView(leiSlug: "constituicao-federal-1988", titulo: "Constituição", mostrarSeletorParte: true)
    }
}

/// Tela de navegação de uma lei — usada tanto pela Constituição (com o seletor
/// Texto Permanente/ADCT) quanto pelo Código Civil e outras leis de "parte"
/// única (sem o seletor, sempre `permanente`).
struct LeiArtigosView: View {
    let leiSlug: String
    let titulo: String
    var mostrarSeletorParte: Bool = false

    @State private var parte: ParteConstitucional = .permanente
    @State private var artigos: [Artigo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedParte: ParteConstitucional?

    @State private var searchText = ""
    @State private var searchResults: [Artigo] = []
    @State private var isSearchingRemote = false
    @State private var isSearchActive = false
    @FocusState private var isSearchFieldFocused: Bool

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

    /// Botão de busca da navigation bar. Nenhum `.buttonStyle` é aplicado
    /// aqui de propósito: dentro de um `ToolbarItem`, o próprio sistema já
    /// desenha o vidro (Liquid Glass) automaticamente a partir do iOS 26 —
    /// igual ao botão voltar, que também não tem estilo nenhum. Aplicar
    /// `.buttonStyle(.glass)` por cima duplicava o efeito (dois círculos
    /// concêntricos, um do toolbar e outro do botão).
    private var botaoDeBusca: some View {
        Button {
            ativarBusca()
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("Pesquisar")
    }

    private func ativarBusca() {
        isSearchFieldFocused = true
        withAnimation(.snappy(duration: 0.25)) {
            isSearchActive = true
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if mostrarSeletorParte {
                Picker("Parte", selection: $parte) {
                    ForEach(ParteConstitucional.allCases, id: \.self) { parte in
                        Text(parte.titulo).tag(parte)
                    }
                }
                .pickerStyle(.segmented)
                .padding()
            }

            content
        }
        // Voltar e título ficam 100% nativos (navigation bar do sistema) — no
        // iOS 26 isso já dá o botão voltar no estilo "Liquid Glass" padrão,
        // sem precisar recriar nada na mão.
        .navigationTitle(titulo)
        .navigationBarTitleDisplayMode(.inline)
        // O botão de busca é próprio (não `.searchable`) pra ficar na mesma
        // navigation bar do voltar: a partir do iOS 26, `.searchable` sem
        // placement customizado passou a ancorar um campo flutuante no
        // rodapé da tela (padrão novo do sistema), separado do voltar.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                botaoDeBusca
            }
        }
        // O campo de busca some assim que ativado, no lugar de qualquer
        // outro conteúdo fixo — a localização estrutural (Parte/Título/
        // Capítulo) não é mais um header separado aqui: é o cabeçalho nativo
        // de cada `Section` da lista (ver `ArtigoListView`), do mesmo jeito
        // que o índice alfabético do app Contatos fica fixo ao rolar, sem
        // nenhum background próprio — por isso não cria emenda com a nav bar.
        .safeAreaInset(edge: .top) {
            if isSearchActive {
                CampoBuscaHeaderView(searchText: $searchText, isSearchFieldFocused: $isSearchFieldFocused) {
                    isSearchActive = false
                    searchText = ""
                    isSearchFieldFocused = false
                }
            }
        }
        .task(id: parte) {
            await load()
        }
        .task(id: "\(parte.rawValue)|\(searchText)") {
            await search()
        }
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
            let response = try await LeisService.artigos(leiSlug: leiSlug, parte: parte, busca: searchText)
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
            let response = try await LeisService.artigos(leiSlug: leiSlug, parte: parte)
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
///
/// O título de cada grupo é o cabeçalho nativo da `Section` — o próprio
/// `List` (.plain) já fixa esse cabeçalho no topo enquanto a seção rola por
/// baixo dele, do mesmo jeito que o índice alfabético do app Contatos fica
/// fixo. Sem background/material próprio de propósito: só texto sobre o
/// fundo natural da lista, igual à letra do índice — é isso que garante que
/// não apareça nenhuma emenda visual durante a rolagem.
struct ArtigoListView: View {
    let artigos: [Artigo]

    @Environment(AuthStore.self) private var authStore
    @Environment(FavoritosStore.self) private var favoritosStore
    /// Id do artigo tocado — usado com `navigationDestination(item:)` em vez de
    /// `NavigationLink`, que sempre desenha a setinha de disclosure na List.
    @State private var artigoIdSelecionado: Int?

    private var grupos: [(titulo: String?, descricao: String?, artigos: [Artigo])] {
        var result: [(titulo: String?, descricao: String?, artigos: [Artigo])] = []
        for artigo in artigos {
            if !result.isEmpty && result[result.count - 1].titulo == artigo.grupoEstrutural {
                result[result.count - 1].artigos.append(artigo)
            } else {
                result.append((artigo.grupoEstrutural, artigo.descricaoEstrutural, [artigo]))
            }
        }
        return result
    }

    var body: some View {
        List {
            ForEach(Array(grupos.enumerated()), id: \.offset) { _, grupo in
                Section {
                    ForEach(grupo.artigos) { artigo in
                        Button {
                            artigoIdSelecionado = artigo.id
                        } label: {
                            ArtigoCardView(artigo: artigo)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .trailing) {
                            if authStore.isAuthenticated {
                                let favoritado = favoritosStore.estaFavoritado(artigoId: artigo.id, dispositivoId: nil)
                                Button {
                                    alternarFavorito(artigo)
                                } label: {
                                    Label(
                                        favoritado ? "Remover" : "Favoritar",
                                        systemImage: favoritado ? "star.slash.fill" : "star.fill"
                                    )
                                }
                                .tint(favoritado ? .gray : .yellow)
                            }
                        }
                    }
                } header: {
                    if let titulo = grupo.titulo {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(titulo)
                            if let descricao = grupo.descricao {
                                Text(descricao)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .textCase(nil)
                            }
                        }
                        .padding(.bottom, 2)
                    }
                }
            }
        }
        .listStyle(.plain)
        .navigationDestination(item: $artigoIdSelecionado) { id in
            if let artigo = artigos.first(where: { $0.id == id }) {
                ArtigoDetailView(artigoId: id, resumo: artigo)
            }
        }
    }

    private func alternarFavorito(_ artigo: Artigo) {
        guard let token = authStore.token else { return }
        Task {
            await favoritosStore.alternar(artigoId: artigo.id, dispositivoId: nil, token: token)
        }
    }
}

struct ArtigoCardView: View {
    let artigo: Artigo
    /// Mostra o título da lei acima do caput — usado na busca global (aba
    /// Buscar), onde os resultados podem vir de leis diferentes.
    var mostrarLei: Bool = false

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
            if let rubrica = artigo.rubrica {
                Text(rubrica)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
            }
            if mostrarLei, let leiTitulo = artigo.leiTitulo {
                Text(leiTitulo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(artigo.caput)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(artigo.trechoCorrespondente == nil ? 4 : 2)

            if let trecho = artigo.trechoCorrespondente {
                TrechoCorrespondenteView(trecho: trecho)
            }
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

/// Mostra o dispositivo (parágrafo/inciso/alínea) em que uma busca por texto
/// encontrou o termo, quando ele não está no caput exibido acima. Também
/// reaproveitado para mostrar o parágrafo favoritado na tela Principal.
struct TrechoCorrespondenteView: View {
    let trecho: TrechoCorrespondente

    private var corDestaque: Color {
        switch trecho.tipo {
        case "paragrafo": return .blue
        case "inciso": return .teal
        case "alinea": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(trecho.rotulo)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(corDestaque, in: Capsule())
                .fixedSize()

            Text(trecho.texto)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(3)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.yellow.opacity(0.25), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.yellow.opacity(0.5), lineWidth: 1))
    }
}

#Preview {
    NavigationStack {
        ConstituicaoView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
}
