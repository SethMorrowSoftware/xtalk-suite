#!/usr/bin/env python3
"""
check-binary-freshness.py - prove the committed CoinXT binaries still match the
shim source they were built from.

WHY THIS EXISTS. Suite rule 5 says a native-library change is not done until the
committed `src/code/<arch>-<platform>/` binary is refreshed in the SAME change.
That rule is enforced by nothing except discipline, and the failure it guards
against is silent: you add `cnx_ecdsa_sign` to `native/coinxt.c`, ship the .lcb
that binds it, forget the rebuild, and the engine reports a bind failure at LOAD
time - after install, on someone else's machine, in a library that handles money.
`src/code/MANIFEST.sha256` does not catch this: it proves the committed file is
the file that was committed, not that it is the file the source would produce.

WHAT IT CHECKS, and why it is these two things and not a byte comparison. A
rebuild-and-diff would be the strongest check, but it is only meaningful when the
checking toolchain is the exact one that produced the artifact; a different gcc
emits different bytes for identical source, so on CI (or a contributor's box) it
would fail for a reason that is not a defect. These two are toolchain-independent:

  1. THE EXPORT SET. Every `cnx_*` function defined in native/coinxt.c must be
     exported by the committed library, and the library must export nothing else.
     This catches an added, removed, or renamed entry point - the case that
     actually breaks a bind - and it also catches a binary built without
     src/coinxt.map (which would export ~61 vendored trezor-crypto symbols).
  2. THE ABI NUMBER. CNX_ABI_VERSION in the source must equal what the committed
     library's cnx_abi_version() actually returns when called. This catches an
     ABI bump that the binary did not get, which is the exact skew `cxCheckABI()`
     is designed to refuse at runtime - better to refuse it here.

SKIPS, LOUDLY, when it cannot run: a platform whose binaries it cannot introspect
(it reads ELF, so Linux only), or a missing library for this machine's platform.
A skip prints why. It never passes silently on a check it did not perform.
"""

import ctypes
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)                      # .../coinxt
SHIM = os.path.join(ROOT, "native", "coinxt.c")
CODE = os.path.join(ROOT, "src", "code")

# An EXPORTED definition: `<type> cnx_name(` at column 0. The shim writes every
# export that way (`int cnx_sha256(...)`, `size_t cnx_sha256_len(void)`).
#
# `static` is excluded deliberately and this is not a detail: the shim's internal
# helpers are named cnx_* too (cnx_fits_u32, cnx_fits_int) because they share the
# file's prefix convention, but `static` means they never reach the dynamic
# symbol table. Without this exclusion the checker demanded two symbols the
# library is CORRECT not to export - which is exactly what it reported on its
# first run. A future `static` helper is covered automatically.
DEF_RE = re.compile(
    r"^(?!\s*static\b)[A-Za-z_][A-Za-z0-9_ *]*\b(cnx_[A-Za-z0-9_]+)\s*\(", re.M)
ABI_RE = re.compile(r"^\s*#\s*define\s+CNX_ABI_VERSION\s+(\d+)\s*$", re.M)


def source_facts():
    """The exports and the ABI number the shim source declares."""
    with open(SHIM, encoding="utf-8") as fh:
        src = fh.read()
    # Strip block comments so a cnx_* name inside prose cannot be mistaken for a
    # definition (the shim's header comment names several).
    src = re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    exports = set(DEF_RE.findall(src))
    m = ABI_RE.search(src)
    if m is None:
        sys.exit(f"check-binary-freshness: no CNX_ABI_VERSION in {SHIM}")
    return exports, int(m.group(1))


def elf_exports(path):
    """The defined dynamic symbols of an ELF shared object, or None."""
    try:
        out = subprocess.run(["nm", "-D", "--defined-only", path],
                             capture_output=True, text=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError):
        return None
    return {line.split()[-1] for line in out.splitlines() if line.split()}


def main():
    want_exports, want_abi = source_facts()
    if not want_exports:
        sys.exit("check-binary-freshness: parsed 0 exports from the shim - the "
                 "definition pattern no longer matches, fix this file")

    if not os.path.isdir(CODE):
        print("check-binary-freshness: no src/code/ yet - nothing committed to check")
        return 0

    problems, checked, skipped = [], 0, []
    for entry in sorted(os.listdir(CODE)):
        d = os.path.join(CODE, entry)
        if not os.path.isdir(d):
            continue
        for fn in sorted(os.listdir(d)):
            path = os.path.join(d, fn)
            if not fn.startswith("coinxt."):
                continue
            if not fn.endswith(".so"):
                skipped.append(f"{entry}/{fn} (not ELF; this checker reads ELF only)")
                continue
            got = elf_exports(path)
            if got is None:
                skipped.append(f"{entry}/{fn} (nm unavailable or refused the file)")
                continue
            checked += 1
            missing = want_exports - got
            extra = got - want_exports
            if missing:
                problems.append(f"{entry}/{fn}: the shim defines {sorted(missing)} "
                                f"but the committed library does NOT export them - "
                                f"rebuild it (sh native/build.sh pack) and refresh "
                                f"src/code/MANIFEST.sha256")
            if extra:
                problems.append(f"{entry}/{fn}: exports {len(extra)} symbol(s) the "
                                f"shim does not define, e.g. {sorted(extra)[:6]} - "
                                f"this library was built WITHOUT src/coinxt.map; "
                                f"rebuild with sh native/build.sh pack")

    # The ABI number is a runtime fact, so it needs a load. Only the library for
    # THIS machine can be loaded, so this leg checks one file at most - which is
    # still the one that matters, because an ABI bump touches every platform.
    loadable = os.path.join(CODE, "x86_64-linux", "coinxt.so")
    if sys.platform.startswith("linux") and os.path.exists(loadable):
        try:
            lib = ctypes.CDLL(loadable)
            lib.cnx_abi_version.restype = ctypes.c_int
            got_abi = lib.cnx_abi_version()
            if got_abi != want_abi:
                problems.append(f"x86_64-linux/coinxt.so: cnx_abi_version() returns "
                                f"{got_abi} but the shim defines CNX_ABI_VERSION "
                                f"{want_abi} - the committed binary predates an ABI "
                                f"change (sh native/build.sh pack)")
        except OSError as exc:
            skipped.append(f"x86_64-linux/coinxt.so ABI call ({exc})")
    else:
        skipped.append("the ABI call (needs a linux x86_64 host and that binary)")

    for s in skipped:
        print(f"check-binary-freshness: SKIP {s}")
    if problems:
        for p in problems:
            print(f"check-binary-freshness: {p}")
        return 1
    print(f"check-binary-freshness: OK ({checked} committed library/libraries "
          f"match {len(want_exports)} shim exports, ABI {want_abi})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
