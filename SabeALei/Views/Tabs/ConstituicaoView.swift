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

    /// Quantos artigos vêm por requisição: os primeiros abrem o livro, e o resto
    /// chega de tantos em tantos (ver `carregarProxima`).
    private static let tamanhoDaPagina = 20

    @State private var parte: ParteConstitucional = .permanente
    /// Artigos do livro já carregados — só servem de base pra consulta por
    /// número (o livro chega por páginas, então nem sempre estão todos aqui).
    @State private var artigos: [Artigo] = []
    /// O que a lista desenha, já agrupado (montado fora da MainActor): o livro
    /// inteiro, e o resultado da consulta atual. O `body` só escolhe qual.
    @State private var gruposTodos: [GrupoArtigos] = []
    @State private var gruposBusca: [GrupoArtigos] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedParte: ParteConstitucional?
    /// Paginação do livro: o servidor ainda tem artigos depois dos carregados.
    @State private var temMaisArtigos = false
    @State private var isLoadingMais = false
    @State private var falhaAoCarregarMais = false
    /// Sobe a cada vez que o fim da lista pede mais artigos (dispara o `.task`).
    @State private var pedidosDeMais = 0

    @State private var searchText = ""
    @State private var isSearchingRemote = false
    @State private var isSearchActive = false
    @FocusState private var isSearchFieldFocused: Bool

    /// Só espaços = sem consulta, mostra o livro inteiro.
    private var consultaVazia: Bool { searchText.allSatisfy(\.isWhitespace) }

    private var gruposExibidos: [GrupoArtigos] { consultaVazia ? gruposTodos : gruposBusca }

    /// Identifica uma consulta: quando qualquer parte muda, o `.task(id:)`
    /// cancela a busca anterior e começa a nova. `carregada` entra pra refazer
    /// a consulta por número quando o livro termina de carregar (ou troca de parte).
    private struct ConsultaBusca: Equatable {
        let parte: ParteConstitucional
        let carregada: ParteConstitucional?
        let texto: String
    }

    /// Identifica um pedido de mais artigos. A `parte` entra pra que trocar de
    /// parte cancele o pedido em andamento.
    private struct PedidoDeMais: Equatable {
        let parte: ParteConstitucional
        let numero: Int
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
        // Aqui só entra o campo em cena (nav bar some, campo aparece, animado).
        // O foco/teclado fica de fora de propósito: quem pede é o próprio
        // `BuscaNaBarraView`, num ciclo posterior — ver o comentário lá.
        BuscaMetricas.toqueNoBotao()
        withAnimation(.snappy(duration: 0.25)) {
            isSearchActive = true
        }
    }

    private func cancelarBusca() {
        isSearchFieldFocused = false
        searchText = ""
        withAnimation(.snappy(duration: 0.25)) {
            isSearchActive = false
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
        // Voltar fica 100% nativo (navigation bar do sistema) — no iOS 26
        // isso já dá o botão no estilo "Liquid Glass" padrão, sem precisar
        // recriar nada na mão.
        .navigationTitle(titulo)
        .navigationBarTitleDisplayMode(.inline)
        // Durante a busca, a nav bar nativa inteira some e dá lugar ao
        // `safeAreaInset` abaixo. Tentei colocar o campo direto num
        // `ToolbarItem(.principal)` antes, mas campos de texto dentro da
        // toolbar passam pela ponte com UIKit e não pedem foco de forma
        // confiável — o teclado às vezes simplesmente não abria. Uma view
        // SwiftUI "normal" (fora da toolbar) não tem esse problema.
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
                    fechar: cancelarBusca
                )
                .transition(.opacity)
            }
        }
        .task(id: parte) {
            await load()
        }
        // Fim da lista chegou à tela: carrega o próximo lote de artigos.
        .task(id: PedidoDeMais(parte: parte, numero: pedidosDeMais)) {
            guard pedidosDeMais > 0 else { return }
            await carregarProxima()
        }
        // Uma consulta por vez: mudou o texto (ou a parte), a anterior é
        // cancelada — inclusive a requisição em andamento. Fechar a busca
        // zera o texto, então cancela também; sair da tela cancela sozinho.
        .task(id: ConsultaBusca(parte: parte, carregada: loadedParte, texto: searchText)) {
            await buscar()
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
        } else if isSearchingRemote && gruposBusca.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !consultaVazia && gruposExibidos.isEmpty {
            ContentUnavailableView.search(text: searchText)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ArtigoListView(
                grupos: gruposExibidos,
                // Durante uma consulta a lista é o resultado dela, não o livro em páginas.
                temMais: consultaVazia && temMaisArtigos,
                falhouAoCarregarMais: falhaAoCarregarMais,
                aoChegarNoFim: { pedidosDeMais += 1 }
            )
        }
    }

    /// Consulta só o livro aberto (o servidor recebe o slug da lei; a consulta
    /// por número olha só `artigos`, que já são os desse livro). Nada pesado
    /// roda na MainActor: rede, decode, filtro e agrupamento acontecem fora
    /// dela, e só o resultado final é publicado aqui.
    private func buscar() async {
        let consulta = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !consulta.isEmpty else {
            isSearchingRemote = false
            if !gruposBusca.isEmpty { gruposBusca = [] }
            return
        }

        // "5", "art 5", "art. 5" ou "a5" busca o artigo específico, não um texto
        // solto: consulta local e instantânea, sem debounce.
        if let numero = BuscaLei.numeroReferenciado(consulta) {
            let inicio = ContinuousClock.now
            var grupos = await BuscaLei.porNumero(numero, em: artigos)

            // O livro chega por páginas: se o artigo ainda não está na memória,
            // pergunta ao servidor. O filtro local repete o do servidor de
            // propósito — uma versão da API sem o parâmetro devolveria o livro todo.
            if grupos.isEmpty, temMaisArtigos {
                isSearchingRemote = true
                let encontrados = (try? await LeisService.artigos(leiSlug: leiSlug, parte: parte, numero: numero).artigos) ?? []
                guard !Task.isCancelled else { return }
                grupos = await BuscaLei.porNumero(numero, em: encontrados)
            }

            guard !Task.isCancelled else { return }
            gruposBusca = grupos
            isSearchingRemote = false
            BuscaMetricas.buscaExecutada(
                origem: "número", consulta: consulta, pesquisados: artigos.count,
                resultados: grupos.reduce(0) { $0 + $1.artigos.count }, duracao: .now - inicio
            )
            return
        }

        // Texto solto: debounce (só dispara depois que a digitação pausa) e busca
        // no servidor, que olha também o conteúdo dos dispositivos
        // (parágrafos/incisos/alíneas), não só o caput.
        do {
            try await Task.sleep(for: .milliseconds(250))
        } catch {
            return
        }

        isSearchingRemote = true
        let inicioDaRequisicao = ContinuousClock.now

        let encontrados: [Artigo]
        do {
            encontrados = try await LeisService.artigos(leiSlug: leiSlug, parte: parte, busca: consulta).artigos
        } catch {
            encontrados = []
        }

        guard !Task.isCancelled else { return }
        let grupos = await BuscaLei.agrupar(encontrados)
        guard !Task.isCancelled else { return }

        gruposBusca = grupos
        isSearchingRemote = false
        BuscaMetricas.buscaExecutada(
            origem: "texto", consulta: consulta, pesquisados: artigos.count,
            resultados: encontrados.count, duracao: .now - inicioDaRequisicao
        )
    }

    private func load(force: Bool = false) async {
        if force || loadedParte != parte {
            await carregarPrimeiraPagina()
        }

        // Segundo lote, automático e em segundo plano, assim que o primeiro
        // termina — o usuário já tem o que ler e a lista cresce por baixo. Só
        // roda enquanto o que temos é a primeira página; dali em diante os
        // lotes vêm quando o fim da lista aparece.
        if loadedParte == parte, temMaisArtigos, artigos.count <= Self.tamanhoDaPagina {
            await carregarProxima()
        }
    }

    private func carregarPrimeiraPagina() async {
        isLoading = true
        errorMessage = nil
        isLoadingMais = false
        falhaAoCarregarMais = false
        defer { isLoading = false }

        do {
            let response = try await LeisService.artigos(leiSlug: leiSlug, parte: parte, limite: Self.tamanhoDaPagina)
            let grupos = await BuscaLei.agrupar(response.artigos)
            guard !Task.isCancelled else { return }
            artigos = response.artigos
            gruposTodos = grupos
            // Sem `paginacao` a resposta já é o livro inteiro (servidor sem paginação).
            temMaisArtigos = response.paginacao?.temMais ?? false
            loadedParte = parte
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            // Trocar de parte cancela a carga anterior — isso não é um erro.
            guard !Task.isCancelled else { return }
            errorMessage = "Não foi possível completar a solicitação."
        }
    }

    /// Carrega o próximo lote e o junta ao que já está na lista. Uma requisição
    /// por vez: pedidos que chegam enquanto outro está em andamento são ignorados.
    private func carregarProxima() async {
        guard temMaisArtigos, !isLoadingMais, loadedParte == parte else { return }

        isLoadingMais = true
        falhaAoCarregarMais = false
        let parteDaRequisicao = parte
        defer {
            if parte == parteDaRequisicao { isLoadingMais = false }
        }

        do {
            let response = try await LeisService.artigos(
                leiSlug: leiSlug, parte: parte, limite: Self.tamanhoDaPagina, deslocamento: artigos.count
            )
            let todos = artigos + response.artigos
            // Reagrupa tudo: o último grupo do lote anterior pode continuar neste.
            let grupos = await BuscaLei.agrupar(todos)
            guard !Task.isCancelled, parte == parteDaRequisicao else { return }
            artigos = todos
            gruposTodos = grupos
            temMaisArtigos = response.paginacao?.temMais ?? false
        } catch {
            guard !Task.isCancelled else { return }
            falhaAoCarregarMais = true
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
    /// Já agrupados e prontos pra desenhar (ver `BuscaLei.agrupar`) — o `body`
    /// não filtra, ordena nem reagrupa nada.
    let grupos: [GrupoArtigos]
    /// Ainda há artigos por carregar depois dos que estão na lista.
    var temMais = false
    var falhouAoCarregarMais = false
    /// Chamado quando o fim da lista chega à tela: pede o próximo lote.
    var aoChegarNoFim: () -> Void = {}

    @Environment(AuthStore.self) private var authStore
    @Environment(FavoritosStore.self) private var favoritosStore
    /// Id do artigo tocado — usado com `navigationDestination(item:)` em vez de
    /// `NavigationLink`, que sempre desenha a setinha de disclosure na List.
    @State private var artigoIdSelecionado: Int?

    var body: some View {
        List {
            ForEach(grupos) { grupo in
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
                        VStack(alignment: .center, spacing: 2) {
                            Text(titulo)
                            if let descricao = grupo.descricao {
                                Text(descricao)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .textCase(nil)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                        .padding(.bottom, 2)
                    }
                }
                // O `List` reserva ~22 pt acima de cada cabeçalho de seção. Entre os
                // grupos isso é o que os separa; no primeiro, só afasta o título da
                // navigation bar — e o deixa mais baixo do que ele fica quando é
                // fixado no topo ao rolar.
                .semEspacoAcima(grupo.id == grupos.first?.id)
            }

            if temMais {
                rodapeDeCarregamento
            }
        }
        .listStyle(.plain)
        .navigationDestination(item: $artigoIdSelecionado) { id in
            if let artigo = artigo(id: id) {
                ArtigoDetailView(artigoId: id, resumo: artigo)
            }
        }
    }

    /// Última linha da lista enquanto houver mais artigos: quando ela aparece, o
    /// usuário chegou ao fim do que está carregado e o próximo lote é pedido. O
    /// `id` muda a cada lote pra linha ser recriada — se ela continuar na tela
    /// depois da carga (lote curto), o `onAppear` dispara de novo.
    private var rodapeDeCarregamento: some View {
        Group {
            if falhouAoCarregarMais {
                Button("Não foi possível carregar mais. Tentar novamente", action: aoChegarNoFim)
                    .font(.subheadline)
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity)
        .listRowSeparator(.hidden)
        .id(grupos.reduce(0) { $0 + $1.artigos.count })
        .onAppear(perform: aoChegarNoFim)
    }

    private func artigo(id: Int) -> Artigo? {
        for grupo in grupos {
            if let artigo = grupo.artigos.first(where: { $0.id == id }) { return artigo }
        }
        return nil
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

private extension View {
    /// Tira o espaço que o `List` reserva acima da seção. Só existe a partir do
    /// iOS 26 (`listSectionMargins`); antes disso o espaço padrão continua.
    @ViewBuilder
    func semEspacoAcima(_ aplicar: Bool) -> some View {
        if aplicar {
            if #available(iOS 26.0, *) {
                self.listSectionMargins(.top, 0)
            } else {
                self
            }
        } else {
            self
        }
    }
}
