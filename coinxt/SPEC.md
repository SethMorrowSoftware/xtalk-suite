# CoinXT - Specification

**CoinXT** is a Bitcoin and Ethereum cryptography layer for OpenXTalk (OXT) / the xTalk family. It wraps
**trezor-crypto** (the C crypto core of the Trezor hardware wallet) and **bitcoin-core/secp256k1**
behind a thin, stable C ABI and a livecodescript API, so an xTalk app can generate keys, derive HD
wallets from a mnemonic, build addresses, and build, sign and verify transactions for both chains,
without a browser plugin, a node, or a cloud wallet service.

House style: no em-dashes (hyphens, commas, colons, parentheses). ASCII only in `.lcb` /
`.livecodescript`. Comment the *why*, densely. Public API `cxPascalCase`; C ABI `cnx_snake_case`.

The source of truth for WHAT CoinXT is and the contract each layer meets. The shipped handlers are
[docs/api-reference.md](docs/api-reference.md); the FFI rules and dated evidence are [CLAUDE.md](CLAUDE.md).

## 1. What CoinXT is (and is NOT)

CoinXT provides the **primitives** a wallet or a dapp client is built from. It **is**:

- secp256k1: keypairs, ECDSA (RFC 6979 deterministic), **recoverable** ECDSA (Ethereum's `v`),
  public-key recovery (`ecrecover`), ECDH, point addition, and BIP-340 Schnorr with the BIP-341 tweak.
- The hashes both chains need: SHA-256, SHA-512, SHA3-256, **Keccak-256** (Ethereum's non-NIST
  padding), RIPEMD-160, plus HMAC and PBKDF2-HMAC-SHA512.
- HD wallets: BIP-32 derivation and BIP-39 mnemonics.
- Formats: Base58Check, Bech32 / Bech32m (SegWit v0 / v1), hex, RLP, xprv/xpub, WIF, EIP-55.
- Transaction builders: Bitcoin legacy, BIP-143 and BIP-341 sighashes and serialization; Ethereum
  EIP-155 and EIP-1559.

**Decided NOT to ship, each with the condition for revisiting it:**

- **SHA3-512 is DEFERRED** (2026-08-17; the suite's D-16 reaffirmed it 2026-08-27). The vendored
  `sha3.c` implements it and it is compiled into every binary; shipping it costs a `cnx_sha3_512` export
  and length accessor, `.lcb` wrappers, an ABI bump and a five-platform binary refresh (suite rule 5), and
  no chain, caller or member needs it (callers who want NIST padding have `cxSha3_256`). Ship it only for
  a concrete caller, with the next planned ABI bump. Until then `cxSha3_512` is a `handler not found`,
  and `tools/check-doc-handlers.py` carries a `deferred` entry that fails the day it ships.
- **SLIP-39 is NOT planned** (the suite's D-15, 2026-08-27): revisit only with a named consumer, bundled
  with an ABI bump.

It is **NOT**:

- A key manager or a wallet UI. The app owns key storage, backup, and the confirm-before-sign UX.
- A network layer. CoinXT never touches a peer, a node, or an RPC endpoint. It produces signed bytes;
  the app broadcasts them (optionally over Tor via OnionXT, doc-level composition only).
- A source of consensus truth. It does not validate a chain, a UTXO set, or a nonce. It signs what it is
  told to sign; the app constructs the transaction.
- New cryptography. Every curve op and hash is upstream, audited code; CoinXT adds no cipher of its own
  (the rule SodiumXT and OnionXT hold). Section 2 says which upstream.

## 2. Why trezor-crypto, and the license

[trezor-firmware `crypto/`](https://github.com/trezor/trezor-firmware/tree/main/crypto) is
**MIT-licensed**, plain **C**, has **no external dependencies**, and compiles into constrained targets:
exactly the self-contained, buffer-in / buffer-out, permissively licensed library the family's FFI
pattern can vendor and redistribute. It is the crypto core of a shipping hardware wallet. CoinXT vendors a
**subset** of its files plus a small shim and builds one shared library per platform, with no autotools
and no submodule. The file list, the pin, and why the curve half is a closure rather than a pick-list are
in [native/vendor/VENDOR.md](native/vendor/VENDOR.md).

### 2.1 A SECOND library, and the rule change that admitted it (decided 2026-08-16)

**The rule was** "every curve op and hash is trezor-crypto's". **It is now** "no cryptography of our
own; two upstreams that do not overlap": trezor-crypto, and **bitcoin-core/secp256k1** (MIT, pinned at
`439278a649d3099d62dde966a76dc04aaca7ccb3`). trezor-crypto keeps every hash, ECDSA, recoverable ECDSA,
recovery, ECDH and the two BIP-32 curve steps. libsecp256k1 owns BIP-340 Schnorr, x-only keys, the
BIP-341 tweak and point addition, reached through six `cnx_` entry points (`cnx_schnorr_sign`,
`cnx_schnorr_verify`, `cnx_xonly_pubkey_from_seckey`, `cnx_taproot_tweak_pubkey`,
`cnx_taproot_tweak_seckey`, and since ABI 7 `cnx_pubkey_combine`).

**Why.** trezor-crypto's plain-C tree has **no BIP-340**; it reaches Schnorr only through
`zkp_bip340.c`, which needs the bundled `secp256k1-zkp` and its own build system, an order of magnitude
more vendoring for extras (adaptor signatures, rangeproofs) CoinXT does not use. The other option was
writing BIP-340 by hand, and **hand-rolling a signature scheme is exactly what rule 1 forbids**, so the
second library is the rule obeyed, not waived. Upstream libsecp256k1 is also what Bitcoin Core ships.

**The audit surface it added:** 58 vendored files, 3.13 MB of source (one generated table,
`precomputed_ecmult.c`, is 2.30 MB), compiled as three translation units (`secp256k1.c`, which includes
the rest, and the two tables), every file blob-verified against the pin and hashed in
`native/MANIFEST.sha256`; only the `schnorrsig` and `extrakeys` modules enabled (`ecdh`, `recovery`,
`musig`, `ellswift` and `silentpayments` are neither compiled nor vendored); one long-lived object, a
file-static `secp256k1_context` created on first use, re-randomized before every secret-key operation,
never exposed and never freed; one entry point that is not a pure function of its inputs (section 4);
and simpler licensing, MIT throughout, one entry in [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md).

**The BIP-341 script layer on top** (2026-08-23; engine-proven 2026-08-24 in coinxt's 290/290):
`cxBtcSighashTaproot` (every base type, the three ANYONECANPAY forms, the tapleaf extension, epoch 0x00),
`cxTapLeafHash`, `cxTapBranchHash` and `cxTapControlBlock`. Bounds: no OP_CODESEPARATOR (the extension
always writes position 0xffffffff) and no annex; tree ASSEMBLY above one fold is the app's loop over
`cxTapBranchHash`; the builder returns a digest and is not a signer.

No operation moved between the libraries and nothing is implemented against both; moving one across
that line is an interoperability decision, not a refactor.

## 3. Architecture: what is C and what is script

```
app (livecodescript)
   |
CoinXT public API (cx*)   src/coinxt.livecodescript
   |- ENCODINGS in script (pure byte work): hex, Base58Check, Bech32/Bech32m, RLP, WIF, EIP-55,
   |     addresses, BIP-32 HMAC/serialization/path parse, BIP-39 words, tx serialization, sighashes
   |- FFI seam (unsafe ... end unsafe), one .lcb module
CoinXT C shim (cnx_)   native/coinxt.c  + vendored trezor-crypto and libsecp256k1 subsets
   |- CURVE + HASHES in C (constant-time-sensitive, must be the audited code): keypair, ECDSA,
         recoverable, recover, ECDH, point sum, Schnorr, SHA-2, SHA3-256, Keccak-256, RIPEMD-160,
         HMAC, PBKDF2, the BIP-32 tweaks, the BIP-39 wordlist as data
```

**Rule of thumb** (OnionXT's precedent): anything that touches a private key or a curve point is C;
checksummed byte-shuffling with no secret-dependent branch is livecodescript, pinned by a KAT.

## 4. Determinism and entropy (a load-bearing design decision)

**Every operation is a pure function of its inputs, so every operation is known-answer testable**, with
one deliberate exception below. Signing is RFC 6979 and needs no randomness. Fresh key material is the
caller's: a private key is any valid 32-byte scalar (`cxSeckeyIsValid` checks the range), and the entropy
comes from a real CSPRNG, naturally **SodiumXT's `sxRandomBytes`** (as OnionXT derives onion keys from a
SodiumXT seed) or OS entropy the app obtained itself. CoinXT never invents the randomness your keys
depend on. Two facts qualify "no ambient RNG in the shim"; neither is nonce generation or can weaken a key:

1. **Side-channel blinding.** `vendor/ecdsa.c` draws OS entropy on every scalar multiply and it cancels
   algebraically, which is why the signatures stay KAT-pinnable; the libsecp256k1 context is
   re-randomized before every secret-key operation, upstream's own recommendation.
2. **The ONE non-reproducible output.** `cnx_schnorr_sign` with an ABSENT aux (zero-length) draws 32 OS
   bytes rather than the all-zero aux upstream's NULL would mean: silently picking the least-protected
   option when the caller says nothing is the fail-open shape this member refuses. BIP-340's nonce is
   `hash(aux XOR key, P, msg)`, deterministic in (key, message) even at aux = 0, so the randomness only
   adds protection. **Supply the 32-byte aux and the signature is reproducible**, as the vectors specify.
   `tools/coin-kat.py` asserts both directions: the vectors byte for byte, and two absent-aux signatures
   that differ, both verify, and neither equals the zero-aux one.

## 5. The C ABI contract (`cnx_`)

Carried from the family's FFI law ([CLAUDE.md](CLAUDE.md); the SodiumXT / TorrentXT bindings).

- **Every function returns an `int` status**: `0` ok, or a stable negative code never renumbered:
  `CNX_ERR_NULL` -1, `BADLEN` -2, `RANGE` -3, `BADKEY` -4, `BADSIG` -5, `ENTROPY` -6, `BADDIGEST` -7,
  `INTERNAL` -8. No human strings cross the ABI; the `.lcb` layer maps codes to messages.
- **Buffers cross as `Pointer` + `UIntSize`.** A `Data` does not auto-bridge to `void*`: an in-buffer
  passes `MCDataGetBytePtr` + length, an out-buffer is an `MCMemoryAllocate` block. Lengths are C
  `size_t`, so `UIntSize`, never `CUInt` (a 4-byte int into an 8-byte slot corrupts the heap).
- **No `-needed` retry protocol** (that is SodiumXT's): a `cnx_` function writes a fixed size it reports
  itself, or exactly the output length asked for, so the binding allocates and copies exactly that.
- **Never RETURN a bridged C string.** A returned static/owned pointer is `free()`-on-static.
- **Every length is a function, never a hardcoded LCB constant**: seventeen `cnx_*_len()` accessors
  (tabled in docs/api-reference.md, "Length accessors").
- **`cnx_abi_version()`**: the `.lcb` `cxCheckABI` throws "reinstall CoinXT" on skew, and every handler
  re-checks it before any call that could corrupt memory.
- **The `cnx_` prefix is stable forever**: `binds to` strings name the symbols, so a rename is a silent
  bind failure at load. Every bump so far has been additive; the version moves on ANY ABI change.
- **`textEncode` / `textDecode` are livecodescript-only**: text conversion stays in script; the shim
  sees only `Data`.

### 5.1 The native function surface (the whole wrap)

**44 exports at ABI 7**, all buffer-in / buffer-out, all deterministic except the aux-less signing path
of section 4. Every buffer is pointer + `size_t` (lengths elided below).

```
Curve (trezor-crypto):
  cnx_seckey_verify(sk)                        cnx_pubkey_from_seckey(sk, compressed, out33|65)
  cnx_pubkey_decompress(pub, out65)            cnx_ecdsa_sign(sk, digest32, out_sig64)   // RFC 6979
  cnx_ecdsa_verify(pub, digest32, sig64)       cnx_ecdsa_sign_recoverable(sk, digest32, out65)
  cnx_ecdsa_recover(sig65, digest32, out65)    cnx_ecdh(sk, pub, out65)
  // cnx_ecdh writes the raw point 0x04||X||Y, not the 32-byte X the first sketch assumed:
  // the caller applies its protocol's KDF.

libsecp256k1 (section 2.1); optional inputs are carried BY LENGTH (0 = absent), never by sentinel:
  cnx_schnorr_sign(sk, msg, aux, out_sig64)    // msglen MUST be 32 (rule 3); auxlen 0 = fresh OS
                                               // randomness, 32 = reproducible; never all-zero aux
  cnx_schnorr_verify(xonly32, msg, sig64)      // ANY msglen (the vectors carry 0/1/17/100 bytes); an
                                               // off-curve key is BADSIG, i.e. false (vectors 5, 14)
  cnx_xonly_pubkey_from_seckey(sk, out32)      // no parity output: no caller needs it
  cnx_taproot_tweak_pubkey(internal32, root, out33)   // x-only output key || one parity byte
  cnx_taproot_tweak_seckey(sk, root, out32)
      // Q = P + int(hash_TapTweak(bytes(P) || merkle_root))G. rootlen 0 is KEY-PATH-ONLY and
      // hashes the EMPTY string, NOT 32 zero bytes (the wrong one is a valid-looking unspendable
      // address).
  cnx_pubkey_combine(keys33xN, out33)          // ABI 7: sums the whole set at once, so an
                                               // intermediate infinity is fine and only a FINAL
                                               // infinity is refused (a BIP-352 vector)

Hashes: cnx_sha256, cnx_sha512, cnx_ripemd160, cnx_hmac_sha256, cnx_hmac_sha512,
  cnx_sha3_256 (NIST 0x06 padding; closes OnionXT's gap #2), cnx_keccak256 (Ethereum 0x01, NOT NIST),
  cnx_pbkdf2_hmac_sha512(pw, salt, iterations, out, outlen)

HD (BIP-32): only the two operations that ARE curve arithmetic; the node never crosses the ABI:
  cnx_seckey_tweak_add(sk, tweak, out32)       // ki = IL + kpar mod n
  cnx_pubkey_tweak_add(pub, tweak, out33)      // Ki = point(IL) + Kpar
  // HMAC-SHA512, the 78-byte serialization and the path parse are script. Upstream's bip32.c is
  // NOT vendored: it would pull in curves.c, nist256p1, ed25519-donna and the Cardano variants.

BIP-39: cnx_bip39_wordlist(out)   // 2048 fixed 8-byte slots, space padded (16384 bytes). No
  // cnx_bip39_seed: the seed is PBKDF2, which cxMnemonicToSeed composes; words live in script.

Secret hygiene (ABI 5): cnx_memzero(buf, len)   // wraps vendored memzero.c; INTERNAL to the .lcb,
  // which wipes every raw out-buffer before freeing it. No cx* wrapper: a script Data cannot be wiped.

Plus cnx_abi_version and the seventeen cnx_*_len accessors. Everything else is livecodescript.
```

## 6. The livecodescript API (`cx*`)

[docs/api-reference.md](docs/api-reference.md) is the complete handler list (95: 44 `.lcb`, 51 script),
held complete in both directions by `tools/check-doc-handlers.py`. The contract every handler meets:

- **Functions return a value; every failure THROWS** `"CoinXT: <handler>: ..."`, with no error-code
  return and no partial result. A question routinely answered "no" returns a Boolean instead
  (`cxSeckeyIsValid`, `cxVerify`, `cxSchnorrVerify`, `cxMnemonicValidate`, `cxEthAddressIsChecksummed`).
- **Bytes are `Data`**; text (addresses, mnemonics, hex, WIF) is a String. Wei-scale Ethereum values
  cross as minimal big-endian hex, because they exceed exact-integer range.
- **The HD node is an ARRAY read by name**, with the fields BIP-32 serializes in the order it serializes
  them (`seckey`, `pubkey`, `chaincode`, `depth`, `index`, `parentfp`), so `cxXprv` is a concatenation,
  not a translation. That replaced the `cxHdSeckey` / `cxHdPubkey` / `cxHdChainCode` accessors this
  section first sketched.
- **An empty `pAuxRand` or `pMerkleRoot` means absent** (fresh randomness; a key-path-only output).
- **`cxBtcAddressP2TR` never tweaks**; `cxBtcAddressP2TRFromInternal` is a SEPARATE handler because an
  absent xTalk parameter equals an empty one, so an optional root could not tell "encode this output key"
  from "tweak this internal key with no script tree", and those give different addresses, one
  unspendable. Making the old handler tweak would have silently double-tweaked every correct call.
- **A WIF key crosses as 64 hex characters** both ways (WIF is the paste format); decode returns an array
  (`seckey`, `network`, `compressed`), and both directions range-check via `cxSeckeyIsValid`.
- **A non-ASCII passphrase is the caller's to NFKD-normalize** (`cxMnemonicNormalize` only trims and
  single-spaces). `cxMnemonicToSeed` does not verify the checksum (BIP-39 defines a seed for any
  string): call `cxMnemonicValidate` first on anything a human typed.
- **Repeated transaction fields cross as comma lists read by index**; RLP is built piecewise
  (`cxRlpEncodeBytes` / `cxRlpEncodeList`) because xTalk has no nested-list literal.

## 7. Formats CoinXT must get byte-exact (the spec inside the spec)

Each is a place a wallet silently loses money if a byte is wrong, so each is pinned by a public vector
(section 9). Implement against the standard, not from memory.

- **secp256k1 / RFC 6979**: deterministic `k`; reproducible, low-`s` (BIP-62) for Bitcoin; Ethereum
  wants the recovery id and low-`s` (EIP-2).
- **Keccak-256 vs SHA3-256**: Ethereum uses Keccak with the ORIGINAL `0x01` padding, not FIPS-202's
  `0x06`. Two different functions; never alias them.
- **Ethereum address**: `keccak256(uncompressed_pubkey_without_0x04)`, last 20 bytes, lowercase hex with
  `0x`, then **EIP-55** (uppercase a nibble where the matching nibble of `keccak256(lowercase_address)`
  is >= 8). Verify the checksum on any address the app accepts.
- **Base58Check**: `base58( payload || first4(sha256(sha256(version||payload))) )`; decode recomputes
  and compares the checksum and fails closed.
- **WIF**: Base58Check over `version || 32-byte key || optional 0x01 marker`, 0x80 mainnet / 0xEF
  testnet. Decode fails closed on a bad checksum, a payload that is not 33 or 34 bytes, an unknown
  version, a trailing byte that is not 0x01, and a scalar of zero or >= the group order. The marker is
  surfaced because compressed and uncompressed keys pay different addresses. Pinned to the Bitcoin
  wiki's worked example.
- **Bech32 / Bech32m**: they differ only by the polymod constant (1 vs 0x2bc830a3). SegWit v0 uses
  Bech32, v1+ Bech32m. The HRP, the witness version and the 5-bit squashing must be exact, and the
  checksum verified on decode.
- **BIP-32**: `I = HMAC-SHA512(chaincode, data)`; `IL` tweaks the key, `IR` is the new chaincode;
  hardened indices (>= 0x80000000) use the private key. xprv/xpub is Base58Check with per-network
  version bytes.
- **BIP-39**: 128-256 bits of entropy + the first `entropy_bits/32` bits of `sha256(entropy)` -> 11-bit
  indices into the 2048-word list; seed = `PBKDF2-HMAC-SHA512(mnemonic, "mnemonic" + passphrase, 2048,
  64)`. The wordlist is data, shipped and hashed.
- **RLP**: single bytes < 0x80 are literal, else a length-of-length scheme; decode rejects the
  non-canonical forms.

## 8. Security model and honesty rules

1. **Add no cryptography. Wrap an audited upstream.** Every curve op, hash, and KDF is trezor-crypto's or
   libsecp256k1's (section 2.1). A missing primitive is an upstream request or a new vendored file, never
   a hand-rolled scalar mult or hash. (The family's first rule; it counts double for money.)
2. **The app owns key custody.** CoinXT holds a key only for the microseconds of an operation. Storage,
   backup and a confirm-before-sign step are the app's. Document the boundary loudly.
3. **Secret hygiene across the FFI.** Keys, seeds, and chaincodes cross as `Data` / `Pointer`, are
   `memzero`ed in the shim after use, and are NEVER returned as a bridged C string. Since ABI 5 the
   `.lcb` also wipes every raw out-buffer through `cnx_memzero` before freeing it. The script layer clears
   its key variables (`put empty into tSeckey`) as soon as it is done. The honest limit: OXT script
   variables are not locked memory and can be paged; the desktop is the trust boundary, and we say so.
4. **Fail closed on every malformed input.** A bad checksum, an out-of-range scalar, a wrong-length
   buffer, a non-canonical signature: a clean error, never a wrong-but-plausible key or address.
5. **Sign only what the app constructed.** The signing handlers take a 32-byte digest; the transaction
   builders compute it from fields the app supplied, and the app still confirms the decoded human intent
   before signing. A blind signer is a footgun.
6. **Constant-time is upstream's job, within limits.** No timing-variable branches on secret data in the
   shim; the secret-free formatting is in script where timing does not matter. A desktop is not a
   side-channel-hardened environment; never market CoinXT as hardware-wallet-grade isolation.
7. **Mainnet vs testnet is explicit.** Version bytes and HRPs are parameters, never guessed.

## 9. Testing and conformance

Every deterministic path is pinned to public known-answer vectors in `tools/coin-kat.py` (the OnionXT
`onion-kat.py` model: self-checking, in CI, cross-checked against an independent implementation before
pinning), and the script layer is driven through the same vectors by `tools/check-script-vectors.py`.
Nothing is generated by the library under test. Sources: RFC 6979 and a signature verified by the
independent Python `ecdsa` library; all 19 BIP-340 vectors (ten NEGATIVE); all 7 `scriptPubKey` and all 7
`keyPathSpending` cases of BIP-341's wallet vectors, walked private key -> internal key -> tweaked key ->
the published witness signature, plus its sighash and script-tree cases; `keccak256("")` =
`c5d2460186f7...`, `sha3_256("")`, RIPEMD-160, HMAC-SHA512 and PBKDF2 vectors; the EIP-55 examples;
BIP-32 vectors 1-3; the Trezor BIP-39 vectors; BIP-173 / BIP-350 valid AND invalid strings; the RLP
yellow-paper examples; the BIP-143 worked example, the EIP-155 specification example and a
self-consistent EIP-1559 transaction.

The curve and hash correctness is upstream's; CoinXT's KATs prove the *wrap* and the *script-side
encodings*, end to end from the `cx*` API. Acceptance by code we did not write is
`tools/verify-independent-decoder.py` (python-bitcointx and eth-account, a manual run). Behaviour that
needs a real chain (broadcast, confirmation) belongs to the app that composes CoinXT.

## 10. Composition with the rest of the family

- **SodiumXT** supplies the entropy (`sxRandomBytes`) for fresh keys, and its `sxMemZero` discipline is
  the model for secret hygiene. CoinXT does not duplicate libsodium: the hashes it needs (Keccak,
  RIPEMD-160, SHA-3) are ones libsodium lacks, which is why they come from trezor-crypto.
- **OnionXT** is the natural transport for anything CoinXT-signed that must reach a node privately:
  sign with CoinXT, broadcast through Tor with OnionXT, so the submitting IP is not linked to the address.
  A documentation-level composition; neither library depends on the other.
- **OnionXT's deferred offline SHA3-256** (its gap #2) is `cnx_sha3_256` here, for an offline
  v3-address checksum.
