# CoinXT - Specification

**CoinXT** is a Bitcoin and Ethereum cryptography layer for OpenXTalk (OXT) / the xTalk family. It wraps
**trezor-crypto** (the C crypto core of the Trezor hardware wallet) behind a thin, stable C ABI and a
livecodescript API, so an xTalk app can generate keys, derive HD wallets from a mnemonic, build and
encode addresses, and sign and verify for both chains, without shipping a browser plugin, a node, or a
cloud wallet service.

House style: no em-dashes (hyphens, commas, colons, parentheses). ASCII only in `.lcb` /
`.livecodescript`. Comment the *why*, densely. Public API `cxPascalCase`; C ABI `cnx_snake_case`.

> This is a design spec, not an implementation. Nothing here has been built yet. It is the source of
> truth for WHAT CoinXT is and the contract each layer must meet; the phased HOW is in
> [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md), and the hard-won FFI/LCB rules are in
> [CLAUDE.md](CLAUDE.md).

## 1. What CoinXT is (and is NOT)

CoinXT provides the **primitives** a wallet or a dapp client is built from. It is not a wallet, not a
node, and not a broadcaster.

It **is**:
- secp256k1 elliptic-curve operations: keypairs, ECDSA (RFC 6979 deterministic), **recoverable** ECDSA
  (the `v` recovery id Ethereum needs), public-key recovery (`ecrecover`), ECDH, and Schnorr / BIP-340.
- The hashes both chains need: SHA-256, SHA-512, SHA3-256/512, **Keccak-256** (Ethereum's non-NIST
  padding), RIPEMD-160, plus HMAC and PBKDF2-HMAC-SHA512.
- HD wallets: BIP-32 derivation, BIP-39 mnemonics (and SLIP-39 in a later phase).
- Address and serialization formats: Base58Check, Bech32 / Bech32m (SegWit v0 / v1), hex, RLP, xprv/xpub,
  WIF, and the EIP-55 mixed-case Ethereum checksum.

It is **NOT**:
- A key manager or a wallet UI. The app owns key storage, backup, and the confirm-before-sign UX.
- A network layer. CoinXT never touches a peer, a node, or an RPC endpoint. It produces signed bytes;
  the app broadcasts them (optionally over Tor via OnionXT, doc-level composition only).
- A source of consensus truth. It does not validate a chain, a UTXO set, or a nonce. It signs what it is
  told to sign; the app is responsible for constructing the correct sighash / transaction.
- New cryptography. Every curve op and hash is trezor-crypto's; CoinXT adds no cipher of its own (the
  same rule SodiumXT and OnionXT hold).

## 2. Why trezor-crypto, and the license

[trezor-firmware `crypto/`](https://github.com/trezor/trezor-firmware/tree/main/crypto) (the standalone
`trezor-crypto` repo is deprecated in favour of the monorepo) is **MIT-licensed**, plain **C**, has **no
external dependencies**, and is designed to compile into a constrained target. It bundles a copy of
`secp256k1` (also MIT). That combination is exactly what the family's FFI pattern wants: a self-contained
C library with a buffer-in / buffer-out API and a permissive license we can vendor and redistribute.

It is the crypto core of a shipping hardware wallet, so the curve and hash code is battle-tested and
maintained. CoinXT vendors a **subset** of its `.c` files (the curve, the hashes, BIP-32/39, base58,
bech32) plus a small shim, and builds one shared library per platform. No autotools, no submodule tree,
no libtorrent-scale build matrix.

## 3. Architecture: what is C and what is script

The split follows OnionXT's precedent (base32 and address<->key mapping are pure byte work done in
livecodescript; only the true crypto is native). Keep the native surface as small as the security goal
allows.

```
app (livecodescript)
   |
CoinXT public API (cx*)   src/coinxt.livecodescript
   |- ENCODINGS in script (pure byte work, no secrets-critical math):
   |     hex, Base58Check, Bech32 / Bech32m, RLP, xprv/xpub framing, WIF,
   |     EIP-55 checksum, address composition (P2PKH / P2WPKH / P2TR / eth)
   |- FFI seam (unsafe ... end unsafe), one .lcb module
   |
CoinXT C shim (cnx_)   native/coinxt.c   + vendored trezor-crypto subset
   |- CURVE + HASHES in C (constant-time-sensitive, must be the audited code):
         secp256k1 keypair / ECDSA / recoverable / recover / ECDH / Schnorr,
         SHA-256/512, SHA3, Keccak-256, RIPEMD-160, HMAC, PBKDF2, BIP-32 node math,
         BIP-39 mnemonic-to-seed
```

**Rule of thumb:** anything that touches a private key or a curve point is C (audited trezor-crypto).
Anything that is checksummed byte-shuffling with no secret-dependent branch is livecodescript, pinned by
a KAT. This keeps the trusted native surface minimal and puts the formatting where it is easy to read,
diff, and test.

## 4. Determinism and entropy (a load-bearing design decision)

**CoinXT is deterministic: every operation is a pure function of its inputs, so every operation is
known-answer testable.** trezor-crypto signs with RFC 6979 (deterministic ECDSA), so signing needs no
randomness. The only place randomness is inherent is *fresh key material*, and CoinXT does not generate
it internally:

- A private key is any valid 32-byte scalar. `cxSeckeyValidate` checks range; a seed / mnemonic / entropy
  is supplied by the caller.
- The caller brings entropy from a real CSPRNG. The natural source in this family is **SodiumXT's
  `sxRandomBytes`** (compose it), exactly as OnionXT derives onion keys from a SodiumXT seed. An app
  without SodiumXT passes OS entropy it obtained itself.

This means: no ambient RNG in the shim to get wrong, no non-reproducible outputs, and the whole surface
is pinned by vectors in `tools/coin-kat.py`. It also keeps the trust story honest: CoinXT never invents
the randomness your keys depend on; you hand it in and can audit where it came from.

## 5. The C ABI contract (`cnx_`)

Carried verbatim from the family's FFI law (see [CLAUDE.md](CLAUDE.md) and the SodiumXT / TorrentXT
bindings). The shim is intentionally tiny; these are its shapes.

- **Every function returns an `int` status**: `0` = ok, negative = a stable error code
  (`CNX_ERR_BADLEN`, `CNX_ERR_BADKEY`, `CNX_ERR_BADSIG`, `CNX_ERR_RANGE`, `CNX_ERR_INTERNAL`, ...). No
  human strings cross the ABI; the livecodescript layer maps codes to messages.
- **Byte buffers cross as `Pointer` + `CInt` length.** An LCB `Data` does NOT auto-bridge to `void*`. An
  **in** buffer passes `MCDataGetBytePtr` + length; an **out** buffer is an engine `MCMemoryAllocate`
  block passed as a real `Pointer`, and the shim writes into it and reports bytes written (or a negative
  required size, `-needed`, so the LCB layer can re-allocate and retry).
- **Never RETURN a bridged C string.** Fill a caller buffer; return length. A returned static/owned
  pointer is `free()`-on-static on the first call.
- **Sizes are `size_t` -> `UIntSize`, not `CUInt`.** A 4-byte int into an 8-byte slot corrupts the heap.
- **Every length is a function, never a hardcoded LCB constant:** `cnx_seckey_len()` = 32,
  `cnx_pubkey_len_compressed()` = 33, `cnx_pubkey_len_uncompressed()` = 65, `cnx_ecdsa_sig_len()` = 64,
  `cnx_recoverable_sig_len()` = 65, `cnx_schnorr_sig_len()` = 64, `cnx_xonly_pubkey_len()` = 32,
  `cnx_keccak256_len()` = 32, `cnx_sha256_len()` = 32, `cnx_ripemd160_len()` = 20, `cnx_seed_len()` = 64,
  `cnx_chaincode_len()` = 32.
- **`cnx_abi_version()`** returns an int; the `.lcb` `cxCheckABI()` throws "reinstall CoinXT" on skew
  before any call that could corrupt memory.
- **Exported symbols keep the stable `cnx_` prefix and are never renamed once shipped** (the `.lcb`
  `binds to` strings reference them by name; a rename is a silent bind failure at load).
- **`textEncode` / `textDecode` are livecodescript-only**, so text<->Data conversion stays in the script
  layer; the shim sees only `Data`.

### 5.1 The native function surface (the whole wrap)

Small on purpose. Grouped; each takes/returns fixed-size buffers per section 5.

```
Curve (secp256k1):
  cnx_seckey_verify(sk32) -> int
  cnx_pubkey_from_seckey(sk32, compressed, out_pub) -> int          // 33 or 65 bytes
  cnx_pubkey_decompress(pub, out65) -> int
  cnx_ecdsa_sign(sk32, hash32, out_sig64) -> int                    // RFC 6979
  cnx_ecdsa_verify(pub, hash32, sig64) -> int
  cnx_ecdsa_sign_recoverable(sk32, hash32, out_sig65) -> int        // Ethereum: 64 + recid
  cnx_ecdsa_recover(sig65, hash32, out_pub65) -> int                // ecrecover
  cnx_ecdh(sk32, pub, out32) -> int
  cnx_schnorr_sign(sk32, msg32, aux32, out_sig64) -> int            // BIP-340
  cnx_schnorr_verify(xonly_pub32, msg32, sig64) -> int
  cnx_xonly_from_seckey(sk32, out32, out_parity) -> int             // BIP-340 / Taproot

Hashes:
  cnx_sha256(in, len, out32) / cnx_sha512(in, len, out64)
  cnx_sha3_256(in, len, out32)          // NIST FIPS-202 (also closes OnionXT gap #2)
  cnx_keccak256(in, len, out32)         // Ethereum padding (0x01), NOT NIST (0x06)
  cnx_ripemd160(in, len, out20)
  cnx_hmac_sha256(key, klen, msg, mlen, out32) / cnx_hmac_sha512(...out64)
  cnx_pbkdf2_hmac_sha512(pw, plen, salt, slen, iters, out, outlen) -> int

HD (BIP-32) - the node is a fixed-size opaque byte blob (version||depth||fingerprint||
              child||chaincode||key), so no handle table is needed across the ABI:
  cnx_hdnode_from_seed(seed, slen, out_node) -> int
  cnx_hdnode_derive(node, index, hardened, out_node) -> int         // one step; path split in script
  cnx_hdnode_private_key(node, out32) -> int
  cnx_hdnode_public_key(node, out33) -> int
  cnx_hdnode_chaincode(node, out32) -> int

Mnemonic (BIP-39):
  cnx_bip39_seed(mnemonic, mlen, passphrase, plen, out64) -> int    // PBKDF2-HMAC-SHA512, 2048 iters
  // entropy<->words and the checksum word live in script (pure bytes + a SHA-256 call)
```

That is the entire native surface: roughly 25 functions, all buffer-in / buffer-out, all deterministic.
Everything else in CoinXT is livecodescript.

## 6. The livecodescript API (`cx*`)

Shapes follow the family convention: functions return a value; commands report through `the result`. A
value that can fail returns a `"CoinXT: ..."` string on failure, so callers test the type / prefix.
Bytes are `Data`; text (addresses, mnemonics, hex) is a String built in the script layer.

```
Keys and signatures:
  cxNewSeckey(pEntropy32)                 -> 32-byte seckey (validates; pEntropy from sxRandomBytes)
  cxPublicKey(pSeckey, pCompressed)       -> 33/65-byte pubkey
  cxSign(pSeckey, pHash32)                -> 64-byte ECDSA signature (RFC 6979)
  cxVerify(pPubkey, pHash32, pSig)        -> boolean
  cxSignRecoverable(pSeckey, pHash32)     -> 65-byte signature (r||s||v)      [Ethereum]
  cxRecover(pSig65, pHash32)              -> 65-byte pubkey                    [ecrecover]
  cxEcdh(pSeckey, pPubkey)                -> 32-byte shared secret
  cxSchnorrSign / cxSchnorrVerify         -> BIP-340                          [Taproot]

Hashes (thin over the shim; Data in, Data out):
  cxSha256, cxSha512, cxSha3_256, cxKeccak256, cxRipemd160,
  cxHash160 (RIPEMD160(SHA256(x))), cxHash256 (SHA256(SHA256(x))),
  cxHmacSha256, cxHmacSha512, cxPbkdf2HmacSha512

HD wallets (BIP-32):
  cxHdFromSeed(pSeed)                     -> node
  cxHdDerivePath(pNode, "m/44'/0'/0'/0/0") -> node   (splits the path, loops cnx_hdnode_derive)
  cxHdSeckey(pNode) / cxHdPubkey(pNode) / cxHdChainCode(pNode)
  cxXprv(pNode) / cxXpub(pNode)           -> Base58Check strings   (framed in script)

Mnemonics (BIP-39):
  cxMnemonicFromEntropy(pEntropy)         -> space-joined words   (checksum word computed in script)
  cxMnemonicToSeed(pWords, pPassphrase)   -> 64-byte seed
  cxMnemonicValidate(pWords)              -> boolean

Encodings (PURE SCRIPT, pinned by KAT):
  cxHexEncode / cxHexDecode
  cxBase58CheckEncode(pVersion, pPayload) / cxBase58CheckDecode(pString)   (fails closed on bad checksum)
  cxBech32Encode(pHrp, pWitVer, pProgram) / cxBech32Decode(pString)        (Bech32 and Bech32m)
  cxRlpEncode(pList) / cxRlpDecode(pBytes)                                 [Ethereum tx]

Addresses (compose the above):
  cxBtcAddressP2PKH(pPubkey, pMainnet)    -> Base58Check(0x00 || hash160(pubkey))
  cxBtcAddressP2WPKH(pPubkey, pMainnet)   -> Bech32("bc", 0, hash160(pubkey))
  cxBtcAddressP2TR(pXonly, pMainnet)      -> Bech32m("bc", 1, xonly)
  cxEthAddress(pPubkey)                   -> "0x" + EIP-55( keccak256(pub65[2..65])[13..32] )
  cxEthAddressChecksum(pAddress)          -> EIP-55 mixed-case form; verify on input
```

## 7. Formats CoinXT must get byte-exact (the spec inside the spec)

Each of these is a place a wallet silently loses money if a byte is wrong, so each is pinned by a public
test vector (section 9). Implement against the standard, not from memory.

- **secp256k1 / RFC 6979**: deterministic-`k` ECDSA; a signature must be reproducible and low-`s`
  (BIP-62 canonical) for Bitcoin. Ethereum wants the recovery id and low-`s` (EIP-2).
- **Keccak-256 vs SHA3-256**: Ethereum uses Keccak with the ORIGINAL `0x01` padding, not FIPS-202's
  `0x06`. Two different functions; never alias them.
- **Ethereum address**: `keccak256(uncompressed_pubkey_without_0x04_prefix)`, take the last 20 bytes,
  render lowercase hex with `0x`, then apply the **EIP-55** checksum (uppercase a hex nibble where the
  matching nibble of `keccak256(lowercase_address)` is >= 8). Verify the checksum on any address the app
  accepts.
- **Base58Check**: `base58( payload || first4(sha256(sha256(version||payload))) )`. Decode must recompute
  and compare the 4-byte checksum and fail closed.
- **Bech32 / Bech32m**: the two differ only by the polymod constant (1 vs 0x2bc830a3). SegWit v0 uses
  Bech32; v1+ (Taproot) uses Bech32m. The HRP, the witness-version byte, and the 5-bit squashing must all
  be exact, and the checksum verified on decode.
- **BIP-32**: `I = HMAC-SHA512(chaincode, data)`; `IL` tweaks the key, `IR` is the new chaincode;
  hardened indices (>= 0x80000000) use the private key, non-hardened use the public key. xprv/xpub is a
  Base58Check blob with the version bytes for main/test net.
- **BIP-39**: entropy (128-256 bits) + a checksum of `first (entropy_bits/32)` bits of `sha256(entropy)`
  -> 11-bit word indices into the 2048-word list; seed = `PBKDF2-HMAC-SHA512(mnemonic, "mnemonic" +
  passphrase, 2048, 64)`. The wordlist is data, shipped and hashed.
- **RLP**: the recursive length-prefix encoding Ethereum transactions use; single bytes < 0x80 are
  literal, else a length-of-length scheme. Pure bytes; pin the yellow-paper examples.

## 8. Security model and honesty rules

1. **Add no cryptography. Wrap trezor-crypto.** Every curve op, hash, and KDF is upstream, audited code.
   A missing primitive is an upstream request or a new vendored file, never a hand-rolled scalar mult or
   hash here. (The family's first rule; it counts double for money.)
2. **The app owns key custody.** CoinXT holds a key only for the microseconds of an operation. The app is
   responsible for where seeds and seckeys are stored, how they are backed up, and for a
   confirm-before-sign step. Document the boundary loudly.
3. **Secret hygiene across the FFI.** Private keys, seeds, and chaincodes cross as `Data` / `Pointer`,
   are `memzero`ed in the shim after use, and are NEVER returned as a bridged C string. The livecodescript
   layer clears its own key variables (`put empty into tSeckey`) as soon as it is done. Note the honest
   limit: OXT script variables are not locked memory, so a seed in script can be paged; treat the desktop
   as the trust boundary and say so.
4. **Fail closed on every malformed input.** A bad checksum (Base58Check / Bech32 / EIP-55), an
   out-of-range scalar, a wrong-length buffer, a non-canonical signature: clean error, never a
   wrong-but-plausible key or address. Verify every checksum on decode.
5. **Sign only what the app constructed.** CoinXT signs a 32-byte hash; it does not build your sighash or
   your transaction preimage for you in phase 1 (that is phases 4-5, and even then the app confirms the
   decoded human-readable intent). A blind signer is a footgun; make the caller pass the exact digest.
6. **Constant-time is upstream's job, within limits.** We rely on trezor-crypto's side-channel hardening;
   we do not add timing-variable branches on secret data in the shim, and we do the secret-free formatting
   (base58/bech32) in script where timing does not matter. Note that a general-purpose desktop is not a
   side-channel-hardened environment; do not market CoinXT as hardware-wallet-grade isolation.
7. **Mainnet vs testnet is explicit.** Version bytes and HRPs are parameters, never guessed; the default
   is spelled out at each call site.

## 9. Testing and conformance

Pin every deterministic path with public known-answer vectors in `tools/coin-kat.py` (the OnionXT
`onion-kat.py` model: self-checking, runs in CI, cross-checked against an independent implementation
before pinning). Sources:

- **secp256k1 / ECDSA**: RFC 6979 test vectors; a fixed privkey -> pubkey; a signed digest -> exact
  signature; `ecrecover` round-trip; a Schnorr vector from the BIP-340 test file.
- **Hashes**: `keccak256("")` = `c5d2460186f7...`, `sha3_256("")`, a RIPEMD-160 vector, an HMAC-SHA512
  vector, a PBKDF2-HMAC-SHA512 vector.
- **Ethereum address + EIP-55**: the canonical checksum examples from EIP-55.
- **BIP-32**: the official BIP-32 test vectors (seed -> xprv/xpub and derived paths).
- **BIP-39**: the Trezor BIP-39 vectors (entropy -> mnemonic -> seed).
- **Base58Check / Bech32 / Bech32m**: the BIP-173 / BIP-350 test vectors, valid and INVALID (a corrupt
  checksum must be rejected).
- **RLP**: the yellow-paper / EIP examples.

The curve and hash correctness is trezor-crypto's (its own test suite); CoinXT's KATs prove the *wrap*
and the *script-side encodings*, end to end from the `cx*` API. The wire behaviour that needs a real
chain (broadcast, confirmation) is out of scope and belongs to whatever app composes CoinXT.

## 10. Composition with the rest of the family

- **SodiumXT** supplies the entropy (`sxRandomBytes`) for fresh keys, and its `sxMemZero` / secure-buffer
  discipline is the model for secret hygiene. CoinXT does not duplicate libsodium; the hashes it needs
  (Keccak, RIPEMD-160, SHA-3) are ones libsodium does not have, which is why they come from trezor-crypto.
- **OnionXT** is the natural transport for anything CoinXT-signed that must reach a node privately: build
  and sign a transaction with CoinXT, then broadcast it through Tor with OnionXT so the submitting IP is
  not linked to the address. This is a documentation-level composition; neither library depends on the
  other.
- The offline SHA3-256 that OnionXT deferred (its gap #2) is provided here as `cnx_sha3_256`, so an app
  that loads CoinXT can hand OnionXT an offline v3-address checksum if it ever wants one.
