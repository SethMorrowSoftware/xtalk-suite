#!/usr/bin/env python3
"""release-plan.py - which lanes of release-binaries.yml a NAMED build runs.

    python3 tools/release-plan.py --members "curlxt coinxt"
    python3 tools/release-plan.py --members "$MEMBERS" \\
        --github-output "$GITHUB_OUTPUT" --summary "$GITHUB_STEP_SUMMARY"
    python3 tools/release-plan.py --rows cmake-members     # the rows as read, JSON

WHY. Until 2026-11-21 every dispatch of release-binaries.yml built every lane
of every native member, whatever its `members` input said: that input narrows
what is INSTALLED, never what is built. On that day several members were each
waiting on a release run of their own, every run asked the account for every
lane, the account runs about twenty jobs at a time, and runs queued for hours
behind each other's rebuilds of libraries none of them had changed. The
`build: named` input builds only the named members' lanes, and this tool is
its plan job: it reads the lanes from the workflow, keeps the named members'
rows, and hands them to the twin jobs as their matrices.

WHERE THE ROWS LIVE. Where they always have: the `include:` lists of the
workflow's cmake-members and mac-lipo jobs. Nothing is copied into this tool
or a data file, so a member's rows are written once, beside every other
member's, and a branch that adds rows (six open pull requests did on the day
this was written) merges as it would have. A full run (`build: all`, the
default) is those two jobs as they always were. A named run skips them and
runs their twins, cmake-members-named and mac-lipo-named, whose steps ARE the
originals' (a YAML anchor) and whose matrices are this tool's output. The
coinxt job builds one member, so a named run runs it whole or not at all, and
the Android job builds, per ABI, the named members among the ones
tools/build-android.sh lists.

THE READER. It reads one shape, strictly: a block sequence of flat mappings,
each value a plain scalar, a quoted string or an integer, with comments and
blank lines between rows. Anything else (a flow collection, a block scalar,
an anchor, an alias, a tag, an expression, a value spanning lines, a
duplicate key, a word YAML's two versions read differently) stops it, with
the line named. What it cannot read it must not guess at: a row read
differently from GitHub's own reading would build a library one way in a
named run and another in a full one. tools/test-release-plan.py runs it over
the real workflow on every push, so a row that leaves the shape fails the
suite gates, not a dispatch, and compares its rows with PyYAML's reading of
the same file where PyYAML is installed.

THE NAMES. `members` is the same input the commit job narrows the install
by, so the two read it the same way: names separated by spaces. A named
build refuses an empty list, `all`, a name no lane builds (a typo would
otherwise build nothing and commit nothing, after a queue), and a tab or a
line break between names (the commit job's `case " $MEMBERS "` match would
not see a name after one).

Exit status: 0 with a plan, 1 when the members or the workflow are refused
(the message says which), 2 on a usage error.
"""

import argparse
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WORKFLOW = os.path.join(ROOT, ".github", "workflows", "release-binaries.yml")
ANDROID_SCRIPT = os.path.join(HERE, "build-android.sh")
TAG = "release-plan"

# The jobs whose static `include:` rows a named build filters, the twin that
# runs the kept rows, the plan output that carries them, and the keys every
# row of the job must have.
MATRIX_JOBS = {
    "cmake-members": {"twin": "cmake-members-named", "output": "cmake",
                      "required": ("member", "platform_id", "os")},
    "mac-lipo": {"twin": "mac-lipo-named", "output": "maclipo",
                 "required": ("member",)},
}
# The job that builds exactly one member (its rows are platforms, with no
# `member` key): a named run runs it whole or skips it.
WHOLE_JOBS = {"coinxt": "coinxt"}

NAME = re.compile(r"[a-z][a-z0-9]*\Z")
KEY_LINE = re.compile(r"([A-Za-z_][A-Za-z0-9_-]*):(?:[ ]+(.*))?\Z")
# Words YAML 1.1 (PyYAML) and YAML 1.2 read as different types, plus null and
# the floats: a row must quote any of them, so no parser has to choose.
AMBIGUOUS = re.compile(
    r"(?i:null|~|y|n|yes|no|on|off|true|false|[-+]?\.(?:inf|nan))\Z"
    r"|[-+]?(?:[0-9][0-9_]*)?\.[0-9_]*(?:[eE][-+]?[0-9]+)?\Z"
    r"|[-+]?[0-9][0-9_]*[eE][-+]?[0-9]+\Z"
    r"|[-+]?0[xob][0-9a-fA-F_]+\Z"
    r"|[-+]?0[0-9_]+\Z"
    r"|[-+]?[0-9]+(?::[0-5]?[0-9])+\Z"
    r"|[-+]?[0-9][0-9_]*_[0-9_]*\Z")
INTEGER = re.compile(r"[-+]?(?:0|[1-9][0-9]*)\Z")
ESCAPES = {'"': '"', "\\": "\\", "/": "/", "n": "\n", "t": "\t"}


class ReadError(Exception):
    """The workflow left the shape this reader reads. Never caught to a guess."""

    def __init__(self, line, msg):
        super().__init__("%s:%d: %s" % (os.path.basename(WORKFLOW), line, msg)
                         if line else msg)


class PlanError(Exception):
    """The members asked for cannot make a named build."""


# ------------------------------------------------------------------ reading

def _indent(line):
    return len(line) - len(line.lstrip(" "))


def _skip(line):
    """A blank line, or one that is only a comment."""
    s = line.strip()
    return not s or s.startswith("#")


def _child(lines, lo, hi, indent, key):
    """The line index of `key:` among the lines[lo:hi] at exactly `indent`
    (a child of the mapping those lines belong to), and the index where its
    block ends; None if the mapping has no such key."""
    want = re.compile(r" {%d}%s:(?:[ ]|\Z)" % (indent, re.escape(key)))
    for i in range(lo, hi):
        line = lines[i]
        if _skip(line):
            continue
        if _indent(line) < indent:
            return None
        if _indent(line) == indent and want.match(line):
            end = i + 1
            while end < hi and (_skip(lines[end]) or _indent(lines[end]) > indent):
                end += 1
            return i, end
    return None


def job_span(lines, job):
    """(header index, end index) of `jobs.<job>`, or None."""
    top = _child(lines, 0, len(lines), 0, "jobs")
    if top is None:
        raise ReadError(0, "the workflow has no top-level `jobs:`")
    return _child(lines, top[0] + 1, top[1], 2, job)


def _comment_only(rest, line):
    rest = rest.strip()
    if rest and not rest.startswith("#"):
        raise ReadError(line, "text after a quoted value: %r" % rest)


def _scalar(text, line):
    """One row value, as GitHub's YAML would read it, or ReadError."""
    s = text.strip()
    if not s or s.startswith("#"):
        raise ReadError(line, "an empty value (YAML reads null, or a nested "
                              "block follows): give it a value")
    if "\t" in s:
        raise ReadError(line, "a tab in a value")
    if s[0] == '"':
        out, i = [], 1
        while i < len(s):
            ch = s[i]
            if ch == "\\":
                nxt = s[i + 1:i + 2]
                if nxt not in ESCAPES:
                    raise ReadError(line, "an escape this reader does not read: \\%s" % nxt)
                out.append(ESCAPES[nxt])
                i += 2
                continue
            if ch == '"':
                _comment_only(s[i + 1:], line)
                return _no_expression("".join(out), line)
            out.append(ch)
            i += 1
        raise ReadError(line, "a double-quoted value that does not close on its line")
    if s[0] == "'":
        out, i = [], 1
        while i < len(s):
            if s[i] == "'":
                if s[i + 1:i + 2] == "'":
                    out.append("'")
                    i += 2
                    continue
                _comment_only(s[i + 1:], line)
                return _no_expression("".join(out), line)
            out.append(s[i])
            i += 1
        raise ReadError(line, "a single-quoted value that does not close on its line")
    if s[0] in "[]{},&*!|>%@`#":
        raise ReadError(line, "a value starting with %r (a flow collection, anchor, "
                              "alias, tag, block scalar or reserved character)" % s[0])
    if s[0] in "-?:" and (len(s) == 1 or s[1] == " "):
        raise ReadError(line, "a value starting with %r and a space" % s[0])
    cut = s.find(" #")
    if cut != -1:
        s = s[:cut].rstrip()
    if ": " in s or s.endswith(":"):
        raise ReadError(line, "a ': ' inside an unquoted value (YAML would read a "
                              "mapping there): quote it")
    if INTEGER.match(s):
        return int(s)
    if AMBIGUOUS.match(s):
        raise ReadError(line, "%r: YAML reads this as something other than text, or "
                              "reads it differently by version (null, a boolean, a "
                              "float, octal, hex, base 60): quote it" % s)
    return _no_expression(s, line)


def _no_expression(value, line):
    # A static matrix value with ${{ }} in it is EVALUATED by Actions; the same
    # text arriving through fromJSON() is not. So a row cannot carry one.
    if "${{" in value:
        raise ReadError(line, "an expression in a row (${{ }} is evaluated in a "
                              "static matrix and not in one from fromJSON())")
    return value


def _pair(text, line, row):
    m = KEY_LINE.match(text.rstrip())
    if not m:
        raise ReadError(line, "not a `key: value` line: %r" % text.strip())
    key, rest = m.group(1), m.group(2)
    if key in row:
        raise ReadError(line, "the key %r twice in one row" % key)
    row[key] = _scalar(rest or "", line)


def read_rows(text, job):
    """The `strategy.matrix.include` rows of `jobs.<job>`, in order, each a
    dict; None when the job has no such list (it does not exist, or its
    include is an expression, as a twin's is)."""
    lines = text.split("\n")
    span = job_span(lines, job)
    if span is None:
        return None
    strategy = _child(lines, span[0] + 1, span[1], 4, "strategy")
    if strategy is None:
        return None
    matrix = _child(lines, strategy[0] + 1, strategy[1], 6, "matrix")
    if matrix is None:
        return None
    include = _child(lines, matrix[0] + 1, matrix[1], 8, "include")
    if include is None:
        return None
    head = lines[include[0]].strip()[len("include:"):].strip()
    if head and not head.startswith("#"):
        return None                     # an expression: the list is not here
    rows, row, dash = [], None, None
    for i in range(include[0] + 1, include[1]):
        raw, n = lines[i], i + 1
        if _skip(raw):
            continue
        if "\t" in raw[:_indent(raw) + 1]:
            raise ReadError(n, "a tab in the indentation")
        ind, body = _indent(raw), raw.strip()
        if body == "-" or body.startswith("- "):
            if dash is None:
                dash = ind
            if ind != dash:
                raise ReadError(n, "a row whose dash is not in line with the first row's")
            if body == "-" or not body[2:].strip():
                raise ReadError(n, "a dash alone on its line: start the row's mapping "
                                   "on the dash's line")
            row = {}
            rows.append((n, row))
            _pair(body[2:].strip(), n, row)
        else:
            if row is None:
                raise ReadError(n, "a line before the first row")
            if ind != dash + 2:
                raise ReadError(n, "a line that is not a key of the row above at its "
                                   "indentation (a value spanning lines, or a nested block)")
            _pair(body, n, row)
    return [r for _, r in rows], [n for n, _ in rows]


def lanes(text):
    """Every filtered job's rows, checked: {job: [row, ...]}."""
    out = {}
    for job, spec in MATRIX_JOBS.items():
        got = read_rows(text, job)
        if got is None:
            raise ReadError(0, "jobs.%s has no strategy.matrix.include list of rows" % job)
        rows, starts = got
        if not rows:
            raise ReadError(0, "jobs.%s lists no rows" % job)
        seen = set()
        for row, n in zip(rows, starts):
            for key in spec["required"]:
                if key not in row:
                    raise ReadError(n, "a %s row with no %r" % (job, key))
            if not isinstance(row["member"], str) or not NAME.match(row["member"]):
                raise ReadError(n, "member %r is not a member's name" % (row["member"],))
            ident = (row["member"], row.get("platform_id"))
            if ident in seen:
                raise ReadError(n, "a second %s row for %s" % (job, "/".join(
                    x for x in ident if x)))
            seen.add(ident)
        out[job] = rows
    return out


def android_members(script=ANDROID_SCRIPT):
    """The members tools/build-android.sh builds (its --list `members:` line,
    the list the Android job's own loops read)."""
    done = subprocess.run(["bash", script, "--list"], capture_output=True,
                          text=True, timeout=60)
    found = [l.split(":", 1)[1].split() for l in done.stdout.splitlines()
             if l.startswith("members:")]
    if done.returncode != 0 or len(found) != 1 or not found[0]:
        raise ReadError(0, "build-android.sh --list named no members (exit %d): %s"
                        % (done.returncode, (done.stderr or done.stdout).strip()))
    return found[0]


# ----------------------------------------------------------------- planning

def parse_members(text):
    """The names in the `members` input, in order, once each."""
    text = text or ""
    if re.search(r"[^\S ]", text):
        raise PlanError("separate the names in `members` with spaces: a tab or a "
                        "line break hides the next name from the commit job")
    names = []
    for word in text.split(" "):
        if word and word not in names:
            names.append(word)
    if not names or names == ["all"]:
        raise PlanError("`build: named` builds the members `members` names, and it "
                        "names none (%r): name them, or choose `build: all`" % text)
    if "all" in names:
        raise PlanError("`members` mixes `all` with names: name the members alone")
    bad = [w for w in names if not NAME.match(w)]
    if bad:
        raise PlanError("not a member's name: %s" % ", ".join(repr(w) for w in bad))
    return names


def plan(rows, android, names):
    """What a named build of `names` runs: {output: value} for the plan job."""
    have = {}
    for job in MATRIX_JOBS:
        for row in rows[job]:
            have.setdefault(row["member"], set()).add(job)
    for job, member in WHOLE_JOBS.items():
        have.setdefault(member, set()).add(job)
    for member in android:
        have.setdefault(member, set()).add("android")
    unknown = [n for n in names if n not in have]
    if unknown:
        raise PlanError("no release lane builds %s; the members with lanes are: %s"
                        % (", ".join(unknown), " ".join(sorted(have))))
    out = {}
    for job, spec in MATRIX_JOBS.items():
        out[spec["output"]] = [r for r in rows[job] if r["member"] in names]
    for job, member in WHOLE_JOBS.items():
        out[job] = member in names
    out["android"] = [m for m in android if m in names]
    out["members"] = names
    return out


def outputs(p):
    """The plan as the plan job's step outputs (one line each)."""
    lines = []
    for job, spec in MATRIX_JOBS.items():
        lines.append("%s=%s" % (spec["output"],
                                json.dumps(p[spec["output"]], separators=(",", ":"))))
    for job in WHOLE_JOBS:
        lines.append("%s=%s" % (job, "true" if p[job] else "false"))
    lines.append("android=%s" % " ".join(p["android"]))
    lines.append("members=%s" % " ".join(p["members"]))
    return lines


def summary(p):
    """What runs, for the run's front page and the log."""
    out = ["### A named build: %s" % " ".join(p["members"]), "",
           "| job | lanes |", "|---|---|"]
    for job, spec in MATRIX_JOBS.items():
        rows = p[spec["output"]]
        out.append("| %s | %s |" % (spec["twin"], ", ".join(
            "%s %s" % (r["member"], r.get("platform_id", "universal-mac"))
            for r in rows) if rows else "none"))
    for job, member in WHOLE_JOBS.items():
        out.append("| %s | %s |" % (job, "every platform (and the Windows KATs)"
                                    if p[job] else "none"))
    out.append("| android | %s |" % ("%s, on each of the four ABIs"
                                     % " ".join(p["android"]) if p["android"] else "none"))
    out += ["", "Every other lane is skipped. The `lanes` and `mac_lipo` inputs "
                "still apply, and `members` still decides what is installed."]
    return out


def main(argv):
    ap = argparse.ArgumentParser(prog="release-plan.py", description=__doc__.split("\n")[0])
    ap.add_argument("--members", help="the `members` input of a named build")
    ap.add_argument("--rows", metavar="JOB", help="print the rows read from JOB as JSON")
    ap.add_argument("--workflow", default=WORKFLOW)
    ap.add_argument("--android-list", metavar="MEMBERS",
                    help="the Android members, instead of running build-android.sh --list")
    ap.add_argument("--github-output", metavar="FILE", help="append the outputs here")
    ap.add_argument("--summary", metavar="FILE", help="append the summary here")
    args = ap.parse_args(argv)
    if (args.members is None) == (args.rows is None):
        ap.print_usage(sys.stderr)
        print("%s: give --members or --rows" % TAG, file=sys.stderr)
        return 2
    try:
        with open(args.workflow, encoding="utf-8") as fh:
            text = fh.read()
        if args.rows is not None:
            got = read_rows(text, args.rows)
            if got is None:
                raise ReadError(0, "jobs.%s has no strategy.matrix.include list of rows"
                                % args.rows)
            print(json.dumps(got[0], indent=1))
            return 0
        rows = lanes(text)
        android = (args.android_list.split() if args.android_list is not None
                   else android_members())
        p = plan(rows, android, parse_members(args.members))
    except (ReadError, PlanError) as e:
        print("%s: REFUSED: %s" % (TAG, e), file=sys.stderr)
        if args.github_output:
            print("::error::%s" % e)
        return 1
    for line in summary(p):
        print(line)
    if args.summary:
        with open(args.summary, "a", encoding="utf-8") as fh:
            fh.write("\n".join(summary(p)) + "\n")
    if args.github_output:
        with open(args.github_output, "a", encoding="utf-8") as fh:
            fh.write("\n".join(outputs(p)) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
