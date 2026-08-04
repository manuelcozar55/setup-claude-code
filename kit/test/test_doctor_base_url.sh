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
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
pass=0; fail=0
ok(){ pass=$((pass+1)); }
ko(){ fail=$((fail+1)); echo "FAIL: $1"; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq requerido"; echo "PASS=0 FAIL=1"; exit 1; }
PY="${PYTHON3:-python3}"

free_port() { "$PY" -c 'import socket;s=socket.socket();s.bind(("127.0.0.1",0));print(s.getsockname()[1]);s.close()'; }

install_clean() { # imprime CLAUDE_HOME
  local h; h="$(mktemp -d)"
  CLAUDE_HOME="$h/.claude" GITLEAKS_AUTO_INSTALL=n bash "$KIT/install.sh" >/dev/null 2>&1
  echo "$h/.claude"
}

set_base_url() { # $1 CLAUDE_HOME, $2 url
  local tmp; tmp="$(mktemp)"
  jq --arg u "$2" '.env.ANTHROPIC_BASE_URL = $u' "$1/settings.json" > "$tmp" && mv "$tmp" "$1/settings.json"
}

# doctor.sh se ejecuta con un HOME propio para que sus checks de venv/gitleaks no
# dependan de la maquina del que corre el test; solo nos interesa el check nuevo.
run_doctor() { # $1 CLAUDE_HOME -> imprime salida completa
  CLAUDE_HOME="$1" bash "$KIT/doctor.sh" 2>&1
}

# --- caso A: enrutado a un puerto muerto -> FAIL ----------------------------
CH_A="$(install_clean)"
DEAD="$(free_port)"   # puerto libre = nadie escucha ahi
set_base_url "$CH_A" "http://127.0.0.1:$DEAD"
out_a="$(run_doctor "$CH_A")"; rc_a=$?
if echo "$out_a" | grep -qE '^FAIL .*(BASE_URL|proxy|8787|no responde|no contesta)'; then ok; else
  ko "con ANTHROPIC_BASE_URL a un puerto muerto, doctor no reporta FAIL. Salida: $(echo "$out_a" | tail -3 | tr '\n' ' ')"
fi
[ "$rc_a" -ne 0 ] && ok || ko "doctor debe salir con codigo != 0 si el base URL esta muerto"

# --- caso B: sin ANTHROPIC_BASE_URL -> no debe fallar por este motivo -------
CH_B="$(install_clean)"
out_b="$(run_doctor "$CH_B")"
if echo "$out_b" | grep -qE '^FAIL .*(BASE_URL|proxy)'; then
  ko "sin ANTHROPIC_BASE_URL no deberia haber FAIL de enrutado (es la config por defecto)"
else ok; fi

# --- caso C: enrutado a un endpoint vivo -> PASS ---------------------------
CH_C="$(install_clean)"
LIVE="$(free_port)"
"$PY" - "$LIVE" <<'EOF' &
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
  if curl -fsS -m 1 -o /dev/null "http://127.0.0.1:$LIVE/readyz" 2>/dev/null; then break; fi
  sleep 0.1
done
set_base_url "$CH_C" "http://127.0.0.1:$LIVE"
out_c="$(run_doctor "$CH_C")"
kill "$SRV" 2>/dev/null; wait "$SRV" 2>/dev/null
if echo "$out_c" | grep -qE '^PASS .*(BASE_URL|proxy)'; then ok; else
  ko "con el endpoint vivo, doctor deberia dar PASS de enrutado. Salida: $(echo "$out_c" | grep -iE 'proxy|base_url' | tr '\n' ' ')"
fi
if echo "$out_c" | grep -qE '^FAIL .*(BASE_URL|proxy)'; then
  ko "con el endpoint vivo no deberia haber FAIL de enrutado"
else ok; fi

echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
