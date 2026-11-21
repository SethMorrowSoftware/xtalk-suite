#!/usr/bin/env python3
"""test-kit-reference.py - prove tools/build-kit-reference.py --check FIRES.

A gate that cannot fail prints OK over anything (the suite root's "fixture
before gate"). Each case takes the REAL Kit, breaks it one way in memory, and
requires the gate's check (or its page) to refuse the result with a problem
that names the break. The unbroken Kit must pass and must render the
committed page, so a gate that refuses everything fails here too. A case
whose `old` text is no longer in the Kit fails as "the fixture is stale",
never as a pass. Nothing is written to disk.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "b3x_kit_reference", os.path.join(HERE, "tools", "build-kit-reference.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)

STEP_BLOCK = ("/**\nSummary: One frame.\n\npGen: The loop's generation.\n\n"
              "Example:\nb3kStart\n\nReferences: b3kStart (handler)\n*/\n")
ORPHAN = "/**\nSummary: Nobody's.\n\nExample:\nb3kStart\n\nReferences: b3kStart (handler)\n*/\n"

# (label, old, new, text one of the problems must contain). `old` must occur
# in the Kit exactly once unless the label says "every".
CASES = [
    ("a handler left out of the cheat sheet",
     "--         b3kIsGliding(thing)\n", "--\n",
     "CHEAT SHEET does not name b3kIsGliding"),
    ("a handler named only inside a longer name (whole words)",
     "b3kCamZoom dist / ", "",
     "CHEAT SHEET does not name b3kCamZoom"),
    ("an invented name in the header",
     "--   on mouseUp\n", "--   on mouseUp\n--      b3kSpawnCrate 0, 4, 0\n",
     "names b3kSpawnCrate, which is neither"),
    ("a message the cheat sheet never names",
     'dispatch "b3kFell" to sFrameObj', 'dispatch "b3kFellOff" to sFrameObj',
     "does not name the message b3kFellOff"),
    ("a renamed message left in the cheat sheet",
     'dispatch "b3kFell" to sFrameObj', 'dispatch "b3kFellOff" to sFrameObj',
     "names b3kFell, which is neither"),
    ("a parameter the block documents and the handler lost",
     "command b3kSetup pGx, pGy, pGz\n", "command b3kSetup pGx, pGy\n",
     "b3kSetup: the doc block names parameters"),
    ("parameters out of order",
     "command b3kSetup pGx, pGy, pGz\n", "command b3kSetup pGy, pGx, pGz\n",
     "b3kSetup: the doc block names parameters"),
    ("a public handler with no doc block",
     "on b3kStep pGen\n", "command b3kExtra\nend b3kExtra\n\non b3kStep pGen\n",
     "b3kExtra (line"),
    ("a NOT_API name that grew a doc block",
     "on b3kStep pGen\n", STEP_BLOCK + "on b3kStep pGen\n",
     "b3kStep is in NOT_API but has a doc block"),
    ("a NOT_API name that is gone",
     "on b3kStep pGen\n", "on b3kStepFrame pGen\n",
     "NOT_API names b3kStep"),
    ("a doc block above a private handler",
     "private command b3kSceneLook\n", ORPHAN + "private command b3kSceneLook\n",
     "belongs to no public b3k handler"),
    ("a block with no Summary",
     "Summary: Make a world with gravity, ready for things.\n", "",
     "b3kSetup: its doc block has no Summary"),
    ("no library block",
     "Title: Box3Dxt Kit\n", "Name: Box3Dxt Kit\n",
     "no library block"),
    ("a scan that finds no handlers (every command and function renamed)",
     "every:\ncommand b3k", "\ncommand xb3k",
     "a blind scan passes anything"),
    ("a scan that finds no dispatched message",
     "every:dispatch \"b3k", "dispatch \"zz",
     "found no `dispatch \"b3k...\"`"),
]


def apply(text, old, new):
    if old.startswith("every:"):
        old = old[len("every:"):]
        if old not in text:
            return None
        if old.startswith("\n"):
            new = new if new.startswith("\n") else "\n" + new
        return text.replace(old, new)
    if text.count(old) != 1:
        return None
    return text.replace(old, new)


def main():
    kit = GATE.read(GATE.KIT)
    pages = {rel: GATE.read(rel) for rel in GATE.KNOWN_PAGES}
    failures = []

    base = GATE.check(kit, pages)
    if base:
        failures.append("the unbroken Kit is refused: " + "; ".join(base[:5]))
    committed = GATE.read(GATE.OUT)
    if GATE.render(kit) != committed:
        failures.append("the unbroken Kit does not render the committed "
                        "docs/kit-reference.md (run tools/build-kit-reference.py)")

    for label, old, new, want in CASES:
        broken = apply(kit, old, new)
        if broken is None:
            failures.append("%s: the fixture is stale (its text is not in the Kit "
                            "exactly once)" % label)
            continue
        problems = GATE.check(broken, pages)
        if not any(want in p for p in problems):
            failures.append("%s: not refused (wanted %r; got %s)"
                            % (label, want, problems[:3] or "no problems"))

    # check 4 on a hand-written page, not only the header
    bad = dict(pages)
    bad["docs/kit-guide.md"] = pages["docs/kit-guide.md"] + "\nCall b3kSpawnCrate.\n"
    if not any("docs/kit-guide.md names b3kSpawnCrate" in p for p in GATE.check(kit, bad)):
        failures.append("an invented name in docs/kit-guide.md: not refused")

    # the page follows the blocks: a changed Summary is a stale page
    changed = kit.replace("Summary: Make a world with gravity, ready for things.",
                          "Summary: Make a world.", 1)
    if changed == kit:
        failures.append("the stale-page case is stale (its Summary is not in the Kit)")
    elif GATE.render(changed) == committed:
        failures.append("a changed Summary rendered the committed page: --check is blind")

    if failures:
        print("test-kit-reference: FAIL")
        for f in failures:
            print("  " + f)
        return 1
    print("test-kit-reference: OK (%d breaks refused, the guide case and the stale "
          "page caught, the unbroken Kit passes)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
