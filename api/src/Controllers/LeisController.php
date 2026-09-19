<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Core\Request;
use App\Core\Response;
use App\Models\Artigo;
use App\Models\Categoria;
use App\Models\Lei;

final class LeisController
{
    public function categorias(Request $request): void
    {
        Response::json(['categorias' => Categoria::all()]);
    }

    public function leis(Request $request): void
    {
        $categoriaSlug = (string) $request->query('categoria', '');

        if ($categoriaSlug === '') {
            Response::error('Informe o parâmetro categoria.', 422);
        }

        if (Categoria::findBySlug($categoriaSlug) === null) {
            Response::error('Categoria não encontrada.', 404);
        }

        Response::json(['leis' => Lei::byCategoria($categoriaSlug)]);
    }

    public function artigos(Request $request, array $params): void
    {
        $lei = Lei::findBySlug($params['slug'] ?? '');

        if ($lei === null) {
            Response::error('Lei não encontrada.', 404);
        }

        $parte = (string) $request->query('parte', 'permanente');
        if (!in_array($parte, ['permanente', 'adct'], true)) {
            Response::error('Parâmetro parte inválido. Use "permanente" ou "adct".', 422);
        }

        $busca = trim((string) $request->query('q', ''));

        $registros = $busca === ''
            ? Artigo::listByLei((int) $lei['id'], $parte)
            : Artigo::search((int) $lei['id'], $parte, $busca);

        $artigos = array_map(fn (array $a) => $this->formatArtigo($a), $registros);

        Response::json([
            'lei' => $lei,
            'parte' => $parte,
            'artigos' => $artigos,
        ]);
    }

    public function artigo(Request $request, array $params): void
    {
        $id = (int) ($params['id'] ?? 0);
        $artigo = Artigo::find($id);

        if ($artigo === null) {
            Response::error('Artigo não encontrado.', 404);
        }

        $dispositivos = array_map(
            fn (array $d) => [
                'id' => (int) $d['id'],
                'parentId' => $d['parent_id'] !== null ? (int) $d['parent_id'] : null,
                'tipo' => $d['tipo'],
                'rotulo' => $d['rotulo'],
                'texto' => $d['texto'],
                'nivel' => (int) $d['nivel'],
                'revogado' => (bool) $d['revogado'],
                'ordem' => (int) $d['ordem'],
            ],
            Artigo::dispositivos($id)
        );

        Response::json([
            'artigo' => $this->formatArtigo($artigo),
            'dispositivos' => $dispositivos,
        ]);
    }

    private function formatArtigo(array $a): array
    {
        return [
            'id' => (int) $a['id'],
            'parte' => $a['parte'],
            'numero' => $a['numero'],
            'tituloEstrutural' => $a['titulo_estrutural'],
            'capituloEstrutural' => $a['capitulo_estrutural'],
            'secaoEstrutural' => $a['secao_estrutural'],
            'subsecaoEstrutural' => $a['subsecao_estrutural'],
            'caput' => $a['caput'],
            'revogado' => (bool) $a['revogado'],
            'ordem' => (int) $a['ordem'],
            'leiSlug' => $a['lei_slug'] ?? null,
            'leiTitulo' => $a['lei_titulo'] ?? null,
        ];
    }
}
