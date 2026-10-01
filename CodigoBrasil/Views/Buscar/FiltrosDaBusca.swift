import SwiftUI

enum TipoDeNorma: String, CaseIterable, Identifiable {
    case constituicao, codigo, lei, decreto, tratado

    var id: Self { self }

    var titulo: String {
        switch self {
        case .constituicao: "Constituição"
        case .codigo: "Código"
        case .lei: "Lei"
        case .decreto: "Decreto"
        case .tratado: "Tratado"
        }
    }
}

enum AreaDoDireito: String, CaseIterable, Identifiable {
    case penal, civil, constitucional, trabalho, administrativo, tributario, eleitoral

    var id: Self { self }

    var titulo: String {
        switch self {
        case .penal: "Penal"
        case .civil: "Civil"
        case .constitucional: "Constitucional"
        case .trabalho: "Trabalho"
        case .administrativo: "Administrativo"
        case .tributario: "Tributário"
        case .eleitoral: "Eleitoral"
        }
    }
}

enum Abrangencia: String, CaseIterable, Identifiable {
    case nacional

    var id: Self { self }

    var titulo: String {
        switch self {
        case .nacional: "Conteúdo nacional"
        }
    }
}

/// O que a busca principal (aba Buscar) mostra. Filtra no aparelho, sobre o
/// que já veio da API — cada artigo traz a lei de onde vem (tipo, área e
/// abrangência saem do catálogo, `Livro`) e se está revogado.
struct FiltrosDaBusca: Equatable {
    var tipos = Set(TipoDeNorma.allCases)
    var areas = Set(AreaDoDireito.allCases)
    var vigentes = true
    var revogados = false
    var abrangencias = Set(Abrangencia.allCases)

    /// Quantos grupos (Tipo, Área, Situação, Local) estão diferentes do padrão.
    var gruposAlterados: Int {
        let padrao = FiltrosDaBusca()
        return [
            tipos != padrao.tipos,
            areas != padrao.areas,
            vigentes != padrao.vigentes || revogados != padrao.revogados,
            abrangencias != padrao.abrangencias,
        ].filter { $0 }.count
    }

    func aceita(_ livro: Livro) -> Bool {
        // Leis inteiras estão em vigor — só aparecem se "Vigente" estiver marcado.
        vigentes && aceitaClassificacao(de: livro)
    }

    func aceita(_ artigo: Artigo) -> Bool {
        guard artigo.revogado ? revogados : vigentes else { return false }
        // Artigo de uma lei que o app ainda não classifica: só a situação vale.
        guard let livro = Livro.porSlug(artigo.leiSlug) else { return true }
        return aceitaClassificacao(de: livro)
    }

    private func aceitaClassificacao(de livro: Livro) -> Bool {
        tipos.contains(livro.tipo) && areas.contains(livro.area) && abrangencias.contains(livro.abrangencia)
    }
}

/// Folha de filtros da busca. Altera os filtros na hora — os resultados atrás
/// já vão se ajustando.
struct FiltrosDaBuscaView: View {
    @Binding var filtros: FiltrosDaBusca
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Tipo") {
                    ForEach(TipoDeNorma.allCases) { tipo in
                        linha(tipo.titulo, marcado: filtros.tipos.contains(tipo), emBreve: !Livro.allCases.contains { $0.tipo == tipo }) {
                            filtros.tipos.formSymmetricDifference([tipo])
                        }
                    }
                }

                Section("Área") {
                    ForEach(AreaDoDireito.allCases) { area in
                        linha(area.titulo, marcado: filtros.areas.contains(area), emBreve: !Livro.allCases.contains { $0.area == area }) {
                            filtros.areas.formSymmetricDifference([area])
                        }
                    }
                }

                Section {
                    linha("Vigente", marcado: filtros.vigentes) { filtros.vigentes.toggle() }
                    linha("Revogado", marcado: filtros.revogados) { filtros.revogados.toggle() }
                } header: {
                    Text("Situação")
                } footer: {
                    Text("Artigos revogados ficam de fora, a não ser que você marque “Revogado”.")
                }

                Section("Local") {
                    ForEach(Abrangencia.allCases) { abrangencia in
                        linha(abrangencia.titulo, marcado: filtros.abrangencias.contains(abrangencia)) {
                            filtros.abrangencias.formSymmetricDifference([abrangencia])
                        }
                    }
                }
            }
            .navigationTitle("Filtros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Limpar") {
                        filtros = FiltrosDaBusca()
                    }
                    .disabled(filtros == FiltrosDaBusca())
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("OK") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Linha marcável. `emBreve`: a opção ainda não tem conteúdo na biblioteca.
    private func linha(_ titulo: String, marcado: Bool, emBreve: Bool = false, alternar: @escaping () -> Void) -> some View {
        Button(action: alternar) {
            HStack(spacing: 12) {
                Image(systemName: marcado ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(marcado ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                Text(titulo)
                    .foregroundStyle(.primary)
                Spacer()
                if emBreve {
                    Text("Em breve")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(marcado ? .isSelected : [])
    }
}

#Preview {
    Text("Resultados")
        .sheet(isPresented: .constant(true)) {
            FiltrosDaBuscaView(filtros: .constant(FiltrosDaBusca()))
        }
}
