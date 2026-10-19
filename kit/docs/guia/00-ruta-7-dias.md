# Guía · Ruta de 7 días

Esto no es otra lista de instalación: esa está en [`10-onboarding.md`](../10-onboarding.md) y tarda diez minutos. Esta guía es para lo que viene después: **trabajar bien** con Claude Code una vez instalado. Un hábito por día, unos 30 minutos cada uno, y al final de cada día una comprobación que no depende de tu impresión.

Las cifras citadas se midieron en un setup real en 2026 y están anonimizadas. El porqué completo, en [`01-por-que-contexto.md`](01-por-que-contexto.md); lo que sale mal cuando no se hace, en [`03-antipatrones.md`](03-antipatrones.md).

| Día | Hábito | La cifra que lo justifica |
|---|---|---|
| 1 | Instalar y **medir** con `/context` | ~45k tokens fijos por turno antes de escribir nada |
| 2 | `nucleo.md` con forma fija | el 75 % de las compactaciones llegan con el estado sin actualizar |
| 3 | `/handoff` y `/clear` en vez de compactar | una compactación destruye ~88 % del contexto y tarda ~150 s |
| 4 | Saber qué incidente evita cada hook | la prosa no se cumple sola; un hook sí |
| 5 | Subagentes y Explore | el 84 % de lo compactado es E/S de herramientas |
| 6 | Memoria corta y `recuerda` | un índice de memoria largo cuesta 4,5k tokens en cada turno |
| 7 | Mídete | sin medir, todo lo anterior es opinión |

## Día 1 · Instala y mide

1. `make bootstrap` desde la raíz del repo ([`10-onboarding.md`](../10-onboarding.md) explica cada `FAIL` y `WARN`).
2. Abre `claude` dentro de un repo tuyo y, **antes de escribir nada**, teclea `/context`.
3. Apunta el total y las cuatro partidas grandes: esquemas de herramientas, skills, memoria e instrucciones.

**Por qué.** En un setup cargado se midieron ~45k tokens fijos por turno: esquemas de herramientas 25k, listado de skills 5,6k, índice de memoria 4,5k y cadena de instrucciones 3,2k. Se pagan en cada turno y compiten con tu trabajo por la misma ventana. No puedes recortar lo que no has medido.

**Hecho cuando** tienes la cifra escrita. Es tu línea base para el día 7.

## Día 2 · `nucleo.md`: el estado en disco, con forma fija

En la raíz git de tu proyecto crea `.claude/estado/nucleo.md` con estas secciones y ninguna más:

```markdown
# Estado
## Encargo original (literal)
## Invariantes
## Plan
## Paso actual
## Siguiente acción
## Pendientes y riesgos
## Ficheros tocados
## Comandos de verificación
```

- «Encargo original» son las palabras de quien pidió la tarea, tal cual. «Invariantes», lo que no se toca y por qué. Esas dos no se reescriben nunca.
- «Siguiente acción» es **una**, concreta y ejecutable.
- Lo terminado sale del fichero (a un `diario.md` aparte, que nada inyecta). El hook [`session-start-clear.sh`](../../claude/hooks/session-start-clear.sh) lo entrega a cada sesión nueva (y [`session-start-compact.sh`](../../claude/hooks/session-start-compact.sh) tras cada compactación), pero **solo las secciones de la forma fija**: la primera vez que aparece cada una, con un tope por sección y otro total (3 000 por sección y un tope único de 6 500 bytes en el que «Paso actual», «Siguiente acción» y «Comandos de verificación» entran siempre, cada una con hasta 700, en [`lib/nucleo.sh`](../../claude/hooks/lib/nucleo.sh)). Lo que no tiene esa forma no llega, y una línea lo dice: si el fichero degenera en diario, el modelo recibe el título y el aviso, nada más.

**Por qué.** El 75 % de las compactaciones medidas llegaron con el estado sin tocar en los 20 turnos previos: lo que sobrevivió fue un estado viejo. Y un `nucleo.md` que degeneró en diario llegó a 78 KB con cuatro «TAREA ACTUAL»: se inyectaba troceado y la siguiente acción vigente quedaba en el centro cortado. Lo ves con salidas reales en [`02-sesion-real.md`](02-sesion-real.md).

**Hecho cuando** abres una sesión nueva en el repo, preguntas «¿cuál es la siguiente acción?» y la respuesta sale del fichero sin que lo pegues tú.

## Día 3 · `/handoff` y `/clear` en vez de esperar a la compactación

Instala el mod `cockpit` ([`11-cockpit.md`](../11-cockpit.md)). Al cerrar una fase, `/handoff`: el modelo devuelve las secciones que cambian, el código las fusiona en `nucleo.md` y hace `/clear`. La sesión nueva recibe el estado del hook de arranque; pulsas Enter sobre el prompt que el mod deja relleno con la siguiente acción. Sin el mod, lo mismo a mano: actualiza `nucleo.md` y teclea `/clear`.

Cambias de tarea: `/clear` a secas. Una sesión por tarea.

**Por qué.** Una compactación automática destruye ~88 % del contexto, tarda ~150 s y decide ella qué conservar. Un handoff conserva lo que tú escribiste. La sesión que nunca se cierra es el caso extremo: una permaneció abierta 42 días y acumuló 66 compactaciones.

**Hecho cuando** has hecho el ciclo completo una vez y la sesión nueva empezó con el `git log` y el `git status` que el hook ya calculó (el bloque `<git-hechos>`), sin gastar el primer turno en pedirlos. Si abres `claude` en `~` no hay protocolo: el hook inyecta un `<indice-tareas>` con las tareas que conoce.

## Día 4 · Los hooks: qué incidente evita cada uno

Lee la tabla «hook → incidente que evita» de [`05-security.md`](../05-security.md#hook--incidente-que-evita) y abre [`settings.json`](../../claude/settings.json) al lado. Luego provoca uno a propósito en un repo de prueba: pide «haz `git push` a main» y mira el bloqueo.

**Por qué.** Una regla en `CLAUDE.md` es una petición; un hook es una barrera que se ejecuta siempre. Cada hook del kit existe porque algo pasó. Si no sabes qué evita un hook, no sabrás cuándo apagarlo ni cuándo te falta otro.

**Hecho cuando** puedes decir, para cada hook de tu `settings.json`, qué incidente evita. El que no tenga respuesta sobra.

## Día 5 · Subagentes y Explore

Cualquier exploración de más de tres búsquedas se delega: `Agent(subagent_type="Explore")` o uno de los agentes de [`kit/claude/agents/`](../../claude/agents/). Al hilo principal vuelve la conclusión, no el volcado. El prompt al subagente apunta a un fichero (la spec, `nucleo.md`); no lo pega. Las salidas de `Bash` en el hilo principal, acotadas: `| tail -n 40`, `grep -c`, `--stat`.

**Por qué.** El 84 % de lo que se tira en una compactación es E/S de herramientas: listados, ficheros leídos enteros, salidas de tests. Eso es lo que llena la ventana, no la conversación. Y el 63 % de las compactaciones caen dentro de un mismo turno autónomo, cuando nadie está mirando.

**Hecho cuando** has hecho una tarea con la exploración delegada y `/context` antes y después muestra que el hilo principal casi no creció.

## Día 6 · Memoria corta y `recuerda`

La auto-memoria de Claude Code inyecta el índice `MEMORY.md` en cada turno. Una línea corta por entrada (título y gancho), el contenido en su propio fichero. El hook `session-start.sh` imprime cuántas entradas tienes y avisa cuando el índice pasa de 60 líneas. Para consultar, [`recuerda <términos>`](../../../scripts/recuerda) devuelve solo los párrafos que coinciden, en vez de leer memorias enteras. El formato de una memoria y del índice está en [`13-memoria.md`](../13-memoria.md).

**Por qué.** Un índice de 63 líneas largas costaba 4,5k tokens por turno; con una línea corta por entrada se estima en ~1,5k. Leer memorias enteras para encontrar un dato es pagar el fichero entero por una frase.

**Hecho cuando** tu índice cabe en 60 líneas cortas y has encontrado un hecho con `recuerda` sin abrir ningún fichero.

## Día 7 · Mídete

Repite `/context` y compáralo con el día 1. Luego mide tus sesiones reales con las herramientas de [`04-mide-tu-setup.md`](04-mide-tu-setup.md): compactaciones (cuántas, manuales o automáticas, con el estado fresco o no: [`compact-audit.py`](../../../scripts/compact-audit.py) y [`nucleo_audit.py`](../../../scripts/nucleo_audit.py)) y correcciones por sesión.

**Por qué.** Las sesiones reales medidas tienen una mediana de 4 mensajes y el 58 % contiene alguna corrección. Tu intuición sobre cómo trabajas casi seguro no coincide con tus datos.

**Hecho cuando** tienes tres cifras con fecha (fijo por turno, % de compactaciones manuales, % de sesiones con corrección) y has decidido qué cambiar con ellas. Para adaptar la plantilla a tu caso, [`06-adaptar.md`](06-adaptar.md).
