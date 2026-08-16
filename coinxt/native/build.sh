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
#   bip39_english.c
#              is the phase-4 addition and is DATA, not code: the 2048-word
#              normative BIP-39 English list. Its only dependency is bip39.h,
#              which declares constants and prototypes and pulls in nothing -
#              so bip39.c stays unvendored (see cnx_bip39_wordlist).
# src/coinxt.map keeps every one of these names out of the shipped surface.
vendor_src="$ven/sha3.c $ven/sha2.c $ven/ripemd160.c $ven/hmac.c $ven/pbkdf2.c $ven/memzero.c \
$ven/ecdsa.c $ven/bignum.c $ven/secp256k1.c $ven/rfc6979.c $ven/hmac_drbg.c $ven/hasher.c \
$ven/blake256.c $ven/blake2b.c $ven/groestl.c $ven/base58.c $ven/address.c \
$ven/bip39_english.c"

# The SECOND vendored library (ABI 6): upstream bitcoin-core/secp256k1, which
# supplies BIP-340 Schnorr and the BIP-341 Taproot tweak. Three translation
# units, and that is the whole of it - libsecp256k1 is written as ONE compiled
# unit (src/secp256k1.c #includes every *_impl.h and, under the two module
# defines below, the schnorrsig and extrakeys module bodies), plus two files
# that are nothing but generated constant tables.
#
#   src/secp256k1.c              the library
#   src/precomputed_ecmult.c     odd multiples of G and of 2^128*G, for
#                                verification (see ECMULT_WINDOW_SIZE below)
#   src/precomputed_ecmult_gen.c the signed-digit comb table for k*G, 22 kB at
#                                upstream's default (11, 6) comb configuration,
#                                which is left alone: unlike the file above,
#                                this one is generated FOR one configuration
#                                and carries no #if ladder, so changing
#                                COMB_BLOCKS/COMB_TEETH would require
#                                regenerating it - i.e. a locally generated
#                                vendored file, which the vendor rules forbid.
secp_src="$ven/libsecp256k1/src/secp256k1.c $ven/libsecp256k1/src/precomputed_ecmult.c \
$ven/libsecp256k1/src/precomputed_ecmult_gen.c"

# The compile-time configuration upstream expects an integrator to supply. It
# is CONFIGURATION, not a patch: every one of these is a documented knob that
# upstream's own configure.ac / CMakeLists.txt sets, and no vendored file is
# edited.
#
#   ENABLE_MODULE_SCHNORRSIG / ENABLE_MODULE_EXTRAKEYS
#       compile in the two modules BIP-340 and BIP-341 need, and NOTHING else:
#       ecdh, recovery, musig, ellswift and silentpayments stay out (CoinXT
#       already has ECDH and recovery from trezor-crypto, and the rest is
#       surface we would ship, license and never call).
#
#   ECMULT_WINDOW_SIZE=12
#       the size of the precomputed table used for VERIFICATION, and the one
#       real tradeoff in this vendoring. Upstream's default is 15, which is
#       tuned for a node verifying blocks; the table is 2^(w-2) * 64 * 2 bytes,
#       so 15 costs 1,048,576 bytes of read-only data IN EVERY SHIPPED BINARY,
#       and this member commits four of them. Measured here (gcc 13.3 -O2,
#       x86_64, min of 7 runs of 20,000 BIP-340 verifications):
#           w=15  33.26 us/verify   1,048,576 B table
#           w=12  33.40 us/verify     131,072 B table
#           w=10  35.02 us/verify      32,768 B table
#           w= 8  35.33 us/verify       8,192 B table
#           w= 6  37.64 us/verify       2,048 B table
#       12 removes 87.5% of the table for 0.4% - inside the run-to-run spread,
#       i.e. no measurable verification cost at all. Going further does cost
#       measurable time (5% at w=10) to save 96 kB, which is not a trade worth
#       making after the free part has been taken. The absolute numbers are
#       this machine's; the RANKING is what transfers.
#       precomputed_ecmult.c is a #if ladder over w, so any value in [2..15]
#       compiles from the SAME vendored file - no regeneration, no local
#       patch. Raising it above 15 would need a regenerated table and is
#       refused by upstream's own #error.
#
#   SECP256K1_NO_API_VISIBILITY_ATTRIBUTES
#       makes SECP256K1_API a bare `extern` instead of a visibility or
#       __declspec attribute. Upstream documents this exact define for "a
#       static library which is linked into a shared library, and the latter
#       should not re-export the libsecp256k1 API". Without it a MinGW build
#       would put __declspec(dllexport) on every secp256k1_* entry point and
#       __declspec(dllimport) on the copies our shim sees. See native/coinxt.c.
secp_cppflags="-DENABLE_MODULE_SCHNORRSIG -DENABLE_MODULE_EXTRAKEYS \
-DECMULT_WINDOW_SIZE=12 -DSECP256K1_NO_API_VISIBILITY_ATTRIBUTES"

# Upstream's own warning set, minus what it itself disables. libsecp256k1
# compiles its whole library as one unit and leaves entry points for modules
# that are not enabled unused, so -Wunused-function fires ~15 times on a
# perfectly good build; upstream's configure.ac and CMakeLists.txt both append
# -Wno-unused-function for exactly this reason. It is scoped to UPSTREAM'S
# translation units only - the shim keeps the full -Wall -Wextra - which is why
# the build compiles the two groups separately instead of in one command.
secp_warn="-Wno-unused-function"

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

# Compile upstream libsecp256k1's translation units into the directory named by
# $1, using the compiler word(s) in $2 and any extra flags after that, and echo
# the resulting object list.
#
# TWO REASONS this exists instead of one big cc line:
#   1. WARNINGS. secp_warn must reach upstream's units and must NOT reach ours
#      (see its definition). A single command cannot scope a flag per file.
#   2. A REAL NAME COLLISION. vendor/secp256k1.c (trezor-crypto's curve
#      parameters) and vendor/libsecp256k1/src/secp256k1.c (upstream's whole
#      library) have the SAME BASENAME. Anything deriving an object path from
#      `basename` alone silently overwrites one with the other and links a
#      library missing half its symbols, so upstream's objects carry a secp_
#      prefix here and in the pack target.
compile_secp() {
  _dir="$1"
  _cc="$2"
  shift 2
  _objs=""
  for _s in $secp_src; do
    _o="$_dir/secp_$(basename "$_s" .c).o"
    $_cc -O2 $warn $secp_warn $secp_cppflags "$@" -fPIC -c "$_s" -o "$_o"
    _objs="$_objs $_o"
  done
  echo "$_objs"
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
    stage=$(mktemp -d)
    trap 'rm -rf "$stage"' EXIT
    secp_objs=$(compile_secp "$stage" cc)
    cc -O2 $warn $secp_cppflags $inc -fPIC -shared "$here/coinxt.c" $vendor_src \
       $secp_objs -o "$out" $(platform_libs "$ext")
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
    #  3. THE SURFACE. src/coinxt.map narrows the exports to the cnx_* entry
    #     points; see that file for why shipping the vendored
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
    # Same goal on every platform: ship the cnx_* entry points and NOTHING
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
      $CC_TOOL -O2 $warn $secp_cppflags $inc -fPIC -c "$src" -o "$obj"
      objs="$objs $obj"
    done
    # Upstream libsecp256k1, with its own warning scope and a secp_ object
    # prefix - see compile_secp above for both reasons.
    objs="$objs $(compile_secp "$stage" "$CC_TOOL")"

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
extern int cnx_seckey_tweak_add(const unsigned char *, size_t, const unsigned char *, size_t,
                                unsigned char *, size_t);
extern int cnx_pubkey_tweak_add(const unsigned char *, size_t, const unsigned char *, size_t,
                                unsigned char *, size_t);
extern int cnx_bip39_wordlist(unsigned char *, size_t);
extern size_t cnx_bip39_wordlist_len(void);
extern int cnx_memzero(unsigned char *, size_t);
/* ABI 6: BIP-340 Schnorr and the BIP-341 Taproot tweak (upstream libsecp256k1). */
extern int cnx_schnorr_sign(const unsigned char *, size_t, const unsigned char *, size_t,
                            const unsigned char *, size_t, unsigned char *, size_t);
extern int cnx_schnorr_verify(const unsigned char *, size_t, const unsigned char *, size_t,
                              const unsigned char *, size_t);
extern int cnx_xonly_pubkey_from_seckey(const unsigned char *, size_t, unsigned char *, size_t);
extern int cnx_taproot_tweak_pubkey(const unsigned char *, size_t, const unsigned char *, size_t,
                                    unsigned char *, size_t);
extern int cnx_taproot_tweak_seckey(const unsigned char *, size_t, const unsigned char *, size_t,
                                    unsigned char *, size_t);
extern size_t cnx_schnorr_sig_len(void);
extern size_t cnx_xonly_pubkey_len(void);
extern size_t cnx_taproot_output_len(void);
/* Parse a hex string into bytes; returns the byte count. The ABI-6 vectors are
 * published as hex, and re-spelling them as C initialisers by hand is exactly
 * the transcription error a vector is supposed to catch. */
static int unhex(const char *h, unsigned char *out) {
  int n = 0;
  while (h[2 * n] != 0 && h[2 * n + 1] != 0) {
    unsigned int b = 0;
    sscanf(h + 2 * n, "%2x", &b);
    out[n] = (unsigned char)b;
    n++;
  }
  return n;
}
/* Compare the first `n` bytes of a digest against its hex spelling. */
static int eqn(const unsigned char *b, int n, const char *hexexp) {
  char h[129];
  for (int i = 0; i < n; i++) sprintf(h + 2 * i, "%02x", b[i]);
  return strcmp(h, hexexp) == 0;
}
static int eq(const unsigned char *b, const char *hexexp) { return eqn(b, 32, hexexp); }
int main(void) {
  unsigned char o[64];
  if (cnx_abi_version() != 6) { printf("ABI FAIL\n"); return 1; }
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
  /* Phase 4. The wordlist is a 16 KB write into a caller buffer, which is
   * exactly the shape ASan is best at: an off-by-one in the slot loop lands
   * one byte past the block. The exact-length requirement is checked too, so
   * a caller that sized it from a stale constant is refused rather than
   * overflowed. */
  {
    static unsigned char wl[2048 * 8];
    unsigned char sk[32], tw[32], child[32], par33[33], kid33[33];
    size_t wlen = cnx_bip39_wordlist_len();
    int i;
    if (wlen != sizeof wl) { printf("wordlist len FAIL\n"); return 1; }
    if (cnx_bip39_wordlist(wl, wlen) != 0) { printf("wordlist FAIL\n"); return 1; }
    if (memcmp(wl, "abandon ", 8) != 0) { printf("wordlist[0] FAIL\n"); return 1; }
    if (memcmp(wl + 2047 * 8, "zoo     ", 8) != 0) { printf("wordlist[2047] FAIL\n"); return 1; }
    if (cnx_bip39_wordlist(wl, wlen - 1) != -2) { printf("wordlist len guard FAIL\n"); return 1; }
    /* One BIP-32 step, both halves, and they must land on the same point. */
    for (i = 0; i < 31; i++) { sk[i] = 0; tw[i] = 0; }
    sk[31] = 1;
    tw[31] = 2;
    if (cnx_seckey_tweak_add(sk, 32, tw, 32, child, 32) != 0) { printf("seckey tweak FAIL\n"); return 1; }
    if (child[31] != 3) { printf("seckey tweak value FAIL\n"); return 1; }
    if (cnx_pubkey_from_seckey(sk, 32, 1, par33, 33) != 0) { printf("tweak parent FAIL\n"); return 1; }
    if (cnx_pubkey_tweak_add(par33, 33, tw, 32, kid33, 33) != 0) { printf("pubkey tweak FAIL\n"); return 1; }
    if (cnx_pubkey_from_seckey(child, 32, 1, par33, 33) != 0) { printf("tweak child pub FAIL\n"); return 1; }
    if (memcmp(kid33, par33, 33) != 0) { printf("tweak paths disagree FAIL\n"); return 1; }
    /* The overread guard on the new entry point: 33 bytes claiming 0x04. */
    if (cnx_pubkey_from_seckey(sk, 32, 1, par33, 33) != 0) { printf("tweak parent 2 FAIL\n"); return 1; }
    par33[0] = 0x04;
    if (cnx_pubkey_tweak_add(par33, 33, tw, 32, kid33, 33) != -4) { printf("tweak overread guard FAIL\n"); return 1; }
    for (i = 0; i < 32; i++) tw[i] = 0;
    if (cnx_seckey_tweak_add(sk, 32, tw, 32, child, 32) != -4) { printf("zero tweak guard FAIL\n"); return 1; }
  }
  /* ABI 5: cnx_memzero, the wipe the .lcb runs on every out-buffer before it
   * frees it. The bounds are what matter here: it must wipe EXACTLY len bytes
   * (a one-past write - the classic off-by-one - lands on the 0xAA sentinel at
   * wz[32] and is reported by name; anything further is ASan's), tolerate a
   * zero length as a no-op, tolerate NULL+0 per the shim's firewall
   * convention, and refuse NULL with a nonzero length rather than crash. */
  {
    unsigned char wz[33];
    int i;
    for (i = 0; i < 33; i++) wz[i] = 0xAA;
    if (cnx_memzero(wz, 32) != 0) { printf("memzero rc FAIL\n"); return 1; }
    for (i = 0; i < 32; i++) {
      if (wz[i] != 0) { printf("memzero did not wipe byte %d FAIL\n", i); return 1; }
    }
    if (wz[32] != 0xAA) { printf("memzero wiped past len FAIL\n"); return 1; }
    wz[0] = 0x55;
    if (cnx_memzero(wz, 0) != 0) { printf("memzero len-0 rc FAIL\n"); return 1; }
    if (wz[0] != 0x55) { printf("memzero len-0 wrote FAIL\n"); return 1; }
    if (cnx_memzero(NULL, 0) != 0) { printf("memzero NULL+0 FAIL\n"); return 1; }
    if (cnx_memzero(NULL, 5) != -1) { printf("memzero NULL+len guard FAIL\n"); return 1; }
  }
  /* ---- ABI 6: BIP-340 Schnorr and the BIP-341 Taproot tweak ---------------
   * The exhaustive vector run lives in tools/coin-kat.py (all 19 published
   * BIP-340 cases including the 10 negatives, and all 14 BIP-341 wallet
   * cases). What THIS lane adds is the same code under ASan + UBSan, because
   * the new surface is where the fixed-size stack buffers are: a 64-byte
   * tagged-hash message that is 32 or 64 bytes long depending on the merkle
   * root, a 32-byte aux staging buffer, and a 33-byte output record whose last
   * byte is written separately from the 32 the library serializes. Each of
   * those is one off-by-one away from a report here. */
  {
    unsigned char sk[32], msg[32], aux[32], sig[64], sig2[64], xo[32], want[64];
    unsigned char ipub[32], tout[33], tout0[33], tsk[32], zeros[32];
    int i;
    if (cnx_schnorr_sig_len() != 64 || cnx_xonly_pubkey_len() != 32 ||
        cnx_taproot_output_len() != 33) { printf("abi6 len FAIL\n"); return 1; }
    /* BIP-340 test vector index 0: sk = 3, msg = 0^32, aux = 0^32. */
    for (i = 0; i < 32; i++) { sk[i] = 0; msg[i] = 0; aux[i] = 0; zeros[i] = 0; }
    sk[31] = 3;
    if (cnx_xonly_pubkey_from_seckey(sk, 32, xo, 32) != 0) { printf("xonly FAIL\n"); return 1; }
    if (!eq(xo, "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9")) {
      printf("xonly value FAIL\n"); return 1;
    }
    if (cnx_schnorr_sign(sk, 32, msg, 32, aux, 32, sig, 64) != 0) { printf("schnorr sign FAIL\n"); return 1; }
    unhex("e907831f80848d1069a5371b402410364bdf1c5f8307b0084c55f1ce2dca8215"
          "25f66a4a85ea8b71e482a74f382d2ce5ebeee8fdb2172f477df4900d310536c0", want);
    if (memcmp(sig, want, 64) != 0) { printf("schnorr vector 0 FAIL\n"); return 1; }
    if (cnx_schnorr_verify(xo, 32, msg, 32, sig, 64) != 0) { printf("schnorr verify FAIL\n"); return 1; }
    sig[7] ^= 0x01;
    if (cnx_schnorr_verify(xo, 32, msg, 32, sig, 64) != -5) { printf("schnorr tamper FAIL\n"); return 1; }
    sig[7] ^= 0x01;
    /* BIP-340 index 5: a public key that is not on the curve must be FALSE
     * (-5), not an error - the vector file says so, and a throwing verifier
     * would be unusable on a third party's signature. */
    {
      unsigned char offcurve[32];
      unhex("eefdea4cdb677750a420fee807eacf21eb9898ae79b9768766e4faa04a2d4a34", offcurve);
      if (cnx_schnorr_verify(offcurve, 32, msg, 32, sig, 64) != -5) {
        printf("schnorr off-curve-key FAIL\n"); return 1;
      }
    }
    /* Message length: signing is 32 bytes ONLY (rule 3), verification is any
     * length (BIP-340 admits it and the published vectors use 0/1/17/100). */
    if (cnx_schnorr_sign(sk, 32, msg, 31, aux, 32, sig2, 64) != -2) { printf("sign msglen guard FAIL\n"); return 1; }
    if (cnx_schnorr_verify(xo, 32, NULL, 0, sig, 64) != -5) { printf("verify empty-msg FAIL\n"); return 1; }
    if (cnx_schnorr_verify(xo, 32, NULL, 1, sig, 64) != -1) { printf("verify null-msg guard FAIL\n"); return 1; }
    /* An ABSENT aux (length 0) means "draw fresh OS entropy", never all-zero:
     * two signatures over the same key and message must DIFFER, and both must
     * verify. This is the one non-deterministic entry point in the shim. */
    if (cnx_schnorr_sign(sk, 32, msg, 32, NULL, 0, sig, 64) != 0) { printf("sign no-aux FAIL\n"); return 1; }
    if (cnx_schnorr_sign(sk, 32, msg, 32, NULL, 0, sig2, 64) != 0) { printf("sign no-aux 2 FAIL\n"); return 1; }
    if (memcmp(sig, sig2, 64) == 0) { printf("no-aux signatures identical FAIL\n"); return 1; }
    if (memcmp(sig, want, 64) == 0) { printf("no-aux aliased the zero aux FAIL\n"); return 1; }
    if (cnx_schnorr_verify(xo, 32, msg, 32, sig, 64) != 0 ||
        cnx_schnorr_verify(xo, 32, msg, 32, sig2, 64) != 0) { printf("no-aux verify FAIL\n"); return 1; }
    if (cnx_schnorr_sign(sk, 32, msg, 32, aux, 31, sig2, 64) != -2) { printf("aux len guard FAIL\n"); return 1; }
    /* BIP-341 scriptPubKey vector 0: a key-path-only output (NO merkle root). */
    unhex("d6889cb081036e0faefa3a35157ad71086b123b2b144b649798b494c300a961d", ipub);
    if (cnx_taproot_tweak_pubkey(ipub, 32, NULL, 0, tout, 33) != 0) { printf("taproot tweak FAIL\n"); return 1; }
    if (!eq(tout, "53a1f6e454df1aa2776a2814a721372d6258050de330b3c6d10ee8f4e0dda343")) {
      printf("taproot output key FAIL\n"); return 1;
    }
    if (tout[32] != 1) { printf("taproot parity FAIL\n"); return 1; }
    /* THE CONSENSUS DISTINCTION, asserted rather than assumed: an ABSENT
     * merkle root is the empty byte string, NOT 32 zero bytes. The two hash
     * different lengths and must produce different output keys; if these ever
     * agreed, one of the two spends would be to an address nobody can sweep. */
    if (cnx_taproot_tweak_pubkey(ipub, 32, zeros, 32, tout0, 33) != 0) { printf("taproot zero-root FAIL\n"); return 1; }
    if (memcmp(tout, tout0, 32) == 0) { printf("absent root aliased a zero root FAIL\n"); return 1; }
    /* BIP-341 keyPathSpending input 0: the private half of the same output. */
    {
      unsigned char isk[32], twant[32];
      unhex("6b973d88838f27366ed61c9ad6367663045cb456e28335c109e30717ae0c6baa", isk);
      unhex("2405b971772ad26915c8dcdf10f238753a9b837e5f8e6a86fd7c0cce5b7296d9", twant);
      if (cnx_xonly_pubkey_from_seckey(isk, 32, xo, 32) != 0 || memcmp(xo, ipub, 32) != 0) {
        printf("taproot internal pubkey FAIL\n"); return 1;
      }
      if (cnx_taproot_tweak_seckey(isk, 32, NULL, 0, tsk, 32) != 0) { printf("taproot tweak seckey FAIL\n"); return 1; }
      if (memcmp(tsk, twant, 32) != 0) { printf("taproot tweaked seckey value FAIL\n"); return 1; }
      /* Close the loop: the tweaked PRIVATE key must sign for the output key
       * the PUBLIC path derived from the internal key alone. */
      if (cnx_schnorr_sign(tsk, 32, msg, 32, aux, 32, sig, 64) != 0) { printf("taproot sign FAIL\n"); return 1; }
      if (cnx_schnorr_verify(tout, 32, msg, 32, sig, 64) != 0) { printf("taproot key-path spend FAIL\n"); return 1; }
    }
    /* Fail-closed guards on the new surface. */
    if (cnx_schnorr_sign(NULL, 32, msg, 32, aux, 32, sig, 64) != -1) { printf("sign null-key guard FAIL\n"); return 1; }
    if (cnx_schnorr_sign(sk, 32, msg, 32, aux, 32, sig, 63) != -2) { printf("sign siglen guard FAIL\n"); return 1; }
    if (cnx_xonly_pubkey_from_seckey(sk, 32, xo, 31) != -2) { printf("xonly outlen guard FAIL\n"); return 1; }
    if (cnx_taproot_tweak_pubkey(ipub, 32, NULL, 0, tout, 32) != -2) { printf("taproot outlen guard FAIL\n"); return 1; }
    if (cnx_taproot_tweak_pubkey(ipub, 32, zeros, 5, tout, 33) != -2) { printf("taproot rootlen guard FAIL\n"); return 1; }
    if (cnx_taproot_tweak_pubkey(ipub, 32, NULL, 32, tout, 33) != -1) { printf("taproot null-root guard FAIL\n"); return 1; }
    if (cnx_taproot_tweak_seckey(sk, 32, zeros, 5, tsk, 32) != -2) { printf("tweak-seckey rootlen guard FAIL\n"); return 1; }
    for (i = 0; i < 32; i++) sk[i] = 0;
    if (cnx_schnorr_sign(sk, 32, msg, 32, aux, 32, sig, 64) != -4) { printf("sign zero-key guard FAIL\n"); return 1; }
    if (cnx_xonly_pubkey_from_seckey(sk, 32, xo, 32) != -4) { printf("xonly zero-key guard FAIL\n"); return 1; }
    if (cnx_taproot_tweak_seckey(sk, 32, NULL, 0, tsk, 32) != -4) { printf("tweak-seckey zero-key guard FAIL\n"); return 1; }
    /* An x-only value that is not on the curve is a KEY error here, unlike in
     * verification: the caller is asserting "this is my internal key", not
     * asking a yes/no question about somebody's signature. */
    {
      unsigned char offcurve[32];
      unhex("eefdea4cdb677750a420fee807eacf21eb9898ae79b9768766e4faa04a2d4a34", offcurve);
      if (cnx_taproot_tweak_pubkey(offcurve, 32, NULL, 0, tout, 33) != -4) {
        printf("taproot off-curve internal key guard FAIL\n"); return 1;
      }
    }
  }
  printf("cnx_selftest: OK (ASan/UBSan clean, hashes + secp256k1 + BIP-32/39 + memzero"
         " + BIP-340/341)\n");
  return 0;
}
EOF
    # Upstream's units are instrumented too: the point of this lane is that the
    # NEW code runs under ASan + UBSan, and half of it is upstream's.
    secp_objs=$(compile_secp "$tmp" cc -fsanitize=address,undefined)
    cc $warn $secp_cppflags -fsanitize=address,undefined $inc "$tmp/selftest.c" \
       "$here/coinxt.c" $vendor_src $secp_objs -o "$tmp/cnx_selftest"
    "$tmp/cnx_selftest"
    rm -rf "$tmp"
    ;;
  *)
    echo "usage: sh build.sh [lib|asan|pack]" >&2
    exit 2
    ;;
esac
