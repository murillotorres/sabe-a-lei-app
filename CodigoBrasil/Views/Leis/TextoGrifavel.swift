import SwiftUI
import UIKit

/// Um trecho marcado, já localizado no texto atual do dispositivo.
struct MarcaNoTexto: Equatable {
    let id: UUID
    let intervalo: NSRange
    let cor: CorDoGrifo?
    let temNota: Bool
}

/// O que o texto pede à tela do artigo — é ela que decide login, grava no
/// `EstudosStore` e abre as sheets. Os intervalos são do texto original.
struct AcoesDoTexto {
    var grifar: (NSRange, CorDoGrifo) -> Void
    var anotar: (NSRange) -> Void
    /// Abre (ou cria) a nota do trecho marcado.
    var abrirNota: (UUID) -> Void
    var alterarCor: (UUID, CorDoGrifo) -> Void
    var removerGrifo: (UUID) -> Void
    /// Apaga a nota de um trecho sem cor (e com ela o trecho).
    var removerNota: (UUID) -> Void
}

extension CorDoGrifo {
    /// Cor cheia — bolinhas dos menus e de "Minhas anotações".
    var corDoMarcador: UIColor {
        switch self {
        case .amarelo: .systemYellow
        case .verde: .systemGreen
        case .azul: .systemBlue
        case .vermelho: .systemRed
        case .roxo: .systemPurple
        }
    }

    /// Fundo do grifo: suave o bastante para o texto continuar legível nos
    /// dois modos (o amarelo precisa de mais opacidade para aparecer no claro).
    var corSuave: UIColor {
        let base = corDoMarcador
        let claro: CGFloat = self == .amarelo ? 0.40 : 0.22
        return UIColor { tracos in
            base.withAlphaComponent(tracos.userInterfaceStyle == .dark ? 0.38 : claro)
        }
    }

    var cor: Color { Color(uiColor: corDoMarcador) }

    var bolinha: UIImage? {
        UIImage(systemName: "circle.fill")?.withTintColor(corDoMarcador, renderingMode: .alwaysOriginal)
    }
}

/// Texto de um dispositivo que pode ser selecionado, grifado e anotado.
///
/// O `Text` do SwiftUI não deixa acrescentar ações ao menu de seleção, por isso
/// é um `UITextView` (só leitura). Selecionar mostra "Grifar" (com as cores) e
/// "Adicionar nota" junto de Copiar; tocar num trecho marcado mostra as ações
/// dele; o ícone de nota depois do trecho abre a nota.
struct TextoGrifavel: UIViewRepresentable {
    let texto: String
    let estilo: UIFont.TextStyle
    var marcas: [MarcaNoTexto] = []
    /// Marca destacada por um instante (ao chegar de "Minhas anotações").
    var destaque: UUID?
    var acoes: AcoesDoTexto?

    func makeCoordinator() -> Coordenador { Coordenador() }

    func makeUIView(context: Context) -> UITextView {
        // TextKit 1: é com o layoutManager que se descobre o caractere tocado.
        let view = UITextView(usingTextLayoutManager: false)
        view.isEditable = false
        view.isSelectable = true
        view.isScrollEnabled = false
        view.backgroundColor = .clear
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.dataDetectorTypes = []
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.delegate = context.coordinator

        let toque = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordenador.tocou(_:)))
        toque.cancelsTouchesInView = false
        toque.delegate = context.coordinator
        view.addGestureRecognizer(toque)

        let menu = UIEditMenuInteraction(delegate: context.coordinator)
        view.addInteraction(menu)
        context.coordinator.menuDaMarca = menu
        context.coordinator.textView = view
        return view
    }

    func updateUIView(_ view: UITextView, context: Context) {
        let coordenador = context.coordinator
        coordenador.acoes = acoes
        let fonte = UIFont.doLivro(
            estilo, tamanho: context.environment.tamanhoDaFonteDoLivro,
            dynamicType: context.environment.dynamicTypeSize
        )
        let assinatura = Coordenador.Assinatura(texto: texto, marcas: marcas, destaque: destaque, fonte: fonte)
        // Só remonta quando algo mudou: remontar desfaz a seleção do usuário.
        guard assinatura != coordenador.assinatura else { return }
        coordenador.assinatura = assinatura
        coordenador.montar(texto: texto, fonte: fonte, marcas: marcas, destaque: destaque, em: view)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        let largura = proposal.width.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } ?? 300
        let altura = uiView.sizeThatFits(CGSize(width: largura, height: .greatestFiniteMagnitude)).height
        return CGSize(width: largura, height: ceil(altura))
    }

    @MainActor
    final class Coordenador: NSObject, UITextViewDelegate, @preconcurrency UIEditMenuInteractionDelegate, UIGestureRecognizerDelegate {
        struct Assinatura: Equatable {
            let texto: String
            let marcas: [MarcaNoTexto]
            let destaque: UUID?
            let fonte: UIFont
        }

        weak var textView: UITextView?
        var menuDaMarca: UIEditMenuInteraction?
        var acoes: AcoesDoTexto?
        var assinatura: Assinatura?

        private var texto = ""
        private var marcas: [MarcaNoTexto] = []
        /// Para cada caractere exibido, a posição no texto original (nil = ícone de nota).
        private var originalDoExibido: [Int?] = []
        private var marcaTocada: MarcaNoTexto?

        private static let chaveDaNota = NSAttributedString.Key("CodigoBrasil.notaDaMarca")

        func montar(texto: String, fonte: UIFont, marcas: [MarcaNoTexto], destaque: UUID?, em view: UITextView) {
            self.texto = texto
            self.marcas = marcas
            let ns = texto as NSString
            let validas = marcas.filter { NSMaxRange($0.intervalo) <= ns.length }

            let resultado = NSMutableAttributedString(
                string: texto, attributes: [.font: fonte, .foregroundColor: UIColor.label]
            )
            for marca in validas {
                if let cor = marca.cor {
                    resultado.addAttribute(.backgroundColor, value: cor.corSuave, range: marca.intervalo)
                } else {
                    // Trecho só com nota: sublinhado pontilhado discreto.
                    resultado.addAttributes([
                        .underlineStyle: NSUnderlineStyle.single.rawValue | NSUnderlineStyle.patternDot.rawValue,
                        .underlineColor: UIColor.secondaryLabel,
                    ], range: marca.intervalo)
                }
            }
            if let destaque, let marca = validas.first(where: { $0.id == destaque }) {
                let cor = marca.cor?.corDoMarcador ?? .systemYellow
                resultado.addAttribute(.backgroundColor, value: cor.withAlphaComponent(0.55), range: marca.intervalo)
            }

            // Ícone de nota logo depois de cada trecho anotado. Inseridos do fim
            // para o começo, para as posições ainda não usadas continuarem valendo.
            originalDoExibido = (0..<ns.length).map { Optional($0) }
            let configuracao = UIImage.SymbolConfiguration(font: fonte.withSize(fonte.pointSize * 0.8))
            for marca in validas.filter(\.temNota).sorted(by: { NSMaxRange($0.intervalo) > NSMaxRange($1.intervalo) }) {
                guard let imagem = UIImage(systemName: "note.text", withConfiguration: configuracao)?
                    .withTintColor(.systemOrange, renderingMode: .alwaysOriginal) else { continue }
                let anexo = NSTextAttachment(image: imagem)
                anexo.bounds = CGRect(
                    x: 0, y: (fonte.capHeight - imagem.size.height) / 2,
                    width: imagem.size.width, height: imagem.size.height
                )
                let icone = NSMutableAttributedString(attachment: anexo)
                icone.addAttributes([.font: fonte, Self.chaveDaNota: marca.id], range: NSRange(location: 0, length: icone.length))
                let posicao = NSMaxRange(marca.intervalo)
                resultado.insert(icone, at: posicao)
                originalDoExibido.insert(contentsOf: Array(repeating: nil, count: icone.length), at: posicao)
            }

            view.attributedText = resultado
            view.invalidateIntrinsicContentSize()
        }

        /// Intervalo exibido → intervalo no texto original (sem os ícones).
        private func paraOriginal(_ intervalo: NSRange) -> NSRange? {
            let indices = (intervalo.location..<NSMaxRange(intervalo)).compactMap { i in
                i < originalDoExibido.count ? originalDoExibido[i] : nil
            }
            guard let primeiro = indices.first, let ultimo = indices.last else { return nil }
            return NSRange(location: primeiro, length: ultimo - primeiro + 1)
        }

        // MARK: Seleção

        func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
            guard let acoes,
                  let original = paraOriginal(range).flatMap({ Ancoragem.aparar($0, em: texto) }) else { return nil }

            let cores = CorDoGrifo.allCases.map { cor in
                UIAction(title: cor.nome, image: cor.bolinha) { [weak textView] _ in
                    textView?.selectedTextRange = nil
                    acoes.grifar(original, cor)
                }
            }
            let grifar = UIMenu(title: "Grifar", image: UIImage(systemName: "highlighter"), children: cores)
            let nota = UIAction(title: "Adicionar nota", image: UIImage(systemName: "note.text.badge.plus")) { [weak textView] _ in
                textView?.selectedTextRange = nil
                acoes.anotar(original)
            }
            return UIMenu(children: [grifar, nota] + suggestedActions)
        }

        // MARK: Toque num trecho marcado

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func tocou(_ toque: UITapGestureRecognizer) {
            guard let textView, textView.selectedRange.length == 0, acoes != nil else { return }
            let ponto = toque.location(in: textView)
            guard let indice = indiceDoCaractere(em: ponto, textView) else { return }

            if let id = textView.attributedText.attribute(Self.chaveDaNota, at: indice, effectiveRange: nil) as? UUID {
                acoes?.abrirNota(id)
                return
            }
            guard indice < originalDoExibido.count, let original = originalDoExibido[indice],
                  // A mais recente por cima, como é desenhada.
                  let marca = marcas.last(where: { NSLocationInRange(original, $0.intervalo) }) else { return }
            marcaTocada = marca
            menuDaMarca?.presentEditMenu(with: UIEditMenuConfiguration(identifier: nil, sourcePoint: ponto))
        }

        private func indiceDoCaractere(em ponto: CGPoint, _ textView: UITextView) -> Int? {
            let layout = textView.layoutManager
            let container = textView.textContainer
            let p = CGPoint(x: ponto.x - textView.textContainerInset.left, y: ponto.y - textView.textContainerInset.top)
            let glifo = layout.glyphIndex(for: p, in: container, fractionOfDistanceThroughGlyph: nil)
            let retangulo = layout.boundingRect(forGlyphRange: NSRange(location: glifo, length: 1), in: container)
            // `glyphIndex` sempre devolve o mais próximo — só vale se o toque foi nele.
            guard retangulo.insetBy(dx: -2, dy: -2).contains(p) else { return nil }
            let indice = layout.characterIndexForGlyph(at: glifo)
            return indice < textView.attributedText.length ? indice : nil
        }

        func editMenuInteraction(
            _ interaction: UIEditMenuInteraction, menuFor configuration: UIEditMenuConfiguration,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let marca = marcaTocada, let acoes else { return nil }

            func menuDeCores(_ titulo: String) -> UIMenu {
                UIMenu(title: titulo, image: UIImage(systemName: "paintpalette"), children: CorDoGrifo.allCases
                    .filter { $0 != marca.cor }
                    .map { cor in UIAction(title: cor.nome, image: cor.bolinha) { _ in acoes.alterarCor(marca.id, cor) } })
            }
            let nota = UIAction(
                title: marca.temNota ? "Ver nota" : "Adicionar nota",
                image: UIImage(systemName: marca.temNota ? "note.text" : "note.text.badge.plus")
            ) { _ in acoes.abrirNota(marca.id) }

            if marca.cor != nil {
                let remover = UIAction(title: "Remover grifo", image: UIImage(systemName: "eraser"), attributes: .destructive) { _ in
                    acoes.removerGrifo(marca.id)
                }
                return UIMenu(children: [nota, menuDeCores("Alterar cor"), remover])
            }
            let remover = UIAction(title: "Remover nota", image: UIImage(systemName: "trash"), attributes: .destructive) { _ in
                acoes.removerNota(marca.id)
            }
            return UIMenu(children: [nota, menuDeCores("Grifar"), remover])
        }
    }
}
