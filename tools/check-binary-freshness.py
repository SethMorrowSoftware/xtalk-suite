#!/usr/bin/env python3
"""
check-binary-freshness.py - prove every committed binary in the suite still
matches the source that is supposed to have produced it.

WHY THIS EXISTS, AND WHY AT THE SUITE LEVEL. Suite rule 5 says a native-library
change is not done until the member's committed `src/code/<arch>-<platform>/`
binary is refreshed in the SAME change. Before this file, that rule was enforced
by discipline plus ONE member's copy of this idea: `coinxt/tools/check-binary-
freshness.py`, which reads coinxt's ELF libraries only. Every other member -
sodiumxt, torrentxt, enetxt, datachannelxt, box2dxt - had nothing, and even
coinxt's copy skipped both of its Windows DLLs.

`src/code/MANIFEST.sha256` does not close that gap and was never meant to: it
proves the committed blob is UNCHANGED SINCE IT WAS COMMITTED, not that it is
the blob the current source would produce. A MinGW cross-build that lost an
export, or a shim that got an ABI bump the binary did not, passes the manifest
gate perfectly and then reaches a user as a BIND FAILURE AT LOAD TIME - on an
engine, on someone else's machine, which is exactly the scarce resource this
suite spends its gates protecting.

WHAT IT CHECKS. Four legs, in decreasing order of how portable they are:

  1. THE BIND ORACLE (enforced on every readable container). Every
     `binds to "c:<lib>>symbol"` in a member's `.lcb` must be a name the
     committed library actually EXPORTS. This is the load-time failure, stated
     directly: the engine resolves that bind string by exact name, so a symbol
     that is not in the export table is a `.lcb` that cannot load. 636 binds
     over 24 committed libraries as of 2026-08-17; 26 libraries since
     2026-08-23, when the fat Mach-O reader below brought both committed
     `universal-mac` dylibs under the same legs.
  2. THE SOURCE ORACLE (enforced). Every non-`static` `<prefix>_*` function
     defined at column 0 in the member's shim must be exported too. The bind
     oracle alone would not notice a shim export the `.lcb` has not bound yet
     (sodiumxt has 30 such), and those are the next release's binds.
  3. THE EXPORT CLOSURE (enforced where the member's build has one; see the
     per-format reasons in MEMBERS). The library must export NOTHING beyond
     those definitions plus a written tolerance list. This is what catches a
     library built without its version script - the failure mode where a member
     starts exporting several thousand vendored symbols into the engine's
     process. torrentxt already does; its row says so, with the number.
  4. THE ABI PIN (enforced wherever the constant is decodable). The member's
     `<X>_ABI_VERSION` define must equal what the committed library's
     `<x>_abi_version()` actually returns. That skew is precisely what each
     member's `xxCheckABI()` refuses at RUNTIME; refusing it here costs nobody
     an engine pass.

HOW THE ABI NUMBER IS READ WITHOUT RUNNING THE LIBRARY. coinxt's copy called
`ctypes.CDLL(...).cnx_abi_version()`, which only ever works for the ONE library
matching the host - so an ABI bump that missed the Windows DLLs (four of the six
committed platforms are not this host) was unreachable. Here the number is
DECODED from the function's own code bytes: every one of these is
`int x_abi_version(void) { return N; }`, which every compiler in the tree emits
as `[endbr] mov eax, imm32 ; ret`. We locate the function through the
container's own export table (ELF `.dynsym` st_value, PE `AddressOfFunctions`),
map its address to a file offset, and decode exactly that instruction pair - and
NOTHING else. Where a compiler emitted a prologue instead, the answer is a SKIP
naming the file and the reason, not a scan of the function body for a
plausible-looking immediate: a skip you can name beats a check you cannot
trust, and a wrong ABI number reported confidently is worse than no ABI number
at all. Measured 2026-08-17: 18 of the 24 committed libraries decode - all 12
ELF, sodiumxt's and coinxt's MinGW DLLs, and box2dxt's two; the six that do
not are torrentxt's, enetxt's and datachannelxt's Windows DLLs, whose builds
put a stack-check prologue ahead of the `mov eax`. That split is NOT simply
"MinGW decodes, MSVC does not" - box2dxt's DLLs are MSVC (VCRUNTIME140) too and
decode fine, because its `b2lc_abi_version` is a leaf with no buffers and got
no prologue. Which is the point of decoding rather than assuming: the answer is
read per file, and a file that does not read says so.

Since 2026-08-23 the Mach-O reader adds the two `universal-mac` dylibs, and
BOTH slices of each decode - through two shapes the pair above does not cover,
because the mac release lanes compile at -O0 and keep the frame pointer even in
a leaf constant function: the x86_64 slices read `push rbp ; mov rbp,rsp ;
mov eax, imm32 ; pop rbp ; ret` (an exact second shape the decoder accepts, not
a scan of the body) and the arm64 slices read `MOVZ w0, #imm16 ; RET`
(`decode_return_constant_arm64`). A fat dylib therefore contributes TWO decoded
constants, and they are held to AGREE with each other before either is held to
the header - two slices disagreeing means the fat file was assembled from two
different builds, which no single rebuild produces.

The decoder is not asked to be believed. Where the host CAN load a library
(HOST_PLATFORM below - the one committed platform whose word size and OS match
this process), leg 4 ALSO loads it in a SUBPROCESS and calls the real function,
and requires the two answers to agree. That is the
shipped-is-not-run lesson applied to this file: the byte pattern is a claim
until something executes the thing it claims to describe. The load runs in a
subprocess so that a library which crashes or hangs on load is a REPORTED
failure rather than a dead gate - and a library that cannot load at all is
itself a finding worth having.

The container readers are stdlib `struct` walks, not shell-outs to `nm`. That
is deliberate and the reason is written out in `coinxt/tools/package-
extension.py`'s `read_pe_exports`: binutils' PE support is OPTIONAL, so a plain
Linux `nm` opens a MinGW DLL far enough to list its IMPORT thunks and nothing
else - "cannot check a DLL" must not be a state this tool can be in, because
the platforms that cannot run their own binaries are exactly the ones with no
other evidence. The same argument applies one step further to ELF: `nm` is a
dependency, and this gate runs in CI. Where `nm` IS present the ELF reader is
CROSS-CHECKED against it (see `cross_check_with_nm`), for the same reason the
ABI decoder is cross-checked against the loader.

WHAT IS SKIPPED, AND WHY EACH SKIP IS WRITTEN DOWN RATHER THAN INFERRED:

  * `universal-mac` WAS the first skip here - a written exemption, per member,
    RETIRED 2026-08-23 when the fat Mach-O reader (`read_macho_fat`) landed:
    both committed dylibs now go through the same four legs as every ELF and
    PE, both slices each, plus a cross-slice leg of their own (the two
    architectures must export the IDENTICAL name set, because a fat file whose
    slices ship different APIs binds on one Mac and fails on the other).
    MAC_EXEMPTION keeps the dated history of why the reader was parked. What
    still prints as a SKIP on every run is sodiumxt's dylib measured against
    CURRENT source: it is recorded, deliberately, at a stale ABI -
    MAC_KNOWN_STALE parses the number out of sodiumxt/CLAUDE.md's own platform
    table rather than hand-copying it, the reader CONFIRMS the committed file
    decodes exactly that number, and a red build every run over a recorded,
    dispatch-pending state would be noise somebody deletes within a week. The
    allowance deletes itself: a refreshed dylib stops matching the record, and
    the MAC_KNOWN_STALE row becomes a hard failure until it is removed.
  * Six of the twelve committed Windows DLLs' ABI constants (see above). Their
    BIND, SOURCE and CLOSURE legs all still run - only the ABI number is
    unreadable there.
  * torrentxt's ELF export closure (see its row).

Nothing else is skipped. Every skip prints, with its reason, on every run - and
the summary line prints the COUNTS, not just "OK", so a leg whose pattern
quietly stopped matching shows up as a number that moved.

RUN IT: `python3 tools/check-binary-freshness.py` from anywhere (it locates the
repo from its own path). Exit 0 green, 1 with every problem printed.

  --installing   Tolerate a src/code/<platform>/ directory holding a library
                 this file's `ships` row does not declare, instead of refusing
                 it. ONLY release-binaries.yml's post-install gate step passes
                 this: that job runs tools/install-release-binaries.py and then
                 gates the tree it just wrote, so it is the one context where a
                 platform can legitimately appear ahead of the row that
                 declares it. Gained platforms print either way.
"""

import os
import re
import shutil
import struct
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TAG = "check-binary-freshness"

# Set from --installing in main(). See the `ships` block in check_member() for
# why the tolerance it turns on is scoped to one caller rather than always on.
INSTALLING = False


class ReadError(Exception):
    """The container is a format we recognise but could not read.

    Raised, never swallowed into a None. We identified the file by its magic,
    so "could not read it" says something is wrong with the FILE, and a library
    whose exports cannot be established is the thing this gate exists to refuse.
    """


# --------------------------------------------------------------------------
# The per-member table.
#
# ONE tool with a table, not six carried copies. The family already carries
# `check-livecodescript.py` per member and pays for it with
# `check-checker-drift.py` + `test-checker.py` to prove the copies are the same
# tool; that price buys something there (each member stays self-contained on
# its standalone mirror). It would buy nothing here: this gate reads binaries
# that only exist in this monorepo's layout, and a sixth copy set would give
# the drift checker new work for no benefit.
# --------------------------------------------------------------------------

MEMBERS = [
    {
        "name": "sodiumxt",
        # `lib` is BOTH halves of the same fact: the name inside the engine's
        # bind string (`c:sodiumxt>sxt_init`) and the basename on disk
        # (`sodiumxt.so`). They are one name because the engine resolves the
        # first by looking for the second; asserting them separately would be
        # asserting the same thing twice.
        "lib": "sodiumxt",
        "lcb": ["sodiumxt/src/sodium.lcb"],
        "ships": ["x86-linux", "x86_64-linux", "x86-win32", "x86_64-win32",
                  "universal-mac"],
        "shim": "sodiumxt/src/sodium_shim.c",
        "prefix": "sxt_",
        "abi_header": "sodiumxt/src/sodium_shim.h",
        "abi_define": "SXT_ABI_VERSION",
        "abi_symbol": "sxt_abi_version",
        # Measured 2026-08-17: exports == definitions exactly, on all four
        # readable platforms. libsodium is linked in but not re-exported.
        # Measured 2026-08-23, the day the Mach-O reader landed: the mac
        # dylib's 105 exports (both slices) are all shim definitions too -
        # FEWER than today's source defines, which is its recorded staleness,
        # but nothing beyond the source. The mac linker adds no _init/_fini.
        "closure": {"elf": [], "pe": [], "macho": []},
    },
    {
        "name": "torrentxt",
        "lib": "torrentxt",
        "lcb": ["torrentxt/src/torrent.lcb"],
        # universal-mac exists as a directory holding only a README ("macOS
        # build pending" in the release matrix), so it is NOT declared here:
        # this list is the platforms that must contain a LIBRARY.
        "ships": ["x86-linux", "x86_64-linux", "x86-win32", "x86_64-win32"],
        "shim": "torrentxt/src/torrent_shim.cpp",
        "prefix": "btx_",
        "abi_header": "torrentxt/src/btx_abi.h",
        "abi_define": "BTX_ABI_VERSION",
        "abi_symbol": "btx_abi_version",
        "closure": {
            # OFF for ELF, with the number. The Linux builds statically link
            # libtorrent, boost and libstdc++ with no version script, so
            # x86_64-linux/torrentxt.so exports 5419 names beyond the shim's 78
            # (`_ZGTtNKSt11logic_error4whatEv` and friends). That is a real
            # difference from every other member, not a defect this gate can
            # act on - and a tolerance list long enough to cover it would be a
            # list of libstdc++'s exports, which is not a thing this repo
            # should own. The BIND and SOURCE oracles still run on those two
            # libraries; only the closure is off.
            "elf": "the COMMITTED Linux builds predate src/torrentxt.map and "
                   "export 5419 statically-linked libtorrent/boost/libstdc++ "
                   "symbols beyond the shim's own (measured 2026-08-17). The "
                   "version script landed 2026-08-26, so this skip is now "
                   "scoped to the binaries in the tree rather than to the "
                   "member: the next Linux rebuild should export btx_* and "
                   "btx::test::* only, and THIS ENTRY SHOULD THEN BECOME A "
                   "TOLERANCE LIST (or go away). Re-measure after the next "
                   "release dispatch rather than assuming either outcome",
            # The MSVC DLLs export only what is declared, so the closure IS
            # meaningful there - it is off above for a toolchain reason, not
            # because torrentxt is exempt from the idea.
            "pe": [r"@test@btx@@"],
            # macho: src/torrentxt.map (new 2026-08-26) drives the mac link via
            # -exported_symbols_list and deliberately exports btx::test::*, the
            # hook tests/torrent_smoke_test.cpp calls on the REAL library. The
            # source oracle only collects `extern "C"` btx_* names, so without
            # this the mangled hooks read as unexpected exports and the leg
            # refuses a correct dylib. Same tolerance shape as `pe` above; the
            # reader strips Mach-O's one leading underscore, so this is the ELF
            # spelling, not a doubled-underscore one.
            "macho": [r"^_ZN3btx4test"]},
    },
    {
        "name": "enetxt",
        "lib": "enetxt",
        "lcb": ["enetxt/src/enet.lcb"],
        "ships": ["x86-linux", "x86_64-linux", "x86-win32", "x86_64-win32"],
        "shim": "enetxt/src/enet_shim.cpp",
        "prefix": "enx_",
        "abi_header": "enetxt/src/enx_abi.h",
        "abi_define": "ENX_ABI_VERSION",
        "abi_symbol": "enx_abi_version",
        "closure": {"elf": [], "pe": [], "macho": []},
    },
    {
        "name": "datachannelxt",
        "lib": "datachannelxt",
        "lcb": ["datachannelxt/src/datachannel.lcb"],
        "ships": ["x86-linux", "x86_64-linux", "x86-win32", "x86_64-win32"],
        "shim": "datachannelxt/src/datachannel_shim.cpp",
        "prefix": "dcx_",
        "abi_header": "datachannelxt/src/dcx_abi.h",
        "abi_define": "DCX_ABI_VERSION",
        "abi_symbol": "dcx_abi_version",
        "closure": {
            # The six C++ test hooks live in `namespace dcx { namespace test }`
            # and are reached by the member's own C++ smoke test, not by the
            # `.lcb`. They are not `extern "C"`, so the source oracle's
            # column-0 pattern cannot see them by design (it looks for the C
            # ABI names the engine binds); tolerating them by their MANGLED
            # form is honest about that - the tolerance names a namespace, so a
            # NEW export outside `dcx::test` is still refused.
            "elf": [r"^_ZN3dcx4test"],
            "pe": [r"@test@dcx@@"],
            # macho: the same hooks, same reason. src/datachannelxt.map now
            # drives the mac link too (-exported_symbols_list), so the dylib
            # exports dcx_* AND dcx::test::* exactly as the .so does. The
            # reader strips Mach-O's one leading underscore, so the ELF pattern
            # is the right one here rather than a doubled-underscore variant.
            "macho": [r"^_ZN3dcx4test"],
        },
    },
    {
        "name": "box2dxt",
        "lib": "box2dxt",
        "lcb": ["box2dxt/src/box2dxt.lcb"],
        "ships": ["x86-linux", "x86_64-linux", "x86-win32", "x86_64-win32",
                  "universal-mac"],
        "shim": "box2dxt/src/box2d_lc.c",
        "prefix": "b2lc_",
        # box2dxt keeps its ABI define in the shim itself, not a separate
        # header. Same fact, different file.
        "abi_header": "box2dxt/src/box2d_lc.c",
        "abi_define": "LC_ABI_VERSION",
        "abi_symbol": "b2lc_abi_version",
        "closure": {
            # box2dxt's Linux builds have no version script, so the linker's
            # own `_init`/`_fini` are in the dynamic table alongside the 370
            # b2lc_* exports. They are the ELF runtime's, not box2dxt's, and
            # they cannot collide with a bind: no `.lcb` names them. Two
            # tolerated names is the whole difference between "this member has
            # a clean export set" and "this leg cannot run for this member".
            "elf": [r"^_init$", r"^_fini$"],
            "pe": [],
            # Measured 2026-08-23: the mac dylib exports exactly the shim's
            # 370 definitions on both slices, nothing else - the mac linker
            # adds no _init/_fini, so the tolerance list is empty.
            "macho": [],
        },
    },
    {
        "name": "coinxt",
        "lib": "coinxt",
        "lcb": ["coinxt/src/coinxt.lcb"],
        "ships": ["x86-linux", "x86_64-linux", "x86-win32", "x86_64-win32"],
        # coinxt is the one member whose shim lives under native/, not src/.
        "shim": "coinxt/native/coinxt.c",
        "prefix": "cnx_",
        "abi_header": "coinxt/native/coinxt.c",
        "abi_define": "CNX_ABI_VERSION",
        "abi_symbol": "cnx_abi_version",
        # src/coinxt.map keeps this at exactly the 43 shim exports; without it
        # the library would leak ~61 vendored trezor-crypto symbols, which is
        # the case coinxt's own copy of this gate was written to catch.
        "closure": {"elf": [], "pe": [], "macho": []},
    },
]

# onionxt is pure LiveCodeScript over a local Tor daemon and has no native
# library at all, so it is absent from the table on purpose - and
# `assert_table_covers_tree` below proves that "absent" means "has no
# src/code/", rather than "was forgotten".

PLATFORMS = {
    "x86-linux": ("so", "elf"),
    "x86_64-linux": ("so", "elf"),
    "x86-win32": ("dll", "pe"),
    "x86_64-win32": ("dll", "pe"),
    "universal-mac": ("dylib", "macho"),
}

# RETIRED 2026-08-23, kept as the dated record - nothing skips on this text
# any more. universal-mac was a WRITTEN EXEMPTION from the day this gate
# landed: reading it needs a third container reader (Mach-O, and a FAT one -
# both committed dylibs carry x86_64 and arm64), which `nm` on a Linux host
# cannot stand in for (it answers "file format not recognized"), and macOS was
# the one platform the suite could not rebuild for at all, so a red build here
# would have been a red build nobody could action. The parking reason expired
# in two steps, both on 2026-08-23: release-binaries.yml gained universal mac
# lanes for four members (both slices cross-compiled in one pass and asserted
# at birth - the naive arm64-only build that would regress a fat dylib to thin
# is exactly what those lanes refuse), and the reader (`read_macho_fat` below)
# landed the same day, so both committed dylibs now go through the same legs
# as every ELF and PE.
MAC_EXEMPTION = (
    "universal-mac WAS a written exemption until 2026-08-23; the fat Mach-O "
    "reader in this file now reads both committed dylibs, both slices each. "
    "See the comment above this string for the history of why it was parked"
)

# Written per member while the exemption stood, because the two dylibs were in
# DIFFERENT states and one text covering both would have stated as fact about
# box2dxt something only measured about sodiumxt. Updated 2026-08-23, the day
# the reader landed, so neither entry states something the gate now disproves
# on every run; nothing gates on this dict any more - the operative table for
# the one remaining per-member state is MAC_KNOWN_STALE below.
MAC_MEMBER_NOTE = {
    "sodiumxt":
        "recorded stale, and since 2026-08-23 VERIFIED stale rather than "
        "cited: MAC_KNOWN_STALE parses the recorded ABI out of "
        "sodiumxt/CLAUDE.md's own platform table, and the reader holds both "
        "slices' decoded constant to that number - the SKIP that prints is a "
        "confirmed record, not an unread claim",
    "box2dxt":
        "this entry used to say \"nothing in this tree has ever read this "
        "dylib's export table ... UNVERIFIED\". False since 2026-08-23: the "
        "reader reads both slices' export tables on every run and every leg "
        "is enforced, so the README row's \"all 5 platforms\" claim is now "
        "checked here rather than taken on faith",
}

# The one recorded-stale mac state. The RECORD is the member's own platform
# table row; the number is PARSED out of it on every run, never hand-copied,
# because a hand-copied constant goes stale silently at the next bump - the
# exact failure build-preflight.py exists to prevent for the ABI macros, one
# document over. The flow in check_fat_macho: decoded == recorded means the
# KNOWN state (one SKIP, with the measured deltas); decoded == the source's
# define means the dylib was refreshed and this row is now a stale excuse (a
# hard failure until it is deleted); anything else is unrecorded skew (a hard
# failure, with all three numbers named). A member with no row here gets no
# allowance at all - its dylib is simply held to every leg.
MAC_KNOWN_STALE = {
    "sodiumxt": {
        "record": "sodiumxt/CLAUDE.md",
        # The platform table row: | `universal-mac` | 6 | STALE, ... |
        "pattern": r"^\|\s*`universal-mac`\s*\|\s*(\d+)\s*\|\s*STALE",
        "cite": "sodiumxt/CLAUDE.md's platform table row for universal-mac "
                "(echoed by README.md's release matrix)",
    },
}

# Files that legitimately sit inside src/code/ without being a library.
NON_LIBRARY_FILES = {"MANIFEST.sha256", "README.md"}

# The one committed platform this host could actually LOAD, or None. Both halves
# matter: a 64-bit Python cannot dlopen a 32-bit .so, and this gate runs on
# Linux hosts where neither the mac dylibs nor the cross-built DLLs can be
# loaded. None simply means the ABI decoder runs unconfirmed on this host,
# which prints as a skip rather than passing silently.
if sys.platform.startswith("linux"):
    HOST_PLATFORM = "x86_64-linux" if struct.calcsize("P") == 8 else "x86-linux"
else:
    HOST_PLATFORM = None


# --------------------------------------------------------------------------
# Source side.
# --------------------------------------------------------------------------

# The bind string the engine resolves: `binds to "c:<lib>><symbol>"`, with an
# optional `!<calling convention>` tail (505 of the tree's 639 binds carry
# `!cdecl`). The symbol stops at `!` or the closing quote, and it is taken
# VERBATIM - a decoration mismatch is a real bind failure, so it must read as a
# missing export rather than be normalised away into a pass.
#
# `c:>dlopen!cdecl` - an EMPTY library name - is a bind into the host PROCESS,
# not into a member library (box2dxt uses three of them to probe for its own
# .so at runtime). Requiring a non-empty name before `>` leaves those out,
# which is correct: no committed library is claimed to export them.
BIND_RE = re.compile(r'binds\s+to\s+"c:([A-Za-z0-9_.\-]+)>([^"!]+)')


def binds_from_lcb(paths, lib):
    """Every symbol the member's .lcb binds in ITS OWN library.

    A bind naming a DIFFERENT member's library would be a cross-member link
    this gate is not modelled for, so it is returned separately and refused by
    the caller rather than quietly ignored.
    """
    mine, foreign = set(), []
    for rel in paths:
        with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                for target, symbol in BIND_RE.findall(line):
                    if target == lib:
                        mine.add(symbol)
                    else:
                        foreign.append(f"{rel}:{lineno} binds c:{target}>{symbol}")
    return mine, foreign


# An EXPORTED definition: `<type> <prefix>name(` at column 0.
#
# `static` is excluded and this is not a detail - it is coinxt's guard, carried
# here because box2dxt needs it for a different reason than coinxt did. coinxt's
# shim names internal helpers `cnx_fits_u32` because they share the file's
# prefix convention; box2d_lc.c defines `static int b2lc_world_create_internal`.
# Either way `static` means the symbol never reaches the dynamic table, so
# without this exclusion the source oracle would demand a symbol the library is
# CORRECT not to export - which is exactly what coinxt's copy reported on its
# first run.
def def_re(prefix):
    return re.compile(
        r"^(?!\s*static\b)[A-Za-z_][A-Za-z0-9_ *]*\b(%s[A-Za-z0-9_]+)\s*\("
        % re.escape(prefix), re.M)


def strip_comments(src):
    """Block and line comments out, so prose cannot look like a definition.

    Every member's shim names several of its own exports in its header comment,
    and coinxt's copy strips block comments for exactly that reason. Line
    comments are stripped too: `// int cnx_foo(...)` at column 0 would
    otherwise parse as a definition, and a false definition is a false FAILURE
    demanding a symbol nothing defines.
    """
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


def shim_definitions(rel, prefix):
    """The prefix-named, non-static functions the shim defines at column 0."""
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        src = strip_comments(fh.read())
    # The C++ shims write `extern "C" BTX_API int BTX_CALL btx_foo(...)`. The
    # quotes are not in the type-token character class (widening it to admit
    # them would let string literals match), so the linkage specifier is
    # removed first. It carries no information the pattern needs: what it marks
    # is that the name is UNMANGLED, which is the only kind of name a bind
    # string can resolve anyway.
    src = re.sub(r'^extern\s+"C"\s+', "", src, flags=re.M)
    return set(def_re(prefix).findall(src))


def shim_abi(rel, define):
    """The ABI number the source declares."""
    with open(os.path.join(ROOT, rel), encoding="utf-8") as fh:
        src = fh.read()
    m = re.search(r"^\s*#\s*define\s+%s\s+(\d+)\s*$" % re.escape(define),
                  src, re.M)
    if m is None:
        sys.exit(f"{TAG}: no #define {define} in {rel} - the table is stale, "
                 f"fix it before trusting any other line of this report")
    return int(m.group(1))


# --------------------------------------------------------------------------
# Container readers. Each returns (exports:set, code_at:callable).
#
# `code_at(name)` hands back the first bytes of that export's machine code, or
# None if the name is not exported / its address is not in the file. It exists
# only for the ABI pin.
# --------------------------------------------------------------------------

def detect_format(path):
    with open(path, "rb") as fh:
        magic = fh.read(4)
    if magic[:4] == b"\x7fELF":
        return "elf"
    if magic[:2] == b"MZ":
        return "pe"
    if magic in (b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf",
                 b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe",
                 b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca"):
        return "macho"
    return "unknown"


def read_elf(path):
    """Defined dynamic symbols of an ELF shared object, plus a code reader.

    We walk `.dynsym` through the SECTION headers rather than PT_DYNAMIC
    because the section header gives the symbol COUNT directly (sh_size /
    sh_entsize); recovering it from PT_DYNAMIC means walking DT_HASH's nchain
    or decoding DT_GNU_HASH's bucket array, which is more code for the same
    answer. All twelve committed ELF libraries retain their section headers
    (measured 2026-08-17); a stripped-of-sections library raises instead of
    quietly reporting an empty export set.
    """
    with open(path, "rb") as fh:
        image = fh.read()
    if image[:4] != b"\x7fELF":
        raise ReadError("no ELF magic")
    is32 = image[4] == 1
    if image[5] != 1:
        raise ReadError("big-endian ELF; every committed library is LSB")

    def u16(off):
        return struct.unpack_from("<H", image, off)[0]

    def u32(off):
        return struct.unpack_from("<I", image, off)[0]

    def uword(off):
        return u32(off) if is32 else struct.unpack_from("<Q", image, off)[0]

    if is32:
        e_phoff, e_shoff = uword(28), uword(32)
        e_phentsize, e_phnum = u16(42), u16(44)
        e_shentsize, e_shnum, e_shstrndx = u16(46), u16(48), u16(50)
    else:
        e_phoff, e_shoff = uword(32), uword(40)
        e_phentsize, e_phnum = u16(54), u16(56)
        e_shentsize, e_shnum, e_shstrndx = u16(58), u16(60), u16(62)
    if e_shnum == 0:
        raise ReadError("no section headers (stripped?), so .dynsym cannot be "
                        "located - refusing rather than reporting no exports")

    # PT_LOAD segments map a virtual address to a file offset; the two differ
    # by each segment's own (p_vaddr - p_offset).
    loads = []
    for i in range(e_phnum):
        base = e_phoff + i * e_phentsize
        if u32(base) != 1:                      # PT_LOAD
            continue
        if is32:
            loads.append((uword(base + 8), uword(base + 16), uword(base + 4)))
        else:
            loads.append((uword(base + 16), uword(base + 32), uword(base + 8)))

    def vaddr_to_offset(vaddr):
        for seg_vaddr, filesz, offset in loads:
            if seg_vaddr <= vaddr < seg_vaddr + filesz:
                return offset + vaddr - seg_vaddr
        return None

    sections = []
    for i in range(e_shnum):
        base = e_shoff + i * e_shentsize
        name_off, sh_type = u32(base), u32(base + 4)
        if is32:
            sh_offset, sh_size = uword(base + 16), uword(base + 20)
            sh_link, sh_entsize = u32(base + 24), uword(base + 36)
        else:
            sh_offset, sh_size = uword(base + 24), uword(base + 32)
            sh_link, sh_entsize = u32(base + 40), uword(base + 56)
        sections.append((name_off, sh_type, sh_offset, sh_size, sh_link,
                         sh_entsize))

    shstr = sections[e_shstrndx][2]

    def sec_name(name_off):
        end = image.find(b"\x00", shstr + name_off)
        return image[shstr + name_off:end].decode("ascii", "replace")

    dynsym = None
    for entry in sections:
        if entry[1] == 11 and sec_name(entry[0]) == ".dynsym":   # SHT_DYNSYM
            dynsym = entry
            break
    if dynsym is None:
        raise ReadError("no .dynsym section")
    _, _, sym_off, sym_size, strtab_index, entsize = dynsym
    if entsize == 0:
        raise ReadError(".dynsym declares sh_entsize 0")
    strtab_off = sections[strtab_index][2]

    exports, addresses = set(), {}
    for i in range(sym_size // entsize):
        base = sym_off + i * entsize
        st_name = u32(base)
        if is32:
            st_value = uword(base + 4)
            st_info, st_shndx = image[base + 12], u16(base + 14)
        else:
            st_info, st_shndx = image[base + 4], u16(base + 6)
            st_value = uword(base + 8)
        if st_name == 0 or st_shndx == 0:       # unnamed, or SHN_UNDEF (import)
            continue
        # STB_GLOBAL / STB_WEAK / STB_GNU_UNIQUE. A local dynamic symbol is not
        # something another object can bind to, so it is not an export.
        if (st_info >> 4) not in (1, 2, 10):
            continue
        end = image.find(b"\x00", strtab_off + st_name)
        name = image[strtab_off + st_name:end].decode("ascii", "replace")
        exports.add(name)
        addresses[name] = st_value

    def code_at(name, count=16):
        vaddr = addresses.get(name)
        if vaddr is None:
            return None
        offset = vaddr_to_offset(vaddr)
        if offset is None:
            return None
        return image[offset:offset + count]

    return exports, code_at


def read_pe(path):
    """The PE EXPORT NAME TABLE, plus a code reader.

    The parse is carried from `coinxt/tools/package-extension.py`'s
    `read_pe_exports`, whose reasoning holds unchanged and is worth repeating
    at the point of reuse: we read the [Ordinal/Name Pointer] table, which is
    the loader's own by-name binding table and therefore the exact thing an
    engine's `c:<lib>>name` bind resolves through - not a scan of the file for
    likely-looking strings, because a name occurs in a binary for many reasons
    and only its presence in THIS table means the loader can find it.
    Ordinal-only exports have no entry here, correctly: an export the engine
    cannot NAME is an export the member cannot use.

    What is added here is the ordinal table, which coinxt's copy does not read
    because it only needed the names. Walking name index -> ordinal ->
    AddressOfFunctions gives each export's code, and that is what makes the ABI
    pin reach a Windows DLL from a Linux host.
    """
    with open(path, "rb") as fh:
        image = fh.read()

    def u16(off):
        if off < 0 or off + 2 > len(image):
            raise ReadError("truncated: wanted 2 bytes at 0x%x" % off)
        return struct.unpack_from("<H", image, off)[0]

    def u32(off):
        if off < 0 or off + 4 > len(image):
            raise ReadError("truncated: wanted 4 bytes at 0x%x" % off)
        return struct.unpack_from("<I", image, off)[0]

    pe_off = u32(0x3c)
    if image[pe_off:pe_off + 4] != b"PE\x00\x00":
        raise ReadError("no PE signature at e_lfanew (0x%x)" % pe_off)
    coff = pe_off + 4
    section_count, optional_size = u16(coff + 2), u16(coff + 16)
    optional = coff + 20

    # PE32 and PE32+ differ by the width of four fields ahead of the data
    # directories, hence the 96/112 split. Getting it wrong reads the WRONG
    # directory, so this is a hard branch with no default.
    magic = u16(optional)
    if magic == 0x10b:
        dir_count_off, dir_off = optional + 92, optional + 96
    elif magic == 0x20b:
        dir_count_off, dir_off = optional + 108, optional + 112
    else:
        raise ReadError("unknown optional-header magic 0x%x" % magic)
    if u32(dir_count_off) < 1:
        raise ReadError("the image declares no data directories")

    export_rva, export_size = u32(dir_off), u32(dir_off + 4)

    sections = []
    section_table = optional + optional_size
    for index in range(section_count):
        base = section_table + index * 40
        sections.append((u32(base + 12), u32(base + 8),
                         u32(base + 20), u32(base + 16)))

    def rva_to_offset(rva):
        for vaddr, vsize, raw_ptr, raw_size in sections:
            if vaddr <= rva < vaddr + max(vsize, raw_size):
                delta = rva - vaddr
                # Past SizeOfRawData the bytes exist only once the loader has
                # zero-filled them; there is nothing in the FILE to read.
                if delta >= raw_size:
                    raise ReadError(
                        "RVA 0x%x lands in a section's virtual-only tail" % rva)
                return raw_ptr + delta
        raise ReadError("RVA 0x%x is in no section" % rva)

    if export_rva == 0 or export_size == 0:
        # A real answer, not an error: this DLL exports nothing. The caller
        # then reports every bind missing and refuses, which is the correct
        # verdict for a library that would bind none of them.
        return set(), lambda name, count=16: None

    directory = rva_to_offset(export_rva)
    func_count, name_count = u32(directory + 20), u32(directory + 24)
    funcs_rva, names_rva, ords_rva = (u32(directory + 28), u32(directory + 32),
                                      u32(directory + 36))
    if name_count == 0:
        return set(), lambda name, count=16: None
    if name_count > 65535 or func_count > 65535:
        # PE ordinals are 16-bit, so a larger count is a corrupt field being
        # read as a length. Refuse rather than allocate on it.
        raise ReadError("implausible export count (%d names, %d functions)"
                        % (name_count, func_count))

    name_table = rva_to_offset(names_rva)
    ord_table = rva_to_offset(ords_rva)
    func_table = rva_to_offset(funcs_rva)

    exports, rvas = set(), {}
    for index in range(name_count):
        start = rva_to_offset(u32(name_table + 4 * index))
        end = image.find(b"\x00", start)
        if end < 0:
            raise ReadError("export name %d is not NUL-terminated" % index)
        name = image[start:end].decode("ascii", "replace")
        exports.add(name)
        ordinal = u16(ord_table + 2 * index)
        if ordinal < func_count:
            rvas[name] = u32(func_table + 4 * ordinal)

    def code_at(name, count=16):
        rva = rvas.get(name)
        if rva is None:
            return None
        # An RVA inside the export directory's own range is a FORWARDER (the
        # "OTHERDLL.func" string), not code. Decoding it would be decoding
        # ASCII as instructions.
        if export_rva <= rva < export_rva + export_size:
            return None
        try:
            offset = rva_to_offset(rva)
        except ReadError:
            return None
        return image[offset:offset + count]

    return exports, code_at


# Mach-O CPU types, from <mach/machine.h>: CPU_ARCH_ABI64 (0x01000000) OR'd
# onto CPU_TYPE_X86 (7) and CPU_TYPE_ARM (12). `universal-mac` PROMISES
# exactly these two architectures - a fat file missing either is the
# thin-regression tools/install-release-binaries.py refuses at install time,
# refused here at commit time too.
MACHO_CPUS = {0x01000007: "x86_64", 0x0100000C: "arm64"}

LC_SYMTAB = 0x2
LC_SEGMENT_64 = 0x19


def read_macho_slice(blob, arch):
    """Defined external symbols of ONE 64-bit Mach-O slice, plus a code
    reader - the same (exports, code_at) contract read_elf and read_pe keep,
    per slice.

    Exports come from LC_SYMTAB's nlist_64 table: not a stab ((n_type & 0xE0)
    == 0, the debugger entries), external (N_EXT, 0x01 - something another
    image can bind), and defined in a section (N_SECT, (n_type & 0x0E) ==
    0x0E - an undefined external is an IMPORT). The loader's own by-name
    structure is strictly the export TRIE (LC_DYLD_INFO / LC_DYLD_EXPORTS_
    TRIE); the nlist walk is used here because it is a fraction of the code
    and, on these builds, the same answer - the release lanes pass no
    -exported_symbols_list (which is also what makes ld keep unlisted names
    GLOBAL in the nlist), and the set was cross-checked at landing
    (2026-08-23): box2dxt's slices carry exactly the shim's 370 definitions,
    sodiumxt's exactly 105 of today's 124, zero names beyond source on
    either. A divergence in the dangerous direction - a name here the trie
    does not carry - would be a name the shim does not define, and the
    closure leg fails on those.

    Every LC_SYMTAB offset is relative to the SLICE, not the fat file; the
    caller hands this function the slice's own bytes, so they are used as-is.
    """
    if len(blob) < 32:
        raise ReadError(f"{arch} slice: truncated before mach_header_64")
    magic = struct.unpack_from("<I", blob, 0)[0]
    if magic != 0xFEEDFACF:
        raise ReadError(f"{arch} slice: magic 0x%08x is not MH_MAGIC_64 - "
                        f"both promised architectures are 64-bit "
                        f"little-endian, so anything else is the wrong "
                        f"binary" % magic)
    ncmds = struct.unpack_from("<I", blob, 16)[0]

    symtab = None
    segments = []
    off = 32                                  # mach_header_64 is 8 u32s
    for index in range(ncmds):
        if off + 8 > len(blob):
            raise ReadError(f"{arch} slice: load command {index} runs off "
                            f"the end of the slice")
        cmd, cmdsize = struct.unpack_from("<II", blob, off)
        if cmdsize < 8 or off + cmdsize > len(blob):
            raise ReadError(f"{arch} slice: load command {index} declares "
                            f"an implausible cmdsize {cmdsize}")
        if cmd == LC_SYMTAB:
            if cmdsize < 24:
                raise ReadError(f"{arch} slice: LC_SYMTAB shorter than its "
                                f"own fixed layout")
            symtab = struct.unpack_from("<IIII", blob, off + 8)
        elif cmd == LC_SEGMENT_64:
            if cmdsize < 72:
                raise ReadError(f"{arch} slice: LC_SEGMENT_64 shorter than "
                                f"its own fixed layout")
            # segname[16] at +8; vmaddr/vmsize/fileoff/filesize at +24. All
            # segments join the address map (like the ELF reader's PT_LOAD
            # walk); only filesize counts, because past it the bytes exist
            # only once the loader has zero-filled them.
            vmaddr, _vmsize, fileoff, filesize = struct.unpack_from(
                "<QQQQ", blob, off + 24)
            segments.append((vmaddr, filesize, fileoff))
        off += cmdsize
    if symtab is None:
        raise ReadError(f"{arch} slice: no LC_SYMTAB, so the symbol table "
                        f"cannot be located - refusing rather than "
                        f"reporting no exports")
    symoff, nsyms, stroff, strsize = symtab
    if symoff + 16 * nsyms > len(blob) or stroff + strsize > len(blob):
        raise ReadError(f"{arch} slice: LC_SYMTAB points outside the slice")

    exports, addresses = set(), {}
    for index in range(nsyms):
        base = symoff + 16 * index
        n_strx, n_type, _n_sect, _n_desc, n_value = struct.unpack_from(
            "<IBBHQ", blob, base)
        if n_type & 0xE0:                     # N_STAB
            continue
        if not (n_type & 0x01):               # not N_EXT
            continue
        if (n_type & 0x0E) != 0x0E:           # not N_SECT: an import
            continue
        if n_strx >= strsize:
            raise ReadError(f"{arch} slice: symbol {index} names a string "
                            f"offset outside the string table")
        end = blob.find(b"\x00", stroff + n_strx, stroff + strsize)
        if end < 0:
            raise ReadError(f"{arch} slice: symbol {index}'s name is not "
                            f"NUL-terminated inside the string table")
        name = blob[stroff + n_strx:end].decode("ascii", "replace")
        # Mach-O prepends `_` to every C symbol; the bind string and the shim
        # both spell the name WITHOUT it, so exactly one leading underscore
        # is stripped.
        if name.startswith("_"):
            name = name[1:]
        exports.add(name)
        addresses[name] = n_value

    def code_at(name, count=16):
        # n_value is a vmaddr (unslid; these dylibs' __TEXT starts at 0).
        # Map it through the segment table exactly as the ELF reader maps
        # st_value through PT_LOAD.
        vmaddr = addresses.get(name)
        if vmaddr is None:
            return None
        for seg_vmaddr, filesize, fileoff in segments:
            if seg_vmaddr <= vmaddr < seg_vmaddr + filesize:
                offset = fileoff + vmaddr - seg_vmaddr
                return blob[offset:offset + count]
        return None

    return exports, code_at


def read_macho_fat(path):
    """Both slices of a universal (fat) Mach-O: [(arch, exports, code_at)].

    The fat HEADER is big-endian even though both slices inside it are
    little-endian 64-bit images - the one place Mach-O keeps network order.
    Layout: magic u32 (0xCAFEBABE), nfat_arch u32, then per slice a fat_arch
    of five u32s (cputype, cpusubtype, offset, size, align). This is the same
    layout tools/install-release-binaries.py's `fat_archs` reads at install
    time; it is REIMPLEMENTED here rather than imported because this gate
    stays self-contained the way its ELF and PE readers already are - and
    because that tool needs only the arch names, while this one extracts the
    slices themselves.

    Raises ReadError on anything short of two well-formed slices, one per
    promised architecture. A thin Mach-O gets its own message: it is the
    naive single-arch build the install tool refuses, named as such.
    """
    with open(path, "rb") as fh:
        image = fh.read()
    if len(image) < 8:
        raise ReadError("truncated before the fat header")
    magic = struct.unpack_from(">I", image, 0)[0]
    if magic in (0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE):
        raise ReadError(
            "a THIN Mach-O where universal-mac promises a fat one - the "
            "single-architecture build tools/install-release-binaries.py "
            "refuses at install time, refused here at commit time too")
    if magic != 0xCAFEBABE:
        raise ReadError("magic 0x%08x is not FAT_MAGIC" % magic)
    nfat = struct.unpack_from(">I", image, 4)[0]
    if not 0 < nfat <= 16:
        # A real fat file has a handful of slices; a larger count is a
        # corrupt field being read as a length.
        raise ReadError("implausible fat_arch count %d" % nfat)
    slices = {}
    for index in range(nfat):
        base = 8 + 20 * index
        if base + 20 > len(image):
            raise ReadError("fat header truncated at slice %d" % index)
        cputype, _cpusub, offset, size, _align = struct.unpack_from(
            ">IIIII", image, base)
        arch = MACHO_CPUS.get(cputype)
        if arch is None:
            raise ReadError("slice %d has cputype 0x%08x, which is neither "
                            "x86_64 nor arm64 - not an architecture "
                            "universal-mac promises, so not one this gate "
                            "will guess about" % (index, cputype))
        if offset + size > len(image):
            raise ReadError(f"{arch} slice claims bytes [{offset}, "
                            f"{offset + size}) but the file ends at "
                            f"{len(image)} - truncated")
        if arch in slices:
            raise ReadError(f"two {arch} slices - legal in the format, and "
                            f"not something any build in this tree produces")
        slices[arch] = image[offset:offset + size]
    missing = sorted(set(MACHO_CPUS.values()) - set(slices))
    if missing:
        raise ReadError("no %s slice - universal-mac PROMISES both x86_64 "
                        "and arm64, and a fat container carrying one loads "
                        "for whoever built it and for nobody else"
                        % " or ".join(missing))
    out = []
    for arch in sorted(slices):               # deterministic order
        exports, code_at = read_macho_slice(slices[arch], arch)
        out.append((arch, exports, code_at))
    return out


def read_container(path, fmt):
    if fmt == "elf":
        return read_elf(path)
    if fmt == "pe":
        return read_pe(path)
    # macho does not go through here: a fat file is per-slice (exports,
    # code_at) PAIRS, and flattening them would hide exactly the cross-slice
    # disagreements check_fat_macho exists to catch.
    raise ReadError("no reader for format %r" % fmt)


# --------------------------------------------------------------------------
# The ABI pin.
# --------------------------------------------------------------------------

# `endbr64` / `endbr32`: an Intel CET landing pad the toolchain puts at the top
# of every indirectly-callable function. It is not part of the value.
ENDBR = (b"\xf3\x0f\x1e\xfa", b"\xf3\x0f\x1e\xfb")

# `push rbp ; mov rbp, rsp` - the frame-pointer prologue clang emits at -O0
# even for a leaf constant function. Its epilogue is `pop rbp` (0x5d) before
# the `ret`.
FRAME_X86_64 = b"\x55\x48\x89\xe5"


def decode_return_constant(code):
    """`[endbr] mov eax, imm32 ; ret` -> imm32, else None.

    Deliberately the narrowest possible decoder. Every one of these functions
    is `int x_abi_version(void) { return N; }`, and the six GCC/MinGW builds
    emit exactly this pair; the three MSVC ones emit a `/GS` stack-check
    prologue and put the `mov eax` somewhere inside it. Searching the body for
    a `b8` byte would "work" on those and would also match the first immediate
    of any other function that happened to be laid out that way - so this
    returns None instead, and the caller SKIPS with the member named. A wrong
    ABI number reported confidently is worse than no ABI number: it is the
    coinxt-constant-gate lesson (a gate that overstates its coverage answers
    the question nobody asks twice).

    A second exact shape was ADDED 2026-08-23, when the Mach-O reader landed:
    `push rbp ; mov rbp,rsp ; mov eax, imm32 ; pop rbp ; ret`, which is what
    the mac release lanes' clang emits at -O0 (frame pointer kept, no stack
    check - measured on both committed dylibs' x86_64 slices). It is still an
    exact instruction sequence with nothing variable but the immediate, not a
    scan; a /GS-style prologue still returns None.
    """
    if code is None:
        return None
    start = 4 if code[:4] in ENDBR else 0
    if len(code) >= start + 6 and code[start] == 0xB8 and code[start + 5] == 0xC3:
        return struct.unpack_from("<I", code, start + 1)[0]
    if (code[start:start + 4] == FRAME_X86_64 and len(code) >= start + 11
            and code[start + 4] == 0xB8 and code[start + 9] == 0x5D
            and code[start + 10] == 0xC3):
        return struct.unpack_from("<I", code, start + 5)[0]
    return None


# AArch64 fixed-width instructions, little-endian u32s.
RET_ARM64 = 0xD65F03C0
NOP_ARM64 = 0xD503201F


def decode_return_constant_arm64(code):
    """`MOVZ w0, #imm16 ; RET` -> imm16, else None.

    The arm64 half of the same bargain decode_return_constant strikes: the
    narrowest decoder that reads the committed code, and None (a named SKIP)
    for anything else. The MOVZ match is (insn & 0xFFE0001F) == 0x52800000 -
    the mask pins sf=0 (32-bit), opc=MOVZ, hw=0 (no shift) and Rd=w0, so the
    imm16 at bits 20:5 IS the value the function returns. RET must be the
    very next instruction (it is, on both committed slices) or separated only
    by NOPs: any other intervening instruction could rewrite w0, and decoding
    past one would be the confident wrong answer this file refuses everywhere
    else.
    """
    if code is None or len(code) < 8:
        return None
    insn = struct.unpack_from("<I", code, 0)[0]
    if (insn & 0xFFE0001F) != 0x52800000:
        return None
    for off in range(4, len(code) - 3, 4):
        nxt = struct.unpack_from("<I", code, off)[0]
        if nxt == RET_ARM64:
            return (insn >> 5) & 0xFFFF
        if nxt != NOP_ARM64:
            return None
    return None


def call_abi_in_subprocess(path, symbol):
    """Load the library for real and call it. (value, None) or (None, why).

    A SUBPROCESS, because this is the one leg that executes third-party code:
    a library whose static initialisers crash or hang would otherwise take the
    whole gate with it, and "the committed library does not load" is a finding
    this gate should REPORT rather than die of.
    """
    program = (
        "import ctypes,sys\n"
        "lib = ctypes.CDLL(sys.argv[1])\n"
        "fn = getattr(lib, sys.argv[2])\n"
        "fn.restype = ctypes.c_int\n"
        "print(fn())\n"
    )
    try:
        done = subprocess.run([sys.executable, "-c", program, path, symbol],
                              capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.TimeoutExpired) as exc:
        return None, f"the load did not complete ({exc})"
    if done.returncode != 0:
        detail = (done.stderr.strip().splitlines() or ["no diagnostic"])[-1]
        return None, f"the library did not load or call ({detail})"
    try:
        return int(done.stdout.strip()), None
    except ValueError:
        return None, f"the call printed {done.stdout.strip()!r}"


# --------------------------------------------------------------------------
# Guards that keep this gate from going quietly vacuous.
# --------------------------------------------------------------------------

def assert_table_covers_tree(problems):
    """Every src/code/ tree and every .lcb in the repo must be in MEMBERS.

    Without this, a seventh native member could land with committed binaries
    and this gate would stay green about a tree it never opened - the exact
    shape of hole the suite's coverage gate exists to refuse one layer up.
    """
    known_dirs = {m["name"] for m in MEMBERS}
    known_lcb = {rel for m in MEMBERS for rel in m["lcb"]}
    for entry in sorted(os.listdir(ROOT)):
        code = os.path.join(ROOT, entry, "src", "code")
        if os.path.isdir(code) and entry not in known_dirs:
            problems.append(f"{entry}/src/code/ holds committed binaries but "
                            f"{entry} is not in this file's MEMBERS table, so "
                            f"nothing checks them - add a row")
    for dirpath, dirnames, filenames in os.walk(ROOT):
        # Prune rather than filter: .git holds tens of thousands of objects and
        # a build tree holds copies of the very files being looked for, so
        # descending into either costs time to reach a wrong answer.
        dirnames[:] = [d for d in dirnames
                       if d not in (".git", "build", "node_modules")]
        for fn in filenames:
            if not fn.endswith(".lcb"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, fn), ROOT)
            if rel not in known_lcb:
                problems.append(f"{rel} is an .lcb no MEMBERS row names, so its "
                                f"foreign binds are checked against nothing - "
                                f"add it to the owning member's `lcb` list")


def cross_check_with_nm(path, exports, notes):
    """Where binutils is present, hold the ELF reader to nm's answer.

    The reader replaces a shell-out; that is only an improvement if it agrees
    with the tool it replaced. This is the same move as calling the real
    `abi_version` to check the byte decoder: a parser is a claim until
    something independent confirms it. nm's absence is not a failure - it is
    the reason the parser exists - so this only ever adds evidence.
    """
    tool = shutil.which("nm")
    if tool is None:
        return
    try:
        out = subprocess.run([tool, "-D", "--defined-only", path],
                             capture_output=True, text=True, check=True,
                             timeout=60).stdout
    except (OSError, subprocess.CalledProcessError,
            subprocess.TimeoutExpired):
        return
    theirs = set()
    for line in out.splitlines():
        parts = line.split()
        # "value type name"; type I is an indirect/import thunk, never a
        # definition this library provides.
        if len(parts) == 3 and parts[1] != "I":
            theirs.add(parts[2])
    if theirs != exports:
        only_us = sorted(exports - theirs)[:4]
        only_nm = sorted(theirs - exports)[:4]
        notes.append(f"{os.path.relpath(path, ROOT)}: this file's ELF reader "
                     f"and `nm -D --defined-only` DISAGREE (reader-only "
                     f"{only_us}, nm-only {only_nm}) - one of them is wrong "
                     f"and every verdict on this library is suspect")


# --------------------------------------------------------------------------

def check_export_legs(member, where, fmt, binds, defs, exports,
                      problems, skips, stats):
    """Legs 1-3 against ONE export set.

    Factored out of check_member on 2026-08-23, when the Mach-O reader
    landed, so the fat dylibs are held to the SAME text and the same
    tolerances as every ELF and PE rather than to a re-worded copy that
    could drift.
    """
    name = member["name"]

    # Leg 1: the bind oracle.
    missing = sorted(binds - exports)
    if missing:
        problems.append(
            f"{where}: the .lcb binds {len(missing)} symbol(s) this "
            f"library does NOT export, e.g. {missing[:6]} - the "
            f"extension would fail to bind at LOAD time on this "
            f"platform. Rebuild it and refresh "
            f"{name}/src/code/MANIFEST.sha256 in the same change "
            f"(suite rule 5)")
    else:
        stats["binds"] += len(binds)

    # Leg 2: the source oracle.
    unexported = sorted(defs - exports)
    if unexported:
        problems.append(
            f"{where}: {member['shim']} defines {len(unexported)} "
            f"non-static {member['prefix']}* function(s) this library does "
            f"not export, e.g. {unexported[:6]} - the committed binary "
            f"predates the source")

    # Leg 3: the export closure.
    tolerated = member["closure"].get(fmt)
    if tolerated is None:
        # Fail CLOSED: a member cannot ship a container format its row has
        # made no closure decision about. This is how a THIRD member
        # committing its first dylib is met - not with sodiumxt's allowance
        # inherited by default, but with a demand for its own written row.
        problems.append(
            f"{where}: this member's `closure` table has no entry for "
            f"{fmt!r} - write one (a tolerance list, or a string reason "
            f"for skipping), so the closure leg is a decision rather than "
            f"a gap")
        return
    if isinstance(tolerated, str):
        skips.append(f"{where} export closure - {tolerated}")
        return
    patterns = [re.compile(p) for p in tolerated]
    extra = sorted(e for e in exports - defs
                   if not any(p.search(e) for p in patterns))
    if extra:
        problems.append(
            f"{where}: exports {len(extra)} name(s) the shim does "
            f"not define and no tolerance covers, e.g. {extra[:6]} "
            f"- most often a library built WITHOUT its version "
            f"script, which leaks vendored symbols into the "
            f"engine's process")


def recorded_mac_stale_abi(stale):
    """The ABI number the member's own record says its mac dylib is stuck at.

    PARSED out of the record on every run, never hand-copied into this file:
    a hand-copied number goes stale silently at the next bump, which is the
    failure the root CLAUDE.md records for every other copied constant. None
    means the record no longer parses - the caller turns that into a hard
    problem, because an allowance whose written basis has gone unreadable is
    an allowance standing on nothing.
    """
    try:
        with open(os.path.join(ROOT, stale["record"]), encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return None
    m = re.search(stale["pattern"], text, re.M)
    return int(m.group(1)) if m else None


def check_fat_macho(member, path, where, binds, defs, want_abi,
                    problems, skips, stats):
    """All four legs, plus a cross-slice leg, for one committed fat dylib.

    Returns 1 when the library was opened and judged (the caller's vacuity
    guard counts it), 0 when it could not be read at all.

    The order matters. Cross-slice identity comes FIRST, because every later
    verdict is stated about "the export set" in the singular and that phrase
    is only honest once the two architectures are proven to ship the same
    API - a fat file whose slices differ binds on one Mac and fails on the
    other, and no per-set verdict can be trusted about it. The ABI decode
    runs per slice and the two constants must agree with each other BEFORE
    either is compared with the header, because two slices disagreeing means
    the fat file was assembled from two different builds - a defect no
    single rebuild produces and no header comparison would name.
    """
    try:
        slices = read_macho_fat(path)
    except ReadError as exc:
        # Fail CLOSED, same as the ELF/PE path: the platform id told us what
        # this file claims to be, so "could not read it" is a finding.
        problems.append(f"{where}: a MACHO image whose export table could "
                        f"not be read ({exc}) - a library whose exports "
                        f"cannot be established is what this gate exists to "
                        f"stop")
        return 0
    stats["libs"] += 1
    stats["mac"] += 1

    (arch_a, exports_a, _), (arch_b, exports_b, _) = slices
    if exports_a != exports_b:
        only_a = sorted(exports_a - exports_b)[:4]
        only_b = sorted(exports_b - exports_a)[:4]
        problems.append(
            f"{where}: the {arch_a} and {arch_b} slices export DIFFERENT "
            f"name sets ({arch_a}-only {only_a}, {arch_b}-only {only_b}) - "
            f"the two architectures ship different APIs, so the same stack "
            f"binds on one Mac and fails to load on the other. No leg "
            f"verdict is meaningful on a self-inconsistent library, so none "
            f"is attempted")
        return 1
    exports = exports_a

    # Leg 4's raw material: decode each slice's constant.
    values = {}
    for arch, _, code_at in slices:
        code = code_at(member["abi_symbol"], 24)
        if arch == "x86_64":
            value = decode_return_constant(code)
        else:
            value = decode_return_constant_arm64(code)
        if value is None:
            skips.append(
                f"{where} ABI pin ({arch} slice) - {member['abi_symbol']}'s "
                f"code is not a shape this file decodes, and scanning the "
                f"body for a plausible immediate would be a guess")
        else:
            values[arch] = value
            stats["abi"] += 1
    decoded = None
    if len(values) == 2:
        if values[arch_a] != values[arch_b]:
            problems.append(
                f"{where}: the two slices DISAGREE about their own ABI - "
                f"{arch_a} returns {values[arch_a]}, {arch_b} returns "
                f"{values[arch_b]} - so the fat file was assembled from two "
                f"different builds, which no single rebuild produces")
        else:
            decoded = values[arch_a]
    elif len(values) == 1:
        decoded = next(iter(values.values()))

    stale = MAC_KNOWN_STALE.get(member["name"])
    if stale is not None:
        recorded = recorded_mac_stale_abi(stale)
        if recorded is None:
            problems.append(
                f"{where}: MAC_KNOWN_STALE cites {stale['record']} but its "
                f"universal-mac STALE table row no longer parses - either "
                f"the dylib was refreshed and this member's MAC_KNOWN_STALE "
                f"row should be DELETED, or the table was reformatted and "
                f"the pattern here must follow it. Fix that before trusting "
                f"any mac verdict on this member")
            return 1
        if decoded is not None and decoded == want_abi:
            # A stale excuse, and it must go - but NOT as a hard failure here,
            # because of WHEN this fires. The only thing that refreshes this
            # dylib is install-release-binaries.py, running inside a job that
            # gates BEFORE it commits. So the refusal fired on the very run
            # that earned its removal (release run 9, 2026-08-26: sodiumxt's
            # mac dylib reached ABI 10 and this line blocked the commit that
            # would have justified deleting the row), and the row could not be
            # deleted ahead of time either - without it the still-stale ABI 6
            # dylib fails the header comparison instead. Hard-failing here is a
            # deadlock: the allowance can only be retired by a commit this line
            # refuses to allow.
            #
            # So it reports LOUDLY and lets the run proceed. The excuse is
            # still not allowed to outlive the state it excuses - this text
            # keeps printing on every subsequent run until the row is deleted,
            # and the legs below now hold the library to everything anyway, so
            # nothing is being taken on trust in the meantime. What changed is
            # only that the reminder no longer blocks its own resolution.
            skips.append(
                f"{where}: decodes ABI {decoded} == {member['abi_define']}, "
                f"so the dylib has been REFRESHED and this member's "
                f"MAC_KNOWN_STALE row is now a STALE EXCUSE - delete it (and "
                f"the {stale['record']} STALE row it cites). Reported rather "
                f"than failed because the run that refreshes the dylib is the "
                f"run that must be allowed to land it; the library is held to "
                f"every leg below regardless")
            # Fall through: a refreshed dylib gets the full legs right away.
        elif decoded is not None and decoded != recorded:
            problems.append(
                f"{where}: decodes ABI {decoded}, but {stale['cite']} "
                f"records {recorded} and {member['abi_header']} defines "
                f"{member['abi_define']} {want_abi} - a skew NOBODY wrote "
                f"down, which the recorded-stale allowance does not cover")
            # Fall through: the legs report what else disagrees.
        else:
            # decoded == recorded (or undecodable, in which case the record
            # is cited rather than confirmed and the skip says which).
            missing = sorted(binds - exports)
            unexported = sorted(defs - exports)
            extra = sorted(exports - defs)
            confirm = (f"decodes ABI {decoded} on both slices, exactly the "
                       f"recorded number"
                       if decoded is not None else
                       f"decodes on neither slice, so the recorded number "
                       f"is CITED here, not confirmed")
            skips.append(
                f"{where} bind/source/closure/ABI legs vs CURRENT source - "
                f"this dylib is the KNOWN recorded stale state, not a new "
                f"finding: {stale['cite']} records it at ABI {recorded} "
                f"while {member['abi_header']} defines "
                f"{member['abi_define']} {want_abi}, and the committed file "
                f"{confirm}. Measured against today's source: {len(missing)} "
                f"of {len(binds)} binds unresolved (e.g. {missing[:3]}), "
                f"{len(unexported)} shim definitions unexported, "
                f"{len(extra)} exported name(s) beyond the source - the "
                f"deltas a binary that predates the source is recorded to "
                f"have. This allowance deletes itself: a refreshed dylib "
                f"decodes {want_abi}, which turns the MAC_KNOWN_STALE row "
                f"into a hard failure until it is removed")
            return 1

    check_export_legs(member, where, "macho", binds, defs, exports,
                      problems, skips, stats)

    # Leg 4 proper: the agreed constant against the header. No loader
    # cross-check is possible for this format - no Linux host can dlopen a
    # Mach-O - which is the same evidence state as the cross-built DLLs.
    if decoded is not None and decoded != want_abi:
        problems.append(
            f"{where}: {member['abi_symbol']}() returns {decoded} "
            f"but {member['abi_header']} defines "
            f"{member['abi_define']} {want_abi} - the committed "
            f"binary predates an ABI change, which is the exact "
            f"skew the member's runtime ABI check refuses")
    return 1


def check_member(member, problems, skips, notes, stats):
    name, lib, prefix = member["name"], member["lib"], member["prefix"]

    binds, foreign = binds_from_lcb(member["lcb"], lib)
    for line in foreign:
        problems.append(f"{name}: {line} - a bind into a library this table "
                        f"does not model; nothing checks that symbol exists")
    if not binds:
        # coinxt's copy carries this guard and it is the important one: a
        # pattern that stops matching turns the strongest leg into a silent
        # pass over an empty set.
        problems.append(f"{name}: parsed 0 binds from {member['lcb']} - "
                        f"BIND_RE no longer matches this member's .lcb, so the "
                        f"bind oracle is checking nothing. Fix this file")
        return
    defs = shim_definitions(member["shim"], prefix)
    if not defs:
        problems.append(f"{name}: parsed 0 {prefix}* definitions from "
                        f"{member['shim']} - the definition pattern no longer "
                        f"matches. Fix this file")
        return
    want_abi = shim_abi(member["abi_header"], member["abi_define"])
    stats["distinct"] += len(binds)

    # The .lcb cannot bind a symbol the shim does not define - that is a
    # source-to-source disagreement no rebuild would fix, and it would read as
    # a missing export on every platform at once, which is a confusing way to
    # be told.
    unbacked = sorted(binds - defs)
    if unbacked:
        problems.append(f"{name}: {member['lcb'][0]} binds {unbacked[:6]} which "
                        f"{member['shim']} does not define (non-static, at "
                        f"column 0) - the .lcb and the shim disagree before any "
                        f"binary is involved")

    code_root = os.path.join(ROOT, name, "src", "code")
    if not os.path.isdir(code_root):
        problems.append(f"{name}: no src/code/ - the table says this member "
                        f"ships binaries and it does not")
        return

    checked_here = 0
    # Which platform dirs actually held this member's library. Compared against
    # the row's `ships` afterwards, because "the count went down" is not a
    # failure mode anyone notices: delete sodiumxt/src/code/x86-win32/ and every
    # leg below still passes, on 23 libraries instead of 24, and the summary
    # line is the only place it shows. A DECLARED platform is a promise the tree
    # has to keep.
    found = set()
    for platform in sorted(os.listdir(code_root)):
        pdir = os.path.join(code_root, platform)
        if not os.path.isdir(pdir):
            if platform not in NON_LIBRARY_FILES:
                problems.append(f"{name}/src/code/{platform}: an unexpected "
                                f"file at the code root")
            continue
        if platform not in PLATFORMS:
            problems.append(f"{name}/src/code/{platform}/: not a platform id "
                            f"this gate knows, so its contents are unchecked")
            continue
        suffix, fmt = PLATFORMS[platform]

        for fn in sorted(os.listdir(pdir)):
            path = os.path.join(pdir, fn)
            if fn in NON_LIBRARY_FILES:
                continue
            if fn != f"{lib}.{suffix}":
                problems.append(f"{name}/src/code/{platform}/{fn}: not the "
                                f"library name this gate expects "
                                f"({lib}.{suffix}) and not a known non-library "
                                f"file - a binary nothing checks")
                continue
            # Presence is recorded here, BEFORE any read can fail: `ships` is
            # a claim about what the tree contains, and an unreadable file is
            # still a file that is there.
            found.add(platform)

            actual = detect_format(path)
            if actual != fmt:
                problems.append(f"{name}/src/code/{platform}/{fn}: the platform "
                                f"id promises {fmt.upper()} but the file's magic "
                                f"says {actual.upper()} - the wrong binary is "
                                f"installed here")
                continue
            if fmt == "macho":
                # The per-member skip that stood here until 2026-08-23 is
                # RETIRED (see MAC_EXEMPTION for its history): the fat reader
                # runs instead. It keeps its own leg order, so it does not
                # share the ELF/PE tail below - only check_export_legs.
                checked_here += check_fat_macho(
                    member, path, f"{name}/src/code/{platform}/{fn}",
                    binds, defs, want_abi, problems, skips, stats)
                continue
            try:
                exports, code_at = read_container(path, fmt)
            except ReadError as exc:
                # Fail CLOSED. We recognised the format, so "could not read it"
                # says something is wrong with the FILE.
                problems.append(f"{name}/src/code/{platform}/{fn}: a {fmt.upper()} "
                                f"image whose export table could not be read "
                                f"({exc}) - a library whose exports cannot be "
                                f"established is what this gate exists to stop")
                continue
            if fmt == "elf":
                cross_check_with_nm(path, exports, notes)

            checked_here += 1
            stats["libs"] += 1
            where = f"{name}/src/code/{platform}/{fn}"

            # Legs 1-3, shared with the Mach-O path since 2026-08-23.
            check_export_legs(member, where, fmt, binds, defs, exports,
                              problems, skips, stats)

            # Leg 4: the ABI pin.
            decoded = decode_return_constant(code_at(member["abi_symbol"], 24))
            if decoded is None:
                skips.append(
                    f"{where} ABI pin - {member['abi_symbol']}'s code does not "
                    f"begin `[endbr] mov eax, imm32 ; ret` (this toolchain "
                    f"emitted a stack-check prologue), and scanning the body "
                    f"for a plausible immediate would be a guess")
            else:
                stats["abi"] += 1
                if decoded != want_abi:
                    problems.append(
                        f"{where}: {member['abi_symbol']}() returns {decoded} "
                        f"but {member['abi_header']} defines "
                        f"{member['abi_define']} {want_abi} - the committed "
                        f"binary predates an ABI change, which is the exact "
                        f"skew the member's runtime ABI check refuses")
                # The decoder is a claim; the loader is the evidence. Only
                # the HOST-NATIVE library can be loaded (a 64-bit process
                # cannot dlopen a 32-bit .so), so this confirms one file per
                # member - which is enough, because what is under test is the
                # DECODER, not that one library. When it agrees, the same
                # decoder's verdict on the four platforms nothing here can run
                # stops being an unexamined assumption.
                if platform == HOST_PLATFORM:
                    live, why = call_abi_in_subprocess(path,
                                                       member["abi_symbol"])
                    if live is None:
                        skips.append(f"{where} ABI loader cross-check - {why}")
                    elif live != decoded:
                        problems.append(
                            f"{where}: the ABI DECODER read {decoded} from "
                            f"{member['abi_symbol']}'s code bytes but calling "
                            f"it returns {live} - the decoder in this file is "
                            f"wrong, so every ABI verdict it reports for the "
                            f"platforms that cannot be loaded is worthless")
                    else:
                        stats["confirmed"] += 1

    # `ships` is an INVENTORY, and the leniency below is scoped to the one run
    # that is allowed to change the tree.
    #
    # Losing a platform is the failure this row exists to catch. Gaining one
    # briefly looked like it had to be tolerated everywhere: the tables state a
    # fact about the COMMITTED tree, the thing that changes the committed tree
    # is install-release-binaries.py, and it runs inside a job that gates
    # BEFORE it commits - so the first dispatch to land a member's mac dylib
    # failed here for having landed it (release run 9, 2026-08-26: four
    # members, "holds a library the table's `ships` list does not declare"),
    # and no edit could be pushed ahead of the binary either, because the
    # absent-but-declared leg above would then fire instead. A gate that can
    # only be satisfied by a commit it refuses to let happen checks nothing.
    #
    # Making growth permanently silent was the wrong way out of that, and the
    # hole is exact: the new platform never enters `ships`, so DELETING that
    # newly shipped library afterwards is neither a missing-platform failure
    # nor even a smaller number in the summary - the regression this row was
    # written to catch, reintroduced for the platform most likely to be lost,
    # the one nobody has committed twice yet. So the tolerance now lives where
    # the growth legitimately happens and nowhere else: --installing, passed by
    # release-binaries.yml's post-install gate step and by nothing that runs on
    # an ordinary push. Everywhere else a gained platform is a failure naming
    # the one-line edit that fixes it, and that edit passes on its next run
    # because the binary is committed by then.
    #
    # Either way it is PRINTED. The version this replaces put gained platforms
    # in a stats bucket nothing read, which is how a tolerance becomes
    # invisible rather than merely permissive.
    for platform in sorted(set(member["ships"]) - found):
        problems.append(f"{name}: the table says this member ships a library "
                        f"for {platform} and src/code/{platform}/ does not "
                        f"contain one - either a committed binary was lost, or "
                        f"the platform was dropped and this row was not")
    for platform in sorted(found - set(member["ships"])):
        stats.setdefault("gained", []).append(f"{name}/{platform}")
        if not INSTALLING:
            problems.append(
                f"{name}/src/code/{platform}/ holds a library this member's "
                f"row does not declare. Add \"{platform}\" to the {name} row's "
                f"`ships` list in this file, in the same change that lands the "
                f"binary - until it is there, the floor does not cover this "
                f"platform and deleting the library again would pass. (The "
                f"release job's post-install gate passes --installing, which "
                f"tolerates exactly this state for the one run that creates "
                f"it.)")

    if checked_here == 0:
        problems.append(f"{name}: no committed library was actually checked - "
                        f"this member's row is passing vacuously")


def main(argv=()):
    global INSTALLING
    unknown = [a for a in argv if a != "--installing"]
    if unknown:
        # An unrecognised flag is refused rather than ignored: a caller that
        # meant --installing and typed it wrong would otherwise get the strict
        # gate and read its failure as a real one.
        print(f"{TAG}: unknown argument(s) {unknown} - the only flag is "
              f"--installing")
        return 2
    INSTALLING = "--installing" in argv

    problems, skips, notes = [], [], []
    stats = {"libs": 0, "binds": 0, "distinct": 0, "abi": 0, "confirmed": 0,
             "mac": 0}

    assert_table_covers_tree(problems)
    for member in MEMBERS:
        check_member(member, problems, skips, notes, stats)

    # Printed BEFORE the verdict, and printed in both modes. A platform that
    # appeared without a row is either the release job's new binary (fine, this
    # run) or a library nothing declares (a problem, every other run) - and in
    # neither case may it be silent, which is what the stats bucket nothing
    # read amounted to.
    for gained in stats.get("gained", []):
        print(f"{TAG}: GAINED {gained} - a committed library whose platform "
              f"this file's `ships` row does not list yet"
              + (" (tolerated: --installing)" if INSTALLING else ""))
    for skip in skips:
        print(f"{TAG}: SKIP {skip}")
    for note in notes:
        print(f"{TAG}: NOTE {note}")
        problems.append("the ELF reader disagreed with nm (see NOTE above)")
    if problems:
        for problem in problems:
            print(f"{TAG}: {problem}")
        print(f"{TAG}: FAILED with {len(problems)} problem(s)")
        return 1
    # The numbers are the report. A gate that says only "OK" is a gate nobody
    # can tell from one whose pattern stopped matching - the lesson coinxt's
    # constant gate paid for by printing the count it had PARSED as the count
    # it had CHECKED. So: libraries actually opened, distinct binds resolved,
    # and how many of those resolutions each library was held to.
    print(f"{TAG}: OK - {stats['libs']} committed libraries across "
          f"{len(MEMBERS)} members ({stats['mac']} of them universal mac "
          f"dylibs, both slices read). {stats['distinct']} distinct .lcb "
          f"binds, {stats['binds']} bind-vs-export resolutions; every "
          f"non-static shim definition exported, outside any recorded-stale "
          f"mac state printed above; {stats['abi']} ABI constants decoded "
          f"from committed code (a fat dylib contributes one per slice), "
          f"{stats['confirmed']} of them confirmed by loading the library "
          f"and calling the function")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
