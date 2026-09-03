# Pre-mortem — 2026-11-21, tres meses después

*Ejercicio: es noviembre de 2026 y mcharness ha fracasado. Nadie lo usa, o se usa como
decoración. ¿Qué pasó?*

Cinco causas, ordenadas por probabilidad estimada. Para cada una: la señal temprana que la
delataría, y qué hace hoy el diseño al respecto — incluyendo dónde **no** hace nada.

---

## 1 · El harness exigía disciplina en vez de cablearla · **probabilidad alta**

**Cómo pasó.** Los seis comandos son excelentes y nadie los escribió. `/spec` requiere
teclear `/spec` antes de pedir algo, y en un martes con prisa se teclea la petición a secas.
A los dos meses el flujo es el de siempre y `.claude/commands/` es un museo.

Es exactamente el fallo que ya se midió en el estado anterior: `IntentGate` era la sección
más larga de `CLAUDE.md` y el plan mode valía **2,1 %**. Escribir la regla más alto no
funcionó entonces y no hay razón para que funcione ahora.

**Señal temprana.** `sessions_with_oracle_pct` estancado en ~28 % a los dos meses. Y
`slash_commands` en `metrics.py` sin ninguna entrada de `/spec` o `/verify`.

**Qué hace el diseño.** Parcialmente: `auto-spec.sh` (`UserPromptSubmit`) detecta un encargo
sin criterio de verificación e inyecta el oráculo del proyecto en ese mismo prompt, y
`verify-gate.sh` (Stop) avisa al terminar si se tocó código sin verificar —y en modo autónomo
**impide cerrar el turno** con el oráculo en rojo (ADR 010). Ninguno de los dos depende de
que alguien se acuerde de teclear un comando; ninguno **obliga** en sesión interactiva.

**Qué NO hace, y hay que decirlo.** Nada fuerza a usar `/spec`. Es la debilidad central de
esta versión y es deliberada (ADR 004): un gate bloqueante con falsos positivos se desactiva
entero, y entonces se pierde también lo que sí funcionaba. **La mitigación real es empírica**:
si a los dos meses el uso es cero, el diagnóstico no es "hay que insistir", es que el comando
pedía demasiado y hay que hacerlo automático o borrarlo.

## 2 · La medición nunca tuvo un segundo punto · **probabilidad alta**

**Cómo pasó.** La baseline del 21-ago es impecable y jamás se volvió a correr
`cost-report.sh`. Sin segundo snapshot no hay tendencia, sin tendencia no se sabe si el
harness sirve, y algo cuyo valor no se puede demostrar acaba abandonado sin discusión.

**Señal temprana.** Un solo fichero en `metrics-*.json`. Ya pasó una vez: `delta.md` del
instrumento original decía *"Primera vuelta: no hay snapshot anterior"*.

**Qué hace el diseño.** `cost-report.sh` calcula tendencias en cuanto haya dos snapshots, y
`/retro` incluye actualizar `COST-LOG.md`.

**Qué NO hace.** Nadie ejecuta `metrics.py` periódicamente. **Mitigación concreta y barata**:
un `/loop` semanal o una entrada de cron que corra `cost-report.sh`. No está hecho; es la
primera mejora de la lista.

## 3 · `knowledge/` se pudrió · **probabilidad media**

**Cómo pasó.** En noviembre, `MISTAKES.md` tiene 3 entradas de agosto, `PROCEDURES.md`
describe un entorno que cambió, y `SOURCES.md` está lleno de `[STALE]`. Consultarlo empieza
a dar información falsa, así que se deja de consultar, y entonces sí es peso muerto.

**Señal temprana.** Ningún commit que toque `knowledge/` en cuatro semanas. (Antes se
buscaba por el prefijo `knowledge:`; se retiró por insatisfiable junto a un commit por
tarea, así que la señal ahora es tocar la carpeta, no el prefijo.)

**Qué hace el diseño.** `test_sources_freshness` falla cuando una fuente vence sin marcar,
y está **demostrado que detecta una entrada vencida fabricada**. Cada procedimiento lleva
fecha de validación. La caducidad es visible, no silenciosa.

**Qué NO hace.** La frescura solo se comprueba en `SOURCES.md`. `PROCEDURES.md` y
`MISTAKES.md` llevan fecha pero **nada falla si envejecen**. Extenderlo es fácil y no está.

## 4 · Los sensores dieron falsos positivos y se apagaron · **probabilidad media-baja**

**Cómo pasó.** `verify-gate.sh` avisa en sesiones donde no hacía falta —un README editado,
un fichero de notas— y el aviso se vuelve ruido de fondo. Cuando por fin avisa de algo real,
ya nadie lo lee. O peor: se comentan los hooks del `settings.json` y se olvida.

**Señal temprana.** El aviso aparece en sesiones sin código real. O `settings.json` deja de
declarar los hooks.

**Qué hace el diseño.** El gate solo habla si hay ficheros modificados **en un repo git**, y
calla en sesiones de lectura. Los tres hooks tardan 15-23 ms, así que nunca molestan por
lentos — que es la otra razón habitual para desactivar un hook.

**Qué NO hace.** No distingue un cambio en `README.md` de uno en código. Refinar el filtro
por extensión es la mitigación obvia si la señal aparece.

## 5 · El repo creció hasta volverse otro problema · **probabilidad baja**

**Cómo pasó.** v0.2.0 añadió 6 agentes, 6 skills y adoptó media docena de skills externas.
El presupuesto se fue subiendo "solo esta vez". A los tres meses mcharness pesa más que lo
que ayuda a mantener, y hay que mantenerlo a él.

**Señal temprana.** Un commit que sube los números de `test_harness_structure.sh`.

**Qué hace el diseño.** Bien cubierto: el presupuesto está **verificado por test**, subirlo
exige un commit visible, y hoy se usan **0 de 6 agentes y 4 de 6 skills** — hay margen sin
tocar el techo. El precedente ya está sentado: se descartó crear `oracle-design` porque
duplicaba contenido existente.

**Riesgo residual bajo.** Es el único de los cinco donde el control es realmente duro.

---

## Lo que este pre-mortem no cubre

Que el harness **sí se use y aun así no mejore nada**. Es un desenlace posible y distinto
del fracaso por abandono: los 23 checks de `test_harness_structure.sh` verifican que el
harness está **bien formado**, no que mejore resultados. Eso solo lo dirán los KPIs con el
tiempo — y por eso la causa 2 es la más grave de la lista, aunque no lo parezca: sin segundo
punto de medida, este documento nunca se puede resolver.
