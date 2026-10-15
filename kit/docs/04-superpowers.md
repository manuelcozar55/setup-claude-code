# 04 · El método (plugin esenciales), agentes y agent-browser

Este documento cubre el método (el plugin `esenciales` y sus seis skills), quién lo ejecuta (los 8 agentes con tiering) y una herramienta que se apoya en ese método (agent-browser). `esenciales` y los agentes los reparte el kit; agent-browser es de terceros y se instala por separado. El nombre del fichero se conserva por los enlaces que lo citan: el kit usó superpowers hasta la 1.2.0.

## El plugin esenciales

`esenciales` vive en `kit/plugins/esenciales/` y se publica en el marketplace de este repo (`.claude-plugin/marketplace.json`, el mismo que `cockpit`). Deriva de [superpowers](https://github.com/obra/superpowers) 6.4.1 (MIT; atribución en `THIRD-PARTY.md`). Se instala con el resto de plugins recomendados:

```bash
bash kit/install-plugins.sh            # ver los comandos
bash kit/install-plugins.sh --apply    # instalarlos en scope user
```

o, desde dentro de Claude Code, con `/plugin` tras registrar el marketplace `setup-claude-code`.

Por qué un plugin propio y no superpowers entero: de sus 15 skills solo 6 tuvieron uso en 60 días, y su hook `SessionStart` inyectaba una skill de arranque (~1,9k tokens) en cada inicio, `/clear` y compactación, con la consigna de invocar una skill si había «un 1 %» de probabilidad de que aplicara. Eso choca con ajustar la ceremonia al riesgo. `esenciales` no tiene hooks: cada skill se carga solo cuando su descripción encaja con la tarea. El detalle de qué se adaptó está en `kit/plugins/esenciales/README.md`, junto con cómo volver al original.

## Las seis skills

| Skill | Cuándo entra | Qué deja |
|---|---|---|
| `esenciales:brainstorming` | antes de construir o cambiar comportamiento | diseño aprobado en `.claude/estado/nucleo.md` («Encargo original», «Invariantes»), tras **una** ronda de aclaración como mucho |
| `esenciales:writing-plans` | con el diseño aprobado y varias tareas por delante | la sección `## Plan` de `nucleo.md`: tareas pequeñas con ficheros, cambio y comando de verificación |
| `esenciales:subagent-driven-development` | para ejecutar ese plan | un subagente por tarea, revisión con `code-reviewer`, `[x]` con el comando que la verificó, commit con el porqué |
| `esenciales:systematic-debugging` | ante un fallo o un test rojo | causa raíz antes que parche |
| `esenciales:finishing-a-development-branch` | con la implementación terminada y verde | fusionar, abrir PR o descartar, y limpiar el worktree |
| `esenciales:dispatching-parallel-agents` | con dos o más frentes independientes | un agente por frente, en paralelo |

## Las tres leyes de hierro

Invariantes que el bucle operativo nunca se salta, con independencia de la tarea. Las aplican el `CLAUDE.md` del kit y la skill `deep-change`; las skills de arriba son su herramienta, no su condición:

1. **El gate de diseño**: no se escribe una línea de código hasta acordar el diseño. La ambigüedad se resuelve antes de ejecutar, no a mitad de tarea.
2. **Test antes que implementación**: un fix lleva un test que falla antes del cambio y pasa después.
3. **Verificar antes de completar**: nada se da por "hecho" sin enseñar el comando y su salida. Evidencia, no afirmaciones.

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

Chrome queda bajo `$HOME/.agent-browser/browsers/` tras la primera ejecución. Si tras instalar `agent-browser --version` no se encuentra, revisa el aviso sobre el directorio de binarios globales de pnpm en `02-install.md`.

Política de uso (la que aplica el `CLAUDE.md` de este kit):

- Úsalo como estándar único para tareas de navegador salvo que se pida explícitamente otra cosa.
- Flujo por defecto: `open` → `snapshot -i -c` → actuar sobre las referencias `@eN` de la snapshot → esperar la URL/texto/carga esperada → volver a hacer snapshot tras cada cambio de página.
- Prefiere las snapshots de accesibilidad compactas y sus referencias frente a capturas de pantalla, DOM crudo o JS ad-hoc; las capturas quedan solo para verificación visual.
- Seguridad: nunca expongas secretos o cookies en la salida; usa vault de credenciales o ficheros de estado de sesión; restringe la navegación a los dominios que pida el usuario.
