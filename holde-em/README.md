# holde-em

**Serverless online no-limit Texas Hold'em for OpenXTalk (OXT) and the xTalk family**
(also LiveCode 9.6.3+). No accounts, no server: players meet over the BitTorrent DHT,
every action lives in a signed, hash-chained transcript, and the deal runs on a
security ladder that tops out at a **ristretto255 mental-poker shuffle** — nobody, not
even the table host, can see a card they are not entitled to, and every completed hand
is verifiable after the fact.

Built by composing the OXT extension family:

| Extension | Provides |
|---|---|
| [TorrentXT](../torrentxt/) | rp1 peer messaging, DHT rendezvous (the table code IS the invite), BEP44 signed standings |
| [SodiumXT](../sodiumxt/) | identities, sealed lanes, commitments, randomness — and (since its ABI 8, 2026-08-15) the ristretto255 surface the mental-poker deal needs |
| [OnionXT](../onionxt/) | optional: anonymous tables over Tor, and onion-hosted deck oracles |
| [Box2Dxt](../box2dxt/) | the Kit: spritesheet card animation and physics chips |

> **Documentation:** [`docs/README.md`](docs/README.md) indexes this app's pages. The design contract is [`holdem-spec.md`](holdem-spec.md); the build order is [`IMPLEMENTATION-PLAN.md`](IMPLEMENTATION-PLAN.md).

## Running it

The whole game is one paste-and-run stack that builds its own UI, and hotseat play
needs no extensions at all.

1. **Install [OpenXTalk](https://openxtalk.org) (OXT).** (It also runs in LiveCode
   9.6.3+, but OXT is the target.)
2. **Paste the stack.** `File > New Mainstack`, then `Object > Stack Script`; open
   [`src/holdem.livecodescript`](src/holdem.livecodescript), copy all of it, paste it
   in, and apply/compile.
3. **Close the stack window and reopen it.** Reopening is what builds the table: the
   stack sizes itself to 1024x640 and opens on the lobby. Press **Leave (play hotseat)**
   for a local game. **Close the window when done** — that is what stops the session and
   cancels this stack's timers.
4. **For online play, install the extensions** via `Tools > Extension Manager`:
   **TorrentXT** (`org.openxtalk.library.torrent`) and **SodiumXT**
   (`org.openxtalk.library.sodium`), both required before Create or Join does anything.
   Optional: **Box2Dxt** (`org.openxtalk.box2dxt`) with its `box2dxt-kit` stack loaded,
   for the card art and chip physics, and **OnionXT** (`start using stack "onionxt"`,
   plus a locally running tor daemon) for onion tables. Every one is probed at the point
   of use and fails closed with a readable reason — there is no silent fallback.
5. **The self-test rides in the same stack.** Type `heRunSelftest` in the message box
   for the report panel, or call `heSelfTest()` to get the same report back as a value.

Everything visual and timed is "verified statically; needs an OXT pass" until a human
confirms it in the IDE — the Status section below says which halves are still owed one.

## Status

**Phase 1 hotseat + Phase 2 online play (2d) with onion tables (2f) and the FULL 2e
liveness layer (street checkpoints, show/muck, online History, host election — and,
since v0.23.0, act timers with a per-hand time-bank, sit-out/return, late-join
seating, and onion auto-redial), plus the Phase 3 deck oracle, the Phase 4a-4d
Level 2 layer (compute + void-and-audit) with its 4e adversarial harness, and Phase
5's DLEQ proofs — one paste-and-run stack, at v0.25.0, sized 1024x640 inside
the suite's 720p budget (re-layout verified by rect arithmetic; the confirming eye
is the OXT pass's). v0.25.0 (2026-08-23) batches the Level 2 shuffle-mask step on
SodiumXT ABI 9 - one atomic `sxRistrettoScalarMultBatch` crossing for all 52 mults,
4 FFI crossings per step against the per-point loop's ~312, with that loop kept as
the pre-ABI-9 fallback AND the refusal path so no void string changes - and adds the
leaf-tranche harness section (no wire change; the deal-delivery wire bodies gained
their own protocol-kat pins the same day). v0.24.0 is a correction pass over that liveness layer: ten
reviewed defects (a redial that could kill the host election, a catching-up client
that refused every later timeout, consensus state written around folds the engine
had refused, a table parked for sit-outs that could never resume, ghost seats for
departed peers) fixed with **no wire change at all** — protocol-kat's 114 pins are
untouched (132 since 2026-08-23), so v0.23.0 and v0.24.0 clients speak the identical
protocol.** v0.24.1 clears the three source-side blockers the suite-fold assessment
named, again with no wire and no gameplay change: a dead `b2kSpriteOnFinish` receiver
removed (it was the Kit's setter name, so it never fired -- and the card-flip chaining
it was written for was never wired either), all 187 script-level declarations hoisted
above the first handler, and a quiet `heSelfTest()` entry point added beside
`heRunSelftest`. v0.24.4 (2026-08-17) then corrected the host election itself:
`heNetElectablePubs` scanned the seated list without ever consulting `sitOutBy`, so a
sat-out seat could be elected — and because every client runs the same code, every
client agrees on a successor guaranteed not to re-host, which is a deterministic table
death rather than a divergence. It rides the live-seated scan now, filtered the way
the rest of the liveness layer filters it; two protocol pins were ADDED beside the
existing ones and none changed, so a v0.24.3 client and a v0.24.4 client speak the
identical protocol. v0.24.5 fixed a display defect three hands of real hotseat play
turned up the same day: the History line summed every seat's total commitment, so an
uncalled all-in reported a pot of 2400 for a pot of 784. The deltas, chip conservation
and the settlement audit were right throughout — which is why every existing gate
stayed green over a wrong number — so it was a display defect and not a money one;
`heAwardedPot` is the extracted rule, pinned five ways in the harness and mirrored in
`tools/fold-kat.py`. Both stay "verified statically; needs an OXT pass". The live
multi-machine passes are the pending exit gates: a multi-hand rp1 session on real
networks (Phase 2, now including seats timing out on real wall clocks), a two-machine
onion table over live tor (2f, + a real host-stream loss and redial), and a
**three-machine oracle round** (Phase 3); the ristretto255 handlers (SodiumXT ABI
8/9) have never run on an engine.
`src/holdem.livecodescript` is the whole thing — the hotseat game, the online lobby, its
self-test (`heRunSelftest` in the message box for the report panel, or `heSelfTest()`
to get the same report back as a value), and SodiumXT/TorrentXT diagnostics
(`heProbeSodium` / `heProbeTorrent`) — in a single self-building stack with no required
extensions to be playable hotseat. The table shows per-seat names, chip totals, bets in
front, dealer/blind badges, and fold/all-in/acting/winner states, with quick-bet
controls. A **Settings** panel lets the host configure the table — **opening chips, small/
big blind, ante, player count (2-6), the blind schedule, and deal speed** (fast/normal/slow)
— and Apply starts a fresh table on the new config. Blinds can stay **fixed** (a cash game),
**rise by hands played** (every N hands), or **rise on a timer** (every M minutes) — turning
the table into a tournament — with the interval the host's to set. The betting engine handles antes as dead money (into the pot, never the street
bet, so a seat still owes the full blind) and side pots layer over them; the blind schedule
raises the stakes every N hands. All of that is machine-verified: antes and the level
schedule are pinned in `tools/betting-kat.py`, re-checked on-engine (`heTestAnteRun` /
`heTestLevelRun`), and fuzzed for chip conservation over thousands of ante hands in
`tools/logic-fuzz.py`. A hand plays out at **dealing pace** rather than flashing to the result: each
board street lands a beat after the betting closes, an all-in **runs out one street at a
time**, and the showdown **holds on the revealed hands** before the pot is settled and the
next hand deals. The beats are timer-driven (never per-frame) and are four one-line
constants (`kHeStreetRevealMs`, `kHeRunoutStepMs`, `kHeShowdownHoldMs`, `kHeNextHandDelayMs`)
so the feel is easy to dial in on an OXT pass. With **SodiumXT** present the played hand deals from the **Level 0 committed
keyed-stream shuffle** (spec 7.1) — each contributor's seed is committed, then revealed,
and the deck is a hash of the XOR of the seeds, so the shuffle is fixed by the commitments
and **provably consistent with the revealed seeds on replay** — tamper-evident: no one can
swap a card after the fact. The whole crypto path is wrapped in a `try`, so any failure
falls back to a labelled practice PRNG and the playable path can never break. (One party
still contributes every seed today — in hotseat one human holds them all — so this is the
auditable, tamper-evident machinery, **not yet** unstackable against a *cheating dealer*:
that adversarial guarantee needs independent per-player seeds, each committed before any
reveal, and arrives with online play.)

A **History** panel shows every completed hand — board, pot, winner, the named showdown
hands, per-seat deltas — folded straight from the transcript and **re-verified on the
spot**, with **two audits**: the settlement (the fold re-derives each payout and compares
it to the logged one) and, for Level 0 hands, the **deal** (the committed shuffle is
re-derived from the revealed seeds and confirmed to have produced exactly the cards dealt).
Since v0.21.0 an **online** session's signed wire chain folds here too — translated into
the same replayable shape (holes re-derived from the revealed seeds, mucked showdown hands
annotated) and run through the identical fold + audits. "Copy transcript" exports the raw,
replayable record. Both audits are independently pinned in CI (`tools/fold-kat.py`).

With **SodiumXT + TorrentXT** installed, the stack opens on an **online lobby**: Create a
table (its 64-hex code is the invite) or Join one, and peers meet over the BitTorrent
DHT. Every peer admits-or-drops others at handshake against a signed session token; the
host catches each new joiner up by replaying the whole signed, hash-chained wire log from
genesis (the spec 9 reconnect seam); and a signed `cfg` + `roster` presence pair
propagates so every client verifies (or drops) it and the roster stays in agreement. The
overlay shows the live peer roster and a feed of every verify/drop verdict. The presence
wires are machine-pinned in `tools/protocol-kat.py` and re-checked on-engine by
`heTestLobbyRun`; the transport itself is verified statically and needs an OXT pass (two
machines, one code). On that transport the **full online Level 0 game** runs (Phase 2d):
sealed hole delivery, blinds and betting as signed wires through the same pure engine,
end-of-hand seed reveals every client re-derives the showdown from, verified settles,
co-signed receipts, per-client audits — plus street **checkpoint wires** at every
boundary (fork evidence against an equivocating host, and the resync replay resumes from
your applied seq instead of genesis), **show/muck** display-choice wires at showdown,
and **host election** (deterministic: lowest live seated key) when the host goes silent
mid-game — the in-flight hand voids and stacks stand at the last receipt; the live
handover is the Phase 3 exit gate. Since v0.23.0 the table is also **live against
slow and vanished players** (spec 9): the signed config carries the **act timer, a
one-per-hand time-bank, and the sit-out miss count**; the acting seat's countdown
shows on its plate, and expiry is a **host-signed timeout wire** every client
verifies (exact check-or-fold prescription, transcript-derived bank state, the
deadline against its own clock) before folding — so the transcript stays
deterministic and a rushing host is refused as evidence. Repeated misses (or your
own **Sit out** button) sit a seat out: dealt out at the next boundary, mid-hand
turns auto-folded instantly, **Return** re-enters next hand, and a table short of
live players waits instead of ending. **Late joiners** are seated into empty seats
at the next hand boundary (or watch as observers when the table is full).

With **OnionXT** also loaded (plus a locally running tor daemon), the host can flip the
lobby's transport toggle and host an **onion table** (spec 10, built 2026-08-15): the
same signed envelopes ride OnionXT streams instead of rp1, the table's v3 onion address
is derived deterministically from the host's identity and the table id (a restarted
host keeps its address, so the invite survives), and the invite extends compatibly to
`64hex@<address>.onion` — one pasteable string carrying transport, rendezvous, and the
host endpoint's identity (a v3 address IS its ed25519 key). Everything fails closed
with a readable reason — no tor daemon, no OnionXT, a malformed invite, or an onion
invite pasted into a stack without the library — never a silent fallback to the DHT
transport; a lobby status line walks the tor probe states (connecting / bootstrapping
N% / publishing / redialing / ready / FAILED-with-why). A host stream lost mid-game
**auto-redials** (bounded, backing off — the deterministic onion address means the
same invite still works) and resyncs from a **trimmed** replay when the host answers,
while the election watchdog keeps counting underneath and always concludes. The
invite codec, the refusals, the stream handshake, and the redial-vs-election ordering
are pinned headlessly in the harness (sections 17 and 20); the live multi-hand
onion session (two machines + tor) is the pending engine-era gate.

The lobby's **"Host: ORACLE"** toggle (Phase 3, spec 7.2) makes the same stack host as a
**deck oracle** — a Level 1 table where the host deals every hand and **plays no seat**:
players' committed entropy still fixes the shuffle (the oracle adds its own committed
seed at an extra position, so it cannot stack and nobody's seed stands alone), sealed
hole delivery rides the existing path authored by the oracle key, receipts stay a
seats-only multi-signature, and the oracle's audit verdict files by name. It works over
either transport; an onion-hosted oracle derives its service address under its own
domain tag, so it can never collide with the same host's playing table. Oracle loss is
host loss by construction — the same election path covers both. The harness drives an
oracle-hosted hand end to end on three loopback contexts (section 18); the **live
three-machine round** — two players plus a non-playing oracle on an onion address,
killed mid-hand and recovered per spec 9 — is the Phase 3 exit gate ("verified
statically; needs the multi-machine pass, + live tor for the onion oracle").

The **Level 2 mental-poker layer** (spec 7.3, plan 4a-4e + the Phase 5 proof half) is
built as pure `heL2*` handlers on SodiumXT's ristretto255 surface (ABI 8 + the ABI 9
DLEQ/batch follow-ons): card base points by domain-separated hash-to-group,
commutative shuffle-mask steps with per-hand scalars and permutations, the free
duplicate check (identical points in a masked deck are publicly visible), public and
hole unmask-chain verification, reveal-scalar showdown re-verification — every failure
a distinct, attributable `void:` string — plus, since v0.22.0, the **void-and-audit
state machine** (plan 4d): pinned `shuffleStep`/`unmaskStep` record formats, strict
ordering with replay-vs-equivocation told apart, hand-void with bets returned, and a
mandatory full-reveal audit that **names the signer of the first bad step**. The
spec 12.4 **adversarial harness** (plan 4e) drives five scripted cheater bots against
it — deck-stacker (vs the Level 0 audit), duplicate-point shuffler, rollback replayer,
wrong-scalar unmasker, deal staller — every attack detected and correctly attributed,
every verdict pinned. **Chaum-Pedersen DLEQ proofs** (spec 7.4, Phase 5) ride the
unmask records' reserved `proof` field: derandomized, domain-tagged, batch-verified,
with soundness pinned negatively (forged proofs verify false) — so on a `dleq=1` table
a wrong unmask step is refused instantly instead of costing a void-and-audit round.
`tools/protocol-kat.py` pins the whole layer from fixed scalars end to end (re-derived
by an independent RFC 9496 reference), and the embedded harness re-checks the same
vectors on-engine, skipping cleanly on a pre-ristretto or pre-ABI-9 SodiumXT.
**Honestly: nothing plays on Level 2 yet** — the played-hand wiring and the 4f
deal-time budget measurement are engine-era work, the Phase 5 hostile review and soak
are human-era, and the `sxRistretto*` calls have never run on an engine.

The math is **verified sound** by `tools/logic-fuzz.py`, which checks the committed logic
against *independently-written* references (not the line-for-line KAT mirrors): the
evaluator is verified **exhaustively** over all 2,598,960 five-card hands (exactly 7462
equivalence classes, order-isomorphic to a second evaluator), and side-pot settlement and
whole games (chip conservation, no negative stacks, termination) are fuzzed over ~90k
random configs with fixed seeds — zero defects. Blind scheduling uses a dead-button-aware
rule (the big blind always advances to the next live seat, so eliminations never double-
or skip-charge a blind). All of this runs headless in CI (`tools/*-kat.py` +
`tools/logic-fuzz.py`). Everything visual is "verified statically; needs an OXT pass".

- **[holdem-spec.md](holdem-spec.md)** — the design contract: threat model, the
  three-level deal protocol ladder, the transcript, settlement receipts, and the honest
  non-goals (read section 13 before ever thinking about real stakes).
- **[IMPLEMENTATION-PLAN.md](IMPLEMENTATION-PLAN.md)** — the build order, Phase 0
  (bootstrap) through Phase 5 (hardening), with exit criteria per phase.
- **[CLAUDE.md](CLAUDE.md)** — the engineering playbook: everything about OXT /
  LiveCodeScript / LCB, the required extensions and their APIs, and every carried
  lesson from the sibling repos.

## Development

There is no headless way to compile or run a `.livecodescript`; the automated safety
net is the static gate plus every pure-logic check that CAN run headless — run the gate
after every script edit, and the whole set before you push:

```sh
python3 tools/check-livecodescript.py   # the static gate: after EVERY script edit
python3 tools/check-docs.py             # docs smart-quote scan
python3 tools/check-table-layout.py     # control geometry, re-derived from the builders
python3 tools/evaluator-kat.py          # spec 8.2 evaluator vectors
python3 tools/betting-kat.py            # spec 8.1/8.3 betting + settlement cases
python3 tools/shuffle-kat.py            # the playable integer deal
python3 tools/protocol-kat.py           # spec 6/7.1 wires + the 7.3 ristretto algebra
python3 tools/fold-kat.py               # transcript fold + settlement/deal audits
python3 tools/atlas-kat.py              # card atlas <-> frame-name mapping
python3 tools/sounds-kat.py             # vendored WAVs <-> stack mapping
python3 tools/logic-fuzz.py             # independent-reference fuzz (rules, not the port)
```

`.github/workflows/ci.yml` runs all of those but `check-table-layout.py`, on every push
and PR; suite-side, `tools/build-all.sh --gates` runs every one. Everything else
(anything visual, timed, or extension-touching) is "verified statically; needs an OXT
pass" until a human confirms it in the IDE. See CLAUDE.md for the full workflow.

---

*Seeded from the Box2Dxt repository's `docs/holde-em/` folder, where the spec was
first developed; built out in its own repository; folded home into the
[xTalk suite monorepo](https://github.com/SethMorrowSoftware/xtalk-suite) as the
member directory `holde-em/` on 2026-08-15 (the standalone repository is a mirror).*
