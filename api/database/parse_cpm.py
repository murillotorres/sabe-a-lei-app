#!/usr/bin/env python3
"""Código Penal Militar (Decreto-Lei nº 1.001/1969) -> seed SQL.

Uso: python3 parse_cpm.py [--depurar] > seed_cpm.sql   (lê cpm_raw.html)
A lógica está em parse_planalto.py; ver api/database/CONTEUDO.md.
"""
from parse_planalto import Lei, executar

executar(Lei(
    entrada="cpm_raw.html",
    lei_id=11,
    slug="codigo-penal-militar-1969",
    titulo="Código Penal Militar (Decreto-Lei nº 1.001, de 1969)",
    descricao="Institui o Código Penal Militar, atualizado até a última alteração compilada pelo Planalto.",
    fonte_url="https://www.planalto.gov.br/ccivil_03/decreto-lei/del1001.htm",
    artigo_id_inicial=6739,        # próximo id livre depois do CPPM (719 artigos: 6020-6738)
    dispositivo_id_inicial=13848,  # idem (1.003 dispositivos: 12845-13847)
    inicio="Os Ministros da Marinha",
    rubricas=True,
    cabecalhos_sem_numeral=(r"^Disposi[cç][õo]es Finais$",),
))
