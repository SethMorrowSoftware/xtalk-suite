# 07 - Capabilities Required (Upstream Gaps)

NostrXT composes CoinXT for every hash, signature and curve operation and SodiumXT
for randomness and constant-time compare (CLAUDE.md rule 1), and the OXT engine for
all socket I/O. This is the honest ledger of what it still needs from upstream. The
family's split-the-change law holds throughout: a missing primitive is an **upstream
feature request landed first** (with its own ABI bump and tests), then composed here
- never a hand-rolled cipher, hash or curve op in this member. OnionXT's
`docs/08-capabilities-required.md` is the model and the precedent: all three of its
gaps shipped upstream and were composed, which is the trajectory this file expected
for its one crypto gap - and the trajectory it then followed (closed 2026-08-23,
below).

**Status as of 2026-08-23 (updated the same day v0.1.0 shipped):** ZERO crypto gaps
and ONE engine unknown (TLS sockets, nobody's extension). The one crypto gap this
ledger opened with - the NIP-44 cipher - shipped upstream the same day, as SodiumXT
ABI 10's `sxChaCha20IetfXor` (the record below). Everything else NostrXT needs
already existed: CoinXT ABI 6 carries `cxSha256`, `cxSchnorrSign`,
`cxSchnorrVerify`, `cxXOnlyPubkey`, `cxEcdh`, `cxHmacSha256` and `cxSeckeyIsValid`;
SodiumXT carries `sxRandomBytes` and `sxMemEqual`.

## SodiumXT gaps

### 1. `sxChaCha20IetfXor` (raw IETF ChaCha20) - SHIPPED (SodiumXT ABI 10, 2026-08-23)

**Status: CLOSED, the way OnionXT's three gaps closed.** Shipped upstream as
SodiumXT ABI 10 with its own C KATs (green under ASan/UBSan, cross-checked against
an independent RFC 8439 reference - three implementations agree on the pinned
vectors), a probe-guarded section in SodiumXT's own harness, and the written loud
reason this ledger owed (it landed in `sodiumxt/docs/security.md`; see below).
NostrXT's seam needed NO code change - the try-guarded call, both probes and the
harness's round-trip branch flipped live, exactly as designed. The complete
NIP-44 path now sweeps the official encrypt/decrypt vectors headlessly; no part
of it has met an engine yet (the honesty label stays "verified statically; needs
an OXT pass"). On an installed SodiumXT older than ABI 10 the seam still fails
closed with the capability error, by design - the paragraphs below describe that
path in the present tense because it remains a real deployment state, not a
historical one.

**Exactly what was requested (and shipped, signature for signature):**

```
sxChaCha20IetfXor(pKey as Data, pNonce as Data, pData as Data) returns Data
```

- RFC 8439 ChaCha20 (the IETF variant): 32-byte key, **12-byte nonce**, initial
  block **counter 0**.
- An UNAUTHENTICATED stream xor: bytes in, the same number of bytes out, and the
  operation is its own inverse (encrypt and decrypt are the same call).
- libsodium already ships exactly this as `crypto_stream_chacha20_ietf_xor`, so the
  upstream change is a thin wrap of audited code, not new cryptography - the same
  shape as OnionXT's `sxSha3_256` request, which shipped. (And so it went: the
  shipped `sxt_chacha20_ietf_xor` is that thin wrap, with the shim's standard
  length/pointer firewall around it and the 32/12 length getters beside it.)

**Why NIP-44 needs the UNAUTHENTICATED stream, stated plainly because it looks like
a mistake until it is stated:** NIP-44 v2 does not use Poly1305. Its authentication
is **HMAC-SHA256 over nonce||ciphertext**, keyed by the third slice of the
HKDF-expand output, verified BEFORE the cipher runs on decrypt - that is the
published construction the official vector set pins, byte for byte. An AEAD
(`crypto_aead_chacha20poly1305_ietf_*`) would produce payloads no other Nostr client
can read: sixteen tag bytes in the wrong place and a MAC the spec does not define.
Conformance requires the raw stream; the authentication NIP-44 requires is already
composed here from CoinXT's `cxHmacSha256`.

**The documented tension with SodiumXT's own rules, and what the loud reason must
argue.** SodiumXT's CLAUDE.md rule 3 says "do not expose a bring-your-own-nonce
entry point without a very loud reason" and rule 4 says "never a raw unauthenticated
stream cipher". This request is BOTH, so proposing it upstream owed a written loud
reason in SodiumXT's own docs. THAT DEBT IS PAID: the argument below is now written,
point for point, in `sodiumxt/docs/security.md` ("The one argued exception"), at the
declaration in `sodiumxt/src/sodium_shim.h`, and as dated exceptions inside rules 3
and 4 themselves. It had to argue, at minimum:

- **The nonce discipline lives in the construction, not the caller.** The 12-byte
  ChaCha20 nonce handed to this primitive is never chosen by an app: it is the
  second slice of HKDF-expand over a fresh 32-byte per-message random nonce
  (`sxRandomBytes`, drawn inside `nxNip44Encrypt`). Nonce reuse would require
  an HKDF collision, not a caller mistake.
- **Authentication is provided one layer up, per a published specification.** The
  payload is MACed (HMAC-SHA256, nonce||ciphertext) and the MAC is verified before
  the cipher ever runs - the property SodiumXT's rule 4 exists to guarantee is
  held, just not by Poly1305.
- **The alternative is worse by the family's stronger rule.** Without the upstream
  primitive, the only path to NIP-44 conformance is hand-rolling ChaCha20 in this
  member - exactly what rule 1 (add no cryptography) forbids. A raw-stream export
  wrapping libsodium's audited implementation is the rules being obeyed at the
  family level, not waived.
- **Containment.** The export should be documented in SodiumXT as a
  building-block for composed, spec-pinned constructions that carry their own MAC
  (NIP-44 is the named consumer), not as a sealing API - so nobody mistakes it for
  `sxSecretboxEasy`.

**What fails closed on a pre-ABI-10 install, and the exact error.** `nxNip44Encrypt`
and `nxNip44Decrypt` return empty with `nxLastError()` reading:

```
nxNip44 needs SodiumXT sxChaCha20IetfXor (shipped in SodiumXT ABI 10; the installed SodiumXT predates it - docs/07-capabilities-required.md)
```

(Until 2026-08-23 the parenthetical read "not yet shipped upstream"; the remedy
now is upgrading the installed SodiumXT package to ABI 10 or later.)

`nxProbeCapabilities()` reports `canNip44Cipher` false (cached per session), and
`nxNip44HasCipher()` answers false (a live probe, so an upgraded SodiumXT is noticed
without restarting). Everything BEFORE the cipher seam works and is pinned by
`tools/nostr-kat.py` against the full official vector set today:
`nxNip44ConversationKey` (the official conversation-key vectors, valid and invalid),
`nxNip44MessageKeys` (the message-key vectors), `nxNip44PaddedLen` (the complete
calc_padded_len pair table), the payload structure refusals (version byte, length
floors, base64 strictness), and - the part worth underlining - **the
MAC-before-cipher order is provable today**: the member harness tampers inside the
ciphertext region of the official payload vector and asserts the refusal happens at
the MAC, before any cipher runs.

**How the harness self-upgrades - designed before the ship, true after it.** The
seam section of `examples/nostrxt-tests.livecodescript` branches on
`nxNip44HasCipher()` at run time: while the probe is false (an installed SodiumXT
older than ABI 10) it asserts the fail-closed path (the untampered official vector
reaches the cipher and refuses, naming `sxChaCha20IetfXor`); against a current
package the SAME harness, unchanged, asserts that the official encrypt_decrypt
vector decrypts to its published plaintext and re-encrypts byte-identically under
the fixed vector nonce. The oracle (`tools/nostr_reference.py`) has carried its own
RFC 8439 ChaCha20 since day one and sweeps the full encrypt/decrypt vector set
headlessly, so the pinned constants the round-trip branch exercises were derived
and gate-checked before the primitive existed - and the SodiumXT side reused that
same oracle to derive ITS smoke-test KATs, which is what makes the two members'
evidence independent of libsodium agreeing with itself.

## Engine capabilities to confirm (not extension gaps)

### 2. TLS / `open secure socket` - an ENGINE unknown, now HALF measured

**Status: PARTLY ANSWERED 2026-08-24, and the unanswered half is the one that
matters for security.** Real-world Nostr relays are almost all `wss://`. The relay
layer writes the secure path (`open secure socket to host:port with message ...` in
`nxrConnect`), and on 2026-08-24 that line ran: the demo connected to wss://nos.lol
on Windows/OXT 9.6.3, completed the websocket handshake, published a signed event
and read the relay's ok-true back. It was this suite's first exercised secure
socket, and root `docs/OXT-ENGINE-NOTES.md` **6.8** records it. `open secure socket`
still appears in no other member.

The next engine session must record the rest in the same place, whatever the
answers are. The first bullet is answered; the others are not, and the second is
the reason this gap stays OPEN rather than closing:

- ~~Does `open secure socket ... with message` exist on OXT at all, and does it
  connect to a public relay?~~ **ANSWERED 2026-08-24: yes to both**, and
  `read from socket ... with message` / `write to socket` carried a full websocket
  exchange over it.
- **Certificate verification behaviour** - STILL OPEN, and note what the run above
  does and does not say: it reached an ordinary public host, so a
  connection succeeding is consistent BOTH with verification working and with there
  being no verification at all. Nothing has yet offered this engine a bad
  certificate. Is the peer certificate verified, against which root store, and is
  the HOSTNAME checked? What does `the sslCertificates` do here? An unverified TLS
  socket that connects anyway would be a fail-open this layer must then guard, and
  we still cannot know which until someone points it at a deliberately bad cert.
- **SNI**: is the server name sent? Shared-hosting relays will refuse the handshake
  or serve the wrong certificate without it.
- **Failure delivery**: does a refused or failed TLS handshake arrive as a
  `socketError` message (the plain-socket behaviour the layer assumes), or some
  other way, and with what error text?
- TLS versions accepted. (The second half of this bullet is answered:
  `read from socket ... with message` and `write to socket` DID behave the
  same over the secure socket on 2026-08-24 - short reads reassembled by the
  framing layer, a full handshake and publish carried. Backpressure on a
  large write is untested there, but it is untested on the plain form too,
  so it is question 4 in `08-open-questions.md`, not a TLS question.)

The composition hedge stands on its own merits rather than as a workaround now: a
`.onion` relay over OnionXT's transport seam needs no TLS at all, because Tor
provides the authenticated encrypted channel and the onion address IS the key
(`00-overview.md`, `08-open-questions.md`). What HAS quietly inverted is the
fallback advice: ws:// used to be "the engine-idiom-proven path" to fall back to,
and after 2026-08-24 it is the form with no live run of its own while wss:// has
one.

## Non-gaps: things that look missing and are deliberate

### AES-256-CBC / NIP-04 - a scope decision, not a gap

NIP-04 (the legacy encrypted-DM kind 4) is **out of scope**, decided, with reasons:

- **No AES exists anywhere in this suite**, and libsodium will never provide CBC -
  unauthenticated CBC is precisely the construction libsodium exists to refuse to
  carry, so there is no upstream to request it from that the family trusts.
- **NIP-04 is superseded by NIP-44** and deprecated by the protocol's own docs: no
  MAC (malleable ciphertext), no padding scheme (message lengths leak), and the
  ecosystem's clients have moved. Implementing it would mean adding a weaker
  construction the family would then have to carry forever.
- The cost is stated honestly: NostrXT cannot decrypt legacy kind-4 DMs, and will
  not. An app that must read them needs a different tool.

### bech32 upstreaming into CoinXT - considered and declined

The obvious tidy move - "CoinXT already has engine-proven bech32, use it" - was
weighed and declined, and the reasons are worth keeping because the question will
recur:

- CoinXT's bech32 **enforces BIP-173's 90-character cap in both directions**, which
  is CORRECT for its Bitcoin callers, and keeps its 8-to-5 bit converters private.
  NIP-19 waives the cap for TLV entities (an nprofile with a few relay hints is
  routinely past 90) and wants a 5000-character SHOULD instead.
- Widening a money library's validation for a sibling's convenience loosens checks
  for CoinXT's OWN callers; threading a cap parameter through an engine-proven,
  vector-pinned layer is an interop-visible change to serve exactly one consumer.
  Either direction spends CoinXT's hard-won engine evidence on NostrXT's problem.
- bech32 is checksummed byte shuffling with no secret-dependent branch - exactly
  what family law allows a member to own in script. It is not cryptography, so
  rule 1 does not force it upstream.

So NostrXT carries its own bech32/bech32m, uncapped, with NIP-19's 5000-character
SHOULD enforced instead - and `tools/nostr-kat.py` pins full BIP-173 conformance
INCLUDING asserting the deliberate over-90 deviation as a deviation, so it can never
drift silently (`03-nip19-entities.md`).

### Hand-rolled SHA-256 (or any digest) - forbidden, not missing

Every hash NostrXT uses is composed: event ids are CoinXT's `cxSha256`, the NIP-44
schedule and MAC are CoinXT's `cxHmacSha256`, and the websocket accept derivation
uses the ENGINE's own `sha1Digest` - the one engine-proven builtin hash in this
tree, which riptide already relies on. There is no NostrXT digest, and per rule 1
there never will be; a future need (say SHA-512 for some NIP) is an upstream request
to CoinXT or SodiumXT, exactly like the cipher above.

## Not needed from anyone

- No new CoinXT capability: ABI 6's BIP-340 / x-only / ECDH / HMAC surface is
  everything NIP-01 and the NIP-44 key schedule require.
- No engine change beyond the TLS measurement above: ws:// rides the same
  `open socket` / `read ... with message` idioms OnionXT proved on-engine.
- No relay-side anything: NostrXT speaks stock NIP-01 to unmodified relays.
