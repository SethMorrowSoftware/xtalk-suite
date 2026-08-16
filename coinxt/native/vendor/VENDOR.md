# Vendored third-party sources

**TWO upstream libraries live here**, and that is a decision rather than an accident. Everything
directly under `vendor/` is **trezor-crypto**; everything under `vendor/libsecp256k1/` is
**upstream bitcoin-core/secp256k1**, added 2026-08-16 for BIP-340 Schnorr and the BIP-341 Taproot
tweak. See [`../../SPEC.md`](../../SPEC.md) section 2 and the dated entry in
[`../../CLAUDE.md`](../../CLAUDE.md) for why the "one library" rule changed; the operational summary
is that trezor-crypto's plain-C tree has no BIP-340 implementation at all, and the alternative to a
second audited library was writing a signature scheme by hand.

Both trees are copied verbatim. No local patches, in either.

## trezor-crypto

These files are copied verbatim (no local patches) from **trezor-firmware**, directory `crypto/`.

- Upstream: https://github.com/trezor/trezor-firmware  (directory `crypto/`)
- License: **MIT for trezor-crypto itself** (see `LICENSE` in this directory), but
  **not for every file here**. Upstream vendors third-party implementations that keep
  their own terms: `sha2.*` is BSD-3-Clause, `ripemd160.*` is public domain,
  `blake256.*` is CC0, `blake2b.*` is CC0/OpenSSL/Apache-2.0 at our option (we elect
  CC0), `sha3.*` is RHash's MIT, and `groestl.*` is MIT under a different copyright
  holder. All permissive, none copyleft, but the BSD-3-Clause one binds BINARY
  redistribution and coinxt commits built libraries. The per-file map and the full
  texts are in [`../../THIRD-PARTY-LICENSES.md`](../../THIRD-PARTY-LICENSES.md);
  every file also keeps its own header verbatim.
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

## Files (phase 4: the BIP-39 wordlist)

| file | purpose |
|---|---|
| `bip39.h` | `BIP39_WORD_COUNT` (2048), `BIP39_MAX_WORD_LEN` (8) and the `extern` declaration of the table below. Includes only `stdbool/stddef/stdint` and `options.h`, so it drags in nothing |
| `bip39_english.c` | the 2048-word normative English wordlist |

**`bip39.c` is deliberately NOT vendored.** Its `mnemonic_from_data` returns a `const char *` into a
static buffer, which the C-ABI rules forbid bridging into script, and its `mnemonic_to_seed` is
PBKDF2-HMAC-SHA512, which the shim already exports. What is left of BIP-39 - 11-bit packing and a
checksum - is byte shuffling with no secret-dependent branch and therefore belongs in
`src/coinxt.livecodescript` by the C-vs-script rule. The wordlist crosses as data
(`cnx_bip39_wordlist`), so the script gets the normative list without CoinXT transcribing 2048 words.

The list is **checked, not asserted**: `tools/coin-kat.py` reads it back through the shim, joins it the
canonical way and requires SHA-256 `2f5eed53a4727b4bf8880d8f3f199efc90e58503646d9ff8eff3a2ed3b24dbda`,
the hash BIP-39 itself publishes. It also requires the list to be sorted and duplicate-free, because
the script binary-searches it.

**BIP-32 is not here either, and that was a decision.** `bip32.c` would supply the whole of HD
derivation, but it is written against every curve trezor supports, so vendoring it pulls in `curves.c`,
`nist256p1`, `ed25519-donna` and the Cardano variants - a large closure, nearly all of it code CoinXT
would ship, license and never call. BIP-32 needs exactly two things from the curve, and the
already-vendored `ecdsa.c` / `bignum.c` provide both: `cnx_seckey_tweak_add` (the `bn_add` / `bn_mod`
sequence copied from upstream's own `hdnode_private_ckd_bip32`) and `cnx_pubkey_tweak_add` (upstream's
`ecdsa_tweak_pubkey`, used as is).

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
- The MIT `LICENSE` ships alongside these files (redistribution requirement), and it is **not
  sufficient on its own**: `../../THIRD-PARTY-LICENSES.md` carries the texts for the files here that
  are BSD-3-Clause, public domain, CC0 or separately-held MIT. Adding a vendored file means checking
  its header for terms the MIT text does not cover, and adding it there if so.

## libsecp256k1 (bitcoin-core/secp256k1) - BIP-340 and BIP-341, added 2026-08-16

- Upstream: https://github.com/bitcoin-core/secp256k1
- License: **MIT throughout.** Unlike trezor-crypto, this tree vendors nothing under other terms:
  every file header carries the same MIT notice and a libsecp256k1 contributor's copyright, so it
  adds ONE row to the suite `LICENSE` and no per-file exceptions. `COPYING` ships beside the sources
  here (redistribution requirement) and the text is also in
  [`../../THIRD-PARTY-LICENSES.md`](../../THIRD-PARTY-LICENSES.md).
- Pinned commit: `439278a649d3099d62dde966a76dc04aaca7ccb3` (branch `master`, fetched 2026-08-16)

**Why a commit and not the release tag.** The pin is `v0.8.0` plus twelve commits. Eleven of them
touch only tests; the twelfth (`3d4340d`, "scratch: reject sizes that overflow when added to
header") hardens `src/scratch_impl.h`, which IS one of the files compiled here. So for the subset
vendored below, the pin is exactly "the last release, plus one hardening fix, minus nothing" - which
is a better place to stand than the tag, and the delta is small enough to state in a sentence rather
than to hand-wave. A plain commit hash is also this member's existing precedent: the trezor-crypto
pin above is one.

**Not the `secp256k1-zkp` fork.** Upstream carries the `schnorrsig` and `extrakeys` modules in
tree, which is everything BIP-340 and single-key BIP-341 need; the fork's extra value (adaptor
signatures, rangeproofs, MuSig2 history) is irrelevant here, and upstream is what Bitcoin Core
itself ships and audits.

### What was taken (58 files, and nothing else)

Only what compiles. No `tests*`, no `bench*`, no `ci/`, no `contrib/`, no `sage/`, no `doc/`, no
build system, and none of the modules that are not enabled (`ecdh`, `recovery`, `musig`,
`ellswift`, `silentpayments` - CoinXT already has ECDH and recovery from trezor-crypto, and the
rest is surface we would ship, license and never call).

| path | count | purpose |
|---|---|---|
| `COPYING` | 1 | the MIT text |
| `include/secp256k1.h`, `secp256k1_preallocated.h`, `secp256k1_extrakeys.h`, `secp256k1_schnorrsig.h` | 4 | the public headers the shim includes. `secp256k1_preallocated.h` is not used by CoinXT but IS included by `src/secp256k1.c` |
| `src/secp256k1.c` | 1 | the library. libsecp256k1 compiles as ONE translation unit: this file `#include`s every `*_impl.h` and, under the two module defines, the module bodies |
| `src/precomputed_ecmult.c` | 1 | the generated table of odd multiples of G and 2^128*G, used for VERIFICATION (see the size decision below) |
| `src/precomputed_ecmult_gen.c` | 1 | the generated signed-digit comb table for k*G, 22 kB at upstream's default (11, 6) configuration |
| `src/*.h` | 48 | the implementation headers `src/secp256k1.c` includes, transitively - the closure, computed with `gcc -MM` for both a 64-bit and a 32-bit target so the 32-bit-only files (`field_10x26*`, `scalar_8x32*`, `modinv32*`) are present |
| `src/modules/extrakeys/main_impl.h`, `src/modules/schnorrsig/main_impl.h` | 2 | the two enabled modules |

Two of those 48 headers, `int128_struct.h` and `int128_struct_impl.h`, are not reached by any build
CoinXT currently makes: `int128_impl.h` includes them only under `SECP256K1_INT128_STRUCT`, which
MSVC x64 selects and gcc/MinGW never do. They are vendored anyway, because a vendored file with a
dangling `#include` is a subset that cannot be built on a platform we might add, and the two of them
together are under 6 kB.

### The compile-time configuration (`native/build.sh`, `secp_cppflags`)

Configuration, not patches - every one is a knob upstream's own `configure.ac` / `CMakeLists.txt`
sets:

- `-DENABLE_MODULE_SCHNORRSIG -DENABLE_MODULE_EXTRAKEYS` - compile in the two modules, and only
  those two.
- `-DECMULT_WINDOW_SIZE=12` - **the one real tradeoff.** Upstream's default is 15, tuned for a node
  verifying blocks, and the table is `2^(w-2) * 64 * 2` bytes, i.e. **1,048,576 bytes of read-only
  data in every shipped binary** - and this member commits four of them. Measured here (gcc 13.3
  -O2, x86_64, min of 7 runs of 20,000 BIP-340 verifications):

  | window | verify | table |
  |---|---|---|
  | 15 (upstream default) | 33.26 us | 1,048,576 B |
  | **12 (chosen)** | **33.40 us** | **131,072 B** |
  | 10 | 35.02 us | 32,768 B |
  | 8 | 35.33 us | 8,192 B |
  | 6 | 37.64 us | 2,048 B |

  12 removes 87.5% of the table for 0.4%, which is inside the run-to-run spread - no measurable
  verification cost at all. Going further DOES cost measurable time (5% at w=10) to save a further
  96 kB, which is not worth paying once the free part has been taken. `precomputed_ecmult.c` is an
  `#if` ladder over the window, so any value in [2..15] compiles from the SAME vendored file: this
  is a define, not a regenerated table. The absolute numbers are one machine's; the ranking is what
  transfers.
- `-DSECP256K1_NO_API_VISIBILITY_ATTRIBUTES` - makes `SECP256K1_API` a bare `extern`. Upstream
  documents this define for exactly our case ("a static library which is linked into a shared
  library, and the latter should not re-export the libsecp256k1 API"). Without it MinGW would put
  `__declspec(dllexport)` on every `secp256k1_*` entry point.

Upstream's units are compiled with `-Wall -Wextra -Wno-unused-function`, which is upstream's OWN
flag set: it compiles as one unit and leaves the disabled modules' helpers unused, so the warning
fires about fifteen times on a perfectly good build. The `-Wno-` is scoped to upstream's translation
units and never reaches `native/coinxt.c` - which is why `build.sh` compiles the two groups
separately. That separation is load-bearing for a second reason: `vendor/secp256k1.c`
(trezor-crypto's curve parameters) and `vendor/libsecp256k1/src/secp256k1.c` share a BASENAME, so
any build deriving an object name from `basename` alone silently overwrites one with the other.

### Why the 2.4 MB table is vendored rather than generated

`src/precomputed_ecmult.c` is 2,409,168 bytes, 73% of everything vendored here. The three options
were (a) vendor it verbatim, (b) run upstream's `precompute_ecmult` generator at build time, (c)
shrink it. (c) is not an alternative to the other two - the file is an `#if` ladder, so a smaller
window still compiles the same 2.4 MB source - and it is taken anyway, above, because it shrinks the
BINARY.

(a) is chosen. (b) would keep the repository smaller and would add a **code-generation step to a
build that has none**: `native/build.sh` is POSIX sh and one compiler invocation, and its whole
virtue is that a cross build is `CC=x86_64-w64-mingw32-gcc sh native/build.sh pack x86_64-win32`. A
generator has to be built for the HOST and run before the library is built for the TARGET, which
introduces a second toolchain concept into that script, breaks on any host that cannot execute its
own output, and - the part that actually settles it - produces a table that **nothing in this tree
can hash-pin**. `MANIFEST.sha256` proves every vendored byte is upstream's; a generated table is
proven by nothing except that the generator ran. For a library that handles money, "the table came
from the pinned commit and here is its SHA-256" is worth more than 2.4 MB of repository.

What (a) costs, stated plainly: 3,285,330 bytes of vendored source (2.4 MB of it this one file),
paid once in history, and the four committed binaries grow as recorded in `../../CLAUDE.md`'s
as-built entry.

## Integrity

Every vendored file (and, from the packaging phase on, every shipped release binary) is pinned in
`../MANIFEST.sha256`, checked in CI. Verify locally with:

```sh
cd native && sha256sum -c MANIFEST.sha256
```

Any legitimate change to a vendored file (a re-pin, a recorded patch) refreshes the manifest in the
SAME change; a mismatch anywhere else means the tree is not what was reviewed. It pins 104 files
now (46 trezor-crypto plus this directory's two metadata files, and 58 libsecp256k1).

**How the libsecp256k1 files were verified, and it is the stronger of the two methods used here.**
Each one was extracted with `git cat-file blob <pin>:<path>` from a real clone of the pinned commit,
so it arrived inside a git object whose content hash git had already verified on receipt; the
installed file's blob id was then re-derived locally with `git hash-object` and compared against the
id the commit's tree lists. 58 of 58 matched. That is the same method the phase-2 trezor-crypto
files got, and it is what "verbatim" means here: not "looks the same", but "the same object git
names".
