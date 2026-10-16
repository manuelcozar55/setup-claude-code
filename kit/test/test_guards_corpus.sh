#!/bin/bash
# shellcheck disable=SC2015  # «cond && pass=$((pass+1)) || bad»: la rama del medio es una asignacion y nunca falla.
# test_guards_corpus.sh — el corpus adversario de la campana E5 (715 sondas medidas en Debian) como
# suite data-driven contra los CUATRO guards bash: block-dangerous-commands, destructive-guard,
# branch-guard y secret-guard. Corre contra los ficheros del propio kit.
#
# Fixture: fixtures/guards-corpus.tsv, 7 columnas: id, clase, comando, esperado (B bloquear, A permitir,
# ASK pedir confirmacion, ? sin expectativa), observado en E5, hook(s) que respondieron, veredicto de E5.
# Es una copia del b2-results.tsv de E5 con una sola edicion: el home de la maquina de pruebas
# (/home/mcozar/kit-test) pasa a /home/usuario/kit-test, porque scan-secrets.sh rechaza el nombre
# de una persona concreta en el repo. Esas rutas solo las leen Sentinel y write-guard.
#
# Reglas, por fila:
#   - Read/Write/Edit/MultiEdit/NotebookEdit: no son comandos Bash -> skip (Sentinel y write-guard: PR3/PR6).
#   - esperado A: los cuatro guards tienen que dejarlo pasar.
#   - esperado B con algun guard bash entre los que respondieron en E5: cada uno de ESOS guards bloquea.
#   - esperado B que E5 solo vio caer en Sentinel/smart_approve (o que nadie vio): skip, salvo en las clases que
#     son de los guards bash (destruct, pipe-shell): ahi un guard bash tiene que bloquearlo, o es un falso
#     negativo y la suite cae.
#   - esperado ASK (o veredicto OK-ask de E5): block-dangerous-commands pregunta.
#   - esperado ?: sin expectativa, skip.
#
# DISENO, no error: los 3 «falsos positivos» de E5 son el borrado recursivo FORZADO de build/ (rm -rf build/,
# rm -rf ./build), que block-dangerous-commands.sh deniega a proposito y documenta (rm -rf se bloquea
# siempre; rm -r sin forzar pasa). La suite los fija como BLOCK. Para convertirlos en ALLOW hay que
# cambiar esa decision en el hook y poner DISENO_FP=allow aqui.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
H="${CORPUS_HOOKS_DIR:-$KIT/claude/hooks}"
FIXTURE="${CORPUS_FIXTURE:-$HERE/fixtures/guards-corpus.tsv}"
DISENO_FP="${DISENO_FP:-block}"
pass=0; fail=0; skip_otra=0; skip_pr3=0; skip_sin=0; ran=0; blocks_checked=0

T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/home/.claude"
# Repo de prueba en una rama de feature: el push implicito de branch-guard se resuelve contra la rama
# actual, y el corpus no debe depender de la rama en la que este quien lo ejecuta.
REPO="$T/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q && git -C "$REPO" symbolic-ref HEAD refs/heads/feature/corpus

# run_hook <guard.sh> <comando> -> BLOCK | ASK | ALLOW
run_hook() {
  local out rc
  out=$(cd "$REPO" && jq -nc --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}' \
    | HOME="$T/home" CC_BLOCK_LOG="$T/blocked.log" bash "$H/$1" 2>/dev/null); rc=$?
  if [ "$rc" -eq 2 ]; then echo BLOCK; return; fi
  case $(jq -r '.hookSpecificOutput.permissionDecision // empty' <<<"$out" 2>/dev/null) in
    deny) echo BLOCK ;; ask) echo ASK ;; *) echo ALLOW ;;
  esac
}
bad() { fail=$((fail+1)); echo "FAIL: [#$id $cls] $1 :: $cmd"; }

MINE="block-dangerous-commands.sh destructive-guard.sh branch-guard.sh secret-guard.sh"
[ -f "$FIXTURE" ] || { echo "FAIL: falta el fixture $FIXTURE"; exit 1; }

while IFS=$'\037' read -r id cls cmd exp _ hook verd; do
  case $cmd in
    Read\ *|Write\ *|Edit\ *|MultiEdit\ *|NotebookEdit\ *) skip_otra=$((skip_otra+1)); continue ;;
  esac
  [ "$exp" = '?' ] && { skip_sin=$((skip_sin+1)); continue; }
  # E5 anoto B donde el guard pregunta en vez de denegar (descarga y ejecucion en dos pasos): es ASK.
  [ "$verd" = OK-ask ] && exp=ASK

  mios=""
  for g in $MINE; do case " $hook " in *" $g "*|*" $g(ask) "*) mios="$mios $g" ;; esac; done

  case $exp in
    A)
      ran=$((ran+1))
      if [ "$verd" = "FALSO POSITIVO" ] && [ "$DISENO_FP" = block ]; then
        [ "$(run_hook block-dangerous-commands.sh "$cmd")" = BLOCK ] && pass=$((pass+1)) \
          || bad "DISENO: block-dangerous-commands deberia denegar el borrado recursivo forzado"
        continue
      fi
      for g in $MINE; do
        r=$(run_hook "$g" "$cmd")
        [ "$r" = ALLOW ] && pass=$((pass+1)) || bad "$g dio $r y se esperaba ALLOW"
      done ;;
    ASK)
      ran=$((ran+1))
      r=$(run_hook block-dangerous-commands.sh "$cmd")
      [ "$r" = ASK ] && pass=$((pass+1)) || bad "block-dangerous-commands dio $r y se esperaba ASK" ;;
    B)
      if [ -n "$mios" ]; then
        ran=$((ran+1))
        for g in $mios; do
          r=$(run_hook "$g" "$cmd"); blocks_checked=$((blocks_checked+1))
          [ "$r" = BLOCK ] && pass=$((pass+1)) || bad "$g dio $r y se esperaba BLOCK"
        done
      elif [ "$cls" = destruct ] || [ "$cls" = pipe-shell ]; then
        ran=$((ran+1)); got=ALLOW
        for g in $MINE; do [ "$(run_hook "$g" "$cmd")" = BLOCK ] && { got=BLOCK; break; }; done
        blocks_checked=$((blocks_checked+1))
        [ "$got" = BLOCK ] && pass=$((pass+1)) || bad "falso negativo: ningun guard bash lo bloquea"
      else
        skip_pr3=$((skip_pr3+1))
      fi ;;
    *) skip_sin=$((skip_sin+1)) ;;
  esac
done < <(awk -F'\t' -v OFS='\037' '{ $1=$1; print }' "$FIXTURE")

# Contra una suite decorativa: si el parseo del fixture se rompiera, todo seria skip y pasaria en verde.
[ "$ran" -ge 100 ] && [ "$blocks_checked" -ge 40 ] && pass=$((pass+1)) \
  || { fail=$((fail+1)); echo "FAIL: el corpus ejecuto solo $ran filas ($blocks_checked bloqueos); se esperaban >=100 y >=40"; }

echo "filas ejecutadas=$ran  skip(otra herramienta)=$skip_otra  skip(Sentinel/write-guard: PR3/PR6)=$skip_pr3  skip(sin expectativa)=$skip_sin"
echo "PASS=$pass FAIL=$fail"; [ $fail -eq 0 ]
