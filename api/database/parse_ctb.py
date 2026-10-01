#!/usr/bin/env python3
"""Código de Trânsito Brasileiro (Lei nº 9.503/1997) -> seed SQL.

Uso: python3 parse_ctb.py [--depurar] > seed_ctb.sql   (lê ctb_raw.html)
A lógica está em parse_planalto.py; ver api/database/CONTEUDO.md.
"""
from parse_planalto import Lei, executar

executar(Lei(
    entrada="ctb_raw.html",
    lei_id=9,
    slug="codigo-transito-brasileiro-1997",
    titulo="Código de Trânsito Brasileiro (Lei nº 9.503, de 1997)",
    descricao="Institui o Código de Trânsito Brasileiro, atualizado até a última alteração compilada pelo Planalto.",
    fonte_url="https://www.planalto.gov.br/ccivil_03/leis/l9503compilado.htm",
    artigo_id_inicial=5629,        # próximo id livre depois do CDC (130 artigos: 5499-5628)
    dispositivo_id_inicial=11572,  # idem (342 dispositivos: 11230-11571)
))
