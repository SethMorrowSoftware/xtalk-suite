#!/usr/bin/env python3
"""test-handler-calls.py - fixture tests for tools/check-handler-calls.py.

WHY THIS FILE EXISTS
    check-handler-calls.py answers one question - "does this called name
    exist?" - and it can only answer it about code it can SEE. On 2026-08-17 it
    could not see a third of nocloud's HTTP host, and it said OK anyway.

    Its strip_noise() ran four rules in four separate passes: block comments
    first, then line comments, then string literals. Both orderings were wrong
    at once. A `--` line comment that merely MENTIONED a route glob (`/_qs/*`)
    opened a phantom block comment, because block scanning ran before line
    comments were removed; and an HTTP header string carrying
    `Content-Range: bytes */` CLOSED one, because literals were removed last.
    In nocloud's source both fired: two phantom blocks swallowed 2,476 of 7,541
    lines, the second running to end-of-file. The measured damage was 42
    handler names missing from the "exists" set, every call in that third of
    the file unscanned, and - because check_file numbers the lines it is handed
    - every reported line number after the first phantom open shifted by up to
    2,476.

    That is the unbacked-attestation shape this repo's lesson book keeps
    naming: a gate nobody had ever driven against the constructs it claims to
    understand. test-checker.py was written for the same reason and is the
    model here. Each fixture below drives the REAL scanner over a source shaped
    like the trap, and asserts what the scanner must conclude.

    python3 tools/test-handler-calls.py

Exit code 0 = every fixture behaved, 1 = a rule regressed.
"""
import importlib.util
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_gate():
    path = os.path.join(ROOT, "tools", "check-handler-calls.py")
    spec = importlib.util.spec_from_file_location("check_handler_calls", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# (name, source, predicate(stripped_text, original_source) -> (ok, detail))
def _visible(needle):
    def check(stripped, _src):
        return (needle in stripped,
                f"expected {needle!r} to survive the strip")
    return check


def _hidden(needle):
    def check(stripped, _src):
        return (needle not in stripped,
                f"expected {needle!r} to be stripped as prose")
    return check


def _line_count_preserved(stripped, src):
    want = len(src.splitlines())
    got = len(stripped.splitlines())
    return (want == got,
            f"line count must survive the strip so reported line numbers are "
            f"true: {want} in, {got} out")


FIXTURES = [
    # -- the two halves of the nocloud defect --------------------------------
    ("a line comment mentioning /* does NOT open a block comment",
     'on qsRouteA\n'
     '   -- shared route layer FIRST, so /_qs/* and OPTIONS work\n'
     '   qsCallOne\n'
     'end qsRouteA\n',
     _visible("qsCallOne")),

    ("a string containing */ does NOT close a block comment",
     '/* a real comment mentioning qsHiddenOne\n'
     '   still inside the comment: qsHiddenTwo */\n'
     'on qsRouteB\n'
     '   put "Content-Range: bytes */" & tCrlf into tHead\n'
     '   qsCallTwo\n'
     'end qsRouteB\n',
     _visible("qsCallTwo")),

    ("prose inside a real block comment is still stripped",
     '/* changelog: qsGhostHandler was renamed\n'
     '   and sxGhostCall no longer exists */\n'
     'on qsRealOne\n'
     '   qsCallThree\n'
     'end qsRealOne\n',
     _hidden("sxGhostCall")),

    ("a route glob in a comment does not swallow the rest of the file",
     '-- the /_qs/* endpoints\n'
     'on qsRouteC\n'
     '   qsCallFour\n'
     'end qsRouteC\n',
     _visible("qsCallFour")),

    # -- the constructs the scanner has always had to respect ----------------
    ("a handler name in a -- line comment is prose, not a call",
     'on qsRouteD\n'
     '   -- this mentions sxGhostTwo in prose\n'
     '   qsCallFive\n'
     'end qsRouteD\n',
     _hidden("sxGhostTwo")),

    ("a handler name in a string literal is prose, not a call",
     'on qsRouteE\n'
     '   answer "sxGhostThree failed"\n'
     '   qsCallSix\n'
     'end qsRouteE\n',
     _hidden("sxGhostThree")),

    ("a # comment at line start is prose",
     'on qsRouteF\n'
     '   # sxGhostFour is only mentioned here\n'
     '   qsCallSeven\n'
     'end qsRouteF\n',
     _hidden("sxGhostFour")),

    ("a // comment is prose",
     'on qsRouteG\n'
     '   // sxGhostFive is only mentioned here\n'
     '   qsCallEight\n'
     'end qsRouteG\n',
     _hidden("sxGhostFive")),

    ("a -- inside a string literal does not truncate the line",
     'on qsRouteH\n'
     '   put "a--b" & qsTail into tX\n'
     'end qsRouteH\n',
     _visible("qsTail")),

    ("a // inside a string literal does not truncate the line",
     'on qsRouteI\n'
     '   put "http://host/" & qsPath into tX\n'
     'end qsRouteI\n',
     _visible("qsPath")),

    # -- the property that keeps reported line numbers true ------------------
    ("every line in yields exactly one line out (block comment)",
     '/* one\n   two\n   three */\non qsRouteJ\n   qsCallNine\nend qsRouteJ\n',
     _line_count_preserved),

    ("every line in yields exactly one line out (# comment)",
     '# one\n# two\non qsRouteK\n   qsCallTen\nend qsRouteK\n',
     _line_count_preserved),
]


def main():
    gate = load_gate()
    failures = []
    for name, source, predicate in FIXTURES:
        stripped = gate.strip_noise(source)
        ok, detail = predicate(stripped, source)
        status = "PASS" if ok else "FAIL"
        print(f"{status}  {name}")
        if not ok:
            failures.append(f"{name}: {detail}")

    # -- the system-level property, driven the way the build drives it -------
    # The lesson recorded in the root CLAUDE.md is that a gate must be
    # exercised through the PIPELINE, not only through the function its
    # docstring describes. So: run the real collector over the real tree and
    # assert the file that carried the defect contributes its handlers.
    defined = gate.collect_definitions()
    for name in ("qsCwDrain", "qsETagCore", "qsEditAppendRoute"):
        if name not in defined:
            failures.append(
                f"collect_definitions() lost '{name}' - a handler defined in "
                f"nocloud/src/nocloudquickshare.livecodescript past the line "
                f"where the phantom block comment used to open")
    print(f"PASS  the real tree contributes nocloud's post-4175 handlers"
          if not failures else "FAIL  the real tree scan")

    if failures:
        print()
        for f in failures:
            print("test-handler-calls: " + f)
        print(f"test-handler-calls: {len(failures)} failure(s)")
        return 1
    print(f"\ntest-handler-calls: all {len(FIXTURES)} fixtures behaved "
          f"({len(defined)} handlers known across the tree)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
