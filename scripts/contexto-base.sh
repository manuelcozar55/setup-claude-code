#!/usr/bin/env bash
# contexto-base.sh — mide cuánto contexto mete el kit al arrancar una sesión (ADR 018).
#   scripts/contexto-base.sh            inventario estático por canal: sin red, determinista, gratis
#   scripts/contexto-base.sh --pagar    además, el primer turno real con `claude -p` (cuesta dinero)
# Opciones de --pagar: --salida DIR (JSON de cada corrida; def. mktemp), --tope USD (def. 1.50),
#   --sin-opus (omite la corrida con el modelo de la plantilla).
# Inventario: caracteres/bytes de cada canal en el peor caso razonable. Los hooks se ejecutan con
# entradas sintéticas, un nucleo.md de ~8 KB, un HOME y un repo de mktemp.
# Medida real: usage.input + cache_creation + cache_read del primer turno y total_cost_usd.
#   sin-kit  : --safe-mode (sin CLAUDE.md, skills, hooks ni agentes propios; la política gestionada de
#              /etc/claude-code se carga igual)
#   con-kit  : el kit instalado con install.sh en un CLAUDE_HOME de mktemp y cargado como proyecto
#              (--setting-sources project) en un repo de mktemp; los hooks corren con HOME de mktemp
#   con-kit+nucleo : lo mismo con un nucleo.md de ~8 KB en el repo
#   viva     : la configuración de quien ejecuta, sin aislar (etiquetada: no es reproducible)
# Aislar con CLAUDE_CONFIG_DIR pide un login nuevo (las credenciales no se copian): ver el RESULTADO.
set -euo pipefail
export LC_ALL=C.UTF-8
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../kit" && pwd)"
PAGAR=0 SALIDA="" TOPE=1.50 OPUS=1
while [ $# -gt 0 ]; do
  case $1 in
    --pagar) PAGAR=1 ;;
    --salida) SALIDA=${2:?}; shift ;;
    --tope) TOPE=${2:?}; shift ;;
    --sin-opus) OPUS=0 ;;
    -h|--help) sed -n '2,6p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "opción desconocida: $1" >&2; exit 2 ;;
  esac
  shift
done
for c in jq git; do command -v "$c" >/dev/null || { echo "falta $c" >&2; exit 1; }; done

W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
H=$W/h; R=$W/repo; mkdir -p "$H" "$R"

# --- fixtures deterministas --------------------------------------------------
CLAUDE_HOME=$H/.claude HOME=$H bash "$KIT/install.sh" </dev/null >/dev/null 2>&1
export GIT_AUTHOR_NAME=m GIT_AUTHOR_EMAIL=m@x GIT_COMMITTER_NAME=m GIT_COMMITTER_EMAIL=m@x
git -C "$R" init -q -b main
for i in 1 2 3 4; do
  printf '%s\n' "$i" >"$R/f$i"; git -C "$R" add .
  GIT_AUTHOR_DATE="2026-01-0${i}T00:00:00Z" GIT_COMMITTER_DATE="2026-01-0${i}T00:00:00Z" \
    git -C "$R" commit -q -m "commit $i $(printf 'x%.0s' $(seq 1 140))"
done
mkdir -p "$R/.claude/estado"
NUC=$R/.claude/estado/nucleo.md
{
  printf '# Estado\n## Objetivo\n%s\n## Invariantes\n' "$(printf 'o%.0s' $(seq 1 300))"
  for i in $(seq 1 12); do printf -- '- invariante %s %s\n' "$i" "$(printf 'i%.0s' $(seq 1 60))"; done
  printf '## Plan\n'
  for i in $(seq 1 14); do printf -- '- [ ] paso %s %s\n' "$i" "$(printf 'p%.0s' $(seq 1 60))"; done
  printf '## Paso actual\n%s\n## Siguiente acción\n%s\n## Pendientes\n' "$(printf 'a%.0s' $(seq 1 200))" "$(printf 's%.0s' $(seq 1 200))"
  for i in $(seq 1 10); do printf -- '- pendiente %s %s\n' "$i" "$(printf 'd%.0s' $(seq 1 60))"; done
  printf '## Comandos de verificación\n- make test\n'
} >"$NUC"
head -c 8192 "$NUC" >"$NUC.t" && mv "$NUC.t" "$NUC"
TR=$W/transcript.jsonl   # 170 000 tok de uso sobre un airbag de 167 000: pasa del 85 %
printf '%s\n' '{"type":"assistant","message":{"model":"claude-haiku-4-5","usage":{"input_tokens":170000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' >"$TR"

# --- inventario ---------------------------------------------------------------
LINEAS=()
fila() { LINEAS+=("$(printf '%-52s %8s %8s' "$1" "$2" "$3")"); }
medir() { fila "$1" "$(printf '%s' "$2" | wc -m)" "$(printf '%s' "$2" | wc -c)"; }

# 1. instrucciones globales: CLAUDE.md con el @import expandido
GLOB=$(sed -e '/^@AGENTS.md$/{r '"$KIT/claude/AGENTS.md" -e 'd}' "$KIT/claude/CLAUDE.md")
medir "instrucciones globales (CLAUDE.md + @AGENTS.md)" "$GLOB"

# 2. hooks que inyectan texto (peor caso): additionalContext o systemMessage del JSON de salida
hook() { # etiqueta, script, stdin
  local out
  out=$(cd "$R" && HOME=$H CLAUDE_HOME=$H/.claude bash "$H/.claude/hooks/$2" <<<"$3" 2>/dev/null \
    | jq -r '[.hookSpecificOutput.additionalContext // empty, .systemMessage // empty, .reason // empty] | join("\n")') || out=""
  medir "$1" "$out"
}
IN="{\"cwd\":\"$R\",\"session_id\":\"s0\",\"transcript_path\":\"$TR\""
touch -d '2026-01-01' "$NUC"
hook "SessionStart startup (nucleo 8 KB)" session-start-clear.sh "$IN,\"source\":\"startup\"}"
hook "SessionStart clear (nucleo 8 KB)" session-start-clear.sh "$IN,\"source\":\"clear\"}"
hook "SessionStart resume (+aviso caché caducada)" session-start-clear.sh \
  "$IN,\"source\":\"resume\",\"prompt_cache_likely_expired\":true,\"context_tokens\":150000}"
hook "SessionStart compact (nucleo 8 KB)" session-start-compact.sh "$IN,\"source\":\"compact\"}"
# session-start.sh imprime al stdout (texto plano): también entra como contexto
fila "SessionStart memoria (session-start.sh)" \
  "$(cd "$R" && HOME=$H bash "$H/.claude/hooks/session-start.sh" </dev/null 2>/dev/null | wc -m)" \
  "$(cd "$R" && HOME=$H bash "$H/.claude/hooks/session-start.sh" </dev/null 2>/dev/null | wc -c)"
hook "PostToolUse nucleo-nudge (airbag 85 %)" nucleo-nudge.sh "$IN,\"tool_name\":\"Bash\"}"
hook "Stop context-gauge (>= 60 %)" stop-context-gauge.sh "$IN,\"stop_hook_active\":false}"
fila "UserPromptSubmit (el kit no instala ninguno)" 0 0

# 3. agentes y skills: el campo description, lo que el harness lista siempre
desc() { sed -n '1,/^---$/{/^description:/{s/^description: *//;s/^"\(.*\)"$/\1/;p;q}}' "$1" | sed -n 1p; }
SUMA_A=0 SUMA_AB=0
for f in "$KIT"/claude/agents/*.md; do
  d=$(desc "$f"); n=$(basename "$f" .md)
  medir "agente $n (description)" "$d"
  SUMA_A=$((SUMA_A + $(printf '%s' "$d" | wc -m))); SUMA_AB=$((SUMA_AB + $(printf '%s' "$d" | wc -c)))
done
fila "agentes: suma de las descriptions" "$SUMA_A" "$SUMA_AB"
SUMA_S=0 SUMA_SB=0
for f in "$KIT"/claude/skills/*/SKILL.md; do
  n=$(basename "$(dirname "$f")")
  if grep -q '^disable-model-invocation: *true' "$f"; then
    fila "skill $n (disable-model-invocation: fuera de contexto)" 0 0; continue
  fi
  d=$(desc "$f"); medir "skill $n (description)" "$d"
  SUMA_S=$((SUMA_S + $(printf '%s' "$d" | wc -m))); SUMA_SB=$((SUMA_SB + $(printf '%s' "$d" | wc -c)))
done
fila "skills: suma de las descriptions" "$SUMA_S" "$SUMA_SB"

printf '%-52s %8s %8s\n' "canal (peor caso razonable)" caracteres bytes
printf '%s\n' "${LINEAS[@]}"

# --- medida real ----------------------------------------------------------------
[ "$PAGAR" = 1 ] || exit 0
command -v claude >/dev/null || { echo "falta claude" >&2; exit 1; }
[ -n "$SALIDA" ] || SALIDA=$(mktemp -d); mkdir -p "$SALIDA"
echo; echo "claude $(claude --version) · salida en $SALIDA · tope $TOPE USD"

# el kit como proyecto: CLAUDE.md, agentes, skills y settings con los hooks apuntando al HOME de mktemp
mkproyecto() { # dir
  local d=$1
  mkdir -p "$d/.claude"; git -C "$d" init -q -b main 2>/dev/null || true
  cp "$H/.claude/AGENTS.md" "$d/AGENTS.md"; cp "$H/.claude/CLAUDE.md" "$d/CLAUDE.md"
  cp -r "$H/.claude/agents" "$H/.claude/skills" "$d/.claude/"
  jq --arg h "$H" 'del(.enabledPlugins, .extraKnownMarketplaces, .model, .statusLine)
      | (.hooks[]?[]?.hooks[]?.command) |= ("env HOME=" + $h + " " + (gsub("\\$HOME"; $h)))' \
    "$H/.claude/settings.json" >"$d/.claude/settings.json"
}
P1=$W/p1; P2=$W/p2; V=$W/vacio; mkdir -p "$V"
mkproyecto "$P1"; mkproyecto "$P2"; mkdir -p "$P2/.claude/estado"; cp "$NUC" "$P2/.claude/estado/nucleo.md"

GASTO=0
corre() { # etiqueta modelo dir flags...
  local et=$1 mod=$2 dir=$3; shift 3
  if awk -v g="$GASTO" -v t="$TOPE" -v m="$mod" 'BEGIN{exit !(g + (m=="opus"?0.5:0.1) > t)}'; then
    echo "$et: omitida, el gasto ($GASTO) + estimación pasa del tope"; return 0
  fi
  (cd "$dir" && claude -p "Responde solo: ok" --model "$mod" --output-format json \
     --no-session-persistence "$@" </dev/null >"$SALIDA/$et.json" 2>"$SALIDA/$et.err") || true
  local tok cost
  tok=$(jq -r '.usage | (.input_tokens + .cache_creation_input_tokens + .cache_read_input_tokens)' "$SALIDA/$et.json" 2>/dev/null || echo "?")
  cost=$(jq -r '.total_cost_usd // 0' "$SALIDA/$et.json" 2>/dev/null || echo 0)
  GASTO=$(awk -v a="$GASTO" -v b="$cost" 'BEGIN{printf "%.6f", a+b}')
  printf '%-22s %-7s tokens_entrada=%-7s coste=%s error=%s\n' "$et" "$mod" "$tok" "$cost" \
    "$(jq -r '.is_error | tostring' "$SALIDA/$et.json" 2>/dev/null || echo "?")"
}
corre haiku-sin-kit haiku "$V" --safe-mode
corre haiku-con-kit haiku "$P1" --setting-sources project
corre haiku-con-kit-nucleo haiku "$P2" --setting-sources project
corre haiku-viva haiku "$V"
[ "$OPUS" = 0 ] || corre opus-con-kit opus "$P1" --setting-sources project
echo "gasto total: $GASTO USD"
