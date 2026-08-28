#!/usr/bin/env python3
"""test-lcb-compile.py - prove check-lcb-compile.py's refusals actually fire.

Same argument as tools/test-engine-lint.py, and the same limits. There is no
lc-compile on this machine, so the driver would otherwise ship with its control
logic never once executed - and a control that has never fired is a control in
name only. This drives the REAL tool as a subprocess, the way tools/build-all.sh
runs it, against a FAKE COMPILER that can be told to lie in one way per run.

WHAT IT PROVES: the driver's handling of a compiler's results. Every refusal
fires on the shape it names, and the unmutated baseline passes - without which
the refusals could all be one tool that refuses everything.

WHAT IT DOES NOT PROVE: that lc-compile's real command line is the one the driver
builds, that a foreign binding resolves at load time rather than compile time, or
that the six modules actually compile. Those are DOCUMENTED claims under this
tree's evidence rule until a real compiler has run, and the driver is written to
print the exact command it used so the first run corrects one string.

Usage:
  python3 tools/test-lcb-compile.py
"""

import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TOOL = os.path.join(HERE, "check-lcb-compile.py")

# The fake compiler. It reads --output and the trailing source path, then
# decides by BASENAME. XT_FAKE_LCB names the single lie for this run.
FAKE = r'''#!/usr/bin/env python3
import os, sys
mut = os.environ.get("XT_FAKE_LCB", "")
argv = sys.argv[1:]
out = None
src = None
i = 0
while i < len(argv):
    if argv[i] == "--output":
        out = argv[i + 1]; i += 2; continue
    if argv[i] == "--modulepath":
        i += 2; continue
    if argv[i].startswith("-"):
        i += 1; continue
    src = argv[i]; i += 1
if src is None:
    sys.stderr.write("fake lc-compile: no source given\n"); sys.exit(2)
name = os.path.basename(src)

def ok():
    if out and mut != "no-output":
        open(out, "w").write("fake module\n")
    sys.exit(0)

def bad(msg):
    sys.stdout.write("%s:12:5: error: %s\n" % (src, msg))
    sys.exit(1)

if name == "known_good.lcb":
    bad("injected known-good failure") if mut == "good-fails" else ok()
elif name == "known_bad.lcb":
    ok() if mut == "bad-compiles" else bad("unterminated handler")
elif name == "depth_probe.lcb":
    ok() if mut == "depth-accepted" else bad("wrong number of arguments")
else:
    if mut == "module-fails" and name == "enet.lcb":
        bad("type mismatch in foreign handler declaration")
    ok()
'''

CASES = [
    ("",               0, "MEASURED"),
    ("good-fails",     2, "KNOWN-GOOD control did not compile"),
    ("bad-compiles",   2, "KNOWN-BAD control COMPILED"),
    ("no-output",      2, "KNOWN-GOOD control did not compile"),
    ("module-fails",   1, "REJECTED BY THE COMPILER"),
    ("depth-accepted", 0, "parses but does not check call arity"),
    ("",               0, "checks call arity"),
]


def run(fake, mutation, extra=()):
    env = dict(os.environ)
    env["XT_FAKE_LCB"] = mutation
    env.pop("XT_LC_COMPILE", None)
    proc = subprocess.run([sys.executable, TOOL, "--lc-compile", fake] + list(extra),
                          cwd=ROOT, env=env, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT)
    return proc.returncode, proc.stdout.decode("utf-8", "replace")


def main():
    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        fake = os.path.join(tmp, "fake-lc-compile")
        with open(fake, "w") as fh:
            fh.write(FAKE)
        os.chmod(fake, 0o755)

        for mutation, want_code, want_text in CASES:
            code, out = run(fake, mutation)
            label = mutation or "(baseline)"
            if code != want_code:
                failures.append("%s: exit %d, wanted %d\n%s"
                                % (label, code, want_code, out[-1200:]))
            elif want_text not in out:
                failures.append("%s: exit %d as wanted, but the output never says "
                                "%r\n%s" % (label, code, want_text, out[-1200:]))
            else:
                print("  ok  %-16s -> exit %d (%s)" % (label, code, want_text[:44]))

        # `no-output` deserves its own note: an exit code of 0 with no artefact
        # is the exact shape that lets a miswired compiler lane report a clean
        # compile of nothing. The case above proves the driver refuses it on the
        # CONTROL, which is where it must be caught - by the time a real module
        # silently produced nothing, the run would already be reporting success.

        # Exactly one machine-readable status line per run, on every path -
        # including the error paths, where a shadowed name once made the call
        # itself raise. The fixture suite caught that; nothing else would have.
        for mutation, want in (("", "MEASURED"), ("good-fails", "REFUSED"),
                               ("module-fails", "MEASURED")):
            code, out = run(fake, mutation)
            tail = [l for l in out.strip().split("\n") if l.startswith("XT-ENGINE-STATUS:")]
            if len(tail) != 1 or tail[0].split(": ", 1)[1] != want:
                failures.append("status line for %r: got %r, wanted exactly one %s"
                                % (mutation or "baseline", tail, want))
            else:
                print("  ok  %-16s -> %s" % ("status " + (mutation or "baseline"), tail[0]))

        code, out = run(fake, "", extra=["--only", "nothing-matches-this"])
        if code != 2 or "matched no module" not in out:
            failures.append("empty --only: exit %d, wanted 2\n%s" % (code, out[-1200:]))
        else:
            print("  ok  %-16s -> exit 2 (empty selection refused)" % "empty-only")

        # A module named in MODULES but absent from the tree must fail rather
        # than shrink the corpus silently - the denominator-floor lesson this
        # repo learned when an unterminated comment took 69 handlers out of a
        # coverage count and turned the row green at a smaller wrong number.
        src = open(TOOL).read()
        assert '"enetxt/src/enet.lcb",' in src, "the module list moved"
        try:
            open(TOOL, "w").write(src.replace('"enetxt/src/enet.lcb",',
                                              '"enetxt/src/no-such-module.lcb",'))
            code, out = run(fake, "")
            if code != 2 or "not in the tree" not in out:
                failures.append("missing module: exit %d, wanted 2\n%s" % (code, out[-1200:]))
            else:
                print("  ok  %-16s -> exit 2 (a named module missing from the tree)" % "missing-module")
        finally:
            open(TOOL, "w").write(src)

    if failures:
        print("\ntest-lcb-compile: %d FAILURE(S)\n" % len(failures))
        for f in failures:
            print(f + "\n")
        return 1
    print("\ntest-lcb-compile: OK - every refusal fires, and the unmutated "
          "baseline passes.")
    print("  PROVES: the DRIVER, against a FAKE compiler.")
    print("  DOES NOT PROVE: that lc-compile's real command line is the one the "
          "driver builds, that a foreign binding resolves at load time rather "
          "than compile time, or that the six modules compile. No compiler has "
          "run. See docs/HEADLESS-ENGINE.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
