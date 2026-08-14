#!/usr/bin/env python3
"""check-stack-size.py - every sample stack fits a 720p display.

The suite's demos and pasteable harnesses are run on real, often small,
machines - the two-machine passes happen on whatever hardware is in the
room. A 1280x720 display keeps roughly 640px of height once the OS
taskbar (~48) and the window title bar (~32) are gone, and a shade under
1280 of width once borders are counted. So the family budget is:

    width  <= 1200
    height <= 640

and this gate holds every stack to it. The closing-pass stack shipped at
780x1010 - its Tor section sat BELOW the bottom edge of exactly the
screens it was meant to close legs on - which is how rules earn gates
here (the checker-drift lesson: a rule without a gate rots).

What is checked: literal stack sizes in the three spellings the family
uses -

    set the width of this stack to 820
    set the height of this stack to kWinHeight     (same-file constant)
    uiChrome "Title", 1200, 640                    (the suite UI kit)

A size taken from a custom property (torrent-client restores the user's
chosen height) is the USER's choice, not a shipped default, and is out of
scope. A file with no stack sizing contributes nothing.
"""

import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

MAX_WIDTH = 1200
MAX_HEIGHT = 640

SET_RE = re.compile(
    r'^\s*set\s+the\s+(width|height)\s+of\s+this\s+stack\s+to\s+'
    r'([0-9]+|k[A-Za-z0-9_]+)\s*$')
CHROME_RE = re.compile(
    r'^\s*uiChrome\s+"[^"]*"\s*,\s*([0-9]+)\s*,\s*([0-9]+)\s*(?:,\s*[0-9]+\s*)?$')
CONST_RE = re.compile(
    r'^\s*constant\s+(k[A-Za-z0-9_]+)\s*=\s*([0-9]+)\s*(?:--.*)?$')

# the generated suite harness carries the core's numbers verbatim; checking
# both would double-report one source line, so the generated copy is skipped
# (build-suite-selftest.py --check already pins it to the core). The two
# suite-level carried-block MASTERS are templates, not runnable stacks: the
# harness scaffold sizes its window from kStWidth/kStHeight, which each
# ADOPTER declares - the gate reads the real numbers there.
SKIP = {os.path.join("tests", "suite-selftest.livecodescript"),
        os.path.join("tools", "ui-kit.livecodescript"),
        os.path.join("tools", "harness-scaffold.livecodescript")}


def check_file(path, rel, problems):
    lines = open(path, encoding="utf-8").read().split("\n")
    consts = {}
    for line in lines:
        m = CONST_RE.match(line)
        if m:
            consts[m.group(1)] = int(m.group(2))
    found = 0
    for i, line in enumerate(lines, 1):
        m = SET_RE.match(line)
        if m:
            axis, raw = m.group(1), m.group(2)
            if raw.isdigit():
                value = int(raw)
            elif raw in consts:
                value = consts[raw]
            else:
                problems.append(
                    "%s:%d: stack %s set from %s, which is not a literal "
                    "or a same-file numeric constant - use one so this "
                    "gate can read it" % (rel, i, axis, raw))
                continue
            found += 1
            limit = MAX_WIDTH if axis == "width" else MAX_HEIGHT
            if value > limit:
                problems.append(
                    "%s:%d: stack %s %d exceeds the 720p budget "
                    "(max %d)" % (rel, i, axis, value, limit))
        m = CHROME_RE.match(line)
        if m:
            found += 1
            width, height = int(m.group(1)), int(m.group(2))
            if width > MAX_WIDTH:
                problems.append(
                    "%s:%d: uiChrome width %d exceeds the 720p budget "
                    "(max %d)" % (rel, i, width, MAX_WIDTH))
            if height > MAX_HEIGHT:
                problems.append(
                    "%s:%d: uiChrome height %d exceeds the 720p budget "
                    "(max %d)" % (rel, i, height, MAX_HEIGHT))
    return found


def main():
    problems = []
    sized = 0
    files = 0
    for path in sorted(glob.glob(os.path.join(ROOT, "**", "*.livecodescript"),
                                 recursive=True)):
        rel = os.path.relpath(path, ROOT)
        if rel in SKIP:
            continue
        n = check_file(path, rel, problems)
        if n:
            files += 1
            sized += n
    if problems:
        print("check-stack-size: FAILED")
        for p in problems:
            print("  - %s" % p)
        return 1
    print("check-stack-size: OK (%d stack dimension(s) in %d file(s) "
          "within %dx%d)" % (sized, files, MAX_WIDTH, MAX_HEIGHT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
