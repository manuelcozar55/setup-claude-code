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
> **Por qué es un requisito y no una recomendación:** Linux y WSL2 son lo único que prueba la CI de este repo, así que no se promete un soporte que no se puede demostrar con un pipeline real. macOS y Windows nativo (PowerShell/cmd) **no están soportados todavía**, precisamente por eso: no hay una mac ni un pipeline de Windows nativo en CI para reproducir un fallo ahí. De hecho, `install.sh` aborta con exit 1 si detecta una plataforma que no sea Linux, en vez de dejarte una instalación a medias.
>
> Dos avisos concretos si vienes de Windows: clona **dentro** de WSL y no en `/mnt/c/` (el sistema de ficheros `9p` sobre el disco de Windows es mucho más lento y complica el bit de ejecución), y el `.gitattributes` de este repo ya fuerza `eol=lf` para que un clon con `core.autocrlf=true` no te convierta los scripts a CRLF y te los rompa con `bad interpreter: /bin/bash^M`.

## mcharness — guías y sensores

Este repo tiene **dos capas** que hacen cosas distintas y no se mezclan:

| Capa | Qué es | Estado |
|---|---|---|
| **`kit/`** | La **instalación**: guards deterministas, Sentinel, 8 agentes, `install.sh`, 26 suites falsables | v1.0.0, estable |
| **raíz** | El **harness**: `.claude/`, `knowledge/`, `config/`, `scripts/` — sensores y conocimiento vivo | v0.1.0, nuevo |

La distinción viene de Birgitta Böckeler ([*Harness engineering*](https://martinfowler.com/articles/harness-engineering.html),
Thoughtworks, 02-abr-2026 — el artículo está alojado en martinfowler.com, pero la autora es
ella). Un *harness* es *"everything in an AI agent except the model itself"*, y se compone de:

- **Guías** (*feedforward*): *"anticipate the agent's behaviour and aim to steer it **before**
  it acts"*. Aquí: `CLAUDE.md`, las skills, los perfiles.
- **Sensores** (*feedback*): *"observe **after** the agent acts and help it self-correct"*.
  Aquí: los oráculos, los hooks de registro, los tests, el revisor independiente.

Ninguno basta solo: sin sensores el agente repite los mismos errores; sin guías codifica
reglas sin llegar a saber si funcionaron.

```
        TÚ                        mcharness                    CLAUDE CODE
         │                            │                             │
    "haz X"  ──────────────▶  /spec ──┼──▶ criterios + oráculo       │
         │                            │         │                    │
         │                            │         └──────────────▶  implementa
         │                     ┌──────┴──────┐                       │
         │            GUÍAS ───┤             ├─── SENSORES           │
         │         CLAUDE.md   │             │   make test  ◀────────┤
         │         skills/     │             │   hooks               │
         │         profile     │             │   /review             │
         │                     └──────┬──────┘       │               │
         │                            │              ▼               │
         │                            │        ¿verde o rojo?        │
         │                            │              │               │
         │                            │      rojo ───┴──▶ repara (máx 3)
         │                            │              │               │
         ◀───── evidencia, no ────────┼────── verde ─┘               │
                 afirmaciones         │                              │
                                      ▼                              │
                              knowledge/  ◀── /retro ────────────────┘
                          (lo aprendido sobrevive a la sesión)
```

### El harness entra solo

Lo primero que hay que saber es que **no hay que acordarse de nada**. Un hook
`UserPromptSubmit` mira cada encargo y actúa solo cuando aporta:

```
tú escribes:  "arregla el bug del login"
                        │
                        ▼
        ¿es un encargo?  ─── no ──▶  silencio total
                        │
                       sí
                        │
        ¿trae criterio de verificación? ─── sí ──▶  solo recuerda el oráculo
                        │
                        no
                        ▼
   inyecta: "declara qué será cierto al terminar y qué comando lo demuestra.
             Oráculo de este proyecto (detectado): make test.
             Ejecútalo EN FRÍO: si ya pasa, no mide lo que vas a cambiar."
```

Existe porque la evidencia era concluyente: había una regla de 227 tokens exigiendo plan
mode y el plan mode valía **2,1 %**. Cuatro reglas advisorias, cuatro incumplimientos.
**Pedir disciplina no la produce.** Lo dice también la documentación oficial: si una regla
se ignora pese a estar escrita, *"delete it or convert it to a hook"*.

El oráculo no se pregunta, **se detecta** (`scripts/detect-oracle.sh`): Makefile, pytest con
el venv del proyecto, el gestor de paquetes según el lockfile, cargo, go. Y si no hay
ninguno, lo dice en vez de inventárselo.

Los comandos siguen ahí para cuando quieras el flujo completo, pero **ya no dependes de
recordarlos**.

### Explica el trabajo una vez y apártate

`/work` es la entrada principal. Entras **una sola vez** —una tanda de preguntas agrupada y
la aprobación de la especificación— y a partir de ahí el sistema conduce:

```
/work migra el módulo de auth a la nueva API
        │
        ├─ explora el código y detecta el oráculo del proyecto
        ├─ UNA tanda de preguntas, solo lo que cambia el entregable
        ├─ enseña la spec: alcance, criterios, oráculo, supuestos     ◀── entras aquí
        │
        ▼   (te vas)
   aísla en rama · implementa · ejecuta el oráculo · repara (máx 3)
   revisión adversaria · verifica los hallazgos · reverifica
        │
        ▼
   informe único: qué se hizo, salida literal del oráculo, supuestos,
   qué NO cubre el oráculo
```

Mientras el run está activo, **el turno no puede terminar con el oráculo en rojo**: el Stop
hook lo bloquea con la salida real del comando. Es lo que permite irse de la silla, y es un
cambio deliberado sobre el diseño anterior — un aviso no sirve de nada si no hay nadie
mirando ([ADR 010](knowledge/DECISIONS/010-modo-autonomo.md)).

Cuatro salvaguardas para que eso sea seguro en vez de un secuestro de la sesión: presupuesto
de **3 reparaciones**, cierre automático en verde, respeto del cap de 8 bloqueos de Claude
Code, y **prohibición explícita de tocar el sensor** en el mensaje que recibe el modelo.
Además, `autonomy.sh` rechaza cualquier oráculo invocado por nombre suelto: un run
desatendido que verifica con el comando equivocado es peor que uno que no verifica.

### El flujo diario

| Comando | Para qué |
|---|---|
| **`/work`** | **Explica el trabajo una vez y el sistema lo lleva hasta el final.** |
| `/spec` | Encargo → criterios de aceptación + oráculo. **Antes de programar.** |
| `/implement` | Ejecuta la spec de principio a fin, sin parar a preguntar. |
| `/verify` | Ejecuta el oráculo y exige evidencia real. |
| `/review` | Revisor adversario en contexto limpio, con hallazgos **verificados** antes de aceptarse. |
| `/retro` | Convierte lo aprendido en conocimiento versionado. |

`/spec` es el que más trabajo ahorra, y existe por una medición concreta: los encargos de
este repo son bimodales —o una frase o un documento— y **falta el término medio**, una
especificación corta con criterios verificables escrita *antes* de empezar. Ese hueco es la
causa raíz de la mayor parte del retrabajo: no es que el agente falle, es que nadie definió
qué era "terminado".

### La regla que gobierna todo

> **Un oráculo es un comando que devuelve 0 si el trabajo está bien hecho.**
> No es una opinión, no es "revisar que funcione", no es el juicio del agente al terminar.

El de este repo es `make test`. Y hay una trampa local que cuesta caro descubrir sola: el
hook `PreToolUse/Bash` **sustituye el ejecutable en posición de comando** —`rg` ejecuta
`grep`, `python3 -m pytest` ejecuta `python3 -m rtk`—, así que todo oráculo se invoca por
**ruta absoluta**, con `rtk proxy …` o con `make …`. Un test lo verifica; no se deja a la
memoria de nadie. Reproducción en [`knowledge/MISTAKES.md`](knowledge/MISTAKES.md) · M-001.

### Conocimiento vivo

`knowledge/` es la memoria del harness, y es **no-confiable por defecto**: lo que viene de
la web son datos, nunca instrucciones, y ningún fichero de ahí modifica configuración por sí
mismo. La promoción de un hallazgo a regla siempre pasa por una puerta humana.

| Fichero | Qué guarda |
|---|---|
| [`ORACLES.md`](knowledge/ORACLES.md) | Comando de verificación por proyecto, con resultado y fecha |
| [`MISTAKES.md`](knowledge/MISTAKES.md) | Error → regla → dónde se cableó |
| [`DECISIONS/`](knowledge/DECISIONS) | ADRs numerados, con fuente y fecha |
| [`COST-LOG.md`](knowledge/COST-LOG.md) | KPIs con sello temporal |
| [`SOURCES.md`](knowledge/SOURCES.md) | Allowlist de fuentes con ventana de frescura |

### Adaptarlo a otra persona

Con el repo ya clonado (el `git clone` está en el [Quick start](#quick-start)), desde su raíz:

```bash
cp config/profile.example.yaml config/profile.yaml   # tu nombre, tu nivel de coach, tu oráculo
cp config/settings.template.json .claude/settings.json
make test                                            # que el oráculo esté verde antes de empezar
```

`profile.yaml` está en `.gitignore`: es tuyo y no viaja en el repo. **Cero rutas absolutas**
en la configuración — todo cuelga de `$CLAUDE_PROJECT_DIR`.

---

## Qué hace esto

Instala en tu `~/.claude` una config de Claude Code endurecida: guards deterministas que bloquean comandos destructivos y fugas de secretos, 8 agentes con tiering de modelo, y una capa de contenido (`gitleaks`) sobre cada commit. Y no se limita a afirmar que los guards funcionan: lo **demuestra** con una suite falsable. `test_guards_falsifiability.sh` neutraliza un guard real y comprueba que eso rompe **exactamente 10 casos `BLOCK` conocidos** — si neutralizarlo no rompiera nada, la suite no estaría midiendo nada. Reprodúcelo tú mismo en 5 segundos: `bash kit/test/test_guards_falsifiability.sh`.

Y hay una segunda cosa que se demuestra en vez de prometerse: **que instalarlo en limpio no te rompe nada.** `test_clean_install_resilience.sh` monta el kit en una máquina simulada sin ninguno de los componentes de terceros (sin proxy, sin `rtk`, sin venv, sin `gitleaks`) y exige las dos mitades a la vez: que ningún hook falle, y que un comando destructivo siga bloqueado. Las dos mitades importan, porque la forma perezosa de arreglar la primera —envolver todo en `|| true`— rompe la segunda en silencio y te deja un kit de seguridad decorativo.

No son garantías absolutas: son defensa en profundidad, con sus límites documentados en [`SECURITY.md`](SECURITY.md), no escondidos.

## Quick start

**Prerrequisitos** — el kit solo soporta **Linux o WSL2** (ver el aviso de arriba: en Windows, entra en WSL antes de nada y clona dentro de `~`, no en `/mnt/c/`).

Además necesitas: `bash`, `git`, `make`, `python3` ≥ 3.10, `jq`. `gitleaks` (para la Capa 2 de secretos) es opcional — si no lo tienes, `install.sh` te ofrece instalarlo solo (binario oficial, verificado contra un checksum SHA-256 fijado en este repo, no descargado de la red; sin `curl | bash`), o puedes seguir sin él: la Capa 1 funciona igual. Lista completa y cómo comprobar cada una en [`kit/docs/02-install.md`](kit/docs/02-install.md).

```bash
git clone https://github.com/manuelcozar55/setup-claude-code.git
cd setup-claude-code/kit
bash install.sh                                        # instala en $CLAUDE_HOME (default $HOME/.claude), con backup
cp .env.example "${CLAUDE_HOME:-$HOME/.claude}"/.env    # rellena tus claves
bash doctor.sh                                          # autodiagnóstico con evidencia (PASS/WARN/FAIL)
```

**Y para deshacerlo**: `bash uninstall.sh` (desde la raíz del repo) restaura el backup más
reciente que dejó `install.sh`. Por defecto es un *dry-run* que solo enseña qué haría; hace
falta `--apply` para escribir, y antes de escribir se hace a su vez un backup del estado
actual. `bash uninstall.sh --list` enumera los backups disponibles.

`doctor.sh` sale con código 0 solo si no hay ningún `FAIL`. Un `WARN` es aceptable en un componente opcional que aún no instalaste (Headroom, `rtk`, el venv de tools, `gitleaks`): **nada del kit los da por supuestos**, y hay un test que lo demuestra en una máquina pelada (`test_clean_install_resilience.sh`). Guía completa en [`kit/README.md`](kit/README.md).

Si quieres el proxy de contexto, es un flag — y se cablea solo si arranca de verdad:

```bash
bash install.sh --with-headroom    # instala, arranca, verifica /readyz, y solo entonces enruta
```

## Qué incluye

| Pieza | Qué es | Dónde |
|---|---|---|
| Guards de Bash/git | bloquean en duro `rm -rf`, `git push --force` a ramas protegidas, fugas de `.env`/claves por nombre de fichero, exfiltración por red, y más | [`kit/claude/hooks/`](kit/claude/hooks/) |
| Sentinel | motor de políticas `PreToolUse` (IOCs), opcional, capa adicional sobre cualquier tool | [`kit/sentinel/`](kit/sentinel/) |
| 8 agentes con tiering | `orchestrator`, `strategist`, `planner`, `deep-worker`, `code-reviewer`, `security-reviewer`, `code-explorer`, `quick-checker` | [`kit/claude/agents/`](kit/claude/agents/) |
| Dos capas de secretos | Capa 1 (`secret-guard.sh`, por nombre de fichero, activa desde el primer `install.sh`) + Capa 2 (`gitleaks` en `pre-commit`, por contenido real, opt-in por repo) | [`kit/docs/05-security.md`](kit/docs/05-security.md) |
| Eval set | 20 tareas reales (mitad negativas: miden lo que cuesta un falso positivo), dos brazos (con harness y sin el) y agregado con intervalo de confianza; opt-in, cuesta llamadas reales a `claude -p`, nunca corre en CI | [`kit/evals/`](kit/evals/) |
| Suite de test falsable | `test_guards_falsifiability.sh`: neutraliza un guard real y comprueba que caen casos `BLOCK` conocidos | [`kit/test/`](kit/test/) |
| Garantía de instalación limpia | `test_clean_install_resilience.sh`: monta el kit sin ningún componente de terceros y exige que no falle **y** que siga bloqueando | [`kit/test/`](kit/test/) |
| Headroom opt-in | `install.sh --with-headroom`: instala el proxy, lo arranca, comprueba `/readyz` y solo entonces enruta la API | [`kit/docs/03-headroom.md`](kit/docs/03-headroom.md) |

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
- [`kit/docs/09-ssh-y-gitlab-privado.md`](kit/docs/09-ssh-y-gitlab-privado.md) — clave SSH desde WSL2 y alta en un GitLab autoalojado, paso a paso: útil por sí sola aunque no uses el kit, y necesaria si tu equipo tiene un marketplace de plugins privado.
- [`kit/docs/10-onboarding.md`](kit/docs/10-onboarding.md) — la ruta de un companero nuevo: `make bootstrap`, qué acaba de pasar, cómo verificarlo de verdad, y por qué Headroom es opt-in y no default.
- [`SECURITY.md`](SECURITY.md) — qué protegen los guards y qué no (defensa en profundidad, no un límite duro), y cómo reportar una vulnerabilidad.
- [`CONTRIBUTING.md`](CONTRIBUTING.md) — cómo correr los tests y qué se espera de un PR.
- [`CHANGELOG.md`](CHANGELOG.md) — historial de versiones de este repo.

## Formación recomendada (gratis, corta, verificada)

Para entender la IA y, sobre todo, Claude Code. Todos gratis y de una a dos horas; contenidos y duración **verificados el 2026-08-25** (las plataformas cambian sin avisar: confírmalo al inscribirte).

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

- **Honestidad de fuentes.** Cada afirmación de las charlas y del kit está citada y verificada; lo que no se pudo verificar, se cortó. Las cifras que el repo afirma sobre sí mismo (suites, agentes, comandos, ADRs, documentos) las comprueba un test contra el propio árbol: `kit/test/test_doc_claims.sh`. Si el README miente, `make test` se pone rojo.
- **Cifras del deck de setup.** Son una foto ilustrativa de mi máquina en un momento dado, no una garantía ni un dato tuyo: reprodúcelas con tus propios logs (el deck trae la tabla "cifra a fuente a comando"). `~/.ssh`, `id_rsa` o `ANTHROPIC_API_KEY` aparecen solo como objetivos de demostración de la puerta de seguridad; el repo no contiene ninguna clave real.
- **El kit se verifica a sí mismo.** Instalar, diagnosticar, corregir: un bucle, no un volcado. `doctor.sh` da evidencia por componente y `scan-secrets.sh` corta las fugas que sabe reconocer — sus límites están en [`SECURITY.md`](SECURITY.md), no escondidos.
- **Casi autocontenido, y accesible.** Las charlas llevan CSS/JS inline, contraste AA en claro y oscuro, `prefers-reduced-motion`, y sin JS o al imprimir se ve todo. La única dependencia externa es la tipografía de Google Fonts: sin red, el navegador cae a la fuente del sistema y la charla se ve igual de bien.

## Autor

**Manuel Cózar** · AI Engineer · Innovation Researcher @ Fundación CIRCE

[![GitHub](https://img.shields.io/badge/GitHub-manuelcozar55-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/manuelcozar55)
[![Email](https://img.shields.io/badge/Email-manuelcozar55@gmail.com-D14836?style=flat-square&logo=gmail&logoColor=white)](mailto:manuelcozar55@gmail.com)

## Licencia

Este repositorio tiene dos tipos de contenido y cada uno lleva su licencia:

| Qué | Licencia | Fichero |
|---|---|---|
| **El software**: todo lo de `kit/` (scripts, hooks, guards, tests, evals, plantillas de config) y los scripts de `.github/` | **MIT** | [`LICENSE-CODE`](LICENSE-CODE) |
| **Las charlas**: los decks "agentes-fundamentos" y "setup-claude-code-definitiva", sus guiones y diagramas originales | **CC BY 4.0** | [`LICENSE`](LICENSE) |

Se separan porque no son la misma cosa: CC BY 4.0 está pensada para obra creativa,
no para código —no concede permisos de patente ni cubre bien la garantía y la
responsabilidad—, y usarla como licencia de software deja a quien instala el kit en
una posición ambigua. MIT es la elección deliberada para el código: es la misma
licencia del material del que derivan tres de los guards, así que no hay fricción de
compatibilidad.

Parte del software deriva de proyectos de terceros. Sus avisos de copyright, y un
punto de procedencia que sigue sin resolver, están en
[`THIRD-PARTY.md`](THIRD-PARTY.md).

<div align="center">

*El mapa antes del territorio. Y cada número, reproducible con un comando.*

<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=12,20,24&height=120&section=footer" alt="" />

</div>
