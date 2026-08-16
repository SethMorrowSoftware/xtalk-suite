/* coinxt.c - the CoinXT C shim (cnx_ ABI) over vendored trezor-crypto.
 *
 * CoinXT wraps trezor-crypto (MIT) behind a thin, stable C ABI so an OXT / xTalk
 * app can reach Bitcoin/Ethereum crypto through one LCB foreign module. This file
 * is the ENTIRE native surface (SPEC.md section 5.1): every export is buffer-in /
 * buffer-out, returns an int status, and is deterministic. No I/O, no global
 * state, no ambient RNG (RFC 6979 signing needs none; fresh key material is the
 * caller's, per SPEC.md section 4).
 *
 * Phase 1: the hash surface + the ABI guard + the length functions.
 * Phase 2: the secp256k1 curve surface (keys, ECDSA, recoverable ECDSA,
 * recovery, ECDH). HD (BIP-32) and mnemonic (BIP-39) land in later phases; the
 * ABI contract they all follow was fixed in phase 1 and is unchanged.
 * ABI 6: BIP-340 Schnorr and the BIP-341 Taproot tweak, over a SECOND vendored
 * library - upstream bitcoin-core/secp256k1. That is a change to the rule this
 * file opened with ("wrap trezor-crypto, add no cryptography"), made
 * deliberately and recorded in CLAUDE.md and SPEC.md section 2: trezor-crypto's
 * plain-C tree has no BIP-340 implementation, and hand-rolling a signature
 * scheme is precisely what the rule exists to prevent. See "TWO VENDORED
 * LIBRARIES" below for which library owns which operation.
 *
 * ABI rules (CLAUDE.md, carried family FFI law):
 *  - byte buffers cross as Pointer + length; sizes are size_t;
 *  - every function returns int (0 ok, negative error);
 *  - never return a bridged/owned C string;
 *  - every length is a function, never a hardcoded LCB constant;
 *  - cnx_abi_version() gates a stale binary via the .lcb cxCheckABI().
 */

#include <limits.h>
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h> /* abort(), for the entropy failure path below */
#include <string.h> /* memcpy(), for the two fixed-size tweak/aux staging
                    * buffers in the ABI 6 section. Secrets are wiped with
                    * vendored memzero(), never with memset. */

#include "bip39.h"     /* vendored trezor-crypto: BIP39_WORD_COUNT and the
                        * BIP39_WORDLIST_ENGLISH table (defined in
                        * vendor/bip39_english.c). NOTE: bip39.c is deliberately
                        * NOT vendored - see cnx_bip39_wordlist below.           */
#include "ecdsa.h"     /* vendored trezor-crypto: the curve surface              */
#include "hmac.h"      /* vendored trezor-crypto: hmac_sha256 / hmac_sha512      */
#include "memzero.h"   /* vendored trezor-crypto: best-effort secret wiping      */
#include "pbkdf2.h"    /* vendored trezor-crypto: pbkdf2_hmac_sha512             */
#include "rand.h"      /* vendored trezor-crypto: DECLARES random_buffer; we
                        * DEFINE it below - it is the integrator's hook          */
#include "ripemd160.h" /* vendored trezor-crypto: ripemd160 (one-shot)           */
#include "secp256k1.h" /* vendored trezor-crypto: the secp256k1 curve constants  */
#include "sha2.h"      /* vendored trezor-crypto: sha256_Raw / sha512_Raw        */
#include "sha3.h"      /* vendored trezor-crypto: keccak_256 / sha3_256 (one-shot) */

/* The SECOND vendored library (ABI 6): upstream bitcoin-core/secp256k1, for
 * BIP-340 Schnorr and the BIP-341 Taproot tweak. Included by an explicit
 * subdirectory path rather than by bare name because vendor/ already holds a
 * DIFFERENT secp256k1.h - trezor-crypto's curve-parameter header, included
 * above - and -isystem vendor/ puts both on the search path. The two never
 * collide as identifiers (trezor exports a `secp256k1` struct, upstream a
 * `secp256k1_*` namespace), but the include lines would, so neither is left to
 * search order.
 *
 * SECP256K1_NO_API_VISIBILITY_ATTRIBUTES is set by the build for every
 * translation unit, ours and upstream's. It makes SECP256K1_API a bare
 * `extern`, which is what upstream documents for "a static library which is
 * linked into a shared library, and the latter should not re-export the
 * libsecp256k1 API" - exactly our case. Without it, MinGW would decorate these
 * declarations with __declspec(dllimport) here and __declspec(dllexport) in
 * upstream's own translation unit, and the shipped DLL would advertise (and
 * try to import) a libsecp256k1 surface that is nobody's business but ours.
 * The cnx_* surface stays the only export either way - src/coinxt.map on ELF,
 * a generated .def on PE - but this settles it one layer earlier.           */
#include "libsecp256k1/include/secp256k1.h"
#include "libsecp256k1/include/secp256k1_extrakeys.h"
#include "libsecp256k1/include/secp256k1_schnorrsig.h"

/* The OS entropy backend for random_buffer(). See the entropy section below for
 * why a curve library that signs deterministically still needs one. Choosing
 * this per platform at COMPILE time is deliberate: an unknown platform must be
 * a build failure and a decision, never a silent fallback to something weak. */
#if defined(_WIN32)
#include <windows.h>
/* bcrypt.h must follow windows.h; BCryptGenRandom needs -lbcrypt (build.sh). */
#include <bcrypt.h>
#elif defined(__linux__)
#include <errno.h>
#include <sys/random.h> /* getrandom(2); glibc 2.25+, our documented floor */
#elif defined(__APPLE__) || defined(__FreeBSD__) || defined(__OpenBSD__) || \
    defined(__NetBSD__) || defined(__DragonFly__)
#include <stdlib.h> /* arc4random_buf: cannot fail, by contract */
#else
#error "CoinXT: no OS entropy source known for this platform. Add one here; \
do not fall back to anything weaker (see the entropy section in coinxt.c)."
#endif

/* ---- ABI version + status codes (stable; never renumber a shipped code) ---- */

/* 3: phase 2 added the secp256k1 curve surface. 4: the two BIP-32 curve steps
 * and the BIP-39 wordlist. 5: cnx_memzero, the secret-hygiene export the .lcb
 * header had recorded as future work (it lets the binding wipe its raw
 * out-buffers before freeing them). 6: BIP-340 Schnorr and the BIP-341 Taproot
 * tweak, over the newly vendored upstream libsecp256k1. Additive every time -
 * each bump kept every prior symbol's name and signature - but the rule is to
 * bump on ANY ABI change so cxCheckABI() can refuse a stale binary rather than
 * fail at the first missing bind. */
#define CNX_ABI_VERSION 6

#define CNX_OK 0
#define CNX_ERR_NULL (-1)   /* a required buffer pointer was NULL */
#define CNX_ERR_BADLEN (-2) /* a fixed-size buffer had the wrong length (LCB layer checks) */
#define CNX_ERR_RANGE (-3)  /* a length or count the underlying primitive cannot represent */
/* Phase 2 additions. A shipped code is never renumbered (the .lcb maps each to
 * a message), so these only ever grow at the end. */
#define CNX_ERR_BADKEY (-4)    /* a private or public key upstream rejects */
#define CNX_ERR_BADSIG (-5)    /* a signature that is malformed or does not verify */
#define CNX_ERR_ENTROPY (-6)   /* the OS entropy source is unavailable (see below) */
#define CNX_ERR_BADDIGEST (-7) /* an all-zero digest: forgeable, so refused */
#define CNX_ERR_INTERNAL (-8)  /* upstream failed in a way that maps to nothing above */

int cnx_abi_version(void) { return CNX_ABI_VERSION; }

/* ---- length constants exposed as functions (never hardcode a size in LCB) --- */

size_t cnx_keccak256_len(void) { return 32; }
size_t cnx_sha3_256_len(void) { return 32; }
size_t cnx_sha256_len(void) { return 32; }
size_t cnx_sha512_len(void) { return 64; }
size_t cnx_ripemd160_len(void) { return 20; }
size_t cnx_hmac_sha256_len(void) { return 32; }
size_t cnx_hmac_sha512_len(void) { return 64; }

/* ---- boundary guards --------------------------------------------------------
 * OUR ABI carries every length as size_t, but the vendored primitives do not:
 * hmac_sha256 / hmac_sha512 take uint32_t lengths and pbkdf2_hmac_sha512 takes
 * int ones. On a 64-bit build a size_t larger than those can hold would be
 * TRUNCATED by the implicit conversion, and the primitive would silently hash a
 * different (shorter) message than the caller asked about - a wrong answer, not
 * a crash, which is the worst kind of bug in a money library. So the shim
 * refuses anything the callee cannot represent instead of narrowing it.
 *
 * The u32 test is compiled out where size_t is already 32-bit: there the
 * comparison is tautologically true and -Wextra (-Wtype-limits) would rightly
 * complain about it. */
static int cnx_fits_u32(size_t n) {
#if SIZE_MAX > UINT32_MAX
  return n <= (size_t)UINT32_MAX;
#else
  (void)n;
  return 1;
#endif
}

static int cnx_fits_int(size_t n) { return n <= (size_t)INT_MAX; }

/* ---- hashes -----------------------------------------------------------------
 * Ethereum's "SHA3" is Keccak-256 (original 0x01 padding); NIST SHA3-256 uses
 * 0x06. They are DIFFERENT functions and must never be aliased (the classic
 * Ethereum footgun). trezor-crypto exposes both one-shot; we surface both.
 * out32 is a caller-allocated 32-byte buffer. An empty input is valid (in may be
 * NULL only when inlen == 0; we substitute a valid pointer so no hash internal
 * ever dereferences NULL). */

static const unsigned char cnx_empty[1] = {0};

int cnx_keccak256(const unsigned char *in, size_t inlen, unsigned char *out32) {
  if (out32 == NULL) return CNX_ERR_NULL;
  if (in == NULL) {
    if (inlen != 0) return CNX_ERR_NULL;
    in = cnx_empty;
  }
  keccak_256(in, inlen, out32);
  return CNX_OK;
}

int cnx_sha3_256(const unsigned char *in, size_t inlen, unsigned char *out32) {
  if (out32 == NULL) return CNX_ERR_NULL;
  if (in == NULL) {
    if (inlen != 0) return CNX_ERR_NULL;
    in = cnx_empty;
  }
  sha3_256(in, inlen, out32);
  return CNX_OK;
}

/* SHA-2 and RIPEMD-160. Bitcoin's addresses are RIPEMD160(SHA256(pubkey)) and
 * its checksums are SHA256(SHA256(x)), so both live here; SHA-512 is what
 * BIP-32 / BIP-39 derive with. Same empty-input contract as above. */

int cnx_sha256(const unsigned char *in, size_t inlen, unsigned char *out32) {
  if (out32 == NULL) return CNX_ERR_NULL;
  if (in == NULL) {
    if (inlen != 0) return CNX_ERR_NULL;
    in = cnx_empty;
  }
  sha256_Raw(in, inlen, out32);
  return CNX_OK;
}

int cnx_sha512(const unsigned char *in, size_t inlen, unsigned char *out64) {
  if (out64 == NULL) return CNX_ERR_NULL;
  if (in == NULL) {
    if (inlen != 0) return CNX_ERR_NULL;
    in = cnx_empty;
  }
  sha512_Raw(in, inlen, out64);
  return CNX_OK;
}

int cnx_ripemd160(const unsigned char *in, size_t inlen, unsigned char *out20) {
  if (out20 == NULL) return CNX_ERR_NULL;
  if (in == NULL) {
    if (inlen != 0) return CNX_ERR_NULL;
    in = cnx_empty;
  }
  ripemd160(in, inlen, out20);
  return CNX_OK;
}

/* ---- HMAC -------------------------------------------------------------------
 * A keyed MAC over an arbitrary-length key and message (RFC 2104): both may be
 * empty, and a key longer than the block size is hashed down by the primitive,
 * so there is no key-length restriction to enforce here - only the uint32_t
 * ceiling the vendored signature imposes (see cnx_fits_u32). */

int cnx_hmac_sha256(const unsigned char *key, size_t klen, const unsigned char *msg,
                    size_t mlen, unsigned char *out32) {
  if (out32 == NULL) return CNX_ERR_NULL;
  if (key == NULL) {
    if (klen != 0) return CNX_ERR_NULL;
    key = cnx_empty;
  }
  if (msg == NULL) {
    if (mlen != 0) return CNX_ERR_NULL;
    msg = cnx_empty;
  }
  if (!cnx_fits_u32(klen) || !cnx_fits_u32(mlen)) return CNX_ERR_RANGE;
  hmac_sha256(key, (uint32_t)klen, msg, (uint32_t)mlen, out32);
  return CNX_OK;
}

int cnx_hmac_sha512(const unsigned char *key, size_t klen, const unsigned char *msg,
                    size_t mlen, unsigned char *out64) {
  if (out64 == NULL) return CNX_ERR_NULL;
  if (key == NULL) {
    if (klen != 0) return CNX_ERR_NULL;
    key = cnx_empty;
  }
  if (msg == NULL) {
    if (mlen != 0) return CNX_ERR_NULL;
    msg = cnx_empty;
  }
  if (!cnx_fits_u32(klen) || !cnx_fits_u32(mlen)) return CNX_ERR_RANGE;
  hmac_sha512(key, (uint32_t)klen, msg, (uint32_t)mlen, out64);
  return CNX_OK;
}

/* ---- PBKDF2-HMAC-SHA512 -----------------------------------------------------
 * The BIP-39 mnemonic-to-seed KDF (2048 iterations, salt "mnemonic" + passphrase).
 * An empty password and an empty salt are both legal per RFC 2898.
 *
 * Two refusals that matter, because the primitive would otherwise be QUIETLY
 * wrong rather than loud:
 *  - iterations == 0. Upstream's loop is `for (i = first; i < iterations; i++)`
 *    seeded at first == 1, so a zero count silently yields the ONE-iteration
 *    result: a far weaker key than the caller asked for, with no error. RFC 2898
 *    requires c >= 1, so we fail closed (family rule 4) instead.
 *  - outlen == 0. blocks_count would be 0, the loop would not run, and the call
 *    would return "success" having written nothing into the caller's buffer. */

int cnx_pbkdf2_hmac_sha512(const unsigned char *pw, size_t plen, const unsigned char *salt,
                           size_t slen, uint32_t iterations, unsigned char *out,
                           size_t outlen) {
  if (out == NULL) return CNX_ERR_NULL;
  if (pw == NULL) {
    if (plen != 0) return CNX_ERR_NULL;
    pw = cnx_empty;
  }
  if (salt == NULL) {
    if (slen != 0) return CNX_ERR_NULL;
    salt = cnx_empty;
  }
  if (outlen == 0) return CNX_ERR_BADLEN;
  if (iterations == 0) return CNX_ERR_RANGE;
  if (!cnx_fits_int(plen) || !cnx_fits_int(slen) || !cnx_fits_int(outlen))
    return CNX_ERR_RANGE;
  pbkdf2_hmac_sha512(pw, (int)plen, salt, (int)slen, iterations, out, (int)outlen);
  return CNX_OK;
}

/* ---- secret hygiene: the wipe the binding layer needs (ABI 5) ---------------
 * src/coinxt.lcb allocates every out-buffer as a raw engine block
 * (MCMemoryAllocate) and, until this export existed, freed it UNWIPED: there
 * is no engine <builtin> the binding can name that zeroes a block, and that
 * file refuses to invent one. Its header recorded the fix - "a future
 * cnx_memzero(ptr, len) export ... a shim change and therefore an ABI bump,
 * so it is noted here, not smuggled in" - and this is that change, made with
 * the bump. The binding now wipes every out-buffer through this before
 * MCMemoryDeallocate, so a freed block never re-enters the allocator still
 * holding a seed, a child private key, a chaincode half or an ECDH point.
 *
 * The wipe itself is vendor/memzero.c's, the routine every other secret in
 * this shim already goes through: SecureZeroMemory / memset_s /
 * explicit_bzero / a volatile-pointer byte loop, chosen per platform at
 * compile time, none of which the compiler may elide the way it can a plain
 * memset before free. No wiping technique is invented here (rule 1: wrap).
 *
 * The NULL contract mirrors the in-buffer convention above: NULL with len 0
 * is a tolerated no-op (an empty buffer has nothing to wipe), NULL with a
 * nonzero length is a caller bug and is refused rather than dereferenced,
 * and len 0 with a valid pointer succeeds having done nothing. */
int cnx_memzero(unsigned char *buf, size_t len) {
  if (buf == NULL) return len == 0 ? CNX_OK : CNX_ERR_NULL;
  memzero(buf, len);
  return CNX_OK;
}

/* ---- entropy: the integrator hook, and a corrected design decision ----------
 *
 * READ THIS BEFORE "SIMPLIFYING" IT. The phase-0 plan (IMPLEMENTATION-PLAN.md)
 * and CLAUDE.md both said: wire trezor-crypto's random_buffer/random32 to
 * ABORT, on the reasoning that "nothing should call it once signing is RFC 6979
 * and keys come from the caller, so a called RNG is a loud bug rather than a
 * silent weak key." That reasoning is WRONG, and phase 2 is where it surfaces.
 *
 * The RNG is on the hot path of every curve operation, by design and for a good
 * reason. In vendor/ecdsa.c:
 *
 *   - curve_to_jacobian() calls generate_k_random() to randomize the projective
 *     Z coordinate on EVERY scalar multiply. That is a side-channel (DPA)
 *     countermeasure: the same scalar takes a different internal representation
 *     each time.
 *   - ecdsa_sign_digest() draws a second value, `randk`, and computes s as
 *     (k*randk)^-1 * (R.x*priv + z) * randk. Algebraically the randk cancels,
 *     so the SIGNATURE IS UNCHANGED - it is blinding for the inversion, not
 *     nonce generation. The nonce k itself stays RFC 6979 deterministic.
 *
 * So the two available "no RNG" answers are both bad, and neither is what the
 * plan imagined:
 *   - abort() on call: every cnx_pubkey_from_seckey / sign / verify / ecdh kills
 *     the host process on its first use. Not a loud bug; a dead application.
 *   - return constant bytes: generate_k_random() loops `while (bn_is_zero(k) ||
 *     !bn_is_less(k, prime))`, so all-zero HANGS FOREVER, and any other constant
 *     silently deletes upstream's side-channel countermeasure.
 *
 * What is actually true is narrower than "no RNG in the shim", and it is the
 * part that protects the user: NO KEY MATERIAL COMES FROM AN AMBIENT RNG. Fresh
 * private keys are still the caller's (cnx_seckey_verify validates 32 caller
 * bytes) and nonces are still RFC 6979. This entropy is used only for blinding,
 * where a bad draw costs a countermeasure and never a key, and where the output
 * is bit-for-bit identical either way - which is exactly why the KATs can pin a
 * signature at all.
 *
 * Given it must exist, it is real OS entropy and it fails CLOSED. */

/* Fill buf from the OS. Returns 1 on success, 0 on failure. */
static int cnx_entropy_fill(unsigned char *buf, size_t len) {
#if defined(_WIN32)
  /* BCRYPT_USE_SYSTEM_PREFERRED_RNG means "no algorithm handle needed"; this is
   * the documented modern replacement for CryptGenRandom. */
  return BCryptGenRandom(NULL, (PUCHAR)buf, (ULONG)len,
                         BCRYPT_USE_SYSTEM_PREFERRED_RNG) == 0;
#elif defined(__linux__)
  /* getrandom() can return a SHORT read when interrupted, so loop rather than
   * assume; EINTR before the pool is initialised is the one retryable error. */
  size_t off = 0;
  while (off < len) {
    ssize_t n = getrandom(buf + off, len - off, 0);
    if (n < 0) {
      if (errno == EINTR) continue;
      return 0;
    }
    off += (size_t)n;
  }
  return 1;
#else
  arc4random_buf(buf, len); /* contractually cannot fail */
  return 1;
#endif
}

/* Cheap pre-flight, called by every curve entry point BEFORE it hands control
 * to upstream. It exists to turn the one failure mode that a caller can act on
 * (this machine has no usable entropy source) into a clean CNX_ERR_ENTROPY that
 * the script layer can catch, instead of the abort() below. */
static int cnx_entropy_ok(void) {
  unsigned char probe[8];
  if (!cnx_entropy_fill(probe, sizeof probe)) return 0;
  memzero(probe, sizeof probe);
  return 1;
}

/* The hook trezor-crypto declares in rand.h and requires the integrator to
 * define. Its signature returns void, so there is no way to report a failure
 * upward from here: the only choices are to continue with bytes we did not get
 * (silently unblinded, or an infinite loop in generate_k_random) or to stop.
 * A money library stops. In practice this is unreachable - every caller runs
 * cnx_entropy_ok() microseconds earlier - which is precisely why it is safe to
 * make it fatal. */
void random_buffer(uint8_t *buf, size_t len) {
  if (!cnx_entropy_fill(buf, len)) {
    memzero(buf, len);
    abort();
  }
}

/* ---- curve: lengths ---------------------------------------------------------
 * Same rule as the hashes: every size the LCB layer allocates comes from here,
 * so no size is ever written down twice. */

size_t cnx_seckey_len(void) { return 32; }
size_t cnx_pubkey_len_compressed(void) { return 33; }
size_t cnx_pubkey_len_uncompressed(void) { return 65; }
size_t cnx_ecdsa_sig_len(void) { return 64; }
size_t cnx_recoverable_sig_len(void) { return 65; }
/* The RAW ECDH point (0x04 || X || Y), not a key - see cnx_ecdh. SPEC.md 5.1
 * sketched this as 32 bytes, assuming the X coordinate; the shim reports what
 * upstream actually writes rather than truncating on the caller's behalf. */
size_t cnx_ecdh_len(void) { return 65; }

/* ---- curve: shared input validation ----------------------------------------
 * Upstream's ecdsa_read_pubkey() dispatches on the PREFIX BYTE and reads 65
 * bytes whenever it sees 0x04 - it is never told how long the buffer is. So a
 * 33-byte buffer whose first byte is 0x04 (corrupt, or attacker-chosen) makes
 * it read 32 bytes PAST THE END. The length and the prefix must therefore be
 * agreed HERE, before the pointer is handed over; this is the one buffer rule
 * upstream cannot enforce for us. */
static int cnx_pubkey_ok(const unsigned char *pub, size_t publen) {
  if (pub == NULL) return 0;
  if (publen == 33) return pub[0] == 0x02 || pub[0] == 0x03;
  if (publen == 65) return pub[0] == 0x04;
  return 0;
}

/* ---- curve: keys ------------------------------------------------------------
 * A valid secp256k1 private key is an integer in [1, n-1]. Upstream checks the
 * same bound inside every operation, but a caller wants to ask the question
 * BEFORE it stores 32 bytes as a key, which is what cxNewSeckey does with fresh
 * caller entropy. bn_* is upstream's own arithmetic; no bound is restated. */

int cnx_seckey_verify(const unsigned char *sk, size_t sklen) {
  bignum256 k = {0};
  int ok = 0;
  if (sk == NULL) return CNX_ERR_NULL;
  if (sklen != 32) return CNX_ERR_BADLEN;
  bn_read_be(sk, &k);
  ok = !bn_is_zero(&k) && bn_is_less(&k, &secp256k1.order);
  memzero(&k, sizeof k); /* k IS the private key; do not leave it on the stack */
  return ok ? CNX_OK : CNX_ERR_BADKEY;
}

int cnx_pubkey_from_seckey(const unsigned char *sk, size_t sklen, int compressed,
                           unsigned char *out, size_t outlen) {
  int rc = 0;
  if (sk == NULL || out == NULL) return CNX_ERR_NULL;
  if (sklen != 32) return CNX_ERR_BADLEN;
  if (outlen != (compressed ? (size_t)33 : (size_t)65)) return CNX_ERR_BADLEN;
  if (!cnx_entropy_ok()) return CNX_ERR_ENTROPY;
  rc = compressed ? ecdsa_get_public_key33(&secp256k1, sk, out)
                  : ecdsa_get_public_key65(&secp256k1, sk, out);
  if (rc != 0) {
    /* Upstream already zeroes the output on its invalid-key path; do it here
     * too so this function's contract does not depend on that staying true. */
    memzero(out, outlen);
    return CNX_ERR_BADKEY;
  }
  return CNX_OK;
}

int cnx_pubkey_decompress(const unsigned char *pub, size_t publen,
                          unsigned char *out, size_t outlen) {
  if (out == NULL) return CNX_ERR_NULL;
  if (outlen != 65) return CNX_ERR_BADLEN;
  if (!cnx_pubkey_ok(pub, publen)) return CNX_ERR_BADKEY;
  /* NOTE THE INVERTED CONVENTION: ecdsa_uncompress_pubkey returns 1 for
   * success and 0 for failure, where ecdsa_sign_digest and friends return 0
   * for success. Upstream is not uniform; each call site says which it is. */
  if (ecdsa_uncompress_pubkey(&secp256k1, pub, out) != 1) {
    memzero(out, outlen);
    return CNX_ERR_BADKEY;
  }
  return CNX_OK;
}

/* ---- curve: ECDSA -----------------------------------------------------------
 * Sign the digest the caller hands us and nothing else (CLAUDE.md rule 3): the
 * shim never builds a sighash. The nonce is RFC 6979 (options.h USE_RFC6979=1),
 * so a signature is a pure function of (key, digest) and is KAT-pinnable.
 *
 * LOW-S IS ALREADY ENFORCED by upstream: ecdsa_sign_digest does `if (s >
 * order/2) s = order - s` unconditionally, flipping the recovery bit with it.
 * We add no canonicalization of our own and pass no is_canonical callback -
 * that argument selects EXTRA per-coin rules we do not need. */

int cnx_ecdsa_sign(const unsigned char *sk, size_t sklen, const unsigned char *digest,
                   size_t digestlen, unsigned char *sig, size_t siglen) {
  int rc = 0;
  if (sk == NULL || digest == NULL || sig == NULL) return CNX_ERR_NULL;
  if (sklen != 32 || digestlen != 32 || siglen != 64) return CNX_ERR_BADLEN;
  if (!cnx_entropy_ok()) return CNX_ERR_ENTROPY;
  rc = ecdsa_sign_digest(&secp256k1, sk, digest, sig, NULL, NULL);
  if (rc != 0) {
    memzero(sig, siglen);
    /* Upstream's codes: 1 = all-zero digest (refused because such a signature
     * is forgeable for any key), 2 = invalid private key, -1 = it could not
     * find an acceptable signature within its retry budget. */
    if (rc == 1) return CNX_ERR_BADDIGEST;
    if (rc == 2) return CNX_ERR_BADKEY;
    return CNX_ERR_INTERNAL;
  }
  return CNX_OK;
}

/* Recoverable form: the 64-byte signature followed by the 1-byte recovery id,
 * which is what Ethereum's `v` is built from. The id is upstream's `pby`, and
 * it already accounts for both the y parity and the (vanishingly rare) case
 * where R.x had to be reduced mod n, so it spans 0..3 as the standard says. */
int cnx_ecdsa_sign_recoverable(const unsigned char *sk, size_t sklen,
                               const unsigned char *digest, size_t digestlen,
                               unsigned char *sig, size_t siglen) {
  int rc = 0;
  uint8_t recid = 0;
  if (sk == NULL || digest == NULL || sig == NULL) return CNX_ERR_NULL;
  if (sklen != 32 || digestlen != 32 || siglen != 65) return CNX_ERR_BADLEN;
  if (!cnx_entropy_ok()) return CNX_ERR_ENTROPY;
  rc = ecdsa_sign_digest(&secp256k1, sk, digest, sig, &recid, NULL);
  if (rc != 0) {
    memzero(sig, siglen);
    if (rc == 1) return CNX_ERR_BADDIGEST;
    if (rc == 2) return CNX_ERR_BADKEY;
    return CNX_ERR_INTERNAL;
  }
  sig[64] = (unsigned char)recid;
  return CNX_OK;
}

/* Verification reports through the STATUS, and the split matters: a signature
 * that is well-formed but does not verify is CNX_ERR_BADSIG, while a malformed
 * public key or a wrong buffer length is its own code. The .lcb turns the first
 * into `false` and throws on the rest - a verify that throws on "invalid" is
 * unusable, and one that answers "false" to a malformed key hides a bug. */
int cnx_ecdsa_verify(const unsigned char *pub, size_t publen, const unsigned char *digest,
                     size_t digestlen, const unsigned char *sig, size_t siglen) {
  if (digest == NULL || sig == NULL) return CNX_ERR_NULL;
  if (digestlen != 32 || siglen != 64) return CNX_ERR_BADLEN;
  if (!cnx_pubkey_ok(pub, publen)) return CNX_ERR_BADKEY;
  if (!cnx_entropy_ok()) return CNX_ERR_ENTROPY;
  /* 0 means the signature is VALID here. Every non-zero code (bad pubkey, out
   * of range r/s, zero digest, wrong point) collapses to "does not verify",
   * which is the only distinction a caller can safely act on. */
  return ecdsa_verify_digest(&secp256k1, pub, sig, digest) == 0 ? CNX_OK
                                                                : CNX_ERR_BADSIG;
}

/* ecrecover: the public key that produced this signature over this digest. */
int cnx_ecdsa_recover(const unsigned char *sig, size_t siglen, const unsigned char *digest,
                      size_t digestlen, unsigned char *out, size_t outlen) {
  if (sig == NULL || digest == NULL || out == NULL) return CNX_ERR_NULL;
  if (siglen != 65 || digestlen != 32 || outlen != 65) return CNX_ERR_BADLEN;
  /* The recovery id is the caller's byte and reaches upstream as an int index
   * into two bit tests, so bound it here rather than trusting the wire. */
  if (sig[64] > 3) return CNX_ERR_BADSIG;
  if (!cnx_entropy_ok()) return CNX_ERR_ENTROPY;
  if (ecdsa_recover_pub_from_sig(&secp256k1, out, sig, digest, (int)sig[64]) != 0) {
    memzero(out, outlen);
    return CNX_ERR_BADSIG;
  }
  return CNX_OK;
}

/* ---- curve: ECDH ------------------------------------------------------------
 * The RAW shared point (0x04 || X || Y), exactly as upstream computes it. This
 * is NOT a shared key and must not be used as one: every protocol that uses
 * ECDH puts a KDF over this point (and they disagree about which, and about
 * whether it hashes X alone or the compressed form). Truncating or hashing here
 * would be CoinXT inventing a convention and calling it interoperability, so
 * the shim hands back the point and the caller composes the KDF it needs. */
int cnx_ecdh(const unsigned char *sk, size_t sklen, const unsigned char *pub,
             size_t publen, unsigned char *out, size_t outlen) {
  int rc = 0;
  if (sk == NULL || out == NULL) return CNX_ERR_NULL;
  if (sklen != 32 || outlen != 65) return CNX_ERR_BADLEN;
  if (!cnx_pubkey_ok(pub, publen)) return CNX_ERR_BADKEY;
  if (!cnx_entropy_ok()) return CNX_ERR_ENTROPY;
  rc = ecdh_multiply(&secp256k1, sk, pub, out);
  if (rc != 0) {
    memzero(out, outlen);
    return CNX_ERR_BADKEY; /* 1 = bad public key, 2 = bad private key */
  }
  return CNX_OK;
}

/* ---- BIP-32: the two curve steps derivation needs ---------------------------
 * WHY THESE TWO AND NOT hdnode_* : upstream's bip32.c would give us the whole
 * of BIP-32 for free, but it does NOT come alone. It is written against every
 * curve trezor supports, so vendoring it drags in curves.c, nist256p1,
 * ed25519-donna, curve25519 and the Cardano variants - a large closure, most of
 * it code CoinXT will never call, all of it code CoinXT would then be shipping
 * and licensing. What BIP-32 actually needs from the curve is exactly two
 * operations that the ALREADY-vendored ecdsa.c/bignum.c provide:
 *
 *   CKDpriv:  ki = (IL + kpar) mod n            -> cnx_seckey_tweak_add
 *   CKDpub:   Ki = point(IL) + Kpar             -> cnx_pubkey_tweak_add
 *
 * Everything else in BIP-32 - the HMAC-SHA512, the serialization, the path
 * parse, the hardened/normal split - is byte shuffling with no secret-dependent
 * branch, which by CLAUDE.md's C-vs-script rule belongs in script. So the shim
 * exports the two curve steps and src/coinxt.livecodescript does the rest.
 *
 * Both functions REJECT A ZERO TWEAK, which upstream's own pubkey path accepts.
 * That is deliberate and it is the safer direction: BIP-32 only declares a child
 * invalid when parse256(IL) >= n or the result is zero/infinity, so IL == 0 is
 * technically legal and yields a child key EQUAL TO ITS PARENT. It cannot arise
 * in practice (it is one HMAC-SHA512 output in 2^256), it is a corner no vector
 * exercises, and accepting it on one path while the other rejected it would make
 * private and public derivation of the same child disagree about validity -
 * which is an interoperability bug of exactly the kind this member exists to
 * avoid. A caller that somehow meets it gets an error, and BIP-32's own remedy
 * (move to the next index) is the same remedy it would have had anyway. */

/* ki = (tweak + sk) mod n. The bn_add/bn_mod/bn_is_zero sequence is upstream's
 * own, copied from hdnode_private_ckd_bip32 in trezor-crypto's bip32.c: bn_add
 * leaves a partly-reduced value, so the bn_mod is REQUIRED before bn_write_be,
 * and dropping it is how you get a silently wrong key. */
int cnx_seckey_tweak_add(const unsigned char *sk, size_t sklen,
                         const unsigned char *tweak, size_t tweaklen,
                         unsigned char *out, size_t outlen) {
  bignum256 a = {0}; /* the parent key   */
  bignum256 b = {0}; /* the tweak, then the child key */
  int rc = CNX_OK;
  if (sk == NULL || tweak == NULL || out == NULL) return CNX_ERR_NULL;
  if (sklen != 32 || tweaklen != 32 || outlen != 32) return CNX_ERR_BADLEN;
  bn_read_be(sk, &a);
  bn_read_be(tweak, &b);
  if (bn_is_zero(&a) || !bn_is_less(&a, &secp256k1.order)) {
    rc = CNX_ERR_BADKEY; /* the PARENT is not a valid private key */
  } else if (bn_is_zero(&b) || !bn_is_less(&b, &secp256k1.order)) {
    rc = CNX_ERR_BADKEY; /* IL == 0 or IL >= n: BIP-32 says try the next index */
  } else {
    bn_add(&b, &a);
    bn_mod(&b, &secp256k1.order);
    if (bn_is_zero(&b)) {
      rc = CNX_ERR_BADKEY; /* ki == 0: BIP-32 says try the next index */
    } else {
      bn_write_be(&b, out);
    }
  }
  if (rc != CNX_OK) memzero(out, outlen);
  /* a and b ARE key material; do not leave either on the stack. */
  memzero(&a, sizeof a);
  memzero(&b, sizeof b);
  return rc;
}

/* Ki = point(tweak) + Kpar, compressed. This one IS upstream's audited routine
 * (ecdsa_tweak_pubkey), which reads EXACTLY 33 bytes and dispatches on the
 * prefix byte - so the 33-byte length is agreed here first, for the same
 * overread reason cnx_pubkey_ok exists. An uncompressed parent is refused
 * rather than silently compressed: BIP-32 hashes the COMPRESSED parent key into
 * the HMAC, so a caller holding 65 bytes has already diverged from the spec and
 * should be told, not accommodated. */
int cnx_pubkey_tweak_add(const unsigned char *pub, size_t publen,
                         const unsigned char *tweak, size_t tweaklen,
                         unsigned char *out, size_t outlen) {
  bignum256 t = {0};
  int zero = 0;
  if (tweak == NULL || out == NULL) return CNX_ERR_NULL;
  if (tweaklen != 32 || outlen != 33) return CNX_ERR_BADLEN;
  if (publen != 33 || !cnx_pubkey_ok(pub, publen)) return CNX_ERR_BADKEY;
  bn_read_be(tweak, &t);
  zero = bn_is_zero(&t);
  memzero(&t, sizeof t);
  if (zero) return CNX_ERR_BADKEY; /* see the zero-tweak note above */
  if (!cnx_entropy_ok()) return CNX_ERR_ENTROPY;
  /* Every non-success code collapses to CNX_ERR_BADKEY: the caller's only
   * actionable distinction is "this child is unusable, move to the next index",
   * which is what BIP-32 tells it to do for the tweak/infinity case anyway. */
  if (ecdsa_tweak_pubkey(&secp256k1, pub, tweak, out) !=
      ECDSA_TWEAK_PUBKEY_SUCCESS) {
    memzero(out, outlen);
    return CNX_ERR_BADKEY;
  }
  return CNX_OK;
}

/* ---- BIP-39: the normative English wordlist ---------------------------------
 * The list is NORMATIVE DATA, not code: BIP-39 pins it by the SHA-256 of its
 * canonical newline-joined form, 2f5eed53...b24dbda, and every wallet in the
 * world indexes the same 2048 words in the same order. So it is vendored
 * verbatim (vendor/bip39_english.c, blob-verified against the pinned commit)
 * rather than transcribed into a script constant, where 2048 hand-copied words
 * would be 16 KB of unreviewable diff and one typo away from a wallet that
 * cannot restore its own seed. tools/coin-kat.py re-derives that SHA-256 from
 * what this function returns, so the claim is checked and not asserted.
 *
 * Upstream's bip39.c is NOT vendored with it. Its mnemonic_from_data returns a
 * `const char *` into a static buffer, which the C-ABI law in CLAUDE.md forbids
 * bridging, and its mnemonic_to_seed is PBKDF2-HMAC-SHA512, which this shim
 * already exports. What is left - 11-bit packing and a checksum - is script's
 * job.
 *
 * THE LAYOUT IS FIXED WIDTH, 8 BYTES PER SLOT, SPACE PADDED, in list order:
 *
 *   slot i  =  out[i * 8 .. i * 8 + 7]      word i, then ' ' filler
 *
 * 8 is BIP39_MAX_WORD_LEN and the longest English word is exactly 8, so nothing
 * is truncated. Fixed width is what makes the script side cheap and exact:
 * index -> word is one chunk expression, and word -> index is a binary search
 * over a sorted table rather than a 2048-step scan. A space-separated blob would
 * have forced the script to split 15 KB on every lookup. */

#define CNX_BIP39_SLOT 8

size_t cnx_bip39_wordlist_len(void) {
  return (size_t)BIP39_WORD_COUNT * (size_t)CNX_BIP39_SLOT;
}

int cnx_bip39_wordlist(unsigned char *out, size_t outlen) {
  size_t i = 0;
  if (out == NULL) return CNX_ERR_NULL;
  if (outlen != cnx_bip39_wordlist_len()) return CNX_ERR_BADLEN;
  for (i = 0; i < (size_t)BIP39_WORD_COUNT; i++) {
    const char *word = BIP39_WORDLIST_ENGLISH[i];
    unsigned char *slot = out + i * (size_t)CNX_BIP39_SLOT;
    size_t j = 0;
    while (j < (size_t)CNX_BIP39_SLOT && word[j] != '\0') {
      slot[j] = (unsigned char)word[j];
      j++;
    }
    /* If a future wordlist ever carried a word longer than the slot, the
     * fixed-width contract above would break SILENTLY and every index past it
     * would be wrong. Refuse instead. Unreachable for the pinned list, which
     * tools/coin-kat.py checks by hash. */
    if (word[j] != '\0') {
      memzero(out, outlen);
      return CNX_ERR_INTERNAL;
    }
    while (j < (size_t)CNX_BIP39_SLOT) {
      slot[j] = (unsigned char)' ';
      j++;
    }
  }
  return CNX_OK;
}

/* ==========================================================================
 * ABI 6: BIP-340 Schnorr and the BIP-341 Taproot tweak, over upstream
 * bitcoin-core/secp256k1.
 * ==========================================================================
 *
 * TWO VENDORED LIBRARIES, AND WHY. Everything above this line is
 * trezor-crypto. Everything below it is upstream libsecp256k1. That split is
 * a deliberate change to a rule this project held from phase 0 ("every curve
 * op and hash is trezor-crypto's; CoinXT adds no cipher of its own"), and it
 * is recorded as a decision in CLAUDE.md and SPEC.md section 2 rather than
 * edited quietly into the prose. The short form: trezor-crypto's plain-C tree
 * has NO BIP-340 implementation - it reaches Schnorr only through
 * zkp_bip340.c, which requires the bundled secp256k1-zkp and its own build
 * system - so the choice was between a second audited library and writing a
 * signature scheme here. Rule 1 exists to forbid the second. What did NOT
 * change is the part that matters: CoinXT still adds no cryptography of its
 * own; it now composes two upstream libraries instead of one.
 *
 * THE TWO DO NOT OVERLAP, and that is enforced by which functions exist here.
 * ECDSA, recovery, ECDH, the BIP-32 tweaks and every hash stay on
 * trezor-crypto; Schnorr, x-only keys and the Taproot tweak are upstream's and
 * are reached ONLY through the five entry points below. Nothing is
 * reimplemented against the other library, and no result crosses between them
 * except as opaque 32-byte scalars and serialized keys, which are
 * library-independent by definition. A future maintainer moving an operation
 * from one to the other is making an interoperability decision, not a
 * refactor.
 *
 * THE CONTEXT. Upstream needs a secp256k1_context. It is created ONCE, on
 * first use, and kept in a file-static pointer: creation is not free, and the
 * family's alternative - a handle through script - is exactly what CLAUDE.md
 * says not to build for a stateless library. It is never destroyed, which is
 * correct rather than sloppy: it is one small allocation reachable from a
 * global for the life of the process (so ASan's leak checker does not report
 * it), CoinXT has no shutdown call and by design never will, and freeing it
 * would create a use-after-free window for exactly zero benefit.
 *
 * THREADING. The context is created and re-randomized without a lock, which is
 * sound here for the same reason the rest of this member is: CoinXT is called
 * only from the xTalk engine's script thread (CLAUDE.md, family rule 1: never
 * call an xTalk handler from a foreign thread), and every entry point is
 * synchronous. Upstream states the rule precisely - a constructed context is
 * safe to SHARE across threads, but secp256k1_context_randomize needs
 * exclusive access - so a future multi-threaded host would need a lock around
 * cnx_secp_ready() and nothing else.
 *
 * THE DEFAULT ILLEGAL-ARGUMENT CALLBACK IS LEFT IN PLACE, deliberately.
 * Upstream's default aborts the process on an API misuse (a NULL where the
 * header says non-NULL). Installing a returning callback instead is possible
 * and looks safer, but upstream's own header says that if the callback
 * returns, "the return value and output arguments of the API function call are
 * undefined" - an undefined return in a money library is strictly worse than a
 * loud stop. So the firewall below guarantees the callback is unreachable
 * instead: every pointer upstream is handed is non-NULL and every length is
 * checked here first, which is the same contract cnx_pubkey_ok already
 * enforces for trezor-crypto's unlengthed pubkey parser. This mirrors the
 * abort() in random_buffer above, for the same reason and with the same
 * pre-flight in front of it.                                                */

/* Every length a caller allocates comes from here, never from a constant in
 * the binding (SPEC.md section 5: "every length is a function"). */
size_t cnx_schnorr_sig_len(void) { return 64; }
size_t cnx_xonly_pubkey_len(void) { return 32; }
/* The Taproot output record: 32 bytes of x-only key followed by ONE parity
 * byte (0 = even Y, 1 = odd Y). Packing the parity into the output buffer
 * rather than into an `int *` out-parameter is this member's existing
 * convention, not a new one - cnx_ecdsa_sign_recoverable writes a 65-byte
 * record that is 64 bytes of signature plus a recovery id - and it keeps the
 * binding on shapes an engine has already marshalled: no .lcb in this suite
 * has ever declared a scalar `out` parameter against our own C, and a money
 * library is the wrong place to find out headlessly whether one works. The
 * parity is what a script-path spend needs for its control byte; a key-path
 * spend and a P2TR address need only the 32 bytes. */
size_t cnx_taproot_output_len(void) { return 33; }

/* The one long-lived object in this shim. See "THE CONTEXT" above. */
static secp256k1_context *cnx_secp_ctx = NULL;

/* Create the context if it does not exist, then randomize it.
 *
 * CONTEXT RANDOMIZATION IS THE POINT OF THE CONTEXT. Upstream: "The primary
 * purpose of context objects is to store randomization data for enhanced
 * protection against side-channel leakage. This protection is only effective
 * if the context is randomized after its creation." It blinds the scalar
 * multiplications that involve a SECRET key, so it is re-done before every
 * such operation here, which is upstream's own "before every few computations
 * involving secret keys is recommended as a defense-in-depth measure" taken at
 * its strongest reading. That costs one OS entropy draw and one blinding
 * update per secret operation, which is the same order as what trezor-crypto
 * already spends on this member's ECDSA path (it draws OS entropy on every
 * scalar multiply, for the same reason - see the entropy section above).
 *
 * It FAILS CLOSED. If the OS entropy source is unavailable, the call returns
 * CNX_ERR_ENTROPY and no signing happens, exactly as the trezor-crypto entry
 * points above do via cnx_entropy_ok(). A context that could not be randomized
 * is never used: on the create path it is destroyed again, so the next call
 * retries from scratch rather than inheriting an unblinded context.
 *
 * THE ONE THING THAT IS EASY TO MISREAD, so it is said here rather than left
 * to a reader's inference: `randomize = 0` skips the RE-randomization, not the
 * entropy requirement in general. A brand-new context is always randomized
 * (the flag is forced below), so the FIRST call of any kind - including a
 * verification or an address computation - needs the OS entropy source once.
 * That is not a regression this section introduces: cnx_ecdsa_verify above has
 * required entropy on every call since phase 2, because trezor-crypto
 * randomizes the projective Z coordinate on every scalar multiply. What
 * `randomize = 0` buys is that a public-key operation on an ALREADY-created
 * context spends no entropy and cannot fail for the lack of it. */
static int cnx_secp_ready(int randomize) {
  unsigned char seed[32];
  int fresh = 0;
  int ok = 0;
  if (cnx_secp_ctx == NULL) {
    cnx_secp_ctx = secp256k1_context_create(SECP256K1_CONTEXT_NONE);
    if (cnx_secp_ctx == NULL) return CNX_ERR_INTERNAL;
    fresh = 1;
    randomize = 1; /* a brand-new context has never been randomized */
  }
  if (!randomize) return CNX_OK;
  if (!cnx_entropy_fill(seed, sizeof seed)) {
    if (fresh) {
      secp256k1_context_destroy(cnx_secp_ctx);
      cnx_secp_ctx = NULL;
    }
    return CNX_ERR_ENTROPY;
  }
  ok = secp256k1_context_randomize(cnx_secp_ctx, seed);
  memzero(seed, sizeof seed);
  if (!ok) {
    if (fresh) {
      secp256k1_context_destroy(cnx_secp_ctx);
      cnx_secp_ctx = NULL;
    }
    return CNX_ERR_INTERNAL;
  }
  return CNX_OK;
}

/* The BIP-341 tweak scalar: t = hash_TapTweak(bytes(P) || merkle_root).
 *
 * THE MERKLE ROOT IS OPTIONAL AND ITS ABSENCE IS NOT A ZERO ROOT. THIS IS A
 * CONSENSUS RULE, NOT A CONVENIENCE. BIP-341 defines the tweak over
 * `bytes(P) || merkle_root` where merkle_root is the EMPTY BYTE STRING when
 * the output commits to no script tree (a key-path-only spend, the common
 * case). Hashing 32 zero bytes instead would hash 64 bytes where the spec
 * hashes 32, producing a different tweak, a different output key, a different
 * address, and coins nobody can spend. The two cases are therefore carried by
 * the LENGTH, not by a sentinel value: rootlen 0 means key-path-only and
 * rootlen 32 means a real root, and any other length is refused. An all-zero
 * 32-byte root is a legal (if useless) script commitment and is treated as
 * one, because that is what it is.
 *
 * The tagged hash is upstream's secp256k1_tagged_sha256, i.e.
 * SHA256(SHA256(tag) || SHA256(tag) || msg) with tag = "TapTweak". CoinXT does
 * not build the tagged-hash construction itself even though it has SHA-256
 * three feet up this file: composing it here would be re-deriving a
 * specification detail that the library implementing the rest of BIP-341
 * already implements and tests. */
static int cnx_taproot_tweak_scalar(const unsigned char *internal32,
                                    const unsigned char *root, size_t rootlen,
                                    unsigned char *out32) {
  static const unsigned char tag[8] = {'T', 'a', 'p', 'T', 'w', 'e', 'a', 'k'};
  unsigned char msg[64];
  size_t msglen = 32;
  memcpy(msg, internal32, 32);
  if (rootlen == 32) {
    memcpy(msg + 32, root, 32);
    msglen = 64;
  }
  if (!secp256k1_tagged_sha256(cnx_secp_ctx, out32, tag, sizeof tag, msg, msglen)) {
    memzero(msg, sizeof msg);
    return CNX_ERR_INTERNAL;
  }
  memzero(msg, sizeof msg);
  return CNX_OK;
}

/* Shared guard for the optional merkle root. Mirrors the in-buffer convention
 * this shim uses everywhere else: a NULL pointer is tolerated only when the
 * matching length is 0. */
static int cnx_root_ok(const unsigned char *root, size_t rootlen) {
  if (rootlen == 0) return 1;
  if (rootlen != 32) return 0;
  return root != NULL;
}

/* BIP-340: sign a 32-byte message with a 32-byte private key.
 *
 * THE MESSAGE IS A 32-BYTE DIGEST AND NOTHING ELSE, which is narrower than
 * BIP-340 allows (since 2022 it admits messages of any length; the published
 * vector file exercises 0, 1, 17 and 100 bytes). That is CLAUDE.md rule 3,
 * applied here as it is to cnx_ecdsa_sign: sign only the exact digest the app
 * hands you, never a blob it has not decoded. BIP-341 signs a 32-byte sighash,
 * which is the use this member exists for. VERIFICATION is deliberately NOT
 * restricted the same way - see cnx_schnorr_verify.
 *
 * AUX_RAND, AND WHAT AN ABSENT ONE MEANS HERE. BIP-340's "Default Signing"
 * takes 32 bytes of fresh randomness and folds them into the nonce derivation;
 * upstream accepts NULL and treats it as an all-zero aux, while warning that
 * providing real randomness is recommended. CoinXT does NOT take that default,
 * because a library that silently picks the least-protected option when the
 * caller says nothing is the fail-open shape this member exists to refuse.
 * The rule here is:
 *
 *   auxlen == 32  ->  use exactly those bytes. The signature is then a pure
 *                     function of (key, message, aux) and is KAT-pinnable;
 *                     this is what the BIP-340 test vectors specify and what
 *                     tools/coin-kat.py drives.
 *   auxlen == 0   ->  draw 32 FRESH bytes from the OS entropy source, and fail
 *                     closed (CNX_ERR_ENTROPY) if it is unavailable. Never an
 *                     all-zero aux.
 *   anything else ->  CNX_ERR_BADLEN.
 *
 * The second case is the ONE non-deterministic entry point in this shim, and
 * SPEC.md section 4's "every operation is a pure function of its inputs" now
 * carries that exception explicitly rather than being quietly false. It is
 * safe in the sense that matters: BIP-340's nonce is
 * hash(aux XOR key, P, msg), so it is deterministic in (key, msg) even at
 * aux = 0 and a bad aux draw can never repeat a nonce across different
 * messages. Randomness here only ADDS protection (against fault attacks and
 * against differential power analysis of the nonce derivation); it cannot
 * subtract any. A caller that wants byte-reproducible signatures supplies the
 * aux, which is one line and is what the vectors do.
 *
 * Upstream's sign32 does not itself verify the signature it produced (its
 * header says so and suggests verifying manually). This shim does not add that
 * check either: it would double the cost of every signature to defend against
 * a fault in code the KATs pin byte for byte, and the caller that wants it can
 * call cnx_schnorr_verify - which is exported, and which coin-kat.py runs over
 * every signature this function makes. */
int cnx_schnorr_sign(const unsigned char *sk, size_t sklen,
                     const unsigned char *msg, size_t msglen,
                     const unsigned char *aux, size_t auxlen,
                     unsigned char *sig, size_t siglen) {
  secp256k1_keypair kp;
  unsigned char aux32[32];
  int rc = CNX_OK;
  if (sk == NULL || msg == NULL || sig == NULL) return CNX_ERR_NULL;
  if (sklen != 32 || msglen != 32 || siglen != 64) return CNX_ERR_BADLEN;
  if (aux == NULL) {
    if (auxlen != 0) return CNX_ERR_NULL;
  } else if (auxlen != 0 && auxlen != 32) {
    return CNX_ERR_BADLEN;
  }
  if (auxlen == 32) {
    memcpy(aux32, aux, 32);
  } else if (!cnx_entropy_fill(aux32, sizeof aux32)) {
    return CNX_ERR_ENTROPY;
  }
  rc = cnx_secp_ready(1); /* a SECRET-key operation: re-randomize the context */
  if (rc != CNX_OK) {
    memzero(aux32, sizeof aux32);
    return rc;
  }
  if (!secp256k1_keypair_create(cnx_secp_ctx, &kp, sk)) {
    memzero(aux32, sizeof aux32);
    memzero(&kp, sizeof kp);
    memzero(sig, siglen);
    return CNX_ERR_BADKEY;
  }
  if (!secp256k1_schnorrsig_sign32(cnx_secp_ctx, sig, msg, &kp, aux32)) {
    rc = CNX_ERR_INTERNAL;
    memzero(sig, siglen);
  }
  /* kp holds the private key; aux32 is nonce input. Neither stays on the
   * stack (the same discipline as bignum256 k in cnx_seckey_verify). */
  memzero(&kp, sizeof kp);
  memzero(aux32, sizeof aux32);
  return rc;
}

/* BIP-340 verification. Reports through the STATUS, on exactly the split
 * cnx_ecdsa_verify uses: CNX_OK means the signature is good, CNX_ERR_BADSIG
 * means it is not, and a WRONG BUFFER LENGTH is its own error because that is
 * a caller bug rather than a verdict about a signature.
 *
 * AN X-ONLY KEY THAT DOES NOT PARSE IS "false", NOT AN ERROR, and that is not
 * a judgement call - BIP-340's published vector set decides it. Index 5 is
 * "public key not on the curve" and index 14 is "public key is not a valid X
 * coordinate because it exceeds the field size"; both list their expected
 * verification result as FALSE. A shim that returned CNX_ERR_BADKEY there
 * would make cxSchnorrVerify throw where the specification says it must answer
 * no, and a caller checking a third party's signature would see an exception
 * for a case that is simply an invalid signature. Note this differs from
 * cnx_ecdsa_verify's treatment of a bad pubkey, and the difference is real
 * rather than an inconsistency: there the rejected shapes are wrong LENGTHS
 * and wrong PREFIX BYTES, which are structural, and the overread guard has to
 * refuse them before upstream sees them. Here every 32-byte string is
 * structurally a candidate x-only key and only the curve can say otherwise.
 *
 * THE MESSAGE MAY BE ANY LENGTH, unlike cnx_schnorr_sign's. BIP-340 has
 * admitted arbitrary-length messages since 2022 and its vector file carries
 * four of them (0, 1, 17 and 100 bytes), so a verifier that insisted on 32
 * would REJECT VALID SIGNATURES - failing closed in the wrong direction, which
 * is not safety, it is a wrong answer. Signing stays narrow because signing is
 * where blind-signing risk lives; verifying is where interoperability lives. */
int cnx_schnorr_verify(const unsigned char *xonly, size_t xonlylen,
                       const unsigned char *msg, size_t msglen,
                       const unsigned char *sig, size_t siglen) {
  secp256k1_xonly_pubkey pk;
  int rc = CNX_OK;
  if (xonly == NULL || sig == NULL) return CNX_ERR_NULL;
  if (xonlylen != 32 || siglen != 64) return CNX_ERR_BADLEN;
  if (msg == NULL) {
    if (msglen != 0) return CNX_ERR_NULL;
    msg = cnx_empty;
  }
  rc = cnx_secp_ready(0); /* public data only: no secret scalar to blind */
  if (rc != CNX_OK) return rc;
  if (!secp256k1_xonly_pubkey_parse(cnx_secp_ctx, &pk, xonly)) return CNX_ERR_BADSIG;
  return secp256k1_schnorrsig_verify(cnx_secp_ctx, sig, msg, msglen, &pk) == 1
             ? CNX_OK
             : CNX_ERR_BADSIG;
}

/* The 32-byte x-only public key for a private key: BIP-340's bytes(P), which
 * is the X coordinate of the point whose Y is even. This is the INTERNAL key a
 * Taproot output is built from, and it is also what a BIP-340 verifier needs.
 *
 * It is NOT the 33-byte compressed key with its prefix removed, in general:
 * cnx_pubkey_from_seckey returns the point for THIS private key, whose Y may be
 * odd, whereas x-only serialization implicitly selects the even-Y point. The
 * two X coordinates happen to be equal (negating a point keeps X), so in
 * practice byte 2..33 of the compressed key IS this value - but the reason
 * they agree is a property of the curve, not of the encoding, and a caller
 * should not have to know that. Upstream's keypair machinery states it
 * directly, so this is a call rather than a slice. */
int cnx_xonly_pubkey_from_seckey(const unsigned char *sk, size_t sklen,
                                 unsigned char *out, size_t outlen) {
  secp256k1_keypair kp;
  secp256k1_xonly_pubkey pk;
  int rc = CNX_OK;
  if (sk == NULL || out == NULL) return CNX_ERR_NULL;
  if (sklen != 32 || outlen != 32) return CNX_ERR_BADLEN;
  rc = cnx_secp_ready(1); /* derives a point from a SECRET scalar */
  if (rc != CNX_OK) return rc;
  if (!secp256k1_keypair_create(cnx_secp_ctx, &kp, sk)) {
    memzero(&kp, sizeof kp);
    memzero(out, outlen);
    return CNX_ERR_BADKEY;
  }
  if (!secp256k1_keypair_xonly_pub(cnx_secp_ctx, &pk, NULL, &kp)) {
    memzero(&kp, sizeof kp);
    memzero(out, outlen);
    return CNX_ERR_INTERNAL;
  }
  /* Returns 1 always, per upstream's header; the status is read anyway so a
   * future change of contract cannot pass silently. */
  if (!secp256k1_xonly_pubkey_serialize(cnx_secp_ctx, out, &pk)) {
    memzero(&kp, sizeof kp);
    memzero(out, outlen);
    return CNX_ERR_INTERNAL;
  }
  memzero(&kp, sizeof kp);
  return CNX_OK;
}

/* BIP-341: Q = P + int(hash_TapTweak(bytes(P) || merkle_root)) * G.
 *
 * Writes the 33-byte output record described at cnx_taproot_output_len: 32
 * bytes of x-only output key (the witness program of a P2TR scriptPubKey, and
 * the payload of a bc1p... address) followed by the output key's parity byte.
 *
 * Every input here is PUBLIC, so the context is not re-randomized: upstream is
 * explicit that the randomization blinds multiplications of a SECRET scalar
 * with the base point, and there is no secret in this call. Spending the
 * entropy draw anyway would buy nothing. (It does not make this call
 * entropy-free in absolute terms - creating the context in the first place
 * randomizes it once, whichever entry point gets there first; see
 * cnx_secp_ready.)
 *
 * See cnx_taproot_tweak_scalar for why an absent merkle root is length 0 and
 * NOT 32 zero bytes. */
int cnx_taproot_tweak_pubkey(const unsigned char *internal, size_t internallen,
                             const unsigned char *root, size_t rootlen,
                             unsigned char *out, size_t outlen) {
  secp256k1_xonly_pubkey ipk;
  secp256k1_xonly_pubkey opk;
  secp256k1_pubkey tweaked;
  unsigned char tweak[32];
  int parity = 0;
  int rc = CNX_OK;
  if (internal == NULL || out == NULL) return CNX_ERR_NULL;
  if (internallen != 32 || outlen != 33) return CNX_ERR_BADLEN;
  if (!cnx_root_ok(root, rootlen)) {
    if (rootlen == 32) return CNX_ERR_NULL;
    return CNX_ERR_BADLEN;
  }
  rc = cnx_secp_ready(0);
  if (rc != CNX_OK) return rc;
  if (!secp256k1_xonly_pubkey_parse(cnx_secp_ctx, &ipk, internal)) {
    memzero(out, outlen);
    return CNX_ERR_BADKEY;
  }
  rc = cnx_taproot_tweak_scalar(internal, root, rootlen, tweak);
  if (rc != CNX_OK) {
    memzero(out, outlen);
    return rc;
  }
  /* Upstream returns 0 only when the tweak is the negation of the internal
   * key's scalar (about 1 in 2^128 for a hash output), which BIP-341 treats
   * the same way BIP-32 treats an invalid child: the commitment is unusable
   * and the caller must change an input. */
  if (!secp256k1_xonly_pubkey_tweak_add(cnx_secp_ctx, &tweaked, &ipk, tweak)) {
    memzero(tweak, sizeof tweak);
    memzero(out, outlen);
    return CNX_ERR_BADKEY;
  }
  memzero(tweak, sizeof tweak);
  if (!secp256k1_xonly_pubkey_from_pubkey(cnx_secp_ctx, &opk, &parity, &tweaked)) {
    memzero(out, outlen);
    return CNX_ERR_INTERNAL;
  }
  if (!secp256k1_xonly_pubkey_serialize(cnx_secp_ctx, out, &opk)) {
    memzero(out, outlen);
    return CNX_ERR_INTERNAL;
  }
  out[32] = (unsigned char)(parity ? 1 : 0);
  return CNX_OK;
}

/* The spending half of the same tweak: the private key for the output key
 * cnx_taproot_tweak_pubkey computes from the matching internal key.
 *
 * The tagged hash commits to bytes(P), the EVEN-Y serialization of the
 * internal point - so this function derives P from the private key rather than
 * being told it, which removes the one way a caller could pair a private key
 * with somebody else's internal key and get a spendable-looking result for
 * coins it cannot touch. Upstream's keypair_xonly_tweak_add then handles the
 * negations BIP-341 requires on both sides (the internal key's, if its Y is
 * odd, and the output key's), which is the fiddly part of the spec and the
 * part worth not reimplementing.
 *
 * The result is the scalar to hand to cnx_schnorr_sign for a key-path spend.
 * tools/coin-kat.py closes that loop end to end: tweak the key, sign with it,
 * and verify against the x-only OUTPUT key that cnx_taproot_tweak_pubkey
 * produced from the internal key alone. */
int cnx_taproot_tweak_seckey(const unsigned char *sk, size_t sklen,
                             const unsigned char *root, size_t rootlen,
                             unsigned char *out, size_t outlen) {
  secp256k1_keypair kp;
  secp256k1_xonly_pubkey ipk;
  unsigned char internal[32];
  unsigned char tweak[32];
  int rc = CNX_OK;
  if (sk == NULL || out == NULL) return CNX_ERR_NULL;
  if (sklen != 32 || outlen != 32) return CNX_ERR_BADLEN;
  if (!cnx_root_ok(root, rootlen)) {
    if (rootlen == 32) return CNX_ERR_NULL;
    return CNX_ERR_BADLEN;
  }
  rc = cnx_secp_ready(1); /* a SECRET-key operation */
  if (rc != CNX_OK) return rc;
  if (!secp256k1_keypair_create(cnx_secp_ctx, &kp, sk)) {
    memzero(&kp, sizeof kp);
    memzero(out, outlen);
    return CNX_ERR_BADKEY;
  }
  if (!secp256k1_keypair_xonly_pub(cnx_secp_ctx, &ipk, NULL, &kp) ||
      !secp256k1_xonly_pubkey_serialize(cnx_secp_ctx, internal, &ipk)) {
    memzero(&kp, sizeof kp);
    memzero(out, outlen);
    return CNX_ERR_INTERNAL;
  }
  rc = cnx_taproot_tweak_scalar(internal, root, rootlen, tweak);
  if (rc != CNX_OK) {
    memzero(&kp, sizeof kp);
    memzero(out, outlen);
    return rc;
  }
  if (!secp256k1_keypair_xonly_tweak_add(cnx_secp_ctx, &kp, tweak)) {
    memzero(tweak, sizeof tweak);
    memzero(&kp, sizeof kp);
    memzero(out, outlen);
    return CNX_ERR_BADKEY;
  }
  memzero(tweak, sizeof tweak);
  /* Returns 1 always; read anyway, as above. */
  if (!secp256k1_keypair_sec(cnx_secp_ctx, out, &kp)) {
    memzero(&kp, sizeof kp);
    memzero(out, outlen);
    return CNX_ERR_INTERNAL;
  }
  memzero(&kp, sizeof kp);
  return CNX_OK;
}
