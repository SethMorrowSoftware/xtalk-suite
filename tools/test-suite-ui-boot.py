#!/usr/bin/env python3
"""test-suite-ui-boot.py - prove tools/check-suite-ui-boot.py FAILS on each
defect it exists to catch, the way tools/build-all.sh runs it.

WHY THIS EXISTS
---------------
A blind gate still prints OK (root CLAUDE.md: fixture before gate). The board
gate asserts hundreds of things about a model of a window, and every one of
them could be reading the model instead of the board - so each defect below is
seeded into a SCRATCH COPY of the generated paste (the committed file is never
touched), the gate is run on that copy as a subprocess with --paste, exactly
as build-all.sh would run it on the real one, and the run must:

  1. exit 1 (0 is a blind gate; 2 is a setup failure, not a catch);
  2. print the check that names the defect (the WHY column below) - a gate
     that failed for some other reason has not proven it can see this one;
  3. print no Python traceback (a crash is not a catch).

Each needle must occur EXACTLY ONCE in the paste, so a fixture cannot go stale
by silently matching nothing, or seed the defect in the wrong place. A clean
run on the committed paste must pass, or every "catch" below means nothing.

THE DEFECTS, one per thing the gate is for
------------------------------------------
  a  suLineKind reads the first four characters instead of the first word,
     so an INDENTED FAIL (every returned report's `  FAIL`) is not a FAIL:
     it vanishes from the Failures view and stays unpainted.
  b  the suTallyClose after the SodiumXT sampler in stRun is gone: the open
     tally swallows the deep-harness header (the run's own lines), so the
     sodiumxt row's Show prints lines the row does not own. The totals still
     balance - suTallyOpen closes a dangling mark - which is exactly why the
     member view is derived from the design and not from the spans.
  c  suRowState answers kind "warn" for OK: a kind the kit's uiPill does not
     know, painted in the title band's navy.
  d  stFinish never calls stReportDone: sStRunDone never turns true, the
     report never repaints, the trailer never goes.
  e  suArmRun's refusal no longer looks at sAsyncRunning: a second row's Run
     arms while the first run's pump is live.

And three that prove the gate's MODEL DELTAS are load-bearing:

  f  stCancelPump cancels only stPump, so closing with a Run armed leaves
     its tick queued (the pendingMessages and cancel deltas; without them the
     runner cannot run stCancelPump at all).
  g  the Failures button keeps autoHilite, so the engine clears its hilite
     at release and the view loses its mark (the autohilite delta). Measured
     2026-09-24 with the delta switched off in a scratch copy: the gate then
     passes this mutant on every board check - blind.
  h  suRenderView paints only while the run is live, so the finished view is
     written and left unpainted - and on the Failures view its FAIL lines sit
     on the very line numbers the live render painted (the gate orders its
     presses to make it so). Measured the same way: with the field-replace
     delta off, the Failures-view check this fixture requires PASSES on the
     live render's colours; only the Skips and Show views, whose line numbers
     moved, still caught the mutant.

The mutants run concurrently, at most one gate run per core.

USAGE
    python3 tools/test-suite-ui-boot.py
"""

import concurrent.futures
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GATE = os.path.join(HERE, "check-suite-ui-boot.py")
PASTE = os.path.join(ROOT, "tests", "suite-selftest.livecodescript")
TIMEOUT = 600

# (id, what the defect is, needle, replacement, a line the gate must print)
MUTANTS = [
    ("a", "suLineKind tests the first four characters, not the first word",
     '   if tW1 is "FAIL" then\n      put "fail" into tKind',
     '   if char 1 to 4 of pLine is "FAIL" then\n      put "fail" into tKind',
     "the fail view holds every FAIL line of the report"),
    ("b", "the SodiumXT sampler's suTallyClose is deleted from stRun",
     '         stSectionFailed "SodiumXT", tError\n      end try\n'
     '      suTallyClose\n',
     '         stSectionFailed "SodiumXT", tError\n      end try\n',
     "Show sodiumxt is exactly the lines its row owns"),
    ("c", "suRowState answers kind warn for an OK row",
     '      return "ok" & return & "OK"',
     '      return "warn" & return & "OK"',
     "never the navy default"),
    ("d", "stFinish no longer calls stReportDone",
     '   put empty into sAsyncRunning\n   stReportDone\n   suAfterDone\n',
     '   put empty into sAsyncRunning\n   suAfterDone\n',
     "sStRunDone is true"),
    ("e", "suArmRun's refusal no longer looks at sAsyncRunning",
     '   if sAsyncRunning is "true" or sSuArmed is not empty then',
     '   if sSuArmed is not empty then',
     "live: nothing new is armed"),
    # Three more, each proving a MODEL DELTA is load-bearing rather than a
    # decoration: without the delta the gate could not see the defect.
    ("f", "stCancelPump no longer cancels an armed Run's tick (the "
          "pendingMessages / cancel deltas)",
     '      if item 3 of tLine is "stPump" or item 3 of tLine is "suRunTick" '
     'then',
     '      if item 3 of tLine is "stPump" then',
     "closing with a Run armed cancels its tick and forgets it"),
    ("g", "the Failures button keeps the engine's autoHilite (the autohilite "
          "delta: a click would clear the view's mark)",
     '   set the autoHilite of button "suFilterFail" to false\n',
     '',
     "the filter buttons' hilite marks the view after the release"),
    ("h", "suRenderView paints only while the run is live (the "
          "field-replace delta: the live render's colours must not pass for "
          "the finished one's)",
     '         put tText into field "suView"\n         suPaintView\n',
     '         put tText into field "suView"\n'
     '         if sStRunDone is not "true" then\n'
     '            suPaintView\n'
     '         end if\n',
     "(finished) every line of the fail view is painted by its kind"),
]


def run_gate(path):
    """(exit code, output) of one gate run; a run past TIMEOUT is reported as
    exit None - a hang is a failure to name, not a traceback to read."""
    try:
        proc = subprocess.run([sys.executable, GATE, "--paste", path],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout or ""
        if isinstance(out, bytes):
            out = out.decode("utf-8", "replace")
        return None, out + "\n(no verdict in %d s: the gate hung)" % TIMEOUT
    return proc.returncode, proc.stdout


def one(mutant, paste, scratch):
    mid, what, needle, repl, must = mutant
    hits = paste.count(needle)
    if hits != 1:
        return ["%s (%s): the needle occurs %d times in the paste, not once - "
                "the fixture is stale; re-read the core and update it"
                % (mid, what, hits)]
    path = os.path.join(scratch, "mutant-%s.livecodescript" % mid)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(paste.replace(needle, repl, 1))
    code, out = run_gate(path)
    problems = []
    if code != 1:
        problems.append("%s (%s): the gate exited %s, not 1 - %s"
                        % (mid, what, code,
                           "it is BLIND to this defect" if code == 0
                           else "it hung" if code is None
                           else "a setup failure is not a catch"))
    if must not in out:
        problems.append("%s (%s): the gate never printed %r, so it did not "
                        "fail for THIS reason" % (mid, what, must))
    if "Traceback" in out:
        problems.append("%s (%s): the gate crashed (a traceback is not a "
                        "catch)" % (mid, what))
    if problems:
        tail = "\n".join(out.strip().split("\n")[-12:])
        problems.append("   last lines of that run:\n      "
                        + tail.replace("\n", "\n      "))
    return problems


def main():
    with open(PASTE, encoding="utf-8") as fh:
        paste = fh.read()
    scratch = tempfile.mkdtemp(prefix="test-suite-ui-boot-")
    problems = []
    try:
        # one gate run per core at most: the runs are CPU-bound, and more
        # workers than cores only stretch every run's wall clock
        with concurrent.futures.ThreadPoolExecutor(
                max_workers=max(1, min(len(MUTANTS) + 1,
                                       os.cpu_count() or 1))) as pool:
            clean = pool.submit(run_gate, PASTE)
            futs = [(m, pool.submit(one, m, paste, scratch)) for m in MUTANTS]
            code, out = clean.result()
            if code != 0 or "check-suite-ui-boot: OK" not in out:
                problems.append("the CLEAN paste did not pass (exit %s), so no "
                                "catch below means anything:\n      %s"
                                % (code, "\n      ".join(
                                    out.strip().split("\n")[-12:])))
            for mutant, fut in futs:
                got = fut.result()
                problems.extend(got)
                print("  %s  %-4s %s" % ("ok  " if not got else "FAIL",
                                         mutant[0], mutant[1]))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    if problems:
        print("test-suite-ui-boot: FAIL\n  " + "\n  ".join(problems))
        return 1
    print("test-suite-ui-boot: OK (the clean paste passes, and all %d seeded "
          "defects fail the gate, each on the check that names it)"
          % len(MUTANTS))
    return 0


if __name__ == "__main__":
    sys.exit(main())
