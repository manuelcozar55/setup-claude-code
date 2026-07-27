# 08 · Plugins, MCP y skills: la pila completa

La base que instala este kit (`CLAUDE.md`, `settings.json`, hooks, agentes, Sentinel) es el esqueleto: lo que garantiza guardarraíles deterministas y tiering de modelo desde el primer arranque. Para usar Claude Code "como el autor" hace falta además la pila que rodea ese esqueleto: los plugins declarados en `settings.json`, los servidores MCP que le dan capacidades externas, las skills adicionales que invoca el `CLAUDE.md`, y unos cuantos prerrequisitos de sistema. Mismo principio que en el resto del kit: **terceros se documentan, no se redistribuyen.**

## Plugins de Claude Code

`claude/settings.json` declara ocho plugins en `enabledPlugins`. Cinco vienen del marketplace oficial `claude-plugins-official` (ya conocido por Claude Code, no requiere alta manual); los otros tres vienen de marketplaces externos que el propio `settings.json` del kit ya declara en `extraKnownMarketplaces`, así que Claude Code los reconoce sin que tengas que darlos de alta a mano.

| Plugin | Para qué | Cómo |
|---|---|---|
| `superpowers@claude-plugins-official` | el método y sus skills (ver `04-superpowers.md`) | `/plugin` |
| `code-review@claude-plugins-official` | revisión de PRs | `/plugin` |
| `github@claude-plugins-official` | flujos de GitHub (PRs, issues) | `/plugin` |
| `skill-creator@claude-plugins-official` | crear y editar skills | `/plugin` |
| `frontend-design@claude-plugins-official` | diseño de interfaces | `/plugin` |
| `codex@openai-codex` | integración con Codex | marketplace externo (GitHub `openai/codex-plugin-cc`), ya declarado en `extraKnownMarketplaces`; activa con `/plugin` |
| `understand-anything@understand-anything` | grafos de conocimiento del código; aporta las skills `understand-*` | marketplace externo (GitHub `Lum1104/Understand-Anything`), ya declarado en `extraKnownMarketplaces`; activa con `/plugin` |
| `langsmith-tracing@langsmith-claude-code-plugins` | trazas de ejecución en LangSmith | marketplace externo (GitHub `langchain-ai/langsmith-claude-code-plugins`), ya declarado en `extraKnownMarketplaces`; viene **desactivado** por defecto (`false` en `enabledPlugins`); actívalo con `/plugin` si lo necesitas |

Los cinco primeros se activan (o reinstalan si hiciera falta) con el comando interactivo `/plugin` dentro de una sesión de Claude Code. Los tres últimos, al venir de marketplaces externos ya declarados en el `settings.json` que instala este kit, se activan exactamente igual: `/plugin` los lista porque el marketplace ya es conocido, no hace falta registrar nada a mano. Verifica el estado (instalados, activos, disponibles) con:

```bash
/plugin
```

## Servidores MCP

Capacidades externas que Claude Code invoca vía el protocolo MCP. Conocidos en este setup:

- **perplexity**: búsqueda web. Requiere `PERPLEXITY_API_KEY` en tu `$HOME/.claude/.env` (ver `02-install.md`, paso 3).
- **linkedin**: mensajería. Por seguridad, `settings.json` deniega explícitamente `mcp__linkedin__send_message` y `mcp__linkedin__connect_with_person` en `permissions.deny`: el servidor puede estar activo, pero esas dos acciones concretas quedan bloqueadas sin excepción.

Cómo se añaden: `claude mcp add ...`. La sintaxis exacta (transporte, comando o URL, variables de entorno que necesite) depende de cada servidor; consulta su propio repositorio antes de darlo de alta. El kit no incluye claves ni configuraciones MCP con secretos: cualquier credencial vive solo en tu `.env` local, nunca en este repo.

**Headroom no es un MCP más.** No se añade con `claude mcp add`: es el proxy de contexto (ver `03-headroom.md`), cableado vía `ANTHROPIC_BASE_URL` y el hook `rtk hook claude`. Además de comprimir el contexto, expone sus propias herramientas MCP (por ejemplo `headroom_stats`) directamente a través de su instalación con `rtk`; viene con Headroom, no se registra aparte.

Verifica los servidores dados de alta con:

```bash
claude mcp list
```

## Skills adicionales

El `CLAUDE.md` que instala este kit invoca varias skills que viven en `$HOME/.claude/skills/` y que el kit no redistribuye, mismo principio que con superpowers: se documentan aquí, no se empaquetan en `kit/`.

| Skill | Trigger | Para qué |
|---|---|---|
| `graphify` | `/graphify` | cualquier input a grafo de conocimiento |
| `deep-change` | `/deep-change` | el bucle operativo brainstorm → plan → execute → verify para cambios sustanciales |
| `ultrawork` | `/ultrawork` | modo de máxima potencia: todos los agentes, en paralelo, sin paradas |
| `agent-browser` | se carga antes de cualquier tarea de navegador | estándar de automatización de navegador (ya cubierta en `04-superpowers.md`) |

Instálalas desde su origen o adáptalas a tu propio setup. Nota honesta: el `CLAUDE.md` las invoca como si estuvieran siempre disponibles, pero son herramientas, no leyes de hierro (esas son las cuatro de superpowers, ver `04-superpowers.md`): si una de estas skills no está instalada en tu máquina, el setup degrada con elegancia, no se rompe.

Verifica qué tienes instalado con:

```bash
ls $HOME/.claude/skills/
```

## Prerrequisitos

Todos estos van en `02-install.md`; recordatorio de la pila que usa el setup completo:

| Herramienta | Para qué | Verifica con |
|---|---|---|
| `uv` | gestor de paquetes Python; el kit lo usa vía `uv tool` (declarado en `permissions.allow` de `settings.json`) | `uv --version` |
| venv de tools (`$HOME/.venvs/tools`) | ejecuta Sentinel y `smart_approve.py` con un Python propio, no el del sistema (ver `02-install.md`, paso 4) | `test -x $HOME/.venvs/tools/bin/python3` |
| `rtk` (Headroom) | el proxy de contexto que da soporte al servidor MCP `headroom` (ver `03-headroom.md`) | `rtk --version` |
| `pnpm` | instala `agent-browser` y otros paquetes globales de Node | `pnpm --version` |

## Verificación rápida

```bash
/plugin                  # plugins: activados y disponibles
claude mcp list           # servidores MCP dados de alta
ls $HOME/.claude/skills/   # skills instaladas
```
