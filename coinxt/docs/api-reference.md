# CoinXT API Reference

**The `cx*` handlers that exist today, and nothing else.**

CoinXT is being built in phases (see [../IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md)).
[../SPEC.md](../SPEC.md) describes the *whole designed* API, including the secp256k1 curve
surface, address encodings, and HD wallets. **Most of that does not exist yet.** This file is
the opposite document: it lists only what is shipped, so you can tell at a glance what you can
actually call.

> **Status.** Phase 1, the hash surface, is complete and was closed by an engine pass on
> **2026-08-08**: the binding loaded on a real OXT engine and returned its pinned vectors
> byte-exact. Sixteen public handlers exist. Everything below is real.
>
> **Not shipped, despite appearing in SPEC.md:** `cxNewSeckey`, `cxPublicKey`, `cxSign`,
> `cxVerify`, `cxSignRecoverable`, `cxRecover`, `cxEcdh`, `cxSchnorrSign`/`cxSchnorrVerify`,
> `cxHexEncode`/`cxHexDecode`, `cxBase58CheckEncode`/`Decode`, `cxBech32Encode`/`Decode`,
> `cxRlpEncode`/`Decode`, `cxHash160`, `cxHash256`, `cxBtcAddressP2PKH`/`P2WPKH`/`P2TR`,
> `cxEthAddress`, `cxEthAddressChecksum`, `cxHdFromSeed`, `cxHdDerivePath`, `cxXprv`/`cxXpub`,
> `cxMnemonicFromEntropy`/`ToSeed`/`Validate`. Calling any of them is a `handler not found`.

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
  reports ABI 2, and throws if not, so a mismatched library cannot silently produce garbage.
- **An empty `Data` is legal input** for every digest and for both HMAC slots. It returns the
  documented empty-input digest rather than throwing. This was the binding's one genuinely
  open marshalling question and the 2026-08-08 engine pass settled it.

## The ABI guard

### `cxCheckABI`

```
cxCheckABI
```

A command. Returns nothing. Throws if the loaded native library does not report ABI 2, with
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

## Length accessors

Seven zero-argument handlers returning the digest size the library actually reports.

| Handler | Returns |
|---|---|
| `cxKeccak256Len()` | 32 |
| `cxSha3_256Len()` | 32 |
| `cxSha256Len()` | 32 |
| `cxSha512Len()` | 64 |
| `cxRipemd160Len()` | 20 |
| `cxHmacSha256Len()` | 32 |
| `cxHmacSha512Len()` | 64 |

These are not decoration. **Do not hardcode 32 or 64 in your own code**; ask. A library is
entitled to change a digest size across versions, and a hardcoded length is a buffer overflow
waiting to happen. The binding itself follows this rule: every wrapper sizes its output buffer
from the matching accessor rather than from a literal, which is why a wrong length would break
the digest rather than hide.

Under the hood these are the one genuinely novel thing in the binding: they marshal a C
`size_t` as a foreign `UIntSize` **return** type, which this extension family had previously
proven only as a parameter. The 2026-08-08 engine pass confirmed it works.

## Errors

Every failure is a thrown string starting `"CoinXT:"`. The forms you can encounter:

| Error | Meaning |
|---|---|
| `CoinXT: ABI mismatch - ...` | The bundled native library does not match the extension. Reinstall; they ship together. |
| `CoinXT: <handler>: a required buffer was missing (null).` | A required buffer did not marshal. |
| `CoinXT: <handler>: a buffer had the wrong length.` | A fixed-size buffer was the wrong size. |
| `CoinXT: <handler>: a length or count is out of the range ...` | A length the native primitive cannot represent. |
| `CoinXT: <handler>: an unexpected native status ...` | The loaded library does not match this binding. |
| `CoinXT: cxPbkdf2HmacSha512: the output length must be at least 1 byte ...` | `pOutLen` below 1. |
| `CoinXT: cxPbkdf2HmacSha512: the iteration count must be at least 1 ...` | `pIterations` below 1. |
| `CoinXT: out of memory allocating an output buffer.` | The engine could not allocate the output. |

```
try
   put cxKeccak256(tData) into tDigest
catch tError
   answer "Hashing failed:" && tError
end try
```

## Secret hygiene, honestly

CoinXT zeroes its own scratch buffers in C. It cannot protect the `Data` it hands back.

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
  script and it builds its own UI and exercises all 16 handlers above, including the aliasing
  trap and the fail-closed guards.
- `tools/check-selftest-vectors.py` re-derives the harness's expected digests on every push so
  they cannot drift, using Python's own implementations where an independent one exists.

## See also

- [../SPEC.md](../SPEC.md) - what CoinXT is designed to become, in full.
- [../IMPLEMENTATION-PLAN.md](../IMPLEMENTATION-PLAN.md) - the phase order and each phase's bar.
- [../CLAUDE.md](../CLAUDE.md) - the as-built record and the FFI conventions.
- [../README.md](../README.md) - install, gates, status.
