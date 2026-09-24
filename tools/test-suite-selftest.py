#!/usr/bin/env python3
"""test-suite-selftest.py - prove tools/check-suite-selftest.py's checks FIRE.

WHY THIS FILE EXISTS
    check-suite-selftest.py is the compiler this repository does not have for
    the suite paste, and since D-23 it also reads the hand-written core: the
    board's timers, its control names, its call graph, its rows against the
    registry. Every one of those checks answers "OK" on a tree that is fine
    AND on a gate that has gone blind, and the root CLAUDE.md records what the
    second costs (a blind gate still prints OK; fixture before gate). So this
    drives the REAL gate the way tools/build-all.sh runs it - a subprocess,
    `python3 tools/check-suite-selftest.py`, with the paste path (and --core)
    pointed at SCRATCH COPIES of the committed files - once per defect:

      * the real files pass, with no arguments (build-all's exact call) and
        as untouched scratch copies;
      * each mutation below is ONE defect, reconstructed in the file the check
        reads (the paste or the core), with every needle asserted present
        EXACTLY ONCE first - a needle that drifted would otherwise turn the
        case into a run of the clean file, which passes and proves nothing;
      * each mutated run must FAIL, and the set of checks that fired (the
        gate tags every line `[check N]`) must be exactly the set the case
        names - so a mutation proves its own check discriminates, and proves
        it did not merely trip a neighbour;
      * the NEGATIVE CONTROLS must pass: a comment that names en1stCleanup is
        prose, not a call (check 7 asks the comment-free view), and the
        core's own "call site" report text is a label, not a `call`
        statement (check 14 asks the literal-blanked view). A gate that
        cried wolf on either would be switched off within a week.

    The runs are independent, so they go four or so at a time.

    python3 tools/test-suite-selftest.py
Exit 0 when the clean files pass, every mutation is caught by exactly the
checks it names, and every negative control passes; 1 otherwise.
"""

import concurrent.futures
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GATE = os.path.join(ROOT, "tools", "check-suite-selftest.py")
PASTE = os.path.join(ROOT, "tests", "suite-selftest.livecodescript")
CORE = os.path.join(ROOT, "tests", "suite-selftest.core.livecodescript")


class Stale(Exception):
    """A needle is not in the committed file exactly once: the FIXTURE is out
    of date, which must fail as loudly as a gate regression would."""


def swap(text, needle, replacement, label):
    n = text.count(needle)
    if n != 1:
        raise Stale(f"{label}: needle found {n} time(s), want exactly 1:\n{needle}")
    return text.replace(needle, replacement, 1)


def after(text, needle, extra, label):
    return swap(text, needle, needle + extra, label)


def run_gate(*args):
    proc = subprocess.run([sys.executable, GATE] + list(args),
                          capture_output=True, text=True, cwd=ROOT)
    return proc.returncode, proc.stdout + proc.stderr


def tags(out):
    return set(re.findall(r'^\s+- \[check (\w+)\]', out, re.M))


# ---- anchors in the committed files (each asserted unique by swap) ----------
# The paste: the core's own stCleanup (members' copies are prefixed), the
# paste's first handler, and riptide's generated acquire body.
P_CLEANUP = "command stCleanup\n"
P_FIRST_END = "\nend stMonoFont\n"
P_UIBG = 'constant kUiBg = "240,242,246"\n'
P_SCLINES = ("local sScLines          -- the whole block, kept so a Copy "
             "button has something\n")
P_SCPROBE = 'constant kScProbe = "self-check: delayed write reached the status line"\n'
P_RIPTIDE = ("   if sSession > 0 then\n"
             "      put sSession into rs1sRsTestSession\n"
             "      return rs1sRsTestSession\n"
             "   end if\n"
             "   put 0 into rs1sRsTestSession\n"
             "   return 0\n"
             "end rs1rstAcquireSession\n")
# The fold's riptide body before 9aa62c8 (the alias taken on the FIRST call
# only, with a fallback start), prefixed as the fold wrote it.
P_RIPTIDE_OLD = ("   if rs1sRsTestSession is not empty and rs1sRsTestSession > 0 then\n"
                 "      return rs1sRsTestSession\n"
                 "   end if\n"
                 "   if sSession > 0 then\n"
                 "      put sSession into rs1tNew\n"
                 "   else\n"
                 "      try\n"
                 "         put btStartSession() into rs1tNew\n"
                 "      catch rs1tErr\n"
                 "         put 0 into rs1tNew\n"
                 "      end try\n"
                 "   end if\n"
                 "   if rs1tNew is not empty and rs1tNew > 0 then\n"
                 "      put rs1tNew into rs1sRsTestSession\n"
                 "   end if\n"
                 "   if rs1sRsTestSession is empty or rs1sRsTestSession <= 0 then return 0\n"
                 "   return rs1sRsTestSession\n"
                 "end rs1rstAcquireSession\n")
# The core: suArmRun's one timer, the nostrxt call, the harness marker, the
# last results field suBuildAll builds, the cancel list, the summary's first
# note, the three board constants and one member's scope test.
C_ARM = '   send "suRunTick" to me in 33 milliseconds\n'
C_NX_CALL = "            put nx1nxSelfTest() into tNxReport\n"
C_MARKER = "-- GENERATED MEMBER HARNESSES GO HERE --"
C_LAST_AREA = ('   uiArea "suBootLog", "520,142," & (kStWidth - 20) & "," & '
               '(kStHeight - 18)\n')
C_CANCEL = 'if item 3 of tLine is "stPump" or item 3 of tLine is "suRunTick" then'
C_SCOPE_NOTE = '   stNote "Scope:" && suScopeLabel() & "."\n'
C_NAMES = "Riptide Social,No Cloud Quick Share"
C_KEYS = "riptide,nocloud,holde-em,cross"
C_NX_SCOPE = 'if suInScope("nostrxt") then'
C_NOHARNESS = 'constant kSuNoHarness = "nocloud"'
# the one suNoHarness ask inside suRowControls (the loop with "suNote" & tKey)
C_NOHARNESS_ASK = '      if suNoHarness(tKey) then\n         put "suNote" & tKey & comma after tOut'


def handler(name, *body):
    return ("-- (fixture) " + name + "\ncommand " + name + "\n"
            + "".join("   " + ln + "\n" for ln in body)
            + "end " + name + "\n\n")


def add_handler(core, name, *body):
    return swap(core, C_MARKER, handler(name, *body) + C_MARKER, "core marker")


def timer(core, name, body):
    """Arm `name` from suArmRun, cancel it in stCancelPump and define it with
    `body`: a complete new core timer, so a case can get exactly one property
    wrong (through `name` or `body`) and nothing else."""
    core = after(core, C_ARM, f'   send "{name}" to me in 10 milliseconds\n', "suArmRun")
    core = swap(core, C_CANCEL, C_CANCEL.replace(
        " then", f' or item 3 of tLine is "{name}" then'), "stCancelPump")
    return add_handler(core, name, *body)


PINNED = ("local tN", "set the defaultStack to the short name of this stack",
          "put 1 into tN")

# (label, file, mutate, the checks that must fire (empty = must PASS), a
# phrase the output must carry). Every mutate is ONE defect. The file is the
# one the check reads - "paste" or "core" - or "both" for a defect in a core
# DECLARATION: the paste carries the core's declarations, so a person changing
# one edits the core and regenerates, and a core-only edit would (rightly) also
# trip check 10b, which asks that every core declaration reach the paste.
CASES = [
    # ---- 6b: riptide reads the core's session on every call ----
    ("6b: the riptide alias reverted to first-call-only with a fallback start",
     "paste", lambda t: swap(t, P_RIPTIDE, P_RIPTIDE_OLD, "riptide body"),
     {"6b"}, "rs1rstAcquireSession"),
    ("6b: a cached-handle early return put back above the sSession read",
     "paste", lambda t: swap(t, P_RIPTIDE,
                             "   if rs1sRsTestSession > 0 then\n"
                             "      return rs1sRsTestSession\n"
                             "   end if\n" + P_RIPTIDE, "riptide body"),
     {"6b"}, "returns before it reads"),
    ("6b: a fallback btStartSession where zero should mean SKIP",
     "paste", lambda t: swap(t, P_RIPTIDE, P_RIPTIDE.replace(
         "   put 0 into rs1sRsTestSession\n",
         "   try\n      put btStartSession() into rs1sRsTestSession\n"
         "   catch rs1tErr\n      put 0 into rs1sRsTestSession\n   end try\n"),
         "riptide body"),
     {"6b"}, "can start a session"),
    # ---- 7: the folded teardowns stay unreachable, by any spelling ----
    ('7: do "en1stCleanup" in a core handler',
     "paste", lambda t: after(t, P_CLEANUP, '   do "en1stCleanup"\n', "stCleanup"),
     {"7"}, "en1stCleanup is named outside"),
    ('7: dispatch "bt1stCleanup" in a core handler',
     "paste", lambda t: after(t, P_CLEANUP, '   dispatch "bt1stCleanup"\n', "stCleanup"),
     {"7"}, "bt1stCleanup is named outside"),
    ("7: a one-line if that calls dc1stCleanup",
     "paste", lambda t: after(t, P_CLEANUP,
                              '   if sAsyncRunning is "never" then dc1stCleanup\n',
                              "stCleanup"),
     {"7"}, "dc1stCleanup is named outside"),
    ('7: value("en1stCleanup()")',
     "paste", lambda t: after(t, P_CLEANUP, '   get value("en1stCleanup()")\n',
                              "stCleanup"),
     {"7"}, "en1stCleanup is named outside"),
    ('7: send "dc1stCleanup" as a timer',
     "paste", lambda t: after(t, P_CLEANUP,
                              '   send "dc1stCleanup" to me in 1 tick\n', "stCleanup"),
     {"7"}, "dc1stCleanup is named outside"),
    ("7 NEGATIVE: en1stCleanup and friends named only in comments",
     "paste", lambda t: after(t, P_CLEANUP,
                              "   -- en1stCleanup is never called from here\n"
                              "   /* bt1stCleanup, dc1stCleanup: prose */\n",
                              "stCleanup"),
     set(), "check-suite-selftest: OK"),
    # ---- 10 / 10b: declarations above the first handler, moved not lost ----
    ("10: constant kUiBg moved below the paste's first handler",
     "paste", lambda t: swap(swap(t, P_UIBG, "", "kUiBg"), P_FIRST_END,
                             P_FIRST_END + P_UIBG, "first handler"),
     {"10", "10b"}, "kUiBg"),
    ("10b: the hoisted local sScLines dropped from the paste",
     "paste", lambda t: swap(t, P_SCLINES, "", "sScLines"),
     {"10b"}, "local sScLines"),
    ("10b: a hoisted constant copied instead of moved",
     "paste", lambda t: swap(t, P_SCPROBE, P_SCPROBE + P_SCPROBE, "kScProbe"),
     {"1b", "10b"}, "copied instead of moving"),
    # ---- 13b: each entry point is reachable, not merely named ----
    ("13b: nx1nxSelfTest called only from a handler nothing calls",
     "core", lambda t: add_handler(
         swap(t, C_NX_CALL, "            put empty into tNxReport\n", "nostrxt call"),
         "suUnwiredNostr", "local tR", "put nx1nxSelfTest() into tR"),
     {"13b"}, "nx1nxSelfTest is not reachable"),
    # ---- 14: the core names every handler it reaches ----
    ('14: do "suPaintRows"',
     "core", lambda t: after(t, C_ARM, '   do "suPaintRows"\n', "suArmRun"),
     {"14"}, "`do` statement"),
    ('14: dispatch "suPaintRows"',
     "core", lambda t: after(t, C_ARM, '   dispatch "suPaintRows"\n', "suArmRun"),
     {"14"}, "`dispatch` statement"),
    ("14: call, in a one-line if",
     "core", lambda t: after(t, C_ARM,
                             '   if sSuArmed is empty then call "suPaintRows"\n',
                             "suArmRun"),
     {"14"}, "`call` statement"),
    ("14: value(...)",
     "core", lambda t: after(t, C_ARM, '   get value("suNum(1)")\n', "suArmRun"),
     {"14"}, "value(...)"),
    ("14: a send whose message is a variable",
     "core", lambda t: after(t, C_ARM, "   send sSuArmed to me in 10 milliseconds\n",
                             "suArmRun"),
     {"14"}, "sends a computed message"),
    ('14 NEGATIVE: "call site", do, dispatch, value( and send inside a label',
     "core", lambda t: after(t, C_SCOPE_NOTE,
                             '   stNote "a call site: do this, dispatch that, '
                             'value(x), then call it, send tMsg"\n',
                             "suSummaryNotes"),
     set(), "check-suite-selftest: OK"),
    # ---- 15: timers are cancelled, pinned, and not he1* ----
    ('15: send "stStep" to me in 10 milliseconds (uncancelled, undefined)',
     "core", lambda t: after(t, C_ARM, '   send "stStep" to me in 10 milliseconds\n',
                             "suArmRun"),
     {"15"}, "stCancelPump does not"),
    ("15: a new, cancelled timer whose handler does not pin first",
     "core", lambda t: timer(t, "suPokeTick", ("local tN", "put 1 into tN",
                                              "set the defaultStack to the short "
                                              "name of this stack")),
     {"15"}, "suPokeTick (armed at"),
    ("15: a pinned, cancelled core timer spelled he1*",
     "core", lambda t: timer(t, "he1SuTick", PINNED),
     {"15"}, "holde-em's folded sweep"),
    ("15: a cancel entry for a timer nothing arms",
     "core", lambda t: swap(t, C_CANCEL, C_CANCEL.replace(
         " then", ' or item 3 of tLine is "suGoneTick" then'), "stCancelPump"),
     {"15"}, "suGoneTick, which the core never arms"),
    # ---- 16a: the board's control names are the board's ----
    ('16a: uiArea "st_view" (box2dxt wipes st_*)',
     "core", lambda t: after(t, C_LAST_AREA, '   uiArea "st_view", "520,142,600,200"\n',
                             "suBuildAll"),
     {"16a"}, "'st_view'"),
    ('16a: uiLabel "heScore" (holde-em guards on he*)',
     "core", lambda t: after(t, C_LAST_AREA,
                             '   uiLabel "heScore", "0", "20,20,60,40", 10\n',
                             "suBuildAll"),
     {"16a"}, "'heScore'"),
    ('16a: field "stReport" referenced (box2dxt writes its report there)',
     "core", lambda t: after(t, C_LAST_AREA, '   put empty into field "stReport"\n',
                             "suBuildAll"),
     {"16a"}, "'stReport'"),
    ("16a: a computed builder name that does not open with su",
     "core", lambda t: after(t, C_LAST_AREA,
                             '   uiButton ("xRun" & kStTitle), "Run", "0,0,10,10"\n',
                             "suBuildAll"),
     {"16a"}, "does not open with"),
    # ---- 17: the board against tools/member-registry.py ----
    ("17: a registry title changed in kSuNames",
     "both", lambda t: swap(t, C_NAMES, "Riptide,No Cloud Quick Share", "kSuNames"),
     {"17"}, "kSuNames is"),
    ("17: a registry member missing from kSuKeys",
     "both", lambda t: swap(t, C_KEYS, "riptide,holde-em,cross", "kSuKeys"),
     {"17"}, "kSuKeys is"),
    ("17: a row key compared to the kSuNoHarness LIST with `is`",
     "core", lambda t: swap(t, C_NOHARNESS_ASK,
                            C_NOHARNESS_ASK.replace("if suNoHarness(tKey) then",
                                                    "if tKey is kSuNoHarness then"),
                            "suRowControls' suNoHarness ask"),
     {"17"}, "compares a row key to kSuNoHarness with `is`"),
    ("17: kSuNoHarness names a member the generator's NO_HARNESS does not",
     "both", lambda t: swap(t, C_NOHARNESS, 'constant kSuNoHarness = "nocloud,riptide"',
                            "kSuNoHarness"),
     {"17"}, "kSuNoHarness is"),
    ("17: a member's scope test spelled with the wrong key",
     "core", lambda t: swap(t, C_NX_SCOPE, 'if suInScope("nostr") then', "nostrxt scope"),
     {"17"}, 'no `if suInScope("nostrxt")`'),
]


def main():
    all_ok = True

    def verdict(ok, label, detail=""):
        nonlocal all_ok
        print(f"  {'ok  ' if ok else 'FAIL'} {label}")
        if not ok:
            all_ok = False
            if detail:
                print("       " + detail.replace("\n", "\n       "))

    # The build's exact call, on the committed files.
    rc, out = run_gate()
    verdict(rc == 0 and "check-suite-selftest: OK" in out,
            "the committed paste and core pass, called exactly as build-all.sh calls it",
            out)
    if not all_ok:
        return 1

    paste_text = open(PASTE, encoding="utf-8").read()
    core_text = open(CORE, encoding="utf-8").read()
    # The core's own report text is check 14's standing negative control: if
    # it ever stops carrying "call site" in a literal, say so, rather than let
    # the control silently test nothing.
    verdict(len(re.findall(r'^\s*stNote "[^"]*\bcall site\b', core_text, re.M)) >= 1,
            "the core still carries 'call site' inside a report literal "
            "(check 14's standing negative control)")

    with tempfile.TemporaryDirectory(prefix="suite-selftest-fixture-") as tmp:
        base_paste = os.path.join(tmp, "suite-selftest.livecodescript")
        base_core = os.path.join(tmp, "suite-selftest.core.livecodescript")
        shutil.copyfile(PASTE, base_paste)
        shutil.copyfile(CORE, base_core)
        rc, out = run_gate(base_paste, "--core", base_core)
        verdict(rc == 0 and "check-suite-selftest: OK" in out,
                "untouched scratch copies pass (the path arguments are honoured)", out)

        jobs = []
        for n, (label, which, mutate, want, phrase) in enumerate(CASES):
            paths = {"paste": base_paste, "core": base_core}
            try:
                for kind, text in (("paste", paste_text), ("core", core_text)):
                    if which in (kind, "both"):
                        paths[kind] = os.path.join(
                            tmp, f"case{n:02d}-{kind}.livecodescript")
                        with open(paths[kind], "w", encoding="utf-8") as fh:
                            fh.write(mutate(text))
            except Stale as exc:
                verdict(False, label, f"FIXTURE STALE: {exc}")
                continue
            jobs.append((label, want, phrase,
                         (paths["paste"], "--core", paths["core"])))

        workers = max(2, min(8, os.cpu_count() or 2))
        with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as pool:
            results = list(pool.map(lambda j: run_gate(*j[3]), jobs))
        for (label, want, phrase, _), (rc, out) in zip(jobs, results):
            fired = tags(out)
            if want:
                ok = rc == 1 and fired == want and phrase in out
                why = (f"want rc=1, checks {sorted(want)} and {phrase!r}; got "
                       f"rc={rc}, checks {sorted(fired)}:\n{out}")
            else:
                ok = rc == 0 and phrase in out
                why = f"a negative control must PASS; got rc={rc}:\n{out}"
            verdict(ok, label, why)

    if all_ok:
        print(f"test-suite-selftest: OK ({len(CASES)} mutations and negative "
              f"controls behaved, the clean files pass)")
        return 0
    print("test-suite-selftest: FAILED")
    return 1


if __name__ == "__main__":
    sys.exit(main())
