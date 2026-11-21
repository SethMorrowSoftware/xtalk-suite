#!/usr/bin/env python3
"""check-smoke-coverage.py - tests/smoke_test.c and tests/fuzz_test.c against
src/render3d_shim.c (box3dxt's gate of the same name, for this member).

The smoke test is the only thing that RUNS the shim on every platform (and
under ASan/UBSan), so an export it never enters is an export nothing has run.
This gate holds, all derived from the shim's own LC_API definitions and never
from a list kept by hand:

  1. the declaration block of each test (between the SHIM DECLARATIONS
     markers) is exactly the shim's exports, signature for signature: a test
     that declares `int f(int)` over a shim that defines `double f(int)`
     links, runs and reads garbage;
  2. every export is CALLED by the smoke test's body: named outside the
     declaration block, comments and string literals (a declaration is not a
     call: the suite root CLAUDE.md's box2dxt lesson);
  3. the fuzz test's call table (between the FUZZ CALLS markers) has one
     generated thunk per export, so a new export is fuzzed the day it is
     written.

    python3 tools/check-smoke-coverage.py           # the gate
    python3 tools/check-smoke-coverage.py --write   # regenerate every block

Exit status: 0 held, 1 a difference (each named), 2 the gate could not read
its inputs (a blind gate must not print OK).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHIM = os.path.join(ROOT, "src", "render3d_shim.c")
SMOKE = os.path.join(ROOT, "tests", "smoke_test.c")
FUZZ = os.path.join(ROOT, "tests", "fuzz_test.c")

DECL_BEGIN = "/* >>> BEGIN SHIM DECLARATIONS (generated: tools/check-smoke-coverage.py --write) >>> */"
DECL_END = "/* <<< END SHIM DECLARATIONS <<< */"
FUZZ_BEGIN = "/* >>> BEGIN FUZZ CALLS (generated: tools/check-smoke-coverage.py --write) >>> */"
FUZZ_END = "/* <<< END FUZZ CALLS <<< */"

# Fewer exports than this means the scanner went blind, not that the library
# shrank: fail rather than print OK over nothing.
MIN_EXPORTS = 100

# The parameter kinds the fuzz thunks know how to make up. A new kind is a
# refusal here until the fuzz test learns it.
KINDS = {
    "int": "fz_int()",
    "double": "fz_num()",
    "const char *": "fz_text()",
    "const void *": "(const void *)fz_text()",
    "const unsigned char *": None,   # always paired with an int length
}


def strip_comments(text, blank_strings=False):
    """Cut /* */ and // comments with a string-state-aware scan; optionally
    blank the inside of string literals (a name in a label is not a call)."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"' or c == "'":
            quote = c
            out.append(c)
            i += 1
            while i < n and text[i] != quote:
                if text[i] == "\\" and i + 1 < n:
                    out.append("  " if blank_strings else text[i:i + 2])
                    i += 2
                    continue
                out.append(" " if blank_strings and text[i] != "\n" else text[i])
                i += 1
            if i < n:
                out.append(quote)
                i += 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("\n" * text.count("\n", i, j))
            i = j
        elif text.startswith("//", i):
            j = text.find("\n", i)
            i = n if j < 0 else j
        else:
            out.append(c)
            i += 1
    return "".join(out)


DEF_RE = re.compile(r"^LC_API\s+(.+?)\b(r3x_\w+)\s*\(([^)]*)\)\s*\{?", re.M)


def norm_type(t):
    t = re.sub(r"\s+", " ", t.strip())
    t = t.replace(" *", " *").replace("* ", "*")
    t = re.sub(r"\s*\*", " *", t)
    return t.strip()


def parse_exports(shim_text):
    """[(name, return type, [(type, name)])] in file order, from LC_API
    definitions. A forward prototype (the parameter list followed by ';') is
    not a definition and is skipped. Raises ValueError on a parameter it
    cannot read."""
    text = strip_comments(shim_text)
    out, seen = [], set()
    for m in DEF_RE.finditer(text):
        if not m.group(0).rstrip().endswith("{"):
            continue                      # a prototype, or something stranger
        ret, name, params = norm_type(m.group(1)), m.group(2), m.group(3).strip()
        if name in seen:
            raise ValueError("%s is defined twice in the shim" % name)
        seen.add(name)
        plist = []
        if params and params != "void":
            for p in params.split(","):
                p = p.strip()
                pm = re.match(r"(.+?)(\w+)$", p, re.S)
                if not pm:
                    raise ValueError("cannot read parameter %r of %s" % (p, name))
                plist.append((norm_type(pm.group(1)), pm.group(2)))
        out.append((name, ret, plist))
    return out


def lc_api_definitions(shim_text):
    """How many LC_API lines open a definition, counted WITHOUT the parser's
    regex: an LC_API line whose statement reaches '{' before ';'. If this
    and parse_exports disagree the parser went blind on some line, and a
    blind line is an export nothing checks."""
    text = strip_comments(shim_text)
    n = 0
    for m in re.finditer(r"(?m)^LC_API\b", text):
        brace, semi = text.find("{", m.end()), text.find(";", m.end())
        if brace >= 0 and (semi < 0 or brace < semi):
            n += 1
        elif semi >= 0 and "(*" in text[m.end():semi]:
            n += 1                        # an exported pointer: not a shape this gate knows
    return n


def declaration(e):
    name, ret, plist = e
    params = ", ".join("%s%s%s" % (t, "" if t.endswith("*") else " ", n) for t, n in plist) or "void"
    sep = "" if ret.endswith("*") else " "
    return "extern %s%s%s(%s);" % (ret, sep, name, params)


def decl_block(ex):
    return "\n".join([DECL_BEGIN] + [declaration(e) for e in ex] + [DECL_END])


def fuzz_block(ex):
    lines = [FUZZ_BEGIN]
    names = []
    for name, ret, plist in ex:
        args = []
        i = 0
        while i < len(plist):
            t, pn = plist[i]
            if t == "const unsigned char *":
                if i + 1 >= len(plist) or plist[i + 1][0] != "int":
                    raise ValueError("%s: a byte pointer must be followed by an int length" % name)
                args.append("fz_bytes(), fz_bytes_len()")
                i += 2
                continue
            if t not in KINDS or KINDS[t] is None:
                raise ValueError("%s: the fuzz test cannot make a %r" % (name, t))
            args.append(KINDS[t])
            i += 1
        call = "%s(%s)" % (name, ", ".join(args))
        if ret == "void":
            body = "%s;" % call
        elif ret.endswith("*"):
            body = "fz_seen_ptr((const void *)%s);" % call
        elif ret == "int":
            body = "fz_seen_int(%s);" % call
        elif ret == "double":
            body = "fz_seen_num(%s);" % call
        else:
            raise ValueError("%s returns %r, which the fuzz test cannot take" % (name, ret))
        lines.append("static void fz_%s(void) { %s }" % (name, body))
        names.append(name)
    lines.append("static void (*const k_fuzz_calls[])(void) = {")
    for n in names:
        lines.append("    fz_%s," % n)
    lines.append("};")
    lines.append('static const char *const k_fuzz_names[] = {')
    for n in names:
        lines.append('    "%s",' % n)
    lines.append("};")
    lines.append(FUZZ_END)
    return "\n".join(lines)


def between(text, begin, end):
    """(inside, start, stop) of the span from `begin` through `end`, or None."""
    a = text.find(begin)
    b = text.find(end)
    if a < 0 or b < 0 or b < a:
        return None
    return text[a:b + len(end)], a, b + len(end)


def splice(text, begin, end, block):
    span = between(text, begin, end)
    if span is None:
        return None
    return text[:span[1]] + block + text[span[2]:]


def check(shim_text, smoke_text, fuzz_text):
    """(problems, wanted smoke text, wanted fuzz text). Pure: the fixture
    test calls it on texts it has broken in memory. The wanted texts are None
    when a marker pair is missing."""
    problems = []
    try:
        ex = parse_exports(shim_text)
        want_decl = decl_block(ex)
        want_table = fuzz_block(ex)
    except ValueError as err:
        return ["shim: %s" % err], None, None
    if len(ex) < MIN_EXPORTS:
        return ["only %d exports found in the shim (fewer than %d): the scanner is blind"
                % (len(ex), MIN_EXPORTS)], None, None
    n_lines = lc_api_definitions(shim_text)
    if n_lines != len(ex):
        problems.append("%d LC_API lines in the shim but %d exports parsed: a line the parser cannot read"
                        % (n_lines, len(ex)))
    names = set(e[0] for e in ex)

    # 1. the smoke test's declaration block, line for line
    want_smoke = splice(smoke_text, DECL_BEGIN, DECL_END, want_decl)
    if want_smoke is None:
        problems.append("smoke test: the SHIM DECLARATIONS marker pair is missing")
    else:
        have = set(between(smoke_text, DECL_BEGIN, DECL_END)[0].split("\n"))
        want = set(want_decl.split("\n"))
        for line in sorted(want - have):
            problems.append("smoke test: declaration block lacks: %s" % line)
        for line in sorted(have - want):
            problems.append("smoke test: declaration block has a line the shim does not back: %s" % line)
        if not problems and want_smoke != smoke_text:
            problems.append("smoke test: declaration block is out of order (run --write)")
        # 2. every export CALLED outside the block, comments and literals
        span = between(smoke_text, DECL_BEGIN, DECL_END)
        body = strip_comments(smoke_text[:span[1]] + smoke_text[span[2]:], blank_strings=True)
        called = set(re.findall(r"\b(r3x_\w+)\s*\(", body))
        for name, _, _ in ex:
            if name not in called:
                problems.append("export never called by the smoke test: %s" % name)
        for name in sorted(called - names):
            problems.append("smoke test calls a name the shim does not export: %s" % name)
        if re.search(r"(?m)^\s*extern\b[^;]*\br3x_\w+\s*\(", body):
            problems.append("smoke test declares a shim export by hand, outside the generated block")

    # 3. the fuzz test: the same declarations, one thunk per export, and the
    #    table actually walked
    want_fuzz = splice(fuzz_text, DECL_BEGIN, DECL_END, want_decl)
    if want_fuzz is not None:
        want_fuzz = splice(want_fuzz, FUZZ_BEGIN, FUZZ_END, want_table)
    if want_fuzz is None:
        problems.append("fuzz test: a SHIM DECLARATIONS or FUZZ CALLS marker pair is missing")
    else:
        if between(fuzz_text, DECL_BEGIN, DECL_END)[0] != want_decl:
            problems.append("fuzz test: declaration block is stale (run --write)")
        span = between(fuzz_text, FUZZ_BEGIN, FUZZ_END)
        if span[0] != want_table:
            problems.append("fuzz test: call table is stale (run --write)")
        rest = strip_comments(fuzz_text[:span[1]] + fuzz_text[span[2]:], blank_strings=True)
        if not re.search(r"\bk_fuzz_calls\s*\[[^\]]+\]\s*\(\s*\)", rest):
            problems.append("fuzz test: nothing draws from k_fuzz_calls (the table is never walked)")
    return problems, want_smoke, want_fuzz


def main():
    write = "--write" in sys.argv[1:]
    try:
        with open(SHIM, encoding="utf-8") as f:
            shim = f.read()
        with open(SMOKE, encoding="utf-8") as f:
            smoke = f.read()
        with open(FUZZ, encoding="utf-8") as f:
            fuzz = f.read()
    except OSError as err:
        print("check-smoke-coverage: cannot read an input: %s" % err)
        return 2
    problems, want_smoke, want_fuzz = check(shim, smoke, fuzz)
    if write:
        if want_smoke is None or want_fuzz is None:
            for line in problems:
                print("FAIL " + line)
            return 2
        for path, old, new in ((SMOKE, smoke, want_smoke), (FUZZ, fuzz, want_fuzz)):
            if old != new:
                with open(path, "w", encoding="utf-8", newline="\n") as f:
                    f.write(new)
                print("check-smoke-coverage: wrote %s" % os.path.relpath(path, ROOT))
        problems, _, _ = check(shim, want_smoke, want_fuzz)
    if problems:
        for line in problems:
            print("FAIL " + line)
        return 2 if any("blind" in p for p in problems) else 1
    print("check-smoke-coverage: OK - %d exports, each declared as defined, called by the smoke test and in the fuzz table"
          % len(parse_exports(shim)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
