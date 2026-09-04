#!/usr/bin/env bash
# test_permisos_efectivos.sh — mide si las reglas de permiso de FICHERO que este
# repo publica hacen algo. Medido en Claude Code 2.1.259: las comprobaciones de
# permisos de fichero SOLO consultan reglas `Edit(ruta)` -- `Edit` ya cubre Write,
# MultiEdit y NotebookEdit --, mientras una regla `Write(ruta)` se acepta como
# valida y despues se IGNORA. El propio binario lo avisa por stderr en cada
# arranque: "... is not matched by file permission checks — only Edit(path) rules
# are".
#
# De ahi los dos fallos que este sensor cierra. Un `ask`/`deny` escrito solo con
# Write() no protege nada y no da error: da una capa que no existe -- paso en
# config/settings.template.json y en .claude/settings.json, los dos con
# `Write(**/settings.json)` en `ask` sin gemela `Edit`. Y al reves, las cinco
# reglas `Write(...)` de kit/claude/settings.json eran peso muerto (todas tenian
# gemela) que soltaba cinco avisos por arranque.
#
# Requiere jq (dependencia dura del kit, ver kit/doctor.sh).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
REPO="$(cd "$KIT/.." && pwd)"
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "FAIL: jq requerido"; echo "PASS=0 FAIL=1"; exit 1; }

cd "$REPO"

KIT_SETTINGS="kit/claude/settings.json"
PLANTILLA="config/settings.template.json"
PROYECTO=".claude/settings.json"

# --- Helpers reutilizados tanto en los checks reales como en la seccion de
# falsabilidad (misma logica, no una copia "de mentira" para el fixture). ---

write_sin_gemela() {   # imprime "bucket|regla" por cada Write() sin Edit() del mismo patron
  jq -r '(.permissions // {}) | to_entries[] | select(.value | type == "array") as $b
         | $b.value[] as $w
         | select($w | startswith("Write("))
         | ("Edit(" + $w[6:]) as $e
         | select(($b.value | index($e)) == null)
         | $b.key + "|" + $w' "$1"
}

echo "== 1) test_write_sin_gemela_edit =="
for f in "$KIT_SETTINGS" "$PLANTILLA" "$PROYECTO"; do
  if [ -f "$f" ]; then
    mapfile -t inertes < <(write_sin_gemela "$f")
    for r in "${inertes[@]:-}"; do
      [ -n "$r" ] && echo "  regla inerte: ${r#*|} en permissions.${r%%|*} -- sin Edit() del mismo patron, no la aplica nadie"
    done
    ck "${#inertes[@]}" "0" "$f: ninguna regla Write() sin gemela Edit() (inertes: ${#inertes[@]})"
  else
    # Los tres settings son invariantes del repo: si uno falta, el check no se ha hecho.
    # Un "check por vacio" verde aqui seria el skip silencioso que hace inerte al sensor.
    ck "n" "y" "$f existe (sin el fichero no hay nada que comprobar)"
  fi
done

echo "== 2) test_sin_consentimiento_prefirmado =="
# `skipAutoPermissionPrompt` es consentimiento prefirmado. Viajaba en el settings que
# install.sh instala en ~/.claude/, o sea que el kit lo firmaba por cada persona que
# lo instala. En un kit cuya tesis son capas que bloquean, eso no puede ser el default.
for f in "$KIT_SETTINGS" "$PLANTILLA" "$PROYECTO"; do
  if [ -f "$f" ]; then
    ck "$(jq -r 'has("skipAutoPermissionPrompt")' "$f")" "false" "$f: no distribuye skipAutoPermissionPrompt"
  else
    # Los tres settings son invariantes del repo: si uno falta, el check no se ha hecho.
    # Un "check por vacio" verde aqui seria el skip silencioso que hace inerte al sensor.
    ck "n" "y" "$f existe (sin el fichero no hay nada que comprobar)"
  fi
done

echo "== 3) test_push_forzado_emparejado_por_algun_glob =="
# La primera version de este check contaba CUANTOS globs `Bash(git push` habia y exigia que la
# plantilla no tuviera menos que el kit. Eso mide un literal, no el comportamiento: se quedaba
# verde con 5 reglas de las que ninguna emparejaba `-uf`, y habria seguido verde si alguien
# añadia una sexta regla inutil. De hecho tapo un error real -- la plantilla recibio
# `Bash(git push -f* *)`, que empareja `-f` y `-fu` pero NO `-uf`, porque el comodin va detras
# de la f; el glob que hace falta es `-*f *`.
# Ahora se emparejan de verdad, con el glob de bash (`[[ $cmd == $patron ]]`), que es la misma
# familia de comodines que usa la capa de permisos. No es el matcher del binario, y se declara:
# lo que este check garantiza es que EXISTE un glob que cubre cada grafia peligrosa.
empareja_algun_deny() {   # $1 fichero, $2 comando; imprime y|n
  local f="$1" cmd="$2" regla
  while IFS= read -r regla; do
    regla="${regla#Bash(}"; regla="${regla%)}"
    # shellcheck disable=SC2053  # el glob es el dato bajo prueba: NO entrecomillar
    [[ $cmd == $regla ]] && { echo y; return; }
  done < <(jq -r '(.permissions.deny // [])[] | select(startswith("Bash(git push"))' "$f")
  echo n
}
# Las dos posiciones (bandera antes y despues del refspec, git acepta las dos) por las
# cuatro grafias de la fuerza: larga, corta suelta, y agrupada con la f al final y no al
# final. Las agrupadas son las que se colaban: `-uf` acaba en f y `-fu` no, asi que hacen
# falta los dos comodines (`-*f` y `-f*`) en cada posicion, y no uno.
PUSH_PELIGROSOS=(
  "git push --force origin main"
  "git push -f origin main"
  "git push -uf origin main"
  "git push -fu origin main"
  "git push origin main --force"
  "git push origin main -f"
  "git push origin main -uf"
  "git push origin main -fu"
)
for f in "$KIT_SETTINGS" "$PLANTILLA" "$PROYECTO"; do
  if [ -f "$f" ]; then
    for cmd in "${PUSH_PELIGROSOS[@]}"; do
      ck "$(empareja_algun_deny "$f" "$cmd")" "y" "$f: algun glob de deny empareja '$cmd'"
    done
  else
    # Los tres settings son invariantes del repo: si uno falta, el check no se ha hecho.
    # Un "check por vacio" verde aqui seria el skip silencioso que hace inerte al sensor.
    ck "n" "y" "$f existe (sin el fichero no hay nada que comprobar)"
  fi
done

echo "== Falsabilidad =="
# Cada check de arriba se ejecuta aqui contra un caso fabricado a proposito para
# demostrar que dispara de verdad, no que siempre pasa.
FTMP="$(mktemp -d)"; trap 'rm -rf "$FTMP"' EXIT
falsified=0

# El fixture lleva una huerfana en `ask` y un par bien formado en `deny`: si el
# detector marcase todo Write() sin mirar la gemela, aqui contaria 2 en vez de 1.
cat > "$FTMP/sin-gemela.json" <<'JSON'
{"permissions":{"ask":["Write(**/settings.json)"],"deny":["Write(/hooks/**)","Edit(/hooks/**)"]}}
JSON
mapfile -t f_inertes < <(write_sin_gemela "$FTMP/sin-gemela.json")
if [ "${#f_inertes[@]}" -eq 1 ]; then
  ck "y" "y" "el check 1 SI detecta el ask Write() sin gemela fabricado, y NO marca el par deny bien formado"
  falsified=$((falsified + 1))
else
  ck "n" "y" "el check 1 SI detecta el ask Write() sin gemela fabricado, y NO marca el par deny bien formado (detectadas: ${#f_inertes[@]})"
fi

printf '%s\n' '{"skipAutoPermissionPrompt": true}' > "$FTMP/con-skip.json"
if [ "$(jq -r 'has("skipAutoPermissionPrompt")' "$FTMP/con-skip.json")" = "true" ]; then
  ck "y" "y" "el check 2 SI detecta un settings con skipAutoPermissionPrompt fabricado"
  falsified=$((falsified + 1))
else
  ck "n" "y" "el check 2 SI detecta un settings con skipAutoPermissionPrompt fabricado"
fi

# Fabricado a partir del propio kit quitandole EXACTAMENTE los dos globs de banderas
# agrupadas: el resto de reglas de push siguen ahi, asi que un check por recuento seguiria
# viendo 8 de 10 y podria darlo por bueno. El de comportamiento tiene que ponerse rojo
# justo en `-uf`, que es la grafia que ningun glob restante cubre, y seguir verde en `-f`,
# que si cubren. Si no distinguiese las dos, seria el sensor que este check reemplazo.
jq '.permissions.deny |= map(select(. != "Bash(git push -*f *)" and . != "Bash(git push * -*f)"))' \
  "$KIT_SETTINGS" > "$FTMP/kit-sin-agrupadas.json"
f_uf="$(empareja_algun_deny "$FTMP/kit-sin-agrupadas.json" "git push -uf origin main")"
f_f="$(empareja_algun_deny "$FTMP/kit-sin-agrupadas.json" "git push -f origin main")"
if [ "$f_uf" = "n" ] && [ "$f_f" = "y" ]; then
  ck "y" "y" "el check 3 SI se pone rojo en '-uf' al quitar los globs de banderas agrupadas, y sigue verde en '-f'"
  falsified=$((falsified + 1))
else
  ck "n" "y" "el check 3 SI se pone rojo en '-uf' al quitar los globs de banderas agrupadas, y sigue verde en '-f' (-uf=$f_uf, -f=$f_f)"
fi

ck "$([ "$falsified" -eq 3 ] && echo y || echo n)" "y" "los 3 checks demuestran deteccion real sobre casos fabricados (detectados: $falsified de 3) -- si fuera 0, la suite seria decorativa"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
