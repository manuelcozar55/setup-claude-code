#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0; skipped=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

export CLAUDE_HOME="$tmp/dot"
# Con `set -e` y la salida a /dev/null, un fallo aqui mataba la suite con rc=1 y CERO salida:
# rojo correcto pero imposible de diagnosticar. Se captura para que el rojo diga por que.
set +e; bash "$KIT/install.sh" >"$tmp/install.log" 2>&1; irc=$?; set -e
ck "$irc" "0" "install.sh sale 0 en un CLAUDE_HOME limpio$([ "$irc" -eq 0 ] || printf ' -- %s' "$(tail -1 "$tmp/install.log")")"
ck "$([ -f "$CLAUDE_HOME/CLAUDE.md" ] && echo y)" "y" "instala CLAUDE.md"
ck "$([ -f "$CLAUDE_HOME/settings.json" ] && echo y)" "y" "instala settings.json"
ck "$([ -x "$CLAUDE_HOME/hooks/branch-guard.sh" ] && echo y)" "y" "hook ejecutable"
ck "$([ -f "$CLAUDE_HOME/sentinel/sentinel_preflight.py" ] && echo y)" "y" "instala sentinel"

# Idempotencia + backup: modifica un fichero que el KIT posee, reinstala, debe backupear.
# Se usa .gitleaks.toml y no CLAUDE.md: CLAUDE.md son TUS instrucciones y desde ahora no se
# pisa (ver abajo), asi que ya no genera backup -- genera CLAUDE.kit.md.
echo "# MOD" >> "$CLAUDE_HOME/.gitleaks.toml"
set +e; bash "$KIT/install.sh" >/dev/null 2>&1; rrc=$?; set -e
ck "$(find "$CLAUDE_HOME/backups" -mindepth 2 -maxdepth 2 -name .gitleaks.toml 2>/dev/null | wc -l | tr -d ' ')" "1" "backup creado al reinstalar"
ck "$rrc" "0" "reinstalar no falla"

# --- Reinstalar NO destruye tu configuracion personal -----------------------
# El fallo que esto cierra, medido en una maquina real: un `install.sh --apply` sobre una
# instalacion existente reemplazaba settings.json entero y se llevaba en silencio
# ENABLE_TOOL_SEARCH (~30k de contexto por sesion), el ANTHROPIC_MODEL con el sufijo de la
# ventana de 1M, CLAUDE_CODE_AUTO_COMPACT_WINDOW y tres limites mas. Y reemplazaba CLAUDE.md,
# que es prosa escrita a mano y no se puede fusionar.
if command -v jq >/dev/null 2>&1; then
  tmp2="$(mktemp)"
  jq '.env.MI_CLAVE = "mia" | .model = "fable[1m]" | .statusLine = {"command":"mi-statusline"}
      | .permissions.allow += ["Bash(mi-comando *)"]' \
     "$CLAUDE_HOME/settings.json" > "$tmp2" && mv "$tmp2" "$CLAUDE_HOME/settings.json"
  printf '# mis instrucciones a mano\nno me borres\n' > "$CLAUDE_HOME/CLAUDE.md"
  rm -f "$CLAUDE_HOME/CLAUDE.kit.md"
  set +e; bash "$KIT/install.sh" >/dev/null 2>&1; set -e

  ck "$(jq -r '.env.MI_CLAVE // "AUSENTE"' "$CLAUDE_HOME/settings.json")" "mia" "reinstalar conserva tus claves de env"
  ck "$(jq -r '.model // "AUSENTE"' "$CLAUDE_HOME/settings.json")" "fable[1m]" "reinstalar conserva tu model"
  ck "$(jq -r '.statusLine.command // "AUSENTE"' "$CLAUDE_HOME/settings.json")" "mi-statusline" "reinstalar conserva claves que el kit no gestiona"
  ck "$(jq -r '[.permissions.allow[] | select(. == "Bash(mi-comando *)")] | length' "$CLAUDE_HOME/settings.json")" "1" "reinstalar conserva tus permisos allow"
  ck "$(jq -r '[.permissions.deny[] | select(. == "Bash(git push -*f *)")] | length' "$CLAUDE_HOME/settings.json")" "1" "reinstalar mantiene los deny del kit (union, no reemplazo)"
  ck "$(jq -r '[.hooks.PreToolUse[].hooks[].command | select(test("block-dangerous"))] | length' "$CLAUDE_HOME/settings.json")" "1" "los hooks los sigue poniendo el kit"
  ck "$(grep -c 'no me borres' "$CLAUDE_HOME/CLAUDE.md")" "1" "reinstalar NO pisa tu CLAUDE.md"
  ck "$([ -f "$CLAUDE_HOME/CLAUDE.kit.md" ] && echo y)" "y" "la version del kit queda al lado en CLAUDE.kit.md"
else
  # Este salto era INVISIBLE para el agregado: se imprimia "skip - ..." pero el resumen
  # seguia diciendo "== 11 passed, 0 failed ==", sin ningun skipped y con rc=0. Ocho
  # comprobaciones que NO se habian ejecutado se leian como aprobadas -- ni fallo ni
  # salto, el peor de los tres. Ahora se cuenta, y kit/sumar-tests.sh baja el veredicto
  # agregado a "NO SE PUDO VERIFICAR", que es exactamente lo que es.
  # Cuenta como UN bloque saltado, no como 8: el numero de checks del bloque cambia cada
  # vez que alguien anade uno, y un contador con ese numero a mano acabaria mintiendo por
  # el otro lado. La magnitud va en el mensaje, que no gobierna ninguna cifra.
  echo "skip - jq ausente: no se prueba la fusion de settings.json (8 comprobaciones sin ejecutar)"
  skipped=$((skipped+1))
fi

# Regresion 2026-09-02: un __pycache__ dentro del kit rompia el bucle `cp` de install.sh
# ("cp: -r not specified; omitting directory"), el instalador salia rc=1 y dejaba la
# instalacion a medias -- y con ella test_doctor.sh en rojo por una causa ajena al doctor.
# Los bucles filtran con -f: un directorio se ignora en vez de matar la instalacion.
cp -a "$KIT" "$tmp/kitcopy"
mkdir -p "$tmp/kitcopy/sentinel/__pycache__" "$tmp/kitcopy/claude/agents/__pycache__"
: > "$tmp/kitcopy/sentinel/__pycache__/sentinel_preflight.cpython-314.pyc"
set +e; CLAUDE_HOME="$tmp/dot2" bash "$tmp/kitcopy/install.sh" >"$tmp/pyc.log" 2>&1; prc=$?; set -e
ck "$prc" "0" "un __pycache__ en el kit no rompe la instalacion"
ck "$(grep -c 'omitting directory' "$tmp/pyc.log" || true)" "0" "install.sh no intenta copiar directorios"
ck "$([ -f "$tmp/dot2/sentinel/sentinel_preflight.py" ] && echo y)" "y" "sentinel se instala con __pycache__ presente"
ck "$([ -d "$tmp/dot2/sentinel/__pycache__" ] && echo y || echo n)" "n" "el __pycache__ no viaja a CLAUDE_HOME"

# El campo skipped solo aparece cuando lo hay: asi la linea de una corrida normal no
# cambia (mismo formato que ya leen kit/sumar-tests.sh y CI), y cuando algo se salta
# se ve. Mismo criterio que test_doc_claims.sh.
if [ "$skipped" -gt 0 ]; then
  echo "== $pass passed, $fail failed, $skipped skipped =="
else
  echo "== $pass passed, $fail failed =="
fi
[ "$fail" -eq 0 ]
