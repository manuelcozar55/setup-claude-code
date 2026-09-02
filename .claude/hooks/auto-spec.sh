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

if command -v jq >/dev/null 2>&1; then
  prompt=$(printf '%s' "$payload" | jq -r '.prompt // empty' 2>/dev/null)
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
  sid=$(printf '%s' "$payload" | jq -r '.session_id // "unknown"' 2>/dev/null)
else
  exit 0   # sin jq no se parsea con fiabilidad; callar es mejor que adivinar
fi
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
