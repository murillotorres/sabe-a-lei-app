import SwiftUI

/// Tela de um artigo: o caput em destaque e, abaixo, cada parágrafo/inciso/alínea
/// que o complementa exibido em seu próprio card, indentado conforme a hierarquia.
struct ArtigoDetailView: View {
    let artigoId: Int
    /// Dados já conhecidos da listagem, usados para exibir algo enquanto o detalhe carrega.
    var resumo: Artigo?

    @State private var artigo: Artigo?
    @State private var dispositivos: [ArtigoDispositivo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    private var artigoAtual: Artigo? { artigo ?? resumo }

    var body: some View {
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
                    ForEach(dispositivos) { dispositivo in
                        DispositivoCardView(dispositivo: dispositivo)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(artigoAtual?.titulo ?? "Artigo")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await LeisService.artigo(id: artigoId)
            artigo = response.artigo
            dispositivos = response.dispositivos
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(artigo.titulo)
                    .font(.title3.bold())
                if artigo.revogado {
                    Text("Revogado")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
            Text(artigo.caput)
                .font(.body)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14))
    }
}

/// Um card por parágrafo/inciso/alínea/item, indentado conforme o nível de aninhamento.
struct DispositivoCardView: View {
    let dispositivo: ArtigoDispositivo

    private var accentColor: Color {
        switch dispositivo.tipo {
        case "paragrafo": return .blue
        case "inciso": return .teal
        case "alinea": return .orange
        default: return .secondary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(dispositivo.rotulo)
                .font(.caption.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(accentColor, in: Capsule())
                .fixedSize()

            VStack(alignment: .leading, spacing: 6) {
                Text(dispositivo.texto)
                    .font(.subheadline)
                if dispositivo.revogado {
                    Text("Revogado")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .padding(.leading, CGFloat(max(0, dispositivo.nivel - 1)) * 20)
        .opacity(dispositivo.revogado ? 0.6 : 1)
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
                caput: "Todos são iguais perante a lei...",
                revogado: false, ordem: 5, leiSlug: nil, leiTitulo: nil,
                trechoCorrespondente: nil
            )
        )
    }
}
