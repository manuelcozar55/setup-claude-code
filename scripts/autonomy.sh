#!/usr/bin/env bash
# Estado de un encargo autonomo: el harness conduce y el humano se aparta.
#
# POR QUE EXISTE
#   El objetivo es explicar el trabajo UNA vez y no volver a entrar salvo que haga falta
#   de verdad. Para eso el lazo tiene que cerrarse sin un humano en medio, y eso exige
#   tres cosas que un prompt no da: un criterio de salida escrito, un presupuesto de
#   intentos, y un sensor que decida -- no una opinion del que hace el trabajo.
#
#   Este script guarda ese estado. El Stop hook lo lee para decidir si deja terminar.
#
# Uso:
#   autonomy.sh start --oracle CMD --goal TEXTO [--max-repairs N] [--session ID]
#
#   Sin --session la clave es el directorio actual: un run activo por proyecto. El Stop
#   hook lee ese mismo estado situandose en el cwd del payload, asi que ambos lados
#   coinciden sin que nadie tenga que conocer el session_id.
#   autonomy.sh status [--session ID]      estado legible; exit 0 activo, 1 inactivo
#   autonomy.sh attempt [--session ID]     consume un intento; exit 1 si se agotaron
#   autonomy.sh stop [--session ID]        cierra el run
#   autonomy.sh oracle [--session ID]      imprime solo el comando del oraculo
set -euo pipefail

STATE_DIR="${MCHARNESS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/mcharness}"
mkdir -p "$STATE_DIR"

die() { printf 'autonomy: %s\n' "$*" >&2; exit 1; }

cmd="${1:-}"; shift || true
SESSION=""; ORACLE=""; GOAL=""; MAXREP=3
while [ $# -gt 0 ]; do
  case "$1" in
    --oracle)      ORACLE="${2:-}"; shift 2 ;;
    --goal)        GOAL="${2:-}"; shift 2 ;;
    --max-repairs) MAXREP="${2:-3}"; shift 2 ;;
    --session)     SESSION="${2:-}"; shift 2 ;;
    *) die "opcion desconocida: $1" ;;
  esac
done

# La clave del estado es el DIRECTORIO del proyecto, no el session_id de Claude Code.
# El session_id solo lo conoce el Stop hook, porque le llega en su payload; quien arranca
# el run es el modelo, desde Bash, y ahi no esta expuesto. Con el session_id como clave,
# `start` escribia un fichero que el gate nunca buscaba: el gate no encontraba run, caia a
# modo normal y dejaba terminar el turno con el oraculo en rojo -- exactamente el fallo que
# este modo existe para impedir, y en silencio. Un run por proyecto es ademas el modelo
# real de uso. `--session` se conserva como override explicito para los tests.
[ -n "$SESSION" ] || SESSION="$(basename "$PWD")-$(printf '%s' "$PWD" | cksum | cut -d' ' -f1)"
F="$STATE_DIR/run-$SESSION.env"

case "$cmd" in
  start)
    [ -n "$ORACLE" ] || die "start requiere --oracle CMD"
    [ -n "$GOAL" ]   || die "start requiere --goal TEXTO"
    # El oraculo se invoca por ruta absoluta, 'rtk proxy' o 'make': el hook PreToolUse/Bash
    # sustituye el ejecutable en posicion de comando (MISTAKES.md M-001). Un run autonomo
    # que verifica con el comando equivocado es peor que uno que no verifica: parece que si.
    case "$ORACLE" in
      /*|"rtk proxy "*|"make "*) ;;
      *) die "el oraculo debe ser ruta absoluta, 'rtk proxy ...' o 'make ...' (recibido: $ORACLE)" ;;
    esac
    { echo "ORACLE=$(printf '%q' "$ORACLE")"
      echo "GOAL=$(printf '%q' "$GOAL")"
      echo "MAXREP=$MAXREP"
      echo "ATTEMPTS=0"
      echo "STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } > "$F"
    echo "run autonomo activo (sesion $SESSION)"
    echo "  objetivo : $GOAL"
    echo "  oraculo  : $ORACLE"
    echo "  intentos : $MAXREP reparaciones como maximo"
    ;;
  status)
    [ -f "$F" ] || { echo "sin run autonomo activo"; exit 1; }
    # shellcheck disable=SC1090
    . "$F"
    echo "activo desde $STARTED"
    echo "  objetivo : $GOAL"
    echo "  oraculo  : $ORACLE"
    echo "  intentos : $ATTEMPTS de $MAXREP"
    ;;
  oracle)
    [ -f "$F" ] || exit 1
    # shellcheck disable=SC1090
    . "$F"; printf '%s\n' "$ORACLE"
    ;;
  attempt)
    [ -f "$F" ] || exit 1
    # shellcheck disable=SC1090
    . "$F"
    ATTEMPTS=$((ATTEMPTS + 1))
    sed -i.bak "s/^ATTEMPTS=.*/ATTEMPTS=$ATTEMPTS/" "$F" && rm -f "$F.bak"
    echo "$ATTEMPTS"
    # Agotado el presupuesto se para. Insistir mas alla no es perseverancia: es un lazo
    # sin condicion de salida, y es justo donde aparece la tentacion de aflojar el sensor.
    [ "$ATTEMPTS" -le "$MAXREP" ] || exit 1
    ;;
  stop)
    if [ -f "$F" ]; then rm -f "$F"; echo "run autonomo cerrado"; else echo "no habia run activo"; fi
    ;;
  *)
    die "uso: autonomy.sh {start|status|attempt|oracle|stop} [opciones]"
    ;;
esac
