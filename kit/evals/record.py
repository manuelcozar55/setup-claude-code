#!/usr/bin/env python3
"""Anade una linea al almacen de runs a partir del transcript de una tarea.

El almacen (runs.jsonl, append-only) existe porque un JSON diario que se
sobrescribe no tiene historia: sin historia no hay regresion detectable, y un
eval que no detecta regresiones solo sirve para el dia que se corre.
"""
import json, os, re, sys

task, arm, attempt, result, transcript, store = sys.argv[1:7]


def polaridad(tid):
    """positiva (el harness debe disparar) o negativa (no debe). Se lee del
    propio yaml en vez de pasarla por argumento para que no haya dos fuentes
    de verdad que puedan discrepar. Sin yaml (tareas sinteticas de test): None."""
    p = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tasks", tid + ".yaml")
    try:
        m = re.search(r"^tipo:\s*(\w+)", open(p, errors="replace").read(), re.M)
    except OSError:
        return None
    return m.group(1) if m else None

usage = {}
for line in open(transcript, errors="replace"):
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("type") == "result":
        usage = d

u = usage.get("usage") or {}
model = next(iter(usage.get("modelUsage") or {}), None)

rec = {
    "ts": os.environ.get("EVAL_TS"),
    "task": task,
    "arm": arm,                       # que variaba en este brazo
    "tipo": polaridad(task),          # positiva | negativa; ver report.py
    "attempt": int(attempt),
    "result": result,                 # pass | fail | error
    "model": model,
    "harness_sha": os.environ.get("EVAL_SHA"),
    # Coste y latencia van FUERA de la nota, nunca dentro: una tarea puede
    # resolverse bien y costar el triple, y esas son dos lecturas distintas.
    "cost_usd": usage.get("total_cost_usd"),
    "duration_api_ms": usage.get("duration_api_ms"),
    "num_turns": usage.get("num_turns"),
    "input_tokens": u.get("input_tokens"),
    "output_tokens": u.get("output_tokens"),
    "cache_read_tokens": u.get("cache_read_input_tokens"),
    "api_error": usage.get("is_error"),
    "permission_denials": len(usage.get("permission_denials") or []),
    "transcript": transcript,
}
with open(store, "a") as f:
    f.write(json.dumps(rec, ensure_ascii=False) + "\n")
