#!/usr/bin/env python3
"""Sube runs.jsonl a LangSmith: una traza padre por sesion, un hijo por tarea.

Sin dependencias: urllib de la stdlib. El SDK `langsmith` solo esta en
~/.venvs/tools, y el resto del eval corre con el python3 del sistema; pedir el
SDK aqui convertiria el emisor en el unico componente que no se puede ejecutar
donde se ejecuta lo que mide.

LOCAL O NUBE, indistinto: la URL sale de LANGSMITH_ENDPOINT y por defecto apunta
a la nube. Para una instancia propia:

    LANGSMITH_ENDPOINT=http://localhost:1984 LANGSMITH_API_KEY=... \\
        python3 kit/evals/langsmith_push.py

Sin clave NO es un error: imprime que no hay clave y sale 0. Un eval que se cae
porque el observatorio no esta levantado convierte la telemetria en un punto
unico de fallo de la medicion, que es exactamente al reves.
"""
import argparse, datetime, json, os, sys, urllib.error, urllib.request, uuid

ap = argparse.ArgumentParser()
ap.add_argument("--store", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "runs.jsonl"))
ap.add_argument("--project", default=os.environ.get("CC_LANGSMITH_PROJECT") or "mcharness-evals")
ap.add_argument("--since", help="solo runs con ts >= esta fecha ISO")
ap.add_argument("--dry-run", action="store_true", help="imprime el payload y no envia nada")
a = ap.parse_args()

endpoint = (os.environ.get("LANGSMITH_ENDPOINT") or "https://api.smith.langchain.com").rstrip("/")
api_key = os.environ.get("CC_LANGSMITH_API_KEY") or os.environ.get("LANGSMITH_API_KEY") or ""

if not os.path.exists(a.store):
    print("no hay almacen de runs todavia:", a.store)
    sys.exit(1)

runs = []
retiradas = []
for line in open(a.store, errors="replace"):
    try:
        r = json.loads(line)
    except ValueError:
        continue
    if a.since and (r.get("ts") or "") < a.since:
        continue
    # Una fila retirada del computo no se publica. report.py la deja fuera y dice
    # por que; un observatorio que la ensenara como un fail normal contradiria al
    # informe, y el dato retirado volveria por la puerta de atras. El aviso va a
    # stderr porque stdout es el payload y tiene que seguir siendo JSON puro.
    if str(r.get("excluded") or "").strip():
        retiradas.append(r)
        continue
    runs.append(r)

if retiradas:
    print("no se publican %d fila(s) retiradas del computo: %s"
          % (len(retiradas), ", ".join("%s/%s@%s" % (r.get("task"), r.get("arm"), r.get("ts"))
                                       for r in retiradas)), file=sys.stderr)

if not runs:
    print("el almacen no tiene runs en el rango pedido")
    sys.exit(1)


def parse_ts(s):
    try:
        return datetime.datetime.fromisoformat((s or "").replace("Z", "+00:00"))
    except ValueError:
        return datetime.datetime.now(datetime.timezone.utc)


def seg(dt, rid):
    """Un tramo de dotted_order: marca de tiempo compacta + uuid, como espera LangSmith."""
    return dt.strftime("%Y%m%dT%H%M%S%f") + "Z" + rid


# Una traza por (sesion, brazo): comparar brazos es el objetivo, y mezclarlos
# bajo un mismo padre haria que el arbol no se pudiera leer por brazo.
groups = {}
for r in runs:
    groups.setdefault((r.get("ts"), r.get("arm") or "on"), []).append(r)

payload = []
for (ts, arm), rs in sorted(groups.items(), key=lambda kv: str(kv[0][0])):
    start = parse_ts(ts)
    pid = str(uuid.uuid4())
    pdo = seg(start, pid)
    scored = [r for r in rs if r.get("result") in ("pass", "fail")]
    passed = sum(1 for r in scored if r["result"] == "pass")
    last_end = start
    children = []

    for r in rs:
        cstart = parse_ts(r.get("ts"))
        ms = r.get("duration_api_ms") or 0
        cend = cstart + datetime.timedelta(milliseconds=ms)
        last_end = max(last_end, cend)
        cid = str(uuid.uuid4())
        children.append({
            "id": cid,
            "trace_id": pid,
            "parent_run_id": pid,
            "dotted_order": pdo + "." + seg(cstart, cid),
            "name": r.get("task") or "tarea",
            "run_type": "chain",
            "start_time": cstart.isoformat(),
            "end_time": cend.isoformat(),
            "session_name": a.project,
            "inputs": {"task": r.get("task"), "attempt": r.get("attempt")},
            # El resultado va como texto, no como 0/1: 'error' no es un 0. Ver
            # la nota de report.py sobre por que no se coercionan a suspenso.
            "outputs": {"result": r.get("result")},
            "error": None if r.get("result") != "error" else "no se pudo medir (transcript vacio)",
            "extra": {"metadata": {
                "arm": arm,
                "harness_sha": r.get("harness_sha"),
                "model": r.get("model"),
                "cost_usd": r.get("cost_usd"),
                "num_turns": r.get("num_turns"),
                "input_tokens": r.get("input_tokens"),
                "output_tokens": r.get("output_tokens"),
                "cache_read_tokens": r.get("cache_read_tokens"),
                "permission_denials": r.get("permission_denials"),
            }},
        })

    payload.append({
        "id": pid,
        "trace_id": pid,
        "dotted_order": pdo,
        "name": "eval %s" % arm,
        "run_type": "chain",
        "start_time": start.isoformat(),
        "end_time": last_end.isoformat(),
        "session_name": a.project,
        "inputs": {"arm": arm, "tasks": len(rs)},
        "outputs": {"pass_rate": (passed / len(scored)) if scored else None,
                    "scored": len(scored),
                    "errors": sum(1 for r in rs if r.get("result") == "error")},
        "extra": {"metadata": {"arm": arm, "harness_sha": rs[0].get("harness_sha")}},
    })
    payload.extend(children)

if a.dry_run:
    print(json.dumps({"post": payload}, indent=2, ensure_ascii=False))
    sys.exit(0)

if not api_key:
    print("sin CC_LANGSMITH_API_KEY ni LANGSMITH_API_KEY: no se sube nada.")
    print("El eval ya midio; esto solo publica. Prueba el payload con --dry-run.")
    sys.exit(0)

req = urllib.request.Request(
    endpoint + "/runs/batch",
    data=json.dumps({"post": payload}).encode(),
    headers={"Content-Type": "application/json", "x-api-key": api_key},
    method="POST",
)
try:
    with urllib.request.urlopen(req, timeout=30) as resp:
        print("subido a %s (%s): %d runs, %d trazas"
              % (endpoint, resp.status, len(payload), len(groups)))
except urllib.error.URLError as e:
    # Sin traceback: llevaria la cabecera x-api-key a la salida estandar.
    print("no se pudo subir a %s: %s" % (endpoint, getattr(e, "reason", e)))
    sys.exit(1)
