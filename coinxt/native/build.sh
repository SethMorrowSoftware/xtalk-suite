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
vendor_src="$ven/sha3.c $ven/sha2.c $ven/ripemd160.c $ven/hmac.c $ven/pbkdf2.c $ven/memzero.c"

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
#include <stdint.h>
#include <stdio.h>
#include <string.h>
extern int cnx_abi_version(void);
extern int cnx_keccak256(const unsigned char *, size_t, unsigned char *);
extern int cnx_sha3_256(const unsigned char *, size_t, unsigned char *);
extern int cnx_sha256(const unsigned char *, size_t, unsigned char *);
extern int cnx_sha512(const unsigned char *, size_t, unsigned char *);
extern int cnx_ripemd160(const unsigned char *, size_t, unsigned char *);
extern int cnx_hmac_sha256(const unsigned char *, size_t, const unsigned char *, size_t, unsigned char *);
extern int cnx_hmac_sha512(const unsigned char *, size_t, const unsigned char *, size_t, unsigned char *);
extern int cnx_pbkdf2_hmac_sha512(const unsigned char *, size_t, const unsigned char *, size_t,
                                  uint32_t, unsigned char *, size_t);
/* Compare the first `n` bytes of a digest against its hex spelling. */
static int eqn(const unsigned char *b, int n, const char *hexexp) {
  char h[129];
  for (int i = 0; i < n; i++) sprintf(h + 2 * i, "%02x", b[i]);
  return strcmp(h, hexexp) == 0;
}
static int eq(const unsigned char *b, const char *hexexp) { return eqn(b, 32, hexexp); }
int main(void) {
  unsigned char o[64];
  if (cnx_abi_version() != 2) { printf("ABI FAIL\n"); return 1; }
  cnx_keccak256((const unsigned char *)"", 0, o);
  if (!eq(o, "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470")) { printf("keccak empty FAIL\n"); return 1; }
  cnx_keccak256(NULL, 0, o); /* NULL-with-zero guard path */
  cnx_sha3_256((const unsigned char *)"abc", 3, o);
  if (!eq(o, "3a985da74fe225b2045c172d6bd390bd855f086e3e9d525b46bfe24511431532")) { printf("sha3 abc FAIL\n"); return 1; }
  /* SHA-2 / RIPEMD-160 against their published "abc" vectors. */
  cnx_sha256((const unsigned char *)"abc", 3, o);
  if (!eq(o, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")) { printf("sha256 abc FAIL\n"); return 1; }
  cnx_sha512((const unsigned char *)"abc", 3, o);
  if (!eqn(o, 64, "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a"
                  "2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f")) { printf("sha512 abc FAIL\n"); return 1; }
  cnx_ripemd160((const unsigned char *)"abc", 3, o);
  if (!eqn(o, 20, "8eb208f7e05d987a9b044a8e98c6b087f15a0bfc")) { printf("ripemd160 abc FAIL\n"); return 1; }
  /* HMAC-SHA256, RFC 4231 test case 1. */
  {
    unsigned char k[20]; memset(k, 0x0b, sizeof k);
    cnx_hmac_sha256(k, sizeof k, (const unsigned char *)"Hi There", 8, o);
    if (!eq(o, "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7")) { printf("hmac-sha256 FAIL\n"); return 1; }
  }
  /* The guards must FAIL CLOSED rather than quietly do the wrong thing. */
  if (cnx_pbkdf2_hmac_sha512((const unsigned char *)"pw", 2, (const unsigned char *)"salt", 4, 0, o, 32) != -3) { printf("pbkdf2 zero-iterations guard FAIL\n"); return 1; }
  if (cnx_pbkdf2_hmac_sha512((const unsigned char *)"pw", 2, (const unsigned char *)"salt", 4, 1, o, 0) != -2) { printf("pbkdf2 zero-outlen guard FAIL\n"); return 1; }
  if (cnx_sha256((const unsigned char *)"x", 1, NULL) != -1) { printf("null-out guard FAIL\n"); return 1; }
  if (cnx_sha256(NULL, 1, o) != -1) { printf("null-in-with-length guard FAIL\n"); return 1; }
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
