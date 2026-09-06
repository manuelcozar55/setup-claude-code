#!/usr/bin/env python3
# fake_mch.py — M FALSO para los tests de task 18. Reproduce el contrato de
# `mch project <prepare|apply|query|compensate> --id U --path R` de forma
# DETERMINISTA y con un receipt durable, para poder matar el coordinador de S
# en cada frontera y verificar la recuperacion sin depender de mcharness real.
#
# Escribe el estado en <path>/.fake-mch-receipt-<uuid>.json (asi el test puede
# comprobar que S NUNCA lo toca). Verbos:
#   prepare : NOT_FOUND -> PREPARED (idempotente: si ya existe, devuelve estado)
#   apply   : PREPARED  -> APPLIED  (idempotente); crea un target "instalado"
#   query   : devuelve el estado actual (NOT_FOUND si no hay receipt)
#   compensate: PREPARED->COMPENSATED; APPLIED->COMPENSATED (borra el target)
# Un fichero <path>/.fake-mch-force-blocked hace que query/apply devuelvan
# BLOCKED (simula un receipt irrecuperable). rc 0 salvo BLOCKED (rc 1).
import json
import os
import sys

DIGEST = "fakedigest"


def receipt_path(path, uuid):
    return os.path.join(path, f".fake-mch-receipt-{uuid}.json")


def target_path(path):
    return os.path.join(path, "FAKE-PROJECTED.md")


def _blocked(path):
    return os.path.exists(os.path.join(path, ".fake-mch-force-blocked"))


def _emit(uuid, state, rc=0):
    print(json.dumps({"id": uuid, "state": state, "digest": DIGEST}))
    return rc


def main(argv):
    # Contrato REAL de mch: --path es opcion GLOBAL, antes del subcomando.
    #   mch --path R project <verb> --id U
    # Rechazamos --path DESPUES del verbo (como hace el mch real), para que el
    # fake sea un guardia fiel del contrato y no acepte lo que M rechaza.
    path = None
    rest = list(argv)
    if rest and rest[0] == "--path":
        path = rest[1]
        rest = rest[2:]
    if len(rest) < 2 or rest[0] != "project":
        sys.stderr.write("fake_mch: uso: --path R project <verb> --id U\n")
        return 2
    verb = rest[1]
    uuid = None
    i = 2
    while i < len(rest):
        if rest[i] == "--id":
            uuid = rest[i + 1]; i += 2
        elif rest[i] == "--path":
            sys.stderr.write("fake_mch: --path no va tras el subcomando "
                             "(es opcion global del mch real)\n")
            return 2
        else:
            i += 2
    if not uuid or not path:
        return 2
    recf = receipt_path(path, uuid)

    def read_state():
        if _blocked(path):
            return "BLOCKED"
        if not os.path.exists(recf):
            return "NOT_FOUND"
        try:
            return json.load(open(recf))["state"]
        except (json.JSONDecodeError, OSError, KeyError):
            return "BLOCKED"

    def write_state(state):
        with open(recf, "w") as f:
            json.dump({"id": uuid, "state": state}, f)

    if verb == "query":
        st = read_state()
        return _emit(uuid, st, rc=1 if st == "BLOCKED" else 0)

    if _blocked(path):
        return _emit(uuid, "BLOCKED", rc=1)

    if verb == "prepare":
        st = read_state()
        if st == "NOT_FOUND":
            write_state("PREPARED")
            st = "PREPARED"
        return _emit(uuid, st)

    if verb == "apply":
        st = read_state()
        if st == "NOT_FOUND":
            sys.stderr.write("apply sin prepare\n")
            return 1
        if st == "PREPARED":
            with open(target_path(path), "w") as f:
                f.write("proyectado por M falso\n")
            write_state("APPLIED")
            st = "APPLIED"
        return _emit(uuid, st)

    if verb == "compensate":
        st = read_state()
        if st in ("PREPARED", "APPLIED"):
            tp = target_path(path)
            if os.path.exists(tp):
                os.unlink(tp)
            write_state("COMPENSATED")
            st = "COMPENSATED"
        return _emit(uuid, st)

    sys.stderr.write(f"fake_mch: verbo desconocido {verb}\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
