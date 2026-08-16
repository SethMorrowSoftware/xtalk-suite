# CoinXT - Implementation Plan

The phased build order for CoinXT (see [SPEC.md](SPEC.md) for WHAT, [CLAUDE.md](CLAUDE.md) for the
rules). Each phase has a concrete "done when" bar and states the risk it retires. Build in order: the
native seam and the KAT harness come first, because everything downstream trusts them.

> Status: **phase 0 done, the Schnorr/BIP-340 sourcing pin CLOSED 2026-08-16 (see below); PHASE 1 CLOSED
> 2026-08-08 by an engine pass.** (See the as-built notes in [CLAUDE.md](CLAUDE.md).) The vendored
> SHA-3 / SHA-2 / RIPEMD-160 / HMAC / PBKDF2 units, the `cnx_` shim (ABI 2) with Keccak-256, SHA3-256,
> SHA-256, SHA-512, RIPEMD-160, HMAC-SHA256/512 and PBKDF2-HMAC-SHA512, the ASan + UBSan self-test, and
> the headless KAT harness are in and green. `src/coinxt.lcb`
> (`library org.openxtalk.library.coin`) binds all 16 `cnx_` exports and wraps the whole hash surface as
> `cx*` handlers, with `cxCheckABI()` on ABI 2.
>
> **The phase-1 bar was "`cxKeccak256` and friends return the pinned vectors from a real engine", and on
> 2026-08-08 they did.** `tests/suite-selftest.livecodescript` ran green on a real OXT engine: the
> module loaded and its binds resolved, keccak256 of `""` and of `"abc"` matched their published
> vectors, sha256(`"abc"`) matched FIPS 180-4, ripemd160(`"abc"`) matched its specification vector, and
> `cxSha3_256` was proven distinct from `cxKeccak256`. Two design bets paid off in the same run: the
> novel **`UIntSize` foreign RETURN type works** (the digests are byte-exact, and their buffers are
> sized from it), and **`MCDataGetBytePtr` marshals an empty `Data`** through a plain `Pointer` (hashing
> `""` returned a digest instead of throwing). Neither documented fallback - `CUInt`, `optional Pointer`
> - was needed.
>
> The phase-1 residual - 12 of the 16 public handlers not called by name (`cxCheckABI`, the seven
> `*Len` accessors, `cxSha512`, `cxHmacSha256`, `cxHmacSha512`, `cxPbkdf2HmacSha512`) - was CLOSED
> on 2026-08-10: the member harness, folded into the suite selftest, calls every public handler by
> name, and it ran green on a real engine (207/207 on the same-day re-run). Unlike
> OnionXT (pure script), CoinXT HAS a C shim, so the FFI/C-ABI section of CLAUDE.md is law from phase 1
> onward, and every shim change builds under ASan + UBSan and bumps the ABI + `cxCheckABI()` on any ABI
> change.
>
> **PHASE 2 IS BUILT AND ITS BAR IS MET AT THE C LEVEL (ABI 3).** The bar below is "a signature CoinXT
> makes verifies in an independent library, and `cxRecover` returns the signing pubkey." Both hold, and
> `tools/coin-kat.py` checks them on every push: CoinXT reproduces four published RFC 6979 secp256k1
> signatures byte for byte, its signature verifies in Python `ecdsa`, a signature that library made
> verifies in CoinXT, and recovery round-trips to the signer. ASan + UBSan are clean over the whole
> curve surface. **The engine pass over the fifteen curve `cx*` handlers happened 2026-08-10** (the
> folded harness; both new marshalling shapes - the CInt flag and the Boolean returns - answered on
> the side the code assumed), which closes the phase outright. Two
> phase-0 items are also now settled: the entropy decision was WRONG and is corrected (see CLAUDE.md,
> "Determinism and entropy"), and Schnorr/BIP-340, deferred here because trezor-crypto's plain-C
> tree does not implement it, SHIPPED at ABI 6 on 2026-08-16 over a second vendored library
> (upstream bitcoin-core/secp256k1) - the sourcing question this plan left open, answered. **PHASE 3 IS ALSO BUILT.** `src/coinxt.livecodescript`
> adds 19 public handlers (hex, Base58Check, bech32/bech32m, SegWit addresses, hash160/hash256,
> the four address builders, RLP) with no shim change. Its logic is executed headlessly against the
> published BIP-173 / BIP-350 / EIP-55 / RLP vectors by `tools/check-script-vectors.py`, which runs
> the REAL file through a small LiveCodeScript interpreter - the first time a pure-script layer in
> this family has been executed before an engine saw it. **PHASE 4 IS ALSO BUILT (ABI 4).** Its bar - "the official BIP-39
> mnemonic + a BIP-44 path reproduce the reference address, byte for byte" - is MET headlessly: the
> shim gained `cnx_seckey_tweak_add`, `cnx_pubkey_tweak_add` and the vendored BIP-39 wordlist
> (`cnx_bip39_wordlist` + its length), the script layer gained eleven handlers, and
> `tools/check-script-vectors.py` runs the real file against 14 official BIP-39 vectors, BIP-32 test
> vectors 1-3 and the "abandon ... about" mnemonic down BIP-44/BIP-84/Ethereum paths to the published
> addresses (170 checks, up from 87). **That single engine pass has happened: phases 2, 3 and 4 all
> CLOSED 2026-08-10** - 205/206 on the first folded run (the one red line was the trailing-separator
> fail-open in `cxHdDerivePath`, fixed and re-modelled in the interpreter the same day), then 207/207
> on the re-run with the fixed layer embedded in the paste. Phase 5
> (transaction building) has since landed too: built 2026-08-11, executed headlessly, engine-passed
> 2026-08-12 at 230/230, and independently accepted in all four transaction families 2026-08-13
> (its own section below carries the record). It remains true that it was optional - the primitive
> layer was shippable without it - but "next" it no longer is.

## The "done" bar (applies to every phase)

A change is done when:
1. `tools/check-livecodescript.py` and `tools/check-docs-style.py` pass (carried from OnionXT).
2. The shim builds clean under `gcc/clang -Wall -Wextra -fsanitize=address,undefined` with third-party
   (trezor-crypto) headers treated as system headers (`-isystem`) so their warnings do not pollute ours.
3. The phase's known-answer vectors pass in `tools/coin-kat.py`, cross-checked against an independent
   implementation (Python `ecdsa` / `pycryptodome` / `eth-utils`) BEFORE pinning.
4. It has had (or is clearly flagged as needing) an on-engine pass: load the `.lcb` in a real OXT engine
   and round-trip the phase's `cx*` calls.

No transaction-signing claim is "done" until a signature CoinXT produced verifies in an independent,
mainstream library (not just in CoinXT).

## Phase 0 - Ground truth and decisions (no shipping code)

- **Vendoring**: confirm the exact trezor-crypto `crypto/` files needed (`secp256k1`, `ecdsa.c`,
  `bignum.c`, `hasher.c`, `sha2.c`, `sha3.c`, `ripemd160.c`, `hmac.c`, `pbkdf2.c`, `bip32.c`, `bip39.c`,
  `base58.c`, `segwit_addr.c`, `rand.c` shim, the wordlist), pin the upstream commit, and record its MIT
  `LICENSE` + a `VENDOR.md` noting the commit and any local patches. Decide: vendor a subset vs a git
  subtree of the whole `crypto/` dir.
- **Entropy**: confirm the SPEC decision (caller brings entropy; compose SodiumXT `sxRandomBytes`). Wire
  trezor-crypto's required `random_buffer` / `random32` to abort-if-called, since nothing internal should
  need it once signing is RFC 6979 and keys come from the caller. (A called RNG is then a bug, not a
  silent weak key.)
- **Naming and prefixes**: `cx*` public, `cnx_` C ABI, ABI starts at 1. Confirm no `cx`-stem collision
  with a reserved token.
- **Schnorr / BIP-340**: pin which upstream path provides it (trezor-crypto's own vs the bundled
  secp256k1 module) and whether it ships in phase 2 or is deferred to a Taproot phase.

**Done when:** the file list, the license/vendor record, the entropy model, and the ABI conventions are
written down and agreed. **Risk retired:** building the wrong thing, or a licensing surprise.

## Phase 1 - The native seam: build, hashes, ABI guard

- Vendored subset compiles into one shared library per platform (`.so` / `.dll` / `.dylib`) alongside
  `native/coinxt.c` (the shim). Set up the ASan + UBSan dev build and a release build.
- Implement and export the hash surface (`cnx_sha256/512`, `cnx_sha3_256`, `cnx_keccak256`,
  `cnx_ripemd160`, `cnx_hmac_*`, `cnx_pbkdf2_hmac_sha512`), the length functions, and `cnx_abi_version`.
- Write the `.lcb` module: `use com.livecode.foreign`, the `binds to` declarations, the buffer
  marshalling helper (in-buffer via `MCDataGetBytePtr`; out-buffer via `MCMemoryAllocate`),
  `unsafe ... end unsafe` around every foreign call, `cxCheckABI()`. **As built there is no `-needed`
  re-alloc retry**, and deliberately so: unlike SodiumXT's, this shim returns a status and writes a
  FIXED size it reports itself (`cnx_*_len`), or exactly the PBKDF2 output length asked for, so the
  binding allocates exactly that and copies exactly that back. Nothing hardcodes a size.
- `cx*` wrappers for the hashes; `tools/coin-kat.py` pins `keccak256("")`, `sha3_256("")`, RIPEMD-160,
  HMAC-SHA512, PBKDF2-HMAC-SHA512.

**Done when:** `cxKeccak256` and friends return the pinned vectors from a real engine, ASan/UBSan clean.
**Risk retired:** the whole FFI plumbing (the family's single most expensive area) and the build.

## Phase 2 - Keys and signatures  (CLOSED 2026-08-10 by an engine pass)

- Export and wrap `cnx_seckey_verify`, `cnx_pubkey_from_seckey`, `cnx_pubkey_decompress`,
  `cnx_ecdsa_sign` / `_verify`, `cnx_ecdsa_sign_recoverable` / `cnx_ecdsa_recover`, `cnx_ecdh`. **All
  eight shipped**, with six length accessors.
- `cx*` API: `cxNewSeckey` (validates caller entropy), `cxSeckeyIsValid`, `cxPublicKey`,
  `cxPubkeyDecompress`, `cxSign` / `cxVerify`, `cxSignRecoverable` / `cxRecover`, `cxEcdh`. **All
  shipped**; `cxVerify` and `cxSeckeyIsValid` return Boolean, everything else returns Data.
- **Schnorr / BIP-340 was deferred here, and SHIPPED on 2026-08-16 at ABI 6.** The reason for the
  deferral stands and is what decided the eventual answer: trezor-crypto's plain-C tree has no
  BIP-340 - it reaches Schnorr only via `zkp_bip340.c` on the bundled `secp256k1-zkp`, a far larger
  vendoring. Weighed against P2TR as a whole, the answer was neither of the two this plan imagined:
  **upstream bitcoin-core/secp256k1**, whose in-tree `schnorrsig` and `extrakeys` modules are
  everything BIP-340 and single-key BIP-341 need, vendored as three translation units with no second
  build system. That made a second upstream library part of this project, which is a rule change and
  is recorded as one in SPEC.md section 2.1 and CLAUDE.md.
- Secret hygiene: seckey scratch `memzero`ed in the shim; the `cx*` layer documents clearing key
  variables. KATs: four published RFC 6979 deterministic signatures, the `ecrecover` round-trip, low-`s`
  asserted on every vector (upstream enforces it), ECDH from both sides, and the public-key overread
  guard. The BIP-340 vectors landed with Schnorr on 2026-08-16, and there are nineteen of them, ten
  negative.

**Done when:** a signature CoinXT makes verifies in an independent library, and `cxRecover` returns the
signing pubkey. **MET (2026-08-08)**, headless, on every push: see the status note at the top of this
file. The engine half followed on **2026-08-10**: the folded harness ran all fifteen curve handlers
green on a real engine, so nothing in this phase is "verified statically" any more.
**Risk retired:** the core value proposition (correct, deterministic, recoverable signing on
secp256k1).

## Phase 3 - Encodings and addresses (pure script)  (CLOSED 2026-08-10 by an engine pass)

- Livecodescript, no shim: `cxHexEncode/Decode`, `cxBase58CheckEncode/Decode`,
  `cxBech32Encode/Decode` (Bech32 and Bech32m), `cxRlpEncode/Decode`. Each fails closed on a bad
  checksum / malformed input (the OnionXT base32 discipline: small bit-buffer, byte ops, no `^`/`div`/
  `mod` where a parser chokes).
- Address composition: `cxBtcAddressP2PKH`, `cxBtcAddressP2WPKH`, `cxBtcAddressP2TR`, `cxEthAddress` +
  `cxEthAddressChecksum` (EIP-55).
- KATs: BIP-173 / BIP-350 valid AND invalid vectors, the EIP-55 examples, a P2PKH / P2WPKH / P2TR vector,
  a known-pubkey -> known-eth-address vector.

**Done when:** a pubkey maps to the correct mainnet BTC (all three types) and ETH addresses, and a
corrupt address is rejected. **MET headlessly.** The private key 1 maps to `1BgGZ9tc...` (P2PKH),
`bc1qw508d6...` (P2WPKH) and `bc1p0xlxvl...` (P2TR), and the last two are not CoinXT expectations at
all - they are BIP-173's and BIP-350's OWN example addresses, because hash160(G) is the witness
program in the first and x-only G is the program in the second. Corrupt inputs are rejected across
the board: BIP-173's ten invalid strings, BIP-350's invalid addresses including a v0 address carrying
a bech32m checksum, a corrupt Base58Check tail, and RLP's non-canonical forms.

The **engine pass** happened 2026-08-10, and it is what settled parser behaviour: the encoders all
ran green folded into the suite harness, and the one parser difference the day surfaced was in
phase 4's path walker, not here (`tools/check-script-vectors.py` still settles the LOGIC headlessly
on every push; the interpreter now models the engine's trailing-delimiter counting rule too).
**Risk retired:** the "silently wrong address = lost funds" class, moved into script where it is
diffable and fully KAT-covered - and, unlike previous pure-script layers in this family, actually
executed before shipping.

## Phase 4 - HD wallets and mnemonics  (CLOSED 2026-08-10 by an engine pass)

- Shim: `cnx_hdnode_from_seed`, `cnx_hdnode_derive` (one step), `cnx_hdnode_private_key` / `_public_key`
  / `_chaincode`, `cnx_bip39_seed`.
- Script: `cxHdFromSeed`, `cxHdDerivePath` (parse `m/44'/0'/0'/0/0`, loop the shim per level, handle the
  `'` hardened marker), `cxHdSeckey` / `cxHdPubkey` / `cxHdChainCode`, `cxXprv` / `cxXpub` (Base58Check
  framing in script). BIP-39 entropy<->words + checksum word in script over the shipped wordlist;
  `cxMnemonicFromEntropy`, `cxMnemonicToSeed`, `cxMnemonicValidate`.
- KATs: the official BIP-32 and BIP-39 vectors, end to end (mnemonic -> seed -> node -> derived address).

**Done when:** the official BIP-39 mnemonic + a BIP-44 path reproduce the reference address, byte for
byte. **MET (2026-08-08)**, headless, on every push - and on **2026-08-10** on a real engine: the
folded harness walked the test mnemonic down `m/44'/0'/0'/0/0`, `m/84'/0'/0'/0/0` and
`m/44'/60'/0'/0/0` to the published addresses, green. The engine also found this phase's one real
defect first (the `"m/"` trailing-separator fail-open in the path parse), fixed and confirmed green
the same day. **Risk retired:** wallet interoperability (a CoinXT wallet and any standard wallet
agree on the same key from the same mnemonic).

**As built, three things differ from the sketch above, each deliberately:**

- **The shim exports two curve steps, not five `cnx_hdnode_*` functions.** `cnx_seckey_tweak_add`
  (ki = IL + kpar mod n) and `cnx_pubkey_tweak_add` (Ki = point(IL) + Kpar) are the only parts of
  BIP-32 that ARE curve arithmetic; the HMAC, the serialization and the path parse are byte shuffling
  and live in script by the C-vs-script rule. This also avoided vendoring upstream's `bip32.c`, which
  is written against every curve trezor supports and would have pulled in `curves.c`, `nist256p1`,
  `ed25519-donna` and the Cardano variants.
- **`cnx_bip39_seed` was not needed.** It is PBKDF2-HMAC-SHA512, which phase 1 already exports;
  `cxMnemonicToSeed` composes it. What the shim DOES export is the wordlist
  (`cnx_bip39_wordlist`), as 2048 fixed-width 8-byte slots, so the normative list is vendored
  verbatim rather than transcribed into a script constant.
- **The handler names settled slightly differently**: `cxHdDeriveChild` (one step) and `cxHdNeuter`
  (the watch-only form) exist, and the node is an ARRAY read by name (`["seckey"]`, `["pubkey"]`,
  `["chaincode"]`, `["depth"]`, `["index"]`, `["parentfp"]`) rather than `cxHdSeckey` / `cxHdPubkey`
  / `cxHdChainCode` accessors - the fields are exactly what BIP-32 serializes, in order, so `cxXprv`
  is a concatenation and not a translation.

## Phase 5 - Transaction building and signing (stretch) - BUILT 2026-08-11, ENGINE-PASSED 2026-08-12

- Bitcoin: legacy and SegWit (BIP-143) sighash construction and signing in script (compose `cxSign` +
  the encoders), producing a raw transaction. SHIPPED: `cxBtcSighashLegacy`, `cxBtcSighashSegwit`,
  `cxBtcOutpoint`, `cxBtcOutput`, `cxVarInt`, `cxDerEncode`, `cxBtcWitness`, `cxBtcTxEncode`,
  `cxBtcTxid`.
- Ethereum: legacy (EIP-155) and EIP-1559 typed transactions via the RLP encoders + `cxSignRecoverable`,
  producing a signed, RLP-encoded transaction and the `keccak256` transaction hash. SHIPPED:
  `cxEthLegacySighash`, `cxEthLegacyEncode`, `cxEth1559Sighash`, `cxEth1559Encode`.
- KATs: reproduce a known signed transaction (txid) from known inputs. DONE in the reference model and
  the harness: the BIP-143 native-P2WPKH worked example rebuilds byte for byte (both sighash algorithms
  and its witness), plus the EIP-155 spec example and a self-consistent EIP-1559 transaction.

**Done when:** a raw transaction CoinXT built and signed is accepted as valid by an independent decoder /
testnet node. **Status:** ENGINE-PASSED 2026-08-12 (Windows x64): the folded suite harness ran the whole
coinxt surface at 230/230, including the BIP-143 signed transaction byte for byte, the EIP-155 and
EIP-1559 transactions and hashes, and both phase-5 refusals. Before that, EXECUTED headlessly and
verified against `tools/coin_reference.py` - `tools/check-script-vectors.py` drives all thirteen handlers
THROUGH the script against the BIP-143 / EIP-155 / EIP-1559 vectors (251 checks, the encoders fed the
oracle's own deterministic signatures), the same net phases 3-4 carry. That net paid for itself
immediately, catching a would-be-red engine defect the static gates could not see: `cxBtcTxEncode`
refused to assemble the reference transaction because its trailing-empty scriptSig collapses under the
engine's one-trailing-delimiter chunk rule (fixed, pinned, and confirmed green in the engine run). The
**independent-decoder half of the done-criterion is now MET (2026-08-12)**: `tools/verify-independent-decoder.py`
builds a FRESH native-P2WPKH transaction through the shipped script and python-bitcointx (a full
consensus-shaped verifier) accepts it - `VerifyScript` under `SCRIPT_VERIFY_WITNESS`, its own BIP-143
sighash matching the script's, with a flipped-signature and wrong-amount negative control each rejected.
**Extended 2026-08-13 to all four shipped families**: the same tool now also builds a fresh legacy
P2PKH spend (accepted under the same consensus evaluation, with a tampered-output control - the legacy
sighash commits to the outputs) and fresh EIP-155 / EIP-1559 transactions, which eth-account accepts
by recovering the exact sender, an independent RLP decode confirming every field; 31 checks, a
negative control firing in every family.
It is an acceptance run, not a CI gate (the pip verifiers are not vendored; each half SKIPS loudly
without its packages).
**A live testnet broadcast is the one bar left**, so nothing here is called broadcastable yet.
**Risk retired:** the jump from "signs a digest" to "assembles a real transaction."
Explicitly optional: the primitive layer (phases 1-4) is useful and shippable without this.

## Phase 6 - Packaging, examples, release

- Commit per-platform release binaries + a `MANIFEST.sha256`, refreshed in the same change as any shim
  change (the SodiumXT model). `cxCheckABI()` guards a stale binary. **Started early, on purpose**:
  `native/build.sh pack` and `src/coinxt.map` exist now, and `src/code/x86_64-linux/coinxt.so` +
  `src/code/MANIFEST.sha256` are committed, because without a library named for the `c:coinxt>` bind
  token there is no way to run the phase-1 engine pass at all - the packaging step was blocking the
  phase-1 "done when" bar rather than following it. Pulling the export-filtering decision forward also
  matters more than it looks: once a surface ships it is frozen, and the unfiltered build exported 61
  vendored trezor-crypto symbols (see `src/coinxt.map`). Since written, both halves of that residue
  have landed: FOUR platforms are committed and manifest-pinned (`x86_64-linux`, `x86-linux`,
  `x86_64-win32`, `x86-win32` - the 2026-08-12 release run refreshed all four), and
  `tools/package-extension.py` exists. What is still genuinely phase 6 on the packaging side is the
  `universal-mac` build alone, a deliberate manual `lipo` step (CI builds no macOS lanes; see the
  suite runbook).
- A demo stack and a pure offline self-test harness, formatted like OnionXT's
  (`onionxt-demo` / `onionxt-tests` split): show key gen, address derivation, sign/verify, an HD wallet
  from a mnemonic, and (if phase 5) a signed transaction. **The harness half was filled long ago by
  `tests/coin-selftest.livecodescript` (engine-passed 230/230); the demo half SHIPPED 2026-08-13 as
  `examples/coinxt-demo.livecodescript`** - mnemonic (generate via SodiumXT or import), the BIP-84/44
  and Ethereum addresses, sign/verify, and a decoded, signed native-P2WPKH and EIP-1559 transaction,
  each shown as human intent beside the bytes. Verified statically; its engine pass is a runbook demo
  row.
- Docs: a from-zero usage guide and the honesty caveats (custody is the app's, not hardware-grade
  isolation, sign only what you constructed). **SHIPPED 2026-08-13 as `docs/getting-started.md`**,
  the caveats included: never sign opaque bytes, wei stays hex, backups on paper, network and fee
  values are app inputs, no node or broadcast in CoinXT.

**Done when:** a fresh checkout builds the shim, the KATs and gates pass in CI, and the demo runs the
full path on a real engine. **Risk retired:** "works on my machine" and binary/ABI drift.

## Ordering notes

- Phases 1-4 are the product: primitives, signing, addresses, HD wallets. Phase 5 is a valuable but
  separable layer; ship 1-4 first.
- Keep the native surface frozen early. Every function is buffer-in / buffer-out and deterministic
  (SPEC section 5.1); resist adding stateful handles or an internal RNG. If HD ever needs a handle table,
  use the generation-tagged pattern from SodiumXT, not a raw pointer through script.
- The wordlist and the vendored sources are data + third-party code: hash them in `MANIFEST.sha256` and
  never edit vendored files in place without recording the patch in `VENDOR.md`.
