#!/usr/bin/env bash
# test_install_manifest.sh — install.sh --apply deja en CLAUDE_HOME la version instalada (.kit-version) y un
# manifiesto (.kit-manifest: «sha256  ruta» por fichero que el kit escribio, y «~bin/<cli>» por enlace del
# bindir); doctor.sh imprime la version instalada y avisa si difiere de la del clon. Es lo que permite
# desinstalar (uninstall.sh --kit) y saber que version tienes. Sin red, HOME aislado.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."; REPO="$KIT/.."
tmp="$(mktemp -d)"; trap 'rm -r "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }
VER="$(tr -d '[:space:]' < "$REPO/VERSION")"

export HOME="$tmp/h"; mkdir -p "$HOME"; export CLAUDE_HOME="$HOME/.claude"
bash "$KIT/install.sh" --apply >"$tmp/i.log" 2>&1; ck "$?" "0" "install --apply sale 0"
ck "$(cat "$CLAUDE_HOME/.kit-version" 2>/dev/null)" "$VER" ".kit-version = VERSION del clon"
M="$CLAUDE_HOME/.kit-manifest"
ck "$([ -s "$M" ] && echo y)" "y" ".kit-manifest existe y no esta vacio"
ck "$(grep -cvE '^[0-9a-f]{64}  [^ ]' "$M")" "0" "todas las lineas del manifiesto son «sha256  ruta»"
# Cada fichero del manifiesto (salvo enlaces) existe y su suma coincide.
bad=0; while IFS= read -r l; do
  s="${l%%  *}"; p="${l#*  }"; case "$p" in "~bin/"*) continue ;; esac
  [ "$(sha256sum "$CLAUDE_HOME/$p" 2>/dev/null | cut -d' ' -f1)" = "$s" ] || bad=$((bad+1))
done < "$M"
ck "$bad" "0" "las sumas del manifiesto coinciden con lo instalado"
for f in hooks/branch-guard.sh bin/handoff sentinel/sentinel_preflight.py statusline-command.sh CLAUDE.md AGENTS.md settings.json .gitleaks.toml sentinel-allowlist.json; do
  ck "$(grep -c "  $f\$" "$M")" "1" "manifiesto lista $f"
done
ck "$(grep -c '  ~bin/' "$M")" "5" "manifiesto lista los 5 enlaces del bindir (con scc)"
ck "$(grep -c 'kit-manifest\|kit-version' "$M")" "0" "el manifiesto no se lista a si mismo"

# Reinstalar es idempotente: mismo manifiesto.
cp "$M" "$tmp/m1"; bash "$KIT/install.sh" --apply >/dev/null 2>&1
ck "$(cmp -s "$M" "$tmp/m1" && echo y)" "y" "reinstalar deja el mismo manifiesto"

# Un fichero propio del usuario junto al kit no entra.
mkdir -p "$CLAUDE_HOME/hooks"; echo x > "$CLAUDE_HOME/hooks/mio.sh"; bash "$KIT/install.sh" --apply >/dev/null 2>&1
ck "$(grep -c 'mio.sh' "$M")" "0" "un hook propio no entra en el manifiesto"

# --plan no escribe version ni manifiesto.
H2="$tmp/h2"; mkdir -p "$H2"
HOME="$H2" CLAUDE_HOME="$H2/.claude" TMPDIR="$tmp" bash "$KIT/install.sh" --plan >/dev/null 2>&1
ck "$(find "$H2" -mindepth 1 | wc -l | tr -d ' ')" "0" "--plan no escribe nada en el HOME"

# doctor: version instalada y aviso si difiere.
out="$(bash "$KIT/doctor.sh" 2>&1)"
ck "$(printf '%s\n' "$out" | grep -c "version instalada del kit: $VER")" "1" "doctor imprime la version instalada"
ck "$(printf '%s\n' "$out" | grep -c 'WARN · .*version')" "0" "sin aviso de version cuando coincide"
echo "0.0.1" > "$CLAUDE_HOME/.kit-version"
out="$(bash "$KIT/doctor.sh" 2>&1)"
ck "$(printf '%s\n' "$out" | grep -c "WARN · .*0.0.1.*$VER.*install.sh --apply")" "1" "doctor avisa (WARN con la orden) si la version instalada difiere"
rm "$CLAUDE_HOME/.kit-version"
out="$(bash "$KIT/doctor.sh" 2>&1)"
ck "$(printf '%s\n' "$out" | grep -c 'WARN · .*sin .kit-version.*install.sh --apply')" "1" "doctor avisa si no hay .kit-version"

echo "== $pass ok, $fail fallos =="
[ "$fail" -eq 0 ]
