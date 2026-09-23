import SwiftUI

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
        // Mesma altura do botão "X" ao lado (toolbar item padrão do
        // sistema) — antes, com padding vertical só, o campo ficava mais
        // baixo que o botão.
        .frame(maxWidth: .infinity)
        .frame(height: 44)
        .pilulaDeVidro()
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
    @ViewBuilder
    func pilulaDeVidro() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular, in: Capsule())
        } else {
            self.background(.regularMaterial, in: Capsule())
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
        BuscaNaBarraView(searchText: $searchText, isSearchFieldFocused: $focus)
            .padding()
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
