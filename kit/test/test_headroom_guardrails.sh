#!/bin/bash
# test_headroom_guardrails.sh — los guardarrailes de Headroom que doctor.sh vigila, y las
# tres correcciones de la unidad systemd que install.sh genera.
#
# Por que existen estos checks, y no son precaucion teorica: los cuatro fallos que se
# prueban aqui ocurrieron en una maquina real y ninguno se detecto solo.
#
#   1. ANTHROPIC_BASE_URL vivia en 5 settings.local.json de proyecto, cada uno con un hook
#      `headroom wrap selfheal` que lo reponia en cada arranque. El enrutado dependia del
#      cwd de la sesion: el 94 % del trabajo de un dia salio sin pasar por el proxy, y
#      `headroom doctor` decia "not routed" DENTRO de una sesion enrutada.
#   2. La documentacion de la propia herramienta se contradice sobre si el modo por defecto
#      es `cache` o `token`, y esa inconsistencia ya puso un proxy en `token`. Con el 95,4 %
#      del input en lecturas de cache, `token` tendria que comprimir el 85 % del contexto
#      solo para EMPATAR con `cache`; comprime el 4,2 % de media.
#   3. `--log-messages` (opt-in, y su propio --help avisa "may log sensitive data") dejo 36
#      conversaciones enteras, 12 MB en texto plano y permisos 0644, dos semanas despues de
#      la sesion de depuracion que las creo.
#   4. La unidad que genera el kit habia derivado de la que funciona: sin
#      %h/.local/share/rtk en ReadWritePaths, SQLite da "unable to open database file
#      (code 14)" cada 60 s; sin HF_HUB_OFFLINE=0 el motor de compresion queda
#      available:false EN SILENCIO y /readyz sigue diciendo healthy.
#
# Hermetico a proposito: HOME, XDG_CONFIG_HOME y un `headroom` de pega propios. Sin eso el
# resultado lo decidiria la maquina de quien lo corre (y en CI, donde no hay headroom, los
# checks no se ejecutarian y la suite daria VERDE FALSO). Es la misma leccion que
# 628dfaa "fix(test): hace hermetico test_guards.sh".
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
pass=0; fail=0
ok(){ pass=$((pass+1)); }
ko(){ fail=$((fail+1)); echo "NOT ok - $1"; }
falsified=0
# `cond && ok || ko msg` no es if-then-else (shellcheck SC2015): si `ok` fallara,
# correria `ko` igualmente. Mismo helper que test_with_headroom.sh:18.
want(){ local msg="$1"; shift; if "$@"; then ok; else ko "$msg"; fi; }

command -v jq >/dev/null 2>&1 || { echo "NOT ok - jq requerido"; echo "== 0 passed, 1 failed =="; exit 1; }

install_clean() { # imprime CLAUDE_HOME
  local h; h="$(mktemp -d)"
  CLAUDE_HOME="$h/.claude" GITLEAKS_AUTO_INSTALL=n bash "$KIT/install.sh" >/dev/null 2>&1
  echo "$h/.claude"
}

mk_home() { # imprime una raiz que hace de HOME, con un headroom de pega
  local r; r="$(mktemp -d)"
  mkdir -p "$r/.local/bin" "$r/.config/systemd/user" "$r/.headroom/logs"
  # En .local/bin y no en bin/: la unidad referencia %h/.local/bin/headroom, y
  # `systemd-analyze verify` COMPRUEBA que el ExecStart exista. Con un HOME falso sin
  # el binario devuelve rc=1 ("Command ... is not executable"), asi que el mismo test
  # pasaba lanzado a mano (HOME real, binario presente) y fallaba dentro de
  # `make bootstrap` (HOME aislado). Es la misma no-hermeticidad que esta suite vigila.
  printf '#!/bin/sh\nexit 0\n' > "$r/.local/bin/headroom"; chmod +x "$r/.local/bin/headroom"
  chmod 700 "$r/.headroom"
  # logs/ aparte: nace con el umask del proceso (755), no hereda el 700 del padre. Este
  # 755 es el directorio que crea este mkdir bajo el umask 022 de la shell de test; no es
  # el mismo dato que el 0002/664 de kit/doctor.sh:322-324, que describe los FICHEROS que
  # escribe el proxy real bajo el umask de su propio servicio systemd.
  chmod 700 "$r/.headroom/logs"
  echo "$r"
}

set_base_url() { # $1 fichero de settings, $2 url
  local tmp; tmp="$(mktemp)"
  if [ -f "$1" ]; then jq --arg u "$2" '.env.ANTHROPIC_BASE_URL = $u' "$1" > "$tmp" && mv "$tmp" "$1"
  else printf '{"env":{"ANTHROPIC_BASE_URL":"%s"}}\n' "$2" > "$1"; fi
}

write_unit() { # $1 raiz-HOME, $2 argumentos de ExecStart
  printf '[Unit]\nDescription=t\n\n[Service]\nExecStart=%%h/.local/bin/headroom %s\n\n[Install]\nWantedBy=default.target\n' \
    "$2" > "$1/.config/systemd/user/headroom-proxy.service"
}

write_dropin() { # $1 raiz-HOME, $2 cuerpo de [Service]
  mkdir -p "$1/.config/systemd/user/headroom-proxy.service.d"
  printf '[Service]\n%s\n' "$2" \
    > "$1/.config/systemd/user/headroom-proxy.service.d/10-higiene.conf"
}

run_doctor() { # $1 CLAUDE_HOME, $2 raiz-HOME, $3 doctor alternativo (opcional) -> salida completa
  env -u ANTHROPIC_BASE_URL HOME="$2" XDG_CONFIG_HOME="$2/.config" \
      PATH="$2/.local/bin:$PATH" CLAUDE_HOME="$1" bash "${3:-$KIT/doctor.sh}" 2>&1
}

# --- 1) dos fuentes de enrutado -> FAIL -------------------------------------
CH1="$(install_clean)"; R1="$(mk_home)"
set_base_url "$CH1/settings.json"       "http://127.0.0.1:1"
set_base_url "$CH1/settings.local.json" "http://127.0.0.1:1"
out1="$(run_doctor "$CH1" "$R1")"
if echo "$out1" | grep -qE '^FAIL .*declarado en 2 ficheros'; then ok; else
  ko "con ANTHROPIC_BASE_URL en settings.json Y settings.local.json, doctor no reporta FAIL de fuente duplicada"
fi

# --- 2) una sola fuente -> lo dice, y no falla por eso ----------------------
CH2="$(install_clean)"; R2="$(mk_home)"
set_base_url "$CH2/settings.json" "http://127.0.0.1:1"
out2="$(run_doctor "$CH2" "$R2")"
if echo "$out2" | grep -q 'enrutado declarado en un solo sitio'; then ok; else
  ko "con una sola fuente, doctor no lo declara de forma positiva"
fi
if echo "$out2" | grep -qE '^FAIL .*declarado en 2 ficheros'; then
  ko "con una sola fuente no puede haber FAIL de fuente duplicada"
else ok; fi

# --- 3) --mode token -> FAIL; --mode cache -> PASS -------------------------
CH3="$(install_clean)"; R3="$(mk_home)"
write_unit "$R3" "proxy --port 8787 --mode token --no-telemetry"
out3="$(run_doctor "$CH3" "$R3")"
if echo "$out3" | grep -qE '^FAIL .*--mode cache'; then ok; else
  ko "una unidad con --mode token no produce FAIL (es el ajuste que mas cuesta si se equivoca)"
fi
write_unit "$R3" "proxy --port 8787 --mode cache --no-telemetry"
out3b="$(run_doctor "$CH3" "$R3")"
if echo "$out3b" | grep -q 'el proxy arranca en --mode cache'; then ok; else
  ko "con --mode cache, doctor no lo confirma"
fi
if echo "$out3b" | grep -qE '^FAIL .*--mode cache'; then
  ko "con --mode cache no puede quedar el FAIL del modo"
else ok; falsified=$((falsified + 1)); fi

# --- 4) --budget y --log-messages en la unidad -> FAIL ---------------------
CH4="$(install_clean)"; R4="$(mk_home)"
write_unit "$R4" "proxy --port 8787 --mode cache --budget 10"
out4="$(run_doctor "$CH4" "$R4")"
if echo "$out4" | grep -qE '^FAIL .*--budget'; then ok; else
  ko "--budget en la unidad no produce FAIL (al agotarse devuelve HTTP 200 con cuerpo vacio)"
fi
write_unit "$R4" "proxy --port 8787 --mode cache --log-messages"
out4b="$(run_doctor "$CH4" "$R4")"
if echo "$out4b" | grep -qE '^FAIL .*--log-messages'; then ok; else
  ko "--log-messages en la unidad no produce FAIL (escribe la conversacion entera en claro)"
fi

# --- 5) conversaciones en claro en proxy.jsonl -> FAIL ---------------------
CH5="$(install_clean)"; R5="$(mk_home)"
printf '{"request_id":"x","request_messages":[{"role":"user","content":"hola"}]}\n' \
  > "$R5/.headroom/logs/proxy.jsonl"
out5="$(run_doctor "$CH5" "$R5")"
if echo "$out5" | grep -qE '^FAIL .*request_messages'; then ok; else
  ko "proxy.jsonl con request_messages no produce FAIL (son conversaciones en claro en disco)"
fi
# Falsabilidad: el campo presente pero nulo es el estado normal y NO debe fallar.
printf '{"request_id":"x","request_messages":null}\n' > "$R5/.headroom/logs/proxy.jsonl"
out5b="$(run_doctor "$CH5" "$R5")"
if echo "$out5b" | grep -qE '^FAIL .*request_messages'; then
  ko "request_messages:null es el estado normal del proxy y no debe producir FAIL"
else ok; falsified=$((falsified + 1)); fi

# --- 6) permisos de ~/.headroom -> WARN -----------------------------------
CH6="$(install_clean)"; R6="$(mk_home)"
chmod 755 "$R6/.headroom"
out6="$(run_doctor "$CH6" "$R6")"
if echo "$out6" | grep -qE '^WARN .*\.headroom tiene permisos 755'; then ok; else
  ko "un ~/.headroom en 755 no produce WARN de permisos"
fi

# --- 7) la unidad que GENERA install.sh trae las tres correcciones ---------
# Se genera con el mismo camino que usa test_with_headroom.sh: sin red y sin systemd.
R7="$(mk_home)"
CLAUDE_HOME="$R7/.claude" GITLEAKS_AUTO_INSTALL=n bash "$KIT/install.sh" >/dev/null 2>&1
CLAUDE_HOME="$R7/.claude" XDG_CONFIG_HOME="$R7/.config" HEADROOM_DRY_RUN=1 HEADROOM_FAKE_READY=1 \
  bash "$KIT/install.sh" --with-headroom >/dev/null 2>&1
U7="$R7/.config/systemd/user/headroom-proxy.service"
if [ -f "$U7" ]; then
  want "la unidad generada no da escritura a %h/.local/share/rtk: SQLite dara 'unable to open database file (code 14)' cada 60 s" \
    grep -qE '^ReadWritePaths=.*\.local/share/rtk' "$U7"
  want "la unidad generada no fija HF_HUB_OFFLINE=0: el motor de compresion queda available:false EN SILENCIO" \
    grep -qE '^Environment=HF_HUB_OFFLINE=0' "$U7"
  want "la unidad generada no tapa \$HOME/.ssh: con ProtectHome=read-only el proxy puede leer tus claves" \
    grep -qE '^InaccessiblePaths=.*\.ssh' "$U7"
  want "la unidad generada no fija --mode cache explicitamente" \
    grep -qE '^ExecStart=.*--mode[ =]cache' "$U7"
  # ProtectHome=tmpfs seria mas fuerte pero ocultaria %h/.local/bin/headroom dentro del
  # namespace y la unidad no podria ni ejecutarse (203/EXEC). Se comprueba que NO se use.
  if grep -qE '^ProtectHome=tmpfs' "$U7"; then
    ko "ProtectHome=tmpfs oculta %h/.local/bin/headroom: la unidad no arrancaria (203/EXEC)"
  else ok; fi
  if command -v systemd-analyze >/dev/null 2>&1; then
    want "systemd-analyze verify rechaza la unidad generada" \
      env HOME="$R7" systemd-analyze verify --user "$U7" >/dev/null 2>&1
  else
    echo "skip - systemd-analyze ausente: no se valida la sintaxis de la unidad"
  fi
else
  ko "install.sh --with-headroom no genero la unidad en XDG_CONFIG_HOME"
fi

# --- 8) falsabilidad del sensor nuevo --------------------------------------
# Un sensor que no se puede poner rojo no es un sensor. Se neutraliza la marca que
# busca, sobre una COPIA, y se exige que el caso malo pase de detectado a mudo. Sin
# esto el sensor podria estar comparando contra una cadena que nunca aparece --
# exactamente el defecto que esta entrega arregla -- y la suite seguiria verde.
CH12="$(install_clean)"; R12="$(mk_home)"
FALS="$(mktemp -d)"; cp "$KIT/doctor.sh" "$FALS/doctor.sh"
sed -i 's/payload_preview/zzz_marca_que_no_existe/g' "$FALS/doctor.sh"
printf '%s\n' '2026-09-03 15:35:10,407 - headroom.cache.compression_store - INFO - event=headroom_retrieve {"payload_preview":"texto literal","payload_preview_chars":13}' \
  > "$R12/.headroom/logs/proxy.log"
mudo="$(run_doctor "$CH12" "$R12" "$FALS/doctor.sh")"
if echo "$mudo" | grep -qE '^FAIL .*payload_preview'; then
  ko "el sensor de payload_preview no es falsable: neutralizado sigue detectando"
else
  ok; falsified=$((falsified + 1))
fi

# --- 9) conversacion en claro en proxy.log -> FAIL --------------------------
# El sensor viejo solo miraba proxy.jsonl y su marca "request_messages". La fuga
# real vive en proxy.log, la escribe compression_store a nivel INFO con
# event=headroom_retrieve y --log-messages APAGADO, y su marca es "payload_preview".
# Un sensor que vigila el fichero equivocado se queda verde con conversacion en
# claro a un directorio de distancia: 592 lineas del 2026-09-03 contando las seis
# franjas de rotacion (una medicion contra una sola franja habia dado 100).
CH7="$(install_clean)"; R7="$(mk_home)"
printf '%s\n' '2026-09-03 15:35:10,407 - headroom.cache.compression_store - INFO - event=headroom_retrieve {"hash":"abc","payload_preview":"texto literal de la conversacion","payload_preview_chars":1062}' \
  > "$R7/.headroom/logs/proxy.log"
out7="$(run_doctor "$CH7" "$R7")"
if echo "$out7" | grep -qE '^FAIL .*payload_preview'; then ok; else
  ko "un proxy.log con payload_preview con contenido no produce FAIL"
fi

# --- 10) el mismo log con el preview ya apagado -> silencio -----------------
printf '%s\n' '2026-09-03 15:35:10,407 - headroom.cache.compression_store - INFO - event=headroom_retrieve {"hash":"abc","payload_preview":"","payload_preview_chars":0}' \
  > "$R7/.headroom/logs/proxy.log"
[ -f "$R7/.headroom/logs/proxy.log" ] || ko "el caso 10 corrio sin proxy.log: verde vacio"
out8="$(run_doctor "$CH7" "$R7")"
if echo "$out8" | grep -qE '^FAIL .*payload_preview'; then
  ko "un proxy.log con el preview apagado produce un FAIL falso"
else ok; fi

# --- 11) permisos de ~/.headroom/logs -> WARN ------------------------------
# El 700 del directorio padre no cubre al hijo, y ahi es donde vive el log.
chmod 755 "$R7/.headroom/logs"
out9="$(run_doctor "$CH7" "$R7")"
if echo "$out9" | grep -qE '^WARN .*headroom/logs tiene permisos 755'; then ok; else
  ko "un ~/.headroom/logs en 755 no produce WARN de permisos"
fi
chmod 700 "$R7/.headroom/logs"

# --- 12) unidad sin InaccessiblePaths -> WARN ------------------------------
# Con ProtectHome=read-only el proxy puede LEER ~/.ssh, ~/.aws, ~/.gnupg y
# ~/.config/gh. La plantilla del kit lo tapa, pero nada re-aplica la plantilla:
# la unidad viva de esta maquina es del 21-ago y no llego a tenerlo.
CH10="$(install_clean)"; R10="$(mk_home)"
write_unit "$R10" "proxy --port 8787 --mode cache --no-telemetry"
out10="$(run_doctor "$CH10" "$R10")"
if echo "$out10" | grep -qE '^WARN .*InaccessiblePaths'; then ok; else
  ko "una unidad que no declara InaccessiblePaths no produce WARN"
fi

# --- 13) el mismo endurecimiento, pero en un drop-in -> silencio -----------
# Un grep al fichero de la unidad no ve lo que vive en .service.d/: sin esto el
# sensor daria rojo falso a una maquina correctamente arreglada con drop-in.
write_dropin "$R10" 'InaccessiblePaths=-%h/.ssh -%h/.aws -%h/.gnupg -%h/.config/gh'
[ -f "$R10/.config/systemd/user/headroom-proxy.service" ] || ko "el caso 13 corrio sin unidad: verde vacio"
out11="$(run_doctor "$CH10" "$R10")"
if echo "$out11" | grep -qE '^WARN .*InaccessiblePaths'; then
  ko "el sensor no lee los drop-ins: da WARN con el endurecimiento ya puesto"
else ok; fi

# Un sensor que no puede ponerse rojo no es un sensor. El contador vive aqui, al final
# del fichero, a proposito: en la posicion vieja (justo tras el caso 8) cualquier
# `falsified++` de un caso añadido despues no se contaba. Aqui abajo, cualquier caso
# nuevo que se añada por encima siempre queda dentro de la cuenta.
if [ "$falsified" -ge 3 ]; then ok; else
  ko "los casos negativos no demuestran deteccion real (detectados: $falsified de 3)"
fi

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
