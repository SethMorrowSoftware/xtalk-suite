# 00 - Overview, Protocol and Trust Model

## The one-sentence version

NostrXT lets an xTalk app hold a portable cryptographic identity and publish, fetch and verify
signed events across interchangeable websocket relays, by composing the suite's proven crypto
(CoinXT's BIP-340, SodiumXT's randomness) under a pure-script protocol layer that owns exactly
the byte shuffling family law allows it to own.

Nostr in one line: a keypair IS an identity, a signed event is the ONLY object, and relays are
dumb, untrusted stores reached over websockets - so every guarantee the system offers comes from
the signature on the event, and none comes from the relay. (Status lives in the README's "Gates
and status"; this page is the model.)

## Keys are identity

There are no accounts, no registration, and no recovery. An identity is an x-only secp256k1
public key: 32 bytes, 64 lowercase hex on this API. The matching secret key signs every event
that identity will ever publish. NostrXT mints and validates keys by composition, never itself:
`nxKeyGenerate` draws bytes from SodiumXT's `sxRandomBytes` and validates them with CoinXT's
`cxSeckeyIsValid`; `nxKeyPublic` is CoinXT's `cxXOnlyPubkey`.

For humans, keys wear a bech32 coat (`03-nip19-entities.md`): `npub1...` is the display form of
a public key, `nsec1...` of a secret key. The coats are display encodings of the same 32 bytes.
Two consequences, both enforced in code:

- **Losing the secret key is losing the identity, and leaking it is total.** There is no
  revocation. `nxUriEncode` therefore REFUSES to wrap an nsec in a shareable `nostr:` URI,
  because a secret key in a URI is a secret key in somebody's chat log. The app decides how the
  key lives at rest; NostrXT deliberately is not a key vault.
- **Key equality is the only identity check.** A display name (kind 0 metadata) is a claim
  anyone can make; a NIP-05 identifier (`nxNip05Verify`) is a DNS-trust attestation, useful and
  spoofable at the DNS layer. The pubkey is the identity.

## Events are the only object

Everything - a note, a profile, a contact list, a deletion request, an encrypted DM envelope -
is one record shape: `{id, pubkey, created_at, kind, tags, content, sig}` (an xTalk array here;
the exact shape is in `02-nip01-events.md`). The `id` is the SHA-256 of a canonical
serialization of the other fields, and the `sig` is a BIP-340 Schnorr signature by `pubkey` over
that id - the same scheme Bitcoin's Taproot uses, which is why CoinXT already had it. So an
event is **self-authenticating**: anyone holding it can recompute the id and verify the
signature with no server's help, and no relay, cache, mirror or forwarder can alter a field
without detection. That property only works if it is USED:

> **Verify, then trust (this member's rule 2).** `nxEventVerify` recomputes the id from the
> fields AND verifies the signature over it; only a true from that function makes an inbound
> event worth believing. The relay layer enforces this by default: `nxrConnect`ed relays
> deliver an event to the app only after verification, and a failing event arrives as the
> `"invalid"` callback with the reason, never as an `"event"` (`05-relay-client.md`). An app
> that turns verification off with `nxrSetVerify` owns that decision, eyes open.

## Relays are untrusted stores

A relay is a websocket server that accepts signed events and answers subscriptions (filters).
That is the entire job description. Clients publish to and read from several relays precisely
because no single relay is trusted or load-bearing; a relay that censors or dies is replaced by
changing a URL.

What a relay CAN do to you, all of it undetectable from any single response:

- **Drop** your events, or anyone's. The `OK` message tells you a relay's verdict on your own
  publish; nothing tells you what it later serves to others.
- **Delay** delivery, reorder history, or serve stale views.
- **Lie by omission.** A relay answering with fewer events than it holds is indistinguishable
  from one that never had them. `EOSE` means "I am done answering", not "that was everything".
- **Replay across relays.** Any event it has seen can be forwarded anywhere, forever. Deletion
  (kind 5, `nxDeleteBuild`) is a REQUEST that other relays may honour or ignore.
- **Log your IP, and your interests.** Your REQ filters tell the relay exactly which pubkeys
  and kinds you care about, tied to your connection metadata. This is the privacy floor of the
  protocol, and no payload encryption raises it.

What a relay CANNOT do: **forge a signed event.** It cannot mint an event from your pubkey,
alter one of yours, or backdate a field without breaking the signature - provided the client
verifies (an unverifying client grants a relay all of these powers).

## The metadata realities (what NIP-44 itself documents)

Encrypting `content` with NIP-44 (`04-nip44-payloads.md`) protects exactly the payload bytes,
and the NIP says so. Carried here so the UI never overpromises:

- `created_at`, `kind`, `tags` and both parties' pubkeys stay public on the event: who talks to
  whom, and when, is visible to every relay that carries the envelope.
- **No forward secrecy.** The conversation key is static per pair of keys; a future compromise
  of either secret key decrypts every past payload.
- No deniability and no post-compromise security: NIP-44 is an encryption format, not a
  messaging protocol.

## Where Tor fits

Two different problems, two different tools:

- **wss:// hides content from the wire, not interest from the relay.** TLS stops a network
  observer reading events and filters in flight; the relay still sees your IP, filters and
  publishes. (The 2026-08-24 live run proved the wss:// CHANNEL comes up, not that the
  certificate behind it was checked; `05-relay-client.md`.)
- **A .onion relay over OnionXT is the anonymity path.** The relay layer's transport is
  ordinary engine sockets, the substrate OnionXT's SOCKS client speaks, so a future composition
  would dial a relay's onion address through OnionXT's transport seam and the relay never learns
  your IP. That closes the "log your IP" row above; the "log your interests" row it can only
  pseudonymize (the filters are now tied to a circuit instead of an address). It is a planned
  composition, not shipped code, and it inherits OnionXT's threat model
  (`onionxt/docs/01-threat-model.md`), traffic correlation out of scope included.

## The trust boundaries

- **Trusted:** your secret key handling, the CoinXT and SodiumXT crypto this member composes,
  and the local process.
- **Verified, then trusted:** every event, from anywhere - `nxEventVerify` is the border
  checkpoint.
- **Untrusted:** every relay, every payload before its MAC verifies, the network, and every
  claim (names, NIP-05, profile fields) that is not a key.

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
      |  composes                              |  wss:// `open secure socket`
      v                                        |    (live 2026-08-24; certificate
   CoinXT (cx*, ABI >= 6): sha256,             |    checks unmeasured)
     Schnorr sign/verify, x-only keys,         |  ws://  `open socket` (OnionXT's
     ECDH, HMAC - the HARD dependency          |    idioms; never run in this file)
                                               v
   SodiumXT (sx*): randomness,              Nostr relays
     constant-time compare, the
     NIP-44 cipher - soft
```

- **The core does no I/O and holds no connection state**, so it is testable offline and
  deterministic, and it embeds verbatim in the suite's pasteable self-test
  (`tests/suite-selftest.livecodescript` at the suite root) like the other pure-script
  libraries.
- **The relay layer defines the engine's `socketError` / `socketClosed` / `socketTimeout`** - it
  must, to fail its own connections closed - and those three names are shared by every socket
  user in a process. The suite paste already embeds OnionXT's layer, which defines the same
  three, and the generator refuses an assembly that defines one handler twice. So the relay
  layer stays OUT of the paste and ships in the demo embed (the precedent is OnionXT's
  `onion-httpd` layer); its offline paths run as harness sections that SKIP in the paste. It
  acts only on its own socket ids and passes the rest, and each message is a thin wrapper over a
  named function an embedder can call instead (`06-api-reference.md`), so it coexists with any
  other socket library in one app.

The relay layer composes the core (url parsing, handshake and accept derivation, frame codec,
message build/parse, event verification) and owns only sockets, buffers and handles. Load the
core first.

## What composes what

- **CoinXT (hard, ABI >= 6):** `cxSha256` (event ids), `cxSchnorrSign` / `cxSchnorrVerify`
  (BIP-340), `cxXOnlyPubkey` (the Nostr pubkey), `cxEcdh` and `cxHmacSha256` (the NIP-44 key
  schedule and MAC), `cxSeckeyIsValid`. Without CoinXT every path that needs these fails closed
  with a capability error naming the handler; nothing degrades silently.
- **SodiumXT (soft):** `sxRandomBytes` (key and nonce generation - key generation refuses
  outright without it), `sxMemEqual` (constant-time compare, with a pure-script accumulate loop
  standing in when absent), and `sxChaCha20IetfXor`, the NIP-44 cipher, shipped upstream in
  SodiumXT ABI 10 on 2026-08-23 (`07-capabilities-required.md` gap #1). An installed SodiumXT
  older than that makes NIP-44 fail closed, by design.
- **bech32 is implemented in this member, not borrowed from CoinXT:** CoinXT's copy enforces
  BIP-173's 90-character cap and keeps its bit converters private, while NIP-19 waives the cap
  for TLV entities (`03-nip19-entities.md`).
- **OnionXT (a future composition):** a `.onion` relay over OnionXT's transport seam is a
  composition at that seam, not a rewrite of the relay layer (it needs a transport seam in
  `nxrConnect`); `07-capabilities-required.md` records it as a scope decision.

Dependencies are probed, never assumed: `nxProbeCapabilities()` round-trips each extension once
(a real hash, a real random byte) and caches the answer; a missing extension disables exactly
its feature and never another.
