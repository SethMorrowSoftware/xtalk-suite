#!/usr/bin/env python3
"""test-pdfium-pin.py - prove tools/check-pdfium-pin.py FIRES.

Each case takes the REAL pin and the real files that repeat it, breaks one
thing in memory, and requires the gate to refuse the result with a problem
that names the break ("fixture before gate", suite root CLAUDE.md). The
unbroken set must pass. A case whose `old` text is gone fails as stale.
"""
import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
spec = importlib.util.spec_from_file_location(
    "pdx_pdfium_pin", os.path.join(HERE, "tools", "check-pdfium-pin.py"))
GATE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(GATE)


def main():
    pin = open(os.path.join(HERE, "src", "pdfium.pin"), encoding="utf-8").read()
    repeats = {p.replace(os.sep, "/"): open(os.path.join(HERE, p), encoding="utf-8").read()
               for p in GATE.REPEATS}
    release, rows, _ = GATE.parse_pin(pin)
    failed = 0
    if GATE.check(pin, repeats, {}):
        print("FAIL the unbroken files must pass: %s" % GATE.check(pin, repeats, {})[:3])
        return 1
    win = rows["x86_64-win32"]
    lin = rows["x86_64-linux"]
    number = release.split("/")[1]
    other = "chromium/%d" % (int(number) + 1)

    def lic_without(name):
        t = repeats["THIRD-PARTY-LICENSES.md"]
        return t.replace("\n## " + name, "\n## (cut) " + name)

    # (label, pin text, repeats, committed, text a problem must contain)
    cases = [
        ("the release moved in the pin only", pin.replace("release " + release, "release " + other),
         repeats, {}, "does not name the pinned release " + other),
        ("no release line", pin.replace("release " + release, ""), repeats, {}, "no release line"),
        ("a release that is not chromium/<number>", pin.replace("release " + release, "release latest"),
         repeats, {}, "must be chromium/<number>"),
        ("a platform row dropped", pin.replace("\nx86-win32 ", "\n# x86-win32 "), repeats, {},
         "no row for x86-win32"),
        ("a row for a platform that is not one", pin + "\nriscv-linux linux-riscv %s %s\n" % ("a" * 64, "b" * 64),
         repeats, {}, "riscv-linux is not a platform id"),
        ("a hash cut short", pin.replace(win[1], win[1][:-1]), repeats, {}, "not 64 lowercase hex"),
        ("a hash in capitals", pin.replace(win[2], win[2].upper()), repeats, {}, "not 64 lowercase hex"),
        ("a row pasted and not edited: one library on two platforms", pin.replace(win[2], lin[2]),
         repeats, {}, "name the same library hash"),
        ("one archive on two platforms", pin.replace(" win-x64 ", " linux-x64 "), repeats, {},
         "name the same archive"),
        ("a platform given twice", pin + "\nx86_64-linux linux-x64b %s %s\n" % ("c" * 64, "d" * 64),
         repeats, {}, "x86_64-linux has a second row"),
        ("the README left on another release",
         pin, dict(repeats, **{"README.md": repeats["README.md"].replace(release, other)}), {},
         "README.md"),
        ("the building page naming two releases",
         pin, dict(repeats, **{"docs/building.md": repeats["docs/building.md"] + "\n" + other + "\n"}), {},
         "docs/building.md names " + other),
        ("the licence page without PDFium", pin,
         dict(repeats, **{"THIRD-PARTY-LICENSES.md": lic_without("PDFium")}), {},
         "no section for PDFium"),
        ("the licence page without FreeType", pin,
         dict(repeats, **{"THIRD-PARTY-LICENSES.md": lic_without("FreeType")}), {},
         "no section for FreeType"),
        ("the licence page without the Android-only libunwind", pin,
         dict(repeats, **{"THIRD-PARTY-LICENSES.md": lic_without("libunwind")}), {},
         "no section for libunwind"),
        ("a committed PDFium that is not the pinned one", pin, repeats,
         {"x86_64-linux": "e" * 64}, "is not the pinned one"),
        ("another platform's PDFium committed in a folder", pin, repeats,
         {"x86_64-linux": win[2]}, "is not the pinned one"),
    ]
    for label, p, r, c, want in cases:
        if p == pin and r == repeats and not c:
            print("FAIL %s: the fixture is stale (it changed nothing)" % label)
            failed += 1
            continue
        problems = GATE.check(p, r, c)
        if not problems:
            print("FAIL %s: the gate passed it" % label)
            failed += 1
        elif not any(want in x for x in problems):
            print("FAIL %s: refused, but no problem says %r: %s" % (label, want, problems[:3]))
            failed += 1
    if GATE.check(pin, repeats, {"x86_64-linux": lin[2]}):
        print("FAIL the pinned library, committed, must pass")
        failed += 1
    if failed:
        print("test-pdfium-pin: FAILED (%d)" % failed)
        return 1
    print("test-pdfium-pin: OK (%d breaks each refused by name; the unbroken files pass)" % len(cases))
    return 0


if __name__ == "__main__":
    sys.exit(main())
