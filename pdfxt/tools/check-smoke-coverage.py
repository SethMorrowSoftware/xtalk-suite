#!/usr/bin/env python3
"""check-smoke-coverage.py - tests/smoke_test.c against src/pdfium_shim.c.

The smoke test is the only thing that RUNS the shim on every platform (and
under ASan/UBSan), so an export it never enters is an export nothing has run.
This gate holds two things, both derived from the shim's own LC_API
definitions and never from a list kept by hand:

  1. the declaration block in the smoke test (between the DECLARATIONS
     markers) is exactly the shim's exports, signature for signature - a test
     that declares `int f(int)` over a shim that defines `double f(int)`
     links, runs and reads garbage;
  2. every export is CALLED by the test body: named, followed by `(`,
     outside the declaration block, outside comments and outside string
     literals. A declaration is not a call (suite root CLAUDE.md, the
     box2dxt lesson: grep once counted six `extern`-declared, never-called
     exports as covered).

    python3 tools/check-smoke-coverage.py           # the gate
    python3 tools/check-smoke-coverage.py --write   # regenerate the block

Exit status: 0 held, 1 a difference (each named), 2 the gate could not read
its inputs (a blind gate must not print OK).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHIM = os.path.join(ROOT, "src", "pdfium_shim.c")
SMOKE = os.path.join(ROOT, "tests", "smoke_test.c")

BEGIN = "/* >>> BEGIN DECLARATIONS (generated: tools/check-smoke-coverage.py --write) >>> */"
END = "/* <<< END DECLARATIONS <<< */"
# Fewer exports than this means the parser went blind, not that the shim shrank.
MIN_EXPORTS = 30


def strip_c(text, keep_strings=False):
    """C source with comments (and, unless kept, string and character
    literals) blanked, by a scanner that knows which state it is in: a `//`
    inside a string is not a comment and a quote inside a comment opens
    nothing."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        two = text[i:i + 2]
        if two == "/*":
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
        elif two == "//":
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c:
                j += 2 if text[j] == "\\" else 1
            j = min(j + 1, n)
            out.append(text[i:j] if keep_strings else c + " " * (j - i - 2) + c)
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def exports(shim_text):
    """[(name, declaration)] for every LC_API definition, in file order."""
    found = []
    code = strip_c(shim_text)
    for m in re.finditer(r"^LC_API\s+([^;{]*?\))\s*\{", code, re.M):
        decl = " ".join(m.group(1).split())
        name = re.search(r"(\w+)\s*\(", decl)
        if name:
            found.append((name.group(1), decl + ";"))
    return found


def block_of(smoke_text):
    """(start, end) offsets of the text between the markers, or None."""
    a = smoke_text.find(BEGIN)
    b = smoke_text.find(END)
    if a < 0 or b < 0 or b < a or smoke_text.count(BEGIN) != 1 or smoke_text.count(END) != 1:
        return None
    return a + len(BEGIN), b


def check(shim_text, smoke_text):
    """(problems, exports) - problems empty when the test covers the shim."""
    problems = []
    exps = exports(shim_text)
    if len(exps) < MIN_EXPORTS:
        return ["only %d LC_API exports read from the shim (at least %d expected): "
                "the gate cannot read it" % (len(exps), MIN_EXPORTS)], exps
    names = [n for n, _ in exps]
    for n in sorted(set(names)):
        if names.count(n) > 1:
            problems.append("%s is defined %d times in the shim" % (n, names.count(n)))
        if not n.startswith("pdx_"):
            problems.append("%s is exported without the pdx_ prefix" % n)
    span = block_of(smoke_text)
    if span is None:
        return problems + ["tests/smoke_test.c has no single DECLARATIONS block (both markers, once each, in order)"], exps
    want = "\n" + "\n".join(d for _, d in exps) + "\n"
    have = smoke_text[span[0]:span[1]]
    if have != want:
        have_lines = set(l for l in have.split("\n") if l.strip())
        want_lines = set(l for l in want.split("\n") if l.strip())
        for l in sorted(want_lines - have_lines):
            problems.append("the declaration block lacks: %s" % l)
        for l in sorted(have_lines - want_lines):
            problems.append("the declaration block has a line the shim does not define: %s" % l)
        if have_lines == want_lines:
            problems.append("the declaration block is not in the shim's order")
        problems.append("regenerate it: python3 tools/check-smoke-coverage.py --write")
    body = strip_c(smoke_text[:span[0]] + smoke_text[span[1]:])
    for n in names:
        if not re.search(r"\b%s\s*\(" % re.escape(n), body):
            problems.append("%s is never called by tests/smoke_test.c (a declaration is not a call)" % n)
    return problems, exps


def main(argv):
    try:
        shim_text = open(SHIM, encoding="utf-8").read()
        smoke_text = open(SMOKE, encoding="utf-8").read()
    except OSError as e:
        print("check-smoke-coverage: cannot read its inputs: %s" % e)
        return 2
    if "--write" in argv:
        span = block_of(smoke_text)
        exps = exports(shim_text)
        if span is None or len(exps) < MIN_EXPORTS:
            print("check-smoke-coverage: cannot write: the markers or the exports were not found")
            return 2
        new = smoke_text[:span[0]] + "\n" + "\n".join(d for _, d in exps) + "\n" + smoke_text[span[1]:]
        if new != smoke_text:
            with open(SMOKE, "w", encoding="utf-8", newline="\n") as f:
                f.write(new)
        print("check-smoke-coverage: wrote the declaration block (%d exports)" % len(exps))
        return 0
    problems, exps = check(shim_text, smoke_text)
    if problems:
        for p in problems:
            print("FAIL " + p)
        print("check-smoke-coverage: FAILED (%d problems)" % len(problems))
        return 1
    print("check-smoke-coverage: OK (%d LC_API exports, each declared as the shim defines it "
          "and each called by tests/smoke_test.c)" % len(exps))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
