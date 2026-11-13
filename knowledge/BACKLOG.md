# BACKLOG

Propuestas para el kit que esperan turno. Una idea sin problema medido es un gusto; aquí se
apunta para que no entre por la puerta de atrás.

---

## Congelación

**Levantada el 2026-11-11** por decisión del dueño (iba hasta el 2026-12-09: solo arreglos,
documentación y retiradas). Lo que entró al levantarla está en B-007.

**Hasta v2.0**, ningún hook, agente, skill ni mecanismo nuevo entra en el kit sin
una entrada en este fichero con evidencia medida. Una entrada no es una aprobación: la
decisión se escribe en ella, con su fecha.

## Plantilla de entrada

```
## B-NNN · <propuesta en una línea>

**Fecha:** AAAA-MM-DD
**Propuesta:** qué se añade y dónde.
**Problema que resuelve:** el fallo observado, con la evidencia medida (comando, cifra, informe).
**Coste:** líneas nuevas, hooks nuevos, tokens por sesión.
**Decisión:** entra · no entra · pospuesto, y por qué (AAAA-MM-DD).
```

---

## B-001 · Port de handoff y nucleo.sh a Python stdlib

**Fecha:** 2026-11-11
**Propuesta:** reescribir `handoff` y `nucleo.sh` en Python con solo la biblioteca estándar.
**Problema que resuelve:** sin evidencia medida todavía.
**Coste:** sin medir.
**Decisión:** pospuesto hasta después del 2026-12-09 (2026-11-11).

## B-002 · ICM barato y comprobable

**Fecha:** 2026-11-11
**Propuesta:** un ICM barato y comprobable.
**Problema que resuelve:** sin evidencia medida todavía.
**Coste:** sin medir.
**Decisión:** pospuesto hasta después del 2026-12-09 (2026-11-11).

## B-003 · Prueba del paseo nocturna y opt-in

**Fecha:** 2026-11-11
**Propuesta:** ejecutar la prueba del paseo cada noche, solo para quien la active.
**Problema que resuelve:** sin evidencia medida todavía.
**Coste:** sin medir.
**Decisión:** pospuesto hasta después del 2026-12-09 (2026-11-11).

## B-004 · Sensor de contrato con Claude Code

**Fecha:** 2026-11-11
**Propuesta:** un sensor que detecte cuándo Claude Code cambia el contrato del que depende el kit.
**Problema que resuelve:** sin evidencia medida todavía.
**Coste:** sin medir.
**Decisión:** pospuesto hasta después del 2026-12-09 (2026-11-11).

## B-005 · Evals versionados

**Fecha:** 2026-11-11
**Propuesta:** versionar los evals.
**Problema que resuelve:** sin evidencia medida todavía.
**Coste:** sin medir.
**Decisión:** pospuesto hasta después del 2026-12-09 (2026-11-11).

## B-006 · «Leer solo» en la plantilla de nucleo.md

**Fecha:** 2026-11-11
**Propuesta:** añadir una sección «Leer solo» a la plantilla de `nucleo.md`.
**Problema que resuelve:** sin evidencia medida todavía.
**Coste:** sin medir.
**Decisión:** pospuesto hasta después del 2026-12-09 (2026-11-11).

## B-007 · Dos revisores y una skill de verificación, de terceros

**Fecha:** 2026-11-11
**Propuesta:** agentes `pr-test-analyzer` y `silent-failure-hunter` (de
`anthropics/claude-plugins-official`, Apache-2.0) y skill `verification-before-completion` (de
`obra/superpowers`, MIT), adaptados y con su procedencia en `THIRD-PARTY.md`.
**Problema que resuelve:** tres huecos que ningún agente del kit cubre: dar algo por hecho sin
correr el comando que lo prueba, revisar si los tests de un PR cubren el comportamiento nuevo
(`quick-checker` solo da pasa/falla) y encontrar errores tragados en scripts. Salieron de leer
9 repos fijados por SHA; el uso real todavía no está medido.
**Coste:** 3 ficheros, 237 líneas, 0 hooks; sus `description` suman 676 B (≈ 170 tokens) en
el listado de cada sesión.
**Decisión:** entra (2026-11-11), por decisión del dueño al levantar la congelación. Se mide su
uso en la retro del 2026-12-09; sin usos, se retira.

---

## B-008 · Fundir `session-start.sh`, `session-start-clear.sh` y `session-start-compact.sh`
**Problema que resuelve:** tres scripts de `SessionStart` (matchers `startup|resume`, `clear` y
`compact`) comparten resolución de raíz, ranura de sesión y recorte; cada arreglo de estado hay
que repetirlo tres veces. La auditoría B de la consolidación (12-nov) lo señaló.
**Coste:** unas 50 referencias a los tres nombres en 9 suites (`test_session_start_clear`,
`test_nucleo_hooks`, `test_sesiones_home`, `test_presupuesto_contexto`, `test_doc_claims`…) y en
`scripts/contexto-base.sh`; riesgo de romper la inyección tras `/clear` y tras compactar, que es
lo que mide `nucleo-freshness.log`. Sin ganancia visible para la persona.
**Decisión:** aplazada (2026-11-12). Se hizo antes lo que sí se notaba: dueño por proceso, un
solo aviso de contexto, `post-compact-check.sh` plegado en `autosave.sh`. Reabrir si un cuarto
arreglo vuelve a tocar los tres.

## B-009 · Aplazados de la auditoría final del 13-nov (2.0.0)

**Fecha:** 2026-11-13
**Propuesta:** no añade nada al kit: recoge lo que la auditoría final dejó sin arreglar en 2.0.0, una línea
por hallazgo. Informes en `.claude/estado/informes/2026-11-13-auditoria-final/` (fuera de git). Ninguno cambia el
veredicto de un guard ni la integridad del estado; los de código se hacen después de publicar.
**Decisión:** pospuesto (2026-11-13). Entradas:

Release y scripts (`F5-sumas-release.md`):
- F5-06: `empaquetar-entrega.sh --out` relativo se resuelve contra la raíz del repo, no contra el cwd, y deja el árbol sucio (el siguiente paquete sale con `arbol_limpio=false`). Baja gravedad; el paquete sale bien.
- F5-08: `bump.sh` acepta `01.0.0` y `cambiar-origen.sh` acepta `a/..`. Solo los lanza quien publica; falta ajustar dos regex y dos casos de test.

Instalación y limpieza (`F9-ponytail.md`):
- F9-2: líneas `brew install` en `install.sh`, `doctor.sh` y tres guards que nunca se ven (la puerta de plataforma sale antes en macOS); quitarlas exige cambiar dos aserciones de `test_install_scc_deps.sh`.
- F9-4: el bucle de retirados por ruta está en `install.sh`, `uninstall.sh` y `doctor.sh`; sacarlo a `kit/lib/retirados.sh` (unas −12 líneas). Deuda, sin cambio de comportamiento.
- F9-5: la lista de hooks retirados está en tres sitios (`install.sh`, el literal jq y `hooks-retirados.sha256`); derivarla del `.sha256`. Sin verificar el camino «desinstalar 1.9.1 con el `uninstall.sh` de 2.0.0».
- F9-6: el lector de `.kit-desactivados` está en `install.sh` y en `doctor.sh`; un solo lector en la lib de F9-4.
- F9-7: `del_kit` y `propio` en jq son idénticos en `install.sh` y `uninstall.sh`; un `kit/lib/kit.jq`.
- F9-8: `MCHARNESS_OUT` y `.mcharness-out-marker` siguen como alias de `SCC_OUT`; retirarlos en una versión anunciada, no antes (cambia dónde queda el plan de quien lo use en un script).
- F9-9: `mostrar_fusion_settings` (19 líneas) repite lo que ya enseña el `diff -u`; quitar solo si el diff basta.
- F9-10: `scripts/generar-mapa.sh:95` calcula `.timeout`, que nadie lee.

Tests sueltos y CI (F7):
- F7-4 a F7-6: sin detalle en los informes que recibió el frente de documentación (solo constan como aplazados en `SPEC-arreglos.md`); consultar el informe F7 de la auditoría antes de abrirlos.

Estado y compatibilidad:
- F3-4: las rutas de `settings.json` quedan fijadas a `$HOME/.claude`; con otro `CLAUDE_HOME` los hooks no corren. No se reescriben rutas: se avisa (install y doctor) y queda documentado como no soportado en `OPERAR.md`.

Guards (`W-guards.md`, «Límites y cosas vistas sin tocar»):
- `echo … > x.sh; bash <x.sh` (redirección de entrada pegada) no pregunta; `main` ya lo permitía, no es regresión.
- `bash-write-guard.sh:27-38`: su `deny()` no comprueba que `jq` funcione y sale con 0 (el mismo patrón que se cerró en `block-dangerous-commands.sh`).
- El muestreo de semillas de composición de `test_guards_monotonia.sh` depende de la posición: un caso nuevo con prueba puede dejar sin detectar una mutación; lo vigila `test_guards_falsifiability.sh`.
- `python3 <<'EOF'` con texto que no es Python pasa Sentinel igual que en la base; sin estudiar.

Documentación, lo que exige código o tests (`F8-docs.md`):
- F8-01, F8-04, F8-06, F8-20: los textos están corregidos; falta el sensor en `test_doc_claims.sh` / `test_docs_enlaces.sh` (veredicto citado frente a `test_guards_veredictos.sh`, ancla `ENTREGA.md#actualizar`, fila «apagar» del cockpit, un enlace `[X.Y.Z]:` por cada entrada del CHANGELOG).
- F8-02: el texto de CONTRIBUTING ya dice 7 ficheros; falta la aserción de `test_bump.sh` con la lista exacta de ficheros editados.
- F8-05: el paquete no trae `Makefile` ni la mayoría de `scripts/`; `ENTREGA.md` lo declara. Arreglarlo de verdad es añadir esos scripts a `PRODUCTO` de `empaquetar-entrega.sh`, más un test que resuelva los enlaces relativos de los `.md` del paquete.
- F8-08: el comentario de `test_guards_falsifiability.sh` (:14-17, :63) cita «36» y README; la cifra vive en `10-onboarding.md` y no la ata ningún sensor.
- F8-09: `scripts/verificar-docs.py` solo mira README, ENTREGA, OPERAR y `guia/`; que recorra `kit/docs/*.md`.
- F8-12: `doctor.sh:129` dice «deja de proteger lo que ese guard bloquea» también para guards que solo avisan (`stale-read-guard.py`).
- F8-18: la salida de `install.sh:677` dice «se enlazarian handoff y oraculo» y luego lista cinco.
- F8-21: `scripts/generar-mapa.sh:17` filtra variables por prefijo y deja fuera `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, que mueve los umbrales del aviso y del handoff automático.
- F8-22: `CONTRIBUTING.md:196-199` («Hasta v2.0, ningún hook… sin entrada en BACKLOG») caduca con la 2.0.0, y decidir si sigue vigente es del dueño; el «camino corto» de `02-install.md` y `10-onboarding.md` es `bash kit/install.sh` sin `--plan`, frente al camino `--plan` → `--apply` del README.
