# CoinXT

**Bitcoin and Ethereum cryptography for OpenXTalk (OXT) / the xTalk family.**

CoinXT gives an xTalk app the primitives a wallet or a dapp client is built from, by wrapping
**trezor-crypto** (the MIT-licensed, dependency-free C crypto core of the Trezor hardware wallet) and
**bitcoin-core/secp256k1** (upstream libsecp256k1, MIT, pinned at `439278a6`) behind a thin C ABI and a
livecodescript API. One wrap covers both chains:

- **secp256k1** keypairs, ECDSA (RFC 6979 deterministic), **recoverable** signatures and public-key
  recovery (Ethereum's `v` / `ecrecover`), ECDH, point addition, **BIP-340 Schnorr** and the **BIP-341
  Taproot** tweak, sighash and script-path helpers.
- **Hashes** both chains need: SHA-256/512, SHA3-256, **Keccak-256** (Ethereum's non-NIST padding),
  RIPEMD-160, plus HMAC and PBKDF2-HMAC-SHA512. SHA3-512 is **deferred**: `cxSha3_512` is a
  `handler not found` (the decision and the condition for revisiting it are in SPEC.md section 1).
- **HD wallets:** BIP-32 derivation and BIP-39 mnemonics. SLIP-39 is not planned (the suite's decision
  D-15: revisit only with a named consumer).
- **Address and serialization formats:** Base58Check, Bech32 / Bech32m, hex, RLP, xprv/xpub, WIF
  (fail-closed decode, mainnet and testnet, the 0x01 compressed marker), and the EIP-55 checksum.
- **Transactions:** Bitcoin legacy, BIP-143 SegWit and BIP-341 Taproot sighashes and serialization;
  Ethereum EIP-155 and EIP-1559.

```
app (livecodescript)
   |
CoinXT (cx*)   src/coinxt.livecodescript
   |- encodings in SCRIPT   hex, Base58Check, Bech32/Bech32m, RLP, WIF, addresses, HD framing, tx builders
   |- FFI seam              one .lcb module (src/coinxt.lcb)
CoinXT C shim (cnx_)   native/coinxt.c  +  vendored trezor-crypto (MIT, no external deps)
                                        +  vendored libsecp256k1 (MIT), for BIP-340 / BIP-341 / point sums
   |- curve + hashes in C   secp256k1, SHA2/SHA3/Keccak-256/RIPEMD-160, HMAC, PBKDF2, the BIP-32 tweaks,
                            the BIP-39 wordlist, Schnorr, x-only keys, the Taproot tweak
```

## What CoinXT is NOT

- **Not a wallet, node, or broadcaster.** It produces keys, addresses, and signed bytes. The app owns key
  storage, backup, the confirm-before-sign UX, and putting a signed transaction on the wire (optionally
  through Tor via OnionXT, a documentation-level composition).
- **Not new cryptography.** Every curve op and hash is upstream, audited code. CoinXT adds no cipher of
  its own, the same rule SodiumXT and OnionXT hold.
- **Not hardware-wallet isolation.** It runs in a general-purpose OXT process; script variables are not
  locked memory. It is a strong, correct, self-contained crypto layer, not a secure element.

## Why trezor-crypto, and why a second library beside it

trezor-crypto is MIT-licensed plain C with no external dependencies, and it is the crypto core of a
shipping hardware wallet: exactly the self-contained, buffer-in / buffer-out library the family's FFI
pattern wants. CoinXT vendors a subset of its files plus a small shim, with no autotools and no submodule.
Its plain-C tree has no BIP-340, so since 2026-08-16 CoinXT also vendors upstream libsecp256k1 (three
translation units, one `cc`, no second build system) for BIP-340 Schnorr, x-only keys, the BIP-341 tweak
and point addition, and nothing else; the two libraries do not overlap. The rule change is SPEC.md
section 2.1; the pins, the file lists and the table-size decision are `native/vendor/VENDOR.md`.

## Install and verify

1. Install the packaged **coinxt** extension (`org.openxtalk.library.coin`) through the Extension
   Manager. The native library for your platform resolves from inside it.
2. Put the **script layer** in the message path: the encoders, addresses, HD wallet and transaction
   builders are `src/coinxt.livecodescript`, a script, and load separately with
   `start using stack "coinxt"`.
3. From the message box, `put cxKeccak256Len()` prints 32 (extension loaded) and
   `put cxHexEncode(numToByte(0))` prints 00 (script layer loaded). A `handler not found` on the second
   means step 2 was skipped.

## Documentation

| Document | What it is |
|---|---|
| [docs/getting-started.md](docs/getting-started.md) | From zero: install, verify, run the demo, the same path as code, and the honesty rules to build into an app. Read first. |
| [docs/api-reference.md](docs/api-reference.md) | Every shipped `cx*` handler (95), its contract, refusals and errors. `tools/check-doc-handlers.py` holds it complete in both directions; it also ships inside the packaged extension. |
| [docs/wallet.md](docs/wallet.md) | The CoinXT Wallet (`examples/coin-wallet.livecodescript`) and its pure engine (`examples/wallet-core.livecodescript`): features, backends, proof layers, engine evidence, the `cw*` API. |
| [docs/bitcoin-core-plan.md](docs/bitcoin-core-plan.md) | The Bitcoin Core backend's design: versions and ports, the two channels, the tiers, what is out of scope and why, and the risks only a real node can settle. |
| [SPEC.md](SPEC.md) | The design authority: the C/script split, determinism, the `cnx_` ABI contract and native surface, the byte-exact formats, the security model. |
| [CLAUDE.md](CLAUDE.md) | Maintainer memory: the rules, the traps, and the dated engine evidence ledger. |
| [templates/CLAUDE.md](templates/CLAUDE.md) | The portable xTalk / LiveCode / LCB lesson book, for any new xTalk project. |
| [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) | The per-file license map for the vendored code. |

The root-level documents stay at the root because tools read them by path: `tools/check-doc-handlers.py`
scans `README.md`, `SPEC.md`, `CLAUDE.md` and `templates/CLAUDE.md` (plus every `docs/*.md`), and
`tools/package-extension.py` stages `LICENSE`, `THIRD-PARTY-LICENSES.md` and `docs/api-reference.md`
into the package. Suite-wide documents are indexed at
https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/README.md.

## Layout

```
coinxt/
  README.md  SPEC.md  CLAUDE.md  LICENSE  THIRD-PARTY-LICENSES.md
  templates/CLAUDE.md       the portable lesson book (byte-identical to onionxt's copy)
  .github/workflows/        gates.yml and native.yml, GENERATED from the suite's root lanes
  native/
    coinxt.c                the C shim (the cnx_ ABI over the vendored crypto)
    build.sh                the shared library, `pack` for the shipped one, `asan` for the self-test
    MANIFEST.sha256         pins the 104 files under vendor/ (sources, the BIP-39 wordlist,
                            VENDOR.md and the two licenses)
    vendor/                 the trezor-crypto subset + VENDOR.md + LICENSE
      libsecp256k1/         the bitcoin-core/secp256k1 subset + COPYING
  src/
    coinxt.lcb              the foreign-handler module: all 44 cnx_ exports, ABI 7
    coinxt.livecodescript   the script layer: 51 handlers (encodings, addresses, WIF, mnemonics,
                            HD, transaction builders, Taproot sighash and script-path helpers)
    coinxt.map              the export list the shipped library is narrowed to
    code/                   five committed libraries (x86_64-linux, x86-linux, x86_64-win32,
                            x86-win32, universal-mac) pinned by src/code/MANIFEST.sha256
  tests/
    coin-selftest.livecodescript   the OXT harness: builds its own UI, drives all 95 handlers
    bip352-sending-vectors.json, bip352-receiving-vectors.json, bolt11-vectors.json
  examples/
    coinxt-demo.livecodescript     mnemonic -> addresses -> sign/verify -> a decoded, signed
                                   BTC and ETH transaction
    wallet-core.livecodescript     the wallet engine (prefix cw): pure functions, no state, no I/O
    coin-wallet.livecodescript     the wallet: 13 screens, 8 backend choices (docs/wallet.md)
  tools/
    run-gates.sh            THE gate list, in order (CI and the suite run this script)
    coin-kat.py             known-answer vectors: builds the shim, drives it via ctypes
    check-script-vectors.py + lcs-interp.py + coin_reference.py
                            the script layer, EXECUTED against published vectors and an oracle
    check-wallet-vectors.py + wallet_reference.py
                            wallet-core against its oracle, twice (the second time with `is` /
                            `offset()` folded to the engine's case-insensitive rule)
    check-wallet-boot.py + test-wallet-boot.py
                            BOOTS coin-wallet headlessly over riptide's engine model; fixtures
    check-selftest-vectors.py, check-wallet-ui-version.py, check-doc-handlers.py,
    check-binary-freshness.py, check-livecodescript.py, check-docs-style.py
                            drift, fingerprint, docs-vs-handlers, binary and style gates
    package-extension.py    stage the extension, refresh the manifest, install a library
    verify-independent-decoder.py  manual acceptance in python-bitcointx and eth-account
    mac-cross-cc.sh         a `cc` for cross-building the mac slices on Linux (Zig + ld64.lld)
```

## The gates

```sh
bash tools/run-gates.sh
```

That script is the gate list: CI (`.github/workflows/gates.yml`) and the suite's `tools/build-all.sh`
both run it, so they cannot disagree about what this member's gates are. `coin-kat.py` needs a C
compiler; the three wallet gates take hours. The suite-only gates are listed in the generated section at
the end of this file. OXT cannot compile or load a `.livecodescript` or a `.lcb` headlessly, so the
script logic is EXECUTED by `check-script-vectors.py`, `check-wallet-vectors.py` and
`check-wallet-boot.py`, and parser behaviour still needs an engine pass.

## Status

The dated records are in [CLAUDE.md](CLAUDE.md), "As-built notes"; this is the summary.

- **Engine passes of the library:** 2026-08-08 (phase 1, the hash surface); 2026-08-10 (phases 2-4,
  207/207); 2026-08-12 (phase 5, 230/230, Windows x64); 2026-08-17 (WIF, ABI 5 and the ABI 6
  BIP-340 / BIP-341 surface, 278/278, Windows x86_64, OXT 9.6.3); 2026-08-24 (the BIP-341 sighash and
  script-path handlers, 290/290, Windows x86_64, OXT 9.6.3); 2026-09-24 (ABI 7, 296/296, the suite
  paste on Windows); 2026-09-25 (296/296 again, the suite paste on Linux x86_64 and on Windows x86_64).
  Every handler (95 of 95) has now run green on an engine.
- **ABI 7, `cxPubkeyCombine` (2026-09-10):** ran green on an engine on 2026-09-24 (the suite paste on
  Windows: its six checks), on the 2026-09-12 DLL (release run 34657390798), that build's first engine
  load, and on 2026-09-25 on the same release's `x86_64-linux` library (the maintainer's account:
  64-bit Kubuntu 24.04, the latest committed builds), its first engine load, and on Windows again.
  Every Windows run since 2026-09-12 was 64-bit OXT (the maintainer's account, given 2026-09-26), so
  that DLL is the `x86_64-win32` one: the `x86-win32` DLL may still never have executed anywhere, and
  no engine has loaded the `x86-linux` or mac builds.
- **Independent acceptance:** 2026-08-12, and 2026-08-13 for all four transaction families
  (python-bitcointx 1.1.5 and eth-account 0.13.7, 31 checks, a negative control in each).
- **Broadcast:** Bitcoin testnet spends built over the `cx*` sighash and encoder were accepted from the
  wallet on 2026-09-02 (txid `7978bdd2c097c929cae2ab00084d4454b68b1d054a3f2d53fc7b51b70551e4d5`, a legacy
  spend) and 2026-09-03 (`9bab6640f2bbe01f96a95ffdeca3e96881f1819e677348562ef8bf87da6b719a`, and a
  taproot script-path reveal). No native P2WPKH broadcast is recorded, and no EIP-155 or EIP-1559
  transaction has been broadcast.
- **`examples/coinxt-demo.livecodescript`:** verified statically; needs its OXT pass.

Open work is tracked in the suite's docs/WORK-PLAN.md.

## Reference outputs for integration checks

Private key 1 gives `1BgGZ9tcN4rm9KBzDn7KprQz87SZ26SAMH` (P2PKH),
`bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4` (P2WPKH; BIP-173's own example),
`bc1p0xlxvlhemja6c4dqv22uapctqupfhlxm9h8z3k2e72q4k9hcz7vqzk5jj0` (P2TR; BIP-350's own example) and
`0x7E5F4552091A69125d5DfCb7b8C2659029395Bdf`. The test mnemonic `abandon` x 11 + `about` gives
`m/44'/0'/0'/0/0` -> `1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA`, `m/84'/0'/0'/0/0` ->
`bc1qcr8te4kr609gcawutmrza0j4xv80jy8z306fyu` and `m/44'/60'/0'/0/0` ->
`0x9858EfFD232B4033E47d90003D41EC34EcaEda94`. Check your integration against these before real funds.

## Taproot, three rules a caller must know

- **`cxBtcAddressP2TR` does not tweak.** It encodes the OUTPUT key it is given. If you hold an internal
  key, call `cxBtcAddressP2TRFromInternal`; if you are not sure which you hold, you hold an internal key.
- **An empty merkle root is a key-path-only output**, BIP-341's empty byte string, **not 32 zero bytes**.
  The two give different addresses.
- **An empty `pAuxRand` means fresh OS randomness**, never an all-zero aux. Pass 32 bytes to reproduce a
  published vector byte for byte.

## A note on handling money

CoinXT deals with private keys and real funds, so the family's "compose an audited library, never
hand-roll crypto" rule counts double: the curve and hashes are upstream's, the app owns custody and
confirm-before-sign, and every checksum is verified on decode with a fail-closed error. See the security
model in [SPEC.md](SPEC.md) section 8 and the rules in [CLAUDE.md](CLAUDE.md).

## House style

ASCII only in `.livecodescript` / `.lcb`. No em-dashes anywhere (hyphens, commas, colons,
parentheses). Comment the *why*, densely. Enforced by the carried `check-livecodescript.py` and
`check-docs-style.py` gates.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

CoinXT is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`coinxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/CoinXT: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `coinxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port coinxt --ref pull/<n>/head`, keeping its
author - but a commit made here directly holds up the next publish until
it has been ported, because publishing never overwrites work it did not
write. The suite's `docs/MEMBER-REPO-SPLIT.md` is the whole workflow.

**Suite-level paths cited from here.** This member's `CLAUDE.md` and
`docs/` cite files that live at the suite root, not in this tree:
`docs/OXT-ENGINE-NOTES.md` (engine behaviour, the authoritative list),
`docs/OXT-PASS-RUNBOOK.md`, `tools/build-all.sh`,
`tests/suite-selftest.livecodescript` and the suite-level `docs/`
index. Read them at `https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/<path>`. A path of the
form `../<member>/...` names a sibling member of the suite; each has its
own repository, listed in `tools/member-registry.py` there.

**Sibling members this member's gates need beside it.** `bash
tools/run-gates.sh` (this member's own gate list, the one CI runs)
reaches into these siblings, found as `../<name>` beside this checkout:

- `../riptide` from https://github.com/SethMorrowSoftware/RipTide - `tools/check-demo-boot.py`, the headless boot runner that `tools/check-wallet-boot.py` REUSES rather than copies.
- `../nostrxt` from https://github.com/SethMorrowSoftware/NostrXT - `tools/lcs-interp.py` and the oracle that riptide's runner loads at import time.

Clone them beside this checkout under exactly those directory names
(and keep this checkout named `coinxt`), or point `XTALK_SIBLINGS` at a
directory holding them (`XTALK_SIBLING_<NAME>` for one). The generated
`.github/workflows/gates.yml` takes them from the suite itself, at the
commit named by this repository's newest `Suite-Commit:` trailer - the
versions the suite's gates ran with this tree - and sets
`XTALK_REQUIRE_SIBLINGS=1` so a missing sibling fails the job rather
than skipping its tier. Nothing the SHIPPED code needs is beside it: a
demo that uses a sibling's library carries its own copy (below).

**Carried copies inside this member, and where their masters are.**
Every runnable stack here is one paste-and-run file, so it carries what
it needs verbatim between marker lines. The masters, and the drift gates
that hold every copy byte-identical to them, live in the suite and do
not travel with this member; refresh a copy from the suite (the marker
lines name the master) rather than editing inside the markers.

- The demo UI kit (`tools/ui-kit.livecodescript`; gate `tools/check-ui-kit-drift.py`) in `examples/coinxt-demo.livecodescript`, `examples/coin-wallet.livecodescript`.
- The boot self-check block (`tools/demo-selfcheck.livecodescript`; gate `tools/check-demo-selfcheck-drift.py`) in `examples/coin-wallet.livecodescript`.
- The self-test harness scaffold (`tools/harness-scaffold.livecodescript`; gate `tools/check-harness-scaffold-drift.py`) in `tests/coin-selftest.livecodescript`.
- Sibling libraries embedded by the suite's `tools/sync-demo-embeds.py` (the copy is the shipped file; the master is the sibling's `src/`):
  - `examples/coin-wallet.livecodescript` carries `onionxt/src/onionxt.livecodescript` from https://github.com/SethMorrowSoftware/OnionXT.
- This member's own library, embedded into its own stacks by the same tool so each is one file to paste: `examples/coin-wallet.livecodescript` carries `src/coinxt.livecodescript`; `examples/coin-wallet.livecodescript` carries `examples/wallet-core.livecodescript`; `examples/coinxt-demo.livecodescript` carries `src/coinxt.livecodescript`; `tests/coin-selftest.livecodescript` carries `src/coinxt.livecodescript`.
- `tools/check-docs-style.py`, `tools/check-livecodescript.py`, `tools/lcs-interp.py`, `templates/CLAUDE.md`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

**What this repository cannot check on its own.** The suite-wide gates -
cross-library name disjointness (`tools/check-cross-library-names.py`),
the carried-copy drift gates above, embed freshness, the cross-member
handler-call and typed-boundary checks (`tools/check-handler-calls.py`,
`tools/check-lcb-call-types.py`), the timer-pin closure, and the suite
paste's coverage ratchet (`tools/check-suite-coverage.py`) - run only in
the suite. `tools/run-gates.sh` here is this member's own list, and the
suite's `tools/build-all.sh` runs that same script, so the two cannot
disagree about what this member's gates are.

<!-- ==== SUITE RELATIONSHIP END ==== -->
