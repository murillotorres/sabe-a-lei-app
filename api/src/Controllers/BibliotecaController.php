<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Core\Request;
use App\Core\Response;
use App\Models\ConteudoOffline;
use App\Models\Lei;
use App\Models\LeiVersao;
use PDOException;

/// Endpoints do armazenamento offline do app: manifesto de versões, conteúdo
/// completo de um livro (por páginas) e atualizações incrementais.
///
/// Todos dependem das tabelas de versionamento (migrations/001). Se ainda não
/// foram criadas no banco do ambiente, respondem 503 — o app entende isso como
/// "sem offline por enquanto" e continua funcionando online, como sempre.
final class BibliotecaController
{
    private const ARTIGOS_POR_PAGINA = 100;

    /// Versão publicada de cada lei. Resposta propositalmente minúscula: é o
    /// que o app consulta a cada abertura, sem baixar nenhum conteúdo.
    public function manifesto(Request $request): void
    {
        $livros = $this->protegido(static fn () => LeiVersao::manifesto());

        Response::json(['livros' => $livros]);
    }

    /// Livro completo, em páginas de artigos com seus dispositivos. Cada página
    /// repete a versão e o checksum, para o app detectar uma publicação no
    /// meio do download e recomeçar.
    public function conteudo(Request $request, array $params): void
    {
        [$lei, $versao] = $this->leiPublicada($params['slug'] ?? '');

        $limit = $this->inteiro($request->query('limit'), 'limit', 1) ?? self::ARTIGOS_POR_PAGINA;
        $limit = min($limit, self::ARTIGOS_POR_PAGINA);
        $offset = $this->inteiro($request->query('offset'), 'offset', 0) ?? 0;

        // Um a mais só pra saber se há próxima página.
        $artigos = $this->protegido(static fn () => ConteudoOffline::pagina((int) $lei['id'], $limit + 1, $offset));
        $temMais = count($artigos) > $limit;

        Response::json([
            'lei' => $lei,
            'livro' => $this->livro($lei, $versao),
            'artigos' => array_slice($artigos, 0, $limit),
            'paginacao' => ['limit' => $limit, 'offset' => $offset, 'temMais' => $temMais],
        ]);
    }

    /// O que mudou desde a versão `de` (ex.: `?de=1.1`) até a última publicada.
    public function atualizacoes(Request $request, array $params): void
    {
        [$lei] = $this->leiPublicada($params['slug'] ?? '');

        $de = LeiVersao::interpretar(trim((string) $request->query('de', '')));
        if ($de === null) {
            Response::error('Informe o parâmetro de no formato major.minor (ex.: 1.1).', 422);
        }

        $resposta = $this->protegido(static fn () => LeiVersao::atualizacoes((int) $lei['id'], $de));

        Response::json(['livro' => $lei['slug']] + $resposta);
    }

    /// @return array{0: array, 1: array} lei e sua última versão publicada
    private function leiPublicada(string $slug): array
    {
        $lei = Lei::findBySlug($slug);
        if ($lei === null) {
            Response::error('Lei não encontrada.', 404);
        }

        $versao = $this->protegido(static fn () => LeiVersao::ultima((int) $lei['id']));
        if ($versao === null) {
            Response::error('Esta lei ainda não tem versão publicada para uso offline.', 404);
        }

        return [$lei, $versao];
    }

    private function livro(array $lei, array $versao): array
    {
        return [
            'id' => $lei['slug'],
            'titulo' => $lei['titulo'],
            'versao' => LeiVersao::rotulo($versao),
            'checksum' => $versao['checksum'],
            'totalDeArtigos' => (int) $versao['artigos_total'],
        ];
    }

    private function inteiro(mixed $valor, string $nome, int $minimo): ?int
    {
        if ($valor === null || $valor === '') {
            return null;
        }

        if (filter_var($valor, FILTER_VALIDATE_INT, ['options' => ['min_range' => $minimo]]) === false) {
            Response::error("Parâmetro {$nome} inválido. Use um inteiro maior ou igual a {$minimo}.", 422);
        }

        return (int) $valor;
    }

    /// Executa uma consulta que depende das tabelas de versionamento; se elas
    /// não existirem (migration ainda não aplicada), responde 503 em vez de 500.
    private function protegido(callable $consulta): mixed
    {
        try {
            return $consulta();
        } catch (PDOException $e) {
            Response::error('Armazenamento offline indisponível neste ambiente.', 503);
        }
    }
}
