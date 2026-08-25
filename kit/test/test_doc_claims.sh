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
pass=0; fail=0

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

echo "== $pass passed, $fail failed =="
[ "$fail" -eq 0 ] || exit 1
