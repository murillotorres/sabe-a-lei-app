#!/usr/bin/env python3
"""Código de Defesa do Consumidor (Lei nº 8.078/1990) -> seed SQL.

Uso: python3 parse_cdc.py [--depurar] > seed_cdc.sql   (lê cdc_raw.html)
A lógica está em parse_planalto.py; ver api/database/CONTEUDO.md.
"""
from parse_planalto import Lei, executar

executar(Lei(
    entrada="cdc_raw.html",
    lei_id=8,
    slug="codigo-defesa-consumidor-1990",
    titulo="Código de Defesa do Consumidor (Lei nº 8.078, de 1990)",
    descricao="Dispõe sobre a proteção do consumidor, atualizado até a última alteração compilada pelo Planalto.",
    fonte_url="https://www.planalto.gov.br/ccivil_03/leis/l8078compilado.htm",
    artigo_id_inicial=5499,        # próximo id livre depois do Código Eleitoral (389 artigos: 5110-5498)
    dispositivo_id_inicial=11230,  # idem (919 dispositivos: 10311-11229)
))
