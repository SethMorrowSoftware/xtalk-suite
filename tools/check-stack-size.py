#!/usr/bin/env python3
"""check-stack-size.py - every sample stack fits a 720p display.

The suite's demos and pasteable harnesses are run on real, often small,
machines - the two-machine passes happen on whatever hardware is in the
room. A 1280x720 display keeps roughly 640px of height once the OS
taskbar (~48) and the window title bar (~32) are gone, and a shade under
1280 of width once borders are counted. So the family budget is:

    width  <= 1200
    height <= 640

and this gate holds every stack's WINDOW to it. The closing-pass stack
shipped at 780x1010 - its Tor section sat BELOW the bottom edge of exactly
the screens it was meant to close legs on - which is how rules earn gates
here (the checker-drift lesson: a rule without a gate rots).

What IS checked: the stack's own size, in the four spellings the family
uses -

    set the width of this stack to 820
    set the height of this stack to kWinHeight     (same-file constant)
    uiChrome "Title", 1200, 640                    (the suite UI kit)
    set the rect of this stack to kStackRect       (a "L,T,R,B" constant;
                                                    holde-em's spelling,
                                                    learned in the fold)

What is NOT checked, and never has been: the CONTROLS inside that window.
This gate reads ONE number per axis per stack and stops. It cannot tell
whether a field, a button or a card slot sits inside the window it just
measured, so a control pushed past the bottom edge passes here in silence
- the same shape of failure as the 780x1010 stack, one level down. Nothing
about a green run here says a demo's chrome fits, only that its window
does.

Closing that for the one stack whose layout is dense enough to need it:
holde-em/tools/check-table-layout.py (2026-08-16) re-derives every control
rect from holde-em's own builders, bounds-checks each against the stack
rect this gate reads, and proves the must-not-overlap set pairwise
disjoint against a written exemption list. It runs in the same
`build-all.sh --gates` set. Neither gate subsumes the other: that one
takes the stack rect as its frame and says nothing about the budget, this
one owns the budget and says nothing about what is inside the frame.

A size taken from a custom property (torrent-client restores the user's
chosen height) is the USER's choice, not a shipped default, and is out of
scope. A file with no stack sizing contributes nothing.
"""

import glob
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

MAX_WIDTH = 1200
MAX_HEIGHT = 640

SET_RE = re.compile(
    r'^\s*set\s+the\s+(width|height)\s+of\s+this\s+stack\s+to\s+'
    r'([0-9]+|k[A-Za-z0-9_]+)\s*$')
RECT_RE = re.compile(
    r'^\s*set\s+the\s+rect\s+of\s+this\s+stack\s+to\s+'
    r'("[0-9, ]+"|k[A-Za-z0-9_]+)\s*$')
# a rect constant is a quoted "L,T,R,B" quad, not a bare integer
CONST_STR_PAIR_RE = re.compile(r'(k[A-Za-z0-9_]+)\s*=\s*"([0-9, ]+)"')
# WIDENED 2026-08-20. The old pattern required a LITERAL quoted title and two
# integer literals, so nocloud's
#     uiChrome ("No Cloud Quick Share " & kQsAppVersion), 1100, 640, 56
# matched nothing - and nocloud contributed ZERO dimensions to this gate, the
# only window-building stack in the tree that did. Proven by mutation before the
# fix: rewriting that line to 1600, 1200 still printed the same
# "OK (43 ... in 27 file(s) within 1200x640)", because the file was never
# counted at all. The title is now anything up to the first top-level comma, and
# the two dimensions may be same-file numeric constants, resolved through the
# `consts` map SET_RE already uses.
CHROME_RE = re.compile(
    r'^\s*uiChrome\s+(?:"[^"]*"|\([^)]*\)|[^,]+?)\s*,\s*'
    r'([0-9]+|k[A-Za-z0-9_]+)\s*,\s*([0-9]+|k[A-Za-z0-9_]+)'
    r'\s*(?:,\s*(?:[0-9]+|k[A-Za-z0-9_]+)\s*)?$')

# THE LOOSE PASS. Every line that LOOKS like it sizes a window but that none of
# the three strict patterns consumed is reported, rather than falling through
# silently - the same fail-rather-than-fall-back discipline check-suite-coverage
# applies to its sentinel cut. Without it this gate's count is of what it
# PARSED, reported as what it CHECKED, which is the exact shape CLAUDE.md
# records for coinxt's constant gate.
LOOSE_RE = re.compile(
    r'^\s*(?:set\s+the\s+(?:width|height|rect)\s+of\s+this\s+stack\s+to\b'
    r'|uiChrome\b)')

# Sizing lines that are deliberately unreadable, each with its reason. These are
# not windows: they are the carried kit's own parameterised builder and one
# restore-from-a-saved-property line.
# The blocks this family carries verbatim into many files. A sizing line inside
# one of them belongs to its MASTER, which is measured on its own row.
CARRIED_SPANS = [
    (">>> BEGIN EMBEDDED LIBRARIES", "<<< END EMBEDDED LIBRARIES"),
    ("==== SUITE UI KIT v2 BEGIN", "==== SUITE UI KIT v2 END"),
    ("==== SUITE HARNESS SCAFFOLD v1 BEGIN", "==== SUITE HARNESS SCAFFOLD v1 END"),
    ("==== DEMO SELF-CHECK v1 BEGIN", "==== DEMO SELF-CHECK v1 END"),
]

LOOSE_EXEMPT = {
    "tools/ui-kit.livecodescript":
        "the kit MASTER's uiChrome sizes from pWidth/pHeight - it is a builder, "
        "not a stack; every adopter's own call carries the real numbers",
    "tools/harness-scaffold.livecodescript":
        "the scaffold MASTER sizes from kStWidth/kStHeight, which each adopter "
        "declares",
    "torrentxt/examples/torrent-client.livecodescript":
        "restores a height saved in a custom property (uHeight) at open; the "
        "stack's own budgeted size is set beside it",
}
# a constant line may declare several names (`constant kW = 1180, kH = 640`),
# so the line is matched first and each name = number pair is read out of it
CONST_LINE_RE = re.compile(r'^\s*constant\s+(.+?)\s*(?:--.*)?$')
CONST_PAIR_RE = re.compile(r'(k[A-Za-z0-9_]+)\s*=\s*([0-9]+)')

# the generated suite harness carries the core's numbers verbatim; checking
# both would double-report one source line, so the generated copy is skipped
# (build-suite-selftest.py --check already pins it to the core). The two
# suite-level carried-block MASTERS are templates, not runnable stacks: the
# harness scaffold sizes its window from kStWidth/kStHeight, which each
# ADOPTER declares - the gate reads the real numbers there.
SKIP = {os.path.join("tests", "suite-selftest.livecodescript"),
        os.path.join("tools", "ui-kit.livecodescript"),
        os.path.join("tools", "harness-scaffold.livecodescript")}


def check_file(path, rel, problems, loose_misses=None):
    lines = open(path, encoding="utf-8").read().split("\n")
    consts = {}
    str_consts = {}
    for line in lines:
        m = CONST_LINE_RE.match(line)
        if m:
            for name, value in CONST_PAIR_RE.findall(m.group(1)):
                consts[name] = int(value)
            for name, value in CONST_STR_PAIR_RE.findall(m.group(1)):
                str_consts[name] = value
    found = 0
    consumed = set()
    for i, line in enumerate(lines, 1):
        m = SET_RE.match(line)
        if m:
            axis, raw = m.group(1), m.group(2)
            if raw.isdigit():
                value = int(raw)
            elif raw in consts:
                value = consts[raw]
            else:
                problems.append(
                    "%s:%d: stack %s set from %s, which is not a literal "
                    "or a same-file numeric constant - use one so this "
                    "gate can read it" % (rel, i, axis, raw))
                continue
            found += 1
            limit = MAX_WIDTH if axis == "width" else MAX_HEIGHT
            if value > limit:
                problems.append(
                    "%s:%d: stack %s %d exceeds the 720p budget "
                    "(max %d)" % (rel, i, axis, value, limit))
        m = CHROME_RE.match(line)
        if m:
            width = consts.get(m.group(1)) if not m.group(1).isdigit() \
                else int(m.group(1))
            height = consts.get(m.group(2)) if not m.group(2).isdigit() \
                else int(m.group(2))
            if width is None or height is None:
                if loose_misses is not None:
                    loose_misses.append(
                        "%s:%d: uiChrome sizes from a name this file does not "
                        "declare as a numeric constant (%s, %s)"
                        % (rel, i, m.group(1), m.group(2)))
                continue
            found += 1
            if width > MAX_WIDTH:
                problems.append(
                    "%s:%d: uiChrome width %d exceeds the 720p budget "
                    "(max %d)" % (rel, i, width, MAX_WIDTH))
            if height > MAX_HEIGHT:
                problems.append(
                    "%s:%d: uiChrome height %d exceeds the 720p budget "
                    "(max %d)" % (rel, i, height, MAX_HEIGHT))
            continue
        m = RECT_RE.match(line)
        if m:
            raw = m.group(1)
            if raw.startswith('"'):
                quad = raw.strip('"')
            elif raw in str_consts:
                quad = str_consts[raw]
            else:
                problems.append(
                    "%s:%d: stack rect set from %s, which is not a literal "
                    "quad or a same-file string constant - use one so this "
                    "gate can read it" % (rel, i, raw))
                continue
            parts = [p.strip() for p in quad.split(",")]
            if len(parts) != 4 or not all(p.isdigit() for p in parts):
                problems.append(
                    "%s:%d: stack rect %r is not a numeric L,T,R,B quad"
                    % (rel, i, quad))
                continue
            found += 1
            left, top, right, bottom = (int(p) for p in parts)
            if right - left > MAX_WIDTH:
                problems.append(
                    "%s:%d: stack rect width %d exceeds the 720p budget "
                    "(max %d)" % (rel, i, right - left, MAX_WIDTH))
            if bottom - top > MAX_HEIGHT:
                problems.append(
                    "%s:%d: stack rect height %d exceeds the 720p budget "
                    "(max %d)" % (rel, i, bottom - top, MAX_HEIGHT))
    # THE LOOSE PASS: anything that looks like a sizing line and was not read.
    #
    # CARRIED SPANS ARE CUT FIRST, and the first version of this pass did not do
    # that: it reported `set the width of this stack to pWidth` in fourteen
    # files, which is not fourteen unmeasured stacks - it is ONE line, the ui
    # kit master's own uiChrome builder, carried verbatim into every adopter.
    # A scan that asks "what does this demo do?" has to read the demo's own
    # code, which is the same cut check-suite-coverage makes before it counts
    # calls and check-demo-control-lists makes before it derives names.
    if loose_misses is not None and rel not in LOOSE_EXEMPT:
        carried, skip_to = set(), None
        for i, line in enumerate(lines, 1):
            if skip_to is None:
                hit = next((sp for sp in CARRIED_SPANS if sp[0] in line), None)
                if hit:
                    skip_to = hit[1]
                    carried.add(i)
            else:
                carried.add(i)
                if skip_to in line:
                    skip_to = None
        for i, line in enumerate(lines, 1):
            if i in carried or not LOOSE_RE.match(line):
                continue
            if (SET_RE.match(line) or RECT_RE.match(line)
                    or CHROME_RE.match(line)):
                continue
            loose_misses.append(
                "%s:%d: this line sizes a window and none of the three "
                "patterns could read it, so it was measured by NOTHING:\n"
                "        %s" % (rel, i, line.strip()))
    return found


def main():
    problems = []
    loose_misses = []
    sized = 0
    files = 0
    measured = set()
    for path in sorted(glob.glob(os.path.join(ROOT, "**", "*.livecodescript"),
                                 recursive=True)):
        rel = os.path.relpath(path, ROOT)
        if rel in SKIP:
            continue
        n = check_file(path, rel, problems, loose_misses)
        if n:
            files += 1
            sized += n
            measured.add(rel)

    # THE CROSS-CHECK. check-ui-kit-drift.py's ADOPTERS + EXEMPT is this tree's
    # definition of "a stack that builds a window". Any one of them that
    # contributes no dimension at all is a stack this gate is silently not
    # measuring - which is what nocloud was until 2026-08-20, while the OK line
    # reported a confident 43/27.
    try:
        spec = importlib.util.spec_from_file_location(
            "cukd", os.path.join(HERE, "check-ui-kit-drift.py"))
        cukd = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(cukd)
        windowed = set(cukd.ADOPTERS) | set(cukd.EXEMPT)
    except Exception as exc:                      # pragma: no cover
        problems.append("could not read check-ui-kit-drift.py's stack lists, so "
                        "the cross-check did not run: %s" % exc)
        windowed = set()
    for rel in sorted(windowed):
        if rel in SKIP or rel in measured:
            continue
        if not os.path.exists(os.path.join(ROOT, rel)):
            continue
        problems.append(
            "%s builds a window (it is in check-ui-kit-drift.py's ADOPTERS or "
            "EXEMPT) but contributes no measured dimension - this gate is not "
            "checking it at all" % rel)

    problems.extend(loose_misses)
    if problems:
        print("check-stack-size: FAILED")
        for p in problems:
            print("  - %s" % p)
        return 1
    # the count is of WINDOW dimensions, and the message says so: an "OK"
    # here has never been a statement about any control inside those windows
    print("check-stack-size: OK (%d stack window dimension(s) in %d file(s) "
          "within %dx%d; controls inside them are out of scope - holde-em's "
          "are held by holde-em/tools/check-table-layout.py)"
          % (sized, files, MAX_WIDTH, MAX_HEIGHT))
    return 0


if __name__ == "__main__":
    sys.exit(main())
