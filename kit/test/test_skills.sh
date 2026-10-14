#!/usr/bin/env bash
# test_skills.sh — el kit distribuye 6 skills (kit/claude/skills): frontmatter valido,
# LICENSE MIT en las 5 derivadas de mattpocock/skills, ningun termino privado (el repo es
# publico) e install.sh las copia. Falsable: plantar un termino privado debe poner rojo
# el escaneo. Los terminos se construyen por concatenacion para que esta suite no los lleve literales.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$HERE/.."
S="$KIT/claude/skills"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
pass=0; fail=0
ck(){ if [ "$1" = "$2" ]; then echo "ok - $3"; pass=$((pass+1)); else echo "NOT ok - $3 ($1 != $2)"; fail=$((fail+1)); fi; }

PRIV="ci""rce|home/man""uel|mcoz""ar|manuelco""zar|recu""erda|compac""t-audit|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|[A-Za-z0-9._-]+@[A-Za-z0-9-]+\.[a-z]{2,}|/ho""me/"
scan(){ grep -rIliE "$PRIV" "$1" 2>/dev/null | wc -l | tr -d ' '; }

ck "$(find "$S" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')" "6" "hay 6 skills en kit/claude/skills"

for d in "$S"/*/; do
  n="$(basename "$d")"; f="$d/SKILL.md"
  fm="$(awk 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} NR>1{print}' "$f" 2>/dev/null)"
  ck "$(printf '%s\n' "$fm" | sed -n 's/^name: *//p' | tr -d "\"'")" "$n" "$n: frontmatter name == carpeta"
  ck "$(printf '%s\n' "$fm" | grep -qE '^description: *[^ >|]' && echo y || echo n)" "y" "$n: description no vacio"
done

for n in grilling writing-for-agents domain-modeling retro to-questionnaire; do
  ck "$(grep -qE '^MIT License' "$S/$n/LICENSE" && grep -q 'Permission is hereby granted' "$S/$n/LICENSE" && echo y || echo n)" "y" "$n: LICENSE con texto MIT"
done
for n in retro to-questionnaire; do
  ck "$(grep -q '^disable-model-invocation: true' "$S/$n/SKILL.md" && echo y || echo n)" "y" "$n: disable-model-invocation conservado"
done

ck "$(scan "$S")" "0" "ningun termino privado bajo kit/claude/skills"

# Falsabilidad: plantar un termino privado en una copia debe poner rojo el escaneo
cp -r "$S" "$tmp/skills-copy"
printf 'contacto: %s\n' "ci""rce" > "$tmp/skills-copy/retro/PLANTED.md"
ck "$([ "$(scan "$tmp/skills-copy")" -ge 1 ] && echo rojo || echo verde)" "rojo" "falsabilidad: termino privado plantado => escaneo en rojo"

# install.sh en un HOME temporal instala las skills (recursivo)
export CLAUDE_HOME="$tmp/dot"
bash "$KIT/install.sh" >/dev/null 2>&1
ck "$(cd "$S" && find . -type f | sort | md5sum)" "$(cd "$CLAUDE_HOME/skills" && find . -type f | sort | md5sum)" "install.sh instala todos los ficheros de las skills"
ck "$([ -f "$CLAUDE_HOME/skills/grilling/agents/openai.yaml" ] && echo y || echo n)" "y" "install.sh copia subdirectorios (grilling/agents)"
ck "$(cmp -s "$S/deep-change/SKILL.md" "$CLAUDE_HOME/skills/deep-change/SKILL.md" && echo y || echo n)" "y" "contenido instalado identico"

# no destructivo: una skill modificada se respalda al reinstalar
echo "mia" >> "$CLAUDE_HOME/skills/retro/SKILL.md"
bash "$KIT/install.sh" >/dev/null 2>&1
ck "$(find "$CLAUDE_HOME/backups" -path '*skills/retro/SKILL.md' 2>/dev/null | wc -l | tr -d ' ')" "1" "reinstalar respalda la skill modificada"

# Una skill enlazada desde otro repo no se pisa: cp -p escribiria a traves del symlink
echo "ajena" > "$tmp/ajena.md"
ln -sf "$tmp/ajena.md" "$CLAUDE_HOME/skills/grilling/SKILL.md"
bash "$KIT/install.sh" >/dev/null 2>&1
ck "$(cat "$tmp/ajena.md")" "ajena" "install.sh no escribe a traves de un symlink de skill"
ck "$([ -L "$CLAUDE_HOME/skills/grilling/SKILL.md" ] && echo y || echo n)" "y" "el symlink de la skill sigue en su sitio"

echo "== $pass ok, $fail fallos"
[ "$fail" -eq 0 ]
