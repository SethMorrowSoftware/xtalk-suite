# 08 - Capabilities Required (Upstream Gaps)

OnionXT composes SodiumXT for all cryptography (CLAUDE.md rule 1) and the OXT engine for all socket
I/O. This is the honest list of the narrow crypto primitives it wants. The family rule holds: a needed
crypto primitive is an **upstream SodiumXT feature request landed first**, never a hand-rolled hash in
OnionXT.

**Status as of SodiumXT ABI 7:** all three gaps are now **SHIPPED and composed**. Gaps #1 (ed25519
seed -> expanded key, `sxSignSeedToExpandedKey`) and #3 (HMAC-SHA256, `sxHmacSha256`) shipped in ABI 6
- deterministic-from-seed onions and SAFECOOKIE control auth work. Gap #2 (SHA3-256, offline address
checksum) shipped in **ABI 7** (`sxSha3_256`, 2026-08-11), so `oxAddressFromPublicKey` now emits a real
address and `oxIsValidAddress` verifies checksums offline. OnionXT therefore requires **SodiumXT ABI
>= 6** for the deterministic-onion and SAFECOOKIE paths and **ABI >= 7** for offline address
emission/validation; the SOCKS dial path, Tor-generated onions, and COOKIE/NULL/HASHEDPASSWORD auth
need no SodiumXT at all, and against a pre-ABI-7 SodiumXT the address layer degrades to structural-only
checks (no upstream gap remains).

## SodiumXT gaps

### 1. ed25519 seed -> expanded key (for deterministic onion services) - SHIPPED (SodiumXT ABI 6)

**Status: SHIPPED.** SodiumXT ABI 6 provides `sxSignSeedToExpandedKey(pSeed as Data) returns Data`: a
32-byte seed becomes the 64-byte expanded ed25519 secret key (`SHA-512(seed)` with the scalar clamp,
`a || RH`), done inside SodiumXT. OnionXT composes it directly in `oxExpandedKeyFromSeed` and
`oxCreateServiceFromSeed`; the old script-side SHA-512 + clamp fallback is gone. Known-answer vector
(seed = `0x42` x 32) pinned in `tools/onion-kat.py` and exercised by `examples/onionxt-tests.livecodescript`.

- **Needed by:** `oxCreateServiceFromSeed` and any reproducible-address flow (doc 04). `ADD_ONION
  ED25519-V3:<key>` wants the 64-byte expanded ed25519 secret key (`SHA-512(seed)`, clamped, split into
  scalar `a` and prefix `RH`), not libsodium's `seed || pubkey` secret key. `sxSignSeedToExpandedKey`
  yields exactly that, and its public key matches `sxSignKeypairFromSeed(pSeed)`, so the `.onion`
  address and the app's signing identity stay consistent.

### 2. SHA3-256 (for the v3 onion address checksum) - SHIPPED (SodiumXT ABI 7)

**Status: SHIPPED (2026-08-11).** SodiumXT ABI 7 provides `sxSha3_256(pData as Data) returns Data`
(32 bytes, NIST FIPS 202). libsodium's stable API has no SHA-3, so SodiumXT serves this one
primitive from a vendored implementation (RHash's MIT SHA3 via trezor-crypto, byte-identical to the
copy coinxt already bundles; provenance in `sodiumxt/src/vendor/VENDOR.md`) - option (a) below, taken
once the riptide capstone made offline address emission a real need rather than a nicety. OnionXT's
`oxSha3_256` composes it unchanged: `oxAddressFromPublicKey` now emits real addresses and
`oxIsValidAddress` verifies checksums when the installed SodiumXT is ABI 7+, and both still degrade
exactly as before (capability error / structural-only) against an older SodiumXT. The FIPS 202
vectors and the torproject.org onion-checksum composition vector are pinned in
`sodiumxt/tests/sodium_smoke_test.c` (ASan/UBSan) and `sodiumxt/examples/sodium-tests.livecodescript`;
the address round-trip and tamper checks in `examples/onionxt-tests.livecodescript` that used to skip
now run wherever `oxTransportInfo()["offlineAddress"]` reports true. **The composed script path is
CONFIRMED ON-ENGINE (2026-08-12, Windows x64, SodiumXT ABI 7 installed):** `oxAddressFromPublicKey`
re-encoded torproject.org's and DuckDuckGo's real onion addresses byte-exactly from their recovered
public keys, a tampered address failed checksum validation, and `oxTransportInfo()["offlineAddress"]`
advertised true - the full 43/43 member harness green.

- **Needed by:** `oxAddressFromPublicKey` (to emit a correct 2-byte checksum) and `oxIsValidAddress`
  (to validate a pasted address offline). The checksum is `SHA3-256(".onion checksum" || PUBKEY ||
  VERSION)[:2]`.
- **The options considered while it was deferred**, kept for the record:
  a. Add `sxSha3_256` to SodiumXT from a tiny vetted implementation (what shipped; the suite already
     trusted the identical vendored code in coinxt).
  b. Defer: get your own address from `ADD_ONION`'s `ServiceID` (Tor computes the checksum), and rely
     on Tor's connect-time descriptor-signature check to authenticate a peer's address rather than a
     local checksum verify. base32 decode still recovers the peer's public key without SHA3. (This
     remains the behaviour against a pre-ABI-7 SodiumXT.)
- **Recommendation:** defer (b) for v1; the checksum is a nicety, not a security dependency (the
  descriptor signature is the real authentication). Add (a) only if offline address emission/validation
  becomes a real need.

### 3. HMAC-SHA256 (for SAFECOOKIE control auth) - SHIPPED (SodiumXT ABI 6)

**Status: SHIPPED.** SodiumXT ABI 6 provides `sxHmacSha256(pKey as Data, pMessage as Data) returns
Data` (32-byte MAC). OnionXT's SAFECOOKIE flow (doc 03) composes it directly: verify `SERVERHASH` with
`sxMemEqual` (constant time), then send the controller-to-server hash. COOKIE auth (plain hex over
loopback) remains a fine fallback when SAFECOOKIE prerequisites are absent. Known-answer vector
(RFC 4231 Test Case 2) pinned in `tools/onion-kat.py`.

- **Needed by:** the preferred SAFECOOKIE control-auth method (doc 03), which verifies a server hash
  and computes a client hash, both HMAC-SHA256 over the cookie and nonces. The two HMAC key strings are
  the verbatim Tor control-spec constants; the message is `Cookie || ClientNonce || ServerNonce`.

## Engine capabilities to confirm (not gaps, but Phase 0 unknowns)

These are assumed to exist in OXT (they exist in LiveCode); confirm and record the exact behaviour in
Phase 0, because the whole core rests on them:

- Asynchronous sockets: `open socket ... with message`, `read from socket ... for N with message`,
  `write to socket`, `accept connections on <port> with message`, `close socket`, `socketError` /
  `socketTimeout` messages, and `the socketTimeoutInterval`.
- Binary discipline: byte-exact `read`/`write`, `byte x to y of`, `numToByte`, `byteToNum`,
  `binaryEncode`, `binaryDecode`, with no Unicode reinterpretation on the socket path.
- Reading a file's raw bytes (the control cookie): `open file ... for binary read` / `url
  ("binfile:...")`.
- For Mode B lifecycle (doc 07): `open process` / shelling out to launch and signal a child tor.

## Not needed from anyone

- No new BitTorrent capability (that is TorrentXT's domain, not OnionXT's).
- No Tor-side change: OnionXT uses stock SOCKS5 and the stock control protocol against an unmodified
  tor daemon.
