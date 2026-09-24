#!/usr/bin/env python3
"""Código de Processo Penal (Decreto-Lei nº 3.689/1941) -> seed SQL.

Uso: python3 parse_cpp.py [--depurar] > seed_cpp.sql   (lê cpp_raw.html)
A lógica está em parse_planalto.py; ver api/database/CONTEUDO.md.
"""
from parse_planalto import Lei, executar

executar(Lei(
    entrada="cpp_raw.html",
    lei_id=5,
    slug="codigo-processo-penal-1941",
    titulo="Código de Processo Penal (Decreto-Lei nº 3.689, de 1941)",
    descricao="Institui o Código de Processo Penal, atualizado até a última alteração compilada pelo Planalto.",
    fonte_url="https://www.planalto.gov.br/ccivil_03/decreto-lei/del3689.htm",
    artigo_id_inicial=4012,        # max(artigos.id) do CPC (4011) + 1
    dispositivo_id_inicial=8450,   # max(artigo_dispositivos.id) do CPC (8449) + 1
))
