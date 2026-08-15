#!/usr/bin/env python3
"""check-checker-drift.py - every member's copy of a copied tool is the SAME
tool.

Each member carries its own tools/check-livecodescript.py (and, where it has
docs gates, tools/check-docs-style.py) so the member stays self-contained
when worked on in isolation or mirrored to a standalone repository. The
standing cost of copy-per-member is drift, and the suite paid it in full:
the copies diverged into two independent implementations, sodiumxt's did not
know `switch` (it reported phantom problems in dispatchers and would have
hidden a real imbalance), and a fix applied to one copy was not applied to
the suite. The copies are unified now, and this gate is what keeps them
unified: it FAILS when any copy's bytes differ from its siblings', so "fix
one copy" is no longer a state the tree can quietly be in.

    python3 tools/check-checker-drift.py

Exit code 0 = every copy set is byte-identical, 1 = drift.
"""
import hashlib
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# tool name -> the members that must carry a byte-identical copy
COPY_SETS = {
    "check-livecodescript.py": ["sodiumxt", "torrentxt", "enetxt",
                                "datachannelxt", "onionxt", "coinxt",
                                "riptide", "nocloud", "box2dxt",
                                "holde-em"],
    "check-docs-style.py": ["sodiumxt", "onionxt", "coinxt", "riptide"],
}


def main():
    failures = []
    checked = 0
    for tool, members in sorted(COPY_SETS.items()):
        digests = {}
        for member in members:
            path = os.path.join(ROOT, member, "tools", tool)
            if not os.path.exists(path):
                failures.append("%s: missing from %s/tools/" % (tool, member))
                continue
            with open(path, "rb") as f:
                digests.setdefault(hashlib.sha256(f.read()).hexdigest(),
                                   []).append(member)
            checked += 1
        if len(digests) > 1:
            groups = ", ".join("{%s}" % ", ".join(ms)
                               for ms in sorted(digests.values()))
            failures.append(
                "%s has DRIFTED into %d variants: %s - re-sync every copy "
                "byte-identically (edit one, copy to the rest) in the same "
                "change" % (tool, len(digests), groups))
    if failures:
        print("check-checker-drift: %d FAILURE(S)" % len(failures))
        for f in failures:
            print("  " + f)
        return 1
    print("check-checker-drift: OK (%d copies across %d tools, "
          "byte-identical per tool)" % (checked, len(COPY_SETS)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
