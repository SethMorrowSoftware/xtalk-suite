#!/usr/bin/env python3
"""test-ui-kit-drift.py - prove check-ui-kit-drift.py FIRES on the suite core
and on the generated paste, each for its own reason.

WHY THIS EXISTS
    D-23 (2026-09-24) moved the suite paste's hand-written half,
    tests/suite-selftest.core.livecodescript, from the gate's EXEMPT table to
    its ADOPTERS, and gave the gate a module-level GENERATED_CARRIERS table
    that skips the GENERATED paste, tests/suite-selftest.livecodescript, by
    exact path. Every one of those is a claim the gate prints OK over whether
    or not it holds: an adopter nobody drifts, a skip nothing exercises and an
    exemption nobody re-adds all look identical to a gate that works. A
    fixture that only runs the clean tree proves nothing (root CLAUDE.md,
    "Fixture before gate: a blind gate still prints OK").

WHAT EACH CASE PROVES
    (a) clean      the tree passes, so every later failure is the mutation's.
    (b) drift      one byte flipped INSIDE the core's carried kit is caught
                   and named against the core - the core really is compared.
    (c) by path    a byte copy of the paste planted beside it in tests/ is an
                   UNREGISTERED CARRIER, while the real paste still is not.
                   Same bytes, different verdict: the skip keys on the exact
                   path, never on content, so no stray copy can hide behind it.
    (d) load-bearing  with GENERATED_CARRIERS emptied, the paste itself is
                   flagged - the table is what keeps it out, not a leftover
                   hard-coded path (the gate had one until D-23) or the
                   "GENERATED - do not edit" banner (the paste has none, on
                   purpose: root CLAUDE.md).
    (e) both lists the core re-added to EXEMPT is refused as an exemption of
                   an adopter, so the pre-D-23 entry cannot quietly return.
    (f) registered the core dropped from ADOPTERS is flagged as a carrier
                   nobody registered - it carries the marker, so adoption
                   cannot lapse unnoticed.

HOW IT RUNS, and why that way
    Real files are mutated and restored BYTE FOR BYTE in a finally (read and
    written as bytes, so no newline translation can leave a diff behind);
    module state is monkeypatched and restored in a finally; the gate's main()
    is called with no arguments, exactly as tools/build-all.sh runs
    `python3 tools/check-ui-kit-drift.py`, re-reading the tree every time. The
    gate is exec-loaded by path, the pattern of test-demo-selfcheck-drift.py.
    Each case must fail (or pass) AND print its own sentence: a gate that fires
    for the wrong reason is a mutation that survived. Every needle is asserted
    to exist EXACTLY ONCE before it is mutated - a needle that matched twice,
    or somewhere else, is how test-demo-selfcheck-drift.py once recorded a pass
    it had not earned.

USAGE
    python3 tools/test-ui-kit-drift.py
"""

import contextlib
import importlib.util
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def load(name):
    spec = importlib.util.spec_from_file_location(
        name.replace("-", "_").replace(".py", ""), os.path.join(HERE, name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GATE = load("check-ui-kit-drift.py")

CORE = os.path.join("tests", "suite-selftest.core.livecodescript")
PASTE = os.path.join("tests", "suite-selftest.livecodescript")
# the planted copy's name sorts last in tests/ and names what it is, so a
# crashed run that somehow left it behind is obvious in `git status`
PLANT = os.path.join("tests", "zz-kit-carrier-copy.livecodescript")

# One byte, inside the core's carried kit: the kit's uiMonoFont fallback face.
# The same face is also spelled in the scaffold's stMonoFont, which is why the
# needle carries the `end uiMonoFont` line - bare, it would match twice, and
# the scaffold half is not this gate's to find.
FLIP_FROM = '   return "DejaVu Sans Mono"\nend uiMonoFont\n'
FLIP_TO = '   return "DejaVu Sans Mona"\nend uiMonoFont\n'


class Refused(Exception):
    """A precondition failed: the case cannot prove what its label says."""


def run():
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = GATE.main()
    return rc, buf.getvalue()


def _bytes(rel):
    with open(os.path.join(ROOT, rel), "rb") as fh:
        return fh.read()


def _write(rel, data):
    with open(os.path.join(ROOT, rel), "wb") as fh:
        fh.write(data)


def _span_of(text, rel):
    """(lo, hi) character offsets of the ONE kit block in text."""
    lo, hi = text.count(GATE.BEGIN), text.count(GATE.END)
    if lo != 1 or hi != 1:
        raise Refused("%s carries %d BEGIN / %d END kit markers (want 1/1)"
                      % (rel, lo, hi))
    return text.index(GATE.BEGIN), text.index(GATE.END)


@contextlib.contextmanager
def edited(rel, needle, replacement):
    """Replace needle (exactly once, inside the kit block) in a REAL file."""
    original = _bytes(rel)
    text = original.decode("utf-8")
    n = text.count(needle)
    if n != 1:
        raise Refused("%s: needle found %d times (want exactly 1): %r"
                      % (rel, n, needle))
    lo, hi = _span_of(text, rel)
    if not lo < text.index(needle) < hi:
        raise Refused("%s: needle is outside the carried kit block" % rel)
    try:
        _write(rel, text.replace(needle, replacement, 1).encode("utf-8"))
        yield
    finally:
        _write(rel, original)


@contextlib.contextmanager
def planted(rel, data):
    """A file that exists only for the case; never overwrites a real one."""
    if os.path.exists(os.path.join(ROOT, rel)):
        raise Refused("%s already exists - refusing to overwrite a file this "
                      "fixture did not plant" % rel)
    try:
        _write(rel, data)
        yield
    finally:
        if os.path.exists(os.path.join(ROOT, rel)):
            os.remove(os.path.join(ROOT, rel))


@contextlib.contextmanager
def patched(name, value):
    """Monkeypatch one module-level table of the gate, restored after."""
    old = getattr(GATE, name)
    setattr(GATE, name, value)
    try:
        yield
    finally:
        setattr(GATE, name, old)


def case_clean():
    return contextlib.nullcontext()


def case_drift():
    return edited(CORE, FLIP_FROM, FLIP_TO)


def case_planted_copy():
    paste = _bytes(PASTE)
    # the copy must be a carrier, or "flagged" would prove nothing about the
    # skip: exactly one kit block in the paste, as the generator writes it
    _span_of(paste.decode("utf-8"), PASTE)
    return planted(PLANT, paste)


def case_no_generated_carriers():
    if list(GATE.GENERATED_CARRIERS) != [PASTE]:
        raise Refused("GENERATED_CARRIERS is %r, want exactly the paste"
                      % sorted(GATE.GENERATED_CARRIERS))
    _span_of(_bytes(PASTE).decode("utf-8"), PASTE)
    return patched("GENERATED_CARRIERS", {})


def case_core_exempt():
    if CORE in GATE.EXEMPT:
        raise Refused("%s is already in EXEMPT" % CORE)
    widened = dict(GATE.EXEMPT)
    widened[CORE] = "re-added by test-ui-kit-drift.py case (e)"
    return patched("EXEMPT", widened)


def case_core_unregistered():
    if GATE.ADOPTERS.count(CORE) != 1:
        raise Refused("%s is in ADOPTERS %d times (want exactly 1)"
                      % (CORE, GATE.ADOPTERS.count(CORE)))
    return patched("ADOPTERS", [a for a in GATE.ADOPTERS if a != CORE])


# (label, context factory, gate must fail, sentences it must print,
#  sentences it must NOT print). Sentences are regexes over the gate's output.
CASES = [
    ("(a) the clean tree passes",
     case_clean, False,
     [r"check-ui-kit-drift: OK \("], []),
    ("(b) one byte flipped inside the core's kit copy is drift, named",
     case_drift, True,
     [re.escape(CORE) + r": kit block DIFFERS from the master \(first "
      r"divergence at block line \d+\)"], []),
    ("(c) a byte copy of the paste elsewhere in tests/ is an unregistered "
     "carrier; the real paste is still skipped (by path, not content)",
     case_planted_copy, True,
     [re.escape(PLANT) + r" carries the kit but is not in ADOPTERS"],
     [re.escape(PASTE) + r" carries the kit"]),
    ("(d) GENERATED_CARRIERS emptied: the paste itself is flagged "
     "(the skip is load-bearing)",
     case_no_generated_carriers, True,
     [re.escape(PASTE) + r" carries the kit but is not in ADOPTERS"], []),
    ("(e) the core re-added to EXEMPT is refused as an exempted adopter",
     case_core_exempt, True,
     [r"EXEMPT entry " + re.escape(CORE) + r" is also in ADOPTERS - drop "
      r"the exemption"], []),
    ("(f) the core dropped from ADOPTERS is flagged as an unregistered "
     "carrier",
     case_core_unregistered, True,
     [re.escape(CORE) + r" carries the kit but is not in ADOPTERS"], []),
]


def main():
    before = {rel: _bytes(rel) for rel in (CORE, PASTE)}
    if os.path.exists(os.path.join(ROOT, PLANT)):
        print("test-ui-kit-drift: %s exists before the run - remove it" % PLANT)
        return 1

    bad = 0
    for label, factory, want_fail, say, deny in CASES:
        try:
            with factory():
                rc, out = run()
        except Refused as exc:
            bad += 1
            print("  CANNOT PROVE: %s\n      %s" % (label, exc))
            continue
        why = []
        if (rc != 0) != want_fail:
            why.append("expected the gate to %s, got exit %d"
                       % ("fail" if want_fail else "pass", rc))
        for pat in say:
            if not re.search(pat, out):
                why.append("missing sentence /%s/" % pat)
        for pat in deny:
            if re.search(pat, out):
                why.append("printed a sentence it must not: /%s/" % pat)
        if why:
            bad += 1
            print("  SURVIVED: %s" % label)
            for w in why:
                print("      %s" % w)
            print("      gate output:\n" + "\n".join(
                "        " + l for l in out.rstrip("\n").split("\n")))

    # The tree is restored BYTE FOR BYTE and the plant is gone - checked, not
    # assumed: a fixture that leaves a mutated core behind turns the next
    # gate's red into this one's fault.
    for rel, data in before.items():
        if _bytes(rel) != data:
            bad += 1
            print("  NOT RESTORED: %s differs from before the run" % rel)
    if os.path.exists(os.path.join(ROOT, PLANT)):
        bad += 1
        print("  NOT RESTORED: %s was left behind" % PLANT)
    rc, out = run()
    if rc != 0:
        bad += 1
        print("  NOT RESTORED: the gate fails after the run:\n" + out)

    if bad:
        print("test-ui-kit-drift: FAILED (%d problem(s))" % bad)
        return 1
    print("test-ui-kit-drift: OK (%d case(s), each fails or passes for its own "
          "reason; tree restored byte for byte)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
