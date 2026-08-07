#!/usr/bin/env python3
"""coin-kat.py - known-answer vectors for the CoinXT native shim.

CoinXT wraps trezor-crypto behind the cnx_ ABI. Unlike a pure-script library, the
native shim IS testable headless: this harness builds the shared library from the
vendored source, drives it through ctypes, and checks every deterministic output
against a PUBLIC known-answer vector, cross-checked against an independent
implementation (Python's hashlib) before pinning. It is the CoinXT analogue of
OnionXT's onion-kat.py.

Phase 1 covers the hash surface (Keccak-256 and SHA3-256). Later phases extend
this file with secp256k1 (RFC 6979 signatures, ecrecover), BIP-32 / BIP-39
vectors, and the script-side encoders (once those exist).

Usage:
  python3 coin-kat.py            # build + run the vectors, print each result
  python3 coin-kat.py --check    # same, but terse: one OK line or a non-zero exit

If no C compiler is available, the harness prints a clear skip line and exits 0
(so a docs-only environment does not fail); where cc exists, it runs for real.
"""

import ctypes
import hashlib
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
NATIVE = os.path.normpath(os.path.join(HERE, "..", "native"))
VENDOR = os.path.join(NATIVE, "vendor")

# Published Keccak-256 (Ethereum, 0x01 padding) vectors. These are burned-in,
# widely-cited answers; SHA3-256 is cross-checked live against hashlib instead.
KECCAK256 = {
    b"": "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470",
    b"abc": "4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
}
SHA3_INPUTS = [b"", b"abc", b"The quick brown fox jumps over the lazy dog"]


def find_cc():
    for cc in (os.environ.get("CC"), "cc", "gcc", "clang"):
        if not cc:
            continue
        try:
            subprocess.run([cc, "--version"], stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, check=True)
            return cc
        except (OSError, subprocess.CalledProcessError):
            continue
    return None


def build_lib(cc, out_path):
    src = [os.path.join(NATIVE, "coinxt.c"),
           os.path.join(VENDOR, "sha3.c"),
           os.path.join(VENDOR, "memzero.c")]
    cmd = [cc, "-O2", "-Wall", "-Wextra", "-isystem", VENDOR,
           "-fPIC", "-shared", *src, "-o", out_path]
    subprocess.run(cmd, check=True)


def load(out_path):
    lib = ctypes.CDLL(out_path)
    lib.cnx_abi_version.restype = ctypes.c_int
    for fn in ("cnx_keccak256", "cnx_sha3_256"):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    return lib


def digest(lib, fn, data):
    out = ctypes.create_string_buffer(32)
    rc = getattr(lib, fn)(data, len(data), out)
    if rc != 0:
        raise RuntimeError(f"{fn} returned {rc}")
    return out.raw.hex()


def main(argv):
    check = "--check" in argv[1:]
    cc = find_cc()
    if cc is None:
        print("coin-kat: skipped (no C compiler found)")
        return 0

    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        out_path = os.path.join(tmp, "libcoinxt_kat.so")
        try:
            build_lib(cc, out_path)
        except subprocess.CalledProcessError as exc:
            print(f"coin-kat: BUILD FAILED ({exc})")
            return 1
        lib = load(out_path)

        abi = lib.cnx_abi_version()
        if abi != 1:
            problems.append(f"abi_version = {abi}, expected 1")
        elif not check:
            print(f"abi_version: {abi}")

        for data, exp in KECCAK256.items():
            got = digest(lib, "cnx_keccak256", data)
            ok = got == exp
            if not ok:
                problems.append(f"keccak256({data!r}) = {got}, expected {exp}")
            if not check:
                print(f"  keccak256({data!r:8}) {'OK' if ok else 'FAIL'}")

        for data in SHA3_INPUTS:
            got = digest(lib, "cnx_sha3_256", data)
            exp = hashlib.sha3_256(data).hexdigest()
            ok = got == exp
            if not ok:
                problems.append(f"sha3_256({data!r}) = {got}, expected {exp} (hashlib)")
            if not check:
                print(f"  sha3_256({data!r:12}...) {'OK' if ok else 'FAIL'} vs hashlib")

        # The footgun guard: Keccak-256 and SHA3-256 of the same input MUST differ.
        if digest(lib, "cnx_keccak256", b"") == digest(lib, "cnx_sha3_256", b""):
            problems.append("keccak256 and sha3_256 produced the same digest (aliased!)")

    if problems:
        for p in problems:
            print("coin-kat: FAIL:", p)
        return 1
    print("coin-kat: self-check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
