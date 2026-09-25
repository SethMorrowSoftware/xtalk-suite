#!/usr/bin/env python3
"""test-suite-ui-version.py - prove tools/check-suite-ui-version.py FAILS on a
build the stamp no longer follows, and stays quiet on an edit the build does
not read.

WHY THIS EXISTS
---------------
The gate asks one question - does kSuUiVersion equal the fingerprint of what
suBuildAll reaches? - and a gate that reaches too little answers "yes" to a
real layout change, which is the hand-bumped stamp's failure all over again
(work plan suite-wide #17). So each case below seeds ONE change into a
SCRATCH COPY of tests/suite-selftest.core.livecodescript (the committed file
is never touched), runs the REAL gate on it as a subprocess, exactly as
tools/build-all.sh runs it, and holds the verdict:

  MUST FAIL (a build the stamp does not follow):
    a  a layout edit in suBuildAll itself, the stamp unchanged;
    b  an edit in a HELPER it reaches (suBuildReset), proving the closure
       walks past the root;
    c  an edit in a carried KIT builder (uiButton), proving it walks into
       the kit a re-carry would change;
    d  a constant the build reads (kSuRowStep), proving constants count;
    e  a stale stamp: the build untouched, the constant set back to the
       hand-bumped "suite-board-1";
    f  a stamp that is not prefixed (bare hex digits: suBuild compares it with
       `is`, engine note 2.11);
    g  kSuUiVersion named inside the build (a stamp that hashes itself);
    l  a constant's value changed beside a trailing comment (the comment
       must not blind the gate to the value);
    n  a stale stamp behind a trailing comment on its own line (and --fix
       then restores the value and keeps the comment).
  MUST PASS (the build did not change):
    h  a comment edit inside suBuildAll (comments cannot move a control);
    i  a code edit in a handler the build does not reach (suPump);
    k  a trailing comment on a constant the build reads (the first cut
       died here with "not in list", --fix included);
    m  a trailing comment on the stamp line itself (the first cut read it
       as no declaration: "found 0").
  --fix:
    j  on case a's copy, --fix writes a stamp, the gate then passes, and a
       second --fix changes nothing.

Each needle must occur EXACTLY ONCE in the core, so a stale fixture fails
loudly rather than seeding nothing. The committed core must pass first.

USAGE
    python3 tools/test-suite-ui-version.py
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GATE = os.path.join(HERE, "check-suite-ui-version.py")
CORE = os.path.join(ROOT, "tests", "suite-selftest.core.livecodescript")

STAMP_RE = re.compile(r'^(constant kSuUiVersion = ")([^"]*)(")$', re.M)


def set_stamp(value):
    return lambda t: STAMP_RE.sub(lambda m: m.group(1) + value + m.group(3), t, 1)


def comment_stamp(value):
    """The stamp line with a trailing comment, its value kept (None) or
    replaced."""
    return lambda t: STAMP_RE.sub(
        lambda m: m.group(1) + (m.group(2) if value is None else value)
        + m.group(3) + "   -- derived, never bumped", t, 1)


# (id, what, needle, replacement or a function of the text, must fail?,
#  a phrase the gate must print)
CASES = [
    ("a", "a layout edit in suBuildAll, the stamp unchanged",
     '   uiButton "stCopy", "Copy results", ',
     '   uiButton "stCopy", "Copy report", ',
     True, "fingerprint to"),
    ("b", "an edit in suBuildReset, a helper suBuildAll calls",
     '   put "stTitle,stSummary,stCopy,stRerun,stResults" into tRetired\n',
     '   put "stTitle,stSummary,stCopy,stRerun,stResults,stOld" into tRetired\n',
     True, "fingerprint to"),
    ("c", "an edit in the carried kit's uiButton",
     "command uiButton pName, pLabel, pRect\n",
     "command uiButton pName, pLabel, pRect\n   local tKitProbe\n",
     True, "fingerprint to"),
    ("d", "a constant the build reads (the row pitch)",
     "constant kSuRowStep = 34\n",
     "constant kSuRowStep = 36\n",
     True, "fingerprint to"),
    ("e", "a stale stamp: the hand-bumped value put back",
     None, set_stamp("suite-board-1"),
     True, "is suite-board-1"),
    ("f", "a stamp without its prefix (bare digits compare as numbers)",
     None, set_stamp("123456789012"),
     True, "does not open with"),
    ("g", "kSuUiVersion named inside the build",
     '   suBuildReset\n   uiChrome kStTitle, kStWidth, kStHeight\n',
     '   suBuildReset\n   put kSuUiVersion into tRect\n'
     '   uiChrome kStTitle, kStWidth, kStHeight\n',
     True, "no fixed point"),
    ("h", "a comment edit inside suBuildAll (NEGATIVE: must pass)",
     "   -- the header row: the scaffold's controls, under the scaffold's names\n",
     "   -- the header row: the scaffold's four controls, under their own names\n",
     False, "check-suite-ui-version: OK"),
    ("i", "a code edit the build does not reach (NEGATIVE: must pass)",
     '   send "suPump" to me in 33 milliseconds\nend suPump\n',
     '   put empty into tEvents\n   send "suPump" to me in 33 milliseconds\n'
     'end suPump\n',
     False, "check-suite-ui-version: OK"),
    # A comment AFTER the value of a constant the build reads (review,
    # 2026-09-25): the first cut died on "... is not in list" here, --fix
    # included, over an edit its own rule says changes nothing. k proves it
    # passes; l proves the comment did not blind it to the value beside it.
    ("k", "a trailing comment on a constant the build reads (NEGATIVE: "
          "must pass)",
     "constant kSuRowStep = 34\n",
     "constant kSuRowStep = 34   -- the row pitch\n",
     False, "check-suite-ui-version: OK"),
    ("l", "that constant's value changed beside a trailing comment",
     "constant kSuRowStep = 34\n",
     "constant kSuRowStep = 36   -- the row pitch\n",
     True, "fingerprint to"),
    # The same, on the STAMP's own line: the first cut read one as no
    # declaration at all ("found 0").
    ("m", "a trailing comment on the stamp line (NEGATIVE: must pass)",
     None, comment_stamp(None),
     False, "check-suite-ui-version: OK"),
    ("n", "a stale stamp behind a trailing comment",
     None, comment_stamp("suite-board-1"),
     True, "is suite-board-1"),
]


def run(path, *extra):
    proc = subprocess.run([sys.executable, GATE, "--core", path] + list(extra),
                          stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True)
    return proc.returncode, proc.stdout


def mutate(text, needle, repl):
    if needle is None:
        out = repl(text)
        return out if out != text else None
    if text.count(needle) != 1:
        return None
    return text.replace(needle, repl, 1)


def main():
    problems = []

    def verdict(ok, label, detail=""):
        print("  %s %s" % ("ok  " if ok else "FAIL", label))
        if not ok:
            problems.append(label + (("\n      " + detail.replace("\n", "\n      "))
                                     if detail else ""))

    proc = subprocess.run([sys.executable, GATE], stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT, text=True)
    verdict(proc.returncode == 0 and "check-suite-ui-version: OK" in proc.stdout,
            "the committed core passes, called exactly as build-all.sh calls it",
            proc.stdout)
    if problems:
        print("test-suite-ui-version: FAILED (the clean core must pass first)")
        return 1
    core = open(CORE, encoding="utf-8").read()
    scratch = tempfile.mkdtemp(prefix="test-suite-ui-version-")
    try:
        base = os.path.join(scratch, "clean.livecodescript")
        shutil.copyfile(CORE, base)
        code, out = run(base)
        verdict(code == 0, "an untouched scratch copy passes (--core is honoured)",
                out)
        paths = {}
        for cid, what, needle, repl, must_fail, phrase in CASES:
            text = mutate(core, needle, repl)
            label = "%s  %s" % (cid, what)
            if text is None:
                verdict(False, label, "FIXTURE STALE: the needle is not in the "
                        "core exactly once (or the change changed nothing)")
                continue
            path = os.path.join(scratch, "case-%s.livecodescript" % cid)
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(text)
            paths[cid] = path
            code, out = run(path)
            ok = (code == 1 if must_fail else code == 0) and phrase in out \
                and "Traceback" not in out
            verdict(ok, label, "want exit %d and %r; got exit %d:\n%s"
                    % (1 if must_fail else 0, phrase, code, out))
        # j: --fix on case a's copy
        if "a" in paths:
            code, out = run(paths["a"], "--fix")
            fixed = open(paths["a"], encoding="utf-8").read()
            c2, o2 = run(paths["a"])
            c3, o3 = run(paths["a"], "--fix")
            again = open(paths["a"], encoding="utf-8").read()
            stamp = STAMP_RE.search(fixed)
            verdict(code == 0 and "wrote kSuUiVersion" in out and c2 == 0
                    and c3 == 0 and again == fixed and stamp is not None
                    and stamp.group(2).startswith("suite-board-")
                    and stamp.group(2) != STAMP_RE.search(core).group(2),
                    "j  --fix writes a new prefixed stamp, the gate then "
                    "passes, and a second --fix changes nothing",
                    "\n".join((out, o2, o3)))
            only_stamp = re.sub(STAMP_RE, "", fixed) == re.sub(
                STAMP_RE, "", mutate(core, CASES[0][2], CASES[0][3]))
            verdict(only_stamp, "j  --fix touched the stamp line and nothing "
                    "else")
        # n's copy: --fix rewrites the value and keeps the line's comment
        if "n" in paths:
            code, out = run(paths["n"], "--fix")
            fixed = open(paths["n"], encoding="utf-8").read()
            c2, o2 = run(paths["n"])
            want = comment_stamp(None)(core)
            verdict(code == 0 and c2 == 0 and fixed == want,
                    "n  --fix restores the stamp behind its comment, the "
                    "comment kept and nothing else touched",
                    "\n".join((out, o2)))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    if problems:
        print("test-suite-ui-version: FAILED")
        return 1
    print("test-suite-ui-version: OK (the clean core passes; %d build changes "
          "the stamp did not follow fail, %d edits the build does not read "
          "pass, and --fix writes a stamp the gate accepts)"
          % (sum(1 for c in CASES if c[4]), sum(1 for c in CASES if not c[4])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
