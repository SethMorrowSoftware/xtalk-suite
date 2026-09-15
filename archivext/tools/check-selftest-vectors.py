#!/usr/bin/env python3
"""check-selftest-vectors.py - re-derive every pinned vector in the harness.

WHY THIS EXISTS
    examples/archivext-tests.livecodescript pins its known answers as
    constant literals. A transcription slip in either direction produces a
    harness that agrees with itself: the literal is the expectation, so a
    wrong literal is a test that passes for the wrong value. Every member
    with a vector harness ships this gate (the coinxt lesson).

HOW IT DERIVES, AND HOW INDEPENDENTLY
    The authority is tools/archive-kat.py's harness_vectors(), which derives
    every constant through tools/archive_reference.py - an implementation
    independent of the livecodescript under test, anchored AT IMPORT to
    the three source apps' own test vectors (a broken oracle refuses to
    load) - and from the fixture bytes under tests/fixtures/.

IT CHECKS BY NAME, BOTH DIRECTIONS
    1. Every (name, value) harness_vectors() emits must appear in the
       harness as `constant <name> = "<value>"`, byte-identical.
    2. Every `constant kAxVec...` in the harness must be one the KAT emits -
       a vector cannot land unchecked (the count-what-you-parsed lesson:
       this reports what it CHECKED, and fails on what it did not).
    3. Every other long literal in harness CODE (a hex run of 24+ characters
       or an http URL of 30+) must be listed in INPUTS with a written
       reason, or the gate fails.
    4. The constants sit between the KAT sentinels, and only there - the
       block is regenerated whole by `python3 tools/archive-kat.py`.

USAGE
    python3 archivext/tools/check-selftest-vectors.py [--check]
    Exit 0 when every vector re-derives, 1 otherwise.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
HARNESS = os.path.join(MEMBER, "examples", "archivext-tests.livecodescript")

_spec = importlib.util.spec_from_file_location(
    "archive_kat", os.path.join(HERE, "archive-kat.py"))
KAT = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(KAT)

BEGIN = "-- >>> KAT CONSTANTS BEGIN >>>"
END = "-- <<< KAT CONSTANTS END <<<"

# Long literals that are INPUTS rather than derived expectations, each with
# the reason it may stand unchecked.
INPUTS = {
    "https://archive.org/download/pride_prejudice_test/pp_01_austen_64kb.mp3":
        "the stream URL of the first chapter, spelled out where the vector "
        "is asserted so a reader sees the download path shape; it is also "
        "the oracle's download_url of the pinned chapter name",
    "https://archive.org/advancedsearch.php?q=x&fl%5B%5D=identifier&rows=24&page=1&output=json":
        "the defaults case of axSearchUrl (no sort, rows 24, page 1), "
        "written out so the parameter order is visible in the test",
    "https://archive.org/services/search/v1/scrape?q=x&count=100":
        "the defaults case of axScrapeUrl, same reason",
}

CONST_RE = re.compile(r'^constant (kAxVec\w+) = "(.*)"\s*$', re.M)
LITERAL_RE = re.compile(r'"([0-9a-fA-F]{24,}|https?://[^"]{30,})"')


def main(argv):
    text = open(HARNESS, encoding="utf-8").read()
    problems, notes = [], []

    if text.count(BEGIN) != 1 or text.count(END) != 1:
        print("check-selftest-vectors: the harness must carry exactly one KAT "
              "sentinel pair")
        return 1
    block = text.split(BEGIN, 1)[1].split(END, 1)[0]
    outside = text.split(BEGIN, 1)[0] + text.split(END, 1)[1]
    if CONST_RE.search(outside):
        problems.append("a kAxVec constant sits outside the KAT sentinels - "
                        "they are regenerated whole; move it inside")

    harness_consts = dict(CONST_RE.findall(block))
    derived = dict(KAT.harness_vectors())

    for name, value in derived.items():
        if name not in harness_consts:
            problems.append(f"{name}: derived by archive-kat.py but not pinned "
                            "in the harness")
        elif harness_consts[name] != value:
            problems.append(f"{name}: harness pins "
                            f"{harness_consts[name][:40]}... but the oracle "
                            f"derives {value[:40]}...")
        else:
            notes.append(f"  ok   {name}")

    for name in harness_consts:
        if name not in derived:
            problems.append(f"{name}: pinned in the harness but archive-kat.py "
                            "does not derive it - add the derivation there, "
                            "never hand-pin")

    code = "\n".join(ln.split("--", 1)[0] for ln in outside.split("\n"))
    accounted = set(harness_consts.values()) | set(INPUTS)
    loose = sorted(set(LITERAL_RE.findall(code)) - accounted)
    for lit in loose:
        problems.append(f"{lit[:60]}...: a long literal this gate neither "
                        "re-derives nor lists in INPUTS with a reason")
    for lit in INPUTS:
        if lit not in code:
            problems.append(f"INPUTS lists {lit[:60]}..., which the harness no "
                            "longer uses - delete the entry")

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
          f"archive-kat.py -> archive_reference.py + tests/fixtures; "
          f"{len(INPUTS)} input literal(s) listed with reasons; every long "
          "literal accounted for)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
