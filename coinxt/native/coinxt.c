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

#include <stddef.h>

#include "sha3.h" /* vendored trezor-crypto: keccak_256 / sha3_256 (one-shot) */

/* ---- ABI version + status codes (stable; never renumber a shipped code) ---- */

#define CNX_ABI_VERSION 1

#define CNX_OK 0
#define CNX_ERR_NULL (-1)   /* a required buffer pointer was NULL */
#define CNX_ERR_BADLEN (-2) /* a fixed-size buffer had the wrong length (LCB layer checks) */

int cnx_abi_version(void) { return CNX_ABI_VERSION; }

/* ---- length constants exposed as functions (never hardcode a size in LCB) --- */

size_t cnx_keccak256_len(void) { return 32; }
size_t cnx_sha3_256_len(void) { return 32; }

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
