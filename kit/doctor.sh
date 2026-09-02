#!/usr/bin/env bash
# doctor.sh — Verifica una instalación del kit. Evidencia por componente.
# Uso: [CLAUDE_HOME=$HOME/.claude] bash doctor.sh
set -uo pipefail
KIT="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL · jq no instalado (requerido por doctor; ver docs/02-install.md)"
  exit 1
fi
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
  # shellcheck disable=SC2016 # patron literal para grep -oE, no interpolacion de shell
  refs="$(jq -r '.hooks // {} | .. | .command? // empty' "$CLAUDE_HOME/settings.json" 2>/dev/null \
          | grep -oE '\$HOME/\.claude/hooks/[^" ]+|\$HOME/\.claude/sentinel/[^" ]+' | sort -u)"
  miss=0
  while IFS= read -r r; do
    [ -z "$r" ] && continue
    path="${r/\$HOME/$HOME}"; path="${path/$HOME\/.claude/$CLAUDE_HOME}"
    if [ ! -e "$path" ]; then
      fail "hook/ref no encontrado: $r"; miss=1
    elif [[ "$path" == *.sh && ! -x "$path" ]]; then
      fail "hook no ejecutable: $r"; miss=1
    fi
  done <<< "$refs"
  [ "$miss" -eq 0 ] && pass "hooks referenciados presentes y ejecutables  (fuente: jq .hooks + test -e/-x)"
fi

# 2c. Deriva entre lo que el kit trae y lo desplegado. Es WARN y no FAIL: personalizar un
# hook es legitimo. Pero si divergen y no lo sabes, el kit deja de reproducir tu maquina, y
# eso ya paso: dos guards llevaban meses distintos entre el kit y su copia de origen, con la
# version endurecida en un lado y la antigua en el otro, y nadie lo noto.
derivados=0; derivados_lista=""
for src in "$KIT"/claude/hooks/*; do
  [ -f "$src" ] || continue
  nombre="$(basename "$src")"
  dst="$CLAUDE_HOME/hooks/$nombre"
  [ -f "$dst" ] || continue
  if ! cmp -s "$src" "$dst"; then
    derivados=$((derivados + 1)); derivados_lista="$derivados_lista $nombre"
  fi
done
if [ "$derivados" -gt 0 ]; then
  warn "$derivados hook(s) desplegados difieren de los del kit ($derivados_lista): reinstala para alinearlos, o portalos al kit si el cambio es bueno"
else
  pass "los hooks desplegados coinciden byte a byte con los del kit  (fuente: cmp -s por fichero)"
fi

# 2b. capa de IOCs de Sentinel (opcional -> WARN)
# Se comprueban las MISMAS rutas que busca el hook y en su orden (sentinel_preflight.py:
# <dir del script>/iocs.json -> $CLAUDE_HOME/hooks/iocs.json -> skills/mcp-sentinel/...).
# Antes solo se miraba la segunda, asi que en una instalacion donde sentinel vive FUERA de
# CLAUDE_HOME el WARN era falso: la capa estaba activa con 31 patrones de ruta, 12 de comando
# y 30 de red, y doctor decia que no. Un aviso falso gasta la credibilidad de los verdaderos.
ioc_file=""
ioc_pre="$(jq -r '.hooks // {} | .. | .command? // empty' "$CLAUDE_HOME/settings.json" 2>/dev/null \
           | grep -oE '[^ ]*sentinel_preflight\.py' | head -1)"
ioc_pre="${ioc_pre/\$HOME/$HOME}"
ioc_dir=""
[ -n "$ioc_pre" ] && ioc_dir="$(dirname "$ioc_pre")"
for c in "${ioc_dir:+$ioc_dir/iocs.json}" "$CLAUDE_HOME/sentinel/iocs.json" \
         "$CLAUDE_HOME/hooks/iocs.json" "$CLAUDE_HOME/skills/mcp-sentinel/references/iocs.json"; do
  [ -n "$c" ] && [ -f "$c" ] && { ioc_file="$c"; break; }
done
if [ -n "$ioc_file" ]; then
  pass "Sentinel IOC layer activa: $ioc_file  (fuente: mismo orden de busqueda que el hook)"
else
  warn "Sentinel IOC layer inactiva: falta iocs.json (opcional; ver docs/05-security.md). Los guards de Bash siguen activos."
fi

# 3. agentes
n=$(find "$CLAUDE_HOME/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
if [ "$n" -ge 1 ]; then
  pass "agentes instalados: $n  (fuente: find agents/*.md)"
else
  warn "sin agentes"
fi

# 4. venv de tools (opcional -> WARN)
if [ -x "$HOME/.venvs/tools/bin/python3" ]; then pass "venv tools presente"; else warn "venv tools ausente (opcional; ver docs/02-install.md)"; fi

# 4b. interprete para los hooks Python (smart_approve, sentinel_preflight).
# No es FAIL: optional-hook.sh los convierte en no-op si no hay interprete, y el
# resto de la cadena (los guards de bash) sigue protegiendo. Pero conviene
# saberlo, porque son dos capas menos.
if [ -x "$HOME/.venvs/tools/bin/python3" ] || command -v python3 >/dev/null 2>&1; then
  pass "interprete para hooks Python disponible  (fuente: venv o python3 del sistema)"
else
  warn "sin python3: smart_approve y el preflight de Sentinel quedan en no-op (los guards de bash siguen activos)"
fi

# 5. Enrutado de la API: si algo enruta a un proxy, ese proxy TIENE que contestar.
#
# Esto es un FAIL y no un WARN por una razon medida: este kit distribuia
# ANTHROPIC_BASE_URL=127.0.0.1:8787 en settings.json mientras declaraba Headroom
# como componente opcional de terceros. En una instalacion limpia el puerto
# estaba muerto, Claude Code no podia hablar con la API, y este doctor salia
# "OK (0 FAIL)" porque solo miraba si el binario existia. Un doctor que aprueba
# una instalacion inservible retira la sospecha justo donde hacia falta.
# Cubierto por kit/test/test_doctor_base_url.sh.
#
# Se consulta /readyz y no /health: /health es agregado y se pone en rojo si
# CUALQUIER subcomprobacion falla -- por ejemplo el backend semantico de
# compresion, que es legitimo no instalar (ver docs/03-headroom.md). /readyz
# responde a lo unico que decide aqui: puede atender trafico o no.
base_url="$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$CLAUDE_HOME/settings.json" 2>/dev/null)"
[ -z "$base_url" ] && base_url="${ANTHROPIC_BASE_URL:-}"
probe_url() { # $1 url -> 0 si algo contesta HTTP
  if command -v curl >/dev/null 2>&1; then
    curl -fsS -m 2 -o /dev/null "$1" 2>/dev/null && return 0
    # Un 4xx/5xx tambien prueba que hay un servidor escuchando.
    curl -sS -m 2 -o /dev/null -w '%{http_code}' "$1" 2>/dev/null | grep -qE '^[1-5][0-9][0-9]$' && return 0
    return 1
  fi
  python3 - "$1" <<'EOF' >/dev/null 2>&1
import sys, urllib.request, urllib.error
try:
    urllib.request.urlopen(sys.argv[1], timeout=2)
except urllib.error.HTTPError:
    pass
except Exception:
    sys.exit(1)
EOF
}
if [ -n "$base_url" ]; then
  if probe_url "${base_url%/}/readyz" || probe_url "${base_url%/}/health" || probe_url "$base_url"; then
    pass "API enrutada a $base_url y el proxy responde  (fuente: GET /readyz)"
  else
    fail "API enrutada a $base_url pero ahi no contesta nadie: Claude Code no podra conectar. Arranca el proxy (docs/03-headroom.md) o quita ANTHROPIC_BASE_URL de settings.json"
  fi
else
  pass "API directa a Anthropic: sin proxy en medio  (fuente: sin ANTHROPIC_BASE_URL)"
fi

# 5e. Una sola fuente de enrutado (pertenece al check 5; la numeracion de este bloque
# ya venia sin orden). Medido en una maquina real: ANTHROPIC_BASE_URL vivia
# en 5 settings.local.json de proyecto, cada uno con un hook `headroom wrap selfheal` que
# lo reponia en cada arranque, y ninguno declarado. Consecuencias: el enrutado dependia
# del cwd de la sesion (94 % del trabajo de un dia salio sin pasar por el proxy), y
# `headroom doctor` afirmaba "not routed" DENTRO de una sesion enrutada, porque solo mira
# settings.json. Dos fuentes es peor que ninguna: no se puede apagar lo que no se ve.
rutas_declaradas=0; rutas_detalle=""
for f in "$CLAUDE_HOME/settings.json" "$CLAUDE_HOME/settings.local.json"; do
  if [ -f "$f" ] && jq -e '.env.ANTHROPIC_BASE_URL' "$f" >/dev/null 2>&1; then
    rutas_declaradas=$((rutas_declaradas + 1))
    rutas_detalle="$rutas_detalle $(basename "$f")"
  fi
done
if [ "$rutas_declaradas" -gt 1 ]; then
  fail "ANTHROPIC_BASE_URL declarado en $rutas_declaradas ficheros ($rutas_detalle): el enrutado deja de ser una decision unica y sobrevive a que lo quites de uno. Deja solo settings.json"
elif [ "$rutas_declaradas" -eq 1 ]; then
  pass "enrutado declarado en un solo sitio:$rutas_detalle  (fuente: jq sobre settings.json y settings.local.json)"
fi

# 5a. Headroom (opcional -> WARN). `headroom` y `rtk` son DOS proyectos distintos
# (ver docs/03-headroom.md): el proxy HTTP en :8787 y el filtro de salida de CLI
# que ejecuta el hook `rtk hook claude`. Se comprueban por separado a propósito:
# con un solo `command -v rtk`, una instalación con rtk pero sin el proxy daba
# "Headroom presente" siendo falso, y al revés.
if command -v headroom >/dev/null 2>&1; then
  pass "Headroom (proxy) presente  (fuente: command -v headroom)"

  # El modo pesa mas que cualquier otro ajuste. `token` reescribe los turnos anteriores
  # e invalida el prefijo cacheado, que es de donde sale casi todo el ahorro. Medido en
  # una maquina real: el 95,4 % del input son lecturas de cache, asi que `token` tendria
  # que comprimir el 85 % del contexto solo para EMPATAR con `cache`, y comprime el 4,2 %
  # de media. No se confia en el default porque la herramienta se contradice sobre cual es.
  hr_unit="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/headroom-proxy.service"
  if [ -f "$hr_unit" ]; then
    if grep -qE '^ExecStart=.*--mode[ =]cache' "$hr_unit"; then
      pass "el proxy arranca en --mode cache  (fuente: ExecStart de headroom-proxy.service)"
    else
      fail "headroom-proxy.service no fija --mode cache: en modo token se invalida el prefijo cacheado y el coste sube en vez de bajar (ver docs/03-headroom.md)"
    fi
    if grep -qE '^ExecStart=.*(--budget|--log-messages)' "$hr_unit"; then
      fail "headroom-proxy.service arranca con --budget o --log-messages: el primero devuelve HTTP 200 con cuerpo vacio al agotarse (parece un fallo del cliente); el segundo escribe la conversacion entera en claro a disco"
    fi
  fi

  # --log-messages es opt-in y su propio --help avisa "may log sensitive data": guarda
  # request_messages, o sea la conversacion completa. Medido: 36 conversaciones (12 MB)
  # seguian en un fichero 0644 dos semanas despues de la sesion que las genero.
  hr_jsonl="$HOME/.headroom/logs/proxy.jsonl"
  if [ -f "$hr_jsonl" ] && grep -qm1 '"request_messages":[[:space:]]*\[' "$hr_jsonl" 2>/dev/null; then
    fail "$hr_jsonl guarda cuerpos de peticion (request_messages): conversaciones en claro en disco. Borra el fichero y no arranques el proxy con --log-messages"
  fi
  if [ -d "$HOME/.headroom" ]; then
    hr_perm="$(stat -c '%a' "$HOME/.headroom" 2>/dev/null || echo '')"
    case "$hr_perm" in
      700|750|'') : ;;
      *) warn "$HOME/.headroom tiene permisos $hr_perm: ahi vive material derivado de tus prompts (ccr_store.db, savings_events.jsonl). Corrigelo con: chmod 700 \"\$HOME/.headroom\"" ;;
    esac
  fi
else
  warn "Headroom (proxy) no instalado (opcional; ver docs/03-headroom.md)"
fi
if command -v rtk >/dev/null 2>&1; then
  pass "rtk (filtro de salida de CLI) presente  (fuente: command -v rtk)"
else
  warn "rtk no instalado: el hook 'rtk hook claude' de settings.json queda en no-op via optional-hook.sh (opcional; ver docs/03-headroom.md)"
fi

# 5b. gitleaks (opcional -> WARN): requerido solo para activar la Capa 2 de
# secretos (hooks/git/pre-commit); la Capa 1 (secret-guard.sh) funciona sin él.
gitleaks_bin=""
if command -v gitleaks >/dev/null 2>&1; then gitleaks_bin="gitleaks"
elif [ -x "$HOME/.local/bin/gitleaks" ]; then gitleaks_bin="$HOME/.local/bin/gitleaks"
fi
if [ -n "$gitleaks_bin" ]; then
  gitleaks_ver="$("$gitleaks_bin" version 2>/dev/null | tr -d '\n')"
  pass "gitleaks presente${gitleaks_ver:+ ($gitleaks_ver)}  (fuente: command -v gitleaks)"
else
  warn "gitleaks no instalado: la Capa 2 de secretos (pre-commit) no puede activarse (ver docs/05-security.md)"
fi

# 5c. marca persistente de checksum de gitleaks no coincidente (ver install.sh)
# install.sh nunca falla por esto (dependencia opcional), pero deja esta marca
# para que quien no vio la salida del instalador se entere igualmente.
if [ -f "$CLAUDE_HOME/.gitleaks-checksum-mismatch" ]; then
  fail "checksum de gitleaks no coincidio en una instalacion anterior: ver $CLAUDE_HOME/.gitleaks-checksum-mismatch (posible ataque a la cadena de suministro; ver CONTRIBUTING.md)"
fi

# 5d. Capa 2 de secretos: core.hooksPath en el repo actual (opcional -> WARN)
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  hooks_path="$(git config --get core.hooksPath 2>/dev/null || true)"
  if [ -n "$hooks_path" ]; then
    pass "Capa 2 activa en este repo: core.hooksPath=$hooks_path  (fuente: git config --get core.hooksPath)"
  else
    warn "Capa 2 de secretos no activada en este repo: core.hooksPath sin configurar (opt-in con: bash $KIT/install.sh --enable-secrets-layer2)"
  fi
else
  warn "no estas dentro de un repo git: no se puede comprobar la Capa 2 (core.hooksPath)"
fi

# 6. gate de secretos sobre el kit
if bash "$KIT/scan-secrets.sh" "$KIT" >/dev/null 2>&1; then pass "kit sin secretos  (fuente: scan-secrets.sh)"; else fail "scan-secrets detectó material sensible en el kit"; fi

echo "== $( [ "$fails" -eq 0 ] && echo 'OK (0 FAIL)' || echo "$fails FAIL" ) =="
[ "$fails" -eq 0 ]
