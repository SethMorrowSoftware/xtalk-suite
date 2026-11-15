#!/usr/bin/env python3
"""test-abi-registry.py - prove tools/check-abi-registry.py FIRES.

A gate that cannot fail prints OK over anything (the suite root's "fixture
before gate"). Each case below copies the real header and .lcb, breaks them
one way, and requires the gate to refuse the copy - then requires the
unbroken pair to pass, so a gate that refuses everything fails too.
"""
import importlib.util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "cux_abi_registry", os.path.join(HERE, "tools", "check-abi-registry.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)

HDR = os.path.join(HERE, "src", "cux_abi.h")
LCB = os.path.join(HERE, "src", "curl.lcb")

# (label, file, old, new): each must make the gate fail.
CASES = [
    ("a value changed in the .lcb", "lcb", "constant kOptProxy is 103", "constant kOptProxy is 104"),
    ("two values swapped", "lcb", "constant kInfoBytesDown is 4\nconstant kInfoBytesUp is 5",
     "constant kInfoBytesDown is 5\nconstant kInfoBytesUp is 4"),
    ("an ABI bump on one side only", "hdr", "#define CUX_ABI_VERSION 1", "#define CUX_ABI_VERSION 2"),
    ("a new header option with no .lcb constant", "hdr", "#define CUO_ACCEPT_ENCODING   117",
     "#define CUO_ACCEPT_ENCODING   117\n#define CUO_NEW_THING 118"),
    ("a constant that mirrors nothing", "lcb", "constant kTextMethod is 5",
     "constant kTextMethod is 5\nconstant kTextNothing is 6"),
    ("a header function never bound", "hdr", "CUX_API int    CUX_CALL cux_live_count(void);",
     "CUX_API int    CUX_CALL cux_live_count(void);\nCUX_API int    CUX_CALL cux_new_thing(void);"),
    ("a bind to the wrong symbol", "lcb", 'binds to "c:curlxt>cux_start!cdecl"',
     'binds to "c:curlxt>cux_cancel!cdecl"'),
    ("a name table mapping to the wrong family", "lcb", 'pName is "bodySize" then\n      return kInfoBodySize',
     'pName is "bodySize" then\n      return kTextHeaders'),
    ("a name listed twice", "lcb", 'pName is "cancelled" then',
     'pName is "state" then'),
    ("an option with no name", "lcb", 'else if pName is "referer" then\n      return kOptReferer\n', ""),
]


def run(hdr_text, lcb_text):
    d = tempfile.mkdtemp(prefix="cux-abi-")
    try:
        h = os.path.join(d, "cux_abi.h")
        l = os.path.join(d, "curl.lcb")
        open(h, "w").write(hdr_text)
        open(l, "w").write(lcb_text)
        errors, _, _ = GATE.check(h, l)
        return errors
    finally:
        shutil.rmtree(d)


def main():
    hdr = open(HDR).read()
    lcb = open(LCB).read()
    bad = []
    if run(hdr, lcb):
        bad.append("the unbroken pair is refused: %s" % run(hdr, lcb)[0])
    for label, which, old, new in CASES:
        src = hdr if which == "hdr" else lcb
        if old not in src:
            bad.append("%s: the fixture's anchor is gone (%r)" % (label, old[:40]))
            continue
        mutated = src.replace(old, new, 1)
        errs = run(mutated if which == "hdr" else hdr, mutated if which == "lcb" else lcb)
        if not errs:
            bad.append("%s: the gate did not fire" % label)
    if bad:
        print("test-abi-registry: FAIL\n  " + "\n  ".join(bad))
        return 1
    print("test-abi-registry: OK (%d mutations each refused; the real pair passes)" % len(CASES))
    return 0


if __name__ == "__main__":
    sys.exit(main())
