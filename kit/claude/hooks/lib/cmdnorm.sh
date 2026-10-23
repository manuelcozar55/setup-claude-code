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
# cmdn_parse "$COMMAND" deja tres cosas:
#   CMDN_TEXT  el comando con las continuaciones `\`+NL unidas y los comentarios (fuera de comillas)
#              quitados, comillas INTACTAS: es lo que se alimenta a las regex heredadas. Desde la 1.5
#              se vacia (cuerpo del heredoc fuera, comillas a "" o '') lo que el comando solo escribe o
#              imprime: el cuerpo de un heredoc que leen cat/tee/head..., y lo entrecomillado de echo,
#              printf, grep, jq, git commit/tag..., gh pr/issue... Solo si ningun comando del conjunto
#              puede ejecutar (uno fuera de la lista `known` o con ruta con barra fuera de los
#              directorios del sistema); si no, el texto vuelve entero, como antes. Un cuerpo sin
#              comillas en el delimitador que lleva $( ) o acentos graves tampoco se vacia.
#   CMDN_SEGS  un comando simple por elemento, partido en ; & | ( ) ` y saltos de línea FUERA de
#              comillas. Formato: <opciones globales de git, separadas por \035> US <cmd> US <arg>…
#              con US=\037 entre tokens. Los tokens van descomillados; los prefijos (sudo, env,
#              command, nice, timeout N, VAR=x, { ! if then…) y la ruta del ejecutable se han quitado,
#              y las opciones globales de git (-C dir, -c k=v, --git-dir…) salen del subcomando.
#   CMDN_OPS   en paralelo a CMDN_SEGS: "|" US <dir> si el comando lee la tuberia del anterior, "." si no.
#   cmdn_fields "$seg" lo trocea en el array T: T[0]=opciones globales, T[1]=cmd, T[2…]=args.
#   cmdn_scan_exec fetch|doc decide, sobre SEGS/OPS, si lo que llega por stdin se ejecuta (ver abajo).
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
function dirof(w,   d) { d = w; sub(/[^\/]*$/, "", d); return d }
function flushtxt() { if (txt != "") { np++; tp[np] = txt; tref[np] = 0; txt = "" } }
function addref(d) { flushtxt(); np++; tp[np] = ""; tref[np] = d }
function cmdk(   k, w, b, o) {
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
  return k
}
function emit(   k, w, b, o, g, line, j, w0) {
  k = cmdk()
  if (k > nt) return
  w0 = toks[k]; b = base(w0); g = ""; k++
  if (b == "git") {
    while (k <= nt && toks[k] ~ /^-/) {
      o = toks[k]
      if (gitopt(o) && k < nt) { g = g (g == "" ? "" : GS) o GS toks[k + 1]; k += 2 }
      else { g = g (g == "" ? "" : GS) o; k++ }
    }
  }
  line = g US b
  for (j = k; j <= nt; j++) { w = toks[j]; gsub(/\n/, " ", w); line = line US w }
  nsegs++
  segs = segs line "\n"
  scmd[nsegs] = b; sline[nsegs] = line
  sdir[nsegs] = (w0 ~ /\// ? dirof(w0) : "")
  spipe[nsegs] = (curop == "|")
  ops = ops (curop == "|" ? "|" : ".") US sdir[nsegs] "\n"
  curop = ""
}
function owner(list, idx,   n, a, j) {
  n = split(list, a, " ")
  for (j = 1; j <= n; j++) downer[a[j]] = idx
}
function endseg(   before) {
  endtok()
  if (nt > 0) { before = nsegs; emit(); owner(cdocs, nsegs > before ? nsegs : -1) }
  else owner(cdocs, -1)
  nt = 0; cdocs = ""
}
function buildlines(s,   k, p) {
  nl = split(s, L, "\n"); p = 1
  for (k = 1; k <= nl; k++) { ls[k] = p; p += length(L[k]) + 1 }
  built = 1
}
function lineat(pos,   lo, hi, mid) {
  lo = 1; hi = nl
  while (lo <= hi) {
    mid = int((lo + hi) / 2)
    if (ls[mid] == pos) return mid
    if (ls[mid] < pos) lo = mid + 1; else hi = mid - 1
  }
  return 0
}
# Un heredoc (<<EOF, <<-EOF, con o sin comillas el delimitador) fuera de comillas y de grupos: se anota con su delimitador y su cuerpo se
# lee en el siguiente salto de linea (bodies). Sin delimitador de cierre no es heredoc: el resto sigue siendo
# comandos, como antes.
function regdoc(s, i,   j, n, st, q, w, ch, quoted) {
  if (dn >= 16 || grp > 0 || bt) return
  n = length(s); j = i + 2; st = 0; quoted = 0; w = ""
  if (substr(s, j, 1) == "-") { st = 1; j++ }
  while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
  ch = substr(s, j, 1)
  if (ch == "\\") { quoted = 1; j++; ch = substr(s, j, 1) }
  if (ch == "\047" || ch == "\"") {
    q = ch; j++; quoted = 1
    while (j <= n && substr(s, j, 1) != q) { w = w substr(s, j, 1); j++ }
    if (j > n) return
  } else {
    while (j <= n) { ch = substr(s, j, 1); if (ch ~ /[ \t\n;&|<>()]/) break; w = w ch; j++ }
  }
  if (w == "") return
  dn++; ddelim[dn] = w; dstrip[dn] = st; dquoted[dn] = quoted; dkind[dn] = "X"; downer[dn] = -1
  pn++; pend[pn] = dn; cdocs = cdocs " " dn
}
function bodies(s, i,   k, p, d, q, found, body, cmp, first) {
  if (!built) buildlines(s)
  k = lineat(i)
  if (!k) { pn = 0; return i }
  for (p = 1; p <= pn; p++) {
    d = pend[p]; found = 0; body = ""; first = 1
    for (q = k; q <= nl; q++) {
      cmp = L[q]
      if (dstrip[d]) sub(/^\t+/, "", cmp)
      if (cmp == ddelim[d]) { found = 1; break }
      body = body (first ? "" : "\n") L[q]; first = 0
    }
    if (!found) continue
    dbody[d] = body; dkind[d] = "D"
    addref(d)
    k = q + 1
    i = ls[q] + length(L[q])
  }
  pn = 0
  return i
}
# $(cat <<EOF ... EOF) dentro de comillas dobles (el mensaje de commit de Claude Code): el delimitador va
# entre comillas simples (un heredoc sin comillas expande $( ) del cuerpo y no se trata aqui), asi que el cuerpo no se expande. Devuelve el indice tras el ")" o 0.
function inlinedoc(s, i,   j, n, st, w, k, q, found, body, first, cmp, e, r) {
  if (dn >= 16 || grp > 0 || bt) return 0
  n = length(s); j = i + 2
  while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
  if (substr(s, j, 3) != "cat") return 0
  j += 3
  if (substr(s, j, 1) != " " && substr(s, j, 1) != "\t") return 0
  while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
  if (substr(s, j, 2) != "<<") return 0
  j += 2; st = 0
  if (substr(s, j, 1) == "-") { st = 1; j++ }
  while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
  if (substr(s, j, 1) != "\047") return 0
  j++; w = ""
  while (j <= n && substr(s, j, 1) != "\047") { w = w substr(s, j, 1); j++ }
  if (j > n || w == "") return 0
  j++
  while (substr(s, j, 1) == " " || substr(s, j, 1) == "\t") j++
  if (substr(s, j, 1) != "\n") return 0
  if (!built) buildlines(s)
  k = lineat(j + 1)
  if (!k) return 0
  found = 0; body = ""; first = 1
  for (q = k; q <= nl; q++) {
    cmp = L[q]
    if (st) sub(/^\t+/, "", cmp)
    if (cmp == w) { found = 1; break }
    body = body (first ? "" : "\n") L[q]; first = 0
  }
  if (!found) return 0
  e = ls[q] + length(L[q])
  while (substr(s, e, 1) == " " || substr(s, e, 1) == "\t" || substr(s, e, 1) == "\n") e++
  if (substr(s, e, 1) != ")") return 0
  dn++; dbody[dn] = body; dquoted[dn] = 1; dkind[dn] = "D"; downer[dn] = -1
  cdocs = cdocs " " dn
  idoc = dn
  return e + 1
}
function parse(s,   n, i, c, d, nx, q, start, closed, pv, sp, qplain, e, cw, tgt) {
  txt = ""; segs = ""; ops = ""; nsegs = 0; nt = 0; tok = ""; have = 0; openq = 0
  curop = ""; cdocs = ""; grp = 0; bt = 0; pn = 0; np = 0; built = 0
  if (!nodoc) { dn = 0; split("", downer); split("", dkind) }
  n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") {
      nx = substr(s, i + 1, 1)
      if (nx == "\n") { i += 2; continue }
      if (i == n) { tok = tok c; txt = txt c; have = 1; i++; continue }
      tok = tok nx; have = 1; txt = txt c nx; i += 2; continue
    }
    if ((c == "\047" || c == "\"") && !(i in skip)) {
      start = i; q = c; sp = c; i++; closed = 0; qplain = 0
      cw = ""
      if (!have) { e = cmdk(); if (e <= nt) cw = base(toks[e]) }
      tgt = (have && tok ~ /[<>]$/) || (!have && nt > 0 && toks[nt] ~ /^[0-9&]*[<>]+&?$/)
      have = 1
      while (i <= n) {
        d = substr(s, i, 1)
        if (d == q) { closed = 1; sp = sp d; i++; break }
        if (q == "\"" && d == "\\") {
          nx = substr(s, i + 1, 1)
          if (nx == "\n") { i += 2; continue }
          if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`") { tok = tok nx; sp = sp d nx; i += 2; continue }
        }
        if (q == "\"" && !nodoc && d == "$" && substr(s, i + 1, 1) == "(") {
          e = inlinedoc(s, i)
          if (e) {
            tok = tok substr(s, i, e - i)
            txt = txt sp; sp = ""; flushtxt(); addref(idoc)
            qplain = 1; i = e; continue
          }
        }
        if (q == "\"" && (d == "`" || (d == "$" && substr(s, i + 1, 1) == "("))) qplain = 1
        tok = tok d; sp = sp d; i++
      }
      if (!closed) { openq = start; return }
      if (!nodoc && !qplain && !tgt && grp == 0 && !bt && dn < 16 && (cw in qowner)) {
        dn++; dkind[dn] = "Q"; dspan[dn] = sp; dq[dn] = q; downer[dn] = -1
        cdocs = cdocs " " dn
        addref(dn)
      } else txt = txt sp
      continue
    }
    if (c == "#" && !have) {
      while (i <= n && substr(s, i, 1) != "\n") i++
      continue
    }
    if (c == "<" && !nodoc && substr(s, i, 2) == "<<" && substr(s, i, 3) != "<<<" && substr(s, i - 1, 1) != "<") regdoc(s, i)
    if (c == " " || c == "\t") { endtok(); txt = txt c; i++; continue }
    if (c == "\n") {
      endseg(); txt = txt c; i++
      if (pn > 0) i = bodies(s, i)
      continue
    }
    if (c == ";" || c == "|" || c == "(" || c == ")" || c == "`") {
      endseg()
      if (c == "|") { pv = substr(s, i - 1, 1); nx = substr(s, i + 1, 1); curop = (nx == "|" || pv == "|") ? "" : "|" }
      else if (c == ";") curop = ""
      else if (c == "(") grp++
      else if (c == ")") { if (grp > 0) grp-- }
      else { bt = !bt; curop = "" }
      txt = txt c; i++; continue
    }
    if (c == "&") {
      pv = substr(s, i - 1, 1); nx = substr(s, i + 1, 1)
      if (pv == ">" || pv == "<" || nx == ">") { tok = tok c; have = 1 }
      else { endseg(); if (pv != "|") curop = "" }
      txt = txt c; i++; continue
    }
    tok = tok c; have = 1; txt = txt c; i++
  }
  endseg()
  flushtxt()
}
function parseall(s,   t) {
  split("", skip)
  for (t = 0; t < 400; t++) { parse(s); if (!openq) break; skip[openq] = 1 }
}
# Segmento de datos: lo que como mucho lee su entrada sin ejecutarla (cat, tee, grep, jq...). git, gh, curl y
# wget solo con los argumentos que dicen que su entrada es un cuerpo (un mensaje, un @-).
function sinkseg(n,   c, f, i, a, dat, cfg) {
  c = scmd[n]
  if (c in sinks) return 1
  split(sline[n], f, US)
  if (c == "git") return (f[3] in gitsub)
  if (c == "gh") return (f[3] in ghsub)
  if (c == "curl" || c == "wget") {
    dat = 0; cfg = 0
    for (i = 3; i in f; i++) {
      a = f[i]
      if (a ~ /@-$/) dat = 1
      if ((f[i - 1] == "-T" || f[i - 1] == "--upload-file") && a == "-") dat = 1
      if (c == "wget" && (f[i - 1] == "-i" || f[i - 1] == "--input-file") && a == "-") dat = 1
      if ((f[i - 1] == "-K" || f[i - 1] == "--config") && a == "-") cfg = 1
    }
    return (dat && !cfg)
  }
  return 0
}
function nonexec(n,   c, d) {
  c = scmd[n]; d = sdir[n]
  if (d != "" && !(d in bindir) && !((d in tooldir) && (c in known))) return 0
  return ((c in known) || (c in sinks) || sinkseg(n) || c == "echo" || c == "printf")
}
function passive(j) { return (sinkseg(j) || scmd[j] == "echo" || scmd[j] == "printf") }
function qown(n,   c, f) {
  c = scmd[n]
  if (c == "git" || c == "gh") { split(sline[n], f, US); return (c == "git" ? (f[3] in gitsub) : (f[3] in ghsub)) }
  return (c in qowner)
}
# Un cuerpo de heredoc o un texto entre comillas es dato (se oculta a los guards) solo si su comando es un
# sumidero, lo que tiene detras en su tuberia tambien (lo anterior solo produce texto), y ningun comando de la orden entera puede ejecutar lo que se escribio
# (nada fuera de la lista de herramientas conocidas: bash, un interprete, ./x, find -exec, un bucle...).
function masked(d,   n, a, b, j) {
  n = downer[d]
  if (n < 1 || anyexec) return 0
  b = n; while (b < nsegs && spipe[b + 1]) b++
  if (dkind[d] == "D") {
    if (!dquoted[d] && (index(dbody[d], "$(") || index(dbody[d], "`"))) return 0
    for (j = n; j <= b; j++) if (!sinkseg(j)) return 0
    return 1
  }
  if (!qown(n)) return 0
  for (j = n + 1; j <= b; j++) if (!passive(j)) return 0
  return 1
}
BEGIN {
  RS = "\001"; US = "\037"; GS = "\035"
  split("sudo doas env command nice nohup time exec builtin stdbuf ionice setsid timeout", arr, " "); for (x in arr) wrap[arr[x]] = 1
  split("{ ! then do else elif if while until", arr, " "); for (x in arr) ctl[arr[x]] = 1
  split("cat tee head tail wc sort uniq tr cut grep egrep fgrep rg ag ack jq base64 md5sum sha1sum sha224sum sha256sum sha384sum sha512sum gzip xz man sponge", arr, " "); for (x in arr) sinks[arr[x]] = 1
  split("commit tag notes apply am", arr, " "); for (x in arr) gitsub[arr[x]] = 1
  split("pr issue release gist api", arr, " "); for (x in arr) ghsub[arr[x]] = 1
  split("echo printf grep egrep fgrep rg ag ack jq man git gh", arr, " "); for (x in arr) qowner[arr[x]] = 1
  split("git gh pnpm npm npx yarn corepack cargo go pip pip3 docker podman kubectl code cursor yq curl wget rsync tar zip unzip ls cp mv mkdir touch diff patch make cmake tsc prettier eslint shellcheck gitleaks claude cd pwd true false test [ read exit rm rmdir ln stat date sleep export unset set wait basename dirname readlink realpath mktemp which type file", arr, " "); for (x in arr) known[arr[x]] = 1
  split("/bin/ /sbin/ /usr/bin/ /usr/sbin/", arr, " "); for (x in arr) bindir[arr[x]] = 1
  split("/usr/local/bin/ /usr/local/sbin/ /opt/homebrew/bin/ /opt/homebrew/sbin/ /opt/local/bin/ /snap/bin/ /bin/ /sbin/ /usr/bin/ /usr/sbin/", arr, " "); for (x in arr) tooldir[arr[x]] = 1
}
{ src = src $0 RS }
END {
  sub(/\001$/, "", src)
  nodoc = 0
  parseall(src)
  if (openq) { printf "%s\036%s\036%s", src, "", ""; exit }
  msegs = segs; mops = ops; mn = np; mns = nsegs
  for (k = 1; k <= np; k++) { mtp[k] = tp[k]; mref[k] = tref[k] }
  anyexec = 0
  for (k = 1; k <= nsegs; k++) if (!nonexec(k)) { anyexec = 1; break }
  for (d = 1; d <= dn; d++) dmask[d] = (dkind[d] == "Q" || dkind[d] == "D") ? masked(d) : 0
  nodoc = 1
  for (d = 1; d <= dn; d++) {
    if (dkind[d] != "D" || dmask[d]) continue
    parseall(dbody[d])
    if (openq) { dtxt[d] = dbody[d]; dsegs[d] = ""; dops[d] = "" }
    else {
      out = ""
      for (k = 1; k <= np; k++) out = out tp[k]
      dtxt[d] = out; dsegs[d] = segs; dops[d] = ops
    }
  }
  out = ""
  for (k = 1; k <= mn; k++) {
    d = mref[k]
    if (!d) { out = out mtp[k]; continue }
    if (dkind[d] == "Q") out = out (dmask[d] ? dq[d] dq[d] : dspan[d])
    else if (!dmask[d]) out = out dtxt[d]
  }
  for (d = 1; d <= dn; d++) if (dkind[d] == "D" && !dmask[d]) { msegs = msegs dsegs[d]; mops = mops dops[d] }
  printf "%s\036%s\036%s", out, msegs, mops
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
  local out rest segs
  CMDN_SEGS=(); CMDN_OPS=(); CMDN_CWD=""
  if ! out=$(awk "$CMDN_AWK" <<<"$1" 2>/dev/null) || [[ $out != *"$CMDN_RS"* ]]; then
    CMDN_TEXT=$1; return 1
  fi
  # `${out%%…*}` y `${out#*…}` prueban cada longitud de prefijo: cuadráticos (64 KB ≈ 1,5 s de CPU,
  # el timeout del hook corre en abierto). `read` parte en el primer separador en una pasada.
  IFS=$CMDN_RS read -r -d '' CMDN_TEXT rest <<<"$out"
  IFS=$CMDN_RS read -r -d '' segs rest <<<"$rest"
  mapfile -t CMDN_SEGS <<<"$segs"
  mapfile -t CMDN_OPS <<<"$rest"
  while (( ${#CMDN_SEGS[@]} )) && [[ -z ${CMDN_SEGS[-1]} ]]; do
    unset 'CMDN_SEGS[-1]'
  done
  CMDN_OPS=("${CMDN_OPS[@]:0:${#CMDN_SEGS[@]}}")
  return 0
}

cmdn_fields() {
  IFS=$CMDN_US read -r -a T <<<"$1"
}

# cmdn_pipes_to_shell: 0 si algun comando simple es un interprete de shell que lee su programa de la
# entrada (`| bash`, `| sudo sh -`, sin `-c` ni fichero). Entonces el texto de un echo/printf anterior
# ES la orden, y los guards ya no lo tratan como prosa.
cmdn_pipes_to_shell() {
  local seg a ok cmd
  local -a T
  for seg in "${CMDN_SEGS[@]}"; do
    cmd=${seg#*"$CMDN_US"}; cmd=${cmd%%"$CMDN_US"*}
    case $cmd in bash|sh|zsh|dash|ksh) ;; *) continue ;; esac
    cmdn_fields "$seg"
    ok=1
    for a in "${T[@]:2}"; do
      [[ $a == - || ( $a == -* && $a != -*c* ) ]] || ok=0
    done
    (( ok )) && return 0
  done
  return 1
}

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

# ── Ejecucion de lo que llega por stdin (K1) ────────────────────────────────────────────────────────
# Los guards no bloquean la palabra curl, bash o rm, sino lo que la orden hace con ella. Estas funciones
# deciden sobre CMDN_SEGS/CMDN_OPS (un comando simple por elemento; CMDN_OPS[i] empieza por `|` si ese
# comando recibe la tuberia del anterior). Las usa block-dangerous-commands.sh; Sentinel repite la misma
# logica en Python y test_guards.sh les pasa la misma tabla de casos: tienen que estar de acuerdo.

# cmdn_args: con T ya troceado, deja en CMDN_A los argumentos sin redirecciones (el operando de un
# here-string, de `>` o de un heredoc no es un argumento) y CMDN_HDOC=1 si alguna es heredoc o here-string.
cmdn_args() {
  local i n=${#T[@]} a
  CMDN_A=(); CMDN_HDOC=0
  for (( i = 2; i < n; i++ )); do
    a=${T[i]}
    if [[ $a =~ ^[0-9]*(\&\>\>?|\<\<\<?-?|\>\>?|\<\>?|[\<\>]\&)(.*)$ ]]; then
      [[ ${BASH_REMATCH[1]} == '<<'* ]] && CMDN_HDOC=1
      [[ -z ${BASH_REMATCH[2]} ]] && i=$(( i + 1 ))
      continue
    fi
    CMDN_A+=("$a")
  done
}

# cmdn_runs_input "$codigo": el codigo en linea de un interprete ejecuta lo que lee (exec, eval, system,
# popen, subprocess, un acento grave, una tuberia a un shell...). Las palabras de prosa no cuentan.
cmdn_runs_input() {
  local t=$1 w
  local re='exec|eval|system|popen|spawn|subprocess|child_process|passthru|proc_open|`|\|[[:space:]]*["'"'"']?(sh|bash|zsh|dash)([^[:alnum:]_]|$)'
  for w in executions execution executors executor executables executable executed executing executives executive spawned spawning spawns; do
    t=${t//"$w"/}
  done
  [[ $t =~ $re ]]
}

# cmdn_reads_program: con T y CMDN_A, 0 si el comando LEE SU PROGRAMA de la entrada estandar: un shell sin
# `-c` ni fichero (sh -, sh -s -- arg), un interprete sin codigo en linea ni fichero (python3 -, node, perl),
# o con codigo en linea que ejecuta lo que lee. Un interprete con `-c`/`-e` o con fichero lee de stdin solo
# datos. Con xargs delante de un shell o interprete, la primera linea de stdin es la orden: cuenta. Deja el
# codigo en linea en CMDN_CODE. Ante la duda (un `-m` que no es json.tool) devuelve 0.
cmdn_reads_program() {
  local c=${T[1]:-} a i n=${#CMDN_A[@]} dd=0 pos="" inline=0 mod="" sflag=0 dash=0 kind
  local reshell='(^|[^[:alnum:]_./-])(eval|source|exec|xargs|sh|bash|zsh|dash|ksh|fish|python[0-9.]*|node|nodejs|perl|ruby|php)([^[:alnum:]_-]|$)|(^|[;&|( ])\.[[:space:]]+/dev/stdin'
  CMDN_CODE=""
  c=${c##*/}
  case $c in
    bash|sh|zsh|dash|ksh|fish) kind=shell ;;
    \$*) return 0 ;;
    python|python[0-9]*|node|nodejs|perl|ruby|php) kind=interp ;;
    xargs)
      for a in "${CMDN_A[@]}"; do
        case ${a##*/} in bash|sh|zsh|dash|ksh|fish|python|python[0-9]*|node|nodejs|perl|ruby|php) return 0 ;; esac
      done
      return 1 ;;
    *) return 1 ;;
  esac
  for (( i = 0; i < n; i++ )); do
    a=${CMDN_A[i]}
    if (( dd )); then [[ -z $pos ]] && pos=$a; continue; fi
    case $a in
      --) dd=1; continue ;;
      -) dash=1; [[ -z $pos ]] && pos=-; continue ;;
    esac
    if [[ -z $pos && $a == [-+]* ]]; then
      if [[ $kind == shell ]]; then
        case $a in
          --rcfile|--init-file|-o|+o|-O|+O) i=$(( i + 1 )) ;;
          --*) ;;
          -*c*) inline=1 ;;
        esac
        [[ $a != --* && $a == -*s* ]] && sflag=1
        continue
      fi
      case $c in
        python*)
          if [[ $a =~ ^-[A-Za-z]*c$ ]]; then CMDN_CODE=${CMDN_A[i+1]:-}; inline=1; break
          elif [[ $a == -c?* ]]; then CMDN_CODE=${a#-c}; inline=1; break
          elif [[ $a =~ ^-[A-Za-z]*m$ ]]; then mod=${CMDN_A[i+1]:-x}; break
          elif [[ $a == -m?* ]]; then mod=${a#-m}; break
          elif [[ $a == -W || $a == -X ]]; then i=$(( i + 1 ))
          fi ;;
        node|nodejs)
          case $a in
            -e|-p|-pe|-ep|--eval|--print) CMDN_CODE=${CMDN_A[i+1]:-}; inline=1; i=$(( i + 1 )) ;;
            --eval=*|--print=*) CMDN_CODE=${a#*=}; inline=1 ;;
            -r|--require|--import|--loader|--experimental-loader|-C|--conditions|--input-type) i=$(( i + 1 )) ;;
          esac ;;
        perl)
          if [[ $a =~ ^-[A-Za-z0-9]*[eE]$ ]]; then CMDN_CODE=${CMDN_A[i+1]:-}; inline=1; i=$(( i + 1 ))
          elif [[ $a == -I ]]; then i=$(( i + 1 ))
          fi ;;
        ruby)
          if [[ $a =~ ^-[A-Za-z0-9]*e$ ]]; then CMDN_CODE=${CMDN_A[i+1]:-}; inline=1; i=$(( i + 1 ))
          elif [[ $a == -I || $a == -r ]]; then i=$(( i + 1 ))
          fi ;;
        php)
          case $a in
            -r) CMDN_CODE=${CMDN_A[i+1]:-}; inline=1; i=$(( i + 1 )) ;;
            -f) pos=${CMDN_A[i+1]:-x}; i=$(( i + 1 )) ;;
          esac ;;
      esac
      continue
    fi
    [[ -z $pos ]] && pos=$a
  done
  if [[ $kind == shell ]]; then
    if (( inline )); then
      CMDN_CODE=$pos
      [[ $pos =~ $reshell ]]
      return
    fi
    [[ -z $pos || $sflag == 1 || $pos == - ]]
    return
  fi
  if [[ -n $mod ]]; then [[ $mod != json.tool ]]; return; fi
  if (( dash )); then return 0; fi
  if (( inline )); then cmdn_runs_input "$CMDN_CODE"; return; fi
  [[ -z $pos ]]
}

# cmdn_fetch_exec: 0 si un curl/wget alimenta, dentro de su tuberia, a un comando que lee su programa de la
# entrada (cmdn_reads_program). Deja el descargador en CMDN_FETCHER. Un jq, un python3 -c con codigo propio
# o un bash con fichero no cuentan: ahi lo descargado son datos.
cmdn_fetch_exec() {
  local i fetched="" op
  local -a T
  CMDN_FETCHER=""
  for (( i = 0; i < ${#CMDN_SEGS[@]}; i++ )); do
    op=${CMDN_OPS[i]%%"$CMDN_US"*}
    [[ $op == '|' ]] || fetched=""
    cmdn_fields "${CMDN_SEGS[i]}"
    cmdn_args
    if [[ -n $fetched ]] && cmdn_reads_program; then CMDN_FETCHER=$fetched; return 0; fi
    case ${T[1]:-} in curl|wget) fetched=${T[1]} ;; esac
  done
  return 1
}

# cmdn_doc_exec: 0 si un heredoc o un here-string alimenta, directamente o por tuberia, a un SHELL que lee su
# programa de la entrada (`bash <<EOF`, `cat <<EOF | sh`, `sh <<< "..."`). Con codigo en linea o con
# fichero, el heredoc es solo la entrada de datos del programa. Un interprete que lee su programa del
# heredoc (`python3 - <<EOF`) es el uso corriente y no se bloquea por serlo: pone CMDN_DOC_INTERP=1 y quien
# llama aplica a ese texto las reglas por palabras (el cuerpo es codigo y sigue juzgandose por lo que dice).
cmdn_doc_exec() {
  local i fed=0 op
  local -a T
  for (( i = 0; i < ${#CMDN_SEGS[@]}; i++ )); do
    op=${CMDN_OPS[i]%%"$CMDN_US"*}
    [[ $op == '|' ]] || fed=0
    cmdn_fields "${CMDN_SEGS[i]}"
    cmdn_args
    if cmdn_reads_program && { (( CMDN_HDOC )) || (( fed )); }; then
      case ${T[1]##*/} in
        bash|sh|zsh|dash|ksh|fish|xargs) return 0 ;;
        *) CMDN_DOC_INTERP=1 ;;
      esac
    fi
    (( CMDN_HDOC )) && fed=1
  done
  return 1
}

cmdn_inner_wants() {
  if [[ $1 == fetch ]]; then
    [[ $2 == *'|'* && ( $2 == *curl* || $2 == *wget* ) ]]
  else
    [[ $2 == *'<<'* ]]
  fi
}

# cmdn_inner_strings fetch|doc: las cadenas que otro comando vuelve a leer como orden y que mencionan lo que
# se busca: el `-c` de un shell, el codigo de un interprete, los argumentos de ssh, eval, docker... Un echo,
# un grep o un git commit solo muestran texto, salvo que un shell lea la tuberia (CMDN_PIPED=1). Los
# argumentos de un script no son codigo. Si un interprete lleva dentro un descargador con tuberia a un
# shell, pone CMDN_FORCE=1 (su codigo no se puede trocear como shell).
cmdn_inner_strings() {
  local kind=$1 i a c
  local -a T
  local reint='(curl|wget)[^|]*\|[[:space:]]*["'"'"']?(sudo[[:space:]]+)?([^[:space:]]*/)?(sh|bash|zsh|dash|python[0-9.]*|node|perl|ruby)([^[:alnum:]_]|$)'
  CMDN_INNER=()
  for (( i = 0; i < ${#CMDN_SEGS[@]}; i++ )); do
    cmdn_fields "${CMDN_SEGS[i]}"
    c=${T[1]:-}; c=${c##*/}
    case $c in
      echo|printf|grep|egrep|fgrep|rg|ag|ack|sed|awk|cat|man|type|which|less|head|tail|test|'['|git|gh|jq|curl|wget|tee|tr|cut|sort|uniq|wc|base64|ls|cp|mv|mkdir|touch|rm)
        (( ${CMDN_PIPED:-0} )) || continue ;;
    esac
    cmdn_args
    case $c in
      bash|sh|zsh|dash|ksh|fish)
        cmdn_reads_program; a=$CMDN_CODE
        [[ -n $a ]] && cmdn_inner_wants "$kind" "$a" && CMDN_INNER+=("$a") ;;
      python|python[0-9]*|perl|ruby|node|nodejs|php)
        cmdn_reads_program
        if [[ $kind == fetch && $CMDN_CODE =~ $reint ]]; then CMDN_FORCE=1; fi ;;
      *)
        for a in "${CMDN_A[@]}"; do
          cmdn_inner_wants "$kind" "$a" && CMDN_INNER+=("$a")
        done ;;
    esac
  done
}

# cmdn_scan_exec fetch|doc [profundidad]: 0 si la orden (o una cadena que otro comando relee, hasta 3
# niveles) ejecuta lo que llega por stdin; 1 si no; 2 si pasa de 3 niveles o de 16 cadenas: fallar cerrado,
# porque un guard que se pasa de su timeout deja ejecutar la orden entera. Quien llama pone CMDN_NEST=0.
cmdn_scan_exec() {
  local kind=$1 depth=${2:-0} inner rc=1 text=$CMDN_TEXT
  local -a inners saved_segs saved_ops
  "cmdn_${kind}_exec" && return 0
  CMDN_FORCE=0
  cmdn_inner_strings "$kind"
  (( CMDN_FORCE )) && { CMDN_FETCHER=${CMDN_FETCHER:-curl}; return 0; }
  (( ${#CMDN_INNER[@]} )) || return 1
  (( depth < 3 )) || return 2
  inners=("${CMDN_INNER[@]}")
  saved_segs=("${CMDN_SEGS[@]}"); saved_ops=("${CMDN_OPS[@]}")
  for inner in "${inners[@]}"; do
    (( ++CMDN_NEST <= 16 )) || { rc=2; break; }
    cmdn_parse "$inner" || continue
    cmdn_scan_exec "$kind" $(( depth + 1 )); rc=$?
    (( rc == 1 )) || break
  done
  CMDN_SEGS=("${saved_segs[@]}"); CMDN_OPS=("${saved_ops[@]}"); CMDN_TEXT=$text
  return "$rc"
}
