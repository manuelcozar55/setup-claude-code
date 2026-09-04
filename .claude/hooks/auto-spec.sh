#!/usr/bin/env bash
# UserPromptSubmit — el harness entra solo, en el momento en que pides algo.
#
# POR QUE EXISTE
#   v0.1.0 daba cinco comandos excelentes que habia que acordarse de teclear. La medicion
#   dice que eso no funciona: habia una regla enorme exigiendo plan mode y el plan mode
#   valia 2,1 %. Pedir disciplina no la produce. Esto la cablea.
#
#   El gap concreto: la mediana de encargo son 142 caracteres y casi nunca incluye como
#   se sabra que esta bien hecho. Ese hueco es la causa raiz del retrabajo -- no es que el
#   agente falle, es que nadie definio "terminado". Aqui se rellena solo.
#
# CONTRATO (verificado en code.claude.com/docs/en/hooks, 2026-08-21)
#   El stdout PLANO de UserPromptSubmit se anade al contexto que el modelo ve. No hace
#   falta JSON: la doc lo dice literal y el esquema JSON de este evento no esta documentado.
#   exit 2 BORRA el prompt del usuario -> aqui NUNCA se usa. exit 0 siempre, pase lo que pase.
#
# COSTE: debe ser imperceptible, corre en cada prompt. Medido < 60 ms.
set -uo pipefail

exec 3>&2 2>/dev/null   # cualquier ruido interno no debe ensuciar la sesion

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0

# >>> hk-json ─────────────────────────────────────────────────────────────────
# Leer JSON sin depender de jq. Cadena de tres eslabones, en este orden:
#   1. jq si esta         -> el camino de siempre, sin cambiar un byte
#   2. python3 si no      -> json de la stdlib, parseo de verdad
#   3. ninguno de los dos -> fallo cerrado; quien llama decide como bloquear
# python3 NO es una dependencia nueva: kit/install.sh aborta con exit 1 si no puede crear
# el venv con `python3 -m venv`, y el kit ya distribuye cuatro hooks .py. jq, en cambio,
# no esta declarado como requisito en ningun sitio.
# PROHIBIDO parsear esto con grep/sed/awk: el payload lleva llaves, comillas y saltos de
# linea DENTRO de los valores, y una igualdad por subcadena es exactamente el defecto que
# este repo lleva media rama persiguiendo.
# Este bloque esta DUPLICADO en los seis hooks que leen JSON, y kit/test/test_guards.sh
# comprueba que los seis son identicos byte a byte. Se duplica en vez de compartirse
# porque un hook es un ejecutable hoja que el runtime lanza por ruta absoluta: ninguno de
# los 14 del kit hace `source` de nada, los cuatro guards se instalan en ~/.claude/hooks/
# mientras que auto-spec y verify-gate viven en el repo (no hay ruta relativa comun), y
# una libreria compartida anadiria a un control de seguridad un modo de fallo nuevo --
# libreria ausente => bloquear TODO.
if command -v jq >/dev/null 2>&1; then HK_JSON=jq
elif command -v python3 >/dev/null 2>&1; then HK_JSON=py
else HK_JSON=no; fi

# hk_get <ruta.punteada> [defecto]  --  JSON por stdin, valor por stdout.
# El contrato es el que ya tenia jq a solas, y de el depende todo lo de abajo:
#   rc=0 con salida vacia -> el campo no esta (permitir es lo correcto)
#   rc!=0                 -> no se ha podido leer la entrada (ciego: no puede autorizar)
# El defecto viaja por --arg/argv, nunca interpolado dentro del programa.
hk_get() {
  case "$HK_JSON" in
    jq) if [ $# -ge 2 ]; then jq -r --arg d "$2" ".$1 // \$d" 2>/dev/null
        else jq -r ".$1 // empty" 2>/dev/null; fi ;;
    py) python3 -c 'import json,sys
try: d = json.load(sys.stdin)
except Exception: sys.exit(5)
for k in sys.argv[1].split("."):
    if d is None: break
    if not isinstance(d, dict): sys.exit(5)
    d = d.get(k)
if d is None or d is False: d = sys.argv[2] if len(sys.argv) > 2 else None
if d is not None: print(d if isinstance(d, str) else json.dumps(d))' "$1" ${2+"$2"} 2>/dev/null ;;
    *)  return 127 ;;
  esac
}
# <<< hk-json ─────────────────────────────────────────────────────────────────

prompt=$(printf '%s' "$payload" | hk_get prompt)
cwd=$(printf '%s' "$payload" | hk_get cwd)
sid=$(printf '%s' "$payload" | hk_get session_id unknown)
# Sin jq NI python3 no se parsea con fiabilidad, y este hook se calla saliendo por la
# linea de abajo con el prompt vacio. Ojo: aqui "fallar cerrado" NO puede ser exit 2.
# En UserPromptSubmit ese codigo BORRA el prompt del usuario (contrato citado arriba),
# asi que el unico fallo seguro es el silencio -- al reves que en los cuatro guards,
# donde callar es autorizar. La asimetria del kit se aplica al evento, no al fichero.
[ -n "$prompt" ] || exit 0
[ -n "$cwd" ] || cwd="$PWD"

STATE="${MCHARNESS_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/mcharness}"
mkdir -p "$STATE" 2>/dev/null

lower=$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')
out=""
add() { out="${out}$1
"; }

# ── 1. ¿Es un encargo de trabajo, o una pregunta? ────────────────────────────
# Solo los encargos necesitan criterios de aceptacion. Inyectar esto en una pregunta
# seria el ruido que hace que se ignore el aviso cuando importa.
es_encargo=0
# Raices, no palabras completas: "implementa" cubre "implementar" e "implementalo".
case "$lower" in
  *implement*|*arregla*|*corrige*|*añad*|*anad*|*crea*|*refactor*|*migra*|*escrib*|\
  *cambia*|*elimina*|*integra*|*fix\ *|*add\ *|*build\ *|*write\ *|*haz*)
    es_encargo=1 ;;
esac

# ── 2. ¿Ya trae criterio de verificacion? ────────────────────────────────────
# Si lo trae, no hay gap que cerrar y el harness se calla. Esta rama es la que
# hace que el usuario note el beneficio de escribirlo el mismo: menos interrupcion.
trae_criterio=0
case "$lower" in
  *test*|*prueba*|*verifi*|*oracul*|*"make "*|*"que pase"*|*criterio*|*acepta*|\
  *lint*|*"exit 0"*|*"en verde"*) trae_criterio=1 ;;
esac

# ── 3. Gotchas del entorno, solo si el prompt los va a tocar ─────────────────
# M-001: el hook PreToolUse/Bash sustituye el ejecutable en posicion de comando.
case "$lower" in
  *pytest*|*" rg "*|*ripgrep*|*"python -m"*|*"python3 -m"*|*npm\ test*|*jest*|*vitest*)
    add "· Gotcha de este entorno (MISTAKES.md M-001): el hook PreToolUse/Bash sustituye el"
    add "  ejecutable en posicion de comando -- 'rg' ejecuta grep, 'python3 -m pytest' ejecuta"
    add "  'python3 -m rtk'. Invoca por RUTA ABSOLUTA, con 'rtk proxy ...' o dentro de un script."
    ;;
esac

# ── 4. El oraculo del proyecto, averiguado y no preguntado ───────────────────
DET="$cwd/scripts/detect-oracle.sh"
[ -x "$DET" ] || DET="${CLAUDE_PROJECT_DIR:-}/scripts/detect-oracle.sh"
oracle=""
[ -x "$DET" ] && oracle=$("$DET" "$cwd" 2>/dev/null | head -1)

# ── 5. Brief de sesion: primer ENCARGO de la sesion, no primer prompt ────────
# Atado al encargo a proposito: en una sesion de preguntas el brief no aporta, y el
# ruido de hoy es la razon por la que manana se ignora el aviso que si importaba.
# La marca solo se escribe cuando el brief se emite de verdad, para que un primer
# prompt de lectura no consuma el turno del brief.
if [ "$es_encargo" -eq 1 ] && [ ! -f "$STATE/session-$sid.briefed" ]; then
  K="$cwd/knowledge"
  if [ -f "$K/MISTAKES.md" ]; then
    n=$(grep -c '^## M-' "$K/MISTAKES.md" 2>/dev/null || echo 0)
    if [ "$n" -gt 0 ]; then
      add "· Errores ya cometidos en este repo ($n): knowledge/MISTAKES.md. No los repitas."
      : > "$STATE/session-$sid.briefed" 2>/dev/null
    fi
  fi
fi

# ── 6. El nucleo: encargo sin criterio -> se le pone criterio ────────────────
if [ "$es_encargo" -eq 1 ] && [ "$trae_criterio" -eq 0 ]; then
  add "· Esto es un encargo de trabajo y no trae criterio de verificacion. Antes de escribir"
  add "  codigo, declara en una linea: que sera cierto cuando este hecho, y QUE COMANDO lo"
  add "  demuestra. Si hay dos lecturas del encargo que producen entregables distintos,"
  add "  pregunta ahora -- no a mitad."
  if [ -n "$oracle" ]; then
    add "  Oraculo de este proyecto (detectado): $oracle"
    add "  Ejecutalo EN FRIO antes de tocar nada: si ya pasa, no mide lo que vas a cambiar."
  else
    add "  No se ha detectado oraculo en este proyecto. Si vas a modificar codigo, la primera"
    add "  tarea es dejar uno ejecutable; no finjas verificacion que no puedes correr."
  fi
  add "· Al terminar: ensena la salida del comando, no una afirmacion de que funciona. Y"
  add "  comprueba con 'git diff --name-only' que no has tocado el propio sensor."
elif [ "$es_encargo" -eq 1 ] && [ -n "$oracle" ]; then
  add "· Oraculo de este proyecto: $oracle -- cierra con su salida delante."
fi

# ── 7. La medicion envejece: avisar antes de que el harness deje de ser evaluable ──
# Causa nº2 del PRE-MORTEM: "la medicion nunca tuvo un segundo punto". Sin dos snapshots
# no hay tendencia, y sin tendencia nadie puede decir si esto sirve. Cuesta un stat.
# Nada de procesos de fondo ni cron: solo se avisa, en el momento en que hay alguien leyendo.
OUTDIR="${METRICS_OUT_DIR:-$HOME/ai-mastery/bucle/data}"
if [ "$es_encargo" -eq 1 ] && [ -d "$OUTDIR" ]; then
  last=$(find "$OUTDIR" -maxdepth 1 -name 'metrics-*.json' -printf '%T@\n' 2>/dev/null | sort -rn | head -1)
  if [ -n "$last" ]; then
    dias=$(( ( $(date +%s) - ${last%.*} ) / 86400 ))
    [ "$dias" -ge 7 ] && add "· Hace $dias dias del ultimo snapshot de metricas. Sin un segundo punto no hay tendencia y el harness no es evaluable: 'scripts/cost-report.sh'."
  fi
fi

exec 2>&3 3>&-
[ -n "$out" ] || exit 0

printf '<mcharness>\n%s</mcharness>\n' "$out"
exit 0
