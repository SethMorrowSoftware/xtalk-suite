#!/usr/bin/env python3
"""test-harness-scaffold-drift.py - prove check-harness-scaffold-drift.py
FIRES on the suite core and on the generated paste, each for its own reason.

WHY THIS EXISTS
    The suite core, tests/suite-selftest.core.livecodescript, is a registered
    scaffold adopter; D-23 (2026-09-24) kept the block verbatim under the new
    board and gave the gate a module-level GENERATED_CARRIERS
    table that skips the GENERATED paste, tests/suite-selftest.livecodescript,
    by exact path (it had been an inline set the fixture could not reach). A
    skip is exactly the kind of line that reads correct and proves nothing: a
    gate that skipped too much, or by content, prints the same OK as one that
    works. A fixture that only runs the clean tree is a blind gate twice over
    (root CLAUDE.md, "Fixture before gate").

WHAT EACH CASE PROVES
    (a) clean      the tree passes, so every later failure is the mutation's.
    (b) by path    a byte copy of the paste planted beside it in tests/ is an
                   UNREGISTERED CARRIER, while the real paste still is not.
                   Same bytes, different verdict: the skip keys on the exact
                   path, never on content.
    (c) load-bearing  with GENERATED_CARRIERS emptied, the paste itself is
                   flagged - the table is what keeps it out (the paste has no
                   "GENERATED - do not edit" banner, on purpose: root
                   CLAUDE.md), and the only thing that does.
    (d) drift      one byte flipped INSIDE the core's carried scaffold is
                   caught and named against the core - the core, the one
                   copy of the block a maintainer of the paste can edit, is
                   really compared.

HOW IT RUNS, and why that way
    As test-ui-kit-drift.py: real files mutated and restored BYTE FOR BYTE in a
    finally, module state monkeypatched and restored in a finally, the gate's
    main() called with no arguments exactly as tools/build-all.sh runs
    `python3 tools/check-harness-scaffold-drift.py`. Each case must fail (or
    pass) AND print its own sentence, and every needle must exist EXACTLY ONCE,
    inside the block, before it is mutated.

USAGE
    python3 tools/test-harness-scaffold-drift.py
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


GATE = load("check-harness-scaffold-drift.py")

CORE = os.path.join("tests", "suite-selftest.core.livecodescript")
PASTE = os.path.join("tests", "suite-selftest.livecodescript")
PLANT = os.path.join("tests", "zz-scaffold-carrier-copy.livecodescript")

# One byte, inside the core's carried scaffold: stMonoFont's fallback face.
# The kit's uiMonoFont spells the same face, so the needle carries the
# `end stMonoFont` line to be unique - and to stay in THIS block.
FLIP_FROM = '   return "DejaVu Sans Mono"\nend stMonoFont\n'
FLIP_TO = '   return "DejaVu Sans Mona"\nend stMonoFont\n'


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
    """(lo, hi) character offsets of the ONE scaffold block in text."""
    lo, hi = text.count(GATE.BEGIN), text.count(GATE.END)
    if lo != 1 or hi != 1:
        raise Refused("%s carries %d BEGIN / %d END scaffold markers "
                      "(want 1/1)" % (rel, lo, hi))
    return text.index(GATE.BEGIN), text.index(GATE.END)


@contextlib.contextmanager
def edited(rel, needle, replacement):
    """Replace needle (exactly once, inside the scaffold) in a REAL file."""
    original = _bytes(rel)
    text = original.decode("utf-8")
    n = text.count(needle)
    if n != 1:
        raise Refused("%s: needle found %d times (want exactly 1): %r"
                      % (rel, n, needle))
    lo, hi = _span_of(text, rel)
    if not lo < text.index(needle) < hi:
        raise Refused("%s: needle is outside the carried scaffold" % rel)
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


def case_planted_copy():
    paste = _bytes(PASTE)
    # the copy must be a carrier (one scaffold block, the core's), or
    # "flagged" would prove nothing about the skip
    _span_of(paste.decode("utf-8"), PASTE)
    return planted(PLANT, paste)


def case_no_generated_carriers():
    if list(GATE.GENERATED_CARRIERS) != [PASTE]:
        raise Refused("GENERATED_CARRIERS is %r, want exactly the paste"
                      % sorted(GATE.GENERATED_CARRIERS))
    _span_of(_bytes(PASTE).decode("utf-8"), PASTE)
    return patched("GENERATED_CARRIERS", {})


def case_drift():
    return edited(CORE, FLIP_FROM, FLIP_TO)


# (label, context factory, gate must fail, sentences it must print,
#  sentences it must NOT print). Sentences are regexes over the gate's output.
CASES = [
    ("(a) the clean tree passes",
     case_clean, False,
     [r"check-harness-scaffold-drift: OK \("], []),
    ("(b) a byte copy of the paste elsewhere in tests/ is an unregistered "
     "carrier; the real paste is still skipped (by path, not content)",
     case_planted_copy, True,
     [re.escape(PLANT) + r" carries the scaffold but is not in ADOPTERS"],
     [re.escape(PASTE) + r" carries the scaffold"]),
    ("(c) GENERATED_CARRIERS emptied: the paste itself is flagged "
     "(the skip is load-bearing)",
     case_no_generated_carriers, True,
     [re.escape(PASTE) + r" carries the scaffold but is not in ADOPTERS"],
     []),
    ("(d) one byte flipped inside the core's scaffold copy is drift, named",
     case_drift, True,
     [re.escape(CORE) + r": scaffold block DIFFERS from the master \(first "
      r"divergence at block line \d+\)"], []),
]


def main():
    before = {rel: _bytes(rel) for rel in (CORE, PASTE)}
    if os.path.exists(os.path.join(ROOT, PLANT)):
        print("test-harness-scaffold-drift: %s exists before the run - "
              "remove it" % PLANT)
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

    # restored BYTE FOR BYTE and the plant gone - checked, not assumed
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
        print("test-harness-scaffold-drift: FAILED (%d problem(s))" % bad)
        return 1
    print("test-harness-scaffold-drift: OK (%d case(s), each fails or passes "
          "for its own reason; tree restored byte for byte)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
