# Riptide Social

The suite's capstone app: a serverless social application composed entirely from the
installed OpenXTalk suite extensions, per the design in the suite's
[`docs/RIPTIDE-SOCIAL-SPEC.md`](https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/RIPTIDE-SOCIAL-SPEC.md).
No server, no account, no hosting bill: your identity is an ed25519 key you hold,
following someone is knowing their key, and reaching them is verifying them.

## Status

All eight spec phases are built with their UI, and phases 1-4 are done on two machines.
Anything not listed as done is "verified statically; needs an OXT pass" (plus a live-Tor
pass for the anon persona and a live-relay pass for Nostr).

- **Phases 1-2** (identity, the live feed): engine-passed 2026-08-12 in the suite paste
  (133/133); two-machine propagation closed 2026-08-13.
- **Phases 3-4** (media, DMs): done on two machines 2026-08-15 - a follower fetched and
  PLAYED an attached video, and two identities exchanged encrypted DMs both ways with no
  server.
- **Phases 4-7, compute**: green in the suite paste on an engine 2026-08-15, 2026-08-20
  (riptide 338/0/2) and 2026-08-24 (391/391, including the kind-C rail and the BTXO
  receive path; phase 6's admission and welcome bytes re-pinned 2026-09-09 since).
  Phase 5 (the call) is built and never run; the live legs of phases 6-7 (the LAN
  mesh, the anon persona over Tor) are owed.
- **Phase 8** (the Nostr bridge, built 2026-08-29): the library is executed headlessly
  against the real committed CoinXT by `tools/check-script-vectors.py`, which settles
  logic, not parser behaviour. The card's boot was reported working on an engine
  2026-08-29, and the v11 UI boot read 9 passed / 1 failed, the one FAIL a since-fixed
  defect in the carried self-check. Needs an OXT + live-relay pass.

A post renders only after `rsIngestHead`/`rsIngestPost` verify it, so a received feed IS
a verified walk. `CLAUDE.md` holds the dated evidence ledger.

## What ships

- **`examples/riptide-social.livecodescript`**, the app, on the suite UI kit: FIVE
  cards - Feed (identity, publish, the verified chain walk, the media strip), Messages
  (DMs + the Call button), Devices (the LAN mesh), Anon (the persona and the live guard
  panel), and Nostr (the phase-8 bridge). `tools/check-demo-boot.py` boots it
  headlessly; `examples/README.md` is its run guide.
- **`src/riptide.livecodescript`**, the pure-script `rs*` library, one line per rail:
  - identity: the master seed and the `RIPTKEY1` sealed key file (Argon2id + secretbox);
    the KDF subkey tree (`sxKdfDerive`, context `"riptide\0"`); handle (a 64-hex ed25519
    public key) <-> `.onion` both ways; the rendezvous ids `inboxId` and `roomId`;
  - the feed: `RSH1` heads and `RSP1` posts with the tamper-evident chain, the kind-C
    chunked rail for long posts, and the live BEP44 layer (publish, lookup,
    verify-on-ingest; the library never owns the session);
  - media: a trackerless torrent seeded in place, a sequential fetch, a piece-deadline
    plan;
  - DMs: `RSK1` prekeys, `RSI1` sealed intros, `RSM1` rp1 frames, secretstream; the
    `O`/`A` kinds carry phase-5 SDP;
  - the LAN mesh: the `RSL1` three-leg admission (challenge, response, welcome), sync
    records D/F/P and the media-handoff pointer M - authenticated, not encrypted;
  - the anon persona: onion-only identities, `rsAnonDmSeed`, BTXO with the
    `rsBtxoStreamStep` receiver, `rsPersonaAllows` (the guard every transport branch
    routes through), and the 8.2/8.3 onion serving seams;
  - Nostr: the `RSN1` identity bridge and the sealed `RIPTAPP1` app-state store.
- **`tests/riptide-selftest.livecodescript`**, the harness: call `rsSelfTest()` on an
  engine with the extensions installed; it is also folded into the suite paste with the
  library. No network is awaited: the live-feed section drives a local session (skipping
  honestly without torrentxt), and everything else is offline.
- **`tools/riptide_reference.py`**, the oracle, anchored to vectors from OUTSIDE this
  directory (the sodiumxt C KATs, torrentxt's cross-project BEP44 conformance vector, a
  real published v3 onion); `tests/riptide_golden_test.py` pins it and
  `tools/check-selftest-vectors.py` re-derives every golden constant in the harness
  from it; the others are inputs, each listed with a reason, and the gate prints the
  split.

## Gates

Run from this directory:

```sh
bash tools/run-gates.sh                     # the full list: what CI runs
python3 tools/check-livecodescript.py       # the static script gate
python3 tools/check-docs-style.py           # the house prose gate
python3 tests/riptide_golden_test.py        # the byte-for-byte goldens
python3 tools/check-selftest-vectors.py     # harness constants vs oracle
```

`run-gates.sh` also runs the execution gates (`check-script-vectors.py`, then
`test-demo-boot.py` and `check-demo-boot.py`) and `export-protocol-vectors.py --check`.
The prose gate is the one an edit to these pages trips: every `.md` and
`.livecodescript` here uses plain hyphens and straight quotes only.

## Extension dependencies

Riptide probes, never assumes (`rsProbeCapabilities()`): a missing extension disables
exactly its feature, with a clear message, and never another one.

| Extension | Need | Role (phases 1-8) |
|---|---|---|
| SodiumXT | required | the trust root: KDF, sealing, signing, hashing, crypto_kx, secretstream; at ABI 7 also the preferred SHA3 provider. Also seals the `RIPTAPP1` app-state store |
| coinxt | optional | two unrelated jobs: `cxSha3_256` is the fallback SHA3 provider for the offline `.onion` self-computation, and secp256k1 + BIP-340 + SHA-256 are what the phase-8 Nostr rail signs with. Without it the Nostr card disables itself with an install line and nothing else changes |
| nostrxt | optional | the phase-8 rail's protocol layer: canonical NIP-01 events, NIP-19 entities, filters, and (in the app, not the library) the relay websocket client. The app carries both files, so no `start using` step |
| onionxt | optional | offline onion verification, and the anon persona's service (`rsAnonCreateService` via `oxCreateServiceFromSeed`) |
| torrentxt | optional | the live feed (BEP44 puts/lookups), media torrents, and the DM inbox swarms + rp1 transport; every live handler refuses cleanly without it |
| enetxt | optional | the phase-6 LAN device mesh (the admission handshake rides enet channel 0) |
| datachannelxt | optional | the phase-5 call (a direct data channel, signalled over the DM rail) |

The onion address: `rsOnionFromPublicKey` prefers `sxSha3_256` (SodiumXT ABI 7,
2026-08-11) with `cxSha3_256` as the fallback. Without either it degrades to a clear
error, and the address is still available from `oxServiceAddress` after publishing. The
security-relevant verify direction, `rsVerifyOnionClaim`, needs no SHA-3 and works with
onionxt alone.

## What remains

The live passes, scripted in `docs/two-machine-runbook.md`: phase 5 (the call and its
typing lane, ideally `typ srflx` across two networks), phase 6 (the mesh through the
draft-appears criterion, plus the third-device step), phase 7 over a live tor daemon
(including the 8.2/8.3 serving), and phase 8 against a real relay. Also owed: the
phase-4 DM clean close (2026-08-17, never run), the phase-3 faststart re-run
(mid-download playback was measured negative 2026-08-27 and fixed the same day), and
the phase-8 boot re-paste, which should read 10 passed / 0 failed. The persona's onion
REPLY rail is deliberately unbuilt: answering an accepted intro means a public-side DM
to the proven sender. Labels flip only on a dated engine report; the suite's
`docs/WORK-PLAN.md` tracks the open items.

## Documentation

| Document | What it is |
|---|---|
| [docs/api-reference.md](docs/api-reference.md) | the public `rs*` surface of the library: 106 handlers at 0.12.0, phases 1-8 |
| [docs/two-machine-runbook.md](docs/two-machine-runbook.md) | how to drive the app on real OXT machines, phase by phase, with the log lines each step expects |
| [docs/protocol-vectors.json](docs/protocol-vectors.json) | GENERATED: the Riptide Protocol conformance bundle, 67 golden vectors (one fixed identity, every wire record, derivation and target) plus 31 refusal vectors, for implementations in any language. Its prose half is the suite's [`docs/RIPTIDE-PROTOCOL.md`](https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/RIPTIDE-PROTOCOL.md). Regenerate with `python3 tools/export-protocol-vectors.py`, whose `--check` re-executes the bundle in the gate set; never edit it by hand |
| [examples/README.md](examples/README.md) | the run guide for the app stack |
| [CLAUDE.md](CLAUDE.md) | maintainer memory: the rules, the decisions, the traps, the evidence ledger |
| [RIPTIDE-SOCIAL-SPEC.md](https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/RIPTIDE-SOCIAL-SPEC.md) | the capstone design, at suite level: the identity seed, the signed BEP44 feed with co-seeded torrent media, the rp1 and secretstream DMs, WebRTC live sessions, enet LAN device sync, the onion-only persona, and the Nostr rail |

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

Riptide Social is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`riptide/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/RipTide: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `riptide/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port riptide --ref pull/<n>/head`, keeping its
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

- `../nostrxt` from https://github.com/SethMorrowSoftware/NostrXT - `tools/lcs-interp.py` (the family interpreter, loaded rather than copied), the nostrxt library the bridge is written over, and the `nostr_reference.py` oracle.
- `../coinxt` from https://github.com/SethMorrowSoftware/CoinXT - the committed x86_64-linux binary, for the signing paths.

Clone them beside this checkout under exactly those directory names
(and keep this checkout named `riptide`), or point `XTALK_SIBLINGS` at a
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

- The demo UI kit (`tools/ui-kit.livecodescript`; gate `tools/check-ui-kit-drift.py`) in `examples/riptide-social.livecodescript`.
- The boot self-check block (`tools/demo-selfcheck.livecodescript`; gate `tools/check-demo-selfcheck-drift.py`) in `examples/riptide-social.livecodescript`.
- Sibling libraries embedded by the suite's `tools/sync-demo-embeds.py` (the copy is the shipped file; the master is the sibling's `src/`):
  - `examples/riptide-social.livecodescript` carries `nostrxt/src/nostrxt.livecodescript` from https://github.com/SethMorrowSoftware/NostrXT.
  - `examples/riptide-social.livecodescript` carries `nostrxt/src/nostr-relay.livecodescript` from https://github.com/SethMorrowSoftware/NostrXT.
  - `examples/riptide-social.livecodescript` carries `onionxt/src/onionxt.livecodescript` from https://github.com/SethMorrowSoftware/OnionXT.
  - `examples/riptide-social.livecodescript` carries `onionxt/src/onion-httpd.livecodescript` from https://github.com/SethMorrowSoftware/OnionXT.
- This member's own library, embedded into its own stacks by the same tool so each is one file to paste: `examples/riptide-social.livecodescript` carries `src/riptide.livecodescript`.
- `tools/check-docs-style.py`, `tools/check-livecodescript.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

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
