#!/usr/bin/env bash
# test_install_plugins.sh — install-plugins.sh instala plugins de terceros por referencia:
# sin --apply no ejecuta nada (diff-first), con --apply llama a `claude plugin` con los ids
# esperados, lo opcional (impeccable, find-skills) solo entra con --with-optional y un fallo
# de `claude` corta con exit != 0. Sin red: `claude`, `npx` y `pnpm` son dobles que registran.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; SCRIPT="$HERE/../install-plugins.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

mkdir -p "$tmp/bin"; log="$tmp/calls.log"
for b in claude npx; do
  # shellcheck disable=SC2016  # $* y FAIL_ON los expande el doble al ejecutarse, no este script
  printf '#!%s\necho "%s $*" >> "%s"\n[ -z "${FAIL_ON:-}" ] || [[ "$*" != *"$FAIL_ON"* ]]\n' "$BASH" "$b" "$log" > "$tmp/bin/$b"
  chmod +x "$tmp/bin/$b"
done
# Solo los dobles en PATH: un pnpm/claude real del sistema nunca se ejecuta.
run(){ : > "$log"; PATH="$tmp/bin" "$BASH" "$SCRIPT" "$@" > "$tmp/out" 2>&1; }

run; ck "$?" "0" "modo diff: exit 0"
ck "$(wc -l < "$log" | tr -d ' ')" "0" "modo diff: no ejecuta ningun comando"
ck "$(grep -c '^claude plugin install' "$tmp/out")" "4" "modo diff: imprime 4 instalaciones recomendadas"

run --apply; ck "$?" "0" "--apply: exit 0"
for id in superpowers@claude-plugins-official frontend-design@claude-plugins-official ponytail@ponytail ui-ux-pro-max@ui-ux-pro-max-skill; do
  ck "$(grep -c "^claude plugin install $id --scope user --yes$" "$log")" "1" "--apply instala $id en scope user"
done
ck "$(grep -c 'marketplace add DietrichGebert/ponytail --scope user' "$log")" "1" "--apply registra el marketplace de ponytail"
ck "$(grep -c 'impeccable\|find-skills' "$log")" "0" "sin --with-optional no entra lo opcional"
ck "$(grep -c '^claude plugin marketplace add' "$log")" "2" "solo registra los 2 marketplaces de terceros (el oficial ya viene)"

run --apply --with-optional; ck "$?" "0" "--with-optional: exit 0"
ck "$(grep -c '^claude plugin install impeccable@impeccable' "$log")" "1" "--with-optional instala impeccable"
ck "$(grep -c '^claude plugin marketplace add pbakaus/impeccable --scope user$' "$log")" "1" "--with-optional registra el marketplace de impeccable"
ck "$(grep -c '^npx skills add vercel-labs/skills --skill find-skills -g -a claude-code -y$' "$log")" "1" "--with-optional instala find-skills (npx sin pnpm)"

cp "$tmp/bin/npx" "$tmp/bin/pnpm"; sed -i 's/echo "npx/echo "pnpm/' "$tmp/bin/pnpm"
run --apply --with-optional
ck "$(grep -c '^pnpm dlx skills add vercel-labs/skills --skill find-skills' "$log")" "1" "con pnpm en PATH usa pnpm dlx"
rm "$tmp/bin/pnpm"

# Falsabilidad: si `claude` falla, el script no sigue ni dice que ha instalado
set +e; FAIL_ON=ponytail@ponytail run --apply; rc=$?; set -e
ck "$([ "$rc" -ne 0 ] && echo rojo || echo verde)" "rojo" "falsabilidad: fallo de claude => exit != 0"
ck "$(grep -c 'ui-ux-pro-max@' "$log")" "0" "tras el fallo no ejecuta los siguientes"

set +e; run --bogus; rc=$?; set -e
ck "$rc" "2" "argumento desconocido => exit 2"

echo "pass=$pass fail=$fail"
[ "$fail" = 0 ]
