# Riptide Social

The suite's capstone app, being built: a serverless social application
composed entirely from the installed OpenXTalk suite extensions, per the
design in `../docs/RIPTIDE-SOCIAL-SPEC.md`. No server, no account, no
hosting bill: your identity is an ed25519 key you hold, following someone
is knowing their key, and reaching them is verifying them.

## Status: phase 2 (of 7) in the tree; phase 1 engine-passed

> **Honesty convention.** **Phase 1 is ENGINE-PASSED as of 2026-08-12**
> (Windows x64, folded into the suite harness): 89/89, 0 skipped, every
> extension probe true including hasSha3. The **phase-2 live feed layer**
> (head publish through the external-signing seam, content-addressed post
> publish, the async lookups, and the ingest verifiers) is verified
> statically and against the pure-Python oracle; it **needs an OXT
> pass**, and phase 2's done-criterion - a SECOND machine walks the chain
> and verifies every authorSig - additionally needs two machines on a
> real DHT. rp1 DMs and onion streams are later phases; no claim is made
> about them at all.

What ships today, per the spec's phased roadmap (section 10.3, phases 1
and 2):

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

| Extension | Need | Role today (phases 1-2) |
|---|---|---|
| SodiumXT | required | the trust root: KDF, sealing, signing, hashing; at ABI 7 also the preferred SHA3 provider |
| coinxt | optional | `cxSha3_256` is the fallback SHA3 provider for the offline `.onion` self-computation |
| onionxt | optional | `oxPublicKeyFromAddress` verifies a claimed onion offline |
| torrentxt | optional | the phase-2 live feed layer: BEP44 puts and lookups through a session the app owns; every live handler refuses cleanly without it |
| enetxt, datachannelxt | later phases | probed and reported only |

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

## What phase 3+ adds (not yet written)

In spec order: media torrents (create, seed, co-seed, sequential
playback), then DMs (the inbox rendezvous swarm, sealed intros, pairwise
secretstream over rp1), live dataChannel sessions, LAN device sync, and
the anonymous persona. Each phase lands with its own engine pass before
its labels flip - phase 2's own pass (and its two-machine propagation
half) is still open, per the status note above.
