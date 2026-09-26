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

  f  stCancelPump cancels only suPump, so closing with a Run armed leaves
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

And four for what a review found on 2026-09-25, each invisible to the gate
until that day:

  i  stCancelPump cancels "stPump" again: the name enet-selftest's and
     datachannel-selftest's own pumps use, so a loopback running in either
     window dies when the paste opens (the model's foreign timers).
  j  suBootPending reads a fired probe as still pending (it used to read
     `the pendingMessages`, where every demo's "scTickProbe" looks alike).
  k  the stamped build no longer re-asserts 1200 x 640, so a window resized
     and reopened turns the boot self-check red over a green run.
  l  riptide's summary line goes back to two counts: its skips are printed
     and never merged, and the Skips view disagrees with the summary.

And six for the transports' process-wide holds (work plan suite-wide #16,
the gate's one scenario with modelled natives: another stack holds ENet and
a DataChannel peer beside the paste):

  m  stCleanup's release is the old bare enDeinitialize, so opening the
     paste gives back a hold it never took and the other stack's host dies.
  n  the folded enetxt harness's two inits go uncounted again (the
     generator's rewrite undone), so the run leaks two holds.
  o  stCleanup's release is the old bare dcCleanup, so opening the paste
     frees the other stack's DataChannel peer.
  p  suEnRelease gives back one hold more than it counted.
  q  suEnInit counts a refused enInitialize, so the teardown gives back
     holds the paste never took.
  r  the loopback goes on to bind after a refused enInitialize (the old
     start: a refusal read as a held port).

And one for the review of work plan suite-wide #15 (2026-09-26), which found
the core's comment saying the gate checks stCancelPump's delimiter restore
when nothing did (the restore could go and the gate stayed green, measured):

  s  stCancelPump no longer puts back the itemDelimiter it found. Under the
     model's GLOBAL delimiter a caller's "|" comes back as comma; on the
     Windows and Linux engines (handler-local, engine note 2.3) it could
     not reach the handler, so this pins the family's rule, not an engine
     hazard.

The mutants run concurrently, at most one gate run per core.

THE --full MUTANTS (python3 tools/test-suite-ui-boot.py --full)
---------------------------------------------------------------
The gate's --full profile (Run all over the whole paste, every member
folded, as openStack starts it) is the step before an engine session, not a
per-push gate, and so is its fixture: each case is one whole interpreted Run
all, minutes long (the gate's docstring has the measured wall time and the
reason it stays out of build-all --gates). Run it first, then the gate, per
docs/OXT-PASS-RUNBOOK.md section 3.2. Each defect must be caught BY NAME:

  F1  a folded harness throws: riptide's rs1rsSelfTest raises before its
      first section. The core's per-member catch reports the section; the
      gate must name the handler the error was raised in, and its line.
  F2  the interpreter REFUSES a statement inside a folded holde-em section
      (a hexadecimal text compared with a decimal one, engine note 2.11): a
      refusal is no script error, so no script catch sees it, and it would
      take the whole run. The gate must name the section and the handler.
  F3  a row miscounts: holde-em's block is counted to no row (its
      suTallyOpen deleted), so the rows no longer add up to the totals.
  F4  the teardown never runs: stFinish's stTeardown call is deleted.

And two a review found on 2026-09-26, each GREEN against the gate as first
written (so each check they name was made exact for them):

  F5  a misspelt native call: holde-em's SodiumXT probe calls
      sxRandmUniform. The run is exactly an absent library's, so only the
      can't-find-handler check can see it, and it did not while an absent
      native was any undefined name with a native prefix; it is now a
      public handler a native member's .lcb declares.
  F6  the teardown moves from stFinish to the pump's last tick, counted to
      its row: once, before the summary, every count adding up. The check
      said "from stFinish" and counted calls; it now reads the caller.

A clean --full run on the committed paste must pass first, as above.

USAGE
    python3 tools/test-suite-ui-boot.py           # the fast tier's mutants
    python3 tools/test-suite-ui-boot.py --full    # the --full profile's
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
     '      if item 3 of tLine is "suPump" or item 3 of tLine is "suRunTick" '
     'then',
     '      if item 3 of tLine is "suPump" then',
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
    # Four for the 2026-09-25 review's findings, each gated since that day.
    ("i", "stCancelPump cancels the old pump name again, which is also "
          "enet-selftest's and datachannel-selftest's (a foreign timer)",
     '      if item 3 of tLine is "suPump" or item 3 of tLine is "suRunTick" '
     'then',
     '      if item 3 of tLine is "suPump" or item 3 of tLine is "suRunTick" '
     'or item 3 of tLine is "stPump" then',
     "stCancelPump leaves another stack's pump and probe queued"),
    ("j", "suBootPending ignores the self-check's finished count line, so a "
          "fired probe still reads as pending",
     '      if not tDone then\n         return true\n',
     '      if true then\n         return true\n',
     "suBootPending does not read another demo's pending probe"),
    ("k", "suBuild's stamped path no longer puts a resized window back",
     '         if the width of this stack is not kStWidth then\n'
     '            set the width of this stack to kStWidth\n'
     '         end if\n'
     '         if the height of this stack is not kStHeight then\n'
     '            set the height of this stack to kStHeight\n'
     '         end if\n',
     '',
     "a stamped build over a resized window puts it back"),
    ("l", "riptide's summary goes back to two counts, its skip count on a "
          "prose line the merge never reads",
     '   return rs1sPass && "passed," && rs1sFail && "failed," && rs1sSkip '
     '&& "skipped" & \\\n'
     '         return & "(the skips are optional dependencies; see the log)" '
     '& \\\n',
     '   return rs1sPass && "passed," && rs1sFail && "failed" & \\\n'
     '         return & rs1sSkip && "skipped (optional dependencies; see the '
     'log)" & \\\n',
     "the report's SKIP-kind lines are the totals' skipped count"),
    # Six for the transports' process-wide holds (work plan suite-wide #16,
    # scenario_transport_holds). m and o are the pre-2026-09-25 core put
    # back; n is the fold before the generator routed its inits.
    ("m", "stCleanup's release is the old bare enDeinitialize, called on "
          "every open before any initialize",
     '      suEnRelease false\n',
     '      enDeinitialize\n',
     "open (stCleanup before any run): the other stack's ENet host is alive"),
    ("n", "the folded enetxt harness initializes uncounted (the generator's "
          "rewrite undone)",
     '   en1stAssert "enInitialize returns 0", suEnInit() is 0\n'
     '   en1stAssert "enInitialize idempotent", suEnInit() is 0\n',
     '   en1stAssert "enInitialize returns 0", enInitialize() is 0\n'
     '   en1stAssert "enInitialize idempotent", enInitialize() is 0\n',
     "the enetxt run took three holds"),
    ("o", "stCleanup's release is the old bare dcCleanup, called on every "
          "open",
     '      suDcRelease false\n',
     '      dcCleanup\n',
     "open (stCleanup before any run): no dcCleanup without a DataChannel "
     "hold of the paste's own"),
    ("p", "suEnRelease gives back one more hold than it counted",
     '   repeat while sSuEnHeld > 0\n',
     '   repeat while sSuEnHeld >= 0\n',
     "open (stCleanup before any run): the paste never gave back an ENet "
     "hold it did not take"),
    ("q", "suEnInit counts a refused enInitialize",
     '   put enInitialize() into tR\n   if tR is 0 then\n',
     '   put enInitialize() into tR\n   if tR is not empty then\n',
     "three refused enInitialize calls are counted as no hold"),
    ("r", "the loopback goes on to bind after a refused enInitialize",
     '   if tInit is not 0 then\n      put "failed" into sPhaseEn\n'
     '      exit stStartEnetLoopback\n   end if\n',
     '',
     "and the loopback stopped at the refusal: no host was attempted"),
    # One for the suite-wide #15 review: a restore no check could see go.
    ("s", "stCancelPump no longer restores the itemDelimiter it found",
     '   end repeat\n   set the itemDelimiter to tOld\n'
     '   put empty into sSuArmed\n',
     '   end repeat\n   put empty into sSuArmed\n',
     "stCancelPump hands its caller's itemDelimiter back"),
]


# The --full profile's mutants (the header's F list). Each `must` is a tuple:
# the check that names the defect, and what the name must carry.
FULL_MUTANTS = [
    ("F1", "a folded harness throws: riptide's rs1rsSelfTest raises before "
           "its first section",
     '   put 0 into rs1sSkip\n   put rsProbeCapabilities() into rs1tCaps\n',
     '   put 0 into rs1sSkip\n   throw "fixture F1: planted in riptide"\n'
     '   put rsProbeCapabilities() into rs1tCaps\n',
     ("no section threw", "raised in rs1rsSelfTest",
      'throw "fixture F1: planted in riptide"')),
    ("F2", "the interpreter refuses a statement inside a folded holde-em "
           "section (a hex text against a decimal one)",
     '"-- 21. Pure helpers: leaf values nothing else pinned (shallow)" & '
     'return after he1gRpt\n',
     '"-- 21. Pure helpers: leaf values nothing else pinned (shallow)" & '
     'return after he1gRpt\n   get "0x10" is "16"\n',
     ("the interpreter refused nothing", "he1heSelfTest",
      "he1heTestHelpersRun", 'get "0x10" is "16"')),
    ("F3", "a row miscounts: holde-em's block is counted to no row (its "
           "suTallyOpen deleted)",
     '   if suInScope("holde-em") then\n      suTallyOpen "holde-em"\n',
     '   if suInScope("holde-em") then\n',
     ("the rows add up to the totals line",)),
    ("F4", "the teardown never runs: stFinish's stTeardown call deleted",
     '   try\n      stTeardown\n   catch tError\n'
     '      stSectionFailed "teardown", tError\n',
     '   try\n   catch tError\n      stSectionFailed "teardown", tError\n',
     ("stFinish ran once and stTeardown ran once",)),
    # Found by review, 2026-09-26: each was GREEN against the gate as first
    # written, and each check it now fails was made exact for it.
    ("F5", "a misspelt native call: holde-em's SodiumXT probe calls "
           "sxRandmUniform, which no .lcb declares",
     '         get sxRandomUniform(2)\n'
     '         put "true" into he1gHasSodiumChk\n',
     '         get sxRandmUniform(2)\n'
     '         put "true" into he1gHasSodiumChk\n',
     ("every can't-find-handler the run raised names an ABSENT native",
      "sxRandmUniform")),
    ("F6", "the teardown moves out of stFinish into the pump's last tick "
           "(counted to its row, so every count still adds up)",
     ('   try\n      stTeardown\n   catch tError\n'
      '      stSectionFailed "teardown", tError\n',
      '   if stEnDone() and stDcDone() then\n      stFinish\n'),
     ('   try\n   catch tError\n      stSectionFailed "teardown", tError\n',
      '   if stEnDone() and stDcDone() then\n      suTallyOpen "cross"\n'
      '      stTeardown\n      suTallyClose\n      stFinish\n'),
     ("stTeardown's call came from stFinish",)),
]
# One whole interpreted Run all per case, at most one case per core.
FULL_TIMEOUT = 5400


def run_gate(path, full=False):
    """(exit code, output) of one gate run; a run past its timeout is
    reported as exit None - a hang is a failure to name, not a traceback to
    read."""
    limit = FULL_TIMEOUT if full else TIMEOUT
    cmd = [sys.executable, GATE, "--paste", path] + (["--full"] if full
                                                    else [])
    try:
        proc = subprocess.run(cmd, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT, text=True,
                              timeout=limit)
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout or ""
        if isinstance(out, bytes):
            out = out.decode("utf-8", "replace")
        return None, out + "\n(no verdict in %d s: the gate hung)" % limit
    return proc.returncode, proc.stdout


def one(mutant, paste, scratch, full=False):
    mid, what, needle, repl, must = mutant
    # A mutant is one edit, or (F6) a tuple of edits applied in order, each
    # needle required exactly once in the text it is applied to.
    edits = (list(zip(needle, repl)) if isinstance(needle, tuple)
             else [(needle, repl)])
    text = paste
    for k, (nd, rp) in enumerate(edits, 1):
        hits = text.count(nd)
        if hits != 1:
            return ["%s (%s): needle %d of %d occurs %d times in the paste, "
                    "not once - the fixture is stale; re-read the core and "
                    "update it" % (mid, what, k, len(edits), hits)]
        text = text.replace(nd, rp, 1)
    path = os.path.join(scratch, "mutant-%s.livecodescript" % mid)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    code, out = run_gate(path, full)
    problems = []
    if code != 1:
        problems.append("%s (%s): the gate exited %s, not 1 - %s"
                        % (mid, what, code,
                           "it is BLIND to this defect" if code == 0
                           else "it hung" if code is None
                           else "a setup failure is not a catch"))
    for need in ((must,) if isinstance(must, str) else must):
        if need not in out:
            problems.append("%s (%s): the gate never printed %r, so it did "
                            "not fail for THIS reason, or did not name it"
                            % (mid, what, need))
    if "Traceback" in out:
        problems.append("%s (%s): the gate crashed (a traceback is not a "
                        "catch)" % (mid, what))
    if problems:
        tail = "\n".join(out.strip().split("\n")[-12:])
        problems.append("   last lines of that run:\n      "
                        + tail.replace("\n", "\n      "))
    return problems


def main(argv):
    full = "--full" in argv
    mutants = FULL_MUTANTS if full else MUTANTS
    ok_line = ("check-suite-ui-boot --full: OK" if full
               else "check-suite-ui-boot: OK")
    with open(PASTE, encoding="utf-8") as fh:
        paste = fh.read()
    scratch = tempfile.mkdtemp(prefix="test-suite-ui-boot-")
    problems = []
    try:
        # one gate run per core at most: the runs are CPU-bound, and more
        # workers than cores only stretch every run's wall clock
        with concurrent.futures.ThreadPoolExecutor(
                max_workers=max(1, min(len(mutants) + 1,
                                       os.cpu_count() or 1))) as pool:
            clean = pool.submit(run_gate, PASTE, full)
            futs = [(m, pool.submit(one, m, paste, scratch, full))
                    for m in mutants]
            code, out = clean.result()
            if code != 0 or ok_line not in out:
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
    print("test-suite-ui-boot%s: OK (the clean paste passes, and all %d "
          "seeded defects fail the gate, each on the check that names it)"
          % (" --full" if full else "", len(mutants)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
