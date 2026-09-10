#!/usr/bin/env python3
"""test-timer-stack-pin.py - fixture tests for tools/check-timer-stack-pin.py.

WHY THIS FILE EXISTS
    check-timer-stack-pin.py has been widened twice, and both widenings were
    the same mistake found late: the gate asked the question that described
    the bug already found (one callee list on 2026-08-17; one entry class,
    `send ... to me in`, until 2026-09-09) and reported OK over everything the
    question could not see - 40 chains the first time, 24 the second. Neither
    widening was pinned by a fixture, so a third narrowing could land the same
    way: quietly, as a gate that still prints OK.

    This file drives the REAL gate (its main(), the way build-all.sh runs it)
    over a temporary tree shaped like the traps, with a minimal ui-kit master
    beside it, and asserts what it must conclude:

      - all THREE delivery classes are entries: `send ... to me in` (the plain
        and the computed spelling), `with message "X"`, the engine's own socket
        messages, and a name handed to a library registrar (oxSetStreamCallback
        / oxhRoute) - the last of which appears at NO call site;
      - each finding names the class that delivered the handler, and never
        claims a `send` for a handler the engine or a library delivers;
      - the closure is real (a hazard two calls deep is found) and a pinned
        handler is a WALL (a hazard below a pin is NOT reported);
      - the carried kit is consulted (an armed handler calling an unpinned ui*
        helper is found);
      - a clean tree passes and says how many handlers it looked at;
      - a tree with no delayed handler at all is refused as a broken scan.

    python3 tools/test-timer-stack-pin.py

Exit code 0 = every fixture behaved, 1 = a rule regressed.
"""
import contextlib
import importlib.util
import io
import os
import shutil
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_gate():
    path = os.path.join(ROOT, "tools", "check-timer-stack-pin.py")
    spec = importlib.util.spec_from_file_location("check_timer_stack_pin", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# A minimal kit master: one ui* helper that touches a control unqualified and
# does not pin (the hazard the real uiStatus had until 2026-08-18), and one
# that pins (must NOT be counted as unpinned).
KIT = '''script "kit-fixture"
on uiStatus pText, pKind
   put pText into field "uiStatus"
end uiStatus

on uiPinned pText
   set the defaultStack to the short name of this stack
   put pText into field "uiStatus"
end uiPinned
'''

# Every trap in one stack, so one run of the gate must find exactly these.
TRAPS = '''script "fixture-traps"
on openStack
   send "faTick" to me in 100 milliseconds
   send ("faFlash" && quote & "x" & quote) to me in 1200 milliseconds
   send "faWallTick" to me in 1 millisecond
   send "faViaWall" to me in 1 millisecond
   send "faKitTick" to me in 1 millisecond
   read from socket "127.0.0.1:1" with message "faData"
   oxSetStreamCallback "faStream"
   oxhRoute "GET", "/", "faServe"
end openStack

on faTick
   faLog "tick"
end faTick

on faLog pText
   put pText & return after field "faLog"
end faLog

on faFlash pBtn
   set the label of button pBtn to "Copied"
end faFlash

on faData pSock, pData
   put pData into field "faLog"
end faData

on faStream pStream, pEvent, pData
   faServe pStream
end faStream

on faServe pStream
   faLog "serve"
end faServe

on socketError pSock, pErr
   faLog pErr
end socketError

on faWallTick
   set the defaultStack to the short name of this stack
   faLog "safe: pinned at the entry point"
end faWallTick

on faViaWall
   faWall
end faViaWall

on faWall
   set the defaultStack to the short name of this stack
   faLog "safe: below a wall"
end faWall

on faKitTick
   uiStatus "hello", "ok"
end faKitTick
'''

# The same shapes, every one pinned at its entry: the gate must pass.
CLEAN = '''script "fixture-clean"
on openStack
   send "fbTick" to me in 100 milliseconds
   read from socket "127.0.0.1:1" with message "fbData"
end openStack

on fbTick
   set the defaultStack to the short name of this stack
   fbLog "tick"
end fbTick

on fbData pSock, pData
   set the defaultStack to the short name of this stack
   fbLog pData
end fbData

on fbLog pText
   put pText & return after field "fbLog"
end fbLog
'''

# (handler, the delivery class the finding MUST name, a fragment of the WHY)
EXPECTED = [
    ("faTick",      "armed by `send ... to me in`",            "reaches faLog"),
    ("faFlash",     "armed by `send ... to me in`",            "touches"),
    ("faKitTick",   "armed by `send ... to me in`",            "calls uiStatus"),
    ("faData",      "named by `with message`",                 "touches"),
    ("faStream",    "registered as a library callback",        "reaches faServe -> faLog"),
    ("faServe",     "registered as a library callback",        "reaches faLog"),
    ("socketError", "engine socket message delivered by the ENGINE", "reaches faLog"),
]
# Delayed handlers that must NOT be reported: pinned at the entry, or only
# reaching a hazard through a handler that pins (the wall).
SILENT = ["faWallTick", "faViaWall", "faWall", "faLog", "openStack", "GET"]


def run_gate(gate, files):
    """Build a temp tree holding `files` plus the kit master, point the REAL
    gate at it, and return (exit code, printed lines)."""
    tmp = tempfile.mkdtemp(prefix="timer-pin-fixture-")
    try:
        os.makedirs(os.path.join(tmp, "tools"))
        with open(os.path.join(tmp, "tools", "ui-kit.livecodescript"), "w",
                  encoding="utf-8") as f:
            f.write(KIT)
        for name, text in files.items():
            with open(os.path.join(tmp, name), "w", encoding="utf-8") as f:
                f.write(text)
        gate.ROOT = tmp
        gate.KIT = os.path.join(tmp, "tools", "ui-kit.livecodescript")
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = gate.main([])
        return code, out.getvalue().splitlines()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main():
    gate = load_gate()
    problems = []
    nfixtures = 0

    def ok(cond, label):
        nonlocal nfixtures
        nfixtures += 1
        if not cond:
            problems.append(label)

    # --- 1. every trap, one run ------------------------------------------
    code, lines = run_gate(gate, {"traps.livecodescript": TRAPS})
    findings = [l for l in lines if "()" in l and " and " in l]
    ok(code == 1, "the trap tree must FAIL the gate")
    for name, how, why in EXPECTED:
        mine = [l for l in findings if l.split(":", 1)[1].strip().startswith(name + "()")]
        ok(len(mine) == 1,
           f"{name}: expected exactly one finding, got {len(mine)}: {mine}")
        if mine:
            ok(how in mine[0], f"{name}: the finding must say it {how!r}; got {mine[0]!r}")
            ok(why in mine[0], f"{name}: the finding must explain {why!r}; got {mine[0]!r}")
            if "send" not in how:
                ok("send" not in mine[0],
                   f"{name}: a handler the engine or a library delivers must not be "
                   f"described as armed by `send`; got {mine[0]!r}")
    for name in SILENT:
        mine = [l for l in findings if l.split(":", 1)[1].strip().startswith(name + "()")]
        ok(not mine, f"{name}: must NOT be reported (pinned, or below a wall); got {mine}")
    ok(any(l.strip() == f"check-timer-stack-pin: {len(EXPECTED)} finding(s)" for l in lines),
       f"the count line must say {len(EXPECTED)} finding(s); got {lines[-1:] }")

    # --- 2. the clean tree passes, and says what it looked at ------------
    code, lines = run_gate(gate, {"clean.livecodescript": CLEAN})
    ok(code == 0, f"the clean tree must PASS the gate; got {code}: {lines}")
    ok(any("OK (2 delayed handler(s) across 1 file(s)" in l for l in lines),
       f"the OK line must count both delivery classes in the clean tree; got {lines}")

    # --- 3. no delayed handler anywhere is a broken scan, not a pass ------
    code, lines = run_gate(gate, {})
    ok(code == 1 and any("found NO armed handlers" in l for l in lines),
       f"an empty tree must be refused as a broken scan; got {code}: {lines}")

    if problems:
        for p in problems:
            print("  FAIL " + p)
        print(f"test-timer-stack-pin: {len(problems)} of {nfixtures} fixture(s) FAILED")
        return 1
    print(f"test-timer-stack-pin: OK ({nfixtures} fixture(s): three delivery classes, "
          "the closure, the wall, the kit, a clean tree, and the empty-scan refusal)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
