import SwiftUI

/// Medidas da barra de busca, iguais às da navigation bar nativa do iOS 26
/// (medidas no aparelho): controles circulares de 44 pt e 16 pt de margem até
/// a borda da tela. Com isso o "X" cai exatamente onde estava o botão de
/// busca, e o campo ocupa o lugar do botão voltar + título.
enum MedidasDaBusca {
    static let controle: CGFloat = 44
    static let margem: CGFloat = 16
}

/// Barra que ocupa o lugar da navigation bar enquanto a busca está ativa:
/// campo de busca + botão de fechar, com as mesmas medidas e posições dos
/// botões nativos (ver `MedidasDaBusca`).
struct BarraDeBuscaView: View {
    @Binding var searchText: String
    var isSearchFieldFocused: FocusState<Bool>.Binding
    var fechar: @MainActor () -> Void

    var body: some View {
        HStack(spacing: MedidasDaBusca.margem) {
            BuscaNaBarraView(searchText: $searchText, isSearchFieldFocused: isSearchFieldFocused)

            // Fora de um `ToolbarItem` o sistema não desenha o vidro sozinho —
            // aqui ele é aplicado à mão, num círculo com o mesmo diâmetro do
            // botão de busca da toolbar.
            Button(action: fechar) {
                Image(systemName: "xmark")
                    .frame(width: MedidasDaBusca.controle, height: MedidasDaBusca.controle)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .vidro(em: Circle(), interativo: true)
            .accessibilityLabel("Cancelar busca")
        }
        .padding(.horizontal, MedidasDaBusca.margem)
        // Sem padding em cima: os controles ficam exatamente na altura dos
        // botões da navigation bar. Embaixo, um respiro pra borda da barra não
        // encostar no vidro.
        .padding(.bottom, 8)
        .background(.bar, ignoresSafeAreaEdges: .top)
    }
}

/// Campo de busca com foco automático, mostrado no topo da tela do livro
/// enquanto a busca está ativa (no lugar da navigation bar nativa).
///
/// O fundo em pílula usa o Liquid Glass nativo a partir do iOS 26 — mesmo
/// estilo do campo de busca do app Contatos — com `Material` como
/// aproximação em versões anteriores.
struct BuscaNaBarraView: View {
    @Binding var searchText: String
    var isSearchFieldFocused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Buscar por número ou texto...", text: $searchText)
                .focused(isSearchFieldFocused)
                .textFieldStyle(.plain)
                // Busca jurídica: sem correção, sem maiúscula automática e sem
                // Writing Tools — o sistema não precisa subir NLP/IA de escrita
                // (CoreNLP, WritingTools, GenerativeModels) pra um campo assim.
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .semWritingTools()
                .submitLabel(.search)
                .onSubmit {
                    isSearchFieldFocused.wrappedValue = false
                }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .frame(height: MedidasDaBusca.controle)
        .vidro(em: Capsule())
        // O foco NÃO é pedido no `.onAppear`: ele roda dentro da mesma passada
        // de layout/commit que insere o campo, e o primeiro `becomeFirstResponder`
        // do processo carrega os frameworks de entrada de texto (TextInputUI,
        // AutoFillUI, CoreNLP...) de forma síncrona — tudo no mesmo ciclo, o que
        // estourava o fence do Core Animation (Fence-hang de ~1,9 s).
        // `.task` só começa depois que a view já está na hierarquia, ou seja,
        // fora do commit que a inseriu, e é cancelado sozinho se a busca fechar.
        .task { await pedirFoco() }
        #if DEBUG
        .onAppear { BuscaMetricas.campoInserido() }
        #endif
    }

    private func pedirFoco() async {
        // O `yield` deixa qualquer outro trabalho pendente da MainActor (início
        // da animação, layout) rodar antes de o teclado começar a subir.
        await Task.yield()
        guard !Task.isCancelled else { return }
        isSearchFieldFocused.wrappedValue = true
        BuscaMetricas.focoSolicitado()
    }
}

private extension View {
    /// Liquid Glass nativo a partir do iOS 26; `Material` como aproximação antes.
    @ViewBuilder
    func vidro<S: Shape>(em forma: S, interativo: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(interativo ? .regular.interactive() : .regular, in: forma)
        } else {
            self.background(.regularMaterial, in: forma)
        }
    }

    /// Writing Tools (iOS 18+) não faz sentido num campo de busca.
    @ViewBuilder
    func semWritingTools() -> some View {
        if #available(iOS 18.0, *) {
            self.writingToolsBehavior(.disabled)
        } else {
            self
        }
    }
}

#Preview {
    @Previewable @State var searchText = ""
    @Previewable @FocusState var focus: Bool

    return VStack {
        BarraDeBuscaView(searchText: $searchText, isSearchFieldFocused: $focus, fechar: {})
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
