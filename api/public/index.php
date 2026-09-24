<?php

declare(strict_types=1);

use App\Controllers\AuthController;
use App\Controllers\BibliotecaController;
use App\Controllers\FavoritoController;
use App\Controllers\LeisController;
use App\Core\Env;
use App\Core\Request;
use App\Core\Router;

require dirname(__DIR__) . '/src/autoload.php';

Env::load(dirname(__DIR__) . '/.env');

$request = new Request();
$router = new Router();
$auth = new AuthController();
$leis = new LeisController();
$favoritos = new FavoritoController();
$biblioteca = new BibliotecaController();

$router->post('/auth/register', fn () => $auth->register($request));
$router->post('/auth/login', fn () => $auth->login($request));
$router->get('/auth/me', fn () => $auth->me($request));

$router->get('/categorias', fn () => $leis->categorias($request));
$router->get('/leis', fn () => $leis->leis($request));
$router->get('/leis/:slug/artigos', fn ($params) => $leis->artigos($request, $params));
$router->get('/artigos/:id', fn ($params) => $leis->artigo($request, $params));
$router->get('/busca', fn () => $leis->buscar($request));

$router->get('/biblioteca/manifesto', fn () => $biblioteca->manifesto($request));
$router->get('/leis/:slug/conteudo', fn ($params) => $biblioteca->conteudo($request, $params));
$router->get('/leis/:slug/atualizacoes', fn ($params) => $biblioteca->atualizacoes($request, $params));

$router->get('/favoritos', fn () => $favoritos->listar($request));
$router->post('/favoritos', fn () => $favoritos->criar($request));
$router->delete('/favoritos/:id', fn ($params) => $favoritos->remover($request, $params));

$router->dispatch(Request::method(), Request::path());
