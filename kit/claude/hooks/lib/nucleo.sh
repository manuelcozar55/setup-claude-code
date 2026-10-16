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

# nucleo_enlazado <raíz>: .claude, .claude/estado o nucleo.md es un symlink, o la ruta resuelta de nucleo.md
# cae fuera de la raíz. El repo puede ser de terceros: con un enlace decidiría qué fichero de fuera se
# inyecta y dónde se escribe el checkpoint (con prompts). Con `.claude` enlazado, mirar solo estado/ y
# nucleo.md no bastaba. realpath falla cerrado: sin resolver, se da por enlazado.
nucleo_enlazado() {
  [ -L "$1/.claude" ] || [ -L "$1/.claude/estado" ] || [ -L "$1/.claude/estado/nucleo.md" ] && return 0
  local r e
  r=$(realpath -m -- "$1" 2>/dev/null) && e=$(realpath -m -- "$1/.claude/estado/nucleo.md" 2>/dev/null) || return 0
  case $e in "$r"/*) return 1 ;; esac
  return 0
}

# nucleo_ctx <transcript>: "tokens pct", con pct sobre el airbag (ventana − 33 000, la línea en la
# que compacta solo). Nada si el transcript no trae uso. La ventana es min(la del modelo, el env), como
# en el binario: el modelo tiene 1M con [1m] en el id (ANTHROPIC_MODEL o `model` de settings.json) o si es
# de una familia que lo trae por defecto (opus 4.7+, opus 5+, fable, mythos, sonnet 5+); si no, 200 000.
# El id del último assistant del transcript cuenta también (settings.json suele traer un alias pelado
# como «opus», que no dice la ventana). Un env mayor no sube el airbag; sin env (o no numérico) manda la ventana del modelo.
nucleo_ctx() {
  local w=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-} m=200000 t tm id s
  # Sin `timeout`: 40 líneas no cuelgan a jq, y en coreutils de Rust arrancarlo cuesta ~100 ms.
  read -r t tm < <(tail -n 40 "$1" 2>/dev/null \
    | jq -rR 'fromjson? | select(.type=="assistant" and .message.usage!=null) | .message
        | ((.usage.input_tokens//0)+(.usage.cache_read_input_tokens//0)+(.usage.cache_creation_input_tokens//0)) as $n
        | select($n>0) | "\($n) \(.model // "-")"' 2>/dev/null \
    | tail -1)
  [ -n "$t" ] || return 0
  id=$tm
  # Un id configurado cuenta entero si el transcript no trae modelo; si lo trae, solo por su [1m]
  # y solo si nombra ese modelo (haiku en el transcript con opus[1m] en settings sigue en 200k).
  for s in "${ANTHROPIC_MODEL:-}" "$(sed -n 's/.*"model"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$HOME/.claude/settings.json" 2>/dev/null)"; do
    case $tm:$s in -:?* | *"${s%%\[1m\]*}"*:*'[1m]'*) id="$id $s" ;; esac
  done
  case $id in
    *'[1m]'* | *opus-4[-.][7-9]* | *opus-[5-9]* | *fable* | *mythos* | *sonnet-[5-9]*) m=1000000 ;;
  esac
  case "$w" in ''|*[!0-9]*) w=$m;; esac
  [ "$w" -gt "$m" ] && w=$m
  [ "$w" -gt 33000 ] || w=$m
  printf '%s %s\n' "$t" "$((t * 100 / (w - 33000)))"
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
      # Repetido: solo entra si la primera copia quedó vacía (plantilla con «## Pendientes» y, después, el
      # «## Pendientes y riesgos» de /handoff); con contenido sigue ganando la primera. Los marcadores
      # <!-- … --> de la plantilla no cuentan como contenido (si no, «Encargo original» y «Plan» del
      # handoff se descartaban como repetidos de un Objetivo y un Plan que solo tenían el marcador).
      if (c == "" || (visto[c] && con[c])) { fuera++; next }
      visto[c] = 1; actual = c; coment = 0
      if (usado + length($0) > tope) { omitidas = omitidas " «" substr(t, 1, 80) "»"; next }
      viva = 1; sale($0); next
    }
    viva {
      resto = sec - dentro; if (tope - usado < resto) resto = tope - usado
      if (coment) { if (index($0, "-->")) coment = 0 }
      else if ($0 ~ /^[ \t]*<!--/) { if (!index($0, "-->")) coment = 1; else { t2 = $0; sub(/.*-->/, "", t2); if (t2 ~ /[^ \t]/) con[actual]++ } }
      else if ($0 ~ /[^ \t]/) con[actual]++
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
