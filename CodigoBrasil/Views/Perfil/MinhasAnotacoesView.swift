import SwiftUI

/// Tudo o que o usuário marcou e escreveu nos artigos — grifos, notas de trecho
/// e anotações de artigo — mais os favoritos, num lugar só. Filtra por tipo,
/// livro, matéria e cor; ordena por data ou pela ordem da legislação; e busca
/// no texto das notas, no trecho grifado, no nome da lei e no número do artigo.
/// Tocar num item abre o artigo já no trecho.
struct MinhasAnotacoesView: View {
    @Environment(AuthStore.self) private var authStore
    @Environment(EstudosStore.self) private var estudos
    @Environment(FavoritosStore.self) private var favoritosStore

    @State private var busca = ""
    @State private var tipo: FiltroDeTipo = .todos
    @State private var livro: Livro?
    @State private var area: AreaDoDireito?
    @State private var cor: CorDoGrifo?
    @State private var ordem: OrdemDosEstudos = .recentes
    @State private var pedindoLogin = false

    private var filtrando: Bool { tipo != .todos || livro != nil || area != nil || cor != nil }

    private var itensExibidos: [ItemDeEstudo] {
        let palavras = BuscaTexto.tokenizar(busca)
        let itens = ItemDeEstudo.todos(estudos: estudos, favoritos: favoritosStore.favoritos)
            .filter { item in
                tipo.aceita(item)
                    && (livro == nil || item.livro == livro)
                    && (area == nil || item.livro?.area == area)
                    && (cor == nil || item.cor == cor)
                    && palavras.allSatisfy { item.textoDeBusca.contains($0) }
            }
        return ordem.ordenar(itens)
    }

    var body: some View {
        Group {
            if !authStore.isAuthenticated {
                ContentUnavailableView {
                    Label("Salve seus estudos", systemImage: "highlighter")
                } description: {
                    Text("Entre na sua conta para criar grifos e anotações e acessá-los em qualquer dispositivo.")
                } actions: {
                    Button("Entrar ou criar conta") { pedindoLogin = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                lista
            }
        }
        .navigationTitle("Minhas anotações")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $pedindoLogin) {
            SalveSeusEstudosView()
        }
    }

    private var lista: some View {
        let itens = itensExibidos
        return List {
            if estudos.quantidadeDePendencias > 0 && estudos.ultimaFalhou {
                Label(
                    "Alterações salvas neste aparelho. Serão sincronizadas quando houver conexão.",
                    systemImage: "icloud.slash"
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            if filtrando {
                HStack {
                    Text(descricaoDosFiltros)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Limpar", action: limparFiltros)
                        .font(.footnote)
                        .buttonStyle(.borderless)
                }
            }
            ForEach(itens) { item in
                NavigationLink {
                    ArtigoDetailView(artigoId: item.artigoId, resumo: item.artigoCompleto, livro: item.livro, foco: item.foco)
                } label: {
                    ItemDeEstudoRow(item: item)
                }
                .swipeActions(edge: .trailing) {
                    if item.podeExcluir {
                        Button("Excluir", role: .destructive) { excluir(item) }
                    }
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if itens.isEmpty {
                if !busca.isEmpty {
                    ContentUnavailableView.search(text: busca)
                } else if filtrando {
                    ContentUnavailableView(
                        "Nada com esses filtros", systemImage: "line.3.horizontal.decrease",
                        description: Text("Tente outros filtros.")
                    )
                } else {
                    ContentUnavailableView(
                        "Nenhuma anotação ainda", systemImage: "highlighter",
                        description: Text("Selecione um trecho de um artigo para grifar ou adicionar uma nota.")
                    )
                }
            }
        }
        .searchable(text: $busca, prompt: "Notas, trechos, leis, artigos")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { menuDeFiltros }
        }
        .refreshable { await atualizar() }
        .task { await atualizar() }
    }

    /// Menu de filtros e ordenação, no estilo do app Mensagens.
    private var menuDeFiltros: some View {
        Menu {
            Picker("Mostrar", selection: $tipo) {
                ForEach(FiltroDeTipo.allCases) { tipo in
                    Label(tipo.titulo, systemImage: tipo.icone).tag(tipo)
                }
            }
            .pickerStyle(.inline)

            Section("Filtrar por") {
                Picker(selection: $livro) {
                    Text("Todos").tag(Livro?.none)
                    ForEach(Livro.allCases) { livro in
                        Text(livro.titulo).tag(Optional(livro))
                    }
                } label: {
                    Label("Diploma legal", systemImage: "book.closed")
                }
                .pickerStyle(.menu)

                Picker(selection: $area) {
                    Text("Todas").tag(AreaDoDireito?.none)
                    ForEach(areasComLivros) { area in
                        Text(area.titulo).tag(Optional(area))
                    }
                } label: {
                    Label("Matéria", systemImage: "scalemass")
                }
                .pickerStyle(.menu)

                Picker(selection: $cor) {
                    Text("Todas").tag(CorDoGrifo?.none)
                    ForEach(CorDoGrifo.allCases) { cor in
                        Label {
                            Text(cor.nome)
                        } icon: {
                            if let bolinha = cor.bolinha { Image(uiImage: bolinha) }
                        }
                        .tag(Optional(cor))
                    }
                } label: {
                    Label("Cor do grifo", systemImage: "paintpalette")
                }
                .pickerStyle(.menu)
            }

            Picker("Ordenar", selection: $ordem) {
                ForEach(OrdemDosEstudos.allCases) { ordem in
                    Text(ordem.titulo).tag(ordem)
                }
            }
            .pickerStyle(.inline)

            if filtrando {
                Button("Limpar filtros", systemImage: "xmark.circle", action: limparFiltros)
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
                .symbolVariant(filtrando ? .circle.fill : .none)
        }
        .accessibilityLabel("Filtrar e ordenar")
    }

    private var areasComLivros: [AreaDoDireito] {
        AreaDoDireito.allCases.filter { area in Livro.allCases.contains { $0.area == area } }
    }

    private var descricaoDosFiltros: String {
        var partes: [String] = []
        if tipo != .todos { partes.append(tipo.titulo) }
        if let livro { partes.append(livro.titulo) }
        if let area { partes.append(area.titulo) }
        if let cor { partes.append(cor.nome) }
        return partes.joined(separator: " · ")
    }

    private func limparFiltros() {
        tipo = .todos
        livro = nil
        area = nil
        cor = nil
    }

    private func excluir(_ item: ItemDeEstudo) {
        switch item.conteudo {
        case .grifo(let grifo, _): estudos.excluirGrifo(grifo.id)
        case .anotacao(let nota): estudos.removerNota(nota.id)
        case .favorito: break
        }
    }

    private func atualizar() async {
        guard let token = authStore.token else { return }
        async let anotacoes: Void = estudos.sincronizar()
        async let favoritos: Void = favoritosStore.carregar(token: token)
        _ = await (anotacoes, favoritos)
    }
}

// MARK: - Filtros

private enum FiltroDeTipo: String, CaseIterable, Identifiable {
    case todos, grifos, anotacoes, favoritos

    var id: Self { self }

    var titulo: String {
        switch self {
        case .todos: "Todos"
        case .grifos: "Grifos"
        case .anotacoes: "Anotações"
        case .favoritos: "Favoritos"
        }
    }

    var icone: String {
        switch self {
        case .todos: "tray.full"
        case .grifos: "highlighter"
        case .anotacoes: "note.text"
        case .favoritos: "star"
        }
    }

    /// "Todos" = grifos e anotações; favoritos aparecem no filtro próprio.
    func aceita(_ item: ItemDeEstudo) -> Bool {
        switch (self, item.conteudo) {
        case (.todos, .favorito): false
        case (.todos, _): true
        case (.grifos, .grifo(let grifo, _)): grifo.cor != nil
        case (.anotacoes, .grifo(_, let nota)): nota != nil
        case (.anotacoes, .anotacao): true
        case (.favoritos, .favorito): true
        default: false
        }
    }
}

private enum OrdemDosEstudos: String, CaseIterable, Identifiable {
    case recentes, antigos, legislacao

    var id: Self { self }

    var titulo: String {
        switch self {
        case .recentes: "Mais recentes"
        case .antigos: "Mais antigos"
        case .legislacao: "Ordem da legislação"
        }
    }

    func ordenar(_ itens: [ItemDeEstudo]) -> [ItemDeEstudo] {
        switch self {
        case .recentes: itens.sorted { $0.data > $1.data }
        case .antigos: itens.sorted { $0.data < $1.data }
        case .legislacao: itens.sorted { $0.posicaoNaLegislacao.lexicographicallyPrecedes($1.posicaoNaLegislacao) }
        }
    }
}

// MARK: - Itens

/// Um registro da lista: um trecho marcado (com a nota, se houver), uma
/// anotação do artigo inteiro ou um favorito.
private struct ItemDeEstudo: Identifiable {
    enum Conteudo {
        case grifo(Grifo, nota: Anotacao?)
        case anotacao(Anotacao)
        case favorito(Favorito)
    }

    let id: String
    let conteudo: Conteudo
    let artigoId: Int
    let resumo: ResumoDoArtigoEstudado?
    let data: Date
    /// Já normalizado (sem acento, minúsculo) para a busca.
    let textoDeBusca: String

    var livro: Livro? { Livro.porSlug(resumo?.leiSlug) }

    var cor: CorDoGrifo? {
        if case .grifo(let grifo, _) = conteudo { return grifo.cor }
        return nil
    }

    var podeExcluir: Bool {
        if case .favorito = conteudo { return false }
        return true
    }

    var foco: FocoNoArtigo? {
        switch conteudo {
        case .grifo(let grifo, _): .grifo(grifo.id)
        case .anotacao(let nota): .anotacao(nota.id)
        case .favorito: nil
        }
    }

    /// O favorito já traz o artigo inteiro; os demais carregam ao abrir.
    var artigoCompleto: Artigo? {
        if case .favorito(let favorito) = conteudo { return favorito.artigo }
        return nil
    }

    /// Livro (na ordem da Biblioteca), parte, artigo, dispositivo, posição no texto.
    var posicaoNaLegislacao: [Int] {
        let indiceDoLivro = livro.flatMap { Livro.allCases.firstIndex(of: $0) } ?? Int.max
        let parte = resumo?.parte == ParteConstitucional.adct.rawValue ? 1 : 0
        var posicao = [indiceDoLivro, parte, resumo?.ordem ?? Int.max]
        switch conteudo {
        case .grifo(let grifo, _): posicao += [grifo.dispositivoOrdem, grifo.inicio]
        // A anotação do artigo inteiro vem depois dos trechos do artigo.
        case .anotacao, .favorito: posicao += [Int.max, 0]
        }
        return posicao
    }

    @MainActor
    static func todos(estudos: EstudosStore, favoritos: [Favorito]) -> [ItemDeEstudo] {
        var itens: [ItemDeEstudo] = []

        for grifo in estudos.grifosAtivos {
            let nota = estudos.nota(doGrifo: grifo.id)
            itens.append(ItemDeEstudo(
                id: "g-\(grifo.id)", conteudo: .grifo(grifo, nota: nota), artigoId: grifo.artigoId,
                resumo: grifo.artigo ?? nota?.artigo,
                data: max(grifo.alteradoEm, nota?.alteradoEm ?? .distantPast),
                textoDeBusca: textoDeBusca(grifo.artigo, [grifo.trecho, nota?.conteudo])
            ))
        }
        for nota in estudos.anotacoesAtivas where nota.grifoId == nil {
            itens.append(ItemDeEstudo(
                id: "a-\(nota.id)", conteudo: .anotacao(nota), artigoId: nota.artigoId,
                resumo: nota.artigo, data: nota.alteradoEm,
                textoDeBusca: textoDeBusca(nota.artigo, [nota.conteudo])
            ))
        }
        // Favoritos não têm data no app: a lista do servidor já vem do mais
        // recente para o mais antigo, e essa posição vira a data.
        for (posicao, favorito) in favoritos.enumerated() {
            let resumo = ResumoDoArtigoEstudado(favorito.artigo, leiSlug: nil)
            itens.append(ItemDeEstudo(
                id: "f-\(favorito.id)", conteudo: .favorito(favorito), artigoId: favorito.artigo.id,
                resumo: resumo, data: Date(timeIntervalSince1970: Double(favoritos.count - posicao)),
                textoDeBusca: textoDeBusca(resumo, [favorito.artigo.caput, favorito.dispositivo?.texto])
            ))
        }
        return itens
    }

    private static func textoDeBusca(_ resumo: ResumoDoArtigoEstudado?, _ textos: [String?]) -> String {
        var partes = textos.compactMap { $0 }
        if let resumo {
            partes += ["art \(resumo.numero)", "artigo \(resumo.numero)", resumo.rubrica ?? ""]
            if let livro = Livro.porSlug(resumo.leiSlug) {
                partes += [livro.titulo, livro.nomeCompleto] + livro.siglas
            }
        }
        return BuscaTexto.normalizar(partes.joined(separator: " "))
    }
}

private struct ItemDeEstudoRow: View {
    let item: ItemDeEstudo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.livro?.titulo ?? "")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if case .favorito = item.conteudo {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                } else {
                    Text(item.data.formatted(.dateTime.day().month(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Text(item.resumo?.titulo ?? "Artigo")
                .font(.headline)

            switch item.conteudo {
            case .grifo(let grifo, let nota):
                HStack(alignment: .top, spacing: 8) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(grifo.cor?.cor ?? Color.secondary.opacity(0.4))
                        .frame(width: 4)
                    Text("“\(grifo.trecho)”")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(4)
                }
                .fixedSize(horizontal: false, vertical: true)
                if let nota {
                    linhaDeNota(nota.conteudo)
                }
            case .anotacao(let anotacao):
                linhaDeNota(anotacao.conteudo, rotulo: "Anotação do artigo:")
            case .favorito(let favorito):
                Text(favorito.dispositivo?.texto ?? favorito.artigo.caput)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
    }

    private func linhaDeNota(_ texto: String, rotulo: String = "Minha nota:") -> some View {
        (Text(rotulo).bold() + Text(" ") + Text(texto))
            .font(.subheadline)
            .lineLimit(4)
    }
}
