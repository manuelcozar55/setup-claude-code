#!/usr/bin/env bash
# claude-characterization.sh — foto reproducible del Claude que este arbol proyecta.
#
# El todo 14 del plan provider-agnostic-agent-harness necesita una BASELINE contra
# la que los todos posteriores (15-22, 26) comparen: si un refactor cambia un byte
# de la superficie de Claude sin querer, esta foto tiene que ponerse en rojo.
#
# La foto son tres anclas deterministas, todas sobre la FUENTE versionada (no sobre
# un $CLAUDE_HOME instalado, que embebe rutas de la maquina):
#
#   1. source_tree_sha256  — sha256 de (ruta relativa + contenido) de los 29 ficheros
#      bajo kit/claude/ y kit/sentinel/ que install.sh proyecta 1:1 en CLAUDE_HOME.
#      Un fichero nuevo, borrado o editado en esa superficie mueve este digest.
#   2. source_file_count   — cuantos ficheros hay en esa superficie (29 hoy).
#   3. script_sha256[...]  — sha256 de los tres scripts endurecidos que gobiernan el
#      ciclo de vida (install/doctor/uninstall), es decir el "estado pre-refactor"
#      que el todo 19 promete no alterar en su comportamiento.
#
# Se emite JSON canonico (claves ordenadas, sin espacios superfluos) por stdout para
# que `diff` byte-a-byte contra la baseline sea la asercion. Sin red, sin instalar.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/.." && pwd)"

# Superficie que se proyecta en Claude. Orden estable con LC_ALL=C.
tree_sha256() {  # $1.. = dirs
  ( cd "$REPO" && find "$@" -type f -exec sha256sum {} + | LC_ALL=C sort -k2 \
      | sha256sum | cut -d' ' -f1 )
}
file_count() {  # $1.. = dirs
  ( cd "$REPO" && find "$@" -type f | wc -l | tr -d ' ' )
}
file_sha256() {  # $1 = ruta relativa
  ( cd "$REPO" && sha256sum "$1" | cut -d' ' -f1 )
}

SURFACE=(kit/claude kit/sentinel)

TREE="$(tree_sha256 "${SURFACE[@]}")"
COUNT="$(file_count "${SURFACE[@]}")"
INSTALL="$(file_sha256 kit/install.sh)"
DOCTOR="$(file_sha256 kit/doctor.sh)"
UNINSTALL="$(file_sha256 uninstall.sh)"

# JSON canonico a mano: claves en orden lexicografico, sin blancos superfluos.
printf '{'
printf '"schema":"claude-characterization-v1",'
printf '"scripts":{'
printf '"doctor_sha256":"%s",' "$DOCTOR"
printf '"install_sha256":"%s",' "$INSTALL"
printf '"uninstall_sha256":"%s"' "$UNINSTALL"
printf '},'
printf '"source_file_count":%s,' "$COUNT"
printf '"source_tree_sha256":"%s",' "$TREE"
printf '"surface":["kit/claude","kit/sentinel"]'
printf '}\n'
