#!/usr/bin/env python3
"""test-demo-selfcheck-drift.py - prove the self-check gates FIRE.

These fixtures exist because one of the checks they now cover was DEAD. The
drift gate's fourth failure mode - "a demo that ships the plumbing and reports
nothing" - was written as `"scBegin" not in text` against the whole file, and
every adopter carries the master block, which DEFINES `command scBegin`. The
substring is present by construction, so the branch was unreachable, and the
gate had shipped and passed for a day while claiming a check it could not make.

The mutations are applied to REAL adopters and restored in a finally block, so
what is tested is the gate as build-all.sh runs it, not a hand-built fixture
that resembles it. That distinction is the one root CLAUDE.md records under
"Component verified, system claimed".

USAGE
    python3 tools/test-demo-selfcheck-drift.py
"""

import importlib.util
import io
import os
import re
import sys
import contextlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load(name):
    spec = importlib.util.spec_from_file_location(
        name.replace("-", "_"), os.path.join(HERE, name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


DRIFT = load("check-demo-selfcheck-drift.py")
LISTS = load("check-demo-control-lists.py")

EC = os.path.join(ROOT, "enetxt", "examples", "enet-lan-chat.livecodescript")


def run(mod, argv=None):
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        try:
            rc = mod.main(argv) if argv is not None else mod.main()
        except TypeError:
            rc = mod.main([])
    return rc, buf.getvalue()


def with_mutation(path, mutate):
    """Apply mutate(text)->text, run both gates, restore. Returns (rc_drift, rc_lists)."""
    original = open(path, encoding="utf-8").read()
    try:
        open(path, "w", encoding="utf-8").write(mutate(original))
        rc_d, _ = run(DRIFT)
        rc_l, _ = run(LISTS, [])
        return rc_d, rc_l
    finally:
        open(path, "w", encoding="utf-8").write(original)


def _strip_asserts(text, handler):
    """Remove every scAssert/scSkip line from ONE handler's body."""
    m = re.search(r"^command\s+%s\b" % handler, text, re.M)
    end = re.search(r"^end\s+%s\b" % handler, text[m.end():], re.M)
    lo, hi = m.end(), m.end() + end.start()
    body = re.sub(r"^\s*sc(?:Assert|Skip)\b.*(?:\\\n.*)*$", "",
                  text[lo:hi], flags=re.M)
    return text[:lo] + body + text[hi:]


CASES = [
    # (label, mutate, expect drift fires, expect lists fires)
    ("the only real scBegin call is deleted",
     lambda t: t.replace('   scBegin "ecLog"\n', "", 1), True, False),
    ("scArmProbe is deleted (the probe never fires, the report never ends)",
     lambda t: t.replace("   scArmProbe\n", "", 1), True, False),
    # ANCHOR THE MUTATION TO THE HANDLER, not to the first match in the file.
    # The unanchored version matched scTickProbe's own scAssert - inside the
    # CARRIED BLOCK, which sits above ecScRun - and deleted everything down to
    # ecScRun's scArmProbe, taking the control-list constant with it. The gate
    # then fired for the wrong reason and the fixture recorded a pass it had not
    # earned. A mutation that does not do what its label says is worse than no
    # mutation, because the label is what the next reader trusts.
    ("every assertion in ecScRun is removed",
     lambda t: _strip_asserts(t, "ecScRun"), True, False),
    ("the run handler is no longer called from openStack",
     lambda t: t.replace("\n   ecScRun\n", "\n", 1), True, False),
    ("one line of the carried block is edited",
     lambda t: t.replace("command scAssert pName, pOk",
                         "command scAssert pName, pOk -- tweak", 1), True, False),
    ("a phantom control name is added to the list",
     lambda t: t.replace('constant kEcScControls = "',
                         'constant kEcScControls = "ecGhost,', 1), False, True),
    ("a real control name is dropped from the list",
     lambda t: t.replace("ecAddr,", "", 1), False, True),
    ("the assertion's count disagrees with the list",
     lambda t: re.sub(r'"all \d+ controls', '"all 999 controls', t, count=1),
     False, True),
]


def main():
    rc_d, out_d = run(DRIFT)
    rc_l, out_l = run(LISTS, [])
    if rc_d != 0 or rc_l != 0:
        print("test-demo-selfcheck-drift: the tree is not clean to begin with")
        print(out_d + out_l)
        return 1

    bad = 0
    for label, mutate, want_d, want_l in CASES:
        got_d, got_l = with_mutation(EC, mutate)
        ok_d = (got_d != 0) == want_d
        ok_l = (got_l != 0) == want_l
        if not (ok_d and ok_l):
            bad += 1
            print("  SURVIVED: %s" % label)
            if not ok_d:
                print("      drift gate: expected %s, got exit %d"
                      % ("fire" if want_d else "pass", got_d))
            if not ok_l:
                print("      list gate:  expected %s, got exit %d"
                      % ("fire" if want_l else "pass", got_l))
    if bad:
        print("test-demo-selfcheck-drift: %d mutation(s) SURVIVED" % bad)
        return 1

    # And the tree is restored, byte for byte.
    rc_d, _ = run(DRIFT)
    rc_l, _ = run(LISTS, [])
    if rc_d != 0 or rc_l != 0:
        print("test-demo-selfcheck-drift: the tree was NOT restored")
        return 1
    print("test-demo-selfcheck-drift: OK (%d mutation(s), every one caught, "
          "tree restored)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
