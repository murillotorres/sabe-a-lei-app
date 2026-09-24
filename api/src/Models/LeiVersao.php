<?php

declare(strict_types=1);

namespace App\Models;

use App\Core\Database;

/// Versões publicadas de cada lei, para o armazenamento offline do app.
///
/// Fluxo de quem edita o conteúdo: altera a lei no banco (reseed, correção
/// pontual...) e roda `php bin/publicar-versao.php <slug>`. O publicador
/// compara o banco com o último snapshot, registra o que foi inserido,
/// alterado e removido e cria a versão seguinte — ninguém escreve delta à mão.
///
/// Versões são `major.minor`: `minor` sobe a cada publicação incremental (o app
/// baixa só as mudanças); `major` sobe com `--major`, para alterações
/// estruturais, e obriga o app a baixar o livro inteiro de novo.
final class LeiVersao
{
    /// Acima disso o delta deixa de compensar: o app baixa o livro inteiro.
    public const LIMITE_DE_MUDANCAS_NO_DELTA = 300;

    public static function rotulo(array $versao): string
    {
        return $versao['major'] . '.' . $versao['minor'];
    }

    /// "1.2" => [1, 2]; `null` se não for nesse formato.
    public static function interpretar(string $texto): ?array
    {
        if (preg_match('/^(\d{1,5})\.(\d{1,5})$/', $texto, $m) !== 1) {
            return null;
        }

        return [(int) $m[1], (int) $m[2]];
    }

    public static function ultima(int $leiId): ?array
    {
        $stmt = Database::connection()->prepare(
            'SELECT id, major, minor, checksum, artigos_total
             FROM lei_versoes WHERE lei_id = :lei_id ORDER BY id DESC LIMIT 1'
        );
        $stmt->execute(['lei_id' => $leiId]);

        return $stmt->fetch() ?: null;
    }

    public static function encontrar(int $leiId, int $major, int $minor): ?array
    {
        $stmt = Database::connection()->prepare(
            'SELECT id, major, minor, checksum, artigos_total
             FROM lei_versoes WHERE lei_id = :lei_id AND major = :major AND minor = :minor LIMIT 1'
        );
        $stmt->execute(['lei_id' => $leiId, 'major' => $major, 'minor' => $minor]);

        return $stmt->fetch() ?: null;
    }

    /// Leis com versão publicada — o que o app consulta ao abrir para saber se
    /// algum livro armazenado está desatualizado. Leve de propósito: sem conteúdo.
    public static function manifesto(): array
    {
        $stmt = Database::connection()->query(
            'SELECT leis.slug, leis.titulo, v.major, v.minor, v.checksum, v.artigos_total
             FROM leis
             INNER JOIN lei_versoes v ON v.id = (
                 SELECT MAX(id) FROM lei_versoes WHERE lei_id = leis.id
             )
             ORDER BY leis.id'
        );

        return array_map(static fn (array $l) => [
            'id' => $l['slug'],
            'titulo' => $l['titulo'],
            'versao' => self::rotulo($l),
            'checksum' => $l['checksum'],
            'totalDeArtigos' => (int) $l['artigos_total'],
        ], $stmt->fetchAll());
    }

    /// Compara o banco com o último snapshot e, se houver diferença, publica a
    /// próxima versão. Com `$simular`, só calcula e devolve o resultado.
    ///
    /// @return array{
    ///   publicada: bool, versao: string|null, anterior: string|null,
    ///   inseridos: int, alterados: int, removidos: int, checksum: string, total: int
    /// }
    public static function publicar(int $leiId, bool $estrutural = false, ?string $notas = null, bool $simular = false): array
    {
        $atual = ConteudoOffline::hashesAtuais($leiId);
        $checksum = ConteudoOffline::checksumDoLivro($atual);
        $ultima = self::ultima($leiId);

        $resultado = [
            'publicada' => false,
            'versao' => $ultima !== null ? self::rotulo($ultima) : null,
            'anterior' => $ultima !== null ? self::rotulo($ultima) : null,
            'inseridos' => 0,
            'alterados' => 0,
            'removidos' => 0,
            'checksum' => $checksum,
            'total' => count($atual),
        ];

        $mudancas = [];
        if ($ultima !== null) {
            $snapshot = self::snapshot($leiId);

            foreach ($atual as $chave => $artigo) {
                if (!isset($snapshot[$chave])) {
                    $mudancas[] = [$artigo['parte'], $artigo['numero'], 'insert'];
                    $resultado['inseridos']++;
                } elseif ($snapshot[$chave] !== $artigo['hash']) {
                    $mudancas[] = [$artigo['parte'], $artigo['numero'], 'update'];
                    $resultado['alterados']++;
                }
            }
            foreach ($snapshot as $chave => $hash) {
                if (!isset($atual[$chave])) {
                    [$parte, $numero] = explode('|', $chave, 2);
                    $mudancas[] = [$parte, $numero, 'delete'];
                    $resultado['removidos']++;
                }
            }

            // Nada mudou no conteúdo — e o checksum confirma que o snapshot bate com o banco.
            if ($mudancas === [] && !$estrutural && $ultima['checksum'] === $checksum) {
                return $resultado;
            }
        }

        if ($ultima === null) {
            $major = 1;
            $minor = 0;
        } elseif ($estrutural) {
            $major = (int) $ultima['major'] + 1;
            $minor = 0;
        } else {
            $major = (int) $ultima['major'];
            $minor = (int) $ultima['minor'] + 1;
        }

        $resultado['publicada'] = !$simular;
        $resultado['versao'] = "{$major}.{$minor}";

        if ($simular) {
            return $resultado;
        }

        $pdo = Database::connection();
        $pdo->beginTransaction();
        try {
            $stmt = $pdo->prepare(
                'INSERT INTO lei_versoes (lei_id, major, minor, checksum, artigos_total, notas)
                 VALUES (:lei_id, :major, :minor, :checksum, :total, :notas)'
            );
            $stmt->execute([
                'lei_id' => $leiId, 'major' => $major, 'minor' => $minor,
                'checksum' => $checksum, 'total' => count($atual), 'notas' => $notas,
            ]);
            $versaoId = (int) $pdo->lastInsertId();

            $inserirMudanca = $pdo->prepare(
                'INSERT INTO lei_mudancas (versao_id, parte, numero, tipo) VALUES (?, ?, ?, ?)'
            );
            foreach ($mudancas as [$parte, $numero, $tipo]) {
                $inserirMudanca->execute([$versaoId, $parte, $numero, $tipo]);
            }

            // O snapshot passa a ser o estado recém-publicado.
            $pdo->prepare('DELETE FROM lei_snapshot WHERE lei_id = ?')->execute([$leiId]);
            $inserirSnapshot = $pdo->prepare(
                'INSERT INTO lei_snapshot (lei_id, parte, numero, hash) VALUES (?, ?, ?, ?)'
            );
            foreach ($atual as $artigo) {
                $inserirSnapshot->execute([$leiId, $artigo['parte'], $artigo['numero'], $artigo['hash']]);
            }

            $pdo->commit();
        } catch (\Throwable $e) {
            $pdo->rollBack();
            throw $e;
        }

        return $resultado;
    }

    /// Mudanças entre a versão `$de` e a última, já consolidadas por artigo
    /// (várias edições do mesmo artigo viram uma) e com o conteúdo atual dos
    /// artigos inseridos/alterados. `requerDownloadCompleto` quando o delta não
    /// é viável: versão de origem desconhecida, mudança estrutural (major) ou
    /// alteração grande demais.
    public static function atualizacoes(int $leiId, array $de): array
    {
        $ultima = self::ultima($leiId);
        $origem = self::encontrar($leiId, $de[0], $de[1]);

        $resposta = [
            'deVersao' => "{$de[0]}.{$de[1]}",
            'paraVersao' => $ultima !== null ? self::rotulo($ultima) : null,
            'checksum' => $ultima['checksum'] ?? null,
            'requerDownloadCompleto' => false,
            'mudancas' => [],
        ];

        if ($ultima === null || $origem === null || (int) $origem['major'] !== (int) $ultima['major']) {
            $resposta['requerDownloadCompleto'] = true;

            return $resposta;
        }

        if ((int) $origem['id'] === (int) $ultima['id']) {
            return $resposta;
        }

        $stmt = Database::connection()->prepare(
            'SELECT m.parte, m.numero, m.tipo
             FROM lei_mudancas m
             INNER JOIN lei_versoes v ON v.id = m.versao_id
             WHERE v.lei_id = :lei_id AND v.id > :origem_id AND v.id <= :ultima_id
             ORDER BY v.id, m.id'
        );
        $stmt->execute(['lei_id' => $leiId, 'origem_id' => $origem['id'], 'ultima_id' => $ultima['id']]);

        // Primeiro e último tipo de cada artigo no intervalo: é o que diz se ele
        // existia na versão de origem e se ainda existe na de destino.
        $extremos = [];
        foreach ($stmt->fetchAll() as $linha) {
            $chave = $linha['parte'] . '|' . $linha['numero'];
            $extremos[$chave] ??= ['parte' => $linha['parte'], 'numero' => $linha['numero'], 'primeiro' => $linha['tipo']];
            $extremos[$chave]['ultimo'] = $linha['tipo'];
        }

        $consolidadas = [];
        foreach ($extremos as $e) {
            $existia = $e['primeiro'] !== 'insert';
            $existe = $e['ultimo'] !== 'delete';

            $tipo = match (true) {
                $existia && $existe => 'update',
                !$existia && $existe => 'insert',
                $existia && !$existe => 'delete',
                default => null, // criado e removido dentro do intervalo: o app nunca soube dele
            };

            if ($tipo !== null) {
                $consolidadas[] = ['tipo' => $tipo, 'parte' => $e['parte'], 'numero' => $e['numero']];
            }
        }

        if (count($consolidadas) > self::LIMITE_DE_MUDANCAS_NO_DELTA) {
            $resposta['requerDownloadCompleto'] = true;

            return $resposta;
        }

        $chavesComConteudo = [];
        foreach ($consolidadas as $m) {
            if ($m['tipo'] !== 'delete') {
                $chavesComConteudo[] = [$m['parte'], $m['numero']];
            }
        }

        $conteudo = [];
        foreach (ConteudoOffline::porChaves($leiId, $chavesComConteudo) as $artigo) {
            $conteudo[$artigo['parte'] . '|' . $artigo['numero']] = $artigo;
        }

        foreach ($consolidadas as $m) {
            if ($m['tipo'] === 'delete') {
                $resposta['mudancas'][] = $m;
                continue;
            }

            $artigo = $conteudo[$m['parte'] . '|' . $m['numero']] ?? null;
            if ($artigo === null) {
                // Publicado, mas já não está no banco: só o download completo resolve.
                $resposta['requerDownloadCompleto'] = true;
                $resposta['mudancas'] = [];

                return $resposta;
            }

            $resposta['mudancas'][] = $m + ['artigo' => $artigo];
        }

        return $resposta;
    }

    /// `"parte|numero" => hash` do último conteúdo publicado.
    private static function snapshot(int $leiId): array
    {
        $stmt = Database::connection()->prepare('SELECT parte, numero, hash FROM lei_snapshot WHERE lei_id = :lei_id');
        $stmt->execute(['lei_id' => $leiId]);

        $snapshot = [];
        foreach ($stmt->fetchAll() as $linha) {
            $snapshot[$linha['parte'] . '|' . $linha['numero']] = $linha['hash'];
        }

        return $snapshot;
    }
}
