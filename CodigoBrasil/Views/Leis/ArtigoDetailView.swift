import SwiftUI

/// Tela de um artigo: o caput em destaque e, abaixo, cada parágrafo/inciso/alínea
/// que o complementa exibido em seu próprio card, indentado conforme a hierarquia.
struct ArtigoDetailView: View {
    let artigoId: Int
    /// Dados já conhecidos da listagem, usados para exibir algo enquanto o detalhe carrega.
    var resumo: Artigo?
    /// Livro do artigo. Quem abre pela lista do livro informa (os artigos de lá
    /// não trazem o slug); da busca e dos favoritos sai do próprio artigo.
    var livro: Livro?
    /// Aberto a partir da lista do próprio livro: ir ao livro completo é só voltar.
    var abertoPeloLivro = false

    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore
    @Environment(FavoritosStore.self) private var favoritosStore

    @State private var artigo: Artigo?
    @State private var blocos: [BlocoDispositivo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var searchText = ""
    /// Resultado da busca neste artigo — calculado uma vez, depois do atraso
    /// da digitação, e não a cada vez que a tela é redesenhada.
    @State private var busca = ResultadoNoArtigo(consulta: "", blocos: [], sugestao: nil)
    @State private var isTogglingFavorito = false
    @State private var isPresentingAuth = false
    @State private var isMostrandoLivro = false

    private var artigoAtual: Artigo? { artigo ?? resumo }

    private var livroAtual: Livro? { livro ?? Livro.porSlug(artigoAtual?.leiSlug) }

    /// Volta pro livro se veio dele; senão abre o livro por cima.
    private func abrirLivro() {
        if abertoPeloLivro {
            dismiss()
        } else {
            isMostrandoLivro = true
        }
    }

    /// Filtra e reordena os cards por compatibilidade com a busca — mesmo
    /// critério usado na busca geral da Constituição (quantas palavras batem,
    /// priorizando as que aparecem mais próximas umas das outras), só que
    /// aplicado apenas ao conteúdo deste artigo, já carregado localmente. Cada
    /// card é pontuado pelo texto todo (parágrafo/inciso + suas alíneas).
    /// Palavra que não aparece em nenhum card é completada ou corrigida pelo
    /// vocabulário do próprio artigo (`CorrecaoDeBusca`) — a consulta corrigida
    /// vai em `sugestao`.
    private func buscarNoArtigo(_ consulta: String) -> ResultadoNoArtigo {
        var tokens = BuscaTexto.tokenizar(consulta)
        guard !tokens.isEmpty else { return ResultadoNoArtigo(consulta: consulta, blocos: blocos, sugestao: nil) }

        var sugestao: String?
        var alternativas: [String: [String]] = [:]
        let textos = blocos.map { BuscaTexto.normalizar($0.textoCompleto) }
        if let ajuste = CorrecaoDeBusca.ajustarConsulta(
            tokens,
            textos: { [artigoAtual?.caput ?? ""] + blocos.map(\.textoCompleto) },
            aparece: { token in
                guard let regex = BuscaTexto.compilar([token]).first ?? nil else { return true }
                return textos.contains { regex.firstMatch(in: $0, range: NSRange($0.startIndex..., in: $0)) != nil }
            }
        ) {
            tokens = ajuste.tokens
            alternativas = ajuste.alternativas
            sugestao = ajuste.sugestao
        }

        let regexes = BuscaTexto.compilar(tokens, extras: alternativas)
        let encontrados = zip(blocos, textos)
            .map { ($0, BuscaTexto.pontuarNormalizado($1, tokens: tokens, regexes: regexes)) }
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .map { $0.0 }
        return ResultadoNoArtigo(consulta: consulta, blocos: encontrados, sugestao: sugestao)
    }

    /// Espera a digitação parar (`BuscaTexto.atrasoDaDigitacao`) e busca.
    /// Campo vazio volta ao artigo inteiro na hora.
    private func atualizarBusca() async {
        let consulta = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !consulta.isEmpty else {
            busca = ResultadoNoArtigo(consulta: "", blocos: [], sugestao: nil)
            return
        }

        do {
            try await Task.sleep(for: BuscaTexto.atrasoDaDigitacao)
        } catch {
            return
        }
        busca = buscarNoArtigo(consulta)
    }

    /// "Artigo 13", ou "Preâmbulo" no único caso em que o artigo não tem número.
    private var tituloGrande: String {
        guard let numero = artigoAtual?.numero else { return "Artigo" }
        return numero == "Preâmbulo" ? "Preâmbulo" : "Artigo \(numero)"
    }

    private var isFavorito: Bool {
        favoritosStore.estaFavoritado(artigoId: artigoId, dispositivoId: nil)
    }

    /// Menu de ações da barra, no estilo do app Mensagens. Nenhum `.buttonStyle`
    /// de propósito: dentro de um `ToolbarItem` o sistema já desenha o vidro
    /// sozinho (igual ao botão voltar) — só o artigo inteiro pode ser favoritado.
    private var menuDeAcoes: some View {
        Menu {
            if let livroAtual {
                Button(action: abrirLivro) {
                    Label(livroAtual.tituloDoLivroCompleto, systemImage: livroAtual.icone)
                }
            }
            Button(action: alternarFavorito) {
                if isFavorito {
                    Label("Remover dos favoritos", systemImage: "star.slash")
                } else {
                    Label("Adicionar aos favoritos", systemImage: "star")
                }
            }
            .disabled(isTogglingFavorito)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Opções do artigo")
    }

    /// Título no centro da barra: "Artigo 2" (com uma estrela discreta se for
    /// favorito) e, embaixo, o livro ("Constituição Federal").
    private var tituloDaBarra: some View {
        VStack(spacing: 1) {
            HStack(spacing: 4) {
                Text(tituloGrande)
                    .font(.headline)
                if isFavorito {
                    Image(systemName: "star.fill")
                        .imageScale(.small)
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel("Favorito")
                }
            }
            if let nome = livroAtual?.nomeCompleto {
                Text(nome)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func alternarFavorito() {
        // Sem sessão a estrela continua visível — tocar nela convida a entrar.
        guard let token = authStore.token else {
            isPresentingAuth = true
            return
        }
        isTogglingFavorito = true
        Task {
            await favoritosStore.alternar(artigoId: artigoId, dispositivoId: nil, token: token)
            isTogglingFavorito = false
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // O subtítulo fica logo abaixo da barra de navegação (onde está o
            // título), centralizado e fixo — não rola junto com o conteúdo.
            if let rubrica = artigoAtual?.rubrica {
                Text(rubrica)
                    .fonteDoLivro(.title3, peso: .bold)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                    // Negativo de propósito: a barra de navegação já reserva uma
                    // folga abaixo do título, e somada ao padding normal deixava
                    // um vão grande entre título e subtítulo. Como o padding
                    // negativo encolhe o layout, o conteúdo sobe junto e a
                    // distância até o primeiro card não muda.
                    .padding(.top, -14)
                    .padding(.bottom, 8)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let artigoAtual {
                        ArtigoCaputCardView(artigo: artigoAtual)
                    }

                    if isLoading && artigo == nil {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else {
                        let buscando = !busca.consulta.isEmpty
                        if buscando && busca.blocos.isEmpty {
                            ContentUnavailableView.search(text: busca.consulta)
                                .padding(.top, 24)
                        } else {
                            if let sugestao = busca.sugestao {
                                SugestaoDeBuscaView(sugestao: sugestao, margem: 4)
                            }
                            ForEach(buscando ? busca.blocos : blocos) { bloco in
                                DispositivoCardView(bloco: bloco, destacado: buscando)
                            }
                            if !buscando, let livroAtual {
                                LivroCompletoButton(livro: livroAtual, action: abrirLivro)
                                    .padding(.top, 12)
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .background(Color(.systemGroupedBackground))
        // Título nativo, centralizado na barra, na mesma linha do botão voltar.
        .navigationTitle(tituloGrande)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $isMostrandoLivro) {
            livroAtual?.destino
        }
        // Sem a barra de tabs nesta tela: o rodapé é da busca.
        .toolbar(.hidden, for: .tabBar)
        // Busca nativa. A partir do iOS 26 o item de busca vai para a barra
        // inferior (Liquid Glass do sistema); antes disso fica no topo.
        .searchable(text: $searchText, prompt: "Buscar neste artigo")
        .naoEsconderBarraNaBusca()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                menuDeAcoes
            }
            // O `navigationTitle` continua valendo pro botão voltar da tela seguinte.
            ToolbarItem(placement: .principal) {
                tituloDaBarra
            }
            if #available(iOS 26.0, *) {
                DefaultToolbarItem(kind: .search, placement: .bottomBar)
            }
        }
        .sheet(isPresented: $isPresentingAuth) {
            AuthView()
        }
        .task { await load() }
        // Refaz quando o texto muda ou quando o artigo termina de carregar.
        .task(id: ChaveDaBusca(texto: searchText, blocos: blocos.count)) {
            await atualizarBusca()
        }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await RepositorioDeLivros.detalhe(artigoId: artigoId)
            artigo = response.artigo
            blocos = BlocoDispositivo.agrupar(response.dispositivos)
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Não foi possível completar a solicitação."
        }
    }
}

private struct ArtigoCaputCardView: View {
    let artigo: Artigo

    var body: some View {
        // Sem o "Art. N" aqui: o número já é o título da barra de navegação.
        VStack(alignment: .leading, spacing: 8) {
            if artigo.revogado {
                SeloRevogadoView()
            }
            Text(artigo.caput)
                .fonteDoLivro(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Um card da tela do artigo: um parágrafo ou inciso e, dentro dele, as
/// alíneas (e itens) que o detalham — esses não ganham card próprio.
struct BlocoDispositivo: Identifiable, Equatable {
    let principal: ArtigoDispositivo
    private(set) var subitens: [ArtigoDispositivo]

    var id: Int { principal.id }

    /// Todo o texto que o card mostra — é sobre ele que a busca pontua.
    var textoCompleto: String {
        ([principal.texto] + subitens.map(\.texto)).joined(separator: " ")
    }

    /// Agrupa os dispositivos (já em ordem de leitura): cada parágrafo ou inciso
    /// abre um card, e o que vem depois dele (alíneas, itens) entra nesse card.
    static func agrupar(_ dispositivos: [ArtigoDispositivo]) -> [BlocoDispositivo] {
        var blocos: [BlocoDispositivo] = []
        for dispositivo in dispositivos {
            let abreCard = dispositivo.tipo == "paragrafo" || dispositivo.tipo == "inciso"
            if !abreCard, !blocos.isEmpty {
                blocos[blocos.count - 1].subitens.append(dispositivo)
            } else {
                blocos.append(BlocoDispositivo(principal: dispositivo, subitens: []))
            }
        }
        return blocos
    }
}

/// Card de parágrafo/inciso: o tipo em letras pequenas com a bolinha do número
/// logo abaixo, à esquerda; o texto à direita, seguido da lista de alíneas
/// (bolinhas amarelas) quando houver. Indentado conforme o nível de aninhamento.
struct DispositivoCardView: View {
    let bloco: BlocoDispositivo
    /// true quando este card é resultado de uma busca dentro do artigo — pinta
    /// o fundo de amarelo, no mesmo estilo do trecho destacado na busca geral.
    var destacado: Bool = false

    /// 9 pt no tamanho de texto padrão; continua acompanhando o Dynamic Type.
    @ScaledMetric(relativeTo: .caption2) private var fonteDoTipo: CGFloat = 9

    private var dispositivo: ArtigoDispositivo { bloco.principal }

    /// Rótulo pequeno do tipo do dispositivo ("PARÁGRAFO", "INCISO").
    private func cabecalho(_ texto: String, linhas: Int = 1) -> some View {
        Text(texto)
            .font(.system(size: fonteDoTipo, weight: .bold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .multilineTextAlignment(.center)
            .lineLimit(linhas)
            .minimumScaleFactor(0.7)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 4) {
                if dispositivo.ehParagrafoUnico {
                    // Sem número pra mostrar: só o rótulo, em duas linhas, sem bolinha.
                    cabecalho("Parágrafo\núnico", linhas: 2)
                } else {
                    if let tipo = dispositivo.nomeDoTipo {
                        cabecalho(tipo)
                    }
                    MarcadorView(
                        texto: dispositivo.rotuloCompacto,
                        cor: dispositivo.cor,
                        corDoTexto: dispositivo.corDoTexto
                    )
                }
            }
            .frame(width: 60)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dispositivo.texto)
                        .fonteDoLivro(.subheadline)
                    if dispositivo.revogado {
                        SeloRevogadoView()
                    }
                }

                ForEach(bloco.subitens) { subitem in
                    SubitemView(subitem: subitem, nivelDoCard: dispositivo.nivel)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            destacado ? Color.yellow.opacity(0.25) : Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(destacado ? Color.yellow.opacity(0.5) : .clear, lineWidth: 1)
        )
        .padding(.leading, CGFloat(max(0, dispositivo.nivel - 1)) * 20)
        .opacity(dispositivo.revogado ? 0.6 : 1)
    }
}

/// Uma alínea (ou item) dentro do card do parágrafo/inciso: bolinha com a letra
/// e o texto ao lado, em formato de lista.
private struct SubitemView: View {
    let subitem: ArtigoDispositivo
    /// Nível do parágrafo/inciso dono do card — itens mais fundos que as alíneas
    /// (filhos delas) ganham um recuo a mais.
    let nivelDoCard: Int

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            MarcadorView(
                texto: subitem.rotuloCompacto,
                cor: subitem.cor,
                corDoTexto: subitem.corDoTexto,
                lado: 26,
                fonte: .caption2.bold()
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(subitem.texto)
                    .fonteDoLivro(.subheadline)
                if subitem.revogado {
                    SeloRevogadoView()
                }
            }
            .padding(.top, 3)
        }
        .padding(.leading, CGFloat(max(0, subitem.nivel - nivelDoCard - 1)) * 16)
        .opacity(subitem.revogado ? 0.6 : 1)
    }
}

/// Bolinha com o rótulo do dispositivo (§ 1º, I, a...). Quando o texto é mais
/// largo que um círculo (números romanos longos, "Único"), estica em pílula.
private struct MarcadorView: View {
    let texto: String
    let cor: Color
    var corDoTexto: Color = .white
    var lado: CGFloat = 36
    var fonte: Font = .caption.bold()

    var body: some View {
        Text(texto)
            .font(fonte)
            .foregroundStyle(corDoTexto)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 6)
            .frame(minWidth: lado, minHeight: lado)
            .background(cor, in: Capsule())
    }
}

/// Fim do artigo: leva ao livro inteiro ("Constituição Completa").
private struct LivroCompletoButton: View {
    let livro: Livro
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: livro.icone)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(livro.cor, in: RoundedRectangle(cornerRadius: 8))
                Text(livro.tituloDoLivroCompleto)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}

private struct SeloRevogadoView: View {
    var body: some View {
        Text("Revogado")
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.red.opacity(0.15), in: Capsule())
            .foregroundStyle(.red)
    }
}

private extension ArtigoDispositivo {
    /// Cabeçalho pequeno acima da bolinha. Alíneas e itens não têm: ficam
    /// dentro do card do parágrafo/inciso, só com a bolinha.
    var nomeDoTipo: String? {
        switch tipo {
        case "paragrafo": return "Parágrafo"
        case "inciso": return "Inciso"
        default: return nil
        }
    }

    /// "Parágrafo único" não tem número: o card mostra só o rótulo, sem bolinha.
    var ehParagrafoUnico: Bool {
        tipo == "paragrafo"
            && rotulo.range(of: "único", options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// O que vai dentro da bolinha: "Parágrafo 1º" perde o "Parágrafo " (o
    /// cabeçalho acima já diz) e "a)" vira "a".
    var rotuloCompacto: String {
        var rotulo = self.rotulo
        if tipo == "paragrafo",
           let prefixo = rotulo.range(of: "parágrafo ", options: [.anchored, .caseInsensitive, .diacriticInsensitive]) {
            rotulo.removeSubrange(rotulo.startIndex..<prefixo.upperBound)
            rotulo = rotulo.prefix(1).uppercased() + rotulo.dropFirst()
        }
        if tipo == "alinea", rotulo.hasSuffix(")") {
            rotulo.removeLast()
        }
        return rotulo
    }

    var cor: Color {
        switch tipo {
        case "paragrafo": return .blue
        case "inciso": return .teal
        case "alinea": return .yellow
        default: return .secondary
        }
    }

    /// Texto branco em cima do amarelo não tem contraste — só ele muda.
    var corDoTexto: Color {
        tipo == "alinea" ? .black : .white
    }
}

private extension View {
    /// Por padrão o sistema esconde a barra de navegação inteira (botão voltar e
    /// título) quando a busca ganha foco. Isso mantém o cabeçalho na tela.
    /// Só existe a partir do iOS 17.1.
    @ViewBuilder
    func naoEsconderBarraNaBusca() -> some View {
        if #available(iOS 17.1, *) {
            self.searchPresentationToolbarBehavior(.avoidHidingContent)
        } else {
            self
        }
    }
}

#Preview {
    NavigationStack {
        ArtigoDetailView(
            artigoId: 6,
            resumo: Artigo(
                id: 6, parte: "permanente", numero: "5",
                tituloEstrutural: "Título II", capituloEstrutural: "Capítulo I",
                secaoEstrutural: nil, subsecaoEstrutural: nil,
                descricaoEstrutural: "Do crime", rubrica: "Relação de causalidade",
                caput: "Todos são iguais perante a lei...",
                revogado: false, ordem: 5, leiSlug: nil, leiTitulo: nil,
                trechoCorrespondente: nil
            )
        )
    }
    .environment(AuthStore())
    .environment(FavoritosStore())
}

/// Resultado de uma busca dentro do artigo.
private struct ResultadoNoArtigo {
    let consulta: String
    let blocos: [BlocoDispositivo]
    let sugestao: String?
}

private struct ChaveDaBusca: Equatable {
    let texto: String
    let blocos: Int
}
