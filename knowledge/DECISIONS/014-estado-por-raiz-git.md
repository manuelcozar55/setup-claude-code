# ADR 014 — Estado v3: la unidad es la raíz git, con dueño y CLIs

**Fecha:** 2026-10-19 · **Estado:** aceptada

## Contexto

El 19-oct había 4 sesiones vivas sobre un mismo nucleo en `~`; una sesión ajena recibió el estado de otra
tarea recortado, y el aviso de contexto le pidió actualizar un nucleo que no era suyo. El nucleo de un proyecto
llegó a apilar dos tareas (3,6× el tope). Además el estado se reescribía entero con el modelo en cada cierre de
fase (pierde detalle) y los oráculos con `| tail` devolvían el rc de `tail`.

## Decisión

- **Unidad = raíz git** (repo o worktree): una tarea = un worktree = un nucleo = una sesión dueña. `$HOME`,
  `$HOME/.claude/**` y un directorio sin git no son proyecto (`nucleo_raiz` sale con rc 1).
- **Dueño** en `.claude/estado/.dueno` (`sesion=`, `desde=`), sin pid, con TTL de 4 h. Lo reclama SessionStart; la
  ajena recibe un aviso y su nudge calla. No bloquea: un dueño huérfano caduca solo.
- **CLIs `handoff` y `oraculo`** (bash + jq, válidos en Claude Code, Codex y opencode). El modelo redacta un
  borrador; `handoff --desde` decide: valida cabeceras, conserva Objetivo, une Invariantes por líneas, mueve los
  `[x]` a `diario.md`, pliega el último rc de `oraculo` (que solo escribe en `verificaciones.log`), rota copias y recorta al tope omitiendo secciones enteras.
- **Tope único** `NUCLEO_TOPE=6500` en la lib; la plantilla y la doc lo citan sin cifra. Un solo orden de secciones, el de la plantilla,
  para emitir y para recortar.
- **El índice de `~` es derivado**: se calcula al arrancar desde los nucleos de las raíces registradas. Un
  `indice.md` escrito por `handoff` necesitaría un escritor, y un escritor es una deriva esperando a ocurrir.
- **La autocompactación es el airbag, no el camino**: el normal es `handoff` entre turnos al 70 % y `/clear`.
  Para que el nucleo baste sin subir el tope lleva tres campos baratos: las correcciones literales de la
  persona con fecha (en Invariantes), los ficheros calientes con rango y el último rc junto a cada comando.

## Alternativas descartadas

Un nucleo global único (es lo que falla); un segundo handoff «de sesión» (dos resúmenes del mismo trabajo
divergen y duplican el coste); dueño por pid (el hook no conoce el de claude); pedir `pipefail` al modelo en vez
de `oraculo`.

## Consecuencias

Dueño solo se reclama si `.claude/estado/` ya existe (no ensucia repos ajenos): la primera sesión de un
proyecto virgen no queda como dueña hasta que haya estado. El emisor sigue cortando por sección con aviso;
`handoff` es quien garantiza no pasar del tope al escribir.
