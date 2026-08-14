#!/usr/bin/env python3
"""Assemble a ready-to-ship Box2Dxt platformer package.

The zip is self-contained and matches dist/INSTALL.md:

    NewPlateformerDemo.oxtstack    (your saved stack -- --stack)
    INSTALL.md
    box2dxt.lce                    (optional prebuilt extension -- --lce)
    extension/   box2dxt.lcb + code/<arch>-<platform>/box2dxt.{so,dll,dylib}
    source/      box2d_lc.c, box2dxt-kit.livecodescript   (reference)
    spritesheets/  the platformer's PNG + XML sheets

The native library ships INSIDE the extension (the code/ tree), so the recipient
installs one extension and the engine loads the right per-platform library
automatically -- no loose .so/.dll/.dylib, no rename, no sudo, no /usr/lib. The
extension/ folder comes straight from src/ (src/box2dxt.lcb + src/code/, which is
committed; tools/package-extension.py refreshes it from a newer build). If you have already built
a .lce in OXT's Extension Builder, pass it with --lce to drop it in too, so
testers can install in one click instead of Packaging it themselves.

The only thing this script can't produce is the *saved* stack -- build and save
it in OXT first, then point --stack at it:

    python3 tools/make-release.py --stack ~/Desktop/NewPlateformerDemo.oxtstack
    python3 tools/make-release.py --stack ~/Desktop/Demo.oxtstack --lce ~/box2dxt.lce

--check validates the inputs only.
"""

import argparse
import sys
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

# Reference copies of the C shim and the Kit (the .lcb lives under extension/).
SOURCE_FILES = ["box2d_lc.c", "box2dxt-kit.livecodescript"]

# the spritesheets the platformer loads (PNG + XML each)  ->  spritesheets/
PLATFORMER_SHEETS = [
    "spritesheet-characters-default", "spritesheet-enemies-default",
    "spritesheet-tiles-default", "spritesheet-backgrounds-default", "enemies",
]


def human(nbytes):
    size = float(nbytes)
    for unit in ("B", "KB", "MB"):
        if size < 1024 or unit == "MB":
            return f"{size:.0f} {unit}" if unit == "B" else f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} MB"


def rel(src):
    return src.relative_to(REPO) if src.is_relative_to(REPO) else src


def main():
    ap = argparse.ArgumentParser(description="Build the Box2Dxt platformer distribution zip.")
    ap.add_argument("--stack", help="path to the built & saved platformer stack (.oxtstack)")
    ap.add_argument("--lce", help="optional prebuilt extension to drop in (box2dxt.lce, built in OXT)")
    ap.add_argument("--out", default="dist/NewPlateformerDemo.zip", help="output zip path")
    ap.add_argument("--top", default="NewPlateformerDemo", help="top-level folder name inside the zip")
    ap.add_argument("--stack-name", default="NewPlateformerDemo.oxtstack", help="filename the stack gets inside the zip (the guide refers to this name)")
    ap.add_argument("--sheets", default="Spritesheets", help="folder holding the platformer's spritesheets")
    ap.add_argument("--check", action="store_true", help="validate inputs only; do not write the zip")
    args = ap.parse_args()

    items = []  # (arcname-relative-to-top, source Path)
    problems = []

    # extension/ : the .lcb plus its bundled per-platform native libraries (code/).
    # This is the whole point -- the lib travels inside the extension.
    lcb = REPO / "src" / "box2dxt.lcb"
    if lcb.is_file():
        items.append(("extension/box2dxt.lcb", lcb))
    else:
        problems.append("missing src/box2dxt.lcb")

    code_dir = REPO / "src" / "code"
    code_libs = sorted(code_dir.rglob("box2dxt.*")) if code_dir.is_dir() else []
    if code_libs:
        for lib in code_libs:
            items.append((f"extension/code/{lib.relative_to(code_dir).as_posix()}", lib))
    else:
        problems.append("missing src/code/<arch>-<platform>/box2dxt.* "
                        "(run: python3 tools/package-extension.py)")

    # source/ : the C shim and the Kit, for reference / rebuilding.
    for name in SOURCE_FILES:
        src = REPO / "src" / name
        if src.is_file():
            items.append((f"source/{name}", src))
        else:
            problems.append(f"missing source file: src/{name}")

    # the install guide, at the root
    install = REPO / "dist" / "INSTALL.md"
    if install.is_file():
        items.append(("INSTALL.md", install))
    else:
        problems.append("missing dist/INSTALL.md")

    # box2dxt.lce : optional prebuilt extension, at the root
    if args.lce:
        lce = Path(args.lce).expanduser()
        if lce.is_file():
            items.append(("box2dxt.lce", lce))
        else:
            problems.append(f"--lce is not a file: {lce}")

    # spritesheets/ : the demo's art (PNG + XML pairs)
    sheets_dir = Path(args.sheets).expanduser()
    if not sheets_dir.is_absolute():
        sheets_dir = REPO / args.sheets
    for base in PLATFORMER_SHEETS:
        for ext in ("png", "xml"):
            src = sheets_dir / f"{base}.{ext}"
            if src.is_file():
                items.append((f"spritesheets/{base}.{ext}", src))
            else:
                problems.append(f"missing spritesheet: {src}")

    # the saved stack, at the root (required to build the zip, not just to --check)
    stack = None
    if args.stack:
        stack = Path(args.stack).expanduser()
        if stack.is_file():
            items.append((args.stack_name, stack))
        else:
            problems.append(f"--stack is not a file: {stack}")
    elif not args.check:
        problems.append("--stack is required (build & save the .oxtstack in OXT first)")

    if problems:
        print("Cannot build the release:", file=sys.stderr)
        for p in problems:
            print(f"  - {p}", file=sys.stderr)
        return 1

    print(f"Release contents (top folder: {args.top}/):")
    for arc, src in items:
        print(f"  {arc:<40} <- {rel(src)}  ({human(src.stat().st_size)})")

    if args.check:
        print("\n--check: inputs valid" + ("" if stack else " (no --stack given; a real build needs one)") + ".")
        return 0

    out = Path(args.out) if Path(args.out).is_absolute() else (REPO / args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for arc, src in items:
            z.write(src, f"{args.top}/{arc}")

    print(f"\nWrote {rel(out)}  ({human(out.stat().st_size)}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
