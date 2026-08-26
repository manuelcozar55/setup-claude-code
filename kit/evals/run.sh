#!/usr/bin/env bash
# run.sh — corre el eval set en directorios temporales aislados, uno por tarea.
#
# OPT-IN, no automatico: esto NO se ejecuta via `make test`, `doctor.sh` ni CI.
# Cuesta dinero real (una llamada a `claude -p` por tarea y repeticion).
# Correrlo a mano: `bash kit/evals/run.sh`. Ver README.md para el criterio de
# admision de tareas y el porque de --permission-mode auto.
#
# Variables:
#   RUNS=n   repeticiones por tarea (por defecto 1). Con 1 no hay varianza que
#            medir: el intervalo que saca report.py sale enorme, y eso es la
#            respuesta correcta, no un defecto del informe.
#   ARM=x    brazo experimental. 'on' (por defecto) corre con el harness puesto;
#            'off' es el control y anade --safe-mode. Sin los dos brazos, el
#            numero mide el MODELO, no el harness, y report.py lo dice.
set -u
E="$(cd "$(dirname "$0")" && pwd)"
# Exportados los dos: `bash _check.sh` es otro proceso y no hereda lo que no se exporta.
# Sin `export PY`, el check de 01/03/04/05 corria como "" grade.py -> "command not
# found" -> fail. Cuatro de seis tareas daban rojo sin mirar al agente.
export PY="${PYTHON3:-python3}"
export GRADE="$E/grade.py"
RUNS="${RUNS:-1}"
ARM="${ARM:-on}"
# El control. --safe-mode apaga CLAUDE.md, skills, hooks, plugins, MCP, comandos
# y agentes propios, y a diferencia de --bare SIGUE autenticando con la sesion
# normal (--bare exige ANTHROPIC_API_KEY, que una cuenta de suscripcion no tiene).
# Medido en este equipo: agentes 24->4, comandos 99->47, servidores MCP 12->0.
# Ojo: al no haber hooks, el brazo 'off' corre SIN los guards. Es aceptable solo
# porque cada tarea vive en un mktemp -d y el prompt lo pone el repo, no la red.
ARMFLAGS=(); [ "$ARM" = off ] && ARMFLAGS=(--safe-mode)
STORE="$E/runs.jsonl"
EVAL_TS="$(date -u +%FT%TZ)"; export EVAL_TS
EVAL_SHA="$(git -C "$E" rev-parse --short HEAD 2>/dev/null || echo desconocido)"; export EVAL_SHA
OUT="$E/resultados-$(date +%F).json"
TMP="$E/.resultados.parcial"
: > "$TMP"

for f in "$E"/tasks/*.yaml; do
  id=$(basename "$f" .yaml)
  for attempt in $(seq 1 "$RUNS"); do
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
    claude "${ARMFLAGS[@]}" -p "$(cat _prompt.txt)" --permission-mode auto --output-format stream-json --verbose > _run.jsonl 2>_run.err
    bash _check.sh >/dev/null 2>&1; rc=$?
    # 2 = no se pudo medir (transcript vacio). Contarlo como fail convierte una averia
    # de instrumentacion en un suspenso del agente, que es la lectura contraria.
    case $rc in 0) r=pass;; 2) r=error;; *) r=fail;; esac
    mkdir -p "$E/transcripts"
    keep="$E/transcripts/$id-$ARM-$attempt-$(date +%F).jsonl"
    cp _run.jsonl "$keep"   # sin esto no se pueden leer despues
    "$PY" "$E/record.py" "$id" "$ARM" "$attempt" "$r" "$keep" "$STORE"
    printf '  "%s": "%s",\n' "$id" "$r" >> "$TMP"
    echo "$id [$ARM $attempt/$RUNS]: $r"
    cd "$E" && rm -rf "$d"
  done
done

{ echo "{"; sed '$ s/,$//' "$TMP"; echo "}"; } > "$OUT"
rm -f "$TMP"
echo "-> $OUT"
echo "-> $STORE (historico; agregalo con: $PY $E/report.py)"
