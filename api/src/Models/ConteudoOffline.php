<?php

declare(strict_types=1);

namespace App\Models;

use App\Core\Database;
use PDO;

/// Conteúdo de uma lei no formato consumido pelo armazenamento offline do app:
/// cada artigo já com seus dispositivos (parágrafos/incisos/alíneas) e um hash
/// do conteúdo. O hash é o que permite descobrir, sem comparar texto, quais
/// artigos mudaram entre duas versões (ver `LeiVersao`).
final class ConteudoOffline
{
    /// "Página" de artigos completos, na ordem de leitura (parte, ordem). O
    /// livro é baixado por páginas para nenhuma resposta ficar grande demais.
    public static function pagina(int $leiId, int $limit, int $offset): array
    {
        $stmt = Database::connection()->prepare(
            'SELECT id, parte, numero, titulo_estrutural, capitulo_estrutural,
                    secao_estrutural, subsecao_estrutural, descricao_estrutural,
                    rubrica, caput, revogado, ordem
             FROM artigos
             WHERE lei_id = :lei_id
             ORDER BY parte, ordem
             LIMIT :limit OFFSET :offset'
        );
        $stmt->bindValue(':lei_id', $leiId, PDO::PARAM_INT);
        $stmt->bindValue(':limit', $limit, PDO::PARAM_INT);
        $stmt->bindValue(':offset', $offset, PDO::PARAM_INT);
        $stmt->execute();

        return self::comDispositivos($stmt->fetchAll());
    }

    /// Artigos pelas chaves naturais `[parte, numero]` — usado pelo delta, que
    /// identifica o que mudou por parte+numero e não pelo id.
    public static function porChaves(int $leiId, array $chaves): array
    {
        if ($chaves === []) {
            return [];
        }

        $condicoes = implode(' OR ', array_fill(0, count($chaves), '(parte = ? AND numero = ?)'));
        $parametros = [$leiId];
        foreach ($chaves as [$parte, $numero]) {
            $parametros[] = $parte;
            $parametros[] = $numero;
        }

        $stmt = Database::connection()->prepare(
            "SELECT id, parte, numero, titulo_estrutural, capitulo_estrutural,
                    secao_estrutural, subsecao_estrutural, descricao_estrutural,
                    rubrica, caput, revogado, ordem
             FROM artigos
             WHERE lei_id = ? AND ($condicoes)
             ORDER BY parte, ordem"
        );
        $stmt->execute($parametros);

        return self::comDispositivos($stmt->fetchAll());
    }

    /// Estado atual da lei no banco: `"parte|numero" => [parte, numero, ordem, hash]`
    /// para cada artigo. É a base tanto do checksum do livro quanto da
    /// comparação com o último snapshot publicado.
    public static function hashesAtuais(int $leiId): array
    {
        $stmt = Database::connection()->prepare(
            'SELECT id, parte, numero, titulo_estrutural, capitulo_estrutural,
                    secao_estrutural, subsecao_estrutural, descricao_estrutural,
                    rubrica, caput, revogado, ordem
             FROM artigos
             WHERE lei_id = :lei_id
             ORDER BY parte, ordem'
        );
        $stmt->execute(['lei_id' => $leiId]);
        $artigos = $stmt->fetchAll();

        $dispositivos = self::dispositivosPorArtigo(array_map(static fn (array $a) => (int) $a['id'], $artigos));

        $hashes = [];
        foreach ($artigos as $artigo) {
            $hashes[$artigo['parte'] . '|' . $artigo['numero']] = [
                'parte' => $artigo['parte'],
                'numero' => $artigo['numero'],
                'ordem' => (int) $artigo['ordem'],
                'hash' => self::hash($artigo, $dispositivos[(int) $artigo['id']] ?? []),
            ];
        }

        return $hashes;
    }

    /// SHA-256 do livro: um hash por artigo (parte|ordem|numero|hash), na ordem
    /// de leitura. O app recalcula o mesmo valor a partir do que guardou — se
    /// não bater, o conteúdo local está inconsistente e é baixado de novo.
    /// A ordenação e o formato daqui precisam ficar idênticos aos do app.
    public static function checksumDoLivro(array $hashes): string
    {
        $itens = array_values($hashes);
        usort($itens, static function (array $a, array $b): int {
            $porParte = strcmp($a['parte'], $b['parte']);
            if ($porParte !== 0) {
                return $porParte;
            }

            $porOrdem = $a['ordem'] <=> $b['ordem'];

            return $porOrdem !== 0 ? $porOrdem : strcmp($a['numero'], $b['numero']);
        });

        $linhas = array_map(
            static fn (array $i) => "{$i['parte']}|{$i['ordem']}|{$i['numero']}|{$i['hash']}",
            $itens
        );

        return hash('sha256', implode("\n", $linhas));
    }

    /// Hash do conteúdo de um artigo (campos + dispositivos), sem o id — o id é
    /// identidade, não conteúdo. Só o servidor calcula; o app apenas o guarda.
    public static function hash(array $artigo, array $dispositivos): string
    {
        $conteudo = [
            $artigo['parte'],
            $artigo['numero'],
            $artigo['titulo_estrutural'],
            $artigo['capitulo_estrutural'],
            $artigo['secao_estrutural'],
            $artigo['subsecao_estrutural'],
            $artigo['descricao_estrutural'],
            $artigo['rubrica'],
            $artigo['caput'],
            (int) $artigo['revogado'],
            (int) $artigo['ordem'],
            array_map(static fn (array $d) => [
                (int) $d['id'],
                $d['parent_id'] !== null ? (int) $d['parent_id'] : null,
                $d['tipo'],
                $d['rotulo'],
                $d['texto'],
                (int) $d['nivel'],
                (int) $d['revogado'],
                (int) $d['ordem'],
            ], $dispositivos),
        ];

        return sha1((string) json_encode($conteudo, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES));
    }

    /// Anexa dispositivos e hash a cada artigo e devolve no formato da API.
    private static function comDispositivos(array $artigos): array
    {
        $dispositivos = self::dispositivosPorArtigo(array_map(static fn (array $a) => (int) $a['id'], $artigos));

        return array_map(function (array $artigo) use ($dispositivos): array {
            $doArtigo = $dispositivos[(int) $artigo['id']] ?? [];

            return Artigo::formatar($artigo) + [
                'hash' => self::hash($artigo, $doArtigo),
                'dispositivos' => array_map(static fn (array $d) => [
                    'id' => (int) $d['id'],
                    'parentId' => $d['parent_id'] !== null ? (int) $d['parent_id'] : null,
                    'tipo' => $d['tipo'],
                    'rotulo' => $d['rotulo'],
                    'texto' => $d['texto'],
                    'nivel' => (int) $d['nivel'],
                    'revogado' => (bool) $d['revogado'],
                    'ordem' => (int) $d['ordem'],
                ], $doArtigo),
            ];
        }, $artigos);
    }

    /// Mapa artigo_id => dispositivos completos, em ordem.
    private static function dispositivosPorArtigo(array $artigoIds): array
    {
        if ($artigoIds === []) {
            return [];
        }

        $porArtigo = [];
        // Em blocos pra não estourar o limite de placeholders em livros grandes.
        foreach (array_chunk($artigoIds, 500) as $bloco) {
            $placeholders = implode(',', array_fill(0, count($bloco), '?'));
            $stmt = Database::connection()->prepare(
                "SELECT id, artigo_id, parent_id, tipo, rotulo, texto, nivel, revogado, ordem
                 FROM artigo_dispositivos
                 WHERE artigo_id IN ($placeholders)
                 ORDER BY artigo_id, ordem"
            );
            $stmt->execute($bloco);

            foreach ($stmt->fetchAll() as $linha) {
                $porArtigo[(int) $linha['artigo_id']][] = $linha;
            }
        }

        return $porArtigo;
    }
}
