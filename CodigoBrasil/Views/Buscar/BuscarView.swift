import SwiftUI

/// Abas que aparecem sob o campo assim que o usuário começa a digitar.
/// Jurisprudência e Anotações entram depois, quando houver esse conteúdo.
enum EscopoDaBusca: String, CaseIterable, Identifiable {
    case todos, legislacao, artigos, tratados

    var id: Self { self }

    var titulo: String {
        switch self {
        case .todos: "Todos"
        case .legislacao: "Legislação"
        case .artigos: "Artigos"
        case .tratados: "Tratados"
        }
    }

    var mostraLeis: Bool { self == .todos || self == .legislacao }
    var mostraArtigos: Bool { self == .todos || self == .artigos }
}

/// Busca em toda a biblioteca (aba Buscar). As leis saem do catálogo do app
/// (`Livro`), na hora; os artigos, do endpoint /busca, que procura em todas as
/// leis cadastradas.
struct BuscarView: View {
    @State private var query = ""
    @State private var escopo: EscopoDaBusca = .todos

    @State private var artigos: [Artigo] = []
    /// Palavras que o servidor usou (com sinônimos e correções) — é o que se
    /// destaca nos resultados. `nil` = API antiga: destaca o que foi digitado.
    @State private var termos: [String]?
    @State private var sugestao: String?
    /// Consulta a que `artigos` corresponde — enquanto a nova não chega, os
    /// resultados antigos continuam na tela, só com o indicador de carregamento.
    @State private var consultaDosArtigos: String?
    @State private var carregando = false
    @State private var falhou = false

    @State private var artigoIdSelecionado: Int?

    @State private var filtros = FiltrosDaBusca()
    @State private var mostrandoFiltros = false

    @State private var historico = HistoricoDeBuscas()
    /// Busca aberta a partir do histórico: roda sem esperar o usuário parar de digitar.
    @State private var consultaInstantanea: String?
    /// Consulta que a seção Legislação mostra — só muda depois do atraso da
    /// digitação, junto com a busca de artigos.
    @State private var consultaDasLeis = ""

    private var consulta: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var leis: [Livro] {
        consultaDasLeis.isEmpty ? [] : Livro.buscar(consultaDasLeis)
    }

    var body: some View {
        NavigationStack {
            conteudo
                .navigationTitle("Buscar")
                // Título grande na altura da barra de navegação (como na
                // Biblioteca), sem o espaço vazio acima dele.
                .toolbarTitleDisplayMode(.inlineLarge)
                .searchable(text: $query, prompt: "Leis, artigos, temas…")
                .searchScopes($escopo, activation: .onTextEntry) {
                    ForEach(EscopoDaBusca.allCases) { escopo in
                        Text(escopo.titulo).tag(escopo)
                    }
                }
                .onSubmit(of: .search) {
                    registrarBuscaAtual()
                }
                .task {
                    await historico.carregar()
                }
                .task(id: consulta) {
                    await buscar()
                }
                .navigationDestination(item: $artigoIdSelecionado) { id in
                    if let artigo = artigos.first(where: { $0.id == id }) {
                        ArtigoDetailView(artigoId: id, resumo: artigo)
                    }
                }
                .sheet(isPresented: $mostrandoFiltros) {
                    FiltrosDaBuscaView(filtros: $filtros)
                }
        }
    }

    @ViewBuilder
    private var conteudo: some View {
        let todasAsLeis = escopo.mostraLeis ? self.leis : []
        let todosOsArtigos = escopo.mostraArtigos ? self.artigos : []
        let leis = todasAsLeis.filter(filtros.aceita)
        let artigos = todosOsArtigos.filter(filtros.aceita)
        let ocultos = todasAsLeis.count + todosOsArtigos.count - leis.count - artigos.count
        let aguardandoArtigos = escopo.mostraArtigos && (carregando || consultaDosArtigos != consulta)
        let aguardandoLeis = escopo.mostraLeis && consultaDasLeis != consulta

        if consulta.isEmpty && !historico.entradas.isEmpty {
            BuscasRecentesView(historico: historico, abrir: abrirDoHistorico)
        } else if consulta.isEmpty {
            ContentUnavailableView(
                "Buscar",
                systemImage: "magnifyingglass",
                description: Text("Encontre leis e artigos em toda a biblioteca — por tema, palavra ou sigla (CP, CPC, CF88…).")
            )
        } else if escopo == .tratados {
            ContentUnavailableView(
                "Nenhum tratado ainda",
                systemImage: "globe.americas",
                description: Text("Os tratados internacionais ainda não fazem parte da biblioteca.")
            )
        } else if leis.isEmpty && artigos.isEmpty {
            if aguardandoArtigos {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if ocultos > 0 {
                ContentUnavailableView {
                    Label("Nada com esses filtros", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text(ocultos == 1 ? "1 resultado ficou de fora pelos filtros." : "\(ocultos) resultados ficaram de fora pelos filtros.")
                } actions: {
                    Button("Limpar filtros") {
                        filtros = FiltrosDaBusca()
                    }
                    .buttonStyle(.borderedProminent)
                    Button("Ajustar filtros", action: abrirFiltros)
                }
            } else if falhou && escopo.mostraArtigos {
                ContentUnavailableView(
                    "Não foi possível buscar",
                    systemImage: "wifi.exclamationmark",
                    description: Text("Verifique sua conexão e tente novamente.")
                )
            } else {
                ContentUnavailableView.search(text: consulta)
            }
        } else {
            ResultadosBuscaView(
                escopo: escopo,
                leis: leis,
                artigos: artigos,
                tokens: termos ?? BuscaTexto.tokenizar(consulta),
                sugestao: escopo.mostraArtigos ? sugestao : nil,
                carregando: aguardandoArtigos || aguardandoLeis,
                falhou: falhou,
                filtrosAlterados: filtros.gruposAlterados,
                abrirFiltros: abrirFiltros,
                aoAbrirResultado: registrarBuscaAtual,
                artigoIdSelecionado: $artigoIdSelecionado
            )
        }
    }

    /// Fecha o teclado antes — o campo de busca continua com o foco e o
    /// teclado ficaria por cima da folha. Sem cancelar a busca (o que
    /// `dismissSearch` faria, apagando o texto).
    private func abrirFiltros() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        mostrandoFiltros = true
    }

    /// Mostra na hora o último resultado guardado dessa busca (se houver) e
    /// dispara a busca sem o intervalo de digitação — ela atualiza a lista em
    /// seguida, em silêncio.
    private func abrirDoHistorico(_ entrada: HistoricoDeBuscas.Entrada) {
        if let resposta = entrada.resposta {
            aplicar(resposta, para: entrada.consulta)
        }
        consultaInstantanea = entrada.consulta
        query = entrada.consulta
        historico.registrar(entrada.consulta, resposta: nil)
    }

    /// Guarda a busca atual no histórico (tecla buscar ou toque num resultado),
    /// com o resultado se ele já chegou.
    private func registrarBuscaAtual() {
        guard !consulta.isEmpty else { return }
        let resposta = consultaDosArtigos == consulta && !falhou
            ? BuscaResponse(artigos: artigos, termos: termos, sugestao: sugestao)
            : nil
        historico.registrar(consulta, resposta: resposta)
    }

    private func aplicar(_ resposta: BuscaResponse, para consulta: String) {
        artigos = resposta.artigos
        termos = resposta.termos
        sugestao = resposta.sugestao
        consultaDosArtigos = consulta
        falhou = false
    }

    /// Espera o usuário parar de digitar (`BuscaTexto.atrasoDaDigitacao`) antes
    /// de buscar — leis e artigos. Aberta pelo histórico, busca na hora.
    private func buscar() async {
        let consulta = consulta
        guard !consulta.isEmpty else {
            consultaDasLeis = ""
            artigos = []
            termos = nil
            sugestao = nil
            consultaDosArtigos = nil
            carregando = false
            falhou = false
            return
        }

        let instantanea = consulta == consultaInstantanea
        consultaInstantanea = nil
        // Resultado do histórico já na tela: a busca só atualiza, sem indicador
        // de carregamento e sem apagar nada se falhar (ex.: sem internet).
        let jaTemResultado = consultaDosArtigos == consulta

        if !instantanea {
            do {
                try await Task.sleep(for: BuscaTexto.atrasoDaDigitacao)
            } catch {
                return
            }
        }
        consultaDasLeis = consulta

        if !jaTemResultado {
            carregando = true
        }

        do {
            let resposta = try await LeisService.buscarGlobal(query: consulta)
            guard !Task.isCancelled else { return }
            aplicar(resposta, para: consulta)
            historico.atualizar(consulta, resposta: resposta)
        } catch {
            guard !Task.isCancelled else { return }
            if !jaTemResultado {
                artigos = []
                termos = nil
                sugestao = nil
                consultaDosArtigos = consulta
                falhou = true
            }
        }

        carregando = false
    }
}

/// Últimas buscas, mostradas com o campo vazio. Tocar abre o resultado na hora;
/// deslizar apaga uma; "Limpar" apaga todas.
private struct BuscasRecentesView: View {
    let historico: HistoricoDeBuscas
    let abrir: (HistoricoDeBuscas.Entrada) -> Void

    var body: some View {
        List {
            Section {
                ForEach(historico.entradas) { entrada in
                    Button {
                        abrir(entrada)
                    } label: {
                        Label {
                            Text(entrada.consulta)
                        } icon: {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(.secondary)
                        }
                    }
                    // Botão de lista pinta o texto com a cor de destaque; aqui é conteúdo, não ação.
                    .tint(.primary)
                }
                .onDelete(perform: historico.remover)
            } header: {
                HStack {
                    Text("Buscas recentes")
                    Spacer()
                    Button("Limpar", action: historico.limpar)
                        .font(.subheadline)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
    }
}

private struct ResultadosBuscaView: View {
    let escopo: EscopoDaBusca
    let leis: [Livro]
    let artigos: [Artigo]
    let tokens: [String]
    let sugestao: String?
    let carregando: Bool
    let falhou: Bool
    let filtrosAlterados: Int
    let abrirFiltros: () -> Void
    /// Tocar num resultado é o sinal de que a busca serviu — entra no histórico.
    let aoAbrirResultado: () -> Void
    @Binding var artigoIdSelecionado: Int?

    private var contagem: String {
        let total = leis.count + artigos.count
        return total == 1 ? "1 resultado" : "\(total) resultados"
    }

    var body: some View {
        List {
            HStack {
                Text("\(escopo.titulo) · \(contagem)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                BotaoDeFiltros(alterados: filtrosAlterados, acao: abrirFiltros)
            }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 20, bottom: 0, trailing: 20))

            if let sugestao {
                SugestaoDeBuscaView(sugestao: sugestao)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets())
            }

            if !leis.isEmpty {
                Section("Legislação") {
                    ForEach(leis) { livro in
                        NavigationLink {
                            livro.destino
                        } label: {
                            ResultadoLeiView(livro: livro)
                        }
                        .simultaneousGesture(TapGesture().onEnded(aoAbrirResultado))
                    }
                }
            }

            if escopo.mostraArtigos {
                Section("Artigos") {
                    if carregando && artigos.isEmpty {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else if artigos.isEmpty {
                        Text(falhou ? "Não foi possível buscar os artigos. Verifique sua conexão." : "Nenhum artigo encontrado.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(artigos) { artigo in
                        Button {
                            aoAbrirResultado()
                            artigoIdSelecionado = artigo.id
                        } label: {
                            ResultadoArtigoView(artigo: artigo, tokens: tokens)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .opacity(carregando && !artigos.isEmpty ? 0.6 : 1)
        .animation(.snappy(duration: 0.2), value: carregando)
    }
}

/// Abre a folha de filtros; com filtros fora do padrão, fica preenchido e
/// mostra quantos grupos foram alterados.
private struct BotaoDeFiltros: View {
    let alterados: Int
    let acao: () -> Void

    var body: some View {
        Button(action: acao) {
            Label(
                alterados > 0 ? "Filtros (\(alterados))" : "Filtros",
                systemImage: alterados > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
            )
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .controlSize(.small)
        .tint(alterados > 0 ? .accentColor : .secondary)
    }
}

private struct ResultadoLeiView: View {
    let livro: Livro

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: livro.icone)
                .font(.body.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(livro.cor.gradient, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(livro.titulo)
                    .font(.body.weight(.semibold))
                Text(livro.categoria.titulo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

/// Resultado de artigo: de qual lei vem, "Art. 25 — Legítima defesa", o
/// começo do texto com as palavras buscadas destacadas e onde o artigo fica
/// na estrutura da lei (Código Penal › Parte Geral › Título II › Do crime).
private struct ResultadoArtigoView: View {
    let artigo: Artigo
    let tokens: [String]

    private var livro: Livro? { Livro.porSlug(artigo.leiSlug) }

    /// Nome curto da lei: o do catálogo do app ou, pra uma lei que o app ainda
    /// não conhece, o título da API sem o número/ano entre parênteses.
    private var nomeDaLei: String? {
        if let livro { return livro.titulo }
        guard let titulo = artigo.leiTitulo else { return nil }
        return titulo.replacing(/\s*\(.*\)\s*$/, with: "")
    }

    private var cabecalho: String {
        guard let rubrica = artigo.rubrica, !rubrica.isEmpty else { return artigo.titulo }
        return "\(artigo.titulo) — \(rubrica)"
    }

    private var caminho: String {
        var partes: [String] = []
        if let nomeDaLei { partes.append(nomeDaLei) }
        if artigo.parte == ParteConstitucional.adct.rawValue { partes.append("ADCT") }
        if let titulo = artigo.tituloEstrutural {
            partes += titulo.components(separatedBy: " · ")
        }
        partes += [artigo.capituloEstrutural, artigo.secaoEstrutural, artigo.subsecaoEstrutural, artigo.descricaoEstrutural]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
        return partes.joined(separator: " › ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let nomeDaLei {
                Text(nomeDaLei)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(livro?.cor ?? .secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(cabecalho)
                    .fonteDoLivro(.headline)
                    .foregroundStyle(.primary)
                if artigo.revogado {
                    Text("Revogado")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
            }

            Text(DestaqueDeBusca.destacar(artigo.caput, tokens: tokens))
                .fonteDoLivro(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(artigo.trechoCorrespondente == nil ? 3 : 2)

            if let trecho = artigo.trechoCorrespondente {
                TrechoCorrespondenteView(trecho: trecho)
            }

            Text(caminho)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Destaca no texto as palavras buscadas — com o mesmo critério da busca:
/// sem acento, sem maiúsculas e só a palavra (ou expressão) inteira.
enum DestaqueDeBusca {
    static func destacar(_ texto: String, tokens: [String]) -> AttributedString {
        var resultado = AttributedString(texto)
        guard !tokens.isEmpty else { return resultado }

        // A comparação é feita no texto sem acento/maiúsculas; as posições só
        // valem no original se cada caractere continuar sendo um só (é o caso do
        // português: "á" → "a", "Ç" → "c"). Por isso aqui não entra o resto de
        // `BuscaTexto.normalizar` ("§" → "paragrafo" mudaria o tamanho).
        let normalizados = texto.map {
            String($0).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
        }
        guard normalizados.allSatisfy({ $0.count == 1 }) else { return resultado }
        let alvo = normalizados.joined()
        let range = NSRange(alvo.startIndex..., in: alvo)

        for regex in BuscaTexto.compilar(tokens).compactMap({ $0 }) {
            for match in regex.matches(in: alvo, range: range) {
                guard let trecho = Range(match.range, in: alvo) else { continue }
                let inicio = alvo.distance(from: alvo.startIndex, to: trecho.lowerBound)
                let tamanho = alvo.distance(from: trecho.lowerBound, to: trecho.upperBound)

                let de = resultado.characters.index(resultado.startIndex, offsetBy: inicio)
                let ate = resultado.characters.index(de, offsetBy: tamanho)
                resultado[de..<ate].inlinePresentationIntent = .stronglyEmphasized
                resultado[de..<ate].foregroundColor = .primary
            }
        }

        return resultado
    }
}

#Preview {
    BuscarView()
        .environment(AuthStore())
        .environment(FavoritosStore())
        .environment(ArmazenamentoOffline())
}
