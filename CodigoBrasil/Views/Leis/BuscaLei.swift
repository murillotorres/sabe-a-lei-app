import Foundation
import OSLog

/// Artigos consecutivos que compartilham o mesmo cabeçalho estrutural
/// (Parte · Título · Capítulo…), já prontos pra renderização — a lista não
/// precisa reagrupar nada dentro do `body`.
struct GrupoArtigos: Identifiable, Equatable, Sendable {
    /// Id do primeiro artigo do grupo: estável entre renderizações (ao contrário
    /// de um índice) e único, já que um artigo só pertence a um grupo.
    let id: Int
    let titulo: String?
    let descricao: String?
    let artigos: [Artigo]
}

/// Consulta dentro do livro aberto. Tudo aqui é puro e `nonisolated`: as
/// funções `async` rodam no executor global (`@concurrent`), então filtrar e
/// agrupar não ocupa a MainActor — só o resultado pronto volta pra ela.
enum BuscaLei {
    /// Reconhece referências a um artigo específico ("5", "art5", "art 5", "art. 5",
    /// "artigo 5º", "a5", "5o", "103-A", "103 - a"...) e devolve o número
    /// normalizado, ou `nil` se o texto não for isso.
    static func numeroReferenciado(_ texto: String) -> String? {
        let trimmed = texto
            .replacing(/[º°ª]/, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        guard !trimmed.isEmpty else { return nil }

        guard let match = trimmed.wholeMatch(of: /(?:artigo|art\.?|a\.?)?\s*(\d+)o?(?:\s*[-‐‑–—]\s*([a-zA-Z]))?/.ignoresCase()) else {
            return nil
        }

        let numero = String(match.1)
        guard let letra = match.2 else { return numero }
        return "\(numero)-\(letra.uppercased())"
    }

    /// Agrupa o livro (ou um resultado de busca) pelo cabeçalho estrutural.
    @concurrent
    static func agrupar(_ artigos: [Artigo]) async -> [GrupoArtigos] {
        montarGrupos(artigos)
    }

    /// Consulta por número de artigo — só olha os artigos do livro aberto.
    @concurrent
    static func porNumero(_ numero: String, em artigos: [Artigo]) async -> [GrupoArtigos] {
        montarGrupos(artigos.filter { $0.numero == numero })
    }

    private static func montarGrupos(_ artigos: [Artigo]) -> [GrupoArtigos] {
        guard !artigos.isEmpty else { return [] }

        var grupos: [GrupoArtigos] = []
        var inicio = 0
        // `grupoEstrutural` monta uma string a cada chamada — calculado uma vez por artigo.
        var tituloAtual = artigos[0].grupoEstrutural

        for indice in 1..<artigos.count {
            let titulo = artigos[indice].grupoEstrutural
            guard titulo != tituloAtual else { continue }

            grupos.append(GrupoArtigos(
                id: artigos[inicio].id,
                titulo: tituloAtual,
                descricao: artigos[inicio].descricaoEstrutural,
                artigos: Array(artigos[inicio..<indice])
            ))
            inicio = indice
            tituloAtual = titulo
        }

        grupos.append(GrupoArtigos(
            id: artigos[inicio].id,
            titulo: tituloAtual,
            descricao: artigos[inicio].descricaoEstrutural,
            artigos: Array(artigos[inicio...])
        ))
        return grupos
    }
}

/// Pontuação de compatibilidade de um texto com as palavras buscadas — mesma
/// lógica usada no backend para a busca geral (ver `Artigo::pontuar` na API).
/// Serve tanto à busca dentro de um artigo quanto à busca dentro de um livro
/// salvo no aparelho (`BuscaLocal`).
enum BuscaTexto {
    /// Quanto as buscas esperam depois da última letra digitada antes de
    /// rodar: digitar "homicidio" faz uma busca, não nove — e não ocupa o
    /// aparelho (nem o servidor) a cada tecla.
    static let atrasoDaDigitacao: Duration = .milliseconds(500)

    /// Trocados antes de tirar acentos: ordinal some ("5º" = "5"), "§" vira
    /// palavra e hífen/travessão viram espaço ("decreto-lei" = "decreto lei").
    private static let especiais: [(String, String)] = [
        ("º", ""), ("°", ""), ("ª", ""), ("§", " paragrafo "),
        ("-", " "), ("‐", " "), ("‑", " "), ("–", " "), ("—", " "),
    ]

    /// Forma comparável de um texto: minúsculas, sem acento, sem ordinal, "§"
    /// por extenso e hífen como espaço. Idêntica a `Artigo::normalizar` na API
    /// — a busca offline depende disso para dar o mesmo resultado.
    static func normalizar(_ texto: String) -> String {
        var texto = texto.lowercased()
        for (de, para) in especiais where texto.contains(de) {
            texto = texto.replacingOccurrences(of: de, with: para)
        }
        return texto.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "pt_BR"))
    }

    /// Palavras da consulta, normalizadas e sem repetição. Pontuação separa
    /// palavras ("art.5º," → "art", "5").
    static func tokenizar(_ consulta: String) -> [String] {
        var vistos = Set<String>()
        return normalizar(consulta)
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { vistos.insert($0).inserted }
    }

    /// Abreviações que a busca entende: a palavra digitada casa também com as
    /// formas listadas. Mesma tabela da API (`Artigo::ABREVIACOES`).
    static let abreviacoes: [String: [String]] = [
        "art": ["artigo"],
        "artigo": ["art"],
        "arts": ["artigos"],
        "artigos": ["arts"],
        "par": ["paragrafo"],
        "inc": ["inciso"],
        "al": ["alinea"],
        "cod": ["codigo"],
        "const": ["constituicao"],
        "dec": ["decreto"],
        "proc": ["processo"],
        "cf": ["constituicao federal"],
        "ec": ["emenda constitucional"],
        "lc": ["lei complementar"],
        "dl": ["decreto lei"],
        "adct": ["ato das disposicoes constitucionais transitorias"],
        "stf": ["supremo tribunal federal"],
        "stj": ["superior tribunal de justica"],
        "tse": ["tribunal superior eleitoral"],
        "tst": ["tribunal superior do trabalho"],
        "mp": ["ministerio publico"],
    ]

    /// Uma regex por palavra (já com as abreviações), compilada uma vez —
    /// pontuar muitos textos com a mesma consulta (um livro inteiro) não deve
    /// recompilar tudo a cada texto.
    /// `extras`: outras palavras que valem por um token (as completações de uma
    /// palavra digitada pela metade).
    static func compilar(_ tokens: [String], extras: [String: [String]] = [:]) -> [NSRegularExpression?] {
        tokens.map { token in
            let alternativas = ([token] + (abreviacoes[token] ?? []) + (extras[token] ?? [])).map {
                NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: "\\s+")
            }
            return try? NSRegularExpression(pattern: "\\b(?:\(alternativas.joined(separator: "|")))\\b")
        }
    }

    static func pontuar(_ texto: String, tokens: [String]) -> Int {
        pontuarNormalizado(normalizar(texto), tokens: tokens, regexes: compilar(tokens))
    }

    /// Como `pontuar`, para um texto que já foi normalizado e regexes já compiladas.
    static func pontuarNormalizado(_ textoNormalizado: String, tokens: [String], regexes: [NSRegularExpression?]) -> Int {
        guard !tokens.isEmpty else { return 0 }
        let range = NSRange(textoNormalizado.startIndex..., in: textoNormalizado)

        // O servidor mede posições em bytes UTF-8; o NSRegularExpression, em unidades
        // UTF-16. Só difere em texto com caracteres fora do ASCII (º, §, aspas...) —
        // converte nesses casos pra a "janela" entre as palavras, e portanto a ordem
        // dos resultados, ser a mesma da API.
        let mapaParaUTF8 = textoNormalizado.utf8.count == textoNormalizado.utf16.count
            ? nil : mapaDeUTF16ParaUTF8(textoNormalizado)

        var posicoesPorToken: [Int: [Int]] = [:]
        for (indice, regex) in regexes.enumerated() {
            guard let regex else { continue }

            let posicoes = regex.matches(in: textoNormalizado, range: range).map { resultado in
                mapaParaUTF8?[resultado.range.location] ?? resultado.range.location
            }
            if !posicoes.isEmpty {
                posicoesPorToken[indice] = posicoes
            }
        }

        let tokensEncontrados = posicoesPorToken.count
        guard tokensEncontrados > 0 else { return 0 }

        let totalOcorrencias = posicoesPorToken.values.reduce(0) { $0 + $1.count }
        var pontuacao = tokensEncontrados * 100_000 + min(totalOcorrencias, 50)

        if tokensEncontrados == tokens.count, let janela = menorJanela(posicoesPorToken) {
            pontuacao += max(0, 50_000 - janela)
        }

        return pontuacao
    }

    /// `mapa[posição UTF-16] = posição em bytes UTF-8` do mesmo caractere.
    private static func mapaDeUTF16ParaUTF8(_ texto: String) -> [Int] {
        var mapa: [Int] = []
        mapa.reserveCapacity(texto.utf16.count + 1)

        var bytes = 0
        for escalar in texto.unicodeScalars {
            for _ in 0..<escalar.utf16.count { mapa.append(bytes) }
            bytes += escalar.utf8.count
        }
        mapa.append(bytes)
        return mapa
    }

    /// Menor trecho que contém pelo menos uma ocorrência de cada palavra —
    /// janela deslizante sobre as posições ordenadas de todos os tokens.
    private static func menorJanela(_ posicoesPorToken: [Int: [Int]]) -> Int? {
        var eventos: [(posicao: Int, token: Int)] = []
        for (token, posicoes) in posicoesPorToken {
            eventos.append(contentsOf: posicoes.map { (posicao: $0, token: token) })
        }
        eventos.sort { $0.posicao < $1.posicao }

        let totalTokens = posicoesPorToken.count
        var contagem: [Int: Int] = [:]
        var distintos = 0
        var menor: Int?
        var esquerda = 0

        for (posicao, token) in eventos {
            contagem[token, default: 0] += 1
            if contagem[token] == 1 { distintos += 1 }

            while distintos == totalTokens {
                let janela = posicao - eventos[esquerda].posicao
                menor = min(menor ?? janela, janela)

                let tokenEsquerda = eventos[esquerda].token
                contagem[tokenEsquerda]! -= 1
                if contagem[tokenEsquerda] == 0 { distintos -= 1 }
                esquerda += 1
            }
        }

        return menor
    }
}

/// Correção de digitação ("defeza" → "defesa"), para a palavra que não aparece
/// em nenhum texto pesquisado. Repete `CorrecaoDeBusca` da API — mesmo
/// vocabulário, distância e desempate —, então a busca offline sugere o mesmo
/// que a online.
enum CorrecaoDeBusca {
    struct Palavra: Sendable {
        /// Grafia original em minúsculas (a primeira vista nos textos).
        let original: String
        var frequencia: Int
    }

    struct Correcao: Sendable, Equatable {
        let normalizada: String
        let original: String
    }

    /// Vocabulário dos textos, na ordem dada: palavras de 4 letras ou mais,
    /// indexadas pela forma normalizada.
    static func vocabulario(_ textos: some Sequence<String>) -> [String: Palavra] {
        var vocabulario: [String: Palavra] = [:]
        for texto in textos {
            for palavra in texto.lowercased().split(whereSeparator: { !$0.isLetter }) where palavra.count >= 4 {
                let normalizada = BuscaTexto.normalizar(String(palavra))
                if vocabulario[normalizada] != nil {
                    vocabulario[normalizada]!.frequencia += 1
                } else {
                    vocabulario[normalizada] = Palavra(original: String(palavra), frequencia: 1)
                }
            }
        }
        return vocabulario
    }

    /// A palavra do vocabulário mais parecida: a que soa igual, ou a de mesma
    /// primeira letra com até 1 erro em palavras de até 7 letras, 2 acima disso
    /// (ou nas mesmas letras embaralhadas), sem ser só outra flexão. A primeira
    /// letra só pode estar errada em palavra de 8+ letras e se for o único erro.
    /// Desempate: a que soa igual, menos erros, a que só completa letras que
    /// faltaram, a mais frequente, a primeira em ordem alfabética.
    static func corrigir(_ termo: String, vocabulario: [String: Palavra]) -> Correcao? {
        let letras = Array(termo.unicodeScalars)
        guard letras.count >= 4, !termo.contains(where: \.isNumber) else { return nil }
        let tolerancia = letras.count <= 7 ? 1 : 2
        let som = fonetica(termo)

        var melhor: (som: Int, distancia: Int, faltou: Int, frequencia: Int, palavra: String)?
        for (normalizada, palavra) in vocabulario {
            let candidata = Array(normalizada.unicodeScalars)
            guard abs(candidata.count - letras.count) <= 2 else { continue }
            let mesmoSom = fonetica(normalizada) == som
            let distancia = distancia(letras, candidata)
            if !mesmoSom {
                // A primeira letra quase nunca é o erro — "decreto" não vira "secreto".
                // Mesmas letras em outra ordem ("estrupo" × "estupro") tolera 2 trocas.
                // Exceção: palavra longa em que só a primeira letra está errada
                // ("lroducao" → "producao").
                let limite = mesmasLetras(letras, candidata) ? max(tolerancia, 2) : tolerancia
                let soAPrimeira = letras.count >= 8 && letras.dropFirst().elementsEqual(candidata.dropFirst())
                guard candidata.first == letras.first || soAPrimeira,
                      distancia <= limite, !soMudaFlexao(letras, candidata) else { continue }
            }

            // Entre iguais, a que só completa letras que faltaram ("expresao" →
            // "expressao") ganha de uma que troca letras ("expresso").
            let chave = (mesmoSom ? 0 : 1, distancia, faltouLetra(letras, candidata) ? 0 : 1, -palavra.frequencia, normalizada)
            if let atual = melhor, (atual.som, atual.distancia, atual.faltou, -atual.frequencia, atual.palavra) <= chave {
                continue
            }
            melhor = (chave.0, chave.1, chave.2, palavra.frequencia, normalizada)
        }

        guard let melhor, let palavra = vocabulario[melhor.palavra] else { return nil }
        return Correcao(normalizada: melhor.palavra, original: palavra.original)
    }

    /// Chave de som de uma palavra normalizada: grafias que soam igual em
    /// português dão a mesma chave ("homicidio" = "omicidio", "defesa" =
    /// "defeza", "divorcio" = "divorsio"). Igual a `CorrecaoDeBusca::fonetica` na API.
    static func fonetica(_ palavra: String) -> String {
        var p = palavra.hasPrefix("h") ? String(palavra.dropFirst()) : palavra
        for (de, para) in [("ph", "f"), ("ch", "x"), ("lh", "l"), ("nh", "n"), ("qu", "k"), ("q", "k")] {
            p = p.replacingOccurrences(of: de, with: para)
        }
        p = p.replacing(/g(?=[ei])/, with: "j")
        p = p.replacing(/gu(?=[ei])/, with: "g")
        p = p.replacing(/sc(?=[ei])/, with: "s")
        p = p.replacing(/c(?=[ei])/, with: "s")
        for (de, para) in [("c", "k"), ("z", "s"), ("y", "i"), ("w", "v"), ("h", "")] {
            p = p.replacingOccurrences(of: de, with: para)
        }

        // Letras dobradas contam como uma ("excesso" = "exceso").
        var semDobradas = ""
        for letra in p where letra != semDobradas.last {
            semDobradas.append(letra)
        }
        return semDobradas
    }

    /// Palavra digitada pela metade só é completada a partir de 4 letras, e
    /// vale pelas 20 palavras mais usadas que começam com ela.
    private static let minimoParaCompletar = 4
    private static let maximoDeCompletacoes = 20

    /// Palavras do vocabulário que começam com `prefixo` ("homici" → homicídio,
    /// homicida…), das mais usadas para as menos (empate: ordem alfabética).
    /// Igual a `CorrecaoDeBusca::completar` na API.
    static func completar(_ prefixo: String, vocabulario: [String: Palavra]) -> [String] {
        guard prefixo.unicodeScalars.count >= minimoParaCompletar, !prefixo.contains(where: \.isNumber) else { return [] }
        return vocabulario
            .filter { $0.key != prefixo && $0.key.hasPrefix(prefixo) }
            .sorted { ($1.value.frequencia, $0.key) < ($0.value.frequencia, $1.key) }
            .prefix(maximoDeCompletacoes)
            .map(\.key)
    }

    private static func mesmasLetras(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Bool {
        a.count == b.count && a.sorted { $0.value < $1.value } == b.sorted { $0.value < $1.value }
    }

    /// `digitada` é `palavra` com letras faltando (as que existem estão na ordem).
    private static func faltouLetra(_ digitada: [Unicode.Scalar], _ palavra: [Unicode.Scalar]) -> Bool {
        var j = 0
        for letra in palavra where j < digitada.count && letra == digitada[j] {
            j += 1
        }
        return j == digitada.count && palavra.count > digitada.count
    }

    /// Terminações de flexão (gênero, número, verbo) — mesma lista da API.
    private static let flexoes: Set<String> = [
        "a", "e", "o", "s", "as", "es", "os", "m", "r", "am", "em", "ar", "er", "ir",
        "do", "da", "dos", "das", "ao", "oes", "aes", "al", "ais", "el", "eis",
    ]

    /// As duas palavras só diferem na terminação, e as duas terminações são de
    /// flexão ("decreto" × "decreta"): trocar uma pela outra não é corrigir
    /// digitação. Completar a palavra ("corpu" → "corpus") continua valendo.
    static func soMudaFlexao(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Bool {
        var comum = 0
        while comum < a.count, comum < b.count, a[comum] == b[comum] { comum += 1 }
        let restoA = String(String.UnicodeScalarView(a[comum...]))
        let restoB = String(String.UnicodeScalarView(b[comum...]))
        return !restoA.isEmpty && !restoB.isEmpty && flexoes.contains(restoA) && flexoes.contains(restoB)
    }

    /// A consulta como deveria ter sido digitada: palavras corrigidas na grafia
    /// dos textos e as demais com acento quando o vocabulário tem.
    static func sugestao(_ palavras: [String], correcoes: [String: Correcao], vocabulario: [String: Palavra]) -> String {
        palavras
            .map { correcoes[$0]?.original ?? vocabulario[$0]?.original ?? $0 }
            .joined(separator: " ")
    }

    /// Busca depois de completar/corrigir as palavras que não existiam.
    struct ConsultaAjustada: Sendable, Equatable {
        let tokens: [String]
        /// Token completado => as outras completações que também valem por ele.
        let alternativas: [String: [String]]
        /// Só quando algo foi corrigido — completar é digitação normal.
        let sugestao: String?
    }

    /// Ajusta, entre `tokens`, os que `aparece` diz não existirem nos textos:
    /// completa ("homici" → homicídio, homicida…) ou corrige ("defeza",
    /// "omicidio"). `nil` se nada mudou. Igual a `CorrecaoDeBusca::ajustar` na API.
    static func ajustarConsulta(
        _ tokens: [String], textos: () -> [String], aparece: (String) -> Bool
    ) -> ConsultaAjustada? {
        let ausentes = tokens.filter { !aparece($0) }
        guard !ausentes.isEmpty else { return nil }

        let vocabulario = vocabulario(textos())
        var trocas: [String: String] = [:]
        var alternativas: [String: [String]] = [:]
        var correcoes: [String: Correcao] = [:]
        for token in ausentes {
            let completacoes = completar(token, vocabulario: vocabulario)
            if let primeira = completacoes.first {
                trocas[token] = primeira
                alternativas[primeira] = Array(completacoes.dropFirst())
            } else if let correcao = corrigir(token, vocabulario: vocabulario) {
                trocas[token] = correcao.normalizada
                correcoes[token] = correcao
            }
        }
        guard !trocas.isEmpty else { return nil }

        var vistos = Set<String>()
        let ajustados = tokens
            .map { trocas[$0] ?? $0 }
            .filter { vistos.insert($0).inserted }
        return ConsultaAjustada(
            tokens: ajustados,
            alternativas: alternativas,
            sugestao: correcoes.isEmpty ? nil : sugestao(tokens, correcoes: correcoes, vocabulario: vocabulario)
        )
    }

    /// `digitada` é `palavra` com erro de digitação — mesma tolerância de
    /// `corrigir`. Também vale para a palavra ainda sendo digitada: compara com
    /// o começo de `palavra` do mesmo tamanho ("constitu" ~ "constituicao").
    static func parecidas(_ digitada: String, _ palavra: String) -> Bool {
        let letras = Array(digitada.unicodeScalars)
        guard letras.count >= 4, !digitada.contains(where: \.isNumber) else { return false }
        let tolerancia = letras.count <= 7 ? 1 : 2

        let alvo = Array(palavra.unicodeScalars)
        if fonetica(digitada) == fonetica(palavra) { return true }
        guard alvo.first == letras.first else { return false }
        if abs(alvo.count - letras.count) <= tolerancia, distancia(letras, alvo) <= tolerancia {
            return true
        }
        return alvo.count > letras.count && distancia(letras, Array(alvo.prefix(letras.count))) <= tolerancia
    }

    /// Erros de digitação entre duas palavras: letra a mais, a menos, trocada
    /// ou duas vizinhas invertidas ("estrupo" → "estupro" é 1). Distância de
    /// Damerau (alinhamento ótimo), igual a `CorrecaoDeBusca::distancia` na API.
    static func distancia(_ a: [Unicode.Scalar], _ b: [Unicode.Scalar]) -> Int {
        guard !a.isEmpty else { return b.count }
        guard !b.isEmpty else { return a.count }

        var d = [[Int]](repeating: [Int](repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                let custo = a[i - 1] == b[j - 1] ? 0 : 1
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + custo)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1)
                }
            }
        }
        return d[a.count][b.count]
    }
}

#if DEBUG
import UIKit

/// Medições da abertura e do uso da busca — só em DEBUG. Ajudam a ver onde o
/// tempo vai (ver o relatório Fence-hang): toque → campo inserido → foco
/// solicitado → teclado. Filtrar no Console por subsystem
/// `com.murillotorres.codigobrasil`, category `Busca`.
@MainActor
enum BuscaMetricas {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "CodigoBrasil", category: "Busca")
    private static var toque: ContinuousClock.Instant?

    private static var observadoresDoTeclado: [any NSObjectProtocol] = []

    static func toqueNoBotao() {
        toque = .now
        logger.debug("[busca] toque no botão de pesquisa")
        observarTecladoUmaVez()
    }

    static func campoInserido() { marcar("campo inserido na hierarquia") }
    static func focoSolicitado() { marcar("foco solicitado") }
    static func tecladoVaiAparecer() { marcar("teclado vai aparecer") }
    static func tecladoApareceu() { marcar("teclado apareceu") }

    static func buscaExecutada(origem: String, consulta: String, pesquisados: Int, resultados: Int, duracao: Duration) {
        logger.debug("[busca] \(origem) \"\(consulta)\": \(pesquisados) artigo(s) no livro → \(resultados) resultado(s) em \(milissegundos(duracao), format: .fixed(precision: 1)) ms")
    }

    /// Quanto a main thread ficou ocupada carregando o teclado no pré-aquecimento
    /// (`TecladoPreAquecido`) — o custo que antes caía na abertura da busca.
    static func tecladoPreAquecido(duracao: Duration) {
        logger.debug("[busca] teclado pré-aquecido após o lançamento: main thread ocupada por \(milissegundos(duracao), format: .fixed(precision: 1)) ms")
    }

    private static func marcar(_ evento: String) {
        guard let toque else { return }
        logger.debug("[busca] \(evento) — +\(milissegundos(.now - toque), format: .fixed(precision: 1)) ms após o toque")
    }

    private static func milissegundos(_ duracao: Duration) -> Double {
        let componentes = duracao.components
        return Double(componentes.seconds) * 1000 + Double(componentes.attoseconds) / 1e15
    }

    /// Observers de disparo único: registrados no toque, saem depois do
    /// `keyboardDidShow` (ou no próximo toque, se o teclado nunca subir).
    private static func observarTecladoUmaVez() {
        removerObservadoresDoTeclado()
        let centro = NotificationCenter.default
        observadoresDoTeclado = [
            centro.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { tecladoVaiAparecer() }
            },
            centro.addObserver(forName: UIResponder.keyboardDidShowNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    tecladoApareceu()
                    removerObservadoresDoTeclado()
                }
            },
        ]
    }

    private static func removerObservadoresDoTeclado() {
        observadoresDoTeclado.forEach(NotificationCenter.default.removeObserver)
        observadoresDoTeclado = []
    }
}
#else
@MainActor
enum BuscaMetricas {
    static func toqueNoBotao() {}
    static func campoInserido() {}
    static func focoSolicitado() {}
    static func buscaExecutada(origem: String, consulta: String, pesquisados: Int, resultados: Int, duracao: Duration) {}
    static func tecladoPreAquecido(duracao: Duration) {}
}
#endif
