#!/usr/bin/env python3
"""check-harness-scaffold-drift.py - the pasteable-harness scaffolding is
ONE block, byte-identical everywhere it is carried.

tools/harness-scaffold.livecodescript is the master; each window-building
harness embeds the block between its BEGIN/END marker lines verbatim. This
is the checker-drift/ui-kit-drift model applied to the harness scaffolding,
and it exists because the drift it guards against already happened: the
five scaffoldings were measured 99% identical with torrentxt's copy
spelling sections and summaries its own way, and the Copy button / SKIP
outcome / per-line paint each living in only one copy.

Three failure modes, all fatal: a registered adopter whose block differs
from the master; a file carrying the BEGIN marker that is not registered
(adoption must be deliberate); a registered adopter with no marker. The
GENERATED suite paste carries the core's copy, markers and all (the member
harnesses' copies are folded in prefixed, without markers), and is pinned to
its sources by build-suite-selftest.py --check, so it is skipped here by
exact path through GENERATED_CARRIERS, never by content.
tools/test-harness-scaffold-drift.py proves the skip is load-bearing and
path-exact, and that drift in the core's copy is caught.
"""

import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

MASTER = os.path.join("tools", "harness-scaffold.livecodescript")

ADOPTERS = [
    os.path.join("enetxt", "tests", "enet-selftest.livecodescript"),
    os.path.join("datachannelxt", "tests", "datachannel-selftest.livecodescript"),
    os.path.join("torrentxt", "tests", "torrent-selftest.livecodescript"),
    os.path.join("coinxt", "tests", "coin-selftest.livecodescript"),
    os.path.join("tests", "suite-selftest.core.livecodescript"),
]

BEGIN = ("-- ==== SUITE HARNESS SCAFFOLD v1 BEGIN (verbatim copy; master: "
         "tools/harness-scaffold.livecodescript; gate: "
         "tools/check-harness-scaffold-drift.py) ====")
END = "-- ==== SUITE HARNESS SCAFFOLD v1 END ===="


# GENERATED CARRIERS, skipped BY EXACT PATH and never by content. The suite
# paste carries the core's copy of this block, but it is not a copy anyone
# edits: tools/build-suite-selftest.py writes it from the core (whose copy
# this gate checks) and hoists the carried blocks' declarations above its
# first handler, so it is deliberately NOT byte-identical to the master, and
# `build-suite-selftest.py --check` pins it to the source instead. The same
# table is in all three carried-block drift gates (ui-kit, demo-selfcheck,
# this one), at module level so each gate's fixture can prove the skip is
# load-bearing and path-exact - a byte copy of the paste anywhere else in
# tests/ must still be flagged as an unregistered carrier.
GENERATED_CARRIERS = {
    os.path.join("tests", "suite-selftest.livecodescript"):
        "generated from the core by tools/build-suite-selftest.py, which hoists "
        "its carried blocks' declarations; --check pins it to the core",
}


def extract(path):
    text = open(os.path.join(ROOT, path), encoding="utf-8").read()
    lines = text.split("\n")
    begins = [i for i, l in enumerate(lines) if l.strip() == BEGIN]
    ends = [i for i, l in enumerate(lines) if l.strip() == END]
    if len(begins) != 1 or len(ends) != 1:
        return None, ("%s: expected exactly one BEGIN and one END marker, "
                      "found %d/%d" % (path, len(begins), len(ends)))
    if ends[0] <= begins[0]:
        return None, "%s: END marker precedes BEGIN" % path
    return "\n".join(lines[begins[0]:ends[0] + 1]), None


def main():
    problems = []
    master_block, err = extract(MASTER)
    if err:
        print("check-harness-scaffold-drift: FAILED - %s" % err)
        return 1

    # the generated paste carries the core's copy (see GENERATED_CARRIERS);
    # build-suite-selftest.py --check pins it to the checked source
    carriers = []
    for pattern in ("*/tests/*.livecodescript", "tests/*.livecodescript"):
        for path in sorted(glob.glob(os.path.join(ROOT, pattern))):
            rel = os.path.relpath(path, ROOT)
            if rel in GENERATED_CARRIERS:
                continue
            text = open(path, encoding="utf-8").read()
            if "GENERATED - do not edit" in text[:4000]:
                continue
            if BEGIN in text:
                carriers.append(rel)
    for rel in carriers:
        if rel not in ADOPTERS:
            problems.append("%s carries the scaffold but is not in ADOPTERS - "
                            "register it here in the same commit" % rel)

    checked = 0
    for rel in ADOPTERS:
        if not os.path.exists(os.path.join(ROOT, rel)):
            problems.append("%s is registered but does not exist" % rel)
            continue
        block, err = extract(rel)
        if err:
            problems.append(err)
            continue
        if block != master_block:
            mlines = master_block.split("\n")
            blines = block.split("\n")
            where = "line counts differ (%d vs master %d)" % (
                len(blines), len(mlines))
            for i, (a, b) in enumerate(zip(blines, mlines)):
                if a != b:
                    where = "first divergence at block line %d" % (i + 1)
                    break
            problems.append("%s: scaffold block DIFFERS from the master (%s) "
                            "- edit tools/harness-scaffold.livecodescript and "
                            "re-carry" % (rel, where))
            continue
        checked += 1

    if problems:
        print("check-harness-scaffold-drift: FAILED")
        for p in problems:
            print("  - %s" % p)
        return 1
    print("check-harness-scaffold-drift: OK (%d adopter(s) byte-identical to "
          "the master scaffold)" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
