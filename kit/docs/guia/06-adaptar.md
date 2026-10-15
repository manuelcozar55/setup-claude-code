# Guía · Adaptar la plantilla: qué borrar según tu caso

La plantilla del kit ([`settings.json`](../../claude/settings.json) y [`CLAUDE.md`](../../claude/CLAUDE.md)) es la de un setup concreto. Todo lo que cargas y no usas lo pagas en cada turno ([`01-por-que-contexto.md`](01-por-que-contexto.md#1--pagas-45k-tokens-antes-de-escribir-nada)), así que adaptarla es sobre todo **quitar**. Regla para todo lo que sigue: mide con `/context` antes y después, en una sesión nueva.

Lo que **no** se quita en ningún caso: los guards de `PreToolUse` sobre `Bash`, el bloque `permissions.deny` que protege la propia configuración (`Edit(/hooks/**)`, `Edit(/settings.json)`…) y el hook de arranque que entrega `nucleo.md`. Son las barreras y el estado; lo demás es preferencia.

## Para todos: lo que es del autor, no tuyo

| Qué | Dónde | Quítalo si… |
|---|---|---|
| `WebFetch(domain:…)` en `permissions.allow` | `settings.json` | no consultas esas fuentes (son de un uso concreto: bibliografía y boletines oficiales) |
| `Bash(uv tool list)`, `Bash(rtk gain)`, `Bash(graphify query *)`, `Bash(graphify path *)`, `Bash(graphify explain *)` | `settings.json` → `allow` | no usas esas herramientas; un `allow` que no usas es superficie sin beneficio. Son subcomandos sueltos y no comodines porque `rtk *` ejecutaba cualquier comando vía `err`/`test`/`summary`/`proxy`, y `graphify install\|hook\|clone\|add` tocan la config de los agentes, los hooks de git o la red |
| `understand-anything` y su marketplace | `enabledPlugins`, `extraKnownMarketplaces` | no lo has usado en un mes |
| `"model": "opus[1m]"` | `settings.json` | tu trabajo cabe en una ventana normal ([`06-routine.md`](../06-routine.md#opus1m-solo-cuando-no-cabe)); y si fijas el modelo por `env.ANTHROPIC_MODEL`, quita esta clave: una sola fuente ([antipatrón 7](03-antipatrones.md#7--model-que-no-se-queda)) |
| El bloque de agent-browser | `CLAUDE.md` | no automatizas navegador |
| El párrafo de Headroom | `CLAUDE.md` | no usas el proxy (medido: 0,2-0,6 % de ahorro) |

## Sin Codex (solo Claude Code)

- Quita `codex@openai-codex` de `enabledPlugins` y `openai-codex` de `extraKnownMarketplaces`.
- Si tu plantilla parte las instrucciones en un `AGENTS.md` común y una capa propia de Claude (para que Codex u otros agentes lean las mismas reglas), con un solo agente basta **un** `CLAUDE.md`: junta las dos partes y borra la importación. Un fichero menos que mantener en sincronía.
- Lo que pierdes: la segunda opinión de otra familia de modelos. Si alguna vez la echas de menos, vuelve a activarlo; no hay nada más que deshacer.

## Sin MCP

- El hook `narthex-post-mcp.py` (`PostToolUse` con matcher `mcp__.*`) escanea las respuestas de servidores MCP en busca de inyección. Sin servidores MCP no se dispara nunca: puedes dejarlo (no cuesta nada) o quitarlo para que la configuración diga la verdad.
- Las reglas `deny` con forma `mcp__<servidor>__<método>` (en la plantilla, dos métodos de un servidor de LinkedIn que escriben a terceros) sobran si no tienes ese servidor. Si algún día lo añades, vuelven: un MCP que escribe a terceros sin barrera es el peor caso.
- Si **sí** usas MCP: cada servidor carga sus esquemas y a veces instrucciones en cada turno. Mira en `/context` cuánto pesa cada uno y desconecta el que no uses esa semana.

## Sin equipo (trabajas solo)

- `branch-guard.sh` bloquea `git push` a `main`, `master` y `production`. Si en tus repos personales empujas a `main` a propósito, no lo borres: ajusta la lista con `CC_PROTECT_BRANCHES` (por ejemplo, solo `production`). Quitar el guard entero también quita la protección en los repos donde sí importa.
- El marketplace privado de plugins y el alta en un GitLab autoalojado ([`09-ssh-y-gitlab-privado.md`](../09-ssh-y-gitlab-privado.md)) no te hacen falta.
- La Capa 2 de secretos (`gitleaks` en `pre-commit`) se activa repo a repo: actívala en los que publiques, aunque trabajes solo. Un secreto en un repo público no distingue tamaños de equipo.
- `nucleo.md` sigue siendo útil sin equipo: tu «yo» de mañana, tras un `/clear`, es la otra persona.

## Al terminar

1. Edita tu `~/.claude/settings.json` y tu `~/.claude/CLAUDE.md` a mano (la plantilla prohíbe que Claude edite su propia configuración), o edita la plantilla en tu copia del kit y reinstala con `bash kit/install.sh`; si tu `~/.claude` es un repo git con remoto, el instalador solo enseña el diff y escribe con `--apply`.
2. `bash kit/doctor.sh`: un `FAIL` es un hallazgo; un `WARN` por algo que quitaste a propósito es lo esperado.
3. `/context` en una sesión nueva, y apunta la cifra en la ficha de [`04-mide-tu-setup.md`](04-mide-tu-setup.md).
