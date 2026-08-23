# 00 - Overview and Architecture

## The one-sentence version

NostrXT lets an xTalk app hold a portable cryptographic identity and publish, fetch and verify
signed events across interchangeable websocket relays, by composing the suite's proven crypto
(CoinXT's BIP-340, SodiumXT's randomness) under a pure-script protocol layer that owns exactly
the byte shuffling family law allows it to own.

## What Nostr is

Nostr is a deliberately small protocol built from three ideas:

1. **Events signed with BIP-340 over secp256k1.** The unit of everything is an event: a small
   record (pubkey, timestamp, kind, tags, content) whose id is the SHA-256 of a canonical JSON
   serialization and whose signature is a BIP-340 Schnorr signature over that id. An event is
   therefore self-verifying anywhere, forever: anyone holding it can recompute the id and check
   the signature with no server's help. That is the same signature scheme Bitcoin's Taproot
   uses - which is why CoinXT already had it, and why NostrXT exists as a thin layer rather
   than a crypto project (`02-nip01-events.md`).
2. **Relays as dumb websocket stores.** A relay accepts events, stores them, and answers
   subscriptions (filters) over a plain websocket. It has no authority: it cannot forge an
   event (it holds no keys), and it cannot silently alter one (the id and signature would
   break). Clients talk to several at once and treat them as interchangeable - a relay that
   censors or dies is replaced by changing a URL (`01-protocol-model.md`,
   `05-relay-client.md`).
3. **Clients own identity.** The user's identity IS a secp256k1 keypair, held by the client,
   shown to humans as bech32 entities (`npub...`, `nsec...`; `03-nip19-entities.md`). No
   account, no registration, no recovery service - which is both the point and the sharp edge:
   the app decides how the secret key lives at rest, and NostrXT deliberately is not a key
   vault.

Encrypted DMs ride the same event stream as NIP-44 payloads (`04-nip44-payloads.md`), with one
honest caveat carried throughout these docs: the raw ChaCha20 cipher is the single primitive
the suite is missing, so encrypt/decrypt fail closed until SodiumXT ships it
(`07-capabilities-required.md`).

## The architecture: two files, and why the split is load-bearing

```
   your xTalk app
      |                                        |
      v                                        v
   nx* core                                 nxr* relay client
   src/nostrxt.livecodescript               src/nostr-relay.livecodescript
   pure compute: NO I/O, no connection      the stateful RFC 6455 machine over
   state; events, ids, signatures,          engine sockets: handshake, frames,
   NIP-19, NIP-44 schedule + MAC,           relay messages, callbacks, teardown;
   filters, wire messages, ws math          defines socketError/Closed/Timeout
      |                                        |
      |  composes                              |  ws://  `open socket` (the idioms
      v                                        |         OnionXT proved on-engine)
   CoinXT (cx*, ABI >= 6): sha256,             |  wss:// `open secure socket`
     Schnorr sign/verify, x-only keys,         |         (UNPROVEN suite-wide)
     ECDH, HMAC - the HARD dependency          v
   SodiumXT (sx*): randomness,              Nostr relays
     constant-time compare - soft
```

The split is not a tidiness preference; both halves are load-bearing:

- **The core does no I/O and holds no connection state**, so it is testable offline and
  deterministic, and it embeds verbatim in the suite's pasteable self-test
  (`tests/suite-selftest.livecodescript` at the repository root) exactly as the other
  pure-script libraries do.
- **The relay layer defines the engine's `socketError` / `socketClosed` / `socketTimeout`
  handlers** - it must, to fail its own connections closed - and those three names are shared
  by every socket user in a process. The suite paste already embeds OnionXT's layer, which
  defines the same three, and the suite generator refuses (as it must) an assembly that
  defines one handler twice. So the relay layer stays OUT of the paste, ships in the demo
  embed instead, and its offline paths are exercised by harness sections that SKIP in the
  paste - the same precedent as OnionXT's `onion-httpd` layer. The relay layer acts only on
  its own socket ids and passes those messages otherwise, so it coexists with any other
  socket library in the same app.

The relay layer composes the core (url parsing, handshake and accept derivation, frame
codec, message build/parse, event verification) and owns only sockets, buffers and handles.
Load the core first.

## What composes what

- **CoinXT (hard, ABI >= 6):** `cxSha256` (event ids), `cxSchnorrSign` / `cxSchnorrVerify`
  (BIP-340 signatures), `cxXOnlyPubkey` (the Nostr pubkey), `cxEcdh` and `cxHmacSha256` (the
  NIP-44 key schedule and MAC), `cxSeckeyIsValid` (key validation). Without CoinXT, every
  path that needs these fails closed with a capability error naming the handler; nothing
  degrades silently.
- **SodiumXT (soft):** `sxRandomBytes` (key and nonce generation - key generation refuses
  outright without it) and `sxMemEqual` (constant-time compare, with a pure-script
  accumulate-loop standing in when absent). Plus the one requested primitive,
  `sxChaCha20IetfXor`, which does not exist yet (`07-capabilities-required.md`).
- **bech32 is implemented in this member, not borrowed from CoinXT**, for a reason worth
  knowing: CoinXT's copy enforces BIP-173's 90-character cap (correct for its Bitcoin
  callers) and keeps its 8-to-5 bit converters private, while NIP-19 waives the cap for TLV
  entities. NostrXT enforces NIP-19's 5000-character SHOULD instead, and the KAT pins full
  BIP-173 conformance INCLUDING asserting the deliberate over-90 deviation as a deviation
  (`03-nip19-entities.md`).
- **OnionXT (future, by composition):** relays are just websocket endpoints, so a `.onion`
  relay reached over OnionXT's transport seam is a planned composition path, not a rewrite -
  and a hedge against the open wss:// question (`08-open-questions.md`).

Dependencies are probed, never assumed: `nxProbeCapabilities()` round-trips each extension
once (a real hash, a real random byte) and caches the answer; a missing extension disables
exactly its feature and never another.

## Honesty status

**Verified statically; needs an OXT pass. Relay paths: verified statically; needs an OXT
pass + a live-relay pass.** Nothing in this member has run on a real OXT engine. What is
machine-verified headlessly on every build: `tools/nostr-kat.py` sweeps the full published
BIP-340, NIP-44 v2, BIP-173 and NIP-19 vector sets through the independent oracle
`tools/nostr_reference.py`, and `tools/check-selftest-vectors.py` re-derives every constant
the member harness pins, by name, both directions. The open engine questions - wss:// above
all - are collected in `08-open-questions.md`, and the source carries a `VERIFY (on-engine)`
label at every point where an engine behaviour is assumed rather than measured.

## Reading order

1. This overview.
2. `01-protocol-model.md` - events, relays, filters and subscriptions: the protocol as one
   coherent model, before any bytes.
3. `02-nip01-events.md` - the canonical serialization (exactly seven escapes, and why owning
   the serializer is what makes ids right), ids, signatures, the event array shape.
4. `03-nip19-entities.md` - bech32 and the npub/nsec/note/TLV entities, and the deliberate
   length-cap deviation.
5. `04-nip44-payloads.md` - the v2 payload byte for byte: conversation key, message keys,
   padding, MAC-before-cipher, and the cipher seam.
6. `05-relay-client.md` - the nxr* state machine, the callback contract, and
   verify-before-deliver.
7. `06-api-reference.md` - the public nx* / nxr* surface, handler by handler.
8. `07-capabilities-required.md` - the one upstream gap (`sxChaCha20IetfXor`), what it
   blocks, and the documented tension with SodiumXT's own rules.
9. `08-open-questions.md` - the honest to-do list: the engine pass, the live-relay pass,
   wss://, onion relays, NIP-17.
10. `09-usage-guide.md` - from zero to a signed event on a relay, for any OXT app.
