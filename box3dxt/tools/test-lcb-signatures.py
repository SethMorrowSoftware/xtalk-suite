#!/usr/bin/env python3
"""test-lcb-signatures.py - prove tools/check-lcb-signatures.py FIRES.

A gate that cannot fail prints OK over anything (the suite root's "fixture
before gate"). Each case takes the REAL binding, shim and engine self-test,
breaks one of them one way in memory, and requires the gate to refuse the
result with a problem that names the break. The unbroken three must pass, so
a gate that refuses everything fails here too. A case whose `old` text is no
longer in the file fails as "the fixture is stale", never as a pass.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "b3x_lcb_signatures", os.path.join(HERE, "tools", "check-lcb-signatures.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)

BUILTIN = ('foreign handler MCStringCreateWithBytes(in pBytes as Pointer, in pByteCount as CUInt, '
           'in pEncoding as CUInt, in pIsExternalRep as CBool, out rString as String) returns CBool '
           'binds to "<builtin>"\n')

DATA_BUILTIN = ('foreign handler MCDataCreateWithBytes(in pBytes as Pointer, in pByteCount as CUInt, '
                'out rData as Data) returns CBool binds to "<builtin>"\n')

# (label, file, old, new, text one of the problems must contain)
CASES = [
    ("a foreign parameter of the wrong type", "lcb",
     "_world_step(in pWorld as CInt, in pSeconds as CDouble, in pSubsteps as CInt)",
     "_world_step(in pWorld as CInt, in pSeconds as CInt, in pSubsteps as CInt)",
     "parameter 2 is declared CInt"),
    ("a foreign parameter dropped", "lcb",
     "_world_step(in pWorld as CInt, in pSeconds as CDouble, in pSubsteps as CInt)",
     "_world_step(in pWorld as CInt, in pSeconds as CDouble)",
     "b3x_world_step"),
    ("a foreign return of the wrong type", "lcb",
     '_world_is_valid(in pWorld as CInt) returns CInt binds',
     '_world_is_valid(in pWorld as CInt) returns CDouble binds',
     "b3x_world_is_valid"),
    ("a bind to another handler's symbol", "lcb",
     '"c:box3dxt>b3x_world_destroy!cdecl"', '"c:box3dxt>b3x_world_is_valid!cdecl"',
     "b3x_world_is_valid is bound twice"),
    ("a foreign handler off the mechanical name", "lcb",
     "private foreign handler _world_destroy(", "private foreign handler _world_remove(",
     "must be named _world_destroy"),
    ("an export nothing binds", "shim",
     "LC_API int b3x_abi_version(void)",
     "LC_API int b3x_new_thing(void) { return 0; }\nLC_API int b3x_abi_version(void)",
     "b3x_new_thing is exported with no foreign handler"),
    ("a text result returned as ZStringNative", "lcb",
     "_library_version() returns Pointer", "_library_version() returns ZStringNative",
     "_library_version"),
    ("a second engine builtin", "lcb", BUILTIN,
     BUILTIN + 'foreign handler MCStringCopy(in pS as String, out rS as String) returns CBool binds to "<builtin>"\n',
     "a foreign handler this gate cannot read"),
    ("the engine builtin declared twice", "lcb", BUILTIN, BUILTIN + BUILTIN,
     "MCStringCreateWithBytes must be declared exactly once"),
    ("the data builtin declared twice", "lcb", DATA_BUILTIN, DATA_BUILTIN + DATA_BUILTIN,
     "MCDataCreateWithBytes must be declared exactly once"),
    ("the data builtin in another spelling", "lcb", DATA_BUILTIN,
     DATA_BUILTIN.replace("in pByteCount as CUInt", "in pByteCount as CInt"),
     "a foreign handler this gate cannot read"),
    ("the picture copied as text", "lcb",
     "public handler b3RenderPixels() returns Data", "public handler b3RenderPixels() returns String",
     "b3RenderPixels returns String, but b3x_render_pixels gives bytes"),
    ("a text result copied as bytes", "lcb",
     "public handler b3RenderCamera() returns String", "public handler b3RenderCamera() returns Data",
     "b3RenderCamera returns Data, but b3x_render_camera gives text"),
    ("the picture not copied by dataOf", "lcb",
     "      put _render_pixels() into tP\n   end unsafe\n   return dataOf(tP)",
     "      put _render_pixels() into tP\n   end unsafe\n   return textOf(tP)",
     "does not end `return dataOf(tP)`"),
    ("dataOf measuring with something else", "lcb",
     "      put _render_byte_count() into tLength\n      put MCDataCreateWithBytes",
     "      put _text_length(pBytes) into tLength\n      put MCDataCreateWithBytes",
     "dataOf() must measure with _render_byte_count"),
    ("a public handler off the mechanical name", "lcb",
     "public handler b3WorldStep(", "public handler b3WorldAdvance(",
     "b3WorldStep"),
    ("a Boolean handed to the C side unconverted", "lcb",
     "_body_set_awake(pBody, asInt(pFlag))", "_body_set_awake(pBody, pFlag)",
     "b3BodySetAwake"),
    ("public parameters in another order than the call", "lcb",
     "_body_set_awake(pBody, asInt(pFlag))", "_body_set_awake(asInt(pFlag), pBody)",
     "b3BodySetAwake"),
    ("a text result not copied by textOf", "lcb",
     "      put _library_version() into tP\n   end unsafe\n   return textOf(tP)",
     "      put _library_version() into tP\n   end unsafe\n   return tP",
     "b3LibraryVersion"),
    ("a doc block without one of its parameters", "lcb",
     "pSubsteps: How many sub-steps the solver takes, 1 to 64. 4 is the usual\nchoice.\n\n", "",
     "b3WorldStep"),
    ("a doc block without a Summary", "lcb",
     "Summary: Advances a world by a slice of time.\n", "",
     "b3WorldStep"),
    ("an ABI bump in the shim only", "shim",
     "#define B3X_ABI_VERSION 3", "#define B3X_ABI_VERSION 4", "ABI"),
    ("an ABI bump in the binding's check only", "lcb",
     "   if tV is not 3 then", "   if tV is not 4 then", "ABI"),
    ("the ABI handler's doc block left at the old ABI", "lcb",
     "Returns: The ABI number; this binding needs 3.", "Returns: The ABI number; this binding needs 2.",
     "b3ABIVersion's doc block"),
    ("the ABI handler's doc block silent on the ABI", "lcb",
     "Returns: The ABI number; this binding needs 3.", "Returns: The ABI number.",
     "b3ABIVersion's doc block"),
    ("a handler missing from the engine self-test's sweep", "selftest",
     '      put "b3ABIVersion" into tName\n      get b3ABIVersion()\n', "",
     "sweep"),
]


def main():
    texts = {
        "lcb": open(GATE.LCB, encoding="utf-8").read(),
        "shim": open(GATE.SHIM, encoding="utf-8").read(),
        "selftest": open(GATE.SELFTEST, encoding="utf-8").read(),
    }
    failed = 0
    problems, _ = GATE.check(texts["lcb"], texts["shim"], texts["selftest"])
    if problems:
        print("FAIL the unbroken files must pass: %s" % problems[:3])
        failed += 1
    for label, which, old, new, want in CASES:
        if texts[which].count(old) < 1:
            print("FAIL %s: the fixture is stale (its text is not in the %s)" % (label, which))
            failed += 1
            continue
        mutated = dict(texts)
        mutated[which] = texts[which].replace(old, new, 1)
        problems, _ = GATE.check(mutated["lcb"], mutated["shim"], mutated["selftest"])
        if not problems:
            print("FAIL %s: the gate passed it" % label)
            failed += 1
        elif not any(want in p for p in problems):
            print("FAIL %s: refused, but no problem says %r: %s" % (label, want, problems[:3]))
            failed += 1
    if failed:
        print("test-lcb-signatures: FAILED (%d of %d)" % (failed, len(CASES) + 1))
        return 1
    print("test-lcb-signatures: OK (%d mutations each refused by name; the unbroken files pass)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
