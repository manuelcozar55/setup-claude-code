#!/usr/bin/env bash
# scan-secrets.sh — Gate determinista de secretos/PII sobre el kit.
# Uso: scan-secrets.sh [DIR]   (default: carpeta del propio script)
# Exit 0 = limpio (PASS); 1 = hallazgos (FAIL).
set -euo pipefail
TARGET="${1:-$(cd "$(dirname "$0")" && pwd)}"
SELF="$(basename "$0")"

# Patrones de VALOR (no de nombre). Los nombres de variables (ANTHROPIC_API_KEY) son válidos.
PATTERNS=(
  '\<sk-[A-Za-z0-9_-]{20,}'
  'pplx-[A-Za-z0-9]{20,}'
  'gh[oprsu]_[A-Za-z0-9]{20,}'
  'AKIA[0-9A-Z]{16}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY'
  '/root/'
)
found=0
report() { echo "LEAK: $1"; found=1; }

# El nombre de la cuenta A SECAS, sin ruta delante. El patron /home/<x>/ de mas abajo
# solo lo ve dentro de una ruta: en el journal de mcharness el nombre iba suelto en un
# campo `actor` y 131 lineas pasaron por limpias porque el patron no PODIA coincidir.
# Un nombre corto o generico (root, runner, ci) haria saltar palabras normales, asi que
# ahi el check NO se hace -- pero se dice al final, nunca se calla: omitir no es aprobar.
CUENTA="${SCAN_SECRETS_CUENTA:-$(id -un 2>/dev/null || true)}"
CUENTA_GENERICOS='root|user|users|usuario|ubuntu|debian|runner|admin|administrator|ci|build|builder|node|docker|test|guest|jenkins|vagrant|codespace|vscode|azureuser|ec2-user|pi|dev|home'
cuenta_omitida=""
if [ -z "$CUENTA" ]; then
  cuenta_omitida="no se pudo leer el nombre de la cuenta local"
elif [ "${#CUENTA}" -lt 8 ]; then
  cuenta_omitida="el nombre de la cuenta local tiene menos de 8 caracteres y buscarlo daria falsos positivos"
elif printf '%s' "$CUENTA" | grep -qiE "^($CUENTA_GENERICOS)$"; then
  cuenta_omitida="el nombre de la cuenta local es un nombre generico"
fi

# Dentro de un repo git NO se escanea lo ignorado. Un fichero ignorado no se va a
# commitear, asi que un hallazgo ahi es ruido -- y era ruido con consecuencias:
# test_harness_structure.sh ejecuta este escaner sobre la raiz del repo, y daba ROJO en
# la maquina de quien tuviera scratch de SDD en disco y VERDE en CI, donde el clon esta
# limpio. Un sensor cuyo resultado depende de ficheros que no viajan no mide el repo.
# Fuera de un repo (los fixtures de test) se enumera con find, como antes.
list_files() {
  if git -C "$TARGET" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$TARGET" ls-files -z --cached --others --exclude-standard \
      | while IFS= read -r -d '' rel; do printf '%s\0' "$TARGET/$rel"; done
  else
    find "$TARGET" -type f -not -path '*/.git/*' -print0
  fi
}

while IFS= read -r -d '' f; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"
  # El propio escáner y su test documentan patrones: se excluyen.
  [ "$base" = "$SELF" ] && continue
  [ "$base" = "test_scan_secrets.sh" ] && continue
  for p in "${PATTERNS[@]}"; do
    if grep -InE "$p" "$f" >/dev/null 2>&1; then
      report "patrón /$p/ en $f"; grep -InE "$p" "$f" | head -2 || true
    fi
  done
  # Emails que no sean de ejemplo/noreply = PII.
  if grep -InoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" 2>/dev/null \
       | grep -viE '@example\.(com|org)|noreply@|you@example|manuelcozar55@gmail\.com' >/dev/null 2>&1; then
    report "email real en $f"
    grep -InoE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}' "$f" \
      | grep -viE '@example\.(com|org)|noreply@|you@example|manuelcozar55@gmail\.com' | head -2 || true
  fi
  if [ -z "$cuenta_omitida" ] && grep -Fnw -e "$CUENTA" "$f" >/dev/null 2>&1; then
    report "nombre de la cuenta local a secas en $f (usa un marcador de posicion)"
    grep -Fnw -e "$CUENTA" "$f" | head -2 || true
  fi
  # Credencial de 64 hex ASIGNADA a un nombre de credencial. Existe porque
  # claude/.gitleaks.toml exime esa forma del generic-api-key -- es la forma de las
  # huellas que mch sella como `- sensor:` -- y ese comentario promete que este
  # escaner cubre lo cedido. La clave esta en exigir el nombre pegado al valor: en
  # el journal esos mismos 64 hex van indexados por una RUTA de fichero, no por un
  # nombre de credencial, y por eso no caen aqui.
  if grep -IniE '(password|passwd|secret|token|api_?key)[[:space:]]*[:=][[:space:]]*"?[a-f0-9]{64}"?' "$f" >/dev/null 2>&1; then
    report "credencial de 64 hex asignada en $f"
    grep -IniE '(password|passwd|secret|token|api_?key)[[:space:]]*[:=][[:space:]]*"?[a-f0-9]{64}"?' "$f" | head -2 || true
  fi
  # Ruta del home de una persona concreta. No entra en PATTERNS porque necesita excluir
  # los marcadores de posicion legitimos, igual que el check de emails. Por que existe:
  # este kit vendoriza sentinel, y la copia de origen habia sustituido /root/ por el home
  # literal de un usuario al cambiar de maquina -- incluida la PLANTILLA de allowlist, que
  # es el peor sitio posible. Que no llegara al repo publico fue disciplina, no sensor.
  if grep -InoE '/home/[a-z][a-z0-9._-]*/' "$f" 2>/dev/null \
       | grep -viE '/home/(ciuser|user|usuario|youruser|tu-usuario|tuusuario)/' >/dev/null 2>&1; then
    report "ruta del home de un usuario concreto en $f (usa \$HOME o ~)"
    grep -InoE '/home/[a-z][a-z0-9._-]*/' "$f" \
      | grep -viE '/home/(ciuser|user|usuario|youruser|tu-usuario|tuusuario)/' | head -2 || true
  fi
done < <(list_files)

if [ -n "$cuenta_omitida" ]; then
  echo "NOTA: el nombre de la cuenta a secas no se ha comprobado: $cuenta_omitida"
fi
if [ "$found" -ne 0 ]; then echo "FAIL: secretos/PII detectados en $TARGET"; exit 1; fi
echo "PASS: sin secretos/PII en $TARGET"
