# Riptide Social

The suite's capstone app, being built: a serverless social application
composed entirely from the installed OpenXTalk suite extensions, per the
design in `../docs/RIPTIDE-SOCIAL-SPEC.md`. No server, no account, no
hosting bill: your identity is an ed25519 key you hold, following someone
is knowing their key, and reaching them is verifying them.

> **Documentation:** [`docs/README.md`](docs/README.md) indexes this app's pages, and points at the capstone specification, which lives at suite level in [`../docs/RIPTIDE-SOCIAL-SPEC.md`](../docs/RIPTIDE-SOCIAL-SPEC.md).

## Status: all 7 phases BUILT; phases 1-4 DONE on two machines

> **Honesty convention.** **Phases 1-2 ENGINE-PASSED 2026-08-12** (folded
> into the suite harness), their two-machine propagation criterion closed
> 2026-08-13. **Phases 3 and 4 closed on two machines 2026-08-15**: a
> follower fetched and PLAYED an attached video (which necessarily walked
> head publish -> fetch -> chain walk -> authorSig verify -> media
> info-hash -> swarm join -> playback), and two identities exchanged
> encrypted DMs, chat both ways, with no server (the sealed RSI1 intro,
> the deterministic-role crypto_kx session, and the pairwise secretstream
> over rp1 all carrying real traffic). The same day the whole phase 4-7
> COMPUTE surface ran green in the suite selftest on a real engine.
> **Phases 5-7 are BUILT and statically verified, their live passes
> pending**: the dc call with its spec-6.2 typing lane (phase 5), the
> LAN mesh with its mutual welcome AND its sync payload - drafts, feed
> seq, presence over the admitted mesh (phase 6, built 2026-08-15),
> plus the channel-2 decision settled 2026-08-16 (media handoff as a
> signed channel-0 pointer at the torrent rail; channel 2 reserved,
> dark) - and the anon persona over live Tor (phase 7).
> `docs/two-machine-runbook.md` scripts what remains.
>
> The flagship stack is `examples/riptide-social.livecodescript` (on the
> suite UI kit): FOUR cards - Feed (identity, publish, the verified chain
> walk, the media strip), Messages (DMs + the Call button), Devices (the
> LAN mesh), and Anon (the persona and the live guard panel). A post
> renders only after `rsIngestHead`/`rsIngestPost` verify it, so a
> received feed IS a verified walk. `examples/README.md` carries the run
> procedures; run records are the maintainer's dated accounts.

What ships today, per the spec's phased roadmap (section 10.3):

- **`src/riptide.livecodescript`**, a pure-script library:
  - the master seed and the `RIPTKEY1` sealed key file (Argon2id +
    secretbox, the family's `BTXPREF1` convention with riptide's magic)
  - the KDF subkey tree: one 32-byte master derives the identity, DM,
    LAN, and anonymous-persona subkeys (`sxKdfDerive`, context
    `"riptide\0"`)
  - identity to handle (64-hex ed25519 public key) to `.onion` address,
    both directions
  - the rendezvous derivations: `inboxId` and `roomId`
  - the `RSH1` feed-head and `RSP1` post-record wire formats: build,
    strict parse, and author-signature verification, with the
    tamper-evident post chain
  - **the media layer (phase 3)**: attach a file as a trackerless torrent
    seeded in place (`rsMediaCreate`), fetch-and-co-seed sequentially
    (`rsMediaFetch`), and the status snapshot a player paints from
  - **the DM layer (phase 4)**: crypto_kx prekeys as signed `RSK1`
    records, sealed `RSI1` intros bound to one recipient, `RSM1` rp1
    frames, deterministic-role sessions, and the inbox-swarm join +
    framed send; the message kinds `O`/`A` carry phase-5 SDP over the
    same encrypted rail
  - **the LAN mesh admission (phase 6)**: the shared-master keypair and
    the three-leg RSL1 challenge/response/WELCOME handshake (mutual auth
    - a stranger on your Wi-Fi cannot join, and a rogue host cannot fake
    being yours)
  - **the phase-6 sync records** (2026-08-15): the payload past admission,
    per spec section 7's channel discipline - draft sync (channel 0:
    absolute draft text with a monotonic per-device seq), feed-seq /
    read-receipt state (channel 0, applied as max so two devices never
    publish a conflicting head), and presence/typing (channel 1,
    unreliable-unsequenced, safely droppable absolute state). All signed
    under the shared LAN key with a distinct domain tag,
    verify-then-parse on every inbound record; authenticated, not
    encrypted (the LAN sees draft plaintext, said loudly in the UI)
  - **the phase-6 media handoff** (2026-08-16, the channel-2 decision):
    spec section 7's bulk media lane, settled as a fourth signed record
    kind on channel 0 - a small POINTER (info-hash + file name + size)
    at the phase-3 torrent path, because media essentially never fits
    enet's 60000-byte packet budget and bulk over that seam is a
    torrent in this suite. Channel 2 itself stays reserved, dark; the
    pointed-at bytes ride the ordinary torrent rail (swarm visibility
    and DHT discovery, recorded honestly)
  - **the anon persona (phase 7)**: onion-only identities
    (`rsAnonHandle`/`rsAnonOnion`), the sealed-DM prekey subkey
    (`rsAnonDmSeed`, spec 8.3), BTXO framing, and `rsPersonaAllows` - the
    section-9.3 deanonymization guard every transport branch routes
    through
  - **the 8.2/8.3 onion serving seams** (2026-08-15): `rsAnonFeedPage`
    (the persona's feed page as deterministic, golden-pinned HTML - a
    wire format, entries escaped), `rsAnonPrekeyBody` (the signed RSK1
    prekey record as hex text for the GET `/prekey` route), and
    `rsAnonAcceptDm` (the POST `/dm` body: strict-hex refusal BEFORE any
    decode, then the existing seal-open verify-then-parse under the
    persona's own subkeys). The demo registers the onion-httpd routes;
    the library stays pure
  - **the phase-2 live feed layer**: `rsPublishHead` signs the canonical
    BEP44 buffer with SodiumXT and stores it with `btDhtPutSigned` (the
    identity secret never enters libtorrent, and libtorrent re-verifies
    the signature before queueing); `rsPublishPost` / `rsPublishImmutable`
    store content-addressed items whose returned target is recomputed and
    compared; `rsRequestHead` / `rsRequestImmutable` issue the async
    lookups; and `rsIngestHead` / `rsIngestPost` verify each drained
    `dhtMutableItem` / `dhtImmutableItem` event (BEP44 signature under
    the followed handle, content address, author signature) before the
    app believes a byte of it. The library never starts, stops, or polls
    a session - the app owns the one session per process.
- **`tests/riptide-selftest.livecodescript`**, the harness: call
  `rsSelfTest()` on an engine with the extensions installed. It is also
  folded into the suite-wide paste (`tests/suite-selftest.livecodescript`
  at the repository root) along with the library itself, so one paste
  exercises riptide with the rest of the suite. No network is awaited:
  the live-feed section drives real puts and lookups against a local
  session (skipping honestly without torrentxt); everything else is
  fully offline.
- **`tests/riptide_golden_test.py`** and **`tools/riptide_reference.py`**:
  the pure-Python oracle and the golden test that pins every vector.
  The oracle anchors to vectors from OUTSIDE this directory: the sodiumxt
  C KATs, torrentxt's cross-project BEP44 conformance vector, and a real
  published v3 onion address.
- **`tools/check-selftest-vectors.py`**: re-derives every golden constant
  in the harness from the oracle, with an honest coverage count.

Run the offline gates from this directory:

```sh
python3 tools/check-livecodescript.py       # the static script gate
python3 tests/riptide_golden_test.py        # the byte-for-byte goldens
python3 tools/check-selftest-vectors.py     # harness constants vs oracle
```

All three also run in `tools/build-all.sh --gates` at the repository root.

## Extension dependencies

Riptide probes, never assumes (`rsProbeCapabilities()`); a missing
extension disables exactly its feature, with a clear message, and never
another one.

| Extension | Need | Role today (phases 1-7) |
|---|---|---|
| SodiumXT | required | the trust root: KDF, sealing, signing, hashing, crypto_kx, secretstream; at ABI 7 also the preferred SHA3 provider |
| coinxt | optional | `cxSha3_256` is the fallback SHA3 provider for the offline `.onion` self-computation |
| onionxt | optional | offline onion verification, and the anon persona's service (`rsAnonCreateService` via `oxCreateServiceFromSeed`) |
| torrentxt | optional | the live feed (BEP44 puts/lookups), media torrents, and the DM inbox swarms + rp1 transport; every live handler refuses cleanly without it |
| enetxt | optional | the phase-6 LAN device mesh (the admission handshake rides enet channel 0) |
| datachannelxt | optional | the phase-5 call (a direct data channel, signalled over the DM rail) |

A note on the onion address, because it is the one place the composition
was subtle: libsodium has no SHA-3, so onionxt's `oxAddressFromPublicKey`
spent its first months as a registered known-missing gap
(`onionxt/docs/08`, gap 2), and riptide originally closed it by composing
coinxt's `cxSha3_256`. Building riptide phase 1 made offline address
emission a real need, and that is what got `sxSha3_256` shipped in
SodiumXT ABI 7 (2026-08-11) - the gap is now closed upstream, onionxt's
own address functions work, and `rsOnionFromPublicKey` prefers
`sxSha3_256` with `cxSha3_256` kept as the fallback. Without either
provider it still degrades to a clear error (the address remains
available from `oxServiceAddress` after publishing, via tor itself). The
security-relevant VERIFY direction, `rsVerifyOnionClaim`, needs no SHA-3
at all and works with onionxt alone.

## What remains

The live passes, scripted in `docs/two-machine-runbook.md`: the phase-5
call (watch for the CONNECTED/via line, ideally `typ srflx` across two
networks, and the spec-6.2 typing lane built 2026-08-15), the phase-6
mesh (mutual admitted verdicts on both sides, then the full
done-criterion: a draft typed on one device appearing on the other with
a stranger refused - the sync payload is BUILT as of 2026-08-15,
verified statically), phase 7 over a live tor daemon - which now includes
spec 8.3's onion transport (the feed page, `/prekey`, and the POST `/dm`
sealed-intro drop are BUILT as of 2026-08-15, library seams plus the
demo's onion-httpd wiring, verified statically; the live-Tor pass is
what remains) - and phase 3's mid-download nuance (playback visibly
below 100%). One piece of the anon rail is deliberately unbuilt: the
persona's REPLY over an onion stream (answering an accepted intro means
a public-side DM to the proven sender). Labels flip only on a dated
engine report, per the honesty convention.
