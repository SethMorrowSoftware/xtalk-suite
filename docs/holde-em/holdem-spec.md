# Online Texas Hold'em for the OXT extension family — design spec

**Status: pre-implementation spec (plan, not as-built).** This is the design brief for a
serverless online no-limit Texas Hold'em game built on the OpenXTalk extension family:
Box2Dxt (presentation), TorrentXT (transport + rendezvous), SodiumXT (all cryptography),
and optionally OnionXT (anonymous transport / oracle hosting). This spec is the contract
to build against; its companions are `CLAUDE.md` (the operational guide + every carried
OXT/LiveCodeScript lesson) and `IMPLEMENTATION-PLAN.md` (the phased build order). Where
the eventual code differs from this spec, the code wins and this file gets updated.

The one-sentence design goal: **make the deal and the settlement cryptographically
verifiable now, so that if chips ever carry real value, the game logic is not the weak
link.** The spec is explicit about what that does and does not buy (section 2, section 13).

---

## 1. Goals and non-goals

**Goals**

- A 2-9 player no-limit hold'em table with **no server**: peers meet over the BitTorrent
  DHT, talk over the `rp1` peer-wire extension, and every game action lives in a
  hash-chained, ed25519-signed transcript any client can replay and verify. **6-max is
  the reference configuration** — every latency budget, pool size, and test-exit
  criterion is stated for (at least) six seats; anything that only works heads-up is a
  bug.
- A **deal protocol ladder** (section 7): the same game runs at three security levels,
  from "friendly table, rotating host" up to a **ristretto255 mental-poker deal** where
  no party — player or host — can see a card they are not entitled to, and every
  completed hand is verifiable after the fact.
- **Deterministic settlement**: chip deltas are a pure function of the transcript;
  every player countersigns a settlement receipt per hand. Receipts, not balances, are
  the interface a future value layer would consume.
- Cheating that cannot be *prevented* must be *detected and attributable* — the
  transcript must identify the signer of the offending message.
- Degrade gracefully: the same stack runs a hotseat game with zero networking, a
  friendly rp1 table at Level 0, and a hardened table at Level 2.
- A presentation layer worthy of the Kit: spritesheet card animation, physical chips
  (section 11).

**Non-goals (stated so nobody discovers them late)**

- **Regulatory compliance.** Real-money play implicates gambling licensing, KYC/AML,
  and jurisdiction law. None of that is addressed here and none of it is a software
  problem. This spec's job ends at technical fairness and auditability.
- **Collusion resistance.** Two players sharing hole cards over the phone beat every
  protocol on earth, including the ones commercial poker sites run. Detection heuristics
  (statistical play analysis) are out of scope.
- **Bot detection.** Out of scope, same reason.
- **Zero-knowledge shuffle proofs** (Bayer-Groth and friends). They are the known
  ceiling above Level 2 — prevention instead of detection for malformed shuffles — and
  they are a research project, not an extension feature. Documented in 7.4, not built.
- **Custody / payments.** No wallet, no deposits. Section 13 defines the receipt
  interface a value layer (e.g. CoinXT) could consume, and stops there.

## 2. Threat model

Tiered, in ascending capability. Each protocol level in section 7 states which tiers it
defeats.

| Tier | Adversary | Wants | Answer |
|---|---|---|---|
| T0 | Wire observer (ISP, LAN, DHT crawler) | read hands, link players | all payloads sealed/authenticated (SodiumXT); optional Tor for metadata (OnionXT) |
| T1 | Cheating **player** | peek at cards, stack the deck, forge/replay/reorder messages, roll back a lost hand | signatures + hash chain + seq numbers kill forgery/replay/rollback at every level; card secrecy depends on the level (L0: dealer peeks, L2: nobody peeks) |
| T2 | Cheating **host/dealer** | same, from the privileged seat | L0: entropy-committed shuffle means the host cannot *stack*, but can *peek* (accepted, rotated); L1: peeker has no stake; L2: the privileged seat does not exist |
| T3 | **Colluding** players (incl. host) | share hole-card knowledge, soft-play | out of scope at the protocol layer (see non-goals); the transcript at least preserves the evidence for after-the-fact analysis |
| T4 | Network attacker | DoS a player mid-hand, partition the table | liveness rules (section 9): timers, void-and-audit, forfeit; a DoS can void a hand but cannot steal a pot |

Explicitly out of scope: endpoint compromise (malware reading the victim's own screen),
a global passive adversary correlating Tor traffic, and out-of-band collusion.

**The residual-risk sentence that must survive into any user-facing doc:** at Level 2
the deal is fair and the ledger is honest even against a cheating majority at the wire
level, but *nothing* here stops two humans exchanging screenshots. Real value makes that
threat profitable. Read section 13 before attaching value.

## 3. What each repo provides

| Layer | Repo | Used for |
|---|---|---|
| Rendezvous | TorrentXT | `btAddInfohash` phantom swarm per table + `btDhtAnnounce` / `btDhtGetPeers`; the table code is the info-hash (nocloud's short-code UX) |
| Messaging | TorrentXT | `rp1` (`btRp1Enable` / `btRp1SetToken` / `btRp1Send` / `btRp1Poll`): opaque bytes, ~1 s flush, 60000-byte cap — far above every message here |
| Identity, crypto | SodiumXT | ed25519 identities (`sxSignKeypairFromSeed`, `sxSignDetached`), sealed boxes for private lanes, `sxHash` commitments, `sxRandomBytes` entropy, kx session keys; **Level 2 needs new `sxRistretto*` handlers** (section 14) |
| Profiles, standings | TorrentXT + SodiumXT | BEP44 mutable records signed externally (`btDhtBep44SignBuf` + `sxSignDetached` + `btDhtPutSigned`) — the key never crosses the FFI |
| Anonymous transport | OnionXT | optional: the whole table over onion streams (latency is irrelevant here); hosting the Level 1 oracle as a v3 onion service |
| Presentation | Box2Dxt Kit | spritesheet cards, physical chips, the frame loop (section 11) |

Fallback transport: any peer pair may upgrade to a direct engine-socket TCP link
(`btMapPort` for the router port, nocloud's proven pattern) purely for snappier UX. The
protocol never *requires* better than rp1's ~1 s.

## 4. Architecture and roles

- **Player**: holds a long-term ed25519 identity; signs every message it emits.
- **Table host**: the player (or oracle) whose machine relays messages and assigns
  transcript sequence numbers. **The host is a message switchboard, not an authority**:
  it orders messages, it cannot forge them (each is signer-signed) and, from Level 1 up,
  it cannot see anything a player cannot.
- **Deck oracle** (Level 1 only): a non-playing host; see 7.2.

Topology is a star through the host (rp1 or TCP or onion). A full mesh is never
required; any player unreachable peer-to-peer still plays via relay.

**The game is a deterministic state machine over the transcript.** Client UI state is a
pure fold over transcript messages. This buys: reconnection (replay the log), spectators
(read-only replay), dispute evidence (the log *is* the game), and the settlement function
(section 8.3).

## 5. Identity and keys

- **Long-term identity**: 32-byte seed → `sxSignKeypairFromSeed`. The public key is the
  player id; a short fingerprint (first 8 hex of `sxHash(pubkey)`) is the display handle.
  Profiles (name, avatar hash, standings) live in BEP44 mutable records under this key.
- **Per-table session**: on join, each player generates an ephemeral X25519 box keypair
  (`sxBoxKeypair`), binds it by signing `("HOLDEM-SESS-v1", tableId, boxPub)` with the
  long-term key. Private lanes (hole-card deliveries at L0/L1) are sealed boxes to the
  session key. Fresh per table; compromise of one table's session key never spans tables.
- **Admission**: the table config (section 6) lists the admitted pubkeys (or "open").
  Each peer's `btRp1SetToken` carries its signed admission claim so peers can drop
  strangers at handshake time, before any game message.
- **Freshness law**: every hand uses fresh deal randomness (L0 seeds, L2 scalars and
  permutations). Nothing dealing-related is ever reused across hands. Long-term keys
  sign; they never encrypt.

## 6. The transcript

Every game message is one envelope, CBOR-or-tab-delimited (implementation's choice, but
canonical — one byte sequence per logical message, or signatures break):

```
{ v: 1,                     -- protocol version
  table: <32B table id>,    -- random, chosen by the creator; the DHT info-hash is sxHash(table)
  hand: <int>,              -- hand number, 0 = table setup
  seq: <int>,               -- assigned by the host relay, strictly increasing
  prev: <32B>,              -- sxHash of the previous envelope (hash chain)
  from: <ed25519 pubkey>,
  type: <string>,           -- see the message vocabulary below
  body: <type-specific>,
  sig: <64B> }              -- sxSignDetached over all preceding fields, canonical order
```

Rules, each closing a specific hole:

- **Verify or drop.** A message with a bad signature, an unknown `from`, a stale `seq`,
  or a `prev` that does not match the local chain head is dropped and logged. No
  exceptions, including from the host.
- **The host assigns `seq` and countersigns the envelope it relays** (an outer
  signature). A host that reorders or drops selectively produces a chain other players
  can present as evidence; it still cannot forge content.
- **Checkpoints**: at every street boundary (deal complete, flop, turn, river, showdown)
  each player signs the current chain head (`type: "ckpt"`). A rollback attack now needs
  every player's cooperation — i.e. it is not an attack, it is a table agreeing to void.
- **Table config is message zero**: stakes, blinds, timer lengths, deal level (0/1/2),
  admitted keys, void/forfeit rules — signed by every player before hand 1. Nobody can
  later dispute the rules they signed.

Message vocabulary (body schemas fixed at implementation time, names fixed here):
`cfg join leave sit stand shuffleStep unmaskStep seedCommit seedReveal holeDeliver
bid[SB/BB] act(fold|check|call|bet|raise|allin) ckpt show muck settle audit chat`.

## 7. The deal protocol ladder

The deal is the only part of poker that is cryptographically interesting. Everything
else is bookkeeping over the transcript. The table config pins the level; all three
levels share the transcript, betting engine, and settlement.

### 7.1 Level 0 — rotating host deal (friendly tables)

The spades-grade protocol, inherited unchanged:

1. Every player broadcasts `seedCommit` = `sxHash(seed_i)` (32-byte `sxRandomBytes` seed).
2. Every player sends `seed_i` to the current dealer in a sealed box.
3. The shuffle is a Fisher-Yates draw from a keyed stream:
   `stream = sxHash("HOLDEM-SHUF-v1" || table || hand || seed_1 XOR ... XOR seed_N)`.
   The dealer **cannot stack the deck**: their own seed was committed before they saw
   anyone else's.
4. The dealer sends each player's two hole cards in a sealed box (`holeDeliver`); board
   cards are broadcast at each street.
5. At hand end, everyone broadcasts `seedReveal`; every client recomputes the shuffle
   and audits the whole deal (`audit` message carries pass/fail + the failing step).

Defeats: T0 entirely, T1 stacking/forgery, T2 stacking. Accepts: the dealer *sees* all
cards that hand (rotate the deal every hand), and the audit reveals mucked cards after
the hand (a visible house rule). **This level exists to get a playable game early and to
soak-test the transcript; it is not the value-ready level.**

### 7.2 Level 1 — deck oracle (non-playing dealer)

Level 0's exact protocol, but the dealer role is a machine with no stake: a headless-ish
"deck daemon" mode of the same stack, run by a non-player (a spare box, a Pi), reachable
**as a v3 onion service via OnionXT** so it needs no port forwarding and its operator
needs no network setup. Entropy is still player-committed (the oracle cannot stack); the
oracle sees cards but holds no cards, and it never sees the betting (it gets deal-phase
messages only). Collusion oracle-with-player remains (T3) — that is why Level 2 exists.

### 7.3 Level 2 — ristretto255 mental poker (the value-candidate deal)

No dealer at all: nobody — player, host, or oracle — learns any card they are not
entitled to, at any point. Built on one primitive: commutative masking by scalar
multiplication on the ristretto255 group (libsodium has carried it since 1.0.18;
SodiumXT must expose it — section 14).

**Setup (public, once):** the base deck is 52 points
`P_c = sxRistrettoFromHash(sxHash512("HOLDEM-CARD-v1|" || cardName))`, e.g.
`"HOLDEM-CARD-v1|Qs"`. Hash-to-group means no party knows any discrete-log relation
between any two card points — that unknowability is what the whole construction leans on.

**Shuffle-mask round (per hand):** in seat order, each player i takes the incoming deck
(52 points; the base deck for the first player), multiplies **every** point by one fresh
secret scalar `k_i`, applies one fresh secret permutation `sigma_i`, and broadcasts the
resulting deck as `shuffleStep` (52 x 32 bytes = 1664 bytes; the transcript keeps every
intermediate deck, signed by its author). After all N players, the deck
`D = perm(k_1 k_2 ... k_N * base)` is on the table and nobody knows the composite
permutation or can strip the composite mask alone.

- Unlinkability of the shuffle is DDH on ristretto255; recovering a mask is CDH. Both
  are the assumptions the rest of libsodium already stands on.
- **Free integrity check**: duplicated positions in a masked deck are *publicly visible*
  (same card + same composite mask = identical 32-byte points), so every client asserts
  all 52 points of every `shuffleStep` are distinct, and rejects the step otherwise —
  card duplication is prevented, not just detected.

**Dealing.** Card positions are consumed in a fixed public order (hole cards by seat,
then burn/flop/turn/river as in a live game, so the "cut card" arguments are moot).

- *Public card at position j*: an unmask chain in seat order. Player 1 broadcasts
  `unmaskStep` = `k_1^{-1} * D[j]`, player 2 applies `k_2^{-1}` to that, and so on; the
  final value must equal some base point `P_c` — that is the card. A final value outside
  the 52-point table is proof of a wrong step somewhere → the **void-and-audit rule**
  (below). Every step is signed by its author.
- *Hole card for player A at position j*: the same chain, but A goes **last** and does
  not broadcast the final step. The publicly-visible penultimate value is
  `V = k_A * P_c`, which is useless to everyone but A (CDH). A strips `k_A` privately
  and knows its card. Nothing is sealed, nothing is private except A's own last step —
  the transcript stays fully public.

**Showdown (reveal-scalar showdown — the trick that makes this practical):** a player
who wants the pot broadcasts `show` carrying `(k_A, sigma_A)`. Every client then
verifies *everything A did this hand*: the shuffle step recomputes exactly, every
unmask step recomputes exactly, and A's hole cards fall out of `V * k_A^{-1}` for the
world to see — which is precisely what showdown means in poker. No zero-knowledge
proofs, no extra rounds. Key facts making this safe:

- Scalars and permutations are **per-hand**; revealing them exposes nothing about any
  other hand.
- Revealing `(k_A, sigma_A)` alone does not unmask anyone else's cards or the stub —
  those stay behind the other players' scalars.
- **Mucking still works**: a player may decline to reveal (forfeiting any pot claim),
  exactly like sliding cards to the muck face-down. Their steps simply stay unverified
  that hand — unverified is not cheated; the duplicate check and the garbage-card rule
  still bound what they could have done.

**Void-and-audit rule (the T1/T4 backstop):** if any unmask chain ends outside the card
table, or any player times out mid-deal, the hand is **void**: all bets return, and the
table runs a full audit — every player must reveal that hand's `(k_i, sigma_i)` (the
hand is void, so the reveal costs nothing). The audit recomputes every signed step and
**names the signer of the first bad one**: attribution, not suspicion. Refusing the
audit = the refuser is the named party, per the signed table config. So a cheater or a
staller can burn a hand, but gains nothing, gets named, and (config) forfeits/is kicked.
Repeated voids are themselves evidence.

Defeats: T0-T2 entirely at the card layer (nobody peeks, nobody stacks, everything
attributable). Accepts: T3 (out-of-band collusion — see section 2), and selective abort
costs a void hand before the cheater is named.

**Cost:** one shuffle round = 52 scalar mults + 1 permutation per player (sub-10 ms
native; ~52 FFI crossings, deal-time only — nowhere near a per-frame path), and the
round is N sequential steps ≈ N rp1 ticks once per hand. **Unmask chains batch per
tick — normatively:** a player who owes chain steps applies their scalar to EVERY
pending position and answers with ONE rp1 message, so all in-flight cards advance in
parallel and the pipeline depth is N hops, not N-per-card. The hole-card deal therefore
completes in ~N ticks and each street reveal in ~N more — about 6 s each at a 6-max
table over rp1 (a live dealer's pace; sub-second over the direct-TCP lane). Dealing
card-by-card (cards x N ticks — over a minute at 6-max) is a spec violation, not an
implementation choice. A batch FFI handler (`sxRistrettoScalarMultBatch`) is an
optional later optimization, not a prerequisite.

### 7.4 The ceiling above Level 2 (documented, not built)

Two upgrades exist in the literature if this ever needs to outgrow void-and-audit:
**Chaum-Pedersen DLEQ proofs** per unmask step (each step ships a ~96-byte proof that
the same secret scalar was used as in the shuffle step — wrong steps become impossible
rather than attributable, no more void hands; needs only the same `sxRistretto*` surface
plus point add) and **Bayer-Groth verifiable shuffles** (proof the shuffle step is a
permutation of its input — closes the last detection-only gap; a genuine research
project). Neither blocks value-readiness under this spec's model: void-and-audit with
attribution and pre-signed forfeit rules is a sound foundation — but DLEQ is the natural
first hardening pass, and the message envelope reserves a `proof` field for it.

## 8. Game engine

### 8.1 Betting engine

Deterministic no-limit hold'em over the transcript. The rules the implementation must
pin (all classic, all fiddly, all testable without networking):

- Button and blinds rotate by seat order; heads-up: button is small blind and acts
  first pre-flop, last post-flop.
- Min-raise = size of the largest prior bet/raise of the street; an all-in below the
  min-raise does **not** reopen betting for players who already acted.
- Side pots: layered by all-in amounts; each layer awarded independently at showdown
  (the settlement function iterates pot layers, not players).
- Showdown order: last aggressor of the final street first, then clockwise; players may
  muck in turn (Level 2: muck = don't reveal scalars).
- Timers (from the signed config): act timer with one time-bank per hand; deal-phase
  timer (Level 2 chains); expiry = check/fold in betting, void-and-audit in dealing.

### 8.2 Hand evaluator

Pure xTalk module: best 5 of 7, full ranking with kickers, split detection. Written and
pinned **before** any UI exists, harness-style (the repo's self-test pattern —
self-diagnosing asserts that print what was observed):

- Known-answer vectors: royal/straight/wheel (A-2-3-4-5) flushes, quads with kicker,
  boat over boat, flush vs straight, board-plays-both (split), three-way splits with
  side pots, the A-K-Q-J-9 "almost straight".
- Property checks with fixed seeds: evaluator(7 cards) never depends on input order;
  the winner of (handA vs handB) is antisymmetric.

### 8.3 Settlement receipts

At hand end every client computes `deltas = settle(transcript[hand])` — a pure
function — and broadcasts `settle` carrying `sxHash(deltas || chainHead)` signed. A hand
is **closed** when all seated players' settle signatures match; the collected signatures
form the **settlement receipt**. Receipts hash-chain hand to hand (each receipt commits
to its predecessor), so a table session produces one countersigned ledger no subset of
players can rewrite. Play-money standings published as BEP44 records are derived from
receipts. **A future value layer must consume receipts and nothing but receipts**
(section 13).

## 9. Liveness, disconnects, and aborts

- **Reconnect**: rejoin with the table code, present identity, receive the transcript
  since your last `ckpt`, fold the log, resume. Hole cards at L2 need no re-delivery —
  the chain values are in the transcript; the player recomputes with their own scalar.
  (L0/L1: the dealer re-sends the sealed `holeDeliver` on request.)
- **Timeout in betting**: auto check/fold, seat goes to sit-out after (config) misses.
- **Timeout in dealing** (L2): void-and-audit (7.3). A player who habitually
  "disconnects" when the flop looks bad voids hands but never sees that flop — aborting
  gains zero information (the abort happens before any unmask they can read) — and
  eats the config's forfeit rule.
- **Host loss**: any player can call a host election (deterministic: lowest pubkey among
  live seats); the transcript's checkpoints make the handover point unambiguous. Voids
  the in-flight hand at L2 (audit optional — nobody misbehaved), resumes from the last
  receipt.

## 10. Transport profile

- One rp1 payload = one envelope; no fragmentation needed (largest message is a 1664-byte
  `shuffleStep`; cap is 60000).
- Poll cadence: one `btRp1Poll` drain per existing poll tick (the TorrentXT helpers'
  250 ms tick is fine); **never** per-frame work — the playbook's single-`if` idle rule
  applies to the whole net layer.
- Table lifecycle: create = random table id → `btAddInfohash(sxHash(id))` + announce;
  join = same from the short code; leave = part message + remove torrent. The DHT
  carries **zero game data** — rendezvous only (plus optional BEP44 standings).
- Onion tables: identical envelopes over OnionXT streams; the table code becomes the
  onion address. Latency budget already fits.
- Direct-TCP upgrade: optional pairwise `btMapPort` + engine sockets for sub-100 ms
  action UX; protocol-equivalent, falls back to rp1 silently.

## 11. Presentation (the Box2Dxt part)

Hotseat-first: the table, cards, chips, and full betting UI run locally with a Level 0
local deal before any networking lands (milestone M0). House rules from the playbook
apply throughout; gotcha numbers below cite the carried-lessons list in `CLAUDE.md`
(numbering preserved from Box2Dxt). The specific plan:

- **Art**: Kenney CC0 playing-card + chip sheets (in-family with the platformer's
  assets), loaded via `b2kSheetLoadAtlas`; faces are named frames. `b2kSheetScale` if
  families mix (gotcha 24).
- **Pool at build** (never create mid-hand): card sprites sized for the table's max
  seats at showdown — 2 hole cards x max seats + 5 board + burn indicator (6-max: 18;
  9-max worst case: 24) — plus ~20 chip bodies, parked off-table; `b2kSheetEnsureIcon`
  at build for **every** face that can appear — the ~250 ms lazy-slice hitch landing on
  the river flip is the one unforgivable jank.
- **Deal**: `b2kSpriteMoveTo` slides from the shoe, staggered ~70 ms by `send ... in`
  timers.
- **Flip** (flop/turn/river): sprites do not rotate (gotcha 23), so flips are the
  squash trick — one-shot `b2kSpritePlay` back->edge, then in `b2kSpriteOnFinish` swap
  the face with `b2kSpriteSetFrame` and play edge->flat. Gotchas 19 (OnFinish fires for
  whoever started it) and 27 (capture per-flip context immediately) apply verbatim.
- **Chips**: the one earned physics flourish — chips are *graphics* bodies (they tumble;
  rotation matters), tossed at the pot with a single `b2kForce` write and left to
  settle and sleep (gotcha 17: no per-frame velocity writes, ever). Pot-push to the
  winner is a `b2kSpriteMoveTo` sweep of pooled stacks.
- **Idle cost**: between animations the table costs a handful of gate-`if`s per frame;
  pot/stack HUD updates on change only, 4 Hz max.

## 12. Test plan

1. **Evaluator vectors** (8.2) — pure, offline, first code written.
2. **Protocol KATs**: fixed seeds/scalars → pinned expected decks, chains, and receipts
   (the OnionXT `onion-kat.py` pattern; runs in CI with no engine).
3. **Transcript replay determinism**: a canned table session replays to identical state
   and receipts on every platform (the Box2Dxt determinism-harness pattern applied to
   pure script — no physics involved, so this must pass bit-exact).
4. **Adversarial harness**: scripted cheater bots in the self-test — deck-stacker (L0),
   wrong-scalar unmask, duplicate-point shuffle, rollback replayer, timeout staller —
   each must be *detected and correctly attributed*, and the honest table must settle
   or void exactly per config. The harness prints observed-vs-expected per the repo's
   self-diagnosing-assert rule.
5. **On-engine OXT rounds** for everything visual and everything timed (statically
   verified is not verified; the harness cannot see jank).

## 13. Value-readiness (read before attaching money)

This spec makes the *game* value-ready; it does not make a *product* value-ready:

- **What Level 2 + receipts guarantee**: nobody saw a card they should not have; the
  deal was unstackable; every action is signed and ordered; the ledger is the
  countersigned receipt chain; disputes reduce to "replay the transcript".
- **What they cannot guarantee**: no collusion, no bots, no compromised endpoints, and
  no protection from the operator-of-record's legal exposure. Real-money play is a
  regulated activity in most jurisdictions — licensing, KYC/AML, age verification,
  responsible-gaming duties. Those are prerequisites, not features, and they are out of
  scope here **deliberately**, so that no one mistakes this spec for them.
- **The interface**: a value layer consumes settlement receipts (8.3) — countersigned,
  hash-chained, replay-verifiable — and must treat anything less (a claimed balance, an
  unsigned delta) as void. If CoinXT is ever wired in, it plugs in there, and the deal
  level MUST be 2 with DLEQ hardening (7.4) shipped first.
- **Sequencing rule**: value attaches only after the adversarial harness (12.4) passes
  attribution on every scripted attack, and after a hostile review of the deal
  implementation by someone who did not write it.

## 14. Prerequisite work items, per repo

| Repo | Item | Size |
|---|---|---|
| **SodiumXT** | Expose ristretto255: `sxRistrettoFromHash`, `sxRistrettoScalarMultPoint`, `sxRistrettoScalarRandom`, `sxRistrettoScalarInvert`, `sxRistrettoPointValid`, plus `sxHash512` if not already public (libsodium carries all of it; this is expose-only, no new cryptography) + ABI bump + KAT vectors | the only blocking native work |
| **SodiumXT** (later) | `sxRistrettoScalarMultBatch` (52 points, one crossing); point add/sub + `sxRistrettoScalarMultBase` for DLEQ (7.4) | optimization / hardening pass |
| **TorrentXT** | none — rp1 + BEP44 + phantom swarms suffice as shipped | — |
| **OnionXT** | none — streams + onion services as shipped (L1 oracle, onion tables) | — |
| **Box2Dxt** | none — the Kit as shipped covers section 11 | — |
| **this repo** (`holde-em`, seeded from Box2Dxt `docs/holde-em/`) | the game itself: transcript engine, deal ladder, betting engine + evaluator, table UI; ships as a self-contained stack in the family style (self-building UI, static gates, self-test harness) | the project |

## 15. Milestones

- **M0 — hotseat**: table UI + animations (11), evaluator + betting engine + side pots
  (8.1/8.2), local Level 0 deal, self-test harness with evaluator vectors. No network.
  *Playable and demoable by itself.*
- **M1 — friendly online**: identity, table codes, rp1 envelopes, transcript + ckpts,
  Level 0 deal, receipts, reconnect. Onion-table variant lands here for free.
- **M2 — oracle**: Level 1 deck daemon as an onion service; host election.
- **M3 — mental poker**: SodiumXT ristretto handlers land first (with KATs), then the
  Level 2 shuffle/unmask/showdown/void-audit, then the adversarial harness (12.4).
- **M4 — hardening**: DLEQ per-step proofs (7.4), batch scalar mult, hostile review,
  soak testing. Only after M4 does section 13's sequencing rule even begin to apply.

## 16. Security checklist (implementation laws, SodiumXT-doc style)

- Compare secrets and MACs with `sxMemEqual`, never `is` / `=`.
- All randomness from `sxRandomBytes` / `sxRandomUniform`; the engine `random()` never
  touches anything dealing- or key-related.
- Every hash is domain-separated (`"HOLDEM-<PURPOSE>-v<N>|"` prefixes, versioned).
- Sign canonical bytes; verify before parse; drop-and-log on any failure (6).
- Fresh per-hand randomness, fresh per-table session keys; long-term keys only sign (5).
- No secret ever crosses the FFI that has an external-signing path (BEP44 puts go
  through `btDhtBep44SignBuf` + `sxSignDetached` + `btDhtPutSigned`).
- Scalars/permutations at L2 are per-hand and revealed only via showdown or void-audit.
- The net layer obeys the single-threaded playbook: one poll drain per tick, no
  per-frame crypto, no per-frame FFI.
