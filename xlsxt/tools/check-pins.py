#!/usr/bin/env python3
"""check-pins.py - the three pinned libraries, said the same way everywhere.

xlsxt builds libxlsxwriter, zlib and Expat from source at pinned commits
(CMakeLists.txt). Their versions are then WRITTEN in four more places, and a
hand-copied number goes stale silently (the suite root's lesson): the table
in CMakeLists.txt's own comment, THIRD-PARTY-LICENSES.md (which a package
ships as the notice of what is inside it), the version text the smoke test
expects from the built library, and the example in the binding's doc block.

    python3 tools/check-pins.py
        the gate, compiler-free: every one of those names the same three
        versions, and THIRD-PARTY-LICENSES.md names the three commits.

    python3 tools/check-pins.py --source <build>/_deps
        also, over the FETCHED sources of a configured build (the native
        lane runs this): each library's own header declares the version the
        pin's comment claims, and libxlsxwriter reads USE_R_LANG in exactly
        one place, the one src/quiet/R.h answers. If a new release used that
        switch for anything else, defining it would change more than where
        the warnings go.

Exit status: 0 held, 1 a difference, 2 an input could not be read.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIBRARIES = (("libxlsxwriter", "LIBXLSXWRITER"), ("zlib", "ZLIB"), ("Expat", "EXPAT"))


def read_pins(cmake_text):
    """({library: (version, commit)}, problems) from CMakeLists.txt."""
    pins, problems = {}, []
    for name, key in LIBRARIES:
        c = re.search(r'set\(XLSXT_%s_COMMIT\s+"([0-9a-f]{40})"\)' % key, cmake_text)
        v = re.search(r"^#   %s ([0-9][0-9.]*)\s" % re.escape(name), cmake_text, re.M)
        if not c or not v:
            problems.append("CMakeLists.txt: cannot find the pin of %s (its commit and its line in the "
                            "comment's table)" % name)
            continue
        pins[name] = (v.group(1), c.group(1))
    return pins, problems


def check(cmake_text, licenses_text, smoke_text, lcb_text):
    """Problems. Pure: the fixture test drives it on mutated text."""
    pins, problems = read_pins(cmake_text)
    if problems:
        return problems
    for name, (version, commit) in pins.items():
        if not re.search(r"\b%s %s\b" % (re.escape(name), re.escape(version)), licenses_text):
            problems.append("THIRD-PARTY-LICENSES.md does not name %s %s" % (name, version))
        if commit not in licenses_text:
            problems.append("THIRD-PARTY-LICENSES.md does not name %s's pinned commit %s" % (name, commit))
        if '"%s %s"' % (name, version) not in smoke_text:
            problems.append('tests/smoke_test.c does not expect "%s %s" in the library\'s version text'
                            % (name, version))
    example = "xlsxt ABI 1; " + "; ".join("%s %s" % (n, pins[n][0]) for n, _ in LIBRARIES)
    if example not in re.sub(r"\s+", " ", lcb_text):
        problems.append('src/xlsxt.lcb: xlLibraryVersion\'s doc block does not give "%s"' % example)
    # every 40-hex id the notice names must be a pin: a stale one left behind
    # beside the new one would satisfy the checks above
    for stray in sorted(set(re.findall(r"\b[0-9a-f]{40}\b", licenses_text)) - {c for _, c in pins.values()}):
        problems.append("THIRD-PARTY-LICENSES.md names a commit that is not a pin: %s" % stray)
    return problems


def check_source(deps, pins):
    """Problems of the fetched sources under a build's _deps folder."""
    problems = []

    def read(*parts):
        path = os.path.join(deps, *parts)
        try:
            return open(path, encoding="utf-8", errors="replace").read()
        except OSError:
            problems.append("cannot read %s" % path)
            return ""

    lxw = re.search(r'#define LXW_VERSION "([^"]+)"', read("libxlsxwriter-src", "include", "xlsxwriter.h"))
    z = re.search(r'#define ZLIB_VERSION "([^"]+)"', read("zlib-src", "zlib.h"))
    e = read("expat-src", "expat", "lib", "expat.h")
    em = [re.search(r"#\s*define XML_%s_VERSION (\d+)" % k, e) for k in ("MAJOR", "MINOR", "MICRO")]
    have = {"libxlsxwriter": lxw.group(1) if lxw else None, "zlib": z.group(1) if z else None,
            "Expat": ".".join(m.group(1) for m in em) if all(em) else None}
    for name, version in have.items():
        if version != pins[name][0]:
            problems.append("%s: the fetched source calls itself %s, CMakeLists.txt's comment says %s"
                            % (name, version, pins[name][0]))
    users = []
    top = os.path.join(deps, "libxlsxwriter-src")
    for folder in ("include", "src", "third_party"):
        for base, _, files in os.walk(os.path.join(top, folder)):
            for f in files:
                if f.endswith((".c", ".h")):
                    path = os.path.join(base, f)
                    n = open(path, encoding="utf-8", errors="replace").read().count("USE_R_LANG")
                    if n:
                        users.append((os.path.relpath(path, top).replace(os.sep, "/"), n))
    if users != [("include/xlsxwriter/common.h", 1)]:
        problems.append("libxlsxwriter reads USE_R_LANG somewhere other than the one place src/quiet/R.h "
                        "answers (include/xlsxwriter/common.h, once): %s" % users)
    return problems


def main(argv):
    try:
        texts = [open(os.path.join(ROOT, *p), encoding="utf-8").read() for p in
                 (("CMakeLists.txt",), ("THIRD-PARTY-LICENSES.md",), ("tests", "smoke_test.c"),
                  ("src", "xlsxt.lcb"))]
    except OSError as e:
        print("check-pins: cannot read its inputs: %s" % e)
        return 2
    problems = check(*texts)
    pins, _ = read_pins(texts[0])
    source = argv[argv.index("--source") + 1] if "--source" in argv and argv.index("--source") + 1 < len(argv) else None
    if source and not problems:
        problems += check_source(source, pins)
    if problems:
        print("check-pins: FAILED")
        for p in problems:
            print("  - " + p)
        return 1
    print("check-pins: OK (%s%s)" % (", ".join("%s %s" % (n, pins[n][0]) for n, _ in LIBRARIES),
                                     "; the fetched sources agree" if source else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
