#!/usr/bin/env python3
"""Converte o HTML compilado do Código de Processo Civil (Lei nº 13.105/2015,
Planalto) em INSERTs SQL, no mesmo formato usado pelas demais leis (ver
api/database/CONTEUDO.md).
"""
import re
import sys
import unicodedata
from bs4 import BeautifulSoup

ENTRADA = "cpc_raw.html"
LEI_ID = 4
CATEGORIA_ID = 2  # "codigos", já existe (criada para o Código Civil)
ARTIGO_ID_INICIAL = 2939        # max(artigos.id) atual (2938) + 1
# Cascata: Código Civil (1.774 dispositivos, 2920-4693) + Código Penal (913
# dispositivos, 4694-5606) — ver CONTEUDO.md sobre a convenção de ids fixos.
DISPOSITIVO_ID_INICIAL = 5607

# Regexes tolerantes a espaço em volta do ordinal e a sufixo de letra colado
# (não separado por espaço) — ver parse_codigo_penal.py para o motivo de cada
# detalhe; aqui reaproveitados mesmo o HTML sendo mais limpo, por segurança.
RE_ARTIGO = re.compile(r"^Art\.?\s*(\d+(?:\.\d+)?)(-[A-Z](?:-[A-Z])?)?\s*(?:[ºo°])?\.?\s*[-–]*\s*(.*)$", re.S)
RE_MULTI_REVOGADO = re.compile(r"Art\.?\s*(\d+)\.\s*(\(Revogad[^)]*\))", re.I)
RE_PARAGRAFO_UNICO = re.compile(r"^Par[aá]grafo\s+[uú]nico\.?\s*[-–]?\s*(.*)$", re.S | re.I)
RE_PARAGRAFO = re.compile(r"^§\s*(\d+)\s*(?:[ºo°])?\s*(?:-([A-Z](?:-[A-Z])?)\b)?\.?\s*[-–]?\s*(.*)$", re.S)
RE_INCISO = re.compile(r"^([IVXLCDM]+)(?:\s*[-–]\s*|\s+)(.*)$", re.S)
RE_ALINEA = re.compile(r"^([a-z])\)\s*(.*)$", re.S)

RE_HEADING_PARTE = re.compile(r"^PARTE\s+(\w+)", re.I)
RE_HEADING_GENERICO = re.compile(
    r"^(LIVRO|T[IÍ]TULO|CAP[IÍ]TULO|SUBSE[CÇ][AÃ]O|SE[CÇ][AÃ]O)\s+([IVXLCDM]+(?:-[A-Z])?|[UÚ]nic[oa])\b", re.I
)
CANONICO = {
    "LIVRO": "Livro",
    "TITULO": "Título", "TÍTULO": "Título",
    "CAPITULO": "Capítulo", "CAPÍTULO": "Capítulo",
    "SECAO": "Seção", "SEÇAO": "Seção", "SECÃO": "Seção", "SEÇÃO": "Seção",
    "SUBSECAO": "Subseção", "SUBSEÇAO": "Subseção", "SUBSECÃO": "Subseção", "SUBSEÇÃO": "Subseção",
}

# "(Revogado...)" e "(VETADO)" recebem o mesmo tratamento visual no app (selo
# "Revogado") — um dispositivo vetado também nunca teve força de lei.
RE_REVOGADO_INICIO = re.compile(r"^\(?(revogad[ao]s?|vetado)\b", re.I)

# Abre quando uma linha começa com aspas curvas (uma citação literal do texto
# de OUTRA lei, dentro de um artigo do CPC que a está alterando — ex. Art.
# 1.067 cita o "Art. 275" do Código Eleitoral). Enquanto aberta, tudo é
# continuação do caput do artigo do CPC que abriu a citação, nunca um
# dispositivo novo — senão o "Art. 275" citado criaria uma entrada fantasma
# colidindo com um artigo real do CPC de mesmo número.
ASPA_ABRE = "“"
ASPA_FECHA = "”"


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
    (Vigência)" — sobra só o texto descritivo, se houver."""
    anterior = None
    while anterior != texto:
        anterior = texto
        texto = re.sub(r"\s*\([^()]*\)\.?\s*$", "", texto).strip()
        texto = re.sub(r"\s+Vig[eê]ncia\s*$", "", texto, flags=re.I).strip()
    return texto


def normalizar_descricao(texto):
    """"DOS ATOS DAS PARTES" (caixa alta) -> "Dos atos das partes"."""
    if not texto:
        return None
    return texto[0].upper() + texto[1:].lower()


class Artigo:
    def __init__(self, numero, contexto, descricao=None, rubrica=None):
        self.numero = numero
        self.caput = ""
        self.revogado = False
        self.contexto = contexto  # (parte, livro, titulo, capitulo, secao, subsecao)
        self.descricao = descricao
        self.rubrica = rubrica
        self.dispositivos = []


def montar_titulo_estrutural(parte, livro, titulo):
    partes = [p for p in [parte, livro, titulo] if p]
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


def main():
    with open(ENTRADA, "rb") as f:
        # Mesmo gerador do Código Penal (Microsoft FrontPage) — Windows-1252,
        # não ISO-8859-1 puro (aspas curvas e travessão em bytes 0x93/0x94/0x96).
        html = f.read().decode("cp1252")

    soup = BeautifulSoup(html, "html.parser")
    for strike in soup.find_all("strike"):
        strike.decompose()
    # Redação superada também aparece marcada só por CSS inline, sem <strike>
    # (ex.: Art. 153 tem duas declarações completas — a de 2015 e a redação
    # dada depois — e só a inline-styled é a antiga).
    for riscado in soup.find_all(style=lambda v: v and "line-through" in v):
        riscado.decompose()

    parte_atual = livro_atual = titulo_atual = capitulo_atual = secao_atual = subsecao_atual = None
    descricao_parte = descricao_livro = descricao_titulo = None
    descricao_capitulo = descricao_secao = descricao_subsecao = None
    pendente_nivel = None
    rubrica_pendente = None
    artigos: list[Artigo] = []
    artigo_atual = None
    pilha_nivel: dict[int, int] = {}
    nivel_container = 0
    em_citacao = False
    dentro_do_corpo = False

    def descricao_atual():
        return descricao_subsecao or descricao_secao or descricao_capitulo or descricao_titulo or descricao_livro or descricao_parte

    for p in soup.find_all("p"):
        texto = limpar_texto(p.get_text(" ", strip=True))
        if not texto:
            continue

        if not dentro_do_corpo:
            if texto.startswith("A PRESIDENTA DA REP") or texto.startswith("O PRESIDENTE DA REP"):
                dentro_do_corpo = True
            continue
        if texto.startswith("Brasília,") or texto == "ÍNDICE" or texto.startswith("Este texto"):
            break

        if em_citacao:
            if artigo_atual is not None:
                artigo_atual.caput = (artigo_atual.caput + " " + texto).strip()
            if ASPA_FECHA in texto:
                em_citacao = False
            continue

        if texto.startswith(ASPA_ABRE):
            if artigo_atual is not None:
                artigo_atual.caput = (artigo_atual.caput + " " + texto).strip()
            em_citacao = ASPA_FECHA not in texto
            rubrica_pendente = None
            continue

        eh_centralizado = (p.get("align") or "").upper() == "CENTER"

        if eh_centralizado:
            if pendente_nivel is not None:
                nivel_pendente, pendente_nivel = pendente_nivel, None
                if not RE_HEADING_PARTE.match(texto) and not formatar_heading(texto):
                    desc = normalizar_descricao(limpar_citacoes(texto))
                    if desc:
                        if nivel_pendente == "parte":
                            descricao_parte = desc
                        elif nivel_pendente == "livro":
                            descricao_livro = desc
                        elif nivel_pendente == "titulo":
                            descricao_titulo = desc
                        elif nivel_pendente == "capitulo":
                            descricao_capitulo = desc
                        elif nivel_pendente == "secao":
                            descricao_secao = desc
                        elif nivel_pendente == "subsecao":
                            descricao_subsecao = desc
                    continue

            m_parte = RE_HEADING_PARTE.match(texto)
            if m_parte:
                parte_atual = f"Parte {m_parte.group(1).capitalize()}"
                livro_atual = titulo_atual = capitulo_atual = secao_atual = subsecao_atual = None
                descricao_parte = descricao_livro = descricao_titulo = None
                descricao_capitulo = descricao_secao = descricao_subsecao = None
                resto = limpar_citacoes(texto[m_parte.end():].strip())
                if resto:
                    descricao_parte = normalizar_descricao(resto)
                else:
                    pendente_nivel = "parte"
                continue

            heading = formatar_heading(texto)
            if heading:
                m_h = RE_HEADING_GENERICO.match(texto)
                resto = limpar_citacoes(texto[m_h.end():].strip())
                desc = normalizar_descricao(resto) if resto else None
                if heading.startswith("Livro"):
                    livro_atual = heading
                    titulo_atual = capitulo_atual = secao_atual = subsecao_atual = None
                    descricao_titulo = descricao_capitulo = descricao_secao = descricao_subsecao = None
                    descricao_livro = desc
                    if desc is None:
                        pendente_nivel = "livro"
                elif heading.startswith("Título"):
                    titulo_atual = heading
                    capitulo_atual = secao_atual = subsecao_atual = None
                    descricao_capitulo = descricao_secao = descricao_subsecao = None
                    descricao_titulo = desc
                    if desc is None:
                        pendente_nivel = "titulo"
                elif heading.startswith("Capítulo"):
                    capitulo_atual = heading
                    secao_atual = subsecao_atual = None
                    descricao_secao = descricao_subsecao = None
                    descricao_capitulo = desc
                    if desc is None:
                        pendente_nivel = "capitulo"
                elif heading.startswith("Subseção"):
                    subsecao_atual = heading
                    descricao_subsecao = desc
                    if desc is None:
                        pendente_nivel = "subsecao"
                elif heading.startswith("Seção"):
                    secao_atual = heading
                    subsecao_atual = None
                    descricao_subsecao = None
                    descricao_secao = desc
                    if desc is None:
                        pendente_nivel = "secao"
                continue
            continue  # cabeçalho centralizado não reconhecido — ignora

        revogados_em_bloco = RE_MULTI_REVOGADO.findall(texto)
        if len(revogados_em_bloco) >= 2:
            for numero, revtxt in revogados_em_bloco:
                artigo_atual = Artigo(
                    numero, (parte_atual, livro_atual, titulo_atual, capitulo_atual, secao_atual, subsecao_atual),
                    descricao=descricao_atual(),
                )
                artigo_atual.caput = revtxt
                artigo_atual.revogado = True
                artigos.append(artigo_atual)
            pilha_nivel = {}
            nivel_container = 0
            rubrica_pendente = None
            continue

        m = RE_ARTIGO.match(texto)
        if m:
            numero = normalizar_numero(m.group(1))
            if m.group(2):
                numero += m.group(2)
            resto = m.group(3).strip()
            artigo_atual = Artigo(
                numero, (parte_atual, livro_atual, titulo_atual, capitulo_atual, secao_atual, subsecao_atual),
                descricao=descricao_atual(), rubrica=rubrica_pendente,
            )
            rubrica_pendente = None
            artigo_atual.caput = resto
            if RE_REVOGADO_INICIO.match(resto):
                artigo_atual.revogado = True
            artigos.append(artigo_atual)
            pilha_nivel = {}
            nivel_container = 0
            continue

        if artigo_atual is None:
            rubrica_pendente = None
            continue  # nota antes do primeiro artigo — descarta

        m = RE_PARAGRAFO_UNICO.match(texto)
        if m:
            adicionar_dispositivo(artigo_atual, pilha_nivel, "paragrafo", "Parágrafo único", m.group(1).strip(), nivel=1)
            nivel_container = 1
            rubrica_pendente = None
            continue

        m = RE_PARAGRAFO.match(texto)
        if m:
            numero_paragrafo = int(m.group(1))
            sufixo = f"-{m.group(2)}" if m.group(2) else ""
            rotulo = f"§ {numero_paragrafo}º{sufixo}" if numero_paragrafo < 10 else f"§ {numero_paragrafo}{sufixo}"
            adicionar_dispositivo(artigo_atual, pilha_nivel, "paragrafo", rotulo, m.group(3).strip(), nivel=1)
            nivel_container = 1
            rubrica_pendente = None
            continue

        m = RE_INCISO.match(texto)
        if m:
            nivel = 2 if (1 in pilha_nivel and artigo_atual.dispositivos[pilha_nivel[1]]["tipo"] == "paragrafo") else 1
            adicionar_dispositivo(artigo_atual, pilha_nivel, "inciso", m.group(1), m.group(2).strip(), nivel=nivel)
            nivel_container = nivel
            rubrica_pendente = None
            continue

        m = RE_ALINEA.match(texto)
        if m:
            adicionar_dispositivo(artigo_atual, pilha_nivel, "alinea", f"{m.group(1)})", m.group(2).strip(), nivel=nivel_container + 1)
            rubrica_pendente = None
            continue

        if texto.lower().startswith("pena"):
            if pilha_nivel:
                ultimo_nivel = max(pilha_nivel.keys())
                disp = artigo_atual.dispositivos[pilha_nivel[ultimo_nivel]]
                disp["texto"] = (disp["texto"] + " " + texto).strip()
            else:
                artigo_atual.caput = (artigo_atual.caput + " " + texto).strip()
            rubrica_pendente = None
            continue

        # Não bate com nenhum padrão conhecido: candidata a rubrica do
        # PRÓXIMO "Art." (mesma lógica do Código Penal) — descartada se não
        # for seguida de um (os "rubrica_pendente = None" acima).
        rubrica_pendente = limpar_citacoes(texto) or None

    emitir_sql(artigos)


def sql_str(v):
    if v is None:
        return "NULL"
    v = str(v).replace("\\", "\\\\").replace("'", "\\'")
    return f"'{v}'"


def emitir_sql(artigos: list):
    out = sys.stdout
    out.write("-- Código Brasil — seed: Código de Processo Civil (Lei nº 13.105/2015)\n")
    out.write("-- Gerado a partir de https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2015/lei/l13105.htm\n")
    out.write("-- Idempotente: apaga e recria os dados desta lei (categoria_id/lei_id fixos) a cada execução.\n\n")

    out.write("SET FOREIGN_KEY_CHECKS=0;\n")
    out.write(f"DELETE FROM artigo_dispositivos WHERE artigo_id IN (SELECT id FROM artigos WHERE lei_id = {LEI_ID});\n")
    out.write(f"DELETE FROM artigos WHERE lei_id = {LEI_ID};\n")
    out.write(f"DELETE FROM leis WHERE id = {LEI_ID};\n")
    out.write("SET FOREIGN_KEY_CHECKS=1;\n\n")

    out.write(f"INSERT IGNORE INTO categorias (id, slug, nome) VALUES ({CATEGORIA_ID}, 'codigos', 'Códigos');\n\n")

    out.write("INSERT INTO leis (id, categoria_id, slug, titulo, descricao, fonte_url) VALUES\n")
    out.write(
        f"({LEI_ID}, {CATEGORIA_ID}, 'codigo-processo-civil-2015', "
        f"'Código de Processo Civil (Lei nº 13.105, de 2015)', "
        f"'Institui o Código de Processo Civil, atualizado até a última alteração compilada pelo Planalto.', "
        f"'https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2015/lei/l13105.htm');\n\n"
    )

    artigo_rows = []
    disp_rows = []
    artigo_id = ARTIGO_ID_INICIAL
    disp_id = DISPOSITIVO_ID_INICIAL
    ordem_artigo = 1

    for artigo in artigos:
        parte, livro, titulo, capitulo, secao, subsecao = artigo.contexto
        titulo_estrutural = montar_titulo_estrutural(parte, livro, titulo)

        artigo_rows.append(
            "(" + ", ".join([
                str(artigo_id), str(LEI_ID), sql_str("permanente"), sql_str(artigo.numero),
                sql_str(titulo_estrutural), sql_str(capitulo), sql_str(secao), sql_str(subsecao),
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
