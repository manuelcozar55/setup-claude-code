# Auditoría de CLAUDE.md + RTK.md — 2026-08-21

Insumo para el ADR de presupuesto de contexto (FASE 3).
Criterio: *"right altitude"* (Anthropic, 29-sep-2025) y el test por línea de
Claude Code best-practices — *"Would removing this cause Claude to make mistakes?"*

Estado medido: **`~/.claude/CLAUDE.md` 136 líneas / ~1.978 tok · `RTK.md` 29 líneas / ~241 tok.**

Veredictos: **KEEP** (se queda) · **SKILL** (baja a carga bajo demanda) ·
**HOOK** (pasa a control determinista) · **CUT** (se elimina) · **CONFIG** (ya está en settings.json)

| Sección | ~tok | Propósito | Problema medido | Veredicto |
|---|---:|---|---|---|
| `# graphify` | 56 | Fuerza invocar la skill al teclear `/graphify` | **0 invocaciones** en 47 sesiones. La skill ya tiene `description` que la hace invocable; la regla duplica el mecanismo nativo | **CUT** |
| `# agent-browser` | 203 | Estándar de automatización de navegador | 3 invocaciones. Seis de las siete líneas repiten lo que el `SKILL.md` ya declara | **SKILL** (dejar 1 línea) |
| `# userEmail` | 14 | Identidad | Aparece **dos veces** en el contexto cargado (aquí y al final, ampliado) | **CUT** (duplicado) |
| `## Prompt Defense` | 39 | Ignorar instrucciones de contenido externo | Válido y no inferible. Refuerza §7 | **KEEP** |
| `## Security` | 86 | Nunca leer `~/.ssh`, `.env`; nunca pipe-to-shell; confirmar destructivos | **Ya es determinista**: `secret-guard`, `block-dangerous-commands`, `destructive-guard` y la `deny` de settings.json lo imponen. La regla advisoria es una segunda copia más débil | **HOOK** (ya existe; borrar el texto) |
| `## Package Manager` | 34 | Usar `pnpm`, no `npm` | **`pnpm` no está en PATH** (solo shim de corepack en el bindir de nvm). La regla es hoy incumplible tal cual | **KEEP, corregida** |
| `## Python CLI Tools` + `# Check first` | 142 | Venv persistente en `~/.venvs/tools` | Gotcha real, no inferible del código. Pero 12 líneas de receta bash caben mejor en una skill | **SKILL** (dejar la prohibición) |
| `## Code Standards` | 239 | Simplicidad, cambios quirúrgicos, orphan rule | Alto valor. Son los **"principios de la casa"** — ver nota de atribución abajo. Demasiado largos para contexto fijo | **SKILL** |
| `## Testing & Verification` | 56 | Correr tests; verificar comportamiento, no solo tipos | **Núcleo del harness.** Hoy advisorio y sin sensor detrás | **KEEP + HOOK** |
| `## Git Workflow` | 46 | Commits atómicos, nunca `--no-verify`, no enmendar publicados | Parcialmente cableado (`branch-guard.sh`, `git/pre-commit`) | **KEEP** (reducir) |
| `## Performance & Token Efficiency` | 65 | Preferir Grep a Read; usar `Explore`; auto-compact 75 % | Incumplida y redundante: Read 221 vs Bash 2.379; `Explore` **4 usos**; el 75 % **ya está** en `env.CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` | **CUT** + **CONFIG** |
| `## IntentGate` | 227 | 5 preguntas antes de tarea ambigua | **Plan mode: 2,1 % de sesiones.** La regla más larga del fichero es la más incumplida. Candidata #1 | **HOOK o CUT** |
| `## Never-Stop Principle` | 90 | No preguntar a mitad de tarea | **Tensión con IntentGate**: una manda parar y preguntar, la otra manda no parar. La frontera ("antes de empezar") es sutil y se pierde en el ruido | **KEEP** (fundir con la anterior) |
| `## Parallel-First Execution` | 51 | Lanzar agentes en paralelo por defecto | Apunta a `superpowers:dispatching-parallel-agents`: **0 invocaciones** | **CUT** |
| `## Agent Delegation` | 152 | Tabla de 8 agentes → cuándo usar cada uno | **La tabla no funciona: 70 % de las delegaciones van a `general-purpose` y 6 de los 8 agentes nunca se han usado.** Es guía pura sin sensor | **CUT y rediseñar** |
| `## Operating loop` | 263 | Bucle `deep-change` | 3 invocaciones. Es la sección **más cara** del fichero y describe un proceso que la propia skill ya contiene | **SKILL** |
| `## Stack local` | 215 | 4 gotchas de Headroom y del proxy :8787 | **El mejor contenido del fichero**: no inferible, específico, previene incidentes reproducidos | **KEEP** |
| `RTK.md` (importado) | 241 | Comandos meta de rtk + aviso de colisión de nombres | Referencia consultable, no regla de conducta. Y su premisa de reescritura "transparente" **está desmentida** por M-001 | **SKILL + MISTAKES** |

## Recuento

| | ~tok |
|---|---:|
| Estado actual (CLAUDE.md + RTK.md) | **2.219** |
| KEEP tal cual | 442 |
| KEEP reducido / corregido | ~180 |
| A SKILL (carga bajo demanda) | 848 |
| A HOOK (ya existe o por construir) | 313 |
| CUT (duplicado, incumplido o redundante) | ~436 |

Proyección: **~620 tok** de contexto fijo, un **72 % menos**, sin perder ninguna regla —
las que valen se mueven a donde se cumplen solas.

> **Aviso de coherencia (contrato §3).** Este recorte optimiza el **KPI 6**, que el propio
> encargo declara irrelevante (0,0001 % de la entrada medida). Se ejecuta porque
> best-practices avisa de que *"if your CLAUDE.md is too long, Claude ignores half of it"* —
> el beneficio esperado es **adherencia**, no ahorro. Si el retrabajo (KPI 1) no mejora
> tras el cambio, el recorte no sirvió y hay que decirlo en `MISTAKES.md`.

## Nota de atribución

`## Code Standards` reproduce cuatro principios (*think before coding · simplicity first ·
surgical changes · goal-driven execution*) atribuidos habitualmente a Andrej Karpathy.
**Verificado 2026-08-21: no hay fuente primaria.** Son una formulación de la comunidad
derivada de sus observaciones (`multica-ai/andrej-karpathy-skills`, literal: *"derived from
Andrej Karpathy's observations on LLM coding pitfalls"*). Se citan como **principios de la
casa**, nunca como cita de Karpathy.
