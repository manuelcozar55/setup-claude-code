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

# Y la fila retirada del computo tampoco se publica aqui. report.py la deja fuera
# de TODO computo; si el observatorio la ensenara como un fail normal, el dato
# retirado volveria por la puerta de atras y las dos vistas del mismo almacen
# dirian cosas distintas. Dos aserciones y ninguna vale sola: la primera compara
# los dos sentidos (con la clave se publica una menos, sin ella se publica), la
# segunda exige que la retirada no sea muda.
X=$(mktemp -d) || exit 1
"$PY" - "$X/con.jsonl" "$X/sin.jsonl" <<'PYEOF'
import json, sys
def r(task, arm, res, **k):
    d = {"ts": "2026-01-01T00:00:00Z", "task": task, "arm": arm, "tipo": "positiva",
         "attempt": 1, "result": res, "model": "m", "cost_usd": 0.1,
         "duration_api_ms": 5, "input_tokens": 1}
    d.update(k)
    return d
# El mismo almacen dos veces, y la unica diferencia entre los dos es la clave
# 'excluded': asi la asercion mide la retirada y no otra cosa.
rows = [r("01-a", "on", "pass"), r("02-b", "on", "fail"), r("01-a", "off", "pass")]
open(sys.argv[2], "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
rows[1]["excluded"] = "instrumento averiado (E28)"
open(sys.argv[1], "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
PYEOF
ls_hijos() {
  "$PY" "$P" --store "$1" --dry-run 2>/dev/null | "$PY" -c "
import json, sys
print(sum(1 for r in json.load(sys.stdin)['post'] if 'parent_run_id' in r))" 2>/dev/null
}
ck "$(ls_hijos "$X/con.jsonl") $(ls_hijos "$X/sin.jsonl")" "2 3" \
   "langsmith_push: la fila retirada no se publica, y sin retirar si se publicaria"
# El aviso va a stderr a proposito: stdout es el payload y tiene que seguir siendo
# JSON puro, como comprueba la asercion de arriba de esta seccion.
avi=$("$PY" "$P" --store "$X/con.jsonl" --dry-run 2>&1 >/dev/null)
case "$avi" in
  *"no se publican 1 fila"*02-b*)
    echo "ok - langsmith_push dice que retiro una fila, no la calla"; pass=$((pass+1));;
  *) echo "NOT ok - langsmith_push retira la fila en silencio: $avi"; fail=$((fail+1));;
esac
rm -f "$X"/*.jsonl; rmdir "$X" 2>/dev/null

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

# --- 16. LangSmith local de verdad: el emisor contra algo que escucha -------
# El bloque 7 comprueba la FORMA del payload en seco. Aqui el payload viaja por
# red hasta un receptor que habla el ingest de LangSmith, y se mira lo que queda
# guardado al otro lado. Sin esto, "medible en LangSmith local" era una
# afirmacion sin sensor: LangSmith autoalojado exige licencia de pago, asi que
# nunca se habia enviado una traza a nada y el emisor solo se probaba en seco.
L=$(mktemp -d) || exit 1

espera_puerto() {  # $1 = log del receptor -> imprime el puerto, vacio si no arranco
  for _ in $(seq 1 60); do
    p=$(sed -n 's#.*127\.0\.0\.1:\([0-9]*\).*#\1#p' "$1" 2>/dev/null | head -1)
    [ -n "$p" ] && { printf '%s' "$p"; return 0; }
    sleep 0.2
  done
  return 1
}

"$PY" "$E/langsmith_local.py" --port 0 --store "$L/rx.jsonl" --max-requests 1 \
  > "$L/srv.log" 2>&1 &
srv=$!
if ! port=$(espera_puerto "$L/srv.log"); then
  echo "NOT ok - el receptor local no llego a escuchar; los 3 checks de red no corren"
  fail=$((fail+1)); kill "$srv" 2>/dev/null
else
  LANGSMITH_ENDPOINT="http://127.0.0.1:$port" LANGSMITH_API_KEY=local \
    CC_LANGSMITH_PROJECT=prueba "$PY" "$P" --store "$S" >/dev/null 2>&1
  ck "$?" 0 "langsmith: el emisor sube de verdad contra un receptor local que escucha"
  wait "$srv" 2>/dev/null

  # Lo que importa no es que llegue, es que llegue ARBOL. Una lista plana de
  # runs sueltos se sube igual de bien y no se puede leer por brazo.
  forma=$("$PY" - "$L/rx.jsonl" <<'PYEOF'
import json, sys
runs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
par = [r for r in runs if not r.get("parent_run_id")]
chi = [r for r in runs if r.get("parent_run_id")]
byid = {r["id"]: r for r in par}
ok = (len(par) >= 1 and len(chi) >= 1
      and all(c["parent_run_id"] in byid for c in chi)
      and all(c["dotted_order"].startswith(byid[c["parent_run_id"]]["dotted_order"] + ".")
              for c in chi)
      and all(r.get("session_name") == "prueba" for r in runs))
print("arbol" if ok else "roto")
PYEOF
)
  ck "$forma" "arbol" "langsmith: al otro lado queda un arbol por brazo, no una lista suelta"

  # Y cada traza tiene que decir de que brazo viene: comparar on con off es el
  # objetivo entero. Trazas sin brazo son bonitas y no responden a nada.
  brazos=$("$PY" - "$L/rx.jsonl" <<'PYEOF'
import json, sys
runs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
print(",".join(sorted({((r.get("extra") or {}).get("metadata") or {}).get("arm") or "?"
                       for r in runs})))
PYEOF
)
  ck "$brazos" "off,on" "langsmith: cada traza llega etiquetada con su brazo"
fi

# "Sin clave sale 0" no basta: podria salir 0 y haber subido igual. Con un
# receptor delante se comprueba lo unico que importa, que no llego nada.
"$PY" "$E/langsmith_local.py" --port 0 --store "$L/vacio.jsonl" --max-requests 1 \
  > "$L/srv2.log" 2>&1 &
srv2=$!
if port2=$(espera_puerto "$L/srv2.log"); then
  env -u LANGSMITH_API_KEY -u CC_LANGSMITH_API_KEY \
    LANGSMITH_ENDPOINT="http://127.0.0.1:$port2" \
    "$PY" "$P" --store "$S" >/dev/null 2>&1
fi
kill "$srv2" 2>/dev/null; wait "$srv2" 2>/dev/null
if [ -s "$L/vacio.jsonl" ]; then
  echo "NOT ok - sin clave el emisor subio igual: la traza salio a un sitio sin autenticar"
  fail=$((fail+1))
else
  echo "ok - sin clave no llega nada al receptor, no solo 'sale 0'"; pass=$((pass+1))
fi
rm -rf "$L"

# --- 17. El puente a Phoenix (interfaz local de verdad) ---------------------
# Phoenix es la unica via a "medible en local" con interfaz: LangSmith autoalojado
# es de pago y no tiene tramo gratuito. El emisor necesita SDK y vive en el venv de
# herramientas, pero su --dry-run no necesita nada, y es ahi donde se comprueba lo
# que puede romperse en silencio: la forma del arbol y las etiquetas.
F=$(mktemp -d) || exit 1
"$PY" - "$F/mix.jsonl" <<'PYEOF'
import json, sys
def r(task, arm, res):
    return {"ts": "2026-01-01T00:00:00Z", "task": task, "arm": arm, "tipo": "positiva",
            "attempt": 1, "result": res, "model": "m", "cost_usd": 0.1,
            "duration_api_ms": 5, "input_tokens": 1}
# A proposito en orden NO alfabetico: si el emisor no ordena, el arbol se lee
# distinto en cada tirada y comparar dos ejecuciones deja de ser posible.
rows = [r("03-c", "on", "pass"), r("01-a", "on", "pass"), r("02-b", "on", "fail"),
        r("01-a", "off", "error")]
open(sys.argv[1], "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
PYEOF
"$PY" "$E/phoenix_push.py" --store "$F/mix.jsonl" --dry-run > "$F/arbol.json" 2>/dev/null

etiq=$("$PY" - "$F/arbol.json" <<'PYEOF'
import json, sys
t = json.load(open(sys.argv[1]))
# Un padre por brazo, y cada hijo etiquetado con el brazo de SU padre: sin eso
# no se puede filtrar por brazo, que es la comparacion entera.
ok = (len(t) == 2
      and sorted(p["attrs"]["eval.arm"] for p in t) == ["off", "on"]
      and all(h["attrs"]["eval.arm"] == p["attrs"]["eval.arm"]
              for p in t for h in p["hijos"]))
print("etiquetado" if ok else "suelto")
PYEOF
)
ck "$etiq" "etiquetado" "phoenix: un padre por brazo y cada tarea etiquetada con el suyo"

orden=$("$PY" - "$F/arbol.json" <<'PYEOF'
import json, sys
t = json.load(open(sys.argv[1]))
on = [p for p in t if p["attrs"]["eval.arm"] == "on"][0]
n = [h["nombre"] for h in on["hijos"]]
print("ordenado" if n == sorted(n) else "azar:" + ",".join(n))
PYEOF
)
ck "$orden" "ordenado" "phoenix: las tareas salen ordenadas, no al azar del diccionario"

# Cuarta vez que el repo defiende lo mismo: 'error' no es un cero. Si el puente lo
# coercionara, la interfaz ensenaria un suspenso donde no se pudo medir.
err=$("$PY" - "$F/arbol.json" <<'PYEOF'
import json, sys
t = json.load(open(sys.argv[1]))
off = [p for p in t if p["attrs"]["eval.arm"] == "off"][0]
h = off["hijos"][0]
print(h["attrs"]["eval.result"] + "/" + str(json.loads(h["attrs"]["output.value"])["result"]))
PYEOF
)
ck "$err" "error/error" "phoenix: un 'error' viaja como error, no como suspenso"

# Lo mismo que en la seccion 7 y por lo mismo: report.py deja la fila fuera de todo
# computo y este puente la publicaba como un fail normal.
X=$(mktemp -d) || exit 1
"$PY" - "$X/con.jsonl" "$X/sin.jsonl" <<'PYEOF'
import json, sys
def r(task, arm, res, **k):
    d = {"ts": "2026-01-01T00:00:00Z", "task": task, "arm": arm, "tipo": "positiva",
         "attempt": 1, "result": res, "model": "m", "cost_usd": 0.1,
         "duration_api_ms": 5, "input_tokens": 1}
    d.update(k)
    return d
# El mismo almacen dos veces, y la unica diferencia entre los dos es la clave
# 'excluded': asi la asercion mide la retirada y no otra cosa.
rows = [r("01-a", "on", "pass"), r("02-b", "on", "fail"), r("01-a", "off", "pass")]
open(sys.argv[2], "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
rows[1]["excluded"] = "instrumento averiado (E28)"
open(sys.argv[1], "w").write("\n".join(json.dumps(x) for x in rows) + "\n")
PYEOF
ph_hijos() {
  "$PY" "$E/phoenix_push.py" --store "$1" --dry-run 2>/dev/null | "$PY" -c "
import json, sys
print(sum(len(p['hijos']) for p in json.load(sys.stdin)))" 2>/dev/null
}
ck "$(ph_hijos "$X/con.jsonl") $(ph_hijos "$X/sin.jsonl")" "2 3" \
   "phoenix: la fila retirada no se publica, y sin retirar si se publicaria"
avi=$("$PY" "$E/phoenix_push.py" --store "$X/con.jsonl" --dry-run 2>&1 >/dev/null)
case "$avi" in
  *"no se publican 1 fila"*02-b*)
    echo "ok - phoenix dice que retiro una fila, no la calla"; pass=$((pass+1));;
  *) echo "NOT ok - phoenix retira la fila en silencio: $avi"; fail=$((fail+1));;
esac
rm -f "$X"/*.jsonl; rmdir "$X" 2>/dev/null
rm -rf "$F"

# --- 18. El modelo que se apunta es el que hizo el trabajo (E24) ------------
# Cada sesion de `claude -p` gasta ~15 tokens en un haiku auxiliar, y ese aparece
# el primero en modelUsage. Apuntando el primero, 40 tiradas de opus quedaron
# etiquetadas como haiku y el guardia de E24 se nego a comparar dos brazos que
# habian corrido con el MISMO modelo. Un guardia alimentado con el dato
# equivocado no protege: bloquea lo bueno y deja pasar lo malo.
G=$(mktemp -d) || exit 1
"$PY" - "$G/t.jsonl" <<'PYEOF'
import json, sys
# El auxiliar va primero A PROPOSITO: es el orden real de un transcript.
open(sys.argv[1], "w").write(json.dumps({
    "type": "result", "total_cost_usd": 0.1, "duration_api_ms": 1, "num_turns": 1,
    "usage": {"input_tokens": 1},
    "modelUsage": {"aux-mini": {"outputTokens": 15},
                   "el-que-trabaja": {"outputTokens": 900}}}) + "\n")
PYEOF
EVAL_TS=2026-01-01T00:00:00Z EVAL_SHA=deadbee \
  "$PY" "$E/record.py" t1 on 1 pass "$G/t.jsonl" "$G/r.jsonl" 2>/dev/null
ck "$("$PY" -c "
import json,sys
print(json.loads(open(sys.argv[1]).readline())['model'])
" "$G/r.jsonl" 2>/dev/null)" "el-que-trabaja" "se apunta el modelo que hizo el trabajo, no el auxiliar de 15 tokens"

# --- 19. Ablar una pieza que nunca se encendio no mide nada (E27) -----------
# Medido en las 26 tiradas reales del brazo completo: CERO invocaciones de Skill,
# porque el agente corre en un mktemp -d y las skills del repo no viajan ahi. Sin
# este guardia, ARM=sin-skills daria delta 0 y el informe lo leeria como "la pieza
# no aporta", que es una conclusion falsa con aspecto de resultado.
H=$(mktemp -d) || exit 1
"$PY" - "$H" <<'PYEOF'
import json, os, sys
H = sys.argv[1]
def r(arm, res, skills):
    return {"ts": "2026-01-01T00:00:00Z", "task": "t1", "arm": arm, "tipo": "positiva",
            "attempt": 1, "result": res, "model": "m", "cost_usd": 0.1,
            "duration_api_ms": 1, "input_tokens": 1, "skill_calls": skills,
            "mcp_calls": 0}
for nombre, n in (("apagada.jsonl", 0), ("encendida.jsonl", 3)):
    filas = [r("on", "pass", n), r("sin-skills", "fail", 0)]
    open(os.path.join(H, nombre), "w").write(
        "\n".join(json.dumps(x) for x in filas) + "\n")
PYEOF
apagada=$("$PY" "$E/report.py" --store "$H/apagada.jsonl" 2>&1)
encendida=$("$PY" "$E/report.py" --store "$H/encendida.jsonl" 2>&1)
if printf '%s' "$apagada" | grep -q 'sin-skills *NO MEDIBLE'; then
  echo "ok - ablar skills que no se activaron ni una vez sale como NO MEDIBLE"; pass=$((pass+1))
else
  echo "NOT ok - cero activaciones y aun asi opina sobre la pieza: un 0 que parece hallazgo"; fail=$((fail+1))
fi
# El brazo que NO se ha corrido tambien tiene que decirlo, y decir si merece la
# pena: son 20 llamadas de API cada uno.
if printf '%s' "$apagada" | grep -q 'sin-mcp .*no mediria nada'; then
  echo "ok - el brazo de ablacion sin correr avisa de que correrlo no mediria nada"; pass=$((pass+1))
else
  echo "NOT ok - calla sobre el brazo que falta: 20 llamadas para no medir nada"; fail=$((fail+1))
fi
# Y con la pieza encendida tiene que volver a medir: un guardia que calla siempre
# informa lo mismo que ninguno.
if printf '%s' "$encendida" | grep -q 'sin-skills *NO MEDIBLE'; then
  echo "NOT ok - con 3 activaciones sigue diciendo NO MEDIBLE: el guardia no mide, tapa"; fail=$((fail+1))
else
  echo "ok - con la pieza activada la ablacion se mide"; pass=$((pass+1))
fi

# --- 20. Todo check tiene que APROBAR una solucion correcta (E28) -----------
# El §10 comprueba el lado facil: que ningun check apruebe el estado inicial.
# Faltaba el otro, y por ahi se colo un corrector roto: la 12 suspendia por el
# __pycache__ que deja verificar el trabajo, o sea castigaba justo lo que el
# harness prescribe. Empujaba la nota en contra del harness, que es la
# direccion que menos sospechas levanta.
SOLD=$(mktemp -d) || exit 1
malas=""; con_sol=0; sin_sol=0
for f in "$E"/tasks/*.yaml; do
  id=$(basename "$f" .yaml)
  sol=$("$PY" -c "import sys,yaml;print((yaml.safe_load(open(sys.argv[1])) or {}).get('solucion') or '')" "$f")
  if [ -z "$sol" ]; then sin_sol=$((sin_sol+1)); continue; fi
  con_sol=$((con_sol+1))
  w="$SOLD/$id"; mkdir -p "$w"
  # El andamio vive FUERA del directorio de trabajo: si no, los tres ficheros
  # auxiliares cuentan como ficheros sembrados en las tareas de alcance.
  "$PY" -c "
import os, sys, yaml
t = yaml.safe_load(open(sys.argv[1])); d = sys.argv[2]; i = sys.argv[3]
for k, n in (('setup', 'setup'), ('solucion', 'sol'), ('check', 'check')):
    open(os.path.join(d, '%s-%s.sh' % (n, i)), 'w').write(t.get(k) or ':\n')
" "$f" "$SOLD" "$id"
  ( cd "$w" || exit 1
    bash "$SOLD/setup-$id.sh" >/dev/null 2>&1
    bash "$SOLD/sol-$id.sh" >/dev/null 2>&1
    PY="$PY" GRADE="$E/grade.py" RUN_JSONL="$w/_run.jsonl" bash "$SOLD/check-$id.sh" >/dev/null 2>&1 ) || malas="$malas $id"
done
if [ -z "$malas" ]; then
  echo "ok - los $con_sol checks con solucion declarada la aprueban"; pass=$((pass+1))
else
  echo "NOT ok - el check suspende una solucion correcta:$malas"; fail=$((fail+1))
fi
# Contar no es aseverar: con con_sol=0 esta seccion daba dos verdes sin medir
# nada. El suelo sube cuando suben las soluciones declaradas (Tarea 4: 10).
if [ "$con_sol" -ge 10 ]; then
  echo "ok - cobertura de solucion: $con_sol declaradas, $sin_sol sin declarar"
  pass=$((pass+1))
else
  echo "NOT ok - cobertura de solucion insuficiente: $con_sol declaradas, se exigen 10"
  fail=$((fail+1))
fi

# --- 21. Se puede saber lo que cuesta una tirada sin pagarla (E29) ----------
# El Makefile declaraba "40 llamadas / ~12 USD" escrito a mano. Una cifra sin
# sensor se pudre igual que una afirmacion sin sensor.
FAKEBIN=$(mktemp -d) || exit 1
PROBE="$FAKEBIN/invocado"
printf '#!/usr/bin/env bash\ntouch "%s"\nexit 0\n' "$PROBE" > "$FAKEBIN/claude"
chmod +x "$FAKEBIN/claude"
salida=$(PATH="$FAKEBIN:$PATH" DRYRUN=1 bash "$E/run.sh" 2>&1); rc=$?
ck "$rc" 0 "DRYRUN=1 sale con 0"
if [ -e "$PROBE" ]; then
  echo "NOT ok - DRYRUN=1 invoco a claude: no es un ensayo, es la tirada"; fail=$((fail+1))
else
  echo "ok - DRYRUN=1 no invoca a claude ni una vez"; pass=$((pass+1))
fi
if printf '%s' "$salida" | grep -q 'llamadas'; then
  echo "ok - DRYRUN=1 dice cuantas llamadas haria"; pass=$((pass+1))
else
  echo "NOT ok - DRYRUN=1 no dice cuantas llamadas haria"; fail=$((fail+1))
fi
# Correr dos tareas no puede costar lo que cuestan veinte, y pedir una que no
# existe tiene que doler: si se ignora en silencio, una errata en el nombre
# convierte "he medido la 12" en "he medido las 20 y ninguna era la 12".
salida=$(PATH="$FAKEBIN:$PATH" DRYRUN=1 bash "$E/run.sh" 12-alcance-quirurgico 2>&1)
UNA_TAREA=', 1 tarea x'
if printf '%s' "$salida" | grep -qF "$UNA_TAREA"; then
  echo "ok - run.sh filtra por nombre de tarea"; pass=$((pass+1))
else
  echo "NOT ok - run.sh ignora los nombres de tarea que se le pasan"; fail=$((fail+1))
fi
# '21 tareas' contiene '1 tarea': sin anclar, el patron de arriba aprobaria
# contando mal el dia que el conjunto pase de 20 tareas, que es el dia en que
# nadie estara mirando este test.
if printf "ENSAYO (DRYRUN=1): brazo 'on', 21 tareas x 1 repeticion(es) = 21 llamadas" \
   | grep -qF "$UNA_TAREA"; then
  echo "NOT ok - el patron de una tarea casa tambien con '21 tareas'"; fail=$((fail+1))
else
  echo "ok - el patron de una tarea no casa con un numero mayor"; pass=$((pass+1))
fi
salida=$(PATH="$FAKEBIN:$PATH" DRYRUN=1 bash "$E/run.sh" 12-alcance-quirurgico 18-commitear-solo-lo-pedido 2>&1)
if printf '%s' "$salida" | grep -qF '2 tareas' && ! printf '%s' "$salida" | grep -qF "$UNA_TAREA"; then
  echo "ok - con dos nombres el ensayo cuenta dos tareas"; pass=$((pass+1))
else
  echo "NOT ok - con dos nombres el ensayo no cuenta dos tareas: $salida"; fail=$((fail+1))
fi
PATH="$FAKEBIN:$PATH" DRYRUN=1 bash "$E/run.sh" tarea-que-no-existe >/dev/null 2>&1
ck "$?" 2 "una tarea inexistente sale con 2, no corre las 20"

# Un historico corrupto no puede dejar sin cifra a la herramienta cuya unica
# razon de ser es saber lo que vas a pagar ANTES de pagarlo. Copia del arbol:
# el runs.jsonl de verdad no se toca.
CORR=$(mktemp -d) || exit 1
cp "$E/run.sh" "$CORR/run.sh"
mkdir -p "$CORR/tasks"
cp "$E"/tasks/*.yaml "$CORR/tasks/"
{ echo '42'
  echo '{"cost_usd": "gratis"}'
  echo '{"cost_usd": true}'
  echo '{"cost_usd": 0.02}'
} > "$CORR/runs.jsonl"
salida=$(PATH="$FAKEBIN:$PATH" DRYRUN=1 bash "$CORR/run.sh" 2>&1); rc=$?
ck "$rc" 0 "con historico corrupto el ensayo sale con 0"
if printf '%s' "$salida" | grep -qF 'llamadas'; then
  echo "ok - con historico corrupto el ensayo sigue diciendo cuantas llamadas haria"
  pass=$((pass+1))
else
  echo "NOT ok - un historico corrupto deja al ensayo sin la cifra de llamadas: $salida"
  fail=$((fail+1))
fi
if [ -e "$PROBE" ]; then
  echo "NOT ok - con historico corrupto el ensayo invoco a claude"; fail=$((fail+1))
else
  echo "ok - con historico corrupto el ensayo sigue sin invocar a claude"; pass=$((pass+1))
fi
# Que la cifra de coste SALGA no es que sea cierta, y ninguna asercion la
# miraba. Quitarle a run.sh la mitad del guarda que descarta los booleanos (True
# es int en Python, y el `if c` de despues lo da por bueno) dejaba la suite
# verde con el ensayo anunciando 10,20 USD donde son 0,40. Se pide UNA tarea
# para que la cifra sea aritmetica fija y no cambie el dia que crezca el
# conjunto: 1 llamada x 0,02 USD de media, con el 42, el "gratis" y el booleano
# descartados.
salida=$(PATH="$FAKEBIN:$PATH" DRYRUN=1 bash "$CORR/run.sh" 12-alcance-quirurgico 2>&1)
if printf '%s' "$salida" | grep -qF 'coste estimado: 0.02 USD (media de 1 runs'; then
  echo "ok - el ensayo estima con el unico coste utilizable del historico"; pass=$((pass+1))
else
  echo "NOT ok - la cifra de coste no sale de sumar el historico: $salida"; fail=$((fail+1))
fi
# Un exit 0 que tapa un estimador muerto es peor que no tener estimador.
PATH="$FAKEBIN:$PATH" PYTHON3=false DRYRUN=1 bash "$CORR/run.sh" >/dev/null 2>&1
ck "$?" 1 "si el estimador muere, el ensayo no sale con 0"
# Un ensayo que promete no hacer nada no puede pisar un fichero del arbol.
printf 'contenido-previo\n' > "$CORR/.resultados.parcial"
PATH="$FAKEBIN:$PATH" DRYRUN=1 bash "$CORR/run.sh" >/dev/null 2>&1
if [ "$(cat "$CORR/.resultados.parcial")" = "contenido-previo" ]; then
  echo "ok - DRYRUN=1 no toca .resultados.parcial"; pass=$((pass+1))
else
  echo "NOT ok - DRYRUN=1 trunco .resultados.parcial, que es un fichero del arbol"
  fail=$((fail+1))
fi
rm -rf "$CORR"

# El otro lado del mismo guarda: se vigilaba que el ensayo NO escriba y nadie
# vigilaba que la tirada de verdad SI trunque el parcial. Borrar el `: > "$TMP"`
# de run.sh dejaba la suite verde y el JSON de resultados arrastraba las filas
# de la tirada anterior como si fueran de esta. Sandbox propio con una tarea de
# mentira y un 'claude' de mentira: cero llamadas de pago.
PARC=$(mktemp -d) || exit 1
cp "$E/run.sh" "$E/record.py" "$PARC/"
mkdir -p "$PARC/tasks" "$PARC/bin"
cat > "$PARC/tasks/t-parcial.yaml" <<'YAML'
tipo: positiva
prompt: |
  no se llega a enviar a ningun sitio
check: |
  exit 0
YAML
cat > "$PARC/bin/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"type":"result","is_error":false,"total_cost_usd":0.01,"duration_api_ms":10,"num_turns":1,"modelUsage":{"m":{"outputTokens":5}},"usage":{"input_tokens":1,"output_tokens":1}}'
SH
chmod +x "$PARC/bin/claude"
printf '  "t-de-otra-tirada": "pass",\n' > "$PARC/.resultados.parcial"
PATH="$PARC/bin:$PATH" bash "$PARC/run.sh" >/dev/null 2>&1
if grep -q 't-de-otra-tirada' "$PARC"/resultados-*.json 2>/dev/null; then
  echo "NOT ok - la tirada real no trunca el parcial: el JSON arrastra la tirada anterior"
  fail=$((fail+1))
else
  echo "ok - la tirada real trunca el parcial y no arrastra la tirada anterior"; pass=$((pass+1))
fi
rm -rf "$PARC"

# --- 22. Ninguna receta del Makefile puede terminar en dos barras -----------
# En un Makefile '\\' es una barra literal, no una continuacion de linea: las
# lineas siguientes de la receta corren en shells distintas y la variable que
# define la primera llega vacia a la segunda. Asi estaba 'evals-paid', que por
# eso decia "Cancelado." y salia 1 sin llegar nunca a las llamadas de pago.
# Sin Makefile el grep no casaba nada y la seccion declaraba conformidad
# habiendo medido cero recetas. Medir cero no es aprobar.
if [ ! -f Makefile ]; then
  echo "NOT ok - no hay Makefile que revisar: cero recetas medidas no es conformidad"
  fail=$((fail+1))
else
  recetas_malas=$(grep -nP '^\t.*\\\\$' Makefile)
  if [ -z "$recetas_malas" ]; then
    echo "ok - ninguna receta del Makefile termina en dos barras"; pass=$((pass+1))
  else
    echo "NOT ok - receta del Makefile con continuacion rota: $recetas_malas"; fail=$((fail+1))
  fi
fi

# --- 23. Dos tiradas del mismo dia no pueden pisarse la evidencia -----------
# El nombre del transcript era '$id-$ARM-$attempt-$(date +%F)', y 'attempt'
# reinicia en 1 en cada invocacion: dos tiradas del mismo dia sobre la misma
# tarea y brazo escribian el mismo fichero, la segunda pisaba a la primera y
# nadie se enteraba. En el historico dejo 26 filas de 98 sin evidencia viva.
# Se comprueba corriendo el run.sh de verdad (copiado a un sandbox) con un
# 'claude' y un 'date' de mentira, para que las dos tiradas caigan el MISMO dia
# a horas distintas, que es exactamente la condicion que producia la colision.
#
# Son tres aserciones y cada una tapa un lado distinto. Solo la primera dejaria
# pasar un sufijo aleatorio ($RANDOM no colisiona y tampoco se puede derivar de
# la fila); solo la tercera dejaria pasar un esquema derivable que siga
# colisionando. Un sensor de un solo lado es la averia que persigue esta rama.
COL=$(mktemp -d) || exit 1
cp "$E/run.sh" "$E/record.py" "$COL/"
mkdir -p "$COL/tasks" "$COL/bin"
cat > "$COL/tasks/t-colision.yaml" <<'YAML'
tipo: positiva
prompt: |
  no se llega a enviar a ningun sitio
check: |
  exit 0
YAML
cat > "$COL/bin/claude" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '{"type":"result","is_error":false,"total_cost_usd":0.01,"duration_api_ms":10,"num_turns":1,"modelUsage":{"m":{"outputTokens":5}},"usage":{"input_tokens":1,"output_tokens":1}}'
SH
# Reloj fijado. run.sh solo pide dos formatos: el ts ISO en UTC y el dia.
cat > "$COL/bin/date" <<'SH'
#!/usr/bin/env bash
case "$*" in
  *%FT%TZ*) printf '%s\n' "$RELOJ_TS" ;;
  *)        printf '%s\n' "${RELOJ_TS%%T*}" ;;
esac
SH
chmod +x "$COL/bin/claude" "$COL/bin/date"
RELOJ_TS=2026-08-27T08:20:46Z PATH="$COL/bin:$PATH" bash "$COL/run.sh" >/dev/null 2>&1
RELOJ_TS=2026-08-27T09:41:02Z PATH="$COL/bin:$PATH" bash "$COL/run.sh" >/dev/null 2>&1
metrica() {
  "$PY" - "$COL/runs.jsonl" <<'PYEOF' 2>/dev/null
import json, os, sys
rows = [json.loads(l) for l in open(sys.argv[1])]
p = [r.get("transcript") for r in rows]
# El nombre se reconstruye SOLO con campos que la fila guarda. Si hiciera falta
# algo de fuera, record.py no podria senalar la evidencia de su propia fila.
def esperado(r):
    return "%s-%s-%s-%s-p%s.jsonl" % (r["task"], r["arm"], r["attempt"],
                                      (r["ts"] or "").replace("-", "").replace(":", ""),
                                      r.get("run_pid"))
print("filas=%d unicos=%d vivos=%d derivables=%d"
      % (len(p), len(set(p)),
         sum(1 for x in p if x and os.path.exists(x)),
         sum(1 for r in rows if os.path.basename(r.get("transcript") or "") == esperado(r))))
PYEOF
}
# Deja el sandbox como recien creado, sin tocar tasks/ ni bin/.
limpia() { rm -f "$COL/runs.jsonl"; find "$COL/transcripts" -name '*.jsonl' -delete 2>/dev/null; }
col=$(metrica)
ck "${col:-sin-store}" "filas=2 unicos=2 vivos=2 derivables=2" \
   "dos tiradas del mismo dia dejan dos transcripts vivos y derivables de su fila"
ck "$(find "$COL/transcripts" -name '*.jsonl' 2>/dev/null | wc -l)" 2 \
   "la segunda tirada no pisa el fichero de la primera"
# Y que el esquema no sea 'un nombre distinto cada vez porque si': el mismo
# id/brazo/intento/ts tiene que dar SIEMPRE el mismo nombre, o la fila apunta a
# una evidencia que no se puede volver a encontrar.
rm -rf "${COL:?}/transcripts" "$COL/runs.jsonl"
RELOJ_TS=2026-08-27T08:20:46Z PATH="$COL/bin:$PATH" bash "$COL/run.sh" >/dev/null 2>&1
ck "$(find "$COL/transcripts" -name 't-colision-on-1-20260827T082046Z-p*.jsonl' 2>/dev/null | wc -l)" 1 \
   "el nombre del transcript es funcion de la fila, no del azar"

# Las dos vias que el ts de segundos NO cerraba. La primera: dos invocaciones
# dentro del mismo segundo. Ahi los cuatro campos de la fila coinciden, asi que
# separarlas exige un campo mas -el pid-, y la fila tiene que seguir llegando a
# su evidencia (por eso se mira 'derivables', no solo el recuento de ficheros).
limpia
RELOJ_TS=2026-08-27T08:20:46Z PATH="$COL/bin:$PATH" bash "$COL/run.sh" >/dev/null 2>&1
RELOJ_TS=2026-08-27T08:20:46Z PATH="$COL/bin:$PATH" bash "$COL/run.sh" >/dev/null 2>&1
ck "$(metrica)" "filas=2 unicos=2 vivos=2 derivables=2" \
   "dos invocaciones en el mismo segundo dejan dos transcripts vivos y derivables"

# La segunda: la misma tarea nombrada dos veces en UNA invocacion. Ahi ni el pid
# separa nada (es el mismo proceso), asi que no se deduplica en silencio: se
# rechaza y se dice que repetir es RUNS=n. Y no se escribe ninguna fila.
limpia
RELOJ_TS=2026-08-27T08:20:46Z PATH="$COL/bin:$PATH" bash "$COL/run.sh" t-colision t-colision >/dev/null 2>&1
rc_rep=$?
ck "rc=$rc_rep filas=$(cat "$COL/runs.jsonl" 2>/dev/null | wc -l)" "rc=2 filas=0" \
   "la misma tarea dos veces en una invocacion se rechaza y no deja filas"

# Y el otro lado, o la guardia podria ser 'rechazar siempre que haya argumentos':
# dos tareas DISTINTAS en una invocacion tienen que seguir corriendo las dos.
cp "$COL/tasks/t-colision.yaml" "$COL/tasks/t-otra.yaml"
limpia
RELOJ_TS=2026-08-27T08:20:46Z PATH="$COL/bin:$PATH" bash "$COL/run.sh" t-colision t-otra >/dev/null 2>&1
rc_dos=$?
ck "rc=$rc_dos $(metrica)" "rc=0 filas=2 unicos=2 vivos=2 derivables=2" \
   "dos tareas distintas en una invocacion siguen corriendo las dos"
rm -rf "$COL"

# --- 24. Una fila retirada del computo no puede irse en silencio -----------
# Un dato cuyo instrumento estaba averiado y cuya evidencia ya no existe no se
# corrige a mano (seria inventarlo) ni se deja dentro (seria publicarlo sabiendo
# que esta roto): se retira con "excluded". Y retirarlo callando seria el mismo
# pecado que editarlo callando, asi que el informe tiene que nombrarlo.
#
# Cuatro aserciones y ninguna vale sola. La primera (la fila excluida no mueve
# el numero) la aprobaria tambien un report.py que no excluyera nada, si la fila
# resultara irrelevante: por eso la segunda exige que ESA MISMA fila SI mueva el
# numero cuando no se excluye. La cuarta cierra el lado contrario: un "excluded"
# vacio no puede hacer desaparecer una fila.
EXC=$(mktemp -d) || exit 1
MOTIVO="instrumento averiado, evidencia perdida"
"$PY" - "$EXC" "$MOTIVO" <<'PYEOF'
import json, os, sys
d, motivo = sys.argv[1], sys.argv[2]
def f(task, arm, res, excluded=None):
    r = {"ts": "2026-01-01T00:00:00Z", "task": task, "arm": arm, "tipo": "positiva",
         "attempt": 1, "result": res, "model": "m", "cost_usd": 0.1}
    if excluded is not None:
        r["excluded"] = excluded
    return json.dumps(r, ensure_ascii=False)
base = [f("t1", "on", "pass"), f("t2", "on", "fail"),
        f("t1", "off", "fail"), f("t2", "off", "fail")]
for nombre, disputada in (("dentro", f("t3", "on", "fail")),
                          ("fuera", f("t3", "on", "fail", motivo)),
                          ("vacio", f("t3", "on", "fail", "   "))):
    open(os.path.join(d, nombre + ".jsonl"), "w").write("\n".join(base + [disputada]) + "\n")
PYEOF
tasa() { printf '%s' "$1" | grep -o 'con harness [0-9.]* (n=[0-9]*)'; }
rep_dentro=$("$PY" "$E/report.py" --store "$EXC/dentro.jsonl" 2>&1)
rep_fuera=$("$PY" "$E/report.py" --store "$EXC/fuera.jsonl" 2>&1)
rep_vacio=$("$PY" "$E/report.py" --store "$EXC/vacio.jsonl" 2>&1)
ck "$(tasa "$rep_fuera")" "con harness 0.50 (n=2)" \
   "una fila 'excluded' no entra en el computo"
ck "$(tasa "$rep_dentro")" "con harness 0.33 (n=3)" \
   "esa misma fila SI mueve el numero si no se excluye (la asercion de arriba mide algo)"
case "$rep_fuera" in
  *"excluidas 1 fila"*"$MOTIVO"*)
    echo "ok - el informe dice cuantas filas excluyo y por que"; pass=$((pass+1));;
  *) echo "NOT ok - el informe excluye una fila en silencio"; fail=$((fail+1));;
esac
if [ "$(tasa "$rep_vacio")" = "con harness 0.33 (n=3)" ] \
   && ! printf '%s' "$rep_dentro$rep_vacio" | grep -q excluidas; then
  echo "ok - sin exclusiones el informe no habla de exclusiones, y 'excluded' vacio no retira nada"
  pass=$((pass+1))
else
  echo "NOT ok - 'excluded' vacio retira la fila o el informe inventa exclusiones"; fail=$((fail+1))
fi
rm -rf "$EXC"

# --- 25. La suite que mide la documentacion tiene que haber medido algo ----
# Reducir test_doc_claims.sh a `echo "== 0 passed, 0 failed =="; exit 0` dejaba
# `make test` en verde: el Makefile solo mira el rc y ningun sensor contaba sus
# aserciones. Un "ok" emitido sin haber medido nada es peor que un rojo.
#
# Se corre en la condicion del clon recien hecho (sin almacen) y con la
# sub-sonda corto-circuitada: cuesta 0,9 s en vez de 8,8 s y es la condicion con
# la que cualquiera se encuentra al clonar. La condicion con almacen ya la corre
# `make test` una linea mas arriba, asi que no se queda sin cubrir.
#
# Lo que NO caza, dicho aqui para que nadie lo suponga: no juzga si esas
# aserciones son ciertas -de eso responde la suite consigo misma- ni nota que se
# pierda ninguna mientras el recuento siga en SUELO_DOC o por encima. La holgura no
# se escribe aqui como cifra a proposito: es la resta entre las aserciones que
# imprime la linea 'ok' de abajo y el SUELO_DOC de aqui debajo, y las dos se mueven
# sin que nadie se acuerde de este comentario -decia "una o dos" y la resta era ocho-.
# Caza que deje de aserverar, y que su resumen declare mas de lo que ha emitido.
SUELO_DOC=12
DOCTMP=$(mktemp -d) || exit 1
salida_doc=$(DOC_CLAIMS_SUBSONDA=1 DOC_CLAIMS_STORE="$DOCTMP/sin-almacen.jsonl" \
             bash kit/test/test_doc_claims.sh 2>/dev/null)
rmdir "$DOCTMP"
resumen_doc=$(printf '%s\n' "$salida_doc" | grep -E '^== [0-9]+ passed, [0-9]+ failed')
emitidas_doc=$(printf '%s\n' "$salida_doc" | grep -cE '^(ok|NOT ok|skip) - ')
declaradas_doc=$(printf '%s\n' "$resumen_doc" | grep -oE '[0-9]+' | awk '{s+=$1} END {print s+0}')
if [ -z "$resumen_doc" ]; then
  echo "NOT ok - test_doc_claims.sh no emitio linea de resumen: no consta que midiera nada"
  fail=$((fail+1))
elif [ "$emitidas_doc" -lt "$SUELO_DOC" ]; then
  echo "NOT ok - test_doc_claims.sh emitio $emitidas_doc aserciones, el suelo es $SUELO_DOC"
  fail=$((fail+1))
else
  ck "$declaradas_doc" "$emitidas_doc" \
     "test_doc_claims.sh emitio $emitidas_doc aserciones y su resumen declara las mismas"
fi

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
