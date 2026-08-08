#!/bin/sh
# build.sh - build the CoinXT native shim.
#
# Three outputs, on purpose (CLAUDE.md "Commands"):
#   libcoinxt.<ext>  - a plain shared library the ctypes KAT harness loads. Built
#                      without sanitizers so it can be loaded into a
#                      non-instrumented host process. Lands in native/, which is
#                      NOT where the extension looks - this one is for tooling.
#   cnx_selftest     - an ASan + UBSan executable that exercises the shim and is
#                      run to prove the native code is memory-clean.
#   src/code/<arch>-<platform>/coinxt.<ext>
#                    - the SHIPPED library: the exact file the packaged extension
#                      carries and the engine dlopen()s when src/coinxt.lcb binds
#                      `c:coinxt>`. Filtered to the cnx_* surface, stripped, and
#                      named for the bind token (the `pack` target below).
#
# Usage:  sh native/build.sh                  # the tooling library (native/)
#         sh native/build.sh asan             # build + run the ASan/UBSan self-test
#         sh native/build.sh pack             # the SHIPPED library into src/code/
#         sh native/build.sh pack x86-linux   # ... for an explicit platform id
#                                             # (REQUIRED for any cross build)
#
# Run from the CoinXT/ directory (or anywhere; paths are resolved from this file).

set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)   # .../CoinXT/native
root=$(CDPATH= cd -- "$here/.." && pwd)             # .../CoinXT
ven="$here/vendor"

# The vendored trezor-crypto translation units this phase needs.
#
# The curve half of this list is a CLOSURE, not a wish list: it was found by
# compiling the set, reading the undefined symbols, adding the file that
# defines them, and repeating until the only unresolved name left was
# random_buffer - which is ours to define, on purpose (see coinxt.c). Two
# entries look gratuitous and are not:
#   hasher.c   ecdsa.h types its message-signing entry points against
#              HasherType, so ecdsa.o references the dispatch table even
#              though CoinXT only ever signs a digest;
#   blake256.c / blake2b.c / groestl.c
#              are that table's other backends. Dropping them would mean
#              editing a vendored file, which the vendor rules forbid.
# src/coinxt.map keeps every one of these names out of the shipped surface.
vendor_src="$ven/sha3.c $ven/sha2.c $ven/ripemd160.c $ven/hmac.c $ven/pbkdf2.c $ven/memzero.c \
$ven/ecdsa.c $ven/bignum.c $ven/secp256k1.c $ven/rfc6979.c $ven/hmac_drbg.c $ven/hasher.c \
$ven/blake256.c $ven/blake2b.c $ven/groestl.c $ven/base58.c $ven/address.c"

# Third-party headers are -isystem so their warnings do not pollute -Wall -Wextra.
warn="-Wall -Wextra"
inc="-isystem $ven"

# Platform libraries the shim itself needs. Windows draws blinding entropy from
# BCryptGenRandom, which lives in bcrypt.dll; Linux uses getrandom(2) and macOS
# arc4random_buf, both in libc, so neither needs a flag. Deciding this from the
# OUTPUT (the extension being built) and not from `uname` matters for the same
# reason the platform id does: a mingw cross build on Linux still needs -lbcrypt.
platform_libs() {
  case "$1" in
    dll) echo "-lbcrypt" ;;
    *)   echo "" ;;
  esac
}

case "${1:-lib}" in
  lib)
    # Pick the platform extension (best effort; default .so).
    ext=so
    case "$(uname -s 2>/dev/null || echo unknown)" in
      Darwin*) ext=dylib ;;
      MINGW*|MSYS*|CYGWIN*) ext=dll ;;
    esac
    out="$here/libcoinxt.$ext"
    cc -O2 $warn $inc -fPIC -shared "$here/coinxt.c" $vendor_src -o "$out" \
       $(platform_libs "$ext")
    echo "built $out"
    ;;
  pack)
    # The shipped artifact. Three things make it different from the `lib`
    # target, and each of them is load-bearing:
    #
    #  1. THE NAME. src/coinxt.lcb binds to "c:coinxt>cnx_*". The engine resolves
    #     that leading token to a file named `coinxt.<ext>` inside the packaged
    #     extension, NOT `libcoinxt.<ext>` - the `lib` prefix that is idiomatic
    #     everywhere else in Unix is exactly wrong here. Every sibling member
    #     ships the same way (sodiumxt.so, enetxt.so, datachannelxt.so).
    #  2. THE PATH. src/code/<arch>-<platform>/ is where the engine looks, and
    #     the directory names are the engine's spelling, not uname's.
    #  3. THE SURFACE. src/coinxt.map narrows the exports from 77 symbols to the
    #     16 cnx_* entry points; see that file for why shipping the vendored
    #     trezor-crypto names into an engine process is not acceptable. If the
    #     linker will not take a version script we say so loudly and continue,
    #     because a wide-surface library that WORKS beats no library at all - but
    #     you should not commit that one.
    #
    # The platform id may be given explicitly:  sh native/build.sh pack x86-linux
    # CROSS BUILDS MUST DO THIS. `uname` describes the MACHINE, not the output,
    # so a 32-bit build driven by a `cc` that wraps `gcc -m32` still reports
    # x86_64 - and would file an x86 library into x86_64-linux/, silently
    # overwriting a good committed binary with one for the wrong architecture.
    # Deriving it is only safe for a native build, so that stays the default and
    # anything else says what it is building.
    if [ $# -ge 2 ]; then
      platform_id="$2"
      case "$platform_id" in
        *-mac|universal-mac) ext=dylib ;;
        *-win32)             ext=dll ;;
        *)                   ext=so ;;
      esac
    else
      ext=so
      plat=linux
      case "$(uname -s 2>/dev/null || echo unknown)" in
        Darwin*)              ext=dylib; plat=mac ;;
        MINGW*|MSYS*|CYGWIN*) ext=dll;   plat=win32 ;;
      esac
      case "$(uname -m 2>/dev/null || echo unknown)" in
        x86_64|amd64)  arch=x86_64 ;;
        i?86)          arch=x86 ;;
        arm64|aarch64) arch=arm64 ;;
        *)             arch=$(uname -m) ;;
      esac
      # macOS ships one fat binary for both slices, under the engine's own name
      # for it; there is no per-arch mac directory in this family.
      if [ "$plat" = mac ]; then
        platform_id=universal-mac
      else
        platform_id="$arch-$plat"
      fi
    fi
    dir="$root/src/code/$platform_id"
    out="$dir/coinxt.$ext"
    # Build to a scratch dir and move the result into place only on success.
    # Writing straight to $out would truncate a good committed binary the moment
    # a build failed, and `mkdir -p` up front would leave an empty platform
    # directory behind that reads as "this platform is supported" when it is not.
    stage=$(mktemp -d)
    trap 'rm -rf "$stage"' EXIT
    staged="$stage/coinxt.$ext"

    # ---- the export surface, per object format ------------------------------
    # Same goal on every platform: ship the 16 cnx_* entry points and NOTHING
    # else (see src/coinxt.map for why a wide surface is unacceptable here). The
    # MECHANISM differs by object format, and picking the wrong one fails OPEN -
    # you get a working library with 77 exports - so each is handled explicitly
    # rather than left to a default:
    #
    #   ELF   a linker version script (src/coinxt.map). Filters at link time, so
    #         it reaches the vendored units too.
    #   PE    a .def file. MinGW AUTO-EXPORTS every global when no .def and no
    #         __declspec(dllexport) is present - measured: 77 symbols - and a
    #         version script is silently IGNORED for PE, which is exactly the
    #         fail-open case. Supplying a .def turns auto-export off.
    #   Mach-O  -exported_symbols_list. ld64 ignores a version script too.
    #
    # The .def and the symbols list are GENERATED from the compiled objects
    # rather than committed, so they can never drift from the shim: whatever the
    # objects define as a global cnx_* IS the export list, by construction.
    NM_TOOL="${NM:-nm}"
    STRIP_TOOL="${STRIP:-strip}"
    CC_TOOL="${CC:-cc}"

    objs=""
    for src in "$here/coinxt.c" $vendor_src; do
      obj="$stage/$(basename "$src" .c).o"
      $CC_TOOL -O2 $warn $inc -fPIC -c "$src" -o "$obj"
      objs="$objs $obj"
    done

    # Every global cnx_* the objects actually define. `nm -g --defined-only`
    # spells a defined global as a T/D/R/B code in column 2.
    exports=$($NM_TOOL -g --defined-only $objs 2>/dev/null \
              | awk '$2 ~ /^[TDRB]$/ {print $3}' \
              | sed 's/^_//' | grep '^cnx_' | sort -u)
    if [ -z "$exports" ]; then
      echo "build.sh pack: could not read any cnx_* export from the objects" >&2
      echo "  ($NM_TOOL did not report them; set NM= to the matching nm)" >&2
      exit 1
    fi

    ldflags=""
    case "$ext" in
      so)
        vscript="$root/src/coinxt.map"
        if [ ! -f "$vscript" ]; then
          echo "build.sh pack: src/coinxt.map is missing; refusing to ship a" >&2
          echo "  wide-surface library. Restore it." >&2
          exit 1
        fi
        # Two probes, not one, and the order matters. The obvious single probe -
        # "does a link WITH the version script succeed?" - cannot tell a linker
        # that refuses version scripts from a toolchain that cannot link at all,
        # and reports the second as the first. That is the worst confusion here,
        # because the "fix" it implies is to ship the wide surface. So: prove the
        # toolchain links a trivial shared object FIRST; only then does a failure
        # with the script added mean what the message says.
        if $CC_TOOL -fPIC -shared -o /dev/null -xc /dev/null 2>/dev/null; then
          if $CC_TOOL -fPIC -shared -Wl,--version-script="$vscript" -o /dev/null -xc /dev/null 2>/dev/null; then
            ldflags="-Wl,--version-script=$vscript"
          else
            echo "build.sh pack: this linker will not take src/coinxt.map;" >&2
            echo "  refusing to ship a wide-surface library." >&2
            exit 1
          fi
        fi
        ;;
      dll)
        printf 'EXPORTS\n' > "$stage/coinxt.def"
        for sym in $exports; do printf '%s\n' "$sym" >> "$stage/coinxt.def"; done
        ldflags="$stage/coinxt.def"
        ;;
      dylib)
        # ld64 wants the C symbol name with its leading underscore.
        : > "$stage/coinxt.exp"
        for sym in $exports; do printf '_%s\n' "$sym" >> "$stage/coinxt.exp"; done
        ldflags="-Wl,-exported_symbols_list,$stage/coinxt.exp"
        ;;
    esac

    $CC_TOOL -shared $objs $ldflags -o "$staged" $(platform_libs "$ext")
    # Debug info and local symbols are dead weight in a committed binary and
    # make the artifact differ run to run; --strip-unneeded keeps exactly the
    # dynamic symbols the engine needs to bind. macOS strip needs -x (a plain
    # strip on a dylib removes symbols the dynamic linker still wants).
    if command -v "$STRIP_TOOL" > /dev/null 2>&1; then
      if [ "$ext" = dylib ]; then
        "$STRIP_TOOL" -x "$staged" 2>/dev/null || true
      else
        "$STRIP_TOOL" --strip-unneeded "$staged" 2>/dev/null || "$STRIP_TOOL" "$staged" 2>/dev/null || true
      fi
    fi
    mkdir -p "$dir"
    mv "$staged" "$out"
    echo "built $out"
    echo "exported symbols (the shipped surface):"
    printf '  %s\n' $exports
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
extern int cnx_seckey_verify(const unsigned char *, size_t);
extern int cnx_pubkey_from_seckey(const unsigned char *, size_t, int, unsigned char *, size_t);
extern int cnx_pubkey_decompress(const unsigned char *, size_t, unsigned char *, size_t);
extern int cnx_ecdsa_sign(const unsigned char *, size_t, const unsigned char *, size_t,
                          unsigned char *, size_t);
extern int cnx_ecdsa_verify(const unsigned char *, size_t, const unsigned char *, size_t,
                            const unsigned char *, size_t);
extern int cnx_ecdsa_sign_recoverable(const unsigned char *, size_t, const unsigned char *, size_t,
                                      unsigned char *, size_t);
extern int cnx_ecdsa_recover(const unsigned char *, size_t, const unsigned char *, size_t,
                             unsigned char *, size_t);
extern int cnx_ecdh(const unsigned char *, size_t, const unsigned char *, size_t,
                    unsigned char *, size_t);
/* Compare the first `n` bytes of a digest against its hex spelling. */
static int eqn(const unsigned char *b, int n, const char *hexexp) {
  char h[129];
  for (int i = 0; i < n; i++) sprintf(h + 2 * i, "%02x", b[i]);
  return strcmp(h, hexexp) == 0;
}
static int eq(const unsigned char *b, const char *hexexp) { return eqn(b, 32, hexexp); }
int main(void) {
  unsigned char o[64];
  if (cnx_abi_version() != 3) { printf("ABI FAIL\n"); return 1; }
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

  /* ---- the secp256k1 surface (phase 2) ------------------------------------
   * The vectors live in tools/coin-kat.py; what THIS test adds is running the
   * curve code under ASan + UBSan, where the vendored bignum and point
   * arithmetic would report an overread or an undefined shift. So it drives
   * every entry point at least once with real inputs, and re-states only the
   * one vector that needs no table (private key 1 is the generator G). */
  {
    unsigned char sk[32], pub33[33], pub65[65], got65[65], sig[64], rsig[65], sh1[65], sh2[65];
    unsigned char digest[32], bpub[33], bsk[32];
    int i;
    for (i = 0; i < 31; i++) sk[i] = 0;
    sk[31] = 1;                                  /* the private key 1 -> G */
    if (cnx_seckey_verify(sk, 32) != 0) { printf("seckey_verify FAIL\n"); return 1; }
    if (cnx_pubkey_from_seckey(sk, 32, 1, pub33, 33) != 0) { printf("pubkey33 FAIL\n"); return 1; }
    if (!eqn(pub33, 33, "0279be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798")) {
      printf("pubkey33 is not G FAIL\n"); return 1;
    }
    if (cnx_pubkey_from_seckey(sk, 32, 0, pub65, 65) != 0) { printf("pubkey65 FAIL\n"); return 1; }
    if (cnx_pubkey_decompress(pub33, 33, got65, 65) != 0 || memcmp(got65, pub65, 65) != 0) {
      printf("decompress FAIL\n"); return 1;
    }
    /* Sign and verify a real digest, then prove verification rejects. */
    cnx_sha256((const unsigned char *)"abc", 3, digest);
    if (cnx_ecdsa_sign(sk, 32, digest, 32, sig, 64) != 0) { printf("sign FAIL\n"); return 1; }
    if (cnx_ecdsa_verify(pub33, 33, digest, 32, sig, 64) != 0) { printf("verify FAIL\n"); return 1; }
    if (cnx_ecdsa_verify(pub65, 65, digest, 32, sig, 64) != 0) { printf("verify65 FAIL\n"); return 1; }
    sig[5] ^= 0x01;
    if (cnx_ecdsa_verify(pub33, 33, digest, 32, sig, 64) != -5) { printf("tamper FAIL\n"); return 1; }
    sig[5] ^= 0x01;
    /* Recoverable sign must round-trip back to the signing key. */
    if (cnx_ecdsa_sign_recoverable(sk, 32, digest, 32, rsig, 65) != 0) { printf("signrec FAIL\n"); return 1; }
    if (memcmp(rsig, sig, 64) != 0) { printf("signrec differs from sign FAIL\n"); return 1; }
    if (cnx_ecdsa_recover(rsig, 65, digest, 32, got65, 65) != 0) { printf("recover FAIL\n"); return 1; }
    if (memcmp(got65, pub65, 65) != 0) { printf("recover != signer FAIL\n"); return 1; }
    /* ECDH must agree from both sides. */
    for (i = 0; i < 31; i++) bsk[i] = 0;
    bsk[31] = 2;
    if (cnx_pubkey_from_seckey(bsk, 32, 1, bpub, 33) != 0) { printf("bpub FAIL\n"); return 1; }
    if (cnx_ecdh(sk, 32, bpub, 33, sh1, 65) != 0) { printf("ecdh a FAIL\n"); return 1; }
    if (cnx_ecdh(bsk, 32, pub33, 33, sh2, 65) != 0) { printf("ecdh b FAIL\n"); return 1; }
    if (memcmp(sh1, sh2, 65) != 0) { printf("ecdh disagreement FAIL\n"); return 1; }
    /* Fail-closed. The 0x04-prefix case is the pubkey OVERREAD guard: without
     * it upstream would read 65 bytes out of this 33-byte buffer, which is
     * exactly what ASan is here to catch if the guard ever regresses. */
    {
      unsigned char lying[33];
      memcpy(lying, pub33, 33);
      lying[0] = 0x04;
      if (cnx_ecdsa_verify(lying, 33, digest, 32, sig, 64) != -4) { printf("overread guard FAIL\n"); return 1; }
    }
    memset(sk, 0, sizeof sk);
    if (cnx_seckey_verify(sk, 32) != -4) { printf("zero seckey guard FAIL\n"); return 1; }
    if (cnx_ecdsa_sign(sk, 32, digest, 32, sig, 64) != -4) { printf("sign-with-zero-key guard FAIL\n"); return 1; }
    sk[31] = 1;
    memset(digest, 0, sizeof digest);
    if (cnx_ecdsa_sign(sk, 32, digest, 32, sig, 64) != -7) { printf("zero-digest guard FAIL\n"); return 1; }
  }
  printf("cnx_selftest: OK (ASan/UBSan clean, hashes + secp256k1)\n");
  return 0;
}
EOF
    cc $warn -fsanitize=address,undefined $inc "$tmp/selftest.c" "$here/coinxt.c" $vendor_src -o "$tmp/cnx_selftest"
    "$tmp/cnx_selftest"
    rm -rf "$tmp"
    ;;
  *)
    echo "usage: sh build.sh [lib|asan|pack]" >&2
    exit 2
    ;;
esac
