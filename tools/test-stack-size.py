#!/usr/bin/env python3
"""test-stack-size.py - prove the 720p budget gate fires on all three legs.

The gate reported "OK (43 stack window dimension(s) in 27 file(s))" for months
while measuring NOTHING in nocloud, whose only sizing call parenthesises its
title. That is a count of what it PARSED, printed as what it CHECKED - the shape
root CLAUDE.md records for coinxt's constant gate. Rewriting nocloud's window to
1600x1200 did not change the number or the verdict.

So the fixtures are deliberately not just "an oversize window fails". The three
legs are:
  1. STRICT   - an oversize dimension it can read.
  2. LOOSE    - a sizing line it CANNOT read is a failure, not a silent skip.
  3. CROSS    - a stack that builds a window (per check-ui-kit-drift's ADOPTERS
                or EXEMPT) and contributes no dimension at all is a failure.
Leg 3 is the one that would have caught the original bug, and legs 1 and 2 both
pass against the blind version - which is why all three are here.

USAGE
    python3 tools/test-stack-size.py
"""

import contextlib
import importlib.util
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
NOCLOUD = os.path.join(ROOT, "nocloud", "src", "nocloudquickshare.livecodescript")

spec = importlib.util.spec_from_file_location(
    "css", os.path.join(HERE, "check-stack-size.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)

CHROME = 'uiChrome ("No Cloud Quick Share " & kQsAppVersion), 1100, 640, 56'


def run():
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = GATE.main()
    return rc, buf.getvalue()


CASES = [
    ("STRICT: an oversize window it CAN read",
     lambda t: t.replace(CHROME, CHROME.replace("1100, 640", "1600, 1200"), 1),
     "exceeds the 720p budget"),
    ("LOOSE: a sizing line it CANNOT read is a failure, not a skip",
     lambda t: t.replace(CHROME, 'uiChrome tTitle, tW, tH, 56', 1),
     "measured by NOTHING"),
    ("CROSS: a window-building stack contributing no dimension at all",
     lambda t: t.replace(CHROME, '-- ' + CHROME, 1),
     "contributes no measured dimension"),
]


def main():
    rc, out = run()
    if rc != 0:
        print("test-stack-size: the tree is not clean to begin with\n" + out)
        return 1
    if "45 stack window dimension" not in out:
        print("test-stack-size: expected 45 measured dimensions, got:\n" + out)
        return 1

    original = open(NOCLOUD, encoding="utf-8").read()
    if CHROME not in original:
        print("test-stack-size: fixture stale - nocloud's uiChrome line changed")
        return 1

    bad = 0
    try:
        for label, mutate, expect in CASES:
            open(NOCLOUD, "w", encoding="utf-8").write(mutate(original))
            rc, out = run()
            if rc == 0:
                bad += 1
                print("  SURVIVED: %s" % label)
            elif expect not in out:
                bad += 1
                print("  MISDIAGNOSED: %s\n      wanted %r in the output, got:\n%s"
                      % (label, expect, out))
    finally:
        open(NOCLOUD, "w", encoding="utf-8").write(original)

    if bad:
        print("test-stack-size: %d leg(s) not proven" % bad)
        return 1
    rc, _ = run()
    if rc != 0:
        print("test-stack-size: nocloud was NOT restored")
        return 1
    print("test-stack-size: OK (%d leg(s), each fires and names its own reason, "
          "tree restored)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
