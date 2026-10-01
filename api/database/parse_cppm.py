#!/usr/bin/env python3
"""Código de Processo Penal Militar (Decreto-Lei nº 1.002/1969) -> seed SQL.

Uso: python3 parse_cppm.py [--depurar] > seed_cppm.sql   (lê cppm_raw.html)
A lógica está em parse_planalto.py; ver api/database/CONTEUDO.md.
"""
from parse_planalto import Lei, executar

executar(Lei(
    entrada="cppm_raw.html",
    lei_id=10,
    slug="codigo-processo-penal-militar-1969",
    titulo="Código de Processo Penal Militar (Decreto-Lei nº 1.002, de 1969)",
    descricao="Institui o Código de Processo Penal Militar, atualizado até a última alteração compilada pelo Planalto.",
    fonte_url="https://www.planalto.gov.br/ccivil_03/decreto-lei/del1002.htm",
    artigo_id_inicial=6020,        # próximo id livre depois do CTB (391 artigos: 5629-6019)
    dispositivo_id_inicial=12845,  # idem (1.273 dispositivos: 11572-12844)
    inicio="Os Ministros da Marinha",
    rubricas=True,
    cabecalhos_sem_numeral=(r"^Disposi[cç][õo]es Finais e Transit[óo]rias$",),
))
