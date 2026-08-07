#!/usr/bin/env python3
"""coin-kat.py - known-answer vectors for the CoinXT native shim.

CoinXT wraps trezor-crypto behind the cnx_ ABI. Unlike a pure-script library, the
native shim IS testable headless: this harness builds the shared library from the
vendored source, drives it through ctypes, and checks every deterministic output
against a PUBLIC known-answer vector, cross-checked against an independent
implementation (Python's hashlib) before pinning. It is the CoinXT analogue of
OnionXT's onion-kat.py.

Phase 1 covers the whole hash surface: Keccak-256, SHA3-256, SHA-256, SHA-512,
RIPEMD-160, HMAC-SHA256/512, and PBKDF2-HMAC-SHA512 (the BIP-39 mnemonic-to-seed
KDF), plus the shim's fail-closed guards. Later phases extend this file with
secp256k1 (RFC 6979 signatures, ecrecover), BIP-32 / BIP-39 wallet vectors, and
the script-side encoders (once those exist).

Every digest is pinned to a PUBLIC vector AND, where Python ships an independent
implementation of the same primitive, cross-checked against it live. RIPEMD-160
is the exception: OpenSSL 3 moved it to the legacy provider, so hashlib often
cannot supply it. There the published vectors stand alone and the harness says
so rather than silently skipping the check.

Usage:
  python3 coin-kat.py            # build + run the vectors, print each result
  python3 coin-kat.py --check    # same, but terse: one OK line or a non-zero exit

If no C compiler is available, the harness prints a clear skip line and exits 0
(so a docs-only environment does not fail); where cc exists, it runs for real.
"""

import ctypes
import hashlib
import hmac as pyhmac
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

# Published SHA-2 vectors (FIPS 180-4 examples). Also cross-checked against
# hashlib below, which is the independent implementation.
SHA256 = {
    b"": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    b"abc": "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
}
SHA512 = {
    b"": ("cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce"
          "47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e"),
    b"abc": ("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
             "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"),
}

# The published RIPEMD-160 vectors from the algorithm's own specification. These
# stand alone: hashlib usually cannot provide ripemd160 on OpenSSL 3, so there is
# no second opinion available for this one primitive (reported, never skipped).
RIPEMD160 = {
    b"": "9c1185a5c5e9fc54612808977ee8f548b2258d31",
    b"a": "0bdc9d2d256b3ee9daae347be6f4dc835a467ffe",
    b"abc": "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc",
    b"message digest": "5d0689ef49d2fae572b881b123a85ffa21595f36",
}

# RFC 4231 HMAC test cases 1 and 2 (key, message) -> (sha256 mac, sha512 mac).
HMAC_CASES = [
    (b"\x0b" * 20, b"Hi There",
     "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7",
     "87aa7cdea5ef619d4ff0b4241a1d6cb02379f4e2ce4ec2787ad0b30545e17cde"
     "daa833b7d6b8a702038b274eaea3f4e4be9d914eeb61f1702e696c203a126854"),
    (b"Jefe", b"what do ya want for nothing?",
     "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
     "164b7a7bfcf819e2e395fbe73b56e0a387bd64222e831fd610270cd7ea250554"
     "9758bf75c05a994a6d034f65f8f0e6fdcaeab1a34d4a6b4b636e070a38bce737"),
]

# The BIP-39 mnemonic-to-seed vector everyone knows: the all-"abandon" sentence
# with the passphrase "TREZOR". This is the exact shape CoinXT will use the KDF
# for (salt = "mnemonic" + passphrase, 2048 iterations, a 64-byte seed), so it
# pins the real call, not just the primitive.
BIP39_MNEMONIC = (b"abandon abandon abandon abandon abandon abandon "
                  b"abandon abandon abandon abandon abandon about")
BIP39_SALT = b"mnemonicTREZOR"
BIP39_ITERS = 2048
BIP39_SEED = ("c55257c360c07c72029aebc1b53c05ed0362ada38ead3e3e9efa3708e5349553"
              "1f09a6987599d18264c1e1c92f2cf141630c7a3c4ab7c81b2f001698e7463b04")


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
           os.path.join(VENDOR, "sha2.c"),
           os.path.join(VENDOR, "ripemd160.c"),
           os.path.join(VENDOR, "hmac.c"),
           os.path.join(VENDOR, "pbkdf2.c"),
           os.path.join(VENDOR, "memzero.c")]
    cmd = [cc, "-O2", "-Wall", "-Wextra", "-isystem", VENDOR,
           "-fPIC", "-shared", *src, "-o", out_path]
    subprocess.run(cmd, check=True)


def load(out_path):
    lib = ctypes.CDLL(out_path)
    lib.cnx_abi_version.restype = ctypes.c_int
    # in-buffer + length -> out-buffer, the shape of every one-shot digest.
    for fn in ("cnx_keccak256", "cnx_sha3_256", "cnx_sha256", "cnx_sha512",
               "cnx_ripemd160"):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    # key + msg -> mac.
    for fn in ("cnx_hmac_sha256", "cnx_hmac_sha512"):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                      ctypes.c_char_p, ctypes.c_size_t, ctypes.c_char_p]
    lib.cnx_pbkdf2_hmac_sha512.restype = ctypes.c_int
    lib.cnx_pbkdf2_hmac_sha512.argtypes = [
        ctypes.c_char_p, ctypes.c_size_t,   # password
        ctypes.c_char_p, ctypes.c_size_t,   # salt
        ctypes.c_uint32,                    # iterations
        ctypes.c_char_p, ctypes.c_size_t,   # out, outlen
    ]
    for fn in ("cnx_sha256_len", "cnx_sha512_len", "cnx_ripemd160_len",
               "cnx_hmac_sha256_len", "cnx_hmac_sha512_len",
               "cnx_keccak256_len", "cnx_sha3_256_len"):
        getattr(lib, fn).restype = ctypes.c_size_t
    return lib


def digest(lib, fn, data, outlen=32):
    """Drive a one-shot digest. `data` may be None to exercise the NULL path."""
    out = ctypes.create_string_buffer(outlen)
    rc = getattr(lib, fn)(data, 0 if data is None else len(data), out)
    if rc != 0:
        raise RuntimeError(f"{fn} returned {rc}")
    return out.raw.hex()


def mac(lib, fn, key, msg, outlen):
    out = ctypes.create_string_buffer(outlen)
    rc = getattr(lib, fn)(key, len(key), msg, len(msg), out)
    if rc != 0:
        raise RuntimeError(f"{fn} returned {rc}")
    return out.raw.hex()


def pbkdf2(lib, pw, salt, iters, outlen):
    out = ctypes.create_string_buffer(outlen)
    rc = lib.cnx_pbkdf2_hmac_sha512(pw, len(pw), salt, len(salt), iters, out, outlen)
    if rc != 0:
        raise RuntimeError(f"cnx_pbkdf2_hmac_sha512 returned {rc}")
    return out.raw.hex()


def main(argv):
    check = "--check" in argv[1:]

    # --lib <path>: drive an ALREADY-BUILT library instead of compiling a fresh
    # one. The default (build from source in a temp dir) is what the gates want:
    # it tests the SOURCE and cannot be fooled by a stale artifact. But a release
    # artifact needs the opposite question answered - "does THIS FILE, the one we
    # are about to ship, produce the right answers?" - and for a cross-compiled
    # Windows DLL that question can only be asked on Windows, against the exact
    # binary. Same vectors either way; only the subject changes.
    given = None
    if "--lib" in argv[1:]:
        i = argv.index("--lib")
        if i + 1 >= len(argv):
            print("coin-kat: --lib needs a path")
            return 2
        given = argv[i + 1]
        if not os.path.exists(given):
            print(f"coin-kat: --lib {given} does not exist")
            return 1

    cc = None
    if given is None:
        cc = find_cc()
        if cc is None:
            print("coin-kat: skipped (no C compiler found)")
            return 0

    problems = []
    with tempfile.TemporaryDirectory() as tmp:
        if given is not None:
            out_path = given
            print(f"coin-kat: driving the given library {given}")
        else:
            out_path = os.path.join(tmp, "libcoinxt_kat.so")
            try:
                build_lib(cc, out_path)
            except subprocess.CalledProcessError as exc:
                print(f"coin-kat: BUILD FAILED ({exc})")
                return 1
        lib = load(out_path)

        abi = lib.cnx_abi_version()
        if abi != 2:
            problems.append(f"abi_version = {abi}, expected 2")
        elif not check:
            print(f"abi_version: {abi}")

        # Every length the LCB layer will ask the shim for, so a future edit that
        # changes one is caught here rather than by a truncated digest.
        for fn, want in (("cnx_keccak256_len", 32), ("cnx_sha3_256_len", 32),
                         ("cnx_sha256_len", 32), ("cnx_sha512_len", 64),
                         ("cnx_ripemd160_len", 20), ("cnx_hmac_sha256_len", 32),
                         ("cnx_hmac_sha512_len", 64)):
            got = getattr(lib, fn)()
            if got != want:
                problems.append(f"{fn}() = {got}, expected {want}")

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

        # ---- SHA-2: published vector AND hashlib, which must agree with each other
        for data, exp in SHA256.items():
            got = digest(lib, "cnx_sha256", data)
            if got != exp:
                problems.append(f"sha256({data!r}) = {got}, expected {exp}")
            if got != hashlib.sha256(data).hexdigest():
                problems.append(f"sha256({data!r}) disagrees with hashlib")
            if not check:
                print(f"  sha256({data!r:8}) {'OK' if got == exp else 'FAIL'} vs vector + hashlib")
        for data, exp in SHA512.items():
            got = digest(lib, "cnx_sha512", data, 64)
            if got != exp:
                problems.append(f"sha512({data!r}) = {got}, expected {exp}")
            if got != hashlib.sha512(data).hexdigest():
                problems.append(f"sha512({data!r}) disagrees with hashlib")
            if not check:
                print(f"  sha512({data!r:8}) {'OK' if got == exp else 'FAIL'} vs vector + hashlib")

        # ---- RIPEMD-160: published vectors; hashlib only if this build has it
        try:
            hashlib.new("ripemd160")
            have_rmd = True
        except (ValueError, TypeError):
            have_rmd = False
        for data, exp in RIPEMD160.items():
            got = digest(lib, "cnx_ripemd160", data, 20)
            if got != exp:
                problems.append(f"ripemd160({data!r}) = {got}, expected {exp}")
            if have_rmd:
                h = hashlib.new("ripemd160", data).hexdigest()
                if got != h:
                    problems.append(f"ripemd160({data!r}) disagrees with hashlib")
        if not check:
            second = "vector + hashlib" if have_rmd else "vector only (hashlib has no ripemd160 here)"
            print(f"  ripemd160 x{len(RIPEMD160)} OK vs {second}")

        # ---- HMAC: RFC 4231 vectors AND Python's hmac module
        for key, msg, exp256, exp512 in HMAC_CASES:
            got = mac(lib, "cnx_hmac_sha256", key, msg, 32)
            if got != exp256:
                problems.append(f"hmac_sha256({msg!r}) = {got}, expected {exp256}")
            if got != pyhmac.new(key, msg, hashlib.sha256).hexdigest():
                problems.append(f"hmac_sha256({msg!r}) disagrees with python hmac")
            got = mac(lib, "cnx_hmac_sha512", key, msg, 64)
            if got != exp512:
                problems.append(f"hmac_sha512({msg!r}) = {got}, expected {exp512}")
            if got != pyhmac.new(key, msg, hashlib.sha512).hexdigest():
                problems.append(f"hmac_sha512({msg!r}) disagrees with python hmac")
        if not check:
            print(f"  hmac-sha256/512 x{len(HMAC_CASES)} OK vs RFC 4231 + python hmac")

        # ---- PBKDF2-HMAC-SHA512: the BIP-39 seed vector, plus hashlib
        got = pbkdf2(lib, BIP39_MNEMONIC, BIP39_SALT, BIP39_ITERS, 64)
        if got != BIP39_SEED:
            problems.append(f"bip39 seed = {got}, expected {BIP39_SEED}")
        ref = hashlib.pbkdf2_hmac("sha512", BIP39_MNEMONIC, BIP39_SALT,
                                  BIP39_ITERS, 64).hex()
        if got != ref:
            problems.append("pbkdf2_hmac_sha512 disagrees with hashlib")
        if not check:
            print(f"  pbkdf2-hmac-sha512 (BIP-39 seed) {'OK' if got == BIP39_SEED else 'FAIL'} vs vector + hashlib")

        # A derived length that is NOT a whole number of SHA-512 blocks exercises
        # the partial-final-block path, which a 64-byte-only test never touches.
        got = pbkdf2(lib, b"password", b"salt", 100, 100)
        ref = hashlib.pbkdf2_hmac("sha512", b"password", b"salt", 100, 100).hex()
        if got != ref:
            problems.append("pbkdf2_hmac_sha512 partial-block output disagrees with hashlib")

        # ---- the shim's own guards must FAIL CLOSED, not quietly do something else
        out = ctypes.create_string_buffer(32)
        guards = [
            ("zero iterations", lib.cnx_pbkdf2_hmac_sha512(b"pw", 2, b"salt", 4, 0, out, 32), -3),
            ("zero outlen", lib.cnx_pbkdf2_hmac_sha512(b"pw", 2, b"salt", 4, 1, out, 0), -2),
            ("NULL out", lib.cnx_sha256(b"x", 1, None), -1),
            ("NULL in with length", lib.cnx_sha256(None, 1, out), -1),
            ("NULL hmac key with length", lib.cnx_hmac_sha256(None, 1, b"m", 1, out), -1),
        ]
        for name, rc, want in guards:
            if rc != want:
                problems.append(f"guard '{name}' returned {rc}, expected {want}")
        if not check:
            print(f"  fail-closed guards x{len(guards)} OK")

        # An empty input is legal and must still produce the right digest through
        # the NULL-with-zero-length path the LCB layer can hand us.
        if digest(lib, "cnx_sha256", None) != SHA256[b""]:
            problems.append("sha256(NULL, 0) did not equal sha256 of the empty string")

    if problems:
        for p in problems:
            print("coin-kat: FAIL:", p)
        return 1
    print("coin-kat: self-check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
