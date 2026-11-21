#!/usr/bin/env python3
"""test-engine-sweep.py - the fixture for run-engine-selftest.py --check-sweep.

The sweep check holds tests/engine-selftest.lc's SWEEP to the binding: every
public handler of src/curl.lcb called there, in code, the count the sweep
reports equal to the binding's, and the sweep itself called by the test. A
check that cannot fail proves nothing (root CLAUDE.md, "Fixture before
gate"), so this runs it over the REAL files, which must pass, and over
copies of them broken one way at a time, each of which must fail and name
what broke.

    python3 tools/test-engine-sweep.py
"""

import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load_driver():
    spec = importlib.util.spec_from_file_location(
        "curlxt_run_engine_selftest", os.path.join(HERE, "run-engine-selftest.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    drv = load_driver()
    with open(drv.LCB, encoding="utf-8") as fh:
        lcb = fh.read()
    with open(drv.TEST, encoding="utf-8") as fh:
        test = fh.read()
    names = drv.public_handlers(lcb)
    failures = []
    broken = []

    def expect(label, lcb_text, test_text, needle):
        if needle is not None:
            broken.append(label)
        problems = drv.sweep_problems(lcb_text, test_text)
        if needle is None:
            if problems:
                failures.append("%s: expected no problem, got %s" % (label, problems))
        elif not any(needle in p for p in problems):
            failures.append("%s: expected a problem naming %r, got %s" % (label, needle, problems))

    def once(text, old, new, label):
        """text with old replaced by new, refusing a fixture that no longer
        matches the file (a mutation that changed nothing proves nothing)."""
        if text.count(old) != 1:
            failures.append("%s: the fixture expects %r exactly once in the file" % (label, old))
            return text
        return text.replace(old, new)

    if len(names) < 29:
        failures.append("only %d public handlers read from src/curl.lcb" % len(names))

    # The real files pass.
    expect("the real files", lcb, test, None)

    # A call removed from the sweep is named.
    expect("a call removed",
           lcb, once(test, "      get cuWsWait(0, 0)\n", "", "a call removed"), "cuWsWait")

    # A call turned into a comment is not a call.
    expect("a call commented out",
           lcb, once(test, "      get cuWsWait(0, 0)\n", "      -- get cuWsWait(0, 0)\n",
                     "a call commented out"), "cuWsWait")
    expect("a call in a block comment",
           lcb, once(test, "      get cuWsWait(0, 0)\n", "      /* get cuWsWait(0, 0) */\n",
                     "a call in a block comment"), "cuWsWait")

    # A name inside a literal is a label, not a call: the sweep's own
    # `put "cuWsWait" into tName` must not count once the call is gone.
    mutated = once(test, "      get cuWsWait(0, 0)\n", "", "a label left behind")
    if 'put "cuWsWait" into tName' not in drv.sweep_text(mutated):
        failures.append("a label left behind: the fixture expects the sweep's label line")
    expect("a label left behind", lcb, mutated, "cuWsWait")

    # A handler added to the binding without its sweep line is named, and
    # the count no longer matches.
    added = lcb.replace("public handler cuWsWait(",
                        "public handler cuWsFake(in pSocket as Integer) returns Integer\n"
                        "   return 0\nend handler\n\npublic handler cuWsWait(", 1)
    if added == lcb:
        failures.append("a handler added: the fixture could not add one")
    expect("a handler added", added, test, "cuWsFake")
    expect("a handler added (count)", added, test, "is not the binding's %d" % (len(names) + 1))

    # A count that is not the binding's.
    expect("a stale count", lcb,
           once(test, "put %d into tCount" % len(names), "put %d into tCount" % (len(names) - 1),
                "a stale count"), "the sweep's count")

    # No marker pair, a repeated one, or markers out of order.
    expect("no markers", lcb,
           once(test, drv.SWEEP_BEGIN, "-- SWEEP", "no markers"), "no single SWEEP marker pair")
    expect("a repeated pair", lcb, test + "\n" + drv.SWEEP_BEGIN + "\n" + drv.SWEEP_END + "\n",
           "no single SWEEP marker pair")
    swapped = test.replace(drv.SWEEP_BEGIN, "\0").replace(drv.SWEEP_END, drv.SWEEP_BEGIN)
    swapped = swapped.replace("\0", drv.SWEEP_END)
    expect("markers out of order", lcb, swapped, "no single SWEEP marker pair")

    # A sweep nobody calls, including one whose only call is a comment.
    expect("the sweep never called", lcb,
           once(test, "      sweepEveryHandler\n", "", "the sweep never called"),
           "calls sweepEveryHandler")
    expect("the sweep called in a comment", lcb,
           once(test, "      sweepEveryHandler\n", "      -- sweepEveryHandler\n",
                "the sweep called in a comment"),
           "calls sweepEveryHandler")

    expect("the sweep called only inside a block comment", lcb,
           once(test, "      sweepEveryHandler\n", "/*\n      sweepEveryHandler\n*/\n",
                "the sweep called only inside a block comment"),
           "calls sweepEveryHandler")
    # A call from inside the sweep itself is not the test calling it.
    inside = once(test, "      sweepEveryHandler\n", "", "the sweep calling itself")
    inside = once(inside, "      put %d into tCount\n" % len(names),
                  "      put %d into tCount\n      sweepEveryHandler\n" % len(names),
                  "the sweep calling itself")
    expect("the sweep calling itself", lcb, inside, "calls sweepEveryHandler")

    # strip_comments keeps a literal's "--" and every line break.
    sample = 'put "a--b" into tX -- gone\nput 1 into tY # gone\n/* gone\ngone */put 2 into tZ\n'
    stripped = drv.strip_comments(sample)
    if '"a--b"' not in stripped or "gone" in stripped or stripped.count("\n") != sample.count("\n"):
        failures.append("strip_comments: %r became %r" % (sample, stripped))

    if failures:
        for f in failures:
            print("test-engine-sweep: FAIL - " + f)
        return 1
    print("test-engine-sweep: OK (the real files pass; %d broken cases each fail by name)"
          % len(broken))
    return 0


if __name__ == "__main__":
    sys.exit(main())
