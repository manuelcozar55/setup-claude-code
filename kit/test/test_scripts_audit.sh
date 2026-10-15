#!/usr/bin/env bash
# test_scripts_audit.sh — scripts/compact-audit.py y scripts/nucleo_audit.py sobre un
# directorio de transcripts SINTETICO (nunca sobre ~/.claude/projects real): una sesion
# con una compactacion manual y nucleo.md escrito antes y releido despues, mas un
# transcript de subagente que tambien compacta y debe quedar fuera. HOME apunta a un
# directorio vacio: si algun script ignorara CLAUDE_PROJECTS_DIR, no veria nada.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
REPO="$(cd "$KIT/.." && pwd)"
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
P="$tmp/projects"; mkdir -p "$P/-tmp-demo/s1/subagents" "$tmp/home"
NUC=/tmp/demo/.claude/estado/nucleo.md
BOUNDARY='{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"manual","preTokens":1000,"postTokens":100,"durationMs":2000}}'
cat > "$P/-tmp-demo/s1.jsonl" <<EOF
{"type":"user","message":{"role":"user","content":"arregla el instalador"}}
{"type":"assistant","message":{"id":"m1","usage":{"input_tokens":10,"cache_read_input_tokens":90},"content":[{"type":"tool_use","name":"Edit","input":{"file_path":"$NUC"}}]}}
$BOUNDARY
{"type":"user","isCompactSummary":true,"message":{"role":"user","content":"This session is being continued from a previous conversation"}}
{"type":"assistant","message":{"id":"m2","content":[{"type":"tool_use","name":"Read","input":{"file_path":"$NUC"}}]}}
{"type":"user","message":{"role":"user","content":"sigue"}}
EOF
printf '%s\n' "$BOUNDARY" > "$P/-tmp-demo/s1/subagents/agent-a.jsonl"
run() { HOME="$tmp/home" CLAUDE_PROJECTS_DIR="$P" python3 "$REPO/scripts/$1"; }

out=$(run compact-audit.py); rc=$?
ck "$rc" "0" "compact-audit.py sale 0"
ck "$(grep -c '^sesiones analizadas: 1 | con compactación: 1 | compactaciones: 1$' <<<"$out")" "1" \
  "compact-audit.py: 1 sesion, 1 compactacion (el subagente no cuenta)"
ck "$(grep -c 'manuales: 1 (100 %)' <<<"$out")" "1" "compact-audit.py: la compactacion es manual"

out=$(run nucleo_audit.py); rc=$?
ck "$rc" "0" "nucleo_audit.py sale 0"
ck "$(grep -c '^1 sessions 1 with_comp 1 compactions 1$' <<<"$out")" "1" "nucleo_audit.py: 1 sesion, 1 compactacion"
ck "$(grep -c '^2 comp: nucleo tool_use in next6 yes/no 1 0 ' <<<"$out")" "1" "nucleo_audit.py: nucleo.md releido tras compactar"
ck "$(grep -c '^3 comps w/ write within 5 turns before 1 ' <<<"$out")" "1" "nucleo_audit.py: nucleo.md escrito antes de compactar"

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
