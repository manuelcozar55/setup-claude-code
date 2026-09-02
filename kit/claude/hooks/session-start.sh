#!/usr/bin/env bash
# SessionStart hook — brief context reminder
#
# NO imprime el cuerpo de MEMORY.md: el sistema de auto-memoria de Claude Code ya
# lo inyecta por su cuenta, y hasta 2026-08-25 el indice entero llegaba DOS veces
# al contexto (~985 tokens duplicados por sesion). Lo que este hook aporta y la
# auto-memoria no es la senal de vida: si esta linea no aparece, la ruta de
# memoria no es la que crees, y eso hay que verlo.
MEMORY="$HOME/.claude/projects/$(echo "$PWD" | tr '/' '-')/memory/MEMORY.md"
# El limite estaba en 20 y el indice ya iba por 16 (2026-08-17): a cuatro memorias
# de empezar a perderlas sin decir nada. Si se vuelve a alcanzar, que se note.
LIMIT=60
if [ -f "$MEMORY" ]; then
  N=$(grep -c '^- \[' "$MEMORY" 2>/dev/null || echo 0)
  echo "[SessionStart] Memory: $N entradas en $MEMORY"
  if [ "$(wc -l < "$MEMORY")" -gt "$LIMIT" ]; then
    echo "[SessionStart] AVISO: MEMORY.md supera $LIMIT lineas; poda el indice."
  fi
else
  echo "[SessionStart] No project memory found. Global: ~/.claude/CLAUDE.md active."
fi
