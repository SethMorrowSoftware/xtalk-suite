# Vendored third-party sources

These files are copied verbatim (no local patches) from **trezor-firmware**,
directory `crypto/` - byte-identical to the copies the sibling member coinxt
already vendors under `coinxt/native/vendor/` (same upstream, same pinned
commit), so the suite carries ONE provenance for this code, not two.

- Upstream: https://github.com/trezor/trezor-firmware  (directory `crypto/`)
- License: **MIT for trezor-crypto itself** (see `LICENSE` in this directory).
  `sha3.*` is RHash's MIT under its own copyright holder; `memzero.*` and
  `byte_order.h` / `options.h` are trezor-crypto's MIT. All permissive, none
  copyleft. The suite-level attribution table in the repository root `LICENSE`
  lists the SHA-3 row; every file keeps its own header verbatim.
- Pinned commit: `230cfe37e4c5fefb6ca117725d261a7b3646a995` (branch `main`,
  fetched 2026-07-02, via the coinxt vendor copy on 2026-08-11)

## Why sodiumxt vendors anything at all

libsodium's stable API deliberately has no SHA-3/Keccak, and the family needs
SHA3-256 for exactly one thing: the 2-byte checksum inside a v3 `.onion`
address, so an address can be computed OFFLINE from an ed25519 public key
(onionxt `oxAddressFromPublicKey`, riptide's identity-to-onion mapping). That
was onionxt's deferred capability gap #2 (`onionxt/docs/08`). `sxt_sha3_256`
(ABI 7) closes it with the smallest audited implementation already trusted by
this repository.

## Files

| file | purpose |
|---|---|
| `sha3.h` / `sha3.c` | SHA3-256 (NIST FIPS-202, 0x06 padding); the Keccak-256 entry points exist in the file but are NOT exported through the shim |
| `memzero.h` / `memzero.c` | best-effort secret wiping used by the sha3 context |
| `byte_order.h` | endianness macros `sha3.c` compiles against |
| `options.h` | trezor-crypto compile-time config the headers include |

Only `sxt_sha3_256` / `sxt_sha3_256_bytes` are exported; the shim's hidden
default visibility keeps every vendored symbol internal to the library.
