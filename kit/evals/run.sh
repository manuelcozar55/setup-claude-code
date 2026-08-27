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
#            Ademas hay tres brazos de ABLACION, que quitan UNA pieza y dejan
#            el resto puesta: sin-ajustes, sin-skills, sin-mcp. El lift on/off
#            dice si el harness sirve; solo la ablacion dice QUE pieza sirve.
set -u
E="$(cd "$(dirname "$0")" && pwd)"
# Exportados los dos: `bash _check.sh` es otro proceso y no hereda lo que no se exporta.
# Sin `export PY`, el check de 01/03/04/05 corria como "" grade.py -> "command not
# found" -> fail. Cuatro de seis tareas daban rojo sin mirar al agente.
export PY="${PYTHON3:-python3}"
export GRADE="$E/grade.py"
RUNS="${RUNS:-1}"
ARM="${ARM:-on}"
# Los brazos. --safe-mode apaga CLAUDE.md, skills, hooks, plugins, MCP, comandos
# y agentes propios, y a diferencia de --bare SIGUE autenticando con la sesion
# normal (--bare exige ANTHROPIC_API_KEY, que una cuenta de suscripcion no tiene).
# Medido en este equipo: agentes 24->4, comandos 99->47, servidores MCP 12->0.
# Ojo: al no haber hooks, el brazo 'off' corre SIN los guards. Es aceptable solo
# porque cada tarea vive en un mktemp -d y el prompt lo pone el repo, no la red.
#
# Los tres de ablacion quitan una pieza cada uno. No hay un cuarto para CLAUDE.md
# porque el CLI no tiene interruptor propio para el: solo --safe-mode, que lo
# apaga todo, y --bare, que exige API key. Queda dicho en vez de simulado.
#   sin-ajustes  al correr en un mktemp -d no hay ajustes de proyecto ni locales,
#                asi que esto deja la sesion sin settings.json de usuario: se van
#                los hooks, los permisos y el env de golpe. Son tres cosas, no
#                una, porque el CLI no las separa; report.py lo etiqueta asi.
#   sin-skills   --disable-slash-commands ("Disable all skills" en el propio --help).
#   sin-mcp      --strict-mcp-config sin ningun --mcp-config: 12 servidores -> 0.
case "$ARM" in
  on)          ARMFLAGS=() ;;
  off)         ARMFLAGS=(--safe-mode) ;;
  sin-ajustes) ARMFLAGS=(--setting-sources "project,local") ;;
  sin-skills)  ARMFLAGS=(--disable-slash-commands) ;;
  sin-mcp)     ARMFLAGS=(--strict-mcp-config) ;;
  # Sin esto, un ARM mal escrito corria con el harness PUESTO y se guardaba con
  # la etiqueta del typo. `ARM=Off` (con mayuscula) habria producido un brazo de
  # control que en realidad no controlaba nada, y el informe se lo habria creido.
  *) echo "run.sh: ARM desconocido '$ARM'. Validos: on off sin-ajustes sin-skills sin-mcp" >&2
     exit 2 ;;
esac
# El modelo no puede cambiar entre brazos o el lift mide dos cosas a la vez. Es
# un riesgo real aqui: 'sin-ajustes' tira el settings.json que fija el modelo.
# Se pasa explicito si EVAL_MODEL esta puesto, y report.py se niega a comparar
# brazos que corrieron con modelos distintos (lo sabe por lo que graba record.py).
[ -n "${EVAL_MODEL:-}" ] && ARMFLAGS+=(--model "$EVAL_MODEL")
STORE="$E/runs.jsonl"
EVAL_TS="$(date -u +%FT%TZ)"; export EVAL_TS
EVAL_SHA="$(git -C "$E" rev-parse --short HEAD 2>/dev/null || echo desconocido)"; export EVAL_SHA
OUT="$E/resultados-$(date +%F).json"
TMP="$E/.resultados.parcial"

# Sin argumentos, todas. Con argumentos, solo esas, y un nombre que no existe
# es error: correr el conjunto entero "por si acaso" es justo lo que se paga.
TAREAS=()
if [ "$#" -eq 0 ]; then
  for f in "$E"/tasks/*.yaml; do TAREAS+=("$f"); done
else
  for a in "$@"; do
    f="$E/tasks/$a.yaml"
    [ -f "$f" ] || { echo "run.sh: no existe la tarea '$a'" >&2; exit 2; }
    TAREAS+=("$f")
  done
fi

# Coste estimado a partir de lo ya gastado, no de un numero escrito a mano.
if [ "${DRYRUN:-0}" = "1" ]; then
  n=${#TAREAS[@]}
  "$PY" - "$STORE" "$n" "$RUNS" "$ARM" <<'PYEOF'
import json, sys
store, n, runs, arm = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
costes = []
try:
    for linea in open(store):
        try:
            d = json.loads(linea)
        except ValueError:
            continue
        # Una linea escalar valida ('42') pasa el json.loads y revienta en .get;
        # un cost_usd de texto revienta despues en sum(). Una linea mala se salta:
        # el numero de llamadas es exacto aunque no quede ni un coste utilizable.
        if not isinstance(d, dict):
            continue
        c = d.get("cost_usd")
        if isinstance(c, bool) or not isinstance(c, (int, float)):
            continue
        if c:
            costes.append(c)
except IOError:
    pass
llamadas = n * runs
tarea_s = "tarea" if n == 1 else "tareas"
print("ENSAYO (DRYRUN=1): brazo '%s', %d %s x %d repeticion(es) = %d llamadas"
      % (arm, n, tarea_s, runs, llamadas))
if costes:
    # Media de TODO el historico: mezcla brazos y modelos, asi que con ARM=off
    # estima con costes de 'on'. Es orden de magnitud, no la factura del brazo.
    medio = sum(costes) / len(costes)
    print("coste estimado: %.2f USD (media de %d runs ya guardados, todos los brazos: %.4f USD)"
          % (medio * llamadas, len(costes), medio))
else:
    # Sin historico no hay estimacion. Inventar una seria peor que no darla.
    print("coste estimado: desconocido, no hay runs guardados de los que sacar la media")
PYEOF
  # Sin set -e, un estimador muerto caia al exit 0 de abajo: el ensayo decia que
  # todo fue bien justo cuando se habia quedado sin la unica cifra que da.
  exit $?
fi

: > "$TMP"
for f in "${TAREAS[@]}"; do
  id=$(basename "$f" .yaml)
  for attempt in $(seq 1 "$RUNS"); do
    d=$(mktemp -d) || continue
    # Dos directorios sin parentesco, no uno. Con el enunciado y el check dentro
    # del cwd del agente, el evaluado puede LEER SU PROPIO ORACULO: en la primera
    # tirada real, 3 de 12 ejecuciones hicieron `cat _check.sh`, y en la 06 lo
    # hicieron los dos brazos antes de aprobar. Un `../` no descubre nada porque
    # el meta es otro mktemp -d, no un hermano.
    m=$(mktemp -d) || { rmdir "$d"; continue; }
    "$PY" -c "
import os, sys, yaml
t = yaml.safe_load(open(sys.argv[1])); m = sys.argv[2]
open(os.path.join(m,'_setup.sh'),'w').write(t.get('setup') or ':\n')
open(os.path.join(m,'_check.sh'),'w').write(t['check'])
open(os.path.join(m,'_prompt.txt'),'w').write(t['prompt'])
" "$f" "$m"
    cd "$d" || continue
    bash "$m/_setup.sh"
    # --permission-mode auto: sin esto, claude -p sin TTY no puede conceder
    # permisos y las tareas que requieren Edit/Bash miden friccion de permisos
    # en vez de comportamiento. --dangerously-skip-permissions y bypassPermissions
    # estan bloqueados como root; "auto" no lo esta y sigue invocando los hooks
    # PreToolUse (secret-guard, sentinel, smart_approve) mas el clasificador
    # propio de Claude Code, asi que el aislamiento del mktemp -d no depende
    # solo de este flag. Ver README.md para el detalle completo.
    claude "${ARMFLAGS[@]}" -p "$(cat "$m/_prompt.txt")" --permission-mode auto --output-format stream-json --verbose > "$m/_run.jsonl" 2>"$m/_run.err"
    # El transcript tambien vive fuera: leerlo es leer la trayectoria que se esta
    # puntuando. grade.py lo toma de RUN_JSONL (ver su valor por defecto).
    export RUN_JSONL="$m/_run.jsonl"
    bash "$m/_check.sh" >/dev/null 2>&1; rc=$?
    # 2 = no se pudo medir (transcript vacio). Contarlo como fail convierte una averia
    # de instrumentacion en un suspenso del agente, que es la lectura contraria.
    case $rc in 0) r=pass;; 2) r=error;; *) r=fail;; esac
    mkdir -p "$E/transcripts"
    # El sufijo es el instante de la tirada, no el dia. 'attempt' reinicia en 1 en
    # cada invocacion, asi que con '$(date +%F)' dos tiradas del mismo dia sobre la
    # misma tarea y el mismo brazo escribian EL MISMO fichero y la primera perdia su
    # evidencia sin decirlo. Medido sobre el historico que dejo ese nombre: 26 de 98
    # filas (27 %) apuntan a un transcript que otra fila piso.
    # Los cuatro componentes son exactamente los que record.py graba en la fila
    # (task, arm, attempt, ts), asi que desde una fila se puede reconstruir el nombre
    # de su evidencia; un sufijo aleatorio evitaria la colision pero romperia eso.
    keep="$E/transcripts/$id-$ARM-$attempt-${EVAL_TS//[-:]/}.jsonl"
    cp "$m/_run.jsonl" "$keep"   # sin esto no se pueden leer despues
    "$PY" "$E/record.py" "$id" "$ARM" "$attempt" "$r" "$keep" "$STORE"
    printf '  "%s": "%s",\n' "$id" "$r" >> "$TMP"
    echo "$id [$ARM $attempt/$RUNS]: $r"
    cd "$E" && rm -rf "$d" "$m"
  done
done

{ echo "{"; sed '$ s/,$//' "$TMP"; echo "}"; } > "$OUT"
rm -f "$TMP"
echo "-> $OUT"
echo "-> $STORE (historico; agregalo con: $PY $E/report.py)"
