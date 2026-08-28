#!/usr/bin/env python3
"""check-engine-lint.py - run the REAL engine over the script corpus.

WHY THIS EXISTS, AND WHY IT IS DIFFERENT FROM EVERY OTHER GATE HERE.

Every other gate in tools/ is a stand-in for a compiler this project believed it
could not run. Seventy-four places in the tree say so outright ("OXT has no
headless way to compile or run .livecodescript or .lcb"), and the whole static
apparatus - the unified checker's twenty-odd rules, the duplicate-declaration
scan, the constants-before-use walk, coinxt's hand-written LiveCodeScript
interpreter - is built on that premise. On 2026-08-27 a reply to the suite's
forum post said the premise is wrong: that the server engine and the LCB
compiler both run headless, and that text editors already lint LiveCodeScript
by driving the server engine. This tool is what that claim cashes out to if it
is true.

NOTHING HERE ASSUMES IT IS TRUE. The tool has three states and says which one it
is in, every run:

  SKIPPED   no engine configured. Prints how to configure one and exits 0, so it
            can sit in the always-on gate lane without pretending to have run.
            `--require` turns this into a hard failure, which is what the
            dedicated engine CI lane passes.
  MEASURED  an engine ran and the report came back complete and self-consistent.
            Only then does a verdict about the corpus mean anything.
  BROKEN    an engine ran and the report is not trustworthy - a control
            misbehaved, the completeness marker is missing, the record count
            disagrees, a requested file has no verdict. This exits non-zero
            WITHOUT reporting on the corpus at all, because a report that cannot
            account for itself must not be allowed to say the tree is clean.

THE CONTROLS ARE THE DESIGN, NOT A DETAIL. This repository's CLAUDE.md catalogues
gates that reported OK while measuring nothing: a coverage gate that counted a
SKIP NOTE as coverage, a constant gate that printed the count of constants it had
PARSED as the count it had CHECKED, a name-resolution gate blind to 2,476 lines
of one member, a collision detector defeated by a trailing comment. A lane that
shells out to an external binary is a fresh opportunity to join that list - the
binary can be missing, the wrapper can compile nothing, a glob can match zero
files, stderr can be dropped, an exit code can be ignored - and every one of
those failures looks exactly like success. So:

  * the engine-side script emits a KNOWN-GOOD and a KNOWN-BAD control on every
    run. Known-good must compile, known-bad must NOT. If the known-bad compiles,
    the engine is not checking anything and the whole report is refused.
  * the report carries a completeness marker with a record COUNT, and a report
    without it, or with a count that disagrees, is refused. (The tree already
    paid for this lesson once: a live harness surface that stops mid-run reads
    exactly like a finished one, and three truncated pastes were diagnosed as a
    hung pump before anyone noticed they were early copies.)
  * every path in the manifest must come back with exactly one verdict. A
    silently-dropped file is the difference between "the corpus is clean" and
    "the part of the corpus I happened to look at is clean".
  * an empty read is an ERROR, never an empty script. An empty script compiles.
  * the corpus floor refuses a run over implausibly few files, so a broken
    discovery walk fails instead of passing.

WHAT A GREEN RUN DOES AND DOES NOT EARN. It earns "parses on <engine> <version>,
dated". It does NOT earn "verified", and no result from this tool may promote a
runtime entry in docs/OXT-ENGINE-NOTES.md. Of that file's 25 entries roughly
SEVEN are compile-time (1.3 constants, 1.4 smart quotes, 1.5 reserved-token
shadowing, 1.6 duplicate declarations, 1.7 `the number of keys of`, 3.3 the
zero-argument statement call, and 1.2's class if `the explicitVariables` turns
out to work). The other eighteen are runtime or GUI semantics that a compiler
cannot see. Sold honestly, this lane retires about a quarter of the expensive
knowledge - which is a great deal, and is not everything.

USAGE
  python3 tools/check-engine-lint.py                 # gate mode; skips loudly
  XT_ENGINE=/path/to/livecode-server python3 tools/check-engine-lint.py
  python3 tools/check-engine-lint.py --require       # no engine => failure
  python3 tools/check-engine-lint.py --probe         # capability probe only
  python3 tools/check-engine-lint.py --only 'coinxt/*'
  python3 tools/check-engine-lint.py --keep-temp     # leave the wrapper for reading
"""

import argparse
import fnmatch
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

PROBE_SRC = os.path.join(HERE, "engine-probe.livecodescript")
LINT_SRC = os.path.join(HERE, "engine-lint.livecodescript")

# The engine binaries this tool knows how to drive, in the order it looks for
# them on PATH. Names only - it never goes hunting through the filesystem, both
# because a wrong engine silently answering is worse than no engine and because
# an accidental match would make the lane's result depend on what else is
# installed on the machine.
ENGINE_NAMES = ("livecode-server", "lc-server", "livecode-community-server")

# Anything below this and the discovery walk is broken, not the tree. Measured
# 2026-08-28: the tree carries 49 .livecodescript files. The floor is
# deliberately well under that (files legitimately come and go) and well over
# zero (which is the number a broken glob produces).
CORPUS_FLOOR = 30

# Files the engine is EXPECTED to reject, each with the reason and the dated run
# that established it.
#
# DELIBERATELY EMPTY. It would be easy to guess which files cannot compile
# standalone - the carried masters are fragments, tools/harness-scaffold.livecode
# script is already exempt from the static gate as "a TEMPLATE WITH HOLES" - but
# guessing is how a permanent exemption gets written for a file that would in
# fact have compiled, and this tree has an explicit rule against a stale excuse
# outliving its reason. Entries land here only from a dated engine run, quoting
# what the engine actually said. Until then a fragment that fails to compile is
# a real finding and should be read as one.
EXPECTED_FAILURES = {}

MARK_LINT_BEGIN = "XTLINT-BEGIN"
MARK_LINT_END = "XTLINT-END"
MARK_PROBE_BEGIN = "XTPROBE-BEGIN"
MARK_PROBE_END = "XTPROBE-END"


class Refusal(Exception):
    """The report cannot account for itself. Distinct from a corpus failure:
    this means the measurement is void, not that the tree is dirty.

    `raw` carries whatever the engine printed, because on the first run against
    a real engine that text IS the finding - it is how the report format gets
    corrected from a guess into a record."""

    def __init__(self, message, raw=None):
        super().__init__(message)
        self.raw = raw


# --------------------------------------------------------------------------
# discovery
# --------------------------------------------------------------------------

def find_engine(explicit):
    """Return (path, how) or (None, why-not). Explicit beats environment beats
    PATH, and a path that was named explicitly and does not exist is an ERROR
    rather than a fallthrough - silently falling back to a different engine than
    the one asked for is how a lane ends up reporting on something nobody
    chose."""
    if explicit:
        if not os.path.isfile(explicit):
            raise Refusal("--engine %s does not exist" % explicit)
        return explicit, "--engine"
    env = os.environ.get("XT_ENGINE", "").strip()
    if env:
        if not os.path.isfile(env):
            raise Refusal("XT_ENGINE=%s does not exist" % env)
        return env, "XT_ENGINE"
    for name in ENGINE_NAMES:
        found = shutil.which(name)
        if found:
            return found, "PATH (%s)" % name
    return None, "no --engine, no XT_ENGINE, and none of %s on PATH" % ", ".join(ENGINE_NAMES)


def corpus(only=None):
    """Every .livecodescript in the tree, sorted, repo-relative."""
    out = []
    for base, dirs, files in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in (".git", "build", "node_modules")]
        for f in files:
            if f.endswith(".livecodescript"):
                rel = os.path.relpath(os.path.join(base, f), ROOT)
                if only and not fnmatch.fnmatch(rel, only):
                    continue
                out.append(rel)
    return sorted(out)


# --------------------------------------------------------------------------
# wrapper construction
# --------------------------------------------------------------------------

def strip_script_header(text):
    """Drop a leading `script "Name"` line.

    That line is a stack-NAME marker and is meaningful only when the file IS its
    own stack (engine notes 1.1). Inside a server wrapper it names a stack that
    is not there. The same strip is what tools/sync-demo-embeds.py does when it
    embeds a provider into a demo, and for the same reason: a second script-name
    line mid-file puts everything after it outside the enclosing declaration
    scope."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        s = line.strip()
        if not s or s.startswith("--"):
            continue
        if s.startswith("script "):
            del lines[i]
        break
    return "\n".join(lines)


# The generated wrapper's entry call is preceded by this line, and the line is
# not cosmetic. tools/test-engine-lint.py's fake engine has to find the call to
# learn where the manifest is, and its first version searched the wrapper for
# `xtLintRun("...")` - which matched the USAGE EXAMPLE in the engine-side
# script's own header comment and sent it hunting for a file called
# "/abs/path/to/manifest.txt". That is this tree's recorded comment-versus-code
# failure landing again (root CLAUDE.md: "the third time in one session that
# comment-vs-literal handling silently changed an answer"), and the fix is to
# make the real call findable by something a comment cannot accidentally be.
CALL_SENTINEL = "-- XT-ENGINE-ENTRY-CALL (generated; the line below is the real one)"


def server_wrapper(body, call):
    """Wrap an engine-side script for the server engine.

    The call goes LAST, below every handler definition, because OXT resolves
    script-level names by lexical position (engine notes 1.2) - the rule that
    cost this project an engine session when a generated fold placed 106
    declarations below the handler that read them."""
    return "<?lc\n" + body + "\n\n" + CALL_SENTINEL + "\n" + call + "\n?>\n"


def run_engine(engine, script_path, timeout):
    try:
        proc = subprocess.run([engine, script_path], cwd=ROOT, timeout=timeout,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        raise Refusal("engine %s could not be executed" % engine)
    except subprocess.TimeoutExpired:
        raise Refusal("engine timed out after %ds - a report that never "
                      "finished is not a report" % timeout)
    return (proc.returncode,
            proc.stdout.decode("utf-8", "replace"),
            proc.stderr.decode("utf-8", "replace"))


# --------------------------------------------------------------------------
# report parsing - deliberately suspicious
# --------------------------------------------------------------------------

def parse_report(out, begin_mark, end_mark):
    """Return (records, count_claimed). Refuses anything it cannot account for.

    The exit code is NOT the primary signal and is checked separately by the
    caller. Whether this engine sets one at all is an open question the probe
    answers; a gate that trusted it before that answer arrived would be
    trusting a guess."""
    lines = out.split("\n")
    begin = None
    end = None
    for i, line in enumerate(lines):
        if line.startswith(begin_mark):
            begin = i
        elif line.startswith(end_mark):
            end = i
    if begin is None:
        raise Refusal("the report has no %s marker - the engine produced no "
                      "recognisable output." % begin_mark, raw=out)
    if end is None:
        raise Refusal("the report has no %s marker - it STOPPED partway. A "
                      "truncated report reads exactly like a finished one, "
                      "which is why the marker exists." % end_mark, raw=out)
    if end < begin:
        raise Refusal("the report's end marker precedes its begin marker")

    body = lines[begin + 1:end]
    records = []
    for raw in body:
        if not raw.strip():
            continue
        parts = raw.split("\t")
        if len(parts) < 3:
            raise Refusal("unparseable record (fewer than 3 tab-separated "
                          "fields): %r" % raw[:200])
        kind, name, verdict = parts[0], parts[1], parts[2]
        detail = parts[3] if len(parts) > 3 else ""
        records.append((kind, name, verdict, detail))

    tail = lines[end].split("\t")
    if len(tail) < 2 or not tail[1].strip().isdigit():
        raise Refusal("the %s marker carries no record count: %r" % (end_mark, lines[end][:200]))
    claimed = int(tail[1].strip())
    if claimed != len(records):
        raise Refusal("the report claims %d records and carries %d - it was "
                      "truncated in a way that kept its last line" % (claimed, len(records)))
    return records, claimed


def check_controls(records):
    """The known-good must compile and the known-bad must not.

    An engine that accepts everything and an engine that checks nothing produce
    identical clean reports, and only the negative control separates them."""
    got = {}
    for kind, name, verdict, detail in records:
        if kind == "CONTROL":
            got[name] = (verdict, detail)
    for want in ("known-good", "known-bad"):
        if want not in got:
            raise Refusal("the report carries no %s control - it cannot be "
                          "trusted to have checked anything" % want)
    gv, gd = got["known-good"]
    bv, bd = got["known-bad"]
    if gv != "OK":
        raise Refusal("the KNOWN-GOOD control did not compile (%s: %s). Either "
                      "the engine is rejecting valid script or the harness is "
                      "broken; either way no verdict about the corpus is "
                      "meaningful." % (gv, gd))
    if bv == "OK":
        raise Refusal("the KNOWN-BAD control COMPILED. The engine is not "
                      "checking anything, so a clean corpus report here would "
                      "be meaningless. (The known-bad is engine note 3.3's own "
                      "defect: a zero-argument call in statement position.)")
    return gd, bd


# --------------------------------------------------------------------------
# modes
# --------------------------------------------------------------------------

def do_probe(engine, timeout, keep_temp):
    body = strip_script_header(open(PROBE_SRC).read())
    wrapper = server_wrapper(body, 'put xtProbeRun("%s")' % PROBE_SRC.replace('"', ''))
    path = os.path.join(ROOT, ".xt-engine-probe.lc")
    open(path, "w").write(wrapper)
    try:
        code, out, err = run_engine(engine, path, timeout)
    finally:
        if not keep_temp and os.path.exists(path):
            os.remove(path)

    print("== engine capability probe ==")
    print("engine     : %s" % engine)
    print("exit code  : %d" % code)
    if err.strip():
        print("stderr     :")
        for line in err.rstrip().split("\n"):
            print("    " + line)
    try:
        records, _ = parse_report(out, MARK_PROBE_BEGIN, MARK_PROBE_END)
    except Refusal as exc:
        print("\nPROBE REFUSED: %s\n" % exc)
        print("---- raw stdout ----")
        print(out)
        print("---- end raw stdout ----")
        print("\nThis is a RESULT, not a crash: it says this engine cannot run "
              "the probe in this form. Record it in docs/OXT-ENGINE-NOTES.md "
              "with the date and the engine build, and the next attempt starts "
              "from evidence rather than from the same guess.")
        return 1

    width = max(len(r[1]) for r in records) if records else 10
    for _kind, name, verdict, detail in records:
        print("  %-*s  %-6s  %s" % (width, name, verdict, detail))
    print("\n%d rows. Commit this output under docs/ as a dated record: it is "
          "the first OBSERVED evidence this project has about the headless "
          "surfaces, and every other tool in this lane reads it rather than "
          "guessing." % len(records))
    return 0


def do_lint(engine, only, timeout, keep_temp):
    files = corpus(only)
    if only is None and len(files) < CORPUS_FLOOR:
        raise Refusal("the corpus walk found %d .livecodescript files and the "
                      "floor is %d - discovery is broken, not the tree"
                      % (len(files), CORPUS_FLOOR))
    if not files:
        raise Refusal("no files matched --only %r" % only)

    manifest = os.path.join(ROOT, ".xt-engine-manifest.txt")
    with open(manifest, "w") as fh:
        for rel in files:
            fh.write(os.path.join(ROOT, rel) + "\n")

    body = strip_script_header(open(LINT_SRC).read())
    wrapper = server_wrapper(body, 'put xtLintRun("%s")' % manifest.replace('"', ''))
    path = os.path.join(ROOT, ".xt-engine-lint.lc")
    open(path, "w").write(wrapper)
    try:
        code, out, err = run_engine(engine, path, timeout)
    finally:
        if not keep_temp:
            for p in (path, manifest):
                if os.path.exists(p):
                    os.remove(p)

    records, _ = parse_report(out, MARK_LINT_BEGIN, MARK_LINT_END)
    good_detail, bad_detail = check_controls(records)

    fatal = [r for r in records if r[0] == "FATAL"]
    if fatal:
        raise Refusal("the engine reported a fatal condition: "
                      + "; ".join("%s %s: %s" % (r[1], r[2], r[3]) for r in fatal))

    seen = {}
    for kind, name, verdict, detail in records:
        if kind != "FILE":
            continue
        rel = os.path.relpath(name, ROOT)
        if rel in seen:
            raise Refusal("%s has two verdicts in one report" % rel)
        seen[rel] = (verdict, detail)

    missing = [f for f in files if f not in seen]
    if missing:
        raise Refusal("%d requested file(s) came back with no verdict, starting "
                      "with %s. A dropped file is the difference between 'the "
                      "corpus is clean' and 'the part I looked at is clean'."
                      % (len(missing), missing[0]))
    extra = [f for f in seen if f not in files]
    if extra:
        raise Refusal("the report covers %d file(s) that were not requested: %s"
                      % (len(extra), ", ".join(sorted(extra)[:5])))

    stale = [p for p in EXPECTED_FAILURES if p not in seen]
    if stale:
        raise Refusal("EXPECTED_FAILURES names %s, which the corpus no longer "
                      "contains - a renamed file must not leave a permanent "
                      "excuse behind it" % ", ".join(sorted(stale)))

    ok, failed, errored, expected = [], [], [], []
    for rel in files:
        verdict, detail = seen[rel]
        if verdict == "OK":
            if rel in EXPECTED_FAILURES:
                failed.append((rel, "compiled, but EXPECTED_FAILURES says it "
                                    "should not: " + EXPECTED_FAILURES[rel]))
            else:
                ok.append(rel)
        elif rel in EXPECTED_FAILURES:
            expected.append((rel, EXPECTED_FAILURES[rel], detail))
        elif verdict == "ERROR":
            errored.append((rel, detail))
        else:
            failed.append((rel, detail))

    print("== engine lint ==")
    print("engine        : %s" % engine)
    print("exit code     : %d" % code)
    print("controls      : known-good OK, known-bad rejected (%s)"
          % (bad_detail[:90] or "no detail"))
    print("files compiled: %d of %d" % (len(ok), len(files)))
    if expected:
        print("expected fail : %d" % len(expected))
        for rel, why, detail in expected:
            print("    %s\n        reason: %s\n        engine: %s" % (rel, why, detail[:200]))
    if err.strip():
        print("stderr        :")
        for line in err.rstrip().split("\n")[:40]:
            print("    " + line)

    if errored:
        print("\nERRORED (the harness could not ask, which is not the same as "
              "a syntax error):")
        for rel, detail in errored:
            print("  %s\n      %s" % (rel, detail[:300]))
    if failed:
        print("\nREJECTED BY THE ENGINE:")
        for rel, detail in failed:
            print("  %s\n      %s" % (rel, detail[:300]))

    if failed or errored:
        print("\n%d rejected, %d errored." % (len(failed), len(errored)))
        return 1
    print("\nMEASURED: every one of the %d scripts parses on this engine. That "
          "is a PARSE result and nothing more - the runtime entries in "
          "docs/OXT-ENGINE-NOTES.md are untouched by it." % len(files))
    return 0


def skip_notice(why, require):
    banner = "check-engine-lint: %s" % ("REQUIRED BUT UNAVAILABLE" if require else "SKIPPED")
    print(banner)
    print("  reason: %s" % why)
    print("")
    print("  This is the only gate in the tree that runs a REAL compiler over")
    print("  the script corpus, and it is INERT until an engine is pointed at")
    print("  it. Everything else in tools/ approximates the parse; this runs it.")
    print("")
    print("      XT_ENGINE=/path/to/livecode-server python3 tools/check-engine-lint.py")
    print("      python3 tools/check-engine-lint.py --engine /path/to/livecode-server --probe")
    print("")
    print("  Run --probe FIRST. It asks the engine what it can actually do and")
    print("  prints the answers; every claim this lane rests on is DOCUMENTED")
    print("  until that report exists. See docs/HEADLESS-ENGINE.md.")
    return 2 if require else 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--engine", help="path to a headless engine binary")
    ap.add_argument("--probe", action="store_true",
                    help="run the capability probe instead of the lint")
    ap.add_argument("--require", action="store_true",
                    help="treat a missing engine as a failure (the CI engine lane)")
    ap.add_argument("--only", help="repo-relative glob to narrow the corpus")
    ap.add_argument("--timeout", type=int, default=900,
                    help="seconds before the engine run is refused (default 900)")
    ap.add_argument("--keep-temp", action="store_true",
                    help="leave the generated wrapper and manifest in place")
    args = ap.parse_args()

    try:
        engine, how = find_engine(args.engine)
    except Refusal as exc:
        print("check-engine-lint: REFUSED - %s" % exc)
        return 2
    if engine is None:
        return skip_notice(how, args.require)

    print("check-engine-lint: engine from %s -> %s" % (how, engine))
    try:
        if args.probe:
            return do_probe(engine, args.timeout, args.keep_temp)
        return do_lint(engine, args.only, args.timeout, args.keep_temp)
    except Refusal as exc:
        print("\ncheck-engine-lint: REPORT REFUSED")
        print("  %s" % exc)
        if getattr(exc, "raw", None) is not None:
            print("\n---- raw engine output ----")
            print(exc.raw if exc.raw.strip() else "(the engine printed nothing at all)")
            print("---- end raw engine output ----")
        print("\n  Refused, not failed: the measurement is void, so this run says")
        print("  NOTHING about whether the corpus is clean. Fix the measurement")
        print("  first - a lane that reports on a corpus it did not read is the")
        print("  failure mode this repository has documented four times.")
        return 2


if __name__ == "__main__":
    sys.exit(main())
