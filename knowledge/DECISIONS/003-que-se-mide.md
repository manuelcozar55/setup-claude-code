# ADR 003 — Qué se mide, qué no, y por qué las cifras heredadas se archivan

**Fecha:** 2026-08-21 · **Estado:** aceptada

## Contexto

El encargo traía una tabla de KPIs con cifras concretas: 68 % de sesiones con correcciones,
14 % con interrupciones, mediana de 109 tool calls, p90 de 460, mediana de encargo de 520
caracteres.

Al reejecutar el instrumento que supuestamente las produjo (`analyze.py`) el 2026-08-21,
**ninguna salió**.

| KPI declarado | Medido hoy | Diagnóstico |
|---|---|---|
| Correcciones 68 % de **sesiones** | 9,0 % de **turnos** (12/134) | Denominador distinto: divide por `user_turns` |
| Interrupciones 14 % | 0 | No reproducible |
| Tool calls mediana 109 / p90 460 | — | **La métrica no existe en el instrumento** |
| Encargo mediana 520 ch / p90 19.363 | 142 / 798 | Un orden de magnitud |
| Contexto fijo ~2.200 tok / 2,09 B | ~2.240 / 2,25 B | ✅ el único que cuadra |

## Decisión

**1 · Las cifras heredadas se archivan como históricos sin procedencia verificable.**
No son criterios de aceptación. El contrato del propio encargo lo exige: *"un '778 passed'
de otra máquina y otra fecha es una predicción, no un oráculo"*. Se aplica esa regla a las
cifras del encargo mismo.

**2 · La línea base es la del 2026-08-21T15:45:30Z**, con su sello, su filtro declarado
(`-not -path "*/subagents/*"`: 236 transcripts → 47 sesiones) y su comando.

**3 · Se mide esto:**

| # | KPI | Base | Dirección |
|---|---|---|---|
| 1 | Retrabajo por turno **y por sesión** (ambos, con nombres distintos) | 9,0 % / por medir | ↓ |
| 2 | Interrupciones | 0 | ↓ |
| 3 | Coste equivalente-API, con % delegado | 1.934 $ · 31,8 % | ↓ a igual resultado |
| 4 | Tool calls: total, mediana y p90 **por sesión** | 3.424 · medianas por construir | contexto |
| 5 | **Sesiones con oráculo ejecutado** | 0 → medible desde hoy | ↑ **el que más importa** |
| 6 | Contexto fijo | ~2.240 tok | dato, medido una vez |

**4 · No se mide como objetivo:** el contexto fijo. Es el 0,0001 % de la entrada. Se midió
una vez para la auditoría y se deja de perseguir.

**5 · Regla de aceptación:** ninguna optimización del KPI 6 se acepta si empeora el 1, el 3
o el 5.

## Por qué se separa retrabajo-por-turno de retrabajo-por-sesión

Porque confundirlos es exactamente lo que produjo el "68 %". Son preguntas distintas:
*¿cuánto de lo que pido sale mal?* (turno) y *¿cuántas veces salgo de una sesión habiendo
tenido que corregir?* (sesión). El instrumento ahora emite las dos con nombres que no se
confunden.

## La métrica pedagógica

*"Elevarme a experto"* no es medible tal cual. Se operacionaliza como:

> **Número de veces que el usuario escribe un criterio de verificación en su encargo
> inicial, sin que el harness se lo pida.** Base 2026-08-21: cerca de cero.

Y su señal de fracaso: si el coach produce texto que no cambia ninguna decisión, es ruido.
Ver `.claude/skills/coach/SKILL.md`.

## Alternativas descartadas

- **Reconstruir las cifras heredadas** buscando la ventana temporal que las produjera.
  Descartada: coste alto, y aunque salieran, seguirían sin ser reproducibles a futuro.
- **Adoptarlas como objetivo igualmente.** Descartada: fijar un objetivo contra un número
  que no se puede volver a medir garantiza no saber nunca si se cumplió.
- **Medir cuota real de suscripción** en vez de equivalente-API. Descartada: no hay
  instrumento que la exponga. Se declara la limitación en vez de fingir precisión.

## Consecuencias

La primera comparación útil de tendencia no existe hasta el segundo snapshot. Un harness que
se juzga a sí mismo necesita dos puntos, y hoy solo hay uno. **Este ADR no demuestra
mejora: establece desde dónde se mide.**
