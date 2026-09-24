#!/usr/bin/env php
<?php

declare(strict_types=1);

/// Publica a próxima versão de uma lei para o armazenamento offline do app.
///
/// Uso:
///   php bin/publicar-versao.php <slug>            publica se algo mudou desde a última versão
///   php bin/publicar-versao.php --todas           o mesmo para todas as leis
///   php bin/publicar-versao.php <slug> --major    versão estrutural: o app baixa o livro inteiro
///   php bin/publicar-versao.php <slug> --simular  mostra o que mudaria, sem gravar
///   php bin/publicar-versao.php <slug> --notas="Lei 14.xxx/2026"
///
/// Rode depois de alterar o conteúdo de uma lei no banco (reseed ou correção).
/// Na primeira execução de uma lei, publica a versão 1.0.

use App\Core\Database;
use App\Core\Env;
use App\Models\Lei;
use App\Models\LeiVersao;

require dirname(__DIR__) . '/src/autoload.php';

Env::load(dirname(__DIR__) . '/.env');

$slugs = [];
$estrutural = false;
$simular = false;
$todas = false;
$notas = null;

foreach (array_slice($argv, 1) as $argumento) {
    if ($argumento === '--major') {
        $estrutural = true;
    } elseif ($argumento === '--simular') {
        $simular = true;
    } elseif ($argumento === '--todas') {
        $todas = true;
    } elseif (str_starts_with($argumento, '--notas=')) {
        $notas = substr($argumento, strlen('--notas='));
    } elseif (str_starts_with($argumento, '--')) {
        fwrite(STDERR, "Opção desconhecida: {$argumento}\n");
        exit(2);
    } else {
        $slugs[] = $argumento;
    }
}

if ($todas) {
    $slugs = array_column(Database::connection()->query('SELECT slug FROM leis ORDER BY id')->fetchAll(), 'slug');
}

if ($slugs === []) {
    fwrite(STDERR, "Informe o slug da lei ou use --todas.\n");
    exit(2);
}

foreach ($slugs as $slug) {
    $lei = Lei::findBySlug($slug);
    if ($lei === null) {
        fwrite(STDERR, "Lei não encontrada: {$slug}\n");
        exit(1);
    }

    $r = LeiVersao::publicar((int) $lei['id'], $estrutural, $notas, $simular);

    if ($r['anterior'] !== null && $r['versao'] === $r['anterior']) {
        echo "{$slug}: sem mudanças (versão {$r['versao']}, {$r['total']} artigos)\n";
        continue;
    }

    $situacao = $simular ? 'seria publicada' : 'publicada';
    $de = $r['anterior'] !== null ? "{$r['anterior']} → " : '';
    echo "{$slug}: versão {$de}{$r['versao']} {$situacao} — "
        . "{$r['inseridos']} inseridos, {$r['alterados']} alterados, {$r['removidos']} removidos "
        . "({$r['total']} artigos)\n";
}
