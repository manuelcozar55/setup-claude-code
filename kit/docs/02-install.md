# 02 · Instalación

Este documento cubre la instalación de la parte que el kit sí redistribuye: la config saneada de `~/.claude` (`CLAUDE.md`, `settings.json`, agentes, hooks, Sentinel) y el venv de herramientas. Es la **única fuente** del procedimiento de instalación: el resto de documentos resume y enlaza aquí. Los terceros (agent-browser) se documentan aparte en `04-superpowers.md`: el kit no lleva sus binarios. El plugin `esenciales` es del kit y lo instala `install-plugins.sh` (ver `04-superpowers.md`).

## Prerrequisitos

**Plataforma**: `install.sh` solo soporta **Linux o WSL2** (comprueba `uname -s` y aborta con un mensaje claro en cualquier otra); es lo único que prueba la CI de este repo. macOS y Windows nativo no están soportados todavía, precisamente porque no hay pipeline real que lo demuestre. Si vienes de Windows, instala WSL2 y corre el instalador dentro de tu distribución Linux, no en PowerShell/cmd.

| Herramienta | Para qué | Verifica con |
|---|---|---|
| `bash`, `make` | `install.sh`, `doctor.sh`, los guards y la suite son bash; `make bootstrap` y `make test` | `bash --version` · `make --version` |
| `git` | clonar el repo, y los guards de `secret-guard.sh`/`branch-guard.sh` operan sobre `git` | `git --version` |
| `node` ≥ 20 + `pnpm` | runtime de Claude Code y de agent-browser | `node --version` · `pnpm --version` |
| `python3` (≥ 3.10) + `venv` | Sentinel y los hooks Python corren sobre un venv propio, nunca sobre el Python del sistema | `python3 --version` |
| `gh` (GitHub CLI) | flujo de PRs desde Claude Code | `gh --version` |
| `jq` | **obligatorio**: `install.sh` aborta si falta (fusiona `settings.json` con `jq`), los cuatro guards de Bash leen el payload con `jq` y sin él fallan en cerrado —deniegan en vez de permitir en silencio—, y `doctor.sh` lo marca `FAIL` | `jq --version` |
| `uv` | gestor de paquetes Python que usa el kit vía `uv tool` (declarado en `permissions.allow` de `settings.json`) | `uv --version` |
| `gitleaks` (opcional, versión fijada `8.30.1`) | escaneo de contenido en el `pre-commit` de la Capa 2 de secretos; sin él, esa capa no puede activarse (la Capa 1, `secret-guard.sh`, funciona igual). Si no lo tienes, `install.sh` te ofrece instalarlo (release oficial, verificado contra un checksum SHA-256 fijado en este repo — no descargado de la red —, nunca `curl \| bash`): confirma con `y`, o exporta `GITLEAKS_AUTO_INSTALL=1` para saltarte el prompt en un entorno no interactivo. Si el checksum no coincide, la instalación de `gitleaks` no rompe el resto (degrada a la Capa 1), pero deja una marca en `$CLAUDE_HOME/.gitleaks-checksum-mismatch` que `doctor.sh` reporta como `FAIL`. Ver `docs/05-security.md` | `gitleaks version` |

Comprueba todo de una vez:

```bash
git --version && node --version && pnpm --version && python3 --version && gh --version && jq --version
```

Si falta `pnpm`, actívalo con corepack (viene con Node ≥ 16.9, no hace falta instalar nada por pipe a shell):

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

## El camino corto: `make bootstrap`

```bash
git clone https://github.com/manuelcozar55/setup-claude-code.git
cd setup-claude-code
make bootstrap
```

`make bootstrap` hace cuatro cosas y para si alguna falla: crea tu `config/profile.yaml` desde el ejemplo (es tuyo, está en `.gitignore` y no viaja: tu nombre, tu nivel de coach y tu oráculo), instala el kit en `~/.claude`, ejecuta el oráculo del repo (`make test`) y corre `kit/doctor.sh`. Los pasos siguientes son el mismo camino a mano, más lo opcional.

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

`install.sh` es idempotente: si vuelves a ejecutarlo, cualquier fichero que fuera a pisar se guarda antes con backup en `$CLAUDE_HOME/backups/<fecha>-<pid>-<aleatorio>/`, y nunca sobreescribe sin copia; reinstalar sin cambios no crea un segundo backup. Copia (no enlaza) `settings.json`, `CLAUDE.md`, los hooks, los agentes, las skills del método y Sentinel. `settings.json` se **fusiona** con `jq`, no se pisa: tus claves propias sobreviven, y un symlink no se toca.

**Diff-first.** Si tu `$CLAUDE_HOME` es un repo git con remoto (un repo de configuración propio), el instalador **no escribe nada**: genera aparte el árbol que instalaría y te muestra el diff (nuevos, idénticos, modificados) para que copies lo que quieras ([ADR 008](../../knowledge/DECISIONS/008-install-diff-first.md)). `--apply` fuerza la escritura real, siempre con backup; `--plan` fuerza el modo diff aunque no sea un repo git.

### Modelo, ventana y esfuerzo: una sola fuente (medido)

- **La ventana de 1M va por el sufijo `[1m]` del id de modelo**, no por la cabecera beta `context-1m` (falso indicador) ni por `--1m` (estampa el sufijo sobre cualquier modelo y rompe Haiku). Ponlo en `env.ANTHROPIC_MODEL`, p. ej. `"opus[1m]"`.
- **Una sola fuente del modelo.** `/model` no persiste: el `env` se reaplica en cada arranque y gana. Si fijas `ANTHROPIC_MODEL`, quita la clave `model` de `settings.json`: queda muerta y confunde.
- **`effortLevel: "max"` cae a `high` en silencio.** El máximo que se puede fijar en settings es `xhigh` (el de la plantilla).
- **El airbag se mueve con `CLAUDE_CODE_AUTO_COMPACT_WINDOW`** (la plantilla: `250000`; compacta solo a la ventana − 33 000 tokens, y sobre esa línea miden sus % los hooks de `nucleo.md`). Sin sufijos `k`/`m`: se lee como entero. `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` es un hook de test, no una opción: solo baja el umbral, y en la ruta de 1M no hace nada.
- `cleanupPeriodDays: 14` acota cuánto tiempo se guardan los transcripts en disco.

## Paso 3 · Variables de entorno

```bash
cp .env.example $HOME/.claude/.env
$EDITOR $HOME/.claude/.env
```

Rellena `ANTHROPIC_API_KEY` y, si la usas, `PERPLEXITY_API_KEY`. El fichero `.env` **nunca** se sube al repo (el hook `secret-guard.sh` y el gate `scan-secrets.sh` están precisamente para que no ocurra por descuido).

## Paso 3b · CLIs `handoff` y `oraculo`

`install.sh` copia `bin/handoff` y `bin/oraculo` a `$CLAUDE_HOME/bin/` (diff-first, ejecutables) e imprime la orden
para enlazarlos a tu `PATH`:

```bash
mkdir -p "$HOME/.local/bin" && ln -sf "$CLAUDE_HOME/bin/handoff" "$HOME/.local/bin/handoff" && ln -sf "$CLAUDE_HOME/bin/oraculo" "$HOME/.local/bin/oraculo"
```

Son bash + `jq`, sin red, y valen igual en Claude Code, Codex y opencode (`handoff --help`, `oraculo --help`).

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

- **esenciales, los 8 agentes, y agent-browser**: ver `docs/04-superpowers.md`. Los plugins se instalan por referencia desde su marketplace con `bash install-plugins.sh` (diff-first).

Lo anterior es el esqueleto. Para la pila completa (plugins de Claude Code, servidores MCP, skills adicionales como `graphify` o `deep-change`), ver `docs/08-plugins-mcp-y-skills.md`.

## Paso 6 · Verificar

```bash
bash doctor.sh
```

`doctor.sh` imprime un informe por componente: `PASS`, `WARN` o `FAIL`, y el "cómo se obtuvo" de cada línea. Sale con código 0 solo si no hay ningún `FAIL`. Los `WARN` son aceptables cuando corresponden a un componente opcional que aún no has instalado (el venv de tools, `rtk`, `gitleaks`): el setup base funciona sin ellos, degradando con elegancia en vez de romperse.

Un caso **no** degrada con elegancia y por eso es `FAIL`: que `ANTHROPIC_BASE_URL` enrute la API a un proxy que no contesta. Ahí Claude Code se queda sin poder hablar con la API, y el síntoma no se parece a un problema de configuración. El `settings.json` que distribuye el kit no fija esa variable: si `doctor.sh` la encuentra, viene de tu config (por ejemplo, restos de un proxy que ya no usas) y basta con quitarla.

Detalle completo del significado de cada línea y de cómo reproducirla en `07-verify.md`.

## Paso 7 · Capa 2 de secretos (opt-in, por repositorio)

`install.sh` nunca la activa por su cuenta en un repo que no hayas nombrado. Desde dentro del repo que quieras proteger (requiere `gitleaks`):

```bash
cd tu-repo && bash /ruta/al/kit/install.sh --enable-secrets-layer2
```

Para falsos positivos de los guards, usa `sentinel-allowlist.json` en vez de desactivarlos. Detalle en `05-security.md`.

## Desinstalar

```bash
bash uninstall.sh          # desde la raíz del repo; dry-run: dice qué haría y no toca nada
bash uninstall.sh --apply  # restaura el backup más reciente (antes hace backup del estado actual)
bash uninstall.sh --list   # enumera los backups disponibles
```
