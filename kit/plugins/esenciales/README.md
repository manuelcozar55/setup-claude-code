# esenciales

Plugin del kit con las seis skills de método que de verdad se usan, derivadas de
[superpowers](https://github.com/obra/superpowers) 6.4.1 (MIT, © 2025 Jesse Vincent;
licencia íntegra en `LICENSE` y atribución en `THIRD-PARTY.md` de la raíz).

| Skill | Para qué |
|---|---|
| `brainstorming` | aclarar el encargo y acordar el diseño antes de tocar código |
| `writing-plans` | partir el diseño en tareas pequeñas y verificables |
| `subagent-driven-development` | ejecutar el plan con un subagente por tarea y revisión |
| `systematic-debugging` | causa raíz antes que parche |
| `finishing-a-development-branch` | cerrar la rama: verificar, fusionar o abrir PR, limpiar |
| `dispatching-parallel-agents` | repartir trabajo independiente entre agentes en paralelo |

Se invocan como `esenciales:<skill>`.

## Por qué 6 y no 15

superpowers trae 15 skills. En 60 días de uso real solo 6 se invocaron alguna vez; son
estas. Las otras nueve ocupaban sitio en el listado de skills de cada sesión sin aportar.

Lo que más pesaba no era una skill, sino su hook `SessionStart`: inyectaba
`using-superpowers` en cada arranque, `/clear` y compactación (~1,9k tokens cada vez), y esa
skill manda invocar otra «si hay aunque sea un 1 % de probabilidad» de que aplique. Eso
choca con la regla de la casa de ajustar la ceremonia al riesgo: una edición trivial no
necesita diseño ni plan. Este plugin **no tiene directorio `hooks/`**: las skills se cargan
solo cuando su descripción encaja con la tarea.

## Qué se adaptó

Cada `SKILL.md` termina con una línea «Adaptado de superpowers 6.4.1 (MIT): …» que dice qué
cambió. En resumen:

- Todas: el namespace pasa a `esenciales:`, y las referencias a skills no incluidas se
  sustituyen por el paso equivalente en una línea (verificar con el oráculo real, revisar
  con el agente `code-reviewer`, `git worktree add`…).
- `brainstorming`: una sola ronda de aclaración y el diseño completo antes del OK, en vez
  de una pregunta por mensaje; el diseño aprobado va a `.claude/estado/nucleo.md`
  («Encargo original» e «Invariantes»). Sin el companion visual del original: su servidor
  local cargaba un logo de un dominio de terceros y reportaba la versión, y aquí nada sale
  a terceros sin pedirlo. La skill funciona igual sin él.
- `writing-plans`: el plan va a la sección `## Plan` de `.claude/estado/nucleo.md`.
- `subagent-driven-development`: cada tarea se cierra con `[x]` en `nucleo.md` y el comando
  que la verificó; revisión con `code-reviewer`; commits con el porqué.
- `systematic-debugging`, `finishing-a-development-branch`, `dispatching-parallel-agents`:
  solo las sustituciones anteriores.

Los ficheros de apoyo (prompts, scripts) se copian sin cambios salvo dos líneas: la ruta de la spec en
`brainstorming/spec-document-reviewer-prompt.md` y una referencia a TDD en
`systematic-debugging/CREATION-LOG.md`.

## Instalar y volver a superpowers

```bash
claude plugin marketplace add manuelcozar55/setup-claude-code --scope user
claude plugin install esenciales@setup-claude-code --scope user
```

`kit/install-plugins.sh --apply` hace lo mismo. Para volver al original, en scope user:

```bash
claude plugin uninstall esenciales@setup-claude-code --scope user
claude plugin install superpowers@claude-plugins-official --scope user
```

y cambia la entrada correspondiente de `enabledPlugins` en tu `settings.json`. No tengas
los dos activos a la vez: las skills se llaman igual y competirían por el mismo disparador.
