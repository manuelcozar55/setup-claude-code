#!/usr/bin/env bash
# copilot_lifecycle_gate.sh — el gate de CICLO DE VIDA ACOTADO de Copilot (todo
# 22). Modela agentStop/subagentStop como BOUNDED ENFORCEMENT.
#
# QUE ES: Copilot SI expone un ciclo de vida nativo — un hook de agentStop/
# subagentStop que devuelve `decision:"block"` fuerza otro turno. Pero es
# ACOTADO: tras 8 respuestas de bloqueo CONSECUTIVAS, Copilot fuerza la parada
# pase lo que pase. Este gate implementa exactamente esa semantica sobre un
# contador PERSISTENTE por sesion (COPILOT_BLOCK_STATE):
#
#   1. --verdict green  -> ALLOW y RESET del contador a 0 (turno cerro limpio).
#   2. --verdict red     con contador < 8 -> BLOCK e incrementa (bloqueo n/8).
#   3. --verdict red     con contador == 8 -> STOP FORZADO (el tope se agota; ya
#      no bloquea, la parada la impone Copilot). Se marca "forced": true.
#   4. Tras un STOP forzado, un green vuelve a resetear a 0.
#
# El decision "stop" es la traduccion honesta del degradado: NUNCA se emite
# "enforced". Por eso ambas superficies de Copilot son profile-certified, jamas
# lifecycle-enforced.
#
# Salida: JSON por stdout {"decision":"allow"|"block"|"stop","count":N,
# "cap":8,"forced":true|false,"reason":...}. rc 0 en allow/stop, rc 2 en block
# (block fuerza continuacion, como el hook nativo).
set -uo pipefail

CAP=8
VERDICT=""
STATE="${COPILOT_BLOCK_STATE:-}"
while [ $# -gt 0 ]; do
  case "$1" in
    --verdict) VERDICT="${2:-}"; shift 2 ;;
    --verdict=*) VERDICT="${1#--verdict=}"; shift ;;
    --state) STATE="${2:-}"; shift 2 ;;
    --from-hook) shift 2 ;;
    -h|--help)
      printf 'uso: copilot_lifecycle_gate.sh --verdict green|red [--state RUTA]\n' >&2
      printf '  El contador de bloqueos consecutivos vive en COPILOT_BLOCK_STATE o --state.\n' >&2
      exit 0 ;;
    *) shift ;;
  esac
done

if command -v jq >/dev/null 2>&1; then EMIT=jq
elif command -v python3 >/dev/null 2>&1; then EMIT=py; else EMIT=no; fi

emit() { # decision count forced reason  -> stdout JSON
  local d="$1" c="$2" f="$3" r="$4"
  case "$EMIT" in
    jq) jq -n --arg d "$d" --argjson c "$c" --argjson f "$f" --argjson cap "$CAP" --arg r "$r" \
          '{decision:$d,count:$c,cap:$cap,forced:$f,reason:$r}' ;;
    py) python3 -c 'import json,sys
print(json.dumps({"decision":sys.argv[1],"count":int(sys.argv[2]),"cap":int(sys.argv[5]),"forced":sys.argv[3]=="true","reason":sys.argv[4]},ensure_ascii=False))' \
          "$d" "$c" "$f" "$r" "$CAP" ;;
    *)  printf '{"decision":"%s","count":%s,"cap":%s,"forced":%s}\n' "$d" "$c" "$CAP" "$f" ;;
  esac
}

[ -n "$STATE" ] || { echo '{"decision":"block","reason":"sin COPILOT_BLOCK_STATE: no puedo llevar el contador de bloqueos"}' ; exit 2; }
case "$VERDICT" in
  green|red) : ;;
  *) echo '{"decision":"block","reason":"--verdict debe ser green o red"}'; exit 2 ;;
esac

count=0
if [ -f "$STATE" ]; then
  count="$(tr -cd '0-9' < "$STATE")"; count="${count:-0}"
fi

if [ "$VERDICT" = green ]; then
  printf '0' > "$STATE"
  emit allow 0 false "turno verde: la puerta permite y el contador de bloqueos se resetea a 0"
  exit 0
fi

# rojo
if [ "$count" -ge "$CAP" ]; then
  # el tope ya estaba agotado: Copilot fuerza la parada. No se resetea aqui;
  # solo un verde limpia el contador.
  emit stop "$count" true "tope de $CAP bloqueos AGOTADO: Copilot fuerza la parada (bounded enforcement, ciclo de vida degradado). NO es lifecycle-enforced."
  exit 0
fi

count=$((count+1))
printf '%s' "$count" > "$STATE"
if [ "$count" -ge "$CAP" ]; then
  # justo alcanzamos el tope con este bloqueo: aun bloqueamos (bloqueo 8/8);
  # el PROXIMO rojo sera el que fuerce la parada.
  emit block "$count" false "bloqueo $count/$CAP: enforcement nativo activo (el proximo rojo agotaria el tope)"
  exit 2
fi
emit block "$count" false "bloqueo $count/$CAP: enforcement nativo activo (agentStop fuerza continuacion)"
exit 2
