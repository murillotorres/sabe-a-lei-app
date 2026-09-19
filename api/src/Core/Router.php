<?php

declare(strict_types=1);

namespace App\Core;

final class Router
{
    /** @var array<int, array{0: string, 1: string, 2: callable}> */
    private array $routes = [];

    public function get(string $path, callable $handler): void
    {
        $this->add('GET', $path, $handler);
    }

    public function post(string $path, callable $handler): void
    {
        $this->add('POST', $path, $handler);
    }

    private function add(string $method, string $path, callable $handler): void
    {
        $this->routes[] = [$method, $path, $handler];
    }

    public function dispatch(string $method, string $path): void
    {
        foreach ($this->routes as [$routeMethod, $routePath, $handler]) {
            if ($routeMethod !== $method) {
                continue;
            }

            $params = $this->match($routePath, $path);
            if ($params !== null) {
                $handler($params);

                return;
            }
        }

        Response::error('Rota não encontrada.', 404);
    }

    /** @return array<string, string>|null */
    private function match(string $routePath, string $path): ?array
    {
        $routeSegments = explode('/', trim($routePath, '/'));
        $pathSegments = explode('/', trim($path, '/'));

        if (count($routeSegments) !== count($pathSegments)) {
            return null;
        }

        $params = [];
        foreach ($routeSegments as $i => $segment) {
            if (str_starts_with($segment, ':')) {
                $params[substr($segment, 1)] = $pathSegments[$i];
                continue;
            }
            if ($segment !== $pathSegments[$i]) {
                return null;
            }
        }

        return $params;
    }
}
