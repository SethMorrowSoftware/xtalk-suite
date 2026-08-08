# Vendored third-party sources

These files are copied verbatim (no local patches) from **trezor-firmware**, directory `crypto/`.

- Upstream: https://github.com/trezor/trezor-firmware  (directory `crypto/`)
- License: **MIT** (see `LICENSE` in this directory)
- Pinned commit: `230cfe37e4c5fefb6ca117725d261a7b3646a995` (branch `main`, fetched 2026-07-02)

## Files (phase 1: the hash unit, complete)

| file | purpose |
|---|---|
| `sha3.h` / `sha3.c` | Keccak-256 (Ethereum, 0x01 padding) and SHA3-256 (NIST FIPS-202, 0x06) |
| `sha2.h` / `sha2.c` | SHA-256 and SHA-512 (Bitcoin checksums / address hashing; BIP-32 and BIP-39 derivation) |
| `ripemd160.h` / `ripemd160.c` | RIPEMD-160, the outer half of a Bitcoin `HASH160` |
| `hmac.h` / `hmac.c` | HMAC-SHA256 / HMAC-SHA512 (RFC 2104) |
| `pbkdf2.h` / `pbkdf2.c` | PBKDF2-HMAC-SHA512, the BIP-39 mnemonic-to-seed KDF |
| `memzero.h` / `memzero.c` | best-effort secret wiping used by the hash contexts |
| `byte_order.h` | endianness macros used by `sha3.c` and `sha2.c` |
| `options.h` | trezor-crypto compile-time config (USE_KECCAK=1, USE_RFC6979=1, ...) |

## Files (phase 2: the secp256k1 curve, complete)

This set is a **closure, not a wish list**. It was found by compiling, reading the undefined symbols,
adding the file that defines them, and repeating until the only unresolved name left was
`random_buffer` (which is ours to define, on purpose: see `../coinxt.c`).

| file | purpose |
|---|---|
| `ecdsa.h` / `ecdsa.c` | the curve surface: keys, ECDSA sign/verify over a digest, recovery, ECDH |
| `bignum.h` / `bignum.c` | the 256-bit modular arithmetic everything above is built from |
| `secp256k1.h` / `secp256k1.c` | the curve parameters (with `USE_PRECOMPUTED_CP=0`, so `secp256k1.table` is NOT needed and not vendored) |
| `rfc6979.h` / `rfc6979.c` | deterministic nonce generation, so a signature is a pure function of key and digest |
| `hmac_drbg.h` / `hmac_drbg.c` | the DRBG RFC 6979 is specified in terms of |
| `hasher.h` / `hasher.c` | the hash-dispatch table `ecdsa.h` types its message-signing entry points against |
| `blake256.*`, `blake2b.*`, `blake2_common.h`, `groestl.*` | the other backends in that table |
| `base58.h` / `base58.c`, `address.h` / `address.c` | referenced by `ecdsa.c`'s address helpers |
| `script.h`, `bip32.h`, `rand.h`, `ed25519-donna/ed25519.h` | headers only; no `.c` of theirs is needed |

Four of those entries look gratuitous, and each is load-bearing for a reason worth writing down,
because the obvious "cleanup" in every case is to edit a vendored file, which the rules below forbid:

- **`hasher.c` and its blake/groestl backends.** `ecdsa.h` declares `ecdsa_sign()` and `ecdsa_verify()`
  in terms of `HasherType`, so `ecdsa.o` references the dispatch table even though CoinXT only ever
  signs a **digest** and never calls those entry points. The table pulls in its backends.
- **`base58.c` / `address.c`.** `ecdsa.c` also contains address and WIF helpers CoinXT never calls
  (those encodings live in script, by design), and their references have to resolve at link time.
- **`script.h`.** `bignum.c` includes it and then uses **nothing** from it; the header is vendored only
  so `bignum.c` compiles as written.
- **`bip32.h` and `ed25519-donna/ed25519.h`.** `secp256k1.h` needs `curve_info` from `bip32.h`, which
  unconditionally includes the ed25519 header for its typedefs. No ed25519 code is linked.

None of these names reach the shipped surface: `src/coinxt.map` (and the generated `.def` on Windows)
narrows the exports to the `cnx_*` entry points, which is checked in CI per object format.

## Integrity, and how it was actually verified

Every file above is byte-identical to upstream at the pinned commit. The phase-2 check is stronger than
phase 1's re-fetch-and-compare: the sources were taken from a real `git fetch` of the pinned commit, so
each one arrived in a git object whose content hash git verified on receipt, and each installed file's
blob id was then re-derived locally and compared against the id the commit's tree lists. The 15
phase-1 files were re-verified the same way in the same run and were unchanged.

Later phases add `bip32.c` / `bip39.c` (HD + mnemonic) and `segwit_addr.c` if we ever decide to keep an
encoding native rather than in script.

**Not vendored, deliberately: `rand.c`.** trezor-crypto expects the integrator to supply
`random_buffer()`, and upstream's file is a placeholder PRNG. CoinXT defines its own in `../coinxt.c`
over the OS entropy source, and fails closed. See that file for why the curve needs entropy at all even
though signing is deterministic; it is not the reason phase 0 assumed.

## Rules (CLAUDE.md)

- **Verbatim only.** Do not edit a vendored file in place. If a patch is ever unavoidable, record it here
  with a diff and a reason, and hash the patched file in `MANIFEST.sha256`.
- **Re-pin deliberately.** Bumping the upstream commit is its own change: update the SHA above, re-run
  `tools/coin-kat.py`, refresh `../MANIFEST.sha256`, and note anything that shifted.
- The MIT `LICENSE` ships alongside these files (redistribution requirement).

## Integrity

Every vendored file (and, from the packaging phase on, every shipped release binary) is pinned in
`../MANIFEST.sha256`, checked in CI. Verify locally with:

```sh
cd native && sha256sum -c MANIFEST.sha256
```

Any legitimate change to a vendored file (a re-pin, a recorded patch) refreshes the manifest in the
SAME change; a mismatch anywhere else means the tree is not what was reviewed.
