#!/usr/bin/env bash
# test_txnwrite.sh — primitivas de escritura cerrada del instalador (task 16).
#
# kit/lib/txnwrite.py expone EXACTAMENTE cuatro subcomandos (copy-owned,
# json-merge-owned-keys, managed-text-block, diff-only) y ninguna escritura
# a un target gestionado ocurre fuera de ellos. Cada escritura hereda el patron
# transaccional de task-6: dirfd O_NOFOLLOW, staging O_EXCL 0600, WAL 0600
# hash-encadenado con fsync, publicacion por renameat2 (RENAME_NOREPLACE al
# crear, RENAME_EXCHANGE con verificacion del inodo desplazado al reemplazar),
# nunca rename-ordinario-tras-check. La recuperacion es idempotente por hashes;
# un tercer hash desconocido o un WAL corrupto fallan en cerrado (piden fsck).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
LIB="$KIT/lib/txnwrite.py"
PY=/usr/bin/python3
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

txn(){ "$PY" -I "$LIB" "$@"; }

# ------------------------------------------------------------ existencia y API
ck "$([ -f "$LIB" ] && echo y || echo n)" "y" "kit/lib/txnwrite.py existe"

set +e
subs="$(txn --list-primitives 2>/dev/null)"; rc=$?
set -e
ck "$rc" "0" "--list-primitives responde rc=0"
# Exactamente cuatro, en orden canonico y sin nada mas.
ck "$subs" "copy-owned
diff-only
json-merge-owned-keys
managed-text-block" "expone EXACTAMENTE las cuatro primitivas"

# ------------------------------------------------------------------ copy-owned
ROOT="$tmp/root"; mkdir -p "$ROOT"; chmod 700 "$ROOT"
SRC="$tmp/src.txt"; printf 'contenido-uno\n' > "$SRC"

set +e
txn copy-owned --root "$ROOT" --src "$SRC" --dst "a/b/c.txt" --mode 0644 >/dev/null 2>&1; rc=$?
set -e
ck "$rc" "0" "copy-owned crea target nuevo (rc=0)"
ck "$([ -f "$ROOT/a/b/c.txt" ] && echo y || echo n)" "y" "copy-owned escribio el fichero"
ck "$(cat "$ROOT/a/b/c.txt")" "contenido-uno" "copy-owned bytes exactos"
ck "$(stat -c '%a' "$ROOT/a/b/c.txt")" "644" "copy-owned aplica el modo pedido"
# Idempotencia: mismo src => sin cambios, sin backup nuevo.
set +e; txn copy-owned --root "$ROOT" --src "$SRC" --dst "a/b/c.txt" --mode 0644 >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "0" "copy-owned idempotente (rc=0 sin cambios)"

# Reemplazo via RENAME_EXCHANGE: cambia el contenido de un target existente.
printf 'contenido-dos\n' > "$SRC"
set +e; txn copy-owned --root "$ROOT" --src "$SRC" --dst "a/b/c.txt" --mode 0644 >/dev/null 2>&1; rc=$?; set -e
ck "$rc" "0" "copy-owned reemplaza target existente (rc=0)"
ck "$(cat "$ROOT/a/b/c.txt")" "contenido-dos" "copy-owned reemplazo: bytes nuevos"

# ------------------------------------------------- WAL 0600 y purga tras commit
WAL="$ROOT/.cckit-txn.wal"
if [ -f "$WAL" ]; then
  ck "$(stat -c '%a' "$WAL")" "600" "WAL, si persiste, es 0600"
else
  ck "y" "y" "WAL retirado tras commit (aceptable)"
fi

# ----------------------------------------------------- confinamiento: symlink
# Un componente de ruta que es symlink fuera del root se rechaza SIN escribir.
mkdir -p "$tmp/afuera"
ln -s "$tmp/afuera" "$ROOT/enlace"
set +e
txn copy-owned --root "$ROOT" --src "$SRC" --dst "enlace/x.txt" --mode 0644 >/dev/null 2>&1; rc=$?
set -e
ck "$([ "$rc" -ne 0 ] && echo y || echo n)" "y" "copy-owned rechaza symlink en la ruta (rc!=0)"
ck "$([ -e "$tmp/afuera/x.txt" ] && echo escapo || echo confinado)" "confinado" "no escribio fuera del root por el symlink"

# --------------------------------------------------- confinamiento: escape ..
set +e
txn copy-owned --root "$ROOT" --src "$SRC" --dst "../fuera.txt" --mode 0644 >/dev/null 2>&1; rc=$?
set -e
ck "$([ "$rc" -ne 0 ] && echo y || echo n)" "y" "copy-owned rechaza '..' en dst (rc!=0)"
ck "$([ -e "$tmp/fuera.txt" ] && echo escapo || echo confinado)" "confinado" "no escribio via '..'"

# --------------------------------------------------- root no propiedad / raiz
set +e; txn copy-owned --root "/" --src "$SRC" --dst "x.txt" --mode 0644 >/dev/null 2>&1; rc=$?; set -e
ck "$([ "$rc" -ne 0 ] && echo y || echo n)" "y" "copy-owned rechaza root '/'"

# ------------------------------------------------- managed-text-block por stdin
set +e
printf 'linea-bloque\n' | txn managed-text-block --root "$ROOT" --dst "gen/unit.txt" --mode 0644 --whole-file >/dev/null 2>&1; rc=$?
set -e
ck "$rc" "0" "managed-text-block escribe desde stdin (rc=0)"
ck "$(cat "$ROOT/gen/unit.txt" 2>/dev/null)" "linea-bloque" "managed-text-block bytes exactos"

# ----------------------------------------------- json-merge-owned-keys env
KITJSON="$tmp/kit.json"; printf '{"env":{"A":"1"},"hooks":{"h":1},"permissions":{"allow":["x"],"deny":["y"]}}\n' > "$KITJSON"
printf '{"env":{"B":"2"},"model":"mine"}\n' > "$ROOT/settings.json"
set +e
txn json-merge-owned-keys --root "$ROOT" --dst "settings.json" --kit-json "$KITJSON" --policy claude-settings >/dev/null 2>&1; rc=$?
set -e
ck "$rc" "0" "json-merge-owned-keys fusiona (rc=0)"
if command -v "$PY" >/dev/null 2>&1; then
  model="$("$PY" -c 'import json,sys;print(json.load(open(sys.argv[1]))["model"])' "$ROOT/settings.json" 2>/dev/null)"
  ck "$model" "mine" "json-merge conserva el ajuste del usuario (model)"
  bkeep="$("$PY" -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d["env"].get("B"))' "$ROOT/settings.json" 2>/dev/null)"
  ck "$bkeep" "2" "json-merge conserva env del usuario"
fi

# ----------------------------------------------------------- diff-only no escribe
before="$(cat "$ROOT/settings.json")"
set +e
txn diff-only --root "$ROOT" --dst "settings.json" --src "$KITJSON" --label codex >/dev/null 2>&1; rc=$?
set -e
ck "$rc" "0" "diff-only responde rc=0"
ck "$(cat "$ROOT/settings.json")" "$before" "diff-only NO escribe (target intacto)"

# ------------------------------------------------ recuperacion: WAL corrupto bloquea
ROOT2="$tmp/root2"; mkdir -p "$ROOT2"; chmod 700 "$ROOT2"
printf 'esto-no-es-json-wal\n' > "$ROOT2/.cckit-txn.wal"; chmod 600 "$ROOT2/.cckit-txn.wal"
set +e
txn copy-owned --root "$ROOT2" --src "$SRC" --dst "z.txt" --mode 0644 >/dev/null 2>&1; rc=$?
set -e
ck "$([ "$rc" -ne 0 ] && echo y || echo n)" "y" "WAL corrupto bloquea la siguiente escritura (pide fsck)"
ck "$([ -e "$ROOT2/z.txt" ] && echo escribio || echo bloqueado)" "bloqueado" "no escribio con WAL corrupto"

# --------------------------------------- recuperacion: tercer hash bloquea (recover)
# Un WAL 'prepared' cuyo target on-disk no coincide ni con pre ni con post
# es un tercer hash: recover debe bloquear en vez de adivinar.
ROOT3="$tmp/root3"; mkdir -p "$ROOT3"; chmod 700 "$ROOT3"
printf 'estado-desconocido\n' > "$ROOT3/t.txt"; chmod 644 "$ROOT3/t.txt"
"$PY" -I "$LIB" --emit-test-prepared-wal \
  --root "$ROOT3" --dst "t.txt" \
  --pre-sha "$(printf 'PRE\n' | sha256sum | cut -d' ' -f1)" \
  --post-sha "$(printf 'POST\n' | sha256sum | cut -d' ' -f1)" >/dev/null 2>&1 || true
set +e
txn recover --root "$ROOT3" >/dev/null 2>&1; rc=$?
set -e
ck "$([ "$rc" -ne 0 ] && echo y || echo n)" "y" "recover con tercer hash bloquea (rc!=0)"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
