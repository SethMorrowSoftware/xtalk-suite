#!/usr/bin/env python3
"""check-gallery-ui-version: the gallery's UI version must FOLLOW its builder.

archive-gallery rebuilds its window only when the stamp it carries differs
from the one this script computes (agBuild: "if the uAgUiVersion of this
stack is agUiStamp() and there is a field agLog then exit agBuild"). That is
what makes a reopened stack open instantly, and on 2026-09-20 it is also how
a real engine run reported agCacheInfo, agLouder, agQuieter and tiles 11 to
24 MISSING: the three buttons and fourteen tiles had landed that morning,
kAgUiVersion still read the literal it was born with, and a reader pasting
the new script over the stack they already had got yesterday's window with
today's code behind it.

coinxt hit the identical failure first (tools/check-wallet-ui-version.py,
2026-09-04: a BIP-322 checkbox, the Inscribe and Lock buttons and four more
never appeared in any stack that already existed), and this is that gate
applied to this member's demo. It is a SECOND COPY rather than a shared
tool on purpose - each member ships its own gates so it still walks
standalone - but the two are not interchangeable and the difference is
worth stating: the wallet's constant IS its stamp, while this stack's stamp
is composed at runtime by agUiStamp() from the constant PLUS the geometry
(kAgCols, kAgGridRows, kAgTiles, the window and the tile size). The two
halves catch different changes and both are needed. A new control at the
same geometry changes a builder's TEXT and not one number, which is this
gate. A grid that goes from 10 tiles to 24 changes a number the builder
reads in a loop and not one character of its text, which is agUiStamp().

So the constant is DERIVED: kAgUiVersion must equal "gallery-" plus the
first twelve hex digits of the SHA-256 over the text of every
`command agBuild*` handler in the shipped demo, in file order, which is
exactly the text that decides what the window holds. Editing a builder
changes the fingerprint; this gate refuses the stale constant and prints
the right one; --fix writes it. An updated stack then rebuilds because the
stamp it stored is not the one the script computes, with nobody having to
remember anything.

The demo carries verbatim copies of two libraries between sentinels, and
this gate reads the SOURCE file rather than a copy - but it scans the whole
file anyway, because a library that defined an agBuild* handler would be a
collision sync-demo-embeds.py refuses long before this runs.

Usage:  python3 tools/check-gallery-ui-version.py [--fix]
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GALLERY = os.path.join(os.path.dirname(HERE), "examples", "archive-gallery.livecodescript")
PATTERN = re.compile(r"^(?:private )?command (agBuild\w*)\b.*?^end \1\s*$", re.M | re.S)
CONST = re.compile(r'^constant kAgUiVersion = "([^"]*)"$', re.M)
# The runtime stamp's other half, asserted here so a tidy-up that drops the
# geometry from agUiStamp() cannot silently leave this gate as the only
# mechanism - it would then pass a 10-tile grid as a 24-tile one.
STAMP = re.compile(r"^function agUiStamp\b.*?^end agUiStamp\s*$", re.M | re.S)
GEOMETRY = ("kAgCols", "kAgGridRows", "kAgTiles", "kAgWinW", "kAgWinH")


def fingerprint(text):
    whole = [m.group(0) for m in PATTERN.finditer(text)]
    if not whole:
        return None, 0
    digest = hashlib.sha256("\n".join(whole).encode("utf-8")).hexdigest()[:12]
    return "gallery-" + digest, len(whole)


def check_stamp(text):
    """agUiStamp() must still carry the numbers a builder's text cannot show."""
    m = STAMP.search(text)
    if not m:
        return ["no `function agUiStamp` in the demo - the runtime stamp is "
                "half of this mechanism and the geometry half is the half "
                "this gate cannot compute"]
    body = m.group(0)
    missing = [name for name in GEOMETRY if name not in body]
    if missing:
        return ["agUiStamp() no longer names %s, so a layout change that edits "
                "no builder text would not invalidate a built window"
                % ", ".join(missing)]
    return []


def main(argv):
    fix = "--fix" in argv[1:]
    text = open(GALLERY, encoding="utf-8").read()
    problems = check_stamp(text)
    want, count = fingerprint(text)
    if want is None:
        problems.append("found no `command agBuild*` handler, which is not this demo")
    m = CONST.search(text)
    if not m:
        problems.append('no `constant kAgUiVersion = "..."` line')
    if problems:
        for line in problems:
            print("check-gallery-ui-version: FAILED - %s" % line)
        return 1
    have = m.group(1)
    if have == want:
        print("check-gallery-ui-version: OK (kAgUiVersion %s follows %d agBuild* "
              "handler(s); agUiStamp() carries the geometry)" % (want, count))
        return 0
    if fix:
        text = text[:m.start(1)] + want + text[m.end(1):]
        open(GALLERY, "w", encoding="utf-8").write(text)
        print("check-gallery-ui-version: wrote kAgUiVersion %s (was %s) over %d "
              "agBuild* handler(s)" % (want, have, count))
        return 0
    print("check-gallery-ui-version: FAILED - kAgUiVersion is %s but the %d "
          "agBuild* handlers fingerprint to %s. A window built under the old "
          "value would never gain what the builder now makes, which is exactly "
          "what a real engine reported on 2026-09-20. Run with --fix."
          % (have, count, want))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
