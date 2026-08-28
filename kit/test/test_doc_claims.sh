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
  local doc="$1" store="$2" rep alt altstore rc
  [ -f "$store" ] || return 2
  rep=$(mktemp); altstore=$(mktemp); alt=$(mktemp)
  "$PY3" kit/evals/report.py --store "$store" > "$rep" 2>/dev/null
  # La lectura alternativa se comprueba contra su propio informe: el mismo almacen
  # sin la clave 'excluded'. Escribir a mano lo que dice la fila retirada seria
  # publicar una cifra sin sensor, que es la averia que este fichero persigue.
  "$PY3" -c 'import json, sys
for l in open(sys.argv[1], errors="replace"):
    l = l.strip()
    if not l:
        continue
    try:
        r = json.loads(l)
    except ValueError:
        continue
    r.pop("excluded", None)
    print(json.dumps(r, ensure_ascii=False))' "$store" > "$altstore"
  "$PY3" kit/evals/report.py --store "$altstore" > "$alt" 2>/dev/null
  "$PY3" - "$doc" "$store" "$rep" "$alt" <<'PYEOF'
import json, re, sys

doc = open(sys.argv[1], encoding="utf-8", errors="replace").read()
filas = [l for l in open(sys.argv[2], errors="replace") if l.strip()]
rep = open(sys.argv[3], encoding="utf-8", errors="replace").read()


def norm(s):
    return " ".join(s.split())


# Las salvedades del informe NO se enumeran. report.py sabe emitir AVISO, SATURADO,
# NO COMPARABLE, NO MEDIBLE y SIN DATOS, y cada una anula o acota una cifra de las de
# arriba: publicar el coste y callarse el AVISO que dice que ese coste no es
# comparable es publicar media verdad. Habia una lista cerrada de lineas concretas y
# dejaba fuera a toda esta familia; ampliarla a mano cada vez que el informe aprenda a
# avisar de algo nuevo es la misma averia con retraso.
SALVEDAD = re.compile(r"\b(AVISO|SATURADO|NO COMPARABLE|NO MEDIBLE|SIN DATOS)\b")

# Y el veredicto, que se publica siempre: exclusion, tasas+n, coste, las dos
# polaridades, la saturacion y la ablacion. La saturacion son TRES lineas: el
# recuento, la que dice que las mudas no pueden mover el lift y la del conjunto que
# decide; citar la primera y la tercera saltandose la de en medio deja la frase sin
# sujeto, y asi se publico. Fuera queda la lista de nombres de las mudas, que es el
# dato y no la afirmacion, y las cabeceras, las tablas por tarea y la carga de CPU,
# que el doc no copia.
VEREDICTO = (r"excluidas \d+ fila\(s\)",
             r"con harness [0-9.]+ \(n=\d+\)",
             r"coste: ",
             r"(positiva|negativa) \(",
             r"mudas: \d+/\d+ tareas",
             r"sus repeticiones\.",
             r"es de \d+ tarea\(s\)",
             r"sin-[a-z-]+ \(.*\) [0-9.]+ \[")


def exigidas(texto):
    """Las lineas del informe que el bloque publicado tiene que llevar.

    Una salvedad arrastra el resto de su parrafo: la consecuencia vive en sus lineas
    de continuacion ("...el coste de arriba no son comparables"), y sin ellas la
    salvedad se publica descabezada. Se corta por el parrafo y no por una lista de
    continuaciones conocidas, y en la duda se exige de mas: pasarse obliga a publicar
    una linea vecina que report.py tambien emitio; quedarse corto deja callar la
    salvedad, que es el fallo que esto viene a cerrar.
    """
    lineas = texto.splitlines()
    req, i = [], 0
    while i < len(lineas):
        if lineas[i].strip() and SALVEDAD.search(lineas[i]):
            while i < len(lineas) and lineas[i].strip():
                req.append(lineas[i])
                i += 1
        i += 1
    req += [l for l in lineas if l.strip() and any(re.match(p, norm(l)) for p in VEREDICTO)]
    return set(norm(x) for x in req)


emitidas = set(norm(l) for l in rep.splitlines() if l.strip())
# Solo se juzga la seccion de la tirada vigente. Mas arriba el documento cita a
# proposito la tirada de 6 tareas y la del instrumento roto: son lecturas fechadas
# y corregirlas seria falsificar el registro, no arreglar una cifra podrida.
i = doc.find("## La tirada completa")
tramo = doc[i:] if i >= 0 else doc
p = []

# La lectura alternativa publica las cifras del almacen CON la fila retirada
# contada. Sale del tramo vigente antes de juzgarlo: si no, su n=28 y su 16/20 se
# leerian como una contradiccion de lo publicado, cuando son justo la otra
# columna. Se juzga abajo, en (e), contra su propio informe.
ALT = "### La lectura alternativa"
a_i = tramo.find(ALT)
alt_tramo = ""
if a_i < 0:
    p.append("el doc ya no publica la lectura alternativa (la fila retirada contada)")
else:
    a_fin = tramo.find("\n### ", a_i + 4)
    if a_fin < 0:
        a_fin = len(tramo)
    alt_tramo = tramo[a_i:a_fin]
    tramo = tramo[:a_i] + tramo[a_fin:]

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
    # Y al reves, que es el lado que faltaba: exigir solo "lo publicado sale del
    # informe" deja al documento borrar en silencio la linea que no le gusta y la
    # suite sigue verde.
    publicadas = set(lineas)
    for x in sorted(exigidas(rep)):
        if x not in publicadas:
            p.append("el informe emite esta linea y el bloque no la publica: %s" % x)

# (e) Y el bloque alternativo contra SU informe, en los dos sentidos tambien. Lleva
#     ademas la saturacion, que es el quinto numero que mueve la fila retirada.
if alt_tramo:
    alt_rep = open(sys.argv[4], encoding="utf-8", errors="replace").read()
    alt_emitidas = set(norm(l) for l in alt_rep.splitlines() if l.strip())
    ab = re.search(r"```\n(.*?)```", alt_tramo, re.S)
    if ab is None:
        p.append("la lectura alternativa ya no publica su bloque de cifras")
    else:
        alt_lineas = [norm(x) for x in ab.group(1).splitlines() if x.strip()]
        if not alt_lineas:
            p.append("el bloque de la lectura alternativa esta vacio")
        for x in alt_lineas:
            if x not in alt_emitidas:
                p.append("el informe con la fila contada no emite esta linea de la"
                         " lectura alternativa: %s" % x)
        for x in sorted(exigidas(alt_rep)):
            if x not in set(alt_lineas):
                p.append("la lectura alternativa no publica esta linea de su informe: %s" % x)

print("\n".join("  " + x for x in p))
PYEOF
  rc=$?
  rm -f "$rep" "$alt" "$altstore"
  return $rc
}

# veredicto <rc> <quejas> <sujeto-ok> <sujeto-mal>: dictamina el resultado de un
# comprobador. Devuelve 0 solo si aprobo de verdad, e imprime la linea del informe.
#
# Existe por el tercer caso, que es el que se colaba: un comprobador que revienta
# escribe su traceback en stderr y deja el stdout VACIO, o sea exactamente lo mismo
# que uno que no tiene nada que objetar. Mirando solo la salida, "no hay quejas" y
# "no llegue a mirar" son el mismo verde, y asi se publicaba 'ok' sin haber medido
# nada -que es peor que un rojo porque nadie vuelve a mirarlo-. El rc los separa.
#
# Es funcion y no codigo pegado en cada sitio para que la sonda de falsabilidad de
# mas abajo pueda interrogar ESTA decision y no una copia suya: un veredicto que la
# sonda reimplementa es una comprobacion hecha a mano, y se pudre igual.
veredicto() {
  local rc="$1" quejas="$2" sujeto_ok="$3" sujeto_mal="$4"
  if [ "$rc" -ne 0 ]; then
    echo "NOT ok - $sujeto_mal: el comprobador revento (rc=$rc), su traceback esta en stderr"
    return 1
  fi
  if [ -n "$quejas" ]; then
    echo "NOT ok - $sujeto_mal:"; echo "$quejas"
    return 1
  fi
  echo "ok - $sujeto_ok"
}

problemas=$(cifras_eval "$EVALDOC" "$STORE"); rc=$?
if [ "$rc" -eq 2 ]; then
  echo "skip - $EVALDOC: no hay $STORE (esta en .gitignore); sus cifras NO se han comprobado"
  skipped=$((skipped+1))
elif veredicto "$rc" "$problemas" "las cifras de $EVALDOC cuadran con $STORE" \
                                  "$EVALDOC no cuadra con el almacen"; then
  pass=$((pass+1))
else
  fail=$((fail+1))
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
# El recuento de mutantes que publica el doc, contra los que hay en mutantes.py.
# Esta cifra ya se pudrio dos veces -el docstring decia "solo M9-M12" con 25 dentro,
# y la tabla se quedo en "33/33" con 30 versionados a doce lineas de su guardia- y
# cada arreglo de esta rama anade mutantes, asi que se pudre sola si nadie la mide.
recuento_mutantes() {
"$PY3" - "$1" kit/evals/mutantes.py <<'PYEOF'
import re, sys

doc = open(sys.argv[1], encoding="utf-8", errors="replace").read()
src = open(sys.argv[2], encoding="utf-8", errors="replace").read()
ids = [int(x) for x in re.findall(r'^    \("M(\d+)', src, re.M)]
p = []
if not ids:
    p.append("no se reconoce ningun mutante en mutantes.py")
else:
    # Toda cifra pegada a la palabra 'mutantes' es un recuento, este escrita como
    # este: "33/33 mutantes" y "30 de los 38 mutantes" son la misma afirmacion en
    # dos redacciones. Vigilar una sola es el sensor de un lado de siempre, y por
    # eso la otra se pudrio. Aqui se juzgan TODAS, y solo valen dos numeros: los
    # versionados (los que este fichero puede reproducir) y el total historico.
    versionados, total = len(ids), max(ids)
    valores = []
    for x in re.finditer(r"(?<![\w/-])(\d+(?:\s*/\s*\d+)?(?:\s+de\s+los\s+\d+)?)"
                         r"\s+mutantes\b", doc):
        valores += [int(v) for v in re.findall(r"\d+", x.group(1))]
    malos = sorted(set(v for v in valores if v not in (versionados, total)))
    if not valores:
        p.append("el doc ya no dice cuantos mutantes hay")
    for v in malos:
        p.append("el doc publica '%d mutantes' y los unicos recuentos ciertos son"
                 " %d versionados de %d historicos" % (v, versionados, total))
    if valores and not malos and set(valores) != set((versionados, total)):
        p.append("el doc solo publica %s: le falta decir %d versionados de %d historicos"
                 % (sorted(set(valores)), versionados, total))
    # El rango tiene que estar escrito en alguna parte, o el "los N versionados" no
    # dice CUALES y deja de ser comprobable contra el fuente.
    rangos = [(int(a), int(b)) for a, b in re.findall(r"M(\d+)\s*[-\u2013\u2014]\s*M(\d+)", doc)]
    if (min(ids), max(ids)) not in rangos:
        p.append("el doc no publica el rango de los mutantes versionados, M%d-M%d"
                 % (min(ids), max(ids)))
print("\n".join("  " + x for x in p))
PYEOF
}

problemas=$(recuento_mutantes "$EVALDOC"); rc=$?
if veredicto "$rc" "$problemas" \
     "el recuento de mutantes de $EVALDOC cuadra con kit/evals/mutantes.py" \
     "$EVALDOC miente sobre los mutantes"; then
  pass=$((pass+1))
else
  fail=$((fail+1))
fi

# Y que sepa suspender, en las dos redacciones y en el rango: sin esto solo consta
# que hoy absuelve, que es exactamente lo que este fichero no acepta de nadie.
sed -E 's#([0-9]+)/([0-9]+) mutantes#\1/424242 mutantes#' "$EVALDOC" > "$TMPD/m1.md"
sed -E 's#([0-9]+) de los ([0-9]+) mutantes#424242 de los \2 mutantes#' "$EVALDOC" > "$TMPD/m2.md"
sed -E 's#M9.M38#M9-M999#g' "$EVALDOC" > "$TMPD/m3.md"
malos=0
for d in m1 m2 m3; do
  [ -n "$(recuento_mutantes "$TMPD/$d.md")" ] || malos=$((malos+1))
done
if [ "$malos" -eq 0 ]; then
  echo "ok - falsabilidad: acusa el recuento falso en las dos redacciones y el rango falso"
  pass=$((pass+1))
else
  echo "NOT ok - $malos de 3 recuentos de mutantes falsos pasaron el comprobador"
  fail=$((fail+1))
fi

# Las cuatro lineas incomodas, una a una: borrar cualquiera del bloque tiene que
# poner esto rojo. Sin este bucle, el comprobador de arriba solo sabe suspender al
# que publica de mas, nunca al que publica de menos.
if [ -f "$STORE" ]; then
  # Borra la primera linea que case DESPUES de la cabecera de la tirada vigente: las
  # mismas etiquetas aparecen antes en el doc, en tiradas fechadas que no se juzgan.
  sin_linea() {
    awk -v pat="$1" -v desde="${2:-^## La tirada completa}" 'BEGIN{on=0;ya=0}
      $0 ~ desde {on=1}
      {if (on && !ya && $0 ~ pat) {ya=1; next} print}' "$EVALDOC"
  }
  # Las salvedades entran en el bucle con el mismo derecho que las cifras: son las
  # lineas que las anulan, y son las que se estaban callando.
  LINEAS=('^excluidas ' '^con harness ' '^coste: ' '^positiva ' '^negativa '
          '^mudas: ' '^ *sus repeticiones' '^ *es de [0-9]' '^SATURADO: '
          '^arriba seguira ' '^retirar las mudas ' '^sin-ajustes ' '^sin-skills '
          '^sin-mcp ')
  mudas=""; n_borradas=0
  for pat in "${LINEAS[@]}"; do
    sin_linea "$pat" > "$TMPD/borrada.md"
    n_borradas=$((n_borradas+1))
    if [ -z "$(cifras_eval "$TMPD/borrada.md" "$STORE")" ]; then
      mudas="$mudas $pat"
    fi
  done
  # Y las de la lectura alternativa, que es la columna incomoda entera: si se
  # pudiera borrar en silencio, publicarla no costaria nada ni garantizaria nada.
  # (Sin '^excluidas ': su informe no la emite, porque ahi la fila esta contada.)
  for pat in "${LINEAS[@]:1}"; do
    sin_linea "$pat" '^### La lectura alternativa' > "$TMPD/borrada.md"
    n_borradas=$((n_borradas+1))
    if [ -z "$(cifras_eval "$TMPD/borrada.md" "$STORE")" ]; then
      mudas="$mudas alt:$pat"
    fi
  done
  if [ -z "$mudas" ]; then
    echo "ok - falsabilidad: borrar cualquiera de las $n_borradas lineas de los dos bloques pone rojo"
    pass=$((pass+1))
  else
    echo "NOT ok - el doc puede borrar estas lineas del bloque sin que nadie se entere:$mudas"
    fail=$((fail+1))
  fi

  # Y el lado que ningun borrado prueba: una salvedad que hoy NO se emite. Se infla
  # la carga de una maquina en una copia del almacen -no se toca runs.jsonl- hasta
  # que report.py dice que el coste de los dos brazos no es comparable. El doc, que
  # no puede saberlo, tiene que quedarse rojo; y publicandola, verde. Sin esto solo
  # constaria que las salvedades de HOY estan citadas, que es la lista cerrada de
  # siempre disfrazada de sensor.
  "$PY3" - "$STORE" "$TMPD/aviso.jsonl" <<'PYAVISO'
import json, sys
salida = open(sys.argv[2], "w")
for l in open(sys.argv[1], errors="replace"):
    l = l.strip()
    if not l:
        continue
    try:
        r = json.loads(l)
    except ValueError:
        continue
    if isinstance(r, dict) and r.get("arm") == "on" and r.get("load1") is not None:
        r["load1"] = 999.0
    salida.write(json.dumps(r, ensure_ascii=False) + "\n")
PYAVISO
  avisos=$("$PY3" kit/evals/report.py --store "$TMPD/aviso.jsonl" 2>/dev/null \
           | /usr/bin/grep -c '^  AVISO:')
  quejas=$(cifras_eval "$EVALDOC" "$TMPD/aviso.jsonl" | /usr/bin/grep -c 'AVISO:')
  # Y la reciproca, con la salvedad puesta en los dos bloques a mano.
  "$PY3" - "$EVALDOC" "$TMPD/con-aviso.md" <<'PYDOC'
import io, sys
AVISO = ("AVISO: los dos brazos corrieron con la maquina distinta de ocupada.\n"
         "La nota aguanta (el grader es determinista), pero la latencia y el\n"
         "coste de arriba no son comparables. Repetir con la maquina en reposo.\n")
doc = io.open(sys.argv[1], encoding="utf-8").read()
io.open(sys.argv[2], "w", encoding="utf-8").write(
    "".join(l + AVISO if l.startswith("coste: ") and l.endswith("por run)\n") else l
            for l in doc.splitlines(True)))
PYDOC
  restantes=$(cifras_eval "$TMPD/con-aviso.md" "$TMPD/aviso.jsonl" | /usr/bin/grep -c 'AVISO:')
  if [ "$avisos" -ge 1 ] && [ "$quejas" -ge 1 ] && [ "$restantes" -eq 0 ]; then
    echo "ok - falsabilidad: una salvedad que report.py aprende a emitir hoy es obligatoria manana"
    pass=$((pass+1))
  else
    echo "NOT ok - la salvedad no se exige sola: report.py emite $avisos AVISO,"
    echo "         el doc que la calla da $quejas queja(s) y el que la publica $restantes"
    fail=$((fail+1))
  fi
else
  echo "skip - falsabilidad del bloque: hace falta $STORE"
  skipped=$((skipped+1))
fi

# Y el lado que ninguna cifra falsa prueba: que un comprobador que REVIENTA salga
# rojo. Las sondas de arriba deforman el documento, asi que solo demuestran que el
# comprobador sabe suspender cuando funciona; el modo que se colaba es el otro, el
# de no llegar a mirar. Un fallo incondicional tampoco lo prueba: como las demas
# sondas trabajan sobre copias en $TMPD, un `raise` para todos las pone rojas a
# ellas y se ve. El fallo que dejaba la suite entera en verde es el que solo
# alcanza la entrada REAL, y ese es el que se inyecta aqui: un interprete de usar y
# tirar que muere si y solo si le pasan el documento de verdad. No toca el fichero
# versionado, ni el arbol, ni la variable PY3 de fuera -vive en el subshell de la
# sustitucion-, y se exige ver el codigo inyectado en la queja para que la sonda no
# pueda aprobar con un rojo que venga de otra cosa (un 2 por almacen ausente, por
# ejemplo, que seria justo aprobar sin haber medido).
# shellcheck disable=SC2016 # "$@" literal a proposito: es el cuerpo del envoltorio,
# tiene que expandirlo /bin/sh cuando lo ejecute, no este script al escribirlo.
printf '#!/bin/sh\nfor a in "$@"; do\n  [ "$a" = "%s" ] && exit 97\ndone\nexec %s "$@"\n' \
  "$EVALDOC" "$PY3" > "$TMPD/py-revienta"
chmod +x "$TMPD/py-revienta"
sondados=""; ciegos=""
for f in cifras_eval recuento_mutantes; do
  # cifras_eval sale 2 sin llegar a llamar al interprete cuando no hay almacen: ahi
  # la inyeccion no entra y la sonda no mediria lo que dice medir. Se declara.
  if [ "$f" = cifras_eval ] && [ ! -f "$STORE" ]; then
    continue
  fi
  salida=$(PY3="$TMPD/py-revienta"; "$f" "$EVALDOC" "$STORE" 2>/dev/null); rc=$?
  linea=$(veredicto "$rc" "$salida" "NO DEBERIA aprobar: el comprobador nunca miro" "sonda de $f")
  sondados="$sondados $f"
  case "$linea" in
    "NOT ok"*"rc=97"*) ;;
    *) ciegos="$ciegos $f" ;;
  esac
done
if [ -n "$ciegos" ] || [ -z "$sondados" ]; then
  echo "NOT ok - revientan con la entrada real y aun asi se leen como 'ok':${ciegos:- ninguno se llego a sondar}"
  fail=$((fail+1))
else
  echo "ok - falsabilidad: reventar solo con la entrada real sale rojo, no 'ok' ($sondados )"
  pass=$((pass+1))
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
rm -f "$TMPD"/*.md "$TMPD"/*.jsonl "$TMPD"/py-revienta; rmdir "$TMPD"

if [ "$skipped" -gt 0 ]; then
  echo "== $pass passed, $fail failed, $skipped skipped =="
else
  echo "== $pass passed, $fail failed =="
fi
[ "$fail" -eq 0 ] || exit 1
