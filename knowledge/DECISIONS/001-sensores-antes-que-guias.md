# ADR 001 — Sensores antes que guías, y reparar el canal antes que ambos

**Fecha:** 2026-08-21 · **Estado:** aceptada

## Contexto

El marco es el de Birgitta Böckeler (*Harness engineering*, martinfowler.com, 02-abr-2026 —
**la autora es Böckeler, no Fowler**; el artículo está alojado en ese dominio). Distingue:

- **Guías** (feedforward): *"anticipate the agent's behaviour and aim to steer it before it
  acts"*.
- **Sensores** (feedback): *"observe after the agent acts and help it self-correct"*.

Y avisa de que ninguno basta solo: sin sensores el agente repite los mismos errores; sin
guías codifica reglas sin llegar a saber si funcionaron.

El diagnóstico de partida era que a este harness le sobraban guías y le faltaban sensores.
La medición del 2026-08-21 lo confirma: `CLAUDE.md` tenía 18 secciones de reglas, y el
número de sesiones con un oráculo ejecutado era **0** — porque nadie lo medía.

## El hallazgo que cambia el orden

Al caracterizar el entorno apareció algo peor que la ausencia de sensores:

> El hook `PreToolUse/Bash` **sustituye el ejecutable en posición de comando**. `rg` ejecuta
> `grep`; `python3 -m pytest` ejecuta `python3 -m rtk`. Los argumentos no se tocan.

Bash es **5.955 de las llamadas a herramienta** de la ventana medida (2.379 principales +
3.576 en subagentes). Es el canal por el que pasa casi todo sensor computacional.

Un sensor cuyo canal reescribe la pregunta no es un sensor débil: es uno que **miente sin
avisar**, que es estrictamente peor que no tenerlo, porque produce confianza injustificada.

## Decisión

El orden de trabajo es **canal → sensores → guías**:

1. **Reparar el canal.** Todo oráculo se invoca por ruta absoluta, con `rtk proxy …` o con
   `make …`. No es una recomendación: `test_harness_structure.sh` rechaza cualquier entrada
   de `ORACLES.md` que no lo cumpla.
2. **Construir sensores** (computacionales primero, que son *"deterministic and fast"*):
   `make test` como oráculo del repo, `oracle-log.sh` para medir el KPI que faltaba,
   `verify-gate.sh` para avisar de trabajo sin verificar.
3. **Recortar guías** y mover a skill lo que no necesita estar en contexto siempre.

## Alternativas descartadas

- **Escribir mejores reglas en `CLAUDE.md`.** Descartada: la sección más larga del fichero
  (`IntentGate`, 227 tok) regía un plan mode al **2,1 %**. Más texto no arregla adherencia.
- **Desactivar el hook `rtk`.** Descartada: está fuera del alcance (vive en el `~/.claude`
  privado del usuario), y el rodeo por ruta absoluta es verificable por test, que es mejor
  garantía que un cambio de config que nadie comprueba.
- **Empezar por los sensores inferenciales** (revisión por LLM). Descartada de momento:
  Böckeler los describe como más lentos, más caros y no deterministas. Primero lo barato y
  fiable.

## Consecuencias

- Todo comando de `ORACLES.md` es verificable mecánicamente. **Coste**: los comandos son más
  largos y menos cómodos de teclear.
- El KPI 5 pasa de inmedible a medible.
- Queda una deuda declarada: la heurística de `oracle-log.sh` detecta oráculos por nombre
  conocido (`make test`, `pytest`, `shellcheck`, `gitleaks`…). **Falso negativo conocido**:
  un oráculo con nombre propio no se cuenta. Se prefiere contar de menos.

## Fuentes

- Böckeler, *Harness engineering*, 02-abr-2026 — primaria, verificada 2026-08-21.
- Reproducción del fallo del canal: `knowledge/MISTAKES.md` · M-001.

---

**Actualización (2026-08-25).** El diagnóstico de partida sigue en pie, pero la cifra que lo
acompaña no: el número de sesiones con oráculo ejecutado **no era 0**, era **27,7 %** (13 de
47). El 0 era lo que se sabía antes de tener instrumento, y `scripts/metrics.py` lo corrigió
el mismo día — ver `knowledge/COST-LOG.md`, KPI 5. No se reescribe el texto de arriba porque
es el registro de la decisión; se anota aquí que la cifra de referencia es la del COST-LOG.
