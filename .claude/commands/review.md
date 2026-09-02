---
description: Revisión adversaria del diff en contexto limpio, verificando cada hallazgo antes de reportarlo
disable-model-invocation: true
---

Revisa el trabajo con un subagente en **contexto limpio**. Quien escribió el código no es
quien lo corrige.

Qué revisar: $ARGUMENTS

## Por qué un subagente y no tú

Tú acabas de escribir esto. Ves el código que *pretendías* escribir. Un revisor en contexto
fresco ve solo el diff y los criterios, sin el razonamiento que lo produjo, así que lo
juzga por lo que es.

## El aviso que hay que respetar

> Un revisor al que le pides encontrar huecos **los encontrará aunque el trabajo esté bien**,
> porque es lo que le pediste. Perseguirlos todos lleva a sobreingeniería: capas de
> abstracción de más, código defensivo y tests para casos que no pueden ocurrir.

Por eso este comando hace dos cosas que una revisión ingenua no hace: **acota el mandato** y
**verifica los hallazgos antes de aceptarlos**.

## Procedimiento

### 1. Lanza el revisor con mandato estrecho

Delega a `code-reviewer` (o a `security-reviewer` si el diff toca autenticación, entrada de
usuario, secretos o permisos). No uses el agente genérico: para esto hay especialistas.

En el prompt del revisor, obligatoriamente:
- El diff a revisar y **contra qué** se juzga (la spec, los criterios de aceptación).
- *"Reporta solo huecos que afecten a la **corrección** o a los **requisitos declarados**.
  Las preferencias de estilo son opcionales y van marcadas como tales."*
- *"Para cada hallazgo, da el escenario concreto de fallo: qué entrada o estado produce qué
  resultado incorrecto. Un hallazgo sin escenario de fallo no es un hallazgo."*

### 2. Verifica cada hallazgo antes de aceptarlo

**Este paso no es opcional.** Un revisor puede equivocarse con seguridad y buena redacción.

Para cada hallazgo:
- ¿El escenario de fallo es real? Compruébalo contra el código, o reprodúcelo.
- ¿Está dentro del alcance declarado, o es una mejora que nadie pidió?
- ¿La solución propuesta es más simple que el problema, o añade más complejidad de la que
  quita?

Clasifica: **CONFIRMADO** (reproducido) · **PLAUSIBLE** (razonable, sin reproducir) ·
**DESCARTADO** (con la razón).

No implementes sugerencias por deferencia. Estar de acuerdo sin comprobar es tan malo como
ignorar. Si el revisor se equivoca, dilo y sigue.

### 3. Arregla lo confirmado, y vuelve a verificar

Aplica los CONFIRMADOS. Los PLAUSIBLES son decisión del usuario. Los DESCARTADOS se
documentan, no se discuten dos veces.

Después de arreglar, **ejecuta el oráculo otra vez** (`/verify`). Un arreglo sin
reverificar es un cambio sin verificar.

### 4. Reporta

```
VEREDICTO   : APROBADO | CON RESERVAS | BLOQUEADO
CONFIRMADOS : n  (arreglados: n)
PLAUSIBLES  : n  (tuya la decisión)
DESCARTADOS : n  (con motivo)
ORÁCULO TRAS ARREGLOS : <salida> → exit <n>
```

Si el veredicto es APROBADO y no hubo ningún hallazgo, dilo tal cual. Inventar reservas
para parecer riguroso es la otra cara del mismo error.
