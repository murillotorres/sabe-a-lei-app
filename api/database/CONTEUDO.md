# Conteúdo cadastrado no banco de leis

Registro do que já foi importado para as tabelas `categorias` / `leis` / `artigos` /
`artigo_dispositivos` (ver `schema.sql`), para consulta rápida antes de importar a
próxima lei — evita reprocessar o que já existe e mostra o padrão a seguir.

## Constituição Federal

- **Categoria:** `constituicao-federal`
- **Lei:** `constituicao-federal-1988` — Constituição da República Federativa do Brasil de 1988
- **Fonte:** https://www.planalto.gov.br/ccivil_03/constituicao/constituicao.htm
- **Seed:** `api/database/seed_constituicao.sql` (schema + dados em um único arquivo, idempotente)

| Parte | Artigos | Observação |
|---|---|---|
| `permanente` | 274 | Preâmbulo + Art. 1º a 250 (inclui artigos com sufixo de letra, ex. 103-A, 149-A) |
| `adct` | 138 | Ato das Disposições Constitucionais Transitórias, Art. 1º a 138 (numeração própria, sem título/capítulo/seção) |

Total: **412 artigos** e **2.919 dispositivos** (parágrafos + incisos + alíneas).

### Como foi gerado

O HTML oficial foi baixado e convertido de ISO-8859-1 para UTF-8, depois processado
por um parser (`BeautifulSoup` + regex) que:

- reconhece Título/Capítulo/Seção/Subseção, `Art.`, `§`/"Parágrafo único", incisos
  (numeral romano) e alíneas (`a)`, `b)`...) para montar a hierarquia;
- **descarta trechos riscados** (`<strike>` ou `text-decoration: line-through`), que no
  site do Planalto marcam redações antigas já substituídas — mantém só o texto vigente;
- anexa a citação da emenda ("Redação dada pela Emenda Constitucional nº X") ao final
  do texto vigente, quando presente;
- marca `revogado = 1` quando o dispositivo começa com "revogado(a)" (ex.: `Art. 12, §4º, II, a) revogada;`).

### Limitações conhecidas

- A detecção de `revogado` é heurística (regex no início do texto); um artigo/dispositivo
  revogado com redação atípica pode não ser marcado.
- Um artigo duplicado (`ADCT Art. 83`, causado por HTML malformado na fonte — uma tag
  `<p>` não fechada corretamente dentro de um `<strike>`) foi detectado e deduplicado
  automaticamente (mantendo a redação mais recente). Se o Planalto atualizar o HTML,
  vale reconferir a lógica de dedupe em `parse_constituicao.py` antes de reprocessar.
- Não inclui as Emendas Constitucionais como documentos à parte, só o texto consolidado.

## Código Civil

- **Categoria:** `codigos` (nova — antes só existia `constituicao-federal`)
- **Lei:** `codigo-civil-2002` — Código Civil (Lei nº 10.406, de 2002)
- **Fonte:** https://www.planalto.gov.br/ccivil_03/leis/2002/l10406compilada.htm
- **Seed:** `api/database/seed_codigo_civil.sql` (idempotente — apaga e recria `lei_id = 2` /
  `categoria_id = 2`, não mexe na Constituição)
- **Parser:** `api/database/parse_codigo_civil.py` (Python 3 + BeautifulSoup)

Total: **2.092 artigos** (2.046 numerados + variações com sufixo de letra, ex.
`1.358-A`...`1.358-U`) e **1.751 dispositivos**. `parte` é sempre `'permanente'` — o
Código Civil não tem uma divisão equivalente ao ADCT da Constituição.

O Código Civil tem uma hierarquia mais profunda que a Constituição (Parte Geral/Especial
→ Livro → Título → Capítulo → Seção → Subseção, contra só Título → Capítulo → Seção →
Subseção). Em vez de alterar o schema pra caber mais níveis, Parte + Livro + Título ficam
concatenados em `titulo_estrutural` (ex.: `'Parte Especial · Livro I · Título I'`);
Capítulo/Seção/Subseção seguem 1:1 como na Constituição. Como esses campos só alimentam o
cabeçalho de agrupamento na listagem (`Artigo.grupoEstrutural` no app), essa opção evita
mexer no backend e no app por causa de uma lei só.

### Como foi gerado

Mesma abordagem da Constituição (baixar o HTML, processar com BeautifulSoup + regex), com
duas diferenças de formato encontradas neste documento:

- **Sem `<strike>`**: este HTML não usa texto riscado — um dispositivo/artigo revogado
  aparece com o próprio texto substituído por `(Revogado[s] pela Lei nº X, de Y)`
  (geralmente dentro de um link). `revogado = 1` quando o texto começa com "revogado(a)(s)".
- **Cabeçalhos sem numeral romano**: `CAPÍTULO ÚNICO`, `TÍTULO ÚNICO` e `Seção Única`
  aparecem em vez de um numeral (só nesta lei) — tratados como caso especial no parser.
- **Faixa de artigos revogados em bloco**: `Art. 1.620. a 1.629. (Revogados pela Lei nº
  12.010, de 2009)` — um único parágrafo no HTML cobrindo 10 artigos; o parser expande em
  uma linha por artigo do intervalo, todas revogadas, pra não perder a numeração.

### Limitações conhecidas

- Mesma heurística de `revogado` da Constituição (regex no início do texto).
- `§ 10`, `§ 11`... não levam "º" (só de 1º a 9º, seguindo a redação original) — mas o
  rótulo é sintetizado pelo parser, não copiado do HTML; se o Planalto usar outra
  convenção em uma faixa diferente, vale reconferir.

## Código Penal

- **Categoria:** `codigos` (mesma do Código Civil — `INSERT IGNORE`, não recria)
- **Lei:** `codigo-penal-1940` — Código Penal (Decreto-Lei nº 2.848, de 1940)
- **Fonte:** https://www.planalto.gov.br/ccivil_03/decreto-lei/del2848compilado.htm
- **Seed:** `api/database/seed_codigo_penal.sql` (idempotente — apaga e recria `lei_id = 3`,
  não mexe nas outras leis)
- **Parser:** `api/database/parse_codigo_penal.py` (Python 3, sem BeautifulSoup — ver abaixo)

Total: **434 artigos** (361 numerados de 1 a 361 + 73 variações com sufixo de letra, ex.
`121-A`/`121-B`, `359-M-A`/`359-M-B`) e **913 dispositivos**. `parte` é sempre `'permanente'`.
Hierarquia: Parte (Geral/Especial) → Título → Capítulo → Seção, sem Livro/Subseção — por
isso `titulo_estrutural` aqui é só `'Parte · Título'` (sem o terceiro nível que o Código
Civil usa para Livro).

### Por que este parser não usa BeautifulSoup

Este HTML (Decreto-Lei de 1940, com 85 anos de emendas usando ferramentas de autoria
diferentes) tem tags não fechadas cruzando limites de `<p>` de um jeito que faz **tanto**
`html.parser` **quanto** `lxml` perderem parágrafos inteiros ao montar a árvore — o texto
existe em `soup.get_text()` do documento inteiro, mas nenhum `<p>` individual o contém (ex.:
o Art. 1º e o Art. 184 simplesmente somem). Em vez de tentar consertar a árvore, o parser
corta o HTML bruto direto nas posições de abertura de `<p ...>` (`re.split` com regex) e
extrai o texto de cada trecho removendo tags por regex — mais grosseiro, mas não depende de
reconstruir uma árvore corretamente a partir de uma marcação inconsistente.

### Outras diferenças de formato encontradas

- **Charset real é Windows-1252, não ISO-8859-1**: o gerador (Microsoft FrontPage 6.0)
  grava bytes como `0x96` (travessão, usado em muitos incisos: "I – texto") que só
  decodificam certo em `cp1252`; em `iso-8859-1` viram caracteres de controle e quebram o
  reconhecimento de inciso.
- **Separador do artigo/parágrafo é traço, não ponto**: "Art. 2º **-** Ninguém..." em vez
  do "Art. 1º Toda pessoa..." do Código Civil.
- **Ordinal (º) de vários §§ antigos vem de `<sup>o</sup>`**: um "o" minúsculo real dentro
  de `<sup>`, não o caractere º — ao virar texto puro sobra um "o" solto (às vezes com
  espaço extra ao redor, por causa da própria extração). O parser aceita `[ºo°]` com
  tolerância de espaço.
- **Ambiguidade traço-sufixo vs. traço-separador**: "Art. 120 **-** A sentença..." (traço
  separando o número da frase, que por acaso começa com a letra maiúscula "A") é
  estruturalmente idêntico a "Art. 121**-A**. Matar..." (sufixo de letra de verdade) até
  você reparar que o sufixo real vem colado no número/ordinal (sem espaço) e o separador,
  não. O parser só reconhece sufixo de letra quando o traço está imediatamente colado —
  isso já pegou um falso "Art. 120-A" e um "§ 3º-A" fantasmas nos testes.
- **Rubricas marginais**: cada crime tem um título curto acima do artigo (ex. "Homicídio
  simples", "Feminicídio") que não é um cabeçalho estrutural (não é Título/Capítulo/Seção)
  nem tem marcação HTML consistente (às vezes negrito, às vezes não) — o parser descarta
  qualquer linha que não bata com nenhum padrão de artigo/parágrafo/inciso/alínea/Pena,
  mesma política que já se aplicava ao texto descritivo dos cabeçalhos estruturais.
- **Linha "Pena – ..."**: não é um dispositivo numerado; o parser anexa esse texto ao
  caput ou ao dispositivo aberto no momento (parágrafo/inciso), em vez de inventar um tipo
  novo no schema.
- **Bloco de artigos revogados comprimidos**: Arts. 187 a 196 (revogados em bloco pela Lei
  de Propriedade Industrial) aparecem com rubrica + "Art. N. (Revogado...)" repetidos dentro
  de um único `<p>` — o parser detecta múltiplas ocorrências de "Art. N. (Revogado...)" na
  mesma linha e emite um artigo por ocorrência.
- **Sufixo de duas letras**: "Art. 359-M-A" e "Art. 359-M-B" (crimes contra o Estado
  Democrático de Direito, incluídos em 2021) — o grupo de sufixo aceita uma segunda letra
  opcional.

### Bug de hierarquia encontrado (e corrigido só aqui)

O cálculo de nível de uma alínea, herdado do parser da Constituição/Código Civil
(`nivel_pai = max(pilha_nivel.keys())`), pendura cada alínea na **alínea anterior** em vez
do inciso/parágrafo pai, porque depois que a primeira alínea é inserida ela também aparece
em `pilha_nivel` no nível em que a próxima alínea seria colocada. Numa lista "a) b) c) d)"
isso gera uma escada (b) filha de a), c) filha de b)...) em vez de irmãs — só não apareceu
antes porque nenhuma lei processada tinha sequências longas de alíneas. Este parser corrige
isso rastreando o nível do último parágrafo/inciso aberto (`nivel_container`) e sempre
pendurando a alínea nele, não no `max(pilha_nivel)`. **Esse bug pode existir também em
`parse_constituicao.py`/`parse_codigo_civil.py` e nos dados já em produção** — não foi
verificado nem corrigido lá (fora do escopo desta lei).

### Limitações conhecidas

- Mesma heurística de `revogado` da Constituição/Código Civil (regex no início do texto).
- Um punhado de provisões `(VETADO)` sem numeração própria (ex. no Título XII, crimes
  contra o Estado Democrático de Direito) são descartadas — não há como representá-las no
  schema atual sem inventar um rótulo, e não têm efeito jurídico mesmo.
- Ao menos um typo real do texto oficial foi encontrado e tolerado no parser: "III perda..."
  (Art. 129, sem o traço que os incisos vizinhos têm) e "A rt. 107" (espaço espúrio dentro
  de "Art.").

## Código de Processo Civil

- **Categoria:** `codigos` (mesma dos outros códigos — `INSERT IGNORE`, não recria)
- **Lei:** `codigo-processo-civil-2015` — Código de Processo Civil (Lei nº 13.105, de 2015)
- **Fonte:** https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2015/lei/l13105.htm
- **Seed:** `api/database/seed_cpc.sql` (idempotente — apaga e recria `lei_id = 4`, não mexe
  nas outras leis)
- **Parser:** `api/database/parse_cpc.py` (Python 3 + BeautifulSoup)

Total: **1.073 artigos** (1.071 numerados de 1 a 1.072 — falta o 945, revogado sem deixar
nem um "(Revogado)" no texto compilado — + 2 variações com sufixo de letra: `699-A`,
`1.035-A`) e **2.843 dispositivos**. Hierarquia igual à do Código Civil: Parte → Livro →
Título → Capítulo → Seção → Subseção, com `titulo_estrutural` = `'Parte · Livro · Título'`.

### Diferenças de formato encontradas

- **Charset Windows-1252** (mesmo motivo do Código Penal — aspas curvas e travessão em
  bytes fora do ISO-8859-1).
- **Redação superada nem sempre usa `<strike>`**: às vezes é só CSS inline
  (`style="text-decoration:line-through"` num `<span>`/`<font>`), sem a tag — o parser
  descompõe os dois casos. Sem isso, o Art. 153 (por exemplo) aparecia duas vezes: a
  redação de 2015 e a redação atual.
- **Citação literal de outra lei dentro de um artigo do próprio CPC**: as "Disposições
  Finais e Transitórias" (Arts. 1.060–1.071) alteram outras leis (Lei de Arbitragem,
  Código Civil, Código Eleitoral, Lei de Registros Públicos...) citando o texto integral
  do artigo alterado, sempre entre aspas curvas (`"..."`). Sem tratamento especial, esse
  texto citado — que tem sua própria numeração de Art./§/inciso — seria lido como um
  artigo novo do CPC, colidindo com um artigo real do CPC de mesmo número (ex.: a citação
  do "Art. 275" do Código Eleitoral dentro do Art. 1.067 do CPC quase virou um "Art. 275"
  fantasma, quando o CPC já tem um Art. 275 de verdade). O parser detecta a abertura
  (linha começando com `"`) e o fechamento (linha contendo `"`) e trata tudo no meio como
  continuação do caput do artigo do CPC que abriu a citação, nunca como dispositivo novo.
- **`(VETADO)` mantém a numeração** (ao contrário do Código Penal, onde alguns vetos
  ficam sem nenhum número): `Art. 1.055. (VETADO).` é só mais um artigo, marcado
  `revogado = 1` pela mesma heurística que já cobre "vetado" além de "revogado".

### Limitações conhecidas

- Mesma heurística de `revogado`/`vetado` das demais leis (regex no início do texto).
- O Art. 945 não existe no banco (revogado no texto compilado sem deixar substituto) —
  não é um bug do parser, é assim que o Planalto publica; ver `parse_stats_cpc.txt` (não
  versionado) para os totais exatos de uma reexecução.

## Pendente (ainda não cadastrado)

- **Outros Códigos** (Processo Penal, Tributário Nacional, etc.) e **Estatutos** (ECA,
  Idoso, etc.) — sem cards na Biblioteca por enquanto (os cards "Códigos", "Estatutos" e
  "Todas as Leis" foram removidos da grade a pedido; as telas placeholder ainda existem em
  `SabeALei/Views/Tabs/` mas não são mais navegáveis).
- Categoria `estatutos` ainda não existe na tabela `categorias`.

## Como reaplicar / atualizar

```
mysql -h <host> -u <user> -p < api/database/seed_constituicao.sql
mysql -h <host> -u <user> -p < api/database/seed_codigo_civil.sql
mysql -h <host> -u <user> -p < api/database/seed_codigo_penal.sql
mysql -h <host> -u <user> -p < api/database/seed_cpc.sql
```

Cada script cria as tabelas com `CREATE TABLE IF NOT EXISTS` e, antes de inserir, apaga
apenas as linhas da sua própria lei (`DELETE ... WHERE lei_id = 1` ou `= 2`) — seguro
rodar de novo sem duplicar nem afetar a outra lei. Ao adicionar uma lei nova, os próximos
IDs livres de `artigos`/`artigo_dispositivos` (e o próximo `categoria_id`/`lei_id`) saem de
`SELECT MAX(id) FROM ...` — os scripts atuais usam valores fixos calculados a partir do
estado do banco no momento em que foram gerados (ver `ARTIGO_ID_INICIAL` etc. no topo de
`parse_codigo_civil.py`), então confira que o banco alvo bate com esses números antes de
reaplicar num ambiente com mais leis do que quando o script foi escrito.

## Estrutura do schema (resumo)

- `categorias` — slug + nome (ex.: `constituicao-federal`).
- `leis` — pertence a uma categoria; slug + título + fonte.
- `artigos` — um card da listagem: número, `parte` (`permanente`/`adct`), hierarquia
  (título/capítulo/seção/subseção como texto), caput, `revogado`, `ordem`.
- `artigo_dispositivos` — um card da tela de detalhe: `tipo`
  (`paragrafo`/`inciso`/`alinea`/`item`), `rotulo` (ex. `§ 1º`, `I`, `a)`), `texto`,
  `nivel` (profundidade), `parent_id` (auto-relacionamento — alínea aponta pro inciso
  pai, inciso pode apontar pro parágrafo pai), `revogado`, `ordem`.
