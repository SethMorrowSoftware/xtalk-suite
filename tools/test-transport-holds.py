#!/usr/bin/env python3
"""test-transport-holds.py - prove tools/check-transport-holds.py FAILS on
each defect it exists to catch, the way tools/build-all.sh runs it.

WHY THIS EXISTS
---------------
A blind gate still prints OK (root CLAUDE.md: fixture before gate). The gate
drives two windows through a model, and every check could be reading the
model instead of the window - so each defect below is seeded into a SCRATCH
COPY of enetxt/tests/enet-selftest.livecodescript or
tests/suite-closing-pass.livecodescript (the committed files are never
touched), the gate is run on that copy as a subprocess with --selftest or
--closing, and the run must:

  1. exit 1 (0 is a blind gate; 2 is a setup failure, not a catch);
  2. print every check that names the defect (a gate that failed for some
     other reason has not proven it can see this one);
  3. print no Python traceback (a crash is not a catch).

Each needle must occur EXACTLY ONCE in its file, so a fixture cannot go
stale by silently matching nothing. A clean run on the committed files must
pass, or every "catch" means nothing; so must each NEGATIVE control, a
planted line the gate must NOT refuse.

THE DEFECTS (the work plan's enetxt #4 and suite-wide #20)
----------------------------------------------------------
Most put one OLD line back: the code before 2026-09-26.

enet-selftest:
  eA  stCleanup gives back with the old bare enDeinitialize: a close at rest
      takes the other stack's hold and ends its host (the defect itself).
  eB  stFinish gives back with the old two bare calls, beside the counted
      inits: the run's two holds go back at the finish, and the close gives
      back two more.
  eC  stRun's two inits go uncounted again (the old bare enInitialize): the
      run's holds are never given back.
  eD  the no-op leg is the old bare call, with no probe: beside another
      holder it is the call that takes that holder's hold.
  eE  stEnRelease gives back one more hold than it counted.
  eF  stEnInit counts a refused enInitialize: a refused run gives back a
      hold another stack took mid-run.
  eG  the no-op leg leaves its probe host alive.
  eH  the no-op leg reads any refused probe as "the count is zero".

the closing pass:
  cA  closeStack gives back with the old bare enDeinitialize: a close with
      no leg run takes the other stack's hold (the defect itself).
  cB  cpBStart takes its hold before the "already hosting" refusal (the old
      order): a second Host press takes a hold.
  cC  cpBStart's init goes uncounted again (the old `get enInitialize()`):
      leg B's hold is never given back.
  cD  closeStack calls dcCleanup bare: a close with no leg run frees the
      other stack's DataChannel peer.
  cE  cpDcInit counts a refused dcInit (the old flag was set either way).
  cF  leg A goes on after a refused dcInit and makes its peers.
  cG  cpEnRelease gives back one more hold than it counted.
  cH  cpEnInit counts a refused enInitialize.

And the ROUTING half's own, each on a path no scenario drives:

  rA  a bare enDeinitialize in the closing pass's leg F (cpFStop).
  rB  dcCleanup named by a `send` literal in cpFStop.
  rC  a count written outside its handlers (cpBCheckStuck).
  rD  an enInitialize in enet-selftest's stHandleServer.

NEGATIVE controls (the gate must pass): prose naming every library call in
a comment and in a status literal, in both files.

USAGE
    python3 tools/test-transport-holds.py
"""

import concurrent.futures
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GATE = os.path.join(HERE, "check-transport-holds.py")
FILES = {
    "selftest": os.path.join(ROOT, "enetxt", "tests",
                             "enet-selftest.livecodescript"),
    "closing": os.path.join(ROOT, "tests", "suite-closing-pass.livecodescript"),
}
TIMEOUT = 600

EN_INIT = ('   stAssert "enInitialize returns 0", stEnInit() is 0\n'
           '   stAssert "enInitialize idempotent", stEnInit() is 0\n')
CP_REFUSE_THEN_INIT = (
    '   if sEnHost is an integer and sEnHost > 0 then\n'
    '      cpSay "cpBOut", "already hosting or joined; restart OXT to re-run '
    'this leg cleanly"\n'
    '      exit cpBStart\n'
    '   end if\n'
    '   try\n'
    '      put cpEnInit() into tR\n'
    '   catch tErr\n'
    '      cpSay "cpBOut", "enetxt missing:" && tErr\n'
    '      exit cpBStart\n'
    '   end try\n')
CP_INIT_THEN_REFUSE = (
    '   try\n'
    '      put cpEnInit() into tR\n'
    '   catch tErr\n'
    '      cpSay "cpBOut", "enetxt missing:" && tErr\n'
    '      exit cpBStart\n'
    '   end try\n'
    '   if sEnHost is an integer and sEnHost > 0 then\n'
    '      cpSay "cpBOut", "already hosting or joined; restart OXT to re-run '
    'this leg cleanly"\n'
    '      exit cpBStart\n'
    '   end if\n')
CP_FSTOP = 'command cpFStop\n   local tErr\n'

# (id, file, what the defect is, needle, replacement, lines the gate must
#  print). An empty `must` is a NEGATIVE control: the gate must pass.
MUTANTS = [
    ("eA", "selftest", "stCleanup gives back with the old bare enDeinitialize",
     '      stEnRelease false\n', '      enDeinitialize\n',
     ("a close at rest: the other stack's ENet host is alive",
      "enDeinitialize is called only by stEnRelease and stEnNoOpLeg")),
    ("eB", "selftest", "stFinish gives back with the old two bare calls",
     '   stEnRelease true\n   stEnNoOpLeg\n',
     '   stAssert "enDeinitialize returns 0", enDeinitialize() is 0\n'
     '   stAssert "extra deinitialize is a no-op 0", enDeinitialize() is 0\n',
     ("a close at rest: no deinitialize took a hold this window never had",)),
    ("eC", "selftest", "stRun's two inits go uncounted again",
     EN_INIT, EN_INIT.replace("stEnInit()", "enInitialize()"),
     ("the run took two holds (stRun's two enInitialize calls) and counts "
      "them",
      "after the run's finish: the process count is the other stack's alone "
      "(1)")),
    ("eD", "selftest", "the no-op leg is the old bare call, with no probe",
     '   stEnNoOpLeg\n',
     '   stAssert "extra deinitialize is a no-op 0", enDeinitialize() is 0\n',
     ("after the run's finish: no deinitialize took a hold this window never "
      "had",)),
    ("eE", "selftest", "stEnRelease gives back one more than it counted",
     '   repeat while sStEnHeld > 0\n', '   repeat while sStEnHeld >= 0\n',
     ("after the run's finish: no deinitialize took a hold this window never "
      "had",)),
    ("eF", "selftest", "stEnInit counts a refused enInitialize",
     '   put enInitialize() into tR\n   if tR is 0 then\n',
     '   put enInitialize() into tR\n   if tR is not empty then\n',
     ("two refused enInitialize calls are counted as no hold",
      "the refused run's finish, the other stack holding: the other stack's "
      "ENet host is alive")),
    ("eG", "selftest", "the no-op leg leaves its probe host alive",
     '      enHostDestroy tProbe\n', '',
     ("the no-op leg asked the shim with a probe host, and destroyed it",
      "after the run's finish: this window's hosts are destroyed")),
    ("eH", "selftest", "the no-op leg reads any refused probe as a count of "
                       "zero",
     '   if tProbe is 0 and tWhy is "call enInitialize first" then\n',
     '   if tProbe is 0 then\n',
     ("a probe refused for another reason: no call was made",)),
    ("cA", "closing", "closeStack gives back with the old bare enDeinitialize",
     '      cpEnRelease\n', '      enDeinitialize\n',
     ("a close with no leg run: the other stack's ENet host is alive",
      "enDeinitialize is called only by cpEnRelease")),
    ("cB", "closing", "cpBStart takes its hold before the \"already "
                      "hosting\" refusal (the old order)",
     CP_REFUSE_THEN_INIT, CP_INIT_THEN_REFUSE,
     ("... BEFORE a hold is taken (one hold, one host)",)),
    ("cC", "closing", "cpBStart's init goes uncounted again",
     '      put cpEnInit() into tR\n',
     '      get enInitialize()\n      put 0 into tR\n',
     ("leg B Host's close: the process count is the other stack's alone (1)",
      "enInitialize is called only by cpEnInit")),
    ("cD", "closing", "closeStack calls dcCleanup bare",
     '      cpDcRelease\n', '      dcCleanup\n',
     ("a close with no leg run: no dcCleanup without a DataChannel hold of "
      "this window's own",)),
    ("cE", "closing", "cpDcInit counts a refused dcInit (the old flag)",
     '   put dcInit() into tR\n   if tR is 0 then\n',
     '   put dcInit() into tR\n   if tR is not empty then\n',
     ("leg A refused, its close: no dcCleanup without a DataChannel hold of "
      "this window's own",)),
    ("cF", "closing", "leg A goes on after a refused dcInit",
     '   if tR is not 0 then\n'
     '      cpSay "cpAOut", "dcInit refused (" & tR & "):" && dcLastError()\n'
     '      exit cpARun\n'
     '   end if\n', '',
     ("... and stopped there: no peer was made",)),
    ("cG", "closing", "cpEnRelease gives back one more than it counted",
     '   repeat while sCpEnHeld > 0\n', '   repeat while sCpEnHeld >= 0\n',
     ("a close with no leg run: no deinitialize took a hold this window "
      "never had",)),
    ("cH", "closing", "cpEnInit counts a refused enInitialize",
     '   put enInitialize() into tR\n   if tR is 0 then\n',
     '   put enInitialize() into tR\n   if tR is not empty then\n',
     ("the refused leg's close: the other stack's ENet host is alive",)),
    ("rA", "closing", "a bare enDeinitialize in leg F (cpFStop)",
     CP_FSTOP, CP_FSTOP + '   enDeinitialize\n',
     ("enDeinitialize is called only by cpEnRelease",)),
    ("rB", "closing", "dcCleanup named by a send literal in cpFStop",
     CP_FSTOP, CP_FSTOP + '   send "dcCleanup" to me in 10 milliseconds\n',
     ("dcCleanup is called only by cpDcRelease",)),
    ("rC", "closing", "a count written outside its handlers",
     '   set the defaultStack to the short name of this stack\n'
     '   if sEnRole is not "join" or sEnConnected is "true" then\n',
     '   set the defaultStack to the short name of this stack\n'
     '   put 0 into sCpEnHeld\n'
     '   if sEnRole is not "join" or sEnConnected is "true" then\n',
     ("sCpEnHeld is named only by cpEnInit, cpEnRelease",)),
    ("rD", "selftest", "an enInitialize in stHandleServer",
     'command stHandleServer pEvent\n   local tR\n',
     'command stHandleServer pEvent\n   local tR\n   get enInitialize()\n',
     ("enInitialize is called only by stEnInit",)),
    # NEGATIVE controls: prose and labels are not calls
    ("n1", "closing", "NEGATIVE: every library name in a comment and a "
                      "status literal (leg F)",
     CP_FSTOP, CP_FSTOP + '   -- enDeinitialize, dcCleanup, enInitialize, '
                          'dcInit, sCpEnHeld: prose\n'
                          '   cpSay "cpFOut", "enDeinitialize and dcCleanup '
                          'are counted; sCpDcHeld too"\n', ()),
    ("n2", "selftest", "NEGATIVE: every library name in a comment and a "
                       "note literal (stHandleServer)",
     'command stHandleServer pEvent\n   local tR\n',
     'command stHandleServer pEvent\n   local tR\n'
     '   -- enInitialize and enDeinitialize: prose, and sStEnHeld too\n'
     '   stNote "enInitialize and enDeinitialize are counted in sStEnHeld"\n',
     ()),
]


def run_gate(args):
    try:
        proc = subprocess.run([sys.executable, GATE] + args,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                              text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout or ""
        if isinstance(out, bytes):
            out = out.decode("utf-8", "replace")
        return None, out + "\n(no verdict in %d s: the gate hung)" % TIMEOUT
    return proc.returncode, proc.stdout


def one(mutant, texts, scratch):
    mid, key, what, needle, repl, must = mutant
    text = texts[key]
    hits = text.count(needle)
    if hits != 1:
        return ["%s (%s): the needle occurs %d times in %s, not once - the "
                "fixture is stale; re-read the file and update it"
                % (mid, what, hits, os.path.relpath(FILES[key], ROOT))]
    path = os.path.join(scratch, "mutant-%s.livecodescript" % mid)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text.replace(needle, repl, 1))
    code, out = run_gate(["--" + key, path])
    problems = []
    if not must:
        if code != 0:
            problems.append("%s (%s): the gate refused a NEGATIVE control "
                            "(exit %s): it reads prose or a label as a call"
                            % (mid, what, code))
    else:
        if code != 1:
            problems.append("%s (%s): the gate exited %s, not 1 - %s"
                            % (mid, what, code,
                               "it is BLIND to this defect" if code == 0
                               else "it hung" if code is None
                               else "a setup failure is not a catch"))
        for need in must:
            if need not in out:
                problems.append("%s (%s): the gate never printed %r, so it "
                                "did not fail for THIS reason"
                                % (mid, what, need))
    if "Traceback" in out:
        problems.append("%s (%s): the gate crashed (a traceback is not a "
                        "catch)" % (mid, what))
    if problems:
        tail = "\n".join(out.strip().split("\n")[-12:])
        problems.append("   last lines of that run:\n      "
                        + tail.replace("\n", "\n      "))
    return problems


def main():
    texts = {}
    for key, path in FILES.items():
        with open(path, encoding="utf-8") as fh:
            texts[key] = fh.read()
    scratch = tempfile.mkdtemp(prefix="test-transport-holds-")
    problems = []
    try:
        with concurrent.futures.ThreadPoolExecutor(
                max_workers=max(1, min(len(MUTANTS) + 1,
                                       os.cpu_count() or 1))) as pool:
            clean = pool.submit(run_gate, [])
            futs = [(m, pool.submit(one, m, texts, scratch)) for m in MUTANTS]
            code, out = clean.result()
            if code != 0 or "check-transport-holds: OK" not in out:
                problems.append("the CLEAN files did not pass (exit %s), so no "
                                "catch below means anything:\n      %s"
                                % (code, "\n      ".join(
                                    out.strip().split("\n")[-12:])))
            for mutant, fut in futs:
                got = fut.result()
                problems.extend(got)
                print("  %s  %-3s %s" % ("ok  " if not got else "FAIL",
                                         mutant[0], mutant[2]))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    if problems:
        print("test-transport-holds: FAIL\n  " + "\n  ".join(problems))
        return 1
    n_neg = sum(1 for m in MUTANTS if not m[5])
    print("test-transport-holds: OK (the clean files pass, all %d seeded "
          "defects fail the gate on the checks that name them, and %d "
          "negative control(s) pass)" % (len(MUTANTS) - n_neg, n_neg))
    return 0


if __name__ == "__main__":
    sys.exit(main())
