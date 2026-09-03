#!/bin/bash
# test_doctor_base_url.sh — doctor.sh debe FALLAR cuando el tráfico está enrutado
# a un proxy que no contesta.
#
# Por qué es un test y no un detalle: la version anterior reportaba Headroom como
# WARN "opcional" y no comprobaba nunca el endpoint, asi que doctor.sh salia con
# codigo 0 en una maquina cuyo Claude Code no podia hablar con la API. Un doctor
# que aprueba una instalacion inservible es peor que no tener doctor, porque
# retira la sospecha justo donde hacia falta.
#
# Tres casos: enrutado y muerto -> FAIL; sin enrutar -> no es FAIL (es la config
# por defecto del kit y es valida); enrutado y vivo -> PASS.
#
# Casos D-F: la MISMA leccion en el ambito de PROYECTO. El check de fuente unica solo
# miraba $CLAUDE_HOME/settings*.json, y el mecanismo que multiplica fuentes escribe en
# <cwd>/.claude/settings.local.json (`headroom wrap`, wrap.py:1505). Medido: dos fuentes
# vivas en una maquina real y el doctor veia una.
#
# Casos G-I: la statusLine. Claude Code silencia su fallo por completo (exit != 0 o stdout
# vacio dejan la barra en blanco y stderr se descarta), asi que si nadie la comprueba nadie
# se entera: paso hoy, 15 minutos de barra vacia despues de que una instalacion se llevara
# la clave por delante.
#
# Caso J: el sondeo del check 5 tiene que mirar TAMBIEN el ambito de proyecto. Reproducido:
# con la URL declarada solo en <proyecto>/.claude/settings.local.json y el puerto muerto,
# doctor firmaba "PASS - API directa" y "PASS - enrutado declarado en un solo sitio" en la
# misma salida, con rc=0 -- porque el check 5 leia solo $CLAUDE_HOME/settings.json mientras
# el 5e ya enumeraba el ambito de proyecto. Ese estado tenia su fixture construido aqui
# desde el principio (el caso F) y la suite lo declaraba limpio: ver el caso F.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
pass=0; fail=0
ok(){ pass=$((pass+1)); }
ko(){ fail=$((fail+1)); echo "FAIL: $1"; }

command -v jq >/dev/null 2>&1 || { echo "skip - jq ausente: esta suite fabrica settings.json con jq para simular el enrutado"; echo "PASS=0 FAIL=0 SKIP=1"; exit 0; }
PY="${PYTHON3:-python3}"

free_port() { "$PY" -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'; }

install_clean() { # imprime CLAUDE_HOME
  local h; h="$(mktemp -d)"
  CLAUDE_HOME="$h/.claude" GITLEAKS_AUTO_INSTALL=n bash "$KIT/install.sh" >/dev/null 2>&1
  echo "$h/.claude"
}

set_base_url_file() { # $1 fichero de settings (puede no existir aun), $2 url
  local tmp; tmp="$(mktemp)"
  mkdir -p "$(dirname "$1")"; [ -f "$1" ] || echo '{}' > "$1"
  jq --arg u "$2" '.env.ANTHROPIC_BASE_URL = $u' "$1" > "$tmp" && mv "$tmp" "$1"
}

set_base_url() { # $1 CLAUDE_HOME, $2 url
  set_base_url_file "$1/settings.json" "$2"
}

set_statusline() { # $1 CLAUDE_HOME, $2 comando
  local tmp; tmp="$(mktemp)"
  jq --arg c "$2" '.statusLine = {type:"command", command:$c}' "$1/settings.json" > "$tmp" && mv "$tmp" "$1/settings.json"
}

# Un servidor que contesta 200 a todo en el puerto $1, y espera a que conteste antes de
# volver. Deja el PID en SRV para que el caso lo mate. Lo usan los casos C y F: los dos
# necesitan un endpoint VIVO, y tener el servidor escrito dos veces era la via corta a que
# uno de los dos derivara.
stub_vivo() { # $1 puerto -> SRV
  "$PY" - "$1" <<'EOF' &
import sys, http.server, socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Length","2"); self.end_headers()
        self.wfile.write(b"ok")
    def log_message(self, *a): pass
socketserver.TCPServer.allow_reuse_address = True
with socketserver.TCPServer(("127.0.0.1", int(sys.argv[1])), H) as s:
    s.serve_forever()
EOF
  SRV=$!
  for _ in $(seq 1 50); do
    if curl -fsS -m 1 -o /dev/null "http://127.0.0.1:$1/readyz" 2>/dev/null; then return 0; fi
    sleep 0.1
  done
}

# El check nuevo mira settings.json y, si ahi no hay nada, la variable de entorno.
# Se limpia ANTHROPIC_BASE_URL del entorno a proposito: si no, la maquina del que
# corre el test (que puede tener un proxy vivo, como la del autor) decidiria el
# resultado y el caso "sin enrutar" pasaria por el motivo equivocado.
# Se aisla tambien HOME y XDG_CONFIG_HOME: doctor.sh mira estado de MAQUINA fuera de
# CLAUDE_HOME (la unidad systemd, ~/.headroom/logs/proxy.jsonl), y esos hallazgos son
# legitimos pero ajenos a lo que mide este test. Sin aislarlo, un FAIL verdadero de la
# maquina de quien corre el test (p.ej. conversaciones en claro en proxy.jsonl, cuyo
# mensaje contiene la palabra "proxy") casaba con el grep de enrutado de los casos B y C.
# El cwd tambien decide (es un ambito de settings mas), asi que es parametro.
run_doctor() { # $1 CLAUDE_HOME [$2 raiz HOME] [$3 cwd] -> imprime salida completa
  local h; h="${2:-$(mktemp -d)}"; mkdir -p "$h/.headroom/logs" "$h/.config"
  ( cd "${3:-.}" && env -u ANTHROPIC_BASE_URL HOME="$h" XDG_CONFIG_HOME="$h/.config" \
        CLAUDE_HOME="$1" bash "$KIT/doctor.sh" 2>&1 )
}

# --- caso A: enrutado a un puerto muerto -> FAIL ----------------------------
CH_A="$(install_clean)"
DEAD="$(free_port)"   # puerto libre = nadie escucha ahi
set_base_url "$CH_A" "http://127.0.0.1:$DEAD"
out_a="$(run_doctor "$CH_A")"; rc_a=$?
if echo "$out_a" | grep -qE '^FAIL .*(BASE_URL|proxy|8787|no responde|no contesta)'; then ok; else
  ko "con ANTHROPIC_BASE_URL a un puerto muerto, doctor no reporta FAIL. Salida: $(echo "$out_a" | tail -3 | tr '\n' ' ')"
fi
if [ "$rc_a" -ne 0 ]; then ok; else ko "doctor debe salir con codigo != 0 si el base URL esta muerto"; fi

# --- caso B: sin ANTHROPIC_BASE_URL -> no debe fallar por este motivo -------
CH_B="$(install_clean)"
out_b="$(run_doctor "$CH_B")"
if echo "$out_b" | grep -qE '^FAIL .*(BASE_URL|proxy)'; then
  ko "sin ANTHROPIC_BASE_URL no deberia haber FAIL de enrutado (es la config por defecto del kit)"
else ok; fi
# Y debe decirlo de forma positiva: es una configuracion valida, no una carencia.
if echo "$out_b" | grep -qE '^PASS .*(directa|sin proxy)'; then ok; else
  ko "sin proxy, doctor deberia reportar PASS de API directa (salida: $(echo "$out_b" | grep -iE 'api|proxy' | tr '\n' ' '))"
fi

# --- caso C: enrutado a un endpoint vivo -> PASS ---------------------------
CH_C="$(install_clean)"
LIVE="$(free_port)"
stub_vivo "$LIVE"
set_base_url "$CH_C" "http://127.0.0.1:$LIVE"
out_c="$(run_doctor "$CH_C")"
kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
if echo "$out_c" | grep -qE '^PASS .*(BASE_URL|proxy)'; then ok; else
  ko "con el endpoint vivo, doctor deberia dar PASS de enrutado. Salida: $(echo "$out_c" | grep -iE 'proxy|base_url' | tr '\n' ' ')"
fi
if echo "$out_c" | grep -qE '^FAIL .*(BASE_URL|proxy)'; then
  ko "con el endpoint vivo no deberia haber FAIL de enrutado"
else ok; fi

# --- caso D: dos fuentes en ambito de PROYECTO -> FAIL ----------------------
# El ambito de usuario se deja limpio a proposito: si el check volviera a mirar solo
# $CLAUDE_HOME/settings*.json contaria cero y saldria callando, que es el defecto medido.
CH_D="$(install_clean)"; R_D="$(mktemp -d)"; PROY_D="$(mktemp -d)"
set_base_url_file "$CH_D/.claude/settings.local.json" "http://127.0.0.1:1"
set_base_url_file "$PROY_D/.claude/settings.local.json" "http://127.0.0.1:1"
jq -n --arg p "$PROY_D" '{projects:{($p):{}}}' > "$R_D/.claude.json"
out_d="$(run_doctor "$CH_D" "$R_D")"
if echo "$out_d" | grep -qE '^FAIL .*declarado en 2 ficheros'; then ok; else
  ko "dos fuentes de ANTHROPIC_BASE_URL en ambito de proyecto no producen FAIL (salida: $(echo "$out_d" | grep -i base_url | tr '\n' ' '))"
fi
# Un FAIL que no dice QUE fichero editar no sirve para arreglar nada.
if echo "$out_d" | grep -qE "$CH_D/\.claude/settings\.local\.json:[0-9]+.*$PROY_D/\.claude/settings\.local\.json:[0-9]+"; then ok; else
  ko "el FAIL de fuentes duplicadas no identifica los dos ficheros con ruta y linea"
fi

# --- caso E: el proyecto del cwd cuenta como fuente -------------------------
CH_E="$(install_clean)"; R_E="$(mktemp -d)"; PROY_E="$(mktemp -d)"
set_base_url "$CH_E" "http://127.0.0.1:1"
set_base_url_file "$PROY_E/.claude/settings.local.json" "http://127.0.0.1:1"
out_e="$(run_doctor "$CH_E" "$R_E" "$PROY_E")"
if echo "$out_e" | grep -qE '^FAIL .*declarado en 2 ficheros'; then ok; else
  ko "settings.json de usuario + .claude/settings.local.json del cwd son dos fuentes y doctor no lo ve"
fi

# --- caso F: una sola fuente de proyecto, y el proxy contesta -> sin ruido --
# Este caso apuntaba a un puerto MUERTO (como D y E, donde la liveness no importaba) y solo
# exigia que no hubiera FAIL de fuente duplicada: llamaba "sin ruido" a una instalacion sin
# API. Con eso, la suite tenia construido el fixture del defecto del caso J y lo declaraba
# limpio. "Sin ruido" solo vale si el proxy declarado contesta, asi que aqui contesta: F es
# el control positivo del sondeo en ambito de proyecto y J el negativo.
CH_F="$(install_clean)"; R_F="$(mktemp -d)"; PROY_F="$(mktemp -d)"
LIVE_F="$(free_port)"
stub_vivo "$LIVE_F"
set_base_url_file "$PROY_F/.claude/settings.local.json" "http://127.0.0.1:$LIVE_F"
out_f="$(run_doctor "$CH_F" "$R_F" "$PROY_F")"
kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
if echo "$out_f" | grep -qE '^FAIL .*(BASE_URL|proxy|enrutad|declarado)'; then
  ko "una sola fuente de proyecto con el proxy vivo no puede dar ningun FAIL de enrutado (salida: $(echo "$out_f" | grep -E '^FAIL' | tr '\n' ' '))"
else ok; fi
if echo "$out_f" | grep -q 'enrutado declarado en un solo sitio'; then ok; else
  ko "con una sola fuente en ambito de proyecto, doctor no la declara"
fi
# Que la declare no prueba que la haya SONDEADO: eso solo lo prueba el PASS del check 5
# nombrando la URL, y es lo que faltaba (decia "API directa" con el enrutado puesto).
if echo "$out_f" | grep -qE "^PASS .*enrutada a http://127\.0\.0\.1:$LIVE_F"; then ok; else
  ko "el check 5 no sondea la URL declarada en ambito de proyecto (salida: $(echo "$out_f" | grep -iE 'API (directa|enrutada)' | tr '\n' ' '))"
fi
if echo "$out_f" | grep -q 'API directa'; then
  ko "doctor declara una fuente de enrutado y a la vez dice 'API directa': dos PASS que se contradicen en la misma salida"
else ok; fi

# --- caso G: statusLine con un comando que no existe -> FAIL ---------------
CH_G="$(install_clean)"
set_statusline "$CH_G" "bash $CH_G/statusline-que-no-existe.sh"
out_g="$(run_doctor "$CH_G")"
if echo "$out_g" | grep -qE '^FAIL .*statusLine'; then ok; else
  ko "una statusLine que apunta a un script inexistente no produce FAIL (Claude Code deja la barra en blanco sin avisar)"
fi
# Y tiene que senalar el script, no el interprete: 'bash' existe siempre.
if echo "$out_g" | grep -qE '^FAIL .*statusline-que-no-existe\.sh'; then ok; else
  ko "el FAIL de statusLine no nombra el script que falta: extrae mal el ejecutable del comando"
fi

# --- caso H: statusLine que existe pero no imprime nada -> WARN, no FAIL ---
CH_H="$(install_clean)"
printf '#!/usr/bin/env bash\ncat >/dev/null\n' > "$CH_H/statusline-muda.sh"
chmod +x "$CH_H/statusline-muda.sh"
set_statusline "$CH_H" "bash $CH_H/statusline-muda.sh"
out_h="$(run_doctor "$CH_H")"
if echo "$out_h" | grep -qE '^WARN .*statusLine'; then ok; else
  ko "una statusLine que no imprime nada deja la barra en blanco y doctor no avisa"
fi
if echo "$out_h" | grep -qE '^FAIL .*statusLine'; then
  ko "una statusLine muda es WARN, no FAIL: el fallo puede ser del entorno de doctor"
else ok; fi

# --- caso I: sin statusLine -> ni FAIL ni WARN ------------------------------
# El kit no instala statusLine y la mayoria no la usa: convertir su ausencia en hallazgo
# seria ruido en cada instalacion limpia.
if echo "$out_b" | grep -qE '^(FAIL|WARN) .*statusLine'; then
  ko "sin statusLine declarada doctor no puede reportar nada (salida: $(echo "$out_b" | grep -i statusline | tr '\n' ' '))"
else ok; fi

# --- caso J: fuente unica de proyecto a un puerto muerto -> FAIL y rc != 0 --
# El mismo estado que el caso F pero con el proxy caido, que es el que reproduce el fallo en
# abierto: `headroom wrap` escribe la URL en <cwd>/.claude/settings.local.json
# (wrap.py:1505), asi que esta es la instalacion tipica de quien usa el proxy, no un caso
# raro. Antes salia "OK (0 FAIL)" con dos PASS contradictorios; el mismo modo de fallo que
# el comentario del check 5 declara: aprobar una instalacion inservible retira la sospecha
# justo donde hacia falta.
CH_J="$(install_clean)"; R_J="$(mktemp -d)"; PROY_J="$(mktemp -d)"
DEAD_J="$(free_port)"
set_base_url_file "$PROY_J/.claude/settings.local.json" "http://127.0.0.1:$DEAD_J"
out_j="$(run_doctor "$CH_J" "$R_J" "$PROY_J")"; rc_j=$?
if echo "$out_j" | grep -qE '^FAIL .*(BASE_URL|proxy|no responde|no contesta)'; then ok; else
  ko "con la URL declarada SOLO en ambito de proyecto y el puerto muerto, doctor no reporta FAIL (salida: $(echo "$out_j" | grep -iE 'API (directa|enrutada)|un solo sitio' | tr '\n' ' '))"
fi
if [ "$rc_j" -ne 0 ]; then ok; else
  ko "doctor sale con codigo 0 sobre una instalacion enrutada a un puerto muerto desde el ambito de proyecto"
fi
# Un FAIL que no dice QUE fichero editar no sirve para arreglar nada, y el de proyecto no es
# el settings.json de usuario que el mensaje nombraba antes.
if echo "$out_j" | grep -qE "^FAIL .*$PROY_J/\.claude/settings\.local\.json"; then ok; else
  ko "el FAIL de enrutado no nombra el fichero de proyecto que declara la URL"
fi
if echo "$out_j" | grep -q 'API directa'; then
  ko "doctor dice 'API directa' con el enrutado declarado en ambito de proyecto: es el PASS que tapaba el proxy muerto"
else ok; fi

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
