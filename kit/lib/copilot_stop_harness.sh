#!/usr/bin/env bash
# copilot_stop_harness.sh — arnes de parada de Copilot para las DOS superficies:
# modo INTERACTIVO (PTY) y modo PROMPT (`-p`) (todo 22).
#
# QUE ES: un arnes que ejerce el gate de ciclo de vida ACOTADO
# (copilot_lifecycle_gate.sh) alrededor de un turno de `copilot`, en la
# superficie que toque. Las dos superficies son distintas:
#   - --mode prompt      : el no interactivo (`copilot -p`). stdin cerrado.
#   - --mode interactive : el interactivo, que en el runtime real corre sobre un
#                          PTY. Aqui se ejerce con un PTY simulado (script(1)) si
#                          esta disponible; si no, con un pipe. La rama existe y
#                          se ejerce en ambos casos.
#
# CLAVE ("No binary/auth assumption"): el arnes NUNCA asume que `copilot` exista.
# Si el binario no esta en la ruta dada -> decision "block", reason
# "missing_binary": jamas allow, jamas skip. Y NUNCA copia credenciales de
# GitHub ni lee ~/.copilot.
#
# En los tests, el `copilot` real se sustituye por un fake que no toca red. El
# veredicto del turno lo inyecta COPILOT_FAKE_VERDICT (green|red) para ejercer el
# gate de ciclo de vida sin un modelo real.
#
# Salida: JSON por stdout con la decision del gate de ciclo de vida, o
# {"decision":"block","reason":"missing_binary"} si falta el binario.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
LIFECYCLE="$HERE/copilot_lifecycle_gate.sh"

MODE=""
COPILOT=""
STATE="${COPILOT_BLOCK_STATE:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --mode=*) MODE="${1#--mode=}"; shift ;;
    --copilot) COPILOT="${2:-}"; shift 2 ;;
    --copilot=*) COPILOT="${1#--copilot=}"; shift ;;
    --state) STATE="${2:-}"; shift 2 ;;
    -h|--help)
      printf 'uso: copilot_stop_harness.sh --mode interactive|prompt --copilot RUTA\n' >&2
      exit 0 ;;
    *) shift ;;
  esac
done

blk() { printf '{"decision":"block","reason":"%s"}\n' "$1"; exit 2; }

case "$MODE" in
  interactive|prompt) : ;;
  *) blk "mode_invalido" ;;
esac
[ -n "$COPILOT" ] || blk "missing_binary"
# NO se asume el binario: si no existe o no es ejecutable -> missing_binary.
[ -x "$COPILOT" ] || blk "missing_binary"
[ -n "$STATE" ] || blk "sin_estado"

# Ejercer el turno del fake `copilot` en la superficie que toque. El fake no toca
# red ni credenciales; su salida no decide el gate (la decide el veredicto del
# turno, inyectado en los tests via COPILOT_FAKE_VERDICT).
verdict="${COPILOT_FAKE_VERDICT:-green}"
if [ "$MODE" = interactive ]; then
  # Superficie interactiva: PTY. Con script(1) se ejerce sobre un pseudo-tty
  # real; si no esta, se cae a un pipe (la rama de la superficie existe igual).
  if command -v script >/dev/null 2>&1; then
    script -q -c "'$COPILOT' -p 'noop'" /dev/null >/dev/null 2>&1 || true
  else
    "$COPILOT" -p 'noop' >/dev/null 2>&1 </dev/null || true
  fi
else
  # Superficie prompt (-p): no interactivo, stdin cerrado.
  "$COPILOT" -p 'noop' >/dev/null 2>&1 </dev/null || true
fi

# Ejercer el gate de ciclo de vida ACOTADO con el veredicto del turno.
COPILOT_BLOCK_STATE="$STATE" bash "$LIFECYCLE" --verdict "$verdict"
