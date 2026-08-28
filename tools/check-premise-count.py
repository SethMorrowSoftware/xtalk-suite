#!/usr/bin/env python3
"""check-premise-count.py - MEASURE how many places assert the no-headless premise.

WHY THIS IS A GATE AND NOT A SENTENCE.

On 2026-08-28 a paragraph was added to this tree saying the no-headless premise
is asserted in "74 places across 65 files". The figure was measured, it was
correct for the pattern it was measured with, and within a day it had propagated
into seven documents - a CI comment, `tools/build-all.sh`, `CLAUDE.md`,
`docs/README.md`, `docs/OXT-ENGINE-NOTES.md` and two places in
`docs/HEADLESS-ENGINE.md`. An adversarial review then measured it a second way
and got a different answer, because the two passes used different patterns and
neither wrote its pattern down.

That is this repository's single most reliably-recurring failure - the
hand-copied constant, correct on the day and silently wrong after - and it
landed, of all places, on the document arguing that measurement beats
approximation. So the number does not live in prose anymore. It lives here,
where it is RE-DERIVED on every run and printed together with the convention
that produced it, and where prose that quotes a stale figure fails the build.

THE CONVENTION, stated so the number can be disbelieved precisely.

  * files: *.md, *.py, *.lcb, *.livecodescript, *.yml, *.c, *.cpp, *.h
  * a "premise site" is a LINE matching one of PREMISE_PATTERNS below
  * `.git` is excluded; nothing else is
  * a line matching twice counts once; a file is counted once however many
    lines it carries

Any other convention gives another number, and neither is wrong - which is
exactly why the convention has to travel with the figure.

WHAT IT REFUSES

  1. a count below FLOOR. A regex that has gone blind reports a clean small
     number, which reads like progress; the floor turns it into a failure. This
     is the remedy this tree already applied to coinxt's constant gate after it
     printed the count of constants it had PARSED as the count it had CHECKED.
  2. prose anywhere in the tree quoting "N places across M files" (or "N places
     in M files") where N or M disagrees with the measurement. That is the
     specific rot this gate exists for. A line carrying the literal token
     [stale-by-design] is skipped: a DATED RECORD may quote a figure that has
     since stopped being true, and this tree's annotate-do-not-rewrite rule for
     dated records requires that it can. The token has to be typed on purpose,
     so it is never reached by accident.

Usage:
  python3 tools/check-premise-count.py          # print the count; refuse drift
  python3 tools/check-premise-count.py --list    # also list every site
"""

import argparse
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

EXTENSIONS = (".md", ".py", ".lcb", ".livecodescript", ".yml", ".c", ".cpp", ".h")

# The premise, in the spellings the tree actually uses. Deliberately NOT a
# looser net: "GUI runtime" alone matches prose about the engine's UI that has
# nothing to do with headless compilation, and a pattern that over-matches makes
# the number meaningless in the other direction.
PREMISE_PATTERNS = [
    re.compile(r"no headless way", re.I),
    re.compile(r"NO headless way", 0),
    re.compile(r"cannot compile (?:or|and) run", re.I),
    re.compile(r"OXT cannot compile", re.I),
    re.compile(r"is a GUI runtime: there is NO headless", re.I),
]

# Measured 2026-08-28 at 74 sites / 65 files with the convention above. The
# floor is set well below that and well above zero: files legitimately gain and
# lose the sentence, but a walk or a pattern that has broken returns something
# near nothing.
FLOOR = 40

# "74 places across 65 files" and its near neighbours.
QUOTE = re.compile(r"(\d+)\s+places?\s+(?:across|in)\s+(\d+)\s+files?", re.I)

# A DATED RECORD may legitimately quote a figure that is no longer true - this
# tree's annotate-do-not-rewrite rule for dated records requires it, and the
# first thing this gate caught was a status-log entry recording what an earlier
# draft had said. The escape is a token the writer has to type on purpose, so it
# cannot be reached by accident, and it names itself. It is NOT a general
# exemption: a live sentence carrying it is a lie with a licence, and the token's
# presence in a non-record line should be treated as a review finding.
STALE_BY_DESIGN = "[stale-by-design]"


def walk():
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d != ".git"]
        for name in names:
            if name.endswith(EXTENSIONS):
                yield os.path.join(base, name)


def measure():
    sites = []
    for path in walk():
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                lines = fh.read().split("\n")
        except OSError:
            continue
        for i, line in enumerate(lines, 1):
            if any(p.search(line) for p in PREMISE_PATTERNS):
                sites.append((os.path.relpath(path, ROOT), i, line.strip()))
    return sites


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true", help="list every site")
    args = ap.parse_args()

    sites = measure()
    files = sorted({s[0] for s in sites})
    print("check-premise-count: %d premise site(s) across %d file(s)"
          % (len(sites), len(files)))
    print("  convention: lines matching %d pattern(s) in %s, excluding .git"
          % (len(PREMISE_PATTERNS), " ".join(EXTENSIONS)))
    if args.list:
        for rel, lineno, text in sites:
            print("    %s:%d  %s" % (rel, lineno, text[:110]))

    if len(sites) < FLOOR:
        print("\ncheck-premise-count: FAILED - %d sites is below the floor of "
              "%d. Either the premise really has been swept out of the tree - in "
              "which case lower the floor IN THE SAME CHANGE that did the "
              "sweeping, and say which dated engine record authorised it - or "
              "this gate has gone blind and is reporting a clean small number, "
              "which is the shape that reads like progress."
              % (len(sites), FLOOR))
        return 1

    drifted = []
    for path in walk():
        rel = os.path.relpath(path, ROOT)
        if rel == os.path.join("tools", "check-premise-count.py"):
            continue                     # this file names the figure on purpose
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                lines = fh.read().split("\n")
        except OSError:
            continue
        for i, line in enumerate(lines, 1):
            m = QUOTE.search(line)
            if not m:
                continue
            if STALE_BY_DESIGN in line:
                continue        # a dated record quoting what an earlier draft said
            n, mm = int(m.group(1)), int(m.group(2))
            if (n, mm) != (len(sites), len(files)):
                drifted.append((rel, i, m.group(0), line.strip()[:110]))

    if drifted:
        print("\ncheck-premise-count: FAILED - %d place(s) quote a figure that "
              "no longer measures true (%d/%d today):" % (len(drifted), len(sites), len(files)))
        for rel, i, quoted, text in drifted:
            print("    %s:%d  quotes %r\n        %s" % (rel, i, quoted, text))
        print("\n  Do not update the numbers in place - that is how they rotted "
              "the first time. Cite this gate instead, or drop the figure.")
        return 1

    print("  no prose in the tree quotes a drifted figure.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
