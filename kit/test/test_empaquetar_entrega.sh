#!/usr/bin/env bash
# test_empaquetar_entrega.sh — scripts/empaquetar-entrega.sh genera un paquete que se instala SIN el resto del
# repo (W4 entregable 4). Sobre un repo temporal con lo versionado de este: el paquete lleva solo el producto,
# SHA256SUMS pasa, PROCEDENCIA dice commit y arbol limpio, el bundle se clona a la rama que manda ENTREGA.md, y
# desempaquetado en un directorio vacio install --apply y doctor dan rc 0 con HOME aislado.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; REPO="$HERE/../.."
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

# Repo temporal con el arbol actual (incluidos los ficheros nuevos aun sin versionar) en un solo commit.
R="$tmp/repo"; mkdir -p "$R"
git -C "$REPO" ls-files -z --cached --others --exclude-standard | (cd "$REPO" && xargs -0 -I{} cp --parents -p {} "$R" 2>/dev/null)
git -C "$R" init -q && git -C "$R" add -A && git -C "$R" commit -q -m base --no-gpg-sign
COMMIT="$(git -C "$R" rev-parse HEAD)"
VER="$(tr -d '[:space:]' < "$R/VERSION")"
P="$tmp/out"

(cd "$R" && bash scripts/empaquetar-entrega.sh --out "$P" >/dev/null 2>&1); rc=$?
ck "$rc" "0" "empaquetar sale 0"
ck "$(find "$P" -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort | tr '\n' ' ')" "PROCEDENCIA.json SHA256SUMS scc-v$VER scc-v$VER.bundle scc-v$VER.zip " "deja directorio, zip, bundle, PROCEDENCIA y SHA256SUMS"
D="$P/scc-v$VER"
ck "$(cd "$P" && sha256sum -c SHA256SUMS >/dev/null 2>&1; echo $?)" "0" "sha256sum -c SHA256SUMS pasa"
ck "$(jq -r .commit "$P/PROCEDENCIA.json")" "$COMMIT" "PROCEDENCIA.json lleva el commit"
ck "$(jq -r '.version + " " + (.arbol_limpio | tostring)' "$P/PROCEDENCIA.json")" "$VER true" "y la version y que el arbol estaba limpio"

# Solo el producto
for f in kit/install.sh kit/doctor.sh uninstall.sh scripts/backup.sh scripts/scc.sh scripts/aceptacion-local.sh ENTREGA.md README.md VERSION BUILD_ID LICENSE NOTICE THIRD-PARTY.md SECURITY.md CHANGELOG.md kit/ORIGEN; do
  [ -e "$R/$f" ] || continue
  ck "$([ -f "$D/$f" ] && echo y)" "y" "lleva $f"
done
ck "$(find "$D"/kit/test "$D"/kit/evals "$D"/knowledge "$D"/.claude "$D"/CLAUDE.md "$D"/AGENTS.md "$D"/config -maxdepth 0 2>/dev/null | wc -l | tr -d ' ')" "0" "no lleva kit/test, kit/evals, knowledge, .claude, config ni CLAUDE.md/AGENTS.md de la raiz"
ck "$(find "$D"/scripts -mindepth 1 -maxdepth 1 -printf '%f\n' | LC_ALL=C sort | tr '\n' ' ')" "aceptacion-local.sh backup.sh scc.sh " "de scripts/ solo los tres que usa el producto"

# El ZIP trae lo mismo que el directorio
ck "$(cd "$tmp" && mkdir z && cd z && unzip -q "$P/scc-v$VER.zip" && find . -type f | wc -l | tr -d ' ')" "$(find "$D" -type f | wc -l | tr -d ' ')" "el ZIP tiene los mismos ficheros que el directorio"

# Reproducible: mismo commit, mismo ZIP
P2="$tmp/out2"; (cd "$R" && bash scripts/empaquetar-entrega.sh --out "$P2" >/dev/null 2>&1)
ck "$(sha256sum < "$P2/scc-v$VER.zip")" "$(sha256sum < "$P/scc-v$VER.zip")" "dos empaquetados del mismo commit dan el mismo ZIP"
ck "$(cd "$R" && bash scripts/empaquetar-entrega.sh --out "$P" >/dev/null 2>&1; echo $?)" "1" "no pisa una entrega existente"

# Bundle: la rama de ENTREGA.md, con el commit
git clone -q --branch "release/scc-v$VER-debian" "$P/scc-v$VER.bundle" "$tmp/clon" 2>/dev/null
ck "$(git -C "$tmp/clon" rev-parse HEAD 2>/dev/null)" "$COMMIT" "el bundle se clona en release/scc-v$VER-debian al commit"

# Arbol sucio: lo dice, y el paquete sale del commit, no del arbol
echo cambio >> "$R/README.md"
(cd "$R" && bash scripts/empaquetar-entrega.sh --out "$tmp/out3" >/dev/null 2>&1)
ck "$(jq -r .arbol_limpio "$tmp/out3/PROCEDENCIA.json")" "false" "con el arbol sucio, PROCEDENCIA dice arbol_limpio=false"
ck "$(grep -c '^cambio$' "$tmp/out3/scc-v$VER/README.md")" "0" "y el paquete sale del commit, no del arbol de trabajo"
ck "$(cd "$R" && bash scripts/empaquetar-entrega.sh --out "$tmp/out4" no-existe >/dev/null 2>&1; echo $?)" "1" "una ref inexistente falla"

# Desempaquetado en un directorio vacio: instalar y doctor sin el resto del repo
U="$tmp/entrega"; mkdir "$U"; (cd "$U" && unzip -q "$P/scc-v$VER.zip")
H="$tmp/home"; mkdir "$H"
(cd "$U/scc-v$VER" && HOME="$H" CLAUDE_HOME="$H/.claude" bash kit/install.sh --apply >"$tmp/i.log" 2>&1); ck "$?" "0" "desempaquetado: install --apply rc 0"
(cd "$U/scc-v$VER" && HOME="$H" CLAUDE_HOME="$H/.claude" bash kit/doctor.sh >"$tmp/d.log" 2>&1); ck "$?" "0" "desempaquetado: doctor rc 0 (0 FAIL)"
(cd "$U/scc-v$VER" && HOME="$H" CLAUDE_HOME="$H/.claude" bash uninstall.sh --kit --apply >"$tmp/u.log" 2>&1); ck "$?" "0" "desempaquetado: uninstall --kit --apply rc 0"
ck "$(HOME="$H" PATH=/nonexistent "$BASH" "$U/scc-v$VER/scripts/scc.sh" --version >/dev/null 2>&1; echo $?)" "127" "scc.sh sin claude en el PATH falla con 127, no con un error de rutas"

# La aceptacion lanzada desde Claude Code (CLAUDE_PID heredado) no puede tratar S1 y S2 como la misma sesion.
HA="$tmp/home-acep"; mkdir "$HA"
ck "$(cd "$U/scc-v$VER" && HOME="$HA" CLAUDE_PID=$$ bash scripts/aceptacion-local.sh "$tmp/acep" >"$tmp/acep.log" 2>&1; echo $?)" "0" "aceptacion-local pasa con CLAUDE_PID heredado"

# Reproducible tambien entre zonas horarias y umask: misma suma del ZIP.
P3="$tmp/out-tz"; (cd "$R" && TZ=Asia/Tokyo bash -c 'umask 077; exec bash scripts/empaquetar-entrega.sh --out "$0"' "$P3" >/dev/null 2>&1)
P4="$tmp/out-tz2"; (cd "$R" && TZ=America/Los_Angeles bash -c 'umask 002; exec bash scripts/empaquetar-entrega.sh --out "$0"' "$P4" >/dev/null 2>&1)
ck "$(sha256sum < "$P3/scc-v$VER.zip")" "$(sha256sum < "$P/scc-v$VER.zip")" "el ZIP no cambia con TZ=Tokyo y umask 077"
ck "$(sha256sum < "$P4/scc-v$VER.zip")" "$(sha256sum < "$P/scc-v$VER.zip")" "ni con TZ=Los_Angeles y umask 002"

echo "== $pass ok, $fail fallos =="
[ "$fail" -eq 0 ]
