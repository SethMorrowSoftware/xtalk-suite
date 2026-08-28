#!/usr/bin/env python3
"""check-lcb-compile.py - run the REAL LiveCode Builder compiler over the .lcb corpus.

THE PRIZE HERE IS BIGGER THAN THE SCRIPT SIDE, AND THE CONFIDENCE IS HIGHER.

The suite's six .lcb modules are 10,297 lines that have never been compiled
except inside a GUI Extension Builder session, by hand, one member at a time.
Unlike LiveCodeScript, LCB is STATIC and TYPED: handlers declare parameter and
return types, `foreign handler` declarations carry a typed C signature, and
`variable` declarations are mandatory. Everything a type system can catch in
that corpus is currently caught by hand-written Python approximations -
tools/check-lcb-call-types.py walks the script-to-.lcb boundary argument by
argument precisely because none of the 630 public handlers has an optional
parameter and an empty value into `in pHost as Integer` is a hard runtime error
(engine notes 6.4); box2dxt/tools/check-lcb-signatures.py re-implements arity
and parameter-type agreement across 370 binds. A compiler does all of that as a
side effect of existing.

WHAT IS FAVOURABLE HERE, MEASURED RATHER THAN HOPED. Across all six modules the
only `use` clauses are com.livecode.foreign (6), com.livecode.arithmetic (2) and
com.livecode.string (2) - all builtin. There is no user module, no dependency
graph, and nothing to resolve between members: each file compiles alone against
the stock module path. And the foreign bindings are of the form
    binds to "c:enetxt>enx_abi_version!cdecl"
where the library token is looked up in the extension's code/<platform>/ folder.
STRONG EXPECTATION, and it is DOCUMENTED not OBSERVED: that lookup happens at
LOAD time, so lc-compile should not need any native .so present. If that turns
out to be wrong, this tool says so in the engine's own words rather than
guessing - and the fix (build the six libraries first) is one CI step.

THE INVOCATION IS DELIBERATELY OVERRIDABLE, because nobody here has run it.
The default command line below is this project's best reading of lc-compile's
interface and it is a CLAIM. The tool PRINTS the exact command it ran, every
run, so the first person with a compiler in front of them corrects one string
instead of reverse-engineering a wrapper. Use --lcb-arg to append flags and
--modulepath / XT_LCB_MODULEPATH to point at the builtin interface files.

THE CONTROLS, and why there are three kinds. A compiler lane can fail silently
in exactly the way this repository has documented four times: point it at
nothing, glob zero files, drop stderr, ignore the exit code, and it reports a
clean corpus it never read. So every run compiles, alongside the real corpus:

  KNOWN-GOOD    a minimal valid module. Must compile. If it does not, the
                invocation is wrong and NO verdict about the corpus is emitted.
  KNOWN-BAD     a structurally broken module (a handler with no `end handler`).
                Must fail. If a compiler accepts it, it is not checking, and a
                clean corpus report would be meaningless.
  DEPTH PROBE   a module that PARSES but is semantically wrong: a call with the
                wrong argument count. This one is INFORMATIVE, not required -
                whether lc-compile rejects it measures how much of
                check-lcb-call-types.py and check-lcb-signatures.py a real
                compiler would subsume. That is a measurement this project wants
                and does not have, so the tool reports it rather than asserting
                it.

The controls are written to a temp directory rather than committed. A broken
.lcb sitting in the tree would be walked by every gate that globs for one, and
an exemption in each of them is a worse trade than generating two files.

USAGE
  python3 tools/check-lcb-compile.py                     # skips loudly if absent
  XT_LC_COMPILE=/path/to/lc-compile python3 tools/check-lcb-compile.py
  python3 tools/check-lcb-compile.py --require           # the CI engine lane
  python3 tools/check-lcb-compile.py --lc-compile ... --modulepath ... --verbose
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

COMPILER_NAMES = ("lc-compile", "lc-compile-9", "lc_compile")

# The suite's .lcb corpus. Named explicitly rather than globbed: these six are
# the modules, and a seventh appearing is a thing a maintainer should have to
# add here on purpose. The floor below turns an accidental deletion into a
# failure instead of a smaller green number.
MODULES = (
    "sodiumxt/src/sodium.lcb",
    "torrentxt/src/torrent.lcb",
    "enetxt/src/enet.lcb",
    "datachannelxt/src/datachannel.lcb",
    "coinxt/src/coinxt.lcb",
    "box2dxt/src/box2dxt.lcb",
)

CONTROL_GOOD = '''library com.example.xtcontrolgood

metadata version is "1.0.0"
metadata author is "xTalk suite control"
metadata title is "control good"

public handler XtControlAdd(in pLeft as Integer, in pRight as Integer) returns Integer
   return pLeft + pRight
end handler

end library
'''

# Structurally broken: the handler is never closed, so the module closer is
# consumed looking for one. This is the same shape check-livecodescript.py's
# check_lcb_module rule approximates ("OXT otherwise consumes the whole file
# looking for the closer and reports a syntax error at end-of-file").
CONTROL_BAD = '''library com.example.xtcontrolbad

metadata version is "1.0.0"
metadata author is "xTalk suite control"
metadata title is "control bad"

public handler XtControlBroken(in pLeft as Integer) returns Integer
   return pLeft + 1

end library
'''

# Parses, but calls a two-parameter handler with one argument. Whether this is
# rejected is the DEPTH measurement described in the header.
CONTROL_DEPTH = '''library com.example.xtcontroldepth

metadata version is "1.0.0"
metadata author is "xTalk suite control"
metadata title is "control depth"

private handler XtControlTwo(in pLeft as Integer, in pRight as Integer) returns Integer
   return pLeft + pRight
end handler

public handler XtControlCaller() returns Integer
   return XtControlTwo(1)
end handler

end library
'''


class Refusal(Exception):
    """The measurement is void - not the same as the corpus being dirty."""


def find_compiler(explicit):
    if explicit:
        if not os.path.isfile(explicit):
            raise Refusal("--lc-compile %s does not exist" % explicit)
        return explicit, "--lc-compile"
    env = os.environ.get("XT_LC_COMPILE", "").strip()
    if env:
        if not os.path.isfile(env):
            raise Refusal("XT_LC_COMPILE=%s does not exist" % env)
        return env, "XT_LC_COMPILE"
    for name in COMPILER_NAMES:
        found = shutil.which(name)
        if found:
            return found, "PATH (%s)" % name
    return None, ("no --lc-compile, no XT_LC_COMPILE, and none of %s on PATH"
                  % ", ".join(COMPILER_NAMES))


def compile_one(compiler, src, outdir, modulepath, extra, timeout):
    """Return (ok, command, stdout+stderr).

    The command is returned so the caller can print it. That is not a debugging
    convenience: the flags below are this project's best reading of an interface
    it has never driven, and the single most useful thing a first real run can
    produce is the exact string that did or did not work."""
    out = os.path.join(outdir, os.path.basename(src) + ".lcm")
    cmd = [compiler]
    if modulepath:
        for entry in modulepath.split(os.pathsep):
            if entry:
                cmd += ["--modulepath", entry]
    cmd += ["--output", out]
    cmd += list(extra)
    cmd += [src]
    try:
        proc = subprocess.run(cmd, cwd=ROOT, timeout=timeout,
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    except FileNotFoundError:
        raise Refusal("could not execute %s" % compiler)
    except subprocess.TimeoutExpired:
        return False, cmd, "timed out after %ds" % timeout
    text = proc.stdout.decode("utf-8", "replace")
    # An exit code of 0 with no output file is the shape that would let a
    # miswired invocation report a clean compile of nothing at all, so both are
    # required. This is the same reasoning as the script lane's completeness
    # marker: a lane must be able to prove it did the work, not merely fail to
    # find a problem.
    produced = os.path.exists(out) and os.path.getsize(out) > 0
    return (proc.returncode == 0 and produced), cmd, text


def run_controls(compiler, outdir, modulepath, extra, timeout, verbose):
    tmp = os.path.join(outdir, "controls")
    os.makedirs(tmp, exist_ok=True)
    results = {}
    for name, body in (("known-good", CONTROL_GOOD),
                       ("known-bad", CONTROL_BAD),
                       ("depth-probe", CONTROL_DEPTH)):
        path = os.path.join(tmp, name.replace("-", "_") + ".lcb")
        with open(path, "w") as fh:
            fh.write(body)
        ok, cmd, text = compile_one(compiler, path, tmp, modulepath, extra, timeout)
        results[name] = (ok, text)
        if verbose:
            print("  control %-12s -> %s\n    %s" % (name, "compiled" if ok else "rejected",
                                                     " ".join(cmd)))
            if text.strip():
                for line in text.rstrip().split("\n")[:12]:
                    print("      " + line)

    good_ok, good_text = results["known-good"]
    bad_ok, bad_text = results["known-bad"]
    if not good_ok:
        raise Refusal(
            "the KNOWN-GOOD control did not compile, so the invocation is wrong "
            "and no verdict about the corpus would mean anything.\n"
            "  The compiler said:\n%s\n"
            "  Fix the command line with --modulepath / --lcb-arg (see this "
            "tool's header: the default flags are a documented CLAIM, not an "
            "observed interface)."
            % "\n".join("    " + l for l in good_text.rstrip().split("\n")[:20]))
    if bad_ok:
        raise Refusal(
            "the KNOWN-BAD control COMPILED. An unterminated handler was "
            "accepted, so this compiler is not checking anything a clean corpus "
            "report could rest on.")
    return results


def skip_notice(why, require):
    print("check-lcb-compile: %s" % ("REQUIRED BUT UNAVAILABLE" if require else "SKIPPED"))
    print("  reason: %s" % why)
    print("")
    print("  The six .lcb modules (10,297 lines of typed, foreign-bound code)")
    print("  have never been compiled outside a manual GUI session. This gate")
    print("  is what changes that, and it is inert until a compiler is named:")
    print("")
    print("      XT_LC_COMPILE=/path/to/lc-compile python3 tools/check-lcb-compile.py")
    print("")
    print("  See docs/HEADLESS-ENGINE.md. The default flags are a CLAIM until a")
    print("  first run corrects them; the tool prints the command it ran.")
    return 2 if require else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--lc-compile", dest="lc_compile", help="path to lc-compile")
    ap.add_argument("--modulepath", help="module interface path(s), os.pathsep-separated; "
                                         "defaults to $XT_LCB_MODULEPATH")
    ap.add_argument("--lcb-arg", action="append", default=[],
                    help="extra flag passed through to lc-compile (repeatable)")
    ap.add_argument("--require", action="store_true")
    ap.add_argument("--only", help="substring; compile only matching modules")
    ap.add_argument("--timeout", type=int, default=300)
    ap.add_argument("--verbose", action="store_true")
    args = ap.parse_args()

    try:
        compiler, how = find_compiler(args.lc_compile)
    except Refusal as exc:
        print("check-lcb-compile: REFUSED - %s" % exc)
        return 2
    if compiler is None:
        return skip_notice(how, args.require)

    modulepath = args.modulepath or os.environ.get("XT_LCB_MODULEPATH", "")
    print("check-lcb-compile: compiler from %s -> %s" % (how, compiler))
    print("  modulepath: %s" % (modulepath or "(none given - relying on the "
                                              "compiler's own default)"))

    missing = [m for m in MODULES if not os.path.isfile(os.path.join(ROOT, m))]
    if missing:
        print("check-lcb-compile: REFUSED - the module list names files that are "
              "not in the tree: %s" % ", ".join(missing))
        return 2

    targets = [m for m in MODULES if not args.only or args.only in m]
    if not targets:
        print("check-lcb-compile: REFUSED - --only %r matched no module" % args.only)
        return 2

    with tempfile.TemporaryDirectory() as outdir:
        try:
            controls = run_controls(compiler, outdir, modulepath, args.lcb_arg,
                                    args.timeout, args.verbose)
        except Refusal as exc:
            print("\ncheck-lcb-compile: REFUSED\n  %s" % exc)
            return 2

        depth_ok, depth_text = controls["depth-probe"]
        print("  controls  : known-good compiled, known-bad rejected")
        print("  depth     : a wrong-arity call was %s"
              % ("ACCEPTED - this compiler parses but does not check call arity, "
                 "so tools/check-lcb-call-types.py and box2dxt's "
                 "check-lcb-signatures.py keep their whole job"
                 if depth_ok else
                 "REJECTED - the compiler checks call arity, so the hand-written "
                 "arity gates are duplicating it and can be re-scoped"))
        if depth_text.strip() and args.verbose:
            for line in depth_text.rstrip().split("\n")[:10]:
                print("      " + line)

        failed = []
        for rel in targets:
            src = os.path.join(ROOT, rel)
            ok, cmd, text = compile_one(compiler, src, outdir, modulepath,
                                        args.lcb_arg, args.timeout)
            status = "compiled" if ok else "REJECTED"
            print("  %-34s %s" % (rel, status))
            if args.verbose:
                print("      " + " ".join(cmd))
            if not ok:
                failed.append((rel, text))

        if failed:
            print("\nREJECTED BY THE COMPILER:")
            for rel, text in failed:
                print("  %s" % rel)
                for line in text.rstrip().split("\n")[:25]:
                    print("      " + line)
            print("\n%d of %d module(s) rejected." % (len(failed), len(targets)))
            return 1

    print("\nMEASURED: all %d module(s) compile. That is a COMPILE result: it "
          "says the modules parse and satisfy whatever this compiler checks. It "
          "says nothing about whether a binding LOADS or a foreign call "
          "MARSHALS - those still need an engine." % len(targets))
    return 0


if __name__ == "__main__":
    sys.exit(main())
