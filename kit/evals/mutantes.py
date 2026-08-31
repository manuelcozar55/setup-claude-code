#!/usr/bin/env python3
"""Mutacion de los sensores del eval: rompe UNA afirmacion y exige que la suite
se ponga roja. Un sensor que sigue verde con la afirmacion rota no es un sensor.

    python3 kit/evals/mutantes.py     # ~4 min, sin red, sin coste

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
SUITE_DOC = ["bash", "kit/test/test_doc_claims.sh"]
ALMACEN = "kit/evals/runs.jsonl"

# Cada mutante puede declarar CUAL suite deberia cazarlo (6.o campo, por defecto
# SUITE). No se corren las dos siempre por dos motivos, y el segundo pesa mas que
# el primero: correr las dos multiplicaria el coste -test_evals.sh 9,4 s mas
# test_doc_claims.sh 8,8 s por cada mutante, de 191 s a ~580 s- y, sobre todo,
# "muertos N/N" dejaria de decir QUE sensor vigila cada afirmacion. Un mutante
# que muere por la suite equivocada es un ROJO POR OTRA COSA dado por bueno.
#
# (nombre, fichero, ancla, mutacion, aguja que debe aparecer en el NOT ok[, suite])
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
     'keep="$E/transcripts/$id-$ARM-$attempt-${EVAL_TS//[-:]/}-p$EVAL_RUN.jsonl"',
     'keep="$E/transcripts/$id-$ARM-$attempt-$(date +%F).jsonl"',
     "no pisa el fichero de la primera"),

    # El otro lado: un sufijo al azar tampoco colisiona, pero deja una fila que
    # no puede senalar su evidencia. Si §23 fuera solo el recuento de ficheros,
    # esto escaparia.
    ("M31 el transcript se nombra al azar y la fila deja de poder senalarlo",
     "kit/evals/run.sh",
     'keep="$E/transcripts/$id-$ARM-$attempt-${EVAL_TS//[-:]/}-p$EVAL_RUN.jsonl"',
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

    # Las dos vias de colision que el ts de segundos no cerraba, una por mutante.
    ("M34 la misma tarea repetida en una invocacion vuelve a colar dos filas",
     "kit/evals/run.sh",
     """    for y in ${TAREAS[@]+"${TAREAS[@]}"}; do
      [ "$y" = "$f" ] || continue
      echo "run.sh: la tarea '$a' esta repetida; para repetirla usa RUNS=n" >&2
      exit 2
    done""",
     "    :",
     "dos veces en una invocacion"),

    ("M35 el nombre pierde el pid y dos invocaciones del mismo segundo se pisan",
     "kit/evals/run.sh",
     'keep="$E/transcripts/$id-$ARM-$attempt-${EVAL_TS//[-:]/}-p$EVAL_RUN.jsonl"',
     'keep="$E/transcripts/$id-$ARM-$attempt-${EVAL_TS//[-:]/}.jsonl"',
     "en el mismo segundo"),

    # El otro lado de M35: el pid en el nombre no vale de nada si la fila no lo
    # guarda, porque entonces el nombre deja de poder reconstruirse desde la fila.
    ("M36 record.py deja de grabar el pid y la fila ya no llega a su evidencia",
     "kit/evals/record.py",
     '    "run_pid": os.environ.get("EVAL_RUN"),',
     '    "run_pid": None,',
     "derivables de su fila"),

    ("M37 langsmith vuelve a publicar la fila retirada",
     "kit/evals/langsmith_push.py",
     '    if str(r.get("excluded") or "").strip():',
     "    if False:",
     "langsmith_push: la fila retirada"),

    ("M38 phoenix vuelve a publicar la fila retirada",
     "kit/evals/phoenix_push.py",
     '    if str(r.get("excluded") or "").strip():',
     "    if False:",
     "phoenix: la fila retirada"),

    # La suite que mide la documentacion no se vigilaba a si misma: vaciarla
    # entera dejaba `make test` en rc=0 porque el Makefile solo mira el rc.
    ("M39 la suite que mide la documentacion se vacia y no asevera nada",
     "kit/test/test_doc_claims.sh",
     "pass=0; fail=0; skipped=0",
     'pass=0; fail=0; skipped=0\necho "== 0 passed, 0 failed =="\nexit 0',
     "el suelo es"),

    # No basta con vigilar el disparador del aviso (eso ya lo hace M14): la FRASE
    # tiene que decir la cifra contada, o vuelve a salir identica al 85 % y al
    # 100 %. Este mutante deja el umbral intacto y solo deforma el numero.
    ("M40 el aviso de saturacion miente en la cifra que ha contado",
     "kit/evals/report.py",
     '        print("  SATURADO: %d de %d tareas ya no distinguen nada. El numero de"\n'
     "              % (len(mudas), len(comunes)))",
     '        print("  SATURADO: %d de %d tareas ya no distinguen nada. El numero de"\n'
     "              % (len(comunes), len(comunes)))",
     "no cuadra con el almacen",
     SUITE_DOC),

]


def suite_de(m):
    return m[5] if len(m) > 5 else SUITE


def corre(suite):
    r = subprocess.run(suite, capture_output=True, text=True, timeout=600)
    return r.returncode, r.stdout


def firma(l):
    """La misma asercion en un bucle imprime una linea por vuelta y solo cambia lo que
    va entre comillas (M9 imprime una por brazo). Eso no es ambiguedad: ambiguedad es
    que la aguja case con OTRA asercion.

    Lo que iba entre parentesis SI se compara. Normalizarlo tambien tapaba ambiguedad
    de verdad -dos aserciones distintas que solo se diferencian en el parentesis
    quedaban con la misma firma y el mutante salia CAZADO sin saber cual disparo- y
    medido sobre la tanda entera no protegia nada: 30/30 y cero AGUJA AMBIGUA sin esa
    linea. Era un falso negativo pagado por un beneficio que nadie cobraba."""
    return " ".join(re.sub(r"'[^']*'", "''", l).split())


def md5(f):
    return hashlib.md5(io.open(f, "rb").read()).hexdigest()


def main():
    os.chdir(REPO)
    antes = {m[1]: md5(m[1]) for m in MUTANTES}
    suites = []
    for m in MUTANTES:
        if suite_de(m) not in suites:
            suites.append(suite_de(m))

    for suite in suites:
        rc, out = corre(suite)
        print("BASE: rc=%d - %s (%s)" % (rc, out.strip().splitlines()[-1], suite[-1]))
        if rc != 0:
            print("la suite ya esta roja sin mutar; no se puede medir nada")
            return 1

    # Sin almacen, test_doc_claims.sh salta sus comprobaciones de cifras: un
    # mutante vigilado por ella escaparia sin que ese verde signifique nada. Se
    # declara y se cuenta aparte, como el skip de la propia suite, en vez de
    # darlo por muerto o por vivo.
    sin_almacen = not os.path.exists(ALMACEN)
    no_medibles = []

    vivos = []
    for m in MUTANTES:
        nombre, fich, ancla, mut, aguja = m[:5]
        suite = suite_de(m)
        if suite is SUITE_DOC and sin_almacen:
            print("  NO MEDIBLE  %s: falta %s y la suite salta las cifras" % (nombre, ALMACEN))
            no_medibles.append(nombre)
            continue
        orig = io.open(fich, encoding="utf-8").read()
        if ancla not in orig:
            print("  ANCLA PERDIDA %s: ya no esta en %s" % (nombre, fich))
            vivos.append(nombre)
            continue
        respaldo = tempfile.mkstemp()[1]
        shutil.copy2(fich, respaldo)
        try:
            io.open(fich, "w", encoding="utf-8").write(orig.replace(ancla, mut, 1))
            rc, out = corre(suite)
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
    print("")
    rc = 0
    for suite in suites:
        r, out = corre(suite)
        print("RESTAURADO: rc=%d - %s (%s)" % (r, out.strip().splitlines()[-1], suite[-1]))
        rc = rc or r
    medidos = len(MUTANTES) - len(no_medibles)
    print("muertos %d/%d" % (medidos - len(vivos), medidos))
    if no_medibles:
        print("NO MEDIBLES (fuera del denominador): %s" % ", ".join(no_medibles))
    if sucios:
        print("AVISO: estos ficheros NO volvieron a su estado original: %s" % ", ".join(sucios))
    return 1 if (vivos or sucios or rc != 0) else 0


if __name__ == "__main__":
    sys.exit(main())
