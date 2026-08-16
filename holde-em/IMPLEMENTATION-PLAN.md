# IMPLEMENTATION-PLAN.md — the phased build order

Read `CLAUDE.md` first (the operational guide) and treat `holdem-spec.md` as the
contract; this file sequences the work. Phases are strictly ordered by dependency, each
with **exit criteria** that separate what a machine can verify (static gates, KATs)
from what only the user's on-engine OXT pass can confirm. Nothing advances a phase on
"verified statically" alone.

The spec's milestones map onto phases: M0 = Phase 1, M1 = Phase 2, M2 = Phase 3,
M3 = Phase 4 (+ workstream U), M4 = Phase 5.

---

## Phase 0 — repo bootstrap (done)

> **Where this project lives (updated in the 2026-08-15 fold):** the seed folder
> left Box2Dxt for its own repository as step 1 planned, was built there through
> v0.18.0, and then folded home into the xTalk suite monorepo as the member
> directory `holde-em/` — the riptide/nocloud mold. The standalone repository
> becomes a mirror; the suite's stale seed copy at `docs/holde-em/` was removed
> in the fold. The safety net below now ALSO runs suite-side on every push, via
> `tools/build-all.sh --gates`.

The seed folder becomes its own repository and gains its safety net.

1. Move `docs/holde-em/` out of Box2Dxt into the new repo root (this folder is laid out
   so the move is a plain copy; nothing references Box2Dxt paths). **Done.**
2. `README.md` (done in the seed), license decision. **Decided: MIT** (the family
   default), `LICENSE` at the repo root.
3. CI (`.github/workflows/ci.yml`): runs `tools/check-livecodescript.py`, the docs
   smart-quote scan (`tools/check-docs.py`), and every headless KAT
   (`tools/evaluator-kat.py`, `tools/betting-kat.py`, `tools/protocol-kat.py`) on
   every push/PR. **Done.**
4. Skeletons: superseded — Phase 1's pure logic landed directly (see below); the two
   stacks exist with full scaffolding and `kHeHarnessV = 1`.
5. **Decision recorded — Kit delivery:** `start using` the installed Kit stack for now
   (`heKitTryInit` probes for stack "box2dxt-kit" and degrades to the dependency-free
   flat UI mode when absent). Embedding a synced copy between sentinels stays open as
   a Phase 1d option once the Kit is actually wired to art and the paste size can be
   measured; the sync tooling is not carried until then.

**Exit:** CI green in the new repo ✅; stack compiles and runs in OXT ✅ (the
"pending, needs the first OXT pass" this line carried was stale by v0.11.1 — the
stack's changelog records repeated OXT passes from v0.2.0 on, and the v0.17.2
defect was found AT first run on engine; corrected in the 2026-08-15 fold's
truth pass).

## Phase 1 — hotseat game (spec M0)

Everything runs locally, six seats on one machine, zero networking. This phase is
where all visual iteration happens and where the pure logic gets pinned. Build order
inside the phase matters:

**Status:** 1a/1b and the pure halves of 1e are written and machine-pinned (CI KATs
green; the stack's own `heRunSelftest` carries the same vectors for the on-engine
run). 1d exists as the self-building chrome in two modes — a dependency-free flat mode
and the Kit mode scaffold (atlas loading, pre-warm, gated frame loop); animation
polish is left for the OXT pass. Everything below stays "verified statically; needs an
OXT pass" until the user runs the harness and plays hands in OXT.

**Math + rules audit (v0.3.0).** The betting engine, side pots, settlement, evaluator,
and PRNG were audited: property tests (an independent conserving side-pot reference vs
the engine over 60k+ configs; 6k random full games; 400 full sessions to elimination;
min-raise invariants; PRNG uniformity) all pass with zero defects, and an
xTalk-vs-Python equivalence pass confirmed the shipped stack matches the tested
mirrors. The one rules gap found -- no dead-button handling, so an elimination could
double- or skip-charge a blind -- is fixed: the big blind now always advances to the
next live seat (`heScheduleButton`, pinned in `tools/betting-kat.py` and the on-engine
harness). The table UI was also rebuilt chip-forward (per-seat panels, chip totals,
bets in front, dealer/blind badges, fold/all-in/acting/winner states, pot, quick-bet
buttons) -- verified statically, needs an OXT pass.

**As-built deal (v0.2.0, a code-wins decision).** 1c was originally the Level 0
commit-reveal keyed-stream deal (spec 7.1). Repeated OXT passes threw double/binary
conversion errors wherever script code touched FFI-bridged SodiumXT `Data` through the
chunk/arithmetic evaluator — persisting even after the H6 copy-to-local fix. So the
**playable deal is now a pure-integer PRNG shuffle** (Park-Miller MINSTD, seeded from
`sxRandomUniform` when present — an integer result, no binary in script — else engine
time+`random()`, labelled practice), pinned by `tools/shuffle-kat.py`. This unblocks a
playable, demoable M0 without depending on the fragile FFI-binary path. The
cryptographic Level 0 deal stays specced and KAT-pinned (`tools/protocol-kat.py`) and
moves to **Phase 2**, to be wired only behind a confirmed `heProbeSodium` (the stack's
per-`sx*`-call diagnostic). Everything is one paste-and-run stack now — the separate
self-test stack was folded into `src/holdem.livecodescript`.

- **1a. Hand evaluator** (spec 8.2) — first code written, pure function, pinned by
  known-answer vectors in the harness AND mirrored in `tools/` so CI runs them
  headless. Vectors: royal/straight/wheel flushes, quads+kicker, boat over boat, flush
  vs straight, board-plays (split), the A-K-Q-J-9 near-straight, order-independence
  property checks.
- **1b. Betting engine + side pots** (spec 8.1) — a pure state machine consuming
  transcript-shaped messages even offline (hotseat actions are appended to a local log
  and folded, exactly as network messages will be — this is deliberate: Phase 2 then
  swaps the message source, not the engine). Pin with harness cases: min-raise rules,
  all-in-below-min-raise not reopening, three-way layered side pots, heads-up blind
  order, showdown order.
- **1c. Level 0 local deal** (spec 7.1 run against local seats) — seeds, commitments,
  Fisher-Yates from the keyed stream, hole delivery, end-of-hand audit. Running the
  real commit-reveal code paths locally means Phase 2 adds transport, not logic.
- **1d. Table UI + animations** (spec 11) — self-building UI (the family pattern:
  construct chrome on open, tag with a `kUIVersion`, bump when chrome changes); pooled
  card sprites + chip bodies at build; `b2kSheetEnsureIcon` pre-warm; deal slides
  (`b2kSpriteMoveTo`, ~70 ms stagger), squash-flip via one-shot + `b2kSpriteOnFinish`
  + `b2kSpriteSetFrame` (gotchas 19/23/27); one-impulse chip tosses that settle and
  sleep (gotcha 17); HUD on-change at <= 4 Hz.
- **1e. Harness v1**: evaluator vectors, betting cases, deal-audit round-trip,
  transcript replay determinism (a canned hotseat session folds to identical state
  twice), plus the family rule — bump `kHeHarnessV` on every engine-behavior change.

**Exit:** the user plays a complete **6-seat** hotseat session in OXT (blinds through
showdown through settlement, multiple hands, side pots exercised, all 17 table cards
on-screen at a full showdown); harness green; CI KATs green. *Playable and demoable by
itself.*

## Phase 2 — friendly online play (spec M1, deal Level 0)

The netcode spike. Everything here is turn-rate — rp1's ~1 s tick is the budget.

- **2a. Identity module**: seed → `sxSignKeypairFromSeed`; fingerprint handles; BEP44
  profile records via the external-signing path (`btDhtBep44SignBuf` +
  `sxSignDetached` + `btDhtPutSigned`).
- **2b. Table rendezvous**: random table id → `btAddInfohash(sxHash(id))` +
  `btDhtAnnounce`/`btDhtGetPeers`; the nocloud-style short code IS the invite;
  admission tokens in `btRp1SetToken`.
- **2c. Envelope + transcript** (spec 6): canonical serialization, signing, hash
  chain, host seq assignment + countersign, verify-or-drop, street checkpoints.
  `tools/protocol-kat.py` pins envelope bytes, chain heads, and a full Level 0 deal
  from fixed seeds — headless, in CI.
- **2d. Online Level 0 deal + receipts** (spec 7.1, 8.3): sealed-box hole delivery,
  end-of-hand seed reveal audit, countersigned settlement receipts chained hand to
  hand. **Status: written (v0.17.0), netsim-pinned on one machine; needs the
  multi-machine OXT pass.** As-built shape: `join` wires bind each player's session
  box pub on-chain; host `sit` wires assign seats; the dealer is the button seat;
  seeds travel as on-chain `seedSeal` ciphertexts; showdown ranks are re-derived
  from the revealed seeds (players cannot lie about holes); the host's `settle` is
  verified by every client before folding; `receipt` wires carry the 8.3
  co-signatures. Street `ckpt` wires and `show`/`muck` were deferred to 2e alongside
  liveness (they exist for reconnect windows and display choice, not correctness) and
  landed there (v0.21.0, below); online History folding likewise.
- **2e. Liveness** (spec 9): act timers + time-bank, sit-out, reconnect via
  transcript replay from last checkpoint, host election.
  **Status: BUILT in three increments, all verified statically -- the
  reconnect/hardening half at v0.18.0 (deterministic per-hand seeds,
  replay-proof emissions, catch-up suppression, the crash-and-reconnect sim);
  street ckpts, show/muck, online History, and the election at v0.21.0; and
  the liveness remainder (act timers + time-bank, sit-out/return, late-join,
  onion auto-redial) at v0.23.0, corrected by the v0.24.0 review pass (ten
  local defects in that layer, no wire changed -- the last bullet below).
  The timed live pass is what 2e still owes (the closing note below).**
  As-built:
  - **Street ckpt wires** (spec 6): at each boundary (deal/flop/turn/river/
    showdown) every seated client signs the head the boundary's TRANSITION wire
    produced -- body `street=..,head=..,sig=..`, so the head rides the wire and
    a verified ckpt naming a different head is logged as CKPT-FORK evidence,
    never folded as agreement. Consumed on replay: the `s?` resync frame now
    carries the requester's applied seq and the host replays only the tail, so
    a mid-hand client resumes from (at worst) its last street boundary instead
    of shedding the whole log; a bare `s?` and the reconnect handshake still
    get the full replay. Pinned: ckpt_body/ckpt_head7 in protocol-kat; the
    netplay sim asserts same-head ckpts on both sides and a marker-only
    trimmed replay for a caught-up peer.
  - **show/muck** (spec 6/8.1): seat-scoped display-choice wires emitted after
    the verified settle -- display only (ranks derive from the revealed
    seeds). Policy: contested non-losers show, contested losers muck,
    uncontested winners muck, earlier folds emit nothing. The showdown paint
    now honors it (only shown seats' cards go up); History annotates
    "(mucked)". Pinned: show/muck wire heads in protocol-kat, the annotation
    in fold-kat + the canned fold fixtures.
  - **Online History folding**: heNetLogToHotseat translates the signed chain
    into the hotseat-shaped transcript (sit wires -> cfg seats/stacks, pubkeys
    -> seat names, sealed deliveries -> holes re-derived from the reveals,
    show/muck repositioned ahead of their settle) and History runs the SAME
    fold + deal audit over it; the netplay sim pins a 2-hand translation
    (settle-verified, 2/2 deals verified, stacks match the live fold).
  - **Host election** (spec 9): built as the slice Phase 3 needs -- a
    wire-silence watchdog (60 s during play; the onion transport also routes
    its positive stream-death here), deterministic election (lowest pubkey
    among live seated players, `heElectHostOf`, pinned as elected_host), void
    of the in-flight hand with stacks standing at the last receipt, and the
    successor NAMED on every client. The LIVE handover (elected host re-hosts,
    peers re-join) is exercised by Phase 3's exit gate, not faked here.
  - **The 2e remainder CLOSED at v0.23.0 (2026-08-16, verified statically;
    harness section 20 pins the headless slice).** As-built:
    - **Act timers + time-bank** (spec 8.1/9): timer lengths ride the signed
      cfg (`act=/bank=/miss=` -- lobby_cfg_body/lobby_head2 pins regenerated,
      a documented consensus change; wire-compatible, unknown keys are
      ignored); no deadline wire exists -- the host-countersigned
      turn-opening wire starts every clock, and expiry is the HOST's signed
      timeout wire: the EXISTING act/bid wire with `seat=/timeout=1/bank=`
      marks, verified by every client (exact check-or-fold prescription,
      transcript-derived bank state, deadline passed on its own clock within
      5 s of transport jitter -- deliberately NOT the +-600 s wall-clock
      window, no timestamp crosses the wire; catch-up replay waives the
      clock check) and folded as the named seat's action. The one per-hand
      bank auto-arms on the first would-be timeout and spends ON the wire
      (`bank=1` -- consensus, not clocks). Forced posts get the same
      treatment once the deal completes; an L0 deal stall stays honestly
      unprescribed (spec 9's dealing timeout is the L2 machine's).
    - **Sit-out/return** (spec 9): auto after `miss=` consecutive timeouts
      (transcript-derived), or by the seat's own signed `stand`; a
      sitting-out seat times out instantly mid-hand and is dealt out at the
      boundary (`heNetNextOccList`); its own `sit` (no pub) re-enters next
      hand; a short table WAITS for returns instead of ending.
    - **Late-join**: the existing full-replay machinery stands; the host now
      seats joined-but-unseated keys into empty seats at each hand boundary
      (ascending pubkey, cfg-capped, signed sit wires, cfg opening stack) --
      or the joiner stays an observer when full. Since v0.24.0 the key must
      also be PRESENT (heNetPubIsLive), not merely have joined once.
    - **Onion auto-redial**: bounded (4 attempts, 2/4/8/16 s backoff, 10 s
      per dial) on host-stream death during play, BEFORE the 60 s election
      watchdog concludes; every step gates on the election (it always
      concludes; the redial stands down quietly), and a successful redial
      resyncs via the TRIMMED replay (the hello's compatible trailing-seq
      item; a host wire applying resets the counter).
    - **The v0.24.0 CORRECTION PASS (2026-08-16, verified statically).** A
      review of the layer above found ten defects, every one of them local
      state-ordering or control-flow -- **no wire changed** (protocol-kat's
      114 pins are untouched, so a v0.23.0 and a v0.24.0 client speak the
      identical protocol). Fixed, each with its own harness pin in section
      20 (kHeHarnessV 39), each pin written to fail against the old
      behaviour: a mid-redial dial failure took the fail-closed path and
      cancelled the poll tick, which killed the election watchdog and
      attempts 2..4 (heNetOnionDialFail); redial exhaustion overwrote the
      elected successor's status line (heNetOnionStandDown, one quiet exit
      for both paths); a full-replay client's act clock started at replay
      time and then refused the host's live timeout forever
      (heNetTurnClockStart marks the clock replayed; the waiver keys on
      that and dies with the turn); the timeoutSent latch never cleared on
      an engine-refused timeout, so the host silently stopped re-emitting
      (heNetTimeoutRearm); the time-bank spend, the miss count and the
      miss RESET all ran around a fold that can refuse (gGame["foldApplied"]
      gates all three -- and being identical on every client made the wrong
      state consensus rather than a detectable divergence); a table parked
      for sit-outs could never resume (the park is latched and the react
      engine unparks it on the returning seat's own wire); the plate's
      countdown painted over SIT OUT (heSeatFaceLabel, now pure and pinned);
      and heNetHandKick's duplicate occupancy scan collapsed into
      heNetSeatedWithChipsList.
      **DECIDED 2026-08-16: spectators are DEFERRED** (owner: "we do not
      need spectators at this point"). This is no longer blocking; what
      follows is the record of what deferring MEANS, kept so the question
      is not re-derived from scratch when someone wants them. The
      late-join gate now requires liveness, but spec 4's read-only
      SPECTATOR is still indistinguishable from a player at a hand
      boundary: the admission token carries a role field, yet every client
      that can talk to this build sends "player" in it, so refusing on role
      would refuse real players. Declaring spectator intent needs a wire
      and/or UI decision (a role a joiner can choose, or a `sit`-request
      wire the host answers) -- deliberately NOT invented in a pass whose
      whole constraint was to change no wire. Not needed for the 2e live
      pass; revisit only if spectators are wanted.
    What the LIVE pass still owes 2e: a timed multi-machine session on wall
    clocks (real seats timing out, the bank visibly arming, a sit-out
    rejoining), a real tor host-stream loss -> redial -> trimmed resync
    (plus the standing 2f two-machine onion exit), and a try at the one
    RECORDED edge -- a timeout redelivered inside a reorder-buffer burst is
    early-refused by the client that just caught up (fail-visible, healed
    by reconnect; holde-em/CLAUDE.md's liveness contracts name it). Until
    then everything above is "verified statically; needs an OXT pass".
- **2f. Onion tables** (spec 10): the same envelopes over OnionXT streams — expected
  to fall out nearly free once 2c is honest about its transport seam.
  **Status: built 2026-08-15 (v0.20.0), verified statically; the exit — a
  multi-hand onion table session on two machines with a running tor daemon — is
  the pending live gate.** It did fall out nearly free: 2c/2d had already
  funneled every outbound payload through four netCap-seamed senders and every
  inbound frame through one router (heNetOnMessage), so 2f added exactly one
  live byte-out seam (heNetTxTo, routed by gGame["transport"]) plus a poll-tick
  line-reassembly drain on the inbound side — the envelopes, chain, fold, and
  react engine changed not at all. As-built decisions (recorded in spec 10):
  the host's service seed is H("HOLDEM-ONION-v1|" || idSeed || "|" || table)
  (secret-keyed, per-table, deterministic — a restarted host keeps its address,
  so the invite survives); the invite extends compatibly to
  `<64hex>@<56base32>.onion` (one word, non-hex, so a pre-2f stack refuses it
  readably instead of joining an unannounced DHT table — downgrade refusal by
  format, and heJoinRefusal is the pure gate); the admission token that rides
  rp1's handshake event rides each stream's first wire line (the "h" frame),
  answered by the host's own hello before the replay so the ordered stream
  delivers host identity before host-signed wires; one wire line per oxWrite,
  LF-terminated (no payload can carry an LF — every free-text field is
  hex-encoded). Assume-running tor on the stock ports, every probe state on a
  lobby status line, every silent wait watchdogged, every failure fail-closed
  with a readable reason (the nocloud pattern). Harness section 17 pins the
  headless slice: invite codec + refusal vectors, seed-derivation properties,
  the address round-trip when OnionXT is present, and the hello handshake
  driven through the real router on loopback contexts.

**Exit:** a **6-seat** table completes a multi-hand session over rp1, spread across as
many real machines as are available (minimum three; multiple stack instances per
machine fill the remaining seats) and user-verified on real home networks, not just
localhost; a mid-hand disconnect reconnects and resumes; a tampered envelope and a
replayed envelope are provably dropped (harness bots); receipts match on every seat;
KATs green in CI.

## Phase 3 — deck oracle (spec M2, deal Level 1)

- Deck-daemon mode of the same stack (headless-ish table host that plays no seat):
  Level 0 dealing logic relocated behind the oracle role; players' entropy still
  commits the shuffle.
- Hosted as a v3 onion service (`oxCreateServiceFromSeed` for a stable address);
  assume-running tor, fail closed with a clear message when absent (the nocloud
  pattern).
- Host election handles oracle loss identically to host loss.

> **BUILT 2026-08-16 (v0.21.0), verified statically; the exit below is the
> pending live gate.** As-built decisions (recorded in spec 7.2):
> - "Oracle mode" is the lobby's Host toggle on the SAME stack -- the host
>   role minus the seat, not a separate daemon. `level=1` in the signed cfg
>   IS the oracle marker (spec 7.2 is Level 1); `dealLevel` carries
>   `level=1,dealer=0`. A pre-oracle client refuses the hand readably at its
>   dealLevel gate (downgrade refusal), never mis-folds the table.
> - Players' entropy still commits the shuffle, and the oracle contributes
>   its OWN committed seed at position dealCount+1 -- committed before it
>   saw anyone's, so it cannot stack; it holds no cards, no stack, and signs
>   no receipts (a seats-only multi-signature), but it does reveal its seed
>   (the XOR needs it) and emits its audit verdict, filed as "oracle".
> - Hole delivery rides the EXISTING sealed path, authored by the oracle
>   key; seedSeals seal to the oracle's session box (its join binds one).
> - Works over EITHER transport via the 2f seam. An onion oracle derives its
>   service seed under its own domain tag (kHeDomainOracle -- spec 16:
>   every hash carries its purpose), pinned in protocol-kat beside the 2f
>   playing derivation.
> - Oracle loss IS host loss by construction (one election path; the
>   oracle, never seated, is never electable) -- see 2e's election note.
> - Harness section 18 drives an oracle-hosted hand end to end on three
>   loopback contexts (deal path, the no-seat invariant everywhere,
>   seats-only receipts, the oracle's reveal + audit, election + void on
>   oracle silence), with the live legs SKIPped by name.

**Exit:** a three-machine round (two players + non-playing oracle on an onion address)
completes with the oracle never holding a seat; killing the oracle mid-hand voids and
resumes per spec 9. **This is the one gate the build above still owes -- nothing about
the oracle is "done" until that round has been played for real.**

## Workstream U — upstream SodiumXT ristretto255 (parallel; blocks Phase 4)

> **SHIPPED 2026-08-15 (statically).** With both projects now members of the
> xtalk-suite monorepo, this landed as suite-internal work: SodiumXT ABI 8
> exposes the five handlers below, KAT-pinned twice over (libsodium-derived
> vectors in its C smoke test and member harness, re-derived by the
> independent RFC 9496 reference now embedded in this repo's
> `tools/protocol-kat.py` - the exit criterion's cross-check). `sxHash512`
> proved unnecessary: `sxHash(tData, 64)` already yields the 64-byte digest
> `sxRistrettoFromHash` wants. Still open before Phase 4 leans on it: the
> `sxRistretto*` handlers' first OXT engine pass, and the recorded Phase 5
> follow-ons (batch multiplication, point add/sub, base mult for DLEQ).
> Those follow-ons shipped 2026-08-15 too, as SodiumXT ABI 9
> (`sxRistrettoAdd`/`sxRistrettoSub`, `sxRistrettoScalarMultBase`,
> `sxRistrettoScalarMultBatch`, `sxRistrettoScalarAdd`/`sxRistrettoScalarMul`)
> - statically, with the same twice-over KAT pinning in
> `tools/protocol-kat.py` - so the engine pass is now the one open item here.

Runs in the **SodiumXT repo**, not here; tracked in this plan because Phase 4 cannot
start without it.

- Expose: `sxRistrettoFromHash`, `sxRistrettoScalarMultPoint`,
  `sxRistrettoScalarRandom`, `sxRistrettoScalarInvert`, `sxRistrettoPointValid`
  (+ `sxHash512` if not already public). All are thin wrappers over libsodium's
  `crypto_core_ristretto255_*` / `crypto_scalarmult_ristretto255` — expose-only, no new
  cryptography.
- SodiumXT ABI bump + KAT vectors (libsodium's own test vectors) + self-test additions,
  per that repo's contribution rules.
- Later (Phase 5): `sxRistrettoScalarMultBatch` (52 points, one FFI crossing) and
  point add/sub + `sxRistrettoScalarMultBase` for DLEQ proofs.

**Exit:** SodiumXT release with the new surface; KATs green there; this repo's
`tools/protocol-kat.py` extended with cross-checked ristretto vectors.

## Phase 4 — mental poker (spec M3, deal Level 2)

> **4a-4c COMPUTE built + KAT-pinned 2026-08-15 (statically; v0.19.0).** The
> pure algebra of the masked deck, the unmask chains, and the reveal-scalar
> showdown landed as the heL2* section of `src/holdem.livecodescript`:
> values in, values out (H5), lowercase hex at every seam (the H6
> corollary), every failure a distinct "void:..." string so 4d's
> attribution can name it, and nothing wired into any played-hand path.
> `tools/protocol-kat.py` pins a complete Level 2 hand from FIXED scalars
> end to end -- the 52 base points, a three-seat mask/shuffle round, a
> public unmask chain, a hole chain with the owner's step absent, the
> showdown re-verification from a revealed (k, sigma), and seven refusal
> cases (24 new pinned values, all re-derived by the file's independent
> RFC 9496 reference) -- and `heTestLevel2Run` re-checks the same constants
> on-engine behind a cached ABI-8 probe (a pre-ristretto SodiumXT is a
> clean SKIP, never an uncaught throw). Still open: 4d-4f and ALL
> orchestration (wire vocabulary, void-and-audit sequencing, the
> adversarial bots), and the OXT engine pass owes the sx* call shapes and
> the 4f deal-time budget measurement. Spec 7.3 carries the as-built
> decision marks.

> **4d/4e built + KAT-pinned 2026-08-16 (statically; v0.22.0).** The
> void-and-audit layer landed PURE and transport-agnostic (H5) -- the
> 4a-4c note above filed sequencing under engine-era orchestration, but
> the sequencing itself needs no wire, only records, so the harness can
> drive it fully: the step-record formats are pinned (spec 6 as-built --
> `shuffleStep` body `pos=,ck=,deck=` with the deck's points "|"-joined and
> `ck` the Phase 5 commitment key; `unmaskStep` body `pos=,slot=,val=,
> proof=` with `proof` spec 7.4's reserved field), and `heL2Void*` is the
> machine that consumes them: strict shuffle order, identical-re-post = dup
> vs different-re-post = named equivocation, the free public checks per
> record, owner-aware chain order per slot, completion -> card or void.
> Attribution is DIRECT (named=pos) when the record itself is refusable
> and DEFERRED to `heL2VoidAudit` -- the mandatory full-reveal audit, in
> the mandatory order (ck binding + shuffle re-verification per
> contributor, then chains in slot order) -- when only the reveals can say
> (final-not-in-table); a timeout names the staller provisionally and the
> audit keeps the name only if everything signed re-verifies (the spec's
> "first bad one" rule). The outcome line pins hand-void + bets-return +
> reveal-required. The 4e bots are pure drivers over that machine
> (harness section 19): deck-stacker (vs L0, heAuditDeal names it),
> duplicate-point shuffler, rollback replayer, wrong-scalar unmasker
> (deferred -> audit names its step), deal staller -- every verdict string
> pinned twice (protocol-kat's l2v_/l0_ scenario keys over the independent
> reference, re-asserted on-engine with self-diagnosing asserts). Still
> open here: 4f (the deal-time budget is an ENGINE measurement) and the
> played-hand wiring; the sx* ABI-9 calls have never run on an engine.

The value-candidate deal. Prerequisite: Workstream U shipped.

- **4a. Masked deck**: base points from domain-separated hash-to-group; per-hand
  scalar + permutation per player; shuffle-mask rounds with signed full-deck
  `shuffleStep`s; the free duplicate check (identical points in a masked deck are
  publicly visible) asserted on every step.
- **4b. Unmask chains**: public cards (chain in seat order, last value must hit the
  52-point table) and hole cards (owner last, penultimate value public and useless to
  everyone else).
- **4c. Reveal-scalar showdown**: `show` carries `(k, sigma)`; every client re-verifies
  the revealer's every step; muck = don't reveal.
- **4d. Void-and-audit**: garbage final point or deal-phase timeout → hand void, bets
  return, mandatory full reveal for the void hand, first bad signed step names the
  cheater, config-signed forfeit applies.
- **4e. Adversarial harness** (spec 12.4): scripted cheater bots — deck-stacker
  (against L0), wrong-scalar unmasker, duplicate-point shuffler, rollback replayer,
  deal staller — every one must be *detected and correctly attributed* in the harness
  report. Self-diagnosing asserts (print observed vs expected), per the family rule.
- **4f. Deal-time budget check** on-engine: the 52-mult FFI burst per shuffle step must
  not visibly hitch the table (measure; if it does, pull Workstream U's batch handler
  forward).

**Exit:** full Level 2 sessions across real machines at the reference **6-max** size
(user-verified — including the deal pace: ~6 s per street over rp1 per the spec's
batched-chain requirement); the adversarial harness passes attribution on every
scripted attack; KATs pin a complete Level 2 hand from fixed scalars end to end.

## Phase 5 — hardening (spec M4)

> **The DLEQ half built + KAT-pinned 2026-08-16 (statically; v0.22.0), on
> SodiumXT ABI 9.** `heL2DleqProve`/`heL2DleqVerify` (+ `heL2CommitKeyHex`)
> are Chaum-Pedersen over ristretto255: prove P2 = k*P1 for the k behind
> ck = k*B -- an unmask step proves (k, stepOut, stepIn) -- with a
> DERANDOMIZED nonce (RFC 6979 / EdDSA pattern), a domain-tagged
> Fiat-Shamir challenge over the lowercased hex transcript, every scalar
> reduced mod L via ScalarAdd-zero before any point mult (libsodium masks
> bit 255 in scalarmult; the reference reduces mod L; reducing first pins
> both), and proof = a1||a2||z (96 bytes, spec 7.4's size) riding the
> unmaskStep record's reserved `proof` field. The verifier batches c*ck
> and c*P2 through ONE `sxRistrettoScalarMultBatch` crossing (the one
> place the batch genuinely saves a crossing -- z*B and z*P1 have
> different bases and cannot join it; the 52-mult shuffle-step batch
> stays a 4f decision, measured on-engine). On a dleq=1 machine a wrong
> unmask is refused INSTANTLY with direct attribution -- 7.4's
> "impossible rather than attributable" -- and missing ck/proof are
> themselves named refusals. Soundness is pinned NEGATIVELY in
> protocol-kat (wrong secret, swapped points, tampered commitment, and
> the honest procedure over a false statement -- the wrong-scalar
> unmasker's only forgery). The Fiat-Shamir transcript and response
> equation were mirrored and pinned in the pure-Python reference FIRST,
> then the xTalk written to match. NOT done, on purpose: the hostile
> review and the soak period below are HUMAN-ERA work and stay open --
> nothing about this build discharges them -- and the sx* DLEQ calls have
> never run on an engine.

- DLEQ (Chaum-Pedersen) proofs per unmask step — wrong steps become impossible rather
  than attributable; the envelope's reserved `proof` field fills in. **Built (above).**
- Batch scalar mult; any measured FFI hot spots. **The batch handler shipped (ABI 9)
  and the DLEQ verifier uses it; the deal-path hot spots wait on 4f's measurement.**
- **Hostile review** of the deal implementation by someone who did not write it, and a
  soak-test period. Only after this does spec section 13's sequencing rule (the gate in
  front of any future value layer) even begin to apply — and section 13's non-goals
  (regulatory, collusion, bots) remain exactly as out-of-scope as the spec says.
  **Open — human-era, deliberately not claimable by any static build.**

**Exit:** spec 7.4's first-hardening ceiling shipped; review findings closed; the
"value-readiness" checklist in spec 13 honestly assessable.

---

## Risks and mitigations (carried forward from the family's experience)

| Risk | Mitigation |
|---|---|
| rp1's ~1 s tick feels sluggish for action UX | It is the *budget*, not the goal: direct-TCP upgrade lane (`btMapPort` + engine sockets, the nocloud pattern) is optional polish from Phase 2e on; the protocol never requires it |
| UPnP absent/broken in many homes | Never required: rp1 rides the swarm; onion tables need no ports at all; direct TCP is opportunistic only |
| OXT socket/timer quirks under load | nocloud already shipped an HTTP server on engine sockets — carry its lessons; all net work on the poll timer, never per-frame (H2) |
| Evaluator/side-pot edge cases | Pure functions + CI KATs before any UI exists (1a/1b); the family's harness-first rule |
| Level 2 FFI burst hitches the deal | Measure at 4f; batch handler ready in Workstream U |
| A "constant declared below its use" class of silent OXT bug | Gotcha 29 discipline + constants at top of file; the static gate cannot see this one — code review must |
| Scope creep toward value before the gates | Spec 13's sequencing rule is written into Phase 5's exit criteria; nothing in Phases 0-4 touches money |
