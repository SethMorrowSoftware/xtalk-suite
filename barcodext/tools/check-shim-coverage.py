#!/usr/bin/env python3
"""check-shim-coverage.py - the shim, its tests and its binding name the same
functions.

A member like this one is four files that must agree by NAME and nothing
makes them: the shim (src/*_shim.c or .cpp) defines the exports, the smoke
test calls them, the binding (src/<member>.lcb) binds them, and the engine
self-test calls the binding's public handlers. A disagreement is not a
compile error anywhere. It is an export nothing has ever run, or a bind that
fails to resolve on an engine, the first time a script reaches it.

Everything is derived from the files; nothing is listed by hand, and the
same file serves every member that carries it (the member's name is its
directory's; the suite's check-checker-drift.py holds the copies equal):

  1. every export the shim defines is CALLED by tests/smoke_test.*: named
     outside comments, string literals and `extern` declarations. A
     declaration is not a call (suite root CLAUDE.md, the box2dxt lesson);
  2. the binding binds exactly the shim's exports, each once: no export left
     unbound (dead code that still ships), no bind to a name the shim does
     not define (a resolve failure on an engine);
  3. the ABI number is the same in the shim's #define, in the binding's
     checkABI() comparison and in the sentence it throws;
  4. the linker's export pattern (src/<member>.map) is the exports' prefix;
  5. every public handler of the binding is in the engine self-test's sweep
     (tests/engine-selftest.lc: `put "name" into tName`, then a call), and
     the sweep names no handler that is gone;
  6. every export is declared wherever the tests declare the shim (a second
     translation unit's idea of a signature is the suite's
     check-lcb-signatures.py's to hold; here, only that none is missing).

    python3 tools/check-shim-coverage.py

Exit status: 0 held, 1 a difference (each named), 2 the gate could not read
its inputs (a blind gate must not print OK).
"""
import glob
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Fewer exports or public handlers than this means the scanner went blind,
# not that the member shrank: fail rather than print OK over nothing.
MIN_EXPORTS = 10
MIN_PUBLIC = 5


class Blind(Exception):
    pass


def strip_c(text, blank_strings=True):
    """Cut /* */ and // comments with a string-state-aware scan, and blank
    the inside of string literals (a name in a label is not a call)."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == '"' or c == "'":
            quote = c
            out.append(c)
            i += 1
            while i < n and text[i] != quote and text[i] != "\n":
                if text[i] == "\\" and i + 1 < n:
                    out.append("  " if blank_strings else text[i:i + 2])
                    i += 2
                    continue
                out.append(" " if blank_strings else text[i])
                i += 1
            if i < n and text[i] == quote:
                out.append(quote)
                i += 1
        elif text.startswith("/*", i):
            j = text.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append("".join(ch if ch == "\n" else " " for ch in text[i:j]))
            i = j
        elif text.startswith("//", i):
            j = text.find("\n", i)
            j = n if j < 0 else j
            i = j
        else:
            out.append(c)
            i += 1
    return "".join(out)


def strip_script(text):
    """Cut -- and # comments of a LiveCode script or .lcb, and /* */ blocks,
    leaving string literals as they are (the sweep's names are literals)."""
    text = re.sub(r"/\*.*?\*/", lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)
    out = []
    for line in text.split("\n"):
        cut, quoted = len(line), False
        for i, c in enumerate(line):
            if c == '"':
                quoted = not quoted
            elif not quoted and (line.startswith("--", i) or c == "#"):
                cut = i
                break
        out.append(line[:cut])
    return "\n".join(out)


def member_files(root):
    """The member's files, found, not listed."""
    member = os.path.basename(os.path.abspath(root))
    shims = sorted(glob.glob(os.path.join(root, "src", "*_shim.c")) + glob.glob(os.path.join(root, "src", "*_shim.cpp")))
    smokes = sorted(glob.glob(os.path.join(root, "tests", "smoke_test.c*")))
    if len(shims) != 1:
        raise Blind("expected one src/*_shim.c or .cpp, found %d" % len(shims))
    if len(smokes) != 1:
        raise Blind("expected one tests/smoke_test.c or .cpp, found %d" % len(smokes))
    files = {
        "member": member,
        "shim": shims[0],
        "smoke": smokes[0],
        "lcb": os.path.join(root, "src", member + ".lcb"),
        "map": os.path.join(root, "src", member + ".map"),
        "engine": os.path.join(root, "tests", "engine-selftest.lc"),
        "declared": sorted(glob.glob(os.path.join(root, "tests", "*_exports.h"))
                           + glob.glob(os.path.join(root, "tests", "*_test.c*"))),
    }
    for key in ("lcb", "map", "engine"):
        if not os.path.exists(files[key]):
            raise Blind("missing " + os.path.relpath(files[key], root))
    return files


def read(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def check(texts, member):
    """The problems, as sentences. `texts` maps shim, smoke, lcb, map, engine
    to file text and declared to a list of texts; the fixture test hands in
    broken ones."""
    problems = []
    shim = strip_c(texts["shim"])
    macro = re.search(r"(?m)^\s*#\s*define\s+([A-Z][A-Z0-9]*_API)\b", shim)
    if not macro:
        raise Blind("the shim defines no <PREFIX>_API export macro")
    macro = macro.group(1)
    prefix = macro[:-4].lower() + "_"
    exports = re.findall(r"(?m)^%s\s+[^;{()]*?\b(%s\w+)\s*\(" % (macro, prefix), shim)
    if len(exports) < MIN_EXPORTS:
        raise Blind("only %d %s exports found in the shim" % (len(exports), macro))
    for name in sorted(set(n for n in exports if exports.count(n) > 1)):
        problems.append("export defined twice in the shim: " + name)
    exports = sorted(set(exports))

    # 1. called by the smoke test (declarations cut: a statement that begins
    # `extern` and runs to its semicolon).
    smoke = strip_c(texts["smoke"])
    body = re.sub(r"(?ms)^[ \t]*extern\b[^;]*;", "", smoke)
    for name in exports:
        if not re.search(r"\b%s\s*\(" % re.escape(name), body):
            problems.append("export never called by the smoke test: " + name)

    # 6. declared for the tests
    declared = "\n".join(strip_c(t) for t in texts["declared"])
    for name in exports:
        if not re.search(r"\b%s\s*\(" % re.escape(name), declared):
            problems.append("export declared nowhere under tests/: " + name)

    # 2. the binding's binds
    lcb = strip_script(texts["lcb"])
    binds = re.findall(r'binds to "c:([A-Za-z0-9_]+)>([A-Za-z0-9_]+)!cdecl"', lcb)
    for library, name in binds:
        if library != member:
            problems.append("bind to the library '%s', not '%s': %s" % (library, member, name))
    bound = [name for _, name in binds]
    for name in sorted(set(n for n in bound if bound.count(n) > 1)):
        problems.append("export bound twice in the binding: " + name)
    for name in exports:
        if name not in bound:
            problems.append("export the binding never binds: " + name)
    for name in sorted(set(bound)):
        if name not in exports:
            problems.append("bind to a name the shim does not define: " + name)

    # 3. the ABI number, three places
    abi = re.search(r"(?m)^\s*#\s*define\s+[A-Z][A-Z0-9]*_ABI_VERSION\s+(\d+)\s*$", shim)
    if not abi:
        raise Blind("the shim defines no <PREFIX>_ABI_VERSION number")
    abi = abi.group(1)
    compared = re.search(r"if tV is not (\d+) then", lcb)
    thrown = re.search(r"this binding needs ABI (\d+)", lcb)
    if not compared or not thrown:
        problems.append("the binding's checkABI() has no `if tV is not N then` or no 'this binding needs ABI N'")
    else:
        if compared.group(1) != abi:
            problems.append("ABI: the shim says %s, the binding's checkABI() compares with %s" % (abi, compared.group(1)))
        if thrown.group(1) != abi:
            problems.append("ABI: the shim says %s, the binding's error says it needs %s" % (abi, thrown.group(1)))

    # 4. the linker's pattern
    if not re.search(r"(?m)^\s*%s\*;\s*$" % re.escape(prefix), strip_c(texts["map"])):
        problems.append("src/%s.map does not export the pattern %s*" % (member, prefix))

    # 5. the engine sweep
    public = re.findall(r"(?m)^public handler\s+(\w+)\s*\(", lcb)
    if len(public) < MIN_PUBLIC:
        raise Blind("only %d public handlers found in the binding" % len(public))
    engine = strip_script(texts["engine"])
    sweep = re.search(r"(?ms)^command sweepEveryHandler\b(.*?)^end sweepEveryHandler\b", engine)
    if not sweep:
        problems.append("tests/engine-selftest.lc has no `command sweepEveryHandler`")
    else:
        sweep = sweep.group(1)
        named = re.findall(r'put "(\w+)" into tName\s*\n\s*(.*)', sweep)
        seen = {}
        for name, following in named:
            seen[name] = following
            if not re.search(r"\b%s\b" % re.escape(name), following):
                problems.append("engine sweep names %s and then calls something else: %s" % (name, following.strip()))
        for name in public:
            if name not in seen:
                problems.append("public handler missing from the engine sweep: " + name)
        for name in sorted(seen):
            if name not in public:
                problems.append("engine sweep names a handler the binding does not have: " + name)
    return problems, len(exports), len(public)


def main():
    try:
        files = member_files(ROOT)
        texts = {key: read(files[key]) for key in ("shim", "smoke", "lcb", "map", "engine")}
        texts["declared"] = [read(path) for path in files["declared"]]
        problems, exports, public = check(texts, files["member"])
    except (Blind, OSError) as e:
        print("check-shim-coverage: CANNOT CHECK - %s" % e)
        return 2
    if problems:
        print("check-shim-coverage: %d PROBLEM(S)" % len(problems))
        for p in problems:
            print("  " + p)
        return 1
    print("check-shim-coverage: OK (%d exports called by the smoke test and bound once each; %d public handlers in "
          "the engine sweep; one ABI number)" % (exports, public))
    return 0


if __name__ == "__main__":
    sys.exit(main())
