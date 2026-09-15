#!/usr/bin/env python3
"""test-script-vectors.py - prove check-script-vectors.py FIRES.

The family's mutation-test law (root CLAUDE.md): a gate is exercised the way
the BUILD runs it, not the way its docstring describes it. So this runs the
real gate over the real tree first (it must be clean), then seeds each
defect class into the SHIPPED src/archivext.livecodescript in place, runs
the gate the way build-all does, and restores the file byte-identically -
try/finally - before the next case.

The defect classes, one per layer the gate covers:
  1. two hex digits transposed in the percent-encoder's alphabet
                                                  -> every encoded URL moves
  2. the sanitizer no longer blanks a colon in plain mode
                                                  -> "Dracula: Chapter 1" queries a field
  3. a preset row's collection misspelled          -> the table diverges
  4. the chapter stem no longer strips _vbr        -> encodes stop grouping
  5. MP4-first inverted in the video ranking       -> the wrong encode plays
  6. the natural-order pad shortened to one digit  -> part10 sorts before part2
  7. the fixed etree ordering dropped              -> discs interleave
Each mutation reconstructs a defect FAITHFULLY (an edit a human could make),
not a syntax error - a gate that only catches files that fail to parse
would be a parser, not a vector gate.

Each case is a full gate run, so this takes a few minutes; it runs in
build-all.sh's member walk before the gate, per the fixture-before-gate law.

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
SCRIPT = os.path.join(MEMBER, "src", "archivext.livecodescript")


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
        ("a transposed hex alphabet is caught",
         'constant kAxHexDigits = "0123456789ABCDEF"',
         'constant kAxHexDigits = "0123456789ABDCEF"'),
        ("a sanitizer that keeps a colon in plain mode is caught",
         'put axBlankChars(tQ, "{}[]^~:") into tQ',
         'put axBlankChars(tQ, "{}[]^~") into tQ'),
        ("a misspelled preset collection is caught",
         "collection:(PhilLeshandFriends) AND mediatype:(etree)",
         "collection:(PhilLeshAndFriends) AND mediatype:(etree)"),
        ("a chapter stem that keeps _vbr is caught",
         'if axEndsWithAny(tStem, "_vbr,_orig,_original") then',
         'if axEndsWithAny(tStem, "_orig,_original") then'),
        ("an inverted MP4-first video rank is caught",
         '   else if pKind is "video" then\n      if tExtn is "mp4" then\n         put 0 into tRank\n      else\n         put 1 into tRank\n      end if',
         '   else if pKind is "video" then\n      if tExtn is "mp4" then\n         put 1 into tRank\n      else\n         put 0 into tRank\n      end if'),
        ("a one-digit natural pad is caught",
         "constant kAxNaturalPad = 12",
         "constant kAxNaturalPad = 1"),
        ("a dropped fixed etree ordering is caught",
         '      if tKind is "audio-tracks" then\n         put "1|" & axBlankChars(axNaturalKey(tEntry["name"]), tab) & tab & tG & return after tOrder\n      else if tKind is "documents" then',
         '      if tKind is "audio-tracks-never" then\n         put "1|" & axBlankChars(axNaturalKey(tEntry["name"]), tab) & tab & tG & return after tOrder\n      else if tKind is "documents" then'),
    ]
    for label, old, new in cases:
        mutated = mutate(original, old, new, label)
        try:
            open(SCRIPT, "w", encoding="utf-8").write(mutated)
            rc, out = run_gate()
            all_ok &= check(label, True, rc, out)
        finally:
            open(SCRIPT, "w", encoding="utf-8").write(original)
    rc, out = run_gate()
    all_ok &= check("the tree is restored and clean", False, rc, out)
    print("test-script-vectors: " + ("OK" if all_ok else "FAILED"))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
