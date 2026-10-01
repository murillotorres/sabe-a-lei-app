#!/usr/bin/env python3
"""Motor compartilhado para converter o HTML de uma lei do Planalto em INSERTs
SQL, no mesmo formato das demais leis (ver api/database/CONTEUDO.md).

Cada lei tem um script fino (`parse_cpp.py`, `parse_ctn.py`,
`parse_codigo_eleitoral.py`, `parse_cdc.py`, `parse_ctb.py`, `parse_cppm.py`,
`parse_cpm.py`) que só declara a configuração (`Lei`) e chama
`executar()`. Os parsers antigos (Constituição, Código Civil, Código Penal,
CPC) continuam independentes.

Decisões herdadas do parser do Código Penal (ver CONTEUDO.md):
- sem BeautifulSoup: o HTML do Planalto (FrontPage) tem tags não fechadas
  cruzando limites de <p>, e a árvore perde parágrafos; o corte é feito no
  texto bruto, pelas aberturas de <p>;
- charset Windows-1252 (não ISO-8859-1);
- a hierarquia Parte/Livro/Título fica concatenada em `titulo_estrutural`;
  Capítulo/Seção/Subseção têm coluna própria.

O que este motor acrescenta:
- descarta texto riscado (`<strike>` e `text-decoration: line-through`), que no
  Planalto marca a redação antiga já substituída;
- reconhece o sufixo de letra depois do ordinal ("Art. 3º-A");
- descrição de cabeçalho em várias linhas, ignorando notas entre parênteses
  ("(Redação dada pela Lei nº X)") que o Planalto põe no meio dela;
- numerais por extenso nos cabeçalhos ("LIVRO PRIMEIRO", "PARTE SEGUNDA");
- `--depurar` lista as linhas que não casaram com nenhum padrão, pra conferir
  se o parser não está engolindo texto de lei.
"""
import html as htmllib
import re
import sys
import unicodedata
from dataclasses import dataclass


@dataclass
class Lei:
    entrada: str
    lei_id: int
    slug: str
    titulo: str
    descricao: str
    fonte_url: str
    artigo_id_inicial: int
    dispositivo_id_inicial: int
    # Fórmula de abertura do texto (antes dela vêm o cabeçalho do site, a
    # ementa e links) e do encerramento (data e assinaturas).
    inicio: str = "O PRESIDENTE DA REP"
    categoria_id: int = 2  # "codigos"
    # Cabeçalhos centralizados sem numeral (ex. "DISPOSIÇÕES FINAIS E
    # TRANSITÓRIAS"): regex do texto inteiro. Encerram a hierarquia em vigor e
    # viram o próprio rótulo estrutural dos artigos seguintes.
    cabecalhos_sem_numeral: tuple = ()
    # A lei tem epígrafe acima de cada artigo ("Homicídio simples")? Se sim, a
    # linha solta logo antes de um "Art." vira a `rubrica` dele (como no Código
    # Penal); senão essas linhas são descartadas.
    rubricas: bool = False


# "At. 248" e "Ar. 337" (sem uma das letras) são erros do próprio Planalto no
# Código Eleitoral. O sufixo de letra ("3º-A", "121-A", "359-M-A") vem colado ao número ou ao
# ordinal — nunca com espaço: "Art. 120 - A sentença..." é um separador seguido
# de frase que começa com "A", e não o artigo 120-A. A exceção é "Art. 7º -A."
# (CTB): espaço entre o ordinal e o hífen, mas hífen colado na letra.
RE_ARTIGO = re.compile(
    r"^A\s?(?:rt|r|t)\.?\s*(\d+(?:\.\d+)?(?:\s\d(?=\.\s))?)\s?(?:[ºo°](?:\s(?=-[A-Z]))?)?(-[A-Z](?:-[A-Z])?)?(?![A-Za-zÀ-ú])[\s.\-–]*(.*)$", re.S
)
# Vários artigos revogados num único parágrafo ("Art. 1.620. a 1.629. ..." ou
# "Art. 187. (Revogado...) Art. 188. (Revogado...)").
RE_MULTI_REVOGADO = re.compile(r"Art\.?\s*(\d+)\.\s*(\(Revogad[^)]*\))")
# "Arts. 52 a 58. (Revogados pelo Decreto-lei nº 406, de 1968" (o Planalto às
# vezes esquece o parêntese final) e "§§ 4º e 5º (Revogados pela ...)".
RE_ARTIGOS_REVOGADOS = re.compile(r"^Arts\.?\s*(\d+)\s*(a|e)\s*(\d+)\.?\s*(\(Revogad.*)$", re.S | re.I)
RE_PARAGRAFOS_REVOGADOS = re.compile(r"^§§\s*(\d+)\s*[ºo°]?\s*(a|e)\s*(\d+)\s*[ºo°]?\s*(\(Revogad.*)$", re.S | re.I)
RE_PARAGRAFO_UNICO = re.compile(r"^Par[aá]grafo\s+[uú]nico\.?\s*[-–]?\s*(.*)$", re.S | re.I)
# "§. 2º" (ponto espúrio) aparece no Código Eleitoral.
# O sufixo vem colado com hífen ("§ 6º-A"); a única exceção é "§ 6º B (VETADO)"
# (sem hífen) no Art. 135 do Código Eleitoral, aceita só antes de "(VETADO)"/"(Revogado".
RE_PARAGRAFO = re.compile(
    r"^§\.?\s*(\d+)\s*(?:[ºo°])?\s*(?:-([A-Z](?:-[A-Z])?)\b|([A-Z])(?=\s+\((?:VETADO|Revogad)))?\.?\s*[-–]?\s*(.*)$", re.S
)
# Traço opcional: "III perda..." (sem traço) é um typo real do texto oficial.
RE_INCISO = re.compile(r"^([IVXLCDM][IVXLCDMl]*)(?:\s*[-–]\s*|\s+)(.*)$", re.S)
RE_ALINEA = re.compile(r"^([a-z])\)\s*(.*)$", re.S)
# Item de alínea: "1 - bicicleta;" ou "1. 110 km/h ..." (CTB, Arts. 61 e 96). Só
# vale com uma alínea aberta — número solto no começo de linha é texto comum.
RE_ITEM = re.compile(r"^(\d{1,2})\s*[.\-–]\s+(.*)$", re.S)

NUMERAL = (
    r"[IVXLCDM]+(?:-[A-Z])?|PRIMEIR[OA]|SEGUND[OA]|TERCEIR[OA]|QUART[OA]|QUINT[OA]|SEXT[OA]|"
    r"S[EÉ]TIM[OA]|OITAV[OA]|NON[OA]|D[EÉ]CIM[OA]|[UÚ]NIC[OA]|GERAL|ESPECIAL"
)
# "SeçãoI" (sem espaço) é um typo do CPP.
RE_HEADING = re.compile(
    rf"^(PARTE|LIVRO|T\s?[IÍ]TULO|CAP[IÍ]TULO|SUBSE[CÇ][AÃ]O|SE[CÇ][AÃ]O)\s*({NUMERAL})(?![A-Za-zÀ-ú])\s*(.*)$", re.I
)
NIVEIS = ["parte", "livro", "titulo", "capitulo", "secao", "subsecao"]
ROTULO = {
    "PARTE": ("parte", "Parte"), "LIVRO": ("livro", "Livro"),
    "TITULO": ("titulo", "Título"), "TÍTULO": ("titulo", "Título"),
    "CAPITULO": ("capitulo", "Capítulo"), "CAPÍTULO": ("capitulo", "Capítulo"),
    "SECAO": ("secao", "Seção"), "SEÇAO": ("secao", "Seção"), "SECÃO": ("secao", "Seção"), "SEÇÃO": ("secao", "Seção"),
    "SUBSECAO": ("subsecao", "Subseção"), "SUBSEÇAO": ("subsecao", "Subseção"),
    "SUBSECÃO": ("subsecao", "Subseção"), "SUBSEÇÃO": ("subsecao", "Subseção"),
}

# "(Revogado...)" e "(VETADO)" recebem o mesmo selo no app — um dispositivo
# vetado também nunca teve força de lei.
RE_REVOGADO_INICIO = re.compile(r"^\(?(revogad[ao]s?|vetado)\b", re.I)
# Linhas soltas que são só links/etiquetas do site, nunca texto de lei.
RUIDO = {"vigência", "produção de efeitos", "texto compilado", "vide", "*"}


# Notas de emenda no fim de uma linha, com os links "Vigência"/"Produção de efeitos".
# O parêntese final é opcional: "(Incluído dad" (Art. 162 do CTB) vem cortado na fonte.
RE_NOTAS_FINAIS = re.compile(
    r"(?:\s*(?:\((?:Reda|Inclu|Revog|Vig|Vide|Produ|Acrescid|Renumerad)[^()]*\)?|Vig[eê]ncia|Produ[cç][aã]o de efeitos))+\s*$",
    re.I,
)


def limpar_texto(txt: str) -> str:
    txt = unicodedata.normalize("NFC", txt)
    txt = txt.replace("\xa0", " ")
    txt = txt.replace("Leinº", "Lei nº")  # erro do próprio Planalto nas notas de emenda
    txt = re.sub(r"\s+", " ", txt).strip()
    txt = re.sub(r"\s+([;:,\.\)])", r"\1", txt)
    txt = re.sub(r"\(\s+", "(", txt)
    return txt.strip()


def limpar_citacoes(texto: str) -> str:
    """Remove parênteses finais em cadeia, tipo "(Incluído pela Lei nº X)
    (Vigência)" — sobra só o texto descritivo, se houver."""
    anterior = None
    while anterior != texto:
        anterior = texto
        texto = re.sub(r"\s*\([^()]*\)\.?\s*$", "", texto).strip()
        texto = re.sub(r"\s+(Vig[eê]ncia|Produ[cç][aã]o de efeitos)\s*$", "", texto, flags=re.I).strip()
    return texto


def normalizar_descricao(texto):
    """"DO CRIME" (caixa alta) -> "Do crime": só a primeira letra maiúscula."""
    if not texto:
        return None
    texto = texto.strip(' "“”')
    return texto[0].upper() + texto[1:].lower() if texto else None


def corrigir_rotulo(texto: str) -> str:
    """Rótulos de parágrafo malformados na fonte (Código de Processo Penal
    Militar e Código Penal Militar): "§ § 1°", "6§º", e "4º Se o furto…" sem o §."""
    texto = re.sub(r"^§\s+§\s*", "§ ", texto)  # "§§ 4º e 5º" (sem espaço) é o plural, legítimo
    texto = re.sub(r"^(\d{1,2})\s*§\s*([ºo°])", r"§ \1\2", texto)
    return re.sub(r"^(\d{1,2})\s?[º°]\s+(?=[A-ZÀ-Ú])", r"§ \1º ", texto)


def eh_nota(texto: str) -> bool:
    """Linha só de citação entre parênteses — "(Incluído pela Lei nº X)"."""
    return texto.startswith("(") and not limpar_citacoes(texto)


# Início de um dispositivo (rótulo) dentro de um trecho riscado.
RE_ABERTURA = re.compile(r"<(?:p|h[1-6])\b[^>]*>", re.I)
RE_ROTULO_RISCADO = re.compile(
    r"^(A\s?rt\.?\s*\d+(?:\.\d+)?\s?[ºo°]?(?:-[A-Z](?:-[A-Z])?)?\.?"
    r"|§\.?\s*\d+\s?[ºo°]?(?:-[A-Z](?:-[A-Z])?)?"
    r"|Par[aá]grafo\s+[uú]nico\.?"
    r"|[IVXLCDM]+\s*[-–]"
    r"|[a-z]\))"
)
MARCA = "\ue000"


def html_para_texto(fragmento: str) -> str:
    # O ordinal vem como "<sup>o</sup>" ("art. 122, n<sup>o</sup> 17"); trocar a
    # tag por espaço, como o resto, deixaria "n o 17".
    fragmento = re.sub(r"<sup\b[^>]*>(?:\s|<[^>]+>)*o(?:\s|<[^>]+>)*</sup>", "º", fragmento, flags=re.I)
    return htmllib.unescape(re.sub(r"<[^>]+>", " ", fragmento))


def remover_riscados(html: str) -> str:
    """Tira o texto riscado (redação superada), mas:
    - mantém as aberturas de <p> que estavam dentro do trecho — um <strike> que
      cruza a fronteira de um parágrafo não pode fundir o texto vizinho;
    - guarda o rótulo (ex. "Art. 194.") de um trecho riscado dentro de um único
      parágrafo: no Planalto o rótulo de um dispositivo revogado fica DENTRO do
      <strike> e só a nota "(Revogado pela Lei nº X)" sobra fora. Sem o rótulo,
      o artigo simplesmente sumiria da numeração."""
    def substituir(m):
        trecho = m.group(0)
        aberturas = re.findall(RE_ABERTURA, trecho)
        if aberturas:
            return "".join(aberturas)
        texto = limpar_texto(html_para_texto(trecho))
        rotulo = RE_ROTULO_RISCADO.match(texto)
        return f"{MARCA}{rotulo.group(1)}{MARCA}" if rotulo else ""

    # O rótulo às vezes vem partido em vários <strike> seguidos ("<strike>Art.</strike>
    # <strike>64. A pena…</strike>", e até "A<strike>rt.</strike>" no Código Penal
    # Militar): junta os trechos vizinhos do mesmo parágrafo antes de procurar o rótulo.
    html = re.sub(r"\bA(<strike\b[^>]*>)rt\b", r"\1Art", html, flags=re.I)
    html = re.sub(r"</strike>(?:\s|&nbsp;|<(?!/?(?:p|h[1-6])\b|/?strike\b)[^>]+>)*<strike\b[^>]*>", " ", html, flags=re.I)
    html = re.sub(r"<strike\b[^>]*>.*?</strike>", substituir, html, flags=re.S | re.I)
    # Riscado só por CSS, sem a tag (também usado pelo Planalto).
    html = re.sub(r"<span\b[^>]*line-through[^>]*>.*?</span>", substituir, html, flags=re.S | re.I)
    return html


def resolver_marcas(texto: str) -> str:
    """Se o que sobrou do parágrafo é só "(Revogado ...)" ou "(Suspensa a
    execução ...)", devolve o rótulo do trecho riscado junto; senão descarta as
    marcas."""
    marcas = re.findall(f"{MARCA}(.*?){MARCA}", texto)
    # O ponto final do texto riscado às vezes fica fora do <strike> (". (Revogado…)").
    restante = limpar_texto(re.sub(f"{MARCA}.*?{MARCA}", " ", texto)).lstrip(". ")
    if marcas and re.match(r"^\(?(revogad[ao]s?|suspens[ao])\b", restante, re.I):
        return limpar_texto(f"{marcas[0]} {restante}")
    return restante


def converter_tabelas(html: str) -> str:
    """Cada linha de tabela vira um <p data-tabela>, com as células separadas por
    " — " (os pontilhados de preenchimento saem). O CTN tem duas tabelas de
    coeficientes (Arts. 90 e 91); tratadas como texto, não como artigos."""
    def tabela(m):
        linhas = []
        for tr in re.findall(r"<tr\b.*?</tr>", m.group(0), flags=re.S | re.I):
            celulas = [
                re.sub(r"\.{4,}", "", limpar_texto(html_para_texto(td))).strip()
                for td in re.findall(r"<t[dh]\b.*?</t[dh]>", tr, flags=re.S | re.I)
            ]
            texto = " — ".join(c for c in celulas if c)
            if texto:
                linhas.append(f'<p data-tabela="1">{htmllib.escape(texto)}</p>')
        return "".join(linhas)

    return re.sub(r"<table\b.*?</table>", tabela, html, flags=re.S | re.I)


def eh_negrito(conteudo: str) -> bool:
    """O parágrafo é todo em <b> (fora as notas de emenda)? É como o Planalto
    marca as rubricas dos códigos militares."""
    negrito = limpar_texto(html_para_texto(" ".join(re.findall(r"<b\b[^>]*>(.*?)</b>", conteudo, flags=re.S | re.I))))
    fora = limpar_texto(html_para_texto(re.sub(r"<b\b[^>]*>.*?</b>", " ", conteudo, flags=re.S | re.I)))
    return bool(negrito) and not re.sub(RE_NOTAS_FINAIS, "", fora)


def extrair_paragrafos(html: str):
    """(centralizado, texto, linha de tabela, negrito) de cada parágrafo. Os
    cabeçalhos do Código Penal Militar vêm em <h1>/<h2>, não em <p>."""
    partes = re.split(r"<(?:p|h[1-6])\b([^>]*)>", html, flags=re.I)
    resultado = []
    for i in range(1, len(partes), 2):
        attrs = partes[i]
        conteudo = partes[i + 1] if i + 1 < len(partes) else ""
        texto = resolver_marcas(html_para_texto(conteudo))
        centralizado = bool(
            re.search(r'align\s*=\s*"?center', attrs, re.I) or re.search(r"text-align\s*:\s*center", attrs, re.I)
        )
        resultado.append((centralizado, texto, "data-tabela" in attrs, eh_negrito(conteudo)))
    return resultado


class Artigo:
    def __init__(self, numero, contexto, descricao):
        self.numero = numero
        self.caput = ""
        self.revogado = False
        self.contexto = contexto  # rótulos por nível, na ordem de NIVEIS
        self.descricao = descricao
        self.rubrica = None
        self.dispositivos = []


def adicionar_dispositivo(artigo, pilha_nivel, tipo, rotulo, texto, nivel):
    parent_idx = pilha_nivel.get(nivel - 1) if nivel > 1 else None
    artigo.dispositivos.append({
        "tipo": tipo, "rotulo": rotulo, "texto": texto, "nivel": nivel,
        "parent_idx": parent_idx, "revogado": bool(RE_REVOGADO_INICIO.match(texto)),
    })
    pilha_nivel[nivel] = len(artigo.dispositivos) - 1
    for n in list(pilha_nivel.keys()):
        if n > nivel:
            del pilha_nivel[n]


def interpretar(lei: Lei, depurar: bool):
    with open(lei.entrada, "rb") as f:
        html = f.read().decode("cp1252")
    paragrafos = extrair_paragrafos(converter_tabelas(remover_riscados(html)))

    inicio = next(i for i, (_, t, _, _) in enumerate(paragrafos) if t.startswith(lei.inicio))
    fim = next(
        (i for i in range(inicio + 1, len(paragrafos))
         if re.match(r"^((Bras[ií]lia|Rio de Janeiro),\s+(em\s+)?\d|Este texto n[aã]o substitui)", paragrafos[i][1])),
        len(paragrafos),
    )

    rotulos = {n: None for n in NIVEIS}
    descricoes = {n: None for n in NIVEIS}
    # Nível cujo cabeçalho ainda está juntando a descrição (que pode ocupar mais
    # de uma linha centralizada). Fecha no primeiro parágrafo que não é
    # centralizado.
    aguardando = None
    ultimo_cabecalho = None  # nível do último cabeçalho, enquanto só vierem linhas centralizadas
    artigos: list[Artigo] = []
    artigo_atual = None
    pilha_nivel: dict[int, int] = {}
    # Nível do último parágrafo/inciso aberto: as alíneas penduram nele, não no
    # "max(pilha_nivel)" (que inclui a alínea anterior e faria uma escada).
    nivel_container = 0
    nivel_alinea = None  # nível da última alínea aberta (pai dos itens)
    nao_reconhecidas: list[str] = []
    linha_solta = False  # a linha anterior era linha de tabela (ver abaixo)
    sem_numeral_ativo = False  # o rótulo de "parte" é um cabeçalho sem numeral
    # Linha solta candidata a rubrica do próximo artigo (só com `lei.rubricas`).
    # Vale apenas se a linha seguinte abrir um artigo novo.
    rubrica_pendente = None
    em_citacao = False  # entre aspas abertas e não fechadas (ver abaixo)

    def contexto():
        return tuple(rotulos[n] for n in NIVEIS)

    def anexar_texto(texto, sep=" "):
        """Continua o texto do último dispositivo aberto (ou do caput)."""
        if artigo_atual.dispositivos:
            alvo = artigo_atual.dispositivos[-1]
            alvo["texto"] = f"{alvo['texto']}{sep}{texto}".strip()
        else:
            artigo_atual.caput = f"{artigo_atual.caput}{sep}{texto}".strip()

    def descricao_atual():
        for n in reversed(NIVEIS):
            if descricoes[n]:
                return descricoes[n]
        return None

    for i in range(inicio + 1, fim):
        centralizado, texto, tabela, negrito = paragrafos[i]
        if not texto or texto.lower() in RUIDO:
            continue
        if eh_nota(texto) and rubrica_pendente is not None:
            continue  # "(Redação dada pela Lei nº X)" logo depois da rubrica
        rubrica, rubrica_pendente = rubrica_pendente, None

        # Dentro de uma citação de outra lei (o Art. 113 do CDC acrescenta §§ à Lei
        # nº 7.347 citando o texto entre aspas): tudo é texto do dispositivo aberto
        # até fechar as aspas — os "§ 5º" citados não são parágrafos desta lei.
        if em_citacao and not centralizado:
            if RE_ARTIGO.match(texto):
                em_citacao = False  # aspas que o Planalto esqueceu de fechar
            else:
                anexar_texto(texto)
                em_citacao = not re.search(r"[\"”]", texto)
                continue

        anterior_era_linha_solta, linha_solta = linha_solta, False
        if tabela:
            if artigo_atual is not None:
                anexar_texto(texto, "; " if anterior_era_linha_solta else " ")
            linha_solta = True
            continue

        texto = corrigir_rotulo(texto)
        # "Art. 139-A" do CTB e o "§ 2º" do Art. 33 do CPPM vêm num <p> centralizado por engano.
        if centralizado and not RE_HEADING.match(texto) and (
            RE_ARTIGO.match(texto) or RE_PARAGRAFO.match(texto) or RE_PARAGRAFO_UNICO.match(texto)
        ):
            centralizado = False
        if centralizado:
            m = RE_HEADING.match(texto)
            if m:
                nivel, rotulo = ROTULO[m.group(1).upper().replace(" ", "")]
                if sem_numeral_ativo:
                    rotulos["parte"] = None
                    sem_numeral_ativo = False
                numeral = m.group(2)
                eh_romano = bool(re.match(r"^[IVXLCDM]+(-[A-Z])?$", numeral, re.I))
                rotulos[nivel] = f"{rotulo} {numeral.upper() if eh_romano else numeral.capitalize()}"
                # Um cabeçalho novo encerra tudo o que estava abaixo dele.
                for n in NIVEIS[NIVEIS.index(nivel) + 1:]:
                    rotulos[n] = descricoes[n] = None
                # "Seção I - Dos crimes…" (Código Penal Militar): traço entre rótulo e descrição.
                resto = limpar_citacoes(m.group(3).strip().lstrip("-– "))
                descricoes[nivel] = normalizar_descricao(resto) if resto else None
                aguardando = nivel if descricoes[nivel] is None else None
                ultimo_cabecalho = nivel
                continue

            # Descrição que já veio na linha do rótulo e continua na seguinte, em
            # minúscula ("Seção I - Dos crimes contra a liberdade" / "individual").
            if aguardando is None and ultimo_cabecalho and texto[:1].islower():
                descricoes[ultimo_cabecalho] = normalizar_descricao(f"{descricoes[ultimo_cabecalho]} {limpar_citacoes(texto)}")
                continue

            if aguardando is not None:
                if eh_nota(texto):
                    continue
                desc = limpar_citacoes(texto)
                if desc:
                    atual = descricoes[aguardando]
                    descricoes[aguardando] = normalizar_descricao(f"{atual} {desc}" if atual else desc)
                continue

            if any(re.match(padrao, texto, re.I) for padrao in lei.cabecalhos_sem_numeral):
                for n in NIVEIS:
                    rotulos[n] = descricoes[n] = None
                rotulos["parte"] = normalizar_descricao(limpar_citacoes(texto))
                sem_numeral_ativo = True
                aguardando = None
                ultimo_cabecalho = None
                continue
            # Centralizado que não é cabeçalho nem descrição: dentro de um artigo
            # são as linhas de uma tabela feita à mão com parágrafos centralizados
            # (quadro de coeficientes do Art. 91 do CTN) — vira texto do dispositivo
            # aberto, com os pontilhados de preenchimento trocados por travessão.
            if artigo_atual is not None and not eh_nota(texto):
                anexar_texto(re.sub(r"\s*\.{4,}\s*", " — ", texto), "; " if anterior_era_linha_solta else " ")
                linha_solta = True
                if depurar:
                    nao_reconhecidas.append(f"[Art. {artigo_atual.numero}] (centralizada anexada) {texto[:90]}")
            continue

        if aguardando is not None:
            if eh_nota(texto):
                continue
            if texto.isupper() and not RE_ARTIGO.match(texto):
                desc = limpar_citacoes(texto)
                atual = descricoes[aguardando]
                descricoes[aguardando] = normalizar_descricao(f"{atual} {desc}" if atual else desc)
                continue
        aguardando = None
        ultimo_cabecalho = None

        blocos = RE_MULTI_REVOGADO.findall(texto)
        if len(blocos) >= 2:
            for numero, revtxt in blocos:
                artigo_atual = Artigo(numero, contexto(), descricao_atual())
                artigo_atual.caput = revtxt
                artigo_atual.revogado = True
                artigos.append(artigo_atual)
            pilha_nivel = {}
            nivel_container = 0
            continue

        m = RE_ARTIGOS_REVOGADOS.match(texto)
        if m:
            inicial, final, nota = int(m.group(1)), int(m.group(3)), m.group(4).strip().rstrip(".")
            numeros = range(inicial, final + 1) if m.group(2).lower() == "a" else (inicial, final)
            for numero in numeros:
                artigo_atual = Artigo(str(numero), contexto(), descricao_atual())
                artigo_atual.caput = nota if nota.endswith(")") else nota + ")"
                artigo_atual.revogado = True
                artigos.append(artigo_atual)
            pilha_nivel = {}
            nivel_container = 0
            continue

        m = RE_ARTIGO.match(texto)
        if m:
            numero = re.sub(r"[.\s]", "", m.group(1)) + (m.group(2) or "")
            resto = m.group(3).strip()
            artigo_atual = Artigo(numero, contexto(), descricao_atual())
            artigo_atual.rubrica = rubrica
            artigo_atual.caput = resto
            artigo_atual.revogado = bool(RE_REVOGADO_INICIO.match(resto))
            artigos.append(artigo_atual)
            pilha_nivel = {}
            nivel_container = 0
            continue

        if artigo_atual is None:
            # Nota antes do primeiro artigo — ou a rubrica do Art. 1º.
            if lei.rubricas and not eh_nota(texto):
                rubrica_pendente = limpar_citacoes(texto) or None
            continue

        m = RE_PARAGRAFOS_REVOGADOS.match(texto)
        if m:
            inicial, final, nota = int(m.group(1)), int(m.group(3)), m.group(4).strip().rstrip(".")
            numeros = range(inicial, final + 1) if m.group(2).lower() == "a" else (inicial, final)
            for numero in numeros:
                rotulo = f"§ {numero}º" if numero < 10 else f"§ {numero}"
                adicionar_dispositivo(artigo_atual, pilha_nivel, "paragrafo", rotulo, nota if nota.endswith(")") else nota + ")", 1)
            nivel_container = 1
            continue

        m = RE_PARAGRAFO_UNICO.match(texto)
        if m:
            adicionar_dispositivo(artigo_atual, pilha_nivel, "paragrafo", "Parágrafo único", m.group(1).strip(), 1)
            nivel_container = 1
            continue

        m = RE_PARAGRAFO.match(texto)
        if m:
            numero_paragrafo = int(m.group(1))
            letra = m.group(2) or m.group(3)
            sufixo = f"-{letra}" if letra else ""
            rotulo = f"§ {numero_paragrafo}º{sufixo}" if numero_paragrafo < 10 else f"§ {numero_paragrafo}{sufixo}"
            adicionar_dispositivo(artigo_atual, pilha_nivel, "paragrafo", rotulo, m.group(4).strip(), 1)
            nivel_container = 1
            continue

        m = RE_INCISO.match(texto)
        if m:
            nivel = 2 if (1 in pilha_nivel and artigo_atual.dispositivos[pilha_nivel[1]]["tipo"] == "paragrafo") else 1
            adicionar_dispositivo(artigo_atual, pilha_nivel, "inciso", m.group(1).replace("l", "I"), m.group(2).strip(), nivel)
            nivel_container = nivel
            continue

        m = RE_ALINEA.match(texto)
        if m:
            adicionar_dispositivo(artigo_atual, pilha_nivel, "alinea", f"{m.group(1)})", m.group(2).strip(), nivel_container + 1)
            nivel_alinea = nivel_container + 1
            continue

        m = RE_ITEM.match(texto)
        if m and nivel_alinea in pilha_nivel and artigo_atual.dispositivos[pilha_nivel[nivel_alinea]]["tipo"] == "alinea":
            adicionar_dispositivo(artigo_atual, pilha_nivel, "item", m.group(1), m.group(2).strip(), nivel_alinea + 1)
            continue

        # Não bate com nenhum padrão. Ou é texto de lei que o Planalto quebrou em
        # outro <p> (começa em minúscula, ou é uma frase completa — ex. a fórmula
        # do compromisso do jurado no Art. 472 do CPP), e então continua o
        # dispositivo aberto; ou é rubrica/nota ("Juiz das Garantias",
        # "(Incluído pela Lei nº X)"), que não é texto de lei e é descartada.
        # A pontuação final é conferida sem as notas ("Infração – gravíssima;
        # (Incluído pela Lei nº X) Produção de efeitos", no CTB).
        sem_notas = re.sub(RE_NOTAS_FINAIS, "", texto)
        if lei.rubricas and negrito and not eh_nota(texto):
            rubrica_pendente = limpar_citacoes(texto).rstrip(". ") or None
            if depurar:
                nao_reconhecidas.append(f"[Art. {artigo_atual.numero}] (rubrica) {texto[:100]}")
            continue
        # Nas leis com rubrica, um ")" final só conta se não for de nota: "Abandono do
        # processo (Redação dada pela Lei nº X)" é rubrica, não texto.
        termina_frase = re.search(r"[.;:?!]$", sem_notas) or (
            re.search(r"[.;:?!)]$", texto) and not (lei.rubricas and sem_notas != texto)
        )
        if not eh_nota(texto) and (texto[0].islower() or termina_frase or texto[0] in "\"“"):
            anexar_texto(texto)
            em_citacao = texto[0] in "\"“" and not re.search(r"[\"”]", texto[1:])
            if depurar:
                nao_reconhecidas.append(f"[Art. {artigo_atual.numero}] (anexada) {texto[:100]}")
        else:
            if lei.rubricas and not eh_nota(texto):
                rubrica_pendente = limpar_citacoes(texto) or None
            if depurar:
                nao_reconhecidas.append(f"[Art. {artigo_atual.numero}] {texto[:110]}")

    if depurar:
        sys.stderr.write(f"--- {len(nao_reconhecidas)} linhas não reconhecidas ---\n")
        for linha in nao_reconhecidas:
            sys.stderr.write(linha + "\n")
    return artigos


def sql_str(v):
    if v is None:
        return "NULL"
    v = str(v).replace("\\", "\\\\").replace("'", "\\'")
    return f"'{v}'"


def emitir_sql(lei: Lei, artigos: list):
    out = sys.stdout
    out.write(f"-- Código Brasil — seed: {lei.titulo}\n")
    out.write(f"-- Gerado a partir de {lei.fonte_url}\n")
    out.write("-- Idempotente: apaga e recria os dados desta lei (categoria_id/lei_id fixos) a cada execução.\n\n")

    # FOREIGN_KEY_CHECKS=0 ao redor do DELETE: artigo_dispositivos tem FK de
    # auto-relacionamento (parent_id) e o MySQL pode tentar apagar o pai antes
    # da filha num DELETE em lote.
    out.write("SET FOREIGN_KEY_CHECKS=0;\n")
    out.write(f"DELETE FROM artigo_dispositivos WHERE artigo_id IN (SELECT id FROM artigos WHERE lei_id = {lei.lei_id});\n")
    out.write(f"DELETE FROM artigos WHERE lei_id = {lei.lei_id};\n")
    out.write(f"DELETE FROM leis WHERE id = {lei.lei_id};\n")
    out.write("SET FOREIGN_KEY_CHECKS=1;\n\n")

    out.write(f"INSERT IGNORE INTO categorias (id, slug, nome) VALUES ({lei.categoria_id}, 'codigos', 'Códigos');\n\n")
    out.write("INSERT INTO leis (id, categoria_id, slug, titulo, descricao, fonte_url) VALUES\n")
    out.write(
        f"({lei.lei_id}, {lei.categoria_id}, {sql_str(lei.slug)}, {sql_str(lei.titulo)}, "
        f"{sql_str(lei.descricao)}, {sql_str(lei.fonte_url)});\n\n"
    )

    artigo_rows, disp_rows = [], []
    artigo_id, disp_id = lei.artigo_id_inicial, lei.dispositivo_id_inicial

    for ordem_artigo, artigo in enumerate(artigos, start=1):
        parte, livro, titulo, capitulo, secao, subsecao = artigo.contexto
        titulo_estrutural = " · ".join(p for p in (parte, livro, titulo) if p) or None
        artigo_rows.append(
            "(" + ", ".join([
                str(artigo_id), str(lei.lei_id), sql_str("permanente"), sql_str(artigo.numero),
                sql_str(titulo_estrutural), sql_str(capitulo), sql_str(secao), sql_str(subsecao),
                sql_str(artigo.descricao), sql_str(artigo.rubrica),
                sql_str(artigo.caput), "1" if artigo.revogado else "0", str(ordem_artigo),
            ]) + ")"
        )
        idx_para_id = {}
        for ordem_disp, (idx, d) in enumerate(enumerate(artigo.dispositivos), start=1):
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
        artigo_id += 1

    out.write(
        "INSERT INTO artigos (id, lei_id, parte, numero, titulo_estrutural, capitulo_estrutural, "
        "secao_estrutural, subsecao_estrutural, descricao_estrutural, rubrica, caput, revogado, ordem) VALUES\n"
    )
    out.write(",\n".join(artigo_rows) + ";\n\n")
    if disp_rows:
        out.write("INSERT INTO artigo_dispositivos (id, artigo_id, parent_id, tipo, rotulo, texto, nivel, revogado, ordem) VALUES\n")
        out.write(",\n".join(disp_rows) + ";\n")

    sys.stderr.write(
        f"Artigos: {len(artigo_rows)}\nDispositivos: {len(disp_rows)}\n"
        f"Próximo artigo_id livre: {artigo_id}\nPróximo dispositivo_id livre: {disp_id}\n"
    )


def executar(lei: Lei):
    """Ponto de entrada dos scripts finos: `python3 parse_x.py > seed_x.sql`.
    Com `--depurar`, lista no stderr as linhas que nenhum padrão reconheceu."""
    artigos = interpretar(lei, depurar="--depurar" in sys.argv)
    emitir_sql(lei, artigos)
