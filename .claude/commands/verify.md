---
description: Ejecuta el oráculo y reporta evidencia real; prohíbe afirmar éxito sin salida de comando delante
disable-model-invocation: true
---

Verifica el trabajo hecho. **Evidencia antes que afirmaciones, siempre.**

Objetivo a verificar: $ARGUMENTS

## La regla que gobierna este comando

> No declares nada terminado sin la salida del comando delante.

"He comprobado que funciona", "los tests deberían pasar" y "el cambio es correcto" no son
verificación. Son predicciones. La verificación es un comando, su salida literal, y su
código de salida.

## Procedimiento

### 1. Identifica el oráculo

Busca en este orden:
1. El campo `Oráculo` de `SPEC.md`, si existe.
2. La tabla de `knowledge/ORACLES.md` para este proyecto.
3. Deriva uno si es evidente: hay tests, hay linter, hay build, hay un script de arranque.

**Invócalo por ruta absoluta, con `rtk proxy …` o con `make …`.** Nunca por nombre suelto:
el hook `PreToolUse/Bash` sustituye el ejecutable en posición de comando, así que
`pytest` puede no ejecutar pytest. Está documentado en `knowledge/MISTAKES.md` · M-001.

Si no encuentras oráculo y no es derivable: **para y dilo**. No inventes uno que no puedes
ejecutar, y no sustituyas el oráculo por tu propia lectura del código. Sin sensor no hay
verificación; hay una opinión bien redactada.

### 2. Ejecútalo y guarda la salida literal

Nada de resúmenes. La salida cruda, o las últimas 30 líneas si es enorme.

### 3. Si falla: repara, máximo 3 veces

Cada reparación va seguida de una nueva ejecución del oráculo. Agotadas las 3, **para** y
reporta el fallo con tu hipótesis. Un cuarto intento no es perseverancia: es un lazo sin
condición de salida, y es exactamente donde aparece la tentación de aflojar el sensor.

### 4. Comprueba que no has tocado el sensor

Esto es lo que separa una verificación honesta de un teatro:

```
git diff --name-only
```

Si en esa lista aparece un fichero de test, un `conftest.py`, un `pytest.ini`, un umbral o
el propio comando del oráculo → **has aflojado el sensor**. No cierres la tarea. Revierte
ese cambio concreto y, si de verdad el test estaba mal, dilo como hallazgo aparte para que
se decida fuera de este lazo.

### 5. Reporta

```
ORÁCULO   : <comando exacto>
SALIDA    : <literal>
EXIT CODE : <n>
SENSOR    : intacto | ALTERADO (lista de ficheros)
VEREDICTO : verde | rojo | sin sensor
```

Y añade, en una frase, **qué NO queda cubierto por este oráculo**. Todo oráculo tiene
puntos ciegos; el que dice no tenerlos es el más peligroso.
