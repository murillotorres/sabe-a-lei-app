#!/usr/bin/env python3
"""Código Tributário Nacional (Lei nº 5.172/1966) -> seed SQL.

Uso: python3 parse_ctn.py [--depurar] > seed_ctn.sql   (lê ctn_raw.html)
A lógica está em parse_planalto.py; ver api/database/CONTEUDO.md.
"""
from parse_planalto import Lei, executar

executar(Lei(
    entrada="ctn_raw.html",
    lei_id=6,
    slug="codigo-tributario-nacional-1966",
    titulo="Código Tributário Nacional (Lei nº 5.172, de 1966)",
    descricao="Dispõe sobre o Sistema Tributário Nacional e institui normas gerais de direito tributário, atualizado até a última alteração compilada pelo Planalto.",
    fonte_url="https://www.planalto.gov.br/ccivil_03/leis/l5172compilado.htm",
    artigo_id_inicial=4865,        # próximo id livre depois do CPP (853 artigos: 4012-4864)
    dispositivo_id_inicial=9744,   # idem (1.294 dispositivos: 8450-9743)
    cabecalhos_sem_numeral=(r"^Disposi[cç][aã]o Preliminar$", r"^Disposi[cç][õo]es Finais e Transit[óo]rias$"),
))
