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
    "r3x_smoke_coverage", os.path.join(HERE, "tools", "check-smoke-coverage.py"))
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
    pat = re.compile(r"(?m)^(?!extern\b)(.*?)\b%s\(" % name)

    def f(text):
        out = text
        while True:
            out, n = pat.subn(r"\1uncalled(", out)
            if n == 0:
                break
        return out if out != text else None
    return f


def in_span(begin, end, edit):
    """Apply `edit` to the generated span between two markers only."""
    def f(text):
        span = GATE.between(text, begin, end)
        if span is None:
            return None
        new = edit(span[0])
        return None if new == span[0] else text[:span[1]] + new + text[span[2]:]
    return f


# (label, file, mutation, text one of the problems must contain)
CASES = [
    ("a new export nothing declares or calls", "shim",
     swap("LC_API int r3x_abi_version(void)",
          "LC_API int r3x_new_thing(void) { return 0; }\nLC_API int r3x_abi_version(void)"),
     "export never called by the smoke test: r3x_new_thing"),
    ("an export whose signature changed under the tests", "shim",
     swap("LC_API void r3x_texture_set_smooth(int texture, int flag)",
          "LC_API void r3x_texture_set_smooth(int texture, int flag, int extra)"),
     "declaration block lacks"),
    ("an export whose return type changed under the tests", "shim",
     swap("LC_API int r3x_abi_version(void)", "LC_API double r3x_abi_version(void)"),
     "declaration block lacks: extern double r3x_abi_version(void);"),
    ("a declaration edited by hand", "smoke",
     swap("extern void r3x_texture_set_smooth(int texture, int flag);",
          "extern int r3x_texture_set_smooth(int texture, int flag);"),
     "declaration block has a line the shim does not back"),
    ("an export declared but no longer called (smoke)", "smoke",
     drop_calls("r3x_scene_set_fog"),
     "export never called by the smoke test: r3x_scene_set_fog"),
    ("a second export declared but no longer called (smoke)", "smoke",
     drop_calls("r3x_texture_set_smooth"),
     "export never called by the smoke test: r3x_texture_set_smooth"),
    ("an export named only in a comment and a string", "smoke",
     lambda t: (lambda u: None if u is None else
                u + '\n/* r3x_scene_set_fog(1) */\nstatic const char *k_note = "r3x_scene_set_fog(1)";\n')(
         drop_calls("r3x_scene_set_fog")(t)),
     "export never called by the smoke test: r3x_scene_set_fog"),
    ("a call of a name the shim does not export", "smoke",
     swap("    r3x_scene_set_fog(s, 0, 0, 255, 1, 5);",
          "    r3x_scene_set_fog(s, 0, 0, 255, 1, 5);\n    r3x_no_such_call();"),
     "smoke test calls a name the shim does not export: r3x_no_such_call"),
    ("a declaration written by hand outside the block", "smoke",
     lambda t: t + "\nextern int r3x_abi_version(void);\n",
     "declares a shim export by hand"),
    ("a marker pair removed (smoke)", "smoke",
     swap(GATE.DECL_END, "/* gone */"),
     "SHIM DECLARATIONS marker pair is missing"),
    ("a line dropped from the fuzz test's call table", "fuzz",
     in_span(GATE.FUZZ_BEGIN, GATE.FUZZ_END,
             lambda s: "\n".join(l for l in s.split("\n") if "r3x_scene_set_fog" not in l)),
     "fuzz test: call table is stale"),
    ("a thunk's arguments edited by hand", "fuzz",
     in_span(GATE.FUZZ_BEGIN, GATE.FUZZ_END,
             lambda s: s.replace("r3x_texture_set_smooth(fz_int(), fz_int())", "r3x_texture_set_smooth(1, 1)")),
     "fuzz test: call table is stale"),
    ("the fuzz test's declarations edited by hand", "fuzz",
     swap("extern void r3x_texture_set_smooth(int texture, int flag);",
          "extern int r3x_texture_set_smooth(int texture, int flag);"),
     "fuzz test: declaration block is stale"),
    ("the fuzz table never walked", "fuzz",
     lambda t: (lambda u: None if u == t else u)(re.sub(r"k_fuzz_calls\[c\]\(\);", "(void)c;", t)),
     "nothing draws from k_fuzz_calls"),
    ("a marker pair removed (fuzz)", "fuzz",
     swap(GATE.FUZZ_END, "/* gone */"),
     "marker pair is missing"),
    ("an LC_API line the parser cannot read", "shim",
     swap("LC_API int r3x_abi_version(void)",
          "LC_API int (*r3x_hook)(void);\nLC_API int r3x_abi_version(void)"),
     "LC_API lines in the shim but"),
    ("an export defined twice", "shim",
     swap("LC_API int r3x_abi_version(void)",
          "LC_API int r3x_thread_count(void) { return 0; }\nLC_API int r3x_abi_version(void)"),
     "defined twice"),
    ("a parameter kind the fuzz test cannot make", "shim",
     swap("LC_API void r3x_texture_set_smooth(int texture, int flag)",
          "LC_API void r3x_texture_set_smooth(int texture, float flag)"),
     "the fuzz test cannot make a 'float'"),
    ("a shim the scanner cannot see into", "shim",
     lambda t: t.replace("\nLC_API ", "\nEXPORTED "),
     "the scanner is blind"),
]


def main():
    texts = {}
    for key, path in (("shim", GATE.SHIM), ("smoke", GATE.SMOKE), ("fuzz", GATE.FUZZ)):
        with open(path, encoding="utf-8") as f:
            texts[key] = f.read()

    def run(t):
        return GATE.check(t["shim"], t["smoke"], t["fuzz"])[0]

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
