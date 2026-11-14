# ADR 027 — Tras `/handoff` + `/clear` la sesión conserva su raíz de estado y su carpeta, y siempre recibe un mínimo

**Fecha:** 2026-11-04 · **Estado:** aceptada · **Complementa a:** ADR 014, 019 y 026 · enmendada por 029 (en `~`, la raíz es el proyecto vinculado si lo hay)

## Contexto

La persona pidió que «se mantenga la carpeta al hacer handoff y clear siempre, incluso un mínimo de contexto o un
cacho de nucleo.md». Antes de cambiar nada se comprobaron tres hipótesis:

1. **«El hook crea otra ranura tras `/clear`»: falsa.** La ranura se ata al proceso `claude` (`.proceso`, ticks de
   `/proc/<pid>/stat`, ADR 019), y `/clear` no cambia de proceso. Lo que sí cambia de proceso es `resume` en otra
   terminal: ahí la ranura se pierde y solo llega el índice (límite ya documentado en el ADR 019; no se toca).
2. **«El mod usa el cwd vivo y los hooks el de arranque»: cierta, y es la causa.** `resolveRoot` del cockpit usaba
   `$.session.cwd()` (el cwd vivo) y `$.process.run` corre el CLI en ese mismo cwd. Una sesión abierta en `~` que había
   hecho `cd` a un repo guardaba el handoff en `<repo>/.claude/estado/nucleo.md`; el `/clear` devuelve el cwd a `~` y
   `session-start-clear.sh` (que parte de `CLAUDE_PROJECT_DIR`) inyectaba la ranura antigua de `~`, o solo el índice.
   El relleno del prompt llevaba además `.claude/estado/nucleo.md` relativo, que en `~` apunta a otro fichero.
3. **«Si no cabe o falla la lectura, no llega nada»: cierta en dos formas.** Un nucleo de texto libre (sin las secciones
   de la plantilla) no emitía nada, y un reparto por tope agotado por Invariantes/Plan/Pendientes dejaba fuera
   «Objetivo» (`[recortado por tope: se omiten «Objetivo»]`).

## Decisión

1. **Una sola raíz para el mod y los hooks:** el cockpit la toma de `$.session.root()` (donde arrancó la sesión, o donde
   la llevó `/cd`; un `cd` de la shell no la mueve) y lanza el CLI con `CLAUDE_PROJECT_DIR` = esa raíz. El CLI sigue
   corriendo en el cwd vivo. Con `--raiz` en un proyecto, y sin `--raiz` en `~` (ranura), nada más cambia (D1/D2: `~` no es proyecto).
2. **La carpeta viaja en el nucleo:** `handoff --desde` anota bajo el título `> carpeta de trabajo: <ruta>` cuando su
   cwd difiere del punto de arranque (`CLAUDE_PROJECT_DIR`, o `~` en una ranura, o la raíz del proyecto). Ruta absoluta,
   directorio, sin controles, ≤ 400 chars; cada handoff la sustituye o la quita; cuenta dentro del tope de 6 500 B.
3. **La sesión nueva es llevada a esa carpeta:** tras `clear`/`resume`, `session-start-clear.sh` pasa la línea dentro de
   los datos y, fuera de ellos, añade la frase «la sesión anterior trabajaba en X: si sigue siendo ahí donde toca
   trabajar, haz `cd`» (paso 5 del protocolo en un proyecto; una frase tras los datos en `~`). El hook no puede mover
   el cwd; lo hace la sesión, con el `cd` de su shell. La ruta se valida otra vez al leerla: absoluta, solo `[A-Za-z0-9._/@+-]`, sin `..`, directorio
   existente y que sea la raíz de arranque (o cuelgue de ella) o `~` (o cuelgue de `~`). Va entre comillas simples, como dato, en la
   frase; si no pasa, la sesión recibe un aviso sin la ruta y ninguna instrucción de `cd` (el nucleo de un proyecto es dato ajeno:
   `x$(id)` o «ignora lo anterior…» no deben llegar como texto libre a una frase que manda hacer `cd`).
4. **Piso de emisión:** `nucleo_emitir` copia delante lo que falte entre Objetivo y Siguiente acción (≤ 600 B cada una, con
   su cabecera) y, si la emisión no lleva ninguna sección, las primeras líneas del fichero (≤ 1 500 B) con la ruta de donde
   está el resto. El piso se resta del tope y la emisión se rehace con lo que queda: las secciones no gastan más que antes. El tope
   no es la longitud de la salida: los avisos `[LEE …]` y `[fuera de forma]` van encima (medido con 120 nucleos aleatorios: máximo
   6 895 B con tope 6 500, 6 878 antes del piso; el test lo acota a ≤ 7 000). Si el
   nucleo es ilegible, el hook lo dice en lugar de dejar el bloque vacío.

5. **La ranura desde `$.process.run`, medida en vivo (4-nov-2026, claude 2.1.311):** un mod de sonda cargado con
   `claude -p --plugin-dir <sonda> --model haiku` lanzó por `$.process.run` un `sh -c`. Resultado: `PPID` = el pid del
   `claude` (comm `claude`; cadena sh → claude → shell que lo lanzó), así que el hijo cuelga directamente de él y el
   respaldo del CLI (`$PPID` con comm `claude`, `nucleo_sesion_pid`) vale. `CLAUDE_PID` no lo exporta claude: el hijo lo
   veía **definido solo porque el claude de la sonda estaba lanzado desde la shell de otro claude** (valía el pid del
   externo, `1471844`); lanzado con `env -u CLAUDE_PID` salía sin definir. Un valor heredado ganaría al `$PPID` y
   escribiría en la ranura del claude exterior, así que `viaStart` pasa `CLAUDE_PID=''` (comprobado en la misma sonda:
   `env: { CLAUDE_PID: '' }` llega vacío y el `PPID` sigue siendo claude). Los tests cubren el camino sin `CLAUDE_PID`
   (`test_sesiones_home.sh` 20, con un proceso de comm `claude`) y que el mod lo deja vacío (`handoff.test.tsx`, «raíz»).

## Alternativas descartadas

- **Un fichero puntero aparte** (`carpeta` junto al nucleo, o en la ranura): otro sitio donde puede quedar rancio, otra
  lectura en cada hook y otra cosa que `handoff` debe mantener atómica con el nucleo. La línea del encabezado viaja con el
  nucleo, se escribe en la misma operación y ya tiene precedente (`> sesión anterior:`).
- **Que el mod ejecute `/cd`:** es un comando `local-jsx`, no invocable de forma segura desde un plugin, y cambiaría la
  raíz de la sesión (nucleo, `CLAUDE.md` anidados) en vez de solo devolver a la persona a su carpeta.
- **Resolver la raíz por el cwd vivo también en los hooks:** el hook de `clear` recibe `cwd` = el de arranque, no el vivo
  (`/clear` lo restablece), así que ese dato no existe en SessionStart.
- **Ranura por `session_id`:** `/clear` cambia el `session_id`; la ranura tendría que migrarse en cada limpieza.

## Consecuencias

- Pendiente (no resuelto aquí): `resume` en un proceso nuevo sigue sin heredar la ranura de `~` (ADR 019); y si `/cd`
  mueve `$.session.root()` pero no `CLAUDE_PROJECT_DIR` de los hooks, la divergencia vuelve para ese caso.
- Con un CLI instalado anterior a este cambio, el mod nuevo funciona igual (solo añade una variable de entorno y no
  pasa nada nuevo por argv), pero no anota la carpeta: actualizar `~/.claude/bin/handoff` y los hooks va con `install.sh`.
- El relleno del prompt tras `/clear` sigue usando `.claude/estado/nucleo.md` relativo en un proyecto: es correcto mientras
  la sesión arranque en la raíz git; arrancando en un subdirectorio, la ruta absoluta que da el hook manda.
- Handoff automático en `~` (04-nov): el mod solo acepta como estado, sin raíz, `~/.claude/estado/sesiones/<x>/nucleo.md` (nunca el `estado/nucleo.md` compartido) y distingue «sin ranura» de «sin proyecto» en el texto y en el log; sonda en vivo: el hijo de `$.process.run` cuelga de claude (rama A), no hace falta pasar el pid.
