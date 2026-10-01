<?php

declare(strict_types=1);

namespace App\Models;

/// Ajuste das palavras que não aparecem em nenhum texto pesquisado — a busca
/// não mexe em palavra que existe, senão "pena" viraria "penal". Em ordem:
///
///   1. Completar: palavra ainda sendo digitada ("homici" → homicídio, homicida…)
///   2. Corrigir: erro de digitação ("defeza" → defesa), inclusive pelo som
///      ("omicidio" → homicídio)
///
/// O app repete esta lógica na busca offline (`CorrecaoDeBusca` em
/// `BuscaLei.swift`): mesmo vocabulário, mesma distância e mesmo desempate,
/// para a sugestão ser a mesma com ou sem internet.
final class CorrecaoDeBusca
{
    /// Vocabulário dos textos, na ordem dada: normalizada => [grafia original
    /// em minúsculas (a primeira vista), quantas vezes aparece]. Só palavras
    /// de 4 letras ou mais.
    public static function vocabulario(iterable $textos): array
    {
        $vocabulario = [];
        foreach ($textos as $texto) {
            preg_match_all('/\p{L}{4,}/u', mb_strtolower((string) $texto, 'UTF-8'), $m);
            foreach ($m[0] as $palavra) {
                $normalizada = Artigo::normalizar($palavra);
                if (isset($vocabulario[$normalizada])) {
                    $vocabulario[$normalizada][1]++;
                } else {
                    $vocabulario[$normalizada] = [$palavra, 1];
                }
            }
        }

        return $vocabulario;
    }

    /// Palavra digitada pela metade só é completada a partir de 4 letras, e
    /// vale pelas 20 palavras mais usadas que começam com ela.
    private const MINIMO_PARA_COMPLETAR = 4;
    private const MAXIMO_DE_COMPLETACOES = 20;

    /// Ajusta `$tokens` que `$aparece` diz não existirem nos textos: completa
    /// (a mais usada fica no lugar do token e as outras vão em `alternativas`)
    /// ou corrige. `sugestao` só existe se algo foi corrigido — completar é
    /// digitação normal. `null` se nada mudou.
    /// @return array{tokens: string[], trocas: array<string, string>, alternativas: array<string, string[]>, sugestao: ?string}|null
    public static function ajustar(array $tokens, callable $aparece, callable $textos): ?array
    {
        $ausentes = array_values(array_filter($tokens, static fn (string $t) => !$aparece($t)));
        if ($ausentes === []) {
            return null;
        }

        $vocabulario = self::vocabulario($textos());
        $trocas = [];
        $alternativas = [];
        $correcoes = [];
        foreach ($ausentes as $token) {
            $completacoes = self::completar($token, $vocabulario);
            if ($completacoes !== []) {
                $trocas[$token] = $completacoes[0];
                $alternativas[$completacoes[0]] = array_slice($completacoes, 1);
            } elseif (($correcao = self::corrigir($token, $vocabulario)) !== null) {
                $trocas[$token] = $correcao['normalizada'];
                $correcoes[$token] = $correcao;
            }
        }
        if ($trocas === []) {
            return null;
        }

        return [
            'tokens' => array_values(array_unique(array_map(static fn (string $t) => $trocas[$t] ?? $t, $tokens))),
            'trocas' => $trocas,
            'alternativas' => $alternativas,
            'sugestao' => $correcoes === [] ? null : self::sugestao($tokens, $correcoes, $vocabulario),
        ];
    }

    /// Palavras do vocabulário que começam com `$prefixo`, das mais usadas para
    /// as menos (empate: ordem alfabética).
    /// @return string[]
    public static function completar(string $prefixo, array $vocabulario): array
    {
        if (strlen($prefixo) < self::MINIMO_PARA_COMPLETAR || preg_match('/\d/', $prefixo) === 1) {
            return [];
        }

        $achadas = [];
        foreach ($vocabulario as $normalizada => [, $frequencia]) {
            $normalizada = (string) $normalizada;
            if ($normalizada !== $prefixo && str_starts_with($normalizada, $prefixo)) {
                $achadas[] = [-$frequencia, $normalizada];
            }
        }
        sort($achadas);

        return array_map(static fn (array $a) => $a[1], array_slice($achadas, 0, self::MAXIMO_DE_COMPLETACOES));
    }

    /// A palavra do vocabulário mais parecida com `$termo`. Vale a que soa igual
    /// ("omicidio" × "homicidio", "divorsio" × "divorcio") ou a de mesma
    /// primeira letra com até 1 erro em palavras de até 7 letras, 2 acima disso
    /// (ou nas mesmas letras embaralhadas), sem ser só outra flexão. A primeira
    /// letra só pode estar errada em palavra de 8+ letras e se for o único erro. Desempate:
    /// a que soa igual, menos erros, a que só completa letras que faltaram, a
    /// mais frequente, a primeira em ordem alfabética.
    /// @return array{normalizada: string, original: string}|null
    public static function corrigir(string $termo, array $vocabulario): ?array
    {
        $tamanho = strlen($termo);
        if ($tamanho < 4 || preg_match('/\d/', $termo) === 1) {
            return null;
        }
        $tolerancia = $tamanho <= 7 ? 1 : 2;
        $som = self::fonetica($termo);

        $melhor = null;
        $melhorChave = null;
        foreach ($vocabulario as $normalizada => [$original, $frequencia]) {
            $normalizada = (string) $normalizada;
            if (abs(strlen($normalizada) - $tamanho) > 2) {
                continue;
            }
            $mesmoSom = self::fonetica($normalizada) === $som;
            $distancia = self::distancia($termo, $normalizada);
            if (!$mesmoSom) {
                // A primeira letra quase nunca é o erro — "decreto" não vira "secreto".
                // Mesmas letras em outra ordem ("estrupo" × "estupro") tolera 2 trocas.
                // Exceção: palavra longa em que só a primeira letra está errada
                // ("lroducao" → "producao").
                $limite = self::mesmasLetras($termo, $normalizada) ? max($tolerancia, 2) : $tolerancia;
                $soAPrimeira = $tamanho >= 8 && substr($termo, 1) === substr($normalizada, 1);
                if (($normalizada[0] !== $termo[0] && !$soAPrimeira) || $distancia > $limite || self::soMudaFlexao($termo, $normalizada)) {
                    continue;
                }
            }
            // Entre iguais, a que só completa letras que faltaram ("expresao" →
            // "expressao") ganha de uma que troca letras ("expresso").
            $chave = [$mesmoSom ? 0 : 1, $distancia, self::faltouLetra($termo, $normalizada) ? 0 : 1, -$frequencia, $normalizada];
            if ($melhorChave === null || $chave < $melhorChave) {
                $melhorChave = $chave;
                $melhor = $normalizada;
            }
        }

        return $melhor === null ? null : ['normalizada' => $melhor, 'original' => $vocabulario[$melhor][0]];
    }

    /// Chave de som de uma palavra normalizada: grafias que soam igual em
    /// português dão a mesma chave ("homicidio" = "omicidio", "defesa" =
    /// "defeza", "divorcio" = "divorsio"). Igual a `CorrecaoDeBusca.fonetica` no app.
    public static function fonetica(string $palavra): string
    {
        $p = preg_replace('/^h/', '', $palavra);
        $p = strtr($p, ['ph' => 'f', 'ch' => 'x', 'lh' => 'l', 'nh' => 'n', 'qu' => 'k', 'q' => 'k']);
        $p = preg_replace('/g(?=[ei])/', 'j', $p);
        $p = preg_replace('/gu(?=[ei])/', 'g', $p);
        $p = preg_replace('/sc(?=[ei])/', 's', $p);
        $p = preg_replace('/c(?=[ei])/', 's', $p);
        $p = strtr($p, ['c' => 'k', 'z' => 's', 'y' => 'i', 'w' => 'v', 'h' => '']);

        return preg_replace('/(.)\1+/', '$1', $p);
    }

    /// Erros de digitação entre duas palavras: letra a mais, a menos, trocada ou
    /// duas vizinhas invertidas ("estrupo" → "estupro" é 1). Distância de
    /// Damerau (alinhamento ótimo) — `levenshtein()` contaria a inversão como 2.
    public static function distancia(string $a, string $b): int
    {
        $n = strlen($a);
        $m = strlen($b);
        $d = [];
        for ($i = 0; $i <= $n; $i++) {
            $d[$i][0] = $i;
        }
        for ($j = 0; $j <= $m; $j++) {
            $d[0][$j] = $j;
        }
        for ($i = 1; $i <= $n; $i++) {
            for ($j = 1; $j <= $m; $j++) {
                $custo = $a[$i - 1] === $b[$j - 1] ? 0 : 1;
                $d[$i][$j] = min($d[$i - 1][$j] + 1, $d[$i][$j - 1] + 1, $d[$i - 1][$j - 1] + $custo);
                if ($i > 1 && $j > 1 && $a[$i - 1] === $b[$j - 2] && $a[$i - 2] === $b[$j - 1]) {
                    $d[$i][$j] = min($d[$i][$j], $d[$i - 2][$j - 2] + 1);
                }
            }
        }

        return $d[$n][$m];
    }

    private static function mesmasLetras(string $a, string $b): bool
    {
        return strlen($a) === strlen($b) && count_chars($a, 1) === count_chars($b, 1);
    }

    /// `$digitada` é `$palavra` com letras faltando (as que existem estão na ordem).
    private static function faltouLetra(string $digitada, string $palavra): bool
    {
        $j = 0;
        for ($i = 0, $n = strlen($palavra); $i < $n && $j < strlen($digitada); $i++) {
            if ($palavra[$i] === $digitada[$j]) {
                $j++;
            }
        }

        return $j === strlen($digitada) && strlen($palavra) > strlen($digitada);
    }

    /// Terminações de flexão (gênero, número, verbo). Trocar uma pela outra não
    /// é erro de digitação: "decreto" ausente num livro não deve virar "decreta".
    private const FLEXOES = ['a', 'e', 'o', 's', 'as', 'es', 'os', 'm', 'r', 'am', 'em', 'ar', 'er', 'ir',
        'do', 'da', 'dos', 'das', 'ao', 'oes', 'aes', 'al', 'ais', 'el', 'eis'];

    /// As duas palavras só diferem na terminação, e as duas terminações são de
    /// flexão ("decret|o" × "decret|a", "qualifica|do" × "qualifica|m"). Completar
    /// a palavra não conta: "corpu" → "corpus" continua valendo.
    public static function soMudaFlexao(string $a, string $b): bool
    {
        $comum = strspn($a ^ $b, "\0");
        $restoA = substr($a, $comum);
        $restoB = substr($b, $comum);

        return $restoA !== '' && $restoB !== ''
            && in_array($restoA, self::FLEXOES, true) && in_array($restoB, self::FLEXOES, true);
    }

    /// A consulta como o usuário deveria ter digitado: cada palavra corrigida
    /// na grafia das leis, e as demais com acento quando o vocabulário tem
    /// ("legitima defeza" → "legítima defesa").
    /// @param array<string, array{normalizada: string, original: string}> $correcoes palavra => correção
    public static function sugestao(array $palavras, array $correcoes, array $vocabulario): string
    {
        return implode(' ', array_map(
            static fn (string $p) => $correcoes[$p]['original'] ?? $vocabulario[$p][0] ?? $p,
            $palavras
        ));
    }
}
