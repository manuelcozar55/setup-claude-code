#!/usr/bin/env python3
"""recall.py — recuerdo razonado sobre las memorias, sin cargarlas enteras.

Uso:  recuerda <términos...>    devuelve solo los párrafos que coinciden, ordenados
      recuerda -l               índice (name + description) de todas las memorias
      recuerda -f <slug>        una memoria completa

Por qué existe: el índice (`MEMORY.md`) se inyecta en cada arranque, pero las memorias
enteras pesan muchas veces más. Leerlas todas para comprobar un dato es gasto puro:
esto cobra el recuerdo solo al usarlo. Insensible a mayúsculas y acentos: el corpus mezcla
«compactacion» y «compactación».

Directorio: $CLAUDE_MEMORY_DIR, o por defecto el memory/ del proyecto de $HOME
(~/.claude/projects/<$HOME con cada carácter no alfanumérico cambiado por '-'>/memory).
"""
import os, re, sys, unicodedata

HOME = os.path.expanduser("~")
DIR = os.environ.get("CLAUDE_MEMORY_DIR") or os.path.join(
    HOME, ".claude", "projects", re.sub(r"[^A-Za-z0-9]", "-", HOME), "memory")
TOPE, TOP = 1200, 3


def norm(s):
    s = unicodedata.normalize("NFKD", s.lower())
    return "".join(c for c in s if not unicodedata.combining(c))


def sangrar(txt):
    return "\n".join("  " + l for l in txt.splitlines()) + "\n"


def cargar():
    for f in sorted(os.listdir(DIR)):
        if not f.endswith(".md") or f == "MEMORY.md":
            continue
        with open(os.path.join(DIR, f), errors="ignore") as fh:
            t = fh.read()
        m = re.search(r'^description:\s*"?(.*?)"?\s*$', t, re.M)
        cuerpo = t.split("---", 2)[-1].strip() if t.startswith("---") else t
        yield f[:-3], (m.group(1) if m else ""), cuerpo


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__.strip()); return 2
    if a[0] in ("-h", "--help"):
        print(__doc__.strip()); return 0
    if not os.path.isdir(DIR):
        print(f"no existe el directorio de memorias: {DIR} (define CLAUDE_MEMORY_DIR)",
              file=sys.stderr); return 2
    if a[0] == "-l":
        for n, d, _ in cargar():
            print(f"{n}\n    {d}")
        return 0
    if a[0] == "-f":
        slug = a[1] if len(a) > 1 else ""
        if not re.fullmatch(r"[A-Za-z0-9._-]+", slug):
            print("slug inválido (solo letras, dígitos, . _ -)", file=sys.stderr); return 2
        p = os.path.join(DIR, slug + ".md")
        if not os.path.realpath(p).startswith(os.path.realpath(DIR) + os.sep):
            print("el fichero apunta fuera del directorio de memorias", file=sys.stderr); return 2
        if not os.path.isfile(p):
            print(f"no existe: {slug} — prueba: recuerda -l", file=sys.stderr)
            return 1
        with open(p) as fh:
            sys.stdout.write(fh.read())
        return 0

    terms = [norm(t) for t in a if len(t) > 2]
    if not terms:
        print("términos demasiado cortos (>2 caracteres)", file=sys.stderr); return 2
    res, total = [], 0
    for n, d, cuerpo in cargar():
        total += 1
        cab, cpo = norm(n + " " + d), norm(cuerpo)
        hit_cab = {t for t in terms if t in cab}
        hit_cpo = {t for t in terms if t in cpo}
        if not (hit_cab or hit_cpo):
            continue
        parrafos = [p for p in re.split(r"\n\s*\n", cuerpo)
                    if any(t in norm(p) for t in terms)]
        res.append((len(hit_cab | hit_cpo), 3 * len(hit_cab) + len(hit_cpo),
                    n, d, sorted(hit_cab | hit_cpo), parrafos))
    res.sort(reverse=True)
    if not res:
        print(f"sin coincidencias para {' '.join(a)} en {total} memorias. "
              f"Índice: recuerda -l", file=sys.stderr)
        return 1
    for _, _, n, d, hits, parrafos in res[:TOP]:
        print(f"## {n}  [coincide: {', '.join(hits)}]")
        if d:
            print(f"    {d}")
        acum, omitidos = 0, 0
        for p in parrafos:
            if acum + len(p) <= TOPE:
                print(sangrar(p)); acum += len(p)
            else:
                omitidos += 1
        if acum == 0 and parrafos:
            p = parrafos[0]
            print(sangrar(p[:TOPE]))
            print(f"    [párrafo recortado a {TOPE} de {len(p)} chars]")
            omitidos -= 1
        if omitidos:
            print(f"    [...{omitidos} párrafo(s) más coinciden; completa: recuerda -f {n}]")
    if len(res) > TOP:
        print(f"[{len(res) - TOP} memorias más coinciden con menos fuerza: "
              f"{', '.join(r[2] for r in res[TOP:])}]")
    return 0


if __name__ == "__main__":
    sys.exit(main())
