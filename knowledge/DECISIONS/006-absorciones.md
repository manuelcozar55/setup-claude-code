# ADR 006 — Absorber `harness` y `ai-mastery/bucle` sin reescribirlos

**Fecha:** 2026-08-21 · **Estado:** aceptada

## Contexto

Dos piezas ya existían fuera del repo y funcionaban:

- **`~/.claude/skills/harness/`** — cola de tareas con oráculo obligatorio e inmutable,
  reanudación de tareas `en-curso`, presupuesto de tiempo y máximo 3 reparaciones.
- **`~/ai-mastery/bucle/`** — `analyze.py` (~50 métricas sobre transcripts) y `render.py`,
  ambos 100 % stdlib.

La tentación por defecto ante código ajeno es reescribirlo con el estilo propio. Es casi
siempre una mala idea: se pierde comportamiento que nadie documentó y se importan bugs
nuevos a cambio de coherencia estética.

## Decisión

**`skills/harness/` entra tal cual, verificado por checksum.**

```
identico  SKILL.md
identico  PLANTILLA-TAREAS.md
identico  referencias/oraculos.md
```

Su doctrina —*"ninguna tarea entra en ejecución sin un oráculo"* y *"el oráculo es inmutable
durante la ejecución de su tarea"*— es exactamente la tesis de mcharness, mejor formulada de
lo que la habría escrito de cero. Además ya documenta un primo hermano de M-001: que probar
con `python3` en vez de con el intérprete correcto produjo *"un diagnóstico de 'no hay ningún
oráculo ejecutable' que era rotundamente falso"*.

Consecuencia directa: **no se creó una skill `oracle-design`**. Habría duplicado
`referencias/oraculos.md`. Se gasta presupuesto en lo que falta, no en reescribir lo que ya
está bien.

**`analyze.py` → `scripts/metrics.py`: conservar y extender, nunca sustituir.**

Verificación exigida y cumplida: comparación **clave a clave** contra el original sobre los
mismos datos reales. **Cero regresiones** en las ~44 claves existentes. Ocho claves nuevas:

| Clave nueva | Por qué |
|---|---|
| `rework_sessions` / `rework_sessions_pct` | El encargo hablaba de "% de sesiones" y el instrumento medía "% de turnos". Ahora existen las dos, con nombres que no se confunden |
| `sessions_with_oracle` / `..._pct` | El KPI que más importa, y que no se medía |
| `tool_calls_per_session_median` / `_p90` | Declarados en el encargo, ausentes del instrumento |
| `filter_applied` | El filtro de subagentes, explícito en la salida |
| `sessions_with_correction_pct` | Alias legible, calculado una sola vez |

Dos cambios estructurales, justificados:

1. **Rutas parametrizadas** (`CLAUDE_PROJECTS_DIR`, `METRICS_OUT_DIR`) con los mismos
   defaults. Sin esto el instrumento no es testeable, y un medidor que no se puede probar
   no merece confianza.
2. **Filtro de subagentes explícito.** El original los separaba por la *profundidad* de dos
   globs (`projects/*/*.jsonl` vs `projects/*/*/subagents/*.jsonl`), no por un filtro. Eso
   es frágil y no auditable: una sesión anidada un nivel más abajo desaparecería del
   denominador sin que nadie lo notara. Ahora se excluye `/subagents/` por nombre y se
   declara en la salida. **Verificado que el conjunto resultante es idéntico** (47 / 192)
   antes de aceptar el cambio.

## Alternativas descartadas

- **Reescribir `analyze.py` con dataclasses y tipos.** Descartada: coste alto, riesgo de
  perder alguna de las ~50 métricas, beneficio cero para el usuario.
- **Dejar el instrumento fuera del repo** y llamarlo por ruta. Descartada: rompe la
  transferibilidad, que es una de las cuatro propiedades del encargo.
- **Reescribir la skill `harness` en inglés** por coherencia con el resto del repo.
  Descartada: es documentación de proceso que su autor lee en español, y traducir prosa
  cuidada solo para uniformar es destruir valor.

## Consecuencias

El repo hereda dos estilos de código distintos. Aceptado y declarado: la alternativa era
perder comportamiento probado a cambio de uniformidad. `metrics.py` sigue sin dependencias
externas y corre con el `python3` de sistema (3.14.4) sin instalar nada.
