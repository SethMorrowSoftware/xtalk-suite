#!/usr/bin/env python3
"""run-engine-demo.py - run examples/curlxt-live.livecodescript, the desktop
demo, start to finish on OXT-Beyond's desktop engine with no screen.

    run-engine-demo.py ENGINE MODULE LIBRARY

      ENGINE   standalone-community, the desktop engine from the -binaries
               archive of an OXT-Beyond release
      MODULE   curl.lcm, compiled from src/curl.lcb by that release's
               lc-compile
      LIBRARY  the curlxt library to load (.../curlxt.so)

WHY THE DESKTOP ENGINE. The demo serves its own scenes: it listens on
127.0.0.1 with `accept connections`. The server engine that
run-engine-selftest.py uses opens such a listener and never delivers a
connection to it (measured 2026-11-21 on OXT-Beyond 0.2.7-rc.6; the suite's
engine note 6.15), so it cannot host the demo. The desktop engine of the
same archive, started with -ui, runs a script-only stack with no display
and delivers every socket message (engine note 6.16). It needs no display
server: DISPLAY is taken out of its environment, so a run on a desktop
cannot open a window either.

WHAT RUNS. tests/engine-demo.livecodescript loads the extension, opens the
demo the way start-here's launcher does, lets scene 1 start by itself,
presses every other scene's button, reads each scene's own verdict from
the demo's log, then closes the demo, checks that curlxt and the engine hold
nothing, and opens and closes it again. The demo needs nothing from this
file: no server and no network (scene 4's internet tile says plainly when
it cannot reach out, and nothing else depends on it).

WHAT GREEN MEANS. The engine's exit status is 0 AND its last word is a line
"SUMMARY passed failed" with no failure and at least FLOOR checks: an engine
that printed nothing, or stopped half way, must not read as a pass.

WHAT IT CANNOT SEE is anything drawn: the window is never shown. A check of
the look needs an OXT pass on a screen.

Verified on 2026-11-21 with OXT-Beyond 0.2.7-rc.6's desktop engine
(9.7.1-OXT, Linux x86-64); the root native-curlxt.yml `engine` job runs it
on every change, after run-engine-selftest.py. It is not a gate of
tools/run-gates.sh: it needs an engine.
"""

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
DRIVER = os.path.join(MEMBER, "tests", "engine-demo.livecodescript")
DEMO = os.path.join(MEMBER, "examples", "curlxt-live.livecodescript")
# The driver makes its checks one by one (no loop decides how many), and the
# first full run (2026-11-21) made 26. Every early stop it knows of prints a
# FAIL too; the floor is for the one it does not. Raise it with the count,
# never lower it to pass.
FLOOR = 26
# The scenes take about 45 s; the driver's own watchdog stops a hung run at
# 240 s and says where, so this outer limit is only for an engine that hangs
# before or after the driver.
TIMEOUT = 300


def main(argv):
    if len(argv) != 4:
        print(__doc__.split("\n\n")[1])
        return 2
    engine, module, library = (os.path.abspath(a) for a in argv[1:])
    for what, path in (("engine", engine), ("module", module), ("library", library),
                       ("driver", DRIVER), ("demo", DEMO)):
        if not os.path.isfile(path):
            print("run-engine-demo: FAIL - no %s at %s" % (what, path))
            return 1
    env = dict(os.environ)
    env.pop("DISPLAY", None)
    env["CURLXT_DEMO_MODULE"] = module
    # The engine is given the library WITHOUT its extension: it adds the
    # platform's own when it resolves "c:curlxt>...".
    env["CURLXT_DEMO_LIBRARY"] = os.path.splitext(library)[0]
    env["CURLXT_DEMO_STACK"] = DEMO
    cmd = [engine, "-ui", DRIVER]
    try:
        run = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                             timeout=TIMEOUT, cwd=MEMBER, env=env)
    except subprocess.TimeoutExpired as exc:
        out = (exc.stdout or b"").decode("utf-8", "replace")
        print(out)
        print("run-engine-demo: FAIL - the engine did not finish in %d s" % TIMEOUT)
        return 1

    out = run.stdout.decode("utf-8", "replace")
    sys.stdout.write(out)
    summary = re.findall(r"(?m)^SUMMARY (\d+) (\d+)\s*$", out)
    if not summary:
        print("run-engine-demo: FAIL - the engine printed no SUMMARY line (exit %d)" % run.returncode)
        return 1
    passed, failed = (int(x) for x in summary[-1])
    if run.returncode != 0 or failed != 0:
        print("run-engine-demo: FAIL - %d of %d checks failed (engine exit %d)"
              % (failed, passed + failed, run.returncode))
        return 1
    if passed < FLOOR:
        print("run-engine-demo: FAIL - only %d checks ran (floor %d)" % (passed, FLOOR))
        return 1
    print("run-engine-demo: OK (%d checks; the demo's five scenes on the desktop engine over %s)"
          % (passed, os.path.basename(library)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
