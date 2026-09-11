#!/usr/bin/env python3
"""test-script-vectors.py - prove tools/check-script-vectors.py can FAIL.

A gate that has gone blind prints OK, and this tree has met that shape more
than once (coinxt's constant gate counting what it parsed as what it checked;
the demo-embed collision detector shipping blind). So this drives the gate
the way build-all.sh does - the real entry point, over a real copy of the
shipped stack - with one rules defect edited into the copy each time, and
requires a non-zero exit that NAMES the section the defect lives in. Then it
drives the untouched copy and requires OK, so a fixture that "fails" only
because the copy would not load cannot pass as discrimination.

The three defects are the three kinds of rule the game is made of: a hand
RANK (a straight flush scored as a straight), a SETTLEMENT (the odd chip
vanishing, which breaks chip conservation), and the DEAL (a shuffle that
never swaps). Each anchor must occur exactly once, so a rename in the shipped
script fails this test rather than silently turning a fixture into a no-op.
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
GATE = os.path.join(HERE, "check-script-vectors.py")
STACK = os.path.join(MEMBER, "src", "holdem.livecodescript")

# (label, anchor, replacement, the section the gate must name)
FIXTURES = [
    ("a straight flush ranked as a plain straight",
     '      return "08" & heTwoDigits(tHighStraight) & "00000000"\n',
     '      return "04" & heTwoDigits(tHighStraight) & "00000000"\n',
     "heTestEvaluatorRun"),
    ("the odd chip vanishing from a split pot",
     "      put tLayerAmt mod tWinCount into tRemainder\n",
     "      put 0 into tRemainder\n",
     "heTestBettingRun"),
    ("a shuffle that never swaps",
     "      put tHold into tDeckA[tSwapPos]\n",
     "      put tHold into tDeckA[tPos]\n",
     "heTestShuffleRun"),
]


def run_gate(path):
    proc = subprocess.run([sys.executable, GATE, "--source", path],
                          capture_output=True, text=True)
    return proc.returncode, proc.stdout + proc.stderr


def main():
    with open(STACK, "r", encoding="utf-8") as fh:
        shipped = fh.read()
    tmp = tempfile.mkdtemp(prefix="holdem-vectors-fixtures-")
    failed = 0
    try:
        for label, anchor, replacement, must_name in FIXTURES:
            if shipped.count(anchor) != 1:
                print("FAIL  %s - the anchor occurs %d times in the shipped stack, "
                      "so the fixture cannot apply" % (label, shipped.count(anchor)))
                failed += 1
                continue
            path = os.path.join(tmp, "mutated.livecodescript")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(shipped.replace(anchor, replacement))
            rc, out = run_gate(path)
            if rc == 0:
                failed += 1
                print("FAIL  %s - the gate passed a stack carrying it" % label)
            elif ("%s:" % must_name) not in out and ("%s " % must_name) not in out:
                failed += 1
                print("FAIL  %s - the gate failed without naming %s\n      %s"
                      % (label, must_name, out.strip().split("\n")[-1]))
            else:
                print("PASS  %s" % label)
        path = os.path.join(tmp, "clean.livecodescript")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(shipped)
        rc, out = run_gate(path)
        if rc != 0:
            failed += 1
            print("FAIL  the untouched copy does not pass, so nothing above was "
                  "discrimination\n      " + "\n      ".join(out.strip().split("\n")[-6:]))
        else:
            print("PASS  the untouched copy passes")
    finally:
        import shutil
        shutil.rmtree(tmp, ignore_errors=True)
    if failed:
        print("test-script-vectors: FAIL (%d)" % failed)
        return 1
    print("test-script-vectors: OK (%d seeded defects caught by section, the clean copy passes)"
          % len(FIXTURES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
