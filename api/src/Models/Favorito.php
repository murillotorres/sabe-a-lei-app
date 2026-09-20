<?php

declare(strict_types=1);

namespace App\Models;

use App\Core\Database;

/// Um artigo inteiro ou um parágrafo específico marcado como favorito por um
/// usuário. `dispositivo_id` nulo significa "o artigo inteiro"; quando
/// presente, sempre aponta para um dispositivo do tipo 'paragrafo' — a
/// validação de que é mesmo um parágrafo (não inciso/alínea) fica no
/// controller, que já precisa carregar o dispositivo pra conferir o dono.
final class Favorito
{
    // f.id vai como favorito_id (não "id") pra não colidir com a.id: o
    // resultado é passado direto pra Artigo::formatar(), que espera 'id'
    // como o id do artigo.
    private const SELECT_BASE = 'SELECT f.id AS favorito_id, f.dispositivo_id,
            a.id, a.parte, a.numero, a.titulo_estrutural, a.capitulo_estrutural,
            a.secao_estrutural, a.subsecao_estrutural, a.caput, a.revogado, a.ordem,
            leis.slug AS lei_slug, leis.titulo AS lei_titulo,
            d.id AS d_id, d.tipo AS d_tipo, d.rotulo AS d_rotulo, d.texto AS d_texto
        FROM favoritos f
        INNER JOIN artigos a ON a.id = f.artigo_id
        INNER JOIN leis ON leis.id = a.lei_id
        LEFT JOIN artigo_dispositivos d ON d.id = f.dispositivo_id';

    public static function listarPorUsuario(int $userId): array
    {
        $stmt = Database::connection()->prepare(
            self::SELECT_BASE . ' WHERE f.user_id = :user_id ORDER BY f.created_at DESC, f.id DESC'
        );
        $stmt->execute(['user_id' => $userId]);

        return $stmt->fetchAll();
    }

    public static function buscar(int $id, int $userId): ?array
    {
        $stmt = Database::connection()->prepare(
            self::SELECT_BASE . ' WHERE f.id = :id AND f.user_id = :user_id LIMIT 1'
        );
        $stmt->execute(['id' => $id, 'user_id' => $userId]);

        return $stmt->fetch() ?: null;
    }

    /// Id do favorito existente para esse (artigo, dispositivo), ou null.
    /// Usa `<=>` (comparação nula-segura do MySQL) porque dispositivo_id pode
    /// ser NULL — "=" nunca bate com NULL, mesmo quando os dois lados são NULL.
    public static function existenteId(int $userId, int $artigoId, ?int $dispositivoId): ?int
    {
        $stmt = Database::connection()->prepare(
            'SELECT id FROM favoritos
             WHERE user_id = :user_id AND artigo_id = :artigo_id AND dispositivo_id <=> :dispositivo_id
             LIMIT 1'
        );
        $stmt->execute(['user_id' => $userId, 'artigo_id' => $artigoId, 'dispositivo_id' => $dispositivoId]);

        $row = $stmt->fetch();

        return $row === false ? null : (int) $row['id'];
    }

    public static function criar(int $userId, int $artigoId, ?int $dispositivoId): int
    {
        $stmt = Database::connection()->prepare(
            'INSERT INTO favoritos (user_id, artigo_id, dispositivo_id) VALUES (:user_id, :artigo_id, :dispositivo_id)'
        );
        $stmt->execute(['user_id' => $userId, 'artigo_id' => $artigoId, 'dispositivo_id' => $dispositivoId]);

        return (int) Database::connection()->lastInsertId();
    }

    public static function remover(int $id, int $userId): bool
    {
        $stmt = Database::connection()->prepare(
            'DELETE FROM favoritos WHERE id = :id AND user_id = :user_id'
        );
        $stmt->execute(['id' => $id, 'user_id' => $userId]);

        return $stmt->rowCount() > 0;
    }
}
