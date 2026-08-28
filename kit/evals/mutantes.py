#!/usr/bin/env python3
"""Mutacion de los sensores del eval: rompe UNA afirmacion y exige que la suite
se ponga roja. Un sensor que sigue verde con la afirmacion rota no es un sensor.

    python3 kit/evals/mutantes.py     # ~12 s, sin red, sin coste

Salida 0 solo si TODOS los mutantes mueren y los ficheros quedan byte a byte
como estaban. Si un ancla ya no existe en el fuente, es FALLO, no aviso: un
mutante que no se aplica deja de vigilar en silencio, que es el modo de fallo
que este fichero existe para evitar.

Historico: los mutantes M1-M8 (brazos, grader, polaridad, oraculo visible) se
corrieron con scripts de usar y tirar y no estan aqui. Reproducible es todo
lo que esta en MUTANTES, de M9 en adelante: no hay ninguno fuera.
"""
import hashlib
import re
import io
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SUITE = ["bash", "kit/test/test_evals.sh"]

# (nombre, fichero, ancla, mutacion, aguja que debe aparecer en el NOT ok)
MUTANTES = [
    ("M9  guardia de ARM desconocido retirado",
     "kit/evals/run.sh",
     """  *) echo "run.sh: ARM desconocido '$ARM'. Validos: on off sin-ajustes sin-skills sin-mcp" >&2
     exit 2 ;;""",
     "  *) ;;",
     "no se rechaza"),

    ("M10 lectura de la ablacion invertida",
     "kit/evals/report.py",
     'lect = ("la pieza APORTA" if d <= -0.05 else',
     'lect = ("la pieza APORTA" if d <= -99 else',
     "la pieza aporta"),

    ("M11 guardia de modelos distintos retirado",
     "kit/evals/report.py",
     "    return (not ma or not mb or ma == mb), ma, mb",
     "    return True, ma, mb",
     "no se restan"),

    ("M12 el sensor de flags vigila un flag que no existe",
     "kit/test/test_evals.sh",
     "for flag in --setting-sources --disable-slash-commands --strict-mcp-config --model; do",
     "for flag in --setting-sources --flag-que-no-existe-jamas; do",
     "mide el harness completo"),

    ("M13 las tareas mudas dejan de contarse",
     "kit/evals/report.py",
     '        if len(res) == 1 and res <= {"pass", "fail"}:',
     '        if False:',
     "se satura en silencio"),

    ("M14 el aviso de conjunto saturado retirado",
     "kit/evals/report.py",
     "    if comunes and utiles <= max(1, len(comunes) // 5):",
     "    if comunes and utiles < 0:",
     "saturado sin aviso"),

    ("M15 el informe opina sobre mudez sin brazo de control",
     "kit/evals/report.py",
     'if "on" not in by_arm or "off" not in by_arm:\n    print("  NO MEDIBLE: hace falta el brazo de control para saber que tareas son mudas.")',
     'if False:\n    print("  NO MEDIBLE: hace falta el brazo de control para saber que tareas son mudas.")',
     "se pronuncia sobre tareas mudas"),

    ("M16 record.py deja de registrar la carga de la maquina",
     "kit/evals/record.py",
     "rec.update(maquina())",
     "rec.update({})",
     "carga, CPUs y memoria"),

    ("M17 el aviso de cargas dispares nunca salta",
     "kit/evals/report.py",
     "            if abs(on[\"load1\"] - off[\"load1\"]) > max(1.0, cpus / 4.0):",
     "            if abs(on[\"load1\"] - off[\"load1\"]) > 1e9:",
     "ni un aviso"),

    ("M18 el aviso de cargas dispares salta siempre",
     "kit/evals/report.py",
     "            if abs(on[\"load1\"] - off[\"load1\"]) > max(1.0, cpus / 4.0):",
     "            if True:",
     "sale siempre"),

    ("M19 el emisor deja de autenticarse contra el receptor",
     "kit/evals/langsmith_push.py",
     '"Content-Type": "application/json", "x-api-key": api_key',
     '"Content-Type": "application/json", "x-api-key": ""',
     "un receptor local que escucha"),

    ("M20 las tareas dejan de colgar de la traza de su brazo",
     "kit/evals/langsmith_push.py",
     '            "parent_run_id": pid,',
     '            "parent_run_id": None,',
     "no una lista suelta"),

    ("M21 el puente a Phoenix deja de ordenar las tareas",
     "kit/evals/phoenix_push.py",
     '        for r in sorted(rs, key=lambda x: x.get("task") or ""):',
     "        for r in rs:",
     "al azar del diccionario"),

    ("M22 los hijos pierden la etiqueta de brazo",
     "kit/evals/phoenix_push.py",
     '                    "eval.arm": arm,\n                    "eval.result"',
     '                    "eval.arm": "",\n                    "eval.result"',
     "etiquetada con el suyo"),

    ("M23 se apunta el primer modelo del diccionario, no el que trabajo",
     "kit/evals/record.py",
     'model = max(mu, key=lambda k: (mu[k] or {}).get("outputTokens") or 0) if mu else None',
     "model = next(iter(mu), None)",
     "no el auxiliar"),

    ("M24 el informe opina sobre una pieza que nunca se encendio",
     "kit/evals/report.py",
     "            if vistos and not sum(x.get(campo[0]) or 0 for x in vistos):",
     "            if False:",
     "parece hallazgo"),

    ("M25 el guardia de pieza apagada tapa tambien las encendidas",
     "kit/evals/report.py",
     "            if vistos and not sum(x.get(campo[0]) or 0 for x in vistos):",
     "            if vistos:",
     "el guardia no mide, tapa"),

    ("M26 el brazo de ablacion que falta no dice si merece la pena correrlo",
     "kit/evals/report.py",
     "        if campo and vistos and not sum(x.get(campo[0]) or 0 for x in vistos):",
     "        if False:",
     "para no medir nada"),
    # M27 no muta al acusador del §20: neutralizarlo con todos los correctores
    # sanos no cambia nada observable y escapa (caza = suite roja Y aguja en un
    # NOT ok). Para probar al acusador hay que darle un culpable: un check que
    # suspende a su propia solucion declarada.
    ("M27 un corrector que suspende a quien acierta tiene que ser acusado",
     "kit/evals/tasks/20-no-reescribir-lo-publicado.yaml",
     'grep -q "arreglo el parser"',
     'grep -q "cadena-que-ninguna-solucion-produce"',
     "suspende una solucion correcta"),

    # Aflojar la 12 a f.get('suma') tambien escapa, medido: el check aflojado
    # sigue rechazando el estado inicial (§10 calla) y aprueba la solucion (§20
    # calla). Lo que si acusa es volver a castigar el rastro de verificar.
    ("M28 la 12 vuelve a castigar el rastro de verificar",
     "kit/evals/tasks/12-alcance-quirurgico.yaml",
     "\\|__pycache__",
     "",
     "suspende una solucion correcta"),

    ("M29 el suelo de cobertura deja de vigilar cuantas soluciones hay",
     "kit/test/test_evals.sh",
     'if [ "$con_sol" -ge 10 ]; then',
     'if [ "$con_sol" -ge 999 ]; then',
     "cobertura de solucion insuficiente"),

    ("M30 el transcript vuelve a nombrarse por el dia y las tiradas se pisan",
     "kit/evals/run.sh",
     'keep="$E/transcripts/$id-$ARM-$attempt-${EVAL_TS//[-:]/}.jsonl"',
     'keep="$E/transcripts/$id-$ARM-$attempt-$(date +%F).jsonl"',
     "dos transcripts vivos"),

    # El otro lado: un sufijo al azar tampoco colisiona, pero deja una fila que
    # no puede senalar su evidencia. Si §23 fuera solo el recuento de ficheros,
    # esto escaparia.
    ("M31 el transcript se nombra al azar y la fila deja de poder senalarlo",
     "kit/evals/run.sh",
     'keep="$E/transcripts/$id-$ARM-$attempt-${EVAL_TS//[-:]/}.jsonl"',
     'keep="$E/transcripts/$id-$ARM-$attempt-$RANDOM$RANDOM.jsonl"',
     "funcion de la fila"),

    ("M32 las filas retiradas vuelven a entrar en el computo",
     "kit/evals/report.py",
     '    if str(r.get("excluded") or "").strip():',
     "    if False:",
     "no entra en el computo"),

    ("M33 el informe retira filas en silencio",
     "kit/evals/report.py",
     'if excluidas:\n    print("excluidas',
     'if False:\n    print("excluidas',
     "excluye una fila"),

]


def corre():
    r = subprocess.run(SUITE, capture_output=True, text=True, timeout=600)
    return r.returncode, r.stdout


def firma(l):
    """La misma asercion en un bucle imprime una linea por vuelta, y solo cambia lo
    que va entre comillas o entre parentesis (el valor probado, el obtenido). Eso no
    es ambiguedad: ambiguedad es que la aguja case con OTRA asercion."""
    l = re.sub(r"'[^']*'", "''", l)
    l = re.sub(r"\([^)]*\)", "()", l)
    return " ".join(l.split())


def md5(f):
    return hashlib.md5(io.open(f, "rb").read()).hexdigest()


def main():
    os.chdir(REPO)
    antes = {f: md5(f) for _, f, _, _, _ in MUTANTES}

    rc, out = corre()
    print("BASE: rc=%d - %s" % (rc, out.strip().splitlines()[-1]))
    if rc != 0:
        print("la suite ya esta roja sin mutar; no se puede medir nada")
        return 1

    vivos = []
    for nombre, fich, ancla, mut, aguja in MUTANTES:
        orig = io.open(fich, encoding="utf-8").read()
        if ancla not in orig:
            print("  ANCLA PERDIDA %s: ya no esta en %s" % (nombre, fich))
            vivos.append(nombre)
            continue
        respaldo = tempfile.mkstemp()[1]
        shutil.copy2(fich, respaldo)
        try:
            io.open(fich, "w", encoding="utf-8").write(orig.replace(ancla, mut, 1))
            rc, out = corre()
            motivo = {}
            for l in out.splitlines():
                if l.startswith("NOT ok") and aguja.lower() in l.lower():
                    motivo.setdefault(firma(l), l.strip())
            motivo = [motivo[k] for k in sorted(motivo)]
            if rc != 0 and len(motivo) > 1:
                # Una aguja que casa con dos aserciones distintas da el mutante por
                # cazado sin saber cual disparo: es el 'rojo por otra cosa' con otro
                # nombre, solo que aprobando. Se pide una aguja mas estrecha.
                print("  AGUJA AMBIGUA  %s: casa con %d NOT ok distintos" % (nombre, len(motivo)))
                for l in motivo:
                    print("          -> %s" % l)
                vivos.append(nombre)
            elif rc != 0 and motivo:
                print("  CAZADO  %s\n          -> %s" % (nombre, motivo[0]))
            elif rc != 0:
                # Rojo por otra cosa no vale: el sensor que se esta probando no
                # es el que disparo, y quedaria dado por bueno sin serlo.
                print("  ROJO POR OTRA COSA  %s" % nombre)
                vivos.append(nombre)
            else:
                print("  ESCAPA  %s  <-- el sensor no sirve" % nombre)
                vivos.append(nombre)
        finally:
            shutil.copy2(respaldo, fich)
            os.unlink(respaldo)

    sucios = [f for f, h in antes.items() if md5(f) != h]
    rc, out = corre()
    print("\nRESTAURADO: rc=%d - %s" % (rc, out.strip().splitlines()[-1]))
    print("muertos %d/%d" % (len(MUTANTES) - len(vivos), len(MUTANTES)))
    if sucios:
        print("AVISO: estos ficheros NO volvieron a su estado original: %s" % ", ".join(sucios))
    return 1 if (vivos or sucios or rc != 0) else 0


if __name__ == "__main__":
    sys.exit(main())
