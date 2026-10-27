# ADR 021 — `PostCompact` en el kit: medir lo que sobrevive al resumen

**Fecha:** 2026-10-26 · **Estado:** aceptada

## Contexto

Un sensor suelto (`post-compact-check.sh`, fuera del kit) comparaba el resumen con el checkpoint y dejaba una
línea en `session-logs/compact-AAAA-MM.log`, que lee `scripts/compact-audit.py`. Calló el 20-oct: la
reinstalación del 21-oct lo dejó sin cablear, porque el kit no lo conocía. Además buscaba el checkpoint en
`estado/`, y `pre-compact.sh` escribe en `estado/checkpoints/`.

## Decisión

El kit trae `hooks/post-compact-check.sh` y es dueño de la entrada `PostCompact` (timeout 5 s). Contrato
verificado en la doc oficial (code.claude.com/docs/en/hooks, «PostCompact input»): además de los campos comunes,
`trigger` (`manual|auto`) y `compact_summary`. Sin control de decisión: solo efectos laterales; no puede
bloquear. Mismo formato de log (`anclas_perdidas=N`), misma ruta de checkpoint que `pre-compact.sh` (bajo `~`,
`estado/` a secas). Sin modelo, falla en abierto, exit 0 siempre.

## Descartado

- Dejarlo fuera del kit: la fusión por propietario no protege lo que el kit no declara suyo.
- Escribir en `~/.claude/session-logs` fijo: se respeta `CLAUDE_HOME`, como `pre-compact.sh`; el lector sigue
  mirando `~/.claude` (instalación por defecto).
