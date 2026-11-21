#!/usr/bin/env python3
"""check-smoke-coverage.py - tests/smoke_test.c and tests/fuzz_test.c against
src/audio_shim.c.

The smoke test is the only thing that RUNS the shim on every platform (and
under ASan/UBSan), so an export it never enters is an export nothing has run.
This gate holds two things, both derived from the shim's own LC_API
definitions and never from a list kept by hand:

  1. the declaration block in the smoke test (between the SHIM DECLARATIONS
     markers) is exactly the shim's exports, signature for signature - a test
     that declares `int f(int)` over a shim that defines `double f(int)`
     links, runs and reads garbage;
  2. every export is CALLED by the test body: named outside the declaration
     block, outside comments and outside string literals. A declaration is
     not a call (suite root CLAUDE.md, the box2dxt lesson: grep once counted
     six `extern`-declared, never-called exports as covered).

The fuzz test (tests/fuzz_test.c) is held the same way: its declaration block
is the shim's, and its call table (between the FUZZ CALLS markers) has one
generated thunk per export, so a new export is fuzzed the day it is written
and none can be left out by hand. box3dxt's gate of the same name is this
one's ancestor.

    python3 tools/check-smoke-coverage.py           # the gate
    python3 tools/check-smoke-coverage.py --write   # regenerate every block

Exit status: 0 held, 1 a difference (each named), 2 the gate could not read
its inputs (a blind gate must not print OK).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHIM = os.path.join(ROOT, "src", "audio_shim.c")
SMOKE = os.path.join(ROOT, "tests", "smoke_test.c")

DECL_BEGIN = "/* >>> BEGIN SHIM DECLARATIONS (generated: tools/check-smoke-coverage.py --write) >>> */"
DECL_END = "/* <<< END SHIM DECLARATIONS <<< */"
FUZZ = os.path.join(ROOT, "tests", "fuzz_test.c")
FUZZ_BEGIN = "/* >>> BEGIN FUZZ CALLS (generated: tools/check-smoke-coverage.py --write) >>> */"
FUZZ_END = "/* <<< END FUZZ CALLS <<< */"

# A shim this small in exports means the scanner went blind, not that the
# binding shrank: fail rather than print OK over nothing.
MIN_EXPORTS = 100


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
            out.append(re.sub(r"[^\n]", " ", text[i:j]))
            i = j
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def norm_type(t):
    t = re.sub(r"\s+", " ", t.strip())
    return t.replace(" *", "*").replace("* ", "*")


def parse_exports(shim_text):
    """[(name, return type, [param types], [param names])] in file order."""
    code = strip_comments(shim_text)
    exports = []
    for m in re.finditer(r"^LC_API\s+([^(;{]+?)\b(aux_\w+)\s*\(([^)]*)\)", code, re.M | re.S):
        ret, name, params = norm_type(m.group(1)), m.group(2), m.group(3)
        types, names = [], []
        if params.strip() and params.strip() != "void":
            for p in params.split(","):
                pm = re.match(r"^\s*(.+?)(\w+)\s*$", p, re.S)
                if not pm:
                    raise ValueError("unreadable parameter %r of %s" % (p, name))
                types.append(norm_type(pm.group(1)))
                names.append(pm.group(2))
        exports.append((name, ret, types, names))
    return exports


def decl_block(exports):
    lines = ["/* %d exports, in the shim's order. Plain declarations: the test is a client of" % len(exports),
             " * the built library, exactly as the engine's FFI is. */"]
    for name, ret, types, names in exports:
        params = ", ".join("%s%s%s" % (t, "" if t.endswith("*") else " ", n) for t, n in zip(types, names)) or "void"
        sep = "" if ret.endswith("*") else " "
        lines.append("extern %s%s%s(%s);" % (ret, sep, name, params))
    return "\n".join(lines) + "\n"


# How the fuzz test draws an argument, BY PARAMETER NAME. A name the shim
# introduces that is not here stops --write and the gate: a parameter fuzzed
# with the wrong kind of value (a sound handle drawn as a small number) is a
# call that only ever takes its refusal path.
FUZZ_INT = {
    "engine": "HE()", "sound": "HS()", "group": "HG()", "capture": "HC()",
    "device": "DEV()", "sampleRate": "RATE()", "channels": "CH()",
    "index": "small(-1, 6)", "points": "small(-2, 2100)", "frames": "small(-5, 3000)",
    "stream": "flag()", "flag": "flag()",
}
FUZZ_DOUBLE = {
    "seconds": "T()", "startSeconds": "T()", "endSeconds": "T()", "bufferSeconds": "BUF()",
    "volume": "V()", "from": "V()", "to": "V()", "amplitude": "V()", "pan": "V()",
    "hertz": "HZ()",
}
FUZZ_TEXT = {"format": "FMT()", "path": "PATH()", "savePath": "SAVE()", "shape": "SHAPE()", "color": "COLOR()"}
# Exports the table cannot draw arguments for; the fuzz test's own code must
# call each (aux_text_length takes a text result: text() measures every one;
# aux_out_pointer is read by bytes_out() after every call that returns a
# byte count).
FUZZ_BY_HAND = {"aux_text_length", "aux_out_pointer"}
# Creators: the pool a returned handle joins.
FUZZ_KEEP = [(r"^aux_engine_create", "s_engines"),
             (r"^aux_sound_(load|load_data|from_pcm|tone|noise|clone)$", "s_sounds"),
             (r"^aux_group_create$", "s_groups"), (r"^aux_capture_open$", "s_captures")]
# Calls that leave bytes in the out buffer: the fuzz test reads every one of
# them back (under ASan, a count larger than the buffer is a report).
FUZZ_BYTES = {"aux_engine_render", "aux_capture_read", "aux_decode_file", "aux_decode_data", "aux_wav_encode"}


def fuzz_block(exports):
    out = ["/* One thunk per export: it draws the arguments, in order (C leaves the",
           " * order of argument evaluation open, and a run must be the same",
           " * everywhere), names itself for the trace and makes the call. */"]
    table = []
    for n, (name, ret, types, names) in enumerate(exports):
        if name in FUZZ_BY_HAND:
            continue
        draws, args = [], []
        for i, (t, pn) in enumerate(zip(types, names)):
            if t == "int" and pn == "length":
                if i == 0 or types[i - 1] != "const void*":
                    raise ValueError("%s: a length must follow the bytes it measures" % name)
                draws.append("int a%d = blob_length(k);" % i)
            elif t == "int":
                if pn not in FUZZ_INT:
                    raise ValueError("no fuzz draw for int parameter %r of %s (add it to FUZZ_INT)" % (pn, name))
                draws.append("int a%d = %s;" % (i, FUZZ_INT[pn]))
            elif t == "double":
                draws.append("double a%d = %s;" % (i, FUZZ_DOUBLE.get(pn, "D()")))
            elif t == "const char*":
                if pn not in FUZZ_TEXT:
                    raise ValueError("no fuzz draw for text parameter %r of %s (add it to FUZZ_TEXT)" % (pn, name))
                draws.append("const char *a%d = %s;" % (i, FUZZ_TEXT[pn]))
            elif t == "const void*" and pn == "bytes":
                draws.append("int k = blob_pick(); const void *a%d = blob_bytes(k);" % i)
            else:
                raise ValueError("no fuzz draw for a %s parameter (%s of %s)" % (t, pn, name))
            args.append("a%d" % i)
        call = "%s(%s)" % (name, ", ".join(args))
        pool = next((p for rx, p in FUZZ_KEEP if re.match(rx, name)), None)
        if ret == "void":
            use = "%s;" % call
        elif ret == "int" and name in FUZZ_BYTES:
            use = "bytes_out(%s);" % call
        elif ret == "int":
            use = "s_lastInt = %s;%s" % (call, " keep(&%s, s_lastInt);" % pool if pool else "")
        elif ret == "double":
            use = "number(%s);" % call
        elif ret == "const char*":
            use = "text(%s);" % call
        else:
            raise ValueError("no fuzz handling for a %s result (%s)" % (ret, name))
        out.append('static void fz_%d(void) { %s%strace("%s"); %s }'
                   % (n, " ".join(draws), " " if draws else "", name, use))
        table.append('    { "%s", fz_%d },' % (name, n))
    out += ["typedef struct { const char *name; void (*call)(void); } FuzzCall;",
            "static const FuzzCall k_fuzz[] = {"] + table + ["};"]
    return "\n".join(out) + "\n"


def check_fuzz(shim_text, fuzz_text):
    """Problems of the fuzz test against the shim. Pure, like check()."""
    problems = []
    exports = parse_exports(shim_text)
    decl = between(fuzz_text, DECL_BEGIN, DECL_END)
    calls = between(fuzz_text, FUZZ_BEGIN, FUZZ_END)
    if decl is None:
        problems.append("fuzz test: the SHIM DECLARATIONS marker pair is missing or repeated")
    elif decl[0] != decl_block(exports):
        problems.append("fuzz test: declaration block is stale (run tools/check-smoke-coverage.py --write)")
    try:
        want = fuzz_block(exports)
    except ValueError as e:
        problems.append("fuzz test: %s" % e)
        return problems
    if calls is None:
        problems.append("fuzz test: the FUZZ CALLS marker pair is missing or repeated")
    elif calls[0] != want:
        problems.append("fuzz test: call table is stale (run tools/check-smoke-coverage.py --write)")
    # The table must be WALKED: a generated list nothing indexes fuzzes nothing.
    if calls is not None:
        rest = strip_comments(fuzz_text[:calls[1]] + fuzz_text[calls[2]:], blank_strings=True)
        if not re.search(r"\bk_fuzz\s*\[", rest) or not re.search(r"->\s*call\s*\(", rest):
            problems.append("fuzz test: nothing draws from k_fuzz and calls it")
        for name in sorted(FUZZ_BY_HAND):
            if not re.search(r"\b%s\s*\(" % name, rest):
                problems.append("fuzz test: %s is not in the table and nothing calls it by hand" % name)
    return problems


def between(text, begin, end):
    """(inside, start, stop) of the one span between two markers, else None."""
    if text.count(begin) != 1 or text.count(end) != 1:
        return None
    i = text.index(begin) + len(begin) + 1
    j = text.index(end)
    if j < i - 1:
        return None
    return text[i:j], i, j


def replace_between(text, begin, end, body):
    span = between(text, begin, end)
    if span is None:
        raise ValueError("marker pair missing or repeated: %s" % begin)
    return text[:span[1]] + body + text[span[2]:]


def check(shim_text, smoke_text):
    """Return (problems, stats). Pure: the fixture test drives it on mutated text."""
    problems = []
    exports = parse_exports(shim_text)
    names = [e[0] for e in exports]
    if len(exports) < MIN_EXPORTS:
        problems.append("only %d LC_API exports parsed from the shim (floor %d): the scanner is blind"
                        % (len(exports), MIN_EXPORTS))
        return problems, {"exports": len(exports)}
    dup = sorted(set(n for n in names if names.count(n) > 1))
    for n in dup:
        problems.append("export defined twice in the shim: %s" % n)
    # An LC_API line the parser could not read as a definition would silently
    # leave an export out of everything below.
    raw = len(re.findall(r"^LC_API\b", strip_comments(shim_text), re.M))
    if raw != len(exports):
        problems.append("%d LC_API lines in the shim but %d parsed as definitions" % (raw, len(exports)))

    decl = between(smoke_text, DECL_BEGIN, DECL_END)
    if decl is None:
        problems.append("smoke test: the SHIM DECLARATIONS marker pair is missing or repeated")
    elif decl[0] != decl_block(exports):
        want = set(decl_block(exports).splitlines())
        have = set(decl[0].splitlines())
        for line in sorted(want - have)[:12]:
            problems.append("declaration block lacks: %s" % line)
        for line in sorted(have - want)[:12]:
            problems.append("declaration block has a line the shim does not back: %s" % line)
        if want == have:
            problems.append("declaration block differs from the shim in order only")

    # What the test CALLS: the body with the generated block cut.
    body = smoke_text
    if decl is not None:
        body = body[:decl[1]] + body[decl[2]:]
    scan = strip_comments(body, blank_strings=True)
    called = set(re.findall(r"\b(aux_\w+)\s*\(", scan))
    for n in names:
        if n not in called:
            problems.append("export never called by the smoke test: %s" % n)
    for n in sorted(called - set(names)):
        problems.append("smoke test calls a name the shim does not export: %s" % n)
    return problems, {"exports": len(exports), "direct": len(called)}


def main(argv):
    try:
        shim_text = open(SHIM, encoding="utf-8").read()
        smoke_text = open(SMOKE, encoding="utf-8").read()
    except OSError as e:
        print("check-smoke-coverage: cannot read its inputs: %s" % e)
        return 2
    try:
        fuzz_text = open(FUZZ, encoding="utf-8").read()
    except OSError as e:
        print("check-smoke-coverage: cannot read its inputs: %s" % e)
        return 2
    if "--write" in argv:
        exports = parse_exports(shim_text)
        newf = replace_between(fuzz_text, DECL_BEGIN, DECL_END, decl_block(exports))
        newf = replace_between(newf, FUZZ_BEGIN, FUZZ_END, fuzz_block(exports))
        if newf != fuzz_text:
            with open(FUZZ, "w", encoding="utf-8", newline="\n") as f:
                f.write(newf)
            print("check-smoke-coverage: wrote both generated blocks of tests/fuzz_test.c")
        fuzz_text = newf
        new = replace_between(smoke_text, DECL_BEGIN, DECL_END, decl_block(exports))
        if new != smoke_text:
            with open(SMOKE, "w", encoding="utf-8", newline="\n") as f:
                f.write(new)
            print("check-smoke-coverage: wrote the declaration block of tests/smoke_test.c")
        smoke_text = new
    problems, stats = check(shim_text, smoke_text)
    problems += check_fuzz(shim_text, fuzz_text)
    if problems:
        for p in problems:
            print("FAIL " + p)
        print("check-smoke-coverage: %d problem(s)" % len(problems))
        return 1
    print("check-smoke-coverage: OK - %d exports, each declared as the shim defines it and each called "
          "by name; the fuzz test's table holds every one" % stats["exports"])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
