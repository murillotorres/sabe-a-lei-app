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

## Pendente (ainda não cadastrado)

- **Códigos** (Civil, Penal, Processo Civil, etc.) — aba "Códigos" no app ainda é placeholder.
- **Estatutos** (ECA, Idoso, etc.) — aba "Estatutos" no app ainda é placeholder.
- Categorias `codigos` e `estatutos` ainda não existem na tabela `categorias`.

## Como reaplicar / atualizar

```
mysql -h <host> -u <user> -p < api/database/seed_constituicao.sql
```

O script cria as tabelas com `CREATE TABLE IF NOT EXISTS` e, antes de inserir, apaga
apenas as linhas da lei `constituicao-federal-1988` (`DELETE ... WHERE lei_id = 1`) —
seguro para rodar de novo sem duplicar nem afetar outras leis.

## Estrutura do schema (resumo)

- `categorias` — slug + nome (ex.: `constituicao-federal`).
- `leis` — pertence a uma categoria; slug + título + fonte.
- `artigos` — um card da listagem: número, `parte` (`permanente`/`adct`), hierarquia
  (título/capítulo/seção/subseção como texto), caput, `revogado`, `ordem`.
- `artigo_dispositivos` — um card da tela de detalhe: `tipo`
  (`paragrafo`/`inciso`/`alinea`/`item`), `rotulo` (ex. `§ 1º`, `I`, `a)`), `texto`,
  `nivel` (profundidade), `parent_id` (auto-relacionamento — alínea aponta pro inciso
  pai, inciso pode apontar pro parágrafo pai), `revogado`, `ordem`.
