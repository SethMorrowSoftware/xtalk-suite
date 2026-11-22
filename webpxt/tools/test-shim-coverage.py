#!/usr/bin/env python3
"""test-shim-coverage.py - prove tools/check-shim-coverage.py FIRES.

A gate that cannot fail prints OK over anything (the suite root's "fixture
before gate"). Each case takes this member's REAL shim, smoke test, binding,
linker map and engine self-test, breaks one of them one way in memory, and
requires the gate to refuse the result with a problem that names the break.
The unbroken set must pass. The breaks are found in the files, not typed
(the first export, the first public handler), so the same file serves every
member that carries it; a case that finds nothing to break fails as "the
fixture is stale".
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location("shim_coverage", os.path.join(HERE, "tools", "check-shim-coverage.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)


def main():
    files = GATE.member_files(HERE)
    member = files["member"]
    real = {key: GATE.read(files[key]) for key in ("shim", "smoke", "lcb", "map", "engine")}
    real["declared"] = [GATE.read(path) for path in files["declared"]]
    failures = []

    problems, exports, public = GATE.check(real, member)
    if problems:
        failures.append("the unbroken files do not pass: " + "; ".join(problems[:3]))

    shim = GATE.strip_c(real["shim"])
    macro = re.search(r"(?m)^\s*#\s*define\s+([A-Z][A-Z0-9]*_API)\b", shim).group(1)
    prefix = macro[:-4].lower() + "_"
    # An export with parameters, so that cutting its calls cannot be undone
    # by a declaration that looks the same: the last one the shim defines.
    names = re.findall(r"(?m)^%s\s+[^;{()]*?\b(%s\w+)\s*\(" % (macro, prefix), shim)
    victim = names[-1]
    first = names[0]
    handler = re.findall(r"(?m)^public handler\s+(\w+)\s*\(", real["lcb"])[-1]
    abi_line = re.search(r"(?m)^(\s*#\s*define\s+[A-Z][A-Z0-9]*_ABI_VERSION\s+)(\d+)\s*$", real["shim"])

    def with_(key, new):
        if new is None or new == real[key]:
            return None
        broken = dict(real)
        broken[key] = new
        return broken

    def drop_calls(text, name):
        """Every CALL of `name` gone, an `extern` declaration of it kept."""
        return re.sub(r"(?m)^(?![ \t]*extern\b)(.*)$", lambda m: re.sub(r"\b%s\s*\(" % name, "uncalled(", m.group(1)), text)

    cases = [
        ("a new export nothing calls or binds",
         with_("shim", real["shim"].replace("%s int %sabi_version(void)" % (macro, prefix),
                                            "%s int %snew_thing(void) { return 0; }\n%s int %sabi_version(void)"
                                            % (macro, prefix, macro, prefix), 1)),
         ["export never called by the smoke test: %snew_thing" % prefix,
          "export the binding never binds: %snew_thing" % prefix]),
        ("an export the smoke test declares but no longer calls",
         with_("smoke", drop_calls(real["smoke"], victim)),
         ["export never called by the smoke test: " + victim]),
        ("an export named only in a comment and a string of the smoke test",
         with_("smoke", drop_calls(real["smoke"], victim) + '\n/* %s(1) */\nstatic const char *k_label = "%s(";\n'
               % (victim, victim)),
         ["export never called by the smoke test: " + victim]),
        ("a bind removed from the binding",
         with_("lcb", re.sub(r'(?m)^private foreign handler .*c:%s>%s!cdecl"\n' % (member, victim), "", real["lcb"], count=1)),
         ["export the binding never binds: " + victim]),
        ("a bind to a name the shim does not define",
         with_("lcb", real["lcb"].replace('c:%s>%s!cdecl"' % (member, victim), 'c:%s>%s_renamed!cdecl"' % (member, victim), 1)),
         ["bind to a name the shim does not define: %s_renamed" % victim]),
        ("a bind written twice",
         with_("lcb", re.sub(r'(?m)^(private foreign handler )(\w+)(.*c:%s>%s!cdecl"\n)' % (member, first),
                             r"\1\2\3\1\2_again\3", real["lcb"], count=1)),
         ["export bound twice in the binding: " + first]),
        ("a bind to another library",
         with_("lcb", real["lcb"].replace('c:%s>%s!cdecl"' % (member, first), 'c:other>%s!cdecl"' % first, 1)),
         ["bind to the library 'other'"]),
        ("the shim's ABI number bumped alone",
         with_("shim", real["shim"].replace(abi_line.group(0), abi_line.group(1) + str(int(abi_line.group(2)) + 1), 1)
               if abi_line else None),
         ["the binding's checkABI() compares with", "the binding's error says it needs"]),
        ("the binding's comparison bumped, its sentence left",
         with_("lcb", re.sub(r"if tV is not (\d+) then", lambda m: "if tV is not %d then" % (int(m.group(1)) + 1),
                             real["lcb"], count=1)),
         ["the binding's checkABI() compares with"]),
        ("the linker map exporting another pattern",
         with_("map", real["map"].replace(prefix + "*;", "other_*;", 1)),
         ["does not export the pattern " + prefix + "*"]),
        ("a public handler the engine sweep never names",
         with_("engine", real["engine"].replace('put "%s" into tName' % handler, 'put "somethingElse" into tName', 1)),
         ["public handler missing from the engine sweep: " + handler,
          "engine sweep names a handler the binding does not have: somethingElse"]),
        ("a sweep line that names one handler and calls another",
         with_("engine", re.sub(r'(put "%s" into tName\s*\n\s*)(.*)' % handler, r"\1get 1 + 1", real["engine"], count=1)),
         ["engine sweep names %s and then calls something else" % handler]),
        ("a new public handler the sweep does not have",
         with_("lcb", real["lcb"].replace("\nend library", "\npublic handler %sBrandNew() returns nothing\nend handler\n\nend library"
                                          % handler[:2], 1)),
         ["public handler missing from the engine sweep: %sBrandNew" % handler[:2]]),
        ("the sweep gone",
         with_("engine", real["engine"].replace("command sweepEveryHandler", "command sweepSomethingElse", 1)),
         ["has no `command sweepEveryHandler`"]),
    ]
    for label, broken, wanted in cases:
        if broken is None:
            failures.append("%s: the fixture is stale (nothing to break)" % label)
            continue
        try:
            found, _, _ = GATE.check(broken, member)
        except GATE.Blind as e:
            found = ["BLIND: %s" % e]
        for want in wanted:
            if not any(want in p for p in found):
                failures.append("%s: the gate did not say '%s' (it said: %s)" % (label, want, "; ".join(found[:3]) or "OK"))

    # A blind gate refuses to answer.
    for label, key, new in (("a shim with no exports", "shim", re.sub(r"(?m)^%s\b" % macro, "static", real["shim"])),
                            ("a binding with no public handlers", "lcb", real["lcb"].replace("public handler", "handler"))):
        broken = dict(real)
        broken[key] = new
        try:
            GATE.check(broken, member)
            failures.append("%s: the gate answered instead of refusing" % label)
        except GATE.Blind:
            pass

    if failures:
        print("test-shim-coverage: %d FAILURE(S)" % len(failures))
        for f in failures:
            print("  " + f)
        return 1
    print("test-shim-coverage: OK (%d breaks refused by name, 2 blind inputs refused, the real files pass)" % len(cases))
    return 0


if __name__ == "__main__":
    sys.exit(main())
