<?php

declare(strict_types=1);

namespace App\Core;

/**
 * Implementação mínima de JWT (HS256). O algoritmo é sempre fixo em HS256 —
 * o campo "alg" do header recebido nunca é usado para decidir a verificação,
 * o que evita ataques clássicos de confusão de algoritmo (ex.: "alg: none").
 */
final class Jwt
{
    public static function encode(array $payload, string $secret, int $ttlSeconds = 604800): string
    {
        $header = ['alg' => 'HS256', 'typ' => 'JWT'];
        $payload['iat'] = time();
        $payload['exp'] = time() + $ttlSeconds;

        $segments = [
            self::base64UrlEncode(json_encode($header)),
            self::base64UrlEncode(json_encode($payload)),
        ];

        $signature = hash_hmac('sha256', implode('.', $segments), $secret, true);
        $segments[] = self::base64UrlEncode($signature);

        return implode('.', $segments);
    }

    public static function decode(string $token, string $secret): ?array
    {
        $parts = explode('.', $token);

        if (count($parts) !== 3) {
            return null;
        }

        [$headerB64, $payloadB64, $signatureB64] = $parts;

        $expectedSignature = hash_hmac('sha256', "{$headerB64}.{$payloadB64}", $secret, true);
        $signature = self::base64UrlDecode($signatureB64);

        if (!hash_equals($expectedSignature, $signature)) {
            return null;
        }

        $payload = json_decode(self::base64UrlDecode($payloadB64), true);

        if (!is_array($payload)) {
            return null;
        }

        if (isset($payload['exp']) && time() >= (int) $payload['exp']) {
            return null;
        }

        return $payload;
    }

    private static function base64UrlEncode(string $data): string
    {
        return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
    }

    private static function base64UrlDecode(string $data): string
    {
        $remainder = strlen($data) % 4;
        $padded = $remainder === 0 ? $data : str_pad($data, strlen($data) + (4 - $remainder), '=');

        return base64_decode(strtr($padded, '-_', '+/')) ?: '';
    }
}
