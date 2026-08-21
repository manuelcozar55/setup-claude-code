# SKILLS-REGISTRY

Origen, vetado y versión fijada de todo lo que se carga en el harness.

> **v0.1.0 adopta CERO skills externas.** Las skills son un vector de ataque real: se cargan
> en contexto y pueden traer scripts ejecutables. La matriz de decisión se produce ahora; la
> adopción, si la hay, es v0.2.0 y con vetado escrito.

---

## Criterio de vetado

Una skill externa entra solo si cumple **las cuatro**:

1. **Cubre una tarea frecuente y medida** — no una que uno se imagina haciendo.
2. **Pasa el vetado de seguridad** — revisado el `SKILL.md` **y todos sus scripts**, no solo
   la descripción. Sin red no declarada, sin exfiltración, sin escritura fuera de su ámbito.
3. **No solapa** con algo que ya está.
4. **Su coste de mantenimiento se justifica** por uso real, no por potencial.

**Ante la duda, no se instala.** Y se fija versión: una skill que se autoactualiza es una
puerta trasera con buena reputación.

---

## Skills propias de mcharness (4 de 6 del presupuesto)

| Skill | Origen | Qué aporta | Riesgo |
|---|---|---|---|
| `harness` | **Absorbida** de `~/.claude/skills/harness/`, sin cambios (checksums idénticos) | Cola de tareas con oráculo obligatorio e inmutable, reanudación, presupuesto de tiempo, máx 3 reparaciones | Ninguno: sin scripts, solo doctrina |
| `house-rules` | Propia. Extraída de `CLAUDE.md` | Los cuatro principios de la casa, con su nota de atribución | Ninguno |
| `coach` | Propia | Explicación pedagógica en 3 niveles + **criterio para detectar que es ruido** | Ninguno |
| `dev-env` | Propia. Extraída de `CLAUDE.md` + medición | Gotchas verificados del entorno: reescritura de comandos, venvs, `/mnt/c`, Headroom | Ninguno |

**Presupuesto restante: 2.** No se gasta por gastarlo.

**Descartada deliberadamente: `oracle-design`.** Su contenido ya existe completo en
`.claude/skills/harness/referencias/oraculos.md`. Crearla habría sido gastar presupuesto en
duplicar algo bien escrito. Sesgo del curador: **eliminar y redirigir, no añadir**.

---

## Inventario de lo instalado hoy en `~/.claude/skills/` (18) — decisión

Uso medido sobre 47 sesiones. **El peso en disco y el uso no se parecen en nada.**

| Skill | Tamaño | Usos | Decisión |
|---|---:|---:|---|
| `impeccable` | 3,26 MB | 2 | **Revisar.** El 62 % del disco por 2 usos. Su hook de `Stop` tiene `timeout: 30` (mide 108 ms, pero el techo es el riesgo) |
| `ui-ux-pro-max` | 1,62 MB | **0** | **Candidata a eliminar.** 31 % del disco, cero uso |
| `taste-skill` | 87 KB | **0** | **Candidata a eliminar** |
| `graphify` | 85 KB | **0** | **Candidata a eliminar.** Además `CLAUDE.md` tenía una regla dedicada a forzar su invocación, que tampoco funcionó |
| `ui-design-system` | 76 KB | **0** | Candidata a eliminar |
| `emil-design-eng` | 27 KB | **0** | Candidata a eliminar |
| `harness` | 21 KB | — | **Absorbida** en el repo |
| `review-animations` | 18 KB | **0** | **No carga en runtime.** Rota o mal declarada |
| `no-ai-slop` | 17 KB | 0 | Mantener: barata |
| `excalidraw` | 17 KB | 0 | **Revisar:** el `name` del frontmatter (`excalidraw-skill`) no coincide con el directorio |
| `continuous-learning-v2` | 14 KB | 0 | **Revisar:** solapa con `/retro` y con `knowledge/`. Un sistema que escribe reglas solo choca con el ADR 007 |
| `markitdown`, `codebase-onboarding`, `deep-change`, `deep-research`, `ultrawork`, `agent-browser`, `web-design-guidelines` | < 10 KB | 0-3 | Mantener: baratas y específicas |

**Total: 5,29 MB, del que `impeccable` + `ui-ux-pro-max` son el 92 %, con 2 usos entre las
dos.** El diagnóstico no es que falte capacidad: es que la capacidad está mal asignada.

---

## Agentes

| | Cantidad | Usos medidos |
|---|---:|---|
| Heredados en `kit/claude/agents/` | 8 | `deep-worker` 17 · `code-reviewer` 15 · **los otros 6, cero** |
| Nuevos de mcharness | **0** | — |

De 150 delegaciones, **105 (70 %) fueron a `general-purpose`**. Añadir un noveno agente
sería empeorar el diagnóstico. En su lugar, `/review` **nombra al especialista** en vez de
dejar la elección al azar. Ver ADR 005.

---

## MCP conectados

| Servidor | Usos | Decisión |
|---|---:|---|
| `serena` | 4 | **Cablear su uso.** `/implement` ya lo exige antes de tocar símbolos compartidos: `find_referencing_symbols` da análisis de impacto *antes* de romper algo, que es un sensor computacional de primer orden |
| `firecrawl` | 4 (+460 en subagentes) | Mantener: es el motor de la investigación |
| `headroom` | **0** | Revisar. Es infraestructura, no herramienta de sesión |
| `linkedin` | **0** | Revisar. Dos de sus tools ya están en la `deny` de settings |
| 9 conectores `claude.ai` | **0** | **Sin autenticar.** Autenticar los útiles o darlos de baja: un MCP registrado y roto es ruido en cada arranque |

*(El encargo mencionaba 11 conectores sin autenticar; el cache
`mcp-needs-auth-cache.json` lista **9**.)*
