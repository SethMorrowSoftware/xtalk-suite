#!/usr/bin/env python3
"""Docs gate (Phase 0): smart quotes, and the version the docs name.

1. The house style is straight quotes everywhere, including docs -- partly
   hygiene, partly self-defence: prose gets pasted into scripts and commit
   messages, and one curly quote that later drifts into a .livecodescript
   fails OXT compilation (gotcha 1). Scans every tracked .md file.

2. The front doors name the build they describe: CLAUDE.md's "Current:"
   line (kHeVersion, kHeHarnessV, kUIVersion, kHeEnvV) and the README's
   newest status heading ("**v<kHeVersion> (harness <kHeHarnessV>)").
   Both must agree with the constants in src/holdem.livecodescript, so a
   release that bumps the script and forgets its docs fails here instead of
   being found by a reader of the published repository (2026-11-14: the
   question "is the published example up to date?" was answered by hand).

`--selftest` runs the version check over mutated copies of the real docs
(a fixture before the gate: a blind check would still print OK).
Exit non-zero on any hit.
"""

import pathlib
import re
import sys

SMART_QUOTES = {0x2018, 0x2019, 0x201C, 0x201D}
CONSTANTS = ("kHeVersion", "kHeHarnessV", "kUIVersion", "kHeEnvV")


def script_constants(src_text):
    """The four version constants as the script declares them."""
    out = {}
    for name in CONSTANTS:
        m = re.search(r'^constant %s = "([^"]*)"' % name, src_text, re.M)
        if not m:
            raise SystemExit("FAIL  src/holdem.livecodescript declares no %s" % name)
        out[name] = m.group(1)
    return out


def version_problems(consts, claude_text, readme_text):
    """Every disagreement between the docs and the script, as text."""
    bad = []
    m = re.search(r"Current:\s*`kHeVersion`\s*([0-9.]+),\s*`kHeHarnessV`\s*(\d+),"
                  r"\s*`kUIVersion`\s*(\d+),\s*table protocol \(`kHeEnvV`\)\s*(\d+)",
                  claude_text)
    if not m:
        bad.append("CLAUDE.md: no 'Current: `kHeVersion` ..., `kHeHarnessV` ..., "
                   "`kUIVersion` ..., table protocol (`kHeEnvV`) ...' line")
    else:
        for name, got in zip(CONSTANTS, m.groups()):
            if got != consts[name]:
                bad.append("CLAUDE.md: Current names %s %s, the script declares %s"
                           % (name, got, consts[name]))
    # The README's status section opens with the newest build's heading.
    status = readme_text.split("## Status", 1)
    m = re.search(r"\*\*v([0-9.]+) \(harness (\d+)\)", status[1]) if len(status) == 2 else None
    if not m:
        bad.append("README.md: no '**v<version> (harness <n>)' heading under ## Status")
    else:
        if m.group(1) != consts["kHeVersion"]:
            bad.append("README.md: the newest status names v%s, the script declares kHeVersion %s"
                       % (m.group(1), consts["kHeVersion"]))
        if m.group(2) != consts["kHeHarnessV"]:
            bad.append("README.md: the newest status names harness %s, the script declares %s"
                       % (m.group(2), consts["kHeHarnessV"]))
    return bad


def selftest(root):
    consts = script_constants((root / "src" / "holdem.livecodescript").read_text(encoding="utf-8"))
    claude = (root / "CLAUDE.md").read_text(encoding="utf-8")
    readme = (root / "README.md").read_text(encoding="utf-8")
    fails = 0

    def expect(label, problems, want_hit):
        nonlocal fails
        if bool(problems) != want_hit:
            print("FAIL  selftest %s: %s" % (label, problems or "no problem found"))
            fails += 1
        else:
            print("ok    selftest %s" % label)

    expect("real docs agree", version_problems(consts, claude, readme), False)
    bumped = dict(consts, kHeVersion=consts["kHeVersion"] + ".1")
    expect("a kHeVersion bump without the docs", version_problems(bumped, claude, readme), True)
    bumped = dict(consts, kHeHarnessV=str(int(consts["kHeHarnessV"]) + 1))
    expect("a kHeHarnessV bump without the docs", version_problems(bumped, claude, readme), True)
    bumped = dict(consts, kUIVersion=str(int(consts["kUIVersion"]) + 1))
    expect("a kUIVersion bump without CLAUDE.md", version_problems(bumped, claude, readme), True)
    bumped = dict(consts, kHeEnvV=str(int(consts["kHeEnvV"]) + 1))
    expect("a kHeEnvV bump without CLAUDE.md", version_problems(bumped, claude, readme), True)
    expect("CLAUDE.md with no Current line",
           version_problems(consts, claude.replace("Current:", "Now:"), readme), True)
    expect("README with no status heading",
           version_problems(consts, claude, readme.replace("## Status", "## State")), True)
    # A stale heading ABOVE the current one is what a forgotten update looks like.
    stale = readme.replace("## Status\n", "## Status\n\n**v0.0.1 (harness 1), 2020-01-01.** old.\n", 1)
    expect("an older heading first under Status", version_problems(consts, claude, stale), True)
    if fails:
        print("FAILED -- %d docs selftest case(s)." % fails)
        return 1
    print("docs selftest: all cases behave.")
    return 0


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    if "--selftest" in sys.argv[1:]:
        return selftest(root)
    bad = 0
    for path in sorted(root.rglob("*.md")):
        if ".git" in path.parts:
            continue
        rel = path.relative_to(root)
        for lineno, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            hits = sorted({c for c in line if ord(c) in SMART_QUOTES})
            if hits:
                print("FAIL  %s:%d: smart quote(s) %s -- use straight ASCII"
                      % (rel, lineno, "".join(hits)))
                bad += 1
    consts = script_constants((root / "src" / "holdem.livecodescript").read_text(encoding="utf-8"))
    for problem in version_problems(consts,
                                    (root / "CLAUDE.md").read_text(encoding="utf-8"),
                                    (root / "README.md").read_text(encoding="utf-8")):
        print("FAIL  " + problem)
        bad += 1
    if bad:
        print("FAILED -- %d docs problem(s)." % bad)
        return 1
    print("All docs are smart-quote clean, and name holde-em %s, harness %s."
          % (consts["kHeVersion"], consts["kHeHarnessV"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
