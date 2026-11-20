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
    "gpx_lcb_signatures", os.path.join(HERE, "tools", "check-lcb-signatures.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)

BUILTIN = ('foreign handler MCStringCreateWithBytes(in pBytes as Pointer, in pByteCount as CUInt, '
           'in pEncoding as CUInt, in pIsExternalRep as CBool, out rString as String) returns CBool '
           'binds to "<builtin>"\n')

# (label, file, old, new, text one of the problems must contain)
CASES = [
    ("a foreign parameter of the wrong type", "lcb",
     "_gpx_pad_rumble(in pPad as CInt, in pLow as CDouble, in pHigh as CDouble, in pMilliseconds as CInt)",
     "_gpx_pad_rumble(in pPad as CInt, in pLow as CInt, in pHigh as CDouble, in pMilliseconds as CInt)",
     "parameter 2 is declared CInt"),
    ("a foreign parameter dropped", "lcb",
     "_gpx_pad_rumble(in pPad as CInt, in pLow as CDouble, in pHigh as CDouble, in pMilliseconds as CInt)",
     "_gpx_pad_rumble(in pPad as CInt, in pLow as CDouble, in pHigh as CDouble)",
     "gpx_pad_rumble"),
    ("a foreign return of the wrong type", "lcb",
     '_gpx_pad_is_connected(in pPad as CInt) returns CInt binds',
     '_gpx_pad_is_connected(in pPad as CInt) returns CDouble binds',
     "gpx_pad_is_connected"),
    ("a bind to another handler's symbol", "lcb",
     '"c:gamepadxt>gpx_virtual_detach!cdecl"', '"c:gamepadxt>gpx_pad_is_connected!cdecl"',
     "gpx_pad_is_connected is bound twice"),
    ("a foreign handler off the mechanical name", "lcb",
     "private foreign handler _gpx_virtual_detach(", "private foreign handler _gpx_virtual_remove(",
     "must be named _gpx_virtual_detach"),
    # lc-compile -Werror refuses a one-word all-lowercase name, which is why
    # the foreign name carries the whole symbol: the short form must not return
    ("a foreign handler named without the shim's prefix", "lcb",
     "private foreign handler _gpx_start(", "private foreign handler _start(",
     "must be named _gpx_start"),
    ("an export nothing binds", "shim",
     "LC_API int gpx_abi_version(void)",
     "LC_API int gpx_new_thing(void) { return 0; }\nLC_API int gpx_abi_version(void)",
     "gpx_new_thing is exported with no foreign handler"),
    ("a text result returned as ZStringNative", "lcb",
     "_gpx_library_version() returns Pointer", "_gpx_library_version() returns ZStringNative",
     "_gpx_library_version"),
    ("a text result returned as ZStringUTF8", "lcb",
     "_gpx_library_version() returns Pointer", "_gpx_library_version() returns ZStringUTF8",
     "_gpx_library_version"),
    ("a second engine builtin", "lcb", BUILTIN,
     BUILTIN + 'foreign handler MCStringCopy(in pS as String, out rS as String) returns CBool binds to "<builtin>"\n',
     "a foreign handler this gate cannot read"),
    ("the engine builtin declared twice", "lcb", BUILTIN, BUILTIN + BUILTIN,
     "MCStringCreateWithBytes must be declared exactly once"),
    ("a public handler off the mechanical name", "lcb",
     "public handler gpPadRumble(", "public handler gpPadShake(",
     "gpPadRumble"),
    ("a Boolean handed to the C side unconverted", "lcb",
     "_gpx_virtual_set_button(pPad, pButton, asInt(pDown))", "_gpx_virtual_set_button(pPad, pButton, pDown)",
     "gpVirtualSetButton"),
    ("public parameters in another order than the call", "lcb",
     "_gpx_virtual_set_button(pPad, pButton, asInt(pDown))", "_gpx_virtual_set_button(pButton, pPad, asInt(pDown))",
     "gpVirtualSetButton"),
    ("a text result not copied by textOf", "lcb",
     "      put _gpx_library_version() into tP\n   end unsafe\n   return textOf(tP)",
     "      put _gpx_library_version() into tP\n   end unsafe\n   return tP",
     "gpLibraryVersion"),
    ("a doc block without one of its parameters", "lcb",
     "pHigh: The strength of the light, fast motor, 0 to 1.\n\npMilliseconds: How long to rumble, 0 to 60000.\n\nReturns: True if the pad took it;",
     "pHigh: The strength of the light, fast motor, 0 to 1.\n\nReturns: True if the pad took it;",
     "gpPadRumble"),
    ("a doc block without a Summary", "lcb",
     "Summary: Makes a pad rumble.\n", "",
     "gpPadRumble"),
    ("an ABI bump in the shim only", "shim",
     "#define GPX_ABI_VERSION 1", "#define GPX_ABI_VERSION 2", "ABI"),
    ("an ABI bump in the binding's check only", "lcb",
     "   if tV is not 1 then", "   if tV is not 2 then", "ABI"),
    ("a handler missing from the engine self-test's sweep", "selftest",
     '      put "gpABIVersion" into tName\n      get gpABIVersion()\n', "",
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
