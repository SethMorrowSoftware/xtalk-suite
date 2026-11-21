#!/usr/bin/env python3
"""test-release-plan.py - a named release build runs the named members' lanes
and nothing else, and a full one runs exactly what it ran before.

release-binaries.yml's `build: named` (2026-11-21) is held here in three
parts, each read from the files as they are:

  1. THE READER. tools/release-plan.py reads the rows of the workflow's
     `include:` lists for the plan job. Fixtures first: rows it must read to
     exact values (plain text with quotes in it, a quoted value with a
     comment after it, an integer), and every shape it must REFUSE rather
     than guess at (a flow collection, a block scalar, an anchor, an alias,
     a tag, an expression, a value spanning lines, a duplicate key, a word
     YAML reads as a boolean, null or a number). Then the real workflow's
     rows, held to PyYAML's reading of the same file where PyYAML is
     installed (it is not in the suite-gates job; the strict shape is what
     holds there, and this prints a NOTE saying so).

  2. THE PLAN. The members input read the way the commit job reads it, the
     refusals (no names, `all`, a name no lane builds, a tab), and for every
     member with lanes: its plan is its rows, in the workflow's order, and
     no other member's. A row added in place for a new member (what each
     member's pull request does) is planned with no change to the tool.

  3. THE WIRING. Every job's `needs` and `if`, read from the workflow and
     evaluated the way Actions does (GitHub's loose comparisons, `&&` and
     `||` returning an operand, and the success() it prepends to a
     condition with no status function) for every combination of the
     dispatch inputs, and of jobs failing:
       - a full run (`build` all or absent) runs, and commits, exactly as
         the conditions before 2026-11-21 did (kept below as OLD, the
         spec), for every combination of failures;
       - a named run runs the plan, the named members' twins, coinxt only
         when named, Android only for an Android member, and never the
         full jobs;
       - the commit job runs only when nothing that ran failed, and never
         after a refused plan;
       - no condition names a job its `needs` leaves out, and a twin whose
         matrix the plan left empty never runs (Actions refuses an empty
         matrix).
     And the shape: each twin's steps are an alias of its original's
     anchor, its name, runner, container and defaults are the original's,
     its matrix is the plan output of the same name, and the Android job's
     loops read the one chosen list.

A fixture first proves the evaluator models the implicit success(): the
commit condition of run 37413026408 (no `!cancelled()`) is skipped when
mac_lipo=false, as that run was. Logic only, like every workflow test here:
it runs no workflow, and upgrades no label.

USAGE
    python3 tools/test-release-plan.py
"""

import contextlib
import functools
import importlib.util
import io
import itertools
import json
import math
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "release-binaries.yml")
TAG = "test-release-plan"
FAILURES = []
# Where check() reports: FAILURES, or (part 4) a mutant's run, which stops at
# the first thing it catches.
SINK = [FAILURES]


class Caught(Exception):
    pass


def load(name, filename):
    spec = importlib.util.spec_from_file_location(name, os.path.join(HERE, filename))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


RP = load("release_plan", "release-plan.py")


def check(ok, label, detail=""):
    if not ok:
        if len(SINK) > 1:
            raise Caught(label)
        FAILURES.append("%s\n        got: %s" % (label, detail))
        print("  FAIL  " + label)
    return ok


# --------------------------------------------------------------- 1. reader

def rows_of(body):
    """Read a one-job workflow whose include list is `body`."""
    text = ("name: t\njobs:\n  j:\n    strategy:\n      matrix:\n        include:\n"
            + body + "    runs-on: x\n")
    return RP.read_rows(text, "j")[0]


GOOD = [
    ("plain values, comments and blank lines between rows",
     "          # a comment\n"
     "          - member: aaxt\n"
     "            platform_id: x86_64-linux\n"
     "\n"
     "            # a comment inside a row\n"
     "            cmake_args: -DCMAKE_OSX_ARCHITECTURES=\"arm64;x86_64\" -A Win32\n"
     "          - member: bbxt\n"
     "            manylinux: \"1\"    # quoted, then a comment\n"
     "            build_jobs: 2          # an integer, then a comment\n"
     "            apt_i386: libssl-dev:i386 zlib1g-dev:i386\n"
     "            single: 'it''s'\n",
     [{"member": "aaxt", "platform_id": "x86_64-linux",
       "cmake_args": '-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64" -A Win32'},
      {"member": "bbxt", "manylinux": "1", "build_jobs": 2,
       "apt_i386": "libssl-dev:i386 zlib1g-dev:i386", "single": "it's"}]),
    ("a value ending in a comment loses the comment, as YAML's does",
     "          - member: ccxt\n"
     "            os: ubuntu-24.04 # trailing\n",
     [{"member": "ccxt", "os": "ubuntu-24.04"}]),
]

BAD = [
    ("a flow sequence", "          - member: aaxt\n            apt: [a, b]\n"),
    ("a flow mapping", "          - member: aaxt\n            x: {a: 1}\n"),
    ("a block scalar", "          - member: aaxt\n            x: |\n              text\n"),
    ("an anchor", "          - member: aaxt\n            x: &a text\n"),
    ("an alias", "          - member: aaxt\n            x: *a\n"),
    ("a tag", "          - member: aaxt\n            x: !!str 1\n"),
    ("an expression", "          - member: aaxt\n            x: ${{ matrix.os }}\n"),
    ("a quoted expression", "          - member: aaxt\n            x: \"${{ env.X }}\"\n"),
    ("a value spanning lines", "          - member: aaxt\n            x: one\n              two\n"),
    ("a nested mapping", "          - member: aaxt\n            x:\n              y: 1\n"),
    ("an empty value", "          - member: aaxt\n            x:\n"),
    ("a duplicate key", "          - member: aaxt\n            x: 1\n            x: 2\n"),
    ("a dash alone on its line", "          -\n            member: aaxt\n"),
    ("a row out of line", "          - member: aaxt\n            - member: bbxt\n"),
    ("a key out of line", "          - member: aaxt\n              x: 1\n"),
    ("a ': ' in a plain value", "          - member: aaxt\n            x: a: b\n"),
    ("yes (a boolean to YAML 1.1)", "          - member: aaxt\n            x: yes\n"),
    ("on (a boolean to YAML 1.1)", "          - member: aaxt\n            x: on\n"),
    ("true", "          - member: aaxt\n            x: true\n"),
    ("null", "          - member: aaxt\n            x: null\n"),
    ("~", "          - member: aaxt\n            x: ~\n"),
    ("a float (3.12 is not 3.12 text)", "          - member: aaxt\n            x: 3.12\n"),
    ("a leading-zero integer (octal to YAML 1.1)", "          - member: aaxt\n            x: 0755\n"),
    ("hex", "          - member: aaxt\n            x: 0x1F\n"),
    ("base 60", "          - member: aaxt\n            x: 1:30\n"),
    ("an unterminated quote", "          - member: aaxt\n            x: \"open\n"),
    ("an unknown escape", "          - member: aaxt\n            x: \"\\q\"\n"),
    ("text after a quoted value", "          - member: aaxt\n            x: \"a\" b\n"),
    ("a tab in a value", "          - member: aaxt\n            x: a\tb\n"),
    ("a line before the first row", "            x: 1\n          - member: aaxt\n"),
]


def test_reader():
    print("1. the reader")
    for label, body, want in GOOD:
        try:
            got = rows_of(body)
        except RP.ReadError as e:
            got = "refused: %s" % e
        check(got == want and all(type(got[i][k]) is type(want[i][k])
                                  for i in range(len(want)) for k in want[i]),
              "reads " + label, got)
    for label, body in BAD:
        try:
            got = rows_of(body)
            check(False, "refuses " + label, got)
        except RP.ReadError as e:
            check(re.search(r":\d+: ", str(e)) is not None,
                  "refuses %s, naming the line" % label, str(e))
    text = ("name: t\njobs:\n  j:\n    strategy:\n      matrix:\n"
            "        include: ${{ fromJSON(needs.plan.outputs.cmake) }}\n")
    check(RP.read_rows(text, "j") is None, "an include that is an expression is "
          "not a list of rows (a twin's)")
    check(RP.read_rows(text, "nojob") is None, "a job that is not there has no rows")

    with open(WORKFLOW, encoding="utf-8") as fh:
        text = fh.read()
    rows = RP.lanes(text)
    installer = load("irb", "install-release-binaries.py")
    for job, got in rows.items():
        members = sorted({r["member"] for r in got})
        check(set(members) <= set(installer.MEMBERS),
              "every %s row builds a member the installer installs" % job,
              (members, sorted(installer.MEMBERS)))
    try:
        import yaml
    except ImportError:
        yaml = None
        print("  NOTE  PyYAML is not installed here: the real rows are held by the "
              "reader's strict shape alone (the comparison runs where it is)")
    if yaml is not None:
        doc = yaml.safe_load(text)
        for job in ("cmake-members", "mac-lipo", "coinxt", "android"):
            mine = RP.read_rows(text, job)[0]
            theirs = doc["jobs"][job]["strategy"]["matrix"]["include"]
            same = mine == theirs and all(type(a[k]) is type(b[k])
                                          for a, b in zip(mine, theirs) for k in a)
            check(same, "the %s rows read as PyYAML reads them (%d rows)"
                  % (job, len(mine)), (mine, theirs))
        jobs = doc["jobs"]
        for job, spec in RP.MATRIX_JOBS.items():
            check(jobs[spec["twin"]]["steps"] == jobs[job]["steps"],
                  "%s's steps resolve, through the alias, to %s's" % (spec["twin"], job))
    return text, rows


# ----------------------------------------------------------------- 2. plan

def test_plan(text, rows):
    print("2. the plan")
    android = RP.android_members()
    done = subprocess.run(["bash", os.path.join(HERE, "build-android.sh"), "--list"],
                          capture_output=True, text=True)
    listed = [l.split(":", 1)[1].split() for l in done.stdout.splitlines()
              if l.startswith("members:")]
    check(listed and android == listed[0], "the Android members are build-android.sh "
          "--list's `members:` line, the list the Android job's loops read",
          (android, listed))
    for words, want in (("curlxt", ["curlxt"]), ("  curlxt   coinxt ", ["curlxt", "coinxt"]),
                        ("enetxt enetxt", ["enetxt"])):
        check(RP.parse_members(words) == want, "members %r reads as %r" % (words, want),
              RP.parse_members(words))
    for words, why in (("", "no names"), ("all", "all"), ("   ", "only spaces"),
                       ("curlxt all", "all among names"), ("curlxt\tcoinxt", "a tab"),
                       ("curlxt\ncoinxt", "a line break"), ("CurlXT", "capitals"),
                       ("curlxt,coinxt", "a comma")):
        try:
            RP.parse_members(words)
            check(False, "members %r is refused (%s)" % (words, why))
        except RP.PlanError:
            pass

    have = set(android) | {"coinxt"} | {r["member"] for j in rows for r in rows[j]}
    for member in sorted(have):
        p = RP.plan(rows, android, [member])
        for job, spec in RP.MATRIX_JOBS.items():
            want = [r for r in rows[job] if r["member"] == member]
            check(p[spec["output"]] == want, "%s: its %s rows, in the workflow's order, "
                  "and no other member's" % (member, job), p[spec["output"]])
        check(p["coinxt"] == (member == "coinxt"), "%s: coinxt's job only if it is coinxt"
              % member, p["coinxt"])
        check(p["android"] == ([member] if member in android else []),
              "%s: the Android job builds it alone" % member, p["android"])
    p = RP.plan(rows, android, ["torrentxt", "coinxt"])
    check(p["android"] == [m for m in android if m in ("torrentxt", "coinxt")],
          "two members: the Android list keeps build-android.sh's order", p["android"])
    for names in (["curlx"], ["onionxt"], ["curlxt", "nosuchxt"]):
        try:
            RP.plan(rows, android, names)
            check(False, "a name no lane builds is refused: %s" % names)
        except RP.PlanError as e:
            check("no release lane builds" in str(e), "a name no lane builds is refused, "
                  "and named: %s" % names, str(e))

    # A member's pull request adds its rows in place; the plan finds them.
    anchor = "          - member: curlxt\n            platform_id: x86_64-linux\n"
    check(anchor in text, "the fixture's insertion point (curlxt's first row) exists")
    grown = text.replace(anchor, "          - member: zzzxt\n            platform_id: "
                         "x86_64-linux\n            os: ubuntu-24.04\n" + anchor, 1)
    p = RP.plan(RP.lanes(grown), android, ["zzzxt"])
    check([r["member"] for r in p["cmake"]] == ["zzzxt"] and not p["maclipo"]
          and not p["coinxt"] and not p["android"],
          "a member whose rows were added in place is planned with no change to the tool",
          p)

    # The step's outputs: one line each, JSON on one line.
    def quietly(argv):
        """RP.main(argv), with what it prints kept: (status, stdout, stderr)."""
        o, e = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(o), contextlib.redirect_stderr(e):
            rc = RP.main(argv)
        return rc, o.getvalue(), e.getvalue()

    with tempfile.TemporaryDirectory(prefix=TAG + "-") as tmp:
        out, summ = os.path.join(tmp, "out"), os.path.join(tmp, "summary")
        rc, said, _ = quietly(["--members", "curlxt coinxt", "--github-output", out,
                               "--summary", summ])
        check("A named build: curlxt coinxt" in said, "the plan prints its table to "
              "the step's log too", said)
        with open(out, encoding="utf-8") as fh:
            got = dict(l.split("=", 1) for l in fh.read().splitlines())
        check(rc == 0 and set(got) == {"cmake", "maclipo", "coinxt", "android", "members"},
              "--github-output writes the plan's five outputs", (rc, got))
        check(json.loads(got.get("cmake", "null")) == [r for r in rows["cmake-members"]
                                                       if r["member"] == "curlxt"]
              and json.loads(got.get("maclipo", "null")) == [r for r in rows["mac-lipo"]
                                                             if r["member"] == "curlxt"]
              and got.get("coinxt") == "true" and got.get("members") == "curlxt coinxt",
              "  ...which carry the rows, the coinxt flag and the names", got)
        with open(summ, encoding="utf-8") as fh:
            check("A named build: curlxt coinxt" in fh.read(), "--summary writes the "
                  "table of what runs")
        open(out, "w").close()
        rc, said, err = quietly(["--members", "all", "--github-output", out])
        check(rc == 1 and os.path.getsize(out) == 0,
              "a refused plan exits 1 and writes no output", rc)
        check(said.startswith("::error::") and "REFUSED" in err,
              "  ...and says why, as an annotation on the run", (said, err))
        rc, _, err = quietly([])
        check(rc == 2 and "give --members or --rows" in err, "no question is a usage "
              "error, not a plan", (rc, err))


# --------------------------------------------------------------- 3. wiring

TOKEN = re.compile(r"\s*(?:(\|\||&&|==|!=|<=|>=|<|>|!|\(|\)|,)|'((?:[^']|'')*)'"
                   r"|(\d+(?:\.\d+)?)|([A-Za-z_][A-Za-z0-9_.-]*))")
STATUS = ("success", "failure", "cancelled", "always")


def parse(expr):
    """An Actions expression, as a tree: the forms these conditions use."""
    toks, pos = [], 0
    while expr[pos:].strip():
        m = TOKEN.match(expr, pos)
        if not m or m.end() == pos:
            raise ValueError("cannot read %r" % expr[pos:])
        op, lit, num, name = m.groups()
        if op:
            toks.append(("op", op))
        elif lit is not None:
            toks.append(("lit", lit.replace("''", "'")))
        elif num:
            toks.append(("lit", float(num)))
        else:
            toks.append(("name", name))
        pos = m.end()
    i = 0

    def peek():
        return toks[i] if i < len(toks) else (None, None)

    def take(want=None):
        nonlocal i
        tok = peek()
        if want is not None and tok != want:
            raise ValueError("expected %r at %r in %r" % (want, tok, expr))
        i += 1
        return tok

    def primary():
        kind, val = take()
        if (kind, val) == ("op", "("):
            node = orx()
            take(("op", ")"))
            return node
        if kind == "lit":
            return ("lit", val)
        if kind == "name":
            if val in ("true", "false"):
                return ("lit", val == "true")
            if val == "null":
                return ("lit", None)
            if peek() == ("op", "("):
                take()
                args = []
                while peek() != ("op", ")"):
                    args.append(orx())
                    if peek() == ("op", ","):
                        take()
                take(("op", ")"))
                return ("call", val, args)
            return ("ref", val)
        raise ValueError("unexpected %r in %r" % (val, expr))

    def unary():
        if peek() == ("op", "!"):
            take()
            return ("not", unary())
        node = primary()
        if peek()[0] == "op" and peek()[1] in ("==", "!=", "<", ">", "<=", ">="):
            op = take()[1]
            node = ("cmp", op, node, primary())
        return node

    def andx():
        node = unary()
        while peek() == ("op", "&&"):
            take()
            node = ("and", node, unary())
        return node

    def orx():
        node = andx()
        while peek() == ("op", "||"):
            take()
            node = ("or", node, andx())
        return node

    tree = orx()
    if i != len(toks):
        raise ValueError("trailing tokens in %r" % expr)
    return tree


def calls(tree):
    if tree[0] == "call":
        yield tree[1]
        for a in tree[2]:
            yield from calls(a)
    elif tree[0] in ("and", "or"):
        yield from calls(tree[1])
        yield from calls(tree[2])
    elif tree[0] == "not":
        yield from calls(tree[1])
    elif tree[0] == "cmp":
        yield from calls(tree[2])
        yield from calls(tree[3])


@functools.lru_cache(maxsize=None)
def condition(expr):
    """A job's `if` as Actions runs it: success() && it, unless it calls a
    status function itself; success() alone when there is none. Cached: the
    job graph is run thousands of times over the same few conditions."""
    if expr is None:
        return ("call", "success", [])
    expr = expr.strip()
    if expr.startswith("${{") and expr.endswith("}}"):
        expr = expr[3:-2]
    tree = parse(expr)
    if not set(calls(tree)) & set(STATUS):
        tree = ("and", ("call", "success", []), tree)
    return tree


def truthy(v):
    if isinstance(v, float) and math.isnan(v):
        return False
    return v not in (False, 0, "", None)


def number(v):
    if v is None:
        return 0.0
    if isinstance(v, bool):
        return 1.0 if v else 0.0
    if isinstance(v, (int, float)):
        return float(v)
    try:
        return float(json.loads(v)) if v.strip() else 0.0
    except (ValueError, TypeError):
        return float("nan")


def equal(a, b):
    """Actions' loose ==: strings ignore case; mismatched types compare as numbers."""
    if isinstance(a, str) and isinstance(b, str):
        return a.lower() == b.lower()
    if type(a) is type(b) and not isinstance(a, float):
        return a == b
    x, y = number(a), number(b)
    return not (math.isnan(x) or math.isnan(y)) and x == y


def evaluate(tree, ctx, needs, scope):
    """`needs` is what the needs context holds (the direct needs); `scope`
    is what a status function reads: the needs, or every ancestor."""
    kind = tree[0]
    if kind == "lit":
        return tree[1]
    if kind == "or":
        left = evaluate(tree[1], ctx, needs, scope)
        return left if truthy(left) else evaluate(tree[2], ctx, needs, scope)
    if kind == "and":
        left = evaluate(tree[1], ctx, needs, scope)
        return evaluate(tree[2], ctx, needs, scope) if truthy(left) else left
    if kind == "not":
        return not truthy(evaluate(tree[1], ctx, needs, scope))
    if kind == "cmp":
        a = evaluate(tree[2], ctx, needs, scope)
        b = evaluate(tree[3], ctx, needs, scope)
        if tree[1] == "==":
            return equal(a, b)
        if tree[1] == "!=":
            return not equal(a, b)
        raise ValueError("ordering comparisons are not modelled")
    if kind == "call":
        results = [ctx["needs"][n]["result"] for n in scope]
        if tree[1] == "success":
            return all(r == "success" for r in results)
        if tree[1] == "failure":
            return any(r == "failure" for r in results)
        if tree[1] == "cancelled":
            return False
        if tree[1] == "always":
            return True
        raise ValueError("function %s() is not modelled" % tree[1])
    if kind == "ref":
        parts = tree[1].split(".")
        if parts[0] == "needs" and len(parts) > 1 and parts[1] not in needs:
            raise ValueError("needs.%s is named but not needed" % parts[1])
        cur = ctx
        for part in parts:
            cur = cur.get(part) if isinstance(cur, dict) else None
        return cur
    raise ValueError(kind)


def job_table(text):
    """{job: (needs, if)} for every job, in file order, read as written."""
    lines = text.split("\n")
    top = RP._child(lines, 0, len(lines), 0, "jobs")
    jobs, i = {}, top[0] + 1
    while i < top[1]:
        m = re.match(r"  ([a-z0-9-]+):\s*$", lines[i])
        if not m:
            i += 1
            continue
        span = RP.job_span(lines, m.group(1))
        needs, cond = [], None
        got = RP._child(lines, span[0] + 1, span[1], 4, "needs")
        if got:
            value = lines[got[0]].split(":", 1)[1].strip()
            needs = [n.strip() for n in value.strip("[]").split(",") if n.strip()]
        got = RP._child(lines, span[0] + 1, span[1], 4, "if")
        if got:
            value = lines[got[0]].split(":", 1)[1].strip()
            if value in (">-", ">", "|", "|-"):
                value = " ".join(l.strip() for l in lines[got[0] + 1:got[1]]
                                 if l.strip() and not l.strip().startswith("#"))
            cond = value
        jobs[m.group(1)] = (needs, cond)
        i = span[1]
    return jobs


BUILD_JOBS = ("plan", "cmake-members", "cmake-members-named", "coinxt", "kat-windows",
              "mac-lipo", "mac-lipo-named", "android")
ARTIFACT_JOBS = ("cmake-members", "cmake-members-named", "coinxt", "mac-lipo",
                 "mac-lipo-named", "android")
DYNAMIC = {spec["twin"]: spec["output"] for spec in RP.MATRIX_JOBS.values()}

# The conditions before 2026-11-21, as written then: the spec a full run is
# held to. (The plan job and the twins did not exist.)
OLD = {
    "cmake-members": ([], "github.event.inputs.lanes != 'android'"),
    "coinxt": ([], "github.event.inputs.lanes != 'android'"),
    "kat-windows": (["coinxt"], None),
    "mac-lipo": ([], "github.event.inputs.mac_lipo != 'false' && "
                     "github.event.inputs.lanes != 'android'"),
    "android": ([], "github.event.inputs.lanes != 'desktop'"),
    "bundle": (["cmake-members", "coinxt", "kat-windows", "mac-lipo", "android"], "always()"),
    "commit-binaries": (
        ["cmake-members", "coinxt", "kat-windows", "mac-lipo", "android", "bundle"],
        "!cancelled() && github.event.inputs.commit_mode != 'none' && "
        "(needs.cmake-members.result == 'success' || (needs.cmake-members.result == "
        "'skipped' && github.event.inputs.lanes == 'android')) && "
        "(needs.coinxt.result == 'success' || (needs.coinxt.result == 'skipped' && "
        "github.event.inputs.lanes == 'android')) && "
        "(needs.kat-windows.result == 'success' || (needs.kat-windows.result == "
        "'skipped' && github.event.inputs.lanes == 'android')) && "
        "(needs.mac-lipo.result == 'success' || needs.mac-lipo.result == 'skipped') && "
        "(needs.android.result == 'success' || (needs.android.result == 'skipped' && "
        "github.event.inputs.lanes == 'desktop')) && needs.bundle.result == 'success'"),
}


def simulate(jobs, inputs, plan_out, fail, chain=False):
    """Run the job graph once: which jobs run, each one's result, and the
    plan's outputs (None: the plan is refused, so it fails).

    `chain` is how a status function reads the jobs before it. GitHub's
    docs say a failure or skip "applies to all jobs in the dependency chain
    from the point of failure or skip onwards", and a success() over every
    ANCESTOR is the reading that makes it so (a job whose need ran under
    !cancelled() after a skip is still skipped); over the direct needs is
    the other. The wiring must hold under both, so the test runs both."""
    trees = {j: condition(c) for j, (n, c) in jobs.items()}
    ctx = {"github": {"event": {"inputs": inputs}}, "needs": {}}
    results, problems, ancestors = {}, [], {}
    for job, (needs, _) in jobs.items():
        for n in needs:
            if n not in results:
                problems.append("%s needs %s, which is not an earlier job" % (job, n))
        ancestors[job] = set(needs).union(*(ancestors.get(n, set()) for n in needs))
        scope = sorted(ancestors[job]) if chain else needs
        try:
            runs = truthy(evaluate(trees[job], ctx, needs, scope))
        except ValueError as e:
            problems.append("%s: %s" % (job, e))
            runs = False
        if not runs:
            result = "skipped"
        elif job == "plan":
            result = "failure" if plan_out is None or job in fail else "success"
        elif job == "bundle":
            # It collects what the jobs it waited for uploaded, and fails
            # (if-no-files-found: error) when there is nothing.
            result = ("success" if any(results.get(j) == "success" for j in ARTIFACT_JOBS
                                       if j in needs) else "failure")
        else:
            result = "failure" if job in fail else "success"
            if job in DYNAMIC and plan_out is not None and not plan_out[DYNAMIC[job]]:
                problems.append("%s runs with an empty matrix" % job)
        results[job] = result
        outputs = {}
        if job == "plan" and result == "success":
            outputs = {k: (json.dumps(v, separators=(",", ":")) if isinstance(v, list)
                           and k != "android" else
                           " ".join(v) if k == "android" else
                           ("true" if v else "false") if isinstance(v, bool) else v)
                       for k, v in plan_out.items()}
        ctx["needs"][job] = {"result": result, "outputs": outputs}
    return results, problems


def test_wiring(text, rows, quiet=False):
    if not quiet:
        print("3. the wiring")
    jobs = job_table(text)
    known = set(BUILD_JOBS) | {"bundle", "commit-binaries"}
    check(set(jobs) == known, "the workflow's jobs are the ones this test classifies "
          "(a new job needs a place in a named build: add it here and to the plan)",
          sorted(set(jobs) ^ known))
    if set(jobs) != known:
        return

    # Fixture: the evaluator models the success() Actions prepends. Run
    # 37413026408's commit condition had no !cancelled(), and a skipped
    # mac-lipo skipped the commit job; today's has it, and does not.
    then = dict(OLD)
    then["commit-binaries"] = (OLD["commit-binaries"][0],
                               OLD["commit-binaries"][1].replace("!cancelled() && ", "", 1))
    inputs = {"commit_mode": "branch", "lanes": "all", "mac_lipo": "false"}
    got, _ = simulate(then, inputs, None, ())
    check(got["mac-lipo"] == "skipped" and got["commit-binaries"] == "skipped",
          "fixture: without !cancelled(), a skipped need skips the commit (run "
          "37413026408)", got)
    got, _ = simulate(OLD, inputs, None, ())
    check(got["commit-binaries"] == "success", "fixture: with it, the commit runs", got)
    check(equal(None, "") and equal("Named", "named") and not equal(None, "[]")
          and not equal("1", "true"), "fixture: Actions' loose comparisons")
    # Fixture: the two readings of a status function differ where they
    # should. a is skipped, b runs after it under !cancelled(), c needs b and
    # says nothing: over the needs c runs, over the chain it is skipped.
    toy = {"a": ([], "false"), "b": (["a"], "!cancelled()"), "c": (["b"], None)}
    direct, _ = simulate(toy, {}, None, ())
    chained, _ = simulate(toy, {}, None, (), chain=True)
    check(direct["b"] == chained["b"] == "success" and direct["c"] == "success"
          and chained["c"] == "skipped", "fixture: a skip two levels up skips a job "
          "with no status function over the chain, and not over the needs",
          (direct, chained))

    # Two members the tree does not have, so that every shape a plan can
    # take is driven even while every real member builds everywhere: zzzxt
    # has one desktop row and no Android build (a DESKTOP_ONLY member of
    # build-android.sh), yyyxt an Android build and no desktop row.
    rows = dict(rows)
    rows["cmake-members"] = rows["cmake-members"] + [
        {"member": "zzzxt", "platform_id": "x86_64-linux", "os": "ubuntu-24.04"}]
    android = RP.android_members() + ["yyyxt"]
    have = set(android) | {"coinxt"} | {r["member"] for j in rows for r in rows[j]}
    member_cases = [[m] for m in sorted(have)] + [
        ["curlxt", "coinxt"], ["torrentxt", "datachannelxt"], ["enetxt", "sodiumxt", "box2dxt"],
        ["zzzxt", "yyyxt"], ["zzzxt", "coinxt"]]
    refused = ["", "all", "curlx", "onionxt", "curlxt\tcoinxt"]

    def scenarios():
        for build in (None, "all"):
            for lanes in (None, "all", "desktop", "android"):
                for mac in (None, "true", "false"):
                    for commit in ("branch", "none"):
                        yield (build, lanes, mac, commit, None)
        for names in [" ".join(c) for c in member_cases] + refused:
            for lanes in ("all", "desktop", "android"):
                for mac in ("true", "false"):
                    for commit in ("branch", "none"):
                        yield ("named", lanes, mac, commit, names)

    count = 0
    for (build, lanes, mac, commit, names), chain in itertools.product(scenarios(),
                                                                        (False, True)):
        inputs = {k: v for k, v in (("build", build), ("lanes", lanes), ("mac_lipo", mac),
                                    ("commit_mode", commit), ("members", names))
                  if v is not None}
        plan_out = None
        if build == "named":
            try:
                plan_out = RP.plan(rows, android, RP.parse_members(names))
            except RP.PlanError:
                plan_out = None
        label = "build=%s lanes=%s mac_lipo=%s commit_mode=%s members=%r (%s)" % (
            build, lanes, mac, commit, names,
            "status over the chain" if chain else "status over the needs")
        base, problems = simulate(jobs, inputs, plan_out, (), chain)
        check(not problems, label + ": every condition evaluates", problems)
        ran = [j for j in BUILD_JOBS if base[j] != "skipped"]
        lane = lanes or "all"
        if build != "named":
            old, _ = simulate(OLD, inputs, None, (), chain)
            want = {j for j in OLD if j not in ("bundle", "commit-binaries")
                    and old[j] != "skipped"}
            check(set(ran) == want, label + ": a full run runs what it ran before",
                  (ran, sorted(want)))
        else:
            want = {"plan"}  # it runs whatever was named, and fails a refusal
            if plan_out is not None:
                if lane != "android" and plan_out["cmake"]:
                    want.add("cmake-members-named")
                if lane != "android" and mac != "false" and plan_out["maclipo"]:
                    want.add("mac-lipo-named")
                if lane != "android" and plan_out["coinxt"]:
                    want |= {"coinxt", "kat-windows"}
                if lane != "desktop" and plan_out["android"]:
                    want.add("android")
            check(set(ran) == want, label + ": a named run runs the plan and the named "
                  "members' lanes, and nothing else", (ran, sorted(want)))
        # Every combination of the jobs that ran failing: the commit runs
        # only when none did, and a full run decides as it did before.
        could = [j for j in ran]
        for k in range(len(could) + 1):
            for failed in itertools.combinations(could, k):
                got, problems = simulate(jobs, inputs, plan_out, set(failed), chain)
                count += 1
                if problems:
                    check(False, label + " failing %s: conditions evaluate" % (failed,),
                          problems)
                    continue
                extra = [j for j in BUILD_JOBS if got[j] != "skipped" and j not in ran]
                check(not extra, label + " failing %s: a failure never starts a job"
                      % (failed,), extra)
                landed = got["commit-binaries"] != "skipped"
                should = (commit != "none" and not failed and got["bundle"] == "success"
                          and (build != "named" or plan_out is not None))
                check(landed == should, label + " failing %s: the commit job %s"
                      % (failed, "runs only when nothing failed" if should else
                         "must not run"), got)
                if build != "named":
                    old, _ = simulate(OLD, inputs, None, set(failed), chain)
                    check(landed == (old["commit-binaries"] != "skipped"),
                          label + " failing %s: a full run commits when it did before"
                          % (failed,), (got, old))
    if not quiet:
        print("  %d runs of the job graph evaluated" % count)
    check(set(jobs["bundle"][0]) == set(BUILD_JOBS) - {"plan"},
          "the bundle waits for every job that builds (a twin it did not wait for "
          "would upload after it collected)", jobs["bundle"][0])
    check(set(jobs["commit-binaries"][0]) == set(BUILD_JOBS) | {"bundle"},
          "the commit job waits for every job, the plan included", jobs["commit-binaries"][0])

    # The shape of the twins, the plan job and the Android job.
    lines = text.split("\n")

    def line_of(job, *path):
        """The line of job.path[0].path[1]..., each key one level (two
        spaces) below the last, as written; None if any is missing."""
        span = RP.job_span(lines, job)
        lo, hi, got = span[0] + 1, span[1], None
        for depth, key in enumerate(path):
            got = RP._child(lines, lo, hi, 4 + 2 * depth, key)
            if not got:
                return None
            lo, hi = got[0] + 1, got[1]
        return lines[got[0]].strip()

    def keys_of(job):
        span = RP.job_span(lines, job)
        return {m.group(1) for l in lines[span[0] + 1:span[1]]
                for m in [re.match(r"    ([A-Za-z_][A-Za-z0-9_-]*):", l)] if m}

    def block_of(job, key):
        span = RP.job_span(lines, job)
        got = RP._child(lines, span[0] + 1, span[1], 4, key)
        return [l for l in lines[got[0]:got[1]] if l.strip()
                and not l.strip().startswith("#")] if got else None

    for job, spec in RP.MATRIX_JOBS.items():
        twin, output = spec["twin"], spec["output"]
        anchor = line_of(job, "steps")
        m = re.fullmatch(r"steps: &([A-Za-z0-9-]+)", anchor or "")
        check(m is not None, "%s's steps carry an anchor" % job, anchor)
        if m:
            check(line_of(twin, "steps") == "steps: *" + m.group(1),
                  "  ...and %s's steps are its alias" % twin, line_of(twin, "steps"))
            check(text.count("&" + m.group(1)) == 1 and text.count("*" + m.group(1)) == 1,
                  "  ...the anchor defined once and used once", m.group(1))
        # Every key of the original's but its if, strategy and steps is the
        # twin's, as written (a timeout or an env added to one alone would
        # make a named build of a lane differ from a full one); the twin
        # adds only `needs`.
        check(keys_of(twin) == keys_of(job) | {"needs"},
              "%s has %s's keys, and needs the plan" % (twin, job),
              sorted(keys_of(twin) ^ (keys_of(job) | {"needs"})))
        for key in sorted(keys_of(job) - {"if", "strategy", "steps"}):
            check(block_of(job, key) == block_of(twin, key),
                  "%s's %s is %s's" % (twin, key, job), (block_of(job, key),
                                                         block_of(twin, key)))
        include = line_of(twin, "strategy", "matrix", "include")
        check(include == "include: ${{ fromJSON(needs.plan.outputs.%s) }}" % output,
              "%s's matrix is the plan's %s output" % (twin, output), include)
        check(line_of(twin, "strategy", "fail-fast") ==
              line_of(job, "strategy", "fail-fast") == "fail-fast: false",
              "%s keeps fail-fast off, as %s does" % (twin, job),
              (line_of(twin, "strategy", "fail-fast"), line_of(job, "strategy", "fail-fast")))
    outputs = block_of("plan", "outputs") or []
    for name in [s["output"] for s in RP.MATRIX_JOBS.values()] + ["coinxt", "android"]:
        check("      %s: ${{ steps.plan.outputs.%s }}" % (name, name) in outputs,
              "the plan job outputs %s from its step" % name, outputs)
    plan_step = "\n".join(block_of("plan", "steps") or [])
    check('MEMBERS: ${{ github.event.inputs.members }}' in plan_step
          and 'python3 tools/release-plan.py --members "$MEMBERS"' in plan_step
          and '--github-output "$GITHUB_OUTPUT"' in plan_step,
          "the plan step runs this tool on the `members` input")
    android_steps = "\n".join(block_of("android", "steps") or [])
    # The Choose step loops over what it chooses FROM; every other step's
    # loop (the build and the stage) must read what it chose.
    steps = re.split(r"\n(?=      - )", android_steps)
    choose = [st for st in steps if "name: Choose the members" in st]
    loops = [l for st in steps if st not in choose
             for l in re.findall(r"for member in (.+); do", st)]
    check(len(choose) == 1 and len(loops) == 2
          and all(l == "$ANDROID_MEMBERS" for l in loops),
          "the Android job's build and stage loops read the chosen list", loops)
    check("NAMED: ${{ needs.plan.outputs.android }}" in android_steps
          and 'echo "ANDROID_MEMBERS=$chosen" >> "$GITHUB_ENV"' in android_steps
          and 'want=$(wc -w <<< "${ANDROID_MEMBERS:-}")' in android_steps,
          "  ...which the Choose step makes from the plan, and the emulator rows count")
    inp = re.search(r"\n      build:\n((?:        .*\n)+)", text)
    check(inp is not None and "options: [all, named]" in inp.group(1)
          and "default: all" in inp.group(1), "the `build` input: all or named, all "
          "by default", inp.group(1) if inp else None)
    check("$MEMBERS" in "\n".join(block_of("commit-binaries", "steps") or [])
          and "MEMBERS: ${{ github.event.inputs.members }}" in text,
          "the commit job still narrows the install by `members`")


# Fixture before gate: mistakes the wiring checks must catch, each made in
# the workflow's text in memory (old, new), found exactly once.
MUTANTS = [
    ("the full desktop job also runs in a named build",
     "    if: github.event.inputs.lanes != 'android' && github.event.inputs.build != 'named'\n",
     "    if: github.event.inputs.lanes != 'android'\n"),
    ("the full mac job also runs in a named build",
     "    if: github.event.inputs.mac_lipo != 'false' && github.event.inputs.lanes != "
     "'android' && github.event.inputs.build != 'named'\n",
     "    if: github.event.inputs.mac_lipo != 'false' && github.event.inputs.lanes != "
     "'android'\n"),
    ("coinxt without !cancelled() (the skipped plan of a full run would skip it)",
     "      !cancelled() && github.event.inputs.lanes != 'android' &&\n",
     "      github.event.inputs.lanes != 'android' &&\n"),
    ("Android builds in a named run that named no Android member",
     "       (needs.plan.result == 'success' && needs.plan.outputs.android != ''))",
     "       needs.plan.result == 'success')"),
    ("a twin runs when the plan gave it no rows (an empty matrix)",
     "needs.plan.outputs.cmake != '[]'\n", "true\n"),
    ("the Windows KATs left to the implicit success() (a skipped plan two levels "
     "up skips them in every full build)",
     "    if: ${{ !cancelled() && needs.coinxt.result == 'success' }}\n", ""),
    ("the plan job never runs",
     "    if: github.event.inputs.build == 'named'\n",
     "    if: github.event.inputs.build == 'all'\n"),
    ("the commit job loses !cancelled()",
     "    if: >-\n      !cancelled() &&\n      github.event.inputs.commit_mode != 'none' &&",
     "    if: >-\n      github.event.inputs.commit_mode != 'none' &&"),
    ("the commit job takes a failed twin",
     "      (needs.cmake-members-named.result == 'success' ||",
     "      (needs.cmake-members-named.result != 'cancelled' ||"),
    ("the commit job refuses a named run that left coinxt's KATs out",
     "      (needs.kat-windows.result == 'success' ||\n"
     "       (needs.kat-windows.result == 'skipped' &&\n"
     "        (github.event.inputs.lanes == 'android' ||\n"
     "         (github.event.inputs.build == 'named' && needs.plan.outputs.coinxt != 'true')))) &&",
     "      (needs.kat-windows.result == 'success' ||\n"
     "       (needs.kat-windows.result == 'skipped' && github.event.inputs.lanes == 'android')) &&"),
    ("the bundle no longer waits for a twin",
     "    needs: [cmake-members, cmake-members-named, coinxt, kat-windows, mac-lipo, "
     "mac-lipo-named, android]\n",
     "    needs: [cmake-members, coinxt, kat-windows, mac-lipo, mac-lipo-named, android]\n"),
    ("a twin's steps alias the other job's",
     "    steps: *cmake-member-steps\n", "    steps: *mac-lipo-steps\n"),
    ("a twin reads the other twin's rows",
     "        include: ${{ fromJSON(needs.plan.outputs.cmake) }}\n",
     "        include: ${{ fromJSON(needs.plan.outputs.maclipo) }}\n"),
    ("a twin runs somewhere else",
     "    runs-on: macos-15\n    defaults:\n      run:\n"
     "        working-directory: ${{ matrix.member }}\n    steps: *mac-lipo-steps\n",
     "    runs-on: macos-14\n    defaults:\n      run:\n"
     "        working-directory: ${{ matrix.member }}\n    steps: *mac-lipo-steps\n"),
    ("a twin gains a key its original lacks",
     "    container: ${{ matrix.container }}\n    defaults:\n      run:\n"
     "        working-directory: ${{ matrix.member }}\n    steps: *cmake-member-steps\n",
     "    container: ${{ matrix.container }}\n    timeout-minutes: 5\n    defaults:\n"
     "      run:\n        working-directory: ${{ matrix.member }}\n"
     "    steps: *cmake-member-steps\n"),
    ("the Android build loop reads every member again",
     # The line after the loop's head is the emulator switch for a member
     # built for a later Android (torrentxt), not the group marker.
     "          for member in $ANDROID_MEMBERS; do\n            if [ -n \"$booted\" ]; then",
     "          for member in $(bash tools/build-android.sh --list | sed -n "
     "'s/^members: *//p'); do\n            if [ -n \"$booted\" ]; then"),
    ("the Choose step writes the whole list",
     'echo "ANDROID_MEMBERS=$chosen" >> "$GITHUB_ENV"',
     'echo "ANDROID_MEMBERS=$listed" >> "$GITHUB_ENV"'),
    ("the build input defaults to named",
     "        options: [all, named]\n        default: all\n",
     "        options: [all, named]\n        default: named\n"),
]


def test_mutants(text, rows):
    print("4. the wiring checks are not blind")
    for label, old, new in MUTANTS:
        if not check(text.count(old) == 1, "mutant %r is found once in the workflow"
                     % label, text.count(old)):
            continue
        SINK.append([])
        try:
            test_wiring(text.replace(old, new), rows, quiet=True)
            caught = None
        except Caught as e:
            caught = str(e)
        finally:
            SINK.pop()
        check(caught is not None, "the wiring checks catch: " + label)
    if not FAILURES:
        print("  %d mutants, each caught" % len(MUTANTS))


def main():
    text, rows = test_reader()
    test_plan(text, rows)
    test_wiring(text, rows)
    test_mutants(text, rows)
    if FAILURES:
        print("\n%s: %d FAILURE(S)" % (TAG, len(FAILURES)))
        for failure in FAILURES[:40]:
            print("  " + failure)
        return 1
    print("\n%s: OK - the reader reads the rows and refuses every other shape, a "
          "named plan is the named members' rows, and the job graph runs a full "
          "build as before and a named build alone" % TAG)
    return 0


if __name__ == "__main__":
    sys.exit(main())
