---
description: Implementa una spec aprobada de principio a fin, sin parar a preguntar, cerrando con el oráculo
disable-model-invocation: true
---

Implementa el trabajo especificado. Ejecuta hasta el final: **no preguntes a mitad**.

Qué implementar: $ARGUMENTS

## Contrato de este comando

Las preguntas van **antes** (`/spec`). Una vez empezado, manda terminar. Si aparece una
ambigüedad a mitad, toma la opción **conservadora y reversible**, anótala como supuesto, y
sigue. La única parada válida es un bloqueo que hace imposible continuar.

Esto no es prisa: es que preguntar a mitad devuelve al humano a la silla de piloto, que es
justo lo que el harness existe para evitar.

## Procedimiento

### 1. Carga el contrato

Lee `SPEC.md` si existe. Si no hay spec y el trabajo no es trivial, **para y ejecuta
`/spec` primero**. Implementar sin criterios de aceptación es cómo se produce trabajo que
parece hecho.

Ejecuta el oráculo **en frío** antes de tocar nada:
- Si ya pasa → o el trabajo está hecho, o el oráculo no mide lo que vas a cambiar. Averigua
  cuál de las dos antes de seguir.
- Si falla → bien, ese es tu punto de partida y tienes señal.

### 2. Aísla

Rama dedicada, nunca la rama por defecto. Si el proyecto no tiene control de versiones,
dilo antes de modificar nada y haz copia de cada fichero que toques.

### 3. Explora con precisión, no leyendo de todo

Antes de cambiar un símbolo compartido, mira quién lo usa. El análisis de impacto va
**antes** del cambio, no después de romper algo:

- `mcp__serena__get_symbols_overview` para la forma de un fichero
- `mcp__serena__find_symbol` para un cuerpo concreto
- `mcp__serena__find_referencing_symbols` para saber qué se rompe

Cuesta una fracción de un `Read` completo y responde una pregunta que `Read` no responde.

### 4. Escribe el código

- El mínimo que resuelve el problema. Nada especulativo.
- Toca solo lo que debas. Sin refactors de paso, sin "mejorar" lo adyacente.
- Sin comentarios salvo que el *porqué* no sea obvio.
- Sin abstracciones de un solo uso, sin flexibilidad que nadie pidió, sin manejo de errores
  para escenarios imposibles.
- **Regla del huérfano**: elimina lo que *tus* cambios dejaron sin usar. No toques código
  muerto preexistente — menciónalo, no lo borres.
- Escribe como escribe el código de alrededor: su densidad de comentarios, sus nombres,
  sus modismos. Aunque tú lo harías distinto.

### 5. Cierra con el oráculo

Ejecuta `/verify`. No des nada por terminado sin su salida delante, y comprueba que el
diff no toca el sensor.

### 6. Informe final, no narración durante

Al terminar, y solo al terminar:

```
QUÉ SE HIZO   : …
ORÁCULO       : <comando> → <salida> → exit <n>
SUPUESTOS     : los que tomaste sin preguntar
FUERA DE SPEC : lo que NO hiciste y por qué
QUEDA ABIERTO : …
```

Si tuviste que dejar algo sin hacer, dilo explícitamente. Recortar el alcance es decisión
del usuario, no tuya.
