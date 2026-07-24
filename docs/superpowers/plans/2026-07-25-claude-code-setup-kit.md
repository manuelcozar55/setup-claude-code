# Claude Code Setup Kit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir en `data/claude-code-setup/` un kit transferible, saneado y auto-verificable que replica el setup de Claude Code del autor (de Headroom a la rutina con haiku) en otra máquina, de forma segura y 100% funcional.

**Architecture:** Kit espejo-saneado con bucle instalar→diagnosticar→corregir. Tres scripts bash (scan-secrets, install, doctor) con TDD, una capa `claude/`+`sentinel/` saneada extraída de los ficheros reales, y `docs/` que documenta los terceros (Headroom/superpowers/agent-browser/venv). Encarna los principios Karpathy (spec/disco como fuente de verdad) y loop engineering (verificación como bucle, guardrail determinista).

**Tech Stack:** bash (POSIX-friendly, `set -euo pipefail`), `jq`, `git`, `find`/`grep -E`. Tests en bash puro (sin dependencias; `bats` opcional).

## Global Constraints

- **Cero secretos en el kit.** Nunca incluir `.credentials.json`, `*.env`, `history.jsonl`, `audit-logs/`, `daemon.log`, `*.db`/`ccr_store*`, `savings*`, `sessions/`, `transcripts/`, `projects/`, `backups/`, `telemetry/`, cachés. Secretos→placeholders en `.env.example`. Rutas `/root`→`$HOME`/`$CLAUDE_HOME`. Email real→`you@example.com`.
- **No hardcodear literales personales** (email real, tokens) ni siquiera dentro de los scripts que se envían: el escáner detecta por patrón/heurística, no por lista de valores reales.
- **Idempotencia y backup**: `install.sh` nunca pisa sin copia timestamped; segunda ejecución no rompe.
- **Evidencia**: cada script imprime estado + cómo se obtuvo; `doctor.sh` usa PASS/WARN/FAIL, exit 0 solo si 0 FAIL.
- **Terceros = instrucciones**, no binarios ni datos personales.
- **Autoría**: commits como `manuelcozar55 <manuelcozar55@gmail.com>`, SIN trailer `Co-Authored-By` (preferencia del usuario, sobrescribe la regla global).
- **Objetivo de shell**: Linux/WSL/macOS (bash). No Windows nativo.
- **Todos los scripts** empiezan con `#!/usr/bin/env bash` y `set -euo pipefail`, y son `chmod +x`.

## File Structure

```
data/claude-code-setup/
├── README.md
├── install.sh
├── doctor.sh
├── scan-secrets.sh
├── .env.example
├── requirements-tools.txt
├── claude/{CLAUDE.md,settings.json,agents/*,hooks/*,sentinel-allowlist.json}
├── sentinel/sentinel_preflight.py
├── test/{test_scan_secrets.sh,test_install.sh,test_doctor.sh}
└── docs/{01-overview,02-install,03-headroom,04-superpowers,05-security,06-routine,07-verify}.md
```

---

## Task 1: Scaffolding del kit + reconciliar `.gitignore` + retirar capturas

**Files:**
- Create dirs: `data/claude-code-setup/{claude/agents,claude/hooks,sentinel,test,docs}`
- Modify: `.gitignore`
- Delete: `data/*.jpeg` (capturas de WhatsApp)

**Interfaces:**
- Produces: el árbol de directorios vacío del kit y un `.gitignore` que versiona `data/claude-code-setup/` excluyendo binarios/DBs/imágenes residuales.

- [ ] **Step 1: Ver el `.gitignore` actual y las imágenes**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
sed -n '1,5p' .gitignore   # la línea 1 es "data/" (bloquea todo data/)
ls data/*.jpeg | wc -l      # 10 capturas
```
Expected: `.gitignore` contiene `data/`; 10 jpeg.

- [ ] **Step 2: Estrechar `.gitignore`**

Reemplaza el bloque de `data/` (las primeras líneas con el comentario de WhatsApp y `data/`) por reglas que solo ignoren imágenes/binarios/datos, permitiendo versionar el kit:

Old:
```gitignore
# Capturas de origen (WhatsApp): fondo negro, barras de estado; no profesionales para compartir.
# Se conservan en local pero fuera del repo. Ver README (sección "Origen de los diagramas").
data/
```
New:
```gitignore
# Capturas de origen (WhatsApp) y binarios/datos: fuera del repo.
# El kit transferible (data/claude-code-setup/) SÍ se versiona.
data/*.jpeg
data/*.jpg
data/*.png
data/claude-code-setup/**/*.db
data/claude-code-setup/**/*.log
data/claude-code-setup/**/.env
```

- [ ] **Step 3: Borrar las capturas de WhatsApp y crear el árbol del kit**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
rm -f data/*.jpeg
mkdir -p data/claude-code-setup/{claude/agents,claude/hooks,sentinel,test,docs}
touch data/claude-code-setup/.gitkeep   # placeholder temporal para versionar dirs vacíos
find data -type f | sort
```
Expected: sin `.jpeg`; existe el árbol `data/claude-code-setup/...`.

- [ ] **Step 4: Verificar que el kit es versionable**

Run:
```bash
git check-ignore -v data/claude-code-setup/.gitkeep || echo "NOT ignored (correcto)"
git status --short | grep -c 'data/claude-code-setup' || true
```
Expected: `.gitkeep` NO ignorado.

- [ ] **Step 5: Commit**

```bash
git add .gitignore data/claude-code-setup/.gitkeep
git commit -m "chore(kit): scaffold data/claude-code-setup and narrow .gitignore

Retira las capturas de WhatsApp y permite versionar el kit transferible."
```

---

## Task 2: `scan-secrets.sh` con TDD (gate de seguridad)

**Files:**
- Create: `data/claude-code-setup/test/test_scan_secrets.sh`
- Create: `data/claude-code-setup/scan-secrets.sh`

**Interfaces:**
- Produces: `scan-secrets.sh [DIR]` → exit 0 (PASS) si no hay secretos/PII; exit 1 (FAIL) + hallazgos si los hay. Consumido por `doctor.sh` y por la verificación final.

- [ ] **Step 1: Escribir el test que falla (RED)**

Create `data/claude-code-setup/test/test_scan_secrets.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCAN="$HERE/../scan-secrets.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
check() { if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 (got $1 want $2)"; fail=$((fail+1)); fi; }

# Caso limpio -> PASS (exit 0)
mkdir -p "$tmp/clean"
printf 'ANTHROPIC_API_KEY=your-key-here\nhome=%s/.claude\nmail: you@example.com\n' '$HOME' > "$tmp/clean/ok.txt"
set +e; bash "$SCAN" "$tmp/clean" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "0" "kit limpio pasa"

# Caso con clave -> FAIL (exit 1)
mkdir -p "$tmp/dirty"
printf 'key=sk-ant-api03-%s\n' "$(printf 'A%.0s' {1..40})" > "$tmp/dirty/leak.txt"
set +e; bash "$SCAN" "$tmp/dirty" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "1" "clave sk- detectada"

# Caso con ruta /root/ -> FAIL
mkdir -p "$tmp/root"; printf 'path=/root/.claude/x\n' > "$tmp/root/leak.txt"
set +e; bash "$SCAN" "$tmp/root" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "1" "ruta /root detectada"

# Caso con email real (no example) -> FAIL
mkdir -p "$tmp/mail"; printf 'contact real.person@company.io\n' > "$tmp/mail/leak.txt"
set +e; bash "$SCAN" "$tmp/mail" >/dev/null 2>&1; rc=$?; set -e
check "$rc" "1" "email real detectado"

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Ejecutar el test → falla (script no existe)**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup/data/claude-code-setup
bash test/test_scan_secrets.sh; echo "rc=$?"
```
Expected: FAIL (scan-secrets.sh no existe todavía; los `bash "$SCAN"` devuelven 127, los checks no cuadran).

- [ ] **Step 3: Implementar `scan-secrets.sh` (GREEN)**

Create `data/claude-code-setup/scan-secrets.sh`:
```bash
#!/usr/bin/env bash
# scan-secrets.sh — Gate determinista de secretos/PII sobre el kit.
# Uso: scan-secrets.sh [DIR]   (default: carpeta del propio script)
# Exit 0 = limpio (PASS); 1 = hallazgos (FAIL).
set -euo pipefail
TARGET="${1:-$(cd "$(dirname "$0")" && pwd)}"
SELF="$(basename "$0")"

# Patrones de VALOR (no de nombre). Los nombres de variables (ANTHROPIC_API_KEY) son válidos.
PATTERNS=(
  'sk-[A-Za-z0-9_-]{20,}'
  'pplx-[A-Za-z0-9]{20,}'
  'gh[oprsu]_[A-Za-z0-9]{20,}'
  'AKIA[0-9A-Z]{16}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY'
  '/root/'
)
found=0
report() { echo "LEAK: $1"; found=1; }

while IFS= read -r -d '' f; do
  base="$(basename "$f")"
  # El propio escáner y su test documentan patrones: se excluyen.
  [ "$base" = "$SELF" ] && continue
  [ "$base" = "test_scan_secrets.sh" ] && continue
  for p in "${PATTERNS[@]}"; do
    if grep -InE "$p" "$f" >/dev/null 2>&1; then
      report "patrón /$p/ en $f"; grep -InE "$p" "$f" | head -2
    fi
  done
  # Emails que no sean de ejemplo/noreply = PII.
  if grep -InoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" 2>/dev/null \
       | grep -viE '@example\.(com|org)|noreply@|you@example|manuelcozar55@gmail\.com' >/dev/null 2>&1; then
    report "email real en $f"
    grep -InoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" \
      | grep -viE '@example\.(com|org)|noreply@|you@example|manuelcozar55@gmail\.com' | head -2
  fi
done < <(find "$TARGET" -type f -not -path '*/.git/*' -print0)

if [ "$found" -ne 0 ]; then echo "FAIL: secretos/PII detectados en $TARGET"; exit 1; fi
echo "PASS: sin secretos/PII en $TARGET"
```
Note: `manuelcozar55@gmail.com` se permite (es la identidad pública del autor del repo); el email de trabajo `@fcirce.es` NO está en la allowlist, así que se detecta si se cuela.

- [ ] **Step 4: Ejecutar el test → verde**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup/data/claude-code-setup
chmod +x scan-secrets.sh test/test_scan_secrets.sh
bash test/test_scan_secrets.sh; echo "rc=$?"
```
Expected: `4 passed, 0 failed`, rc=0.

- [ ] **Step 5: Commit**

```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
git add data/claude-code-setup/scan-secrets.sh data/claude-code-setup/test/test_scan_secrets.sh
git commit -m "feat(kit): add scan-secrets gate with TDD (4/4 green)"
```

---

## Task 3: Extracción saneada de `claude/`, `sentinel/`, `.env.example`, `requirements-tools.txt`

**Files:**
- Create: `data/claude-code-setup/claude/CLAUDE.md`, `claude/settings.json`, `claude/sentinel-allowlist.json`, `claude/agents/*.md`, `claude/hooks/*`
- Create: `data/claude-code-setup/sentinel/sentinel_preflight.py`
- Create: `data/claude-code-setup/.env.example`, `data/claude-code-setup/requirements-tools.txt`

**Interfaces:**
- Consumes: ficheros reales en `~/.claude`, `/root/sentinel`, `~/.venvs/tools` (lectura; algunas pueden requerir aprobación del clasificador).
- Produces: capa saneada del kit, que DEBE pasar `scan-secrets.sh`.

**Reglas de saneado (aplicar a cada fichero copiado):**
- `/root` → `$HOME` (y rutas de `~/.claude` → `$CLAUDE_HOME`).
- Email `usuario@ejemplo.invalid` → `you@example.com`.
- Cualquier valor bajo `.env` de `settings.json` que parezca secreto → `"${NOMBRE_VAR}"` (placeholder), y documentar el nombre en `.env.example`.
- Dominios personales en `sentinel-allowlist.json` → `example.com`/`api.example.com`.

- [ ] **Step 1: Copiar y sanear `CLAUDE.md`**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
sed -e 's#/root/#$HOME/#g' -e 's#mcozar@fcirce\.es#you@example.com#g' \
    ~/.claude/CLAUDE.md > data/claude-code-setup/claude/CLAUDE.md
grep -nE '/root/|fcirce' data/claude-code-setup/claude/CLAUDE.md || echo "sanitized ok"
```
Expected: `sanitized ok` (sin `/root/` ni `fcirce`).

- [ ] **Step 2: Copiar y sanear `settings.json`** (leer con cuidado; puede requerir aprobación)

Procedimiento (ejecútalo, no es placeholder):
1. Leer `~/.claude/settings.json`.
2. Copiar tal cual PERO: (a) en `.env`, sustituir cualquier valor con pinta de secreto (claves, tokens) por el placeholder `"${CLAVE}"`; conservar valores no sensibles. (b) sustituir rutas `/root/...` por `$HOME/...` en los `command` de hooks. (c) Mantener la estructura de `hooks`, `permissions`, `model`, `statusLine`.
3. Los `command` de hooks que apuntan a `/root/.venvs/tools/bin/python3` → `$HOME/.venvs/tools/bin/python3`; los de `/root/.claude/hooks/*` → `$HOME/.claude/hooks/*`; el de `/root/sentinel/sentinel_preflight.py` → `$HOME/.claude/sentinel/sentinel_preflight.py` (el kit instala Sentinel dentro de `$CLAUDE_HOME/sentinel`).

Run (validación):
```bash
jq empty data/claude-code-setup/claude/settings.json && echo "JSON válido"
grep -nE '/root/|sk-|pplx-|gho_' data/claude-code-setup/claude/settings.json || echo "sanitized ok"
```
Expected: JSON válido; `sanitized ok`.

- [ ] **Step 3: Copiar los 8 agentes (portables, sin saneo salvo rutas)**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
for a in ~/.claude/agents/*.md; do
  sed -e 's#/root/#$HOME/#g' -e 's#mcozar@fcirce\.es#you@example.com#g' "$a" \
    > "data/claude-code-setup/claude/agents/$(basename "$a")"
done
ls data/claude-code-setup/claude/agents/ | wc -l   # 8
```
Expected: 8 ficheros.

- [ ] **Step 4: Copiar y sanear los hooks portables**

Copia estos hooks (portables) aplicando `s#/root/#$HOME/#g`: `block-dangerous-commands.sh`, `branch-guard.sh`, `destructive-guard.sh`, `secret-guard.sh`, `session-start.sh`, `pre-compact.sh`, `stop-session-summary.sh`, `smart_approve.py`. (NO copiar `narthex-post-mcp.py` si contiene rutas/tokens específicos; si lo copias, sanéalo igual.)
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
for h in block-dangerous-commands.sh branch-guard.sh destructive-guard.sh secret-guard.sh session-start.sh pre-compact.sh stop-session-summary.sh smart_approve.py; do
  sed 's#/root/#$HOME/#g' "$HOME/.claude/hooks/$h" > "data/claude-code-setup/claude/hooks/$h"
done
chmod +x data/claude-code-setup/claude/hooks/*.sh
ls data/claude-code-setup/claude/hooks/
```

- [ ] **Step 5: Copiar y sanear Sentinel + allowlist**

```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
sed 's#/root/#$HOME/#g' /root/sentinel/sentinel_preflight.py > data/claude-code-setup/sentinel/sentinel_preflight.py
# allowlist: sanear dominios personales a example.com (revisar contenido y reemplazar)
sed -e 's#/root/#$HOME/#g' ~/.claude/sentinel-allowlist.json > data/claude-code-setup/claude/sentinel-allowlist.json
jq empty data/claude-code-setup/claude/sentinel-allowlist.json && echo "allowlist JSON ok"
```
Revisa manualmente el allowlist: si hay dominios personales/privados, sustitúyelos por `example.com`. Si Sentinel tiene ficheros de soporte (imports locales), cópialos igual saneados.

- [ ] **Step 6: `.env.example` y `requirements-tools.txt`**

`.env.example` (los nombres de variable reales del setup; SIN valores):
```bash
cat > data/claude-code-setup/.env.example <<'EOF'
# Copia a .env y rellena. NUNCA subas .env al repo.
ANTHROPIC_API_KEY=your-anthropic-key
PERPLEXITY_API_KEY=your-perplexity-key
LANGSMITH_API_KEY=your-langsmith-key
LANGSMITH_TRACING=false
EOF
```
`requirements-tools.txt` (CLI curado, no el stack ML). Deriva de `~/.venvs/tools/bin` los CLIs realmente usados por el setup:
```bash
cat > data/claude-code-setup/requirements-tools.txt <<'EOF'
# CLIs del venv de tools (~/.venvs/tools). Instala con:
#   python3 -m venv ~/.venvs/tools && ~/.venvs/tools/bin/pip install -r requirements-tools.txt
markitdown[all]
ast-grep-cli
basedpyright
ruff
EOF
```
(Ajusta la lista a los CLIs que el CLAUDE.md/decks referencian; NO incluir torch/cuda/azure.)

- [ ] **Step 7: GATE — el material saneado no tiene secretos**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup/data/claude-code-setup
bash scan-secrets.sh .; echo "rc=$?"
```
Expected: `PASS`, rc=0. Si FAIL, sanear el fichero señalado y repetir (bucle de corrección).

- [ ] **Step 8: Commit**

```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
rm -f data/claude-code-setup/.gitkeep
git add data/claude-code-setup/claude data/claude-code-setup/sentinel data/claude-code-setup/.env.example data/claude-code-setup/requirements-tools.txt
git commit -m "feat(kit): sanitized claude/, sentinel/, env example and tools reqs (scan PASS)"
```

---

## Task 4: `install.sh` con TDD (idempotente, con backup)

**Files:**
- Create: `data/claude-code-setup/test/test_install.sh`
- Create: `data/claude-code-setup/install.sh`

**Interfaces:**
- Produces: `CLAUDE_HOME=/ruta bash install.sh` instala `claude/*` y `sentinel/*` en `$CLAUDE_HOME` (default `$HOME/.claude`), con backup timestamped de lo que fuese a pisar, idempotente. No instala terceros (imprime instrucciones).

- [ ] **Step 1: Test que falla (RED)**

Create `data/claude-code-setup/test/test_install.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

export CLAUDE_HOME="$tmp/dot"
bash "$KIT/install.sh" >/dev/null 2>&1
ck "$([ -f "$CLAUDE_HOME/CLAUDE.md" ] && echo y)" "y" "instala CLAUDE.md"
ck "$([ -f "$CLAUDE_HOME/settings.json" ] && echo y)" "y" "instala settings.json"
ck "$([ -x "$CLAUDE_HOME/hooks/branch-guard.sh" ] && echo y)" "y" "hook ejecutable"
ck "$([ -f "$CLAUDE_HOME/sentinel/sentinel_preflight.py" ] && echo y)" "y" "instala sentinel"

# Idempotencia + backup: modifica un fichero, reinstala, debe backupear y no romper
echo "MOD" >> "$CLAUDE_HOME/CLAUDE.md"
bash "$KIT/install.sh" >/dev/null 2>&1
ck "$(ls "$CLAUDE_HOME"/backups/*/CLAUDE.md 2>/dev/null | wc -l | tr -d ' ')" "1" "backup creado al reinstalar"
ck "$?" "0" "reinstalar no falla"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
```

- [ ] **Step 2: Ejecutar → falla**

Run: `bash data/claude-code-setup/test/test_install.sh; echo rc=$?` → Expected: FAIL (no existe install.sh).

- [ ] **Step 3: Implementar `install.sh` (GREEN)**

Create `data/claude-code-setup/install.sh`:
```bash
#!/usr/bin/env bash
# install.sh — Instala el kit saneado en CLAUDE_HOME (idempotente, con backup).
# Uso: [CLAUDE_HOME=$HOME/.claude] bash install.sh
set -euo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ 2>/dev/null || echo backup)"
BK="$CLAUDE_HOME/backups/$STAMP"

echo "==> Instalando en $CLAUDE_HOME"
mkdir -p "$CLAUDE_HOME/hooks" "$CLAUDE_HOME/agents" "$CLAUDE_HOME/sentinel"

install_file() {  # src dst
  local src="$1" dst="$2"
  if [ -f "$dst" ] && ! cmp -s "$src" "$dst"; then
    mkdir -p "$(dirname "$BK/${dst#$CLAUDE_HOME/}")"
    cp -p "$dst" "$BK/${dst#$CLAUDE_HOME/}"
    echo "   backup: ${dst#$CLAUDE_HOME/}"
  fi
  cp -p "$src" "$dst"
}

install_file "$KIT/claude/CLAUDE.md"            "$CLAUDE_HOME/CLAUDE.md"
install_file "$KIT/claude/settings.json"        "$CLAUDE_HOME/settings.json"
install_file "$KIT/claude/sentinel-allowlist.json" "$CLAUDE_HOME/sentinel-allowlist.json"
for f in "$KIT"/claude/agents/*; do [ -e "$f" ] && install_file "$f" "$CLAUDE_HOME/agents/$(basename "$f")"; done
for f in "$KIT"/claude/hooks/*;  do [ -e "$f" ] && install_file "$f" "$CLAUDE_HOME/hooks/$(basename "$f")"; done
for f in "$KIT"/sentinel/*;      do [ -e "$f" ] && install_file "$f" "$CLAUDE_HOME/sentinel/$(basename "$f")"; done
chmod +x "$CLAUDE_HOME"/hooks/*.sh 2>/dev/null || true

echo "==> Config instalada. Terceros (ver docs/): superpowers, Headroom, agent-browser, venv de tools."
echo "==> Rellena tus claves:  cp $KIT/.env.example \$HOME/.claude/.env  &&  editar"
echo "==> Verifica:            bash $KIT/doctor.sh"
```

- [ ] **Step 4: Ejecutar test → verde**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup/data/claude-code-setup
chmod +x install.sh test/test_install.sh
bash test/test_install.sh; echo rc=$?
```
Expected: `6 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
git add data/claude-code-setup/install.sh data/claude-code-setup/test/test_install.sh
git commit -m "feat(kit): idempotent install.sh with backup (TDD 6/6 green)"
```

---

## Task 5: `doctor.sh` con TDD (health-check con evidencia)

**Files:**
- Create: `data/claude-code-setup/test/test_doctor.sh`
- Create: `data/claude-code-setup/doctor.sh`

**Interfaces:**
- Produces: `CLAUDE_HOME=/ruta bash doctor.sh` → informe PASS/WARN/FAIL por componente; exit 0 solo si 0 FAIL. Reusa `scan-secrets.sh`.

- [ ] **Step 1: Test que falla (RED)**

Create `data/claude-code-setup/test/test_doctor.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

export CLAUDE_HOME="$tmp/dot"
bash "$KIT/install.sh" >/dev/null 2>&1
set +e; bash "$KIT/doctor.sh" >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "0" "doctor PASS sobre instalación limpia"

# Rompe un hook referenciado -> FAIL
rm -f "$CLAUDE_HOME/hooks/branch-guard.sh"
set +e; bash "$KIT/doctor.sh" >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "1" "doctor FAIL con hook ausente"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
```

- [ ] **Step 2: Ejecutar → falla** (`bash test/test_doctor.sh` → FAIL).

- [ ] **Step 3: Implementar `doctor.sh` (GREEN)**

Create `data/claude-code-setup/doctor.sh`:
```bash
#!/usr/bin/env bash
# doctor.sh — Verifica una instalación del kit. Evidencia por componente.
# Uso: [CLAUDE_HOME=$HOME/.claude] bash doctor.sh
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
fails=0
pass(){ echo "PASS · $1"; }
warn(){ echo "WARN · $1"; }
fail(){ echo "FAIL · $1"; fails=$((fails+1)); }

echo "== doctor: CLAUDE_HOME=$CLAUDE_HOME =="

# 1. settings.json válido
if [ -f "$CLAUDE_HOME/settings.json" ] && jq empty "$CLAUDE_HOME/settings.json" 2>/dev/null; then
  pass "settings.json válido  (fuente: jq empty)"
else
  fail "settings.json ausente o inválido"
fi

# 2. hooks referenciados existen y son ejecutables
if [ -f "$CLAUDE_HOME/settings.json" ]; then
  refs="$(jq -r '.hooks // {} | .. | .command? // empty' "$CLAUDE_HOME/settings.json" 2>/dev/null \
          | grep -oE '\$HOME/\.claude/hooks/[^" ]+|\$HOME/\.claude/sentinel/[^" ]+' | sort -u)"
  miss=0
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    path="${r/\$HOME/$HOME}"; path="${path/$HOME\/.claude/$CLAUDE_HOME}"
    [ -e "$path" ] || { fail "hook/ref no encontrado: $r"; miss=1; }
  done <<< "$refs"
  [ "$miss" -eq 0 ] && pass "hooks referenciados presentes  (fuente: jq .hooks + test -e)"
fi

# 3. agentes
n=$(ls "$CLAUDE_HOME"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
[ "$n" -ge 1 ] && pass "agentes instalados: $n  (fuente: ls agents/*.md)" || warn "sin agentes"

# 4. venv de tools (opcional -> WARN)
if [ -x "$HOME/.venvs/tools/bin/python3" ]; then pass "venv tools presente"; else warn "venv tools ausente (opcional; ver docs/02-install.md)"; fi

# 5. Headroom (opcional -> WARN)
if command -v rtk >/dev/null 2>&1; then pass "Headroom rtk presente"; else warn "Headroom no instalado (opcional; ver docs/03-headroom.md)"; fi

# 6. gate de secretos sobre el kit
if bash "$KIT/scan-secrets.sh" "$KIT" >/dev/null 2>&1; then pass "kit sin secretos  (fuente: scan-secrets.sh)"; else fail "scan-secrets detectó material sensible en el kit"; fi

echo "== $( [ "$fails" -eq 0 ] && echo 'OK (0 FAIL)' || echo "$fails FAIL" ) =="
[ "$fails" -eq 0 ]
```

- [ ] **Step 4: Test → verde**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup/data/claude-code-setup
chmod +x doctor.sh test/test_doctor.sh
bash test/test_doctor.sh; echo rc=$?
```
Expected: `2 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
git add data/claude-code-setup/doctor.sh data/claude-code-setup/test/test_doctor.sh
git commit -m "feat(kit): doctor.sh health-check with evidence (TDD 2/2 green)"
```

---

## Task 6: `docs/` (7 documentos)

**Files:**
- Create: `data/claude-code-setup/docs/{01-overview,02-install,03-headroom,04-superpowers,05-security,06-routine,07-verify}.md`

**Interfaces:**
- Produces: el conocimiento transferible. Español, tono experto-práctico (estilo del autor). Terceros con comandos reales, no binarios.

Contenido requerido por documento (prosa real, no placeholders):

- [ ] **Step 1: `01-overview.md`** — El mapa. Modelo Karpathy (LLM=CPU, contexto=RAM, spec=fuente de verdad). Los 10 pilares agrupados (motor/capacidades/confianza). Loop engineering (design the loop, no el prompt). Cómo encaja cada pieza real: superpowers (método/loop), Sentinel (barreras), Headroom (contexto/coste), venv (herramientas), tiering (opus/sonnet/haiku). Diagrama mermaid mapa→territorio.

- [ ] **Step 2: `02-install.md`** — Prereqs (node ≥20 + pnpm, python3 + venv, gh, jq, git). Pasos: 1) clonar; 2) `bash install.sh`; 3) `cp .env.example ~/.claude/.env` y rellenar; 4) instalar venv de tools con `requirements-tools.txt`; 5) instalar terceros (remite a 03/04); 6) `bash doctor.sh`. Comandos exactos.

- [ ] **Step 3: `03-headroom.md`** — Qué es (router de contenido/proxy local que comprime resultados de tool antes del modelo; no resume con LLM). Instalación de Headroom/`rtk`, arranque del proxy local, y cómo se cablea el hook `rtk hook claude` en `settings.json` (PreToolUse Bash). Endpoint de salud `127.0.0.1:8787/readyz` (nota: Sentinel puede bloquear IP en crudo; usar `headroom_stats`). Sin DBs/savings.

- [ ] **Step 4: `04-superpowers.md`** — Plugin superpowers (marketplace + `enabledPlugins`), las 14 skills (leyes de hierro: skills-first, brainstorming, TDD, verify-before-completion), los 8 agentes con tiering (opus: orchestrator/strategist/planner; sonnet: deep-worker/reviewers; haiku: quick-checker), y agent-browser (instalación global, política de uso). Comandos de instalación.

- [ ] **Step 5: `05-security.md`** — Sentinel (PreToolUse, matcher vacío, DENY/ASK/WARN/ALLOW, fail-open y su trade-off consciente). Los guards (block-dangerous, branch-guard, destructive-guard, secret-guard, smart_approve). Manejo de secretos (`.env`, nunca al repo; `.env.example`). El gate `scan-secrets.sh`. Filosofía: barreras deterministas que acotan el blast radius.

- [ ] **Step 6: `06-routine.md`** — La rutina: tiering opus/sonnet/haiku por categoría; ping de las 6:00 (ancla la ventana rodante de 5h; aviso honesto: mecánica de suscripción, no garantía); `/compact` a mano vs autocompact al 75% (airbag, no plan A); opus[1m] solo cuando no cabe; git worktrees para aislar; handoffs por fichero. Plantilla OPCIONAL de cron/systemd para el ping (comentada, no se ejecuta sola).

- [ ] **Step 7: `07-verify.md`** — Cómo verificar: `scan-secrets.sh`, `install.sh` en `CLAUDE_HOME` temporal, `doctor.sh`, `test/*.sh`. La filosofía "cifra → fuente → comando": nada se da por bueno sin evidencia. Tabla de comprobaciones.

- [ ] **Step 8: Verificar y commit**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup/data/claude-code-setup
ls docs/ | wc -l                 # 7
bash scan-secrets.sh .; echo rc=$?   # PASS
grep -rnE '/root/|mcozar@fcirce' docs/ || echo "docs sanitized"
```
Expected: 7 docs; scan PASS; docs sanitized.
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
git add data/claude-code-setup/docs
git commit -m "docs(kit): overview, install, headroom, superpowers, security, routine, verify"
```

---

## Task 7: `README.md` del kit (estilo manuelcozar55)

**Files:**
- Create: `data/claude-code-setup/README.md`

**Interfaces:**
- Produces: portada del kit. Banner capsule-render, badges for-the-badge, quickstart (clonar → install → .env → doctor), tabla de qué incluye, mermaid, "Notas de experto", "Autor". Enlaza a `docs/`.

- [ ] **Step 1: Escribir el README** con secciones: Qué es · Quickstart (3 comandos) · Qué incluye (tabla) · Cómo funciona (mermaid instalar→diagnosticar→corregir) · Seguridad (gate) · Terceros (enlaces a docs) · Notas de experto (Karpathy/loop engineering) · Autor. Sin `/root/`, sin email real.

- [ ] **Step 2: Verificar y commit**

```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup/data/claude-code-setup
bash scan-secrets.sh .; echo rc=$?   # PASS
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
git add data/claude-code-setup/README.md
git commit -m "docs(kit): README with quickstart, mermaid and expert notes"
```

---

## Task 8: Verificación de integración end-to-end + reporte

**Files:**
- Modify: `docs/superpowers/specs/2026-07-25-claude-code-setup-kit-design.md` (marcar criterios de éxito cumplidos)

**Interfaces:**
- Consumes: el kit completo.

- [ ] **Step 1: Suite completa + instalación real en temporal**

Run:
```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup/data/claude-code-setup
echo "== tests =="; for t in test/*.sh; do echo "-- $t"; bash "$t" || exit 1; done
echo "== scan =="; bash scan-secrets.sh .
echo "== install+doctor en temporal =="; D=$(mktemp -d); CLAUDE_HOME="$D/dot" bash install.sh >/dev/null && CLAUDE_HOME="$D/dot" bash doctor.sh; rc=$?
echo "== reinstall idempotente =="; CLAUDE_HOME="$D/dot" bash install.sh >/dev/null && echo "reinstall ok"
rm -rf "$D"; echo "final rc=$rc"
```
Expected: todos los tests verdes; scan PASS; doctor 0 FAIL (WARN aceptables para terceros ausentes); reinstall ok.

- [ ] **Step 2: Verificación de criterios de éxito** (marca en el spec los 6 criterios con evidencia).

- [ ] **Step 3: Commit**

```bash
cd /mnt/c/Users/ManuelCozarBaranguan/Downloads/CC-Setup
git add docs/superpowers/specs/2026-07-25-claude-code-setup-kit-design.md
git commit -m "docs(spec): mark setup-kit success criteria met with evidence"
```

---

## Self-Review

**1. Cobertura del spec:** scan-secrets (T2) · claude/sentinel/env/reqs saneados (T3) · install (T4) · doctor (T5) · docs 7 (T6) · README (T7) · integración (T8) · scaffolding+gitignore+borrar imágenes (T1). Los 6 criterios de éxito → T8.

**2. Placeholders:** los 3 scripts y los 3 tests llevan código completo y ejecutable. Extracción = comandos concretos + reglas de saneado (no "TODO sanear"). Docs = contenido requerido específico por sección. Único trabajo dependiente de lectura en vivo: sanear `settings.json`/allowlist reales (procedimiento exacto dado; el gate protege la salida).

**3. Consistencia de nombres:** `CLAUDE_HOME` como contrato en install/doctor/tests; `scan-secrets.sh` reusado por doctor y verificación; rutas `$HOME/.claude/{hooks,sentinel}` coherentes entre settings saneado, install y doctor.

**4. Ambigüedad:** email permitido = `manuelcozar55@gmail.com` (identidad pública); `@fcirce.es` prohibido. Terceros documentados, no copiados. Objetivo bash Linux/WSL/macOS.
