#!/usr/bin/env bash
# test_guia.sh — la guía didáctica (kit/docs/guia/) existe, está enlazada desde el mapa y no
# tiene enlaces rotos. Una guía que manda a un fichero que no existe enseña a desconfiar de ella.
set -u
cd "$(dirname "$0")/../.." || exit 1
G=kit/docs/guia; OV=kit/docs/01-overview.md
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (esperado '$3', sale '$2')"; FAIL=1; fi; }

# rotos <fichero.md>: imprime cada enlace relativo que no resuelve desde el directorio del fichero.
rotos() {
  local d t; d=$(dirname "$1")
  command grep -oE '\]\([^)]+\)' "$1" | sed -E 's/^\]\(//; s/\)$//; s/#.*//' | while IFS= read -r t; do
    case "$t" in ''|http://*|https://*|mailto:*) continue ;; esac
    [ -e "$d/$t" ] || echo "$1 -> $t"
  done
}

for f in 00-ruta-7-dias.md 01-por-que-contexto.md 02-sesion-real.md 03-antipatrones.md \
         04-mide-tu-setup.md 06-adaptar.md README.en.md; do
  ok "existe $G/$f" "$([ -s "$G/$f" ] && echo si)" si
  ok "$OV enlaza guia/$f" "$(command grep -c "](guia/$f)" "$OV")" 1
done
for f in "$G"/*.md; do
  ok "enlaces relativos de $f resuelven" "$(rotos "$f")" ""
done

# El sensor sabe suspender: un enlace roto sembrado tiene que salir.
T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
printf '[bien](bien.md) [web](https://example.com) [ancla](#x) [mal](no-existe.md#y)\n' >"$T/a.md"; : >"$T/bien.md"
ok "rotos() caza un enlace roto y solo ese" "$(rotos "$T/a.md")" "$T/a.md -> no-existe.md"
exit $FAIL
