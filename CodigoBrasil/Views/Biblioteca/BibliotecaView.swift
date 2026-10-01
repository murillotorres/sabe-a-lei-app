import SwiftUI

/// Seções da Biblioteca, na ordem em que aparecem.
enum CategoriaDaBiblioteca: CaseIterable {
    case constituicao, codigosPrincipais

    var titulo: String {
        switch self {
        case .constituicao: "Constituição"
        case .codigosPrincipais: "Códigos principais"
        }
    }
}

/// Livros da Biblioteca, na ordem em que aparecem. É o que a busca por título
/// percorre — aqui e na aba Legislação da busca principal (`BuscarView`).
enum Livro: CaseIterable, Identifiable {
    case constituicao, codigoCivil, codigoPenal, codigoProcessoCivil, codigoProcessoPenal, codigoTributarioNacional, codigoEleitoral

    var id: Self { self }

    var categoria: CategoriaDaBiblioteca {
        switch self {
        case .constituicao: .constituicao
        case .codigoCivil, .codigoPenal, .codigoProcessoCivil, .codigoProcessoPenal, .codigoTributarioNacional, .codigoEleitoral:
            .codigosPrincipais
        }
    }

    var slug: String {
        switch self {
        case .constituicao: ConstituicaoView.slug
        case .codigoCivil: CodigoCivilView.slug
        case .codigoPenal: CodigoPenalView.slug
        case .codigoProcessoCivil: CodigoProcessoCivilView.slug
        case .codigoProcessoPenal: CodigoProcessoPenalView.slug
        case .codigoTributarioNacional: CodigoTributarioNacionalView.slug
        case .codigoEleitoral: CodigoEleitoralView.slug
        }
    }

    /// Título do livro, o mesmo da tela dele — é nele que a busca procura.
    var titulo: String {
        switch self {
        case .constituicao: ConstituicaoView.titulo
        case .codigoCivil: CodigoCivilView.titulo
        case .codigoPenal: CodigoPenalView.titulo
        case .codigoProcessoCivil: CodigoProcessoCivilView.titulo
        case .codigoProcessoPenal: CodigoProcessoPenalView.titulo
        case .codigoTributarioNacional: CodigoTributarioNacionalView.titulo
        case .codigoEleitoral: CodigoEleitoralView.titulo
        }
    }

    /// Nome por extenso — subtítulo da tela do artigo.
    var nomeCompleto: String {
        self == .constituicao ? "Constituição Federal" : titulo
    }

    /// Botão que leva ao livro inteiro: "Constituição Completa", "Código Civil
    /// Completo" — concorda com o gênero do nome.
    var tituloDoLivroCompleto: String {
        self == .constituicao ? "\(titulo) Completa" : "\(titulo) Completo"
    }

    /// Texto do card, que pode ser mais curto que o título pra caber na grade.
    var rotulo: String {
        switch self {
        case .codigoProcessoCivil: "Processo Civil"
        case .codigoProcessoPenal: "Processo Penal"
        case .codigoTributarioNacional: "Tributário"
        default: titulo
        }
    }

    /// Siglas e apelidos pelos quais o livro também é procurado. Só casam com a
    /// palavra inteira — "cp" acha o Código Penal, não o CPC nem o CPP.
    var siglas: [String] {
        switch self {
        case .constituicao: ["cf", "cf88", "crfb", "federal", "carta", "magna"]
        case .codigoCivil: ["cc", "cc02"]
        case .codigoPenal: ["cp"]
        case .codigoProcessoCivil: ["cpc", "ncpc"]
        case .codigoProcessoPenal: ["cpp"]
        case .codigoTributarioNacional: ["ctn"]
        case .codigoEleitoral: ["ce"]
        }
    }

    /// Classificação usada pelos filtros da busca (`FiltrosDaBusca`).
    var tipo: TipoDeNorma {
        self == .constituicao ? .constituicao : .codigo
    }

    var area: AreaDoDireito {
        switch self {
        case .constituicao: .constitucional
        case .codigoCivil, .codigoProcessoCivil: .civil
        case .codigoPenal, .codigoProcessoPenal: .penal
        case .codigoTributarioNacional: .tributario
        case .codigoEleitoral: .eleitoral
        }
    }

    /// Todo o acervo atual é legislação federal.
    var abrangencia: Abrangencia { .nacional }

    static func porSlug(_ slug: String?) -> Livro? {
        allCases.first { $0.slug == slug }
    }

    /// Livros em que cada palavra digitada está no título ou é uma das siglas,
    /// sem distinguir maiúsculas, acentos, hífen nem pontuação. No título vale
    /// "contém" (e não palavra inteira) pra que a lista já reaja enquanto a
    /// palavra ainda está sendo digitada, e erro de digitação é tolerado
    /// ("constituisao", "codgo penal"). Com a busca vazia, todos.
    static func buscar(_ consulta: String) -> [Livro] {
        let palavras = BuscaTexto.tokenizar(consulta)
        guard !palavras.isEmpty else { return allCases }
        return allCases.filter { livro in
            let titulo = BuscaTexto.normalizar(livro.titulo)
            let palavrasDoTitulo = BuscaTexto.tokenizar(livro.titulo)
            return palavras.allSatisfy { palavra in
                titulo.contains(palavra)
                    || livro.siglas.contains(palavra)
                    || palavrasDoTitulo.contains { CorrecaoDeBusca.parecidas(palavra, $0) }
            }
        }
    }

    var icone: String {
        switch self {
        case .constituicao: "building.columns.fill"
        case .codigoCivil: "building.2.fill"
        case .codigoPenal: "exclamationmark.shield.fill"
        case .codigoProcessoCivil: "list.bullet.clipboard.fill"
        case .codigoProcessoPenal: "scalemass.fill"
        case .codigoTributarioNacional: "banknote.fill"
        case .codigoEleitoral: "checkmark.seal.fill"
        }
    }

    var cor: Color {
        switch self {
        case .constituicao: .blue
        case .codigoCivil: .indigo
        case .codigoPenal: .red
        case .codigoProcessoCivil: .green
        case .codigoProcessoPenal: .orange
        case .codigoTributarioNacional: .teal
        case .codigoEleitoral: .purple
        }
    }

    @ViewBuilder
    var destino: some View {
        switch self {
        case .constituicao: ConstituicaoView()
        case .codigoCivil: CodigoCivilView()
        case .codigoPenal: CodigoPenalView()
        case .codigoProcessoCivil: CodigoProcessoCivilView()
        case .codigoProcessoPenal: CodigoProcessoPenalView()
        case .codigoTributarioNacional: CodigoTributarioNacionalView()
        case .codigoEleitoral: CodigoEleitoralView()
        }
    }
}

/// Hub com todas as leis do app. Ponto único de entrada pro conteúdo, no
/// lugar das abas separadas que existiam antes.
struct BibliotecaView: View {
    @Environment(ArmazenamentoOffline.self) private var armazenamento

    private let colunas = [GridItem(.flexible()), GridItem(.flexible())]

    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var isSearchFieldFocused: Bool

    /// O livro está salvo no aparelho e disponível offline?
    private func baixado(_ slug: String) -> Bool {
        armazenamento.estado(de: slug).disponivelOffline
    }

    private var livrosExibidos: [Livro] {
        Livro.buscar(searchText)
    }

    /// Os livros exibidos separados por categoria; categoria sem nenhum livro
    /// (na busca) some junto com o subtítulo.
    private var secoes: [(categoria: CategoriaDaBiblioteca, livros: [Livro])] {
        let exibidos = livrosExibidos
        return CategoriaDaBiblioteca.allCases.compactMap { categoria in
            let livros = exibidos.filter { $0.categoria == categoria }
            return livros.isEmpty ? nil : (categoria, livros)
        }
    }

    /// Botão de busca da navigation bar — sem `.buttonStyle` de propósito: dentro
    /// de um `ToolbarItem` o sistema já desenha o vidro (ver `LeiArtigosView`).
    private var botaoDeBusca: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) {
                isSearchActive = true
            }
        } label: {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("Pesquisar")
    }

    private func cancelarBusca() {
        isSearchFieldFocused = false
        searchText = ""
        withAnimation(.snappy(duration: 0.25)) {
            isSearchActive = false
        }
    }

    var body: some View {
        ScrollView {
            if livrosExibidos.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .padding(.top, 60)
            } else {
                VStack(alignment: .leading, spacing: 24) {
                    ForEach(secoes, id: \.categoria) { secao in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(secao.categoria.titulo)
                                .font(.title2.bold())
                                .accessibilityAddTraits(.isHeader)

                            LazyVGrid(columns: colunas, spacing: 12) {
                                ForEach(secao.livros) { livro in
                                    NavigationLink {
                                        livro.destino
                                    } label: {
                                        HomeCardView(titulo: livro.rotulo, icone: livro.icone, cor: livro.cor, baixado: baixado(livro.slug))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .animation(.snappy(duration: 0.25), value: livrosExibidos)
        .background(Color(.systemGroupedBackground))
        // Título grande, alinhado à esquerda e na altura do botão de busca
        // (`inlineLarge`), em vez do título grande abaixo da barra.
        .navigationTitle("Biblioteca Jurídica")
        .toolbarTitleDisplayMode(.inlineLarge)
        // Mesma mecânica da tela de livro (`LeiArtigosView`): com a busca ativa
        // a nav bar some e o campo, fora da toolbar, ocupa o lugar dela — quem
        // pede o foco/teclado é o próprio `BuscaNaBarraView`, num ciclo posterior.
        .toolbar(isSearchActive ? .hidden : .automatic, for: .navigationBar)
        .toolbar {
            if !isSearchActive {
                ToolbarItem(placement: .topBarTrailing) {
                    botaoDeBusca
                }
            }
        }
        .safeAreaInset(edge: .top) {
            if isSearchActive {
                BarraDeBuscaView(
                    searchText: $searchText,
                    isSearchFieldFocused: $isSearchFieldFocused,
                    prompt: "Buscar por título...",
                    fechar: cancelarBusca
                )
                .transition(.opacity)
            }
        }
    }
}

#Preview {
    NavigationStack {
        BibliotecaView()
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
    .environment(ArmazenamentoOffline())
}
