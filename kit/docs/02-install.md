# 02 · Instalación

Este documento cubre la configuración que el kit redistribuye en `~/.claude` y los
extras opcionales. La matriz de lo instalado, lo cargado por el lanzador y lo externo
está en [`10-onboarding.md`](10-onboarding.md#0--qué-vas-a-levantar).
Si recibiste una consolidación con `BUILD_ID`, sigue también [`ENTREGA.md`](../../ENTREGA.md):
`scripts/scc.sh` carga los plugins incluidos; `install-plugins.sh` es la alternativa global.

## Prerrequisitos

**Plataforma**: `install.sh` solo soporta **Linux o WSL2** (comprueba `uname -s` y aborta con un mensaje claro en cualquier otra); es lo único que prueba la CI de este repo. macOS y Windows nativo no están soportados todavía, precisamente porque no hay pipeline real que lo demuestre. Si vienes de Windows, instala WSL2 y corre el instalador dentro de tu distribución Linux, no en PowerShell/cmd.

| Herramienta | Para qué | Verifica con |
|---|---|---|
| `bash`, `make` | `install.sh`, `doctor.sh`, los guards y la suite son bash; `make bootstrap` y `make test` | `bash --version` · `make --version` |
| `git` | clonar el repo, y los guards de `secret-guard.sh`/`branch-guard.sh` operan sobre `git` | `git --version` |
| Claude Code autenticado | ejecutar las sesiones; la distribución nativa no necesita Node para arrancar | `claude --version` |
| `python3` (≥ 3.10) | Sentinel y los hooks Python; usan el venv si existe y, si no, el Python del sistema | `python3 --version` |
| `zip`, `unzip` | copias de seguridad y restauración con `scripts/backup.sh` y `uninstall.sh --apply`; en Debian: `sudo apt install zip unzip` | `zip -v` · `unzip -v` |
| `node` + `pnpm` (opcionales) | herramientas JavaScript externas, como agent-browser; según los requisitos de cada herramienta | `node --version` · `pnpm --version` |
| `gh` (opcional) | flujo de PRs en GitHub | `gh --version` |
| `jq` | **obligatorio**: `install.sh` aborta si falta (fusiona `settings.json` con `jq`), los cinco guards de Bash leen el payload con `jq` y sin él fallan en cerrado —deniegan en vez de permitir en silencio—, y `doctor.sh` lo marca `FAIL` | `jq --version` |
| `uv` (opcional) | gestor de paquetes Python; solo lo necesitas si instalas herramientas con `uv tool` | `uv --version` |
| `gitleaks` (opcional, versión fijada `8.30.1`) | escaneo de contenido en el `pre-commit` de la Capa 2 de secretos; sin él, esa capa no puede activarse (la Capa 1, `secret-guard.sh`, funciona igual). Si no lo tienes, `install.sh` te ofrece instalarlo (necesita `curl` y `ca-certificates`; release oficial, verificado contra un checksum SHA-256 fijado en este repo — no descargado de la red —, nunca `curl \| bash`): confirma con `y`, o exporta `GITLEAKS_AUTO_INSTALL=1` para saltarte el prompt en un entorno no interactivo. Si el checksum no coincide, la instalación de `gitleaks` no rompe el resto (degrada a la Capa 1), pero deja una marca en `$CLAUDE_HOME/.gitleaks-checksum-mismatch` que `doctor.sh` reporta como `FAIL`. Ver `docs/05-security.md` | `gitleaks version` |

Comprueba todo de una vez:

```bash
git --version && python3 --version && jq --version && claude --version
```

Si necesitas herramientas JavaScript y tu instalación de Node incluye corepack,
puedes activar `pnpm` con:

```bash
corepack enable
corepack prepare pnpm@latest --activate
```

**Aviso conocido (pnpm ≥ 11)**: desde la v11, pnpm movió el directorio de binarios globales de `$PNPM_HOME` a `$PNPM_HOME/bin`. Si tu `.bashrc`/`.zshrc` lo generó un `pnpm setup` de una versión anterior, solo tendrás en el `PATH` la ruta vieja, y todo lo que instales después con `pnpm add -g` (incluido `agent-browser`, ver `04-superpowers.md`) quedará invisible para el shell aunque la instalación termine sin ningún error. Comprueba que la ruta activa está en tu `PATH`:

```bash
echo "$PATH" | tr ':' '\n' | grep -F "$(pnpm config get global-bin-dir)"
```

Si no aparece nada, añade esa ruta a mano a tu `.bashrc`/`.zshrc`.

**Si vienes de Windows**: clona **dentro** de WSL (`~/`), no en `/mnt/c/` (más lento y complica el bit de ejecución). Si tienes `git config core.autocrlf true`, no lo combatas: el `.gitattributes` del repo fuerza LF en scripts y hooks, porque un hook con CRLF no se ejecuta (`bad interpreter: /bin/bash^M`) y el fallo se lee como "el hook no hace nada".

## El camino corto: `bash kit/install.sh`

```bash
git clone https://github.com/manuelcozar55/setup-claude-code.git
cd setup-claude-code
bash kit/install.sh
bash kit/doctor.sh
```

Esta es la vía para quien solo quiere usar el kit. Instala la config en `~/.claude`, enlaza `handoff` y `oraculo` en tu `PATH` y no ejecuta la suite de tests. Para el primer día completo (prerrequisitos, primer proyecto, bucle diario) sigue [`10-onboarding.md`](10-onboarding.md).

`make bootstrap` **no** es la vía de quien solo usa el kit. Está pensado para quien trabaja en este repo: crea `config/profile.yaml` (tu perfil del harness de la raíz), instala, ejecuta `make test` (más de un minuto) y corre `doctor.sh`. Si lo usas, los avisos de `install.sh` quedan tapados bajo la salida de los tests: repásalos con `bash kit/install.sh`.

Los pasos siguientes son el mismo camino con más detalle, más lo opcional.

## Paso 1 · Clonar

```bash
git clone https://github.com/manuelcozar55/setup-claude-code.git
cd setup-claude-code/kit
```

## Paso 2 · Instalar la config saneada

```bash
bash install.sh
```

Por defecto instala en `$HOME/.claude`. Si quieres probarlo primero en una ruta aislada (recomendado la primera vez):

```bash
CLAUDE_HOME=/ruta/alternativa bash install.sh
```

Con un `CLAUDE_HOME` que no es `$HOME/.claude` el instalador no toca `~/.local/bin`: imprime las órdenes `ln -s` de `handoff` y `oraculo` por si quieres enlazarlos tú (Paso 3b).
Esta variable selecciona el destino de los archivos, no el perfil que Claude Code carga
automáticamente. Los comandos de la plantilla usan `$HOME/.claude`. Para una inspección
sin activar nada, usa `bash install.sh --plan`; para probar la instalación completa,
usa un HOME de prueba o el ensayo `scripts/aceptacion-local.sh` de la entrega.

`install.sh` es idempotente: si vuelves a ejecutarlo, cualquier fichero que fuera a pisar se guarda antes con backup en `$CLAUDE_HOME/backups/<fecha>-<pid>-<aleatorio>/`, y nunca sobreescribe sin copia; reinstalar sin cambios no crea un segundo backup. Copia (no enlaza) `settings.json`, `CLAUDE.md`, los hooks, los agentes, las skills del método y Sentinel. `settings.json` se **fusiona** con `jq`, no se pisa: tus claves propias (permisos, `env`, plugins) sobreviven, y un symlink no se toca. Los hooks se fusionan **por propietario**. El kit sustituye solo las entradas cuyo comando es uno de sus scripts de `.claude/hooks/` o `.claude/sentinel/`, incluidos los que ya retiró. Cuenta tanto si va a secas como tras un intérprete o con `optional-hook.sh`. Un comando que además hace otra cosa es tuyo. Tus hooks se quedan detrás de los suyos, en el mismo evento y con su `matcher`, y `doctor.sh` los lista como hooks ajenos al kit. Lo que no tiene forma de hook (un evento que no es lista o un grupo sin `hooks`) se descarta y queda en la copia de seguridad. Hasta la 1.5.0 el kit sustituía el bloque entero y se llevaba los tuyos. La excepción es `permissions.disableBypassPermissionsMode`: queda en `"disable"` siempre, también en el árbol del plan diff-first, y si tu valor era otro el instalador lo dice. Dos claves tuyas que dejan al kit sin efecto se respetan, pero se avisan al final: `disableAllHooks: true` (no corre ningún hook, tampoco los guards; `doctor.sh` lo marca `FAIL`) y `permissions.defaultMode: "bypassPermissions"` (con `"disable"` queda inerte).

**Si ya tenías un `CLAUDE.md`.** El instalador no lo toca y deja la plantilla del kit en `CLAUDE.kit.md`. Al terminar te avisa de lo que falta: añade la línea `@AGENTS.md` a tu `CLAUDE.md` para que Claude Code cargue las reglas del kit (`AGENTS.md` sí se instala). Sin esa línea los hooks funcionan, pero el modelo no conoce la convención de `nucleo.md` ni los comandos `handoff` y `oraculo`. `doctor.sh` lo marca con un `WARN`. Para el resto de la plantilla (sección «Contexto»), copia lo que quieras de `CLAUDE.kit.md`.

**Diff-first.** Si tu `$CLAUDE_HOME` es un repo git con remoto (un repo de configuración propio), el instalador **no escribe nada**: genera aparte el árbol que instalaría y te muestra el diff (nuevos, idénticos, modificados) para que copies lo que quieras ([ADR 008](../../knowledge/DECISIONS/008-install-diff-first.md)). El plan parte de lo que tienes instalado y enseña lo que haría `--apply`: `settings.json` sale fusionado, y un `CLAUDE.md` o `AGENTS.md` tuyo sale intacto, con la versión del kit en `*.kit.md`. Hasta la 1.5.0 partía de un árbol vacío y daba por borrados tu `env`, tus permisos, tus hooks y tu `CLAUDE.md`, aunque `--apply` los conservase. `--apply` fuerza la escritura real, siempre con backup; `--plan` fuerza el modo diff aunque no sea un repo git. El árbol del plan queda en `${TMPDIR:-/tmp}/mcharness-plan.XXXXXX` y no se borra solo (lo necesitas para el diff y para copiar lo que quieras); bórralo con `rm -r` cuando termines.

### Modelo, ventana y esfuerzo: una sola fuente (medido)

- **El modelo se fija con la clave `model` de `settings.json`.** La plantilla trae `"model": "opus"`. Opus 4.7 y posteriores ya traen la ventana de 1M sin ningún sufijo. El sufijo `[1m]` (`"opus[1m]"`) solo hace falta en Opus 4.6 y Sonnet 4.6. Si tu plan no incluye 1M, deja `"opus"` sin sufijo. `claude plugin marketplace add` (Claude Code 2.1.309) reescribe `"opus"` a `"opus[1m]"` en tu `settings.json`: es una normalización de Claude Code, no del kit, y `doctor.sh` excluye `settings.json` de su comprobación de deriva.
- **Una sola fuente del modelo.** No pongas además `env.ANTHROPIC_MODEL`: dos fuentes confunden. Para comprobar qué modelo y qué ventana usa de verdad tu sesión, escribe `/status` en Claude Code.
- **No uses `--1m` al arrancar**: estampa el sufijo sobre cualquier modelo y rompe Haiku. Tampoco te fíes de la cabecera beta `context-1m`: no indica nada.
- **`effortLevel: "max"` cae a `high` en silencio.** El máximo que se puede fijar en settings es `xhigh` (el de la plantilla). **Límite conocido:** según la documentación de Claude Code (`model-config`), un `effortLevel` de primer nivel en los ajustes de usuario solo rige modelos anteriores a Opus 5.5; para Opus 5.5 y posteriores lo ignora y manda el nivel guardado por modelo (`/effort` o `/model`). Si tu alias `opus` resuelve a uno de ellos, el `xhigh` de la plantilla puede ser inerte: compruébalo con `/status` y fíjalo con `/effort`.
- **El airbag se mueve con `CLAUDE_CODE_AUTO_COMPACT_WINDOW`** (la plantilla: `250000`; compacta solo a la ventana − 33 000 tokens, y sobre esa línea miden sus % los hooks de `nucleo.md`). Sin sufijos `k`/`m`: se lee como entero. `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` es un hook de test, no una opción: solo baja el umbral, y en la ruta de 1M no hace nada.
- **Por qué 250 K y no más** (decisión, no descuido): es el freno de coste. Cada turno reenvía el contexto entero, así que la ventana es el precio del turno; con 1M de ventana el mismo trabajo cuesta mucho más por turno. El coste de quedarse en 250 K también está medido: una compactación en una sesión autónoma larga llegó a `pre_tokens` 218 467 y tardó 129 s (`duration_ms` 129 277), y otra sesión llegó a 208 709 tokens sin compactar. Si una tarea concreta necesita más margen, súbela solo en esa ejecución; no cambies la plantilla.
- **Cambiarla en una ejecución: `--settings`, no la variable de entorno.** En las pruebas, `CLAUDE_CODE_AUTO_COMPACT_WINDOW=400000 claude -p …` no movió la ventana (causa probable, no verificada: el `env` de `settings.json` se aplica después). Esto sí: `claude -p … --settings '{"env":{"CLAUDE_CODE_AUTO_COMPACT_WINDOW":"400000"}}'` (entero, sin `k`). Compruébalo con `/context` en una sesión interactiva o con el `compact_boundary` del stream-json.
- `cleanupPeriodDays: 14` acota cuánto tiempo se guardan los transcripts en disco.

## Paso 3 · Autenticación y servicios externos

Cada compañero inicia sesión en Claude Code con su propia cuenta. El kit no incluye
credenciales. Si utiliza un proveedor por API o un MCP externo, debe configurar ese
servicio según su documentación y la política de su organización.
Copiar una plantilla de variables a disco no las carga automáticamente en Claude Code.
Las claves y los archivos privados quedan fuera del paquete y de Git.

- **Sin TUI** (SSH, WSL sin ventana, un host nuevo): `claude auth login --email tu@correo` inicia
  sesión desde la terminal y `claude auth status` (JSON: `loggedIn`, `email`, `subscriptionType`) lo comprueba.
- **El login va por cada directorio de configuración.** Una sesión iniciada en el host no llega a otro
  `CLAUDE_CONFIG_DIR`, ni a una distro WSL: repite el login en cada uno.
- **`CLAUDE_CONFIG_DIR` vacía no es lo mismo que sin definir**: `CLAUDE_CONFIG_DIR="" claude auth status`
  da `loggedIn:false`. Quítala con `unset CLAUDE_CONFIG_DIR`; `doctor.sh` avisa (WARN) si la encuentra vacía.

## Paso 3b · CLIs `handoff`, `oraculo` y `cupo`

`install.sh` copia `bin/handoff`, `bin/oraculo` y `bin/cupo` a `$CLAUDE_HOME/bin/` (ejecutables) y crea tres enlaces en `~/.local/bin/`:

- `~/.local/bin/handoff` → `$CLAUDE_HOME/bin/handoff`
- `~/.local/bin/oraculo` → `$CLAUDE_HOME/bin/oraculo`
- `~/.local/bin/cupo` → `$CLAUDE_HOME/bin/cupo`

Reglas del enlace: solo se crea si `CLAUDE_HOME` es `$HOME/.claude` y además no existe nada con ese nombre, o ya era un enlace a `$CLAUDE_HOME/bin`. Con otro `CLAUDE_HOME` (una ruta de prueba, la CI) no escribe en `~/.local/bin`, porque al borrar esa ruta los enlaces quedarían colgando: imprime las órdenes `ln -s` y las ejecutas tú si quieres. Nunca pisa un fichero tuyo ni un enlace a otro sitio: en ese caso te avisa y lo dejas tú como prefieras. En modo diff-first no escribe nada y lo anota en el plan.

Si `~/.local/bin` no está en tu `PATH`, el instalador lo dice al final. En Debian y Ubuntu esa carpeta entra en el `PATH` al iniciar sesión **solo si ya existía**: si la acaba de crear el instalador, **abre una terminal nueva** antes de usar los comandos. Compruébalo con `command -v handoff oraculo cupo`.

`handoff` y `oraculo` son bash + `jq`, sin red, y valen igual en Claude Code, Codex y opencode (`handoff --help`, `oraculo --help`). `cupo` hace un turno mínimo de `claude -p` (consume un turno, no es offline): ver [`06-routine.md`](06-routine.md#sesiones-autónomas-largas). El camino absoluto (`$CLAUDE_HOME/bin/handoff`) funciona siempre, aunque el `PATH` no esté listo.

## Paso 4 · Venv de herramientas

Los hooks del kit (Sentinel y los guards en Python) se ejecutan preferentemente con el Python de un venv dedicado:

```bash
python3 -m venv $HOME/.venvs/tools
$HOME/.venvs/tools/bin/pip install -r requirements-tools.txt
```

Este paso es opcional. `settings.json` no invoca el venv directamente: llama a `hooks/optional-hook.sh --python`, que prefiere `$HOME/.venvs/tools/bin/python3`, cae al `python3` del sistema si no existe, y solo si no hay ninguno de los dos deja el hook en no-op silencioso. Como `sentinel_preflight.py` usa solo la librería estándar, con el `python3` del sistema siguen funcionando. Lo que se pierde sin el venv son los CLIs de `requirements-tools.txt` (`markitdown`, `ast-grep-cli`, `basedpyright`, `ruff`) y `pyyaml`, que es lo que `kit/evals/run.sh` necesita para leer las tareas. `doctor.sh` lo refleja: el venv ausente es `WARN`, no `FAIL`. Si prefieres exponer los CLIs instalados en tu `PATH` general:

```bash
ln -sf $HOME/.venvs/tools/bin/ruff $HOME/.local/bin/ruff
```

## Paso 5 · Terceros

El kit no instala esto por ti; solo lo documenta:

- **Los 6 agentes y las skills del método** ya están instalados con la base.
- **esenciales** está incluido en el repo y `scripts/scc.sh` lo carga localmente; la
  instalación global se hace con `bash install-plugins.sh` (diff-first).
  Que un plugin figure en `enabledPlugins` no demuestra que esté cargado: comprueba `/plugin`.
- **agent-browser** es una herramienta externa: ver `docs/04-superpowers.md`.
- **El mod `cockpit`** (opcional): da `/handoff` y `/nueva` dentro de Claude Code. Instálalo con `claude plugin install cockpit@setup-claude-code` después de registrar el marketplace en el tag del kit (las dos órdenes, en [`11-cockpit.md`](11-cockpit.md)). Sin él, `handoff --desde` hace lo mismo desde la terminal.

Lo anterior es el esqueleto. Para la pila completa (plugins de Claude Code, servidores MCP, skills adicionales como `graphify` o `deep-change`), ver `docs/08-plugins-mcp-y-skills.md`.

## Paso 6 · Verificar

```bash
bash doctor.sh
```

`doctor.sh` imprime un informe por componente: `PASS`, `WARN` o `FAIL`, y el "cómo se obtuvo" de cada línea. Sale con código 0 solo si no hay ningún `FAIL`. Para lo de este documento comprueba que:

- `$CLAUDE_HOME/bin/handoff`, `$CLAUDE_HOME/bin/oraculo` y `$CLAUDE_HOME/templates/nucleo.md` existen. Si falta alguno es `FAIL`: repite `bash install.sh`.
- `settings.json` no tiene `disableAllHooks: true`. Con esa clave no corre ningún hook, tampoco los guards, y es `FAIL`: quítala.
- `handoff` y `oraculo` se resuelven en tu `PATH` y son los del kit (`readlink -f` igual al de `$CLAUDE_HOME/bin/<cli>`). Si no se resuelven, `WARN`: abre una terminal nueva o revisa el Paso 3b. Si el primero del `PATH` es otro programa con ese nombre, también `WARN`, con su ruta: la sugerencia es `ln -s`, nunca `ln -sf`, porque pisaría ese otro.
- Tu `$CLAUDE_HOME/CLAUDE.md` contiene `@AGENTS.md` (o `@…AGENTS.md`). Si no, `WARN`: ver el aviso del Paso 2. Los `WARN` son aceptables cuando corresponden a un componente opcional que aún no has instalado (el venv de tools, `rtk`, `gitleaks`): el setup base funciona sin ellos, degradando con elegancia en vez de romperse.

Un caso **no** degrada con elegancia y por eso es `FAIL`: que `ANTHROPIC_BASE_URL` enrute la API a un proxy que no contesta. Ahí Claude Code se queda sin poder hablar con la API, y el síntoma no se parece a un problema de configuración. El `settings.json` que distribuye el kit no fija esa variable: si `doctor.sh` la encuentra, viene de tu config (por ejemplo, restos de un proxy que ya no usas) y basta con quitarla.

Detalle completo del significado de cada línea y de cómo reproducirla en `07-verify.md`.

## Paso 7 · Tu primer proyecto

El estado de trabajo (`.claude/estado/nucleo.md`) vive en la raíz git del proyecto. Una carpeta sin git no es proyecto: haz `git init` primero. Después:

```bash
cd tu-proyecto
git init            # solo si aún no es un repo
handoff --iniciar   # crea .claude/estado/nucleo.md desde la plantilla
```

`handoff --iniciar` no sobrescribe nada: si `nucleo.md` ya existe, lo dice y sale sin tocarlo. Añade `.claude/estado/` a `.git/info/exclude`, así que no ensucia tus commits. Fuera de un proyecto git termina con error (exit 3). El bucle diario, paso a paso, está en [`10-onboarding.md`](10-onboarding.md).

Dónde va cada cosa: lo temporal, en un `mktemp`; el estado, los informes y los checkpoints, en `.claude/estado/` del proyecto (se crea solo y queda ignorado por git); lo privado de la máquina, en `~/.claude`. `handoff --informe <tema>` crea y te da la ruta de un informe.

## Paso 8 · Capa 2 de secretos (opt-in, por repositorio)

`install.sh` nunca la activa por su cuenta en un repo que no hayas nombrado. Desde dentro del repo que quieras proteger (requiere `gitleaks`):

```bash
cd tu-repo && bash /ruta/al/kit/install.sh --enable-secrets-layer2
```

Para falsos positivos de los guards, usa `sentinel-allowlist.json` en vez de desactivarlos. Detalle en `05-security.md`.

## Actualizar

Desde el clon, pasa a la versión que quieras (`vX.Y.Z` es el tag) y reinstala:

```bash
git fetch --tags
git checkout vX.Y.Z
bash kit/install.sh
bash kit/doctor.sh
claude plugin update cockpit@setup-claude-code   # solo si instalaste el cockpit
```

`install.sh` es idempotente: lo que cambia se guarda antes en `$CLAUDE_HOME/backups/<fecha>-…/` y tu `settings.json` se fusiona, no se pisa (tus hooks se conservan junto a los del kit, ver el Paso 2). Actualiza el kit y el cockpit a la vez: `install.sh` mueve el marketplace del kit al tag nuevo; después, `claude plugin marketplace add "manuelcozar55/setup-claude-code@v$(cat VERSION)"` y `claude plugin update cockpit@setup-claude-code`. Para volver a una versión anterior, haz `git checkout` de su tag y repite las dos órdenes de arriba; los ficheros que esa versión ya no trae no se borran de `$CLAUDE_HOME`.

## Desinstalar y volver atrás

```bash
bash uninstall.sh          # desde la raíz del repo; dry-run: dice qué haría y no toca nada
bash uninstall.sh --apply  # restaura el backup más reciente (antes hace backup del estado actual)
bash uninstall.sh --list   # enumera los backups disponibles
```

Qué hace y qué no. `uninstall.sh` **restaura** el backup más reciente: los ficheros que una instalación o reinstalación sobrescribió (en `$CLAUDE_HOME/backups/`) o un snapshot completo de `scripts/backup.sh` (en `$HOME/backups/`). **No borra** lo que el instalador creó en limpio. Si no hay ningún backup (una máquina nueva con una sola instalación), termina con error: no hay nada que restaurar.

Para quitar el kit del todo, a mano:

- Los enlaces `~/.local/bin/handoff` y `~/.local/bin/oraculo`.
- Los ficheros del kit en `~/.claude` que no quieras conservar (`bin/`, `hooks/`, `agents/`, las skills del método, `templates/nucleo.md`, `AGENTS.md`) y las entradas de `hooks` del `settings.json`. Si ya tenías una config tuya, `bash uninstall.sh --apply` te devuelve su versión anterior.
- El cockpit, si lo instalaste: `claude plugin uninstall cockpit@setup-claude-code`.
- La política gestionada de `/etc/claude-code/`, si tu organización la instaló: la quita quien tenga permisos de administrador, no el kit.
