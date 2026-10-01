<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Core\Auth;
use App\Core\Request;
use App\Core\Response;
use App\Models\Estudo;
use PDOException;

/// Grifos e anotações (Minhas anotações). Um endpoint só: o app manda as
/// alterações feitas no aparelho e recebe as do servidor (ver `Estudo`).
///
/// Depende das tabelas da migrations/002. Se ainda não existirem no banco do
/// ambiente, responde 503 — o app guarda as alterações e tenta de novo depois.
final class EstudoController
{
    public function sincronizar(Request $request): void
    {
        $userId = Auth::userId($request);

        $desde = $request->input('desde', 0);
        $grifos = $request->input('grifos', []);
        $anotacoes = $request->input('anotacoes', []);

        if (!is_int($desde) || $desde < 0 || !is_array($grifos) || !is_array($anotacoes)) {
            Response::error('Requisição inválida.', 422);
        }
        if (count($grifos) > Estudo::LIMITE_POR_LOTE || count($anotacoes) > Estudo::LIMITE_POR_LOTE) {
            Response::error('Lote grande demais.', 413);
        }

        try {
            $resultado = Estudo::sincronizar($userId, $desde, array_values($grifos), array_values($anotacoes));
        } catch (PDOException $e) {
            // 42S02: tabela inexistente — migration ainda não aplicada.
            if ($e->getCode() === '42S02') {
                Response::error('Anotações indisponíveis neste ambiente.', 503);
            }
            throw $e;
        }

        Response::json($resultado);
    }
}
