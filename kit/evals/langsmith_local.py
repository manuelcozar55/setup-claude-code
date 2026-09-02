#!/usr/bin/env python3
"""Receptor local del ingest de LangSmith. NO es LangSmith.

Habla el trozo del protocolo que usa langsmith_push.py (POST /runs/batch) y
escribe lo que recibe en un JSONL. Existe por un motivo concreto: LangSmith
autoalojado es de pago y necesita LANGSMITH_LICENSE_KEY, asi que sin licencia
"medible en LangSmith local" se quedaba en una afirmacion sin sensor. Con esto,
el emisor se prueba de punta a punta -- red real, cabeceras reales, arbol real --
por cero euros y sin depender de que Docker este levantado.

    python3 kit/evals/langsmith_local.py                  # escucha en :1984
    python3 kit/evals/langsmith_local.py --tree            # lee lo recibido

Y entonces, en otra terminal:

    LANGSMITH_ENDPOINT=http://127.0.0.1:1984 LANGSMITH_API_KEY=local \\
        python3 kit/evals/langsmith_push.py

Lo que este fichero NO da: interfaz web, busqueda, comparacion de tiradas. Para
eso hace falta LangSmith de verdad (nube, o autoalojado con licencia) y el unico
cambio es LANGSMITH_ENDPOINT. Que ese cambio baste es justo lo que se prueba aqui.
"""
import argparse, json, os, sys
from http.server import BaseHTTPRequestHandler, HTTPServer

AQUI = os.path.dirname(os.path.abspath(__file__))

ap = argparse.ArgumentParser()
ap.add_argument("--port", type=int, default=1984, help="0 = puerto libre que elija el sistema")
ap.add_argument("--store", default=os.path.join(AQUI, "langsmith-local.jsonl"))
ap.add_argument("--max-requests", type=int, default=0, help="atiende N peticiones y sale (para los tests)")
ap.add_argument("--tree", action="store_true", help="no escucha: imprime el arbol de lo ya recibido")
a = ap.parse_args()


def arbol(store):
    if not os.path.exists(store):
        print("todavia no ha llegado nada a", store)
        return 1
    runs = []
    for line in open(store, errors="replace"):
        try:
            runs.append(json.loads(line))
        except ValueError:
            continue
    padres = [r for r in runs if not r.get("parent_run_id")]
    for p in sorted(padres, key=lambda r: r.get("dotted_order") or ""):
        out = p.get("outputs") or {}
        tasa = out.get("pass_rate")
        print("\n%s  [%s]  %s" % (
            p.get("name"), p.get("session_name"),
            "sin nota" if tasa is None else "acierto %.0f %% de %s" % (100 * tasa, out.get("scored"))))
        hijos = [r for r in runs if r.get("parent_run_id") == p.get("id")]
        for c in sorted(hijos, key=lambda r: r.get("dotted_order") or ""):
            meta = ((c.get("extra") or {}).get("metadata") or {})
            coste = meta.get("cost_usd")
            print("  %-24s %-6s %s" % (
                c.get("name"), ((c.get("outputs") or {}).get("result") or "?"),
                "" if coste is None else "$%.4f" % coste))
    return 0


if a.tree:
    sys.exit(arbol(a.store))


class Handler(BaseHTTPRequestHandler):
    store = a.store

    def log_message(self, *_):
        pass  # el log por defecto va a stderr y ensucia la salida de los tests

    def _responde(self, code, body):
        raw = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self):
        if self.path.rstrip("/") != "/runs/batch":
            # No se calla: si el emisor cambia de ruta, esto lo dice en vez de
            # dejar que las trazas se pierdan en un 404 silencioso.
            print("ruta desconocida:", self.path, flush=True)
            self._responde(404, {"detail": "aqui solo se atiende /runs/batch"})
            return
        if not self.headers.get("x-api-key"):
            print("rechazado: sin cabecera x-api-key", flush=True)
            self._responde(401, {"detail": "falta x-api-key"})
            return
        try:
            cuerpo = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        except ValueError:
            self._responde(422, {"detail": "el cuerpo no es JSON"})
            return
        runs = cuerpo.get("post") or []
        with open(Handler.store, "a") as f:
            for r in runs:
                f.write(json.dumps(r, ensure_ascii=False) + "\n")
        print("recibidos %d runs -> %s" % (len(runs), Handler.store), flush=True)
        self._responde(202, {})


srv = HTTPServer(("127.0.0.1", a.port), Handler)
print("escuchando en http://127.0.0.1:%d" % srv.server_port, flush=True)
try:
    if a.max_requests:
        for _ in range(a.max_requests):
            srv.handle_request()
    else:
        srv.serve_forever()
except KeyboardInterrupt:
    print("\nparado. El arbol de lo recibido:  python3 %s --tree" % __file__)
