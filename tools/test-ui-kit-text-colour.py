#!/usr/bin/env python3
"""test-ui-kit-text-colour.py - prove check-ui-kit-text-colour.py FIRES on
each of its rules, against the real kit master.

WHY THIS EXISTS
    A gate that reads statements prints OK just as readily when its reader
    is blind (root CLAUDE.md, "Fixture before gate: a blind gate still
    prints OK"). Each case below mutates the REAL master's carried block in
    memory, as the gate reads it, and requires the gate's verdict AND its
    sentence, so a rule that fires for the wrong reason is a mutation that
    survived. The kit before 2026-11-21 is case (b) to (d): its uiInput,
    uiArea and uiCheckbox gave words on the kit's colours no colour.

WHAT EACH CASE PROVES
    (a) clean        the master passes, so every later failure is the case's,
                     and main() passes on the file as build-all.sh runs it.
    (b)-(d) the fault  uiInput's, uiArea's and uiCheckbox's text colour
                     taken out: each builder is named, by the rule it breaks.
    (e) comment      the line turned into a comment is not a text colour:
                     comments are cut before statements are read.
    (f) spelling     `fld` for `field` is the same control.
    (g) new builder  a builder that colours a field's background and not its
                     words is refused; one that colours both is not.
    (h) card         a card's background outside EXEMPT is refused.
    (i) load-bearing EXEMPT emptied, the page ground is refused; NO_TEXT_COLOUR
                     emptied, uiButton and uiContextMenu are refused.
    (j) stale        an entry of either table that matches nothing is refused.
    (k) floor        a block that reads as almost no handlers fails main().

USAGE
    python3 tools/test-ui-kit-text-colour.py
"""

import contextlib
import importlib.util
import io
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def load(name):
    spec = importlib.util.spec_from_file_location(
        name.replace("-", "_").replace(".py", ""), os.path.join(HERE, name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GATE = load("check-ui-kit-text-colour.py")

FAILURES = []


def check(label, ok, detail=""):
    print("%s  %s%s" % ("ok  " if ok else "FAIL", label, (": " + detail) if detail and not ok else ""))
    if not ok:
        FAILURES.append(label)


def once(block, needle):
    """The needle must be in the block exactly once, or the case would test
    something else than it says."""
    count = block.count(needle)
    if count != 1:
        raise SystemExit("test-ui-kit-text-colour: needle found %d times, not once: %r" % (count, needle))


def swap(block, needle, replacement):
    once(block, needle)
    return block.replace(needle, replacement)


def named(problems, *words):
    """Whether one problem has all the words."""
    return any(all(w in p for w in words) for p in problems)


def run_main():
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        status = GATE.main()
    return status, out.getvalue()


def main():
    block, err = GATE.DRIFT.extract(GATE.DRIFT.MASTER)
    if err:
        raise SystemExit("test-ui-kit-text-colour: %s" % err)

    # (a)
    check("(a) the master has no breach", GATE.findings(block) == [], "; ".join(GATE.findings(block)))
    status, out = run_main()
    check("(a) main() passes on the master", status == 0 and "OK" in out, out)

    # each builder's text colour, with the lines around it to make it unique
    input_back = "   set the backgroundColor of field pName to kUiCard\n   -- 4-item"
    input_fore = "   set the foregroundColor of field pName to kUiInk\n" + input_back
    area_fore = ("   -- and its words, for uiInput's reason: never the theme's\n"
                 "   set the foregroundColor of field pName to kUiInk\n")
    check_fore = "   set the foregroundColor of button pName to kUiInk\nend uiCheckbox"

    # (b)
    got = GATE.findings(swap(block, input_fore, input_back))
    check("(b) uiInput without a text colour: rule 1", named(got, "uiInput", "backgroundColor of field pName"), got)
    check("(b) uiInput without a text colour: rule 2", named(got, "uiInput", "creates field pName"), got)
    check("(b) and nothing else", all("uiInput" in p for p in got), got)

    # (c)
    got = GATE.findings(swap(block, area_fore, ""))
    check("(c) uiArea without a text colour", named(got, "uiArea", "backgroundColor of field pName")
          and named(got, "uiArea", "creates field pName"), got)

    # (d)
    got = GATE.findings(swap(block, check_fore, "end uiCheckbox"))
    check("(d) uiCheckbox without a text colour", named(got, "uiCheckbox", "check box or a radio button"), got)

    # (e)
    got = GATE.findings(swap(block, input_fore, "   -- set the foregroundColor of field pName to kUiInk\n" + input_back))
    check("(e) a commented-out text colour does not count", named(got, "uiInput", "backgroundColor"), got)

    # (f)
    spelt = swap(block, input_fore, "   set the foregroundColor of fld pName to kUiInk\n" + input_back)
    check("(f) fld is field", GATE.findings(spelt) == [], GATE.findings(spelt))

    # (g)
    end = "-- ==== SUITE UI KIT v2 END ===="
    bad = ("command uiNote pName\n"
           "   set the backgroundColor of field pName to kUiCodeBg\n"
           "end uiNote\n\n")
    good = ("command uiNote pName\n"
            "   set the backgroundColor of field pName to kUiCodeBg\n"
            "   set the foregroundColor of field pName to kUiInk\n"
            "end uiNote\n\n")
    got = GATE.findings(swap(block, end, bad + end))
    check("(g) a new builder's field without a text colour", named(got, "uiNote", "field pName"), got)
    check("(g) and with one it passes", GATE.findings(swap(block, end, good + end)) == [])

    # (h)
    card = ("command uiPage\n"
            "   set the backgroundColor of this card to kUiCodeBg\n"
            "end uiPage\n\n")
    got = GATE.findings(swap(block, end, card + end))
    check("(h) a card's background outside EXEMPT", named(got, "uiPage", "this card", "EXEMPT"), got)

    # (i)
    got = GATE.findings(block, exempt={})
    check("(i) EXEMPT is what lets the page ground pass", named(got, "uiChrome", "this card"), got)
    got = GATE.findings(block, no_text_colour={})
    check("(i) NO_TEXT_COLOUR is what lets the push button pass", named(got, "uiButton", "NO_TEXT_COLOUR"), got)
    check("(i) and the popup menu", named(got, "uiContextMenu", "NO_TEXT_COLOUR"), got)

    # (j)
    stale = dict(GATE.EXEMPT)
    stale[("uiGone", "this card")] = "a reason for nothing"
    got = GATE.findings(block, exempt=stale)
    check("(j) a stale EXEMPT entry", named(got, "EXEMPT entry", "uiGone"), got)
    stale = dict(GATE.NO_TEXT_COLOUR)
    stale["uiLabel"] = "uiLabel colours its field: this entry is stale"
    got = GATE.findings(block, no_text_colour=stale)
    check("(j) a stale NO_TEXT_COLOUR entry", named(got, "NO_TEXT_COLOUR entry", "uiLabel"), got)

    # (k)
    real = GATE.DRIFT.extract
    try:
        GATE.DRIFT.extract = lambda path: ("command uiOnly\nend uiOnly\n", None)
        status, out = run_main()
    finally:
        GATE.DRIFT.extract = real
    check("(k) a block of almost no handlers fails", status == 1 and "only 1 handlers" in out, out)

    if FAILURES:
        print("test-ui-kit-text-colour: FAILED (%d)" % len(FAILURES))
        return 1
    print("test-ui-kit-text-colour: OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
