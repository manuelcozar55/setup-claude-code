# ADR 005 — `kit/` intacto, y el presupuesto de complejidad aplica solo a lo nuevo

**Fecha:** 2026-08-21 · **Estado:** aceptada

## Contexto

El encargo describía el repo como si hubiera que construir `install.sh`, tests, CI y backup.
**La medición dice otra cosa**: `setup-claude-code` es un producto v1.0.0 maduro —
`kit/install.sh` de 372 líneas idempotente, **16 suites de test en verde**, CI de 3 jobs con
smoke-install en Debian y prueba de idempotencia por checksum, 9 documentos de usuario,
licencias resueltas (MIT para código, CC BY 4.0 para las charlas) y dos charlas HTML que
citan rutas del repo.

El encargo también fijaba un presupuesto de **≤6 agentes, ≤6 skills, ≤3 hooks**.
`kit/` ya publica **8 agentes y 11 hooks**, todos testeados y documentados.

## Decisión 1 — Dos capas, sin renombrar nada

- **`kit/`** = capa de **instalación**: guards, hooks, Sentinel, `install.sh`, sus 16 suites.
  Estable. No se toca sin ejecutar `make test`.
- **raíz** = capa de **harness**: `.claude/`, `knowledge/`, `config/`, `scripts/`.
  Aquí va todo lo nuevo.

Renombrar `kit/` → `mcharness/` obligaría a tocar README, 9 docs, `Makefile`, `ci.yml`,
`assert-install.sh`, las 16 suites y las 2 charlas HTML. El beneficio sería un vocabulario
más limpio; el coste, un riesgo alto de romper CI por una ruta olvidada, a cambio de nada
funcional. **No se hace.**

## Decisión 2 — El presupuesto aplica solo a lo nuevo

| | Línea base heredada (`kit/`) | Presupuesto mcharness | Uso actual |
|---|---|---|---|
| Agentes | 8 | ≤ 6 | **0** |
| Skills | 0 | ≤ 6 | **4** |
| Hooks | 11 (timeout 10 s) | ≤ 3 (timeout ≤ 5 s) | **3** |

La línea base queda **explícitamente fuera del cómputo** y `test_harness_structure.sh` lo
documenta en su salida.

**Por qué:** cumplir el presupuesto de forma global obligaría a eliminar 2 agentes y 8 hooks
ya publicados en v1.0.0, con sus tests y su documentación. Eso es un breaking change que
consume el esfuerzo en borrar cobertura existente en vez de en construir sensores, que es
lo que falta. El presupuesto existe para **frenar el crecimiento**, y así cumple esa función
sin destruir nada.

## Decisión 3 — Cero agentes nuevos

El presupuesto permite 6. Se usan **0**. La medición explica por qué: de 150 delegaciones,
**105 (70 %) fueron al agente genérico** y **6 de los 8 especialistas existentes nunca se
invocaron**. El problema no es falta de agentes; es asignación. Añadir un séptimo
especialista sin estrenar sería empeorar el diagnóstico, no tratarlo.

Los comandos (`/review`) nombran especialistas concretos en vez de dejar la elección al azar.
Eso ataca la causa medida.

## Decisión 4 — Cuatro skills, no seis

`harness` (absorbida), `house-rules`, `coach`, `dev-env`.

Se descartó crear una skill `oracle-design`: la doctrina de oráculos **ya existe completa**
en `.claude/skills/harness/referencias/oraculos.md`. Duplicarla habría sido gastar
presupuesto en repetir algo que ya estaba bien escrito. Sesgo por defecto del curador:
eliminar y redirigir, no añadir.

## Alternativas descartadas

- **Renombrar `kit/`** — coste alto, beneficio cosmético (arriba).
- **Presupuesto global recortando a 6/3** — destruye cobertura publicada.
- **Subir el techo a lo existente** (8/11) — honesto, pero renuncia a la presión de poda.

## Consecuencias

Conviven dos vocabularios (`kit` y `mcharness`). Se mitiga documentando la frontera en el
primer bloque de `CLAUDE.md` y en el README. **Es deuda declarada**, no accidental: si
alguna vez se corta una v2.0.0 con breaking changes, ese es el momento de unificar.
