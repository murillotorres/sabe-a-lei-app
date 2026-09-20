<?php

declare(strict_types=1);

namespace App\Core;

final class Auth
{
    /// Exige um Bearer token válido e devolve o id do usuário autenticado,
    /// ou encerra a requisição com 401 se não houver um.
    public static function userId(Request $request): int
    {
        $token = $request->bearerToken();

        if ($token === null) {
            Response::error('Não autenticado.', 401);
        }

        $payload = Jwt::decode($token, Env::required('JWT_SECRET'));

        if ($payload === null || !isset($payload['sub'])) {
            Response::error('Token inválido ou expirado.', 401);
        }

        return (int) $payload['sub'];
    }
}
