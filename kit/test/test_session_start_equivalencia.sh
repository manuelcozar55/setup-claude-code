#!/usr/bin/env bash
# test_session_start_equivalencia.sh — la salida EXACTA (stdout y rc) de lo que corre SessionStart, por `source` y con
# fixtures de estado representativos, contra los ficheros de kit/test/golden/session-start/. Existe para poder fundir
# session-start-clear.sh y session-start-compact.sh en session-start-estado.sh (B-008) sin cambiar lo que recibe el
# modelo: los golden se capturaron con los tres hooks de antes, byte a byte.
# Por source, el arnés lanza (settings.json): session-start.sh siempre (texto plano: la línea de memoria) y, además,
# session-start-estado.sh (JSON; antes -clear con startup|clear|resume y -compact con compact). Cada caso guarda los
# dos flujos por separado, porque el arnés los recibe por separado.
# GOLDEN_ACTUALIZAR=1 reescribe los golden desde los hooks actuales: no lo uses para «arreglar» un rojo, un rojo es
# un cambio de lo que recibe el modelo.
# Sin red; HOME falso en un mktemp que se borra; fechas y rutas fijas para que la salida sea reproducible.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; H="$HERE/../claude/hooks"; GOLD="$HERE/golden/session-start"
T=$(mktemp -d -t scc-ssq.XXXXXX); trap 'kill $(jobs -p) 2>/dev/null; rm -rf -- "$T"' EXIT
export HOME=$T/home GIT_CEILING_DIRECTORIES=$T LC_ALL=C.UTF-8 TZ=UTC
export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
unset CLAUDE_PID CLAUDE_PROJECT_DIR CLAUDE_CONFIG_DIR CLAUDE_HOME CLAUDE_CODE_SESSION_ID NUCLEO_GATE \
  CLAUDE_CODE_AUTO_COMPACT_WINDOW CLAUDE_CODE_SESSION_ATTENDED CLAUDE_CODE_ENTRYPOINT OPENRIG_NODE_ID \
  OPENRIG_SESSION_NAME OPENRIG_OCCUPANT_GENERATION
mkdir -p "$HOME" "$T/out" "$T/bin"
# El aviso tras compactar nombra `handoff` a secas si está en el PATH y con su ruta si no: se fija aquí, o el golden
# depende de si la máquina que corre el test tiene el kit instalado (el runner de CI no lo tiene).
printf '#!/bin/sh\n' >"$T/bin/handoff"; chmod +x "$T/bin/handoff"; export PATH="$T/bin:$PATH"
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1"; FAIL=1; fi; }
G() { git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }

NUCLEO=$'# Estado\n## Objetivo\nhacer X\n## Invariantes\n- no tocar Y\n## Paso actual\nPASO-VIVO\n## Siguiente acción\nrun-tests\n## Pendientes\n- [ ] PENDIENTE-1\n## Comandos de verificación\nmake test'
repo() { mkdir -p "$1"; git -C "$1" init -q; G "$1" commit -q --allow-empty -m base; }
memoria() { # memoria <cwd> <entradas>: el MEMORY.md que busca session-start.sh para ese cwd
  local d i; d="$HOME/.claude/projects/$(printf '%s' "$1" | sed 's/[^A-Za-z0-9]/-/g')/memory"
  mkdir -p "$d"; : >"$d/MEMORY.md"; for i in $(seq 1 "$2"); do echo "- [m$i](m$i.md) — memoria $i" >>"$d/MEMORY.md"; done; }
viejo() { touch -d '2020-01-01 00:00:00 UTC' "$1"; }

# Casos: repo con nucleo y memoria; sin memoria; sin nucleo; plantilla; ESTADO.md; ~ ; memoria larga; desatendido.
R1=$T/r1; repo "$R1"; mkdir -p "$R1/.claude/estado/checkpoints"; printf '%s\n' "$NUCLEO" >"$R1/.claude/estado/nucleo.md"; viejo "$R1/.claude/estado/nucleo.md"
memoria "$R1" 3
SIDH=$(printf '%s' c1 | sha256sum | cut -d' ' -f1)
printf 'CHECKPOINT-DE-C1\nrama: main\n' >"$R1/.claude/estado/checkpoints/checkpoint-compact-$SIDH.md"
R2=$T/r2; repo "$R2"; mkdir -p "$R2/.claude/estado"; printf '%s\n' "$NUCLEO" >"$R2/.claude/estado/nucleo.md"
R3=$T/r3; repo "$R3"
R4=$T/r4; repo "$R4"; mkdir -p "$R4/.claude/estado"; printf '# Estado\n## Objetivo\n\n## Invariantes\n\n## Siguiente acción\n\n' >"$R4/.claude/estado/nucleo.md"
R5=$T/r5; repo "$R5"; printf '# Estado del proyecto\nESTADO-PLANO-MARCA\n' >"$R5/ESTADO.md"
R7=$T/r7; repo "$R7"; mkdir -p "$R7/.claude/estado"; printf '%s\n' "$NUCLEO" >"$R7/.claude/estado/nucleo.md"; memoria "$R7" 70
R8=$T/r8; repo "$R8"; mkdir -p "$R8/.claude/estado"; printf '%s\n' "$NUCLEO" >"$R8/.claude/estado/nucleo.md"
mkdir -p "$HOME/.claude/estado"

# corre <caso> <cwd> <sid> <source> [VAR=valor…] : añade al fichero del caso los dos flujos y los rc de esa source.
corre() {
  local cwd=$2 sid=$3 src=$4 ev est m e rm re f=$T/out/$1.txt; shift 4
  ev=$(jq -cn --arg c "$cwd" --arg s "$sid" --arg src "$src" '{cwd:$c,session_id:$s,source:$src,transcript_path:"",hook_event_name:"SessionStart"}')
  est=session-start-estado.sh
  m=$(cd "$cwd" && env "$@" bash "$H/session-start.sh" <<<"$ev" 2>/dev/null); rm=$?
  e=$(cd "$cwd" && env "$@" bash "$H/$est" <<<"$ev" 2>/dev/null); re=$?
  { printf '=== %s memoria rc=%s ===\n%s\n=== %s estado rc=%s ===\n%s\n' "$src" "$rm" "$m" "$src" "$re" "$e"; } >>"$f"
}
# resume con la caché caducada: los campos de contexto que manda Claude Code desde v2.1.251.
corre_caducado() {
  local cwd=$2 sid=$3 ev m e f=$T/out/$1.txt
  ev=$(jq -cn --arg c "$cwd" --arg s "$sid" '{cwd:$c,session_id:$s,source:"resume",context_tokens:150000,prompt_cache_likely_expired:true,hook_event_name:"SessionStart"}')
  m=$(cd "$cwd" && bash "$H/session-start.sh" <<<"$ev" 2>/dev/null); e=$(cd "$cwd" && bash "$H/session-start-estado.sh" <<<"$ev" 2>/dev/null)
  printf '=== resume-caducado memoria rc=0 ===\n%s\n=== resume-caducado estado rc=0 ===\n%s\n' "$m" "$e" >>"$f"
}

for src in startup clear resume compact; do
  corre proyecto-con-memoria "$R1" c1 "$src"
  corre proyecto-sin-memoria "$R2" c2 "$src"
  corre proyecto-sin-nucleo "$R3" c3 "$src"
  corre nucleo-plantilla "$R4" c4 "$src"
  corre estado-md "$R5" c5 "$src"
  corre memoria-larga "$R7" c7 "$src"
  corre desde-home "$HOME" c6 "$src"
  corre desatendido "$R8" c8 "$src" CLAUDE_CODE_SESSION_ATTENDED=0
done
corre_caducado proyecto-con-memoria "$R1" c1
corre_caducado desde-home "$HOME" c6

# Segunda sesión viva sobre el mismo repo: aviso de dueño ajeno (la dueña es c9a, con un proceso vivo).
R9=$T/r9; repo "$R9"; mkdir -p "$R9/.claude/estado"; printf '%s\n' "$NUCLEO" >"$R9/.claude/estado/nucleo.md"
sleep 300 & PA=$!; sleep 300 & PB=$!
corre dueno-ajeno "$R9" c9a startup CLAUDE_PID=$PA
corre dueno-ajeno "$R9" c9b startup CLAUDE_PID=$PB
corre dueno-ajeno "$R9" c9b compact CLAUDE_PID=$PB
kill "$PA" "$PB" 2>/dev/null

# Lo que cambia entre ejecuciones (ruta del mktemp, también codificada como la codifica Claude Code, y la hora de
# <git-hechos>) fuera de los golden.
TC=$(printf '%s' "$T" | sed 's/[^A-Za-z0-9]/-/g')
for f in "$T"/out/*.txt; do sed -i -e "s|$T|@T@|g" -e "s|$TC|@T@|g" -e 's|calculado=\\"[^\\]*\\"|calculado=\\"@HORA@\\"|g' "$f"; done

if [ "${GOLDEN_ACTUALIZAR:-}" = 1 ]; then
  mkdir -p "$GOLD"; cp "$T"/out/*.txt "$GOLD/"; echo "golden actualizados en $GOLD"; exit 0
fi
n=0
for f in "$T"/out/*.txt; do
  b=$(basename "$f"); n=$((n+1))
  if [ -f "$GOLD/$b" ] && cmp -s "$f" "$GOLD/$b"; then ok "equivalencia $b" 1 1
  else ok "equivalencia $b" 1 0; [ -f "$GOLD/$b" ] && diff "$GOLD/$b" "$f" | head -20 | cut -c1-300; fi
done
ok "no sobra ningún golden" "$(find "$GOLD" -name '*.txt' | wc -l | tr -d ' ')" "$n"
# Los fixtures se ven vivos: cada rama que se compara tiene que haber emitido algo (si no, el test compararía vacío con vacío).
ok "hay estado inyectado tras clear" "$(grep -c 'nucleo-datos fuente' "$T/out/proyecto-con-memoria.txt")" "$(grep -c 'nucleo-datos fuente' "$GOLD/proyecto-con-memoria.txt")"
ok "la línea de memoria sale" "$(grep -c 'Memory: 3 entradas' "$T/out/proyecto-con-memoria.txt")" 5
ok "el aviso de dueño ajeno sale" "$(grep -c 'otra sesión dueña' "$T/out/dueno-ajeno.txt")" 1
ok "el aviso de edad tras compactar sale" "$(grep -c 'Aviso del hook' "$T/out/proyecto-con-memoria.txt")" 1
ok "el aviso de caché caducada sale" "$(grep -c 'caché caducada' "$T/out/proyecto-con-memoria.txt")" 1
exit "$FAIL"
