<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=12,20,24&height=200&section=header&text=setup-claude-code&fontSize=48&fontColor=ffffff&animation=fadeIn&desc=El%20m%C3%A9todo%20detr%C3%A1s%20de%20mi%20trabajo%20con%20Claude%20Code&descAlignY=62&descSize=18" alt="setup-claude-code" />

[![CI](https://github.com/manuelcozar55/setup-claude-code/actions/workflows/ci.yml/badge.svg)](https://github.com/manuelcozar55/setup-claude-code/actions/workflows/ci.yml)

</div>

---

> ### ⚠️ Esto se usa desde WSL2 (o Linux). No desde Windows.
>
> Si estás en Windows, **abre primero tu distribución de WSL2** y trabaja dentro de ella: clona el repo en el sistema de ficheros de Linux (`~/`, no `/mnt/c/`) y ejecuta todo desde ahí. `install.sh`, `doctor.sh`, los guards y la suite de test son bash y asumen rutas POSIX; desde PowerShell o `cmd` no funcionan.
>
> ```powershell
> wsl                     # entra en tu distro por defecto
> ```
>
> **Por qué es un requisito y no una recomendación:** Linux y WSL2 son lo único que prueba la CI de este repo, así que es el único soporte que se puede demostrar con un pipeline real. macOS y Windows nativo no están soportados todavía, precisamente por eso. Dos avisos concretos si vienes de Windows: clona **dentro** de WSL y no en `/mnt/c/` (el sistema de ficheros `9p` sobre el disco de Windows es mucho más lento y complica los permisos de ejecución), y el `.gitattributes` de este repo ya fuerza `eol=lf` para que un clon con `core.autocrlf=true` no te convierta los scripts a CRLF y te los rompa con `bad interpreter: /bin/bash^M`.

## Qué hace esto

Instala en tu `~/.claude` una config de Claude Code endurecida: guards deterministas que bloquean comandos destructivos y fugas de secretos, 8 agentes con tiering de modelo, y una capa de contenido (`gitleaks`) sobre cada commit. Y es el único kit de este tipo que **demuestra** que sus guards funcionan con una suite de test falsable, no solo lo afirma: `test_guards_falsifiability.sh` neutraliza un guard real y comprueba que eso rompe **10 casos `BLOCK` conocidos**. Si neutralizarlo no rompiera nada, la suite no estaría midiendo nada — puedes reproducir esa caída tú mismo, ver el paso 5 más abajo.

No son garantías absolutas: son defensa en profundidad, con sus límites documentados en [`SECURITY.md`](SECURITY.md), no escondidos.

## Quick start

**Prerrequisitos** — el kit solo soporta **Linux o WSL2** (ver el aviso de arriba: en Windows, entra en WSL antes de nada y clona dentro de `~`, no en `/mnt/c/`).

Además necesitas: `bash`, `git`, `python3` ≥ 3.10, `jq`. `gitleaks` (para la Capa 2 de secretos) es opcional — si no lo tienes, `install.sh` te ofrece instalarlo solo (binario oficial, verificado contra un checksum SHA-256 fijado en este repo, no descargado de la red; sin `curl | bash`), o puedes seguir sin él: la Capa 1 funciona igual. Lista completa y cómo comprobar cada una en [`kit/docs/02-install.md`](kit/docs/02-install.md).

```bash
git clone https://github.com/manuelcozar55/setup-claude-code.git
cd setup-claude-code/kit
bash install.sh                                        # instala en $CLAUDE_HOME (default $HOME/.claude), con backup
cp .env.example "${CLAUDE_HOME:-$HOME/.claude}"/.env    # rellena tus claves
bash doctor.sh                                          # autodiagnóstico con evidencia (PASS/WARN/FAIL)
```

`doctor.sh` sale con código 0 solo si no hay ningún `FAIL`. Un `WARN` es aceptable en un componente opcional que aún no instalaste (Headroom, el venv de tools, `gitleaks`): el setup base funciona sin ellos. Guía completa en [`kit/README.md`](kit/README.md).

## Qué incluye

| Pieza | Qué es | Dónde |
|---|---|---|
| Guards de Bash/git | bloquean en duro `rm -rf`, `git push --force` a ramas protegidas, fugas de `.env`/claves por nombre de fichero, exfiltración por red, y más | [`kit/claude/hooks/`](kit/claude/hooks/) |
| Sentinel | motor de políticas `PreToolUse` (IOCs), opcional, capa adicional sobre cualquier tool | [`kit/sentinel/`](kit/sentinel/) |
| 8 agentes con tiering | `orchestrator`, `strategist`, `planner`, `deep-worker`, `code-reviewer`, `security-reviewer`, `code-explorer`, `quick-checker` | [`kit/claude/agents/`](kit/claude/agents/) |
| Dos capas de secretos | Capa 1 (`secret-guard.sh`, por nombre de fichero, activa desde el primer `install.sh`) + Capa 2 (`gitleaks` en `pre-commit`, por contenido real, opt-in por repo) | [`kit/docs/05-security.md`](kit/docs/05-security.md) |
| Eval set | 6 tareas reales + harness de grading; opt-in, cuesta llamadas reales a `claude -p`, nunca corre en CI | [`kit/evals/`](kit/evals/) |
| Suite de test falsable | `test_guards_falsifiability.sh`: neutraliza un guard real y comprueba que caen casos `BLOCK` conocidos | [`kit/test/`](kit/test/) |

## Por qué existe

No es una config que se copia y ya: es un bucle que se instala, se diagnostica y se corrige a sí mismo (`install.sh` → `doctor.sh` → editar/reinstalar), con TDD detrás de cada pieza en vez de "funciona en mi máquina". El porqué completo, con el modelo mental y los diez pilares de ingeniería detrás, está en las dos charlas de este repo (ver más abajo) y en [`kit/docs/01-overview.md`](kit/docs/01-overview.md).

## Configuración

Tras `install.sh`, personaliza en `$CLAUDE_HOME` (`$HOME/.claude` por defecto):

- **`.env`** — tus claves reales (`ANTHROPIC_API_KEY` y, si las usas, `PERPLEXITY_API_KEY`/`LANGSMITH_API_KEY`). Nunca se sube al repo.
- **Capa 2 de secretos** (opt-in, por repositorio de trabajo — `install.sh` nunca la activa por su cuenta en un repo que no hayas nombrado):
  ```bash
  cd tu-repo && bash /ruta/al/kit/install.sh --enable-secrets-layer2
  ```
- **`sentinel-allowlist.json`** — para falsos positivos de los guards, en vez de desactivarlos.

Detalle de cada opción en [`kit/docs/02-install.md`](kit/docs/02-install.md) y [`kit/docs/05-security.md`](kit/docs/05-security.md).

## Las dos charlas

Además del kit, este repo trae dos charlas autocontenidas (HTML + guion, sin instalar nada) que explican el método detrás: **el mapa** (modelo mental de Karpathy y los diez pilares de ingeniería de agentes) y **el territorio** (esta misma máquina, con cifras reales).

| Charla | Fichero | Guion | Para quién |
|--------|---------|-------|------------|
| **Fundamentos** · el mapa | [`agentes-fundamentos.html`](charlas/agentes-fundamentos.html) | [`agentes-fundamentos-guion.md`](charlas/agentes-fundamentos-guion.md) | Manager técnico |
| **Setup** · el territorio | [`setup-claude-code-definitiva.html`](charlas/setup-claude-code-definitiva.html) | [`setup-claude-code-definitiva-guion.md`](charlas/setup-claude-code-definitiva-guion.md) | Desarrolladores |

Ábrelas directamente en el navegador (doble clic, o `xdg-open`/`open`/`start`), no hace falta servidor.

## Más allá del quick start

- [`kit/README.md`](kit/README.md) — guía completa del kit.
- [`kit/docs/`](kit/docs/) — overview, install, Headroom, superpowers, seguridad, rutina, verificación, plugins/MCP/skills.
- [`SECURITY.md`](SECURITY.md) — qué protegen los guards y qué no (defensa en profundidad, no un límite duro), y cómo reportar una vulnerabilidad.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — cómo correr los tests y qué se espera de un PR.

## Formación recomendada (gratis, corta, verificada)

Para entender la IA y, sobre todo, Claude Code. Todos gratis y de una a dos horas; contenidos y duración verificados a fecha de este repo (las plataformas pueden cambiar, confírmalo al inscribirte).

| Curso | Plataforma | Duración | Coste | De qué va |
|-------|------------|----------|-------|-----------|
| [Claude Code 101](https://www.anthropic.com/learn) | Anthropic Academy | ~1 h | Gratis | Intro oficial: instalación, flujo Explore-Plan-Code-Commit, `CLAUDE.md`, MCP. |
| [Claude Code in Action](https://anthropic.skilljar.com/claude-code-in-action) | Anthropic Academy | ~1 h · 15 clases | Gratis | Profundiza: operaciones de fichero, contexto, GitHub, hooks, SDK. Certificado. |
| [Claude Code: A Highly Agentic Coding Assistant](https://www.deeplearning.ai/courses/claude-code-a-highly-agentic-coding-assistant/) | DeepLearning.AI (con Anthropic) | ~2 h · 10 lecciones | Gratis (audit) | Práctica real: RAG chatbot, refactor, Figma a web app, subagentes, git worktrees, hooks, MCP. |
| [MCP: Build Rich-Context AI Apps with Anthropic](https://www.deeplearning.ai/courses/mcp-build-rich-context-ai-apps-with-anthropic/) | DeepLearning.AI (con Anthropic) | 1 h 58 min | Gratis (audit) | MCP a fondo: FastMCP, Inspector, cliente/servidor, despliegue. |

**Ruta sugerida:** empieza por *Claude Code 101* para el flujo básico, salta a *Claude Code in Action* para el día a día, y haz el curso de DeepLearning.AI cuando quieras práctica guiada sobre proyectos reales. El catálogo completo y gratuito de Anthropic (prompt engineering, AI Fluency, MCP) está en [anthropic.com/learn](https://www.anthropic.com/learn).

### Vídeos

Vídeos gratuitos (YouTube), elegidos por contenido, no por duración.

- **[The prompting playbook](https://youtu.be/G2B0YWuJUgI)** - guía de prompting; cómo escribir mejores instrucciones para modelos. (Extra recomendado.)
- **[Claude Code best practices (Code w/ Claude)](https://youtu.be/gv0WHhKelSE)** - charla oficial de Anthropic sobre buenas prácticas de Claude Code; refuerza el "territorio" de este repo.
- **[Context Engineering Our Way to Long-Horizon Agents - Harrison Chase (LangChain)](https://youtu.be/vtugjs2chdA)** - el cofundador de LangChain sobre ingeniería de contexto, harnesses y agentes de largo horizonte; refuerza directamente el "mapa" (loop/context engineering).

## Fuentes

Nada del mapa es opinión. Combina un modelo mental y un cuerpo de ingeniería que puedes leer en la fuente:

| Fuente | Aporta |
|--------|--------|
| **Andrej Karpathy** | El modelo mental: el LLM es la CPU, el contexto es la RAM. |
| **LangChain** · [The Art of Loop Engineering](https://www.langchain.com/blog/the-art-of-loop-engineering) | Los cuatro bucles apilados; "el potencial está en los bucles que construyes alrededor". |
| **LangChain** · [Context Engineering](https://www.langchain.com/blog/context-engineering-for-agents) | Llenar la ventana con la información justa: escribir, seleccionar, comprimir, aislar. |
| **LangChain** · [Multi-agent systems](https://www.langchain.com/blog/how-and-when-to-build-multi-agent-systems) | Herramientas y orquestación: pocas y buenas, y multi-agente solo cuando compensa. |
| **LangChain** · [Runtime / Deep Agents](https://www.langchain.com/blog/runtime-behind-production-deep-agents) | Harness frente a runtime, ejecución durable y el humano en el bucle. |
| **LangChain** · [Agent Observability & Evals](https://www.langchain.com/resources/agent-observability) | "La lógica de tu app está en las trazas, no en el código"; el eval como bucle. |
| **SwirlAI** | La estructura de los diez pilares aquí adaptada. |

## Notas de experto

- **Honestidad de fuentes.** Cada afirmación de las charlas y del kit está citada y verificada; lo que no se pudo verificar, se cortó. Cero cifras infladas.
- **Cifras del deck de setup.** Son una foto ilustrativa de mi máquina en un momento dado, no una garantía ni un dato tuyo: reprodúcelas con tus propios logs (el deck trae la tabla "cifra a fuente a comando"). `~/.ssh`, `id_rsa` o `ANTHROPIC_API_KEY` aparecen solo como objetivos de demostración de la puerta de seguridad; el repo no contiene ninguna clave real.
- **El kit se verifica a sí mismo.** Instalar, diagnosticar, corregir: un bucle, no un volcado. `doctor.sh` da evidencia por componente y `scan-secrets.sh` bloquea cualquier fuga.
- **Autocontenido y accesible.** Las charlas llevan CSS/JS inline, contraste AA en claro y oscuro, `prefers-reduced-motion`, print y JS-off muestran todo.

## Autor

**Manuel Cózar** · AI Engineer · Innovation Researcher @ Fundación CIRCE

[![GitHub](https://img.shields.io/badge/GitHub-manuelcozar55-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/manuelcozar55)
[![Email](https://img.shields.io/badge/Email-manuelcozar55@gmail.com-D14836?style=flat-square&logo=gmail&logoColor=white)](mailto:manuelcozar55@gmail.com)

## Licencia

[CC BY 4.0](LICENSE). Comparte y adapta con atribución.

<div align="center">

*El mapa antes del territorio. Y cada número, reproducible con un comando.*

<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=12,20,24&height=120&section=footer" alt="" />

</div>
