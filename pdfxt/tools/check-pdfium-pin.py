#!/usr/bin/env python3
"""check-pdfium-pin.py - src/pdfium.pin, and everything that repeats it.

pdfxt builds against and ships a PREBUILT PDFium. src/pdfium.pin is the one
table that says which: a release, and for each platform an archive, the
SHA-256 of that archive and the SHA-256 of the library inside it. The CMake
build and the suite's installer both read the file itself. This gate holds
what a reader cannot check by eye and what is written a second time:

  1. the pin parses: one release line, one row for each of the platform ids
     below and no other, every hash 64 hex digits, no archive and no hash
     named twice (a row pasted and not edited ships one platform's library
     on another);
  2. the release is written the same way everywhere it is written by hand:
     README.md, docs/building.md and THIRD-PARTY-LICENSES.md name the pin's
     release and no other `chromium/<number>` (the shim is not on the list:
     the build hands it the release as PDX_PDFIUM_PIN, read from the pin);
  3. THIRD-PARTY-LICENSES.md has a section for every library the pinned
     archives carry a licence for (the list below, read from the archives'
     licenses/ folders when the pin was taken: moving the pin means reading
     that folder again and editing BOTH);
  4. any PDFium library committed under src/code/<platform>/ is the pinned
     one, byte for byte.

Exit status: 0 held, 1 a difference (each named), 2 an input missing.
"""
import hashlib
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

PLATFORMS = {
    "x86_64-linux": ".so", "x86-linux": ".so", "arm64-linux": ".so",
    "x86_64-win32": ".dll", "x86-win32": ".dll", "universal-mac": ".dylib",
    "arm64-android": ".so", "armv7-android": ".so",
    "x86_64-android": ".so", "x86-android": ".so",
}

# One `## ` heading of THIRD-PARTY-LICENSES.md must begin with each.
LICENSED = ["PDFium", "Abseil", "Anti-Grain Geometry", "dragonbox", "fast_float", "FreeType",
            "HarfBuzz", "Highway", "ICU", "Little CMS", "libjpeg-turbo", "OpenJPEG", "libpng",
            "LLVM libc", "simdutf", "zlib", "Catapult", "cpu_features", "libunwind",
            "pdfium-binaries"]

# Files that write the release by hand, relative to the member root.
REPEATS = ["README.md", os.path.join("docs", "building.md"), "THIRD-PARTY-LICENSES.md"]

HEX64 = re.compile(r"^[0-9a-f]{64}$")
RELEASE = re.compile(r"chromium/(\d+)")


def parse_pin(text):
    """(release, {platform: (archive, tgz_sha, lib_sha)}, problems)."""
    release, rows, problems = None, {}, []
    for n, line in enumerate(text.split("\n"), 1):
        parts = line.split("#", 1)[0].split()
        if not parts:
            continue
        if parts[0] == "release":
            if release is not None:
                problems.append("pdfium.pin:%d: a second release line" % n)
            elif len(parts) != 2 or not RELEASE.fullmatch(parts[1]):
                problems.append("pdfium.pin:%d: the release must be chromium/<number>" % n)
            else:
                release = parts[1]
            continue
        if len(parts) != 4:
            problems.append("pdfium.pin:%d: a row is platform-id, archive, two SHA-256 (found %d fields)"
                            % (n, len(parts)))
            continue
        pid, archive, tgz, lib = parts
        if pid in rows:
            problems.append("pdfium.pin:%d: %s has a second row" % (n, pid))
            continue
        if pid not in PLATFORMS:
            problems.append("pdfium.pin:%d: %s is not a platform id of this member" % (n, pid))
        for what, h in (("archive", tgz), ("library", lib)):
            if not HEX64.match(h):
                problems.append("pdfium.pin:%d: the %s hash of %s is not 64 lowercase hex digits"
                                % (n, what, pid))
        rows[pid] = (archive, tgz, lib)
    if release is None:
        problems.append("pdfium.pin: no release line")
    for pid in PLATFORMS:
        if pid not in rows:
            problems.append("pdfium.pin: no row for %s" % pid)
    for col, what in ((0, "archive"), (1, "archive hash"), (2, "library hash")):
        seen = {}
        for pid, row in sorted(rows.items()):
            if row[col] in seen:
                problems.append("pdfium.pin: %s and %s name the same %s"
                                % (seen[row[col]], pid, what))
            seen[row[col]] = pid
    return release, rows, problems


def check(pin_text, repeats, committed):
    """problems. `repeats` is {relative path: text}; `committed` is
    {platform id: sha256 of a committed PDFium library}."""
    release, rows, problems = parse_pin(pin_text)
    if release is None:
        return problems
    for path, text in sorted(repeats.items()):
        named = sorted(set("chromium/" + m for m in RELEASE.findall(text)))
        if release not in named:
            problems.append("%s does not name the pinned release %s" % (path, release))
        for other in named:
            if other != release:
                problems.append("%s names %s, but the pin is %s" % (path, other, release))
    licences = repeats.get("THIRD-PARTY-LICENSES.md", "")
    headings = [l[3:] for l in licences.split("\n") if l.startswith("## ")]
    for name in LICENSED:
        if not any(h.startswith(name) for h in headings):
            problems.append("THIRD-PARTY-LICENSES.md has no section for %s" % name)
    for pid, have in sorted(committed.items()):
        if pid not in rows:
            problems.append("src/code/%s holds a PDFium library and the pin has no such row" % pid)
        elif have != rows[pid][2]:
            problems.append("src/code/%s: the committed PDFium library is not the pinned one "
                            "(SHA-256 %s, pinned %s)" % (pid, have, rows[pid][2]))
    return problems


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    try:
        pin_text = open(os.path.join(ROOT, "src", "pdfium.pin"), encoding="utf-8").read()
        repeats = {p.replace(os.sep, "/"): open(os.path.join(ROOT, p), encoding="utf-8").read()
                   for p in REPEATS}
    except OSError as e:
        print("check-pdfium-pin: cannot read its inputs: %s" % e)
        return 2
    committed = {}
    code = os.path.join(ROOT, "src", "code")
    for pid, ext in PLATFORMS.items():
        lib = os.path.join(code, pid, "pdfium" + ext)
        shim = os.path.join(code, pid, "pdfxt" + ext)
        if os.path.exists(lib):
            committed[pid] = sha256(lib)
    problems = check(pin_text, repeats, committed)
    for pid, ext in PLATFORMS.items():
        lib = os.path.exists(os.path.join(code, pid, "pdfium" + ext))
        shim = os.path.exists(os.path.join(code, pid, "pdfxt" + ext))
        if lib != shim:
            problems.append("src/code/%s holds %s without %s: the two ship together or not at all"
                            % (pid, "pdfium" + ext if lib else "pdfxt" + ext,
                               "pdfxt" + ext if lib else "pdfium" + ext))
    if problems:
        for p in problems:
            print("FAIL " + p)
        print("check-pdfium-pin: FAILED (%d problems)" % len(problems))
        return 1
    release, rows, _ = parse_pin(pin_text)
    print("check-pdfium-pin: OK (%s: %d platform rows, %d files that repeat the release, "
          "%d licence sections, %d committed PDFium libraries each the pinned one)"
          % (release, len(rows), len(repeats), len(LICENSED), len(committed)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
