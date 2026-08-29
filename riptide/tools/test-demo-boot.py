#!/usr/bin/env python3
"""test-demo-boot.py - mutation-proves that check-demo-boot.py FIRES.

The family law (root CLAUDE.md): exercise a gate the way the build runs it,
because a gate that has gone blind reports OK and the discriminating test is
what makes the OK mean anything. Each fixture seeds a REAL defect - each one
drawn from the class that actually shipped on 2026-08-29 - into a COPY of
the shipped demo, runs the boot gate on the copy exactly as build-all runs
it (a subprocess, --check, --file), and requires a non-zero exit. A final
run against the unmodified file must PASS, or the fixtures prove nothing.

The seeded defects, and what each stands in for:
  1. A non-literal `constant` value - the compile-killer that took the
     whole one-unit stack script down (also check 22's territory; this
     gate must catch it too, because it catches it by EXECUTING).
  2. A missing card builder - a rail whose UI never comes to exist.
  3. An unguarded write into a control that is never built - the runtime
     `Chunk`-class error at openStack, the second 2026-08-29 failure shape.
  4. A registered control whose builder line is gone - the world-level
     control check.
"""
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
GATE = os.path.join(HERE, "check-demo-boot.py")
DEMO = os.path.join(MEMBER, "examples", "riptide-social.livecodescript")


def run_gate(path):
    r = subprocess.run([sys.executable, GATE, "--check", "--file", path],
                       capture_output=True, text=True)
    return r.returncode, r.stdout + r.stderr


def mutate(src, old, new, label):
    if src.count(old) != 1:
        print("test-demo-boot: fixture %r is stale - its anchor %r is not "
              "unique in the shipped demo (found %d); update the fixture"
              % (label, old[:60], src.count(old)))
        sys.exit(1)
    return src.replace(old, new)


def main():
    with open(DEMO, "r", encoding="utf-8") as fh:
        clean = fh.read()

    fixtures = [
        ("a non-literal constant kills the one-unit compile",
         'constant kNxDefaultRelayOne = "wss://relay.damus.io"',
         'constant kNxDefaultRelayOne = "wss://" & "relay.damus.io"'),
        ("a dropped card builder is a missing card",
         "   raBuildNostrCard\n",
         "\n"),
        ("an unguarded write to an unbuilt control fails the boot",
         "   raBuild\n   raProbe\n",
         '   raBuild\n   put "x" into field "raNoSuchControl"\n   raProbe\n'),
        ("a control that is registered but never built is caught",
         'uiButton "raNxCopyNpub", "Copy", "476,78,592,102"\n',
         "\n"),
    ]

    failed = 0
    for label, old, new in fixtures:
        mutated = mutate(clean, old, new, label)
        with tempfile.NamedTemporaryFile("w", suffix=".livecodescript",
                                         delete=False,
                                         encoding="utf-8") as fh:
            fh.write(mutated)
            tmp = fh.name
        try:
            rc, out = run_gate(tmp)
            if rc == 0:
                failed += 1
                print("FAIL  %s: the gate did NOT fire\n%s"
                      % (label, out[-400:]))
            else:
                print("PASS  %s" % label)
        finally:
            os.unlink(tmp)

    rc, out = run_gate(DEMO)
    if rc != 0:
        failed += 1
        print("FAIL  the UNMODIFIED demo must pass (else the fixtures "
              "prove nothing)\n%s" % out[-400:])
    else:
        print("PASS  the unmodified demo boots green")

    if failed:
        print("test-demo-boot: %d fixture(s) misbehaved" % failed)
        return 1
    print("test-demo-boot: OK (%d seeded defects caught, clean run passes)"
          % len(fixtures))
    return 0


if __name__ == "__main__":
    sys.exit(main())
