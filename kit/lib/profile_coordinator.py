#!/usr/bin/env python3
# profile_coordinator.py — coordinador transaccional del lado S (task 18).
#
# QUE ES: el "runtime capability/profile schema v1" de S y el coordinador que
# maneja, contra M (`mch project`), el ciclo transaccional de proyeccion de un
# perfil de proveedor SIN escribir nunca los targets ni el receipt de M.
#
# REPARTO M/S (invariante duro, verificado por el test):
#   - M (mcharness, `mch project <prepare|apply|query|compensate> --id U --path R`)
#     es el UNICO que escribe los targets del proyecto y su receipt durable.
#     Devuelve por stdout un JSON {"id","state",...} y rc 0 (rc 1 si BLOCKED).
#   - S (este modulo) preasigna un UUID, PERO no lo persiste en su WAL hasta que
#     M ha respondido a `prepare`. S registra en su propio WAL 0600: el UUID, el
#     estado del coordinador, el receipt/state que M devolvio, las identidades
#     (provider/surface del perfil) y las preimagenes de su propio estado S.
#   - S NUNCA escribe en `--path` de M, ni toca el receipt de M, ni adivina un
#     prior ausente. Si M dice BLOCKED, S para. Si algo de S no es reconstruible,
#     S para (nunca inventa).
#
# MAQUINA DE ESTADOS TRAS CUALQUIER CRASH (se consulta a M el estado EXACTO):
#   NOT_FOUND    -> reintentar prepare
#   PREPARED     -> aplicar o compensar de forma segura (segun la intencion)
#   APPLIED      -> guardar el receipt en el WAL de S y continuar/compensar
#   COMPENSATED  -> restaurar el estado S (su marca de instalacion) y cerrar
#   BLOCKED      -> parar
#
# El WAL de S es append-only, 0600, hash-encadenado (misma disciplina que
# task-16), con fsync de fichero y directorio. Es crash-consistency POR RUTA de
# S; no promete atomicidad fisica multi-fichero ni autentica (solo integridad).
#
# Solo Linux/WSL2. Sin dependencias fuera de la stdlib.
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys

SCHEMA_ID = "runtime-capability-v1"
S_WAL_NAME = ".cckit-profile.wal"
S_STATE_NAME = ".cckit-profile.state"

# Estados que M puede devolver (contrato de mch-projection-v1). S los consume
# tal cual; cualquier otro valor es una violacion del contrato y bloquea.
M_STATES = ("NOT_FOUND", "PREPARED", "APPLIED", "COMPENSATED", "BLOCKED")

# Estados del coordinador S (su propia maquina, distinta de la de M).
S_STATES = ("prepared", "applied", "compensated", "blocked", "complete")

_TIERS = ("structurally-conformant", "profile-certified", "lifecycle-enforced")
_MODES = ("interactive", "non-interactive")
_ENFORCE = ("enforced", "degraded", "none")


class CoordinatorError(RuntimeError):
    pass


class CoordinatorBlocked(RuntimeError):
    """El coordinador para en cerrado: preserva todo, no adivina, rc no-cero."""


def _die(msg):
    raise CoordinatorError(msg)


# ---------------------------------------------------------------- schema v1
def validate_capability(doc):
    """Valida un documento de capacidad/perfil contra el schema v1. Devuelve el
    doc normalizado (dict) o lanza CoordinatorError. Cerrado: rechaza campos
    extra, tiers/modos/enforcement desconocidos y combinaciones incoherentes."""
    if not isinstance(doc, dict):
        _die("capacidad: el documento no es un objeto JSON")
    if doc.get("schema") != SCHEMA_ID:
        _die(f"capacidad: schema desconocido/futuro {doc.get('schema')!r}; "
             f"se exige {SCHEMA_ID!r}")
    permitido = {"schema", "provider", "surface", "tier", "modes", "lifecycle"}
    extra = set(doc.keys()) - permitido
    if extra:
        _die(f"capacidad: campos fuera del contrato: {sorted(extra)}")
    for f in ("provider", "surface"):
        v = doc.get(f)
        if not isinstance(v, str) or not re.fullmatch(r"[a-z][a-z0-9_-]*", v):
            _die(f"capacidad: {f} invalido {v!r}")
    if doc.get("tier") not in _TIERS:
        _die(f"capacidad: tier invalido {doc.get('tier')!r}")
    modes = doc.get("modes")
    if (not isinstance(modes, list) or not modes
            or any(m not in _MODES for m in modes)
            or len(set(modes)) != len(modes)):
        _die(f"capacidad: modes invalidos {modes!r}")
    lc = doc.get("lifecycle")
    if not isinstance(lc, dict):
        _die("capacidad: lifecycle debe ser objeto")
    lc_permitido = {"native_stop", "enforcement", "block_cap"}
    lc_extra = set(lc.keys()) - lc_permitido
    if lc_extra:
        _die(f"capacidad: lifecycle con campos fuera del contrato: {sorted(lc_extra)}")
    if not isinstance(lc.get("native_stop"), bool):
        _die("capacidad: lifecycle.native_stop no es booleano")
    if lc.get("enforcement") not in _ENFORCE:
        _die(f"capacidad: lifecycle.enforcement invalido {lc.get('enforcement')!r}")
    cap = lc.get("block_cap", None)
    if cap is not None and (not isinstance(cap, int) or isinstance(cap, bool) or cap < 1):
        _die(f"capacidad: lifecycle.block_cap invalido {cap!r}")
    if doc["tier"] == "lifecycle-enforced" and (
            lc["enforcement"] != "enforced" or not lc["native_stop"]):
        _die("capacidad: tier 'lifecycle-enforced' exige enforcement 'enforced' "
             "y native_stop true; un ciclo degradado no puede reclamarlo")
    if lc["enforcement"] == "enforced" and doc["tier"] != "lifecycle-enforced":
        _die("capacidad: enforcement 'enforced' solo es coherente con "
             "tier 'lifecycle-enforced'")
    return doc


def capability_digest(doc):
    """Digest canonico de un perfil validado: delata cambios silenciosos."""
    doc = validate_capability(doc)
    canon = json.dumps(doc, ensure_ascii=False, sort_keys=True,
                       separators=(",", ":"))
    return hashlib.sha256(canon.encode("utf-8")).hexdigest()


# ------------------------------------------------------------------- S WAL
def _open_s_root(sroot):
    if not os.path.isabs(sroot):
        _die(f"sroot debe ser absoluto: {sroot!r}")
    if sroot == "/":
        _die("sroot no puede ser '/'")
    fd = os.open(sroot, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    st = os.fstat(fd)
    if st.st_uid != os.geteuid():
        os.close(fd)
        _die(f"sroot no es propiedad del usuario actual: {sroot!r}")
    return fd


def _record_hash(rec_no_hash):
    canon = json.dumps(rec_no_hash, sort_keys=True, separators=(",", ":"))
    return hashlib.sha256(canon.encode()).hexdigest()


def _read_s_wal(root_fd):
    try:
        fd = os.open(S_WAL_NAME, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=root_fd)
    except FileNotFoundError:
        return []
    try:
        raw = os.read(fd, 16 * 1024 * 1024)
    finally:
        os.close(fd)
    recs = []
    prev = "0" * 64
    for line in raw.decode("utf-8", "strict").splitlines():
        if not line.strip():
            continue
        try:
            rec = json.loads(line)
        except json.JSONDecodeError as e:
            raise CoordinatorBlocked(f"WAL de S corrupto (JSON): {e}") from None
        if not isinstance(rec, dict):
            raise CoordinatorBlocked("WAL de S corrupto (record no objeto)")
        rh = rec.pop("record_hash", None)
        if rec.get("prev") != prev:
            raise CoordinatorBlocked("WAL de S corrupto (cadena prev rota)")
        if rh != _record_hash(rec):
            raise CoordinatorBlocked("WAL de S corrupto (record_hash no cuadra)")
        prev = rh
        recs.append(rec)
    return recs


def _append_s_wal(root_fd, recs, rec):
    prev = "0" * 64
    if recs:
        last = {k: v for k, v in recs[-1].items() if k != "record_hash"}
        prev = _record_hash(last)
    rec = dict(rec)
    rec["prev"] = prev
    rec["record_hash"] = _record_hash(rec)
    line = (json.dumps(rec, sort_keys=True, separators=(",", ":")) + "\n").encode()
    fd = os.open(S_WAL_NAME, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW | os.O_CLOEXEC,
                 0o600, dir_fd=root_fd)
    try:
        os.write(fd, line)
        os.fsync(fd)
    finally:
        os.close(fd)
    os.fsync(root_fd)
    recs.append(rec)


# ---------------------------------------------------- estado S (marca instalada)
def _read_s_state(root_fd):
    """Lee la marca de instalacion de S (preimagen para restaurar). Ausente ->
    None; corrupta -> BLOCKED (no se adivina)."""
    try:
        fd = os.open(S_STATE_NAME, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=root_fd)
    except FileNotFoundError:
        return None
    try:
        raw = os.read(fd, 1024 * 1024)
    finally:
        os.close(fd)
    try:
        return json.loads(raw.decode("utf-8"))
    except json.JSONDecodeError as e:
        raise CoordinatorBlocked(f"estado de S corrupto: {e}") from None


def _write_s_state(root_fd, doc):
    data = (json.dumps(doc, ensure_ascii=False, sort_keys=True) + "\n").encode()
    tmp = S_STATE_NAME + ".tmp"
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC,
                 0o600, dir_fd=root_fd)
    try:
        os.write(fd, data)
        os.fsync(fd)
    finally:
        os.close(fd)
    os.rename(tmp, S_STATE_NAME, src_dir_fd=root_fd, dst_dir_fd=root_fd)
    os.fsync(root_fd)


def _clear_s_state(root_fd):
    try:
        os.unlink(S_STATE_NAME, dir_fd=root_fd)
        os.fsync(root_fd)
    except FileNotFoundError:
        pass


# ------------------------------------------------------------- driver de M
def _m_call(mch_cmd, verb, uuid, mpath):
    """Invoca `mch project <verb> --id U --path R` con shell=False y devuelve
    (state, raw_stdout). NO escribe nada en M: solo lee su stdout/rc."""
    argv = list(mch_cmd) + ["--path", mpath, "project", verb, "--id", uuid]
    try:
        cp = subprocess.run(argv, capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as e:
        raise CoordinatorBlocked(f"M no responde a {verb}: {e}") from None
    out = cp.stdout.strip()
    try:
        obj = json.loads(out) if out else {}
    except json.JSONDecodeError:
        raise CoordinatorBlocked(
            f"M devolvio stdout no-JSON en {verb}: {out!r}") from None
    state = obj.get("state")
    if state not in M_STATES:
        raise CoordinatorBlocked(
            f"M devolvio un estado fuera del contrato en {verb}: {state!r}")
    return state, obj


def _query_m(mch_cmd, uuid, mpath):
    return _m_call(mch_cmd, "query", uuid, mpath)[0]


# ---------------------------------------------------------------- coordinar
def coordinate(sroot, mpath, uuid, capability, mch_cmd, intent="apply"):
    """Coordina la transaccion de proyeccion del perfil `capability` contra M,
    con recuperacion segun el estado EXACTO consultado a M. `intent` es 'apply'
    (instalar) o 'compensate' (revertir). Devuelve el estado terminal del
    coordinador S. NUNCA escribe en mpath."""
    validate_capability(capability)
    if intent not in ("apply", "compensate"):
        _die(f"intent invalido: {intent!r}")
    root_fd = _open_s_root(sroot)
    try:
        recs = _read_s_wal(root_fd)
        # El UUID se PERSISTE en el WAL de S solo tras el primer prepare exitoso.
        # Antes de eso, un crash no deja rastro en S y se reintenta limpio.
        m_state = _query_m(mch_cmd, uuid, mpath)

        if m_state == "BLOCKED":
            _append_s_wal(root_fd, recs, _srec(uuid, "blocked", m_state, capability))
            raise CoordinatorBlocked("M esta BLOCKED: el coordinador para")

        if m_state == "NOT_FOUND":
            if intent == "compensate":
                # Nada que compensar en M; S solo restaura su marca si la puso.
                _restore_s(root_fd, recs, uuid, capability)
                return "compensated"
            # reintentar prepare
            st, _ = _m_call(mch_cmd, "prepare", uuid, mpath)
            _append_s_wal(root_fd, recs, _srec(uuid, "prepared", st, capability))
            m_state = st

        if m_state == "PREPARED":
            if intent == "compensate":
                st, _ = _m_call(mch_cmd, "compensate", uuid, mpath)
                _append_s_wal(root_fd, recs, _srec(uuid, "compensated", st, capability))
                _restore_s(root_fd, recs, uuid, capability)
                return "compensated"
            # aplicar: primero sellamos la preimagen de S, luego M escribe.
            pre = _read_s_state(root_fd)
            st, obj = _m_call(mch_cmd, "apply", uuid, mpath)
            if st == "BLOCKED":
                _append_s_wal(root_fd, recs, _srec(uuid, "blocked", st, capability))
                raise CoordinatorBlocked("M paso a BLOCKED durante apply")
            # APPLIED: guardar receipt en el WAL de S y marcar el estado de S.
            _append_s_wal(root_fd, recs,
                          _srec(uuid, "applied", st, capability, receipt=obj, pre=pre))
            _write_s_state(root_fd, {"schema": SCHEMA_ID, "uuid": uuid,
                                     "provider": capability["provider"],
                                     "surface": capability["surface"],
                                     "digest": capability_digest(capability)})
            _append_s_wal(root_fd, recs, _srec(uuid, "complete", st, capability))
            return "complete"

        if m_state == "APPLIED":
            if intent == "compensate":
                st, _ = _m_call(mch_cmd, "compensate", uuid, mpath)
                if st == "BLOCKED":
                    _append_s_wal(root_fd, recs, _srec(uuid, "blocked", st, capability))
                    raise CoordinatorBlocked("compensate de M devolvio BLOCKED")
                _append_s_wal(root_fd, recs, _srec(uuid, "compensated", st, capability))
                _restore_s(root_fd, recs, uuid, capability)
                return "compensated"
            # continuar: guardar receipt idempotente y cerrar.
            _, obj = _m_call(mch_cmd, "query", uuid, mpath)
            _append_s_wal(root_fd, recs,
                          _srec(uuid, "applied", "APPLIED", capability, receipt=obj))
            _write_s_state(root_fd, {"schema": SCHEMA_ID, "uuid": uuid,
                                     "provider": capability["provider"],
                                     "surface": capability["surface"],
                                     "digest": capability_digest(capability)})
            _append_s_wal(root_fd, recs, _srec(uuid, "complete", "APPLIED", capability))
            return "complete"

        if m_state == "COMPENSATED":
            _append_s_wal(root_fd, recs, _srec(uuid, "compensated", m_state, capability))
            _restore_s(root_fd, recs, uuid, capability)
            return "compensated"

        _die(f"estado de M no manejado: {m_state!r}")  # pragma: no cover
    finally:
        os.close(root_fd)


def _restore_s(root_fd, recs, uuid, capability):
    """Restaura el estado de S a su preimagen: si S habia marcado la instalacion,
    la retira. La preimagen se toma del WAL de S; si el WAL de S se perdio, no se
    adivina (se limpia la marca de S, que es lo unico que S posee)."""
    _clear_s_state(root_fd)
    _append_s_wal(root_fd, recs, _srec(uuid, "complete", "COMPENSATED", capability))


def _srec(uuid, sstate, m_state, capability, receipt=None, pre=None):
    if sstate not in S_STATES:
        _die(f"estado de coordinador invalido: {sstate!r}")
    rec = {
        "v": 1, "uuid": uuid, "s_state": sstate, "m_state": m_state,
        "provider": capability["provider"], "surface": capability["surface"],
        "digest": capability_digest(capability),
        "ts": _now(),
    }
    if receipt is not None:
        rec["receipt"] = receipt
    if pre is not None:
        rec["pre"] = pre
    return rec


def _now():
    import time
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())


# ------------------------------------------------------------------ subcommands
def cmd_validate(a):
    with open(a.capability, encoding="utf-8") as f:
        doc = json.load(f)
    validate_capability(doc)
    print(json.dumps({"schema": SCHEMA_ID, "valid": True,
                      "digest": capability_digest(doc)}, ensure_ascii=False))
    return 0


def cmd_digest(a):
    with open(a.capability, encoding="utf-8") as f:
        doc = json.load(f)
    print(capability_digest(doc))
    return 0


def cmd_coordinate(a):
    with open(a.capability, encoding="utf-8") as f:
        doc = json.load(f)
    mch_cmd = a.mch_cmd.split() if a.mch_cmd else ["mch"]
    state = coordinate(a.sroot, a.mpath, a.uuid, doc, mch_cmd, intent=a.intent)
    print(json.dumps({"uuid": a.uuid, "coordinator_state": state},
                     ensure_ascii=False))
    return 0


def cmd_query_s(a):
    """Consulta el estado que S tiene registrado para un UUID (read-only)."""
    root_fd = _open_s_root(a.sroot)
    try:
        recs = _read_s_wal(root_fd)
    finally:
        os.close(root_fd)
    mine = [r for r in recs if r.get("uuid") == a.uuid]
    st = mine[-1]["s_state"] if mine else "none"
    print(json.dumps({"uuid": a.uuid, "s_state": st}, ensure_ascii=False))
    return 0


def main(argv):
    p = argparse.ArgumentParser(prog="profile_coordinator", add_help=True)
    p.add_argument("--schema-id", action="store_true",
                   help="imprime el id del schema y sale")
    sub = p.add_subparsers(dest="cmd")

    sp = sub.add_parser("validate")
    sp.add_argument("--capability", required=True)
    sp.set_defaults(fn=cmd_validate)

    sp = sub.add_parser("digest")
    sp.add_argument("--capability", required=True)
    sp.set_defaults(fn=cmd_digest)

    sp = sub.add_parser("coordinate")
    sp.add_argument("--sroot", required=True)
    sp.add_argument("--mpath", required=True)
    sp.add_argument("--uuid", required=True)
    sp.add_argument("--capability", required=True)
    sp.add_argument("--mch-cmd", default="mch")
    sp.add_argument("--intent", choices=["apply", "compensate"], default="apply")
    sp.set_defaults(fn=cmd_coordinate)

    sp = sub.add_parser("query-s")
    sp.add_argument("--sroot", required=True)
    sp.add_argument("--uuid", required=True)
    sp.set_defaults(fn=cmd_query_s)

    a = p.parse_args(argv)
    if a.schema_id:
        sys.stdout.write(SCHEMA_ID + "\n")
        return 0
    if not getattr(a, "cmd", None):
        p.error("falta subcomando")
    try:
        return a.fn(a)
    except CoordinatorBlocked as e:
        sys.stderr.write("BLOCKED: " + str(e) + "\n")
        return 2
    except CoordinatorError as e:
        sys.stderr.write("profile_coordinator: " + str(e) + "\n")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
