#!/usr/bin/env python3
"""check-selftest-vectors.py - keep the OXT self-test's vectors honest.

tests/coin-selftest.livecodescript is the engine-side harness: a human pastes it
into OXT and it drives all 16 public cx* handlers against known answers. Its
expected values are LiteralS in a .livecodescript file, which means they are
hand-copied, which means they can drift - from tools/coin-kat.py, from the shim,
or from the published vectors themselves. A drifted expectation is worse than no
test: it turns a real regression into a green run, in a library that handles
money.

So this gate re-derives every constant in that harness and refuses to let it
disagree. It needs NO C compiler and no build, so it runs in the always-on gate
set on every push rather than only where a toolchain exists:

  * where Python ships an independent implementation of the primitive
    (hashlib, hmac), the constant is checked against THAT - which is the
    project rule, "cross-checked against an independent implementation before
    pinning", enforced continuously instead of once;
  * RIPEMD-160 is the known exception (OpenSSL 3 moved it to the legacy
    provider, so hashlib usually cannot supply it). There the constant is
    checked against the published vector table in tools/coin-kat.py, and the
    absence of a second opinion is REPORTED, never silently skipped;
  * the two structural claims the harness asserts but does not pin as a digest
    - that PBKDF2's short output prefixes its long one, and that Keccak-256 and
    SHA3-256 really do differ - are re-derived too.

The shim itself is coin-kat.py's job. This file's question is narrower and
different: does the harness we hand a human still SAY the right answers?

Usage:
  python3 tools/check-selftest-vectors.py          # per-vector detail
  python3 tools/check-selftest-vectors.py --check  # terse: one OK line or exit 1
"""

import hashlib
import hmac as pyhmac
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SELFTEST = os.path.normpath(os.path.join(HERE, "..", "tests",
                                         "coin-selftest.livecodescript"))
KAT = os.path.join(HERE, "coin-kat.py")


def load_constants(path):
    """Pull `constant kName = "value"` out of the harness, in file order."""
    with open(path, "r", encoding="utf-8") as handle:
        text = handle.read()
    found = re.findall(r'^constant (k\w+) = "([^"]*)"', text, re.M)
    return dict(found)


def load_kat_table(name):
    """Read one vector table out of coin-kat.py without importing it.

    coin-kat.py builds a shared library at import time in some flows; parsing the
    literal table keeps this gate free of side effects and of a compiler.
    """
    with open(KAT, "r", encoding="utf-8") as handle:
        text = handle.read()
    block = re.search(name + r"\s*=\s*\{(.*?)\n\}", text, re.S)
    if not block:
        return {}
    out = {}
    for key, val in re.findall(r'b"([^"]*)":\s*\(?\s*"([0-9a-f"\s\n]*)"',
                               block.group(1)):
        out[key] = re.sub(r'[\s"]', "", val)
    return out


def load_kat_curve():
    """The secp256k1 constants coin-kat.py pins, read by IMPORTING it.

    The hash tables above are scraped with a regex because they are flat dicts
    of byte strings. The curve tables are lists of tuples, where a regex would
    be both uglier and easier to get quietly wrong, so this leg evaluates the
    file instead. That is safe here for the same reason the regex was chosen
    over it before: coin-kat.py does all of its work inside main(), which is
    guarded by __name__, so evaluating it builds nothing and needs no compiler.

    It reads the SOURCE and execs it rather than going through importlib, and
    that is not stylistic. importlib would consult __pycache__, and a cached
    .pyc is only invalidated when the source's mtime OR size changes - so a
    one-character edit made within the same second as the last run (exactly
    what editing a hex constant looks like) can leave this gate reading the
    PREVIOUS vectors and reporting OK. That was observed while mutation-testing
    this file, not theorised. A gate whose whole job is to catch drift must not
    have a stale-cache path, so it does not have one.
    """
    try:
        with open(KAT, "r", encoding="utf-8") as handle:
            source = handle.read()
        # __file__ has to be present: coin-kat.py derives its own paths from it
        # at module level, and __name__ has to be anything but "__main__" so its
        # entry point stays guarded.
        namespace = {"__name__": "coin_kat_vectors", "__file__": KAT}
        exec(compile(source, KAT, "exec"), namespace)  # noqa: S102 - see above
        pub = {sk: (c, u) for sk, c, u in namespace["PUBKEYS"]}
        sig = {(sk, msg): s for sk, msg, s in namespace["RFC6979"]}
        return {
            "pub1_compressed": pub[1][0],
            "pub1_uncompressed": pub[1][1],
            "sig_satoshi": sig[(1, b"Satoshi Nakamoto")],
        }
    except (OSError, SyntaxError, NameError, AttributeError, KeyError, ValueError):
        return None


def sha3_256(data):
    return hashlib.sha3_256(data).hexdigest()


def have_ripemd():
    try:
        hashlib.new("ripemd160")
        return True
    except (ValueError, TypeError):
        return False


def main(argv):
    terse = "--check" in argv[1:]
    problems = []
    notes = []

    if not os.path.exists(SELFTEST):
        print("check-selftest-vectors: tests/coin-selftest.livecodescript is missing")
        return 1

    k = load_constants(SELFTEST)
    if not k:
        print("check-selftest-vectors: no constants parsed - has the harness changed shape?")
        return 1

    def want(name, expected, source):
        got = k.get(name)
        if got is None:
            problems.append(f"{name} is missing from the harness")
        elif got != expected:
            problems.append(f"{name}\n      harness: {got}\n      {source}: {expected}")
        elif not terse:
            print(f"  OK  {name:16s} vs {source}")

    fox = k.get("kFox", "")
    mnemonic = k.get("kBip39Mnemonic", "").encode()
    salt = k.get("kBip39Salt", "").encode()

    # --- primitives Python can independently reproduce -----------------------
    want("kSha3Empty", sha3_256(b""), "hashlib")
    want("kSha3Abc", sha3_256(b"abc"), "hashlib")
    want("kSha3Fox", sha3_256(fox.encode()), "hashlib")

    want("kSha256Empty", hashlib.sha256(b"").hexdigest(), "hashlib")
    want("kSha256Abc", hashlib.sha256(b"abc").hexdigest(), "hashlib")
    want("kSha512Empty", hashlib.sha512(b"").hexdigest(), "hashlib")
    want("kSha512Abc", hashlib.sha512(b"abc").hexdigest(), "hashlib")

    key1 = b"\x0b" * 20
    want("kHmac1Sha256", pyhmac.new(key1, b"Hi There", hashlib.sha256).hexdigest(), "hmac")
    want("kHmac1Sha512", pyhmac.new(key1, b"Hi There", hashlib.sha512).hexdigest(), "hmac")
    msg2 = b"what do ya want for nothing?"
    want("kHmac2Sha256", pyhmac.new(b"Jefe", msg2, hashlib.sha256).hexdigest(), "hmac")
    want("kHmac2Sha512", pyhmac.new(b"Jefe", msg2, hashlib.sha512).hexdigest(), "hmac")

    want("kBip39Seed",
         hashlib.pbkdf2_hmac("sha512", mnemonic, salt, 2048, 64).hex(),
         "hashlib.pbkdf2")

    # --- Keccak-256: Python has no Keccak, so the KAT table is the reference --
    keccak = load_kat_table("KECCAK256")
    if keccak:
        want("kKeccakEmpty", keccak.get("", ""), "coin-kat")
        want("kKeccakAbc", keccak.get("abc", ""), "coin-kat")
    else:
        problems.append("could not read KECCAK256 out of tools/coin-kat.py")

    # --- RIPEMD-160: the one primitive with no second opinion ----------------
    ripe = load_kat_table("RIPEMD160")
    if have_ripemd():
        for name, msg in (("kRipeEmpty", b""), ("kRipeA", b"a"),
                          ("kRipeAbc", b"abc"), ("kRipeMsgDigest", b"message digest")):
            digest = hashlib.new("ripemd160", msg).hexdigest()
            want(name, digest, "hashlib")
    elif ripe:
        notes.append("RIPEMD-160: hashlib cannot supply it here (OpenSSL 3 legacy "
                     "provider), so the published table in coin-kat.py is the only "
                     "reference available - no independent second opinion.")
        for name, msg in (("kRipeEmpty", ""), ("kRipeA", "a"),
                          ("kRipeAbc", "abc"), ("kRipeMsgDigest", "message digest")):
            want(name, ripe.get(msg, ""), "coin-kat")
    else:
        problems.append("could not read RIPEMD160 out of tools/coin-kat.py")

    # --- secp256k1 (phase 2) -------------------------------------------------
    # Two tiers, the same shape this file already uses for RIPEMD-160.
    #
    # Tier 1 always runs: the harness constants must equal the ones coin-kat.py
    # pins. That is precisely the drift this gate exists to catch, because the
    # two files are meant to be the same claim at two layers, and only one of
    # them is driven by CI on every push.
    #
    # Tier 2 runs when the independent `ecdsa` package is installed, and then
    # RE-DERIVES the values rather than comparing two copies of them. When it is
    # absent the gate says so instead of quietly passing on tier 1 alone.
    curve = load_kat_curve()
    if curve is None:
        problems.append("could not read the secp256k1 tables out of tools/coin-kat.py")
    else:
        want("kPubOneCompressed", curve["pub1_compressed"], "coin-kat")
        want("kPubOneUncompressed", curve["pub1_uncompressed"], "coin-kat")
        want("kSigSatoshi", curve["sig_satoshi"], "coin-kat")

    try:
        from ecdsa import SECP256k1, SigningKey
        from ecdsa.util import sigencode_string
        order = SECP256k1.order
        key = SigningKey.from_secret_exponent(1, curve=SECP256k1)
        vk = key.get_verifying_key()
        want("kPubOneCompressed", vk.to_string("compressed").hex(), "ecdsa")
        want("kPubOneUncompressed", vk.to_string("uncompressed").hex(), "ecdsa")
        raw = key.sign_digest_deterministic(
            hashlib.sha256(b"Satoshi Nakamoto").digest(),
            hashfunc=hashlib.sha256, sigencode=sigencode_string)
        r = int.from_bytes(raw[:32], "big")
        s = int.from_bytes(raw[32:], "big")
        # Upstream always emits the low-s form; normalise before comparing so a
        # mismatch means a wrong signature and not a different convention.
        if s > order // 2:
            s = order - s
        want("kSigSatoshi", (r.to_bytes(32, "big") + s.to_bytes(32, "big")).hex(), "ecdsa")
    except ImportError:
        notes.append("secp256k1: the `ecdsa` package is not installed here, so the "
                     "curve constants were checked against the table in coin-kat.py "
                     "rather than re-derived independently (pip install ecdsa).")

    # --- the structural claims the harness makes beyond the fixed digests ----
    short = hashlib.pbkdf2_hmac("sha512", mnemonic, salt, 2048, 20).hex()
    if short != k.get("kBip39Seed", "")[:40]:
        problems.append("the harness asserts PBKDF2's 20-byte output prefixes its "
                        "64-byte one, and it does not")
    elif not terse:
        print("  OK  PBKDF2 short output prefixes the long one")

    if k.get("kSha3Abc") == k.get("kKeccakAbc") or k.get("kSha3Empty") == k.get("kKeccakEmpty"):
        problems.append("the harness asserts SHA3-256 and Keccak-256 differ, but its "
                        "own constants are equal - the aliasing trap it exists to "
                        "catch would go undetected")
    elif not terse:
        print("  OK  SHA3-256 and Keccak-256 constants genuinely differ")

    for note in notes:
        print(f"  note: {note}")

    if problems:
        print("check-selftest-vectors: FAILED")
        for problem in problems:
            print(f"  - {problem}")
        return 1

    print(f"check-selftest-vectors: OK ({len(k)} harness constant(s) re-derived)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
