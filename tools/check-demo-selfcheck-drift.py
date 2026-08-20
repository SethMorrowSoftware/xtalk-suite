#!/usr/bin/env python3
"""check-demo-selfcheck-drift.py - the demo boot self-check is ONE block,
byte-identical everywhere it is carried.

tools/demo-selfcheck.livecodescript is the master; each adopting demo embeds
the block between its BEGIN/END marker lines verbatim. This is the
checker-drift / ui-kit-drift / harness-scaffold-drift model applied a fourth
time, and it exists BEFORE the drift rather than after it: the first version
of this block was written inline in one demo, and inlining it seventeen times
is precisely how the checker copies, the five harness scaffoldings and the
demo UI each drifted before each got a master and a gate.

Four failure modes, all fatal:
  - a registered adopter whose block differs from the master;
  - a file carrying the BEGIN marker that is not registered (adoption must be
    deliberate);
  - a registered adopter with no marker;
  - a registered adopter that carries the block but never calls scBegin, which
    would be a demo that ships the plumbing and reports nothing. That last one
    is the failure this gate is most likely to actually catch, because it is
    the one a copy-paste rollout produces.

Generated files are skipped: they are pinned to their sources by their own
--check.
"""

import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

MASTER = os.path.join("tools", "demo-selfcheck.livecodescript")

# Every adopter, with the prefix of the handler that drives it. A demo is added
# here in the same change that carries the block into it - never separately.
ADOPTERS = {
    os.path.join("enetxt", "examples", "enet-lan-chat.livecodescript"): "ec",
    os.path.join("datachannelxt", "examples",
                 "datachannel-dht-chat.livecodescript"): "wx",
    os.path.join("torrentxt", "examples",
                 "torrent-rp1-chat.livecodescript"): "rc",
    os.path.join("torrentxt", "examples",
                 "torrent-dht-channels.livecodescript"): "ch",
    os.path.join("torrentxt", "examples",
                 "torrent-client.livecodescript"): "tc",
    os.path.join("torrentxt", "examples",
                 "torrent-quickshare.livecodescript"): "qs",
    os.path.join("nocloud", "src", "nocloudquickshare.livecodescript"): "qs",
    os.path.join("datachannelxt", "examples",
                 "datachannel-loopback.livecodescript"): "lb",
}

BEGIN = ("-- ==== DEMO SELF-CHECK v1 BEGIN (verbatim copy; master: "
         "tools/demo-selfcheck.livecodescript; gate: "
         "tools/check-demo-selfcheck-drift.py) ====")
END = "-- ==== DEMO SELF-CHECK v1 END ===="

GENERATED = "GENERATED - do not edit"


def extract(path):
    text = open(os.path.join(ROOT, path), encoding="utf-8").read()
    lines = text.split("\n")
    begins = [i for i, l in enumerate(lines) if l.strip() == BEGIN]
    ends = [i for i, l in enumerate(lines) if l.strip() == END]
    if len(begins) != 1 or len(ends) != 1:
        return None, text, ("%s: expected exactly one BEGIN and one END marker, "
                            "found %d/%d" % (path, len(begins), len(ends)))
    if ends[0] <= begins[0]:
        return None, text, "%s: END marker precedes BEGIN" % path
    return "\n".join(lines[begins[0]:ends[0] + 1]), text, None


def main():
    problems = []
    master_block, _, err = extract(MASTER)
    if err:
        print(err)
        return 1

    for rel, prefix in sorted(ADOPTERS.items()):
        full = os.path.join(ROOT, rel)
        if not os.path.exists(full):
            problems.append("%s: registered adopter does not exist" % rel)
            continue
        block, text, err = extract(rel)
        if err:
            problems.append(err)
            continue
        if block != master_block:
            problems.append("%s: self-check block DIFFERS from the master. "
                            "Edit %s and re-carry; never patch an adopter."
                            % (rel, MASTER))
        # The block is inert unless the demo drives it. Both halves are
        # required: a run handler that calls scBegin, and openStack calling it.
        run = "%sScRun" % prefix
        if ("command %s" % run) not in text:
            problems.append("%s: carries the block but defines no %s"
                            % (rel, run))
        elif "scBegin" not in text:
            problems.append("%s: defines %s but never calls scBegin - the "
                            "block would ship and report nothing" % (rel, run))
        # EITHER lifecycle hook. Three demos build their window in
        # preOpenStack and never define openStack at all; requiring the one
        # spelling would have kept the block out of them for no reason.
        if not re.search(r"^on (?:pre)?[oO]penStack\b[\s\S]{0,600}?\b%s\b" % run,
                         text, re.M):
            problems.append("%s: %s is never reached from openStack or "
                            "preOpenStack" % (rel, run))

    for path in sorted(glob.glob(os.path.join(ROOT, "**", "*.livecodescript"),
                                 recursive=True)):
        rel = os.path.relpath(path, ROOT)
        if rel == MASTER or rel in ADOPTERS or rel.startswith(".git"):
            continue
        head = open(path, encoding="utf-8", errors="replace").read(4000)
        if GENERATED in head:
            continue
        body = open(path, encoding="utf-8", errors="replace").read()
        if BEGIN in body:
            problems.append("%s: carries the self-check block but is not "
                            "registered in ADOPTERS" % rel)

    for p in problems:
        print(p)
    if problems:
        print("check-demo-selfcheck-drift: %d problem(s)" % len(problems))
        return 1
    print("check-demo-selfcheck-drift: OK (%d adopter(s) byte-identical to the "
          "master, each driven from openStack)" % len(ADOPTERS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
