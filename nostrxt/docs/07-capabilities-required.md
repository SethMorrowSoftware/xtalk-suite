# 07 - Capabilities, Limits and Open Questions

NostrXT composes CoinXT for every hash, signature and curve operation, SodiumXT for randomness,
constant-time compare and the NIP-44 cipher (CLAUDE.md rule 1), and the OXT engine for all
socket I/O. This is the ledger of what it needs from each, what the engine still owes it, and
the scope limits it holds on purpose. The family's split-the-change law holds throughout: a
missing primitive is an **upstream feature landed first** (its own ABI bump and tests), then
composed here - never a hand-rolled cipher, hash or curve op in this member. OnionXT's
`docs/08-capabilities-required.md` was the precedent: all three of its gaps shipped upstream and
were composed, and this member's one crypto gap followed the same path.

The gap labels are stable citations (the shipped capability error names this file; the relay
source cites "docs/07 gap #2"). This file also carries what the retired open-questions page
(docs/08, deleted 2026-09-23) held; each such item says which question it was.

**Status:** ZERO crypto gaps and ONE engine unknown with a security half (TLS, gap #2), plus two
smaller engine unknowns. CoinXT ABI 6 supplies `cxSha256`, `cxSchnorrSign`, `cxSchnorrVerify`,
`cxXOnlyPubkey`, `cxEcdh`, `cxHmacSha256` and `cxSeckeyIsValid`; SodiumXT supplies
`sxRandomBytes`, `sxMemEqual` and, since ABI 10, `sxChaCha20IetfXor`.

## SodiumXT gaps

### Gap #1. `sxChaCha20IetfXor` (raw IETF ChaCha20) - SHIPPED (SodiumXT ABI 10, 2026-08-23)

**Closed.** What was requested, and shipped signature for signature:

```
sxChaCha20IetfXor(pKey as Data, pNonce as Data, pData as Data) returns Data
```

RFC 8439 ChaCha20 (the IETF variant): 32-byte key, **12-byte nonce**, initial block **counter
0**; an UNAUTHENTICATED stream xor, its own inverse. It is a thin wrap of libsodium's audited
`crypto_stream_chacha20_ietf_xor` (the shim's `sxt_chacha20_ietf_xor`, with 32/12 length getters
beside it), the same shape as OnionXT's `sxSha3_256`. It shipped with C KATs green under
ASan/UBSan, cross-checked against this member's oracle (RFC 8439 ChaCha20) and the pinned
libsodium tarball's own expectations - three implementations agreeing. NostrXT's seam needed no
code change. The complete NIP-44 path is engine-proven 2026-08-24 (Windows x86_64, OXT 9.6.3,
274/274 in the suite paste) and again 2026-09-24 (Windows, the engine reports Win32, 277/277);
relay-borne NIP-44 events keep "verified statically; needs a live-relay pass".

**Why NIP-44 needs the UNAUTHENTICATED stream.** NIP-44 v2 does not use Poly1305: its
authentication is HMAC-SHA256 over nonce||ciphertext, keyed by the third HKDF-expand slice and
verified BEFORE the cipher runs. An AEAD (`crypto_aead_chacha20poly1305_ietf_*`) would produce
payloads no other Nostr client can read. Conformance requires the raw stream; the MAC is composed
here from CoinXT's `cxHmacSha256`.

**The loud reason.** The primitive crosses SodiumXT's rule 3 (no bring-your-own-nonce entry
point) and rule 4 (no raw unauthenticated stream cipher), so it owed a written reason, and that
reason now lives in `sodiumxt/docs/security.md` ("The one argued exception"), at the declaration
in `sodiumxt/src/sodium_shim.h`, and as dated exceptions inside SodiumXT's rules 3 and 4:

- **Nonce discipline lives in the construction, not the caller.** The 12-byte ChaCha nonce is
  never chosen by an app: it is an HKDF-expand slice over a fresh 32-byte random nonce drawn
  inside `nxNip44Encrypt`. Reuse would take an HKDF collision, not a caller mistake.
- **Authentication is one layer up, per a published specification**, and verified before the
  cipher runs - the property rule 4 exists to guarantee, held without Poly1305.
- **The alternative is worse by the stronger rule.** Without the primitive, NIP-44 would need a
  hand-rolled ChaCha20 here, which rule 1 forbids.
- **Containment.** It is documented as a building block for spec-pinned constructions that carry
  their own MAC (NIP-44 is the named consumer), not as a sealing API.

**The fail-closed path on an older install.** `nxNip44Encrypt` and `nxNip44Decrypt` return empty
with `nxLastError()` reading exactly:

```
nxNip44 needs SodiumXT sxChaCha20IetfXor (shipped in SodiumXT ABI 10; the installed SodiumXT predates it - docs/07-capabilities-required.md)
```

`nxProbeCapabilities()` reports `canNip44Cipher` false (cached per session) and
`nxNip44HasCipher()` answers false (a live probe, so an upgrade is noticed without restarting).
Everything before the seam - conversation key, message keys, padding, the payload refusals and
the MAC-before-cipher order - works and is vector-pinned on any install. The harness's seam
section branches on `nxNip44HasCipher()` at run time: the fail-closed assertion on an older
package, the official encrypt_decrypt vector decrypting and re-encrypting byte-identically on a
current one.

## Engine capabilities to confirm (not extension gaps)

### Gap #2. TLS / `open secure socket` - HALF measured; the open half is the security half

Real-world Nostr relays are almost all `wss://`, and `nxrConnect` writes the secure path. On
2026-08-24 it ran: the demo connected to wss://nos.lol on Windows/OXT 9.6.3, completed the
websocket handshake, published a signed event and read the relay's ok-true back. So
`open secure socket ... with message` exists, connects asynchronously, fires its message, and
carries `read from socket ... with message` / `write to socket` for a full websocket exchange
(the suite's `docs/OXT-ENGINE-NOTES.md` 6.8). `open secure socket` appears in no other member.

Still open, which is why this gap stays open (formerly 08 question 3 as well):

- **Certificate verification.** That run reached an ordinary public host, so it is equally
  consistent with verification working and with none happening. No bad certificate has been
  offered. Is the peer certificate verified, against which root store, is the HOSTNAME checked,
  and what does `the sslCertificates` do here? An unverified socket that connects anyway would
  be a fail-open this layer must then guard.
- **SNI**: is the server name sent? Shared-hosting relays refuse or serve the wrong certificate
  without it.
- **Failure delivery**: does a refused TLS handshake arrive as a `socketError` message (the
  plain-socket behaviour the layer assumes), or some other way, and with what text?
- **TLS versions** accepted.

Record the answers in engine note 6.8 whatever they are. The fallback advice has inverted: ws://
is now the form with no live run of its own, so it is not the safer starting point. A `.onion`
relay over OnionXT needs no TLS at all (Tor provides the authenticated channel and the onion
address IS the key), but that is a design choice about anonymity (below), not a hedge.

### Other engine unknowns

- **`base64Encode`'s raw emission** (formerly 08 question 1). Every wire format here is
  single-line, so `nxB64Encode` strips both CR and LF unconditionally - correct whether the
  engine wraps with CRLF, LF or not at all. The STRIP is proven correct in effect by the
  2026-08-24 pass and again by the 2026-09-24 one (the NIP-44 payload vectors and the RFC 6455
  accept both ran green); whether `base64Encode` wraps, with which bytes and at what width is
  unrecorded, a one-line message-box observation. The source keeps `VERIFY (on-engine)` at that site until then.
- **Socket write backpressure** (formerly 08 question 4). The relay layer writes whole frames
  with `write to socket`; the frame cap is megabytes. Whether a large write blocks the
  interpreter until the OS buffer drains, queues, or partially writes is unmeasured anywhere in
  the suite (OnionXT never pushed writes that size). If it blocks, big publishes need chunking or
  a ceiling below the protocol cap; measure, then record it in the engine notes.
- The engine-global `socketTimeoutInterval` and the close-handshake ordering are
  `05-relay-client.md` VERIFY items 5 and 8.
- Settled 2026-08-24 (formerly 08 question 2): the `textDecode` UTF-8 round trip of non-BMP
  content is faithful on Windows x86_64 / OXT 9.6.3 (harness event C: a euro sign and a
  four-byte emoji, id pinned), and held again 2026-09-24 (Windows, the engine reports Win32, its
  OXT version not recorded). Scoped to those Windows engines and those two codepoints; the
  fixture bytes stay constants and the harness stays pure ASCII so a future FAIL is a finding.

## Non-gaps and scope decisions

### AES-256-CBC / NIP-04 - out of scope, decided

- **No AES exists anywhere in this suite**, and libsodium will never provide CBC - unauthenticated
  CBC is precisely what libsodium exists to refuse to carry.
- **NIP-04 is superseded by NIP-44** and deprecated by the protocol's own docs: no MAC (malleable
  ciphertext), no padding (lengths leak). Implementing it would add a weaker construction the
  family would then carry forever.
- The cost, stated: NostrXT cannot decrypt legacy kind-4 DMs, and will not. An app that must
  read them needs a different tool.

### bech32 upstreaming into CoinXT - considered and declined

- CoinXT's bech32 **enforces BIP-173's 90-character cap in both directions**, which is CORRECT
  for its Bitcoin callers, and keeps its 8-to-5 bit converters private. NIP-19 waives the cap
  for TLV entities (an nprofile with a few relay hints is routinely past 90).
- Widening a money library's validation for a sibling loosens checks for CoinXT's OWN callers,
  and threading a cap parameter through an engine-proven, vector-pinned layer spends CoinXT's
  engine evidence on NostrXT's problem.
- bech32 is checksummed byte shuffling with no secret-dependent branch, so rule 1 does not force
  it upstream. NostrXT carries its own, uncapped, with NIP-19's 5000-character SHOULD enforced
  and the over-90 deviation asserted by the KAT (`03-nip19-entities.md`).

### Hand-rolled digests - forbidden, not missing

Event ids are CoinXT's `cxSha256`, the NIP-44 schedule and MAC are `cxHmacSha256`, and the
websocket accept uses the ENGINE's own `sha1Digest` - the one engine-proven builtin hash in this
tree, which riptide relies on. A future need (say SHA-512 for some NIP) is an upstream request.

### What the protocol layer does not do yet, and why (formerly 08 questions 5 and 6)

Each addition lands with published vectors pinned first where vectors exist, or is declined with
reasons; the work itself is tracked in the suite's docs/WORK-PLAN.md.

- **NIP-44 extended length.** Plaintext over 65535 bytes refuses until upstream publishes vectors
  for the sketched 6-byte prefix (`04-nip44-payloads.md`, step 4).
- **NIP-17 / NIP-59 (private DMs via gift wrap)** is what users will ask for first. Its blockers
  are cleared (the cipher shipped 2026-08-23; the NIP-44 sections ran green on an engine
  2026-08-24); what remains is design, with the published vectors pinned first. The building
  blocks exist: the kind builders, the complete NIP-44, `nxrSendRaw` for wrapped kinds. NIP-59
  would be its own composable layer.
- **NIP-65 outbox routing.** Kind 10002 is built and parsed (`nxRelayListBuild` /
  `nxRelayListParse`); the ROUTING STRATEGY (read from the author's write relays, write to the
  recipient's read relays, with what fallback and cap) is policy, and belongs above the library
  or in a pool layer, not inside the relay client.
- **A relay pool.** Today one handle is one relay and the app multiplexes. A pool (dial several,
  deduplicate by id, per-relay subscription state, reconnect policy; when is an event "seen",
  which relay's EOSE ends a query) is policy v0.1 does not guess. If it comes, it is a THIRD file
  composing `nxr*` (the onion-httpd-over-`ox*` shape), so the relay client stays a transport.
- **`.onion` relays** over OnionXT's transport seam: a composition at that seam, not a fork of
  the relay layer, and it needs a transport seam in `nxrConnect`. It is the anonymity path
  (`00-overview.md`, "Where Tor fits").
- NIP-42 and NIP-13 are done; anything beyond rides `nxrSendRaw` until it earns handlers.

## Measure before optimizing (formerly 08 questions 7 and 8)

The family's native-last law (proven in OnionXT): default to script, and reach for native only
after an engine pass shows script is too slow.

- **Byte-loop JSON parsing.** `nxRelayParse` / `nxEventFromJson` walk every byte in interpreted
  script: nothing for chat-sized events, unmeasured for a 100 KB kind-30023 article or a fat
  contact list. The remedy ladder: parse less (verbatim slicing already avoids re-serializing),
  then a narrow native helper requested upstream - never a borrowed engine JSON library, for the
  canonical-bytes reason (`06-api-reference.md`, "What is deliberately NOT here").
- **Arithmetic byte-xor in frame masking.** RFC 6455 masking xors every outbound payload byte,
  and `nxByteXor` uses an 8-iteration div/mod loop because the portable-arithmetic discipline
  forbids `bitXor` (operator portability has bitten the family): about eight divisions per byte,
  millions on a megabyte frame. A 256x256 lookup table is the candidate fix; inbound server
  frames are unmasked and already skip it. Do not optimize until an engine shows a stall; the
  harness pins the masked-frame bytes as the regression net.

## Not needed from anyone

No new CoinXT capability (ABI 6's BIP-340 / x-only / ECDH / HMAC surface covers NIP-01 and the
NIP-44 key schedule), no engine change beyond the measurements above, and no relay-side
anything: NostrXT speaks stock NIP-01 to unmodified relays.
