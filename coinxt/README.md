# CoinXT

**Bitcoin and Ethereum cryptography for OpenXTalk (OXT) / the xTalk family.**

CoinXT gives an xTalk app the primitives a wallet or a dapp client is built from, by wrapping
**trezor-crypto** (the MIT-licensed, dependency-free C crypto core of the Trezor hardware wallet) behind
a thin C ABI and a livecodescript API. One wrap covers both chains:

- **secp256k1** keypairs, ECDSA (RFC 6979 deterministic), **recoverable** signatures and public-key
  recovery (Ethereum's `v` / `ecrecover`), and ECDH - all built (see Status). Schnorr / BIP-340
  (Taproot) is designed but deferred, because trezor-crypto's plain-C tree does not implement it.
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
  LICENSE                   CoinXT's own MIT license
  THIRD-PARTY-LICENSES.md   the vendored subset is NOT all MIT (BSD-3-Clause SHA-2, public-domain
                            RIPEMD-160, CC0 BLAKE, separately-held MIT Groestl). Ships with the
                            committed binaries because one of those binds binary redistribution
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
    vendor/                 the vendored trezor-crypto subset (MIT) + VENDOR.md + LICENSE.
                            The curve half is a CLOSURE, not a pick-list: see VENDOR.md for
                            why hasher.c, blake, groestl, base58.c and address.c are in it
  docs/
    api-reference.md        the cx* handlers that EXIST today (contrast SPEC.md, which describes
                            the whole designed API including phases not yet built)
  src/
    coinxt.lcb              the foreign-handler module (binds to all 30 cnx_* exports);
                            engine-proven end to end: phase 1 closed 2026-08-08, phases 2-4
                            closed 2026-08-10 (the folded harness, 207/207 on the re-run)
    coinxt.livecodescript   the phase-3 script layer: hex, Base58Check, bech32/bech32m, RLP
                            and the address builders. NOT part of the .lcb - it loads into the
                            message path (`start using stack "coinxt"`)
  tests/
    coin-selftest.livecodescript  the OXT runtime harness: paste into a stack script, it builds
                            its own UI and drives ALL 78 public cx* handlers against the
                            published vectors (35 from the .lcb, 43 from the script layer)
  tools/
    coin-kat.py             known-answer vectors (builds the shim headless, drives it via ctypes)
    check-selftest-vectors.py  re-derives the self-test's hand-copied vectors so they cannot
                            drift from the shim or the published answers (no compiler needed)
    check-binary-freshness.py  does the committed library still match the shim?
    package-extension.py    stage the installable extension (--assemble), record a newly
                            packed platform (--refresh-manifest), or install a library built
                            elsewhere (--lib, e.g. a macOS lipo output)
    check-livecodescript.py the static gate for .lcb / .livecodescript (carried verbatim)
    check-docs-style.py     the house-style gate for .md (carried verbatim)
    check-script-vectors.py runs src/coinxt.livecodescript against the published vectors, using
    lcs-interp.py           a small interpreter for the LiveCodeScript subset the encoders use.
    coin_reference.py       TEST TOOLING, not shipped: an independent implementation of the
                            phase-3 encodings, validated against the published vectors first so
                            it can serve as the oracle the script is checked against
  examples/                 (later phases)
    coinxt-demo.livecodescript    keygen, addresses, sign/verify, an HD wallet from a mnemonic
    coinxt-tests.livecodescript   a pure, offline self-test harness (sPass/sFail, KATs)
```

## The gates (run before any commit)

```sh
python3 tools/check-livecodescript.py         # static gate for the script layer
python3 tools/check-docs-style.py             # house-style gate for the docs
python3 tools/coin-kat.py --check             # builds the shim, runs the known-answer vectors
python3 tools/check-selftest-vectors.py       # the self-test's vectors have not drifted
python3 tools/check-script-vectors.py         # the SCRIPT encoders reproduce the published vectors
python3 tools/check-binary-freshness.py       # the committed library still matches the shim
sh native/build.sh asan                       # ASan + UBSan native self-test
( cd native && sha256sum -c MANIFEST.sha256 ) # vendored-source integrity
( cd src/code && sha256sum -c MANIFEST.sha256 ) # committed-binary integrity
```

All nine run in CI (`.github/workflows/ci.yml`), and the same set runs in the monorepo's
`suite-gates.yml` via `tools/build-all.sh --gates`. OXT cannot COMPILE or LOAD a `.livecodescript`
or a `.lcb` headlessly, so a script change still needs an on-engine pass for parser behaviour - but
the phase-3 encoders' LOGIC is executed headlessly by `check-script-vectors.py`, so "never run" is
no longer the state they ship in. The honest
status until then is "designed and statically reasoned" (see [CLAUDE.md](CLAUDE.md)).

## Status

**Phase 1 is CLOSED, by an engine pass on 2026-08-08.** The native seam was already proven headless:
the shim (`native/coinxt.c`) over the vendored trezor-crypto units builds under ASan + UBSan, exposes
`cnx_keccak256` / `cnx_sha3_256` (the Ethereum-vs-NIST footgun handled), and passes known-answer
vectors via `tools/coin-kat.py`. What was missing was the binding, and on 2026-08-08 the suite selftest
loaded `src/coinxt.lcb` on a real OXT engine and got the pinned hash vectors back byte-exact. Two
design bets settled in that one run: `UIntSize` works as a foreign RETURN type (novel in this family,
which had only ever proven it as a parameter), and `MCDataGetBytePtr` marshals an empty `Data`, so
hashing `""` returns a digest instead of throwing. Neither documented fallback was needed.

That run called 4 of the 16 public handlers, because CoinXT had no self-building harness to drive the
rest. It has one now: paste `tests/coin-selftest.livecodescript` into a stack script and it exercises
all of them, including the SHA3-vs-Keccak aliasing trap and the fail-closed guards.

**Phase 2, the secp256k1 curve, is BUILT and its native side is cross-verified** (ABI 3; 31 public
`cx*` handlers now). `cxNewSeckey`, `cxSeckeyIsValid`, `cxPublicKey`, `cxPubkeyDecompress`, `cxSign`,
`cxVerify`, `cxSignRecoverable`, `cxRecover` and `cxEcdh` exist, with six length accessors. The
phase's bar was "a signature CoinXT makes verifies in an independent library, and `cxRecover` returns
the signing pubkey", and both hold on every push: CoinXT reproduces four published RFC 6979 secp256k1
signatures byte for byte, its signature verifies in the independent Python `ecdsa` library, a
signature that library made verifies in CoinXT, and recovery round-trips to the signer.

**The fifteen curve handlers ran on-engine on 2026-08-10** (the member harness, folded into the suite
selftest at the repository root), and both marshalling shapes that were new to this binding answered
on the side the code assumed: the C `int` flag marshals (the compressed and uncompressed `cxPublicKey`
calls returned 33 and 65 bytes, distinct), and `Boolean` returns work (`cxVerify` answered true for a
good signature and false for a tampered one). Private key 1 gave the generator G, the published
RFC 6979 signature reproduced byte for byte, and `cxRecover` returned the signing key.

Schnorr / BIP-340 is deferred to a Taproot phase: trezor-crypto's plain-C tree does not implement it,
reaching Schnorr only through the bundled `secp256k1-zkp`.

**Phase 3, encodings and addresses, is BUILT** and adds 19 public handlers in
`src/coinxt.livecodescript`: hex, Base58Check, bech32/bech32m, SegWit addresses, `cxHash160` /
`cxHash256`, the four address builders (P2PKH, P2WPKH, P2TR, Ethereum + EIP-55) and RLP. No shim
change. The private key 1 now maps all the way to `1BgGZ9tc...`, `bc1qw508d6...`, `bc1p0xlxvl...` and
`0x7E5F4552...`, and the two SegWit answers are not CoinXT's expectations but **BIP-173's and
BIP-350's own example addresses**.

That layer is a SCRIPT, not part of the `.lcb`: load it into the message path
(`start using stack "coinxt"`) the way OnionXT ships its `ox*` surface.

**It has also been executed**, which is new for a pure-script layer in this family.
`tools/check-script-vectors.py` runs the real file through a small LiveCodeScript interpreter
(`tools/lcs-interp.py`) against the published BIP-173, BIP-350, EIP-55, RLP and Base58Check vectors,
with the hashes coming from the real shim, in the gate set, on every push. That settles the LOGIC.
Engine parser behaviour got its OXT pass on 2026-08-10 - and earned its keep: the one red line of
that run was a parser-counting difference no gate had modelled (`cxHdDerivePath` of `"m/"` returned
the node unchanged, because the engine counts one trailing delimiter out of existence), fixed,
re-modelled in the interpreter, and confirmed green in the same-day re-run.

**Phase 4, HD wallets and mnemonics, is BUILT** (ABI 4) and adds eleven more script handlers:
`cxMnemonicFromEntropy` / `cxMnemonicToEntropy` / `cxMnemonicValidate` / `cxMnemonicToSeed` /
`cxMnemonicNormalize` for BIP-39, and `cxHdFromSeed` / `cxHdDeriveChild` / `cxHdDerivePath` /
`cxHdNeuter` / `cxXprv` / `cxXpub` for BIP-32. The shim gained only what is genuinely curve
arithmetic - `cnx_seckey_tweak_add`, `cnx_pubkey_tweak_add` - plus the normative BIP-39 wordlist as
data; upstream's `bip32.c` was deliberately not vendored, because it is written against every curve
trezor supports and would have dragged in ed25519, nist256p1 and the Cardano variants for two
operations.

The phase's bar was "the official BIP-39 mnemonic + a BIP-44 path reproduce the reference address,
byte for byte", and it is met headlessly on every push: 14 official BIP-39 entropy vectors round-trip
and produce their published seeds, BIP-32 test vectors 1-3 reproduce their published xprv and xpub
strings, and the test mnemonic every wallet ships with walks down `m/44'/0'/0'/0/0`,
`m/84'/0'/0'/0/0` and `m/44'/60'/0'/0/0` to `1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA`,
`bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu` and `0x9858EfFD232B4033E47d90003D41EC34EcaEda94`. The
vector gate is now 170 checks.

**That engine pass has happened: phases 2, 3 and 4 are CLOSED, 2026-08-10.** The member harness ran
folded into the suite selftest - 205/206 on the first pass (the trailing-separator fail-open above),
then **207/207** on the same-day re-run with the fix and the script layer embedded in the paste. All
65 public `cx*` handlers (35 in the `.lcb`, 30 in the script layer) had by then executed on a real
engine against the published vectors. Phase 5 (2026-08-11) added 13 more, for **78** total, and the
2026-08-12 engine pass (230/230, Windows x64) closed them too: every public handler has now run green
on a real engine.

**Phase 5, transaction building and signing, is BUILT** (2026-08-11) and adds 13 script handlers, so
the surface is now **78** public handlers (35 in the `.lcb`, 43 in the script layer). It composes the
primitives into Bitcoin (legacy SIGHASH_ALL + BIP-143 SegWit) and Ethereum (EIP-155 legacy + EIP-1559
typed) sighashes, signing and serialization. The reference model `tools/coin_reference.py` reproduces
the BIP-143 native-P2WPKH worked example byte for byte (a two-input transaction that exercises both
sighash algorithms and its witness), the EIP-155 specification example, and a self-consistent EIP-1559
transaction; `tools/check-selftest-vectors.py` re-derives every phase-5 harness constant from it. Since
2026-08-11 all thirteen handlers are also **executed headlessly**: `tools/check-script-vectors.py` drives
them through the real `.livecodescript` against those vectors (251 checks, the encoders fed the oracle's
own deterministic signatures), the same net phases 3-4 carry. It caught a defect the static gates could
not - `cxBtcTxEncode` refused to assemble the reference transaction because its trailing-empty scriptSig
collapses under the engine's one-trailing-delimiter chunk rule (fixed and pinned). The **on-engine pass
landed 2026-08-12** (Windows x64): the folded suite harness ran the whole coinxt surface at 230/230,
the BIP-143 signed transaction byte for byte included. The one open bar is external: no transaction
should be called broadcastable until an independent decoder or testnet node accepts it.
Schnorr/BIP-340 stays deferred with Taproot (trezor-crypto's plain-C tree has no BIP-340).

[SPEC.md](SPEC.md), [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md), and [CLAUDE.md](CLAUDE.md) are the
design and the running as-built log. Every deterministic path is pinned to a public known-answer vector,
and the "done" bar for a signing feature is that a CoinXT signature verifies in a mainstream external
library, not just in CoinXT.

CoinXT is a self-contained member: it does not depend on OnionXT (the two compose at the documentation
level only), and everything it needs (the static gates, the CI workflow, the portable engine-lesson
book, the vendored sources and their manifest) lives inside this directory. The **xtalk-suite monorepo
is now the source of truth** (see the root `CLAUDE.md`): development happens here and the former
standalone repositories are mirrors. CoinXT remains structured so it *could* be split out again if
ever needed - the procedure is retained in [MIGRATION.md](MIGRATION.md) as history - but that is not
the current plan.

## A note on handling money

CoinXT deals with private keys and real funds, so the family's "compose an audited library, never
hand-roll crypto" rule counts double: the curve and hashes are trezor-crypto's, the app owns custody and
confirm-before-sign, and every checksum is verified on decode with a fail-closed error. See the security
model in [SPEC.md](SPEC.md) section 8 and the rules in [CLAUDE.md](CLAUDE.md).

## House style

ASCII only in `.livecodescript` / `.lcb`. No em-dashes anywhere (hyphens, commas, colons,
parentheses). Comment the *why*, densely. Enforced by the carried `check-livecodescript.py` and
`check-docs-style.py` gates.
