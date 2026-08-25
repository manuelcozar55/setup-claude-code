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

- **headroom**: el MCP del proxy de contexto (ver `03-headroom.md`). Es el único que este setup deja registrado en ámbito global.
- **firecrawl**: scraping y búsqueda web. Requiere su propia clave en `$HOME/.claude/.env`.
- **perplexity**: búsqueda web. Dado de baja en este setup el 2026-08-17 (llegó sin `PERPLEXITY_API_KEY` tras una migración de máquina y nunca se repuso). Se documenta porque el `.env.example` todavía la nombra: si no la usas, no la des de alta.
- **linkedin**: mensajería. Retirado del ámbito global el 2026-08-25 por coste de arranque (`uvx …@latest` consulta PyPI en **cada** lanzamiento: 1,43 s medidos, más que Serena y Headroom juntos). Si lo repones, píneale la versión y **no toques** las dos denegaciones que `settings.json` mantiene en `permissions.deny` — `mcp__linkedin__send_message` y `mcp__linkedin__connect_with_person` —: siguen ahí a propósito, para que reinstalarlo no reabra en silencio la puerta a escribir a terceros.
- **serena**: navegación por símbolos vía LSP. **Por proyecto, nunca en global** (ver abajo).

### Un MCP en ámbito global es un impuesto fijo, y casi nunca se mide

Registrar un servidor con `--scope user` lo arranca en **todas** las sesiones: en repos ajenos, en `/tmp`, en `$HOME`. Pagas su arranque, su RAM y sus nombres de herramienta en el contexto, uses o no uses el servidor.

Serena es el caso de estudio de este setup. Se registró en global durante semanas. La auditoría del 2026-08-25 recorrió las 55 transcripciones que existían ese día y dio: **1 sesión con llamadas efectivas y 4 llamadas en total**, y los **12 últimos arranques** registrando `No project root found` en su propio log — arrancaba sin proyecto activo, publicando 24 herramientas inertes. No es que Serena sea mala: es que estaba enrutada a donde no había código.

Antes de dejar un MCP en global, mide su uso real en tus propias transcripciones (cuenta bloques `tool_use`, no menciones — el nombre del servidor aparece en el prompt de cada sesión y eso infla cualquier `grep` ingenuo):

```bash
python3 - <<'EOF'
import json, glob, collections, os
calls = collections.Counter(); sesiones = 0; con_uso = set()
for f in glob.glob(os.path.expanduser('~/.claude/projects/*/*.jsonl')):
    sesiones += 1
    for linea in open(f, errors='ignore'):
        if 'mcp__' not in linea: continue
        try: d = json.loads(linea)
        except ValueError: continue
        for b in (d.get('message') or {}).get('content') or []:
            if isinstance(b, dict) and b.get('type') == 'tool_use' and str(b.get('name','')).startswith('mcp__'):
                calls[b['name'].split('__')[1]] += 1; con_uso.add(f)
print(f'{sesiones} sesiones, {len(con_uso)} con llamadas MCP reales')
for k, v in calls.most_common(): print(f'  {v:5d}  {k}')
EOF
```

**Poco uso no basta para retirar nada: lo que decide es coste de arranque x ubicuidad.** En la
misma auditoría, `firecrawl` salió con exactamente el mismo uso que Serena — 4 llamadas en 1 de
esas 55 sesiones — y **se queda**. Es un MCP `type: http` contra un endpoint remoto: no levanta
proceso local, no compila nada, no toca la red en el arranque, y además está registrado en
ámbito de **proyecto**, no global. Su coste real es un puñado de nombres de herramienta
diferidos. Serena costaba un proceso Python más un servidor de lenguaje en cada sesión;
`linkedin` costaba una consulta a PyPI en cada lanzamiento. Mide el uso, sí, pero **retira por
el coste**, no por el recuento.

La regla que sale de ahí: **global solo para lo que usas en cada sesión** (aquí: `headroom`). Todo lo demás, `claude mcp add --scope project` en el repo donde compensa, o un alias dedicado.

Ojo con los wrappers: `headroom wrap claude` registra Serena **por defecto** y vuelve a escribirla en `~/.claude.json` en cada lanzamiento, así que borrarla con `claude mcp remove` no basta — hay que lanzarlo con `--code-memory none`. Y su `--serena-instructions` reescribe tu `CLAUDE.md` en cada arranque con un prompt que ordena cargar las 24 herramientas de golpe, justo lo contrario de lo que consigue `--1m`. Quitar un MCP del arranque es tres sitios, no uno: el registro, el flag del wrapper y el fichero de instrucciones que dejó atrás.

Cómo se añaden: `claude mcp add ...`. La sintaxis exacta (transporte, comando o URL, variables de entorno que necesite) depende de cada servidor; consulta su propio repositorio antes de darlo de alta. El kit no incluye claves ni configuraciones MCP con secretos: cualquier credencial vive solo en tu `.env` local, nunca en este repo.

**Marketplaces privados (GitLab autoalojado, VPN).** Un marketplace de plugins de tu organización se da de alta con su URL SSH — `claude plugin marketplace add git@tu-gitlab:grupo/marketplace.git` — así que necesita una clave SSH dada de alta y la VPN levantada. El proceso completo, con los comandos y el diagnóstico de los fallos que dan todos el mismo mensaje, está en [`09-ssh-y-gitlab-privado.md`](09-ssh-y-gitlab-privado.md). Si la VPN está caída, ese marketplace falla al refrescarse y el resto de Claude Code sigue funcionando igual.

**Headroom son dos piezas, y solo una es un MCP.** El **proxy** de contexto (ver `03-headroom.md`) no se añade con `claude mcp add`: se cablea vía `ANTHROPIC_BASE_URL` y actúa sobre las peticiones a la API, por debajo del protocolo MCP. Aparte de eso, Headroom trae **también** un servidor MCP (`headroom mcp serve`) que sí se registra como cualquier otro y da acceso a sus estadísticas y a recuperar contenido que el proxy comprimió. Puedes usar el proxy sin registrar ese MCP; lo que no tiene sentido es lo contrario.

Y ojo con una confusión que este documento arrastraba: el hook `rtk hook claude` del `settings.json` **no es de Headroom**, es de [`rtk`](https://github.com/rtk-ai/rtk), otro proyecto que filtra la salida de los comandos de shell. Puedes tener uno sin el otro. Ver la tabla comparativa al principio de `03-headroom.md`.

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
| `headroom` | el proxy de contexto en `127.0.0.1:8787`, y el servidor MCP `headroom mcp serve` (ver `03-headroom.md`) | `headroom --version` · `headroom doctor` |
| `rtk` | filtra la salida de los comandos de shell antes de que entre en contexto; es lo que ejecuta el hook `rtk hook claude`. **Proyecto distinto de Headroom** | `rtk --version` |
| `pnpm` | instala `agent-browser` y otros paquetes globales de Node | `pnpm --version` |

## Verificación rápida

```bash
/plugin                  # plugins: activados y disponibles
claude mcp list           # servidores MCP dados de alta
ls $HOME/.claude/skills/   # skills instaladas
```
