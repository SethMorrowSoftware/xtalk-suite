#!/usr/bin/env python3
"""package-extension.py - stage CoinXT as an installable OXT extension.

CoinXT was the only packaged member of the suite with no packaging tool, which
docs/OXT-PASS-RUNBOOK.md named as "the one manual step left" for this member.
This closes that.

HOW THIS DIFFERS FROM ITS SIBLINGS. sodiumxt / torrentxt / enetxt / datachannelxt
build with CMake, so their package-extension.py finds a library in a build/ tree
and installs it. CoinXT does not use CMake: `native/build.sh pack` already
builds the library, names it with the bare token, narrows its exports through
src/coinxt.map, strips it, and drops it straight into
src/code/<platform-id>/coinxt.<ext>. Re-implementing that here would be a second
source of truth for the one step that must not drift, so this tool does NOT
build. It does the three things `pack` deliberately leaves undone:

  --assemble          stage the installable layout under build/package/
  --refresh-manifest  regenerate src/code/MANIFEST.sha256 from what is committed
  --lib <path>        install a library built ELSEWHERE (a cross build, a CI
                      artifact, a macOS lipo output) into src/code/<id>/

THE MANIFEST GAP THIS EXISTS FOR. `pack` does not touch src/code/MANIFEST.sha256.
On the same toolchain that is harmless, because the build is byte-reproducible
and the committed hash still matches. But pack a platform that is NOT yet in the
manifest - macOS being the live example, since CI cannot build it - and the
committed tree now has a library the manifest does not list, which fails the
suite's integrity gate. `--refresh-manifest` is the missing half-step.

WHAT IT REFUSES TO DO. It never invents a signing identity. A macOS dylib should
be codesigned and the final package notarized before public release; that needs
Apple credentials this tool does not have, so it stays a documented manual step.
It also never produces a final .lce: real OXT packaging happens in the IDE. What
you get is a staging folder a human can point the Extension Manager at.

Usage:
  python3 tools/package-extension.py --assemble
  python3 tools/package-extension.py --refresh-manifest
  python3 tools/package-extension.py --lib /path/to/coinxt.dylib --platform-id universal-mac
  python3 tools/package-extension.py --assemble --dry-run
"""

import argparse
import hashlib
import os
import shutil
import subprocess
import sys

# ----------------------------------------------------------------- constants --
REPO_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CODE_ROOT = os.path.join(REPO_ROOT, "src", "code")
MANIFEST = os.path.join(CODE_ROOT, "MANIFEST.sha256")

# platform-id -> the shared-library EXTENSION the engine expects there. The
# committed file is always the bare token `coinxt` + this suffix: the .lcb binds
# `c:coinxt>`, and the engine resolves that token to `coinxt.<ext>`, NOT
# `libcoinxt.<ext>`. The Unix lib prefix is exactly wrong here.
PLATFORM_SUFFIX = {
    "x86_64-linux": ".so",
    "x86-linux": ".so",
    "x86_64-win32": ".dll",
    "x86-win32": ".dll",
    "universal-mac": ".dylib",
}
VALID_PLATFORM_IDS = sorted(PLATFORM_SUFFIX)

# The 16 entry points src/coinxt.map narrows the library down to. A library that
# does not export all of them will fail to bind at load, silently, which is why
# this is checked here rather than discovered on a user's machine.
EXPECTED_EXPORTS = [
    "cnx_abi_version",
    "cnx_keccak256", "cnx_sha3_256", "cnx_sha256", "cnx_sha512", "cnx_ripemd160",
    "cnx_hmac_sha256", "cnx_hmac_sha512", "cnx_pbkdf2_hmac_sha512",
    "cnx_keccak256_len", "cnx_sha3_256_len", "cnx_sha256_len", "cnx_sha512_len",
    "cnx_ripemd160_len", "cnx_hmac_sha256_len", "cnx_hmac_sha512_len",
]


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def strip_in_place(path):
    """Best effort. An unstripped binary is a size problem, not a correctness one.

    `pack` already strips what it builds; this matters only on the --lib path,
    where the artifact came from somewhere else and may carry a full symbol
    table and the build machine's absolute paths.
    """
    tool = shutil.which("strip")
    if tool is None:
        return "not stripped (no strip on PATH)"
    before = os.path.getsize(path)
    try:
        subprocess.run([tool, "--strip-unneeded", path],
                       check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except (subprocess.CalledProcessError, OSError) as exc:
        return "not stripped (%s)" % (exc,)
    return "stripped %d -> %d bytes" % (before, os.path.getsize(path))


def read_exports(path):
    """Return the library's exported symbol names, or None if we cannot tell.

    Deliberately best-effort and cross-format tolerant: `nm -D` reads ELF,
    `nm` reads Mach-O, and neither reads a cross-built Windows DLL on Linux.
    A None means "no opinion", never "bad library" - refusing to install a
    perfectly good DLL because this host has no PE reader would be worse than
    the check is worth.
    """
    tool = shutil.which("nm")
    if tool is None:
        return None
    for args in (["-D", "--defined-only"], ["--defined-only"]):
        try:
            out = subprocess.run([tool] + args + [path], check=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except (subprocess.CalledProcessError, OSError):
            continue
        names = set()
        for line in out.stdout.decode("utf-8", "replace").splitlines():
            parts = line.split()
            if parts:
                names.add(parts[-1].lstrip("_"))
        if names:
            return names
    return None


def install_lib(src_lib, platform_id, dry_run):
    """Install a library built elsewhere into src/code/<platform-id>/."""
    if not os.path.exists(src_lib):
        sys.exit("package-extension: --lib %s does not exist" % src_lib)
    suffix = PLATFORM_SUFFIX[platform_id]
    dest_dir = os.path.join(CODE_ROOT, platform_id)
    dest = os.path.join(dest_dir, "coinxt" + suffix)

    exports = read_exports(src_lib)
    if exports is not None:
        missing = [s for s in EXPECTED_EXPORTS if s not in exports]
        if missing:
            sys.exit("package-extension: %s is missing %d of the 16 cnx_* exports "
                     "(%s). It would fail to bind at load. Refusing to install it."
                     % (src_lib, len(missing), ", ".join(missing[:4])))
        extra = sorted(s for s in exports if s.startswith("cnx_")
                       and s not in EXPECTED_EXPORTS)
        if extra:
            print("  note: %d unexpected cnx_* export(s): %s"
                  % (len(extra), ", ".join(extra[:6])))
        print("  exports: all 16 cnx_* entry points present")
    else:
        print("  exports: not checked (no usable nm for this object on this host)")

    if dry_run:
        print("  would install %s -> %s" % (src_lib, os.path.relpath(dest, REPO_ROOT)))
        return
    # Only now create the directory. Doing it earlier would leave an empty
    # platform folder behind on a failure, which reads as "this platform is
    # supported" when it is not.
    os.makedirs(dest_dir, exist_ok=True)
    existed = os.path.exists(dest)
    shutil.copyfile(src_lib, dest)
    print("  %s %s" % ("updated" if existed else "created",
                       os.path.relpath(dest, REPO_ROOT)))
    print("  " + strip_in_place(dest))


def refresh_manifest(dry_run):
    """Regenerate src/code/MANIFEST.sha256 from every committed library."""
    if not os.path.isdir(CODE_ROOT):
        print("  manifest: no src/code/ yet, nothing to record")
        return
    rows = []
    for pid in VALID_PLATFORM_IDS:
        lib = os.path.join(CODE_ROOT, pid, "coinxt" + PLATFORM_SUFFIX[pid])
        if os.path.exists(lib):
            rows.append((sha256(lib), "%s/coinxt%s" % (pid, PLATFORM_SUFFIX[pid])))
    if not rows:
        print("  manifest: no committed libraries found, nothing to record")
        return
    # Sort by path so the file has a stable order and a diff shows only real
    # hash changes, never a reshuffle.
    body = "".join("%s  %s\n" % (h, p) for h, p in sorted(rows, key=lambda r: r[1]))
    old = ""
    if os.path.exists(MANIFEST):
        with open(MANIFEST, "r", encoding="utf-8") as handle:
            old = handle.read()
    if old == body:
        print("  manifest: already current (%d librar%s)"
              % (len(rows), "y" if len(rows) == 1 else "ies"))
        return
    if dry_run:
        print("  manifest: would rewrite with %d entr%s"
              % (len(rows), "y" if len(rows) == 1 else "ies"))
        return
    with open(MANIFEST, "w", encoding="utf-8") as handle:
        handle.write(body)
    print("  manifest: rewrote with %d entr%s"
          % (len(rows), "y" if len(rows) == 1 else "ies"))


def assemble_staging(dry_run):
    """Stage the installable extension layout under build/package/.

    This is a staging area for a human to point the OXT IDE at, not a finished
    package: producing a real .lce is the engine's job (revPackage / the
    Extension Manager), and this script never pretends otherwise.

        build/package/coinxt.lcb                  the LCB binding
        build/package/code/<id>/coinxt.<ext>      every committed library
        build/package/tests/coin-selftest.livecodescript
        build/package/docs/api-reference.md
        build/package/LICENSE                     CoinXT's own MIT
        build/package/THIRD-PARTY-LICENSES.md     the vendored code's licenses

    The two license files are not decoration and not optional. This staging area
    is where the COMPILED libraries go, and those statically link a vendored
    subset that is not all MIT: the SHA-2 files are BSD-3-Clause, whose clause 2
    requires the notice be reproduced "in the documentation and/or other
    materials provided with the distribution". A package that carries the binary
    and not the notice is the distribution that breaks that, so both files ship
    with it. (See ../THIRD-PARTY-LICENSES.md for the per-file map.)
    """
    staging = os.path.join(REPO_ROOT, "build", "package")
    actions = []

    def stage(rel_src, rel_dst):
        src = os.path.join(REPO_ROOT, rel_src)
        if os.path.exists(src):
            actions.append((src, os.path.join(staging, rel_dst)))

    stage(os.path.join("src", "coinxt.lcb"), "coinxt.lcb")
    # The phase-3 script layer. It is NOT part of the .lcb module: encodings and
    # addresses are pure LiveCodeScript by design (CLAUDE.md, the C-vs-script
    # split), and a user loads it into the message path - `start using stack
    # "coinxt"` - the same way OnionXT ships its ox* surface. Leaving it out of
    # the package would mean cxBtcAddressP2PKH and friends resolve to "handler
    # not found" on a machine where the binary and the binding both loaded fine.
    stage(os.path.join("src", "coinxt.livecodescript"), "coinxt.livecodescript")
    # The engine-side harness travels with the extension: the whole point of it
    # is that whoever installs this can verify the install in one paste.
    stage(os.path.join("tests", "coin-selftest.livecodescript"),
          os.path.join("tests", "coin-selftest.livecodescript"))
    stage(os.path.join("docs", "api-reference.md"),
          os.path.join("docs", "api-reference.md"))
    # The licenses travel WITH the binaries, for the reason in the docstring:
    # one of the vendored licenses binds binary redistribution specifically, and
    # this staging area is the binary redistribution.
    stage("LICENSE", "LICENSE")
    stage("THIRD-PARTY-LICENSES.md", "THIRD-PARTY-LICENSES.md")

    if os.path.isdir(CODE_ROOT):
        for pid in VALID_PLATFORM_IDS:
            suffix = PLATFORM_SUFFIX[pid]
            lib = os.path.join(CODE_ROOT, pid, "coinxt" + suffix)
            if os.path.exists(lib):
                actions.append((lib, os.path.join(staging, "code", pid,
                                                  "coinxt" + suffix)))

    if not actions:
        print("  assemble: nothing to stage yet (no .lcb / no committed libs).")
        return

    # Refuse to stage a binary without the notices that binary requires. The
    # check is here rather than in a doc comment because the failure is silent:
    # deleting a stage() line above still produces a package that installs and
    # works perfectly, and the only thing missing is the legal text that has to
    # accompany the compiled SHA-2 code. A build that is quietly out of
    # compliance is exactly the shape of bug this project gates against.
    staging_a_library = any(os.sep + "code" + os.sep in dst for _, dst in actions)
    if staging_a_library:
        missing = [name for name in ("LICENSE", "THIRD-PARTY-LICENSES.md")
                   if not any(dst.endswith(os.sep + name) for _, dst in actions)]
        if missing:
            sys.exit("package-extension: refusing to stage a compiled library "
                     "without %s. The vendored subset includes BSD-3-Clause code "
                     "(sha2.c/h) whose licence binds BINARY redistribution, so the "
                     "notice has to travel with the package. Restore the file(s) "
                     "and the matching stage() call." % " and ".join(missing))

    staged_macos = False
    for src, dst in actions:
        rel = os.path.relpath(dst, REPO_ROOT)
        if "universal-mac" in dst:
            staged_macos = True
        if dry_run:
            print("  assemble (dry-run): would stage %s" % rel)
            continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(src, dst)
        print("  assemble: staged %s" % rel)

    if staged_macos:
        print("  NOTE: the universal-mac dylib should be codesigned, and the final")
        print("        package notarized, before public release. That needs Apple")
        print("        credentials this script does not have and will not invent.")


def main(argv):
    ap = argparse.ArgumentParser(
        description="Stage CoinXT as an installable OXT extension. Does NOT build: "
                    "use `sh native/build.sh pack` for that.")
    ap.add_argument("--assemble", action="store_true",
                    help="stage the installable layout under build/package/")
    ap.add_argument("--refresh-manifest", action="store_true",
                    help="regenerate src/code/MANIFEST.sha256 from committed libraries")
    ap.add_argument("--lib",
                    help="install a library built elsewhere (cross build, CI artifact, "
                         "macOS lipo output) into src/code/<platform-id>/")
    ap.add_argument("--platform-id", choices=VALID_PLATFORM_IDS,
                    help="required with --lib; never guessed, because uname describes "
                         "the build machine and not the output")
    ap.add_argument("--dry-run", action="store_true",
                    help="report what would happen and change nothing")
    args = ap.parse_args(argv[1:])

    if args.lib and not args.platform_id:
        ap.error("--lib requires --platform-id (guessing it from uname would file a "
                 "cross build under the build machine's platform)")
    if not (args.assemble or args.refresh_manifest or args.lib):
        ap.error("nothing to do: pass --assemble, --refresh-manifest, and/or --lib")

    if args.lib:
        install_lib(args.lib, args.platform_id, args.dry_run)
        # Installing a library without recording it leaves the integrity gate
        # failing, so this is not optional: it is the other half of the action.
        refresh_manifest(args.dry_run)
    elif args.refresh_manifest:
        refresh_manifest(args.dry_run)

    if args.assemble:
        assemble_staging(args.dry_run)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
