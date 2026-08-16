# CoinXT API Reference

**The `cx*` handlers that exist today, and nothing else.**

CoinXT is being built in phases (see [../IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md)).
[../SPEC.md](../SPEC.md) describes the *whole designed* API. This file is the opposite
document: it lists only what is shipped, so you can tell at a glance what you can actually
call. Hashes, the secp256k1 curve, the encodings and addresses (WIF included since
2026-08-15), HD wallets and mnemonics, and (phase 5) transaction building are all shipped;
only Schnorr/Taproot is not.

> **Status.** **Eighty** public handlers exist across two layers: **35** in the `.lcb`
> extension (hashes, the curve, the BIP-32 tweaks and the BIP-39 wordlist) and **45** in
> `src/coinxt.livecodescript` (encodings, addresses, mnemonics, HD derivation and the
> phase-5 transaction builders). The two load differently - see the phase-3 section.
>
> **Phase 5 (transaction building) is ENGINE-PASSED (2026-08-12).** The Bitcoin path reproduces
> the BIP-143 native-P2WPKH worked example byte for byte in `tools/coin_reference.py`, and the
> Ethereum paths reproduce the EIP-155 specification example and a self-consistent EIP-1559
> typed transaction. Since 2026-08-11 all thirteen handlers are also driven THROUGH THE SCRIPT
> by `tools/check-script-vectors.py` (251 checks) against those same vectors, with the encoders
> fed the oracle's own deterministic signatures - the same headless-execution net phases 3 and
> 4 carry. That net immediately caught a defect no static gate could: `cxBtcTxEncode` refused
> to assemble the reference transaction outright, because its trailing empty scriptSig (input 1
> is segwit) collapses under the engine's one-trailing-delimiter chunk rule and tripped a strict
> parallel-list guard; it was fixed and pinned, and the 2026-08-12 engine run (Windows x64,
> 230/230 in the folded suite harness) confirmed it: the whole signed transaction matched
> BIP-143 byte for byte on a real engine, with both new refusals firing as designed.
>
> **The independent-decoder bar is now MET (2026-08-12).** A FRESH native-P2WPKH transaction
> - new key, new amount, a prevout and destination this repo has never pinned - was built
> end to end by `src/coinxt.livecodescript` (its sighash, DER, varint, witness and
> serialization, driven through `tools/lcs-interp.py`) and handed to **python-bitcointx 1.1.5**
> (the maintained python-bitcoinlib fork, a full consensus-shaped script interpreter over
> libsecp256k1). It deserialized the script's bytes, ran `VerifyScript` under
> `SCRIPT_VERIFY_WITNESS`, and confirmed the signature against its own independently-computed
> BIP-143 sighash; a flipped signature byte and a +1-satoshi wrong amount were both rejected,
> so the verdict is not vacuous. `tools/verify-independent-decoder.py` is that acceptance run
> (not a CI gate - it needs the pip packages python-bitcointx + coincurve, so it SKIPS loudly
> without them). **Extended 2026-08-13 to all four shipped families**: a fresh legacy P2PKH
> spend passes the same consensus evaluation (python-bitcointx's own legacy sighash included,
> with a tampered-output negative control), and fresh EIP-155 and EIP-1559 transactions
> (chain id 137, wei values above 2^53) are accepted by **eth-account** - the recovery
> library web3.py itself uses - which recovers the exact sender from the script-built bytes,
> an independent RLP decode confirming every field; 31 checks, a negative control firing in
> every family. **The last bar is a live testnet broadcast**; until then "broadcastable" stays
> unclaimed, but transactions CoinXT builds are now known to be accepted by code we did not
> write, in every family it ships.
>
> **Every phase has now run on a real engine.** *Phase 1, the hash surface,* was closed by an
> engine pass on **2026-08-08**: the binding loaded and returned its pinned vectors byte-exact.
> *Phases 2, 3 and 4* were closed on **2026-08-10**: the member harness ran folded into the
> suite selftest (`tests/suite-selftest.livecodescript` at the repository root), 205/206 on the
> first pass and **207/207** on the same-day re-run. The one red line was a genuine engine
> parser difference no gate had modelled - `cxHdDerivePath` of `"m/"` returned its node
> unchanged because the engine counts one trailing delimiter out of existence - fixed the same
> day, and the refusal observed green in the re-run. *Phase 5* was closed on **2026-08-12**
> (Windows x64): the folded harness ran the whole surface at **230/230**, transactions included.
> The one exception since: the two WIF handlers (2026-08-15) postdate those passes and are
> **verified statically; needs an OXT pass** - executed headlessly by the vector gate against
> the Bitcoin wiki's published worked example, never yet on an engine.
> The native side remains cross-verified on
> every push: CoinXT reproduces four published RFC 6979 signatures byte for byte, a CoinXT
> signature verifies in the independent Python `ecdsa` library, and recovery round-trips to
> the signer.
>
> **Not shipped, despite appearing in SPEC.md:** `cxSchnorrSign`/`cxSchnorrVerify` and
> `cxXonlyFromSeckey` (deferred with Taproot: trezor-crypto's plain-C tree has no BIP-340).
> Calling any of them is a `handler not found`.

## Before anything else

The extension is `org.openxtalk.library.coin`. Install it like any OXT extension; the native
library resolves automatically from inside it.

Two probes, in this order:

```
cxCheckABI                 -- a COMMAND. Silence is the pass; it THROWS on skew.
put cxKeccak256Len()       -- prints 32. The probe that actually returns a value.
```

`cxCheckABI` is declared `returns nothing`, so `put cxCheckABI()` prints a blank line and
proves nothing. Call it bare, as a command. A `handler not found` from either means the
extension is not installed or did not load.

## The shape every handler shares

- **Bytes in, bytes out.** Every input is a `Data` and every digest output is a `Data`. Use
  `textEncode(tString, "utf-8")` to hash text, and pin that encoding: hashing a `String`
  directly leaves the engine free to re-encode it, and a different encoding is a different
  digest.
- **Synchronous and stateless.** CoinXT does no I/O, holds no handles, starts no threads, and
  has nothing to close. There is no session, no poll, no teardown. Re-entrancy is not a
  concern.
- **Deterministic.** Same input, same output, on every platform. That is what makes every
  path known-answer testable, and `tools/coin-kat.py` tests all of them.
- **Errors throw.** A failure raises a string beginning `"CoinXT:"` and naming the handler.
  There is no error-code return and no partial result. Catch with `try ... catch tError`.
- **Every call re-checks the ABI.** Each handler begins by verifying the loaded library
  reports ABI 5, and throws if not, so a mismatched library cannot silently produce garbage.
  (ABI 5, 2026-08-16, is an internal secret-hygiene change - see "Secret hygiene, honestly"
  below. It adds no public handler and changes no signature.)
- **An empty `Data` is legal input** for every digest and for both HMAC slots. It returns the
  documented empty-input digest rather than throwing. This was the binding's one genuinely
  open marshalling question and the 2026-08-08 engine pass settled it.

## The ABI guard

### `cxCheckABI`

```
cxCheckABI
```

A command. Returns nothing. Throws if the loaded native library does not report ABI 5, with
an error telling the user to reinstall the packaged extension. Silence is the pass.

You rarely need to call it explicitly, because every other handler performs the same check
first. It exists so an app can fail loudly at startup instead of at first use.

## One-shot digests

All five take one `Data` and return a `Data` of the fixed size below.

| Handler | Digest | Bytes | Notes |
|---|---|---|---|
| `cxKeccak256(pData)` | Keccak-256 | 32 | **Ethereum's** hash. Not SHA3-256. See the footgun below. |
| `cxSha3_256(pData)` | SHA3-256 | 32 | **NIST** SHA-3. Not Keccak-256. |
| `cxSha256(pData)` | SHA-256 | 32 | FIPS 180-4. Bitcoin's workhorse. |
| `cxSha512(pData)` | SHA-512 | 64 | FIPS 180-4. |
| `cxRipemd160(pData)` | RIPEMD-160 | 20 | The second half of Bitcoin's HASH160. |

```
local tDigest
put cxKeccak256(textEncode("abc", "utf-8")) into tDigest
-- 32 bytes: 4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45
```

> ### The Keccak-256 vs SHA3-256 footgun
>
> These two differ by **one padding byte** and nothing else. They are not interchangeable, and
> a mix-up does not fail loudly: it returns a perfectly well-formed 32-byte digest that is
> simply wrong. On Ethereum that means a wrong address, and funds sent to it are gone.
>
> **Ethereum uses Keccak-256** (`cxKeccak256`), the pre-standardisation variant. Anything
> citing FIPS 202 or "SHA-3" means `cxSha3_256`. When a spec just says "sha3", check which one
> it means before you pick; for anything Ethereum, it is `cxKeccak256`.
>
> `tests/coin-selftest.livecodescript` asserts the two are distinct in both directions, and
> `tools/check-selftest-vectors.py` refuses to let those two constants drift into agreement.

## Keyed hashing

### `cxHmacSha256(pKey, pMessage)` / `cxHmacSha512(pKey, pMessage)`

HMAC per RFC 2104. Returns 32 and 64 bytes respectively. Both arguments are `Data`, and either
may be empty. Key length is unrestricted: HMAC hashes an over-long key and zero-pads a short
one, internally.

```
put cxHmacSha256(tKey, textEncode("Hi There", "utf-8")) into tMac
```

**Do not compare a MAC with `is` or `=`.** That is a timing leak. CoinXT does not ship a
constant-time compare in phase 1; compose SodiumXT's `sxMemEqual` if it is installed, and if
it is not, treat the comparison as a known weakness rather than pretending otherwise.

## Key derivation

### `cxPbkdf2HmacSha512(pPassword, pSalt, pIterations, pOutLen)`

PBKDF2-HMAC-SHA512. Returns exactly `pOutLen` bytes.

This is the BIP-39 mnemonic-to-seed KDF, and the argument shape is chosen for that use: the
salt is the literal string `"mnemonic"` followed by the passphrase, the iteration count is
2048, and the output is 64 bytes.

```
local tSeed
put cxPbkdf2HmacSha512(textEncode(tMnemonic, "utf-8"), \
                       textEncode("mnemonic" & tPassphrase, "utf-8"), 2048, 64) into tSeed
```

Unlike the digests, the caller chooses the output length, so this is the one handler whose
size is not fixed. It is also the only one with argument validation of its own, and it fails
closed rather than quietly doing something useless:

- `pOutLen` below 1 throws. A zero-length key is never what you meant.
- `pIterations` below 1 throws, and the error says why: a count of 0 would silently derive a
  one-iteration key, which looks like a working KDF and offers no work factor at all.
- `pIterations` above 2147483647 throws rather than wrapping.

PBKDF2 output is prefix-consistent: asking for 20 bytes returns exactly the first 20 bytes of
the 64-byte answer. That is a property of the construction, and the self-test pins it.

## The secp256k1 curve

Everything in this section is phase 2. **CoinXT is a calculator, not a wallet:** it holds a
private key for the microseconds of one call and keeps nothing. Storage, backup, and
confirm-before-sign are your application's job.

### `cxNewSeckey(pEntropy)` / `cxSeckeyIsValid(pSeckey)`

`cxNewSeckey` validates 32 bytes of **your** entropy as a private key and returns them
unchanged. There is no transformation, because a secp256k1 private key just *is* a 32-byte
integer in `[1, n-1]`; roughly one draw in 2^128 fails, so the honest API checks and hands back
rather than pretending to generate. **The entropy must be cryptographically random** - compose
SodiumXT's `sxRandomBytes(32)` or the OS. CoinXT deliberately has no key-making RNG of its own,
so nothing here can quietly hand you a weak key. It throws if the bytes are not a valid key.

`cxSeckeyIsValid` asks the same question and returns a **Boolean** instead of throwing, for an
imported key (a pasted hex string, a decoded WIF) where "no" is an ordinary answer. Empty, wrong
length, zero, and `>= n` all answer `false`.

### `cxPublicKey(pSeckey, pCompressed)` / `cxPubkeyDecompress(pPubkey)`

`cxPublicKey` returns 33 bytes (`0x02`/`0x03` || X) when `pCompressed` is true, and 65 bytes
(`0x04` || X || Y) when it is false. Compressed is what modern Bitcoin uses; the uncompressed
form is what an Ethereum address is built from (Keccak-256 of the 64 bytes *after* the `0x04`,
last 20 bytes). `cxPubkeyDecompress` expands a compressed key to 65 bytes, and passing it an
already-uncompressed key returns it unchanged, so code normalising mixed input need not branch.

### `cxSign(pSeckey, pDigest)` / `cxVerify(pPubkey, pDigest, pSignature)`

`cxSign` takes a **32-byte digest** and returns a 64-byte signature (r || s). It is RFC 6979
deterministic: the same key and digest always give the same bytes. `s` is always the low of the
two equivalent values, which Bitcoin relay policy (BIP-62) and Ethereum consensus both require.

> **Sign only what you built.** `cxSign` will sign any 32 bytes you hand it. Constructing the
> correct sighash or transaction preimage, and showing the user what it means, is your job.
> CoinXT does not know what it is signing, and a blind signer is a footgun aimed at whoever
> installed your app.

`cxVerify` returns a **Boolean**, and the split is deliberate: `false` means the signature does
not verify, which is a normal answer you branch on, while a malformed public key or a 63-byte
signature **throws**, because that is a bug in your code. A verify that threw on an invalid
signature would be unusable; one that answered `false` to a malformed key would hide the bug
behind a security-shaped result.

### `cxSignRecoverable(pSeckey, pDigest)` / `cxRecover(pSignature, pDigest)`

`cxSignRecoverable` returns 65 bytes: the same signature with a 1-byte recovery id (0..3)
appended. Ethereum's `v` is built from that id. `cxRecover` takes those 65 bytes plus the digest
and returns the 65-byte public key that produced them.

> **Recovery succeeding proves nothing on its own.** A well-formed signature recovers *some*
> key for any recovery id. It is meaningful only when you compare the recovered key against the
> key you expected. Skipping that comparison is the classic `ecrecover` mistake.

### `cxEcdh(pSeckey, pPubkey)`

Returns the raw 65-byte shared point (`0x04` || X || Y).

> **This is not a shared key.** Every protocol that uses ECDH runs a KDF over this point first,
> and they disagree about which one and about whether it covers X alone or the compressed form.
> Hashing it here would be CoinXT inventing a convention and calling it interoperability, so you
> get the point and supply the KDF your protocol specifies (`cxSha256` of the 32 X bytes is a
> common one - match the other end, do not guess).

## Encodings and addresses (phase 3)

Everything in this section lives in **`src/coinxt.livecodescript`**, not in the
`.lcb` extension, and that difference is load-bearing for you: it is a script, so
it has to be in the message path before its handlers resolve.

```
start using stack "coinxt"     -- if you wrap the script in a stack
-- or insert the script of the library into the back / a library stack
```

If every handler below reports `handler not found` while the hashes and the
curve work, that is the symptom: the extension loaded, the script did not.

These are pure byte work - no key material, no curve points, nothing secret -
which is exactly why they are script and not C (see `../CLAUDE.md`, "The
C-vs-script split"). Every decoder **verifies its checksum and throws** rather
than returning a plausible wrong answer.

### `cxHexEncode(pData)` / `cxHexDecode(pHex)`

Lowercase hex out; upper, lower or mixed case accepted in. `cxHexDecode` throws
on an odd length and on any non-hex character, rather than skipping it.

### `cxHash160(pData)` / `cxHash256(pData)`

`RIPEMD160(SHA256(x))` and `SHA256(SHA256(x))`. Named because Bitcoin names
them, and because writing them out at each call site is how one of them ends up
being SHA-256 twice.

### `cxBase58CheckEncode(pPayload)` / `cxBase58CheckDecode(pText)`

The payload followed by the first 4 bytes of `cxHash256(payload)` - how a
mainnet address, a WIF key and an xprv are all framed. **The decoder verifies**:
a corrupt string throws, it never returns the payload it happened to decode.
Leading zero bytes survive as leading `1` characters, one for one, which is why
a mainnet P2PKH address starts with a `1`.

### `cxWifEncode(pSeckeyHex, pNetwork, pCompressed)` / `cxWifDecode(pWif)`

Wallet Import Format: Base58Check over `version || 32-byte key || optional
0x01 compressed marker`, version `0x80` on mainnet and `0xEF` on testnet.
Shipped 2026-08-15; **verified statically (needs an OXT pass)** - executed
headlessly by `tools/check-script-vectors.py` against oracle-derived vectors
anchored to the Bitcoin wiki's published worked example, both directions plus
the refusals, but these two handlers postdate the engine passes above.

| Handler | Takes | Returns |
|---|---|---|
| `cxWifEncode(pSeckeyHex, pNetwork, pCompressed)` | the key as **64 hex characters**; `"mainnet"` or `"testnet"`; `true` / `false` | the WIF string (`5...` / `K...` / `L...` on mainnet) |
| `cxWifDecode(pWif)` | a WIF string | an array: `seckey` (64 lowercase hex), `network` (`"mainnet"` / `"testnet"`), `compressed` (Boolean) |

The key crosses as **hex text**, not `Data`, in both directions - WIF is the
paste-in / paste-out format, so the key arrives and leaves as text, the same
convention the transaction layer uses for txids and scripts. Run
`cxHexDecode` over the decoded `seckey` before handing it to `cxSign` or
`cxPublicKey`, and note the decoded `compressed` flag: it says which public
key form the funds are held under, so deriving the other form pays a
different address.

**Both directions fail closed.** The encoder refuses a key that is not 64 hex
characters, an unknown network name, a compressed flag that is not literally
`true` or `false`, and a scalar that is zero or at or above the group order
(the range check is `cxSeckeyIsValid`, so a checksummed WIF of an unusable
key can never be produced). The decoder throws on a bad character or
checksum (inside `cxBase58CheckDecode`, whose message stands), a payload that
is not 33 or 34 bytes, a version byte that is neither `0x80` nor `0xEF`, a
trailing byte that is not the `0x01` marker, and the same out-of-range
scalar. A typo in a pasted key is refused, never coerced into a plausible
neighbouring wallet.

### `cxBech32EncodeValues(pHrp, pValues, pSpec)` / `cxBech32DecodeValues(pText)`

The raw bech32 layer, below the addresses. `pValues` is a comma-separated list
of 5-bit numbers and `pSpec` is `"bech32"` or `"bech32m"`. The decoder returns
an array with `hrp`, `spec` and `values`, and **reports which encoding
verified** rather than accepting either - that is what lets the address layer
enforce the BIP-350 pairing. Most callers want the address handlers instead.

### `cxSegwitAddressEncode(pHrp, pVersion, pProgram)` / `cxSegwitAddressDecode(pHrp, pAddress)`

SegWit addresses. The encoding follows from the witness version, per BIP-350:
**v0 uses bech32, v1-v16 use bech32m**. The decoder enforces that pairing, the
2-to-40 byte program range, the exact 20-or-32 bytes v0 requires, the 90
character cap, the mixed-case ban, and canonical padding. `cxSegwitAddressDecode`
returns an array with `version` and `program`, and throws if the address is for a
different network than the `pHrp` you asked for.

### The address builders

| Handler | Produces | Takes |
|---|---|---|
| `cxBtcAddressP2PKH(pPubkey)` | `1...` | a compressed or uncompressed key |
| `cxBtcAddressP2WPKH(pPubkey)` | `bc1q...` | a **33-byte compressed** key only |
| `cxBtcAddressP2TR(pOutputKey)` | `bc1p...` | a **32-byte x-only output key** |
| `cxEthAddress(pPubkey)` | `0x...` lowercase | a compressed or uncompressed key |
| `cxEthAddressChecksum(pAddress)` | `0x...` EIP-55 mixed case | any casing, with or without `0x` |
| `cxEthAddressIsChecksummed(pAddress)` | Boolean | an address to verify |

Three of those are refusals rather than conveniences, and each is a way people
lose money:

- **`cxBtcAddressP2WPKH` rejects an uncompressed key.** A v0 SegWit output built
  from one is unspendable by every modern wallet.
- **`cxBtcAddressP2TR` takes the TWEAKED output key**, not an internal key.
  BIP-341 defines the output key as `Q = P + int(tagged_hash(P || merkle_root))G`,
  and computing that needs the BIP-340 surface CoinXT has deferred with Taproot.
  Handing it a raw internal key produces a valid-looking address nobody can spend
  from. If you do not already know your key is tweaked, it is not.
- **`cxEthAddressIsChecksummed` returns `false` for an all-lowercase address.**
  Such an address carries no checksum at all, and reporting it as valid would
  quietly retire the protection EIP-55 exists to give.

### `cxRlpEncodeBytes(pData)` / `cxRlpEncodeList(pEncodedItems)` / `cxRlpDecode(pData)`

Ethereum's Recursive Length Prefix - what stands between `cxSignRecoverable` and
a broadcastable transaction. The API is built from pieces because xTalk has no
nested-list literal: encode each field with `cxRlpEncodeBytes`, concatenate, and
wrap with `cxRlpEncodeList`.

```
put cxRlpEncodeBytes(tNonce) & cxRlpEncodeBytes(tGasPrice) into tFields
put cxRlpEncodeList(tFields) into tEncoded
```

`cxRlpDecode` returns one item as an array with `kind` (`"bytes"` or `"list"`),
`payload` and `rest`; you walk a list by decoding its payload in a loop. It
**rejects the non-canonical forms** - a single byte below `0x80` wrapped in a
length prefix, a leading zero in a long length, a long form used for a short
value - because RLP's guarantee is that one value has exactly one encoding, and
a decoder that accepts two spellings breaks every hash computed over the result.

## HD wallets and mnemonics (phase 4)

BIP-39 mnemonics, BIP-32 derivation and the BIP-44 / BIP-84 paths a wallet
walks. Like phase 3 these live in `src/coinxt.livecodescript`, not in the `.lcb`
module; `start using stack "coinxt"` before calling them.

**This is the part of CoinXT that can be wrong without failing.** A signature
that is wrong does not verify and an address that is wrong fails its checksum,
but a mis-derived wallet produces perfectly valid keys for the wrong account.
Everything here is pinned to a published vector for that reason. Check your own
integration the same way: derive `m/44'/0'/0'/0/0` from the test mnemonic
`abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon
abandon about` and confirm you get `1LqBGSKuX5yYUonjxT5qGfpUsXKYYWeabA` before
you point it at real funds.

### `cxMnemonicFromEntropy(pEntropy)` / `cxMnemonicToEntropy(pMnemonic)`

16, 20, 24, 28 or 32 bytes of entropy to 12, 15, 18, 21 or 24 words, and back.
**CoinXT does not generate the entropy** - it is yours, from a source you trust
(SodiumXT `sxRandomBytes`), for the same reason `cxNewSeckey` takes bytes rather
than making them. `cxMnemonicToEntropy` verifies the checksum and throws if a
word is wrong, missing or out of order.

### `cxMnemonicValidate(pMnemonic)`

True or false, not a throw, because a restore screen asks this on every
keystroke and an exception is the wrong shape for an answer that is routinely
no.

### `cxMnemonicToSeed(pMnemonic, pPassphrase)`

The 64-byte BIP-39 seed. **It does not verify the checksum** - BIP-39 defines
the seed for any string, which is what lets other schemes reuse the KDF, but it
means a typo yields a perfectly good seed for the wrong wallet. Call
`cxMnemonicValidate` first on anything a human typed.

Whitespace is normalized first (`cxMnemonicNormalize`: trim, and collapse runs
to one space), because BIP-39 derives the seed from the mnemonic STRING and a
trailing newline from a paste would otherwise give a different wallet from every
other implementation. Unicode NFKD is **not** applied: for the English wordlist
that is a no-op, but **a non-ASCII passphrase is yours to normalize** before
calling, or your seed will not match a wallet that did.

### `cxHdFromSeed(pSeed)` / `cxHdDeriveChild(pNode, pIndex)` / `cxHdDerivePath(pNode, pPath)`

A node is an array with the fields BIP-32 serializes, in the order it serializes
them: `seckey` (empty for a watch-only node), `pubkey` (33 bytes, compressed),
`chaincode`, `depth`, `index`, `parentfp`.

```
put cxHdFromSeed(cxMnemonicToSeed(tMnemonic, "")) into tMaster
put cxHdDerivePath(tMaster, "m/44'/0'/0'/0/0") into tAccount
put cxBtcAddressP2PKH(tAccount["pubkey"]) into tAddress
```

A path level may carry `'`, `h` or `H` for hardened. The parse is strict on
purpose: a level that is not plain digits throws rather than being coerced,
because `m/1e3` quietly becoming 1000 is a different wallet with no error
anywhere.

### `cxHdNeuter(pNode)`

The watch-only form: same public key and chain code, no private key. This is the
xpub half of a wallet. It still derives non-hardened children - and therefore
every receive address on that branch - which is what makes an xpub both useful
and a privacy liability if it leaks. It cannot derive a hardened child, because
BIP-32 hashes the private key to make one; that is the property hardened
derivation exists for.

### `cxXprv(pNode)` / `cxXpub(pNode)`

The Base58Check serializations. Mainnet only: a testnet or altcoin prefix is a
different version number and nothing else, but CoinXT does not ship one it has
not pinned to a vector.

### `cxSeckeyTweakAdd` / `cxPubkeyTweakAdd` / `cxBip39Wordlist`

The `.lcb` primitives the above is built from. Most callers want the handlers
above instead; these are public because the script layer is a separate file and
because a caller implementing a non-BIP-32 scheme on the same curve has a real
use for a tweak. `cxBip39Wordlist()` returns the 2048 words as 8-byte
space-padded slots (16384 bytes), which is what an autocomplete in a mnemonic
entry field wants.

## Transactions (phase 5)

Thirteen handlers that assemble and sign Bitcoin and Ethereum transactions by
composing the primitives above. **This layer produces the digest; the app
signs it** (`cxSign` for Bitcoin, `cxSignRecoverable` for Ethereum) and confirms
the decoded human intent first - a blind signer is a footgun. Repeated fields
(a transaction's inputs and outputs) cross as **comma-separated lists of hex**,
one item per input or output, the same convention the RLP and bech32 layers use.

> **Engine-passed 2026-08-12 (230/230, Windows x64), executed headlessly on every
> push, and verified against `tools/coin_reference.py`.** The reference model
> reproduces the BIP-143 native-P2WPKH worked example, the EIP-155 spec example
> and a self-consistent EIP-1559 transaction; `tools/check-script-vectors.py`
> drives all thirteen handlers THROUGH THE script against those vectors (the
> encoders fed the oracle's own deterministic signatures); and the engine run
> reproduced the BIP-143 signed transaction byte for byte. An independent
> decoder now accepts fresh transactions in all four families (see the status
> block at the top); nothing here is called broadcastable until a testnet
> node accepts one too.

> **A note on the list convention, learned by running it.** A repeated field
> whose LAST entry is empty (e.g. `scriptSigs` = `[sig, ""]` for a legacy input
> followed by a segwit one) serializes to `"<sig>,"`, and the engine counts that
> as ONE item, not two, because it ignores one trailing delimiter. So
> `cxBtcTxEncode` reads every list BY INDEX (a missing entry is an empty
> scriptSig / witness, which is its correct meaning) and validates only that a
> list is not LONGER than the input count; a shorter list is indistinguishable
> from trailing empties and is read as such. `pSequences` is the exception and
> must have exactly one entry per input (a sequence is never empty).

**Byte helpers.**

- `cxVarInt(pN)` - Bitcoin CompactSize (1/3/5/9 bytes) as `Data`.
- `cxDerEncode(pCompactSig)` - a 64-byte compact `r || s` (the `cxSign` shape)
  to a DER signature. The `SIGHASH` type byte is the caller's to append.

**Bitcoin.** Amounts and counters are integers (a satoshi amount stays inside
exact-integer range); a `scriptCode` is passed BARE and this layer adds its
length prefix.

- `cxBtcOutpoint(pTxidHex, pVout)` - a 36-byte outpoint from a display-order
  txid and an index (txid byte-reversed, LE index).
- `cxBtcOutput(pAmountSat, pScriptHex)` - a serialized output (LE amount +
  CompactSize script length + script).
- `cxBtcSighashLegacy(pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex,
  pOutputs, pLocktime, pSighashType)` - the pre-SegWit SIGHASH_ALL preimage
  digest for 1-based input `pIndex`.
- `cxBtcSighashSegwit(pVersion, pOutpoints, pSequences, pIndex, pScriptCodeHex,
  pAmountSat, pOutputs, pLocktime, pSighashType)` - the BIP-143 preimage digest
  (commits to the input amount AND to `hashOutputs` - `pOutputs` is required, it
  is the commitment that binds the signature to where the coins go).
- `cxBtcWitness(pItems)` - a serialized witness stack from a comma list of item
  hex (`""` for an input with no witness).
- `cxBtcTxEncode(pVersion, pOutpoints, pScriptSigs, pSequences, pWitnesses,
  pOutputs, pLocktime)` - the raw transaction; emits the BIP-141 marker+flag and
  witness section when any witness is non-empty.
- `cxBtcTxid(pVersion, pOutpoints, pScriptSigs, pSequences, pOutputs, pLocktime)`
  - the display-order txid (hash256 of the non-witness serialization, reversed).

**Ethereum.** Wei-scale fields (`pGasPriceHex`, `pValueHex`, the 1559 fee caps)
cross as minimal big-endian **hex** because they exceed exact-integer range; the
counters (`pNonce`, `pGas`, `pChainId`, `pRecid`) are integers. `pToHex` is the
20-byte recipient (`""` for a contract creation); `pRHex`/`pSHex` are the
compact `r`/`s` from `cxSignRecoverable`.

- `cxEthLegacySighash(pNonce, pGasPriceHex, pGas, pToHex, pValueHex, pDataHex,
  pChainId)` - the EIP-155 signing digest.
- `cxEthLegacyEncode(pNonce, pGasPriceHex, pGas, pToHex, pValueHex, pDataHex,
  pChainId, pRecid, pRHex, pSHex)` - the signed legacy transaction; returns an
  array `["raw"]`, `["txhash"]` (both hex). `v = pRecid + 2*pChainId + 35`.
- `cxEth1559Sighash(pChainId, pNonce, pMaxPriorityHex, pMaxFeeHex, pGas, pToHex,
  pValueHex, pDataHex)` - the EIP-1559 (type 0x02) signing digest, empty access
  list.
- `cxEth1559Encode(pChainId, pNonce, pMaxPriorityHex, pMaxFeeHex, pGas, pToHex,
  pValueHex, pDataHex, pRecid, pRHex, pSHex)` - the signed typed transaction;
  returns `["raw"]`, `["txhash"]`.

## Length accessors

Fourteen zero-argument handlers returning the sizes the library actually reports.

| Handler | Returns |
|---|---|
| `cxKeccak256Len()` | 32 |
| `cxSha3_256Len()` | 32 |
| `cxSha256Len()` | 32 |
| `cxSha512Len()` | 64 |
| `cxRipemd160Len()` | 20 |
| `cxHmacSha256Len()` | 32 |
| `cxHmacSha512Len()` | 64 |
| `cxSeckeyLen()` | 32 |
| `cxPubkeyLenCompressed()` | 33 |
| `cxPubkeyLenUncompressed()` | 65 |
| `cxSignatureLen()` | 64 |
| `cxRecoverableSignatureLen()` | 65 |
| `cxEcdhLen()` | 65 |
| `cxBip39WordlistLen()` | 16384 (2048 words x 8) |

These are not decoration. **Do not hardcode 32 or 64 in your own code**; ask. A library is
entitled to change a digest size across versions, and a hardcoded length is a buffer overflow
waiting to happen. The binding itself follows this rule: every wrapper sizes its output buffer
from the matching accessor rather than from a literal, which is why a wrong length would break
the digest rather than hide.

Under the hood these are the one genuinely novel thing in the binding: they marshal a C
`size_t` as a foreign `UIntSize` **return** type, which this extension family had previously
proven only as a parameter. The 2026-08-08 engine pass confirmed it works.

## A note on `the itemDelimiter`

The script layer moves data as comma-separated lists internally, and an `item`
chunk reads whatever the engine's delimiter currently is. That property is
global mutable state, so an app that sets it and does not restore it would once
have got silently wrong answers here.

**You no longer have to think about this.** The nine handlers that read item
chunks save the delimiter, set it to comma for the duration, and hand your
setting back before returning - including when they throw. Call them with the
delimiter set to anything you like; they are indifferent to it and they will not
change it on you. The vector gate checks both halves of that on every push.

## Errors

Every failure is a thrown string starting `"CoinXT:"`. The forms you can encounter:

| Error | Meaning |
|---|---|
| `CoinXT: ABI mismatch - ...` | The bundled native library does not match the extension. Reinstall; they ship together. |
| `CoinXT: <handler>: a required buffer was missing (null).` | A required buffer did not marshal. |
| `CoinXT: <handler>: a buffer had the wrong length.` | A fixed-size buffer was the wrong size. |
| `CoinXT: <handler>: a length or count is out of the range ...` | A length the native primitive cannot represent. |
| `CoinXT: <handler>: the key is not a valid secp256k1 key.` | A private key outside `[1, n-1]`, or a public key that is malformed, off-curve, or whose length disagrees with its prefix byte. |
| `CoinXT: <handler>: the signature is malformed or does not verify.` | From `cxRecover`, an unusable signature or a recovery id above 3. (From `cxVerify` this is not an error at all: it returns `false`.) |
| `CoinXT: <handler>: the operating system entropy source is unavailable ...` | The curve code could not draw its side-channel blinding. Nothing was signed. |
| `CoinXT: <handler>: the digest is all zero ...` | Refused: a signature over an all-zero digest can be forged for any key. |
| `CoinXT: <handler>: the native curve library failed unexpectedly.` | Upstream failed in a way that maps to nothing above. |
| `CoinXT: <handler>: an unexpected native status ...` | The loaded library does not match this binding. |
| `CoinXT: cxPbkdf2HmacSha512: the output length must be at least 1 byte ...` | `pOutLen` below 1. |
| `CoinXT: cxPbkdf2HmacSha512: the iteration count must be at least 1 ...` | `pIterations` below 1. |
| `CoinXT: out of memory allocating an output buffer.` | The engine could not allocate the output. |
| `CoinXT: the native wipe refused a buffer this extension allocated ...` | Should be unreachable: the ABI guard has already matched, so `cnx_memzero` cannot refuse a live buffer. Seeing it means the loaded library changed underneath the extension. |

```
try
   put cxKeccak256(tData) into tDigest
catch tError
   answer "Hashing failed:" && tError
end try
```

## Secret hygiene, honestly

CoinXT zeroes its own scratch buffers in C, and since **ABI 5 (2026-08-16)** the binding
layer wipes its raw out-buffers too. Every block `src/coinxt.lcb` allocates for a result
used to be freed unwiped (the file said so rather than hiding it); it is now wiped through a
new shim export, `cnx_memzero(ptr, len)` - a wrap of the vendored trezor-crypto `memzero.c`,
the platform wipe a compiler cannot elide - before every `MCMemoryDeallocate`, on the
success path and on both error paths. That covers the outputs that are genuinely key
material (the `cxPbkdf2HmacSha512` seed, the `cxHmacSha512` output BIP-32 splits into a
child-key tweak and a chaincode, the `cxSeckeyTweakAdd` child private key, the `cxEcdh`
shared point) and, deliberately, every other out-buffer as well: classifying "secret enough
to wipe" per handler is a judgment that fails open when it is wrong. `cnx_memzero` is
internal to the binding - there is no public `cx*` wrapper, because a script `Data` cannot
be wiped in place and a handler that pretended otherwise would only invite false
confidence. The wipe contract is executed by the native gates (the ASan self-test and
`coin-kat.py`, including against the committed Linux x86_64 library); the `.lcb` call sites
that route through it are verified statically and await an OXT pass.

What none of that can protect is the `Data` CoinXT hands back.

An OXT script variable is not locked memory: it can be paged to disk, it is not reliably
zeroed when it goes out of scope, and the engine may copy it. So a seed returned by
`cxPbkdf2HmacSha512` lives in ordinary memory for as long as your variable holds it. Clear it
(`put empty into tSeed`) the moment you are done, and understand that this reduces the window
rather than closing it. Do not treat CoinXT as key custody; it is a calculator. Custody,
backup, and confirm-before-sign belong to the app.

## Testing what you build on

- `tools/coin-kat.py` drives every symbol headless through ctypes against public vectors. It
  needs a C compiler; it builds the shim from source and cannot be fooled by a stale artifact.
- `tests/coin-selftest.livecodescript` is the engine-side harness. Paste it into a stack
  script and it builds its own UI and exercises every public handler above, including the
  aliasing trap, the fail-closed guards and (phase 5) the BIP-143 / EIP-155 / EIP-1559
  transaction KATs.
- `tools/check-selftest-vectors.py` re-derives the harness's expected digests on every push so
  they cannot drift, using Python's own implementations where an independent one exists.

## See also

- [../SPEC.md](../SPEC.md) - what CoinXT is designed to become, in full.
- [../IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) - the phase order and each phase's bar.
- [../CLAUDE.md](../CLAUDE.md) - the as-built record and the FFI conventions.
- [../README.md](../README.md) - install, gates, status.
