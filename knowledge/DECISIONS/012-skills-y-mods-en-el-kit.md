# ADR 012 — El kit distribuye skills y mods, además de agentes y hooks

**Fecha:** 2026-10-14 · **Estado:** aceptada

## Contexto

El kit instalaba guards, hooks, Sentinel y agentes: el *entorno* de seguridad, pero no la
forma de trabajar que lo aprovecha. Esa metodología (IntentGate, grilling, bucle `deep-change`,
traspaso de sesión) vivía solo en la máquina de quien la inventó.

## Decisión

`kit/` distribuye también **skills** (`kit/claude/skills/`, seis) y un **mod**
(`kit/mods/cabina/`). Son la capa de instalación del método, documentado en
`kit/docs/12-metodologia.md`. `kit/` no computa en el presupuesto de complejidad (ADR 005).

- Las skills las copia `install.sh` por el camino diff-first, como los agentes (ADR 008).
- El mod **no** lo instala `install.sh`: se carga con `--plugin-dir` o `CLAUDE_CODE_PLUGIN_DIRS`.

## Rechazado

- **Meter el plugin completo de mattpocock/skills:** choca con `/code-review`, `tdd`,
  `handoff` y `research`. Se adoptan solo cinco skills sueltas, con su licencia MIT.
- **Meter `git-guardrails`:** bloquea todo `git push`, y el kit ya tiene `branch-guard.sh`,
  que solo protege las ramas que importan.
