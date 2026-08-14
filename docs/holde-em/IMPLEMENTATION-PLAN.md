# IMPLEMENTATION-PLAN.md — the phased build order

Read `CLAUDE.md` first (the operational guide) and treat `holdem-spec.md` as the
contract; this file sequences the work. Phases are strictly ordered by dependency, each
with **exit criteria** that separate what a machine can verify (static gates, KATs)
from what only the user's on-engine OXT pass can confirm. Nothing advances a phase on
"verified statically" alone.

The spec's milestones map onto phases: M0 = Phase 1, M1 = Phase 2, M2 = Phase 3,
M3 = Phase 4 (+ workstream U), M4 = Phase 5.

---

## Phase 0 — repo bootstrap (current)

The seed folder becomes its own repository and gains its safety net.

1. Move `docs/holde-em/` out of Box2Dxt into the new repo root (this folder is laid out
   so the move is a plain copy; nothing references Box2Dxt paths).
2. `README.md` (done in the seed), license decision (the family is MIT — confirm).
3. CI (`.github/workflows/ci.yml`): run `tools/check-livecodescript.py` on every
   push/PR (it passes trivially until `src/` exists), plus the docs smart-quote scan.
4. Skeletons: `src/holdem.livecodescript` and `src/holdem-selftest.livecodescript`
   with the stack scaffolding (openStack/closeStack brackets, build-UI stub, harness
   runner stub with `kHeHarnessV = 1`).
5. **Decision to record here when made — Kit delivery:** `start using` the Box2Dxt Kit
   stack as an installed dependency, vs embedding a synced copy between sentinels (the
   Box2Dxt-examples pattern; requires carrying `sync-embedded-kit.py` and its CI gate).
   Default leaning: **embed**, so the game stays one paste-and-run stack like the rest
   of the family's examples — but measure the paste size first.

**Exit:** CI green in the new repo; skeleton stack compiles in OXT (user-confirmed).

## Phase 1 — hotseat game (spec M0)

Everything runs locally, six seats on one machine, zero networking. This phase is
where all visual iteration happens and where the pure logic gets pinned. Build order
inside the phase matters:

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
  hand.
- **2e. Liveness** (spec 9): act timers + time-bank, sit-out, reconnect via
  transcript replay from last checkpoint, host election.
- **2f. Onion tables** (spec 10): the same envelopes over OnionXT streams — expected
  to fall out nearly free once 2c is honest about its transport seam.

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

**Exit:** a three-machine round (two players + non-playing oracle on an onion address)
completes with the oracle never holding a seat; killing the oracle mid-hand voids and
resumes per spec 9.

## Workstream U — upstream SodiumXT ristretto255 (parallel; blocks Phase 4)

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

- DLEQ (Chaum-Pedersen) proofs per unmask step — wrong steps become impossible rather
  than attributable; the envelope's reserved `proof` field fills in.
- Batch scalar mult; any measured FFI hot spots.
- **Hostile review** of the deal implementation by someone who did not write it, and a
  soak-test period. Only after this does spec section 13's sequencing rule (the gate in
  front of any future value layer) even begin to apply — and section 13's non-goals
  (regulatory, collusion, bots) remain exactly as out-of-scope as the spec says.

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
