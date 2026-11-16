#!/usr/bin/env python3
"""test-native-lane-paths.py - which changes start a member's native lane,
and which change the publisher holds that lane to.

Since 2026-11-16 a change to a member's docs or Markdown alone starts no
native-<member>.yml run (its THIRD-PARTY-LICENSES.md still does: the
packages carry it). Those lanes build and test on every platform, macOS
among them, and a dated record or an honesty label changes nothing they
test; the member's own gates, docs gates included, still run in
suite-gates.yml for such a change.

publish-members.yml holds a member back unless its lane is green on the
member's last change. A docs-only commit has no lane run, so the publisher
looks past it to the last change the lane's filter starts on. The two must
agree, so this test asks BOTH as they are written:

  - the lane's own `paths:` lists, read from every native-<member>.yml and
    evaluated the way GitHub does (a path is in when the LAST pattern that
    matches it is not a `!` pattern), for pull_request and push alike;
  - the publisher's awk program, cut out of publish-members.yml and RUN
    on the same changed-file lists.

A fixture first proves the evaluator sees the difference between a docs
change and a source change in the patterns before 2026-11-16 (where every
change started the lane), so a blind evaluator cannot pass.

USAGE
    python3 tools/test-native-lane-paths.py
"""

import glob
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WF = os.path.join(ROOT, ".github", "workflows")

failures = []


def fail(msg):
    failures.append(msg)
    print("FAIL: " + msg)


def glob_re(pattern):
    """GitHub's filter globs: `**` any characters, `*` any but `/`."""
    out, i = "", 0
    while i < len(pattern):
        if pattern.startswith("**/", i):
            out += "(?:.*/)?"
            i += 3
        elif pattern.startswith("**", i):
            out += ".*"
            i += 2
        elif pattern[i] == "*":
            out += "[^/]*"
            i += 1
        else:
            out += re.escape(pattern[i])
            i += 1
    return re.compile("^" + out + "$")


def starts(patterns, files):
    """Whether a change to `files` starts a workflow with these `paths:`."""
    for f in files:
        verdict = False
        for p in patterns:
            neg = p.startswith("!")
            if glob_re(p[1:] if neg else p).match(f):
                verdict = not neg
        if verdict:
            return True
    return False


def paths_blocks(text):
    """The `paths:` lists under on.pull_request and on.push, as written."""
    blocks, cur = [], None
    for line in text.split("\n"):
        if line == "    paths:":
            cur = []
            blocks.append(cur)
            continue
        if cur is not None:
            m = re.match(r'^      - "(.*)"$', line)
            if m:
                cur.append(m.group(1))
                continue
            cur = None
    return blocks


def publisher_awk():
    with open(os.path.join(WF, "publish-members.yml"), encoding="utf-8") as f:
        text = f.read()
    m = re.search(r"\| awk -v m=\"\$m/\" -v lane=\"\$lane\" '\n(.*?)'; then", text, re.S)
    if not m:
        sys.exit("FAIL: no awk program in publish-members.yml's lane step")
    return m.group(1)


def awk_starts(program, member, files):
    lane = ".github/workflows/native-%s.yml" % member
    p = subprocess.run(["awk", "-v", "m=%s/" % member, "-v", "lane=" + lane, program],
                       input="".join(f + "\n" for f in files), text=True)
    return p.returncode == 0


# (changed files with <m> for the member, does the lane start)
CASES = [
    (["<m>/src/x.c"], True),
    (["<m>/CMakeLists.txt"], True),
    (["<m>/tests/smoke.py"], True),
    (["<m>/tools/run-gates.sh"], True),
    (["<m>/THIRD-PARTY-LICENSES.md"], True),
    ([".github/workflows/native-<m>.yml"], True),
    (["<m>/docs/building.md", "<m>/src/x.c"], True),
    (["<m>/docs/building.md"], False),
    (["<m>/docs/shot.png"], False),
    (["<m>/README.md"], False),
    (["<m>/CLAUDE.md", "<m>/CHANGELOG.md"], False),
    (["<m>/examples/notes.md"], False),
    (["docs/WORK-PLAN.md"], False),
    (["othermember/src/x.c"], False),
]

# Fixture: the patterns before 2026-11-16 started on every change to the
# member, docs included; the evaluator must say so.
old = ["<m>/**", ".github/workflows/native-<m>.yml"]
if not (starts([p.replace("<m>", "enetxt") for p in old], ["enetxt/docs/a.md"])
        and not starts([p.replace("<m>", "enetxt") for p in old], ["docs/a.md"])):
    sys.exit("FAIL: the evaluator does not read the old patterns as GitHub did")

lanes = sorted(glob.glob(os.path.join(WF, "native-*.yml")))
if not lanes:
    sys.exit("FAIL: no native-<member>.yml lanes")
awk = publisher_awk() if shutil.which("awk") else None
if awk is None:
    print("SKIP: no awk here; the publisher's half is not run")

for path in lanes:
    member = re.search(r"native-(\w+)\.yml$", path).group(1)
    with open(path, encoding="utf-8") as f:
        blocks = paths_blocks(f.read())
    if len(blocks) != 2:
        fail("%s: expected two paths: lists (pull_request, push), found %d"
             % (os.path.basename(path), len(blocks)))
        continue
    if blocks[0] != blocks[1]:
        fail("%s: pull_request and push list different paths" % os.path.basename(path))
    for files, want in CASES:
        files = [f.replace("<m>", member) for f in files]
        got = starts(blocks[0], files)
        if got != want:
            fail("%s: %s %s the lane, expected %s" % (member, files,
                 "starts" if got else "does not start", want))
        if awk is not None and awk_starts(awk, member, files) != want:
            fail("%s: the publisher reads %s as %s, the lane as %s"
                 % (member, files, not want, want))

if failures:
    sys.exit("%d failure(s)" % len(failures))
print("test-native-lane-paths: OK (%d lanes x %d changes, lane filter and publisher agree)"
      % (len(lanes), len(CASES)))
