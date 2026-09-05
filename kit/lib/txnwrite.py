#!/usr/bin/env python3
# txnwrite.py — primitivas de escritura cerrada del instalador (task 16).
#
# Cuatro primitivas y NADA MAS: copy-owned, json-merge-owned-keys,
# managed-text-block, diff-only. Las tres primeras escriben; diff-only nunca
# escribe. Toda escritura hereda el patron transaccional de task-6:
#
#   - El root se abre con O_DIRECTORY|O_NOFOLLOW y se exige propiedad del
#     usuario actual; cada componente de la ruta destino se recorre con
#     openat(O_NOFOLLOW), rechazando symlinks, '..', segmentos vacios y raiz.
#   - El staging se crea O_CREAT|O_EXCL|O_NOFOLLOW en 0600, se escribe entero,
#     se fsync, se le fija el modo final.
#   - Un WAL 0600 hash-encadenado registra prepared->committed con fsync antes
#     de tocar el target.
#   - La publicacion usa renameat2: RENAME_NOREPLACE al crear, RENAME_EXCHANGE
#     al reemplazar, verificando que el inodo desplazado tras el swap sigue
#     teniendo el preimage congelado (si no, se deshace el swap y bloquea).
#     NUNCA rename ordinario tras comprobar: eso deja una ventana de carrera.
#   - fsync de fichero Y del directorio padre.
#
# GARANTIAS HONESTAS (lo que esto NO es):
#   - Es crash-consistency POR RUTA: recover lleva cada target a su preimage o
#     a su postimage, o BLOQUEA. Una instalacion multi-fichero es una secuencia
#     de transacciones por ruta; un fallo puede dejar unas comprometidas y otras
#     no. NO es atomicidad fisica multi-fichero.
#   - renameat2 evita la carrera del rename-tras-check; si no esta disponible,
#     se falla en cerrado, sin caer a un rename ordinario.
#   - El WAL detecta corrupcion (integridad), no la autentica: quien pueda
#     reescribir el WAL entero puede fabricar uno coherente.
#
# Solo Linux/WSL2. Sin dependencias fuera de la stdlib.
import argparse
import ctypes
import ctypes.util
import hashlib
import json
import os
import stat
import sys

WAL_NAME = ".cckit-txn.wal"
STAGE_DIR = ".cckit-txn"
RENAME_NOREPLACE = 1
RENAME_EXCHANGE = 2

# Numero de syscall renameat2 por arquitectura (Linux).
_RENAMEAT2_NR = {
    "x86_64": 316,
    "aarch64": 276,
    "armv7l": 382,
    "armv6l": 382,
    "ppc64le": 357,
    "s390x": 347,
    "riscv64": 276,
}


class TxnError(Exception):
    pass


def _die(msg):
    raise TxnError(msg)


# ------------------------------------------------------------------ renameat2
_libc = ctypes.CDLL(ctypes.util.find_library("c") or "libc.so.6", use_errno=True)


def _renameat2(olddirfd, oldname, newdirfd, newname, flags):
    """renameat2 via glibc si existe; si no, via syscall(2). Sin fallback a
    rename ordinario: si renameat2 no esta, se falla en cerrado."""
    fn = getattr(_libc, "renameat2", None)
    if fn is not None:
        fn.restype = ctypes.c_int
        fn.argtypes = [ctypes.c_int, ctypes.c_char_p,
                       ctypes.c_int, ctypes.c_char_p, ctypes.c_uint]
        rc = fn(olddirfd, oldname.encode(), newdirfd, newname.encode(), flags)
    else:
        arch = os.uname().machine
        nr = _RENAMEAT2_NR.get(arch)
        if nr is None:
            _die(f"renameat2 no disponible en esta arquitectura ({arch}); "
                 "las escrituras cerradas exigen renameat2, no hay fallback")
        _libc.syscall.restype = ctypes.c_long
        rc = _libc.syscall(nr, olddirfd, oldname.encode(),
                           newdirfd, newname.encode(), flags)
    if rc != 0:
        err = ctypes.get_errno()
        raise OSError(err, os.strerror(err),
                      f"renameat2({oldname!r}->{newname!r}, flags={flags})")


# --------------------------------------------------------------- confinamiento
def _open_root(root):
    if root != "/" and root.endswith("/"):
        root = root.rstrip("/")
    if not os.path.isabs(root):
        _die(f"root debe ser absoluto: {root!r}")
    if root == "/":
        _die("root no puede ser la raiz del sistema '/'")
    fd = os.open(root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC)
    st = os.fstat(fd)
    if st.st_uid != os.geteuid():
        os.close(fd)
        _die(f"root no es propiedad del usuario actual: {root!r}")
    return fd


def _split_rel(rel):
    if os.path.isabs(rel):
        _die(f"dst debe ser relativo al root: {rel!r}")
    parts = []
    for p in rel.split("/"):
        if p in ("", ".", ".."):
            _die(f"dst con segmento invalido ({p!r}): {rel!r}")
        parts.append(p)
    if not parts:
        _die(f"dst vacio: {rel!r}")
    return parts


def _walk_parent(root_fd, parts, create):
    """Recorre los directorios padre con openat(O_NOFOLLOW). Devuelve
    (parent_fd, leaf_name). Si create, crea los directorios que falten en 0700.
    Rechaza symlinks y componentes de otro usuario."""
    cur = os.dup(root_fd)
    try:
        for comp in parts[:-1]:
            try:
                nxt = os.open(comp, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                              dir_fd=cur)
            except FileNotFoundError:
                if not create:
                    _die(f"directorio padre inexistente: {comp!r}")
                os.mkdir(comp, 0o700, dir_fd=cur)
                os.fsync(cur)
                nxt = os.open(comp, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                              dir_fd=cur)
            except OSError as e:
                # ELOOP: era un symlink -> O_NOFOLLOW lo rechaza.
                _die(f"componente de ruta no navegable (¿symlink?): {comp!r}: {e}")
            st = os.fstat(nxt)
            if st.st_uid != os.geteuid():
                os.close(nxt)
                os.close(cur)
                _die(f"componente de ruta de otro usuario: {comp!r}")
            os.close(cur)
            cur = nxt
        return cur, parts[-1]
    except Exception:
        os.close(cur)
        raise


def _sha256_bytes(b):
    return hashlib.sha256(b).hexdigest()


def _read_target(parent_fd, name):
    """Lee (bytes, mode) del target si existe y es fichero regular no-symlink.
    Devuelve (None, None) si no existe."""
    try:
        fd = os.open(name, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=parent_fd)
    except FileNotFoundError:
        return None, None
    except OSError as e:
        _die(f"target no legible sin seguir symlink: {name!r}: {e}")
    try:
        st = os.fstat(fd)
        if not stat.S_ISREG(st.st_mode):
            _die(f"target no es fichero regular: {name!r}")
        data = os.read(fd, st.st_size + 1)
        return data, stat.S_IMODE(st.st_mode)
    finally:
        os.close(fd)


# ---------------------------------------------------------------------- WAL
def _wal_path(root_fd):
    return WAL_NAME


def _record_hash(rec_no_hash):
    canon = json.dumps(rec_no_hash, sort_keys=True, separators=(",", ":"))
    return _sha256_bytes(canon.encode())


def _read_wal(root_fd):
    """Devuelve la lista de records validando la cadena. Lanza si esta corrupto."""
    try:
        fd = os.open(WAL_NAME, os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC, dir_fd=root_fd)
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
        except (json.JSONDecodeError, UnicodeDecodeError) as e:
            _die(f"WAL corrupto (JSON invalido): {e}; ejecuta 'txnwrite fsck'")
        if not isinstance(rec, dict):
            _die("WAL corrupto (record no es objeto); ejecuta fsck")
        rh = rec.pop("record_hash", None)
        if rec.get("prev") != prev:
            _die("WAL corrupto (cadena prev rota); ejecuta fsck")
        if rh != _record_hash(rec):
            _die("WAL corrupto (record_hash no cuadra); ejecuta fsck")
        prev = rh
        recs.append(rec)
    return recs


def _append_wal(root_fd, recs, rec):
    prev = "0" * 64
    if recs:
        prev = _record_hash(recs[-1])
    rec = dict(rec)
    rec["prev"] = prev
    rec["record_hash"] = _record_hash(rec)
    line = (json.dumps(rec, sort_keys=True, separators=(",", ":")) + "\n").encode()
    fd = os.open(WAL_NAME, os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW | os.O_CLOEXEC,
                 0o600, dir_fd=root_fd)
    try:
        os.write(fd, line)
        os.fsync(fd)
    finally:
        os.close(fd)
    os.fsync(root_fd)
    recs.append(rec)


def _clear_wal(root_fd):
    try:
        os.unlink(WAL_NAME, dir_fd=root_fd)
        os.fsync(root_fd)
    except FileNotFoundError:
        pass


# ------------------------------------------------------------------ recovery
def _recover(root_fd):
    """Completa o bloquea una transaccion pendiente. Idempotente."""
    recs = _read_wal(root_fd)
    if not recs:
        return
    # La ultima transaccion es la que importa (una en vuelo a la vez).
    txid = recs[-1]["txid"]
    tx = [r for r in recs if r["txid"] == txid]
    states = [r["state"] for r in tx]
    if "committed" in states:
        _clear_wal(root_fd)
        return
    prepared = next((r for r in tx if r["state"] == "prepared"), None)
    if prepared is None:
        _die("WAL corrupto (sin 'prepared'); ejecuta fsck")
    parts = _split_rel(prepared["target"])
    try:
        parent_fd, leaf = _walk_parent(root_fd, parts, create=False)
    except TxnError:
        # El padre no existe: el target no llego a escribirse. Estado = pre
        # (ausente). Coincide con preimage ausente => seguro retirar el WAL.
        if prepared["pre"]["exists"] is False:
            _clear_wal(root_fd)
            return
        _die("recuperacion imposible: padre ausente pero preimage existia; fsck")
    try:
        data, _ = _read_target(parent_fd, leaf)
        cur = None if data is None else _sha256_bytes(data)
        pre = prepared["pre"]["sha256"] if prepared["pre"]["exists"] else None
        post = prepared["post"]["sha256"]
        if cur == post:
            # Ya publicado; solo faltaba cerrar el WAL.
            _clear_wal(root_fd)
            return
        if cur == pre:
            # No llego a publicar; volver al preimage es no hacer nada. Seguro.
            _clear_wal(root_fd)
            return
        # Tercer hash: ni pre ni post. No adivinar.
        _die("recuperacion bloqueada: el target tiene un tercer hash "
             "(ni preimage ni postimage); ejecuta fsck manual")
    finally:
        os.close(parent_fd)


# ------------------------------------------------------------- write engine
def _transactional_write(root, rel, content, mode):
    """Escribe content (bytes) en root/rel con el patron cerrado. Idempotente:
    si el target ya es igual, no toca nada."""
    root_fd = _open_root(root)
    try:
        _recover(root_fd)  # limpia/valida cualquier tx anterior antes de empezar
        parts = _split_rel(rel)
        parent_fd, leaf = _walk_parent(root_fd, parts, create=True)
        try:
            old, old_mode = _read_target(parent_fd, leaf)
            new_sha = _sha256_bytes(content)
            if old is not None and _sha256_bytes(old) == new_sha and old_mode == mode:
                return "="  # idempotente

            # Staging O_EXCL 0600.
            os.makedirs(os.path.join(root, STAGE_DIR), mode=0o700, exist_ok=True)
            txid = f"{_now()}-{os.getpid()}-{_sha256_bytes(os.urandom(8))[:8]}"
            stage_rel = STAGE_DIR + "/" + txid + ".stage"
            sfd = os.open(stage_rel, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                          0o600, dir_fd=root_fd)
            try:
                os.write(sfd, content)
                os.fsync(sfd)
                os.fchmod(sfd, mode)
                os.fsync(sfd)
            finally:
                os.close(sfd)

            recs = _read_wal(root_fd)
            rec = {
                "v": 1, "txid": txid, "state": "prepared", "op": "write",
                "target": rel,
                "pre": {"exists": old is not None,
                        "sha256": (None if old is None else _sha256_bytes(old))},
                "post": {"sha256": new_sha, "mode": format(mode, "04o")},
                "ts": _now(),
            }
            _append_wal(root_fd, recs, rec)

            # Publicar. El staging vive en STAGE_DIR (bajo root_fd); el target
            # cuelga de parent_fd. renameat2 con dirfds distintos.
            stage_parent_fd = os.open(STAGE_DIR, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW | os.O_CLOEXEC,
                                      dir_fd=root_fd)
            try:
                stage_name = txid + ".stage"
                if old is None:
                    _renameat2(stage_parent_fd, stage_name, parent_fd, leaf, RENAME_NOREPLACE)
                else:
                    # EXCHANGE: tras el swap, el inodo desplazado (el viejo) queda
                    # en la ruta de staging. Verificar que sigue siendo el preimage.
                    _renameat2(stage_parent_fd, stage_name, parent_fd, leaf, RENAME_EXCHANGE)
                    disp, _ = _read_target(stage_parent_fd, stage_name)
                    if disp is None or _sha256_bytes(disp) != _sha256_bytes(old):
                        # Algo cambio bajo nuestros pies: deshacer y bloquear.
                        _renameat2(stage_parent_fd, stage_name, parent_fd, leaf, RENAME_EXCHANGE)
                        _die("inodo desplazado no coincide con el preimage; "
                             "escritura abortada (posible carrera)")
                    # Limpiar el inodo viejo desplazado.
                    try:
                        os.unlink(stage_name, dir_fd=stage_parent_fd)
                    except FileNotFoundError:
                        pass
                os.fsync(parent_fd)
            finally:
                os.close(stage_parent_fd)

            recs = _read_wal(root_fd)
            _append_wal(root_fd, recs, {
                "v": 1, "txid": txid, "state": "committed", "op": "write",
                "target": rel, "post": {"sha256": new_sha}, "ts": _now(),
            })
            _clear_wal(root_fd)
            return "+" if old is None else "~"
        finally:
            os.close(parent_fd)
    finally:
        os.close(root_fd)


def _now():
    import time
    return time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())


# ------------------------------------------------------------- json merge
def _merge_claude_settings(kit, old):
    out = dict(kit)
    out.update(old)
    out["env"] = {**(kit.get("env") or {}), **(old.get("env") or {})}
    out["hooks"] = kit.get("hooks") if kit.get("hooks") is not None else old.get("hooks")
    kp = kit.get("permissions") or {}
    op = old.get("permissions") or {}
    perm = dict(kp)
    perm.update(op)
    for lista in ("allow", "deny"):
        del_kit = kp.get(lista) or []
        perm[lista] = del_kit + [x for x in (op.get(lista) or []) if x not in del_kit]
    out["permissions"] = perm
    return out


# ------------------------------------------------------------------ subcommands
def _mode_arg(m, src_path=None):
    if m == "source" and src_path is not None:
        return stat.S_IMODE(os.stat(src_path).st_mode)
    return int(m, 8)


def cmd_copy_owned(a):
    with open(a.src, "rb") as f:
        content = f.read()
    mode = _mode_arg(a.mode, a.src)
    _transactional_write(a.root, a.dst, content, mode)
    return 0


def cmd_managed_text_block(a):
    content = sys.stdin.buffer.read()
    if not a.whole_file:
        _die("managed-text-block requiere --whole-file en esta version")
    mode = _mode_arg(a.mode)
    _transactional_write(a.root, a.dst, content, mode)
    return 0


def cmd_json_merge(a):
    if a.policy != "claude-settings":
        _die(f"policy no soportada: {a.policy!r}")
    with open(a.kit_json, encoding="utf-8") as f:
        kit = json.load(f)
    root_fd = _open_root(a.root)
    try:
        parts = _split_rel(a.dst)
        parent_fd, leaf = _walk_parent(root_fd, parts, create=True)
        try:
            old_bytes, _ = _read_target(parent_fd, leaf)
        finally:
            os.close(parent_fd)
    finally:
        os.close(root_fd)
    if old_bytes is None:
        merged = kit
    else:
        old = json.loads(old_bytes.decode("utf-8"))
        merged = _merge_claude_settings(kit, old)
    for kv in (a.set_env or []):
        k, _, v = kv.partition("=")
        merged.setdefault("env", {})[k] = v
    content = (json.dumps(merged, ensure_ascii=False, indent=2) + "\n").encode()
    _transactional_write(a.root, a.dst, content, 0o644)
    return 0


def cmd_diff_only(a):
    # NUNCA escribe. Muestra el diff propuesto (o "fichero nuevo").
    import difflib
    root_fd = _open_root(a.root)
    try:
        parts = _split_rel(a.dst)
        try:
            parent_fd, leaf = _walk_parent(root_fd, parts, create=False)
            old_bytes, _ = _read_target(parent_fd, leaf)
            os.close(parent_fd)
        except TxnError:
            old_bytes = None
    finally:
        os.close(root_fd)
    if a.src:
        with open(a.src, "rb") as f:
            new_bytes = f.read()
    else:
        new_bytes = sys.stdin.buffer.read()
    old_txt = "" if old_bytes is None else old_bytes.decode("utf-8", "replace")
    new_txt = new_bytes.decode("utf-8", "replace")
    label = a.label or a.dst
    if old_bytes is None:
        sys.stdout.write(f"--- (nuevo) {label}\n")
        sys.stdout.write(new_txt)
    else:
        for line in difflib.unified_diff(old_txt.splitlines(True), new_txt.splitlines(True),
                                         fromfile=f"a/{label}", tofile=f"b/{label}"):
            sys.stdout.write(line)
    return 0


def cmd_recover(a):
    root_fd = _open_root(a.root)
    try:
        _recover(root_fd)
    finally:
        os.close(root_fd)
    return 0


def cmd_emit_test_prepared_wal(a):
    """SOLO para tests: fabrica un WAL con un unico record 'prepared' cuyos
    pre/post no coinciden con el target, para probar el bloqueo por tercer hash."""
    root_fd = _open_root(a.root)
    try:
        rec = {
            "v": 1, "txid": "test-" + _now(), "state": "prepared", "op": "write",
            "target": a.dst,
            "pre": {"exists": True, "sha256": a.pre_sha},
            "post": {"sha256": a.post_sha, "mode": "0644"},
            "ts": _now(),
        }
        _append_wal(root_fd, [], rec)
    finally:
        os.close(root_fd)
    return 0


PRIMITIVES = ["copy-owned", "diff-only", "json-merge-owned-keys", "managed-text-block"]


def main(argv):
    p = argparse.ArgumentParser(prog="txnwrite", add_help=True)
    p.add_argument("--list-primitives", action="store_true")
    p.add_argument("--emit-test-prepared-wal", action="store_true")
    p.add_argument("--root")
    p.add_argument("--dst")
    p.add_argument("--pre-sha")
    p.add_argument("--post-sha")
    sub = p.add_subparsers(dest="cmd")

    sp = sub.add_parser("copy-owned")
    sp.add_argument("--root", required=True)
    sp.add_argument("--src", required=True)
    sp.add_argument("--dst", required=True)
    sp.add_argument("--mode", default="source")
    sp.set_defaults(fn=cmd_copy_owned)

    sp = sub.add_parser("managed-text-block")
    sp.add_argument("--root", required=True)
    sp.add_argument("--dst", required=True)
    sp.add_argument("--mode", default="0644")
    sp.add_argument("--marker", default="")
    sp.add_argument("--whole-file", action="store_true")
    sp.set_defaults(fn=cmd_managed_text_block)

    sp = sub.add_parser("json-merge-owned-keys")
    sp.add_argument("--root", required=True)
    sp.add_argument("--dst", required=True)
    sp.add_argument("--kit-json", required=True)
    sp.add_argument("--policy", default="claude-settings")
    sp.add_argument("--set-env", action="append")
    sp.set_defaults(fn=cmd_json_merge)

    sp = sub.add_parser("diff-only")
    sp.add_argument("--root", required=True)
    sp.add_argument("--dst", required=True)
    sp.add_argument("--src")
    sp.add_argument("--label", default="")
    sp.set_defaults(fn=cmd_diff_only)

    sp = sub.add_parser("recover")
    sp.add_argument("--root", required=True)
    sp.set_defaults(fn=cmd_recover)

    a = p.parse_args(argv)

    if a.list_primitives:
        sys.stdout.write("\n".join(PRIMITIVES) + "\n")
        return 0
    if a.emit_test_prepared_wal:
        return cmd_emit_test_prepared_wal(a)
    if not getattr(a, "cmd", None):
        p.error("falta subcomando")
    try:
        return a.fn(a)
    except TxnError as e:
        sys.stderr.write("txnwrite: " + str(e) + "\n")
        return 1
    except OSError as e:
        sys.stderr.write("txnwrite: " + str(e) + "\n")
        return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
