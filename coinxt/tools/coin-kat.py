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
KDF), plus the shim's fail-closed guards. Phase 2 adds secp256k1: public keys,
RFC 6979 deterministic ECDSA, verification (including what it must REJECT),
recoverable signing, ecrecover, and ECDH. Later phases extend this file with
BIP-32 / BIP-39 wallet vectors and the script-side encoders (once those exist).

Every digest is pinned to a PUBLIC vector AND, where Python ships an independent
implementation of the same primitive, cross-checked against it live. RIPEMD-160
is the exception: OpenSSL 3 moved it to the legacy provider, so hashlib often
cannot supply it. There the published vectors stand alone and the harness says
so rather than silently skipping the check.

For the curve the independent implementation is the `ecdsa` package, which is
optional: without it the published RFC 6979 vectors still run and the harness
says the cross-library leg was skipped. With it, the harness proves the claim
the implementation plan actually asks for - that a signature CoinXT produced
verifies in a mainstream library, and that a signature that library produced
verifies in CoinXT.

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
import re
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

# ---------------------------------------------------------------------------
# Phase 2: secp256k1.
# ---------------------------------------------------------------------------
SECP256K1_ORDER = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141

# Private key 1 is the generator G and private key 2 is 2G, so these two are the
# most-published public keys on the curve and need no second opinion to trust.
PUBKEYS = [
    (1,
     "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798",
     "0479be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798"
     "483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8"),
    (2,
     "02c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
     "04c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5"
     "1ae168fea63dc339a3c58419466ceaeef7f632653266d0e1236431a950cfe52a"),
]

# RFC 6979 deterministic ECDSA over secp256k1 with SHA-256, as (private key,
# message, r||s). These are the widely republished vectors for this exact curve
# and hash; the signature is low-s, which is what both Bitcoin relay policy
# (BIP-62) and Ethereum consensus require and what upstream always emits.
#
# They are the whole point of the phase: because RFC 6979 makes the nonce a pure
# function of (key, digest), a signature is reproducible, so it can be PINNED.
# The native code still draws OS entropy for side-channel blinding on every
# call - that blinding cancels out of the result algebraically, and the
# determinism check at the end of this section is what proves it empirically
# rather than by reading the arithmetic.
RFC6979 = [
    (1, b"Satoshi Nakamoto",
     "934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8"
     "2442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5"),
    (1, b"All those moments will be lost in time, like tears in rain. Time to die...",
     "8600dbd41e348fe5c9465ab92d23e3db8b98b873beecd930736488696438cb6b"
     "547fe64427496db33bf66019dacbf0039c04199abb0122918601db38a72cfc21"),
    (0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364140,
     b"Satoshi Nakamoto",
     "fd567d121db66e382991534ada77a6bd3106f0a1098c231e47993447cd6af2d0"
     "6b39cd0eb1bc8603e159ef5c20a5c8ad685a45b06ce9bebed3f153d10d93bed5"),
    (1, b"Everything should be made as simple as possible, but not simpler.",
     "33a69cd2065432a30f3d1ce4eb0d59b8ab58c74f27c41a7fdb5696ad4e6108c9"
     "6f807982866f785d3f6418d24163ddae117b7db4d5fdf0071de069fa54342262"),
]

# A recoverable signature and the key it recovers to. Unlike the four above this
# is not a published vector (recoverable ECDSA has no canonical vector set), so
# it was PINNED ONLY AFTER the 64-byte half was verified in the independent
# Python `ecdsa` library and the recovered key was checked to equal the signer.
# It guards the one byte those published vectors cannot: the recovery id.
RECOVERABLE_SK = "18e14a7b6a307f426a94f8114701e7c8e774e7f9a47e2c2035db29a206321725"
RECOVERABLE_MSG = b"CoinXT recoverable vector"
RECOVERABLE_SIG = ("7c2ace7a3b9079e5d2cf1ba5b01ae4942f9a9ed9b1a7b89b256f9754113187f2"
                   "2299d0cecba3ac960a8dc89b69d1859e20512c992db7ce8bd99649efbabae789"
                   "01")
RECOVERABLE_PUB = ("0450863ad64a87ae8a2fe83c1af1a8403cb53f53e486d8511dad8a04887e5b235"
                   "22cd470243453a299fa9e77237716103abc11a1df38855ed6f2ee187e9c582ba6")

# ECDH. Also pinned only after being reproduced independently (a * B computed
# with `ecdsa`'s point arithmetic). The value is the RAW shared point, 0x04 ||
# X || Y, not a key: see cnx_ecdh on why nothing is hashed here.
ECDH_A = "11223344556677889900aabbccddeeff00112233445566778899aabbccddeeff"
ECDH_B = "0fedcba987654321fedcba987654321fedcba987654321fedcba9876543210fe"
ECDH_POINT = ("04283ac952766cd1d14796687a482fad6f1799c736b2a096ef860c8c4bc2f234b2"
              "e9b6dab6c944216415d2df49de199ef71e3bad81ac3d72553fd0ce73a1760610")


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


def vendor_sources():
    """The vendored translation units, READ FROM native/build.sh rather than
    listed again here.

    This used to be a second hand-maintained copy of the same list, which is a
    quiet way to lie: the harness would happily build and bless a set of sources
    that is not the set the shipped library is compiled from, and the two only
    have to diverge by one file for the KATs to be testing something nobody
    installs. build.sh is the single source of truth; a parse failure is fatal
    rather than a fallback, because a fallback would restore the same lie.
    """
    path = os.path.join(NATIVE, "build.sh")
    with open(path, encoding="utf-8") as fh:
        m = re.search(r'vendor_src="([^"]*)"', fh.read(), re.S)
    if m is None:
        raise SystemExit("coin-kat: could not read vendor_src from native/build.sh; "
                         "the harness refuses to guess which sources ship")
    files = [p.strip() for p in m.group(1).replace("\\\n", " ").split()]
    out = []
    for f in files:
        if not f.startswith("$ven/"):
            raise SystemExit(f"coin-kat: unexpected entry {f!r} in build.sh vendor_src")
        p = os.path.join(VENDOR, f[len("$ven/"):])
        if not os.path.exists(p):
            raise SystemExit(f"coin-kat: build.sh names {f} but it is not vendored")
        out.append(p)
    return out


def build_lib(cc, out_path):
    src = [os.path.join(NATIVE, "coinxt.c"), *vendor_sources()]
    cmd = [cc, "-O2", "-Wall", "-Wextra", "-isystem", VENDOR,
           "-fPIC", "-shared", *src, "-o", out_path]
    # The shim draws blinding entropy from BCryptGenRandom on Windows; every
    # other platform gets it from libc (getrandom / arc4random_buf).
    if sys.platform.startswith("win") or out_path.endswith(".dll"):
        cmd.append("-lbcrypt")
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
    # ---- the phase-2 curve surface ------------------------------------------
    # Every buffer crosses as pointer + size_t length, so the pubkey argument
    # carries its own length and the shim can refuse a length that disagrees
    # with the prefix byte (the overread guard; see native/coinxt.c).
    lib.cnx_seckey_verify.restype = ctypes.c_int
    lib.cnx_seckey_verify.argtypes = [ctypes.c_char_p, ctypes.c_size_t]
    lib.cnx_pubkey_from_seckey.restype = ctypes.c_int
    lib.cnx_pubkey_from_seckey.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                           ctypes.c_int,
                                           ctypes.c_char_p, ctypes.c_size_t]
    lib.cnx_pubkey_decompress.restype = ctypes.c_int
    lib.cnx_pubkey_decompress.argtypes = [ctypes.c_char_p, ctypes.c_size_t,
                                          ctypes.c_char_p, ctypes.c_size_t]
    for fn in ("cnx_ecdsa_sign", "cnx_ecdsa_sign_recoverable"):
        f = getattr(lib, fn)
        f.restype = ctypes.c_int
        f.argtypes = [ctypes.c_char_p, ctypes.c_size_t,   # seckey
                      ctypes.c_char_p, ctypes.c_size_t,   # digest
                      ctypes.c_char_p, ctypes.c_size_t]   # out
    lib.cnx_ecdsa_verify.restype = ctypes.c_int
    lib.cnx_ecdsa_verify.argtypes = [ctypes.c_char_p, ctypes.c_size_t,  # pubkey
                                     ctypes.c_char_p, ctypes.c_size_t,  # digest
                                     ctypes.c_char_p, ctypes.c_size_t]  # sig
    lib.cnx_ecdsa_recover.restype = ctypes.c_int
    lib.cnx_ecdsa_recover.argtypes = [ctypes.c_char_p, ctypes.c_size_t,  # sig65
                                      ctypes.c_char_p, ctypes.c_size_t,  # digest
                                      ctypes.c_char_p, ctypes.c_size_t]  # out
    lib.cnx_ecdh.restype = ctypes.c_int
    lib.cnx_ecdh.argtypes = [ctypes.c_char_p, ctypes.c_size_t,   # seckey
                             ctypes.c_char_p, ctypes.c_size_t,   # pubkey
                             ctypes.c_char_p, ctypes.c_size_t]   # out
    for fn in ("cnx_sha256_len", "cnx_sha512_len", "cnx_ripemd160_len",
               "cnx_hmac_sha256_len", "cnx_hmac_sha512_len",
               "cnx_keccak256_len", "cnx_sha3_256_len",
               "cnx_seckey_len", "cnx_pubkey_len_compressed",
               "cnx_pubkey_len_uncompressed", "cnx_ecdsa_sig_len",
               "cnx_recoverable_sig_len", "cnx_ecdh_len"):
        getattr(lib, fn).restype = ctypes.c_size_t
    return lib


# ---------------------------------------------------------------------------
# Curve helpers. Each returns (status, bytes) so a KAT can assert on either.
# ---------------------------------------------------------------------------

def pubkey(lib, sk, compressed=True):
    n = 33 if compressed else 65
    out = ctypes.create_string_buffer(n)
    rc = lib.cnx_pubkey_from_seckey(sk, len(sk), 1 if compressed else 0, out, n)
    return rc, out.raw[:n]


def sign(lib, sk, dg, recoverable=False):
    n = 65 if recoverable else 64
    out = ctypes.create_string_buffer(n)
    fn = lib.cnx_ecdsa_sign_recoverable if recoverable else lib.cnx_ecdsa_sign
    rc = fn(sk, len(sk), dg, len(dg), out, n)
    return rc, out.raw[:n]


def recover(lib, sig65, dg):
    out = ctypes.create_string_buffer(65)
    rc = lib.cnx_ecdsa_recover(sig65, len(sig65), dg, len(dg), out, 65)
    return rc, out.raw[:65]


def ecdh(lib, sk, pub):
    out = ctypes.create_string_buffer(65)
    rc = lib.cnx_ecdh(sk, len(sk), pub, len(pub), out, 65)
    return rc, out.raw[:65]


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
        if abi != 3:
            problems.append(f"abi_version = {abi}, expected 3")
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

        # ==================================================================
        # Phase 2: secp256k1.
        # ==================================================================
        for fn, want in (("cnx_seckey_len", 32), ("cnx_pubkey_len_compressed", 33),
                         ("cnx_pubkey_len_uncompressed", 65),
                         ("cnx_ecdsa_sig_len", 64), ("cnx_recoverable_sig_len", 65),
                         ("cnx_ecdh_len", 65)):
            got = getattr(lib, fn)()
            if got != want:
                problems.append(f"{fn}() = {got}, expected {want}")

        # ---- public keys: G and 2G, the two most-published points on the curve
        for sk_int, want33, want65 in PUBKEYS:
            sk = sk_int.to_bytes(32, "big")
            rc, got33 = pubkey(lib, sk, True)
            if rc != 0 or got33.hex() != want33:
                problems.append(f"pubkey33({sk_int}) = {got33.hex()} rc={rc}, expected {want33}")
            rc, got65 = pubkey(lib, sk, False)
            if rc != 0 or got65.hex() != want65:
                problems.append(f"pubkey65({sk_int}) = {got65.hex()} rc={rc}, expected {want65}")
            # Decompressing the compressed form must rebuild the uncompressed one
            # exactly (it solves the curve equation for Y and picks by parity).
            out = ctypes.create_string_buffer(65)
            rc = lib.cnx_pubkey_decompress(got33, 33, out, 65)
            if rc != 0 or out.raw[:65] != got65:
                problems.append(f"pubkey_decompress({sk_int}) did not rebuild the uncompressed key")
        if not check:
            print(f"  secp256k1 pubkeys x{len(PUBKEYS)} OK (+ decompress round-trip)")

        # ---- RFC 6979: the published deterministic signatures
        for sk_int, msg, want in RFC6979:
            sk = sk_int.to_bytes(32, "big")
            dg = hashlib.sha256(msg).digest()
            rc, got = sign(lib, sk, dg)
            if rc != 0 or got.hex() != want:
                problems.append(f"rfc6979 sign({msg[:24]!r}) = {got.hex()} rc={rc}, expected {want}")
            # Every published vector is low-s; assert it rather than assume it,
            # because a high-s signature is non-standard and would be rejected
            # by Bitcoin relay and Ethereum consensus alike.
            if int.from_bytes(got[32:], "big") > SECP256K1_ORDER // 2:
                problems.append(f"rfc6979 sign({msg[:24]!r}) produced a high-s signature")
            _, pub = pubkey(lib, sk, True)
            if lib.cnx_ecdsa_verify(pub, 33, dg, 32, got, 64) != 0:
                problems.append(f"rfc6979 sign({msg[:24]!r}) did not verify under its own key")
        if not check:
            print(f"  RFC 6979 signatures x{len(RFC6979)} OK vs published vectors (low-s, self-verifying)")

        # ---- verification must REJECT, which is the half a signing test cannot show
        sk = bytes.fromhex(RECOVERABLE_SK)
        dg = hashlib.sha256(RECOVERABLE_MSG).digest()
        rc, sig64 = sign(lib, sk, dg)
        _, pub33 = pubkey(lib, sk, True)
        _, pub65 = pubkey(lib, sk, False)
        tampered = bytearray(sig64)
        tampered[10] ^= 0x01
        _, otherpub = pubkey(lib, (int.from_bytes(sk, "big") + 1).to_bytes(32, "big"), True)
        rejects = [
            ("tampered signature", lib.cnx_ecdsa_verify(pub33, 33, dg, 32, bytes(tampered), 64), -5),
            ("wrong public key", lib.cnx_ecdsa_verify(otherpub, 33, dg, 32, sig64, 64), -5),
            ("wrong digest", lib.cnx_ecdsa_verify(pub33, 33, hashlib.sha256(b"other").digest(), 32, sig64, 64), -5),
            # THE OVERREAD GUARD. Upstream's parser reads 65 bytes whenever the
            # prefix is 0x04 and is never told the buffer length, so a 33-byte
            # key claiming to be uncompressed would be read past its end. The
            # length and the prefix have to agree before the pointer is handed
            # over, and this is the test that says they do.
            ("33 bytes with an 0x04 prefix",
             lib.cnx_ecdsa_verify(b"\x04" + pub33[1:], 33, dg, 32, sig64, 64), -4),
            ("65 bytes with an 0x02 prefix",
             lib.cnx_ecdsa_verify(b"\x02" + pub65[1:], 65, dg, 32, sig64, 64), -4),
            ("a 34-byte public key", lib.cnx_ecdsa_verify(pub33 + b"\x00", 34, dg, 32, sig64, 64), -4),
            ("an off-curve public key", lib.cnx_ecdsa_verify(b"\x02" + b"\xff" * 32, 33, dg, 32, sig64, 64), -5),
            ("a 63-byte signature", lib.cnx_ecdsa_verify(pub33, 33, dg, 32, sig64[:63], 63), -2),
        ]
        for name, rc2, want_rc in rejects:
            if rc2 != want_rc:
                problems.append(f"verify of {name} returned {rc2}, expected {want_rc}")
        if lib.cnx_ecdsa_verify(pub65, 65, dg, 32, sig64, 64) != 0:
            problems.append("verify rejected a good signature under the UNCOMPRESSED key")
        if not check:
            print(f"  verification rejects x{len(rejects)} OK (incl. the pubkey-overread guard)")

        # ---- recoverable signing and ecrecover
        rc, sig65 = sign(lib, sk, dg, recoverable=True)
        if rc != 0 or sig65.hex() != RECOVERABLE_SIG:
            problems.append(f"recoverable sign = {sig65.hex()} rc={rc}, expected {RECOVERABLE_SIG}")
        if sig65[:64] != sig64:
            problems.append("the recoverable signature's first 64 bytes differ from the plain one")
        if sig65[64] > 3:
            problems.append(f"recovery id {sig65[64]} is outside 0..3")
        rc, got = recover(lib, sig65, dg)
        if rc != 0 or got.hex() != RECOVERABLE_PUB:
            problems.append(f"recover = {got.hex()} rc={rc}, expected {RECOVERABLE_PUB}")
        if got != pub65:
            problems.append("the recovered key is not the signer's key")
        # A wrong recovery id must not yield the signer. (It usually recovers
        # SOME valid key, which is exactly why a caller must compare the result
        # against the key it expected rather than trust that recovery succeeded.)
        for wrong in range(4):
            if wrong == sig65[64]:
                continue
            rc2, got2 = recover(lib, sig65[:64] + bytes([wrong]), dg)
            if rc2 == 0 and got2 == pub65:
                problems.append(f"recovery id {wrong} also recovered the signer")
        if lib.cnx_ecdsa_recover(sig65[:64] + b"\x04", 65, dg, 32,
                                 ctypes.create_string_buffer(65), 65) != -5:
            problems.append("a recovery id of 4 was not refused")
        if not check:
            print("  recoverable sign + ecrecover OK (round-trips to the signer)")

        # ---- ECDH: both sides must land on the same point, and on the pinned one
        a, b = bytes.fromhex(ECDH_A), bytes.fromhex(ECDH_B)
        _, apub = pubkey(lib, a, True)
        _, bpub = pubkey(lib, b, True)
        rca, sa = ecdh(lib, a, bpub)
        rcb, sb = ecdh(lib, b, apub)
        if rca != 0 or rcb != 0 or sa != sb:
            problems.append("ecdh(a,B) and ecdh(b,A) disagree")
        if sa.hex() != ECDH_POINT:
            problems.append(f"ecdh point = {sa.hex()}, expected {ECDH_POINT}")
        # The uncompressed form of the same key must give the same point.
        _, bpub65 = pubkey(lib, b, False)
        if ecdh(lib, a, bpub65)[1] != sa:
            problems.append("ecdh disagreed between the compressed and uncompressed forms of B")
        if not check:
            print("  ECDH OK (symmetric, and matches the pinned point)")

        # ---- the curve's fail-closed guards
        curve_guards = [
            ("seckey 0", lib.cnx_seckey_verify(bytes(32), 32), -4),
            ("seckey == the group order",
             lib.cnx_seckey_verify(SECP256K1_ORDER.to_bytes(32, "big"), 32), -4),
            ("seckey n-1 (the largest legal key)",
             lib.cnx_seckey_verify((SECP256K1_ORDER - 1).to_bytes(32, "big"), 32), 0),
            ("seckey 1 (the smallest legal key)",
             lib.cnx_seckey_verify((1).to_bytes(32, "big"), 32), 0),
            ("a 31-byte seckey", lib.cnx_seckey_verify(bytes(31), 31), -2),
            ("a NULL seckey", lib.cnx_seckey_verify(None, 32), -1),
            ("signing with key 0", sign(lib, bytes(32), dg)[0], -4),
            # Upstream refuses an all-zero digest because such a signature can be
            # forged for ANY key; the shim surfaces that as its own code rather
            # than letting it look like a generic failure.
            ("signing an all-zero digest", sign(lib, sk, bytes(32))[0], -7),
            ("ecdh with an off-curve pubkey", ecdh(lib, a, b"\x02" + b"\xff" * 32)[0], -4),
            ("ecdh with key 0", ecdh(lib, bytes(32), bpub)[0], -4),
        ]
        for name, rc2, want_rc in curve_guards:
            if rc2 != want_rc:
                problems.append(f"curve guard '{name}' returned {rc2}, expected {want_rc}")
        if not check:
            print(f"  curve fail-closed guards x{len(curve_guards)} OK")

        # ---- determinism, which is the claim the blinding could quietly break
        # Signing draws fresh OS entropy on every call for side-channel blinding.
        # That blinding is supposed to cancel out; if it ever did not, signatures
        # would vary run to run and every pinned vector above would be a flake
        # waiting to happen. Repeat the call and require one distinct answer.
        repeats = {sign(lib, sk, dg)[1] for _ in range(32)}
        if len(repeats) != 1:
            problems.append(f"32 signings of the same input produced {len(repeats)} distinct signatures")
        if not check:
            print("  determinism OK (32 signings of one input agree despite blinding)")

        # ---- the independent second opinion, when it is installed
        # The published vectors above already stand on their own. This block is
        # the stronger claim the plan asks for - that a CoinXT signature verifies
        # in a MAINSTREAM library, not just in CoinXT - and it SKIPS loudly
        # rather than silently when `ecdsa` is not present.
        try:
            from ecdsa import SECP256k1, SigningKey
            from ecdsa.util import sigdecode_string, sigencode_string
            have_ecdsa = True
        except ImportError:
            have_ecdsa = False
        if have_ecdsa:
            key = SigningKey.from_string(sk, curve=SECP256k1)
            if not key.get_verifying_key().verify_digest(
                    sig64, dg, sigdecode=sigdecode_string):
                problems.append("a CoinXT signature did NOT verify in the `ecdsa` library")
            # And the reverse direction: their signature must satisfy our verify.
            theirs = key.sign_digest_deterministic(
                dg, hashfunc=hashlib.sha256, sigencode=sigencode_string)
            r = int.from_bytes(theirs[:32], "big")
            s = int.from_bytes(theirs[32:], "big")
            if s > SECP256K1_ORDER // 2:
                s = SECP256K1_ORDER - s
            low = r.to_bytes(32, "big") + s.to_bytes(32, "big")
            if lib.cnx_ecdsa_verify(pub33, 33, dg, 32, low, 64) != 0:
                problems.append("CoinXT did not verify a signature made by the `ecdsa` library")
            if not check:
                print("  cross-library OK (CoinXT signature verifies in `ecdsa`, and the reverse)")
        elif not check:
            print("  cross-library SKIPPED: the `ecdsa` package is not installed "
                  "(pip install ecdsa). The published vectors above still ran.")

    if problems:
        for p in problems:
            print("coin-kat: FAIL:", p)
        return 1
    print("coin-kat: self-check OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
