# Guía · Por qué todo gira alrededor del contexto

[`01-overview.md`](../01-overview.md) da la imagen: el modelo es la CPU y el contexto es la RAM. Aquí van las cifras que convierten esa imagen en hábitos. Todas se midieron en un setup real en 2026, sobre las transcripciones de las propias sesiones, y están anonimizadas.

## 1 · Pagas ~45k tokens antes de escribir nada

Cada turno reenvía al modelo todo lo que está cargado, lo uses o no. En un setup con muchos plugins, skills y servidores MCP, lo fijo era esto:

| Partida | Tokens por turno |
|---|---|
| Esquemas de herramientas (una sola herramienta pesaba 14,6k) | 25k |
| Listado de skills (67 skills, muchas con cero usos en 60 días) | 5,6k |
| Índice de memoria (`MEMORY.md`, 63 líneas largas) | 4,5k |
| Cadena de instrucciones (`CLAUDE.md` y lo que importa) | 3,2k |
| **Total fijo aproximado** | **~45k** |

De esos 45k, entre 17k y 19k dependían de decisiones de la persona: qué skills tener activas, cómo escribir el índice de memoria, qué servidores MCP dejar cargados. El resto es el propio harness. Consecuencia: **cada plugin o skill que instalas «por si acaso» lo pagas en cada turno de cada sesión.** Mídelo con `/context` antes y después de instalar algo.

## 2 · Cuando la RAM se llena, la compactación tira casi todo

Al acercarse al límite, Claude Code compacta: sustituye la conversación por un resumen. Medido sobre 142 compactaciones:

- **Destruye ~88 % del contexto** y **tarda ~150 s** cada una.
- **Todas fueron automáticas.** Ninguna la pidió la persona en un buen momento.
- **El 84 % de lo compactado era E/S de herramientas**: ficheros leídos enteros, listados, salidas de tests, volcados de búsquedas. La conversación en sí ocupaba poco.
- **El 63 % cayó dentro de un mismo turno autónomo**: el modelo encadenando herramientas sin que nadie mirase. Ahí no hay ningún aviso de fin de turno que valga, porque el turno no ha terminado.

Lo que se deduce:

1. Lo que llena la ventana es lo que traen las herramientas. Por eso se delega la exploración a subagentes (vuelve la conclusión, no el volcado) y se acotan las salidas (`| tail -n 40`, `grep -c`, `--stat`).
2. Esperar a la compactación automática es dejar que otro decida qué conservar, en el peor momento. Cerrar la fase con `/handoff` o `/clear` es decidirlo tú.

## 3 · Lo único que sobrevive es lo que está en disco

Tras una compactación o un `/clear`, el modelo solo sabe lo que se le vuelva a inyectar. De ahí `.claude/estado/nucleo.md`. Pero tener el fichero no basta:

- **El 75 % de las compactaciones (166 de 220) llegaron sin una sola escritura del fichero de estado en los 20 turnos previos.** Lo que se re-inyectaba era un estado viejo, con aspecto de estado vigente.
- **Un `nucleo.md` que degeneró en diario llegó a 78 KB** con cuatro cabeceras «TAREA ACTUAL». Las salidas de hook tienen un tope (10 000 caracteres según la documentación), así que el inyector lo recortaba: cabeza y cola sí, centro no. La tarea vigente vivía en el centro.

La respuesta es una **forma fija** (las secciones del [día 2](00-ruta-7-dias.md#día-2--nucleomd-el-estado-en-disco-con-forma-fija)), lo terminado fuera del fichero, y actualizarlo **al cerrar cada fase**, no cuando te acuerdes. En [`02-sesion-real.md`](02-sesion-real.md) está el recorte real sobre un fichero de 78 KB.

## 4 · Las sesiones reales son cortas y se corrigen mucho

Sobre 45 sesiones reales: **mediana de 4 mensajes de la persona por sesión**, y **el 58 % contiene alguna corrección** («no, eso no», «revierte»). Dos lecturas:

- Las sesiones largas son la excepción, no el caso de diseño. Una tarea, una sesión. La sesión que nunca se cierra es un antipatrón con nombre: una permaneció abierta **42 días** y acumuló **66 compactaciones** (ver [`03-antipatrones.md`](03-antipatrones.md)).
- Corregir es lo normal, y cada corrección cuesta un turno entero con sus 45k fijos. Lo barato es aclarar **antes**: una ronda de preguntas al empezar (IntentGate, en [`12-metodologia.md`](../12-metodologia.md)) y un criterio de «hecho» verificable.

## 5 · Lo que no funcionó, también medido

- **Comprimir con un proxy.** Un proxy de compresión delante de la API (Headroom) ahorró entre **0,2 % y 0,6 %** medido sobre miles de peticiones. Se retiró. La caché de prompts ya hace casi todo el trabajo; el ahorro real está en no cargar lo que no se usa (sección 1) y en no traer volcados (sección 2).
- **Subir la ventana.** Retrasa la compactación, pero cada turno reenvía la ventana entera: una ventana más grande es un turno más caro, no un problema resuelto.
- **Reglas en prosa que nadie comprueba.** «Actualiza el estado antes de compactar» estaba escrito en cuatro sitios y el 75 % de las veces no se hizo. Lo que tiene que cumplirse siempre va en un hook ([día 4](00-ruta-7-dias.md#día-4--los-hooks-qué-incidente-evita-cada-uno)).

## En una línea

Carga poco, delega la exploración, escribe el estado en disco con forma fija al cerrar cada fase, y cierra tú la sesión antes de que la compactación lo haga por ti.
