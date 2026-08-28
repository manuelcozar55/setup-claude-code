#!/usr/bin/env python3
"""Sube runs.jsonl a un Phoenix local: misma forma de arbol que langsmith_push.py.

Existe porque "medible en local" no tiene salida por LangSmith: el autoalojado es
de pago (LANGSMITH_LICENSE_KEY, se pide a ventas) y no hay tramo gratuito ni para
desarrollo. Phoenix (Arize, OSS) da lo que aqui se necesita -- interfaz web, arbol
por brazo, atributos por tarea -- sin Docker y sin licencia:

    ~/.venvs/tools/bin/phoenix serve                  # http://localhost:6006
    ~/.venvs/tools/bin/python kit/evals/phoenix_push.py

ESTE FICHERO NO ESTA EN EL CAMINO CALIENTE DEL EVAL. run.sh no lo llama y el eval
no depende de el: es la unica pieza del repo que necesita SDK (opentelemetry, en
~/.venvs/tools), y por eso se ejecuta con el python de ese venv y no con el del
sistema. Si el eval dependiera de esto, el observatorio seria punto unico de fallo
de la medicion, que es justo al reves.

    --dry-run  imprime el arbol que emitiria, sin SDK y sin red. Es lo que
               comprueba test_evals.sh, que corre con el python del sistema.
"""
import argparse, datetime, json, os, sys

AQUI = os.path.dirname(os.path.abspath(__file__))

ap = argparse.ArgumentParser()
ap.add_argument("--store", default=os.path.join(AQUI, "runs.jsonl"))
ap.add_argument("--project", default=os.environ.get("CC_PHOENIX_PROJECT") or "mcharness-evals")
ap.add_argument("--endpoint", default=os.environ.get("PHOENIX_ENDPOINT") or "http://127.0.0.1:6006")
ap.add_argument("--dry-run", action="store_true", help="imprime el arbol y no envia nada")
a = ap.parse_args()

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
    print("el almacen esta vacio:", a.store)
    sys.exit(1)


def nanos(s):
    """ISO -> nanosegundos desde epoch, que es lo que pide OpenTelemetry."""
    try:
        d = datetime.datetime.fromisoformat((s or "").replace("Z", "+00:00"))
    except ValueError:
        d = datetime.datetime.now(datetime.timezone.utc)
    return int(d.timestamp() * 1_000_000_000)


def arbol():
    """Un padre por (sesion, brazo) y un hijo por tarea. Identico criterio que en
    langsmith_push.py: mezclar brazos bajo un mismo padre haria ilegible justo la
    comparacion que es el objetivo del eval."""
    grupos = {}
    for r in runs:
        grupos.setdefault((r.get("ts"), r.get("arm") or "on"), []).append(r)

    for (ts, arm), rs in sorted(grupos.items(), key=lambda kv: str(kv[0][0])):
        ini = nanos(ts)
        con_nota = [r for r in rs if r.get("result") in ("pass", "fail")]
        aciertos = sum(1 for r in con_nota if r["result"] == "pass")
        hijos, fin = [], ini
        # Ordenados por tarea: los runs de una misma sesion comparten ts, asi que
        # sin esto el orden lo decide el azar y el arbol se lee distinto cada vez.
        for r in sorted(rs, key=lambda x: x.get("task") or ""):
            ci = nanos(r.get("ts"))
            cf = ci + int((r.get("duration_api_ms") or 0) * 1_000_000)
            fin = max(fin, cf)
            hijos.append({
                "nombre": r.get("task") or "tarea", "ini": ci, "fin": cf,
                "error": r.get("result") == "error",
                "attrs": {
                    "openinference.span.kind": "CHAIN",
                    "input.value": json.dumps({"task": r.get("task"), "attempt": r.get("attempt")}),
                    # El resultado viaja como texto, no como 0/1: un 'error' no es
                    # un suspenso. Misma razon que en report.py.
                    "output.value": json.dumps({"result": r.get("result")}),
                    "eval.arm": arm,
                    "eval.result": r.get("result") or "?",
                    "eval.model": r.get("model") or "",
                    "eval.cost_usd": float(r.get("cost_usd") or 0.0),
                    "eval.num_turns": int(r.get("num_turns") or 0),
                    "eval.harness_sha": r.get("harness_sha") or "",
                    "eval.load1": float(r.get("load1") or 0.0),
                },
            })
        yield {
            "nombre": "eval " + arm, "ini": ini, "fin": fin, "error": False,
            "attrs": {
                "openinference.span.kind": "CHAIN",
                "input.value": json.dumps({"arm": arm, "tasks": len(rs)}),
                "output.value": json.dumps({
                    "pass_rate": (aciertos / len(con_nota)) if con_nota else None,
                    "scored": len(con_nota),
                    "errors": sum(1 for r in rs if r.get("result") == "error")}),
                "eval.arm": arm,
            },
        }, hijos


if a.dry_run:
    salida = [{"padre": p["nombre"], "attrs": p["attrs"],
               "hijos": [{"nombre": h["nombre"], "attrs": h["attrs"]} for h in hijos]}
              for p, hijos in arbol()]
    print(json.dumps(salida, indent=2, ensure_ascii=False))
    sys.exit(0)

try:
    from opentelemetry import trace
    from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
    from opentelemetry.sdk.resources import Resource
    from opentelemetry.sdk.trace import TracerProvider
    from opentelemetry.sdk.trace.export import SimpleSpanProcessor
    from opentelemetry.trace import Status, StatusCode
except ImportError:
    print("falta el SDK de OpenTelemetry. Este emisor NO corre con el python del")
    print("sistema a proposito; usa el venv de herramientas:")
    print("  ~/.venvs/tools/bin/pip install arize-phoenix")
    print("  ~/.venvs/tools/bin/python kit/evals/phoenix_push.py")
    print("Para ver el arbol sin SDK y sin red:  --dry-run")
    sys.exit(1)

# Phoenix separa proyectos por 'openinference.project.name'. Con solo
# 'service.name' todo cae en 'default' y las tiradas se mezclan sin avisar.
prov = TracerProvider(resource=Resource.create({
    "openinference.project.name": a.project, "service.name": a.project}))
prov.add_span_processor(SimpleSpanProcessor(
    OTLPSpanExporter(endpoint=a.endpoint.rstrip("/") + "/v1/traces")))
tracer = prov.get_tracer("mcharness-evals")

trazas = tareas = 0
for padre, hijos in arbol():
    sp = tracer.start_span(padre["nombre"], start_time=padre["ini"], attributes=padre["attrs"])
    ctx = trace.set_span_in_context(sp)
    for h in hijos:
        c = tracer.start_span(h["nombre"], context=ctx, start_time=h["ini"], attributes=h["attrs"])
        if h["error"]:
            c.set_status(Status(StatusCode.ERROR, "no se pudo medir (transcript vacio)"))
        c.end(end_time=h["fin"])
        tareas += 1
    sp.end(end_time=padre["fin"])
    trazas += 1
prov.shutdown()
print("enviado a %s: %d trazas, %d tareas. Proyecto '%s'."
      % (a.endpoint, trazas, tareas, a.project))
