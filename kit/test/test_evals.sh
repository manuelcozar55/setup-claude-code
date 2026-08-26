#!/usr/bin/env bash
# test_evals.sh — sensor offline del eval set. No gasta una sola llamada a la API.
#
# El eval set nacio con dos averias que nadie podia ver porque correrlo cuesta dinero
# y nunca se corrio entero: `run.sh` no exportaba $PY, asi que el check de 4 de las 6
# tareas se ejecutaba como `"" grade.py ...` y daba rojo sin mirar al agente; y la
# tarea 06 verificaba con `grep -q test_suma.py _run.jsonl`, que acierta siempre
# porque el prompt se copia dentro del propio transcript. Un eval con un falso
# negativo estructural y un falso positivo estructural mide ruido.
#
# Esta suite comprueba el instrumento, no el agente: contrato de variables, ausencia
# de checks tautologicos, y que cada modo de grade.py sabe fallar.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
E="$PWD/kit/evals"
pass=0; fail=0

ck() { if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1))
       else echo "NOT ok - $3 (obtenido '$1', esperado '$2')"; fail=$((fail+1)); fi; }

PY="${PYTHON3:-python3}"
if ! "$PY" -c 'import yaml' 2>/dev/null; then
  echo "ok - pyyaml no disponible: suite omitida"; echo "== 1 passed, 0 failed =="; exit 0
fi

# --- 1. Contrato de variables entre run.sh y los checks ---------------------
# `bash _check.sh` es otro proceso: hereda lo exportado, nada mas.
missing=$("$PY" - "$E" <<'PYEOF'
import glob, os, re, sys, yaml
E = sys.argv[1]
run = open(os.path.join(E, "run.sh")).read()
exported = set(re.findall(r'^export\s+([A-Za-z_][A-Za-z0-9_]*)', run, re.M))
used = set()
for f in sorted(glob.glob(os.path.join(E, "tasks", "*.yaml"))):
    t = yaml.safe_load(open(f))
    for block in (t.get("check") or "", t.get("setup") or ""):
        used |= set(re.findall(r'\$\{?([A-Z][A-Z0-9_]*)\}?', block))
print(" ".join(sorted(used - exported - {"HOME", "PATH", "PWD", "TMPDIR"})))
PYEOF
)
if [ -z "$missing" ]; then
  echo "ok - run.sh exporta todas las variables que usan los checks"; pass=$((pass+1))
else
  echo "NOT ok - los checks usan variables que run.sh no exporta:$missing"; fail=$((fail+1))
fi

# --- 2. Ningun check puede grepear el transcript crudo ----------------------
# El prompt aparece literal dentro de _run.jsonl. Cualquier grep sobre el fichero
# acierta por el eco del enunciado, no por lo que hizo el agente. Para mirar la
# trayectoria esta grade.py, que distingue tool_use de texto.
taut=$(grep -l '_run\.jsonl' "$E"/tasks/*.yaml 2>/dev/null | tr '\n' ' ')
if [ -z "$taut" ]; then
  echo "ok - ninguna tarea verifica grepeando _run.jsonl directamente"; pass=$((pass+1))
else
  echo "NOT ok - tareas que grepean el transcript crudo (tautologico): $taut"; fail=$((fail+1))
fi

# --- 3. Cada tarea esta bien formada ---------------------------------------
bad=$("$PY" - "$E" <<'PYEOF'
import glob, os, sys, yaml
E = sys.argv[1]
bad = []
for f in sorted(glob.glob(os.path.join(E, "tasks", "*.yaml"))):
    t = yaml.safe_load(open(f)) or {}
    stem = os.path.basename(f)[:-5]
    if t.get("id") != stem:
        bad.append("%s: id '%s' != nombre de fichero" % (stem, t.get("id")))
    for k in ("prompt", "check"):
        if not (t.get(k) or "").strip():
            bad.append("%s: falta '%s'" % (stem, k))
print("; ".join(bad))
PYEOF
)
if [ -z "$bad" ]; then
  echo "ok - las tareas parsean y declaran id, prompt y check"; pass=$((pass+1))
else
  echo "NOT ok - tareas mal formadas: $bad"; fail=$((fail+1))
fi

# --- 4. Falsabilidad: cada modo de grade.py tiene que saber fallar ----------
# Sin esta seccion, un grader roto daria PASS para siempre y el eval entero
# se leeria como "todo verde".
T=$(mktemp -d) || exit 1
trap 'rm -f "$T"/*.jsonl; rmdir "$T" 2>/dev/null' EXIT
G="$E/grade.py"

# Transcript sintetico: el agente edita notas.md y ejecuta `python3 test_suma.py`.
"$PY" - "$T" <<'PYEOF'
import json, os, sys
T = sys.argv[1]
def ev(*content):
    return json.dumps({"type": "assistant", "message": {"role": "assistant", "content": list(content)}})
def tu(name, inp):
    return {"type": "tool_use", "name": name, "input": inp}
def tx(s):
    return {"type": "text", "text": s}

bueno = [ev(tx("Voy a arreglarlo. Usa pnpm install en vez de npm.")),
         ev(tu("Edit", {"file_path": "notas.md", "old_string": "a"})),
         ev(tu("Bash", {"command": "python3 test_suma.py"})),
         ev(tx("Ejecutado: pasa."))]
malo  = [ev(tx("Arreglado, pasa.")),
         ev(tu("Edit", {"file_path": "notas.md", "old_string": "a"})),
         ev(tu("Read", {"file_path": "notas.md"})),
         ev(tu("Bash", {"command": "npm install"}))]
open(os.path.join(T, "bueno.jsonl"), "w").write("\n".join(bueno) + "\n")
open(os.path.join(T, "malo.jsonl"), "w").write("\n".join(malo) + "\n")
open(os.path.join(T, "vacio.jsonl"), "w").write("")
PYEOF

g() { "$PY" "$G" --transcript "$T/$1" "${@:2}" >/dev/null 2>&1; echo $?; }

ck "$(g bueno.jsonl --require-bash 'test_suma.py')" 0 "--require-bash: pasa si el comando se ejecuto"
ck "$(g malo.jsonl  --require-bash 'test_suma.py')" 1 "--require-bash: falla si solo se afirmo que pasa"
ck "$(g bueno.jsonl --no-read-after-edit notas.md)" 0 "--no-read-after-edit: pasa sin relectura"
ck "$(g malo.jsonl  --no-read-after-edit notas.md)" 1 "--no-read-after-edit: falla con relectura"
ck "$(g bueno.jsonl --recommend pnpm --forbid-bash npm)" 0 "--recommend/--forbid-bash: recomendar no es ejecutar"
ck "$(g malo.jsonl  --recommend pnpm --forbid-bash npm)" 1 "--recommend/--forbid-bash: falla si lo ejecuto"

# 2, no 1: 'no se pudo medir' no es 'el agente lo hizo mal'.
ck "$(g vacio.jsonl --require-bash x)"          2 "transcript vacio devuelve 2 (error), no 1 (fail)"
ck "$(g vacio.jsonl --no-read-after-edit x.md)" 2 "transcript vacio devuelve 2 tambien en --no-read-after-edit"

# run.sh tiene que traducir ese 2 a algo distinto de 'fail'.
if grep -q '2) r=error' "$E/run.sh"; then
  echo "ok - run.sh registra el codigo 2 como 'error', no como 'fail'"; pass=$((pass+1))
else
  echo "NOT ok - run.sh no distingue el codigo 2 (error) del 1 (fail)"; fail=$((fail+1))
fi

# --- 5. El brazo de control tiene que seguir existiendo ---------------------
# Si una version futura de Claude Code retira --safe-mode, el brazo 'off' pasa a
# ser una copia del 'on': el lift sale 0.00, report.py lo llama NEUTRO y el eval
# concluye en silencio que el harness no sirve. Es el fallo mas caro posible aqui,
# porque parece un resultado en vez de una averia.
if grep -q 'ARMFLAGS=(--safe-mode)' "$E/run.sh"; then
  echo "ok - run.sh usa --safe-mode como brazo de control"; pass=$((pass+1))
else
  echo "NOT ok - run.sh no define el brazo de control con --safe-mode"; fail=$((fail+1))
fi
if ! command -v claude >/dev/null 2>&1; then
  echo "ok - claude no instalado: no se comprueba el flag"; pass=$((pass+1))
elif claude --help 2>/dev/null | grep -q -- '--safe-mode'; then
  echo "ok - esta version de Claude Code sigue teniendo --safe-mode"; pass=$((pass+1))
else
  echo "NOT ok - --safe-mode ya no existe: el brazo 'off' mide lo mismo que el 'on'"; fail=$((fail+1))
fi

# --- 6. El almacen y el informe -------------------------------------------
# record.py tiene que sacar coste y modelo del evento 'result', y report.py tiene
# que dejar los 'error' FUERA del denominador. Coercionar un error a 0 convierte
# una averia de instrumentacion en un suspenso del agente: el numero baja sin que
# nada haya empeorado.
"$PY" - "$T" <<'PYEOF'
import json, os, sys
T = sys.argv[1]
res = {"type": "result", "subtype": "success", "is_error": False,
       "total_cost_usd": 0.1234, "duration_api_ms": 1000, "num_turns": 3,
       "modelUsage": {"modelo-x": {}},
       "usage": {"input_tokens": 111, "output_tokens": 22, "cache_read_input_tokens": 9}}
open(os.path.join(T, "conresult.jsonl"), "w").write(json.dumps(res) + "\n")
PYEOF

S="$T/store.jsonl"; : > "$S"
EVAL_TS=2026-01-01T00:00:00Z EVAL_SHA=deadbee \
  "$PY" "$E/record.py" t1 on 1 pass "$T/conresult.jsonl" "$S" 2>/dev/null
got=$("$PY" -c "
import json,sys
r=json.loads(open(sys.argv[1]).readline())
print(r['cost_usd'], r['model'], r['input_tokens'], r['harness_sha'], r['result'])
" "$S" 2>/dev/null)
ck "$got" "0.1234 modelo-x 111 deadbee pass" "record.py extrae coste, modelo y tokens del evento result"

# Un pass, un fail y DOS error: la tasa honesta es 0.50 sobre n=2, no 0.25 sobre 4.
for spec in "t1 on 2 fail" "t1 on 3 error" "t1 on 4 error"; do
  # shellcheck disable=SC2086
  set -- $spec
  EVAL_TS=2026-01-01T00:00:00Z EVAL_SHA=deadbee \
    "$PY" "$E/record.py" "$1" "$2" "$3" "$4" "$T/conresult.jsonl" "$S" 2>/dev/null
done
rep=$("$PY" "$E/report.py" --store "$S" 2>&1)
# El coste sintetico es 0.1234 justamente para que la columna $/run no pueda
# colar un "0.50" y dar por buena esta comprobacion sin que la tasa lo sea.
case "$rep" in
  *"0.25"*) echo "NOT ok - report.py mete los 'error' en el denominador (0.25)"; fail=$((fail+1));;
  *"0.50"*) echo "ok - report.py excluye los 'error' del denominador (0.50, no 0.25)"; pass=$((pass+1));;
  *) echo "NOT ok - report.py no da la tasa esperada: $(echo "$rep" | tr '\n' ' ')"; fail=$((fail+1));;
esac
case "$rep" in
  *"NO MEDIBLE"*) echo "ok - con un solo brazo, report.py se niega a dar un lift"; pass=$((pass+1));;
  *) echo "NOT ok - report.py da un veredicto sin brazo de control"; fail=$((fail+1));;
esac

EVAL_TS=2026-01-01T00:00:00Z EVAL_SHA=deadbee \
  "$PY" "$E/record.py" t1 off 1 fail "$T/conresult.jsonl" "$S" 2>/dev/null
rep2=$("$PY" "$E/report.py" --store "$S" 2>&1)
case "$rep2" in
  *"lift"*"SIRVE"*) echo "ok - con los dos brazos, report.py calcula el lift"; pass=$((pass+1));;
  *) echo "NOT ok - report.py no calcula el lift con dos brazos: $(echo "$rep2" | tr '\n' ' ')"; fail=$((fail+1));;
esac

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
