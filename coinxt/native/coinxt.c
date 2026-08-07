/* coinxt.c - the CoinXT C shim (cnx_ ABI) over vendored trezor-crypto.
 *
 * CoinXT wraps trezor-crypto (MIT) behind a thin, stable C ABI so an OXT / xTalk
 * app can reach Bitcoin/Ethereum crypto through one LCB foreign module. This file
 * is the ENTIRE native surface (SPEC.md section 5.1): every export is buffer-in /
 * buffer-out, returns an int status, and is deterministic. No I/O, no global
 * state, no ambient RNG (RFC 6979 signing needs none; fresh key material is the
 * caller's, per SPEC.md section 4).
 *
 * Phase 1: the hash surface + the ABI guard + the length functions. The curve
 * (secp256k1), HD (BIP-32), and mnemonic (BIP-39) exports land in later phases;
 * the ABI contract they all follow is fixed here.
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

#include "hmac.h"      /* vendored trezor-crypto: hmac_sha256 / hmac_sha512      */
#include "pbkdf2.h"    /* vendored trezor-crypto: pbkdf2_hmac_sha512             */
#include "ripemd160.h" /* vendored trezor-crypto: ripemd160 (one-shot)           */
#include "sha2.h"      /* vendored trezor-crypto: sha256_Raw / sha512_Raw        */
#include "sha3.h"      /* vendored trezor-crypto: keccak_256 / sha3_256 (one-shot) */

/* ---- ABI version + status codes (stable; never renumber a shipped code) ---- */

/* 2: phase 1 completed the hash surface (SHA-2, RIPEMD-160, HMAC, PBKDF2).
 * Additive - every ABI 1 symbol kept its name and signature - but the rule is
 * to bump on ANY ABI change so cxCheckABI() can refuse a stale binary rather
 * than fail at the first missing bind. */
#define CNX_ABI_VERSION 2

#define CNX_OK 0
#define CNX_ERR_NULL (-1)   /* a required buffer pointer was NULL */
#define CNX_ERR_BADLEN (-2) /* a fixed-size buffer had the wrong length (LCB layer checks) */
#define CNX_ERR_RANGE (-3)  /* a length or count the underlying primitive cannot represent */

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
