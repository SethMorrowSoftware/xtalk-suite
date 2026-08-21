#!/usr/bin/env python3
"""check-demo-control-lists.py - each demo's self-check control list is DERIVED,
and this is the derivation.

WHY THIS EXISTS
    Every adopter of the boot self-check carries a `constant k<Pfx>ScControls`
    naming every control it depends on, and asserts they all exist. Those lists
    were generated once, by hand-run script, and a hand-run generator is a list
    that is right on the day it is written. This tool IS the generator
    (`--write`) and the gate (default), so the two can never disagree.

WHAT A WRONG LIST COSTS
    A phantom name makes `scMissing` report a control that was never supposed to
    exist, so the demo prints `FAIL all N controls this script names exist
    (missing: ...)` on EVERY open - a tidy red line that reads exactly like a
    real defect. That trains the operator to ignore the block, which is worse
    than having no block. Four of the eleven shipped with one:

      riptide-social   `Attached` and `Handed`, scraped out of
                       `uiStatus "Attached" && ...` - uiStatus's first argument
                       is TEXT, not a control name.
      torrent-quickshare, nocloud, onionxt-demo
                       `uiFooter`, added unconditionally, in three demos that
                       never call uiFooter - so the field is never created.

THE TWO RULES THAT FIX BOTH, and why they are derived rather than listed
    1. THE BUILDER SET COMES FROM THE KIT MASTER, not from a pattern. A kit
       handler creates a control named by its first argument if and only if that
       parameter is literally `pName` - true of uiLabel/uiWrap/uiCap/uiSection/
       uiInput/uiArea/uiTable/uiButton/uiCheckbox/uiGfx/uiPanel/uiPill, false of
       uiChrome (pTitle), uiStatus (pText) and uiFooter (pText). Reading the
       master means a new builder is picked up with no edit here, and a
       text-taking helper can never be mistaken for one again.
    2. THE CHROME IS CONDITIONAL. uiChrome creates uiTitle and uiStatus;
       uiFooter creates uiFooter. A demo gets those names in its list only if it
       calls the handler that builds them.

PARSING, same three cuts as everywhere else in this family
    Comments are cut with a string-state-aware scanner (a `--` inside a literal
    is not a comment); the three carried spans are cut so only the demo's own
    code is read; and the scan reads literals, so the noise-stripper that blanks
    them is the wrong tool - root CLAUDE.md records that lesson three times.

USAGE
    python3 tools/check-demo-control-lists.py            # gate
    python3 tools/check-demo-control-lists.py --write    # regenerate the lists
"""

import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

_spec = importlib.util.spec_from_file_location(
    "csd", os.path.join(HERE, "check-demo-selfcheck-drift.py"))
_csd = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(_csd)
ADOPTERS = _csd.ADOPTERS

KIT = os.path.join(ROOT, "tools", "ui-kit.livecodescript")

SPANS = [(">>> BEGIN EMBEDDED LIBRARIES", "<<< END EMBEDDED LIBRARIES"),
         ("==== SUITE UI KIT v2 BEGIN", "==== SUITE UI KIT v2 END"),
         ("==== DEMO SELF-CHECK v1 BEGIN", "==== DEMO SELF-CHECK v1 END")]

NAME = r"[A-Za-z][A-Za-z0-9_:]*"
REF = re.compile(r'\b(?:field|button|graphic|image|scrollbar|player)\s+"(%s)"' % NAME)


def strip_comment(line):
    out, in_str, i = [], False, 0
    while i < len(line):
        c = line[i]
        if c == '"':
            in_str = not in_str
        elif not in_str and line[i:i + 2] == "--":
            break
        out.append(c)
        i += 1
    return "".join(out)


def builders():
    """Kit handlers whose FIRST parameter is literally pName."""
    out = set()
    for m in re.finditer(r"^command\s+(ui\w+)\s+(p\w+)", 
                         open(KIT, encoding="utf-8").read(), re.M):
        if m.group(2) == "pName":
            out.add(m.group(1))
    return out


def demo_source(path):
    lines = open(path, encoding="utf-8", errors="replace").read().split("\n")
    keep, skip = [], None
    for l in lines:
        if skip is None:
            hit = next((s for s in SPANS if s[0] in l), None)
            if hit:
                skip = hit[1]
                continue
            keep.append(strip_comment(l))
        elif skip in l:
            skip = None
    return "\n".join(keep)


def derive(path):
    text = demo_source(path)
    names = set(REF.findall(text))
    for b in builders():
        names |= set(re.findall(r'^\s*%s\s+"(%s)"' % (b, NAME), text, re.M))
    # CONDITIONAL CHROME: only what this demo actually builds.
    if re.search(r"^\s*uiChrome\b", text, re.M):
        names |= {"uiTitle", "uiStatus"}
    if re.search(r"^\s*uiFooter\b", text, re.M):
        names.add("uiFooter")
    return sorted(names)


def const_name(prefix):
    return "k%sScControls" % (prefix[0].upper() + prefix[1:])


def main(argv):
    write = "--write" in argv
    problems, nnames = [], 0
    for rel, prefix in sorted(ADOPTERS.items()):
        path = os.path.join(ROOT, rel)
        want = derive(path)
        nnames += len(want)
        const = const_name(prefix)
        text = open(path, encoding="utf-8").read()
        m = re.search(r'constant %s = "([^"]*)"' % const, text)
        if not m:
            problems.append("%s: no `constant %s`" % (rel, const))
            continue
        have = [n for n in m.group(1).split(",") if n]
        lab = re.search(r'"all (\d+) controls this script names exist', text)
        if write:
            text = text[:m.start()] + 'constant %s = "%s"' % (const, ",".join(want)) \
                   + text[m.end():]
            text = re.sub(r'"all \d+ controls this script names exist',
                          '"all %d controls this script names exist' % len(want),
                          text, count=1)
            open(path, "w", encoding="utf-8").write(text)
            if sorted(have) != want:
                print("%s: %d -> %d" % (rel, len(have), len(want)))
            continue
        extra = sorted(set(have) - set(want))
        missing = sorted(set(want) - set(have))
        if extra:
            problems.append(
                "%s: %s names %d control(s) the source does not build or "
                "reference: %s\n    Each one makes the demo print a FAIL on "
                "every open. Re-run with --write."
                % (rel, const, len(extra), ",".join(extra)))
        if missing:
            problems.append(
                "%s: %s omits %d control(s) the source uses: %s\n    Re-run "
                "with --write." % (rel, const, len(missing), ",".join(missing)))
        if lab and int(lab.group(1)) != len(have):
            problems.append(
                "%s: the assertion says \"all %s controls\" but %s carries %d - "
                "a line that disagrees with the check beside it."
                % (rel, lab.group(1), const, len(have)))

    for p in problems:
        print(p)
    if problems:
        print("check-demo-control-lists: %d problem(s)" % len(problems))
        return 1
    if not write and nnames == 0:
        print("check-demo-control-lists: derived NO names - the scan is broken")
        return 1
    if write:
        print("check-demo-control-lists: wrote %d list(s)" % len(ADOPTERS))
        return 0
    print("check-demo-control-lists: OK (%d adopter(s), %d control name(s) "
          "re-derived from source and matched)" % (len(ADOPTERS), nnames))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
