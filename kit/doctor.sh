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

# 2c. hooks desplegados vs. los del kit -- y, si difieren, POR QUE difieren.
#     Un WARN indiscriminado colapsa dos cosas opuestas: "el usuario lo personalizo"
#     (suyo, correcto) y "la instalacion se quedo atras" (fallo). El discriminador es
#     el sha del blob: si el contenido instalado aparece en el historial de git del kit
#     para ESA ruta, ese fichero ES una version antigua del kit. Nueve huecos de guardas
#     cerrados en 69db95d siguieron abiertos en la maquina con doctor saliendo 0.
REPO="$(cd "$KIT/.." && pwd)"
tiene_git=n
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  tiene_git=y
fi

rancios=0; rancios_lista=""
propios=0; propios_lista=""
for src in "$KIT"/claude/hooks/*; do
  [ -f "$src" ] || continue
  nombre="$(basename "$src")"
  dst="$CLAUDE_HOME/hooks/$nombre"
  [ -f "$dst" ] || continue
  cmp -s "$src" "$dst" && continue

  # git rev-list HEAD solo ve lo que el historial disponible trae: un checkout
  # superficial o una rama con squash/rebase pueden no traer la version vieja
  # aunque exista. Eso empuja hacia "propio" (WARN) un caso que en realidad es
  # "rancio" (FAIL) -- se equivoca del lado seguro, y es inherente a como git
  # ve el historial, no algo que este check pueda arreglar por si solo.
  encontrado=n
  if [ "$tiene_git" = y ]; then
    blob="$(git -C "$REPO" hash-object "$dst" 2>/dev/null)"
    if [ -n "$blob" ]; then
      for c in $(git -C "$REPO" rev-list HEAD -- "kit/claude/hooks/$nombre" 2>/dev/null); do
        if [ "$(git -C "$REPO" rev-parse "$c:kit/claude/hooks/$nombre" 2>/dev/null)" = "$blob" ]; then
          encontrado=y; break
        fi
      done
    fi
  fi

  if [ "$encontrado" = y ]; then
    rancios=$((rancios + 1)); rancios_lista="$rancios_lista $nombre"
  else
    propios=$((propios + 1)); propios_lista="$propios_lista $nombre"
  fi
done

if [ "$rancios" -gt 0 ]; then
  fail "$rancios hook(s) desplegados son una version ANTIGUA del kit ($rancios_lista): la instalacion se quedo atras y las correcciones posteriores NO estan puestas. Reinstala: bash kit/install.sh  (fuente: el sha del blob instalado aparece en el historial de git del kit)"
elif [ "$propios" -gt 0 ]; then
  warn "$propios hook(s) desplegados difieren del kit y no coinciden con ninguna version historica ($propios_lista): personalizacion local. Portalos al kit si el cambio es bueno  (fuente: git hash-object contra rev-list)"
else
  pass "los hooks desplegados coinciden byte a byte con los del kit  (fuente: cmp -s por fichero)"
fi

# 2d. la skill 'harness' vive en dos copias sin dueno declarado. El kit NO instala
#     skills, asi que ninguna de las dos es "la del kit": es un fork sin origen,
#     divergente en ambas direcciones. Se avisa, no se falla: unificarla exige un
#     paso de redaccion de PII que todavia no existe (spec fase 3), y publicar la
#     copia mas completa sin ese paso seria peor que la divergencia.
skill_repo="$KIT/../.claude/skills/harness/SKILL.md"
skill_desp="$CLAUDE_HOME/skills/harness/SKILL.md"
if [ -f "$skill_repo" ] && [ -f "$skill_desp" ] && ! cmp -s "$skill_repo" "$skill_desp"; then
  n_repo="$(wc -l < "$skill_repo" | tr -d ' ')"
  n_desp="$(wc -l < "$skill_desp" | tr -d ' ')"
  warn "dos copias divergentes de la skill harness sin fuente unica: $skill_desp ($n_desp lineas) vs $skill_repo ($n_repo lineas)  (fuente: cmp -s)"
else
  pass "skill harness: sin fork detectable entre la copia del repo y la desplegada  (fuente: cmp -s)"
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

# 2d. statusLine: si settings.json la declara, su comando tiene que resolverse.
# Claude Code no avisa de nada aqui: medido en 2.1.258, un exit != 0 o un stdout vacio dejan
# la barra EN BLANCO en silencio y stderr se descarta. Ya paso: una instalacion escribio
# settings.json entero con cp -p y se llevo la clave statusLine por delante; 15 minutos con
# la barra vacia y ni una linea de aviso en ningun sitio.
# Del string del comando se extrae el ejecutable REAL: en "bash ~/.claude/statusline.sh" lo
# que puede faltar es el script, no bash.
# Si no hay statusLine este check calla: la mayoria de instalaciones del kit no la usa y eso
# no es un defecto. Ejecutarla es solo WARN (con timeout) porque el fallo puede ser del
# entorno de doctor y no de la barra.
sl_cmd="$(jq -r '.statusLine.command // empty' "$CLAUDE_HOME/settings.json" 2>/dev/null)"
if [ -n "$sl_cmd" ]; then
  read -r -a sl_argv <<< "$sl_cmd"
  sl_bin="${sl_argv[0]}"; sl_directo=1
  case "$(basename "$sl_bin")" in
    bash|sh|dash|zsh|python|python3|node)
      for w in "${sl_argv[@]:1}"; do
        case "$w" in -*) ;; *) sl_bin="$w"; sl_directo=0; break ;; esac
      done ;;
  esac
  sl_bin="${sl_bin/#\~/$HOME}"; sl_bin="${sl_bin/\$HOME/$HOME}"
  [[ "$sl_bin" != */* ]] && sl_bin="$(command -v "$sl_bin" 2>/dev/null || echo "$sl_bin")"
  if [ ! -f "$sl_bin" ]; then
    fail "statusLine declarada en settings.json pero su comando no se resuelve: '$sl_cmd' apunta a $sl_bin, que no existe. Claude Code deja la barra en blanco SIN avisar: restaura el fichero o quita la clave statusLine"
  elif [ "$sl_directo" -eq 1 ] && [ ! -x "$sl_bin" ]; then
    fail "statusLine declarada pero $sl_bin no es ejecutable: la barra sale en blanco sin aviso. Corrigelo con: chmod +x \"$sl_bin\""
  else
    sl_out="$(printf '{"hook_event_name":"Status","session_id":"doctor","cwd":"%s","model":{"display_name":"doctor"},"workspace":{"current_dir":"%s","project_dir":"%s"}}' \
              "$PWD" "$PWD" "$PWD" | timeout 5 bash -c "$sl_cmd" 2>/dev/null)"
    sl_rc=$?
    if [ "$sl_rc" -ne 0 ]; then
      warn "statusLine: '$sl_cmd' salio con codigo $sl_rc sobre un payload JSON de prueba; con ese codigo Claude Code dejaria la barra en blanco sin avisar"
    elif [ -z "$sl_out" ]; then
      warn "statusLine: '$sl_cmd' no imprimio nada sobre un payload JSON de prueba; stdout vacio = barra en blanco, y Claude Code no lo reporta"
    else
      pass "statusLine resuelve a $sl_bin y responde  (fuente: ejecucion con payload JSON minimo y timeout 5)"
    fi
  fi
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
# La URL que se sondea sale de la MISMA enumeracion de ambitos que cuenta el 5e, y en el
# orden de precedencia real de Claude Code (proyecto local -> proyecto -> usuario). Antes se
# leia solo $CLAUDE_HOME/settings.json y el entorno, y eso reproducia el fallo en abierto que
# describe el parrafo de arriba: con la URL declarada unicamente en
# <proyecto>/.claude/settings.local.json y el puerto muerto, este check no sondeaba nada y
# decia "API directa" mientras el 5e, unas lineas mas abajo, declaraba el enrutado. Dos PASS
# que se contradicen en la misma salida y rc=0, con Claude Code incapaz de hablar con la API.
# managed-settings.json y --settings mandan por encima de todo eso, pero el primero vive
# fuera de CLAUDE_HOME y el segundo es un flag de arranque: doctor no los puede ver.
#
# Se mira el ambito de PROYECTO y no solo el de usuario porque el proyecto es justo donde
# aparecen las fuentes de mas: `headroom wrap` escribe la URL en
# <cwd>/.claude/settings.local.json (wrap.py:1505), no en settings.json. Medido en esta
# maquina: dos fuentes vivas, una de usuario y otra en $CLAUDE_HOME/.claude/, y la version
# anterior de este check solo veia la primera -- acertaba por accidente.
# Los candidatos se enumeran, no se barren: un find por el home es lento y cuenta como
# fuente ficheros que Claude Code no carga (por ejemplo $CLAUDE_HOME/backups/**). La lista
# de proyectos es la que ya mantiene Claude Code en ~/.claude.json, para no inventar una
# fuente de verdad nueva. Se deduplica por ruta porque los ambitos se solapan: con $HOME
# declarado como proyecto, $HOME/.claude/settings.local.json es el MISMO fichero que el de
# usuario, y contarlo dos veces seria un FAIL falso.
rutas_declaradas=0; rutas_detalle=""; rutas_url=""; rutas_origen=""
enumerar_enrutado() {
  local candidatos="" vistas="" d f linea
  while IFS= read -r d; do
    [ -n "$d" ] || continue
    candidatos="$candidatos
$d/.claude/settings.local.json
$d/.claude/settings.json"
  done <<< "$PWD
$CLAUDE_HOME
$(jq -r '.projects // {} | keys[]' "$HOME/.claude.json" 2>/dev/null)"
  candidatos="$candidatos
$CLAUDE_HOME/settings.local.json
$CLAUDE_HOME/settings.json"
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case " $vistas " in *" $f "*) continue ;; esac
    vistas="$vistas $f"
    if [ -f "$f" ] && jq -e '.env.ANTHROPIC_BASE_URL' "$f" >/dev/null 2>&1; then
      rutas_declaradas=$((rutas_declaradas + 1))
      linea="$(grep -n ANTHROPIC_BASE_URL "$f" | head -1 | cut -d: -f1)"
      rutas_detalle="$rutas_detalle $f:${linea:-?}"
      if [ -z "$rutas_url" ]; then
        rutas_url="$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$f" 2>/dev/null)"
        rutas_origen="$f"
      fi
    fi
  done <<< "$candidatos"
}
enumerar_enrutado
base_url="$rutas_url"; base_src="$rutas_origen"
if [ -z "$base_url" ] && [ -n "${ANTHROPIC_BASE_URL:-}" ]; then
  base_url="$ANTHROPIC_BASE_URL"; base_src="tu entorno"
fi
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
    fail "API enrutada a $base_url por $base_src pero ahi no contesta nadie: Claude Code no podra conectar. Arranca el proxy (docs/03-headroom.md) o quita ANTHROPIC_BASE_URL de $base_src"
  fi
elif [ "$rutas_declaradas" -gt 0 ]; then
  # Declarado con la cadena vacia: no enruta a ninguna parte, pero decir "API directa"
  # seria contradecir al 5e en la misma salida, que es justo el fallo que se corrige aqui.
  warn "ANTHROPIC_BASE_URL declarado en$rutas_detalle con valor vacio: no enruta a ninguna parte y deja la clave puesta para quien la lea despues. Quitala"
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
#
# Se cuenta sobre la enumeracion del check 5 (enumerar_enrutado, arriba): la misma lista que
# decide QUE URL se sondea, para que contar las fuentes y probarlas no puedan discrepar.
if [ "$rutas_declaradas" -gt 1 ]; then
  fail "ANTHROPIC_BASE_URL declarado en $rutas_declaradas ficheros ($rutas_detalle): el enrutado deja de ser una decision unica y sobrevive a que lo quites de uno. Deja solo settings.json"
elif [ "$rutas_declaradas" -eq 1 ]; then
  pass "enrutado declarado en un solo sitio:$rutas_detalle  (fuente: jq sobre settings*.json de usuario, del cwd y de los proyectos de ~/.claude.json)"
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
