#!/usr/bin/env python3
"""test-script-vectors.py - prove check-script-vectors.py FIRES.

The family's mutation-test law (root CLAUDE.md): a gate is exercised the way
the BUILD runs it, not the way its docstring describes it - and this member's
own adoption bar for an execution gate (IMPLEMENTATION-PLAN.md Phase 10) says
"a seeded mutation must fail it before it counts as cover". So this runs the
real gate over the real tree first (it must be clean), then seeds each defect
class into the SHIPPED src/nostrxt.livecodescript in place, runs the gate the
way build-all does, and restores the file byte-identically - try/finally -
before the next case.

The four defect classes, one per layer the gate covers:
  1. a serializer escape dropped (\\n emitted raw)      -> the id preimage moves
  2. the bech32 charset transposed (two digits swapped) -> every entity moves
  3. the NIP-44 padding rounded one byte high           -> every payload moves
  4. the MAC compare short-circuited to true            -> tampering accepted

Each mutation reconstructs a defect FAITHFULLY (an edit a human could make),
not a syntax error - a gate that only catches files that fail to parse would
be a parser, not a vector gate.

This file is SLOW (each case is a full gate run, and the gate interprets the
real script statement by statement), so it is an attestation to run when the
gate or the interpreter changes, not a per-push suite gate - the same standing
coinxt's mutation drives have. Run it and record the result.

USAGE
    python3 tools/test-script-vectors.py
    Exit 0 when the clean tree passes AND every mutation is caught.
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
GATE = os.path.join(HERE, "check-script-vectors.py")
SCRIPT = os.path.join(MEMBER, "src", "nostrxt.livecodescript")


def run_gate():
    proc = subprocess.run([sys.executable, GATE, "--check"],
                          capture_output=True, text=True, cwd=MEMBER)
    return proc.returncode, proc.stdout + proc.stderr


def check(label, want_fail, rc, out):
    ok = (rc != 0) if want_fail else (rc == 0)
    print(("  ok   " if ok else "  FAIL ") + label)
    if not ok:
        print(f"       rc={rc}\n" + out[-1500:])
    return ok


def mutate(original, old, new, label):
    assert original.count(old) >= 1, f"fixture stale: {label}: {old!r} not found"
    return original.replace(old, new, 1)


def main():
    all_ok = True
    rc, out = run_gate()
    all_ok &= check("the real tree is clean to begin with", False, rc, out)
    if not all_ok:
        return 1

    original = open(SCRIPT, encoding="utf-8").read()
    cases = [
        # 1. drop the \n escape: the serializer emits a raw newline where
        # NIP-01 mandates \\n - every id over content with a newline moves.
        ("a dropped serializer escape is caught",
         "put numToByte(92) & numToByte(110) after tOut",
         "put numToByte(10) after tOut"),
        # 2. transpose two bech32 digits: a classic transcription slip that
        # still round-trips against itself and is wrong against the world.
        ("a transposed bech32 charset is caught",
         'constant kNxBech32Charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"',
         'constant kNxBech32Charset = "qpzry9x8gf2tvdw0s3jn54khce6mua7l"'
         .replace("qp", "pq")),
        # 3. nudge the padding: one byte high keeps every structural check
        # green and changes every ciphertext.
        ("a nudged NIP-44 padding is caught",
         "return tChunk * (nxIntDiv(pLen - 1, tChunk) + 1)",
         "return tChunk * (nxIntDiv(pLen - 1, tChunk) + 1) + 32"),
        # 4. short-circuit the MAC compare: the tamper check stops firing and
        # a modified payload decrypts - the worst NIP-44 defect there is.
        ("a short-circuited MAC compare is caught",
         "if not nxCtEqualHex(nxHexEncode(tExpected), nxHexEncode(tMac)) then",
         "if false then"),
    ]
    for label, old, new in cases:
        try:
            mutated = mutate(original, old, new, label)
            open(SCRIPT, "w", encoding="utf-8").write(mutated)
            rc, out = run_gate()
            all_ok &= check(label, True, rc, out)
        finally:
            open(SCRIPT, "w", encoding="utf-8").write(original)

    rc, out = run_gate()
    all_ok &= check("the tree is byte-identical after the mutations", False,
                    rc, out)
    if not all_ok:
        print("test-script-vectors: FAILURES above")
        return 1
    print("test-script-vectors: all 4 mutations caught, tree restored")
    return 0


if __name__ == "__main__":
    sys.exit(main())
