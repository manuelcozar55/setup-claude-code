#!/usr/bin/env python3
"""verificar-docs.py — la documentacion que lee quien recibe el kit no puede citar lo que no existe.

Sobre README.md, ENTREGA.md, kit/docs/OPERAR.md y la guia (kit/docs/guia/*.md) comprueba:
  1. Cada enlace relativo resuelve, y su ancla existe en el destino.
  2. Cada ruta entre acentos graves que empieza por un directorio o fichero del repo existe.
  3. Cada `bash <ruta>.sh` que cita existe.
  4. La version minima de Claude Code sale de una sola fuente (MIN_CLAUDE_CODE en el cockpit) y todo lo que
     la cita dice lo mismo; README dice la version del cockpit de plugin.json.
  5. Las cifras de OPERAR/README que tienen una fuente en el codigo (NUCLEO_TOPE) coinciden con ella.
  6. Longitud: README <= 120 lineas y OPERAR <= 200.
  7. Nada de `scripts/scc.sh` (el lanzador instalado es `scc`) ni de CC_NUCLEO_GATE fuera de su historia.
  8. 02-install.md dice cuantos enlaces crea install.sh (los que lista CLIS).

Uso: verificar-docs.py [--root DIR]. Sale 0 si todo cuadra y 1 si no; cada hallazgo, una linea. Solo stdlib.
"""
import argparse
import re
import sys
from pathlib import Path

NUMEROS = {1: "un", 2: "dos", 3: "tres", 4: "cuatro", 5: "cinco", 6: "seis", 7: "siete", 8: "ocho"}
# Donde CC_NUCLEO_GATE puede seguir apareciendo: es historia, no instruccion.
GATE_PERMITIDO = {"CHANGELOG.md", "knowledge/DECISIONS/020-compuerta-nucleo.md", "kit/test/fixtures/nucleo-gate.retirado.sh",
                  "kit/test/test_docs_enlaces.sh"}
SIN_SCC_SH = ["README.md", "kit/docs/OPERAR.md", "kit/docs/02-install.md", "kit/docs/10-onboarding.md",
              "kit/docs/11-cockpit.md", "kit/docs/08-plugins-mcp-y-skills.md"]


def slug(titulo):
    s = re.sub(r"[`*_]", "", titulo.strip().lower())
    s = re.sub(r"[^\w\s-]", "", s)
    return re.sub(r"\s", "-", s)


def anclas(ruta):
    out = set()
    en_codigo = False
    for linea in ruta.read_text(encoding="utf-8").splitlines():
        if linea.startswith("```"):
            en_codigo = not en_codigo
        m = re.match(r"#{1,6}\s+(.*)", linea)
        if m and not en_codigo:
            out.add(slug(m.group(1)))
    return out


def sin_codigo(texto):
    return re.sub(r"```.*?```", "", texto, flags=re.S)


def docs_a_vigilar(root):
    docs = [root / "README.md", root / "ENTREGA.md", root / "kit/docs/OPERAR.md"]
    docs += sorted((root / "kit/docs/guia").glob("*.md"))
    return [d for d in docs if d.exists()]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=str(Path(__file__).resolve().parent.parent))
    root = Path(ap.parse_args().root).resolve()
    fallos = []

    def fallo(doc, msg):
        fallos.append(f"{doc.relative_to(root)}: {msg}")

    # `.claude/` queda fuera: en la documentacion es el de tu proyecto o el de ~, no el andamiaje de la raiz.
    propios = {p.name for p in root.iterdir() if not p.name.startswith(".")}
    cache_anclas = {}

    for doc in docs_a_vigilar(root):
        texto = doc.read_text(encoding="utf-8")
        prosa = sin_codigo(texto)
        for destino in re.findall(r"\]\(([^)\s]+)\)", prosa):
            if re.match(r"(https?:|mailto:)", destino):
                continue
            ruta, _, ancla = destino.partition("#")
            objetivo = (doc.parent / ruta) if ruta else doc
            if not objetivo.exists():
                fallo(doc, f"enlace roto -> {destino}")
                continue
            if ancla and objetivo.suffix == ".md":
                if objetivo not in cache_anclas:
                    cache_anclas[objetivo] = anclas(objetivo)
                if ancla not in cache_anclas[objetivo]:
                    fallo(doc, f"el enlace {destino} apunta a una ancla que no existe")
        for tramo in re.findall(r"`([^`\n]+)`", prosa):
            primero = tramo.split()[0] if tramo.split() else ""
            if any(c in primero for c in "~$<>*{}…|") or primero.startswith("/") or "://" in primero:
                continue
            raiz = primero.split("/")[0]
            if "/" in primero and raiz in propios and re.search(r"\.\w+$|/$", primero):
                if not (root / primero).exists():
                    fallo(doc, f"la ruta `{primero}` no existe en el arbol")
        for ruta in re.findall(r"\bbash\s+((?:kit|scripts)/[\w./-]+\.sh|uninstall\.sh)", texto):
            if not (root / ruta).exists():
                fallo(doc, f"cita `bash {ruta}` y no existe")

    # 4. una sola fuente para la version minima de Claude Code y la del cockpit
    reg = root / "kit/mods/cockpit/hooks/register.tsx"
    minima = None
    if reg.exists():
        m = re.search(r"MIN_CLAUDE_CODE = '([0-9.]+)'", reg.read_text(encoding="utf-8"))
        minima = m.group(1) if m else None
    if not minima:
        fallos.append("kit/mods/cockpit/hooks/register.tsx: no encuentro MIN_CLAUDE_CODE, la fuente unica de la version minima")
    else:
        for rel in ("README.md", "kit/docs/OPERAR.md"):
            d = root / rel
            if d.exists() and minima not in d.read_text(encoding="utf-8"):
                fallos.append(f"{rel}: no dice la version minima de Claude Code ({minima}, de MIN_CLAUDE_CODE)")
        for doc in docs_a_vigilar(root):
            if doc.name == "ENTREGA.md":
                continue
            for v in re.findall(r"\b2\.1\.\d+\b", doc.read_text(encoding="utf-8")):
                if v != minima:
                    fallo(doc, f"cita Claude Code {v}, y la unica version minima es {minima}")
    pj = root / "kit/mods/cockpit/.claude-plugin/plugin.json"
    rd = root / "README.md"
    if pj.exists() and rd.exists():
        mj = re.search(r'"version":\s*"([0-9.]+)"', pj.read_text(encoding="utf-8"))
        mr = re.search(r"cockpit: ([0-9]+\.[0-9]+\.[0-9]+)", rd.read_text(encoding="utf-8"))
        if not mj or not mr:
            fallos.append("README.md: falta `cockpit: X.Y.Z` o plugin.json no tiene version (los necesita bump.sh)")
        elif mj.group(1) != mr.group(1):
            fallos.append(f"README.md dice cockpit {mr.group(1)} y plugin.json {mj.group(1)}")

    # 5. NUCLEO_TOPE
    lib = root / "kit/claude/hooks/lib/nucleo.sh"
    if lib.exists():
        m = re.search(r"NUCLEO_TOPE=\$\{NUCLEO_TOPE:-(\d+)\}", lib.read_text(encoding="utf-8"))
        if m:
            for rel in ("README.md", "kit/docs/OPERAR.md"):
                d = root / rel
                if d.exists() and m.group(1) not in d.read_text(encoding="utf-8"):
                    fallos.append(f"{rel}: no cita el tope de estado que inyecta el kit ({m.group(1)} bytes, NUCLEO_TOPE)")

    # 6. longitudes
    for rel, tope in (("README.md", 120), ("kit/docs/OPERAR.md", 200)):
        d = root / rel
        if d.exists():
            n = len(d.read_text(encoding="utf-8").splitlines())
            if n > tope:
                fallos.append(f"{rel}: {n} lineas, el tope es {tope}")

    # 7. el lanzador y el nombre de la compuerta
    for rel in SIN_SCC_SH:
        d = root / rel
        if d.exists() and "scripts/scc.sh" in d.read_text(encoding="utf-8"):
            fallos.append(f"{rel}: cita scripts/scc.sh; el lanzador instalado es `scc`")
    for d in list(root.rglob("*.md")) + list(root.rglob("*.sh")) + list(root.rglob("*.py")):
        rel = d.relative_to(root).as_posix()
        if rel.startswith((".git/", "kit/mods/cockpit/node_modules")) or rel in GATE_PERMITIDO or rel == "scripts/verificar-docs.py":
            continue
        if "CC_NUCLEO_GATE" in d.read_text(encoding="utf-8", errors="replace"):
            fallos.append(f"{rel}: cita CC_NUCLEO_GATE; el codigo lee NUCLEO_GATE")

    # 8. cuantos enlaces crea install.sh
    inst, doc = root / "kit/install.sh", root / "kit/docs/02-install.md"
    if inst.exists() and doc.exists():
        m = re.search(r'^CLIS="([^"]+)"', inst.read_text(encoding="utf-8"), re.M)
        if m:
            n = len(m.group(1).split())
            if f"crea {NUMEROS.get(n, str(n))} enlaces" not in doc.read_text(encoding="utf-8"):
                fallos.append(f"kit/docs/02-install.md: no dice «crea {NUMEROS.get(n, n)} enlaces» (install.sh enlaza {n}: {m.group(1)})")

    for f in fallos:
        print(f)
    if not fallos:
        print("ok - la documentacion cita solo lo que existe")
    return 1 if fallos else 0


if __name__ == "__main__":
    sys.exit(main())
