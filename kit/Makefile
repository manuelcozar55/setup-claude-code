# Este Makefile existe por un falso verde, no por comodidad.
#
# El Quick start deja al lector dentro de kit/ y le manda `make test`. Sin Makefile
# aqui, make encontraba el DIRECTORIO kit/test, lo tomaba por un target ya construido
# y respondia "Nothing to be done for 'test'" con exit 0: un oraculo que devuelve 0
# sin ejecutar nada, en un repo cuya tesis es justo lo contrario. Delegar en la raiz
# es la forma mas corta de que ese comando signifique lo que el lector cree.
.DEFAULT_GOAL := test
.PHONY: help install test doctor evals-paid

help install test doctor evals-paid:
	@$(MAKE) -C .. $@
