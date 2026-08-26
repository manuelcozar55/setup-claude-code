#!/usr/bin/env python3
"""Lee runs.jsonl y responde tres preguntas, no una.

  1. ¿Pasa?        tasa de acierto por tarea, con intervalo, no un pass/fail pelado.
  2. ¿Sirve?       diferencia entre el brazo con harness y el brazo sin el (lift),
                   desglosada en tareas positivas (debe disparar) y negativas
                   (no debe): juntas se cancelan y el numero miente.
  3. ¿A que coste? dolares, tokens y latencia, SIEMPRE fuera de la nota.

Las tres separadas a proposito: una tarea puede pasar, no deberle nada al harness
y costar el triple. Meterlo todo en un numero borra justo eso.

Uso:  python3 report.py [--store runs.jsonl] [--since YYYY-MM-DD] [--md]
"""
import argparse, collections, json, math, os, sys

ap = argparse.ArgumentParser()
ap.add_argument("--store", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "runs.jsonl"))
ap.add_argument("--since", help="ignora runs anteriores a esta fecha (ISO)")
ap.add_argument("--md", action="store_true", help="tabla markdown en vez de texto plano")
a = ap.parse_args()

if not os.path.exists(a.store):
    print("no hay almacen de runs todavia:", a.store); sys.exit(1)

runs = []
for line in open(a.store, errors="replace"):
    try:
        r = json.loads(line)
    except ValueError:
        continue
    if a.since and (r.get("ts") or "") < a.since:
        continue
    runs.append(r)

if not runs:
    print("el almacen no tiene runs en el rango pedido"); sys.exit(1)


def wilson(k, n, z=1.96):
    """Intervalo de Wilson al 95 %. Con n=1 sale enorme, y eso es la respuesta
    correcta: una sola muestra no distingue una mejora de un golpe de suerte."""
    if n == 0:
        return (0.0, 1.0)
    p = k / n
    d = 1 + z * z / n
    c = p + z * z / (2 * n)
    s = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return ((c - s) / d, (c + s) / d)


def agg(rs):
    # Los 'error' (no se pudo medir) NO cuentan como fallo del agente: salen del
    # denominador y se reportan aparte. Coercionarlos a 0 inventa un suspenso.
    scored = [r for r in rs if r.get("result") in ("pass", "fail")]
    errors = [r for r in rs if r.get("result") == "error"]
    k = sum(1 for r in scored if r["result"] == "pass")
    n = len(scored)
    nums = lambda key: [r[key] for r in rs if isinstance(r.get(key), (int, float))]
    mean = lambda v: sum(v) / len(v) if v else None
    return {"k": k, "n": n, "errors": len(errors),
            "rate": (k / n) if n else None, "ci": wilson(k, n) if n else None,
            "cost": mean(nums("cost_usd")), "ms": mean(nums("duration_api_ms")),
            "tok_in": mean(nums("input_tokens")),
            "modelos": sorted({r["model"] for r in rs if r.get("model")})}


def comparables(a_rs, b_rs):
    """Dos brazos solo son comparables si corrieron el MISMO modelo. Es un riesgo
    real, no teorico: el brazo 'sin-ajustes' tira el settings.json que fija el
    modelo, asi que puede caer a otro sin avisar. Restar dos tasas de dos modelos
    distintos produce un numero con aspecto de lift que no mide el harness."""
    ma, mb = agg(a_rs)["modelos"], agg(b_rs)["modelos"]
    return (not ma or not mb or ma == mb), ma, mb


def fmt(x, nd=3):
    return "—" if x is None else ("%.*f" % (nd, x))


by_arm = collections.defaultdict(list)
for r in runs:
    by_arm[r.get("arm") or "on"].append(r)

sep = " | " if a.md else "  "
bar = "|" if a.md else " "


def row(cells):
    print((bar + sep if a.md else "") + sep.join(cells) + (sep + bar if a.md else ""))


# --- 1 y 3: por tarea, dentro de cada brazo ---------------------------------
for arm in sorted(by_arm):
    rs = by_arm[arm]
    print("\n== brazo '%s' — %d runs, %d tareas ==" % (arm, len(rs), len({r["task"] for r in rs})))
    row(["tarea".ljust(32), "n", "pass", "IC95", "err", "$/run", "ms", "tok_in"])
    if a.md:
        row(["---"] * 8)
    by_task = collections.defaultdict(list)
    for r in rs:
        by_task[r["task"]].append(r)
    for t in sorted(by_task):
        s = agg(by_task[t])
        ci = "—" if not s["ci"] else "%.2f-%.2f" % s["ci"]
        row([t.ljust(32), str(s["n"]), fmt(s["rate"], 2), ci, str(s["errors"]),
             fmt(s["cost"], 4), fmt(s["ms"], 0), fmt(s["tok_in"], 0)])
    tot = agg(rs)
    row(["TOTAL".ljust(32), str(tot["n"]), fmt(tot["rate"], 2),
         "%.2f-%.2f" % tot["ci"] if tot["ci"] else "—", str(tot["errors"]),
         fmt(tot["cost"], 4), fmt(tot["ms"], 0), fmt(tot["tok_in"], 0)])

# --- 2: lift, solo si hay con que comparar ----------------------------------
if "on" in by_arm and "off" in by_arm:
    on, off = agg(by_arm["on"]), agg(by_arm["off"])
    ok, ma, mb = comparables(by_arm["on"], by_arm["off"])
    if not ok:
        print("\n== lift del harness ==")
        print("  NO COMPARABLE: los brazos corrieron modelos distintos (%s vs %s)."
              % (",".join(ma), ",".join(mb)))
        print("  Fijar EVAL_MODEL y repetir; restar estas dos tasas mide el modelo, no el harness.")
    if ok and on["rate"] is not None and off["rate"] is not None:
        lift = on["rate"] - off["rate"]
        # Bandas adaptadas de las de SkillEvaluator para 'skill lift'. Alli se
        # aplican a dimensiones 0-1; aqui a una tasa de acierto. Con n pequeno
        # casi todo cae en NEUTRO, y esa es la lectura honesta, no un defecto.
        band = "SIRVE" if lift >= 0.05 else ("PERJUDICA" if lift <= -0.10 else "NEUTRO (ruido)")
        print("\n== lift del harness ==")
        print("  con harness %.2f (n=%d) · sin harness %.2f (n=%d) · lift %+.2f -> %s"
              % (on["rate"], on["n"], off["rate"], off["n"], lift, band))
        if on["cost"] and off["cost"]:
            print("  coste: %+.1f %% ($%.4f vs $%.4f por run)"
                  % (100 * (on["cost"] / off["cost"] - 1), on["cost"], off["cost"]))

    # El total agregado puede valer 0 porque el harness ayuda en las positivas y
    # estorba lo mismo en las negativas. Sumadas se cancelan y sale "NEUTRO":
    # el peor desenlace posible, porque parece que no pasa nada. Separadas, no.
    LECTURA = {
        "positiva": ("el harness ayuda", "el harness no llega"),
        "negativa": ("el harness no estorba", "FALSOS POSITIVOS: el harness estorba"),
    }
    for tipo in ("positiva", "negativa") if ok else ():
        sub_on = [r for r in by_arm["on"] if r.get("tipo") == tipo]
        sub_off = [r for r in by_arm["off"] if r.get("tipo") == tipo]
        if not sub_on or not sub_off:
            continue
        so, sf = agg(sub_on), agg(sub_off)
        if so["rate"] is None or sf["rate"] is None:
            continue
        d = so["rate"] - sf["rate"]
        bien, mal = LECTURA[tipo]
        print("  %-9s (%2d/%2d runs) %.2f vs %.2f · %+.2f -> %s"
              % (tipo, so["n"], sf["n"], so["rate"], sf["rate"], d,
                 bien if (d >= 0 if tipo == "negativa" else d >= 0.05) else mal))
else:
    print("\n== lift del harness ==")
    print("  NO MEDIBLE: hace falta el brazo de control. Sin el, esto mide el modelo,")
    print("  no el harness. Ver README.md, seccion 'El brazo de control'.")

# --- 2b: ablacion por componente -------------------------------------------
# El lift de arriba dice si el harness sirve; esto dice QUE PIEZA sirve, que es
# otra pregunta. Anthropic lo propone como metodo y ninguna de las dos fuentes de
# NVIDIA lo hace: SkillEvaluator es un interruptor binario del skill entero y
# labs-OO-Agents no documenta ablacion ninguna. Ver EVAL-CRITERIA.md, E22.
ABL = {
    "sin-ajustes": "hooks, permisos y env",
    "sin-skills": "skills y comandos",
    "sin-mcp": "servidores MCP",
}
presentes = [x for x in ABL if x in by_arm]
print("\n== ablacion por componente ==")
if not presentes:
    print("  SIN DATOS: correr ARM=sin-ajustes, ARM=sin-skills y ARM=sin-mcp.")
    print("  Sin esto, 'el harness sirve' no llega nunca a 'esta pieza sirve'.")
elif "on" not in by_arm:
    print("  NO MEDIBLE: hay brazos de ablacion pero ninguno con el harness completo")
    print("  contra el que restar. Correr ARM=on.")
else:
    todo = agg(by_arm["on"])
    for arm in presentes:
        ok, ma, mb = comparables(by_arm[arm], by_arm["on"])
        if not ok:
            print("  %-12s NO COMPARABLE: modelos distintos (%s vs %s)"
                  % (arm, ",".join(ma), ",".join(mb)))
            continue
        s = agg(by_arm[arm])
        if s["rate"] is None or todo["rate"] is None:
            continue
        d = s["rate"] - todo["rate"]
        # Quitar la pieza y BAJAR es la senal de que la pieza aportaba. Subir no
        # es "mejor sin ella" a la ligera: con n pequeno lo normal es ruido, y la
        # banda de +-0,05 lo dice en vez de dejar que se lea como un hallazgo.
        lect = ("la pieza APORTA" if d <= -0.05 else
                "la pieza ESTORBA" if d >= 0.05 else "no se distingue del ruido")
        ci = "%.2f-%.2f" % s["ci"] if s["ci"] else "—"
        print("  %-12s (%-22s) %.2f [%s] vs %.2f con todo · %+.2f -> %s"
              % (arm, ABL[arm], s["rate"], ci, todo["rate"], d, lect))
