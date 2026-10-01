import SwiftUI

@main
struct CodigoBrasilApp: App {
    @State private var authStore = AuthStore()
    @State private var favoritosStore = FavoritosStore()
    @State private var armazenamento = ArmazenamentoOffline()
    @State private var estudos = EstudosStore()
    @AppStorage(TamanhoDaFonte.chave) private var tamanhoDaFonte = TamanhoDaFonte.padrao.rawValue
    @AppStorage(BoasVindasView.chave) private var boasVindasConcluida = false
    /// Sessão salva no Keychain de uma instalação anterior (o Keychain sobrevive à
    /// desinstalação; o UserDefaults não). Quem já está logado não precisa das boas-vindas.
    @State private var jaTemSessao = KeychainStore.loadToken() != nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if boasVindasConcluida || jaTemSessao {
                    MainTabView()
                } else {
                    BoasVindasView {
                        withAnimation { boasVindasConcluida = true }
                    }
                }
            }
                .environment(authStore)
                .environment(favoritosStore)
                .environment(armazenamento)
                .environment(estudos)
                .environment(\.tamanhoDaFonteDoLivro, TamanhoDaFonte(rawValue: tamanhoDaFonte) ?? .padrao)
                .task {
                    if jaTemSessao { boasVindasConcluida = true }
                    await authStore.restoreSession()
                }
        }
        .onChange(of: scenePhase, initial: true) { _, fase in
            // O primeiro teclado do processo é caro de carregar; paga isso agora,
            // com o app parado, e não no primeiro toque na busca.
            if fase == .active {
                TecladoPreAquecido.agendar()
                // Verifica atualizações dos livros offline em segundo plano — nunca segura a interface.
                armazenamento.aoFicarAtivo()
                // Envia grifos/anotações pendentes e traz os de outros aparelhos.
                estudos.aoFicarAtivo()
            }
        }
    }
}
