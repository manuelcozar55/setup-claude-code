#!/usr/bin/env python3
"""compact-audit.py — métricas de compactación sobre las transcripciones reales.

Uso: python3 scripts/compact-audit.py [--since DIAS]
Lee $CLAUDE_PROJECTS_DIR (por defecto ~/.claude/projects) y excluye */subagents/*: los
subagentes no los escribe la persona y distorsionan los recuentos. Objetivos: >= 50 %
manuales, <= 3 por sesión larga, 0 huecos de <= 2 mensajes, entrada < 25k tokens por
mensaje humano.
"""
import argparse, glob, json, os, re, sys, time
from collections import Counter, defaultdict

CORR = re.compile(r"\b(no|mal|error|incorrecto|equivocado|revierte|falso|para)\b", re.I)


def human_text(r):
    """Texto escrito por la persona, o None. Excluye isMeta, resúmenes de compactación y los
    bloques que la runtime envuelve en <...> (system-reminder, local-command, skills)."""
    if r.get("type") != "user" or r.get("isMeta") or r.get("isCompactSummary"):
        return None
    c = (r.get("message") or {}).get("content")
    if isinstance(c, list):
        c = " ".join(b.get("text", "") for b in c if b.get("type") == "text")
    if not isinstance(c, str) or not c.strip() or c.lstrip().startswith("<") or c.startswith("Base directory for this skill"):
        return None
    return c


def pct(a, p):
    a = sorted(a)
    return a[min(len(a) - 1, int(len(a) * p))] if a else 0


def usage_tot(r):
    u = (r.get("message") or {}).get("usage") or {}
    return u.get("input_tokens", 0) + u.get("cache_read_input_tokens", 0) + u.get("cache_creation_input_tokens", 0)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", type=int, default=0, help="solo sesiones modificadas en los últimos N días")
    a = ap.parse_args()
    root = os.environ.get("CLAUDE_PROJECTS_DIR") or os.path.expanduser("~/.claude/projects")
    files = [f for f in glob.glob(f"{root}/**/*.jsonl", recursive=True) if "/subagents/" not in f]
    if a.since:
        lim = time.time() - a.since * 86400
        files = [f for f in files if os.path.getmtime(f) > lim]
    trig, dur, destr, gaps, inflow, per, first, comp = Counter(), [], [], [], [], Counter(), [], Counter()
    corr_post = 0
    for f in files:
        recs = []
        for line in open(f, errors="ignore"):
            try:
                recs.append(json.loads(line))
            except ValueError:
                pass
        for r in recs:
            if r.get("type") == "assistant" and usage_tot(r):
                first.append(usage_tot(r)); break
        idx = [i for i, r in enumerate(recs) if r.get("type") == "system" and r.get("subtype") == "compact_boundary"]
        if not idx:
            continue
        per[f] = len(idx)
        prev, prev_post = 0, None
        for i in idx:
            m = recs[i].get("compactMetadata") or {}
            trig[m.get("trigger", "?")] += 1
            if m.get("durationMs"): dur.append(m["durationMs"] / 1000)
            pre, post = m.get("preTokens"), m.get("postTokens")
            if pre and post: destr.append(1 - post / pre)
            n_h = 0
            for r in recs[prev:i]:
                c = (r.get("message") or {}).get("content")
                if human_text(r) is not None:
                    n_h += 1
                if r.get("type") == "user" and isinstance(c, list):
                    for b in c:
                        if b.get("type") == "tool_result":
                            cc = b.get("content"); comp["tool_result"] += len(cc if isinstance(cc, str) else json.dumps(cc))
                if r.get("type") == "assistant" and isinstance(c, list):
                    for b in c:
                        if b.get("type") == "tool_use": comp["tool_use_input"] += len(json.dumps(b.get("input", {})))
                        elif b.get("type") == "text": comp["assistant_text"] += len(b.get("text", ""))
            gaps.append(n_h)
            if pre and n_h and prev_post is not None:
                inflow.append((pre - prev_post) / n_h)
            prev, prev_post = i, post
            # correcciones en los 2 primeros mensajes humanos tras compactar (heurística)
            k = 0
            for r in recs[i + 1:i + 400]:
                t = human_text(r)
                if t is not None:
                    k += 1
                    if CORR.search(t): corr_post += 1; break
                    if k >= 2: break
    n = sum(trig.values())
    print(f"sesiones analizadas: {len(files)} | con compactación: {len(per)} | compactaciones: {n}")
    if not n:
        return
    print(f"  manuales: {trig.get('manual',0)} ({100*trig.get('manual',0)/n:.0f} %)  auto: {trig.get('auto',0)}")
    print(f"  por sesión: mediana {pct(list(per.values()),.5)}  p90 {pct(list(per.values()),.9)}  máx {max(per.values())}")
    print(f"  duración: mediana {pct(dur,.5):.0f} s  p90 {pct(dur,.9):.0f} s  total {sum(dur)/60:.0f} min")
    print(f"  destruido por evento: mediana {100*pct(destr,.5):.0f} %")
    print(f"  mensajes humanos entre compactaciones: mediana {pct(gaps,.5)}  huecos <=2: {sum(1 for g in gaps if g<=2)} de {len(gaps)}")
    print(f"  dentro del mismo turno (0 mensajes humanos desde la anterior): {sum(1 for g in gaps if g==0)} de {len(gaps)}  <- ahí el hook Stop no llega a avisar")
    if inflow: print(f"  entrada por mensaje humano: mediana {pct(inflow,.5)/1000:.0f}k tok")
    tot = sum(comp.values()) or 1
    print("  composición de lo compactado: " + ", ".join(f"{k} {100*v/tot:.0f} %" for k, v in comp.most_common()))
    print(f"  compactaciones seguidas de corrección (2 msgs, heurística): {corr_post} ({100*corr_post/n:.0f} %)")
    print(f"coste fijo primer turno: mediana {pct(first,.5)/1000:.1f}k  p90 {pct(first,.9)/1000:.1f}k  (n={len(first)})")
    logs = sorted(glob.glob(os.path.expanduser("~/.claude/session-logs/compact-*.log")))
    if logs:
        rows = [l.split("\t") for f in logs for l in open(f) if l.strip()]
        lost = [int(x.split("=")[1]) for r in rows for x in r if x.startswith("anclas_perdidas=")]
        print(f"post-compact log: {len(rows)} eventos, anclas perdidas media {sum(lost)/max(1,len(lost)):.1f}, con pérdida {sum(1 for x in lost if x)}")


if __name__ == "__main__":
    main()
