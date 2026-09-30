import SwiftUI

/// Primeira tela do app depois de instalado: logo sobre o verde da abertura, os
/// formulários de login/cadastro e, mais discreto, "Continuar sem login".
///
/// Tudo vive num único `Form` rolável (logo incluído) para o teclado nunca
/// esconder o que o usuário está digitando. Fecha sozinha assim que há sessão.
struct BoasVindasView: View {
    /// Marca, no UserDefaults, que esta tela já foi vista. O UserDefaults some
    /// com o app desinstalado — por isso ela volta a cada instalação nova.
    static let chave = "boasVindas.concluida"

    private enum Modo: String, CaseIterable {
        case login = "Entrar"
        case cadastro = "Criar conta"
    }

    /// Chamado ao continuar sem login ou quando o login/cadastro dá certo.
    let concluir: () -> Void

    @Environment(AuthStore.self) private var authStore
    @State private var modo: Modo = .login

    private let verde = Color("FundoAbertura")

    var body: some View {
        Form {
            Section {
                Image("LogoAbertura")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("Código Brasil")
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
            }

            Section {
                Picker("Modo", selection: $modo) {
                    ForEach(Modo.allCases, id: \.self) { modo in
                        Text(modo.rawValue).tag(modo)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            switch modo {
            case .login:
                LoginForm()
            case .cadastro:
                RegisterForm()
            }

            Section {
                Button(action: concluir) {
                    Text("Continuar sem login")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background(verde.ignoresSafeArea())
        // Os botões dos formulários seguem o verde do app em vez do azul do sistema.
        .tint(verde)
        .onChange(of: authStore.isAuthenticated) { _, autenticado in
            if autenticado { concluir() }
        }
        .onChange(of: modo) {
            authStore.errorMessage = nil
        }
    }
}

#Preview {
    BoasVindasView(concluir: {})
        .environment(AuthStore())
}
