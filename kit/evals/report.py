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
# Una fila con "excluded" no vacio queda FUERA de todo computo. Es para el dato
# cuyo instrumento estaba averiado y cuya evidencia ya no existe: ni se corrige a
# mano (seria inventarlo) ni se deja dentro (seria publicarlo sabiendolo roto).
# Retirarlo en silencio seria el mismo pecado, asi que el informe lo dice.
excluidas = []
for line in open(a.store, errors="replace"):
    try:
        r = json.loads(line)
    except ValueError:
        continue
    if not isinstance(r, dict):
        continue
    if a.since and (r.get("ts") or "") < a.since:
        continue
    if str(r.get("excluded") or "").strip():
        excluidas.append(r)
        continue
    runs.append(r)

if excluidas:
    print("excluidas %d fila(s), fuera de todo computo: %s" % (len(excluidas), " · ".join(
        "%s/%s@%s (%s)" % (r.get("task"), r.get("arm"), r.get("ts"), str(r.get("excluded")).strip())
        for r in excluidas)))

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
            "load1": mean(nums("load1")),
            "cpus": max(nums("cpus")) if nums("cpus") else None,
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
        # La carga de la maquina no toca la NOTA (el grader es determinista), pero
        # si el coste y la latencia. Aqui corre en WSL2 con el proxy compitiendo,
        # asi que dos brazos medidos con maquinas distintas de ocupadas no tienen
        # comparable la parte de "a que coste".
        if on["load1"] is not None and off["load1"] is not None:
            cpus = on["cpus"] or off["cpus"] or 4
            print("  carga media al correr: %.2f vs %.2f (de %d CPUs)"
                  % (on["load1"], off["load1"], cpus))
            if abs(on["load1"] - off["load1"]) > max(1.0, cpus / 4.0):
                print("  AVISO: los dos brazos corrieron con la maquina distinta de ocupada.")
                print("  La nota aguanta (el grader es determinista), pero la latencia y el")
                print("  coste de arriba no son comparables. Repetir con la maquina en reposo.")

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

# --- 2c: poder discriminante del conjunto (E16) -----------------------------
# Hamel: una tasa de acierto que tiende a 100 % dejo de informar. Aqui se mide
# mas fino que con un umbral sobre el total: una tarea que da el MISMO resultado
# en los dos brazos, en todas sus repeticiones, no puede mover el lift. Es peso
# muerto, se pague o no. Sin esto, el conjunto se satura poco a poco y el informe
# sigue diciendo "20 tareas" cuando las que deciden son cuatro.
print("\n== poder discriminante del conjunto ==")
if "on" not in by_arm or "off" not in by_arm:
    print("  NO MEDIBLE: hace falta el brazo de control para saber que tareas son mudas.")
else:
    def por_tarea(arm):
        d = collections.defaultdict(list)
        for r in by_arm[arm]:
            d[r["task"]].append(r)
        return d
    t_on, t_off = por_tarea("on"), por_tarea("off")
    comunes = sorted(set(t_on) & set(t_off))
    mudas = []
    for t in comunes:
        res = {r.get("result") for r in t_on[t]} | {r.get("result") for r in t_off[t]}
        # Un unico resultado en los dos brazos y en todas las repeticiones: la
        # tarea no discrimina nada. 'error' no cuenta como mudez, es una averia.
        if len(res) == 1 and res <= {"pass", "fail"}:
            mudas.append(t)
    utiles = len(comunes) - len(mudas)
    print("  mudas: %d/%d tareas dieron el mismo resultado en los dos brazos y en todas"
          % (len(mudas), len(comunes)))
    print("         sus repeticiones. No pueden mover el lift: el conjunto que decide")
    print("         es de %d tarea(s), no de %d." % (utiles, len(comunes)))
    if mudas:
        print("         %s" % ", ".join(mudas))
    if comunes and utiles <= max(1, len(comunes) // 5):
        print("  SATURADO: cuatro de cada cinco tareas ya no distinguen nada. El numero de")
        print("  arriba seguira subiendo sin que el harness mejore. Toca subir el suelo:")
        print("  retirar las mudas y minar fallos nuevos (README.md, 'Como crecer').")

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
    # Ablar una pieza que el agente no llego a usar no mide la pieza: mide nada,
    # y con pinta de resultado. Medido: en las 26 tiradas del brazo completo hubo
    # CERO invocaciones de Skill, porque el agente corre en un mktemp -d y las
    # skills del repo no estan ahi. Ver EVAL-CRITERIA.md, E27.
    USO = {"sin-skills": ("skill_calls", "skills"), "sin-mcp": ("mcp_calls", "servidores MCP")}
    for arm in presentes:
        campo = USO.get(arm)
        if campo:
            vistos = [x for x in by_arm["on"] if x.get(campo[0]) is not None]
            if vistos and not sum(x.get(campo[0]) or 0 for x in vistos):
                print("  %-12s NO MEDIBLE: %s no se activaron ni una vez en el brazo"
                      % (arm, campo[1]))
                print("               completo (%d tiradas). Apagar lo que nunca se"
                      " enciende no mueve nada." % len(vistos))
                continue
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
    # Los brazos que faltan, dichos por su nombre: y si la pieza no se activo
    # nunca, tambien que correrlos no mediria nada. Son 20 llamadas de API cada
    # uno; callarlo sale caro.
    for arm in [x for x in ABL if x not in presentes]:
        campo = USO.get(arm)
        vistos = [x for x in by_arm["on"] if campo and x.get(campo[0]) is not None]
        if campo and vistos and not sum(x.get(campo[0]) or 0 for x in vistos):
            print("  %-12s SIN DATOS, y correrlo no mediria nada: %s no se activaron"
                  " ni una vez" % (arm, campo[1]))
        else:
            print("  %-12s SIN DATOS: correr ARM=%s" % (arm, arm))
