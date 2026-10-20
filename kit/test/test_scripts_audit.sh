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


# --- make bateria: make test + shellcheck + scan-secrets + gitleaks, cada uno con su .rc y su .log ---
# Dobles por variable (BATERIA_*): la suite no se relanza a si misma ni toca la red. Un oraculo que falla
# tiene que dar rc != 0 con SU .rc escrito, y un binario ausente rc 127 (nunca un SKIP).
bat() {  # $1 = carpeta de salida; el resto, asignaciones make. Deja el rc de make en $brc.
  local d="$1"; shift
  make -C "$REPO" --no-print-directory bateria BATERIA_DIR="$d" BATERIA_BASE=HEAD BATERIA_TEST_CMD=true \
    BATERIA_SCAN_CMD=true BATERIA_SHELLCHECK=true BATERIA_GITLEAKS=true "$@" > "$d.out" 2>&1; brc=$?
}
bat "$tmp/bat-ok"
ck "$brc" "0" "bateria: con los cuatro verdes sale 0"
ck "$(cat "$tmp/bat-ok"/{make,sc,scan,gl}.rc | tr '\n' ' ')" "0 0 0 0 " "bateria: escribe los cuatro .rc"
ck "$(for x in make sc scan gl; do [ -f "$tmp/bat-ok/$x.log" ] && echo y; done | wc -l | tr -d ' ')" "4" "bateria: escribe los cuatro .log"
ck "$(grep -c '^make=0 sc=0 scan=0 gl=0$' "$tmp/bat-ok.out")" "1" "bateria: imprime el resumen make=0 sc=0 scan=0 gl=0"
printf '#!/bin/sh\necho "SC2086 simulado"\nexit 1\n' > "$tmp/sc-malo"; chmod +x "$tmp/sc-malo"
bat "$tmp/bat-sc" BATERIA_SHELLCHECK="$tmp/sc-malo"
ck "$([ "$brc" -ne 0 ] && echo y || echo n)" "y" "bateria: shellcheck que falla -> rc != 0 (rc=$brc)"
ck "$(cat "$tmp/bat-sc/sc.rc")" "1" "bateria: shellcheck que falla deja sc.rc=1"
ck "$(grep -c 'SC2086 simulado' "$tmp/bat-sc/sc.log")" "1" "bateria: shellcheck que falla deja su salida en sc.log"
ck "$(cat "$tmp/bat-sc/make.rc" "$tmp/bat-sc/scan.rc" "$tmp/bat-sc/gl.rc" | tr '\n' ' ')" "0 0 0 " "bateria: un fallo no impide correr los otros tres"
ck "$(grep -c '^make=0 sc=1 scan=0 gl=0$' "$tmp/bat-sc.out")" "1" "bateria: el resumen refleja sc=1"
bat "$tmp/bat-gl" BATERIA_GITLEAKS=herramienta-que-no-existe
ck "$([ "$brc" -ne 0 ] && echo y || echo n)" "y" "bateria: gitleaks ausente -> rc != 0 (rc=$brc)"
ck "$(cat "$tmp/bat-gl/gl.rc")" "127" "bateria: gitleaks ausente deja gl.rc=127 (no SKIP)"
bat "$tmp/bat-mk" BATERIA_TEST_CMD=false BATERIA_SCAN_CMD=false
ck "$(cat "$tmp/bat-mk/make.rc" "$tmp/bat-mk/scan.rc" | tr '\n' ' ')" "1 1 " "bateria: make test y scan que fallan dejan su .rc"
ck "$([ "$brc" -ne 0 ] && echo y || echo n)" "y" "bateria: make test y scan que fallan -> rc != 0"

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
