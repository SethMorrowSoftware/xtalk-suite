#!/usr/bin/env python3
"""Refresh code/<platform-id>/ beside the extension source with the native libs.

This is the intended, cross-platform way to ship native code with a LiveCode
Builder extension: the per-platform shared library lives INSIDE the extension,
in a code/<platform-id>/ folder next to the .lcb. When the extension is built
and installed, the IDE maps each library into `the revLibraryMapping` and the
engine resolves the c:box2dxt> bindings from there -- so the consumer installs
ONE extension and the library comes with it. No loose .so/.dll/.dylib, no
/usr/lib, no sudo, no LD_LIBRARY_PATH, no "next to the stack". Same on Linux,
macOS and Windows, on LiveCode 9.6.3 and OpenXTalk.

Those per-platform libraries are COMMITTED under src/code/ (built and tested by
CI -- see .github/workflows/build.yml -- and attached to each GitHub Release), so
a fresh clone of this repo is already a ready-to-build extension: open
src/box2dxt.lcb in OXT's Extension Builder and Package -> .lce.

Use this script only to REFRESH that tree when you have newer binaries. Point each
--<platform> flag at the matching freshly-built (build/libbox2dxt.*) or
Release-downloaded library and it copies them into src/code/<platform-id>/ under
the bare binding name. A platform with no flag is left untouched.

    python3 tools/package-extension.py --check                     # list the committed tree
    python3 tools/package-extension.py --linux64 build/libbox2dxt.so
    python3 tools/package-extension.py --win64 ~/dl/box2dxt-windows-x64.dll \
                                       --mac   ~/dl/libbox2dxt-macos-universal.dylib

PLATFORM-ID FORMAT: <architecture>-<platform>, verified against the LiveCode/OXT
engine + IDE source (the IDE's code-folder matcher filters on `the processor`
first, then the platform). The architecture comes FIRST -- e.g. x86_64-linux,
NOT linux-x86_64. Windows uses the -win32 suffix for both bitnesses. The file is
the bare token box2dxt.{so,dll,dylib} (no "lib" prefix; it must equal the
c:box2dxt> binding name).
"""

import argparse
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The extension source; its folder is where the code/ tree lives.
LCB_SRC = "src/box2dxt.lcb"

# platform-id ("<arch>-<platform>", arch FIRST) -> (override-flag attr, bare name).
# The bare name must equal the binding token "box2dxt" (the engine maps
# c:box2dxt> to box2dxt.{so,dll,dylib} -- no "lib" prefix).
CODE_LAYOUT = {
    "x86_64-linux":  ("linux64", "box2dxt.so"),
    "x86-linux":     ("linux32", "box2dxt.so"),
    "x86_64-win32":  ("win64",   "box2dxt.dll"),
    "x86-win32":     ("win32",   "box2dxt.dll"),
    "universal-mac": ("mac",     "box2dxt.dylib"),
}


def main():
    ap = argparse.ArgumentParser(description="Refresh src/code/<platform-id>/ from per-platform native libraries.")
    ap.add_argument("--linux64", help="source .so for code/x86_64-linux/")
    ap.add_argument("--linux32", help="source .so for code/x86-linux/")
    ap.add_argument("--win64", help="source .dll for code/x86_64-win32/")
    ap.add_argument("--win32", help="source .dll for code/x86-win32/")
    ap.add_argument("--mac", help="source .dylib for code/universal-mac/")
    ap.add_argument("--check", action="store_true", help="list/validate the committed src/code/ tree and exit")
    args = ap.parse_args()

    code_root = os.path.join(ROOT, os.path.dirname(LCB_SRC), "code")
    rel = lambda p: os.path.relpath(p, ROOT)

    if not os.path.isfile(os.path.join(ROOT, LCB_SRC)):
        print(f"missing extension source: {LCB_SRC}", file=sys.stderr)
        return 1

    # --check: report the committed tree; non-zero if any platform slot is empty
    # (an extension missing a slot won't load on that target).
    if args.check:
        print("Committed extension tree (src/code/<platform-id>/):")
        missing = []
        for platform_id, (_, bare) in CODE_LAYOUT.items():
            dest = os.path.join(code_root, platform_id, bare)
            if os.path.isfile(dest):
                print(f"  {rel(dest)}  ({os.path.getsize(dest)} bytes)")
            else:
                missing.append(f"src/code/{platform_id}/{bare}")
        if missing:
            print("MISSING -- the extension will not load on these targets:", file=sys.stderr)
            for m in missing:
                print(f"  - {m}", file=sys.stderr)
            return 1
        return 0

    # Copy each provided source into its committed slot under the bare name.
    plan = []          # (dest_abspath, src_abspath)
    problems = []
    for platform_id, (attr, bare) in CODE_LAYOUT.items():
        src = getattr(args, attr)
        if not src:
            continue
        src_abs = src if os.path.isabs(src) else os.path.join(ROOT, src)
        if os.path.isfile(src_abs):
            plan.append((os.path.join(code_root, platform_id, bare), src_abs))
        else:
            problems.append(f"--{attr}: not a file: {src}")

    if not plan and not problems:
        print("Nothing to do. Pass --linux64/--linux32/--win64/--win32/--mac to refresh a", file=sys.stderr)
        print("platform, or --check to validate the committed tree. (src/code/ is committed,", file=sys.stderr)
        print("so a fresh clone is already build-ready.)", file=sys.stderr)
        return 1
    if problems:
        print("Cannot refresh -- inputs missing:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    for dest_abs, src_abs in plan:
        os.makedirs(os.path.dirname(dest_abs), exist_ok=True)
        shutil.copy2(src_abs, dest_abs)
        print(f"  + {rel(dest_abs)}")

    print()
    print("src/box2dxt.lcb + src/code/ is the ready-to-build extension.")
    print("Open src/box2dxt.lcb in OXT's Extension Builder and Package -> .lce.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
