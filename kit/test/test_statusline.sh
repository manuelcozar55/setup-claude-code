#!/usr/bin/env bash
# test_statusline.sh — contrato de la statusline del kit (kit/claude/statusline-command.sh):
#   - la ruta de trabajo sale COMPLETA, sin abreviar segmentos ni elipsis
#   - el repositorio git sale como NOMBRE del proyecto (decision explicita), no ruta
#   - dos lineas: modelo/ruta/git arriba; contexto (gris) y limites (azul) abajo
#   - si una linea no cabe en COLUMNS se parte por los "|" sin perder nada
#
# Modelo de fallo que cubre (los dos eran reales antes de 2026-08-31):
#   1. current-working-dir con metadata.segments="1"  -> ".../.claude"
#   2. flexMode "full-minus-40" + recorte de linea    -> "... |" a mitad de ruta
# ok/bad solo imprimen y nunca fallan: "A && ok || bad" es seguro aqui.
# shellcheck disable=SC2015
set -u

SL="$(cd "$(dirname "$0")/.." && pwd)/claude/statusline-command.sh"
fails=0
tests=0

# La barra pinta con ANSI, y la antigua (ccstatusline) sustituia los espacios por NBSP (U+00A0,
# bytes c2 a0) para que el terminal no los colapse: hay que normalizar ambos o
# ninguna asercion con espacio ASCII casa.
normalize() { sed -e 's/\x1b\[[0-9;]*m//g' -e 's/\xc2\xa0/ /g'; }

mkinput() { # $1 = cwd
  jq -n --arg cwd "$1" \
        --argjson r5 "$(( $(date +%s) + 11580 ))" \
        --argjson r7 "$(( $(date +%s) + 194400 ))" '{
    hook_event_name:"Status", session_id:"statusline-test",
    transcript_path:"/nonexistent/transcript.jsonl", cwd:$cwd,
    model:{id:"claude-opus-5[1m]", display_name:"Opus 5 (1M context)"},
    workspace:{current_dir:$cwd, project_dir:$cwd},
    version:"2.0.0", output_style:{name:"default"}, exceeds_200k_tokens:false,
    context_window:{current_usage:{input_tokens:2, output_tokens:16,
      cache_creation_input_tokens:1440, cache_read_input_tokens:79610}},
    rate_limits:{ five_hour:{used_percentage:37.4, resets_at:$r5},
                  seven_day:{used_percentage:12.9, resets_at:$r7} }
  }'
}

# COLUMNS fijo: sin el, el wrapper toma el ancho del terminal que corre el test
run() { mkinput "$1" | COLUMNS=100000 bash "$SL" 2>/dev/null | normalize; }

# los contadores «resets in XhYm» avanzan mientras corre el test: fuera para comparar
sin_contadores() { sed -e 's/(resets in [^)]*)/(resets in R)/g'; }

ok()   { tests=$((tests+1)); printf '  PASS  %s\n' "$1"; }
bad()  { tests=$((tests+1)); fails=$((fails+1)); printf '  FAIL  %s\n     -> %s\n' "$1" "$2"; }
assert_has()   { case "$3" in *"$2"*) ok "$1";; *) bad "$1" "no contiene «$2» en: $3";; esac; }
assert_hasnt() { case "$3" in *"$2"*) bad "$1" "contiene «$2» en: $3";; *) ok "$1";; esac; }

# --- entorno de prueba: repo con ruta larga, y un directorio sin git ------------
TMP="$(mktemp -d)"
cleanup() { [ -n "${TMP:-}" ] && [ -d "$TMP" ] && rm -r -- "$TMP"; }
trap cleanup EXIT
DEEP="$TMP/nivel-uno/nivel-dos/nivel-tres/nivel-cuatro/nivel-cinco/repositorio-con-nombre-largo"
mkdir -p "$DEEP"
git -C "$DEEP" init -q -b rama-de-prueba-con-nombre-largo
git -C "$DEEP" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
NOGIT="$TMP/sin-repositorio"; mkdir -p "$NOGIT"

echo "== 1. repo con ruta larga ($(printf '%s' "$DEEP" | wc -c) chars) =="
OUT="$(run "$DEEP")"
echo "     $OUT"
assert_has   "cwd larga completa"  "$DEEP"                                       "$OUT"
assert_has   "repo = nombre solo"  "| repositorio-con-nombre-largo |"            "$OUT"
assert_has   "rama completa"       "rama-de-prueba-con-nombre-largo"             "$OUT"
assert_hasnt "sin abreviatura"     ".../"                                        "$OUT"
assert_hasnt "sin elipsis ascii"   "..."                                         "$OUT"
assert_hasnt "sin elipsis unicode" "…"                                           "$OUT"

echo "== 2. subdirectorio del repo (cwd != raiz) =="
mkdir -p "$DEEP/sub/carpeta"
OUT="$(run "$DEEP/sub/carpeta")"
echo "     $OUT"
assert_has "cwd = subdirectorio"    "$DEEP/sub/carpeta"                "$OUT"
assert_has "repo = raiz, no subdir" "| repositorio-con-nombre-largo |" "$OUT"
assert_hasnt "repo no es 'carpeta'" "| carpeta |"                      "$OUT"

echo "== 3. directorio sin repositorio =="
OUT="$(run "$NOGIT")"
echo "     $OUT"
assert_has   "cwd completa"        "$NOGIT" "$OUT"
assert_has   "raiz -> «no git»"    "no git" "$OUT"
assert_hasnt "sin separador doble" "|  |"   "$OUT"

echo "== 4. disposicion y colores =="
OUT="$(run "$DEEP" | sin_contadores)"
L1=$(printf '%s\n' "$OUT" | sed -n 1p); L2=$(printf '%s\n' "$OUT" | sed -n 2p)
[ "$(printf '%s\n' "$OUT" | wc -l)" -eq 2 ] && ok "dos lineas" || bad "dos lineas" "$OUT"
case "$L1" in "Opus 5 | $DEEP | "*) ok "linea 1 empieza por el modelo, sin «Model:»";; *) bad "linea 1" "$L1";; esac
assert_hasnt "contexto fuera de la linea 1" "Ctx" "$L1"
[ "$L2" = "Ctx: 81.1k | 5h:37% (resets in R) | 7d:13% (resets in R)" ] \
  && ok "linea 2 = contexto y limites" || bad "linea 2" "$L2"
RAW="$(mkinput "$DEEP" | COLUMNS=100000 bash "$SL" 2>/dev/null)"
assert_has "Ctx en gris"  $'\e[38;5;59mCtx: 81.1k' "$RAW"
assert_has "5h en azul"   $'\e[34m5h:37%'          "$RAW"
assert_has "7d en azul"   $'\e[34m7d:13%'          "$RAW"

echo "== 5. linea larga: se parte en varias, sin recortar ni perder nada =="
aplanar() { tr '\n' '\001' | sed 's/\x01$//; s/\x01/ | /g'; }
UNA="$(run "$DEEP/sub/carpeta" | sin_contadores | aplanar)"
for W in 80 50; do
  OUT="$(mkinput "$DEEP/sub/carpeta" | COLUMNS=$W bash "$SL" 2>/dev/null | normalize | sin_contadores)"
  [ "$(printf '%s\n' "$OUT" | wc -l)" -gt 2 ] && ok "ancho $W: varias lineas" || bad "ancho $W" "una sola linea: $OUT"
  # length() de mawk cuenta bytes y parte los caracteres UTF-8: se mide con ${#} de bash.
  LARGA=$(export LC_ALL=C.UTF-8; while IFS= read -r l; do
    if [ "${#l}" -gt $((W-6)) ] && [[ $l == *" | "* ]]; then printf '%s\n' "$l"; break; fi
  done <<< "$OUT")
  [ -z "$LARGA" ] && ok "ancho $W: ninguna linea partible pasa de $((W-6))" || bad "ancho $W" "linea larga: $LARGA"
  [ "$(printf '%s\n' "$OUT" | aplanar)" = "$UNA" ] \
    && ok "ancho $W: unidas por \" | \" dan la linea original" || bad "ancho $W" "se perdio contenido: $OUT"
done

echo "== 6. primera peticion: sin uso de contexto ni rate limits =="
OUT="$(mkinput "$DEEP" | jq '.context_window.current_usage = null | del(.rate_limits)' \
       | COLUMNS=100000 bash "$SL" 2>/dev/null | normalize | sed -n 2p)"
[ "$OUT" = "Ctx: 0" ] && ok "linea 2 = «Ctx: 0» sin separadores sueltos" || bad "linea 2" "«$OUT»"

echo "== 7. /mnt/* (DrvFs): rama sin recuento; en ext4 si hay diff =="
# Medido: en un repo bajo /mnt/c los dos diff --shortstat llevaban la barra a 2,7 s por refresco
# (18 ms en ext4). Un git falso registra sus argumentos y finge un repo en cualquier ruta.
FAKEBIN="$TMP/fakebin"; GITLOG="$TMP/git-args.log"; mkdir -p "$FAKEBIN"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"%s"\ncase "$*" in *rev-parse*) echo /mnt/x/repo;; *branch*) echo rama-mnt;; esac\n' \
  "$GITLOG" > "$FAKEBIN/git"; chmod +x "$FAKEBIN/git"
OUT="$(mkinput /mnt/x/repo | PATH="$FAKEBIN:$PATH" COLUMNS=100000 bash "$SL" 2>/dev/null | normalize)"
assert_has   "/mnt: rama visible"     "⎇ rama-mnt" "$OUT"
assert_hasnt "/mnt: sin recuento"     "(+"         "$OUT"
assert_hasnt "/mnt: no invoca git diff" "diff --shortstat" "$(cat "$GITLOG")"
: > "$GITLOG"
mkinput "$DEEP" | PATH="$FAKEBIN:$PATH" COLUMNS=100000 bash "$SL" >/dev/null 2>&1
assert_has   "ext4: invoca git diff"  "diff --shortstat" "$(cat "$GITLOG")"

echo
printf '%s\n' "-----------------------------------------"
if [ "$fails" -eq 0 ]; then printf 'OK  %d/%d\n' "$tests" "$tests"
else printf 'FALLOS %d de %d\n' "$fails" "$tests"; fi
[ "$fails" -eq 0 ]
