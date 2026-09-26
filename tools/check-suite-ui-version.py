#!/usr/bin/env python3
"""check-suite-ui-version.py - the suite board's build stamp must FOLLOW its
build.

WHY THIS EXISTS
---------------
The suite paste builds its board once and STAMPS the stack: suBuild in
tests/suite-selftest.core.livecodescript rebuilds only when the stack's
uSuUiVersion differs from the constant kSuUiVersion ("if the uSuUiVersion of
this stack is kSuUiVersion then" repaint and exit). That is what lets a
reopened stack skip the build, and it is also how a layout change is lost: a
change to suBuildAll, or to any kit handler it calls, that forgets to bump
the constant leaves every stack an older paste already built showing the
window the LAST build drew, while a fresh stack shows the new one. The
constant read "suite-board-1" from D-23 (2026-09-24) and was bumped by hand;
work plan suite-wide #17 (review, 2026-09-25) named it as the hand-copied
number root CLAUDE.md warns about, before anything had gone wrong.

coinxt met the same shape first and paid for it: every wallet control added
between 2026-09-02 and 2026-09-04 failed to appear in any stack that already
existed, because kWaUiVersion never moved. coinxt/tools/check-wallet-ui-version.py
holds that constant to a hash of its waBuild* handlers, and this is the same
gate with the same --fix, for the board.

WHAT IS HASHED, AND WHY THIS SET
--------------------------------
Everything the build READS, found from the core rather than listed by hand:

  * the handlers suBuildAll REACHES: the closure from suBuildAll over every
    name of a handler the core defines that appears in a reached handler's
    code (comments stripped by the generator's own scanner, string literals
    KEPT, so a `send "x"` or `do "x"` counts). It over-approximates on
    purpose: a name in a branch that never runs still counts, which can only
    make the stamp change when it need not (a rebuild, which is cheap),
    never stay put when it must not. It reaches suBuildReset and the carried
    UI kit's builders, so a kit change re-carried into the core moves the
    stamp too;
  * every column-0 constant those handlers name (kSuKeys, kSuNames, the row
    geometry, kStWidth/kStHeight/kStTitle, the kit's colours), because a
    new member in kSuKeys is a new row, and the builder text alone would not
    change.

Each handler is hashed as its CODE: the comment-free lines with trailing
space dropped and blank lines skipped, in file order. A comment cannot change
what the window holds, and hashing prose would make every comment edit in
the carried kit a stamp change - which teaches people to run --fix without
reading. (The wallet gate hashes whole handler text; the difference is
deliberate.) kSuUiVersion itself is refused inside the closure: a stamp that
hashes itself has no fixed point.

The stamp is "suite-board-" plus the first twelve hex digits of SHA-256. The
prefix is not decoration: suBuild compares stamps with `is`, and the engine
compares two number-like texts as NUMBERS (engine note 2.11), so a bare hex
digest made of digits could equal a different one. The prefix makes both
sides text, always; this gate refuses a stamp that does not carry it.

Usage:
  python3 tools/check-suite-ui-version.py            # the gate
  python3 tools/check-suite-ui-version.py --fix      # write the stamp
  python3 tools/check-suite-ui-version.py --core P   # another copy (fixtures)
After --fix, regenerate the paste: python3 tools/build-suite-selftest.py.
"""

import hashlib
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CORE = os.path.join(ROOT, "tests", "suite-selftest.core.livecodescript")
BUILD_ROOT = "suBuildAll"
STAMP = "kSuUiVersion"
PREFIX = "suite-board-"
# The closure must reach these, or it is not the board's builder any more
# and a green here would be checking nothing.
FLOOR = ("suBuildAll", "suBuildReset", "uiChrome", "uiButton", "uiLabel")
# The stamp's own line may carry a trailing comment, like any other
# declaration in the core: the first cut refused one as "found 0" (review,
# 2026-09-25). --fix rewrites the quoted value only.
CONST_LINE = re.compile(r'^constant\s+' + STAMP + r'\s*=\s*"([^"]*)"'
                        r'[ \t]*(?:(?:--|#|//)[^\n]*)?$', re.M)


def _load_generator():
    """The generator's comment scanner, so this gate and the tool that writes
    the paste cannot disagree about what is code (check-suite-selftest.py
    loads it the same way)."""
    path = os.path.join(HERE, "build-suite-selftest.py")
    spec = importlib.util.spec_from_file_location("build_suite_selftest", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def handlers(view):
    """{lower name: (spelling, first, last)} of every column-0 handler in a
    comment-free view (0-based, inclusive); refuses a duplicate or an
    unterminated one."""
    opener = re.compile(r'^(?:private\s+)?(?:command|function|on)\s+(\w+)', re.I)
    out, i = {}, 0
    while i < len(view):
        m = opener.match(view[i])
        if not m:
            i += 1
            continue
        name = m.group(1)
        end = re.compile(r'^\s*end\s+' + re.escape(name) + r'\s*$', re.I)
        j = i + 1
        while j < len(view) and not end.match(view[j]):
            j += 1
        if j >= len(view):
            raise ValueError("handler %s never ends" % name)
        if name.lower() in out:
            raise ValueError("handler %s is defined twice" % name)
        out[name.lower()] = (name, i, j)
        i = j + 1
    return out


def constants(view, gen):
    """{lower name: (spelling, its comment-free declaration line, its index)}
    for every name a column-0 `constant` line declares, split by the
    generator's own declaration_names (a comma inside a string literal is
    data, not a second name: kSuKeys is one constant).

    The INDEX is carried, not looked up again: the first cut ordered the
    constants with view.index(the rstripped line), and a line with anything
    after its value - a trailing `-- comment`, which the view keeps as
    trailing space, or plain trailing space - is not in the view in that
    form. The gate then died on "'constant kSuRowStep = 34' is not in list",
    --fix with it, over an edit its own rule says changes nothing (review,
    2026-09-25)."""
    out = {}
    for i, ln in enumerate(view):
        if re.match(r'^constant\s', ln, re.I):
            for name in gen.declaration_names(ln[len("constant"):]):
                out[name.lower()] = (name, ln.rstrip(), i)
    return out


def fingerprint(text, gen):
    """(stamp, reached handler spellings, constant names) for a core's
    text; raises ValueError on a core this gate cannot read honestly."""
    view = gen.strip_comments(text).split("\n")
    table = handlers(view)
    if BUILD_ROOT.lower() not in table:
        raise ValueError("no %s handler: this is not the board's core" % BUILD_ROOT)
    consts = constants(view, gen)
    reach, frontier = {BUILD_ROOT.lower()}, [BUILD_ROOT.lower()]
    named = set()
    while frontier:
        _, a, b = table[frontier.pop()]
        for ln in view[a + 1:b]:
            for tok in re.findall(r'\b(\w+)\b', ln):
                low = tok.lower()
                if low in table and low not in reach:
                    reach.add(low)
                    frontier.append(low)
                elif low in consts:
                    named.add(low)
    if STAMP.lower() in named:
        raise ValueError("%s is named inside the build it stamps; a stamp that "
                         "hashes itself has no fixed point" % STAMP)
    missing = [n for n in FLOOR if n.lower() not in reach]
    if missing:
        raise ValueError("the closure from %s no longer reaches %s, so it is "
                         "not the board's builder any more and a match here "
                         "would check nothing" % (BUILD_ROOT, ", ".join(missing)))
    parts = []
    for low in sorted(reach, key=lambda n: table[n][1]):
        spelling, a, b = table[low]
        code = [ln.rstrip() for ln in view[a:b + 1] if ln.strip()]
        parts.append("\n".join(code))
    for low in sorted(named, key=lambda n: (consts[n][2], n)):
        parts.append(consts[low][1])
    digest = hashlib.sha256("\n\n".join(parts).encode("utf-8")).hexdigest()[:12]
    spellings = [table[n][0] for n in sorted(reach, key=lambda n: table[n][1])]
    return PREFIX + digest, spellings, sorted(consts[n][0] for n in named)


def main(argv):
    fix = "--fix" in argv
    path = CORE
    if "--core" in argv:
        k = argv.index("--core")
        if k + 1 >= len(argv):
            print("usage: check-suite-ui-version.py [--fix] [--core PATH]")
            return 2
        path = argv[k + 1]
    rel = os.path.relpath(os.path.abspath(path), ROOT)
    if not os.path.isfile(path):
        print("check-suite-ui-version: FAILED - %s is missing" % rel)
        return 1
    text = open(path, encoding="utf-8").read()
    gen = _load_generator()
    try:
        want, reached, named = fingerprint(text, gen)
    except (ValueError, SystemExit) as exc:
        print("check-suite-ui-version: FAILED - %s: %s" % (rel, exc))
        return 1
    hits = list(CONST_LINE.finditer(text))
    if len(hits) != 1:
        print("check-suite-ui-version: FAILED - %s must declare `constant %s = "
              "\"...\"` exactly once at column 0; found %d"
              % (rel, STAMP, len(hits)))
        return 1
    m = hits[0]
    have = m.group(1)
    what = "%d handler(s) and %d constant(s) reached from %s" % (
        len(reached), len(named), BUILD_ROOT)
    if have == want:
        print("check-suite-ui-version: OK (%s %s follows the %s)"
              % (STAMP, want, what))
        return 0
    if fix:
        text = text[:m.start(1)] + want + text[m.end(1):]
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(text)
        print("check-suite-ui-version: wrote %s %s (was %s) over the %s; now "
              "regenerate the paste: python3 tools/build-suite-selftest.py"
              % (STAMP, want, have, what))
        return 0
    why = ("it does not open with %r, and suBuild compares it with `is`, "
           "which compares number-like text as numbers (engine note 2.11)"
           % PREFIX if not have.startswith(PREFIX) else
           "a stack an older paste built under the old value would keep "
           "that build's window, never gaining what the builder now makes")
    print("check-suite-ui-version: FAILED - %s in %s is %s, but the %s "
          "fingerprint to %s: %s. Run with --fix, then python3 "
          "tools/build-suite-selftest.py."
          % (STAMP, rel, have, what, want, why))
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
