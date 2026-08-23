# NostrXT

**Nostr protocol layer for OpenXTalk (OXT) / the xTalk family: signed events, bech32 entities, encrypted payloads, and a relay client, in pure script over the suite's proven crypto.**

NostrXT gives an xTalk app the whole client side of the Nostr protocol
(events signed with BIP-340 over secp256k1, published to and fetched from
dumb websocket relays) without adding one line of cryptography of its own:

1. **NIP-01 events** - build, canonically serialize, id, sign, and verify
   events. The canonical serializer is owned byte for byte (exactly seven
   escapes; every other control byte verbatim), because a borrowed JSON
   encoder produces well-formed WRONG event ids.
2. **NIP-19 entities** - `npub` / `nsec` / `note` and the TLV forms
   (`nprofile` / `nevent` / `naddr`), plus `nostr:` URIs, over a bech32
   implementation pinned to the BIP-173 vectors.
3. **NIP-44 v2 encrypted payloads** - the conversation key, message keys,
   padding and MAC are implemented and vector-pinned today; the raw ChaCha20
   cipher call is the one primitive missing upstream, so encrypt/decrypt
   fail closed with a clear capability error until SodiumXT ships it
   (see `docs/07-capabilities-required.md`).
4. **NIP-01 filters and relay messages** - filter building, client-side
   filter matching, and the REQ / CLOSE / EVENT / AUTH wire messages,
   with a strict owned JSON parser for what relays send back.
5. **A relay client** - an RFC 6455 websocket state machine over engine
   sockets that verifies every inbound event (id + signature) before
   delivering it, fails closed on every wire error, and reports through
   per-relay callbacks.
6. **Discovery and proof of work** - NIP-05 identifier verification (the
   fetch is the app's), NIP-11 relay information parsing, NIP-13 difficulty.

```
   your xTalk app
      |  build / sign / verify / encode        |  connect / subscribe / publish
      v                                        v
   nx* core                                 nxr* relay client
   src/nostrxt.livecodescript               src/nostr-relay.livecodescript
   PURE COMPUTE, no I/O, no state           the stateful websocket machine:
   beyond the error surface:                handshake, frames, NIP-01 relay
   events + canonical JSON, NIP-19,         messages in and out, per-relay
   NIP-44 schedule + MAC, filters,          callbacks, verify-before-deliver
   ws framing math, JSON parser                |
      |                                        |  ws://  engine `open socket`
      |  composes (probed, never assumed)      |  wss:// engine `open secure
      v                                        v         socket` - UNPROVEN
   CoinXT (cx*, ABI >= 6, HARD):            Nostr relays (dumb websocket
     cxSha256, cxSchnorrSign/Verify,        stores; the app picks them,
     cxXOnlyPubkey, cxEcdh,                 the user can change them)
     cxHmacSha256, cxSeckeyIsValid
   SodiumXT (sx*, soft):
     sxRandomBytes, sxMemEqual
     [sxChaCha20IetfXor: requested
      upstream, not yet shipped]
```

## Why this matters

Most social and messaging platforms own three things the user should own:
the identity (an account the platform can close), the address book (a graph
the platform can mine), and the archive (posts the platform can delete).
Nostr inverts all three with one move: identity is a keypair the user holds,
every event is signed with it and self-verifying anywhere, and relays are
interchangeable dumb stores - if one bans you or dies, you publish the same
signed events to another and nothing about your identity changes. For the
xTalk family this is a natural fit: the hard cryptography already exists in
CoinXT (BIP-340 landed there for Bitcoin's sake and is exactly Nostr's
signature scheme) and SodiumXT, so the whole protocol layer is pure,
readable script over proven native ground - the same shape as OnionXT over
a tor daemon. And because relays are just websocket endpoints, a future
`.onion` relay over OnionXT's transport seam is a composition, not a
rewrite (`docs/08-open-questions.md`).

## What NostrXT is NOT

- **It is not a key vault.** Secret keys cross this API as 64-hex strings
  and NostrXT holds none of them beyond the call. Where a key lives at rest
  (a password manager, a SodiumXT-sealed file, a prompt every launch) is the
  app's decision, and the app should treat `nsec` strings as the passwords
  they are.
- **It is not a NIP-04 implementation, by decision.** NIP-04 direct messages
  need AES-256-CBC; no AES exists anywhere in this suite, libsodium
  deliberately provides no CBC mode so SodiumXT never will, and NIP-04 is
  superseded by NIP-44 (which also fixes NIP-04's malleability and metadata
  problems). Implementing a deprecated scheme would mean hand-rolling a
  cipher, which family law forbids. This is a decision with reasons, not a
  gap waiting for code.
- **It is not a relay server.** NostrXT speaks the client side of NIP-01.
  Storing and serving other people's events is a different program.
- **It hand-rolls no cryptography.** SHA-256, Schnorr, x-only keys, ECDH and
  HMAC are CoinXT calls; randomness and constant-time compare are SodiumXT
  calls. What NostrXT owns in pure script is exactly the checksummed byte
  shuffling family law allows there: JSON bytes, bech32 bit packing, the
  NIP-44 key schedule and padding, websocket framing math.
- **Encrypted DMs are not complete until the upstream cipher ships.**
  NIP-44's raw ChaCha20 exists nowhere in the suite; the requested SodiumXT
  primitive is `sxChaCha20IetfXor` (`docs/07-capabilities-required.md`).
  Until it lands, `nxNip44Encrypt` / `nxNip44Decrypt` fail closed with a
  capability error naming it - the key schedule, padding and MAC paths work
  and are vector-pinned today, and the harness already proves the
  MAC-before-cipher order.

## Layout

```
nostrxt/                    (the NostrXT member of the xtalk-suite monorepo)
  README.md                 you are here
  IMPLEMENTATION-PLAN.md    the phased build order and the open phases
  LICENSE                   MIT; NostrXT bundles no third-party code
  docs/
    00-overview.md          what Nostr is, the two-file split, the reading order
    01-protocol-model.md    events, relays, filters: the protocol as a model
    02-nip01-events.md      canonical serialization, ids, signatures, byte for byte
    03-nip19-entities.md    bech32 and the npub/nsec/note/TLV entities
    04-nip44-payloads.md    the v2 payload: key schedule, padding, MAC, the cipher seam
    05-relay-client.md      the nxr* websocket state machine and callback contract
    06-api-reference.md     the public nx* / nxr* surface
    07-capabilities-required.md  the one upstream gap (sxChaCha20IetfXor) and its tension
    08-open-questions.md    the honest to-do list (wss://, onion relays, NIP-17)
    09-usage-guide.md       from-zero guide for any OXT app that uses NostrXT
  src/
    nostrxt.livecodescript      the pure-compute core (public nx*)
    nostr-relay.livecodescript  the relay client over engine sockets (public nxr*)
  examples/
    nostrxt-tests.livecodescript  the offline, deterministic member self-test
  tools/
    nostr_reference.py      the independent Python oracle (anchored at import)
    nostr-kat.py            sweeps the full published vector sets; emits the
                            constants the harness pins, with source URLs
    check-selftest-vectors.py  re-derives every pinned harness constant by name
    check-livecodescript.py the family's static gate (carried, byte-identical)
    check-docs-style.py     the prose house-style gate (no dashes / curly quotes)
```

## Install / verify

NostrXT is two `.livecodescript` stacks and needs no native build of its
own; the native crypto arrives through the sibling extensions.

1. Install **CoinXT** (the `cx*` extension, ABI >= 6 - it carries BIP-340)
   and **SodiumXT** into the engine. CoinXT is the HARD dependency: without
   it, ids, signing, verification and the NIP-44 key schedule all fail
   closed with capability errors. SodiumXT is soft: without it, key
   generation refuses and constant-time compare falls back to a pure-script
   loop.
2. Load the core, then the relay client (the relay layer composes the core,
   so the core must be in the message path):

   ```
   start using stack "nostrxt"          -- src/nostrxt.livecodescript
   start using stack "nostr-relay"      -- src/nostr-relay.livecodescript (only if you need sockets)
   ```

3. Probe from the message box:

   ```
   put nxVersion()
   ```

   which answers `NostrXT 0.1.0`. Then `put nxProbeCapabilities()["canSign"]`
   tells you whether CoinXT round-tripped, and the member self-test
   (`examples/nostrxt-tests.livecodescript`, entry point `nxSelfTest()`)
   prints the full report with per-check PASS / FAIL / SKIP lines.

`docs/09-usage-guide.md` walks the first signed event and the first relay
subscription end to end.

## Gates and status

**STATUS: verified statically; needs an OXT pass. Relay paths additionally:
verified statically; needs an OXT pass + a live-relay pass.** Nothing in
this member has run on a real OXT engine yet, and nothing here claims
otherwise - the honesty convention is the family's law.

What IS machine-verified, headlessly, on every build:

- `tools/nostr-kat.py --check` sweeps the **full published vector sets**
  through `tools/nostr_reference.py`, an independent Python implementation
  that anchors itself to a transcribed vector subset at import (a broken
  oracle refuses to load): the complete official BIP-340 `test-vectors.csv`
  including every negative row, the complete official NIP-44 v2 set
  (conversation keys valid and invalid, message keys, padded lengths,
  encrypt/decrypt, invalid payloads and the invalid plaintext lengths), the
  BIP-173 valid and invalid strings, and the published NIP-19 examples.
  Every source URL is named in the tool. One deviation is deliberate and
  the KAT asserts it AS a deviation: NIP-19 waives BIP-173's 90-character
  cap for TLV entities, so the "overall max length exceeded" vector decodes
  here on purpose (NostrXT enforces NIP-19's 5000-character SHOULD instead,
  fail closed). This is also why bech32 is implemented in this member
  rather than borrowed: CoinXT's copy enforces the 90-character cap its
  Bitcoin callers need, and its 8-to-5 bit converters are private.
- `tools/check-selftest-vectors.py` re-derives **every pinned constant in
  the harness by name** (38 as this is written; the gate's own output is
  the authoritative count) through the KAT and the oracle, both directions:
  a derived vector that is not pinned fails, a pinned constant the KAT does
  not derive fails, and any other long literal in harness code must be
  listed as an input with a written reason. A transcription slip cannot
  produce a harness that agrees with itself.
- `tools/check-livecodescript.py` (the family's unified static gate,
  byte-identical across members) and `tools/check-docs-style.py` hold the
  script and prose rules.

What is NOT verified and says so in the source: every on-engine behaviour
(the harness and both libraries carry `VERIFY (on-engine)` labels where an
engine question is open), and above all **wss://**. The relay client writes
the `open secure socket` path, but nothing in this whole suite has ever
opened a TLS socket - certificate verification, TLS version support and
failure delivery are unmeasured engine questions, flagged in the source and
carried in `docs/08-open-questions.md`. The ws:// path mirrors the socket
idioms OnionXT proved on-engine, which is evidence about the idioms, not
about this file.

## Troubleshooting

The failure modes a first setup actually hits. Every `nx*` function fails
by returning empty (or false) with the reason in `nxLastError()`; every
`nxr*` command reports through `the result` - read those first.

### Ids, signing or verification return empty; `nxLastError()` says "needs CoinXT ..."

CoinXT (ABI >= 6) is not loaded into the message path. NostrXT probes its
dependencies with real round-trips and fails closed per feature: nothing
signs, ids, verifies or derives NIP-44 keys without CoinXT. Install the
CoinXT extension and re-open the stack (the capability probe is cached;
`nxNip44HasCipher()` is the one live re-probe).

### `nxNip44Encrypt` / `nxNip44Decrypt` return empty naming `sxChaCha20IetfXor`

Expected today, not a setup error: the raw ChaCha20 primitive has not
shipped in SodiumXT yet (`docs/07-capabilities-required.md`). The payload
is refused fail-closed at the cipher seam; everything up to it (conversation
key, message keys, padding, MAC) works and is vector-pinned.

### Relay verbs throw "can't find handler" (nxWsUrlParse, nxClientReq, ...)

The relay layer is loaded but the core is not. `nostr-relay` composes the
`nx*` core and owns only sockets, buffers and handles - `start using stack
"nostrxt"` as well, before you need the relay.

### Every inbound event arrives as the "invalid" callback

Verification is ON by default and fails closed: without CoinXT, events
cannot be verified, so they are delivered as `"invalid"` with the reason,
never as unverified `"event"`s. Install CoinXT, or - eyes open, per relay -
`nxrSetVerify <relay>, false` for raw delivery.

### A `wss://` relay will not connect, or fails strangely

wss:// is the suite's open TLS question (see Gates and status): the path is
written but has never run. If the relay offers a ws:// form, prove your
wiring against that first; whatever the engine does with `open secure
socket`, record it - that observation is the pass `docs/08-open-questions.md`
is waiting for.

### A dial hangs with no error callback at all

If your app defines `socketError`, `socketClosed` or `socketTimeout`, it
must `pass` the ones that are not its own. Those three names are the
engine's, shared by every socket user in the process; the relay layer acts
only on its own socket ids and passes the rest, and an app that swallows
them starves every other socket library silently - the symptom is a hang,
not an error (the family rule; see the suite's engine-behaviour ledger,
`docs/OXT-ENGINE-NOTES.md` at the repository root).

## House style

ASCII only in `.livecodescript`. No em-dashes anywhere, docs included
(hyphens, commas, colons, parentheses). Comment the *why*, densely. These
are enforced by `tools/check-livecodescript.py` and `tools/check-docs-style.py`,
and they are not optional: curly quotes fail OXT compilation outright.
