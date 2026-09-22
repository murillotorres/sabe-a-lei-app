#!/usr/bin/env python3
"""Converte o HTML compilado do Código Penal (Planalto) em INSERTs SQL, no
mesmo formato usado pela Constituição/Código Civil (ver api/database/CONTEUDO.md).

Diferente do Código Civil, este HTML (Decreto-Lei nº 2.848/1940) tem marcação
muito mais malformada (tags não fechadas cruzando limites de <p>, herança de
décadas de emendas com ferramentas de autoria diferentes) — por isso não usa
BeautifulSoup para montar a árvore (perde conteúdo em alguns pontos, ver
CONTEUDO.md), e sim um split direto no texto bruto pelas aberturas de <p>.
"""
import re
import sys
import html as htmllib
import unicodedata

ENTRADA = "codigo_penal_raw.html"
LEI_ID = 3
CATEGORIA_ID = 2  # "codigos", já existe (criada para o Código Civil)
ARTIGO_ID_INICIAL = 2505        # max(artigos.id) atual (2504) + 1
# O Código Civil foi reprocessado depois (fix de encoding cp1252) e passou de
# 1.751 pra 1.774 dispositivos, então o próximo id livre subiu de 4671 pra
# 4694 — ver CONTEUDO.md sobre a convenção de ids fixos por lei.
DISPOSITIVO_ID_INICIAL = 4694

# "Art" às vezes aparece com espaço espúrio ("A rt. 107") — resíduo de OCR/cópia
# do próprio site do Planalto. O sufixo de letra (121-A) e o ordinal (1º/2º) às
# vezes vêm com espaço em volta por causa de <sup>o</sup> nos ordinais antigos
# (ver limpar_texto/RE_PARAGRAFO abaixo), então os separadores são tolerantes.
# O sufixo de letra pode ter duas letras (ex. "Art. 359-M-A", nos crimes
# contra o Estado Democrático de Direito incluídos em 2021) — daí o
# "(?:-[A-Z])?" opcional dentro do próprio grupo da letra.
# O traço do sufixo tem que vir colado no número ("120-A"), sem espaço — do
# contrário "Art. 120 - A sentença..." (separador antes de frase começando
# por "A") seria lido como o artigo "120-A" por engano.
RE_ARTIGO = re.compile(r"^A\s?rt\.?\s*(\d+(?:\.\d+)?)(-[A-Z](?:-[A-Z])?)?\s*(?:[ºo°])?\.?\s*[-–]*\s*(.*)$", re.S)
# Bloco de artigos revogados comprimidos em um único parágrafo (ex.: Arts.
# 187 a 196, revogados em bloco pela Lei de Propriedade Industrial) — cada
# "Art. N. (Revogado...)" vira um artigo, descartando rubricas entre eles.
RE_MULTI_REVOGADO = re.compile(r"Art\.?\s*(\d+)\.\s*(\(Revogad[^)]*\))")
RE_PARAGRAFO_UNICO = re.compile(r"^Par[aá]grafo\s+[uú]nico\.?\s*[-–]?\s*(.*)$", re.S | re.I)
# O ordinal (º) em muitos §§ antigos vem de "<sup>o</sup>", que ao virar texto
# puro fica " o " (com espaços) em vez de colado — por isso há tolerância de
# espaço ANTES do traço do sufixo de letra, mas não DEPOIS: "2º-A" (sufixo
# real, sem espaço entre o traço e a letra) precisa se distinguir de "3º - A
# lei..." (separador solto antes de uma frase que começa com "A").
RE_PARAGRAFO = re.compile(r"^§\s*(\d+)\s*(?:[ºo°])?\s*(?:-([A-Z](?:-[A-Z])?)\b)?\.?\s*[-–]?\s*(.*)$", re.S)
# Dash opcional: "III perda..." (sem traço) é um typo real do texto oficial.
RE_INCISO = re.compile(r"^([IVXLCDM]+)(?:\s*[-–]\s*|\s+)(.*)$", re.S)
RE_ALINEA = re.compile(r"^([a-z])\)\s*(.*)$", re.S)

RE_HEADING_PARTE = re.compile(r"^PARTE\s+(\w+)", re.I)
RE_HEADING_GENERICO = re.compile(
    r"^(T[IÍ]TULO|CAP[IÍ]TULO|SE[CÇ][AÃ]O)\s+([IVXLCDM]+(?:-[A-Z])?|[UÚ]nic[oa])\b", re.I
)
CANONICO = {
    "TITULO": "Título", "TÍTULO": "Título",
    "CAPITULO": "Capítulo", "CAPÍTULO": "Capítulo",
    "SECAO": "Seção", "SEÇAO": "Seção", "SECÃO": "Seção", "SEÇÃO": "Seção",
}

RE_REVOGADO_INICIO = re.compile(r"^\(?revogad[ao]s?\b", re.I)


def limpar_texto(txt: str) -> str:
    txt = unicodedata.normalize("NFC", txt)
    txt = txt.replace("\xa0", " ")
    txt = re.sub(r"\s+", " ", txt).strip()
    txt = re.sub(r"\s+([;:,\.\)])", r"\1", txt)
    txt = re.sub(r"\(\s+", "(", txt)
    return txt.strip()


def normalizar_numero(numero: str) -> str:
    return numero.replace(".", "")


def formatar_heading(texto):
    m = RE_HEADING_GENERICO.match(texto)
    if not m:
        return None
    rotulo = CANONICO.get(m.group(1).upper(), m.group(1).capitalize())
    numeral = m.group(2)
    if not re.match(r"^[IVXLCDM]+(-[A-Z])?$", numeral, re.I):
        numeral = numeral.capitalize()
    return f"{rotulo} {numeral}"


def limpar_citacoes(texto: str) -> str:
    """Remove parênteses finais em cadeia, tipo "(Incluído pela Lei nº X)
    (Vigência)" — sobra só o texto descritivo, se houver. Tolera um ponto
    final depois do parêntese (typo real do texto oficial em pelo menos um
    caso) e um "Vigência" solto sem parênteses no fim (idem)."""
    anterior = None
    while anterior != texto:
        anterior = texto
        texto = re.sub(r"\s*\([^()]*\)\.?\s*$", "", texto).strip()
        texto = re.sub(r"\s+Vig[eê]ncia\s*$", "", texto, flags=re.I).strip()
    return texto


def normalizar_descricao(texto):
    """"DO CRIME" (caixa alta, como vem do centralizado) -> "Do crime"."""
    if not texto:
        return None
    return texto[0].upper() + texto[1:].lower()


class Artigo:
    def __init__(self, numero, contexto, descricao=None, rubrica=None):
        self.numero = numero
        self.caput = ""
        self.revogado = False
        self.contexto = contexto  # (parte, titulo, capitulo, secao)
        # Descrição do cabeçalho estrutural mais específico em vigor (ex.:
        # "Do crime") e rubrica/epígrafe do próprio artigo (ex.: "Relação de
        # causalidade") — ambos None quando a lei não usa a convenção.
        self.descricao = descricao
        self.rubrica = rubrica
        self.dispositivos = []


def montar_titulo_estrutural(parte, titulo):
    partes = [p for p in [parte, titulo] if p]
    return " · ".join(partes) if partes else None


def adicionar_dispositivo(artigo: Artigo, pilha_nivel: dict, tipo: str, rotulo: str, texto: str, nivel: int):
    revogado = bool(RE_REVOGADO_INICIO.match(texto))
    parent_idx = pilha_nivel.get(nivel - 1) if nivel > 1 else None
    artigo.dispositivos.append({
        "tipo": tipo, "rotulo": rotulo, "texto": texto,
        "nivel": nivel, "parent_idx": parent_idx, "revogado": revogado,
    })
    pilha_nivel[nivel] = len(artigo.dispositivos) - 1
    for n in list(pilha_nivel.keys()):
        if n > nivel:
            del pilha_nivel[n]


def extrair_paragrafos(html: str):
    """Divide o HTML bruto pelas aberturas de <p>, sem montar árvore DOM.

    O parser da Constituição/Código Civil usa BeautifulSoup normalmente, mas
    neste documento tags não fechadas (<font>/<b>/<i> cruzando limites de <p>)
    fazem tanto html.parser quanto lxml perderem parágrafos inteiros (ex.:
    Art. 1º e Art. 184 somem, ver CONTEUDO.md). Cortar direto no texto bruto
    pela posição de cada "<p...>" evita depender da reconstrução de árvore.
    """
    partes = re.split(r"<p\b([^>]*)>", html, flags=re.I)
    resultado = []
    for i in range(1, len(partes), 2):
        attrs = partes[i]
        conteudo_html = partes[i + 1] if i + 1 < len(partes) else ""
        texto = re.sub(r"<[^>]+>", " ", conteudo_html)
        texto = htmllib.unescape(texto)
        texto = limpar_texto(texto)
        m = re.search(r'align\s*=\s*"?([a-zA-Z]+)"?', attrs, re.I)
        align = m.group(1).upper() if m else ""
        resultado.append((align, texto))
    return resultado


def main():
    with open(ENTRADA, "rb") as f:
        # O gerador (Microsoft FrontPage 6.0) grava em Windows-1252, não
        # ISO-8859-1 puro: bytes como 0x96 (travessão usado em muitos incisos)
        # só decodificam certo em cp1252 — em iso-8859-1 viram caracteres de
        # controle e quebram o RE_INCISO.
        html = f.read().decode("cp1252")

    paragrafos = extrair_paragrafos(html)

    inicio = next(i for i, (_, t) in enumerate(paragrafos) if t.startswith("O PRESIDENTE DA REP"))
    fim = len(paragrafos)
    for i in range(inicio + 1, len(paragrafos)):
        if paragrafos[i][1].startswith("Este texto"):
            fim = i
            break

    parte_atual = titulo_atual = capitulo_atual = secao_atual = None
    descricao_parte = descricao_titulo = descricao_capitulo = descricao_secao = None
    # Quando um cabeçalho centralizado não tem descrição colada na mesma linha
    # (ex.: "CAPÍTULO I-A (Incluído...)"), ela pode vir como a PRÓXIMA linha
    # centralizada sozinha ("DA EXPOSIÇÃO DA INTIMIDADE SEXUAL") — esta
    # variável guarda qual nível está esperando essa segunda linha.
    pendente_nivel = None
    # Última linha não reconhecida antes de um "Art." novo — vira a rubrica
    # desse artigo (ex.: "Relação de causalidade" antes do Art. 13). Zerada
    # sempre que qualquer outra coisa é processada, pra não vazar pra um
    # artigo mais adiante sem relação nenhuma com ela.
    rubrica_pendente = None
    artigos: list[Artigo] = []
    artigo_atual = None
    pilha_nivel: dict[int, int] = {}
    # Nivel do último parágrafo/inciso aberto — as alíneas penduram nele
    # (nivel_container + 1), não em "max(pilha_nivel)": esse último inclui a
    # própria alínea anterior depois que ela é inserida, o que faria cada
    # alínea de uma lista (a, b, c, d...) virar filha da anterior em vez de
    # irmã (bug encontrado e corrigido aqui; não existia neste parser antes
    # porque nenhuma lei processada tinha sequências longas de alíneas).
    nivel_container = 0

    def descricao_atual():
        return descricao_secao or descricao_capitulo or descricao_titulo or descricao_parte

    def processar_linha(texto):
        nonlocal artigo_atual, pilha_nivel, nivel_container, rubrica_pendente

        m = RE_ARTIGO.match(texto)
        if m:
            numero = normalizar_numero(m.group(1))
            if m.group(2):
                numero += m.group(2)  # já vem com o traço (grupo é "-[A-Z]...")
            resto = m.group(3).strip()
            artigo_atual = Artigo(
                numero, (parte_atual, titulo_atual, capitulo_atual, secao_atual),
                descricao=descricao_atual(), rubrica=rubrica_pendente,
            )
            rubrica_pendente = None
            artigo_atual.caput = resto
            if RE_REVOGADO_INICIO.match(resto):
                artigo_atual.revogado = True
            artigos.append(artigo_atual)
            pilha_nivel = {}
            nivel_container = 0
            return

        if artigo_atual is None:
            rubrica_pendente = None
            return  # nota antes do primeiro artigo — descarta

        m = RE_PARAGRAFO_UNICO.match(texto)
        if m:
            adicionar_dispositivo(artigo_atual, pilha_nivel, "paragrafo", "Parágrafo único", m.group(1).strip(), nivel=1)
            nivel_container = 1
            rubrica_pendente = None
            return

        m = RE_PARAGRAFO.match(texto)
        if m:
            numero_paragrafo = int(m.group(1))
            sufixo = f"-{m.group(2)}" if m.group(2) else ""
            rotulo = f"§ {numero_paragrafo}º{sufixo}" if numero_paragrafo < 10 else f"§ {numero_paragrafo}{sufixo}"
            adicionar_dispositivo(artigo_atual, pilha_nivel, "paragrafo", rotulo, m.group(3).strip(), nivel=1)
            nivel_container = 1
            rubrica_pendente = None
            return

        m = RE_INCISO.match(texto)
        if m:
            nivel = 2 if (1 in pilha_nivel and artigo_atual.dispositivos[pilha_nivel[1]]["tipo"] == "paragrafo") else 1
            adicionar_dispositivo(artigo_atual, pilha_nivel, "inciso", m.group(1), m.group(2).strip(), nivel=nivel)
            nivel_container = nivel
            rubrica_pendente = None
            return

        m = RE_ALINEA.match(texto)
        if m:
            adicionar_dispositivo(artigo_atual, pilha_nivel, "alinea", f"{m.group(1)})", m.group(2).strip(), nivel=nivel_container + 1)
            rubrica_pendente = None
            return

        if texto.lower().startswith("pena"):
            # Linha de cominação de pena: não é um dispositivo numerado próprio,
            # mas pertence ao artigo/dispositivo aberto no momento — mantém a
            # info sem inventar um tipo novo no schema.
            if pilha_nivel:
                ultimo_nivel = max(pilha_nivel.keys())
                disp = artigo_atual.dispositivos[pilha_nivel[ultimo_nivel]]
                disp["texto"] = (disp["texto"] + " " + texto).strip()
            else:
                artigo_atual.caput = (artigo_atual.caput + " " + texto).strip()
            rubrica_pendente = None
            return

        # Não bate com nenhum padrão conhecido: no restante do documento (ver
        # levantamento em CONTEUDO.md) isso é quase sempre rubrica marginal
        # ("nome do crime", ex. "Homicídio simples") ou nota de rodapé — nunca
        # uma continuação real de frase entre <p>s. Guarda como candidata a
        # rubrica do PRÓXIMO "Art." (se não for seguida de um, é descartada
        # pelos "rubrica_pendente = None" nos outros ramos acima).
        rubrica_pendente = limpar_citacoes(texto) or None

    for i in range(inicio + 1, fim):
        align, texto = paragrafos[i]
        if not texto:
            continue

        if align == "CENTER":
            # Uma linha centralizada pendente de descrição (ver mais abaixo)
            # se resolve aqui, desde que esta linha não seja ela mesma um
            # cabeçalho novo — senão a "descrição" pendente fica None mesmo.
            if pendente_nivel is not None:
                nivel_pendente, pendente_nivel = pendente_nivel, None
                if not RE_HEADING_PARTE.match(texto) and not formatar_heading(texto):
                    desc = normalizar_descricao(limpar_citacoes(texto))
                    if nivel_pendente == "parte":
                        descricao_parte = desc
                    elif nivel_pendente == "titulo":
                        descricao_titulo = desc
                    elif nivel_pendente == "capitulo":
                        descricao_capitulo = desc
                    elif nivel_pendente == "secao":
                        descricao_secao = desc
                    continue

            m_parte = RE_HEADING_PARTE.match(texto)
            if m_parte:
                parte_atual = f"Parte {m_parte.group(1).capitalize()}"
                titulo_atual = capitulo_atual = secao_atual = None
                descricao_parte = descricao_titulo = descricao_capitulo = descricao_secao = None
                rubrica_pendente = None
                # Único caso do documento em que "PARTE ... TÍTULO ..." vêm
                # colados num <p> só (o cabeçalho de abertura) — o resto do
                # texto após "PARTE GERAL" ainda pode conter o Título.
                resto = texto[m_parte.end():].strip()
                heading2 = formatar_heading(resto)
                if heading2 and heading2.startswith("Título"):
                    titulo_atual = heading2
                    m_h2 = RE_HEADING_GENERICO.match(resto)
                    desc2 = limpar_citacoes(resto[m_h2.end():].strip())
                    if desc2:
                        descricao_titulo = normalizar_descricao(desc2)
                    else:
                        pendente_nivel = "titulo"
                else:
                    resto_limpo = limpar_citacoes(resto)
                    if resto_limpo:
                        descricao_parte = normalizar_descricao(resto_limpo)
                    else:
                        pendente_nivel = "parte"
                continue

            heading = formatar_heading(texto)
            if heading:
                m_h = RE_HEADING_GENERICO.match(texto)
                resto_limpo = limpar_citacoes(texto[m_h.end():].strip())
                desc = normalizar_descricao(resto_limpo) if resto_limpo else None
                rubrica_pendente = None
                if heading.startswith("Título"):
                    titulo_atual = heading
                    capitulo_atual = secao_atual = None
                    descricao_titulo = desc
                    descricao_capitulo = descricao_secao = None
                    if desc is None:
                        pendente_nivel = "titulo"
                elif heading.startswith("Capítulo"):
                    capitulo_atual = heading
                    secao_atual = None
                    descricao_capitulo = desc
                    descricao_secao = None
                    if desc is None:
                        pendente_nivel = "capitulo"
                elif heading.startswith("Seção"):
                    secao_atual = heading
                    descricao_secao = desc
                    if desc is None:
                        pendente_nivel = "secao"
                continue
            continue  # cabeçalho não reconhecido (ex. "DISPOSIÇÕES FINAIS") — ignora

        # >= 1 (não só >= 2): mesmo um artigo revogado sozinho pode ter uma
        # rubrica antes ("Concorrência desleal Art. 196. (Revogado...)"), o
        # que faz RE_ARTIGO (ancorado no início da linha) não bater.
        revogados_em_bloco = RE_MULTI_REVOGADO.findall(texto)
        if len(revogados_em_bloco) >= 1:
            for numero, revtxt in revogados_em_bloco:
                artigo_atual = Artigo(
                    numero, (parte_atual, titulo_atual, capitulo_atual, secao_atual),
                    descricao=descricao_atual(),
                )
                artigo_atual.caput = revtxt
                artigo_atual.revogado = True
                artigos.append(artigo_atual)
            pilha_nivel = {}
            rubrica_pendente = None
            continue

        processar_linha(texto)

    emitir_sql(artigos)


def sql_str(v):
    if v is None:
        return "NULL"
    v = str(v).replace("\\", "\\\\").replace("'", "\\'")
    return f"'{v}'"


def emitir_sql(artigos: list):
    out = sys.stdout
    out.write("-- Sabe a Lei — seed: Código Penal (Decreto-Lei nº 2.848/1940)\n")
    out.write("-- Gerado a partir de https://www.planalto.gov.br/ccivil_03/decreto-lei/del2848compilado.htm\n")
    out.write("-- Idempotente: apaga e recria os dados desta lei (categoria_id/lei_id fixos) a cada execução.\n\n")

    # FOREIGN_KEY_CHECKS=0 ao redor do DELETE: artigo_dispositivos tem uma FK
    # de auto-relacionamento (parent_id), e um artigo com alíneas encadeadas
    # (parágrafo > inciso > alínea) faz o MySQL recusar o DELETE em lote — ele
    # tenta apagar uma linha "pai" antes da "filha" que ainda aponta pra ela,
    # já que a ordem de um DELETE de múltiplas linhas não é garantida.
    out.write("SET FOREIGN_KEY_CHECKS=0;\n")
    out.write(f"DELETE FROM artigo_dispositivos WHERE artigo_id IN (SELECT id FROM artigos WHERE lei_id = {LEI_ID});\n")
    out.write(f"DELETE FROM artigos WHERE lei_id = {LEI_ID};\n")
    out.write(f"DELETE FROM leis WHERE id = {LEI_ID};\n")
    out.write("SET FOREIGN_KEY_CHECKS=1;\n\n")

    out.write(
        f"INSERT IGNORE INTO categorias (id, slug, nome) VALUES ({CATEGORIA_ID}, 'codigos', 'Códigos');\n\n"
    )

    out.write("INSERT INTO leis (id, categoria_id, slug, titulo, descricao, fonte_url) VALUES\n")
    out.write(
        f"({LEI_ID}, {CATEGORIA_ID}, 'codigo-penal-1940', "
        f"'Código Penal (Decreto-Lei nº 2.848, de 1940)', "
        f"'Institui o Código Penal, atualizado até a última alteração compilada pelo Planalto.', "
        f"'https://www.planalto.gov.br/ccivil_03/decreto-lei/del2848compilado.htm');\n\n"
    )

    artigo_rows = []
    disp_rows = []
    artigo_id = ARTIGO_ID_INICIAL
    disp_id = DISPOSITIVO_ID_INICIAL
    ordem_artigo = 1

    for artigo in artigos:
        parte, titulo, capitulo, secao = artigo.contexto
        titulo_estrutural = montar_titulo_estrutural(parte, titulo)

        artigo_rows.append(
            "(" + ", ".join([
                str(artigo_id), str(LEI_ID), sql_str("permanente"), sql_str(artigo.numero),
                sql_str(titulo_estrutural), sql_str(capitulo), sql_str(secao), "NULL",
                sql_str(artigo.descricao), sql_str(artigo.rubrica),
                sql_str(artigo.caput), "1" if artigo.revogado else "0", str(ordem_artigo),
            ]) + ")"
        )

        ordem_disp = 1
        idx_para_id = {}
        for idx, d in enumerate(artigo.dispositivos):
            parent_id = idx_para_id.get(d["parent_idx"]) if d["parent_idx"] is not None else None
            disp_rows.append(
                "(" + ", ".join([
                    str(disp_id), str(artigo_id), str(parent_id) if parent_id is not None else "NULL",
                    sql_str(d["tipo"]), sql_str(d["rotulo"]), sql_str(d["texto"]),
                    str(d["nivel"]), "1" if d["revogado"] else "0", str(ordem_disp),
                ]) + ")"
            )
            idx_para_id[idx] = disp_id
            disp_id += 1
            ordem_disp += 1

        artigo_id += 1
        ordem_artigo += 1

    out.write(
        "INSERT INTO artigos (id, lei_id, parte, numero, titulo_estrutural, capitulo_estrutural, "
        "secao_estrutural, subsecao_estrutural, descricao_estrutural, rubrica, caput, revogado, ordem) VALUES\n"
    )
    out.write(",\n".join(artigo_rows) + ";\n\n")

    if disp_rows:
        out.write(
            "INSERT INTO artigo_dispositivos (id, artigo_id, parent_id, tipo, rotulo, texto, nivel, revogado, ordem) VALUES\n"
        )
        out.write(",\n".join(disp_rows) + ";\n")

    sys.stderr.write(f"Artigos: {len(artigo_rows)}\nDispositivos: {len(disp_rows)}\n")


if __name__ == "__main__":
    main()
