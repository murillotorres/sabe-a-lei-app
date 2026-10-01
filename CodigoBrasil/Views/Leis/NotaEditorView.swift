import SwiftUI

/// Escrever ou editar uma anotação: o trecho selecionado (quando é nota de
/// trecho), o campo de texto e Salvar. Texto vazio ao salvar apaga a nota.
struct NotaEditorView: View {
    let titulo: String
    /// O trecho a que a nota pertence; nulo para a anotação do artigo inteiro.
    var trecho: String?
    var textoInicial: String = ""
    /// Só para uma nota que já existe.
    var excluir: (() -> Void)?
    let salvar: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var texto = ""
    @State private var confirmandoExclusao = false
    @FocusState private var focado: Bool

    var body: some View {
        NavigationStack {
            Form {
                if let trecho {
                    Section("Trecho selecionado") {
                        Text("“\(trecho)”")
                            .fonteDoLivro(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(8)
                    }
                }
                Section("Minha anotação") {
                    TextField("Escreva sua anotação", text: $texto, axis: .vertical)
                        .lineLimit(5...)
                        .focused($focado)
                }
                if let excluir {
                    Section {
                        Button("Excluir anotação", role: .destructive) {
                            confirmandoExclusao = true
                        }
                        .confirmationDialog("Excluir esta anotação?", isPresented: $confirmandoExclusao, titleVisibility: .visible) {
                            Button("Excluir", role: .destructive) {
                                excluir()
                                dismiss()
                            }
                        }
                    }
                }
            }
            .navigationTitle(titulo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salvar") {
                        salvar(texto)
                        dismiss()
                    }
                    .disabled(textoInicial.isEmpty && texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                texto = textoInicial
                focado = textoInicial.isEmpty
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Mostrado quando alguém sem conta tenta grifar ou anotar: nada é guardado
/// sem login, para nunca existir um dado local que possa se perder sem aviso.
struct SalveSeusEstudosView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthStore.self) private var authStore
    @State private var criandoConta: Bool?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "highlighter")
                .font(.system(size: 44))
                .foregroundStyle(.tint)
                .padding(.top, 8)
            Text("Salve seus estudos")
                .font(.title2.bold())
            Text("Entre na sua conta para criar grifos e anotações e acessá-los em qualquer dispositivo.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                Button {
                    criandoConta = false
                } label: {
                    Text("Entrar").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    criandoConta = true
                } label: {
                    Text("Criar conta").frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
            .padding(.top, 8)
        }
        .padding(24)
        .presentationDetents([.medium])
        .sheet(item: Binding(
            get: { criandoConta.map(ModoDeEntrada.init) },
            set: { criandoConta = $0?.criandoConta }
        )) { modo in
            AuthView(criandoConta: modo.criandoConta)
        }
        .onChange(of: authStore.isAuthenticated) { _, logado in
            if logado { dismiss() }
        }
    }

    private struct ModoDeEntrada: Identifiable {
        let criandoConta: Bool
        var id: Bool { criandoConta }
    }
}

/// Um grifo cujo trecho mudou numa atualização da lei: o texto do dispositivo
/// de quando o grifo foi feito e o de agora, lado a lado.
struct ComparacaoDeTextoView: View {
    let trecho: String
    let textoAnterior: String
    let textoAtual: String?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Este trecho foi alterado desde que você fez esta anotação.", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .font(.subheadline)
                }
                Section("Trecho grifado") {
                    Text("“\(trecho)”").fonteDoLivro(.subheadline)
                }
                Section("Texto anterior") {
                    Text(textoAnterior).fonteDoLivro(.subheadline)
                }
                Section("Texto atual") {
                    if let textoAtual {
                        Text(textoAtual).fonteDoLivro(.subheadline)
                    } else {
                        Text("Este dispositivo não existe mais no artigo.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Trecho alterado")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") { dismiss() }
                }
            }
        }
    }
}
