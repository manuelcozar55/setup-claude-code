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

# Construye un proyecto M gobernado VERDE y luego lo lleva a ESTADO INVALIDO:
# mas de una tarea en-curso a la vez. El productor real lo rechaza en el propio
# `task start` de la segunda (el lazo exige exactamente una en-curso), asi que
# el estado se fabrica volcando el `estado:` de una segunda tarea PENDIENTE a
# `en-curso` en TAREAS.md (la via limpia que el binario real deja construir). El
# productor real cae a rc1/invalid_state ("hay 2 tareas en-curso ...").
mrg_build_invalid_state() {
  local dir="$1"
  mrg_build_green "$dir" || return 1
  "$MCH_REAL" --path "$dir" task add "t2" --oracle 'true' >/dev/null 2>&1 || return 1
  python3 - "$dir/TAREAS.md" <<'PY' || return 1
import sys,re
p=sys.argv[1]; L=open(p,encoding="utf-8").read().split("\n")
in2=False; done=False
for i,l in enumerate(L):
    if re.match(r"^##\s+T-002\b",l): in2=True; continue
    if in2 and re.match(r"^##\s+T-\d",l): in2=False
    if in2 and re.match(r"^-\s*estado\s*:",l):
        L[i]=re.sub(r":.*$",": en-curso",l); done=True; break
open(p,"w",encoding="utf-8").write("\n".join(L))
sys.exit(0 if done else 1)
PY
}

# Construye un proyecto M gobernado VERDE y luego suprime la AUTORIDAD: retira la
# linea `oraculo:` de la tarea en-curso en TAREAS.md. La autoridad requiere el
# `--oracle` en el `task add` (el binario real lo exige al crear), asi que el
# estado "en-curso SIN oraculo" se fabrica quitando esa linea de la cola (la via
# limpia que el binario real deja construir). El productor real cae a
# rc1/authority_missing ("T-001 esta en-curso sin oraculo: sin autoridad no hay
# lazo").
mrg_build_authority_missing() {
  local dir="$1"
  mrg_build_green "$dir" || return 1
  python3 - "$dir/TAREAS.md" <<'PY' || return 1
import sys,re
p=sys.argv[1]; L=open(p,encoding="utf-8").read().split("\n")
in1=False; out=[]; dropped=False
for l in L:
    if re.match(r"^##\s+T-001\b",l): in1=True
    elif re.match(r"^##\s+T-\d",l): in1=False
    if in1 and re.match(r"^-\s*or[a\xe1]culo\s*:",l): dropped=True; continue
    out.append(l)
open(p,"w",encoding="utf-8").write("\n".join(out))
sys.exit(0 if dropped else 1)
PY
}

# Verifica el rc CRUDO del productor real en un dir gobernado (sanity: sin esto
# no sabriamos que M quedo en el estado esperado). Escribe el rc por stdout.
mrg_real_gate_rc() {
  local dir="$1"
  ( cd "$dir" && "$MCH_REAL" --path "$dir" task gate --json >/dev/null 2>&1; echo $? )
}
