# ADR 002 — Presupuesto de CLAUDE.md: 100 líneas / ~900 tokens

**Fecha:** 2026-08-21 · **Estado:** aceptada

## Contexto

`~/.claude/CLAUDE.md` medía **136 líneas / ~1.978 tok**, más `RTK.md` importado (~241 tok):
**~2.219 tok de contexto fijo por sesión**.

Sobre 2,25 B de tokens de entrada medidos, eso es el **0,0001 %**. En términos de coste es
un error de redondeo, y en suscripción la caché no ahorra cuota. **Optimizar esto por coste
no tiene sentido y no es lo que se está haciendo aquí.**

## La razón real, que no es el ahorro

La documentación oficial de Claude Code lo dice sin rodeos:

> *"If your CLAUDE.md is too long, Claude ignores half of it because important rules get
> lost in the noise."*
> Fix: *"Ruthlessly prune. If Claude already does something correctly without the
> instruction, delete it or convert it to a hook."*

Y da el test por línea: *"Would removing this cause Claude to make mistakes?"*

La evidencia local es consistente con ese diagnóstico. La sección más larga del fichero
(`IntentGate`, 227 tok) regía un plan mode al **2,1 %**. `Parallel-First` apuntaba a una
skill con **0 invocaciones**. `Agent Delegation` describía 8 especialistas mientras el
**70 %** de las delegaciones iba al agente genérico y **6 de los 8 nunca se usaron**.

No es que las reglas fueran malas. Es que estaban donde no se leen.

## Decisión

**Presupuesto: `CLAUDE.md` < 100 líneas y < 900 tokens aproximados** (chars/4).
Verificado por `test_harness_structure.sh`. Resultado actual: **81 líneas / ~896 tok**.

Criterio de asignación por contenido:

| Contenido | Dónde va | Por qué |
|---|---|---|
| Gotcha no inferible del entorno | `CLAUDE.md` | Sin él se cometen errores. Pasa el test |
| Regla que ya impone un hook | fuera | Duplicar un control determinista lo debilita |
| Conocimiento de dominio o receta larga | skill | Se carga cuando hace falta |
| Regla incumplida de forma medible | hook, o se borra | Repetirla más alto no ha funcionado |
| Algo que el modelo ya hace bien | fuera | No pasa el test |

> **Este presupuesto es una decisión propia de este repo.** No procede de Anthropic.
> Se verificó el artículo de context engineering (29-sep-2025) y **no fija ningún
> presupuesto para CLAUDE.md**: los "1.000-2.000 tokens" que a veces se le atribuyen son el
> tamaño del resumen que devuelve un subagente. Atribuirlo sería falsear la fuente.

## Alternativas descartadas

- **Sin presupuesto, solo criterio.** Es lo que había, y produjo 136 líneas.
- **Presupuesto en tokens exactos** (con tokenizador real). Descartada: añade una dependencia
  para ganar precisión que no cambia ninguna decisión. `chars/4` basta para un techo.
- **Trocear en varios ficheros importados.** Descartada: mueve el bulto sin reducirlo, porque
  los imports se cargan igual.

## Consecuencias

Proyección de la auditoría: **2.219 → ~620 tok**, un 72 % menos, sin perder ninguna regla —
las que valen se mueven a donde sí se cumplen.

> **Criterio de fracaso, declarado por adelantado.** Este cambio busca **adherencia**, no
> ahorro. Si tras el recorte el retrabajo (KPI 1) no mejora, el recorte no sirvió y hay que
> escribirlo en `MISTAKES.md` en vez de celebrar los tokens ahorrados. La regla de aceptación
> del encargo lo dice: no se acepta ninguna optimización del KPI 6 que empeore el 1, 3 o 5.

## Fuentes

- Claude Code best-practices — primaria, verificada 2026-08-21.
- Anthropic, *Effective context engineering*, 29-sep-2025 — primaria, verificada.
- Medición local: `knowledge/AUDIT-CLAUDE-MD.md`, `knowledge/COST-LOG.md`.
