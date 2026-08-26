#!/usr/bin/env python3
"""check-doc-status-consistency.py - a blanket "nothing has run on an engine"
must say what closed it, or it is a live claim that an engine pass can falsify.

WHY THIS GATE EXISTS
    On 2026-08-24 nostrxt had its first engine pass: 274 passed, 0 failed, 2
    deliberate skips. That result was written into README.md,
    IMPLEMENTATION-PLAN.md, docs/00-overview.md, docs/05-relay-client.md and
    docs/07-capabilities-required.md.

    It was NOT written into the STATUS headers of the other seven docs, which
    went on opening with "Nothing described here has run on a real engine",
    "Nothing on this page has run on a real OXT engine", and "Nothing in this
    member has run on a real OXT engine". Two suite-level documents carried the
    same stranded sentence: docs/EXTENSIONS-OVERVIEW.md's nostrxt section said
    "Nothing has met an engine" four lines under its own bullet recording the
    pass, and docs/OXT-PASS-RUNBOOK.md still listed the executed fold as a
    pending row. Found and fixed 2026-08-26; ten sites in one member.

    Nothing here was written dishonestly. This is what a PARTIAL UPDATE looks
    like: evidence arrives, the obvious carriers get edited, and the rest of the
    corpus keeps asserting the old world. The honesty convention is the family's
    law, and this is it failing in the UNDERSTATING direction - which is worth a
    gate precisely because that direction feels safe. It is not. The convention's
    whole value is that a label is worth reading; a label saying "unproven" over
    274 green checks teaches a reader to skip labels, and after that the ones
    that matter stop working too.

WHAT IT CHECKS, AND THE ONE DISTINCTION IT TURNS ON
    A BLANKET negative - a claim scoped to a whole page, member or document
    ("nothing here has run on an engine") rather than to a named subsystem - must
    be FOLLOWED, within a short window, by a dated record of what closed it.

    The direction is the whole rule, and it is not a trick:

      "...nothing has run on a real OXT engine. The member-wide status was
       'verified statically; needs an OXT pass' until 2026-08-24, when the
       first engine pass ran green"
                                            <- a RECORD. The negative is the
                                               past state; the date closes it.
                                               Correct as written. PASSES.

      "Status: ... engine-proven 2026-08-24 ... Nothing has met an engine."
                                            <- a CONTRADICTION. The positive
                                               came first and the negative
                                               survived an edit that should have
                                               removed it. FAILS.

    So the gate asks one question with one right answer: does the sentence that
    closes this negative come AFTER it? A blanket negative with nothing after it
    is a live assertion, and the tree is full of dated engine passes that can
    falsify one.

WHAT IT DELIBERATELY DOES NOT CHECK - and why the list is this short
    check-handler-calls.py's docstring states the rule this gate was written
    under: a false alarm in a gate is worse than a missed one, because it teaches
    people to ignore the gate. check-doc-anchors.py refuses to guess for the same
    reason. So:

    - SCOPED negatives are invisible to it. "The receive leg has not run on an
      engine", "the mac lanes have produced no committed binary yet", "browser
      interop is unproven" are not just allowed, they are REQUIRED by the honesty
      convention, and they are the overwhelming majority of negative claims in
      this tree. Only the blanket forms below are matched.
    - It does not try to decide whether a positive is TRUE, or whether it covers
      the same surface as the negative it excuses. That needs judgement, and a
      gate that guesses at judgement produces the false alarms above.
    - It does not read .livecodescript headers. They go stale the same way (the
      coinxt harness header, corrected 2026-08-26, had a fresh STATUS line
      prepended over a body still saying HD wallets "do not exist yet"), but the
      blanket forms there are written too many ways to match without guessing.

USAGE
    python3 tools/check-doc-status-consistency.py [-v]
    Exit 0 when every blanket negative is closed by a following dated record,
    1 when any stands alone.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# A negative scoped to a whole page / member / document. The subject is an
# indefinite "nothing"/"none of it"/"no part of it" - never a named subsystem,
# which is what keeps every legitimate scoped label out of this gate's sight.
# The span between the indefinite subject and its verb must stay inside ONE
# clause. Without that, "nothing about this build discharges them -- and the sx*
# DLEQ calls have never run on an engine" matched: the gate bridged an em-dash
# into a DIFFERENT subject and flagged a correctly-scoped claim. That is the
# false-alarm class this family refuses to ship, so the connectives below are
# hard boundaries.
CLAUSE = r"(?:(?!\b(?:and|but|while|whereas|though|although)\b)[^.;:\u2014\n]){0,%d}?"

BLANKET_NEG = re.compile(
    r"\b(?:nothing|none of (?:it|them|this)|no part of (?:it|this))\b"
    + (CLAUSE % 80) +
    r"\b(?:has|have|had)\b"
    + (CLAUSE % 40) +
    r"\b(?:run|met|been run|touched|reached)\b"
    + (CLAUSE % 60) +
    r"\b(?:engine|relay|daemon)\b",
    re.I)

# A dated record of a pass. The DATE is required: "it works now" is not a record,
# and this tree's convention is that evidence is dated or it is not evidence.
DATED_POS = re.compile(
    r"(?:"
    r"engine[- ](?:pass|proven|passed|green|verified)"
    r"|ran green"
    r"|live[- ]proven"
    r"|ENGINE-(?:PROVEN|PASSED|VERIFIED)"
    r"|first engine (?:pass|contact)"
    r")"
    r"[^.]{0,120}?\b20\d\d-\d\d-\d\d\b"
    r"|\b20\d\d-\d\d-\d\d\b[^.]{0,120}?(?:"
    r"engine[- ](?:pass|proven|passed|green|verified)|ran green|live[- ]proven)",
    re.I)

# How far after the negative the closing record may sit. One long paragraph.
WINDOW = 700

SKIP_DIRS = {".git", "build", "node_modules", "__pycache__"}


def discover(root):
    out = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for name in filenames:
            if name.endswith(".md"):
                out.append(os.path.join(dirpath, name))
    return sorted(out)


def line_of(text, pos):
    return text.count("\n", 0, pos) + 1


def unwrap(text):
    """Turn hard-wrap newlines into spaces, leaving PARAGRAPH breaks as newlines.

    Length is preserved exactly, so every offset still maps to the original
    line. This exists because markdown prose is hard-wrapped and a clause
    routinely spans a line: coinxt's "Nothing in this\nsection has run on an
    engine yet" went invisible the moment the clause pattern stopped crossing
    newlines, which is a MISSED alarm introduced while fixing a false one.
    Paragraph breaks stay hard boundaries, which is what the clause rule needs.
    """
    out = list(text)
    for i, ch in enumerate(out):
        if ch != "\n":
            continue
        # a blank-line break: this newline, or the one before it, bounds a
        # paragraph. Leave both alone.
        before = text[:i].rstrip(" \t")
        after = text[i + 1:].lstrip(" \t")
        if before.endswith("\n") or after.startswith("\n"):
            continue
        out[i] = " "
    return "".join(out)


def scan(path, text):
    """Return (problems, excused) for one document."""
    problems, excused = [], []
    flat = unwrap(text)
    for m in BLANKET_NEG.finditer(flat):
        # The closing record must sit in the SAME paragraph. unwrap() has
        # already turned every hard-wrap newline into a space, so a surviving
        # newline IS a paragraph boundary - and a date under the next heading
        # closes nothing. Without this cut the gate excused a claim whose only
        # nearby date belonged to an unrelated section.
        after = flat[m.end():m.end() + WINDOW].split("\n", 1)[0]
        closing = DATED_POS.search(after)
        rel = os.path.relpath(path, ROOT)
        sentence = re.sub(r"\s+", " ", m.group(0)).strip()
        if closing:
            excused.append((rel, line_of(text, m.start()), sentence,
                            re.sub(r"\s+", " ", closing.group(0)).strip()[:70]))
        else:
            problems.append((rel, line_of(text, m.start()), sentence))
    return problems, excused


def main(argv):
    verbose = "-v" in argv
    targets = [a for a in argv[1:] if not a.startswith("-")] or discover(ROOT)
    problems, excused = [], []
    for path in targets:
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError as exc:
            print("check-doc-status-consistency: cannot read %s: %s" % (path, exc))
            return 1
        p, e = scan(path, text)
        problems.extend(p)
        excused.extend(e)

    if verbose and excused:
        print("EXCUSED - a dated record follows the blanket claim, which is the "
              "correct shape:")
        for rel, ln, sentence, closing in excused:
            print("  %s:%d" % (rel, ln))
            print("      claim  : %s" % sentence[:110])
            print("      closed : %s" % closing)
        print()

    if problems:
        for rel, ln, sentence in problems:
            print("FAIL  %s:%d: a BLANKET \"nothing has run\" claim with no dated "
                  "record after it" % (rel, ln))
            print("      %s" % sentence[:150])
            print("      Either scope the claim to the subsystem that really has "
                  "not run, or follow it with the dated pass that closed it.")
        print("\ncheck-doc-status-consistency: %d unclosed blanket claim(s) in "
              "%d file(s) scanned (%d correctly closed)"
              % (len(problems), len(targets), len(excused)))
        return 1

    print("check-doc-status-consistency: OK (%d file(s); %d blanket claim(s), "
          "each closed by a dated record after it)" % (len(targets), len(excused)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
