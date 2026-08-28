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
import time
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
    sys.stdout.write("XTLINT-BEGIN\t1\nCONTROL\tknown-good-pre\tOK\t\n")
    sys.stdout.flush()
    time.sleep(30)
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

if "xtProbeRun(" in call:
    rows = [("probe.selfArithmetic", "YES", "2 + 2 -> 4"),
            ("probe.emitRoundTrip", "YES", "a b<NL>c"),
            ("engine.environment", "INFO", "server"),
            ("engine.version", "INFO", "9.6.3"),
            ("object.createStack", "YES", "there is a stack -> true"),
            ("compile.goodIsClean", "YES", "the result ->"),
            ("compile.badIsReported", "YES", "the result -> compile error"),
            ("compile.resultClearedOnSuccess", "YES", "the result ->"),
            ("runtime.sendInTime", "YES", "ticked -> true")]
    if mut == "probe-no-mandatory":
        rows = [r for r in rows if r[0] != "probe.selfArithmetic"]
    if mut == "probe-mandatory-error":
        rows = [(r[0], "ERROR", "boom") if r[0].startswith("probe.") else r for r in rows]
    if mut == "probe-all-no":
        rows = [(r[0], "NO", r[2]) if (r[1] == "YES" and not r[0].startswith("probe.")) else r
                for r in rows]
    if mut == "probe-all-error":
        rows = [(r[0], "ERROR", "boom") for r in rows]
    if mut == "probe-no-identity":
        rows = [r for r in rows if not r[0].startswith("engine.")]
    if mut == "probe-empty-identity":
        # present, well-formed, and worthless - the shape a `do`-scope bug
        # produces, and the one an absence check alone would wave through
        rows = [(r[0], r[1], "") if r[0].startswith("engine.") else r for r in rows]
    print("XTPROBE-BEGIN\t1")
    for r in rows:
        print("PROBE\t%s\t%s\t%s" % r)
    print("XTPROBE-END\t%d" % len(rows))
    sys.exit(0)

m = re.search(r'xtLintRun\("([^"]+)"\)', call)
if not m:
    sys.stderr.write("fake engine: the entry call is not xtLintRun: %s\n" % call)
    sys.exit(3)
paths = [l.strip() for l in open(m.group(1)) if l.strip()]

recs = []
def ctl(name, verdict, detail=""):
    recs.append(("CONTROL", name, verdict, detail))

if mut != "no-controls":
    ctl("known-good-pre", "FAIL" if mut == "good-fails" else "OK")
    ctl("known-bad-pre", "OK" if mut == "bad-compiles" else "FAIL",
        "line 2: zero-argument call")
    if mut != "no-large-control":
        ctl("known-bad-large", "OK" if mut == "big-control-ok" else "FAIL",
            "line 20001: zero-argument call")
    if mut == "control-dupe":
        ctl("known-good-pre", "OK")
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
    size = os.path.getsize(p)
    if mut == "chars-lie" and i == 1:
        size = size // 2
    if mut == "chars-missing" and i == 1:
        detail = "no size field here"
        recs.append(("FILE", p, verdict, detail))
        continue
    detail = "chars=%d; " % size + ("line 9: syntax error" if verdict != "OK" else "")
    if mut == "cascade" and i < 5:
        verdict = "FAIL"
        detail = "chars=%d; Handler: error in statement" % size
    if mut == "shared-block":
        # two carriers of one broken block, plus two unrelated failures: the
        # identical group is NOT a majority, so it must not be read as a cascade
        if i in (0, 1):
            verdict = "FAIL"
            detail = "chars=%d; line 40: the carried block is broken" % size
        elif i in (2, 3):
            verdict = "FAIL"
            detail = "chars=%d; line %d: something else entirely" % (size, i)
    recs.append(("FILE", p, verdict, detail))
if mut == "duplicate":
    recs.append(("FILE", paths[0], "OK", "chars=%d; " % os.path.getsize(paths[0])))
if mut == "extra":
    recs.append(("FILE", os.path.join(os.path.dirname(paths[0]), "not-requested.livecodescript"),
                 "OK", "chars=1; "))

if mut not in ("no-controls", "no-post-controls"):
    ctl("known-good-post", "OK")
    ctl("known-bad-post", "OK" if mut == "post-degrades" else "FAIL",
        "line 2: zero-argument call")

out_lines = []
if mut != "no-begin":
    out_lines.append("XTLINT-BEGIN\t1")
for r in recs:
    out_lines.append("%s\t%s\t%s\t%s" % r)
if mut != "no-end":
    count = len(recs) + (7 if mut == "bad-count" else 0)
    out_lines.append("XTLINT-END\t%d" % count)
if mut == "junk-record":
    out_lines.insert(2, "FILE\tonly-two-fields")
print("\n".join(out_lines))

'''

# (mutation, expected exit, a fragment that must appear in the output)
# expected exit 2 = REFUSED (the measurement is void); 1 = the corpus is dirty.
CASES = [
    ("",                 0, "MEASURED"),
    ("bad-compiles",     2, "known-bad-pre control COMPILED"),
    ("post-degrades",    2, "stopped checking partway through"),
    ("big-control-ok",   2, "size-dependent"),
    ("no-large-control", 2, "missing control(s) known-bad-large"),
    ("no-post-controls", 2, "known-good-post"),
    ("control-dupe",     2, "two CONTROL records named"),
    ("chars-lie",        2, "engine read"),
    ("chars-missing",    2, "no chars= field"),
    ("cascade",          2, "signature of one error copied down the run"),
    # The DISCRIMINATION that matters: two carriers of one broken block
    # share error text legitimately (this tree carries four blocks
    # byte-identically into a dozen files each). That must report a dirty
    # corpus (exit 1), not refuse the measurement (exit 2).
    ("shared-block",     1, "REJECTED BY THE ENGINE"),
    ("good-fails",       2, "known-good-pre control did not compile"),
    ("no-controls",      2, "missing control(s)"),
    ("no-begin",         2, "no XTLINT-BEGIN marker"),
    ("no-end",           2, "no XTLINT-END marker"),
    ("bad-count",        2, "records and carries"),
    ("drop-one",         2, "came back with no verdict"),
    ("duplicate",        2, "two FILE records named"),
    ("extra",            2, "were not requested"),
    ("junk-record",      2, "unparseable record"),
    ("fatal",            2, "fatal condition"),
    ("silent",           2, "no XTLINT-BEGIN marker"),
    ("one-fails",        1, "REJECTED BY THE ENGINE"),
    ("one-errors",       1, "ERRORED"),
]



def _patch_lock(what):
    """Serialize the in-place patch below against another copy of this suite.

    Two of the fixture cases MUTATE THE REAL TOOL FILE and restore it in a
    finally - the idiom tools/test-cross-library-names.py already uses, and the
    right one, because a hand-built copy would prove a property of the copy. The
    cost is that two concurrent runs corrupt each other: a background
    `build-all.sh --gates` sweep raced an interactive run of this suite and the
    second died on `AssertionError: the exemption table moved`, which reads like
    a real regression and is not one.

    A lock file, not a redesign. It fails LOUDLY after a bounded wait rather than
    hanging, and the message says what is actually happening, because the whole
    reason this exists is that the raw symptom was misleading."""
    path = os.path.join(tempfile.gettempdir(), "xt-engine-fixture.lock")
    for _ in range(600):                       # 60s, in 100ms steps
        try:
            fd = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
            os.write(fd, str(os.getpid()).encode())
            os.close(fd)
            return path
        except FileExistsError:
            time.sleep(0.1)
    raise SystemExit(
        "%s: another copy of this fixture suite has held the in-place-patch "
        "lock (%s) for 60s. Two runs cannot patch the same tool file at once. "
        "If no other run is live, delete that file." % (what, path))


def _patch_unlock(path):
    try:
        os.remove(path)
    except OSError:
        pass


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
        PROBE_CASES = [
            ("",                      0, "XT-ENGINE-STATUS: MEASURED"),
            # An engine may legitimately answer NO to every capability - that is
            # a successful measurement of a limited engine. It may NOT produce a
            # report that fails to prove anything executed.
            ("probe-all-no",          0, "capabilities: 0 YES"),
            ("probe-no-mandatory",    1, "probe.selfArithmetic is MISSING"),
            ("probe-mandatory-error", 1, "is ERROR"),
            ("probe-all-error",       1, "failing to ASK"),
            ("probe-no-identity",     1, "cannot be pinned to a build"),
            ("probe-empty-identity",  1, "cannot be pinned to a build"),
        ]
        for mutation, want_code, want_text in PROBE_CASES:
            code, out = run(fake, mutation, extra=["--probe"])
            label = "--probe " + (mutation or "baseline")
            if code != want_code or want_text not in out:
                failures.append("%s: exit %d (wanted %d) / missing %r\n%s"
                                % (label, code, want_code, want_text, out[-1500:]))
            else:
                print("  ok  %-26s -> exit %d (%s)" % (label, code, want_text[:40]))

        # Exactly one machine-readable status line per run, on every path. CI
        # asserts on it; prose is what changes when a message is improved.
        for mutation, want in (("", "MEASURED"), ("bad-compiles", "REFUSED")):
            code, out = run(fake, mutation)
            tail = [l for l in out.strip().split("\n") if l.startswith("XT-ENGINE-STATUS:")]
            if len(tail) != 1 or tail[0].split(": ", 1)[1] != want:
                failures.append("status line for %r: got %r, wanted exactly one %s"
                                % (mutation or "baseline", tail, want))
            else:
                print("  ok  %-26s -> %s" % ("status-line " + (mutation or "baseline"), tail[0]))

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
        lock = _patch_lock("test-engine-lint")
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
            _patch_unlock(lock)

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
    print("  PROVES: the DRIVER, against a FAKE engine speaking the format "
          "tools/engine-lint.livecodescript is written to emit.")
    print("  DOES NOT PROVE: that any real engine emits that format, that "
          "`set the script of` reports compile errors at all, or that a server "
          "engine will run the wrapper. No engine has run. See "
          "docs/HEADLESS-ENGINE.md.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
