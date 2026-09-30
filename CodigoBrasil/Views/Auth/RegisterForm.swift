import SwiftUI

/// Seções para dentro de um `Form` — quem usa (AuthView, BoasVindasView) põe o `Form` em volta.
struct RegisterForm: View {
    @Environment(AuthStore.self) private var authStore
    @State private var name = ""
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        Group {
            Section {
                TextField("Nome", text: $name)
                    .textContentType(.name)
                TextField("E-mail", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Senha (mín. 8 caracteres)", text: $password)
                    .textContentType(.newPassword)
            }

            if let errorMessage = authStore.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await authStore.register(name: name, email: email, password: password) }
                } label: {
                    if authStore.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Criar conta")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(name.isEmpty || email.isEmpty || password.count < 8 || authStore.isLoading)
            }
        }
    }
}

#Preview {
    Form {
        RegisterForm()
    }
    .environment(AuthStore())
}
