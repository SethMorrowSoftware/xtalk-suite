# Online Texas Hold'em for the OXT extension family - design spec

**Status: the living contract, written to match the as-built code.** The design of a
serverless no-limit Texas Hold'em game on the OpenXTalk extension family: Box2Dxt
(presentation), TorrentXT (transport, rendezvous), SodiumXT (all cryptography) and
optionally OnionXT (anonymous transport, oracle hosting). Its companion is `CLAUDE.md`
(operations, layer contracts, carried lessons). Where the code differs, the code wins
and this file is updated. Code cites it by section number; the numbering is stable.

The one-sentence design goal: **make the deal and the settlement cryptographically
verifiable now, so that if chips ever carry real value, the game logic is not the weak
link.** The spec is explicit about what that does and does not buy (sections 2 and 13).

---

## 1. Goals and non-goals

**Goals**

- A 2-9 player no-limit hold'em table with **no server**: peers meet over the DHT,
  talk over `rp1`, and every action lives in a hash-chained, ed25519-signed transcript
  any client can replay and verify. **As built the table is 2-6** (`kHeMinSeats` /
  `kHeMaxSeats`; six seat spots); 7-9 has no code behind it. **6-max is the reference
  configuration** for every budget and exit; anything that only works heads-up is a bug.
- A **deal protocol ladder** (section 7): the same game runs at three security levels,
  from "friendly table, rotating host" up to a **ristretto255 mental-poker deal** where
  no party, player or host, can see a card they are not entitled to, and every
  completed hand is verifiable after the fact.
- **Deterministic settlement**: deltas are a pure function of the transcript; every
  seated player countersigns a receipt per hand. Receipts, not balances, are the
  interface a future value layer would consume.
- Cheating that cannot be *prevented* must be *detected and attributable* to the signer
  of the offending message.
- Degrade gracefully: the same stack runs a hotseat game with zero networking, a
  friendly rp1 table at Level 0, and a hardened table at Level 2.
- A presentation layer worthy of the Kit (section 11).

**Non-goals (stated so nobody discovers them late)**

- **Regulatory compliance.** Real-money play implicates gambling licensing, KYC/AML and
  jurisdiction law. None of that is a software problem; this spec's job ends at
  technical fairness and auditability.
- **Collusion resistance and bot detection.** Two players sharing hole cards over the
  phone beat every protocol on earth; detection heuristics are out of scope.
- **Zero-knowledge shuffle proofs** (Bayer-Groth and friends): the known ceiling above
  Level 2, a research project rather than an extension feature. Documented in 7.4, not
  built.
- **Custody / payments.** No wallet, no deposits. Section 13 defines the receipt
  interface a value layer (e.g. CoinXT) could consume, and stops there.

## 2. Threat model

Tiered, in ascending capability. Each protocol level in section 7 states which tiers it
defeats.

| Tier | Adversary | Wants | Answer |
|---|---|---|---|
| T0 | Wire observer (ISP, LAN, DHT crawler) | read hands, link players | all payloads sealed/authenticated (SodiumXT); optional Tor for metadata (OnionXT) |
| T1 | Cheating **player** | peek at cards, stack the deck, forge/replay/reorder messages, roll back a lost hand | signatures + hash chain + seq numbers kill forgery/replay/rollback at every level; card secrecy depends on the level (L0: dealer peeks, L2: nobody peeks) |
| T2 | Cheating **host/dealer** | same, from the privileged seat | L0: entropy-committed shuffle means the host cannot *stack*, but can *peek* (accepted, rotated); L1: the peeker has no stake; L2: the privileged seat does not exist |
| T3 | **Colluding** players (incl. host) | share hole-card knowledge, soft-play | out of scope at the protocol layer (see non-goals); the transcript at least preserves the evidence |
| T4 | Network attacker | DoS a player mid-hand, partition the table | liveness rules (section 9): timers, void-and-audit, forfeit; a DoS can void a hand but cannot steal a pot |

Out of scope: endpoint compromise, a global passive Tor adversary, out-of-band collusion.

**The residual-risk sentence that must survive into any user-facing doc:** at Level 2
the deal is fair and the ledger is honest even against a cheating majority at the wire
level, but *nothing* here stops two humans exchanging screenshots. Real value makes that
threat profitable. Read section 13 before attaching value.

## 3. What each repo provides

| Layer | Repo | Used for |
|---|---|---|
| Rendezvous | TorrentXT | `btAddInfohash` phantom swarm per table + `btDhtAnnounce` / `btDhtGetPeers`; the table code is the invite |
| Messaging | TorrentXT | `rp1` (`btRp1Enable` / `btRp1SetToken` / `btRp1Send` / `btRp1Poll`): opaque bytes, ~1 s flush, 60000-byte cap, far above every message here |
| Identity, crypto | SodiumXT | ed25519 identities, sealed boxes for private lanes, `sxHash` commitments, `sxRandomBytes` entropy; Level 2 rides the `sxRistretto*` surface (ABI 8, plus ABI 9 for DLEQ and the batch step; section 14) |
| Profiles, standings | TorrentXT + SodiumXT | BEP44 mutable records signed externally (`btDhtBep44SignBuf` + `sxSignDetached` + `btDhtPutSigned`), the key never crossing the FFI. **Specified, not built:** no BEP44 call exists in the stack |
| Anonymous transport | OnionXT | optional: the whole table over onion streams; hosting the Level 1 oracle as a v3 onion service. Carried inside the stack |
| Presentation | Box2Dxt Kit | spritesheet cards and the frame loop (section 11) |

An optional direct-TCP upgrade is specified and unbuilt (section 10); the protocol
never *requires* better than rp1's ~1 s.

## 4. Architecture and roles

- **Player**: holds a long-term ed25519 identity; signs every message it emits.
- **Table host**: the player (or oracle) whose machine relays messages and assigns
  transcript sequence numbers. **The host is a message switchboard, not an authority**:
  it orders messages and cannot forge them (each is signer-signed).
- **Deck oracle** (Level 1 only): a non-playing host; see 7.2.

Topology is a star through the host (rp1 or onion). A full mesh is never required; any
player unreachable peer-to-peer still plays via relay.

**The game is a deterministic state machine over the transcript.** Client UI state is a
pure fold over transcript messages. This buys reconnection (replay the log), spectators
(read-only replay), dispute evidence (the log *is* the game), and the settlement
function (8.3). Spectators were DEFERRED on 2026-08-16: as built, every client joins as
role "player", so a joiner at a table with a free seat is seated at the next hand
boundary; offering a read-only role needs a wire/UI decision.

## 5. Identity and keys

- **Long-term identity**: 32-byte seed -> `sxSignKeypairFromSeed`. The public key is the
  player id; the display fingerprint is the first 8 hex of `sxHash(pubkey)`. BEP44
  profiles (name, avatar hash, standings) are specified, not built (section 3).
- **Per-table session**: on join, each player makes an ephemeral X25519 box keypair and
  binds it by signing `("HOLDEM-SESS-v1", tableId, boxPub)` with the long-term key. As
  built, the `join` wire's `box=` field under the contentLine signature IS that
  binding. Private lanes (hole-card deliveries at L0/L1) are sealed boxes to the
  session key; compromise of one table's session key never spans tables.
- **Admission**: each peer's `btRp1SetToken` carries its signed admission claim
  (`"HOLDEM-SESS-v1|" table | pub | role`, `heAdmitTokenData`), so peers drop a token
  that does not verify for this table at handshake time, before any game message. As
  built every table is effectively "open": any key whose token verifies is admitted. An
  admitted-pubkey list in the table config is **specified, not built**.
- **Freshness law**: fresh deal randomness every hand (L0 seeds, L2 scalars and
  permutations). Long-term keys sign; they never encrypt.

## 6. The transcript

Every game message is one envelope: tab-delimited, with layered signatures (the sender
signs the *content*, the host signs the *sequenced envelope*, because a sender cannot
know `seq` or `prev` under a relay that assigns ordering). Byte-pinned by
`tools/protocol-kat.py`:

```
contentLine = v TAB tableHex TAB hand TAB fromHex TAB type TAB bodyHex
senderSig   = sxSignDetached over utf8(contentLine), by the sender key
envLine     = contentLine TAB senderSigHex TAB seq TAB prevHex
hostSig     = sxSignDetached over utf8(envLine), by the host relay key
wire        = envLine TAB hostSigHex          -- one wire line = one rp1 payload
chainHead   = sxHash("HOLDEM-CHAIN-v1|" || utf8(wire)); genesis prev = 32 zero bytes
```

**A wire is EXACTLY ten TAB-separated fields; a receiver MUST count them and drop
anything else** (normative since 2026-09-09). The signatures cover a PREFIX (sender
items 1-6, host 1-9) while the chain hashes the WHOLE line, so an appended field passes
every signature check and forks the receiver's chain unrecoverably. A bare trailing tab
must also be refused (the engine ignores one trailing delimiter when counting, suite
engine note 2.2); a legal wire ends in a 128-hex host signature.

Fields: `v` protocol version; `table` the 32-byte random table id; `hand` the hand
number, 0 = table setup; `seq` assigned by the host relay, strictly increasing; `prev`
the previous envelope's chain head; `from` the sender's ed25519 pubkey; `body` hex of
type-specific UTF-8 text (hex so no tab can leak into the frame). The DHT info-hash is
the FIRST 20 BYTES of `sxHash(table bytes)`, 40 hex (`heTableInfohash`, pinned as
table_infohash); it hashes the table id's BYTES, not its hex text.

Rules, each closing a specific hole:

- **Verify or drop.** A message with a bad signature, an unknown `from`, a stale `seq`,
  or a `prev` that does not match the local chain head is dropped and logged. No
  exceptions, including from the host.
- **The host assigns `seq` and countersigns what it relays.** Selective reordering or
  dropping leaves a chain others can present as evidence; content cannot be forged.
- **Checkpoints**: at every street boundary (deal complete, flop, turn, river,
  showdown) each player signs the chain head (`type: "ckpt"`). A rollback then needs
  every player's cooperation, which is a table agreeing to void, not an attack.
- **Table config is message zero**: stakes, blinds, timer lengths and deal level. As
  built the host alone authors and signs `cfg` (`v, level, sb, bb, ante, stack, seats,
  button, act, bank, miss`; `heLobbyCfgBody`, pinned as `kKatLobbyCfgBody`), and the
  host relay refuses a `cfg` from any other key. An admitted-key list, void/forfeit
  rules and per-player co-signing of `cfg` before hand 1 are **specified, not built**.
- **Every wire index is a canonical decimal, keyed and compared as TEXT** (normative
  since 2026-09-25, v0.25.5). A position, seat, count, dealer seat, button or dealt
  hand's number, and the relay's `seq`, is a non-empty run of ASCII digits with no
  leading zero (at most 14, below where the engine blurs two integers), inside its
  range; a receiver drops any other spelling. The format's own zeros (the oracle's
  `dealer=0`, `level=0`) are matched as exact text. The engine reads `"03"`, `"3.0"`,
  `"+3"`, `" 3"` and `"3e0"` as the number 3 while an array keeps the raw key (suite
  engine notes 2.10, 2.11), so a numeric check let a dealer post its own `seedCommit`
  under aliases of its position, have them counted as everyone's, collect the honest
  seals, and choose its seed last. Per-position and per-seat state is stored under
  the canonical key, first wins, and every "all are in" count is WALKED over
  positions `1..count` (or the hand's dealt seats), never incremented per message, so
  no alias or duplicate can advance it (`heCanonIdx`, `heNetPosFilled`,
  `heNetSeatsFilled`).
- **A per-hand wire names the open hand** (normative since 2026-09-25). `dealLevel`,
  the three seed types, `holeDeliver`, `board`, `bid*`, `act`, `settle`, `receipt`,
  `audit`, `ckpt`, `show` and `muck` must carry the currently open hand in `hand`,
  which the SENDER signs; any other is dropped whole. Without it a host could
  re-sequence a previous hand's signed commitments and reveals into a new hand and
  hold every seed before choosing its own, or replay a player's old `act` at its
  turn. And `handStart` hand numbers strictly increase at a table: each seat's seed
  derives from table and hand (7.1 step 1), so a repeated number repeats every seed.
  History's translation applies both rules. **Not closed:** WITHIN one hand an `act`
  carries no turn key, so the host could re-sequence a player's earlier signed act at
  a later turn (two honest checks are byte-identical, so no content dedupe can tell
  them apart). Binding an act to its turn changes wire bytes; it is not built.

Message vocabulary: `cfg join leave sit stand shuffleStep unmaskStep seedCommit
seedSeal seedReveal holeDeliver board bid[SB/BB/Ante] act(fold|check|call|bet|raise|
allin) ckpt show muck settle receipt audit chat`. `board` carries the L0/L1 street
broadcast so replay is self-contained; `seedSeal` carries 7.1 step 2's sealed seed ON
the chain; `receipt` carries the 8.3 co-signature. protocol-kat pins every one of the
22 source wire types.

Body schemas (all byte-pinned in `tools/protocol-kat.py`):

- `cfg`: also carries the section-9 timer lengths `act=<s>,bank=<s>,miss=<n>`; unknown
  keys are ignored, so extensions are wire-compatible.
- `join`: `box=<64hex>`, the sender's per-table session box pub. `stand`: `seat=N`
  from the seat's own key (sit-out).
- `sit` (host, one per seated player at game start): `seat=N,pub=<64hex>`. A `sit`
  WITHOUT `pub=`, from the seat's own key, is a return from sit-out.
- `handStart` (host): `seats=1|2|..,button=B`, at least two seats, strictly
  ascending, the button among them. `dealLevel` (host):
  `level=0,dealer=<seat>,count=N` (the dealer is the button seat's player; `count` is
  the number of dealt seats); the oracle's form is `level=1,dealer=0` (7.2).
- `seedCommit` / `seedSeal` / `seedReveal`: `pos=<seat>` plus payload from the seat's
  own key. `holeDeliver` (dealer): `seat=N,sealed=<hex>`, the two card names sealed to
  seat N's session box pub. `board` (dealer): `street=..,cards=a|b|c`.
- `settle` (host): the deltas, verified by every client against its own `heSettleOf`
  before folding (8.3).
- `ckpt`: `street=<deal|flop|turn|river|showdown>,head=<64hex>,sig=<128hex>`, a
  signature over `"HOLDEM-CKPT-v1|<head>"` for the head the boundary's TRANSITION wire
  produced (the last holeDeliver for "deal", the street's board wire, the wire that
  closed the betting for "showdown"). A verified ckpt naming a different head is fork
  evidence, never agreement.
- `show` / `muck`: `seat=N` from the seat's own key, after the verified settle.
  **Display only by construction:** online ranks derive from the REVEALED seeds, never
  from claims. Policy: contested non-losers show, contested losers muck, uncontested
  winners muck, earlier folds emit nothing. Only shown seats' cards paint; History
  annotates "(mucked)"; the audit is untouched.
- `shuffleStep`: `pos=<P>,ck=<64hex|empty>,deck=<52 x 64hex "|"-joined>`; `ck` is the
  DLEQ commitment key `k_P * B`, required under a `dleq=1` config.
  `unmaskStep`: `pos=<P>,slot=<S>,val=<64hex>,proof=<192hex|empty>`, `slot` the deck
  position 1..52, `proof` the 7.4 field.
- A **timeout** is not a new type: the HOST authors the existing `act` wire with
  `verb=<check|fold>,amount=0,seat=<N>,timeout=1,bank=<1|0>` (or a `bid*` wire with
  `amount=,seat=,timeout=1,bank=` for a pending forced post), folded as seat N's action
  once every client has verified it (section 9).

## 7. The deal protocol ladder

The deal is the only part of poker that is cryptographically interesting; everything
else is bookkeeping over the transcript. The table config pins the level; all levels
share the transcript, betting engine and settlement.

### 7.1 Level 0 - rotating host deal (friendly tables)

1. Every player broadcasts `seedCommit` = `sxHash("HOLDEM-SEEDC-v1|" || seed_i)`.
   `seed_i` is DERIVED, not drawn: `sxHash("HOLDEM-SEEDP-v1|" || idSeed || "|" ||
   table || "|" || hand)`, secret-keyed by the player's identity seed, fresh per hand,
   and deterministic, so a client that crashes and rejoins mid-hand re-derives the
   seed it committed and can still seal and reveal.
2. Every player sends `seed_i` to the current dealer in a sealed box, carried ON the
   chain as `seedSeal`.
3. The shuffle is a Fisher-Yates draw from a keyed stream: `streamKey =
   sxHash("HOLDEM-SHUF-v1|" || table || "|" || decimal(hand) || "|" || seed_1 XOR ...
   XOR seed_N)`; stream block j = `sxHash(streamKey || uint32be(j))`; draws are 4-byte
   big-endian words, rejection-sampled (no modulo bias). The dealer **cannot stack the
   deck**: their own seed was committed before they saw anyone else's. That holds only
   while "every commitment is in" means one canonical commitment per position of THIS
   hand (section 6's index and hand rules; before v0.25.5 a dealer's aliased
   commitments could satisfy it).
4. The dealer sends each player's two hole cards in a sealed box (`holeDeliver`);
   board cards are broadcast at each street.
5. At hand end everyone broadcasts `seedReveal`; every client recomputes the shuffle and
   audits the whole deal (`audit` carries pass/fail and the failing step).

Defeats: T0 entirely, T1 stacking/forgery, T2 stacking. Accepts: the dealer *sees* all
cards that hand (rotate the deal every hand), and the audit reveals mucked cards after
the hand (a visible house rule). **This level exists to get a playable game early and to
soak-test the transcript; it is not the value-ready level.** In hotseat one node holds
every seed, so a hotseat deal is tamper-evident, not unstackable.

### 7.2 Level 1 - deck oracle (non-playing dealer)

Level 0's protocol with the dealer role taken by a party with no stake: the lobby's
**"Host: ORACLE"** mode of the same stack, the HOST ROLE minus the seat, bound at Create
and reachable over either transport (as a v3 onion service it needs no port forwarding).

- `level=1` in the signed table config IS the oracle marker; `dealLevel` carries
  `level=1,dealer=0`. A client without Level 1 refuses the hand readably ("unsupported
  deal level 1") instead of mis-folding.
- **The oracle contributes its own committed seed** at position dealCount+1, committed
  before it saw anyone's, so it cannot stack and no player's entropy stands alone. It
  reveals that seed at hand end and files its audit verdict as "oracle". It holds no
  cards, banks no stack, and signs **no settlement receipt** (receipts stay the seats'
  multi-signature, 8.3). Hole delivery is the ordinary sealed path authored by the
  oracle key; players' `seedSeal`s seal to the oracle's session box.
- The oracle IS the relay host, so it sees the public, signed betting wires. What
  Level 1 buys is the no-stake property (the peeker holds no cards and no chips). A
  betting-blind daemon splitting relay from dealer was declined: D-21 (2026-08-27).
- An onion oracle derives its service seed under its **own domain tag**,
  `"HOLDEM-ORACLE-v1|"` (pinned as oracle_service_seed vs onion_service_seed), so its
  address never collides with the same host's playing table.
- **Oracle loss is host loss** (section 9); the oracle, never seated, is never
  electable.

Collusion oracle-with-player remains (T3); that is why Level 2 exists.

### 7.3 Level 2 - ristretto255 mental poker (the value-candidate deal)

No dealer at all: nobody, player, host or oracle, learns any card they are not entitled
to, at any point. Built on one primitive: commutative masking by scalar multiplication
on the ristretto255 group, through SodiumXT's `sxRistretto*` surface.

**Setup (public, once):** the base deck is 52 points `P_c =
sxRistrettoFromHash(sxHash("HOLDEM-L2-CARD-v1|" || cardName, 64))`, e.g.
`"HOLDEM-L2-CARD-v1|Qs"`. Hash-to-group means no party knows any discrete-log relation
between two card points; the construction leans on that.

**Shuffle-mask round (per hand):** in seat order, each player takes the incoming deck
(the base deck for the first), multiplies **every** point by one fresh secret scalar
`k_i`, applies one fresh secret permutation `sigma_i`, and broadcasts the result as
`shuffleStep` (52 x 32 = 1664 bytes; every intermediate deck stays in the transcript,
signed). After N players, `D = perm(k_1 k_2 ... k_N * base)` is on the table and nobody
knows the composite permutation or can strip the composite mask alone. Unlinkability is
DDH on ristretto255; recovering a mask is CDH. **Free integrity check:** duplicated
positions are *publicly visible* (identical points), so every client asserts all 52
points of every `shuffleStep` are distinct: duplication is prevented, not detected.

**Dealing.** Card positions are consumed in a fixed public order (hole cards by seat,
then burn/flop/turn/river as in a live game).

- *Public card at position j*: an unmask chain in seat order. Player 1 broadcasts
  `unmaskStep` = `k_1^{-1} * D[j]`, player 2 applies `k_2^{-1}` to that, and so on; the
  final value must equal some base point `P_c`, which is the card. A final value outside
  the 52-point table is proof of a wrong step somewhere (the void-and-audit rule below).
- *Hole card for player A at position j*: the same chain, but A goes **last** and does
  not broadcast the final step. The public penultimate value `V = k_A * P_c` is useless
  to everyone but A (CDH); A strips `k_A` privately. The transcript stays fully public.

**Showdown (reveal-scalar):** a player who wants the pot broadcasts `show` carrying
`(k_A, sigma_A)`. Every client then re-verifies everything A did this hand: the shuffle
step recomputes exactly, every unmask step recomputes exactly, and A's hole cards fall
out of `V * k_A^{-1}`. No zero-knowledge proofs, no extra rounds.

Scalars and permutations are **per-hand**, so revealing them exposes no other hand and
nobody else's cards. **Mucking still works**: declining to reveal forfeits any pot
claim; unverified is not cheated, since the duplicate check and the garbage-card rule
still bound what the player could have done.

**Void-and-audit rule (the T1/T4 backstop):** if any unmask chain ends outside the card
table, or any player times out mid-deal, the hand is **void**: all bets return, and the
table runs a full audit, every player revealing that hand's `(k_i, sigma_i)` (the hand is
void, so the reveal costs nothing). The audit recomputes every signed step and **names
the signer of the first bad one**. Refusing the audit makes the refuser the named party;
a config-set forfeit on top of that is specified, not built (section 6). Repeated voids
are themselves evidence.

Defeats: T0-T2 entirely at the card layer (nobody peeks, nobody stacks, everything
attributable). Accepts: T3, and selective abort costs a void hand before the cheater is
named.

**Cost and pace.** A shuffle round is 52 scalar mults + 1 permutation per player, deal
time only (on ABI 9 one `sxRistrettoScalarMultBatch`: 4 FFI crossings per step against
the per-point loop's ~312), N sequential steps per hand. **Unmask chains batch per
tick, normatively:** a player owing chain steps applies their scalar to EVERY pending
position and answers with ONE rp1 message, so the pipeline depth is N hops, not N per
card: the hole deal takes ~N ticks and each street ~N more, about 6 s each at 6-max over
rp1. Dealing card by card (over a minute at 6-max) is a spec violation.

**Implementation contract** (pinned in `tools/protocol-kat.py` against its independent
RFC 9496 reference):

- Every seam is lowercase hex text: a deck is a 52-item comma list of 64-hex points;
  sigma a 52-item comma list with `out[j] = k * in[sigma[j]]`; an unmask chain a comma
  list whose first item is the masked table point, then one seat's value per item (a
  hole chain carries only the public part).
- Void conditions are DISTINCT strings, never throws: `scalar-format`, `point-format`,
  `invalid-point`, `identity-point`, `deck-size`, `perm-size`, `perm-format`,
  `duplicate-point`, `chain-short`, `final-not-in-table`, `hole-not-in-table`,
  `shuffle-mismatch`, `unmask-mismatch`, `scalar-zero` (position-tagged where one
  exists). libsodium reports invalid-point and identity-result as ONE failure, so the
  validity predicate runs first.
- sigma's distinctness is NOT validated by the masker (the duplicate check refuses a
  repeated index publicly). Verification IS the doer re-run: the showdown re-check
  calls the handler that built the step.

**The void-and-audit machine** (`heL2Void*`, pure and transport-agnostic):

- It consumes the deduped, host-sequenced stream. An identical re-post of the last
  applied record is a harmless `dup`; a DIFFERENT step for a filled position is named
  equivocation (`void:step-equivocation`).
- **Attribution is two-tier.** A publicly refusable record (bad format or encoding,
  duplicate deck, order violation, a bad or missing DLEQ proof) voids with its signer
  named at once; a chain completing OUTSIDE the card table voids with attribution
  DEFERRED (`named=audit`), since only the full reveal can say whose step lied.
- **The audit order is fixed**: per contributor 1..N, the reveal present, then the ck
  binding when a commitment key was posted, then the shuffle step re-verified from
  (k, sigma); then every opened chain in slot order, each step in chain order. The
  FIRST bad signed step names the cheater. A deal-phase timeout names the staller
  PROVISIONALLY; the name stands only if everything signed re-verifies. Reveals travel
  one line per contributor: `<pos> TAB <kHex> TAB <sigma comma-list>`.
- **The outcome line is pinned**: `void|<why>|named=<pos|audit>|bets-return|
  reveal-required`. A config-signed forfeit would apply above this layer (specified,
  not built; section 6).
- Hole-slot owners are declared by the ORCHESTRATOR at machine creation (the deal
  layout is public and fixed), never by a record.

As built, the machine, the bots and DLEQ are complete; **Level 2 is not yet wired into
played hands** (the dealLevel gate refuses anything but 0 and 1).

### 7.4 The ceiling above Level 2 (DLEQ built; Bayer-Groth documented, not built)

**Bayer-Groth verifiable shuffles** (proof a shuffle step permutes its input) are a
research project, not built. **Chaum-Pedersen DLEQ proofs** per unmask step (wrong steps
become impossible rather than attributable) are the first hardening pass, and built:

- **The binding is a per-hand commitment key.** A shuffle step cannot be DLEQ'd
  directly (the permutation hides which output matches which input), so each
  `shuffleStep` carries `ck = k*B`, and every unmask step proves the SAME k against it:
  statement `P2 = k*P1` over (B, ck, P1, P2), an unmask step proving (k, stepOut,
  stepIn) since `out = k^-1 * in <=> in = k * out`. A garbage ck still ends attributable
  through the audit, where the binding check runs first.
- **Derandomized nonce** (the RFC 6979 / EdDSA pattern): `w =
  reduce(H32("HOLDEM-L2-DLEQW-v1|" || k || "|" || p1 || "|" || p2))`; challenge `c =
  reduce(H32("HOLDEM-L2-DLEQ-v1|" || ck || "|" || p1 || "|" || p2 || "|" || a1 || "|"
  || a2))` over LOWERCASED hex; response `z = w + c*k mod L`; `proof = a1 || a2 || z`
  (96 bytes). `reduce()` is ScalarAdd-zero, applied before any point multiplication, so
  libsodium's bit-255 masking and the reference's mod-L arithmetic never see different
  scalars; a NON-CANONICAL z in a received proof is refused, never reduced.
- **Verification** checks `z*B == a1 + c*ck` and `z*P1 == a2 + c*P2`, named
  distinctly; `c*ck` and `c*P2` ride ONE batch crossing.
- **Under `dleq=1`** the machine REQUIRES ck and proof (missing is a named refusal) and
  verifies each proof before applying the step: a wrong unmask is refused instantly
  with direct attribution. A staller can still force a void.
- **Soundness is pinned negatively**: a wrong secret, swapped points, a tampered
  commitment, and the honest procedure run over a FALSE statement all verify false, in
  protocol-kat and in the harness.

## 8. Game engine

### 8.1 Betting engine

Deterministic no-limit hold'em over the transcript. The rules the implementation pins:

- Button and blinds rotate by seat order; heads-up, the button is the small blind and
  acts first pre-flop, last post-flop. **Dead button:** the big blind always advances to
  the next live seat, so an elimination never double- or skip-charges a blind.
- Min-raise = the largest prior bet/raise of the street. An all-in below the min-raise
  does **not** reopen betting for players who already acted, **per wager**: several
  short all-ins that only cumulatively amount to a full raise still do not reopen (TDA's
  cumulative reading is stricter; changing it is a deliberate, spec-first change).
- Side pots: layered by all-in amounts, each layer awarded independently. Split-pot odd
  chips go to the first winning seat clockwise from the button; a short all-in big blind
  still sets the full `bb` to call. Antes are dead money (into the pot, never the street
  bet).
- Showdown order: the last aggressor of the final street first, then clockwise; players
  may muck in turn (Level 2: muck = don't reveal scalars).
- **Timers** (lengths from the signed config): an act timer with one time-bank per
  hand, and a deal-phase timer for Level 2 chains; expiry is check/fold in betting,
  void-and-audit in dealing. The host-countersigned turn-opening wire starts every
  clock; expiry is the host's signed timeout wire (section 6). The bank AUTO-ARMS on a
  seat's first would-be timeout each hand and its spend rides the wire (`bank=1`), so
  bank state is consensus. Forced posts time out the same way once the deal completes;
  an L0 deal stall deliberately has NO timeout prescription. Bank spend and miss count
  move only when the engine APPLIED the timeout; a refused timeout re-arms.

### 8.2 Hand evaluator

Pure xTalk: best 5 of 7, full ranking with kickers, split detection, pinned before any
UI existed. Known-answer vectors: royal/straight/wheel (A-2-3-4-5) flushes, quads with
kicker, boat over boat, flush vs straight, board-plays-both (split), three-way splits
with side pots, the A-K-Q-J-9 "almost straight". Properties (fixed seeds): the result
never depends on input order, and (handA vs handB) is antisymmetric.

### 8.3 Settlement receipts

At hand end the HOST emits `settle` carrying the deltas, and every client verifies it
against its own `heSettleOf(transcript[hand])` recomputation before folding it. Then:

- `settleHash = H("HOLDEM-SETL-v1|" || deltas || "|" || chainHead)`
  (`heSettleHashHex`).
- `receiptHead = H("HOLDEM-RCPT-v1|" || settleHash || "|" || prevReceipt)`, the
  genesis `prevReceipt` being 64 zeros, so receipts hash-chain hand to hand.
- Each SEATED player signs `"HOLDEM-RSIG-v1|<receiptHead>"` and emits `receipt
  head=,sig=`; the oracle signs none. The signatures form the **settlement receipt**: a
  countersigned ledger no subset of players can rewrite.

Play-money BEP44 standings derived from receipts are specified, not built. **A future
value layer must consume receipts and nothing but receipts** (section 13).

## 9. Liveness, disconnects, and aborts

- **Reconnect**: rejoin with the table code, receive the transcript, fold it, resume.
  Hole cards need no re-delivery (L0/L1: the sealed `holeDeliver` is ON the chain and
  the seed re-derives, 7.1 step 1; L2: the chain values are in the transcript). The
  host prefixes a replay with an unsigned `r!` frame carrying its head seq (honored only
  from the host's live handle); the client suspends its emissions until its applied seq
  reaches the mark, then reacts once. A lost marker degrades to noise, never a wedge.
- **Mid-stream gap recovery**: rp1 is lossy, reordering and REDELIVERING. A verified
  wire is classified by its host `seq` against the last seq applied, never by a bare
  `prev`-vs-head test: at or below it, a duplicate, dropped silently; exactly next,
  chained and applied; further ahead, held in a bounded reorder buffer while an unsigned
  `s?` goes to the host (debounced to ~once per 2 s, honored only from an admitted,
  connected peer, rate-limited). `s?` carries the applied seq and the host TRIMS the
  replay to the wires past it; a bare `s?` and the reconnect handshake get the full log.
  The mark is only a trim hint: dedup keeps a replay safe; a lie only starves the liar.
- **Timeout in betting**: the HOST's signed timeout wire (section 6), verified by every
  client: host authority, the exact check-or-fold prescription (never fold a seat that
  could check), the transcript-derived bank state, and the deadline passed on the
  CLIENT's own clock within 5 s of jitter (not the +-600 s window: no timestamp crosses
  the wire), waived for a historical wire and for a turn whose clock started during a
  catch-up replay. `miss=` consecutive timeouts, or the seat's own `stand`, sit it out:
  dealt out at the next boundary, mid-hand turns timing out instantly (a pending blind
  included), back next hand on its own `sit` (no `pub=`). A table with fewer than 2 live
  seats but 2+ chip-holding seats WAITS. Late-join rides the same boundary: a present
  joiner takes the lowest empty seat with the cfg opening stack, or observes when full.
- **Timeout in dealing** (L2): void-and-audit (7.3); an aborter never sees the flop
  and is the named party (a config forfeit rule is specified, not built; section 6).
- **Host loss**: a wire-silence watchdog (no host-countersigned wire for 60 s during
  play; the onion transport also routes positive stream death here). No calling round:
  the successor is the lowest pubkey among live SEATED players holding chips, not the
  lost host and **not sitting out**, so every client names it independently
  (`heNetElectablePubs` decides the candidates, `heElectHostOf` only sorts; pinned as
  elected_host and elected_host_sitout). Sit-out may gate the election because it is
  transcript-derived; per-client observation (a live handle, a last-heard stamp) may
  gate SEATING but never an election. The in-flight hand voids and stacks stand at the
  last receipt (free at L0). Until the live handover is proven, the client fails
  closed with the successor named. On the ONION transport, host-stream death first
  arms a bounded AUTO-REDIAL (4 attempts, 2/4/8/16 s backoff, 10 s per dial; the
  deterministic address means the same invite redials) while the watchdog keeps
  counting. Every redial step gates on the election; a dial failure mid-redial
  re-arms rather than tearing the transport down; both exits leave the successor named.
  A redial's hello names the applied seq, so the replay arrives trimmed; a host-signed
  wire applying resets the attempt counter.

## 10. Transport profile

- One rp1 payload = one envelope, no fragmentation (the largest is the 1664-byte
  `shuffleStep`; the cap is 60000). rp1's ~1 s tick is the BUDGET, not the goal; UPnP is
  never required. One `btRp1Poll` drain per 250 ms tick; **never** per-frame work.
- Table lifecycle: create = random table id -> `btAddInfohash` of the section 6
  info-hash + announce; join = the same from the code; leave = part + remove torrent.
  The DHT carries **zero game data**, rendezvous only.
- **Onion tables** (identical envelopes over OnionXT streams):
  - The invite is `<64hex-table>@<56base32>.onion`: one word, deliberately non-hex, so a
    client without onion support refuses it readably (downgrade refusal by format). An
    onion invite without working OnionXT is refused outright; there is no fallback
    transport either way.
  - Service seed = `sxHash("HOLDEM-ONION-v1|" || idSeed || "|" || tableId)`,
    secret-keyed and re-derivable, so a restarted host republishes the same address,
    computed offline at create (`sxSignKeypairFromSeed` -> `oxAddressFromPublicKey`;
    SodiumXT ABI 7's SHA3) and cross-checked against `oxServiceAddress` at publish.
  - One LF-terminated frame per `oxWrite` (safe: every free-text field is hex),
    reassembled per stream on the poll tick and fed to the rp1 router.
  - The admission token rides the stream's first line (the `h` frame, beside
    `c`/`w`/`r!`/`s?`); the host answers a verified hello with its own *before* the
    replay; an unverified hello earns nothing.
  - Onion tables touch no DHT. Tor is assumed on SOCKS 9050 / control 9051, probed
    fail-closed through watchdogged states on a lobby status line.
- **Direct-TCP upgrade** (optional, unbuilt): pairwise `btMapPort` + engine sockets for
  sub-100 ms action UX; protocol-equivalent, falling back to rp1 silently.

## 11. Presentation (the Box2Dxt part)

Hotseat-first. Gotcha numbers cite `CLAUDE.md`'s carried list.

**Built:** self-building chrome in a dependency-free flat mode and a Kit mode (atlas
loading, pre-warm, gated frame loop); Kenney CC0 card faces and backs via
`b2kSheetLoadAtlas` (`b2kSheetScale` if families mix, gotcha 24); pooled card slots
swapped with `b2kSpriteSetFrame`; `b2kSheetEnsureIcon` at build for every face (a
~250 ms lazy slice on the river is the one unforgivable jank); procedural chips (the
Kenney pack has none); HUD on change only, at most 4 Hz; timer-driven dealing pace.

**Specified, not built** (no `b2kSpritePlay`, `b2kFrameTarget`, `b2kForce` or chip body
exists in the stack): **deal** slides (`b2kSpriteMoveTo` from the shoe, ~70 ms stagger);
**flips** by the squash trick (sprites do not rotate, gotcha 23): one-shot
`b2kSpritePlay` back->edge, swap the face in the game's own finish receiver, play
edge->flat, the receiver registered by `b2kFrameTarget me` once and
`b2kSpriteOnFinish tSpr, "heCardFlipDone"` per sprite (the Kit's SETTER; gotchas 19 and
27); **chips** as graphic bodies tossed with one `b2kForce` write, left to sleep
(gotcha 17), and a `b2kSpriteMoveTo` pot-push.

## 12. Test plan

1. **Evaluator vectors** (8.2): pure, offline, first code written.
2. **Protocol KATs**: fixed seeds/scalars -> pinned decks, chains and receipts, in CI
   (`tools/protocol-kat.py`).
3. **Transcript replay determinism**: a canned session replays to identical state and
   receipts on every platform, bit-exact.
4. **Adversarial harness**: scripted cheater bots (deck-stacker vs L0, wrong-scalar
   unmask, duplicate-point shuffle, rollback replayer, timeout staller), each
   *detected and correctly attributed*, the honest table settling or voiding exactly
   per config. All five are pure drivers over the 7.3 machine in harness section 19
   (`heTestLevel2VoidRun`), every verdict pinned twice (protocol-kat's l2v_/l0_ keys
   and the harness); the wrong-scalar bot runs without DLEQ (the audit names its step)
   and under `dleq=1` (refused instantly).
5. **On-engine OXT rounds** for everything visual and timed (the harness cannot see
   jank).

## 13. Value-readiness (read before attaching money)

This spec makes the *game* value-ready; it does not make a *product* value-ready:

- **What Level 2 + receipts guarantee**: nobody saw a card they should not have; the
  deal was unstackable; every action is signed and ordered; the ledger is the
  countersigned receipt chain; disputes reduce to "replay the transcript".
- **What they cannot guarantee**: no collusion, no bots, no compromised endpoints, and
  no protection from the operator-of-record's legal exposure. Real-money play is a
  regulated activity in most jurisdictions: licensing, KYC/AML, age verification,
  responsible-gaming duties. Those are prerequisites, not features, and they are out of
  scope here **deliberately**, so that no one mistakes this spec for them.
- **The interface**: a value layer consumes settlement receipts (8.3), countersigned,
  hash-chained and replay-verifiable, and must treat anything less (a claimed balance,
  an unsigned delta) as void. If CoinXT is ever wired in, it plugs in there, and the
  deal level MUST be 2 with DLEQ hardening (7.4) shipped first.
- **Sequencing rule**: value attaches only after the adversarial harness (12.4) passes
  attribution on every scripted attack, and after a hostile review of the deal
  implementation by someone who did not write it.

## 14. Prerequisite work items, per repo

All delivered. SodiumXT supplied the ristretto255 surface on 2026-08-15: ABI 8
(`sxRistrettoFromHash`, `sxRistrettoScalarMultPoint`, `sxRistrettoScalarRandom`,
`sxRistrettoScalarInvert`, `sxRistrettoPointValid`; `sxHash(x, 64)` is the 64-byte hash)
and ABI 9 (add/sub, `sxRistrettoScalarMultBase`, `sxRistrettoScalarMultBatch`, scalar
add/mul). TorrentXT, OnionXT and Box2Dxt needed nothing beyond what they ship.

## 15. Milestones

M0 hotseat, M1 friendly online (Level 0, onion tables), M2 oracle (Level 1, host
election), M3 mental poker (Level 2 and the 12.4 harness), M4 hardening (DLEQ, batch
mult, hostile review, soak). Only after M4 does section 13's sequencing rule begin to
apply. `README.md`'s phase table records what is built and what each exit still owes.

## 16. Security checklist (implementation laws, SodiumXT-doc style)

- Compare secrets and MACs with `sxMemEqual`, never `is` / `=`.
- Compare every PUBLIC hex value (a digest, commitment, head, key, signature or table id)
  with `heHexEq`, never bare `is` / `=`: two number-like texts compare as numbers, so two
  that overflow a double are equal (the suite's engine note 2.11; v0.25.4).
- Read every wire index (position, seat, count, hand, seq) through `heCanonIdx`, key
  by what it returns, and COUNT by walking the range, never per message: `"03"` is
  the number 3 to `is` and a different array key (section 6; v0.25.5).
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
