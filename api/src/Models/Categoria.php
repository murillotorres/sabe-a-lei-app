<?php

declare(strict_types=1);

namespace App\Models;

use App\Core\Database;

final class Categoria
{
    public static function all(): array
    {
        return Database::connection()
            ->query('SELECT id, slug, nome FROM categorias ORDER BY nome')
            ->fetchAll();
    }

    public static function findBySlug(string $slug): ?array
    {
        $stmt = Database::connection()->prepare(
            'SELECT id, slug, nome FROM categorias WHERE slug = :slug LIMIT 1'
        );
        $stmt->execute(['slug' => $slug]);

        return $stmt->fetch() ?: null;
    }
}
