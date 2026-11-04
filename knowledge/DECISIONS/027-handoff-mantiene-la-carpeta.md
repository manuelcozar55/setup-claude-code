# ADR 027 — Tras `/handoff` + `/clear` la sesión conserva su raíz de estado y su carpeta, y siempre recibe un mínimo

**Fecha:** 2026-11-04 · **Estado:** aceptada · **Complementa a:** ADR 014, 019 y 026

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
   el cwd; lo hace la sesión, con el `cd` de su shell. La ruta se valida otra vez al leerla (existe, sin controles ni bidi)
   y se trata como dato: no se ejecuta nada por estar en el fichero.
4. **Piso de emisión:** `nucleo_emitir` copia delante lo que falte entre Objetivo y Siguiente acción (≤ 600 B cada una, con
   su cabecera) y, si la emisión no lleva ninguna sección, las primeras líneas del fichero (≤ 1 500 B) con la ruta de donde
   está el resto. El piso se resta del tope y la emisión se rehace con lo que queda, así que el total no crece. Si el
   nucleo es ilegible, el hook lo dice en lugar de dejar el bloque vacío.

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
