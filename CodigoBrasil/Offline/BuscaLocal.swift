import Foundation

/// Busca por texto dentro de um livro que está salvo no aparelho. Mesmo critério
/// de relevância da busca da API (`Artigo::search` no backend) — quantas
/// palavras batem, priorizando as mais próximas —, então o resultado é o mesmo
/// com ou sem internet, sem ir ao servidor.
enum BuscaLocal {
    /// Normaliza (sem acento, minúsculas) todo o texto do livro uma única vez.
    static func montarIndice(_ livro: LivroOffline) -> LocalBookStore.IndiceDeBusca {
        LocalBookStore.IndiceDeBusca(
            artigos: livro.artigos.map { item in
                BuscaTexto.normalizar(([item.artigo.caput] + item.dispositivos.map(\.texto)).joined(separator: " "))
            },
            dispositivos: livro.artigos.map { item in
                item.dispositivos.map { BuscaTexto.normalizar($0.texto) }
            }
        )
    }

    /// Palavra que não aparece em nenhum artigo da parte é completada ou
    /// corrigida (`CorrecaoDeBusca`), como faz a API — a consulta corrigida
    /// volta em `sugestao`.
    static func buscar(_ livro: LivroOffline, indice: LocalBookStore.IndiceDeBusca, parte: String, consulta: String) -> ResultadoDaBusca {
        var tokens = BuscaTexto.tokenizar(consulta)
        guard !tokens.isEmpty else { return ResultadoDaBusca(artigos: [], sugestao: nil) }

        let posicoesDaParte = livro.artigos.indices.filter { livro.artigos[$0].artigo.parte == parte }
        var sugestao: String?
        var alternativas: [String: [String]] = [:]
        if let ajuste = CorrecaoDeBusca.ajustarConsulta(
            tokens,
            textos: {
                // Mesma ordem da API: caput e dispositivos de cada artigo.
                posicoesDaParte.flatMap { posicao in
                    [livro.artigos[posicao].artigo.caput] + livro.artigos[posicao].dispositivos.map(\.texto)
                }
            },
            aparece: { token in
                guard let regex = BuscaTexto.compilar([token]).first ?? nil else { return true }
                return posicoesDaParte.contains { posicao in
                    let texto = indice.artigos[posicao]
                    return regex.firstMatch(in: texto, range: NSRange(texto.startIndex..., in: texto)) != nil
                }
            }
        ) {
            tokens = ajuste.tokens
            alternativas = ajuste.alternativas
            sugestao = ajuste.sugestao
        }

        let regexes = BuscaTexto.compilar(tokens, extras: alternativas)
        var pontuados: [(artigo: Artigo, pontuacao: Int)] = []

        for (posicao, item) in livro.artigos.enumerated() where item.artigo.parte == parte {
            let pontuacao = BuscaTexto.pontuarNormalizado(indice.artigos[posicao], tokens: tokens, regexes: regexes)
            guard pontuacao > 0 else { continue }

            pontuados.append((
                item.artigo.comTrecho(trecho(de: item, textos: indice.dispositivos[posicao], tokens: tokens, regexes: regexes)),
                pontuacao
            ))
        }

        // Mais palavras batendo primeiro; entre iguais, a ordem original da lei.
        let artigos = pontuados
            .sorted { $0.pontuacao != $1.pontuacao ? $0.pontuacao > $1.pontuacao : $0.artigo.ordem < $1.artigo.ordem }
            .map(\.artigo)
        return ResultadoDaBusca(artigos: artigos, sugestao: sugestao)
    }

    /// O dispositivo (parágrafo/inciso/alínea) que melhor casa com a busca — o que
    /// explica por que o artigo apareceu. `nil` se só o caput bateu.
    private static func trecho(
        de item: ArtigoOffline, textos: [String], tokens: [String], regexes: [NSRegularExpression?]
    ) -> TrechoCorrespondente? {
        var melhor: (dispositivo: ArtigoDispositivo, pontuacao: Int)?

        for (dispositivo, texto) in zip(item.dispositivos, textos) {
            let pontuacao = BuscaTexto.pontuarNormalizado(texto, tokens: tokens, regexes: regexes)
            if pontuacao > (melhor?.pontuacao ?? 0) {
                melhor = (dispositivo, pontuacao)
            }
        }

        guard let melhor else { return nil }
        return TrechoCorrespondente(tipo: melhor.dispositivo.tipo, rotulo: melhor.dispositivo.rotulo, texto: melhor.dispositivo.texto)
    }
}

extension Artigo {
    /// Cópia do artigo com o trecho que casou com a busca.
    func comTrecho(_ trecho: TrechoCorrespondente?) -> Artigo {
        Artigo(
            id: id, parte: parte, numero: numero, tituloEstrutural: tituloEstrutural,
            capituloEstrutural: capituloEstrutural, secaoEstrutural: secaoEstrutural,
            subsecaoEstrutural: subsecaoEstrutural, descricaoEstrutural: descricaoEstrutural,
            rubrica: rubrica, caput: caput, revogado: revogado, ordem: ordem,
            leiSlug: leiSlug, leiTitulo: leiTitulo, trechoCorrespondente: trecho
        )
    }
}
