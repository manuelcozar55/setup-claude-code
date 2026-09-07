#!/usr/bin/env python3
# installer_core.py — nucleo del instalador (task 19).
#
# QUE ES: un INTERPRETE de operaciones cerradas. No es un ejecutor generico ni
# una capa de plugins: recibe un PLAN declarativo (JSON) donde cada operacion
# nombra EXACTAMENTE una de las cuatro primitivas de task-16 y la enruta a
# kit/lib/txnwrite.py. Sobre ese interprete monta los cuatro verbos de ciclo de
# vida: install / doctor / diff / uninstall.
#
# POR QUE SEPARADO (y por que NO toca install/doctor/uninstall .sh):
#   El todo 19 dice "extract installer-core WITHOUT changing Claude". La
#   caracterizacion (scripts/claude-characterization.sh) sella el sha256 de
#   install.sh, doctor.sh y uninstall.sh. Este modulo es ADITIVO: es la pieza
#   reutilizable que los perfiles nativos (tasks 20-22) enrutaran, sin mover un
#   byte de la superficie de Claude ni de los tres scripts sellados.
#
# LO QUE APORTA SOBRE txnwrite (el valor real, no un passthrough):
#   - CONFLICTO DE PROPIEDAD: txnwrite copy-owned PISA cualquier target previo.
#     El core lleva un LEDGER de propiedad (.cckit-owned.json, 0600) y RECHAZA
#     ANTES de escribir pisar un target ajeno (existe pero no lo instalamos
#     nosotros, o su contenido on-disk no coincide con lo que sellamos).
#   - RECHAZO PRE-ESCRITURA de: operacion desconocida, ruta insegura y conflicto.
#     Todo el plan se valida ANTES de tocar el primer target: o entra entero o
#     no entra (validacion previa; la ejecucion sigue siendo por-ruta).
#   - RECUPERACION: hereda el WAL de txnwrite; un WAL corrupto/tercer-hash
#     BLOQUEA en vez de adivinar. uninstall solo retira lo que el ledger posee
#     y cuyo sha on-disk coincide: un fichero manual o modificado se preserva.
#
# GARANTIAS HONESTAS: es crash-consistency POR RUTA (cada op es una tx de
# txnwrite). NO promete atomicidad fisica multi-fichero. El ledger detecta
# propiedad por integridad (sha256), no la autentica.
#
# Solo Linux/WSL2. Sin dependencias fuera de la stdlib.
import argparse
import hashlib
import json
import os
import stat
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TXNWRITE = os.path.join(HERE, "txnwrite.py")
PY = sys.executable or "/usr/bin/python3"

LEDGER_NAME = ".cckit-owned.json"
LEDGER_SCHEMA = "installer-core-owned-v1"
PLAN_SCHEMA = "installer-core-plan-v1"

# EXACTAMENTE las cuatro primitivas cerradas de task-16. Ni una mas: una
# operacion fuera de este conjunto es un plan invalido y se rechaza pre-escritura.
PRIMITIVES = ("copy-owned", "diff-only", "json-merge-owned-keys", "managed-text-block")
# Las que ESCRIBEN un target propio (diff-only nunca escribe).
WRITING_PRIMITIVES = ("copy-owned", "json-merge-owned-keys", "managed-text-block")


class CoreError(Exception):
    pass


def _die(msg):
    raise CoreError(msg)


def _sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


# ------------------------------------------------------------- confinamiento
def _open_root(root):
    """Mismo contrato de confinamiento que txnwrite: absoluto, no '/', propiedad
    del usuario actual, sin seguir symlinks."""
    if root != "/" and root.endswith("/"):
        root = root.rstrip("/")
    if not os.path.isabs(root):
        _die(f"root debe ser absoluto: {root!r}")
    if root == "/":
        _die("root no puede ser la raiz del sistema '/'")
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    try:
        st = os.fstat(fd)
        if st.st_uid != os.geteuid():
            _die(f"root no es propiedad del usuario actual: {root!r}")
    except CoreError:
        os.close(fd)
        raise
    return fd


def _validate_rel(rel):
    """Rechaza rutas inseguras (absolutas, con segmentos vacios/./..). NO sigue
    symlinks: eso lo hace txnwrite al recorrer, y ademas lo comprobamos aqui
    contra el arbol real antes de decidir conflicto."""
    if not isinstance(rel, str) or not rel:
        _die(f"dst invalido: {rel!r}")
    if os.path.isabs(rel):
        _die(f"dst debe ser relativo al root: {rel!r}")
    parts = rel.split("/")
    for p in parts:
        if p in ("", ".", ".."):
            _die(f"dst con segmento invalido ({p!r}): {rel!r}")
    return parts


def _target_exists_regular(root, parts):
    """(existe_regular, path_absoluto, es_symlink_en_ruta). Recorre con lstat
    para no seguir symlinks: si un componente es symlink, lo señala."""
    cur = root
    for comp in parts[:-1]:
        cur = os.path.join(cur, comp)
        if os.path.islink(cur):
            return (False, None, True)
        if os.path.exists(cur) and not os.path.isdir(cur):
            # un componente intermedio existe y no es directorio: ruta imposible
            return (False, None, True)
    leaf = os.path.join(cur, parts[-1])
    if os.path.islink(leaf):
        return (False, leaf, True)
    if os.path.exists(leaf):
        st = os.lstat(leaf)
        return (stat.S_ISREG(st.st_mode), leaf, False)
    return (False, leaf, False)


# ------------------------------------------------------------------ ledger
def _ledger_path(root):
    return os.path.join(root, LEDGER_NAME)


def _read_ledger(root):
    p = _ledger_path(root)
    if not os.path.exists(p):
        return {"schema": LEDGER_SCHEMA, "owned": {}}
    if os.path.islink(p):
        _die(f"ledger de propiedad es un symlink: {p!r}")
    with open(p, encoding="utf-8") as f:
        d = json.load(f)
    if not isinstance(d, dict) or d.get("schema") != LEDGER_SCHEMA:
        _die(f"ledger de propiedad con schema desconocido: {p!r}")
    d.setdefault("owned", {})
    return d


def _write_ledger(root, ledger):
    """Escritura durable del ledger via la propia primitiva cerrada copy-owned,
    para heredar staging O_EXCL + WAL + renameat2. Nada de rename-tras-check."""
    content = (json.dumps(ledger, sort_keys=True, ensure_ascii=False, indent=2) + "\n").encode()
    stage = os.path.join(root, "." + LEDGER_NAME + ".src")
    fd = os.open(stage, os.O_WRONLY | os.O_CREAT | os.O_TRUNC | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600)
    try:
        os.write(fd, content)
        os.fsync(fd)
    finally:
        os.close(fd)
    try:
        _run_txn(["copy-owned", "--root", root, "--src", stage,
                  "--dst", LEDGER_NAME, "--mode", "0600"])
    finally:
        try:
            os.unlink(stage)
        except FileNotFoundError:
            pass


# --------------------------------------------------------------- txnwrite bridge
def _run_txn(args):
    """Invoca kit/lib/txnwrite.py con argv (shell=False). Devuelve (rc, out, err)."""
    p = subprocess.run([PY, "-I", TXNWRITE] + args,
                       stdin=subprocess.DEVNULL,
                       capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr


def _txn_args_for(op, root):
    """Traduce una operacion del plan a los argv de la primitiva. Solo lee del
    plan las claves que la primitiva conoce; nada dinamico, ningun shell."""
    name = op["op"]
    dst = op["dst"]
    if name == "copy-owned":
        return ["copy-owned", "--root", root, "--src", op["src"],
                "--dst", dst, "--mode", op.get("mode", "0644")]
    if name == "managed-text-block":
        # el contenido va por stdin en la primitiva; el plan lo trae en 'content'
        return ["managed-text-block", "--root", root, "--dst", dst,
                "--mode", op.get("mode", "0644"), "--whole-file"]
    if name == "json-merge-owned-keys":
        return ["json-merge-owned-keys", "--root", root, "--dst", dst,
                "--kit-json", op["kit_json"], "--policy", op.get("policy", "claude-settings")]
    if name == "diff-only":
        a = ["diff-only", "--root", root, "--dst", dst]
        if op.get("src"):
            a += ["--src", op["src"]]
        if op.get("label"):
            a += ["--label", op["label"]]
        return a
    _die(f"operacion desconocida: {name!r}")


# ------------------------------------------------------------------ plan
def _load_plan(path):
    if os.path.islink(path):
        _die(f"plan es un symlink: {path!r}")
    with open(path, encoding="utf-8") as f:
        plan = json.load(f)
    if not isinstance(plan, dict) or plan.get("schema") != PLAN_SCHEMA:
        _die(f"plan con schema desconocido (esperado {PLAN_SCHEMA})")
    ops = plan.get("operations")
    if not isinstance(ops, list) or not ops:
        _die("plan sin operaciones")
    return ops


def _prevalidate(root, ops, ledger, *, writing_only):
    """Valida TODO el plan ANTES de tocar el primer target. Falla en cerrado por:
    operacion desconocida, ruta insegura o conflicto de propiedad. writing_only
    limita el chequeo de conflicto a las primitivas que escriben. diff-only NUNCA
    escribe, asi que nunca se le exige propiedad (solo seguridad de ruta): un
    target ajeno preexistente es exactamente lo que un diff propone mostrar."""
    owned = ledger["owned"]
    for op in ops:
        if not isinstance(op, dict) or "op" not in op or "dst" not in op:
            _die(f"operacion mal formada: {op!r}")
        name = op["op"]
        if name not in PRIMITIVES:
            _die(f"operacion no es una primitiva cerrada: {name!r}")
        parts = _validate_rel(op["dst"])
        if writing_only and name not in WRITING_PRIMITIVES:
            continue
        exists_reg, leaf, link_in_path = _target_exists_regular(root, parts)
        if link_in_path:
            _die(f"ruta con symlink o componente no-directorio: {op['dst']!r}")
        if not exists_reg:
            continue
        if name not in WRITING_PRIMITIVES:
            continue
        # Existe un fichero regular. Solo es nuestro si el ledger lo registra
        # Y su sha on-disk coincide con el que sellamos. Cualquier otra cosa es
        # un conflicto de propiedad: no se pisa a ciegas.
        rec = owned.get(op["dst"])
        cur_sha = _sha256_file(leaf)
        if rec is None:
            _die(f"conflicto de propiedad: {op['dst']!r} ya existe y no lo instalo el core")
        if rec.get("sha256") != cur_sha:
            _die(f"conflicto de propiedad: {op['dst']!r} fue modificado fuera del core")


# ------------------------------------------------------------------ verbs
def cmd_install(a):
    root_fd = _open_root(a.root)
    os.close(root_fd)
    ops = _load_plan(a.plan)
    ledger = _read_ledger(a.root)
    _prevalidate(a.root, ops, ledger, writing_only=True)
    changed = False
    for op in ops:
        if op["op"] not in WRITING_PRIMITIVES:
            continue
        args = _txn_args_for(op, a.root)
        if op["op"] == "managed-text-block":
            # esta primitiva lee de stdin; en un plan el contenido es 'content'
            content = op.get("content", "")
            p = subprocess.run([PY, "-I", TXNWRITE] + args,
                               input=content.encode(), capture_output=True)
            rc, err = p.returncode, p.stderr.decode("utf-8", "replace")
        else:
            rc, _out, err = _run_txn(args)
        if rc != 0:
            _die(f"primitiva {op['op']} fallo en {op['dst']!r}: {err.strip()}")
        # sella propiedad: sha de lo que quedo en disco
        _, leaf, _link = _target_exists_regular(a.root, _validate_rel(op["dst"]))
        ledger["owned"][op["dst"]] = {"op": op["op"], "sha256": _sha256_file(leaf)}
        changed = True
    if changed:
        _write_ledger(a.root, ledger)
    return 0


def cmd_diff(a):
    root_fd = _open_root(a.root)
    os.close(root_fd)
    ops = _load_plan(a.plan)
    ledger = _read_ledger(a.root)
    # diff no escribe: valida operacion y ruta, pero NO exige propiedad.
    _prevalidate(a.root, ops, ledger, writing_only=False)
    for op in ops:
        # Todas las escrituras se muestran como diff-only (nunca escribe).
        if op["op"] == "diff-only":
            args = _txn_args_for(op, a.root)
        else:
            # proyecta la operacion de escritura a un diff-only del mismo dst
            dop = {"op": "diff-only", "dst": op["dst"], "src": op.get("src"),
                   "label": op.get("label", op["dst"])}
            args = _txn_args_for(dop, a.root)
        if op["op"] == "managed-text-block":
            content = op.get("content", "")
            p = subprocess.run([PY, "-I", TXNWRITE] + args,
                               input=content.encode(), capture_output=True)
            rc, out = p.returncode, p.stdout.decode("utf-8", "replace")
        else:
            rc, out, _err = _run_txn(args)
        if rc != 0:
            _die(f"diff-only fallo en {op['dst']!r}")
        sys.stdout.write(out)
    return 0


def cmd_doctor(a):
    """Solo lectura: reporta, por cada op de escritura, si el target existe y si
    su sha coincide con lo sellado en el ledger. No muta nada."""
    root_fd = _open_root(a.root)
    os.close(root_fd)
    ops = _load_plan(a.plan)
    ledger = _read_ledger(a.root)
    owned = ledger["owned"]
    report = {"schema": "installer-core-doctor-v1", "root": a.root, "targets": []}
    ok = True
    for op in ops:
        if op["op"] not in WRITING_PRIMITIVES:
            continue
        parts = _validate_rel(op["dst"])
        exists_reg, leaf, link_in_path = _target_exists_regular(a.root, parts)
        entry = {"dst": op["dst"], "present": bool(exists_reg)}
        if link_in_path:
            entry["state"] = "path-conflict"
            ok = False
        elif not exists_reg:
            entry["state"] = "absent"
        else:
            rec = owned.get(op["dst"])
            cur = _sha256_file(leaf)
            if rec is None:
                entry["state"] = "unowned"
            elif rec.get("sha256") == cur:
                entry["state"] = "owned-clean"
            else:
                entry["state"] = "owned-drifted"
        report["targets"].append(entry)
    sys.stdout.write(json.dumps(report, sort_keys=True) + "\n")
    return 0 if ok else 1


def cmd_uninstall(a):
    """Retira SOLO los targets que el ledger posee Y cuyo sha on-disk sigue
    coincidiendo con lo sellado. Un fichero manual (no en ledger) o modificado
    (sha distinto) se PRESERVA."""
    root_fd = _open_root(a.root)
    os.close(root_fd)
    ops = _load_plan(a.plan)
    ledger = _read_ledger(a.root)
    owned = ledger["owned"]
    changed = False
    for op in ops:
        if op["op"] not in WRITING_PRIMITIVES:
            continue
        dst = op["dst"]
        rec = owned.get(dst)
        if rec is None:
            continue  # no es nuestro: no se toca
        parts = _validate_rel(dst)
        exists_reg, leaf, link_in_path = _target_exists_regular(a.root, parts)
        if link_in_path or not exists_reg:
            owned.pop(dst, None)
            changed = True
            continue
        if _sha256_file(leaf) != rec.get("sha256"):
            continue  # modificado fuera del core: se preserva, no se retira
        os.unlink(leaf)
        pfd = os.open(os.path.dirname(leaf), os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
        try:
            os.fsync(pfd)
        finally:
            os.close(pfd)
        owned.pop(dst, None)
        changed = True
    if changed:
        _write_ledger(a.root, ledger)
    return 0


def main(argv):
    p = argparse.ArgumentParser(prog="installer_core", add_help=True)
    p.add_argument("--list-operations", action="store_true")
    sub = p.add_subparsers(dest="cmd")
    for verb, fn in (("install", cmd_install), ("diff", cmd_diff),
                     ("doctor", cmd_doctor), ("uninstall", cmd_uninstall)):
        sp = sub.add_parser(verb)
        sp.add_argument("--root", required=True)
        sp.add_argument("--plan", required=True)
        sp.set_defaults(fn=fn)

    a = p.parse_args(argv)
    if a.list_operations:
        sys.stdout.write("\n".join(sorted(PRIMITIVES)) + "\n")
        return 0
    if not getattr(a, "cmd", None):
        p.error("falta verbo (install|diff|doctor|uninstall)")
    try:
        return a.fn(a)
    except CoreError as e:
        sys.stderr.write("installer_core: " + str(e) + "\n")
        return 1
    except OSError as e:
        sys.stderr.write("installer_core: " + str(e) + "\n")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
