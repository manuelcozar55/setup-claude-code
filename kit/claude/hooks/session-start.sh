#!/usr/bin/env bash
# SessionStart hook — brief context reminder
#
# NO imprime el cuerpo de MEMORY.md. La auto-memoria de Claude Code ya inyecta ese
# indice por su cuenta, asi que volcarlo aqui lo mete DOS VECES en el contexto de
# cada sesion (medido 2026-08-25: ~985 tokens duplicados por arranque, gratis).
# Lo que este hook aporta y la auto-memoria no es la senal de vida: si esta linea
# no sale, la ruta de memoria no es la que crees, y eso hay que verlo.
MEMORY="$HOME/.claude/projects/$(echo "$PWD" | tr '/' '-')/memory/MEMORY.md"
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
