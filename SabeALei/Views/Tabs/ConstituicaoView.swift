import SwiftUI

private let constituicaoSlug = "constituicao-federal-1988"

struct ConstituicaoView: View {
    @State private var parte: ParteConstitucional = .permanente
    @State private var artigos: [Artigo] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var loadedParte: ParteConstitucional?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Parte", selection: $parte) {
                    ForEach(ParteConstitucional.allCases, id: \.self) { parte in
                        Text(parte.titulo).tag(parte)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                content
            }
            .navigationTitle("Constituição")
            .task(id: parte) {
                await load()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && loadedParte != parte {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Não foi possível carregar", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Tentar novamente") {
                    Task { await load(force: true) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ArtigoListView(artigos: artigos)
        }
    }

    private func load(force: Bool = false) async {
        if !force && loadedParte == parte { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await LeisService.artigos(leiSlug: constituicaoSlug, parte: parte)
            artigos = response.artigos
            loadedParte = parte
        } catch let error as APIError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = "Não foi possível completar a solicitação."
        }
    }
}

/// Lista os artigos em cards, agrupados pelo título/capítulo/seção estrutural quando disponível.
struct ArtigoListView: View {
    let artigos: [Artigo]

    private var grupos: [(titulo: String?, artigos: [Artigo])] {
        var result: [(titulo: String?, artigos: [Artigo])] = []
        for artigo in artigos {
            if !result.isEmpty && result[result.count - 1].titulo == artigo.grupoEstrutural {
                result[result.count - 1].artigos.append(artigo)
            } else {
                result.append((artigo.grupoEstrutural, [artigo]))
            }
        }
        return result
    }

    var body: some View {
        List {
            ForEach(Array(grupos.enumerated()), id: \.offset) { _, grupo in
                Section {
                    ForEach(grupo.artigos) { artigo in
                        NavigationLink {
                            ArtigoDetailView(artigoId: artigo.id, resumo: artigo)
                        } label: {
                            ArtigoCardView(artigo: artigo)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    }
                } header: {
                    if let titulo = grupo.titulo {
                        Text(titulo)
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

struct ArtigoCardView: View {
    let artigo: Artigo

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(artigo.titulo)
                    .font(.headline)
                    .foregroundStyle(.tint)
                if artigo.revogado {
                    Text("Revogado")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.15), in: Capsule())
                        .foregroundStyle(.red)
                }
                Spacer()
            }
            Text(artigo.caput)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(4)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    ConstituicaoView()
}
