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

# --- 7. El emisor a LangSmith -----------------------------------------------
# Tres cosas, y la tercera es la que importa para "LangSmith LOCAL": si el
# emisor ignorara LANGSMITH_ENDPOINT, seguiria funcionando contra la nube y
# nadie lo notaria hasta que los datos aparecieran en el sitio equivocado.
P="$E/langsmith_push.py"
pay=$("$PY" "$P" --store "$S" --dry-run 2>/dev/null)
shape=$(printf '%s' "$pay" | "$PY" -c "
import json,sys
p=json.load(sys.stdin)['post']
par=[r for r in p if 'parent_run_id' not in r]
chi=[r for r in p if 'parent_run_id' in r]
ok=bool(par) and bool(chi) and all(
    c['dotted_order'].startswith(next(x['dotted_order'] for x in par if x['id']==c['parent_run_id'])+'.')
    for c in chi)
print('anidado' if ok else 'suelto')
" 2>/dev/null)
ck "$shape" "anidado" "langsmith_push: cada tarea cuelga de la traza de su brazo"

# Sin clave no puede ser un error: el eval ya midio, esto solo publica. Si
# reventara, el observatorio caido tumbaria la medicion entera.
env -u LANGSMITH_API_KEY -u CC_LANGSMITH_API_KEY \
  "$PY" "$P" --store "$S" >/dev/null 2>&1
ck "$?" 0 "langsmith_push: sin clave sale 0, no tumba el eval"

# Endpoint local inalcanzable: tiene que intentarlo AHI (no en la nube), fallar
# limpio y no escupir un traceback, que llevaria la cabecera x-api-key a stdout.
out=$(LANGSMITH_ENDPOINT=http://127.0.0.1:1 LANGSMITH_API_KEY=clave-de-mentira \
  "$PY" "$P" --store "$S" 2>&1); rc=$?
case "$out" in
  *Traceback*|*clave-de-mentira*)
    echo "NOT ok - langsmith_push filtra traceback o la clave al fallar"; fail=$((fail+1));;
  *127.0.0.1:1*)
    if [ "$rc" -eq 1 ]; then
      echo "ok - langsmith_push respeta LANGSMITH_ENDPOINT y falla limpio"; pass=$((pass+1))
    else
      echo "NOT ok - langsmith_push no senala fallo de subida (rc=$rc)"; fail=$((fail+1))
    fi;;
  *) echo "NOT ok - langsmith_push ignora LANGSMITH_ENDPOINT: $out"; fail=$((fail+1));;
esac

# --- 8. EVAL-CRITERIA.md no puede mentir sobre el numero de tareas ----------
# E12 (20-50 tareas) es el criterio incumplido que mas limita al resto. Si el doc
# dice "hay 6" cuando ya hay 20, el hueco declarado desaparece de la vista sin que
# nadie lo haya cerrado.
DOC="$PWD/knowledge/EVAL-CRITERIA.md"
if [ -f "$DOC" ]; then
  dicho=$(grep -o '\*\*hay [0-9]\+\*\*' "$DOC" | grep -o '[0-9]\+' | head -1)
  real=$(find "$E/tasks" -name '*.yaml' 2>/dev/null | wc -l)
  ck "${dicho:-ninguno}" "$real" "EVAL-CRITERIA.md declara el numero real de tareas"
fi

# --- 9. El evaluado no puede ver su propio oraculo -------------------------
# En la primera tirada real con API, 3 de 12 ejecuciones hicieron `cat _check.sh`
# desde su propio cwd, y en la tarea 06 lo hicieron LOS DOS BRAZOS antes de
# aprobar: el agente podia leer la condicion exacta que se le iba a exigir. El
# sensor es de comportamiento, no un grep: se corre run.sh entero con un `claude`
# de mentira que lo unico que hace es listar su directorio de trabajo.
W=$(mktemp -d) || exit 1
cp -R "$E" "$W/evals"
rm -f "$W"/evals/tasks/*.yaml "$W"/evals/runs.jsonl "$W"/evals/resultados-*.json
printf 'id: sonda\nprompt: |\n  no hagas nada\nsetup: |\n  : > archivo.txt\ncheck: |\n  true\n' \
  > "$W/evals/tasks/sonda.yaml"

mkdir -p "$W/bin"
cat > "$W/bin/claude" <<'STUB'
#!/usr/bin/env bash
ls -A > "$PROBE"
printf '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"ok"}]}}\n'
STUB
chmod +x "$W/bin/claude"

PROBE="$W/visto.txt" PATH="$W/bin:$PATH" bash "$W/evals/run.sh" >/dev/null 2>&1
visto=$(cat "$W/visto.txt" 2>/dev/null)
if [ -z "$visto" ]; then
  echo "NOT ok - la sonda no llego a ejecutarse: el sensor de fuga no midio nada"; fail=$((fail+1))
else
  fugas=""
  for n in _check.sh _prompt.txt _setup.sh _run.jsonl; do
    printf '%s\n' "$visto" | grep -qx -- "$n" && fugas="$fugas $n"
  done
  if [ -z "$fugas" ]; then
    echo "ok - el cwd del agente no contiene el check, el enunciado ni el transcript"; pass=$((pass+1))
  else
    echo "NOT ok - el agente ve su propio oraculo en el cwd:$fugas"; fail=$((fail+1))
  fi
  # Contraprueba: si la sonda no viera NADA de la tarea, el listado estaria vacio
  # por una averia y el check de arriba pasaria en falso.
  if printf '%s\n' "$visto" | grep -qx -- 'archivo.txt'; then
    echo "ok - la sonda si ve los ficheros de la tarea (el listado no esta vacio)"; pass=$((pass+1))
  else
    echo "NOT ok - la sonda no ve ni los ficheros del setup: listado sospechoso"; fail=$((fail+1))
  fi
fi
rm -rf "$W"

# --- 10. Ningun check puede aprobar el estado inicial ----------------------
# Con el setup hecho y SIN agente, todo check tiene que dar exactamente 1.
# Un 0 seria un check que aprueba sin que nadie haya hecho nada. Un 2 tambien
# es defecto: run.sh lo traduce a 'error' y la tarea sale del denominador, asi
# que un agente que no hace nada dejaria de contar como suspenso. Aqui se
# colaron cuatro: `grep` sobre un fichero inexistente devuelve 2, no 1.
V=$(mktemp -d) || exit 1
# Transcript no vacio pero inutil: el agente dice que lo hizo y no toca nada.
# Vacio daria 2 (no medible) y taparia justo lo que se quiere distinguir.
printf '%s\n' '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"Hecho."}]}}' > "$V/inutil.jsonl"
malos=""; sospechosos=""
for f in "$E"/tasks/*.yaml; do
  tid=$(basename "$f" .yaml)
  vd=$(mktemp -d); vm=$(mktemp -d)
  "$PY" -c "
import os, sys, yaml
t = yaml.safe_load(open(sys.argv[1])); m = sys.argv[2]
open(os.path.join(m,'_setup.sh'),'w').write(t.get('setup') or ':\n')
open(os.path.join(m,'_check.sh'),'w').write(t['check'])
" "$f" "$vm"
  cp "$V/inutil.jsonl" "$vm/_run.jsonl"
  ( cd "$vd" && bash "$vm/_setup.sh" >/dev/null 2>&1
    PY="$PY" GRADE="$E/grade.py" RUN_JSONL="$vm/_run.jsonl" bash "$vm/_check.sh" >/dev/null 2>&1 )
  case $? in
    0) malos="$malos $tid";;
    2) sospechosos="$sospechosos $tid";;
  esac
  rm -rf "$vd" "$vm"
done
rm -rf "$V"
if [ -n "$malos" ]; then
  echo "NOT ok - checks que aprueban sin agente:$malos"; fail=$((fail+1))
else
  echo "ok - ningun check aprueba el estado inicial"; pass=$((pass+1))
fi
if [ -n "$sospechosos" ]; then
  echo "NOT ok - checks que dan 'error' (2) donde deberian dar 'fail' (1):$sospechosos"; fail=$((fail+1))
else
  echo "ok - no hacer nada cuenta como fallo, no como averia del instrumento"; pass=$((pass+1))
fi

# --- 11. Mitad debe-disparar, mitad no-debe-disparar (E11) ----------------
# Sin tareas negativas el eval solo puede premiar un harness mas ruidoso: nada
# mide lo que cuesta un falso positivo. La proporcion se declara por tarea en
# `tipo:` y se cuenta aqui; se admite un desvio de una tarea para numeros impares.
pos=$(grep -l '^tipo: positiva' "$E"/tasks/*.yaml 2>/dev/null | wc -l)
neg=$(grep -l '^tipo: negativa' "$E"/tasks/*.yaml 2>/dev/null | wc -l)
sin=$(grep -L '^tipo: \(positiva\|negativa\)' "$E"/tasks/*.yaml 2>/dev/null | tr '\n' ' ')
if [ -n "$sin" ]; then
  echo "NOT ok - tareas sin 'tipo: positiva|negativa': $sin"; fail=$((fail+1))
else
  echo "ok - toda tarea declara si el harness debe disparar o no"; pass=$((pass+1))
fi
d=$((pos - neg)); [ "$d" -lt 0 ] && d=$((-d))
if [ "$d" -le 1 ]; then
  echo "ok - mezcla equilibrada: $pos positivas / $neg negativas"; pass=$((pass+1))
else
  echo "NOT ok - mezcla desequilibrada: $pos positivas / $neg negativas (desvio $d)"; fail=$((fail+1))
fi

# --- 12. El lift agregado no puede tapar una cancelacion ------------------
# Caso construido: el harness acierta TODAS las positivas y suspende TODAS las
# negativas. Sumado da lift 0,00 y report.py lo llama "NEUTRO (ruido)", que es
# el peor desenlace posible porque parece que no pasa nada. El desglose por
# polaridad tiene que enseñar el +1,00 y el -1,00 por separado.
Z=$(mktemp -d) || exit 1
"$PY" - "$Z/cancela.jsonl" <<'PYEOF'
import json, sys
def r(task, arm, res, tipo):
    return {"ts": "2026-01-01T00:00:00Z", "task": task, "arm": arm, "tipo": tipo,
            "attempt": 1, "result": res, "model": "m", "cost_usd": 0.1,
            "duration_api_ms": 1, "input_tokens": 1}
rows = []
for i in range(4):
    rows += [r("p%d" % i, "on", "pass", "positiva"), r("p%d" % i, "off", "fail", "positiva"),
             r("n%d" % i, "on", "fail", "negativa"), r("n%d" % i, "off", "pass", "negativa")]
open(sys.argv[1], "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
PYEOF
canc=$("$PY" "$E/report.py" --store "$Z/cancela.jsonl" 2>&1)
rm -rf "$Z"
if printf '%s' "$canc" | grep -q 'NEUTRO'; then
  if printf '%s' "$canc" | grep -q 'FALSOS POSITIVOS'; then
    echo "ok - el desglose por polaridad destapa la cancelacion que el total esconde"; pass=$((pass+1))
  else
    echo "NOT ok - el total dice NEUTRO y nada avisa de los falsos positivos"; fail=$((fail+1))
  fi
else
  echo "NOT ok - el caso de cancelacion ya no produce un total neutro: sensor obsoleto"; fail=$((fail+1))
fi

# El campo del que vive todo lo anterior. Si record.py dejara de escribirlo, el
# desglose desapareceria en silencio y el informe volveria a un solo numero.
EVAL_TS=2026-01-01T00:00:00Z EVAL_SHA=deadbee \
  "$PY" "$E/record.py" 01-no-releer-tras-editar on 9 pass "$T/conresult.jsonl" "$S" 2>/dev/null
ck "$("$PY" -c "
import json,sys
for l in open(sys.argv[1]):
    r=json.loads(l)
    if r.get('attempt')==9: print(r.get('tipo')); break
" "$S" 2>/dev/null)" "positiva" "record.py saca la polaridad del yaml de la tarea"

# --- 13. Los brazos de ablacion tienen que seguir siendo brazos -------------
# Un brazo de ablacion cuyo flag ya no existe no da error: corre con el harness
# COMPLETO y se guarda con la etiqueta de la pieza retirada. El informe leeria
# "no se distingue del ruido" para las tres piezas y la conclusion seria que
# ninguna aporta. Este sensor mira el --help del CLI instalado, gratis.
if command -v claude >/dev/null 2>&1; then
  H=$(claude --help 2>&1)
  for flag in --setting-sources --disable-slash-commands --strict-mcp-config --model; do
    if printf '%s' "$H" | grep -q -- "$flag"; then
      echo "ok - el CLI sigue teniendo $flag (un brazo de ablacion depende de el)"; pass=$((pass+1))
    else
      echo "NOT ok - $flag ya no existe: el brazo que lo usa mide el harness completo"; fail=$((fail+1))
    fi
  done
else
  echo "ok - claude no instalado: comprobacion de flags omitida"; pass=$((pass+1))
fi

# Un ARM mal escrito corria con el harness puesto y se guardaba con el typo por
# etiqueta. `ARM=Off` es el caso peligroso: un control que no controla nada.
#
# Este bloque llamaba a run.sh a pelo y con ARM="" en la lista. Escribiendolo se
# gastaron 4 llamadas reales y 1,32 USD: `ARM="${ARM:-on}"` convierte la cadena
# vacia en 'on', asi que el caso "invalido" era en realidad el brazo completo y
# arranco el eval de pago dentro de la suite gratuita. De ahi las dos medidas:
# ARM="" fuera de la lista, y un `claude` de pega en el PATH para que ni un error
# futuro en este sensor pueda volver a llegar a la API.
FAKE=$(mktemp -d) || exit 1
export PROBE="$FAKE/invocado"
cat > "$FAKE/claude" <<'STUB'
#!/usr/bin/env bash
touch "$PROBE"
STUB
chmod +x "$FAKE/claude"
# Sobre una COPIA, como el §9, y con una sola tarea: si el guardia se rompiera,
# este sensor no puede escribir en el runs.jsonl de verdad ni tardar 80 tirones.
# Un sensor que ensucia el almacen que vigila deja de ser un sensor.
cp -R "$E" "$FAKE/evals"
rm -f "$FAKE"/evals/tasks/*.yaml "$FAKE"/evals/runs.jsonl "$FAKE"/evals/resultados-*.json
printf 'id: sonda\ntipo: positiva\nprompt: |\n  nada\nsetup: |\n  :\ncheck: |\n  true\n' \
  > "$FAKE/evals/tasks/sonda.yaml"
for malo in basura Off ON on-; do
  out=$(PATH="$FAKE:$PATH" ARM="$malo" RUNS=1 bash "$FAKE/evals/run.sh" 2>&1); rc=$?
  if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'ARM desconocido'; then
    echo "ok - ARM='$malo' se rechaza antes de gastar una llamada"; pass=$((pass+1))
  else
    echo "NOT ok - ARM='$malo' no se rechaza (rc=$rc): brazo sin sentido con etiqueta creible"; fail=$((fail+1))
  fi
done
# Y el rechazo tiene que ocurrir ANTES de invocar al agente, no despues: si el
# `claude` de pega se llego a ejecutar, el guardia esta puesto demasiado tarde.
if [ -e "$PROBE" ]; then
  echo "NOT ok - un ARM invalido llego a invocar al agente: el guardia va demasiado tarde"; fail=$((fail+1))
else
  echo "ok - ningun ARM invalido invoco al agente"; pass=$((pass+1))
fi

# El informe de ablacion, con las tres lecturas: la pieza aporta, la pieza es
# indistinguible del ruido, y los brazos no son comparables porque el modelo
# cambio (riesgo real: 'sin-ajustes' tira el settings.json que fija el modelo).
A=$(mktemp -d) || exit 1
"$PY" - "$A/abl.jsonl" <<'PYEOF2'
import json, sys
def r(task, arm, res, model="m1"):
    return {"ts": "2026-01-01T00:00:00Z", "task": task, "arm": arm, "tipo": "positiva",
            "attempt": 1, "result": res, "model": model, "cost_usd": 0.1,
            "duration_api_ms": 1, "input_tokens": 1}
rows = []
for i in range(10):
    rows += [r("t%d" % i, "on", "pass"),
             r("t%d" % i, "sin-ajustes", "fail" if i < 6 else "pass"),
             r("t%d" % i, "sin-skills", "pass"),
             r("t%d" % i, "sin-mcp", "pass", model="m2")]
open(sys.argv[1], "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
PYEOF2
abl=$("$PY" "$E/report.py" --store "$A/abl.jsonl" 2>&1)
rm -rf "$A"
ck "$(printf '%s' "$abl" | grep -c 'sin-ajustes.*la pieza APORTA')" "1" \
   "quitar una pieza y bajar el acierto se lee como que la pieza aporta"
ck "$(printf '%s' "$abl" | grep -c 'sin-skills.*no se distingue del ruido')" "1" \
   "una pieza cuya retirada no cambia nada no se vende como hallazgo"
ck "$(printf '%s' "$abl" | grep -c 'sin-mcp.*NO COMPARABLE')" "1" \
   "dos brazos con modelos distintos no se restan: mediria el modelo"

# Y sin brazos de ablacion, el informe tiene que decir que falta, no callarse:
# un hueco silencioso se lee como que la pregunta ya esta contestada.
ck "$("$PY" "$E/report.py" --store "$S" 2>&1 | grep -c 'ablacion por componente')" "1" \
   "el informe declara el hueco de ablacion cuando no hay brazos que comparar"

# --- 14. Un conjunto saturado tiene que decirlo (E16) ----------------------
# Hamel: una tasa que tiende a 100 % dejo de informar. El caso construido es el
# peor: casi todas las tareas dan el mismo resultado en los DOS brazos, asi que
# son peso muerto y el informe seguiria presumiendo de "n tareas" mientras las
# que deciden son una.
W=$(mktemp -d) || exit 1
"$PY" - "$W/saturado.jsonl" <<'PYEOF'
import json, sys
def r(task, arm, res):
    return {"ts": "2026-01-01T00:00:00Z", "task": task, "arm": arm, "tipo": "positiva",
            "attempt": 1, "result": res, "model": "m", "cost_usd": 0.1,
            "duration_api_ms": 1, "input_tokens": 1}
rows = []
for i in range(5):
    rows += [r("t%d" % i, "on", "pass"), r("t%d" % i, "off", "pass")]
# La sexta si discrimina: sin ella no se distingue "saturado" de "vacio".
rows += [r("t5", "on", "pass"), r("t5", "off", "fail")]
open(sys.argv[1], "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
PYEOF
sat=$("$PY" "$E/report.py" --store "$W/saturado.jsonl" 2>&1)
rm -rf "$W"
if printf '%s' "$sat" | grep -q 'mudas: 5/6'; then
  echo "ok - el informe cuenta las tareas que no distinguen los brazos"; pass=$((pass+1))
else
  echo "NOT ok - las tareas mudas no se cuentan: el conjunto se satura en silencio"; fail=$((fail+1))
fi
if printf '%s' "$sat" | grep -q 'SATURADO'; then
  echo "ok - un conjunto sin poder discriminante se declara SATURADO"; pass=$((pass+1))
else
  echo "NOT ok - conjunto saturado sin aviso: la tasa subira sin que el harness mejore"; fail=$((fail+1))
fi
# Y con un solo brazo no puede inventarse la respuesta: sin control no hay forma
# de saber cual es muda, y decir "0 mudas" seria mentir por omision.
Y=$(mktemp -d) || exit 1
"$PY" - "$Y/unbrazo.jsonl" <<'PYEOF'
import json, sys
r = {"ts": "2026-01-01T00:00:00Z", "task": "t1", "arm": "on", "tipo": "positiva",
     "attempt": 1, "result": "pass", "model": "m", "cost_usd": 0.1,
     "duration_api_ms": 1, "input_tokens": 1}
open(sys.argv[1], "w").write(json.dumps(r) + "\n")
PYEOF
uno=$("$PY" "$E/report.py" --store "$Y/unbrazo.jsonl" 2>&1)
rm -rf "$Y"
if printf '%s' "$uno" | grep -q 'para saber que tareas son mudas'; then
  echo "ok - sin brazo de control, el poder discriminante se declara no medible"; pass=$((pass+1))
else
  echo "NOT ok - el informe se pronuncia sobre tareas mudas sin brazo de control"; fail=$((fail+1))
fi

# --- 15. La infraestructura es variable experimental (E14) ------------------
# Esto corre en WSL2 con el proxy Headroom compitiendo por CPU. Sin registrar la
# carga, una latencia que empeora no se distingue de una maquina ocupada, y el
# "a que coste" del informe compara dos brazos medidos en condiciones distintas.
V=$(mktemp -d) || exit 1
EVAL_TS=2026-01-01T00:00:00Z EVAL_SHA=deadbee \
  "$PY" "$E/record.py" t1 on 1 pass "$T/conresult.jsonl" "$V/maq.jsonl" 2>/dev/null
ck "$("$PY" -c "
import json,sys
r=json.loads(open(sys.argv[1]).readline())
print(all(r.get(k) is not None for k in ('load1','cpus','mem_free_mb')))
" "$V/maq.jsonl" 2>/dev/null)" "True" "record.py registra carga, CPUs y memoria libre"

# Y el dato tiene que servir para algo: dos brazos con la maquina distinta de
# ocupada no tienen comparable el coste ni la latencia, y hay que decirlo.
"$PY" - "$V/carga.jsonl" <<'PYEOF'
import json, sys
def r(arm, res, load):
    return {"ts": "2026-01-01T00:00:00Z", "task": "t1", "arm": arm, "tipo": "positiva",
            "attempt": 1, "result": res, "model": "m", "cost_usd": 0.1,
            "duration_api_ms": 1, "input_tokens": 1, "load1": load, "cpus": 8,
            "mem_free_mb": 100}
rows = [r("on", "pass", 0.1), r("off", "fail", 20.0)]
open(sys.argv[1], "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
PYEOF
carga=$("$PY" "$E/report.py" --store "$V/carga.jsonl" 2>&1)
if printf '%s' "$carga" | grep -q 'AVISO: los dos brazos corrieron con la maquina distinta'; then
  echo "ok - dos brazos con cargas dispares avisan de que el coste no es comparable"; pass=$((pass+1))
else
  echo "NOT ok - carga 0.1 contra 20.0 en 8 CPUs y ni un aviso: el coste se lee como si nada"; fail=$((fail+1))
fi
# Un aviso que sale siempre es tan inutil como no tenerlo.
"$PY" - "$V/tranquila.jsonl" <<'PYEOF'
import json, sys
def r(arm, res, load):
    return {"ts": "2026-01-01T00:00:00Z", "task": "t1", "arm": arm, "tipo": "positiva",
            "attempt": 1, "result": res, "model": "m", "cost_usd": 0.1,
            "duration_api_ms": 1, "input_tokens": 1, "load1": load, "cpus": 8,
            "mem_free_mb": 100}
rows = [r("on", "pass", 0.4), r("off", "fail", 0.5)]
open(sys.argv[1], "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
PYEOF
tranq=$("$PY" "$E/report.py" --store "$V/tranquila.jsonl" 2>&1)
rm -rf "$V"
if printf '%s' "$tranq" | grep -q 'AVISO: los dos brazos corrieron'; then
  echo "NOT ok - el aviso de carga salta con 0.4 contra 0.5: sale siempre y no informa"; fail=$((fail+1))
else
  echo "ok - con la maquina igual de tranquila en los dos brazos no hay aviso"; pass=$((pass+1))
fi

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
