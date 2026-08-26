#!/usr/bin/env python3
"""test-doc-status-consistency.py - prove the status gate still discriminates.

WHY THIS FILE EXISTS, AND WHY IT DRIVES THE PIPELINE
    The root CLAUDE.md records the way a gate's own test can lie: the
    suite-selftest declaration guard was "mutation-tested" against a hand-built
    input matching its DOCSTRING, an input the real pipeline never produces, so a
    component was verified while the system claim stayed false. The rule it left
    behind is "exercise it the way the build will".

    So every case below is a REAL-SHAPED markdown fragment run through
    check_doc_status_consistency.scan() - the same entry point the gate itself
    calls - hard-wrapped at markdown widths, because unwrapping is where this
    gate has already broken once in each direction.

THE TWO REGRESSIONS THESE FIXTURES PIN
    Both were introduced while fixing the other, which is the whole reason they
    are pinned together:

    1. FALSE ALARM. The first clause pattern bridged an em-dash into a different
       subject, so holde-em's correctly-scoped "the sx* DLEQ calls have never run
       on an engine" was flagged because an unrelated "nothing about this build
       discharges them" sat in front of it. Cases 5 and 6.
    2. MISSED ALARM. Fixing that by forbidding newlines inside a clause made
       coinxt's hard-wrapped "Nothing in this\\nsection has run on an engine yet"
       invisible. Case 3.

USAGE
    python3 tools/test-doc-status-consistency.py
    Exit 0 when every fixture lands on the expected side.
"""
import os
import sys
import importlib.util

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "cdsc", os.path.join(HERE, "check-doc-status-consistency.py"))
cdsc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cdsc)

# (name, expect_problem, text)
CASES = [
    ("a bare blanket claim with nothing after it", True,
     "# 06 - Public API Reference\n\n"
     "> **Status: verified statically; needs an OXT pass.** Every relay-facing\n"
     "> handler additionally needs a live-relay pass. Nothing on this page has\n"
     "> run on a real OXT engine. What IS machine-verified on every build:\n"
     "> `tools/nostr-kat.py` sweeps the published vector sets.\n"),

    ("a blanket claim closed by a dated record AFTER it", False,
     "Phases 0 through 5 CLOSED - statically - on 2026-08-23. \"Closed\n"
     "statically\" means every gate exits 0, every answer is pinned, and\n"
     "**nothing has run on a real OXT engine**. The member-wide status was\n"
     "\"verified statically; needs an OXT pass\" until 2026-08-24, when the\n"
     "first engine pass ran green (274/274 in the suite paste).\n"),

    ("a blanket claim hard-wrapped mid-clause (the MISSED-alarm regression)", True,
     "## BIP-340 Schnorr and BIP-341 Taproot (ABI 6)\n\n"
     "New on 2026-08-16, over a SECOND vendored native library. **Nothing in this\n"
     "section has run on an engine yet** - it is verified statically and executed\n"
     "headlessly against the published vector files.\n"),

    ("a dated positive BEFORE and nothing after (the contradiction shape)", True,
     "- **Status**: the `nx*` core is engine-proven 2026-08-24 (Windows x86_64,\n"
     "  OXT 9.6.3; 274/274 in the suite paste). The relay layer is split.\n"
     "  Nothing has met an engine. What is machine-verified headlessly:\n"
     "  `tools/nostr-kat.py` sweeps the complete published BIP-340 csv.\n"),

    ("a SCOPED negative after an unrelated 'nothing' (the FALSE-alarm regression)", False,
     "> NOT done, on purpose: the hostile review and the soak period below are\n"
     "> HUMAN-ERA work and stay open -- nothing about this build discharges\n"
     "> them -- and the sx* DLEQ calls have never run on an engine.\n"),

    ("a plainly scoped negative, the convention's required form", False,
     "The receive leg has not run on an engine, and NIP-42 auth has not either;\n"
     "both keep \"verified statically; needs a live-relay pass\".\n"),

    ("a blanket claim closed across a hard wrap", False,
     "Nothing in this member has run on a real OXT engine; that was true until\n"
     "the first engine pass ran green on 2026-08-24, recorded in CLAUDE.md.\n"),

    ("a blanket claim whose 'closing' record carries no date", True,
     "Nothing on this page has run on a real engine. It works now and the\n"
     "harness is green, so the label will be updated at some point.\n"),

    ("a blanket claim separated from its date by a PARAGRAPH break", True,
     "Nothing in this section has met an engine.\n\n"
     "## An unrelated heading\n\n"
     "Some other subject entirely ran green on 2026-08-24.\n"),

    ("prose with no blanket claim at all", False,
     "The `nx*` core is engine-proven 2026-08-24. Every byte-level claim in this\n"
     "document is pinned headlessly by `tools/nostr-kat.py`.\n"),
]


def main():
    bad = 0
    for name, expect_problem, text in CASES:
        problems, excused = cdsc.scan("fixture.md", text)
        got = bool(problems)
        if got != expect_problem:
            print("FAIL  %s" % name)
            print("      expected %s, got %s (problems=%d excused=%d)"
                  % ("a PROBLEM" if expect_problem else "no problem",
                     "a PROBLEM" if got else "no problem",
                     len(problems), len(excused)))
            for _, ln, sentence in problems:
                print("      flagged: %s" % sentence[:100])
            bad += 1
        else:
            print("ok    %s" % name)

    # Case 5 must be silent for the RIGHT reason: the scoped claim is present in
    # the text and the gate simply does not match it. If a future edit made the
    # gate blind to blanket claims entirely, every case would pass "no problem"
    # and this suite would go green while checking nothing - so assert the
    # positive direction still fires on the same shape with the clause joined.
    problems, _ = cdsc.scan("fixture.md",
                            "nothing about this build has run on an engine.\n")
    if not problems:
        print("FAIL  the gate no longer fires on ANY blanket claim - it has gone "
              "blind, and cases expecting 'no problem' would pass vacuously")
        bad += 1
    else:
        print("ok    the gate still fires on a blanket claim (not vacuously green)")

    if bad:
        print("\ntest-doc-status-consistency: %d fixture(s) landed on the wrong side."
              % bad)
        return 1
    print("\ntest-doc-status-consistency: all %d fixtures discriminate correctly."
          % (len(CASES) + 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
