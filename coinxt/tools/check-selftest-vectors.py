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
