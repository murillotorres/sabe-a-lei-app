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
                    secao_estrutural, subsecao_estrutural, caput, revogado, ordem
             FROM artigos
             WHERE lei_id = :lei_id AND parte = :parte
             ORDER BY ordem'
        );
        $stmt->execute(['lei_id' => $leiId, 'parte' => $parte]);

        return $stmt->fetchAll();
    }

    /// Busca por palavras soltas, olhando não só o caput como os dispositivos
    /// (parágrafos/incisos/alíneas) do artigo. Ordena por "compatibilidade":
    /// quanto mais palavras da busca o artigo contém, mais relevante ele é;
    /// entre artigos igualmente relevantes, prevalece a ordem original da lei.
    public static function search(int $leiId, string $parte, string $query): array
    {
        $tokens = self::tokenizar($query);
        if ($tokens === []) {
            return [];
        }

        $artigos = self::listByLei($leiId, $parte);
        if ($artigos === []) {
            return [];
        }

        $textosDispositivos = self::textosDispositivosPorArtigo(
            array_map(static fn (array $a) => (int) $a['id'], $artigos)
        );

        $pontuados = [];
        foreach ($artigos as $artigo) {
            $texto = self::normalizar($artigo['caput'] . ' ' . ($textosDispositivos[(int) $artigo['id']] ?? ''));

            $pontuacao = self::pontuar($texto, $tokens);
            if ($pontuacao === 0) {
                continue;
            }

            $pontuados[] = ['artigo' => $artigo, 'pontuacao' => $pontuacao];
        }

        usort($pontuados, static function (array $a, array $b): int {
            return $a['pontuacao'] !== $b['pontuacao']
                ? $b['pontuacao'] <=> $a['pontuacao']
                : $a['artigo']['ordem'] <=> $b['artigo']['ordem'];
        });

        return array_map(static fn (array $p) => $p['artigo'], $pontuados);
    }

    /// Mapa artigo_id => texto concatenado de todos os seus dispositivos.
    private static function textosDispositivosPorArtigo(array $artigoIds): array
    {
        if ($artigoIds === []) {
            return [];
        }

        $placeholders = implode(',', array_fill(0, count($artigoIds), '?'));
        $stmt = Database::connection()->prepare(
            "SELECT artigo_id, texto FROM artigo_dispositivos WHERE artigo_id IN ($placeholders)"
        );
        $stmt->execute($artigoIds);

        $textos = [];
        foreach ($stmt->fetchAll() as $row) {
            $id = (int) $row['artigo_id'];
            $textos[$id] = ($textos[$id] ?? '') . ' ' . $row['texto'];
        }

        return $textos;
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
}
