#!/bin/sh
# build.sh - build the CoinXT native shim.
#
# Two outputs, on purpose (CLAUDE.md "Commands"):
#   libcoinxt.<ext>  - a plain shared library the LCB module (and the ctypes KAT
#                      harness) loads. Built without sanitizers so it can be loaded
#                      into a non-instrumented host process.
#   cnx_selftest     - an ASan + UBSan executable that exercises the shim and is
#                      run to prove the native code is memory-clean.
#
# Usage:  sh native/build.sh          # build the shared library
#         sh native/build.sh asan     # build + run the ASan/UBSan self-test
#
# Run from the CoinXT/ directory (or anywhere; paths are resolved from this file).

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)   # .../CoinXT/native
ven="$here/vendor"

# The vendored trezor-crypto translation units this phase needs.
vendor_src="$ven/sha3.c $ven/memzero.c"

# Third-party headers are -isystem so their warnings do not pollute -Wall -Wextra.
warn="-Wall -Wextra"
inc="-isystem $ven"

case "${1:-lib}" in
  lib)
    # Pick the platform extension (best effort; default .so).
    ext=so
    case "$(uname -s 2>/dev/null || echo unknown)" in
      Darwin*) ext=dylib ;;
      MINGW*|MSYS*|CYGWIN*) ext=dll ;;
    esac
    out="$here/libcoinxt.$ext"
    cc -O2 $warn $inc -fPIC -shared "$here/coinxt.c" $vendor_src -o "$out"
    echo "built $out"
    ;;
  asan)
    tmp=$(mktemp -d)
    cat > "$tmp/selftest.c" <<'EOF'
#include <stddef.h>
#include <stdio.h>
#include <string.h>
extern int cnx_abi_version(void);
extern int cnx_keccak256(const unsigned char *, size_t, unsigned char *);
extern int cnx_sha3_256(const unsigned char *, size_t, unsigned char *);
static int eq(const unsigned char *b, const char *hexexp) {
  char h[65];
  for (int i = 0; i < 32; i++) sprintf(h + 2 * i, "%02x", b[i]);
  return strcmp(h, hexexp) == 0;
}
int main(void) {
  unsigned char o[32];
  if (cnx_abi_version() != 1) { printf("ABI FAIL\n"); return 1; }
  cnx_keccak256((const unsigned char *)"", 0, o);
  if (!eq(o, "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")) { printf("keccak empty FAIL\n"); return 1; }
  cnx_keccak256(NULL, 0, o); /* NULL-with-zero guard path */
  cnx_sha3_256((const unsigned char *)"abc", 3, o);
  if (!eq(o, "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532")) { printf("sha3 abc FAIL\n"); return 1; }
  printf("cnx_selftest: OK (ASan/UBSan clean)\n");
  return 0;
}
EOF
    cc $warn -fsanitize=address,undefined $inc "$tmp/selftest.c" "$here/coinxt.c" $vendor_src -o "$tmp/cnx_selftest"
    "$tmp/cnx_selftest"
    rm -rf "$tmp"
    ;;
  *)
    echo "usage: sh build.sh [lib|asan]" >&2
    exit 2
    ;;
esac
