<?php

declare(strict_types=1);

namespace App\Models;

/// Busca em todas as leis cadastradas (aba Buscar do app). Cada artigo cai numa
/// faixa de relevância e as faixas nunca se misturam:
///
///   1. Referência exata   — "art. 121 cp", "5 cf", "121"
///   2. Título exato       — a rubrica do artigo é exatamente o que foi digitado
///   3. Expressão exata    — a frase digitada aparece inteira (no título antes do texto)
///   4. Termos no título   — todas as palavras estão no título
///   5. Termos no conteúdo — todas as palavras estão no texto (singular/plural valem)
///   6. Sinônimos          — só batem todas se contar os sinônimos ("assassinato" → homicídio)
///   7. Parcial            — só algumas palavras; aparece apenas se nada acima bateu
///
/// Palavra que não aparece em lei nenhuma é completada ("homici" → homicídio,
/// homicida…) ou corrigida ("defeza", "omicidio") por `CorrecaoDeBusca`, e a
/// busca inteira roda com a consulta ajustada — "legitima defeza" ainda acha o
/// título exato do art. 25. A consulta corrigida volta em `sugestao`.
///
/// "Título" é a rubrica do artigo ("Homicídio simples") ou, com peso menor, o
/// cabeçalho do capítulo em que ele está ("Dos crimes contra a vida") — só o
/// Código Penal tem rubricas. Dentro da faixa, desempata: bateu na rubrica,
/// bateu no cabeçalho, bateu no caput (e não só num inciso), proximidade das
/// palavras (`Artigo::pontuar`) e, por fim, a ordem das leis.
///
/// A busca dentro de um livro (`Artigo::search`) continua com o critério antigo,
/// o mesmo da busca offline do app (`BuscaLocal`).
final class BuscaGlobal
{
    private const REFERENCIA = 1;
    private const TITULO_EXATO = 2;
    private const EXPRESSAO_EXATA = 3;
    private const TERMOS_NO_TITULO = 4;
    private const TERMOS_NO_CONTEUDO = 5;
    private const SINONIMOS = 6;
    private const PARCIAL = 7;

    /// Palavras que não identificam nada sozinhas — contá-las fazia "crimes
    /// contra a vida" achar qualquer artigo com a letra "a". Continuam valendo
    /// na expressão exata.
    private const PALAVRAS_VAZIAS = [
        'a', 'o', 'as', 'os', 'e', 'ou', 'de', 'da', 'do', 'das', 'dos', 'em', 'no', 'na', 'nos', 'nas',
        'um', 'uma', 'para', 'por', 'pelo', 'pela', 'com', 'sem', 'que', 'se', 'ao', 'aos', 'art', 'artigo',
    ];

    /// Siglas e apelidos de cada lei, por slug — as mesmas do catálogo do app
    /// (`Livro.siglas`). Usadas pra reconhecer "art. 121 cp".
    private const SIGLAS = [
        'constituicao-federal-1988' => ['cf', 'cf88', 'crfb', 'federal', 'constituicao', 'carta', 'magna'],
        'codigo-civil-2002' => ['cc', 'cc02'],
        'codigo-penal-1940' => ['cp'],
        'codigo-processo-civil-2015' => ['cpc', 'ncpc'],
        'codigo-processo-penal-1941' => ['cpp'],
        'codigo-tributario-nacional-1966' => ['ctn'],
        'codigo-eleitoral-1965' => ['ce'],
        'codigo-defesa-consumidor-1990' => ['cdc'],
        'codigo-transito-brasileiro-1997' => ['ctb'],
        'codigo-penal-militar-1969' => ['cpm'],
        'codigo-processo-penal-militar-1969' => ['cppm'],
    ];

    /// Sinônimos e termos leigos → termos usados na lei (já normalizados). Direcional:
    /// "matar" procura "homicidio", mas "homicidio" não procura "matar".
    /// Palavra completada => as outras completações que também valem por ela
    /// ("homicidio" => ["homicida", …] para "homici"). Refeito a cada busca.
    private static array $completacoes = [];

    private const SINONIMOS_POR_TERMO = [
        'assassinato' => ['homicidio'],
        'assassinar' => ['homicidio', 'matar'],
        'matar' => ['homicidio'],
        'morte' => ['obito', 'falecimento'],
        'falecimento' => ['obito', 'morte'],
        'obito' => ['morte', 'falecimento'],
        'agressao' => ['lesao'],
        'ferimento' => ['lesao'],
        'casamento' => ['matrimonio', 'conjuge', 'conjuges'],
        'matrimonio' => ['casamento'],
        'marido' => ['conjuge'],
        'esposa' => ['conjuge'],
        'aluguel' => ['locacao', 'aluguer'],
        'inquilino' => ['locatario'],
        'senhorio' => ['locador'],
        'dono' => ['proprietario'],
        'heranca' => ['sucessao', 'herdeiro', 'herdeiros'],
        'pensao' => ['alimentos'],
        'imposto' => ['tributo', 'tributos'],
        'impostos' => ['tributo', 'tributos'],
        'tributo' => ['imposto'],
        'juiz' => ['magistrado'],
        'magistrado' => ['juiz'],
        'empregado' => ['trabalhador'],
        'trabalhador' => ['empregado'],
        'parlamentar' => ['deputado', 'senador'],
        'eleicao' => ['pleito'],
        'voto' => ['sufragio'],
        'propina' => ['vantagem indevida'],
        'cadeia' => ['prisao', 'reclusao'],
        'preso' => ['prisao', 'recluso'],
        'pm' => ['policia militar'],
    ];

    /// @return array{artigos: array, termos: string[], sugestao: ?string}
    public static function buscar(string $consulta): array
    {
        $palavras = self::palavras($consulta);
        if ($palavras === []) {
            return ['artigos' => [], 'termos' => [], 'sugestao' => null];
        }

        $artigos = Artigo::listAll();

        $referencia = self::referencia($palavras, $artigos);
        if ($referencia !== null) {
            return ['artigos' => $referencia, 'termos' => [], 'sugestao' => null];
        }

        $dispositivos = Artigo::dispositivosPorArtigo(array_map(static fn (array $a) => (int) $a['id'], $artigos));

        // Texto de cada artigo normalizado uma vez só.
        $textos = [];
        foreach ($artigos as $i => $artigo) {
            $lista = $dispositivos[(int) $artigo['id']] ?? [];
            $textos[$i] = [
                'rubrica' => Artigo::normalizar((string) ($artigo['rubrica'] ?? '')),
                'caput' => Artigo::normalizar($artigo['caput']),
                'completo' => Artigo::normalizar($artigo['caput'] . ' ' . implode(' ', array_column($lista, 'texto'))),
                'cabecalho' => Artigo::normalizar((string) ($artigo['descricao_estrutural'] ?? '')),
            ];
        }

        // Palavra que não aparece em lei nenhuma (nem por sinônimo) é completada
        // ("homici") ou corrigida ("defeza", "omicidio") — `CorrecaoDeBusca`.
        self::$completacoes = [];
        $sugestao = null;
        $ajuste = CorrecaoDeBusca::ajustar(
            self::termos($palavras),
            static fn (string $termo) => self::apareceEmAlgum(self::padrao(self::alternativas($termo, sinonimos: true)), $textos),
            static fn () => self::textosOriginais($artigos, $dispositivos),
        );
        if ($ajuste !== null) {
            $trocas = $ajuste['trocas'];
            $palavras = array_values(array_unique(array_map(static fn (string $p) => $trocas[$p] ?? $p, $palavras)));
            self::$completacoes = $ajuste['alternativas'];
            $sugestao = $ajuste['sugestao'];
        }

        $termos = self::termos($palavras);
        $frase = implode(' ', $palavras);
        $exatos = array_map(static fn (string $t) => self::padrao(self::alternativas($t)), $termos);
        $comSinonimos = array_map(static fn (string $t) => self::padrao(self::alternativas($t, sinonimos: true)), $termos);
        $padraoFrase = self::padrao([$frase]);

        $pontuados = [];
        foreach ($artigos as $i => $artigo) {
            $texto = $textos[$i];
            // Títulos do artigo: a rubrica ("Homicídio simples") e, mais fraco, o
            // cabeçalho do capítulo em que ele está ("Dos crimes contra a vida").
            $titulos = array_filter([$texto['rubrica'], $texto['cabecalho']], static fn (string $t) => $t !== '');
            $tudo = implode(' ', [...$titulos, $texto['completo']]);

            $fraseNoTitulo = self::algumTitulo($titulos, static fn (string $t) => preg_match($padraoFrase, $t) === 1);

            if ($texto['rubrica'] !== '' && $texto['rubrica'] === $frase) {
                $faixa = self::TITULO_EXATO;
            } elseif ($fraseNoTitulo || preg_match($padraoFrase, $texto['completo']) === 1) {
                $faixa = self::EXPRESSAO_EXATA;
            } elseif (self::algumTitulo($titulos, static fn (string $t) => self::todos($exatos, $t))) {
                $faixa = self::TERMOS_NO_TITULO;
            } elseif (self::todos($exatos, $tudo)) {
                $faixa = self::TERMOS_NO_CONTEUDO;
            } elseif (self::todos($comSinonimos, $tudo)) {
                $faixa = self::SINONIMOS;
            } elseif (self::algum($comSinonimos, $tudo)) {
                $faixa = self::PARCIAL;
            } else {
                continue;
            }

            $padroes = $faixa >= self::SINONIMOS ? $comSinonimos : $exatos;
            $artigo['trecho_correspondente'] = self::trecho($dispositivos[(int) $artigo['id']] ?? [], $padroes, $padraoFrase);

            // Onde as palavras estão no título: 0 = rubrica, 1 = cabeçalho, 2 = em nenhum.
            $bateNo = static fn (string $t) => $t !== '' && (preg_match($padraoFrase, $t) === 1 || self::todos($padroes, $t));
            $posicaoNoTitulo = $bateNo($texto['rubrica']) ? 0 : ($bateNo($texto['cabecalho']) ? 1 : 2);

            $pontuados[] = [
                'artigo' => $artigo,
                // Comparado posição a posição: menor vem antes.
                'chave' => [
                    $faixa,
                    $posicaoNoTitulo,
                    self::todos($padroes, $texto['caput']) ? 0 : 1,
                    -Artigo::pontuar($tudo, $termos, self::$completacoes),
                    $faixa === self::PARCIAL ? -self::quantos($padroes, $tudo) : 0,
                    (int) $artigo['lei_id'],
                    $artigo['parte'] === 'permanente' ? 0 : 1,
                    (int) $artigo['ordem'],
                ],
            ];
        }

        // Resultado com só parte das palavras é ruído quando há artigos com todas.
        $completos = array_filter($pontuados, static fn (array $p) => $p['chave'][0] !== self::PARCIAL);
        if ($completos !== []) {
            $pontuados = $completos;
        }

        usort($pontuados, static fn (array $a, array $b): int => $a['chave'] <=> $b['chave']);

        return [
            'artigos' => array_map(static fn (array $p) => $p['artigo'], $pontuados),
            'termos' => self::termosParaDestaque($termos),
            'sugestao' => $pontuados === [] ? null : $sugestao,
        ];
    }

    // MARK: Referência a artigo

    /// "art. 121 cp", "artigo 5º da constituição", "cp 121", "121" → os artigos com
    /// esse número nas leis indicadas (todas, se nenhuma). `null` se a busca não
    /// é uma referência ou se nenhum artigo tem esse número.
    private static function referencia(array $palavras, array $artigos): ?array
    {
        $numero = null;
        $resto = [];
        $ignorarProxima = false;
        foreach ($palavras as $palavra) {
            if ($ignorarProxima) {
                // O número/rótulo do parágrafo/inciso ("§ 2º", "inciso IV"): a
                // referência leva ao artigo.
                $ignorarProxima = false;
            } elseif ($numero === null && preg_match('/^(?:art|artigo|arts|a)?(\d+)([a-z])?$/', $palavra, $m) === 1) {
                // "5o" é ordinal digitado sem º; outra letra é o sufixo ("103a" → "103-A").
                $letra = $m[2] ?? '';
                $numero = $m[1] . ($letra !== '' && $letra !== 'o' ? '-' . strtoupper($letra) : '');
            } elseif (in_array($palavra, ['paragrafo', 'par', 'inciso', 'inc', 'alinea', 'al'], true)) {
                $ignorarProxima = true;
            } elseif (!in_array($palavra, ['art', 'artigo', 'arts', 'da', 'do', 'de', 'o', 'a', 'caput', 'unico'], true)) {
                $resto[] = $palavra;
            }
        }

        if ($numero === null) {
            return null;
        }

        $leis = [];
        foreach ($artigos as $artigo) {
            $leis[$artigo['lei_slug']] ??= Artigo::normalizar($artigo['lei_titulo']);
        }

        $leisIndicadas = array_filter($leis, static function (string $titulo, string $slug) use ($resto): bool {
            foreach ($resto as $palavra) {
                if (!in_array($palavra, self::SIGLAS[$slug] ?? [], true) && !str_contains($titulo, $palavra)) {
                    return false;
                }
            }
            return true;
        }, ARRAY_FILTER_USE_BOTH);

        if ($leisIndicadas === []) {
            return null;
        }

        $encontrados = array_values(array_filter(
            $artigos,
            static fn (array $a) => $a['numero'] === $numero && isset($leisIndicadas[$a['lei_slug']])
        ));

        // "código penal" também cabe no Código de Processo Penal: o título mais
        // curto é o que mais se parece com o digitado.
        usort($encontrados, static fn (array $a, array $b): int => [
            mb_strlen($leisIndicadas[$a['lei_slug']]), (int) $a['lei_id'], $a['parte'] === 'permanente' ? 0 : 1,
        ] <=> [
            mb_strlen($leisIndicadas[$b['lei_slug']]), (int) $b['lei_id'], $b['parte'] === 'permanente' ? 0 : 1,
        ]);

        return $encontrados === [] ? null : $encontrados;
    }

    // MARK: Palavras e padrões

    /// Palavras normalizadas da consulta, sem pontuação ("art. 5º" → "art", "5").
    /// "103-A" vira "103a" antes de o hífen virar espaço — é número de artigo.
    private static function palavras(string $consulta): array
    {
        $consulta = preg_replace('/(\d)\s*[-‐‑–—]\s*(\p{L})(?!\p{L})/u', '$1$2', $consulta) ?? $consulta;

        return Artigo::tokenizar($consulta);
    }

    /// As palavras que identificam algo — sem "de", "a", "art"… (a menos que
    /// só haja essas).
    private static function termos(array $palavras): array
    {
        return array_values(array_diff($palavras, self::PALAVRAS_VAZIAS)) ?: $palavras;
    }

    /// Formas que valem pela palavra: ela, singular/plural, abreviações e,
    /// opcionalmente, sinônimos.
    private static function alternativas(string $termo, bool $sinonimos = false): array
    {
        return array_values(array_unique([
            ...self::variantes($termo),
            ...(Artigo::ABREVIACOES[$termo] ?? []),
            ...(self::$completacoes[$termo] ?? []),
            ...($sinonimos ? self::SINONIMOS_POR_TERMO[$termo] ?? [] : []),
        ]));
    }

    /// Textos na grafia original (rubrica, caput e dispositivos de cada artigo,
    /// em ordem) — de onde sai o vocabulário da correção de digitação.
    private static function textosOriginais(array $artigos, array $dispositivos): \Generator
    {
        foreach ($artigos as $artigo) {
            yield (string) ($artigo['rubrica'] ?? '');
            yield $artigo['caput'];
            foreach ($dispositivos[(int) $artigo['id']] ?? [] as $dispositivo) {
                yield $dispositivo['texto'];
            }
        }
    }

    /// A palavra e sua forma no singular/plural — "homicidios" acha "homicidio",
    /// "lesao" acha "lesoes".
    private static function variantes(string $termo): array
    {
        $variantes = [$termo];
        if (mb_strlen($termo) < 4 || preg_match('/\d/', $termo) === 1) {
            return $variantes;
        }

        // Só a primeira regra que servir; nenhuma serviu, é o "s" simples.
        $regras = [['oes', 'ao'], ['ais', 'al'], ['eis', 'el'], ['res', 'r'], ['zes', 'z'], ['ns', 'm']];
        foreach ($regras as [$plural, $singular]) {
            if (str_ends_with($termo, $plural)) {
                return [$termo, substr($termo, 0, -strlen($plural)) . $singular];
            }
            if (str_ends_with($termo, $singular)) {
                return [$termo, substr($termo, 0, -strlen($singular)) . $plural];
            }
        }
        $variantes[] = str_ends_with($termo, 's') ? substr($termo, 0, -1) : $termo . 's';

        return $variantes;
    }

    /// Regex de palavra inteira que casa com qualquer das alternativas.
    private static function padrao(array $alternativas): string
    {
        $partes = array_map(static fn (string $a) => str_replace('\\ ', '\\s+', preg_quote($a, '/')), array_unique($alternativas));

        return '/\b(?:' . implode('|', $partes) . ')\b/u';
    }

    private static function todos(array $padroes, string $texto): bool
    {
        foreach ($padroes as $padrao) {
            if (preg_match($padrao, $texto) !== 1) {
                return false;
            }
        }
        return true;
    }

    private static function algum(array $padroes, string $texto): bool
    {
        return self::quantos($padroes, $texto) > 0;
    }

    private static function quantos(array $padroes, string $texto): int
    {
        return count(array_filter($padroes, static fn (string $p) => preg_match($p, $texto) === 1));
    }

    private static function algumTitulo(array $titulos, callable $bate): bool
    {
        foreach ($titulos as $titulo) {
            if ($bate($titulo)) {
                return true;
            }
        }
        return false;
    }

    private static function apareceEmAlgum(string $padrao, array $textos): bool
    {
        foreach ($textos as $texto) {
            if (preg_match($padrao, $texto['rubrica'] . ' ' . $texto['cabecalho'] . ' ' . $texto['completo']) === 1) {
                return true;
            }
        }
        return false;
    }

    // MARK: Resposta

    /// Palavras que o app deve destacar no texto: as buscadas (já corrigidas),
    /// com singular/plural, abreviações e sinônimos.
    private static function termosParaDestaque(array $termos): array
    {
        $destaque = [];
        foreach ($termos as $termo) {
            array_push($destaque, ...self::alternativas($termo, sinonimos: true));
        }

        return array_values(array_unique($destaque));
    }

    /// O dispositivo (parágrafo/inciso/alínea) que explica o resultado: o que
    /// tem a expressão exata ou, senão, o maior número de palavras buscadas.
    private static function trecho(array $dispositivos, array $padroes, string $padraoFrase): ?array
    {
        $melhor = null;
        $melhorPontuacao = 0;
        foreach ($dispositivos as $dispositivo) {
            $texto = Artigo::normalizar($dispositivo['texto']);
            $pontuacao = self::quantos($padroes, $texto) + (preg_match($padraoFrase, $texto) === 1 ? 100 : 0);
            if ($pontuacao > $melhorPontuacao) {
                $melhorPontuacao = $pontuacao;
                $melhor = $dispositivo;
            }
        }

        return $melhor === null ? null : [
            'tipo' => $melhor['tipo'],
            'rotulo' => $melhor['rotulo'],
            'texto' => $melhor['texto'],
        ];
    }
}
