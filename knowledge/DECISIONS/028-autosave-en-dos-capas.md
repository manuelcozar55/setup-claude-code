# ADR 028 — Autosave del estado en dos capas: hitos y turnos, reloj solo como red, el modelo fuera del camino caliente

**Fecha:** 2026-11-09 · **Estado:** propuesta · **Complementa a:** ADR 015, 026, 027

## Contexto

`nucleo.md` solo queda bien escrito cuando la persona ejecuta `/handoff`. Lo medido sobre las transcripciones y los
logs del kit:

- **El 85 % de las compactaciones cae a mitad de un turno** (116 automáticas del hilo principal, 16-oct a 3-nov;
  ADR 026, «Contexto»). Ahí un handoff con `/clear` no cabe.
- **El 75 % llega sin estado escrito** en los 20 turnos previos (166 de 220; `kit/docs/guia/01-por-que-contexto.md:37`).
  De ahí la base de 25 % de arranques con estado fresco que usa la métrica de este ADR.
- **El aviso 50/70/85 % se cumple el 47 %** de las veces en 3 turnos, y en el 22 % se compacta antes de que se
  cumpla (186 avisos; ADR 020).
- **Cierre desatendido, 06-nov-2026:** falló porque dependía de que la persona hiciera `/handoff` y cerrara 4
  sesiones; ninguna se cerró en 6 h. `agentes.sh` en `SessionEnd` solo libera `.dueno` y anota agentes cortados
  (`kit/claude/hooks/agentes.sh:1-87`), no guarda estado.
- **`claude --resume` desde `~` pierde la ranura.** La ranura `~/.claude/estado/sesiones/<fecha>-<pid>/` se ata al
  proceso (`.proceso`, ticks de `/proc/<pid>/stat`; `kit/claude/hooks/lib/nucleo.sh:135-272`). Al reabrir el PID
  cambia y la ranura antigua no se reinyecta: límite ya documentado en los ADR 019 y 027, pero no resuelto.

El kit tampoco tiene hoy el hueco cubierto con hooks shell. Ningún hook escribe `nucleo.md` ni llama a un modelo
(`knowledge/DECISIONS/015-handoff-hibrido-por-defecto.md`). El único auto-handoff vive en el cockpit, que es opt-in:
`maybeAutoHandoff` dispara al cerrar un turno `answer` con contexto ≥ `COCKPIT_AUTO_HANDOFF` (50-95, por defecto 70),
hace fork, toast, banda, `/clear` y relleno de prompt (`kit/mods/cockpit/hooks/register.tsx:805-835`, umbral :572).
Es visible por construcción y no corre en `-p` ni sin TUI.

### Qué falta, por lectura del código (`.claude/estado/informes/2026-11-09-auto-handoff/scc-mecanismos.md`, §4)

1. **Disparo por turno sin modelo:** `stop-context-gauge.sh` corre en cada `Stop`, recibe `session_id`, `cwd`,
   `transcript_path` y `last_assistant_message`, y solo avisa u observa (`kit/claude/hooks/stop-context-gauge.sh:1-74`).
2. **Captura determinista desde el transcript:** existe el último mensaje humano (`pre-compact.sh:74-86`), el último
   `git commit` (`stop-context-gauge.sh:52-58`) y el uso de contexto (`lib/nucleo.sh:504-537`). No existe extracción de
   ficheros tocados por Edit/Write ni de comandos Bash con su resultado; los «Ficheros tocados» salen de git y los rc
   de `verificaciones.log` solo si el modelo usó `oraculo` (`kit/claude/bin/oraculo:1-60`).
3. **Sin detector de hito:** hay señales sueltas (commit en el transcript, `oraculo` rc 0, TodoWrite completo en el
   cockpit, `register.tsx:1032`) y ninguna dispara un guardado.
4. **El fork no es silencioso:** `runHandoff` siempre actualiza banda, toast y recibo (`register.tsx:693-800`). El coste
   del fork al 70 % no está medido (`kit/docs/11-cockpit.md`, «Limitaciones»).

### Qué dice la industria sobre cuándo y quién guarda

Anthropic clasifica los bucles por qué los dispara y qué los termina: turn-based, goal-based, time-based y proactive
(«Loop engineering: Getting started with loops», 2026-06-30, https://claude.com/blog/getting-started-with-loops).
El texto no trata la persistencia entre ejecuciones; aquí se usa solo como vocabulario para ordenar disparadores:

| Patrón | Qué dispara | Equivalente en SCC |
|---|---|---|
| Turn-based | cierre de un turno | `Stop` (ADR 026: el handoff necesita frontera de turno) |
| Goal-based | meta comprobable | hito: oráculo a verde en `verificaciones.log`, `git commit`/PR fusionada, `[x]` en el Plan, TodoWrite completo |
| Time-based | reloj | `$.clock.every` del mod, `Notification` `idle_prompt` |
| Proactive | el agente se autoinicia | `/loop`, sleep-time de Letta, consolidación tras compactar |

La revisión de fuentes (`industria.md`, §4) deja cuatro prácticas repetidas que fundamentan el diseño:

- **Guardar en límites naturales, no por reloj.** OpenAI Agents SDK guarda los items nuevos tras cada run
  (https://openai.github.io/openai-agents-python/sessions/, leído 2026-11-09); LangGraph persiste por super-step
  (https://docs.langchain.com/oss/python/langgraph/persistence, 2026-11-09, lectura parcial); Letta consolida tras N
  pasos o al compactar (https://docs.letta.com/guides/agents/sleep-time-agents, 2026-11-09). El tiempo puro aparece solo
  como disparo de trabajo: `/loop` solo corre con la sesión abierta e inactiva y expira a los 7 días
  (https://code.claude.com/docs/en/scheduled-tasks, 2026-11-09).
- **Lo barato lo escribe código determinista; la síntesis, un modelo, fuera del hilo principal.** Letta usa modelos
  baratos y agentes en segundo plano «sin interrumpir el trabajo activo»; `/goal` usa Haiku
  (https://code.claude.com/docs/en/goal, 2026-11-09).
- **Lo redactado por el modelo lo reescribe solo el modelo.** Cognition observó que apoyarse en notas sin la
  compactación del propio modelo degradaba («el modelo no sabe lo que no sabe»;
  https://cognition.ai/blog/dont-build-multi-agents, 2025-06-12; el seguimiento con Sonnet 4.5, sep-2025, [S]).
  Anthropic mantiene estructura rígida para lo que se actualiza (https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents,
  2025-11-26).
- **Topes en todo lo automático** (turn caps, 7 días del `/loop`, 3 check-ins ociosos de `/goal`).

Claude Code 2.1.311 aporta las piezas para hacerlo sin modelo (`claude-code-capacidades.md`, §1 y §6;
https://code.claude.com/docs/en/hooks, 2026-11-09): `Stop` con `last_assistant_message`; `async: true` solo en `command`;
`PostCompact` con `compact_summary` sin coste de modelo extra; `SessionEnd` con presupuesto de 1,5 s que sube con
`timeout` por hook hasta 60 s; `SessionStart` con matchers `startup|resume|clear|compact|fork`.

## Decisión

**Autosave en dos capas, disparado por hitos y turnos. El reloj es solo una red de seguridad. El modelo no está nunca
en el camino caliente.**

### Capa 1 — kit, determinista, siempre activa, cero llamadas al modelo (coherente con ADR 015)

1. **`Stop` asíncrono** (`"async": true`, con control de duración propio dentro del script), ampliando
   `stop-context-gauge.sh`: no suma hook al presupuesto. Tras cada turno llama a un modo nuevo del CLI,
   `handoff --auto --sesion <sid>`, que fusiona **solo** la sección `## Último turno (auto)`, ≤ 600 B, dentro del
   tope de 5700 B (`kit/claude/bin/handoff:19-33`; el CLI escribe ≤ 5700 B de 6500, con 800 B para agentes):
   hora, último mensaje humano (molde: `pre-compact.sh:74-86`), `last_assistant_message` recortado, ficheros tocados
   (fuente de verdad: git, `git diff --name-only HEAD` + `git ls-files --others --exclude-standard` con `timeout 3`,
   porque `/mnt/c` es 3,7× más lento; las rutas `tool_use.input.file_path` de Edit/Write/NotebookEdit del transcript
   son complemento y pueden ir por detrás, ya que el transcript se escribe de forma asíncrona), comandos Bash con rc
   (del transcript y de `verificaciones.log`), rama/HEAD y % de contexto (`nucleo_ctx`, `lib/nucleo.sh:510`, ya en
   producción para el nudge; la capa 2 usa `$.session.usage()`).
   Como `async` no aplica timeout (https://code.claude.com/docs/en/hooks, 2026-11-09), el script se autoacota: `timeout`
   interno ≤ 5 s para la captura. Qué hace Claude Code al exceder el timeout declarado en settings sigue [NV].
2. **No toca Objetivo, Invariantes, Paso actual ni Siguiente acción.** Lo redactado por el modelo lo reescribe solo
   el modelo (Cognition, arriba). Un resumen determinista de «Paso actual» sería un dato falso con apariencia de
   síntesis.
   `handoff --auto` es un camino propio del CLI con cuatro reglas: (a) solo escribe `## Último turno (auto)`, cabecera
   nueva añadida a la lista fija de la plantilla; (b) bajo el mismo lock y con escritura atómica (tmp + `mv`); (c) NO
   rota `nucleo.prev-*` (las copias prev son solo para fusiones redactadas por el modelo); (d) NO toca ni libera el
   dueño (hoy `--desde` lo libera al terminar).
   **Límite explícito:** `Stop` no corre si la persona interrumpe el turno. Ese turno lo cubren `PreCompact`/`PostCompact`
   y `SessionEnd`, o el `Stop` siguiente: el estado puede ir, como máximo, un turno interrumpido por detrás.
3. **Marca `dirty`** (hubo Edit/Write/commit desde la última síntesis con modelo) en un fichero hermano del estado.
4. **`PostCompact`:** guarda `compact_summary` como checkpoint junto al de `pre-compact.sh` y marca `dirty=compact`.
   Hoy `post-compact-check.sh` solo compara anclas (`post-compact-check.sh:1-51`).
5. **`SessionEnd`** con `timeout` explícito (≈ 10 s; el defecto es 1,5 s): mismo vaciado determinista para `clear`,
   `logout`, `prompt_input_exit` y `other`. Se amplía `agentes.sh` (hoy 3 s, `settings.json:249`), sin hook nuevo.
6. **`SessionStart` localiza la ranura por `session_id` además de por PID:** índice `sid → ranura`. Con él,
   `claude --resume` desde `~` recupera su estado, que es el fallo del contexto. Las rutas se siguen validando como
   en el ADR 027 (absolutas, sin `..`, bajo `~` o la raíz).
7. **Resultado:** el estado nunca va más de un turno por detrás, aunque no haya cockpit y la persona no haga nada.

### Capa 2 — cockpit (opt-in), síntesis con modelo, silenciosa

1. Reutiliza `maybeAutoHandoff` y `runHandoff` (`register.tsx:805-835`, :693-800) con un modo **`silent`**: sin toast,
   sin banda, sin recibo en el chat; a lo sumo un indicador en la statusline («guardado hh:mm»).
2. **Guarda sin `/clear`** (`runHandoff(false)`, lo que ya hace `/handoff solo`). El `/clear` con relleno de prompt
   queda solo para el airbag (≥ 70 %), que por naturaleza es visible.
3. **Disparadores**, evaluados en `turn.complete`:
   - (goal) hito: oráculo verde tras rojo, commit o PR, `[x]` nuevo en el Plan, TodoWrite completo;
   - (turn) cada ≈ 8 turnos o +15 puntos de contexto desde la última síntesis, solo si `dirty`;
   - (proactive) primer `turn.complete` tras una compactación: se detecta por `dirty=compact` (capa 1), no por
     `session.compact` (ver Descartado);
   - (time, red) `$.clock.every(10 min)` solo si `dirty` y sin síntesis en ≥ 10 min.
4. **Topes:** una síntesis cada 5 turnos y cada 10 min como máximo; ninguna sin `dirty`; el fork exige una respuesta
   previa del modelo en el proceso (`nothing-to-fork`, `scc-mecanismos.md` §1c); el coste del fork se mide y se anota
   en `knowledge/COST-LOG.md`.
   **Modelo de síntesis:** se empieza con `$.model.fork` (código existente; comparte el prefijo cacheado de la
   conversación, así que el coste real son tokens de lectura de caché). Criterio: si la mediana por síntesis supera el
   2 % de los tokens del turno medio, la fase 3 cambia a `$.model.complete` con un modelo pequeño (Haiku) sobre el
   bloque auto + los últimos mensajes. El rastro del fork en el transcript sigue [NV].
5. `/handoff` sigue como orden manual. `/autosave on|off|status` controla la capa 2.

### Restricciones que se respetan

- Presupuesto del repo (`CLAUDE.md`): ≤ 3 hooks nuevos. Ampliar `stop-context-gauge.sh` y `agentes.sh` no suma;
  `PostCompact` sustituye en el sitio a `post-compact-check.sh` o se añade a él (decisión en la fase 1).
- `timeout ≤ 5 s` en el camino caliente. El `Stop` declara un timeout ≥ el del script (15 s hoy,
  `settings.json:216`) para no fallar en abierto.
- El único escritor de `nucleo.md` sigue siendo el CLI (lock, `nucleo.prev-*`, tope, diario, dueño). Ningún hook edita
  el fichero a mano. El SID del evento va en `--sesion` (`handoff:114-115`).
- El contenido del estado y de los transcripts es dato: sin rutas de credenciales, sin pasar a servicios externos
  (política gestionada, reglas 1 y 7). El fork usa el mismo modelo y sesión que ya ven esos datos; no hay llamada
  nueva a un tercero.

## Descartado

- **El reloj como disparador principal.** La industria usa el tiempo para disparar trabajo, no para persistir
  (`industria.md`, §4.3). Sin `dirty` escribiría ruido y compitiría por el fork; las sesiones pueden pasar días
  inactivas; `/loop` solo corre con la sesión inactiva y caduca a los 7 días
  (https://code.claude.com/docs/en/scheduled-tasks, 2026-11-09). Queda solo como red de la fase 4.
- **Un cron externo con `claude -p --resume`.** Cuesta una llamada por sesión, depende de la autenticación con cswap,
  puede salir con `exit 1` si la salida está redirigida (`claude attach`; [NV] el caso de una sesión viva en otra
  terminal; https://code.claude.com/docs/en/sessions, 2026-11-09) y compite con la sesión viva por el estado.
- **Hooks `prompt`/`agent` en cada `Stop`.** Una llamada facturada por turno y latencia (`prompt` 30 s, `agent` 60 s y
  experimental; https://code.claude.com/docs/en/hooks, 2026-11-09). `async` solo existe para `command`. Es lo que ya
  rechazó el ADR 015 («modelo en Stop: una llamada por turno»).
- **`/schedule` en la nube.** Clona el repo en limpio y no ve el disco local ni `~/.claude`
  (https://code.claude.com/docs/en/routines, 2026-11-09).
- **Que un hook determinista reescriba «Paso actual» con un resumen sin modelo.** Degrada (Cognition, 2025-06-12) y
  rompe el contrato del ADR 015 de que lo redactado lo escribe el modelo.
- **Escuchar `session.compact` desde el mod.** En las máquinas con `/etc/claude-code`, `cc-plugin-sec-default@builtin`
  se sienta el primero y lo tapa (ADR 026). Se evita con un fichero `dirty=compact` que escribe el hook shell.
- **Bloquear la compactación desde `PreCompact`.** Ya descartado en los ADR 013, 015 y 022.

## Plan de implementación

Cada fase se cierra con `make test` en rc 0 (`CLAUDE.md`) y su verificación concreta.

1. **Kit, capa 1.** `handoff --auto`, extracción de ficheros/comandos del transcript, `Stop` asíncrono, `SessionEnd`
   y `PostCompact`. Tests nuevos en `kit/test/test_autosave.sh`: sección ≤ 600 B, tope respetado, sin tocar las otras
   secciones, transcript a medias, `-p`, y 50 ejecuciones seguidas de `--auto` → 0 `nucleo.prev-*` nuevos, dueño
   intacto, nucleo ≤ tope. Medida: sobre las transcripciones, % de
   compactaciones/clears/resumes que arrancan con estado ≤ 1 turno de antigüedad (base 25 %, objetivo ≥ 95 %), con
   `scripts/nucleo_audit.py`.
2. **Ranura por `sid`.** Índice `sid → ranura` en `lib/nucleo.sh` y lectura en `session-start-clear.sh`. Caso nuevo
   en `kit/test/test_sesiones_home.sh`: `--resume` desde `~` con PID distinto recupera el estado.
3. **Cockpit, capa 2.** `silent`, disparadores, topes y `/autosave`. Verificación: `claude plugin test .` (176 tests
   `.tsx` más los nuevos de `handoff.test.tsx`) y coste del fork en `knowledge/COST-LOG.md`.
4. **Red temporal**, solo si las métricas de 1-3 dejan huecos (`$.clock.every`, `Notification` `idle_prompt`, cuyo
   disparo es [NV]).
5. **Docs.** `kit/docs/guia`, `kit/docs/11-cockpit.md`, CHANGELOG 1.9.0. Se retira la ceremonia de `/handoff` de las
   instrucciones; queda como orden manual.

### Antes de implementar, probar (de `claude-code-capacidades.md`, §6)

- (a) Que un `Stop` async escribe durante una sesión larga y qué hace Claude Code con el timeout de `settings.json`
  ([NV]: la doc solo dice que no se aplica a async en ejecución).
- (b) `SessionEnd` con `timeout: 10` y escritura real tras `Ctrl-C`/cierre de terminal.
- (c) Que `$.model.fork` no deja rastro en el transcript ([NV]; la doc no lo afirma).

## Métricas de éxito

| Métrica | Objetivo | Cómo se mide |
|---|---|---|
| `/handoff` manuales necesarios | 0 en una semana de uso | recuento en transcripciones |
| Arranques (compact/clear/resume) con estado ≤ 1 turno | ≥ 95 % (base 25 %) | `nucleo-freshness.log` y `compact-AAAA-MM.log` |
| Líneas en el chat producidas por el autosave | 0 | revisión de transcripciones: ni toast ni recibo ni mensaje |
| Coste de síntesis de la capa 2 | acotado; cifra a fijar tras medir | fork medido en `knowledge/COST-LOG.md` |
| Latencia añadida al turno por la capa 1 | 0 (async) | tiempo de `Stop` en `gate-nucleo.log` |
| `make test` | verde, exit 0 | `make test` |

## Qué permite afirmar de SCC

- La continuidad de estado de sesión deja de depender de que la persona se acuerde: la capa 1 la garantiza con hooks
  shell, sin cockpit y sin modelo, y está medida (arranques con estado ≤ 1 turno).
- Los guardrails siguen siendo deterministas (ADR 015): ningún hook llama a un modelo; el CLI es el único escritor.
- Los sensores miden el resultado (`nucleo-freshness.log`, `compact-AAAA-MM.log`), no solo lo registran.
- La continuidad también cruza la cuenta: `--resume` desde `~` recupera su estado por `session_id`, sea cual sea la
  cuenta de cswap con la que se reabra.
- No afirma todavía: el coste de la capa 2 (sin medir), que el fork sea invisible en el transcript ([NV]), ni que la
  capa 2 funcione sin cockpit: requiere el mod y una TUI interactiva.
