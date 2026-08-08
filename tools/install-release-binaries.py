#!/usr/bin/env python3
"""
install-release-binaries.py - land a release-binaries bundle into the tree.

USAGE
    python3 tools/install-release-binaries.py <bundle-dir> [--dry-run]

The bundle is what .github/workflows/release-binaries.yml publishes: one
directory laid out as

    <member>/<platform-id>/<member>.<so|dll|dylib>

WHO CALLS THIS. Both paths, and they are the same code on purpose:

  * release-binaries.yml's commit job runs it on the runner, so the checks below
    stand between a freshly built artifact and the repository;
  * you run it by hand on an unzipped bundle when the workflow was dispatched
    with commit_mode: none, or when you built something locally.

CI reusing this rather than reimplementing it is the point. A verifier that only
guards the manual path is a verifier that guards the path nobody takes.

WHAT IT CHECKS BEFORE TOUCHING ANYTHING. Every file is verified first and the
tree is only written once every check has passed, so a bad bundle cannot leave
the repository half-updated:

  * the FILENAME matches the member. The engine resolves an LCB `c:<name>>` bind
    to a file of exactly that name, so `libcoinxt.so` or `coinxt-1.0.so` is not
    a cosmetic difference - it is a library that will not load.
  * the OBJECT FORMAT and ARCHITECTURE match the platform directory, read from
    the ELF/PE/Mach-O header rather than trusted from the path. This catches the
    failure this repo has already had to design against - a cross build that
    reports the build machine's arch and files an x86 library under
    x86_64-linux - and the macOS version of it: a THIN dylib under
    `universal-mac` is REFUSED, because it loads for whoever built it and fails
    only for users on the other architecture.
  * for coinxt, the EXPORT SURFACE is exactly the cnx_* entry points. That check
    fails OPEN if it is skipped (a wrong export mechanism yields a WORKING
    library with 77 symbols), so it is asserted here too, not only in CI.

It then refreshes each touched member's src/code/MANIFEST.sha256 - creating one
for a member that had none, and saying so - and prints what changed. It does not
commit: in CI that is the calling job's next step, and locally it is yours.
"""

import hashlib
import os
import re
import shutil
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MEMBERS = ("sodiumxt", "torrentxt", "enetxt", "datachannelxt", "coinxt")
EXT_FOR = {"linux": "so", "win32": "dll", "mac": "dylib"}


def platform_kind(platform_id):
    if platform_id.endswith("-linux"):
        return "linux"
    if platform_id.endswith("-win32"):
        return "win32"
    if platform_id == "universal-mac" or platform_id.endswith("-mac"):
        return "mac"
    return None


def read_format(path):
    """(kind, arch) read from the file header, or (None, reason)."""
    with open(path, "rb") as fh:
        head = fh.read(64)
    if len(head) < 20:
        return None, "too short to be a library"
    if head[:4] == b"\x7fELF":
        cls = head[4]                      # 1 = 32-bit, 2 = 64-bit
        machine = struct.unpack_from("<H", head, 18)[0]
        arch = {0x03: "x86", 0x3E: "x86_64", 0xB7: "arm64"}.get(machine, f"e_machine {machine:#x}")
        if cls == 1 and arch == "x86_64":
            arch = "x86"                   # belt and braces; should not happen
        return "linux", arch
    if head[:2] == b"MZ":
        off = struct.unpack_from("<I", head, 0x3C)[0]
        with open(path, "rb") as fh:
            fh.seek(off)
            sig = fh.read(6)
        if sig[:4] != b"PE\0\0":
            return None, "MZ header without a PE signature"
        machine = struct.unpack_from("<H", sig, 4)[0]
        arch = {0x014C: "x86", 0x8664: "x86_64", 0xAA64: "arm64"}.get(machine, f"machine {machine:#x}")
        return "win32", arch
    # Mach-O, thin (any endianness/width) or fat.
    magic = struct.unpack_from(">I", head, 0)[0]
    if magic in (0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE):
        return "mac", "thin"
    if magic in (0xCAFEBABE, 0xBEBAFECA):
        return "mac", "universal"
    return None, "unrecognised object format"


def coinxt_exports(path):
    """The cnx_-filtered export list of an ELF, or None when unreadable here."""
    try:
        out = subprocess.run(["nm", "-D", "--defined-only", path],
                             capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    return {ln.split()[-1] for ln in out.splitlines() if ln.split()}


def main(argv):
    if len(argv) < 2:
        sys.exit(__doc__.strip())
    bundle = os.path.abspath(argv[1])
    dry = "--dry-run" in argv[2:]
    if not os.path.isdir(bundle):
        sys.exit(f"install-release-binaries: {bundle} is not a directory")

    plan, problems, skipped = [], [], []

    for member in sorted(os.listdir(bundle)):
        mdir = os.path.join(bundle, member)
        if not os.path.isdir(mdir):
            continue
        if member not in MEMBERS:
            skipped.append(f"{member}/ (not a native suite member)")
            continue
        for platform_id in sorted(os.listdir(mdir)):
            pdir = os.path.join(mdir, platform_id)
            if not os.path.isdir(pdir):
                continue
            kind = platform_kind(platform_id)
            if kind is None:
                problems.append(f"{member}/{platform_id}: unknown platform id")
                continue
            want = f"{member}.{EXT_FOR[kind]}"
            src = os.path.join(pdir, want)
            if not os.path.exists(src):
                have = [f for f in os.listdir(pdir) if not f.endswith(".md")]
                problems.append(
                    f"{member}/{platform_id}: expected {want}, found {have or 'nothing'} "
                    f"- the engine resolves the bind token to that exact name")
                continue

            got_kind, got_arch = read_format(src)
            if got_kind is None:
                problems.append(f"{member}/{platform_id}/{want}: {got_arch}")
                continue
            if got_kind != kind:
                problems.append(
                    f"{member}/{platform_id}/{want}: it is a {got_kind} library "
                    f"in a {kind} directory")
                continue
            # The arch half, from the header rather than the path.
            if kind in ("linux", "win32"):
                want_arch = platform_id.rsplit("-", 1)[0]
                if got_arch != want_arch:
                    problems.append(
                        f"{member}/{platform_id}/{want}: built for {got_arch}, not "
                        f"{want_arch} - a cross build that reported the build "
                        f"machine's arch would look exactly like this")
                    continue
            elif got_arch == "thin":
                # A REFUSAL, not a note. `universal-mac` is a promise about the
                # file, and a thin dylib breaks it in the worst way available:
                # it loads perfectly on the machine that built it and fails only
                # for users on the other architecture. This is not hypothetical -
                # macos-15 runners are arm64-only, so the obvious CI lane builds
                # exactly this, and committing one would have replaced
                # sodiumxt's genuine 2-architecture dylib with an arm64-only
                # file. release-binaries.yml has no macOS lanes for that reason;
                # this check is what stops a hand-assembled bundle doing it too.
                # Build each slice and `lipo -create` them.
                problems.append(
                    f"{member}/{platform_id}/{want}: a THIN Mach-O, but "
                    f"{platform_id} promises a universal binary - it would load "
                    f"for whoever built it and fail for everyone on the other "
                    f"architecture. lipo the two slices together first")
                continue

            if member == "coinxt" and kind == "linux":
                exports = coinxt_exports(src)
                if exports is None:
                    skipped.append(f"coinxt/{platform_id}: export check (nm unavailable)")
                else:
                    extra = {e for e in exports if not e.startswith("cnx_")}
                    if extra:
                        problems.append(
                            f"coinxt/{platform_id}/{want}: exports {len(extra)} symbol(s) "
                            f"outside the cnx_ surface, e.g. {sorted(extra)[:5]} - built "
                            f"without src/coinxt.map")
                        continue

            dst = os.path.join(ROOT, member, "src", "code", platform_id, want)
            plan.append((member, platform_id, src, dst))

    for s in skipped:
        print(f"  note: {s}")
    if problems:
        print("\ninstall-release-binaries: REFUSING to install; nothing was written.")
        for p in problems:
            print(f"  {p}")
        return 1
    if not plan:
        print("install-release-binaries: the bundle contained no installable library")
        return 1

    print(f"\n{len(plan)} librar{'y' if len(plan) == 1 else 'ies'} verified:")
    for member, platform_id, src, dst in plan:
        old = ""
        if os.path.exists(dst):
            with open(dst, "rb") as fh:
                a = hashlib.sha256(fh.read()).hexdigest()
            with open(src, "rb") as fh:
                b = hashlib.sha256(fh.read()).hexdigest()
            old = "  (unchanged)" if a == b else "  (REPLACES the committed one)"
        else:
            old = "  (new)"
        print(f"  {member}/{platform_id}/{os.path.basename(dst)}{old}")

    if dry:
        print("\n--dry-run: nothing written.")
        return 0

    touched = set()
    for member, _platform_id, src, dst in plan:
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(src, dst)
        touched.add(member)

    # Refresh each touched member's manifest over EVERY library it has, not just
    # the ones in this bundle: the manifest is a statement about the directory.
    #
    # Members that have never had one GET one, and that is called out rather than
    # done quietly. Only sodiumxt and coinxt ship a src/code manifest today, so a
    # member whose binaries this tool lands is also a member that gains integrity
    # checking - tools/build-all.sh picks the file up automatically and verifies
    # it from then on. That is an improvement, but it changes what the gates
    # cover, so it belongs in the output and in the diff you review rather than
    # turning up later as a mystery file.
    for member in sorted(touched):
        code = os.path.join(ROOT, member, "src", "code")
        existed = os.path.exists(os.path.join(code, "MANIFEST.sha256"))
        lines = []
        for dirpath, _dirnames, filenames in os.walk(code):
            for fn in sorted(filenames):
                if fn == "MANIFEST.sha256" or fn.endswith(".md"):
                    continue
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, code)
                with open(full, "rb") as fh:
                    lines.append(f"{hashlib.sha256(fh.read()).hexdigest()}  {rel}")
        with open(os.path.join(code, "MANIFEST.sha256"), "w", encoding="utf-8") as fh:
            fh.write("\n".join(sorted(lines, key=lambda l: l.split("  ", 1)[1])) + "\n")
        verb = "refreshed" if existed else "CREATED (new integrity coverage for this member)"
        print(f"  {verb} {member}/src/code/MANIFEST.sha256 ({len(lines)} file(s))")

    print("\nInstalled. Review with `git status` / `git diff --stat`, run "
          "`tools/build-all.sh --gates`, then commit deliberately (suite rule 5).")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
