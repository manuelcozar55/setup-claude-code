# ADR 024 — Retirar el agente `orchestrator` del kit

**Fecha:** 2026-10-29 · **Estado:** aceptada (decisión de la persona, M13)

## Contexto

`orchestrator` (opus) descomponía tareas en frentes paralelos. `knowledge/COST-LOG.md` (sección de delegación, 141
sesiones, 150 llamadas a `Agent`) lo cuenta entre los agentes propios con 0 invocaciones: la delegación real va a
`general-purpose` (70 %) y `deep-worker` (11 %). La paralelización la cubren `strategist` (plan) y `deep-worker`
(ejecución), más la skill de despacho en paralelo del plugin `esenciales`.

## Decisión

Se borra `kit/claude/agents/orchestrator.md`. El kit pasa de 7 a 6 agentes. `strategist` recomienda `deep-worker`
como único ejecutor. Ningún agente ni skill del kit delega en `orchestrator` (`git grep subagent_type kit/` no lo
nombra). Cifras actualizadas en `README.md`, `kit/README.md` y `kit/docs/` (01, 02, 04, 10).

## Límites

- La evidencia de uso 0 sale de una máquina (la de la persona); en otras instalaciones podría haberse usado.
- `install.sh --apply` no borra agentes ya instalados: `~/.claude/agents/orchestrator.md` sigue en las máquinas
  existentes. **Lo borra la persona a mano** (no se toca `~/.claude` desde el trabajo del repo).
- `knowledge/COST-LOG.md` y `CHANGELOG.md` conservan las menciones históricas.

## Vuelta atrás

Revertir los commits recupera el agente.
