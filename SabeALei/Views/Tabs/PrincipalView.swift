import SwiftUI

struct PrincipalView: View {
    private let colunas = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.tint)
                        Text("Sabe a Lei")
                            .font(.largeTitle.bold())
                        Text("Vade mecum digital")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    LazyVGrid(columns: colunas, spacing: 12) {
                        NavigationLink {
                            ConstituicaoView()
                        } label: {
                            HomeCardView(titulo: "Constituição", icone: "building.columns.fill", cor: .blue)
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            BibliotecaView()
                        } label: {
                            HomeCardView(titulo: "Biblioteca", icone: "books.vertical.fill", cor: .indigo)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Principal")
        }
    }
}

/// Atalho em formato de card — ícone + título, mesmo estilo em toda tela que
/// funcione como um hub de navegação (Principal, Biblioteca...).
struct HomeCardView: View {
    let titulo: String
    let icone: String
    var cor: Color = .accentColor
    /// Quando informado, mostra à direita o símbolo de download: azul se o livro
    /// já está no aparelho, apagado se não. `nil` = card sem o indicador.
    var baixado: Bool?

    /// Lado do quadrado do ícone — a altura do card é travada nesse mesmo
    /// valor, senão o quadrado esticaria pra virar retângulo.
    private let ladoIcone: CGFloat = 48

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icone)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: ladoIcone, height: ladoIcone)
                .background(cor)
            // O título ocupa o espaço que sobra (em vez de um Spacer, que ainda somaria
            // dois espaçamentos e comprimiria o texto quando há o indicador de download).
            Text(titulo)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(baixado == nil ? 0.7 : 0.6)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let baixado {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 16))
                    .padding(.leading, -4)
                    .foregroundStyle(baixado ? Color.blue : Color.secondary.opacity(0.45))
                    .accessibilityLabel(baixado ? "Disponível offline" : "Não baixado")
            }
        }
        .padding(.trailing, baixado == nil ? 16 : 12)
        .frame(maxWidth: .infinity, minHeight: ladoIcone, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

#Preview {
    PrincipalView()
        .environment(AuthStore())
        .environment(FavoritosStore())
        .environment(ArmazenamentoOffline())
}
