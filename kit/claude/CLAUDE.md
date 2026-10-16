@AGENTS.md

# Capa de Claude Code

Lo común a los tres runtimes está en `AGENTS.md` (importado arriba). Aquí, solo lo que depende
de los hooks, skills y subagentes que este kit instala en `~/.claude/`.

## Ceremonia según riesgo
- Trabajo sustancial, ambiguo, irreversible o que toca seguridad o producción → skill `deep-change`
  (`~/.claude/skills/deep-change/SKILL.md`, o `/deep-change`): diseño aprobado antes de ejecutar,
  commits con su porqué, y aplicar a producción solo como paso aparte, confirmado y con rollback.
- Ediciones triviales, consultas y preguntas van directas, sin ese bucle.
- Evidencia, no afirmaciones: nada está hecho sin la salida de su comando de verificación delante.

## Contexto
- Explorar y verificar se delega en los subagentes de `~/.claude/agents/` (`code-explorer`,
  `quick-checker`): al hilo principal vuelve la conclusión, no el volcado.
- Salidas de Bash acotadas y honestas (`| tail -n 40`, `grep -c`, `--stat`); nunca un filtro que reescriba la salida.
- Busca antes de leer un fichero entero (`rg -n <patrón>`) y no releas lo que ya está cargado.
- `.claude/estado/nucleo.md` es el estado; el hook avisa cuándo actualizarlo; tras compactar llega inyectado; la historia va a `diario.md`.
- Excepción a Never-Stop: con el aviso del 70 % del umbral de autocompactación, terminar la fase, actualizar el estado
  y cerrar el turno es parada válida; el handoff y `/clear` vienen después, del cockpit o de la persona.
- Cambio de tarea: `/nueva <tarea>` con cockpit (archiva el estado y limpia); sin él, `/clear`.
