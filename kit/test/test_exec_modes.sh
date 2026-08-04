#!/usr/bin/env bash
# test_exec_modes.sh — los ficheros que el kit invoca DIRECTAMENTE por nombre
# (hooks referenciados en settings.json, el hook de git) estan commiteados
# con modo 100755 en el arbol de git.
#
# Por que importa: git ignora en silencio, sin ningun mensaje de error, un
# hook que no sea ejecutable. Si uno de estos ficheros queda commiteado como
# 100644, cualquiera que clone el repo tiene ese hook muerto -- y ninguna
# observacion local del bit de ejecucion lo detecta en un filesystem que
# reporta rwx para todo (p.ex. un montaje /mnt/c de Windows) o con
# core.fileMode=false. La unica fuente fiable es lo que git tiene
# REGISTRADO, via `git ls-files -s`, no el bit del filesystem.
#
# kit/install.sh hace `chmod +x` tras copiar los hooks (defensa en
# profundidad), asi que este bug no rompe una instalacion normal -- pero
# deja el hook muerto para quien no pase por install.sh (p.ej. un
# colaborador que active core.hooksPath directamente contra el repo), y es
# trivial de reintroducir (un `git add` tras editar en un filesystem que no
# respeta el bit de ejecucion). Este test es la unica red que lo detecta.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
REPO="$(cd "$KIT/.." && pwd)"
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

cd "$REPO" || exit 1

# Ficheros invocados DIRECTAMENTE por nombre (sin "bash "/"python3 " delante):
# los hooks de kit/claude/hooks/*.sh y el hook de git (ver kit/claude/settings.json
# y install.sh), mas los entrypoints de kit/*.sh que un usuario corre como
# ./kit/doctor.sh. Los .py (invocados siempre via "python3 script.py") y los
# kit/test/*.sh (invocados siempre via "bash script.sh", ver Makefile/CI) no
# entran: no dependen de este bit.
REQUIRED_EXEC=(
  kit/claude/hooks/git/pre-commit
  kit/claude/hooks/block-dangerous-commands.sh
  kit/claude/hooks/branch-guard.sh
  kit/claude/hooks/destructive-guard.sh
  kit/claude/hooks/pre-compact.sh
  kit/claude/hooks/secret-guard.sh
  kit/claude/hooks/session-start.sh
  kit/claude/hooks/stop-session-summary.sh
  kit/doctor.sh
  kit/install.sh
  kit/scan-secrets.sh
)

# mode_of_line: extrae el modo (100755/100644) de una linea de `git ls-files -s`.
mode_of_line() { printf '%s\n' "$1" | awk '{print $1}'; }

for f in "${REQUIRED_EXEC[@]}"; do
  line="$(git ls-files -s -- "$f")"
  ck "$([ -n "$line" ] && echo y || echo n)" "y" "$f esta versionado"
  mode="$(mode_of_line "$line")"
  ck "$mode" "100755" "$f registrado como 100755 en git (git ls-files -s)"
done

# --- Auto-falsabilidad: si el modo registrado fuera 100644, ¿lo detecto? ---
# No se corrompe el indice real del repo (romperia el checkout de CI); se
# fabrica una linea de `git ls-files -s` con el mismo formato pero modo
# 100644, y se comprueba que la MISMA logica de arriba la marca como fallo.
FAKE_LINE="100644 0000000000000000000000000000000000000000 0	kit/claude/hooks/secret-guard.sh"
fake_mode="$(mode_of_line "$FAKE_LINE")"
if [ "$fake_mode" != "100755" ]; then
  ck "y" "y" "la comprobacion SI detecta un modo 100644 fabricado a proposito (no es un check que nunca dispara)"
else
  ck "n" "y" "la comprobacion SI detecta un modo 100644 fabricado a proposito (no es un check que nunca dispara)"
fi

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
