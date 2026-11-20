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
    "r3x_lcb_signatures", os.path.join(HERE, "tools", "check-lcb-signatures.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)

BUILTIN = 'foreign handler MCDataGetLength(in pData as Data) returns CUInt binds to "<builtin>"\n'

# (label, file, old, new, text one of the problems must contain)
CASES = [
    ("a foreign parameter of the wrong type", "lcb",
     "_node_set_position(in pNode as CInt, in pX as CDouble,",
     "_node_set_position(in pNode as CInt, in pX as CInt,",
     "r3x_node_set_position parameters are"),
    ("a foreign parameter dropped", "lcb",
     "_scene_render(in pScene as CInt, in pW as CInt, in pH as CInt)",
     "_scene_render(in pScene as CInt, in pW as CInt)",
     "r3x_scene_render parameters are"),
    ("a foreign return of the wrong type", "lcb",
     "_scene_is_valid(in pScene as CInt) returns CInt binds",
     "_scene_is_valid(in pScene as CInt) returns CDouble binds",
     "r3x_scene_is_valid returns CDouble"),
    ("a bind to another handler's symbol", "lcb",
     '"c:render3dxt>r3x_scene_destroy!cdecl"', '"c:render3dxt>r3x_scene_is_valid!cdecl"',
     "r3x_scene_is_valid is bound twice"),
    ("a foreign handler off the mechanical name", "lcb",
     "private foreign handler _scene_destroy(", "private foreign handler _scene_remove(",
     "must be bound as _scene_destroy"),
    ("an export nothing binds", "shim",
     "LC_API int r3x_abi_version(void)",
     "LC_API int r3x_new_thing(void) { return 0; }\nLC_API int r3x_abi_version(void)",
     "r3x_new_thing is exported by the shim and never bound"),
    ("a bind to a function the shim lacks", "shim",
     "LC_API const char *r3x_hit_text(void)", "static const char *r3x_hit_text_gone(void)",
     "r3x_hit_text is bound but the shim does not define it"),
    ("a text result returned as ZStringNative", "lcb",
     "_library_version() returns Pointer", "_library_version() returns ZStringNative",
     "returns a C string"),
    ("a text argument taken as a Pointer", "lcb",
     "_texture_load(in pPath as ZStringUTF8)", "_texture_load(in pPath as Pointer)",
     "r3x_texture_load parameters are"),
    ("a fifth engine builtin", "lcb", BUILTIN,
     BUILTIN + 'foreign handler MCStringCopy(in pS as String, out rS as String) returns CBool binds to "<builtin>"\n',
     "a foreign handler this gate cannot read"),
    ("an engine builtin declared twice", "lcb", BUILTIN, BUILTIN + BUILTIN,
     "must appear exactly once"),
    ("a public handler off the mechanical name", "lcb",
     "public handler r3SceneRender(", "public handler r3SceneDraw(",
     "no public handler r3SceneRender"),
    ("a public parameter of the wrong type", "lcb",
     "public handler r3NodeSetVisible(in pNode as Integer, in pFlag as Boolean)",
     "public handler r3NodeSetVisible(in pNode as Integer, in pFlag as Integer)",
     "r3NodeSetVisible is declared"),
    ("a Boolean handed to the C side unconverted", "lcb",
     "_node_set_visible(pNode, asInt(pFlag))", "_node_set_visible(pNode, pFlag)",
     "r3NodeSetVisible's body"),
    ("arguments in another order than the C function's", "lcb",
     "_node_set_tag(pNode, pTag)", "_node_set_tag(pTag, pNode)",
     "r3NodeSetTag's body"),
    ("a text result not copied by textOf", "lcb",
     "      put _library_version() into tR\n   end unsafe\n   return textOf(tR)",
     "      put _library_version() into tR\n   end unsafe\n   return tR",
     "r3LibraryVersion's body"),
    ("the picture copied with the wrong length", "lcb",
     "         put MCDataCreateWithBytes(tPtr, tLen, tData) into tOk\n      end if\n   end unsafe\n   return tData\nend handler\n\n/**\nSummary: Returns the last",
     "         put MCDataCreateWithBytes(tPtr, 4, tData) into tOk\n      end if\n   end unsafe\n   return tData\nend handler\n\n/**\nSummary: Returns the last",
     "r3SceneRender's body"),
    ("a doc block without one of its parameters", "lcb",
     "pTag: A whole number; 0 means no tag.\n\n", "",
     "r3NodeSetTag's doc block does not describe pTag"),
    ("a doc block without a Summary", "lcb",
     "Summary: Draws a scene and returns the picture.\n", "",
     "r3SceneRender's doc block has no Summary"),
    ("a public handler with no doc block", "lcb",
     "*/\npublic handler r3ThreadCount(", "*/\n\npublic handler r3ThreadCount(",
     "r3ThreadCount has no doc block"),
    ("an ABI bump in the shim only", "shim",
     "#define R3X_ABI_VERSION 1", "#define R3X_ABI_VERSION 2", "ABI 2"),
    ("an ABI bump in the binding's check only", "lcb",
     "   if tV is not 1 then", "   if tV is not 2 then", "ABI 1"),
    ("a handler missing from the engine self-test's sweep", "selftest",
     '      put "r3ABIVersion" into tName\n      get r3ABIVersion()\n', "",
     "sweep is stale"),
    ("a shim the scanner cannot read", "shim", "LC_API ", "LC_APY ", "the scanner is blind"),
]


def main():
    texts = {
        "lcb": open(GATE.LCB, encoding="utf-8").read(),
        "shim": open(GATE.SHIM, encoding="utf-8").read(),
        "selftest": open(GATE.SELFTEST, encoding="utf-8").read(),
    }
    failed = 0
    problems = GATE.check(texts["lcb"], texts["shim"], texts["selftest"])[0]
    if problems:
        print("FAIL the unbroken files must pass: %s" % problems[:3])
        failed += 1
    for label, which, old, new, want in CASES:
        if texts[which].count(old) < 1:
            print("FAIL %s: the fixture is stale (its text is not in the %s)" % (label, which))
            failed += 1
            continue
        mutated = dict(texts)
        count = -1 if label == "a shim the scanner cannot read" else 1
        mutated[which] = texts[which].replace(old, new, count)
        problems = GATE.check(mutated["lcb"], mutated["shim"], mutated["selftest"])[0]
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
