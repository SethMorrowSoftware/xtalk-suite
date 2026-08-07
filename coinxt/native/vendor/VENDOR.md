# Vendored third-party sources

These files are copied verbatim (no local patches) from **trezor-firmware**, directory `crypto/`.

- Upstream: https://github.com/trezor/trezor-firmware  (directory `crypto/`)
- License: **MIT** (see `LICENSE` in this directory)
- Pinned commit: `230cfe37e4c5fefb6ca117725d261a7b3646a995` (branch `main`, fetched 2026-07-02)

## Files (phase 1: the hash unit)

| file | purpose |
|---|---|
| `sha3.h` / `sha3.c` | Keccak-256 (Ethereum, 0x01 padding) and SHA3-256 (NIST FIPS-202, 0x06) |
| `memzero.h` / `memzero.c` | best-effort secret wiping used by the hash contexts |
| `byte_order.h` | endianness macros used by `sha3.c` |
| `options.h` | trezor-crypto compile-time config (USE_KECCAK=1, USE_RFC6979=1, ...) |

Later phases add `secp256k1` + `ecdsa.c` + `bignum.c` (curve), `sha2.c` / `ripemd160.c` / `hmac.c` /
`pbkdf2.c` (hashes/KDF), `bip32.c` / `bip39.c` (HD + mnemonic), and `base58.c` / `segwit_addr.c` if we
decide to keep any encoding native rather than in script.

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
