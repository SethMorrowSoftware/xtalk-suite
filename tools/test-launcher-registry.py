#!/usr/bin/env python3
"""test-launcher-registry.py - prove the front-door gate fires in all three
directions, and specifically for a row whose stack carries NO block.

Direction 2 was blind to seven of the twenty-seven rows until 2026-08-20: its
runnable set was the union of two drift gates' ADOPTERS lists, which omits
check-ui-kit-drift.py's EXEMPT map - the stacks that build a window and
deliberately do not carry the kit. Deleting the box2dxt-platformer row left the
gate green. That is why one of the mutations below is specifically an EXEMPT-list
row: a fixture that only ever drops an ADOPTERS row would have passed against the
blind version too.

Mutations are applied to the real start-here.livecodescript and restored in a
finally block, so what is tested is the gate as build-all.sh runs it.

USAGE
    python3 tools/test-launcher-registry.py
"""

import contextlib
import importlib.util
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LAUNCHER = os.path.join(ROOT, "start-here.livecodescript")


def load(name):
    spec = importlib.util.spec_from_file_location(
        name.replace("-", "_"), os.path.join(HERE, name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GATE = load("check-launcher-registry.py")


def run():
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            rc = GATE.main([])
        except TypeError:
            rc = GATE.main()
    return rc, buf.getvalue()


def drop_row(text, needle):
    out = [l for l in text.split("\n") if needle not in l]
    if len(out) == len(text.split("\n")):
        raise AssertionError("fixture stale: no registry row contains %r" % needle)
    return "\n".join(out)


CASES = [
    # (label, needle - a path that appears in exactly the row we mean)
    ("a ui-kit ADOPTERS row (enet-lan-chat)",
     "enetxt/examples/enet-lan-chat.livecodescript"),
    ("a ui-kit EXEMPT row - the blind spot (box2dxt-platformer)",
     "box2dxt/examples/box2dxt-platformer.livecodescript"),
    ("the other EXEMPT shape - a whole application (holde-em)",
     "holde-em/src/holdem.livecodescript"),
    ("a harness-scaffold ADOPTERS row (coin-selftest)",
     "coinxt/tests/coin-selftest.livecodescript"),
]


def main():
    rc, out = run()
    if rc != 0:
        print("test-launcher-registry: the tree is not clean to begin with")
        print(out)
        return 1

    original = open(LAUNCHER, encoding="utf-8").read()
    bad = 0
    try:
        for label, needle in CASES:
            open(LAUNCHER, "w", encoding="utf-8").write(drop_row(original, needle))
            rc, out = run()
            if rc == 0:
                bad += 1
                print("  SURVIVED: dropping %s left the gate green" % label)
            elif needle not in out:
                bad += 1
                print("  MISNAMED: dropping %s fired, but the message does not "
                      "name it:\n      %s" % (label, out.strip().splitlines()[0]))
    finally:
        open(LAUNCHER, "w", encoding="utf-8").write(original)

    if bad:
        print("test-launcher-registry: %d mutation(s) not caught" % bad)
        return 1
    rc, _ = run()
    if rc != 0:
        print("test-launcher-registry: the launcher was NOT restored")
        return 1
    print("test-launcher-registry: OK (%d dropped row(s), every one caught and "
          "named, launcher restored)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
