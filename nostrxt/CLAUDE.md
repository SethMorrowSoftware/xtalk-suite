# CLAUDE.md

This file guides Claude Code (claude.ai/code) when working in the NostrXT member of the
xtalk-suite monorepo (`nostrxt/`).

> **Read the docs first.** [docs/00-overview.md](docs/00-overview.md) (architecture),
> [docs/01-protocol-model.md](docs/01-protocol-model.md) (what a relay can and cannot do to you),
> [docs/02-nip01-events.md](docs/02-nip01-events.md) (the canonical bytes, the one thing this
> member must never get wrong), [docs/04-nip44-payloads.md](docs/04-nip44-payloads.md) and
> [docs/07-capabilities-required.md](docs/07-capabilities-required.md) (the one crypto gap and
> whose it is), and [docs/05-relay-client.md](docs/05-relay-client.md) (the socket state machine).
> [IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md) is the phased HOW. This file is the
> operational as-built record and the hard-won-lesson list, in the same spirit as the sibling
> `CLAUDE.md` files; most lessons below are CARRIED from OnionXT (sockets), CoinXT (vectors and
> canonical bytes) and riptide (the no-throw library shape) so we do not pay for them twice.

House style: no em-dashes (hyphens, commas, colons, parentheses). ASCII only in
`.livecodescript`, even in comments and strings. Comment the *why*, densely; match the
surrounding style.

## What this is

**NostrXT** is a Nostr protocol layer for OpenXTalk (OXT) / the xTalk family. It lets an xTalk
app (1) build, sign, verify, encode and parse Nostr events (NIP-01, with BIP-340 signatures over
secp256k1), (2) speak the human formats (NIP-19 bech32 entities, NIP-21 URIs), (3) run the
NIP-44 v2 encrypted-payload construction, and (4) talk to relays over websockets (RFC 6455 in
pure script over engine sockets), including NIP-42 auth, NIP-01 filters and subscriptions. It
adds **no cryptography of its own**: hashes, signatures and ECDH are CoinXT calls, randomness
and constant-time compare are SodiumXT calls.

```
app (xTalk)
   |- nx*  src/nostrxt.livecodescript      the CORE: pure compute, no I/O, no sockets
   |         events + canonical JSON, NIP-19 bech32/TLV, NIP-44 schedule + padding + MAC,
   |         filters, wire messages, websocket framing math, PoW, NIP-05/NIP-11 parsing
   |         |- composes CoinXT  (cx*: sha256, Schnorr, x-only keys, ECDH, HMAC)  HARD for crypto
   |         |- composes SodiumXT (sx*: randomness, constant-time compare)        soft
   |- nxr* src/nostr-relay.livecodescript  the RELAY CLIENT: engine sockets, handles, buffers
             ws:// today (the onionxt socket idioms); wss:// written but engine-unproven
```

The split into two files is **load-bearing, not aesthetic**: the suite paste embeds the core
verbatim, and the relay layer defines the engine's `socketError` / `socketClosed` /
`socketTimeout` handlers, which the embedded OnionXT layer also defines. Two definitions of one
handler refuse the paste build, so the relay layer ships in the demo embed instead (the
onion-httpd precedent) and its offline paths are exercised by probe-guarded harness sections
that SKIP in the paste.

## How NostrXT differs from its siblings (read this before you assume)

1. **Unlike OnionXT, the core is stateless and does no I/O** (the riptide shape): every nx*
   handler is bytes-and-strings in, bytes-and-strings out, offline-testable. Only the nxr*
   layer owns sockets, and it is a separate file for the reason above.
2. **Unlike CoinXT, the interop surface is TEXT, not transactions**: the canonical NIP-01
   serialization is the contract. One wrong escape byte changes every event id this member
   ever computes. That is why the serializer is owned (a stock JSON encoder escapes control
   bytes NIP-01 says to pass verbatim) and why it is pinned byte-for-byte by the KAT and the
   vector gate.
3. **Unlike both, it carries its own bech32.** CoinXT's is engine-proven but enforces
   BIP-173's 90-character cap in both directions and keeps its bit converters private; NIP-19
   waives the cap for TLV entities. NostrXT implements bech32/bech32m uncapped (NIP-19's
   5000-character SHOULD is enforced instead) and the KAT asserts the deviation ON PURPOSE, so
   it can never drift silently. This is the checksummed byte shuffling family law allows in
   script; it is not cryptography.
4. **The two layers have different error conventions, both deliberate.** Core nx* handlers
   NEVER throw: functions return empty (or false) and record the reason for `nxLastError()`;
   every cx*/sx* call sits inside a try. Relay nxr* commands report through `the result`
   (empty on success, a "NostrXT relay: ..." string on refusal; handle-yielding commands
   return the integer, so callers test `the result is an integer`), the OnionXT shape for a
   stateful layer. Do not mix them.

## The rules that make this safe and correct

1. **Add no cryptography. Compose CoinXT and SodiumXT.** SHA-256, BIP-340 Schnorr, x-only
   keys, ECDH and HMAC-SHA256 are cx* calls; randomness and constant-time compare are sx*
   calls. The one missing primitive (NIP-44's raw ChaCha20) is an UPSTREAM SodiumXT feature
   request (`sxChaCha20IetfXor`, docs/07), never a hand-rolled cipher here: until it ships,
   `nxNip44Encrypt` / `nxNip44Decrypt` fail closed with a capability error naming it, and the
   harness proves the MAC-verifies-before-cipher order today.
2. **Verify, then trust.** An event from a relay is untrusted text until `nxEventVerify`
   passes (id recomputed from the fields AND the signature checked). The relay layer verifies
   by default and delivers failures as "invalid", never as events; turning that off is a
   per-relay, eyes-open act (`nxrSetVerify`). Message types compare byte-exact ("EVENT", not
   "event"): `is` folds case in this dialect, so every name comparison goes through the
   byte-exact helper.
3. **The canonical bytes are law.** `nxEventSerialize` is the id preimage: exactly seven
   escapes, other control bytes verbatim, UTF-8, no whitespace. Any change here is
   interop-visible and requires re-running `tools/nostr-kat.py`, re-pasting the harness
   constants, and an engine re-pass. Never "clean up" the serializer.
4. **Fail closed on every wire and parse error.** A bad checksum, a truncated TLV, a MAC
   mismatch, a hostile frame length, an unparseable relay message: refuse and (in the relay
   layer) tear the connection down. No silent fallbacks, no truncation.
5. **Own the lifecycle.** Every `nxrConnect` has an idempotent `nxrDisconnect`; `nxrShutdown`
   closes everything and is safe to call twice; there is no deterministic unload hook in OXT,
   so the app frees on `closeStack`. A stale handle or socket id is a clean no-op.
6. **Secret hygiene.** Secret keys cross this API as hex strings by design (the paste-format
   convention), which means: never log an nsec, never put one in an error message, and
   `nxUriEncode` REFUSES to wrap one. `nxKeyGenerate` refuses to run without SodiumXT
   randomness rather than degrading. The honest limit is documented: OXT script variables are
   not locked memory.

## Commands

**Static gate for the script layer** (the only automated safety net; OXT has no headless
compile):
```sh
python3 tools/check-livecodescript.py
```
The unified family checker, byte-identical across members (`tools/check-checker-drift.py` at
the suite root enforces that). A script change is only "done" once this passes.

**The vector spine** (what makes "verified statically" mean something here):
```sh
python3 tools/nostr-kat.py --check          # full published-vector sweep through the oracle
python3 tools/nostr-kat.py                  # print the constants the harness pins
python3 tools/check-selftest-vectors.py     # every harness constant re-derives BY NAME
python3 tools/check-docs-style.py           # member prose style (no dashes, no curly quotes)
python3 tools/check-doc-handlers.py --check # docs and source agree on the public surface
```
`tools/nostr_reference.py` is the independent oracle (own secp256k1, BIP-340, bech32, HKDF,
ChaCha20, NIP-44, canonical serializer); it anchors to the published BIP-340 / NIP-44 /
BIP-173 / NIP-19 vectors at import and REFUSES TO LOAD broken. Never hand-edit a harness
vector: edit the fixture in the KAT, re-run it, paste the constants block.

**There is no headless way to run `.livecodescript` on OXT**, so everything here is
**"verified statically; needs an OXT pass"**, and the relay paths add **"+ a live-relay
pass"**. Do not claim a handshake works until it has shaken hands with a real relay.

## Member gotchas (paid for elsewhere, carried here)

1. **`is` folds case.** Tag names, relay message types, base64 accept values, bech32
   round-trips: all compare through byte-exact helpers (`nxStrEqExact` in the core, `nxrStrEq`
   in the relay layer). A folded compare on "EVENT" vs "event" silently accepts a
   non-conforming relay.
2. **`itemDelimiter` / `lineDelimiter` are global mutable state.** Every chunk read in both
   files saves, sets, uses and restores. Internal list-shaped data flows as 1-based
   sequential ARRAYS (counted with the delimiter-free `is among the keys of` walk) exactly so
   most code never touches a delimiter at all.
3. **JSON in this dialect is byte work.** Braces are refused outside string literals by the
   family checker, so JSON is built by concatenating brace characters inside quoted literals
   and parsed by walking UTF-8 bytes. `f(x)["k"]` is refused too: every function result is
   put into a local before subscripting.
4. **The engine's number coercion is a canonical-form hazard.** "1e3" `is an integer` in this
   dialect, so `nxEventFromJson` requires created_at and kind to be PLAIN DIGIT runs before
   they may reach the serializer; anything else refuses.
5. **The socket lessons are OnionXT's, inherited whole** (see onionxt/CLAUDE.md): byte
   discipline on sockets, `with message` everywhere, short reads are normal, `open socket` is
   async and failure arrives as a `socketError` MESSAGE, watchdog every handshake, store the
   engine's socket id verbatim with a `|name` suffix. Plus the family rule this layer obeys
   and one library before it did not: act only on OWN socket ids in
   `socketError`/`socketClosed`/`socketTimeout` and `pass` the rest.
6. **The NIP-44 length policy is the vectors', not the newest spec text's.** The published
   vector set pins the u16 prefix only and marks 65536+ invalid; the newer spec sketches a
   6-byte extended prefix with no vectors. NostrXT refuses plaintext over 65535 bytes, fail
   closed, and says so. If upstream vectors for the extended form land, that is a deliberate
   change with new KAT rows, not a quiet edit.
7. **wss:// is written, labeled, and UNMEASURED.** `open secure socket` appears nowhere else
   in the suite and the root engine notes have no TLS entry. The first engine session that
   touches it must record what actually happens (verification behaviour, failure delivery,
   TLS versions) in `docs/OXT-ENGINE-NOTES.md` at the suite root, whatever the answer is.

## As-built notes (v0.1.0, 2026-08-23)

Everything below is the initial build; nothing has met an engine yet. Record engine results
here as they are learned (that is what this section is for).

- The full public surface: the core's nx* handlers and the relay layer's nxr* handlers, every
  one exercised by name in `examples/nostrxt-tests.livecodescript` (offline, deterministic,
  SKIP-counted for absent extensions and for the relay layer in the suite paste).
- The KAT sweeps the COMPLETE published sets headlessly: the BIP-340 csv (signing rows,
  verification rows, every negative), the official NIP-44 v2 vectors (conversation keys valid
  and invalid, message keys, padding pairs, encrypt/decrypt including the long-message sha256
  rows and the invalid payloads), the BIP-173 valid/invalid strings, and the published NIP-19
  examples. The RFC 6455 values are DERIVED (sha1 + base64 over the GUID anchored to the
  python-websockets reference implementation, because the RFC text hosts were unreachable from
  the build environment; the derived accept for the sample key matches the RFC's published
  example).
- The one deliberate scope cut: NIP-04. No AES exists anywhere in the suite, libsodium will
  never ship CBC, and NIP-04 is superseded by NIP-44; documented as a decision in docs/07.
- The one known gap: the NIP-44 cipher call, fail-closed behind the `sxChaCha20IetfXor` seam
  (docs/07). The harness self-upgrades: the moment a SodiumXT with that primitive is
  installed, the seam section stops expecting the capability error and starts KATing the
  official payload vector.
- Suite integration: the core embeds in the suite paste as a script layer; the harness folds
  under prefix nx1; the relay layer stays out of the paste (see "What this is"); the demo
  carries core + relay + harness between sync-demo-embeds sentinels.

## Git / workflow

- Develop on a per-task branch; commit there; open a draft PR if none exists.
- A `.livecodescript` change is "done" once `tools/check-livecodescript.py` passes, the KAT
  and vector gates are green, every carrier is regenerated (`python3
  tools/build-suite-selftest.py` and `python3 tools/sync-demo-embeds.py` at the suite root),
  and it has had, or is clearly flagged as needing, an on-engine pass.
- A change that needs a new CoinXT or SodiumXT primitive splits: the upstream feature lands
  first (with its own ABI bump and tests), then NostrXT composes it. `sxChaCha20IetfXor` is
  the standing example (docs/07).
- A change to the canonical serializer, the bech32 layer, or the NIP-44 construction is
  interop-visible: new KAT rows land in the SAME change, and the honesty label resets to
  "needs an OXT re-pass".
- **No em-dashes** in committed prose (enforced by `tools/check-docs-style.py`). Match the
  surrounding style: comment the *why*, densely.
