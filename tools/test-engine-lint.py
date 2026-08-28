#!/usr/bin/env python3
"""test-engine-lint.py - prove check-engine-lint.py's refusals actually fire.

WHY THIS EXISTS. check-engine-lint.py cannot be run for real anywhere in this
project's CI today: there is no engine on the machine. That is exactly the
situation in which a driver ships blind - its parser never sees a report, its
refusals never fire, and the first person to point an engine at it discovers
that the gate has been a no-op wearing a gate's vocabulary. This repository has
that failure four times over in its own CLAUDE.md, including one gate whose
mutation test drove a FUNCTION with a hand-built input the PIPELINE never
produces ("component verified, system claimed").

So this test drives the REAL tool as a SUBPROCESS, the way tools/build-all.sh
runs it, against a FAKE ENGINE: a small script that speaks the report format and
can be told to lie in one specific way per run. Each mutation asserts the tool
REFUSES; the unmutated baseline asserts it does not. The baseline is not
ceremony - without it every mutation could be "passing" because the tool refuses
everything, which is the same no-op in the other direction.

WHAT THIS DOES NOT PROVE, stated plainly because the distinction is the whole
honesty of this lane: the fake engine emits a report in the format
tools/engine-lint.livecodescript is WRITTEN to emit, and nothing here has ever
seen a real engine. So this proves the DRIVER handles the format correctly. It
does not prove a real engine produces that format, that `set the script of`
reports compile errors through `the result`, or that the server engine will run
the wrapper at all. Those are what tools/engine-probe.livecodescript is for, and
until it has run they stay DOCUMENTED under this tree's evidence rule. If the
first real run shows a different shape, the format changes and these fixtures
change with it - that is a cheap edit, and it is the point of keeping the
assumption in one place.

Usage:
  python3 tools/test-engine-lint.py
"""

import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TOOL = os.path.join(HERE, "check-engine-lint.py")

# The fake engine. It is handed the generated wrapper, digs the manifest path out
# of the xtLintRun(...) call inside it - so a driver that stopped writing a
# manifest would break this test rather than sneak past it - and prints a report
# over exactly those paths. XT_FAKE_MUTATE names the single lie to tell.
FAKE = r'''#!/usr/bin/env python3
import os, re, sys, time
mut = os.environ.get("XT_FAKE_MUTATE", "")
wrapper = open(sys.argv[1]).read()

if mut == "silent":
    sys.exit(0)
if mut == "hang":
    time.sleep(30)
    sys.exit(0)

if "xtProbeRun(" in wrapper.split("-- XT-ENGINE-ENTRY-CALL")[-1]:
    print("XTPROBE-BEGIN\t1")
    rows = [("engine.environment", "INFO", "server"),
            ("engine.version", "INFO", "9.6.3"),
            ("object.createStack", "YES", "there is a stack -> true"),
            ("compile.goodIsClean", "YES", "the result ->"),
            ("compile.badIsReported", "YES", "the result -> compile error")]
    for r in rows:
        print("PROBE\t%s\t%s\t%s" % r)
    print("XTPROBE-END\t%d" % len(rows))
    sys.exit(0)

# The entry call is found through the driver's sentinel, NOT by searching the
# wrapper for xtLintRun(...). The first version of this fake did the latter and
# matched the USAGE EXAMPLE inside engine-lint.livecodescript's own header
# comment, so it went looking for "/abs/path/to/manifest.txt" and every case
# below "passed" for the wrong reason. Kept as a comment because it is the
# repo's own comment-versus-code trap, landing inside the tool written to guard
# against exactly that class.
lines = wrapper.split("\n")
call = None
for i, ln in enumerate(lines):
    if ln.startswith("-- XT-ENGINE-ENTRY-CALL") and i + 1 < len(lines):
        call = lines[i + 1]
        break
if call is None:
    sys.stderr.write("fake engine: the wrapper carries no entry-call sentinel\n")
    sys.exit(3)
m = re.search(r'xtLintRun\("([^"]+)"\)', call)
if not m:
    sys.stderr.write("fake engine: the entry call is not xtLintRun: %s\n" % call)
    sys.exit(3)
paths = [l.strip() for l in open(m.group(1)) if l.strip()]

recs = []
good = "OK" if mut != "good-fails" else "FAIL"
bad = "FAIL" if mut != "bad-compiles" else "OK"
recs.append(("CONTROL", "known-good", good, ""))
recs.append(("CONTROL", "known-bad", bad, "line 2: zero-argument call"))
if mut == "no-controls":
    recs = []
if mut == "fatal":
    recs.append(("FATAL", "host-stack", "ERROR", "cannot create stack"))

for i, p in enumerate(paths):
    if mut == "drop-one" and i == 3:
        continue
    verdict = "OK"
    if mut == "one-fails" and i == 2:
        verdict = "FAIL"
    if mut == "one-errors" and i == 2:
        verdict = "ERROR"
    detail = "chars=123; " + ("line 9: syntax error" if verdict != "OK" else "")
    recs.append(("FILE", p, verdict, detail))
if mut == "duplicate":
    recs.append(("FILE", paths[0], "OK", "chars=123; "))
if mut == "extra":
    recs.append(("FILE", os.path.join(os.path.dirname(paths[0]), "not-requested.livecodescript"),
                 "OK", "chars=1; "))

lines = []
if mut != "no-begin":
    lines.append("XTLINT-BEGIN\t1")
for r in recs:
    lines.append("%s\t%s\t%s\t%s" % r)
if mut != "no-end":
    count = len(recs) + (7 if mut == "bad-count" else 0)
    lines.append("XTLINT-END\t%d" % count)
if mut == "junk-record":
    lines.insert(2, "FILE\tonly-two-fields")
print("\n".join(lines))
'''

# (mutation, expected exit, a fragment that must appear in the output)
# expected exit 2 = REFUSED (the measurement is void); 1 = the corpus is dirty.
CASES = [
    ("",             0, "MEASURED"),
    ("bad-compiles", 2, "KNOWN-BAD control COMPILED"),
    ("good-fails",   2, "KNOWN-GOOD control did not compile"),
    ("no-controls",  2, "no known-good control"),
    ("no-begin",     2, "no XTLINT-BEGIN marker"),
    ("no-end",       2, "no XTLINT-END marker"),
    ("bad-count",    2, "records and carries"),
    ("drop-one",     2, "came back with no verdict"),
    ("duplicate",    2, "two verdicts in one report"),
    ("extra",        2, "were not requested"),
    ("junk-record",  2, "unparseable record"),
    ("fatal",        2, "fatal condition"),
    ("silent",       2, "no XTLINT-BEGIN marker"),
    ("one-fails",    1, "REJECTED BY THE ENGINE"),
    ("one-errors",   1, "ERRORED"),
]


def run(fake, mutation, extra=()):
    env = dict(os.environ)
    env["XT_FAKE_MUTATE"] = mutation
    env.pop("XT_ENGINE", None)
    proc = subprocess.run([sys.executable, TOOL, "--engine", fake] + list(extra),
                          cwd=ROOT, env=env, stdout=subprocess.PIPE,
                          stderr=subprocess.STDOUT)
    return proc.returncode, proc.stdout.decode("utf-8", "replace")


def main():
    failures = []
    with tempfile.TemporaryDirectory() as tmp:
        fake = os.path.join(tmp, "fake-engine")
        with open(fake, "w") as fh:
            fh.write(FAKE)
        os.chmod(fake, 0o755)

        for mutation, want_code, want_text in CASES:
            code, out = run(fake, mutation)
            label = mutation or "(baseline, unmutated)"
            if code != want_code:
                failures.append("%s: exit %d, wanted %d\n%s"
                                % (label, code, want_code, out[-1500:]))
            elif want_text not in out:
                failures.append("%s: exit %d as wanted, but the output never says "
                                "%r - the refusal that fired may not be the one "
                                "under test\n%s" % (label, code, want_text, out[-1500:]))
            else:
                print("  ok  %-14s -> exit %d (%s)" % (label, code, want_text[:40]))

        # The probe path parses too, and its own end marker is enforced.
        code, out = run(fake, "", extra=["--probe"])
        if code != 0 or "engine capability probe" not in out:
            failures.append("--probe: exit %d\n%s" % (code, out[-1500:]))
        else:
            print("  ok  %-14s -> exit 0 (probe report parsed)" % "--probe")

        code, out = run(fake, "silent", extra=["--probe"])
        if code != 1 or "PROBE REFUSED" not in out:
            failures.append("--probe silent: exit %d, wanted 1 with PROBE "
                            "REFUSED\n%s" % (code, out[-1500:]))
        else:
            print("  ok  %-14s -> exit 1 (probe refuses a silent engine)" % "--probe silent")

        code, out = run(fake, "hang", extra=["--timeout", "2"])
        if code != 2 or "timed out" not in out:
            failures.append("hang: exit %d, wanted 2 with a timeout refusal\n%s"
                            % (code, out[-1500:]))
        else:
            print("  ok  %-14s -> exit 2 (engine that never finishes)" % "hang")

        # A stale exemption must not outlive the file it excuses. Patched in the
        # real tool file and restored, the way test-cross-library-names.py
        # mutates real corpus files: a hand-built copy would prove something
        # about the copy.
        src = open(TOOL).read()
        assert "EXPECTED_FAILURES = {}" in src, "the exemption table moved"
        try:
            open(TOOL, "w").write(src.replace(
                "EXPECTED_FAILURES = {}",
                'EXPECTED_FAILURES = {"no/such/file.livecodescript": "stale"}'))
            code, out = run(fake, "")
            if code != 2 or "permanent excuse" not in out:
                failures.append("stale exemption: exit %d, wanted 2\n%s"
                                % (code, out[-1500:]))
            else:
                print("  ok  %-14s -> exit 2 (stale exemption refused)" % "stale-exempt")
        finally:
            open(TOOL, "w").write(src)

        # And the corpus floor: a glob that matches almost nothing must not be
        # allowed to report a clean tree.
        code, out = run(fake, "", extra=["--only", "no-such-pattern/*"])
        if code != 2 or "no files matched" not in out:
            failures.append("empty --only: exit %d, wanted 2\n%s" % (code, out[-1500:]))
        else:
            print("  ok  %-14s -> exit 2 (empty selection refused)" % "empty-only")

    if failures:
        print("\ntest-engine-lint: %d FAILURE(S)\n" % len(failures))
        for f in failures:
            print(f + "\n")
        return 1
    print("\ntest-engine-lint: OK - every refusal fires, and the unmutated "
          "baseline passes (so they are refusals, not a tool that refuses "
          "everything).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
