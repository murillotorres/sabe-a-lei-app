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
    /// Teto de artigos por página — evita que um `limit` enorme reproduza, na
    /// prática, a resposta do livro inteiro.
    private const LIMITE_MAXIMO_POR_PAGINA = 100;

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

        // Busca por texto sempre olha o livro inteiro (a relevância é calculada
        // sobre todos os artigos), então não é paginada.
        if ($busca !== '') {
            $registros = Artigo::search((int) $lei['id'], $parte, $busca);

            Response::json([
                'lei' => $lei,
                'parte' => $parte,
                'artigos' => array_map(fn (array $a) => $this->formatArtigo($a), $registros),
            ]);
        }

        $numero = trim((string) $request->query('numero', ''));
        $numero = $numero === '' ? null : $numero;

        $limit = $this->inteiroPositivo($request->query('limit'), 'limit');
        $offset = $this->inteiroPositivo($request->query('offset'), 'offset', minimo: 0) ?? 0;

        // Sem `limit` a resposta é o livro inteiro, como antes da paginação — é
        // o que mantém funcionando as versões do app que ainda não paginam.
        if ($limit === null) {
            $registros = Artigo::listByLei((int) $lei['id'], $parte, numero: $numero);

            Response::json([
                'lei' => $lei,
                'parte' => $parte,
                'artigos' => array_map(fn (array $a) => $this->formatArtigo($a), $registros),
            ]);
        }

        $limit = min($limit, self::LIMITE_MAXIMO_POR_PAGINA);

        // Pede um a mais só pra saber se ainda há o que carregar, sem um COUNT à parte.
        $registros = Artigo::listByLei((int) $lei['id'], $parte, $limit + 1, $offset, $numero);
        $temMais = count($registros) > $limit;

        Response::json([
            'lei' => $lei,
            'parte' => $parte,
            'artigos' => array_map(fn (array $a) => $this->formatArtigo($a), array_slice($registros, 0, $limit)),
            'paginacao' => [
                'limit' => $limit,
                'offset' => $offset,
                'temMais' => $temMais,
            ],
        ]);
    }

    /// Lê um parâmetro inteiro opcional da query: `null` se ausente, 422 se
    /// vier algo que não seja um inteiro `>= $minimo`.
    private function inteiroPositivo(mixed $valor, string $nome, int $minimo = 1): ?int
    {
        if ($valor === null || $valor === '') {
            return null;
        }

        if (filter_var($valor, FILTER_VALIDATE_INT, ['options' => ['min_range' => $minimo]]) === false) {
            Response::error("Parâmetro {$nome} inválido. Use um inteiro maior ou igual a {$minimo}.", 422);
        }

        return (int) $valor;
    }

    /// Busca em todas as leis cadastradas (aba Buscar) — ao contrário de
    /// `artigos()`, não fica restrita a uma lei/parte específica.
    public function buscar(Request $request): void
    {
        $busca = trim((string) $request->query('q', ''));

        $artigos = $busca === ''
            ? []
            : array_map(fn (array $a) => $this->formatArtigo($a), Artigo::searchGlobal($busca));

        Response::json(['artigos' => $artigos]);
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
        $artigo = Artigo::formatar($a);

        if (isset($a['trecho_correspondente'])) {
            $artigo['trechoCorrespondente'] = $a['trecho_correspondente'];
        }

        return $artigo;
    }
}
