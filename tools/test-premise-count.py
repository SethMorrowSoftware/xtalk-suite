#!/usr/bin/env python3
"""test-premise-count.py - prove check-premise-count.py measures and refuses.

Both directions, because a gate that fails on everything and a gate that passes
on everything are equally useless and look identical from a single test. The
mutations edit the REAL tree in place and restore in a finally - the idiom
tools/test-cross-library-names.py already uses - so the gate is exercised the way
tools/build-all.sh runs it rather than against a hand-built fixture the pipeline
never produces. That distinction is written into this repo's CLAUDE.md as a
lesson paid for once: a mutation test that drove a FUNCTION with a hand-made
input proved a property of the input, not of the tool.

Usage:
  python3 tools/test-premise-count.py
"""

import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TOOL = os.path.join(HERE, "check-premise-count.py")
SCRATCH = os.path.join(ROOT, "docs", "ZZ-premise-count-fixture.md")


def run():
    proc = subprocess.run([sys.executable, TOOL], cwd=ROOT,
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return proc.returncode, proc.stdout.decode("utf-8", "replace")


def main():
    failures = []

    code, out = run()
    if code != 0:
        failures.append("baseline: exit %d, wanted 0\n%s" % (code, out[-900:]))
    else:
        print("  ok  baseline                  -> exit 0")

    # It must actually be COUNTING, not reporting a constant. A file carrying
    # the premise sentence must move the number by exactly one.
    before = out
    n_before = int(before.split("count: ")[1].split(" premise")[0])
    try:
        with open(SCRATCH, "w") as fh:
            fh.write("# fixture\n\nOXT has no headless way to compile this.\n")
        code, out = run()
        n_after = int(out.split("count: ")[1].split(" premise")[0])
        if n_after != n_before + 1:
            failures.append("adding one premise site moved the count from %d to "
                            "%d - the gate is not counting" % (n_before, n_after))
        else:
            print("  ok  counts a new site        -> %d -> %d" % (n_before, n_after))
    finally:
        if os.path.exists(SCRATCH):
            os.remove(SCRATCH)

    # Drifted prose must fail. This is the rot the gate exists for.
    try:
        with open(SCRATCH, "w") as fh:
            fh.write("# fixture\n\nThe premise is asserted in 9999 places across "
                     "8888 files, which is not true.\n")
        code, out = run()
        if code != 1 or "quote a figure that no longer measures true" not in out:
            failures.append("drifted quote: exit %d, wanted 1\n%s" % (code, out[-900:]))
        else:
            print("  ok  refuses a drifted quote -> exit 1")
    finally:
        if os.path.exists(SCRATCH):
            os.remove(SCRATCH)

    # A quote that AGREES must pass, or the gate is just banning the phrase.
    code, out = run()
    n = int(out.split("count: ")[1].split(" premise")[0])
    f = int(out.split("across ")[1].split(" file")[0])
    try:
        with open(SCRATCH, "w") as fh:
            fh.write("# fixture\n\nMeasured: %d places across %d files.\n" % (n, f))
        code, out = run()
        if code != 0:
            failures.append("agreeing quote: exit %d, wanted 0 - the gate is "
                            "banning the phrase rather than checking the "
                            "number\n%s" % (code, out[-900:]))
        else:
            print("  ok  accepts an agreeing quote-> exit 0")
    finally:
        if os.path.exists(SCRATCH):
            os.remove(SCRATCH)

    # The dated-record escape works, and ONLY with the token.
    try:
        with open(SCRATCH, "w") as fh:
            fh.write("# fixture\n\nAn earlier draft said 9999 places across "
                     "8888 files. [stale-by-design]\n")
        code, out = run()
        if code != 0:
            failures.append("stale-by-design token: exit %d, wanted 0 - a dated "
                            "record must be able to quote a figure that has "
                            "stopped being true\n%s" % (code, out[-900:]))
        else:
            print("  ok  [stale-by-design] escapes-> exit 0")
    finally:
        if os.path.exists(SCRATCH):
            os.remove(SCRATCH)

    # A blinded pattern set must hit the floor, not report a clean small number.
    src = open(TOOL).read()
    assert "PREMISE_PATTERNS = [" in src, "the pattern list moved"
    try:
        broken = src.replace('re.compile(r"no headless way", re.I),',
                             're.compile(r"zzz-no-such-phrase-zzz", re.I),')
        broken = broken.replace('re.compile(r"NO headless way", 0),',
                                're.compile(r"zzz-no-such-phrase-2-zzz", 0),')
        broken = broken.replace('re.compile(r"cannot compile (?:or|and) run", re.I),',
                                're.compile(r"zzz-no-such-phrase-3-zzz", re.I),')
        broken = broken.replace('re.compile(r"OXT cannot compile", re.I),',
                                're.compile(r"zzz-no-such-phrase-4-zzz", re.I),')
        open(TOOL, "w").write(broken)
        code, out = run()
        if code != 1 or "below the floor" not in out:
            failures.append("blinded patterns: exit %d, wanted 1 with a floor "
                            "failure - a gate that has gone blind must not "
                            "report a clean small number\n%s" % (code, out[-900:]))
        else:
            print("  ok  blinded patterns hit the floor -> exit 1")
    finally:
        open(TOOL, "w").write(src)

    if failures:
        print("\ntest-premise-count: %d FAILURE(S)\n" % len(failures))
        for f in failures:
            print(f + "\n")
        return 1
    print("\ntest-premise-count: OK - it counts, it refuses drift, it accepts "
          "agreement, and a blinded pattern set fails on the floor instead of "
          "reporting a tidy small number.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
