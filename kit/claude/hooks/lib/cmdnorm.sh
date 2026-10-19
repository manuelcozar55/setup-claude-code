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
function emit(   k, w, b, o, g, line, j) {
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
  if (k > nt) return
  b = base(toks[k]); g = ""; k++
  if (b == "git") {
    while (k <= nt && toks[k] ~ /^-/) {
      o = toks[k]
      if (gitopt(o) && k < nt) { g = g (g == "" ? "" : GS) o GS toks[k + 1]; k += 2 }
      else { g = g (g == "" ? "" : GS) o; k++ }
    }
  }
  line = g US b
  for (j = k; j <= nt; j++) { w = toks[j]; gsub(/\n/, " ", w); line = line US w }
  segs = segs line "\n"
}
function endseg() { endtok(); if (nt > 0) emit(); nt = 0 }
function parse(s,   n, i, c, d, nx, q, start, closed, pv) {
  txt = ""; segs = ""; nt = 0; tok = ""; have = 0; openq = 0
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
      start = i; q = c; txt = txt c; i++; have = 1; closed = 0
      while (i <= n) {
        d = substr(s, i, 1)
        if (d == q) { closed = 1; txt = txt d; i++; break }
        if (q == "\"" && d == "\\") {
          nx = substr(s, i + 1, 1)
          if (nx == "\n") { i += 2; continue }
          if (nx == "\"" || nx == "\\" || nx == "$" || nx == "`") { tok = tok nx; txt = txt d nx; i += 2; continue }
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
    if (c == "\n") { endseg(); txt = txt c; i++; continue }
    if (c == ";" || c == "|" || c == "(" || c == ")" || c == "`") { endseg(); txt = txt c; i++; continue }
    if (c == "&") {
      pv = substr(s, i - 1, 1); nx = substr(s, i + 1, 1)
      if (pv == ">" || pv == "<" || nx == ">") { tok = tok c; have = 1 }
      else endseg()
      txt = txt c; i++; continue
    }
    tok = tok c; have = 1; txt = txt c; i++
  }
  endseg()
}
BEGIN {
  RS = "\001"; US = "\037"; GS = "\035"
  split("sudo doas env command nice nohup time exec builtin stdbuf ionice setsid timeout", arr, " "); for (x in arr) wrap[arr[x]] = 1
  split("{ ! then do else elif if while until", arr, " "); for (x in arr) ctl[arr[x]] = 1
}
{ src = src $0 RS }
END {
  sub(/\001$/, "", src)
  for (t = 0; t < 400; t++) { parse(src); if (!openq) break; skip[openq] = 1 }
  if (openq) { txt = src; segs = "" }
  printf "%s\036%s", txt, segs
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
  local out rest line
  CMDN_SEGS=(); CMDN_CWD=""
  if ! out=$(awk "$CMDN_AWK" <<<"$1" 2>/dev/null) || [[ $out != *"$CMDN_RS"* ]]; then
    CMDN_TEXT=$1; return 1
  fi
  # `${out%%…*}` y `${out#*…}` prueban cada longitud de prefijo: cuadráticos (64 KB ≈ 1,5 s de CPU,
  # el timeout del hook corre en abierto). `read` parte en el primer separador en una pasada.
  IFS=$CMDN_RS read -r -d '' CMDN_TEXT rest <<<"$out"
  while IFS= read -r line; do
    [[ -n $line ]] && CMDN_SEGS+=("$line")
  done <<<"$rest"
  return 0
}

cmdn_fields() {
  IFS=$CMDN_US read -r -a T <<<"$1"
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
