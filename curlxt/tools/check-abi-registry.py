#!/usr/bin/env python3
"""check-abi-registry.py - prove src/curl.lcb cannot drift from src/cux_abi.h.

The header is the SINGLE SOURCE OF TRUTH. Every number the binding uses is a
`#define` there, and the .lcb mirrors each under a mechanically derived name:

    CUX_ABI_VERSION        -> kABIVersion
    CUX_STATE_<NAME>       -> kState<Name>
    CUX_RESULT_CANCELLED   -> kResultCancelled
    CUO_<NAME>             -> kOpt<Name>
    CUI_<NAME>             -> kInfo<Name>
    CUT_<NAME>             -> kText<Name>

so a missing constant, a wrong value and a swap of two values all fail here
rather than on an engine. It also proves the FOREIGN SURFACE: every function
the header declares (bar the cux_selftest_throw test hook) has exactly one
`private foreign handler _cux_x ... binds to "c:curlxt>cux_x!cdecl"` in the
.lcb, and nothing else is bound. And it proves every option, info and text
id the binding's name tables hand out (`_optionId`, `_infoId`, `_textId`) is
one of the constants it mirrors, with no name listed twice.

    python3 tools/check-abi-registry.py [cux_abi.h] [curl.lcb]

Exit 0 = in sync, 1 = drift. tools/test-abi-registry.py mutation-proves it.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PREFIXES = (("CUX_STATE_", "kState"), ("CUX_RESULT_", "kResult"),
            ("CUO_", "kOpt"), ("CUI_", "kInfo"), ("CUT_", "kText"))
TEST_HOOKS = {"cux_selftest_throw"}


def camel(rest):
    return "".join(w.capitalize() for w in rest.lower().split("_"))


def check(header_path, lcb_path):
    errors = []
    with open(header_path, encoding="utf-8") as fh:
        hdr = fh.read()
    with open(lcb_path, encoding="utf-8") as fh:
        lcb = fh.read()
    defines = {m.group(1): int(m.group(2)) for m in
               re.finditer(r"^#define\s+(\w+)\s+\(?(-?\d+)\)?", hdr, re.M)}
    consts = {}
    for m in re.finditer(r"^constant\s+(k\w+)\s+is\s+(-?\d+)\s*$", lcb, re.M):
        if m.group(1) in consts:
            errors.append("constant %s is declared twice" % m.group(1))
        consts[m.group(1)] = int(m.group(2))

    expected = {"kABIVersion": ("CUX_ABI_VERSION", defines.get("CUX_ABI_VERSION"))}
    for name, value in defines.items():
        for cpre, lpre in PREFIXES:
            if name.startswith(cpre):
                expected[lpre + camel(name[len(cpre):])] = (name, value)
    if len(expected) < 40:
        errors.append("only %d mirrored defines parsed: the parser is blind" % len(expected))
    for lname, (cname, value) in sorted(expected.items()):
        if lname not in consts:
            errors.append("%s (%s = %s) has no `constant %s is %s` in the .lcb"
                          % (cname, cname, value, lname, value))
        elif consts[lname] != value:
            errors.append("%s is %s in the .lcb but %s = %s in the header"
                          % (lname, consts[lname], cname, value))
    mirrored = {k for k in consts if k.startswith(("kState", "kResult", "kOpt", "kInfo", "kText"))}
    for extra in sorted(mirrored - set(expected)):
        errors.append("constant %s mirrors nothing in the header" % extra)

    # the foreign surface
    declared = set(re.findall(r"^CUX_API\s+\w+\s+CUX_CALL\s+(cux_\w+)\(", hdr, re.M))
    if len(declared) < 15:
        errors.append("only %d header functions parsed: the parser is blind" % len(declared))
    binds = re.findall(r'^private foreign handler _(cux_\w+)\(.*binds to "c:curlxt>(cux_\w+)!cdecl"',
                       lcb, re.M)
    bound = {}
    for handler, symbol in binds:
        if handler != symbol:
            errors.append("foreign handler _%s binds to %s" % (handler, symbol))
        if symbol in bound:
            errors.append("%s is bound twice" % symbol)
        bound[symbol] = True
    for sym in sorted(declared - TEST_HOOKS - set(bound)):
        errors.append("header function %s is never bound by the .lcb" % sym)
    for sym in sorted(set(bound) - declared):
        errors.append("the .lcb binds %s, which the header does not declare" % sym)

    # the name tables
    for handler, prefix in (("_optionId", "kOpt"), ("_infoId", "kInfo"), ("_textId", "kText")):
        start = lcb.find("private handler %s(" % handler)
        if start < 0:
            errors.append("name table %s is missing" % handler)
            continue
        body = lcb[start:lcb.index("end handler", start)]
        pairs = re.findall(r'pName is "(\w+)" then\s+return (k\w+)', body)
        if not pairs:
            errors.append("name table %s lists no names" % handler)
        names = [n for n, _ in pairs]
        for n in sorted(set(x for x in names if names.count(x) > 1)):
            errors.append("%s lists %r twice" % (handler, n))
        ids = [k for _, k in pairs]
        for k in sorted(set(x for x in ids if ids.count(x) > 1)):
            errors.append("%s maps two names to %s" % (handler, k))
        for _, k in pairs:
            if not k.startswith(prefix) or k not in consts:
                errors.append("%s returns %s, not a %s* constant" % (handler, k, prefix))
        missing = sorted(k for k in mirrored if k.startswith(prefix) and k not in ids)
        for k in missing:
            errors.append("%s gives no name for %s" % (handler, k))
    return errors, len(expected), len(declared)


def main(argv):
    header = argv[1] if len(argv) > 1 else os.path.join(HERE, "src", "cux_abi.h")
    lcb = argv[2] if len(argv) > 2 else os.path.join(HERE, "src", "curl.lcb")
    errors, n_consts, n_funcs = check(header, lcb)
    if errors:
        print("check-abi-registry: %d problem(s)" % len(errors))
        for e in errors:
            print("  " + e)
        return 1
    print("check-abi-registry: OK (%d constants and %d foreign functions in sync)"
          % (n_consts, n_funcs))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
