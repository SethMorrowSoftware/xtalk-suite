#!/usr/bin/env python3
"""check-member-standalone.py - every member is ready to be its own repository,
held as a property of the TREE rather than of one cleanup pass.

WHY THIS EXISTS. On 2026-09-21 the first member (archivext) left the suite
for a repository of its own, and what it took with it was the directory as
it stood: a README whose links climbed into the suite's docs/, no
.gitignore, a .github/ that had never been written, and gates whose only
runner was the suite's tools/build-all.sh. Preparing the other eleven by
hand is one pass; keeping them prepared while the tree keeps changing is
this gate, in the shape the ui-kit gate gave "every demo is a kit adopter":
a rule the build refuses to let rot.

WHAT IT CHECKS, per member in tools/member-registry.py:

  1. THE KIT. README.md, LICENSE, CLAUDE.md, .gitignore, tools/run-gates.sh
     (executable), tools/check-livecodescript.py, .github/workflows/gates.yml
     (and native.yml for a native member), and .gitattributes when the
     member commits binary or media files - because git's diff/merge
     heuristics on a .so are a property the suite root pinned and the
     member's own repository would otherwise lose.
  2. NO LINK CLIMBS OUT. A markdown link whose target resolves outside the
     member directory (`../../docs/README.md`, `../torrentxt/`) renders as a
     404 the day the member is its own repository. Suite-level and sibling
     references are written as absolute URLs (tools/sync-member-readmes.py
     explains where each kind resolves), so this refuses the relative form.
  3. NO TOOL CLIMBS OUT EXCEPT THROUGH THE SIBLING HELPER. A script under
     tools/ or tests/ that computes the suite root (`os.path.dirname(MEMBER)`,
     `"..", ".."`, `parent.parent.parent`) must define `def sibling(` - the
     one declared, overridable way to reach a sibling member (XTALK_SIBLINGS
     / XTALK_SIBLING_<NAME>, docs/MEMBER-REPO-SPLIT.md). A raw climb is a
     FileNotFoundError traceback in a standalone checkout.
  4. EVERY GATE FILE IS RUN. Each check-*.py, test-*.py, *-kat.py,
     *-fuzz.py, sync-*.py, export-*.py and audit-*.py under tools/, and
     each *golden*.py / *_test.py under tests/, must be named by the
     member's tools/run-gates.sh - or carry a written reason in EXEMPT
     below. A gate file no script runs is this tree's recorded failure
     shape (check-doc-anchors.py sat uninvoked for weeks; box2dxt's
     sync-embedded-kit.py --check was "in CI" in five places and in zero
     workflows), and a stale exemption is refused so a renamed file cannot
     leave a permanent excuse behind. "Named" means named in the runner's
     CODE: until 2026-09-22 a mention in a comment counted, so a runner
     whose only trace of a gate was "# check-x.py is retired" passed this
     check about a gate it never ran - the very shape the check exists to
     refuse, one level up. No member had that shape when it was closed.
  5. THE REGISTRY AND THE TREE AGREE. A member-shaped directory (CLAUDE.md +
     tools/check-livecodescript.py) that the registry does not list, or a
     registry row whose directory is gone, fails - the archivext lesson one
     level up: thirteen registries named a member that no longer existed.

The generated-copy questions (are the workflows and the README section
current?) belong to their generators' --check and are not repeated here.

    python3 tools/check-member-standalone.py            # the gate
    python3 tools/test-member-standalone.py             # its fixtures

Exit 0 = every member is ready; 1 = the problems are listed.
"""

import fnmatch
import importlib.util
import os
import re
import stat
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


REG = _load("member_registry", os.path.join(HERE, "member-registry.py"))

BINARY_EXT = {".so", ".dll", ".dylib", ".exp", ".png", ".jpg", ".jpeg",
              ".gif", ".wav", ".mp3", ".ogg", ".zip", ".ttf", ".otf"}

# Files under tools/ and tests/ that LOOK like gates by name and are not, each
# with the reason. Keyed by member-relative path; a key whose file is gone
# fails the gate.
EXEMPT = {
    "coinxt/tools/verify-independent-decoder.py":
        "a one-off verifier run by hand when the independent decoder is "
        "re-derived; its docstring says it is not a build gate",
}

GATE_TOOL_RE = re.compile(r"^(check-.*|test-.*|.*-kat|.*-fuzz|sync-.*|export-.*|audit-.*)\.py$")
GATE_TEST_RE = re.compile(r"^(.*golden.*|.*_test)\.py$")

LINK_RE = re.compile(r"\]\(([^)\s]+)\)")
CLIMB_RE = re.compile(r"os\.path\.dirname\(MEMBER\)|\"\.\.\",\s*\"\.\.\"|"
                      r"'\.\.',\s*'\.\.'|parent\.parent\.parent|"
                      r"\bSUITE\s*=")


def member_shaped(path):
    return (os.path.isfile(os.path.join(path, "CLAUDE.md")) and
            os.path.isfile(os.path.join(path, "tools", "check-livecodescript.py")))


def commits_binaries(mpath):
    for dirpath, dirnames, filenames in os.walk(mpath):
        dirnames[:] = [d for d in dirnames if d not in (".git", "build")]
        for f in filenames:
            if os.path.splitext(f)[1].lower() in BINARY_EXT:
                return True
    return False


def check_kit(mpath, m, problems):
    need = ["README.md", "LICENSE", "CLAUDE.md", ".gitignore",
            os.path.join("tools", "run-gates.sh"),
            os.path.join("tools", "check-livecodescript.py"),
            os.path.join(".github", "workflows", "gates.yml")]
    if m.native:
        need.append(os.path.join(".github", "workflows", "native.yml"))
    if commits_binaries(mpath):
        need.append(".gitattributes")
    for rel in need:
        p = os.path.join(mpath, rel)
        if not os.path.isfile(p):
            problems.append("%s/%s is missing" % (m.name, rel.replace(os.sep, "/")))
    rg = os.path.join(mpath, "tools", "run-gates.sh")
    if os.path.isfile(rg) and not os.stat(rg).st_mode & stat.S_IXUSR:
        problems.append("%s/tools/run-gates.sh is not executable" % m.name)


def check_links(mpath, m, problems):
    for dirpath, dirnames, filenames in os.walk(mpath):
        dirnames[:] = [d for d in dirnames if d not in (".git", "build")]
        for f in filenames:
            if not f.endswith(".md"):
                continue
            path = os.path.join(dirpath, f)
            with open(path, encoding="utf-8", errors="replace") as fh:
                for n, line in enumerate(fh, 1):
                    for target in LINK_RE.findall(line):
                        if not target.startswith("../"):
                            continue
                        t = target.split("#", 1)[0]
                        resolved = os.path.normpath(os.path.join(dirpath, t))
                        if not (resolved == mpath or
                                resolved.startswith(mpath + os.sep)):
                            problems.append(
                                "%s:%d: link %s climbs out of the member "
                                "(resolves to %s) - use the absolute URL"
                                % (os.path.relpath(path, ROOT), n, target,
                                   os.path.relpath(resolved, ROOT)))


def check_tools_climb(mpath, m, problems):
    for sub in ("tools", "tests"):
        d = os.path.join(mpath, sub)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not f.endswith(".py"):
                continue
            path = os.path.join(d, f)
            with open(path, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            code = "\n".join(l for l in text.split("\n")
                             if not l.lstrip().startswith("#"))
            if CLIMB_RE.search(code) and "def sibling(" not in code:
                problems.append(
                    "%s/%s/%s climbs to the suite root without a sibling() "
                    "helper (XTALK_SIBLINGS / XTALK_SIBLING_<NAME>, "
                    "docs/MEMBER-REPO-SPLIT.md)" % (m.name, sub, f))


def _code_of(script):
    """The runner with its comments removed - whole-line comments and a
    trailing ` # ...` - because a gate named only in a comment is a gate the
    runner does not run. A `#` not preceded by whitespace (`${#arr[@]}`) is
    shell, not a comment, and stays."""
    out = []
    for line in script.split("\n"):
        if line.lstrip().startswith("#"):
            continue
        out.append(re.split(r"\s#", line, 1)[0])
    return "\n".join(out)


def check_gates_named(mpath, m, problems):
    rg = os.path.join(mpath, "tools", "run-gates.sh")
    if not os.path.isfile(rg):
        return   # already reported by check_kit
    with open(rg, encoding="utf-8", errors="replace") as fh:
        script = _code_of(fh.read())
    # A runner may name a gate by GLOB - `for rel in tests/*golden*.py` is
    # the convention build-all.sh set, so a new golden is covered with no
    # edit - and a glob that matches the file counts as naming it.
    globs = [tok.strip("\"'") for tok in re.split(r"[\s;()]+", script)
             if "*" in tok]
    for sub, pat in (("tools", GATE_TOOL_RE), ("tests", GATE_TEST_RE)):
        d = os.path.join(mpath, sub)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if not pat.match(f) or f == "run-gates.sh":
                continue
            key = "%s/%s/%s" % (m.name, sub, f)
            if key in EXEMPT:
                continue
            rel = "%s/%s" % (sub, f)
            named = f in script or any(fnmatch.fnmatch(rel, g) for g in globs)
            if not named:
                problems.append(
                    "%s is a gate file that %s/tools/run-gates.sh never "
                    "names - run it there, or record why not in EXEMPT"
                    % (key, m.name))
    for key in EXEMPT:
        if key.startswith(m.name + "/") and not os.path.isfile(os.path.join(ROOT, key)):
            problems.append("EXEMPT names %s, which does not exist - remove "
                            "the stale exemption" % key)


def check_member(mpath, m, problems):
    """Every per-member check, over one directory. The fixture test drives
    this on synthetic trees, so it must take its inputs rather than read
    the registry."""
    check_kit(mpath, m, problems)
    check_links(mpath, m, problems)
    check_tools_climb(mpath, m, problems)
    check_gates_named(mpath, m, problems)


def check_registry(problems):
    listed = set(m.name for m in REG.MEMBERS)
    for m in REG.MEMBERS:
        if not os.path.isdir(m.path):
            problems.append("tools/member-registry.py lists %s, which does "
                            "not exist - a member that leaves takes its row "
                            "with it" % m.name)
    for name in sorted(os.listdir(ROOT)):
        p = os.path.join(ROOT, name)
        if os.path.isdir(p) and member_shaped(p) and name not in listed:
            problems.append("%s/ is member-shaped and tools/member-registry.py "
                            "does not list it - the split tooling cannot see "
                            "it" % name)


def main(argv):
    problems = []
    check_registry(problems)
    n = 0
    for m in REG.MEMBERS:
        if not os.path.isdir(m.path):
            continue
        n += 1
        check_member(m.path, m, problems)
    if problems:
        print("check-member-standalone: %d problem(s)" % len(problems))
        for p in problems:
            print("  - " + p)
        return 1
    print("check-member-standalone: OK (%d member(s) carry the standalone kit, "
          "no link or tool climbs out of its member, and every gate file is "
          "named by its member's tools/run-gates.sh)" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
