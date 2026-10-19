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
# 1b. disableAllHooks: true apaga todos los hooks, guards incluidos, aunque cada fichero este en su
# sitio: el resto de checks saldria en verde sobre un kit que no protege nada. install.sh lo respeta y avisa.
if jq -e '.disableAllHooks == true' "$CLAUDE_HOME/settings.json" >/dev/null 2>&1; then
  fail "settings.json tiene disableAllHooks: true: no corre ningun hook, tampoco los guards. Quita la clave"
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

# 2b0. CLIs del flujo de estado y plantilla. Sin bin/handoff, bin/oraculo o templates/nucleo.md el flujo v3
# no arranca: es FAIL. Que no esten en el PATH es WARN (se resuelve con una terminal nueva o el enlace).
for cli in handoff oraculo; do
  if [ -x "$CLAUDE_HOME/bin/$cli" ]; then
    pass "bin/$cli presente y ejecutable  (fuente: test -x)"
  else
    fail "falta $CLAUDE_HOME/bin/$cli o no es ejecutable (reinstala: bash $KIT/install.sh)"
  fi
  # Resolverse no basta: un $cli ajeno primero en el PATH daba PASS y la persona corria otro programa.
  # La sugerencia es ln -s y no -sf: -sf pisaria justo el hueco ajeno que install.sh no toca.
  cli_ruta="$(command -v "$cli" 2>/dev/null)"
  if [ -z "$cli_ruta" ]; then
    warn "$cli no se resuelve en tu PATH: ln -s \"$CLAUDE_HOME/bin/$cli\" \"\$HOME/.local/bin/$cli\" y abre una terminal nueva (comprueba que ~/.local/bin esta en el PATH)"
  elif [ "$(readlink -f -- "$cli_ruta")" = "$(readlink -f -- "$CLAUDE_HOME/bin/$cli")" ]; then
    pass "$cli se resuelve en el PATH  (fuente: command -v + readlink -f)"
  else
    warn "$cli del PATH es $cli_ruta, que no es $CLAUDE_HOME/bin/$cli: usa esa ruta o resuelve el conflicto (si retiras el otro: ln -s \"$CLAUDE_HOME/bin/$cli\" \"\$HOME/.local/bin/$cli\")"
  fi
done
if [ -f "$CLAUDE_HOME/templates/nucleo.md" ]; then
  pass "templates/nucleo.md presente  (fuente: test -f)"
else
  fail "falta $CLAUDE_HOME/templates/nucleo.md (reinstala: bash $KIT/install.sh)"
fi
# El CLAUDE.md debe importar AGENTS.md: sin el, AGENTS.md esta instalado pero nadie lo lee.
if [ -f "$CLAUDE_HOME/CLAUDE.md" ] && command grep -qE '@[^[:space:]]*AGENTS\.md' "$CLAUDE_HOME/CLAUDE.md"; then
  pass "CLAUDE.md importa AGENTS.md  (fuente: grep @AGENTS.md)"
else
  warn "tu CLAUDE.md no contiene @AGENTS.md: añadelo (la plantilla del kit esta en CLAUDE.kit.md)"
fi

# 2c. Deriva entre lo que el kit trae y lo desplegado. Es WARN y no FAIL: personalizar un
# hook es legitimo. Pero si divergen y no lo sabes, el kit deja de reproducir tu maquina, y
# eso ya paso: dos guards llevaban meses distintos entre el kit y su copia de origen, con la
# version endurecida en un lado y la antigua en el otro, y nadie lo noto.
derivados=0; derivados_lista=""
# hooks/lib/ y sentinel/ tambien: nucleo.sh y sentinel_preflight.py gobiernan hooks enteros y antes quedaban fuera.
# De sentinel/ solo el codigo (*.py): iocs.json es dato que la persona personaliza por diseno y
# reinstalar para "alinearlo" pisaria sus datos; su acoplamiento con el preflight lo cubre 2d.
for src in "$KIT"/claude/hooks/* "$KIT"/claude/hooks/lib/* "$KIT"/sentinel/*.py; do
  [ -f "$src" ] || continue
  case "$src" in
    "$KIT"/sentinel/*.py) nombre="sentinel/$(basename "$src")"; dst="$CLAUDE_HOME/$nombre" ;;
    "$KIT"/claude/hooks/lib/*) nombre="lib/$(basename "$src")"; dst="$CLAUDE_HOME/hooks/$nombre" ;;
    *) nombre="$(basename "$src")"; dst="$CLAUDE_HOME/hooks/$nombre" ;;
  esac
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

# 2d. version minima del preflight que exige iocs.json (acoplamiento datos/codigo, E6 #27).
# Un iocs.json nuevo con un preflight viejo no falla: las reglas que el codigo viejo no sabe
# leer (p. ej. las de tuberia al shell, que cuentan con la union de continuaciones) se quedan
# a medias en silencio. Se compara el entero de iocs.json contra PREFLIGHT_VERSION del .py.
if [ -n "$ioc_file" ]; then
  ioc_want="$(jq -r '.min_preflight_version // empty' "$ioc_file" 2>/dev/null)"
  pre_py=""
  for c in "${ioc_file%/*}/sentinel_preflight.py" "$ioc_pre" "$CLAUDE_HOME/sentinel/sentinel_preflight.py"; do
    [ -n "$c" ] && [ -f "$c" ] && { pre_py="$c"; break; }
  done
  case "$ioc_want" in
    ''|*[!0-9]*) ;;
    *) if [ -n "$pre_py" ]; then
         pre_have="$(grep -oE '^PREFLIGHT_VERSION = [0-9]+' "$pre_py" | grep -oE '[0-9]+$' | head -1)"
         pre_have="${pre_have:-1}"
         if [ "$pre_have" -lt "$ioc_want" ]; then
           warn "iocs.json exige sentinel_preflight.py v$ioc_want y el instalado ($pre_py) es v$pre_have: reinstala el kit para alinearlos"
         else
           pass "sentinel_preflight.py v$pre_have cubre lo que exige iocs.json (v$ioc_want)"
         fi
       fi ;;
  esac
fi

# 2e. statusLine: si settings.json la declara, su comando tiene que resolverse.
# Claude Code no avisa de nada aqui: medido en 2.1.258, un exit != 0 o un stdout vacio dejan
# la barra EN BLANCO en silencio y stderr se descarta. Ya paso: una instalacion escribio
# settings.json entero con cp -p y se llevo la clave statusLine por delante; 15 minutos con
# la barra vacia y ni una linea de aviso en ningun sitio.
# Del string del comando se extrae el ejecutable REAL: en "bash ~/.claude/statusline.sh" lo
# que puede faltar es el script, no bash.
# Si no hay statusLine este check calla: el kit instala una, pero quitarla es valido y eso
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

# 4b. interprete para los hooks Python (sentinel_preflight, write-guard).
# No es FAIL: optional-hook.sh los convierte en no-op si no hay interprete, y el
# resto de la cadena (los guards de bash) sigue protegiendo. Pero conviene
# saberlo, porque son capas menos.
if [ -x "$HOME/.venvs/tools/bin/python3" ] || command -v python3 >/dev/null 2>&1; then
  pass "interprete para hooks Python disponible  (fuente: venv o python3 del sistema)"
else
  warn "sin python3: el preflight de Sentinel y write-guard quedan en no-op (los guards de bash siguen activos)"
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
# compresion, que es legitimo no instalar. /readyz
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
    fail "API enrutada a $base_url por $base_src pero ahi no contesta nadie: Claude Code no podra conectar. Arranca el proxy o quita ANTHROPIC_BASE_URL de $base_src"
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

# 5a. rtk (opcional -> WARN): filtro de salida de CLI que el kit ya NO cablea
# (el hook `rtk hook claude` se retiró).
if command -v rtk >/dev/null 2>&1; then
  pass "rtk (filtro de salida de CLI) presente  (fuente: command -v rtk)"
else
  warn "rtk no instalado (opcional): el kit no lo cablea -- ningun hook de settings.json lo invoca -- y solo lo deja permitido en permissions.allow; ver docs/08-plugins-mcp-y-skills.md"
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
