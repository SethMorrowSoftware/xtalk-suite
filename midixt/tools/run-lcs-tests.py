#!/usr/bin/env python3
"""Run a ShowControl-family member's LiveCode SCRIPT suites inside a real OXT
engine, headlessly.

Shared by the three ShowControl members of the suite (oscxt, midixt, artnetxt):
this file is BYTE-IDENTICAL in each (the suite's tools/check-checker-drift.py
holds the copies equal); what differs lives in tools/runner_config.py.

tools/run-lcb-tests.py covers the LCB bindings under lc-run. What it cannot
reach is the half users actually touch: LiveCode Script calling the extensions
(the Script <-> LCB boundary, where most real-world bugs in ShowControl's
history lived), the shipped example/helper scripts, and the engine's own UDP
sockets. This runner covers that half with the STANDALONE engine started with
-ui (no window, no display needed):

    standalone-community -ui tests/lcs/_runner.livecodescript

per test handler, one engine process each (a crash fails one test, not the run).
The runner stack loads the compiled extensions from a packaged-extension layout
(<ext>/module.lcm + <ext>/code/<platform-id>/<lib>), maps the native libraries
the same way the IDE does, `start using`s the helper library, and dispatches the
handler; assertions print TAP on stdout.

Engine facts this relies on (from OXT-Beyond's own CI, tools/ci/run_engine_tests.py):
  * -ui needs no X display; DISPLAY/WAYLAND_DISPLAY are removed so no test can
    reach one.
  * On Windows the engine is a GUI-subsystem program: its stdout is read from a
    file it inherits (not via cmd.exe). Engines older than OXT-Beyond 0.2.1-rc.1
    lose redirected output.
  * Engine flags are parsed out of argv ANYWHERE on the line, so test parameters
    travel in environment variables (SC_*), never as arguments.
  * Output goes to temporary files, not pipes, and each engine runs in its own
    process group so a timeout can kill everything it started.
  * Windows engines older than OXT-Beyond 0.2.1-rc.2 deliver NO socket events
    without a UI. A one-shot probe decides whether socket suites can run here;
    when it fails they SKIP -- and FAIL under --require-all (CI), so an engine
    that cannot test sockets can never pass the socket suites silently.

Test files declare their needs on header lines:
    -- needs: sockets                 (skip unless the socket probe passed)
    -- peers: osc artnet              (start tools/sim peers; ports in SC_*_PEER_PORT)
    -- requires: KEY ...              (which library each extension gets, by the
                                       keys of tools/runner_config.py; default:
                                       each extension's first key)

Usage:
    python3 tools/run-lcs-tests.py --oxt-bin <OXT build folder> [--build-dir build]
        [--lib KEY=PATH ...] [--filter REGEX] [--require-all] [--min-assertions N]
"""

import argparse
import importlib.util
import os
import re
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "tools" / "sim"))

import runner_config as CFG                 # noqa: E402 -- this member's own facts

_spec = importlib.util.spec_from_file_location("run_lcb_tests", str(ROOT / "tools" / "run-lcb-tests.py"))
lcb = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(lcb)

LCS_DIR = ROOT / "tests" / "lcs"
STAGED_RUNNER = [None]          # set by main() once the scripts are staged
RUNNER = LCS_DIR / "_runner.livecodescript"
HELPERS = ROOT / CFG.HELPERS
NEEDS_RE = re.compile(r"^--[ \t]*needs:[ \t]*([^\r\n]*)$", re.M)
PEERS_RE = re.compile(r"^--[ \t]*peers:[ \t]*([^\r\n]*)$", re.M)
REQUIRES_RE = re.compile(r"^--[ \t]*requires:[ \t]*([^\r\n]*)$", re.M)


def find_engine(bin_dir):
    cands = [bin_dir / ("standalone-community" + lcb.EXE),
             bin_dir / "Standalone-Community.app" / "Contents" / "MacOS" / "Standalone-Community",
             bin_dir.parent / "Standalone-Community.app" / "Contents" / "MacOS" / "Standalone-Community"]
    for c in cands:
        if c.is_file():
            return c
    sys.stderr.write("run-lcs-tests: no standalone engine next to lc-compile in %s\n" % bin_dir)
    sys.exit(2)


def engine_env(extra):
    env = dict(os.environ)
    for var in ("DISPLAY", "WAYLAND_DISPLAY"):
        env.pop(var, None)              # -ui needs no display; a test must not reach one
    # LiveCode paths are forward-slash on every platform; a backslash path that
    # reaches the revLibraryMapping fails to load ("unable to load foreign library").
    env.update({k: (v.as_posix() if isinstance(v, Path) else str(v)) for k, v in extra.items()})
    return env


def stage_scripts(work):
    """Copy the runner, the test stacks and the examples into <work>/scripts.

    The engine is a classic Win32 program bound by MAX_PATH (260): from a deep
    checkout, `url "file:..."` on a long example name fails outright. Staging into
    the (short) work dir keeps every path the engine sees well inside the limit,
    and freezes the files for the run."""
    dst = work / "scripts"
    dst.mkdir(parents=True, exist_ok=True)
    staged = {}
    for f in [RUNNER] + sorted(LCS_DIR.glob("*.livecodescript")) + sorted(ROOT.glob("examples/*.livecodescript")):
        sub = dst / ("examples" if f.parent.name == "examples" else "lcs")
        sub.mkdir(exist_ok=True)
        shutil.copy2(f, sub / f.name)
        staged[f] = sub / f.name
    return staged


def run_engine(engine, env, timeout, cwd):
    """Run the runner stack once; return (exit status or None on timeout, stdout, stderr)."""
    with tempfile.TemporaryFile() as out, tempfile.TemporaryFile() as err:
        kw = {}
        if lcb.IS_WIN:
            kw["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
        else:
            kw["start_new_session"] = True
        p = subprocess.Popen([str(engine), "-ui", str(STAGED_RUNNER[0])], stdout=out, stderr=err,
                             stdin=subprocess.DEVNULL, env=env, cwd=str(cwd), **kw)
        try:
            status = p.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            status = None
            if lcb.IS_WIN:
                subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)], capture_output=True)
            else:
                try:
                    os.killpg(p.pid, signal.SIGKILL)
                except OSError:
                    pass
            p.wait()
        out.seek(0)
        err.seek(0)
        return (status, out.read().decode("utf-8", "replace"), err.read().decode("utf-8", "replace"))


def build_ext_root(ext_root, mod_dir, libs, requires):
    """The packaged-extension layout: <ext>/module.lcm (+ code/<platform-id>/<lib>).

    Each extension of tools/runner_config.py's ENGINE_EXTENSIONS gets the first
    of its library keys that the test file `requires:`, or else its first key."""
    if ext_root.exists():
        shutil.rmtree(ext_root)
    pid = lcb.host_platform_id()
    missing = []
    for folder, module, keys in CFG.ENGINE_EXTENSIONS:
        d = ext_root / folder
        d.mkdir(parents=True)
        shutil.copy2(mod_dir / (module + ".lcm"), d / "module.lcm")
        if not keys:
            continue
        chosen = next((k for k in keys if k in requires), keys[0])
        if chosen not in libs:
            missing.append(chosen)
            continue
        code = d / "code" / pid
        code.mkdir(parents=True)
        token = lcb.LIBRARIES[chosen][0]
        shutil.copy2(libs[chosen][0], code / (token + lcb.LIB_EXT))
    return missing


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--oxt-bin")
    ap.add_argument("--build-dir", default=str(ROOT / "build"))
    ap.add_argument("--work-dir")
    ap.add_argument("--lib", action="append", metavar="KEY=PATH",
                    help="use this file for library KEY (keys: %s); repeatable" % ", ".join(lcb.LIB_KEYS))
    ap.add_argument("--filter")
    ap.add_argument("--timeout", type=int, default=120)
    ap.add_argument("--port-base", type=int,
                    default=int(os.environ.get(CFG.MEMBER.upper() + "_PORT_BASE", str(CFG.PORT_BASE))))
    ap.add_argument("--require-all", action="store_true", default=os.environ.get(CFG.MEMBER.upper() + "_REQUIRE_ALL") == "1")
    ap.add_argument("--min-assertions", type=int, default=0)
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    lc_compile, lc_run, lci_dir = lcb.find_toolchain(args.oxt_bin)
    engine = find_engine(lc_compile.parent)
    build_dir = Path(args.build_dir).resolve()
    work = Path(args.work_dir).resolve() if args.work_dir else build_dir / "lcs-tests"
    if work.exists():
        shutil.rmtree(work)
    mod_dir = work / "modules"
    mod_dir.mkdir(parents=True)
    print("engine    : %s" % engine)
    libs = lcb.resolve_libs(args)
    for key in lcb.LIB_KEYS:
        print("lib %-9s: %s" % (key, ("%s  [%s]" % libs[key]) if key in libs else "(not available)"))

    # ---- compile the extensions (-Werror) + any engine-only test controls ------
    log, ok = [], True
    for name, src in lcb.EXTENSIONS:
        ok &= lcb.compile_lcb(lc_compile, lci_dir, mod_dir, src, mod_dir / (name + ".lcm"), log,
                              werror=True)
    for name, rel in CFG.ENGINE_SUPPORT:
        ok &= lcb.compile_lcb(lc_compile, lci_dir, mod_dir, ROOT / rel, mod_dir / (name + ".lcm"), log)
    if not ok:
        print("\n".join(log))
        print("run-lcs-tests: compilation failed")
        return 2

    staged = stage_scripts(work)
    STAGED_RUNNER[0] = staged[RUNNER]

    # ---- the engine's own compile gate over every .livecodescript ----------------
    # A compile error in Script is SILENT in the engine (a broken script-only stack
    # never opens; `set the script` leaves the result empty), so ask the engine to
    # compile each file and count handlers. This is the real compiler, not a lint.
    results, skipped = [], []
    lcs_files = [staged[f] for f in sorted(ROOT.glob("examples/*.livecodescript")) + sorted(LCS_DIR.glob("*.livecodescript"))]
    # One engine per file: compiling several scripts in one engine let an earlier
    # file's stack state make a later, valid file read as handler-less.
    cr = lcb.Result("compile", "engine-compile-check")
    for f in lcs_files:
        st, out, err = run_engine(engine, engine_env({"SC_MODE": "compile-check", "SC_FILES": f.as_posix()}), 60, work)
        before = len(cr.ok) + len(cr.notok)
        lcb.parse_tap(out, cr)
        if st is None or len(cr.ok) + len(cr.notok) == before:
            cr.notok.append("the runner stack never started (status %s) -- usually a compile error in "
                            "tests/lcs/_runner.livecodescript itself, which the engine reports nowhere" % st)
            break
    results.append(cr)
    print("%-5s engine compile check: %d of %d .livecodescript file(s) compile" % (
        cr.verdict, len(cr.ok), len(lcs_files)))
    for d in cr.notok + [x for x in cr.diags if "fails to compile" in x]:
        print("        " + d)

    # ---- can this engine do UDP without a UI? ----------------------------------
    status, out, err = run_engine(engine, engine_env({"SC_MODE": "probe-sockets", "SC_PORT_BASE": args.port_base}),
                                  30, work)
    sockets_ok = status == 0 and "ok - engine delivers UDP" in out
    print("sockets   : %s" % ("usable without a UI" if sockets_ok else
                              "NOT usable without a UI on this engine (socket suites will skip)"))
    if args.verbose or (status not in (0, 1)):
        print(out + err)

    flt = re.compile(args.filter) if args.filter else None
    tests = sorted(p for p in LCS_DIR.glob("*_test.livecodescript"))
    for tf in tests:
        src = tf.read_text(encoding="utf-8")
        needs = (NEEDS_RE.search(src).group(1).split() if NEEDS_RE.search(src) else [])
        peers = (PEERS_RE.search(src).group(1).split() if PEERS_RE.search(src) else [])
        requires = (REQUIRES_RE.search(src).group(1).split() if REQUIRES_RE.search(src) else [])
        bad = [k for k in requires if k not in lcb.LIBRARIES]
        if bad:
            r = lcb.Result(tf.stem, "<requires>")
            r.notok.append("unknown library key(s) in requires: %s" % ", ".join(bad))
            results.append(r)
            print("FAIL  %s::<requires>  unknown key(s) %s" % (tf.stem, ", ".join(bad)))
            continue
        suite = tf.stem
        if "sockets" in needs and not sockets_ok:
            skipped.append((suite, "engine cannot deliver socket events without a UI"))
            print("SKIP  %s  (needs sockets)" % suite)
            continue
        ext_root = work / "ext" / suite
        missing = build_ext_root(ext_root, mod_dir, libs, requires)
        if missing:
            skipped.append((suite, "missing native library: " + ", ".join(missing)))
            print("SKIP  %s  (needs %s)" % (suite, ", ".join(missing)))
            continue
        base_env = {"SC_TEST_FILE": staged[tf], "SC_EXT_ROOT": ext_root, "SC_HELPERS": staged[HELPERS],
                    "SC_PORT_BASE": args.port_base, "SC_SOCKETS": "1" if sockets_ok else "0"}
        st, out, err = run_engine(engine, engine_env(dict(base_env, SC_MODE="list")), 60, work)
        handlers = [l.strip() for l in out.splitlines() if l.strip().startswith("Test")]
        if not handlers:
            r = lcb.Result(suite, "<list>")
            r.notok.append("could not list handlers (status %s): %s" % (st, (out + err).strip()[-300:]))
            results.append(r)
            print("FAIL  %s::<list>" % suite)
            continue
        for h in handlers:
            if flt and not flt.search("%s::%s" % (suite, h)):
                continue
            running = []
            env_extra = dict(base_env, SC_MODE="run", SC_TEST=h)
            try:
                if "osc" in peers:
                    from osc_peer import OscPeer
                    running.append(OscPeer(port=0, ack=True).start_background())
                    env_extra["SC_OSC_PEER_PORT"] = running[-1].port
                if "artnet" in peers:
                    from artnet_node import ArtNetNode
                    running.append(ArtNetNode(port=0, short_name="SimNode", echo_offset=1).start_background())
                    env_extra["SC_ARTNET_PEER_PORT"] = running[-1].port
                t0 = time.time()
                st, out, err = run_engine(engine, engine_env(env_extra), args.timeout, work)
            finally:
                for p in running:
                    p.stop()
            r = lcb.Result(suite, h)
            r.seconds = time.time() - t0
            lcb.parse_tap(out, r)
            if st is None:
                r.timed_out = True
                r.notok.append("timed out after %ds" % args.timeout)
            elif st != len(r.notok):
                # the runner quits with its failure count; anything else is a crash
                r.status = st
                r.notok.append("engine exited with status %s (expected %d)%s" % (
                    st, len(r.notok), (": " + err.strip()[-300:]) if err.strip() else ""))
            results.append(r)
            print("%-5s %-50s %3d ok%s  %.1fs" % (r.verdict, r.name, len(r.ok),
                                                 (", %d skip" % len(r.skip)) if r.skip else "", r.seconds))
            if r.verdict == "FAIL" or args.verbose:
                for d in r.notok:
                    print("        not ok - " + d)
                for d in r.diags[-15:]:
                    print("        " + d)

    n_fail = sum(1 for r in results if r.verdict == "FAIL")
    n_pass = sum(1 for r in results if r.verdict == "PASS")
    n_skip = sum(1 for r in results if r.verdict == "SKIP")
    n_ok = sum(len(r.ok) for r in results)
    print("\n" + "=" * 72)
    print("LCS in-engine: %d handler(s) passed, %d failed, %d skipped; %d assertion(s) ok"
          % (n_pass, n_fail, n_skip, n_ok))
    rc = 1 if n_fail else 0
    if skipped:
        msg = "; ".join("%s (%s)" % s for s in skipped)
        if args.require_all:
            print("FAIL: suites skipped under --require-all: " + msg)
            rc = 1
        else:
            print("NOTE: suites skipped (pass --require-all to make this fatal): " + msg)
    if args.min_assertions and n_ok < args.min_assertions:
        print("FAIL: only %d assertion(s) passed; the floor is %d" % (n_ok, args.min_assertions))
        rc = 1
    print("=" * 72)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### %s: LCS in-engine suite (%s, sockets %s)\n\n" % (
                CFG.MEMBER, lcb.host_platform_id(), "on" if sockets_ok else "OFF"))
            f.write("| result | handler | ok | not ok |\n|---|---|---|---|\n")
            for r in results:
                f.write("| %s | `%s` | %d | %d |\n" % (r.verdict, r.name, len(r.ok), len(r.notok)))
            for s in skipped:
                f.write("| SKIP | `%s` | | %s |\n" % s)
            f.write("\n")
    return rc


if __name__ == "__main__":
    sys.exit(main())
