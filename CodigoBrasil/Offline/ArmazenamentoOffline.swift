import Foundation
import Observation

/// Ponto de entrada do armazenamento offline para a interface: guarda a
/// configuração escolhida, expõe o estado de cada livro (baixando, disponível
/// offline, atualizando, erro) e traduz eventos do app — abrir um livro, abrir o
/// app, trocar a configuração — em pedidos ao `SincronizadorDaBiblioteca`.
///
/// Não faz rede nem toca em arquivos: isso é do sincronizador e do `LocalBookStore`.
@MainActor
@Observable
final class ArmazenamentoOffline {
    private(set) var modo: ModoDeArmazenamento
    private(set) var estados: [String: EstadoOffline] = [:]

    @ObservationIgnored private let sincronizador: SincronizadorDaBiblioteca
    @ObservationIgnored private let loja: LocalBookStore
    @ObservationIgnored private var ultimaVerificacao: Date?

    /// Voltar ao primeiro plano só reverifica se já passou este tempo; abrir o
    /// app do zero sempre verifica. Nada de relógio: é só uma trava.
    private static let intervaloEntreVerificacoes: TimeInterval = 3600

    init(
        sincronizador: SincronizadorDaBiblioteca = .shared,
        loja: LocalBookStore = .shared,
        modo: ModoDeArmazenamento = .salvo
    ) {
        self.sincronizador = sincronizador
        self.loja = loja
        self.modo = modo

        Task { [weak self] in
            await sincronizador.observar { id, estado in
                Task { @MainActor in self?.estados[id] = estado }
            }
        }
    }

    func estado(de livroId: String) -> EstadoOffline {
        estados[livroId] ?? EstadoOffline()
    }

    // MARK: Eventos do app

    /// O app ficou ativo (abertura ou volta ao primeiro plano). Nunca bloqueia a
    /// interface: tudo acontece em segundo plano.
    func aoFicarAtivo() {
        Task { await iniciar() }
    }

    /// O usuário abriu um livro e a tela já está carregada: se a configuração
    /// permite, o download completo dele começa em segundo plano.
    func livroAberto(_ livroId: String) {
        guard modo.permiteBaixar else { return }
        Task { await sincronizador.solicitarDownload(livroId) }
    }

    /// Trocar a configuração. Sair de "armazenar" apaga os livros offline — e só
    /// eles (ver `LocalBookStore.removerTudo`).
    func alterarModo(_ novo: ModoDeArmazenamento) async {
        guard novo != modo else { return }

        modo = novo
        ModoDeArmazenamento.salvo = novo
        LogOffline.offline("Storage mode: \(novo.rawValue)")

        if !novo.permiteBaixar {
            await sincronizador.cancelarTudo()
            await loja.removerTudo()
            estados = [:]
        } else {
            ultimaVerificacao = nil
        }
    }

    // MARK: Interno

    private func iniciar() async {
        estados = await sincronizador.estadosArmazenados()

        guard modo.permiteBaixar else {
            // Rede de segurança: sem o modo ligado não deve sobrar livro salvo (ex.: uma remoção interrompida).
            if !estados.isEmpty {
                await sincronizador.cancelarTudo()
                await loja.removerTudo()
                estados = [:]
            }
            return
        }

        if let ultima = ultimaVerificacao, Date().timeIntervalSince(ultima) < Self.intervaloEntreVerificacoes {
            return
        }

        ultimaVerificacao = Date()
        await sincronizador.solicitarVerificacao()
    }
}
