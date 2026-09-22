<?php

declare(strict_types=1);

namespace App\Models;

use App\Core\Database;

final class Artigo
{
    public static function listByLei(int $leiId, string $parte): array
    {
        $stmt = Database::connection()->prepare(
            'SELECT id, parte, numero, titulo_estrutural, capitulo_estrutural,
                    secao_estrutural, subsecao_estrutural, descricao_estrutural,
                    rubrica, caput, revogado, ordem
             FROM artigos
             WHERE lei_id = :lei_id AND parte = :parte
             ORDER BY ordem'
        );
        $stmt->execute(['lei_id' => $leiId, 'parte' => $parte]);

        return $stmt->fetchAll();
    }

    /// Todos os artigos de todas as leis cadastradas, com o slug/título da lei
    /// já incluídos — usado pela busca global (aba Buscar), que não fica
    /// restrita a uma lei/parte específica como a busca dentro da Constituição.
    public static function listAll(): array
    {
        $stmt = Database::connection()->prepare(
            'SELECT a.id, a.parte, a.numero, a.titulo_estrutural, a.capitulo_estrutural,
                    a.secao_estrutural, a.subsecao_estrutural, a.descricao_estrutural,
                    a.rubrica, a.caput, a.revogado, a.ordem,
                    leis.slug AS lei_slug, leis.titulo AS lei_titulo
             FROM artigos a
             INNER JOIN leis ON leis.id = a.lei_id
             ORDER BY leis.id, a.parte, a.ordem'
        );
        $stmt->execute();

        return $stmt->fetchAll();
    }

    /// Busca por palavras soltas dentro de uma lei/parte específica (ex.: só o
    /// texto permanente da Constituição). Ver `pontuarEOrdenar` pro critério
    /// de relevância.
    public static function search(int $leiId, string $parte, string $query): array
    {
        $tokens = self::tokenizar($query);
        if ($tokens === []) {
            return [];
        }

        return self::pontuarEOrdenar(self::listByLei($leiId, $parte), $tokens);
    }

    /// Mesma busca, mas em todas as leis cadastradas — usada pela aba Buscar.
    public static function searchGlobal(string $query): array
    {
        $tokens = self::tokenizar($query);
        if ($tokens === []) {
            return [];
        }

        return self::pontuarEOrdenar(self::listAll(), $tokens);
    }

    /// Pontua cada artigo pela compatibilidade com as palavras buscadas e
    /// ordena por relevância: quanto mais palavras da busca o artigo contém,
    /// mais relevante ele é; entre artigos igualmente relevantes, prevalece a
    /// ordem original da lei (e, na busca global, a ordem das leis entre si).
    private static function pontuarEOrdenar(array $artigos, array $tokens): array
    {
        if ($artigos === []) {
            return [];
        }

        $dispositivosPorArtigo = self::dispositivosPorArtigo(
            array_map(static fn (array $a) => (int) $a['id'], $artigos)
        );

        $pontuados = [];
        foreach ($artigos as $artigo) {
            $dispositivos = $dispositivosPorArtigo[(int) $artigo['id']] ?? [];
            $textoCombinado = self::normalizar(
                $artigo['caput'] . ' ' . implode(' ', array_column($dispositivos, 'texto'))
            );

            $pontuacao = self::pontuar($textoCombinado, $tokens);
            if ($pontuacao === 0) {
                continue;
            }

            // Quando a busca "bate" em algum dispositivo (parágrafo/inciso/alínea),
            // não só no caput, devolve esse trecho junto — é o que explica pro
            // usuário por que aquele artigo apareceu no resultado.
            $artigo['trecho_correspondente'] = self::trechoCorrespondente($dispositivos, $tokens);

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
    private static function dispositivosPorArtigo(array $artigoIds): array
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
    private static function trechoCorrespondente(array $dispositivos, array $tokens): ?array
    {
        $melhor = null;
        $melhorPontuacao = 0;

        foreach ($dispositivos as $dispositivo) {
            $pontuacao = self::pontuar(self::normalizar($dispositivo['texto']), $tokens);
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
    private static function pontuar(string $texto, array $tokens): int
    {
        $ocorrenciasPorToken = [];
        foreach ($tokens as $indice => $token) {
            $padrao = '/\b' . preg_quote($token, '/') . '\b/u';
            if (preg_match_all($padrao, $texto, $matches, PREG_OFFSET_CAPTURE) > 0) {
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

    private static function tokenizar(string $query): array
    {
        $normalizado = self::normalizar($query);
        $tokens = preg_split('/\s+/', trim($normalizado), -1, PREG_SPLIT_NO_EMPTY) ?: [];

        return array_values(array_unique($tokens));
    }

    /// Minúsculas e sem acento, para comparação tolerante ("Poder" == "poder" == "PODÉR").
    private static function normalizar(string $texto): string
    {
        $texto = mb_strtolower($texto, 'UTF-8');

        static $comAcento = ['á', 'à', 'â', 'ã', 'ä', 'é', 'è', 'ê', 'ë', 'í', 'ì', 'î', 'ï',
            'ó', 'ò', 'ô', 'õ', 'ö', 'ú', 'ù', 'û', 'ü', 'ç', 'ñ'];
        static $semAcento = ['a', 'a', 'a', 'a', 'a', 'e', 'e', 'e', 'e', 'i', 'i', 'i', 'i',
            'o', 'o', 'o', 'o', 'o', 'u', 'u', 'u', 'u', 'c', 'n'];

        return str_replace($comAcento, $semAcento, $texto);
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
