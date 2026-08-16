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
import struct
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

# The 35 entry points src/coinxt.map narrows the library down to (ABI 5). A
# library that does not export all of them will fail to bind at load, silently,
# which is why this is checked here rather than discovered on a user's machine.
# Keep this list equal to the cnx_* definitions in native/coinxt.c; the
# freshness gate (tools/check-binary-freshness.py) derives the same set from
# the source and holds the committed ELF libraries to it. That gate reads ELF
# only, so for a cross-built Windows DLL the check below is the only export
# gate on the install path, and a stale list here would wave a stale DLL
# through. (Between commit 55f9130 and 2026-08-16 this was ALSO stated as
# "the only missing-export check an installed DLL gets", which was false in
# the direction that matters: the reader underneath it returned "no opinion"
# for every PE, so the gate did not run at all. See read_exports below and the
# dated note in CLAUDE.md.)
EXPECTED_EXPORTS = [
    # phase 1: the ABI guard + the hash surface
    "cnx_abi_version",
    "cnx_keccak256", "cnx_sha3_256", "cnx_sha256", "cnx_sha512", "cnx_ripemd160",
    "cnx_hmac_sha256", "cnx_hmac_sha512", "cnx_pbkdf2_hmac_sha512",
    "cnx_keccak256_len", "cnx_sha3_256_len", "cnx_sha256_len", "cnx_sha512_len",
    "cnx_ripemd160_len", "cnx_hmac_sha256_len", "cnx_hmac_sha512_len",
    # phase 2: the secp256k1 curve
    "cnx_seckey_verify", "cnx_pubkey_from_seckey", "cnx_pubkey_decompress",
    "cnx_ecdsa_sign", "cnx_ecdsa_verify", "cnx_ecdsa_sign_recoverable",
    "cnx_ecdsa_recover", "cnx_ecdh",
    "cnx_seckey_len", "cnx_pubkey_len_compressed", "cnx_pubkey_len_uncompressed",
    "cnx_ecdsa_sig_len", "cnx_recoverable_sig_len", "cnx_ecdh_len",
    # phase 4: the BIP-32 curve steps + the BIP-39 wordlist
    "cnx_seckey_tweak_add", "cnx_pubkey_tweak_add",
    "cnx_bip39_wordlist", "cnx_bip39_wordlist_len",
    # ABI 5: the secret-hygiene wipe the .lcb runs on every out-buffer
    "cnx_memzero",
    # ABI 6: BIP-340 Schnorr and the BIP-341 Taproot tweak (upstream libsecp256k1)
    "cnx_schnorr_sign", "cnx_schnorr_verify", "cnx_xonly_pubkey_from_seckey",
    "cnx_taproot_tweak_pubkey", "cnx_taproot_tweak_seckey",
    "cnx_schnorr_sig_len", "cnx_xonly_pubkey_len", "cnx_taproot_output_len",
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


class ExportReadError(Exception):
    """We recognised the container format and then failed to read it.

    This is NOT the same thing as "no opinion". A file whose format we can
    parse but whose export table does not parse is malformed, and installing a
    malformed library is exactly the outcome this whole check exists to
    prevent. Callers turn this into a refusal, never a warning.
    """


def detect_format(path):
    """Identify the container by magic: 'pe', 'elf', 'macho' or 'unknown'.

    Magic rather than the file extension, because the extension is chosen by
    the --platform-id the caller passed and this is precisely where a caller
    who mismatched the two must be caught.
    """
    with open(path, "rb") as handle:
        head = handle.read(4)
    if head[:4] == b"\x7fELF":
        return "elf"
    if head[:2] == b"MZ":
        return "pe"
    if head[:4] in (b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe",
                    b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe",
                    b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
        return "macho"
    return "unknown"


def read_pe_exports(path):
    """Return the set of names in a PE's EXPORT NAME TABLE. Raises, never shrugs.

    WHY THIS IS PARSED HERE AND NOT SHELLED OUT. The fail-open this replaces
    came from depending on a tool whose PE support is OPTIONAL: binutils `nm`
    only reads PE when it was configured with the pe targets, and on a plain
    Linux binutils it opens a mingw DLL far enough to list the IMPORT thunks
    (type I) and nothing else. Filtering the thunks out (the 2026-08-16 fix)
    stopped the false refusal but left an empty set, which the old contract
    turned into None - "no opinion" - for exactly the artifact class that has
    no other export gate in the tree. Parsing the header here removes the
    dependency entirely: any host that can run this script can read a PE, so
    "cannot check a DLL" stops being a state this tool can be in. `objdump -p`
    would have worked on THIS host (the repo's Windows checks do use binutils),
    but it would have re-created the same "works until the host's binutils is
    plain" hole one layer down, and it would mean parsing a text listing whose
    shape is a binutils implementation detail rather than the file format.
    ~60 lines of stdlib struct reading is the cheaper of the two.

    We read the [Ordinal/Name Pointer] table specifically - the loader's own
    by-name binding table, which is what the engine's `c:coinxt>cnx_*` binds
    resolve through. Not a scan of the file for `cnx_` strings: a name occurs
    in a binary for many reasons (a debug string, an unexported static's
    symbol) and only its presence in THIS table means the loader can find it.
    Ordinal-only exports have no entry here, correctly: an export the engine
    cannot name is an export CoinXT cannot use.

    Names are returned VERBATIM, with no underscore stripping. A leading `_`
    or a trailing `@N` is a real decoration mismatch (the engine resolves the
    bind string by exact name), so it must read as a missing export, not be
    normalised away into a pass.
    """
    with open(path, "rb") as handle:
        image = handle.read()

    def u16(off):
        if off < 0 or off + 2 > len(image):
            raise ExportReadError("truncated: wanted 2 bytes at 0x%x" % off)
        return struct.unpack_from("<H", image, off)[0]

    def u32(off):
        if off < 0 or off + 4 > len(image):
            raise ExportReadError("truncated: wanted 4 bytes at 0x%x" % off)
        return struct.unpack_from("<I", image, off)[0]

    # DOS stub -> e_lfanew -> the PE signature.
    pe_off = u32(0x3c)
    if image[pe_off:pe_off + 4] != b"PE\x00\x00":
        raise ExportReadError("no PE signature at e_lfanew (0x%x): this starts "
                              "with MZ but is not a PE image" % pe_off)
    coff = pe_off + 4
    section_count = u16(coff + 2)
    optional_size = u16(coff + 16)
    optional = coff + 20

    # The optional header's magic decides where the data directory count and
    # the directories themselves sit. PE32 and PE32+ differ by the width of
    # four fields before them, hence the 96 / 112 split; getting this wrong
    # would read the WRONG directory, so it is a hard branch with no default.
    magic = u16(optional)
    if magic == 0x10b:      # PE32 (our x86-win32 build)
        dir_count_off, dir_off = optional + 92, optional + 96
    elif magic == 0x20b:    # PE32+ (our x86_64-win32 build)
        dir_count_off, dir_off = optional + 108, optional + 112
    else:
        raise ExportReadError("unknown optional-header magic 0x%x" % magic)
    if u32(dir_count_off) < 1:
        raise ExportReadError("the image declares no data directories, so it "
                              "cannot carry an export table")

    export_rva, export_size = u32(dir_off), u32(dir_off + 4)
    if export_rva == 0 or export_size == 0:
        # A real, checkable answer and not an error: this DLL exports nothing.
        # The caller then reports all 35 names missing and refuses, which is
        # the correct verdict for a library that would bind none of them.
        return set()

    # RVA -> file offset needs the section table: an RVA is an offset into the
    # LOADED image, and the on-disk layout differs from it by each section's
    # own (VirtualAddress - PointerToRawData).
    sections = []
    section_table = optional + optional_size
    for index in range(section_count):
        base = section_table + index * 40
        sections.append((u32(base + 12),    # VirtualAddress
                         u32(base + 8),     # VirtualSize
                         u32(base + 20),    # PointerToRawData
                         u32(base + 16)))   # SizeOfRawData

    def rva_to_offset(rva):
        for vaddr, vsize, raw_ptr, raw_size in sections:
            if vaddr <= rva < vaddr + max(vsize, raw_size):
                delta = rva - vaddr
                # Past SizeOfRawData the bytes exist only once the loader has
                # zero-filled them; there is nothing in the FILE to read, so
                # an export table pointing there is malformed, not empty.
                if delta >= raw_size:
                    raise ExportReadError(
                        "RVA 0x%x lands in a section's virtual-only tail" % rva)
                return raw_ptr + delta
        raise ExportReadError("RVA 0x%x is in no section" % rva)

    # IMAGE_EXPORT_DIRECTORY: NumberOfNames at +24, AddressOfNames at +32.
    directory = rva_to_offset(export_rva)
    name_count = u32(directory + 24)
    names_rva = u32(directory + 32)
    if name_count == 0:
        return set()
    if name_count > 65535:
        # PE ordinals are 16-bit, so a larger count is a corrupt field being
        # read as a length. Refuse rather than allocate on it.
        raise ExportReadError("implausible export-name count %d" % name_count)

    name_table = rva_to_offset(names_rva)
    names = set()
    for index in range(name_count):
        start = rva_to_offset(u32(name_table + 4 * index))
        end = image.find(b"\x00", start)
        if end < 0:
            raise ExportReadError("export name %d is not NUL-terminated" % index)
        names.add(image[start:end].decode("ascii", "replace"))
    return names


def read_nm_exports(path):
    """ELF / Mach-O exports via `nm`, or None if this host cannot tell.

    None means "no opinion" and is still the contract HERE, for two formats
    where it is honest: an ELF install is separately gated by
    tools/check-binary-freshness.py, which reads ELF directly and holds the
    committed libraries to the same cnx_* set on every gate run, and a Mach-O
    on a Linux host may genuinely be unreadable (binutils needs the mach-o
    targets). The caller prints a loud warning on a None; it must never be the
    quiet normal path, which is what it had become for PEs.
    """
    tool = shutil.which("nm")
    if tool is None:
        return None
    # `-D` (dynamic symbols) is the ELF form and errors on Mach-O, so try it
    # first and fall back. Success is judged by nm's EXIT STATUS, not by
    # whether names came back: a library that really exports nothing is an
    # answer (and a refusal), not a reason to shrug.
    for args in (["-D", "--defined-only"], ["--defined-only"]):
        try:
            out = subprocess.run([tool] + args + [path], check=True,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except (subprocess.CalledProcessError, OSError):
            continue
        names = set()
        for line in out.stdout.decode("utf-8", "replace").splitlines():
            parts = line.split()
            # nm prints "value type name". Type I is an indirect/import thunk,
            # never a definition this library provides; Mach-O carries the
            # leading underscore the C name does not have.
            if len(parts) == 3 and parts[1] != "I":
                names.add(parts[2].lstrip("_"))
        return names
    return None


def read_exports(path):
    """Return the library's exported names, or None only when truly unknowable.

    Dispatches on the container's MAGIC. A PE always produces a real answer or
    raises ExportReadError; only ELF (separately gated), Mach-O and an
    unrecognised container can come back None.
    """
    fmt = detect_format(path)
    if fmt == "pe":
        return read_pe_exports(path)
    if fmt in ("elf", "macho"):
        return read_nm_exports(path)
    return None


def install_lib(src_lib, platform_id, dry_run):
    """Install a library built elsewhere into src/code/<platform-id>/."""
    if not os.path.exists(src_lib):
        sys.exit("package-extension: --lib %s does not exist" % src_lib)
    suffix = PLATFORM_SUFFIX[platform_id]
    dest_dir = os.path.join(CODE_ROOT, platform_id)
    dest = os.path.join(dest_dir, "coinxt" + suffix)

    fmt = detect_format(src_lib)
    if fmt == "unknown":
        # Every platform id this tool knows maps to ELF, PE or Mach-O, so a
        # container that is none of the three cannot be a shared library for
        # any of them. Refusing here also means the no-opinion branch below is
        # reachable only by a format we know and this host merely cannot read.
        sys.exit("package-extension: %s is not an ELF, PE or Mach-O image "
                 "(its magic matches none of them), so it cannot be the shared "
                 "library for any platform id this tool supports. Refusing to "
                 "install it." % src_lib)
    try:
        exports = read_exports(src_lib)
    except ExportReadError as exc:
        # Fail CLOSED. We recognised the format, so "could not read it" says
        # something is wrong with the file, not with this host.
        sys.exit("package-extension: %s is a %s image whose export table could "
                 "not be read (%s). A library whose exports cannot be "
                 "established is exactly what this check exists to stop. "
                 "Refusing to install it." % (src_lib, fmt.upper(), exc))
    if exports is not None:
        missing = [s for s in EXPECTED_EXPORTS if s not in exports]
        if missing:
            sys.exit("package-extension: %s is missing %d of the %d cnx_* exports "
                     "(%s). It would fail to bind at load. Refusing to install it."
                     % (src_lib, len(missing), len(EXPECTED_EXPORTS),
                        ", ".join(missing[:4])))
        extra = sorted(s for s in exports if s.startswith("cnx_")
                       and s not in EXPECTED_EXPORTS)
        if extra:
            print("  note: %d unexpected cnx_* export(s): %s"
                  % (len(extra), ", ".join(extra[:6])))
        # Name the table the verdict came from. "checked" is worth little if
        # the reader is silent about WHAT it read, which is how a check that
        # was reading a PE's import thunks passed unnoticed for a day.
        source = {"pe": "PE export name table",
                  "elf": "ELF dynamic symbols",
                  "macho": "Mach-O symbol table"}[fmt]
        print("  exports: all %d cnx_* entry points present (%s)"
              % (len(EXPECTED_EXPORTS), source))
    else:
        # The one surviving no-opinion path, and it is deliberately LOUD. It
        # can only be reached by a Mach-O or an unrecognised container (a PE
        # raises, an ELF answers whenever nm exists and is separately held by
        # tools/check-binary-freshness.py), so it should be rare enough that a
        # human reads the warning rather than learning to scroll past it.
        print("  WARNING: exports NOT checked - no usable nm for this %s object "
              "on this host." % fmt)
        print("           %s is being installed WITHOUT the missing-export gate."
              % os.path.basename(src_lib))
        print("           Re-run this on a host whose nm reads the format, or "
              "verify the %d cnx_* names by hand." % len(EXPECTED_EXPORTS))

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
