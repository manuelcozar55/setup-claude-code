#!/bin/bash
# test_clean_install_resilience.sh — la garantía central del kit para un tercero:
# una instalación limpia, en una máquina que NO tiene ninguno de los componentes
# de terceros (Headroom, rtk, venv de tools, gitleaks), debe (a) no romper Claude
# Code y (b) seguir bloqueando lo que promete bloquear.
#
# Las dos mitades importan y se prueban por separado, porque arreglar (a) de la
# forma perezosa --envolver todo en `|| true`-- rompe (b) en silencio y deja un
# kit de seguridad decorativo. Aquí se exige que un comando destructivo siga
# saliendo con el código 2 que Claude Code interpreta como bloqueo.
#
# Simulación de "máquina limpia": PATH reducido (sin rtk) y PYTHON_HOOK_BIN
# apuntando a un intérprete inexistente para los hooks que usan el venv.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
pass=0; fail=0
ok(){ pass=$((pass+1)); }
ko(){ fail=$((fail+1)); echo "FAIL: $1"; }
# `cond && ok || ko msg` no es if-then-else (shellcheck SC2015). want() lo hace
# explicito: want "mensaje" <comando>.
want(){ local msg="$1"; shift; if "$@"; then ok; else ko "$msg"; fi; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq requerido"; echo "PASS=0 FAIL=1"; exit 1; }

S="$KIT/claude/settings.json"

# --- 1. el kit no enruta a un proxy que no instala --------------------------
# Un ANTHROPIC_BASE_URL fijado aqui apunta a 127.0.0.1:8787 en una maquina donde
# nadie escucha: Claude Code no puede hablar con la API. Es el fallo mas grave
# posible en un kit de config, porque parece un problema de la herramienta.
if jq -e '.env.ANTHROPIC_BASE_URL' "$S" >/dev/null 2>&1; then
  ko "settings.json fija ANTHROPIC_BASE_URL: una instalacion limpia queda sin API (usar install.sh --with-headroom)"
else
  ok
fi

# --- 2. toda dependencia de tercero pasa por el wrapper --------------------
# Se listan los comandos de hook y se comprueba que ninguno invoque
# directamente rtk ni un python3 del venv.
cmds="$(jq -r '.hooks // {} | .. | .command? // empty' "$S")"
bare_rtk=0; bare_venv=0
while IFS= read -r c; do
  [ -z "$c" ] && continue
  case "$c" in
    *optional-hook.sh*) continue ;;
  esac
  case "$c" in
    rtk\ *|*/rtk\ *) bare_rtk=1 ;;
  esac
  case "$c" in
    *.venvs/tools/bin/python3*) bare_venv=1 ;;
  esac
done <<< "$cmds"
if [ "$bare_rtk" -eq 0 ]; then ok; else ko "rtk se invoca sin optional-hook.sh (exit 127 si no esta instalado)"; fi
if [ "$bare_venv" -eq 0 ]; then ok; else ko "el python3 del venv se invoca sin optional-hook.sh (exit 127 si no existe)"; fi

# --- 3. no se ha perdido ninguna salvaguarda por el camino -----------------
# Blindaje contra el arreglo perezoso: si alguien "simplifica" settings.json y se
# lleva por delante las denegaciones, el kit deja de proteger.
# El suelo "-ge 8 denegaciones" no medía nada: pasaba igual con 19 reglas que con 9. Se
# exige el conjunto que el kit promete, entrada por entrada, para que quitar cualquiera
# ponga el test en rojo; anadir reglas nuevas no lo rompe.
REQUIRED_DENY=(
  'Bash(rm -rf /*)'
  'Bash(rm -rf ~/*)'
  'Bash(git push --force *)'
  'Edit(/hooks/**)'
  'Edit(/settings.json)'
  'Edit(/settings.local.json)'
  'Edit(/sentinel-allowlist.json)'
  'Edit(/sentinel/**)'
)
for d in "${REQUIRED_DENY[@]}"; do
  if jq -e --arg d "$d" '.permissions.deny | index($d) != null' "$S" >/dev/null 2>&1; then
    ok
  else
    ko "falta la denegacion '$d' en settings.json"
  fi
done
n_allow="$(jq -r '.permissions.allow | length' "$S")"
want "esperaba >=8 permisos, hay $n_allow" [ "$n_allow" -ge 8 ]

# --- 4. instalacion limpia en un CLAUDE_HOME temporal ----------------------
TMP_HOME="$(mktemp -d)"
export CLAUDE_HOME="$TMP_HOME/.claude"
if GITLEAKS_AUTO_INSTALL=n bash "$KIT/install.sh" >/dev/null 2>&1; then ok; else ko "install.sh fallo en un CLAUDE_HOME limpio"; fi
want "optional-hook.sh no quedo instalado y ejecutable" [ -x "$CLAUDE_HOME/hooks/optional-hook.sh" ]

# --- 5. la prueba funcional: la cadena PreToolUse en una maquina pelada ----
# Se ejecuta cada comando de hook configurado, con $HOME reescrito al temporal,
# sin rtk en el PATH y sin interprete de venv. Ninguno debe salir 127.
CLEAN_PATH="/usr/bin:/bin"
run_hook_chain() { # $1 = payload JSON; imprime "rc:<codigo>" por hook
  local payload="$1" c path rc
  while IFS= read -r c; do
    [ -z "$c" ] && continue
    path="${c//\$HOME/$TMP_HOME}"
    rc=0
    printf '%s' "$payload" | env -i HOME="$TMP_HOME" PATH="$CLEAN_PATH" \
      PYTHON_HOOK_BIN=/no/existe/python3 bash -c "$path" >/dev/null 2>&1 || rc=$?
    echo "rc:$rc"
  done <<< "$(jq -r '.hooks.PreToolUse // [] | .[].hooks[].command' "$CLAUDE_HOME/settings.json")"
}

benign='{"tool_name":"Bash","tool_input":{"command":"ls -la /tmp"}}'
if run_hook_chain "$benign" | grep -q '^rc:127$'; then
  ko "algun hook sale 127 en una maquina limpia (dependencia de tercero sin envolver)"
else
  ok
fi
# Y que no bloquee un comando inocente: nada de exit 2 con un simple ls.
if run_hook_chain "$benign" | grep -q '^rc:2$'; then
  ko "un 'ls -la /tmp' inocente queda bloqueado en una instalacion limpia"
else
  ok
fi

# --- 6. y sigue protegiendo: rm -rf / debe bloquear -----------------------
# Esta es la mitad que impide el arreglo perezoso. Los guards que protegen
# (block-dangerous-commands, destructive-guard) son del kit, pero NO son
# autonomos: leen el comando del payload con jq. Ese es su unico tercero, y no
# es opcional -- install.sh lo exige en una puerta de dependencia --, asi que
# CLEAN_PATH lo conserva a proposito (/usr/bin/jq). El caso contrario, un PATH
# sin jq, se mide aparte en el bloque 7.
destructive='{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
if run_hook_chain "$destructive" | grep -q '^rc:2$'; then
  ok
else
  ko "rm -rf / NO queda bloqueado en una instalacion limpia: los guards son decorativos"
fi

# --- 7. sin jq en el PATH: la Capa 1 falla en CERRADO ---------------------
# El bloque 6 corre con jq presente, asi que no veia el caso real: los cuatro guards
# leen el payload con jq y, sin el, salian 0 en silencio -- la Capa 1 entera apagada sin
# un solo mensaje. Aqui se exige lo contrario: que DENIEGUEN (cada uno con su protocolo)
# incluso con un comando inocente, y que install.sh se niegue a instalar sin jq -- si
# instalara, denegar en el guard dejaria a quien instala sin Bash y sin explicacion.
# Granja de symlinks a CLEAN_PATH saltando jq: es la unica forma de que `command -v jq`
# falle DE VERDAD dentro del hook (un jq no ejecutable o una funcion no lo consiguen).
NOJQ="$TMP_HOME/nojq"; mkdir -p "$NOJQ"
IFS=: read -ra CDIRS <<< "$CLEAN_PATH"
for d in "${CDIRS[@]}"; do
  [ -d "$d" ] || continue
  for f in "$d"/*; do
    b="${f##*/}"
    [ -e "$f" ] && [ "$b" != jq ] && [ ! -e "$NOJQ/$b" ] && ln -s "$f" "$NOJQ/$b"
  done
done
if env -i PATH="$NOJQ" sh -c 'command -v jq >/dev/null 2>&1'; then
  ko "la granja sin jq si tiene jq: el bloque 7 no probaria nada (falsabilidad)"
else
  ok
fi

run_guard() { # $1 = fichero del guard, $2 = payload; imprime "rc:<codigo> <salida>"
  local rc=0 out
  out=$(printf '%s' "$2" | env -i HOME="$TMP_HOME" PATH="$NOJQ" \
    bash "$CLAUDE_HOME/hooks/$1" 2>&1) || rc=$?
  printf 'rc:%s %s' "$rc" "$out"
}

case "$(run_guard block-dangerous-commands.sh "$benign")" in
  rc:0*'"permissionDecision"'*'"deny"'*) ok ;;
  *) ko "block-dangerous-commands.sh no deniega sin jq: permite en silencio (fail-open)" ;;
esac
for g in branch-guard.sh destructive-guard.sh secret-guard.sh; do
  case "$(run_guard "$g" "$benign")" in
    rc:2*) ok ;;
    *) ko "$g no bloquea (exit 2) sin jq: permite en silencio (fail-open)" ;;
  esac
done

rc_nojq=0
CLAUDE_HOME="$TMP_HOME/.claude-nojq" PATH="$NOJQ" bash "$KIT/install.sh" </dev/null >/dev/null 2>&1 || rc_nojq=$?
want "install.sh instala sin jq (rc=$rc_nojq): falta la puerta de dependencia" [ "$rc_nojq" -ne 0 ]
want "install.sh dejo un CLAUDE_HOME a medias al abortar sin jq" [ ! -e "$TMP_HOME/.claude-nojq" ]

rm -rf "$TMP_HOME"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
