# Changelog

Formato basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/).
Este proyecto sigue [Versionado Semántico](https://semver.org/lang/es/).
`[Unreleased]` recoge lo que está en `main`, o en camino a él por PR, y aún no se ha
etiquetado.

## [Unreleased]

## [1.6.0] - 2026-10-27

### Added

- **Compuerta de frescura del nucleo (`nucleo-gate.sh`, `PreToolUse`).** El aviso de `nucleo-nudge.sh` se cumplía en el 47 % de los casos en 3 turnos (186 avisos) y dentro de un turno autónomo no hay Stop que lo fuerce. Tras el aviso de la banda 70 u 85 con el nucleo sin escribir, la 4.ª llamada del hilo principal se deniega una vez por banda y sesión, con el motivo (`actualiza <nucleo>` o `handoff --desde <borrador> --sesion <id>`). Pasan siempre lo que cuelga de `.claude/estado/` y `handoff`; los subagentes (`agent_id`) no cuentan; falla en abierto; `env.CC_NUCLEO_GATE=0` la apaga y `doctor.sh` lo marca WARN. El nudge guarda ahora `nudge-<sid>.nucleo` con la ruta que miró. ADR 020. Tests: `test_nucleo_gate.sh`.
- **Hook `PostCompact` (`post-compact-check.sh`).** Tras compactar comprueba que el resumen nombre los ficheros que el checkpoint de `pre-compact.sh` declaraba tocados (su `git status`; un fichero nombrado solo en un prompt no cuenta), anota `anclas_perdidas=N` en `session-logs/compact-AAAA-MM.log` (lo lee `compact-audit.py`) y avisa si falta alguno. Sin modelo, timeout 5 s, falla en abierto. Antes era un script suelto que la reinstalación del 21-oct dejó sin cablear. ADR 021.
- **`doctor.sh` avisa (WARN) de cuatro derivas que antes no veía:** memoria automática con `.md` sin línea en `MEMORY.md` o con enlaces rotos; `MEMORY.md` por encima de 150 líneas o 20 KB (Claude Code carga 200 líneas o 25 KB); worktrees `prunable` o en detached bajo `/tmp` del repo actual; y un `nucleo.md` mayor que `NUCLEO_TOPE`. Nunca FAIL; el coste de `doctor` no cambia.
- **`test_presupuesto_contexto.sh` suma por evento lo que inyectan los hooks del kit** y falla por encima de 10.000 caracteres. Es un presupuesto propio: la doc de Claude Code pone ese tope por cadena, no por evento.

### Fixed

- **Un `git` colgado ya no agota el timeout de `pre-compact.sh`, `session-start-compact.sh` ni `post-compact-check.sh`.** `nucleo_raiz` llamaba a git sin tope y el hook moría por timeout sin checkpoint, nucleo ni línea de log; ahora acepta un tope (2 s en los tres hooks) y, si git no responde, cae a `$HOME`. Rescatado de `fix/icm-checkpoint-local`.
- **`test_evals.sh` y `test_doctor_base_url.sh` ya no dejan sus `mktemp -d` en `/tmp`:** eran 5 y 23 directorios por corrida en un tmpfs de inodos fijos (agotado el 2026-10-03). Cada suite fija un `TMPDIR` propio y lo borra.
- **`test_evals.sh` anota en `SCC_SKIP_LOG` lo que se salta** (sin pyyaml o sin `claude`): antes imprimía `ok` y el resumen de `make test` no lo listaba.

## [1.5.1] - 2026-10-26

### Fixed

- **`install.sh` ya no borra tus hooks al reinstalar: la fusión de `settings.json` va por propietario.**
  - **Qué pasaba:** `install_settings` sustituía el bloque `hooks` entero (`$kit.hooks // $old.hooks`). La reinstalación del 21-oct se llevó en silencio un `PostCompact → post-compact-check.sh` y un `PreCompact` de otra capa.
  - **Qué hace ahora:** el kit solo sustituye las entradas cuyo comando es uno de sus scripts de `.claude/{hooks,sentinel}/`, a secas, tras un intérprete o con `optional-hook.sh`. Cuentan los que cablea la plantilla y los retirados `smart_approve.py` y `preflight.sh`. Un comando que además hace otra cosa es tuyo.
  - **Lo que se conserva:** el resto queda detrás de las suyas, con su `matcher`, y `doctor.sh` lista los hooks ajenos al kit. Un evento que no es lista o un grupo sin `hooks` se descarta sin abortar la fusión.
  - **Tests:** `test_install_settings_merge.sh` (casos e a e3, 5 rojos contra v1.5.0) y `test_doctor.sh`.
- **`install.sh --plan` enseña lo que haría `--apply`.**
  - **Qué pasaba:** el plan generaba su árbol en un directorio vacío. `settings.json` salía como la plantilla sin fusionar, y `CLAUDE.md` y `AGENTS.md` como los del kit. El diff daba por borrados tu `env`, `model`, permisos y hooks propios, y tu `CLAUDE.md`, aunque `--apply` los conserva. Es el modo por defecto cuando `CLAUDE_HOME` es un repo con remoto.
  - **Qué hace ahora:** siembra el árbol del plan con una copia de los tres instalados (copia y no enlace, para no fusionar a través de él). Los backups de esa fusión se hacen dentro del árbol del plan y se borran, y `CLAUDE_HOME` no se toca. Si tu `CLAUDE.md` no importa `AGENTS.md`, el plan lo avisa como `--apply`.
  - **Tests:** `test_install_diff_first.sh` compara el `settings.json` del plan con el de `--apply` sobre una copia (6 rojos contra `5de0955`). Un mutante que siembra el enlace cae en 2 checks, y otro sin el aviso ni la limpieza del backup, también en 2.
- **Guards, pipe-a-shell (C-01).** `block-dangerous-commands.sh` y Sentinel bloquean también `busybox sh`, `ash`, `dash`, `ksh`, `fish`, `node`/`nodejs`, `perl`, `ruby`, `php`, `lua`, los envoltorios `time`/`nice`/`timeout`/`stdbuf`/`setsid`/`env`/`nohup`/`xargs`, `( … )`, `{ …; }`, asignaciones de entorno, `bash <<< "$(curl …)"`, `nc … | sh`, `| while read; eval` y `| awk system`. Test: `fixtures/guards-v151.tsv` (C-01), 47 filas rojas antes. Lo que ninguna regla ve (`cur''l`, `$S` con `S=bash`) queda en `05-security.md`.
- **Guards, `.env` sin barra inicial en Sentinel (C-03).** `cat .env`, `head`, `source`, `cp`, `tar`, `xxd`, `base64`, `curl -d @.env` y `git show HEAD:.env` se bloquean por palabra del comando; `.env.example` y las demás plantillas pasan. `secret-guard.sh` sigue mirando solo `git add` (documentado).
- **Guards, escrituras por Bash sobre la config del kit (C-04).** Sentinel bloquea `rm`, `mv`, `cp` hacia, `chmod`, `tee`, `sed -i`, `>`, `install`, `ln`, `dd of=`… sobre `~/.claude/settings*.json`, `hooks/`, `sentinel/` y `sentinel-allowlist.json`, sin que la allowlist lo levante. Leerlos sigue permitido. Límite: el código de `python -c` no se lee.
- **Guards, git y `gh` (C-06, C-07).** Se bloquean las abreviaturas reales de `--mirror`, `--delete` y `--no-verify`, `git -c core.hooksPath=…` y `git -c alias.…`; `git config core.hooksPath ruta` pide confirmación (F-02). `gh api` con DELETE/PUT/PATCH, `/merge`, `force=true`, `state=closed` o una mutación, y `gh repo delete`, piden confirmación.
- **Guards, la excepción de K1 era demasiado ancha (C-08, C-09).** `python` con ruta o con prefijo de entorno y descargas con `-o`/`-K`/`-T`/`-d @fichero` ya no entran en ella; los dos guards coinciden en la sustitución `$(curl …)` en posición de comando, `X=$(curl …); $X` y la redirección o `tee` hacia `~/.bashrc`, `~/.profile`… Los `jq -f`, `jq -n env` o `curl -K … | jq` no pasaban por la excepción (`curl … | jq` no es pipe-a-shell): no se bloquean y queda dicho en `05-security.md`.
- **Los cinco guards de Bash fallan cerrados (C-02).** `settings.json` lleva `"onFailure": "block"` en ellos: un guard que no arranca o agota su timeout ya no deja ejecutar el comando. Documentado en la referencia de hooks (Claude Code ≥ 2.1.295) y comprobado con `claude` 2.1.308; `doctor.sh` avisa con una versión anterior.
- **El bloqueo de Sentinel ya no manda a ampliar la allowlist (B-03).** En un bloqueo de comando o de config del kit el mensaje da la salida (descarga a fichero, `jq` o `python -c` que solo lea) en lugar de la línea de la allowlist.
- **El tope de CPU de `test_guards_falsifiability.sh` mide el mejor de hasta 3 (A-02).** Con otra suite en marcha en la misma CPU, una sola medida daba falsos rojos; el tope sigue en 1000 ms.
- **`05-security.md` decía que `Edit(...)` no frena a `Bash` (C-12, C-15).** La referencia de permisos dice que las reglas de Read/Edit sí alcanzan a `cat`, `head`, `tail`, `sed`, `tee` y a las redirecciones, y no a `grep -r` ni a scripts. Corregido, con los límites que seguían sin declararse.
- **El registro de agentes decía «terminado sin informe» aunque el subagente hubiera entregado el suyo por `SubagentHandback` (B-01, prueba de v1.5.0 en Debian).** Al saltar `SubagentStop` el payload no trae `last_assistant_message` y el transcript del agente aún no contiene el `SubagentHandback` (3 de 3 agentes con `msg:""`; el `tool_response` del `Agent` en la sesión madre tampoco repite el informe). Un reintento en el hook añadiría esperas al camino caliente; en su lugar `nucleo_agentes_estado` relee el transcript ya completo cuando el Stop no guardó mensaje, así que «sin informe» solo queda si de verdad no hay. `handback_de` y `msg_de` pasan a `lib/agentes.sh`. Test: `carrera:` en `test_agentes.sh`.
- **`make test` salía rc=2 en un locale C/POSIX (A-01).** La sonda de falsabilidad de `M9–M40` usaba `.` para la raya (3 bytes en UTF-8) y en C casa 1 byte: no inyectaba nada. Ahora `M9[^M]{1,4}M40`, independiente de los bytes.
- **`handoff --desde` sin `--sesion` usa `$CLAUDE_CODE_SESSION_ID` (B-02).** La sesión dueña ya no sale con rc 5 por no repetir su propio ID. Test en `test_nucleo_integridad.sh`.
- **`session-start.sh` no dice «No project memory found» junto a la inyección de `nucleo.md` (B-05).**
- **`doctor.sh` distingue los agentes del kit de los personales (B-08):** «N, de ellos 1 ajeno(s) al kit: planner.md».
- **`05-security.md` publicaba cifras de `iocs.json` que no cuadraban (C-13).** Decía 31 patrones de ruta y 12 de comando; el fichero trae 21 de ruta (más 5 expresiones regulares y 6 extensiones de clave) y 21 de comando. `test_doc_claims.sh` las cuenta ahora con `jq`.
- **`05-security.md` decía que Sentinel falla abierto ante un error interno.** Desde `5259097` sale con código 2 y bloquea. La sección dice ahora qué falla cerrado y qué falla abierto (sin Python, sin `iocs.json` y el `timeout`), y cómo lo acota el `ask` por tamaño y por tiempo.
- **Guards, falso positivo de K1 con `curl -XGET`, `-XPOST` o `-XPUT` hacia `python3 -m json.tool` (F-01).** La excepción buscaba `-o/-O/-K/-T` en cualquier letra del cluster corto, y `-XPOST` lleva una `O` y una `T`. Ahora una opción corta que toma valor (`-X`, `-H`, `-d`…) se come el resto del cluster y el texto entre comillas (`--header "X-Token: ab -o cd"`) no cuenta como opciones, en `block-dangerous-commands.sh` y en Sentinel. Lo que se bloqueaba de verdad (`-o`, `-O`, `-K`, `-T`, `-d @fichero`) sigue igual; de paso, `-o/ruta` y `-o"ruta"` pegados, que no se veían, ahora también se bloquean.
- **`git config core.hooksPath ruta` pasa de bloqueo a confirmación (F-02).** Es el comando que `05-security.md` documenta para activar la Capa 2 de secretos y el flujo normal de husky/`.githooks`; negarlo dejaba a la compañera sin poder activarla desde Claude Code. Ahora pregunta, con un mensaje que explica el efecto y apunta a `install.sh --enable-secrets-layer2`. `git -c core.hooksPath=…` de una sola orden sigue bloqueado.
- **`git -c "core.hooksPath=…"` y `git -c 'alias.x=!sh'` entre comillas se bloquean (F-04).** La regla de C-06 miraba el texto con comillas y no veía `-c "core.hooksPath=/dev/null"`, `-c 'core.hooksPath=…'` ni `core.hooks"Path"`; ahora se aplica al texto sin comillas, como la de `--no-verify`.
- **Escribir en `~/.profile.bak` o `~/.bashrc.orig` ya no se bloquea (F-06, N-02).** El patrón de ficheros de arranque no tenía límite de palabra tras `profile`/`bashrc`; ahora el nombre ha de terminar ahí (comilla, espacio, `;`, `&`, `|`, `)`, `<`, `>`, `}` o fin). Los directorios `~/.bashrc.d/`, `~/.profile.d/` y `~/.zshrc.d/` (que el shell carga entero) siguen bloqueados en los dos guards. En Sentinel, `.bash_*` y `.zsh_*` (`.bash_logout`, `.bash_aliases`) y `.bash/`, `.zsh/` se siguen bloqueando como antes.
- **`gh api` destructivo ya no pide confirmación por texto (F-07, N-01).** La regla se ancla a un `gh api` real en posición de comando (inicio, tras `;`/`&`/`|`/`(`/`!`/`then`/`do`/`else`, dentro de `bash -c '…'`/`sh -c`/`eval`/`ssh host '…'`, y tras `sudo`, `env`, `VAR=x`, `time`, `nohup`, `nice`, `timeout N`, `watch`, `xargs`…) y `mutation` cuenta solo dentro de `-f/-F query=`. El cuerpo de un `gh pr create --body`, un `echo "gh api -X DELETE …" >> notas.md` o una ruta como `contents/mutation.md` ya no disparan `ask`; los `gh api` reales siguen pidiéndolo. Falso positivo aceptado: un `;`, `|` o `then` dentro del texto de un mensaje seguido de `gh api -X DELETE` sí pide confirmación (es un `ask`).
- **Sentinel bloquea `mv` y `rm -r` sobre `~/.claude` entero (F-05).** C-04 protegía `hooks/`, `sentinel/` y `settings*.json` pero no el directorio padre: `mv ~/.claude ~/.claude.old` se llevaba hooks y settings de una vez. Ahora `mv` (no como destino) y `rm -r`/`-rf`/`-R` sobre `~/.claude` se bloquean; los hijos legítimos (`projects/`, `plans/`) siguen libres. El resto de formas de llegar a la config (`cd`, variables, `xargs`, `tar -C`…) queda como límite declarado en `05-security.md`.
- **`block-dangerous-commands.sh` no sale con rc 1 sin `HOME` (F-09).** Con `set -u` y `HOME` sin definir moría con `HOME: unbound variable`; con `onFailure: "block"` eso bloqueaba `Bash` sin decidir. Ahora usa `${HOME:-/nonexistent}` y decide como siempre. Test en `test_guards.sh`: ningún guard de Bash sale con un código distinto de 0 y 2 sin `HOME`.
- **Sentinel ya no agota su `timeout` con un comando relleno (F-03).** `curl x | ((((…` de 65 KB tardaba 23 s (muy por debajo del tope de 128 KB) y `curl x | jq . |` repetido hasta el tope pasaba de 20 s; como Sentinel no lleva `onFailure`, el hook muerto por `timeout` dejaba ejecutar el comando entero y anulaba C-03 y C-04 (`; cat .env` al final pasaba). Sentinel se da ahora un presupuesto de 1,5 s de reloj para el análisis: si no cabe, responde `ask` —la misma decisión que ya aplica por encima del tope de tamaño— y nunca un allow. Con los payloads de la revisión, hasta 128 KB, responde en 1,6 s (antes: más de 20 s). Test de tiempo en `test_guards_falsifiability.sh` (mejor de hasta 3).
- **El watchdog de Sentinel no deja escapar `_OverBudget` (N-05).** `decide_within_budget` anida `try/finally` para que una alarma que cae entre el final del cuerpo y `setitimer(0)` acabe en `ask` y no en un traceback (rc 1, que no bloquea). Sin test determinista: la ventana es de microsegundos.

### Added

- `make test` termina con un bloque «verde, pero con capas SALTADAS» cuando una suite se salta algo (sin `gitleaks`, sin `claude` en el PATH, sin `kit/evals/runs.jsonl`). Las suites anotan en `SCC_SKIP_LOG`; el rc no cambia (A-03).

### Documentación

- Duración real de `make test` (A-04), `cupo` y el paso opcional de claves del instalador (A-05), el marketplace que fija `install.sh` (A-06), `marketplace add` reescribe `model` a `opus[1m]` (A-07), el árbol de `--plan` no se borra solo (A-08), el mensaje «directory denied» sobre un fichero (B-04), por qué un `.env` sin ignorar sale en «Ficheros tocados» y se deja (B-06), el `ref` del marketplace es una etiqueta mutable y no admite `sha` (C-10), `effortLevel` de primer nivel no rige Opus 5.5 y posteriores según la doc oficial (C-11).

### Lista v1.6 (no entra en un PATCH)

- curl: opciones con comillas dentro del nombre (`"-o"`, `'-T'`, `-"o"`, `--"output"`, `-s"o"`, `-$'o'`) siguen pasando la excepción K1 de `curl | jq` (N-03). Cerrarlo exige expandir el shell.
- `gh api graphql -f query='query{x}' -f mutation=1` pide confirmación; `git -c core.hooks\Path=…` pasa; `git commit -m "… git -c core.hooksPath"` y `echo "git -c core.hooksPath=x" > notas.md` se bloquean (N-04).
- Registrar el informe de `SubagentHandback` con un hook `PostToolUse` (matcher `SubagentHandback`, `tool_input.message`, `agent_id` para correlar) en vez de leer el transcript (C-05). Es la vía que documenta Claude Code y no tiene carrera ni ventana de 30 líneas, pero cambia el mecanismo de K4 ya verificado en vivo y toca `settings.json`.
- `effortLevel` por modelo (`modelSettings`) en la plantilla, si `/status` confirma que el de primer nivel es inerte con el alias `opus` (C-11).
- `source:"fork"` en el matcher de `SessionStart` (C-14): la sesión forkeada hereda el transcript con la inyección ya hecha, así que no urge.
- Los guards leen el literal del comando, no el argv que el shell expandirá: `cur''l`, `b""ash`, `/bin/b*sh`, `S=bash; … | $S`, `rm -"rf"` y `F=-rf; rm $F` solo los cubriría un guard que ejecute la expansión en un shell de prueba o el sandbox del sistema operativo.
- Escrituras desde código en línea (`python -c`, `node -e`) sobre la config del kit, `shutil.rmtree` y `rsync --delete`: ninguna regex las ve; hace falta el sandbox.
- git: comodines en `git push` (`ma*`, `refs/heads/*:refs/heads/*`), `xargs git push`, `HUSKY=0`, `git config alias.*` y `GIT_CONFIG_*`.
- `secret-guard.sh` solo mira `git add`; el resto de lecturas de `.env` las cubre Sentinel, que es opcional (necesita Python).
- Un solo núcleo para los dos guards (hoy `block-dangerous-commands.sh` y `iocs.json` repiten los patrones a mano y los tests los cruzan).
- Límites de los guards que la revisión de v1.5.1 encontró y que no se cierran en un PATCH (declarados en `05-security.md`): la config del kit desde `Bash` por `cd`/`pushd`, variables, sustituciones, `xargs`, `tar -C`, `unzip -d`, `vim -es`, `awk -i inplace` y el `.claude/settings.local.json` del proyecto (F-05); `gh api` con `state="closed"` entre comillas, `merges`, mutaciones desde fichero y `gh repo archive`/`release delete`/`secret set` (F-08); las diferencias entre `block-dangerous-commands.sh` y Sentinel fuera de las formas citadas (F-10).
- Ampliar la regla de `git -c` a lo que ejecuta código como `alias.`: `core.pager`, `core.sshCommand`, `core.fsmonitor`, `core.editor` y `credential.helper=!…` (F-11). Se deja para v1.6 porque `core.pager=cat` y `-c credential.helper=` vacío son usos legítimos que hay que separar antes de bloquear.
- Anclas de `gh api` que siguen sin preguntar, sin regresión (M-02): `find -exec`, `parallel`, `su -c`, `script -qc`, `docker run` y `case`. Una palabra `then`, `do` o `ssh host` dentro de un texto pide confirmación (M-01, falso positivo aceptado). Tampoco se protegen `.zprofile.d/`, `.zshenv.d/` ni las escrituras con `cp`, `mv`, `ln -s` o `sed -i` hacia `~/.bashrc.d/` (M-03).

## [1.5.0] - 2026-10-24

Arreglos K1-K13 del A/B «¿aporta scc?» (23-oct): lo que estorbaba en sesiones autónomas reales.

### Added

- `cupo` (`kit/claude/bin/cupo`): comprobación previa a una sesión autónoma larga. Un turno mínimo lee `rate_limit_event` y sale 1 si algún cupo está en `rejected` o por encima del umbral (80 % por defecto), y 2 si no hay veredicto. No lee credenciales (K2).
- `doctor.sh` avisa si `CLAUDE_CONFIG_DIR` está definida pero vacía (K10).
- Un test compara el número de suites que dicen los documentos con el real (K13).

### Changed

- Guards: una excepción estrecha al bloqueo de descarga por tubería (`curl`/`wget`). Pasa si va hacia `python -c` con flags simples y un código que solo nombra, fuera de sus cadenas, lo necesario para leer e imprimir JSON. Es una lista blanca, no negra: `exec`, `pdb`, `sys._getframe`, los identificadores no ASCII y la expansión del shell entre comillas dobles quedan fuera, o hacia `jq` o `python -m json.tool` exactos. Todo lo demás decide igual que en v1.4.1, y los mensajes de bloqueo dicen la alternativa (descargar a fichero; escribir texto con la herramienta Write). `block-dangerous-commands.sh` y Sentinel coinciden en toda la excepción. Lo comprueba el corpus de 782 comandos de la revisión adversaria: ninguna regresión respecto a v1.4.1 aparte de las tres relajaciones buscadas (K1).
- En sesiones desatendidas (`CLAUDE_CODE_SESSION_ATTENDED=0` o `CLAUDE_CODE_ENTRYPOINT=sdk-cli`) los avisos de contexto ya no piden «cierra el turno», `/handoff` ni la tecla `h`: piden actualizar `nucleo.md` y seguir (K3).
- La inyección de `nucleo.md` sale sin los comentarios `<!-- -->` de la plantilla. En `-p`, el encuadre de «Siguiente acción» pasa de «no se ejecuta hasta que la persona confirme» a «síguelo solo si encaja con el encargo de esta sesión» (K8).
- `handoff --desde` genera el bloque de «Ficheros tocados» desde git y conserva debajo lo escrito a mano (K9).

### Fixed

- `nucleo.md` con la plantilla vacía inyecta un aviso corto en vez de 0 B (K5).
- El registro de agentes distingue «terminado» de «terminado sin informe»: lee el informe de `SubagentHandback`, después `last_assistant_message` y, si faltan, el último texto del transcript (K4).
- `write-guard` deja de avisar a los subagentes de que deleguen el fichero grande (K7).
- El aviso del airbag mide desde la primera herramienta aunque el último `assistant` esté a más de 40 líneas del final del transcript (K12).

### Docs

- Sesiones autónomas: `cupo`, guardar `terminal_reason` y `api_error_status`, `--permission-mode auto` (con `acceptEdits` no se escribe `.claude/estado/`) y la trampa de `pgrep -f` dentro de `bash -c` (K2, K11). La ventana de 250 K se queda, con su porqué y cómo cambiarla en una sola ejecución (K6). Login por cada config dir con `claude auth login --email` (K10).

## [1.4.1] - 2026-10-22

Auditoría de prompts aplicada a los agentes del kit (`planner` se retira: duplicaba a `strategist`) y suites de contexto que ya no dependen de lo largo que sea `TMPDIR`.

### Changed

- Agentes: `strategist` devuelve sus preguntas de aclaración como salida (un subagente no puede hablar con la persona) y absorbe el paso de verificación de `planner`; `security-reviewer` remite a la regla de secretos de las reglas comunes y sustituye «alertar al dueño» por informar primero; `orchestrator` deja el tono «relentless» y descompone solo por independencia; `code-explorer` acota cuándo usarlo frente a `Explore`; `deep-worker` pierde una lista de prohibiciones repetida.

### Removed

- Agente `planner`: duplicaba a `strategist`. Los agentes del kit pasan de 8 a 7.

### Upgrade

- En instalaciones previas, `~/.claude/agents/planner.md` queda huérfano (el instalador no borra) y puede eliminarse; `doctor.sh` no lo echa en falta.

### Fixed

- Tests independientes de la longitud de `TMPDIR`: `test_nucleo_lib`, `test_nucleo_nudge` y `test_presupuesto_contexto` fallaban con un `TMPDIR` largo porque sus fixtures asumían un `mktemp` corto (el aviso del nudge cita la ruta y el índice tiene un tope de 2 500 caracteres). Defecto de las pruebas, no del producto.

## [1.4.0] - 2026-10-22

Que un compañero instale el kit en limpio (WSL2 Ubuntu) y tenga el estado v3 operativo desde la
primera sesión: `install.sh` deja `handoff` y `oraculo` en el PATH, `doctor.sh` comprueba que
están, `handoff --iniciar` crea el primer `nucleo.md` y `10-onboarding.md` es la guía del primer
día. Además, los guards de refspec forzado y de `find -delete` se deciden sobre tokens,
`branch-guard.sh` deja de fallar en abierto con comandos largos y el `settings.json` del kit pasa a
ser techo también sin política gestionada.

### Added

- Estado por sesión en `~`: el handoff del cockpit (`/handoff`, `/nueva` y la banda del dock) usa la ranura `~/.claude/estado/sesiones/<fecha>-<pid>/` de la sesión cuando no hay proyecto, vía `handoff --estado` y `--desde` sin `--raiz` (ADR 019).
- Consolidación local identificada por `BUILD_ID`: cockpit 0.6.1, lanzador `scripts/scc.sh` y guía `ENTREGA.md`. `/autonomo on|off` continúa el encargo autorizado tras confirmar un handoff, también desde HOME; conserva misión y pasos, y se desactiva al cambiar de tarea.
- `install.sh` enlaza `handoff` y `oraculo` en `~/.local/bin` (solo sobre hueco libre o enlace propio; nunca pisa uno ajeno), avisa si `~/.local/bin` no está en el PATH y, con un `CLAUDE.md` previo sin `@AGENTS.md`, termina con un aviso visible (plantilla en `CLAUDE.kit.md`). En diff-first lo pone en el plan sin escribir. El aviso de credenciales solo sale si la plantilla existe.
- `doctor.sh`: FAIL si falta `bin/handoff`, `bin/oraculo` o `templates/nucleo.md`; WARN si no se resuelven en el PATH o si `CLAUDE.md` no importa `AGENTS.md`.
- `handoff --iniciar [--raiz D]` crea el primer `nucleo.md` desde la plantilla (nunca sobrescribe; exit 3 sin proyecto).
- Registro de agentes (ADR 017): `SubagentStart`, `SubagentStop` y `SessionEnd` llaman a `agentes.sh`, que anota en `estado/agentes.jsonl` y lo rota a 200 líneas o 14 días. El `nucleo.md` inyectado lista los agentes con su `RESULTADO.md`, y con agentes en vuelo el aviso de contexto (`stop-context-gauge.sh`) pide `/handoff solo`, no `/clear`.
- Estado con una sola puerta de escritura (ADR 016): `nucleo_estado_dir` decide dónde se escribe, con fallback a `~/.claude/estado/<nombre>-<hash>`, y `handoff --informe TEMA` crea `<raíz>/.claude/estado/informes/AAAA-MM-DD-TEMA/` para los informes.
- Aviso de edad tras compactar: `session-start-compact.sh` avisa una vez por versión del `nucleo.md` (solo a la sesión dueña) de que el estado reinyectado puede estar rancio.
- `doctor.sh`: WARN con `env.CC_ALLOW_DESTRUCTIVE=1` (apaga `destructive-guard.sh`), con `claude` ausente o anterior a 2.1.292, con `.claude/estado/` sin ignorar y con ficheros sueltos, y con `informes/` por encima de `DOCTOR_INFORMES_MB` (50 por omisión).
- `make bateria` (test, shellcheck, scan-secrets y gitleaks con un `.rc` y un `.log` cada uno), `scripts/contexto-base.sh` y `test_presupuesto_contexto.sh`, que fija el tope de contexto por canal (ADR 018).

### Changed

- Plantilla `settings.json` genérica: `model` pasa a `"opus"` (Opus 4.7+ trae 1M sin sufijo), `allow` queda en `Bash(uv tool list)`, se retiran `codex`, `understand-anything` y `frontend-design` con sus marketplaces, y se registra `setup-claude-code` para que `esenciales` no quede colgado.
- `AGENTS.md` instalado: la mención a `recuerda` pasa a condicional (el instalador no lo instala).
- `templates/nucleo.md`: el comentario de cabecera pasa dentro de «Objetivo» y el orden de secciones coincide con el que `handoff` escribe.
- Plantilla `settings.json`: `"tui": "fullscreen"` por defecto, junto al tema oscuro; al reinstalar se conservan el tema y el renderer que ya tuvieras.
- El marketplace del kit queda fijado al tag `v<VERSION>` en vez de seguir `main`, y al fusionar con una instalación previa gana la entrada del kit.

### Fixed

- Inyección tras `/handoff` y `/clear`: un `nucleo.md` dentro del tope (`NUCLEO_TOPE`) se inyecta entero. Antes, «Paso actual», «Siguiente acción» y «Comandos de verificación» se cortaban a 700 B aunque el total cupiera, y lo que `handoff` daba por bueno llegaba recortado. Por encima del tope se omiten secciones enteras en el orden de `handoff` (Pendientes, Plan, Ficheros tocados), con aviso y `[LEE …]`; el reparto por sección queda solo para cuando ni así cabe. El aviso de contexto (`nucleo-nudge.sh`) da el tamaño cuando un `nucleo.md` editado a mano pasa del tope.
- Propiedad del estado: un `clear` ajeno no roba una sesión vigente; bloqueo de escrituras, recibo SHA-256 y archivo condicionado al hash. `SessionEnd` libera solo el dueño propio. Un proceso vivo no pierde propiedad por antigüedad.
- Agentes: eventos por sesión y contexto acotado; una tarea hermana no se trata como descendiente pendiente de un agente ya terminado.
- Cockpit: ruta canónica del CLI en el prompt HOME, progreso desconocido si faltan datos y advertencias visibles sin limpiar ante errores. La continuación no se reenvía si su resultado es ambiguo.
- Handoff: presupuesto UTF-8 antes de guardar, con reserva para objetivo e invariantes y una sola regeneración compacta si el borrador excede el espacio disponible. Evita que resúmenes redundantes frenen la continuidad; si no cabe, conserva el contexto sin escribir.
- Prueba de propiedad: comprueba el aviso completo, sin contar apariciones accidentales del identificador de sesión en las rutas temporales.
- Guards: parser con carga por bloque y reutilización del último segmento validado en el mismo cwd. La prueba mide tiempo monotónico y CPU por separado, conservando los límites de rendimiento.
- Instalación: protege wrappers ajenos enlazados; doctor detecta bibliotecas ausentes y deriva de CLI y plantillas, además de hooks.

- `pre-compact.sh`: si el transcript declarado falta, no se puede leer o no tiene ninguna línea JSON (o jq falla), no se publica checkpoint y se conserva el anterior (`pipefail`); una línea final a medias se descarta y se conservan los mensajes válidos. Acepta también los mensajes de Codex (`event_msg/user_message`).
- La plantilla `nucleo.md` pegada tal cual como borrador de `handoff --desde` ya no da rc 2.
- Tests: las suites que instalan usan `HOME` falso para no enlazar en el `~/.local/bin` real; la etiqueta de `test_session_start_clear.sh` indica el tope real (9 500).
- `handoff --desde` ya no duplica «Objetivo» ni «Invariantes» cuando la sección del nucleo y la del borrador son solo comentario (el nucleo recién iniciado pegado como borrador crecía una cabecera en cada fusión).
- `pre-compact.sh`: un registro JSON válido con `message`, `payload` o un elemento de `content` que no es objeto se salta en vez de abortar jq y perder el checkpoint entero.
- `pre-compact.sh`: sin checkpoint previo, el aviso de fallo (transcript ausente o publicación fallida) dice que no había ninguno en vez de «anterior conservado».
- `install.sh` solo enlaza `handoff` y `oraculo` en `~/.local/bin` si `CLAUDE_HOME` resuelve a `$HOME/.claude`; con otro (prueba, CI) imprime las órdenes `ln -s` y no escribe, para no dejar enlaces colgantes en el bin real. El plan diff-first deja de prometer los enlaces en ese caso, y el aviso final de PATH ya no da los CLIs por enlazados: dice que el PATH solo hace falta si se crean esos enlaces, o que se use `$CLAUDE_HOME/bin/<nombre>`.
- `doctor.sh`: un `handoff` u `oraculo` del PATH cuyo `readlink -f` no es el de `$CLAUDE_HOME/bin/<cli>` da WARN con su ruta (antes PASS); las sugerencias usan `ln -s`, nunca `ln -sf`.
- `doctor.sh` y `.github/scripts/assert-install.sh` comprueban el inventario completo y recursivo de `kit/claude` y `kit/sentinel`: FAIL si falta un fichero (skills, `AGENTS.md`) o un ejecutable pierde el permiso, WARN si su contenido difiere; un symlink propio cuenta como presente y `sentinel/iocs.json` sigue siendo opcional.
- `scripts/backup.sh` nombra el ZIP con sello UTC, PID y aleatorio: dos backups en el mismo segundo (el previo de `uninstall.sh --apply` y el que acabas de crear) ya no colisionan ni abortan.
- `doctor.sh`: `settings.json`, `CLAUDE.md` y `AGENTS.md` ya no cuentan como deriva (`install.sh` fusiona el primero y no pisa los otros dos), así que una instalación con los tuyos no arrastra un WARN permanente; si falta alguno sigue siendo FAIL.
- Tests: los dos casos H3 de tiempo (`test_nucleo_lib.sh`, `test_session_start_clear.sh`) pasan de 2,5 s a 4 s; en WSL2 midieron 1,6-2,8 s y el tope anterior tumbaba `make test` sin defecto.
- Primer prompt tras `/handoff` + `/clear`. El relleno ya no corta la Siguiente acción a 200 caracteres a mitad de palabra, de ruta o de code span. Ahora corta en una frase o en un espacio, cierra la comilla y termina en «… (sigue en <ruta>)»; también avisa cuando hay más líneas debajo. `HANDOFF_PROMPT` y la plantilla piden que la primera línea, de 160 caracteres como máximo, sea la acción con su condición, nunca «pedir el sí», porque es lo que la persona aprueba al pulsar Enter. Si la relectura falla después de guardar, ya no se informa «Handoff fallido».
- `handoff` e inyección:
  - Lo que `handoff` guarda cabe entero junto al bloque de agentes: escribe como mucho `NUCLEO_TOPE − NUCLEO_RESERVA_AGENTES` (5 700 B), y el cockpit y el aviso de tamaño usan ese mismo tope.
  - Siguiente acción no se omite nunca. Paso actual se recorta por línea en vez de quitarse, y el original va a `diario.md`.
  - Al cortar una sección se respeta el límite de línea y se cierra su valla.
  - El checkpoint de compact ya no parte caracteres UTF-8.
- Hooks: un `nucleo.md` vacío o con solo la plantilla ya no anuncia «Hay trabajo en curso». `nucleo_estado_seguro` rechaza una ruta relativa en lugar de entrar en un bucle infinito.
- `install.sh` valida sus argumentos antes de tocar nada, y crea los enlaces por ruta canónica sin pisar los existentes.

### Security

- Guards: el refspec forzado de `git push` (`+main`, `+HEAD:main`, `+refs/heads/master`, `+feature`) se bloquea como el resto de force-push. Se decide sobre tokens de `git push`: cae también entre comillas, con ANSI-C o con variable (`'+feature'`, `"+HEAD"`, `$'+feature'`, `+$B`, `+${B}`, `+$(…)`) y dentro de `bash -c`, y no da falso positivo en `git stash push -m "wip +login"`, mensajes de commit, `git log --grep "push +1"` ni el argumento de `-o`. Casos rojos primero en `test_guards_falsifiability.sh`, con negativos legítimos.
- Guards: `find … -delete` se decide sobre tokens y por familia de ruta. El directorio actual (`.`, `./`, `./.`, `*`, `./*`, sin ruta; también tras `-L`/`-H`/`--` o entre comillas) se bloquea salvo que un filtro por nombre o ruta acote el borrado: va antes de cada `-delete` y la expresión no lleva `-o`, `-or`, `,`, `!`, `-not` ni `-prune` (`find . -name '*.pyc' -delete` pasa; `-name '*'` no cuenta como filtro). Una ruta con glob o llaves (`.*`, `?*`, `[!.]*`, `{a,b}`) cuenta como el directorio actual. Una ruta amplia (`..` y lo que sube de él, `~`, `$HOME`, `/`, `/*`, `/etc`, todo `/home/…` y `/mnt/…`) se bloquea siempre. `build` o `/tmp/x` pasan. Citarlo en `echo`, `grep` o un mensaje de commit ya no bloquea.
- Guards: las cadenas anidadas que `block-dangerous-commands.sh`, `destructive-guard.sh` y `branch-guard.sh` vuelven a analizar llevan un tope (más de 3 niveles de `bash -c`/`sh -c` o 16 comandos); pasado el tope se deniega, en vez de dejar pasar el nivel que ya no se analiza. `branch-guard.sh` solo mira los segmentos con `push` (y los `cd`), y calcula la rama actual una vez por repo (deniega pasados 16 repos distintos): antes, 12 KB de `x git;` costaban 7 s de CPU, 128 KB pasaban de 20 s y 12000 segmentos `git push` (108 KB) 36 s, con un timeout de 10 s y sin envoltorio, así que el guard fallaba en abierto. Ahora son 0,06 s, 0,4 s y menos de 2 s.
- Guards: el texto de `echo`/`printf` que va a `| bash`/`| sh`, el código de `python -c` que llama a `os.system`/`subprocess` y `find … | xargs rm` se analizan como la orden en los tres guards. Escribir la orden a un fichero y ejecutarlo después queda fuera de alcance (`kit/docs/05-security.md`).
- `branch-guard.sh`: una redirección pegada al operando (`git push origin main>/dev/null`) o la rama en ANSI-C (`$'main'`) ya no ocultan la rama protegida.
- `settings.json` del kit: `disableBypassPermissionsMode: "disable"` y seis deny de `Read` y seis de `Edit` (`~/.ssh`, `~/.aws`, `~/.gnupg`, `~/.netrc`, `.env*`, `secrets.*`), para que el kit sea techo también sin política gestionada.
- Fusión de `settings.json`: `permissions.disableBypassPermissionsMode` queda en `"disable"` siempre (gana el kit, y se dice si tu valor era otro). Un `disableAllHooks: true` o un `permissions.defaultMode: "bypassPermissions"` previos se respetan, pero `install.sh` avisa al final, también en el plan diff-first; `doctor.sh` da FAIL con `disableAllHooks: true`.

### Documentation

- **Guía del primer día para un compañero.** `kit/docs/10-onboarding.md` pasa a ser la guía genérica (WSL2 Ubuntu): prerrequisitos con `apt`, `bash kit/install.sh`, `doctor.sh`, primer proyecto con `git init` + `handoff --iniciar`, bucle diario `oraculo --` → `/handoff` o `handoff --desde` → `/clear` y tabla de fallos. `make bootstrap` deja de ser la vía de quien solo usa el kit.
- `02-install.md` documenta los enlaces de `handoff` y `oraculo` en `~/.local/bin`, el aviso de `@AGENTS.md` con un `CLAUDE.md` previo, las comprobaciones nuevas de `doctor.sh`, que la fusión de `settings.json` sustituye los hooks propios por los del kit (con backup) y que el modelo se fija con `"model": "opus"` (sin `[1m]` en Opus 4.7+).
- `11-cockpit.md`: instalación, versión probada de Claude Code (2.1.292, sin mínimo comprobado), fijado al tag de la versión, y `/handoff solo` frente a `handoff --solo`. La ruta de 7 días pasa a la plantilla de `nucleo.md` de v3 y a `handoff --desde`.
- ADR 004 (sustituida en parte), 007 (no implementada) y 011 (issues sin re-verificar) con su estado real.
- ADR nuevos: 016 (dónde se escribe cada cosa), 017 (registro de agentes), 018 (presupuesto de contexto) y 019 (sesiones en HOME).
- `ENTREGA.md`, `README.md` y `kit/docs/{02-install,06-routine,08-plugins-mcp-y-skills,10-onboarding,11-cockpit}.md` se alinean con la instalación real: requisitos (Python 3, `zip`, `unzip`), verificación SHA-256 del paquete, qué trae la base frente a lo opcional, vuelta atrás con `uninstall.sh` en dry-run, rechazo de escritura con código 5 si otra sesión reclama el estado y vuelta al renderer clásico con `/tui default`.

## [1.3.0] - 2026-10-19

Dos frentes. El primero, **que el estado de una tarea sobreviva a la compactación sin depender de
que el modelo se acuerde**: el cockpit lanza el handoff solo, entre turnos (ADR 013), y el estado
pasa a vivir por raíz git, con una sesión dueña, escrito por dos CLIs del kit, `handoff` y `oraculo`,
que validan, fusionan y anotan el rc real (ADR 014). El segundo, **cerrar guards que fallaban en
abierto**: un comando de 64 KB hacía que los guards de Bash se pasaran de su timeout y la herramienta
se ejecutara; se cierran los hallazgos de la revisión del 16-oct sobre instalador, normalización de
comandos, Sentinel, estado y write-guard; entra `bash-write-guard.sh`, que mira lo que Bash escribe,
y sale `smart_approve.py`, que fallaba en abierto sin `settings.json`.

### Added

- **Estado v3: núcleo y CLI.** `nucleo_raiz` ya no toma por proyecto un directorio sin git, `$HOME` ni `~/.claude`: imprime `$HOME` y sale con rc 1. `NUCLEO_TOPE` (6500) vive solo en `lib/nucleo.sh`. Una tarea = una sesión dueña (`.claude/estado/.dueno`, TTL 4 h, `NUCLEO_DUENO_TTL`): SessionStart la reclama o avisa a la ajena, y el nudge de contexto calla a quien no es dueña y al 70 % remite a `handoff`. La emisión sigue el orden D5, omite los `[x]` del Plan y deja `recortes.log`. Plantilla `nucleo.md` en orden D5, sin cifras, con correcciones fechadas, rangos de ficheros y `→ rc=N`.
- **Nuevos CLIs `bin/oraculo` y `bin/handoff`** (bash + jq; `install.sh` los copia a `$CLAUDE_HOME/bin/` y imprime el enlace a `~/.local/bin`). `oraculo -- <cmd>` corre con `pipefail`, imprime las últimas 40 líneas y `rc=N`, y anota en `verificaciones.log`. `handoff --desde` valida el borrador contra la plantilla, conserva Objetivo, une las Invariantes por líneas, mueve los `[x]` a `diario.md` con comando y hash, pliega el rc, rota 3 copias y recorta al tope omitiendo secciones enteras; `--solo`, `--commit`, `--migrar`, `--estado`. Exit 0/2/3/4.
- **cockpit 0.5.0**: `/handoff` y el handoff automático delegan la fusión en `~/.claude/bin/handoff --desde` (el fork solo redacta el borrador, con los campos de la decisión 13; borrador en fichero temporal 600). Exit 2/3/4 con mensajes claros y un reintento en el 4; sin binario, aviso con la orden de instalación y sin fusión de reserva. Fuera `mergeNucleo`, `keepCopies`, `excludeState` y la tabla de alias. Raíz según la decisión 6 (`$HOME`, `$HOME/.claude/**` y fuera de git no son proyecto). El dock muestra dueño y % del tope leyendo `handoff --estado`. Tests: 89 (antes 82); `test_mod_cockpit.sh` comprueba que no quedan funciones de fusión en TS.
- La plantilla pública `CLAUDE.md` cita `oraculo -- <cmd>` (rc real), el cambio mínimo por parche y `handoff` como parada de fin de fase al 70 %; `deep-change` aclara que una rama nunca aísla configuración viva y que cada `[x]` cerrado va a diario con su comando y hash. `test_claude_md_template.sh` fija cada frase.
- Nuevo `bash-write-guard.sh` (PreToolUse Bash, timeout 5): deniega secretos en heredoc, `>`, `>>`, `tee` y `sed -i`; salida en bash puro si el comando no escribe; 64 KB < 1 s.
- Lista única de patrones de secreto en `hooks/lib/secret-patterns` (TSV), compartida con `write-guard.py` (que falla cerrado sin ella); test de paridad Python re / grep -E.
- `block-dangerous-commands.sh`: ask para `gh pr|issue close|merge` y `sudo apt|apt-get|dnf|pip`; `--no-verify` sigue en deny.
- Sentinel: `~/.aws/` protegido como directorio; `secrets.token_hex` pasa (fijado). El falso positivo de lectura de config no se reprodujo: sin cambio de lógica.
- Nuevo `scripts/guards-cpu.sh` (p50/p95 de CPU de la cadena Bash): antes p95 205 ms, después 222 ms (p50 176 -> 163).
- **Corpus adversario de E5 como suite: `test_guards_corpus.sh`.** El corpus de la campaña
  E5 (`fixtures/guards-corpus.tsv`, una columna de esperado y otra del guard que respondió) tiene
  715 filas; 119 se ejecutan contra los cuatro guards bash en un repo temporal en rama de feature
  (336 aserciones, 0 falsos negativos). Las otras 596 se omiten con motivo contado: 110 de otras
  herramientas, 483 que solo vieron Sentinel o smart_approve (Sentinel y write-guard se cubren en
  `test_guards.sh`) y 3 sin expectativa. Los guards de antes de este cambio también la
  pasan: es una red contra regresiones, no el test rojo de los hallazgos (eso es `test_guards.sh`).
  Los 3 «falsos positivos» del corpus son el borrado recursivo forzado de `build/`, que el hook
  deniega por diseño documentado, y la suite los fija como `BLOCK` (`DISENO_FP=allow` los cambia
  si se decide lo contrario). Suma la suite 41 a Makefile, `ci.yml` y las cifras de la doc.

- **Handoff automático y `/nueva` en cockpit 0.4.0.** Al cerrar un turno del bucle principal
  con el contexto por encima del umbral (70 % del límite de autocompactación por defecto;
  `COCKPIT_AUTO_HANDOFF=off` lo desactiva, un entero 50-95 lo cambia), el mod guarda el estado
  con el handoff de siempre, hace `/clear` y deja «sigue…» escrito en el prompt, sin enviarlo.
  Si la autocompactación salta a mitad de turno, la pospone hasta un techo (1,5 × el límite,
  nunca más de media ventana real del modelo) para que el handoff llegue al cerrar el turno;
  pasado el techo, o en subagentes, compacta como siempre. `/nueva <tarea>` archiva el
  `nucleo.md` de la tarea actual en `.claude/estado/archivo/`, limpia y deja la tarea nueva en
  el prompt. Solo actúa donde el estado es de la tarea: un repo que no es `$HOME`; con
  subagentes vivos o si empieza otro turno entre el guardado y el `/clear`, no limpia. El veto
  cede si la lectura del contexto falla o si el handoff quedó en error, y `/nueva` no corre
  con un turno o un handoff en marcha. 21 tests nuevos en `tests/handoff.test.tsx`. La capa
  de Claude Code (`kit/claude/CLAUDE.md`) declara el fin de fase al 70 % como excepción a
  Never-Stop y `/nueva` como cambio de tarea.

- **Herramientas de medida y memoria en `scripts/`**: `compact-audit.py` (compactaciones:
  manuales frente a automáticas, duración, lo destruido) y `nucleo_audit.py` (si
  `nucleo.md` se escribe antes de compactar y se relee después) leen `$CLAUDE_PROJECTS_DIR`;
  `recuerda` (`recall.py`) devuelve solo los párrafos de memoria que coinciden y lee
  `$CLAUDE_MEMORY_DIR`. `kit/docs/13-memoria.md` fija el formato de una memoria, el índice
  corto y que las memorias nunca salen a un servicio externo.
- **Guía para trabajar bien tras instalar** (`kit/docs/guia/`): ruta de 7 días con una
  comprobación por día, el porqué del contexto con cifras medidas, una sesión real con las
  salidas literales de los hooks, antipatrones, cómo medirse, qué borrar de la plantilla y una
  ruta corta en inglés. `05-security.md` gana la tabla «hook → incidente que evita».
  `test_guia.sh` exige que existan, que `01-overview.md` los enlace y que ningún enlace
  relativo esté roto; `test_doc_claims.sh` juzga también sus cifras.
- **Tema oscuro y statusline del kit.** `kit/claude/settings.json` pasa de `light-ansi` a
  `dark` y declara `statusLine` con `bash $HOME/.claude/statusline-command.sh`, que `install.sh`
  copia y deja ejecutable: dos líneas en bash + `jq` (modelo, ruta, repo, rama y cambios;
  contexto y límites 5h/7d), se parte por los `|` según el ancho del TTY sin recortar nada.
  Sustituye a ccstatusline (~300 ms por refresco, node y un bundle de 3,3 MB). La fusión de
  `settings.json` no cambia: quien ya tenía `theme` o `statusLine` conserva los suyos. Sensor
  nuevo `test_statusline.sh` (26 casos) y `doctor` exige PASS de la barra en una instalación limpia.
- **Agent Dock y handoff con controles sin letra ni cromo (cockpit 0.3.4).** `Equipo` sube
  bajo la cabecera, antes de la misión; la misión se titula `Misión:` y `▸ más` ya no dibuja
  la tecla `m` como `m:` (se pulsa con un clic o Enter bajo el foco). Los tres botones de
  handoff pasan a `plain` con los corchetes en la etiqueta (`[solo guardar]`): el cromo
  `[ solo guardar ]` lo dibuja el motor y un mod no puede estrecharlo, y `plain` con tecla
  dibujaría `g: …`, así que las teclas `y`/`g`/`n` desaparecen. La línea «N% until
  auto-compact» que sale bajo el prompt es una notificación del propio Claude Code
  (`token-warning`), no del mod: no hay componente de `ui.render` que la cubra.
- **CI: shellcheck fijado a 0.11.0 con checksum, como gitleaks.** El `shellcheck` de `apt`
  del runner (0.10) seguía emitiendo `SC2002` (*useless cat*), que la 0.11 local ya no
  reporta por defecto: la PR #37 cayó en rojo por un `cat` inútil en
  `test_plugin_esenciales.sh` con el árbol limpio en local. Se corrige la línea y `ci.yml`
  descarga la versión fijada en `SHELLCHECK_VERSION`, de modo que local y CI ven lo mismo
  (CONTRIBUTING lo documenta).
- **Agent Dock: una herramienta larga ya no es un atasco (cockpit 0.3.3).** El dock medía
  «sin actividad» desde el inicio de la última llamada a herramienta y no sabía que seguía en
  marcha: un agente dentro de un `make test` de 4 min pasaba a `Parados` a los 2 y, con el
  turno principal ya terminado, la cabecera caía a `IDLE`. Ahora una llamada en vuelo cuenta
  como actividad hasta que vuelve. Los estados `waiting` (aprobación de un plan, tarea en
  segundo plano) e `idle` (teammate entre turnos) de la API, que el dock no conocía, siguen
  en `Trabajando` con su motivo y fuera del reloj de atasco. Dos tests nuevos.
- **Agent Dock sin cortes y con la actividad de cada agente (cockpit 0.3.2).** `Hechos` ya no
  se queda en los 8 últimos con `… y N más`, ni el estado en los 40 últimos agentes (eso
  renumeraba los `T<n>`): se dibujan todos y el pane hace scroll. La segunda línea de un agente
  que trabaja (su última herramienta) ya no la pisa el sondeo de 1,5 s, que escribía filas
  leídas antes de un `tool.call`; y de una ruta enseña la cola (`checkout/precio.ts`), no la raíz.
- **Agent Dock legible en un pane estrecho (cockpit 0.3.1).** La misión nace plegada en una
  sola línea con `…` (antes dos), así que los agentes suben al principio del pane. El tiempo
  de cada agente, el de la misión y el de «sin actividad» llevan unidades (`45s`, `10m42s`,
  `1h05m`, como mucho 6 celdas por debajo de 100 h): el `10:42` a secas se leía como una hora,
  y en un pane estrecho se partía en `10:` / `42`. El prefijo y el tiempo de cada fila ya no
  se encogen; solo cede la descripción. La versión sube para que `/plugin update` traiga el
  código nuevo: con la misma versión, la caché seguía sirviendo el dock anterior.
- **Agent Dock v3 (cockpit 0.3.0): misión en dos líneas y agentes por secciones.** La misión
  muestra siempre sus dos primeras líneas (envueltas a mano al ancho del pane) y el botón
  `▸ más` / `▾ menos` (tecla `m` con el pane enfocado) despliega el resto. Antes el clic
  "no hacía nada": el texto vivía dentro del `Button`, que no acota a su hijo, y la misión
  desplegada salía en una sola línea cortada por el borde. Los subagentes van ahora a una
  columna a cualquier ancho, en cuatro secciones fijas con su cuenta (`Trabajando`,
  `En cola`, `Parados`, `Hechos`), una línea por agente y otra de actividad para los vivos.
  Fuera las dos columnas, la regleta de color, las chips rotativas y la barra con contador
  `Nh` por tarjeta. Los botones de `Equipo` pasan al final del pane, para que la misión y
  los agentes vivos ocupen las primeras filas; un agente en cola no enseña tiempo; la barra
  de la misión ya no cuenta un agente fallado como hecho; un estado que el mod no conoce
  sale bajo `Trabajando` en vez de desaparecer. Los tests cubren fallado, detenido, atascado
  y estado desconocido (antes sin probar).
- **Agent Dock rediseñado.** Tarjetas sin borde con barra de estado, actividad del agente
  visible, barra fina y contador en la misma línea (antes el `Nh` caía a otra línea),
  contadores en una sola línea y misión plegada de verdad por defecto (el `Button` no
  acotaba el truncado de su hijo; ahora se corta a mano). Los tests miden el texto
  dibujado, no las props.
  La misión solo la fija un prompt de la persona: una notificación de tarea en segundo plano
  ya no la pisa con su texto `<task-notification>`.
- **El kit instala las skills del método de trabajo.** `kit/claude/skills/` trae
  `deep-change` (bucle operativo: plan, informe vivo de cambios, contención de riesgo) y
  cinco skills de [mattpocock/skills](https://github.com/mattpocock/skills) (MIT, con su
  `LICENSE`): `grilling`, `writing-for-agents`, `domain-modeling`, y las manuales `retro` y
  `to-questionnaire`. `install.sh` las copia por el mismo camino diff-first que los agentes.
  Sensor: `kit/test/test_skills.sh`, falsable (planta un dato privado y exige rojo).
- **Mod `cockpit` en `kit/mods/cockpit/`:** `/handoff` (documento de traspaso con secretos
  redactados, luego `/clear` y retomar) y el pane *Agent Dock*. Se carga con
  `--plugin-dir` o `CLAUDE_CODE_PLUGIN_DIRS`; no lo instala `install.sh`. Doc:
  `kit/docs/11-cockpit.md`. Sensor: `kit/test/test_mod_cockpit.sh`, sin red ni CLI.
  Al retomar, la sesión nueva ejecuta los comandos de verificación del handoff y responde
  con un resumen corto antes de seguir: el handoff puede estar desfasado.
- **`kit/install-plugins.sh`: plugins de terceros por referencia.** Instala desde su
  marketplace `ponytail` y `ui-ux-pro-max` (más `esenciales` y `frontend-design`), y con
  `--with-optional` `impeccable` y `find-skills`. Opt-in y diff-first; no copia nada al repo.
  Doc: `kit/docs/08-plugins-mcp-y-skills.md`. Sensor: `kit/test/test_install_plugins.sh`,
  sin red (dobles de `claude`/`npx`/`pnpm`), falsable.
- **Cockpit instalable para todas las sesiones y Agent Dock a dos columnas.** El repo es un
  marketplace (`.claude-plugin/marketplace.json`): `/plugin install cockpit --marketplace
  manuelcozar55/setup-claude-code`, y `install-plugins.sh` lo incluye. El dock pasa a dos
  columnas con barra fina, contadores en una línea y misión plegable con un clic; test
  falsable en `tests/dock.test.tsx`.
- **Plugin `esenciales` en `kit/plugins/esenciales/`:** las skills de superpowers con uso
  real (MIT, atribución en `THIRD-PARTY.md`), sin `hooks/`: el `SessionStart` de superpowers
  inyectaba `using-superpowers` (~1,9k tokens) en cada arranque, `/clear` y compactación.
  Sustituye a `superpowers` en `install-plugins.sh` y en `enabledPlugins`. Sensor:
  `kit/test/test_plugin_esenciales.sh`. 6 skills en vez de las 3 del plan: decisión de la
  persona del 2026-10-15 por uso medido en 60 días (brainstorming 10, writing-plans 10,
  subagent-driven-development 10, finishing-a-development-branch 3,
  dispatching-parallel-agents 3, systematic-debugging 2; las otras 9, 0).

- **Arranque desde `~`: `<indice-tareas>` en vez del nucleo compartido (handoff v2, D1).** `session-start-clear.sh`
  ya no inyecta el nucleo de `~`; emite un `<indice-tareas>` derivado (`nucleo_indice`) de los
  nucleos de las raíces registradas en `~/.claude/estado/raices` (máx. 15 por fecha, el heredado de
  `~` primero y marcado, hasta 8 pendientes `(persona)`, tope ~2 500 caracteres, datos escapados,
  sin marcadores de lista ni `[x]` ni controles bidi). El hook registra cada raíz de proyecto al
  arrancar (idempotente) y solo si tiene `.claude/estado/nucleo.md` propio y no enlazado; el
  registro se crea con modo 600 (directorio 700), pasadas 100 líneas se reescribe de forma atómica
  sin duplicados ni raíces sin nucleo, y el índice lee como máximo las 50 últimas únicas. Lo mismo
  vale tras compactar: `session-start-compact.sh` inyecta el índice (con «Contexto compactado.»
  delante, vía `nucleo_indice_ctx`) en vez del nucleo compartido y nunca manda «escríbelo»;
  `nucleo-nudge.sh` y `stop-context-gauge.sh` tampoco tratan el nucleo de `~` como de la sesión (K8). La plantilla del nucleo pide marcar
  `(persona)` lo que solo puede hacer la persona.

- **Arranque con `<git-hechos>`.** El hook calcula `git log --oneline -5` y `git status --short`
  (`timeout -k 1 1`, `--no-show-signature`, `core.fsmonitor=false`, `--no-optional-locks` para no dejar un `index.lock` bajo otra
  sesión del mismo repo, ≤ 1 200 caracteres, `</` escapado) y los inyecta entre la línea de datos y
  `<nucleo-datos>`.

### Changed

- **`05-security.md` declara el límite que ninguna regex cubre.** Los guards ven el texto del
  comando, no el argv que el shell construirá (`F=-rf; rm $F`, `rm -rf $(echo /)`, `eval`,
  `bash -c "$X"`); la capa de permisos de Claude Code es la última barrera.

- **`iocs.json` declara el preflight que exige y `doctor` lo comprueba (auditoría E6 #27).**
  `iocs.json` e `iocs.example.json` llevan `"min_preflight_version": 2`,
  `sentinel_preflight.py` una constante `PREFLIGHT_VERSION = 2` (sin ella, un preflight de
  antes de este cambio cuenta como v1) y `doctor.sh` avisa con `WARN` si el instalado es más
  viejo que lo que pide el iocs de al lado; si coincide, `PASS`. Antes un iocs nuevo con un
  preflight viejo se quedaba a medias sin avisar (las reglas de tubería cuentan con la unión de
  continuaciones del código nuevo). 3 casos nuevos en `test_doctor.sh`. Cambio mínimo y
  localizado (bloque 2c); la deriva de `hooks/lib/` y `sentinel/` es del PR4.
- **Contrato de salida de `echo $X_TOKEN`: de `additionalContext` a `deny`.** Quien tuviera un
  flujo que expande una variable sensible (`curl -H "Authorization: $GITHUB_TOKEN"`) pasa de un
  aviso a un bloqueo; la salida es `env_vars` en `~/.claude/sentinel-allowlist.json`, como
  antes para los avisos.

- **Los hooks Python arrancan con `python3 -I -S`** (`optional-hook.sh`). Medido: 22 → 8 ms
  por hook, porque `site` cargaba apport y un `.pth` editable que apunta a `/mnt/c`,
  escribible desde Windows, dentro de cada guard. Los cinco hooks solo usan stdlib;
  `test_optional_hook.sh` comprueba el `-I -S` y que cada hook arranca así sin `ImportError`.
- **La statusline no cuenta cambios bajo `/mnt/*`.** En un repo en DrvFs los dos
  `git diff --shortstat` llevaban el refresco a 2,7 s (18 ms en ext4); ahí se queda en repo y
  rama. `test_statusline.sh` lo fija con un `git` falso que registra sus argumentos.
- **La instalación se explica en un solo sitio: `kit/docs/02-install.md`.** Estaba contada
  cuatro veces (README, `kit/README.md`, `02-install.md` y `10-onboarding.md`) y las copias
  divergían. `02-install.md` absorbe lo que solo estaba fuera —`make bootstrap`, el modo
  diff-first con `--apply`/`--plan`, la fusión de `settings.json`, la Capa 2 de secretos, el
  aviso de CRLF y desinstalar— y el resto queda en un párrafo corto con enlace.
- **La plantilla de instrucciones es modular**: `kit/claude/AGENTS.md` es el núcleo común a
  Claude Code, Codex y opencode, y `kit/claude/CLAUDE.md` una capa fina que lo importa con
  `@AGENTS.md`. Lleva una línea de precedencia, los desempates (una ronda de aclaración; el
  test tras la lógica nueva) y «ceremonia según riesgo»; sale Headroom, que el kit no instala.
  `install.sh` copia los dos; `test_claude_md_template.sh` vigila sus techos y que toda ruta
  citada exista.
- **`/handoff` del mod `cockpit` escribe `.claude/estado/nucleo.md`** en la raíz git (o el cwd)
  en vez de un fichero en `$TMPDIR`: el tmpfs se pierde al reiniciar y duplicaba el
  `nucleo.md`, que se quedaba desfasado. El fork devuelve solo las secciones que cambian y el
  código las fusiona: «Encargo original» e «Invariantes» se conservan byte a byte (regenerar el
  estado entero es lo que pierde detalle). Copias `nucleo.prev-<sello>.md`, se guardan 3, y
  `.claude/estado/` va a `.git/info/exclude` si git no lo ignora. Secciones nuevas: Encargo
  original, Siguiente acción, Ficheros tocados, No repetir.
- **La retoma tras `/clear` la hace el hook `session-start-clear.sh`** (SessionStart
  `startup|clear`, registrado en `kit/claude/settings.json`), no un prompt del mod: es nativo,
  funciona sin cockpit y no compite con un mensaje de la persona enviado durante el `/clear`.
  Entrega `nucleo.md` (≤ 8 KB, sin secciones CERRADA) como datos, con el protocolo de arranque:
  `git log`/`git status`/oráculo, manda git, y lo irreversible se confirma.
- **Banda de handoff del cockpit (0.2.1).** Los botones pierden la letra delante (`guardar
  + /clear`, `solo guardar`; las teclas `y`/`g` siguen activas) y «n cancelar» pasa a ser
  `no guardar + /clear`, que limpia sin escribir handoff (cancelar es pulsar `handoff` otra
  vez). La fila amarilla usa `columnGap`: `gap` también separa las líneas partidas por
  `flexWrap` y dejaba una fila en blanco en anchos estrechos. Test falsable en
  `tests/cockpit.test.tsx`.
- **`LICENSE` es ahora el texto MIT literal: renombrarlo no bastaba.** En la 1.2.0 se
  intercambiaron los nombres para que el fichero que GitHub inspecciona fuese el del
  software, y la API pasó de `license: null` a `Other` / `NOASSERTION`: encontraba el
  fichero y no reconocía su contenido. La causa medida son las nueve líneas de preámbulo
  en castellano (alcance y terceros) que llevaba delante del texto legal — el detector
  compara el fichero con una plantilla, y esa prosa lo aleja lo bastante. El cuerpo MIT ya
  era **byte a byte** el de la plantilla de GitHub (`gh api /licenses/mit`), así que el
  arreglo es quitarle todo lo que no es licencia: `LICENSE` queda idéntico a esa plantilla
  salvo el titular del copyright. Las precisiones no se pierden, se mudan a `NOTICE`
  —alcance de la MIT frente a la CC BY 4.0 de las charlas, y la incorporación de
  `THIRD-PARTY.md` a las condiciones—, que es un nombre que el detector ignora por
  convención. `README.md` explica el porqué en el sitio donde alguien lo busca. No cambia
  ninguna condición de licencia: cambia qué fichero las contiene.

- **Protocolo de arranque, paso 1.** Con `<git-hechos>` ya no pide repetir `git log` ni `git status`;
  sin git, o si falla, queda el paso 1 anterior.

- **`nucleo_emitir`: tope único de 6 500 con reservas dentro.** «Paso actual», «Siguiente acción» y
  «Comandos de verificación» tienen reserva propia (hasta 700 bytes cada una) y se miden primero; el
  resto recibe 6 500 menos eso. Con reservas cortas el Plan conserva su espacio y con las tres llenas
  quedan ~4 300; peor caso total ≈ 9 400 (el test mide 8 677), dentro de los 9 500 de protocolo + git-hechos + nucleo.

- **Cockpit 0.4.2: el primer mensaje tras `/clear` dice qué se va a hacer.** El relleno del prompt era un
  «sigue con la Siguiente acción…» genérico y la persona aprobaba a ciegas. Ahora es «adelante con la
  Siguiente acción de .claude/estado/nucleo.md: <primera línea de «Siguiente acción»>», sacada del
  documento ya fusionado (sin marcador de lista ni caracteres de control, ≤ 200 caracteres con «…»); el
  prefijo fijo impide que empiece por `/` o `!`, y sin línea queda el genérico. Los mensajes de la UI
  salen del resultado de `$.prompt.fill`: «revisa el prompt y pulsa Enter para seguir», «escribe:
  <texto>» si no se rellenó, «/clear falló: escribe /clear y luego <texto>»; desaparece toda instrucción
  «escribe «sigue»». Cambio de especificación: el test del handoff automático espera ahora el relleno
  informado. `/nueva` no cambia.

### Removed

- Eliminado `smart_approve.py` (fallaba abierto sin settings.json); filas del corpus reatribuidas; `STUB_BLOCK_CASES` sigue en 28; deny del kit intactos.
- **Headroom se retira del kit.** Medido sobre 12 322 peticiones reales: ahorro propio
  0,2-0,6 % del coste, latencia añadida p50 40 ms, y el 89 % del «ahorro» que enseñaba su
  medidor era la búsqueda nativa de herramientas de Claude Code. Salen `install.sh
  --with-headroom`, `test_with_headroom.sh`, `test_headroom_guardrails.sh`, los checks de la
  unidad y los logs del proxy en `doctor.sh`, los comprobadores de su doc en
  `test_doc_claims.sh`, la pista de `make bootstrap` y sus pasos de CI. `03-headroom.md` pasa
  a `kit/docs/archive/` con una cabecera ADR. `doctor.sh` conserva el check de enrutado: un
  `ANTHROPIC_BASE_URL` que sobreviva a la retirada y apunte a un puerto muerto sigue siendo `FAIL`.
- **LangSmith sale del eval.** Se borran `kit/evals/langsmith_push.py` y
  `kit/evals/langsmith_local.py`, los objetivos `make langsmith-local`/`langsmith-arbol`, sus
  bloques de `test_evals.sh` y los mutantes M19, M20 y M37. La interfaz local de trazas es
  Phoenix (`phoenix_push.py`, openinference), que ya tenía su propio sensor de la fila retirada.
- **`charlas/` y `docs/superpowers/` salen del árbol.** Las charlas tenían su propia
  audiencia y `docs/superpowers/` eran planes y registros de proceso ya ejecutados; el repo
  queda centrado en el kit y el harness. Con las charlas se va `LICENSE-DOCS` (CC BY 4.0, que
  solo las cubría): el repo queda bajo MIT. Todo sigue en el historial de git.
- **`preflight.sh`.** Solo recuperaba el proxy de Headroom vía systemd; retirado Headroom,
  era un `SessionStart` sin trabajo. Sale el script y su bloque de la plantilla.

### Fixed

- `handoff`: una sección vacía del borrador (sin cuerpo o solo comentarios) conserva la del nucleo; para vaciarla, `- (nada)`. Antes borraba el Plan y sus `[x]`.
- `handoff`: al recortar al tope se omiten primero las secciones ajenas a la plantilla; el nucleo escrito ya no supera `NUCLEO_TOPE` por una sección extra y el aviso nombra lo realmente omitido.
- `handoff --commit` funciona tras una ejecución sin `--commit` (`git add -f` solo de nucleo, diario, .gitignore y archivo/) y libera el dueño aunque falle el commit.
- `oraculo` solo anota en `verificaciones.log` si `.claude/estado/` ya existe: no ensucia repos ajenos.
- SessionStart: con `source=clear` la sesión nueva reclama el dueño anterior y lo nombra en una línea informativa.
- Seguridad: `nucleo_enlazado` rechaza cualquier enlace simbólico directo dentro de `.claude/estado/` (diario.md, verificaciones.log, .gitignore, archivo); `handoff` (también `--migrar`) sale 3 sin escribir y `oraculo` ejecuta pero no anota.
- Tests: `shellcheck -x` limpio en `test_nucleo_hooks.sh`.
- `bash-write-guard.sh`: `sed ... -i` / `--in-place` detrás de un script con `;`, `|` o `&` (también entre comillas) vuelve a escanearse; antes pasaba con una clave dentro.
- Sentinel: `.aws/credentials` y `.aws/config` se deniegan también en ruta relativa (`cd ~ && cat .aws/credentials`) y con el nombre entrecomillado (`~/".aws"/credentials`).
- Sentinel: el ioc `secrets.*` cubre además `toml`, `ini`, `conf`, `cfg` y `tfvars` (`secrets.token_hex` de Python sigue permitido).
- `lib/secret-patterns`: añade `BEGIN ENCRYPTED PRIVATE KEY` y los tokens de GitHub `ghs_` y `ghu_`.
- **`branch-guard.sh`: las redirecciones no cuentan como operandos del push (E7.3 CR-2).** `git push origin 2>&1`, `... 2>&1 | tail -3` y `git push -u origin >/dev/null` con main activa daban rc 0, porque `2>&1` pasaba a ser el destino. Se descartan los operandos `^[0-9]*[<>]` y `^&>`. Límite: una redirección con espacio (`> fichero`) deja el nombre del fichero como operando.
- **`branch-guard.sh`: con `--repo`/`--repo=` todos los posicionales son refspecs (E7.3 CR-3).** El guard tomaba el primero por remoto, así que `git push --repo=origin main` desde una feature pasaba (3576d87 lo bloqueaba).

- **cockpit 0.4.1: el handoff rechaza también un `.claude` enlazado y ya no confunde una sección final sin salto con un cuerpo.** `refuseLinks` solo miraba `estado/`, `nucleo.md` y `nucleo.prev-*`; con `.claude -> otro sitio` el enlace es el padre y `runHandoff` leía y escribía a través de él, justo lo que los hooks del kit (`nucleo_enlazado`) ya rechazan. Ahora lista `.claude` desde su padre y aborta con aviso. `bodyOf` devolvía la cabecera entera si no había `\n` tras ella (`## Objetivo` como última línea), así que `missingFixed` la daba por rellena y nunca se pedía ni se rellenaba; ahora devuelve vacío, y el relleno de `mergeNucleo` cubre ese caso. Tests: `handoff.test.tsx` (68 pass). Límite: solo se comprueba `.claude`, no ancestros más arriba.

- **`install.sh --plan` ya no puede borrar tu instalación (E6 #1, crítico).** El modo plan
  hacía un borrado recursivo forzado de `MCHARNESS_OUT` (por defecto `$PWD/.mcharness-out`) sin
  comprobar nada: apuntarlo a `CLAUDE_HOME`, a un padre suyo o a un directorio cualquiera
  lo vaciaba. Ahora, sin `MCHARNESS_OUT`, el plan se genera en un `mktemp -d` nuevo (no hay
  nada previo que borrar; se conserva a propósito porque el texto manda copiar a mano desde
  ahí). Con `MCHARNESS_OUT`, solo se usa si no existe, está vacío o lleva el marcador
  `.mcharness-out-marker` que escribe el propio script; cualquier solape con `CLAUDE_HOME`
  (iguales o una contiene a la otra, con `realpath -m`) o un directorio ajeno sin marcador
  termina en exit 1 con mensaje, sin borrar nada. Cambio de comportamiento: ya no existe el
  directorio por defecto `$PWD/.mcharness-out`; el plan queda en `/tmp/mcharness-plan.*`
  (o `$TMPDIR`), que el script no limpia. 25 aserciones nuevas (las de #12 y #27 incluidas) en
  `test_install_diff_first.sh` (rojas contra `3ea7442`, verdes ahora).

- **`settings.json` enlazado se conserva al fusionar (E6 #12).** `install_settings` hacía `mv`
  del merge sobre el enlace y lo sustituía por un fichero regular, rompiendo el repo propio
  al que apuntaba. Ahora fusiona a través del enlace (temporal junto al destino real, backup
  bajo el nombre del enlace) y el enlace sigue siendo enlace. Límite declarado: `install_file`
  sigue omitiendo los demás enlaces sin tocarlos; solo `settings.json` se escribe a través.

- **Mensaje de `--plan` veraz y `test_statusline.sh` con mawk (E6 #27).** `--plan` sobre un
  `CLAUDE_HOME` que no es repo git decía «es tu propio repo git (con remoto)»; ahora dice
  «Modo --plan» y «solo muestra lo que se instalaría», y el texto de repo git queda para
  cuando de verdad lo es. Las 2 aserciones de «ancho 80/50» fallaban con mawk 1.3.4 porque su
  `length()` cuenta bytes y parte los caracteres UTF-8; se miden con `${#}` de bash
  (`LC_ALL=C.UTF-8`). La suite da 30/30 con gawk y con mawk. Sin efecto en producción.

- **`nucleo_emitir` reserva sitio para «Paso actual» y «Siguiente acción».** El tope de 6 500 B se
  gastaba por orden y con un nucleo de 12-20 KB se perdían justo esas dos. Ahora tienen reserva
  propia de 700 B cada una, fuera del tope; el recorte cae sobre Plan, Pendientes, Comandos y
  Ficheros. Total máximo de la emisión ≈ 7 900 B. Con un nucleo de 12 y de 20 KB ambas salen.
- **El corte por bytes no parte un carácter UTF-8** (título, cabecera y sección recortada); se
  detecta el byte de continuación con octales, igual en gawk y mawk.
- **El recorte a 9 500 de `session-start-clear.sh`/`-compact.sh` cierra siempre `<nucleo-datos>`**
  (`nucleo_tope`, con rutas de ~1 800 caracteres quedaba abierto).
- **`session-start.sh`**: sin entradas imprimía dos ceros (`grep -c … || echo 0`); la ruta de la
  memoria codifica como Claude Code (todo no alfanumérico → `-`, así `.claude` → `-claude` en
  `--claude`), con el `/`→`-` anterior de respaldo.
- **`nucleo-nudge.sh` (PostToolUse)** lee primero el transcript y la marca de banda: bajo el 50 %
  o con la banda ya avisada no lanza `git` ni mira el nucleo. Efecto lateral: la marca también se
  rearma con el nucleo fresco.
- **`pre-compact.sh` rota checkpoints también por número** (`NUCLEO_CHECKPOINT_KEEP`, 5 por defecto,
  contando el nuevo), además de los 14 días. Su `.gitignore` pasa de `checkpoint-compact-*` a
  `checkpoint-compact*` para cubrir el respaldo sin hash `checkpoint-compact.md` (sin
  `session_id`); los `.gitignore` ya creados reciben la línea nueva.
- **`doctor.sh` compara también `hooks/lib/` y `sentinel/`** en el chequeo de deriva
  kit/desplegado (WARN, como el resto). `iocs.json` personalizado saldrá como deriva.
- **`narthex-post-mcp.py`: `log()` captura `OSError`** y avisa por stderr; antes un directorio de
  auditoría no escribible llegaba al `except` de `main` y el hook salía 0 sin emitir el aviso
  al modelo.

Subsección: Fixed (cockpit 0.4.1)

- **El handoff del cockpit ya no pierde escrituras concurrentes ni deja el Objetivo vacío (E6 #7, #11).** El fork tarda segundos y `prev` se leía antes: una escritura de otra sesión o del hook PreCompact se perdía y el respaldo `nucleo.prev-*` no era la versión reemplazada, mientras se anunciaba «Guardado». Ahora `nucleo.md` se relee tras el fork y, si difiere, el handoff aborta con «nucleo.md cambió durante el handoff» sin escribir ni limpiar. «Objetivo» (el nombre de la plantilla del kit) se protege como «Encargo original» y, si está vacío (o solo tiene el marcador `<!-- -->`), el prompt lo pide y la fusión lo rellena; lo que ya tiene contenido sigue byte a byte. `prev` escapa `</nucleo-actual>` dentro del bloque de datos y los títulos se comparan sin acentos ni mayúsculas (`Siguiente acción` = `siguiente accion`). Si `estado/`, `nucleo.md` o una copia `nucleo.prev-*` son enlaces simbólicos, el handoff no lee ni escribe. 7 tests nuevos (66 en el mod). Límites: una escritura entre la relectura y la escritura final no es detectable (la API no tiene reemplazo atómico); los enlaces se detectan con `find -type l` porque `$.fs` no tiene lstat, y solo se miran `estado/` y sus entradas directas, no los directorios superiores.

- **`nucleo_ctx` medía sobre 200k en modelos de 1M.** Exigía `[1m]` en el id, y Opus 4.7+,
  Opus 5, Fable y Sonnet 5 traen 1M sin sufijo: con el alias `opus` el aviso marcaba ~30 % de
  más. La ventana sale ahora también del id del último assistant del transcript, en la misma
  lectura de `jq`; el `[1m]` de `ANTHROPIC_MODEL` o de `settings.json` solo cuenta para el
  modelo que nombra. El aviso del 70 % declara el fin de fase como parada válida y el del 85 %
  remite al handoff automático, salvo con `COCKPIT_AUTO_HANDOFF=off`.

- **`nucleo_emitir` perdía los pendientes de `/handoff`**: con un `nucleo.md` sembrado desde la plantilla (`## Pendientes` vacío) el handoff escribe `## Pendientes y riesgos` más abajo y, al ganar la primera copia, lo inyectado traía la sección vacía y ninguna señal más que «fuera de forma» (visto e2e en Debian con Haiku y Sonnet). Ahora una sección repetida entra si la primera quedó vacía; con contenido sigue ganando la primera. Tests en `test_nucleo_lib.sh`; verificado con gawk y mawk.
  Los marcadores `<!-- … -->` de la plantilla (Objetivo, Plan) tampoco cuentan como contenido: sin eso el
  «Encargo original» y el «Plan» del handoff se descartaban como repetidos (hallazgo de /code-review, E6).
- **`test_harness_structure.sh` sin gitleaks**: el grep de respaldo no llevaba `\<` delante de `sk-` y casaba con el fixture kebab «risk-mitigation-…» de `test_scan_secrets.sh`, así que la suite fallaba en cualquier máquina sin gitleaks (visto en Debian 13). Mismo límite de palabra que `kit/scan-secrets.sh`.
- **Sentinel: los ficheros de clave se miran por palabra de shell y por su papel, no por
  regex sobre el comando.** Las seis regex de extensión (`.pem`, `.key`, `.p12`, `.pfx`,
  `.jks`, `.keystore`) miraban subcadenas y en la instalación real dieron 245 denegaciones
  falsas en un día; una regex intermedia que exigía un nombre delante dejaba pasar el oculto
  (`.server.key`) y los sufijos de copia (`x.key~`), porque `cat .server.key` y el filtro
  `jq '.data.key'` son el mismo texto. Ahora `sentinel_preflight.py` parte el comando con un
  lexer propio (comillas, escapes, redirecciones, saltos de línea; un `#` que abre palabra
  comenta hasta fin de línea, como en bash; `$( )` y acento grave se leen como comando
  aparte) y compara cada componente de ruta con `key_file_extensions` de `iocs.json`, que
  sustituye a la regex; sus entradas se filtran una a una (con o sin punto inicial) y, si la
  lista falta o no queda ninguna, el código usa las seis por defecto y el motivo del deny lo
  dice: una lista vacía no apaga la comprobación. El cuerpo de un heredoc se lee como
  comandos salvo que lo reciba un sumidero de datos conocido. El consumidor es el comando que
  lleva el `<<`, sin `sudo`, `env`, `nice`, `time`, `command` ni `exec`. `cat`, `tee`,
  `grep`, `jq`, `git commit -F -`, `curl -d @-`, `curl -T -`, `wget -i -` y el resto de la
  lista lo hacen datos (`curl -K -` no: una configuración por stdin puede subir un fichero;
  `sed` y `awk` solo si su programa, también el pegado a `-e`/`--expression=`/`--source=`,
  no ejecuta nada): un `cat > data.jsonl <<'EOF'` con JSON no se mira como rutas. Un
  intérprete lo hace código, salvo que su código en línea (`python -c`, `node -e`,
  `perl -e`, `ruby -e`, `php -r`, `lua -e`, `Rscript -e`, `bun -e`, `deno eval`; sin tabla se
  mira entero) ejecute lo que lee, por nombres de ejecución (`system`, `system2`, `exec…`,
  `spawn…`, `eval`, `popen`, `Deno.Command`:
  `perl -ne 'system $_'`, `php -r 'passthru(…)'`; `evaluate` no casa), y `ssh`, `sudo -s`, `fish`, `xargs`,
  `psql` o cualquier desconocido, comandos. Manda el peor consumidor de su tubería, comandos
  sobre perl/ruby sobre el resto de código (`cat <<EOF | python3 | sh` son comandos), y el de
  todo el comando si el heredoc o su tubería pasan por un grupo, un bucle o una sustitución
  de proceso (`cat <<EOF | { cat; sh; }`). Si después del heredoc, en la misma orden, hay un
  ejecutor (un shell, un intérprete, `source`, `eval`, `chmod`, `xargs`, `find`/`fd` con
  exec, `flock -c`, `./x`, también tras `timeout`, `nohup`, `busybox`, `unshare` y similares;
  una ruta bajo `/bin`, `/usr/bin`, `/sbin` o `/usr/sbin` como `/usr/bin/git` no lo es), el
  cuerpo son comandos sin seguir el nombre del fichero ni cómo se escribió
  (`cat <<EOF >run.sh; bash run.sh`, también `sed -n '1w run.sh'`, `cat run.sh | sh`, tras
  `mv` o por variable; coste: `cat <<'EOF' && bash deploy.sh` con una clave en el cuerpo se
  deniega); `cat > notes.md <<'EOF' … && git add notes.md` sigue siendo datos. Sin comillas en el delimitador sus `$( )` se
  ejecutan, y la barra-salto solo sirve para hallar el delimitador (100 000 líneas con barra
  final y sin delimitador cuestan 1,1 s; antes 13,4 s, la unión era cuadrática). Las llaves
  `{a,b}` y las secuencias de letras `{a..z}` sin comillas se expanden sin repetidos hasta 64
  por palabra y 4 096 por comando entero (un solo contador que incluye sustituciones, cadenas
  releídas y literales de código; 4 096 expansiones cuestan 15 ms) y pasado el tope se
  deniega (`brace expansion too large`); una secuencia numérica (`{1..1000}`) no aporta
  letras: cuenta como su primer valor y no gasta tope; entre comillas no se expanden, como en
  bash, y en una cadena releída (`bash -c '…'`) se expanden grupo a grupo sin truncar nunca
  (más de 64 grupos deniegan). Se exime el patrón de `grep`/`rg`/`ag`/`ack`, el filtro de
  `jq` y el mensaje de `git commit|tag|merge -m`, con la aridad de sus opciones (`-e`, `-f`,
  `-g`, `--match`, `--files` y `--type-list` anulan la exención, también como letra de un
  racimo de flags cortos, pero no como letra del valor de una opción: `rg -t typescript` ya
  no la anula); del código de `node -e`/`python -c`/`perl -e`/`ruby -e` solo se miran los
  literales de cadena (una vez cada uno; pasado el presupuesto, sin expandir), las formas de
  cita con su letra (`%q()`, `%x()`…; `q()`, `qq{}`, `qx()` y el `%()` pegado solo en perl y
  ruby; una sin cierre no se traga nada) y, de cada tramo con barra, todos sus componentes
  si tiene forma de ruta (`/`, `./`, `../`, `~/`) y si no el último (`opts.key/2` es una
  división), y solo si el flag va antes del script (`python3 x.py -c …` no exime). El cuerpo de una sustitución `$( )` dentro de un papel
  exento se lee como comando propio: el commit con heredoc (`-m "$(cat <<'EOF' … EOF)"`) deja
  de dar falso positivo. **Se deniegan**, como en `main`: rutas,
  comillas, el oculto (`.server.key`, `.env.key`, `.tls.pem`), los sufijos de copia (`~`,
  `#`, `+`, `-old`, `.bak`), globs (`*.key`, `[s]erver.key`), `'x'.key`, `server.{key,pem}`,
  `x.key.{1..3}`, acento grave, `$( )`, `bash -c '…'`, un heredoc con una clave hacia `ssh`,
  `sudo -s`, `fish` o `php`, directorios (`dir.p12/x`; en código, con forma de ruta) y las
  rutas de Windows.
  **Dejan de denegarse** (falsos positivos medidos): `jq 'to_entries[].key'`, `.data.key`,
  la división `.a/.key`, `grep -rn "event.key" src/`, `rg -t typescript 'event.key'`,
  `git commit -m "use opts.key"`, `node -e "console.log(o.key)"`,
  `node -e 'console.log(opts.key/2)'`, `echo {1..100}`, unas notas en
  `cat <<EOF >out.txt && bash run.sh`, `a.key.json`, `config.key.ts` y la prosa que nombra la
  extensión. **Límite declarado**: el oculto a secas sin barra (`cat .key`), indistinguible
  de la prosa; donde el papel de una palabra no se clasifica (`sudo grep`, `git -C x commit`)
  se deniega de más, nunca de menos; un script escrito por un heredoc y ejecutado en otra
  llamada o con un comando fuera de la lista de ejecutores (`make run.sh`, `pnpm exec sh run.sh`)
  no se ve, y un ejecutor en cualquier línea posterior de la misma llamada deniega aunque el
  heredoc no escriba el fichero que ejecuta (coste de la regla sin nombres, pinado en la suite:
  unas notas seguidas de `python3 gen.py`, un `git commit -F -` seguido de `bash scripts/check.sh`).
  Una palabra con barra se clasifica por su basename solo si es una ruta absoluta en una lista
  cerrada de directorios (`/bin`, `/sbin`, `/usr/bin`, `/usr/sbin`, `/usr/local/bin`,
  `/usr/local/sbin`, `/opt/homebrew/bin`, `/opt/homebrew/sbin`, `/opt/local/bin`, `/snap/bin`) y
  el basename es una herramienta conocida que no ejecuta su argumento (`git`, `gh`, `pnpm`, `code`,
  `make`, `curl`, los sumideros): `/usr/local/bin/git add` tras un heredoc no es ejecutor; todo lo
  demás con barra (`./run.sh`, `./bin/git`, `~/bin/git`, `node_modules/.bin/tsc`, `$NVM/bin/pnpm`,
  `/opt/tools/foo`) sí, y deniega de más; no se ve una herramienta conocida que el propio heredoc
  escriba en esos directorios (en macOS `/usr/local/bin` y `/opt/homebrew/bin` son del usuario y
  basta un `>`; en Linux piden root) ni que ejecute su argumento (`pnpm exec sh run.sh`, `make run`
  o `/usr/local/bin/make run` con un Makefile escrito por el heredoc). El código en línea sigue viendo
  cualquier palabra con `exec` o `spawn` (`os.execlpe`, `os.spawnle`, `execa`) y `popen` con sufijo
  (`Open3.popen3`); solo se exime una lista cerrada de prosa (`execution`, `executor`, `executable`,
  `executed`, `executing`, `executive`, `spawned`, `spawning`, `spawns`), y otra palabra de prosa
  deniega de más (la forma sin sufijo es un nombre de API en Lua y Groovy: no se exime).
  `fd`/`fdfind` ven la `x` dentro de un racimo de flags, dígitos incluidos (`-Hx`,
  `-1Hx`; `-ex` es `-e x`); `unshare` reconoce `--propagation`, `--setgroups`, `--monotonic`,
  `--boottime`, `--map-users` y `--map-groups`; `setpriv` y `nsenter` son prefijos con su aridad.
  `deno`: el subcomando es la primera palabra de su lista de subcomandos que no sea el valor de
  `-L`/`--log-level` (`deno --log-level info eval` se ve); sin subcomando conocido todo es código en
  línea; el valor de otra opción global que coincida con un subcomando es límite (`deno -c check
  eval` toma `check` por subcomando). Un prefijo sin
  comando solo cuenta como shell si abre uno por diseño (`sudo`/`doas` con `-s`, `-i`, `--shell`,
  `--login`, también en racimo o tras `-u usuario`; `chroot`, `unshare`, `nsenter`, `exec` con solo
  redirecciones) o lleva el comando en un valor (`flock -c`, `env -S`): `flock -n 9` o `timeout 5` a
  secas ya no deniegan; cada prefijo lo declara en `_BARE_SHELL` y la suite exige que estén todos.
  Los demás límites asumidos van en el comentario de `key_file_extensions`.
  257 sondas nuevas en `test_guards.sh` (25 de la regex, 17 fallaban con ella; 16, 32, 35,
  24, 22, 22, 26, 36 y 19 de las nueve rondas de revisión, 11, 17, 21, 16, 18, 14, 14, 23 y 12
  fallaban antes de su fix).
  Además, `test_guards.sh` escribía sus deny en el `sentinel.jsonl` del HOME real;
  `test_guards_falsifiability.sh` lo impide ahora con un HOME simulado.
- **`pre-compact.sh` rota los checkpoints de más de 14 días, después de publicar el nuevo.**
  Escribe uno por sesión, con los últimos prompts de la persona, y nadie los borraba. La
  rotación va tras el `mv` y excluye el recién escrito: si generar o publicar falla, el
  checkpoint anterior se conserva de verdad. `nucleo-freshness.log` (una línea por
  compactación) se acota a las últimas 1 000 al pasar de 2 000, con un temporal de `mktemp`
  que conserva el modo del log y que un `trap` borra si el `tail` o el `mv` fallan o una señal
  mata el hook a medias. Nuevo caso que fija que un
  directorio sin git ni `.claude/estado` no gana un `.claude/` (una instalación anterior a
  3917835 dejó 47 bajo un home).
- **`/handoff` (cockpit 0.3.5) escribe donde el hook de arranque lee.** Resolvía la raíz git
  desde el cwd del proceso del mod, no desde el de la sesión, y desde `~/.claude` escribía un
  `.claude/.claude/estado/nucleo.md` anidado que nadie inyectaba. Ahora usa `git -C <cwd>` y
  sube `$HOME/.claude/**` a `$HOME`, como `nucleo_raiz` desde el cwd de la sesión
  (`CLAUDE_PROJECT_DIR` no llega al mod).
- **`session-start-clear.sh` avisa al retomar con la caché caducada.** Con `resume`,
  `prompt_cache_likely_expired` y ≥ 100 000 tokens, un `systemMessage` propone `/handoff`: el
  turno siguiente reescribe el contexto entero (medido: 96 % del prefijo tras > 1 h), así que
  retomar limpio cuesta casi lo mismo. La doc envía los mismos campos en `fork`, pero el matcher
  del kit no lanza el hook ahí: una sesión bifurcada ya trae su contexto. `context_tokens` solo cuenta si es número: en jq una
  cadena ordena por encima de cualquier número y el umbral se cumplía siempre.
- **`nucleo_emitir` reconoce las secciones en `###`.** Las sesiones escriben la tarea como
  `## TAREA ACTUAL` con `### Encargo original`, `### Plan`…; solo con `##` el inyector entregaba
  el título (148 chars de un nucleo real de 7,7 KB) y el modelo retomaba a ciegas. Un `###` que
  nombra una sección de plantilla aún no vista es cabecera bajo cualquier `##`; sin clave es
  contenido solo bajo un `##` de plantilla (`### Fase 1` en `## Plan`) y, bajo otro, cierra la
  sección y cuenta en «fuera de forma», para que un `### Hecho` no se cuele en Pendientes. Solo
  el nombre distingue ese `### Hecho` de un subapartado: un `### Fase 1` bajo `## TAREA ACTUAL`
  también cierra la sección (los subapartados se escriben con `####`), pero no en silencio: si
  cierra una sección viva, la salida pide leer el fichero y sugiere `####`. La
  clave va por prefijo también en `###`: `### Plan de migración` reclama Plan, como ya hacía
  `## Plan de migración`. Límites: un `##` de plantilla repetido descarta su contenido y sus `###`
  sin clave sin más señal que «fuera de forma»; un `###` sin clave justo después de
  `## TAREA ACTUAL`, sin sección viva que cerrar, se descarta sin la línea «LEE»; esa línea
  sale también en la disposición de siempre (`### Hecho` tras una sección viva), coste de hacer
  visible la pérdida; y una cerca sangrada suelta (una ``` de ejemplo en prosa) vuelve impar la
  paridad y desactiva todas las cercas del fichero, con su aviso.
- **`nucleo_emitir` no cierra la sección en un `# comentario` dentro de un bloque de
  código.** La regla de cabecera casaba cualquier línea que empezara por `# `, también entre
  ```; un comentario en «Comandos de verificación» cortaba la sección y los comandos, lo más
  importante de re-inyectar tras `/clear` o compactar, se perdían sin aviso con un «fuera de
  forma» falso. Hallazgo de `/code-review` del 15-oct; test que fallaba antes del cambio.
  Las cercas solo cuentan si están equilibradas: admiten cualquier sangría (un paso numerado
  lleva su bloque de comandos sangrado cuatro espacios) y tres o más acentos graves (una línea
  ```` ```x``` ```` no es cerca). Si una queda sin cerrar se ignoran todas, para que no se trague
  el resto del fichero, y la salida lo avisa y pide leer el fichero. Límites: un ```` ``` ````
  dentro de un bloque sangrado de CommonMark cuenta como cerca; no se contemplan cercas anidadas
  ni `~~~`, ni se casa el cierre con el apertor (longitud ni info string). El fichero se lee dos
  veces (como ya hacía `wc -c`): si otra sesión lo escribe entre medias, la paridad puede no ser
  la del texto emitido.
- **Sentinel ya no lee el allowlist del directorio de trabajo.** Un repo clonado con
  `.security/sentinel-allowlist.json` podía convertir en `allow` el deny de un `.env` o,
  con `[]`/`{"paths":null}`, tumbar toda herramienta con exit 2. Solo cuenta el de `$HOME`;
  datos malformados (allowlist, iocs, regex, audit-log) se ignoran en vez de bloquear.
- **Más grafías de pipe-a-shell y menos falsos positivos en `block-dangerous-commands.sh`.**
  Pasaban `| sudo -E bash -`, `|& bash`, `| python3` o `. <(curl ..)`; y `"$(curl ..)"` como
  argumento, `npm` citado en texto o `--no-verify` entre comillas se denegaban en falso.
- **`lib/nucleo.sh`: raíz de worktrees, tope real de la inyección, ventana sin `[1m]` y
  symlinks.** Un worktree de `claude --worktree` resolvía al repo padre, `</NUCLEO-DATOS>`
  cerraba el envoltorio, un título enorme saltaba el tope y un `nucleo.md` enlazado hacía
  escribir o leer fuera del repo.
- **`pre-compact.sh` no ensucia repos ni deja el checkpoint commiteable; el nudge se
  rearma.** Creaba `.claude/estado/.gitignore` en cualquier repo y, si ya existía, dejaba el
  checkpoint con los prompts de la persona como `??`; el aviso de `nucleo.md` solo saltaba
  en el primer ciclo de compactación.
- **El `nucleo.md` de un repo ya no ordena ejecutar nada, y el `allow` no lanza código.**
  El arranque propone el oráculo y solo lo ejecuta si la persona confirma; con
  `Bash(uv tool *)` un repo hostil podía ejecutar `uv tool run --from git+https://…`. El
  `allow` pasa a `uv tool list`, `rtk gain` y `graphify query|path|explain`.
- **`task-brief` (plugin `esenciales`) solo acepta un número de tarea entero.** `N` iba sin
  validar a un nombre de fichero y a una regex de awk: `../../../x` salía del espacio de
  trabajo y `1.*` mezclaba las tareas 1, 10, 11…

- **El sensor de `[Unreleased]` enrojecía un CHANGELOG correcto, y se vio al estrenar el
  procedimiento de release.** `test_doc_claims.sh` juzga las cifras de inventario de esa
  sección —suites, ADRs y las cuatro del eval— y lo hace estricto a propósito: un `claim`
  que no llega a juzgar ninguna cifra aprobaría pase lo que pase. Contemplaba la sección
  **vacía** (recién etiquetada una versión) como `skip`, pero no el caso siguiente: la
  primera entrada nueva puede hablar de algo que no es el inventario. La de licencias de
  arriba no menciona ninguna de las seis, y las seis dieron `NOT ok` sobre un fichero que
  no tenía nada mal — el sensor exigía que cada entrada del changelog recitara el
  inventario. Se añade a `claim` un tercer estado, `claim_omiso`: estricto con la cifra
  que esté escrita, `skip` **visible en el resumen** con la que no. No se ha usado
  `claim_flojo`, que existía ya, precisamente porque su camino silencioso imprime `ok`
  habiendo juzgado cero. Y el modo nuevo trae su propia sonda de falsabilidad: sobre una
  sección fabricada que escribe una cifra falsa, `claim_omiso` sigue enrojeciendo — lo que
  había que demostrar no es que sepa omitir, sino que omitir no le quitó el juicio.

- **Cockpit 0.4.2: el handoff ya no duplica «Pendientes».** El prompt del fork pedía «## Pendientes y
  riesgos» y la plantilla usa «## Pendientes»: la fusión no las emparejaba, la del fork se añadía al
  final y `nucleo_emitir` inyectaba la vieja. Ahora el prompt usa las cabeceras de la plantilla (con la
  marca `(persona)`), una tabla de alias pliega «Pendientes y riesgos» a «Pendientes» y, cuando el fork
  devuelve la sección, sustituye la primera aparición y elimina las repetidas (su texto queda en
  `nucleo.prev-*`).

- **`nucleo-nudge.sh` ignora a los subagentes** (`agent_id` no vacío): un Explore recibía «CONTEXTO 55 %…
  actualiza nucleo.md».

- **Cockpit 0.4.2: `nextLine` sin bidi ni vallas.** Sustituye por espacio U+202A-202E, U+2066-2069 y
  U+2028-2029 (un U+202E en la Siguiente acción invertía en pantalla lo que la persona aprueba con
  Enter), salta las vallas de código (```` ``` ````, ```` ```bash ````) y toma el primer comando; el corte
  a 200 va por puntos de código y no parte un par sustituto. Si `/clear` falla, el mensaje vuelve a
  decir dónde quedó el estado: «Guardado en <ruta>, pero /clear falló: escribe /clear y luego <texto>».

- **`<git-hechos>` ejecutaba `git log` sin `--no-show-signature`:** un repo con `log.showSignature=true`
  y `gpg.program=<script>` ejecutaba ese script en `SessionStart`. Ahora la firma no se consulta y las
  dos llamadas de git usan `timeout -k 1 1`.

### Security

- Los guards de Bash ya no fallan en abierto por el tamano del comando. Un comando de 64 KB en una
  linea costaba 9-15 s de CPU en Sentinel y 2-4 s en cada guard, y un hook que pasa de su timeout (10 s)
  no bloquea: la herramienta se ejecuta. Causas: `${x#*sep}` en `cmdnorm.sh` (cuadratico), los `grep`
  de `block-dangerous-commands.sh` en UTF-8 (ahora `LC_ALL=C`, 64 KB de segmentos: 13 s a 0,4 s) y
  `(?i).*_TOKEN$` buscada en una palabra larga en Sentinel. Ahora todos son lineales (256 KB: 0,3-0,6 s
  en una linea, ~4 s en el peor caso de 128 000 segmentos).
- Por encima de 128 KB (con 256 KB el peor caso, ~4 s de CPU por guard y los seis a la vez, rozaba el
  timeout en una máquina de 2 núcleos), block-dangerous, branch-guard, destructive-guard, secret-guard y Sentinel piden
  confirmacion (`ask`) y sugieren la herramienta Write para contenidos grandes, en vez de arriesgar el
  timeout.
- `scripts/guards-cpu.sh` mide muestras grandes hook a hook y falla si alguno pasa de 1000 ms: con ~20
  muestras el p95 las escondia (antes: p95 181 ms con max 15 886 ms).
- **`branch-guard.sh` vuelve a ver el push que va dentro de `bash -c`, `sh -c`, `eval`, `ssh host`, `xargs` y `find -exec` (E7.3 CR-1).** El guard de la normalización (PR2) solo inspeccionaba segmentos cuyo ejecutable era `git`, y el guard de texto de 3576d87 bloqueaba esas grafias (rc 2): regresión, rc 0 con la rama protegida como destino. Ahora, si el ejecutable no es `git` pero el segmento nombra `git`, la cadena interior se vuelve a normalizar y se analiza con la misma lógica (hasta 3 niveles); `echo`, `printf`, `grep` y similares quedan fuera para que la prosa con un push dentro no dé falsos positivos. Latencia: 24 ms por invocación (25 antes; presupuesto 150). Límite: la cadena construida con variables sigue fuera de alcance.
- **`branch-guard.sh` bloquea `--all`, `--branches` y `--mirror` (E7.3 CR-8).** Empujan todas las ramas, las protegidas incluidas, y se trataban como opciones sin destino. Límite declarado en `docs/05-security.md`: con `push.default=upstream` y un upstream de nombre distinto al de la rama local, el `git push` a secas no se resuelve (el guard no lee la configuración de git).
- **`destructive-guard.sh`: un `..` tras el directorio seguro ya no exime el `rm -rf` (E7.3 CR-4).** `rm -rf ~/dist/../Documents` y `rm -rf ~/node_modules/../<claves>` salían con rc 0 porque la exención miraba `/dir/` como subcadena. Se cierra en el check 5 y en el check 1 (texto, anterior a E7: mismo agujero, arreglo local de una condición). `rm -rf dist/..` pasa a ser sensible. `rm -rf ../node_modules` sigue permitido (el `..` va antes, no después).

- **Los cuatro guards bash leen el comando normalizado, no el texto crudo (E6 4, 5, 6, 9).** Cada
  guard comparaba el literal con su propia regex y fallaba por separado ante las mismas grafías:
  un `#` dentro de comillas cortaba el escaneo (`git commit -m "fix #12" && git reset --hard`
  pasaba), `git -C dir reset --hard`, `sudo git …`, `/usr/bin/git`, `git clean --force -d`,
  `rm -rv`, `rm -R` y `rm -rf --` salían de los patrones, la continuación `\`+salto de línea
  partía el pipe-a-shell en dos líneas, `git push origin "main"`, `git push` a secas y
  `git push origin HEAD` con main activa pasaban (y `main-menu` daba falso positivo), y
  `git -C . add <fichero de entorno>` no llegaba al filtro. Nueva `hooks/lib/cmdnorm.sh` (se
  instala con el resto de `hooks/lib/*`): una sola pasada de awk POSIX, con mawk y gawk dando el
  mismo resultado, que une continuaciones, quita comentarios solo fuera de comillas, descomilla
  tokens y reconoce los prefijos `sudo`/`env`/`command`/`nice`/`timeout N`/`VAR=x`, la ruta del
  ejecutable y las opciones globales de git (`-C`, `-c`, `--git-dir`, `--work-tree`…).
  `block-dangerous-commands.sh` escanea el texto normalizado; `destructive-guard.sh` conserva sus
  checks (siguen viendo lo que va dentro de un `bash -c`) y suma uno por comando simple que cubre
  `-R`, `-rv`, `--` y las rutas sensibles sin `-f` (`git clean -n` y `--dry-run` no se deniegan);
  `branch-guard.sh` resuelve el destino real (refspec implícito o `HEAD` → rama actual con
  `git symbolic-ref`, en el cwd del hook o el que fijen `git -C`/`cd`) y compara por igualdad de
  token; `secret-guard.sh` evalúa la exención del fichero de ejemplo por operando y contempla
  `-A`/`--all`/`.` con el repo resuelto por `-C`/`cd`. Tests: `test_guards.sh` pasa de 399 a
  503 casos (+104: 6 de continuaciones, 37 de `destructive-guard`, 34 de `branch-guard`, 27 de
  `secret-guard`), cada uno rojo antes del arreglo; `test_guards_falsifiability.sh` fija ahora
  **28** casos `BLOCK` (eran 10) y README y onboarding citan la cifra nueva. Latencia medida
  (20 invocaciones por guard, media; HOME limpio, ext4): 11/12/11/7 ms → 16/16/13/11 ms
  (block-dangerous / destructive / branch / secret), +18 ms en la suma de los cuatro (de ~41 a
  ~59 ms), dentro del presupuesto de 150 ms de la cadena. Límites declarados: sigue siendo el
  texto, no el argv (`F=-rf; rm $F`, `eval`, `bash -c "$X"`, sustituciones), `bash -c "git reset
  --hard"` solo lo ve el check heredado de `rm`, no el de git, y `git push --all` no se
  contempla; si `lib/cmdnorm.sh` falta o awk falla, los guards deniegan (fail-closed nuevo, hasta
  ahora no dependían de ninguna lib).

- **Sentinel juzga cada URL, cada ruta y cada variable por separado (auditoría E6 #2, #3, #10,
  #14, #15).** Seis huecos reproducidos con comandos normales: un host permitido en un
  comentario (`# https://github.com`) o en una segunda URL eximía todo el comando del bloqueo de
  exfiltración; un ejecutable bajo `/tmp` (`/tmp/bin/cat clave.key`) eximía sus argumentos porque
  `is_allowed_path` recibía el comando entero; Grep (`glob`), Glob (`pattern`) y NotebookEdit
  (`notebook_path`) leían directorios de claves porque `PATH_FIELDS` era cerrado; un comodín
  (`~/.s*/id_rsa`) o un `..` intermedio (`~/.aws/../.aws/config`) esquivaban las rutas literales
  de `iocs.json` (21 de 320 en el corpus de E5); y las variables sensibles solo avisaban, con la
  regex `(?i).*_TOKEN$` anclada al final del comando entero. Ahora: `without_allowed_urls` quita
  solo las URL permitidas y el resto se sigue comprobando (una URL no permitida basta para
  bloquear); la exención de ruta solo vale en campos que son una ruta (`file_path`, `path`,
  `notebook_path`, `file`, `filename`, `glob`, `pattern`), nunca en `command`, `url`, etc.;
  `PATH_FIELDS` se abre a esos campos (el `pattern` de Grep queda fuera: es una regex sobre
  contenido); las rutas se comparan normalizadas (`~`, `$HOME`, `..`, llaves), con comodines
  contra los componentes de cada patrón (el `*` no cruza un punto inicial y un `*` pelado solo
  cuenta en el nivel de fichero de un directorio oculto: `~/.aws/*` se deniega, `ls /etc/*` y
  `ls ~/.config/*` no) y por nombre base para las claves de `~/.ssh` (`id_ed25519`) cuando es
  una ruta entera; y leer una variable sensible (`$X`, `${X}`, `printenv X`) pasa de aviso a
  deny, con la regex aplicada a cada nombre. Nombrarla sin leerla (un mensaje de commit) sigue
  siendo aviso. Las 16 filas SOLO-AVISO y las 21 de ruta del corpus de E5, más 11 sondas de
  tubería, son ahora casos de `test_guards.sh`; las 69 filas A de Bash del corpus siguen en
  ALLOW. Latencia de Sentinel sin cambio medido: mediana de 20 invocaciones 47-52 ms antes y
  45-47 ms después (ruido de la máquina; el coste es una pasada de regex por campo). Límites
  declarados: `ls /etc/*` y `cat /etc/*` no se tratan como lectura de `/etc/shadow`; el nombre
  base `id_rsa` como palabra suelta de un comando es prosa y no se deniega; `export X_TOKEN=…`
  y los volcados `env`/`printenv` sin operandos solo avisan o pasan (no leen una variable
  concreta); un comando entero sigue sin exención de ruta, así que `cat /tmp/x.pem` se deniega
  como antes; una herramienta de terceros que nombre su ruta con otra clave no se ve.

- **Tubería al shell en Sentinel: `sudo bash`, `env bash`, `|&`, ruta absoluta y continuación
  (auditoría E6 #6, parte Sentinel).** Las dos regex de `iocs.json` (`curl`/`wget` … `| shell`)
  no veían `| sudo bash`, `| env bash`, `|& sh`, `| /bin/bash`, `| dash`, `| node` ni
  `curl x \`+salto de línea`| bash`; además `| sha256sum` se bloqueaba por casar el prefijo
  `sh`. Ahora aceptan prefijos (`sudo`, `doas`, `env`, `nohup`, `exec`, `command`, `stdbuf`, con
  opciones y `VAR=val`), `|&`, ruta del intérprete y exigen fin de palabra; el código une
  `\`+salto de línea antes de casar. Límite: `sudo -u root bash` (opción con valor) y `sh -c
  "$(curl …)"` no los ve Sentinel; los cubre `block-dangerous-commands.sh` (PR2).

Subseccion: Security (E6 #13 y #16)

- **`write-guard` dejaba pasar claves de proyecto de OpenAI, dos herramientas de escritura y todo `.env.example`.** `sk-proj-…` y `sk-svcacct-…` llevan guiones y no casaban con `sk-[a-zA-Z0-9]{20,}`; el matcher de `settings.json` era `Write|Edit`, asi que `MultiEdit` (`edits[].new_string`) y `NotebookEdit` (`new_source`, `notebook_path`) escribian sin escaneo; los ficheros `.env.example/.template/.sample/.dist` estaban exentos aunque contuvieran una clave real; y cualquier excepcion del hook acababa en `exit 0` (permitir). Ahora: patron nuevo para ambos prefijos, matcher `Write|Edit|MultiEdit|NotebookEdit` y el hook lee el campo de cada herramienta; en ficheros exentos siguen bloqueando los secretos de alta confianza (OpenAI, AWS, GitHub, PEM…) salvo que el valor parezca placeholder (`xxxx`, `changeme`, `your-`/`your_`, `<…>`, `example`) y las asignaciones genericas siguen exentas; y el hook falla cerrado: JSON invalido o excepcion → `exit 2` con mensaje en stderr. Cubierto por 16 casos nuevos en `test_guards.sh` (seccion 16). Latencia: 20 invocaciones del hook en 0,56 s (~28 ms cada una, cadena sin cambios de coste). Limites declarados: un valor real al que se le pegue `xxxx`/`changeme` dentro del mismo token en un fichero de ejemplo pasa como placeholder; el fail-closed es solo de `write-guard`: `smart_approve.py` y `stale-read-guard.py` siguen fail-open por diseno.

- **`nucleo_enlazado` mira los tres componentes y la ruta resuelta.** Solo comprobaba `estado/` y
  `nucleo.md`: con `.claude -> /otro/sitio` los hooks de estado inyectaban ficheros ajenos y
  `pre-compact.sh` escribía checkpoints con prompts fuera del repo. Ahora `.claude`, `estado` y
  `nucleo.md` se rechazan si son symlink, y `realpath -m` del nucleo debe quedar dentro de la
  raíz (si no se resuelve, falla cerrado). `session-start-compact.sh` tampoco inyecta un
  checkpoint que sea un enlace. Límite declarado: un `~/.claude` enlazado a propósito (dotfiles)
  desactiva el estado en `$HOME`; `pre-compact.sh` no necesita guarda propia del checkpoint
  porque publica con `mv` (reemplaza el enlace, no escribe a su destino).

- **`<git-hechos>` e `<indice-tareas>` eliminan U+202A-202E, U+2066-2069 y U+2028-2029** (controles
  bidi y separadores de línea) de los datos de repos ajenos. Sin arreglo, declarado: el filtro `clean`
  de `git status` (Claude Code ya ejecuta `git status` en el mismo cwd al arrancar, así que no se
  amplía la superficie); el orden del índice por mtime de un nucleo ajeno solo afecta a la prioridad;
  `agent_id` lo pone el harness.

## [1.2.0] - 2026-09-04

Tres frentes con la misma forma: **protecciones que el repo declaraba y que no existían.** Por
un lado se cierran los guards y el instalador, que fallaban en abierto cuando faltaba `jq`; por
otro los sensores de Headroom, que vigilaban el fichero equivocado o no vigilaban del todo
(`InaccessiblePaths`, el `UMask` de los logs); y por el tercero se retiran afirmaciones
publicadas que dejaron de ser verdad cuando cambió el kit, y se escribe lo que no estaba
escrito. Del inventario solo se mueve una cifra, y es la de los sensores: **27 → 28 suites**,
por el que vigila la capa de permisos. Siguen 11 ADRs, y el conjunto de evals sigue en
20 tareas —10 positivas y 10 negativas— con 32 mutantes.

### Security

- **Los cuatro guards de Bash fallaban en abierto sin `jq`.** `block-dangerous-commands.sh`,
  `branch-guard.sh`, `destructive-guard.sh` y `secret-guard.sh` empezaban leyendo el comando
  con `jq -r … 2>/dev/null` y salían con `exit 0` si el resultado venía vacío. En una máquina
  sin `jq` los cuatro salían con rc=0 y sin imprimir nada: la Capa 1 entera quedaba
  desactivada **en silencio**, que es el peor modo de fallo para un guard, porque el usuario
  cree que está protegido. Ahora los cuatro tienen puerta de dependencia antes de parsear, y
  un payload ilegible deniega en vez de permitir. Se respetan los dos protocolos que ya usaba
  el kit: JSON con `permissionDecision: "deny"` en `block-dangerous-commands.sh` —emitido con
  `printf` cuando no hay `jq`, porque su función `deny()` lo necesita— y stderr con `exit 2`
  en los otros tres, que es el único código que bloquea. `CC_ALLOW_DESTRUCTIVE=1` se sigue
  honrando antes de la puerta.
- **`install.sh` reemplazaba tu `settings.json` cuando faltaba `jq`.** `install_settings()`
  trataba «sin `jq`» igual que «no hay fichero previo»: sobrescribía con la plantilla y dejaba
  un backup. Combinado con el punto anterior, una instalación sin `jq` producía una config con
  los guards inertes. Ahora `install.sh` aborta al principio, con el mensaje y las órdenes de
  `apt`/`dnf`/`pacman`, y no deja `CLAUDE_HOME` a medias.
- **Cinco reglas `Write(...)` de `permissions.deny` eran peso muerto.** Las comprobaciones de
  permisos de fichero solo consultan reglas `Edit(ruta)` —que ya cubren
  Write/MultiEdit/NotebookEdit—; `Write(ruta)` se acepta como válida y se ignora, y el binario
  lo avisa por `stderr` en cada arranque. En `kit/claude/settings.json` las cinco tenían
  gemela `Edit`, así que no había agujero, solo peso, y se retiran las cinco. En
  `config/settings.template.json` y en `.claude/settings.json` sí lo había: un `ask` sobre
  `Write(**/settings.json)` **sin gemela**, es decir una protección que no existía; pasa a
  escribirse `Edit(**/settings.json)`, que es la forma que sí se consulta.
- **Tres de las ocho grafías del push forzado no las paraba ningún glob.** La plantilla y
  `.claude/settings.json` llevaban cuatro globs de `push` contra los cinco del kit: les
  faltaban los dos de banderas cortas agrupadas, así que `git push -uf origin main` caía en el
  kit y pasaba en la plantilla —la que el README manda copiar—. Al escribir el sensor apareció
  un tercer hueco que **ninguno de los tres** ficheros cubría: `git push origin main -fu`,
  agrupadas en posición final con la `f` no última. `* -*f` exige que el token acabe en `f`
  (cubre `-uf`) y `-f* *` solo vale delante del refspec; hacía falta el espejo `* -f*`. Los
  tres ficheros cubren ahora las ocho grafías: dos posiciones —git acepta la bandera antes y
  después del refspec— por larga, corta suelta y agrupada en los dos órdenes. Quedan 8 globs
  en plantilla y proyecto y 6 en el kit.
- **El borrado de una rama remota solo estaba cubierto en su forma larga.**
  `block-dangerous-commands.sh` denegaba `git push --delete`, pero `git push -d` y
  `git push origin :rama` pasaban los cinco guards. Medirlo contra `main` daba cobertura
  completa donde no la había: ahí las tres grafías caen, pero por `branch-guard.sh`, que
  bloquea por el **nombre** de la rama; contra una rama de feature no quedaba nada. Es la
  misma trampa que dejaba pasar `git push -uf`. Cubiertas las tres —y la agrupada `-qd`— con
  **diez** casos `ALLOW` de contrapeso, seis de ellos escritos porque la revisión demostró por
  ejecución que la primera versión del patrón daba falsos positivos: la valla `[^;&|]*` dejaba
  entrar una sustitución de órdenes, un comentario y unos dos puntos entrecomillados, y
  bloqueaba `git branch push-notifications -d`, que no borra nada remoto. Se sustituyó por una
  lista blanca de caracteres de refspec y por exigir que `push` sea un token suelto: 21 de 21
  casos correctos. El precio se declara en el propio hook: una bandera que llegue por
  sustitución —`git push $FLAGS`— sigue siendo invisible, porque el guard lee el literal del
  comando y no `argv`.
- **El kit dejaba de firmar el consentimiento por quien lo instala.** `kit/claude/settings.json`
  viajaba con `skipAutoPermissionPrompt: true`, y `install.sh` lo copia a `~/.claude/`: el kit
  aceptaba de antemano, en nombre de cada persona que lo instalase, el aviso que Claude Code
  muestra antes de conceder permisos automáticos. En un kit cuya tesis son capas que bloquean,
  eso no puede ser el default. Se retira de los tres `settings.json` y el sensor nuevo vigila
  que no reaparezca. Quien lo quiera, lo pone en su config; ya no viene puesto.
- **`doctor.sh` vigilaba el fichero equivocado.** El sensor de conversación en
  claro solo miraba `~/.headroom/logs/proxy.jsonl` y su marca `request_messages`.
  La fuga real la escribe `compression_store` en `proxy.log`, a nivel INFO y con
  `--log-messages` **apagado**, en forma de `payload_preview` de hasta 4096
  caracteres: 592 líneas solo del 2026-09-03, contando las seis franjas de rotación
  (una medición contra una sola franja había dado 100). El sensor estaba verde.
- **La unidad generada no tapaba las credenciales en las máquinas viejas.** La
  plantilla declara `InaccessiblePaths` desde hace tiempo, pero nada re-aplica la
  plantilla y `doctor.sh` solo inspeccionaba `ExecStart=`. Ahora avisa, y lee
  también `headroom-proxy.service.d/*.conf` para no dar verde falso a una máquina
  arreglada con drop-in ni rojo falso a la que lo tiene en la unidad.
- **`UMask=0077` y `HEADROOM_LOG_PAYLOAD_PREVIEW=0` en la unidad.** El proceso
  heredaba `Umask 0002`, así que los logs nacían en 664 y cada rotación los
  volvía a crear así; `chmod` solo arregla el pasado. La variable no se puede
  cambiar en caliente: no está en `_KNOBS_BY_ENV` y el lector consulta
  `os.environ` directo, así que `/admin/runtime-env` no la ve.
- `chmod 700` también a `~/.headroom/logs`, que el `700` del directorio padre no
  cubría.

### Fixed

- **Retirado de la documentación el hook `rtk hook claude`, que el kit ya no cablea.** La
  1.1.0 lo quitó de `settings.json` —reescribía el ejecutable en posición de comando, así que
  `rg` acababa ejecutando `grep`— pero seis ficheros siguieron describiéndolo en presente:
  `kit/docs/03-headroom.md` lo daba como una de las «dos piezas» que conectan el kit con
  Headroom y explicaba su bloque JSON; `kit/docs/08-plugins-mcp-y-skills.md` lo listaba como
  cableado por el kit y como prerrequisito; `kit/docs/10-onboarding.md` pedía `rtk` para que
  los hooks no quedaran en no-op; `CONTRIBUTING.md` lo usaba de ejemplo vivo de
  `optional-hook.sh`; `THIRD-PARTY.md` lo declaraba «envuelto por `optional-hook.sh`»; y
  `kit/doctor.sh` avisaba de que «el hook de `settings.json` queda en no-op». De `rtk` solo
  queda `Bash(rtk *)` en `permissions.allow`: ningún hook lo invoca, así que instalarlo no
  cambia nada y no tenerlo no deja nada a medias. Cada mención pasa a tiempo pasado, con
  fecha y motivo, y `optional-hook.sh` se documenta por lo que sí envuelve: los hooks que
  necesitan el intérprete del venv de tools (Sentinel, `smart_approve.py`,
  `stale-read-guard.py` y `write-guard.py`).
- **Tres cifras publicadas no cuadraban con el `settings.json` que se reparte.**
  `kit/docs/05-security.md` decía que una llamada a `Bash` atraviesa siete hooks `PreToolUse`,
  contando el de `rtk`; son 6 (Sentinel, los cuatro guards y `smart_approve.py`).
  `kit/docs/08-plugins-mcp-y-skills.md` anunciaba ocho plugins con cinco del marketplace
  oficial, y su tabla traía además una fila que `enabledPlugins` no declara
  (`github@claude-plugins-official`): son 7 con 4 oficiales, y la fila se va.
  `kit/docs/10-onboarding.md` hablaba de cinco guards donde hay cuatro. Las tres las derivan
  ahora aserciones nuevas de `kit/test/test_doc_claims.sh` con `jq` sobre
  `kit/claude/settings.json`, en vez de estar escritas a mano. De paso, la cifra de suites que
  arrastraban `CONTRIBUTING.md` y `kit/docs/10-onboarding.md` se pone al día.
- **`kit/docs/04-superpowers.md` se contradecía consigo mismo sobre los agentes.** Su primer
  párrafo metía a los agentes en el mismo saco que superpowers y agent-browser —«el kit los
  documenta, no los redistribuye»— y cuarenta líneas más abajo la tabla de niveles los
  inventaría uno por uno, porque el kit **sí** los reparte en `kit/claude/agents/`. Se acota
  la frase a lo que es de terceros y se remite a esa tabla como el inventario que es.
- **La plantilla `kit/claude/CLAUDE.md` afirmaba en presente dos cosas que no trae el kit.**
  Daba `agent-browser` por «instalado globalmente» y el venv de herramientas por «ya creado»
  —cierto en la máquina del autor, falso en una instalación limpia— y remitía a «los
  subagentes de la tabla de arriba» sin que en el fichero haya ninguna tabla. Pasan a
  instrucción (instálalo, créalo si falta) y a la ruta real, `~/.claude/agents/`.
- **Cerrada la deuda declarada sobre `kit/docs/07-verify.md:84`.** La 1.1.0 dejó dicho que esa
  fila seguía describiendo la fuente del check 5 como un `jq` sobre el `settings.json` del
  usuario cuando el propio release ya había ampliado la fuente, y que ninguna suite grepeaba
  la expresión. La fila describe ahora lo que hace `doctor.sh`: enumera `$PWD`, `$CLAUDE_HOME`
  y cada proyecto de `~/.claude.json`, cruza `settings.json` con `settings.local.json`, suma
  `$ANTHROPIC_BASE_URL` del entorno y falla también si la URL se declara en más de un fichero.
- **Dos líneas de la «Deuda declarada» de la 1.1.0 no se sostienen al re-medirlas.** La
  primera decía que en `block-dangerous-commands.sh` «una línea en el allowlist desactiva
  **todo** el blocklist». Medido con un `$HOME` hermético y un allowlist de una sola entrada
  (`ufw disable`): esa cadena exacta pasa a `allow` y el resto sigue denegado, incluida la
  misma orden con un flag (`ufw disable --force`) y `git push --force origin main`. El alcance
  real es *una cadena exacta exenta de todas las reglas del guard* —`index($cmd)` es igualdad
  de cadena, no un patrón—, y sigue siendo deuda por eso: exime de todas las reglas a la vez
  cuando lo que se quería era eximir un caso. La segunda daba por cerrado el borrado de rama
  remota con el hueco de `--delete`, y medirlo bien destapó lo contrario: la cobertura era
  asimétrica. Contra una rama protegida caen las cuatro escrituras —`--delete`, `-d`,
  `origin :rama` y el `push` normal— con rc=2, pero las bloquea `branch-guard.sh` por nombrar
  la rama, no la regla de `--delete`; contra una rama de feature, la misma acción tenía dos
  decisiones opuestas según cómo se escribiera el flag. Ya no es deuda: se cierra en esta
  misma entrega, arriba, en `Security`.
- **`uninstall.sh --apply` podía escribir sobre el `~/.claude.json` real.** El fichero se
  calculaba a partir de `$HOME` literal mientras todo lo demás se derivaba de `CLAUDE_HOME`,
  así que con `CLAUDE_HOME` apuntando a otro sitio —una prueba, una instalación paralela— el
  desinstalador tocaba la config viva del usuario. Ahora se deriva de `CLAUDE_HOME` y se
  propaga al plan del `--dry-run`, al mensaje final y a `scripts/backup.sh`. En una
  instalación normal el comportamiento es idéntico.
- **El cuarto check de `destructive-guard.sh` bloqueaba sin auditar.** `find … -delete` sobre
  ruta amplia salía con `exit 2` pero no llamaba a `log_block`, cuando los tres checks
  anteriores sí: el log de auditoría mentía por omisión justo en el caso más destructivo.

### Documentation

- **Documentada la capa de permisos que corre antes de todos los hooks.** `SECURITY.md`
  describía la Capa 1, la Capa 2 y Sentinel, pero no las reglas `permissions.deny` de
  `settings.json`, que evalúa Claude Code **antes** de que ningún hook vea la llamada y son
  las que impiden que una sesión desarme sus propias barreras editándolas. Se documentan las
  tres familias que cubren (los borrados de la raíz y de `$HOME` más el `git push --force`,
  los dos métodos de escritura del MCP de LinkedIn, y la configuración del propio kit), su
  complemento en el `PROTECTED_CONFIG` de Sentinel, y las dos trampas medidas hoy sobre
  Claude Code 2.1.259: las comprobaciones de fichero **solo** consultan reglas `Edit(ruta)`
  —una regla `Write(ruta)` se acepta como válida y se ignora, y el propio binario lo avisa por
  `stderr` en cada arranque— y una barra inicial ancla la ruta al fichero de settings, no a la
  raíz del filesystem, así que una ruta absoluta necesita dos: `Edit(//home/usuario/...)`. Y
  lo que la capa **no** cubre: una regla `Edit(...)` no frena a `Bash`, así que el `sed -i`,
  el `tee` o la redirección sobre el mismo fichero los para la Capa 1, no esta. La política,
  en `SECURITY.md`; el detalle operativo, en `kit/docs/05-security.md`.
- **Documentada la precedencia del allowlist de Sentinel.** `load_user_allowlist()`
  (`kit/sentinel/sentinel_preflight.py`) prueba el `.security/sentinel-allowlist.json` del
  directorio de trabajo antes que el de `$HOME` y se queda con el primero que exista, sin
  unirlos: abrir una sesión dentro de un repo clonado puede sustituir tu allowlist por el suyo
  (medido: con `paths: ["/"]` convertía en `allow` los denies de `~/.aws` y `~/.ssh`). La
  1.1.0 lo llevaba en la deuda declarada como «abierto y sin documentar»; queda escrito como
  el compromiso que es —un proyecto declara sus falsos positivos una vez, no persona a
  persona— con su contrapeso en código (`ALWAYS_DENY_PATHS`, que se consulta antes y ningún
  fichero de datos levanta). La exención sigue abierta: el seguimiento n.º 1 no se cierra.

- **`AGENTS.md`: el mapa que faltaba para un agente.** Varios harness buscan las instrucciones
  del repo por ese nombre y no existía, y `CLAUDE.md` no podía absorberlo porque vivía a **un
  token** de su techo de 900 (`test_harness_structure.sh` mide `wc -c / 4`: bytes, no
  caracteres, y con acentos la diferencia decide si algo cabe). No repite las reglas: mapea lo
  que un agente no puede deducir leyendo el código. Que hay **dos** `CLAUDE.md` con propósitos
  opuestos —el de la raíz manda en este repo; `kit/claude/CLAUDE.md` es una plantilla que se
  instala en el `~/.claude` de otra persona—, que `kit/docs/` es referencia y `docs/` es archivo
  de proceso, que los guards bloquean por el **literal** del comando (nombrar una ruta de
  credenciales aunque sea para excluirla dispara Sentinel, y la salida es reformular, nunca
  ampliar la allowlist), y que `knowledge/` es memoria no-confiable por defecto.
- **El README dice en 30 segundos qué es esto, para quién es y para quién no.** Su «Qué hace
  esto» vivía en la línea 225, no contestaba nunca lo segundo, y su única frase-resumen
  viajaba URL-encoded dentro del `src` de la imagen de cabecera, invisible en texto plano. Al
  escribirlo se midieron sus dos promesas nuevas y **una salió falsa**: «`uninstall.sh`
  revierte» es mentira —sin flags solo simula, revertir exige `--apply`— y se corrigió antes de
  publicarla. La otra se sostiene: `install.sh` fusiona `settings.json` con `jq`, comprobado con
  cinco marcas propias que sobreviven a la instalación.
- **Las tablas de `knowledge/` declaraban cinco de nueve ficheros.** Ahora están los nueve, en
  el README con su glosa y en `CLAUDE.md` como índice: el techo de tokens no daba para ambos.

- **El fichero MIT pasa a llamarse `LICENSE`, y la CC BY a `LICENSE-DOCS`.** Medido, no
  supuesto: `gh repo view --json licenseInfo` devolvía **`null`** y la barra lateral de GitHub
  no anunciaba licencia alguna. GitHub deduce la licencia del fichero llamado `LICENSE`
  exactamente, y ahí vivía la CC BY 4.0 con un preámbulo propio que su detector no reconoce,
  así que el MIT que cubre `kit/` era invisible. Un repo que aparenta no tener licencia se lee
  como *todos los derechos reservados*, que es lo contrario de lo que este repo quiere. El
  reparto de fondo no cambia —software MIT, charlas CC BY 4.0—, solo qué fichero lleva cada
  nombre; se actualizaron las cuatro referencias cruzadas (los dos preámbulos, la tabla del
  README y `THIRD-PARTY.md`) y el README explica ahora por qué el nombre importa, para que
  nadie lo «arregle» de vuelta.

### Testing

- **Un sensor que mantiene honesto a `AGENTS.md`.** El valor entero de ese fichero está en su
  tabla de rutas, así que una ruta muerta no es un detalle de estilo: manda al agente a leer
  nada y le hace creer que ya lo leyó. El check vive en `test_doc_claims.sh` —que ya es el
  guardián de las afirmaciones— en vez de en una suite nueva, que habría cambiado el recuento
  declarado en tres documentos; comprueba las rutas que el mapa cita y trae su propia
  falsabilidad. Verificado contra el fichero **real**, no solo con un fixture: inyectando una
  ruta inexistente la suite sale rc=1, y al restaurarla vuelve a verde.
- **Doce hallazgos `SC2016` que tumbaban la CI, declarados uno a uno.** El job de `shellcheck`
  corre con severidad por defecto, así que un `note` lo tumba igual que un error. Los doce
  (medidos: 10 en `test_doc_claims.sh`, 2 en `test_guards.sh`) son casos donde las comillas
  simples **son** el punto: el payload debe llegar literal al guard, o el patrón buscar
  backticks de markdown, o el test deja de medir lo que dice medir. Se declaran con once
  directivas por línea, cada una con su motivo, en vez de una exención de fichero: así un
  `SC2016` futuro que sí sea un error no queda tapado. Colocarlas mal cuesta más que el
  hallazgo — una entre un `done` y su heredoc rompió el parseo del fichero entero (`SC1123`
  más `SC1009`/`SC1073`/`SC1072`): la directiva precede al **comando compuesto completo**.

- **Siete aserciones nuevas en `kit/test/test_doc_claims.sh`.** Seis comprobaciones derivadas
  del árbol en vez de escritas a mano: la longitud de la cadena `PreToolUse` sobre `Bash` que
  publica `kit/docs/05-security.md`, el total de `enabledPlugins`, cuántos son del marketplace
  oficial, que ningún plugin nombrado en la doc falte de `enabledPlugins` (así se cazó la fila
  fantasma), el número de guards que citan dos documentos, y que ningún hook del kit cablee
  `rtk hook claude` ni ninguna línea del árbol versionado lo afirme en presente —las menciones
  históricas tienen que ir marcadas como tales—. La séptima es su sonda de falsabilidad:
  deforma copias del `settings.json` y de los documentos con las siete averías que esas
  comprobaciones persiguen —la cadena con otra cifra y sin cifra, un hook de más, el plugin
  fantasma, el plugin retirado del settings, la frase de `rtk` en presente— y exige que se
  queje de todas, más un contrapeso en pasado que debe aprobar. La suite pasa de 31 a 44
  aserciones sin aflojar ninguna de las anteriores.

- **Sensor nuevo para la capa de permisos: `kit/test/test_permisos_efectivos.sh`.** Ata las
  tres cosas que la auditoría encontró sueltas, sobre los tres `settings.json` que el repo
  publica: que ninguna regla `Write(...)` viva sin su gemela `Edit(...)` —o la protección no
  existe—, que no reaparezca `skipAutoPermissionPrompt`, y que **alguna** regla `deny` empareje
  cada una de las ocho grafías del push forzado. Esta tercera nació contando reglas —«que la
  plantilla no tenga menos globs que el kit»— y así se quedaba verde con cinco reglas de las
  que ninguna paraba `-uf`: un check que mide un literal en vez del comportamiento. Ahora
  empareja de verdad, con el glob de bash sobre el comando, y por eso encontró el hueco de
  `-fu` que arriba se cierra. Trae sus tres casos fabricados para demostrar que distingue el
  par bien formado del huérfano; el del tercer check quita los dos globs de banderas agrupadas
  y exige rojo en `-uf` y verde en `-f`, o sería el sensor que reemplazó. Probada en rojo dos
  veces: mutando la plantilla al glob equivocado —`-f*` por `-*f`, **mismo número de reglas**,
  el defecto que de verdad hubo— da 2 failed y `rc=1`, donde el recuento habría aprobado; y
  escondiendo `config/settings.template.json`, 24 passed / 3 failed y `rc=1`. Los tres ficheros
  son invariantes del repo, así que su ausencia **falla** en vez de pasar por vacío: un sensor
  que aprueba cuando no encuentra su entrada es un sensor inerte. 34 aserciones.
- **Los sensores de los cuatro arreglos, todos probados en rojo antes que en verde.**
  `test_clean_install_resilience.sh` cambia un recuento ciego de reglas `deny` por un conjunto
  comprobado entrada por entrada, y añade el caso que faltaba: un `PATH` sin `jq` donde los
  cuatro guards tienen que denegar un comando inocente y el instalador tiene que abortar sin
  dejar `CLAUDE_HOME` a medias (12 → 24 aserciones). `test_install_settings_merge.sh` reescribe
  el caso de «sin `jq`» al comportamiento nuevo: aborta, tu `settings.json` queda intacto y no
  hay backup (23 → 25). `test_guards.sh` cubre el bloqueo auditado del cuarto check y las
  cuatro grafías del borrado remoto con sus diez contrapesos `ALLOW` (49 → 65); contra el
  guard anterior, cuatro de esos casos pasaban, y seis de los `ALLOW` son falsos positivos que
  la revisión encontró en la primera versión del patrón. `test_uninstall.sh` estrena un caso
  con `HOME` y `CLAUDE_HOME` distintos, la única forma de ver el defecto (16 → 18).
- **CI: lo que se medía a medias.** `shellcheck -x` pasa de 42 a 50 ficheros, porque la lista
  se saca de `git ls-files` en vez de escribirse a mano. Se añade `compileall` sobre los 13
  `.py` versionados: un `SyntaxError` en un hook sale con `exit 1`, y como solo `exit 2`
  bloquea, un guard roto era un no-op silencioso. Se comprueba que el pin de `gitleaks`
  —versión y sha256— coincide con el de `kit/install.sh`, y se retira el escaneo redundante.
  `concurrency` cancela ejecuciones solapadas fuera de `main`. Los tres nombres de job se
  conservan byte a byte: son los contextos que exige la protección de rama, y renombrarlos la
  rompería en silencio.

## [1.1.0] - 2026-09-02

El repo pasa de ser solo un instalador endurecido a ser también un **harness**: guías
(lo que se dice antes de actuar) y **sensores** (lo que mide después), en el sentido de
Birgitta Böckeler (*Harness engineering*, 02-abr-2026). Lo nuevo vive en la raíz, pero
`kit/` no queda intacto: suma 38 ficheros nuevos —el subsistema de evals con sus casos
y sus pruebas— y 41 ficheros de v1.0.0 retocados, `install.sh` entre ellos. El árbol
corre hoy 27 suites de test, frente a las 16 de v1.0.0.

### Added

- **El hallazgo que reordenó el trabajo: el canal de Bash reescribe los comandos.**
  El hook `PreToolUse/Bash` sustituye el ejecutable en posición de comando — `rg` ejecuta
  `grep`, `python3 -m pytest` ejecuta `python3 -m rtk`. Bash acumula **6.093 llamadas a
  herramienta** en el snapshot del 2026-08-21 (2.410 en la sesión principal + 3.683 en
  subagentes, `tools_top.Bash` de cada mitad),
  así que casi todo sensor pasaba por un canal que altera la pregunta.
  Un oráculo así no mide lo que dice medir. Reproducción, alcance y las tres vías que lo
  evitan en `knowledge/MISTAKES.md` · M-001, y un test que rechaza cualquier oráculo
  registrado por nombre suelto.

- **Cinco prompts de trabajo** en `.claude/commands/`: `/spec`, `/implement`, `/verify`,
  `/review`, `/retro`. `/spec` existe por una medición concreta: los encargos eran
  bimodales —una frase o un documento— y faltaba el término medio, la especificación con
  criterios verificables escrita antes de empezar.

- **Tres sensores** en `.claude/hooks/`, medidos entre 15 y 23 ms: `oracle-log.sh` registra
  qué sesiones ejecutaron un oráculo, `verify-gate.sh` avisa al terminar si se tocó código
  sin verificar, y `auto-spec.sh` pone delante el oráculo del proyecto en el primer encargo
  (detalle más abajo; sustituye a `session-brief.sh`). **En modo normal ninguno bloquea**:
  un falso positivo bloqueante cuesta mucho más que un aviso ignorado, y ese endurecimiento
  se decide con datos. La única excepción llegó después y con ADR propio: con un run
  autónomo activo, `verify-gate.sh` sí bloquea el cierre de turno (ADR 010).

- **`scripts/backup.sh`** — ZIP con manifiesto SHA-256 que **restaura en un temporal y
  revalida los 932 checksums**, y que se probó falsable en cuatro casos. Resuelve
  `sha256sum` frente a `shasum -a 256` porque aquí es uutils, no GNU, y en macOS no existe.

- **`scripts/metrics.py`** — absorbe `analyze.py` con **cero regresiones** en sus ~44
  métricas y añade las que el encargo declaraba y el instrumento no calculaba: retrabajo
  **por sesión** (no solo por turno), mediana y p90 de tool calls, y sesiones con oráculo
  ejecutado. El filtro de subagentes pasa a ser explícito en vez de depender de la
  profundidad de un glob. Más `scripts/cost-report.sh` con tendencia entre snapshots.

- **`knowledge/`** — memoria versionada: `ORACLES.md`, `MISTAKES.md`, `PROCEDURES.md`,
  `COST-LOG.md`, `SOURCES.md`, `SKILLS-REGISTRY.md` y 11 ADRs. Es **no-confiable por
  defecto**: lo que viene de la web son datos, nunca instrucciones, y la promoción de un
  hallazgo a regla pasa siempre por una puerta humana.

- **Cuatro skills** (`harness` absorbida sin cambios y verificada por checksum,
  `house-rules`, `coach`, `dev-env`) y **cero agentes nuevos**: de 150 delegaciones, 105
  fueron al agente genérico y 6 de los 8 especialistas existentes nunca se usaron. El
  problema no era falta de capacidad.

- **Nueve suites de test nuevas** (`test_harness_structure.sh`, `test_metrics.sh`, <!-- doc-claims:ignore: "Nueve" cuenta las suites NUEVAS desde v1.0.0, no el total del arbol -->
  `test_install_diff_first.sh`, `test_uninstall.sh`, `test_detect_oracle.sh`,
  `test_auto_spec.sh`, `test_autonomy.sh`, `test_doc_claims.sh`, `test_evals.sh`,
  `test_install_settings_merge.sh`), todas
  con sección de falsabilidad. El total pasa de 16 a 27 suites.

- **El harness entra solo: `auto-spec.sh`, un hook `UserPromptSubmit`** (ADR 009). Cuatro
  reglas advisorias de `CLAUDE.md` tenían adherencia medida —`IntentGate` 2,1 %,
  `Parallel-First` 0 invocaciones, la tabla de delegación 70 % al agente genérico, "verifica
  tu trabajo" 27,7 % de sesiones con oráculo—: pedir disciplina no la produce. El hook
  clasifica el prompt y **solo** si es un encargo sin criterio de verificación inyecta la
  petición de declarar qué será cierto al terminar, el oráculo del proyecto detectado por
  `scripts/detect-oracle.sh` y el recordatorio de ejecutarlo en frío; si el criterio ya viene
  escrito, se calla. Emite **stdout plano**, que es lo único que la documentación especifica
  para este evento, y **nunca `exit 2`**, que borraría el prompt recién escrito. Verificado en
  `test_auto_spec.sh` con 16 checks —incluido el de falsabilidad: un encargo y una pregunta
  tienen que producir salidas distintas— y 23 ms de latencia medida.
- **Modo autónomo: `/work` y `scripts/autonomy.sh`** (ADR 010). Un sexto prompt de trabajo en
  el que el usuario entra **una sola vez** (una tanda de preguntas agrupada más la aprobación
  de la spec); a partir de ahí, cada pregunta es un fallo de diseño. No aparece un hook nuevo:
  `verify-gate.sh` gana un segundo modo, y con un run activo un oráculo en rojo **bloquea**
  (`decision: block`) con un presupuesto de 3 reparaciones. El ADR 004 decidió que nada
  bloquea porque un aviso le llega a un humano que reacciona, y esa es justo la premisa que
  desaparece en un run desatendido. El motivo devuelto al modelo prohíbe explícitamente tocar
  el sensor, y `autonomy.sh start` rechaza oráculos que no sean ruta absoluta, `rtk proxy …` o
  `make …`, porque el canal de Bash sustituye el ejecutable (M-001) y verificar con el comando
  equivocado es peor que no verificar: parece que sí. Los cuatro estados —rojo, verde,
  presupuesto agotado y `stop_hook_active`— están cubiertos en `test_autonomy.sh`.

- **`THIRD-PARTY.md`** con los avisos de terceros, que faltaban. Reproduce íntegro
  el aviso MIT de `yurukusa/claude-code-hooks` (`Copyright (c) 2026 yurukusa`,
  verificado contra el `LICENSE` del repositorio de origen), del que derivan
  `branch-guard.sh`, `destructive-guard.sh` y `secret-guard.sh`: la MIT exige que
  ese aviso viaje con las copias y hasta ahora solo había una línea `# Source:`.
  Distingue código derivado de dependencias externas no redistribuidas —gitleaks
  (MIT), Headroom (Apache-2.0) y rtk (Apache-2.0), las tres comprobadas contra la
  API de GitHub—, porque mezclarlas desdibuja qué hay que cumplir de verdad.
- **Queda documentado un punto de procedencia sin resolver.**
  `block-dangerous-commands.sh` declara en su cabecera derivar de
  `randomdreft/claude-code-security-hook` *"(public domain)"*, pero ese
  repositorio **no tiene fichero de licencia** (`license: null` en la API de
  GitHub) y el dominio público no se presume. No se corrige inventando otra
  afirmación: se registra el hecho verificable y las tres vías para cerrarlo.

- **`.github/dependabot.yml`** para el ecosistema `github-actions`. El CI ancla
  las Actions por SHA, que es lo correcto, pero un pin no se actualiza solo: sin
  esto se quedan clavadas en la versión anclada, incluidas las vulnerabilidades
  que se les descubran después.


- **El eval set pasa de medir ruido a medir comportamiento, y de 6 casos a 20 tareas**
  (10 positivas / 10 negativas).
  Que la mitad sean casos negativos es deliberado: sin ellos, un harness que dice que sí
  a todo puntúa igual que uno que discrimina. Correrlo cuesta
  dinero, así que nunca se había corrido entero y nadie había visto que tenía un falso
  negativo y un falso positivo estructurales.

- **Brazo de control (`ARM=off`, que añade `--safe-mode`) y las tres preguntas separadas.**
  Sin control no hay *lift*: "acierta 0,85" no dice nada si no se sabe qué acierta sin el
  harness puesto. El informe responde por separado *¿funciona?*, *¿sirve?* y *¿a qué
  coste?*, y no mete nunca el precio dentro de la nota.

- **Ablación por componente: tres brazos más** (`sin-ajustes`, `sin-skills`, `sin-mcp`),
  cinco en total contando `on` y `off`. El *lift* dice si el harness sirve; no dice **qué
  pieza** sirve. Medido en la tirada del 2026-08-27: `sin-ajustes` cuesta −0,17, más que
  el lift entero; `sin-skills` y `sin-mcp` salen `SIN DATOS` porque en esa tirada no se
  activó ni una skill ni un servidor MCP, y el informe dice que correrlos no mediría
  nada en vez de publicar un cero.

- **Tareas mudas: el conjunto declara cuándo dejó de informar** (E16). `report.py` cuenta
  las que dieron el mismo resultado en los dos brazos y en todas sus repeticiones —no
  pueden mover el lift— y escribe `SATURADO`. En la tirada del 2026-08-27 son mudas 17 de
  20 tareas: el conjunto que decide es de tres, no de veinte. Con un solo brazo el bloque
  escribe `NO MEDIBLE` en vez de "0 mudas", porque sin control un cero sería mentir por
  omisión.

- **La máquina es una variable experimental, no un decorado** (E14). `record.py` apunta de
  cada tirada el modelo, el sha, el coste, los turnos, la carga, las CPUs y la memoria
  libre; `report.py` avisa si los brazos corrieron con la máquina en estados distintos, y
  su guardia hermano `comparables()` escribe `NO COMPARABLE` en vez de restar dos brazos
  que corrieron modelos distintos.

- **`make mutantes`: 32 mutantes versionados (M9–M40)** que rompen a propósito un sensor
  del eval cada vez y exigen que la suite se ponga roja. Un sensor que no ha suspendido
  nunca no se sabe si sabe suspender. Tarda unos 4 minutos y no cuesta dinero.

- **`DRYRUN=1` y filtro por tarea** (E29). El coste de una tirada se estima **antes** de
  pagarla y a partir de lo ya gastado (`kit/evals/runs.jsonl`), no de una cifra escrita a
  mano: el `Makefile` decía "40 llamadas / ~12 USD". Salvedad medida: `runs.jsonl` está en
  `.gitignore`, y sin él el ensayo sigue contando llamadas pero no puede estimar dólares.

- **Dos puentes al observatorio, ninguno con Docker ni licencia**: `langsmith_push.py`
  —nube o receptor local en `:1984`, con `make langsmith-local` y `make langsmith-arbol`—
  y `phoenix_push.py` con `make phoenix`, que levanta una interfaz web en `:6006`. La
  telemetría se prueba contra algo que escucha, no en seco.

- **Una fila con el instrumento averiado y sin evidencia se retira, no se corrige**
  (`excluded` en `runs.jsonl`). Queda fuera de todo cómputo, el informe lo anuncia en su
  primera línea en vez de retirarla en silencio, y queda fuera también de los dos puentes:
  ni `langsmith_push.py` ni `phoenix_push.py` la publican, y ambos lo dicen por `stderr`.
  Publicarla allí la habría devuelto por la puerta de atrás, enseñada como un `fail`
  normal.

- **`knowledge/EVAL-CRITERIA.md`: 29 criterios de calidad del eval**, cada uno con su
  fuente y su estado honesto, y **ADR 011**, que decide no migrar a OpenHarness. Las cifras
  que ese documento publica se derivan de `runs.jsonl` en tiempo de test; sin el almacén
  —gitignorado— esas aserciones pasan a `skip`, no a `ok`.

- **`kit/doctor.sh` era ciego justo donde se produce el daño, y la garantía de la fusión no
  tenía sensor.** El check de fuente única de `ANTHROPIC_BASE_URL` solo recorría el ámbito de
  usuario, pero el que multiplica fuentes es `headroom wrap`, que escribe en
  `$PWD/.claude/settings.local.json` — ámbito de **proyecto**. Ahora enumera también los
  proyectos que Claude Code registra en `~/.claude.json`, deduplicando por ruta de fichero (en
  un `$HOME` declarado como proyecto, el fichero de proyecto y el de usuario son el mismo, y
  sin dedupe una sola fuente contaba dos veces y daba un FAIL falso), e informa de `ruta:línea`
  de cada fuente. Un check nuevo vigila `statusLine`: resuelve el ejecutable real del comando
  saltando el intérprete, FALLA si no existe o no es ejecutable, avisa si no imprime nada o
  sale con código distinto de 0 —el modo de fallo que Claude Code silencia por completo— y
  calla si no está declarada, porque el kit no la instala. Y suite nueva
  `test_install_settings_merge.sh`: 23 aserciones sobre la fusión de `settings.json`, con el
  caso del incidente verificado por mutación (al revertir la fusión a la copia entera, la
  suite cae con 5 fallos, el primero por `statusLine` ausente).

### Changed

- **`sentinel-allowlist.json`: fuera los tres dominios de LinkedIn**, que quedaron muertos al
  retirar ese MCP. Es **higiene, no endurecimiento**, y conviene no venderlo como otra cosa:
  la allowlist de Sentinel solo hace que una URL *salte* las heurísticas de red (pastebin,
  TLD sospechoso, IP cruda), así que `linkedin.com` las pasaría igual estando o no en la
  lista. Lo que se gana es que la config deje de describir un servidor que ya no existe.

- **`CLAUDE.md`** de proyecto: 76 líneas / ~895 aprox-tokens, bajo el presupuesto que
  verifica `test_harness_structure.sh` (<100 líneas, <900 aprox-tokens). La auditoría que lo justifica está en `knowledge/AUDIT-CLAUDE-MD.md` y se apoya
  en uso medido: la sección más larga del fichero anterior regía un plan mode al 2,1 %.

- **`kit/install.sh`** pasa a ser *diff-first por detección*: si `$CLAUDE_HOME` es un repo
  git con remoto —el caso real del autor, con 138 ficheros sin commitear— no escribe;
  genera el árbol aparte, muestra el diff y dice qué commitear. `--apply` fuerza. En un HOME
  temporal sin git el comportamiento es el de siempre, así que ni las suites ni CI cambian.

- **El presupuesto de `timeout` de los hooks deja de ser un número plano.** Los 5 s protegen
  el **camino caliente** (`UserPromptSubmit` en cada prompt, `PostToolUse` en cada llamada a
  herramienta), donde cada milisegundo se paga cientos de veces. El `Stop` no está en ese
  camino y en modo autónomo su trabajo *es* ejecutar el oráculo: declararlo a 5 s no lo hacía
  barato, lo hacía **inútil**, porque Claude Code mataba el hook antes de que el oráculo
  terminara (`make test` tarda ~30 s) y el gate fallaba **en abierto**, dejando cerrar el
  turno con el oráculo en rojo. Ahora se declara a 600 s y `test_harness_structure.sh` exige
  la regla de verdad: un `Stop` nunca puede declarar menos que el `timeout` que se aplica a
  sí mismo por dentro, con su propio check de falsabilidad.

- **El estado del modo autónomo se indexa por directorio de proyecto, no por `session_id`.**
  Quien arranca el run es el modelo desde Bash, y ahí el `session_id` no existe: solo aparece
  dentro del payload del hook. Con la clave anterior, `autonomy.sh start` escribía en un
  fichero y el Stop hook leía otro, así que el gate no encontraba run y caía a modo normal.
  **Fallaba en abierto y en silencio**, que es la peor forma de fallar en un mecanismo de
  seguridad.


- **`report.py` deja de dar un número desnudo.** Cada tasa va con su intervalo de Wilson al
  95 %, el veredicto se decide por bandas (`SIRVE` ≥ +0,05, `PERJUDICA` ≤ −0,10, `NEUTRO`
  en medio) y las salvedades que matan una cifra —`AVISO` de máquina distinta, `SATURADO`,
  `NO COMPARABLE`, `NO MEDIBLE`, `SIN DATOS`— salen pegadas a ella, no en una nota al pie.

- **`kit/Makefile` delega en la raíz.** El Quick start deja al lector dentro de `kit/` y le
  manda `make test`; sin Makefile ahí, `make` encontraba el **directorio** `kit/test`, lo
  tomaba por un target ya construido y respondía "Nothing to be done for 'test'" con exit
  0: un oráculo que devuelve 0 sin ejecutar nada, en un repo cuya tesis es la contraria.

### Removed

- **`session-brief.sh`**, sustituido por `auto-spec.sh` (ADR 009). Su función —poner delante
  el oráculo del proyecto y los errores ya cometidos— se hace ahora en el primer *encargo* y
  no en el arranque, donde se diluía y no sobrevivía a un `/clear`. **El presupuesto se
  mantiene en 3 hooks**: se sustituye, no se suma.

### Fixed

- **Reinstalar el kit destruía la configuración personal de quien ya lo tenía.** Medido en una
  máquina real: un `install.sh --apply` sobre una instalación existente reemplazaba
  `settings.json` entero y se llevaba en silencio `ENABLE_TOOL_SEARCH` (que vale ~30k de
  contexto por sesión), el `ANTHROPIC_MODEL` con el sufijo de la ventana de 1M,
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW`, tres límites más, el `statusLine` y tres hooks; y
  reemplazaba `CLAUDE.md`, que es prosa escrita a mano. Había backup, pero un backup que hay
  que descubrir no es una salvaguarda: es una autopsia. Ahora `settings.json` se **fusiona**
  con una regla declarada — los `hooks` los pone el kit, los `permissions` se unen (nunca se
  pierde un `deny` ni un `allow`), tus claves de `env` ganan y el kit solo añade las nuevas, y
  todo lo demás es tuyo e intacto — y `CLAUDE.md` no se pisa: la del kit queda al lado como
  `CLAUDE.kit.md`.
- **El kit no distribuía tres hooks que sí corrían en producción**, así que instalarlo los
  borraba y un clon limpio nunca los tenía: `write-guard.py` (secretos en el contenido que se
  escribe), `narthex-post-mcp.py` (unicode invisible y frases de jailbreak en respuestas de
  MCPs de terceros) y `preflight.sh` (recupera el proxy por systemd). Los tres son portables
  y ya están registrados vía `optional-hook.sh`.
- **La capa de IOCs de Sentinel venía apagada de fábrica.** El kit solo traía
  `iocs.example.json`, así que cada instalación arrancaba sin los 31 patrones de ruta
  sensible, 12 de comando peligroso y 30 de red — con un `WARN` que nadie lee. Ahora se
  distribuye `iocs.json` completo, con su allowlist en `~/` y no en el home de nadie.

- **Lo que impide que la documentación mienta no corría en CI, y nada lo declaraba.**
  `test_doc_claims.sh` y `test_evals.sh` quedaban fuera del pipeline: El `Makefile` corría 25 y `ci.yml` 23: las ausentes eran `test_doc_claims.sh`
  y `test_evals.sh`, así que un PR que rompiera una cifra del README pasaba en verde. Y el
  hueco podía volver, porque el único sensor comparaba `kit/test/` contra el *target* del
  Makefile, nunca contra CI. Se añaden a `ci.yml` y `test_harness_structure.sh` gana una
  sección de paridad `Makefile ↔ ci.yml` con su caso de falsabilidad.
- **La unidad systemd que genera `install.sh --with-headroom` reproducía dos bugs ya
  diagnosticados**: sin `%h/.local/share/rtk` en `ReadWritePaths`, SQLite da *"unable to open
  database file (code 14)"* cada 60 s; sin `HF_HUB_OFFLINE=0`, el motor de compresión queda
  `available:false` **en silencio** mientras `/readyz` sigue diciendo `healthy`.
- **Tres tests medían la máquina de quien los ejecutaba, no el repo.** `test_doctor.sh` y el
  `run_doctor()` de `test_doctor_base_url.sh` no aislaban `HOME`; y `kit/scan-secrets.sh`
  escaneaba ficheros *ignorados* por git, así que `test_harness_structure.sh` daba rojo en una
  máquina con scratch en disco y verde en CI, donde el clon está limpio. Misma lección que
  `628dfaa`.
- **`.claude/skills/dev-env/SKILL.md` afirmaba que un `ANTHROPIC_BASE_URL` en `settings.json`
  desactiva la ventana de 1M, el tool search y remote-control.** Dos de las tres son falsas,
  medido dentro de una sesión enrutada: solo `/remote-control` cae. Y recomendaba
  `headroom wrap claude`, que escribe la variable en el `settings.local.json` del proyecto y
  la repone con un hook `SessionStart` — el mecanismo que dejó `ANTHROPIC_BASE_URL` en 5
  ficheros no declarados y el enrutado dependiendo del `cwd`.
- **`hooks/stale-read-guard.py` estaba en producción sin viajar en el kit.** Se añade y se
  registra vía `optional-hook.sh --python`. Su propia instrumentación mide por qué importa:
  las relecturas eran el mayor desperdicio identificado del presupuesto de tokens, mayor que
  todo lo que comprime el proxy.
- **Se retira `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=75` de la plantilla de `settings.json`.** Es un
  hook de pruebas del cliente, no un ajuste soportado: en la ruta de 200k regala ~32k de los
  180k usables, y en la de 1M es inerte. La máquina de referencia ya lo había abandonado; la
  plantilla se había quedado atrás.

- **El guard de force-push no veía los flags cortos agrupados.** `git push -uf origin main`
  fuerza de verdad, pero no contiene `-f` como token suelto, así que el patrón anterior
  (`-f\b`) lo dejaba pasar — justo la protección que el kit anuncia como dura. Pasaba en las
  **dos** capas: el hook `block-dangerous-commands.sh` y los globs de `permissions.deny` en
  `settings.json`, que `smart_approve.py` evalúa. Ahora se acepta cualquier grupo de flags
  cortos que contenga una `f` (en `git push` la única opción corta con `f` es `--force`), y
  `--follow-tags` sigue pasando porque tras el guion viene otro guion, no letras. Cinco casos
  de regresión nuevos en `test_guards.sh`, que pasa de 28 a 33 checks.
- **La Capa 2 de secretos bloqueaba *todos* los commits de cualquier repo protegido que no
  tuviera `.gitleaks.toml` propio.** El hook `pre-commit` pasaba a ciegas
  `-c "$REPO_ROOT/.gitleaks.toml"`; si el fichero no estaba, gitleaks abortaba con
  `unable to load gitleaks config` y el commit moría — un fallo cerrado que parece un
  hallazgo de secreto. Ahora resuelve la config en orden (repo → `$CLAUDE_HOME`) y, si no
  hay ninguna, avisa por stderr y sigue con las reglas por defecto de gitleaks en vez de
  abortar. **El fixture del test tapaba el bug**: copiaba la config a la raíz del repo de
  prueba, un escenario que un usuario real no tiene. Ya no la copia, y hay tres casos nuevos
  (`test_secret_content_gitleaks.sh`, 20 checks) incluido el que importa: sin config en
  ninguna parte, un commit limpio pasa y una credencial AWS real sigue bloqueada.
- **`make test` desde `kit/` devolvía exit 0 sin ejecutar un solo test.** El Quick start deja
  al lector dentro de `kit/`, donde no había `Makefile`: make encontraba el *directorio*
  `kit/test`, lo tomaba por un target ya construido y respondía "Nothing to be done for
  'test'". Un oráculo que devuelve 0 sin medir nada, en el repo cuya tesis es lo contrario.
  `kit/Makefile` delega ahora en la raíz.
- **`test_autonomy.sh` seguía probando un contrato que ya no existía.** El estado del modo
  autónomo pasó a indexarse por directorio de proyecto y no por `session_id` (quien lanza el
  run desde Bash no conoce el `session_id`), y la suite seguía arrancando los runs con
  `--session`. Reescritos los ocho bloques del gate: el run se arranca como lo arranca el
  modelo, y cada payload lleva a propósito un UUID distinto, de forma que una regresión al
  indexado por sesión se caería en rojo en vez de dejar cerrar el turno con el oráculo rojo.
- **`test_guards_falsifiability.sh` comprobaba `> 0` caídas y citaba una constante que no
  existía.** Una regresión que bajase de 10 casos `BLOCK` a 1 pasaba en verde, y el 10 que
  el README publica como hecho medido no estaba anclado en ninguna parte. Ahora
  `STUB_BLOCK_CASES=10` es explícito y la suite exige esa cifra exacta.
- **El sensor de frescura de `SOURCES.md` leía el número de fila como si fueran días,
  y tumbaba `make test` entero.** En `source_field` el patrón de la ventana llevaba el
  sufijo de unidad como opcional — `(d|dias|días)?` — así que casaba con la primera
  columna numérica de la fila, que es el `#` de orden. Las filas 1 a 4 salían
  "vencidas sin marcar `[STALE]`" por su posición en la tabla, no por su fecha:
  `| … | 2026-08-21 | 365 d |` se leía como una ventana de 4 días. Como
  `test_harness_structure.sh` es la antepenúltima suite del `Makefile` y make aborta en el
  primer fallo, **las dos últimas suites (`test_install_diff_first`, `test_uninstall`)
  llevaban tiempo sin ejecutarse**: 21 de 23. Con la unidad obligatoria, las 23 corren y
  `make test` vuelve a exit 0.
- **El check de falsabilidad de ese sensor pasaba sin cubrir el bug que tenía delante.**
  Su fila fabricada era `| url | primaria | fecha | 30 |`: sin columna `#` y sin unidad,
  es decir, con una forma que la tabla real nunca tiene. Un caso fabricado que no imita
  la forma de los datos de producción demuestra menos de lo que aparenta. Ahora la fila
  fabricada tiene las siete columnas reales.
- **`session-start.sh` metía `MEMORY.md` dos veces en el contexto de cada sesión.** El
  hook volcaba el índice con `head -20` y la auto-memoria de Claude Code ya lo inyecta
  por su cuenta: ~985 tokens duplicados en cada arranque. Ahora imprime el recuento de
  entradas y el aviso de tamaño — la señal de vida que la auto-memoria no da — pero no
  el cuerpo.

- **Falso fallo en la verificación de backups por SIGPIPE.** `unzip -Z1 | grep -q` con
  `set -o pipefail` mataba a `unzip` y el verificador reportaba un ZIP correcto como roto.
  Solo aparecía a escala real (933 entradas), no con el fixture de 6. `shellcheck` no lo
  detecta. Queda documentado en `MISTAKES.md` · M-003.

- **El software del kit no tenía licencia, y el README daba a entender que sí.**
  El `LICENSE` de CC BY 4.0 acota su alcance, en su propio preámbulo, a los decks
  y sus guiones originales: nunca cubrió `kit/`. Pero el README decía
  *"CC BY 4.0. Comparte y adapta con atribución"* sin distinguir, así que quien
  clonaba el repo creía tener un permiso que legalmente no existía — por defecto,
  ausencia de licencia es reserva de todos los derechos. Se añade
  **`LICENSE-CODE`** con licencia **MIT** para todo lo de `kit/` y los scripts de
  `.github/`; se acota explícitamente el `LICENSE` de CC BY a las charlas; y la
  sección de licencia del README pasa a declarar el reparto en una tabla. MIT es
  elección deliberada: es la misma licencia del material del que derivan tres
  guards, así que no hay fricción de compatibilidad.

- **El workflow de CI no parseaba, así que su último job no llegaba a ejecutarse.** Un
  `name:` sin comillas con dos puntos dentro —`test_uninstall.sh (restaura el backup mas
  reciente: interno o ZIP…)`— es YAML inválido. Se entrecomilla y se añade a
  `test_harness_structure.sh` el sensor que lo habría cazado antes de subirlo.


- **El evaluado podía leer su propio oráculo.** El enunciado, el setup, el check y el
  transcript vivían en el mismo directorio de trabajo que se le daba al agente: de 12
  ejecuciones de la primera tirada real, 4 leyeron ficheros del harness y 3 hicieron `cat
  _check.sh` — en la tarea 06 lo hicieron los dos brazos, y los dos aprobaron. Ahora el
  meta vive en un `mktemp -d` **sin parentesco** con el del agente, así que un `../` no
  descubre nada. El sensor es de comportamiento, no un `grep` sobre `run.sh`: corre
  `run.sh` entero con un `claude` de mentira que solo lista su `cwd`.

- **El eval set medía ruido, no comportamiento**, y no se había visto porque correrlo
  cuesta dinero. `run.sh` definía `PY` sin exportarlo y `bash _check.sh` es otro proceso,
  así que el check de cuatro de los seis casos se ejecutaba como `"" grade.py …` y daba
  rojo sin mirar al agente. La 06 daba verde pasara lo que pasara: verificaba con `grep -q
  'test_suma.py' _run.jsonl` y el prompt se copia literalmente dentro del transcript, así
  que acertaba por el eco del enunciado. Y un `error` de instrumentación se agregaba junto
  al `fail`, que convierte una avería del aparato en un suspenso del agente.

- **El modelo apuntado era el equivocado.** `record.py` guardaba `next(iter(modelUsage))`,
  el primero del diccionario, y cada sesión de `claude -p` gasta unos 15 tokens en un haiku
  auxiliar: 40 tiradas de Opus quedaron etiquetadas como Haiku y el guardia de E24 se
  negaba a comparar dos brazos que habían corrido con el **mismo** modelo. Un guardia
  alimentado con el dato equivocado no protege: bloquea lo bueno.

- **El nombre del transcript colisionaba y se comía la evidencia.** Llevaba `$(date +%F)`
  —el día— y `attempt` reinicia en cada invocación, así que dos tiradas de la misma tarea
  y el mismo brazo el mismo día se pisaban. Pasa a llevar el `ts` de la fila. Una de esas
  colisiones ya había ocurrido, y por eso la fila retirada no es re-auditable.

- **`make evals-paid` nunca llegaba a preguntar, y el defecto era preexistente.** La receta
  terminaba en `\\`, que en un Makefile es una barra literal y no una continuación: `read`
  definía `ans` en una shell y la comparación corría en otra, con `ans` vacío. Fallaba
  **cerrado** —decía "Cancelado." y salía 1 siempre—, así que no era un riesgo de gasto:
  era un target muerto. El sensor exige que ninguna línea de receta acabe en dos barras,
  así que cubre también a los targets futuros.

- **El ensayo podía mentir sobre lo que ibas a pagar.** El estimador de `DRYRUN=1` moría
  con un `runs.jsonl` corrupto —una línea JSON escalar, un `cost_usd` de texto— y `run.sh`
  salía con 0 igualmente, porque tiene `set -u` sin `set -e` y el traceback caía en un
  `exit 0` incondicional: el operador se quedaba sin la única cifra que la herramienta
  existe para darle, y con un exit 0 diciendo que todo fue bien. Además, el `: > "$TMP"`
  que trunca el parcial corría **antes** del bloque de ensayo, así que un ensayo que
  promete no tocar nada pisaba un fichero del árbol.

- **Dos correctores confundían la forma con la calidad.** El de la 12 castigaba verificar
  —`__pycache__` es el rastro de comprobar que el módulo importa, no un fichero sembrado— y
  no miraba el exceso de celo que la tarea existe para medir. El de la 11 exige el literal
  `.venv/bin/pip` y suspende `.venv/bin/python -m pip install requests`, que es la misma
  solución escrita de otra forma; ese sigue sin arreglar y **infla la ablación de
  `sin-ajustes`**, y la salvedad va escrita junto al −0,17, no en una nota al pie.

- **Se deja de versionar bytecode.** Un `.pyc` publica en `co_filename` la ruta absoluta de
  compilación, que aquí incluye el nombre de usuario.

- **Dos fallos en abierto del propio arreglo de la fusión.** La escritura final era `cp -p`
  desde un temporal en `/tmp`: un fallo a mitad dejaba el `settings.json` truncado, y además
  el `cp` desde `/tmp` bajaba el modo del fichero a `600` en cada instalación. Ahora el
  temporal se crea junto al destino y entra con `mv` —rename atómico— preservando el modo
  original (`644`, el que escribe una instalación limpia). Y el hook `preflight.sh` resucitaba
  el proxy de Headroom en **cada** sesión de **cualquier** proyecto, contradiciendo su propio
  mensaje ("Claude Code funciona igual, no depende del proxy"): ahora solo lo levanta si hay
  opt-in declarado —la variable en el entorno o la URL en un `settings`—, porque sin nadie
  enrutado son 1,3 GB de RSS para nadie.

- **`install.sh` abortaba la instalación entera si Sentinel había dejado un `__pycache__`.**
  Los bucles de `agents/*` y `sentinel/*` filtraban con `[ -e "$f" ]`, así que un directorio
  llegaba a un `cp` sin `-r`: `cp: -r not specified; omitting directory`, `rc=1` e instalación
  a medias — y `test_doctor.sh` en rojo por una causa ajena al doctor, porque corre `install.sh`
  bajo `set -e`. El filtro pasa a `[ -f "$f" ]`, que es lo que ya hacía el bucle de `hooks/`.
  Reproducido sobre el árbol real, que arrastraba tres `__pycache__` desde el 25-ago: `rc=1`
  antes, `rc=0` después. Cuatro casos nuevos en `test_install.sh`, y el rc del primer
  `install.sh` deja de perderse: antes un fallo ahí mataba la suite con `rc=1` y cero salida.
- **`doctor.sh` daba por buena una instalación sin API.** El check 5 leía
  `.env.ANTHROPIC_BASE_URL` solo del `settings.json` de usuario, así que un enrutado declarado
  en ámbito de proyecto —que es el que gana— no se sondeaba: con el proxy muerto imprimía
  `PASS · API directa a Anthropic` junto al `PASS` del 5e que sí lo veía declarado, dos
  afirmaciones que se contradicen, y `rc=0`. La enumeración de ámbitos se extrae a
  `enumerar_enrutado()` y la consumen los dos checks en orden de precedencia real; el `FAIL`
  nombra el fichero de origen. `test_doctor_base_url.sh` pasa de 16 a 22 asserts: el caso F
  era un sensor invertido —afirmaba que una instalación sin API es un estado limpio— y queda
  como control positivo, con el caso J nuevo como negativo. Falsabilidad medida: los 6 asserts
  nuevos caen contra el `doctor.sh` anterior y los 16 previos siguen verdes.
- **`pre-compact.sh` leía un campo que no existe.** Esperaba `triggerReason`; el evento envía
  `trigger`, y `triggerReason` tiene 0 apariciones en el binario 2.1.258, así que el hook
  imprimía siempre `(unknown)`. Las dos entradas `PreCompact` del `settings.json` instalado
  (`manual` y `auto`, mismo comando) se consolidan en un `matcher: "manual|auto"`.

### Documentation

- **`08-plugins-mcp-y-skills.md`: la sección de MCP decía cosas que ya no eran verdad, y
  callaba la que más cuesta.** Listaba `perplexity` como si estuviera operativa (dada de
  baja el 2026-08-17) y no mencionaba `headroom`, `firecrawl` ni `serena`. Se reescribe con
  el estado real y se añade **"Un MCP en ámbito global es un impuesto fijo, y casi nunca se
  mide"**: por qué `--scope user` lo arranca también en `/tmp` y en repos ajenos, el script
  para contar el uso *efectivo* en tus propias transcripciones (bloques `tool_use`, no
  menciones: el nombre del servidor sale en el prompt de cada sesión e infla cualquier
  `grep` ingenuo), y el caso medido que lo motiva — Serena en global durante semanas, 1 de
  55 sesiones con llamadas reales y sus 12 últimos arranques sin proyecto activo. Incluye
  el detalle que hace que quitarlo no funcione a la primera: `headroom wrap claude`
  re-registra Serena en cada lanzamiento salvo con `--code-memory none`. Incluye el
  contraejemplo que evita leer mal la regla: `firecrawl` tiene el **mismo** uso medido que
  Serena — 4 llamadas en 1 de esas 55 sesiones — y se queda, porque es `type: http` en ámbito de
  proyecto y no levanta proceso local. Se retira por **coste de arranque x ubicuidad**, no
  por recuento de llamadas.
- **`03-headroom.md`: el sufijo `[1m]` viaja pegado al modelo y rompe el cambio de modelo.**
  `--1m` reescribe `ANTHROPIC_MODEL` del proceso hijo, y se lo aplica a *cualquier* modelo que
  le pases. Con Haiku, que no tiene la beta de contexto largo, la sesión muere con
  `400 The long context beta is not yet available for this subscription` — un error que se
  confunde con un problema de cuota o de credenciales. Documentado con la traza medida.

- **Atribuciones corregidas**, todas verificadas contra la fuente el 2026-08-21:
  el artículo de *harness engineering* es de **Birgitta Böckeler**, no de Fowler, y **no da
  una definición formal de *harnessability***; el de *context engineering* es de
  sep-2025 y **no fija ningún presupuesto de tokens para CLAUDE.md**; los cuatro principios
  atribuidos a **Karpathy no tienen fuente primaria** y pasan a ser "principios de la casa";
  la cita de Cherny sigue siendo **secundaria**; y `anthropics/skills` **no enumera 17
  skills** y tiene licencia mixta.

- **Los KPIs heredados se archivan como históricos sin procedencia verificable.** El "68 %
  de sesiones con correcciones" medía en realidad 8,8 % de *turnos*; la métrica correcta,
  ahora que existe, da 19,1 % de sesiones. Y las sesiones con oráculo no valían 0 sino
  27,7 %: nunca se habían medido, que no es lo mismo.

- **`03-headroom.md` explica ahora que `headroom wrap` pone `ENABLE_TOOL_SEARCH`
  por su cuenta.** La doc recomendaba la variable en `settings.json` pero no decía
  que el wrapper ya la escribe, con lo que quitarla de la config no la desactiva:
  se repone en cada arranque. Se documenta la precedencia real que implementa
  `headroom/cli/wrap.py` (flag explícito → valor preexistente en el entorno →
  default `true` de `headroom/providers/claude/runtime.py`) y el hecho de que el
  `env` de `settings.json` se aplica **después** del arranque y pisa al wrapper —
  que es por lo que un `"false"` olvidado ahí anula el deferral en silencio. Se
  añade también que en Vertex AI el deferral viene desactivado por defecto.
- **Aviso sobre el hook que deja `headroom init` y que puede levantar un segundo
  proxy.** `init` escribe un `.claude/settings.local.json` de ámbito proyecto que
  engancha `headroom init hook ensure` a `SessionStart` **y** a
  `PreToolUse(Bash)`. Con `supervisor_kind: "none"` en el manifiesto del perfil,
  ese hook cae en `start_detached_agent()` si `/readyz` no contesta en 1 s, y
  arranca un proxy fuera del supervisor. Con el proxy ya corriendo como unidad
  systemd con `Restart=always`, el resultado son **dos instancias peleando por el
  puerto 8787** y respuestas **HTTP 200 vacías** que Claude Code reporta como
  fallo de la API. Se documenta cómo evitarlo y que `hook ensure` no reescribe
  ficheros de configuración, así que neutralizar ese settings es estable.

- **Las cifras que la documentación afirma sobre el repo pasan a tener sensor.** `README.md`
  decía 16 suites con 23 en el `Makefile`, `kit/README.md` "8 documentos" con 9, y tres <!-- doc-claims:ignore: cita del estado ANTERIOR al sensor, no del arbol de hoy -->
  documentos seguían citando `session-brief.sh` meses después de borrarlo. Nada se ponía en
  rojo porque nadie medía el texto. `test_doc_claims.sh` cuenta el árbol real (suites,
  agentes, comandos, ADRs, documentos), lo compara con lo que dicen los documentos que hablan
  **en presente** —en dígito y en letra, porque "cinco comandos" era justo la forma que se
  quedaba sin actualizar— y comprueba que ningún `.sh` citado en la documentación haya
  dejado de existir. `knowledge/DECISIONS/`, `knowledge/PRE-MORTEM.md` y
  `docs/superpowers/plans/` quedan **fuera a propósito**: son registros fechados, y una cifra
  de agosto ahí es correcta aunque hoy sea otra. De `CHANGELOG.md` entra solo la sección
  `[Unreleased]`, que describe el árbol de hoy; sus secciones publicadas quedan fuera por lo
  mismo. Trae su propio check de falsabilidad.


- **`kit/evals/README.md` publica el inventario del eval y cómo crecerlo**, y desde esta
  rama sus cifras tienen sensor: el recuento de tareas de su cabecera se compara con
  `kit/evals/tasks/*.yaml` en cada `make test`.

- **La tirada completa está publicada con su condición** en `knowledge/EVAL-CRITERIA.md`:
  98 llamadas reales, los 20 casos, tres brazos, `RUNS=1`, `claude-opus-5[1m]` y sin el
  proxy Headroom en medio —con `ANTHROPIC_BASE_URL` puesto, el lift mediría harness y
  proxy a la vez—. Va con **las dos lecturas**, con y sin la fila retirada, porque cuál de
  las dos columnas es la verdadera no lo decide un argumento sino una llamada de pago que
  **está pendiente**. Y con una fe de erratas que nombra al commit `e7d4fee`: no se enmienda
  un mensaje publicado, se corrige aquí.

- **La doc recomendaba como oráculo del enrutado una herramienta que miente en los dos
  sentidos.** `headroom doctor` da `claude ⚠ not routed` dentro de una sesión enrutada —solo
  juzga ficheros, no la sesión— y a la vez `codex ✓ routed` con cero peticiones OpenAI en los
  logs; reproducido tres veces, la última hoy. Se retira como oráculo de `03-headroom.md` y de
  `07-verify.md` y se sustituye por los dos que sí contestan: el `environ` de un proceso hijo
  de la sesión y `doctor.sh`. Se documenta el mecanismo que faltaba —`headroom wrap` escribe la
  URL en el `settings.local.json` del **proyecto** y la restaura al salir, así que el enrutado
  es por proyecto y quitarla a mano no dura— y que el kit **no fija versión** de `headroom-ai`.
  Seis afirmaciones de esa doc pasan a tener sensor en `test_doc_claims.sh`, con diez averías
  fabricadas para probar que acusan.

- **Tres afirmaciones falsas sobre la capa de IOCs, retiradas.** `05-security.md` y
  `SECURITY.md` decían que el kit no distribuye `iocs.json` "para no filtrar indicadores
  propios"; el kit lo trae desde `2de31d5`, con 31 patrones de ruta, 12 de comando y 30 de red,
  e `install.sh` lo copia junto al hook. En una instalación limpia `doctor.sh` imprime
  `PASS · Sentinel IOC layer activa` sin que haya que hacer nada, así que el paso de activación
  que documentaban era un rito vacío. Se conserva íntegro el comportamiento *fail-open* —sin el
  fichero, `load_iocs()` devuelve `{}` y todos los checks son un no-op silencioso— y se
  documenta el orden de búsqueda real, con su consecuencia: un `iocs.json` puesto en `hooks/`
  queda sombreado por el del kit y no se lee nunca. `07-verify.md` publicaba además un oráculo
  falso (`test -f "$CLAUDE_HOME/hooks/iocs.json"`, que da `WARN` donde `doctor.sh` da `PASS`).
- **`06-routine.md` atribuía al kit un umbral de autocompact que el kit no toca.** Afirmaba
  configurar el 75 % con `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` en `settings.json`; esa clave no
  aparece en el `settings.json` que instala. Medido aparte: ese override es un hook de test que
  solo *baja* el umbral, y en la ruta de 1M es inerte.
- **La plantilla `kit/claude/CLAUDE.md` deja de llevar el estado de una máquina.** Fuera el
  correo del autor, la fecha del día y tres bloques con 0 uso medido: 143 → 115 líneas y
  1.977 → 1.624 aprox-tokens, con techo declarado en su sensor (120 líneas / 1.700 tokens).
  Queda dicho lo que sigue sobrando y no se toca aquí: la plantilla manda usar skills
  (`deep-change`, `superpowers`) que el kit no instala.
- **`VERSION` en la raíz como única fuente de la versión**, con un sensor que exige que
  coincidan `VERSION`, la sección más nueva del CHANGELOG y el `vX.Y.Z` de la línea `estable`
  de `README.md` y `CLAUDE.md`. Sin `git tag` a propósito: `actions/checkout` no trae tags y el
  check degradaría a `skip` en CI, que es como no tenerlo. La duración del oráculo en
  `CLAUDE.md` pasa de "~45 s" a "151-179 s en un i9-14900HX", que es lo medido.

### Security

- **Tres rutas con el nombre real de personas salían publicadas en `HEAD`**, en
  `knowledge/ORACLES.md` y en `.claude/skills/harness/referencias/oraculos.md`: rutas
  absolutas de proyectos de cliente con el nombre de usuario y, en un caso, el nombre civil
  completo dentro de una ruta de Windows. Redactadas conservando la lección que las hacía
  útiles (el oráculo se invoca por **ruta absoluta**, M-001).
- **Un `.pyc` estaba versionado** (`scripts/__pycache__/metrics.cpython-314.pyc`). El
  bytecode lleva dentro la ruta absoluta de compilación en `co_filename`, así que publicaba
  el árbol de directorios de la máquina del autor. Se saca del índice y `__pycache__/` entra
  en `.gitignore`.

- **Nueve huecos de los guards de `git push` y `rm`, cerrados con su caso de test.** Se colaban
  el `push -f` con `-C` delante, el refspec forzado con `+`, `--mirror`, el borrado de rama
  remota con `--delete`, el `push` a `master` tras un `cd` encadenado (por el ancla `^` de
  `branch-guard.sh`), el `rm` recursivo y forzado en forma larga, y `find … -delete` bajo
  `/home/`. `test_guards.sh` suma 14 casos —10 que caen contra los guards anteriores y 6
  contrapesos anti-sobrebloqueo: `-C` sin forzar, rama de feature, `rm -r` sin forzar,
  `find -delete` en `/tmp`— y `test_guards_falsifiability.sh` mantiene sus 10 `BLOCK` exactos,
  así que la cifra que afirma el README sigue siendo verdad. La tabla de reglas gana un camino
  rápido de un solo `grep`: el camino caliente (comando permitido) baja de 62 a 8 ms medianos y
  de 43 a 1 invocación de proceso; el denegado sube de 44 a 68 ms, que es el raro y acaba en una
  interrupción al usuario. Diferencial sobre 65 comandos: 7 diferencias de decisión, las 7
  intencionadas.
- **Sentinel gana un suelo en código que ningún fichero de datos puede levantar.**
  `ALWAYS_DENY_PATHS` —el fichero de credenciales de Claude Code, la clave privada de SSH (el
  `.pub` no empareja) y las credenciales de AWS— se consulta **antes** del allowlist. Cierra una
  asimetría medida: con `$HOME/.claude/` en el allowlist, *nombrar* ese fichero de credenciales
  se bloqueaba y *abrirlo* se permitía sin registro. Aguanta con un allowlist hostil
  (`paths: ["/"]`) y con `iocs.json` vaciado a `{}`, que es el kill-switch que convierte todos
  los demás checks de ruta en no-op. Coste medido sobre el `~/.claude` real (6.358 ficheros):
  las denegaciones pasan de 1 a 13, y las 12 nuevas son material de clave —el de control del
  demonio y 11 de sesión— que el kit no referencia en ningún sitio.
- **El agente ya no puede desactivar sus propios guards sin dejar rastro.** `PROTECTED_CONFIG`
  (`settings*.json`, `hooks/`, `sentinel/`, `sentinel-allowlist.json`, `iocs.json`,
  `.gitleaks.toml`) no deniega —eso es cosa de `permissions.deny`— pero **no es eximible y se
  registra siempre**: seis vías que antes pasaban `allow` sin log, incluida la de añadir una
  entrada al allowlist con `jq`, quedan auditadas. Sobre los mismos 6.358 ficheros añade **0
  denegaciones** y 30 rutas registradas, y `kit/claude/hooks/` del propio repo no empareja
  (falta el punto), así que no estorba al desarrollo del kit. El mensaje de `deny` deja de
  anunciar la vía de exención donde era mentira: para una regla del suelo ningún allowlist la
  levanta, así que el prospecto era falso y a la vez instructivo.
- **gitleaks: las claves de Anthropic se colaban en 5 de 7 emplazamientos.** La regla por
  defecto `anthropic-api-key` solo dispara con la forma exacta de 93 caracteres terminada en
  `AA`, así que la misma clave alargada a 105 se comiteaba incluso en `.yaml` — y el caso 1 de
  la suite pasaba por la regla por defecto, no por una del kit, de modo que la afirmación de
  `.gitleaks.toml:26-28` era falsa. Regla nueva `anthropic-api-key-prefix` sobre el prefijo de
  clave de Anthropic con 20+ caracteres, sin `path` y sin umbral de entropía ni longitud fija;
  la medición queda dentro del comentario. Falsabilidad: neutralizar el regex hace caer **1 de
  22** casos y no 22, lo que prueba que la mutación desactiva la regla y no la carga de la
  config. La clave del fixture se compone en ejecución, porque un literal de 20+ caracteres tras
  el prefijo haría que la regla bloqueara el commit que lo añade.
- **Los nueve `*.sh` de `kit/claude/hooks/` quedan versionados `100755`.** `preflight.sh` era el
  único a `100644`: instalado, `rc=126` y nunca se ejecutaba, con el fallo leyéndose como "el
  hook no hace nada". `test_guards.sh` añade un sensor de modo que mira disco **e** índice
  —falsable quitando el bit solo del índice— porque `git ls-files -s` es la única vía que ve la
  causa real.
- **Guard de configuración: 10 reglas `deny` sobre `Write`/`Edit` de `hooks/**`,
  `settings.json`, `settings.local.json`, `sentinel-allowlist.json` y `sentinel/**`** (rutas con
  una sola barra, ancladas al propio fichero de settings). El motivo es medido: en un solo día
  tres escritores distintos reescribieron el `settings.json` de usuario y uno se llevó por
  delante la clave `statusLine`. **Declarado y sin sensor**: la sonda que confirmaría que el
  binario honra esa forma la intercepta el clasificador de permisos antes de llegar a la capa
  que se quiere medir, así que no se afirma que funcione. El enforcement probado sigue siendo
  el de los hooks.

### Deuda declarada

Lo que se midió, no se arregló en esta versión y se documenta para que nadie lo lea como
resuelto. Ninguna de estas líneas tiene sensor: son huecos conocidos, no regresiones.

- **El allowlist por proyecto sigue abierto y sin documentar.** `load_user_allowlist()` prefiere
  el `.security/sentinel-allowlist.json` del directorio de trabajo sobre el del usuario, así que
  **un repo clonado puede traer sus propias exenciones**. Con el suelo en código ya no expone
  credenciales ni la config de los guards, pero todavía puede eximirse la config de npm, los
  certificados o la base de contraseñas del sistema. Seguimiento nº 1.
- **`block-dangerous-commands.sh` exime por igualdad exacta de cadena** (`index($cmd)` + `exit
  0`): una línea en el allowlist desactiva **todo** el blocklist, no un patrón. En Sentinel esa
  misma lista es más estrecha, porque solo exime el check de comandos.
- **Sentinel es fail-open por diseño** (`except: sys.exit(0)`): cualquier entrada que lo haga
  fallar es un bypass universal y silencioso.
- **Los guards leen el literal del comando, no el `argv`** que expandirá el shell: entrecomillar
  los flags o pasarlos por una variable derrota cualquier regex de flags. Está dicho en el
  comentario del hook y no se tapa con más regex, que daría una falsa sensación de cierre.
- **`dict-password-config-file` sigue acotada por extensión de config**, así que una contraseña
  en un `.txt` se comitea. Ampliarla reintroduce la clase de 18 falsos positivos ya medida.
- **`kit/docs/07-verify.md:84` sigue describiendo la fuente del check 5 como un `jq` sobre el
  `settings.json` de usuario**, que con la corrección de este release es incompleto: ahora es la
  enumeración de ámbitos. Ninguna suite grepea esa expresión, así que nada se pone rojo.

## [1.0.0] - 2026-08-05

Primera versión etiquetada. Recoge el kit completo: guards deterministas con
suite de test falsable, 8 agentes con tiering, dos capas de secretos, eval set
opt-in, y `install.sh`/`doctor.sh` como bucle de instalación y diagnóstico.

### Fixed

- **Una instalación limpia ya no puede quedarse sin API.** `kit/claude/settings.json`
  distribuía `ANTHROPIC_BASE_URL=http://127.0.0.1:8787` mientras `install.sh`
  declaraba Headroom como componente de terceros que el kit no instala: quien
  clonaba en limpio se quedaba con Claude Code enrutado a un puerto donde no
  escuchaba nadie, sin poder hablar con la API y con un síntoma que no parecía
  de configuración. La variable sale del `settings.json` distribuido; ahora la
  escribe `install.sh --with-headroom` y solo después de comprobar `/readyz`.
  **Cambio de config con impacto:** si dependías de que el kit enrutara al
  proxy, recupéralo con ese flag (o añade la variable a mano). Sigue yendo en
  `settings.json` y no en el shell, por el motivo que explica `03-headroom.md`.
  Cubierto por `kit/test/test_clean_install_resilience.sh`.
- **`doctor.sh` ya no aprueba una instalación inservible.** No comprobaba nunca
  el endpoint, así que salía con código 0 en una máquina cuyo Claude Code no
  podía conectar. Ahora, si algo enruta la API, ese endpoint tiene que contestar
  o es `FAIL`. Se consulta `/readyz` y no `/health`, que es agregado y se pone
  en rojo por subcomprobaciones que es legítimo no tener.
  Cubierto por `kit/test/test_doctor_base_url.sh`.
- **Los hooks ya no fallan por dependencias que el kit no instala.**
  `rtk hook claude` y los dos hooks Python del venv daban exit 127 en una
  máquina limpia — el preflight de Sentinel, con `matcher ""`, en *todas* las
  llamadas a tool. Ahora pasan por `optional-hook.sh`. Lo que el wrapper no hace
  es tragarse un bloqueo: si el guard está instalado y sale con código 2, ese 2
  se propaga, porque es así como se deniega una acción.
- **`headroom` y `rtk` se documentaban como una sola herramienta, y son dos
  proyectos independientes.** `kit/docs/03-headroom.md` titulaba "Instalar
  Headroom (`rtk`)" y verificaba el proxy con `rtk --version`; `doctor.sh`
  hacía `command -v rtk` y reportaba "Headroom presente". Son
  [headroomlabs-ai/headroom](https://github.com/headroomlabs-ai/headroom)
  (proxy HTTP en `127.0.0.1:8787`, Python, se cablea con `ANTHROPIC_BASE_URL`) y
  [rtk-ai/rtk](https://github.com/rtk-ai/rtk) (binario Rust que filtra la
  salida de los comandos de shell, se cablea con el hook `rtk hook claude`).
  Ninguna necesita a la otra. Con la comprobación anterior, tener `rtk` sin el
  proxy daba un `PASS` falso, y al revés. `doctor.sh` ahora las comprueba por
  separado, y se corrige también en `07-verify.md` y
  `08-plugins-mcp-y-skills.md`, con una tabla comparativa al principio de
  `03-headroom.md`.

### Added

- **`kit/claude/hooks/optional-hook.sh`**: ejecuta un hook solo si su dependencia
  existe. No-op silencioso si falta; `exec` con propagación literal del código de
  salida si está, incluido el 2 que bloquea. Modo `--python` que resuelve el
  intérprete (venv → `python3` del sistema), lo que además mejora la cobertura:
  en una máquina con Python pero sin venv, `smart_approve.py` y el preflight de
  Sentinel ahora sí corren, cuando antes daban 127.
  Contrato en `kit/test/test_optional_hook.sh` (9 asserts).
- **`install.sh --with-headroom`**: instala `headroom-ai[proxy]` en el venv,
  escribe la unidad de systemd de usuario con `--mode cache` explícito,
  `StartLimitIntervalSec=0` en `[Unit]` y el output-shaper por `ExecStartPost`,
  arranca, espera `/readyz` y **solo entonces** enruta la API. Si el proxy no
  arranca, sale con error y deja la config intacta.
  Cubierto por `kit/test/test_with_headroom.sh` (13 asserts, sin red ni systemd).
- **`kit/test/test_clean_install_resilience.sh`** (12 asserts): monta el kit en
  una máquina simulada sin ninguno de los componentes de terceros y exige las dos
  mitades del contrato — que ningún hook falle, y que un comando destructivo siga
  saliendo con el código que bloquea. Impide "arreglar" la primera mitad a base
  de `|| true`, que rompería la segunda en silencio.
- **`kit/docs/09-ssh-y-gitlab-privado.md`: guía completa de clave SSH y alta en
  un GitLab autoalojado, desde WSL2.** Ocho pasos con los comandos, pensada para
  que alguien de un equipo la siga de principio a fin sin saber de SSH: generar
  la clave (`ssh-keygen -t ed25519` con `-C`, `-f` y `-N ""`, cada flag
  explicado y con la contrapartida real de no poner passphrase en una tabla),
  permisos, copiar la `.pub`, darla de alta en la web de GitLab, el bloque de
  `~/.ssh/config`, `ssh-agent`, y probar con `ssh -T`. Todo genérico: el host va
  en una variable `GITLAB_HOST` y los ejemplos usan `@example.com`.

  Tres cosas que la hacen útil más allá de un copia-pega:

  - **El paso que casi nadie documenta.** Una clave con nombre no estándar
    (`-f id_ed25519_algo`) **no se usa** hasta configurarla, porque `ssh` solo
    prueba los nombres por defecto. Va con la salida real de `ssh -v`
    enseñándolo (`Trying private key: ~/.ssh/id_rsa`, `id_ecdsa`,
    `id_ed25519`… y la tuya no aparece). Es la causa nº 1 de
    `Permission denied (publickey)` con la clave perfectamente dada de alta.
  - **Diagnóstico por `Offering public key`.** Casi todos los fallos dan el
    mismo mensaje, así que el mensaje no informa: la guía enseña a distinguir
    "no se ofreció la clave" de "se ofreció y el servidor la rechazó" mirando
    esa línea de `ssh -v`, y una tabla con los ocho errores restantes.
  - **`IdentitiesOnly yes` explicado**, no copiado: sin él `ssh` ofrece todas
    las claves y el servidor corta por `MaxAuthTries`, con un
    `Too many authentication failures` que parece del servidor y es tuyo.

  Solo se citan mensajes de error **reproducidos**. En particular **no** se
  promete el clásico `UNPROTECTED PRIVATE KEY FILE`: se probó la clave privada
  en `640`, `644`, `660`, `666` y `777` y OpenSSH 10.2 no avisó en ningún caso,
  así que la guía dice que no te fíes de eso como red de seguridad.

- **La guía avisa de que los guards de este kit bloquean sus propios comandos.**
  Sentinel trata `~/.ssh/` como ruta sensible, así que bloquea incluso un `cat`
  de la clave **pública** (`SENTINEL BLOCKED [Bash]: [CRITICAL] sensitive path:
  ~/.ssh/`). No es un fallo: el guard no distingue `.pub` de la privada, y esa
  imprecisión es deliberada. La salida correcta es hacer este alta —tarea humana
  y de una sola vez— en una terminal normal, **no** añadir `~/.ssh/` al
  `sentinel-allowlist.json`, que abriría el acceso a las claves privadas de
  forma permanente para ahorrarse abrir una pestaña.
- `08-plugins-mcp-y-skills.md` explica ahora que un marketplace de plugins
  privado se da de alta por URL SSH y por tanto depende de esa guía y de la VPN,
  y que si la VPN está caída solo falla ese marketplace: el resto de Claude Code
  sigue igual.
- **Aviso de WSL2 al principio del `README.md`.** El requisito estaba, pero
  enterrado dentro de "Quick start". Ahora abre el documento, con el `wsl` que
  hay que ejecutar primero y dos avisos concretos para quien viene de Windows:
  clonar **dentro** de WSL y no en `/mnt/c/` (el `9p` es mucho más lento y
  complica el bit de ejecución), y el `.gitattributes` que ya evita que
  `core.autocrlf=true` convierta los scripts a CRLF.
- `kit/docs/03-headroom.md`, sección nueva: **lo que Claude Code desactiva por
  su cuenta cuando `ANTHROPIC_BASE_URL` apunta a un endpoint custom.** Son tres
  cosas y dos tienen arreglo: la **ventana de contexto de 1M** (topa en 200k;
  la selección del picker `/model` no sobrevive al endpoint custom, se recupera
  con `ANTHROPIC_MODEL=<modelo>[1m]`), la **carga de herramientas on-demand**
  (carga todos los schemas de golpe; se recupera con `ENABLE_TOOL_SEARCH=true`)
  y **Remote Control** (`/rc`, sin arreglo posible: es un gate del cliente). El
  primero es el que muerde en silencio: con `"model": "opus[1m]"` en
  `settings.json` nada indica que te han recortado el contexto. El kit no fija
  `ANTHROPIC_MODEL` a propósito — pinchar un modelo en la config de otra
  persona sería peor que el problema.
- `kit/docs/03-headroom.md`: **`ANTHROPIC_BASE_URL` tiene que ir en
  `settings.json`, no en el `.bashrc`/`.profile`.** Claude Code lee su entorno
  una sola vez al arrancar y las sesiones heredan un snapshot del shell: si el
  proxy no estaba arriba en ese instante, la sesión entera se queda sin enrutar,
  sin recuperación y sin avisar (`headroom doctor` → `savings: no tokens saved
  yet`). La disponibilidad se resuelve con `Restart=always` en systemd, no con
  un export condicional.
- `kit/docs/03-headroom.md`: **el motor de compresión puede estar apagado sin
  que nada lo diga** (`kompress` con `backend: null` en `/health`) y el proxy
  sigue sirviendo tráfico igual. Dos causas: el modelo ONNX (~260 MB) no
  descargado —el preload de arranque usa solo caché local a propósito, para no
  bloquear el bind del puerto—, o una unidad de systemd endurecida en la que
  `~/.cache/huggingface` no es escribible, que lo deja inutilizable para
  siempre.
- `kit/docs/03-headroom.md`: **cómo medir el ahorro sin engañarse.** `/stats`
  son contadores del proceso y se reinician con el servicio; `/stats-history`
  es el histórico durable. Y la única cifra que juzga si el modo `cache` hace
  su trabajo es `lifetime.cache_read_tokens / lifetime.total_input_tokens`, la
  proporción servida desde el prompt-caching de Anthropic.
- `kit/docs/03-headroom.md`: instalar con el extra **`[proxy]`, no `[all]`**
  (`[all]` arrastra `torch` y ~6 GB que el motor no usa: su backend es ONNX
  Runtime, ya incluido en `[proxy]`; el aviso `PyTorch was not found` es
  inocuo). Y `StartLimitIntervalSec` va en la sección **`[Unit]`**: en
  `[Service]` systemd lo ignora en silencio y deja el default de 5 arranques en
  10 s.
- Hash SHA-256 de `gitleaks` (x64 y arm64) fijado como constante dentro de
  `kit/install.sh`, verificado por el propio mantenedor contra la release
  oficial `v8.30.1` — ya no se confía en el `checksums.txt` servido por el
  mismo host que el tarball, que solo protegía contra corrupción en
  tránsito, no contra una release comprometida. Procedimiento de
  actualización documentado en `CONTRIBUTING.md` ("Actualizar gitleaks").
- Si el checksum de `gitleaks` no coincide con el fijado, la instalación ya
  no lo trata igual que "sin red": deja una marca persistente en
  `$CLAUDE_HOME/.gitleaks-checksum-mismatch` (con versión, arquitectura y
  hash esperado) que `doctor.sh` reporta como `FAIL` en instalaciones
  posteriores — sin romper el resto de la instalación (la Capa 1 de
  secretos sigue activa). Cubierto por
  `kit/test/test_install_gitleaks_checksum.sh` (9 casos).
- `.gitattributes` en la raíz: fuerza LF (`eol=lf`) en todo lo que se
  ejecuta o parsea (`*.sh`, `*.py`, `*.yml`/`*.yaml`, `*.toml`, `*.json`,
  `Makefile`, el hook sin extensión `kit/claude/hooks/git/pre-commit`,
  etc.). Protege a quien clona desde Windows/WSL2 con
  `core.autocrlf=true` (default de Git) de que un clon normal convierta LF
  a CRLF y rompa cada script (`bad interpreter: .../bash^M`). Cubierto por
  `kit/test/test_gitattributes.sh` (4 casos, con auto-falsación).
- `shellcheck` en un job nuevo de CI sobre los 20 scripts del kit (`kit/*.sh`,
  hooks, `kit/test/*.sh`, `.github/scripts/*.sh`).
- `doctor.sh` reporta ahora el estado de la Capa 2 de secretos: versión de
  `gitleaks` instalada, si `core.hooksPath` está configurado en el repo
  actual, y si quedó una marca de checksum-mismatch pendiente de revisar.
- Puerta de plataforma en `kit/install.sh`: comprueba `uname -s` y aborta con
  un mensaje claro (y sin dejar nada a medias) en cualquier plataforma que no
  sea Linux o WSL2, con detección informativa (no bloqueante) de WSL2. Es lo
  único que prueba la CI de este repo, así que es lo único que se promete.
- Instalación automática y opcional de `gitleaks` (versión fijada `8.30.1`)
  desde `kit/install.sh`: detecta si ya está en el sistema y, si no, ofrece
  descargar el binario oficial verificando su checksum SHA-256 contra el
  fichero de checksums publicado (nunca `curl | bash`). Si falla por
  cualquier motivo (sin red, checksum no coincide, sin permisos), degrada
  con un aviso claro en vez de romper el resto de la instalación — la Capa 1
  de secretos funciona igual sin `gitleaks`. `doctor.sh` ya lo reportaba.
- Subcomando `kit/install.sh --enable-secrets-layer2`: activa
  `core.hooksPath` de git (Capa 2 de secretos) solo en el repositorio desde
  el que se invoca explícitamente. `install.sh` sin flags nunca toca esta
  config por su cuenta, ni siquiera corriendo dentro de un repo git — ver
  `kit/docs/05-security.md` para el razonamiento. Complementa (no sustituye)
  el one-liner manual ya documentado.
- Tres suites de test nuevas: `test_install_platform_gate.sh` (4 casos),
  `test_install_gitleaks.sh` (6 casos) y `test_enable_secrets_layer2.sh`
  (6 casos), añadidas a `make test` y a `.github/workflows/ci.yml`.
- README.md reescrito como landing page de 30 segundos: qué hace el kit por
  delante de qué es, prerrequisitos explícitos (Linux/WSL2) en el quick
  start, y solo el badge de CI (sin badges decorativos).
- Integración continua (`.github/workflows/ci.yml`) con dos jobs: las suites
  de test completas (`kit/test/*.sh`, incluyendo la de falsabilidad de
  guards y `gitleaks dir` sobre el repo) y un smoke test en contenedor Debian
  limpio que instala el kit como usuario **no root**, corre `install.sh` dos
  veces para probar idempotencia, y asserta postcondiciones reales
  (ficheros, permisos de ejecución, JSON válido, `doctor.sh`) en vez de solo
  el código de salida. El eval set nunca se ejecuta en CI.
- Andamiaje de comunidad: `CONTRIBUTING.md`, `SECURITY.md` (documenta los
  límites conocidos de los guards de secretos en vez de esconderlos),
  `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), plantillas de issue
  (bug/feature) y de PR, `Makefile` (`make install|test|doctor|help`,
  `evals-paid` opt-in y con confirmación), `.editorconfig`.
- Capa de contenido para secretos: `gitleaks` en un hook `pre-commit`
  (`kit/claude/hooks/git/pre-commit` + `kit/claude/.gitleaks.toml`), que
  escanea lo que de verdad queda staged en vez de adivinar el efecto de un
  comando por su texto. Complementa la Capa 1 existente
  (`secret-guard.sh`, por nombre de fichero).
- Eval set mínimo de 6 tareas (`kit/evals/`), opt-in y aislado por tarea en
  su propio directorio temporal. Documentado como que cuesta dinero real y
  que nunca se invoca desde `make test`, `doctor.sh` ni CI.
- Suite `test_guards_falsifiability.sh`: prueba que la suite de guards mide
  comportamiento real neutralizando un guard y comprobando que eso rompe
  casos BLOCK conocidos.

### Changed

- La regla propia de `kit/claude/.gitleaks.toml` (contraseñas de tipo
  diccionario en ficheros de config) ya no incluye `.json` en su path: la
  medición de 0 falsos positivos solo era válida para este repo pequeño y
  centrado en documentación, y en un proyecto Node real `.json` cubre
  `package-lock.json`/`tsconfig.json`/specs de OpenAPI, donde un
  `"token": "valor-interno"` inocuo dispararía la regla. Documentado con un
  fixture nuevo en `test_secret_content_gitleaks.sh` (caso 17).
- El badge de CI en `README.md` ya no apunta a `?branch=v2-autonomous`:
  refleja la rama por defecto una vez fusionada.

### Fixed

- Ancla del patrón `sk-` en la capa de nombre de secretos para evitar falsos
  positivos sobre texto kebab-case legítimo.
- `smoke-install-nonroot` fallaba en el primer step (`Illegal option -o
  pipefail`): dentro de un `container:`, Actions ejecuta `run:` con `sh -e
  {0}` sin importar el shell por defecto del runner, y el `sh` de
  `debian:12-slim` es `dash`, que no soporta `pipefail`. Fix: `defaults: run:
  shell: bash` a nivel de job (verificado que `debian:12-slim` trae bash de
  fabrica).
- `test_guards.sh` no era hermético: 3 casos (`rm -rf` en raíz, force push
  directo/compuesto) dependían de las reglas `permissions.deny` que
  `smart_approve.py` lee de `$HOME/.claude/settings.json` — con un `HOME`
  limpio pasaban 24/27, con el `HOME` real de esta máquina pasaban 27/27,
  sin que la suite lo detectara. Fix: la suite ahora construye su propio
  `$HOME` temporal con las reglas de `kit/claude/settings.json` antes de
  correr, y da el mismo resultado (28/0) con cualquier `HOME`. De paso,
  se añade un caso explícito que documenta como hallazgo de seguridad —no
  se oculta— que `smart_approve.py` falla abierto (permite todo) cuando no
  hay `settings.json`: no hay allowlist que cargar, así que no hay nada que
  bloquear. El resto de suites de `kit/test/` no tenían esta dependencia de
  `$HOME` (comprobado corriendo las 11 con `HOME` limpio).
- 8 ficheros invocados directamente por nombre (los hooks de
  `kit/claude/hooks/*.sh`, `kit/claude/hooks/git/pre-commit`) estaban
  commiteados con modo `100644` en vez de `100755` — git ignora en
  silencio, sin ningún error, un hook no ejecutable, así que cualquiera
  que clonase el repo y activase la Capa 2 de secretos (`core.hooksPath`)
  tendría el hook muerto. Invisible en local porque este repo vive en un
  montaje `/mnt/c` (9P) que reporta `rwx` para todo con
  `core.fileMode=false`, así que ninguna observación del bit de ejecución
  en el filesystem es fiable aquí; el único fix real es sobre el modo que
  git tiene REGISTRADO (`git update-index --chmod=+x`, no `chmod`).
  Nueva suite `kit/test/test_exec_modes.sh` (con auto-falsación) que
  comprueba estos modos vía `git ls-files -s`, añadida a `make test` y a
  `.github/workflows/ci.yml`.

### Documentation

- Documentado el modelo de dos capas de secretos (por nombre + por
  contenido), pasos de verificación y el porqué de mantener el eval set
  fuera de CI.

[Unreleased]: https://github.com/manuelcozar55/setup-claude-code/compare/v1.6.0...HEAD
[1.6.0]: https://github.com/manuelcozar55/setup-claude-code/compare/v1.5.1...v1.6.0
[1.5.1]: https://github.com/manuelcozar55/setup-claude-code/compare/v1.5.0...v1.5.1
[1.5.0]: https://github.com/manuelcozar55/setup-claude-code/compare/v1.4.1...v1.5.0
[1.4.1]: https://github.com/manuelcozar55/setup-claude-code/compare/v1.4.0...v1.4.1
[1.4.0]: https://github.com/manuelcozar55/setup-claude-code/compare/v1.3.0...v1.4.0
[1.3.0]: https://github.com/manuelcozar55/setup-claude-code/compare/v1.2.0...v1.3.0
[1.2.0]: https://github.com/manuelcozar55/setup-claude-code/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/manuelcozar55/setup-claude-code/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/manuelcozar55/setup-claude-code/releases/tag/v1.0.0
