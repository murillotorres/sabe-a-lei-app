import SwiftUI

/// Tamanho do texto dos livros (Perfil › Personalizar). O valor bruto é o
/// deslocamento, em pontos, somado ao tamanho padrão de cada texto — e é ele
/// que fica salvo.
enum TamanhoDaFonte: Int, CaseIterable, Identifiable, Sendable {
    case menor = -2
    case padrao = 0
    case grande = 2
    case maior = 4
    case maximo = 6

    var id: Int { rawValue }

    var pontos: CGFloat { CGFloat(rawValue) }

    var titulo: String {
        switch self {
        case .menor: return "Menor"
        case .padrao: return "Padrão"
        case .grande: return "Grande"
        case .maior: return "Maior"
        case .maximo: return "Máximo"
        }
    }

    /// Chave do UserDefaults, compartilhada pelo `@AppStorage` da raiz do app e
    /// da tela Personalizar.
    static let chave = "personalizar.tamanhoDaFonte"
}

extension EnvironmentValues {
    /// Definido uma vez na raiz do app; quem desenha texto de livro só lê.
    @Entry var tamanhoDaFonteDoLivro: TamanhoDaFonte = .padrao
}

extension View {
    /// Fonte do texto de um livro: o estilo de sempre (continua acompanhando o
    /// Dynamic Type) mais os pontos escolhidos em Perfil › Personalizar. No
    /// tamanho padrão é exatamente `.font(estilo)`.
    func fonteDoLivro(_ estilo: Font.TextStyle, peso: Font.Weight? = nil) -> some View {
        modifier(FonteDoLivro(estilo: estilo, peso: peso))
    }
}

private struct FonteDoLivro: ViewModifier {
    let estilo: Font.TextStyle
    let peso: Font.Weight?

    @Environment(\.tamanhoDaFonteDoLivro) private var tamanho
    /// Tamanho do estilo no Dynamic Type atual — é a base sobre a qual os pontos somam.
    @ScaledMetric private var tamanhoBase: CGFloat

    init(estilo: Font.TextStyle, peso: Font.Weight?) {
        self.estilo = estilo
        self.peso = peso
        _tamanhoBase = ScaledMetric(wrappedValue: estilo.pontosNoPadrao, relativeTo: estilo)
    }

    func body(content: Content) -> some View {
        let fonte: Font = tamanho == .padrao
            ? .system(estilo, weight: peso)
            : .system(size: tamanhoBase + tamanho.pontos, weight: peso ?? estilo.pesoNoPadrao)
        content.font(fonte)
    }
}

private extension Font.TextStyle {
    /// Tamanho do estilo no Dynamic Type padrão (Large) do iOS.
    var pontosNoPadrao: CGFloat {
        switch self {
        case .largeTitle: return 34
        case .title: return 28
        case .title2: return 22
        case .title3: return 20
        case .headline, .body: return 17
        case .callout: return 16
        case .subheadline: return 15
        case .footnote: return 13
        case .caption: return 12
        case .caption2: return 11
        @unknown default: return 17
        }
    }

    var pesoNoPadrao: Font.Weight { self == .headline ? .semibold : .regular }
}
