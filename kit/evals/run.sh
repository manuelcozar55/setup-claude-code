#!/usr/bin/env bash
# run.sh — corre el eval set en directorios temporales aislados, uno por tarea.
#
# OPT-IN, no automatico: esto NO se ejecuta via `make test`, `doctor.sh` ni CI.
# Cuesta dinero real (6 llamadas a `claude -p`, una por tarea). Correrlo a
# mano: `bash kit/evals/run.sh`. Ver README.md para el criterio de admision
# de tareas y el porque de --permission-mode auto.
set -u
E="$(cd "$(dirname "$0")" && pwd)"
# Exportados los dos: `bash _check.sh` es otro proceso y no hereda lo que no se exporta.
# Sin `export PY`, el check de 01/03/04/05 corria como "" grade.py -> "command not
# found" -> fail. Cuatro de seis tareas daban rojo sin mirar al agente.
export PY="${PYTHON3:-python3}"
export GRADE="$E/grade.py"
OUT="$E/resultados-$(date +%F).json"
TMP="$E/.resultados.parcial"
: > "$TMP"

for f in "$E"/tasks/*.yaml; do
  id=$(basename "$f" .yaml)
  d=$(mktemp -d) || continue
  cd "$d" || continue
  "$PY" -c "
import yaml, sys
t = yaml.safe_load(open(sys.argv[1]))
open('_setup.sh','w').write(t.get('setup') or ':\n')
open('_check.sh','w').write(t['check'])
open('_prompt.txt','w').write(t['prompt'])
" "$f"
  bash _setup.sh
  # --permission-mode auto: sin esto, claude -p sin TTY no puede conceder
  # permisos y las tareas que requieren Edit/Bash miden friccion de permisos
  # en vez de comportamiento. --dangerously-skip-permissions y bypassPermissions
  # estan bloqueados como root; "auto" no lo esta y sigue invocando los hooks
  # PreToolUse (secret-guard, sentinel, smart_approve) mas el clasificador
  # propio de Claude Code, asi que el aislamiento del mktemp -d no depende
  # solo de este flag. Ver README.md para el detalle completo.
  claude -p "$(cat _prompt.txt)" --permission-mode auto --output-format stream-json --verbose > _run.jsonl 2>_run.err
  bash _check.sh >/dev/null 2>&1; rc=$?
  # 2 = no se pudo medir (transcript vacio). Contarlo como fail convierte una averia
  # de instrumentacion en un suspenso del agente, que es la lectura contraria.
  case $rc in 0) r=pass;; 2) r=error;; *) r=fail;; esac
  mkdir -p "$E/transcripts"
  cp _run.jsonl "$E/transcripts/$id-$(date +%F).jsonl"   # sin esto no se pueden leer despues
  printf '  "%s": "%s",\n' "$id" "$r" >> "$TMP"
  echo "$id: $r"
  cd "$E" && rm -rf "$d"
done

{ echo "{"; sed '$ s/,$//' "$TMP"; echo "}"; } > "$OUT"
rm -f "$TMP"
echo "-> $OUT"
