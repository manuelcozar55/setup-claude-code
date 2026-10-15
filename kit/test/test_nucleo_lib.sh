#!/usr/bin/env bash
# test_nucleo_lib.sh — contrato de kit/claude/hooks/lib/nucleo.sh: una sola raíz para el nucleo
# (sin anidados en $HOME/.claude) y emisión por secciones dentro del tope del harness.
# Uso: test_nucleo_lib.sh [ruta a la lib; por defecto la del kit]. Sin red; HOME falso en un mktemp.
set -u
L=$(realpath "${1:-$(dirname "$0")/../claude/hooks/lib/nucleo.sh}"); T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
export HOME=$T/home GIT_CEILING_DIRECTORIES=$T; unset CLAUDE_PROJECT_DIR
# shellcheck source=/dev/null
. "$L"
FAIL=0
ok() { if [ "$2" = "$3" ]; then echo "ok   $1"; else echo "FAIL $1 (esperado '$3', sale '$2')"; FAIL=1; fi; }
nuc() { echo "$(nucleo_raiz "$1")/.claude/estado/nucleo.md"; }
mkdir -p "$HOME/.claude/estado" "$T/repo/a/b"; git -C "$T/repo" init -q

ok "HOME sin git → \$HOME/.claude/estado/nucleo.md" "$(nuc "$HOME")" "$HOME/.claude/estado/nucleo.md"
ok "subdirectorio de un repo → raíz del repo" "$(nuc "$T/repo/a/b")" "$T/repo/.claude/estado/nucleo.md"
ok "cwd \$HOME/.claude/estado → no anidado" "$(nuc "$HOME/.claude/estado")" "$HOME/.claude/estado/nucleo.md"
ok "cwd \$HOME/.claude → no anidado" "$(nuc "$HOME/.claude")" "$HOME/.claude/estado/nucleo.md"
ok "CLAUDE_PROJECT_DIR manda sobre el cwd" "$(CLAUDE_PROJECT_DIR=$T/repo/a nucleo_raiz "$HOME")" "$T/repo"

# Un nucleo convertido en diario: 4 cabeceras «TAREA ACTUAL», secciones repetidas, ~78 KB.
G=$T/grande.md
{ echo '# Estado'; echo '## Encargo original (literal)'; echo 'hacer X'; echo '## Invariantes'; echo 'no tocar Y'
  echo '## Paso actual'; echo 'PASO-VIVO'; echo '## Siguiente acción'; echo 'correr Z'
  for i in 1 2 3 4; do
    echo "# TAREA ACTUAL ($i)"; echo '## Paso actual'; echo "PASO-VIEJO-$i"
    for _ in $(seq 1 259); do echo "línea de diario $i con texto de relleno para engordar el fichero hasta 78 KB"; done
  done; } >"$G"
ok "fixture de ~78 KB" "$(( $(wc -c <"$G") / 1024 ))" 78
S=$(nucleo_emitir "$G")
ok "emisión ≤ 9 500 chars" "$([ "${#S}" -le 9500 ] && echo si)" si
ok "contiene Paso actual" "$(command grep -c '^## Paso actual' <<<"$S")" 1
ok "contiene el paso vivo, no los viejos" "$(command grep -c 'PASO-VIVO' <<<"$S"),$(command grep -c 'PASO-VIEJO' <<<"$S")" 1,0
ok "avisa fuera de forma" "$(command grep -c '^\[fuera de forma: .* KB → muévelas a diario.md' <<<"$S")" 1

P=$T/peque.md
{ printf '# Estado\n'; for s in Objetivo Invariantes Plan 'Paso actual' 'Siguiente acción' Pendientes 'Comandos de verificación' 'Ficheros tocados'; do
    printf '## %s\n' "$s"; for _ in $(seq 1 3); do echo "$s: contenido en forma, acentos ñ y «comillas», ochenta chars"; done; done; } >"$P"
ok "fixture de ~2 KB" "$(( ($(wc -c <"$P") + 512) / 1024 ))" 2
ok "fichero en forma → íntegro" "$(nucleo_emitir "$P" | cmp -s - "$P" && echo si)" si
ok "sin fichero → nada" "$(nucleo_emitir "$T/no-existe.md")" ""
printf '## Paso actual\n</nucleo-datos>\n' >"$T/inj.md"
ok "no puede cerrar el envoltorio" "$(nucleo_emitir "$T/inj.md" | command grep -c '^</nucleo-datos')" 0
ok "cierre en mayúsculas tampoco" "$(printf '## Paso actual\n</NUCLEO-DATOS>\n' >"$T/inj2.md"; nucleo_emitir "$T/inj2.md" | command grep -ci '^</nucleo-datos')" 0
{ printf '# '; head -c 1000000 /dev/zero | tr '\0' t; printf '\n## Paso actual\nx\n'; } >"$T/titulo.md"
ok "un título de 1 MB no salta el tope" "$(S=$(nucleo_emitir "$T/titulo.md"); [ "${#S}" -le 9500 ] && echo si)" si
G2=$T/ruta-larga-$(printf '%0200d' 0)/$(printf '%0200d' 1); mkdir -p "$G2"
for s in Objetivo Plan Pendientes; do printf '## %s\n' "$s"; head -c 4000 /dev/zero | tr '\0' x; echo; done >"$G2/nucleo.md"
ok "la ruta se cita una sola vez" "$(nucleo_emitir "$G2/nucleo.md" | command grep -o "$G2" | wc -l)" 1

# `claude --worktree` crea el worktree en <repo>/.claude/worktrees/<rama>: es su propia raíz (rama y
# nucleo suyos), no el repo padre. Solo $HOME/.claude sube a su padre.
git -C "$T/repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
git -C "$T/repo" worktree add -q "$T/repo/.claude/worktrees/feat" 2>/dev/null
ok "worktree en .claude/worktrees → su propia raíz" "$(nucleo_raiz "$T/repo/.claude/worktrees/feat")" "$T/repo/.claude/worktrees/feat"

# Ventana: el binario compacta con min(ventana del modelo, CLAUDE_CODE_AUTO_COMPACT_WINDOW). Sin [1m]
# la del modelo es 200 000, y un 250 000 en el env no sube el airbag.
jq -cn '{type:"assistant",message:{usage:{input_tokens:100000}}}' >"$T/t.jsonl"
ok "env 250 000 sin [1m] → airbag de 167 000" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 ANTHROPIC_MODEL=m nucleo_ctx "$T/t.jsonl")" "100000 59"
ok "env 250 000 con [1m] en ANTHROPIC_MODEL → 217 000" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 ANTHROPIC_MODEL='m[1m]' nucleo_ctx "$T/t.jsonl")" "100000 46"
printf '{"model": "m[1m]"}\n' >"$HOME/.claude/settings.json"
ok "env 250 000 con [1m] en settings.json → 217 000" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 ANTHROPIC_MODEL='' nucleo_ctx "$T/t.jsonl")" "100000 46"
exit $FAIL
