# holde-em

**Serverless online no-limit Texas Hold'em for OpenXTalk (OXT) and the xTalk family**
(also LiveCode 9.6.3+). No accounts, no server: players meet over the BitTorrent DHT,
every action lives in a signed, hash-chained transcript, and the deal runs on a
security ladder that tops out at a **ristretto255 mental-poker shuffle**, where nobody,
not even the table host, can see a card they are not entitled to, and every completed
hand is verifiable after the fact.

> **The residual risk (spec 2):** at Level 2 the deal is fair and the ledger is honest
> even against a cheating majority at the wire level, but *nothing* here stops two
> humans exchanging screenshots. Real value makes that threat profitable. Read
> [holdem-spec.md](holdem-spec.md) section 13 before attaching value.

| Extension | Provides |
|---|---|
| [TorrentXT](https://github.com/SethMorrowSoftware/TorrentXT) | rp1 peer messaging and DHT rendezvous (the table code IS the invite) |
| [SodiumXT](https://github.com/SethMorrowSoftware/SodiumXT) | identities, sealing, commitments, randomness, and the ristretto255 surface (ABI 8, plus ABI 9 for DLEQ and the batch step) |
| [OnionXT](https://github.com/SethMorrowSoftware/OnionXT) | optional onion tables and onion-hosted deck oracles; CARRIED inside the stack, so only a local tor daemon is needed |
| [Box2Dxt](https://github.com/SethMorrowSoftware/Box2Dxt) Kit | optional spritesheet card art |

## Running it

The whole game is one paste-and-run stack that builds its own UI; hotseat play needs
no extensions at all.

1. **Install [OpenXTalk](https://openxtalk.org) (OXT).**
2. **Paste the stack.** `File > New Mainstack`, then `Object > Stack Script`; paste all
   of [`src/holdem.livecodescript`](src/holdem.livecodescript) and apply.
3. **Close the stack window and reopen it.** Reopening builds the table (1024x640) and
   opens on the lobby. Press **Leave (play hotseat)** for a local game. Close the window
   when done: that stops the session and cancels this stack's timers.
4. **For online play**, install **TorrentXT** (`org.openxtalk.library.torrent`) and
   **SodiumXT** (`org.openxtalk.library.sodium`) via `Tools > Extension Manager`.
   Optional: the **Box2Dxt Kit** (the `box2dxt-kit` stack in use) for card art, and a
   locally running **tor** daemon (SOCKS 9050, control 9051) for onion tables. Every
   dependency is probed at its point of use and fails closed with a readable reason.
5. **The self-test rides in the same stack:** `heRunSelftest` in the message box for
   the report panel, or `heSelfTest()` for the same report as a value.

## What it does

- **Hotseat, 2-6 seats.** Settings: opening chips, SB/BB, ante, seats, the blind
  schedule (fixed, every N hands, or every M minutes) and deal speed. Hands play at a
  dealing pace (`kHeStreetRevealMs`, `kHeRunoutStepMs`, `kHeShowdownHoldMs`,
  `kHeNextHandDelayMs`). With SodiumXT present, hands deal from the **Level 0 committed
  keyed-stream shuffle** (spec 7.1), falling back to a labelled practice PRNG. In
  hotseat one node holds every seed, so the deal is tamper-evident, not unstackable;
  online tables use per-player seeds committed before any reveal.
- **History** shows every hand, folded from the transcript and re-verified with two
  audits (the settlement, and the deal for Level 0), online chains included; **Copy
  transcript** exports the raw record.
- **Online lobby** (TorrentXT + SodiumXT): Create or Join; signed admission; sealed
  hole delivery; verified settles and co-signed receipts; street checkpoints;
  show/muck; host election when the host goes silent.
- **Liveness:** act timer with a per-hand time-bank, sit-out/return, late-join seating,
  and a parked table that waits for players instead of ending.
- **Onion tables** with a deterministic address (the invite survives a host restart)
  and bounded auto-redial on stream loss.
- **"Host: ORACLE"** (Level 1): the same stack deals as a non-playing oracle.
- **Level 2** (spec 7.3-7.4): the ristretto255 mask/unmask machine with void-and-audit,
  five scripted cheater bots (spec 12.4), Chaum-Pedersen DLEQ proofs, and a batched
  mask step (4 FFI crossings per step on ABI 9).

The math is backed by `tools/logic-fuzz.py`, which checks the logic against
*independently written* references: the evaluator exhaustively over all 2,598,960
five-card hands (exactly 7462 classes), and side pots and whole games (chip
conservation, no negative stacks, termination) over ~90k fuzzed configs, including the
dead-button rule.

## Status

**v0.25.3 (harness 45).** The folded harness is engine-green: latest **667/0** at
v0.25.2/h43 on 2026-08-27 (in the suite paste; platform not recorded), the same evening
as the first two-machine 2d contact. [CLAUDE.md](CLAUDE.md) carries the full evidence
ledger.
Anything visual, timed or multi-machine is "verified statically; needs an OXT pass"
until a person confirms it. **Honestly: no played hand deals on Level 2 yet.** The
wiring and the 4f deal-time check are open, and the Phase 5 hostile review and soak are
human work.

| Phase (milestone) | Built | Engine evidence | Exit still owed |
|---|---|---|---|
| 1 hotseat (M0) | evaluator, betting and side pots, deal, table UI (flat and Kit modes), harness; 1d animations unbuilt | harness green folded; three heads-up hotseat hands, 2026-08-17 | a 6-seat session (blinds to settlement, several hands, side pots, all 17 cards on screen) plus the 720p eye |
| 2 online (M1) | 2a identity (BEP44 profiles not built); 2b-2d v0.17.0; 2e v0.18.0, v0.21.0, v0.23.0 (corrected v0.24.0); 2f onion v0.20.0 | headless slices green folded; first two-machine 2d contact 2026-08-27 dealt under the lobby overlay (v0.25.3 fixes it, statically) | multi-machine rp1 session, timed liveness session, two-machine tor session with a redial |
| 3 oracle (M2) | v0.21.0 | oracle section green folded | three-machine round, oracle killed mid-hand |
| Workstream U | SodiumXT ABI 8 and 9 (2026-08-15) | ran 2026-08-17 (Windows) and 2026-08-18 (Linux) | none |
| 4 mental poker (M3) | 4a-4c v0.19.0, 4d/4e v0.22.0, batch step v0.25.0 | sections 16 and 19 green folded 2026-08-17; batch path 2026-08-24 | played-hand wiring, 4f, 6-max Level 2 sessions |
| 5 hardening (M4) | DLEQ v0.22.0 | a wrong unmask refused and named, 2026-08-17 | hostile review by a non-author, and a soak |

Open work is tracked in the suite's docs/WORK-PLAN.md.

## Development

```sh
bash tools/run-gates.sh                 # the whole gate list, in order
python3 tools/check-livecodescript.py   # the static gate: after EVERY script edit
python3 tools/check-script-vectors.py   # the harness itself, run headlessly
```

`tools/run-gates.sh` is the one list: the static gate, the docs and table-layout gates,
seven KAT mirrors, the independent fuzz, and the execution gate, which runs the shipped
stack's harness sections through the family's interpreter (compiling still needs an
engine). CI is the generated `.github/workflows/gates.yml`, and the suite runs the same
script.

## Documentation

- [holdem-spec.md](holdem-spec.md): the design contract (threat model, deal ladder,
  transcript, settlement receipts, non-goals). The source and the KAT tools cite it by
  name and section number, which is why the documents live at the member root.
- [CLAUDE.md](CLAUDE.md): the engineering playbook, layer contracts and evidence ledger.
- [assets/cards/NOTICE.md](assets/cards/NOTICE.md) and
  [assets/sounds/NOTICE.md](assets/sounds/NOTICE.md): licensing for the vendored art
  and audio.
- The suite index:
  [docs/README.md](https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/docs/README.md).

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

holde-em is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`holde-em/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/hold-em: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `holde-em/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port holde-em --ref pull/<n>/head`, keeping its
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

- `../riptide` from https://github.com/SethMorrowSoftware/RipTide - `tools/check-demo-boot.py` and `tools/riptide_reference.py`, which `tools/check-script-vectors.py` drives the stack through.
- `../nostrxt` from https://github.com/SethMorrowSoftware/NostrXT - what riptide's runner loads at import time.
- `../coinxt` from https://github.com/SethMorrowSoftware/CoinXT - what riptide's runner loads at import time.

Clone them beside this checkout under exactly those directory names
(and keep this checkout named `holde-em`), or point `XTALK_SIBLINGS` at a
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

- Sibling libraries embedded by the suite's `tools/sync-demo-embeds.py` (the copy is the shipped file; the master is the sibling's `src/`):
  - `src/holdem.livecodescript` carries `onionxt/src/onionxt.livecodescript` from https://github.com/SethMorrowSoftware/OnionXT.
- `tools/check-livecodescript.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

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
