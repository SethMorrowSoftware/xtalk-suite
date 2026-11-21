#!/usr/bin/env python3
"""check-ui-kit-text-colour.py - words on a colour of the kit's get a colour
of the kit's (tools/ui-kit.livecodescript, rule 7 of its header).

WHY THIS EXISTS
    On Windows in the dark appearance, render3dxt's physics demo showed its
    log and its check boxes' labels white on white on 2026-11-20, and the
    xlsxt and pdfxt demos their fields on 2026-11-21 (OXT-Beyond 0.2.8-dp.1
    on Windows 11, on the maintainer's PC; measured there: the field's
    effective foregroundColor 255,255,255). uiInput and uiArea gave their
    fields the kit's white (kUiCard) and no text colour, and the engine gave
    the words the dark appearance's white.
    The kit's labels never had the fault, because uiLabel always set kUiInk;
    a check box had it too, its label on the page's kUiBg. OXT-Beyond after
    0.2.8-dp.2 draws such words black, as LiveCode Community did (its pull
    request 608), but a demo must read the same on every engine the suite
    supports, 0.2.8-dp.1 among them: the kit names its colours.

WHAT IT HOLDS, in the master's carried block (check-ui-kit-drift.py holds
every adopter's copy byte-identical to it, so the master is the one place):
    1. a `set the backgroundColor of field X` or `... of button X` has a
       `set the foregroundColor of` the same X in the same handler;
    2. a field a builder creates (`create field`, then named) gets a
       foregroundColor in that builder;
    3. a button made a check box or a radio button gets a foregroundColor
       where it is made one: it has no face, so its label is on the page;
    4. a backgroundColor on anything else is a graphic's (a graphic has no
       words) or is listed in EXEMPT with its reason;
    5. a builder that creates a button and gives it no text colour is listed
       in NO_TEXT_COLOUR with its reason (the theme draws a push button's
       face and words together).
    A stale EXEMPT or NO_TEXT_COLOUR entry fails too, so neither table can
    rot into folklore. tools/test-ui-kit-text-colour.py proves each rule
    fires on the real master, mutated in memory.

    It reads statements, not meaning: a colour set through a variable
    target, a `do`, or a handler of the adopter's is invisible to it, and
    the kit uses none of those. It holds the kit, not the adopters' own
    code, whose colours are each demo's.

USAGE
    python3 tools/check-ui-kit-text-colour.py
"""

import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def _load(name):
    spec = importlib.util.spec_from_file_location(
        name.replace("-", "_").replace(".py", ""), os.path.join(HERE, name))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# The block's markers and the master's path are the drift gate's: one
# definition of what the carried block is
DRIFT = _load("check-ui-kit-drift.py")

# A background colour that is neither a field's nor a button's nor a
# graphic's, keyed by (handler, target), with the reason a reader needs.
EXEMPT = {
    ("uiChrome", "this card"):
        "the page ground: every control inherits a text colour set here, and "
        "a native push button's face is the theme's (dark in the dark "
        "appearance), so kUiInk on the card would put dark words on it",
}

# Builders that create a button and give it no text colour, with the reason.
NO_TEXT_COLOUR = {
    "uiButton":
        "a push button: the theme draws its face and its words together, in "
        "either appearance (uiCheckbox colours the check box made from one)",
    "uiContextMenu":
        "a hidden popup menu: the theme draws the menu it shows",
}

HANDLER_RE = re.compile(r"(?i)^\s*(?:private\s+)?(?:command|function|on|getprop|setprop)\s+([A-Za-z_]\w*)")
SET_COLOUR_RE = re.compile(
    r"(?i)^\s*set\s+the\s+(backgroundColor|foregroundColor)\s+of\s+(.+?)\s+to\s+\S")
NAME_LAST_RE = re.compile(r"(?i)^\s*set\s+the\s+name\s+of\s+the\s+last\s+(field|button)\s+to\s+(.+?)\s*$")
CREATE_RE = re.compile(r"(?i)^\s*create\s+(field|button)\s*$")
INDICATOR_RE = re.compile(
    r'(?i)^\s*set\s+the\s+style\s+of\s+(button\s+.+?)\s+to\s+"(checkbox|radioButton|radio)"\s*$')


def code_line(line):
    """The line with its comment cut, outside string literals."""
    out = []
    quoted = False
    i = 0
    while i < len(line):
        c = line[i]
        if c == '"':
            quoted = not quoted
        elif not quoted and (line.startswith("--", i) or c == "#"):
            break
        out.append(c)
        i += 1
    return "".join(out).rstrip()


def target(text):
    """A control reference as one spelling: whitespace collapsed, `the`
    dropped, `fld`/`btn` spelt out."""
    text = re.sub(r"\s+", " ", text.strip())
    text = re.sub(r"(?i)^the ", "", text)
    text = re.sub(r"(?i)^fld\b", "field", text)
    text = re.sub(r"(?i)^btn\b", "button", text)
    return text


def handlers(block):
    """[(name, [code lines])] of the block's handlers."""
    out = []
    current = None
    for raw in block.split("\n"):
        line = code_line(raw)
        if current is None:
            m = HANDLER_RE.match(line)
            if m:
                current = (m.group(1), [])
            continue
        if re.match(r"(?i)^\s*end\s+%s\s*$" % re.escape(current[0]), line):
            out.append(current)
            current = None
            continue
        if line.strip():
            current[1].append(line)
    return out


def findings(block, exempt=None, no_text_colour=None):
    """The rule breaches of a kit block, one sentence each."""
    exempt = EXEMPT if exempt is None else exempt
    no_text_colour = NO_TEXT_COLOUR if no_text_colour is None else no_text_colour
    problems = []
    used_exempt = set()
    used_no_text = set()
    for name, lines in handlers(block):
        backs, fores = [], set()
        created = {}
        made = None
        indicators = []
        for line in lines:
            m = SET_COLOUR_RE.match(line)
            if m:
                what = target(m.group(2))
                if m.group(1).lower() == "backgroundcolor":
                    backs.append(what)
                else:
                    fores.add(what.lower())
                continue
            m = CREATE_RE.match(line)
            if m:
                made = m.group(1).lower()
                continue
            m = NAME_LAST_RE.match(line)
            if m and made == m.group(1).lower():
                created[target("%s %s" % (m.group(1), m.group(2)))] = made
                made = None
                continue
            m = INDICATOR_RE.match(line)
            if m:
                indicators.append(target(m.group(1)))
        for what in backs:
            kind = what.split(" ", 1)[0].lower()
            if kind in ("field", "button"):
                if what.lower() not in fores:
                    problems.append("%s sets the backgroundColor of %s and not its foregroundColor: its "
                                    "words would take the appearance's colour (white in the dark one) on "
                                    "the kit's colour" % (name, what))
            elif kind == "graphic":
                continue
            elif (name, what) in exempt:
                used_exempt.add((name, what))
            else:
                problems.append("%s sets the backgroundColor of %s, which is neither a field, a button nor "
                                "a graphic: give its words a colour, or list it in EXEMPT with the reason"
                                % (name, what))
        for what, kind in created.items():
            if kind == "field" and what.lower() not in fores:
                problems.append("%s creates %s and gives it no foregroundColor: its words would take the "
                                "appearance's colour (white in the dark one)" % (name, what))
            if kind == "button" and what.lower() not in fores:
                if name in no_text_colour:
                    used_no_text.add(name)
                else:
                    problems.append("%s creates %s and gives it no foregroundColor: give it one, or list "
                                    "the builder in NO_TEXT_COLOUR with the reason" % (name, what))
        for what in indicators:
            if what.lower() not in fores:
                problems.append("%s makes %s a check box or a radio button and gives it no "
                                "foregroundColor: it has no face, so its label is on the page, in the "
                                "appearance's colour (white in the dark one)" % (name, what))
    for key in sorted(set(exempt) - used_exempt):
        problems.append("EXEMPT entry %r matches no backgroundColor the kit sets: remove it" % (key,))
    for key in sorted(set(no_text_colour) - used_no_text):
        problems.append("NO_TEXT_COLOUR entry %r is not a builder that creates a button without a text "
                        "colour: remove it" % key)
    return problems


def main():
    block, err = DRIFT.extract(DRIFT.MASTER)
    if err:
        print("check-ui-kit-text-colour: FAILED - %s" % err)
        return 1
    count = len(handlers(block))
    if count < 10:
        # a block that parsed into almost nothing would pass every rule
        print("check-ui-kit-text-colour: FAILED - only %d handlers read from %s" % (count, DRIFT.MASTER))
        return 1
    problems = findings(block)
    if problems:
        print("check-ui-kit-text-colour: FAILED")
        for p in problems:
            print("  - " + p)
        return 1
    print("check-ui-kit-text-colour: OK (%d handlers of %s; every background colour on a field or button "
          "has a text colour beside it)" % (count, DRIFT.MASTER))
    return 0


if __name__ == "__main__":
    sys.exit(main())
