#!/usr/bin/env python3
"""Docs smart-quote scan (Phase 0 gate).

The house style is straight quotes everywhere, including docs -- partly
hygiene, partly self-defence: prose gets pasted into scripts and commit
messages, and one curly quote that later drifts into a .livecodescript fails
OXT compilation (gotcha 1). Scans every tracked .md file; exit non-zero on
any hit.
"""

import pathlib
import sys

SMART_QUOTES = {0x2018, 0x2019, 0x201C, 0x201D}


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    bad = 0
    for path in sorted(root.rglob("*.md")):
        if ".git" in path.parts:
            continue
        rel = path.relative_to(root)
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            hits = sorted({c for c in line if ord(c) in SMART_QUOTES})
            if hits:
                print("FAIL  %s:%d: smart quote(s) %s -- use straight ASCII"
                      % (rel, lineno, "".join(hits)))
                bad += 1
    if bad:
        print("FAILED -- %d smart-quote line(s) in docs." % bad)
        return 1
    print("All docs are smart-quote clean.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
