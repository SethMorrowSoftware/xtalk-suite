#!/usr/bin/env python3
"""check-ui-kit-drift.py - the demo UI kit is ONE block, byte-identical
everywhere it is carried.

tools/ui-kit.livecodescript is the master; each adopting demo stack embeds
the block between its BEGIN/END marker lines verbatim, so every demo stays a
single paste-and-run file (the suite rule) while the suite keeps one look.
That is the same shape as the per-member checker copies, and it fails the
same way the checkers once did: a fix applied to one copy and not the others.
check-checker-drift.py is the precedent; this gate is that idea for the kit.

Three failure modes, all fatal:
  - a registered adopter whose embedded block differs from the master
    (drift: the look was patched in place instead of in the master);
  - a file that carries the BEGIN marker but is not registered below
    (adoption must be deliberate, so a new adopter is a one-line change
    HERE in the same commit);
  - a registered adopter with no marker (the kit was dropped or the file
    moved, and the registry would otherwise rot into a list of exemptions
    nobody re-reads - the coverage-gate lesson).
"""

import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

MASTER = os.path.join("tools", "ui-kit.livecodescript")

# Adopters, repo-relative. Adding a demo to the kit means carrying the block
# AND adding it here, in the same commit.
ADOPTERS = [
    os.path.join("coinxt", "examples", "coinxt-demo.livecodescript"),
    os.path.join("datachannelxt", "examples", "datachannel-dht-chat.livecodescript"),
    os.path.join("datachannelxt", "examples", "datachannel-loopback.livecodescript"),
    os.path.join("enetxt", "examples", "enet-lan-chat.livecodescript"),
    os.path.join("riptide", "examples", "riptide-social.livecodescript"),
    os.path.join("torrentxt", "examples", "torrent-rp1-chat.livecodescript"),
    os.path.join("tests", "suite-closing-pass.livecodescript"),
]

BEGIN = ("-- ==== SUITE UI KIT v2 BEGIN (verbatim copy; master: "
         "tools/ui-kit.livecodescript; gate: tools/check-ui-kit-drift.py) ====")
END = "-- ==== SUITE UI KIT v2 END ===="


def extract(path):
    """The kit block of one file, marker lines included, or an error string.
    Inclusive of the markers so a tampered marker line is itself drift."""
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
        print("check-ui-kit-drift: FAILED - %s" % err)
        return 1

    # every stack that CARRIES the marker must be registered - member examples
    # (subdirectories included), app sources, and the suite-level stacks in
    # root tests/ alike. Generated files (the onionxt standalones, the folded
    # suite harness) inherit their source part's block and are checked at the
    # SOURCE, so a generated carrier is skipped rather than registered - its
    # freshness gate (build-standalone.py --check / build-suite-selftest.py
    # --check) already pins it to the checked source.
    carriers = []
    for pattern in ("*/examples/*.livecodescript",
                    "*/examples/*/*.livecodescript",
                    "*/src/*.livecodescript",
                    "tests/*.livecodescript"):
        for path in sorted(glob.glob(os.path.join(ROOT, pattern))):
            rel = os.path.relpath(path, ROOT)
            text = open(path, encoding="utf-8").read()
            if "GENERATED - do not edit" in text[:4000]:
                continue
            if BEGIN in text:
                carriers.append(rel)
    for rel in carriers:
        if rel not in ADOPTERS:
            problems.append("%s carries the kit but is not in ADOPTERS - "
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
            problems.append("%s: kit block DIFFERS from the master (%s) - "
                            "edit tools/ui-kit.livecodescript and re-carry"
                            % (rel, where))
            continue
        checked += 1

    if problems:
        print("check-ui-kit-drift: FAILED")
        for p in problems:
            print("  - %s" % p)
        return 1
    print("check-ui-kit-drift: OK (%d adopter(s) byte-identical to the "
          "master kit)" % checked)
    return 0


if __name__ == "__main__":
    sys.exit(main())
