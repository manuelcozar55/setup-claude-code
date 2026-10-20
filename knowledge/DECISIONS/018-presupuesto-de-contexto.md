# ADR 018 — Presupuesto de contexto: medir antes de recortar, tope por canal

**Fecha:** 2026-10-20 · **Estado:** aceptada; la línea base se fija con la primera medida

## Contexto

El kit inyecta contexto por varios canales: instrucciones globales (unos 5,5 KB), SessionStart
(hasta 9500 caracteres), los avisos de PostToolUse y Stop, y las descripciones de los 8 agentes.
Cada canal tiene su tope, pero nadie sabía cuánto cuesta en tokens arrancar una sesión con el
kit, ni había un test que impidiera que un canal creciera sin que nadie se diera cuenta. Sin ese
número, «optimizar el contexto» se queda en opinión.

## Decisión

- **Línea base medida:** tokens del primer turno de una sesión vacía (`claude -p
  --output-format json`) en tres casos: sin kit, con kit y con `nucleo.md` lleno. Se apunta en
  `COST-LOG.md` y se repite en cada aceptación.
- **Tope por canal, comprobado sin red en `make test`:** instrucciones globales, el peor caso de
  cada hook, la suma de SessionStart, el bloque de agentes y las descripciones de los agentes.
  Superar un tope es un fallo, no un aviso.
- **Recortar solo lo que la medida señale.** Cada recorte va con su medida de antes y después.
- **Delegación:** al hilo principal vuelve la conclusión y la ruta de `RESULTADO.md`, no el volcado.

## Alternativas descartadas

- Recortar a ojo: se optimiza lo que se ve, no lo que pesa.
- Medir solo en bytes: no capta las instrucciones del harness ni el coste real; los bytes son el
  test barato y los tokens, la medida de verdad.

## Consecuencias

- La medida en tokens necesita red y cuesta poco. Va en las evals y en la aceptación, no en
  `make test`, que sigue sin red.
