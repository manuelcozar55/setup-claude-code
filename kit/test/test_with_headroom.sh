#!/bin/bash
# test_with_headroom.sh — contrato de `install.sh --with-headroom`.
#
# La regla que se prueba, y es la razon de ser del subcomando: settings.json solo
# gana ANTHROPIC_BASE_URL DESPUES de comprobar que el proxy responde. Si se
# escribiera antes (o sin comprobar), se reintroduciria exactamente el fallo que
# esta rama arregla: una config que enruta a un puerto muerto.
#
# Corre sin red y sin systemd: HEADROOM_DRY_RUN=1 salta el pip y el systemctl, y
# HEADROOM_FAKE_READY simula el resultado del readiness check.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
pass=0; fail=0
ok(){ pass=$((pass+1)); }
ko(){ fail=$((fail+1)); echo "FAIL: $1"; }
# `cond && ok || ko msg` no es if-then-else (shellcheck SC2015): si `ok` fallara,
# correria `ko` igualmente. want() lo hace explicito: want "mensaje" <comando>.
want(){ local msg="$1"; shift; if "$@"; then ok; else ko "$msg"; fi; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq requerido"; echo "PASS=0 FAIL=1"; exit 1; }

setup() { # imprime raiz temporal; instala el kit limpio dentro
  local root; root="$(mktemp -d)"
  CLAUDE_HOME="$root/.claude" GITLEAKS_AUTO_INSTALL=n bash "$KIT/install.sh" >/dev/null 2>&1
  echo "$root"
}

run_wh() { # $1 root, $2 fake_ready(1|0) -> imprime salida, devuelve rc
  local root="$1" ready="$2"
  CLAUDE_HOME="$root/.claude" \
  XDG_CONFIG_HOME="$root/.config" \
  HEADROOM_DRY_RUN=1 \
  HEADROOM_FAKE_READY="$ready" \
  bash "$KIT/install.sh" --with-headroom 2>&1
}

# --- caso A: el proxy no llega a responder -> NO se toca settings.json ------
ROOT_A="$(setup)"
out_a="$(run_wh "$ROOT_A" 0)"; rc_a=$?
if jq -e '.env.ANTHROPIC_BASE_URL' "$ROOT_A/.claude/settings.json" >/dev/null 2>&1; then
  ko "con el proxy sin responder, settings.json NO debe ganar ANTHROPIC_BASE_URL"
else ok; fi
want "si el proxy no responde, --with-headroom debe salir != 0" [ "$rc_a" -ne 0 ]
if printf '%s' "$out_a" | grep -qiE 'no responde|no contesta|readyz|no arranc'; then ok; else
  ko "debe explicar por que no cableo (salida: $(printf '%s' "$out_a" | tail -2 | tr '\n' ' '))"
fi

# --- caso B: el proxy responde -> se cablea --------------------------------
ROOT_B="$(setup)"
out_b="$(run_wh "$ROOT_B" 1)"; rc_b=$?
want "con el proxy vivo, --with-headroom debe salir 0 (salida: $(printf '%s' "$out_b" | tail -2 | tr '\n' ' '))" [ "$rc_b" -eq 0 ]
got="$(jq -r '.env.ANTHROPIC_BASE_URL // empty' "$ROOT_B/.claude/settings.json")"
want "con el proxy vivo, settings.json debe ganar ANTHROPIC_BASE_URL" [ -n "$got" ]
case "$got" in *8787*) ok ;; *) ko "el base URL deberia apuntar al puerto configurado (fue: $got)" ;; esac
want "settings.json quedo invalido tras cablear" jq empty "$ROOT_B/.claude/settings.json"

# --- caso C: la unidad systemd lleva las decisiones que protegen el ahorro --
UNIT="$ROOT_B/.config/systemd/user/headroom-proxy.service"
want "no se escribio la unidad en $UNIT" [ -f "$UNIT" ]
if [ -f "$UNIT" ]; then
  want "la unidad debe fijar --mode cache explicitamente (el modo token invalida el prompt caching)" \
    grep -q -- '--mode cache' "$UNIT"
  # StartLimitIntervalSec debe ir en [Unit]: en [Service] systemd lo ignora en
  # silencio y la unidad muere tras 5 arranques en 10 s.
  if awk '/^\[Unit\]/{u=1;next} /^\[/{u=0} u&&/StartLimitIntervalSec=0/{found=1} END{exit !found}' "$UNIT"; then ok; else
    ko "StartLimitIntervalSec=0 debe estar en la seccion [Unit], no en [Service]"
  fi
  want "la unidad debe reintentar (Restart=always)" grep -q 'Restart=always' "$UNIT"
fi

# --- caso D: idempotente ---------------------------------------------------
run_wh "$ROOT_B" 1 >/dev/null 2>&1
want "reejecutar rompio settings.json" jq empty "$ROOT_B/.claude/settings.json"
n="$(jq -r '.env | keys | map(select(. == "ANTHROPIC_BASE_URL")) | length' "$ROOT_B/.claude/settings.json")"
want "ANTHROPIC_BASE_URL duplicada tras reejecutar ($n)" [ "$n" = "1" ]

rm -rf "$ROOT_A" "$ROOT_B"
echo "PASS=$pass FAIL=$fail"
[ "$fail" -eq 0 ]
