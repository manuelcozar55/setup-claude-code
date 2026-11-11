# BACKLOG

Propuestas para el kit que esperan turno. Una idea sin problema medido es un gusto; aquí se
apunta para que no entre por la puerta de atrás.

---

## Congelación

**Levantada el 2026-11-11** por decisión del dueño (iba hasta el 2026-12-09: solo arreglos,
documentación y retiradas). Lo que entró al levantarla está en B-007.

**Hasta v2.0**, ningún hook, agente, skill ni mecanismo nuevo entra en el kit sin
una entrada en este fichero con evidencia medida. Una entrada no es una aprobación: la
decisión se escribe en ella, con su fecha.

## Plantilla de entrada

```
## B-NNN · <propuesta en una línea>

**Fecha:** AAAA-MM-DD
**Propuesta:** qué se añade y dónde.
**Problema que resuelve:** el fallo observado, con la evidencia medida (comando, cifra, informe).
**Coste:** líneas nuevas, hooks nuevos, tokens por sesión.
**Decisión:** entra · no entra · pospuesto, y por qué (AAAA-MM-DD).
```

---

## B-001 · Port de handoff y nucleo.sh a Python stdlib

**Fecha:** 2026-11-11
**Propuesta:** reescribir `handoff` y `nucleo.sh` en Python con solo la biblioteca estándar.
**Problema que resuelve:** sin evidencia medida todavía.
**Coste:** sin medir.
**Decisión:** pospuesto hasta después del 2026-12-09 (2026-11-11).

## B-002 · ICM barato y comprobable

**Fecha:** 2026-11-11
**Propuesta:** un ICM barato y comprobable.
**Problema que resuelve:** sin evidencia medida todavía.
**Coste:** sin medir.
**Decisión:** pospuesto hasta después del 2026-12-09 (2026-11-11).

## B-003 · Prueba del paseo nocturna y opt-in

**Fecha:** 2026-11-11
**Propuesta:** ejecutar la prueba del paseo cada noche, solo para quien la active.
**Problema que resuelve:** sin evidencia medida todavía.
**Coste:** sin medir.
**Decisión:** pospuesto hasta después del 2026-12-09 (2026-11-11).

## B-004 · Sensor de contrato con Claude Code

**Fecha:** 2026-11-11
**Propuesta:** un sensor que detecte cuándo Claude Code cambia el contrato del que depende el kit.
**Problema que resuelve:** sin evidencia medida todavía.
**Coste:** sin medir.
**Decisión:** pospuesto hasta después del 2026-12-09 (2026-11-11).

## B-005 · Evals versionados

**Fecha:** 2026-11-11
**Propuesta:** versionar los evals.
**Problema que resuelve:** sin evidencia medida todavía.
**Coste:** sin medir.
**Decisión:** pospuesto hasta después del 2026-12-09 (2026-11-11).

## B-006 · «Leer solo» en la plantilla de nucleo.md

**Fecha:** 2026-11-11
**Propuesta:** añadir una sección «Leer solo» a la plantilla de `nucleo.md`.
**Problema que resuelve:** sin evidencia medida todavía.
**Coste:** sin medir.
**Decisión:** pospuesto hasta después del 2026-12-09 (2026-11-11).

## B-007 · Dos revisores y una skill de verificación, de terceros

**Fecha:** 2026-11-11
**Propuesta:** agentes `pr-test-analyzer` y `silent-failure-hunter` (de
`anthropics/claude-plugins-official`, Apache-2.0) y skill `verification-before-completion` (de
`obra/superpowers`, MIT), adaptados y con su procedencia en `THIRD-PARTY.md`.
**Problema que resuelve:** tres huecos que ningún agente del kit cubre: dar algo por hecho sin
correr el comando que lo prueba, revisar si los tests de un PR cubren el comportamiento nuevo
(`quick-checker` solo da pasa/falla) y encontrar errores tragados en scripts. Salieron de leer
9 repos fijados por SHA; el uso real todavía no está medido.
**Coste:** 3 ficheros, 237 líneas, 0 hooks; sus `description` suman 676 B (≈ 170 tokens) en
el listado de cada sesión.
**Decisión:** entra (2026-11-11), por decisión del dueño al levantar la congelación. Se mide su
uso en la retro del 2026-12-09; sin usos, se retira.
