#!/usr/bin/env python3
"""test-member-standalone.py - fixtures for check-member-standalone.py.

A gate that has gone blind reports OK, and the discriminating test is what
makes the OK mean anything (the root CLAUDE.md's fixture-before-gate law).
This drives check_member() over synthetic member trees built in a temp
directory - the way the build will run it, not a hand-built input matching
the docstring - and requires each of its four checks to FIRE on the shape it
exists for and to stay QUIET on the clean shape beside it. It then requires
the real tree to be clean, so a regression in either direction is caught
here before the gate is trusted.

    python3 tools/test-member-standalone.py
"""

import importlib.util
import os
import shutil
import stat
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


GATE = _load("check_member_standalone",
             os.path.join(HERE, "check-member-standalone.py"))
REG = GATE.REG


def write(path, text, executable=False):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    if executable:
        os.chmod(path, os.stat(path).st_mode | stat.S_IXUSR)


def clean_member(base, name, native=False):
    """The minimal shape the gate accepts."""
    p = os.path.join(base, name)
    write(os.path.join(p, "README.md"), "# %s\n\nSee [the docs](docs/README.md).\n" % name)
    write(os.path.join(p, "LICENSE"), "MIT\n")
    write(os.path.join(p, "CLAUDE.md"), "# notes\n")
    write(os.path.join(p, ".gitignore"), "__pycache__/\n")
    write(os.path.join(p, "docs", "README.md"), "[up](../README.md)\n")
    write(os.path.join(p, "tools", "check-livecodescript.py"), "# checker\n")
    write(os.path.join(p, "tools", "check-thing.py"), "# a gate\n")
    write(os.path.join(p, "tools", "run-gates.sh"),
          "#!/usr/bin/env bash\npython3 tools/check-livecodescript.py\n"
          "python3 tools/check-thing.py\n", executable=True)
    write(os.path.join(p, ".github", "workflows", "gates.yml"), "name: gates\n")
    if native:
        write(os.path.join(p, ".github", "workflows", "native.yml"), "name: native\n")
    return p


class Row(object):
    def __init__(self, name, native):
        self.name = name
        self.native = native


def run(p, row):
    problems = []
    GATE.check_member(p, row, problems)
    return problems


CASES = []


def case(label, expect):
    def deco(fn):
        CASES.append((label, fn, expect))
        return fn
    return deco


@case("clean member is clean", None)
def _(base):
    return run(clean_member(base, "alpha"), Row("alpha", False))


@case("missing .gitignore fires", ".gitignore is missing")
def _(base):
    p = clean_member(base, "alpha")
    os.remove(os.path.join(p, ".gitignore"))
    return run(p, Row("alpha", False))


@case("native member without native.yml fires", "native.yml is missing")
def _(base):
    p = clean_member(base, "alpha")
    return run(p, Row("alpha", True))


@case("a committed .so without .gitattributes fires", ".gitattributes is missing")
def _(base):
    p = clean_member(base, "alpha")
    write(os.path.join(p, "src", "code", "x86_64-linux", "alpha.so"), "\0")
    return run(p, Row("alpha", False))


@case("a committed .so with .gitattributes is clean", None)
def _(base):
    p = clean_member(base, "alpha")
    write(os.path.join(p, "src", "code", "x86_64-linux", "alpha.so"), "\0")
    write(os.path.join(p, ".gitattributes"), "*.so binary\n")
    return run(p, Row("alpha", False))


@case("run-gates.sh not executable fires", "not executable")
def _(base):
    p = clean_member(base, "alpha")
    rg = os.path.join(p, "tools", "run-gates.sh")
    os.chmod(rg, os.stat(rg).st_mode & ~stat.S_IXUSR)
    return run(p, Row("alpha", False))


@case("a link climbing into the suite fires", "climbs out of the member")
def _(base):
    p = clean_member(base, "alpha")
    write(os.path.join(p, "docs", "README.md"),
          "[suite index](../../docs/README.md)\n")
    return run(p, Row("alpha", False))


@case("a link climbing to a sibling fires", "climbs out of the member")
def _(base):
    p = clean_member(base, "alpha")
    write(os.path.join(p, "README.md"), "[torrent](../torrentxt/)\n")
    return run(p, Row("alpha", False))


@case("a ../ link that stays inside the member is clean", None)
def _(base):
    p = clean_member(base, "alpha")
    write(os.path.join(p, "docs", "deep", "x.md"),
          "[up two](../../README.md#status) and [up](../README.md)\n")
    return run(p, Row("alpha", False))


@case("a tool computing the suite root without sibling() fires",
      "climbs to the suite root without a sibling() helper")
def _(base):
    p = clean_member(base, "alpha")
    write(os.path.join(p, "tools", "check-thing.py"),
          "import os\nHERE = os.path.dirname(os.path.abspath(__file__))\n"
          "MEMBER = os.path.dirname(HERE)\nSUITE = os.path.dirname(MEMBER)\n")
    return run(p, Row("alpha", False))


@case("the same tool with a sibling() helper is clean", None)
def _(base):
    p = clean_member(base, "alpha")
    write(os.path.join(p, "tools", "check-thing.py"),
          "import os\nHERE = os.path.dirname(os.path.abspath(__file__))\n"
          "MEMBER = os.path.dirname(HERE)\n"
          "def sibling(name):\n"
          "    return os.path.join(os.environ.get('XTALK_SIBLINGS') or "
          "os.path.dirname(MEMBER), name)\n")
    return run(p, Row("alpha", False))


@case("a climb inside a comment is not a climb", None)
def _(base):
    p = clean_member(base, "alpha")
    write(os.path.join(p, "tools", "check-thing.py"),
          "# the old code did SUITE = os.path.dirname(MEMBER)\nprint(1)\n")
    return run(p, Row("alpha", False))


@case("a gate file run-gates.sh never names fires", "never names")
def _(base):
    p = clean_member(base, "alpha")
    write(os.path.join(p, "tools", "wire-kat.py"), "# a KAT\n")
    return run(p, Row("alpha", False))


@case("a golden test run-gates.sh never names fires", "never names")
def _(base):
    p = clean_member(base, "alpha")
    write(os.path.join(p, "tests", "record_golden_test.py"), "# golden\n")
    return run(p, Row("alpha", False))


@case("a golden named by the tests/*golden*.py glob is clean", None)
def _(base):
    p = clean_member(base, "alpha")
    write(os.path.join(p, "tests", "record_golden_test.py"), "# golden\n")
    write(os.path.join(p, "tools", "run-gates.sh"),
          "#!/usr/bin/env bash\npython3 tools/check-livecodescript.py\n"
          "python3 tools/check-thing.py\n"
          "for rel in tests/*golden*.py; do python3 \"$rel\"; done\n",
          executable=True)
    return run(p, Row("alpha", False))


@case("a non-gate tool (package-extension.py) is not demanded", None)
def _(base):
    p = clean_member(base, "alpha")
    write(os.path.join(p, "tools", "package-extension.py"), "# packer\n")
    write(os.path.join(p, "tools", "alpha_reference.py"), "# oracle\n")
    return run(p, Row("alpha", False))


def main():
    failures = 0
    for label, fn, expect in CASES:
        base = tempfile.mkdtemp(prefix="member-standalone-")
        try:
            problems = fn(base)
        finally:
            shutil.rmtree(base, ignore_errors=True)
        if expect is None:
            ok = not problems
            detail = "; ".join(problems)
        else:
            ok = any(expect in p for p in problems)
            detail = "; ".join(problems) or "(no problems reported)"
        print("  %s %s" % ("ok  " if ok else "FAIL", label))
        if not ok:
            failures += 1
            print("       got: %s" % detail)
    # And the real tree, through the gate's own main: the fixtures prove
    # the checks discriminate; this proves the tree is clean by them.
    rc = GATE.main([])
    if rc != 0:
        failures += 1
        print("  FAIL the real tree is not clean by the gate")
    if failures:
        print("test-member-standalone: %d FAILURE(S) of %d case(s)"
              % (failures, len(CASES) + 1))
        return 1
    print("test-member-standalone: OK (%d fixture case(s) discriminate, "
          "and the real tree is clean)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
