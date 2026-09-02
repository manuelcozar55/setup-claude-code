#!/usr/bin/env bash
# test_doc_claims.sh — pone rojo el README cuando miente.
#
# El repo defiende que una afirmacion sin sensor se pudre. La documentacion era la
# excepcion: decia "16 suites" con 23 en el Makefile, "8 documentos" con 9, y citaba
# hooks borrados. Nada se ponia rojo porque nadie medía el texto. Esto lo mide.
#
# Cubre solo documentos que hablan en PRESENTE del estado del repo. Quedan fuera a
# proposito knowledge/DECISIONS/ y docs/superpowers/: son registros fechados, y una
# cifra de 2026-08 ahi es correcta aunque hoy sea otra. De CHANGELOG.md entra solo la
# seccion [Unreleased], que describe el arbol de HOY; sus secciones publicadas quedan
# fuera por lo mismo que los ADR, y el porque esta abajo, junto al recorte.
set -uo pipefail
# Ruta absoluta de este fichero ANTES del cd: la sonda de los puntos de llamada, mas
# abajo, vuelve a correr la suite ENTERA contra si misma, y tras el cd un $0 relativo
# ya no la nombra.
SELF=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
cd "$(dirname "$0")/../.." || exit 1
pass=0; fail=0; skipped=0

# knowledge/PRE-MORTEM.md tampoco entra: es el mismo genero que los ADR, una foto fechada.
DOCS=(README.md CLAUDE.md CONTRIBUTING.md kit/README.md kit/evals/README.md
      knowledge/ORACLES.md knowledge/PROCEDURES.md kit/docs/*.md)
# Fuera de DOCS a proposito (el porque, en la seccion 4), pero sus filas nombran el
# sensor de cada afirmacion, y esos nombres si son comprobables: citar un script que
# no existe deja la fila sin sensor sin que se note.
EVALDOC=knowledge/EVAL-CRITERIA.md

# Cuenta ficheros por glob sin pasar por `ls` (que se rompe con nombres raros).
count() { echo "$#"; }

# Numeros en castellano: los documentos escriben tanto "6 comandos" como "seis comandos",
# y la version en letra es justo la que se quedaba sin actualizar.
word_for() { case "$1" in
  1) echo uno;; 2) echo dos;; 3) echo tres;; 4) echo cuatro;; 5) echo cinco;; 6) echo seis;;
  7) echo siete;; 8) echo ocho;; 9) echo nueve;; 10) echo diez;; 11) echo once;; 12) echo doce;;
  *) echo "";; esac; }   # >12 no aparece escrito en letra en ningun documento

# claim <real> <sustantivo> <fichero...>: toda cifra que preceda a <sustantivo> en esos
# ficheros debe ser <real>. Devuelve 1 si encuentra alguna que no lo sea, y tambien si no
# encuentra NINGUNA: un claim que no juzga una sola cifra aprueba pase lo que pase.
CLAIM_SIN_CIFRA=
# claim_flojo: lo mismo, pero sin exigir haber juzgado nada. Solo para las afirmaciones
# que hoy no aparecen escritas con cifra en ningun documento; el motivo, en su llamada.
claim_flojo() { CLAIM_SIN_CIFRA=1; claim "$@"; CLAIM_SIN_CIFRA=; }
claim() {
  local real="$1" noun="$2"; shift 2
  local bad="" w f hit rest n vistas=0; w=$(word_for "$real")
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
        "$real"|"$w") vistas=$((vistas+1)) ;;
        [0-9]*|uno|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|once|doce)
          vistas=$((vistas+1))
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
  elif [ "$vistas" -eq 0 ] && [ -z "$CLAIM_SIN_CIFRA" ]; then
    # Sin esto un `claim` cuya frase se reescribe deja de encajar y sigue diciendo
    # 'ok' habiendo juzgado cero cifras: el sensor de un solo lado, que sabe
    # suspender y no sabe medir. Rojo ruidoso en vez de verde mudo.
    echo "NOT ok - '$noun': no hay ninguna cifra que juzgar en $*: mide cero y aprobaria siempre"
    fail=$((fail+1))
  elif [ "$vistas" -eq 0 ]; then
    echo "ok - '$noun': ningun documento escribe una cifra delante; no hay nada que juzgar"
    pass=$((pass+1))
  else
    echo "ok - '$noun': la doc dice $real y el repo tiene $real ($vistas cifra(s) juzgada(s))"
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
# Estas dos van flojas por un defecto PREEXISTENTE, no por comodidad: medido con el
# guardia puesto, ninguna juzga una sola cifra hoy. Ningun documento de DOCS escribe un
# numero delante de "ADR(s)", y delante de "comandos" solo hay palabras ("los comandos",
# "ejecutar comandos"), nunca una cifra. Siguen puestas porque el dia que alguien
# publique "9 ADRs" o "5 comandos" las cazan; exigirles medir hoy pediria escribir esas
# cifras en README.md y CLAUDE.md, que es otro encargo. Queda declarado, no tapado.
claim_flojo "$(count knowledge/DECISIONS/*.md)" ADRs "${DOCS[@]}"
claim "$(count kit/claude/agents/*.md)" agentes "${DOCS[@]}"
claim_flojo "$(count .claude/commands/*.md)" comandos "${DOCS[@]}"
claim "$(count kit/docs/*.md)" documentos kit/README.md kit/docs/01-overview.md
# El inventario del eval era la unica cifra que nadie juzgaba: "40 tareas reales
# (30 positivas / 10 negativas)" pasaba verde. Va acotado a los dos indices porque
# "tareas" a secas tambien nombra recuentos parciales ciertos -las 9 que puntuan el
# transcript, las 6 de la primera tirada- y ahi la cifra correcta no es el total.
claim "$(count kit/evals/tasks/*.yaml)" tareas README.md kit/README.md
claim "$(grep -l '^tipo: positiva' kit/evals/tasks/*.yaml | wc -l)" positivas README.md kit/README.md
claim "$(grep -l '^tipo: negativa' kit/evals/tasks/*.yaml | wc -l)" negativas README.md kit/README.md
# El mismo inventario en el indice del propio eval, anclado a la FRASE de la cabecera
# ("**N tareas** en `tasks/*.yaml`") y no a la palabra suelta. Ese fichero lleva cuatro
# recuentos parciales ciertos -9, 5/6, seis y 20-30- que un `claim` sobre "tareas"
# enrojeceria, y uno de ellos vive dentro del bloque que copia la salida literal de
# report.py: exentarlo con doc-claims:ignore falsificaria la cita. Anclar solo mide la
# cabecera; que la cabecera siga existiendo lo exige el guardia de 'vistas' de arriba.
claim "$(count kit/evals/tasks/*.yaml)" 'tareas\*\* en' kit/evals/README.md

# La seccion [Unreleased] de CHANGELOG.md, y solo ella.
#
# El fichero entero NO puede entrar en DOCS, y no por comodidad: un changelog es un
# registro y sus secciones publicadas DEBEN conservar los numeros que eran ciertos al
# publicarlas. Meterlo completo bajo claim() enrojeceria afirmaciones verdaderas -el
# sensor de un solo lado por el otro lado, que es un defecto peor que el que esto
# cierra-. Las secciones historicas quedan fuera POR DISENO, igual que los ADR.
#
# Pero [Unreleased] no es historia: describe el arbol de HOY, asi que sus cifras si son
# verificables contra el arbol de hoy, y sin sensor se pudren solas. Medido: la frase
# "de 16 a 24" suites la escribio esta misma rama siendo CIERTA -bc8d64e tenia 24
# ficheros en kit/test/- y la propia rama anadio la 25 sin que nada se pusiera rojo.
#
# La seccion se recorta a un fichero aparte y las lineas de fuera se VACIAN en vez de
# borrarse: asi el numero de linea que sale en la queja es el de CHANGELOG.md. El corte
# es la primera cabecera '## [<digito>', que es la del ultimo release.
UNRELD=$(mktemp -d) || exit 1
UNREL="$UNRELD/CHANGELOG.md-Unreleased"
awk '/^## \[Unreleased\]/ {on=1} /^## \[[0-9]/ {on=0} {print (on ? $0 : "")}' \
    CHANGELOG.md > "$UNREL"
# Recien etiquetada una version, [Unreleased] se queda VACIA a proposito: es el paso 4
# del procedimiento de release (CONTRIBUTING.md). Exigirle cifras entonces seria
# enrojecer un fichero correcto, asi que se declara 'skip' y se ve en el resumen. Lo
# que NO se hace es aflojar los claim de abajo a claim_flojo: mientras la seccion tenga
# contenido, un claim que no juzgue ninguna cifra es un 'ok' que no mide.
# El awk imprime tambien la linea de la cabecera, y de ahi sale la unica forma de
# distinguir "la seccion esta vacia" de "el recorte se ha roto": si la cabecera NO
# aparece en el recorte, el ancla ha dejado de casar y no hay nada que medir. Sin esta
# distincion el fallo es mudo -medido: con el ancla escrita /^## \[UnReleased\]/ la
# suite daba "22 passed, 0 failed, 1 skipped" y rc=0, seis cifras dejadas de mirar-.
# No se cuenta la seccion por segunda vez a mano: eso serian dos implementaciones y la
# segunda se pudriria igual.
if [ "$(grep -c '^## \[Unreleased\]' "$UNREL")" -ne 1 ]; then
  echo "NOT ok - el recorte de [Unreleased] no trae su cabecera: el ancla del awk ya no"
  echo "         casa con CHANGELOG.md, y sin ella el skip aprobaria sin medir nada"
  fail=$((fail+1))
elif [ "$(grep -c . "$UNREL")" -eq 1 ]; then
  echo "skip - CHANGELOG.md [Unreleased]: seccion vacia (version recien etiquetada);"
  echo "       sus cifras NO se han comprobado"
  skipped=$((skipped+1))
else
  claim "$SUITES" suites "$UNREL"
  claim "$(count knowledge/DECISIONS/*.md)" ADRs "$UNREL"
  # El inventario del eval, que es lo que esta rama anade y lo que [Unreleased] anuncia.
  # Aqui si van estrictos -no como sobre DOCS-: las entradas nuevas escriben las cuatro
  # cifras, asi que hay algo que juzgar. Ojo al redactarlas: el sed de claim es GOLOSO y
  # solo juzga la ULTIMA aparicion de "<n> <sustantivo>" de cada linea, asi que un
  # recuento parcial cierto ("decide 3 tareas") enrojece si queda el ultimo de su linea.
  claim "$(count kit/evals/tasks/*.yaml)" tareas "$UNREL"
  claim "$(grep -l '^tipo: positiva' kit/evals/tasks/*.yaml | wc -l)" positivas "$UNREL"
  claim "$(grep -l '^tipo: negativa' kit/evals/tasks/*.yaml | wc -l)" negativas "$UNREL"
  claim "$(grep -cE '^    \("M[0-9]+' kit/evals/mutantes.py)" mutantes "$UNREL"
fi
rm -f "$UNREL"; rmdir "$UNRELD"

# --- 2. Todo script citado en la doc existe --------------------------------
# Asi es como sobrevivio 'session-brief.sh' en tres documentos despues de borrarlo.
# Nombres generico de ejemplo: no son ficheros del repo y no deben existir.
GENERICOS=" script.sh script-que-lo-contiene.sh "
missing=""
while IFS= read -r s; do
  case "$GENERICOS" in *" $s "*) continue;; esac
  find . -name "$s" -not -path './.git/*' | grep -q . || missing="$missing $s"
done <<< "$(grep -rhoE '\b[a-z0-9][a-z0-9_-]*\.sh\b' "${DOCS[@]}" "$EVALDOC" | sort -u)"
if [ -z "$missing" ]; then
  echo "ok - todos los .sh citados en la doc existen en el repo"; pass=$((pass+1))
else
  echo "NOT ok - la doc cita scripts que no existen:$missing"; fail=$((fail+1))
fi

# Las filas de EVAL-CRITERIA.md nombran el sensor por numero de seccion
# ("test_evals.sh §21"). Cambiar §21 por §99 dejaba la fila apuntando a un sensor
# inexistente sin una queja. Se juzga contra la UNION de las dos suites que el doc
# cita, no contra una en concreto: la frase no siempre nombra el fichero, y atar
# cada § a su script pediria adivinar a que se refiere el texto.
secciones=$(grep -hoE '^# --- [0-9]+\.' kit/test/test_evals.sh kit/test/test_doc_claims.sh \
            | grep -oE '[0-9]+' | sort -un)
citadas=$(grep -oE '§[0-9]+' "$EVALDOC" | tr -d '§' | sort -un)
fantasma=""
while IFS= read -r n; do
  [ -n "$n" ] || continue
  printf '%s\n' "$secciones" | grep -qx "$n" || fantasma="$fantasma §$n"
done <<< "$citadas"
if [ -z "$fantasma" ]; then
  echo "ok - las $(printf '%s\n' "$citadas" | wc -l) secciones que cita $EVALDOC existen"
  pass=$((pass+1))
else
  echo "NOT ok - $EVALDOC cita secciones que no existen:$fantasma"; fail=$((fail+1))
fi

# El suelo de cobertura se publica en el doc ("suelo de cobertura 10/20") y vive en
# el fuente como `-ge 10`. Nada ataba una cifra a la otra ni al tamano del conjunto:
# el doc podia publicar 99/20 y quedarse verde.
suelo_src=$(grep -oE 'con_sol" -ge [0-9]+' kit/test/test_evals.sh | grep -oE '[0-9]+$')
suelo_doc=$(grep -oE 'suelo de cobertura [0-9]+/[0-9]+' "$EVALDOC" | grep -oE '[0-9]+/[0-9]+')
suelo_real="$suelo_src/$(count kit/evals/tasks/*.yaml)"
if [ -z "$suelo_src" ] || [ -z "$suelo_doc" ]; then
  echo "NOT ok - no se encuentra el suelo de cobertura en el fuente o en el doc: nada que comparar"
  fail=$((fail+1))
elif [ "$suelo_doc" = "$suelo_real" ]; then
  echo "ok - el suelo de cobertura publicado ($suelo_doc) es el del fuente"; pass=$((pass+1))
else
  echo "NOT ok - el doc publica suelo de cobertura $suelo_doc y el fuente exige $suelo_real"
  fail=$((fail+1))
fi

# --- 3. Falsabilidad: el comprobador tiene que saber fallar ----------------
# Sin esto, un `claim` con la regex rota daria verde para siempre.
TMP=$(mktemp); printf 'el kit trae 99 agentes y cuatro comandos\n' > "$TMP"
# Y el tercer caso, que es el que aprobaba sin medir: un fichero donde la frase no
# encaja. Sin el guardia de 'vistas', esto sale 'ok' habiendo juzgado cero cifras.
MUDO=$(mktemp); printf 'el kit trae agentes, pero aqui nadie dice cuantos\n' > "$MUDO"
before=$fail
claim 8 agentes "$TMP" >/dev/null; claim 6 comandos "$TMP" >/dev/null
claim 8 agentes "$MUDO" >/dev/null
rm -f "$TMP" "$MUDO"
if [ $((fail - before)) -eq 3 ]; then
  fail=$before; pass=$((pass+1))
  echo "ok - falsabilidad: detecta una cifra falsa en digito (99), en letra (cuatro) y un"
  echo "     fichero sin ninguna cifra que juzgar (verde sin medir)"
else
  fail=$before; fail=$((fail+1))
  echo "NOT ok - el comprobador no detecto cifras deliberadamente falsas, o aprobo un fichero"
  echo "         donde no tenia nada que medir (tautologia)"
fi

# --- 4. Las cifras de knowledge/EVAL-CRITERIA.md salen del almacen de tiradas ---
# Ese documento no entra en DOCS a proposito. `claim` juzga cifras de inventario
# (suites, ADRs, agentes, comandos) contra lo que hay en el arbol, y NINGUNA de las
# cifras que se pudren ahi es de esa forma: son el n de cada brazo, tasas, un lift y
# el recuento de tareas mudas, que solo existen en kit/evals/runs.jsonl. Medido:
# meterlo en DOCS deja la suite en verde sin mirar una sola de ellas. Lo que si se
# le exige, arriba, es que los scripts que nombra existan.
# El almacen se deja sustituir por el entorno por la misma razon que el interprete: la
# sonda de los puntos de llamada vuelve a correr esta suite contra si misma y, en un
# clon limpio -donde runs.jsonl no existe, porque esta en .gitignore-, tiene que poder
# darle un almacen fabricado para que el punto de llamada de cifras_eval se sonde
# igual. Sin esto la sonda cubriria uno de los dos puntos y diria 'ok': medir la mitad.
STORE="${DOC_CLAIMS_STORE:-kit/evals/runs.jsonl}"
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
# El 2 solo significa "no hay datos" si de verdad no hay almacen, y eso hay que
# exigirlo, no suponerlo. Medido con el almacen presente (57 780 B) y un rc=2
# provocado, esto imprimia "skip - ... no hay kit/evals/runs.jsonl" y cerraba en
# "15 passed, 0 failed, 1 skipped", EXIT=0: un reventon disfrazado de skip, y con un
# motivo falso. Con almacen delante, un rc=2 baja a veredicto y sale rojo como
# cualquier otro rc distinto de 0.
if [ "$rc" -eq 2 ] && [ ! -f "$STORE" ]; then
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
    # (1) Juicio por VALOR: toda cifra pegada a la palabra 'mutantes' tiene que ser
    # uno de los dos unicos recuentos ciertos -los versionados, que este fichero
    # puede reproducir, y el total historico-. "33/33 mutantes" y "30 de los 38
    # mutantes" son la misma afirmacion en dos redacciones y las dos caen aqui.
    #
    # Los dos limites de ESTE bloque, medidos: (i) solo ve las cifras PEGADAS a la
    # palabra -"de los mutantes, se reproducen 25" pasa por aqui sin una queja-, y
    # (ii) solo juzga el VALOR, nunca el papel: con {versionados, total} como unico
    # filtro los dos recuentos ciertos son intercambiables, y "<total>/<total>
    # mutantes; los <total> mutantes versionados" pasa (1) limpio. Para (ii) esta (2),
    # que ata cada cifra a su papel -y ahi si caza esa frase, y tambien "el fichero
    # versiona 25 de ellos" y "los 25 ultimos versionados", que se le escapan a (1)
    # pero no al sensor-.
    #
    # Y lo que se le escapa al sensor ENTERO, que no es lo mismo y es lo que hay que
    # declarar aqui: toda frase falsa cuya redaccion no sea ninguna de las tres de (2)
    # y que ademas, o lleve por cifra uno de los dos recuentos ciertos, o no lleve la
    # cifra pegada a la palabra. Medido sobre el documento real, estas tres pasan sin
    # una queja (las dos primeras van con el papel escrito, no con el numero, para que
    # no se pudran el dia que se anada un mutante):
    #     "En la practica los <total> mutantes se reproducen todos."
    #     "Los <versionados> mutantes historicos cubren toda la serie."
    #     "De los mutantes, se reproducen 25."   (cifra falsa y despegada: da igual cual)
    # Decir que solo se le escapa la cifra que NO va pegada a "mutantes" era falso, y
    # decir que solo se le escapan las cifras ciertas lo era igual: la tercera no es
    # ninguna de las dos cosas y tambien pasa.
    #
    # Y lo que SI caza, para que nadie lea la lista de arriba como la lista entera:
    # cualquier cifra pegada a la palabra que no sea uno de los dos recuentos ciertos,
    # las tres redacciones de (2) con el numero cambiado, la desaparicion de la forma
    # obligatoria y la del rango M-M.
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
    # (2) Juicio por PAPEL: cada patron ata un numero a lo que ese numero significa.
    # Es el lado que (1) no puede ver, porque para (1) los dos recuentos ciertos son
    # intercambiables. Los marcados obligatorios tienen que APARECER: si manana se
    # reescribe la frase en una redaccion que estos patrones no conocen, el sensor
    # se pone rojo en vez de quedarse midiendo cero y cantando verde, que es como se
    # perdio la anterior. Pasarse obliga a redactar de una forma concreta; quedarse
    # corto deja el papel sin vigilar, y ese es el fallo que esto viene a cerrar.
    #
    # El precio de pasarse esta medido y es real: este lado ACUSA A REDACCIONES
    # CIERTAS. Sobre el documento real, escribir "los 30 mutantes que se versionan" en
    # vez de "los 30 mutantes versionados", o "Solo 30 mutantes de los 38 son
    # reproducibles" en vez de "Solo 30 de los 38 mutantes son reproducibles", dispara
    # la queja de patron obligatorio ausente siendo las dos frases verdad. Se acepta a
    # proposito y no se afloja: falla en ruidoso -delante del operador y con un mensaje
    # que dice exactamente que forma echa en falta-, no en silencio, y aflojar por aqui
    # tira justo en la direccion contraria a lo que se le pide al bloque (1).
    ETIQUETA = {"versionados": ("los mutantes versionados", versionados),
                "total": ("el total historico", total)}
    PAPELES = (("los N ... versionados", True,
                r"(?<![\w/-])(\d+)\s+(?:\S+\s+)?versionados", ("versionados",)),
               ("N de los M mutantes", True,
                r"(?<![\w/-])(\d+)\s+de\s+los\s+(\d+)\s+mutantes", ("versionados", "total")),
               # No obligatorio: hoy el doc no lo usa. Esta puesto porque "versiona
               # 25 de ellos" es una de las redacciones medidas que se colaban.
               ("versiona N", False, r"\bversionan?\s+(\d+)", ("versionados",)))
    vistos = set()
    for nombre, _obl, patron, papeles in PAPELES:
        for x in re.finditer(patron, doc):
            vistos.add(nombre)
            for g, papel in enumerate(papeles, 1):
                etiqueta, cierto = ETIQUETA[papel]
                if int(x.group(g)) != cierto:
                    p.append("el doc escribe '%s': ahi el %s tendria que ser %d (%s)"
                             % (" ".join(x.group(0).split()), x.group(g), cierto, etiqueta))
    for nombre, obl, _patron, _papeles in PAPELES:
        if obl and nombre not in vistos:
            p.append("el doc ya no ata ninguna cifra a su papel en la forma '%s': por"
                     " valor, %d y %d son intercambiables y nadie se enteraria"
                     % (nombre, versionados, total))
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
sed -E 's#M9.M40#M9-M999#g' "$EVALDOC" > "$TMPD/m3.md"
# Y los dos que el juicio por valor no puede ver, que son los que motivan el juicio
# por papel: m4 cambia los dos recuentos ciertos de sitio -las dos cifras siguen
# siendo legales, solo estan en el papel del otro- y m5 escribe la cifra sin pegarla
# a la palabra 'mutantes', que es la redaccion medida por la que se colo la mitad de
# la frase original. Si el documento se reescribe y alguna de estas sustituciones
# deja de encajar, la copia sale identica al original, el comprobador no se queja y
# ESTA sonda se pone roja: una sonda que deja de inyectar tiene que notarse.
sed -E 's#([0-9]+)/([0-9]+) mutantes; los ([0-9]+) mutantes versionados#\3/\3 mutantes; los \1 mutantes versionados#' \
    "$EVALDOC" > "$TMPD/m4.md"
sed -E 's#los [0-9]+ mutantes versionados#los 25 ultimos versionados#' "$EVALDOC" > "$TMPD/m5.md"
VARIANTES=(m1 m2 m3 m4 m5)
malos=0
for d in "${VARIANTES[@]}"; do
  [ -n "$(recuento_mutantes "$TMPD/$d.md")" ] || malos=$((malos+1))
done
if [ "$malos" -eq 0 ]; then
  echo "ok - falsabilidad: acusa las ${#VARIANTES[@]} deformaciones del recuento (recuento falso en"
  echo "     las dos redacciones, rango falso, papeles intercambiados y cifra despegada)"
  pass=$((pass+1))
else
  echo "NOT ok - $malos de ${#VARIANTES[@]} deformaciones del recuento pasaron el comprobador"
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
  # "Verde" es CERO quejas, no cero quejas que digan 'AVISO:'. Contando solo esas,
  # esta sonda aprobaba una cita mutilada: medido, un doc que publica el titular del
  # AVISO y se come sus dos lineas de continuacion produce cuatro quejas -el
  # comprobador funciona: la salvedad se publico descabezada- y NINGUNA lleva la
  # cadena 'AVISO:', porque citan la segunda linea y la tercera. El comprobador
  # estaba bien; la sonda medía menos de lo que su comentario prometia.
  # Y el rc, por lo mismo que arriba: si el comprobador revienta aqui, la salida
  # sale vacia y "no queda ninguna queja" seria otra vez un verde sin haber medido.
  restantes_txt=$(cifras_eval "$TMPD/con-aviso.md" "$TMPD/aviso.jsonl"); rc_rest=$?
  restantes=$(printf '%s\n' "$restantes_txt" | /usr/bin/grep -c .)
  if [ "$avisos" -ge 1 ] && [ "$quejas" -ge 1 ] && [ "$rc_rest" -eq 0 ] \
     && [ "$restantes" -eq 0 ]; then
    echo "ok - falsabilidad: una salvedad que report.py aprende a emitir hoy es obligatoria manana"
    pass=$((pass+1))
  else
    echo "NOT ok - la salvedad no se exige sola: report.py emite $avisos AVISO,"
    echo "         el doc que la calla da $quejas queja(s) y el que la publica $restantes (rc=$rc_rest)"
    echo "$restantes_txt"
    fail=$((fail+1))
  fi
else
  echo "skip - falsabilidad del bloque: hace falta $STORE"
  skipped=$((skipped+1))
fi

# Y el lado que ninguna cifra falsa prueba: que un comprobador que REVIENTA salga
# rojo. Las sondas de arriba deforman el documento, asi que solo demuestran que el
# comprobador sabe suspender cuando funciona; el modo que se colaba es el otro, el
# de no llegar a mirar.
#
# Lo que se sonda NO es veredicto() por su cuenta. El bug vivia en los dos PUNTOS DE
# LLAMADA -capturaban la salida del comprobador y no miraban su rc-, y una sonda que
# interroga al helper en aislamiento los deja sin vigilar: medido, revirtiendo solo
# los dos puntos de llamada y dejando helper y sonda intactos, la suite cerraba en
# "16 passed, 0 failed", EXIT=0, con la sonda misma diciendo 'ok'. Un arreglo que
# nadie puede deshacer en rojo es media pieza. Asi que esta sonda vuelve a correr la
# SUITE ENTERA -este mismo fichero, no una copia que se pudre aparte- con el
# interprete saboteado, y exige que salga roja POR ESOS DOS SITIOS.
#
# El sabotaje va entero en el entorno y no escribe nada en el arbol: un interprete de
# usar y tirar en $TMPD que muere si y solo si le pasan a la vez el documento REAL y
# el almacen (o mutantes.py). Esa conjuncion es la que alcanza a los dos puntos de
# llamada y a nada mas: las otras llamadas que citan el documento no citan ninguno de
# los dos, y las demas sondas de este fichero trabajan sobre copias en $TMPD. Un
# fallo incondicional no probaria nada, porque las pondria rojas a todas.
#
# Cada punto de llamada recibe un codigo distinto y se exige ver LOS DOS en la queja,
# no solo EXIT=1. Solo esos dos sitios pueden recibirlos, asi que exigir uno de cada
# es exigir que los dos se hayan sondado y que los dos hayan puesto rojo el reventon;
# sin eso la sonda aprobaria con un rojo que viene de otra cosa, o con la inyeccion
# sin llegar a ejecutarse, que seria otra vez aprobar sin haber medido nada.
#
# Y el 2 de cifras_eval no es un numero cualquiera: es el codigo con el que ese
# comprobador dice "no hay almacen". Inyectarlo CON el almacen delante sonda de paso
# que el skip exige su condicion en vez de suponerla -si vuelve a suponerla, esa
# linea sale 'skip' en vez de 'NOT ok ... (rc=2)' y esta sonda se pone roja-.
if [ -n "${DOC_CLAIMS_SUBSONDA:-}" ]; then
  # Esta corrida ES la sub-corrida: sin este corte, recursion infinita. Se declara en
  # el resumen y no se calla, para que exportar la variable por fuera se vea como un
  # skip en el recuento en vez de borrar la sonda en silencio.
  echo "skip - falsabilidad de los puntos de llamada: esta corrida es la sub-corrida de esa sonda"
  skipped=$((skipped+1))
else
  # El almacen solo tiene que EXISTIR para que la llamada llegue al interprete: lo que
  # se mide aqui no es lo que el almacen diga, sino si el punto de llamada convierte
  # un rc!=0 en rojo. runs.jsonl esta en .gitignore -no tenerlo es el estado de todo
  # clon limpio y de todo worktree recien creado-, asi que cuando falta se fabrica uno
  # vacio en $TMPD y los dos puntos se sondan igual. Sondar uno y cantar verde seria
  # medir la mitad, y es el caso normal, no el raro.
  if [ -f "$STORE" ]; then
    sonda_store="$STORE"
  else
    sonda_store="$TMPD/sonda.jsonl"; : > "$sonda_store"
  fi
  # shellcheck disable=SC2016 # "$@", "$a" y "$d$s" literales a proposito: son el
  # cuerpo del envoltorio, lo expande /bin/sh al ejecutarlo, no este script al
  # escribirlo.
  printf '#!/bin/sh\nd=0; s=0; m=0\nfor a in "$@"; do\n  [ "$a" = "%s" ] && d=1\n  [ "$a" = "%s" ] && s=1\n  [ "$a" = kit/evals/mutantes.py ] && m=1\ndone\n[ "$d$s" = 11 ] && exit 2\n[ "$d$m" = 11 ] && exit 97\nexec %s "$@"\n' \
    "$EVALDOC" "$sonda_store" "$PY3" > "$TMPD/py-revienta"
  chmod +x "$TMPD/py-revienta"
  sub=$(DOC_CLAIMS_SUBSONDA=1 PYTHON3="$TMPD/py-revienta" DOC_CLAIMS_STORE="$sonda_store" \
        bash "$SELF" 2>/dev/null); sub_rc=$?
  rojos=$(printf '%s\n' "$sub" | /usr/bin/grep -c '^NOT ok')
  con2=$(printf '%s\n' "$sub" | /usr/bin/grep -c '^NOT ok.*rc=2)')
  con97=$(printf '%s\n' "$sub" | /usr/bin/grep -c '^NOT ok.*rc=97)')
  if [ "$sub_rc" -eq 1 ] && [ "$con2" -eq 1 ] && [ "$con97" -eq 1 ]; then
    echo "ok - falsabilidad: con el interprete saboteado la SUITE ENTERA sale roja (EXIT=1) y los"
    echo "     dos puntos de llamada ponen rojo el reventon (rc=2 con almacen y rc=97), no 'ok'"
    pass=$((pass+1))
  else
    echo "NOT ok - los puntos de llamada no ponen rojo el reventon: la sub-corrida de la suite"
    echo "         entera salio EXIT=$sub_rc con $rojos 'NOT ok', $con2 con el rc=2 inyectado y"
    echo "         $con97 con el rc=97; se esperaba EXIT=1, 1 y 1. Sus veredictos:"
    # Solo las lineas de veredicto: el detalle de las quejas no dice nada de lo que se
    # juzga aqui y, con el almacen fabricado, son decenas que entierran el sintoma.
    printf '%s\n' "$sub" | /usr/bin/grep -E '^(ok|NOT ok|skip|==)' | sed 's/^/         | /'
    fail=$((fail+1))
  fi
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

# --- 5. La doc de Headroom, contra install.sh, el Makefile y la unidad -----
# Headroom era la unica parte grande del repo sin sensor de doc: cero coincidencias con
# "headroom" en este fichero. Sus afirmaciones no son cifras de inventario -las que
# `claim` sabe juzgar-, son promesas sobre lo que install.sh escribe, sobre lo que la
# unidad systemd arranca y sobre con que se comprueba el enrutado. Se cubren esas.
#
# Lo que NO se cubre, y es deliberado: las cifras de ahorro, latencia y RAM del proxy.
# Son mediciones fechadas de una maquina concreta y no tienen fuente de verdad en el
# arbol, asi que un sensor solo podria compararlas consigo mismas. Copiar el texto no
# es medirlo.
#
# Cada comprobador recibe los ficheros por argumento en vez de nombrarlos dentro: asi
# las sondas de falsabilidad del final pueden interrogarlo sobre copias deformadas. Un
# comprobador que solo sabe mirar el arbol real no se puede poner rojo a proposito.
HRDOC=kit/docs/03-headroom.md
ONBDOC=kit/docs/10-onboarding.md
VERDOC=kit/docs/07-verify.md

# hr_check <sujeto> <comprobador> <fichero...>: un renglon por queja, nada si cuadra.
hr_check() {
  local sujeto="$1" fn="$2"; shift 2
  local q; q=$("$fn" "$@")
  if [ -z "$q" ]; then
    echo "ok - $sujeto"; pass=$((pass+1))
  else
    echo "NOT ok - $sujeto:"; echo "$q"; fail=$((fail+1))
  fi
}

# La unidad systemd: `--mode cache` explicito y NUNCA `--budget` ni `--log-messages`.
# El modo token invalida el prompt-caching, que es de donde sale el ahorro de verdad;
# --budget devuelve HTTP 200 con cuerpo vacio al agotarse, que se lee como un fallo del
# cliente; --log-messages escribe la conversacion entera en claro. doctor.sh vigila la
# unidad INSTALADA (test_headroom_guardrails.sh); lo que nadie vigilaba es el ExecStart
# que PUBLICA la doc, y copiar un ExecStart de un documento es exactamente como llegan
# esos flags a una maquina.
hr_unidad() {
  local f l vistas=0
  for f in "$@"; do
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      vistas=$((vistas+1))
      case "$l" in
        *"--mode cache"*) ;;
        *) echo "  $f: ExecStart sin '--mode cache': $(printf '%s' "$l" | cut -c1-58)" ;;
      esac
      case "$l" in
        *--budget*|*--log-messages*)
          echo "  $f: ExecStart con --budget o --log-messages: $(printf '%s' "$l" | cut -c1-58)" ;;
      esac
    done <<< "$(grep -h '^ExecStart=.*headroom proxy' "$f" 2>/dev/null)"
  done
  [ "$vistas" -gt 0 ] || echo "  ningun ExecStart de 'headroom proxy' en $*: no hay nada que juzgar"
}
hr_check "la unidad de Headroom lleva --mode cache y nunca --budget ni --log-messages" \
  hr_unidad "$HRDOC" kit/install.sh

# ANTHROPIC_BASE_URL se escribe SOLO bajo --with-headroom. Es la promesa central del kit
# sobre esa variable -distribuirla dejaba a quien clonaba en limpio enrutado a un puerto
# muerto, sin API y con un sintoma que no se parece a un problema de config- y vive en
# dos sitios que se pudren por separado: el codigo y la frase del documento. El bloque
# se delimita por sus dos anclas reales (el `if` del flag y su `exit 0` + `fi`); si
# dejan de casar, esto se queja en vez de aprobar sin haber mirado nada.
hr_base_url() {
  local src="$1"; shift
  local gate end hit n dentro=0 f
  gate=$(grep -nF '= "--with-headroom" ]; then' "$src" | head -1 | cut -d: -f1)
  if [ -n "$gate" ]; then
    end=$(awk -v g="$gate" 'NR>=g { if (prev=="  exit 0" && $0=="fi") { print NR; exit } } { prev=$0 }' "$src")
  fi
  if [ -z "$gate" ] || [ -z "$end" ]; then
    echo "  no se reconoce el bloque --with-headroom de $src: no hay nada que juzgar"
  else
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      n=${hit%%:*}
      if [ "$n" -ge "$gate" ] && [ "$n" -le "$end" ]; then
        dentro=$((dentro+1))
      else
        echo "  $src:$n toca ANTHROPIC_BASE_URL fuera del bloque --with-headroom ($gate-$end)"
      fi
    done <<< "$(grep -n 'ANTHROPIC_BASE_URL' "$src" | grep -vE '^[0-9]+:[[:space:]]*#')"
    [ "$dentro" -gt 0 ] || echo "  ninguna linea de $src escribe ANTHROPIC_BASE_URL dentro del bloque: el cableado se fue de sitio"
  fi
  for f in "$@"; do
    if ! grep -qE 'ANTHROPIC_BASE_URL.*--with-headroom|--with-headroom.*ANTHROPIC_BASE_URL' "$f"; then
      echo "  $f ya no dice que ANTHROPIC_BASE_URL la escriba install.sh --with-headroom"
    fi
  done
}
hr_check "ANTHROPIC_BASE_URL solo se escribe bajo --with-headroom, y la doc lo dice" \
  hr_base_url kit/install.sh "$HRDOC"

# `make bootstrap` no instala Headroom. Es opt-in por una medicion, no por gusto (paso 5
# de 10-onboarding.md), asi que el dia que bootstrap lo arrastre, la primera tabla que
# lee un companero nuevo miente y nadie se enteraria: bootstrap no lo declara, lo hace.
#
# Se juzgan los COMANDOS del target, no su texto: las lineas de `echo` del propio
# bootstrap nombran Headroom precisamente para decir que ahi no se instala -y hasta
# imprimen el `install.sh --with-headroom` como pista-, asi que un grep sobre el cuerpo
# entero enrojece el estado correcto. Medido: es lo que hacia la primera version de
# esto. Lo que no puede aparecer es un comando que lo instale.
hr_bootstrap() {
  local mk="$1"; shift
  local cuerpo f
  cuerpo=$(awk '/^bootstrap:/ {on=1; next} /^[a-zA-Z_.-]+:/ {on=0} on {print}' "$mk" \
           | grep -vE '^[[:space:]]*@?echo ')
  if [ -z "$cuerpo" ] || ! printf '%s\n' "$cuerpo" | grep -q 'install.sh'; then
    echo "  no se reconoce el target bootstrap de $mk (o ya no llama a install.sh): nada que juzgar"
  elif printf '%s\n' "$cuerpo" | grep -qi 'headroom'; then
    echo "  un comando del target bootstrap de $mk nombra headroom: la doc promete que bootstrap NO lo instala"
  fi
  for f in "$@"; do
    # shellcheck disable=SC2016 # los backticks son los del markdown de la fila, literales
    if ! grep -qE '^\| Headroom .*`make bootstrap` no lo instala' "$f"; then
      echo "  $f ya no declara que 'make bootstrap' no instala Headroom"
    fi
  done
}
hr_check "'make bootstrap' no instala Headroom, y 10-onboarding.md lo declara" \
  hr_bootstrap Makefile "$ONBDOC"

# Regresion del oraculo de enrutado. `headroom doctor` estuvo recomendado en dos sitios
# -"Mejor que el curl" en 03 y la fila de la tabla de 07- teniendo el propio repo medido
# que miente en los dos sentidos: dice `claude not routed` DENTRO de una sesion enrutada
# (solo juzga el settings.json que el mira, no la sesion) y `codex routed` con cero
# peticiones OpenAI en los logs. Aqui se vigila que no vuelva.
#
# A este comprobador NO se le exige haber juzgado alguna linea, y es la excepcion
# razonada al guardia de 'vistas' que gobierna el resto del fichero: que la doc deje de
# nombrar a `headroom doctor` junto al enrutado es un estado CORRECTO, no un sensor
# ciego. Lo que sostiene la medicion son las dos piezas de al lado: la sonda de
# falsabilidad, que le mete la frase retirada tal como estaba escrita, y hr_oraculos,
# que exige que los dos oraculos que si funcionan sigan citados.
hr_doctor_oraculo() {
  local f l vistas=0
  for f in "$@"; do
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      vistas=$((vistas+1))
      printf '%s' "$l" | grep -qiE 'miente|no uses' \
        || echo "  $f: propone 'headroom doctor' como comprobacion de enrutado: $(printf '%s' "$l" | cut -c1-58)"
    done <<< "$(grep -iE 'headroom doctor' "$f" 2>/dev/null | grep -iE 'enrutad|routed')"
  done
}
hr_oraculos() {
  local f
  for f in "$@"; do
    grep -q 'environ' "$f" || echo "  $f ya no cita el oraculo del entorno del proceso hijo (/proc/<pid>/environ)"
    grep -q 'doctor\.sh' "$f" || echo "  $f ya no cita doctor.sh como oraculo del enrutado"
  done
}
hr_check "ninguna linea de la doc propone 'headroom doctor' como oraculo del enrutado" \
  hr_doctor_oraculo kit/docs/*.md
hr_check "03 y 07 citan los dos oraculos que si contestan (el hijo de la sesion y doctor.sh)" \
  hr_oraculos "$HRDOC" "$VERDOC"

# El pin que no hay: install.sh instala con --upgrade y sin version, asi que el kit no
# espera una version concreta. El documento lo dice ahora porque antes se leia justo lo
# contrario; si algun dia se pina, esto se pone rojo y la frase hay que reescribirla.
hr_sin_pin() {
  local src="$1"; shift
  local pip f
  pip=$(grep -nE "install .*'headroom-ai\[proxy\]'" "$src" | head -1)
  if [ -z "$pip" ]; then
    echo "  $src ya no instala 'headroom-ai[proxy]' sin pin reconocible: nada que juzgar"
  elif printf '%s\n' "$pip" | grep -qE 'headroom-ai\[proxy\](==|>=|<=|~=|!=)'; then
    echo "  $src instala headroom-ai[proxy] con pin de version: la doc dice que no hay pin"
  fi
  for f in "$@"; do
    grep -q 'No hay pin de versión' "$f" || echo "  $f ya no dice que no hay pin de version"
  done
}
hr_check "headroom-ai[proxy] se instala sin pin, y 03-headroom.md lo dice" \
  hr_sin_pin kit/install.sh "$HRDOC"

# Falsabilidad de los cinco. Sin esto, un grep que dejara de encajar daria verde para
# siempre, que es el modo de fallo que este fichero existe para evitar. Cada caso
# deforma una COPIA con la averia exacta que su comprobador persigue -incluida la frase
# que se retiro, escrita tal como estaba- y se exigen los diez rojos: los cinco del lado
# del codigo y los cinco del lado del documento, que son los dos sitios donde se pudre.
HRTMP=$(mktemp -d) || exit 1
sed 's/--mode cache/--mode token/' "$HRDOC"                     > "$HRTMP/u-token.md"
sed 's/--no-telemetry/--no-telemetry --log-messages/' "$HRDOC"  > "$HRTMP/u-log.md"
{ cat kit/install.sh; echo 'ANTHROPIC_BASE_URL=http://127.0.0.1:8787  # reintroducido fuera del flag'; } \
                                                                > "$HRTMP/i-fuera.sh"
sed 's/--with-headroom//g' "$HRDOC"                             > "$HRTMP/d-sin-flag.md"
sed 's|bash kit/install.sh$|bash kit/install.sh --with-headroom|' Makefile > "$HRTMP/mk-hr"
sed 's/no lo instala/lo instala/' "$ONBDOC"                     > "$HRTMP/d-bootstrap.md"
# shellcheck disable=SC2016 # es la frase retirada, con sus backticks de markdown literales
printf '%s\n' '**Mejor que el `curl`: `headroom doctor`.** Comprueba que Claude Code y Codex estan enrutados.' \
                                                                > "$HRTMP/d-viejo.md"
sed 's/environ/entorno/g; s/doctor\.sh/comprobador/g' "$VERDOC" > "$HRTMP/d-sin-oraculos.md"
sed "s/'headroom-ai\[proxy\]'/'headroom-ai[proxy]==0.36.2'/" kit/install.sh > "$HRTMP/i-pin.sh"
sed 's/No hay pin/Hay pin/' "$HRDOC"                            > "$HRTMP/d-pin.md"
hr_malos=0
for hr_caso in \
  "hr_unidad $HRTMP/u-token.md" \
  "hr_unidad $HRTMP/u-log.md" \
  "hr_base_url $HRTMP/i-fuera.sh $HRDOC" \
  "hr_base_url kit/install.sh $HRTMP/d-sin-flag.md" \
  "hr_bootstrap $HRTMP/mk-hr $ONBDOC" \
  "hr_bootstrap Makefile $HRTMP/d-bootstrap.md" \
  "hr_doctor_oraculo $HRTMP/d-viejo.md" \
  "hr_oraculos $HRTMP/d-sin-oraculos.md" \
  "hr_sin_pin $HRTMP/i-pin.sh $HRDOC" \
  "hr_sin_pin kit/install.sh $HRTMP/d-pin.md"
do
  # shellcheck disable=SC2086 # la palabra es "<comprobador> <fichero...>": se parte a proposito
  [ -n "$($hr_caso)" ] || { hr_malos=$((hr_malos+1)); echo "     (sin queja: $hr_caso)"; }
done
if [ "$hr_malos" -eq 0 ]; then
  echo "ok - falsabilidad: los cinco comprobadores de Headroom acusan las diez averias"
  echo "     fabricadas (--mode token, --log-messages, la URL fuera del flag, bootstrap"
  echo "     instalandolo, la frase retirada de 'headroom doctor' y el pin de version)"
  pass=$((pass+1))
else
  echo "NOT ok - $hr_malos de 10 averias fabricadas pasaron el comprobador (tautologia)"
  fail=$((fail+1))
fi
rm -f "$HRTMP"/*; rmdir "$HRTMP"

if [ "$skipped" -gt 0 ]; then
  echo "== $pass passed, $fail failed, $skipped skipped =="
else
  echo "== $pass passed, $fail failed =="
fi
[ "$fail" -eq 0 ] || exit 1
