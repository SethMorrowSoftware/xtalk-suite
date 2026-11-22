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
    "pdx_lcb_signatures", os.path.join(HERE, "tools", "check-lcb-signatures.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)

BUILTIN = ('foreign handler MCStringCreateWithBytes(in pBytes as Pointer, in pByteCount as CUInt, '
           'in pEncoding as CUInt, in pIsExternalRep as CBool, out rString as String) returns CBool '
           'binds to "<builtin>"\n')

# (label, file, old, new, text one of the problems must contain)
CASES = [
    ("a foreign parameter of the wrong type", "lcb",
     "_pdx_page_text(in pDocument as CInt, in pPage as CInt)",
     "_pdx_page_text(in pDocument as CInt, in pPage as CDouble)",
     "pdx_page_text"),
    ("a foreign parameter dropped", "lcb",
     "_pdx_page_text(in pDocument as CInt, in pPage as CInt)",
     "_pdx_page_text(in pDocument as CInt)",
     "pdx_page_text"),
    ("a foreign return of the wrong type", "lcb",
     "_pdx_page_count(in pDocument as CInt) returns CInt binds",
     "_pdx_page_count(in pDocument as CInt) returns CDouble binds",
     "pdx_page_count"),
    ("a bind to another handler's symbol", "lcb",
     '"c:pdfxt>pdx_close!cdecl"', '"c:pdfxt>pdx_page_count!cdecl"',
     "pdx_page_count is bound twice"),
    ("a foreign handler off the mechanical name", "lcb",
     "private foreign handler _pdx_close(", "private foreign handler _pdx_shut(",
     "_pdx_close"),
    ("an export nothing binds", "shim",
     "LC_API int pdx_open_count(void)",
     "LC_API int pdx_new_thing(void) { return 0; }\nLC_API int pdx_open_count(void)",
     "pdx_new_thing"),
    ("a text result returned as ZStringNative", "lcb",
     "_pdx_library_version() returns Pointer", "_pdx_library_version() returns ZStringNative",
     "pdx_library_version"),
    ("a path taken as ZStringNative", "lcb",
     "_pdx_open(in pPath as ZStringUTF8,", "_pdx_open(in pPath as ZStringNative,",
     "pdx_open"),
    ("a fourth engine builtin", "lcb", BUILTIN,
     BUILTIN + 'foreign handler MCStringCopy(in pS as String, out rS as String) returns CBool binds to "<builtin>"\n',
     "a foreign handler this gate cannot read"),
    ("an engine builtin declared twice", "lcb", BUILTIN, BUILTIN + BUILTIN,
     "must be declared exactly once"),
    ("a public handler off the mechanical name", "lcb",
     "public handler pdfPageCount(", "public handler pdfCountPages(",
     "pdfPageCount"),
    ("public parameters in another order than the call", "lcb",
     "_pdx_open(pPath, pPassword)", "_pdx_open(pPassword, pPath)",
     "pdfOpen"),
    ("a text result not copied by textOf", "lcb",
     "      put _pdx_library_version() into tP\n   end unsafe\n   return textOf(tP)",
     "      put _pdx_library_version() into tP\n   end unsafe\n   return tP",
     "pdfLibraryVersion"),
    ("a bytes result not copied by dataOf", "lcb",
     "      put _pdx_render_page(pDocument, pPage, pWidth, pHeight, pFlags) into tP\n   end unsafe\n   return dataOf(tP)",
     "      put _pdx_render_page(pDocument, pPage, pWidth, pHeight, pFlags) into tP\n   end unsafe\n   return textOf(tP)",
     "pdfRenderPage"),
    ("a doc block without its parameter", "lcb",
     "Summary: Returns how many pages a document has.\n\npDocument: A document handle from <pdfOpen> or <pdfOpenData>.\n",
     "Summary: Returns how many pages a document has.\n",
     "pdfPageCount"),
    ("a doc block without a Summary", "lcb",
     "Summary: Returns how many pages a document has.\n", "",
     "pdfPageCount"),
    ("an ABI bump in the shim only", "shim",
     "#define PDX_ABI_VERSION 1", "#define PDX_ABI_VERSION 2", "ABI"),
    ("an ABI bump in the binding's check only", "lcb",
     "   if tV is not 1 then", "   if tV is not 2 then", "ABI"),
    ("a handler missing from the engine self-test's sweep", "selftest",
     '      put "pdfABIVersion" into tName\n      get pdfABIVersion()\n', "",
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
