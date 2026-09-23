import SwiftUI

/// Campo de busca com foco automático, mostrado logo abaixo da navigation
/// bar nativa enquanto a busca está ativa — mesmo visual do campo usado
/// dentro de um artigo (`CampoBuscaFixoView`), só que com foco controlado de
/// fora pra abrir o teclado sozinho ao tocar o ícone de pesquisa.
struct CampoBuscaHeaderView: View {
    @Binding var searchText: String
    var isSearchFieldFocused: FocusState<Bool>.Binding
    let aoCancelar: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Buscar por número ou texto...", text: $searchText)
                    .focused(isSearchFieldFocused)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()
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
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(Color(.systemGray5), in: RoundedRectangle(cornerRadius: 10))

            Button("Cancelar", action: aoCancelar)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar, ignoresSafeAreaEdges: .horizontal)
        .transition(.opacity)
    }
}

#Preview {
    @Previewable @State var searchText = ""
    @Previewable @FocusState var focus: Bool

    return VStack {
        CampoBuscaHeaderView(searchText: $searchText, isSearchFieldFocused: $focus) {}
        Spacer()
    }
    .background(Color(.systemGroupedBackground))
}
