#!/usr/bin/env bash
# test_presupuesto_contexto.sh — tope de contexto por canal (ADR 018). Sin red. Mide con
# scripts/contexto-base.sh --peor (nucleo.md de 24 KB, ruta de ~200 chars, dueño ajeno, todos los avisos
# encendidos, la entrada sintética de cada guard) y falla si un canal pasa de su tope. Los topes son la medida
# del 20-oct (knowledge/COST-LOG.md, «Presupuesto por canal») + 10 %, subida a la centena.
# Subir un tope exige repetir la medida y apuntarla en COST-LOG.md: no se sube «por si acaso».
set -uo pipefail
unset CLAUDE_PID   # bajo Claude Code se hereda y daría ranura de sesión a los hooks de ~
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$(cd "$HERE/../.." && pwd)"
pass=0; fail=0

# prefijo de la fila de contexto-base.sh | tope en caracteres
TOPES='instrucciones globales|6900
SessionStart compact|9500
SessionStart startup|9500
SessionStart clear|9500
SessionStart resume|9500
SessionStart memoria|100
PostToolUse nucleo-nudge|600
Stop context-gauge|400
write-guard (fichero nuevo|500
write-guard (secretos|600
stale-read-guard|800
narthex|1400
UserPromptSubmit|0
agentes: suma|2600
bloque de agentes|800
skills: suma|900'
TOPE_AGENTE=500   # la mayor description de un agente

TAB=$(bash "$REPO/scripts/contexto-base.sh" --peor 2>&1) || { echo "NOT ok - contexto-base.sh --peor falla"; echo "$TAB" | tail -n 5; exit 1; }
cifra() { awk -v p="$1" 'index($0, p) == 1 { print $(NF-1); exit }' <<<"$TAB"; }

# juzga: canal cifra tope -> 0 si cabe. Pasarse es FAIL con el canal, la cifra y el tope.
juzga() { [ -n "$2" ] && [ "$2" -le "$3" ]; }
ck() { # canal cifra tope
  if juzga "$1" "$2" "$3"; then echo "ok - $1: $2 <= $3"; pass=$((pass+1))
  else echo "NOT ok - $1: ${2:-sin medida} pasa del tope $3"; fail=$((fail+1)); fi
}
while IFS='|' read -r canal tope; do ck "$canal" "$(cifra "$canal")" "$tope"; done <<<"$TOPES"

mayor=$(awk '/^agente /{ if ($(NF-1) > m) m = $(NF-1) } END { print m }' <<<"$TAB")
ck "agente con la mayor description" "$mayor" "$TOPE_AGENTE"
if [ "$(cifra 'bloque de agentes')" -gt 0 ]; then
  echo 'ok - registro lleno genera bloque de agentes'; pass=$((pass+1))
else echo 'NOT ok - registro lleno no genera bloque de agentes'; fail=$((fail+1)); fi

# Suma por evento. La doc de hooks (code.claude.com/docs/en/hooks, «Output limits», 2026-10-26) fija 10 000 chars
# por cadena de additionalContext/stdout, medida cada una por separado aunque varios hooks corran en el mismo
# evento; lo que pasa va a un fichero con vista previa de 2 000 y sin ajuste. Esta suma es un presupuesto propio y
# más estricto del kit: lo que un evento puede meter de golpe en la ventana cabe en un solo tope. Se suman las filas
# de TAB que disparan juntas (las alternativas de un mismo evento cuentan por su máximo, no se suman).
TOPE_EVENTO=10000
# evento | filas que disparan juntas (+) con alternativas (/): prefijos de TAB
EVENTOS='SessionStart|SessionStart memoria+SessionStart compact/SessionStart startup/SessionStart clear/SessionStart resume
PostToolUse|PostToolUse nucleo-nudge+narthex
PreToolUse|write-guard (fichero nuevo/write-guard (secretos/stale-read-guard
Stop|Stop context-gauge'
suma_evento() { # tabla spec -> suma de los hooks que disparan juntos
  local tab=$1 spec=$2 total=0 grupo alt m v
  while IFS= read -r grupo; do
    m=0
    while IFS= read -r alt; do
      v=$(awk -v p="$alt" 'index($0, p) == 1 { print $(NF-1); exit }' <<<"$tab"); v=${v:-0}
      [ "$v" -gt "$m" ] && m=$v
    done < <(tr '/' '\n' <<<"$grupo")
    total=$((total + m))
  done < <(tr '+' '\n' <<<"$spec")
  echo "$total"
}
while IFS='|' read -r ev spec; do ck "evento $ev: suma de sus hooks" "$(suma_evento "$TAB" "$spec")" "$TOPE_EVENTO"; done <<<"$EVENTOS"
# falsable: dos hooks del mismo evento que juntos pasan del tope hacen caer la comprobación; uno solo, no
FIX=$'hook-a (fixture)   6000   6000\nhook-b (fixture)   5000   5000'
if juzga evento "$(suma_evento "$FIX" 'hook-a+hook-b')" "$TOPE_EVENTO" || ! juzga evento "$(suma_evento "$FIX" 'hook-a')" "$TOPE_EVENTO"
then echo "NOT ok - falsable: la suma por evento no distingue 6000+5000 de 6000"; fail=$((fail+1))
else echo "ok - falsable: dos hooks de 6000 y 5000 en un evento dan FAIL; uno solo, ok"; pass=$((pass+1)); fi

# W6: SessionStart en ~ con la ranura de sesión llena (nucleo al tope) y el índice lleno (15 raíces, 2 500 chars):
# la frase + la ranura + el índice caben en el tope del canal: nucleo_tope no corta y el índice llega hasta su cierre.
# El «[recortado]» que el índice pone en su propio tope de 2 500 es por diseño y no cuenta aquí.
TS=$(mktemp -d); sleep 300 & SP=$!
(
  export HOME=$TS/h GIT_CEILING_DIRECTORIES=$TS LC_ALL=C.UTF-8; unset NUCLEO_REGISTRO CLAUDE_PROJECT_DIR
  mkdir -p "$HOME/.claude/estado"
  L=$(printf 'x%.0s' $(seq 1 78))
  for i in $(seq 1 15); do
    r=$TS/proyecto-con-nombre-largo-$i; mkdir -p "$r/.claude/estado"; printf '%s\n' "$r" >>"$HOME/.claude/estado/raices"
    printf '# N\n## Objetivo\n%s\n## Paso actual\n%s\n' "$L" "$L" >"$r/.claude/estado/nucleo.md"
  done
  { for s in Objetivo Invariantes Plan "Paso actual" "Siguiente acción" Pendientes "Comandos de verificación" "Ficheros tocados"; do
      printf '## %s\n' "$s"; for _ in 1 2 3 4 5 6 7 8; do printf '%s\n' "- $L$L"; done; done; } >"$TS/b.md"
  cd "$HOME" && CLAUDE_PID=$SP bash "$REPO/kit/claude/bin/handoff" --desde "$TS/b.md" >/dev/null 2>&1
  jq -cn --arg c "$HOME" '{cwd:$c,session_id:"s",source:"clear"}' | CLAUDE_PID=$SP bash "$REPO/kit/claude/hooks/session-start-clear.sh" \
    | jq -r '.hookSpecificOutput.additionalContext // empty' >"$TS/ctx"
)
kill "$SP" 2>/dev/null; wait "$SP" 2>/dev/null
ck "SessionStart ~ con ranura e índice llenos" "$(wc -m <"$TS/ctx" | tr -d ' ')" 9500
if grep -q '<nucleo-datos fuente=".*sesiones/' "$TS/ctx" && [ "$(tail -n 1 "$TS/ctx")" = '</indice-tareas>' ]
then echo "ok - ~ con ranura: nucleo de la sesión e índice enteros"; pass=$((pass+1))
else echo "NOT ok - ~ con ranura: falta el nucleo o el índice, o se recortó"; fail=$((fail+1)); fi
rm -r -f -- "$TS"

# falsable: un caracter por encima del tope tiene que dar FAIL, y en el tope exacto, ok
while IFS='|' read -r canal tope; do
  if juzga "$canal" $((tope + 1)) "$tope" || ! juzga "$canal" "$tope" "$tope"; then
    echo "NOT ok - falsable: $canal no distingue tope+1 de tope"; fail=$((fail+1))
  else echo "ok - falsable: $canal da FAIL con tope+1"; pass=$((pass+1)); fi
done <<<"$TOPES"

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
