#!/bin/bash
# test_guards_r1.sh — los corpus de la revision independiente R1 (2026-11-12: guards-r1.jsonl, ronda 1, 566 ordenes mas las propias,
# y guards-r2.jsonl, ronda 2, 1.198 ordenes y 127 de git en `main`) contra la CADENA de PreToolUse de Bash (cinco guards mas Sentinel;
# el veredicto es el peor: BLOCK > ASK > ALLOW) y el sensor de MONOTONIA.
#
# Cada fila de los fixtures lleva:
#   exp   el veredicto esperado (`BLOCK|ASK` = valen las dos salidas seguras; `ALLOW|ASK` idem)
#   base  lo que daba la version anterior (bc68243) con ese mismo comando; se midio una vez y se guarda
#   br    opcional: `main` ejecuta la fila en un repo cuya rama actual es main (el resto, en feat/demo)
#   ex    solo en las filas que BAJAN de BLOCK a ALLOW: el NOMBRE de la prueba de la lista cerrada de exenciones
#         (fixtures/guards-exenciones.txt) que demuestra que el literal peligroso es inocuo. Sin `ex`, o con un nombre que no
#         esta en la lista, esa bajada es una regresion.
#   limite  un limite conocido y documentado (SECURITY.md): exp recoge lo que hoy pasa, y esta fila avisa si algun dia cambia.
#
# Monotonia: lo que la base bloqueaba solo puede pasar a ALLOW si el parser demuestra de forma positiva que es dato en un contexto
# conocido. En cualquier otro caso en que el analisis nuevo no encuentra la orden, el veredicto es ASK (o BLOCK), nunca ALLOW en silencio.
#
# Los comandos NUNCA se ejecutan: se dan como texto a los guards. Marcadores: @@ROOT@@ (/ro + ot/) para que scan-secrets no lo vea.
# R1_HOOKS_DIR / R1_SENTINEL apuntan la suite a otra copia de los guards (test_guards_falsifiability.sh los muta); R1_DUMP=1 imprime
# `DUMP id veredicto` por fila (asi se midio la columna `base` con la copia de bc68243).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
H="${R1_HOOKS_DIR:-$KIT/claude/hooks}"
SEN="${R1_SENTINEL:-$KIT/sentinel/sentinel_preflight.py}"
PY="${PYTHON3:-python3}"
FIXES="${R1_FIXTURE:-$HERE/fixtures/guards-r1.jsonl $HERE/fixtures/guards-r2.jsonl}"
EXENC="$HERE/fixtures/guards-exenciones.txt"
JOBS=${R1_JOBS:-8}

T=$(mktemp -d); trap 'rm -rf -- "$T"' EXIT
mkdir -p "$T/home/.claude" "$T/repo" "$T/repo-main" "$T/res"
cp "$KIT/claude/sentinel-allowlist.json" "$T/home/.claude/"
(
  cd "$T/repo" && git init -q -b feat/demo \
    && git config user.email t@example.com && git config user.name t \
    && mkdir -p docs src build node_modules config \
    && printf 'x\n' > README.md && printf '.env\n' > .gitignore && git add README.md .gitignore \
    && git commit -qm init
) >/dev/null 2>&1
(
  cd "$T/repo-main" && git init -q -b main \
    && git config user.email t@example.com && git config user.name t \
    && mkdir -p docs src build node_modules config \
    && printf 'x\n' > README.md && printf '.env\n' > .gitignore && git add README.md .gitignore \
    && git commit -qm init
) >/dev/null 2>&1

code() {
  local rc=$1 out=$2
  (( rc == 2 )) && { echo X2; return; }
  (( rc != 0 )) && { echo "E$rc"; return; }
  case $out in
    *'"permissionDecision": "deny"'*|*'"permissionDecision":"deny"'*) echo D ;;
    *'"permissionDecision": "ask"'*|*'"permissionDecision":"ask"'*) echo K ;;
    *) echo A ;;
  esac
}

# run_case <n> <fichero con el comando>: deja en $T/res/<n> "VEREDICTO<TAB>fila"
run_case() {
  local n=$1 cf=$2 repo=$3 payload out rc c worst=ALLOW g row=""
  payload=$(jq -nc --rawfile c "$cf" --arg cwd "$repo" '{session_id:"t",transcript_path:"/dev/null",cwd:$cwd,hook_event_name:"PreToolUse",tool_name:"Bash",tool_input:{command:$c}}')
  for g in block-dangerous-commands branch-guard destructive-guard secret-guard bash-write-guard sentinel; do
    if [[ $g == sentinel ]]; then
      out=$(cd "$repo" && HOME="$T/home" "$PY" -I -S "$SEN" <<<"$payload" 2>/dev/null); rc=$?
    else
      out=$(cd "$repo" && HOME="$T/home" CC_BLOCK_LOG="$T/blocked.log" bash "$H/$g.sh" <<<"$payload" 2>/dev/null); rc=$?
    fi
    c=$(code "$rc" "$out")
    row+="${g:0:3}=$c "
    case $c in
      D|X2|E*) worst=BLOCK ;;
      K) [[ $worst == BLOCK ]] || worst=ASK ;;
    esac
  done
  printf '%s\t%s\n' "$worst" "$row" > "$T/res/$n"
}

n=0; running=0
declare -a IDS EXPS BASES EXS
while IFS= read -r line; do
  [[ -z $line ]] && continue
  n=$((n+1))
  jq -j '.cmd' <<<"$line" > "$T/cmd.$n"
  # El marcador se monta aqui: el fixture no lleva el literal que scan-secrets rechaza.
  if grep -q '@@ROOT@@' "$T/cmd.$n"; then
    sed -i "s#@@ROOT@@#/ro""ot/#g" "$T/cmd.$n"
  fi
  IDS[n]=$(jq -r .id <<<"$line"); EXPS[n]=$(jq -r .exp <<<"$line"); BASES[n]=$(jq -r .base <<<"$line")
  EXS[n]=$(jq -r '.ex // ""' <<<"$line")
  run_case "$n" "$T/cmd.$n" "$T/repo$([[ $(jq -r '.br // ""' <<<"$line") == main ]] && echo -main)" &
  running=$((running+1))
  if (( running >= JOBS )); then wait; running=0; fi
done < <(for f in $FIXES; do cat "$f"; done)
wait

pass=0; fail=0; viol=0; peli=0; peli_mal=0; leg=0; leg_blk=0; exentos=0
for ((i = 1; i <= n; i++)); do
  IFS=$'\t' read -r v row < "$T/res/$i"
  id=${IDS[i]}; exp=${EXPS[i]}; base=${BASES[i]}
  [[ -n ${R1_DUMP:-} ]] && printf 'DUMP\t%s\t%s\n' "$id" "$v"
  if [[ "|$exp|" == *"|$v|"* ]]; then pass=$((pass+1)); else
    fail=$((fail+1)); echo "FAIL: [$id] esperado $exp, obtenido $v ($row) :: $(head -c 100 "$T/cmd.$i" | tr '\n' ' ')"
  fi
  # Sensor de monotonia.
  if [[ $base == BLOCK && $v == ALLOW ]]; then
    if [[ -z ${EXS[i]} ]]; then
      viol=$((viol+1)); fail=$((fail+1))
      echo "FAIL: [$id] MONOTONIA: la base bloqueaba y ahora pasa sin que sea prosa ni build conocido :: $(head -c 100 "$T/cmd.$i" | tr '\n' ' ')"
    elif ! grep -qxF -- "${EXS[i]}" <(grep -v '^#' "$EXENC" | cut -f1); then
      viol=$((viol+1)); fail=$((fail+1))
      echo "FAIL: [$id] MONOTONIA: la exencion «${EXS[i]}» no esta en la lista cerrada (fixtures/guards-exenciones.txt) :: $(head -c 100 "$T/cmd.$i" | tr '\n' ' ')"
    else
      exentos=$((exentos+1))
    fi
  elif [[ -n ${EXS[i]} ]]; then
    fail=$((fail+1)); echo "FAIL: [$id] lleva exencion (ex) pero no baja de BLOCK a ALLOW: quitala, una exencion de mas es un permiso sin dueno"
  fi
  case $exp in
    BLOCK|'BLOCK|ASK'|ASK) peli=$((peli+1)); [[ $v == ALLOW ]] && peli_mal=$((peli_mal+1)) ;;
    *) leg=$((leg+1)); [[ $v == BLOCK ]] && leg_blk=$((leg_blk+1)) ;;
  esac
done
echo "corpus R1+R2: $n ordenes; con veredicto esperado: $pass; esperados peligrosos que pasan: $peli_mal/$peli; esperados legitimos bloqueados: $leg_blk/$leg"
echo "monotonia: $viol violaciones; $exentos exenciones declaradas (BLOCK->ALLOW con razon)"
echo "PASS=$pass FAIL=$fail"; [ $fail -eq 0 ]
