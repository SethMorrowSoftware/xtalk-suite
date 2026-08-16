# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this
repository. Read it before touching anything; it carries everything already learned the
hard way across the sibling repos so it never has to be re-learned here.

> **Folded into the monorepo 2026-08-15.** This directory was copied verbatim (via
> `git archive`, tracked files only) from the standalone `hold-em` repository, which
> becomes a mirror; development happens here now, like every other member. Prose and
> paths below may still say "this repo" or read as if this directory were its own
> repo root (the suite's standing consolidation-debt caveat). The seed
> docs the suite had carried at `docs/holde-em/` (stale at pre-implementation while
> this repo reached v0.18.0) were REMOVED in the fold - this directory is the one
> authority. What the fold changed, each per suite law:
>
> - `tools/check-livecodescript.py` was REPLACED with the suite's unified checker,
>   registered in `tools/check-checker-drift.py` and fixture-tested by
>   `tools/test-checker.py` - never edit it here alone. First contact found TWO real
>   engine traps this repo's own lineage could not see, both in the Level 0 deal
>   path: `heXorSeedsHex` walked its hex pairs with `repeat with ... step 2` (OXT
>   ignores the increment - it would have XORed 63 OVERLAPPING pairs and derived a
>   wrong-but-internally-consistent deck), and `heDeckFromStreamKey` re-threw from
>   inside a `catch` (the throw never reaches the caller on OXT). Both are rewritten;
>   both handlers are re-labelled "verified statically; needs an OXT re-pass", and
>   whether the PREVIOUS on-engine Level 0 runs dealt from the stepped or the
>   1-stepped stream is exactly what that re-pass should establish (the Python KAT
>   mirrors pin the 2-stepped semantics).
> - The hold-em lineage checker survived the fold as `tools/check-holdem-idioms.py`,
>   because eight of its checks had no unified-checker counterpart and every one had
>   shipped-defect provenance here. The recorded follow-up - porting those checks
>   INTO the unified checker and retiring the file - was KEPT on 2026-08-15, the
>   same day: the unified `check-livecodescript.py` now carries them as its checks
>   13-21 (fixture-tested in every member copy), and the file is gone. Two ports
>   were honestly NARROWED by fleet engine evidence, and one was refused: the
>   bitwise refusal gates only the function-call form `bitXor(a, b)` (the operator
>   form stands in engine-passed code in four members - H7's blanket ban stays THIS
>   member's prose law); the catch-variable check fires only when the catch body
>   REFERENCES the undeclared variable (onionxt's probes fired the unreferenced
>   form green on-engine); and the chunk-of-array-element refusal (H6) was NOT
>   ported at all - riptide/onionxt/box2dxt/nocloud chunk array elements in
>   engine-passed code, so H6 stays this member's prose law too, with the
>   reasoning recorded in the unified checker's docstring.
> - All ten pure-logic gates (the idiom checker, `check-docs.py`, the seven KATs,
>   `logic-fuzz.py`) are wired into the suite's `tools/build-all.sh --gates`, which
>   CI runs on every push; this member's own `.github/workflows/ci.yml` stays for
>   standalone work but is inert here (GitHub runs only root workflows).
> - `src/holdem.livecodescript` is EXEMPT in the suite's `tools/check-ui-kit-drift.py`
>   ("game table on the b2k Kit; suite-kit chrome is phase-2" - the box2dxt games'
>   reasoning). Registering it exposed a latent suite-gate bug the fold fixed: the
>   gate's window-building regex ended in a literal backspace byte, so the
>   width/height spelling had never matched; the rect spelling this stack uses was
>   also unknown to it (and to `tools/check-stack-size.py`, which now parses it).
> - The stack SHIPPED at 1024x690 - 50px over the suite's 720p height budget, with
>   the status line and quick-bet row genuinely below y=640 - and carried a written
>   SKIP in `tools/check-stack-size.py` until the recorded follow-up landed. **The
>   720p re-layout landed at v0.23.0 (2026-08-16)**: 1024x640, the felt's vertical
>   rhythm tightened (felt 48..524, board centre 300 -> 286, the pot line moved
>   below the board, the seat ring pulled in) and the slider/action/status rows
>   pulled inside the fold. The SKIP entry is GONE - the gate holds this stack to
>   the budget like everyone else. Verified statically BY ARITHMETIC (every control
>   rect re-derived from the constants: all within 1024x640, non-layered chrome
>   pairwise disjoint, the designed layers named); the confirming EYE - nothing
>   clipped, the felt still reads - is the OXT pass's.
> - The `he*` prefix is registered in `tools/check-handler-calls.py`, which also
>   learned to strip `/* */` block comments (this file's header changelog leaked
>   prose into its candidate set - and 31 phantom "definitions" out of it, suite-wide).
> - Registered in the `start-here.livecodescript` launcher. NOT folded into the
>   generated suite selftest or its coverage gate: this member's harness lives
>   EMBEDDED in the game stack (`heRunSelftest`), not as a separate foldable file -
>   extracting it (or teaching the fold machinery an embedded harness) is recorded
>   follow-up, the box2dxt precedent.
>
> Where this file and the suite root `CLAUDE.md` conflict, this file wins inside
> `holde-em/`; paths in the docs below may still read as if this were its own repo
> root (the suite's standing consolidation-debt caveat).

## What this is

**holde-em** is a serverless online no-limit Texas Hold'em game for **OpenXTalk (OXT)**
and the wider **xTalk** family (also compatible with **LiveCode 9.6.3+**). It is a
pure-script project: **no native code lives in this repo**. It composes four sibling
extensions, each of which wraps its own native library behind a friendly xTalk surface:

```
your table stack (this repo)                 src/holdem.livecodescript
   |- game logic: transcript, deal ladder, betting, evaluator = pure xTalk, here
   |- bt*   TorrentXT   org.openxtalk.library.torrent    rp1 messaging, DHT rendezvous, BEP44
   |- sx*   SodiumXT    org.openxtalk.library.sodium     identity, sealing, hashing, randomness
   |- ox*   OnionXT     (script library + local tor)     onion tables, oracle hosting  [optional]
   |- b2k*  Box2Dxt Kit org.openxtalk.box2dxt            card sprites, chip physics, frame loop
```

The three documents that govern this repo:

- **`holdem-spec.md`** — the design contract (deal protocol ladder, transcript, threat
  model, settlement receipts). Where code differs from the spec, the code wins and the
  spec gets updated.
- **`IMPLEMENTATION-PLAN.md`** — the phased build order with exit criteria per phase.
- **This file** — how to work here without getting bitten by OXT.

**Status: Phase 2 online play (2d) + onion tables (2f) + the WHOLE 2e liveness
layer (street ckpt wires, show/muck, online History folding, host election -- and,
since v0.23.0, act timers + time-bank, sit-out/return, late-join, onion
auto-redial) + the Phase 3 deck oracle written, on Phase 1 hotseat, plus the Phase
4a-4d Level 2 layer (compute + void-and-audit sequencing), the 4e adversarial
bots, and Phase 5's DLEQ proofs on SodiumXT ABI 9 (all pure; nothing plays on
Level 2 yet), at v0.24.0 -- v0.23.0 brought the table inside the suite's 720p
budget (1024x640; the check-stack-size SKIP is gone) and v0.24.0 corrected ten
reviewed defects in that liveness layer with NO wire change (the liveness
contracts block below carries each one). The pending live gates: a
TIMED multi-hand session on wall clocks (seats timing out for real), a multi-hand
onion table session on two machines with running tor (2f, + a real host-stream
loss -> redial), and the Phase 3 THREE-MACHINE oracle round (two players + a
non-playing oracle, killed mid-hand and recovered per spec 9; + live tor for an
onion-hosted oracle); the sx* DLEQ calls have never run on an engine, and the
re-layout's confirming eye is the OXT pass's.** The project was seeded from Box2Dxt's `docs/holde-em/` folder, built out in
its own repository, and folded home into the suite 2026-08-15 (the blockquote above).
README.md's Status section is the current authority; IMPLEMENTATION-PLAN.md carries the
per-phase ledger.

**Because chips may someday carry real value**, the security posture is not optional
polish: read spec sections 2 (threat model), 13 (value-readiness), and 16 (security
checklist) before writing any protocol code, and follow section 16 as law.

## The three layers of the platform (for a fresh Claude)

1. **`.livecodescript` (LiveCodeScript / xTalk)** — everything in this repo. An
   English-like, message-path language: handlers are `on ...`/`command ...`/
   `function ...` closed by `end <name>`; commands report through `the result`,
   functions return values; controls carry **custom properties** (a per-object text
   datastore); timers are `send <msg> to <obj> in <ms> milliseconds`; TCP is available
   through engine sockets (`open socket`, `accept connections`). There is **no headless
   way to compile or run it** — the IDE is a GUI runtime. Development therefore leans on
   static gates (below) plus a human "OXT pass".
2. **LCB (LiveCode Builder)** — the extension language the *siblings* are written in:
   `foreign handler` declarations bind a flat C ABI, packaged as installable extensions;
   the engine resolves each extension's bundled native library via
   `the revLibraryMapping` automatically (no loose libraries, no `LD_LIBRARY_PATH`).
   **This repo writes no LCB** — it only calls the public handlers the installed
   extensions put on the message path.
3. **The C shims / native libraries** — libtorrent-rasterbar, libsodium, Box2D, wrapped
   by their repos behind frozen, versioned C ABIs (`btx_*`, `b2lc_*` symbol prefixes).
   Family conventions you will see reflected in every API: ids cross the FFI as
   **positive int handles** (0 = invalid; stale handles are harmless no-ops, never
   crashes), reals as `double`, booleans as `int`, and **all inbound events arrive
   through poll-drained queues** dispatched on the message path — no callback ever runs
   script from a foreign thread.

## Commands

**Static verification** (the only automated gate that exists for xTalk; run after
**every** `.livecodescript` edit, and in CI):

```sh
python3 tools/check-livecodescript.py   # the suite's UNIFIED checker (drift-gated copy)
```

Since the 2026-08-15 fold, `check-livecodescript.py` is the suite's unified gate
(ASCII, balance incl. switch/try, constants-before-use, token-shadow, zero-arg
statement calls, repeat-step and throw-in-catch refusals, the per-dialect
antipattern sets - and, since the same-day checker union, the hold-em lineage
checks 13-21: bitwise-as-function, engine-token declared names, referenced
undeclared catch variables, command-with-parens, dynamic property names,
message-box prose, never-declared k-constants, dangling else, stray backslash) -
byte-identical in every member and held so by the suite's checker-drift gate:
never edit the copy here alone. The old lineage checker
(`check-holdem-idioms.py`) is retired; its two checks the fleet's engine
evidence would not support fleet-wide (H6's chunk-of-array refusal, H7's
blanket bitwise ban) remain THIS member's prose law, below. Exit non-zero on
any failure.

**Pure-logic pinning** (Phase 1+): the evaluator vectors, betting-engine cases, and
protocol KATs run headless in CI because they are plain algorithms — the one part of
this project that CAN be fully machine-verified. The gates, in the order CI runs them:

```sh
python3 tools/check-livecodescript.py   # dialect gates, every .livecodescript
python3 tools/check-docs.py             # smart-quote scan over *.md
python3 tools/evaluator-kat.py          # spec 8.2 vectors (mirror of heEval7/heRank5)
python3 tools/betting-kat.py            # spec 8.1/8.3 cases (mirror of heBetApply/heSettleOf)
python3 tools/shuffle-kat.py            # playable integer deal (mirror of heShuffleDeck)
python3 tools/protocol-kat.py           # spec 6/7.1 crypto deal + 7.3 L2 algebra
python3 tools/sounds-kat.py             # vendored casino-audio WAVs <-> stack mapping
python3 tools/logic-fuzz.py             # INDEPENDENT-reference fuzz (rules, not the port)
```

The KATs above are *mirrors* — ported line-for-line from the xTalk so a green KAT plus a
green on-engine harness pins the two together. That proves "the port matches the engine",
not "the rules are right": a bug living in both the xTalk and its twin passes unseen.
`tools/logic-fuzz.py` closes that hole — it drives the same mirror functions but checks
them against a SECOND, independently-written evaluator and side-pot settlement (plus
whole-game invariants: chip conservation, no negative stacks, termination). It runs the
evaluator EXHAUSTIVELY (all 2,598,960 five-card hands → exactly 7462 classes) and fuzzes
settlement/games over ~90k configs with fixed seeds (~30 s; `--full` does the exhaustive
order-isomorphism, `--quick` a 5 s smoke). This is the committed backing for any
"verified sound by property tests" claim — do not make that claim without it.

The KAT vectors are also embedded in the stack's own self-test (`heRunSelftest` in the
message box), so a green harness run on-engine plus green KATs in CI pins the xTalk to
the mirrors. Keep it that way: game rules, shuffle, and settlement must live in
handlers that take values and return values, with no UI reads inside.

**The single stack.** `src/holdem.livecodescript` is one paste-and-run stack: the
hotseat game AND its self-test (`heRunSelftest`) and a SodiumXT diagnostic
(`heProbeSodium`) are folded into it. There is no second stack.

**Binary stays out of the playable path (v0.2.0, the hard-won rule).** Repeated OXT
passes threw double/binary conversion errors wherever script touched FFI-bridged
binary (SodiumXT `Data`) through the chunk/arithmetic evaluator — even after copying
the element to a local (H6). The resolution: the **playable deal uses a pure-integer
PRNG** (Park-Miller MINSTD: only `+`, `*`, `mod`, every product `< 2^53` so it is
exact in a double), seeded from `sxRandomUniform` (an *integer* result — no binary
crosses into script) when SodiumXT is present, and from engine time+`random()` as a
labelled practice fallback otherwise. Nothing in a played hand calls `sxHash`,
`sxRandomBytes`, `sxBin2Hex`, `textEncode`, or any `byte`/`byteToNum`/`numToByte`.
The cryptographic Level 0 deal (commit-reveal keyed-stream, spec 7.1) stays specced
and KAT-pinned in `tools/protocol-kat.py` as the Phase 2 / value-path target; wire it
back only behind a confirmed `heProbeSodium` (which tries each `sx*` call in its own
`try` and names any that throws).

**RESOLVED (v0.4.0) — `sxHash` needs an output-length argument.** The v0.2.0 probe
found `sxHash` threw while `sxRandomUniform`/`sxRandomBytes`/`sxBin2Hex` worked; reading
SodiumXT's real `docs/api-reference.md` (cloned into the session) showed why: the
signature is **`sxHash(pData, pOutLen)`** — the earlier code called `sxHash(data)` with
one argument, which throws. Use `sxHash(data, 32)` for BLAKE2b-256. Two other guessed
shapes were also wrong and are now corrected against the real API: **`sxSignKeypairFrom-
Seed pSeed, out rPub, out rSec`** is a *command with out-parameters* (not a function
returning an array), and hole-card delivery uses **`sxSeal(msg, recipPub)` /
`sxSealOpen(sealed, recipPub, recipSec)`**. Everything crosses as `Data`; `textEncode`
strings before hashing/signing, `textDecode(..., "ascii")` the hex helpers back to
text. The crypto seams (`heHash32`, `heHashDomHex`, `heDeriveIdentity`, `heSignDetachedD`,
`heVerifyDetached`, `heSeal`) now wrap these one place each; `heProbeSodium` exercises
the full roundtrip. Lesson: **read the sibling's `docs/api-reference.md`, do not guess
FFI signatures** — the family repos are addable to the session for exactly this (and
since the fold the siblings sit right beside this directory:
`../sodiumxt/docs/api-reference.md` and so on).

**Level 2 COMPUTE layer (v0.19.0, 2026-08-15 -- Phase 4a-4c, the pure half only).**
The ristretto255 mental-poker deal algebra (spec 7.3) is the `heL2*` section of the
stack: base points by domain-separated hash-to-group (`kHeDomainL2Card` -- the
as-built domain is `"HOLDEM-L2-CARD-v1|"`, spec 7.3 carries the decision marks), one
full shuffle-mask step (`out[j] = k * in[sigma[j]]`, doer and showdown-verifier are
the SAME handler), the free duplicate check, public/hole unmask-chain verification,
and reveal-scalar re-verification. The contracts to keep intact when touching it:
values in, values out (H5); every seam lowercase hex text (the H6 corollary -- raw
Data only ever inside sx* call expressions); every failure a DISTINCT `"void:..."`
string, never a throw (each sx* call in its own try with declared catch locals,
H4/H8), because Phase 4d's void-and-audit attribution will switch on those exact
strings -- they are pinned in `tools/protocol-kat.py` (the `l2_*` mirror twins,
re-derived by its independent RFC 9496 reference; 24 pinned values) and re-checked
on-engine by `heTestLevel2Run`, which SKIPs behind `heL2HasRistretto` (a pre-ABI-8
SodiumXT throws "can't find handler" on the first `sxRistretto*` touch; the cached
probe's catch is the detection). The `sxRistrettoScalarMultPoint` throw conflates
invalid-point and identity-result (libsodium reports one failure); the validity
predicate runs FIRST in `heL2MaskPointHex`, which is what makes the two void strings
separable -- keep that ordering. NOTHING in this layer is wired to a played hand,
the UI, or the wire: 4d-4f and all orchestration are engine-era work, and the OXT
pass owes the sx* call shapes plus the 4f deal-time budget (52 mults per shuffle
step, deal-time only, per the playbook).

**Level 2 void-and-audit + bots + DLEQ (v0.22.0, 2026-08-16 -- Phase 4d/4e +
Phase 5's proof half; verified statically -- the sx* DLEQ calls, ABI 9, have
never run on an engine).** The contracts to keep intact when touching the
heL2Void*/heL2Dleq* half of the L2 section:
  - **The record formats are PINNED consensus surface** (spec 6 as-built):
    shuffleStep `pos=,ck=,deck=` ("|"-joined points; ck = k*B, the DLEQ
    commitment key), unmaskStep `pos=,slot=,val=,proof=` (proof = spec 7.4's
    reserved field, a1||a2||z). Changing a byte of either -- or of the DLEQ
    transcript derivation -- is a consensus break: protocol-kat pins move,
    kHeHarnessV bumps, every client updates together.
  - **The machine stays pure and latched** (H5): values in, values out, the
    state array shuttled by the caller; after any void it is frozen evidence
    and every later record is ignored. The signer position comes from the
    VERIFIED envelope, never from the body (the body's pos must merely agree).
  - **Dup vs equivocation is load-bearing**: an identical re-post of the last
    applied record is a harmless "dup" (rp1 redelivers -- naming it would
    convict the innocent); only a DIFFERENT step for a filled position is
    named. Keep the transport dedup (seq) in front of the machine.
  - **Attribution tiers**: direct (named=pos) only for publicly-refusable
    records; deferred (named=audit) when only reveals can say
    (final-not-in-table). heL2VoidAudit's ORDER is normative -- ck binding,
    then shuffle re-verification per contributor, then chains in slot order --
    and a recorded staller keeps its name only when everything signed
    re-verifies (spec 7.3's "first bad one" rule).
  - **Every scalar is reduced mod L (ScalarAdd-zero) before any point mult**,
    and a non-canonical z in a received proof is refused, never reduced:
    libsodium masks bit 255 inside scalarmult while protocol-kat's reference
    reduces the full value mod L -- reducing first is the ONLY reason the two
    sides can never diverge. Do not "simplify" the reduce away.
  - **The DLEQ nonce is derandomized on purpose** (w hashes the secret + the
    whole statement under kHeDomainL2DleqW): it makes the proof pinnable from
    fixed scalars AND makes nonce reuse across different statements (which
    forfeits k) impossible by construction. Never swap it for a random w.
  - **Transcript hashes see LOWERCASED hex** (xTalk `is` is case-blind;
    hashes are not). heL2DleqVerify batches c*ck + c*P2 through ONE
    sxRistrettoScalarMultBatch crossing; z*B and z*P1 cannot join it
    (different bases).
  - heL2HasDleq is the cached ABI-9 probe (heL2HasRistretto pattern); the
    audit's ck-binding check gates on it, so a pre-ABI-9 engine still audits
    (minus the binding) instead of mis-naming. Harness section 19 SKIPs the
    DLEQ half by name below ABI 9 and still drives the machine on ABI 8.

**Onion tables (v0.20.0, 2026-08-15 -- Phase 2f).** The plan's bet paid off: 2c/2d
had already funneled every outbound payload through four netCap-seamed senders and
every inbound frame through ONE router (heNetOnMessage), so swapping the byte
transport cost one new live seam -- `heNetTxTo`, routed by `gGame["transport"]`
("rp1" | "onion") -- plus a poll-tick line-reassembly drain inbound. The envelopes,
chain, fold, and react engine changed NOT AT ALL. The contracts to keep intact when
touching the `heNetOnion*` section:
  - **All protocol work on the poll tick (H2).** The three OnionXT callbacks
    (`heOnionStatus`/`heOnionPeer`/`heOnionStreamEvt`) only STASH bytes and flags
    into gGame; `heNetOnionTick` does everything else, one state compare when idle.
    Every ox* call sits in its own try with a declared catch local (H8), and every
    silent async wait has a watchdog (the `kHeOnion*Ticks` deadlines).
  - **Fail closed, never fall back.** Assume-running tor on the stock ports (9050/
    9051; Tor Browser alone exposes no control port -- say so in the message). An
    onion invite without OnionXT refuses outright (`heJoinRefusal`, pure and
    dependency-injected so the harness drives both branches); a DHT invite never
    goes near tor. The lobby's Tor line walks the quickshare-pill states.
  - **The invite is the compatibility seam:** `<64hex>@<56base32>.onion`, one word
    and non-hex ON PURPOSE -- a pre-2f stack's `word 1` + heIsHex gate refuses it
    readably (downgrade refusal by format). The onion address derives from
    `heOnionSeedHex` (kHeDomainOnion: secret-keyed by the host identity seed,
    per-table, deterministic -- restart-stable, spec 9) and is computed OFFLINE at
    create, then cross-checked against `oxServiceAddress` at publish.
  - **The "h" hello frame is the rp1 handshake's stand-in**: the same signed
    admission token as the stream's first wire line, verify-or-drop before any
    reply; the host's answering hello precedes the replay so the ordered stream
    delivers host identity before host-signed wires. LF framing is safe because
    every free-text field is hex-encoded (one wire line per oxWrite; LF as
    `numToChar(10)`, the OnionXT byte-discipline).
  - **H1:** streams + service close on leave/stop (`heNetStop`'s onion branch);
    the control connection deliberately survives between tables and is
    `oxShutdown` on closeStack (`gOxCtlUp` remembers we opened it).
  - The 2e deferral CLOSED (v0.23.0): a lost host stream during play now arms
    the bounded AUTO-REDIAL (heNetOnionRedialArm: 4 attempts, 2/4/8/16 s
    doubling backoff, 10 s per dial -- the deterministic onion address is what
    makes redialing the same invite the recovery) while the 60 s election
    watchdog keeps counting underneath; every redial step gates on hostLost,
    so the election always concludes and the redial stands down quietly.
    Outside play the old fail-closed "Join again" message stands. The redial
    hello carries the applied seq as a compatible trailing token item, so the
    reconnect replay arrives TRIMMED (the v0.23.0 contracts block below).
  The whole section is verified statically; the live two-machine tor session is
  the exit gate (harness section 17 pins the headless slice; section 20 pins
  the redial ordering).

**2e remainder + Phase 3 deck oracle (v0.21.0, 2026-08-16 -- verified statically;
the three-machine round is the live gate, + live tor for an onion oracle).** The
contracts to keep intact when touching these:
  - **Street ckpts sign the TRANSITION wire's head.** Every client records the
    boundary head at the wire that produced it (last holeDeliver = "deal", the
    street's board wire, the betting-closing wire = "showdown") -- that is what
    makes two verified ckpts naming different heads FORK EVIDENCE rather than a
    timing artifact. Never sign "whatever the head is now". The ckpt body
    (street/head/sig) and the seq 7-9 wire extension are byte-pinned in
    protocol-kat; emissions are presence-guarded per street like everything in
    the react engine.
  - **The `s?` seq is a trim hint, never an authority.** The host trims the
    replay to wires past the requester's named seq; dedup keeps every replay
    idempotent, so a wrong mark can only cost bytes or starve the liar. The
    reconnect handshake still replays in full -- a rebuilt client has nothing.
  - **show/muck are display-only BY CONSTRUCTION.** Online ranks derive from
    the revealed seeds; the wires only gate what PAINTS (heNetShowSeat) and
    what History annotates ("(mucked)"). Do not let a show/muck wire near the
    settle or audit paths. Policy lives in react step 11b; the fold annotation
    is mirrored in fold-kat (keep the twins in step).
  - **The History translator re-derives, never invents.** heNetLogToHotseat
    (pure, H5) turns the signed chain into the hotseat shape; sealed
    holeDeliver wires become card lines ONLY from complete seed reveals --
    an unrevealed hand honestly gets none and its contested settle is NAMED
    by the fold. show/muck reposition ahead of their settle (the fold
    snapshots its history line there).
  - **The oracle is the host role minus the seat.** level=1 in the signed cfg
    is the ONLY marker (spec 7.2 is Level 1); dealLevel carries level=1,
    dealer=0; the dealer-authority seams go through heNetDealerPubHex /
    heNetWeDeal, and the entropy seams through heNetContribCount /
    heNetMyContribPos / heNetContribPosOk (the oracle owns exactly position
    dealCount+1 -- committed before it saw anyone's seed, revealed at hand
    end because the XOR needs it). No seat, no stack, no receipt signature;
    its audit files as "oracle" (slot 0). An onion oracle derives its service
    seed under kHeDomainOracle (never kHeDomainOnion -- the addresses must
    not collide). Recorded divergence from the spec sketch: the as-built
    oracle IS the relay, so it sees the (public, signed) betting wires; the
    no-stake property is what Level 1 actually buys (spec 7.2 as-built).
  - **Oracle loss IS host loss** -- one watchdog (60 s wire-silence during
    play; onion stream-death routes in directly), one deterministic election
    (heElectHostOf: lowest live seated pubkey, pinned as elected_host), one
    void-to-last-receipt. The elected host is NAMED and the client fails
    closed; the live handover belongs to the Phase 3 exit gate. Never make
    the election guess or negotiate -- determinism is the whole point.
  - Harness: netplay (15) pins ckpts/show-muck/trimmed-resync/History; the
    oracle section (18) runs THREE loopback contexts (heTNetPump's third
    seat) and SKIPs the live legs by name.

**2e liveness remainder + the 720p re-layout (v0.23.0, 2026-08-16), with the
v0.24.0 CORRECTIONS folded in below (2026-08-16: ten reviewed defects in this
layer, all local state-ordering/control-flow -- NO wire changed, protocol-kat's
114 pins are untouched, so v0.23.0 and v0.24.0 clients speak the identical
protocol). Verified statically; the timed live pass and the re-layout's
confirming eye are what the OXT pass owes.** The contracts to keep intact when
touching the liveness layer:
  - **The timeout is a FIELD, never a new kind.** The host authors the
    EXISTING act/bid wire with `seat=/timeout=1/bank=` marks; a pre-liveness
    client engine-rejects it visibly (out of turn for the host's seat) instead
    of mis-folding -- that compatibility is why the design refused a new
    message type. The bodies + heads are pinned (protocol-kat seq 10..13);
    changing a byte is a consensus break (pins move, kHeHarnessV bumps).
  - **No deadline ever crosses a wire.** The signed cfg carries the LENGTHS
    (`act=/bank=/miss=`; heNetCfgVal defaults keep pre-liveness cfgs folding),
    the host-countersigned turn-opening wire starts every clock
    (heNetTurnMark: the clock restarts only when the SUBJECT changes, so
    redelivery never extends a deadline), and verification is interval-on-
    one-clock: refuse a timeout more than kHeActSkewSecs (5 s, transport
    jitter) EARLY -- deliberately not the +-600 s wall-clock precedent. The
    verb/bank checks always run; they are transcript-deterministic.
    **The waiver keys on the CLOCK, not on the wire's seq (v0.24.0).**
    heNetTurnClockStart marks a turn's clock REPLAYED when it is started
    while a host replay is streaming (catchUpTo set), and heNetTimeoutOk
    waives the deadline for that turn only -- the next live turn mark
    clears the flag, so a waiver can never shelter a rushing host on a
    live turn. The seq-keyed waiver (a timeout wire at seq <= catchUpTo is
    historical) stays as well, for wires whose turn mark predates the
    replay. **What v0.23.0 got wrong, corrected here:** it had ONLY the
    seq waiver, so a client that caught up by full replay started the
    current turn's clock at replay time and then refused the host's LIVE
    timeout (seq past catchUpTo, ~10 s elapsed against a 90 s limit) as
    premature. Every other node folded the seat, so that client stayed one
    action behind for the rest of the session, every later wire
    engine-rejecting out of turn with no chain-level signal.
    KNOWN EDGE, recorded not engineered away: a timeout drained out of the
    REORDER BUFFER (a lost turn-opening wire redelivered in the same burst,
    with no r! marker) can be early-refused by the one client that only
    just learned of the turn -- locally indistinguishable from a rushing
    host, so refusing is the right fail-visible call; its fold then
    disputes at the settle. A reconnect DOES heal it now -- the replay
    re-marks the turn's clock as replayed and the waiver applies -- which
    is exactly what the v0.23.0 text claimed without it being true. The
    live pass should still try to hit this.
  - **Nothing consensus moves on a fold that did not happen (v0.24.0).**
    heNetEngineFold records gGame["foldApplied"] and every caller that
    writes shared state reads it FIRST: the bank spend and the miss count
    only move for a timeout heBetApply actually took, and a live act/bid
    only resets the miss count when the engine took THAT. v0.23.0 wrote all
    three around a fold that can refuse -- and because every client does it
    identically, the wrong state was CONSENSUS, not a divergence anything
    could detect: a seat lost its one time-bank and gained a miss for an
    action that never applied, and an out-of-turn wire from a stalling
    client reset its miss count forever, so it never sat out.
  - **Bank state is consensus, never a clock's guess.** The one per-hand
    time-bank auto-arms on the first would-be timeout (a request wire would
    race the timeout) and spends ON the wire (`bank=1` -> bankUsedBy); a
    bank-denying or bank-double-spending host timeout is refused by name.
  - **A refused timeout re-arms; it never latches (v0.24.0).** timeoutSent
    is cleared only by heNetTurnMark, which a rejected fold never reaches
    (turnKey does not move) -- so v0.23.0's host emitted once and then
    exited on its guard forever: the seat never acted and the table stalled
    SILENTLY, the exact failure the timer exists to prevent.
    heNetTimeoutRearm restarts the interval on the refused wire (the same
    wire on every client, so interval-on-one-clock survives): a bounded
    retry one act period later instead of a 4 Hz re-emit storm.
  - **Sit-out is transcript-derived**: `stand` (own key) or `miss=`
    consecutive timeouts (heNetTimeoutMiss); a live act/bid RESETS the miss
    count; sitting-out seats time out instantly (limit 0) and are dealt out
    by heNetNextOccList -- the ONE occupant rule heNetHandKick and the
    harness share (v0.24.0: its "seated with chips" half is
    heNetSeatedWithChipsList, which heNetHandKick's parked-vs-over test
    reads too -- the duplicate scan it used to carry could have drifted
    with only one of the two pinned). The seat plate says SIT OUT ahead of
    any countdown (heSeatFaceLabel, pure and pinned -- the countdown branch
    used to win and painted "0s", which is what the limit IS for a
    sitting-out seat). `sit` with no pub (own key) returns; the
    host-assignment `sit` keeps its pub=, so the forms never collide.
  - **A parked table can always resume (v0.24.0).** A short table WAITS
    instead of declaring game over while 2+ stacks exist -- and the park is
    LATCHED (gGame["handWait"]), so heNetNextHandTick fires from it in any
    phase, and heNetGameReact kicks the table the moment the folded
    transcript says two seats are dealable. v0.23.0 re-armed the beat only
    under autoNext and additionally required phase "between" -- false when
    the park came from heNetStartGame -- so the beat died on its first
    firing, and nothing else kicked: the sit-return fold cleared sitOutBy
    and stopped there, so Return succeeded and the table never dealt again.
    heNetHandKick clears the latch BEFORE it emits anything, because its
    own emissions fold re-entrantly through react.
  - **Late-join rides the boundary, and requires PRESENCE (v0.24.0)**:
    heNetSeatLateJoiners seats joined-but-unseated keys (ascending pubkey,
    lowest empty seat, cfg-capped) as signed sit wires at each kick; full =
    observer, and the standing replay machinery is what got the joiner
    current. "Has joined" is a historical fact and nothing ever clears
    boxByPub/admittedA, so it was NOT enough: a peer that joined and closed
    its stack was seated as a ghost that timed out every turn until two
    misses sat it out, then held the seat for the session (seats are never
    released). heNetPubIsLive answers "present now" from state we already
    keep -- a current transport handle (authoritative on the onion
    transport: heNetOnionDead clears it at stream death) plus a last-heard
    stamp, gGame["seenMsByPub"], written by heNetApplyWire and
    heNetOnHandshake (the only liveness rp1 has -- it surfaces no
    disconnect event). kHeSeatLiveSecs is a judgement call, not a measured
    number. **OPEN DECISION: spectator intent.** Spec 4's read-only role is
    still indistinguishable from a player here -- the admission token has a
    role field, but every client that can talk to this build sends
    "player", so refusing on role would refuse real players. Declaring
    spectator intent needs a wire/UI decision; none was invented in the
    v0.24.0 pass (also recorded in IMPLEMENTATION-PLAN.md 2e).
  - **The redial must not race the election** -- structurally: the 60 s
    wire-silence watchdog counts through every redial (a dead stream
    delivers no wires), every redial step gates on hostLost, and the
    stand-down NEVER clobbers the election's status message
    (heNetOnionStandDown is quiet; BOTH exits from the redial state use it
    since v0.24.0 -- the exhaustion branch used to run the election and
    then call heNetOnionFail two lines later, whose heUISetStatus
    overwrote the successor's name with "Join again"). Attempts are bounded
    (kHeRedialMax/kHeRedialBaseTicks, heRedialWaitTicks pure); proof the
    host answered is a host-signed wire APPLYING (heNetApplyWire resets the
    counter), nothing weaker. The redial hello's trailing seq is items-1..3
    compatible with old hosts (heAdmitTokenVerify never reads past item 3).
  - **The election always concludes -- so a redial must never call
    heNetOnionFail (v0.24.0).** heNetOnionFail tears the transport down via
    heNetStop, which clears gGame["online"] and cancels the poll tick --
    and heNetHostLossCheck exits on its FIRST line when online is not
    "true". A mid-redial dial failure therefore killed the watchdog AND
    attempts 2..4 (the bounded schedule collapsed to one), leaving a dead
    table with no successor. heNetOnionDialFail owns the fork now: mid-
    redial re-arms the schedule (heNetOnionRedialArm runs the election
    itself at exhaustion), join-time still fails closed. When touching this
    section, the rule is: nothing may tear the transport down while
    hostLost is false and gameOn is true.
  - **The re-layout is arithmetic until an eye confirms it.** Every rect
    derives from the constants block (kHeStackRect 1024x640); the pot line
    sits BELOW the board because the centre column above it belongs to seat
    4's cluster and bet chip -- move anything and re-run the rect
    arithmetic (bounds + pairwise disjointness with the designed layers
    named) before trusting it. check-stack-size now gates the budget.
  - Harness section 20 (heTestLivenessRun) pins all of it headlessly:
    prescriptions and backoff pure, wire pins, the backdated-clock netsim
    hand (premature-timeout refusal included), auto-sit-out, the waiting
    table, stand/sit round-trips, a third context late-joining to identical
    fold state, and the redial-vs-election ordering; the live legs are
    SKIPped by name. **Every v0.24.0 correction above got its own pin
    there** (kHeHarnessV 39), each one written to FAIL against the
    v0.23.0 behaviour: the seat-plate label order, the replayed-clock
    waiver and its expiry, an engine-refused timeout leaving bank/miss/
    latch alone, a rejected act not resetting the miss count, the parked
    latch firing the beat in any phase, the return unparking the table, a
    ghost key not being seated (with a present one still seated beside
    it), a mid-redial dial failure re-arming with online still true, and
    exhaustion leaving the elected successor on the status line.

**Do not claim runtime behavior you cannot observe.** Anything visual, timed, socket-,
or extension-touching gets the phrase "verified statically; needs an OXT pass" and the
user confirms in the IDE. This discipline is house law across the family.

## Required extensions

| Extension | Library id | Prefix | Needed from | Notes |
|---|---|---|---|---|
| **TorrentXT** | `org.openxtalk.library.torrent` | `bt*` | Phase 2 | ABI v8+. Uses: session settings, `btAddInfohash` phantom swarms, `btDhtAnnounce`/`btDhtGetPeers`, **rp1** (`btRp1Enable/SetToken/Send/Poll`), BEP44 (`btDhtBep44SignBuf` + `btDhtPutSigned`, `btDhtGetMutable`), `btMapPort` for the optional direct-TCP upgrade. Also install its `torrent-helpers` poll dispatcher (`btStartPolling`). |
| **SodiumXT** | `org.openxtalk.library.sodium` | `sx*` | Phase 2 (Phase 1 uses only `sxRandomBytes`/`sxHash` if installed) | Identity, sealing, commitments, randomness. **Phase 4's ristretto255 surface SHIPPED 2026-08-15** (SodiumXT ABI 8, `sxRistretto*`) **and Phase 5's DLEQ/batch surface too** (ABI 9, same day: add/sub, base-mult, batch, scalar add/mul) — cross-checked KATs green, no `sxRistretto*` handler has run on an engine yet. |
| **OnionXT** | script libraries `onionxt` (+ `onion-httpd`) | `ox*` | **onion tables BUILT 2026-08-15 (2f, v0.20.0); oracle hosting BUILT 2026-08-16 (Phase 3, v0.21.0** -- the oracle's service seed derives under its own domain tag, kHeDomainOracle**)** -- optional per table (the host picks the transport at Create; a DHT table never touches it) | Not an extension bundle: two `.livecodescript` libraries plus a **locally running tor daemon** (SOCKS 9050, control 9051; assume-running, fail-closed). Needs SodiumXT ABI >= 6 for deterministic onions, ABI 7 (`sxSha3_256`) for the offline invite address. Verified statically; needs the two-machine live-tor pass (+ the three-machine oracle round). |
| **Box2Dxt** | `org.openxtalk.box2dxt` + the Kit stack | `b2*` / `b2k*` | Phase 1 | Presentation only: spritesheet cards, physics chips, the `on b2kFrame` loop. The Kit is a `.livecodescript` stack (`box2dxt-kit`); whether this repo `start using`s it or embeds a synced copy between sentinels (the Box2Dxt-examples pattern) is a Phase 1 decision recorded in the plan. |

Install all of them through the OXT **Extension Manager**; each bundles its native
libraries per platform — nothing else to install, no `sudo`. Native **sessions bracket
the stack's life**: start in `openStack` (e.g. `btStartSession` → read handle from
`the result`), tear down in `closeStack` (`btStopPolling`, `btStopSession`) — OXT has no
deterministic extension-unload hook, so a session left running leaks its threads.

## API quick-reference (the handlers this game actually calls)

Enough surface that work here rarely needs the sibling repos open. Authoritative docs:
each sibling's `docs/api-reference.md`.

**TorrentXT** — commands report via `the result`; events drain via `btPoll(sSession)` /
`btRp1Poll(sSession)` each poll tick (the helpers' 250 ms cadence is fine).
`btStartSession`/`btStopSession`/`btLastError()`; `btSetBool sSession, "enable_dht"|
"enable_upnp"|"enable_natpmp", true`; rendezvous: `btAddInfohash(sSession, tHex40,
tPath)` + `btDhtAnnounce`/`btDhtGetPeers`; **rp1**: `btRp1Enable` (before adding swarms),
`btRp1SetToken sSession, tSignedBlob` (lands in peers' `rp1Handshake` event as `token`),
`btRp1Send sSession, tPeer, tBytes` (opaque, <= 60000 bytes, flushed on libtorrent's
<= 1 s per-peer tick — **turn-rate, not frame-rate**), `btRp1Poll` (events: `rp1Handshake`
/ `rp1Message` with `peer`, `payload`); BEP44: `btDhtBep44SignBuf(salt, seq, value)` →
sign externally with `sxSignDetached` → `btDhtPutSigned` (the secret key never crosses
into TorrentXT), `btDhtGetMutable`, `btDhtPutImmutable`/`btDhtGetImmutable`; ports:
`btMapPort` (confirmed by a `portMapped` event) for the optional direct-TCP lane.

**SodiumXT** — everything is `Data`; `textEncode` xTalk strings before hashing/sealing;
failures **throw** (wrap in `try`), except `sxSignVerifyDetached` which returns false.
**Exact signatures matter (see the resolved-`sxHash` note above):** identity/signing is
`sxSignKeypairFromSeed pSeed, out rPub, out rSec` (a **command with out-params**, not a
function), then `sxSignDetached(msg, sec)` → `Data` and `sxSignVerifyDetached(sig, msg,
pub)` → `Boolean` (never throws). Private lanes: `sxBoxKeypair`/`sxBoxKeypairFromSeed
pSeed, out rPub, out rSec` (commands), sealed boxes `sxSeal(msg, recipPub)` /
`sxSealOpen(sealed, recipPub, recipSec)` (anonymous sender), `sxBox`/`sxBoxOpen`
(authenticated). Symmetric: `sxSecretBox`/`sxSecretBoxOpen`, `sxAeadEncrypt`/
`sxAeadDecrypt` (nonces handled internally). Hashing/commitments: **`sxHash(pData,
pOutLen)`** (the output length is mandatory — use `32` for BLAKE2b-256), `sxHashKeyed(pData,
pKey, pOutLen)`, `sxHmacSha256`. Hex helpers `sxBin2Hex`/`sxHex2Bin` take and return
`Data` (ASCII) — `textDecode(..., "ascii")` for a display string. Randomness:
`sxRandomBytes`, `sxRandomUniform`. Utility: `sxMemEqual` (constant-time — the ONLY
legal way to compare secrets/MACs), `sxBin2Hex`/`sxHex2Bin`, `sxBin2Base64`/
`sxBase642Bin`. Passphrases (if a UI lock is ever added): `sxPwHash*` (Argon2id).
Shipped for Phase 4 (SodiumXT ABI 8, 2026-08-15): `sxRistrettoFromHash(h64)`,
`sxRistrettoScalarMultPoint(k, p)`, `sxRistrettoScalarRandom()`,
`sxRistrettoScalarInvert(k)` (all -> 32-byte `Data`, throw on failure - the
catch path is the detection path), `sxRistrettoPointValid(p)` -> Boolean (a
predicate, never throws on malformed input); the 64-byte from-hash input is
`sxHash(tData, 64)`. Shipped for Phase 5 (SodiumXT ABI 9, 2026-08-15, the
DLEQ/batch surface): `sxRistrettoAdd(p, q)` / `sxRistrettoSub(p, q)` (identity
a legal operand AND result - unlike scalarmult, add/sub have no identity
failure mode), `sxRistrettoScalarMultBase(k)` (throws on zero scalar),
`sxRistrettoScalarMultBatch(k, pointsConcat)` (one scalar times a CONCATENATION
of 32-byte encodings, one FFI crossing, ATOMIC - one bad point throws for the
whole call), `sxRistrettoScalarAdd(x, y)` / `sxRistrettoScalarMul(x, y)` (mod
L, widen-and-reduce semantics; zero legal, only a wrong length throws).
Verified statically; NO sxRistretto* handler has run on an engine yet.

**OnionXT** — assumes a reachable tor daemon; it is a transport + naming layer and adds
no cryptography of its own (composes SodiumXT). Dial-out: `oxDial` through SOCKS5 →
stream id, `oxWrite`, `oxCloseStream`, callbacks via `oxSetStreamCallback`. Hosting:
`oxConnectControl` (+ `oxSetControlPort`/`oxSetSocksPort`), `oxCreateService` /
`oxCreateServiceFromSeed` (deterministic address from a seed), `oxPublishService`,
`oxRemoveService`. Addresses: `oxAddressFromPublicKey`/`oxPublicKeyFromAddress`/
`oxIsValidAddress` (a v3 onion address IS an ed25519 public key — self-authenticating
rendezvous). Readiness: `oxIsReady`, `oxBootstrapProgress`.

**Box2Dxt Kit** — pixels/degrees, y-down; the Kit drives a fixed 1/60 s loop and calls
`on b2kFrame` in your script each tick. Sheets: `b2kSheetLoadAtlas`, `b2kSheetScale`,
`b2kSheetFrameNames`, and **`b2kSheetEnsureIcon` at build for every frame that can
appear** (a lazy first slice costs ~250 ms). Sprites: `b2kSpriteNew`, `b2kSpritePlay`
(one-shots fire `b2kSpriteOnFinish` — see carried gotcha 19), `b2kSpriteSetFrame`,
`b2kSpriteFPS`, `b2kSpriteFlipH`, `b2kSpriteMoveTo` (never a raw `set the loc`),
`b2kSpriteBind`/`b2kSpriteRemove`. Bodies (chips): `b2kSpawnBox`/`b2kSpawnBall` are
*commands* → `put the result into tCtrl` immediately (gotcha 27); one `b2kForce` toss,
then let them sleep (gotcha 17). Sensors/contacts (if ever used) go to
`b2kContactTarget` (gotcha 14). Deterministic stepping exists (`b2kStepOnce`,
`b2kInputInject`) but this game does not depend on physics determinism — physics is
cosmetic here by design (spec section 11).

## LiveCodeScript / OXT gotchas (carried from Box2Dxt, original numbering kept)

`holdem-spec.md` cites these by number, so the Box2Dxt numbering is preserved; gaps are
lessons that only apply to platformer-style games and were left behind. OXT's compiler
is **stricter than LiveCode's**; every one of these broke a real build or shipped a real
bug in the family.

1. **No smart quotes.** Curly quotes (U+201C U+201D U+2018 U+2019) anywhere — even in a comment or string literal —
   fail OXT compilation. Straight ASCII `"` and `'` only. (Unicode glyphs in *display*
   strings are fine.) The static gate enforces this.
2. **Avoid names that shadow engine tokens.** Custom property/variable names whose stem
   is an engine keyword break compilation even when prefixed (real case: `the uCat` /
   `the uMask` → renamed `uHitChans`/`uOnChans`). A whole name that case-insensitively
   *equals* a token is even worse — it silently evaluates AS the token: `tAb` is read as
   the `tab` constant (found v0.4.2, in `heByteXor` → renamed `tWorkA`). Prefer
   distinctive multi-word stems. The static gate now flags any local/param whose name
   equals an engine token (unified checker check 14).
3. **Prefix conventions:** `u` = custom property, `g` = script-local global, `t` =
   handler local, `p` = parameter, `k` = constant. Public API prefixes in the family:
   `b2k*`, `bt*`, `sx*`, `ox*`; this repo's public surface will be `he*` (holde-em) —
   pick distinctive names within it.
4. **Control-structure shape matters.** Block form `if cond then` … `end if`; the
   single-line form `if cond then doSomething` has **no** `end if`. A trailing `\`
   continues a logical line. Naive brace-counters false-positive on `\`-continued `if`
   and multi-line `else if` — verify by eye before "fixing" valid code.
5. **`itemDelimiter`/`lineDelimiter` are global mutable state.** Set immediately before
   every parse; never assume the current value. Envelope fields and record packing will
   interleave tab- and comma-delimited text constantly.
6. **Constants must be literal.** `constant k = "120"` compiles; `constant k = a*b`
   does not — derive computed values at runtime.
7. **Command results vs function returns.** A command reports via `the result`; a
   function returns a value. Mixing them up fails silently — and calling a **command**
   with function-call syntax `heFoo()` does not fail silently: it **throws** at the call
   site ("error in function handler"), the body never runs (found v0.10.x — the harness
   called `heProbeSodium()` this way and the probe blew up before executing). Only a
   `function` may be invoked with `()`; a command is a statement, or route it through a
   value via `the result`. The static gate flags a locally-declared command used with
   `()` in expression position (unified checker check 16) — a parenthesised first
   argument `heFoo (x), y` is legal and is not flagged.
8. **Custom properties are text.** Everything round-trips as strings; booleans are the
   strings `"true"`/`"false"`.
10. **Dangling else.** A bare `else` on the line after a single-line `if cond then stmt`
    binds to that inner `if`, closes the wrong block, and surfaces as a baffling
    "missing end if" at handler end. The static gate flags the exact pairing
    (unified checker check 20).
11. **Declare `local` only at the top of a handler.** A `local` nested inside an
    `if`/`repeat` block has broken compilation of an entire script.
13. **Object-type tokens are single words.** `import audioClip from file …` compiles;
    `import audio clip …` does not. Dictionary prose spells them as two words; the
    tokens are not. Same family (found v0.17.1): the message box CONTAINER is the
    single token `msg` — `put x into msg`; the prose form `put x into the message
    box` throws at runtime. The static gate flags `the message box` in code
    (unified checker check 18).
14. **Sensor/contact messages go to `b2kContactTarget`, not the frame target.**
    Forgetting it = silent sensors with zero errors. Set both targets if the table ever
    uses Kit sensors.
17. **`b2kSetVelocity` wakes the body — by design.** Never write a velocity per-frame to
    something meant to rest. Chips get ONE toss impulse, then sleep; a sleeping body
    costs the solver zero.
19. **A non-looping animation fires `b2kSpriteOnFinish` whoever started it.** Card-flip
    chaining relies on this; every `*Done` handler must gate on its own context lock so
    a stale finish cannot double-fire a flip sequence.
23. **Sprites follow position only — they do not rotate.** Card flips are therefore
    squash-frame animations, never rotations; anything that must visibly tumble (chips)
    is a *graphic*-backed body, not a sprite.
24. **Mixed sprite families never share a table raw.** Foreign sheets load with
    `b2kSheetScale` normalisation; some families' frame names carry their `.png` suffix
    and some do not — check per sheet.
27. **`the result` is consumed by the NEXT command.** Capture it into a local
    immediately after every spawn/maker call before calling anything else. Several past
    bugs in the family were a stale `the result`.
29. **A `constant` must be declared before its first use, lexically.** OXT resolves
    constant names by file position; a use above the declaration compiles clean and
    silently evaluates to nothing at runtime. Declare constants at the top of the file
    (this bug shipped a broken feature in the family once already). The unified
    checker now gates both halves: use-above-declaration (check 4) and a `k` name
    with NO declaration at all (check 19, the heTestDealRun defect).

House additions for THIS repo (earned in the siblings, restated as law here):

- **H1. Bracket native sessions around the stack's life** (`openStack`/`closeStack`);
  never leave a TorrentXT session running after close.
- **H2. One poll drain per tick.** `btPoll` + `btRp1Poll` on the helpers' timer (~250 ms)
  — never in `on b2kFrame`, never per-frame.
- **H3. Everything is `Data` at the SodiumXT boundary.** `textEncode(..., "utf-8")` on
  the way in, `textDecode` on the way out; hex only for display/transcript-text fields.
- **H4. Crypto failures throw** — every `sxSecretBoxOpen`/`sxSealOpen`/`sxSignOpen` sits
  in a `try`/`catch`, and the catch path treats the message as hostile (drop and log),
  never as a retry.
- **H5. Pure logic stays pure.** Evaluator, betting engine, transcript fold, settlement:
  values in, values out, no UI reads, no `the result` reliance inside — this is what
  keeps them machine-testable (and it is why the KATs can run in CI at all).
- **H6. Never take a chunk of an array element directly.** `byte i of tA[j]`,
  `char 5 to -1 of tA["from"]`, `item n of tA["stacks"]` — all of them throw a
  double/binary conversion error at runtime (found on this repo's first OXT pass, in
  the seed-XOR path; the compiler accepts the syntax happily). Copy the element into a
  plain local, then chunk the local. Same rule for `replace ... in tA["k"]` — copy out,
  modify, or avoid. NOT a static gate any more, ON PURPOSE (the 2026-08-15
  checker union): riptide, onionxt, box2dxt and nocloud all chunk array
  elements in engine-passed code, so the pattern is not a fleet-wide trap -
  what threw HERE was FFI-bridged binary meeting the chunk evaluator (see the
  corollary below). H6 stays this member's law, held by review, not a checker.
  **Corollary (v0.1.1): keep FFI-bridged binary away from the script chunk evaluator
  entirely.** The double/binary error persisted past the copy-to-local fix, so binary
  from `sx*` handlers is now hex-encoded at the edge (`sxBin2Hex` — itself proven by
  the sodium probe) and everything script-side chunks plain hex text; raw Data exists
  only in expressions passed straight into `sx*` calls. Seeds, the shuffle stream, and
  every transcript field follow this rule.
- **H7. No bitwise operators.** `bitXor`/`bitAnd`/`bitOr`/`bitNot` throw the same
  double/binary conversion error at runtime on this OXT engine (found v0.4.1, in the
  seed-XOR path — `bitXor(acc, baseConvert(...))`). They are valid LiveCode syntax, so
  no structural check sees them. Do every bit operation with **pure integer arithmetic**
  (`div`, `mod`, `add`, `*`) — the repo carries `heByteXor` (an 8-iteration div/mod XOR)
  for exactly this. The static gate flags the function-call form `bitXor(a, b)`
  fleet-wide (unified checker check 13) - which is the exact shape v0.4.1
  shipped - but NOT the operator form `a bitXor b`, which stands in
  engine-passed code in four other members; the blanket no-bitwise rule stays
  THIS member's law, held by review.
- **H8. Declare the catch variable as a local.** `try … catch tErr` where `tErr` is not in
  the handler's `local` list throws a SECOND error on strict OXT the moment the catch
  fires and its body references the variable — which masks the real failure and surfaces
  as an opaque "error in function handler". It is invisible on a read (the catch only
  misbehaves when it actually fires) and only bites once the `try` body starts throwing:
  `heProbeSodium`/`heProbeTorrent`/`heDeckFromStreamKey`/`heNetStart` all shipped this and
  blew up only once SodiumXT/TorrentXT was installed (found v0.10.x — the probe threw
  instead of reporting). Every `catch <var>` must have a matching `local … <var>` (the
  family pattern; `heTableNew` does it right). The static gate flags an undeclared catch
  variable whose catch body REFERENCES it (unified checker check 15; the unreferenced
  form is engine-proven safe in onionxt's probes, so only the reference is gated -
  declaring every catch variable regardless stays this member's convention).
- **H9. No parenthesised dynamic property names.** `the (expr) of obj` /
  `set the (expr) of obj to ...` — building a property NAME at runtime — is not
  portable xTalk: property names are compile-time tokens, and the computed-name form
  is engine-shaky on OXT. It shipped once (v0.14.0 stored avatar paths in per-seat
  props named `"uHeAvatarPath" & N`) and was caught in the pre-OXT-pass re-audit
  (v0.15.0 fold of PR #33). The portable shape is ONE property holding a line-/item-
  indexed list (`uHeAvatarPaths`, line N = seat N — paths cannot contain a newline,
  so the index is safe); copy the property into a local before chunking it (H6
  corollary). The static gate flags any `the (` in code (unified checker check 17).

## The single-threaded performance playbook (condensed for a card game)

OXT runs everything — script, FFI, rendering — on ONE interpreted thread at ~60 fps
(~16 ms budget). Costs in order: interpreter ops, FFI round-trips, property-set redraws.

- **Pool at build, never create mid-hand.** All card sprites, chip bodies, and UI
  chrome exist before hand 1; reuse by `b2kSpriteMoveTo`/frame swap. Creates stall
  under accelerated rendering.
- **Pre-warm every sheet frame** that can appear (`b2kSheetEnsureIcon` at build).
- **HUD text at 4 Hz max, and only on change** (pot, stacks, timers). An every-frame
  field write forces an every-frame relayout+repaint — the single biggest avoidable
  cost found in the family's games.
- **Idle costs one compare.** Between animations the table's `b2kFrame` work must gate
  behind single `if`s.
- **No per-frame crypto, no per-frame FFI.** All signing/sealing happens at message
  boundaries (human-rate); the deal-time burst (52 scalar mults at Phase 4) is fine
  *because* it is deal-time.
- **Defer world changes out of event dispatch**: `send "..." to me in 80 milliseconds`
  and guard the handler against stale sends with a mode/lock check.

## Security house rules

Spec section 16 is the checklist and it is law. The load-bearing ones: `sxMemEqual` for
every secret comparison; `sxRandomBytes` for everything unguessable (the engine
`random()` never touches dealing or keys); domain-separated, versioned hash inputs
(`"HOLDEM-<PURPOSE>-v<N>|"`); verify-then-parse on every inbound envelope, drop-and-log
on any failure; fresh per-hand deal randomness and per-table session keys; long-term
keys only ever sign. When in doubt, the spec's threat model (section 2) decides.

## Workflow

- **After every `.livecodescript` edit:** `python3 tools/check-livecodescript.py`
  (since the 2026-08-15 checker union it carries the hold-em lineage checks too;
  the separate idiom gate is retired).
- **The self-test harness** (`heRunSelftest`, embedded in the one stack) follows the
  Box2Dxt pattern: deterministic assertions, a version constant (`kHeHarnessV`) printed
  in the report header and **bumped on every engine-behavior change** so a stale paste
  identifies itself, and self-diagnosing asserts that print what was observed, not just
  FAIL. Expect first-contact arithmetic errors in new tests; write them to debug
  themselves.
- **The OXT round-trip:** you change script → gates pass → the user pastes/compiles in
  OXT, runs the harness and/or plays, reports back. Anything not user-confirmed stays
  labelled "verified statically".
- **Git:** work on the session's task branch, push, open a draft PR. Keep commits
  scoped; docs-only changes say so.
- **Style:** this codebase comments the *why*, densely, in the family's voice — mirror
  it. Straight quotes everywhere, including docs.

## Repo layout (as-built; see IMPLEMENTATION-PLAN.md for sequencing)

```
README.md                          front door
CLAUDE.md                          you are here
LICENSE                            MIT (the family default, decided Phase 0)
holdem-spec.md                     the design contract
IMPLEMENTATION-PLAN.md             the phased build order
tools/check-livecodescript.py      the suite's UNIFIED static checker (drift-gated;
                                   since 2026-08-15 it carries the hold-em lineage
                                   checks as its 13-21 - the old idiom gate is retired)
tools/check-docs.py                docs smart-quote scan
tools/evaluator-kat.py             spec 8.2 evaluator vectors (CI mirror of heEval7)
tools/betting-kat.py               spec 8.1/8.3 betting + settlement cases (CI mirror)
tools/shuffle-kat.py               playable integer deal (CI mirror of heShuffleDeck)
tools/protocol-kat.py              spec 6/7.1 envelope/chain/deal wires + the
                                   spec 7.3 Level 2 ristretto algebra (l2_* twins
                                   over an independent RFC 9496 reference)
tools/fold-kat.py                  transcript fold + settlement/deal audits (CI mirror)
tools/atlas-kat.py                 Kenney card atlas <-> frame-name mapping
tools/sounds-kat.py                vendored casino WAVs <-> stack mapping
tools/logic-fuzz.py                INDEPENDENT-reference fuzz (rules, not the port)
assets/cards/, assets/sounds/      vendored Kenney CC0 art + audio (see NOTICE.md)
src/holdem.livecodescript          the whole thing: game + self-test + sodium probe,
                                   one self-building paste-and-run stack
.github/workflows/ci.yml           the standalone mirror's CI; INERT in the suite
                                   (tools/build-all.sh --gates runs the same set here)
```
