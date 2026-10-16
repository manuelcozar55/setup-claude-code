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
# Plantilla con «## Pendientes» vacío y, más abajo, el «## Pendientes y riesgos» que escribe /handoff:
# el primero (vacío) ganaba y lo inyectado perdía los pendientes sin más aviso que «fuera de forma».
printf '# Estado\n## Pendientes\n## Comandos de verificación\n- x\n## Pendientes y riesgos\n- pendiente-real\n' > "$T/dup-vacio.md"
ok "## vacío de plantilla + mismo nombre con contenido → se emite el segundo" "$(nucleo_emitir "$T/dup-vacio.md" | command grep -c 'pendiente-real')" 1
printf '# Estado\n## Pendientes\n- primero\n## Pendientes y riesgos\n- segundo\n' > "$T/dup-lleno.md"
ok "## con contenido repetido → sigue ganando el primero" "$(nucleo_emitir "$T/dup-lleno.md" | command grep -c 'segundo')" 0
# Los marcadores <!-- … --> de la plantilla (Objetivo, Plan) no son contenido: el «## Encargo original» y el
# «## Plan» que escribe /handoff deben entrar aunque la plantilla ya traiga esas secciones con marcador.
printf '# Estado\n## Objetivo\n<!-- marcador -->\n## Plan\n<!-- [x] paso\n   dos líneas -->\n## Encargo original\n- encargo-real\n## Plan\n- plan-real\n' > "$T/dup-marcador.md"
ok "## solo con marcador <!-- --> + mismo nombre con contenido → se emite el segundo" "$(nucleo_emitir "$T/dup-marcador.md" | command grep -c -E 'encargo-real|plan-real')" 2
printf '# Estado\n## Plan\n<!-- a --> texto\n## Plan\n- segundo-plan\n' > "$T/dup-marcador-texto.md"
ok "marcador seguido de texto en la misma línea sí es contenido → gana el primero" "$(nucleo_emitir "$T/dup-marcador-texto.md" | command grep -c 'segundo-plan')" 0
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
# Familias con 1M por defecto (sin sufijo): opus-4-7 en adelante, opus-5+, fable, mythos, sonnet-5+.
for m in claude-opus-4-7 claude-opus-4.8 claude-opus-5 fable-1 mythos-1 claude-sonnet-5-5; do
  ok "$m sin [1m], env 250 000 → 217 000" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 ANTHROPIC_MODEL=$m nucleo_ctx "$T/t.jsonl")" "100000 46"
done
for m in claude-opus-4-6 claude-opus-4-20250514 claude-sonnet-4-6 claude-haiku-4-5; do
  ok "$m sin [1m], env 250 000 → 167 000" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 ANTHROPIC_MODEL=$m nucleo_ctx "$T/t.jsonl")" "100000 59"
done
ok "familia 1M, env sin definir → 967 000" "$(ANTHROPIC_MODEL=claude-opus-4-7 CLAUDE_CODE_AUTO_COMPACT_WINDOW='' nucleo_ctx "$T/t.jsonl")" "100000 10"
ok "familia 1M, env 2 000 000 → tope 1M" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=2000000 ANTHROPIC_MODEL=claude-opus-4-7 nucleo_ctx "$T/t.jsonl")" "100000 10"
ok "familia 1M, env 150 000 → manda el env" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=150000 ANTHROPIC_MODEL=claude-opus-4-7 nucleo_ctx "$T/t.jsonl")" "100000 85"
ok "familia 1M, env no numérico → 1M" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250k ANTHROPIC_MODEL=claude-opus-4-7 nucleo_ctx "$T/t.jsonl")" "100000 10"
printf '{"model": "m[1m]"}\n' >"$HOME/.claude/settings.json"
ok "env 250 000 con [1m] en settings.json → 217 000" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 ANTHROPIC_MODEL='' nucleo_ctx "$T/t.jsonl")" "100000 46"
# El modelo sale del último assistant del transcript: con settings "opus" (alias pelado) y un id 1M ahí, 1M topado por el env.
jq -cn '{type:"assistant",message:{model:"claude-opus-5-5",usage:{input_tokens:100000}}}' >"$T/tm.jsonl"
printf '{"model": "opus"}\n' >"$HOME/.claude/settings.json"
ok "transcript opus-5-5 + settings alias, env 250 000 → 217 000" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 ANTHROPIC_MODEL='' nucleo_ctx "$T/tm.jsonl")" "100000 46"
jq -cn '{type:"assistant",message:{model:"claude-opus-4-6",usage:{input_tokens:100000}}}' >"$T/tm2.jsonl"
ok "transcript opus-4-6 + settings alias, env 250 000 → 167 000" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 ANTHROPIC_MODEL='' nucleo_ctx "$T/tm2.jsonl")" "100000 59"
ok "sin modelo en el transcript, alias en settings → 200k" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 ANTHROPIC_MODEL='' nucleo_ctx "$T/t.jsonl")" "100000 59"
# El [1m] de env o settings vale solo para el modelo que nombra: haiku en el transcript con opus[1m] en settings sigue en 200k.
jq -cn '{type:"assistant",message:{model:"claude-haiku-4-5",usage:{input_tokens:100000}}}' >"$T/tm3.jsonl"
jq -cn '{type:"assistant",message:{model:"claude-sonnet-4-6",usage:{input_tokens:100000}}}' >"$T/tm4.jsonl"
printf '{"model": "opus[1m]"}\n' >"$HOME/.claude/settings.json"
ok "transcript haiku + settings opus[1m] → 167 000" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 ANTHROPIC_MODEL='' nucleo_ctx "$T/tm3.jsonl")" "100000 59"
ok "transcript opus-4-6 + settings opus[1m] → 217 000" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 ANTHROPIC_MODEL='' nucleo_ctx "$T/tm2.jsonl")" "100000 46"
ok "transcript sonnet-4-6 + su [1m] en el env → 217 000" "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=250000 ANTHROPIC_MODEL='claude-sonnet-4-6[1m]' nucleo_ctx "$T/tm4.jsonl")" "100000 46"
# Forma vista en vivo (15-oct): la tarea bajo «## TAREA ACTUAL» con sus secciones en ###. Solo
# con ## se inyectaba el título (148 chars) y el modelo retomaba a ciegas.
A=$T/anidado.md
printf '%s\n' '# Estado global' '## Hecho recientemente' '- cosa vieja' '## TAREA ACTUAL (15-oct): cerrar X' \
  '### Encargo original (literal)' 'ENCARGO-ANIDADO' '### Plan' '- [ ] PLAN-ANIDADO' '### Hechos que corrigen' 'HECHO-AJENO' \
  '### Comandos de verificación' 'make test' >"$A"
S=$(nucleo_emitir "$A")
ok "### bajo TAREA ACTUAL: el encargo llega" "$(command grep -c ENCARGO-ANIDADO <<<"$S")" 1
ok "### bajo TAREA ACTUAL: el plan llega" "$(command grep -c PLAN-ANIDADO <<<"$S")" 1
ok "### bajo TAREA ACTUAL: verificación llega" "$(command grep -c '^make test' <<<"$S")" 1
ok "### fuera de plantilla: no llega" "$(command grep -c HECHO-AJENO <<<"$S")" 0
# Un ### sin clave de plantilla es contenido: «### Fase 1» dentro de «## Plan» cortaba el resto del plan.
F=$T/fases.md
printf '%s\n' '# Estado' '## Plan' '### Fase 1' '- [ ] FASE-A' '### Fase 2' '- [ ] FASE-B' >"$F"
S=$(nucleo_emitir "$F")
ok "### bajo ## Plan: las cuatro líneas llegan" "$(command grep -c '^### Fase [12]$\|FASE-[AB]' <<<"$S")" 4
ok "### bajo ## Plan: no es fuera de forma" "$(command grep -c 'fuera de forma' <<<"$S")" 0
ok "### bajo ## Plan: no pide leer el fichero" "$(command grep -c '^\[LEE ' <<<"$S")" 0
# Cercas: una línea ```x``` no abre bloque, y una cerca sin cerrar no se traga las secciones siguientes.
# Tragadas, llegaban como cuerpo del Objetivo: lo delata la sección ajena del final, que se cuela.
F=$T/cerca1.md
# shellcheck disable=SC2016 # las comillas invertidas son una cerca markdown literal, no una sustitución
printf '%s\n' '# Estado' '## Objetivo' '```x```' '## Plan' '- [ ] PLAN-TRAS-CERCA' '## Hecho' 'HECHO-AJENO' >"$F"
ok "cerca de una línea: el Plan llega y lo ajeno no" "$(nucleo_emitir "$F" | command grep -c 'PLAN-TRAS-CERCA\|HECHO-AJENO')" 1
F=$T/cerca2.md
printf '%s\n' '# Estado' '## Objetivo' '```' 'código sin cerrar' '## Comandos de verificación' 'make CMD-TRAS-CERCA' \
  '## Hecho' 'HECHO-AJENO' >"$F"
ok "cerca sin cerrar: los comandos llegan y lo ajeno no" "$(nucleo_emitir "$F" | command grep -c 'CMD-TRAS-CERCA\|HECHO-AJENO')" 1
# ### con clave aún no vista abre su sección aunque cuelgue de un ## de plantilla: plegada en Plan,
# caía con el tope de 3 000 bytes de Plan (el relleno lo agota).
printf -v R '%*s' 2980 ''; F=$T/hermanas.md
printf '%s\n' '# Estado' '## Plan' '- [ ] p' "${R// /r}" '### Paso actual' 'PA-HERMANA' '### Pendientes' '- Q-HERMANA' >"$F"
S=$(nucleo_emitir "$F")
ok "### hermanas bajo ## Plan: secciones propias" "$(command grep -c '^### Paso actual$\|^PA-HERMANA$\|^### Pendientes$\|^- Q-HERMANA$' <<<"$S")" 4
ok "### hermanas bajo ## Plan: nada recortado" "$(command grep -c 'recortado' <<<"$S")" 0
# Bajo un ## que no es de plantilla, un ### sin clave cierra la sección y cuenta en fuera: la historia
# cerrada («### Hecho») no puede colarse como pendiente sin aviso.
F=$T/nota.md
printf '%s\n' '# Estado' '## TAREA ACTUAL' '### Encargo original' 'E-ENC' '### Nota' 'N-NOTA' '### Plan' '- [ ] X-PLAN' >"$F"
S=$(nucleo_emitir "$F")
ok "### sin clave bajo TAREA ACTUAL: cierra la sección" "$(command grep -c 'E-ENC\|N-NOTA\|X-PLAN' <<<"$S")" 2
ok "### sin clave bajo TAREA ACTUAL: cuenta en fuera" "$(command grep -c '^\[fuera de forma: 2 secciones' <<<"$S")" 1
F=$T/hecho.md
printf '%s\n' '# Estado' '## TAREA ACTUAL' '### Pendientes' '- P-PEND' '### Hecho' 'HECHO-AJENO' >"$F"
S=$(nucleo_emitir "$F")
ok "### Hecho tras Pendientes: no se cuela" "$(command grep -c 'P-PEND\|HECHO-AJENO' <<<"$S")" 1
ok "### Hecho tras Pendientes: avisa fuera de forma" "$(command grep -c '^\[fuera de forma: 2 secciones' <<<"$S")" 1
# Lo mismo con un subapartado («### Fase 1» tras «### Plan»): solo el nombre lo distingue de «### Hecho», así
# que también cierra, pero la pérdida se ve: la salida pide leer el fichero y sugiere ####.
F=$T/fase-perdida.md
printf '%s\n' '# E' '## TAREA ACTUAL' '### Plan' '- p' '### Fase 1' '- FASE-A' '### Pendientes' '- P' >"$F"
S=$(nucleo_emitir "$F")
ok "### sin clave tras Plan bajo TAREA ACTUAL: no llega" "$(command grep -c FASE-A <<<"$S")" 0
ok "### sin clave cierra una sección: pide leer el fichero" "$(command grep -c '^\[LEE ' <<<"$S")" 1
ok "### sin clave cierra una sección: sugiere ####" "$(command grep -c 'escríbelo con ####)\]$' <<<"$S")" 1
# Cercas equilibradas: un «## Plan» citado en un bloque es inerte y el Plan real llega como sección.
F=$T/cerca-citada.md
# shellcheck disable=SC2016 # las comillas invertidas son una cerca markdown literal, no una sustitución
printf '%s\n' '# Estado' '## Objetivo' '```md' '## Plan' 'CITADO' '```' '## Plan' '- [ ] REAL' '## Hecho' 'AJ-CITA' >"$F"
S=$(nucleo_emitir "$F")
ok "cerca con ## Plan citado: el Plan real llega" "$(command grep -c 'CITADO\|REAL' <<<"$S")" 2
ok "cerca con ## Plan citado: lo ajeno no" "$(command grep -c AJ-CITA <<<"$S")" 0
# Cerca sin cerrar bajo ###: se ignoran todas, así que ni ## ajeno ni ### se tragan.
F=$T/cerca-impar.md
printf '%s\n' '# Estado' '## TAREA ACTUAL' '### Plan' '- [ ] P-IMPAR' '```' '## Hecho' 'AJ-IMPAR' '### Pendientes' '- Q-IMPAR' >"$F"
S=$(nucleo_emitir "$F")
ok "cerca impar: Pendientes llega como sección" "$(command grep -c '^### Pendientes$\|Q-IMPAR' <<<"$S")" 2
ok "cerca impar: lo ajeno no" "$(command grep -c AJ-IMPAR <<<"$S")" 0
# Cerca de cuatro acentos (y con sangría): también conmuta.
F=$T/cerca4.md
# shellcheck disable=SC2016 # las comillas invertidas son una cerca markdown literal, no una sustitución
printf '%s\n' '# Estado' '## Comandos de verificación' '````' '# comentario' 'make CMD-CUATRO' '````' \
  '## Pendientes' '  ```sh' '# otro' '  ```' '- Q-SANGRIA' >"$F"
ok "cerca de cuatro y con sangría: los comandos llegan" "$(nucleo_emitir "$F" | command grep -c 'CMD-CUATRO\|Q-SANGRIA')" 2
# Cuatro espacios también son cerca: en un nucleo lo común es un paso numerado con su bloque sangrado, y si
# no contara su # comentario cortaría los comandos.
F=$T/cerca-paso.md
# shellcheck disable=SC2016 # las comillas invertidas son una cerca markdown literal, no una sustitución
printf '%s\n' '## Plan' '1. correr' '    ```sh' '# c' 'make X' '    ```' '- Q' '## Pendientes' '- r' >"$F"
ok "cerca sangrada cuatro espacios: el Plan sigue y Pendientes llega" "$(nucleo_emitir "$F" | command grep -c '^make X$\|^- Q$\|^## Pendientes$\|^- r$')" 4
# Límite declarado: un ``` dentro de un bloque sangrado de CommonMark cuenta como cerca; aquí deja la paridad
# impar, y se avisa.
F=$T/cerca-sangrada.md
# shellcheck disable=SC2016 # las comillas invertidas son una cerca markdown literal, no una sustitución
printf '%s\n' '# Estado' '## Objetivo' '    ```' '## Comandos de verificación' '```sh' '# comentario' 'make CMD-SANGRADA' '```' \
  '## Plan' '- [ ] P-SANGRADA' >"$F"
ok "cuatro espacios cuentan: entran en la paridad" "$(nucleo_emitir "$F" | command grep -c '^\[cercas sin equilibrar')" 1
# Cercas impares: se ignoran, pero no en silencio.
ok "cerca sin cerrar: avisa" "$(nucleo_emitir "$T/cerca2.md" | command grep -c '^\[cercas sin equilibrar: se ignoran')" 1
ok "cerca sin cerrar: pide leer el fichero" "$(nucleo_emitir "$T/cerca2.md" | command grep -c '^\[LEE ')" 1
ok "cercas equilibradas: sin aviso" "$(nucleo_emitir "$T/cerca4.md" | command grep -c 'cercas sin equilibrar')" 0

# --- #8: .claude enlazado (o estado/) a otro sitio: los tres componentes se miran y la ruta resuelta queda en el repo ---
mkdir -p "$T/ajeno/estado" "$T/r8a" "$T/r8b/.claude" "$T/r8c/.claude/estado" "$T/r8d/.claude/estado"
printf '## Objetivo\nAJENO\n' >"$T/ajeno/estado/nucleo.md"
ln -s "$T/ajeno" "$T/r8a/.claude"
ln -s "$T/ajeno/estado" "$T/r8b/.claude/estado"
ln -s "$T/ajeno/estado/nucleo.md" "$T/r8c/.claude/estado/nucleo.md"
printf '## Objetivo\nPROPIO\n' >"$T/r8d/.claude/estado/nucleo.md"
ok "enlazado: .claude es un symlink" "$(nucleo_enlazado "$T/r8a" && echo si)" si
ok "enlazado: estado es un symlink" "$(nucleo_enlazado "$T/r8b" && echo si)" si
ok "enlazado: nucleo.md es un symlink" "$(nucleo_enlazado "$T/r8c" && echo si)" si
ok "enlazado: árbol propio sin enlaces → no" "$(nucleo_enlazado "$T/r8d" && echo si || echo no)" no
ln -s "$T/r8d" "$T/r8e"
ok "enlazado: la raíz misma puede ser un symlink" "$(nucleo_enlazado "$T/r8e" && echo si || echo no)" no

exit $FAIL
