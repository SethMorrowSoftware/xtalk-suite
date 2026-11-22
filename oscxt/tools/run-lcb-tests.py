#!/usr/bin/env python3
"""Compile and RUN a ShowControl-family member's LiveCode Builder layer headlessly,
under lc-run.

Shared by the three ShowControl members of the suite (oscxt, midixt, artnetxt):
this file is BYTE-IDENTICAL in each (the suite's tools/check-checker-drift.py
holds the copies equal), and everything that differs between them lives in the
member's own tools/runner_config.py (its extensions, its native libraries, its
helper script).

The long-standing assumption in the xtalk family was that OXT is a GUI runtime
with no headless way to compile or run .lcb. That is not true of the toolchain
the engine ships: every OXT / LiveCode build carries

  * lc-compile  -- the LCB compiler (the same one the IDE's Extension Builder uses)
  * lc-run      -- the LCB virtual machine as a console program, with the full
                   foreign-function interface (libffi), the "<builtin>" engine
                   helpers (MCDataGetBytePtr, MCMemoryAllocate, ...), and the
                   standard library minus the engine/canvas/widget modules.

This script uses both to give the .lcb bindings a real automated test suite:

  1. compiles the member's src/*.lcb with lc-compile -Werror -- the flag the
     IDE's Extension Builder passes, so a warning here is an extension nobody
     can install (ShowControl's three bindings all failed it before the suite);
  2. generates the vectors module from tests/vectors/*.json (the same
     wire-format vectors the Python reference and the C tests check);
  3. compiles tests/lcb/_*.lcb (support libraries) and tests/lcb/*_test.lcb;
  4. stages the native libraries each suite needs (the freshly built shim, or a
     test double such as midixt's MOCK RtMidi library, which has a virtual
     loopback cable, so a whole MIDI stack runs with no hardware);
  5. runs every public Test* handler in its OWN lc-run process (a crash or an
     uncaught LCB error fails that one test and is reported, it cannot take the
     rest of the run down), parses the TAP the com.livecode.unittest syntax
     prints (`ok - ...`, `not ok - ...`, `# diagnostic`), and summarizes.

What it cannot cover: the engine-only half -- LiveCode Script calling into the
extension (the Script <-> LCB boundary), and engine UDP sockets. Those run under
the standalone engine with -ui; see tools/run-lcs-tests.py.

Each test module declares the native libraries it needs on a header line, by
the keys tools/runner_config.py's LIBRARIES defines:

    -- requires: oscxt

A module whose library is unavailable is SKIPPED loudly -- and FAILS instead
when --require-all (or <MEMBER>_REQUIRE_ALL=1, OSCXT_REQUIRE_ALL for oscxt) is
set, which CI does, so a
missing build can never pass silently.

Usage:
    python3 tools/run-lcb-tests.py --oxt-bin <dir with lc-compile/lc-run> \\
        [--build-dir build] [--lib KEY=PATH ...] [--filter REGEX]
        [--require-all] [--min-assertions N]

The OXT folder may also come from $OXT_BIN. Native libraries are found in
--build-dir (CMake output, any config subfolder) unless given explicitly with
--lib KEY=PATH; the member's committed src/code/<platform-id>/ binary is the
fallback for a real (non-mock) library, reported as such (it may be stale).

Exit status: 0 all good, 1 any failure (or fewer assertions than the floor),
2 the toolchain could not be found / a compile failed.
"""

import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

import runner_config as CFG                 # noqa: E402 -- this member's own facts

# (module name, source) for each extension the member ships.
EXTENSIONS = [(name, ROOT / rel) for name, rel in CFG.EXTENSIONS]
TEST_DIR = ROOT / "tests" / "lcb"
# key -> (bare binding token, "built" | "mock"). A test names keys in `requires:`.
LIBRARIES = dict(CFG.LIBRARIES)
LIB_KEYS = tuple(LIBRARIES)

IS_WIN = sys.platform.startswith("win")
IS_MAC = sys.platform == "darwin"
EXE = ".exe" if IS_WIN else ""
LIB_EXT = ".dll" if IS_WIN else (".dylib" if IS_MAC else ".so")


# ---------------------------------------------------------------------------
# Toolchain + library discovery
# ---------------------------------------------------------------------------

def find_toolchain(oxt_bin):
    """Return (lc_compile, lc_run, lci_dir) or exit 2 with a useful message."""
    candidates = []
    if oxt_bin:
        candidates.append(Path(oxt_bin))
    if os.environ.get("OXT_BIN"):
        candidates.append(Path(os.environ["OXT_BIN"]))
    which = shutil.which("lc-compile")
    if which:
        candidates.append(Path(which).parent)
    for base in candidates:
        # Accept the build-folder layout (lc-compile beside modules/lci) and the
        # installed-IDE layout (Toolchain/lc-compile + Toolchain/modules/lci).
        for d in (base, base / "Toolchain"):
            lcc, lcr, lci = d / ("lc-compile" + EXE), d / ("lc-run" + EXE), d / "modules" / "lci"
            if lcc.is_file() and lcr.is_file() and lci.is_dir():
                return lcc, lcr, lci
    sys.stderr.write(
        "run-lcb-tests: cannot find lc-compile + lc-run + modules/lci.\n"
        "  Pass --oxt-bin <folder> or set OXT_BIN. Any OXT/LiveCode build folder\n"
        "  or OXT-Beyond '*-binaries' release archive has them (see docs/building.md).\n")
    sys.exit(2)


def host_platform_id():
    """The code/<platform-id> folder name for this host (architecture FIRST)."""
    machine = platform.machine().lower()
    arch = {"amd64": "x86_64", "x86_64": "x86_64", "i386": "x86", "i686": "x86",
            "x86": "x86", "arm64": "arm64", "aarch64": "arm64"}.get(machine, machine)
    if IS_WIN:
        return arch + "-win32"
    if IS_MAC:
        return "universal-mac"
    return arch + "-linux"


def find_built(build_dir, name, exclude_mock=True, only_mock=False):
    """Find <name>.<ext> under a CMake build dir (Ninja/Makefiles or multi-config)."""
    if not build_dir or not build_dir.is_dir():
        return None
    hits = []
    for p in build_dir.rglob(name + LIB_EXT):
        rel = p.relative_to(build_dir).parts
        if "_deps" in rel or "lcb-tests" in rel or "lcs-tests" in rel:
            continue
        in_mock = "mock" in rel
        if only_mock and not in_mock:
            continue
        if exclude_mock and in_mock:
            continue
        hits.append(p)
    if not hits:
        return None
    hits.sort(key=lambda p: p.stat().st_mtime, reverse=True)   # newest build wins
    return hits[0]


def given_libs(args):
    """--lib KEY=PATH (repeatable) -> {key: Path}; an unknown key is an error."""
    given = {}
    for spec in args.lib or []:
        key, sep, path = spec.partition("=")
        if not sep or key not in LIBRARIES:
            raise SystemExit("run-lcb-tests: --lib wants KEY=PATH with KEY one of %s, not %r"
                             % (", ".join(LIB_KEYS), spec))
        given[key] = Path(path).resolve()
    return given


def resolve_libs(args):
    """Map library key -> (path, provenance) for whatever is available."""
    build_dir = Path(args.build_dir).resolve() if args.build_dir else None
    given = given_libs(args)
    libs = {}
    for key, (token, kind) in LIBRARIES.items():
        if key in given:
            if not given[key].is_file():
                raise SystemExit("run-lcb-tests: --lib %s=%s: no such file" % (key, given[key]))
            libs[key] = (given[key], "given")
        elif kind == "mock":
            mock = find_built(build_dir, token, exclude_mock=False, only_mock=True)
            if mock:
                libs[key] = (mock, "built test double (<build>/mock/)")
        else:
            built = find_built(build_dir, token)
            if built:
                libs[key] = (built, "built")
            else:
                committed = ROOT / "src" / "code" / host_platform_id() / (token + LIB_EXT)
                if committed.is_file():
                    libs[key] = (committed, "COMMITTED binary (not rebuilt from this tree)")
    return libs


# ---------------------------------------------------------------------------
# Compilation
# ---------------------------------------------------------------------------

MODULE_RE = re.compile(r"^\s*(?:library|module)\s+([A-Za-z0-9_.]+)\s*$", re.M)
REQUIRES_RE = re.compile(r"^--[ \t]*requires:[ \t]*([^\r\n]*)$", re.M)


def module_id(src):
    m = MODULE_RE.search(src.read_text(encoding="utf-8"))
    if not m:
        raise SystemExit("run-lcb-tests: no library/module line in %s" % src)
    return m.group(1)


def compile_lcb(lc_compile, lci_dir, mod_dir, src, out_lcm, log, manifest=None, werror=False):
    mid = module_id(src)
    cmd = [str(lc_compile)] + (["-Werror"] if werror else []) + [
           "--modulepath", str(mod_dir), "--modulepath", str(lci_dir),
           # --interface keeps the .lci out of the FIRST --modulepath's default
           # spot -- without it lc-compile writes it there, which once dropped
           # stray .lci files into an installed OXT's modules/lci.
           "--interface", str(mod_dir / (mid + ".lci")),
           "--output", str(out_lcm)]
    if manifest:
        cmd += ["--manifest", str(manifest)]
    cmd += ["--", str(src)]
    r = subprocess.run(cmd, capture_output=True, text=True, cwd=str(ROOT))
    # Under -Werror (the shipped extensions) every diagnostic is a failure and
    # is shown; the test modules are compiled without it, and their
    # all-lowercase-name warnings are noise there.
    noise = [l for l in (r.stdout + r.stderr).splitlines()
             if l.strip() and (werror or "All-lowercase name" not in l) and not l.startswith(" ")]
    log.append("$ " + " ".join(cmd))
    log.extend(noise)
    if r.returncode != 0 or not out_lcm.is_file():
        sys.stderr.write("COMPILE FAILED: %s\n%s%s\n" % (src.relative_to(ROOT) if ROOT in src.parents else src,
                                                      r.stdout, r.stderr))
        return False
    return True


# ---------------------------------------------------------------------------
# Native staging
# ---------------------------------------------------------------------------

def stage_libs(stage_dir, needs, libs):
    """Copy the needed libraries into stage_dir under the bare binding name.

    lc-run has no revLibraryMapping: "c:oscxt>sym" is a raw dlopen("oscxt") on
    POSIX (so the file must be literally named "oscxt" -- no suffix is added --
    and be on LD_LIBRARY_PATH / in the cwd) and LoadLibrary("oscxt") on Windows
    (which appends .dll and searches the cwd and PATH)."""
    if stage_dir.exists():
        shutil.rmtree(stage_dir)
    stage_dir.mkdir(parents=True)
    for key in needs:
        path, _ = libs[key]
        token = LIBRARIES[key][0]
        shutil.copy2(path, stage_dir / (token + LIB_EXT))
        if not IS_WIN:
            shutil.copy2(path, stage_dir / token)


def run_env(stage_dir):
    env = dict(os.environ)
    s = str(stage_dir)
    if IS_WIN:
        env["PATH"] = s + os.pathsep + env.get("PATH", "")
    elif IS_MAC:
        env["DYLD_LIBRARY_PATH"] = s + os.pathsep + env.get("DYLD_LIBRARY_PATH", "")
    else:
        env["LD_LIBRARY_PATH"] = s + os.pathsep + env.get("LD_LIBRARY_PATH", "")
    return env


# ---------------------------------------------------------------------------
# Running + TAP parsing
# ---------------------------------------------------------------------------

class Result:
    def __init__(self, suite, handler):
        self.suite, self.handler = suite, handler
        self.ok, self.notok, self.skip, self.todo = [], [], [], []
        self.diags, self.status, self.stderr, self.seconds = [], 0, "", 0.0
        self.timed_out = False

    @property
    def name(self):
        return "%s::%s" % (self.suite, self.handler)

    @property
    def verdict(self):
        if self.timed_out or self.status != 0 or self.notok:
            return "FAIL"
        if not self.ok and self.skip:
            return "SKIP"
        if not self.ok:
            return "FAIL"           # ran, asserted nothing: a collapsed test is a failure
        return "PASS"


TAP_OK = re.compile(r"^ok\b(?:\s*-\s*)?(.*)$")
TAP_NOTOK = re.compile(r"^not ok\b(?:\s*-\s*)?(.*)$")


def parse_tap(text, res):
    for raw in text.splitlines():
        line = raw.rstrip("\r")
        m = TAP_NOTOK.match(line)
        if m:
            desc = m.group(1)
            if "# TODO" in desc:            # broken test (expected failure)
                res.todo.append(desc)
            else:
                res.notok.append(desc)
            continue
        m = TAP_OK.match(line)
        if m:
            desc = m.group(1)
            if "# SKIP" in desc:
                res.skip.append(desc)
            elif "# TODO" in desc:
                res.todo.append(desc)
            else:
                res.ok.append(desc)
            continue
        if line.startswith("#"):
            res.diags.append(line)
        elif line.strip():
            res.diags.append("# " + line)  # VM error trace lines etc.


def list_handlers(lc_run, loads, lcm, cwd, env):
    r = subprocess.run([str(lc_run)] + loads + ["--list-handlers", str(lcm)],
                       capture_output=True, text=True, cwd=str(cwd), env=env, timeout=60)
    if r.returncode != 0:
        raise RuntimeError("lc-run --list-handlers failed for %s:\n%s%s" % (lcm.name, r.stdout, r.stderr))
    return [h.strip() for h in r.stdout.splitlines() if h.strip().startswith("Test")]


def run_handler(lc_run, loads, lcm, handler, cwd, env, timeout, suite):
    res = Result(suite, handler)
    t0 = time.time()
    try:
        r = subprocess.run([str(lc_run)] + loads + ["--handler", handler, str(lcm)],
                           capture_output=True, text=True, cwd=str(cwd), env=env,
                           timeout=timeout, errors="replace")
        res.status = r.returncode
        parse_tap(r.stdout, res)
        res.stderr = r.stderr
        # lc-run prints an uncaught LCB error ("ERROR: Uncaught error: ...") and
        # its stack to stdout/stderr and exits non-zero; surface it as a failure.
        if r.returncode != 0:
            tail = (r.stdout + r.stderr).strip().splitlines()[-6:]
            res.notok.append("handler exited with status %d%s" % (
                r.returncode, (": " + " | ".join(tail)) if tail else " (crash -- no output)"))
    except subprocess.TimeoutExpired:
        res.timed_out = True
        res.notok.append("timed out after %ds" % timeout)
    res.seconds = time.time() - t0
    return res


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--oxt-bin", help="folder holding lc-compile, lc-run and modules/lci (or $OXT_BIN)")
    ap.add_argument("--build-dir", default=str(ROOT / "build"), help="CMake build dir to find native libs in")
    ap.add_argument("--work-dir", help="scratch dir (default <build-dir>/lcb-tests)")
    ap.add_argument("--lib", action="append", metavar="KEY=PATH",
                    help="use this file for library KEY (keys: %s); repeatable" % ", ".join(LIB_KEYS))
    ap.add_argument("--filter", help="regex on suite::handler")
    ap.add_argument("--timeout", type=int, default=120, help="seconds per test handler")
    ap.add_argument("--require-all", action="store_true",
                    default=os.environ.get(CFG.MEMBER.upper() + "_REQUIRE_ALL") == "1",
                    help="a suite skipped for a missing native library is a FAILURE")
    ap.add_argument("--min-assertions", type=int, default=0,
                    help="fail if fewer assertions passed in total (guards a collapsed run)")
    ap.add_argument("--tap-out", help="write the combined TAP stream here")
    ap.add_argument("-v", "--verbose", action="store_true")
    args = ap.parse_args()

    lc_compile, lc_run, lci_dir = find_toolchain(args.oxt_bin)
    build_dir = Path(args.build_dir).resolve()
    work = Path(args.work_dir).resolve() if args.work_dir else build_dir / "lcb-tests"
    mod_dir, gen_dir, stage_root = work / "modules", work / "gen", work / "stage"
    if work.exists():
        shutil.rmtree(work)
    for d in (mod_dir, gen_dir, stage_root):
        d.mkdir(parents=True)

    print("toolchain : %s" % lc_compile.parent)
    libs = resolve_libs(args)
    for key in LIB_KEYS:
        if key in libs:
            print("lib %-9s: %s  [%s]" % (key, libs[key][0], libs[key][1]))
        else:
            print("lib %-9s: (not available)" % key)

    # ---- 1. compile the extensions (a real compile gate, -Werror as the IDE) --
    log = []
    loads = []
    ok = True
    for name, src in EXTENSIONS:
        out = mod_dir / (name + ".lcm")
        manifest = mod_dir / (name + "-manifest.xml")
        if compile_lcb(lc_compile, lci_dir, mod_dir, src, out, log, manifest, werror=True):
            loads += ["-l", str(out)]
        else:
            ok = False

    # ---- 2. generate the vectors module from tests/vectors/*.json -----------
    import gen_vectors                          # tools/gen_vectors.py
    gen_src = gen_dir / "vectors_test.lcb"
    gen_vectors.write_lcb_module(gen_src)

    # ---- 3. support libraries, then test modules -----------------------------
    for src in sorted(TEST_DIR.glob("_*.lcb")):
        out = mod_dir / (src.stem.lstrip("_") + ".lcm")
        if compile_lcb(lc_compile, lci_dir, mod_dir, src, out, log):
            loads += ["-l", str(out)]
        else:
            ok = False
    tests = []
    for src in sorted(TEST_DIR.glob("*_test.lcb")) + [gen_src]:
        out = mod_dir / (src.stem + ".lcm")
        if compile_lcb(lc_compile, lci_dir, mod_dir, src, out, log):
            req = REQUIRES_RE.search(src.read_text(encoding="utf-8"))
            needs = req.group(1).split() if req else []
            bad = [n for n in needs if n not in LIB_KEYS]
            if bad:
                sys.stderr.write("%s: unknown library key(s) in requires: %s\n" % (src.name, bad))
                ok = False
            tests.append((src.stem, out, needs))
        else:
            ok = False
    if args.verbose:
        print("\n".join(log))
    if not ok:
        print("\nrun-lcb-tests: compilation failed (see above)")
        return 2
    print("compiled  : %d extension(s), %d test module(s)\n" % (len(EXTENSIONS), len(tests)))

    # ---- 4/5. stage + run ------------------------------------------------------
    flt = re.compile(args.filter) if args.filter else None
    results, skipped_suites = [], []
    for suite, lcm, needs in tests:
        missing = [n for n in needs if n not in libs]
        if missing:
            skipped_suites.append((suite, missing))
            print("SKIP  %s  (needs %s)" % (suite, ", ".join(missing)))
            continue
        stage = stage_root / suite
        stage_libs(stage, needs, libs)
        env = run_env(stage)
        try:
            handlers = list_handlers(lc_run, loads, lcm, stage, env)
        except Exception as e:  # noqa: BLE001 -- report and fail the suite
            r = Result(suite, "<load>")
            r.notok.append(str(e))
            results.append(r)
            print("FAIL  %s::<load>  %s" % (suite, e))
            continue
        for h in handlers:
            if flt and not flt.search("%s::%s" % (suite, h)):
                continue
            r = run_handler(lc_run, loads, lcm, h, stage, env, args.timeout, suite)
            results.append(r)
            v = r.verdict
            print("%-5s %-46s %3d ok%s  %.1fs" % (
                v, r.name, len(r.ok),
                (", %d skip" % len(r.skip)) if r.skip else "", r.seconds))
            if v == "FAIL" or args.verbose:
                for d in r.notok:
                    print("        not ok - " + d)
                for d in r.diags[-12:]:
                    print("        " + d)

    # ---- summary ----------------------------------------------------------------
    n_fail = sum(1 for r in results if r.verdict == "FAIL")
    n_pass = sum(1 for r in results if r.verdict == "PASS")
    n_skip = sum(1 for r in results if r.verdict == "SKIP")
    n_assert = sum(len(r.ok) for r in results)
    n_bad = sum(len(r.notok) for r in results)
    print("\n" + "=" * 72)
    print("LCB headless: %d handler(s) passed, %d failed, %d skipped; %d assertion(s) ok, %d not ok"
          % (n_pass, n_fail, n_skip, n_assert, n_bad))
    rc = 0
    if n_fail:
        rc = 1
    if skipped_suites:
        msg = "; ".join("%s (needs %s)" % (s, ", ".join(m)) for s, m in skipped_suites)
        if args.require_all:
            print("FAIL: suites skipped under --require-all: " + msg)
            rc = 1
        else:
            print("NOTE: suites skipped (pass --require-all to make this fatal): " + msg)
    if args.min_assertions and n_assert < args.min_assertions:
        print("FAIL: only %d assertion(s) passed; the floor is %d (did a suite stop running?)"
              % (n_assert, args.min_assertions))
        rc = 1
    print("=" * 72)

    if args.tap_out:
        with open(args.tap_out, "w", encoding="utf-8") as f:
            for r in results:
                f.write("# %s  [%s]\n" % (r.name, r.verdict))
                for d in r.ok:
                    f.write("ok - %s\n" % d)
                for d in r.skip:
                    f.write("ok - %s\n" % d)
                for d in r.notok:
                    f.write("not ok - %s\n" % d)
                for d in r.diags:
                    f.write("%s\n" % d)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("### %s: LCB headless suite (%s)\n\n" % (CFG.MEMBER, host_platform_id()))
            f.write("| result | handler | ok | not ok |\n|---|---|---|---|\n")
            for r in results:
                f.write("| %s | `%s` | %d | %d |\n" % (r.verdict, r.name, len(r.ok), len(r.notok)))
            f.write("\n**%d passed, %d failed, %d skipped -- %d assertions**\n\n" % (n_pass, n_fail, n_skip, n_assert))
    return rc


if __name__ == "__main__":
    sys.exit(main())
