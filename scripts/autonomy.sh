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
#   autonomy.sh start --oracle CMD --goal TEXTO [--max-repairs N] [--max-minutes N] [--session ID]
#
#   --max-minutes (defecto 240): el run caduca; pasado ese plazo el Stop hook lo cierra sin
#   ejecutar el oraculo, para que una sesion que murio en rojo no bloquee a la siguiente.
#   Cada evento (start, intento, stop) deja una fila en .claude/estado/autonomia.tsv:
#   fecha evento intento rc hash-ultimas-25-lineas-del-oraculo segundos. Ni el oraculo ni
#   el objetivo se copian: el historial no arrastra datos del proyecto.
#
#   Sin --session la clave es el directorio actual: un run activo por proyecto. El Stop
#   hook lee ese mismo estado situandose en el cwd del payload, asi que ambos lados
#   coinciden sin que nadie tenga que conocer el session_id.
#   autonomy.sh status [--session ID]      estado legible; exit 0 activo, 1 inactivo
#   autonomy.sh attempt [--session ID]     consume un intento; exit 1 si se agotaron
#   autonomy.sh stop [--session ID]        cierra el run
#   autonomy.sh expired [--session ID]     exit 0 si el run supero --max-minutes (o su STARTED
#                                          no se entiende: se libera, falla en abierto)
#   autonomy.sh oracle [--session ID]      imprime solo el comando del oraculo
#   autonomy.sh sensor-check [--session ID] lista los ficheros sensor cambiados o borrados
#                                          desde `start`; exit 1 si hay alguno
set -euo pipefail

STATE_DIR="${MCHARNESS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/mcharness}"
mkdir -p "$STATE_DIR"

die() { printf 'autonomy: %s\n' "$*" >&2; exit 1; }

cmd="${1:-}"; shift || true
SESSION=""; ORACLE=""; GOAL=""; MAXREP=3; MAXMIN=240; RC="-"; HASH="-"
while [ $# -gt 0 ]; do
  case "$1" in
    --oracle)      ORACLE="${2:-}"; shift 2 ;;
    --goal)        GOAL="${2:-}"; shift 2 ;;
    --max-repairs) MAXREP="${2:-3}"; shift 2 ;;
    --max-minutes) MAXMIN="${2:-}"; shift 2 ;;
    --rc)          RC="${2:--}"; shift 2 ;;
    --hash)        HASH="${2:--}"; shift 2 ;;
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
# --session entra en el nombre de un fichero del estado: ni `/` ni `..` (escapar del directorio).
if [ -n "$SESSION" ]; then
  case "$SESSION" in
    *[!A-Za-z0-9._-]*|*..*) die "--session solo admite letras, cifras, '.', '-' y '_' (sin '..'): $SESSION" ;;
  esac
fi
[ -n "$SESSION" ] || SESSION="$(basename "$PWD")-$(printf '%s' "$PWD" | cksum | cut -d' ' -f1)"
F="$STATE_DIR/run-$SESSION.env"
H="$STATE_DIR/run-$SESSION.sensor"

# Ficheros rastreados que son el sensor: aflojarlos cierra el lazo en falso. Hashes y no
# `git diff`: asi no se culpa al modelo de cambios que ya estaban sin commitear al arrancar.
sensor_hashes() {
  local top
  top=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  git -C "$top" ls-files -z -- Makefile conftest.py pytest.ini '.github/workflows/' 'tests/' 'test/' 'kit/test/' \
    '**/conftest.py' '**/pytest.ini' '**/Makefile' 2>/dev/null |
    (cd "$top" && xargs -0 -r sha1sum 2>/dev/null) || true
}

# El Stop hook ejecuta el oraculo sin pasar por permisos: el allow de `autonomy.sh *` cubre el
# arranque, no lo que arranca. Solo se acepta lo que vive en el repo: `make X`, `bash kit/test/X.sh`,
# `oraculo -- ...` o una ruta relativa; nada de rutas absolutas, `..`, `~` ni encadenados de shell.
# El nombre suelto sigue rechazado (MISTAKES.md M-001: el hook PreToolUse/Bash lo reescribia).
oracle_ok() {
  local o="$1" w ok=1
  case "$o" in
    *[\;\&\|\`\$\<\>\(\)]*|*$'\n'*|*..*) return 1 ;;
  esac
  set -f
  for w in $o; do
    case "$w" in /*|'~'*|*=/*|-[A-Za-z]/*) ok=0 ;; esac
  done
  set +f
  [ "$ok" -eq 1 ] || return 1
  case "$o" in
    "make "*|"bash kit/test/"*.sh*|"oraculo -- "*) return 0 ;;
  esac
  case "${o%% *}" in */*) return 0 ;; esac
  return 1
}

# Historial: una fila por evento. Los campos los genera este script (sin texto libre), asi
# que un objetivo o un oraculo multilinea no pueden romper el TSV. Un fallo al escribir no
# detiene el run.
tsv() {
  local ev="$1" att="$2" secs=0 e
  if [ -n "${STARTED:-}" ] && e=$(date -u -d "$STARTED" +%s 2>/dev/null); then secs=$(( $(date -u +%s) - e )); fi
  {
    mkdir -p "$PWD/.claude/estado"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$ev" "$att" "$RC" "$HASH" "$secs" \
      >> "$PWD/.claude/estado/autonomia.tsv"
  } 2>/dev/null || true
}

# El env se LEE, no se `source`a: quien pueda escribirlo no ejecuta nada. Solo se toman las
# claves conocidas; ORACLE se revalida y lo numerico se descarta si no son cifras.
load() {
  ORACLE=""; GOAL=""; MAXREP=3; MAXMIN=240; ATTEMPTS=0; STARTED=""
  local line k v
  while IFS= read -r line; do
    k="${line%%=*}"; v="${line#*=}"
    case "$k" in
      ORACLE|GOAL) printf -v "$k" '%s' "$v" ;;
      MAXREP|MAXMIN|ATTEMPTS) case "$v" in ''|*[!0-9]*) ;; *) printf -v "$k" '%s' "$v" ;; esac ;;
      STARTED) case "$v" in *[!0-9TZ:-]*) ;; *) STARTED="$v" ;; esac ;;
    esac
  done < "$F"
}

case "$cmd" in
  start)
    [ -n "$ORACLE" ] || die "start requiere --oracle CMD"
    [ -n "$GOAL" ]   || die "start requiere --goal TEXTO"
    # El oraculo se invoca por ruta absoluta, 'rtk proxy' o 'make': el hook PreToolUse/Bash
    # sustituye el ejecutable en posicion de comando (MISTAKES.md M-001). Un run autonomo
    # que verifica con el comando equivocado es peor que uno que no verifica: parece que si.
    oracle_ok "$ORACLE" || die "oraculo no admitido: use 'make ...', 'bash kit/test/X.sh', 'oraculo -- ...' o una ruta relativa del repo, sin rutas absolutas, '..' ni encadenados (recibido: $ORACLE)"
    case "$MAXMIN" in ''|*[!0-9]*|0) die "--max-minutes debe ser un entero positivo (recibido: $MAXMIN)" ;; esac
    { echo "ORACLE=$ORACLE"
      echo "GOAL=$(printf '%s' "$GOAL" | tr '\n\t' '  ')"
      echo "MAXREP=$MAXREP"
      echo "MAXMIN=$MAXMIN"
      echo "ATTEMPTS=0"
      echo "STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ)"; } > "$F"
    sensor_hashes > "$H" 2>/dev/null || : > "$H"
    STARTED=$(date -u +%Y-%m-%dT%H:%M:%SZ); RC="-"; HASH="-"; tsv start 0
    echo "run autonomo activo (sesion $SESSION)"
    echo "  objetivo : $GOAL"
    echo "  oraculo  : $ORACLE"
    echo "  intentos : $MAXREP reparaciones como maximo"
    echo "  caduca   : a los $MAXMIN minutos"
    ;;
  status)
    [ -f "$F" ] || { echo "sin run autonomo activo"; exit 1; }
    load
    echo "activo desde $STARTED"
    echo "  objetivo : $GOAL"
    echo "  oraculo  : $ORACLE"
    echo "  intentos : $ATTEMPTS de $MAXREP"
    ;;
  oracle)
    [ -f "$F" ] || exit 1
    load; oracle_ok "$ORACLE" || exit 1
    printf '%s\n' "$ORACLE"
    ;;
  attempt)
    [ -f "$F" ] || exit 1
    load
    ATTEMPTS=$((ATTEMPTS + 1))
    sed -i.bak "s/^ATTEMPTS=.*/ATTEMPTS=$ATTEMPTS/" "$F" && rm -f "$F.bak"
    echo "$ATTEMPTS"
    tsv intento "$ATTEMPTS"
    # Agotado el presupuesto se para. Insistir mas alla no es perseverancia: es un lazo
    # sin condicion de salida, y es justo donde aparece la tentacion de aflojar el sensor.
    [ "$ATTEMPTS" -le "$MAXREP" ] || exit 1
    ;;
  sensor-check)
    # Falla en abierto: sin run o sin fichero de hashes no hay nada que comparar.
    [ -f "$F" ] && [ -f "$H" ] || exit 0
    now=$'\n'"$(sensor_hashes)"$'\n'
    top=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
    altered=""
    while IFS= read -r line; do
      [ -n "$line" ] || continue
      case "$now" in
        *$'\n'"$line"$'\n'*) ;;
        *) p="${line#*  }"
           if [ -e "$top/$p" ]; then altered="$altered$p"$'\n'; else altered="$altered$p (borrado)"$'\n'; fi ;;
      esac
    done < "$H"
    [ -z "$altered" ] || { printf '%s' "$altered"; exit 1; }
    ;;
  expired)
    [ -f "$F" ] || exit 1
    load
    # STARTED vacio, ilegible o en el futuro: se libera (date -d vacio daria las 00:00 de hoy).
    [ -n "$STARTED" ] || exit 0
    started=$(date -u -d "$STARTED" +%s 2>/dev/null) || exit 0
    age=$(( $(date -u +%s) - started ))
    [ "$age" -lt 0 ] || [ "$age" -ge "$(( MAXMIN * 60 ))" ]
    ;;
  stop)
    if [ -f "$F" ]; then
      load; tsv stop "$ATTEMPTS"
      rm -f "$F" "$H"; echo "run autonomo cerrado"; else echo "no habia run activo"; fi
    ;;
  *)
    die "uso: autonomy.sh {start|status|attempt|oracle|sensor-check|expired|stop} [opciones]"
    ;;
esac
