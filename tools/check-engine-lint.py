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


def status(kind):
    """The last line of every run, on every path.

    CI asserted on prose before this existed, and prose is exactly what changes
    when someone improves a message. One machine-readable line means the
    workflow can assert MEASURED without pattern-matching an explanation."""
    print("XT-ENGINE-STATUS: %s" % kind)


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
    except subprocess.TimeoutExpired as exc:
        # Whatever the engine managed to print before it hung IS the finding -
        # it names the probe that did not return. The first version discarded
        # it, which made a hang the one failure mode that taught nothing.
        partial = b""
        for chunk in (exc.output, exc.stderr):
            if chunk:
                partial += chunk if isinstance(chunk, bytes) else chunk.encode()
        raise Refusal("engine timed out after %ds - a report that never "
                      "finished is not a report" % timeout,
                      raw=partial.decode("utf-8", "replace"))
    return (proc.returncode,
            proc.stdout.decode("utf-8", "replace"),
            proc.stderr.decode("utf-8", "replace"))


# --------------------------------------------------------------------------
# report parsing - deliberately suspicious
# --------------------------------------------------------------------------

def classify_engine(engine):
    """Ask an unrecognised binary what it is.

    The driver generates a SERVER-shaped wrapper (`<?lc ... ?>`). Handed a
    standalone or desktop engine instead, it would produce something that binary
    cannot read, and the resulting "no marker" refusal would be read as
    headless-does-not-work rather than as wrong-engine-kind. This runs the binary
    bare and with --help and returns the transcript, so the refusal carries the
    evidence that tells the two apart."""
    out = []
    for args in ([], ["--help"]):
        try:
            proc = subprocess.run([engine] + args, timeout=20,
                                  stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            text = proc.stdout.decode("utf-8", "replace").strip()
        except Exception as exc:                    # noqa: BLE001 - reporting only
            text = "(could not run: %s)" % exc
        out.append("$ %s %s\n%s" % (os.path.basename(engine), " ".join(args),
                                    text[:1500] or "(no output)"))
    return "\n\n".join(out)


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

    # A report that can carry two answers to one question cannot be parsed
    # safely, whichever answer a parser happens to keep. Across every record
    # kind, not just FILE: the control pairs are where a duplicate would be most
    # dangerous, because one name with two verdicts hides a degradation.
    seen_keys = set()
    for kind, name, _v, _d in records:
        if (kind, name) in seen_keys:
            raise Refusal("the report carries two %s records named %r - a report "
                          "with two answers to one question cannot be trusted "
                          "for either" % (kind, name))
        seen_keys.add((kind, name))

    tail = lines[end].split("\t")
    if len(tail) < 2 or not tail[1].strip().isdigit():
        raise Refusal("the %s marker carries no record count: %r" % (end_mark, lines[end][:200]))
    claimed = int(tail[1].strip())
    if claimed != len(records):
        raise Refusal("the report claims %d records and carries %d - it was "
                      "truncated in a way that kept its last line" % (claimed, len(records)))
    return records, claimed


def check_controls(records):
    """All four small controls plus the scale control must be present and behave.

    An engine that accepts everything and an engine that checks nothing produce
    identical clean reports, and only the negative control separates them. The
    pair is emitted twice - before the corpus and after it - because a single
    pre-corpus pair cannot see an engine that DEGRADES partway through; and the
    scale control exists because two sixty-byte strings say nothing about an
    engine's behaviour at the 1.95 MB this corpus actually reaches."""
    got = {}
    for kind, name, verdict, detail in records:
        if kind == "CONTROL":
            got[name] = (verdict, detail)

    required = ("known-good-pre", "known-bad-pre",
                "known-good-post", "known-bad-post", "known-bad-large")
    missing = [w for w in required if w not in got]
    if missing:
        raise Refusal("the report is missing control(s) %s - it cannot be "
                      "trusted to have checked anything. (pre and post exist so "
                      "a partway degradation is visible; the large one because "
                      "sixty-byte controls say nothing about an engine at corpus "
                      "scale.)" % ", ".join(missing))

    for name in ("known-good-pre", "known-good-post"):
        verdict, detail = got[name]
        if verdict != "OK":
            raise Refusal("the %s control did not compile (%s: %s). Either the "
                          "engine is rejecting valid script or the harness is "
                          "broken; either way no verdict about the corpus is "
                          "meaningful." % (name, verdict, detail))
    for name in ("known-bad-pre", "known-bad-post", "known-bad-large"):
        verdict, detail = got[name]
        if verdict == "OK":
            extra = ""
            if name == "known-bad-post":
                extra = (" It was rejected BEFORE the corpus and accepted after, "
                         "so the engine stopped checking partway through this "
                         "run - every clean verdict after that point is void.")
            if name == "known-bad-large":
                extra = (" The same defect is caught in a 60-byte script and "
                         "missed in a 20,000-line one, so this engine's checking "
                         "is size-dependent and the corpus's large files were not "
                         "really checked.")
            raise Refusal("the %s control COMPILED.%s (The defect is engine note "
                          "3.3's own: a zero-argument call in statement "
                          "position.)" % (name, extra))
    return got["known-bad-pre"][1]


def check_no_cascade(seen):
    """Refuse a report whose failures look like ONE error copied down the run.

    If a successful `set the script of` leaves `the result` UNCHANGED, one real
    compile failure becomes every later file's verdict, and the run reports a
    corpus full of defects that reads like a catastrophe rather than like a
    broken measurement. The engine-side script clears the result before each
    compile; this is the backstop for when the clear did not work.

    IT IS DELIBERATELY NOT "ANY TWO FILES AGREE", because in THIS tree two files
    agreeing is ordinary. Four blocks are carried byte-identically into a dozen
    files each - the ui-kit, the harness scaffold, the demo self-check, and the
    embedded libraries - so one defect in a master legitimately produces the
    same error text in sixteen demos. That is a real finding, not a cascade, and
    a gate that refused it would be crying wolf on the tree's own architecture.

    So the signature is narrower: three or more files sharing one text AND that
    group being most of the failures. A carried-block defect leaves the files
    that do not carry the block reporting something else; a stale `the result`
    makes everything downstream identical."""
    buckets = {}
    failures = 0
    for rel, (verdict, detail) in seen.items():
        if verdict == "OK":
            continue
        failures += 1
        body = detail.split("; ", 1)[1].strip() if "; " in detail else detail.strip()
        if not body:
            continue
        buckets.setdefault(body, []).append(rel)
    for body, files in buckets.items():
        if len(files) >= 3 and len(files) * 2 > failures:
            raise Refusal(
                "%d of %d failing files came back with BYTE-IDENTICAL text, "
                "which is the signature of one error copied down the run - a "
                "stale `the result` read as each file's verdict - rather than a "
                "corpus fact.\n  Files: %s\n  Text: %r\n"
                "  IF THIS IS REAL: a defect in one carried block (the ui-kit, "
                "the scaffold, the self-check, an embedded library) does produce "
                "identical text in every carrier. Tell them apart by re-running "
                "one file alone:\n"
                "      python3 tools/check-engine-lint.py --only '%s'\n"
                "  A cascade clears when the file is compiled first; a real "
                "defect does not."
                % (len(files), failures, ", ".join(sorted(files)[:4]), body[:200],
                   sorted(files)[0]))


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
        print(out if out.strip() else "(the engine printed nothing at all)")
        print("---- end raw stdout ----")
        print("\n---- what this binary says it is ----")
        print(classify_engine(engine))
        print("---- end ----")
        print("\nThis is a RESULT, not a crash: it says this engine cannot run "
              "the probe in this form. The transcript above is the evidence for "
              "WHICH failure it is - a server engine that could not parse the "
              "wrapper, or a binary that is not a server engine at all. Record "
              "it in docs/OXT-ENGINE-NOTES.md with the date and the build.")
        status("REFUSED")
        return 1

    by_name = {r[1]: (r[2], r[3]) for r in records}
    width = max(len(r[1]) for r in records) if records else 10
    for _kind, name, verdict, detail in records:
        print("  %-*s  %-6s  %s" % (width, name, verdict, detail))

    # THE PROBE HAS TO BE ABLE TO FAIL.
    #
    # The first version of this printed the rows and exited 0 whatever they
    # said, so a report in which every capability came back NO - or every row
    # came back ERROR - read as a successful probe worth committing. That is the
    # tree's own documented failure shape (a gate answering the question nobody
    # asks twice) landing in the one tool whose entire job is producing evidence.
    #
    # The mandatory rows below are not capabilities. They must be YES on any
    # engine that EXECUTED the probe at all, so they separate "this engine
    # cannot do these things" from "nothing ran".
    problems = []
    for name in ("probe.selfArithmetic", "probe.emitRoundTrip"):
        verdict = by_name.get(name, ("MISSING", ""))[0]
        if verdict not in ("YES", "OK"):
            problems.append("mandatory row %s is %s - this report is not "
                            "evidence that anything executed" % (name, verdict))
    if by_name.get("engine.environment", ("MISSING", ""))[0] == "MISSING" and \
       by_name.get("engine.version", ("MISSING", ""))[0] == "MISSING":
        problems.append("neither engine.environment nor engine.version is "
                        "present, so this report cannot be pinned to a build "
                        "and may not be cited as evidence about one")
    # The mandatory rows are NOT capabilities and are counted separately. Summed
    # in, they put a floor of two YES under every report, so a probe in which
    # the engine could do nothing at all would still print a non-zero
    # capability count - a small number that reads like a small success.
    caps = [r for r in records if not r[1].startswith("probe.")
            and r[2] in ("YES", "NO", "ERROR", "UNAVAILABLE")]
    yes = sum(1 for r in caps if r[2] == "YES")
    no = sum(1 for r in caps if r[2] == "NO")
    err = sum(1 for r in records if r[2] in ("ERROR", "UNAVAILABLE"))
    print("\n  capabilities: %d YES, %d NO (of %d asked); %d ERROR/UNAVAILABLE "
          "row(s) overall; %d rows total"
          % (yes, no, len(caps), err, len(records)))

    # An engine can legitimately answer NO to everything. It cannot legitimately
    # ERROR on everything: that is the probe failing to ask, not the engine
    # failing to do, and the two must not be summed into one green report.
    if records and err * 2 > len(records):
        problems.append("%d of %d rows are ERROR/UNAVAILABLE - the probe is "
                        "failing to ASK, which is not the same as the engine "
                        "failing to DO, and a report that is mostly the former "
                        "measures nothing" % (err, len(records)))

    # DELIBERATELY NOT A REFUSAL, and the distinction is worth stating.
    #
    # In the LINT, a known-bad that compiles voids the report: every clean
    # verdict after it is meaningless. In the PROBE, the same row is THE FINDING
    # - it is the answer to "can this engine lint at all?", and answering "no"
    # is a successful measurement. Refusing here would make the probe unable to
    # report the one negative result that most needs recording. So it prints as
    # a verdict, loudly, and exits 0.
    bad = by_name.get("compile.badIsReported", ("MISSING", ""))
    if bad[0] == "YES":
        print("  VERDICT: `set the script of` reports a bad script on this "
              "engine, so HEADLESS-ENGINE.md stage 2 (the script lint) IS "
              "authorised.")
    else:
        print("  VERDICT: compile.badIsReported is %s - this engine did NOT "
              "report a zero-argument call in statement position, so "
              "`set the script of` is not a lint on it and stage 2 is NOT "
              "authorised. That is a real result; record it. Check the "
              "compile.errorFormat row for what it said instead, and note the "
              "open question in HEADLESS-ENGINE.md section 9: the engine may be "
              "STORING the script and deferring the parse to first execution, "
              "in which case the idiom must be set-then-call." % bad[0])

    if problems:
        print("\nPROBE REFUSED - the report cannot be cited as evidence:")
        for prob in problems:
            print("  - %s" % prob)
        status("REFUSED")
        return 1

    print("\nCommit this output under docs/ as a dated record: it is the first "
          "OBSERVED evidence this project has about the headless surfaces, and "
          "every other tool in this lane reads it rather than guessing.")
    status("MEASURED")
    return 0


def git_corpus():
    """`git ls-files` as an INDEPENDENT list.

    The os.walk in corpus() has a prune list, and a prune bug that silently drops
    four members leaves the count plausible and the run green - a shrunken
    denominator, which is the failure this tree has already paid for once (an
    unterminated comment took 69 handlers out of a coverage count and turned the
    row green at a smaller wrong number). git's index cannot be broken by the
    same bug, so disagreement between the two is a refusal."""
    try:
        proc = subprocess.run(["git", "ls-files", "*.livecodescript"], cwd=ROOT,
                              timeout=60, stdout=subprocess.PIPE,
                              stderr=subprocess.DEVNULL)
    except Exception:                               # noqa: BLE001 - optional check
        return None
    if proc.returncode != 0:
        return None
    return sorted(l for l in proc.stdout.decode().split("\n") if l.strip())


def do_lint(engine, only, timeout, keep_temp):
    files = corpus(only)
    if only is None:
        tracked = git_corpus()
        if tracked is not None:
            # Untracked files are legitimate mid-change, so only a walk that has
            # LOST something git can see is a refusal.
            lost = [f for f in tracked if f not in files]
            if lost:
                raise Refusal("`git ls-files` names %d .livecodescript file(s) "
                              "the corpus walk did not find, starting with %s - "
                              "the walk is broken, and a shrunken denominator "
                              "reports green at a smaller wrong number"
                              % (len(lost), lost[0]))
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
    bad_detail = check_controls(records)

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

    check_no_cascade(seen)

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
    # Printed because degradation should show as a NUMBER, not as an absence: an
    # engine that quietly stops reading past some size leaves every count right
    # and this total wrong.
    total = 0
    for rel in files:
        detail = seen[rel][1]
        if detail.startswith("chars="):
            head = detail.split(";", 1)[0][len("chars="):].strip()
            if head.isdigit():
                total += int(head)
    print("bytes compiled: %d (as reported by the engine, summed over %d files)"
          % (total, len(files)))
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
        status("MEASURED")
        return 1
    print("\nMEASURED: every one of the %d scripts parses on this engine. That "
          "is a PARSE result and nothing more - the runtime entries in "
          "docs/OXT-ENGINE-NOTES.md are untouched by it." % len(files))
    status("MEASURED")
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
    status("REQUIRED-BUT-UNAVAILABLE" if require else "SKIPPED")
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
        status("REFUSED")
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
        status("REFUSED")
        return 2


if __name__ == "__main__":
    sys.exit(main())
