#!/usr/bin/env bash
# test_uninstall.sh — uninstall.sh (raiz del repo) restaura el backup mas
# reciente, soportando los dos origenes que produce este kit: los backups
# internos de kit/install.sh y los ZIP de scripts/backup.sh.
#
# --dry-run (el modo por defecto) nunca toca nada -- se comprueba con un
# checksum del directorio antes/despues, no solo "mirando" la salida.
# --apply restaura de verdad. La falsabilidad la aporta el caso del ZIP con
# checksum invalido: si uninstall.sh no verificara nada, este caso pasaria.
#
# Cada caso usa su propio HOME temporal (no solo CLAUDE_HOME): uninstall.sh
# delega en scripts/backup.sh para su backup de seguridad, y ese script usa
# mas rutas derivadas de $HOME (BUCLE_DIR, CLAUDE_JSON) que hay que aislar
# para no arrastrar estado real de la maquina a un test.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$HERE/../.."
UNINSTALL="$REPO/uninstall.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

# Checksum recursivo de un directorio: contenido + rutas relativas.
tree_checksum() {
  ( cd "$1" && find . -type f -exec sha256sum {} + | LC_ALL=C sort | sha256sum | cut -d' ' -f1 )
}

# ---------------------------------------------------------- entorno comun
setup_home() {  # $1 = nombre del HOME temporal
  local h="$tmp/$1"
  mkdir -p "$h"
  printf '%s\n' "$h"
}

# ================================================== Caso 1: --list ========
H1="$(setup_home home1)"
export HOME="$H1" CLAUDE_HOME="$H1/.claude" BACKUP_DIR="$H1/backups"
out_empty="$(bash "$UNINSTALL" --list 2>&1)"
ck "$(echo "$out_empty" | grep -qic 'no hay backups' && echo y || echo n)" "y" "--list sin backups lo dice con claridad"

bash "$REPO/kit/install.sh" >/dev/null 2>&1
# Testigo: .gitleaks.toml y no CLAUDE.md. CLAUDE.md son TUS instrucciones y desde ahora
# install.sh no la pisa, asi que ya no genera backup interno (deja CLAUDE.kit.md al lado).
echo "MODIFICADO" >> "$CLAUDE_HOME/.gitleaks.toml"
bash "$REPO/kit/install.sh" >/dev/null 2>&1   # genera un backup interno

out_list="$(bash "$UNINSTALL" --list 2>&1)"
ck "$(echo "$out_list" | grep -qc '^internal' && echo y || echo n)" "y" "--list enumera el backup interno con su tipo"
ck "$(echo "$out_list" | grep -Eqc '[0-9]{4}-[0-9]{2}-[0-9]{2}' && echo y || echo n)" "y" "--list muestra una fecha legible"
ck "$(echo "$out_list" | grep -Eqc '[0-9]+(B|KiB|MiB)' && echo y || echo n)" "y" "--list muestra un tamano legible"

# ============================================ Caso 2: --dry-run no toca nada
before="$(tree_checksum "$H1")"
out_dry="$(bash "$UNINSTALL" --dry-run 2>&1)"
after="$(tree_checksum "$H1")"
ck "$before" "$after" "--dry-run no modifica nada (checksum del arbol identico antes/despues)"
ck "$(echo "$out_dry" | grep -qic 'dry-run' && echo y || echo n)" "y" "--dry-run lo deja explicito en la salida"
ck "$(echo "$out_dry" | grep -qic -- '--apply' && echo y || echo n)" "y" "--dry-run indica como restaurar de verdad"

# Sin argumentos == --dry-run (el modo por defecto)
before2="$(tree_checksum "$H1")"
bash "$UNINSTALL" >/dev/null 2>&1
after2="$(tree_checksum "$H1")"
ck "$before2" "$after2" "sin argumentos (modo por defecto) tampoco modifica nada"

# El backup interno mas reciente contiene el .gitleaks.toml de ANTES de la 2a
# instalacion (kit + "MODIFICADO"): eso es lo que --apply debe traer de
# vuelta, no el contenido actual (que ya es el kit "limpio" tras esa 2a
# instalacion).
latest_backup_dir="$(find "$CLAUDE_HOME/backups" -mindepth 1 -maxdepth 1 -type d | LC_ALL=C sort | tail -1)"
expected_restore="$(cat "$latest_backup_dir/.gitleaks.toml")"
bash "$UNINSTALL" --apply >/tmp/uninstall_apply_out.$$.log 2>&1
apply_rc=$?
ck "$apply_rc" "0" "--apply sale con exit 0"
after_restore="$(cat "$CLAUDE_HOME/.gitleaks.toml")"
ck "$([ "$expected_restore" = "$after_restore" ] && echo mismo || echo distinto)" "mismo" \
  "--apply restaura el .gitleaks.toml del backup interno mas reciente (contenido MODIFICADO)"
ck "$(find "$BACKUP_DIR" -maxdepth 1 -name 'claude-safety-*.zip' 2>/dev/null | wc -l | tr -d ' ')" "1" \
  "--apply hizo primero su propio backup de seguridad (ZIP en BACKUP_DIR)"
ck "$(find "$BACKUP_DIR" -maxdepth 1 -name 'claude-state-*.zip' 2>/dev/null | wc -l | tr -d ' ')" "0" \
  "el ZIP de seguridad no usa el nombre de los backups periodicos (no compite con ellos)"

# Doble --apply: la 2a ejecucion no debe restaurar el ZIP de seguridad de la 1a (estado ANTERIOR a la restauracion).
echo "ESTROPEADO" > "$CLAUDE_HOME/.gitleaks.toml"
bash "$UNINSTALL" --apply >/dev/null 2>&1
ck "$([ "$(cat "$CLAUDE_HOME/.gitleaks.toml")" = "$expected_restore" ] && echo mismo || echo distinto)" "mismo" \
  "un segundo --apply restaura otra vez el backup interno, no el ZIP de seguridad del primero"
ck "$(bash "$UNINSTALL" --dry-run 2>&1 | grep -c 'backup interno de install.sh')" "1" \
  "--dry-run sin --from elige un backup interno aunque haya ZIP mas recientes"
rm -f "/tmp/uninstall_apply_out.$$.log"

# ============================================ Caso 4: ZIP de scripts/backup.sh
H2="$(setup_home home2)"
export HOME="$H2" CLAUDE_HOME="$H2/.claude" BACKUP_DIR="$H2/backups"
bash "$REPO/kit/install.sh" >/dev/null 2>&1
# Fija el reloj de ambos backups al mismo segundo. El PID y $RANDOM, como en
# install.sh, deben bastar para que el backup previo de --apply no colisione.
date() {
  if [ "$#" -eq 2 ] && [ "$1" = "-u" ] && [ "$2" = "+%Y%m%dT%H%M%SZ" ]; then
    printf '%s\n' "20000101T000000Z"
  elif [ "$#" -eq 1 ] && [ "$1" = "+%Y%m%d-%H%M%S" ]; then
    printf '%s\n' "20000101-000000"
  else
    command date "$@"
  fi
}
export -f date
ck "$(date -u +%Y%m%dT%H%M%SZ)" "20000101T000000Z" "el caso ZIP fija ambos backups al mismo segundo"
bash "$REPO/scripts/backup.sh" >/dev/null 2>&1
ZIP1="$(find "$BACKUP_DIR" -maxdepth 1 -name 'claude-state-*.zip' | head -1)"
echo "SERA_SOBREESCRITO" >> "$CLAUDE_HOME/CLAUDE.md"

set +e
out_nofrom="$(bash "$UNINSTALL" --apply 2>&1)"; rc_nofrom=$?
set -e
ck "$rc_nofrom" "1" "sin backup interno, --apply NO restaura un ZIP por ser el mas reciente"
ck "$(echo "$out_nofrom" | grep -c -- '--from')" "1" "el error indica --from FICHERO"
ck "$(grep -c SERA_SOBREESCRITO "$CLAUDE_HOME/CLAUDE.md" || true)" "1" "esa negativa no toco nada"

out_dry_zip="$(bash "$UNINSTALL" --dry-run --from "$ZIP1" 2>&1)"
ck "$(echo "$out_dry_zip" | grep -qc '^zip$\|zip de scripts/backup.sh\|snapshot ZIP' && echo y || echo n)" "y" \
  "--dry-run identifica el origen ZIP cuando es el backup mas reciente"
ck "$(grep -qc SERA_SOBREESCRITO "$CLAUDE_HOME/CLAUDE.md" && echo y || echo n)" "y" "--dry-run (con ZIP) no toco el fichero real"

set +e
bash "$UNINSTALL" --apply --from "$ZIP1" >/dev/null 2>&1
apply_zip_rc=$?
set -e
unset -f date
ck "$apply_zip_rc" "0" "--apply (ZIP) sale con exit 0 aunque ambos backups comparten reloj"
ck "$(find "$BACKUP_DIR" -maxdepth 1 -name 'claude-s*-20000101T000000Z-*.zip' | wc -l | tr -d ' ')" "2" \
  "--apply conserva dos backups distintos creados en el mismo segundo"
ck "$(grep -qc SERA_SOBREESCRITO "$CLAUDE_HOME/CLAUDE.md" 2>/dev/null; echo $?)" "1" \
  "--apply (ZIP) restauro sobre el cambio no respaldado"

# ============================================ Caso 5: falsabilidad — ZIP con
# checksum invalido debe rechazarse (si esto pasara, la verificacion seria
# decorativa, como comprueba test_gitattributes.sh / test_exec_modes.sh con
# sus propios casos fabricados).
H3="$(setup_home home3)"
export HOME="$H3" CLAUDE_HOME="$H3/.claude" BACKUP_DIR="$H3/backups"
mkdir -p "$CLAUDE_HOME" "$BACKUP_DIR"
stage="$tmp/stage-bad"
mkdir -p "$stage/claude-state-bad/claude"
echo "hola" > "$stage/claude-state-bad/claude/CLAUDE.md"
echo "0000000000000000000000000000000000000000000000000000000000000  claude/CLAUDE.md" \
  > "$stage/claude-state-bad/MANIFEST.sha256"
( cd "$stage" && zip -qr "$BACKUP_DIR/claude-state-bad.zip" claude-state-bad )

set +e
out_bad="$(bash "$UNINSTALL" --dry-run --from "$BACKUP_DIR/claude-state-bad.zip" 2>&1)"; rc_bad=$?
set -e
ck "$rc_bad" "1" "ZIP con checksum invalido: uninstall.sh NO restaura, sale con exit distinto de 0"
ck "$(echo "$out_bad" | grep -qic 'checksum' && echo y || echo n)" "y" "el motivo del rechazo se explica (checksum)"

# ==================================== Caso 6: el .claude.json de $HOME no se toca
# uninstall.sh restauraba el claude.json del backup en un "$HOME/.claude.json" literal,
# el unico sitio del script que no honraba $CLAUDE_HOME: probarlo con un CLAUDE_HOME
# temporal pisaba el .claude.json REAL de quien lo ejecutaba con una copia de semanas
# atras. Aqui HOME y CLAUDE_HOME son temporales DISTINTOS (la forma exacta del fallo, y
# la razon de que este caso sea seguro de correr) y lo que se mide es que el .claude.json
# de $HOME sigue byte a byte igual.
H4="$(setup_home home4)"
CH4="$tmp/claude-home4"; mkdir -p "$CH4"
export HOME="$H4" CLAUDE_HOME="$CH4" BACKUP_DIR="$tmp/backups4"
printf '{"proyectos":"los de verdad"}\n' > "$H4/.claude.json"
json_before="$(sha256sum "$H4/.claude.json" | cut -d' ' -f1)"

stage_json="$tmp/stage-json/claude-state-json"
mkdir -p "$stage_json/claude" "$BACKUP_DIR"
echo "del backup" > "$stage_json/claude/CLAUDE.md"
printf '{"proyectos":"los del backup"}\n' > "$stage_json/claude.json"
( cd "$stage_json" && find . -type f -exec sha256sum {} + ) > "$tmp/manifest-json"
mv "$tmp/manifest-json" "$stage_json/MANIFEST.sha256"
( cd "$tmp/stage-json" && zip -qr "$BACKUP_DIR/claude-state-json.zip" claude-state-json )

bash "$UNINSTALL" --apply --from "$BACKUP_DIR/claude-state-json.zip" >/dev/null 2>&1
ck "$(sha256sum "$H4/.claude.json" | cut -d' ' -f1)" "$json_before" \
  "--apply con un CLAUDE_HOME temporal NO toca el .claude.json de \$HOME"
ck "$(cat "$tmp/.claude.json" 2>/dev/null || echo ausente)" '{"proyectos":"los del backup"}' \
  "--apply restaura el claude.json del backup al lado de \$CLAUDE_HOME"


# H8: la memoria (projects/*/memory/) viaja en el ZIP aunque projects/ se excluya; los transcripts no.
H5="$(setup_home home5)"
export HOME="$H5" CLAUDE_HOME="$H5/.claude" BACKUP_DIR="$H5/backups"
mkdir -p "$CLAUDE_HOME/projects/-x/memory" "$CLAUDE_HOME/projects/-x/sesion"
echo "recuerdo" > "$CLAUDE_HOME/projects/-x/memory/a.md"
echo "{}" > "$CLAUDE_HOME/projects/-x/abc.jsonl"
echo "x" > "$CLAUDE_HOME/projects/-x/sesion/t.txt"
echo "cfg" > "$CLAUDE_HOME/settings.json"
bash "$REPO/scripts/backup.sh" >/dev/null 2>&1
Z5="$(find "$BACKUP_DIR" -maxdepth 1 -name 'claude-state-*.zip' | head -1)"
ck "$(unzip -Z1 "$Z5" | grep -c 'claude/projects/-x/memory/a.md$')" "1" "H8: backup.sh incluye projects/*/memory/"
ck "$(unzip -Z1 "$Z5" | grep -c 'abc.jsonl$\|sesion/t.txt$')" "0" "H8: los transcripts siguen fuera"

# H19c: un enlace simbolico a directorio (skill proyectada) se guarda como enlace, no como copia del repo ajeno.
mkdir -p "$tmp/repo-ajeno" "$CLAUDE_HOME/skills"; echo s > "$tmp/repo-ajeno/SKILL.md"
ln -s "$tmp/repo-ajeno" "$CLAUDE_HOME/skills/proyectada"
bash "$REPO/scripts/backup.sh" >/dev/null 2>&1
Z6="$(find "$BACKUP_DIR" -maxdepth 1 -name 'claude-state-*.zip' -newer "$Z5" | head -1)"
ck "$(unzip -Z1 "$Z6" | grep -c 'skills/proyectada/SKILL.md$')" "0" "H19c: zip -y guarda el enlace, no el contenido del directorio apuntado"

# Restauracion: las entradas regulares sustituyen enlaces, sin escribir fuera.
# Ambos origenes recorren rutas de copia distintas. El rollback usa el ZIP real.
for route in internal zip; do
  for target in file dangling directory; do
    H="$(setup_home "link-$route-$target")"
    export HOME="$H" CLAUDE_HOME="$H/.claude" BACKUP_DIR="$H/backups"
    source_dir="$H/seleccion ' con espacios"; mkdir -p "$source_dir" "$CLAUDE_HOME" "$BACKUP_DIR"
    echo elegido > "$source_dir/settings.json"
    source="$source_dir"
    if [ "$route" = zip ]; then
      CLAUDE_HOME="$source_dir" bash "$REPO/scripts/backup.sh" >"$H/snapshot.log" 2>&1
      source="$(find "$BACKUP_DIR" -name 'claude-state-*.zip' -print -quit)"
      mv "$source" "$H/seleccion ' con espacios.zip"; source="$H/seleccion ' con espacios.zip"
    fi
    external="$H/ajeno"
    case "$target" in
      file) echo anterior > "$external" ;;
      directory)
        mkdir -p "$external"; echo anterior > "$external/testigo"
        external_before="$(tree_checksum "$external")" ;;
    esac
    ln -s "$external" "$CLAUDE_HOME/settings.json"
    # Un fichero independiente exige que el rollback recupere tambien bytes.
    echo anterior > "$CLAUDE_HOME/CLAUDE.md"
    outside_before="$(tree_checksum "$H")"
    out="$(bash "$UNINSTALL" --dry-run --from "$source" 2>&1)"
    ck "$(tree_checksum "$H")" "$outside_before" "$route/$target: dry-run no cambia bytes"
    rc=0; bash "$UNINSTALL" --apply --from "$source" >"$H/apply.log" 2>&1 || rc=$?
    ck "$rc" "0" "$route/$target: restaura el origen explicito"
    ck "$(cat "$CLAUDE_HOME/settings.json" 2>/dev/null || true)" "elegido" "$route/$target: restaura exactamente el origen elegido"
    ck "$([ -L "$CLAUDE_HOME/settings.json" ] && echo enlace || echo regular)" "regular" "$route/$target: sustituye el enlace de destino"
    case "$target" in
      file) ck "$(cat "$external")" "anterior" "$route/$target: bytes ajenos intactos" ;;
      directory) ck "$(tree_checksum "$external")" "$external_before" "$route/$target: directorio ajeno intacto" ;;
      dangling) ck "$([ -e "$external" ] && echo existe || echo ausente)" "ausente" "$route/$target: no crea el destino del enlace roto" ;;
    esac
    safety="$(find "$BACKUP_DIR" -name 'claude-safety-*.zip' -print -quit)"
    echo posterior > "$CLAUDE_HOME/CLAUDE.md"
    rc=0; bash "$UNINSTALL" --apply --from "$safety" >"$H/rollback.log" 2>&1 || rc=$?
    ck "$rc" "0" "$route/$target: rollback desde el ZIP de seguridad"
    ck "$(readlink "$CLAUDE_HOME/settings.json" || true)" "$external" "$route/$target: rollback recupera la topologia anterior"
    ck "$(cat "$CLAUDE_HOME/CLAUDE.md")" "anterior" "$route/$target: rollback recupera los bytes anteriores"
  done
done

# La orden de dry-run fija la seleccion aunque exista otro backup por defecto.
for route in internal zip; do
  H="$(setup_home "suggested-$route")"
  export HOME="$H" CLAUDE_HOME="$H/.claude" BACKUP_DIR="$H/backups"
  source_dir="$H/seleccion ' con espacios"
  mkdir -p "$source_dir" "$CLAUDE_HOME/backups/otro" "$BACKUP_DIR"
  echo elegido > "$source_dir/settings.json"
  echo otro > "$CLAUDE_HOME/backups/otro/settings.json"
  source="$source_dir"
  if [ "$route" = zip ]; then
    CLAUDE_HOME="$source_dir" bash "$REPO/scripts/backup.sh" >"$H/snapshot.log" 2>&1
    source="$(find "$BACKUP_DIR" -name 'claude-state-*.zip' -print -quit)"
    mv "$source" "$H/seleccion ' con espacios.zip"; source="$H/seleccion ' con espacios.zip"
  fi
  out="$(bash "$UNINSTALL" --dry-run --from "$source" 2>&1)"
  suggested="$(printf '%s\n' "$out" | awk '/^Para restaurar de verdad:/ {sub(/^Para restaurar de verdad: */, ""); print}')"
  rc=0; bash -c "$suggested" >"$H/suggested.log" 2>&1 || rc=$?
  ck "$rc" "0" "$route: orden sugerida valida para Bash"
  ck "$(cat "$CLAUDE_HOME/settings.json" 2>/dev/null || true)" "elegido" "$route: orden sugerida conserva --from con comillas y espacios"
done

# El JSON global es estado previo incluso sin ficheros en CLAUDE_HOME.
for home_state in empty missing; do
  for json_state in regular link opaque dangling absent; do
    H="$(setup_home "json-$home_state-$json_state")"
    export HOME="$H" CLAUDE_HOME="$H/.claude" BACKUP_DIR="$H/backups"
    source_dir="$H/source"; mkdir -p "$source_dir" "$BACKUP_DIR"
    echo nuevo > "$H/nuevo.json"
    # Snapshot sin ningun fichero en claude/: el unico contenido es global.
    CLAUDE_HOME="$source_dir" CLAUDE_JSON="$H/nuevo.json" bash "$REPO/scripts/backup.sh" >"$H/snapshot.log" 2>&1
    source="$(find "$BACKUP_DIR" -name 'claude-state-*.zip' -print -quit)"
    if [ "$home_state" = empty ]; then mkdir -p "$CLAUDE_HOME"; fi
    case "$json_state" in
      regular) echo anterior > "$H/.claude.json" ;;
      link|opaque)
        target=externo.json
        [ "$json_state" != opaque ] || target=$'opaco-\xff\n'
        echo anterior > "$H/$target"; ln -s "$target" "$H/.claude.json"
        link_before="$(readlink -n "$H/.claude.json" | base64 -w0)" ;;
      dangling) ln -s inexistente.json "$H/.claude.json" ;;
    esac
    rc=0; bash "$UNINSTALL" --apply --from "$source" >"$H/apply.log" 2>&1 || rc=$?
    ck "$rc" "0" "$home_state/$json_state: restaura JSON global"
    ck "$(cat "$H/.claude.json" 2>/dev/null || true)" "nuevo" "$home_state/$json_state: JSON elegido restaurado"
    expected_type=regular
    case "$json_state" in link|opaque) expected_type=enlace ;; esac
    ck "$([ -L "$H/.claude.json" ] && echo enlace || echo regular)" "$expected_type" "$home_state/$json_state: conserva un alias global valido"
    case "$json_state" in
      link|opaque)
        ck "$(readlink -n "$H/.claude.json" | base64 -w0)" "$link_before" "$home_state/$json_state: conserva los bytes del destino del alias"
        ck "$(cat "$H/$target")" "nuevo" "$home_state/$json_state: restaura el destino global respaldado" ;;
    esac
    safety="$(find "$BACKUP_DIR" -name 'claude-safety-*.zip' -print -quit)"
    if [ "$json_state" = absent ]; then
      ck "$safety" "" "$home_state/$json_state: no crea backup de una instalacion realmente vacia"
    else
      ck "$([ -n "$safety" ] && echo existe || echo ausente)" "existe" "$home_state/$json_state: el JSON anterior tiene backup"
      rc=0; bash "$UNINSTALL" --apply --from "$safety" >"$H/rollback.log" 2>&1 || rc=$?
      ck "$rc" "0" "$home_state/$json_state: rollback del JSON global"
      case "$json_state" in
        regular) ck "$(cat "$H/.claude.json" 2>/dev/null || true)" "anterior" "$home_state/$json_state: recupera JSON anterior" ;;
        link|opaque)
          ck "$(readlink -n "$H/.claude.json" | base64 -w0)" "$link_before" "$home_state/$json_state: recupera enlace relativo global"
          ck "$(cat "$H/$target")" "anterior" "$home_state/$json_state: JSON externo recuperado" ;;
        dangling)
          ck "$(readlink "$H/.claude.json" || true)" "inexistente.json" "$home_state/$json_state: recupera enlace global roto"
          ck "$([ -e "$H/inexistente.json" ] && echo existe || echo ausente)" "ausente" "$home_state/$json_state: destino roto sigue ausente" ;;
      esac
    fi
  done
done

# Un backup periodico de un JSON enlazado incluye sus bytes, portables a otro HOME.
H="$(setup_home portable-json)"
export HOME="$H" CLAUDE_HOME="$H/.claude" BACKUP_DIR="$H/backups"
mkdir -p "$CLAUDE_HOME" "$H/dot"
echo JSON-PORTABLE > "$H/dot/config.json"; ln -s dot/config.json "$H/.claude.json"
bash "$REPO/scripts/backup.sh" >"$H/backup.log" 2>&1
source="$(find "$BACKUP_DIR" -name 'claude-state-*.zip' -print -quit)"
mkdir "$H/extraido"; unzip -q "$source" -d "$H/extraido"
snapshot="$(find "$H/extraido" -mindepth 1 -maxdepth 1 -type d -print -quit)"
ck "$([ -f "$snapshot/claude.json" ] && [ ! -L "$snapshot/claude.json" ] && echo regular || echo no)" "regular" "portable: el ZIP contiene un JSON regular"
ck "$(cat "$snapshot/claude.json" 2>/dev/null || true)" "JSON-PORTABLE" "portable: el ZIP contiene los bytes del JSON enlazado"
ck "$(grep -Fc './claude.json' "$snapshot/MANIFEST.sha256" || true)" "1" "portable: el manifiesto cubre esos bytes"
rc=0; HOME="$H/otro" CLAUDE_HOME="$H/otro/.claude" BACKUP_DIR="$H/otro/backups" \
  bash "$UNINSTALL" --apply --from "$source" >"$H/otro.log" 2>&1 || rc=$?
ck "$rc" "0" "portable: restaura en otro HOME sin el directorio de dotfiles"
ck "$(cat "$H/otro/.claude.json" 2>/dev/null || true)" "JSON-PORTABLE" "portable: el receptor recupera el contenido global"

# Las operaciones sobre una entrada conservan su tipo al deshacerse, incluso
# si el enlace del snapshot pasa a resolver en la maquina que lo restaura.
for transition in link-to-dangling opaque-link-to-dangling file-to-live-link; do
  H="$(setup_home "entry-$transition")"
  export HOME="$H" CLAUDE_HOME="$H/.claude" BACKUP_DIR="$H/backups"
  mkdir -p "$CLAUDE_HOME" "$H/source-home/.claude"
  ln -s destino.json "$H/source-home/.claude.json"
  CLAUDE_HOME="$H/source-home/.claude" CLAUDE_JSON="$H/source-home/.claude.json" \
    bash "$REPO/scripts/backup.sh" >"$H/snapshot.log" 2>&1
  source="$(find "$BACKUP_DIR" -name 'claude-state-*.zip' -print -quit)"
  echo AJENO > "$H/externo.json"
  if [ "$transition" != file-to-live-link ]; then
    entry_target=externo.json
    [ "$transition" != opaque-link-to-dangling ] || entry_target=$'opaco-\xff\n'
    echo AJENO > "$H/$entry_target"; ln -s "$entry_target" "$H/.claude.json"
    entry_link_before="$(readlink -n "$H/.claude.json" | base64 -w0)"
  else
    echo ANTERIOR > "$H/.claude.json"; echo AJENO > "$H/destino.json"
  fi
  rc=0; bash "$UNINSTALL" --apply --from "$source" >"$H/apply.log" 2>&1 || rc=$?
  ck "$rc" "0" "$transition: aplica el enlace como entrada"
  ck "$(readlink "$H/.claude.json" || true)" "destino.json" "$transition: conserva el enlace del snapshot"
  safety="$(find "$BACKUP_DIR" -name 'claude-safety-*.zip' -print -quit)"
  rc=0; bash "$UNINSTALL" --apply --from "$safety" >"$H/rollback.log" 2>&1 || rc=$?
  ck "$rc" "0" "$transition: rollback de la sustitucion de entrada"
  if [ "$transition" != file-to-live-link ]; then
    ck "$(readlink -n "$H/.claude.json" | base64 -w0)" "$entry_link_before" "$transition: recupera los bytes del alias anterior"
    ck "$(cat "$H/$entry_target")" "AJENO" "$transition: conserva los bytes del destino del alias"
  else
    ck "$([ -L "$H/.claude.json" ] && echo enlace || echo regular)" "regular" "$transition: recupera la entrada regular anterior"
    ck "$(cat "$H/.claude.json")" "ANTERIOR" "$transition: recupera los bytes anteriores"
    ck "$(cat "$H/destino.json")" "AJENO" "$transition: no escribe a traves del enlace sobrevenido"
  fi
  ck "$(cat "$H/externo.json")" "AJENO" "$transition: no toca el destino ajeno de la entrada"
  second_safety="$(find "$BACKUP_DIR" -name 'claude-safety-*.zip' ! -path "$safety" -print -quit)"
  rc=0; bash "$UNINSTALL" --apply --from "$second_safety" >"$H/rollback-segundo.log" 2>&1 || rc=$?
  ck "$rc" "0" "$transition: el rollback tambien tiene respaldo util"
  ck "$(readlink "$H/.claude.json" || true)" "destino.json" "$transition: segunda vuelta recupera el tipo y enlace intermedios"
done

# Un registro de entrada invalido no puede convertirse en una restauracion
# ordinaria por omision. Se rechaza antes de tocar el arbol o el JSON global.
for invalid in uncovered unicode-coverage unknown bad64 empty-target nul-target multiple symlink-record file-with-link-payload uncovered-payload; do
  H="$(setup_home "invalid-entry-$invalid")"
  export HOME="$H" CLAUDE_HOME="$H/.claude" BACKUP_DIR="$H/backups"
  snapshot="$H/snapshot/estado"
  mkdir -p "$snapshot/claude" "$CLAUDE_HOME"
  echo NUEVO > "$snapshot/claude/settings.json"; echo NUEVO > "$snapshot/claude.json"
  record='{"type":"file"}'
  case "$invalid" in
    unknown) record='{"type":"desconocido"}' ;;
    bad64) record='{"type":"link","target_b64":"%%%"}' ;;
    empty-target) record='{"type":"link","target_b64":""}' ;;
    nul-target) record='{"type":"link","target_b64":"YQBi"}' ;;
    multiple) record=$'{"type":"file"}\n{"type":"file"}' ;;
  esac
  if [ "$invalid" = symlink-record ]; then
    printf '%s\n' "$record" >"$H/record.json"
    ln -s "$H/record.json" "$snapshot/.claude-json-entry.json"
  else
    printf '%s\n' "$record" >"$snapshot/.claude-json-entry.json"
  fi
  if [ "$invalid" = file-with-link-payload ]; then
    mv "$snapshot/claude.json" "$snapshot/payload.json"
    ln -s payload.json "$snapshot/claude.json"
  fi
  if [ "$invalid" = unicode-coverage ]; then
    fake_dir=$'nombre\xc2\x85'"$(printf '%064d' 0)  ."
    mkdir "$snapshot/$fake_dir"
    echo OTRO >"$snapshot/$fake_dir/.claude-json-entry.json"
  fi
  (
    cd "$snapshot"
    find . -type f -print0 | LC_ALL=C sort -z |
      while IFS= read -r -d '' f; do
        [ "$invalid:$f" != uncovered:./.claude-json-entry.json ] || continue
        [ "$invalid:$f" != unicode-coverage:./.claude-json-entry.json ] || continue
        [ "$invalid:$f" != uncovered-payload:./claude.json ] || continue
        sha256sum "$f"
      done >"$H/manifest"
    mv "$H/manifest" MANIFEST.sha256
    cd ..; zip -qry "$H/source.zip" estado
  )
  echo ANTERIOR > "$CLAUDE_HOME/settings.json"; echo ANTERIOR > "$H/.claude.json"
  before="$(tree_checksum "$CLAUDE_HOME")"
  mkdir "$H/tmp"
  rc=0; TMPDIR="$H/tmp" bash "$UNINSTALL" --dry-run --from "$H/source.zip" >"$H/plan.log" 2>&1 || rc=$?
  ck "$rc" "1" "$invalid: el plan tambien rechaza el registro invalido"
  ck "$([ -d "$H/tmp" ] && find "$H/tmp" -mindepth 1 | wc -l || echo ausente)" "0" "$invalid: el plan elimina su extraccion temporal"
  rc=0; bash "$UNINSTALL" --apply --from "$H/source.zip" >"$H/apply.log" 2>&1 || rc=$?
  ck "$rc" "1" "$invalid: rechaza el registro de entrada invalido"
  ck "$(tree_checksum "$CLAUDE_HOME")" "$before" "$invalid: rechazo antes de escribir el arbol"
  ck "$(cat "$H/.claude.json")" "ANTERIOR" "$invalid: rechazo antes de escribir el JSON"
done

# La raiz elegida explicitamente puede estar enlazada: se restaura su contenido
# conservando el alias y el JSON junto a la ruta elegida, no junto a su destino.
for route in internal zip; do
  for topology in root ancestor; do
    for json_state in present absent; do
      H="$(setup_home "alias-$route-$topology-$json_state")"
      physical="$H/dotfiles/config"; mkdir -p "$physical" "$H/source" "$H/backups"
      if [ "$topology" = root ]; then
        alias="$H/.claude"; ln -s "$physical" "$alias"
        export HOME="$H" CLAUDE_HOME="$alias"
      else
        alias="$H/alias"; ln -s "$H/dotfiles" "$alias"
        export HOME="$alias" CLAUDE_HOME="$alias/config"
      fi
      export BACKUP_DIR="$H/backups"
      alias_before="$(readlink "$alias")"
      global_json="$(dirname "$CLAUDE_HOME")/.claude.json"
      echo anterior > "$physical/settings.json"
      echo conservar > "$physical/CLAUDE.md"
      if [ "$topology" = root ]; then echo ajeno > "$H/dotfiles/.claude.json"; fi
      if [ "$json_state" = present ]; then echo anterior > "$global_json"; fi
      echo elegido > "$H/source/settings.json"; echo elegido > "$H/nuevo.json"
      source="$H/source"
      if [ "$route" = zip ]; then
        CLAUDE_HOME="$source" CLAUDE_JSON="$H/nuevo.json" bash "$REPO/scripts/backup.sh" >"$H/snapshot.log" 2>&1
        source="$(find "$BACKUP_DIR" -name 'claude-state-*.zip' -print -quit)"
      fi
      rc=0; bash "$UNINSTALL" --apply --from "$source" >"$H/apply.log" 2>&1 || rc=$?
      ck "$rc" "0" "$route/$topology/$json_state: restaura una raiz explicitamente enlazada"
      ck "$(cat "$physical/settings.json")" "elegido" "$route/$topology/$json_state: escribe en la raiz fisica elegida"
      ck "$(readlink "$alias" || true)" "$alias_before" "$route/$topology/$json_state: conserva el alias"
      ck "$(cat "$physical/CLAUDE.md")" "conservar" "$route/$topology/$json_state: conserva entradas fuera del snapshot"
      if [ "$route" = zip ]; then
        ck "$(cat "$global_json" 2>/dev/null || true)" "elegido" "$route/$topology/$json_state: JSON junto a la ruta elegida"
      fi
      if [ "$topology" = root ]; then
        ck "$(cat "$H/dotfiles/.claude.json")" "ajeno" "$route/$topology/$json_state: no confunde el JSON de la raiz fisica"
      fi
      safety="$(find "$BACKUP_DIR" -name 'claude-safety-*.zip' -print -quit)"
      ck "$([ -n "$safety" ] && echo existe || echo ausente)" "existe" "$route/$topology/$json_state: respalda el contenido real"
      rc=0; bash "$UNINSTALL" --apply --from "$safety" >"$H/rollback.log" 2>&1 || rc=$?
      ck "$rc" "0" "$route/$topology/$json_state: rollback disponible"
      ck "$(cat "$physical/settings.json")" "anterior" "$route/$topology/$json_state: rollback recupera bytes"
      ck "$(readlink "$alias" || true)" "$alias_before" "$route/$topology/$json_state: rollback conserva el alias"
      if [ "$json_state" = present ]; then
        ck "$(cat "$global_json")" "anterior" "$route/$topology/$json_state: rollback recupera JSON"
      fi
    done
  done
done

# Un directorio INTERNO enlazado no esta respaldado recursivamente.
# Rechazar TODO antes de escribir, tambien una entrada independiente y el JSON.
# La antigua negativa para la raiz se sustituye arriba por restauracion y
# rollback comprobados: la raiz es una eleccion explicita, no una entrada.
for route in internal zip; do
  for conflict in parent type; do
    H="$(setup_home "preflight-$route-$conflict")"
    export HOME="$H" CLAUDE_HOME="$H/.claude" BACKUP_DIR="$H/backups"
    source_dir="$H/source"; mkdir -p "$source_dir/hooks" "$BACKUP_DIR" "$H/externo"
    echo nuevo > "$source_dir/CLAUDE.md"; echo nuevo > "$source_dir/hooks/a.sh"
    echo nuevo > "$H/nuevo.json"
    source="$source_dir"
    if [ "$route" = zip ]; then
      CLAUDE_HOME="$source_dir" CLAUDE_JSON="$H/nuevo.json" bash "$REPO/scripts/backup.sh" >"$H/snapshot.log" 2>&1
      source="$(find "$BACKUP_DIR" -name 'claude-state-*.zip' -print -quit)"
    fi
    mkdir -p "$CLAUDE_HOME"
    echo anterior > "$CLAUDE_HOME/CLAUDE.md"; echo anterior > "$H/.claude.json"
    if [ "$conflict" = type ]; then
      mkdir -p "$CLAUDE_HOME/hooks/a.sh"; echo anterior > "$CLAUDE_HOME/hooks/a.sh/keep"
    elif [ "$conflict" = parent ]; then
      ln -s "$H/externo" "$CLAUDE_HOME/hooks"; echo anterior > "$H/externo/a.sh"
    fi
    before="$(tree_checksum "$CLAUDE_HOME")"; outside_before="$(tree_checksum "$H/externo")"
    rc=0; bash "$UNINSTALL" --apply --from "$source" >"$H/apply.log" 2>&1 || rc=$?
    ck "$rc" "1" "$route/$conflict: preflight rechaza topologia incompatible"
    ck "$(tree_checksum "$CLAUDE_HOME")" "$before" "$route/$conflict: rechazo antes de cualquier escritura en el arbol"
    ck "$(tree_checksum "$H/externo")" "$outside_before" "$route/$conflict: rechazo deja el arbol ajeno intacto"
    ck "$(cat "$H/.claude.json")" "anterior" "$route/$conflict: rechazo deja JSON intacto"
    ck "$(find "$BACKUP_DIR" -name 'claude-safety-*.zip' | wc -l | tr -d ' ')" "0" "$route/$conflict: preflight antes del backup"
  done
done

# Un kit incompleto no puede restaurar sobre datos previos sin respaldo.
H="$(setup_home incomplete)"
export HOME="$H" CLAUDE_HOME="$H/.claude" BACKUP_DIR="$H/backups"
mkdir -p "$H/kit" "$H/source" "$CLAUDE_HOME"
cp "$UNINSTALL" "$H/kit/uninstall.sh"
echo elegido > "$H/source/settings.json"
echo anterior > "$CLAUDE_HOME/settings.json"; echo anterior > "$H/.claude.json"
before="$(tree_checksum "$CLAUDE_HOME")"
rc=0; bash "$H/kit/uninstall.sh" --apply --from "$H/source" >"$H/apply.log" 2>&1 || rc=$?
ck "$rc" "1" "sin backup.sh: rechaza restaurar sobre estado previo"
ck "$(tree_checksum "$CLAUDE_HOME")" "$before" "sin backup.sh: conserva todos los bytes locales"
ck "$(cat "$H/.claude.json")" "anterior" "sin backup.sh: conserva el JSON global"
ck "$(grep -Fc 'scripts/backup.sh' "$H/apply.log" || true)" "1" "sin backup.sh: identifica el componente necesario"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
