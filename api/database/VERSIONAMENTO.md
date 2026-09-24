# Versionamento das leis (armazenamento offline do app)

O app pode guardar livros no aparelho ("Perfil › Armazenamento"). Para saber se
uma cópia está desatualizada — sem baixar nada —, cada lei tem uma versão
`major.minor` publicada pelo backend.

## Colocando no ar (uma vez por ambiente)

```bash
mysql sabe_a_lei < api/database/migrations/001_versionamento_offline.sql   # cria 3 tabelas novas
php api/bin/publicar-versao.php --todas                                    # publica a versão 1.0 de cada lei
```

Enquanto a migration não for aplicada, os endpoints abaixo respondem **503** e o
app segue funcionando online, como sempre. A migration não altera nenhuma tabela existente.

## Publicando uma atualização (fluxo do dia a dia)

1. Altere o conteúdo da lei no banco (reseed, correção pontual, novo artigo…).
2. Rode:

```bash
php api/bin/publicar-versao.php codigo-penal-1940                 # 1.1 → 1.2
php api/bin/publicar-versao.php codigo-penal-1940 --simular       # só mostra o que mudaria
php api/bin/publicar-versao.php codigo-penal-1940 --notas="Lei 14.xxx/2026"
php api/bin/publicar-versao.php codigo-penal-1940 --major         # mudança estrutural
```

O publicador compara o banco com o último snapshot publicado (um hash por
artigo, incluindo seus dispositivos) e registra sozinho o que foi **inserido,
alterado e removido** — não há JSON de atualização para escrever. Sem mudanças,
não publica nada.

- **minor** (padrão): o app baixa só o que mudou.
- **major** (`--major`): para alterações estruturais (renumeração em massa,
  reorganização dos livros/títulos). O app baixa o livro inteiro de novo.
- Mais de 300 artigos alterados numa atualização também mandam o app baixar o livro inteiro.

> Depois de mudar o conteúdo, **publique**. Conteúdo alterado e não publicado faz
> o checksum do livro divergir do anunciado; o app detecta, descarta o download e
> tenta de novo mais tarde.

## Endpoints

| Rota | Uso |
|---|---|
| `GET /biblioteca/manifesto` | Versão e checksum de cada livro publicado. É a única requisição feita ao abrir o app. |
| `GET /leis/:slug/conteudo?limit=100&offset=0` | Livro completo, por páginas, com dispositivos e hash por artigo. |
| `GET /leis/:slug/atualizacoes?de=1.1` | Mudanças (`insert`/`update`/`delete`) da versão `1.1` até a última, já com o conteúdo dos artigos. Traz `requerDownloadCompleto` quando o delta não é viável. |

O livro é identificado pelo slug da lei (`codigo-penal-1940`); o artigo, dentro
das atualizações, pela chave natural `parte` + `numero` (não pelo id).

## Integridade

- Cada artigo tem um `hash` do conteúdo (SHA-1, calculado no servidor).
- O checksum do livro é o SHA-256 de `parte|ordem|numero|hash` de todos os
  artigos, na ordem de leitura. O app recalcula esse valor a partir do que guardou
  e compara com o do servidor (`LivroOffline.checksum` ↔ `ConteudoOffline::checksumDoLivro`;
  as duas fórmulas precisam continuar idênticas).

## Requisitos

Os ids dos artigos (`artigos.id`) precisam se manter estáveis entre reseeds —
favoritos já dependem disso, e o app também usa o id para abrir o artigo.
