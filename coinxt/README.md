# CoinXT

**Bitcoin and Ethereum cryptography for OpenXTalk (OXT) / the xTalk family.**

CoinXT gives an xTalk app the primitives a wallet or a dapp client is built from, by wrapping
**trezor-crypto** (the MIT-licensed, dependency-free C crypto core of the Trezor hardware wallet) and
**bitcoin-core/secp256k1** (upstream libsecp256k1, MIT) behind a thin C ABI and a livecodescript API.
One wrap covers both chains:

- **secp256k1** keypairs, ECDSA (RFC 6979 deterministic), **recoverable** signatures and public-key
  recovery (Ethereum's `v` / `ecrecover`), ECDH, and - since 2026-08-16 - **BIP-340 Schnorr and the
  BIP-341 Taproot tweak**. All built (see Status).
- **Hashes** both chains need: SHA-256/512, SHA3-256, **Keccak-256** (Ethereum's non-NIST padding),
  RIPEMD-160, plus HMAC and PBKDF2-HMAC-SHA512. (SHA3-**512** is **deferred**, decided 2026-08-17:
  `cxSha3_512` is a `handler not found` and this line no longer offers it. The primitive is compiled
  in - the vendored `sha3.c` has it - but exporting it means an ABI bump and a four-platform binary
  refresh, and no chain, caller or suite member needs it. SPEC.md section 1 carries the full
  decision and the condition for revisiting it.)
- **HD wallets:** BIP-32 derivation, BIP-39 mnemonics (SLIP-39 later).
- **Address and serialization formats:** Base58Check, Bech32 / Bech32m, hex, RLP, xprv/xpub, WIF
  (encode and fail-closed decode, mainnet and testnet, the 0x01 compressed marker), and the EIP-55
  Ethereum checksum. (WIF shipped 2026-08-15; engine-proven 2026-08-17 in coinxt's 278/278 -
  this parenthesis said "needs an OXT pass" for a week after that run, the
  description-rots lesson again.)

```
app (livecodescript)
   |
CoinXT (cx*)   src/coinxt.livecodescript
   |- encodings in SCRIPT   hex, Base58Check, Bech32/Bech32m, RLP, addresses (pure byte work)
   |- FFI seam              one .lcb module
CoinXT C shim (cnx_)   native/coinxt.c  +  vendored trezor-crypto (MIT, no external deps)
                                        +  vendored libsecp256k1 (MIT), for BIP-340 / BIP-341
   |- curve + hashes in C   secp256k1, SHA2/SHA3/Keccak-256/RIPEMD-160, HMAC, PBKDF2, BIP-32, BIP-39,
                            Schnorr, x-only keys, the Taproot tweak
```

> **Documentation:** [`docs/README.md`](docs/README.md) indexes every page for this member, including the ones that live at the member root (SPEC, the plan, MIGRATION) so you do not have to know which is where.

## What CoinXT is NOT

- **Not a wallet, node, or broadcaster.** It produces keys, addresses, and signed bytes. The app owns key
  storage, backup, the confirm-before-sign UX, and putting a signed transaction on the wire (optionally
  through Tor via OnionXT, a documentation-level composition).
- **Not new cryptography.** Every curve op and hash is upstream, audited code. CoinXT adds no cipher of
  its own, the same rule SodiumXT and OnionXT hold. (That rule used to name ONE upstream. It names two
  since 2026-08-16, and the change is recorded as a decision in SPEC.md section 2.1 rather than edited
  quietly into this sentence: trezor-crypto's plain-C tree has no BIP-340, and hand-rolling a signature
  scheme is exactly what the rule exists to prevent.)
- **Not hardware-wallet isolation.** It runs in a general-purpose OXT process; script variables are not
  locked memory. It is a strong, correct, self-contained crypto layer, not a secure element.

## Why trezor-crypto, and why a second library beside it

MIT-licensed, plain C, **no external dependencies**, and it bundles secp256k1 (also MIT). That is exactly
what the family's FFI pattern wants: a self-contained C library with a buffer-in / buffer-out API and a
permissive license we can vendor and redistribute. It is the crypto core of a shipping hardware wallet,
so the curve and hash code is battle-tested. CoinXT vendors a subset of its `.c` files plus a small shim
and builds one shared library per platform. No autotools, no submodule tree.

**Taproot needed a second one.** trezor-crypto's plain-C tree has no BIP-340 implementation at all - it
reaches Schnorr only through `zkp_bip340.c`, which drags in the whole bundled `secp256k1-zkp` and its
build system. So since 2026-08-16 CoinXT also vendors **upstream bitcoin-core/secp256k1** (MIT, pinned
at `439278a6`), compiled the same way: sources copied verbatim, three translation units, one `cc`, no
second build system. It owns BIP-340 Schnorr, x-only keys and the BIP-341 tweak, and nothing else; the
two libraries do not overlap. The rule change is written down in SPEC.md section 2.1 and the vendoring
(the pin, the 58 files, the table-size decision) in `native/vendor/VENDOR.md`.

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
    MANIFEST.sha256         integrity pins for the vendored sources AND the wordlist (47
                            entries); the four committed release binaries are pinned by
                            src/code/MANIFEST.sha256
    vendor/                 the vendored trezor-crypto subset (MIT) + VENDOR.md + LICENSE.
      libsecp256k1/         the vendored bitcoin-core/secp256k1 subset (MIT) + COPYING.
                            The curve half is a CLOSURE, not a pick-list: see VENDOR.md for
                            why hasher.c, blake, groestl, base58.c and address.c are in it
  docs/
    README.md               the index for every page of this member, the root ones included
    getting-started.md      from zero: install, verify, run the demo, the same path as code,
                            and the honesty caveats to build into your app
    api-reference.md        the cx* handlers that EXIST today (contrast SPEC.md, which describes
                            the whole designed API including phases not yet built)
  src/
    coinxt.lcb              the foreign-handler module (binds to all 43 cnx_* exports, ABI 6);
                            engine-proven end to end: phase 1 closed 2026-08-08, phases 2-4
                            closed 2026-08-10 (the folded harness, 207/207 on the re-run)
    coinxt.livecodescript   the phase-3 script layer: hex, Base58Check, bech32/bech32m, RLP
                            and the address builders. NOT part of the .lcb - it loads into the
                            message path (`start using stack "coinxt"`)
  tests/
    coin-selftest.livecodescript  the OXT runtime harness: paste into a stack script, it builds
                            its own UI and drives ALL 94 public cx* handlers against the
                            published vectors (43 from the .lcb, 51 from the script layer);
                            the suite's tools/check-suite-coverage.py is what reads 94/94
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
    check-wallet-vectors.py the same machinery one layer up: runs the SHIPPED wallet engine
                            (examples/wallet-core.livecodescript) against wallet_reference.py
                            with the real shim signing - complete signed transactions on all
                            five spend paths - and then RUNS THE WHOLE SET AGAIN with `is` and
                            `offset()` folded to the engine's own case-insensitive default,
                            requiring the same answers
    check-wallet-boot.py    one layer up again: BOOTS examples/coin-wallet.livecodescript
                            headlessly over riptide's engine object model (imported, not
                            copied) with the COMMITTED coinxt.so under it - the card builders,
                            the show/hide sweep, the click router, a signed spend, a PSBT
                            round trip and the sealed wallet file. No compiler needed
    wallet_reference.py     TEST TOOLING: the wallet layer's oracle. Extends coin_reference.py
                            and anchors itself at import to the BIP-44/49/84/86 addresses,
                            BIP-49/84's account ypub and zpub, Core's descriptor checksums,
                            the 226/141 vsizes, the 546/540/330/294 dust thresholds and two
                            golden QR matrices from an independent encoder
  examples/
    coinxt-demo.livecodescript    the phase-6 demo: mnemonic -> accounts -> addresses ->
                                  sign/verify -> a decoded, signed BTC + ETH transaction
                                  (verified statically; needs its OXT pass). The offline
                                  self-test role this tree once planned for examples/ is
                                  filled by tests/coin-selftest.livecodescript
    wallet-core.livecodescript    the WALLET ENGINE: a pure calculator layer (prefix cw) over
                                  CoinXT. Scripts and addresses for all five standard output
                                  types, SLIP-132 extended keys, exact satoshi arithmetic,
                                  worst-case vsize and fees, four coin-selection strategies,
                                  sighash dispatch and witness shapes, BIP-174 PSBT, signed
                                  messages, BIP-21, output descriptors, transaction decoding,
                                  JSON and QR. No state, no `item`/`line` chunks, no UI and no
                                  I/O - which is what lets check-wallet-vectors.py run it
    coin-wallet.livecodescript    the WALLET: ten screens over that engine in one paste-and-run
                                  stack (carries coinxt, the engine and onionxt). Seeds,
                                  watch-only, imported keys, multisig and taproot; coin control,
                                  RBF, PSBT cosigning, signed messages, descriptors, QR codes,
                                  and Esplora or Electrum over Tor. See docs/wallet.md
```

## The gates (run before any commit)

```sh
python3 tools/check-livecodescript.py         # static gate for the script layer
python3 tools/check-docs-style.py             # house-style gate for the docs
python3 tools/coin-kat.py --check             # builds the shim, runs the known-answer vectors
python3 tools/check-selftest-vectors.py       # the self-test's vectors have not drifted
python3 tools/check-script-vectors.py         # the SCRIPT encoders reproduce the published vectors
python3 tools/check-wallet-vectors.py         # the SHIPPED wallet engine, against its own oracle,
                                              #   twice: once as written, once with the engine's
                                              #   case-insensitive `is`/`offset()`
python3 tools/check-wallet-boot.py            # the SHIPPED wallet stack, BOOTED headlessly
python3 tools/check-binary-freshness.py       # the committed library still matches the shim
sh native/build.sh asan                       # ASan + UBSan native self-test
( cd native && sha256sum -c MANIFEST.sha256 ) # vendored-source integrity
( cd src/code && sha256sum -c MANIFEST.sha256 ) # committed-binary integrity
```

The monorepo's `suite-gates.yml`, via `tools/build-all.sh --gates`, runs every one of them plus
`python3 tools/check-doc-handlers.py --check` (the docs-vs-shipped-handler-set gate). The member's
own `.github/workflows/ci.yml` carries a SUBSET - it predates the two wallet gates and does not run
them - so this list going green locally is the thing to trust, and the member workflow going green
is not by itself proof that the suite gates will. OXT cannot COMPILE or LOAD a
`.livecodescript` or a `.lcb` headlessly, so a script change still needs an on-engine pass for parser
behaviour - but the phase-3 encoders' LOGIC is executed headlessly by `check-script-vectors.py`,
the wallet engine's by `check-wallet-vectors.py`, and the wallet STACK's whole openStack chain by
`check-wallet-boot.py`, so "never run" is no longer the state any of the three ship in. The honest status until then is "designed and statically reasoned" (see [CLAUDE.md](CLAUDE.md)).

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

Schnorr / BIP-340 WAS deferred here for exactly that reason. It shipped at ABI 6 on 2026-08-16 over a
second vendored library; see the ABI 6 entry at the end of this section.

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
engine against the published vectors. Phase 5 (2026-08-11) added 13 more, for 78, and the
2026-08-12 engine pass (230/230, Windows x64) closed them too - and the **2026-08-17 pass took
coinxt to 278/278 on a real engine**, closing the WIF, `cnx_memzero`, Schnorr/BIP-340 and
BIP-341 Taproot surfaces that had shipped since. Every public handler has now run green on an
engine. The one bar left before "broadcastable" is unchanged: a live testnet broadcast.

**Phase 5, transaction building and signing, is BUILT** (2026-08-11) and adds 13 script handlers,
which brought the surface to 78 public handlers (35 in the `.lcb`, 43 in the script layer; 80 and
45 since WIF, below). It composes the
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
the BIP-143 signed transaction byte for byte included. The first half of the external bar is met too
(2026-08-12, extended 2026-08-13 to all four families): `tools/verify-independent-decoder.py` has
python-bitcointx accept fresh legacy and segwit spends under consensus rules, and eth-account recover
the exact sender from fresh EIP-155 and EIP-1559 transactions, negative controls firing in every
family. A live testnet broadcast is the one bar left before any transaction is called broadcastable.
Schnorr/BIP-340 shipped at ABI 6 (below).

**ABI 6, BIP-340 Schnorr and the BIP-341 Taproot tweak, is SHIPPED (2026-08-16).** The shim gains
eight exports (43 now) over a SECOND vendored library, upstream bitcoin-core/secp256k1:
`cnx_schnorr_sign` / `cnx_schnorr_verify`, `cnx_xonly_pubkey_from_seckey`,
`cnx_taproot_tweak_pubkey` / `cnx_taproot_tweak_seckey` and three length accessors. `src/coinxt.lcb`
wraps all of them (`cxSchnorrSign`, `cxSchnorrVerify`, `cxXOnlyPubkey`, `cxTaprootTweakPubkey`,
`cxTaprootTweakSeckey`, `cxSchnorrSignatureLen`, `cxXOnlyPubkeyLen`, `cxTaprootOutputLen`) and the
script layer adds `cxTaprootTweak` (the same tweak as a named array) and
**`cxBtcAddressP2TRFromInternal`**, which is the P2TR address builder that actually tweaks. The
surface was 90 public handlers at that ship (43 `.lcb` + 47 script; 94 since the 2026-08-23
script-layer BIP-341 handlers below).

Three things a caller should know before using it:

- **`cxBtcAddressP2TR` is unchanged and stays unchanged.** It encodes the output key it is given and
  does not tweak, exactly as before. If you hold an INTERNAL key, call
  `cxBtcAddressP2TRFromInternal`; if you are not sure which you hold, you hold an internal key.
  Making the old handler tweak would have turned every existing correct call into a double tweak -
  a valid-looking address nobody can spend from - with no way to tell the two cases apart, so the
  two are separate handlers.
- **An empty merkle root is a key-path-only output** (the single-signature case), and that is
  BIP-341's empty byte string, **not 32 zero bytes**. The two produce different addresses. The
  distinction is carried by length all the way down to the C, so there is no sentinel to get wrong.
- **An empty `pAuxRand` means "draw fresh OS randomness"**, never an all-zero aux, so
  `cxSchnorrSign` returns a different (equally valid) signature each time. Pass 32 bytes to
  reproduce a published vector byte for byte.

The two gaps that paragraph used to name here CLOSED on 2026-08-23, as pure script over this
surface (94 public handlers now: 43 `.lcb` + 51 script): **`cxBtcSighashTaproot`** is the BIP-341
`SigMsg` builder - the full type set, SIGHASH_DEFAULT through the three ANYONECANPAY forms, plus
the tapleaf extension for script-path signing - and **`cxTapLeafHash` / `cxTapBranchHash` /
`cxTapControlBlock`** are the script-path byte work (the branch sort lives inside the handler; the
tree SHAPE above one fold stays the app's loop). Pinned headlessly to the published bitcoin/bips
wallet vectors - all seven keyPathSpending sighashes, all six script trees, every control block -
by driving the real script through `tools/check-script-vectors.py`; no OP_CODESEPARATOR, no annex;
**ENGINE-PROVEN 2026-08-24** (Windows x86_64, OXT 9.6.3: all 12 BIP-341 checks green in coinxt's
290/290 - leaf hashes including the 0xfa version, the sorted branch fold, the control block,
both sighash paths and every refusal).

Correctness: **all 19 of BIP-340's official test vectors run, ten of them NEGATIVE** (a public key
off the curve, has_even_y(R) false, a negated message, a negated s, two infinity cases, and the
field-size / group-order edges), plus all 7 BIP-341 `scriptPubKey` vectors and all 7
`keyPathSpending` inputs walked private key -> internal key -> tweaked key -> the published witness
signature. `native/build.sh asan` is clean over the new code. The `.lcb` and script layers are
**ENGINE-PROVEN 2026-08-17** (Windows x86_64, OXT 9.6.3): all 19 published BIP-340 vectors
including the 10 negatives, and the BIP-341 wallet vectors, ran green as part of coinxt's 278/278.

**ABI 5, the recorded secret-hygiene fix, is SHIPPED (2026-08-16).** The shim gains one
export, `cnx_memzero(ptr, len)` - a wrap of the vendored trezor-crypto `memzero.c`
(SecureZeroMemory / memset_s / explicit_bzero / a volatile loop, per platform; no wiping
technique of our own) - and `src/coinxt.lcb` now wipes every raw out-buffer through it
before freeing: the PBKDF2 seed path its header had recorded as the known gap, plus the
other secret outputs the audit named (the BIP-32 HMAC-SHA512 block, the tweaked child
private key, the ECDH point) and, unconditionally, every non-secret output too. No new
public handler; the surface stays 80 (35 in the `.lcb`, 45 in the script layer), and the
export is deliberately not script-visible - a script `Data` cannot be wiped in place, and
that honest limit stands documented rather than papered over. The wipe contract is
EXECUTED by the native gates on Linux (the ASan/UBSan self-test and `coin-kat.py`, which
also drives the committed x86_64 library); the `.lcb` call sites are verified statically
and need an OXT pass; the two Windows DLLs are MinGW cross-builds carrying the
sodiumxt-precedent static checks (export parity, ABI-in-disassembly, clean imports) and
need their Windows execution proof - the next `release-binaries.yml` dispatch supersedes
them with `kat-windows`-proven builds (see CLAUDE.md for the recorded deviation).

**WIF, the last designed encoding, is BUILT (2026-08-15)**: `cxWifEncode` / `cxWifDecode` in the
script layer, no shim change, for **80** public handlers (35 in the `.lcb`, 45 in the script layer).
Standard Wallet Import Format - Base58Check over `version || key || optional 0x01 compressed
marker`, version `0x80` mainnet / `0xEF` testnet - with the fail-closed decode the rest of the
surface holds to: a bad checksum, a wrong payload length, an unknown version byte, a trailing byte
that is not `0x01`, and an out-of-range scalar each throw (both directions range-check through
`cxSeckeyIsValid`, so a checksummed WIF of an unusable key is refused rather than framed). The
vectors are derived by `tools/coin_reference.py` and anchored to the Bitcoin wiki's published
worked example, which `tools/check-script-vectors.py` drives through the shipped script in both
directions plus the refusals, and mutation testing confirmed each refusal vector catches its
defect. **ENGINE-PROVEN 2026-08-17** (coinxt 278/278, Windows x86_64) and reconfirmed in the
2026-08-24 run's 290/290 - this paragraph carried "needs an OXT pass" for a week after the
run that closed it.

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
hand-roll crypto" rule counts double: the curve and hashes are upstream's, the app owns custody and
confirm-before-sign, and every checksum is verified on decode with a fail-closed error. See the security
model in [SPEC.md](SPEC.md) section 8 and the rules in [CLAUDE.md](CLAUDE.md).

## House style

ASCII only in `.livecodescript` / `.lcb`. No em-dashes anywhere (hyphens, commas, colons,
parentheses). Comment the *why*, densely. Enforced by the carried `check-livecodescript.py` and
`check-docs-style.py` gates.
