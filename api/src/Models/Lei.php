<?php

declare(strict_types=1);

namespace App\Models;

use App\Core\Database;

final class Lei
{
    public static function byCategoria(string $categoriaSlug): array
    {
        $stmt = Database::connection()->prepare(
            'SELECT leis.id, leis.slug, leis.titulo, leis.descricao, leis.fonte_url
             FROM leis
             INNER JOIN categorias ON categorias.id = leis.categoria_id
             WHERE categorias.slug = :slug
             ORDER BY leis.titulo'
        );
        $stmt->execute(['slug' => $categoriaSlug]);

        return $stmt->fetchAll();
    }

    public static function findBySlug(string $slug): ?array
    {
        $stmt = Database::connection()->prepare(
            'SELECT id, categoria_id, slug, titulo, descricao, fonte_url FROM leis WHERE slug = :slug LIMIT 1'
        );
        $stmt->execute(['slug' => $slug]);

        return $stmt->fetch() ?: null;
    }
}
