#!/usr/bin/env python3
"""check-doc-anchors.py - an ANCHORED citation must still point at something.

WHY THIS GATE EXISTS
    `docs/OPEN-DECISIONS.md` opened with an attestation that every one of its 52
    `file:line` citations had been "re-verified against the tree on the compile
    date". On the compile date that was true. One day later six of them landed in
    unrelated prose: the brief for coinxt's Schnorr decision pointed at the punch
    list's summary paragraph, the riptide feed-retention brief pointed three
    sections short of the section it names, and the `cnx_memzero` citation landed
    on a comment about `use com.livecode.foreign`.

    Nothing was edited dishonestly. **A line number is a fact about a file's
    current shape**, and this tree reshapes faster than its documents are re-read.
    A brief whose evidence points at the wrong paragraph is worse than one with no
    citation, because the reader trusts it - and OPEN-DECISIONS' own recorded
    lesson (D-01) is that a brief is only as good as its evidence.

WHAT IT CHECKS - AND THE ONE THING IT REFUSES TO GUESS
    It fails on exactly one condition: an ANCHORED citation - `path` followed by
    ("some phrase") - whose phrase no longer appears in that file. An anchor is
    text that moves WITH the thing it names, so it survives every edit above it.
    That question has one right answer and no judgement in it.

    It does NOT try to validate bare `file:line` citations, and the first version
    of this gate is why. Run against every `path` in backticks it reported 93
    "broken" citations - and nearly all of them were the tree's own DOCUMENTED
    convention, not defects: a member's docs cite paths relative to THAT member's
    root (`tests/enet-selftest.livecodescript` inside `enetxt/docs/`), suite docs
    use bare basenames as shorthand (`build-all.sh`), dated records legitimately
    name files that have since been retired (`check-holdem-idioms.py`, retired in
    the 2026-08-15 checker union), and a forward-looking plan may name a file that
    does not exist YET (`tests/preflight.livecodescript`). Each is correct as
    written.

    check-handler-calls.py's docstring already states the rule this gate nearly
    broke: **a false alarm in a gate is worse than a missed one, because it
    teaches people to ignore the gate.** So the un-anchored citations are COUNTED
    and reported as UNVERIFIED - never as passed, and never as failed. Paying that
    count down by adding anchors is the work; overstating what was checked is the
    thing this gate exists to stop.

USAGE
    python3 tools/check-doc-anchors.py [-v]
    Exit 0 when every anchor resolves, 1 when any anchor is broken.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOCS = os.path.join(ROOT, "docs")

# `path/to/file.ext` or `path/to/file.ext:12-34`, optionally followed by an
# anchor: ("a phrase that moves with the thing it names").
CITE_RE = re.compile(
    r'`([A-Za-z0-9_./-]+\.(?:md|py|sh|livecodescript|lcb|c|h|cpp|yml|json))'
    r'(?::\d+(?:-\d+)?)?`'
    r'(?:\s*\(\s*"([^"]+)")?')


def resolve(path):
    """Repo-root-relative, docs/-relative, or a unique basename anywhere."""
    for cand in (os.path.join(ROOT, path), os.path.join(DOCS, path)):
        if os.path.isfile(cand):
            return cand
    base = os.path.basename(path)
    hits = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames
                       if d != ".git" and not d.startswith("build")]
        if base in filenames:
            hits.append(os.path.join(dirpath, base))
            if len(hits) > 1:
                return None          # ambiguous - cannot decide, so do not try
    return hits[0] if hits else None


def main(argv):
    verbose = "-v" in argv
    problems = []
    anchored = unanchored = 0

    for fn in sorted(os.listdir(DOCS)):
        if not fn.endswith(".md"):
            continue
        doc = os.path.join(DOCS, fn)
        for lineno, line in enumerate(
                open(doc, encoding="utf-8").read().splitlines(), 1):
            for m in CITE_RE.finditer(line):
                path, anchor = m.groups()
                if not anchor:
                    unanchored += 1
                    continue
                anchored += 1
                full = resolve(path)
                if full is None:
                    problems.append(
                        f"{fn}:{lineno}: anchored citation names '{path}', which "
                        f"does not resolve to exactly one file in this tree")
                    continue
                text = open(full, encoding="utf-8", errors="replace").read()
                if anchor not in text:
                    problems.append(
                        f"{fn}:{lineno}: anchor \"{anchor}\" no longer appears "
                        f"anywhere in {path} - the thing it named was renamed, "
                        f"reworded, or removed")
                elif verbose:
                    at = text[:text.index(anchor)].count("\n") + 1
                    print(f"  ok  {fn}:{lineno} -> {os.path.relpath(full, ROOT)}:{at}")

    if problems:
        for p in problems:
            print("check-doc-anchors: " + p)
        print(f"check-doc-anchors: {len(problems)} broken anchor(s)")
        return 1
    print(f"check-doc-anchors: OK ({anchored} anchor(s) re-resolved; "
          f"{unanchored} bare citation(s) NOT checked - see the docstring for "
          f"why guessing at those produces false alarms)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
