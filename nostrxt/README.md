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
3. **NIP-44 v2 encrypted payloads** - the COMPLETE construction: conversation
   key, message keys, padding, MAC, and (since 2026-08-23) the raw ChaCha20
   cipher itself, composed from SodiumXT ABI 10's `sxChaCha20IetfXor`. On an
   installed SodiumXT older than ABI 10, encrypt/decrypt fail closed with a
   clear capability error (`docs/07-capabilities-required.md`).
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
      |                                        |  wss:// `open secure socket`
      |  composes (probed, never assumed)      |    (live-run 2026-08-24; cert
      |                                        |    checks unmeasured)
      |                                        |  ws:// `open socket` (never run)
      v                                        v
   CoinXT (cx*, ABI >= 6, HARD):            Nostr relays (dumb websocket
     cxSha256, cxSchnorrSign/Verify,        stores; the app picks them,
     cxXOnlyPubkey, cxEcdh,                 the user can change them)
     cxHmacSha256, cxSeckeyIsValid
   SodiumXT (sx*, soft):
     sxRandomBytes, sxMemEqual,
     sxChaCha20IetfXor (ABI 10)
```

## Why this matters

Most platforms own three things the user should: the identity (an account
the platform can close), the address book, and the archive. Nostr inverts
all three: identity is a keypair the user holds, every event is signed with
it and self-verifying anywhere, and relays are interchangeable dumb stores -
if one bans you or dies, you publish the same signed events to another. For
the xTalk family the hard cryptography already exists (CoinXT's BIP-340 is
exactly Nostr's signature scheme), so the whole protocol layer is readable
script over proven native ground.

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
  HMAC are CoinXT calls; randomness, constant-time compare and the NIP-44
  cipher are SodiumXT calls. What NostrXT owns in pure script is exactly the
  checksummed byte shuffling family law allows there: JSON bytes, bech32 bit
  packing, the NIP-44 key schedule and padding, websocket framing math.

## Documentation

The `docs/` series is numbered and readable in order. **If you just want to
use NostrXT, jump to [`docs/09-usage-guide.md`](docs/09-usage-guide.md).**
The numbers are stable citations (the shipped capability error names
`docs/07-capabilities-required.md`; other files cite "docs/05 VERIFY item 9"
and "docs/07 gap #2"), so the retired 01 and 08 leave gaps rather than a
renumbering: 01's protocol and trust model now lives in 00, and 08's open
questions live in 07 as limits and unknowns.

| Document | What it is |
|---|---|
| [00-overview.md](docs/00-overview.md) | What Nostr is, the trust model (what a relay can and cannot do to you), the two-file architecture and what composes what. |
| [02-nip01-events.md](docs/02-nip01-events.md) | NIP-01 events byte for byte: the one wire format where close enough produces a wrong answer that looks right. |
| [03-nip19-entities.md](docs/03-nip19-entities.md) | NIP-19 bech32 entities, the one deliberate BIP-173 deviation, and nsec handling. |
| [04-nip44-payloads.md](docs/04-nip44-payloads.md) | The NIP-44 v2 construction step by step, its documented limits, and the NIP-04 decision. |
| [05-relay-client.md](docs/05-relay-client.md) | The `nxr*` websocket relay client: state machine, callback contract, NIP-42, the socket pass-through rule, and the engine VERIFY list. |
| [06-api-reference.md](docs/06-api-reference.md) | Every public handler of both source files; `tools/check-doc-handlers.py` holds it and the source in agreement. |
| [07-capabilities-required.md](docs/07-capabilities-required.md) | What this member needs from upstream and the engine: the closed cipher gap, the half-measured TLS question, the remaining unknowns, scope limits and decisions. |
| [09-usage-guide.md](docs/09-usage-guide.md) | From zero to a signed event on a relay: task-oriented recipes. The page most readers want. |

## Layout

```
nostrxt/     (the NostrXT member of the xtalk-suite monorepo)
  README.md  CLAUDE.md (maintainer memory: rules, gotchas, the dated evidence ledger)
  LICENSE    MIT; NostrXT bundles no third-party code
  docs/      the numbered series (table above)
  src/       nostrxt.livecodescript (the nx* core), nostr-relay.livecodescript (the nxr* client)
  examples/  nostrxt-tests (the offline self-test) and nostrxt-demo (paste-and-run; carries the
             core, the relay layer and the harness, so nothing needs `start using` first)
  tools/     run-gates.sh (the gate list), nostr_reference.py (the oracle), nostr-kat.py, the
             vector / execution / doc gates below, the family's carried interpreter and checkers
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
   put nxProbeCapabilities() into tCaps; put tCaps["canSign"]
   ```

   The first answers `NostrXT 0.1.0`; the second tells you whether CoinXT
   round-tripped (a function result cannot be subscripted directly, so it
   goes into a variable first). The member self-test
   (`examples/nostrxt-tests.livecodescript`, entry point `nxSelfTest()`)
   prints the full report with per-check PASS / FAIL / SKIP lines.

`docs/09-usage-guide.md` walks the first signed event and the first relay
subscription end to end.

## Gates and status

**The nx* core is ENGINE-PROVEN 2026-08-24** (Windows x86_64, OXT 9.6.3:
274 passed, 0 failed, 2 deliberate skips in the suite paste - both skips are
the relay layer, which is not in the paste by design), the complete NIP-44
path through the real SodiumXT ABI 10 cipher included. **The relay layer's
connect / handshake / publish / confirm path is LIVE-PROVEN 2026-08-24**: the
demo's boot self-check ran 9/9 green, then it opened a real TLS websocket to
wss://nos.lol, signed a kind-1 note, published it and received the relay's
ok-true for its id. Still "verified statically; needs a live-relay pass": the
REQ/subscribe receive leg, the NIP-42 auth exchange, and every ws:// path
(the proven run was secure). That run met an ordinary public host, so
whether the engine refuses a bad certificate is unmeasured in both
directions (the suite's `docs/OXT-ENGINE-NOTES.md` 6.8). The source carries a
`VERIFY (on-engine)` label wherever an engine behaviour is assumed.

What IS machine-verified, headlessly, on every build (`bash tools/run-gates.sh`):

- `tools/nostr-kat.py --check` sweeps the **full published vector sets**
  (the BIP-340 `test-vectors.csv` with every negative row, the official
  NIP-44 v2 set, the BIP-173 strings, the NIP-19 examples; every source URL
  named) through `tools/nostr_reference.py`, an independent implementation
  that anchors itself at import and refuses to load broken. One deviation is
  asserted AS a deviation: the over-90 BIP-173 vector decodes here on
  purpose, because NIP-19 waives that cap for TLV entities (NostrXT enforces
  NIP-19's 5000-character SHOULD instead).
- `tools/check-selftest-vectors.py` re-derives **every pinned constant in
  the harness by name**, both directions (the gate prints the count), so a
  transcription slip cannot produce a harness that agrees with itself.
- `tools/check-script-vectors.py` EXECUTES the shipped core through the
  family's headless interpreter against the same vectors, over the committed
  CoinXT and SodiumXT binaries, and `tools/test-script-vectors.py` proves it
  fails on seeded defects. That settles logic, not engine parsing, so it
  upgrades no label.
- `tools/check-livecodescript.py` (the family's unified static gate),
  `tools/check-docs-style.py` and `tools/check-doc-handlers.py` hold the
  script, prose and API-reference rules.

## Troubleshooting

The failure modes a first setup actually hits. Every `nx*` function fails
by returning empty (or false) with the reason in `nxLastError()`; every
`nxr*` command reports through `the result` - read those first.

### Ids, signing or verification return empty; `nxLastError()` says "needs CoinXT ..."

CoinXT (ABI >= 6) is not loaded into the message path, and NostrXT fails
closed per feature without it. Install the CoinXT extension and re-open the
stack (the capability probe is cached; `nxNip44HasCipher()` is the one live
re-probe).

### `nxNip44Encrypt` / `nxNip44Decrypt` return empty naming `sxChaCha20IetfXor`

The installed SodiumXT predates ABI 10 (2026-08-23), where
`sxChaCha20IetfXor` shipped. Upgrade it, then re-open the stack or call
`nxNip44HasCipher()` (the `nxProbeCapabilities` row is cached per session).
Everything up to the cipher seam still works and is vector-pinned.

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

The wss:// form works (the 2026-08-24 live run used it), so a failure here
is about your relay, network or certificate situation. Still unmeasured,
and worth recording in the suite's `docs/OXT-ENGINE-NOTES.md` 6.8 if you hit
them: what the engine does with an INVALID certificate (do not assume it
refuses one), and how a TLS failure is delivered. The ws:// form has no live
run behind it, so it is not a cleaner fallback.

### A dial hangs with no error callback at all

If your app defines `socketError`, `socketClosed` or `socketTimeout`, it
must `pass` the ones that are not its own (or call `nxrSocketError` and
friends, which answer whether the socket was the relay layer's). Those three
names are the engine's, shared by every socket user in the process; an app
that swallows them starves every other socket library silently - the
symptom is a hang, not an error (`docs/05-relay-client.md`).

## House style

ASCII only in `.livecodescript`. No em-dashes anywhere, docs included
(hyphens, commas, colons, parentheses). Comment the *why*, densely. These
are enforced by `tools/check-livecodescript.py` and `tools/check-docs-style.py`,
and they are not optional: curly quotes fail OXT compilation outright.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

NostrXT is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`nostrxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/NostrXT: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `nostrxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port nostrxt --ref pull/<n>/head`, keeping its
author - but a commit made here directly holds up the next publish until
it has been ported, because publishing never overwrites work it did not
write. The suite's `docs/MEMBER-REPO-SPLIT.md` is the whole workflow.

**Suite-level paths cited from here.** This member's `CLAUDE.md` and
`docs/` cite files that live at the suite root, not in this tree:
`docs/OXT-ENGINE-NOTES.md` (engine behaviour, the authoritative list),
`docs/OXT-PASS-RUNBOOK.md`, `tools/build-all.sh`,
`tests/suite-selftest.livecodescript` and the suite-level `docs/`
index. Read them at `https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/<path>`. A path of the
form `../<member>/...` names a sibling member of the suite; each has its
own repository, listed in `tools/member-registry.py` there.

**Sibling members this member's gates need beside it.** `bash
tools/run-gates.sh` (this member's own gate list, the one CI runs)
reaches into these siblings, found as `../<name>` beside this checkout:

- `../coinxt` from https://github.com/SethMorrowSoftware/CoinXT - the committed x86_64-linux binary, which tier 2 of `tools/check-script-vectors.py` executes the composed paths against.
- `../sodiumxt` from https://github.com/SethMorrowSoftware/SodiumXT - the committed x86_64-linux binary, for the NIP-44 cipher seam in the same tier.

Clone them beside this checkout under exactly those directory names
(and keep this checkout named `nostrxt`), or point `XTALK_SIBLINGS` at a
directory holding them (`XTALK_SIBLING_<NAME>` for one). The generated
`.github/workflows/gates.yml` takes them from the suite itself, at the
commit named by this repository's newest `Suite-Commit:` trailer - the
versions the suite's gates ran with this tree - and sets
`XTALK_REQUIRE_SIBLINGS=1` so a missing sibling fails the job rather
than skipping its tier. Nothing the SHIPPED code needs is beside it: a
demo that uses a sibling's library carries its own copy (below).

**Carried copies inside this member, and where their masters are.**
Every runnable stack here is one paste-and-run file, so it carries what
it needs verbatim between marker lines. The masters, and the drift gates
that hold every copy byte-identical to them, live in the suite and do
not travel with this member; refresh a copy from the suite (the marker
lines name the master) rather than editing inside the markers.

- The demo UI kit (`tools/ui-kit.livecodescript`; gate `tools/check-ui-kit-drift.py`) in `examples/nostrxt-demo.livecodescript`.
- The boot self-check block (`tools/demo-selfcheck.livecodescript`; gate `tools/check-demo-selfcheck-drift.py`) in `examples/nostrxt-demo.livecodescript`.
- This member's own library, embedded into its own stacks by the same tool so each is one file to paste: `examples/nostrxt-demo.livecodescript` carries `src/nostrxt.livecodescript`; `examples/nostrxt-demo.livecodescript` carries `src/nostr-relay.livecodescript`; `examples/nostrxt-demo.livecodescript` carries `examples/nostrxt-tests.livecodescript`.
- `tools/check-docs-style.py`, `tools/check-livecodescript.py`, `tools/lcs-interp.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

**What other members carry from this one.** The suite embeds this
member's script into the stacks below, verbatim; a change to it
reaches them when the suite re-runs `tools/sync-demo-embeds.py`, and
is not done until every carrier has been re-run on an engine:

- `riptide/examples/riptide-social.livecodescript` in riptide carries `src/nostrxt.livecodescript`.
- `riptide/examples/riptide-social.livecodescript` in riptide carries `src/nostr-relay.livecodescript`.

**What this repository cannot check on its own.** The suite-wide gates -
cross-library name disjointness (`tools/check-cross-library-names.py`),
the carried-copy drift gates above, embed freshness, the cross-member
handler-call and typed-boundary checks (`tools/check-handler-calls.py`,
`tools/check-lcb-call-types.py`), the timer-pin closure, and the suite
paste's coverage ratchet (`tools/check-suite-coverage.py`) - run only in
the suite. `tools/run-gates.sh` here is this member's own list, and the
suite's `tools/build-all.sh` runs that same script, so the two cannot
disagree about what this member's gates are.

<!-- ==== SUITE RELATIONSHIP END ==== -->
