#!/usr/bin/env bash
# test_gitattributes.sh — todo fichero versionado que se ejecuta o se parsea
# (scripts, hooks sin extension, configs) esta libre de CRLF en el arbol de
# trabajo. Sin .gitattributes, un clon con core.autocrlf=true (el default de
# Git en Windows/WSL2, el publico objetivo de este kit) convierte LF a CRLF
# y rompe cada script con "bad interpreter: /usr/bin/env bash^M". Esta suite
# tambien se auto-falsea: fabrica un fichero con CRLF a proposito y comprueba
# que la propia comprobacion lo detecta, para no confiar en un grep que
# nunca dispara.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
REPO="$(cd "$KIT/.." && pwd)"
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

cd "$REPO"

ck "$([ -f .gitattributes ] && echo y || echo n)" "y" ".gitattributes existe en la raiz del repo"

# Ficheros ejecutados o parseados por el kit: scripts, hooks sin extension,
# manifiestos. Se listan via git ls-files (lo versionado, no el arbol suelto).
mapfile -t targets < <(git ls-files -- '*.sh' '*.py' '*.yml' '*.yaml' '*.toml' '*.json' Makefile kit/claude/hooks/git/pre-commit)

ck "$([ "${#targets[@]}" -ge 1 ] && echo y || echo n)" "y" "hay ficheros candidatos que comprobar (${#targets[@]})"

crlf_found=""
for f in "${targets[@]}"; do
  [ -f "$f" ] || continue
  if grep -qU $'\r' "$f" 2>/dev/null; then
    crlf_found="$crlf_found $f"
  fi
done
ck "$([ -z "$crlf_found" ] && echo y || echo n)" "y" "ningun fichero ejecutado/parseado tiene CRLF en el arbol de trabajo:$crlf_found"

# --- Auto-falsabilidad: si fabrico un CRLF a proposito, ¿lo detecto? -------
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '#!/usr/bin/env bash\r\necho hola\r\n' > "$tmp/fake.sh"
if grep -qU $'\r' "$tmp/fake.sh"; then
  ck "y" "y" "la comprobacion SI detecta un CRLF fabricado a proposito (no es un grep que nunca dispara)"
else
  ck "n" "y" "la comprobacion SI detecta un CRLF fabricado a proposito (no es un grep que nunca dispara)"
fi

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
