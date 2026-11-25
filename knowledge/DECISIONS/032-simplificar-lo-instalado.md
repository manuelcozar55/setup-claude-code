# ADR 032 — Simplificar lo que se instala: núcleo por defecto, el resto con `--con`

**Fecha:** 2026-11-24 · **Estado:** aceptada (decisión de la persona: «ADELANTE» el 23-nov, «TODO SEGUN EL RECOMENDADO» el 24-nov) · **Revisa:** ADR 005 · **Anota:** ADR 024

## Contexto

Medido sobre el uso real de una máquina (04-nov a 23-nov, 255 sesiones):

- Skills: `deep-change` 28 usos; las seis de `esenciales`, `verification-before-completion` y `retro`, 0.
- Agentes: `deep-worker` 188, `code-reviewer` 65, `code-explorer` 32, `security-reviewer` 17, `quick-checker` 6,
  `silent-failure-hunter` 6, `pr-test-analyzer` 1.
- Guards: bloquearon en 85 de 255 sesiones, con un 64,9 % de falsos positivos (`efectividad.tsv`, 11-nov). Sentinel
  bloqueó en 54 de 200.
- Estado: `/clear` 93 veces, autocompactación 219, `/handoff` como orden 0; el bloque automático estaba en el 80 %
  de las compactaciones.
- Cockpit: `scc` 15 usos, sin eventos desde el 14-nov. Avisos de contexto: el 47 % se cumplió (ADR 020).
- El kit instalaba 21 hooks, 7 agentes y 9 skills, y el presupuesto del ADR 005 no cuenta `kit/`.

El ADR 005 fijó que el presupuesto de complejidad solo aplica a lo nuevo y dejó `kit/` fuera «para no destruir
cobertura publicada». Esa excepción dejó crecer lo instalado sin freno: lo que más pesa en el día 1 de quien lo usa.

## Decisión

1. **Una instalación sin flags deja solo el núcleo.** Lo demás sigue en el repo y se pide con
   `install.sh --con <pieza>[,<pieza>…]`: `sentinel`, `cockpit`, `esenciales`, `revisores` (`silent-failure-hunter`,
   `pr-test-analyzer`), `skills-extra` (`verification-before-completion`, `retro`) y `nudge` (avisos de contexto).
   Una actualización nunca retira una pieza ya instalada: la conserva y dice cómo quitarla.
2. **Un solo `session-start` para `/clear` y compactación.** Se funden `session-start-clear.sh` y
   `session-start-compact.sh` en `session-start-estado.sh`, que ramifica por `source`; `session-start.sh` se queda
   aparte (B-008 en el BACKLOG). Una actualización retira los dos viejos.
3. **`NUCLEO_GATE` apagada por defecto** (estaba en `observe`).
4. **El presupuesto ya cuenta `kit/`.** `kit/test/test_presupuesto_kit.sh` cuenta lo que instala el kit por defecto y
   falla al superar el tope: 17 hooks cableados, 2 de `SessionStart`, 5 agentes y 1 skill. Revisa la decisión 2 del
   ADR 005: la línea base de `kit/` deja de estar fuera del cómputo. Subir un tope exige decir qué se retira.
5. **`AGENTS.md` pierde lo que ya impone un guard o una regla `deny`**: queda una línea que lo dice. El tope de
   instrucciones globales baja de 6900 a 6741 caracteres.
6. **El instalador sale 1 si el doctor final da un FAIL**; un WARN no cambia el código de salida.
7. **Versión 3.0.0** (sin tag): cambia lo que instala `install.sh` sin flags.
8. **`agentes.sh` se queda cableado**; se revisa en la retro del 2026-12-09.

Mecanismo de la simplificación: **desactivar por defecto en esta versión y borrar el código en la siguiente**, no
borrar ya. Es reversible con una orden y da una versión para que alguien lo eche en falta.

## Criterios de salida

Se miden en la retro del 2026-12-09 (la de B-007), sobre las mismas fuentes (`efectividad`, transcripts de la
máquina), con la misma definición de falso positivo:

- **Falsos positivos de los guards por debajo del 20 %** (hoy 64,9 %).
- **Bloqueos por sesión**: menos que el 85 de 255 de partida. Si sube, esta decisión no ha servido.
- **Piezas opcionales pedidas**: una pieza que nadie ha instalado con `--con` ni usado en esa retro se borra del
  código en la versión siguiente. Una que sí se pidió se queda como opcional.
- **Condición para borrar el código opcional**: criterios de arriba cumplidos y ningún informe de que alguien
  echó en falta una pieza. Si algún criterio falla, no se borra nada y se reabre este ADR.

Límite de la evidencia: una máquina, 20 días; los transcripts anteriores ya no existen.

## Anotación sobre el ADR 024

El ADR 024 dice que el kit pasa a 6 agentes y que `strategist` recomienda `deep-worker`. El repo hoy tiene 7
agentes en `kit/claude/agents/` y ningún `strategist`: la cifra y el agente de aquel día se quedan como registro, no
como estado actual. El sensor de `test_doc_claims.sh` ya falla si un doc nombra un agente que no existe. Esta
versión retira además `session-start-clear.sh` y `session-start-compact.sh` (decisión 2).

## Alternativas descartadas

- **Borrar ya el código opcional.** Irreversible sin una versión de margen y con la evidencia de una sola máquina.
- **Subir el techo a lo existente.** Honesto, pero renuncia a la presión de poda que pedía el ADR 005.
- **Fundir también `session-start.sh`.** El arranque normal no comparte la rama de estado: el coste en suites
  superaba la ganancia visible.

## Consecuencias

Quien dependía de Sentinel, el cockpit o los avisos debe pedirlos con `--con`; el CHANGELOG lo dice. Tras el
2026-12-09 hay datos para decidir qué se borra.
