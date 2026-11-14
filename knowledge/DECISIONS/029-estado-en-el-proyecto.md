# ADR 029 — Una sesión lanzada en `~` que trabaja sobre un proyecto se vincula a él: su estado vive en el repo y la ranura solo coordina

**Fecha:** 2026-11-14 · **Estado:** aceptada · implementada en 2.1.0 (2026-11-14) · **Enmienda a:** ADR 019 y 027

## Contexto

La persona pidió que un repo, aunque la sesión se lance en `~`, guarde su información en el propio repo y no en el
general, y que el general solo coordine. Medido antes de cambiar nada (14-nov-2026, Claude Code 2.1.311):

- **40 de 53 sesiones** de los últimos cinco días (10 a 14-nov) se lanzaron en `~`. Su estado iba a una ranura privada,
  `~/.claude/estado/sesiones/<fecha>-<pid>/nucleo.md` (ADR 019), que ninguna otra sesión del repo encuentra.
- La raíz es el punto de arranque (`CLAUDE_PROJECT_DIR`, ADR 027): los hooks y el cockpit escribían en la ranura aunque la
  sesión llevara horas trabajando en un repo.
- El Bash tool **no** exporta `CLAUDE_PROJECT_DIR` (llega vacío; sí exporta `CLAUDE_PID`). Un `handoff` manual tras un `cd` a
  un repo resolvía por el cwd y escribía en el repo. El estado de una misma sesión quedaba partido en dos ficheros según
  quién lo escribiera.
- El ADR 027 descartó resolver la raíz por el cwd vivo (en SessionStart ese dato no existe y el cwd se mueve). Sigue siendo
  cierto, así que el vínculo no puede deducirse del cwd.

## Decisión

1. **El vínculo es explícito y fijo.** `handoff --proyecto <ruta>` vincula la ranura de la sesión con el toplevel git de
   `<ruta>` (vale cualquier carpeta de dentro). Lo ejecuta el modelo o la persona; nada vincula solo.
2. **El vínculo es una línea en la cabecera del `nucleo.md` de la ranura:** `> proyecto: <raíz>`, con el mismo precedente que
   `> sesión anterior:` y `> carpeta de trabajo:` (ADR 027): viaja con el nucleo, se escribe en la misma operación y no hay
   un fichero puntero que pueda quedar rancio. Se valida al leerla (`nucleo_proyecto`): ruta absoluta, solo
   `[A-Za-z0-9._/@+-]`, sin `..`, directorio existente, su propio toplevel git, y ni `~`, ni `~/.claude`, ni nada que cuelgue
   de ellos. Si no pasa, no hay vínculo, la sesión sigue en la ranura y el aviso que se inyecta no reproduce la ruta (el
   nucleo es dato ajeno, igual que en el ADR 027).
3. **Un solo punto de resolución: `nucleo_raiz`.** Donde antes devolvía `~` con rc 1, y este proceso tiene ranura con vínculo
   válido, devuelve la raíz vinculada. Desde ahí nucleo, dueño, autosave, PreCompact, registro de agentes y reinyección se
   comportan como en una sesión lanzada en ese repo. Si `CLAUDE_PROJECT_DIR` apunta a un repo, el vínculo no se consulta; un
   `--raiz` explícito lo ignora siempre (`NUCLEO_VINCULO=0`). **El vínculo también es fijo frente al cwd:** una sesión de `~`
   vinculada a A que ejecuta el CLI con el cwd en otro repo B sigue escribiendo en A (7a66d12).
4. **`--proyecto` es transaccional, bajo los locks de la ranura y del proyecto.** Rechaza sin tocar nada si la sesión no es de
   `~` (rc 3), si la ruta no es un proyecto válido (rc 3) o si el proyecto tiene dueño ajeno vigente (rc 5, mismo texto que
   `--desde`); sin `--sesion` sale con 64. Después: un proyecto sin estado se siembra con el nucleo de la ranura (sin sus
   líneas de cabecera); uno con estado recibe el nucleo de la ranura entero en el `diario.md` de la ranura, con
   encabezado fechado (nada se pierde y nada se fusiona solo); el nucleo de la ranura queda como coordinación (título,
   `> sesión anterior:`, `> proyecto:` y `## Coordinación` con una línea por vínculo, máximo 10); se reclama el dueño del
   proyecto, se asegura `.claude/estado/` en `.git/info/exclude` y el registro de agentes pasa al proyecto. Es idempotente;
   revincular suelta el dueño del proyecto anterior.
5. **`handoff --estado` con ranura vinculada** devuelve `raiz`, `nucleo` y `dueno` del proyecto, `sesion` (la ranura) y
   `vinculado: true`. El cockpit no reimplementa nada: llama al CLI sin `--raiz` y se fía de `raiz`.
6. **Reinyección (clear, compact, resume):** con vínculo válido se inyecta el nucleo del proyecto por el camino normal y una
   línea que dice que la sesión se lanzó en `~`, está vinculada a '<raíz>' (entre comillas, como dato) y que, si toca
   trabajar allí, haga `cd`. `resume` en un proceso nuevo adopta la ranura por `session_id` antes de resolver la raíz y el
   vínculo viaja con ella. `nucleo_indice_ctx` nombra `handoff --proyecto <ruta>` como la forma de abrir una tarea de
   proyecto desde `~`.
7. **Propuesta de vínculo (nudge):** una sesión de `~` con ranura, sin vínculo y con el cwd vivo dentro de un proyecto válido
   recibe, una vez por sesión y raíz (marca `session-logs/nudge-vinculo-<SID>`), la orden exacta con la condición «si el
   encargo es de ese proyecto». Solo sale cuando el nudge ya habla (bandas 50, 70 y 85 %). Las órdenes que sugieren los
   hooks llevan `--ranura`, así que funcionan desde cualquier cwd.
8. **Cockpit 0.10.0:** con vínculo, `/handoff`, el handoff automático, el autosave por hitos y el panel usan el estado del
   proyecto; el panel dice que la sesión viene de `~`; `/nueva` conserva el vínculo (la línea vive en el nucleo de la ranura,
   así que `/nueva` no debe archivar la ranura). Sin vínculo, nada cambia.
9. **Tres arreglos del diagnóstico, en la misma versión:**
   - **F1, orden de descarte al reinyectar** (`_nucleo_emitir_awk`): cuando no cabe todo cae antes «Último turno (auto)», luego
     «Ficheros tocados» (regenerable desde git), «Plan» y al final «Pendientes». Antes caía Pendientes antes que Ficheros. El
     fallo existía en 2.0.0 (test rojo con 4 fallos sobre 626ff6f). **Solo cambia la reinyección:** `handoff --desde` sobre el
     tope sigue omitiendo antes Pendientes (decisión previa, fijada por `test_nucleo_hooks.sh`), deja copia en `diario.md` y
     avisa en el acto.
   - **F2, medidor de contexto** (`nucleo_ctx`): `fable-5-2` sin sufijo `[1m]` cuenta como ventana de 200 000. Medido: 24 de 24
     autocompactaciones con ese modelo a 167-172k (200k menos 33k) en Claude Code 2.1.311, mientras que `opus-5-5` y
     `fable-5-1` pasan de 200k. Con el medidor contra 1M, el aviso del 70 % llegaba con ~91 % real. Es un atajo declarado
     (`shortcut:` en el código): el límite real del motor no se lee desde shell, y si un binario nuevo le da 1M el medidor
     avisará antes de tiempo, que es la dirección inocua.
   - **F3, regla de esperas** (`kit/claude/CLAUDE.md`): toda espera de fondo lleva `timeout`; un shell de fondo vivo bloquea el
     handoff automático.

## Alternativas descartadas

- **Vínculo automático por el cwd** (la sesión se vincula sola al entrar en un repo): la persona eligió «explícito y fijo».
  Además el cwd se mueve, un `cd` de paso a otro repo habría desplazado el estado, y SessionStart no lo ve (ADR 027).
- **Un fichero puntero aparte** en la ranura: otro sitio que se queda rancio y otra lectura en cada hook; la línea de cabecera
  viaja con el nucleo (mismo argumento que en el ADR 027).
- **Fusionar el nucleo de la ranura con el del proyecto al vincular:** mezcla estados de dos tareas sin que nadie lo revise; se
  prefirió sembrar si no hay estado y archivar en el diario de la ranura si lo hay.
- **Que el cockpit decidiera por su cuenta qué es proyecto** (su `resolveRoot` por git desde el arranque da null en `~`): dos
  validaciones que divergen. Toma `raiz` y `vinculado` del CLI.
- **Que `--raiz` respete el vínculo:** `--raiz` es la orden explícita de dónde escribir; gana siempre.
- **Cambiar también el orden de omisión al escribir (`--desde`)** en F1: lo fija un test existente (W2) y la copia en
  `diario.md` ya protege lo omitido; fuera de alcance.

## Consecuencias

- Una ranura sin vínculo se comporta exactamente como en 2.0.0 (las suites existentes pasan sin editar sus aserciones, salvo lo que sigue). Dos
  aserciones de «pasa poco» de `test_nucleo_lib.sh` fijaban el orden antiguo de descarte y se cambiaron a la par que F1.
- Dos sesiones de `~` vinculadas al mismo repo: la segunda recibe el trato de dueño ajeno de siempre (rc 5); nadie pisa a nadie.
- Coste medido: `handoff --estado` pasa de ≈ 95 a ≈ 106 ms por llamada (20 llamadas, sin `CLAUDE_PROJECT_DIR`); con
  `CLAUDE_PROJECT_DIR` en un repo no hay consulta extra. En los hooks, como mucho una lectura de fichero y una llamada a git
  (timeout de 5 s intacto).
- Una ranura tiene un solo proyecto activo. Revincular sustituye y deja rastro en `## Coordinación`. No hay flag para
  desvincular: se borra la línea `> proyecto:` de la ranura; `handoff --liberar` suelta el
  dueño.
- Sin `CLAUDE_PID` (el Bash tool lo exporta; otros entornos no), `--proyecto` necesita `--ranura <slot>`; si no, sale con 3.
- No se arregla aquí que un shell de fondo vivo bloquee el handoff automático (solo la regla F3), ni los nucleos antiguos que ya
  superan el tope, ni la separación de bytes de entrada y salida en `recortes.log`.
- Pendiente: el test «carrera: si nucleo.md cambia durante la fusión» de `test_nucleo_hooks.sh` falló 1 de 4 corridas (depende
  de un `sleep 0.3`); preexistente.
- Enmienda al ADR 019 («solo donde no hay proyecto»): una sesión de `~` puede tener proyecto por vínculo, y entonces su ranura
  solo coordina. Enmienda al ADR 027 («`~` no es proyecto», raíz = punto de arranque): la raíz es el punto de arranque, salvo que
  en `~` haya un vínculo válido.
