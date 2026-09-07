#!/usr/bin/env bash
# mch_real_governed.sh — util compartida para construir estados GOBERNADOS REALES
# de M y ejercer los tres puentes de S (Claude Stop, Codex/Copilot gate manual)
# contra el PRODUCTOR REAL `mch task gate --json`, no contra fakes.
#
# POR QUE EXISTE (hallazgo 2 del orquestador, medido): las suites de puente sólo
# consultaban al productor real en el camino `ungoverned` (rc3/ALLOW). TODAS las
# clausulas gobernadas (rc0 verde, rc1 rojo) se probaban con fakes que la propia
# S fabrica. Esta util cierra ese hueco: crea un proyecto M de verdad, lo lleva a
# VERDE (rc0) y a ROJO (rc1) con el binario real, y expone helpers para que cada
# suite afirme que el puente decide igual contra el productor real que contra el
# fake — cerrando el bucle productor↔consumidor entre repos de verdad.
#
# Contrato de uso (se sourcea desde una suite que ya definio MCH_REAL, T, ck,
# decision):
#   mrg_build_green DIR   -> deja en DIR un proyecto M gobernado con run VERDE
#   mrg_build_red   DIR   -> deja en DIR un proyecto M gobernado en ROJO (start sin run)
# Ambas devuelven rc0 si el productor real quedo en el estado esperado, rc!=0 si
# no se pudo (p.ej. git ausente): la suite trata rc!=0 como fallo, nunca como skip.
#
# NO ejecuta shell del proyecto salvo el oraculo 'true' sellado por el propio M
# (que es como M gobierna). No toca el ~/.codex, ~/.claude ni el M real: todo va
# a directorios temporales que crea la suite.

# Construye un proyecto M gobernado y lo deja en VERDE (gate rc0/verified).
mrg_build_green() {
  local dir="$1"
  ( set -e
    mkdir -p "$dir"
    cd "$dir"
    git init -q
    printf 'x\n' > README.md
    git add -A && git commit -qm init
    "$MCH_REAL" --path "$dir" init            >/dev/null 2>&1
    "$MCH_REAL" --path "$dir" oracle --set 'true' >/dev/null 2>&1
    "$MCH_REAL" --path "$dir" task init        >/dev/null 2>&1
    "$MCH_REAL" --path "$dir" task add "t" --oracle 'true' >/dev/null 2>&1
    "$MCH_REAL" --path "$dir" task start T-001  >/dev/null 2>&1
    "$MCH_REAL" --path "$dir" task run   T-001  >/dev/null 2>&1
  )
}

# Construye un proyecto M gobernado y lo deja en ROJO (gate rc1/governed_red):
# tarea en-curso SIN run verde tras el ultimo start.
mrg_build_red() {
  local dir="$1"
  ( set -e
    mkdir -p "$dir"
    cd "$dir"
    git init -q
    printf 'x\n' > README.md
    git add -A && git commit -qm init
    "$MCH_REAL" --path "$dir" init            >/dev/null 2>&1
    "$MCH_REAL" --path "$dir" oracle --set 'true' >/dev/null 2>&1
    "$MCH_REAL" --path "$dir" task init        >/dev/null 2>&1
    "$MCH_REAL" --path "$dir" task add "t" --oracle 'true' >/dev/null 2>&1
    "$MCH_REAL" --path "$dir" task start T-001  >/dev/null 2>&1
  )
}

# Construye un proyecto M gobernado VERDE y luego ROMPE la AUTORIDAD del gate
# declarando gate_authority_version=99 en state.json: el productor real cae a
# rc1/authority_incompatible (habla contrato 2, el estado declara 99).
mrg_build_authbreak() {
  local dir="$1"
  mrg_build_green "$dir" || return 1
  python3 - "$dir/.agents/state.json" <<'PY' || return 1
import json,sys
p=sys.argv[1]
d=json.load(open(p))
d["gate_authority_version"]=99
json.dump(d,open(p,"w"))
PY
}

# Construye un proyecto M gobernado VERDE y luego deja la sonda del oraculo SIN
# sello VERDE (probe.ok=false): autoridad presente pero no confiable. El productor
# real cae a rc1/authority_untrusted.
mrg_build_untrusted() {
  local dir="$1"
  mrg_build_green "$dir" || return 1
  python3 - "$dir/.agents/state.json" <<'PY' || return 1
import json,sys
p=sys.argv[1]
d=json.load(open(p))
pr=d.get("probe") or {}
pr["ok"]=False
pr["rc"]=1
d["probe"]=pr
json.dump(d,open(p,"w"))
PY
}

# Verifica el rc CRUDO del productor real en un dir gobernado (sanity: sin esto
# no sabriamos que M quedo en el estado esperado). Escribe el rc por stdout.
mrg_real_gate_rc() {
  local dir="$1"
  ( cd "$dir" && "$MCH_REAL" --path "$dir" task gate --json >/dev/null 2>&1; echo $? )
}
