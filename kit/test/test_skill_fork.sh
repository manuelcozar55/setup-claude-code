#!/usr/bin/env bash
# test_skill_fork.sh — la skill 'harness' vive en dos copias sin dueno declarado y
# divergentes en ambas direcciones. Mientras no se unifiquen (fase 3), doctor tiene
# que decirlo: una divergencia que nadie mide es una divergencia que crece.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
REPO="$(cd "$KIT/.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

correr(){ env -u ANTHROPIC_BASE_URL CLAUDE_HOME="$tmp/dot" HOME="$tmp/home" \
            XDG_CONFIG_HOME="$tmp/home/.config" bash "$KIT/doctor.sh" 2>&1; }
mkdir -p "$tmp/home/.config"

REPOSKILL="$REPO/.claude/skills/harness/SKILL.md"
if [ ! -f "$REPOSKILL" ]; then
  echo "ok - el repo no trae skills/harness: suite omitida"; echo "== 1 passed, 0 failed =="; exit 0
fi

# --- Caso 1: las dos copias existen y difieren -> doctor lo reporta --------
rm -rf "$tmp/dot"; mkdir -p "$tmp/dot/skills/harness"
{ cat "$REPOSKILL"; echo "# divergencia fabricada"; } > "$tmp/dot/skills/harness/SKILL.md"
salida1="$(correr)"
ck "$(echo "$salida1" | grep -qi 'dos copias divergentes de la skill harness' && echo y || echo n)" "y" \
   "dos copias que difieren: doctor lo reporta"

# --- Caso 2 (falsabilidad): copias identicas -> doctor NO lo reporta -------
rm -rf "$tmp/dot"; mkdir -p "$tmp/dot/skills/harness"
cp "$REPOSKILL" "$tmp/dot/skills/harness/SKILL.md"
salida2="$(correr)"
ck "$(echo "$salida2" | grep -qi 'dos copias divergentes de la skill harness' && echo y || echo n)" "n" \
   "falsabilidad: copias identicas no se reportan como divergentes"
ck "$(echo "$salida2" | grep -qi 'skill harness: sin fork detectable' && echo y || echo n)" "y" \
   "falsabilidad: copias identicas SI llegan al check (rama else ejecutada)"

# --- Caso 3: la copia desplegada no existe -> doctor NO inventa nada -------
rm -rf "$tmp/dot"; mkdir -p "$tmp/dot"
salida3="$(correr)"
ck "$(echo "$salida3" | grep -qi 'dos copias divergentes de la skill harness' && echo y || echo n)" "n" \
   "sin copia desplegada no hay fork que reportar"
ck "$(echo "$salida3" | grep -qi 'skill harness: sin fork detectable' && echo y || echo n)" "y" \
   "sin copia desplegada tambien cae en la rama else (no es un doctor muerto a mitad)"

echo "== $pass passed, $fail failed =="; [ "$fail" -eq 0 ]
