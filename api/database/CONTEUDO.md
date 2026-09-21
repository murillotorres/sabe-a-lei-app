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

## Pendente (ainda não cadastrado)

- **Outros Códigos** (Penal, Processo Civil, Processo Penal, etc.) — a aba "Códigos" no
  app hoje só teria o Código Civil.
- **Estatutos** (ECA, Idoso, etc.) — aba "Estatutos" no app ainda é placeholder.
- Categoria `estatutos` ainda não existe na tabela `categorias`.

## Como reaplicar / atualizar

```
mysql -h <host> -u <user> -p < api/database/seed_constituicao.sql
mysql -h <host> -u <user> -p < api/database/seed_codigo_civil.sql
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
