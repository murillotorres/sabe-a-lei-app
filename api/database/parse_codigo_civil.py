#!/usr/bin/env python3
"""Converte o HTML compilado do Código Civil (Planalto) em INSERTs SQL,
no mesmo formato usado pela Constituição (ver api/database/CONTEUDO.md).
"""
import re
import sys
import unicodedata
from bs4 import BeautifulSoup

ENTRADA = "codigo_civil_raw.html"
LEI_ID = 2
CATEGORIA_ID = 2
ARTIGO_ID_INICIAL = 413        # max(artigos.id) atual (412) + 1
DISPOSITIVO_ID_INICIAL = 2920  # max(artigo_dispositivos.id) atual (2919) + 1

RE_ARTIGO = re.compile(r"^Art\.?\s*(\d+(?:\.\d+)?(?:-[A-Z])?)[ºo°]?\.?\s*(.*)$", re.S)
# Caso raro: uma faixa de artigos revogados em bloco, ex. "Art. 1.620. a 1.629.
# (Revogados pela Lei nº 12.010, de 2009)" — vira uma linha por artigo do intervalo.
RE_ARTIGO_INTERVALO = re.compile(r"^Art\.?\s*(\d+(?:\.\d+)?)\.?\s*a\s*(\d+(?:\.\d+)?)\.?\s*(.*)$", re.S | re.I)
RE_PARAGRAFO_UNICO = re.compile(r"^Par[aá]grafo\s+[uú]nico\.?\s*(.*)$", re.S | re.I)
RE_PARAGRAFO = re.compile(r"^§\s*(\d+)[ºo°]?\.?\s*(.*)$", re.S)
RE_INCISO = re.compile(r"^([IVXLCDM]+)\s*[-–]\s*(.*)$", re.S)
RE_ALINEA = re.compile(r"^([a-z])\)\s*(.*)$", re.S)

RE_HEADING_PARTE = re.compile(r"^PARTE\s+(\w+)", re.I)
# \b depois do numeral evita casar só o prefixo de uma palavra (ex.: "C" em
# "LIVRO COMPLEMENTAR" — "C" sozinho é um numeral romano válido, mas "CO..."
# não é, e o \b garante que o numeral termina numa fronteira de palavra real).
# "SUBT[IÍ]TULO" tem que vir antes de "T[IÍ]TULO" na alternância (ambos
# poderiam em tese casar, embora o ^ ancorado no início da string já evite
# ambiguidade aqui — mantido nessa ordem por clareza).
RE_HEADING_GENERICO = re.compile(
    r"^(LIVRO|SUBT[IÍ]TULO|T[IÍ]TULO|CAP[IÍ]TULO|SUBSE[CÇ][AÃ]O|SE[CÇ][AÃ]O)\s+([IVXLCDM]+(?:-[A-Z])?|[UÚ]nic[oa])\b", re.I
)
RE_HEADING_COMPLEMENTAR = re.compile(r"^LIVRO\s+COMPLEMENTAR\b", re.I)
CANONICO = {
    "LIVRO": "Livro",
    "SUBTITULO": "Subtítulo", "SUBTÍTULO": "Subtítulo",
    "TITULO": "Título", "TÍTULO": "Título",
    "CAPITULO": "Capítulo", "CAPÍTULO": "Capítulo",
    "SECAO": "Seção", "SEÇAO": "Seção", "SECÃO": "Seção", "SEÇÃO": "Seção",
    "SUBSECAO": "Subseção", "SUBSEÇAO": "Subseção", "SUBSECÃO": "Subseção", "SUBSEÇÃO": "Subseção",
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
        numeral = numeral.capitalize()  # "ÚNICO"/"Única" -> "Único"/"Única"
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
    """"DAS PESSOAS NATURAIS" (caixa alta) -> "Das pessoas naturais"."""
    if not texto:
        return None
    return texto[0].upper() + texto[1:].lower()


class Artigo:
    def __init__(self, numero, contexto, descricao=None, rubrica=None):
        self.numero = numero
        self.caput = ""
        self.revogado = False
        self.contexto = contexto  # (parte, livro, titulo, subtitulo, capitulo, secao, subsecao)
        # Descrição do cabeçalho estrutural mais específico em vigor (ex.:
        # "Da laje") e rubrica/epígrafe do próprio artigo — este Código não
        # usa a convenção de rubrica por artigo, então fica sempre None aqui,
        # mas o campo existe pra manter o mesmo formato de linha do parser
        # do Código Penal.
        self.descricao = descricao
        self.rubrica = rubrica
        self.dispositivos = []


def montar_titulo_estrutural(parte, livro, titulo, subtitulo):
    partes = [p for p in [parte, livro, titulo, subtitulo] if p]
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
        # O gerador (Microsoft FrontPage) grava em Windows-1252, não
        # ISO-8859-1 puro (aspas curvas e travessão em bytes 0x93/0x94/0x96) —
        # mesmo problema encontrado depois no Código Penal; corrigido aqui
        # nesta reexecução também.
        html = f.read().decode("cp1252")

    soup = BeautifulSoup(html, "html.parser")
    for sup in soup.find_all("sup"):
        sup.decompose()

    parte_atual = livro_atual = titulo_atual = subtitulo_atual = capitulo_atual = secao_atual = subsecao_atual = None
    descricao_parte = descricao_livro = descricao_titulo = None
    descricao_subtitulo = descricao_capitulo = descricao_secao = descricao_subsecao = None
    # Cabeçalho centralizado sem descrição colada na mesma linha (ex.:
    # "SUBTÍTULO I" sozinho) pode ter a descrição na PRÓXIMA linha
    # centralizada ("Da Sociedade Não Personificada") — guarda qual nível
    # está esperando essa segunda linha.
    pendente_nivel = None
    artigos: list[Artigo] = []
    artigo_atual = None
    pilha_nivel: dict[int, int] = {}
    nivel_container = 0
    dentro_do_corpo = False

    def descricao_atual():
        return (descricao_subsecao or descricao_secao or descricao_capitulo
                or descricao_subtitulo or descricao_titulo or descricao_livro or descricao_parte)

    for p in soup.find_all("p"):
        texto = limpar_texto(p.get_text(" ", strip=True))
        if not texto:
            continue

        if not dentro_do_corpo:
            if texto.startswith("O PRESIDENTE DA REP"):
                dentro_do_corpo = True
            continue
        if texto.startswith("Brasília,") or texto == "ÍNDICE" or texto.startswith("Este texto"):
            break

        eh_centralizado = (p.get("align") or "").upper() == "CENTER"

        if eh_centralizado:
            if pendente_nivel is not None:
                nivel_pendente, pendente_nivel = pendente_nivel, None
                eh_novo_cabecalho = (
                    RE_HEADING_PARTE.match(texto) or RE_HEADING_COMPLEMENTAR.match(texto) or formatar_heading(texto)
                )
                if not eh_novo_cabecalho:
                    desc = normalizar_descricao(limpar_citacoes(texto))
                    if desc:
                        if nivel_pendente == "parte":
                            descricao_parte = desc
                        elif nivel_pendente == "livro":
                            descricao_livro = desc
                        elif nivel_pendente == "titulo":
                            descricao_titulo = desc
                        elif nivel_pendente == "subtitulo":
                            descricao_subtitulo = desc
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
                livro_atual = titulo_atual = subtitulo_atual = capitulo_atual = secao_atual = subsecao_atual = None
                descricao_parte = descricao_livro = descricao_titulo = None
                descricao_subtitulo = descricao_capitulo = descricao_secao = descricao_subsecao = None
                resto = limpar_citacoes(texto[m_parte.end():].strip())
                if resto:
                    descricao_parte = normalizar_descricao(resto)
                else:
                    pendente_nivel = "parte"
                continue

            if RE_HEADING_COMPLEMENTAR.match(texto):
                livro_atual = "Livro Complementar"
                titulo_atual = subtitulo_atual = capitulo_atual = secao_atual = subsecao_atual = None
                descricao_livro = descricao_titulo = None
                descricao_subtitulo = descricao_capitulo = descricao_secao = descricao_subsecao = None
                resto = limpar_citacoes(texto[RE_HEADING_COMPLEMENTAR.match(texto).end():].strip())
                if resto:
                    descricao_livro = normalizar_descricao(resto)
                else:
                    pendente_nivel = "livro"
                continue

            heading = formatar_heading(texto)
            if heading:
                m_h = RE_HEADING_GENERICO.match(texto)
                resto = limpar_citacoes(texto[m_h.end():].strip())
                desc = normalizar_descricao(resto) if resto else None
                if heading.startswith("Livro"):
                    livro_atual = heading
                    titulo_atual = subtitulo_atual = capitulo_atual = secao_atual = subsecao_atual = None
                    descricao_titulo = None
                    descricao_subtitulo = descricao_capitulo = descricao_secao = descricao_subsecao = None
                    descricao_livro = desc
                    if desc is None:
                        pendente_nivel = "livro"
                elif heading.startswith("Subtítulo"):
                    subtitulo_atual = heading
                    capitulo_atual = secao_atual = subsecao_atual = None
                    descricao_capitulo = descricao_secao = descricao_subsecao = None
                    descricao_subtitulo = desc
                    if desc is None:
                        pendente_nivel = "subtitulo"
                elif heading.startswith("Título"):
                    titulo_atual = heading
                    subtitulo_atual = capitulo_atual = secao_atual = subsecao_atual = None
                    descricao_subtitulo = descricao_capitulo = descricao_secao = descricao_subsecao = None
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

        m = RE_ARTIGO_INTERVALO.match(texto)
        if m:
            inicio = int(normalizar_numero(m.group(1)))
            fim = int(normalizar_numero(m.group(2)))
            resto = m.group(3).strip()
            for n in range(inicio, fim + 1):
                artigo_atual = Artigo(
                    str(n),
                    (parte_atual, livro_atual, titulo_atual, subtitulo_atual, capitulo_atual, secao_atual, subsecao_atual),
                    descricao=descricao_atual(),
                )
                artigo_atual.caput = resto
                if RE_REVOGADO_INICIO.match(resto):
                    artigo_atual.revogado = True
                artigos.append(artigo_atual)
            pilha_nivel = {}
            nivel_container = 0
            continue

        m = RE_ARTIGO.match(texto)
        if m:
            numero = normalizar_numero(m.group(1))
            resto = m.group(2).strip()
            artigo_atual = Artigo(
                numero,
                (parte_atual, livro_atual, titulo_atual, subtitulo_atual, capitulo_atual, secao_atual, subsecao_atual),
                descricao=descricao_atual(),
            )
            artigo_atual.caput = resto
            if RE_REVOGADO_INICIO.match(resto):
                artigo_atual.revogado = True
            artigos.append(artigo_atual)
            pilha_nivel = {}
            nivel_container = 0
            continue

        if artigo_atual is None:
            continue

        m = RE_PARAGRAFO_UNICO.match(texto)
        if m:
            adicionar_dispositivo(artigo_atual, pilha_nivel, "paragrafo", "Parágrafo único", m.group(1).strip(), nivel=1)
            nivel_container = 1
            continue

        m = RE_PARAGRAFO.match(texto)
        if m:
            # Convenção legislativa: só de 1 a 9 leva o "º" (§ 1º...§ 9º); de
            # 10 em diante é só o número (§ 10, § 11...), como no original.
            numero_paragrafo = int(m.group(1))
            rotulo = f"§ {numero_paragrafo}º" if numero_paragrafo < 10 else f"§ {numero_paragrafo}"
            adicionar_dispositivo(artigo_atual, pilha_nivel, "paragrafo", rotulo, m.group(2).strip(), nivel=1)
            nivel_container = 1
            continue

        m = RE_INCISO.match(texto)
        if m:
            nivel = 2 if (1 in pilha_nivel and artigo_atual.dispositivos[pilha_nivel[1]]["tipo"] == "paragrafo") else 1
            adicionar_dispositivo(artigo_atual, pilha_nivel, "inciso", m.group(1), m.group(2).strip(), nivel=nivel)
            nivel_container = nivel
            continue

        m = RE_ALINEA.match(texto)
        if m:
            # nivel_container (não "max(pilha_nivel)"): esse último passaria a
            # incluir a própria alínea anterior depois que ela é inserida, o
            # que faria cada alínea de uma lista (a, b, c, d...) virar filha
            # da anterior em vez de irmã (bug encontrado e corrigido no
            # parser do Código Penal, replicado aqui na mesma reexecução).
            adicionar_dispositivo(artigo_atual, pilha_nivel, "alinea", f"{m.group(1)})", m.group(2).strip(), nivel=nivel_container + 1)
            continue

        if pilha_nivel:
            ultimo_nivel = max(pilha_nivel.keys())
            disp = artigo_atual.dispositivos[pilha_nivel[ultimo_nivel]]
            disp["texto"] = (disp["texto"] + " " + texto).strip()
        else:
            artigo_atual.caput = (artigo_atual.caput + " " + texto).strip()

    emitir_sql(artigos)


def sql_str(v):
    if v is None:
        return "NULL"
    v = str(v).replace("\\", "\\\\").replace("'", "\\'")
    return f"'{v}'"


def emitir_sql(artigos: list):
    out = sys.stdout
    out.write("-- Código Brasil — seed: Código Civil (Lei nº 10.406/2002)\n")
    out.write("-- Gerado a partir de https://www.planalto.gov.br/ccivil_03/leis/2002/l10406compilada.htm\n")
    out.write("-- Idempotente: apaga e recria os dados desta lei (categoria_id/lei_id fixos) a cada execução.\n\n")

    # FOREIGN_KEY_CHECKS=0 ao redor do DELETE: artigo_dispositivos tem uma FK
    # de auto-relacionamento (parent_id), e um artigo com alíneas encadeadas
    # (parágrafo > inciso > alínea) faz o MySQL recusar o DELETE em lote —
    # mesmo problema encontrado depois no Código Penal, corrigido aqui também.
    out.write("SET FOREIGN_KEY_CHECKS=0;\n")
    out.write(f"DELETE FROM artigo_dispositivos WHERE artigo_id IN (SELECT id FROM artigos WHERE lei_id = {LEI_ID});\n")
    out.write(f"DELETE FROM artigos WHERE lei_id = {LEI_ID};\n")
    out.write(f"DELETE FROM leis WHERE id = {LEI_ID};\n")
    out.write("SET FOREIGN_KEY_CHECKS=1;\n\n")

    # A categoria `codigos` é compartilhada com o Código Penal e o CPC, então
    # não é apagada aqui (o DELETE falhava com #1451 num banco onde essas leis
    # já apontam pra ela, e o SET FOREIGN_KEY_CHECKS=0 acima não vale em todo
    # import, ex. phpMyAdmin) — só garantida, como nos outros dois seeds.
    out.write(f"INSERT IGNORE INTO categorias (id, slug, nome) VALUES ({CATEGORIA_ID}, 'codigos', 'Códigos');\n\n")

    out.write("INSERT INTO leis (id, categoria_id, slug, titulo, descricao, fonte_url) VALUES\n")
    out.write(
        f"({LEI_ID}, {CATEGORIA_ID}, 'codigo-civil-2002', "
        f"'Código Civil (Lei nº 10.406, de 2002)', "
        f"'Institui o Código Civil, atualizado até a última alteração compilada pelo Planalto.', "
        f"'https://www.planalto.gov.br/ccivil_03/leis/2002/l10406compilada.htm');\n\n"
    )

    artigo_rows = []
    disp_rows = []
    artigo_id = ARTIGO_ID_INICIAL
    disp_id = DISPOSITIVO_ID_INICIAL
    ordem_artigo = 1

    for artigo in artigos:
        parte, livro, titulo, subtitulo, capitulo, secao, subsecao = artigo.contexto
        titulo_estrutural = montar_titulo_estrutural(parte, livro, titulo, subtitulo)

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
