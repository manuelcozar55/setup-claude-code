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

# Esta suite no llama a jq, pero todo lo que mide sale de kit/doctor.sh, que lo usa en
# 12 sitios: sin jq doctor no llega al check de la skill y la suite daba "2 passed,
# 3 failed" -- tres rojos que no dicen nada sobre la divergencia que vigila. Se omite
# declarandolo, como ya hacen otras diez suites de este repo.
if ! command -v jq >/dev/null 2>&1; then
  echo "skip - jq ausente: esta suite lee el informe de doctor.sh, que necesita jq para producirlo"
  echo "== 0 passed, 0 failed, 1 skipped =="; exit 0
fi

correr(){ env -u ANTHROPIC_BASE_URL CLAUDE_HOME="$tmp/dot" HOME="$tmp/home" \
            XDG_CONFIG_HOME="$tmp/home/.config" bash "$KIT/doctor.sh" 2>&1; }
mkdir -p "$tmp/home/.config"

REPOSKILL="$REPO/.claude/skills/harness/SKILL.md"
if [ ! -f "$REPOSKILL" ]; then
  # .claude/skills/harness/SKILL.md esta versionado (git ls-files lo confirma): su
  # presencia es un invariante del repo, no un input opcional. Si algun dia falta -- y
  # va a faltar: la fase 3 unifica esta skill -- un skip verde aqui mediria cero en
  # silencio. Eso es un sensor inerte, no un skip honesto: falla ruidoso.
  echo "NOT ok - $REPOSKILL no existe: esta suite no mide nada. Si la fase 3 unifico" \
       "la skill harness, esta suite hay que REESCRIBIRLA, no omitirla."
  echo "== 0 passed, 1 failed =="
  exit 1
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
