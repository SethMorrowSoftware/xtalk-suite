#!/usr/bin/env python3
"""test-smoke-coverage.py - prove tools/check-smoke-coverage.py FIRES.

A gate that cannot fail prints OK over anything (the suite root's "fixture
before gate"). Each case takes the REAL shim, smoke test and fuzz test,
breaks one of them one way in memory, and requires the gate to refuse the
result with a problem that names the break. The unbroken three must pass. A
case whose text is no longer in its file fails as "the fixture is stale".

The one this gate exists for is "an export the smoke test never calls": a
declaration is not a call (grep once counted six `extern`-declared,
never-called exports in box2dxt as covered), so two of the cases leave the
declaration in place and take away only the calls.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "xlx_smoke_coverage", os.path.join(HERE, "tools", "check-smoke-coverage.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)


def swap(old, new, count=1):
    def f(text):
        if old not in text:
            return None
        return text.replace(old, new, count)
    return f


def drop_calls(name):
    """Every CALL of `name` gone, its `extern` declaration kept."""
    def f(text):
        out, n = re.subn(r"(?m)^(?!extern\b)(.*?)\b%s\(" % name, r"\1uncalled(", text)
        while n:
            out, n = re.subn(r"(?m)^(?!extern\b)(.*?)\b%s\(" % name, r"\1uncalled(", out)
            if n == 0:
                break
        return out if out != text else None
    return f


# (label, file, mutation, text one of the problems must contain)
CASES = [
    ("a new export nothing declares or calls", "shim",
     swap("LC_API int xlx_abi_version(void)",
          "LC_API int xlx_new_thing(void) { return 0; }\nLC_API int xlx_abi_version(void)"),
     "export never called by the smoke test: xlx_new_thing"),
    ("an export whose signature changed under the tests", "shim",
     swap("LC_API void xlx_sheet_set_landscape(int sheet, int flag)",
          "LC_API void xlx_sheet_set_landscape(int sheet, int flag, int extra)"),
     "declaration block lacks"),
    ("a declaration edited by hand", "smoke",
     swap("extern void xlx_sheet_set_landscape(int sheet, int flag);",
          "extern int xlx_sheet_set_landscape(int sheet, int flag);"),
     "declaration block has a line the shim does not back"),
    ("an export declared but no longer called (smoke)", "smoke",
     drop_calls("xlx_sheet_set_landscape"),
     "export never called by the smoke test: xlx_sheet_set_landscape"),
    ("a second export declared but no longer called (smoke)", "smoke",
     drop_calls("xlx_set_temp_folder"),
     "export never called by the smoke test: xlx_set_temp_folder"),
    ("a call of a name the shim does not export", "smoke",
     swap('    xlx_set_temp_folder("");', '    xlx_set_temp_folder("");\n    xlx_no_such_call();'),
     "smoke test calls a name the shim does not export: xlx_no_such_call"),
    ("a marker pair removed (smoke)", "smoke",
     swap(GATE.DECL_END, "/* gone */"),
     "SHIM DECLARATIONS marker pair is missing"),
    ("a line dropped from the fuzz test's call table", "fuzz",
     lambda t: (lambda span: None if span is None else
                t[:span[1]] + "\n".join(l for l in span[0].split("\n") if "xlx_sheet_set_landscape" not in l)
                + t[span[2]:])(GATE.between(t, GATE.FUZZ_BEGIN, GATE.FUZZ_END)),
     "fuzz test: call table is stale"),
    ("the fuzz test's declarations edited by hand", "fuzz",
     swap("extern void xlx_sheet_set_landscape(int sheet, int flag);",
          "extern int xlx_sheet_set_landscape(int sheet, int flag);"),
     "fuzz test: declaration block is stale"),
    ("the fuzz table never walked", "fuzz",
     lambda t: re.sub(r"->\s*call\s*\(", "->skip(", t) if re.search(r"->\s*call\s*\(", t) else None,
     "nothing draws from k_fuzz"),
    ("an LC_API line the parser cannot read", "shim",
     swap("LC_API int xlx_abi_version(void)", "LC_API int (*xlx_hook)(void);\nLC_API int xlx_abi_version(void)"),
     "LC_API lines in the shim but"),
]


def main():
    texts = {
        "shim": open(GATE.SHIM, encoding="utf-8").read(),
        "smoke": open(GATE.SMOKE, encoding="utf-8").read(),
        "fuzz": open(GATE.FUZZ, encoding="utf-8").read(),
    }

    def run(t):
        problems, _ = GATE.check(t["shim"], t["smoke"])
        if len(GATE.parse_exports(t["shim"])) >= GATE.MIN_EXPORTS:
            problems = problems + GATE.check_fuzz(t["shim"], t["fuzz"])
        return problems

    failed = 0
    problems = run(texts)
    if problems:
        print("FAIL the unbroken files must pass: %s" % problems[:3])
        failed += 1
    for label, which, mutate, want in CASES:
        new = mutate(texts[which])
        if new is None or new == texts[which]:
            print("FAIL %s: the fixture is stale (its text is not in the %s test or shim)" % (label, which))
            failed += 1
            continue
        mutated = dict(texts)
        mutated[which] = new
        problems = run(mutated)
        if not problems:
            print("FAIL %s: the gate passed it" % label)
            failed += 1
        elif not any(want in p for p in problems):
            print("FAIL %s: refused, but no problem says %r: %s" % (label, want, problems[:3]))
            failed += 1
    if failed:
        print("test-smoke-coverage: FAILED (%d of %d)" % (failed, len(CASES) + 1))
        return 1
    print("test-smoke-coverage: OK (%d mutations each refused by name; the unbroken files pass)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
