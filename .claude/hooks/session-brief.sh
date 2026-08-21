#!/usr/bin/env bash
# SessionStart — pone delante el oraculo del proyecto y los errores ya cometidos aqui.
#
# Por que existe: knowledge/ solo sirve si se consulta. Dejarlo a criterio del agente es
# feedforward sin garantia; cargarlo al arrancar es determinista. Es barato porque son dos
# ficheros pequenos, no el directorio entero: progressive disclosure, punteros y no datos.
#
# Contrato: exit 0 SIEMPRE, sin red, < 100 ms. Solo escribe en stdout.
set -uo pipefail

payload=$(cat 2>/dev/null) || true
if command -v jq >/dev/null 2>&1 && [ -n "${payload:-}" ]; then
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
fi
[ -n "${cwd:-}" ] || cwd="$PWD"

K="$cwd/knowledge"
[ -d "$K" ] || exit 0

echo "── mcharness ──"

# 1. El oraculo, que es lo unico que cierra el lazo.
if [ -f "$K/ORACLES.md" ]; then
  line=$(grep -m1 '^| \*\*mcharness\*\*' "$K/ORACLES.md" 2>/dev/null || true)
  if [ -n "$line" ]; then
    cmd=$(printf '%s' "$line" | awk -F'|' '{print $3}' | tr -d ' `')
    [ -n "$cmd" ] && echo "Oráculo: $cmd   (ejecútalo antes de dar nada por hecho)"
  fi
fi

# 2. Los errores ya cometidos aqui: titulares, no el fichero entero.
if [ -f "$K/MISTAKES.md" ]; then
  n=$(grep -c '^## M-' "$K/MISTAKES.md" 2>/dev/null || echo 0)
  if [ "$n" -gt 0 ]; then
    echo "Errores registrados ($n) — detalle en knowledge/MISTAKES.md:"
    grep '^## M-' "$K/MISTAKES.md" 2>/dev/null | head -5 | sed 's/^## /  · /'
  fi
fi

# 3. Perfil, si lo hay.
if [ -f "$cwd/config/profile.yaml" ]; then
  lvl=$(grep -m1 '^explain:' "$cwd/config/profile.yaml" 2>/dev/null | awk '{print $2}')
  [ -n "$lvl" ] && echo "Coach: explain=$lvl"
fi

exit 0
