#!/usr/bin/env python3
"""check-smoke-coverage.py - tests/smoke_test.c and tests/fuzz_test.c against
src/box3d_shim.c.

The smoke test is the only thing that RUNS the shim on every platform (and
under ASan/UBSan), so an export it never enters is an export nothing has run.
This gate holds three things, all derived from the shim's own LC_API
definitions and never from a list kept by hand:

  1. the declaration block in the smoke test (between the SHIM DECLARATIONS
     markers) is exactly the shim's exports, signature for signature - a test
     that declares `int f(int)` over a shim that defines `double f(int)`
     links, runs and reads garbage;
  2. the joint family table (between the JOINT FAMILY TABLE markers) is
     exactly the scalar joint calls the shim defines - the table is how ~170
     near-identical getters and setters are each entered, on their own joint
     type, on another type and on no joint;
  3. every export is CALLED by the test body: named outside the declaration
     block, outside comments and outside string literals. A declaration is
     not a call (suite root CLAUDE.md, the box2dxt lesson: grep once counted
     six `extern`-declared, never-called exports as covered).

The fuzz test (tests/fuzz_test.c) is held the same way: its declaration block
is the shim's, and its call table (between the FUZZ CALLS markers) has one
generated thunk per export, so a new export is fuzzed the day it is written
and none can be left out by hand.

    python3 tools/check-smoke-coverage.py           # the gate
    python3 tools/check-smoke-coverage.py --write   # regenerate every block

Exit status: 0 held, 1 a difference (each named), 2 the gate could not read
its inputs (a blind gate must not print OK).
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SHIM = os.path.join(ROOT, "src", "box3d_shim.c")
SMOKE = os.path.join(ROOT, "tests", "smoke_test.c")

DECL_BEGIN = "/* >>> BEGIN SHIM DECLARATIONS (generated: tools/check-smoke-coverage.py --write) >>> */"
DECL_END = "/* <<< END SHIM DECLARATIONS <<< */"
FAM_BEGIN = "/* >>> BEGIN JOINT FAMILY TABLE (generated: tools/check-smoke-coverage.py --write) >>> */"
FAM_END = "/* <<< END JOINT FAMILY TABLE <<< */"
FUZZ = os.path.join(ROOT, "tests", "fuzz_test.c")
FUZZ_BEGIN = "/* >>> BEGIN FUZZ CALLS (generated: tools/check-smoke-coverage.py --write) >>> */"
FUZZ_END = "/* <<< END FUZZ CALLS <<< */"

# The joint words, in the order test_joint_families() passes its handles.
FAMILIES = ["revolute", "prismatic", "spherical", "weld", "distance", "wheel", "motor", "parallel"]

# A shim this small in exports means the scanner went blind, not that the
# binding shrank: fail rather than print OK over nothing.
MIN_EXPORTS = 300


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
    for m in re.finditer(r"^LC_API\s+([^(;{]+?)\b(b3x_\w+)\s*\(([^)]*)\)", code, re.M | re.S):
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


def family_tables(exports):
    """(float pairs, flag pairs, lone getters, unclassified) over the exports
    whose only parameter is the joint and whose name starts with a joint word."""
    by_name = {e[0]: e for e in exports}
    floats, flags, getters, used = [], [], [], set()
    for name, ret, types, _ in exports:
        m = re.match(r"^b3x_(%s)_(.+)$" % "|".join(FAMILIES), name)
        if not m:
            continue
        word, rest = m.group(1), m.group(2)
        fam = FAMILIES.index(word)
        if ret == "void" and types == ["int", "double"] and rest.startswith("set_"):
            getter = "b3x_%s_%s" % (word, rest[4:])
            g = by_name.get(getter)
            if g and g[1] == "double" and g[2] == ["int"]:
                floats.append((fam, name, getter))
                used.update((name, getter))
        elif ret == "void" and types == ["int", "int"] and rest.startswith("enable_"):
            getter = "b3x_%s_is_%s_enabled" % (word, rest[7:])
            g = by_name.get(getter)
            if g and g[1] == "int" and g[2] == ["int"]:
                flags.append((fam, name, getter))
                used.update((name, getter))
    for name, ret, types, _ in exports:
        m = re.match(r"^b3x_(%s)_" % "|".join(FAMILIES), name)
        if m and name not in used and ret == "double" and types == ["int"]:
            getters.append((FAMILIES.index(m.group(1)), name))
            used.add(name)
    return floats, flags, getters


def family_block(exports):
    floats, flags, getters = family_tables(exports)
    out = ["/* Derived from the shim: every scalar joint setter with its getter, every",
           " * enable flag with its reader, and every getter that has no setter. The",
           " * family number indexes the handles test_joint_families() is given:",
           " * %s. */" % ", ".join("%s %d" % (w, i) for i, w in enumerate(FAMILIES)),
           "typedef struct { const char *name; int family; void (*set)(int, double); double (*get)(int); } FloatPair;",
           "typedef struct { const char *name; int family; void (*set)(int, int); int (*get)(int); } FlagPair;",
           "typedef struct { const char *name; int family; double (*get)(int); } Getter;",
           "static const FloatPair k_float_pairs[] = {"]
    out += ['    { "%s", %d, %s, %s },' % (s, fam, s, g) for fam, s, g in floats]
    out += ["};", "static const FlagPair k_flag_pairs[] = {"]
    out += ['    { "%s", %d, %s, %s },' % (s, fam, s, g) for fam, s, g in flags]
    out += ["};", "static const Getter k_getters[] = {"]
    out += ['    { "%s", %d, %s },' % (g, fam, g) for fam, g in getters]
    out += ["};"]
    return "\n".join(out) + "\n"


# How the fuzz test draws an argument, BY PARAMETER NAME. A name the shim
# introduces that is not here stops --write and the gate: a parameter fuzzed
# with the wrong kind of value (a body handle drawn as a small number) is a
# call that only ever takes its refusal path.
FUZZ_INT = {
    "w": "HW()", "b": "HB()", "ba": "HB()", "bb": "HB()", "s": "HS()", "j": "HJ()",
    "index": "small(-1, 6)", "p1": "small(0, 9)", "p2": "small(0, 9)", "p3": "small(0, 9)",
    "flag": "flag()", "wake": "flag()", "collide": "flag()", "updateMass": "flag()",
    "contact": "flag()", "hit": "flag()", "sensor": "flag()",
    "lx": "flag()", "ly": "flag()", "lz": "flag()", "ax": "flag()", "ay": "flag()", "az": "flag()",
    "type": "small(-1, 4)", "workers": "small(-1, 5)", "group": "small(-3, 3)",
    # the renderer: small pictures (a fuzz run renders thousands), pixels in
    # and just outside them, a colour in and just outside a byte
    "width": "small(-1, 48)", "height": "small(-1, 48)", "mode": "small(-1, 3)",
    "x": "small(-2, 50)", "y": "small(-2, 50)",
    "red": "small(-2, 257)", "green": "small(-2, 257)", "blue": "small(-2, 257)",
    "topRed": "small(-2, 257)", "topGreen": "small(-2, 257)", "topBlue": "small(-2, 257)",
    "bottomRed": "small(-2, 257)", "bottomGreen": "small(-2, 257)", "bottomBlue": "small(-2, 257)",
    "sides": "small(0, 34)", "substeps": "small(-1, 9)", "countX": "small(0, 9)", "countZ": "small(0, 9)",
}
FUZZ_DOUBLE = {
    "qx": "Q(0)", "qy": "Q(1)", "qz": "Q(2)", "qw": "Q(3)",
    "dt": "DT()", "category": "BITS()", "mask": "BITS()",
    "radius": "DP()", "radius1": "DP()", "radius2": "DP()", "height": "DP()",
    "hx": "DP()", "hy": "DP()", "hz": "DP()", "density": "DP()", "friction": "DP()",
    "restitution": "DP()", "hertz": "DP()", "damping": "DP()",
}
# Exports the table cannot draw arguments for; the fuzz test's own code must
# call each (b3x_text_length takes a text result: text() measures every one;
# b3x_render_pixels is bytes, not text: picture() reads every one after each call.
FUZZ_BY_HAND = {"b3x_text_length", "b3x_render_pixels"}
# Creators: the pool a returned handle joins.
FUZZ_KEEP = [(r"^b3x_world_create$", "s_worlds"), (r"^b3x_body_create", "s_bodies"),
             (r"^b3x_shape_add_", "s_shapes"),
             (r"^b3x_joint_(revolute|prismatic|spherical|weld|distance|wheel|motor|parallel|filter)$", "s_joints")]


def fuzz_block(exports):
    out = ["/* Two thunks per export. fz_N draws the arguments, in order (C leaves the",
           " * order of argument evaluation open, and a run must be the same",
           " * everywhere), and hands them to rp_N, which traces and makes the call;",
           " * a replayed trace enters at rp_N with the numbers it read. Every",
           " * argument rides as a double: an int fits one exactly. */"]
    table = []
    for n, (name, ret, types, names) in enumerate(exports):
        if name in FUZZ_BY_HAND:
            continue
        draws, args = [], []
        for i, (t, pn) in enumerate(zip(types, names)):
            if t == "int":
                if pn not in FUZZ_INT:
                    raise ValueError("no fuzz draw for int parameter %r of %s (add it to FUZZ_INT)" % (pn, name))
                draws.append("a[%d] = %s;" % (i, FUZZ_INT[pn]))
                args.append("(int)a[%d]" % i)
            elif t == "double":
                draws.append("a[%d] = %s;" % (i, FUZZ_DOUBLE.get(pn, "D()")))
                args.append("a[%d]" % i)
            else:
                raise ValueError("no fuzz draw for a %s parameter (%s of %s)" % (t, pn, name))
        call = "%s(%s)" % (name, ", ".join(args))
        pool = next((p for rx, p in FUZZ_KEEP if re.match(rx, name)), None)
        if ret == "void":
            use = "%s;" % call
        elif ret == "int":
            use = "s_lastInt = %s;%s" % (call, " keep(&%s, s_lastInt);" % pool if pool else "")
        elif ret == "double":
            use = "number(%s);" % call
        elif ret == "const char*":
            use = "text(%s);" % call
        else:
            raise ValueError("no fuzz handling for a %s result (%s)" % (ret, name))
        k = len(types)
        out.append('static void rp_%d(const double *a) { %str("%s", %d, a); %s }'
                   % (n, "" if k else "(void)a; ", name, k, use))
        out.append("static void fz_%d(void) { double a[%d]; %s rp_%d(a); }" % (n, max(k, 1), " ".join(draws), n))
        table.append('    { "%s", %d, fz_%d, rp_%d },' % (name, k, n, n))
    out += ["typedef struct { const char *name; int argc; void (*call)(void); void (*replay)(const double *); } FuzzCall;",
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
    fam = between(smoke_text, FAM_BEGIN, FAM_END)
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
    if fam is None:
        problems.append("smoke test: the JOINT FAMILY TABLE marker pair is missing or repeated")
    elif fam[0] != family_block(exports):
        problems.append("joint family table is stale (run tools/check-smoke-coverage.py --write)")

    # What the test CALLS: the body with both generated blocks cut, except
    # that a name in the family table counts when test_joint_families() is
    # itself called (the table is walked whole, so each entry is entered).
    body = smoke_text
    if decl is not None:
        body = body[:decl[1]] + body[decl[2]:]
    fam2 = between(body, FAM_BEGIN, FAM_END)
    table_names = set()
    if fam2 is not None:
        table_names = set(re.findall(r"\bb3x_\w+", strip_comments(fam2[0], blank_strings=True)))
        body = body[:fam2[1]] + body[fam2[2]:]
    scan = strip_comments(body, blank_strings=True)
    called = set(re.findall(r"\b(b3x_\w+)\s*\(", scan))
    walks_table = (len(re.findall(r"\btest_joint_families\s*\(", scan)) >= 2
                   and all(k in scan for k in ("k_float_pairs", "k_flag_pairs", "k_getters")))
    if not walks_table:
        problems.append("test_joint_families() is not both defined and called, or does not walk all three tables")
    else:
        called |= table_names
    for n in names:
        if n not in called:
            problems.append("export never called by the smoke test: %s" % n)
    for n in sorted(called - set(names)):
        problems.append("smoke test calls a name the shim does not export: %s" % n)
    floats, flags, getters = family_tables(exports)
    return problems, {"exports": len(exports), "table": len(floats) * 2 + len(flags) * 2 + len(getters),
                      "direct": len(called - table_names)}


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
        new = replace_between(new, FAM_BEGIN, FAM_END, family_block(exports))
        if new != smoke_text:
            with open(SMOKE, "w", encoding="utf-8", newline="\n") as f:
                f.write(new)
            print("check-smoke-coverage: wrote both generated blocks of tests/smoke_test.c")
        smoke_text = new
    problems, stats = check(shim_text, smoke_text)
    problems += check_fuzz(shim_text, fuzz_text)
    if problems:
        for p in problems:
            print("FAIL " + p)
        print("check-smoke-coverage: %d problem(s)" % len(problems))
        return 1
    print("check-smoke-coverage: OK - %d exports, each declared as the shim defines it and each called "
          "(%d by name, %d through the joint family table); the fuzz test's table holds every one"
          % (stats["exports"], stats["direct"], stats["table"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
