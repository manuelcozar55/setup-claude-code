# shellcheck shell=bash
# Una raíz, una forma y una medida de contexto para los hooks de estado (.claude/estado/nucleo.md).
# Por qué: cada hook resolvía la raíz a su manera (toplevel git, CLAUDE_PROJECT_DIR o cwd), y en $HOME
# o dentro de .claude/ salía un nucleo anidado o ninguno. Y la inyección cortaba por bytes un fichero
# convertido en diario: por encima de 10 000 chars el harness manda la salida a fichero.

# nucleo_raiz <cwd>: raíz del proyecto dueño de <raíz>/.claude/estado/nucleo.md. Toplevel git de
# CLAUDE_PROJECT_DIR (o del cwd); sin git, ese mismo directorio. Lo que cae dentro de $HOME/.claude sube
# a $HOME: desde $HOME/.claude/estado el nucleo es $HOME/.claude/estado/nucleo.md, no uno anidado. Solo
# ese: un worktree de `claude --worktree` vive en <repo>/.claude/worktrees/<rama> y es su propia raíz.
nucleo_raiz() {
  local base=${CLAUDE_PROJECT_DIR:-$1} r
  r=$(git -C "$base" rev-parse --show-toplevel 2>/dev/null) || r=$base
  case $r in "$HOME/.claude" | "$HOME/.claude/"*) r=$HOME ;; esac
  printf '%s\n' "$r"
}

# nucleo_enlazado <raíz>: .claude/estado o nucleo.md es un symlink. El repo puede ser de terceros: con
# un enlace decidiría qué fichero de fuera se inyecta y dónde se escribe el checkpoint (con prompts).
nucleo_enlazado() { [ -L "$1/.claude/estado" ] || [ -L "$1/.claude/estado/nucleo.md" ]; }

# nucleo_ctx <transcript>: "tokens pct", con pct sobre el airbag (ventana − 33 000, la línea en la
# que compacta solo). Nada si el transcript no trae uso. La ventana es min(la del modelo, el env), como
# en el binario: sin [1m] el modelo tiene 200 000 y un env mayor no sube el airbag.
nucleo_ctx() {
  local w=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-200000} t
  case "$w" in ''|*[!0-9]*) w=200000;; esac
  [ "$w" -gt 33000 ] || w=200000
  if [ "$w" -gt 200000 ]; then
    case ${ANTHROPIC_MODEL:-} in *'[1m]'*) ;; *)
      command grep -qs '"model"[[:space:]]*:[[:space:]]*"[^"]*\[1m\]' "$HOME/.claude/settings.json" || w=200000 ;;
    esac
  fi
  # Sin `timeout`: 40 líneas no cuelgan a jq, y en coreutils de Rust arrancarlo cuesta ~100 ms.
  t=$(tail -n 40 "$1" 2>/dev/null \
    | jq -rR 'fromjson? | select(.type=="assistant" and .message.usage!=null) | .message.usage
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
    # ### también: las sesiones escriben la tarea como «## TAREA ACTUAL» con sus secciones en ###. Si nombra
    # una sección aún no vista es cabecera; si no, es contenido solo bajo un ## de plantilla (padre: «### Fase 1»
    # en «## Plan»); bajo otro ## cierra y cuenta en fuera, para que «### Hecho» no se cuele en Pendientes.
    # Solo el nombre distingue ese «### Hecho» de un subapartado «### Fase 1»: si cierra una sección viva
    # (cerradas), la salida pide leer el fichero y sugiere escribir los subapartados con ####.
    # La clave va por prefijo también en ###: «### Plan de migración» reclama Plan, como ya lo hacía con ##.
    # Dentro de un bloque ``` nada es cabecera: un «# comentario» cerraba la sección y perdía los comandos.
    # Primera pasada: cuenta las cercas; si quedan impares se ignoran todas (y se avisa), para que una sin
    # cerrar no se trague el resto del fichero. Con cualquier sangría: un paso numerado lleva su bloque
    # sangrado cuatro espacios, y sin contarlo su # comentario cortaba los comandos.
    # Límites: un ``` dentro de un bloque sangrado de CommonMark cuenta como cerca; no se casa el cierre con
    # la longitud ni el info string del apertor; ni cercas anidadas (```` con ``` dentro) ni ~~~; si otra
    # sesión escribe el fichero entre las dos lecturas (como ya pasaba con wc -c), la paridad puede no ser
    # la del texto emitido; y un ## de plantilla repetido descarta su contenido y sus ### sin clave sin más
    # señal que «fuera de forma».
    NR == FNR { if ($0 ~ /^[ \t]*```+[^`]*$/) cercas++; next }
    /^[ \t]*```+[^`]*$/ && cercas % 2 == 0 { cerca = !cerca }
    /^#(#|##)? / && !cerca {
      t = $0; sub(/^#(#|##)? /, "", t); c = ""
      for (i = 1; i <= n; i++) if (index(t, k[i]) == 1) c = (k[i] == "Encargo original") ? "Objetivo" : k[i]
    }
    /^#(#|##)? / && !cerca && ($0 !~ /^### / || (c != "" && !visto[c]) || !padre) {
      if ($0 ~ /^### / && viva && !padre && (c == "" || visto[c])) cerradas++
      viva = 0; dentro = 0
      if ($0 ~ /^# /) { padre = 0; if (!titulo) { titulo = 1; sale(substr($0, 1, 200)) } else fuera++; next }
      if ($0 ~ /^## /) padre = (c != "")
      if (c == "" || visto[c]++) { fuera++; next }
      if (usado + length($0) > tope) { omitidas = omitidas " «" substr(t, 1, 80) "»"; next }
      viva = 1; sale($0); next
    }
    viva {
      resto = sec - dentro; if (tope - usado < resto) resto = tope - usado
      if (length($0) < resto) { sale($0); dentro += length($0) + 1; next }
      sale(substr($0, 1, resto > 0 ? resto : 0)); viva = 0
      sale("[recortado: sección incompleta.]"); recortes++
    }
    END {
      printf "%s", out
      if (cercas % 2) print "[cercas sin equilibrar: se ignoran; un # comentario dentro de un bloque puede cortar su sección]"
      if (omitidas != "") print "[recortado por tope: se omiten" omitidas ".]"
      if (recortes || omitidas != "" || cerradas || cercas % 2) print "[LEE " f " antes de actuar: lo inyectado está incompleto.]"
      if (fuera || kb > 12) print "[fuera de forma: " fuera + 0 " secciones / " kb " KB → muévelas a diario.md, que nunca se inyecta" \
        (cerradas ? " (un ### sin nombre de plantilla cerró una sección: si era un subapartado, escríbelo con ####)" : "") "]"
    }' "$1" "$1" | sed 's|</|<\\/|g'
}
