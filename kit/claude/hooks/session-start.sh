#!/usr/bin/env bash
# SessionStart hook — brief context reminder
#
# NO imprime el cuerpo de MEMORY.md: el sistema de auto-memoria de Claude Code ya
# lo inyecta por su cuenta, y hasta 2026-08-25 el indice entero llegaba DOS veces
# al contexto (~985 tokens duplicados por sesion). Lo que este hook aporta y la
# auto-memoria no es la senal de vida: si esta linea no aparece, la ruta de
# memoria no es la que crees, y eso hay que verlo.
# Claude Code nombra el directorio del proyecto cambiando todo carácter no alfanumérico por «-» (un «.» o un
# «_» en la ruta también); `/`→`-` solo queda de respaldo por si esa regla cambia.
MEMORY="$HOME/.claude/projects/$(printf '%s' "$PWD" | sed 's/[^A-Za-z0-9]/-/g')/memory/MEMORY.md"
[ -f "$MEMORY" ] || MEMORY="$HOME/.claude/projects/$(printf '%s' "$PWD" | tr '/' '-')/memory/MEMORY.md"
# El limite estaba en 20 y el indice ya iba por 16 (2026-08-17): a cuatro memorias
# de empezar a perderlas sin decir nada. Si se vuelve a alcanzar, que se note.
LIMIT=60
if [ -f "$MEMORY" ]; then
  N=$(grep -c '^- \[' "$MEMORY" 2>/dev/null) || N=${N:-0}
  echo "[SessionStart] Memory: $N entradas en $MEMORY"
  if [ "$(wc -l < "$MEMORY")" -gt "$LIMIT" ]; then
    echo "[SessionStart] AVISO: MEMORY.md supera $LIMIT lineas; poda el indice."
  fi
else
  echo "[SessionStart] No project memory found. Global: ~/.claude/CLAUDE.md active."
fi
