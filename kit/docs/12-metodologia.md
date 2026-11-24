# 12 · Metodología: un solo bucle

El kit instala una forma de trabajar y la reduce a una regla: **adapta la ceremonia al riesgo**.
Un typo, una búsqueda o una pregunta se hacen directos. Un cambio grande, ambiguo, irreversible o
que toca seguridad o producción entra por `/deep-change`. No hay más bucles.

## El bucle: `/deep-change`

La skill [`deep-change`](../claude/skills/deep-change/SKILL.md) es lo único que el kit instala por defecto en
`~/.claude/skills/`. Sus pasos, en orden:

1. **Apertura** (IntentGate, en [`AGENTS.md`](../claude/AGENTS.md)): resultado, alcance, criterios
   verificables y supuestos. Si hay un camino más simple, se dice. Una sola ronda de preguntas.
2. **Diseño aprobado antes de ejecutar.** Tareas pequeñas, cada una con ficheros, cambio y prueba.
3. **Ejecutar sin parar** (Never-Stop): sin «¿sigo?». Ante una duda a mitad, la opción conservadora y
   reversible, anotada en el informe. Solo para un bloqueo que exige a la persona.
4. **Verificar con el código de salida.** El test que primero falla y luego pasa; el artefacto real mejor
   que «compila, luego funciona». Lo que no se pudo verificar se dice, no se insinúa.
5. **Commits con su porqué** y el estado al día.

El criterio para dar algo por entregado es doble: **la entrega** (el cambio hace lo pedido, con la prueba que lo
demuestra) y **el lector** (quien lo reciba entiende qué cambió y por qué sin reconstruirlo). Sin evidencia de las
dos, no está hecho.

Si instalas la pieza opcional `esenciales`, su skill de ejecución manda dentro de su propio worktree; fuera de él,
manda `deep-change`.

## El estado, en disco y sin pedirlo

El estado de una tarea vive en `.claude/estado/nucleo.md` de la raíz git del proyecto: una tarea, un
worktree, un fichero. No hay que crearlo ni actualizarlo a mano.

- Tras cada turno, `autosave.sh` guarda la sección `## Último turno (auto)` (hora, rama, HEAD, ficheros tocados,
  comandos con su rc). En un repo sin estado, el primer guardado con trabajo crea `nucleo.md` desde la plantilla
  y deja `.claude/estado/` fuera de git. Las claves y tokens se redactan antes de guardarse (ADR 028).
- Tras `/clear`, `resume` o una compactación, `session-start-estado.sh` entrega el estado a la sesión nueva como
  dato, no como orden. Si lleva más de 10 min sin tocarse, pide al modelo actualizarlo.
- Secciones, en el orden en que se inyectan: Objetivo, Invariantes, Paso actual, Siguiente acción, Comandos de
  verificación, Plan, Pendientes y Ficheros tocados ([`templates/nucleo.md`](../claude/templates/nucleo.md)). Lo
  cerrado va a `diario.md`, que nunca se inyecta.
- Cada `[x]` del Plan nombra el comando que lo verificó. `oraculo -- <cmd>` lo ejecuta con `pipefail`, imprime las
  últimas 40 líneas y `rc=N`, sale con ese rc y lo anota en `.claude/estado/verificaciones.log`.
- `handoff --desde <borrador>` es la orden manual y opcional para fijar un foco al cerrar una fase; valida las
  cabeceras, conserva Objetivo y nunca borra una Invariante. `handoff --proyecto <ruta>` vincula una sesión
  lanzada en `~` con un repo (ADR 029). Con el mod [`cockpit`](11-cockpit.md), `/handoff` y `/nueva` lo hacen por ti.
- Una sesión es dueña del estado mientras su proceso `claude` esté vivo (`.claude/estado/.dueno`); otra sesión
  recibe un aviso y `--auto` no escribe en el estado ajeno. `handoff --liberar <sesión>` lo suelta.

## Qué se dispara y cuándo

| Evento | Hooks (timeout) | Efecto visible |
|---|---|---|
| `SessionStart` | `session-start.sh`, `session-start-estado.sh` (`startup\|clear\|resume\|compact`) | Inyecta el nucleo como dato; avisa si otra sesión es la dueña o si se retoma con la caché caducada |
| `Stop` | `autosave.sh` (10, asíncrono), `agentes.sh` (15) | Guarda `## Último turno (auto)`; anota los agentes en vuelo; compuerta de commit (`NUCLEO_GATE`, apagada por defecto) |
| `PreCompact` | `pre-compact.sh` (10) | Checkpoint y la línea de `nucleo-freshness.log` |
| `PostCompact` | `autosave.sh` (8) | Guarda y mide cuántas anclas del checkpoint nombra el resumen |
| `SessionEnd` | `autosave.sh` (10), `agentes.sh` (3) | Guarda, libera al dueño y anota los agentes que se cortan al cerrar |
| `SubagentStart` / `SubagentStop` | `agentes.sh` (3) | Registro de agentes (el bloque `<agentes>` del arranque) |

Los avisos de contexto (50, 70 y 85 %) son la pieza opcional `nudge` (`--con nudge`): sin ella, el estado ya queda
guardado por `autosave.sh` y no hay avisos. Para apagar el guardado quita las entradas de `autosave.sh` del
`settings.json`; el resto sigue funcionando.

## Variables

No hay variables `AUTOSAVE_*` ni `HANDOFF_*`. Las que quedan:

| Variable | Defecto | Efecto |
|---|---|---|
| `NUCLEO_TOPE` | `6500` | Bytes que se inyectan del nucleo y que `handoff` deja escritos (menos 800 de reserva para `<agentes>`) |
| `NUCLEO_AUTOINICIO` | `1` | `0`: un repo sin `nucleo.md` no se crea solo desde `--auto` |
| `NUCLEO_DUENO_TTL` | `14400` | Segundos tras los que caduca un dueño sin identidad de proceso |
| `NUCLEO_GATE` | `off` | `observe` solo anota en `gate-nucleo.log` un commit sin nucleo tocado; `block` bloquea el `Stop` en ese caso |
| `NUCLEO_COCKPIT` | sin fijar | `1` o `0` fuerza «hay cockpit» o «no hay»; sin fijar se detecta |
| `NUCLEO_CHECKPOINT_KEEP` | `5` | Checkpoints de `pre-compact.sh` que se conservan por proyecto |
| `NUCLEO_REGISTRO` | `~/.claude/estado/raices` | Registro de raíces que alimenta el índice de `~` |
| `COCKPIT_AUTO_HANDOFF` | sin fijar | `off`: el cockpit no hace el handoff automático |

La tabla de todos los interruptores, con su efecto, está en [`MAPA.md`](MAPA.md).

## Subagentes

Dos o más flujos independientes se lanzan en paralelo, cada uno con su contexto: al hilo principal vuelve la
conclusión, no el volcado. El prompt a un subagente apunta a un fichero de spec; no lo pega. Cada uno es dueño de
sus ficheros y ninguno hace commit ni push: lo hace el hilo principal. Los agentes que instala el kit están en
[`kit/claude/agents/`](../claude/agents/); los revisores extra son la pieza `revisores`.

## Cerrar el ciclo

`/retro` revisa una sesión y propone mejoras al entorno del agente; es manual y es la pieza `skills-extra`
(`bash kit/install.sh --con skills-extra`). Aplicarlas es un cambio aparte, por `deep-change`. No confundir con
`/retro-repo` ([`.claude/commands/retro-repo.md`](../../.claude/commands/retro-repo.md)), que es de este repo y
convierte lo aprendido en `knowledge/` versionado.

La skill `retro` deriva de [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, con su licencia en
cada carpeta y la atribución en [`THIRD-PARTY.md`](../../THIRD-PARTY.md)). `deep-change` es propia.
