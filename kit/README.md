<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=12,20,24&height=200&section=header&text=claude-code-setup&fontSize=44&fontColor=ffffff&animation=fadeIn&desc=El%20kit%20transferible%20detr%C3%A1s%20de%20mi%20trabajo%20con%20Claude%20Code&descAlignY=62&descSize=17" alt="claude-code-setup" />

![Claude Code](https://img.shields.io/badge/Claude_Code-kit-D97757?style=for-the-badge&logo=anthropic&logoColor=white)
![Bash](https://img.shields.io/badge/Scripts-Bash-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)
![Security](https://img.shields.io/badge/scan--secrets-PASS-2EA44F?style=for-the-badge&logo=shieldsdotio&logoColor=white)
![License](https://img.shields.io/badge/License-CC_BY_4.0-EF9421?style=for-the-badge)

> **De los guards a la rutina.** No es una config que se copia y ya, es un bucle que se instala, se diagnostica y se corrige a sí mismo.

</div>

---

## Qué es esto

Un kit transferible: la config saneada de `~/.claude` (`CLAUDE.md`, `settings.json`, agentes, hooks de guardarraíles), y los scripts que instalan y verifican todo lo anterior con evidencia reproducible. No es una demo, es la máquina real, empaquetada para que corra en otra máquina distinta a la mía.

Cubre desde los **guards** que bloquean antes de que el modelo actúe hasta el estado de cada tarea en disco y el bucle `/deep-change`. Por defecto se instala solo el núcleo; Sentinel, el cockpit, el plugin **esenciales**, los revisores, `retro` y los avisos de contexto son piezas opcionales que se piden con `--con` (ver el Quickstart). Cada pieza tapa un hueco concreto de los diez pilares de ingeniería de agentes; el mapa completo está en [`docs/01-overview.md`](docs/01-overview.md). Esta config es el esqueleto: la pila completa (plugins de Claude Code, servidores MCP, skills adicionales) está documentada en [`docs/08-plugins-mcp-y-skills.md`](docs/08-plugins-mcp-y-skills.md).

## Quickstart

Linux o WSL2. Desde la raíz del clon, `bash kit/install.sh` instala el núcleo (idempotente, con
backup) y acaba con el veredicto de `doctor.sh` (`bash kit/doctor.sh` lo repite con el detalle: sale 0 solo sin ningún `FAIL`).
Las piezas opcionales se piden con `bash kit/install.sh --con <pieza>[,<pieza>…]`: `sentinel`, `cockpit`, `esenciales`, `revisores`,
`skills-extra`, `nudge`. Primer día guiado en
[`docs/10-onboarding.md`](docs/10-onboarding.md). (`make bootstrap` añade la suite y es para quien desarrolla este repo, no para usar el kit.) El procedimiento completo
—a mano, venv de tools, plugins, Capa 2 y desinstalar— está solo en [`docs/02-install.md`](docs/02-install.md).

## Qué incluye

| Pieza | Contenido | Qué resuelve |
|---|---|---|
| `claude/` | `CLAUDE.md`, `settings.json`, `sentinel-allowlist.json`, `.gitleaks.toml` | la config saneada que `install.sh` copia a `CLAUDE_HOME` |
| `claude/hooks/` | guards de Bash (`block-dangerous-commands.sh`, `branch-guard.sh`, `destructive-guard.sh`, `secret-guard.sh`, `bash-write-guard.sh`), `optional-hook.sh`, hooks de sesión, y `hooks/git/pre-commit` (Capa 2 de secretos, por contenido, con `claude/.gitleaks.toml`) | barreras deterministas antes de cada acción, y sobre el índice real antes de cada commit |
| `claude/agents/` | 7 agentes (`deep-worker`, `code-reviewer`, `security-reviewer`, `code-explorer`, `quick-checker`, `pr-test-analyzer`, `silent-failure-hunter`; los dos últimos solo con `--con revisores`) | orquestación con tiering de modelo por tarea |
| `sentinel/` | `sentinel_preflight.py` (opcional: `--con sentinel`) | el motor de políticas `PreToolUse` que decide allow/warn/deny |
| `install.sh` · `doctor.sh` · `scan-secrets.sh` | scripts de instalación y verificación | instalar sin pisar nada, diagnosticar con evidencia, cerrar la puerta de secretos |
| `test/` | regresión de guards, instalador y Capa 2 de secretos, en bash puro | `test/test_guards.sh`, `test/test_guards_falsifiability.sh`, `test/test_secret_content_gitleaks.sh` y el resto: 68 suites, todas en `make test` |
| `claude/skills/` · `mods/cockpit/` | las 3 skills del método (`install.sh` copia `deep-change` a `~/.claude/skills/`; `retro` y `verification-before-completion` con `--con skills-extra`) y el mod de traspaso de sesión (`--con cockpit`; lo carga el lanzador `scc`) | llevar la forma de trabajar, no solo los guards; ver `docs/12-metodologia.md` |
| `evals/` | 23 tareas reales (10 positivas / 10 negativas / 3 de resultado), brazo de control (`ARM=off`), historico y puente a Phoenix para ver las trazas en local (opt-in, no corre en `test/`, cuesta llamadas reales a `claude -p`) | medir si el harness **sirve**, no solo si el agente pasa — ver [`evals/README.md`](evals/README.md) |
| `docs/` | 14 documentos, del mapa (`01`) al onboarding (`10`), el cockpit (`11`), la metodología (`12`), la memoria (`13`), cómo operar (`OPERAR`) y el mapa generado de piezas (`MAPA`); todos en el índice de abajo | el mapa mental y el "cómo" de cada pieza, con enlaces a terceros |

## Cómo funciona

El kit no es un script de un solo uso, es un bucle que se repite con las mismas garantías cada vez: instalar, diagnosticar, corregir, reinstalar.

```mermaid
flowchart LR
    I["1 · Instalar<br/>install.sh (idempotente, con backup)"]
    D["2 · Diagnosticar<br/>doctor.sh (PASS/WARN/FAIL por componente)"]
    C["3 · Corregir<br/>seguir lo que dice el doctor, reinstalar"]
    I --> D --> C -->|"vuelve a instalar"| I
    classDef paso fill:#475569,stroke:#334155,color:#FFFFFF
    classDef gate fill:#8F5E00,stroke:#6B4600,color:#FFFFFF
    class I,C paso
    class D gate
```

`design the loop, not the prompt`: `doctor.sh` es el bucle de verificación, `scan-secrets.sh` es el guardarraíl determinista que lo cierra. Ninguna pieza se da por instalada sin su comando y su salida esperada.

## Seguridad

El repo pasa por una puerta antes de cualquier commit: [`scan-secrets.sh`](scan-secrets.sh) escanea el kit en busca de claves (`sk-…`, `pplx-…`, tokens de GitHub, claves AWS, private keys), rutas absolutas de la cuenta root y emails reales. Exit 0 solo si el resultado es limpio. Desde la raíz del clon:

```bash
bash kit/scan-secrets.sh .
# PASS: sin secretos/PII en .
```

El kit no usa claves ni ficheros `.env`: no hay nada que rellenar. `doctor.sh` corre este mismo gate como su último chequeo. La barrera de secretos en sí es de dos capas: `secret-guard.sh` bloquea por nombre de fichero en `git add` (Capa 1), y un `pre-commit` con `gitleaks` escanea el contenido del índice real antes de cada commit (Capa 2, opcional, requiere `gitleaks` instalado — `install.sh` te lo ofrece instalar solo, con checksum verificado, si no lo tienes). La Capa 2 se activa por repositorio con `bash install.sh --enable-secrets-layer2` desde dentro del repo que quieras proteger, o con el one-liner manual equivalente. Detalle completo, incluyendo Sentinel, en [`docs/05-security.md`](docs/05-security.md).

## Terceros

El kit no redistribuye binarios de terceros, solo los documenta y los cablea con la config que sí instala:

| Documento | Cubre |
|---|---|
| [`docs/01-overview.md`](docs/01-overview.md) | el mapa: modelo mental de Karpathy y los 10 pilares |
| [`docs/02-install.md`](docs/02-install.md) | prerrequisitos, instalación paso a paso, venv de herramientas |
| [`docs/04-superpowers.md`](docs/04-superpowers.md) | el plugin esenciales (opcional, `--con esenciales`), los 7 agentes con tiering, agent-browser |
| [`docs/05-security.md`](docs/05-security.md) | los guards de Bash/git, Sentinel (opcional), manejo de secretos |
| [`docs/06-routine.md`](docs/06-routine.md) | una rutina diaria posible (la del autor, no automática): tiering, ping de las 6:00, `/compact`, worktrees |
| [`docs/07-verify.md`](docs/07-verify.md) | los tres scripts, con evidencia "cifra → fuente → comando" |
| [`docs/08-plugins-mcp-y-skills.md`](docs/08-plugins-mcp-y-skills.md) | la pila completa: plugins de Claude Code, servidores MCP, skills adicionales, prerrequisitos extra |
| [`docs/09-ssh-y-gitlab-privado.md`](docs/09-ssh-y-gitlab-privado.md) | clave SSH desde WSL2 y alta en un GitLab autoalojado, paso a paso |
| [`docs/10-onboarding.md`](docs/10-onboarding.md) | de cero a sesión verde: qué levantas, cómo leer `doctor.sh` y qué hacer cuando algo va mal |
| [`docs/11-cockpit.md`](docs/11-cockpit.md) | el mod `cockpit` (opcional): `/handoff`, Agent Dock y `scc` |
| [`docs/12-metodologia.md`](docs/12-metodologia.md) | el método en una página: `/deep-change`, estado automático y verificación |
| [`docs/13-memoria.md`](docs/13-memoria.md) | la memoria compartida y `recuerda` |
| [`docs/OPERAR.md`](docs/OPERAR.md) | qué hacer cuando algo estorba o falla, actualizar, desinstalar, costes |
| [`docs/MAPA.md`](docs/MAPA.md) | qué hace cada hook, agente, skill y variable, y cómo se apaga (generado) |
| [`docs/guia/`](docs/guia/00-ruta-7-dias.md) | trabajar bien tras instalar: ruta de 7 días, el porqué con cifras medidas, una sesión real, antipatrones, mídete y qué borrar de la plantilla |

## Notas de experto

- **Spec = fuente de verdad (Karpathy).** Lo único que sobrevive cuando el contexto se vacía (un `/compact`, una sesión nueva) es lo que quedó escrito en disco. Este kit trata sus propios ficheros igual que una spec: `install.sh` reconstruye el estado completo a partir de lo que hay en disco, no de lo que alguien recuerde haber configurado a mano.
- **Loop engineering: el kit se verifica a sí mismo.** No hay paso de instalación sin su paso de diagnóstico correspondiente: `install.sh` sin `doctor.sh` es fe ciega. El bucle instalar → diagnosticar → corregir es el mismo principio de "diseña el bucle, no el prompt" aplicado al propio kit, no solo a cómo se opera Claude Code con él.
- **Idempotencia con backup, nunca sobrescritura silenciosa.** Cada fichero que `install.sh` fuera a pisar se guarda antes con timestamp en `$CLAUDE_HOME/backups/`. Correrlo dos veces nunca pierde tu configuración previa.
- **Degradar con elegancia, no romper.** Componentes opcionales (venv de tools, `rtk`, `gitleaks`) producen `WARN`, no `FAIL`: el setup base funciona sin ellos.

## Autor

**Manuel Cózar** · AI Engineer · Innovation Researcher @ Fundación CIRCE

[![GitHub](https://img.shields.io/badge/GitHub-manuelcozar55-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/manuelcozar55)
[![Email](https://img.shields.io/badge/Email-manuelcozar55@gmail.com-D14836?style=flat-square&logo=gmail&logoColor=white)](mailto:manuelcozar55@gmail.com)

<div align="center">

*El bucle antes que el prompt. Y cada línea de `doctor.sh`, reproducible con un comando.*

<img src="https://capsule-render.vercel.app/api?type=waving&color=gradient&customColorList=12,20,24&height=120&section=footer" alt="" />

</div>
