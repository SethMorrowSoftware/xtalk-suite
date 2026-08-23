#!/usr/bin/env python3
"""
install-release-binaries.py - land a release-binaries bundle into the tree.

USAGE
    python3 tools/install-release-binaries.py <bundle-dir> [--dry-run]
    python3 tools/install-release-binaries.py --selftest

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

--selftest is this file's own regression, and it lives here rather than in a
sibling tool because what it pins is THIS file's behaviour, end to end. It drives
main() over throwaway bundles - the five COMMITTED box2dxt libraries for the
accept case, synthesised headers for the refusals - and asserts what each one is
supposed to do: that a box2dxt bundle installs at all (it did not, until
2026-08-17), that an unknown member directory is still merely skipped rather than
installed, that a thin Mach-O and a wrong architecture and a wrong filename are
each REFUSED, and that both manifest legs below - refreshed and CREATED - do what
their message says, driven against a temporary ROOT so the real tree is never
written. The accept case deliberately reads the member's real committed files
instead of synthesising them, because a synthetic ELF would prove only that the
parser parses. This repo's standing lesson is that SHIPPED IS NOT RUN: a claim
that can be pinned by executing the code should not be left as a comment.
"""

import contextlib
import hashlib
import io
import os
import re
import shutil
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# The members whose libraries this tool will land. Anything else in a bundle is
# reported as skipped, which is the right default - the bundle directory is
# whatever the workflow or a human unzipped, not a trusted manifest.
#
# BOX2DXT JOINED 2026-08-17, and the token is VERIFICATION-ONLY. It does NOT put
# box2dxt in a release lane and deliberately does not pre-empt the decision
# box2dxt/CLAUDE.md reserves for the owner: its known-good Linux build runs
# `docker run manylinux2014` INSIDE a stock runner (glibc floor 2.17), while
# release-binaries.yml's cmake-members job uses the `container:` shape with
# manylinux_2_28, so joining that matrix as-is would raise the member's glibc
# floor - a real portability regression, and a call nobody should make as a
# side effect of editing a Python tuple. Until that lane exists, nothing in CI
# produces a box2dxt bundle and this token is inert there.
#
# What it DOES buy is the hand-assembled path, which is the one people actually
# use for a member with no lane: a locally built or unzipped box2dxt bundle used
# to be routed to "not a native suite member" and then refused with "the bundle
# contained no installable library", so the only way to land those five binaries
# was to copy them in by hand - with none of the filename, object-format,
# architecture or fat-Mach-O checks below run over them, and the manifest
# refreshed by hand or not at all. That is exactly the failure mode suite rule 5
# exists to prevent, so the fix is worth landing ahead of the YAML half.
MEMBERS = ("sodiumxt", "torrentxt", "enetxt", "datachannelxt", "coinxt", "box2dxt")
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


# Mach-O CPU types, from <mach/machine.h>: CPU_ARCH_ABI64 (0x01000000) OR'd
# onto CPU_TYPE_X86 (7) and CPU_TYPE_ARM (12).
_MACHO_CPU = {0x00000007: "x86", 0x01000007: "x86_64",
              0x0000000C: "arm", 0x0100000C: "arm64"}


def fat_archs(path):
    """The architecture names inside a FAT Mach-O header, or None when the
    file is not one. A fat MAGIC alone is not a universal binary - the header
    carries a slice COUNT and per-slice cputypes, and a fat file with one
    slice (or two of the same arch) is legal and loads exactly like a thin
    one: for whoever built it, and for nobody else. Now that CI lanes emit
    these, the promise `universal-mac` makes has to be checked against the
    slice table, not the magic."""
    with open(path, "rb") as fh:
        head = fh.read(8)
        if len(head) < 8 or struct.unpack_from(">I", head, 0)[0] != 0xCAFEBABE:
            return None
        nfat = struct.unpack_from(">I", head, 4)[0]
        if not 0 < nfat <= 16:      # a real fat file has a handful of slices
            return None
        archs = []
        body = fh.read(20 * nfat)   # fat_arch: cputype,cpusubtype,offset,size,align
        if len(body) < 20 * nfat:
            return None
        for i in range(nfat):
            cputype = struct.unpack_from(">I", body, 20 * i)[0]
            archs.append(_MACHO_CPU.get(cputype, f"cputype {cputype:#x}"))
        return sorted(archs)


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
                # macos-15 runners are arm64-only, so the OBVIOUS CI lane builds
                # exactly this, and committing one would have replaced
                # sodiumxt's genuine 2-architecture dylib with an arm64-only
                # file. (Until 2026-08-23 release-binaries.yml had no macOS
                # lanes for that reason; its mac lanes now build BOTH slices via
                # CMAKE_OSX_ARCHITECTURES / multi-arch CC and assert `lipo
                # -archs` at birth, and this check plus the slice check below
                # are what stop a hand-assembled bundle - or a regressed lane -
                # from landing anything less.) Build each slice and
                # `lipo -create` them.
                problems.append(
                    f"{member}/{platform_id}/{want}: a THIN Mach-O, but "
                    f"{platform_id} promises a universal binary - it would load "
                    f"for whoever built it and fail for everyone on the other "
                    f"architecture. lipo the two slices together first")
                continue
            elif got_arch == "universal":
                # The fat MAGIC is not the promise; the slice table is. A fat
                # container carrying one slice - or two of the same arch - is
                # legal Mach-O and fails users exactly like the thin case above.
                archs = fat_archs(src)
                if archs is None:
                    problems.append(
                        f"{member}/{platform_id}/{want}: fat Mach-O magic but "
                        f"the slice table is unreadable - refusing a file this "
                        f"tool cannot verify")
                    continue
                if not {"x86_64", "arm64"} <= set(archs):
                    problems.append(
                        f"{member}/{platform_id}/{want}: a fat Mach-O carrying "
                        f"only {'+'.join(archs)} - universal-mac promises BOTH "
                        f"x86_64 and arm64 slices")
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
    # done quietly: tools/build-all.sh picks a MANIFEST.sha256 up automatically
    # and verifies it from then on, so creating one changes what the gate set
    # covers. That is an improvement, but a change in gate coverage belongs in the
    # output and in the diff you review rather than turning up later as a mystery
    # file.
    #
    # CORRECTED 2026-08-17. The line here used to say "only sodiumxt and coinxt
    # ship a src/code manifest today". Measured against the tree: ALL SIX members
    # that have a src/code carry one - sodiumxt, torrentxt, enetxt, datachannelxt,
    # coinxt, and box2dxt (whose manifest landed with its 2026-08-14 fold) - which
    # is exactly the set MEMBERS names. So the CREATED leg cannot fire on today's
    # tree, and the comment was inviting a reader to reason from a false premise
    # about which members are protected.
    #
    # The leg is KEPT rather than deleted, for two reasons. This tool creates the
    # destination directory too (os.makedirs above), so it is the path by which a
    # member's FIRST binaries arrive, and it is the only place that would notice.
    # And MEMBERS grows - box2dxt was added to it the same day this comment was
    # corrected - so "no member lacks a manifest" is a fact about today's tuple,
    # not an invariant. Deleting the leg would mean the next member to join lands
    # binaries with no integrity coverage and no notice that the gate set just
    # changed shape. It is not dead-by-neglect either: --selftest drives both legs
    # against a throwaway ROOT, so the branch is EXECUTED on every gate run rather
    # than asserted to work - which is the distinction that made the sentence above
    # wrong for as long as it was.
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


# --------------------------------------------------------------------------
# --selftest
# --------------------------------------------------------------------------
# Header synthesisers. Each writes the exact prefix read_format() reads and not
# one byte more - these are fixtures for the FORMAT checks, not loadable
# libraries, and pretending otherwise would only invite someone to try one.

def _bytes_elf(elf_class, e_machine):
    """A 64-byte ELF header. elf_class: 1 = 32-bit, 2 = 64-bit."""
    head = bytearray(64)
    head[0:4] = b"\x7fELF"
    head[4] = elf_class
    struct.pack_into("<H", head, 18, e_machine)
    return bytes(head)


def _bytes_pe(machine):
    """An MZ stub whose e_lfanew points at a PE signature and machine word."""
    head = bytearray(0x46)
    head[0:2] = b"MZ"
    struct.pack_into("<I", head, 0x3C, 0x40)
    head[0x40:0x44] = b"PE\0\0"
    struct.pack_into("<H", head, 0x44, machine)
    return bytes(head)


def _bytes_thin_macho():
    """A 64-bit little-endian THIN Mach-O magic - byte for byte what an
    arm64-only macos runner emits, and what universal-mac must refuse."""
    return b"\xcf\xfa\xed\xfe" + bytes(60)


def _bytes_fat_macho(cputypes):
    """A FAT Mach-O header with the given cputype list - the slice TABLE is
    what universal-mac actually promises, so the fixtures must be able to
    spell both the honest two-arch case and the one-slice container that
    carries the fat magic while breaking the promise."""
    head = bytearray(struct.pack(">II", 0xCAFEBABE, len(cputypes)))
    for cpu in cputypes:
        head += struct.pack(">IIIII", cpu, 0, 0, 0, 0)
    return bytes(head)


def _put(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(data)


def _capture(args):
    """main() over argv, stdout captured -> (rc, text). The gate drives the
    real entry point rather than the helpers underneath it, because the bug it
    exists to catch - a member missing from MEMBERS - lives in the routing, and
    every helper below is perfectly happy without it."""
    buf = io.StringIO()
    try:
        with contextlib.redirect_stdout(buf):
            rc = main(["install-release-binaries.py"] + args)
    except Exception as exc:  # noqa: BLE001 - deliberately everything
        # A traceback out of main() is a FAILURE of the check that is running,
        # not a crash of the gate. Reporting it as one keeps the remaining
        # checks running and names the fixture that caused it - measured while
        # mutation-testing this gate: deleting the "expected <member>.<ext>"
        # existence check makes read_format() raise FileNotFoundError, which
        # ended the whole run with a bare traceback and no indication of which
        # bundle it came from. 99 is returned so that every rc assertion here
        # (which expects 0 or 1) fails rather than accidentally matching.
        return 99, buf.getvalue() + f"\n[raised] {type(exc).__name__}: {exc}"
    return rc, buf.getvalue()


def selftest():
    global ROOT
    failures = []
    tmp = tempfile.mkdtemp(prefix="install-release-selftest-")

    def check(name, ok, detail=""):
        print(f"  {'ok  ' if ok else 'FAIL'}  {name}")
        if not ok:
            failures.append(f"{name}\n        got: {detail}")

    try:
        # 1. THE ACCEPT CASE, over the member's REAL committed libraries. This is
        #    the box2dxt claim in executable form: before box2dxt was in MEMBERS
        #    this exact bundle printed one skip note and returned 1.
        #
        #    The expected count is READ FROM THE TREE rather than written down as
        #    5 (which is what it was on 2026-08-17: four ELF/PE targets plus the
        #    fat universal-mac dylib). A hard 5 would redden this gate the day
        #    box2dxt gains an arm64-linux target - a good change - and a gate that
        #    goes red for good changes is a gate somebody deletes. The property
        #    worth pinning is "EVERY committed library of this member passes every
        #    check in this file", which survives the platform set moving.
        code = os.path.join(ROOT, "box2dxt", "src", "code")
        bundle = os.path.join(tmp, "bundle")
        staged = 0
        for platform_id in sorted(os.listdir(code)):
            pdir = os.path.join(code, platform_id)
            if not os.path.isdir(pdir):
                continue
            for fn in sorted(f for f in os.listdir(pdir) if not f.endswith(".md")):
                _put(os.path.join(bundle, "box2dxt", platform_id, fn), b"")
                shutil.copy2(os.path.join(pdir, fn),
                             os.path.join(bundle, "box2dxt", platform_id, fn))
                staged += 1
        check("box2dxt ships committed libraries to verify (suite rule 5)",
              staged > 0, staged)

        rc, out = _capture([bundle, "--dry-run"])
        check("a box2dxt bundle is accepted (rc 0)", rc == 0, out)
        check(f"  ...with all {staged} libraries verified",
              f"{staged} libraries verified" in out, out)
        check("  ...and NOT routed to 'not a native suite member'",
              "not a native suite member" not in out, out)
        check("  ...writing nothing under --dry-run",
              "--dry-run: nothing written." in out, out)
        # Positively, not just by the absence of a complaint: the committed dylib
        # really is fat, so the accept above is not the thin-Mach-O leg passing by
        # accident on a file it should have refused.
        dylib = os.path.join(code, "universal-mac", "box2dxt.dylib")
        check("the committed universal-mac dylib reads as a FAT Mach-O",
              read_format(dylib) == ("mac", "universal"), read_format(dylib))

        # 2. THE REFUSALS. Each one proves a leg of the accept case is live rather
        #    than vacuous - a checker that says yes to everything would pass 1.
        _put(os.path.join(tmp, "thin", "box2dxt", "universal-mac", "box2dxt.dylib"),
             _bytes_thin_macho())
        rc, out = _capture([os.path.join(tmp, "thin"), "--dry-run"])
        check("a THIN Mach-O under universal-mac is REFUSED",
              rc == 1 and "THIN Mach-O" in out, out)

        # The fat magic alone must not be enough: a one-slice fat container is
        # legal Mach-O and fails users exactly like the thin case. This is the
        # shape a mac CI lane regresses to if its CMAKE_OSX_ARCHITECTURES flag
        # is dropped and someone "fixes" the thin refusal by wrapping the lone
        # slice in a fat header.
        _put(os.path.join(tmp, "oneslice", "box2dxt", "universal-mac",
                          "box2dxt.dylib"), _bytes_fat_macho([0x0100000C]))
        rc, out = _capture([os.path.join(tmp, "oneslice"), "--dry-run"])
        check("a fat Mach-O carrying ONLY arm64 is REFUSED",
              rc == 1 and "carrying only arm64" in out, out)
        check("  ...and the real committed dylib carries both slices",
              fat_archs(dylib) is not None
              and {"x86_64", "arm64"} <= set(fat_archs(dylib)),
              fat_archs(dylib))

        _put(os.path.join(tmp, "arch", "box2dxt", "x86-linux", "box2dxt.so"),
             _bytes_elf(2, 0x3E))
        rc, out = _capture([os.path.join(tmp, "arch"), "--dry-run"])
        check("an x86_64 ELF filed under x86-linux is REFUSED",
              rc == 1 and "built for x86_64, not x86" in out, out)

        _put(os.path.join(tmp, "pe", "box2dxt", "x86_64-win32", "box2dxt.dll"),
             _bytes_pe(0x014C))
        rc, out = _capture([os.path.join(tmp, "pe"), "--dry-run"])
        check("an x86 PE filed under x86_64-win32 is REFUSED",
              rc == 1 and "built for x86, not x86_64" in out, out)

        _put(os.path.join(tmp, "name", "box2dxt", "x86_64-linux", "libbox2dxt.so"),
             _bytes_elf(2, 0x3E))
        rc, out = _capture([os.path.join(tmp, "name"), "--dry-run"])
        check("a mis-named library is REFUSED (the bind token is a filename)",
              rc == 1 and "expected box2dxt.so" in out, out)

        # 3. THE ROUTING box2dxt used to get. Skipping an unknown directory is
        #    correct and must survive; what was wrong was which directories
        #    counted as unknown.
        _put(os.path.join(tmp, "unknown", "onionxt", "x86_64-linux", "onionxt.so"),
             _bytes_elf(2, 0x3E))
        rc, out = _capture([os.path.join(tmp, "unknown"), "--dry-run"])
        check("a non-member directory is skipped, never installed",
              rc == 1 and "not a native suite member" in out, out)

        # 4. BOTH MANIFEST LEGS, against a throwaway ROOT so the real tree is
        #    untouched. The CREATED leg cannot fire on this tree (every member in
        #    MEMBERS already ships a manifest), which is precisely why it needs
        #    executing here: it is the branch a future member's first install
        #    takes, and nothing else would ever run it.
        saved_root, fake_root = ROOT, os.path.join(tmp, "root")
        try:
            ROOT = fake_root
            rc, out = _capture([bundle])
            created = os.path.join(fake_root, "box2dxt", "src", "code",
                                   "MANIFEST.sha256")
            check("a first install CREATES the member's manifest, and says so",
                  rc == 0 and "CREATED (new integrity coverage" in out
                  and os.path.exists(created), out)
            body = []
            if os.path.exists(created):
                with open(created, encoding="utf-8") as fh:
                    body = fh.read().splitlines()
            check("  ...covering every library it landed and nothing else",
                  len(body) == staged and all(len(ln.split("  ", 1)[0]) == 64
                                              for ln in body), body)
            rc, out = _capture([bundle])
            check("a second install REFRESHES it instead",
                  rc == 0 and "refreshed box2dxt/src/code/MANIFEST.sha256" in out,
                  out)
            check("  ...reporting the now-identical libraries unchanged",
                  out.count("(unchanged)") == staged, out)
        finally:
            ROOT = saved_root
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    if failures:
        print(f"\ninstall-release-binaries --selftest: {len(failures)} FAILURE(S)")
        for f in failures:
            print(f"  {f}")
        return 1
    print("\ninstall-release-binaries --selftest: all checks passed.")
    return 0


if __name__ == "__main__":
    # --selftest is dispatched before the bundle-dir argument handling: it takes
    # no bundle, and main() would otherwise print the docstring and exit.
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    sys.exit(main(sys.argv))
