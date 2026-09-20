<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Core\Auth;
use App\Core\Request;
use App\Core\Response;
use App\Models\Artigo;
use App\Models\Favorito;

final class FavoritoController
{
    public function listar(Request $request): void
    {
        $userId = Auth::userId($request);

        $favoritos = array_map([$this, 'formatar'], Favorito::listarPorUsuario($userId));

        Response::json(['favoritos' => $favoritos]);
    }

    public function criar(Request $request): void
    {
        $userId = Auth::userId($request);

        $artigoId = (int) ($request->input('artigoId') ?? 0);
        $dispositivoIdBruto = $request->input('dispositivoId');
        $dispositivoId = $dispositivoIdBruto !== null ? (int) $dispositivoIdBruto : null;

        if ($artigoId <= 0) {
            Response::error('Informe o artigo a favoritar.', 422);
        }

        if (Artigo::find($artigoId) === null) {
            Response::error('Artigo não encontrado.', 404);
        }

        if ($dispositivoId !== null) {
            $dispositivo = Artigo::dispositivo($dispositivoId);
            if ($dispositivo === null || (int) $dispositivo['artigo_id'] !== $artigoId) {
                Response::error('Dispositivo não encontrado neste artigo.', 404);
            }
            if ($dispositivo['tipo'] !== 'paragrafo') {
                Response::error('Só é possível favoritar o artigo inteiro ou um parágrafo.', 422);
            }
        }

        $id = Favorito::existenteId($userId, $artigoId, $dispositivoId)
            ?? Favorito::criar($userId, $artigoId, $dispositivoId);

        $favorito = Favorito::buscar($id, $userId);
        Response::json(['favorito' => $this->formatar($favorito)], 201);
    }

    public function remover(Request $request, array $params): void
    {
        $userId = Auth::userId($request);
        $id = (int) ($params['id'] ?? 0);

        if (!Favorito::remover($id, $userId)) {
            Response::error('Favorito não encontrado.', 404);
        }

        Response::json(['ok' => true]);
    }

    private function formatar(array $f): array
    {
        $dispositivo = null;
        if ($f['dispositivo_id'] !== null) {
            $dispositivo = [
                'id' => (int) $f['d_id'],
                'tipo' => $f['d_tipo'],
                'rotulo' => $f['d_rotulo'],
                'texto' => $f['d_texto'],
            ];
        }

        return [
            'id' => (int) $f['favorito_id'],
            'artigo' => Artigo::formatar($f),
            'dispositivo' => $dispositivo,
        ];
    }
}
