#!/usr/bin/env python3
"""Código Eleitoral (Lei nº 4.737/1965) -> seed SQL.

Uso: python3 parse_codigo_eleitoral.py [--depurar] > seed_codigo_eleitoral.sql   (lê ce_raw.html)
A lógica está em parse_planalto.py; ver api/database/CONTEUDO.md.
"""
from parse_planalto import Lei, executar

executar(Lei(
    entrada="ce_raw.html",
    lei_id=7,
    slug="codigo-eleitoral-1965",
    titulo="Código Eleitoral (Lei nº 4.737, de 1965)",
    descricao="Institui o Código Eleitoral, atualizado até a última alteração compilada pelo Planalto.",
    fonte_url="https://www.planalto.gov.br/ccivil_03/leis/l4737compilado.htm",
    artigo_id_inicial=5110,        # próximo id livre depois do CTN (245 artigos: 4865-5109)
    dispositivo_id_inicial=10311,  # idem (567 dispositivos: 9744-10310)
))
