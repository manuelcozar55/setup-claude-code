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
DOCS=(README.md AGENTS.md CLAUDE.md CONTRIBUTING.md kit/README.md kit/evals/README.md
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
# claim_omiso: estricto con las cifras que estan, pero si no hay ninguna lo dice como
# 'skip' en vez de aprobar. Es para el material donde una afirmacion puede legitimamente
# no escribirse -[Unreleased] recien etiquetada, por ejemplo-: ahi un 'ok' seria un verde
# mudo y un fallo seria enrojecer un fichero correcto. El skip se ve en el resumen.
claim_omiso() { CLAIM_SIN_CIFRA=skip; claim "$@"; CLAIM_SIN_CIFRA=; }
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
  elif [ "$vistas" -eq 0 ] && [ "$CLAIM_SIN_CIFRA" = skip ]; then
    # Ni 'ok' ni rojo: la afirmacion no esta escrita, y quien lea el resumen tiene que
    # verlo. Un 'ok' aqui es el verde mudo que el caso de abajo existe para evitar.
    echo "skip - '$noun': $* no escribe ninguna cifra delante; no se ha comprobado"
    skipped=$((skipped+1))
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
# que NO se hace es aflojar los claim de abajo a claim_flojo, que dice 'ok' habiendo
# juzgado cero cifras.
#
# Que la seccion tenga contenido tampoco garantiza que hable del inventario, y eso lo
# aprendio este sensor en carne propia: al cortar la 1.2.0, la primera entrada nueva de
# [Unreleased] era de licencias -no menciona suites, ni ADRs, ni el eval- y las seis
# lineas de abajo dieron seis fallos sobre un CHANGELOG correcto. De ahi claim_omiso:
# estricto con la cifra que este escrita, 'skip' visible con la que no. La diferencia
# con claim_flojo es justo la que importa aqui: no hay ningun camino que imprima 'ok'
# sin haber juzgado nada.
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
  claim_omiso "$SUITES" suites "$UNREL"
  claim_omiso "$(count knowledge/DECISIONS/*.md)" ADRs "$UNREL"
  # El inventario del eval, que es lo que esta rama anade y lo que [Unreleased] anuncia.
  # Aqui si van estrictos -no como sobre DOCS-: las entradas nuevas escriben las cuatro
  # cifras, asi que hay algo que juzgar. Ojo al redactarlas: el sed de claim es GOLOSO y
  # solo juzga la ULTIMA aparicion de "<n> <sustantivo>" de cada linea, asi que un
  # recuento parcial cierto ("decide 3 tareas") enrojece si queda el ultimo de su linea.
  claim_omiso "$(count kit/evals/tasks/*.yaml)" tareas "$UNREL"
  claim_omiso "$(grep -l '^tipo: positiva' kit/evals/tasks/*.yaml | wc -l)" positivas "$UNREL"
  claim_omiso "$(grep -l '^tipo: negativa' kit/evals/tasks/*.yaml | wc -l)" negativas "$UNREL"
  claim_omiso "$(grep -cE '^    \("M[0-9]+' kit/evals/mutantes.py)" mutantes "$UNREL"
fi
rm -f "$UNREL"; rmdir "$UNRELD"

# Falsabilidad del modo 'skip' que estrena el bloque de arriba. Lo que hay que demostrar
# no es que sepa omitir -eso se ve en el resumen- sino que omitir no le ha quitado el
# juicio: con una cifra escrita y falsa tiene que seguir enrojeciendo. Las dos secciones
# se fabrican, porque deformar la real no distinguiria un caso del otro.
OMTMP=$(mktemp -d) || exit 1
printf '## [Unreleased]\n\n- entrada de licencias, sin inventario.\n' > "$OMTMP/sin.md"
printf '## [Unreleased]\n\n- ahora hay 99 suites de test.\n' > "$OMTMP/con.md"
om_sin=$(claim_omiso "$SUITES" suites "$OMTMP/sin.md")
om_con=$(claim_omiso "$SUITES" suites "$OMTMP/con.md")
if [ "${om_sin#skip}" != "$om_sin" ] && [ "${om_con#NOT ok}" != "$om_con" ]; then
  echo "ok - claim_omiso omite la cifra que no esta y sigue enrojeciendo una que miente"
  pass=$((pass+1))
else
  echo "NOT ok - el modo 'skip' de claim no discrimina: sin cifra dijo '${om_sin%%$'\n'*}'"
  echo "         y con una cifra falsa dijo '${om_con%%$'\n'*}'"
  fail=$((fail+1))
fi
rm -f "$OMTMP/sin.md" "$OMTMP/con.md"; rmdir "$OMTMP"

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

# --- 6. La capa de IOCs: el kit la trae, y ningun documento puede negarlo ----
# Tres documentos publicaban que "el kit no trae iocs.json" y que para activar la capa
# habia que copiar el ejemplo a $HOME/.claude/hooks/. Las dos cosas eran falsas:
# kit/sentinel/iocs.json esta versionado, install.sh lo copia junto al hook y doctor.sh
# imprime PASS en una instalacion limpia; y el paso que mandaba el doc creaba un fichero
# SOMBREADO, porque load_iocs() mira primero al lado de sentinel_preflight.py. Nada se
# puso rojo porque el sensor de esta suite juzga cifras de inventario, y "el kit no lo
# trae" no lleva cifra.
#
# Se juzga en los DOS sentidos, y por eso el fichero entra por argumento: mientras el kit
# lo distribuya, ningun documento puede negarlo; si algun dia deja de distribuirlo, el que
# lo afirme se pone rojo. Un sensor de un solo lado convierte el arreglo de hoy en la
# mentira de manana.
iocs_doc() {
  local ioc="$1"; shift
  local f l corte vistas=0
  corte=$(printf '%s' "$ioc" | cut -c1-40)
  for f in "$@"; do
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      vistas=$((vistas+1))
      if [ -f "$ioc" ]; then
        printf '%s' "$l" | grep -qiE 'no (lo |la )?(trae|incluye|distribuye|reparte)' \
          && echo "  $f niega que el kit traiga $corte, y esta versionado: $(printf '%s' "$l" | cut -c1-70)"
      elif printf '%s' "$l" | grep -qiE '(trae|distribuye|incluye|viene con)' \
        && ! printf '%s' "$l" | grep -qiE 'no (lo |la )?(trae|incluye|distribuye|reparte)'; then
        echo "  $f afirma que el kit trae $corte y ya no esta en el arbol: $(printf '%s' "$l" | cut -c1-70)"
      fi
    done <<< "$(grep -ni 'iocs\.json' "$f" 2>/dev/null | grep -v 'doc-claims:ignore')"
  done
  [ "$vistas" -gt 0 ] \
    || echo "  ninguno de los $# documentos nombra iocs.json: no hay nada que juzgar"
}
# SECURITY.md no esta en DOCS -no habla en presente del inventario del arbol- pero es uno
# de los tres sitios donde vivia la frase falsa, asi que entra aqui por su nombre.
hr_check "ningun documento niega que el kit distribuya kit/sentinel/iocs.json" \
  iocs_doc kit/sentinel/iocs.json "${DOCS[@]}" SECURITY.md

# Falsabilidad, los dos sentidos y el caso mudo. Las dos primeras copias reinyectan la
# frase retirada TAL COMO estaba escrita; la tercera pregunta por un iocs.json que no
# existe, que es el unico modo de sondar la otra rama sin borrar el fichero del arbol.
IOCTMP=$(mktemp -d) || exit 1
sed 's/el kit lo distribuye/el kit no lo trae/' kit/docs/05-security.md > "$IOCTMP/d-niega.md"
sed 's/que el kit \*\*sí\*\* distribuye/que el kit no incluye/' SECURITY.md > "$IOCTMP/s-niega.md"
printf 'Sentinel lee sus patrones de un fichero.\n' > "$IOCTMP/d-mudo.md"
ioc_malos=0
for ioc_caso in \
  "iocs_doc kit/sentinel/iocs.json $IOCTMP/d-niega.md" \
  "iocs_doc kit/sentinel/iocs.json $IOCTMP/s-niega.md" \
  "iocs_doc $IOCTMP/no-existe.json kit/docs/05-security.md" \
  "iocs_doc kit/sentinel/iocs.json $IOCTMP/d-mudo.md"
do
  # shellcheck disable=SC2086 # la palabra es "<comprobador> <fichero...>": se parte a proposito
  [ -n "$($ioc_caso)" ] || { ioc_malos=$((ioc_malos+1)); echo "     (sin queja: $ioc_caso)"; }
done
if [ "$ioc_malos" -eq 0 ]; then
  echo "ok - falsabilidad: acusa las dos redacciones de la frase retirada, el documento que"
  echo "     afirmaria lo contrario si el kit dejara de traer el fichero, y el que no mide nada"
  pass=$((pass+1))
else
  echo "NOT ok - $ioc_malos de 4 averias fabricadas pasaron el comprobador de iocs.json"
  fail=$((fail+1))
fi
rm -f "$IOCTMP"/*; rmdir "$IOCTMP"

# --- 7. La plantilla publica: sin el estado de esta maquina y con techo propio ---
# kit/claude/CLAUDE.md no es documentacion: install.sh la ESCRIBE en el $HOME/.claude de
# quien la instala. Llevaba dentro dos bloques que Claude Code inyecta el mismo en cada
# sesion -'# userEmail' y '# currentDate'-, asi que la plantilla le afirmaba al modelo un
# correo ajeno y una fecha congelada (112 dias de desfase el dia que se retiro) en cada
# sesion de cada usuario. Y una version fijada de agent-browser, que se pudre sola en
# cuanto el paquete publica: la cura no es actualizarla, es no escribirla.
#
# El techo va aqui por una asimetria medida: el presupuesto de contexto de
# test_harness_structure.sh vigila SOLO el CLAUDE.md de la raiz (<100 lineas, <900
# aprox-tokens; medido 76/899), y la plantilla que se reparte llegaba a 143 lineas y 1.977
# aprox-tokens sin un solo sensor. Su techo es mas alto a proposito -tiene que sostenerse
# sola en una maquina recien instalada, sin knowledge/ ni skills al lado- pero es un
# numero declarado y medido, no la ausencia de numero. Pasar de aqui pide otra ronda de
# poda (knowledge/AUDIT-CLAUDE-MD.md, que aun tiene secciones marcadas SKILL y HOOK), no
# subir el techo.
PLANTILLA_LINEAS=120
PLANTILLA_TOKENS=1700
plantilla_doc() {
  local f="$1" l t
  if [ ! -f "$f" ]; then
    echo "  no existe $f: install.sh escribe esa plantilla en el \$HOME de quien lo corre"
    return 0
  fi
  grep -qi 'userEmail' "$f" \
    && echo "  $f fija el correo del usuario: Claude Code inyecta '# userEmail' en runtime"
  grep -qiE "currentDate|today's date is" "$f" \
    && echo "  $f fija la fecha: Claude Code inyecta '# currentDate' en runtime, y aqui se pudre"
  grep -qE 'agent-browser[ `]+[0-9]+\.[0-9]+' "$f" \
    && echo "  $f fija una version de agent-browser: se pudre en la siguiente publicacion"
  l=$(wc -l < "$f" | tr -d ' ')
  t=$(( $(wc -c < "$f" | tr -d ' ') / 4 ))
  [ "$l" -lt "$PLANTILLA_LINEAS" ] \
    || echo "  $f tiene $l lineas y su techo declarado son $PLANTILLA_LINEAS"
  [ "$t" -lt "$PLANTILLA_TOKENS" ] \
    || echo "  $f tiene $t aprox-tokens (chars/4) y su techo declarado son $PLANTILLA_TOKENS"
  return 0
}
hr_check "la plantilla kit/claude/CLAUDE.md no lleva estado de una maquina y cabe en su techo ($PLANTILLA_LINEAS lineas / $PLANTILLA_TOKENS aprox-tokens)" \
  plantilla_doc kit/claude/CLAUDE.md

# Falsabilidad: los tres bloques retirados, escritos tal como estaban, el techo desbordado
# y la plantilla ausente.
PLTMP=$(mktemp -d) || exit 1
{ cat kit/claude/CLAUDE.md; printf '# userEmail\nThe user email address is x@example.com.\n'; } \
  > "$PLTMP/p-mail.md"
{ cat kit/claude/CLAUDE.md; printf '# currentDate\nToday'"'"'s date is 2026-05-13.\n'; } \
  > "$PLTMP/p-fecha.md"
# El pin de version se ANADE en vez de sustituir una frase de la plantilla. El ancla
# anterior era su linea literal ("Installed globally as `agent-browser`") y se rompio al
# retirar esa afirmacion -la plantilla decia en presente que el paquete ya estaba
# instalado, y el kit no lo instala-, con lo que la deformacion dejo de deformar y la
# sonda aprobaba sin medir. Medido: "1 de 5 averias fabricadas pasaron el comprobador".
# shellcheck disable=SC2016 # los backticks son los del markdown de la plantilla, literales
{ cat kit/claude/CLAUDE.md; printf -- '- Pinned to `agent-browser 0.27.0`.\n'; } \
  > "$PLTMP/p-version.md"
{ cat kit/claude/CLAUDE.md; seq 1 "$PLANTILLA_LINEAS" | sed 's/^/relleno /'; } > "$PLTMP/p-gordo.md"
pl_malos=0
for pl_caso in p-mail p-fecha p-version p-gordo no-existe; do
  [ -n "$(plantilla_doc "$PLTMP/$pl_caso.md")" ] \
    || { pl_malos=$((pl_malos+1)); echo "     (sin queja: $pl_caso)"; }
done
if [ "$pl_malos" -eq 0 ]; then
  echo "ok - falsabilidad: acusa los tres bloques retirados (userEmail, currentDate, la version"
  echo "     de agent-browser), el techo desbordado y la plantilla que no esta"
  pass=$((pass+1))
else
  echo "NOT ok - $pl_malos de 5 averias fabricadas pasaron el comprobador de la plantilla"
  fail=$((fail+1))
fi
rm -f "$PLTMP"/*; rmdir "$PLTMP"

# --- 8. La version: una fuente legible por maquina y sus copias en prosa ------
# Hasta la 1.1.0 la version vivia SOLO en prosa -README.md y CLAUDE.md decian "v1.0.0,
# estable"- y nada la vigilaba: `grep '1\.0\.0' kit/test/*.sh` daba cero coincidencias con
# el arbol a 111 commits de la etiqueta. Etiquetar la 1.1.0 habria dejado los dos
# documentos diciendo v1.0.0 con las 27 suites en verde.
#
# La fuente es el fichero VERSION y NO `git tag`: actions/checkout no trae etiquetas, asi
# que atarlo a la etiqueta degradaria este check a un skip en CI, que es un verde que no
# mide. La seccion mas nueva del CHANGELOG entra porque es la que dice QUE es esa version;
# sus secciones publicadas siguen fuera de `claim` por lo de §1, que es otra cosa: aqui no
# se juzga ninguna cifra de dentro, solo el numero de la cabecera.
#
# En prosa se ancla a la linea que declara el estado del kit ("v1.1.0, estable"), no a
# cualquier vX.Y.Z del documento: la capa de la raiz publica su propia version en la fila
# de al lado ("v0.1.0, nuevo") y es correcta. El precio del ancla esta medido y se acepta:
# si alguien escribe "estable" en una linea que lleva otra version, sale rojo; y si la
# quita, sale rojo por no haber medido nada.
ver_unica() {
  local vf="$1" chlog="$2"; shift 2
  local ver nuevo f v n
  ver=$(sed -n 1p "$vf" 2>/dev/null | tr -d ' \r')
  if [ -z "$ver" ]; then
    echo "  no hay $vf o su primera linea esta vacia: la version vuelve a vivir solo en prosa"
    return 0
  fi
  case "$ver" in
    [0-9]*.[0-9]*.[0-9]*) ;;
    *) echo "  $vf no contiene una version semantica, sino '$ver'"; return 0 ;;
  esac
  nuevo=$(grep -oE '^## \[[0-9]+\.[0-9]+\.[0-9]+\]' "$chlog" 2>/dev/null | sed -n 1p \
          | tr -d '#[] ')
  if [ -z "$nuevo" ]; then
    echo "  $chlog no publica ninguna seccion '## [x.y.z]': $vf dice $ver y nadie lo respalda"
  elif [ "$nuevo" != "$ver" ]; then
    echo "  $vf dice $ver y la seccion mas nueva de $chlog es la [$nuevo]"
  fi
  for f in "$@"; do
    n=0
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      n=$((n+1))
      [ "$v" = "v$ver" ] || echo "  $f publica $v donde $vf dice $ver"
    done <<< "$(grep -h 'estable' "$f" 2>/dev/null | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+')"
    [ "$n" -gt 0 ] \
      || echo "  $f ya no publica ninguna version junto a 'estable': no hay nada que juzgar"
  done
}
hr_check "VERSION, README.md, CLAUDE.md y la seccion mas nueva de CHANGELOG.md dicen la misma version" \
  ver_unica VERSION CHANGELOG.md README.md CLAUDE.md

# Falsabilidad. Las deformaciones NO salen del arbol real, y esa es la diferencia con las
# sondas de arriba: mientras la version en curso no este etiquetada en el CHANGELOG, el
# comprobador ya se queja del arbol, y deformar una copia de un estado que YA esta rojo no
# demuestra nada -saldria queja igual y la sonda aprobaria sin medir-. Asi que se fabrica
# un juego coherente de cuatro ficheros, se exige que salga VERDE, y desde ahi se deforma
# una pieza cada vez.
VTMP=$(mktemp -d) || exit 1
printf '9.9.9\n' > "$VTMP/VERSION"
# shellcheck disable=SC2016 # los backticks son los del markdown de las dos filas, literales
printf '| **`kit/`** | La instalacion: guards, hooks, Sentinel | v9.9.9, estable |\n' > "$VTMP/README.md"
# shellcheck disable=SC2016 # idem: es la linea de CLAUDE.md, no una expansion
printf -- '- `kit/` - capa de instalacion, v9.9.9, estable. No se toca sin `make test`.\n' \
  > "$VTMP/CLAUDE.md"
printf '# Changelog\n\n## [Unreleased]\n\n## [9.9.9] - 2026-01-01\n\n## [1.0.0] - 2026-08-05\n' \
  > "$VTMP/CHANGELOG.md"
printf '1.2.3\n' > "$VTMP/VERSION-otra"
: > "$VTMP/VERSION-vacia"
sed 's/v9\.9\.9/v1.2.3/' "$VTMP/README.md"                  > "$VTMP/README-otra.md"
sed 's/v9\.9\.9, //'     "$VTMP/README.md"                  > "$VTMP/README-muda.md"
sed 's/v9\.9\.9/v1.2.3/' "$VTMP/CLAUDE.md"                  > "$VTMP/CLAUDE-otra.md"
sed 's/^## \[9\.9\.9\]/## [1.2.3]/' "$VTMP/CHANGELOG.md"    > "$VTMP/CHANGELOG-otra.md"
sed '/^## \[[0-9]/d'     "$VTMP/CHANGELOG.md"               > "$VTMP/CHANGELOG-sin.md"
ver_malos=0
if [ -n "$(ver_unica "$VTMP/VERSION" "$VTMP/CHANGELOG.md" "$VTMP/README.md" "$VTMP/CLAUDE.md")" ]; then
  ver_malos=$((ver_malos+1)); echo "     (el juego coherente sale con quejas: el comprobador no sabe aprobar)"
fi
for ver_caso in \
  "$VTMP/VERSION-otra $VTMP/CHANGELOG.md $VTMP/README.md $VTMP/CLAUDE.md" \
  "$VTMP/VERSION-vacia $VTMP/CHANGELOG.md $VTMP/README.md $VTMP/CLAUDE.md" \
  "$VTMP/VERSION $VTMP/CHANGELOG-otra.md $VTMP/README.md $VTMP/CLAUDE.md" \
  "$VTMP/VERSION $VTMP/CHANGELOG-sin.md $VTMP/README.md $VTMP/CLAUDE.md" \
  "$VTMP/VERSION $VTMP/CHANGELOG.md $VTMP/README-otra.md $VTMP/CLAUDE.md" \
  "$VTMP/VERSION $VTMP/CHANGELOG.md $VTMP/README-muda.md $VTMP/CLAUDE.md" \
  "$VTMP/VERSION $VTMP/CHANGELOG.md $VTMP/README.md $VTMP/CLAUDE-otra.md"
do
  # shellcheck disable=SC2086 # la palabra son los cuatro ficheros: se parte a proposito
  [ -n "$(ver_unica $ver_caso)" ] \
    || { ver_malos=$((ver_malos+1)); echo "     (sin queja: $ver_caso)"; }
done
if [ "$ver_malos" -eq 0 ]; then
  echo "ok - falsabilidad: aprueba un juego coherente y acusa las siete deformaciones (VERSION"
  echo "     distinta y vacia, CHANGELOG con otra cabecera y sin ninguna, README con otra"
  echo "     version y sin ninguna, CLAUDE.md con otra version)"
  pass=$((pass+1))
else
  echo "NOT ok - $ver_malos de 8 casos fabricados salieron al reves (tautologia)"
  fail=$((fail+1))
fi
rm -f "$VTMP"/*; rmdir "$VTMP"

# --- 9. La cadena de hooks, el inventario de plugins y el hook que ya no se cablea ---
# Tres afirmaciones publicadas que se pudrieron sin que nada se pusiera rojo, porque
# `claim` solo sabe juzgar los sustantivos del inventario (suites, ADRs, agentes...):
#   - "una llamada a Bash pasa por 7 hooks PreToolUse en serie": la cadena real es de 6.
#   - "declara ocho plugins ... Cinco vienen del marketplace oficial": son 7 y 4, y la
#     tabla mantenia una fila para github@claude-plugins-official, que ya no esta en el
#     settings: un plugin fantasma que se lee como instrucción de instalación.
#   - "el hook `rtk hook claude` de settings.json": el kit dejo de cablearlo, y la frase
#     seguia en cuatro documentos, en el WARN de doctor.sh y en THIRD-PARTY.md.
# Las tres se derivan de kit/claude/settings.json -lo que install.sh reparte- en vez de
# escribirse a mano. Una cifra copiada es exactamente la averia que este fichero persigue.
SETTINGS=kit/claude/settings.json
SECDOC=kit/docs/05-security.md
PLUGDOC=kit/docs/08-plugins-mcp-y-skills.md

# La cadena que ve UNA LLAMADA A BASH: matcher vacio (corre antes de cualquier tool) o
# matcher que casa con "Bash" como regex anclada, que es como Claude Code lo evalua. Los
# hooks de `Read` y de `Write|Edit` existen y no cuentan aqui a proposito: la frase del
# documento habla del coste de una llamada a Bash, no del total de hooks del fichero.
cadena_bash() {
  local s="$1"; shift
  local real f l n vistas=0
  real=$(jq '[.hooks.PreToolUse[] | . as $h
              | select((($h.matcher // "") == "") or ("Bash" | test("^(" + $h.matcher + ")$")))
              | .hooks[]] | length' "$s" 2>/dev/null)
  case "$real" in
    ''|0) echo "  no se puede contar la cadena PreToolUse de $s: no hay nada que juzgar"
          return 0 ;;
  esac
  # shellcheck disable=SC2016 # los backticks son los del markdown del documento, literales
  for f in "$@"; do
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      vistas=$((vistas+1))
      n=$(printf '%s' "$l" | sed -E 's/.*[^0-9]([0-9]+) hooks `PreToolUse`.*/\1/')
      [ "$n" = "$real" ] \
        || echo "  $f publica $n hooks PreToolUse y jq cuenta $real en $s"
    done <<< "$(grep -nE '[0-9]+ hooks `PreToolUse`' "$f" 2>/dev/null)"
  done
  [ "$vistas" -gt 0 ] \
    || echo "  ningun documento de $* publica la cifra de la cadena PreToolUse: no hay nada que juzgar"
}
hr_check "la cifra de hooks PreToolUse de 05-security.md es la que cuenta jq en settings.json" \
  cadena_bash "$SETTINGS" "$SECDOC"

# El inventario de plugins, del mismo settings.json. `claim` vale tal cual para el total
# ("siete plugins") y para los oficiales anclado a su frase ("cuatro del marketplace
# oficial"): "oficiales" a secas no aparece con cifra delante en ningun documento. El numeral
# va en minuscula en el documento a proposito: `claim` compara la palabra tal cual y "Cuatro"
# le es invisible.
PLUG_TOTAL=$(jq '.enabledPlugins | length' "$SETTINGS")
PLUG_OFI=$(jq '[.enabledPlugins | keys[]
                | select(endswith("@claude-plugins-official"))] | length' "$SETTINGS")
claim "$PLUG_TOTAL" plugins "${DOCS[@]}"
claim "$PLUG_OFI" 'del marketplace oficial' "$PLUGDOC"

# Y que la doc no nombre un plugin que el settings no declara. La fila fantasma de
# github@claude-plugins-official sobrevivio meses a que se quitara de enabledPlugins, y una
# fila de esa tabla se lee como "esto lo tienes activo". Se excluye la forma `git@host` de
# una URL SSH, que casa con el patron y no es una referencia de plugin.
plugins_nombrados() {
  local s="$1"; shift
  local f p vistas=0
  for f in "$@"; do
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      case "$p" in git@*) continue ;; esac
      vistas=$((vistas+1))
      jq -e --arg p "$p" '.enabledPlugins | has($p)' "$s" >/dev/null 2>&1 \
        || echo "  $f nombra el plugin '$p' y $s no lo declara en enabledPlugins"
    done <<< "$(grep -hoE '[a-z0-9][a-z0-9_-]*@[a-z0-9][a-z0-9_-]*' "$f" 2>/dev/null | sort -u)"
  done
  [ "$vistas" -gt 0 ] || echo "  ningun documento de $* nombra un plugin: no hay nada que juzgar"
}
hr_check "todo plugin que nombra la doc esta declarado en enabledPlugins de settings.json" \
  plugins_nombrados "$SETTINGS" "$PLUGDOC" kit/docs/04-superpowers.md

# Los 4 guards de Bash: los hooks con matcher Bash que NO pasan por optional-hook.sh, o sea
# los que llevan sus patrones dentro. 10-onboarding.md publica la misma cifra para otro
# hecho ("`jq` es dependencia dura de N guards"), y hoy coinciden por una razon
# comprobable: los cuatro leen el payload con jq. Se comprueba que sigan coincidiendo antes
# de juzgar con una sola cifra dos frases distintas; el dia que divergan, esto se queja en
# vez de dejar una de las dos podrida.
GUARDS=$(jq -r '[.hooks.PreToolUse[] | . as $h
                 | select((($h.matcher // "") != "") and ("Bash" | test("^(" + $h.matcher + ")$")))
                 | .hooks[].command | select(test("optional-hook") | not)] | length' "$SETTINGS")
GUARDS_JQ=$(grep -lE '\bjq\b' kit/claude/hooks/*.sh 2>/dev/null | wc -l | tr -d ' ')
if [ "$GUARDS" = "$GUARDS_JQ" ]; then
  claim "$GUARDS" guards "$SECDOC" "$ONBDOC"
else
  echo "NOT ok - los guards de Bash del settings ($GUARDS) y los que dependen de jq"
  echo "         ($GUARDS_JQ) ya no son los mismos: 05-security.md y 10-onboarding.md"
  echo "         publican una sola cifra para dos hechos que han dejado de coincidir"
  fail=$((fail+1))
fi

# `rtk hook claude`: el kit dejo de cablearlo, asi que la unica mencion honesta es en
# pasado. Se juzgan dos cosas: (a) los comandos de hook del settings, donde no puede
# aparecer, y (b) toda linea del arbol versionado que lo nombre, que tiene que decir a la
# vez que se retiro. Quedan fuera CHANGELOG.md y knowledge/ por lo mismo que en §1: son
# registros fechados y ahi la frase era cierta el dia que se escribio -docs/superpowers/ ya
# esta fuera de DOCS por eso mismo-, y este propio fichero, que contiene la cadena porque es
# quien la busca.
#
# A la mitad (b) NO se le exige haber juzgado alguna linea, y es la misma excepcion razonada
# que hr_doctor_oraculo: que nadie lo nombre es el estado CORRECTO, no un sensor ciego. Lo
# que sostiene la medicion es la sonda de falsabilidad, que le mete la frase retirada tal
# como estaba escrita y exige queja.
rtk_no_cableado() {
  local s="$1"; shift
  local f l cmds
  cmds=$(jq -r '.hooks // {} | .. | .command? // empty' "$s" 2>/dev/null)
  if [ -z "$cmds" ]; then
    echo "  no se leen los comandos de hook de $s: no hay nada que juzgar"
  else
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      case "$l" in
        *rtk*) echo "  $s vuelve a cablear rtk en un hook: $(printf '%s' "$l" | cut -c1-58)" ;;
      esac
    done <<< "$cmds"
  fi
  for f in "$@"; do
    while IFS= read -r l; do
      [ -n "$l" ] || continue
      printf '%s' "$l" \
        | grep -qiE 'se retir|ya no|cableaba|invocaba|tra[ií]a|hubo|dej[oó] de|hasta el' \
        || echo "  $f afirma en presente el hook 'rtk hook claude': $(printf '%s' "$l" | cut -c1-58)"
    done <<< "$(grep -n 'rtk hook claude' "$f" 2>/dev/null)"
  done
}
# La lista se calcula aqui y no dentro del comprobador, como el resto de §5: asi la sonda
# de falsabilidad puede interrogarlo sobre copias deformadas. `grep -rl` y no `git grep`
# para no depender de que el arbol sea un repo con indice.
RTK_FICHEROS=$(grep -rl 'rtk hook claude' . --exclude-dir=.git 2>/dev/null \
               | sed 's|^\./||' \
               | grep -vE '^(CHANGELOG\.md|knowledge/|docs/superpowers/|kit/test/test_doc_claims\.sh)' \
               | sort | tr '\n' ' ')
# shellcheck disable=SC2086 # la lista de ficheros se parte a proposito
hr_check "ningun hook del kit cablea 'rtk hook claude' y ninguna linea lo afirma en presente" \
  rtk_no_cableado "$SETTINGS" $RTK_FICHEROS

# Falsabilidad de los cuatro comprobadores de esta seccion: cada caso deforma una COPIA con
# la averia exacta que su comprobador persigue -del lado del settings y del lado del
# documento, que son los dos sitios donde se pudre-, y ademas se exige que el arbol real
# salga limpio, porque un comprobador que se queja siempre no distingue nada.
NUTMP=$(mktemp -d) || exit 1
jq '.hooks.PreToolUse += [{"matcher":"Bash","hooks":[{"type":"command","command":"$HOME/.claude/hooks/optional-hook.sh rtk hook claude","timeout":10}]}]' \
  "$SETTINGS" > "$NUTMP/s-mas-rtk.json"
jq 'del(.enabledPlugins["codex@openai-codex"])' "$SETTINGS" > "$NUTMP/s-menos-plugin.json"
# shellcheck disable=SC2016 # los backticks son los del markdown de 05-security.md, literales
sed 's/6 hooks `PreToolUse`/9 hooks `PreToolUse`/' "$SECDOC"          > "$NUTMP/d-cadena.md"
# shellcheck disable=SC2016 # idem
sed 's/hooks `PreToolUse` en serie/hooks en serie/'  "$SECDOC"        > "$NUTMP/d-muda.md"
# shellcheck disable=SC2016 # idem: es la fila fantasma, con sus backticks de markdown
printf '%s\n' '| `github@claude-plugins-official` | flujos de GitHub | `/plugin` |' \
                                                                      > "$NUTMP/d-fantasma.md"
# La frase retirada, escrita tal como estaba en 03-headroom.md antes de este cambio.
# shellcheck disable=SC2016 # los backticks son los del markdown, literales
printf '%s\n' '`rtk hook claude` se ejecuta antes de cada llamada a Bash. No necesitas escribirlo tu: ya viene en el `settings.json` que instala `install.sh`.' \
                                                                      > "$NUTMP/d-rtk-presente.md"
# Y el contrapeso: la mencion en pasado, que es correcta y NO debe quejarse.
# shellcheck disable=SC2016 # idem
printf '%s\n' 'Hasta el 2026-09-02 el `settings.json` cableaba el hook `rtk hook claude`; se retiro.' \
                                                                      > "$NUTMP/d-rtk-pasado.md"
nu_malos=0
if [ -n "$(rtk_no_cableado "$SETTINGS" "$NUTMP/d-rtk-pasado.md")" ]; then
  nu_malos=$((nu_malos+1)); echo "     (se queja de una mencion en pasado, que es correcta)"
fi
for nu_caso in \
  "cadena_bash $SETTINGS $NUTMP/d-cadena.md" \
  "cadena_bash $SETTINGS $NUTMP/d-muda.md" \
  "cadena_bash $NUTMP/s-mas-rtk.json $SECDOC" \
  "plugins_nombrados $SETTINGS $NUTMP/d-fantasma.md" \
  "plugins_nombrados $NUTMP/s-menos-plugin.json $PLUGDOC" \
  "rtk_no_cableado $NUTMP/s-mas-rtk.json" \
  "rtk_no_cableado $SETTINGS $NUTMP/d-rtk-presente.md"
do
  # shellcheck disable=SC2086 # la palabra es "<comprobador> <fichero...>": se parte a proposito
  [ -n "$($nu_caso)" ] || { nu_malos=$((nu_malos+1)); echo "     (sin queja: $nu_caso)"; }
done
if [ "$nu_malos" -eq 0 ]; then
  echo "ok - falsabilidad: acusa las siete averias fabricadas (la cadena con otra cifra y sin"
  echo "     cifra, un hook de mas en el settings, el plugin fantasma, el plugin retirado del"
  echo "     settings y la frase de rtk en presente) y aprueba la mencion en pasado"
  pass=$((pass+1))
else
  echo "NOT ok - $nu_malos de 8 casos fabricados salieron al reves (tautologia)"
  fail=$((fail+1))
fi
rm -f "$NUTMP"/*; rmdir "$NUTMP"

# --- AGENTS.md: el mapa no puede citar rutas que no existen -----------------
# POR QUE: AGENTS.md es lo primero que lee un agente en varios harness, y su valor
# entero esta en la tabla de rutas. Una ruta que ya no existe no solo manda al agente
# a leer nada: le hace creer que ya lo ha leido. Se comprueban los tokens entre
# backticks que parecen rutas del repo -- se excluyen los que empiezan por '~', '/',
# '$' o '.' (entorno del usuario, absolutas y extensiones sueltas como `.sh`), los que
# llevan espacios (`make test`) y los que llevan glob.
if [ -f AGENTS.md ]; then
  am_malas=0
  am_total=0
  # shellcheck disable=SC2016  # el patron busca backticks LITERALES en AGENTS.md: con
  # comillas dobles la shell intentaria ejecutar lo que hubiera entre ellos.
  while read -r ruta; do
    [ -n "$ruta" ] || continue
    am_total=$((am_total+1))
    if [ ! -e "$ruta" ]; then
      echo "     AGENTS.md cita una ruta que no existe: $ruta"
      am_malas=$((am_malas+1))
    fi
  done <<AM
$(grep -oE '`[^`]+`' AGENTS.md | tr -d '`' \
  | grep -vE '^[~/$.]|[*[:space:]]' \
  | grep -E '/|\.md$' | sort -u)
AM
  if [ "$am_malas" -eq 0 ]; then
    echo "ok - las $am_total rutas que cita AGENTS.md existen todas"; pass=$((pass+1))
  else
    echo "NOT ok - AGENTS.md cita $am_malas rutas inexistentes de $am_total"; fail=$((fail+1))
  fi

  # Falsabilidad del sensor de arriba: si una ruta inventada NO lo pusiera en rojo,
  # el sensor no estaria mirando nada.
  AMTMP=$(mktemp -d)
  # shellcheck disable=SC2016  # idem: el fixture y su patron llevan backticks literales.
  printf 'cita `kit/no/existe/jamas.md` y nada mas\n' > "$AMTMP/AGENTS.md"
  # shellcheck disable=SC2016  # idem: backticks literales en el patron del fixture.
  am_fake=$( (cd "$AMTMP" && grep -oE '`[^`]+`' AGENTS.md | tr -d '`' \
    | grep -vE '^[~/$.]|[*[:space:]]' | grep -E '/|\.md$' \
    | while read -r r; do [ -e "$r" ] || echo malo; done | wc -l) )
  if [ "$am_fake" -eq 1 ]; then
    echo "ok - el sensor de rutas de AGENTS.md detecta una ruta inventada (falsable)"
    pass=$((pass+1))
  else
    echo "NOT ok - una ruta inventada no puso en rojo el sensor de AGENTS.md (tautologia)"
    fail=$((fail+1))
  fi
  rm -f "$AMTMP"/*; rmdir "$AMTMP"
else
  echo "NOT ok - AGENTS.md no existe: el mapa que los harness buscan por ese nombre falta"
  fail=$((fail+1))
fi

if [ "$skipped" -gt 0 ]; then
  echo "== $pass passed, $fail failed, $skipped skipped =="
else
  echo "== $pass passed, $fail failed =="
fi
[ "$fail" -eq 0 ] || exit 1
