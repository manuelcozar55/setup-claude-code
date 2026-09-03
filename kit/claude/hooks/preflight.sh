#!/usr/bin/env bash
# SessionStart: recupera headroom si esta caido.
#
# ─────────────────────────────────────────────────────────────────────────────
# LEE ESTO ANTES DE TOCAR NADA. La version anterior de este hook hacia:
#
#     pkill -f "headroom proxy"
#     nohup headroom proxy --port $P --mode cache --budget 20 ... &
#
# y provoco un incidente real el 2026-08-17 (NRestarts=92 y contando):
#
#  1. `pkill` mata el proceso que supervisa systemd. La unidad tiene
#     Restart=always + RestartSec=3 + StartLimitIntervalSec=0, asi que systemd
#     levanta INMEDIATAMENTE el suyo... mientras el `nohup` levanta otro. Los dos
#     pelean por el 8787, el que pierde muere con
#     `[Errno 98] address already in use` y systemd lo relanza cada 3 s PARA
#     SIEMPRE. Es el mismo bug que acumulo >20.000 reinicios en el equipo
#     anterior, y la unidad systemd lo documenta en su cabecera: la unidad es la
#     UNICA fuente de verdad del proxy.
#
#  2. `--budget 20` BLOQUEA peticiones al agotarse. El gasto acumulado de esta
#     maquina va por ~1.300 $, asi que un budget de 20 $ nace agotado. Por eso el
#     proxy devolvia HTTP 200 con cuerpo VACIO en ~5 ms sin llamar nunca a la API
#     (`upstream_connect: null`, `tok_out=0`, `transforms=none`) y Claude Code
#     mostraba "API returned an empty or malformed response (HTTP 200)".
#     No hay budget a proposito. No lo vuelvas a poner aqui.
#
#  3. El bucle `for i in $(seq 1 20); do sleep 1` bloqueaba el arranque de la
#     sesion hasta 20 s. Un hook de SessionStart NO debe esperar a nada.
#
# Reglas que salen de ahi, y que este script respeta:
#   - Arrancar/parar el proxy SOLO por systemd. Nunca pkill, nunca nohup.
#   - Los flags del proxy viven en la unidad, no aqui.
#   - No bloquear el arranque de la sesion. Nunca.
#   - Salir 0 siempre: este hook no puede impedir que arranque una sesion.
# ─────────────────────────────────────────────────────────────────────────────
set -uo pipefail
M=""

# --- headroom: recuperar por systemd, sin bloquear ---------------------------
# Solo si alguien ha declarado el opt-in. Sin nadie enrutado, levantar el proxy
# son 1,3 GB de RSS para nadie: medido el 2026-09-02, 0,813 % de ahorro de por
# vida a cambio de 497 ms por peticion, y el 81,5 % de las del dia no ahorraron.
_headroom_optin() {
  [ -n "${ANTHROPIC_BASE_URL:-}" ] && return 0
  command grep -qs ANTHROPIC_BASE_URL \
    "${CLAUDE_HOME:-$HOME/.claude}/settings.json" \
    "${CLAUDE_HOME:-$HOME/.claude}/settings.local.json" \
    "$PWD/.claude/settings.local.json"
}

if _headroom_optin && ! curl -sf -m 2 "http://127.0.0.1:${HEADROOM_PORT:-8787}/readyz" >/dev/null 2>&1; then
  # reset-failed es lo que desatasca una unidad que se quedo en bucle de bind.
  systemctl --user reset-failed headroom-proxy.service >/dev/null 2>&1
  systemctl --user start        headroom-proxy.service >/dev/null 2>&1
  # Un unico sondeo corto, solo para poder informar. Si no esta listo, da igual:
  # systemd sigue reintentando por su cuenta y Claude Code no depende del proxy.
  sleep 1
  if curl -sf -m 2 "http://127.0.0.1:${HEADROOM_PORT:-8787}/readyz" >/dev/null 2>&1; then
    M="Headroom estaba caido: systemd lo ha levantado."
  else
    M="Headroom caido y hay enrutado declarado: systemd reintentando. Para trabajar sin el, ANTHROPIC_BASE_URL= claude."
  fi
fi

[ -n "$M" ] && echo "$M"
exit 0
