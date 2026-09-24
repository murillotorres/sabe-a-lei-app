import SwiftUI

/// Perfil › Armazenamento: escolhe se o app guarda os livros no aparelho para
/// usar offline. As opções vêm de `ModoDeArmazenamento`.
struct ArmazenamentoView: View {
    @Environment(ArmazenamentoOffline.self) private var armazenamento

    var body: some View {
        List {
            Section {
                ForEach(ModoDeArmazenamento.allCases) { modo in
                    Button {
                        Task { await armazenamento.alterarModo(modo) }
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(modo.titulo)
                                    .foregroundStyle(.primary)
                                Text(modo.descricao)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.leading)
                            }
                            Spacer(minLength: 0)
                            if armazenamento.modo == modo {
                                Image(systemName: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    // Sem isso o Button do List pinta título e descrição com a cor de destaque.
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(armazenamento.modo == modo ? .isSelected : [])
                }
            } footer: {
                Text("Ao escolher “Não armazenar nenhum livro”, os livros salvos no aparelho são removidos. Favoritos e dados da conta não são afetados.")
            }
        }
        .navigationTitle("Armazenamento")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        ArmazenamentoView()
    }
    .environment(ArmazenamentoOffline())
}
