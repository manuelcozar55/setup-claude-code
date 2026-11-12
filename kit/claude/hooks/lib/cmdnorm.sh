#!/bin/bash
# cmdnorm.sh — normalización común de comandos Bash para los guards (block-dangerous-commands,
# destructive-guard, branch-guard, secret-guard). Se carga con `.`, no se ejecuta.
#
# Por qué existe: cada guard leía el TEXTO del comando con su propia regex, y cada una fallaba por
# separado ante las mismas grafías: un `#` dentro de comillas cortaba el escaneo, la `\`+salto de
# línea partía el pipe-a-shell, y `git -C dir`, `sudo git`, `/usr/bin/git` o `git "push"` sacaban el
# subcomando del patrón. Una sola pasada de awk resuelve las cuatro cosas y los guards deciden sobre
# el resultado.
#
# cmdn_parse "$COMMAND" deja dos cosas:
#   CMDN_TEXT  el comando con las continuaciones `\`+NL unidas y los comentarios (fuera de comillas)
#              quitados, comillas INTACTAS: es lo que se alimenta a las regex heredadas.
#   CMDN_SEGS  un comando simple por elemento, partido en ; & | ( ) ` y saltos de línea FUERA de
#              comillas. Formato: <opciones globales de git, separadas por \035> US <cmd> US <arg>…
#              con US=\037 entre tokens. Los tokens van descomillados; los prefijos (sudo, env,
#              command, nice, timeout N, VAR=x, { ! if then…) y la ruta del ejecutable se han quitado,
#              y las opciones globales de git (-C dir, -c k=v, --git-dir…) salen del subcomando.
#   cmdn_fields "$seg" lo trocea en el array T: T[0]=opciones globales, T[1]=cmd, T[2…]=args.
#
# LÍMITE (docs/05-security.md): se normaliza el texto, no el argv que el shell expandirá. `F=-rf; rm $F`,
# `eval`, `bash -c "$X"` y las sustituciones siguen fuera de alcance; la última barrera es la capa de
# permisos de Claude Code.
#
# Solo awk POSIX (mawk y gawk dan lo mismo): sin gensub, sin arrays de arrays.

# shellcheck disable=SC2034  # CMDN_TEXT, CMDN_SEGS y CMDN_GS los consumen los guards que cargan esta lib.
CMDN_US=$'\037'
CMDN_GS=$'\035'
CMDN_RS=$'\036'
CMDN_FS=$'\034'

# shellcheck disable=SC2016  # el programa awk va literal: nada se expande en bash.
CMDN_AWK='
function base(w) { if (w != "/" && w ~ /\//) sub(/.*\//, "", w); return w }
function endtok() { if (have) { nt++; toks[nt] = tok } tok = ""; have = 0 }
function argopt(b, o) {
  if (b == "sudo") return (o == "-u" || o == "-g" || o == "-h" || o == "-p" || o == "-C" || o == "-r" || o == "-t" || o == "-U" || o == "--user" || o == "--group")
  if (b == "env") return (o == "-u" || o == "-C" || o == "-S" || o == "--unset" || o == "--chdir")
  if (b == "nice") return (o == "-n" || o == "--adjustment")
  if (b == "timeout") return (o == "-s" || o == "-k" || o == "--signal" || o == "--kill-after")
  if (b == "ionice") return (o == "-c" || o == "-n" || o == "-p" || o == "-P" || o == "-u")
  if (b == "doas") return (o == "-u" || o == "-C")
  return 0
}
function gitopt(o) { return (o == "-C" || o == "-c" || o == "--git-dir" || o == "--work-tree" || o == "--namespace" || o == "--super-prefix" || o == "--config-env" || o == "--attr-source") }
function clean_opt(t) { return (t ~ /^-[A-Za-z0-9]+$/ || t ~ /^--[A-Za-z0-9][A-Za-z0-9-]*$/ || t == "--") }
function redir(t) { return (t ~ /^[0-9]*[<>]/) }
function redir_alone(t) { return (t ~ /^[0-9]*(>>?[|]?|<<?)$/) }
function push(body) { qn++; queue[qn] = body }

# Contexto cerrado (regla de las pruebas de exencion): una prueba solo vale si la linea entera es UNA tuberia de la orden exenta y
# consumidores de la lista cerrada, con opciones de una lista cerrada y escritura solo a ficheros de documento. Cualquier otra cosa
# (un separador, un prefijo, una opcion desconocida, un destino que un interprete o make leeria) deja nosimple=1 y manda la base.
# Destino de una escritura que NO es codigo ni configuracion de nadie: extension de documento, fuera de .git, .claude, .husky,
# .github y de los ficheros que un agente lee como instrucciones.
function docext(t,   b) {
  if (t == "/dev/null" || t == "/dev/stdout" || t == "/dev/stderr") return 1
  if (t ~ /(^|\/)\.(git|claude|husky|github)(\/|$)/) return 0
  b = base(t)
  if (b == "CLAUDE.md" || b == "AGENTS.md" || b == "SKILL.md" || b == "MEMORY.md") return 0
  return ((t ~ /\.(md|txt|log|rst|csv|tsv)$/ || b == ".gitignore") && t !~ /[$`*?{[~\\]/)
}
# Opcion (token que empieza por -) de la lista cerrada de inocuas de la orden b: una opcion que ejecuta (--pre, --pager, -O, -P de
# man, --hostname-bin), que escribe (-o, --output) o desconocida no esta.
function optok(b, t,   nm, i, l) {
  if (t == "-" || t == "--" || t ~ /^-[0-9]+$/) return 1
  if (t ~ /^--[A-Za-z][A-Za-z0-9-]*(=.*)?$/) { nm = t; sub(/=.*/, "", nm); return (nm in longs) }
  if ((b in grepf) && t ~ /^-e./) return 1
  if (b == "awk" && t ~ /^-F./) return 1
  if (t ~ /^-[A-Za-z0-9]+$/) {
    l = lett[b]
    for (i = 2; i <= length(t); i++) if (index(l, substr(t, i, 1)) == 0 && substr(t, i, 1) !~ /[0-9]/) return 0
    return 1
  }
  return 0
}

# Cuerpo de un `"$( )"` que es SOLO un `cat` con heredoc de delimitador entrecomillado: su salida es el texto literal del heredoc (delimitador entre comillas, sin
# expansion) y no cambia nada de la linea: no quita el contexto cerrado (es la forma habitual del mensaje de commit).
function catdoc(b,   d, r, p, t) {
  if (!match(b, "^[ \t\n]*cat[ \t]+<<-?[ \t]*\047[A-Za-z_][A-Za-z0-9_]*\047[ \t]*\n")) return 0
  t = substr(b, 1, RLENGTH); r = substr(b, RLENGTH + 1)
  sub(/^[^\047]*\047/, "", t); sub(/\047.*$/, "", t); d = t
  r = "\n" r "\n"
  p = index(r, "\n" d "\n")
  if (!p) return 0
  return (substr(r, p + length(d) + 2) ~ /^[ \t\n]*$/)
}

# Palabra delimitadora de un heredoc que empieza en p (tras `<<`): deja HDQ (entrecomillada o con barra) y HDEND (indice tras ella).
function hdword(s, p,   n, q, w, ch) {
  n = length(s); w = ""; HDQ = 0
  if (substr(s, p, 1) == "-") p++
  while (substr(s, p, 1) == " " || substr(s, p, 1) == "\t") p++
  ch = substr(s, p, 1)
  if (ch == "\047" || ch == "\"") {
    HDQ = 1; q = ch; p++
    while (p <= n && substr(s, p, 1) != q) { w = w substr(s, p, 1); p++ }
    p++
  } else {
    if (ch == "\\") { HDQ = 1; p++ }
    while (p <= n) {
      ch = substr(s, p, 1)
      if (ch == " " || ch == "\t" || ch == "\n" || ch == ";" || ch == "|" || ch == "&" || ch == "<" || ch == ">" || ch == "(" || ch == ")") break
      w = w ch; p++
    }
  }
  HDEND = p
  return w
}

# Indice del `)` que cierra un `$(` cuyo cuerpo empieza en i (n+1 si no cierra: el resto es el cuerpo). Respeta comillas,
# `$(` anidados, parentesis de subshell y heredocs (el cuerpo de un heredoc puede llevar `)` sueltos).
function subend(s, i,   n, d, c, j, hw, e, p, rest) {
  n = length(s); d = 0; hw = ""
  for (j = i; j <= n; j++) {
    c = substr(s, j, 1)
    if (c == "\\") { j++; continue }
    if (c == "\047") { e = index(substr(s, j + 1), "\047"); if (!e) return n + 1; j += e; continue }
    if (c == "\"") {
      for (j++; j <= n; j++) {
        c = substr(s, j, 1)
        if (c == "\\") { j++; continue }
        if (c == "\"") break
        if (c == "$" && substr(s, j + 1, 1) == "(") j = subend(s, j + 2)
      }
      continue
    }
    if (c == "`") { e = index(substr(s, j + 1), "`"); if (!e) return n + 1; j += e; continue }
    if (c == "$" && substr(s, j + 1, 1) == "(") { j = subend(s, j + 2); continue }
    if (c == "(") { d++; continue }
    if (c == ")") { if (d == 0) return j; d--; continue }
    if (c == "<" && substr(s, j + 1, 1) == "<" && substr(s, j + 2, 1) != "<" && substr(s, j - 1, 1) != "<") {
      hw = hdword(s, j + 2)
      if (hw != "") { j = HDEND - 1 }
      continue
    }
    if (c == "\n" && hw != "") {
      rest = substr(s, j); p = index(rest, "\n" hw "\n")
      if (p) j = j + p - 1 + length(hw)
      hw = ""
    }
  }
  return n + 1
}

# Cuerpos de `$( )` y de comillas invertidas dentro de un texto que el shell expande (comillas dobles, heredoc sin comillas):
# se encolan para analizarlos como ordenes.
function scansubs(s,   n, j, c, e) {
  n = length(s)
  for (j = 1; j <= n; j++) {
    c = substr(s, j, 1)
    if (c == "\\") { j++; continue }
    if (c == "$" && substr(s, j + 1, 1) == "(") { e = subend(s, j + 2); push(substr(s, j + 2, e - (j + 2))); j = e; continue }
    if (c == "`") { e = index(substr(s, j + 1), "`"); if (!e) e = n - j + 1; push(substr(s, j + 1, e - 1)); j += e; continue }
  }
}

# Los argumentos que son PROSA (un mensaje de commit, el patron de un grep, el texto de un echo) no son ordenes. Devuelve
# los argumentos del comando simple que empieza en toks[k] con esa prosa quitada. mode 0: solo lo que NUNCA se ejecuta
# (el valor de -m de git, el cuerpo de un gh pr create); mode 1: ademas los argumentos de echo, printf, grep, sed...
function render(k, b, mode,   j, sj, t, out, drop, subc, keepnext, gh) {
  out = ""; drop = 0
  if (b == "git") {
    sj = k + 1
    while (sj <= nt && toks[sj] ~ /^-/) sj += (gitopt(toks[sj]) && sj < nt) ? 2 : 1
    subc = toks[sj]
    if (sj > k + 1) nosimple = 1
    for (j = k + 1; j <= nt; j++) {
      t = toks[j]
      if (j <= sj) { out = out " " t; continue }
      if ((subc in dispsub) && t ~ /^-./ && t != "--" && !optok("git", t)) nosimple = 1
      if (subc in msgsub) {
        if (drop) { drop = 0; continue }
        if (t ~ /^-[A-Za-z]*m$/ || t == "--message") { out = out " " t; drop = 1; continue }
        if (t ~ /^--message=/) { out = out " --message"; continue }
        if (match(t, /^-[A-Za-z]*m/)) { out = out " " substr(t, 1, RLENGTH); continue }
        if (t ~ /^-./ && t != "--" && !optok("gitmsg", t)) nosimple = 1
      } else if (subc in dispsub) {
        if (clean_opt(t) || redir(t)) out = out " " t
        continue
      }
      out = out " " t
    }
    return out
  }
  if (b == "gh") {
    for (j = k + 1; j <= nt; j++) {
      t = toks[j]
      if (drop) { drop = 0; continue }
      if (t == "-b" || t == "--body" || t == "-t" || t == "--title" || t == "-m" || t == "--message" || t == "--notes" || t == "--description") { out = out " " t; drop = 1; continue }
      if (t ~ /^--(body|title|message|notes|description)=/) { sub(/=.*/, "", t) }
      if (t ~ /^-./ && t != "--" && t !~ /^(-[btmBdH]|--(body|title|message|notes|description|base|head|draft|fill))$/) nosimple = 1
      out = out " " t
    }
    return out
  }
  if (mode == 1 && (b in prose)) {
    keepnext = 0
    for (j = k + 1; j <= nt; j++) {
      t = toks[j]
      if (keepnext) { keepnext = 0; out = out " " t; continue }
      if (redir(t)) { out = out " " t; if (redir_alone(t)) keepnext = 1; continue }
      if (b == "sed" || b == "awk" || b == "gawk" || b == "mawk" || b == "nawk") {
        # Un programa de awk con system/getline/pipe y un script de sed con el comando `e` o la bandera `e` EJECUTAN: no son prosa.
        if (t !~ /[ \t\n]/ || (b == "sed" ? t ~ /(^|[^A-Za-z_])e([ \t;}]|$)|\/[A-Za-z]*e[A-Za-z]*([ \t;}]|$)/ : t ~ /system|getline|popen|[|]/)) out = out " " t
        continue
      }
      if (clean_opt(t)) out = out " " t
    }
    return out
  }
  for (j = k + 1; j <= nt; j++) out = out " " toks[j]
  return out
}

function emit(   k, w, b, o, g, line, j, kd, pre, a, ok, psh, shl, sp) {
  k = 1
  while (k <= nt) {
    w = toks[k]; b = base(w)
    if (w ~ /^[A-Za-z_][A-Za-z0-9_]*=/) { k++; continue }
    if (b in ctl) { k++; continue }
    if (b in wrap) {
      k++
      while (k <= nt && toks[k] ~ /^-/) {
        o = toks[k]; k++
        if (o == "--") break
        if (argopt(b, o) && k <= nt) k++
      }
      if (b == "timeout" && k <= nt) k++
      continue
    }
    break
  }
  if (k > 1) nosimple = 1
  for (j = 1; j <= nt; j++) {
    a = toks[j]
    if (a ~ /^[0-9&]*>>?[|]?/) {
      o = a; sub(/^[0-9&]*>>?[|]?/, "", o)
      if (o == "" && j < nt) o = toks[j + 1]
      if (o !~ /^&[0-9-]*$/ && !docext(o)) nosimple = 1
    }
  }
  if (k <= nt) {
    b = base(toks[k])
    if ((b in lett) && b != "git") for (j = k + 1; j <= nt; j++) { if (toks[j] == "--" || ((b == "echo" || b == "printf") && toks[j] !~ /^-/)) break; if (toks[j] ~ /^-./ && !optok(b, toks[j])) nosimple = 1 }
    if (b == "tee") for (j = k + 1; j <= nt; j++) if (toks[j] !~ /^-/ && !docext(toks[j])) nosimple = 1
    if (b == "uniq" || b == "xxd") { o = 0; for (j = k + 1; j <= nt; j++) if (toks[j] !~ /^-/) o++; if (o > 1) nosimple = 1 }
    if (b == "cd" || b == "pushd" || b == "popd") nosimple = 1
  }
  kd = (forceS || subdepth > 0 || btick) ? "S" : "P"
  for (j = 1; j <= nt; j++) gsub(/\n/, " ", toks[j])
  nseg++
  sepn[nseg] = pend; pend = ""
  # Un receptor de pipe solo cierra el contexto si es un consumidor de texto de la lista cerrada (`| less`, `| gh api`, `| git var` no).
  if (k <= nt && sepn[nseg] ~ /[|]/ && (!(b in lett) || (b == "git" && !(toks[k + 1] in dispsub)))) nosimple = 1
  pre = ""
  for (j = 1; j < k && j <= nt; j++) pre = pre (pre == "" ? "" : " ") toks[j]
  segline[nseg] = ""; segcmd[nseg] = ""; segshell[nseg] = 0; segpsh[nseg] = 0
  if (k > nt) {
    exA[nseg] = pre; exB[nseg] = pre
    # Un receptor de pipe sin orden que se pueda leer (`| env -S sh`, `| X=1`): el consumidor es desconocido.
    sp = sepn[nseg]; gsub(/[|][|]/, "", sp)
    if (nt > 0 && !(nt == 1 && (toks[1] in ctl)) && (sp ~ /[|]/ || sepn[nseg] ~ /@/)) segpsh[nseg] = 1
    return
  }
  b = base(toks[k]); g = ""
  exA[nseg] = pre (pre == "" ? "" : " ") toks[k] render(k, b, 0)
  exB[nseg] = (kd == "S") ? exA[nseg] : pre (pre == "" ? "" : " ") toks[k] render(k, b, 1)
  segcmd[nseg] = b
  # Un comando simple `shell [opciones sin -c]` lee su programa de la entrada; ssh, xargs y `. /dev/stdin` tambien lo ejecutan.
  shl = (b in shells) || b == "ssh"
  ok = 1
  for (j = k + 1; j <= nt; j++) { a = toks[j]; if (b in shells) { if (!(a == "-" || (a ~ /^-/ && a !~ /^-.*c/))) ok = 0 } if (a in shells) shl = 1 }
  psh = ((b in shells) && ok) || b == "ssh" || b == "xargs" || b == "at" || b == "batch" || b == "crontab" || ((b == "source" || b == ".") && toks[k + 1] == "/dev/stdin")
  # Regla estructural: el texto que llega por una tuberia (o a un >( )) solo es DATO si el receptor esta en la lista cerrada de
  # consumidores de texto; cualquier otro (python3, awk, parallel, busybox sh, un ejecutable desconocido, $X...) lo puede ejecutar.
  sp = sepn[nseg]; gsub(/[|][|]/, "", sp)
  if ((sp ~ /[|]/ || sepn[nseg] ~ /@/) && !(b in inert)) psh = 1
  # `<( )` alimenta a la orden que lo precede: si esa no es un consumidor de texto (`source <(echo ...)`, `python3 <(...)`), el texto es codigo.
  if (sepn[nseg] ~ /@/ && nseg > 1 && !(segcmd[nseg - 1] in inert)) psh = 1
  segshell[nseg] = shl; segpsh[nseg] = psh
  k++
  if (b == "git") {
    while (k <= nt && toks[k] ~ /^-/) {
      o = toks[k]
      if (gitopt(o) && k < nt) { g = g (g == "" ? "" : GS) o GS toks[k + 1]; k += 2 }
      else { g = g (g == "" ? "" : GS) o; k++ }
    }
    if (g != "") nosimple = 1
  }
  sq = sepn[nseg]; gsub(/@/, "", sq)
  line = kd sq FSEP g US b
  for (j = k; j <= nt; j++) line = line US toks[j]
  segline[nseg] = line
}
function endseg() { endtok(); if (nt > 0) emit(); nt = 0 }

# Cuerpos de los heredocs pendientes de la linea que acaba de cerrarse. Un cuerpo es DATO (se salta) salvo que lo consuma un
# shell, el segmento siguiente por pipe sea un shell, o sea un interprete y el codigo ejecute algo; sin delimitador de cierre
# se trata como ordenes (falla cerrado). Si el delimitador no va entrecomillado, los `$( )` del cuerpo si se expanden: se encolan.
function heredocs(s, i, n,   h, o, m, body, rest, p, e, w, isdata, bs, lt, L) {
  for (h = 1; h <= hdn; h++) {
    w = hdw[h]; o = hdo[h]
    rest = substr(s, i - 1)
    if (hddash[h]) {
      e = 0; p = i
      while (p <= n) {
        m = index(substr(s, p), "\n"); lt = (m ? substr(s, p, m - 1) : substr(s, p)); L = length(lt)
        sub(/^\t+/, "", lt)
        if (lt == w) { e = p + L - 1; break }
        if (!m) break
        p += m
      }
      if (!e) return i
      bs = p
    } else {
      p = index(rest, "\n" w "\n")
      if (p) { bs = i - 1 + p; e = i - 2 + p + length(w) }
      else if (substr(rest, length(rest) - length(w)) == "\n" w) { bs = n - length(w) + 1; e = n }
      else return i
    }
    body = substr(s, i, bs - i)
    # Un cuerpo es DATO solo si lo recibe un consumidor de texto de la lista cerrada (cat, tee, git...) y no lo leen un shell ni
    # un receptor de pipe que no sea de texto. Un interprete (`python3 - <<EOF`) o una orden desconocida NO lo prueban. Lo que
    # venga DESPUES en la orden (`cat > a.sh <<EOF ... EOF` y luego `bash a.sh`) se mira al final: hdb/hdo quedan pendientes.
    isdata = 1
    if (!(o <= nseg && (segcmd[o] in inert))) isdata = 0
    if (o <= nseg && segshell[o]) isdata = 0
    for (m = o + 1; m <= nseg; m++) if (segpsh[m]) isdata = 0
    if (!isdata) return i
    nhb++; hdb[nhb] = body; hdo2[nhb] = o
    if (!hdq[h]) scansubs(body)
    txt = txt substr(s, i, e - i + 1)
    i = e + 1
  }
  return i
}

function parse(s, ismain,   n, i, j, k, rest, c, d, nx, q, start, closed, pv, e, w) {
  txt = ""; nt = 0; tok = ""; have = 0; openq = 0; hdn = 0; subdepth = 0; btick = 0
  pend = ismain ? "" : ";"
  forceS = !ismain
  n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") {
      nx = substr(s, i + 1, 1)
      if (nx == "\n") { i += 2; continue }
      if (i == n) { tok = tok c; txt = txt c; have = 1; i++; continue }
      tok = tok nx; have = 1; txt = txt c nx; i += 2; continue
    }
    if (c == "$") {
      nx = substr(s, i + 1, 1)
      if ((nx == "\047" || nx == "\"") && !((i + 1) in skip)) {
        # Formas $-comilla (ANSI-C y locale): bash quita el `$` y las comillas. Si lleva una barra invertida dentro, el valor
        # real no se puede calcular aqui: el `$` se queda en el token y el guard de git push lo trata como sospechoso.
        pv = 0
        if (nx == "\047") for (j = i + 2; j <= n && substr(s, j, 1) != nx; j++) if (substr(s, j, 1) == "\\") { pv = 1; break }
        if (pv) tok = tok c
        txt = txt c; i++; continue
      }
    }
    if ((c == "\047" || c == "\"") && !(i in skip)) {
      start = i; q = c; txt = txt c; i++; have = 1; closed = 0
      while (i <= n) {
        d = substr(s, i, 1)
        if (d == q) { closed = 1; txt = txt d; i++; break }
        if (q == "\"" && d == "\\") {
          nx = substr(s, i + 1, 1)
          if (nx == "\n") { i += 2; continue }
          if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`") { tok = tok nx; txt = txt d nx; i += 2; continue }
        }
        if (q == "\"" && d == "$" && substr(s, i + 1, 1) == "(") {
          # Sustitucion dentro de comillas dobles: el shell la ejecuta. Se copia entera al token y su cuerpo se encola.
          e = subend(s, i + 2)
          push(substr(s, i + 2, e - (i + 2)))
          if (ismain && catdoc(substr(s, i + 2, e - (i + 2)))) neutral++
          w = substr(s, i, e - i + 1); tok = tok w; txt = txt w; i = e + 1; continue
        }
        if (q == "\"" && d == "`") {
          e = index(substr(s, i + 1), "`")
          if (!e) e = n - i + 1
          push(substr(s, i + 1, e - 1))
          w = substr(s, i, e + 1); tok = tok w; txt = txt w; i += e + 1; continue
        }
        tok = tok d; txt = txt d; i++
      }
      if (!closed) { openq = start; return }
      continue
    }
    if (c == "#" && !have) {
      while (i <= n && substr(s, i, 1) != "\n") i++
      continue
    }
    if (c == " " || c == "\t") { endtok(); txt = txt c; i++; continue }
    if (c == "<" && substr(s, i + 1, 1) == "<" && substr(s, i + 2, 1) != "<" && substr(s, i - 1, 1) != "<") {
      w = hdword(s, i + 2)
      if (w != "") { hdn++; hdw[hdn] = w; hdq[hdn] = HDQ; hddash[hdn] = (substr(s, i + 2, 1) == "-"); hdo[hdn] = nseg + 1 }
    }
    if (c == "\n") {
      endtok(); endseg(); txt = txt c; i++
      if (pend !~ /;$/) pend = pend ";"
      if (hdn > 0) { i = heredocs(s, i, n); hdn = 0 }
      continue
    }
    if (c == ";" || c == "|" || c == "(" || c == ")" || c == "`") {
      pv = (c == "(" && tok ~ /^[0-9]*[<>]$/)
      endseg(); txt = txt c; i++
      if (c == "(") subdepth++
      if (c == ")" && subdepth > 0) subdepth--
      if (c == "`") btick = !btick
      pend = pend (pv ? "@" : "") c
      continue
    }
    if (c == "&") {
      pv = substr(s, i - 1, 1); nx = substr(s, i + 1, 1)
      if (pv == ">" || pv == "<" || nx == ">") { tok = tok c; have = 1 }
      else { endseg(); pend = pend c }
      txt = txt c; i++; continue
    }
    tok = tok c; have = 1; txt = txt c; i++
  }
  endseg()
}
# Una pasada por texto: el comando de la persona y, encolados, los cuerpos de sus sustituciones.
function run(s, ismain,   t, b0, q0, n0) {
  b0 = nseg; q0 = qn; n0 = neutral
  delete skip
  for (t = 0; t < 400; t++) {
    nseg = b0; qn = q0; neutral = n0
    parse(s, ismain)
    if (!openq) break
    skip[openq] = 1
  }
  if (openq) {
    nseg = b0; qn = q0
    if (ismain) { txt = s; unparsed = 1 }
    else { nseg++; sepn[nseg] = ";"; exA[nseg] = s; exB[nseg] = s; segline[nseg] = ""; segcmd[nseg] = ""; segshell[nseg] = 0; segpsh[nseg] = 0 }
  }
  if (ismain) { maintxt = txt; mainlast = nseg; maintail = pend; gsub(/;/, "", maintail) }
}
BEGIN {
  RS = "\001"; US = "\037"; GS = "\035"; FSEP = "\034"
  split("sudo doas env command nice nohup time exec builtin stdbuf ionice setsid timeout", arr, " "); for (x in arr) wrap[arr[x]] = 1
  split("{ ! then do else elif if while until", arr, " "); for (x in arr) ctl[arr[x]] = 1
  split("sh bash zsh dash ksh ash fish mksh ksh93", arr, " "); for (x in arr) shells[arr[x]] = 1
  split("python python2 python3 perl ruby node nodejs php lua deno bun Rscript tclsh pwsh", arr, " "); for (x in arr) interps[arr[x]] = 1
  split("echo printf grep egrep fgrep rg ag ack zgrep sed awk gawk mawk nawk man type which test [", arr, " "); for (x in arr) prose[arr[x]] = 1
  # Consumidores de TEXTO inocuos (lista CERRADA): ninguno ejecuta lo que lee. Un receptor que no esta aqui (un interprete, un
  # envoltorio, un ejecutable desconocido, una variable) NO prueba que el texto de un echo o de un heredoc sea dato.
  split("cat tee grep egrep fgrep rg ag ack zgrep wc head tail sort uniq cut tr jq less more column nl fold tac rev paste expand unexpand comm diff cmp xxd od hexdump base64 md5sum sha1sum sha256sum cksum basename dirname git gh echo printf true :", arr, " "); for (x in arr) inert[arr[x]] = 1
  # Ordenes que pueden seguir a un heredoc de texto sin convertirlo en codigo: las inocuas y las que no ejecutan nada propio.
  split("ls pwd cd mkdir touch chmod cp mv ln stat file date whoami hostname uname id test [ false sleep fi done esac }", arr, " "); for (x in arr) benign[arr[x]] = 1
  for (x in inert) benign[x] = 1
  split("commit tag stash merge notes revert", arr, " "); for (x in arr) msgsub[arr[x]] = 1
  split("log show diff grep blame shortlog rev-list", arr, " "); for (x in arr) dispsub[arr[x]] = 1
  # Opciones inocuas por orden (lista CERRADA, letras de las opciones cortas) y nombres de opciones largas inocuas. Lo que ejecuta
  # (--pre, --pager, -O, man -P), escribe (-o, --output, sed -i) o no esta aqui quita la prueba y manda la base.
  g0 = "ivnrRlLcwxFEGHhsqoaIzUuTbmABCSVyZPgtjkfeMlN"
  lett["grep"] = g0; lett["egrep"] = g0; lett["fgrep"] = g0; lett["zgrep"] = g0; lett["rg"] = g0; lett["ag"] = g0; lett["ack"] = g0
  split("grep egrep fgrep zgrep rg ag ack", arr, " "); for (x in arr) grepf[arr[x]] = 1
  lett["git"] = "pnvcwlLhHEFiIqsazUuTbmABCSGgkrxP"
  lett["sed"] = "nEerzsu"; lett["awk"] = "Fv"; lett["gawk"] = "Fv"; lett["mawk"] = "Fv"; lett["nawk"] = "Fv"
  lett["man"] = "kfwa"; lett["which"] = "a"; lett["type"] = "afptP"; lett["echo"] = "neE"; lett["printf"] = ""
  lett["test"] = "abcdefghLknoprstuwxzGOS"; lett["["] = lett["test"]
  lett["cat"] = "AbeEnstTuv"; lett["head"] = "cnqvz"; lett["tail"] = "cnqvzf"; lett["wc"] = "clmwL"
  lett["sort"] = "bdfgiMhnRrsuVzckmt"; lett["uniq"] = "cdDfiuszw"; lett["cut"] = "bcdfnsz"; lett["tr"] = "cdst"
  lett["jq"] = "CcenrRsSaj"; lett["column"] = "tsnxecwo"; lett["nl"] = "bdfhilnpsvw"
  lett["fold"] = "bsw"; lett["tac"] = "brs"; lett["rev"] = ""; lett["paste"] = "dsz"; lett["expand"] = "it"; lett["unexpand"] = "at"
  lett["comm"] = "123iz"; lett["diff"] = "uqrcbBwiyEZaNsTp"; lett["cmp"] = "bilns"; lett["xxd"] = "abcEgiluprRs"
  lett["od"] = "AjNtvxcodabfhilz"; lett["hexdump"] = "bcCdnosvx"; lett["base64"] = "diw"
  lett["md5sum"] = "bctwzq"; lett["sha1sum"] = "bctwzq"; lett["sha256sum"] = "bctwzq"; lett["cksum"] = "ar"
  lett["basename"] = "asz"; lett["dirname"] = "z"; lett["tee"] = "ai"; lett["true"] = ""; lett[":"] = ""; lett["rm"] = "rRfvdiI"; lett["gitmsg"] = "amqvs"
  split("--color --colour --ignore-case --line-number --count --recursive --word-regexp --fixed-strings --extended-regexp --files-with-matches --files-without-match --invert-match --quiet --silent --no-filename --with-filename --null --text --max-count --regexp --include --exclude --type --glob --after-context --before-context --context --only-matching --no-messages --hidden --follow --smart-case --case-sensitive --no-ignore --oneline --graph --stat --name-only --name-status --decorate --all --no-color --abbrev-commit --shortstat --numstat --cached --staged --merges --no-merges --first-parent --reverse --patch --full-history --pretty --format --since --until --after --before --author --committer --grep --date --abbrev --diff-filter --arg --argjson --raw-output --compact-output --slurp --tab --indent --sort-keys --raw-input --null-input --exit-status --join-output --slurpfile --rawfile --args --jsonargs --regexp-extended --separate --null-data --numeric-sort --unique --number --show-all --squeeze-blank --show-ends --show-tabs --lines --bytes --verbose --words --chars --append --apropos --whatis --where --force --dir --amend --no-edit --signoff --allow-empty --annotate", arr, " "); for (x in arr) longs[arr[x]] = 1
}
{ src = src $0 RS }
function drain() { while (qi < qn && qi < 200 && !unparsed) { qi++; run(queue[qi], 0) } }
END {
  sub(/\001$/, "", src)
  nseg = 0; qn = 0; qi = 0; unparsed = 0; nhb = 0; hp = 1
  run(src, 1)
  drain()
  # Los cuerpos de heredoc dados por dato se confirman ahora que se ve la orden entera: si despues viene algo que no es inocuo
  # (un shell, un interprete, `./a.sh`), el cuerpo pasa a ser codigo y se analiza como ordenes.
  while (hp <= nhb && !unparsed) {
    ok = 1
    for (m = hdo2[hp] + 1; m <= nseg; m++) if (!(segcmd[m] in benign)) ok = 0
    if (!ok) push(hdb[hp])
    hp++
    drain()
  }
  if (unparsed) { ex = src; segs = ""; psh = 1 }
  else {
    psh = 0
    for (m = 1; m <= nseg; m++) if (segpsh[m]) psh = 1
    ex = ""; segs = ""
    for (m = 1; m <= nseg; m++) {
      sq = sepn[m]; gsub(/@/, "", sq)
      ex = ex sq (psh ? exA[m] : exB[m])
      if (m == mainlast) ex = ex maintail
      if (segline[m] != "") segs = segs segline[m] "\n"
    }
    # Pasado el tope de cuerpos encolados el resto no se analiza: se deja como texto de orden (falla cerrado).
    for (m = qi + 1; m <= qn; m++) ex = ex ";" queue[m]
  }
  # Contexto cerrado: una sola tuberia, sin sustituciones, subshells, prefijos ni escrituras a codigo. Sin el, ninguna prueba de
  # exencion vale: el texto vuelve entero (como lo veia la base) y los guards de ordenes no eximen nada.
  simple = (!unparsed && qn == neutral && !nosimple && maintail == "")
  for (m = 1; m <= mainlast && simple; m++) {
    if (m == 1) { if (sepn[m] != "") simple = 0 }
    else if (sepn[m] != "|" && sepn[m] != "|&") simple = 0
  }
  if (!simple) ex = maintxt
  printf "%s\036%s\036%s\036%s\036%s", maintxt, ex, psh, simple + 0, segs
}
'

# Tope de tamano. Los guards son lineales (256 KB: peor caso medido ~4 s de CPU cada uno, y corren a la
# vez: con 2 nucleos rozan los 10 s de timeout; con 128 KB, ~2 s), pero un hook que pasa de su timeout
# NO bloquea: la herramienta se ejecuta. Por encima del tope el guard no se arriesga a quedarse sin
# tiempo y pide confirmacion, que es fallar CERRADO.
CMDN_MAX_BYTES=131072

# cmdn_oversize "$COMMAND": si pasa del tope imprime la decision `ask` y devuelve 0; si no, devuelve 1.
cmdn_oversize() {
  local LC_ALL=C
  (( ${#1} > CMDN_MAX_BYTES )) || return 1
  jq -n --arg r "Confirm: el comando pesa $(( ${#1} / 1024 )) KB (tope $(( CMDN_MAX_BYTES / 1024 )) KB): los guards no pueden analizarlo dentro de su timeout, y un guard que se pasa de tiempo deja ejecutar la herramienta. Escribe los contenidos grandes con la herramienta Write y ejecuta un comando corto." '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "ask",
      permissionDecisionReason: $r
    }
  }'
}

cmdn_parse() {
  local out rest
  CMDN_SEGS=(); CMDN_CWD=""; CMDN_EXEC=""; CMDN_PSH=1; CMDN_SIMPLE=0
  # Los cuatro bytes de control con los que el parser separa sus salidas (\034-\037) no pueden ir en el comando: un \036 propio
  # desplazaria texto, EXEC y segmentos. Bash no los trata como separador, asi que pasan a espacio.
  set -- "${1//[$'\034\035\036\037']/ }"
  if ! out=$(awk "$CMDN_AWK" <<<"$1" 2>/dev/null) || [[ $out != *"$CMDN_RS"* ]]; then
    CMDN_TEXT=$1; CMDN_EXEC=$1; [[ -n ${CMDN_LINE_SET:-} ]] || { CMDN_LINE_SIMPLE=0; CMDN_LINE_SET=1; }; return 1
  fi
  # `${out%%…*}` y `${out#*…}` prueban cada longitud de prefijo: cuadráticos (64 KB ≈ 1,5 s de CPU,
  # el timeout del hook corre en abierto). `read` parte en el primer separador en una pasada.
  IFS=$CMDN_RS read -r -d '' CMDN_TEXT CMDN_EXEC CMDN_PSH CMDN_SIMPLE rest <<<"$out"
  # CMDN_LINE_SIMPLE: el contexto cerrado de la orden PRINCIPAL (la primera que se analiza); los analisis de ordenes anidadas
  # (bash -c, ssh...) no lo cambian y por tanto nunca lo heredan.
  [[ -n ${CMDN_LINE_SET:-} ]] || { CMDN_LINE_SIMPLE=$CMDN_SIMPLE; CMDN_LINE_SET=1; }
  mapfile -t CMDN_SEGS <<<"$rest"
  while (( ${#CMDN_SEGS[@]} )) && [[ -z ${CMDN_SEGS[-1]} ]]; do
    unset 'CMDN_SEGS[-1]'
  done
  return 0
}

# cmdn_fields "$seg": T[0]=opciones globales de git, T[1]=cmd, T[2…]=args; T_KIND = P (orden) o S (dentro de una
# sustitución o un subshell); T_SEP = lo que separó este comando del anterior (`;`, `|`, `&&`, `(`…).
cmdn_fields() {
  local pre=${1%%"$CMDN_FS"*}
  T_KIND=${pre:0:1}; T_SEP=${pre:1}
  IFS=$CMDN_US read -r -a T <<<"${1#*"$CMDN_FS"}"
}

# cmdn_pipes_to_shell: 0 si el texto de un echo/printf (o de un heredoc) puede acabar EJECUTADO: algun receptor de una tuberia (o de un
# >( )) no es un consumidor de texto de la lista cerrada de cmdnorm (python3, awk, parallel, busybox sh, un ejecutable desconocido, $X,
# un shell que lee su programa de la entrada...). Entonces ese texto ES la orden y los guards ya no lo tratan como prosa: sin prueba
# de que es dato, manda lo que diria el analisis del texto entero. Lo calcula el parser (CMDN_PSH); si no pudo, es 1.
cmdn_pipes_to_shell() { (( CMDN_PSH )); }

# cmdn_code_inner "$arg" palabra: el argumento de `python -c`/`perl -e`... lleva el comando dentro de
# una llamada (`os.system('find . -delete')`, `subprocess.run(['git','push'])`). Comillas, corchetes,
# parentesis y comas pasan a espacios y se devuelve (en REPLY) desde la palabra: queda un comando
# normal que se puede volver a normalizar. Solo si el codigo llama a algo que ejecuta (system, popen,
# subprocess, exec): un `print('find . -delete')` sigue siendo prosa.
cmdn_code_inner() {
  [[ $1 == *system* || $1 == *popen* || $1 == *subprocess* || $1 == *exec* ]] || return 1
  local a=${1//[\'\"\[\]\(\),]/ }
  [[ $a == *"$2"* ]] || return 1
  REPLY="$2${a#*"$2"}"
}

# Sigue los `cd` de la orden para resolver con git el repo donde de verdad corre el siguiente
# comando. Se llama con T ya troceado; solo actúa sobre `cd dir` con dir existente.
cmdn_track_cd() {
  local d=${T[2]:-}
  [[ ${T[1]:-} == cd && -n $d && $d != -* ]] || return 0
  d=${d/#\~/$HOME}
  if [[ $d == /* ]]; then :; else d="${CMDN_CWD:-.}/$d"; fi
  [[ -d $d ]] && CMDN_CWD=$d
  return 0
}

# ── rm: qué ruta es sensible y cuál es un directorio de build conocido ───────────────────────────────────
# Compartido por block-dangerous-commands (deniega/pregunta) y destructive-guard (deniega): una sola
# definición, para que no se desalineen. El operando es un token ya descomillado de cmdn_fields.
# CMDN_SAFE_DIRS: los nombres de directorio de build o de cache que se pueden borrar (la lista cerrada de `cmdn_rm_proof`).
# CC_SAFE_DELETE_DIRS los cambia, separados por `:`.
CMDN_SAFE_DIRS=${CC_SAFE_DELETE_DIRS:-node_modules:dist:build:out:target:.cache:__pycache__:coverage:.next:.nuxt:.turbo:.parcel-cache:.svelte-kit:.pytest_cache:.mypy_cache:.ruff_cache:.tox:.venv:tmp}
IFS=':' read -ra CMDN_DIRS <<< "$CMDN_SAFE_DIRS"

# cmdn_path_norm "$ruta": en REPLY, la ruta sin `//`, sin `/./` y sin `/` ni `/.` finales (`/tmp//`, `/tmp/.` son `/tmp`).
cmdn_path_norm() {
  local p=$1
  while [[ $p == *//* ]]; do p=${p//\/\//\/}; done
  while [[ $p == */./* ]]; do p=${p//\/.\//\/}; done
  while [[ ${#p} -gt 1 && ( $p == */ || $p == */. ) ]]; do
    if [[ $p == */. ]]; then p=${p%.}; else p=${p%/}; fi
  done
  REPLY=$p
}

# shellcheck disable=SC2088,SC2016  # `~` y `$HOME` son el TEXTO del operando, no se expanden.
cmdn_sensitive_operand() {
  cmdn_path_norm "$1"; local p=$REPLY
  case $p in
    /|/[!a-z]*|/home*|/etc*|/usr*|/var*|/root*|/boot*|/lib*|/bin*|/sbin*|/dev*|/proc*|/sys*|/mnt*|/media*|/opt*|/srv*) return 0 ;;
    '~'*|..|../*|'$HOME'|'$HOME/'*|'${HOME}'|'${HOME}/'*|*/..|*/../*) return 0 ;;
  esac
  # Un solo componente absoluto (`/tmp`, `/data`) es el directorio entero, no un hijo suyo; igual `/tmp/*` y `/tmp/.*`: lo vacian.
  [[ $p == /* && ${p:1} != */* ]] && return 0
  [[ ( $p == /*/'*' || $p == /*/'.*' || $p == /*/'**' ) && ${p:1} != */*/* ]] && return 0
  return 1
}

# cmdn_not_link <directorio> <componente> [strict]: el componente, resuelto con el disco como esta, sigue siendo hijo directo del
# directorio (no es un enlace a otro sitio). strict: el propio directorio tampoco es un enlace (/tmp). Sin `realpath` no hay prueba.
cmdn_not_link() {
  command -v realpath >/dev/null 2>&1 || return 1
  local b r
  b=$(realpath -m -- "$1" 2>/dev/null) || return 1
  [[ -z ${3:-} || $b == "$1" ]] || return 1
  r=$(realpath -m -- "$1/$2" 2>/dev/null) || return 1
  [[ $r == "${b%/}/$2" ]]
}

# cmdn_rm_proof "$operando": PRUEBA POSITIVA de que un operando de `rm -rf` es inocuo (lista cerrada, nada se exime por no parecer
# peligroso). Devuelve 0 y deja el nombre de la prueba en REPLY; 1 si no la hay, y entonces manda el criterio de la base (denegar).
#   build-relativo        ruta relativa dentro del proyecto con un directorio de build conocido (CMDN_DIRS) como componente, sin `..`,
#                         sin comodin ni llave en el primer componente
#   home-proyecto-build   ~/<proyecto>/.../<directorio de build>, con el proyecto no oculto y sin comodin
#   tmp-subruta           /tmp/<subruta concreta>: nunca /tmp, /tmp/* ni /tmp/.*
# Cualquier otra ruta absoluta, con `~usuario`, con `$` o con `..` no tiene prueba (`~/build`, `~/.cache`, `/run/user/1000`, `/ho?e/u`).
# shellcheck disable=SC2088  # `~` es el TEXTO del operando, no se expande.
cmdn_rm_proof() {
  local p first rest d c base
  local -a parts
  # Contexto cerrado: la prueba mira el operando, pero vale solo si la linea es una orden simple (sin `cd`, sin `ln`, sin nada que
  # cambie lo que el operando nombra) y la ruta RESUELTA, con el disco como esta, queda donde el texto dice.
  (( ${CMDN_LINE_SIMPLE:-0} )) || return 1
  # Operando literal: solo `[A-Za-z0-9._/+@-]` (y `~/` inicial); ni comodines, ni `%`, ni `~` suelta, ni `/.` finales.
  [[ -n $1 && ${1#'~/'} =~ ^[A-Za-z0-9._/+@-]+$ && $1 != */. && $1 != */./* ]] || return 1
  cmdn_path_norm "$1"; p=$REPLY
  [[ -n $p && $p != *..* && $p != *'$'* && $p != *'`'* && $p != *\\* ]] || return 1
  case $p in
    /tmp/*)
      rest=${p#/tmp/}; first=${rest%%/*}
      [[ -n $first && $first != *['*?[{']* ]] || return 1
      cmdn_not_link /tmp "$first" strict || return 1
      REPLY=tmp-subruta; return 0 ;;
    /*|'~'|'~'[!/]*) return 1 ;;
    '~/'*)
      rest=${p#'~/'}; first=${rest%%/*}
      [[ $rest == */* && -n $first && $first != .* && $first != *['*?[{']* ]] || return 1
      cmdn_not_link "$HOME" "$first" || return 1
      rest=${rest#*/}; REPLY=home-proyecto-build ;;
    *)
      rest=${p#./}; first=${rest%%/*}
      [[ -n $first && $first != *['*?[{']* ]] || return 1
      base=$PWD
      case $base in /|/tmp|/home|/etc*|/usr*|/var*|/bin*|/sbin*|/lib*|/boot*|/dev*|/proc*|/sys*|/root*) return 1 ;; /?*) ;; *) return 1 ;; esac
      cmdn_not_link "$base" "$first" || return 1
      REPLY=build-relativo ;;
  esac
  IFS=/ read -ra parts <<<"$rest"
  for c in "${parts[@]}"; do
    for d in "${CMDN_DIRS[@]}"; do [[ $c == "$d" ]] && return 0; done
  done
  return 1
}

# Operando que no se puede resolver en un hook: variable, sustitución, comillas invertidas, o una llave con ruta dentro.
cmdn_opaque_operand() {
  [[ $1 == *'$'* || $1 == *'`'* || ( $1 == *'{'*','* && ( $1 == */* || $1 == *'~'* || $1 == *..* ) ) ]]
}

# Operando que vacía el directorio de trabajo o el repo entero: `.`, `./`, `*`, `./*`, `.*`, `.git`.
cmdn_cwd_operand() {
  case $1 in .|./|'*'|'./*'|'.*'|.git|.git/|./.git|./.git/) return 0 ;; esac
  return 1
}
