<?php

declare(strict_types=1);

namespace App\Models;

use App\Core\Database;
use DateTimeImmutable;
use DateTimeZone;
use PDO;
use Throwable;

/// Grifos e anotações do usuário (migrations/002). Toda a troca com o app passa
/// por `sincronizar`: o app manda o que mudou no aparelho e recebe o que mudou
/// no servidor desde a última revisão que ele conhece — numa transação só.
///
/// Regras:
/// - o id é um UUID do app; reenviar o mesmo registro só o atualiza (nunca duplica);
/// - conflito entre aparelhos: vence o `alteradoEm` mais recente;
/// - excluir marca `excluido_em` (o registro continua, para a exclusão chegar
///   aos outros aparelhos); excluir um grifo exclui as notas dele;
/// - cada registro gravado recebe a próxima `revisao` do usuário.
final class Estudo
{
    public const CORES = ['amarelo', 'verde', 'azul', 'vermelho', 'roxo'];

    /// Limite de registros por chamada — o app envia em lotes menores que isso.
    public const LIMITE_POR_LOTE = 500;

    private const UUID = '/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/';

    /// @param array<int, mixed> $grifos
    /// @param array<int, mixed> $anotacoes
    /// @return array{revisao: int, completo: bool, grifos: array, anotacoes: array, rejeitados: array}
    public static function sincronizar(int $userId, int $desde, array $grifos, array $anotacoes): array
    {
        $db = Database::connection();
        $db->beginTransaction();

        try {
            // Trava a revisão do usuário: duas sincronizações simultâneas (dois
            // aparelhos) passam uma de cada vez.
            $db->prepare('INSERT IGNORE INTO estudo_revisoes (user_id, revisao) VALUES (:u, 0)')
                ->execute(['u' => $userId]);
            $stmt = $db->prepare('SELECT revisao FROM estudo_revisoes WHERE user_id = :u FOR UPDATE');
            $stmt->execute(['u' => $userId]);
            $revisao = (int) $stmt->fetchColumn();

            // Desde uma revisão que o servidor não conhece (banco recriado): manda
            // tudo e o app troca o que tem pelo que vier.
            $completo = $desde <= 0 || $desde > $revisao;
            if ($completo) {
                $desde = 0;
            }

            $rejeitados = [];
            // Registros enviados que perderam o conflito: voltam na resposta mesmo
            // que não tenham mudado desde `desde`, para o app ficar com a versão vencedora.
            $devolverGrifos = [];
            $devolverAnotacoes = [];

            foreach ($grifos as $bruto) {
                $grifo = self::validarGrifo($bruto);
                if ($grifo === null) {
                    $rejeitados[] = is_array($bruto) ? (string) ($bruto['id'] ?? '') : '';
                    continue;
                }
                $resultado = self::gravarGrifo($db, $userId, $grifo, $revisao);
                if ($resultado === 'rejeitado') {
                    $rejeitados[] = $grifo['id'];
                } elseif ($resultado === 'perdeu') {
                    $devolverGrifos[] = $grifo['id'];
                }
            }

            foreach ($anotacoes as $bruto) {
                $anotacao = self::validarAnotacao($bruto);
                if ($anotacao === null) {
                    $rejeitados[] = is_array($bruto) ? (string) ($bruto['id'] ?? '') : '';
                    continue;
                }
                $resultado = self::gravarAnotacao($db, $userId, $anotacao, $revisao);
                if ($resultado === 'rejeitado') {
                    $rejeitados[] = $anotacao['id'];
                } elseif ($resultado === 'perdeu') {
                    $devolverAnotacoes[] = $anotacao['id'];
                }
            }

            $db->prepare('UPDATE estudo_revisoes SET revisao = :r WHERE user_id = :u')
                ->execute(['r' => $revisao, 'u' => $userId]);

            $resposta = [
                'revisao' => $revisao,
                'completo' => $completo,
                'grifos' => array_map(self::formatarGrifo(...), self::mudancas($db, 'grifos', $userId, $desde, $devolverGrifos)),
                'anotacoes' => array_map(self::formatarAnotacao(...), self::mudancas($db, 'anotacoes', $userId, $desde, $devolverAnotacoes)),
                'rejeitados' => array_values(array_filter(array_unique($rejeitados))),
            ];

            $db->commit();

            return $resposta;
        } catch (Throwable $e) {
            $db->rollBack();
            throw $e;
        }
    }

    // MARK: Gravação

    /// @return 'gravado'|'perdeu'|'rejeitado'
    private static function gravarGrifo(PDO $db, int $userId, array $g, int &$revisao): string
    {
        $leiId = self::leiDoArtigo($db, $g['artigoId']);
        if ($leiId === null) {
            return 'rejeitado';
        }

        $atual = self::existente($db, 'grifos', $g['id']);
        if ($atual !== null && (int) $atual['user_id'] !== $userId) {
            return 'rejeitado';
        }
        if ($atual !== null && $atual['alterado_em'] > $g['alteradoEm']) {
            return 'perdeu';
        }

        $revisao++;
        $dados = [
            'id' => $g['id'], 'user_id' => $userId, 'lei_id' => $leiId, 'artigo_id' => $g['artigoId'],
            'dispositivo_id' => $g['dispositivoId'], 'dispositivo_chave' => $g['dispositivoChave'],
            'dispositivo_ordem' => $g['dispositivoOrdem'], 'trecho' => $g['trecho'],
            'prefixo' => $g['prefixo'], 'sufixo' => $g['sufixo'], 'inicio' => $g['inicio'], 'fim' => $g['fim'],
            'texto_original' => $g['textoOriginal'], 'cor' => $g['cor'], 'versao' => $g['versao'],
            'criado_em' => $g['criadoEm'], 'alterado_em' => $g['alteradoEm'],
            'excluido_em' => $g['excluido'] ? $g['alteradoEm'] : null, 'revisao' => $revisao,
        ];

        if ($atual === null) {
            $db->prepare(
                'INSERT INTO grifos (id, user_id, lei_id, artigo_id, dispositivo_id, dispositivo_chave,
                    dispositivo_ordem, trecho, prefixo, sufixo, inicio, fim, texto_original, cor, versao,
                    criado_em, alterado_em, excluido_em, revisao)
                 VALUES (:id, :user_id, :lei_id, :artigo_id, :dispositivo_id, :dispositivo_chave,
                    :dispositivo_ordem, :trecho, :prefixo, :sufixo, :inicio, :fim, :texto_original, :cor, :versao,
                    :criado_em, :alterado_em, :excluido_em, :revisao)'
            )->execute($dados);
        } else {
            // criado_em e user_id não mudam depois de criados.
            unset($dados['criado_em'], $dados['user_id']);
            $db->prepare(
                'UPDATE grifos SET lei_id = :lei_id, artigo_id = :artigo_id, dispositivo_id = :dispositivo_id,
                    dispositivo_chave = :dispositivo_chave, dispositivo_ordem = :dispositivo_ordem,
                    trecho = :trecho, prefixo = :prefixo, sufixo = :sufixo, inicio = :inicio, fim = :fim,
                    texto_original = :texto_original, cor = :cor, versao = :versao,
                    alterado_em = :alterado_em, excluido_em = :excluido_em, revisao = :revisao
                 WHERE id = :id'
            )->execute($dados);
        }

        // Grifo excluído leva as notas dele junto.
        if ($g['excluido']) {
            $notas = $db->prepare(
                'SELECT id FROM anotacoes WHERE user_id = :u AND grifo_id = :g AND excluido_em IS NULL FOR UPDATE'
            );
            $notas->execute(['u' => $userId, 'g' => $g['id']]);
            foreach ($notas->fetchAll(PDO::FETCH_COLUMN) as $notaId) {
                $revisao++;
                $db->prepare(
                    'UPDATE anotacoes SET excluido_em = :e, alterado_em = GREATEST(alterado_em, :e2), revisao = :r WHERE id = :id'
                )->execute(['e' => $g['alteradoEm'], 'e2' => $g['alteradoEm'], 'r' => $revisao, 'id' => $notaId]);
            }
        }

        return 'gravado';
    }

    /// @return 'gravado'|'perdeu'|'rejeitado'
    private static function gravarAnotacao(PDO $db, int $userId, array $a, int &$revisao): string
    {
        $leiId = self::leiDoArtigo($db, $a['artigoId']);
        if ($leiId === null) {
            return 'rejeitado';
        }

        $atual = self::existente($db, 'anotacoes', $a['id']);
        if ($atual !== null && (int) $atual['user_id'] !== $userId) {
            return 'rejeitado';
        }
        if ($atual !== null && $atual['alterado_em'] > $a['alteradoEm']) {
            return 'perdeu';
        }

        $revisao++;
        $dados = [
            'id' => $a['id'], 'user_id' => $userId, 'lei_id' => $leiId, 'artigo_id' => $a['artigoId'],
            'grifo_id' => $a['grifoId'], 'conteudo' => $a['conteudo'],
            'criado_em' => $a['criadoEm'], 'alterado_em' => $a['alteradoEm'],
            'excluido_em' => $a['excluido'] ? $a['alteradoEm'] : null, 'revisao' => $revisao,
        ];

        if ($atual === null) {
            $db->prepare(
                'INSERT INTO anotacoes (id, user_id, lei_id, artigo_id, grifo_id, conteudo,
                    criado_em, alterado_em, excluido_em, revisao)
                 VALUES (:id, :user_id, :lei_id, :artigo_id, :grifo_id, :conteudo,
                    :criado_em, :alterado_em, :excluido_em, :revisao)'
            )->execute($dados);
        } else {
            unset($dados['criado_em'], $dados['user_id']);
            $db->prepare(
                'UPDATE anotacoes SET lei_id = :lei_id, artigo_id = :artigo_id, grifo_id = :grifo_id,
                    conteudo = :conteudo, alterado_em = :alterado_em, excluido_em = :excluido_em, revisao = :revisao
                 WHERE id = :id'
            )->execute($dados);
        }

        return 'gravado';
    }

    private static function existente(PDO $db, string $tabela, string $id): ?array
    {
        $stmt = $db->prepare("SELECT user_id, alterado_em FROM {$tabela} WHERE id = :id FOR UPDATE");
        $stmt->execute(['id' => $id]);

        return $stmt->fetch() ?: null;
    }

    private static function leiDoArtigo(PDO $db, int $artigoId): ?int
    {
        static $cache = [];
        if (!array_key_exists($artigoId, $cache)) {
            $stmt = $db->prepare('SELECT lei_id FROM artigos WHERE id = :id');
            $stmt->execute(['id' => $artigoId]);
            $leiId = $stmt->fetchColumn();
            $cache[$artigoId] = $leiId === false ? null : (int) $leiId;
        }

        return $cache[$artigoId];
    }

    // MARK: Leitura

    /// Registros com revisão posterior a `desde`, mais os listados em `ids`.
    /// Numa carga completa (`desde` 0), os excluídos ficam de fora.
    private static function mudancas(PDO $db, string $tabela, int $userId, int $desde, array $ids): array
    {
        $artigo = 'a.parte AS a_parte, a.numero AS a_numero, a.rubrica AS a_rubrica, a.ordem AS a_ordem,
            leis.slug AS lei_slug';
        $condicao = $desde === 0 ? 't.revisao > 0 AND t.excluido_em IS NULL' : 't.revisao > :desde';
        $parametros = ['u' => $userId];
        if ($desde !== 0) {
            $parametros['desde'] = $desde;
        }

        if ($ids !== []) {
            $marcadores = [];
            foreach (array_values($ids) as $i => $id) {
                $marcadores[] = ":id{$i}";
                $parametros["id{$i}"] = $id;
            }
            $condicao = "({$condicao} OR t.id IN (" . implode(', ', $marcadores) . '))';
        }

        $stmt = $db->prepare(
            "SELECT t.*, {$artigo}
             FROM {$tabela} t
             LEFT JOIN artigos a ON a.id = t.artigo_id
             LEFT JOIN leis ON leis.id = t.lei_id
             WHERE t.user_id = :u AND {$condicao}
             ORDER BY t.revisao"
        );
        $stmt->execute($parametros);

        return $stmt->fetchAll();
    }

    private static function formatarGrifo(array $g): array
    {
        return [
            'id' => $g['id'],
            'artigoId' => (int) $g['artigo_id'],
            'dispositivoId' => $g['dispositivo_id'] !== null ? (int) $g['dispositivo_id'] : null,
            'dispositivoChave' => $g['dispositivo_chave'],
            'dispositivoOrdem' => (int) $g['dispositivo_ordem'],
            'trecho' => $g['trecho'],
            'prefixo' => $g['prefixo'],
            'sufixo' => $g['sufixo'],
            'inicio' => (int) $g['inicio'],
            'fim' => (int) $g['fim'],
            'textoOriginal' => $g['texto_original'],
            'cor' => $g['cor'],
            'versao' => $g['versao'],
            'criadoEm' => self::paraIso($g['criado_em']),
            'alteradoEm' => self::paraIso($g['alterado_em']),
            'excluido' => $g['excluido_em'] !== null,
            'artigo' => self::resumoDoArtigo($g),
        ];
    }

    private static function formatarAnotacao(array $a): array
    {
        return [
            'id' => $a['id'],
            'artigoId' => (int) $a['artigo_id'],
            'grifoId' => $a['grifo_id'],
            'conteudo' => $a['conteudo'],
            'criadoEm' => self::paraIso($a['criado_em']),
            'alteradoEm' => self::paraIso($a['alterado_em']),
            'excluido' => $a['excluido_em'] !== null,
            'artigo' => self::resumoDoArtigo($a),
        ];
    }

    /// O suficiente para "Minhas anotações" mostrar e ordenar o registro sem
    /// abrir o artigo. Nulo se o artigo não existir mais.
    private static function resumoDoArtigo(array $linha): ?array
    {
        if ($linha['a_numero'] === null) {
            return null;
        }

        return [
            'leiSlug' => $linha['lei_slug'],
            'parte' => $linha['a_parte'],
            'numero' => $linha['a_numero'],
            'rubrica' => $linha['a_rubrica'],
            'ordem' => (int) $linha['a_ordem'],
        ];
    }

    // MARK: Validação

    private static function validarGrifo(mixed $g): ?array
    {
        if (!is_array($g)) {
            return null;
        }

        $id = self::uuid($g['id'] ?? null);
        $artigoId = self::inteiro($g['artigoId'] ?? null);
        $chave = self::texto($g['dispositivoChave'] ?? null, 120);
        $trecho = self::texto($g['trecho'] ?? null, 20000);
        $original = self::texto($g['textoOriginal'] ?? null, 60000);
        $inicio = self::inteiro($g['inicio'] ?? null, 0);
        $fim = self::inteiro($g['fim'] ?? null, 1);
        $criado = self::data($g['criadoEm'] ?? null);
        $alterado = self::data($g['alteradoEm'] ?? null);
        $cor = $g['cor'] ?? null;

        if ($id === null || $artigoId === null || $chave === null || $chave === '' || $trecho === null
            || $trecho === '' || $original === null || $inicio === null || $fim === null || $fim <= $inicio
            || $criado === null || $alterado === null || ($cor !== null && !in_array($cor, self::CORES, true))) {
            return null;
        }

        $dispositivoId = $g['dispositivoId'] ?? null;
        $versao = $g['versao'] ?? null;

        return [
            'id' => $id,
            'artigoId' => $artigoId,
            'dispositivoId' => is_int($dispositivoId) && $dispositivoId > 0 ? $dispositivoId : null,
            'dispositivoChave' => $chave,
            'dispositivoOrdem' => self::inteiro($g['dispositivoOrdem'] ?? 0, 0) ?? 0,
            'trecho' => $trecho,
            'prefixo' => mb_substr(is_string($g['prefixo'] ?? null) ? $g['prefixo'] : '', 0, 255),
            'sufixo' => mb_substr(is_string($g['sufixo'] ?? null) ? $g['sufixo'] : '', 0, 255),
            'inicio' => $inicio,
            'fim' => $fim,
            'textoOriginal' => $original,
            'cor' => $cor,
            'versao' => is_string($versao) ? mb_substr($versao, 0, 20) : null,
            'criadoEm' => $criado,
            'alteradoEm' => $alterado,
            'excluido' => ($g['excluido'] ?? false) === true,
        ];
    }

    private static function validarAnotacao(mixed $a): ?array
    {
        if (!is_array($a)) {
            return null;
        }

        $id = self::uuid($a['id'] ?? null);
        $artigoId = self::inteiro($a['artigoId'] ?? null);
        $conteudo = self::texto($a['conteudo'] ?? null, 20000);
        $criado = self::data($a['criadoEm'] ?? null);
        $alterado = self::data($a['alteradoEm'] ?? null);
        $grifoBruto = $a['grifoId'] ?? null;
        $grifoId = $grifoBruto === null ? null : self::uuid($grifoBruto);

        if ($id === null || $artigoId === null || $conteudo === null || $criado === null || $alterado === null
            || ($grifoBruto !== null && $grifoId === null)) {
            return null;
        }

        return [
            'id' => $id,
            'artigoId' => $artigoId,
            'grifoId' => $grifoId,
            'conteudo' => $conteudo,
            'criadoEm' => $criado,
            'alteradoEm' => $alterado,
            'excluido' => ($a['excluido'] ?? false) === true,
        ];
    }

    private static function uuid(mixed $valor): ?string
    {
        if (!is_string($valor)) {
            return null;
        }
        $valor = strtolower($valor);

        return preg_match(self::UUID, $valor) === 1 ? $valor : null;
    }

    private static function inteiro(mixed $valor, int $minimo = 1): ?int
    {
        return is_int($valor) && $valor >= $minimo ? $valor : null;
    }

    private static function texto(mixed $valor, int $maximo): ?string
    {
        return is_string($valor) && mb_strlen($valor) <= $maximo ? $valor : null;
    }

    /// Data ISO 8601 do app → DATETIME(3) em UTC. Nunca no futuro: um relógio
    /// adiantado não pode fazer uma edição vencer as próximas indefinidamente.
    private static function data(mixed $valor): ?string
    {
        if (!is_string($valor)) {
            return null;
        }
        try {
            $data = new DateTimeImmutable($valor);
        } catch (Throwable) {
            return null;
        }
        $utc = new DateTimeZone('UTC');
        $data = $data->setTimezone($utc);
        $agora = new DateTimeImmutable('now', $utc);

        return ($data > $agora ? $agora : $data)->format('Y-m-d H:i:s.v');
    }

    private static function paraIso(string $data): string
    {
        return (new DateTimeImmutable($data, new DateTimeZone('UTC')))->format('Y-m-d\TH:i:s.v\Z');
    }
}
