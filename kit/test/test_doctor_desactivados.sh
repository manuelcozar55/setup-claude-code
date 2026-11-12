#!/usr/bin/env bash
# test_doctor_desactivados.sh — doctor distingue «apagado a proposito» de «roto»:
#   1. Un hook del kit que falta en settings.json y NO consta en .kit-desactivados es FAIL (rc 1).
#   2. Si consta (una linea por script), es INFO «desactivado por ti» y doctor sale 0.
#   3. Constar no tapa otro hook roto: con dos quitados y uno solo anotado, sigue FAIL.
#   4. Tras reinstalar (install.sh --apply devuelve el hook), la lista queda obsoleta: WARN, no FAIL.
# Es el procedimiento que documenta kit/docs/OPERAR.md. HOME aislado, sin red.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

mkdir -p "$tmp/home/.config"
export CLAUDE_HOME="$tmp/home/.claude"
S="$CLAUDE_HOME/settings.json"
doc() { env -u ANTHROPIC_BASE_URL -u CLAUDE_CONFIG_DIR HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/home/.config" bash "$KIT/doctor.sh" 2>&1; }
quitar() {  # script... -> los quita de settings.json (lo que haria la persona a mano)
  local s
  for s in "$@"; do
    jq --arg s "$s" '.hooks |= with_entries(.value |= map(.hooks |= map(select(.command | contains("/" + $s + "\"") | not))) | .value |= map(select(.hooks | length > 0)))' \
      "$S" > "$S.tmp" && mv "$S.tmp" "$S"
  done
}

HOME="$tmp/home" bash "$KIT/install.sh" --apply >/dev/null 2>&1
out="$(doc)"; rc=$?
ck "$rc" "0" "linea base: doctor sale 0 sobre una instalacion limpia"
ck "$(grep -c '^INFO ' <<<"$out")" "0" "linea base: sin .kit-desactivados no hay INFO"

quitar branch-guard.sh
out="$(doc)"; rc=$?
ck "$rc" "1" "1: hook quitado y sin anotar es FAIL"
ck "$(grep -c '^FAIL · settings.json no cablea hook(s) del kit: branch-guard.sh' <<<"$out")" "1" "1: el FAIL nombra el script"
ck "$(grep -c '\.kit-desactivados' <<<"$out")" "1" "1: el FAIL dice donde anotarlo"

printf 'branch-guard.sh\n' > "$CLAUDE_HOME/.kit-desactivados"
out="$(doc)"; rc=$?
ck "$rc" "0" "2: anotado en .kit-desactivados, doctor sale 0"
ck "$(grep -c '^INFO · desactivado por ti.*branch-guard.sh' <<<"$out")" "1" "2: sale INFO «desactivado por ti» con el script"
ck "$(grep -c '^FAIL' <<<"$out")" "0" "2: ningun FAIL"

quitar destructive-guard.sh
out="$(doc)"; rc=$?
ck "$rc" "1" "3: un segundo hook quitado sin anotar sigue siendo FAIL"
ck "$(grep -c '^FAIL .*destructive-guard.sh' <<<"$out")" "1" "3: el FAIL nombra solo el que no consta"
ck "$(grep -c '^FAIL .*branch-guard.sh' <<<"$out")" "0" "3: el anotado no sale en el FAIL"

printf '# lo quite yo\n\ndestructive-guard.sh\n' >> "$CLAUDE_HOME/.kit-desactivados"
out="$(doc)"; rc=$?
ck "$rc" "0" "3b: comentarios y lineas vacias de la lista se ignoran; con los dos anotados, rc 0"

HOME="$tmp/home" bash "$KIT/install.sh" --apply >/dev/null 2>&1
out="$(doc)"; rc=$?
ck "$rc" "0" "4: tras reinstalar el hook vuelve y una lista obsoleta no es FAIL"
ck "$(grep -c '^WARN · .kit-desactivados lista branch-guard.sh pero settings.json lo cablea' <<<"$out")" "1" "4: WARN por la lista obsoleta"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
