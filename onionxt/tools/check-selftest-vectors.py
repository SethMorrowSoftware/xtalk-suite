#!/usr/bin/env python3
"""check-selftest-vectors.py - re-derive every pinned vector in the harness.

WHY THIS EXISTS
    examples/onionxt-tests.livecodescript carries its known-answer vectors as
    hex and base32 LITERALS, hand-copied from tools/onion-kat.py, and until
    2026-08-19 nothing compared the two. A transcription slip in either
    direction produced a harness that agreed with itself: the literal is the
    expectation, so a wrong literal is a test that passes for the wrong value.
    coinxt and riptide have both shipped this gate for their own harnesses;
    onionxt did not.

WHAT IT RE-DERIVES, AND HOW INDEPENDENTLY
    Independence varies by vector and the report says which is which, because
    "re-derived" from the same file the literal was copied from is a weaker
    claim than "re-derived from the standard library":

      HMAC-SHA256   hmac + hashlib. Fully independent of this repo.
      v3 onion      the address <-> pubkey round trip AND the checksum, the
                    latter recomputed with hashlib.sha3_256 against the
                    published ".onion checksum" construction - so a corrupted
                    literal fails even if onion-kat.py were corrupted the same
                    way.
      expanded key  tools/onion-kat.py's ed25519 implementation. This one is
                    NOT independent: it is the file the literal was copied
                    from, so it catches TRANSCRIPTION only. Said plainly rather
                    than counted as if it were the same kind of evidence.

IT REPORTS WHAT IT CHECKED, NOT WHAT IT PARSED
    coinxt's constant gate once printed "66 harness constants re-derived" where
    66 was the number it had FOUND, and two constants added in the same change
    sailed through. So this enumerates every long literal in the harness and
    fails on any that is neither re-derived nor listed as an input with a
    reason. A new vector cannot land unchecked.

USAGE
    python3 onionxt/tools/check-selftest-vectors.py
    Exit 0 when every vector re-derives, 1 otherwise.
"""
import hashlib
import hmac
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
HARNESS = os.path.join(MEMBER, "examples", "onionxt-tests.livecodescript")

_spec = importlib.util.spec_from_file_location(
    "onion_kat", os.path.join(HERE, "onion-kat.py"))
KAT = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(KAT)

# A literal that is an INPUT rather than an expectation gets a reason here.
# Empty today: every long literal in this harness is something we can derive.
INPUTS = {}

LITERAL_RE = re.compile(r'"([0-9a-fA-F]{24,}|[a-z2-7]{40,}(?:\.onion)?)"')


def harness_literals():
    """Every long literal in CODE (comments stripped: prose is not a vector)."""
    text = open(HARNESS, encoding="utf-8").read()
    code = "\n".join(ln.split("--", 1)[0] for ln in text.split("\n"))
    return code, set(LITERAL_RE.findall(code))


def onion_checksum_ok(addr):
    """Recompute the v3 checksum from the published construction, with the
    standard library - NOT with onion-kat.py's copy of it."""
    core = addr[:-len(".onion")] if addr.endswith(".onion") else addr
    raw = KAT.base32_decode(core)
    if len(raw) != 35 or raw[34] != 3:
        return False
    pub, chk = raw[:32], raw[32:34]
    want = hashlib.sha3_256(b".onion checksum" + pub + b"\x03").digest()[:2]
    return chk == want


def main(argv):
    code, lits = harness_literals()
    checked, notes, problems = set(), [], []

    # ---- 1. the two v3 onion addresses --------------------------------------
    addrs = [l for l in lits if l.endswith(".onion")]
    if len(addrs) != 2:
        problems.append(f"expected 2 .onion literals, found {len(addrs)} - the "
                        "harness changed and this gate has not")
    for addr in sorted(addrs):
        if not onion_checksum_ok(addr):
            problems.append(f"{addr}: the v3 checksum does not recompute "
                            "(hashlib.sha3_256 over the published construction)")
            continue
        pub = KAT.pubkey_from_address(addr)
        back = KAT.address_from_pubkey(pub)
        if back != (addr[:-len(".onion")] if not addr.endswith(".onion") else addr):
            # address_from_pubkey may or may not append .onion; compare cores
            if back.rstrip(".onion") != addr[:-len(".onion")]:
                problems.append(f"{addr}: does not survive the pubkey round trip "
                                f"(got {back})")
                continue
        checked.add(addr)
        notes.append(f"  ok   {addr[:20]}... v3 checksum recomputed (stdlib) and "
                     "pubkey round-trips")

    # ---- 2. HMAC-SHA256, RFC 4231 Test Case 2 -------------------------------
    want = hmac.new(b"Jefe", b"what do ya want for nothing?",
                    hashlib.sha256).hexdigest()
    if want in lits:
        checked.add(want)
        notes.append("  ok   sxHmacSha256 RFC 4231 TC2 re-derived with hmac+hashlib "
                     "(independent of this repo)")
    else:
        problems.append("the RFC 4231 Test Case 2 HMAC literal is not in the "
                        f"harness - expected {want}")

    # ---- 3. the 64-byte expanded key for seed 0x42 x 32 ---------------------
    exp = KAT.expanded_key_from_seed(b"\x42" * 32).hex()
    # MATCH THE FRAGMENTS AGAINST THE DERIVED VALUE, do not just concatenate
    # every remaining hex literal in source order. The first version did the
    # latter, and a mutation exposed it: a NEW unrelated hex vector added to the
    # harness got swept into the expanded key, which then failed as a
    # "does not re-derive" - the right verdict for the wrong reason, and the
    # wrong message for whoever added it. Accumulate only while the running
    # join is still a PREFIX of what onion-kat.py derives; anything that does
    # not fit stays unaccounted and is reported as such by check 4.
    ordered = sorted((l for l in lits if re.fullmatch(r'[0-9a-f]{24,}', l)
                      and l != want), key=lambda s: code.index('"' + s + '"'))
    frags, joined = [], ""
    for l in ordered:
        if exp.startswith(joined + l):
            frags.append(l)
            joined += l
            if joined == exp:
                break
    if joined == exp:
        checked.update(frags)
        notes.append(f"  ok   expanded key for seed 0x42 x 32 re-derived from "
                     f"onion-kat.py and matches across {len(frags)} source "
                     "fragment(s) - TRANSCRIPTION only, same file it was copied from")
    else:
        problems.append("the expanded-key literal(s) do not re-derive: harness has "
                        f"{joined[:32]}... ({len(joined)} chars), onion-kat.py "
                        f"derives {exp[:32]}... ({len(exp)} chars)")

    # ---- 4. nothing unaccounted --------------------------------------------
    loose = sorted(lits - checked - set(INPUTS))
    for l in loose:
        problems.append(f"{l[:48]}...: a long literal this gate neither re-derives "
                        "nor lists in INPUTS with a reason - add it on purpose")

    for n in notes:
        print(n)
    for p in problems:
        print("check-selftest-vectors: " + p)
    if problems:
        print(f"check-selftest-vectors: {len(problems)} problem(s)")
        return 1
    print(f"check-selftest-vectors: OK ({len(checked)} of {len(lits)} harness "
          f"literal(s) re-derived, {len(INPUTS)} listed as inputs; every long "
          "literal accounted for)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
