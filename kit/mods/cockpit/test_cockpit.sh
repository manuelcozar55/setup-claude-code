#!/usr/bin/env bash
# test_cockpit.sh — capas ejecutables del mod cockpit (kit/mods/cockpit):
#   1. tsc sobre una copia de lo VERSIONADO (como un clon limpio: el tsconfig no puede depender de nada generado).
#   2. contrato con el CLI real kit/claude/bin/handoff (sin claude, sin red).
#   3. claude plugin validate y claude plugin test (no cuestan dinero). Sin `claude`: SKIP anunciado, nunca verde.
# tsc: COCKPIT_TSC, o `tsc` del PATH, o `pnpm dlx typescript@5.6.3 tsc`. Sin ninguno: SKIP anunciado.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../.." && pwd)"
MOD="$ROOT/kit/mods/cockpit"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
pass=0; fail=0
check() { if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 (got $1 want $2)"; fail=$((fail+1)); fi; }
skip() { echo "SKIP - $1"; [ -z "${SCC_SKIP_LOG:-}" ] || echo "SKIP: $1 (test_cockpit.sh)" >> "$SCC_SKIP_LOG"; }

# ---- 1. tsc en un clon limpio del mod
copy="$tmp/clon"
mkdir -p "$copy"
if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 && [ -n "$(git -C "$ROOT" ls-files kit/mods/cockpit)" ]; then
  (cd "$ROOT" && git ls-files -z kit/mods/cockpit | xargs -0 -I{} cp --parents {} "$copy")
else
  mkdir -p "$copy/kit/mods" && cp -R "$MOD" "$copy/kit/mods/"
fi
if [ -n "${COCKPIT_TSC:-}" ]; then read -r -a TSC <<<"$COCKPIT_TSC"
elif command -v tsc >/dev/null 2>&1; then TSC=(tsc)
elif command -v pnpm >/dev/null 2>&1 && timeout 120 pnpm dlx typescript@5.6.3 tsc --version >/dev/null 2>&1; then TSC=(pnpm dlx typescript@5.6.3 tsc)
else TSC=(); fi
if [ "${#TSC[@]}" -gt 0 ]; then
  set +e; (cd "$copy/kit/mods/cockpit" && "${TSC[@]}" -p . --noEmit >"$tmp/tsc.log" 2>&1); rc=$?; set -e
  [ "$rc" -eq 0 ] || head -20 "$tmp/tsc.log"
  check "$rc" "0" "tsc en un clon limpio del mod"
  # Falsabilidad: un error de tipos plantado tiene que dar rojo.
  printf 'export const planted: number = "x"\n' > "$copy/kit/mods/cockpit/hooks/planted.ts"
  set +e; (cd "$copy/kit/mods/cockpit" && "${TSC[@]}" -p . --noEmit >/dev/null 2>&1); rc=$?; set -e
  check "$([ "$rc" -ne 0 ] && echo rojo || echo verde)" "rojo" "falsabilidad: un error de tipos plantado da rojo"
else
  # En CI (COCKPIT_REQUIRE_TSC=1) la ausencia de tsc es un fallo, no un salto.
  if [ -n "${COCKPIT_REQUIRE_TSC:-}" ]; then check "sin tsc" "tsc" "hay un tsc con el que tipar el cockpit"
  else skip "tsc del cockpit: no hay tsc ni pnpm dlx (define COCKPIT_TSC)"; fi
fi

# ---- 2. contrato con el CLI real
# Los tests del mod simulan el CLI con un stub; aqui corre el bin/handoff REAL con los borradores que el mod pide y con
# los que no debe producir. Sandbox: HOME propio, repo git propio, sin red.
CLI="$ROOT/kit/claude/bin/handoff"
REG="$MOD/hooks/register.tsx"
SB="$tmp/sb"; mkdir -p "$SB/home" "$SB/proj" "$SB/proj2"
git -C "$SB/proj" init -q . && git -C "$SB/proj2" init -q .
cli() { local root=$1; shift; (cd "$root" && env HOME="$SB/home" CLAUDE_HOME="$SB/home/.claude" CLAUDE_PROJECT_DIR="$root" CLAUDE_PID= CLAUDE_CONFIG_DIR="$SB/home/.claude" bash "$CLI" "$@"); }
accent() { sed 's/á/a/g; s/é/e/g; s/í/i/g; s/ó/o/g; s/ú/u/g' | tr '[:upper:]' '[:lower:]'; }

# 2a. Las cabeceras que el prompt del mod pide (HANDOFF_PROMPT y firstNote) son todas admitidas por el CLI.
mod_heads="$(awk '/^export const HANDOFF_PROMPT = `/{on=1} on && /^## /{print substr($0,4)} /^Sé concreto/{on=0}' "$REG"; grep '^const firstNote' "$REG" | grep -o '«## [A-Za-z]*»' | sed 's/«## //; s/»//')"
check "$(printf '%s\n' "$mod_heads" | grep -c .)" "8" "el prompt del mod pide 8 secciones (6 de HANDOFF_PROMPT + Objetivo e Invariantes)"
draft="$SB/draft.md"; : >"$draft"
while IFS= read -r h; do [ -z "$h" ] || printf '## %s\ncontenido de %s\n' "$h" "$h" >>"$draft"; done <<<"$mod_heads"
set +e; out="$(cli "$SB/proj" --desde "$draft" --raiz "$SB/proj" --sesion s1 --json 2>"$tmp/err")"; rc=$?; set -e
check "$rc" "0" "CLI real: el borrador completo que pide el mod se guarda (rc 0)"
check "$(printf '%s' "$out" | jq -r '(.nucleo | endswith("/nucleo.md")) and (.sha256 | test("^[a-f0-9]{64}$"))' 2>/dev/null)" "true" "CLI real: el recibo trae nucleo y sha256 de 64 hex (lo que exige el mod)"

# 2b. La lista ADMITTED del mod es la del CLI.
cli_list="$(grep -o 'admitidas: [^)]*' "$CLI" | head -1 | sed 's/admitidas: //' | tr ',' '\n' | sed 's/^ *//' | accent | sort)"
mod_list="$(grep '^const ADMITTED = ' "$REG" | grep -o "'[a-z ]*'" | tr -d "'" | sort)"
check "$mod_list" "$cli_list" "ADMITTED del mod = admitidas del CLI"
ok_all=1
while IFS= read -r h; do
  printf '## %s\nx\n' "$h" >"$SB/one.md"
  # Un estado nuevo cada vez: el borrador de una sola seccion no debe depender del anterior.
  rm -r "$SB/proj2/.claude" 2>/dev/null || true
  cli "$SB/proj2" --desde "$SB/one.md" --raiz "$SB/proj2" --sesion s1 --json >/dev/null 2>&1 || { ok_all=0; echo "  rechazada: $h"; }
done <<<"$(grep -o 'admitidas: [^)]*' "$CLI" | head -1 | sed 's/admitidas: //' | tr ',' '\n' | sed 's/^ *//')"
check "$ok_all" "1" "CLI real: cada cabecera de ADMITTED se admite sola"

# 2c. Lo que el mod no debe producir: una cabecera fuera de la plantilla es rc 2 con la cabecera nombrada.
printf '## Plan\n- [ ] a\n## Notas\nalgo suelto\n' >"$SB/notas.md"
set +e; cli "$SB/proj" --desde "$SB/notas.md" --raiz "$SB/proj" --sesion s1 --json >"$SB/o" 2>"$SB/e"; rc=$?; set -e
check "$rc" "2" "CLI real: «## Notas» es rc 2 (por eso el mod la descarta antes de llamar)"
check "$(grep -c 'cabecera no admitida «Notas»' "$SB/e")" "1" "CLI real: el rc 2 nombra la cabecera"
printf '## Plan\n- [ ] a\n## Plan\n- [ ] b\n' >"$SB/rep.md"
set +e; cli "$SB/proj" --desde "$SB/rep.md" --raiz "$SB/proj" --sesion s1 --json >/dev/null 2>"$SB/e"; rc=$?; set -e
check "$rc" "2" "CLI real: una cabecera repetida es rc 2 (el mod deja la primera)"

# 2d. --estado: los campos que el mod lee y los rc que distingue (3 sin proyecto, 5 con dueño ajeno).
est="$(cli "$SB/proj" --estado --raiz "$SB/proj" --sesion s1)"
check "$(printf '%s' "$est" | jq -r '[.nucleo,.pct,.bytes,.tope,.agentes_vivos] | map(. != null) | all')" "true" "CLI real: --estado trae nucleo, pct, bytes, tope y agentes_vivos"
check "$(printf '%s' "$est" | jq -r 'has("dueno")')" "true" "CLI real: --estado trae dueno"
printf 'sesion=otra-sesion\ndesde=%s\n' "$(date +%s)" >"$SB/proj/.claude/estado/.dueno"
check "$(cli "$SB/proj" --estado --raiz "$SB/proj" --sesion s1 | jq -c '.dueno | [.sesion, .vigente]')" '["otra-sesion",true]' "CLI real: --estado nombra al dueño ajeno y su vigencia (el mod no forkea si es vigente)"
set +e; cli "$SB/proj" --desde "$SB/draft.md" --raiz "$SB/proj" --sesion s1 --json >/dev/null 2>&1; rc=$?; set -e
check "$rc" "5" "CLI real: --desde con dueño ajeno es rc 5"
set +e; (cd "$SB/home" && env HOME="$SB/home" CLAUDE_HOME="$SB/home/.claude" CLAUDE_PID= bash "$CLI" --estado --sesion s1 >/dev/null 2>&1); rc=$?; set -e
check "$rc" "3" "CLI real: --estado en ~ sin ranura es rc 3"

# 2e. ESTADO.md: «Decisiones» y «Cómo se comprueba» solo se admiten con ESTADO.md como estado (lista ADMITTED_ESTADO_MD).
printf '# Estado\n\n- Objetivo (una línea): x\n' >"$SB/proj2/ESTADO.md"
rm -r "$SB/proj2/.claude" 2>/dev/null || true
printf '## Decisiones\n- d\n' >"$SB/dec.md"
set +e; cli "$SB/proj2" --desde "$SB/dec.md" --raiz "$SB/proj2" --sesion s1 --json >/dev/null 2>&1; rc=$?; set -e
check "$rc" "0" "CLI real: «## Decisiones» se admite con ESTADO.md como estado"
check "$(grep '^const ADMITTED_ESTADO_MD = ' "$REG" | grep -o "'[a-z ]*'" | tr -d "'" | sort | tr '\n' ,)" "como se comprueba,decisiones," "el mod admite en modo ESTADO.md solo decisiones y como se comprueba"
rm "$SB/proj2/ESTADO.md"; rm -r "$SB/proj2/.claude" 2>/dev/null || true
set +e; cli "$SB/proj2" --desde "$SB/dec.md" --raiz "$SB/proj2" --sesion s1 --json >/dev/null 2>&1; rc=$?; set -e
check "$rc" "2" "CLI real: sin ESTADO.md como estado «## Decisiones» es rc 2"

# ---- 3. claude plugin validate / test
if command -v claude >/dev/null 2>&1; then
  set +e
  claude plugin validate "$MOD" >"$tmp/validate.log" 2>&1; rcv=$?
  claude plugin test "$MOD" >"$tmp/test.log" 2>&1; rct=$?
  set -e
  [ "$rcv" -eq 0 ] || tail -20 "$tmp/validate.log"
  [ "$rct" -eq 0 ] || tail -30 "$tmp/test.log"
  check "$rcv" "0" "claude plugin validate"
  check "$rct" "0" "claude plugin test ($(grep -E '^ *[0-9]+ pass' "$tmp/test.log" | tr -d ' ' | head -1))"
else
  skip "claude plugin validate/test del cockpit: claude no esta en PATH"
fi

echo "pass=$pass fail=$fail"
[ "$fail" -eq 0 ]
