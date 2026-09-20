<?php

declare(strict_types=1);

namespace App\Controllers;

use App\Core\Auth;
use App\Core\Env;
use App\Core\Jwt;
use App\Core\Request;
use App\Core\Response;
use App\Models\User;

final class AuthController
{
    public function register(Request $request): void
    {
        $name = trim((string) $request->input('name', ''));
        $email = strtolower(trim((string) $request->input('email', '')));
        $password = (string) $request->input('password', '');

        if ($name === '' || $email === '' || $password === '') {
            Response::error('Nome, e-mail e senha são obrigatórios.', 422);
        }

        if (filter_var($email, FILTER_VALIDATE_EMAIL) === false) {
            Response::error('E-mail inválido.', 422);
        }

        if (strlen($password) < 8) {
            Response::error('A senha deve ter pelo menos 8 caracteres.', 422);
        }

        if (User::findByEmail($email) !== null) {
            Response::error('Este e-mail já está cadastrado.', 409);
        }

        $userId = User::create($name, $email, password_hash($password, PASSWORD_DEFAULT));

        Response::json([
            'token' => $this->issueToken($userId),
            'user' => User::findById($userId),
        ], 201);
    }

    public function login(Request $request): void
    {
        $email = strtolower(trim((string) $request->input('email', '')));
        $password = (string) $request->input('password', '');

        if ($email === '' || $password === '') {
            Response::error('E-mail e senha são obrigatórios.', 422);
        }

        $user = User::findByEmail($email);

        if ($user === null || !password_verify($password, $user['password_hash'])) {
            Response::error('Credenciais inválidas.', 401);
        }

        unset($user['password_hash']);

        Response::json([
            'token' => $this->issueToken((int) $user['id']),
            'user' => $user,
        ]);
    }

    public function me(Request $request): void
    {
        $userId = Auth::userId($request);
        $user = User::findById($userId);

        if ($user === null) {
            Response::error('Usuário não encontrado.', 404);
        }

        Response::json(['user' => $user]);
    }

    private function issueToken(int $userId): string
    {
        return Jwt::encode(['sub' => $userId], Env::required('JWT_SECRET'));
    }
}
