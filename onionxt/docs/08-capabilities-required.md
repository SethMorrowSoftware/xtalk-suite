# 08 - Capabilities Required

OnionXT composes SodiumXT for all cryptography (CLAUDE.md rule 1): a needed primitive is an **upstream
SodiumXT feature landed first**, never a hand-rolled hash here. All three it needed have shipped.

## SodiumXT gaps (all shipped)

### 1. ed25519 seed -> expanded key (deterministic onion services) - SodiumXT ABI 6

`sxSignSeedToExpandedKey(pSeed)` returns the 64-byte expanded key (`SHA-512(seed)`, clamped, `a || RH`)
that `ADD_ONION ED25519-V3:` wants (doc 04); its public key matches `sxSignKeypairFromSeed(pSeed)`.
Composed in `oxExpandedKeyFromSeed` / `oxCreateServiceFromSeed`; the seed `0x42` x 32 known answer is
pinned in `tools/onion-kat.py`.

### 2. SHA3-256 (the v3 address checksum) - SodiumXT ABI 7, 2026-08-11

`sxSha3_256(pData)` (FIPS 202) serves the checksum `SHA3-256(".onion checksum" || PUBKEY ||
VERSION)[:2]` for `oxAddressFromPublicKey` and `oxIsValidAddress`. libsodium has no SHA-3, so SodiumXT
vendors RHash's MIT SHA3 via trezor-crypto, byte-identical to coinxt's (provenance in
`sodiumxt/src/vendor/VENDOR.md`; vectors in `sodiumxt/tests/sodium_smoke_test.c` and sodium-tests).
**Confirmed on an engine 2026-08-12** (Windows x64, ABI 7, harness 43/43): torproject.org's and
DuckDuckGo's onions re-encoded byte-exactly, a tampered address refused, `offlineAddress` true. Against
an older SodiumXT the address layer degrades to structural checks (doc 04).

### 3. HMAC-SHA256 (SAFECOOKIE control auth) - SodiumXT ABI 6

`sxHmacSha256(pKey, pMessage)` computes the SAFECOOKIE server and client hashes over
`Cookie || ClientNonce || ServerNonce` with the two verbatim control-spec key strings; `SERVERHASH` is
checked in constant time with `sxMemEqual` (doc 03). RFC 4231 Test Case 2 is pinned in
`tools/onion-kat.py`. COOKIE auth (plain hex over loopback) is the fallback without it.

## What needs which SodiumXT

| Path | Needs | `oxTransportInfo()` flag |
|---|---|---|
| SOCKS dial, Tor-generated onions, COOKIE / NULL / HASHEDPASSWORD auth | no SodiumXT | |
| SAFECOOKIE auth | `sxHmacSha256` + `sxRandomBytes` (ABI >= 6) | `safeCookieAuth` |
| Deterministic onions from a seed | `sxSignSeedToExpandedKey` (ABI >= 6) | `deterministicOnion` |
| Offline address emission and checksum validation | `sxSha3_256` (ABI >= 7) | `offlineAddress` |

## Engine capabilities relied on

Asynchronous sockets, the engine's `socketError` and `socketClosed` messages, byte-exact binary I/O
and binfile reads of the control cookie are engine-confirmed (CLAUDE.md evidence ledger, confirmed
items 1-7). `socketTimeout`, including its repeat while a read or write is pending, is DOCUMENTED only
(the suite's engine note 6.1) and not yet observed, and so is `open process`, used only by the optional
Mode B launch (doc 07). All three socket messages are the engine's names, so an app must `pass` the
ones that are not its own (doc 10 section 2). Nothing is needed from BitTorrent or from Tor itself
(stock SOCKS5 and control protocol against an unmodified tor).
