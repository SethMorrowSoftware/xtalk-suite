#!/usr/bin/env python3
"""check-selftest-vectors.py - re-derive every pinned vector in the harness.

WHY THIS EXISTS
    examples/nostrxt-tests.livecodescript pins its known answers as constant
    literals. A transcription slip in either direction produces a harness
    that agrees with itself: the literal is the expectation, so a wrong
    literal is a test that passes for the wrong value. Every member with a
    vector harness ships this gate (the coinxt lesson); nostrxt ships it
    from day one.

HOW IT DERIVES, AND HOW INDEPENDENTLY
    The authority is tools/nostr-kat.py's harness_vectors(), which derives
    every constant through tools/nostr_reference.py - an implementation
    independent of the livecodescript under test, anchored AT IMPORT to the
    published BIP-340 / NIP-44 / BIP-173 / NIP-19 vectors (a broken oracle
    refuses to load). So "re-derived" here means: derived again from the
    published sets and the fixture definitions, not read back from the file
    the literal was copied from.

IT CHECKS BY NAME, BOTH DIRECTIONS
    1. Every (name, value) harness_vectors() emits must appear in the
       harness as `constant <name> = "<value>"`, byte-identical.
    2. Every `constant kNxVec...` in the harness must be one the KAT emits -
       a vector cannot land unchecked (the coinxt count-what-you-parsed
       lesson: this reports what it CHECKED, and fails on what it did not).
    3. Every other long literal in harness CODE must be listed in INPUTS
       with a written reason, or the gate fails.

USAGE
    python3 nostrxt/tools/check-selftest-vectors.py [--check]
    Exit 0 when every vector re-derives, 1 otherwise.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
HARNESS = os.path.join(MEMBER, "examples", "nostrxt-tests.livecodescript")

_spec = importlib.util.spec_from_file_location(
    "nostr_kat", os.path.join(HERE, "nostr-kat.py"))
KAT = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(KAT)

# Long literals that are INPUTS rather than derived expectations, each with
# the reason it may stand unchecked.
INPUTS = {
    "0000000000000000000000000000000000000000000000000000000000000000":
        "the all-zero 32 bytes: BIP-340's deterministic aux in one check and "
        "the invalid zero scalar in another - an input, not an expectation",
    "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff":
        "the all-ones id whose difficulty is zero by inspection - an input "
        "to nxPowDifficulty, not a derived value",
    "6EA6C7B5B5373CC1881DF20C8F80BB5F5577F3AC4C41747A55ACA40382436D46":
        "kNxVecIdB UPPERCASED - the input to the wire-lowercase refusal "
        "check (nxEventFromJson must refuse an uppercase id); the lowercase "
        "form re-derives by name as kNxVecIdB above",
}

CONST_RE = re.compile(r'^constant (kNxVec\w+) = "(.*)"\s*$', re.M)
LITERAL_RE = re.compile(
    r'"([0-9a-fA-F]{24,}'
    r'|(?:npub|nsec|note|nprofile|nevent|naddr)1[a-z0-9]{20,}'
    r'|[A-Za-z0-9+/]{40,}={0,2})"')


def main(argv):
    text = open(HARNESS, encoding="utf-8").read()
    problems, notes = [], []

    harness_consts = dict(CONST_RE.findall(text))
    derived = dict(KAT.harness_vectors())

    # 1. every derived vector is pinned, byte-identical
    for name, value in derived.items():
        if name not in harness_consts:
            problems.append(f"{name}: derived by nostr-kat.py but not pinned "
                            "in the harness")
        elif harness_consts[name] != value:
            problems.append(f"{name}: harness pins "
                            f"{harness_consts[name][:40]}... but the oracle "
                            f"derives {value[:40]}...")
        else:
            notes.append(f"  ok   {name}")

    # 2. every pinned kNxVec constant is one the KAT derives
    for name in harness_consts:
        if name not in derived:
            problems.append(f"{name}: pinned in the harness but nostr-kat.py "
                            "does not derive it - add the derivation there, "
                            "never hand-pin")

    # 3. every remaining long literal in CODE is an accounted input
    code = "\n".join(ln.split("--", 1)[0] for ln in text.split("\n"))
    accounted = set(harness_consts.values()) | set(INPUTS)
    loose = sorted(set(LITERAL_RE.findall(code)) - accounted)
    for lit in loose:
        problems.append(f"{lit[:48]}...: a long literal this gate neither "
                        "re-derives nor lists in INPUTS with a reason")

    if "--check" not in argv:
        for n in notes:
            print(n)
    for p in problems:
        print("check-selftest-vectors: " + p)
    if problems:
        print(f"check-selftest-vectors: {len(problems)} problem(s)")
        return 1
    print(f"check-selftest-vectors: OK ({len(notes)} of "
          f"{len(harness_consts)} pinned constants re-derived by name via "
          f"nostr-kat.py -> nostr_reference.py, {len(INPUTS)} input literal(s) "
          "listed with reasons; every long literal accounted for)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
