#!/bin/bash
# test_optional_capabilities.sh — la CLAUDE.md que el kit PROYECTA en una maquina
# ajena no puede prescribir capacidades personales de terceros (las skills
# `deep-change`/`superpowers`) como si estuvieran instaladas, sin declararlas
# opcionales ni ofrecer un camino cuando no lo estan.
#
# Por que existe (F-03/RT-03, boundary del todo 17): el kit vendoriza un CLAUDE.md
# que en "Operating loop" ordena `run the deep-change skill ... composing the
# superpowers skills`. En la maquina del autor esas skills existen; en la maquina
# limpia donde install.sh proyecta este fichero, no tienen por que. Prescribir un
# metodo obligatorio apoyado en un plugin ausente deja al usuario nuevo con una
# instruccion que no puede cumplir y sin fallback declarado. La base del kit
# (guards, Sentinel, agentes) SI funciona sin esos terceros -- hay un test que lo
# prueba en maquina pelada (test_clean_install_resilience.sh) -- asi que la doc
# debe decir que esa capa es opcional. Esta suite lo falsifica.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
DOC="$KIT/claude/CLAUDE.md"
pass=0; fail=0

check() { # $1 desc  $2 = 0 si OK
  if [ "$2" -eq 0 ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1"; fi
}

# El bloque que prescribe deep-change/superpowers tiene que marcar esas skills como
# opcionales/terceros con un camino alternativo. Se mide por la co-ocurrencia de la
# prescripcion con una palabra de opcionalidad en el MISMO documento proyectado.
grep -qiE 'deep-change|superpowers' "$DOC"; has_prescription=$?
grep -qiE 'optional|opcional|if (it is |you have )?installed|when installed|si (la|las|el|los) .*(instal|dispon)|not installed|ausente|fallback' "$DOC"; has_optionality=$?

if [ "$has_prescription" -eq 0 ]; then
  check "la CLAUDE.md proyectada declara opcionales las skills de terceros que prescribe" "$has_optionality"
else
  check "no hay prescripcion de terceros que exija declaracion de opcionalidad" 0
fi

echo "PASS=$pass FAIL=$fail SKIP=0"
[ "$fail" -eq 0 ]
