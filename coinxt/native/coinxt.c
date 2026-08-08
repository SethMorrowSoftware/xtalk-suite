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

/* 3: phase 2 added the secp256k1 curve surface. Additive again - every ABI 2
 * symbol kept its name and signature - but the rule is to bump on ANY ABI
 * change so cxCheckABI() can refuse a stale binary rather than fail at the
 * first missing bind. */
#define CNX_ABI_VERSION 4

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
