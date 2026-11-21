#!/usr/bin/env python3
"""test-member-gates.py - prove tools/check-pins.py and
tools/check-web-names.py FIRE.

A gate that cannot fail prints OK over anything (the suite root's "fixture
before gate"). Each case takes the REAL files, breaks one of them one way in
memory, and requires the gate to refuse the result with a problem that names
the break. The unbroken files must pass. A case whose text is no longer in
its file fails as "the fixture is stale".

The archive half of check-web-names.py is driven with nm listings written
here, in the shape llvm-nm prints for a wasm archive: the web lane runs it on
the real one.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load(name):
    spec = importlib.util.spec_from_file_location(name.replace("-", "_"), os.path.join(HERE, "tools", name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


PINS = load("check-pins")
WEB = load("check-web-names")


def read(*parts):
    return open(os.path.join(HERE, *parts), encoding="utf-8").read()


def main():
    failed = 0
    count = 0

    def expect(label, problems, want):
        nonlocal failed, count
        count += 1
        if not problems:
            print("FAIL %s: the gate passed it" % label)
            failed += 1
        elif not any(want in p for p in problems):
            print("FAIL %s: refused, but no problem says %r: %s" % (label, want, problems[:3]))
            failed += 1

    def swap(label, text, old, new):
        nonlocal failed
        if old not in text:
            print("FAIL %s: the fixture is stale (its text is not in the file)" % label)
            failed += 1
            return None
        return text.replace(old, new, 1)

    # ---- check-pins
    cmake, lic, smoke, lcb = (read("CMakeLists.txt"), read("THIRD-PARTY-LICENSES.md"),
                              read("tests", "smoke_test.c"), read("src", "xlsxt.lcb"))
    if PINS.check(cmake, lic, smoke, lcb):
        print("FAIL check-pins: the unbroken files must pass: %s" % PINS.check(cmake, lic, smoke, lcb)[:3])
        failed += 1
    pins, _ = PINS.read_pins(cmake)
    zv, zc = pins["zlib"]
    for label, args, want in (
        ("a version bumped in CMakeLists.txt's table only",
         lambda: (swap("table", cmake, "#   zlib %s " % zv, "#   zlib 9.9 "), lic, smoke, lcb),
         "THIRD-PARTY-LICENSES.md does not name zlib 9.9"),
        ("a commit bumped in CMakeLists.txt only",
         lambda: (swap("commit", cmake, zc, "0" * 40), lic, smoke, lcb),
         "does not name zlib's pinned commit"),
        ("a stale commit left in the notice beside the new one",
         lambda: (cmake, lic + "\n" + "1" * 40 + "\n", smoke, lcb),
         "names a commit that is not a pin"),
        ("the smoke test expecting another version",
         lambda: (cmake, lic, swap("smoke", smoke, '"zlib %s"' % zv, '"zlib 0.1"'), lcb),
         "tests/smoke_test.c does not expect"),
        ("the binding's example naming another version",
         lambda: (cmake, lic, smoke, swap("lcb", lcb, "libxlsxwriter %s; zlib" % pins["libxlsxwriter"][0],
                                          "libxlsxwriter 0.0.1; zlib")),
         "xlLibraryVersion's doc block"),
        ("a pin CMakeLists.txt no longer states",
         lambda: (swap("set", cmake, "set(XLSXT_EXPAT_COMMIT", "set(XLSXT_EXPAT_REVISION"), lic, smoke, lcb),
         "cannot find the pin of Expat"),
    ):
        a = args()
        if any(x is None for x in a):
            continue
        expect("check-pins: " + label, PINS.check(*a), want)

    # ---- check-web-names: the header
    header = read("src", "xlsx_web_names.h")
    if WEB.check_header(header, cmake):
        print("FAIL check-web-names: the unbroken files must pass: %s" % WEB.check_header(header, cmake)[:3])
        failed += 1
    one = "#define MD5_Init xlxw_MD5_Init\n"
    for label, mutate, want in (
        ("a name renamed to something else", lambda: swap("rename", header, one, "#define MD5_Init other_MD5_Init\n"),
         "is renamed to other_MD5_Init"),
        ("a name renamed twice", lambda: swap("twice", header, one, one + one), "MD5_Init is renamed twice"),
        ("one of the shim's own names renamed",
         lambda: swap("own", header, one, one + "#define xlx_abi_version xlxw_xlx_abi_version\n"),
         "xlx_abi_version must keep its name"),
        ("a line that is not a rename", lambda: swap("line", header, one, one + "#undef MD5_Init\n"),
         "a line that is not"),
        ("a line added by hand, out of order",
         lambda: swap("order", header, one, "#define zzz_late xlxw_zzz_late\n" + one), "is not what --write would write"),
        ("the shim's own function for libxlsxwriter left out",
         lambda: swap("extra", header, "#define emyg_dtoa xlxw_emyg_dtoa\n", ""), "emyg_dtoa"),
        ("a marker removed", lambda: swap("marker", header, WEB.END, "/* gone */"), "NAMES marker pair"),
    ):
        text = mutate()
        if text is not None:
            expect("check-web-names: " + label, WEB.check_header(text, cmake), want)
    cut = WEB.BEGIN + "\n" + one + "#define emyg_dtoa xlxw_emyg_dtoa\n" + WEB.END
    expect("check-web-names: a header of two names",
           WEB.check_header(WEB.PROLOGUE + cut + "\n" + WEB.EPILOGUE, cmake), "floor")
    text = swap("cmake", cmake, "-include", "-imacros")
    if text is not None:
        expect("check-web-names: CMakeLists.txt no longer including the header", WEB.check_header(header, text),
               "no longer puts src/xlsx_web_names.h")

    # ---- check-web-names: the archive
    good = ("xlsxt-web.o:\n00000001 T xlx_abi_version\n00000002 T xlsxt_web_exports\n"
            "00000003 T xlxw_MD5_Init\n00000010 D xlxw_z_errmsg\n         U malloc\n")
    if WEB.check_archive(good, header):
        print("FAIL check-web-names: a clean archive listing must pass: %s" % WEB.check_archive(good, header)[:3])
        failed += 1
    expect("check-web-names: a library function under its own name",
           WEB.check_archive(good + "00000004 T inflate\n", header), "defines the global inflate")
    expect("check-web-names: a library's data under its own name",
           WEB.check_archive(good + "00000004 D z_errmsg\n", header), "defines the global z_errmsg")
    expect("check-web-names: an archive without the table",
           WEB.check_archive(good.replace("00000002 T xlsxt_web_exports\n", ""), header), "xlsxt_web_exports")
    expect("check-web-names: a listing nm could not make sense of",
           WEB.check_archive("xlsxt-web.o: no symbols\n", header), "defines no xlx_* name")

    if failed:
        print("test-member-gates: FAILED (%d of %d)" % (failed, count + 3))
        return 1
    print("test-member-gates: OK (%d mutations each refused by name; the unbroken files pass)" % count)
    return 0


if __name__ == "__main__":
    sys.exit(main())
