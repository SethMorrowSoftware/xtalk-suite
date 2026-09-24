# Riptide Social - a serverless social app on the xTalk suite

> **No server, no account, no hosting bill, no company in the middle.** Your
> identity is an ed25519 key you hold; following someone is knowing their key;
> reaching them is verifying them. One app - a public feed with media, DMs,
> live calls, same-LAN device sync, an anonymous persona and reach into Nostr -
> in pure script over the suite members (section 11).
>
> The **design authority**: rails, rules, security model, roadmap, decisions.
> Bytes are normative in `docs/RIPTIDE-PROTOCOL.md`, "the protocol" below,
> which wins on bytes. The implementation is `riptide/src/riptide.livecodescript`
> (the `rs*` library) plus `riptide/examples/riptide-social.livecodescript`;
> `riptide/CLAUDE.md` holds the as-built decisions and dated evidence. Code
> cites sections by number, so the numbering is stable. **Status:** all eight
> phases built, 1-4 done on two machines, the live passes of 5-8 open (section
> 10.3); anything not marked DONE there is "verified statically; needs an OXT
> pass" ("+ live-Tor pass" for anonymity, "+ live-relay pass" for Nostr).

## 1. Scope & decision

Riptide Social is ONE OXT stack wiring the installed members together in
script. It commits to an **identity-first** architecture: one Argon2id-sealed
master seed derives every key the app uses, so one unlock reconstructs the
feed key, the onion address, the DM keys, the LAN key and the Nostr key - and
the public half of the one identity key IS your handle. Each member owns a
corner the others cannot serve honestly:

| Member | Corner it owns | Why not another |
|---|---|---|
| **SodiumXT** `sx*` | Identity, signing, sealing, stream crypto, KDF, Argon2id | The trust root; no transport does crypto |
| **TorrentXT** `bt*` | Public rendezvous (BEP44 signed DHT), bulk media, serverless DM transport (rp1) | Onion cannot carry a UDP DHT; enet/dc are not many-to-many |
| **OnionXT** `ox*`/`oxh*` | IP-metadata privacy, self-authenticating `.onion` addresses, HTTP over an onion | Tor is the only member that hides the network path |
| **dataChannelXT** `dc*` | Live 1:1 across NATs, per-channel reliability | Torrent latency is seconds; enet needs a reachable IP |
| **enetxt** `en*` | Same-venue realtime at game cadence (your own devices on a LAN) | dc's ICE handshake is overkill on a LAN; torrent/onion are too slow |
| **CoinXT** `cx*` (rail 6) | secp256k1 and BIP-340 for the Nostr key | No other member does secp256k1 |
| **NostrXT** `nx*`/`nxr*` (rail 6) | The Nostr protocol: NIP-01 events, NIP-19, relay sockets | Reach: an audience that already exists |

The unifying idea: **transports are chosen by reachability and metadata cost;
identity is chosen once.**

## 2. Ground rules carried from the family

1. **One thread, one dispatcher**: one FFI round trip per poll, one clock read
   per pass, UI repaint at <= 4 Hz and only on change; ONE dispatcher drains
   every member's poll per tick (section 10.1).
2. **The static gate is law**: `riptide/tools/check-livecodescript.py` on every
   script edit.
3. **Fail-closed capability probes** (section 3.4): a missing member disables
   exactly its feature, with a clear message, and never regresses another.
4. **The honesty convention**: "verified statically; needs an OXT pass", with
   "+ live-Tor pass" for anonymity and "+ live-relay pass" for relays.
5. **One wire format per record, versioned by a magic** and pinned by golden
   vectors: a framing change mints a new magic on both ends, never a silent
   fix; a new rail gets a new salt or record, never a new field.

## 3. The identity foundation - one seed, the whole keyring

### 3.1 The master seed and the unlock

The root secret is a **32-byte master seed** from `sxRandomBytes(32)`, sealed
at rest as `RIPTKEY1` (97 bytes; protocol 2.4): `sxPwHash` (Argon2id,
`sxPwMemInteractive()`, opslimit 2 - the family's sealed-prefs parameters)
turns the passphrase and a fresh 16-byte salt into a wrap key for
`sxSecretBox`. A wrong passphrase fails the Poly1305 tag, never mis-decrypts.

### 3.2 The KDF subkey tree

Every other key is `sxKdfDerive(master, subkeyId, "riptide\0", 32)`
(libsodium's BLAKE2b KDF, an 8-byte context). One seed never feeds two cipher
schemes, so every new use takes a new row (protocol section 2 is normative):

| Subkey | Role | Consumer |
|---|---|---|
| `1` | public identity ed25519 seed | `btDhtKeypair` AND `oxCreateServiceFromSeed`: handle, feed key, public `.onion` |
| `2` | DM crypto_kx seed | the signed prekey and pairwise session keys (section 5) |
| `3` | shared LAN-mesh ed25519 seed | RSL1 admission and sync signatures; every device of one identity derives the SAME key (section 7) |
| `4` | Nostr secp256k1 key candidate | `cxXOnlyPubkey` / `cxSchnorrSign` via the ladder below (section 8A) |
| `5` | app-state sealing key | the `RIPTAPP1` store (section 8A.4) |
| `100 + n` | anon persona n ed25519 seed | `oxCreateServiceFromSeed` only (section 8) |
| `200 + n` | anon persona n DM kx seed | the persona's sealed-DM prekey (section 8.3) |

**The subkey-4 ladder.** A secp256k1 secret must lie in `1..n-1`; a KDF output
is 32 uniform bytes. The gap is about 2^-128 wide, so no real master lands in
it - which is why the rule is easy to get wrong. Riptide re-hashes with
SHA-256, at most 8 rungs, then refuses (bounded, no new dependency, never a
weaker key). `rsNostrSeckeyFrom` takes a CANDIDATE, not a master, so the
untakeable branch is testable: the all-zeros candidate and the group order `n`
both step forward, and both are pinned golden vectors.

### 3.3 Why "reaching you is verifying you" is literally true

A v3 onion address IS an ed25519 public key in base32 (`oxAddressFromPublicKey`
/ `oxPublicKeyFromAddress` are a pure offline bijection), BEP44 signs with
ed25519, and OnionXT builds its service key from a seed via
`sxSignSeedToExpandedKey`, which preserves the public point. Subkey 1 feeds
both, so `oxAddressFromPublicKey(btDhtKeypair(idSeed)["publicKey"])` is your
`.onion` and the handle and the onion are the SAME identity: a follower
computes it locally and Tor proves the far end holds the key - no certificate,
no directory, no hijackable key exchange. The identity secret **never crosses
into libtorrent** (4.2).

### 3.4 The capability matrix

`rsProbeCapabilities()` probes each member once, each in its own `try`:

| Key | Probe | If false |
|---|---|---|
| `canCrypto` | a real `sxSecretBox` round trip | **Hard requirement** (the trust root): the app says so and refuses identity. OnionXT itself also requires SodiumXT ABI >= 6 |
| `hasTorrent` | `btLastError()` answers | no public feed, media or rp1 DMs; identity still works |
| `hasOnion` | `oxVersion()` non-empty | no anon persona; the public app is untouched |
| `hasDataChannel` | `dcLibraryVersion()` non-empty | no calls; DMs stay text over rp1 |
| `hasEnet` | `enLibraryVersion()` non-empty | no LAN device mesh |
| `hasCoin`, `canNostrSign`, `hasNostr`, `hasNostrRelay` | `cxSha3_256Len()`; `nxKeyPublic` of a fixed scalar; an `nxHexEncode` round trip; `nxrVersion()` | no rail 6, or (relay layer only missing) its compute without relay I/O |
| `hasSha3` | `rsSha3` gives 32 bytes (`sxSha3_256`, else `cxSha3_256`) | no offline `.onion` spelling |

Tor readiness is NOT a startup probe (bootstrap is live): a publish that finds
the control port unauthenticated connects and resumes from the status callback.

## 4. Rail 1 - the public feed (TorrentXT BEP44 + bulk)

A signed, mutable DHT pointer names an immutable, content-addressed post
history; followers co-seed the media; nothing is hosted (protocol section 4).

### 4.1 The head - one signed RSH1 record

BEP44 caps a mutable value at 1000 bytes of the BENCODED value, so the head is
a pointer whose raw record MUST be at most 996 bytes. Published under the
identity key at salt `"riptide-head"`, it names a display name, the newest
post, the signed prekey (5.1), an optional onion address, and a
`profileMetaTarget`: an immutable item holding the display name's raw UTF-8
(1..64 bytes), brought under the head's signature by content addressing.
Followers fetch with `btDhtGetMutable(session, handle, "riptide-head")`. Head
ingest is **monotone per handle** (normative since 2026-09-08): a reader keeps
and persists the highest seq it accepted, refuses a lower one and accepts an
equal one, so a replaying DHT node cannot roll it back to a stale head.

### 4.2 Signing without leaking the key

`btDhtBep44SignBuf("riptide-head", seq, v)` builds BEP44's canonical buffer,
`sxSignDetached` signs it with the identity key inside SodiumXT, and
`btDhtPutSigned` stores it after the native layer verifies the signature (a
bad one returns `-3` locally instead of vanishing on the network). `seq` is
the author's monotonic counter, persisted in `RIPTAPP1`; each re-put is a
version every follower's next fetch sees.

### 4.3 Posts - a tamper-evident hash chain

Each post is an immutable `RSP1` item (1..996 bytes): timestamp,
`prevPostTarget`, the text (kind `D` inline, or kind `C` naming 1..16 chunk
items for a long post), up to 8 media info-hashes, and `authorSig` over
everything before it. `prevPostTarget` makes the feed a tamper-evident linked
list walked back from the head, and a post stays verifiable out of DHT
context. A reader verifies the signature and recomputes every content address
before rendering anything.

### 4.4 Media - followers are the CDN

An attachment is a single file seeded in place as a trackerless v1 torrent
(`rsMediaCreate`); its info-hash rides in the post. Followers fetch by magnet,
sequentially, with deadlines on the front pieces (`rsMediaFetch`,
`rsMediaStreamPlan`), and keep seeding, so popular media gets faster as it
spreads. Play unlocks on the contiguous downloaded front (at least 5%), never
on file existence; a non-faststart video keeps its index at the tail and
cannot start early whatever the fetch order. **Followers-only sealed media is
NOT built; it is deferred to its own spec** (the sketch: seal with
`sxEncryptFile`, carry the per-file key in the post). Today every attachment
is public to anyone holding its info-hash.

## 5. Rail 2 - DMs (TorrentXT rp1 + SodiumXT secretstream)

DMs ride **rp1**, TorrentXT's BEP10 peer-wire extension, between peers in a
**phantom swarm** (no tracker, no server, no content), under `sxSecretStream`.

### 5.1 First contact - the inbox rendezvous

Anyone reaches you at a deterministic **inbox swarm**,
`BLAKE2b-20(handlePub || "riptide-inbox")` as 40 hex (`rsInboxId`, joined with
`btAddInfohash`). The first message is an `RSI1` intro (268 bytes: sender
handle, sender kx public, recipient handle, timestamp, signature) **sealed to
the recipient's VERIFIED `RSK1` prekey**, never to the raw handle: `sxSeal`
needs a curve25519 key, and a prekey signed by the identity key makes the seal
target provable. The recipient handle inside the signed body binds the intro
to one inbox, so a replay to a third party is refused; recipients also apply a
freshness window. Outbound: fetch the head, verify the prekey, join their
inbox swarm, send the intro and a stream header to each rp1-capable peer; a
bystander never produces ciphertext the session accepts, so it drops out.

### 5.2 The pairwise session

The lexically smaller handle is the `crypto_kx` client, so both sides derive
the same session with no negotiation (my tx is your rx). The library also
derives a golden-pinned pairwise room, `rsRoomId` =
`BLAKE2b-20(sortedConcat(pkA, pkB) || sessionSalt)`; the reference app keeps
its one conversation in the recipient's inbox swarm. Each direction is its own
secretstream: the header first, then one `sxSecretStreamPush` per `btRp1Send`
(60000-byte cap); a hang-up sends one message with the FINAL tag
(`sxIsFinalTag`). Message kinds: `T` text, `O`/`A` SDP for rail 3.
`btRp1SetToken` is NOT used: a peer authenticates by producing ciphertext the
session accepts. rp1's <= 1 s per-peer tick suits text and is the trigger to
escalate to rail 3.

## 6. Rail 3 - live 1:1 sessions (dataChannelXT)

### 6.1 Signalling over the rail you already have

SDP offer and answer ride the open DM secretstream as kinds `O`/`A`, inheriting
its authentication: no unauthenticated-SDP window, no dead-drop latency. One
blob, non-trickle (shipped when gathering completes), negotiated
automatically. The no-prior-contact cold start (dht-chat's DHT dead-drop) is
deliberately unbuilt: the phase-4 secretstream IS the warm channel.

### 6.2 The session

```
peer   = dcCreatePeer("stun:stun.l.google.com:19302")   -- STUN only, no TURN
chat   = dcCreateChannel(peer, "riptide-call")
typing = dcCreateChannelEx(peer, "riptide-typing", "", true, 0, -1, false, -1)
```

No TURN by design: a symmetric-NAT pair fails visibly rather than relaying
silently. The typing lane (unordered, `maxRetransmits 0`) is created BEFORE ICE
gathering so both channels ride one offer; the callee routes channels BY
LABEL, never arrival order. Both sides send ABSOLUTE state (`"1"`/`"0"`),
debounced, re-asserted every second, and expired locally so a dropped `"0"`
cannot stick; the DTLS session the DM-signalled SDP authenticated scopes the
lane. After the call the rp1 DM carries on. Verified statically; needs the
two-network call pass.

## 7. Rail 4 - same-LAN device sync (enetxt)

Your own devices sync at wire speed on a LAN, within ONE identity, never
follower-facing - the one rail where sub-frame latency matters and ICE would
be pure overhead (protocol section 6). One device hosts with
`enHostCreateServer("", 27099, 32, 3, 0, 0)` (every interface, port 27099, a
small peer cap, three channels); the others `enConnect`.

**Admission** is `RSL1` challenge / response / welcome: a fresh nonce (`C`),
the joiner's signature over it with the shared subkey-3 key (`R`), and the
host's signature over the joiner's response signature (`W`). It is MUTUAL: a
stranger on the same cafe Wi-Fi cannot join, and a rogue host cannot pass as
yours. The `enConnect` rider is a u32 protocol tag only. The LAN domain tags
are prefix-free since 2026-09-09.

**Sync records** are signed under the same key over `"riptide-lan-s"` + the
whole body, verified before parsing, and refused from unadmitted peers:
`D` draft (channel 0: the whole draft as absolute state, <= 4096 bytes,
refuse-not-truncate, applied at a strictly higher per-device seq); `F` feed
state (channel 0: the feed seq applied as MAX, so two devices never publish a
conflicting head, plus a read receipt); `P` presence/typing (channel 1, sent
UNSEQUENCED, enet flag 2 - its own tick makes it reorder-proof); `M` media
handoff (channel 0: a signed POINTER - info-hash, name, size - whose bytes
ride the rail-1 torrent path). **Channel 2 is RESERVED and dark**: a chunked
channel-2 protocol was rejected because it would reimplement libtorrent's
per-piece integrity, resume and backpressure without their proof.

**Honest limits, surfaced in the UI:** records are authenticated, NOT
encrypted (the LAN carries draft plaintext; encryption would need a new
traffic subkey); a pointed-at torrent shows your IP to swarm peers; a fully
offline LAN may not find its swarm, since discovery is the DHT. The live mesh
is verified statically; needs the two-machine pass.

## 8. Rail 5 - the anonymous persona (OnionXT, Model C)

A separate ed25519 identity (subkey `100+n`) that lives ONLY as an onion
service. One persona ships (index 0; section 12).

### 8.1 Why it must be onion-only

The DHT is UDP and rp1 a clearnet peer-wire connection; neither rides Tor, so
a persona that published a head or announced a swarm would leak its IP and
link its key to its DHT presence. It therefore calls none of
`btDhtPutMutable`, `btDhtGetMutable`, `btDhtPutImmutable`, `btAddMagnet`,
`btAddTorrentFile`, `btCreateTorrent`, `btDhtAnnounce` or `btRp1*`, and opens
no dc, enet or Nostr channel: a violation is a deanonymization bug (9.3).

### 8.2 The anon feed - HTTP over an onion

The service is created FROM SEED (`rsAnonCreateService` ->
`oxCreateServiceFromSeed`), so the address stays the persona's identity; the
app does NOT call `oxhServe` (it creates a Tor-generated key) but wires
`oxSetPeerCallback "oxhPeer"` and the onion-httpd routes itself. `GET /`
serves `rsAnonFeedPage`, one deterministic, golden-pinned HTML page with every
entry HTML-escaped - pinned bytes make the feed a wire format, not a
restylable `oxhServeFiles` folder. `GET /prekey` serves the persona's `RSK1`
as 264 hex chars; `POST /dm` is 8.3. The `.onion` travels out of band as a
contact card, never via the DHT, and browsing it proves the follower reached
the key-holder. Serving over HTTP is slower and non-scaling next to a swarm,
the honest cost of anonymity. The live serving is verified statically; needs
an OXT + live-Tor pass.

### 8.3 Anon DMs - sealed over a Tor stream

A follower fetches `/prekey` and verifies it against the very onion it dialed
(subkey `200+n`'s kx public, signed by the subkey-`100+n` persona identity),
then POSTs the sealed `RSI1` intro to `/dm` as EXACTLY 632 lowercase hex
chars. Anything else is refused before any decode; `rsAnonAcceptDm` runs the
seal-open, verify-then-parse path, and every refusal gets one identical reply
so the route is not an oracle. The phase-4 records compose unchanged, the
public identity cannot open the persona's mail, and neither side shows a
swarm or an IP. **Reply over the stream is deliberately unbuilt**: onion-httpd
answers and closes each request, so an accepted intro surfaces its PROVEN
sender and answering is a public-side DM. Bulk transfer uses Model C `BTXO`
framing, which the library builds and parses (`rsBtxoStreamStep`); the app
does not yet wire an anon file transfer. The live leg is verified statically;
needs an OXT + live-Tor pass.

### 8.4 One unlock, two unlinkable identities

One unlock reconstructs both identities, but their public keys are distinct
KDF subkeys and the persona's never appears in a public record, so they are
cryptographically unlinkable. The caveats are surfaced in the UI:
cross-posting, correlated timing or a global passive adversary can still link
them - the tool removes the easy links, not the operator's mistakes.

## 8A. Rail 6 - reach, over Nostr (NostrXT)

### 8A.1 Why a sixth rail, and why it is not a dependency

Added 2026-08-29, the only rail that talks to somebody else's servers (bytes:
protocol section 8). The five rails are sovereign and give no **reach**: a
riptide handle means nothing to someone who does not run riptide. Nostr is
the opposite, honest trade - somebody else's relays, an IP they can see, an
audience already there. So the rail is a **bridge, never a dependency**: none
of it sits on another rail's path, and with no CoinXT, no NostrXT or no relay
reachable, riptide is exactly the phase-7 app. NostrXT owns the protocol
(NIP-01 serialization, BIP-340, NIP-19, filters, relay sockets); riptide owns
the key (8A.2), the bridge (8A.3) and the media convention (8A.5).

### 8A.2 The identity: one more subkey, no new secret to keep

Subkey 4 through the 3.2 ladder: no separate Nostr key to back up. The doors
differ on purpose: `rsNostrKeys` returns only the pubkey and npub,
`rsNostrSignEvent` derives the secret, signs and drops it, and `nsec` export
is a separately named act (`rsNostrExportSeckey`).

### 8A.3 The bridge: a linkage BOTH keys signed

Neither an ed25519 handle nor a secp256k1 npub can sign for the other, so a
one-signature claim is an accusation any key-holder could make about a
stranger's other key. `RSN1` (276 bytes) is signed by BOTH over one preimage,
`"riptide-nostr-b"` + the 148-byte body (magic inside; the domain keeps it out
of the LAN rail's namespace): ed25519 over the preimage, BIP-340 over its
SHA-256. It is published to the **DHT** (BEP44 mutable, identity key, salt
`"riptide-nostr"` - a new salt, never a new `RSH1` field) and to **relays**
(NIP-78 kind `30078`, `d` tag `"riptide.bridge"`, the record as hex;
replaceable, because a bridge is current state). Anyone can copy a bridge, so
the reader requires the record's `nostrPub` to BE the event's author: a copy
verifies as the original author's linkage, never the republisher's. DHT
bridge ingest is monotone per handle, like head ingest. **Publishing the
bridge links the two identities in public and cannot be unpublished**, so it
is always an explicit click, never a side effect, and the UI says so.

### 8A.4 Persistence: the RIPTAPP1 store

Follows, relay lists, counters and seq watermarks survive a restart in a store
sealed under subkey 5 (`rsSealAppState` / `rsOpenAppState`) - sealed because a
follow list IS the social graph, the exact material 8.4 says a persona must
stay unlinked from. The library fixes the envelope (magic, cap, UTF-8 round
trip); the app owns the format inside it.

### 8A.5 Media across the boundary

An attachment rides a note as an `r` tag, `magnet:?xt=urn:btih:<40 hex>`
(ordinary clients render a link); the bytes still ride rail 1, like the
section-7 `M` pointer. Inbound, a non-magnet `r` tag is skipped, and nothing
is fetched automatically: joining a swarm shows the IP, so it is a click.

### 8A.6 What this rail deliberately does NOT do

**Nostr DMs**: NIP-04 is deprecated and needs AES, which this suite lacks
(libsodium ships no CBC); NIP-17 needs an ephemeral-key layer and a metadata
analysis not yet done; section 5 already answers to nobody, and a half-built
encrypted rail beside it would be worse than none. **Automatic NIP-42 auth**:
answering tells the relay who you are, so it is logged and left to the user.
**Dialling on open**: default relays are offered as text and connecting is a
click; phoning a stranger's server on open is a privacy decision made for the
user. **Packaging:** the app embeds two socket libraries (OnionXT, NostrXT's
relay layer), so it defines `socketError` / `socketClosed` / `socketTimeout`
itself and calls both libraries' named functions - the first such stack.

## 9. Security model & honesty

### 9.1 What each layer buys

| Layer | Provides | Does **not** provide |
|---|---|---|
| SodiumXT | Confidentiality, integrity, authenticity; a wrong key or tamper is *rejected* | Metadata privacy; forward secrecy beyond secretstream rekey |
| BEP44 signing | An authenticated, sequence-ordered feed; a tamper-evident post chain | Confidentiality (public feeds are public); deletion (the DHT is append-until-expiry) |
| rp1 phantom swarm | Serverless peer rendezvous and transport | IP privacy - both peers learn each other's address |
| dataChannel | NAT-traversed P2P, DTLS-encrypted transport | Hiding IPs (ICE reveals them); anonymity |
| enet LAN | Device-mesh speed and simplicity; signed records | Anything off the LAN; confidentiality (signed, not encrypted) |
| OnionXT | IP-metadata privacy; a CA-free self-authenticating address | Defence against a global passive adversary or a compromised local tor |
| Nostr relays (8A) | Reach: an existing audience, and durable storage of your public events on servers you do not run | Anything at all. A relay sees your IP, every event you publish and the timing of both; it can drop events, lie by omission, or keep them after you delete. Signatures make its copy trustworthy, not the relay |

### 9.2 Tor hides the route, SodiumXT hides the contents

OnionXT keeps the **network** from learning who talks to whom; SodiumXT keeps
the **contents** unreadable and unforgeable even to a malicious relay or route
handler. Neither substitutes for the other: an onion stream still seals its
payload, and a sealed DM over rp1 still leaks both IPs.

### 9.3 The deanonymization guard

**An anon-persona path calls no `bt*` DHT/torrent/rp1 handler, no dc or enet
channel and no Nostr relay; a public-persona path never serves through the
persona's onion.** The enforcement point is
`rsPersonaAllows(isAnon, transport)`, a pure fail-closed policy over nine
transports (`onion`, `dht`, `torrent`, `rp1`, `enet`, `dc`, `feed`, `media`,
`nostr`, joined 2026-08-29): the persona gets `onion` only, the public
identity everything but `onion`, and an unknown transport refuses for BOTH.
The folded suite harness asserts the full truth table cell by cell (inference
is how the 2026-08-14 review found `feed` and `media` unproven), and the Anon
card paints it live from the function, so the UI cannot drift from the code.

The app asserts it at its real branch points - the dc call
(`rsPersonaAllows(false, "dc")`), the anon publish (`(true, "onion")`), the
relay dial (`(false, "nostr")`); its other transport call sites (16 at the
corrected 2026-08-23 count) are compile-time public-persona paths, where a
guard call would be a constant. **Normative:** anything that adds persona
state routes every new transport branch through the guard, failing closed
with a visible message, never falling back to clearnet. This mirrors the
Model C guard set (`docs/ONIONXT-INTEGRATION-PLAN.md` section 7) and is the
app's highest-severity invariant.

### 9.4 The trust boundary and the honest limits

- **The local tor daemon is trusted**; a compromised one defeats the anonymity
  whatever the crypto. Launching tor is OnionXT's optional lifecycle layer,
  never a requirement.
- **A global passive adversary** is out of scope, as it is for Tor itself.
- **Every anonymity claim in the UI** reads "needs an OXT + live-Tor pass"
  until measured on a real engine against a real daemon.

## 10. Event loop, testing, and roadmap

### 10.1 One dispatcher, never block

The app's one timer handler, `raPoll`, drains `btPoll` + `btRp1Poll`, `enPoll`
with the LAN sync tick, and `dcPoll` with the SDP ship and typing tick, each in
its own `try` so one bad drain never kills the chain; OnionXT and the relay
arrive as engine socket callbacks. A 250 ms paint tier repaints panels,
expires deadlines, and runs the debounced app-state save and relay watchdog.
Long operations are state machines advanced one tick at a time. Cadence: ~33
ms while a dc call or the enet mesh is live (both pump-or-nothing), 250 ms
otherwise (the design allowed up to 1 s).

### 10.2 What is testable without an engine

The static gate on every script edit. **Golden vectors** for everything that
must match byte-for-byte (the KDF tree, identity -> onion, every record,
`inboxId`/`roomId`, BEP44 buffers and targets, the subkey-4 ladder, Nostr
event ids, `BTXO`), held in the oracle `riptide/tools/riptide_reference.py`
(crypto_kx anchored to a real libsodium by `emit-kx-anchor.py`) and exported
with refusal vectors as `riptide/docs/protocol-vectors.json`. **Execution**:
`riptide/tools/check-script-vectors.py` runs the shipped library through the
family's headless interpreter against the committed CoinXT, and
`riptide/tools/check-demo-boot.py` boots the shipped stack headlessly (two
capability profiles, every card) - both settle logic, not the engine's parser.
The rest is the **on-engine VERIFY list** (feed propagation latency, rp1
handshake time, dc connect behind two NATs, enet LAN RTT, onion publish and
inbound, relay behaviour), scripted in `riptide/docs/two-machine-runbook.md`.

### 10.3 Phased roadmap and status

Each phase ends on an OXT pass. Dated records: `riptide/CLAUDE.md`; open legs:
`docs/OXT-PASS-RUNBOOK.md` and `docs/WORK-PLAN.md`.

| Phase | Done when | Status |
|---|---|---|
| 1. Identity + unlock | two runs from one passphrase reconstruct the same handle and `.onion` | **DONE 2026-08-12**: engine-passed on Windows x64, 89/89; re-proven whenever a second machine unlocks the same key file |
| 2. Public feed | a second machine walks the chain and verifies every `authorSig` | **DONE 2026-08-13**: two machines, feeds both directions (live-feed compute ran green 2026-08-12, 133/133) |
| 3. Media | a follower plays a video mid-download | **DONE 2026-08-15**, two machines: a follower fetched and played an attached video, mid-download start not distinguished from a fast full transfer. Measured 2026-08-27: negative as then wired (Play unlocked on file existence); fixed the same day (the contiguous-front floor). Open: the faststart re-run |
| 4. DMs | two machines exchange authenticated encrypted DMs with no server | **DONE 2026-08-15**: two machines, both ways |
| 5. Live sessions (call + typing lane) | a call connects across two networks | **BUILT 2026-08-15**; verified statically. Open: the two-network pass |
| 6. LAN sync | a draft written on one device appears on another, a stranger refused | **BUILT** 2026-08-14 to 08-16. Compute ran green on an engine 2026-08-15 (admission) and 2026-08-20 (sync records). The admission preimage changed 2026-09-09, so admission on the current bytes is verified statically; needs an OXT pass. Open: the two-machine mesh pass |
| 7. Anon persona | reachable and browsable over Tor with zero `bt*` calls provable in a trace | **BUILT** 2026-08-14 to 08-15. Compute ran green on an engine 2026-08-15 (guard, onion derivation, BTXO) and 2026-08-20 (serving seams). Open: needs an OXT + live-Tor pass |
| 8. Nostr reach | a note read by an ordinary Nostr client; a followed npub's note in the timeline; a third party resolves the bridge in BOTH directions | **BUILT 2026-08-29**; compute EXECUTED headlessly against the committed CoinXT (logic, not parsing). The card broke `openStack` on an engine that day (`Chunk: no target found`), was reverted, and was re-landed the same day with `openStack` byte-identical to the engine-proven body behind `check-demo-boot.py`; the re-land was reported working on an engine the same day, and the v11 boot then read 9 passed / 1 failed, the failure the self-check's own defect (suite engine note 5.6), since fixed. Open: the boot re-paste, the in-app bridge reader, an OXT + live-relay pass |

The folded riptide harness is the standing compute record: in the suite paste
on an engine 2026-08-15 (phases 4-7 green bar three malformed-UTF-8 refusals,
which showed `textDecode` does not throw; fixed), green 2026-08-20 on Windows
(338 passed / 0 failed / 2 skipped, the live anon-service legs) and green
2026-08-24 on Windows x86_64 (391/391, incl. the kind-C post and BTXO receive).
Sections added since (Nostr, app state, watermarks, the u64 bound, the
996-byte cap) are verified statically; needs an OXT pass.

## 11. API surface - what exists vs. what is assumed

**Zero compiled-extension changes.** Riptide composes existing public handlers
only (`sx*`, `bt*`, `ox*`/`oxh*`, `dc*`, `en*`, `cx*`, `nx*`/`nxr*`);
`tools/check-handler-calls.py` proves every cross-member call names a real
handler. The one member change it prompted is optional to it: SodiumXT ABI 7
shipped `sxSha3_256` (2026-08-11) after phase 1 found no SHA-3 in the trust
root, and `rsSha3` falls back to CoinXT's `cxSha3_256`. No member calls `rs*`.
**Non-goals**, each a new spec: feed deletion (the DHT is append-until-expiry),
forward-secret group DMs, followers-only sealed media (4.4), Nostr DMs (8A.6).

## 12. Open decisions for the owner

All five decisions this section posed are settled (`docs/OPEN-DECISIONS.md`).

1. **One stack or a stack set?** ONE stack,
   `riptide/examples/riptide-social.livecodescript`: rails behind tabs, one
   dispatcher and one keyring in one script.
2. **Anon persona count.** Exactly one ships (index `0` at every call site);
   many are derivable (subkeys `100+n` / `200+n`).
3. **Prekey rotation.** A single long-term prekey (`rsBuildPrekey` /
   `rsVerifyPrekey`, advertised in the head); rotation would be a later spec.
4. **Feed retention. DECIDED 2026-08-27 (D-06, owner-delegated): a follower
   does NOT republish followed heads.** Privacy-first: republishing amplifies
   retention of someone else's content without consent; a feed going quiet
   while its author is offline is a visible, explainable failure, content
   outliving its author's delete is neither. Revisitable only as an explicit
   per-follow opt-in, never a default. Retention is the author's own re-put.
5. **Which demo first?** Overtaken: the build went through phase 8.

Raised since, not decided here (`docs/WORK-PLAN.md`): whether the 2026-09-09
LAN tag change should have minted a new `RSL1` magic (section 2, rule 5), the
author's own-head refresh cadence while online, and an in-app bridge reader.
