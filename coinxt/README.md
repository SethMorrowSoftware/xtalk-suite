# CoinXT

**Bitcoin and Ethereum cryptography for OpenXTalk (OXT) / the xTalk family.**

CoinXT gives an xTalk app the primitives a wallet or a dapp client is built from, by wrapping
**trezor-crypto** (the MIT-licensed, dependency-free C crypto core of the Trezor hardware wallet) behind
a thin C ABI and a livecodescript API. One wrap covers both chains:

- **secp256k1** keypairs, ECDSA (RFC 6979 deterministic), **recoverable** signatures and public-key
  recovery (Ethereum's `v` / `ecrecover`), ECDH, and Schnorr / BIP-340 (Taproot).
- **Hashes** both chains need: SHA-256/512, SHA3-256/512, **Keccak-256** (Ethereum's non-NIST padding),
  RIPEMD-160, plus HMAC and PBKDF2-HMAC-SHA512.
- **HD wallets:** BIP-32 derivation, BIP-39 mnemonics (SLIP-39 later).
- **Address and serialization formats:** Base58Check, Bech32 / Bech32m, hex, RLP, xprv/xpub, WIF, and the
  EIP-55 Ethereum checksum.

```
app (livecodescript)
   |
CoinXT (cx*)   src/coinxt.livecodescript
   |- encodings in SCRIPT   hex, Base58Check, Bech32/Bech32m, RLP, addresses (pure byte work)
   |- FFI seam              one .lcb module
CoinXT C shim (cnx_)   native/coinxt.c  +  vendored trezor-crypto (MIT, no external deps)
   |- curve + hashes in C   secp256k1, SHA2/SHA3/Keccak-256/RIPEMD-160, HMAC, PBKDF2, BIP-32, BIP-39
```

## What CoinXT is NOT

- **Not a wallet, node, or broadcaster.** It produces keys, addresses, and signed bytes. The app owns key
  storage, backup, the confirm-before-sign UX, and putting a signed transaction on the wire (optionally
  through Tor via OnionXT, a documentation-level composition).
- **Not new cryptography.** Every curve op and hash is trezor-crypto's. CoinXT adds no cipher of its own,
  the same rule SodiumXT and OnionXT hold.
- **Not hardware-wallet isolation.** It runs in a general-purpose OXT process; script variables are not
  locked memory. It is a strong, correct, self-contained crypto layer, not a secure element.

## Why trezor-crypto

MIT-licensed, plain C, **no external dependencies**, and it bundles secp256k1 (also MIT). That is exactly
what the family's FFI pattern wants: a self-contained C library with a buffer-in / buffer-out API and a
permissive license we can vendor and redistribute. It is the crypto core of a shipping hardware wallet,
so the curve and hash code is battle-tested. CoinXT vendors a subset of its `.c` files plus a small shim
and builds one shared library per platform. No autotools, no submodule tree.

## Layout

```
CoinXT/
  README.md                 you are here
  SPEC.md                   what CoinXT is: the C/script split, the ABI contract, formats, security model
  IMPLEMENTATION-PLAN.md    the phased build order
  CLAUDE.md                 the operational guide + the FFI/C-ABI law (read before touching the shim)
  MIGRATION.md              how to split CoinXT into its own repository (delete after the move)
  templates/
    CLAUDE.md               the portable xTalk/LiveCode/LCB lesson book (ALL the family's generic
                            engine lessons; copy it to the root of any NEW xTalk project)
  .github/workflows/ci.yml  the gates in CI (dormant until CoinXT is a repository root)
  native/
    coinxt.c                the C shim (cnx_ ABI over the vendored crypto)
    build.sh                builds the shared library, and the ASan + UBSan self-test
    MANIFEST.sha256         integrity pins: the vendored sources now; release binaries and the
                            wordlist join in later phases
    vendor/                 the vendored trezor-crypto subset (MIT) + VENDOR.md + LICENSE
  src/                      (lands with the on-engine binding step)
    coinxt.lcb              the foreign-handler module (binds to cnx_*)
    coinxt.livecodescript   the public cx* API + the script-side encodings
  tools/
    coin-kat.py             known-answer vectors (builds the shim headless, drives it via ctypes)
    check-livecodescript.py the static gate for .lcb / .livecodescript (carried verbatim)
    check-docs-style.py     the house-style gate for .md (carried verbatim)
  examples/                 (later phases)
    coinxt-demo.livecodescript    keygen, addresses, sign/verify, an HD wallet from a mnemonic
    coinxt-tests.livecodescript   a pure, offline self-test harness (sPass/sFail, KATs)
```

## The gates (run before any commit)

```sh
python3 tools/check-livecodescript.py         # static gate for the script layer
python3 tools/check-docs-style.py             # house-style gate for the docs
python3 tools/coin-kat.py --check             # builds the shim, runs the known-answer vectors
sh native/build.sh asan                       # ASan + UBSan native self-test
( cd native && sha256sum -c MANIFEST.sha256 ) # vendored-source integrity
```

All five run in CI (`.github/workflows/ci.yml`). There is no headless way to compile or run
`.livecodescript` / `.lcb` on OXT, so a script change additionally needs an on-engine pass; the honest
status until then is "designed and statically reasoned" (see [CLAUDE.md](CLAUDE.md)).

## Status

**Design done; phase 1 underway.** The native seam is proven: the shim (`native/coinxt.c`) over the
vendored trezor-crypto SHA-3 unit builds under ASan + UBSan, exposes `cnx_keccak256` / `cnx_sha3_256`
(the Ethereum-vs-NIST footgun handled), and passes known-answer vectors headless via
`tools/coin-kat.py` (Keccak against published vectors, SHA3 against Python `hashlib`). That retires the
FFI/build pipeline, the family's most expensive area. Next: the secp256k1 curve surface (phase 2), then
encodings/addresses, HD wallets, and the `.lcb` on-engine binding.

[SPEC.md](SPEC.md), [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md), and [CLAUDE.md](CLAUDE.md) are the
design and the running as-built log. Every deterministic path is pinned to a public known-answer vector,
and the "done" bar for a signing feature is that a CoinXT signature verifies in a mainstream external
library, not just in CoinXT.

CoinXT is an independent library: it does not depend on OnionXT (the two compose at the documentation
level only), and everything it needs (the static gates, the CI workflow, the portable engine-lesson
book, the vendored sources and their manifest) lives inside this directory. It is currently staged
inside the OnionXT repository and is ready to be split into its own repository; the exact procedure and
the post-split checklist are in [MIGRATION.md](MIGRATION.md). (Remove this paragraph after the move.)

## A note on handling money

CoinXT deals with private keys and real funds, so the family's "compose an audited library, never
hand-roll crypto" rule counts double: the curve and hashes are trezor-crypto's, the app owns custody and
confirm-before-sign, and every checksum is verified on decode with a fail-closed error. See the security
model in [SPEC.md](SPEC.md) section 8 and the rules in [CLAUDE.md](CLAUDE.md).

## House style

ASCII only in `.livecodescript` / `.lcb`. No em-dashes anywhere (hyphens, commas, colons,
parentheses). Comment the *why*, densely. Enforced by the carried `check-livecodescript.py` and
`check-docs-style.py` gates.
