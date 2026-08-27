#!/usr/bin/env bash
# test_doc_claims.sh — pone rojo el README cuando miente.
#
# El repo defiende que una afirmacion sin sensor se pudre. La documentacion era la
# excepcion: decia "16 suites" con 23 en el Makefile, "8 documentos" con 9, y citaba
# hooks borrados. Nada se ponia rojo porque nadie medía el texto. Esto lo mide.
#
# Cubre solo documentos que hablan en PRESENTE del estado del repo. Quedan fuera a
# proposito CHANGELOG.md, knowledge/DECISIONS/ y docs/superpowers/: son registros
# fechados, y una cifra de 2026-08 ahi es correcta aunque hoy sea otra.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
pass=0; fail=0; skipped=0

# knowledge/PRE-MORTEM.md tampoco entra: es el mismo genero que los ADR, una foto fechada.
DOCS=(README.md CLAUDE.md CONTRIBUTING.md kit/README.md knowledge/ORACLES.md
      knowledge/PROCEDURES.md kit/docs/*.md)

# Cuenta ficheros por glob sin pasar por `ls` (que se rompe con nombres raros).
count() { echo "$#"; }

# Numeros en castellano: los documentos escriben tanto "6 comandos" como "seis comandos",
# y la version en letra es justo la que se quedaba sin actualizar.
word_for() { case "$1" in
  1) echo uno;; 2) echo dos;; 3) echo tres;; 4) echo cuatro;; 5) echo cinco;; 6) echo seis;;
  7) echo siete;; 8) echo ocho;; 9) echo nueve;; 10) echo diez;; 11) echo once;; 12) echo doce;;
  *) echo "";; esac; }   # >12 no aparece escrito en letra en ningun documento

# claim <real> <sustantivo> <fichero...>: toda cifra que preceda a <sustantivo> en esos
# ficheros debe ser <real>. Devuelve 1 si encuentra alguna que no lo sea.
claim() {
  local real="$1" noun="$2"; shift 2
  local bad="" w f hit rest n; w=$(word_for "$real")
  for f in "$@"; do
    # Dos exenciones, ninguna es una cifra del inventario: una linea de presupuesto
    # ("<=6 agentes") y un recuento parcial marcado a mano con doc-claims:ignore.
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      rest=${hit#*:}
      n=$(printf '%s' "$rest" \
          | sed -E "s/.*(^|[^[:alnum:]])([0-9]+\+?|[[:alpha:]]+)[[:space:]]+$noun.*/\2/I" \
          | tr -d '+')
      [ "$n" = "$rest" ] && continue          # la regex no encajo: no hay cifra que juzgar
      case "$n" in
        "$real"|"$w") ;;
        [0-9]*|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce)
          bad="$bad
  $f:$(printf '%s' "$hit" | cut -c1-90)" ;;
        *) ;;   # "las suites", "sus agentes": no es una cifra
      esac
    done <<< "$(grep -nEi "\b([0-9]+\+?|[a-zñáéíóú]+) $noun\b" "$f" 2>/dev/null \
                | grep -v 'doc-claims:ignore' | grep -v '≤' || true)"
  done
  if [ -n "$bad" ]; then
    echo "NOT ok - '$noun': el repo tiene $real y la doc dice otra cosa:$bad"
    fail=$((fail+1))
  else
    echo "ok - '$noun': la doc dice $real y el repo tiene $real"
    pass=$((pass+1))
  fi
}

# --- 1. Cifras que se pueden contar ----------------------------------------
SUITES=$(count kit/test/*.sh)
MK=$(grep -c 'bash kit/test' Makefile)
if [ "$SUITES" -eq "$MK" ]; then
  echo "ok - las $SUITES suites de kit/test/ estan todas en el target 'test'"; pass=$((pass+1))
else
  echo "NOT ok - hay $SUITES ficheros en kit/test/ pero $MK lineas en el Makefile"; fail=$((fail+1))
fi

claim "$SUITES" suites "${DOCS[@]}"
claim "$(count knowledge/DECISIONS/*.md)" ADRs "${DOCS[@]}"
claim "$(count kit/claude/agents/*.md)" agentes "${DOCS[@]}"
claim "$(count .claude/commands/*.md)" comandos "${DOCS[@]}"
claim "$(count kit/docs/*.md)" documentos kit/README.md kit/docs/01-overview.md

# --- 2. Todo script citado en la doc existe --------------------------------
# Asi es como sobrevivio 'session-brief.sh' en tres documentos despues de borrarlo.
# Nombres generico de ejemplo: no son ficheros del repo y no deben existir.
GENERICOS=" script.sh script-que-lo-contiene.sh "
missing=""
while IFS= read -r s; do
  case "$GENERICOS" in *" $s "*) continue;; esac
  find . -name "$s" -not -path './.git/*' | grep -q . || missing="$missing $s"
done <<< "$(grep -rhoE '\b[a-z0-9][a-z0-9_-]*\.sh\b' "${DOCS[@]}" | sort -u)"
if [ -z "$missing" ]; then
  echo "ok - todos los .sh citados en la doc existen en el repo"; pass=$((pass+1))
else
  echo "NOT ok - la doc cita scripts que no existen:$missing"; fail=$((fail+1))
fi

# --- 3. Falsabilidad: el comprobador tiene que saber fallar ----------------
# Sin esto, un `claim` con la regex rota daria verde para siempre.
TMP=$(mktemp); printf 'el kit trae 99 agentes y cuatro comandos\n' > "$TMP"
before=$fail; claim 8 agentes "$TMP" >/dev/null; claim 6 comandos "$TMP" >/dev/null
rm -f "$TMP"
if [ $((fail - before)) -eq 2 ]; then
  fail=$before; pass=$((pass+1))
  echo "ok - falsabilidad: detecta una cifra falsa en digito (99) y en letra (cuatro)"
else
  fail=$before; fail=$((fail+1))
  echo "NOT ok - el comprobador no detecto cifras deliberadamente falsas (tautologia)"
fi

# --- 4. Las cifras de knowledge/EVAL-CRITERIA.md salen del almacen de tiradas ---
# Ese documento no entra en DOCS a proposito. `claim` juzga cifras de inventario
# (suites, ADRs, agentes, comandos) contra lo que hay en el arbol, y NINGUNA de las
# cifras que se pudren ahi es de esa forma: son el n de cada brazo, tasas, un lift y
# el recuento de tareas mudas, que solo existen en kit/evals/runs.jsonl. Medido:
# meterlo en DOCS deja la suite en verde sin mirar una sola de ellas.
EVALDOC=knowledge/EVAL-CRITERIA.md
STORE=kit/evals/runs.jsonl
PY3="${PYTHON3:-python3}"

# cifras_eval <doc> <almacen>: un renglon por discrepancia, nada si todo cuadra.
# Sale 2 sin imprimir cuando no hay almacen. runs.jsonl esta en .gitignore, asi que
# en un clon limpio NO existe, y contestar "ok" sin haber comparado una sola cifra
# seria justo el sensor que aprueba sin medir. Se dice 'skip' y se ve en el resumen.
cifras_eval() {
  local doc="$1" store="$2" rep rc
  [ -f "$store" ] || return 2
  rep=$(mktemp)
  "$PY3" kit/evals/report.py --store "$store" > "$rep" 2>/dev/null
  "$PY3" - "$doc" "$store" "$rep" <<'PYEOF'
import json, re, sys

doc = open(sys.argv[1], encoding="utf-8", errors="replace").read()
filas = [l for l in open(sys.argv[2], errors="replace") if l.strip()]
rep = open(sys.argv[3], encoding="utf-8", errors="replace").read()


def norm(s):
    return " ".join(s.split())


emitidas = set(norm(l) for l in rep.splitlines() if l.strip())
# Solo se juzga la seccion de la tirada vigente. Mas arriba el documento cita a
# proposito la tirada de 6 tareas y la del instrumento roto: son lecturas fechadas
# y corregirlas seria falsificar el registro, no arreglar una cifra podrida.
i = doc.find("## La tirada completa")
tramo = doc[i:] if i >= 0 else doc
p = []

# (a) Llamadas pagadas. Una fila del almacen es una llamada que se pago, entre o no
#     despues en el computo: retirar una fila no devuelve el dinero.
dichas = re.findall(r"(\d+) llamadas reales", tramo)
if not dichas:
    p.append("el doc ya no dice cuantas llamadas reales costo la tirada")
for d in dichas:
    if int(d) != len(filas):
        p.append("el doc dice %s llamadas reales y el almacen tiene %d filas" % (d, len(filas)))

# (b) El n de cada brazo, contado del almacen SIN pasar por report.py: si el
#     documento y el informe se equivocasen igual, esto los pilla a los dos.
n = {}
for l in filas:
    try:
        r = json.loads(l)
    except ValueError:
        continue
    if not isinstance(r, dict) or str(r.get("excluded") or "").strip():
        continue
    n[r.get("arm")] = n.get(r.get("arm"), 0) + 1
m = re.search(r"con harness [0-9.]+ \(n=(\d+)\).*?sin harness [0-9.]+ \(n=(\d+)\)", tramo)
if not m:
    p.append("el doc ya no publica el n de los dos brazos")
else:
    for etiqueta, dicho, brazo in (("con harness", m.group(1), "on"),
                                   ("sin harness", m.group(2), "off")):
        if int(dicho) != n.get(brazo, -1):
            p.append("el doc da n=%s en '%s' y el almacen tiene %d filas de '%s'"
                     % (dicho, etiqueta, n.get(brazo, -1), brazo))

# (c) Cuantas tareas deciden. Es la cifra que mas caro sale de puntualizar y la que
#     mas se pudre: cambia sola en cuanto entra una tirada mas.
m = re.search(r"mudas: (\d+)/(\d+) tareas", rep)
if not m:
    p.append("el informe ya no publica el recuento de tareas mudas")
else:
    mudas, total = int(m.group(1)), int(m.group(2))
    # Solo las frases que hablan del conjunto de HOY. "5 de 6 tareas son mudas" es la
    # lectura fechada de la tirada de 6 y sigue siendo cierta: no se juzga aqui.
    hoy = [x for x in re.finditer(r"(\d+) de (\d+) tareas", tramo) if int(x.group(2)) == total]
    if not hoy:
        p.append("el doc no dice cuantas de las %d tareas del conjunto son mudas" % total)
    for x in hoy:
        if int(x.group(1)) != mudas:
            p.append("el doc dice '%s' y son %d de %d" % (x.group(0), mudas, total))
    deciden = (re.findall(r"[Dd]iscriminan (\d+) tareas de %d" % total, tramo)
               + re.findall(r"decide es de (\d+), no de %d" % total, tramo)
               + re.findall(r"[Dd]eciden (\d+) tareas", tramo))
    if not deciden:
        p.append("el doc no dice cuantas tareas deciden el lift")
    for d in deciden:
        if int(d) != total - mudas:
            p.append("el doc dice que deciden %s tareas y son %d" % (d, total - mudas))

# (d) El bloque publicado tiene que salir TAL CUAL del informe. Esto cubre de una vez
#     tasas, lift, coste, polaridad y ablacion: no hay que enumerarlas. Se comparan
#     los espacios colapsados porque report.py alinea en columnas y el doc no.
b = re.search(r"```\n(.*?)```", tramo, re.S) if i >= 0 else None
if b is None:
    p.append("no se encuentra el bloque de cifras bajo 'La tirada completa'")
else:
    lineas = [norm(x) for x in b.group(1).splitlines() if x.strip()]
    if not lineas:
        p.append("el bloque de cifras publicado esta vacio")
    for x in lineas:
        if x not in emitidas:
            p.append("el informe no emite esta linea publicada: %s" % x)

print("\n".join("  " + x for x in p))
PYEOF
  rc=$?
  rm -f "$rep"
  return $rc
}

problemas=$(cifras_eval "$EVALDOC" "$STORE"); rc=$?
if [ "$rc" -eq 2 ]; then
  echo "skip - $EVALDOC: no hay $STORE (esta en .gitignore); sus cifras NO se han comprobado"
  skipped=$((skipped+1))
elif [ -z "$problemas" ]; then
  echo "ok - las cifras de $EVALDOC cuadran con $STORE"; pass=$((pass+1))
else
  echo "NOT ok - $EVALDOC no cuadra con el almacen:"; echo "$problemas"; fail=$((fail+1))
fi

# Falsabilidad, los dos lados. Sin esto, un regex que dejara de encajar daria verde
# para siempre, que es el modo de fallo que este fichero existe para evitar.
TMPD=$(mktemp -d)
if [ -f "$STORE" ]; then
  # Ninguna cifra verdadera esta escrita aqui: se deforma la que haya.
  sed -E 's/\(n=[0-9]+\)/(n=99999)/g' "$EVALDOC" > "$TMPD/n.md"
  sed -E 's/[0-9]+ llamadas reales/424242 llamadas reales/g' "$EVALDOC" > "$TMPD/ll.md"
  malos=0
  [ -n "$(cifras_eval "$TMPD/n.md" "$STORE")" ] || malos=$((malos+1))
  [ -n "$(cifras_eval "$TMPD/ll.md" "$STORE")" ] || malos=$((malos+1))
  if [ "$malos" -eq 0 ]; then
    echo "ok - falsabilidad: acusa un n y un recuento de llamadas deliberadamente falsos"
    pass=$((pass+1))
  else
    echo "NOT ok - $malos de 2 cifras falsas pasaron el comprobador (tautologia)"
    fail=$((fail+1))
  fi
else
  echo "skip - falsabilidad de las cifras: hace falta $STORE para deformarlo"
  skipped=$((skipped+1))
fi
# Y el otro lado del skip: sin almacen tiene que salir 2, no 0. Un 0 aqui es un 'ok'
# emitido sin datos, que es peor que un rojo porque nadie vuelve a mirarlo.
cifras_eval "$EVALDOC" "$TMPD/no-existe.jsonl" >/dev/null 2>&1
if [ "$?" -eq 2 ]; then
  echo "ok - falsabilidad: sin almacen el comprobador dice skip, no ok"; pass=$((pass+1))
else
  echo "NOT ok - sin almacen el comprobador no se declara skip: aprobaria sin medir"
  fail=$((fail+1))
fi
rm -f "$TMPD"/*.md; rmdir "$TMPD"

if [ "$skipped" -gt 0 ]; then
  echo "== $pass passed, $fail failed, $skipped skipped =="
else
  echo "== $pass passed, $fail failed =="
fi
[ "$fail" -eq 0 ] || exit 1
