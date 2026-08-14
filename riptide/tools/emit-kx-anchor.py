#!/usr/bin/env python3
# emit-kx-anchor.py - print crypto_kx / X25519 anchor vectors from a REAL
# libsodium, for riptide_reference.py's phase-4 self-checks.
#
# WHY THIS EXISTS: the oracle rule is that every primitive is validated
# against a vector from OUTSIDE this repository before the script layer is
# written, and a vector typed from a model's memory is exactly the
# fabrication that rule exists to refuse. The KDF anchor came from the
# sodiumxt C KAT; the kx anchor comes from here: this script loads the
# actual libsodium shared library through ctypes (stdlib; no header, no
# pip) and prints what crypto_scalarmult_base / crypto_kx_seed_keypair /
# crypto_kx_{client,server}_session_keys return for the oracle's fixed
# inputs. Those outputs are then HARDCODED into riptide_reference.py's
# _self_check with a comment recording this provenance, so the oracle
# still runs stdlib-only anywhere - this emitter is only re-run when a
# maintainer wants to re-verify the anchor against a fresh libsodium.
#
# Provenance of the committed vectors: libsodium.so.23.3.0 (libsodium
# 1.0.18), Linux x86_64, 2026-08-14.

import ctypes
import ctypes.util
import sys

# The oracle supplies the fixed inputs so the two files cannot drift.
sys.path.insert(0, __file__.rsplit("/", 1)[0])
import riptide_reference as rr  # noqa: E402


def load_sodium():
    name = ctypes.util.find_library("sodium")
    candidates = [name] if name else []
    candidates += ["libsodium.so.23", "libsodium.so", "libsodium.dylib",
                   "libsodium-23.dll", "libsodium.dll"]
    for c in candidates:
        if not c:
            continue
        try:
            return ctypes.CDLL(c)
        except OSError:
            continue
    raise SystemExit("emit-kx-anchor: no libsodium shared library found - "
                     "install libsodium (runtime package is enough) and rerun")


def main():
    lib = load_sodium()
    if lib.sodium_init() < 0:
        raise SystemExit("sodium_init failed")

    def buf(n):
        return ctypes.create_string_buffer(n)

    master = b"\x42" * 32
    dm = rr.dm_seed(master)
    conf = bytes.fromhex(
        "cac73f09a0478224974a525036ebd73f9727ac8932162eb7fcfb2821ad7eecc7")

    # X25519 base-point mult of a fixed scalar (anchors the ladder itself)
    out = buf(32)
    rc = lib.crypto_scalarmult_base(out, b"\x42" * 32)
    assert rc == 0
    print("scalarmult_base(0x42*32) = %s" % out.raw.hex())

    # crypto_kx_seed_keypair for the golden DM seed and the conformance seed
    for label, seed in (("dm", dm), ("conf", conf)):
        pk = buf(32)
        sk = buf(32)
        rc = lib.crypto_kx_seed_keypair(pk, sk, seed)
        assert rc == 0
        print("kx_seed_keypair(%s).pk = %s" % (label, pk.raw.hex()))
        print("kx_seed_keypair(%s).sk = %s" % (label, sk.raw.hex()))

    # Session keys, both roles. The golden identity's handle sorts below the
    # conformance pubkey, so per riptide's role rule the golden side is the
    # CLIENT. rx/tx must cross-match.
    gpk, gsk = buf(32), buf(32)
    cpk, csk = buf(32), buf(32)
    lib.crypto_kx_seed_keypair(gpk, gsk, dm)
    lib.crypto_kx_seed_keypair(cpk, csk, conf)
    rx, tx = buf(32), buf(32)
    rc = lib.crypto_kx_client_session_keys(rx, tx, gpk, gsk, cpk)
    assert rc == 0
    print("client(golden).rx = %s" % rx.raw.hex())
    print("client(golden).tx = %s" % tx.raw.hex())
    srx, stx = buf(32), buf(32)
    rc = lib.crypto_kx_server_session_keys(srx, stx, cpk, csk, gpk)
    assert rc == 0
    print("server(conf).rx = %s" % srx.raw.hex())
    print("server(conf).tx = %s" % stx.raw.hex())
    assert rx.raw == stx.raw and tx.raw == srx.raw, "rx/tx do not cross-match"
    print("cross-match: client.rx == server.tx and client.tx == server.rx OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
