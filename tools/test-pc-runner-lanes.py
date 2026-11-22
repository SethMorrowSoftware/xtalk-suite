#!/usr/bin/env python3
"""test-pc-runner-lanes.py - what may run on the maintainer's own PCs, and
that it would work there.

Since 2026-11-21 some Linux and Windows lanes of the native-<member>.yml
workflows can run on self-hosted runners on the maintainer's two PCs
(docs/PC-RUNNERS.md), to take load off the account's GitHub-hosted queue.
A self-hosted runner on a PUBLIC repository runs whatever a workflow sends
it, so the routing is the security boundary, and this test holds it as
written:

  1. Only native-<member>.yml routes anything. No other workflow (releases,
     publishing, pages, the gates) names a self-hosted label.
  2. A routed job's runs-on is one of the two canonical expressions below,
     character for character. Both send a job to a PC ONLY when the
     repository variable for that PC is 'on' AND the run is this
     repository's own (a push, a dispatch, or a pull request whose head is
     this repository): a pull request from a fork, and every other event,
     falls back to the GitHub-hosted label the job had before.
  3. Only matrix rows that say `pc: linux` (os ubuntu-24.04, no container)
     or `pc: windows` (os windows-2025) are routed, and a job that routes
     has at least one such row.
  4. A routed job uses no job container, no service containers and no
     `docker` (the PC's runner account has no Docker), and a Windows-routed
     row runs no step that needs vcpkg, Chocolatey or ilammy/msvc-dev-cmd
     (the Windows PC has Visual Studio Build Tools and nothing more).
  5. Every `sudo` line a Linux-routed row would run is fed to the REAL
     tools/pc-runners/sudo (the stand-in the PC's jobs get) with a fake
     dpkg that knows exactly the PACKAGES of setup-linux-runner.sh: the
     line must be accepted, so a lane that starts installing something the
     PC lacks fails HERE, not on the PC.

Fixtures run first and must each be refused: a routing without the fork
guard, one without its switch, a `pc: linux` row in a container, a routed
lane installing a package the PC lacks, a self-hosted label in
release-binaries.yml, and a sudo the stand-in must refuse.

No PyYAML (the gates' Python has none): workflows are read by a small
indentation parser for the subset these files use, and a parse it cannot
make is a failure.

USAGE
    python3 tools/test-pc-runner-lanes.py
"""

import glob
import os
import re
import shlex
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHIM = os.path.join(HERE, "pc-runners", "sudo")
SETUP = os.path.join(HERE, "pc-runners", "setup-linux-runner.sh")

GUARD = ("(github.event_name == 'push' || github.event_name == 'workflow_dispatch'"
         " || (github.event_name == 'pull_request' && github.event.pull_request.head.repo.full_name == github.repository))")
LIN = "fromJSON('[\"self-hosted\",\"Linux\",\"X64\",\"seth-pc\"]')"
WIN = "fromJSON('[\"self-hosted\",\"Windows\",\"X64\",\"seth-pc\"]')"
MATRIX_RO = ("${{ (" + GUARD + " && ((matrix.pc == 'linux' && vars.PC_RUNNERS_LINUX == 'on' && "
             + LIN + ") || (matrix.pc == 'windows' && vars.PC_RUNNERS_WINDOWS == 'on' && "
             + WIN + "))) || matrix.os }}")
STATIC_RO = ("${{ (vars.PC_RUNNERS_LINUX == 'on' && " + GUARD + " && " + LIN
             + ") || 'ubuntu-24.04' }}")
WINDOWS_ONLY_TOOLS = ("vcpkg", "VCPKG_INSTALLATION_ROOT", "choco ", "ilammy/msvc-dev-cmd")


# ---------------------------------------------------------------- a YAML subset

class ParseError(Exception):
    pass


def _scalar(text):
    text = text.strip()
    if len(text) >= 2 and text[0] == text[-1] and text[0] in "'\"":
        body = text[1:-1]
        return body.replace("''", "'") if text[0] == "'" else body
    return text


def _strip_comment(line):
    """A comment starts at ' #' outside quotes."""
    q = None
    for i, c in enumerate(line):
        if q:
            if c == q:
                q = None
        elif c in "'\"":
            q = c
        elif c == "#" and (i == 0 or line[i - 1] in " \t"):
            return line[:i].rstrip()
    return line.rstrip()


def parse_yaml(text):
    """Maps, lists and block scalars, as the workflows here write them."""
    raw = text.split("\n")
    lines = []                      # (indent, content, raw index)
    i = 0
    while i < len(raw):
        line = raw[i]
        stripped = _strip_comment(line)
        if not stripped.strip():
            i += 1
            continue
        indent = len(stripped) - len(stripped.lstrip(" "))
        lines.append((indent, stripped.strip(), i))
        # a block scalar swallows every following line indented deeper
        if re.search(r":\s*[|>][-+]?$", stripped) or re.match(r"^-\s*[|>][-+]?$", stripped.strip()):
            j = i + 1
            block = []
            while j < len(raw) and (not raw[j].strip()
                                    or len(raw[j]) - len(raw[j].lstrip(" ")) > indent):
                block.append(raw[j])
                j += 1
            lines[-1] = (indent, stripped.strip(), i, "\n".join(block))
            i = j
            continue
        i += 1

    pos = 0

    def block_text(entry):
        body = entry[3].split("\n")
        ind = min((len(b) - len(b.lstrip(" ")) for b in body if b.strip()), default=0)
        return "\n".join(b[ind:] for b in body).strip("\n") + "\n"

    def parse_node(indent):
        nonlocal pos
        if pos >= len(lines):
            return None
        if lines[pos][1].startswith("- ") or lines[pos][1] == "-":
            return parse_list(lines[pos][0])
        return parse_map(lines[pos][0])

    def parse_value(entry, rest, indent):
        nonlocal pos
        if len(entry) == 4 and re.match(r"^[|>][-+]?$", rest):
            return block_text(entry)
        if rest == "":
            if pos < len(lines) and lines[pos][0] > indent:
                return parse_node(lines[pos][0])
            if pos < len(lines) and lines[pos][0] == indent and lines[pos][1].startswith("- "):
                return parse_list(indent)
            return None
        return _scalar(rest)

    def parse_map(indent):
        nonlocal pos
        out = {}
        while pos < len(lines) and lines[pos][0] == indent and not lines[pos][1].startswith("- "):
            entry = lines[pos]
            m = re.match(r"^(\"[^\"]*\"|'[^']*'|[^:]+?):(?:\s+(.*)|$)", entry[1])
            if not m:
                raise ParseError("line %d: not a key: %r" % (entry[2] + 1, entry[1]))
            key = _scalar(m.group(1))
            pos += 1
            out[key] = parse_value(entry, (m.group(2) or "").strip(), indent)
        if pos < len(lines) and lines[pos][0] > indent:
            raise ParseError("line %d: unexpected indent" % (lines[pos][2] + 1))
        return out

    def parse_list(indent):
        nonlocal pos
        out = []
        while pos < len(lines) and lines[pos][0] == indent and (lines[pos][1].startswith("- ")
                                                               or lines[pos][1] == "-"):
            entry = lines[pos]
            item = entry[1][1:].strip()
            if re.match(r"^(\"[^\"]*\"|'[^']*'|[A-Za-z0-9_.-]+):(\s|$)", item):
                # "- key: value" opens a map whose keys sit at indent + 2
                sub_indent = indent + 2
                lines[pos] = (sub_indent, item, entry[2]) + tuple(entry[3:])
                out.append(parse_map(sub_indent))
            else:
                pos += 1
                out.append(parse_value(entry, item, indent))
        return out

    result = parse_node(0)
    if pos != len(lines):
        raise ParseError("line %d: not parsed" % (lines[pos][2] + 1))
    return result


# ---------------------------------------------------------------- the checks

def _if_runs(cond, row):
    """Whether a step's `if:` lets a matrix row run it. Only the forms the
    lanes use are decided; anything else counts as RUNNING (the safe side
    for a check that asks what a row would do)."""
    if cond is None:
        return True
    c = cond.strip()
    if c.startswith("${{") and c.endswith("}}"):
        c = c[3:-2].strip()
    if c in ("always()", "success()", "!cancelled()"):
        return True
    m = re.fullmatch(r"matrix\.(\w+)\s*(==|!=)\s*'([^']*)'", c)
    if m:
        eq = str(row.get(m.group(1), "")) == m.group(3)
        return eq if m.group(2) == "==" else not eq
    m = re.fullmatch(r"(!?)matrix\.(\w+)", c)
    if m:
        v = row.get(m.group(2))
        truthy = v not in (None, "", "false", False)
        return not truthy if m.group(1) else truthy
    m = re.fullmatch(r"startsWith\(matrix\.(\w+),\s*'([^']*)'\)", c)
    if m:
        return str(row.get(m.group(1), "")).startswith(m.group(2))
    m = re.fullmatch(r"runner\.os\s*(==|!=)\s*'(\w+)'", c)
    if m:
        os_name = {"linux": "Linux", "windows": "Windows"}[row["pc"]]
        return (os_name == m.group(2)) == (m.group(1) == "==")
    return True


def sudo_commands(run):
    """Every `sudo ...` command a run block executes, as argument lists."""
    text = re.sub(r"\\\n\s*", " ", run)
    cmds = []
    for line in text.split("\n"):
        line = _strip_comment(line).strip()
        for seg in re.split(r"&&|\|\||;|\|", line):
            seg = seg.strip()
            if seg.startswith("sudo "):
                cmds.append(shlex.split(seg)[1:])
    return cmds


def setup_packages(setup_text):
    m = re.search(r"^PACKAGES=\((.*?)^\)", setup_text, re.S | re.M)
    if not m:
        raise ParseError("setup-linux-runner.sh: no PACKAGES=( ... ) list")
    return set(w for line in m.group(1).split("\n") for w in _strip_comment(line).split())


# What one job leaves must never reach the next (review of PR 209,
# 2026-11-22): coinxt's 32-bit pack row writes a `gcc -m32` cc into
# $HOME/bin and the pack rows build drivers in /tmp. On GitHub's machines
# both die with the machine; on the PC each runner needs its own HOME and
# /tmp, emptied by both hooks, and the stand-in sudo and the hooks must sit
# where a job cannot write.
ISOLATION = (
    ("each runner its own /tmp", r"^PrivateTmp=yes$"),
    ("each runner its own HOME", r"^Environment=HOME=\$dir/_home$"),
    ("the stand-in sudo first on PATH, from a root-owned folder",
     r"^printf '%s\\n' \"\$OPT/bin:"),
    ("the shim and hooks root-owned", r'^install -d -m 755 -o root -g root "\$OPT" "\$OPT/bin" "\$OPT/hooks"$'),
    ("job-started empties HOME and /tmp",
     r'cat > "\$OPT/hooks/job-started\.sh" <<EOF\n(?:(?!^EOF$).*\n)*"\$OPT/hooks/clean\.sh"\nEOF'),
    ("job-completed empties HOME and /tmp",
     r'cat > "\$OPT/hooks/job-completed\.sh" <<EOF\n(?:(?!^EOF$).*\n)*"\$OPT/hooks/clean\.sh"\nEOF'),
    ("clean.sh empties the runner's HOME", r'find "\$HOME" -mindepth 1 -delete'),
    ("clean.sh empties the job's /tmp", r"find /tmp /var/tmp -mindepth 1 -user ghrunner -delete"),
)


def isolation_problems(setup_text):
    return ["setup-linux-runner.sh: missing %s" % what
            for what, rx in ISOLATION if not re.search(rx, setup_text, re.M)]


class Shim:
    """The real stand-in sudo, over a fake dpkg that knows `packages`."""

    def __init__(self, packages):
        self.dir = tempfile.mkdtemp(prefix="pc-runner-shim-")
        with open(os.path.join(self.dir, "installed"), "w") as f:
            f.write("\n".join(sorted(packages)) + "\n")
        with open(os.path.join(self.dir, "dpkg-query"), "w") as f:
            f.write('#!/bin/sh\nfor pkg in "$@"; do :; done\n'
                    'grep -qxF "$pkg" "%s/installed" && printf "install ok installed" && exit 0\n'
                    'exit 1\n' % self.dir)
        with open(os.path.join(self.dir, "dpkg"), "w") as f:
            f.write('#!/bin/sh\n[ "$1" = --print-foreign-architectures ] && echo i386\n')
        for n in ("dpkg-query", "dpkg"):
            os.chmod(os.path.join(self.dir, n), 0o755)
        self.bits = os.path.join(self.dir, "mmap_rnd_bits")
        with open(self.bits, "w") as f:
            f.write("28\n")

    def run(self, args):
        env = dict(os.environ, PATH=self.dir + os.pathsep + os.environ.get("PATH", ""),
                   PC_RUNNER_MMAP_RND_BITS_FILE=self.bits)
        p = subprocess.run(["bash", SHIM] + args, env=env, capture_output=True, text=True)
        return p.returncode, (p.stdout + p.stderr).strip()


def check(workflows, shim):
    """workflows: {path: text}. Returns a list of problems."""
    problems = []
    for path, text in sorted(workflows.items()):
        base = os.path.basename(path)
        mentions = "self-hosted" in text or "seth-pc" in text
        if mentions and not re.fullmatch(r"native-[a-z0-9]+\.yml", base):
            problems.append("%s: only native-<member>.yml may name a self-hosted runner" % base)
            continue
        if not mentions:
            continue
        try:
            doc = parse_yaml(text)
        except ParseError as e:
            problems.append("%s: %s" % (base, e))
            continue
        for jname, job in (doc.get("jobs") or {}).items():
            where = "%s job %s" % (base, jname)
            ro = job.get("runs-on")
            matrix = ((job.get("strategy") or {}).get("matrix") or {})
            rows = matrix.get("include") if isinstance(matrix, dict) else None
            rows = rows if isinstance(rows, list) else []
            pc_rows = [r for r in rows if isinstance(r, dict) and "pc" in r]
            routed = isinstance(ro, str) and ("self-hosted" in ro or "seth-pc" in ro)
            if pc_rows and ro != MATRIX_RO:
                problems.append("%s: has `pc:` rows but runs-on is not the canonical routing" % where)
            if not routed:
                continue
            if ro == STATIC_RO:
                route_rows = [{"pc": "linux", "os": "ubuntu-24.04"}]
            elif ro == MATRIX_RO:
                if not pc_rows:
                    problems.append("%s: routes by matrix.pc but no row has `pc:`" % where)
                route_rows = pc_rows
            else:
                problems.append("%s: runs-on names a self-hosted runner but is not one of the "
                                "two canonical expressions (fork guard, switch, fallback)" % where)
                continue
            # `container: ${{ matrix.container }}` is empty on every row that may
            # be routed (rule 3 refuses a `pc:` row with a container)
            if job.get("container") and job.get("container") != "${{ matrix.container }}":
                problems.append("%s: a routed job may not use `container:`" % where)
            if job.get("services"):
                problems.append("%s: a routed job may not use `services:`" % where)
            for r in route_rows:
                rname = "%s row %s" % (where, r.get("name") or r.get("platform") or r.get("os"))
                if r["pc"] == "linux" and (r.get("os") != "ubuntu-24.04" or r.get("container")):
                    problems.append("%s: `pc: linux` needs os ubuntu-24.04 and no container" % rname)
                    continue
                if r["pc"] == "windows" and r.get("os") != "windows-2025":
                    problems.append("%s: `pc: windows` needs os windows-2025" % rname)
                    continue
                if r["pc"] not in ("linux", "windows"):
                    problems.append("%s: `pc:` must be linux or windows" % rname)
                    continue
                for step in job.get("steps") or []:
                    if not _if_runs(step.get("if"), r):
                        continue
                    run = step.get("run") or ""
                    uses = step.get("uses") or ""
                    if re.search(r"(^|\s)docker\s", run):
                        problems.append("%s: runs docker, which the PC runner has not" % rname)
                    if r["pc"] == "windows":
                        for tool in WINDOWS_ONLY_TOOLS:
                            if tool in run or tool in uses:
                                problems.append("%s: step %r needs %s, which the Windows PC has not"
                                                % (rname, step.get("name", ""), tool.strip()))
                    if r["pc"] == "linux":
                        for args in sudo_commands(run):
                            status, out = shim.run(args)
                            if status != 0:
                                problems.append("%s: the PC's sudo refuses `sudo %s`: %s"
                                                % (rname, " ".join(args), out.split("\n")[0]))
    return problems


# ---------------------------------------------------------------- fixtures

FIXTURE = """\
name: native fixturext
on:
  pull_request:
jobs:
  sanitize:
    name: sanitize
    runs-on: %(static)s
    steps:
      - uses: actions/checkout@v4
      - name: Acquire toolchain
        run: |
          sudo apt-get update
          sudo apt-get install -y g++ cmake ninja-build
  build-matrix:
    name: ${{ matrix.name }}
    strategy:
      matrix:
        include:
          - name: linux-x86
            os: ubuntu-24.04
            pc: linux
            acquire: linux32
          - name: macos
            os: macos-15
          - name: windows-x86_64
            os: windows-2025
            pc: windows
    runs-on: %(matrix)s
    steps:
      - name: 32-bit toolchain
        if: matrix.acquire == 'linux32'
        run: |
          sudo dpkg --add-architecture i386
          sudo apt-get update && sudo apt-get install -y gcc-multilib \\
            libssl-dev:i386
      - name: Rosetta
        if: startsWith(matrix.os, 'macos')
        run: sudo softwareupdate --install-rosetta --agree-to-license || true
      - name: Build
        shell: bash
        run: cmake --build build --parallel 4
"""


def fixtures(shim):
    good = FIXTURE % {"static": STATIC_RO, "matrix": MATRIX_RO}
    path = ".github/workflows/native-fixturext.yml"
    failures = []

    def expect(label, wf, refused):
        got = check(wf, shim)
        if bool(got) != refused:
            failures.append("fixture %r: expected %s, got %s" % (
                label, "a refusal" if refused else "no problem", got or "nothing"))

    expect("the canonical lane", {path: good}, False)
    expect("no fork guard", {path: good.replace(GUARD + " && ((", "((", 1)}, True)
    expect("no switch", {path: good.replace("vars.PC_RUNNERS_LINUX == 'on' && " + GUARD,
                                            GUARD, 1)}, True)
    expect("pc: linux in a container",
           {path: good.replace("            acquire: linux32",
                               "            acquire: linux32\n            container: quay.io/x", 1)}, True)
    expect("a job container",
           {path: good.replace("    runs-on: " + STATIC_RO,
                               "    runs-on: " + STATIC_RO + "\n    container: ubuntu:24.04", 1)}, True)
    expect("a package the PC lacks",
           {path: good.replace("ninja-build\n", "ninja-build libfrobnicate-dev\n", 1)}, True)
    expect("vcpkg on a Windows row",
           {path: good.replace("        run: cmake --build build --parallel 4",
                               "        run: vcpkg install openssl", 1)}, True)
    expect("a self-hosted release",
           {".github/workflows/release-binaries.yml":
            "jobs:\n  b:\n    runs-on: [self-hosted, seth-pc]\n"}, True)
    for args, ok in ((["apt-get", "update"], True),
                     (["DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", "cmake"], True),
                     (["sysctl", "-w", "vm.mmap_rnd_bits=28"], True),
                     (["sysctl", "-w", "vm.mmap_rnd_bits=27"], False),
                     (["rm", "-rf", "/"], False),
                     (["apt-get", "remove", "-y", "cmake"], False),
                     (["bash", "-c", "id"], False)):
        status, out = shim.run(args)
        if (status == 0) != ok:
            failures.append("the stand-in sudo %s `sudo %s`: %s" % (
                "refused" if ok else "accepted", " ".join(args), out))
    return failures


def main():
    with open(SETUP) as f:
        setup_text = f.read()
    packages = setup_packages(setup_text)
    shim = Shim(packages)
    failures = fixtures(shim)
    for what, rx in ISOLATION:          # each rule must see its own removal
        if not re.search(rx, setup_text, re.M):
            continue                    # reported below as missing
        broken = re.sub(rx, "", setup_text, flags=re.M)
        if not isolation_problems(broken):
            failures.append("isolation rule %r cannot see its own removal" % what)
    if failures:
        print("test-pc-runner-lanes: FIXTURES FAILED - the check cannot be trusted:")
        for x in failures:
            print("  " + x)
        return 1
    workflows = {}
    for p in sorted(glob.glob(os.path.join(ROOT, ".github", "workflows", "*.yml"))):
        with open(p) as f:
            workflows[os.path.relpath(p, ROOT)] = f.read()
    problems = isolation_problems(setup_text) + check(workflows, shim)
    routed = sum(1 for t in workflows.values() if "seth-pc" in t)
    if problems:
        print("test-pc-runner-lanes: FAIL")
        for x in problems:
            print("  " + x)
        return 1
    print("test-pc-runner-lanes: OK - fixtures refused as they must; %d workflow(s) "
          "route lanes to the PCs, every one guarded, switched and runnable there" % routed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
