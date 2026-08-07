# 08 - Capabilities Required (Upstream Gaps)

OnionXT composes SodiumXT for all cryptography (CLAUDE.md rule 1) and the OXT engine for all socket
I/O. This is the honest list of the narrow crypto primitives it wants. The family rule holds: a needed
crypto primitive is an **upstream SodiumXT feature request landed first**, never a hand-rolled hash in
OnionXT.

**Status as of SodiumXT ABI 6:** gaps #1 (ed25519 seed -> expanded key, `sxSignSeedToExpandedKey`) and
#3 (HMAC-SHA256, `sxHmacSha256`) are **SHIPPED and composed** - deterministic-from-seed onions and
SAFECOOKIE control auth now work. Gap #2 (SHA3-256, offline address checksum) stays **DEFERRED** by
design (libsodium has no SHA-3, and the checksum is a nicety, not a security dependency). OnionXT
therefore requires **SodiumXT ABI >= 6** for the deterministic-onion and SAFECOOKIE paths; the SOCKS
dial path, Tor-generated onions, and COOKIE/NULL/HASHEDPASSWORD auth need no SodiumXT at all.

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

### 2. SHA3-256 (for the v3 onion address checksum) - DEFERRED (the only remaining gap)

**Status: DEFERRED.** libsodium has no SHA-3/Keccak, so SodiumXT does not ship `sxSha3_256`, and this
stays deferred by design. It is only needed to EMIT or offline-VALIDATE an address checksum, which is a
nicety, not a security dependency: address recovery (base32-decode -> ed25519 pubkey) and connect-time
authentication (tor verifies the descriptor signature against the key in the address) both work without
it. `oxAddressFromPublicKey` / `oxIsValidAddress` compose `sxSha3_256` if it ever lands and otherwise
return a clear capability error / do structural-only validation. Revisit only if offline address
emit/validate becomes a real need (it would mean bundling non-libsodium crypto into SodiumXT).

- **Needed by:** `oxAddressFromPublicKey` (to emit a correct 2-byte checksum) and `oxIsValidAddress`
  (to validate a pasted address offline). The checksum is `SHA3-256(".onion checksum" || PUBKEY ||
  VERSION)[:2]`.
- **Options:**
  a. Add `sxSha3_256` to SodiumXT. Note libsodium's stable API does not include SHA-3/Keccak; it would
     come from libsodium's optional/experimental surface or a tiny vetted Keccak added to the shim.
     This is a larger ask than the SHA-512 helper.
  b. Defer: get your own address from `ADD_ONION`'s `ServiceID` (Tor computes the checksum), and rely
     on Tor's connect-time descriptor-signature check to authenticate a peer's address rather than a
     local checksum verify. base32 decode still recovers the peer's public key without SHA3.
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
