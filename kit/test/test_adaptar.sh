#!/usr/bin/env bash
# test_adaptar.sh — kit/docs/guia/06-adaptar.md es falsable: los bloques ```bash de la guia se ejecutan tal cual
# sobre un HOME aislado, en su orden, y cada afirmacion de la guia se comprueba:
#   1. hook propio: el script corre y su cableado en settings.json sobrevive a install.sh --apply.
#   2. umbral: CC_PROTECT_BRANCHES en el env de settings.json cambia lo que branch-guard.sh bloquea, y sobrevive.
#   3. agente: borrado y anotado, doctor sale 0 con INFO; tras actualizar vuelve y doctor avisa con WARN solo si lo cablea.
#   4. actualizacion: un CLAUDE.md propio no se pisa (el kit deja CLAUDE.kit.md).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."; ROOT="$KIT/.."
GUIA="$KIT/docs/guia/06-adaptar.md"
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

mkdir -p "$tmp/home/.config" "$tmp/bloques"
export HOME="$tmp/home" CLAUDE_HOME="$tmp/home/.claude" XDG_CONFIG_HOME="$tmp/home/.config"
unset ANTHROPIC_BASE_URL CLAUDE_CONFIG_DIR CC_PROTECT_BRANCHES CC_ALLOW_DESTRUCTIVE
S="$CLAUDE_HOME/settings.json"
bash "$KIT/install.sh" --apply >/dev/null 2>&1; ck "$?" "0" "instalacion base en HOME aislado"

awk -v d="$tmp/bloques" '/^```bash/ { n++; on = 1; next } /^```/ { on = 0; next } on { print > (d "/" n ".sh") }' "$GUIA"
ck "$(find "$tmp/bloques" -type f | wc -l)" "3" "la guia tiene 3 bloques bash (hook, umbral, agente)"

for n in 1 2 3; do
  (cd "$ROOT" && bash -e "$tmp/bloques/$n.sh" >"$tmp/salida$n" 2>&1); ck "$?" "0" "el bloque $n de la guia se ejecuta tal cual (rc 0)"
done

# 1: hook propio
ck "$(printf '{"tool_input":{"command":"ls"}}' | "$CLAUDE_HOME/hooks/mi-hook.sh" 2>&1)" "mi-hook: ls" "1: el hook propio imprime lo que dice la guia"
cableado() { jq -r '[.hooks.PreToolUse[].hooks[].command | select(contains("mi-hook.sh"))] | length' "$S"; }
ck "$(cableado)" "1" "1: el hook propio esta cableado en PreToolUse"

# 2: umbral
push() { printf '{"tool_name":"Bash","tool_input":{"command":"git push origin %s"}}' "$1"; }
guard() {  # rama -> rc de branch-guard con el env de settings.json aplicado, como hace Claude Code
  ( cd "$tmp" || exit 9
    while IFS='=' read -r k v; do export "$k=$v"; done < <(jq -r '.env // {} | to_entries[] | select(.key | startswith("CC_")) | "\(.key)=\(.value)"' "$S")
    push "$1" | bash "$CLAUDE_HOME/hooks/branch-guard.sh" >/dev/null 2>&1 )
}
guard main; ck "$?" "0" "2: con CC_PROTECT_BRANCHES=production, un push a main pasa"
guard production; ck "$?" "2" "2: y un push a production se bloquea"
( cd "$tmp" && push main | bash "$CLAUDE_HOME/hooks/branch-guard.sh" >/dev/null 2>&1 ); ck "$?" "2" "2: sin la variable, main sigue protegida"

# 3: agente
ck "$([ ! -e "$CLAUDE_HOME/agents/code-reviewer.md" ] && echo borrado)" "borrado" "3: el agente esta borrado"
out="$(env -u CLAUDE_CONFIG_DIR bash "$KIT/doctor.sh" 2>&1)"; rc=$?
ck "$rc" "0" "3: doctor sale 0 con el agente borrado y anotado"
ck "$(grep -c '^INFO · desactivado por ti (consta en .kit-desactivados): agents/code-reviewer.md' <<<"$out")" "1" "3: doctor lo cuenta como desactivado por ti"

# 4: actualizar
echo "# mio" >> "$CLAUDE_HOME/CLAUDE.md"
bash "$KIT/install.sh" --apply >/dev/null 2>&1; ck "$?" "0" "4: install.sh --apply sobre la instalacion adaptada"
ck "$(cableado)" "1" "4: el hook propio sobrevive a la actualizacion"
ck "$(jq -r '.env.CC_PROTECT_BRANCHES' "$S")" "production" "4: el umbral propio sobrevive a la actualizacion"
ck "$([ -x "$CLAUDE_HOME/hooks/mi-hook.sh" ] && echo si)" "si" "4: el script del hook propio sobrevive"
ck "$(tail -1 "$CLAUDE_HOME/CLAUDE.md")" "# mio" "4: tu CLAUDE.md no se pisa"
ck "$([ -f "$CLAUDE_HOME/CLAUDE.kit.md" ] && echo si)" "si" "4: el del kit queda como CLAUDE.kit.md"
ck "$([ -f "$CLAUDE_HOME/agents/code-reviewer.md" ] && echo vuelve)" "vuelve" "4: el agente quitado vuelve (la guia lo dice)"
out="$(bash "$KIT/doctor.sh" 2>&1)"; rc=$?
ck "$rc" "0" "4: doctor sigue sin FAIL tras la actualizacion"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
