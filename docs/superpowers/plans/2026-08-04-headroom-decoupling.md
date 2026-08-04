# Desacoplar Headroom del kit — Implementation Plan

> **For agentic workers:** steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** que una instalación limpia del kit por un tercero no pueda romper Claude Code, y que
quien sí quiera Headroom lo instale y lo cablee con un flag, con el modo que protege el ahorro real.

**Architecture:** opción B (desacoplado). `settings.json` deja de fijar `ANTHROPIC_BASE_URL`.
Un wrapper `optional-hook.sh` convierte toda dependencia de tercero en no-op silencioso en vez de
error. `install.sh --with-headroom` es la única ruta que enruta el tráfico al proxy, y solo tras
comprobar que responde. `doctor.sh` deja de mentir: si la variable está puesta y el puerto no
contesta, es FAIL, no WARN.

**Tech Stack:** bash, jq, python3, systemd --user, headroom-ai (PyPI), pytest-free (suites bash).

## Global Constraints

- Plataforma soportada: Linux / WSL2 únicamente (`install.sh` ya tiene la puerta; no tocar).
- `set -euo pipefail` en scripts nuevos; `set -uo pipefail` en `doctor.sh` (no aborta en el primer fallo).
- Ningún hook puede salir con código 2 salvo para bloquear de verdad: 2 = blocking error en Claude Code.
- Ninguna dependencia de tercero (`rtk`, venv de tools, `headroom`) puede ser requisito para que un
  hook funcione. Ausente = no-op silencioso, exit 0.
- Idempotencia: reejecutar `install.sh` y `--with-headroom` no debe duplicar estado.
- No se redistribuye Headroom. Se instala desde PyPI (`headroom-ai`) en el venv del usuario.
- Todo número que aparezca en docs va con su comando de reproducción al lado.

---

### Task 1: wrapper `optional-hook.sh`

**Files:**
- Create: `kit/claude/hooks/optional-hook.sh`
- Test: `kit/test/test_optional_hook.sh`

**Interfaces:**
- Produces: `optional-hook.sh [--python] <cmd> [args...]`. Exit 0 y sin salida si el ejecutable
  (o, con `--python`, el intérprete o el script) no existe. Si existe, hace `exec` y propaga
  su código de salida tal cual (incluido el 2 que bloquea).

- [ ] **Step 1: test que falla primero** — `kit/test/test_optional_hook.sh` cubre:
      (a) comando inexistente → exit 0, sin stdout/stderr;
      (b) `--python` con venv ausente → exit 0;
      (c) comando existente que sale 2 → exit 2 propagado (el guard sigue bloqueando);
      (d) comando existente que sale 0 → exit 0.
- [ ] **Step 2: correr y ver fallar** — `bash kit/test/test_optional_hook.sh` → FAIL (no existe el wrapper).
- [ ] **Step 3: implementar el wrapper.**
- [ ] **Step 4: correr y ver pasar** — los 4 casos PASS.
- [ ] **Step 5: commit** — `feat(hooks): optional-hook.sh degrada a no-op las deps de terceros`.

### Task 2: `settings.json` sin `ANTHROPIC_BASE_URL` y hooks envueltos

**Files:**
- Modify: `kit/claude/settings.json`
- Test: `kit/test/test_clean_install_resilience.sh`

- [ ] **Step 1: test que falla primero** — asserts: `settings.json` NO contiene
      `ANTHROPIC_BASE_URL`; todo `command` que invoque `python3` del venv o `rtk` pasa por
      `optional-hook.sh`; el JSON sigue siendo válido; los 8 deny y los 8 allow intactos.
- [ ] **Step 2: correr y ver fallar** (hoy la clave está y los hooks van desnudos).
- [ ] **Step 3: editar `settings.json`** — quitar la línea de `ANTHROPIC_BASE_URL`; envolver
      `rtk hook claude`, `sentinel_preflight.py` y `smart_approve.py` con `optional-hook.sh`.
- [ ] **Step 4: correr y ver pasar.**
- [ ] **Step 5: commit** — `fix(kit): no enrutar a un proxy que el kit no instala`.

### Task 3: `doctor.sh` — el WARN que debía ser FAIL

**Files:**
- Modify: `kit/doctor.sh`
- Test: `kit/test/test_doctor_base_url.sh`

- [ ] **Step 1: test que falla primero** — tres casos:
      (a) `ANTHROPIC_BASE_URL` puesta + puerto muerto → FAIL y exit ≠ 0;
      (b) variable ausente → no FAIL por este motivo;
      (c) variable puesta + endpoint vivo (servidor de prueba en un puerto libre) → PASS.
- [ ] **Step 2: correr y ver fallar** (hoy no existe la comprobación).
- [ ] **Step 3: implementar** — check nuevo; además separar Headroom de `rtk` en el check 5
      (son dos herramientas) y comprobar el intérprete que los hooks necesitan.
- [ ] **Step 4: correr y ver pasar**, y `bash kit/test/test_doctor.sh` seguir en verde.
- [ ] **Step 5: commit** — `fix(doctor): un base URL muerto es FAIL, no WARN`.

### Task 4: `install.sh --with-headroom`

**Files:**
- Modify: `kit/install.sh`
- Test: `kit/test/test_with_headroom.sh`

- [ ] **Step 1: test que falla primero** — con `HEADROOM_DRY_RUN=1`: escribe la unidad en un
      `XDG_CONFIG_HOME` temporal, la unidad contiene `--mode cache`, y `settings.json` solo
      gana `ANTHROPIC_BASE_URL` cuando el readiness check pasa (simulado). Sin red, sin systemd.
- [ ] **Step 2: correr y ver fallar.**
- [ ] **Step 3: implementar el subcomando** — instala `headroom-ai` en el venv, escribe la unidad
      de usuario (basada en la unidad probada de esta máquina), `daemon-reload`, `enable --now`,
      espera `/readyz`, y solo entonces mete la variable en `settings.json` con `jq`.
- [ ] **Step 4: correr y ver pasar.**
- [ ] **Step 5: commit** — `feat(install): --with-headroom instala, verifica y luego cablea`.

### Task 5: reescribir `kit/docs/03-headroom.md`

**Files:**
- Modify: `kit/docs/03-headroom.md`
- Modify: `kit/docs/08-plugins-mcp-y-skills.md` (la frase que llama `rtk` a Headroom)

- [ ] **Step 1: corregir el error de fondo** — Headroom y `rtk` son dos herramientas distintas:
      Headroom es el proxy (`headroom proxy`, paquete `headroom-ai`, systemd, :8787); `rtk` es un
      optimizador de comandos independiente que se cablea como hook `PreToolUse`. Hoy el doc los
      presenta como el mismo producto.
- [ ] **Step 2: documentar el ahorro con las cifras medidas y su comando** — prompt caching de
      Anthropic 94,9 % hit / 4.731 $ frente a 17,20 $ (0,88 %) de la compresión propia: ratio 275×.
      De ahí la regla: el modo `cache` no es una preferencia, es lo que protege el 99 % del ahorro.
- [ ] **Step 3: documentar las tres trampas verificadas** — (a) de los cuatro perfiles solo
      `coding` usa modo cache; (b) `headroom install` puede crear una segunda unidad que pelea por
      el 8787 y el health-check contesta con el proxy equivocado; (c) `kompress` se queda
      `unhealthy` sin `~/.cache/huggingface` escribible, y por eso se comprueba `/readyz`, no `/health`.
- [ ] **Step 4: el output-shaper como única palanca sin riesgo** — reduce tokens de salida, que no
      se cachean; solo se activa con un POST a `/admin/runtime-env`.
- [ ] **Step 5: commit** — `docs(headroom): corrige la confusión con rtk y documenta el ahorro real`.

### Task 6: README y CHANGELOG al día

**Files:**
- Modify: `README.md` (el párrafo que dice que un WARN de Headroom es aceptable)
- Modify: `CHANGELOG.md`
- Modify: `kit/README.md`, `kit/docs/02-install.md`, `kit/docs/07-verify.md` (referencias cruzadas)

- [ ] **Step 1: corregir la promesa falsa del README** — hoy dice que el setup base funciona sin
      Headroom, y con la config actual no era verdad. Con este cambio pasa a serlo: decirlo bien.
- [ ] **Step 2: entrada de CHANGELOG** describiendo el breaking change de config.
- [ ] **Step 3: commit** — `docs: el kit ya no depende de un proxy para arrancar`.

### Task 7: suite completa en verde

- [ ] **Step 1: correr todas las suites de `kit/test/`** y anotar resultado real.
- [ ] **Step 2: correr `bash kit/doctor.sh`** en un `CLAUDE_HOME` temporal recién instalado.
- [ ] **Step 3: `test_guards_falsifiability.sh`** debe seguir demostrando que neutralizar un guard
      rompe casos BLOCK conocidos.
- [ ] **Step 4: commit final** y informe.

## Self-Review

- **Cobertura:** los 3 install-breakers → Tasks 1-3. El error factual → Task 5. El "máximo ahorro
  sin perder calidad" → Tasks 4-5. Sin huecos.
- **Placeholders:** ninguno; cada task nombra ficheros exactos y asserts concretos.
- **Consistencia:** `optional-hook.sh` se define en Task 1 y se consume en Task 2 con la misma firma.
- **Fuera de alcance, dicho explícitamente:** traducción a inglés (pendiente de decisión del autor);
  `model: opus[1m]` y `effortLevel: xhigh` se dejan como están (son la identidad opinada del kit, y
  no pude verificar cómo falla en una cuenta sin acceso a Opus); no se toca `~/.claude` de esta máquina.
</content>
</invoke>
