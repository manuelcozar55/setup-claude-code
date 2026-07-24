# Claude Code Setup Kit — Design Spec

**Fecha:** 2026-07-25 · **Autor:** manuelcozar55 · **Estado:** aprobado (brainstorming)
**Ubicación del entregable:** `data/claude-code-setup/` dentro del repo `setup-claude-code`.

## Objetivo

Un kit autocontenido, saneado y **auto-verificable** que replica el setup de Claude Code del autor (de Headroom a la rutina con haiku) en otro ordenador, de forma **segura** (cero secretos) y **100% funcional** (instala, se autodiagnostica y pasa un gate de seguridad, todo con evidencia reproducible).

## Principios rectores (Karpathy + loop engineering)

El kit no solo copia ficheros: encarna el mismo modelo mental que enseñan las charlas del repo, y se aplica a sí mismo.

1. **LLM = CPU, contexto = RAM, spec = fuente de verdad** (Karpathy). El kit trata sus *ficheros* como la fuente de verdad durable: `install.sh` reconstruye el estado en cualquier máquina desde disco, igual que una spec reconstruye el estado tras compactar. Nada vive solo "en la cabeza" del que lo montó.
2. **Design the loop, not the prompt** (loop engineering, LangChain). El kit es un bucle, no un volcado: **instalar → diagnosticar → corregir → reinstalar**. `doctor.sh` es el bucle de verificación; `scan-secrets.sh` es el guardarraíl determinista; juntos forman el "hill-climbing loop" que hace el kit fiable, no solo presente.
3. **Verificar, no confiar** (evidencia > afirmaciones). Ningún paso se da por bueno sin su comando y su salida esperada. `doctor.sh` imprime, por cada componente, la cifra/estado y cómo se obtuvo ("cifra → fuente → comando").
4. **Autonomía acotada + contención de riesgo.** `install.sh` es idempotente, hace *backup* antes de tocar nada y **nunca pisa** una config existente sin copia; el radio de impacto de un fallo está acotado.
5. **La ceremonia se ajusta al riesgo.** El kit distingue lo que copia (config propia, portable) de lo que solo documenta (terceros: Headroom, plugin superpowers, agent-browser, stack ML del venv): no redistribuye binarios ni datos personales.
6. **March of nines / degradación elegante.** Si falta un componente opcional (p. ej. Headroom no instalado), `doctor.sh` lo reporta como WARN, no como fallo duro: el setup base funciona sin él.

## Arquitectura y estructura de ficheros

```
data/claude-code-setup/
├── README.md                 # portada estilo manuelcozar55 (banner, badges, quickstart, mermaid)
├── install.sh                # instalador idempotente → CLAUDE_HOME (backup, no pisa)
├── doctor.sh                 # health-check con evidencia (cifra→fuente→comando)
├── scan-secrets.sh           # gate determinista de secretos sobre el propio kit
├── .env.example              # placeholders: ANTHROPIC/PERPLEXITY/LANGSMITH_API_KEY, etc.
├── requirements-tools.txt    # CLI curado del venv de tools (no el stack ML)
├── claude/                   # ~/.claude portable y saneado
│   ├── CLAUDE.md             # email→placeholder, /root→$HOME
│   ├── settings.json         # env-secrets fuera/placeholder, rutas plantilladas ($CLAUDE_HOME)
│   ├── hooks/                # block-dangerous · branch/destructive/secret-guard · session-start · pre-compact · stop-session-summary · smart_approve.py
│   ├── agents/               # los 8 agentes (portables)
│   └── sentinel-allowlist.json  # saneado (dominios personales → ejemplo)
├── sentinel/                 # motor de políticas: sentinel_preflight.py (+ soporte), saneado
├── test/                     # tests TDD (bash)
│   ├── test_scan_secrets.sh  # fixtures: secreto falso→FAIL, kit limpio→PASS
│   ├── test_install.sh       # instala en CLAUDE_HOME temporal: ficheros, ejecutables, backup, idempotencia
│   └── test_doctor.sh        # valida detección de hooks/venv y ausencia de secretos
└── docs/
    ├── 01-overview.md        # el mapa: modelo Karpathy + los 10 pilares + cómo encaja cada pieza
    ├── 02-install.md         # prereqs (node/pnpm, python, gh, jq) e instalación paso a paso
    ├── 03-headroom.md        # Headroom (rtk/proxy): instalar + config + cómo se cablea el proxy
    ├── 04-superpowers.md     # plugin superpowers + skills + los 8 agentes + tiering
    ├── 05-security.md        # Sentinel + guards + manejo de secretos + trade-off fail-open
    ├── 06-routine.md         # tiering opus/sonnet/haiku, ping 6:00, /compact, opus[1m], worktrees (+ plantilla cron/systemd opcional)
    └── 07-verify.md          # doctor.sh + scan-secrets.sh; filosofía "cifra→fuente→comando"
```

## Componentes e interfaces

- **Extracción + saneado** → produce `claude/`, `sentinel/`, `requirements-tools.txt`, `.env.example`. Regla de saneado: sustituir secretos por placeholders, `/root`→`$HOME`/`$CLAUDE_HOME`, email real→`you@example.com`, dominios personales del allowlist→ejemplos. Fuente: los ficheros reales de `~/.claude`, `/root/sentinel`, `~/.venvs/tools` (lectura cuidadosa; algunas lecturas pueden requerir aprobación por el clasificador).
- **`install.sh`** — Consume: el kit. Produce: instalación en `CLAUDE_HOME` (default `~/.claude`). Contrato: `CLAUDE_HOME=/ruta ./install.sh`; hace backup timestamped de cualquier fichero que fuese a sobrescribir; marca hooks como ejecutables; idempotente (segunda ejecución no rompe ni duplica). No instala terceros: imprime los comandos y remite a `docs/`.
- **`doctor.sh`** — Consume: una instalación (`CLAUDE_HOME`). Produce: informe PASS/WARN/FAIL por componente con evidencia. Exit 0 solo si no hay FAIL. Comprueba: hooks referencian ficheros existentes y ejecutables; `settings.json` es JSON válido; venv de tools presente (WARN si no); Headroom reachable (WARN si no); **cero secretos** en `CLAUDE_HOME` gestionado por el kit.
- **`scan-secrets.sh`** — Consume: un directorio (default el kit). Produce: exit≠0 y lista de hallazgos si detecta patrones de secreto/PII (claves `sk-`/`pplx-`/PEM/AKIA, tokens `gho_`/`ghp_`, `/root/`, emails reales conocidos, nombres de ficheros de credenciales). Es el guardarraíl determinista del kit.
- **`docs/`** — Conocimiento transferible. Terceros documentados con comandos, no binarios.
- **`README.md`** — Portada en el estilo del autor (banner capsule-render, badges for-the-badge, tabla, mermaid, Notas de experto, Autor).

## Política de seguridad (estricta + gate)

**Nunca se incluyen:** `.credentials.json`, `*.env` (perplexity/langsmith), `history.jsonl`, `audit-logs/`, `daemon.log`, `*.db`/`ccr_store*`, `savings*`, `sessions/`, `transcripts/`, `projects/`, `backups/`, `telemetry/`, cachés. **Secretos → placeholders** en `.env.example`. **Rutas** `/root`→`$HOME`/`$CLAUDE_HOME`. El `scan-secrets.sh` se ejecuta en la verificación final y **bloquea** el visto bueno si algo se cuela. `.gitignore` del repo se estrecha para versionar `data/claude-code-setup/` excluyendo solo binarios/DBs/logs residuales.

## Estrategia de tests (TDD)

Arnés bash simple (sin dependencias; usa `bats` si está disponible, si no funciones `assert`). Rojo → verde → commit por unidad:
- **`scan-secrets.sh`**: fixture con `sk-`/`/root/`/email real → **FAIL**; kit saneado → **PASS**. (Se escribe el test que falla antes de implementar el escáner.)
- **`install.sh`**: instalar en `CLAUDE_HOME=$(mktemp -d)` → assert ficheros presentes, hooks ejecutables, `settings.json` válido; re-ejecutar → idempotente; con fichero previo → assert backup creado y original no pisado.
- **`doctor.sh`**: sobre una instalación de prueba → PASS; con hook faltante → FAIL; con secreto inyectado → FAIL.

## Manejo de terceros (documentado, no copiado)

- **Headroom** (`rtk`/proxy local): `docs/03-headroom.md` con instalación, arranque del proxy, y el cableado del hook `rtk hook claude`. Sin binarios ni DBs de ahorro.
- **superpowers** (plugin) + skills + 8 agentes: `docs/04-superpowers.md` con el marketplace/instalación y el listado.
- **agent-browser**: instalación global y política de uso.
- **venv ML**: solo `requirements-tools.txt` curado (CLI: markitdown, ast-grep-cli, basedpyright, ruff, etc.); el stack torch/cuda/azure NO se replica (específico de GPU/máquina), se menciona como opcional.

## Criterios de éxito (100% funcional, verificable)

1. `bash scan-secrets.sh data/claude-code-setup` → PASS (0 hallazgos) — evidencia en salida.
2. `CLAUDE_HOME=$(mktemp -d) bash install.sh` → instala sin error; `doctor.sh` sobre esa instalación → PASS/WARN, 0 FAIL.
3. Re-ejecutar `install.sh` → idempotente (sin error, backups intactos).
4. Todos los `test/*.sh` → verde.
5. `docs/` cubre las 7 áreas; README renderiza (banner/badges/mermaid).
6. El repo versiona `data/claude-code-setup/` sin ningún secreto (verificado por el gate + revisión final).

## Fuera de scope

- Redistribuir binarios de terceros o datos personales (logs, DBs, savings, sesiones).
- Reproducir el stack ML de GPU del venv.
- Automatizar el alta del proxy/ping en la máquina destino (se entrega plantilla opcional, no se ejecuta).
- Instaladores para Windows nativo (objetivo: Linux/WSL/macOS, bash).
