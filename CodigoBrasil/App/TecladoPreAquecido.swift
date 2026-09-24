import UIKit

/// O primeiro teclado de cada processo é caro: o primeiro `becomeFirstResponder`
/// carrega de forma síncrona os frameworks de entrada de texto (TextInputUI,
/// AutoFillUI, CoreNLP, WritingTools...) — no relatório Fence-hang, ~1,9 s. Feito
/// na hora em que o usuário abre a busca, isso congela a animação. Aqui o custo
/// é pago uma única vez, logo depois do lançamento e com o app ocioso, usando um
/// campo invisível que ganha e perde o foco no mesmo instante — o teclado não
/// chega a ser exibido.
@MainActor
enum TecladoPreAquecido {
    private static var agendado = false

    /// Agenda o pré-aquecimento para a próxima vez que a run loop principal ficar
    /// ociosa. Só a primeira chamada tem efeito.
    static func agendar() {
        guard !agendado else { return }
        agendado = true

        // `beforeWaiting` = não há mais nada a fazer neste ciclo, ou seja, o
        // primeiro frame já foi pra tela. O `Task` tira o trabalho de dentro do
        // callout do observer.
        let observador = CFRunLoopObserverCreateWithHandler(
            nil, CFRunLoopActivity.beforeWaiting.rawValue, false, Int.max
        ) { _, _ in
            Task { @MainActor in aquecer() }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observador, .commonModes)
    }

    private static func aquecer() {
        guard let janela = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first
        else {
            agendado = false
            return
        }

        let inicio = ContinuousClock.now
        let campo = UITextField()
        campo.isAccessibilityElement = false
        janela.addSubview(campo)
        defer { campo.removeFromSuperview() }

        // Sem foco possível (app fora de cena, por ex.): tenta de novo na próxima ativação.
        guard campo.becomeFirstResponder() else {
            agendado = false
            return
        }
        campo.resignFirstResponder()
        BuscaMetricas.tecladoPreAquecido(duracao: .now - inicio)
    }
}
