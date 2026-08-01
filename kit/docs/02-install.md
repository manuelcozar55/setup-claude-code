# 02 · Instalación

Este documento cubre la instalación de la parte que el kit sí redistribuye: la config saneada de `~/.claude` (`CLAUDE.md`, `settings.json`, agentes, hooks, Sentinel) y el venv de herramientas. Los terceros (Headroom, el plugin superpowers, agent-browser) se documentan aparte en `03-headroom.md` y `04-superpowers.md`: el kit no lleva sus binarios.

## Prerrequisitos

**Plataforma**: `install.sh` solo soporta **Linux o WSL2** (comprueba `uname -s` y aborta con un mensaje claro en cualquier otra); es lo único que prueba la CI de este repo. macOS y Windows nativo no están soportados todavía, precisamente porque no hay pipeline real que lo demuestre. Si vienes de Windows, instala WSL2 y corre el instalador dentro de tu distribución Linux, no en PowerShell/cmd.

| Herramienta | Para qué | Verifica con |
|---|---|---|
| `git` | clonar el repo, y los guards de `secret-guard.sh`/`branch-guard.sh` operan sobre `git` | `git --version` |
| `node` ≥ 20 + `pnpm` | runtime de Claude Code y de agent-browser | `node --version` · `pnpm --version` |
| `python3` (≥ 3.10) + `venv` | Sentinel y los hooks Python corren sobre un venv propio, nunca sobre el Python del sistema | `python3 --version` |
| `gh` (GitHub CLI) | flujo de PRs desde Claude Code | `gh --version` |
| `jq` | `doctor.sh` y varios hooks parsean JSON con `jq`; sin él, `doctor.sh` falla explícitamente | `jq --version` |
| `uv` | gestor de paquetes Python que usa el kit vía `uv tool` (declarado en `permissions.allow` de `settings.json`) | `uv --version` |
| `gitleaks` (opcional, versión fijada `8.30.1`) | escaneo de contenido en el `pre-commit` de la Capa 2 de secretos; sin él, esa capa no puede activarse (la Capa 1, `secret-guard.sh`, funciona igual). Si no lo tienes, `install.sh` te ofrece instalarlo (release oficial + checksum SHA-256, nunca `curl \| bash`): confirma con `y`, o exporta `GITLEAKS_AUTO_INSTALL=1` para saltarte el prompt en un entorno no interactivo. Ver `docs/05-security.md` | `gitleaks version` |

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

## Paso 1 · Clonar

```bash
git clone <url-del-repo> setup-claude-code
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

`install.sh` es idempotente: si vuelves a ejecutarlo, cualquier fichero que fuera a pisar se guarda antes con backup con timestamp en `$CLAUDE_HOME/backups/`, y nunca sobreescribe sin copia. Puedes correrlo tantas veces como quieras.

## Paso 3 · Variables de entorno

```bash
cp .env.example $HOME/.claude/.env
$EDITOR $HOME/.claude/.env
```

Rellena `ANTHROPIC_API_KEY` y, si los usas, `PERPLEXITY_API_KEY` y `LANGSMITH_API_KEY`. El fichero `.env` **nunca** se sube al repo (el hook `secret-guard.sh` y el gate `scan-secrets.sh` están precisamente para que no ocurra por descuido).

## Paso 4 · Venv de herramientas

Los hooks del kit (Sentinel, `smart_approve.py`) se ejecutan con el Python de un venv dedicado, no con el del sistema:

```bash
python3 -m venv $HOME/.venvs/tools
$HOME/.venvs/tools/bin/pip install -r requirements-tools.txt
```

Este paso no es opcional para que los hooks funcionen: `settings.json` invoca literalmente `$HOME/.venvs/tools/bin/python3` para correr `sentinel_preflight.py` y `smart_approve.py`. Si prefieres exponer los CLIs instalados en tu `PATH` general:

```bash
ln -sf $HOME/.venvs/tools/bin/ruff $HOME/.local/bin/ruff
```

## Paso 5 · Terceros

El kit no instala esto por ti; solo lo documenta:

- **Headroom** (proxy local de contexto/coste): ver `docs/03-headroom.md`.
- **superpowers, los 8 agentes, y agent-browser**: ver `docs/04-superpowers.md`.

Lo anterior es el esqueleto. Para la pila completa (plugins de Claude Code, servidores MCP, skills adicionales como `graphify` o `deep-change`), ver `docs/08-plugins-mcp-y-skills.md`.

## Paso 6 · Verificar

```bash
bash doctor.sh
```

`doctor.sh` imprime un informe por componente: `PASS`, `WARN` o `FAIL`, y el "cómo se obtuvo" de cada línea. Sale con código 0 solo si no hay ningún `FAIL`. Los `WARN` son aceptables cuando corresponden a un componente opcional que aún no has instalado (el venv de tools, Headroom): el setup base funciona sin ellos, degradando con elegancia en vez de romperse.

Detalle completo del significado de cada línea y de cómo reproducirla en `07-verify.md`.
