# 04 · superpowers, agentes y agent-browser

Este documento cubre el método (el plugin superpowers y sus skills), quién lo ejecuta (los 8 agentes con tiering) y una herramienta que se apoya en ese método (agent-browser). Los tres son de terceros o se instalan por separado: el kit los documenta, no los redistribuye.

## El plugin superpowers

superpowers se activa como plugin de Claude Code desde un marketplace. En la config que instala este kit (`claude/settings.json`), la activación queda declarada así:

```json
"enabledPlugins": {
  "superpowers@claude-plugins-official": true
}
```

`claude-plugins-official` es un marketplace ya conocido por Claude Code (no hace falta registrarlo en `extraKnownMarketplaces`; eso solo es necesario para marketplaces de terceros que no vienen dados de alta, como los que ves en el propio `settings.json` para otros plugins). Para activarlo tú mismo:

- **Desde dentro de Claude Code**: usa el comando interactivo `/plugin` para listar marketplaces e instalar `superpowers` (la sintaxis exacta puede variar entre versiones de Claude Code; si tienes dudas, `/plugin` sin argumentos te muestra las opciones disponibles en tu versión).
- **Editando `settings.json` directamente**: añade la clave `"superpowers@claude-plugins-official": true` bajo `enabledPlugins` (tal y como ya viene en el `settings.json` de este kit) y reinicia la sesión de Claude Code para que recoja el plugin.

## Las skills y las 4 leyes de hierro

superpowers agrupa alrededor de 14 skills. El número exacto y sus nombres concretos pueden variar entre versiones del plugin; la forma de comprobarlo en tu propia máquina, una vez instalado, es:

```bash
ls $HOME/.claude/skills/
```

De esas skills, cuatro son leyes de hierro: invariantes que el bucle operativo nunca se salta, con independencia de la tarea.

1. **Skills-first**: antes de improvisar un procedimiento, comprueba si ya existe una skill que lo cubra.
2. **El gate de brainstorming**: no se escribe una línea de código hasta acordar el diseño. Ambigüedad se resuelve antes de ejecutar, no a mitad de tarea.
3. **TDD**: el test va antes que la implementación.
4. **Verificar antes de completar**: nada se da por "hecho" sin enseñar el comando y su salida. Evidencia, no afirmaciones.

Las otras skills son herramientas que se invocan cuando la tarea las pide, no invariantes universales: cosas como orquestar sub-agentes en paralelo (`superpowers:dispatching-parallel-agents`), ejecutar un plan tarea por tarea (`superpowers:executing-plans`), o repartir un plan entre agentes que reportan de vuelta (`superpowers:subagent-driven-development`).

## Los 8 agentes, con tiering

Cuando el método delega, delega con tiering de coste: el modelo más caro para pensar, uno intermedio para ejecutar y revisar, y el más barato para verificar. No tiene sentido pagar un modelo de razonamiento caro para correr un linter.

| Tier | Modelo | Agentes | Para qué |
|---|---|---|---|
| Pensar | `opus` | `orchestrator`, `strategist`, `planner` | descomponer tareas complejas en frentes paralelos, IntentGate antes de ejecutar, planes verificables |
| Ejecutar y revisar | `sonnet` | `deep-worker`, `code-reviewer`, `security-reviewer`, `code-explorer` | implementación autónoma end-to-end, revisión de código pre-PR, auditoría de seguridad, exploración de codebase |
| Verificar | `haiku` | `quick-checker` | PASS/FAIL rápido: tipos, lint, tests, sin análisis ni sugerencias |

Estos 8 agentes están definidos en `claude/agents/*.md` (front-matter con `name`, `description`, `model`, `tools`) y `install.sh` los coloca en `$CLAUDE_HOME/agents/`.

## agent-browser

Para automatización de navegador, este setup usa `agent-browser` en vez de Playwright MCP, `browser-use` o JS ad-hoc.

Instalación global:

```bash
pnpm add -g agent-browser
```

Chrome queda bajo `$HOME/.agent-browser/browsers/` tras la primera ejecución.

Política de uso (la que aplica el `CLAUDE.md` de este kit):

- Úsalo como estándar único para tareas de navegador salvo que se pida explícitamente otra cosa.
- Flujo por defecto: `open` → `snapshot -i -c` → actuar sobre las referencias `@eN` de la snapshot → esperar la URL/texto/carga esperada → volver a hacer snapshot tras cada cambio de página.
- Prefiere las snapshots de accesibilidad compactas y sus referencias frente a capturas de pantalla, DOM crudo o JS ad-hoc; las capturas quedan solo para verificación visual.
- Seguridad: nunca expongas secretos o cookies en la salida; usa vault de credenciales o ficheros de estado de sesión; restringe la navegación a los dominios que pida el usuario.
