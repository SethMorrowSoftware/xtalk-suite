# 01 - Protocol and Trust Model

> STATUS: verified statically; needs an OXT pass. Everything relay-facing additionally
> needs a live-relay pass. Nothing described here has run on a real engine; the
> pure-compute claims are pinned by `tools/nostr-kat.py` against the published
> BIP-340, NIP-44, BIP-173 and NIP-19 vector sets.

## The one-sentence version

Nostr is a protocol where a keypair IS an identity, a signed event is the ONLY object,
and relays are dumb, untrusted stores reached over websockets - so every guarantee the
system offers comes from the signature on the event, and none comes from the relay.

## Keys are identity

There are no accounts, no registration, and no recovery. An identity is an x-only
secp256k1 public key: 32 bytes, 64 lowercase hex on this API. The matching secret key
signs every event that identity will ever publish. NostrXT mints and validates keys by
composition, never itself (the family's no-hand-rolled-crypto law): `nxKeyGenerate`
draws bytes from SodiumXT's `sxRandomBytes` and validates them with CoinXT's
`cxSeckeyIsValid`; `nxKeyPublic` is CoinXT's `cxXOnlyPubkey`.

For humans, keys wear a bech32 coat (see `03-nip19-entities.md`): `npub1...` is the
display form of a public key, `nsec1...` of a secret key. The coats are display
encodings, nothing more - decoding an npub yields the same 32 bytes the protocol uses.
Two consequences follow and both are enforced in code:

- **Losing the secret key is losing the identity, and leaking it is total.** There is
  no revocation. `nxUriEncode` therefore REFUSES to wrap an nsec in a shareable
  `nostr:` URI, because a secret key in a URI is a secret key in somebody's chat log.
- **Key equality is the only identity check.** A display name (kind 0 metadata) is a
  claim anyone can make; a NIP-05 identifier (`nxNip05Verify`) is a DNS-trust
  attestation, useful and spoofable at the DNS layer. The pubkey is the identity.

## Events are the only object

Everything - a note, a profile, a contact list, a deletion request, an encrypted DM
envelope - is one record shape: `{id, pubkey, created_at, kind, tags, content, sig}`.
In this library that record is an xTalk array (the exact shape is in
`02-nip01-events.md`). The `id` is the SHA-256 of a canonical serialization of the
other fields, and the `sig` is a BIP-340 Schnorr signature by `pubkey` over that id.
So an event is **self-authenticating**: given nothing but the event itself, anyone can
recompute the id and verify the signature, and no relay, cache, mirror or forwarder
can alter a field without detection.

That property is why the whole trust model works, and it only works if it is USED:

> **Verify, then trust (this member's rule 2).** `nxEventVerify` recomputes the id
> from the fields AND verifies the signature over it; only a true from that function
> makes an inbound event worth believing. The relay layer enforces this by default:
> `nxrConnect`ed relays deliver an event to the app only after verification, and a
> failing event arrives as the `"invalid"` callback with the reason, never as an
> `"event"` (see `05-relay-client.md`). An app that turns verification off with
> `nxrSetVerify` owns that decision, eyes open.

## Relays are untrusted stores

A relay is a websocket server that accepts signed events and answers subscriptions
(filters). That is the entire job description. Clients publish to several relays and
read from several relays precisely because no single relay is trusted or load-bearing.

What a relay CAN do to you, all of it undetectable from any single response:

- **Drop** your events, or anyone's - refuse to store, refuse to forward. The `OK`
  message tells you a relay's verdict on your own publish; nothing tells you what it
  later serves to others.
- **Delay** delivery, reorder history, or serve stale views.
- **Lie by omission.** A relay answering a subscription with fewer events than it
  holds is indistinguishable from a relay that never had them. `EOSE` means "I am done
  answering", not "that was everything that exists".
- **Replay across relays.** Any event it has seen can be forwarded anywhere, forever.
  Publishing to one relay is publishing to the world; deletion (kind 5,
  `nxDeleteBuild`) is a REQUEST that other relays may honour or ignore.
- **Log your IP, and your interests.** Your REQ filters tell the relay exactly which
  pubkeys and kinds you care about, tied to your connection metadata. This is the
  privacy floor of the protocol, and no payload encryption raises it.

What a relay CANNOT do:

- **Forge a signed event.** It cannot mint an event from your pubkey, alter one of
  yours, or backdate a field, without breaking the signature - provided the client
  verifies (rule 2 again; an unverifying client grants a relay all of these powers).

## The metadata realities (what NIP-44 itself documents)

Encrypting `content` with NIP-44 (see `04-nip44-payloads.md`) protects exactly the
payload bytes and nothing else, and the NIP says so in as many words. Carried here so
the UI never overpromises, in the onionxt threat-model tradition:

- `created_at`, `kind`, `tags` and both parties' pubkeys stay public on the event.
  Who talks to whom, and when, is visible to every relay that carries the envelope.
- **No forward secrecy.** The conversation key is static per pair of keys; a future
  compromise of either secret key decrypts every past payload.
- No deniability and no post-compromise security either; NIP-44 is an encryption
  format, not a messaging protocol, and it says exactly that about itself.

## Where Tor fits (later)

Two different problems, two different tools, and it is worth keeping them apart:

- **wss:// hides content from the wire, not interest from the relay.** TLS to a relay
  stops a network observer reading your events and filters in flight. The relay still
  sees everything: your IP, your filters, your publishes. (And wss:// is the suite's
  open transport question - nothing in this tree has ever opened a secure socket; see
  `05-relay-client.md`.)
- **A .onion relay over OnionXT is the anonymity path.** The relay layer's transport
  is ordinary engine sockets, the same substrate OnionXT's SOCKS client speaks, so a
  future composition dials a relay's onion address through OnionXT's transport seam
  and the relay never learns your IP. That closes the "log your IP" row above; the
  "log your interests" row it can only pseudonymize (the relay still sees the filters,
  now tied to a circuit instead of an address). This is a planned composition, not a
  shipped one, and it inherits OnionXT's own threat model (its `docs/01-threat-model.md`)
  including the honest ceiling: traffic correlation stays out of scope.

## The trust boundaries, stated plainly

- **Trusted:** your secret key handling, the CoinXT and SodiumXT crypto this member
  composes, and the local process.
- **Verified, then trusted:** every event, from anywhere - `nxEventVerify` is the
  border checkpoint.
- **Untrusted:** every relay, every payload before its MAC verifies, the network, and
  every claim (names, NIP-05, profile fields) that is not a key.
