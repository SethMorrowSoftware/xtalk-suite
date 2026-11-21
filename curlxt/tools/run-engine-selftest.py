#!/usr/bin/env python3
"""run-engine-selftest.py - run tests/engine-selftest.lc on OXT-Beyond's
server engine, against servers this file runs on 127.0.0.1.

    run-engine-selftest.py ENGINE MODULE LIBRARY
    run-engine-selftest.py --check-sweep

      ENGINE   server-community, from the -binaries archive of an
               OXT-Beyond release
      MODULE   curl.lcm, compiled from src/curl.lcb by that release's
               lc-compile
      LIBRARY  the curlxt library to load (.../curlxt.so)

WHY A DRIVER. The self-test talks to an HTTP server, a WebSocket echo and
the same echo behind TLS. Those are tools/check-script-vectors.py's own
servers (imported from it, not copied), so the engine run and the
interpreter run answer to one server and cannot drift apart: a command such
as "!frag" means the same thing to both. The certificate wss:// presents is
made for the run by the openssl command, as that gate makes it.

WHAT GREEN MEANS. The engine's exit status is 0 AND its last word is a line
"SUMMARY passed failed" with no failure and at least FLOOR checks: an engine
that printed nothing, or stopped half way, must not read as a pass.

Before it starts the engine, it holds the self-test's SWEEP to the binding:
every public handler of src/curl.lcb must be called there (in code, not in
a comment), the sweep's count must be the binding's, and the test must call
the sweep. That half needs no engine: it runs first here, and alone with
--check-sweep as one of tools/run-gates.sh's gates (fixture:
tools/test-engine-sweep.py), so a handler added without its sweep line
fails the compiler-free gates, not only the engine lane.

Verified on 2026-11-21 with OXT-Beyond 0.2.7-rc.6's engine (9.7.1-OXT,
Linux x86-64); the root native-curlxt.yml `engine` job runs it on every
change. It is not a gate of tools/run-gates.sh: it needs an engine.
"""

import importlib.util
import os
import re
import shutil
import ssl
import subprocess
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
MEMBER = os.path.dirname(HERE)
LCB = os.path.join(MEMBER, "src", "curl.lcb")
TEST = os.path.join(MEMBER, "tests", "engine-selftest.lc")
HELPERS = os.path.join(MEMBER, "src", "curl-helpers.livecodescript")
TSNET = os.path.join(MEMBER, "src", "tsnet.livecodescript")
# The first full run (2026-11-21) made 138 checks. The floor sits a little
# under that, so a run that stopped part way (a section that returned early,
# a throw caught by the main handler) fails here even when it printed a
# SUMMARY with no failure. Raise it with the count, never lower it to pass.
FLOOR = 130
TIMEOUT = 600


def public_handlers(lcb_text):
    return re.findall(r"^public handler (\w+)\(", lcb_text, re.M)


SWEEP_BEGIN = "-- >>> SWEEP >>>"
SWEEP_END = "-- <<< END SWEEP <<<"


def strip_comments(text):
    """The text with every comment blanked: --, // and # to the end of the
    line, and /* ... */ blocks, none of them inside a "quoted" literal
    (xTalk literals have no escapes). Line breaks are kept, so a line
    stays a line."""
    out = []
    i, n = 0, len(text)
    quoted = block = False
    while i < n:
        c = text[i]
        if block:
            if text.startswith("*/", i):
                block = False
                i += 2
                continue
            out.append("\n" if c == "\n" else " ")
        elif quoted:
            out.append(c)
            if c == '"' or c == "\n":
                quoted = False
        elif c == '"':
            quoted = True
            out.append(c)
        elif text.startswith("/*", i):
            block = True
            i += 2
            continue
        elif text.startswith("--", i) or text.startswith("//", i) or c == "#":
            while i < n and text[i] != "\n":
                i += 1
            continue
        else:
            out.append(c)
        i += 1
    return "".join(out)


def sweep_text(test_text):
    """The text between the sweep's markers, or None unless there is
    exactly one pair, in order."""
    if test_text.count(SWEEP_BEGIN) != 1 or test_text.count(SWEEP_END) != 1:
        return None
    start = test_text.find(SWEEP_BEGIN)
    end = test_text.find(SWEEP_END)
    if end < start:
        return None
    return test_text[start + len(SWEEP_BEGIN):end]


def sweep_problems(lcb_text, test_text):
    """Every public handler of the binding is called in the sweep (a call,
    not a mention: the name followed by '(' or written as a statement, in
    code, not in a comment), the count the sweep reports is the binding's,
    and the test outside the sweep calls it."""
    sweep = sweep_text(test_text)
    if sweep is None:
        return ["tests/engine-selftest.lc has no single SWEEP marker pair"]
    names = public_handlers(lcb_text)
    if not names:
        return ["src/curl.lcb has no public handler (has its form changed?)"]
    code = strip_comments(sweep)
    missing = [n for n in names
               if not re.search(r"(?m)(\b%s\(|^\s+%s\s*$)" % (n, n), code)]
    problems = ["the sweep does not call %s, a public handler of src/curl.lcb" % n
                for n in missing]
    # The count it reports once every call has returned (the last
    # assignment; the first one zeroes it).
    counts = re.findall(r"put (\d+) into tCount", code)
    if not counts or int(counts[-1]) != len(names):
        problems.append("the sweep's count (%s) is not the binding's %d public handlers"
                        % (counts[-1] if counts else "none", len(names)))
    rest = strip_comments(test_text.replace(SWEEP_BEGIN + sweep + SWEEP_END, ""))
    if not re.search(r"(?m)^\s+sweepEveryHandler\s*$", rest):
        problems.append("nothing in tests/engine-selftest.lc calls sweepEveryHandler")
    return problems


def check_sweep():
    """The compiler-free half, alone: the gate tools/run-gates.sh runs."""
    with open(LCB, encoding="utf-8") as fh:
        lcb_text = fh.read()
    with open(TEST, encoding="utf-8") as fh:
        test_text = fh.read()
    problems = sweep_problems(lcb_text, test_text)
    if problems:
        for p in problems:
            print("run-engine-selftest --check-sweep: FAIL - " + p)
        return 1
    print("run-engine-selftest --check-sweep: OK (the sweep calls all %d public handlers of src/curl.lcb)"
          % len(public_handlers(lcb_text)))
    return 0


def load_servers():
    spec = importlib.util.spec_from_file_location(
        "curlxt_script_vectors", os.path.join(HERE, "check-script-vectors.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main(argv):
    if argv[1:] == ["--check-sweep"]:
        return check_sweep()
    if len(argv) != 4:
        print(__doc__.split("\n\n")[1])
        return 2
    engine, module, library = (os.path.abspath(a) for a in argv[1:])
    for what, path in (("engine", engine), ("module", module), ("library", library)):
        if not os.path.isfile(path):
            print("run-engine-selftest: FAIL - no %s at %s" % (what, path))
            return 1
    with open(LCB, encoding="utf-8") as fh:
        lcb_text = fh.read()
    with open(TEST, encoding="utf-8") as fh:
        test_text = fh.read()
    problems = sweep_problems(lcb_text, test_text)
    if problems:
        print("run-engine-selftest: FAIL - " + "; ".join(problems))
        return 1

    sv = load_servers()
    tmp = tempfile.mkdtemp(prefix="curlxt-engine-")
    servers = []
    try:
        made = sv.make_certificate(tmp)
        if made is None:
            print("run-engine-selftest: FAIL - no openssl command to make the wss:// certificate")
            return 1
        httpd = sv.TServer(("127.0.0.1", 0), sv.Handler)
        wsd = sv.TWs(("127.0.0.1", 0), sv.WsHandler)
        wssd = sv.TWss(("127.0.0.1", 0), sv.WsHandler)
        wssd.context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        wssd.context.load_cert_chain(made[0], made[1])
        servers = [httpd, wsd, wssd]
        for srv in servers:
            threading.Thread(target=srv.serve_forever, daemon=True).start()
        # The engine is given the library WITHOUT its extension: it adds the
        # platform's own when it resolves "c:curlxt>...".
        libbase = os.path.splitext(library)[0]
        cmd = [engine, TEST, module, libbase, HELPERS, TSNET,
               "http://127.0.0.1:%d" % httpd.server_address[1],
               "ws://127.0.0.1:%d" % wsd.server_address[1],
               "wss://127.0.0.1:%d" % wssd.server_address[1],
               made[0]]
        try:
            run = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                 timeout=TIMEOUT, cwd=MEMBER)
        except subprocess.TimeoutExpired as exc:
            out = (exc.stdout or b"").decode("utf-8", "replace")
            print(out)
            print("run-engine-selftest: FAIL - the engine did not finish in %d s" % TIMEOUT)
            return 1
    finally:
        for srv in servers:
            srv.shutdown()
        shutil.rmtree(tmp, ignore_errors=True)

    out = run.stdout.decode("utf-8", "replace")
    sys.stdout.write(out)
    summary = re.findall(r"(?m)^SUMMARY (\d+) (\d+)\s*$", out)
    if not summary:
        print("run-engine-selftest: FAIL - the engine printed no SUMMARY line (exit %d)" % run.returncode)
        return 1
    passed, failed = (int(x) for x in summary[-1])
    if run.returncode != 0 or failed != 0:
        print("run-engine-selftest: FAIL - %d of %d checks failed (engine exit %d)"
              % (failed, passed + failed, run.returncode))
        return 1
    if passed < FLOOR:
        print("run-engine-selftest: FAIL - only %d checks ran (floor %d)" % (passed, FLOOR))
        return 1
    print("run-engine-selftest: OK (%d checks on the engine over %s)" % (passed, os.path.basename(library)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
