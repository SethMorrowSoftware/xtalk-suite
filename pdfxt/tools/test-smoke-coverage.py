#!/usr/bin/env python3
"""test-smoke-coverage.py - prove tools/check-smoke-coverage.py FIRES.

A gate that cannot fail prints OK over anything (the suite root's "fixture
before gate"). Each case takes the REAL shim and smoke test, breaks one of
them one way in memory, and requires the gate to refuse the result with a
problem that names the break. The unbroken pair must pass. A case whose `old`
text is no longer in the file fails as "the fixture is stale", never as a
pass.
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "pdx_smoke_coverage", os.path.join(HERE, "tools", "check-smoke-coverage.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)

# (label, file, old, new, text one of the problems must contain)
CASES = [
    ("a new export the test never heard of", "shim",
     "LC_API int pdx_open_count(void)",
     "LC_API int pdx_new_thing(int doc) { return doc; }\nLC_API int pdx_open_count(void)",
     "pdx_new_thing"),
    ("a return type changed in the shim only", "shim",
     "LC_API int pdx_page_count(int doc)", "LC_API double pdx_page_count(int doc)",
     "double pdx_page_count(int doc);"),
    ("a parameter added in the shim only", "shim",
     "LC_API int pdx_file_version(int doc)", "LC_API int pdx_file_version(int doc, int extra)",
     "int pdx_file_version(int doc, int extra);"),
    ("a declaration dropped from the block", "smoke",
     "int pdx_is_open(int doc);\n", "",
     "the declaration block lacks: int pdx_is_open(int doc);"),
    ("a declaration the shim does not define", "smoke",
     "int pdx_is_open(int doc);\n", "int pdx_is_open(int doc);\nint pdx_ghost(void);\n",
     "pdx_ghost"),
    ("the block out of the shim's order", "smoke",
     "int pdx_data_length(void);\nvoid pdx_data_release(void);\n",
     "void pdx_data_release(void);\nint pdx_data_length(void);\n",
     "not in the shim's order"),
    ("the end marker gone", "smoke",
     GATE.END, "", "no single DECLARATIONS block"),
    ("an export without the prefix", "shim",
     "LC_API int pdx_open_count(void)", "LC_API int open_count(void)",
     "without the pdx_ prefix"),
]

# Exports whose every call is removed in turn: the name must then be reported
# as never called, although its declaration still stands.
UNCALLED = ["pdx_page_links", "pdx_render_page_region", "pdx_close_all", "pdx_page_char_at"]


def main():
    shim = open(GATE.SHIM, encoding="utf-8").read()
    smoke = open(GATE.SMOKE, encoding="utf-8").read()
    texts = {"shim": shim, "smoke": smoke}
    failed = 0
    total = 1
    problems, exps = GATE.check(shim, smoke)
    if problems:
        print("FAIL the unbroken files must pass: %s" % problems[:3])
        failed += 1
    for label, which, old, new, want in CASES:
        total += 1
        if texts[which].count(old) < 1:
            print("FAIL %s: the fixture is stale (its text is not in the %s)" % (label, which))
            failed += 1
            continue
        mutated = dict(texts)
        mutated[which] = texts[which].replace(old, new, 1)
        problems, _ = GATE.check(mutated["shim"], mutated["smoke"])
        if not problems:
            print("FAIL %s: the gate passed it" % label)
            failed += 1
        elif not any(want in p for p in problems):
            print("FAIL %s: refused, but no problem says %r: %s" % (label, want, problems[:3]))
            failed += 1
    span = GATE.block_of(smoke)
    for name in UNCALLED:
        total += 1
        body = smoke[span[1]:]
        if not re.search(r"\b%s\s*\(" % name, body):
            print("FAIL %s: the fixture is stale (the test does not call it)" % name)
            failed += 1
            continue
        # A call renamed away, then the name left in a comment and in a
        # string: neither is a call.
        cut = re.sub(r"\b%s(\s*\()" % name, r"other_call\1", body)
        cut += '\n/* %s(1); */\nstatic const char *k_note = "%s(1)";\n' % (name, name)
        problems, _ = GATE.check(shim, smoke[:span[1]] + cut)
        if not any(("%s is never called" % name) in p for p in problems):
            print("FAIL %s uncalled: the gate did not say so: %s" % (name, problems[:3]))
            failed += 1
    total += 1
    problems, _ = GATE.check("LC_API int pdx_only(void) { return 1; }\n", smoke)
    if not any("cannot read it" in p for p in problems):
        print("FAIL a shim with one export: the gate did not call itself blind")
        failed += 1
    if failed:
        print("test-smoke-coverage: FAILED (%d of %d)" % (failed, total))
        return 1
    print("test-smoke-coverage: OK (%d cases each refused by name; the unbroken files pass)" % (total - 1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
