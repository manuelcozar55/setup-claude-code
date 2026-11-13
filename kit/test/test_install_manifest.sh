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
# Un `claude` propio en el PATH: sin el, doctor avisa «claude no se encuentra ... claude --version» y ese WARN
# casa con 'WARN · .*version'; aqui se mide el aviso de version del KIT, no que la maquina tenga claude.
mkdir -p "$tmp/bin"; printf '#!/bin/sh\necho "99.0.0 (Claude Code)"\n' >"$tmp/bin/claude"; chmod +x "$tmp/bin/claude"
export PATH="$tmp/bin:$PATH"
out="$(bash "$KIT/doctor.sh" 2>&1)"
ck "$(printf '%s\n' "$out" | grep -c "version instalada del kit: $VER")" "1" "doctor imprime la version instalada"
ck "$(printf '%s\n' "$out" | grep -c 'WARN · .*version')" "0" "sin aviso de version cuando coincide"
echo "0.0.1" > "$CLAUDE_HOME/.kit-version"
out="$(bash "$KIT/doctor.sh" 2>&1)"
ck "$(printf '%s\n' "$out" | grep -c "WARN · .*0.0.1.*$VER.*install.sh --apply")" "1" "doctor avisa (WARN con la orden) si la version instalada difiere"
rm "$CLAUDE_HOME/.kit-version"
out="$(bash "$KIT/doctor.sh" 2>&1)"
ck "$(printf '%s\n' "$out" | grep -c 'WARN · .*sin .kit-version.*install.sh --apply')" "1" "doctor avisa si no hay .kit-version"

# Elementos que 2.0.0 retiro (agente strategist, skills grilling/to-questionnaire/...): al instalar encima de una
# 1.9.1 se borran los que coinciden con una version publicada; el modificado por la persona se conserva y doctor
# lo avisa; un fichero propio en la carpeta de una skill retirada no se toca (ni su carpeta).
FX="$HERE/fixtures/retirados"
H3="$tmp/h3"; mkdir -p "$H3"
export HOME="$H3" CLAUDE_HOME="$H3/.claude"
bash "$KIT/install.sh" --apply >/dev/null 2>&1
mkdir -p "$CLAUDE_HOME/agents" "$CLAUDE_HOME/skills/grilling/agents" "$CLAUDE_HOME/skills/to-questionnaire" "$CLAUDE_HOME/skills/domain-modeling"
cp "$FX/strategist.md" "$CLAUDE_HOME/agents/strategist.md"
cp "$FX/grilling-LICENSE" "$CLAUDE_HOME/skills/grilling/LICENSE"
cp "$FX/grilling-SKILL.md" "$CLAUDE_HOME/skills/grilling/SKILL.md"
cp "$FX/grilling-openai.yaml" "$CLAUDE_HOME/skills/grilling/agents/openai.yaml"
{ cat "$FX/to-questionnaire-SKILL.md"; echo "# mi cambio"; } > "$CLAUDE_HOME/skills/to-questionnaire/SKILL.md"
echo mio > "$CLAUDE_HOME/skills/domain-modeling/mio.md"
bash "$KIT/install.sh" --apply >"$tmp/i3.log" 2>&1
ck "$([ -e "$CLAUDE_HOME/agents/strategist.md" ] && echo y || echo n)" "n" "install borra el agente retirado si es una version publicada"
ck "$([ -e "$CLAUDE_HOME/skills/grilling" ] && echo y || echo n)" "n" "install borra la skill retirada entera (y su carpeta) si todo es publicado"
ck "$(grep -c 'mi cambio' "$CLAUDE_HOME/skills/to-questionnaire/SKILL.md")" "1" "el fichero retirado y modificado por la persona se conserva"
ck "$(grep -c 'skills/to-questionnaire/SKILL.md' "$tmp/i3.log")" "1" "y la instalacion lo dice"
ck "$(cat "$CLAUDE_HOME/skills/domain-modeling/mio.md")" "mio" "un fichero propio en la carpeta de una skill retirada no se toca"
out="$(bash "$KIT/doctor.sh" 2>&1)"
ck "$(printf '%s\n' "$out" | grep -c 'WARN · .*skills/to-questionnaire/SKILL.md')" "1" "doctor avisa del retirado que sigue instalado"
# claude instalado en ~/.local/bin pero fuera del PATH no es «claude no instalado».
mkdir -p "$H3/.local/bin"; cp "$tmp/bin/claude" "$H3/.local/bin/claude"
out="$(PATH=/usr/local/bin:/usr/bin:/bin bash "$KIT/doctor.sh" 2>&1)"
ck "$(printf '%s\n' "$out" | grep -c 'WARN · claude esta instalado en .*no esta en tu PATH')" "1" "doctor distingue claude fuera del PATH de claude no instalado"
# Una skill retirada cuya carpeta es un symlink (skill proyectada desde otro repo): la ruta pasa por el enlace y
# borrar escribiria en ese repo, aunque el fichero final no sea un symlink. No se toca.
O="$tmp/otro-repo/grilling"; mkdir -p "$O/agents"
cp "$FX/grilling-SKILL.md" "$O/SKILL.md"; cp "$FX/grilling-openai.yaml" "$O/agents/openai.yaml"
ln -s "$O" "$CLAUDE_HOME/skills/grilling"
bash "$KIT/install.sh" --apply >/dev/null 2>&1
ck "$([ -f "$O/SKILL.md" ] && [ -f "$O/agents/openai.yaml" ] && echo y || echo n)" "y" "install no borra a traves de una carpeta de skill enlazada"


# Cada ruta retirada que publico una etiqueta v* tiene su suma en hooks-retirados.sha256 (si no, quien actualiza
# desde esa version conserva el fichero y el kit lo da por modificado). Sin etiquetas en el clon: SKIP.
RET="$KIT/hooks-retirados.sha256"
tags="$(git -C "$REPO" tag -l 'v*' 2>/dev/null)"
if [ -z "$tags" ]; then echo "SKIP - el clon no tiene etiquetas v*: no se comparan las sumas retiradas con lo publicado"
else
  falta=""
  nombres="$(awk -F'  ' '$0 !~ /^#/ {print $2}' "$RET" | LC_ALL=C sort -u)"
  for t in $tags; do
    while IFS= read -r rel; do
      case "$rel" in */*) ;; *) rel="hooks/$rel" ;; esac
      s="$(git -C "$REPO" show "$t:kit/claude/$rel" 2>/dev/null | sha256sum | cut -d' ' -f1)" || continue
      git -C "$REPO" cat-file -e "$t:kit/claude/$rel" 2>/dev/null || continue
      grep -qxF "$s  ${rel#hooks/}" "$RET" || grep -qxF "$s  $rel" "$RET" || falta="$falta $t:$rel"
    done <<< "$nombres"
  done
  ck "$falta" "" "toda ruta retirada publicada en una etiqueta v* tiene su suma en hooks-retirados.sha256"
fi
echo "== $pass ok, $fail fallos =="
[ "$fail" -eq 0 ]
