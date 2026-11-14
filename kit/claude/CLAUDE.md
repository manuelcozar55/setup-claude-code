@AGENTS.md

# Capa de Claude Code

Lo común a los tres runtimes está en `AGENTS.md` (importado arriba). Aquí, solo lo que depende
de los hooks, skills y subagentes que este kit instala en `~/.claude/`.

## Ceremonia según riesgo
- Trabajo sustancial, ambiguo, irreversible o que toca seguridad o producción → skill `deep-change`
  (`~/.claude/skills/deep-change/SKILL.md`, o `/deep-change`): diseño aprobado antes de ejecutar,
  commits con su porqué, y aplicar a producción solo como paso aparte, confirmado y con rollback.
- Ediciones triviales, consultas y preguntas van directas, sin ese bucle.
- Cambio mínimo por parche; nunca reescribir un fichero entero.
- Evidencia, no afirmaciones: verifica con `oraculo -- <cmd>` (rc real; si no, `set -o pipefail`); nada está hecho sin esa salida delante.

## Interfaces
- UI: entra por `/impeccable` si está instalada; `ui-ux-pro-max` es solo su fuente de datos
  (UX, accesibilidad, gráficos, stack), nunca la dirección visual.

## Contexto
- Explorar y verificar se delega en los subagentes de `~/.claude/agents/` (`code-explorer`,
  `quick-checker`): al hilo principal vuelve la conclusión, no el volcado.
- Salidas de Bash acotadas y honestas (`| tail -n 40`, `grep -c`, `--stat`); nunca un filtro que reescriba la salida.
- Busca antes de leer un fichero entero (`rg -n <patrón>`) y no releas lo que ya está cargado.
- Si el proyecto tiene `ESTADO.md` en la raíz y no `nucleo.md`, ese es su estado; no crees `nucleo.md`.
- `.claude/estado/nucleo.md` es el estado: se guarda solo tras cada turno, al compactar y al cerrar (`autosave.sh`, ADR 028; también en un repo sin estado), tras compactar llega inyectado y la historia va a `diario.md`. `handoff --desde` (o `/handoff` con cockpit) fija el foco. Variables: `docs/12-metodologia.md`.
- Fin de fase = parada válida: con el aviso de contexto (persona 60 %, modelo 70 %): `handoff`, informe y propuesta de siguiente foco; después `/clear`. El autocompact es solo el airbag.
- Toda espera de fondo lleva `timeout`: un shell de fondo vivo bloquea el handoff automático.
- Cambio de tarea: `/nueva <tarea>` con cockpit (archiva el estado y limpia); sin él, `/clear`.
