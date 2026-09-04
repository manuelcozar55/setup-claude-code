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
# El `!` de negacion es una palabra reservada del shell, no un comando: pasarselo a want()
# como primer argumento da "!: command not found" y el caso se cuenta como fallo sin haber
# medido nada. want_no() lo hace explicito.
want_no(){ local msg="$1"; shift; if "$@"; then ko "$msg"; else ok; fi; }

command -v jq >/dev/null 2>&1 || { echo "skip - jq ausente: esta suite audita settings.json con jq"; echo "PASS=0 FAIL=0 SKIP=1"; exit 0; }

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
# autonomos: necesitan leer JSON. Desde Track M eso no significa `jq`: leen con
# `jq` si esta y con `python3` si no. CLEAN_PATH conserva los dos a proposito;
# los dos casos degradados -sin jq, y sin ninguno de los dos- se miden aparte
# en el bloque 7.
destructive='{"tool_name":"Bash","tool_input":{"command":"rm -rf /"}}'
if run_hook_chain "$destructive" | grep -q '^rc:2$'; then
  ok
else
  ko "rm -rf / NO queda bloqueado en una instalacion limpia: los guards son decorativos"
fi

# --- 7. sin lector de JSON: los dos escalones, y son distintos ------------
# El bloque 6 corre con jq Y python3 presentes, asi que no ve ninguno de los dos casos
# degradados. Aqui se miden por separado, porque el contrato NO es el mismo:
#
#   7a  sin `jq` pero CON `python3`  -> el kit funciona IGUAL. Es la promesa de Track M:
#       los guards leen con el shim hk-json y deciden como siempre, e install.sh instala.
#       Antes de Track M este caso apagaba la Capa 1 entera; despues, exigir aqui un
#       bloqueo seria exigir la averia que se acaba de arreglar.
#   7b  sin `jq` NI `python3`        -> se falla CERRADO y se DICE. Ese es el coste
#       declarado: sin poder leer el payload, un guard ciego no puede autorizar, asi que
#       deniega tambien lo inocuo; e install.sh se niega a instalar, porque instalar
#       dejaria a quien lo hace sin Bash y sin explicacion.
#
# Granja de symlinks a CLEAN_PATH saltando lo que toque: es la unica forma de que
# `command -v` falle DE VERDAD dentro del hook (un binario no ejecutable o una funcion de
# shell no lo consiguen). Se comprueba en las DOS direcciones -que le falta lo que crees y
# que lo que queda ejecuta-, porque un `grep` roto dentro de la granja convertiria
# cualquier medicion de abajo en un rc mudo que se leeria como "deja pasar".
granja_sin() { # $1 = directorio destino, resto = basenames a excluir
  local dst="$1"; shift
  local excluidos=" $* " d f b
  mkdir -p "$dst"
  IFS=: read -ra CDIRS <<< "$CLEAN_PATH"
  for d in "${CDIRS[@]}"; do
    [ -d "$d" ] || continue
    for f in "$d"/*; do
      b="${f##*/}"
      case "$excluidos" in *" $b "*) continue ;; esac
      [ -e "$f" ] && [ ! -e "$dst/$b" ] && ln -s "$f" "$dst/$b"
    done
  done
}
NOJQ="$TMP_HOME/nojq";     granja_sin "$NOJQ" jq
NOJSON="$TMP_HOME/nojson"; granja_sin "$NOJSON" jq python3 python

want_no "la granja sin jq si tiene jq: 7a no probaria nada (falsabilidad)" \
  env -i PATH="$NOJQ" sh -c 'command -v jq >/dev/null 2>&1'
want "la granja sin jq NO tiene python3: 7a mediria 7b (falsabilidad)" \
  env -i PATH="$NOJQ" sh -c 'command -v python3 >/dev/null 2>&1'
want_no "la granja sin lector de JSON conserva alguno: 7b no probaria nada (falsabilidad)" \
  env -i PATH="$NOJSON" sh -c 'command -v jq >/dev/null 2>&1 || command -v python3 >/dev/null 2>&1'
want "el grep de las granjas no ejecuta: cualquier rc de abajo seria mudo (falsabilidad)" \
  env -i PATH="$NOJSON" sh -c 'echo x | grep -q x'

run_guard() { # $1 = fichero del guard, $2 = payload, $3 = PATH; imprime "rc:<codigo> <salida>"
  local rc=0 out
  out=$(printf '%s' "$2" | env -i HOME="$TMP_HOME" PATH="$3" \
    bash "$CLAUDE_HOME/hooks/$1" 2>&1) || rc=$?
  printf 'rc:%s %s' "$rc" "$out"
}

GUARDS_JSON="block-dangerous-commands.sh branch-guard.sh destructive-guard.sh secret-guard.sh"

# 7a: sin jq y con python3, un `ls -la /tmp` tiene que pasar como pasa con jq.
for g in $GUARDS_JSON; do
  case "$(run_guard "$g" "$benign" "$NOJQ")" in
    rc:0*) ok ;;
    *) ko "$g bloquea lo inocuo sin jq (con python3 delante): eso es la averia que Track M arreglo" ;;
  esac
done
rc_nojq=0
CLAUDE_HOME="$TMP_HOME/.claude-nojq" PATH="$NOJQ" GITLEAKS_AUTO_INSTALL=n \
  bash "$KIT/install.sh" </dev/null >/dev/null 2>&1 || rc_nojq=$?
want "install.sh no instala sin jq aunque haya python3 (rc=$rc_nojq): la puerta pide de mas" \
  [ "$rc_nojq" -eq 0 ]
want "install.sh salio 0 sin jq pero no dejo settings.json: instalacion a medias" \
  [ -e "$TMP_HOME/.claude-nojq/settings.json" ]

# 7b: sin ninguno de los dos, fallo cerrado y con motivo. No basta el rc: un rc=2 mudo
# deja a quien lo sufre sin saber que instalar, y ese fue el fallo original.
for g in $GUARDS_JSON; do
  salida="$(run_guard "$g" "$benign" "$NOJSON")"
  case "$salida" in
    rc:2*) ok ;;
    *) ko "$g no bloquea (exit 2) sin jq NI python3: permite en silencio (fail-open)" ;;
  esac
  case "$salida" in
    *"no JSON parser"*|*"lector de JSON"*|*jq*) ok ;;
    *) ko "$g bloquea sin jq NI python3 pero no dice por que: rc=2 mudo" ;;
  esac
done

rc_nojson=0
CLAUDE_HOME="$TMP_HOME/.claude-nojson" PATH="$NOJSON" GITLEAKS_AUTO_INSTALL=n \
  bash "$KIT/install.sh" </dev/null >/dev/null 2>&1 || rc_nojson=$?
want "install.sh instala sin jq NI python3 (rc=$rc_nojson): falta la puerta de dependencia" \
  [ "$rc_nojson" -ne 0 ]
want "install.sh dejo un CLAUDE_HOME a medias al abortar sin lector de JSON" \
  [ ! -e "$TMP_HOME/.claude-nojson" ]

rm -rf "$TMP_HOME"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
