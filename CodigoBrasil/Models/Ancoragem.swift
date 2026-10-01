import Foundation

/// O texto de um dispositivo do artigo (ou do caput), com a chave pela qual os
/// grifos o reencontram.
struct TextoAncoravel: Equatable, Sendable {
    /// "caput", ou o caminho de rótulos até o dispositivo ("§ 1º>II>a)").
    let chave: String
    let dispositivoId: Int?
    /// Posição de leitura no artigo (o caput é 0) — ordena "Minhas anotações".
    let ordem: Int
    let texto: String
}

/// Como um grifo é ancorado no texto e reencontrado depois.
///
/// Os ids de `artigo_dispositivos` mudam quando a lei é reimportada, então a
/// chave do dispositivo é o caminho de rótulos dentro do artigo (os ids de
/// artigo, esses sim, são estáveis). Dentro do dispositivo, o trecho é
/// reencontrado pelo próprio texto; as posições só servem de atalho e de
/// desempate. Se o trecho não existe mais, o grifo NÃO é movido para outro
/// texto: vira "trecho alterado".
enum Ancoragem {
    static let chaveDoCaput = "caput"
    /// Quantos caracteres antes/depois do trecho são guardados para desempatar.
    private static let tamanhoDoContexto = 40

    /// Todos os textos ancoráveis do artigo, na ordem de leitura.
    static func textos(caput: String, dispositivos: [ArtigoDispositivo]) -> [TextoAncoravel] {
        let porId = Dictionary(dispositivos.map { ($0.id, $0) }, uniquingKeysWith: { primeiro, _ in primeiro })
        var usadas: [String: Int] = [:]
        var resultado = [TextoAncoravel(chave: chaveDoCaput, dispositivoId: nil, ordem: 0, texto: caput)]

        for (indice, dispositivo) in dispositivos.enumerated() {
            var caminho = [dispositivo.rotulo]
            var pai = dispositivo.parentId.flatMap { porId[$0] }
            var visitados: Set<Int> = [dispositivo.id]
            while let atual = pai, visitados.insert(atual.id).inserted {
                caminho.insert(atual.rotulo, at: 0)
                pai = atual.parentId.flatMap { porId[$0] }
            }
            var chave = caminho.joined(separator: ">")
            // Rótulo repetido no mesmo nível (raro): numera as ocorrências.
            let ocorrencia = usadas[chave, default: 0]
            usadas[chave] = ocorrencia + 1
            if ocorrencia > 0 { chave += "#\(ocorrencia + 1)" }

            resultado.append(TextoAncoravel(chave: chave, dispositivoId: dispositivo.id, ordem: indice + 1, texto: dispositivo.texto))
        }
        return resultado
    }

    /// O trecho selecionado, sem espaços nas pontas. `nil` se só sobrar espaço.
    static func aparar(_ intervalo: NSRange, em texto: String) -> NSRange? {
        let ns = texto as NSString
        guard intervalo.location != NSNotFound, NSMaxRange(intervalo) <= ns.length else { return nil }
        var inicio = intervalo.location
        var fim = NSMaxRange(intervalo)
        let espacos = CharacterSet.whitespacesAndNewlines
        while inicio < fim, let u = UnicodeScalar(ns.character(at: inicio)), espacos.contains(u) { inicio += 1 }
        while fim > inicio, let u = UnicodeScalar(ns.character(at: fim - 1)), espacos.contains(u) { fim -= 1 }
        return fim > inicio ? NSRange(location: inicio, length: fim - inicio) : nil
    }

    /// Texto antes e depois do trecho, para reencontrá-lo se ele se repetir.
    static func contexto(de intervalo: NSRange, em texto: String) -> (prefixo: String, sufixo: String) {
        let ns = texto as NSString
        let inicioDoPrefixo = max(0, intervalo.location - tamanhoDoContexto)
        let prefixo = ns.substring(with: NSRange(location: inicioDoPrefixo, length: intervalo.location - inicioDoPrefixo))
        let fim = NSMaxRange(intervalo)
        let sufixo = ns.substring(with: NSRange(location: fim, length: min(tamanhoDoContexto, ns.length - fim)))
        return (prefixo, sufixo)
    }

    enum Resultado: Equatable {
        case encontrado(NSRange)
        /// O trecho não está mais no dispositivo (ou o dispositivo sumiu).
        case alterado(textoAtual: String?)
    }

    /// Onde o grifo está no texto atual do artigo.
    static func localizar(_ grifo: Grifo, em textos: [String: TextoAncoravel]) -> Resultado {
        guard let alvo = textos[grifo.dispositivoChave] else { return .alterado(textoAtual: nil) }
        let ns = alvo.texto as NSString
        let salvo = NSRange(location: grifo.inicio, length: grifo.fim - grifo.inicio)

        // Caminho comum: o texto não mudou.
        if NSMaxRange(salvo) <= ns.length, ns.substring(with: salvo) == grifo.trecho {
            return .encontrado(salvo)
        }

        // O dispositivo mudou, mas o trecho pode continuar lá (em outra posição).
        var ocorrencias: [NSRange] = []
        var busca = NSRange(location: 0, length: ns.length)
        while true {
            let achado = ns.range(of: grifo.trecho, options: [], range: busca)
            guard achado.location != NSNotFound else { break }
            ocorrencias.append(achado)
            let proximo = achado.location + 1
            guard proximo < ns.length else { break }
            busca = NSRange(location: proximo, length: ns.length - proximo)
        }

        guard !ocorrencias.isEmpty else { return .alterado(textoAtual: alvo.texto) }
        if ocorrencias.count == 1 { return .encontrado(ocorrencias[0]) }

        // Várias ocorrências: a que mantém o contexto; empate, a mais próxima da posição original.
        func pontos(_ r: NSRange) -> Int {
            let (prefixo, sufixo) = contexto(de: r, em: alvo.texto)
            return (prefixo.hasSuffix(grifo.prefixo) ? 2 : 0) + (sufixo.hasPrefix(grifo.sufixo) ? 2 : 0)
        }
        let melhor = ocorrencias.max { a, b in
            let (pa, pb) = (pontos(a), pontos(b))
            if pa != pb { return pa < pb }
            return abs(a.location - grifo.inicio) > abs(b.location - grifo.inicio)
        }
        return .encontrado(melhor!)
    }
}
