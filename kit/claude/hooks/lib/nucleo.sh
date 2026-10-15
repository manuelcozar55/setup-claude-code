# shellcheck shell=bash
# Una raíz, una forma y una medida de contexto para los hooks de estado (.claude/estado/nucleo.md).
# Por qué: cada hook resolvía la raíz a su manera (toplevel git, CLAUDE_PROJECT_DIR o cwd), y en $HOME
# o dentro de .claude/ salía un nucleo anidado o ninguno. Y la inyección cortaba por bytes un fichero
# convertido en diario: por encima de 10 000 chars el harness manda la salida a fichero.

# nucleo_raiz <cwd>: raíz del proyecto dueño de <raíz>/.claude/estado/nucleo.md. Toplevel git de
# CLAUDE_PROJECT_DIR (o del cwd); sin git, ese mismo directorio. Lo que cae dentro de un .claude/ sube
# a su padre: desde $HOME/.claude/estado el nucleo es $HOME/.claude/estado/nucleo.md, no uno anidado.
nucleo_raiz() {
  local base=${CLAUDE_PROJECT_DIR:-$1} r
  r=$(git -C "$base" rev-parse --show-toplevel 2>/dev/null) || r=$base
  r=${r%%/.claude/*}; r=${r%/.claude}
  printf '%s\n' "$r"
}

# nucleo_ctx <transcript>: "tokens pct", con pct sobre el airbag (ventana − 33 000, la línea en la
# que compacta solo). Nada si el transcript no trae uso.
nucleo_ctx() {
  local w=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-200000} t
  case "$w" in ''|*[!0-9]*) w=200000;; esac
  [ "$w" -gt 33000 ] || w=200000
  t=$(tail -n 40 "$1" 2>/dev/null \
    | timeout 5 jq -rR 'fromjson? | select(.type=="assistant" and .message.usage!=null) | .message.usage
        | ((.input_tokens//0)+(.cache_read_input_tokens//0)+(.cache_creation_input_tokens//0)) | select(.>0)' 2>/dev/null \
    | tail -1)
  [ -n "$t" ] && printf '%s %s\n' "$t" "$((t * 100 / (w - 33000)))"
}

# nucleo_emitir <fichero>: solo las secciones de la plantilla (templates/nucleo.md), la primera vez
# que aparece cada una, con tope por sección y total. Lo demás se omite y se avisa en una línea.
# «Encargo original», «Pendientes y riesgos» y «No repetir» son los nombres que escribe /handoff.
# Bytes (LC_ALL=C): el tope protege el límite del harness, que se mide en la salida entera.
nucleo_emitir() {
  [ -f "$1" ] || return 0
  LC_ALL=C awk -v f="$1" -v kb="$(( ($(wc -c <"$1") + 1023) / 1024 ))" -v sec=3000 -v tope=6500 '
    BEGIN { n = split("Objetivo|Encargo original|Invariantes|Plan|Paso actual|Siguiente acción|Pendientes|Comandos de verificación|Ficheros tocados|No repetir", k, "|") }
    function sale(s) { out = out s "\n"; usado += length(s) + 1 }
    /^#{1,2} / {
      viva = 0; dentro = 0
      if ($0 ~ /^# /) { if (!titulo) { titulo = 1; sale($0) } else fuera++; next }
      t = substr($0, 4); c = ""
      for (i = 1; i <= n; i++) if (index(t, k[i]) == 1) c = (k[i] == "Encargo original") ? "Objetivo" : k[i]
      if (c == "" || visto[c]++) { fuera++; next }
      if (usado + length($0) > tope) { omitidas = omitidas " «" t "»"; next }
      viva = 1; sale($0); next
    }
    viva {
      resto = sec - dentro; if (tope - usado < resto) resto = tope - usado
      if (length($0) < resto) { sale($0); dentro += length($0) + 1; next }
      sale(substr($0, 1, resto > 0 ? resto : 0)); viva = 0
      sale("[recortado: sección incompleta. LEE " f " antes de actuar.]")
    }
    END {
      printf "%s", out
      if (omitidas != "") print "[recortado por tope: se omiten" omitidas ". LEE " f " antes de actuar.]"
      if (fuera || kb > 12) print "[fuera de forma: " fuera + 0 " secciones / " kb " KB → muévelas a diario.md, que nunca se inyecta]"
    }' "$1" | sed 's|</nucleo-datos|<\\/nucleo-datos|g'
}
