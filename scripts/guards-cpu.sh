#!/usr/bin/env bash
# Mide la CPU (user+sys) de la cadena PreToolUse de Bash del settings.json del kit.
#
# Por que existe: cada llamada a Bash pasa por todos los hooks PreToolUse con matcher ""
# o "Bash", y cada uno es un proceso (bash, jq, python). La cobertura de los guards se
# prueba en kit/test; lo que cuestan se mide aqui. La cifra es CPU, no tiempo de pared:
# no depende de que la maquina este ociosa.
#
# Uso:  scripts/guards-cpu.sh [--settings FICHERO]
# Env:  GUARDS_CPU_REPS (repeticiones por comando, 1)  GUARDS_CPU_P95_MAX (ms, 300)
# Salida: p50 y p95 en ms por llamada; exit 1 si el p95 supera GUARDS_CPU_P95_MAX.
#
# Corre sobre un HOME temporal con los hooks y Sentinel del kit copiados, de modo que no
# lee ni escribe el ~/.claude de quien lo ejecuta (ni su log de auditoria).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS="$ROOT/kit/claude/settings.json"
[ "${1:-}" = "--settings" ] && { SETTINGS=$2; shift 2; }
REPS=${GUARDS_CPU_REPS:-1}
MAX=${GUARDS_CPU_P95_MAX:-300}
command -v jq >/dev/null || { echo "falta jq" >&2; exit 2; }

T=$(mktemp -d); trap 'rm -r -- "$T"' EXIT
export HOME="$T/home"
mkdir -p "$HOME/.claude/sentinel" "$T/repo"
cp -r "$ROOT/kit/claude/hooks" "$HOME/.claude/hooks"
cp "$ROOT/kit/sentinel/sentinel_preflight.py" "$HOME/.claude/sentinel/"
[ -f "$ROOT/kit/sentinel/iocs.json" ] && cp "$ROOT/kit/sentinel/iocs.json" "$HOME/.claude/sentinel/"
cp "$SETTINGS" "$HOME/.claude/settings.json"
git -C "$T/repo" init -q && git -C "$T/repo" symbolic-ref HEAD refs/heads/feature/cpu
cd "$T/repo" || exit 2

mapfile -t CHAIN < <(jq -r '.hooks.PreToolUse[] | select(.matcher == "" or .matcher == "Bash") | .hooks[].command' "$SETTINGS")
[ "${#CHAIN[@]}" -gt 0 ] || { echo "sin hooks PreToolUse de Bash en $SETTINGS" >&2; exit 2; }

BODY64=$(head -c 65536 /dev/zero | tr '\0' 'a')
CMDS=(
  'ls -la'
  'git status --short'
  'git log --oneline -5'
  'git diff --stat'
  'git add src/app.py'
  'git commit -m "fix: corrige el redondeo"'
  'git push origin feature/cpu'
  'pnpm test'
  'make test'
  'cat README.md'
  'grep -rn "TODO" src/'
  'jq -r ".version" package.json'
  'find . -name "*.py" -type f'
  'python3 scripts/run.py --flag'
  'gh pr view 12'
  'echo hola > notas.txt'
  'sed -i s/a/b/ notas.txt'
  'ls src | tee lista.txt'
  $'cat > f.txt <<\'EOF\'\nhola\nEOF'
  "cat > big.txt <<'EOF'
$BODY64
EOF"
)

TIMEFORMAT='%3U %3S'
samples=()
for cmd in "${CMDS[@]}"; do
  payload=$(jq -nc --arg c "$cmd" '{tool_name:"Bash",tool_input:{command:$c}}')
  for ((r = 0; r < REPS; r++)); do
    t=$({ time {
      for h in "${CHAIN[@]}"; do printf '%s' "$payload" | bash -c "$h" >/dev/null 2>&1; done
    }; } 2>&1)
    read -r u s <<<"$t"
    samples+=("$(awk -v u="$u" -v s="$s" 'BEGIN { printf "%d", (u + s) * 1000 + 0.5 }')")
  done
done

mapfile -t sorted < <(printf '%s\n' "${samples[@]}" | sort -n)
n=${#sorted[@]}
pct() { local i=$(( (n * $1 + 99) / 100 )); echo "${sorted[i - 1]}"; }
p50=$(pct 50); p95=$(pct 95)
echo "hooks en la cadena: ${#CHAIN[@]}   llamadas medidas: $n   (CPU user+sys por llamada)"
echo "p50=${p50} ms  p95=${p95} ms  max=${sorted[n - 1]} ms  objetivo p95 < ${MAX} ms"
[ "$p95" -lt "$MAX" ]
