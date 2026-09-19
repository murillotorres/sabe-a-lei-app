import SwiftUI

struct LoginForm: View {
    @Environment(AuthStore.self) private var authStore
    @State private var email = ""
    @State private var password = ""

    var body: some View {
        Form {
            Section {
                TextField("E-mail", text: $email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Senha", text: $password)
                    .textContentType(.password)
            }

            if let errorMessage = authStore.errorMessage {
                Section {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button {
                    Task { await authStore.login(email: email, password: password) }
                } label: {
                    if authStore.isLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Entrar")
                            .frame(maxWidth: .infinity)
                    }
                }
                .disabled(email.isEmpty || password.isEmpty || authStore.isLoading)
            }
        }
    }
}

#Preview {
    LoginForm()
        .environment(AuthStore())
}
