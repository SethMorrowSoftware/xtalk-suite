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
    "aux_lcb_signatures", os.path.join(HERE, "tools", "check-lcb-signatures.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)

BUILTIN = ('foreign handler MCStringCreateWithBytes(in pBytes as Pointer, in pByteCount as CUInt, '
           'in pEncoding as CUInt, in pIsExternalRep as CBool, out rString as String) returns CBool '
           'binds to "<builtin>"\n')
DATA_PTR = 'foreign handler MCDataGetBytePtr(in pData as Data) returns Pointer binds to "<builtin>"\n'

# (label, file, old, new, text one of the problems must contain)
CASES = [
    ("a foreign parameter of the wrong type", "lcb",
     "_sound_start_at(in pSound as CInt, in pSeconds as CDouble)",
     "_sound_start_at(in pSound as CInt, in pSeconds as CInt)",
     "parameter 2 is declared CInt"),
    ("a foreign parameter dropped", "lcb",
     "_sound_start_at(in pSound as CInt, in pSeconds as CDouble)",
     "_sound_start_at(in pSound as CInt)",
     "aux_sound_start_at"),
    ("a foreign return of the wrong type", "lcb",
     '_engine_is_valid(in pEngine as CInt) returns CInt binds',
     '_engine_is_valid(in pEngine as CInt) returns CDouble binds',
     "aux_engine_is_valid"),
    ("a bind to another handler's symbol", "lcb",
     '"c:audioxt>aux_engine_free!cdecl"', '"c:audioxt>aux_engine_is_valid!cdecl"',
     "aux_engine_is_valid is bound twice"),
    ("a foreign handler off the mechanical name", "lcb",
     "private foreign handler _engine_free(", "private foreign handler _engine_remove(",
     "must be named _engine_free"),
    ("an export nothing binds", "shim",
     "LC_API int aux_abi_version(void)",
     "LC_API int aux_new_thing(void) { return 0; }\nLC_API int aux_abi_version(void)",
     "aux_new_thing is exported with no foreign handler"),
    ("a text result returned as ZStringNative", "lcb",
     "_library_version() returns Pointer", "_library_version() returns ZStringNative",
     "_library_version"),
    ("a text argument declared a Pointer", "lcb",
     "_sound_load(in pEngine as CInt, in pPath as ZStringUTF8, in pStream as CInt)",
     "_sound_load(in pEngine as CInt, in pPath as Pointer, in pStream as CInt)",
     "parameter 2 is declared Pointer"),
    ("the measured pointer declared a script string (the first engine run)", "lcb",
     "_text_length(in pText as Pointer)", "_text_length(in pText as ZStringUTF8)",
     "parameter 1 is declared ZStringUTF8"),
    ("a fourth engine builtin", "lcb", BUILTIN,
     BUILTIN + 'foreign handler MCStringCopy(in pS as String, out rS as String) returns CBool binds to "<builtin>"\n',
     "a foreign handler this gate cannot read"),
    ("an engine builtin declared twice", "lcb", BUILTIN, BUILTIN + BUILTIN,
     "MCStringCreateWithBytes must be declared exactly once"),
    ("an engine builtin declared another way", "lcb", DATA_PTR,
     DATA_PTR.replace("returns Pointer", "returns CInt"),
     "a foreign handler this gate cannot read"),
    ("a public handler off the mechanical name", "lcb",
     "public handler auSoundStartAt(", "public handler auSoundBeginAt(",
     "auSoundStartAt"),
    ("a Boolean handed to the C side unconverted", "lcb",
     "_sound_set_looping(pSound, asInt(pFlag))", "_sound_set_looping(pSound, pFlag)",
     "auSoundSetLooping"),
    ("public parameters in another order than the call", "lcb",
     "_sound_set_looping(pSound, asInt(pFlag))", "_sound_set_looping(asInt(pFlag), pSound)",
     "auSoundSetLooping"),
    ("a text result not copied by textOf", "lcb",
     "      put _library_version() into tP\n   end unsafe\n   return textOf(tP)",
     "      put _library_version() into tP\n   end unsafe\n   return tP",
     "auLibraryVersion"),
    ("a byte count handed to script as a number", "lcb",
     "public handler auCaptureRead(in pCapture as Integer) returns Data",
     "public handler auCaptureRead(in pCapture as Integer) returns Integer",
     "must return Data through dataOf()"),
    ("a bytes result not copied by dataOf", "lcb",
     "      put _capture_read(pCapture) into tR\n   end unsafe\n   return dataOf(tR)",
     "      put _capture_read(pCapture) into tR\n   end unsafe\n   return the empty data",
     "auCaptureRead returns Data but does not end"),
    ("a number read as a byte count", "lcb",
     "public handler auCaptureAvailable(in pCapture as Integer) returns Integer",
     "public handler auCaptureAvailable(in pCapture as Integer) returns Data",
     "returns Data but is not one of the byte-count exports"),
    ("data measured by something other than its own length", "lcb",
     "   put the number of bytes in pData into tLength\n   unsafe\n      put MCDataGetBytePtr(pData) into tBytes\n"
     "      put _sound_load_data(",
     "   put 1024 into tLength\n   unsafe\n      put MCDataGetBytePtr(pData) into tBytes\n"
     "      put _sound_load_data(",
     "auSoundLoadData must measure its data"),
    ("the pointer and the length handed over the wrong way round", "lcb",
     "_sound_load_data(pEngine, tBytes, tLength, asInt(pStream))",
     "_sound_load_data(pEngine, tLength, tBytes, asInt(pStream))",
     "auSoundLoadData"),
    ("dataOf() copying a count it did not check", "lcb",
     "   if pCount <= 0 then\n      return the empty data\n   end if\n   unsafe\n      put _out_pointer() into tBytes",
     "   unsafe\n      put _out_pointer() into tBytes",
     "dataOf() must return the empty data"),
    ("a doc block without one of its parameters", "lcb",
     "pSeconds: The time on the engine's clock, as <auEngineTime> reports it.\n\nExample", "Example",
     "auSoundStartAt") if False else
    ("a doc block without one of its parameters", "lcb",
     "pShape: The waveform: \"sine\", \"square\", \"triangle\" or \"sawtooth\".\n\n", "",
     "auSoundTone"),
    ("a doc block without a Summary", "lcb",
     "Summary: Makes a tone that plays until it is stopped.\n", "",
     "auSoundTone"),
    ("an ABI bump in the shim only", "shim",
     "#define AUX_ABI_VERSION 1", "#define AUX_ABI_VERSION 2", "ABI"),
    ("an ABI bump in the binding's check only", "lcb",
     "   if tV is not 1 then", "   if tV is not 2 then", "ABI"),
    ("a handler missing from the engine self-test's sweep", "selftest",
     '      put "auABIVersion" into tName\n      get auABIVersion()\n', "",
     "sweep"),
    ("the sweep opening the machine's real sound device", "selftest",
     "      get auEngineCreate(-1, 0, 0)\n", "      get auEngineCreate(0, 0, 0)\n",
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
