#!/usr/bin/env python3
"""test-wallet-boot.py - mutation-proves that check-wallet-boot.py FIRES.

The family law (root CLAUDE.md): exercise a gate the way the build runs it,
because a gate that has gone blind reports OK, and the discriminating test is
what makes the OK mean anything. This member has two dated records of that
failing - a constant gate that reported what it had PARSED as what it had
CHECKED, and, in the same change set that added the boot gate, eleven checks
written against the wrong Checker shape so they passed for any value at all.

Each fixture seeds ONE real defect into a COPY of the shipped stack, runs the
boot gate on the copy exactly as build-all runs it (a subprocess, --check),
and requires a non-zero exit. A final run against the unmutated copy must
PASS, or the fixtures prove nothing about the gate and only that it is
unhappy.

THE PREFILL IS CUT TO TWO IN EVERY FIXTURE, INCLUDING THE CLEAN ONE. Booting
the shipped wallet derives forty addresses through script-level BIP-32 and
bech32, which is most of the gate's runtime and none of its subject: what is
under test here is whether the gate NOTICES things, not how many addresses it
notices them across. Cutting kWaPrefill to 2 makes each fixture a fast run of
the same code paths, and cutting it in the clean run too is what keeps the
comparison honest - the pass and the failures differ by the seeded defect and
by nothing else.

The seeded defects, and what each stands in for:
  1. A non-literal `constant` value - the compile-killer that takes a whole
     one-unit .livecodescript down, which the engine refuses at COMPILE time
     and this gate refuses before it parses.
  2. A control the registry names and no builder builds - the shape a
     rename leaves behind, and what the boot self-check exists to catch.
  3. A control built and never registered - the same gap from the other
     side, which is how the ten rail buttons turned out to be missing from
     kWaScControls.
  4. The show/hide sweep skipping one screen's prefix - the thing no reader
     can check, because it works by control index over 250-odd controls.
  5. The click router refusing to route buttons - the defect riptide's model
     was WRONG about (it answered the short name for `the name of`, so the
     router silently passed every click), and therefore the one this gate
     most needs to be able to see.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
GATE = os.path.join(HERE, "check-wallet-boot.py")
DEMO = os.path.join(MEMBER, "examples", "coin-wallet.livecodescript")

# The address window, cut for every fixture. See the header.
PREFILL = ("constant kWaPrefill = 20", "constant kWaPrefill = 2")


def run_gate(path):
    r = subprocess.run([sys.executable, GATE, "--check", "--file", path],
                       capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def mutate(src, old, new, label):
    if src.count(old) != 1:
        print("test-wallet-boot: fixture %r is stale - its anchor %r appears "
              "%d times in the shipped stack (want 1); update the fixture "
              "rather than the gate." % (label, old[:60], src.count(old)))
        sys.exit(1)
    return src.replace(old, new)


FIXTURES = [
    ("a non-literal constant kills the one-unit compile",
     'constant kWaFileMagic = "COINXT-WALLET-1"',
     'constant kWaFileMagic = "COINXT-WALLET" & "-1"'),
    ("a registered control that no builder builds",
     '   uiButton "wl_generate", "Generate a new seed", "196,484,380,510"\n',
     "\n"),
    ("a control built and named by nothing in the registry",
     '   uiWrap "wl_warn"',
     '   uiLabel "wl_notInTheRegistry", "x", "0,0,10,10", 10\n   uiWrap "wl_warn"'),
    ("the sweep skipping one screen's controls",
     '         if tPrefix is "nv" or tPrefix is "ui" then',
     '         if tPrefix is "nv" or tPrefix is "ui" or tPrefix is "tl" then'),
    ("the click router refusing to route any button",
     '   if word 1 of the name of the target is not "button" then',
     '   if word 1 of the name of the target is not "buttonn" then'),
]


def main():
    with open(DEMO, "r", encoding="utf-8") as fh:
        shipped = fh.read()
    clean = mutate(shipped, PREFILL[0], PREFILL[1], "the prefill cut")

    tmp = tempfile.mkdtemp(prefix="wallet-boot-fixtures-")
    failed = 0
    try:
        for label, old, new in FIXTURES:
            src = mutate(clean, old, new, label)
            path = os.path.join(tmp, "mutated.livecodescript")
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(src)
            rc, out = run_gate(path)
            if rc == 0:
                failed += 1
                print("FAIL  %s - the gate passed a stack carrying it" % label)
                print("      " + "\n      ".join(out.strip().split("\n")[-6:]))
            else:
                print("PASS  %s" % label)

        path = os.path.join(tmp, "clean.livecodescript")
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(clean)
        rc, out = run_gate(path)
        if rc != 0:
            failed += 1
            print("FAIL  the unmutated stack boots green - without this the "
                  "fixtures above prove only that the gate is unhappy")
            print("      " + "\n      ".join(out.strip().split("\n")[-25:]))
        else:
            print("PASS  the unmutated stack boots green")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failed:
        print("test-wallet-boot: %d problem(s)" % failed)
        return 1
    print("test-wallet-boot: OK (%d seeded defects caught, clean run passes)"
          % len(FIXTURES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
