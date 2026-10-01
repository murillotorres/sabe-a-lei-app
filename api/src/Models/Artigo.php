<?php

declare(strict_types=1);

namespace App\Models;

use App\Core\Database;
use PDO;

final class Artigo
{
    /// Artigos de uma lei/parte, em ordem de leitura. Sem `$limit`, devolve todos
    /// (usado pela busca, que precisa pontuar o livro inteiro); com `$limit`,
    /// devolve só essa "página" a partir de `$offset`. `$numero` restringe ao
    /// artigo com esse número exato (ex.: "150", "103-A").
    public static function listByLei(
        int $leiId,
        string $parte,
        ?int $limit = null,
        int $offset = 0,
        ?string $numero = null,
    ): array {
        $sql = 'SELECT id, parte, numero, titulo_estrutural, capitulo_estrutural,
                       secao_estrutural, subsecao_estrutural, descricao_estrutural,
                       rubrica, caput, revogado, ordem
                FROM artigos
                WHERE lei_id = :lei_id AND parte = :parte';

        if ($numero !== null) {
            $sql .= ' AND numero = :numero';
        }

        $sql .= ' ORDER BY ordem';

        if ($limit !== null) {
            $sql .= ' LIMIT :limit OFFSET :offset';
        }

        $stmt = Database::connection()->prepare($sql);
        $stmt->bindValue(':lei_id', $leiId, PDO::PARAM_INT);
        $stmt->bindValue(':parte', $parte, PDO::PARAM_STR);

        if ($numero !== null) {
            $stmt->bindValue(':numero', $numero, PDO::PARAM_STR);
        }

        // Com prepares nativos (ver Database), LIMIT/OFFSET só aceitam inteiros de verdade.
        if ($limit !== null) {
            $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
            $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        }

        $stmt->execute();

        return $stmt->fetchAll();
    }

    /// Todos os artigos de todas as leis cadastradas, com o slug/título da lei
    /// já incluídos — usado pela busca global (aba Buscar, ver `BuscaGlobal`),
    /// que não fica restrita a uma lei/parte específica.
    public static function listAll(): array
    {
        $stmt = Database::connection()->prepare(
            'SELECT a.id, a.parte, a.numero, a.titulo_estrutural, a.capitulo_estrutural,
                    a.secao_estrutural, a.subsecao_estrutural, a.descricao_estrutural,
                    a.rubrica, a.caput, a.revogado, a.ordem,
                    a.lei_id, leis.slug AS lei_slug, leis.titulo AS lei_titulo
             FROM artigos a
             INNER JOIN leis ON leis.id = a.lei_id
             ORDER BY leis.id, a.parte, a.ordem'
        );
        $stmt->execute();

        return $stmt->fetchAll();
    }

    /// Busca por palavras soltas dentro de uma lei/parte específica (ex.: só o
    /// texto permanente da Constituição). Ver `pontuarEOrdenar` pro critério
    /// de relevância. Palavra que não aparece em nenhum artigo é completada ou
    /// corrigida (`CorrecaoDeBusca`); a consulta corrigida volta em `sugestao`.
    /// @return array{artigos: array, sugestao: ?string}
    public static function search(int $leiId, string $parte, string $query): array
    {
        $tokens = self::tokenizar($query);
        $artigos = $tokens === [] ? [] : self::listByLei($leiId, $parte);
        if ($artigos === []) {
            return ['artigos' => [], 'sugestao' => null];
        }

        $dispositivos = self::dispositivosPorArtigo(array_map(static fn (array $a) => (int) $a['id'], $artigos));
        $textos = array_map(
            static fn (array $a) => $a['caput'] . ' ' . implode(' ', array_column($dispositivos[(int) $a['id']] ?? [], 'texto')),
            $artigos
        );
        $normalizados = array_map(self::normalizar(...), $textos);

        $ajuste = CorrecaoDeBusca::ajustar(
            $tokens,
            static function (string $token) use ($normalizados): bool {
                $padrao = self::padraoDoToken($token);
                foreach ($normalizados as $texto) {
                    if (preg_match($padrao, $texto) === 1) {
                        return true;
                    }
                }
                return false;
            },
            static fn () => $textos,
        );

        return [
            'artigos' => self::pontuarEOrdenar(
                $artigos, $ajuste['tokens'] ?? $tokens, $dispositivos, $normalizados, $ajuste['alternativas'] ?? []
            ),
            'sugestao' => $ajuste['sugestao'] ?? null,
        ];
    }

    /// Pontua cada artigo pela compatibilidade com as palavras buscadas e
    /// ordena por relevância: quanto mais palavras da busca o artigo contém,
    /// mais relevante ele é; entre artigos igualmente relevantes, prevalece a
    /// ordem original da lei (e, na busca global, a ordem das leis entre si).
    private static function pontuarEOrdenar(
        array $artigos, array $tokens, array $dispositivosPorArtigo, array $normalizados, array $alternativas,
    ): array
    {
        $pontuados = [];
        foreach ($artigos as $indice => $artigo) {
            $dispositivos = $dispositivosPorArtigo[(int) $artigo['id']] ?? [];

            $pontuacao = self::pontuar($normalizados[$indice], $tokens, $alternativas);
            if ($pontuacao === 0) {
                continue;
            }

            // Quando a busca "bate" em algum dispositivo (parágrafo/inciso/alínea),
            // não só no caput, devolve esse trecho junto — é o que explica pro
            // usuário por que aquele artigo apareceu no resultado.
            $artigo['trecho_correspondente'] = self::trechoCorrespondente($dispositivos, $tokens, $alternativas);

            $pontuados[] = ['artigo' => $artigo, 'pontuacao' => $pontuacao];
        }

        usort($pontuados, static function (array $a, array $b): int {
            return $a['pontuacao'] !== $b['pontuacao']
                ? $b['pontuacao'] <=> $a['pontuacao']
                : $a['artigo']['ordem'] <=> $b['artigo']['ordem'];
        });

        return array_map(static fn (array $p) => $p['artigo'], $pontuados);
    }

    /// Mapa artigo_id => lista de seus dispositivos (rotulo, texto, tipo).
    public static function dispositivosPorArtigo(array $artigoIds): array
    {
        if ($artigoIds === []) {
            return [];
        }

        $placeholders = implode(',', array_fill(0, count($artigoIds), '?'));
        $stmt = Database::connection()->prepare(
            "SELECT artigo_id, tipo, rotulo, texto FROM artigo_dispositivos
             WHERE artigo_id IN ($placeholders) ORDER BY ordem"
        );
        $stmt->execute($artigoIds);

        $porArtigo = [];
        foreach ($stmt->fetchAll() as $row) {
            $porArtigo[(int) $row['artigo_id']][] = $row;
        }

        return $porArtigo;
    }

    /// O dispositivo (parágrafo/inciso/alínea) que melhor casa com a busca,
    /// para mostrar ao usuário qual trecho interno do artigo motivou o resultado.
    /// `null` quando a busca bateu só no caput, sem nenhum dispositivo relevante.
    private static function trechoCorrespondente(array $dispositivos, array $tokens, array $alternativas): ?array
    {
        $melhor = null;
        $melhorPontuacao = 0;

        foreach ($dispositivos as $dispositivo) {
            $pontuacao = self::pontuar(self::normalizar($dispositivo['texto']), $tokens, $alternativas);
            if ($pontuacao > $melhorPontuacao) {
                $melhorPontuacao = $pontuacao;
                $melhor = $dispositivo;
            }
        }

        if ($melhor === null) {
            return null;
        }

        return [
            'tipo' => $melhor['tipo'],
            'rotulo' => $melhor['rotulo'],
            'texto' => $melhor['texto'],
        ];
    }

    /// Pontuação de compatibilidade de um texto com as palavras buscadas: pesa
    /// sobretudo quantas palavras distintas da busca aparecem (como palavra
    /// inteira, não como pedaço de outra — "poder" não deve casar "poderá");
    /// entre textos que contêm todas as palavras, prioriza aqueles em que elas
    /// aparecem próximas umas das outras (como na frase digitada), não apenas
    /// espalhadas em pontos distintos de um artigo longo.
    /// `$alternativas`: outras palavras que valem por um token (as completações
    /// de uma palavra digitada pela metade), além das abreviações.
    public static function pontuar(string $texto, array $tokens, array $alternativas = []): int
    {
        $ocorrenciasPorToken = [];
        foreach ($tokens as $indice => $token) {
            if (preg_match_all(self::padraoDoToken($token, $alternativas[$token] ?? []), $texto, $matches, PREG_OFFSET_CAPTURE) > 0) {
                $ocorrenciasPorToken[$indice] = array_column($matches[0], 1);
            }
        }

        $tokensEncontrados = count($ocorrenciasPorToken);
        if ($tokensEncontrados === 0) {
            return 0;
        }

        $totalOcorrencias = array_sum(array_map('count', $ocorrenciasPorToken));
        $pontuacao = $tokensEncontrados * 100_000 + min($totalOcorrencias, 50);

        if ($tokensEncontrados === count($tokens)) {
            $janela = self::menorJanela($ocorrenciasPorToken);
            if ($janela !== null) {
                $pontuacao += max(0, 50_000 - $janela);
            }
        }

        return $pontuacao;
    }

    /// Menor trecho do texto que contém pelo menos uma ocorrência de cada
    /// palavra buscada (janela deslizante sobre as posições, uma lista por
    /// palavra) — quanto menor, mais "juntas" as palavras aparecem no texto.
    private static function menorJanela(array $ocorrenciasPorToken): ?int
    {
        $eventos = [];
        foreach ($ocorrenciasPorToken as $tokenIndice => $posicoes) {
            foreach ($posicoes as $posicao) {
                $eventos[] = [$posicao, $tokenIndice];
            }
        }
        usort($eventos, static fn (array $a, array $b): int => $a[0] <=> $b[0]);

        $totalTokens = count($ocorrenciasPorToken);
        $contagem = [];
        $distintos = 0;
        $menor = null;
        $esquerda = 0;

        foreach ($eventos as $direita => [$posicao, $tokenIndice]) {
            $contagem[$tokenIndice] = ($contagem[$tokenIndice] ?? 0) + 1;
            if ($contagem[$tokenIndice] === 1) {
                $distintos++;
            }

            while ($distintos === $totalTokens) {
                $janela = $posicao - $eventos[$esquerda][0];
                if ($menor === null || $janela < $menor) {
                    $menor = $janela;
                }

                $tokenEsquerda = $eventos[$esquerda][1];
                $contagem[$tokenEsquerda]--;
                if ($contagem[$tokenEsquerda] === 0) {
                    $distintos--;
                }
                $esquerda++;
            }
        }

        return $menor;
    }

    /// Abreviações que a busca entende: a palavra digitada casa também com as
    /// formas listadas ("inc" acha "inciso"; "art" e "artigo" se acham). Mesma
    /// tabela da busca do app (`BuscaTexto.abreviacoes`).
    public const ABREVIACOES = [
        'art' => ['artigo'],
        'artigo' => ['art'],
        'arts' => ['artigos'],
        'artigos' => ['arts'],
        'par' => ['paragrafo'],
        'inc' => ['inciso'],
        'al' => ['alinea'],
        'cod' => ['codigo'],
        'const' => ['constituicao'],
        'dec' => ['decreto'],
        'proc' => ['processo'],
        'cf' => ['constituicao federal'],
        'ec' => ['emenda constitucional'],
        'lc' => ['lei complementar'],
        'dl' => ['decreto lei'],
        'adct' => ['ato das disposicoes constitucionais transitorias'],
        'stf' => ['supremo tribunal federal'],
        'stj' => ['superior tribunal de justica'],
        'tse' => ['tribunal superior eleitoral'],
        'tst' => ['tribunal superior do trabalho'],
        'mp' => ['ministerio publico'],
    ];

    /// Regex de palavra inteira para um token da busca, já com as abreviações
    /// e as `$extras` (completações).
    public static function padraoDoToken(string $token, array $extras = []): string
    {
        $alternativas = array_map(
            static fn (string $a) => str_replace(' ', '\s+', preg_quote($a, '/')),
            [$token, ...(self::ABREVIACOES[$token] ?? []), ...$extras]
        );

        return '/\b(?:' . implode('|', $alternativas) . ')\b/u';
    }

    public static function tokenizar(string $query): array
    {
        $tokens = preg_split('/[^\p{L}\p{N}]+/u', self::normalizar($query), -1, PREG_SPLIT_NO_EMPTY) ?: [];

        return array_values(array_unique($tokens));
    }

    /// Forma comparável de um texto: minúsculas, sem acento, sem ordinal
    /// ("5º" = "5"), "§" por extenso e hífen/travessão como espaço ("decreto-lei"
    /// = "decreto lei"). A pontuação some na separação das palavras. Tem que
    /// ficar idêntica a `BuscaTexto.normalizar` no app — a busca offline
    /// depende disso para dar o mesmo resultado.
    public static function normalizar(string $texto): string
    {
        $texto = mb_strtolower($texto, 'UTF-8');

        static $especiais = ['º' => '', '°' => '', 'ª' => '', '§' => ' paragrafo ',
            '-' => ' ', '‐' => ' ', '‑' => ' ', '–' => ' ', '—' => ' '];
        static $comAcento = ['á', 'à', 'â', 'ã', 'ä', 'é', 'è', 'ê', 'ë', 'í', 'ì', 'î', 'ï',
            'ó', 'ò', 'ô', 'õ', 'ö', 'ú', 'ù', 'û', 'ü', 'ç', 'ñ'];
        static $semAcento = ['a', 'a', 'a', 'a', 'a', 'e', 'e', 'e', 'e', 'i', 'i', 'i', 'i',
            'o', 'o', 'o', 'o', 'o', 'u', 'u', 'u', 'u', 'c', 'n'];

        return str_replace($comAcento, $semAcento, strtr($texto, $especiais));
    }

    public static function find(int $id): ?array
    {
        $stmt = Database::connection()->prepare(
            'SELECT artigos.id, artigos.lei_id, artigos.parte, artigos.numero,
                    artigos.titulo_estrutural, artigos.capitulo_estrutural,
                    artigos.secao_estrutural, artigos.subsecao_estrutural,
                    artigos.descricao_estrutural, artigos.rubrica,
                    artigos.caput, artigos.revogado, artigos.ordem,
                    leis.slug AS lei_slug, leis.titulo AS lei_titulo
             FROM artigos
             INNER JOIN leis ON leis.id = artigos.lei_id
             WHERE artigos.id = :id
             LIMIT 1'
        );
        $stmt->execute(['id' => $id]);

        return $stmt->fetch() ?: null;
    }

    public static function dispositivos(int $artigoId): array
    {
        $stmt = Database::connection()->prepare(
            'SELECT id, parent_id, tipo, rotulo, texto, nivel, revogado, ordem
             FROM artigo_dispositivos
             WHERE artigo_id = :artigo_id
             ORDER BY ordem'
        );
        $stmt->execute(['artigo_id' => $artigoId]);

        return $stmt->fetchAll();
    }

    public static function dispositivo(int $id): ?array
    {
        $stmt = Database::connection()->prepare(
            'SELECT id, artigo_id, tipo, rotulo, texto
             FROM artigo_dispositivos
             WHERE id = :id
             LIMIT 1'
        );
        $stmt->execute(['id' => $id]);

        return $stmt->fetch() ?: null;
    }

    /// Formato de artigo devolvido pela API (chaves em camelCase). Compartilhado
    /// entre a listagem/busca de artigos e a listagem de favoritos.
    public static function formatar(array $a): array
    {
        return [
            'id' => (int) $a['id'],
            'parte' => $a['parte'],
            'numero' => $a['numero'],
            'tituloEstrutural' => $a['titulo_estrutural'],
            'capituloEstrutural' => $a['capitulo_estrutural'],
            'secaoEstrutural' => $a['secao_estrutural'],
            'subsecaoEstrutural' => $a['subsecao_estrutural'],
            'descricaoEstrutural' => $a['descricao_estrutural'] ?? null,
            'rubrica' => $a['rubrica'] ?? null,
            'caput' => $a['caput'],
            'revogado' => (bool) $a['revogado'],
            'ordem' => (int) $a['ordem'],
            'leiSlug' => $a['lei_slug'] ?? null,
            'leiTitulo' => $a['lei_titulo'] ?? null,
        ];
    }
}
