# CoinXT - Implementation Plan

The phased build order for CoinXT (see [SPEC.md](SPEC.md) for WHAT, [CLAUDE.md](CLAUDE.md) for the
rules). Each phase has a concrete "done when" bar and states the risk it retires. Build in order: the
native seam and the KAT harness come first, because everything downstream trusts them.

> Status: **phase 0 done; phase 1 hash slice done and verified** (see the as-built notes in
> [CLAUDE.md](CLAUDE.md)): the vendored SHA-3 unit, the `cnx_` shim with `cnx_keccak256` /
> `cnx_sha3_256`, the ASan + UBSan self-test, and the headless KAT harness are in and green. The
> `.lcb` on-engine binding and everything from the curve surface on are still to build. Unlike OnionXT
> (pure script), CoinXT HAS a C shim, so the FFI/C-ABI section of CLAUDE.md is law from phase 1 onward,
> and every shim change builds under ASan + UBSan and bumps the ABI + `cxCheckABI()` on any ABI change.

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
  marshalling helper (in-buffer via `MCDataGetBytePtr`; out-buffer via `MCMemoryAllocate` + the `-needed`
  re-alloc retry), `unsafe ... end unsafe` around every foreign call, `cxCheckABI()`.
- `cx*` wrappers for the hashes; `tools/coin-kat.py` pins `keccak256("")`, `sha3_256("")`, RIPEMD-160,
  HMAC-SHA512, PBKDF2-HMAC-SHA512.

**Done when:** `cxKeccak256` and friends return the pinned vectors from a real engine, ASan/UBSan clean.
**Risk retired:** the whole FFI plumbing (the family's single most expensive area) and the build.

## Phase 2 - Keys and signatures

- Export and wrap `cnx_seckey_verify`, `cnx_pubkey_from_seckey`, `cnx_pubkey_decompress`,
  `cnx_ecdsa_sign` / `_verify`, `cnx_ecdsa_sign_recoverable` / `cnx_ecdsa_recover`, `cnx_ecdh`, and (if
  in scope) `cnx_schnorr_sign` / `_verify` + `cnx_xonly_from_seckey`.
- `cx*` API: `cxNewSeckey` (validates caller entropy), `cxPublicKey`, `cxSign` / `cxVerify`,
  `cxSignRecoverable` / `cxRecover`, `cxEcdh`, Schnorr.
- Secret hygiene: seckey buffers `memzero`ed in the shim; the `cx*` layer documents clearing key
  variables. KATs: RFC 6979 deterministic signature, `ecrecover` round-trip, low-`s` canonicalization,
  BIP-340 vector.

**Done when:** a signature CoinXT makes verifies in an independent library, and `cxRecover` returns the
signing pubkey. **Risk retired:** the core value proposition (correct, deterministic, recoverable
signing on secp256k1).

## Phase 3 - Encodings and addresses (pure script)

- Livecodescript, no shim: `cxHexEncode/Decode`, `cxBase58CheckEncode/Decode`,
  `cxBech32Encode/Decode` (Bech32 and Bech32m), `cxRlpEncode/Decode`. Each fails closed on a bad
  checksum / malformed input (the OnionXT base32 discipline: small bit-buffer, byte ops, no `^`/`div`/
  `mod` where a parser chokes).
- Address composition: `cxBtcAddressP2PKH`, `cxBtcAddressP2WPKH`, `cxBtcAddressP2TR`, `cxEthAddress` +
  `cxEthAddressChecksum` (EIP-55).
- KATs: BIP-173 / BIP-350 valid AND invalid vectors, the EIP-55 examples, a P2PKH / P2WPKH / P2TR vector,
  a known-pubkey -> known-eth-address vector.

**Done when:** a pubkey maps to the correct mainnet BTC (all three types) and ETH addresses, and a
corrupt address is rejected. **Risk retired:** the "silently wrong address = lost funds" class, moved
into script where it is diffable and fully KAT-covered.

## Phase 4 - HD wallets and mnemonics

- Shim: `cnx_hdnode_from_seed`, `cnx_hdnode_derive` (one step), `cnx_hdnode_private_key` / `_public_key`
  / `_chaincode`, `cnx_bip39_seed`.
- Script: `cxHdFromSeed`, `cxHdDerivePath` (parse `m/44'/0'/0'/0/0`, loop the shim per level, handle the
  `'` hardened marker), `cxHdSeckey` / `cxHdPubkey` / `cxHdChainCode`, `cxXprv` / `cxXpub` (Base58Check
  framing in script). BIP-39 entropy<->words + checksum word in script over the shipped wordlist;
  `cxMnemonicFromEntropy`, `cxMnemonicToSeed`, `cxMnemonicValidate`.
- KATs: the official BIP-32 and BIP-39 vectors, end to end (mnemonic -> seed -> node -> derived address).

**Done when:** the official BIP-39 mnemonic + a BIP-44 path reproduce the reference address, byte for
byte. **Risk retired:** wallet interoperability (a CoinXT wallet and any standard wallet agree on the
same key from the same mnemonic).

## Phase 5 - Transaction building and signing (stretch)

- Bitcoin: legacy and SegWit (BIP-143) sighash construction and signing in script (compose `cxSign` +
  the encoders), producing a broadcastable raw transaction.
- Ethereum: legacy and EIP-1559 typed transactions via `cxRlpEncode` + `cxSignRecoverable`, producing a
  signed, RLP-encoded transaction and the `keccak256` transaction hash.
- KATs: reproduce a known signed transaction (txid) from known inputs.

**Done when:** a raw transaction CoinXT built and signed is accepted as valid by an independent decoder /
testnet node. **Risk retired:** the jump from "signs a digest" to "produces a real, broadcastable
transaction." Explicitly optional: the primitive layer (phases 1-4) is useful and shippable without this.

## Phase 6 - Packaging, examples, release

- Commit per-platform release binaries + a `MANIFEST.sha256`, refreshed in the same change as any shim
  change (the SodiumXT model). `cxCheckABI()` guards a stale binary.
- A demo stack and a pure offline self-test harness, formatted like OnionXT's
  (`onionxt-demo` / `onionxt-tests` split): show key gen, address derivation, sign/verify, an HD wallet
  from a mnemonic, and (if phase 5) a signed transaction.
- Docs: a from-zero usage guide and the honesty caveats (custody is the app's, not hardware-grade
  isolation, sign only what you constructed).

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
