import SwiftUI

/// Perfil › Personalizar: ajustes de leitura. Por ora, só o tamanho da fonte
/// dos livros — as opções vêm de `TamanhoDaFonte`.
struct PersonalizarView: View {
    @AppStorage(TamanhoDaFonte.chave) private var tamanhoSalvo = TamanhoDaFonte.padrao.rawValue

    private var tamanho: TamanhoDaFonte { TamanhoDaFonte(rawValue: tamanhoSalvo) ?? .padrao }

    /// O controle trabalha com a posição (0…4) do tamanho na lista de opções.
    private var posicao: Binding<Double> {
        Binding(
            get: { Double(TamanhoDaFonte.allCases.firstIndex(of: tamanho) ?? 0) },
            set: { tamanhoSalvo = TamanhoDaFonte.allCases[Int($0.rounded())].rawValue }
        )
    }

    var body: some View {
        List {
            Section {
                // Controle padrão do iPhone para tamanho de texto: "A" pequeno,
                // "A" grande e um passo por opção.
                Slider(
                    value: posicao,
                    in: 0...Double(TamanhoDaFonte.allCases.count - 1),
                    step: 1
                ) {
                    Text("Tamanho da fonte")
                } minimumValueLabel: {
                    Text("A").font(.system(size: 13, weight: .medium))
                } maximumValueLabel: {
                    Text("A").font(.system(size: 22, weight: .medium))
                }
                .accessibilityValue(tamanho.titulo)
            } header: {
                Text("Tamanho da fonte dos livros")
            } footer: {
                Text("Vale para o texto dos artigos, parágrafos, incisos e alíneas.")
            }
        }
        .navigationTitle("Personalizar")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        PersonalizarView()
    }
}
