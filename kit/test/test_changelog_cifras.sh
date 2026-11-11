#!/usr/bin/env bash
# test_changelog_cifras.sh — Toda release >= 1.10.0 del CHANGELOG publica sus cifras de uso real.
# Por qué: la valoración del 2026-11-09 encontró 12 releases en 7 semanas y ninguna con una medida de
# efecto; el criterio de éxito de la mejora 1 es «0 releases sin cifras». Contrato: entre «## [X.Y.Z]»
# (X.Y.Z >= 1.10.0) y el siguiente «## [» hay una línea que empieza por «### Cifras». [Unreleased]
# y las versiones anteriores quedan exentas. Falsable: un CHANGELOG sintético sin bloque debe fallar.
# Solo mawk/awk POSIX: Debian trae mawk sin gawk.
set -u
cd "$(dirname "$0")/../.." || exit 1
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok - $1"; else echo "FAIL - $1: obtenido '$2', esperado '$3'"; FAIL=1; fi; }

# Imprime, una por línea, las versiones >= 1.10.0 sin bloque «### Cifras».
sin_cifras() {
  awk '
    function cierra() { if (v != "" && !tiene) print v; v = ""; tiene = 0 }
    /^## \[/ {
      cierra()
      if (match($0, /^## \[[0-9]+\.[0-9]+\.[0-9]+\]/)) {
        ver = substr($0, 5, RLENGTH - 5); n = split(ver, p, ".")
        if (n == 3 && (p[1] > 1 || (p[1] == 1 && p[2] >= 10))) v = ver
      }
      next
    }
    /^### Cifras/ { tiene = 1 }
    END { cierra() }
  ' "$1"
}

ok "CHANGELOG.md real: ninguna release >= 1.10.0 sin cifras" "$(sin_cifras CHANGELOG.md)" ""

T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
printf '## [Unreleased]\n\n- texto\n\n## [1.10.0] - 2026-11-10\n\n### Added\n\n- algo\n\n## [1.9.0] - 2026-11-09\n\n### Added\n\n- otra\n' > "$T/sin.md"
ok "falsable: 1.10.0 sin bloque se detecta" "$(sin_cifras "$T/sin.md")" "1.10.0"

printf '## [1.10.0] - 2026-11-10\n\n### Added\n\n- algo\n\n### Cifras (uso real, a → b, 2 sesiones)\n\n| Cifra | Valor |\n\n## [1.9.0] - 2026-11-09\n\n- otra\n' > "$T/con.md"
ok "1.10.0 con bloque pasa" "$(sin_cifras "$T/con.md")" ""

printf '## [2.0.0] - 2027-01-01\n\n- algo\n\n## [1.11.2] - 2026-12-01\n\n### Cifras\n\n## [1.9.5] - 2026-11-20\n\n- exenta\n' > "$T/mix.md"
ok "2.0.0 sin bloque se detecta, 1.11.2 con bloque y 1.9.5 exenta no" "$(sin_cifras "$T/mix.md" | tr '\n' ' ')" "2.0.0 "

printf '## [Unreleased]\n\n- sin cifras y exento\n' > "$T/unrel.md"
ok "[Unreleased] queda exento" "$(sin_cifras "$T/unrel.md")" ""

exit $FAIL
