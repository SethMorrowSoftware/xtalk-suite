script "Holdem"
/*
holdem.livecodescript -- serverless no-limit Texas Hold'em for OXT (holde-em).

ONE self-contained, paste-and-run stack: the hotseat game plus its own
self-test harness. Two entry points into that harness: heRunSelftest in the
message box (interactive -- report panel, clipboard, msg) and heSelfTest()
(quiet -- returns the report as a value and touches nothing). No second
stack, no required extensions to be playable.

v0.25.1 -- LEAF TRANCHE 2 (2026-08-27). NO WIRE CHANGED -- not a byte.
kHeVersion 0.25.0 -> 0.25.1, kHeHarnessV 42 -> 43 (a new section, so a
stale paste identifies itself); kUIVersion stays 15 (no chrome moved).
  * SECTION 23 ADDED (heTestLeafRun2): the second tranche of the suite
    coverage gate's no-test worklist, 27 handlers moved out of the
    baseline (129 -> 102), written the morning of a two-machine OXT
    session so the evening paste carries it. Same selection rule and the
    same shallow-on-purpose banner as section 22: pure functions (card
    faces, hand labels, the circular seat walkers, the wire splitter,
    the rejection sampler -- its throw leg included) plus gGame-only
    leaves driven on a synthetic gGame saved/restored around the block
    (call/pot arithmetic, liveness, pacing, seats-alive, contributor
    positions, turn allowances, the header/invite text, the log
    appender). Nothing arms a timer, touches a control, plays a sound,
    or crosses an FFI. Verified statically; needs an OXT pass.

v0.25.0 -- THE BATCHED SHUFFLE-MASK STEP + THE LEAF TRANCHE (2026-08-23).
NO WIRE CHANGED -- not a byte: every pinned record format and void string
stands, and protocol-kat's existing pins are untouched (it grew NEW pins
for the deal-delivery wire types the same day, an additive extension).
kHeVersion 0.24.5 -> 0.25.0, kHeHarnessV 41 -> 42 (a new section plus new
assertions in section 16, so a stale paste identifies itself), kUIVersion
stays 15 (no chrome moved). Verified statically; needs an OXT pass -- and
NOTE: THIS FILE's sxRistretto* calls have not run on an engine (the
exports themselves are engine-observed: sodiumxt's ABI-9 records,
2026-08-17 Windows and 2026-08-18 Linux, the batch call included with its
index-naming failure path - so the pass this member owes is its own
caller, not the library).
  * heL2MaskDeckHex grew a BATCH FAST PATH (plan 4f's batch handler,
    pulled forward ahead of 4f's measure-first order -- the headless
    backlog's A1): on SodiumXT ABI 9, gated on the same cached
    heL2HasDleq() probe the DLEQ verifier uses, the happy path is ONE
    atomic sxRistrettoScalarMultBatch crossing for all 52 mults -- 4 FFI
    crossings for the whole step (hex2bin scalar, hex2bin concat, batch,
    bin2hex) against the per-point loop's ~312. The loop STAYS, twice
    over: it is the only path on a pre-ABI-9 SodiumXT, and it is the
    refusal path everywhere -- the batch is atomic (one bad point throws
    for the whole call) and its error text is never parsed; any throw
    falls through to the loop, which re-derives the verdict with the
    exact position-tagged "void:..." string 4d attribution switches on.
    So the two paths cannot disagree on a refusal by construction, and
    section 16 pins the other half: batch and loop agree byte-for-byte
    on the fixed KAT deck (deterministic scalars, no randomness), and a
    corrupted point still voids with its output position. The wrong
    "52 crossings" figures in this handler's comment and in
    IMPLEMENTATION-PLAN 4f are corrected in the same change.
  * SECTION 22 ADDED (heTestLeafRun): the first tranche of the suite
    coverage gate's no-test worklist -- the nine pure leaves its own
    comment names as the place to start (heRank5, heCardRankVal,
    heCardSuitVal, heTwoDigits, heCountItems, heNextInList, heByteXor,
    heU32BEData, heHexId), each with real value assertions, shallow on
    purpose and the banner says so (the box2dxt precedent). Plus
    heHandStart -- until now named in this harness only inside a test
    label, the gate's one measured literal-vs-call gap -- exercised on
    its PURE PRELUDE only: both refusal guards (active phase, online)
    asserted on a synthetic gGame with handNum-unmoved as the witness,
    because past the guards it deals a hand, arms the paced-step timers
    and drives the table UI, which a folded harness must never do inside
    somebody else's paste. The ten are moved out of the suite gate's
    no-test baseline (139 -> 129); heProbeSodium is the 23rd entry in
    heTestRunAllSections now.

v0.24.4 -- THE ELECTION'S SIT-OUT FILTER + THE HELPERS NO TEST NAMED
(2026-08-17). NO WIRE CHANGED -- not a byte: protocol-kat's pins all still
hold and two were ADDED beside them, so a v0.24.3 client and a v0.24.4
client speak the identical protocol. kHeVersion 0.24.3 -> 0.24.4,
kHeHarnessV 40 -> 41, kUIVersion stays 15 (no chrome moved). Verified
statically; needs an OXT pass.
  * heNetElectablePubs ELECTED SITTING-OUT SEATS, and it is a deterministic
    table death rather than a divergence. It scanned seatedList itself,
    filtering on seated + chips + not-the-lost-host, and never looked at
    sitOutBy -- while spec 9, this file's own header, and heElectHostOf's
    own comment all say the successor is the lowest pubkey among the LIVE
    SEATED players. A sat-out seat is dealt out at every boundary and times
    out instantly, so electing it hands the table to the one key guaranteed
    not to re-host -- and because every client runs the same code, every
    client agrees on the wrong successor and nothing detects it. It rides
    heNetSeatedWithChipsList now (v0.24.0's F10 scan -- this was its last
    stray copy) filtered exactly the way heNetNextOccList filters it: one
    occupancy definition, three readers.
    WHY THE FILTER IS SAFE HERE, which is the whole reason it can be
    applied at all: sitOutBy is derived from the TRANSCRIPT alone (a signed
    stand wire, or heNetTimeoutMiss counting host-authored timeout wires),
    so every client computes the same candidate set with no round trips --
    the property the election exists for. heNetPubIsLive would NOT be safe:
    it answers from per-client observation (our transport handle, our
    last-heard stamp), so two clients could legitimately name two different
    successors. Presence gates SEATING; only transcript-derived facts may
    gate an election.
    WHY NO GATE SAW IT: the handler is REACHABLE and always was -- section
    20 drives heNetHostLost twice and section 18 once -- but every one of
    those assertions only checks that SOME successor was named. The FILTER
    was what nothing tested, so the defect was invisible to a fully green
    507/0 run. Section 20 now pins the candidate set itself (three seats,
    the lowest key sat out, the successor moving up), and protocol-kat
    mirrors it as elected_host_sitout beside elected_host.
  * SECTION 21 ADDED (heTestHelpersRun) for the pure leaf handlers that no
    heTest or heProbe body had ever named -- 205 of this file's 379 public
    handlers were in that state when the suite measured it on 2026-08-16.
    (Spelling those two prefixes with globs and a slash would close this
    block comment on the spot; the unified checker caught exactly that
    while this entry was being written.)
    Shallow on purpose and its banner says so. The two that mattered:
    heTableInfohash is the spec 10 DHT RENDEZVOUS ID (an off-by-one in its
    chunk fails nowhere and costs a whole multi-machine session -- two
    peers announcing to two different keys), and heFingerprintOf is the
    spec 5 display handle; both are pinned in section 9 against new
    protocol-kat mirrors (table_infohash / id_fingerprint1). Plus value
    pins for heSwapExt (including its documented dotted-folder edge and its
    itemDelimiter restore -- atlas-kat hardcodes both sides of the
    .png/.xml pair and models no swap, so these come from the contract, not
    from a mirror), heSettingsNumOk, heHandByOf (including the "between"
    edge that stops the HUD double-counting a settled hand) and heRcTxt.
    heProbeSodium is the 22nd entry in heTestRunAllSections now; it was
    always the trailing PROBE rather than a numbered section, and the two
    places in this file that called it "section 21" are corrected.
  * heFitRect's COMMENT WAS FALSE and is corrected rather than the code.
    It claimed "integer div keeps it exact"; the rect is built as
    centre -+ (t div 2), so the rendered size is 2 * (t div 2) and an ODD
    fitted size comes out one pixel short. What integer div actually buys
    is exact SYMMETRY about the centre, and that is the property
    tools/check-table-layout.py's exemption for both callers rests on --
    it derives the built heSeatAv<N>/heTableLogo rects and argues this
    runtime re-fit can only ever shrink inside them, which an exact-width
    version would weaken by pushing one edge to ceil(t/2). One pixel on a
    blendLevel watermark did not justify an un-eyeballed geometry change in
    the one layer whose confirming eye is still owed to the OXT pass, so
    the behaviour is PINNED (symmetry and the one-pixel cost, both) and the
    comment now says what the code does.

v0.24.1 -- THE THREE SOURCE-SIDE FOLD BLOCKERS, CLEARED (2026-08-16). No
wire change (protocol-kat's 114 pins are untouched), no gameplay change,
no chrome change: kUIVersion stays 15, kHeVersion 0.24.0 -> 0.24.1,
kHeHarnessV 39 -> 40 (the harness grew a second entry point, so a report
has to be able to say which one produced it). Verified statically; needs
an OXT pass.
  * b2kSpriteOnFinish REMOVED, and it was a real defect: this file defined
    it as a RECEIVER, but it is the b2k Kit's SETTER
    (b2kSpriteOnFinish pCtrl, pMessage registers the message the Kit should
    dispatch when a non-looping animation ends, and the Kit dispatches THAT
    REGISTERED NAME). The handler therefore never ran, and it shadowed the
    setter for any future caller. LOUD PART, because it is the kind of
    thing that reads like a regression later: NOTHING BROKE, because the
    card-flip chaining it was written for was never built at all --
    b2kSpritePlay is called nowhere in this file (the pooled card slots
    swap faces with b2kSpriteSetFrame) and b2kFrameTarget is called
    nowhere, so the Kit had neither an animation to finish nor an object to
    dispatch a finish to. Carried gotcha 19 is still true and still owed;
    what was untrue was the belief that this file had honoured it. The real
    three-part wiring is written down where the handler stood, and the
    gotcha now names the setter/receiver trap.
  * THE 81 DECLARATIONS BELOW THE FIRST HANDLER ARE HOISTED. Every
    script-level local and constant now sits above `on preOpenStack`
    (187 of 187), where OXT's lexical-position rule and any assembly that
    hoists a leading preamble can both see them. The harness block moved
    verbatim -- same order, same comments, every constant's literal value
    byte-identical -- and the checker's constants-before-use gate holds it.
  * heSelfTest() ADDED beside heRunSelftest, not instead of it: the quiet,
    returned-report entry point a folded harness needs (riptide's rsSelfTest
    is the shape, copied deliberately). It builds no overlay, does not touch
    clipboardData (the suite scaffold's own Copy-results channel),
    puts the counts on a first line the suite core's stSummaryCounts can
    actually parse -- "n passed, m failed", where the shipped
    "==== n pass, m fail, k skip ====" is refused on purpose -- and sweeps
    its own pending heNet* messages so no timer this harness armed is left
    running inside somebody else's paste. Both entry points drive one
    heTestRunAllSections, so they cannot drift apart.
    (This entry said "or msg" until the 2026-08-16 suite fold, and that half
    was not true: the trailing entry is heProbeSodium (section 21 then, 22
    since v0.24.4 added the pure-helpers section ahead of it), whose last act
    is a bare `put tRpt`, and a bare put writes to msg. Deliberate at its own site --
    running the probe from the message box should print -- and harmless in a
    host paste, since nothing the suite core owns lives in msg. Corrected
    rather than left reading better than it is.)

v0.24.0 -- LIVENESS-LAYER CORRECTIONS: ten reviewed defects in the v0.23.0
2e layer, every one of them a local state-ordering or control-flow fault.
NO WIRE CHANGED -- not a byte, not a field, not an order: protocol-kat's
114 pins are untouched, so a v0.23.0 client and a v0.24.0 client speak the
identical protocol and disagree only about what they do to themselves.
kHeHarnessV 38 -> 39 (section 20 grew a pin per fix); kUIVersion stays 15
(the seat plate's label order changed, but the plate is painted at
runtime, so no saved chrome has to be rebuilt). Verified statically; the
live legs are unchanged and still owed.
  * THE ELECTION ALWAYS CONCLUDES -- for real this time. A dial failure
    during an auto-redial (a throw, a non-integer stream, a callback
    registration failure) took heNetOnionFail, whose heNetStop clears
    gGame["online"] and cancels the poll tick -- and heNetHostLossCheck
    exits on its FIRST line when online is not "true". So the one thing
    the redial design promised, that the 60 s wire-silence watchdog keeps
    counting underneath, was false the moment a redial dial failed: no
    election, and no attempts 2..4 either (the bounded four-attempt
    schedule collapsed to one). heNetOnionDialFail now owns that fork --
    mid-redial failures re-arm the schedule (heNetOnionRedialArm runs the
    election itself at exhaustion), join-time failures still fail closed.
  * ONE QUIET EXIT FROM THE REDIAL STATE (heNetOnionStandDown). The
    exhaustion branch ran the election, which names the elected successor
    on the status line, and then called heNetOnionFail two lines later,
    which overwrote it -- precisely what heNetOnionRedialGiveup's comment
    said must never happen. Both exits share one handler now; the player
    always ends up seeing who was elected.
  * A REPLAYED CLOCK IS MARKED REPLAYED (heNetTurnClockStart). A client
    catching up folds the turn-opening wire NOW, so its act clock starts
    for a turn that opened long ago everywhere else; the host's live
    timeout then lands past the replay's head, where the seq-keyed waiver
    cannot reach it, and was refused as premature. Every other node had
    folded the seat, so that client was one action behind FOREVER, every
    later wire engine-rejecting out of turn with nothing on the chain to
    say why. The waiver keys on the CLOCK now -- and dies with its turn,
    so it can never shelter a rushing host on a live one. (The v0.23.0
    KNOWN EDGE claim that "a reconnect heals it" was false for exactly
    this reason; CLAUDE.md now says what is true.)
  * NOTHING CONSENSUS MOVES ON A FOLD THAT DID NOT HAPPEN.
    heNetEngineFold records gGame["foldApplied"], and the timeout folds
    read it: the seat's one per-hand time-bank is spent and its miss
    counted only when heBetApply actually took the action (both were
    written around a fold that can refuse -- and since every client did it
    identically, the wrong state was CONSENSUS, not a divergence anyone
    could detect); a live act or bid resets the miss counter only when the
    engine took THAT (the unconditional reset let a stalling client hold
    itself at zero misses forever with out-of-turn wires, so it never sat
    out and every hand still burned the full act timer plus bank).
  * A REFUSED TIMEOUT RE-ARMS INSTEAD OF STALLING (heNetTimeoutRearm).
    timeoutSent latched when the host EMITTED, and only heNetTurnMark
    cleared it -- which a refused fold never reaches, since turnKey does
    not move. The host then never re-emitted, the seat never acted, and
    the table stalled silently: the exact failure the timer exists to
    prevent. The interval restarts on the refused wire (the same wire
    everywhere, so the interval-on-one-clock property holds), which is a
    bounded retry rather than a 4 Hz re-emit storm.
  * A PARKED TABLE CAN RESUME (gGame["handWait"] + react's unpark step).
    The "waiting for sitting-out players" park re-armed the beat only under
    autoNext, and the beat additionally required phase "between" -- false
    when the park came from heNetStartGame, so it died on its first firing.
    Nothing else kicked: the sit-return fold cleared sitOutBy and stopped,
    so the returning player saw Return succeed and the table never dealt
    again. The park is latched (any path can re-arm it) and the react
    engine kicks the moment the folded transcript says two seats are
    dealable -- no timer needs to be alive.
  * LATE-JOIN REQUIRES PRESENCE, NOT HISTORY (heNetPubIsLive). The
    boundary seated every admitted key that had ever emitted a join wire,
    and nothing ever clears boxByPub/admittedA -- so a peer that joined and
    closed its stack was handed the lowest empty seat and a full stack,
    timed out every turn until two misses sat it out, and held the seat for
    the session. Liveness comes from state we already keep: a current
    transport handle (authoritative on the onion transport, which clears it
    at stream death) plus a last-heard stamp (the only signal rp1 has -- it
    surfaces no disconnect event). OPEN: telling a SPECTATOR from a player
    still needs a wire/UI decision and none was invented here (recorded in
    CLAUDE.md / IMPLEMENTATION-PLAN.md).
  * THE PLATE'S STATUS OUTRANKS ITS STOPWATCH (heSeatFaceLabel, now pure
    and pinned). A sitting-out seat whose turn came up painted "0s" --
    which is exactly what heNetTurnLimitSecs returns FOR a sitting-out
    seat, so the plate showed the reason for the SIT OUT label instead of
    the label.
  * ONE OCCUPANCY RULE (heNetSeatedWithChipsList). heNetHandKick's
    chip-count loop re-implemented the scan heNetNextOccList had just been
    extracted to centralize, and only heNetNextOccList was pinned.
  * heUISetStatus also stashes gGame["statusTxt"], so a headless harness
    can pin WHICH message won a race for the status line -- the redial
    clobber above was unpinnable while that text lived only in a field.

v0.23.0 -- 2e LIVENESS REMAINDER (spec 8.1/9: act timers + time-bank,
sit-out/return, late-join, onion auto-redial) + the 720p RE-LAYOUT
(1024x690 -> 1024x640, the suite height budget). kHeHarnessV 37 -> 38 (new
section 20 + regenerated cfg pins); kUIVersion 14 -> 15 (the re-layout +
the Sit out toggle). Everything verified statically; the live legs -- a
timed two-machine table on wall clocks, and a real tor-stream loss +
redial -- are named SKIPs, and the re-layout's confirming eye (nothing
clipped, the felt still reads) is the OXT pass's.
  * ACT TIMERS + TIME-BANK (spec 8.1 "timers from the signed config", 9
    "expiry = check/fold"): the timer LENGTHS ride the signed cfg as
    act=/bank=/miss= keys (spec 6 message zero -- lobby_cfg_body/
    lobby_head2 pins regenerated, a documented consensus change; a
    pre-liveness client ignores unknown keys, so the wire stays
    compatible). The deadline needs NO wire of its own: the
    host-countersigned turn-opening wire starts every client's countdown
    identically, and expiry is the HOST's signed TIMEOUT wire -- the
    EXISTING act wire with seat=/timeout=1/bank= marks (never a new kind;
    a pre-liveness client engine-rejects it visibly instead of
    mis-folding) -- folded as the named seat's action so the transcript
    stays deterministic. Every client verifies: host authority, the exact
    spec-9 prescription (check when nothing is owed, else fold; a host
    may never fold a seat that could check), the transcript-derived bank
    state, and that the deadline genuinely passed on ITS OWN clock within
    kHeActSkewSecs (5 s -- transport jitter, NOT the +-600 s wall-clock
    freshness precedent: no timestamp crosses this wire, both sides time
    the same wire-to-wire interval locally; catch-up replay waives the
    check, the live table already policed it). The ONE per-hand time-bank
    (spec 8.1) auto-arms on a seat's first would-be timeout each hand --
    a request wire would race the timeout on a lossy transport -- and its
    spend rides the wire as bank=1, so bank state is CONSENSUS, derived
    from folded wires, never a local clock's guess. Forced posts get the
    same treatment once the deal is complete (timeout-marked bid wires at
    exactly the engine's amount), so a dark seat can no longer wedge the
    blinds; an L0 deal stall (a contributor never commits/seals/reveals)
    stays unprescribed at Level 0, recorded honestly -- spec 9's dealing
    timeout is the L2 void-and-audit machine's. HUD: the acting seat's
    remaining seconds paint through the 4 Hz tick, marked dirty only when
    the shown second changes.
  * SIT-OUT/RETURN (spec 9 "seat goes to sit-out after (config) misses"):
    a seat's own signed "stand" wire (seat-scoped like show/muck) sits it
    out; kHeDefaultMisses consecutive timeouts (transcript-derived, so
    every client agrees) sit it out automatically; a sitting-out seat's
    mid-hand turns time out INSTANTLY (the spec's auto check/fold -- and
    auto-POST for a pending blind) and it is DEALT OUT at the next
    boundary (heNetNextOccList: seated + chips + not sitting out); the
    seat's own "sit" wire (seat only, no pub -- the host-assignment form
    keeps its pub= field) re-enters at the next hand. A table with fewer
    than 2 live seats but 2+ stacks WAITS ("Waiting for sitting-out
    players") and re-arms the between-hands beat instead of declaring
    game over. New top-bar Sit out/Return toggle; the seat plate shows
    SIT OUT.
  * LATE-JOIN (the 2d deferral): a mid-session joiner already got the
    full replay (that machinery stands); now the host seats every joined
    key without a seat at each hand boundary -- lowest empty seat,
    ascending-pubkey order, up to the cfg's seat count, each as a signed
    sit wire, opening stack from the signed cfg -- or it stays an
    OBSERVER when the table is full (it folds the whole game already).
  * ONION AUTO-REDIAL (the 2f deferral): a lost host stream during play
    now arms a BOUNDED redial (4 attempts, 2/4/8/16 s doubling backoff,
    10 s per dial) BEFORE failing closed -- the host's onion address is
    deterministic (spec 9), so the same invite redials. The 60 s
    wire-silence election watchdog keeps counting underneath and always
    concludes: every redial step gates on hostLost and stands down
    quietly when the election names the successor first (never
    clobbering its status message). A successful redial's hello now
    carries our APPLIED SEQ as a compatible trailing token item
    (heAdmitTokenVerify reads items 1..3; old hosts ignore it), so the
    host's reconnect replay arrives TRIMMED to the tail past our seq --
    the spec 9 "since your last ckpt" resync; proof the host answered is
    a host-signed wire applying, which resets the attempt counter.
  * THE 720p RE-LAYOUT (kHeStackRect 1024x690 -> 1024x640): the felt's
    vertical rhythm tightened (felt 48..524, board centre 300 -> 286,
    seat ring pulled in, the pot line moved BELOW the board where the
    centre column is clear of every bet cluster), slider/action/status
    rows pulled inside the fold, the header narrowed clear of the new
    Sit out button. Verified BY ARITHMETIC (every control rect
    re-derived from the constants: all within 1024x640, non-layered
    chrome pairwise disjoint, the designed layers -- felt, logo
    watermark, card slots, per-seat clusters, own-seat bet chips --
    recorded as layers); the suite's check-stack-size gate now holds
    the WINDOW to the budget (its SKIP entry is GONE) and, since
    2026-08-16, tools/check-table-layout.py re-runs that whole rect
    arithmetic off THIS file on every push -- it began as a scratchpad
    script that ran once and was never committed, which made the claim
    above true and unrepeatable. The confirming eye is the OXT pass's.
  * HARNESS section 20 (heTestLivenessRun): timeout verdict + forced-post
    prescriptions (pure), the redial backoff schedule (pure), the
    next-hand occupant rule, the seq 10..13 wire-format pins (timeout
    act/bid, stand, sit-return) + the hello trim frame, a full netsim
    hand with a backdated clock (host emits, both sides verify + fold,
    miss counting, bank consumption, auto-sit-out, instant sit-out
    timeout, stand/return round-trip), a THIRD context late-joining to
    identical fold state, and the redial-vs-election ordering sim.
    Named SKIPs for the live legs.

v0.22.0 -- Phase 4d VOID-AND-AUDIT + Phase 4e ADVERSARIAL BOTS (spec 7.3 /
12.4) + Phase 5 DLEQ PROOFS (spec 7.4) on SodiumXT ABI 9. kHeHarnessV
36 -> 37. All pure compute (H5) -- still nothing wired to a played hand.
Verified statically; the sx* DLEQ calls (sxRistrettoScalarMultBase / Add /
ScalarMultBatch / ScalarAdd / ScalarMul) have never run on an engine.
  * RECORD FORMATS PINNED (spec 6 body conventions; twinned in
    protocol-kat): shuffleStep body "pos=<P>,ck=<64hex|empty>,
    deck=<52x64hex |-joined>" -- ck is the DLEQ commitment key k*B,
    required under a dleq=1 config, legal-empty below it; unmaskStep body
    "pos=<P>,slot=<S>,val=<64hex>,proof=<192hex|empty>" -- proof is spec
    7.4's reserved field, filled at Phase 5. Audit reveals: one line per
    contributor, "<pos> TAB <kHex> TAB <sigma comma-list>".
  * THE 4d MACHINE (heL2Void*): a pure, transport-agnostic state machine
    over one hand's deal -- strict shuffle-step order; an identical
    re-post of the applied record is a harmless "dup" (the state never
    moves), a DIFFERENT one is signed equivocation, named; the free
    public checks run per record; unmask chains per slot in owner-aware
    contributor order; a completed public chain resolves its card or
    voids. Attribution is DIRECT (named=pos) when the record itself is
    refusable, DEFERRED (named=audit) when only the reveals can say
    whose step lied (final-not-in-table). heL2VoidAudit runs the
    MANDATORY full-reveal audit in the mandatory order -- ck binding +
    shuffle re-verification per contributor, then every opened chain in
    slot order -- and names the FIRST bad signed step; a recorded
    staller keeps the name only when everything signed re-verifies. The
    outcome line is "void|<why>|named=<n|audit>|bets-return|
    reveal-required": bets always return, the reveal is always owed
    (spec 7.3 -- the hand is void, so it costs nothing).
  * THE 4e BOTS (harness section 19, spec 12.4): deck-stacker (vs L0 --
    heAuditDeal names a stacked delivery and a re-chosen seed),
    duplicate-point shuffler, rollback replayer, wrong-scalar unmasker
    (chain completes outside the table -> the audit names its step),
    deal staller. Every attack DETECTED and ATTRIBUTED, every verdict
    string pinned twice: protocol-kat's l2v_ and l0_ scenario keys
    (driven by its independent RFC 9496 reference) and re-checked here.
  * PHASE 5 DLEQ (heL2DleqProve / heL2DleqVerify / heL2CommitKeyHex):
    Chaum-Pedersen over ristretto255 -- prove P2 = k*P1 for the k behind
    ck = k*B without revealing k; an unmask step proves (k, stepOut,
    stepIn), since out = k^-1*in <=> in = k*out. DERANDOMIZED nonce (the
    RFC 6979 / EdDSA pattern: w hashes the secret + statement under
    kHeDomainL2DleqW), so the whole proof pins from fixed scalars;
    challenge c under kHeDomainL2Dleq over the LOWERCASED hex transcript
    (ck|p1|p2|a1|a2); proof = a1||a2||z, 96 bytes (spec 7.4's size).
    Every scalar is REDUCED mod L via ScalarAdd-zero before any point
    mult -- libsodium masks bit 255 inside scalarmult while the KAT
    reference reduces mod L, and reducing first pins both sides -- and a
    non-canonical z in a received proof is refused, never quietly
    reduced. The verifier rides c*ck and c*P2 through ONE
    sxRistrettoScalarMultBatch crossing (one scalar, two points --
    exactly the batch shape; z*B and z*P1 have different bases and
    cannot join it). On a dleq=1 machine a wrong unmask is refused
    INSTANTLY with direct attribution (spec 7.4's "impossible rather
    than attributable"); a missing ck or proof is itself a named
    refusal. Soundness is pinned NEGATIVELY: wrong secret, swapped
    points, tampered commitment, and the honest procedure over a FALSE
    statement (the wrong-scalar unmasker's only available forgery) all
    verify false -- the last via equation 2, the step-value binding.
  * heL2HasDleq: cached ABI-9 probe (the heL2HasRistretto pattern -- the
    first sxRistrettoScalarMultBase touch throws on a pre-ABI-9 build
    and the catch IS the detection); the harness SKIPs the DLEQ half by
    name below ABI 9 and still runs the 4d machine on ABI 8.

v0.21.0 -- 2e REMAINDER (street ckpts, show/muck, online History) + the
Phase 3 DECK ORACLE (spec 7.2, Level 1). kHeHarnessV 35 -> 36; kUIVersion
13 -> 14 (lobby host-mode toggle; the create row re-spaces to four buttons).
Everything below is verified statically; the multi-machine passes are the
exit gates (three machines for the oracle, + live tor for an onion oracle).
  * STREET CKPT WIRES (spec 6, the 2e deferral): at each boundary (deal /
    flop / turn / river / showdown) every seated client emits a ckpt wire
    -- body "street=..,head=..,sig=.." over the exact chain head the
    boundary's TRANSITION wire produced, so every client records the same
    head and any verified ckpt naming a different one is logged as
    CKPT-FORK evidence (attributable equivocation), never folded as
    agreement. Presence-guarded per street like every react emission.
    Consumed on replay: the "s?" resync frame now carries the requester's
    applied seq and heNetReplayLogTo replays only the wires PAST it -- a
    mid-hand client resumes from its last applied wire (at worst the last
    street boundary) instead of eating the whole log from genesis; a bare
    "s?" (pre-2e) still gets the full replay, and a rebuilt reconnecting
    client still needs one. Wire + body + chain pins in protocol-kat
    (ckpt_body/ckpt_head7); the netplay sim asserts both seats checkpoint
    the same heads and that a caught-up peer's trimmed replay is
    marker-only.
  * SHOW/MUCK WIRES (spec 6/8.1, the 2e deferral): the showdown display
    choice as first-class wires -- "show"/"muck", body "seat=N", from the
    seat's own key, emitted after the verified settle. Display ONLY, by
    construction: online ranks derive from the revealed seeds, so a muck
    hides nothing from the audit, only from the felt. As-built policy: a
    contested seat with a non-negative delta SHOWS (a claimed pot is a
    shown hand), a contested loser MUCKS, an uncontested winner MUCKS (no
    obligation on a fold-win), earlier folds emit nothing (they already
    mucked face-down). heNetShowdownShow now reveals only OUR cards at
    settle; each other seat's cards appear when ITS show wire folds
    (heNetShowSeat, seed-derived, never a claim). The History fold
    annotates "(mucked)" on the audited showdown line. Pins: show/muck
    bodies + wire heads in protocol-kat (show_head8/muck_head9), the fold
    annotation in fold-kat + heTestFoldRun.
  * ONLINE HISTORY FOLDING (the 2d deferral): heNetLogToHotseat translates
    the signed wire chain into the 4-field hotseat-shaped transcript the
    History panel already folds -- sit wires become the cfg seats/stacks,
    pubkeys become seat names, sealed holeDeliver wires are re-derived
    from the revealed seeds (the same truth the live audit used), show/
    muck ride along ahead of their settle. heHistRefresh now folds an
    online chain through the SAME heFoldTranscript + heAuditDealsFromLog
    path as hotseat, labelled as translated; the netplay sim pins a
    2-hand translation end to end (settle-verified, 2/2 deals verified).
  * DECK ORACLE (Phase 3, spec 7.2): "Host: ORACLE" in the lobby makes the
    same stack host the table and play NO seat -- the Level 0 deal
    relocated behind the oracle role. level=1 in the signed cfg IS the
    oracle marker (spec 7.2 is Level 1); dealLevel carries level=1,
    dealer=0. The oracle contributes its own committed seed at position
    dealCount+1 (players' entropy still commits the shuffle -- the oracle
    seed was committed before it saw anyone's, so the oracle cannot stack
    -- and the oracle holds no cards: no seat, no holes, no stack, no
    receipt signature; it does emit its audit verdict, logged as "oracle").
    Hole delivery rides the EXISTING sealed path, just authored by the
    oracle key; seedSeals seal to the oracle's session box. Over either
    transport via the 2f seam; an onion oracle derives its service seed
    under kHeDomainOracle (recorded above). Joiners see "ORACLE table" on
    the lobby table line. A pre-oracle client refuses the hand readably at
    its dealLevel gate ("unsupported deal level 1") -- downgrade refusal.
  * HOST ELECTION (spec 9, the slice Phase 3 needs): oracle loss IS host
    loss by construction -- the oracle occupies the host role, so ONE path
    serves both. A client that sees no host-countersigned wire for 60 s
    during play (kHeHostLossTicks; wire-silence is rp1's only honest
    signal -- the onion transport also routes its positive stream-death
    here) declares the host lost: the in-flight hand VOIDS (bets that
    never reached a verified settle never moved stacksBy, so the stacks
    already stand at the last receipt), and every client independently
    names the SAME successor -- heElectHostOf, the lowest pubkey among the
    live seated players (deterministic, no round trips; the oracle, never
    seated, is never electable). The LIVE handover -- the elected host
    re-hosting, peers re-joining -- is exactly the Phase 3 exit gate;
    today the successor is NAMED and the client fails closed with the
    recovery spelled out. Pinned: elected_host in protocol-kat; the
    oracle-table sim silences the oracle and asserts both clients agree.
  * HARNESS section 18 (heTestOracleRun) drives an oracle-hosted hand
    headlessly through the REAL handlers on three loopback contexts
    (heTNetPump grew a third seat): the oracle deals sealed holes it
    cannot read, the no-seat invariant holds everywhere, a fold-win hand
    settles with receipts co-signed by the SEATS only, the oracle's seed
    reveals at position 3 and its audit passes -- then the oracle goes
    silent mid-hand-2 and both players elect the same successor and void.
    The LIVE three-machine round (two players + a non-playing oracle on an
    onion address, killed mid-hand) is SKIPped by name: it is the exit.

v0.20.0 -- ONION TABLES (Phase 2f, spec 10): the same envelopes, the same
game, over OnionXT streams -- only the byte transport swaps, exactly as the
plan's framing promised once 2c was honest about its transport seam.
kHeHarnessV 34 -> 35; kUIVersion 12 -> 13 (lobby transport toggle + tor line).
  * THE SEAM, as-built: 2c/2d had already funneled every outbound payload
    through four senders (heNetSendToHost / heNetBroadcast / heNetSendWireTo
    / heNetReplayLogTo, each with the netCap capture branch) and every
    inbound frame through ONE router (heNetOnMessage) -- what was missing
    was only that each sender ended in a hard-coded btRp1Send. 2f adds
    heNetTxTo, the one live byte-out seam, routing by gGame["transport"]
    ("rp1" | "onion"): over onion streams each payload goes out as ONE
    LF-terminated wire line (LF framing is safe by construction -- every
    free-text field is hex-encoded into the frame, so no payload can carry
    an LF). Inbound, the stream callback only STASHES bytes; the poll tick
    reassembles complete lines per stream and dispatches them through the
    SAME heNetOnMessage router rp1 events take (H2: all net work on the
    timer; the OnionXT callbacks are stash-only). The envelopes, the chain,
    the fold, and the react engine change NOT AT ALL.
  * THE HANDSHAKE: rp1 carries the signed admission token in its transport
    handshake event; an onion stream has no such event, so the token rides
    the stream's FIRST wire line instead (the "h" frame -- new transport
    class beside "c"/"w"/"r!"/"s?"). Verify-or-drop BEFORE any reply: a
    stranger's dial earns nothing, not even the host's identity. The host
    answers a verified hello with its OWN hello (the stream is ordered, so
    the joiner adopts the host key before the replayed wires reach it),
    then the shared heNetOnHandshake path runs -- admission, replay,
    roster -- identical to rp1's.
  * ADDRESS + INVITE, the spec-10 as-built decisions: the service seed is
    H("HOLDEM-ONION-v1|" || idSeed || "|" || table) -- SECRET-keyed by the
    host identity seed (an invitee holding the table code cannot derive the
    service key and impersonate the table endpoint), fresh per table, and
    DETERMINISTIC, so a crashed host republishes the SAME .onion and the
    invite outlives the restart (spec 9). The address is derived OFFLINE at
    create time (sxSignKeypairFromSeed -> oxAddressFromPublicKey; a v3
    address IS the service's ed25519 pubkey) so the invite exists
    immediately, and the published address is cross-checked against it when
    the descriptor uploads. The invite extends compatibly:
    "<64hex>@<56base32>.onion" -- ONE word, deliberately NOT hex, so a
    pre-2f stack's `word 1` + heIsHex gate refuses the whole invite with
    its readable message instead of silently joining a DHT table nobody
    announced (downgrade refusal by format; heJoinRefusal is the pure,
    dependency-injected gate the harness drives both ways).
  * ASSUME-RUNNING TOR, FAIL CLOSED (the nocloud pattern): stock ports
    (SOCKS 9050, control 9051), no port scan, no silent fallback to the DHT
    transport in either direction. The lobby gains a "Host over: DHT/Tor"
    toggle (gCfg["transport"]) and a tor status line walking the quickshare
    pill states (library missing / connecting control / bootstrapping N% /
    publishing / dialing / ready / FAILED-with-reason). Every silent async
    wait has a watchdog (kHeOnionCtlTicks/BootTicks/PubTicks/DialTicks) and
    every ox* call sits in its own try with declared catch locals (H8).
    Streams and the service are closed on leave/stop (H1); the control
    connection deliberately stays up between tables and is oxShutdown on
    closeStack (gOxCtlUp).
  * HARNESS section 17 pins the headless slice: invite parse/build round
    trips both transports (+ five refusal vectors), the pure heJoinRefusal
    downgrade refusal, onion-seed determinism/keying, the OnionXT address
    round-trip (oxAddressFromPublicKey <-> oxPublicKeyFromAddress, gated
    SKIP without OnionXT or pre-ABI-7 SodiumXT), and the "h" hello driven
    through the REAL router on netCap loopback contexts -- verified hello
    admits + replies + replays in order, garbage/wrong-table hellos earn
    nothing, the player adopts the host from its hello. The LIVE multi-hand
    onion table session (two machines + a running tor daemon) is the
    engine-era exit gate and is SKIPped by name.

v0.19.0 -- Phase 4a-4c COMPUTE layer: the Level 2 ristretto255 mental-poker
deal algebra (spec 7.3), pure handlers only, on SodiumXT ABI 8's sxRistretto*
surface (Workstream U, shipped 2026-08-15). kHeHarnessV 33 -> 34.
  * NEW heL2* SECTION (values in, values out -- H5; nothing here touches a
    played hand, the UI, or the wire): card base points by domain-separated
    hash-to-group ("HOLDEM-L2-CARD-v1|" & cardName through sxHash(...,64) ->
    sxRistrettoFromHash); one full shuffle-mask step (out[j] = k *
    in[sigma[j]], 52 scalar mults, deal-time only); the FREE duplicate check
    (identical points in a masked deck are publicly visible); public and
    hole unmask-chain verification (last value must hit the 52-point table;
    the hole's penultimate value is public and CDH-useless to non-owners);
    and reveal-scalar showdown re-verification (shuffle step + unmask steps
    recomputed from a revealed (k, sigma)).
  * EVERY SEAM IS LOWERCASE HEX TEXT (the H6 corollary): raw Data exists
    only inside expressions passed straight into sx* calls; decks are
    52-item comma lists of 64-hex points, sigma a 52-item comma list of
    indices, chains comma lists with the masked table point first.
  * FAILURES ARE DISTINCT "void:..." STRINGS, never throws (every sx*
    call sits in its own try, H4/H8): scalar-format / point-format / invalid-point /
    identity-point (libsodium reports zero-scalar and identity results as
    ONE failure -- the sxRistrettoScalarMultPoint throw IS that detection) /
    deck-size / perm-size / perm-format / duplicate-point / chain-short /
    final-not-in-table / hole-not-in-table / shuffle-mismatch /
    unmask-mismatch / scalar-zero / no-ristretto -- so Phase 4d's
    void-and-audit attribution can NAME the condition. sigma is validated
    for range only, deliberately not distinctness: a repeated index
    duplicates an OUTPUT point, which the public duplicate check catches on
    every client (spec 7.3: prevented, not just detected).
  * KAT-PINNED END TO END from fixed scalars in tools/protocol-kat.py (the
    Phase 4 exit criterion): l2_* mirror twins driven by the file's
    independent RFC 9496 ristretto reference pin the base deck, a 3-seat
    mask/shuffle round, both chain kinds, the showdown re-verification, and
    seven refusal cases (24 new pinned values); heTestLevel2Run re-checks
    the same constants on-engine, gated like every sodium section PLUS a
    cached ABI-8 probe (a pre-ristretto SodiumXT throws "can't find
    handler" on first touch -- caught, reported as a SKIP, never an
    uncaught engine error).
  * NOT HERE (engine-era, plan 4d-4f): wire vocabulary and orchestration,
    void-and-audit sequencing, the adversarial harness bots, and the
    deal-time FFI-burst budget measurement. The sx* call shapes themselves
    are verified statically; the whole section needs an OXT pass.

v0.18.0 -- reconnect + adversarial hardening (the single-machine half of 2e,
chosen because it is exactly what real-network play will stress first).
kHeHarnessV 32 -> 33.
  * DETERMINISTIC PER-HAND SEEDS (spec 7.1 as-built): a seat's deal seed is
    now H("HOLDEM-SEEDP-v1|" || idSeed || table || hand) -- secret-keyed by
    the identity seed, fresh per hand (the hand number is in the input), and
    RECONSTRUCTIBLE: a client that crashes and rejoins re-derives the exact
    seed it committed, so it can still seal and reveal instead of wedging
    the hand's audit forever (the old sxRandomBytes seed lived only in RAM).
  * REPLAY-PROOF EMISSIONS: every react emission now carries a PRESENCE
    guard against the folded transcript (commit/seal/reveal/receipt/audit/
    join skip themselves when the chain already carries them), the dealer
    re-derives its deck after a reconnect without re-sending deliveries the
    transcript already holds (per-seat presence), and board wires dedupe by
    street-vs-count on fold -- a redelivered or reconnect-burst flop can no
    longer append twice and shift every later board slot.
  * CATCH-UP SUPPRESSION (the Codex review find on PR #39): react used to
    fire after EVERY replayed wire, against chain states that predate the
    client's own historical messages -- the presence guards saw an
    incomplete transcript and re-emitted join/commit/seal/reveal for every
    hand replayed, and the host sequenced all of it onto the live chain.
    heNetReplayLogTo now PREFIXES the replay with an unsigned "r!" control
    frame carrying the head seq (same transport class as "s?", honored only
    from the host's live handle so a stranger cannot suppress a victim);
    the client stays silent until its applied seq reaches the mark, then
    reacts ONCE against the complete transcript. A lost marker degrades to
    the old noisy behavior -- it can never wedge. The sim asserts the
    replay adds ZERO wires to the chain.
  * THE NETPLAY SIM NOW CRASHES AND RECONNECTS THE PLAYER MID-HAND: its
    context is rebuilt from nothing but its keys + identity seed, the host
    replays the whole signed transcript (heNetReplayLogTo, now behind the
    capture seam too), and the rebuilt client must converge byte-for-byte
    (chain head, seat map, stacks, mid-hand street, re-opened sealed holes)
    AND finish the hand to a clean showdown.
  * ADVERSARIAL PROBES, through the real ingest path on throwaway context
    copies: an out-of-turn act (host-signed, correctly sequenced -- engine-
    rejected on fold), a junk sealed holeDeliver (logged drop, holes stay
    unset, never a throw), a seedReveal that breaks its commitment (named,
    never stored), and a HOST SETTLE THAT LIES (refused outright: no chips
    move, the hand does not complete). The security branches are now pinned
    behavior, not desk-checked claims.

v0.17.3 -- the report gets its OWN scrolling panel (heReportShow: full-size
field + Close, built on first use so it layers above every overlay, no
kUIVersion bump needed). Even the CORRECT msg-container put displays
nothing on OXT when the message-box palette is closed -- the report
"vanished" while the lobby's net field (the live wire feed, which updates
on every wire during the netplay section) looked like the output. The
panel always shows the whole report; the clipboard copy stays.

v0.17.2 -- fix v0.17.1's report delivery: "put gRpt into the message box"
THROWS on OXT -- the message box CONTAINER is the single token "msg" (the
dictionary's prose name is not the compilable token, gotcha 13's family).
Now "put gRpt into msg". New static-gate check 12 flags the prose form so
it can never ship again; CLAUDE.md gotcha 13 carries the lesson.

v0.17.1 -- harness QoL: the self-test report now lands EXPLICITLY in the
message box AND a full copy goes to the clipboard, with a closing line
saying so -- a run floods the status/lobby fields with live lines and the
bare put was too easy to lose behind the stack window, which made the
whole-report read (the point of the harness) a scavenger hunt.
kHeHarnessV 31 -> 32.

v0.17.0 -- ONLINE PLAY (Phase 2d): full Level 0 hands over the signed wire
chain. The game is now literally the spec-4 design: every client folds the
same wires into the same gGame["state"] the hotseat UI already renders, and
a react engine (heNetGameReact) emits only what OUR seat owes next, each
emission behind a per-hand sent-flag so rp1 redelivery and catch-up replay
never double-send. kHeHarnessV 30 -> 31; kUIVersion 11 -> 12 (Start Game).
  * WIRE VOCABULARY (spec 6, as-built bodies): join binds each player's
    per-table session box pub ON the chain (the signed contentLine IS the
    spec-5 binding tuple); host sit wires assign seats (ascending-pubkey
    order); handStart/dealLevel open a hand with dealer = the button seat.
  * THE DEAL (spec 7.1, for real this time): seedCommit from every dealt
    seat -> seedSeal (the seed sealed to the dealer's box, kept on-chain so
    the transcript stays self-contained) -> the dealer opens, verifies every
    commit, derives the committed deck, and delivers each seat's holes in a
    sealed box -> blinds and betting as self-signed wires through the same
    pure engine (the BB posts only after it SEES the SB fold, so forced bets
    cannot race the relay) -> dealer board wires per street -> at hand end
    every seat reveals its seed and every client re-derives deck/holes/ranks
    from the reveals -- nobody can lie about a showdown.
  * SETTLE/RECEIPTS/AUDIT: the host's settle wire is verified against every
    client's own heSettleOf recomputation BEFORE folding (a mismatch is
    refused and flagged, never followed); receipt wires carry the spec-8.3
    co-signatures over a head that chains hand to hand; every client emits
    its audit verdict (commits + wired board + its own delivered holes vs
    the derived deal).
  * THE LOBBY CFG now carries ante + stack (the full stakes fold from the
    signed cfg on every client; protocol-kat pins regenerated); online
    stacks seed from the cfg, never from a parked hotseat game.
  * UI: action buttons emit wires online (only the seat to act may send);
    the prompt is only ever ours; a host-only Start Game button seats the
    joined players and deals hand 1; between-hands the host auto-kicks the
    next hand on the usual pace beat.
  * HARNESS: heTestNetPlay drives TWO complete hands host<->player on one
    machine through the real handlers (real sxSeal roundtrips), via a
    capture seam on the send path (gGame["netCap"]) -- a scripted fold-win
    with deterministic deltas, then a checked-down showdown asserted on
    invariants: five wired board cards, chip conservation, cross-wire stack
    agreement, an advancing receipt chain, clean audits on both seats.
  * Deferred to 2e with liveness: act timers, sit-out/reconnect mid-hand,
    street ckpt wires, show/muck display choice, late-join seating, online
    History folding (the live audit verdicts land in the net feed).

v0.16.0 -- casino sounds (Kenney "Casino Audio", CC0). 11 sounds vendored as
16-bit mono WAVs in assets/sounds (the upstream OGGs are not engine-playable;
converted at vendor time, rate untouched). One playback gate (heSndPlay): config
toggle -> lazy import-once (heSndTryInit imports each WAV as an audioClip; clips
persist inside a saved stack, so the saved stack carries its own sounds) -> a
rotation counter alternates kinds with two takes -> guarded play audioClip.
Wired at message boundaries only: deal (cardSlide) in heUIHandStart, street
(cardPlace) in heUIShowBoardStreet, accepted actions in heEngineDo's act case
(fold=cardShove, check=chipLay, call/bet/raise=chipsHandle, allin=chipsCollide)
-- the ACCEPTED path only, so a rejected action stays silent and remote peers'
actions will sound identical when the transport lands -- and settle (chipsStack)
in heHandSettle. cardShuffle is vendored + mapped but deliberately unwired (3 s;
the deal-animation increment paces it before the first deal). New Settings toggle
"Sounds: On/Off" (gCfg["sounds"], default on; turning it on plays a confirmation
chip as a live test). heProbeSounds prints the resolved folder + per-file
file/clip/ok state; heSndReload re-imports after moving files. Every engine call
is guarded (H8 catch locals): a missing folder, file, or an audio-less engine
degrades to silence, never a broken deal. tools/sounds-kat.py pins the vendored
WAVs (RIFF/PCM16/mono/44100, sane durations) against the stack's kHeSoundFiles
list and the heSndFilesFor mapping, in CI. kUIVersion 10 -> 11 (new Settings
button). Playback itself: verified statically; NEEDS AN OXT PASS.

v0.15.0 -- fold of the two outstanding review branches (PRs #25 + #33), rebased onto
the v0.14.1 fixes so nothing already merged is lost. kUIVersion 9 -> 10 (the bet
slider control changes style, so saved chrome rebuilds); kHeHarnessV 29 -> 30 (the
netsim section gains reorder/duplicate vectors).
  * ONLINE: THE CHAIN-BREAK RESYNC STORM IS FIXED (PR #25, seq-classified wires).
    rp1 is lossy AND redelivers/reorders, but heNetIngestWire treated every
    duplicate as a chain gap: each redelivered wire triggered another full-
    transcript replay, whose own replayed wires re-triggered it, so the client
    resync-looped forever and an online game never started. A verified wire is now
    classified by its host-signed seq against gGame["lastSeq"]: seq <= lastSeq is
    an already-applied duplicate -> dropped SILENTLY; seq = lastSeq+1 must chain
    onto the head and is applied (heNetApplyWire), then any buffered successors
    drain behind it (heNetDrainBuffer); seq > lastSeq+1 is a real gap -> the wire
    is HELD in a bounded reorder buffer (heNetBufferWire, kHeWireBufMax) and one
    debounced replay is requested. The table/version binding and the host-authority
    fold of roster/cfg bodies (both v0.14.1 hardening) are enforced before / inside
    apply exactly as before -- and dedup makes the full-log replay idempotent: a
    caught-up client just sheds the replayed prefix instead of storming. The netsim
    section now drives reorder, cascade-drain and duplicate vectors through the
    real handlers.
  * DYNAMIC PROPERTY NAMES REMOVED (PR #33, the big syntax find). v0.14.0 stored
    avatar paths in per-seat props via the parenthesised computed-name form, which
    is NOT portable xTalk: property names are compile-time tokens, and the dynamic
    form is engine-shaky on OXT. Replaced with ONE uHeAvatarPaths property, line N
    = seat N's path: plain line-chunk syntax, and paths cannot contain a newline.
    New house rule H9 + static-gate check 11 flag the form so it can never ship
    again. (A previously saved stack's per-seat paths are orphaned -- avatars
    re-pick once; acceptable pre-OXT-pass.)
  * BET SLIDER is now style "scale" (a real slider: no arrow chrome), the drag
    handler uses its documented pNewPos parameter, track clicks step by one big
    blind (page = 4 blinds) via lineInc/pageInc, and the scrollbarLineInc/LineDec/
    PageInc/PageDec messages sync the amount box on a deferred send THEN pass --
    never swallowing the engine's default thumb move.
  * IMAGES ASPECT-FIT (PR #33). Setting an image's filename resets the control to
    the picture's natural size; v0.14.0 re-rected after (correct) but into a
    square, stretching non-square pictures. Both avatar and logo now aspect-fit
    via formatWidth/Height (new pure heFitRect), letterboxing on the disc / felt
    instead of distorting.
Plus a four-agent full-file review; the verified findings, all fixed here:
  * H1 LEAK: Settings -> Apply (and the game-over auto-reset) called heTableNew
    while ONLINE, emptying gGame with the TorrentXT session still running -- the
    poll loop died, and Leave/closeStack became no-ops (flag and handle gone), so
    the session was unstoppable and a re-create forked a second one. heTableNew
    now heNetStop's first (a no-op for hotseat).
  * ONLINE LOG CORRUPTION: Settings/History dismiss the lobby overlay without
    restoring it, leaving Deal clickable while online -- a hotseat hand then
    appended raw 4-field lines into the signed wire log, which heNetReplayLogTo
    shipped to every joining peer as junk. heHandStart now refuses to deal while
    online (heHudRefresh also keeps the button disabled).
  * CHIP MINTING: a typed fractional amount ("2.5" is a number) flowed through
    heBetApply into heSettleOf's div/mod accounting, where a fractional remainder
    hands a whole chip to EVERY winner -- chips minted, stacks fractional forever,
    and the replay audit blessed it (it re-derives the same wrong payout). Fixed
    at BOTH ends: the shell truncs the box, and heBetApply rejects non-integer /
    non-numeric wagers (act-bad-amount; a non-number previously THREW mid-
    arithmetic). Pinned in betting-kat case_bad_amounts + heTestLegalRun.
  * REPLAY-AS-AUDIT HARDENING: duplicate bidSB / bidAnte posts (phase stays
    "blinds" until the BB, so repeats replayed clean and audited clean) and
    antes from seats outside the hand are now engine-rejected (sbPosted /
    antePostedBy flags; betting-kat case_duplicate_posts). A truncated or
    hand-edited transcript reaching a contested settle with a short/garbage
    board or hole list is named settle-bad-cards and skipped (new heIsCardList
    guard) instead of THROWING mid-fold and killing the whole History audit.
  * SPEC 6 UNKNOWN-FROM: inbound wires never checked the sender against the
    host-signed roster, so a malicious host could sequence a never-seated key.
    heNetApplyWire now marks unrostered senders and folds NOTHING from them
    (the chain link itself is host-authentic and still advances -- wedging the
    table on it would only punish the honest client). heHostEmitRoster is now
    exercised by the netsim, which also pins the ghost-sender case.
  * HARNESS SELF-PROTECTION: a mid-section throw (netsim above all) used to
    leave the user's REAL gGame replaced by the section's synthetic context;
    heRunSection now snapshots gGame and restores it in its catch. Copy-invite
    fixed to test online-ness (heTableNew fills tableIdHex for hotseat too, so
    the old empty-check handed out a dead code a joiner would wait on forever).
    Game-over reset now clears the finished game's cards. Saved-stack reopen
    rehydrates the runtime state the version-match exit skipped (gSlotCenter
    from the controls' locs, avatar caches, logo fit, kit probe) -- kit mode
    used to be silently unrecoverable after a save/reopen because heKitReload
    pooled zero sprites from the empty slot map. The backs sheet now probes its
    OWN frame-name suffix and width (gotcha 24 is per-sheet); the kit-init
    catch records WHY it dropped to flat (gKitLastErr, shown by heProbeKit).
    Time-based tournaments now show their level in the header (was hands-mode
    only). Mirror-drift gaps closed both ways: BB-option raise, out-of-turn,
    the second reopen probe, burns, the losing showdown name, the ante fold
    transcript, and a REAL draw-bounds loop now run on-engine; the short-SB-
    ante P0 pin and a level-count pin now run in betting-kat. Harness sections
    renumbered 1..14 in run order (two claimed "2b"). heShuffleDeck clamps a
    sub-1 state (MINSTD has no 0 state; the mirror wraps where the engine
    yields 0 -- latent divergence, now clamped identically on both sides).

v0.14.1 -- bug-fix pass. Six defects found by review; the first two are gameplay-
visible, the rest are correctness/robustness. No new controls, so kUIVersion stays 9
(a saved v9 stack keeps its chrome); kHeHarnessV 28 -> 29.
  * POT / 1/2 POT OVER-SIZED EVERY RAISE MADE FACING A BET. heQuickAmount computed
    raiseTo = betCur + owe + potAfterCall, but betCur ALREADY equals streetBy + owe,
    so the call was counted twice. Blinds 1/2 folded to the button: Pot offered a
    raise to 9 where a pot-sized raise is 7 (and 1/2 Pot offered 6 for 4). With
    owe = 0 -- opening a street -- the extra term vanished, which is why the
    opening-bet case always looked correct and this survived. The sizing is now a
    PURE handler, heQuickAmountOf(state, seat, kind) (H5), so it is pinned in
    tools/betting-kat.py (case_quick_amounts) and on-engine in heTestLegalRun
    instead of being eyeballed; heQuickAmount is a one-line gGame wrapper.
  * THE TABLE WENT BLANK FOR THE WHOLE RUNOUT AND SHOWDOWN. heCurrentPot,
    heHandByOf, heSeatFace, heHeaderTxt and heHudRefresh all gated their reads of
    gGame["state"] on phase "hand" -- but the paced beats that follow betting are
    phases "reveal", "runout" and "showdown". So from the moment betting closed:
    the pot read 0 and its chip vanished, every seat showed its pre-hand bankroll
    instead of chips behind, street bets and the SB/BB badges disappeared, and the
    FOLDED / ALL-IN markers went blank -- for the entire all-in runout and the 2.9 s
    showdown hold. Worse, heUIShowdownReveal writes "WINNER" into the seat state
    fields and the very next 4 Hz HUD tick (<= 250 ms later) cleared it, so the
    winner was never actually readable. New heHandLive() names the live set
    (hand / reveal / runout / showdown -- deliberately NOT "between", where the
    deltas are already in gGame["stacksBy"] and handBy would double-count), and
    heSeatFace now leaves a WINNER badge alone through the showdown and the result
    pause; heUIClearCards still clears it when the next hand is dealt.
  * GOING ONLINE MID-HAND CORRUPTED THE SIGNED TRANSCRIPT. heTableCreate/heTableJoin
    empty gGame["log"] and refill it with signed wires, but the hotseat hand runs on
    timer sends that only gate on gGame["phase"] -- which they left untouched. Press
    Lobby -> Create during a hand and the pending heSettleStep / heNextHandTick still
    matched their phase: they fired into the online table, appended raw 4-field
    hotseat lines into the wire log, and heNetReplayLogTo then shipped that junk to
    every joining peer as "w" frames. New heNetParkHotseat (called by both) sweeps
    the paced sends and drops the phase to "idle" so a send that already escaped the
    sweep hits its own stale-guard.
  * THE POLL LOOP COULD DIE SILENTLY. heNetPollTick guarded the per-event dispatch
    but not the drain itself, so a throw out of btRp1Poll/btPoll (stale session
    handle, extension fault) escaped the handler, skipped the re-arm, and killed the
    250 ms loop with no error anywhere -- online play simply stopped receiving. Both
    drains are now in their own try and the re-arm really always runs (H4).
  * HISTORY CLAIMED "AUDIT PASSED" OVER AN UNAUDITED TRANSCRIPT. heHistRefresh folded
    gGame["log"] unconditionally, but online that log holds 10-field signed wires,
    not 4-field hotseat lines: every line fell through heFoldTranscript's switch, so
    the fold returned no history AND no errors -- which the panel read as a clean
    audit. It now gates on heLogIsCleanHotseat (the predicate that already existed
    for exactly this, used by Leave) and says what is actually there.
  * ITEMDELIMITER LEAKS (gotcha 5). heStackFolder returned with it set to "/" and
    heSwapExt with it set to "." -- heKitTryInit's early exit on a missing atlas
    returned to its caller carrying a foreign delimiter. heTestEvaluatorRun left it
    as "|" for the next harness section. All three now save and restore.

v0.14.0 -- UI polish pack (local, hotseat-first -- online avatar/logo delivery to
peers is the next increment). Four additions, all pure-engine, gated behind kUIVersion
9 so a saved v8 stack rebuilds its chrome on next open:
  * SEAT AVATARS -- each seat gets a round portrait at the left of its name plate.
    Click it to pick an image (answer file -> the filename of an image control, so no
    image BINARY ever crosses into script -- H3/H6 safe); the path persists in a
    uHeAvatarPathN custom prop. No picture -> a coloured disc with the seat's initial,
    so an unset seat still looks intentional. heSeatAvatarRender picks image vs initial;
    gAvatarOn[seat] caches which so the 4Hz HUD toggles visibility without re-loading
    the file. Three stacked controls per seat: disc (heSeatAvN), initial (heSeatAvTxN),
    image (heSeatAvImgN).
  * TABLE LOGO -- the host picks a centre-table watermark in Settings (new "Table Logo"
    button). One image "heTableLogo" created BELOW the pot/board so it never hides them,
    faint via blendLevel; path in uHeTableLogoPath. heTableLogoRender loads it.
  * ACTING-SEAT GLOW -- the acting seat's panel gains a gold ring: a constant 2px
    outline whose foregroundColor is the ring when acting and the panel colour (so it
    disappears) otherwise. Keeps the existing bg-colour highlight underneath, so worst
    case it still highlights.
  * BET SLIDER -- a horizontal scrollbar above the action row; drag to set the raise-to
    between the minimum legal raise and all-in, feeding the heAmount box the Bet/Raise
    buttons read. Shown only on a bet/raise turn (heUIPromptToAct), synced by the
    Min/1/2/Pot quick buttons. scrollbarDrag updates the amount live.
All four are visual/timed and need an OXT pass to eyeball (avatar round-crop of a picked
image wants an alpha mask; logo scale/blend; glow ring stroke; slider placement in the
thin margin). Every path degrades gracefully -- a missing file / hidden control never
breaks a deal. Static gates + KATs green.

v0.13.4 -- bigger, more legible cards. The rendered cards read small/squished, so
kHeCardW/kHeCardH grow 50x70 -> 62x84 (kept at the ~140:190 Kenney aspect so flat
glyph cards and kit sprites match) and the 5-card board re-spaces to stay centred on
the felt: kHeBoardDX 58 -> 72 (must stay > kHeCardW so cards never overlap), kHeBoardX0
404 -> 368 (= 512 - 2*kHeBoardDX). Hole-card slots now straddle the seat centre by half
a card + 2px (tSpotX +/- (kHeCardW div 2 + 2)) so they auto-space with the card size.
Both render paths key off kHeCardW/kHeCardH already -- the flat slot rect (heMakeCardSlot)
and the kit sheet scale (b2kSheetScale "heCards", kHeCardW / frameW) -- so one size change
flows to both. kUIVersion bumped 7 -> 8 so an already-built (saved) stack rebuilds its
chrome at the new size on next open; to hand-tune, edit kHeCardW/kHeCardH and set
kHeBoardDX = kHeCardW + 10, kHeBoardX0 = 512 - 2*kHeBoardDX. Verified statically; needs an
OXT pass to eyeball the final size.

v0.13.3 -- detect the Kit when its handlers are on the message path (fixes kit mode
staying OFF even with the Kit loaded). A user's heProbeKit showed the b2k* handlers
present but stack "box2dxt-kit" not loaded under that name (merged into the script /
differently-named host) -- yet heHasKit required the named stack and heKitTryInit did
an unconditional start using stack "box2dxt-kit" that would throw. heHasKit now also
accepts the Kit when b2kSheetFrames responds on the message path, and heKitTryInit only
start-uses the named stack when it actually exists. So after heKitReload the atlas
loads and the card sprites pool.

v0.13.2 -- fix a compile error in heProbeKit (v0.13.1): it used backslash-escaped
quotes (\"box2dxt-kit\") to print quotes, but xTalk has NO string escapes -- \" is a
continuation backslash plus a string-terminating quote, which breaks compilation.
Use the quote constant instead. Added a static gate (check-livecodescript check for
\") so this class is caught in future -- it was invisible to every existing check.

v0.13.1 -- kit setup debugging. heProbeKit now does LIVE checks (not the cached
heHasKit) so it reflects the current state right after you load the Kit, reports
whether the "box2dxt-kit" stack is loaded AND whether the b2k* handlers are on the
message path, and names the exact gap + the fix (the Kit is a SEPARATE stack, not
pasted into this script). New heKitReload clears the cached probe, removes pooled
sprites, and re-runs heKitTryInit -- the message-box command to run after loading the
Kit / saving the stack / moving the assets (heKitTryInit only runs at first build, so
a freshly-added Kit needs this).

v0.13.0 -- actually RENDER the Kenney card art in kit mode (against the real
Box2Dxt kit API, read from the sibling repo -- not guessed). Two things were
missing: (1) b2kSheetLoadAtlas takes the PNG path (the .xml is its optional 2nd
arg) -- the loader was passing the .xml, so the sheet never loaded; fixed, and it
now passes PNG + sibling .xml explicitly. (2) Nothing drew sprites: the display
path still wrote flat glyph fields. Now heKitTryInit resolves the frame ".png"
suffix at load (b2kSheetHasFrame -- gotcha 24), scales the sheet to the slot width
(b2kSheetFrameSize), pre-warms every face, and POOLS one bodiless b2kSpriteNew over
each card slot; heUIShowCardIn swaps the pooled sprite's frame (b2kSpriteSetFrame)
and shows it (hiding the flat field), heUIClearCards hides them between hands. Every
kit call is guarded -- any hiccup falls back to the flat glyph card, never breaks a
deal. New heProbeKit diagnostic (run it in the message box) reports Kit presence,
the resolved atlas path + existence, loaded frame counts, the suffix, UI mode, and
the pooled sprite count. Backs sheet is loaded + sized too (face-down is a follow-up).
NEEDS AN OXT PASS to confirm sprite anchor/scale/z-order; degrades to flat if not.

v0.12.2 -- auto-locate the card atlas. heKitTryInit now defaults the atlas + backs
paths to assets/cards/ sitting NEXT TO the saved stack file (heStackFolder derives
the folder from the stack's own filename), so dropping the assets folder beside the
stack just works with no path to configure. An explicit uHeAtlasPath/uHeBacksPath
still overrides; an unsaved paste-and-run stack (no folder) needs the manual path or
a one-time save. Placement documented in assets/cards/NOTICE.md.

v0.12.1 -- card backs. Vendored the Kenney "Playing Cards Pack" card-back sheet
(assets/cards/playingCardBacks.png + .xml, CC0; 15 designs blue/green/red x5) for
face-down cards, alongside the faces. Added the kHeCardBackFrame constant (default
"cardBack_red2") and a guarded backs-atlas load in heKitTryInit (via uHeBacksPath).
tools/atlas-kat.py now also pins that the chosen back frame exists in the backs
atlas and that all back rects fit the sheet. Note: Kenney's card collection has
cards/backs/jokers/dice but NO poker chips -- chips stay procedural (a colored disc)
unless a dedicated CC0 chip pack is added.

v0.12.0 -- real card art (kit mode). Vendored the Kenney "Playing Cards Pack"
spritesheet (assets/cards/playingCards.png + .xml, CC0) -- the 52-card TextureAtlas
Box2Dxt's foreign-sheet loader parses. Added heKenneyFrame, mapping each internal
card id to its atlas frame (As -> cardSpadesA, Ts -> cardSpades10), and repointed
heKitTryInit's icon pre-warm at those real frame names (the old loop warmed "7s"/
"back", which exist in no Kenney atlas and threw). tools/atlas-kat.py pins in CI
that all 52 cards resolve to frames present in the atlas and that every frame rect
fits the sheet. The atlas load path + frame ".png" suffix + the actual card-sprite
RENDER wiring (b2kSprite*) still need the Box2Dxt api-reference and an OXT pass;
kit mode falls back to the flat glyph cards until then. Point uHeAtlasPath at the
vendored atlas to enable it.

v0.11.1 -- OXT-pass fix: the History panel folded to pot 0 / settle-MISMATCH on
every hand after an online Create/Join. Root cause: the online lobby and the
hotseat game share gGame["log"], but a hotseat line is 4 tab-fields
(handNum|from|type|body) while an online wire is a 10-field signed envelope whose
3rd field is the hand number, not the type. heTableCreate/heTableJoin clears the
log and appends a wire cfg (which carries sb/bb but NO per-seat stacks); leaving
to hotseat then appended hands onto a log with no readable hotseat cfg, so the
fold seeded heBetNewHand with empty stakes/stacks, every blind was rejected, the
pot stayed 0, and the (correct, non-zero) live settle lines all showed MISMATCH.
The live game itself was always correct. Fix: heBtnLeave starts a fresh hotseat
table (clean cfg) unless the log is already a clean hotseat transcript
(heLogIsCleanHotseat), so a peek at the lobby and back preserves a running game.
Harness v28.

v0.11.0 -- deep-dive alpha-readiness audit (9-dimension adversarial review).
Fixes two shipped-path defects the KATs could not see (they mirror the pure
engine, not the impure driver): (P0) heHandStart capped the blind from the
PRE-ante bankroll while the engine validates against the POST-ante stack, so a
blind seat short after its ante had its SB/BB rejected -- dropping the small
blind or wedging the hand in tournament (ante) play; now capped from the engine
stack, pinned by new heTestAnteRun asserts. (P1) a Deal click during the
"between" result-pause left the prior hand's heNextHandTick pending, which could
auto-deal an extra hand -- heCancelPacedSteps now sweeps in-flight paced sends at
heHandStart. Online transport (lobby-only) hardened: envelope table-id/version
bound on ingest; roster/cfg folded only from the host key (relay + ingest);
per-peer "s?" replay rate-limit; heNetStop cancels the poll tick (no forked poll
loop); stale peer handle pruned on reconnect; trust-on-first-use host-key pinning
with a conflict warning; throw-safe rp1 dispatch. CI gates hardened: the vacuous
evaluator-kat antisymmetry tautology replaced with a real check, and
check-livecodescript now catches gotcha 29 (constant used above its declaration)
and gotcha 11 (local inside a block). The "provably unstackable" wording is
corrected to "tamper-evident / consistent with the revealed seeds" -- adversarial
unstackability against a cheating dealer needs independent per-player seeds
(spec 7.1 online deal), still future work. Harness v27.

v0.5.1-0.5.6 -- audit hardening + provability. A four-way audit (protocol,
pure-logic, OXT-dialect, coverage) drove: restored dropped deal KAT constants
that silently broke heTestDealRun + a new gate for undeclared k-constants;
verify-or-drop can no longer throw on a malformed frame (heIsHex before every
decode, H4); chain-gap recovery so a lost rp1 wire no longer wedges a client
(heNetRequestSync + s? replay, spec 9); tools/logic-fuzz.py proving the RULES
against independent references (exhaustive evaluator = 7462 classes + exact
category frequencies + 5/7-card order-isomorphism; peel-based settlement; whole
-game conservation). heRank5 no longer depends on a stable sort (precomputed
composite key). Auditable HAND HISTORY: heFoldTranscript emits a per-hand record
(board/pot/winner/showdown/deltas) with a re-verified settle verdict, surfaced
in a History panel with a "Copy transcript" export, independently pinned by
tools/fold-kat.py. All verified statically / by KAT; the History panel, the
heRank5 sort, and the transport need an OXT pass.

v0.5.0 -- Phase 2e: the online LOBBY. Create or join a table over the DHT and
watch the real transport work end to end -- peers admit-or-drop at handshake
(signed session tokens), the host catches every new joiner up by replaying the
whole signed wire log from genesis (spec 9 reconnect seam), and a signed,
hash-chained cfg + roster presence pair propagates to everyone so each client
verifies (or drops) it and the roster stays in agreement. The overlay shows the
live peer roster and a network-activity feed of every verify/drop verdict. The
new heTestLobbyRun section machine-checks the exact presence wires (canonical
roster body, cfg+roster chain head, verify-or-drop, out-of-order chain break)
against tools/protocol-kat.py with no network -- so CI pins the code path the
transport carries. The lobby transport itself is verified statically and needs
an OXT pass (two machines, one invite code).

v0.4.0 -- Phase 2 (online) foundation. The sxHash mystery is resolved: it
needs an OUTPUT-LENGTH argument, sxHash(data, 32) -- calling it with one arg
was the throw that blocked every earlier crypto attempt. With that fixed the
crypto seams are correct against SodiumXT's real API (sxSignKeypairFromSeed
is a command with out-params; sxSeal/sxSealOpen for hole delivery), and the
signed, hash-chained transcript envelope (spec 6) is implemented and pinned
by tools/protocol-kat.py, re-checked on-engine by heTestCryptoRun. heProbe-
Sodium / heProbeTorrent exercise the full crypto + transport surface. The
online transport wiring (rendezvous, rp1, live deal) is the next increment.

v0.3.0 -- richer chip-forward table UI (per-seat panels with names, chip
totals, bets-in-front, dealer/blind badges, folded/all-in/acting/winner
states, pot display, quick-bet buttons, suit-glyph cards) and a
dead-button-aware blind schedule (the big blind always advances to the next
live seat, so eliminations never double- or skip-charge a blind -- TDA rule
10). The math (side pots, chip conservation, min-raise, PRNG, evaluator) is
verified sound by tools/logic-fuzz.py, which checks the evaluator EXHAUSTIVELY
(all 2,598,960 five-card hands) and fuzzes settlement + whole games against
independently-written references (not the KAT mirrors) over ~90k configs.

v0.2.0 -- binary-free playable path. The first OXT passes hit repeated
double/binary conversion errors wherever script code touched FFI-bridged
binary (SodiumXT Data) through the chunk/arithmetic evaluator. This version
removes that entire class from the playable path:

  * The deal's randomness is a pure-INTEGER PRNG (Park-Miller MINSTD: only
    +, *, and mod, every product < 2^53 so it is exact in a double). It is
    seeded from sxRandomUniform when SodiumXT is present -- sxRandomUniform
    returns an integer, so no binary ever crosses into script -- and from
    engine time+random as a labelled practice fallback otherwise.
  * The transcript stores plain text; no hashing, hex, or textEncode on the
    playable path.
  * Nothing in a played hand calls sxHash / sxRandomBytes / sxBin2Hex.

The cryptographic Level 0 deal (spec 7.1: commit-reveal keyed-stream shuffle,
end-of-hand audit) is the value-path target and stays specced and KAT-pinned
in tools/, but it is deferred here until the SodiumXT surface is confirmed on
this engine -- run heProbeSodium to see exactly which sx* calls work. Wiring
it back in is a Phase-2 step behind a confirmed probe.

The pure logic -- evaluator, betting engine + side pots, settlement,
transcript fold -- is values-in/values-out (house law H5) and machine-pinned
by tools/evaluator-kat.py and tools/betting-kat.py; heRunSelftest re-checks
the same vectors on-engine. Everything visual is verified statically and
needs an OXT pass.
*/

-- >>> BEGIN EMBEDDED LIBRARIES (tools/sync-demo-embeds.py) >>>
-- Pasted from the sources below so this demo runs with NO `start
-- using` wiring. Do not edit inside these sentinels: run
-- `python3 tools/sync-demo-embeds.py` instead. The sources under
-- src/ stay the single source of truth for real projects.
--
-- Libraries come FIRST because OXT resolves script-level constants
-- and locals by lexical position.

-- ---- onionxt/src/onionxt.livecodescript ----
-- onionxt.livecodescript - the OnionXT library.
--
-- OnionXT is a Tor transport and rendezvous layer for OpenXTalk / the xTalk
-- family. It speaks SOCKS5 (RFC 1928 + Tor extensions) and the Tor control
-- protocol to a LOCALLY-RUNNING tor daemon; it does not embed or ship Tor. It
-- adds no cryptography (SodiumXT does that) and, in this form, no native code:
-- the SOCKS5 and control clients are engine socket I/O, and base32 / the
-- ed25519 scalar clamp are pure byte manipulation.
--
-- STATUS: implemented AND run on a real OXT engine against a live tor daemon.
-- The core paths are confirmed on-engine: dialing through the SOCKS proxy, the
-- control-port connect + SAFECOOKIE auth, GETINFO / SETEVENTS, publishing a v3
-- onion service, accepting an inbound (Tor-forwarded) connection, streaming data
-- both ways, and bootstrap/HS_DESC events. The only path NOT yet exercised is the
-- optional Mode B (launching a bundled tor via `open process`), still flagged
-- "VERIFY:" below. The pure-compute paths are pinned by tools/onion-kat.py.
--
-- Conventions (see CLAUDE.md): public API oxPascalCase; locals t..., params
-- p..., script-locals s..., constants k...; SOCKS5 is BINARY (byte / numToByte /
-- byteToNum), the control protocol is CRLF text; every socket op is async
-- (open / read / accept with message) so the one interpreter thread never blocks
-- on the network; loopback (127.0.0.1) only; every open has an idempotent close;
-- every wire error fails closed and tears the resource down.
--
-- The async model (CLAUDE.md): oxDial and oxCreateService return a HANDLE
-- immediately and complete later; the app learns the outcome through the
-- callbacks below, never by a blocking return. The callback contracts are:
--   status callback  <handler> pKind, pInfo
--       pKind = "control"   pInfo = "connected"|"authenticated"|"disconnected"
--                                   |"authfailed: <reason>"|"error: <reason>"
--       pKind = "bootstrap" pInfo = 0..100          (coalesced to <= ~4 Hz)
--       pKind = "ready"     pInfo = empty           (bootstrap reached 100)
--       pKind = "service"   pInfo = <address>.onion (ADD_ONION returned it)
--       pKind = "serviceReady" pInfo = <address>    (descriptor uploaded)
--       pKind = "notice"    pInfo = <diagnostic>    (e.g. an accepted peer's raw id)
--       pKind = "event"     pInfo = <raw 650 line>  (advanced; opt-in noise)
--   stream callback  <handler> pStream, pEvent, pData
--       pEvent = "open"   the SOCKS tunnel (or inbound peer) is live
--       pEvent = "data"   pData is an inbound Data chunk (app frames its own)
--       pEvent = "closed" the peer closed the stream
--       pEvent = "error"  pData is the error; the stream has been torn down
--   peer callback    <handler> pStream, pService, pPeerAddr
--       a remote peer reached a published service; pStream is a fresh inbound
--       stream handle (register a stream callback on it), pService its service
--       handle, pPeerAddr the (loopback) peer address Tor forwarded from.
--
-- Callbacks are delivered with `dispatch` to the callback owner (oxSetCallbackOwner,
-- default the topStack); a missing handler is a clean no-op, so an app wires only
-- the callbacks it needs.

-- ==========================================================================
-- Constants. Loopback host is fixed; only the ports are configurable (and
-- loopback-locked). Declared before first use (OXT resolves a constant by
-- lexical position; a forward reference silently evaluates to nothing).
-- ==========================================================================

constant kOxHost = "127.0.0.1"
constant kOxSocksPortDefault = 9050
constant kOxControlPortDefault = 9051
constant kOxVersion = "1.0.0"

-- A bootstrapping daemon accepts the TCP connection then stalls; bound every
-- handshake so a silent stall becomes a clean error (docs/02 state machine).
constant kOxHandshakeTimeout = 20000     -- milliseconds
-- Coalesce bootstrap/status updates so a flood of 650 lines cannot thrash a
-- field (CLAUDE.md: <= ~4 Hz). 250 ms = 4 Hz.
constant kOxStatusThrottle = 250         -- milliseconds
-- RFC 4648 base32, lowercase, no padding (docs/04). Pure bytes, no crypto.
constant kOxBase32Alphabet = "abcdefghijklmnopqrstuvwxyz234567"
-- The v3 address checksum preimage prefix and version byte (docs/04). SHA3-256
-- of (kOxChecksumPrefix & pubkey & version) gives the 2-byte checksum; the hash
-- itself is a SodiumXT call, never hand-rolled here.
constant kOxChecksumPrefix = ".onion checksum"
-- The two SAFECOOKIE HMAC key strings, verbatim from the Tor control-spec.
constant kOxSafeCookieServerKey = "Tor safe cookie authentication server-to-controller hash"
constant kOxSafeCookieClientKey = "Tor safe cookie authentication controller-to-server hash"

-- ==========================================================================
-- Script-local state. Handle tables are LiveCode associative arrays keyed by a
-- small integer handle or by the engine's socket id; a stale or closed id must
-- be a clean no-op / error, never a crash.
-- ==========================================================================

-- Configurable ports (default to a system tor; Tor Browser uses 9150 / 9151).
local sSocksPort
local sControlPort

-- Control connection and bootstrap state (see docs/03-control-port.md).
local sControlSocket        -- engine id of the open control socket, or empty
local sControlState         -- disconnected|connecting|protocolinfo|authenticating|authenticated|failed
local sControlMethods       -- offered auth methods (comma list) from PROTOCOLINFO
local sControlCookieFile     -- cookie-file path from PROTOCOLINFO (unescaped)
local sControlPassword       -- app-set password for HASHEDPASSWORD auth
local sControlCookieBytes    -- the 32 raw cookie bytes (SAFECOOKIE flow)
local sControlClientNonce    -- our SAFECOOKIE client nonce (raw bytes)
local sControlTorVersion     -- tor version string from GETINFO version
local sBootstrap             -- 0..100 bootstrap percent from STATUS_CLIENT

-- Control command pipeline. One command in flight at a time so replies match
-- commands (docs/03); further commands queue. Reply lines accumulate until the
-- space-separated final line terminates the reply.
local sCtlInFlight           -- label of the in-flight command, or empty
local sCtlReplyLines         -- accumulated reply text (newline-joined)
local sCtlInData             -- true while inside a 250+ CmdData block
local sCtlData               -- accumulated CmdData block text
local sCtlQueue              -- pending commands: lines of "label" & TAB & "command"

-- App-registered callback handler names and the object they dispatch to.
local sStatusCallback
local sPeerCallback
local sCallbackOwner         -- long id of the object whose script has the callbacks
local sLastStatusTick        -- `the milliseconds` of the last coalesced update

-- Handle tables.
local sStreams               -- keyed by integer stream handle (nested array)
local sSockToStream          -- keyed by socket id string -> stream handle
local sServices              -- keyed by integer service handle (nested array)
local sLocalToService        -- keyed by local port -> service handle
local sNextHandle            -- monotonic handle allocator (0 is never valid)

-- ==========================================================================
-- Configuration.
-- ==========================================================================

command oxSetSocksPort pPort
   -- Loopback-locked: only the port is settable, never the host (CLAUDE.md
   -- socket gotcha 6). Take effect on the next oxDial.
   put pPort into sSocksPort
end oxSetSocksPort

command oxSetControlPort pPort
   put pPort into sControlPort
end oxSetControlPort

command oxSetControlPassword pPassword
   -- Only used if the daemon offers HASHEDPASSWORD auth (docs/03 step 2).
   put pPassword into sControlPassword
end oxSetControlPassword

command oxSetCallbackOwner pObjectLongId
   -- The object whose script holds the app callbacks. If unset, callbacks
   -- dispatch to the topStack; setting this explicitly (as the demo does) removes
   -- any ambiguity about which stack. Confirmed on-engine: with an explicit owner,
   -- onStatus / onPeer / onStreamData all resolve and fire.
   put pObjectLongId into sCallbackOwner
end oxSetCallbackOwner

command oxSetStatusCallback pHandlerName
   put pHandlerName into sStatusCallback
end oxSetStatusCallback

command oxSetPeerCallback pHandlerName
   put pHandlerName into sPeerCallback
end oxSetPeerCallback

function oxVersion
   -- The library version, plus the tor version once the control connection has
   -- answered GETINFO version (docs/05).
   if sControlTorVersion is empty then
      return kOxVersion
   end if
   return kOxVersion & " (tor " & sControlTorVersion & ")"
end oxVersion

-- ==========================================================================
-- Control connection, authentication, and the command pipeline
-- (docs/03-control-port.md). The connection is opened and authenticated
-- asynchronously; the app learns the outcome through the status callback.
-- ==========================================================================

command oxConnectControl
   -- Idempotent-ish: refuse a second concurrent connect rather than leak a
   -- socket. Disconnect first to reconnect.
   if sControlSocket is not empty then
      return "OnionXT: control connection already open (oxDisconnectControl first)"
   end if
   local tSocketID
   -- A named connection (|oxctl) so the id is stable and distinct from streams.
   put kOxHost & ":" & effectiveControlPort() & "|oxctl" into tSocketID
   put tSocketID into sControlSocket
   put "connecting" into sControlState
   put empty into sCtlInFlight
   put empty into sCtlReplyLines
   put false into sCtlInData
   put empty into sCtlQueue
   -- Bound the connect/handshake so a stalled daemon fails cleanly.
   set the socketTimeoutInterval to kOxHandshakeTimeout
   open socket to tSocketID with message "oxCtlOpened"
   -- A watchdog independent of the (repeating) socketTimeout: if we are not
   -- authenticated within the deadline, tear the connection down.
   send ("oxCtlDeadline " & quote & tSocketID & quote) to me in kOxHandshakeTimeout milliseconds
   return empty
end oxConnectControl

command oxDisconnectControl
   -- Idempotent close of the control socket and reset of all control state.
   if sControlSocket is not empty then
      oxSafeCloseSocket sControlSocket
   end if
   put empty into sControlSocket
   put "disconnected" into sControlState
   put empty into sCtlInFlight
   put empty into sCtlReplyLines
   put false into sCtlInData
   put empty into sCtlQueue
   put empty into sControlCookieBytes
   put empty into sControlClientNonce
end oxDisconnectControl

function oxIsControlAuthenticated
   return (sControlState is "authenticated")
end oxIsControlAuthenticated

function oxBootstrapProgress
   if sBootstrap is empty then
      return 0
   end if
   return sBootstrap
end oxBootstrapProgress

function oxIsReady
   -- Ready to carry traffic once bootstrapped to 100 and the control port is
   -- authenticated. A published service's own reachability is reported
   -- separately via the "serviceReady" status (HS_DESC UPLOADED).
   return (sBootstrap is 100) and (sControlState is "authenticated")
end oxIsReady

command oxCtlOpened pSocketID
   -- The control TCP connection is up. Start the single persistent line reader
   -- and kick the auth dance with PROTOCOLINFO (allowed pre-auth).
   if pSocketID is not sControlSocket then
      exit oxCtlOpened          -- a stale socket; ignore
   end if
   put "protocolinfo" into sControlState
   oxStatusUpdate "control", "connected"
   -- One outstanding CRLF read at a time; re-armed at the end of oxCtlLine.
   read from socket pSocketID until crlf with message "oxCtlLine"
   oxCtlSend "PROTOCOLINFO 1", "protocolinfo"
end oxCtlOpened

private command oxCtlSend pCommand, pLabel
   -- Send a control command, or queue it if one is already in flight so replies
   -- always match commands (docs/03: keep a single in-flight command queue).
   if sControlSocket is empty then
      exit oxCtlSend
   end if
   if sCtlInFlight is not empty then
      put pLabel & tab & pCommand & return after sCtlQueue
      exit oxCtlSend
   end if
   put pLabel into sCtlInFlight
   put empty into sCtlReplyLines
   put false into sCtlInData
   put empty into sCtlData
   -- Commands are ASCII text; textEncode gives the exact wire bytes, then the
   -- CRLF terminator (docs/03 line framing).
   write textEncode(pCommand & oxCrlf(), "UTF-8") to socket sControlSocket
end oxCtlSend

private command oxCtlDrainQueue
   -- Send the next queued command, if any. Called when a reply completes.
   if sCtlQueue is empty then
      exit oxCtlDrainQueue
   end if
   local tLine, tLabel, tCommand, tSaved
   put line 1 of sCtlQueue into tLine
   delete line 1 of sCtlQueue
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   put item 1 of tLine into tLabel
   put item 2 to -1 of tLine into tCommand
   set the itemDelimiter to tSaved
   oxCtlSend tCommand, tLabel
end oxCtlDrainQueue

command oxCtlLine pSocketID, pData
   -- The persistent control-port line reader. Demultiplexes unsolicited 650
   -- events from command replies, reassembles multi-line replies, and honours
   -- the 250-/250+/'.'/250 space framing (docs/03).
   if pSocketID is not sControlSocket then
      exit oxCtlLine            -- a stale socket; ignore
   end if
   local tLine
   -- Control replies are ASCII; decode as text, then strip the line terminator.
   -- Confirmed on-engine: `read until crlf` returns the trailing CRLF and
   -- oxStripLineEnd removes it, so auth / GETINFO / events all parse correctly.
   put textDecode(pData, "UTF-8") into tLine
   put oxStripLineEnd(tLine) into tLine

   if sCtlInData then
      -- Inside a 250+ CmdData block: a lone "." ends it; other lines are data
      -- with any doubled leading dot un-stuffed (docs/03, RFC 2821 dot-stuffing).
      if tLine is "." then
         put false into sCtlInData
      else
         if char 1 to 2 of tLine is ".." then
            delete char 1 of tLine
         end if
         put tLine & return after sCtlData
      end if
      oxCtlRearm pSocketID
      exit oxCtlLine
   end if

   if the length of tLine < 3 then
      oxCtlRearm pSocketID      -- malformed / empty; skip
      exit oxCtlLine
   end if

   local tCode, tSep
   put char 1 to 3 of tLine into tCode
   put char 4 of tLine into tSep

   if tCode is "650" then
      -- An asynchronous event. Route it to the event handler, never to the
      -- pending-command continuation.
      oxHandleEvent tLine
      oxCtlRearm pSocketID
      exit oxCtlLine
   end if

   -- A command-reply line. Accumulate it and act on the frame control byte.
   put tLine & return after sCtlReplyLines
   if tSep is "+" then
      put true into sCtlInData
   else if tSep is space or tSep is empty then
      -- Space (or a 3-char line) terminates the reply.
      oxCtlReplyComplete
      put empty into sCtlInFlight
      put empty into sCtlReplyLines
      oxCtlDrainQueue
   end if
   -- "-" continuation: just keep reading.
   oxCtlRearm pSocketID
end oxCtlLine

private command oxCtlRearm pSocketID
   -- Keep exactly one read outstanding, but only while the socket is still ours.
   if pSocketID is sControlSocket then
      read from socket pSocketID until crlf with message "oxCtlLine"
   end if
end oxCtlRearm

private command oxCtlReplyComplete
   -- Dispatch the just-completed reply to the continuation for the in-flight
   -- command. if/else-if, not switch (the static gate rejects `end switch`).
   -- tReplyOp, NOT tOp: a t-prefixed "tOp" lowercases to `top`, a reserved OXT
   -- property, and the engine would parse it as the keyword, not this variable
   -- (the prefixed-token-shadow trap, CLAUDE.md gotcha 2).
   local tLabel, tReplyOp, tArg, tSaved
   put sCtlInFlight into tLabel
   put the itemDelimiter into tSaved
   set the itemDelimiter to ":"
   put item 1 of tLabel into tReplyOp
   put item 2 to -1 of tLabel into tArg
   set the itemDelimiter to tSaved

   if tReplyOp is "protocolinfo" then
      oxParseProtocolInfo sCtlReplyLines
      oxChooseAuthAndStart
   else if tReplyOp is "authchallenge" then
      oxHandleAuthChallenge sCtlReplyLines
   else if tReplyOp is "authenticate" then
      oxHandleAuthResult sCtlReplyLines
   else if tReplyOp is "setevents" then
      -- 250 OK expected; nothing to do on success.
   else if tReplyOp is "getinfo-version" then
      oxParseTorVersion sCtlReplyLines
   else if tReplyOp is "getinfo-bootstrap" then
      oxParseBootstrapPhase sCtlReplyLines
   else if tReplyOp is "add_onion" then
      oxHandleAddOnionReply tArg, sCtlReplyLines
   else if tReplyOp is "del_onion" then
      -- 250 OK on success, 552 if unknown; the removal already forgot local
      -- state, so nothing further is required here.
   end if
end oxCtlReplyComplete

private command oxParseProtocolInfo pReply
   -- Extract the offered auth methods and (for cookie auth) the cookie-file path
   -- from the PROTOCOLINFO reply (docs/03 step 1).
   put empty into sControlMethods
   put empty into sControlCookieFile
   local tLine
   repeat for each line tLine in pReply
      if "AUTH METHODS=" is in tLine then
         -- METHODS=<comma list> [COOKIEFILE="<quoted, C-escaped path>"]
         put oxFieldAfter(tLine, "METHODS=") into sControlMethods
         if "COOKIEFILE=" is in tLine then
            put oxCUnescape(oxQuotedValueAfter(tLine, "COOKIEFILE=")) into sControlCookieFile
         end if
      end if
   end repeat
end oxParseProtocolInfo

private command oxChooseAuthAndStart
   -- Priority SAFECOOKIE > COOKIE > NULL > HASHEDPASSWORD (docs/03), but degrade
   -- past any method whose prerequisite is missing rather than fail: SAFECOOKIE
   -- needs SodiumXT HMAC-SHA256 and randomness (docs/08), COOKIE needs the
   -- readable cookie file, HASHEDPASSWORD needs an app-set password.
   put "authenticating" into sControlState

   if oxMethodOffered("SAFECOOKIE") and oxSodiumHasHmac() and oxSodiumHasRandom() then
      if oxLoadCookie() then
         oxStartSafeCookie
         exit oxChooseAuthAndStart
      end if
   end if
   if oxMethodOffered("COOKIE") then
      if oxLoadCookie() then
         local tHex
         put oxBytesToHex(sControlCookieBytes) into tHex
         oxCtlSend "AUTHENTICATE " & tHex, "authenticate"
         exit oxChooseAuthAndStart
      end if
   end if
   if oxMethodOffered("NULL") then
      oxCtlSend "AUTHENTICATE", "authenticate"
      exit oxChooseAuthAndStart
   end if
   if oxMethodOffered("HASHEDPASSWORD") and sControlPassword is not empty then
      -- Quote the password; escape backslash and double-quote (docs/03).
      oxCtlSend "AUTHENTICATE " & quote & oxQuoteEscape(sControlPassword) & quote, "authenticate"
      exit oxChooseAuthAndStart
   end if

   put "failed" into sControlState
   oxStatusUpdate "control", "authfailed: no usable auth method (offered " & sControlMethods & ")"
   oxDisconnectControl
end oxChooseAuthAndStart

private command oxStartSafeCookie
   -- SAFECOOKIE step A: send a 32-byte client nonce as hex (docs/03 step 2).
   put oxRandomBytes(32) into sControlClientNonce
   oxCtlSend "AUTHCHALLENGE SAFECOOKIE " & oxBytesToHex(sControlClientNonce), "authchallenge"
end oxStartSafeCookie

private command oxHandleAuthChallenge pReply
   -- SAFECOOKIE step B/C/D. The reply is a SINGLE final line:
   -- 250 AUTHCHALLENGE SERVERHASH=<hex> SERVERNONCE=<hex> (docs/03; the reply is
   -- space-separated, not a 250- continuation).
   local tLine, tServerHashHex, tServerNonceHex
   put line 1 of pReply into tLine
   if char 1 to 3 of tLine is not "250" then
      put "failed" into sControlState
      oxStatusUpdate "control", "authfailed: AUTHCHALLENGE rejected (" & tLine & ")"
      oxDisconnectControl
      exit oxHandleAuthChallenge
   end if
   put oxFieldAfter(tLine, "SERVERHASH=") into tServerHashHex
   put oxFieldAfter(tLine, "SERVERNONCE=") into tServerNonceHex

   local tServerNonce, tMessage, tExpected, tOk
   put oxHexToBytes(tServerNonceHex) into tServerNonce
   -- HMAC message = CookieBytes || ClientNonce || ServerNonce (docs/03).
   put sControlCookieBytes & sControlClientNonce & tServerNonce into tMessage
   put oxHmac(kOxSafeCookieServerKey, tMessage) into tExpected
   -- Verify the server hash in constant time; a mismatch means the far end does
   -- not hold the cookie (not the real Tor), so abort and do NOT authenticate.
   put oxConstantTimeEqual(tExpected, oxHexToBytes(tServerHashHex)) into tOk
   if not tOk then
      put "failed" into sControlState
      oxStatusUpdate "control", "authfailed: SAFECOOKIE server hash mismatch (not the real Tor?)"
      oxDisconnectControl
      exit oxHandleAuthChallenge
   end if
   -- Step D: authenticate with the controller-to-server hash.
   local tClientHash
   put oxHmac(kOxSafeCookieClientKey, tMessage) into tClientHash
   oxCtlSend "AUTHENTICATE " & oxBytesToHex(tClientHash), "authenticate"
end oxHandleAuthChallenge

private command oxHandleAuthResult pReply
   -- 250 OK => authenticated; anything else (515 bad auth, 514 required) fails
   -- closed (docs/03; there is no unauthenticated fallback, CLAUDE.md rule 4).
   local tLine
   put line 1 of pReply into tLine
   if char 1 to 3 of tLine is "250" then
      put "authenticated" into sControlState
      oxStatusUpdate "control", "authenticated"
      -- Subscribe to the events we care about and learn the tor version.
      oxCtlSend "SETEVENTS STATUS_CLIENT HS_DESC CIRC STREAM", "setevents"
      oxCtlSend "GETINFO version", "getinfo-version"
      -- Query the CURRENT bootstrap phase once. STATUS_CLIENT BOOTSTRAP events
      -- only fire WHILE tor is bootstrapping, so a daemon already at 100% when we
      -- connect emits none and the UI would sit at 0. This one GETINFO seeds it.
      oxCtlSend "GETINFO status/bootstrap-phase", "getinfo-bootstrap"
   else
      put "failed" into sControlState
      oxStatusUpdate "control", "authfailed: " & tLine
      oxDisconnectControl
   end if
end oxHandleAuthResult

private command oxParseTorVersion pReply
   -- 250-version=<x> then 250 OK (docs/03). Pull the version value.
   local tLine
   repeat for each line tLine in pReply
      if "version=" is in tLine then
         put oxFieldAfter(tLine, "version=") into sControlTorVersion
      end if
   end repeat
end oxParseTorVersion

private command oxParseBootstrapPhase pReply
   -- Reply to GETINFO status/bootstrap-phase, carrying the CURRENT bootstrap state
   -- (unlike the STATUS_CLIENT event, which only fires while bootstrapping). Line:
   --   250-status/bootstrap-phase=NOTICE BOOTSTRAP PROGRESS=100 TAG=done SUMMARY="..."
   -- Parse PROGRESS= the same way as the live event so the UI is seeded on connect.
   local tLine, tProgress
   repeat for each line tLine in pReply
      if "PROGRESS=" is in tLine then
         put oxFieldAfter(tLine, "PROGRESS=") into tProgress
         if tProgress is not empty and tProgress is an integer then
            put tProgress into sBootstrap
            oxStatusUpdate "bootstrap", tProgress
            if tProgress is 100 then
               oxStatusUpdate "ready", empty
            end if
         end if
      end if
   end repeat
end oxParseBootstrapPhase

command oxCtlDeadline pSocketID
   -- Handshake watchdog: if this control socket never reached authenticated,
   -- tear it down with a clean error (docs/07: a stalled bootstrap must not hang).
   if pSocketID is not sControlSocket then
      exit oxCtlDeadline
   end if
   if sControlState is not "authenticated" then
      oxStatusUpdate "control", "error: control authentication timed out"
      oxDisconnectControl
   end if
end oxCtlDeadline

-- ==========================================================================
-- Event handling: bootstrap progress and onion-descriptor readiness
-- (docs/03 step 5). 650 lines are tolerant-parsed; never hard-fail on an
-- unrecognized token (the control-spec requires controllers to tolerate them).
-- ==========================================================================

private command oxHandleEvent pLine
   local tType
   put word 2 of pLine into tType
   if tType is "STATUS_CLIENT" then
      if "BOOTSTRAP" is in pLine then
         local tProgress
         put oxFieldAfter(pLine, "PROGRESS=") into tProgress
         if tProgress is not empty and tProgress is an integer then
            put tProgress into sBootstrap
            oxStatusUpdate "bootstrap", tProgress
            if tProgress is 100 then
               oxStatusUpdate "ready", empty
            end if
         end if
      end if
   else if tType is "HS_DESC" then
      -- Positional: HS_DESC <Action> <HSAddress> ... . Our service is reachable
      -- once we see UPLOADED for its address (docs/03 step 5).
      local tAction, tAddress
      put word 3 of pLine into tAction
      put word 4 of pLine into tAddress
      if tAction is "UPLOADED" then
         oxMarkServiceReady tAddress
         oxStatusUpdate "serviceReady", tAddress
      end if
   else
      -- CIRC / STREAM and anything else are diagnostic; surface raw for advanced
      -- apps that opted into an "event" status, otherwise ignored.
      oxStatusUpdate "event", pLine
   end if
end oxHandleEvent

private command oxMarkServiceReady pAddress
   local tKey, tCore
   -- The event carries the ServiceID (no ".onion"); match either spelling.
   put pAddress into tCore
   if tCore ends with ".onion" then
      put char 1 to -7 of tCore into tCore
   end if
   repeat for each key tKey in sServices
      if sServices[tKey]["serviceID"] is tCore then
         put true into sServices[tKey]["ready"]
      end if
   end repeat
end oxMarkServiceReady

private command oxStatusUpdate pKind, pInfo
   -- Deliver a status update to the app, coalescing the high-frequency bootstrap
   -- stream to <= ~4 Hz (CLAUDE.md). Terminal/rare kinds are always delivered.
   if pKind is "bootstrap" and pInfo is not 100 then
      local tNow
      put the milliseconds into tNow
      if sLastStatusTick is not empty and (tNow - sLastStatusTick) < kOxStatusThrottle then
         exit oxStatusUpdate   -- coalesce: drop this intermediate tick
      end if
      put tNow into sLastStatusTick
   end if
   oxDispatch sStatusCallback, pKind, pInfo, empty
end oxStatusUpdate

-- ==========================================================================
-- Outbound: dialing through SOCKS5 (docs/02-socks5-client.md). A callback-driven
-- state machine: greet, CONNECT with ATYP=3 (Tor resolves the name; never a
-- local DNS lookup), parse the reply, hand up a raw byte-stream tunnel.
-- ==========================================================================

command oxDial pHost, pPort
   -- Reports a stream handle through `the result` immediately; the SOCKS
   -- handshake completes asynchronously and the stream's callback receives
   -- "open" or "error" (CLAUDE.md async model).
   if pHost is empty then
      return "OnionXT: oxDial needs a host (a .onion or clearnet name)"
   end if
   if pPort is not an integer or pPort < 1 or pPort > 65535 then
      return "OnionXT: oxDial needs a port in 1..65535"
   end if
   local tHandle, tConnName, tSocketID
   put oxAllocHandle() into tHandle
   -- A NON-numeric connection name so several streams to 127.0.0.1:9050 get
   -- distinct socket ids, and so they never collide with the numeric names the
   -- accept loop assigns (the id separator is a vertical bar, docs LiveCode ref).
   put "oxs" & tHandle into tConnName
   put kOxHost & ":" & effectiveSocksPort() & "|" & tConnName into tSocketID
   put tSocketID into sStreams[tHandle]["socketID"]
   put "connecting" into sStreams[tHandle]["state"]
   put pHost into sStreams[tHandle]["host"]
   put pPort into sStreams[tHandle]["port"]
   put "dial" into sStreams[tHandle]["kind"]
   put empty into sStreams[tHandle]["callback"]
   put tHandle into sSockToStream[tSocketID]
   set the socketTimeoutInterval to kOxHandshakeTimeout
   open socket to tSocketID with message "oxSocksOpened"
   send ("oxStreamDeadline " & tHandle) to me in kOxHandshakeTimeout milliseconds
   return tHandle
end oxDial

command oxSetStreamCallback pStream, pHandlerName
   if sStreams[pStream]["socketID"] is empty then
      return "OnionXT: unknown stream handle " & pStream
   end if
   put pHandlerName into sStreams[pStream]["callback"]
   return empty
end oxSetStreamCallback

command oxWrite pStream, pData
   -- Write app bytes (already sealed by the app via SodiumXT) to the
   -- tunnel. OnionXT does not encrypt (docs/02).
   if sStreams[pStream]["state"] is not "connected" then
      return "OnionXT: stream " & pStream & " is not open"
   end if
   write pData to socket sStreams[pStream]["socketID"]
   return empty
end oxWrite

command oxCloseStream pStream
   -- Idempotent close of the stream socket; forget the handle. A stale handle is
   -- a clean no-op.
   if sStreams[pStream]["socketID"] is empty then
      exit oxCloseStream
   end if
   oxSafeCloseSocket sStreams[pStream]["socketID"]
   delete variable sSockToStream[sStreams[pStream]["socketID"]]
   delete variable sStreams[pStream]
end oxCloseStream

function oxStreamState pStream
   if sStreams[pStream]["socketID"] is empty then
      return "unknown"
   end if
   return sStreams[pStream]["state"]
end oxStreamState

command oxSocksOpened pSocketID
   -- TCP up: send the method-negotiation greeting 05 01 00 (VER=5, 1 method,
   -- method 00 = no auth) and read the 2-byte method selection (docs/02 step 1).
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksOpened        -- stale
   end if
   put "greeting" into sStreams[tHandle]["state"]
   write numToByte(5) & numToByte(1) & numToByte(0) to socket pSocketID
   read from socket pSocketID for 2 with message "oxSocksMethod"
end oxSocksOpened

command oxSocksMethod pSocketID, pData
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksMethod
   end if
   if the number of bytes of pData < 2 then
      oxStreamFail tHandle, "SOCKS greeting reply truncated"
      exit oxSocksMethod
   end if
   local tVer, tMethod
   put byteToNum(byte 1 of pData) into tVer
   put byteToNum(byte 2 of pData) into tMethod
   if tVer is not 5 then
      oxStreamFail tHandle, "SOCKS server is not version 5"
      exit oxSocksMethod
   end if
   if tMethod is not 0 then
      -- 0xFF = no acceptable methods; anything non-zero we do not offer. Fail
      -- closed; on loopback no auth is needed and its absence is a misconfig to
      -- surface, not paper over (docs/02).
      oxStreamFail tHandle, "SOCKS server demands an auth method OnionXT does not offer (0x" & oxByteHex(tMethod) & ")"
      exit oxSocksMethod
   end if
   -- Method OK: send the CONNECT request with ATYP=3 (domain name) so TOR
   -- resolves pHost. This is the anonymity-critical choice (docs/02 step 2).
   put "connect" into sStreams[tHandle]["state"]
   local tHost, tHostBytes, tPort, tRequest
   put sStreams[tHandle]["host"] into tHost
   put textEncode(tHost, "UTF-8") into tHostBytes
   if the number of bytes of tHostBytes > 255 then
      oxStreamFail tHandle, "SOCKS host name exceeds 255 bytes"
      exit oxSocksMethod
   end if
   put sStreams[tHandle]["port"] into tPort
   -- 05 01 00 03 <len> <host bytes> <port-hi> <port-lo>. The port is 2 bytes
   -- big-endian; build it by hand so the wire bytes are self-evident (do not use
   -- binaryEncode "S", which is host order, docs LiveCode ref).
   put numToByte(5) & numToByte(1) & numToByte(0) & numToByte(3) into tRequest
   put numToByte(the number of bytes of tHostBytes) after tRequest
   put tHostBytes after tRequest
   put numToByte(tPort div 256) & numToByte(tPort mod 256) after tRequest
   write tRequest to socket pSocketID
   -- Read the fixed 4-byte reply head (VER REP RSV ATYP); the BND.ADDR that
   -- follows is variable and framed by ATYP (docs/02 step 3).
   put "replyhead" into sStreams[tHandle]["state"]
   read from socket pSocketID for 4 with message "oxSocksReplyHead"
end oxSocksMethod

command oxSocksReplyHead pSocketID, pData
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksReplyHead
   end if
   if the number of bytes of pData < 4 then
      oxStreamFail tHandle, "SOCKS reply head truncated"
      exit oxSocksReplyHead
   end if
   local tVer, tRep, tAtyp
   put byteToNum(byte 1 of pData) into tVer
   put byteToNum(byte 2 of pData) into tRep
   put byteToNum(byte 4 of pData) into tAtyp
   if tRep is not 0 then
      -- Any non-zero REP is failure. Map it (incl. Tor's onion 0xF0..0xF7) to a
      -- human message and tear down (docs/02 REP table; CLAUDE.md rule 4).
      oxStreamFail tHandle, oxSocksRepMessage(tRep)
      exit oxSocksReplyHead
   end if
   put tAtyp into sStreams[tHandle]["atyp"]
   -- Consume BND.ADDR + 2-byte BND.PORT. Length depends on ATYP: 01 -> 4, 04 ->
   -- 16, 03 -> one length byte then that many. We do not use BND.ADDR; we just
   -- frame past it so the socket is left at the start of the tunnel payload.
   if tAtyp is 1 then
      put "replyrest" into sStreams[tHandle]["state"]
      read from socket pSocketID for 6 with message "oxSocksReplyDone"     -- 4 + 2
   else if tAtyp is 4 then
      put "replyrest" into sStreams[tHandle]["state"]
      read from socket pSocketID for 18 with message "oxSocksReplyDone"    -- 16 + 2
   else if tAtyp is 3 then
      put "replylen" into sStreams[tHandle]["state"]
      read from socket pSocketID for 1 with message "oxSocksReplyLen"
   else
      oxStreamFail tHandle, "SOCKS reply has an unknown address type (" & tAtyp & ")"
   end if
end oxSocksReplyHead

command oxSocksReplyLen pSocketID, pData
   -- ATYP=3 domain BND.ADDR: one length byte, then that many, then 2 port bytes.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksReplyLen
   end if
   if the number of bytes of pData < 1 then
      oxStreamFail tHandle, "SOCKS reply address length truncated"
      exit oxSocksReplyLen
   end if
   local tLen
   put byteToNum(byte 1 of pData) + 2 into tLen     -- address bytes + 2 port bytes
   put "replyrest" into sStreams[tHandle]["state"]
   read from socket pSocketID for tLen with message "oxSocksReplyDone"
end oxSocksReplyLen

command oxSocksReplyDone pSocketID, pData
   -- The SOCKS reply is fully consumed and REP was 0: the socket is now a
   -- transparent tunnel. Hand it up and start the streaming inbound reader.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxSocksReplyDone
   end if
   put "connected" into sStreams[tHandle]["state"]
   oxInvokeStreamCallback tHandle, "open", empty
   -- Begin the persistent read; each inbound chunk is delivered as "data".
   -- Confirmed on-engine: the no-quantifier `read ... with message` streams
   -- available bytes as they arrive (a dialed SOCKS tunnel and an inbound onion
   -- HTTP request both deliver chunk by chunk); it does not block to EOF.
   read from socket pSocketID with message "oxStreamData"
end oxSocksReplyDone

command oxStreamData pSocketID, pData
   -- Inbound bytes on a live stream (dialed OR inbound-accepted; both are unified
   -- through the stream tables). Deliver the chunk and re-arm the read.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is empty then
      exit oxStreamData          -- stale / already torn down
   end if
   if the number of bytes of pData > 0 then
      oxInvokeStreamCallback tHandle, "data", pData
   end if
   -- Re-arm only if the stream is still live (the callback may have closed it).
   if sSockToStream[pSocketID] is not empty then
      read from socket pSocketID with message "oxStreamData"
   end if
end oxStreamData

command oxStreamDeadline pStream
   -- Handshake watchdog for a dialed stream: if it never reached "connected",
   -- tear it down (docs/02: a silent stall is the worst failure).
   if sStreams[pStream]["socketID"] is empty then
      exit oxStreamDeadline
   end if
   local tState
   put sStreams[pStream]["state"] into tState
   if tState is not "connected" and tState is not "closed" then
      oxStreamFail pStream, "SOCKS handshake timed out"
   end if
end oxStreamDeadline

private command oxStreamFail pStream, pError
   -- Fail closed: report the error to the app, then close and forget the stream.
   if sStreams[pStream]["socketID"] is empty then
      exit oxStreamFail
   end if
   put "failed" into sStreams[pStream]["state"]
   oxInvokeStreamCallback pStream, "error", pError
   oxSafeCloseSocket sStreams[pStream]["socketID"]
   delete variable sSockToStream[sStreams[pStream]["socketID"]]
   delete variable sStreams[pStream]
end oxStreamFail

private function oxSocksRepMessage pRep
   -- Map a SOCKS REP code to a clear message. Standard RFC 1928 0x00..0x08 plus
   -- Tor's onion extensions 0xF0..0xF7 (docs/02; the extended band only appears
   -- when the SocksPort has ExtendedErrors set, so 0x01/0x04 must map sensibly
   -- too, since without that flag Tor collapses onion failures onto them).
   if pRep is 1 then
      return "general SOCKS server failure"
   else if pRep is 2 then
      return "connection not allowed by ruleset"
   else if pRep is 3 then
      return "network unreachable"
   else if pRep is 4 then
      return "host unreachable"
   else if pRep is 5 then
      return "connection refused"
   else if pRep is 6 then
      return "TTL expired"
   else if pRep is 7 then
      return "command not supported"
   else if pRep is 8 then
      return "address type not supported"
   else if pRep is 240 then
      return "onion service not found (wrong or offline .onion address)"
   else if pRep is 241 then
      return "onion service descriptor is invalid"
   else if pRep is 242 then
      return "onion service introduction failed"
   else if pRep is 243 then
      return "onion service rendezvous failed"
   else if pRep is 244 then
      return "onion service missing client authorization"
   else if pRep is 245 then
      return "onion service wrong client authorization"
   else if pRep is 246 then
      return "onion service invalid address (malformed .onion)"
   else if pRep is 247 then
      return "onion service introduction timed out"
   end if
   return "SOCKS request failed (REP 0x" & oxByteHex(pRep) & ")"
end oxSocksRepMessage

-- ==========================================================================
-- Inbound: onion services (docs/03 step 3-4, docs/04). Listen on loopback
-- FIRST, then ADD_ONION, so a peer that connects the moment the descriptor
-- publishes is answered (CLAUDE.md socket gotcha 5).
-- ==========================================================================

command oxCreateService pVirtualPort, pLocalPort
   -- Ephemeral service, Tor generates the key. Reports a service handle through
   -- `the result`; the .onion address arrives asynchronously (status "service"
   -- and oxServiceAddress) once ADD_ONION replies.
   local tError
   put oxCheckServiceArgs(pVirtualPort, pLocalPort) into tError
   if tError is not empty then
      return tError
   end if
   local tHandle
   put oxStartService(pVirtualPort, pLocalPort) into tHandle
   if tHandle is not an integer then
      return tHandle          -- listener did not bind; surfaced verbatim
   end if
   -- Flags=Detach keeps the service published even if the control connection
   -- drops (a transient socketClosed/socketError, or a reconnect): without it, an
   -- ADD_ONION service dies with its control connection while its descriptor
   -- lingers in the DHT for ~3h, so a later visit hits "unable to find hidden
   -- service identity key" at rendezvous. oxRemoveService / oxShutdown DEL_ONION
   -- it explicitly; a hard crash leaves it until DEL_ONION or a tor restart.
   oxCtlSend "ADD_ONION NEW:ED25519-V3 Flags=Detach Port=" & pVirtualPort & ",127.0.0.1:" & pLocalPort, "add_onion:" & tHandle
   return tHandle
end oxCreateService

command oxCreateServiceFromSeed pSeed, pVirtualPort, pLocalPort
   -- Deterministic, reproducible address: derive the ed25519 identity from pSeed
   -- and pass Tor the 64-byte ED25519-V3 expanded key (docs/04). The expansion is
   -- SodiumXT's sxSignSeedToExpandedKey (docs/08 gap #1, SHIPPED in ABI 6); we
   -- compose it and fail with a clear message if it is absent, never hand-roll
   -- SHA-512. Same seed -> same .onion on every run.
   local tError
   put oxCheckServiceArgs(pVirtualPort, pLocalPort) into tError
   if tError is not empty then
      return tError
   end if
   if the number of bytes of pSeed is not 32 then
      return "OnionXT: oxCreateServiceFromSeed needs a 32-byte seed"
   end if
   local tExpanded
   put oxExpandedKeyFromSeed(pSeed) into tExpanded
   if the number of bytes of tExpanded is not 64 then
      return tExpanded          -- a capability error, surfaced verbatim
   end if
   -- Tor's ADD_ONION ED25519-V3: wants STANDARD RFC 4648 base64 (the +/ alphabet
   -- with = padding). The engine's base64Encode emits exactly that; do NOT use
   -- SodiumXT's sxBin2Base64, which is url-safe and unpadded and tor rejects.
   -- Strip any line-wrap whitespace the encoder may insert (docs/04 base64 note).
   local tBlob
   put oxStripWhitespace(base64Encode(tExpanded)) into tBlob
   local tHandle
   put oxStartService(pVirtualPort, pLocalPort) into tHandle
   if tHandle is not an integer then
      return tHandle          -- listener did not bind; surfaced verbatim
   end if
   -- Flags=Detach: keep the service alive across a control-connection drop (see
   -- oxCreateService); DEL_ONION on teardown still removes it.
   oxCtlSend "ADD_ONION ED25519-V3:" & tBlob & " Flags=Detach Port=" & pVirtualPort & ",127.0.0.1:" & pLocalPort, "add_onion:" & tHandle
   return tHandle
end oxCreateServiceFromSeed

command oxPublishService pVirtualPort, pLocalPort
   -- Publish an onion whose virtual port Tor forwards to a loopback port that
   -- SOMETHING ELSE is already accepting on (LiveCode's built-in HTTPD Library, or
   -- any local server). Unlike oxCreateService, OnionXT does NOT start its own
   -- accept loop: the external server owns the socket, parses the request, and
   -- replies. Teardown DEL_ONIONs the service but leaves that socket alone. Reports
   -- a service handle through `the result`; the .onion address arrives
   -- asynchronously (status "service", oxServiceAddress) once ADD_ONION replies.
   --
   -- SECURITY (the caller's responsibility): `accept connections on port` usually
   -- binds ALL interfaces, so the external server's local port may be reachable
   -- from the LAN, bypassing Tor. The external server MUST enforce loopback itself
   -- (reject any non-127.0.0.1 peer before responding), exactly as OnionXT's own
   -- oxPeerAccepted does. Bind the server to loopback if it supports it.
   local tError
   put oxCheckServiceArgs(pVirtualPort, pLocalPort) into tError
   if tError is not empty then
      return tError
   end if
   local tHandle
   put oxAllocHandle() into tHandle
   put pVirtualPort into sServices[tHandle]["virtualPort"]
   put pLocalPort into sServices[tHandle]["localPort"]
   put empty into sServices[tHandle]["serviceID"]
   put empty into sServices[tHandle]["address"]
   put empty into sServices[tHandle]["privateKey"]
   put false into sServices[tHandle]["ready"]
   -- Mark it external so oxRemoveService DEL_ONIONs it but does not close the
   -- socket (which OnionXT never opened; the external server owns it).
   put true into sServices[tHandle]["external"]
   -- No accept loop here (contrast oxStartService). Flags=Detach as in
   -- oxCreateService, so a control-connection blip does not un-publish it.
   oxCtlSend "ADD_ONION NEW:ED25519-V3 Flags=Detach Port=" & pVirtualPort & ",127.0.0.1:" & pLocalPort, "add_onion:" & tHandle
   return tHandle
end oxPublishService

private function oxCheckServiceArgs pVirtualPort, pLocalPort
   if sControlState is not "authenticated" then
      return "OnionXT: connect and authenticate the control port first (oxConnectControl)"
   end if
   if pVirtualPort is not an integer or pVirtualPort < 1 or pVirtualPort > 65535 then
      return "OnionXT: virtual port must be 1..65535"
   end if
   if pLocalPort is not an integer or pLocalPort < 1 or pLocalPort > 65535 then
      return "OnionXT: local port must be 1..65535"
   end if
   return empty
end oxCheckServiceArgs

private function oxStartService pVirtualPort, pLocalPort
   -- Allocate the handle and START the loopback listener before ADD_ONION so a
   -- forwarded connection is never refused (docs/03 step 4, ordering gotcha).
   local tHandle, tPrior
   put sLocalToService[pLocalPort] into tPrior
   if tPrior is not empty and sServices[tPrior]["localPort"] is not empty then
      -- Fail closed: a second service on an in-use local port would overwrite
      -- the port-to-service mapping, and removing either service would then
      -- close (or orphan) the shared listener out from under the other, so Tor
      -- keeps forwarding to a dead port - which looks exactly like a broken
      -- onion. One local port, one service; pick another local port.
      -- (Verified statically; needs an OXT pass.)
      return "OnionXT: local port " & pLocalPort & " already forwards for another service (one service per local port; pick another local port)"
   end if
   if tPrior is not empty then
      -- The mapping is stale (its service is gone); reclaim it and rebind below.
      delete variable sLocalToService[pLocalPort]
   end if
   put oxAllocHandle() into tHandle
   put pVirtualPort into sServices[tHandle]["virtualPort"]
   put pLocalPort into sServices[tHandle]["localPort"]
   put empty into sServices[tHandle]["serviceID"]
   put empty into sServices[tHandle]["address"]
   put empty into sServices[tHandle]["privateKey"]
   put false into sServices[tHandle]["ready"]
   if sLocalToService[pLocalPort] is empty then
      -- Bind loopback only. The classic `accept connections on port` has no
      -- bind-address argument (may listen on all interfaces), so oxPeerAccepted
      -- enforces loopback by rejecting any non-loopback peer before reading.
      -- Confirmed on-engine: Tor-forwarded onion connections are accepted here.
      accept connections on port pLocalPort with message "oxPeerAccepted"
      if the result is not empty then
         -- The listener did not bind (most often the local port is already in use
         -- by a prior run or another app). Fail closed: with no listener, Tor
         -- forwards inbound onion traffic to a dead port and the visitor gets an
         -- empty response, which looks exactly like a broken onion.
         delete variable sServices[tHandle]
         return "OnionXT: cannot listen on 127.0.0.1:" & pLocalPort & " (" & the result & ")"
      end if
      put true into sServices[tHandle]["listening"]
   end if
   put tHandle into sLocalToService[pLocalPort]
   return tHandle
end oxStartService

private command oxHandleAddOnionReply pHandle, pReply
   -- Parse ServiceID (and PrivateKey unless discarded) from the ADD_ONION reply
   -- (docs/03 step 3). On failure, fail closed and tear the half-built service.
   local tLine
   if char 1 to 3 of (line 1 of pReply) is not "250" and "ServiceID=" is not in pReply then
      oxRemoveService pHandle
      oxStatusUpdate "control", "error: ADD_ONION failed (" & (line 1 of pReply) & ")"
      exit oxHandleAddOnionReply
   end if
   repeat for each line tLine in pReply
      if "ServiceID=" is in tLine then
         put oxFieldAfter(tLine, "ServiceID=") into sServices[pHandle]["serviceID"]
      else if "PrivateKey=" is in tLine then
         put oxFieldAfter(tLine, "PrivateKey=") into sServices[pHandle]["privateKey"]
      end if
   end repeat
   if sServices[pHandle]["serviceID"] is not empty then
      put sServices[pHandle]["serviceID"] & ".onion" into sServices[pHandle]["address"]
      oxStatusUpdate "service", sServices[pHandle]["address"]
   end if
end oxHandleAddOnionReply

command oxRemoveService pService
   -- DEL_ONION and stop the listener. Idempotent: a stale handle is a no-op.
   if sServices[pService]["localPort"] is empty then
      exit oxRemoveService
   end if
   local tServiceID, tLocalPort
   put sServices[pService]["serviceID"] into tServiceID
   put sServices[pService]["localPort"] into tLocalPort
   if tServiceID is not empty and sControlState is "authenticated" then
      oxCtlSend "DEL_ONION " & tServiceID, "del_onion:" & pService
   end if
   -- Stop accepting on the loopback port, but ONLY if WE own the listener
   -- (oxCreateService / oxCreateServiceFromSeed). A publish-only service
   -- (oxPublishService) forwards to a socket an external server owns; leave it
   -- alone, or we would close it out from under that server.
   if sServices[pService]["external"] is not true then
      if sLocalToService[tLocalPort] is pService then
         oxSafeCloseSocket tLocalPort
         delete variable sLocalToService[tLocalPort]
      end if
   end if
   delete variable sServices[pService]
end oxRemoveService

function oxServiceAddress pService
   return sServices[pService]["address"]
end oxServiceAddress

function oxServiceIsReady pService
   return (sServices[pService]["ready"] is true)
end oxServiceIsReady

command oxPeerAccepted pSocketID
   -- Tor forwarded an inbound onion connection to our loopback listener. Enforce
   -- loopback (security-critical: reject any non-loopback peer before reading a
   -- byte), wrap the accepted socket as an inbound stream, and hand it to the app.
   -- Emit a diagnostic notice with the RAW accepted id so a misparse is visible.
   oxStatusUpdate "notice", "accepted connection id=[" & pSocketID & "]"
   local tPeerHost
   put oxHostOfSocket(pSocketID) into tPeerHost
   if not oxHostIsLoopback(tPeerHost) then
      -- Not a Tor-forwarded loopback connection: refuse it (docs LiveCode ref;
      -- the listener may be bound to all interfaces). Print the RAW id next to
      -- the parsed host, because since oxHostIsLoopback stopped treating an
      -- unparseable id as loopback this notice is also how a socket-id spelling
      -- oxHostOfSocket does not know announces itself (it arrives here with an
      -- empty host); one self-contained line is what a tester can act on.
      oxStatusUpdate "notice", "rejected non-loopback peer host [" & tPeerHost & \
         "] from id [" & pSocketID & "]"
      oxSafeCloseSocket pSocketID
      exit oxPeerAccepted
   end if
   local tHandle
   put oxAllocHandle() into tHandle
   put pSocketID into sStreams[tHandle]["socketID"]
   put "connected" into sStreams[tHandle]["state"]
   put "inbound" into sStreams[tHandle]["kind"]
   put empty into sStreams[tHandle]["callback"]
   put tHandle into sSockToStream[pSocketID]
   -- Hand the stream to the app FIRST so it can register a stream callback (the
   -- dispatch is synchronous), THEN arm the read so no inbound chunk is delivered
   -- before there is a callback to receive it.
   oxDispatch sPeerCallback, tHandle, oxGuessService(pSocketID), tPeerHost
   if sSockToStream[pSocketID] is not empty then
      read from socket pSocketID with message "oxStreamData"
   end if
end oxPeerAccepted

private function oxGuessService pSocketID
   -- Best-effort service association for the peer callback. The accept callback
   -- carries the PEER address, not our local port, so we cannot always know which
   -- service was reached (VERIFY the accepted-socket id format on-engine). If a
   -- single service is live, return it; otherwise return empty and let the app
   -- key on distinct local ports.
   local tKeys, tCount, tKey
   put the keys of sServices into tKeys
   put the number of lines of tKeys into tCount
   if tCount is 1 then
      return line 1 of tKeys
   end if
   return empty
end oxGuessService

private function oxHostIsLoopback pHost
   -- Accept a Tor-forwarded peer no matter how the engine spells the local
   -- address in the accepted-socket id, and NOTHING else: `accept connections on
   -- port` takes no bind address (see oxStartService), so the listener may be
   -- reachable from the network and this is the only thing standing between a
   -- routable peer and our stream tables. Takes the host oxHostOfSocket parsed,
   -- so the brackets of "[::1]" are already gone and there is exactly one
   -- spelling of each address to test. Comparisons are case-insensitive by
   -- default, so "::FFFF:" matches "::ffff:" without folding anything.
   --
   -- EMPTY IS A REFUSAL NOW, and that is the point of this change rather than a
   -- side effect. It used to return true, with "some engines report no host for
   -- a local accept" as the reason - but the old parser handed this guard an
   -- empty string for EVERY IPv6-shaped id, so "the engine reported no host" and
   -- "we could not parse this id" were indistinguishable, and the permissive
   -- branch let "::ffff:203.0.113.9:1234" - a routable peer wearing an
   -- IPv4-mapped hat - in as loopback. A guard whose default is accept is a
   -- fail-open guard; CLAUDE.md rule 4 says fail closed on anything we do not
   -- understand. So an unrecognized spelling is refused and oxPeerAccepted
   -- prints the RAW id alongside the parsed host: if a real engine is ever seen
   -- spelling an accepted id with no host at all (or with the fully expanded
   -- "0:0:0:0:0:0:0:1"), the fix is to teach oxHostOfSocket that spelling, never
   -- to re-open this branch.
   local tHost
   put pHost into tHost
   if tHost is empty then
      return false
   end if
   if tHost is kOxHost then
      return true
   end if
   if tHost begins with "127." then
      return true
   end if
   if tHost is "::1" then
      return true
   end if
   if tHost begins with "::ffff:" then
      -- The IPv4-mapped form a dual-stack listener can report. It is the SAME
      -- address with a prefix, so strip it and re-test the v4 rules: that admits
      -- "::ffff:127.0.0.1" (genuinely loopback, and unroutable) and refuses
      -- "::ffff:203.0.113.9" (genuinely routable), which the old empty-item-1
      -- parse could not tell apart.
      delete char 1 to 7 of tHost
      if tHost is kOxHost or tHost begins with "127." then
         return true
      end if
      return false
   end if
   if tHost is "localhost" then
      return true
   end if
   return false
end oxHostIsLoopback

-- ==========================================================================
-- Address helpers: a v3 .onion address IS an ed25519 public key
-- (docs/04-onion-rendezvous.md). base32 and the layout are pure byte work; only
-- the checksum needs SHA3-256, which is composed from SodiumXT (docs/08).
-- ==========================================================================

function oxPublicKeyFromAddress pOnionAddress
   -- Strip ".onion", base32-decode 56 chars -> 35 bytes, return the first 32 (the
   -- ed25519 public key). No crypto needed. Empty on a structural error.
   local tCore, tRaw
   put oxNormalizeAddress(pOnionAddress) into tCore
   if the number of chars of tCore is not 56 then
      return empty
   end if
   put oxBase32Decode(tCore) into tRaw
   if the number of bytes of tRaw is not 35 then
      return empty
   end if
   if byteToNum(byte 35 of tRaw) is not 3 then
      return empty            -- not a version-3 address
   end if
   return byte 1 to 32 of tRaw
end oxPublicKeyFromAddress

function oxAddressFromPublicKey pEd25519Pub
   -- base32( pubkey || checksum || 0x03 ) & ".onion" (docs/04). The checksum is
   -- SHA3-256(".onion checksum" || pubkey || 0x03)[:2], composed from SodiumXT;
   -- absent that primitive, return a clear error rather than a wrong address.
   if the number of bytes of pEd25519Pub is not 32 then
      return "OnionXT: oxAddressFromPublicKey needs a 32-byte ed25519 public key"
   end if
   local tChecksum
   put oxOnionChecksum(pEd25519Pub) into tChecksum
   if the number of bytes of tChecksum is not 2 then
      return tChecksum         -- capability error, surfaced verbatim
   end if
   return oxBase32Encode(pEd25519Pub & tChecksum & numToByte(3)) & ".onion"
end oxAddressFromPublicKey

function oxIsValidAddress pOnionAddress
   -- Structural checks always (length, alphabet, version byte); checksum
   -- verification too when SodiumXT SHA3-256 is available (docs/04, docs/08).
   local tCore, tRaw
   put oxNormalizeAddress(pOnionAddress) into tCore
   if the number of chars of tCore is not 56 then
      return false
   end if
   local tI, tCh
   repeat with tI = 1 to 56
      put char tI of tCore into tCh
      if offset(tCh, kOxBase32Alphabet) is 0 then
         return false
      end if
   end repeat
   put oxBase32Decode(tCore) into tRaw
   if the number of bytes of tRaw is not 35 then
      return false
   end if
   if byteToNum(byte 35 of tRaw) is not 3 then
      return false
   end if
   -- Checksum verification when we can compute it; otherwise structural-only
   -- (the real authentication is Tor's connect-time descriptor-signature check).
   local tChecksum
   put oxOnionChecksum(byte 1 to 32 of tRaw) into tChecksum
   if the number of bytes of tChecksum is not 2 then
      return true             -- no SHA3-256 available; accept the structure
   end if
   return oxConstantTimeEqual(tChecksum, byte 33 to 34 of tRaw)
end oxIsValidAddress

private function oxNormalizeAddress pOnionAddress
   -- Trim, lowercase, and strip a trailing ".onion".
   local tCore
   put oxTrim(pOnionAddress) into tCore
   put toLower(tCore) into tCore
   if tCore ends with ".onion" then
      put char 1 to -7 of tCore into tCore
   end if
   return tCore
end oxNormalizeAddress

private function oxPow2 pN
   -- 2 to the pN, as an exact integer, WITHOUT the ^ operator (some xTalk
   -- parsers reject `^` in a div/mod expression). pN is small in base32 (0..12),
   -- so this is a few multiplies and stays well within exact-integer range.
   local tR, tI
   put 1 into tR
   repeat with tI = 1 to pN
      multiply tR by 2
   end repeat
   return tR
end oxPow2

private function oxIntDiv pA, pB
   -- Integer division (floor, for the non-negative operands base32 uses) WITHOUT
   -- the `div` operator, to sidestep any xTalk parser that mishandles div/mod/^
   -- inside a compound expression. Operands here are small (base32 bit math).
   return trunc(pA / pB)
end oxIntDiv

private function oxIntMod pA, pB
   -- pA modulo pB WITHOUT the `mod` operator (see oxIntDiv).
   return pA - pB * oxIntDiv(pA, pB)
end oxIntMod

private function oxBase32Encode pData
   -- RFC 4648 base32, lowercase, no padding. Pure bit-packing: accumulate input
   -- bytes MSB-first into a small buffer and emit 5-bit groups. The buffer is
   -- masked to its pending bits each iteration so it never grows past ~13 bits
   -- (staying in exact-integer range; a 280-bit accumulator would lose precision).
   local tOut, tBits, tValue, tI, tN, tIndex
   put "" into tOut
   put 0 into tBits
   put 0 into tValue
   put the number of bytes of pData into tN
   repeat with tI = 1 to tN
      put tValue * 256 + byteToNum(byte tI of pData) into tValue
      add 8 to tBits
      repeat while tBits >= 5
         subtract 5 from tBits
         put oxIntMod(oxIntDiv(tValue, oxPow2(tBits)), 32) into tIndex
         put char (tIndex + 1) of kOxBase32Alphabet after tOut
      end repeat
      put oxIntMod(tValue, oxPow2(tBits)) into tValue        -- keep only the pending bits
   end repeat
   if tBits > 0 then
      -- Left-align the final partial group and emit it (canonical no-pad tail).
      put oxIntMod(tValue * oxPow2(5 - tBits), 32) into tIndex
      put char (tIndex + 1) of kOxBase32Alphabet after tOut
   end if
   return tOut
end oxBase32Encode

private function oxBase32Decode pText
   -- Inverse of oxBase32Encode. Accumulate 5 bits per input char and emit a byte
   -- whenever 8 bits are available; leftover (< 5) bits of the final group are
   -- discarded (canonical). Returns empty on any character outside the alphabet.
   local tOut, tBits, tValue, tI, tN, tCh, tIndex, tByteOut
   put "" into tOut
   put 0 into tBits
   put 0 into tValue
   put the number of chars of pText into tN
   repeat with tI = 1 to tN
      put char tI of pText into tCh
      put offset(tCh, kOxBase32Alphabet) into tIndex     -- 1..32, or 0 if absent
      if tIndex is 0 then
         return empty
      end if
      put tValue * 32 + (tIndex - 1) into tValue
      add 5 to tBits
      if tBits >= 8 then
         subtract 8 from tBits
         put oxIntMod(oxIntDiv(tValue, oxPow2(tBits)), 256) into tByteOut
         put numToByte(tByteOut) after tOut
         put oxIntMod(tValue, oxPow2(tBits)) into tValue
      end if
   end repeat
   return tOut
end oxBase32Decode

private function oxOnionChecksum pEd25519Pub
   -- SHA3-256(".onion checksum" || pubkey || 0x03)[:2] (docs/04). H = SHA3-256 is
   -- a SodiumXT primitive (docs/08); compose it and report a capability error if
   -- it is absent, never hand-roll a hash (CLAUDE.md rule 1).
   local tPreimage, tHash
   put textEncode(kOxChecksumPrefix, "UTF-8") & pEd25519Pub & numToByte(3) into tPreimage
   put oxSha3_256(tPreimage) into tHash
   -- A valid SHA3-256 is exactly 32 bytes; any other length is the capability
   -- error string from oxSha3_256, surfaced verbatim (robust against comparing a
   -- string prefix against binary data).
   if the number of bytes of tHash is not 32 then
      return tHash
   end if
   return byte 1 to 2 of tHash
end oxOnionChecksum

private function oxExpandedKeyFromSeed pSeed
   -- Compose SodiumXT's ABI-6 helper (docs/08 gap #1, now SHIPPED): a 32-byte seed
   -- becomes the 64-byte Tor ED25519-V3 expanded secret key (SHA-512(seed) with the
   -- ed25519 scalar clamp, all done inside SodiumXT so OnionXT hand-rolls nothing).
   -- This is exactly the key ADD_ONION ED25519-V3:<key> wants (docs/04), and its
   -- public key equals sxSignKeypairFromSeed(pSeed)'s, so the .onion address and the
   -- app's signing identity stay consistent. Requires SodiumXT ABI >= 6.
   local tExpanded
   try
      put sxSignSeedToExpandedKey(pSeed) into tExpanded
   catch tError
      return "OnionXT: oxCreateServiceFromSeed needs SodiumXT sxSignSeedToExpandedKey (requires SodiumXT ABI >= 6; see docs/08)"
   end try
   if the number of bytes of tExpanded is not 64 then
      return "OnionXT: sxSignSeedToExpandedKey returned " & the number of bytes of tExpanded & " bytes, expected 64"
   end if
   return tExpanded
end oxExpandedKeyFromSeed

-- ==========================================================================
-- Pluggable transport seam (docs/06). Thin wrappers so any higher-layer protocol
-- can treat OnionXT as a transport: dial by rendezvous address, listen at a
-- seed-derived address, send/recv bytes. OnionXT stays a transport: no crypto,
-- no framing opinion; the payload is sealed by the app via SodiumXT.
-- ==========================================================================

function oxTransportInfo
   -- Advertise the transport and which optional SodiumXT-backed capabilities are
   -- available, so a caller can negotiate transports and fall back visibly
   -- rather than silently (docs/06). Returns a LiveCode array.
   local tInfo
   put "ox" into tInfo["transport"]
   put kOxVersion into tInfo["version"]
   put (oxSodiumHasHmac() and oxSodiumHasRandom()) into tInfo["safeCookieAuth"]
   put oxSodiumHasExpansion() into tInfo["deterministicOnion"]
   put oxSodiumHasSha3() into tInfo["offlineAddress"]
   return tInfo
end oxTransportInfo

command oxTransportDial pAddress, pPort
   -- Dial a rendezvous address. Accepts a full <56>.onion, or a 32-byte ed25519
   -- public key / 64-hex string, which it maps to an address first (docs/06).
   local tPort, tHost
   if pPort is empty then
      put 80 into tPort
   else
      put pPort into tPort
   end if
   put pAddress into tHost
   if not (tHost ends with ".onion") then
      local tPub
      if the number of chars of tHost is 64 then
         put oxHexToBytes(tHost) into tPub
      else
         put tHost into tPub
      end if
      if the number of bytes of tPub is 32 then
         put oxAddressFromPublicKey(tPub) into tHost
         if tHost begins with "OnionXT:" then
            return tHost
         end if
      end if
   end if
   oxDial tHost, tPort
   return the result
end oxTransportDial

command oxTransportListen pSeed, pVirtualPort, pLocalPort
   -- Publish a reproducible rendezvous point from a seed (docs/06).
   oxCreateServiceFromSeed pSeed, pVirtualPort, pLocalPort
   return the result
end oxTransportListen

command oxTransportSend pStream, pData
   oxWrite pStream, pData
   return the result
end oxTransportSend

command oxTransportRecv pStream, pHandlerName
   -- Register where inbound bytes are delivered (the stream callback).
   oxSetStreamCallback pStream, pHandlerName
   return the result
end oxTransportRecv

-- ==========================================================================
-- Lifecycle and teardown. Central socket-message handlers and a master
-- oxShutdown so an app can free everything it opened, e.g. on closeStack (there
-- is no deterministic unload hook in OXT; CLAUDE.md handles-and-state).
-- ==========================================================================

command oxShutdown
   -- Idempotent: close every stream, remove every service, disconnect control.
   -- Safe to call twice.
   local tKey, tKeys
   put the keys of sStreams into tKeys
   repeat for each line tKey in tKeys
      oxCloseStream tKey
   end repeat
   put the keys of sServices into tKeys
   repeat for each line tKey in tKeys
      oxRemoveService tKey
   end repeat
   oxDisconnectControl
end oxShutdown

-- THE ENGINE'S THREE SOCKET MESSAGES, SPLIT IN TWO (2026-08-24).
--
-- The LOGIC lives in oxSocketError / oxSocketClosed / oxSocketTimeout, which
-- are ordinary ox*-prefixed functions answering ONE question: was that socket
-- MINE, and did I handle it? The `on socketError` / `on socketClosed` /
-- `on socketTimeout` handlers below are now pure dispatch - call the named
-- one, exit if it consumed the event, otherwise pass.
--
-- WHY, because the split looks like ceremony until you need it: these three
-- names are the ENGINE's, so every socket library in the message path
-- declares the same three, and two scripts cannot define one name in ONE
-- script - which is exactly what embedding a library into an app's stack
-- script does (tools/sync-demo-embeds.py). That is what kept OnionXT out of
-- nocloud's paste and left its users a manual `start using` step. With the
-- logic behind a name of its OWN, an embedder drops these three thin
-- wrappers and calls oxSocketError(...) from its own handler instead of
-- passing - no copy of this logic anywhere, so nothing can go stale.
--
-- The own-socket branches are UNCHANGED and stay the engine-proven ones; the
-- split itself is verified statically and needs a live-Tor re-pass.

-- Was pSocketID one of OUR sockets, and did we handle the error? "true" when
-- consumed, "false" when it belongs to somebody else.
function oxSocketError pSocketID, pError
   -- The engine's socket-failure message. If the socket closes because of an
   -- error, this arrives instead of socketClosed. Look up the owner and fail
   -- closed (docs LiveCode ref). A message for an unknown id is a clean no-op.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is not empty then
      oxStreamFail tHandle, "socket error: " & pError
      return "true"
   end if
   if pSocketID is sControlSocket then
      oxStatusUpdate "control", "error: " & pError
      oxDisconnectControl
      return "true"
   end if
   return "false"
end oxSocketError

on socketError pSocketID, pError
   if oxSocketError(pSocketID, pError) then
      exit socketError
   end if
   -- NOT OURS: pass it on (2026-08-23). The family rule this file itself
   -- documents for apps (docs/05, docs/10) applies to the library too:
   -- swallowing another library's socket event is a silent HANG there. Found
   -- by the suite's cross-library name gate when nostrxt's relay layer became
   -- the second library defining these.
   pass socketError
end socketError

-- Was pSocketID one of OUR sockets, and did we handle the close?
function oxSocketClosed pSocketID
   -- The remote side closed cleanly. Deliver "closed" to a stream's app callback
   -- and forget it; for the control socket, mark disconnected.
   local tHandle
   put sSockToStream[pSocketID] into tHandle
   if tHandle is not empty then
      oxInvokeStreamCallback tHandle, "closed", empty
      delete variable sSockToStream[pSocketID]
      delete variable sStreams[tHandle]
      return "true"
   end if
   if pSocketID is sControlSocket then
      oxStatusUpdate "control", "disconnected"
      oxDisconnectControl
      return "true"
   end if
   return "false"
end oxSocketClosed

on socketClosed pSocketID
   if oxSocketClosed(pSocketID) then
      exit socketClosed
   end if
   -- NOT OURS: pass it on (see socketError above).
   pass socketClosed
end socketClosed

-- Was pSocketID one of OUR sockets, and did we handle the timeout?
function oxSocketTimeout pSocketID
   -- socketTimeout REPEATS every interval while a read/write is pending (docs
   -- LiveCode ref), so it is only fatal during a handshake; on a connected stream
   -- it is just an idle read and must be ignored. Tear down only handshakes.
   local tHandle, tState
   put sSockToStream[pSocketID] into tHandle
   if tHandle is not empty then
      put sStreams[tHandle]["state"] into tState
      if tState is not "connected" then
         oxStreamFail tHandle, "SOCKS handshake timed out"
      end if
      return "true"
   end if
   -- Control socket (ours even when authenticated - an idle timeout there
   -- is normal): only fatal before authentication completes.
   if pSocketID is sControlSocket then
      if sControlState is not "authenticated" then
         oxStatusUpdate "control", "error: control handshake timed out"
         oxDisconnectControl
      end if
      return "true"
   end if
   return "false"
end oxSocketTimeout

on socketTimeout pSocketID
   if oxSocketTimeout(pSocketID) then
      exit socketTimeout
   end if
   -- NOT OURS: pass it on (see socketError above).
   pass socketTimeout
end socketTimeout

-- ==========================================================================
-- Optional Mode B: launch and supervise a bundled tor (docs/07). This is a
-- CONVENIENCE layer, NOT the default and NOT the tested path; the assume-running
-- daemon (Mode A) is the trusted, recommended base. VERIFY every step on-engine.
-- ==========================================================================

command oxLaunchTor pTorPath, pDataDir, pSocksPort, pControlPort
   -- Write a minimal torrc into pDataDir and launch pTorPath against it, so tor
   -- exits with the app (__OwningControllerProcess) and uses cookie auth. Returns
   -- empty on a clean launch attempt, or an error string. The caller then polls
   -- oxConnectControl / oxBootstrapProgress; this does not wait for bootstrap.
   if pTorPath is empty or pDataDir is empty then
      return "OnionXT: oxLaunchTor needs a tor binary path and a data directory"
   end if
   local tSocks, tControl, tTorrc, tRcPath
   if pSocksPort is empty then
      put kOxSocksPortDefault into tSocks
   else
      put pSocksPort into tSocks
   end if
   if pControlPort is empty then
      put kOxControlPortDefault into tControl
   else
      put pControlPort into tControl
   end if
   put "SocksPort " & tSocks & oxCrlf() after tTorrc
   put "ControlPort " & tControl & oxCrlf() after tTorrc
   put "CookieAuthentication 1" & oxCrlf() after tTorrc
   put "DataDirectory " & pDataDir & oxCrlf() after tTorrc
   -- Tie tor's lifetime to this process where the platform supports it.
   put "__OwningControllerProcess " & oxProcessId() & oxCrlf() after tTorrc
   put pDataDir & "/onionxt-torrc" into tRcPath
   put tTorrc into url ("binfile:" & tRcPath)
   oxSetSocksPort tSocks
   oxSetControlPort tControl
   -- open process is platform-specific; launch tor detached with -f <torrc>.
   -- QUOTE BOTH PATHS. The command line is split on whitespace, so an unquoted
   -- "C:/Program Files/Tor/tor.exe" arrives as the two arguments "C:/Program"
   -- and "Files/Tor/tor.exe" and the launch fails - and a data directory under
   -- "Application Support" or a user folder with a space in the name is the
   -- normal case on Windows and macOS, not an edge case. The same applies to
   -- the torrc path, which is derived from pDataDir.
   -- VERIFY: process launch and teardown on your target OXT build.
   open process (quote & pTorPath & quote & " -f " & quote & tRcPath & quote) for read
   return empty
end oxLaunchTor

command oxStopTor
   -- Ask tor to shut down over the control port, then disconnect. If Mode B was
   -- not used this simply disconnects control (idempotent).
   if sControlState is "authenticated" then
      oxCtlSend "SIGNAL SHUTDOWN", "signal"
   end if
   oxDisconnectControl
end oxStopTor

-- ==========================================================================
-- SodiumXT composition helpers (requires SodiumXT ABI >= 6 for the deterministic
-- onion and SAFECOOKIE paths). Each sx* primitive is called DIRECTLY and wrapped
-- in try/catch: an absent handler raises a catchable execution error, so a missing
-- primitive degrades to a clear capability error rather than crashing, and the
-- function's return value comes back unambiguously (CLAUDE.md rule 1; no crypto is
-- hand-rolled here). base32 and the base64 encode are pure byte ops, NOT here.
-- ==========================================================================

private function oxSha3_256 pData
   -- Composed since SodiumXT ABI 7 (docs/08 gap #2, closed 2026-08-11):
   -- sxSha3_256 is the vendored FIPS-202 primitive SodiumXT ships precisely
   -- for this checksum. Against an older installed SodiumXT the absent handler
   -- still raises here and degrades to the clear capability error below. The
   -- checksum is a nicety, not a security dependency (tor authenticates the
   -- onion at connect time), so callers degrade to structural-only checks.
   local tOut
   try
      put sxSha3_256(pData) into tOut
   catch tError
      return "OnionXT: the offline .onion checksum needs SodiumXT SHA3-256 (sxSha3_256, ABI 7+; this SodiumXT predates it - docs/08 #2)"
   end try
   return tOut
end oxSha3_256

private function oxHmac pKeyString, pMessage
   -- HMAC-SHA256 (SodiumXT ABI >= 6). The ASCII key string crosses as its bytes.
   local tOut
   try
      put sxHmacSha256(textEncode(pKeyString, "UTF-8"), pMessage) into tOut
   catch tError
      return "OnionXT: SAFECOOKIE auth needs SodiumXT HMAC-SHA256 (sxHmacSha256, SodiumXT ABI >= 6, docs/08)"
   end try
   return tOut
end oxHmac

private function oxRandomBytes pCount
   local tOut
   try
      put sxRandomBytes(pCount) into tOut
   catch tError
      return empty
   end try
   return tOut
end oxRandomBytes

private function oxConstantTimeEqual pA, pB
   -- Prefer SodiumXT's constant-time compare; fall back to a plain compare only
   -- when it is unavailable (acceptable on a loopback control port).
   local tOut
   try
      put sxMemEqual(pA, pB) into tOut
      return (tOut is true)
   catch tError
      return (pA is pB)
   end try
end oxConstantTimeEqual

private function oxSodiumHasHmac
   -- True if SodiumXT (ABI >= 6) provides HMAC-SHA256. A benign 1-byte probe.
   local tOut
   try
      put sxHmacSha256(numToByte(0), numToByte(0)) into tOut
      return (the number of bytes of tOut is 32)
   catch tError
      return false
   end try
end oxSodiumHasHmac

private function oxSodiumHasRandom
   local tOut
   try
      put sxRandomBytes(1) into tOut
      return (the number of bytes of tOut is 1)
   catch tError
      return false
   end try
end oxSodiumHasRandom

private function oxSodiumHasSha3
   -- Capability probe: true on SodiumXT ABI 7+ (sxSha3_256 shipped 2026-08-11,
   -- docs/08 #2 CLOSED); false only against an older installed SodiumXT.
   try
      get sxSha3_256(empty)
      return true
   catch tError
      return false
   end try
end oxSodiumHasSha3

private function oxSodiumHasExpansion
   -- True if SodiumXT (ABI >= 6) provides the seed -> expanded-key helper.
   local tOut
   try
      put sxSignSeedToExpandedKey(oxZeroBytes(32)) into tOut
      return (the number of bytes of tOut is 64)
   catch tError
      return false
   end try
end oxSodiumHasExpansion

private function oxLoadCookie
   -- Read the 32 raw cookie bytes from the authoritative PROTOCOLINFO path
   -- (docs/03). binfile is binary-safe. Returns true on a plausible 32-byte read.
   if sControlCookieFile is empty then
      return false
   end if
   local tBytes
   put url ("binfile:" & sControlCookieFile) into tBytes
   if the number of bytes of tBytes is not 32 then
      return false
   end if
   put tBytes into sControlCookieBytes
   return true
end oxLoadCookie

-- ==========================================================================
-- Small pure helpers.
-- ==========================================================================

private function effectiveSocksPort
   if sSocksPort is empty then
      return kOxSocksPortDefault
   end if
   return sSocksPort
end effectiveSocksPort

private function effectiveControlPort
   if sControlPort is empty then
      return kOxControlPortDefault
   end if
   return sControlPort
end effectiveControlPort

private function oxAllocHandle
   -- Monotonic; 0 is never a valid handle so a zero/empty is always a clean miss.
   if sNextHandle is empty then
      put 0 into sNextHandle
   end if
   add 1 to sNextHandle
   return sNextHandle
end oxAllocHandle

private command oxSafeCloseSocket pSocketID
   -- Idempotent close: only close ids the engine still lists as open, so closing
   -- a stale/unknown id is a clean no-op (VERIFY the engine tolerates it anyway).
   if pSocketID is empty then
      exit oxSafeCloseSocket
   end if
   if pSocketID is among the lines of the openSockets then
      close socket pSocketID
   end if
end oxSafeCloseSocket

private command oxInvokeStreamCallback pStream, pEvent, pData
   oxDispatch sStreams[pStream]["callback"], pStream, pEvent, pData
end oxInvokeStreamCallback

private command oxDispatch pHandlerName, pArg1, pArg2, pArg3
   -- Deliver to the app; a missing handler is a clean no-op so an app wires only
   -- the callbacks it uses. Guard the call so a throwing app handler cannot break
   -- the state machine.
   if pHandlerName is empty then
      exit oxDispatch
   end if
   local tTarget
   put oxCallbackTarget() into tTarget      -- a local, not a function call inline
   try
      dispatch pHandlerName to tTarget with pArg1, pArg2, pArg3
   catch tIgnore
      -- Swallow app-side callback errors; the transport must keep running.
   end try
end oxDispatch

private function oxCallbackTarget
   -- The object the app callbacks live in. Explicitly set is authoritative;
   -- otherwise the topStack is the best default (VERIFY it is the app's stack).
   if sCallbackOwner is not empty then
      return sCallbackOwner
   end if
   return the topStack
end oxCallbackTarget

private function oxCrlf
   -- The wire line terminator as explicit bytes-to-be (U+000D U+000A), so the
   -- byte value never depends on how the engine defines the `crlf` constant.
   return numToChar(13) & numToChar(10)
end oxCrlf

private function oxStripLineEnd pLine
   -- Strip a trailing LF and/or CR from a decoded reply line, in either order.
   -- A plain function (returns the trimmed line) rather than a @-by-reference
   -- command, to avoid the less-common reference-parameter construct.
   repeat while pLine is not empty and (the last char of pLine is numToChar(10) or the last char of pLine is numToChar(13))
      delete the last char of pLine
   end repeat
   return pLine
end oxStripLineEnd

private function oxFieldAfter pText, pMarker
   -- The whitespace-delimited token immediately following pMarker in pText, or
   -- empty. Used for METHODS=, PROGRESS=, ServiceID=, version=, SERVERHASH=, etc.
   -- itemDelimiter is global mutable state, so save and restore it (gotcha 7).
   local tPos, tRest, tSaved, tOut
   put offset(pMarker, pText) into tPos
   if tPos is 0 then
      return empty
   end if
   put char (tPos + the number of chars of pMarker) to -1 of pText into tRest
   -- Stop at the first space (values here are single tokens; quoted values use
   -- oxQuotedValueAfter instead).
   put the itemDelimiter into tSaved
   set the itemDelimiter to space
   put item 1 of tRest into tOut
   set the itemDelimiter to tSaved
   return tOut
end oxFieldAfter

private function oxQuotedValueAfter pText, pMarker
   -- The C-quoted string value following pMarker (e.g. COOKIEFILE="..."). Returns
   -- the raw (still-escaped) inside of the quotes; the caller un-escapes.
   local tPos, tRest, tOut, tI, tCh, tEsc
   put offset(pMarker, pText) into tPos
   if tPos is 0 then
      return empty
   end if
   put char (tPos + the number of chars of pMarker) to -1 of pText into tRest
   if char 1 of tRest is not quote then
      -- Unquoted value: take up to the next space (save/restore itemDelimiter).
      -- tOut is already declared at the handler top; only tSaved is new here.
      local tSaved
      put the itemDelimiter into tSaved
      set the itemDelimiter to space
      put item 1 of tRest into tOut
      set the itemDelimiter to tSaved
      return tOut
   end if
   -- Walk from just after the opening quote to the matching unescaped quote.
   put empty into tOut
   put false into tEsc
   repeat with tI = 2 to the number of chars of tRest
      put char tI of tRest into tCh
      if tEsc then
         put tCh after tOut
         put false into tEsc
      else if tCh is "\" then
         put tCh after tOut
         put true into tEsc
      else if tCh is quote then
         exit repeat
      else
         put tCh after tOut
      end if
   end repeat
   return tOut
end oxQuotedValueAfter

private function oxCUnescape pStr
   -- Undo Tor's C-style string escapes (docs/03): \n \t \r, octal \0..\377, and
   -- backslash-before-any-other-char is that literal char.
   local tOut, tI, tN, tCh, tNext, tOct
   put empty into tOut
   put the number of chars of pStr into tN
   put 1 into tI
   repeat while tI <= tN
      put char tI of pStr into tCh
      if tCh is "\" and tI < tN then
         put char (tI + 1) of pStr into tNext
         if tNext is "n" then
            put numToChar(10) after tOut
            add 2 to tI
         else if tNext is "t" then
            put numToChar(9) after tOut
            add 2 to tI
         else if tNext is "r" then
            put numToChar(13) after tOut
            add 2 to tI
         else if tNext is in "01234567" then
            -- Up to 3 octal digits.
            put empty into tOct
            add 1 to tI
            repeat while tI <= tN and (the number of chars of tOct) < 3 and (char tI of pStr) is in "01234567"
               put char tI of pStr after tOct
               add 1 to tI
            end repeat
            put numToChar(oxOctalToNum(tOct)) after tOut
         else
            put tNext after tOut
            add 2 to tI
         end if
      else
         put tCh after tOut
         add 1 to tI
      end if
   end repeat
   return tOut
end oxCUnescape

private function oxOctalToNum pOct
   local tVal, tI
   put 0 into tVal
   repeat with tI = 1 to the number of chars of pOct
      put tVal * 8 + (charToNum(char tI of pOct) - 48) into tVal
   end repeat
   return tVal
end oxOctalToNum

private function oxQuoteEscape pStr
   -- Escape backslash and double-quote for a control-port QuotedString.
   local tOut
   put pStr into tOut
   replace "\" with "\\" in tOut
   replace quote with ("\" & quote) in tOut
   return tOut
end oxQuoteEscape

private function oxBytesToHex pData
   -- Lowercase hex (high nibble first). H* unpacks the whole run. binaryDecode is
   -- a FUNCTION (it returns the count decoded and fills the output variable, which
   -- must already exist), so it must be called as a function; `get` discards the
   -- count into `it` while tHex is filled.
   local tHex
   get binaryDecode("H*", pData, tHex)
   return tHex
end oxBytesToHex

private function oxHexToBytes pHex
   return binaryEncode("H*", pHex)
end oxHexToBytes

private function oxByteHex pNum
   -- Two-digit hex for one byte value (for error messages).
   return oxBytesToHex(numToByte(pNum))
end oxByteHex

private function oxHostOfSocket pSocketID
   -- The HOST part of an engine socket id: "host:port", optionally with a
   -- "|name" suffix (we mint "127.0.0.1:9050|oxs3" ourselves; an ACCEPTED id is
   -- whatever the engine spells the PEER address as, so its shape is the
   -- engine's choice, not ours).
   --
   -- This is security-critical input, not a display helper: oxPeerAccepted feeds
   -- the result straight to oxHostIsLoopback, which decides whether an inbound
   -- peer is let in. The obvious "item 1 with the itemDelimiter set to colon"
   -- was wrong in BOTH directions on an IPv6 id, and one of those directions
   -- FAILED OPEN:
   --   "::1:54321"                -> item 1 is EMPTY, and the guard's old
   --                                 empty-is-loopback branch accepted it;
   --   "::ffff:203.0.113.9:1234"  -> item 1 is EMPTY too, so a ROUTABLE peer in
   --                                 IPv4-mapped form was accepted as loopback;
   --   "[::1]:54321"              -> item 1 is "[", so a real loopback peer was
   --                                 refused (the harmless direction).
   -- Parse by SHAPE instead, which also makes the guard's "::1" branch reachable
   -- for the first time (it never could be: item 1 of anything containing a
   -- colon cannot itself contain one):
   --   1. drop any "|name" suffix - the name half is ours and never part of the
   --      host, and it can carry digits that would otherwise look like a port;
   --   2. a bracketed group IS the host, verbatim and unbracketed - the brackets
   --      exist precisely to separate an IPv6 host's colons from the port colon,
   --      and stripping them here means the guard sees ONE spelling of ::1;
   --   3. otherwise the host is everything up to the LAST colon, which is right
   --      for "127.0.0.1:9050" and for a bare "::1:54321" alike;
   --   4. a colon-less id has no port to strip, so it is all host.
   -- Anything this cannot make sense of comes back EMPTY, which oxHostIsLoopback
   -- now REFUSES (it used to accept it); that is the fail-closed direction.
   local tSaved, tRaw, tCut, tOut
   put pSocketID into tRaw
   put offset("|", tRaw) into tCut
   if tCut > 0 then
      delete char tCut to -1 of tRaw
   end if
   if char 1 of tRaw is "[" then
      put offset("]", tRaw) into tCut
      if tCut < 3 then
         return empty              -- unclosed or empty brackets: not a host
      end if
      return char 2 to (tCut - 1) of tRaw
   end if
   if ":" is not in tRaw then
      return tRaw
   end if
   put the itemDelimiter into tSaved
   set the itemDelimiter to ":"
   -- `item 1 to -2` REJOINS its items with the delimiter, which is exactly what
   -- a bare IPv6 host needs: the three empty/short items of "::1:54321" come
   -- back as "::1", while "127.0.0.1:9050" comes back unchanged.
   put item 1 to -2 of tRaw into tOut
   set the itemDelimiter to tSaved
   return tOut
end oxHostOfSocket

private function oxMethodOffered pMethod
   -- sControlMethods is a comma list; force comma before testing membership.
   local tSaved, tResult
   put the itemDelimiter into tSaved
   set the itemDelimiter to comma
   put (pMethod is among the items of sControlMethods) into tResult
   set the itemDelimiter to tSaved
   return tResult
end oxMethodOffered

private function oxStripWhitespace pStr
   local tOut
   put pStr into tOut
   replace numToChar(10) with empty in tOut
   replace numToChar(13) with empty in tOut
   replace space with empty in tOut
   replace tab with empty in tOut
   return tOut
end oxStripWhitespace

private function oxTrim pStr
   -- The `tOut is not empty` guard is essential: the empty string is "in" every
   -- string, so without it an all-whitespace or empty input would loop forever
   -- (the first/last char of empty is empty, which `is in` any charset).
   local tOut, tWhite
   put pStr into tOut
   put space & tab & numToChar(10) & numToChar(13) into tWhite
   repeat while tOut is not empty and (the first char of tOut) is in tWhite
      delete the first char of tOut
   end repeat
   repeat while tOut is not empty and (the last char of tOut) is in tWhite
      delete the last char of tOut
   end repeat
   return tOut
end oxTrim

private function oxZeroBytes pCount
   local tOut, tI
   put empty into tOut
   repeat with tI = 1 to pCount
      put numToByte(0) after tOut
   end repeat
   return tOut
end oxZeroBytes

private function oxProcessId
   -- Best-effort current process id for __OwningControllerProcess (Mode B).
   -- VERIFY the available accessor on your OXT build; empty is tolerated by tor.
   return the processId
end oxProcessId

-- <<< END EMBEDDED LIBRARIES <<<

--------------------------------------------------------------------------
-- constants (all up here: gotcha 29 -- a constant used above its
-- declaration silently evaluates to nothing at runtime)
--------------------------------------------------------------------------

constant kHeVersion = "0.25.2"
constant kHeHarnessV = "43"
constant kUIVersion = "15"

-- card contract (mirrored in tools/evaluator-kat.py): index 1..52,
-- index = (rank - 2) * 4 + suit, rank 2..14, suit 1..4 = c,d,h,s
constant kHeRankChars = "23456789TJQKA"
constant kHeSuitChars = "cdhs"
-- kit-mode card back: which frame of the Kenney playingCardBacks atlas to draw for
-- face-down cards (blue/green/red 1..5). Pinned present by tools/atlas-kat.py; the
-- OXT pass can swap it once the real designs are visible.
constant kHeCardBackFrame = "cardBack_red2"

-- Park-Miller MINSTD: x' = 16807 * x mod (2^31 - 1). 16807 * (2^31-1) is
-- about 3.6e13, well under 2^53, so every step is exact in a double.
constant kHeRngMul = 16807
constant kHeRngMod = 2147483647
constant kHeRngMax = 2147483646

-- Phase 2 (online) protocol: domain-separated, versioned hash tags (spec 16)
-- and the canonical envelope version. Pinned in tools/protocol-kat.py.
constant kHeEnvV = "1"
constant kHeDomainSeedC = "HOLDEM-SEEDC-v1|"
constant kHeDomainShuf = "HOLDEM-SHUF-v1|"
constant kHeDomainChain = "HOLDEM-CHAIN-v1|"
constant kHeDomainSettle = "HOLDEM-SETL-v1|"
constant kHeDomainSess = "HOLDEM-SESS-v1|"
-- per-hand deal-seed derivation (v0.18.0): seed = H(domain || idSeed || "|" ||
-- table || "|" || hand). Secret-keyed (the identity seed never leaves the
-- machine), fresh per hand (spec 5 freshness law -- the hand number is in the
-- input), and DETERMINISTIC -- a reconnecting client re-derives the exact seed
-- it committed, so it can still reveal at hand end instead of wedging the
-- audit (spec 9 reconnect).
constant kHeDomainSeedP = "HOLDEM-SEEDP-v1|"
-- host-trust hardening (spec 6 checkpoints, 8.3 settlement receipts)
constant kHeDomainCkpt = "HOLDEM-CKPT-v1|"
constant kHeDomainRcpt = "HOLDEM-RCPT-v1|"
constant kHeDomainRsig = "HOLDEM-RSIG-v1|"
-- Phase 4 (Level 2 mental poker, spec 7.3): the card-table hash-to-group
-- domain. As-built decision: L2-scoped and versioned ("HOLDEM-L2-CARD-v1|",
-- not the spec sketch's "HOLDEM-CARD-v1|"), so the card table can never
-- collide with any other domain in the family and a future re-keying bumps
-- the version. Pinned in tools/protocol-kat.py (l2_base_deck).
constant kHeDomainL2Card = "HOLDEM-L2-CARD-v1|"

-- Phase 5 (DLEQ hardening, spec 7.4): the Chaum-Pedersen transcript
-- domains and the zero scalar. kHeDomainL2Dleq tags the Fiat-Shamir
-- challenge hash; kHeDomainL2DleqW tags the DERANDOMIZED nonce derivation
-- (the RFC 6979 / EdDSA pattern -- w hashes the secret and the statement,
-- so a bad RNG can never reuse a nonce across two different statements,
-- and the whole proof pins from fixed scalars in tools/protocol-kat.py).
-- kHeL2ZeroScalar feeds sxRistrettoScalarAdd(x, 0) -- the widen-and-reduce
-- that pins every scalar to its canonical mod-L form BEFORE any point
-- multiplication: libsodium masks bit 255 inside scalarmult while the KAT
-- reference reduces the full value mod L, and reducing first is what keeps
-- the two from ever seeing different scalars.
constant kHeDomainL2Dleq = "HOLDEM-L2-DLEQ-v1|"
constant kHeDomainL2DleqW = "HOLDEM-L2-DLEQW-v1|"
constant kHeL2ZeroScalar = "0000000000000000000000000000000000000000000000000000000000000000"
constant kHeGenesisPrev = "0000000000000000000000000000000000000000000000000000000000000000"
constant kHeTwo32 = 4294967296
-- Phase 2f (onion tables, spec 10). The onion-SERVICE seed domain: the seed
-- is H("HOLDEM-ONION-v1|" || idSeed || "|" || table) -- SECRET-keyed by the
-- host's identity seed (an invitee holding the public table code cannot
-- derive the service key and republish/impersonate the table endpoint),
-- fresh per table, and DETERMINISTIC, so a crashed host re-derives the same
-- .onion and the invite survives the restart (spec 9 reconnect; the same
-- PRF shape as the v0.18.0 per-hand seed, kHeDomainSeedP).
constant kHeDomainOnion = "HOLDEM-ONION-v1|"
-- Phase 3 (deck oracle, spec 7.2). The ORACLE table's onion-service seed
-- domain: same derivation shape as kHeDomainOnion, its own tag (spec 16:
-- every hash carries its purpose), so an oracle table's deterministic
-- address can never collide with the same host's PLAYING table on the same
-- table id. Pinned in tools/protocol-kat.py (oracle_service_seed).
constant kHeDomainOracle = "HOLDEM-ORACLE-v1|"
-- 2e street checkpoints (spec 6): the boundaries a ckpt wire may name, in
-- play order. "deal" = the last sealed holeDeliver landed; the rest are the
-- transition wire of their street; "showdown" = the wire that closed the
-- betting. Every client records the SAME boundary head (the chain head
-- right after that transition wire), which is what makes two ckpts that
-- disagree host-fork EVIDENCE rather than a timing artifact.
constant kHeCkptStreets = "deal,flop,turn,river,showdown"
-- spec 9 host-loss watchdog: poll ticks (250 ms) of host wire-silence
-- during PLAY before a client declares the host (or oracle -- same role)
-- lost and runs the deterministic election. 240 ticks = 60 s: generous
-- against rp1's lossy ~1 s cadence, tiny against a genuinely gone host.
-- Armed only while gameOn is true -- an idle lobby is legitimately silent.
constant kHeHostLossTicks = 240
-- 2e act timers (spec 8.1/9). The LENGTHS ride the SIGNED cfg (spec 6:
-- "timer lengths" are message-zero material) as act=/bank=/miss= keys, with
-- these as both the host's shipped values and every reader's defaults
-- (heNetCfgVal), so a pre-liveness cfg still folds. One time-bank per hand
-- per seat (spec 8.1), consumed ONLY by a timeout (bank=1 on the wire, so
-- bank spend is transcript-derived consensus, never a local clock's guess);
-- kHeDefaultMisses consecutive timeouts sit the seat out (spec 9).
constant kHeDefaultActSecs = 30
constant kHeDefaultBankSecs = 60
constant kHeDefaultMisses = 2
-- how recently an admitted key must have been HEARD FROM (an applied wire or
-- a verified handshake) for the host to seat it at a hand boundary
-- (heNetPubIsLive, v0.24.0). Only the rp1 transport needs it -- the onion
-- transport clears a dead peer's handle positively (heNetOnionDead), while
-- rp1 surfaces no disconnect event at all, so a departed peer would otherwise
-- be seated as a ghost that times out every turn and holds the seat for the
-- session. 600 s is deliberately generous against the honest case (a joined
-- but unseated observer emits nothing on its own, so its stamp is usually
-- just its join wire) and still bounds the ghost. A JUDGEMENT CALL, not a
-- measured number -- ACCEPTED BY THE OWNER FOR THE TEST PASS (2026-08-16),
-- which settles it for now without making it measured: the live pass should
-- still report whether a real table's join-to-boundary gap fits inside it.
constant kHeSeatLiveSecs = 600
-- the clock-skew tolerance on a host timeout wire, in seconds. NOT the
-- +-600 s wall-clock freshness window (riptide's rp1-inbox precedent):
-- no wall-clock timestamp crosses this wire at all -- both sides measure
-- the SAME interval (turn-opening wire seen -> timeout wire seen) on their
-- own local clock, so the only honest disagreement is transport jitter
-- (rp1's ~1 s tick, the 250 ms poll, a redelivery burst). A live client
-- refuses a host timeout that lands more than this many seconds EARLY;
-- catch-up replay waives the check (historical wires were policed live).
constant kHeActSkewSecs = 5
-- 2e onion auto-redial (spec 9): bounded attempts with doubling backoff
-- after a lost host stream, BEFORE the kHeHostLossTicks election watchdog
-- concludes. Waits are poll ticks (250 ms): 8/16/32/64 = 2/4/8/16 s, four
-- attempts, each dial capped at kHeRedialDialTicks (10 s) -- so the redial
-- can win early but can never outlast the 60 s watchdog by design: every
-- redial step gates on hostLost, and the election always concludes.
constant kHeRedialMax = 4
constant kHeRedialBaseTicks = 8
constant kHeRedialDialTicks = 40
-- the fixed virtual port every table's onion listens on (4653 = "HOLD" on a
-- phone keypad) and the loopback port tor forwards it to (OnionXT owns the
-- accept loop there). Virtual ports are per-onion, so a fixed one never
-- collides across tables; the local port only has to be free on the HOST's
-- machine (a bind failure surfaces through oxCreateServiceFromSeed's
-- fail-closed result).
constant kHeOnionVirtPort = 4653
constant kHeOnionLocalPort = 46530
-- fail-closed deadlines for the transport's silent async waits, counted in
-- 250 ms poll ticks (the fleet-pass watchdog discipline: no wait without a
-- watchdog). Bootstrap is generous because a cold tor takes tens of seconds
-- and the status line shows live progress the whole way.
constant kHeOnionCtlTicks = 80
constant kHeOnionBootTicks = 720
constant kHeOnionPubTicks = 480
constant kHeOnionDialTicks = 240
-- a per-stream reassembly buffer past this size means the peer is not
-- speaking LF-framed wire lines at all: fail that stream closed (bounded,
-- like kHeWireBufMax bounds the reorder buffer)
constant kHeOnionBufMax = 131072

-- table defaults. kHeDefaultSeats is the MAX seats the layout builds (6 spots);
-- the host can seat fewer (kHeMinSeats..kHeMaxSeats) per table via the config.
constant kHeDefaultSeats = 6
constant kHeMinSeats = 2
constant kHeMaxSeats = 6
constant kHeDefaultSB = 1
constant kHeDefaultBB = 2
constant kHeDefaultAnte = 0
constant kHeDefaultStack = 400
-- how many out-of-order future wires the online client will hold while it waits
-- for the gap before them to fill (rp1 is lossy and reorders/duplicates). A wire
-- further than this ahead of what we have applied is left to the full-log replay.
constant kHeWireBufMax = 64
-- blind-level schedule (tournament option). One level = "sb/bb/ante"; levels are
-- ";"-separated. A literal single-line string (gotcha 6: constants must be
-- literal, so no & lf building). The level advances every kHeDefaultLevelEvery
-- hands when levelMode is "hands"; "off" holds the fixed stakes forever.
constant kHeDefaultLevels = "1/2/0;2/4/0;3/6/0;5/10/0;10/20/0;15/30/0;25/50/0;50/100/10"
constant kHeDefaultLevelEvery = 8
constant kHeDefaultLevelMinutes = 10
-- table pacing (spec 11: physics/timing is cosmetic; these are the "deal feel"
-- beats so a hand does not flash by or end abruptly). These are the NORMAL-speed
-- defaults; the host picks fast/normal/slow and heSpeedPace scales them into the
-- gGame["pace*"] values the schedule handlers actually read (per-tick, not
-- per-frame). Verified statically; the actual feel needs an OXT pass to dial in.
constant kHeNextHandDelayMs = 2600  -- result shown, then the next hand deals
constant kHeStreetRevealMs = 750    -- beat after betting closes before a street lands
constant kHeRunoutStepMs = 1050     -- beat between streets when an all-in runs out
constant kHeShowdownHoldMs = 2900   -- hold on the revealed showdown before settling
constant kHeFoldHoldMs = 1400       -- shorter beat on a fold-win (no cards to read)

-- UI geometry (flat mode and kit mode share the layout). 720p RE-LAYOUT
-- (v0.23.0): the stack now fits the suite's 1200x640 budget -- the old
-- 1024x690 put the status line below y=640 -- by tightening the felt's
-- vertical rhythm (felt 48..524, board centre 300 -> 286, seat ring pulled
-- in, pot line moved BELOW the board where the centre column is clear of
-- every bet chip) and pulling the slider/action/status rows up inside the
-- fold. Verified BY ARITHMETIC (every rect within 1024x640; the designed
-- layers -- felt, logo watermark, card slots, per-seat clusters -- are
-- layers, everything else pairwise disjoint); the confirming eye (nothing
-- clipped, the felt still reads) is the OXT pass's.
constant kHeStackRect = "0,0,1024,640"
constant kHeFeltRect = "40,48,984,524"
constant kHeSeatSpots = "512,474;196,428;150,254;512,124;874,254;828,428"
constant kHeBoardY = 286
-- board of 5 cards, centred on the felt (512): first centre = 512 - 2*kHeBoardDX.
-- Card size is ~140:190 (the Kenney frame aspect) so flat glyph cards and kit
-- sprites match; kHeBoardDX must stay > kHeCardW so the board never overlaps.
constant kHeBoardX0 = 368
constant kHeBoardDX = 72
constant kHeCardW = 62
constant kHeCardH = 84
constant kHeHudMs = 250
constant kHeTableCenter = "512,286"

-- fun seat names (hotseat: one human plays all seats) + palette
constant kHeSeatNames = "You,Ada,Boris,Cleo,Dax,Eve"
constant kHeFeltColor = "18,104,66"
constant kHeFeltRim = "116,74,38"
constant kHePanelColor = "14,64,44"
constant kHePanelActive = "196,150,44"
constant kHeChipColor = "196,58,58"
constant kHeGoldColor = "244,206,96"
constant kHeInk = "24,24,24"
constant kHeRed = "196,36,36"
constant kHeWhite = "246,246,246"

-- v0.14.0 UI pack: avatars, table logo, acting-seat glow, bet slider. Sizes are
-- literal (gotcha 6); all placement geometry derives at runtime in heBuildTable.
constant kHeAvatarSize = 46            -- seat portrait diameter (px); fits the name plate
constant kHeLogoBox = 240              -- table-centre host-logo square (px)
constant kHeLogoDim = 60               -- logo blendLevel (0 opaque..100 gone): a faint watermark
constant kHeGlowColor = "248,224,120"  -- acting-seat ring colour
-- six seat-portrait fallback fill colours (initials disc), one per seat, ";"-separated
constant kHeAvatarFills = "196,58,58;58,120,196;72,168,96;198,150,44;150,96,196;54,170,180"

-- v0.16.0 sound pack: Kenney "Casino Audio" (CC0), vendored as 16-bit mono WAVs
-- in assets/sounds (the OGG originals are not engine-playable; see the NOTICE
-- there). The list is the complete vendored set -- heSndTryInit imports each as
-- an audioClip once (clips persist inside a saved stack), heSndFilesFor maps a
-- game moment to its file(s), tools/sounds-kat.py pins list <-> disk <-> mapping.
constant kHeSoundFiles = "cardShuffle.wav,cardSlide1.wav,cardSlide2.wav,cardPlace1.wav,cardPlace2.wav,cardShove1.wav,chipLay1.wav,chipsHandle1.wav,chipsHandle2.wav,chipsCollide1.wav,chipsStack1.wav"

--------------------------------------------------------------------------
-- script-local state (g prefix per the family convention)
--------------------------------------------------------------------------

local gGame            -- the whole table: see heTableNew for the key map
local gCfg             -- persistent table configuration: survives heTableNew so
                       -- the host's chosen stakes/stacks/seats/levels/speed carry
                       -- from one table to the next. See heCfgDefaults for keys.
local gHasSodiumChk    -- cached extension probe ("", "true", "false")
local gHasR255Chk      -- cached ABI-8 ristretto probe ("", "true", "false"):
                       -- a pre-ristretto SodiumXT throws "can't find handler"
                       -- on the first sxRistretto* touch, so the probe's catch
                       -- IS the detection (heL2HasRistretto)
local gHasDleqChk      -- cached ABI-9 DLEQ/batch probe (same pattern:
                       -- heL2HasDleq's first sxRistrettoScalarMultBase touch
                       -- throws on a pre-ABI-9 build, the catch detects it)
local gHasKitChk
local gUIMode          -- "flat" or "kit"
local gHudDirty        -- HUD repaints only on change, max 4 Hz (playbook)
local gHudTickOn
local gAnimBusy        -- deal-slide / flip bookkeeping counter (b2kFrame).
                       -- The per-sprite flip context locks that lived beside
                       -- it (gFlipCtxA) went with the dead b2kSpriteOnFinish
                       -- receiver; the note where that handler stood carries
                       -- the real wiring for whoever lands the flip.
-- kit-mode card rendering: gSlotCenter[slotName]->"x,y" (recorded as slots build),
-- gCardSpr[slotName]->the Box2Dxt sprite's long id, gKitSuffix is "" or ".png" (the
-- Kenney frame-name suffix as this sheet actually exposes it, resolved at load).
local gSlotCenter
local gCardSpr
local gKitSuffix
local gKitBackSuffix   -- the BACKS sheet's own frame-name suffix (gotcha 24: per-sheet)
local gKitLastErr      -- why the last heKitTryInit dropped to flat (for heProbeKit)
-- v0.14.0 UI pack: gAvatarOn[seat] caches whether a seat shows a custom image ("true")
-- or the initial fallback, so the 4Hz HUD toggles visibility without re-loading files.
local gAvatarOn
-- v0.16.0 sounds: gSndChk = init ran ("true"); gSndOk[file] = clip playable ("true");
-- gSndTick = rotation counter so kinds with 2+ files alternate without random()
local gSndChk
local gSndOk
local gSndTick
-- 2f onion transport: "true" once THIS stack opened the tor control
-- connection, so closeStack knows to oxShutdown what it opened (H1). A
-- script-local, not a gGame key, because gGame is wiped by every new table
-- while the control connection deliberately survives between tables.
local gOxCtlUp

--------------------------------------------------------------------------
-- self-test harness state, HOISTED (2026-08-16). These belong with the
-- harness at the bottom of the file and used to live there; they are up
-- here because a script-level declaration is resolved BY LEXICAL POSITION
-- and, worse, is invisible to any assembly that hoists only the leading
-- preamble (tools/build-suite-selftest.py refuses that shape now -- 81 of
-- this file's 188 declarations were below the first handler). A dropped
-- declaration does not error: LiveCodeScript evaluates an undeclared name
-- as the literal text of its own name, so kKatDeck would compare against
-- the string "kKatDeck" and read like a library defect (the kKatSeedsXor
-- lesson, one door over). Order and comments are the harness block's own,
-- unchanged; every constant's literal value is byte-identical.
--------------------------------------------------------------------------
local gRpt, gPassN, gFailN, gSkipN
-- the netplay loopback's live gGame contexts (host / player, plus a second
-- player for the ORACLE table's three-way star), shuttled by heTNetPump;
-- emptied when each section ends so nothing big lingers. gTNetPlay2G stays
-- empty (not an array) outside the oracle section -- the pump keys on that.
local gTNetHostG, gTNetPlayG, gTNetPlay2G

constant kKatSeed1Deck = "8h,4d,6s,Qd,2c,2d,6d,7d,Ad,Jd,8d,5c,5d,Ts,Tc,7c,8c,Ac,3c,Js,6c,Ah,9d,Jh,2h,As,9s,Kc,8s,4c,Qc,5h,Th,7s,2s,Kh,5s,Qh,9c,4s,Jc,3d,Kd,9h,3s,Qs,3h,Td,Ks,7h,6h,4h"

-- Phase 2 crypto KAT vectors (generated by tools/protocol-kat.py --gen-xtalk;
-- BLAKE2b-256 + ed25519, the corrected SodiumXT calls)
constant kKatHashEmpty = "0e5751c026e543b2e8ab2eb06099daa1d1e5df47778f7787faab45cdf12fe3a8"
constant kKatTableHex = "e52675650d7ad48c7129185efdaec1e2b89cc410d8e4c8e085bcd652187b27d3"
constant kKatSeed1 = "6c10d2dcff41a1a7e8bd9c7530052c7eb91b91808ee5d935e5f56098539eea3c"
constant kKatSeed2 = "f7badd5dc86a8a5dce0984ef43bcb7ec228398e08a854a8a8c455ff895dc8a49"
constant kKatSeed3 = "e848bf12b0bf2708b52c20053ef674e603e7f3a3c7092533dc92e1b0828960cd"
constant kKatCommit1 = "7623721b5a6372fa974ed62f558fce9992259eb2a834ece7bcea66bce970c0e3"
constant kKatCommit2 = "83726c97707155ba2e81f0e5f673dd9e10dfde06e1c8f643bdd8539403aace51"
constant kKatCommit3 = "5f043c34bfb7a626581eb8653c88503a5a8524c9b47bdc2e09e37780005e0308"
-- keyed-stream deal vectors (spec 7.1) -- these were dropped from the block
-- when the lobby constants were added, which silently broke heTestDealRun
-- (undeclared names evaluate to their own text, then heHex2BinD throws). The
-- full set is emitted by tools/protocol-kat.py --gen-xtalk; keep it complete.
constant kKatSeedsXor = "73e2b09387940cf29398389f4d4fef74987ffac3c369b68cb522ded044cb00b8"
constant kKatStreamKey = "e4d91a49ee23982afb804fd386cbd3d2df6370ae0a743b0f461325b94818e40f"
constant kKatDeck = "Ks,4d,3c,Tc,9h,8c,Jd,4h,2c,6d,9d,Th,3d,9s,5s,3h,Qc,2h,9c,8h,7c,Js,7s,2d,6s,Ac,8s,As,Kh,2s,Ah,5h,Jh,Jc,4c,7h,6c,8d,Ad,Kd,Qs,Kc,6h,Qd,7d,5d,Qh,Ts,5c,3s,4s,Td"
constant kKatHole1 = "3c,8c"
constant kKatHole2 = "Ks,Tc"
constant kKatHole3 = "4d,9h"
constant kKatFlop = "4h,2c,6d"
constant kKatTurn = "Th"
constant kKatRiver = "9s"
constant kKatSynthStream = "8eaba859db2f1a2a3bce5e381fc1afa1339dc9b7a8a1bbc550277e756dabdffcf7390d23167268d1523ac24f71f476cd47cd1fcd31cfa7ec51ef45c7853978859f7a10230ff86f287f1ead8ec6ac797f6f3d3a1eb75bcb435b5f491b81077775b47c0dcf3cc1d1c8f329c4e1cdae9c6e21f3825454f5c04a21fde75572ef04e25e36672b9e4ce78b4333da7090746ff00b8e32e7ad161f033523cb6f5ba2b10af1a1ebf6c815e54e4fe5efed623198c302732bf6e40ed8856a89e15d78f564614531b8f684aa727e51ea968727a22eb6e14bd588d502b2637bd73d59a8518eaf7a2311d555dd86147e83af7f1e9ef7c9baf253b851bbb48abecdea0b27f90761a67fb810022c6eae480866f19839deb884a4ec819be41bcb605df7dd1ee2efcdaab49eef76d4a98b6be858d3324ac616f2b1f58fc9a1749a6164e2a0e276d62d1815d6a042c78b82f3b0d1ff78852cf8778ba3e127411f0121775056de9e5f8e4253f98b54e627e74cf8c2a38c83edd7d6272de4eb6bd645ebcae1f1701bda866beadc5968e757a8f902e2be46933346dcb794676fd609e14f67d20432796eb492a0c86910f10e51c5c02e5a9fa95f407283b3d0abfb8357cc5f94fe4416b5984eb07e046975e1c15edece5c9e80fd6de3d43d6831a310fe9d74e0c5bb9e438da44bffd728a284795046da833ffb8fdd16128b7fdee7ef76e434e035c7471d52"
constant kKatSynthDeck = "Ac,Kc,3d,5h,Kh,5d,Qc,3h,2h,5c,8c,4h,4d,Tc,7h,Qs,6c,Ts,6h,7d,Th,6s,Kd,3c,Jc,9s,4c,Ah,5s,2d,8s,As,2s,Ad,9d,Qh,8d,Jh,Qd,Jd,2c,6d,7s,Ks,7c,Js,8h,3s,4s,9h,9c,Td"
constant kKatIdSeed1 = "629a089485b96c24fef651012c8deae57aa438a7a11c81f3e6a99b5e22f83b38"
constant kKatIdSeed2 = "fa645b9f3778a3b162514e3a00436568aef46b726e10ef563c94e73b2c2cb448"
constant kKatIdSeed3 = "7833fb1675dbb196e2222ad6f93ff30aacd313faf7a7818078e30a47f6890083"
constant kKatIdPub1 = "b6ef1a19d789c27bea3f6c127db635929541f34907750ee12d0b715c010c7566"
constant kKatCfgBody = "v=1,level=0,sb=1,bb=2,seats=3,button=1"
constant kKatEnv0ContentHex = "31096535323637353635306437616434386337313239313835656664616563316532623839636334313064386534633865303835626364363532313837623237643309300962366566316131396437383963323762656133663663313237646236333539323935343166333439303737353065653132643062373135633031306337353636096366670937363364333132633663363537363635366333643330326337333632336433313263363236323364333232633733363536313734373333643333326336323735373437343666366533643331"
constant kKatEnv0SenderSig = "c1d5f49bcc0fb8418830f63cc8be9c6bf7e5fd11a77807af38e672aa7284bba9c9cd58d73976888055851d034d440ab504cd0c9ab984f7df368a5f94225b310b"
constant kKatChainHead6 = "62fcd52b3757f590c33bede7330620853074c1e5c153549244a8dac7287e3778"
constant kKatSettleHash = "68095dcf5a74fac1e1340a1073a466dcf117024257f5c265de21698257b34b6f"
constant kKatAdmitSig = "17cf45eeecf27a3e9b63e1e0ff47ae1ea337430cb135fb499944a60681fcd1e949a7a88f532b2f888c0ea32364e93e9aa2f569419f27e8034b695a4ee94d5e0b"
constant kKatIdPub2 = "833fed8ee30a882bd877555a9df260d4322224fa095513d84972a660e7ad6b10"
constant kKatLobbyCfgBody = "v=1,level=0,sb=1,bb=2,ante=0,stack=400,seats=6,button=1,act=30,bank=60,miss=2"
constant kKatRosterBody = "833fed8ee30a882bd877555a9df260d4322224fa095513d84972a660e7ad6b10:player,b6ef1a19d789c27bea3f6c127db635929541f34907750ee12d0b715c010c7566:host"
constant kKatLobbyHead2 = "57c56971affa1ac3d723d600937df12046a7def0c059444054f763e94a65b7fa"
constant kKatCkptSig = "08c7f29409998d642657b9a084802b7ca3a136d696e881b545ed4e5a750fdb6d14e4967f401977aca416f03c0d4f03f98b3acc53e61266f3d8cee9912639e20f"
constant kKatSettleHash2 = "5e716ce9022f4c47d99e081b52be3a8bb5f9f1f56d3def18577c2f7ac9de8df5"
constant kKatRcptHead1 = "53ed9ccc64863dc05c1b76cd7953e19bba73895b8dd22ea00e6c9ff40f423cef"
constant kKatRcptHead2 = "0284af24c750eaaaa5a521b87d8f1ab6ce00b0b2be074ce03d24884e004fc910"
constant kKatRcptSig1 = "222929a8ce05e0d45cab6658d9e67d882d6cfa1f91c35cda8e07a58763c4b1fb6c733e23d116f04ed91960c0ad386541139fed43e1632df341175021d70b1700"
constant kKatRcptSig2 = "20a21d334da7d32b00bf3a17920350ebaad0773121fc3f2d9feba041360d9548fb527c555cab8039985439bed3af73d17656b939942a6bc3a793630275070706"
constant kKatRcptSig3 = "429a37ee32d74fd2d09b1b3a86fccc383c7e773ef52670ed07e4ede7e2e10f9ab4b791d630d0b44bdb6c405ed5238cc0bbab9d40129d3673c2c39f1d5d1a9c09"
-- 2e street ckpt + show/muck wires (spec 6 as-built) + spec 9 election +
-- Phase 3 oracle seeds/cfg (generated by tools/protocol-kat.py --gen-xtalk;
-- keep the block complete -- a dropped constant evaluates to its own name)
constant kKatCkptBody = "street=flop,head=62fcd52b3757f590c33bede7330620853074c1e5c153549244a8dac7287e3778,sig=08c7f29409998d642657b9a084802b7ca3a136d696e881b545ed4e5a750fdb6d14e4967f401977aca416f03c0d4f03f98b3acc53e61266f3d8cee9912639e20f"
constant kKatCkptHead7 = "296cfef0944557351fa4899e8da5722743b4cfd212206dcf9a2b89fc30331497"
constant kKatShowHead8 = "969def7cb20b499f2ae3fa259234f09ac79cd4608e65b2d25b2027217a82a45c"
constant kKatMuckHead9 = "5fbfd0aeef7d918249601a92233de273809dc1b4791e991e22758ba85af6df71"
-- 2e liveness wires (v0.23.0): the seq 10..13 transcript extension --
-- host-authored timeout act/bid (timeout=1/bank= marks on the EXISTING
-- wires), a seat's own stand (sit-out) and pub-less sit (return) -- plus
-- the onion hello's trailing-seq trim frame (tab-framed, so it travels as
-- hex of its UTF-8 bytes, the kKatEnv0ContentHex convention)
constant kKatTimeoutBody = "verb=fold,amount=0,seat=3,timeout=1,bank=1"
constant kKatTimeoutHead10 = "bb5c70e38815d017dbcd3be3654fd8691fd2513bd816a5ab33659e1103fed694"
constant kKatStandHead11 = "fc854db9ed13c5dcaf7ae7455678c87b4a0e1a6286e88ad98dd61dbf173e8ef6"
constant kKatSitBackHead12 = "f69afd084f98085581135c43346641dea04f2937952becc641e9922709ea6cdc"
constant kKatTimeoutBidBody = "amount=2,seat=3,timeout=1,bank=1"
constant kKatTimeoutBidHead13 = "6324a6371f62ec9819d0a53acace305c3faefd274efe5db87bf869e1b4a57fcd"
constant kKatHelloTrimHex = "68093833336665643865653330613838326264383737353535613964663236306434333232323234666130393535313364383439373261363630653761643662313009706c61796572096430326231653832366634333531323634636433613737613135383039323134393566396337646635663066323961333730656262356664643639623961316335633163393232366165323836353931393632326132363664663132346163373535623537313431613664386137376530656238623666376438396465323038093432"
constant kKatIdPub3 = "ad1d6dbbd062cdacf356daf0834471b6246105b17e3b988dd5e7f0db45fb66a6"
constant kKatElectedHost = "833fed8ee30a882bd877555a9df260d4322224fa095513d84972a660e7ad6b10"
-- the same election with the LOWEST key's seat SITTING OUT: spec 9 elects
-- among LIVE seated players, and a sat-out seat is not one, so the successor
-- moves up to kKatIdPub3 (heNetElectablePubs' sit-out filter -- the half
-- heElectHostOf cannot see, because it only ever sees the candidates it is
-- handed)
constant kKatElectedHostSitOut = "ad1d6dbbd062cdacf356daf0834471b6246105b17e3b988dd5e7f0db45fb66a6"
-- the two TRUNCATIONS of the same digest that no other pin covers: the spec
-- 10 DHT rendezvous id (40 hex = 20 bytes of H(tableId), the id BYTES) and
-- the spec 5 display fingerprint (8 hex of H(pubkey), here kKatIdSeed1's)
constant kKatTableInfohash = "891e5f5c70b88414190980f34a02cb06784cd6da"
constant kKatIdFingerprint1 = "77d2c2dc"
constant kKatOnionSeed = "77061b1432063cb55aff898386cfe8948a1655627114891d10e6a5cb5af729e2"
constant kKatOracleSeed = "6e027a075cd69ea09e20004167c54c12491c5538f105c138a0bafe49d956e5d0"
constant kKatLobbyCfgBodyOracle = "v=1,level=1,sb=1,bb=2,ante=0,stack=400,seats=6,button=1,act=30,bank=60,miss=2"
-- Phase 2f invite vector: a STRUCTURALLY valid v3 onion address (56 chars of
-- the base32 alphabet + ".onion") for the pure invite-parse pins. Its
-- checksum is fake by design -- the parse is structural, and the checksum
-- round-trip runs on a REAL derived address when OnionXT + SodiumXT ABI 7
-- are present (section 17). KAT INPUT, not generated.
constant kKatOnionAddr = "abcdefghijklmnopqrstuvwxyz234567abcdefghijklmnopqrstuvwx.onion"
-- Phase 4a-4c Level 2 vectors (generated by tools/protocol-kat.py
-- --gen-xtalk; the ristretto255 deal algebra from FIXED scalars, pinned by
-- the file's independent RFC 9496 reference). Keep the block complete: a
-- dropped constant evaluates to its own name and fails like a library
-- defect (the kKatSeedsXor lesson above).
constant kKatL2Scalar1 = "38f967b55df92422303a885e0bdd8400e52e6ca53623f2c816bc08ce6b7d480a"
constant kKatL2Scalar2 = "04db114cfbf9228a88b8533a2fd8f7b3d023db8adb22abf3ce804a33d105e804"
constant kKatL2Scalar3 = "380b4308d6301ffd7c124b79b15ae31343e221dfc77d6bb4c1ea48de8f34810a"
constant kKatL2Inv1 = "05e469c6d0880a9b8e27c9cfc6b887171837d1c5b5e01a9bc0320fe70a64bc0f"
constant kKatL2Inv2 = "5211b8e991092be89603c8b33eb590833774d63832f1294b7f3dc2b312112b0a"
constant kKatL2Inv3 = "8cf1653acb11f8ea598fe0918c83210d1282a4218f4cf9546a5907f3401c6403"
constant kKatL2Perm1 = "35,31,39,27,36,51,26,11,7,49,18,9,28,24,40,50,25,44,45,34,15,2,13,5,41,3,23,12,33,6,29,52,20,10,21,42,17,46,8,22,38,19,32,47,16,37,30,14,48,1,43,4"
constant kKatL2Perm2 = "30,35,31,18,7,33,4,50,38,19,15,2,29,44,49,16,22,51,47,9,5,10,25,12,6,21,52,24,14,39,8,3,20,37,43,36,46,34,40,26,23,48,28,11,41,42,27,32,1,45,13,17"
constant kKatL2Perm3 = "22,14,28,2,48,29,37,23,52,32,38,25,30,47,43,5,11,3,39,20,1,45,50,21,51,27,15,4,9,26,24,8,19,36,41,35,18,49,7,13,46,6,31,34,44,16,12,33,42,17,10,40"
constant kKatL2BaseDeck = "f43e364e1c1a4da57953b755e62e4a21c6ca54dad6c8afdd4fe527d1fa0f1471,e2b5c63bf1cb966f79bb5dd8049eb0fca145588b5128a6f7322acd1012e45b7c,ca68072db08307f62268023fb580e8148aea78f8b87e7b1d2691a922b5245446,b6e6777a5bf7657fd842629a537b02f06bc9e9c202d51b27cdd550b61c8a8a18,d68850b61f37953e920659d48ee504a51addd0e26996f0719188dad7f37fa52b,0c4a3a1a25314e3144391e6133bc6c7b135fae6673fbe9a0889dd5ed477c171a,4acd93b546fc640606953a84123707ad9a1617357d00e5f763084daa6a0d3840,dcfd9215cf8a022e2198e87af9f4c08059504ffb309a6dd1ff97917b6012902f,a825c649a65028cfa090453b8f8d7c91b5761a4df3c3a099105f764d05bbfc79,a2751a23688be97fee506a367e917f2d1b0b8445d56679fb66af2aca3f1dbc04,e2fd88a0a2bf8ec954e1bd7c637e9c5e810195e3614a09ee400adf6d8cb8c856,78f3c83c94a84614c0589b3f58269687a539de6a4cae5c02449f95bf6a46a46b,a40fdc57edfa2dc321608b50e782cc6f0907f65eada0ad48a25a00f546d0987a,22830c692615fc4b2a8ef1e3f8fbedc51a720107e359f9d2c1af737699af733b,d8ee75f4266debe97bcb495971922583ebb97ad60b78f5e9c1d187972bb1ec1b,44744fa706cee62e39546bb3f60b86c8563625be486dd73ae41bab0fd1a7cb00,4cd2d796f2e9e21c10b4db346d08ec53bbc7af1338f605d1d7e9a5244500af74,4aad6f63cff471e83ab8abbfefc7c52c4ac7e38eec8bab874a98db796b69f710,6ab24c9cd511a4fed28e34f86a40198700626511d05fc986eb5c4e0ac0688245,1a815ccb611b5b5fdcece3e811bf479e6d866f5211c4222766008c7de0b3fd77,40ebc4540b298dec8b107d3465bae5b4298c0d9dd0b052b6ee35085a15967043,1e7bb71f06a5a72d4f6dc5f0e5131b3ed38f344ae8afe4ab6325bd71d97eb770,0e6ac715b89c1b7350d1216965122c5565009b7d9140e0090c4041932c8a5a35,72edfa2243b1b418c24d89f6c7cc3444367945ead40cc152c1a02ed74b894d73,1af2d8904604eb9de539209d048932660026be3e09f1591deed8475b466d9c1d,98afeba72c1aad9ef62bb78730b25e81fb8c0f0aa496f5f558d4a401fb08dc32,2436bc86ba0f7a7a065a61e572021e4ba2f58edba7cf529d0f2fd9c852938d6b,36ff7c85101d8f18a8a98e16d225b56904ae11e5d4b3d441b0213237d274ee1f,9e3d2f7ba70b89df9fbeb9be41281e3738937f124195772e032c3d1fdb78f855,1cd179e72cb1b79eec94f4a249cb7ca303be533cf60004d22d18847ea06b6f74,ee9bf366559e64e3120c89a71b3a3f5157e901b52035c77add57f1e77631c621,62bb8617c9d4a3868b2685d0b68251a7ed77a438835f3955a809cdf991da5144,64b530ce023f8108b30706674fb1d50bcaec450e24b2eebebde1d0039be87b3f,6a88be3b6e714f8c47eb879456ee5343a54ad0090b1f8efa2ee3c55654b7cc16,146f81383fd8305ceec4ca6d3d59cf1358ef3333c708b6e6bb4d5dbd7cebb335,ccdf0af1f4608a4186a2ebddd4729174fb696a72606c0205bc237a181be2e006,248e4956f6625bc4e38f1025413893827006ec904f1d9e48f5bd8b9e8cfe622e,569050be976d1b9f7c3bb79534202819d33b2f747a04b34b00f74e4533f3d534,e686afeda75fbafe47f550a9914e5872f867fd144be9727906844fd7a5efba76,46f0ee3869ccfbd02973504688e82360867cead0540237b88cca8dd64ab8653e,feaa1f3bbfcd9f3e3428dc887d61612bab06635b7991abdd34ec69e01cd21a09,7ac0547ac2ae5c08f7b7dd14e1f2fd46d4110cc464c54379ed738e877bcdb42d,0ad5483deee6ec96989b844a54a52d93fdf9d61aa1c8bad49de64001e0aa7e42,7228ec86b2507b1f73de6668f23b68b01af1cbd1a18bc74b56bb98e0d1044d32,d070da71ae4c8f56464e6a9f0c0a7265f062de5047bce758957a37c3c06b4272,18b94704378b8065af2d9603b0e7a350105628025c8093ad9d6991c8efcd747b,967b07c684c6865789f35f3d3aaa16fae3f7d16d82b13dfe9c06fe79cf6f8578,a4467ecf421b21ff1783d95a45790c51a5904d0da89edfccf0c142e07b558901,fce090799a09255f8066bc186f716f53b7df53a54c38e4d4f83ce7a9800cba6b,d0f0a3ca37ae84285a38836c0abba3536af53cfc32ca1681347baec559f47b7b,88ce578d9d4f057a76486e5f2e15fce75b1d07ea6d23efcb5d0ed421e1d35c37,50532c4ee88d1439e01a61f151c2f25f1ba2319c2d32f943ecfb1264d03ed72e"
constant kKatL2Deck1 = "a8de3428db2d1cb591341ac375bbdb0581bd46f80d2804e94e71710a3b48541f,6208a4235f8ae00a67e3c8f0ebbbf2c97fbcded0363569d684a174c9f9c33472,d80f7d6653463748864517be750974916e0139fe3afcbd1a5e05481471d1e71e,0cb1f4e9cc67e1d58c88b5141f12c64caad25c5cbd5641ed6eb7433ffd9b236f,aca2977971dfa44ef40e9086ab5b58f635f25993d91d1c9eebec806b42e2084d,b42c199b8688e4fa95be56db11c0f269defd692ec3d56726055f4f2e3bf15c22,be8fd78c93e5096e7f156a4b6401874965065c9a39abdb57d2e278b5252cae03,b83bf82a7d4192df111443cde252d748245569be844c373078c97b3c5c21d042,380662f5a44beb9168bad94af183a145d6aa68330087e47c2413e1c02255ce7b,880321e01b402cab8e58739e24b8650502e87a1e53a728f4c7120f85cd79ec31,c4a33acbf3a9748e75320863de31088d2c156358797f55c1992e11ea95a5e768,a610eeaa66e3a4f799ab05ad0a5791ccf155fe9105815c8a5a27341cf00c3e20,ac94ae783e70f5b4db4e723283815cc2266fd5def3d0063ac58f50444e6e6620,ccf2a5e4813136eebc70cc00c8452d587701f378214aaedd1ed577a7f1c1020f,2ad863fc5aa197b4c35efccdb87379ebcc84a15a046bdf7fab33ffb9acd1f759,9ac91cad66318f80906c50bc9c2161ff4204fdd5e573a71c9409b5e92ecfc446,06c97bc904c39b8f2f13833ca41b376d0a70df99c3f48ce81c63e827c700b135,82c2bb912824f452cb8d62f5acad8b700324d13083016ade60dbebd0e24adf16,4cbdb1a1a87e1b2087df92f229a7e3d646f841a730275f3a355647b79d4c726f,202a2868ad6d3b99b4646a08f4f571e2373221ff58df7af32ce2801d1d725770,dc1d10c111206bc0e777e46a9fd5a56a2df56f37cec67f5261c26aa12a2aa937,9ef54cb33db9d77c664069f15bf54061ed01e075b5a5846bff366acb7f477d37,30dec7a12b6fd2f973683dfa053865fa8aa3f08ea5325a10e27aad97020bb729,6aae1939f32cc599e76e968455a30ce4d82280274ddaa3da099226aee642b57a,cac50035ec7bfe2a6f0091969ce08045b28b5fcaf6502d8aae107557e3c3e109,70337dc2f81c273be97d83f42e8f36ea03acec7451c0f6472155ffc4ac0f3518,02bbda5b5f1987ec365739fb37c2a599d2b725bedc0c204deb31fea49b5a9c4b,b4eb5d98403b1e5276994305fca33f4aa508978ed4edd923f18616783458b118,90f8bce01a01e5b30373962182b648c731452a2ccbfec2dba91de8fb022c193a,12cf3f7c4cd5cbc9b1fac833454ef6dbbd7ddd139bfa3812ee19b2bc3a34753f,24fc8edd6bcccf04c49b2b4b337131f6d4fd4d36d1b1c4ba6ed1a24ebeaf581b,98063c80c1bfa451e791f19fbb52723a302c94d16dd01f52425b6a496413785f,6e161fd50766cbd972d31ea5fc0b90807a4a103bf79b9766427cdd7fc4e3521b,8a835b4edd4375f1e2e908f14f1a47ba48e2cd499dc90a64040333d9c9344a74,94deccd57786903f49e7783e30b373781ffd162eab5f095ebdf99f088a048e4c,f0e6fd4c43e8647095384db6e110202c691408d6c9be53f00b4b13023a24d217,b61e937b2825e50de783985a69279b1e07cf45b2113c4ada5a78b8951f57ae0d,2239b5510058e2962e0bd9cf17f54fde38cb3d76f0503ce5ec4e132887c9a571,10135c31a39b36a2af83c0a0ff759facde77bce17b6350579c706f656486a10f,acdee51d73bdf6ee8613c73739d7c897d97a52fb9c6c4a0104395ea4806f2047,6ad5cc0f70a07befcbfbd6abcdb0279a579968e51555c36af6bc6b2bb0f6a010,aa66031a9585d3487f62170ad6bc236d81dbdeff4e0287dcce6e971afcfd4150,205f6e66b3d54d4e23e7be0512194444a13e76ef53bc032773e3eb1ba615015f,1cad41fa4896a2192cb96763568fd7b0b1a17a641235c571d6b9f735f970d800,fa91391acee3da6ce5beb220842c6d3a89b127d898915d78569becf98e42c405,92fd398554c27e6d525f6ab451a60bd34773fb627f5ac5e335ba26ba01d30c39,c202fb60a22eebdf70b871f93f0c871b97a602f2c46e77c9bf6517e5eac87677,2ef2dc398f3c20aa0d472c7be964b1450c8aea652cbc950a0684559328771371,e6ac5b83882b4f694775463dcfa35b30e269be84200826242615191af8072b7a,d4e11d4f0dba15abe5ec94e448871bd11e00e7c5f8c301a5573fbccd3ea2cc04,e4e0dfcd6cf502920991dd5789504d3b4764db3ca8b5a7356d6e1fdd70ffc274,d69d1e07c98931eea27cdd197eee2dd78d2d787adfc8c21dfef0968b9aed5d07"
constant kKatL2MaskedDeck = "1c4a4cd95ab5df7e3fbb801b47c156e726bc8ffef83cb6892e979e12f2f40a18,62e9d101a14e45cbea8506f23a225d6da973a3edfede81a99b7e81c3b9957827,ccbd8b67ded62a4c617adaf2661b6a5f3b321f8ac82d4ed631e174f17e016872,9087ea23c9a04974739041651d08ffaa60c83fe30e93c37ead172ddaeecea577,520321aa5411f0102d9854d7c36d0d9c0d218634c44655b99a3a78256178e774,8c155652fd2bdc7f3b1bbb3e960d9eb5097366f62c924b1c92bed58e945f9f19,1ed3f96f1a7d03fe3da78c54c209ed98aa2f2260bc5ff290ab9cb8ce1391ac0c,b632f200ca5decad5e041fa1d2411ea3555cd46a4b64790ccfe0c70c4de34a0f,9a4602b46bde2c6c860f9e7b9562ce87b62053c75daefeda0ffa3d72e13c4a05,4476b7e54b72b9abda47c42c7a0b55676acb865a9949119d2814a028b381bd10,4a0bb09499996a33d379909b8b7f1c6b48f276c76d7213abc82e920b2155872d,1ce9352e0a5505d7a67c00e0139bcd32ba585c84e416310e92eaccd4ff10245d,dca2411b332e647eec34df62d5fb8162d850bb831a115d1e71d51dce55eed626,56ba017c3ad1ea1126093efca04c749d085112132a578ec755d23a777f982f23,6edb77fbda06a59d0afa90686f9945efa863434424f74a1739c3d5153015f357,fa8273b7c9a231dfeb3ef71bc77788e7d357f292731c79cd2c52ef76acf47a29,c0ba5d3b244be2b869252cf23988a8063908520ff3e34ceca71cda4bbbc84b04,a8c3d44a17fbe150dedf35fadb9f3d5a3fbcf400f20994b4f0e1620478301a15,5e3168d6f5106aca4fea6916765ad28931aeba746d4e5c438e7257a053ec255b,3e59ef03c2f78b1c0be06501b254cee66608e3570dd08c9f16a2256f0585e476,20c2fcd252741106fc6bac82a30dccb3d9bb05f4c65891ebdc81d20cf4c6831a,5a954722e48f2a0534a26271ee77809fe27111152e77c161091d5c78476f6819,b42ba308571bd4f27052bf38ec82b50755dd22d97832cc4eb784630264d99638,a871a574b10e19d6431ae82e6f3d67571e29225e137d44821e887e1efceef715,a2d8ab119c8a7c9f2746cff786f8514fee315631e54c1850a20389b2e2d57e0b,6cc6bbf761404aca110b92e36e637dd5a8bca799e5680077654b0d0f192fa554,7cb1aeacfd37b1d7809c7d269c15737c7f746507c4358a30291c40a0efcfc13f,603aa0b85684a71fe8be7edbaa26cab094c4633df389f818faa6d1dbe69a4a51,2af6de55fc37181ad678f8dcb141c365f875d9a571b8e9727f8c963066792e62,38b0fbfdf0cdb815094dae6ae1ebe102125d5fc5933d2bf42ce9bc2bddd4eb0b,38f162c482282626597a32d0eff26dcadc22ea38b1e107c1934b905397d8b973,9c5f3d94578d122f329b825a8563b03d12b2e5b96916e83f1ff00264df8e9c67,767ac5e92db1ea84be5cf73dd70a39c61a7024e3464e109e36ff2c62b14a7235,308cdbdc2f3334271ef4d25e7f7ecc8933b5918ddbe819bb3484d3fa02325c27,8e8544127ae68c2a8d18a9c8cb8d37a76758916286ebf17597b17b9283b5f909,c0ddddd1e00241611d3c045b85d45b0fbf3ac2ae0078fd928da2955579339920,48c8be8d6374e2763cf6ab51e9a84863ad9d322098006243c8e1eaa318479e78,b49934b95c8748348fe21a30f191d080c805aae4e3505555f324b6974379ab68,bc2c0a3edf2c8f9c761980bcf13d444455d846c2a137a582ca8679ead71ee604,b463da981cfef69817ab80245630bf70deb604820fc87265719410f72462de35,6c7dc076178538735f5e1a890a21f054a9d81039f72424b65be5b041b5c3fa4f,8015469fa91721b299a3b6f7522478398820085127429312e17d42e5a40a462a,9abd2266d21ee49b0a6fc227a6ae21a8a18e8f0019eaf35933518d61f71c4052,d4a31d2d53796a3ffa6f12de5ed0de6cc2131a5d811c6b55505a5e58317af20e,b4e06f3351546a873220664a0585c506524e605453d9ea7d0de46bae5c90ea24,f4383b63dcb04aa7d70595c1450cad7842552095c31328d1c2ff3a5b3469067b,4876092cf6739c17bab348b6ff2d05feb8d00ecdcc865c5c17154b80f157c301,f4bb4c89cacaf8727fd11878f03b9fa47cb1645f5db293a656d3ba3b2641bf3b,da8fba36a6c821b0125984a1b9432c0911849f7fe6183c98abd940dad8d41b41,7247827e28f0b6116ec614a4d713f49ac291b6112f4ad0dd5f3a4f92bc331c02,feef6df7bf025f0f0b77c2fd40da954c44be8b85ccf943301e888e783a312307,e625479c6e3b0e1f1bafbe6f7e7630bd8c7c8c583e802b9282255bfe27574136"
constant kKatL2PublicChain = "1c4a4cd95ab5df7e3fbb801b47c156e726bc8ffef83cb6892e979e12f2f40a18,dccce0c6d9e263337316e3487d17796b76d3057c9473c40b95be7b4b78a10069,54a040c81ab1aca13bf76c725416660af35c171209001e3abfb7aa6f56e2ce24,fce090799a09255f8066bc186f716f53b7df53a54c38e4d4f83ce7a9800cba6b"
constant kKatL2PublicCard = "card:49"
constant kKatL2HoleChain = "62e9d101a14e45cbea8506f23a225d6da973a3edfede81a99b7e81c3b9957827,80b56b50f6eea1ab201aaa93c738dd6441f5842f256bb890a5ebc867e5807c70,3a18dfc38fbbce3503f1fa5b45ba7b88c547799f663ecbd38d7474aa2aadff5b"
constant kKatL2HoleCard = "card:47"
-- Phase 4d/5 vectors (generated by tools/protocol-kat.py --gen-xtalk): the
-- DLEQ commitment keys of the three fixed scalars (ck_i = k_i * B) and the
-- derandomized Chaum-Pedersen proof over the pinned unmask step (statement
-- c0 = k1 * v1, i.e. prove(k1, v1, c0)). Keep the block complete (the
-- kKatSeedsXor lesson).
constant kKatL2Ck1 = "f8aaee2dfe3f251d8726037421fd646a85446b00f132dc37d0792a7e48a08a03"
constant kKatL2Ck2 = "94d02c9027dffcedbc3fca0569b23d13fc966462b5208b5a25668ddefaa4ea65"
constant kKatL2Ck3 = "9ce4b6a7337e94a6c60535fccf71ee83a69745b46359fa9bd0a1846864ad1458"
constant kKatL2DleqProof = "d84b045c40a2d08257ef6907556d4a096a26f0777b2a8c213db9736e403150048634476eb775e61807679da17345da913e9ae89959a0dd3a5ed121483a4de064c838dc1234a84786a24f5c120cf28dc410b59d28213e74c4befbc1992fbb2e04"
-- KAT INPUTS (not generated): the canonical identity encoding (the one
-- VALID point scalar mult must still refuse -- 32 zero bytes) and 32 bytes
-- that are NOT a valid ristretto encoding at all
constant kKatL2Identity = "0000000000000000000000000000000000000000000000000000000000000000"
constant kKatL2BadPoint = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

--------------------------------------------------------------------------
-- lifecycle (house law H1: sessions bracket the stack's life)
--------------------------------------------------------------------------

on preOpenStack
   set the rect of this stack to kHeStackRect
   set the title of this stack to "holde-em " & kHeVersion
end preOpenStack

on openStack
   heCfgDefaults
   heBuildTable
   heTableNew
   -- open on the lobby so the first choice is host / join / hotseat
   heLobbyShow
   heUISetStatus "Create or join an online table, or press Leave to play hotseat."
   put true into gHudTickOn
   send "heHudTick" to me in kHeHudMs milliseconds
end openStack

on closeStack
   local tMsgLine, tShutErr
   put false into gHudTickOn
   -- H1: never leave a TorrentXT session running after close
   heNetStop
   -- H1 for the onion transport too: if THIS stack opened the tor control
   -- connection, free everything it opened -- oxShutdown is OnionXT's
   -- documented app-close call (idempotent: streams, services, control).
   -- Guarded: the library may have been unloaded since (H8 catch local).
   if gOxCtlUp is "true" then
      try
         oxShutdown
      catch tShutErr
         -- OnionXT gone; nothing left to free
      end try
      put empty into gOxCtlUp
   end if
   -- cancel only our own timers; pendingMessages lines are id,time,name,target
   -- (gotcha 5: set the delimiter before parsing -- closeStack inherits it)
   set the itemDelimiter to comma
   repeat for each line tMsgLine in the pendingMessages
      if item 3 of tMsgLine begins with "he" then
         cancel item 1 of tMsgLine
      end if
   end repeat
   pass closeStack
end closeStack

--------------------------------------------------------------------------
-- SodiumXT crypto seams (Phase 2). Every sx* call the online protocol makes
-- goes through one of these wrappers, so the ABI shape lives in exactly one
-- place. CORRECTED against SodiumXT docs/api-reference.md (the v0.2.0 crash
-- was calling sxHash with one argument; it needs an output length):
--   sxHash(pData, pOutLen) -> Data          (BLAKE2b, pOutLen bytes)
--   sxSignKeypairFromSeed pSeed, out rPub, out rSec   (COMMAND, out params)
--   sxSignDetached(pMsg, pSec) -> Data ; sxSignVerifyDetached(sig,msg,pub)->Bool
--   sxSeal(pMsg, pRecipPub) -> Data ; sxSealOpen(sealed, pub, sec) -> Data
-- Everything crosses as Data: textEncode strings before hashing/signing;
-- textDecode(..., "ascii") the hex helpers back to script text (H3/H6: raw
-- Data only ever appears inside an sx* call argument, never chunked).
--------------------------------------------------------------------------

function heHasSodium
   local tProbeErr
   if gHasSodiumChk is empty then
      try
         get sxRandomUniform(2)
         put "true" into gHasSodiumChk
      catch tProbeErr
         put "false" into gHasSodiumChk
      end try
   end if
   return gHasSodiumChk is "true"
end heHasSodium

function heHash32 pData
   -- 32-byte BLAKE2b digest as Data (the output-length arg is mandatory)
   return sxHash(pData, 32)
end heHash32

function heHashHex pData
   -- lowercase-hex string of the 32-byte digest, for transcript text fields
   return textDecode(sxBin2Hex(sxHash(pData, 32)), "ascii")
end heHashHex

function heHashDomHex pTagTxt, pData
   -- domain-separated digest, hex: H(utf8(tag) || data). pData is Data.
   return textDecode(sxBin2Hex(sxHash(textEncode(pTagTxt, "utf-8") & pData, 32)), "ascii")
end heHashDomHex

function heBin2HexS pData
   -- Data -> lowercase-hex String (sxBin2Hex returns ASCII Data)
   return textDecode(sxBin2Hex(pData), "ascii")
end heBin2HexS

function heHex2BinD pHexTxt
   -- hex String -> Data
   return sxHex2Bin(textEncode(pHexTxt, "ascii"))
end heHex2BinD

function heIsHex pTxt, pLen
   -- true iff pTxt is even-length hex (optionally exactly pLen chars). PURE --
   -- no FFI -- so it can gate sxHex2Bin, which THROWS on malformed input. Every
   -- hex field lifted off an untrusted wire must pass this before heHex2BinD, or
   -- one hostile/corrupt frame throws uncaught in the poll loop (house law H4:
   -- verify-or-drop must never raise). pLen 0 = "any even length".
   local tLen, tCh
   put the number of chars of pTxt into tLen
   if tLen is 0 or (tLen mod 2) is not 0 then
      return false
   end if
   if pLen is not empty and pLen is not 0 and tLen is not pLen then
      return false
   end if
   repeat for each char tCh in pTxt
      if offset(tCh, "0123456789abcdefABCDEF") is 0 then
         return false
      end if
   end repeat
   return true
end heIsHex

-- Identity keys are derived by calling sxSignKeypairFromSeed directly into
-- plain locals at each site (the proven-safe form -- same as
-- sxBoxKeypairFromSeed in heProbeSodium). No @-reference wrapper, so there is
-- no script indirection between the foreign out-param and a real variable.

function heSignDetachedD pMsgData, pSecData
   return sxSignDetached(pMsgData, pSecData)
end heSignDetachedD

function heVerifyDetached pSigData, pMsgData, pPubData
   -- never throws; a bad signature is false (spec 6 verify-or-drop)
   return sxSignVerifyDetached(pSigData, pMsgData, pPubData)
end heVerifyDetached

function heFingerprintOf pPubData
   -- display handle: first 8 hex chars of H(pubkey) (spec 5)
   return char 1 to 8 of heHashHex(pPubData)
end heFingerprintOf

command heProbeSodium
   -- diagnostic: exercise every crypto seam the online protocol needs, each
   -- in its own try, reporting ok / THREW. Prints to the message box. With
   -- the corrected signatures this should be all-ok on an engine with
   -- SodiumXT installed; run it once to confirm the Phase 2 surface is live.
   -- tErr and tOuterErr MUST be declared: an undeclared catch variable throws on
   -- strict OXT, which is why this probe blew up only once SodiumXT was installed
   -- (with it absent the handler returns before any catch can fire).
   local tRpt, tData, tPub, tSec, tSig, tSealed, tOpened, tMsg, tRecPub, tRecSec
   local tErr, tOuterErr
   -- the version is stamped in so a STALE paste identifies itself: if the line
   -- below does not say "v0.10.1" (or later) in OXT, the running stack is an old
   -- paste and needs re-pasting -- that alone explains a probe that still throws.
   put "SodiumXT probe (holde-em " & kHeVersion & ", harness v" & kHeHarnessV & "):" & return into tRpt
   -- ONE outer guard around the whole body -- including the heHasSodium check --
   -- so nothing here can ever escape and abort a harness run; whatever throws is
   -- reported into the probe text instead of killing it
   try
      if not heHasSodium() then
         put "  SodiumXT not installed (sxRandomUniform threw)." & return after tRpt
         put tRpt
         return tRpt
      end if
      put textEncode("holde-em probe", "utf-8") into tMsg

      try
         put heBin2HexS(heHash32(textEncode("", "utf-8"))) into tData
         put "  sxHash(empty,32) -> " & tData & return after tRpt
      catch tErr
         put "  sxHash: THREW: " & tErr & return after tRpt
      end try
      try
         sxSignKeypairFromSeed heHash32(textEncode("seed", "utf-8")), tPub, tSec
         put "  sxSignKeypairFromSeed: ok  pub=" & char 1 to 16 of heBin2HexS(tPub) & "..." & return after tRpt
      catch tErr
         put "  sxSignKeypairFromSeed: THREW: " & tErr & return after tRpt
      end try
      try
         put heSignDetachedD(tMsg, tSec) into tSig
         if heVerifyDetached(tSig, tMsg, tPub) then
            put "  sxSignDetached + verify: ok (roundtrip verified)" & return after tRpt
         else
            put "  sxSignDetached: FAILED verify (unexpected)" & return after tRpt
         end if
         if not heVerifyDetached(tSig, textEncode("tampered", "utf-8"), tPub) then
            put "  verify rejects a tampered message: ok" & return after tRpt
         else
            put "  verify accepted a tampered message: BAD" & return after tRpt
         end if
      catch tErr
         put "  sxSignDetached/verify: THREW: " & tErr & return after tRpt
      end try
      -- the sealed-box surface (sxBoxKeypairFromSeed / sxSeal / sxSealOpen) is
      -- SodiumXT Phase 4; a build that ships sign+hash but not box makes these
      -- "can't find handler". That is EXPECTED on such a build and does not break
      -- the game -- hole-card sealing is future work, and heIdentitySetup guards
      -- the box key so a join still succeeds.
      try
         sxBoxKeypairFromSeed heHash32(textEncode("box", "utf-8")), tRecPub, tRecSec
         put sxSeal(tMsg, tRecPub) into tSealed
         put sxSealOpen(tSealed, tRecPub, tRecSec) into tOpened
         if sxMemEqual(tOpened, tMsg) then
            put "  sxSeal + sxSealOpen: ok (sealed-box roundtrip)" & return after tRpt
         else
            put "  sxSeal/Open: roundtrip mismatch" & return after tRpt
         end if
      catch tErr
         put "  box surface (sxBoxKeypairFromSeed/sxSeal/sxSealOpen): THREW: " & tErr \
               & " -- ok if this SodiumXT build has no Phase 4 box handlers yet" & return after tRpt
      end try
   catch tOuterErr
      put "  probe aborted (unguarded): " & tOuterErr & return after tRpt
   end try

   -- heProbeSodium is a COMMAND, so it must NOT be called with function-call
   -- syntax heProbeSodium() -- that throws (the harness hit exactly this). Like
   -- the test sections, it appends its report to gRpt; the harness runs it via
   -- heRunSection, and a standalone `heProbeSodium` echoes the report too.
   put return & tRpt after gRpt
   put tRpt
   return tRpt
end heProbeSodium

--------------------------------------------------------------------------
-- TorrentXT transport probe. Starts THE session, enables rp1, adds a phantom
-- swarm on a rendezvous id, and reports; tears the session back down so the
-- probe leaks nothing. Confirms the transport surface on-engine.
--------------------------------------------------------------------------

command heProbeTorrent
   -- capture "the result" immediately after each bt* command (gotcha 27):
   -- per the docs only btStartSession throws, the rest report via the result
   local tRpt, tSession, tHash, tHandle, tRC, tErr
   put "TorrentXT probe (holde-em " & kHeVersion & "):" & return into tRpt
   try
      put btStartSession() into tSession
   catch tErr
      put "  btStartSession THREW (ABI mismatch?): " & tErr & return after tRpt
      put tRpt
      return tRpt
   end try
   if tSession is 0 or tSession is empty then
      put "  btStartSession failed: " & btLastError() & return after tRpt
      put tRpt
      return tRpt
   end if
   put "  btStartSession -> session " & tSession & return after tRpt
   try
      btSetBool tSession, "enable_dht", true
      put the result into tRC
      put "  btSetBool enable_dht -> " & heRcTxt(tRC) & return after tRpt
      btRp1Enable tSession
      put the result into tRC
      put "  btRp1Enable -> " & heRcTxt(tRC) & return after tRpt
      if heHasSodium() then
         put char 1 to 40 of heHashHex(textEncode("holde-em-probe-table", "utf-8")) into tHash
      else
         put "0123456789abcdef0123456789abcdef01234567" into tHash
      end if
      put btAddInfohash(tSession, tHash, heTempPath()) into tHandle
      if tHandle > 0 then
         put "  btAddInfohash(" & char 1 to 10 of tHash & "...) -> handle " & tHandle & return after tRpt
      else
         put "  btAddInfohash FAILED: " & btLastError() & return after tRpt
      end if
      btDhtAnnounce tSession, tHash, 0
      put the result into tRC
      put "  btDhtAnnounce -> " & heRcTxt(tRC) & return after tRpt
   catch tErr
      put "  transport call THREW: " & tErr & return after tRpt
   end try
   btStopSession tSession
   put "  btStopSession: ok (session torn down)" & return after tRpt
   put tRpt
   return tRpt
end heProbeTorrent

function heTempPath
   -- a scratch save path for the phantom swarm (no content is stored)
   return "he_rendezvous"
end heTempPath

function heRcTxt pRC
   -- a bt* command reports 0/negative via the result; label it for the probe
   if pRC is empty or pRC is 0 then
      return "ok"
   end if
   if pRC < 0 then
      return "FAILED (" & pRC & "): " & btLastError()
   end if
   return "rc=" & pRC
end heRcTxt

--------------------------------------------------------------------------
-- Online transcript: the canonical signed, hash-chained envelope (spec 6),
-- byte-pinned in tools/protocol-kat.py. Layered signatures -- a sender
-- cannot sign seq/prev it does not know under a relay that assigns ordering,
-- so the SENDER signs the content line and the HOST signs the sequenced
-- envelope it relays:
--   contentLine = v TAB tableHex TAB hand TAB fromHex TAB type TAB bodyHex
--   envLine     = contentLine TAB senderSigHex TAB seq TAB prevHex
--   wire        = envLine TAB hostSigHex             (one wire line = one rp1 payload)
--   chainHead   = H("HOLDEM-CHAIN-v1|" || utf8(wire)); genesis prev = 64 zero hex
-- All binary fields travel as lowercase hex; bodies are hex of their UTF-8
-- text, so no tab can ever leak into the frame. (kHeGenesisPrev -- the
-- 64-zero-hex genesis prev -- lives in the top constant block.)
--------------------------------------------------------------------------

function heEnvContentLine pTableHex, pHandNum, pFromHex, pTypeTxt, pBodyTxt
   return kHeEnvV & tab & pTableHex & tab & pHandNum & tab & pFromHex \
         & tab & pTypeTxt & tab & heBin2HexS(textEncode(pBodyTxt, "utf-8"))
end heEnvContentLine

function heEnvSenderSigHex pContentLine, pSenderSecData
   return heBin2HexS(heSignDetachedD(textEncode(pContentLine, "utf-8"), pSenderSecData))
end heEnvSenderSigHex

function heWireBuild pContentLine, pSenderSecData, pSeqNum, pPrevHex, pHostSecData
   -- the host's send path: countersign the sequenced envelope
   local tSenderSig, tEnvLine, tHostSig
   put heEnvSenderSigHex(pContentLine, pSenderSecData) into tSenderSig
   put pContentLine & tab & tSenderSig & tab & pSeqNum & tab & pPrevHex into tEnvLine
   put heBin2HexS(heSignDetachedD(textEncode(tEnvLine, "utf-8"), pHostSecData)) into tHostSig
   return tEnvLine & tab & tHostSig
end heWireBuild

function heChainNextHex pWireLine
   return heHashHex(textEncode(kHeDomainChain & pWireLine, "utf-8"))
end heChainNextHex

function heSettleHashHex pDeltasCSV, pChainHeadData
   -- H("HOLDEM-SETL-v1|" || deltas || "|" || chainHead); chainHead is Data
   return heBin2HexS(heHash32(textEncode(kHeDomainSettle & pDeltasCSV & "|", "utf-8") & pChainHeadData))
end heSettleHashHex

-- Host-trust hardening (spec 6 checkpoints, spec 8.3 settlement receipts),
-- KAT-pinned in tools/protocol-kat.py. A ckpt is a player's signature over the
-- chain head at a street boundary: if two players' ckpts sign DIFFERENT heads,
-- the host forked -- attributable equivocation. A settlement receipt is every
-- seated player's signature over a receipt head that hash-chains hand to hand,
-- so the ledger is multi-signed and no subset can rewrite it. All hex text; the
-- signature payloads are ASCII, so no FFI-bridged binary reaches the chunk
-- evaluator (H6). Sig verification never throws (heVerifyDetached returns false).

function heCkptSigHex pChainHeadHex, pSecData
   -- a player signs "HOLDEM-CKPT-v1|<chainHead>" to checkpoint the transcript
   return heBin2HexS(heSignDetachedD(textEncode(kHeDomainCkpt & pChainHeadHex, "utf-8"), pSecData))
end heCkptSigHex

function heCkptVerify pSigHex, pChainHeadHex, pPubHex
   if not heIsHex(pSigHex, 128) or not heIsHex(pPubHex, 64) then
      return false
   end if
   return heVerifyDetached(heHex2BinD(pSigHex), textEncode(kHeDomainCkpt & pChainHeadHex, "utf-8"), heHex2BinD(pPubHex))
end heCkptVerify

function heCkptBodyTxt pStreetTxt, pHeadHex, pSecData
   -- the street ckpt WIRE body (2e as-built, spec 6): the boundary name, the
   -- head being checkpointed, and the player's ckpt signature over that head,
   -- packaged so a verifier needs nothing but the wire (the head rides along
   -- rather than being inferred, which is what makes a FORK visible: two
   -- verified ckpts for one boundary naming different heads). Pinned as
   -- ckpt_body in tools/protocol-kat.py.
   return "street=" & pStreetTxt & ",head=" & pHeadHex \
         & ",sig=" & heCkptSigHex(pHeadHex, pSecData)
end heCkptBodyTxt

function heReceiptHeadHex pSettleHashHex, pPrevRcptHex
   -- H("HOLDEM-RCPT-v1|" || settleHash || "|" || prevReceipt) -- receipts chain
   -- hand to hand; the genesis predecessor is kHeGenesisPrev (64 zeros)
   return heHashDomHex(kHeDomainRcpt, textEncode(pSettleHashHex & "|" & pPrevRcptHex, "utf-8"))
end heReceiptHeadHex

function heReceiptSigHex pRcptHeadHex, pSecData
   -- a seated player signs "HOLDEM-RSIG-v1|<receiptHead>"; the collected
   -- signatures over one receipt head form the settlement receipt (spec 8.3)
   return heBin2HexS(heSignDetachedD(textEncode(kHeDomainRsig & pRcptHeadHex, "utf-8"), pSecData))
end heReceiptSigHex

function heReceiptSigVerify pSigHex, pRcptHeadHex, pPubHex
   if not heIsHex(pSigHex, 128) or not heIsHex(pPubHex, 64) then
      return false
   end if
   return heVerifyDetached(heHex2BinD(pSigHex), textEncode(kHeDomainRsig & pRcptHeadHex, "utf-8"), heHex2BinD(pPubHex))
end heReceiptSigVerify

function heEnvWireParse pWireLine
   -- split a wire line into its fields and rebuild the two signed spans
   local tA, tSaved, tLine
   put pWireLine into tLine
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   put item 1 of tLine into tA["v"]
   put item 2 of tLine into tA["table"]
   put item 3 of tLine into tA["hand"]
   put item 4 of tLine into tA["from"]
   put item 5 of tLine into tA["type"]
   put item 6 of tLine into tA["bodyHex"]
   put item 7 of tLine into tA["senderSig"]
   put item 8 of tLine into tA["seq"]
   put item 9 of tLine into tA["prev"]
   put item 10 of tLine into tA["hostSig"]
   put item 1 to 6 of tLine into tA["contentLine"]
   put item 1 to 9 of tLine into tA["envLine"]
   set the itemDelimiter to tSaved
   return tA
end heEnvWireParse

function heEnvBodyText pBodyHex
   -- an empty body is empty text; a malformed (non-hex) body drops to empty
   -- rather than throwing in sxHex2Bin. heEnvVerify lets an empty bodyHex pass,
   -- so this is the last guard before a host-crafted body reaches the decoder
   -- (H4: inbound bytes are untrusted, verify-or-drop must never raise).
   if pBodyHex is empty or not heIsHex(pBodyHex, 0) then
      return ""
   end if
   return textDecode(heHex2BinD(pBodyHex), "utf-8")
end heEnvBodyText

function heEnvVerify pWireLine, pFromPubHex, pHostPubHex, pExpectedPrevHex
   -- spec 6 verify-or-drop: bad sig / unknown from / chain break => dropped
   -- and logged, no exceptions (including from the host). pFromPubHex is the
   -- admitted pubkey the caller expects for this sender ("" to skip that
   -- check); pExpectedPrevHex is the local chain head ("" to skip).
   local tA, tFrom, tSenderSig, tHostSig, tBodyHex
   put heEnvWireParse(pWireLine) into tA
   -- shape-check every hex field BEFORE any decode: heHex2BinD (sxHex2Bin)
   -- throws on malformed hex, and this path runs on untrusted inbound bytes,
   -- so a bad frame must become a clean drop, never an uncaught throw (H4).
   put tA["from"] into tFrom
   put tA["senderSig"] into tSenderSig
   put tA["hostSig"] into tHostSig
   put tA["bodyHex"] into tBodyHex
   if not heIsHex(tFrom, 64) or not heIsHex(pHostPubHex, 64) \
         or not heIsHex(tSenderSig, 128) or not heIsHex(tHostSig, 128) then
      return "drop:malformed"
   end if
   if tBodyHex is not empty and not heIsHex(tBodyHex, 0) then
      return "drop:malformed"
   end if
   if pFromPubHex is not empty and tA["from"] is not pFromPubHex then
      return "drop:unknown-from"
   end if
   if not heVerifyDetached(heHex2BinD(tA["senderSig"]), \
         textEncode(tA["contentLine"], "utf-8"), heHex2BinD(tA["from"])) then
      return "drop:bad-sender-sig"
   end if
   if not heVerifyDetached(heHex2BinD(tA["hostSig"]), \
         textEncode(tA["envLine"], "utf-8"), heHex2BinD(pHostPubHex)) then
      return "drop:bad-host-sig"
   end if
   if pExpectedPrevHex is not empty and tA["prev"] is not pExpectedPrevHex then
      return "drop:chain-break"
   end if
   return "ok"
end heEnvVerify

--------------------------------------------------------------------------
-- Level 0 deal (spec 7.1): commit-reveal keyed-stream shuffle. Byte-pinned
-- in tools/protocol-kat.py. Every player commits H("HOLDEM-SEEDC-v1"||seed),
-- shares its seed to the dealer sealed, and the shuffle is a Fisher-Yates
-- draw from stream = H("HOLDEM-SHUF-v1"||table||"|"||hand||"|"||XOR(seeds)),
-- so the dealer cannot stack the deck (its own seed was committed first).
-- The stream is materialised as HEX text and every draw chunks plain hex
-- chars, so no FFI-bridged binary ever reaches the script chunk evaluator
-- (H6): raw Data appears only inside sxHash arguments. Seeds travel as hex.
--------------------------------------------------------------------------

function heByteXor pA, pB
   -- XOR of two byte values (0..255) using ONLY integer arithmetic (div, mod,
   -- add, multiply) -- no bitwise operator, so nothing can trip the engine's
   -- double/binary conversion. Walks the 8 bits low to high.
   -- (locals are tWorkA/tWorkB, NOT tAb -- "tAb" is the tab constant, gotcha 2.)
   local tResult, tBitVal, tWorkA, tWorkB
   put 0 into tResult
   put 1 into tBitVal
   put pA into tWorkA
   put pB into tWorkB
   repeat 8 times
      if (tWorkA mod 2) is not (tWorkB mod 2) then
         add tBitVal to tResult
      end if
      put tWorkA div 2 into tWorkA
      put tWorkB div 2 into tWorkB
      put tBitVal * 2 into tBitVal
   end repeat
   return tResult
end heByteXor

function heXorSeedsHex pSeedsHexA, pCount
   -- XOR of pCount 32-byte seeds (each a 64-hex string), done in hex; returns hex.
   -- The pair walk is a repeat-while because OXT does not honour the increment
   -- of `repeat with ... step N` (family lesson; the suite checker refuses it) -
   -- a stepped loop here would XOR 63 OVERLAPPING pairs instead of 32 aligned
   -- ones and derive a wrong-but-internally-consistent deck.
   local tPairPos, tSeatPos, tAcc, tHexTxt, tOutHex, tPairHex, tByteVal
   put empty into tOutHex
   put 1 into tPairPos
   repeat while tPairPos <= 63
      put 0 into tAcc
      repeat with tSeatPos = 1 to pCount
         put pSeedsHexA[tSeatPos] into tHexTxt
         put baseConvert(char tPairPos to (tPairPos + 1) of tHexTxt, 16, 10) into tByteVal
         put heByteXor(tAcc, tByteVal) into tAcc
      end repeat
      put toLower(baseConvert(tAcc, 10, 16)) into tPairHex
      if the number of chars of tPairHex is 1 then
         put "0" & tPairHex into tPairHex
      end if
      put tPairHex after tOutHex
      add 2 to tPairPos
   end repeat
   return tOutHex
end heXorSeedsHex

function heU32BEData pNum
   -- 4-byte big-endian Data (built from arithmetic, fed straight into sxHash)
   return numToByte(pNum div 16777216 mod 256) & numToByte(pNum div 65536 mod 256) \
         & numToByte(pNum div 256 mod 256) & numToByte(pNum mod 256)
end heU32BEData

function heStreamKeyData pTableData, pHandNum, pXorHex
   -- H("HOLDEM-SHUF-v1|" || table || "|" || decimal(hand) || "|" || seedsXor)
   return heHash32(textEncode(kHeDomainShuf, "utf-8") & pTableData \
         & textEncode("|" & pHandNum & "|", "utf-8") & heHex2BinD(pXorHex))
end heStreamKeyData

function heStreamBlocksHex pKeyData, pBlockCount
   -- hex text of block_j = H(key || uint32be(j)), j = 0 .. pBlockCount-1
   local tOut, tBlockPos
   put empty into tOut
   repeat with tBlockPos = 0 to pBlockCount - 1
      put heBin2HexS(heHash32(pKeyData & heU32BEData(tBlockPos))) after tOut
   end repeat
   return tOut
end heStreamBlocksHex

function heDrawUniform pStreamHex, pOffset, pRangeN
   -- uniform 1..pRangeN via 32-bit BE words (8 hex chars each), rejection
   -- sampled (no modulo bias). The word is two 16-bit halves so baseConvert's
   -- 32-bit signedness is never a factor. Returns "value,nextOffset".
   local tLimit, tWordVal
   put (kHeTwo32 div pRangeN) * pRangeN into tLimit
   repeat forever
      if pOffset + 7 > the number of chars of pStreamHex then
         throw "he-stream-exhausted"
      end if
      put baseConvert(char pOffset to (pOffset + 3) of pStreamHex, 16, 10) * 65536 \
            + baseConvert(char (pOffset + 4) to (pOffset + 7) of pStreamHex, 16, 10) into tWordVal
      add 8 to pOffset
      if tWordVal < tLimit then
         return (tWordVal mod pRangeN) + 1 & comma & pOffset
      end if
   end repeat
end heDrawUniform

function heShuffleFromStreamHex pStreamHex
   -- Fisher-Yates over deck[1..52]; deck 1 is the top, dealt first
   local tDeckA, tPos, tSwapPos, tDrawPair, tHold, tOut, tOffset, tLoopI
   set the itemDelimiter to comma
   repeat with tPos = 1 to 52
      put tPos into tDeckA[tPos]
   end repeat
   put 1 into tOffset
   repeat with tLoopI = 52 down to 2
      put heDrawUniform(pStreamHex, tOffset, tLoopI) into tDrawPair
      put item 1 of tDrawPair into tSwapPos
      put item 2 of tDrawPair into tOffset
      put tDeckA[tLoopI] into tHold
      put tDeckA[tSwapPos] into tDeckA[tLoopI]
      put tHold into tDeckA[tSwapPos]
   end repeat
   put empty into tOut
   repeat with tPos = 1 to 52
      put tDeckA[tPos] & comma after tOut
   end repeat
   delete char -1 of tOut
   return tOut
end heShuffleFromStreamHex

function heDeckFromStreamKey pKeyData
   -- 16 blocks (1024 hex chars) covers 51 draws with slack; extend on the
   -- astronomically-unlikely stream exhaustion rather than fail. The terminal
   -- error is captured and re-thrown AFTER `end try`: a `throw` inside a
   -- `catch` never reaches the caller on OXT (family lesson; the suite
   -- checker refuses the in-catch form).
   local tBlockCount, tDeckList, tShufErr, tFatal
   put 16 into tBlockCount
   repeat forever
      put empty into tFatal
      try
         put heShuffleFromStreamHex(heStreamBlocksHex(pKeyData, tBlockCount)) into tDeckList
         return tDeckList
      catch tShufErr
         if tShufErr contains "he-stream-exhausted" and tBlockCount < 256 then
            put tBlockCount * 2 into tBlockCount
         else
            put tShufErr into tFatal
         end if
      end try
      if tFatal is not empty then
         throw tFatal
      end if
   end repeat
end heDeckFromStreamKey

function heLevel0Deck pTableData, pHandNum, pSeedsHexA, pCount
   -- the full Level 0 shuffled deck from committed seeds
   return heDeckFromStreamKey(heStreamKeyData(pTableData, pHandNum, heXorSeedsHex(pSeedsHexA, pCount)))
end heLevel0Deck

function heSeedCommitHex pSeedHex
   -- H("HOLDEM-SEEDC-v1|" || seed bytes), hex (spec 7.1 step 1)
   return heHashDomHex(kHeDomainSeedC, heHex2BinD(pSeedHex))
end heSeedCommitHex

function heAuditDeal pTableData, pHandNum, pSeedsHexA, pCommitsA, pCount, pDealA, pOccList, pButton
   -- end-of-hand audit (spec 7.1 step 5): recompute the whole deal from the
   -- revealed seeds and name the FIRST failing step. Returns "pass"/"fail:..".
   local tSeatPos, tDeckList, tCheckA, tSeatNum
   set the itemDelimiter to comma
   repeat with tSeatPos = 1 to pCount
      if heSeedCommitHex(pSeedsHexA[tSeatPos]) is not pCommitsA[tSeatPos] then
         return "fail:commit-mismatch-position-" & tSeatPos
      end if
   end repeat
   put heLevel0Deck(pTableData, pHandNum, pSeedsHexA, pCount) into tDeckList
   put heDealAssign(tDeckList, pOccList, pButton) into tCheckA
   repeat for each item tSeatNum in pOccList
      if tCheckA["holesBy"][tSeatNum] is not pDealA["holesBy"][tSeatNum] then
         return "fail:hole-mismatch-seat-" & tSeatNum
      end if
   end repeat
   if tCheckA["flopList"] is not pDealA["flopList"] then
      return "fail:flop-mismatch"
   end if
   if tCheckA["turnIx"] is not pDealA["turnIx"] then
      return "fail:turn-mismatch"
   end if
   if tCheckA["riverIx"] is not pDealA["riverIx"] then
      return "fail:river-mismatch"
   end if
   return "pass"
end heAuditDeal

function heAuditDealsFromLog pLogTxt
   -- replay a transcript and RE-DERIVE every Level 0 deal from the revealed
   -- seeds, confirming the committed keyed-stream shuffle produced exactly the
   -- cards that were dealt -- so the deal is provably CONSISTENT with the revealed
   -- seeds (tamper-evident), checkable by anyone holding the log. (Unstackability
   -- against a cheating dealer needs independent per-player seeds -- spec 7.1 online
   -- deal -- not the single-party seeds generated here.) Only the dealt streets are
   -- compared (a hand folded pre-flop has no board to check). Needs SodiumXT
   -- (recomputes commitments + shuffle). Returns "N/M deals verified" then one
   -- line per Level 0 hand; "no Level 0 deals in this transcript" if none.
   local tLine, tType, tBodyTxt, tBodyA, tOut, tVerified, tTotal
   local tHandNum, tOccList, tButton, tTableHex, tCount, tSeedsA, tCommitsA
   local tHolesA, tBoardList, tPos, tSeatNum, tLevel0, tCardTxt, tOneCard
   local tDeckList, tCheckA, tVerdict, tBoardN
   if not heHasSodium() then
      return "deal audit needs SodiumXT (it recomputes the committed shuffle)."
   end if
   set the itemDelimiter to comma
   put 0 into tVerified
   put 0 into tTotal
   put empty into tOut
   put "false" into tLevel0
   repeat for each line tLine in pLogTxt
      if tLine is empty then
         next repeat
      end if
      put heLogField(tLine, 3) into tType
      put heLogField(tLine, 4) into tBodyTxt
      set the itemDelimiter to comma
      switch tType
         case "handStart"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put tBodyA["seats"] into tOccList
            replace "|" with comma in tOccList
            put tBodyA["button"] into tButton
            put heLogField(tLine, 1) into tHandNum
            put "false" into tLevel0
            put empty into tSeedsA
            put empty into tCommitsA
            put empty into tHolesA
            put empty into tBoardList
            break
         case "dealLevel"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put "true" into tLevel0
            put tBodyA["table"] into tTableHex
            put tBodyA["count"] into tCount
            break
         case "seedCommit"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put tBodyA["commit"] into tCommitsA[tBodyA["pos"]]
            break
         case "seedReveal"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put tBodyA["seed"] into tSeedsA[tBodyA["pos"]]
            break
         case "holeDeliver"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put tBodyA["cards"] into tCardTxt
            replace "|" with comma in tCardTxt
            put heCardIndex(item 1 of tCardTxt) & comma & heCardIndex(item 2 of tCardTxt) into tHolesA[tBodyA["seat"]]
            break
         case "board"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put tBodyA["cards"] into tCardTxt
            replace "|" with comma in tCardTxt
            repeat for each item tOneCard in tCardTxt
               if tBoardList is empty then
                  put heCardIndex(tOneCard) into tBoardList
               else
                  put tBoardList & comma & heCardIndex(tOneCard) into tBoardList
               end if
            end repeat
            break
         case "settle"
            if tLevel0 is "true" then
               add 1 to tTotal
               put heAuditDealLog(tTableHex, tHandNum, tSeedsA, tCommitsA, tCount, tOccList, tButton, tHolesA, tBoardList) into tVerdict
               if tVerdict is "pass" then
                  add 1 to tVerified
                  put "hand " & tHandNum & ": deal-verified (committed shuffle re-derived)" & return after tOut
               else
                  put "hand " & tHandNum & ": deal-FAILED " & tVerdict & return after tOut
               end if
            end if
            break
      end switch
   end repeat
   if tTotal is 0 then
      return "no Level 0 deals in this transcript (practice PRNG deal)."
   end if
   return tVerified & "/" & tTotal & " deals verified" & return & tOut
end heAuditDealsFromLog

function heAuditDealLog pTableHex, pHandNum, pSeedsHexA, pCommitsA, pCount, pOccList, pButton, pHolesA, pBoardList
   -- verify one Level 0 hand from the log: commits bind the seeds, the deck
   -- re-derives, and the dealt holes (always) plus whatever board streets were
   -- revealed match. Returns "pass" or "fail:...".
   local tSeatPos, tDeckList, tCheckA, tSeatNum, tBoardN
   set the itemDelimiter to comma
   repeat with tSeatPos = 1 to pCount
      if heSeedCommitHex(pSeedsHexA[tSeatPos]) is not pCommitsA[tSeatPos] then
         return "fail:commit-mismatch-position-" & tSeatPos
      end if
   end repeat
   put heLevel0Deck(heHex2BinD(pTableHex), pHandNum, pSeedsHexA, pCount) into tDeckList
   put heDealAssign(tDeckList, pOccList, pButton) into tCheckA
   repeat for each item tSeatNum in pOccList
      if tCheckA["holesBy"][tSeatNum] is not pHolesA[tSeatNum] then
         return "fail:hole-mismatch-seat-" & tSeatNum
      end if
   end repeat
   put the number of items of pBoardList into tBoardN
   if tBoardN >= 3 and (item 1 to 3 of pBoardList) is not tCheckA["flopList"] then
      return "fail:flop-mismatch"
   end if
   if tBoardN >= 4 and (item 4 of pBoardList) is not tCheckA["turnIx"] then
      return "fail:turn-mismatch"
   end if
   if tBoardN >= 5 and (item 5 of pBoardList) is not tCheckA["riverIx"] then
      return "fail:river-mismatch"
   end if
   return "pass"
end heAuditDealLog

--------------------------------------------------------------------------
-- Level 2 mental poker COMPUTE (Phase 4a-4c, spec 7.3): the ristretto255
-- deal algebra, on SodiumXT ABI 8's sxRistretto* surface. PURE handlers
-- (H5): values in, values out -- nothing here reads UI, touches the wire,
-- or is called from any played-hand path; the 4d-4f orchestration (wire
-- vocabulary, void-and-audit sequencing, adversarial bots, the deal-time
-- budget measurement) is engine-era work that composes these.
--
-- Representation (the H6 corollary, applied): EVERY seam is lowercase hex
-- text. A deck is a 52-item comma list of 64-hex points; sigma is a 52-item
-- comma list of indices (out[j] = k * in[sigma[j]]); an unmask chain is a
-- comma list whose item 1 is the masked table point and each later item one
-- seat's broadcast step value, in chain order. Raw Data exists ONLY inside
-- expressions passed straight into sx* calls.
--
-- The 4d/4e/5 layer further down (heL2ShuffleBodyOf/heL2UnmaskBodyOf record
-- formats, the heL2Void* machine, heL2Dleq* proofs on the ABI-9 surface)
-- composes these and stays just as pure; played-hand wiring and the 4f
-- deal-time budget measurement remain engine-era work.
--
-- Failures are DISTINCT "void:..." strings, never throws (every sx* call
-- try-guarded, H4, with declared catch locals, H8), so Phase 4d's
-- void-and-audit attribution can name the condition it is refusing on.
-- libsodium reports an invalid point and an identity result as ONE
-- scalar-mult failure; the validity predicate runs FIRST here, so a throw
-- after it can only be the identity result -- that split is what makes
-- "void:invalid-point" and "void:identity-point" separable at all.
--
-- Twinned line for line by the l2_* mirrors in tools/protocol-kat.py,
-- which the file's INDEPENDENT RFC 9496 ristretto reference drives: the
-- pinned values hold this section and the reference together, and
-- heTestLevel2Run re-checks the same constants on-engine. Everything
-- below: verified statically; needs an OXT pass (the sx* call shapes above
-- all).
--------------------------------------------------------------------------

function heL2HasRistretto
   -- cached probe (the heHasSodium pattern): a pre-ABI-8 SodiumXT has no
   -- sxRistretto* handlers at all, so the FIRST touch throws ("can't find
   -- handler") -- the catch IS the detection (H4). sxRistrettoPointValid is
   -- a predicate that never throws on any input and sxRistrettoScalarRandom
   -- takes none, so a throw here can only mean the surface is absent.
   local tProbeErr
   if gHasR255Chk is empty then
      try
         get sxRistrettoPointValid(sxRistrettoScalarRandom())
         put "true" into gHasR255Chk
      catch tProbeErr
         put "false" into gHasR255Chk
      end try
   end if
   return gHasR255Chk is "true"
end heL2HasRistretto

function heL2CardPointHex pCardIdx
   -- base point P_c for card index 1..52 (spec 7.3 setup): domain-separated
   -- hash-to-group, so no party knows any discrete-log relation between two
   -- card points -- the unknowability the whole construction leans on. The
   -- 64-byte uniform input sxRistrettoFromHash wants is sxHash(label, 64)
   -- (BLAKE2b-512); the label is kHeDomainL2Card & the card name.
   local tCardErr
   if pCardIdx is not an integer or pCardIdx < 1 or pCardIdx > 52 then
      return "void:card-range"
   end if
   if not heL2HasRistretto() then
      return "void:no-ristretto"
   end if
   try
      return heBin2HexS(sxRistrettoFromHash(sxHash(textEncode( \
            kHeDomainL2Card & heCardName(pCardIdx), "utf-8"), 64)))
   catch tCardErr
      return "void:no-ristretto"
   end try
end heL2CardPointHex

function heL2BaseDeckHex
   -- the public 52-point card table, built once per hand at deal time
   -- (52 hash+map FFI crossings -- deal-time only, never per-frame, per
   -- the playbook). Position j = card index j (1..52); the SHUFFLED order
   -- comes from the mask steps, never from this table.
   local tCardIdx, tPointHex, tOutList
   put empty into tOutList
   repeat with tCardIdx = 1 to 52
      put heL2CardPointHex(tCardIdx) into tPointHex
      if tPointHex begins with "void:" then
         return tPointHex
      end if
      if tOutList is empty then
         put tPointHex into tOutList
      else
         put comma & tPointHex after tOutList
      end if
   end repeat
   return tOutList
end heL2BaseDeckHex

function heL2ScalarRandomHex
   -- one fresh per-hand masking scalar: uniform nonzero mod L, from
   -- libsodium's CSPRNG (spec 16: engine random() never touches dealing)
   local tRndErr
   if not heL2HasRistretto() then
      return "void:no-ristretto"
   end if
   try
      return heBin2HexS(sxRistrettoScalarRandom())
   catch tRndErr
      return "void:no-ristretto"
   end try
end heL2ScalarRandomHex

function heL2ScalarInvertHex pScalarHex
   -- k^-1 mod L, the unmask scalar. sxRistrettoScalarInvert throws only on
   -- a zero scalar (surface presence is gated first), so the catch names it.
   local tInvErr
   if not heIsHex(pScalarHex, 64) then
      return "void:scalar-format"
   end if
   if not heL2HasRistretto() then
      return "void:no-ristretto"
   end if
   try
      return heBin2HexS(sxRistrettoScalarInvert(heHex2BinD(pScalarHex)))
   catch tInvErr
      return "void:scalar-zero"
   end try
end heL2ScalarInvertHex

function heL2MaskPointHex pScalarHex, pPointHex
   -- q = k * P on ristretto255, hex in / hex out: the atomic op every mask
   -- and unmask step is made of. The validity predicate runs FIRST, so the
   -- scalar-mult throw after it can only be the identity result (a zero
   -- scalar, or P itself the identity) -- the invalid/identity split 4d
   -- attribution needs.
   local tMaskErr, tValidOk
   if not heIsHex(pScalarHex, 64) then
      return "void:scalar-format"
   end if
   if not heIsHex(pPointHex, 64) then
      return "void:point-format"
   end if
   if not heL2HasRistretto() then
      return "void:no-ristretto"
   end if
   try
      put sxRistrettoPointValid(heHex2BinD(pPointHex)) into tValidOk
   catch tMaskErr
      return "void:no-ristretto"
   end try
   if tValidOk is not true then
      return "void:invalid-point"
   end if
   try
      return heBin2HexS(sxRistrettoScalarMultPoint(heHex2BinD(pScalarHex), \
            heHex2BinD(pPointHex)))
   catch tMaskErr
      return "void:identity-point"
   end try
end heL2MaskPointHex

function heL2DeckCheckHex pDeckList
   -- spec 7.3's FREE integrity check: the same card under the same
   -- composite mask is an IDENTICAL 32-byte point, publicly visible, so
   -- every client asserts all 52 points of every shuffle step are distinct
   -- valid encodings and refuses the step otherwise -- duplication is
   -- prevented, not detected after the fact. One pass in position order:
   -- format, then encoding validity, then the duplicate lookup, so the
   -- first offence names its position(s). Keys are lowercased so the
   -- verdict never depends on engine case rules.
   local tPos, tPointHex, tKeyHex, tSeenA, tValidOk, tChkErr
   set the itemDelimiter to comma
   if the number of items of pDeckList is not 52 then
      return "void:deck-size"
   end if
   put 0 into tPos
   repeat for each item tPointHex in pDeckList
      add 1 to tPos
      if not heIsHex(tPointHex, 64) then
         return "void:point-format:" & tPos
      end if
      try
         put sxRistrettoPointValid(heHex2BinD(tPointHex)) into tValidOk
      catch tChkErr
         return "void:no-ristretto"
      end try
      if tValidOk is not true then
         return "void:invalid-point:" & tPos
      end if
      put toLower(tPointHex) into tKeyHex
      if tSeenA[tKeyHex] is not empty then
         return "void:duplicate-point:" & tSeenA[tKeyHex] & "," & tPos
      end if
      put tPos into tSeenA[tKeyHex]
   end repeat
   return "ok"
end heL2DeckCheckHex

function heL2MaskDeckHex pDeckList, pScalarHex, pPermList
   -- one full shuffle-mask step (spec 7.3): out[j] = k * in[sigma[j]] for
   -- j = 1..52, deal-time only. Reused verbatim by showdown
   -- re-verification (heL2RevealShuffleHex), so the doer and the verifier
   -- can never drift. sigma is validated for range/format ONLY,
   -- deliberately not distinctness: a repeated index duplicates a point in
   -- the OUTPUT deck, which the public duplicate check catches on every
   -- client. A void from the point mask comes back with the output
   -- position appended.
   --
   -- TWO PATHS, ONE CONTRACT (plan 4f's batch handler, pulled forward
   -- 2026-08-23). On SodiumXT ABI 9 the happy path is ONE atomic
   -- sxRistrettoScalarMultBatch crossing for all 52 mults -- 4 FFI
   -- crossings for the whole step (one sxHex2Bin for the scalar, one for
   -- the 52-point concatenation, the batch itself, one sxBin2Hex back) --
   -- where the per-point loop below costs 6 per point, ~312 per step.
   -- Gated on heL2HasDleq(), the same cached ABI-9 probe the DLEQ
   -- verifier's batch call gates on. The batch is ATOMIC: one bad point
   -- (invalid encoding, or an identity result) throws for the WHOLE call
   -- with a 1-based index in the message -- and that message is NOT
   -- parsed. ANY deviation from the happy path falls through to the
   -- per-point loop, which re-derives the verdict with the exact
   -- position-tagged "void:..." string 4d attribution switches on, so the
   -- two paths can never disagree about a refusal: every refusal IS the
   -- loop's. The pure-text format checks run BEFORE any hex crosses the
   -- FFI (H4: heIsHex gates sxHex2Bin, which throws on malformed input),
   -- and the loop stays the only path on a pre-ABI-9 SodiumXT. Harness
   -- section 16 pins batch-vs-loop byte agreement on the KAT deck.
   local tOutPos, tSrcPos, tSrcHex, tMaskedHex, tOutList
   local tFastOk, tConcatHex, tBatchHex, tBatchErr
   set the itemDelimiter to comma
   if the number of items of pDeckList is not 52 then
      return "void:deck-size"
   end if
   if the number of items of pPermList is not 52 then
      return "void:perm-size"
   end if
   if heL2HasDleq() and heIsHex(pScalarHex, 64) then
      put "true" into tFastOk
      put empty into tConcatHex
      repeat for each item tSrcPos in pPermList
         if tSrcPos is not an integer or tSrcPos < 1 or tSrcPos > 52 then
            put "false" into tFastOk
            exit repeat
         end if
         put item tSrcPos of pDeckList into tSrcHex
         if not heIsHex(tSrcHex, 64) then
            put "false" into tFastOk
            exit repeat
         end if
         put tSrcHex after tConcatHex
      end repeat
      if tFastOk is "true" then
         try
            put heBin2HexS(sxRistrettoScalarMultBatch(heHex2BinD(pScalarHex), \
                  heHex2BinD(tConcatHex))) into tBatchHex
            put empty into tOutList
            put 1 into tOutPos
            repeat while tOutPos <= 52
               put char (tOutPos * 64 - 63) to (tOutPos * 64) of tBatchHex into tMaskedHex
               if tOutList is empty then
                  put tMaskedHex into tOutList
               else
                  put comma & tMaskedHex after tOutList
               end if
               add 1 to tOutPos
            end repeat
            return tOutList
         catch tBatchErr
            -- an invalid point or an identity result somewhere in the
            -- deck (the batch's merged, atomic failure): fall through --
            -- the loop below re-derives WHICH point and names it exactly
         end try
      end if
   end if
   put empty into tOutList
   put 0 into tOutPos
   repeat for each item tSrcPos in pPermList
      add 1 to tOutPos
      if tSrcPos is not an integer or tSrcPos < 1 or tSrcPos > 52 then
         return "void:perm-format:" & tOutPos
      end if
      put item tSrcPos of pDeckList into tSrcHex
      put heL2MaskPointHex(pScalarHex, tSrcHex) into tMaskedHex
      if tMaskedHex begins with "void:" then
         return tMaskedHex & ":" & tOutPos
      end if
      if tOutList is empty then
         put tMaskedHex into tOutList
      else
         put comma & tMaskedHex after tOutList
      end if
   end repeat
   return tOutList
end heL2MaskDeckHex

function heL2CardOfPointHex pPointHex, pBaseDeckList
   -- card index 1..52 of a point in the base table, 0 when absent. PURE
   -- text scan, no FFI, so table lookups can never throw on hostile input;
   -- `is` compares case-insensitively, which the Python twin mirrors by
   -- lowercasing both sides.
   local tIdx, tBaseHex
   set the itemDelimiter to comma
   put 0 into tIdx
   repeat for each item tBaseHex in pBaseDeckList
      add 1 to tIdx
      if tBaseHex is pPointHex then
         return tIdx
      end if
   end repeat
   return 0
end heL2CardOfPointHex

function heL2PublicCardHex pChainList, pBaseDeckList
   -- verify a COMPLETED public unmask chain (spec 7.3 dealing): every
   -- value must be well-formed and a valid encoding, and the FINAL value
   -- must hit the 52-point table -- that point IS the card. Landing
   -- outside the table is proof of a wrong step somewhere: the
   -- void-and-audit condition, named distinctly for 4d.
   local tPos, tStepHex, tLastHex, tValidOk, tPubErr, tCardIdx
   set the itemDelimiter to comma
   if the number of items of pChainList < 2 then
      return "void:chain-short"
   end if
   put 0 into tPos
   repeat for each item tStepHex in pChainList
      add 1 to tPos
      if not heIsHex(tStepHex, 64) then
         return "void:point-format:" & tPos
      end if
      try
         put sxRistrettoPointValid(heHex2BinD(tStepHex)) into tValidOk
      catch tPubErr
         return "void:no-ristretto"
      end try
      if tValidOk is not true then
         return "void:invalid-point:" & tPos
      end if
      put tStepHex into tLastHex
   end repeat
   put heL2CardOfPointHex(tLastHex, pBaseDeckList) into tCardIdx
   if tCardIdx is 0 then
      return "void:final-not-in-table"
   end if
   return "card:" & tCardIdx
end heL2PublicCardHex

function heL2HoleCardHex pChainList, pInvScalarHex, pBaseDeckList
   -- the owner's last, PRIVATE step of a hole chain (spec 7.3): pChainList
   -- is the PUBLIC part (masked table point first, the other seats' steps
   -- in chain order -- the owner's step is exactly what is absent), and
   -- its final value V = k_owner * P_c is publicly visible but CDH-useless
   -- to everyone else. Strip the own mask off V and resolve the card.
   -- Showdown reuses this with the REVEALED inverse, so A's holes fall out
   -- of V * kA^-1 for the whole table.
   local tPos, tStepHex, tLastHex, tValidOk, tHoleErr, tOwnHex, tCardIdx
   set the itemDelimiter to comma
   if the number of items of pChainList < 1 then
      return "void:chain-short"
   end if
   put 0 into tPos
   repeat for each item tStepHex in pChainList
      add 1 to tPos
      if not heIsHex(tStepHex, 64) then
         return "void:point-format:" & tPos
      end if
      try
         put sxRistrettoPointValid(heHex2BinD(tStepHex)) into tValidOk
      catch tHoleErr
         return "void:no-ristretto"
      end try
      if tValidOk is not true then
         return "void:invalid-point:" & tPos
      end if
      put tStepHex into tLastHex
   end repeat
   put heL2MaskPointHex(pInvScalarHex, tLastHex) into tOwnHex
   if tOwnHex begins with "void:" then
      return tOwnHex
   end if
   put heL2CardOfPointHex(tOwnHex, pBaseDeckList) into tCardIdx
   if tCardIdx is 0 then
      return "void:hole-not-in-table"
   end if
   return "card:" & tCardIdx
end heL2HoleCardHex

function heL2RevealShuffleHex pInDeckList, pOutDeckList, pScalarHex, pPermList
   -- spec 7.3 showdown: recompute the revealer's whole shuffle-mask step
   -- from the revealed (k, sigma) and compare it against the deck it
   -- broadcast that hand; the first mismatching position is named (4d
   -- attribution). Verification IS the doer function re-run, so there is
   -- no second implementation to drift.
   local tRedoneList, tPos, tOutHex, tRedoneHex
   set the itemDelimiter to comma
   put heL2MaskDeckHex(pInDeckList, pScalarHex, pPermList) into tRedoneList
   if tRedoneList begins with "void:" then
      return tRedoneList
   end if
   if the number of items of pOutDeckList is not 52 then
      return "void:deck-size"
   end if
   repeat with tPos = 1 to 52
      put item tPos of pOutDeckList into tOutHex
      put item tPos of tRedoneList into tRedoneHex
      if tRedoneHex is not tOutHex then
         return "void:shuffle-mismatch:" & tPos
      end if
   end repeat
   return "ok"
end heL2RevealShuffleHex

function heL2RevealUnmaskHex pInHex, pOutHex, pScalarHex
   -- spec 7.3 showdown: one broadcast unmask step re-verified from the
   -- revealed scalar -- the step value must equal k^-1 * (its input).
   -- A wrong revealed scalar and a wrong original step are the same
   -- verdict by design: either way the revealer's claim does not recompute.
   local tInvHex, tRedoneHex
   put heL2ScalarInvertHex(pScalarHex) into tInvHex
   if tInvHex begins with "void:" then
      return tInvHex
   end if
   put heL2MaskPointHex(tInvHex, pInHex) into tRedoneHex
   if tRedoneHex begins with "void:" then
      return tRedoneHex
   end if
   if not heIsHex(pOutHex, 64) then
      return "void:point-format"
   end if
   if tRedoneHex is pOutHex then
      return "ok"
   end if
   return "void:unmask-mismatch"
end heL2RevealUnmaskHex

--------------------------------------------------------------------------
-- Phase 4d void-and-audit + Phase 5 DLEQ (spec 7.3/7.4, plan 4d/4e/5).
-- Everything here is PURE (H5) and twinned line for line by the l2_dleq_*
-- and l2_void_* mirrors in tools/protocol-kat.py -- the reference was
-- written and its vectors pinned FIRST, and this side was written to
-- match. Two contracts are pinned:
--
--   * RECORD FORMATS (spec 6 body conventions; the body is UTF-8 text,
--     hex-encoded into the envelope, so its commas never reach the frame;
--     multi-value fields join with "|" like seats=1|2|3 does):
--       shuffleStep  body = pos=<P>,ck=<64hex|empty>,deck=<52x64hex "|">
--       unmaskStep   body = pos=<P>,slot=<S>,val=<64hex>,proof=<192hex|empty>
--     P = contributor position in the shuffle order (seat order at L2);
--     ck = the DLEQ commitment key k_P * B (required when the signed
--     table config pins dleq=1, legal-empty below it); S = the deck
--     position 1..52 being unmasked (consumed in the fixed public order);
--     proof is spec 7.4's reserved field, filled at Phase 5. Audit
--     reveals: one line per contributor, <pos> TAB <kHex> TAB <sigma>.
--
--   * THE DLEQ PROOF (Chaum-Pedersen over ristretto255, spec 7.4): the
--     statement is P2 = k * P1 for the k behind ck = k*B -- an unmask
--     step proves (k, stepOut, stepIn), since out = k^-1*in <=> in =
--     k*out. Derandomized nonce, transcript hashes over LOWERCASED hex,
--     proof = a1||a2||z (96 bytes); the full derivation is spelled out at
--     the constants (kHeDomainL2Dleq/W) and in heL2DleqProve below.
--
-- The machine consumes the DEDUPED, host-sequenced record stream (spec 6
-- kills transport replay at the envelope layer); an identical re-post of
-- the last applied record is tolerated as "dup", any OTHER step for an
-- already-filled position is signed equivocation, named directly. Every
-- refusal is a distinct "void:..." string; attribution is DIRECT
-- (named=pos) when the offending record is itself publicly refusable and
-- DEFERRED (named=0 -> heL2VoidAudit) when only the reveals can say whose
-- step lied. Verified statically; needs an OXT pass (the ABI-9 sx* call
-- shapes have never run on an engine).
--------------------------------------------------------------------------

function heL2HasDleq
   -- cached probe for the ABI-9 DLEQ/batch surface (the heL2HasRistretto
   -- pattern): a pre-ABI-9 SodiumXT has no sxRistrettoScalarMultBase, so
   -- the first touch throws "can't find handler" -- the catch IS the
   -- detection (H4). ScalarRandom never returns zero, so a throw here can
   -- only mean the surface is absent; ABI 9 ships as one unit, so one
   -- handler witnesses all six.
   local tProbeErr
   if gHasDleqChk is empty then
      if not heL2HasRistretto() then
         put "false" into gHasDleqChk
      else
         try
            get sxRistrettoScalarMultBase(sxRistrettoScalarRandom())
            put "true" into gHasDleqChk
         catch tProbeErr
            put "false" into gHasDleqChk
         end try
      end if
   end if
   return gHasDleqChk is "true"
end heL2HasDleq

function heL2PointOkHex pPointHex
   -- format + canonical-encoding validity as a verdict string ("ok" /
   -- "void:..."), the check every 4d record field goes through before any
   -- group math can throw on it (H4: verify-or-drop never raises)
   local tOkErr, tValidOk
   if not heIsHex(pPointHex, 64) then
      return "void:point-format"
   end if
   if not heL2HasRistretto() then
      return "void:no-ristretto"
   end if
   try
      put sxRistrettoPointValid(heHex2BinD(pPointHex)) into tValidOk
   catch tOkErr
      return "void:no-ristretto"
   end try
   if tValidOk is not true then
      return "void:invalid-point"
   end if
   return "ok"
end heL2PointOkHex

function heL2CommitKeyHex pScalarHex
   -- ck = k*B, the per-hand DLEQ commitment key a shuffleStep carries.
   -- The scalar is REDUCED mod L first (ScalarAdd-zero -- see the
   -- kHeL2ZeroScalar comment), so a non-canonical k cannot make libsodium
   -- (bit-255 masking) and the KAT reference (full mod L) disagree.
   -- k == 0 mod L is the merged identity failure the catch names.
   local tCkErr
   if not heIsHex(pScalarHex, 64) then
      return "void:scalar-format"
   end if
   if not heL2HasDleq() then
      return "void:no-dleq"
   end if
   try
      return heBin2HexS(sxRistrettoScalarMultBase(sxRistrettoScalarAdd( \
            heHex2BinD(pScalarHex), heHex2BinD(kHeL2ZeroScalar))))
   catch tCkErr
      return "void:scalar-zero"
   end try
end heL2CommitKeyHex

function heL2DleqProve pScalarHex, pP1Hex, pP2Hex
   -- Chaum-Pedersen DLEQ (spec 7.4): prove P2 = k*P1 for the k behind
   -- ck = k*B, without revealing k. One generic (k, P1, P2) shape serves
   -- the whole deal: an unmask step calls prove(k, stepOut, stepIn).
   -- DERANDOMIZED (RFC 6979 / EdDSA pattern): w = reduce(H32(DLEQW-tag ||
   -- k || "|" || p1 || "|" || p2)) -- deterministic, so protocol-kat pins
   -- the whole proof from fixed scalars, and nonce reuse across two
   -- DIFFERENT statements (which forfeits k) is impossible by
   -- construction. a1 = w*B, a2 = w*P1; c = reduce(H32(DLEQ-tag || ck ||
   -- "|" || p1 || "|" || p2 || "|" || a1 || "|" || a2)); z = w + c*k mod
   -- L; proof = a1 || a2 || z (96 bytes -- spec 7.4's "~96-byte proof").
   -- Hash inputs are LOWERCASED hex (xTalk `is` compares case-blind, but
   -- hashes see bytes); reduce() is ScalarAdd-zero, applied before any
   -- point mult (the kHeL2ZeroScalar rationale).
   local tPrvErr, tOkTxt, tCkHex, tWData, tA1Hex, tA2Hex, tCData, tZHex
   if not heIsHex(pScalarHex, 64) then
      return "void:scalar-format"
   end if
   put heL2PointOkHex(pP1Hex) into tOkTxt
   if tOkTxt is not "ok" then
      return tOkTxt
   end if
   put heL2PointOkHex(pP2Hex) into tOkTxt
   if tOkTxt is not "ok" then
      return tOkTxt
   end if
   if not heL2HasDleq() then
      return "void:no-dleq"
   end if
   put heL2CommitKeyHex(pScalarHex) into tCkHex
   if tCkHex begins with "void:" then
      return tCkHex
   end if
   try
      put sxRistrettoScalarAdd(sxHash(textEncode(kHeDomainL2DleqW & \
            toLower(pScalarHex) & "|" & toLower(pP1Hex) & "|" & \
            toLower(pP2Hex), "utf-8"), 32), \
            heHex2BinD(kHeL2ZeroScalar)) into tWData
   catch tPrvErr
      return "void:no-dleq"
   end try
   try
      put heBin2HexS(sxRistrettoScalarMultBase(tWData)) into tA1Hex
   catch tPrvErr
      return "void:scalar-zero"
   end try
   try
      put heBin2HexS(sxRistrettoScalarMultPoint(tWData, \
            heHex2BinD(pP1Hex))) into tA2Hex
   catch tPrvErr
      return "void:identity-point"
   end try
   try
      put sxRistrettoScalarAdd(sxHash(textEncode(kHeDomainL2Dleq & tCkHex & \
            "|" & toLower(pP1Hex) & "|" & toLower(pP2Hex) & "|" & tA1Hex & \
            "|" & tA2Hex, "utf-8"), 32), \
            heHex2BinD(kHeL2ZeroScalar)) into tCData
      put heBin2HexS(sxRistrettoScalarAdd(tWData, \
            sxRistrettoScalarMul(tCData, heHex2BinD(pScalarHex)))) into tZHex
   catch tPrvErr
      return "void:no-dleq"
   end try
   return tA1Hex & tA2Hex & tZHex
end heL2DleqProve

function heL2DleqVerify pCkHex, pP1Hex, pP2Hex, pProofHex
   -- verify a Chaum-Pedersen proof: z canonical, then z*B == a1 + c*ck
   -- (equation 1, binds the commitment key) and z*P1 == a2 + c*P2
   -- (equation 2, binds the step values) -- named distinctly, first
   -- offence wins. The challenge is RE-DERIVED from the transcript, so a
   -- tampered (a1, a2) changes c and neither equation can close
   -- (Fiat-Shamir). c*ck and c*P2 ride ONE sxRistrettoScalarMultBatch
   -- crossing -- one scalar, two points, exactly the batch call's shape;
   -- z*B and z*P1 have different bases so they cannot join it. A
   -- non-canonical z is refused outright: libsodium masks bit 255 inside
   -- scalarmult while the KAT reference reduces mod L, and an
   -- attacker-chosen representation must reach neither.
   local tVfyErr, tA1Hex, tA2Hex, tZHex, tOkTxt, tZRedHex, tCData
   local tPairHex, tCCkHex, tCP2Hex, tLhsHex, tRhsHex
   if not heIsHex(pProofHex, 192) then
      return "void:proof-format"
   end if
   put char 1 to 64 of pProofHex into tA1Hex
   put char 65 to 128 of pProofHex into tA2Hex
   put char 129 to 192 of pProofHex into tZHex
   put heL2PointOkHex(pCkHex) into tOkTxt
   if tOkTxt is not "ok" then
      return tOkTxt
   end if
   put heL2PointOkHex(pP1Hex) into tOkTxt
   if tOkTxt is not "ok" then
      return tOkTxt
   end if
   put heL2PointOkHex(pP2Hex) into tOkTxt
   if tOkTxt is not "ok" then
      return tOkTxt
   end if
   put heL2PointOkHex(tA1Hex) into tOkTxt
   if tOkTxt is not "ok" then
      return tOkTxt
   end if
   put heL2PointOkHex(tA2Hex) into tOkTxt
   if tOkTxt is not "ok" then
      return tOkTxt
   end if
   if not heL2HasDleq() then
      return "void:no-dleq"
   end if
   try
      put heBin2HexS(sxRistrettoScalarAdd(heHex2BinD(tZHex), \
            heHex2BinD(kHeL2ZeroScalar))) into tZRedHex
   catch tVfyErr
      return "void:no-dleq"
   end try
   if tZRedHex is not tZHex then
      return "void:scalar-format"
   end if
   try
      put sxRistrettoScalarAdd(sxHash(textEncode(kHeDomainL2Dleq & \
            toLower(pCkHex) & "|" & toLower(pP1Hex) & "|" & \
            toLower(pP2Hex) & "|" & toLower(tA1Hex) & "|" & \
            toLower(tA2Hex), "utf-8"), 32), \
            heHex2BinD(kHeL2ZeroScalar)) into tCData
   catch tVfyErr
      return "void:no-dleq"
   end try
   try
      put heBin2HexS(sxRistrettoScalarMultBatch(tCData, \
            heHex2BinD(toLower(pCkHex) & toLower(pP2Hex)))) into tPairHex
   catch tVfyErr
      return "void:identity-point"
   end try
   put char 1 to 64 of tPairHex into tCCkHex
   put char 65 to 128 of tPairHex into tCP2Hex
   try
      put heBin2HexS(sxRistrettoAdd(heHex2BinD(tA1Hex), \
            heHex2BinD(tCCkHex))) into tLhsHex
      put heBin2HexS(sxRistrettoScalarMultBase(heHex2BinD(tZHex))) into tRhsHex
   catch tVfyErr
      return "void:dleq-mismatch:1"
   end try
   if tLhsHex is not tRhsHex then
      return "void:dleq-mismatch:1"
   end if
   try
      put heBin2HexS(sxRistrettoAdd(heHex2BinD(tA2Hex), \
            heHex2BinD(tCP2Hex))) into tLhsHex
      put heBin2HexS(sxRistrettoScalarMultPoint(heHex2BinD(tZHex), \
            heHex2BinD(pP1Hex))) into tRhsHex
   catch tVfyErr
      return "void:dleq-mismatch:2"
   end try
   if tLhsHex is not tRhsHex then
      return "void:dleq-mismatch:2"
   end if
   return "ok"
end heL2DleqVerify

function heL2ShuffleBodyOf pPos, pCkHex, pDeckList
   -- the PINNED shuffleStep record format (the section banner): the deck's
   -- commas become "|" inside the body field, the spec 6 multi-value idiom
   local tPipeList
   put pDeckList into tPipeList
   replace comma with "|" in tPipeList
   return "pos=" & pPos & ",ck=" & pCkHex & ",deck=" & tPipeList
end heL2ShuffleBodyOf

function heL2UnmaskBodyOf pPos, pSlot, pValHex, pProofHex
   -- the PINNED unmaskStep record format; proof is spec 7.4's reserved
   -- field, empty below Phase 5 hardening
   return "pos=" & pPos & ",slot=" & pSlot & ",val=" & pValHex & \
         ",proof=" & pProofHex
end heL2UnmaskBodyOf

function heL2ChainOrder pCount, pOwner
   -- the contributor order of one unmask chain: 1..count in seat order,
   -- the owner removed for a hole slot (spec 7.3: the owner goes LAST and
   -- its step is exactly what is absent from the public chain)
   local tPos, tOut
   put empty into tOut
   repeat with tPos = 1 to pCount
      if tPos is pOwner then
         next repeat
      end if
      if tOut is empty then
         put tPos into tOut
      else
         put comma & tPos after tOut
      end if
   end repeat
   return tOut
end heL2ChainOrder

function heL2VoidMark pStateA, pNamed, pWhy
   -- latch the machine void. pNamed = 0 means attribution is DEFERRED to
   -- the mandatory full-reveal audit (heL2VoidAudit); any later record is
   -- ignored -- a void hand is frozen evidence.
   put "void" into pStateA["phase"]
   put pNamed into pStateA["named"]
   put pWhy into pStateA["why"]
   put "void" into pStateA["last"]
   return pStateA
end heL2VoidMark

function heL2VoidNew pCount, pBaseList, pDleq, pOwnersList
   -- one hand's 4d deal machine (values in, values out -- the caller
   -- shuttles the state array through every step). pOwnersList is a comma
   -- list of <slot>:<ownerPos> pairs naming the hole slots: the deal
   -- layout is PUBLIC (spec 7.3 fixed order), so the ORCHESTRATOR
   -- declares it -- a record cannot, or a cheater would.
   local tStateA, tPair, tColonPos, tSlotF, tOwnF
   put pCount into tStateA["count"]
   put pBaseList into tStateA["base"]
   if pDleq is true then
      put "true" into tStateA["dleq"]
   else
      put "false" into tStateA["dleq"]
   end if
   put "shuffle" into tStateA["phase"]
   put 0 into tStateA["applied"]
   put 0 into tStateA["named"]
   put empty into tStateA["why"]
   put 0 into tStateA["stall"]
   put empty into tStateA["last"]
   put pBaseList into tStateA["deckAt"][0]
   if pCount is not an integer or pCount < 2 or pCount > 9 then
      return heL2VoidMark(tStateA, 0, "void:count-range")
   end if
   set the itemDelimiter to comma
   if the number of items of pBaseList is not 52 then
      return heL2VoidMark(tStateA, 0, "void:deck-size")
   end if
   if pOwnersList is not empty then
      repeat for each item tPair in pOwnersList
         put offset(":", tPair) into tColonPos
         if tColonPos is 0 then
            return heL2VoidMark(tStateA, 0, "void:owner-format")
         end if
         put char 1 to tColonPos - 1 of tPair into tSlotF
         put char tColonPos + 1 to -1 of tPair into tOwnF
         if tSlotF is not an integer or tOwnF is not an integer then
            return heL2VoidMark(tStateA, 0, "void:owner-format")
         end if
         if tSlotF < 1 or tSlotF > 52 or tOwnF < 1 or tOwnF > pCount then
            return heL2VoidMark(tStateA, 0, "void:owner-format")
         end if
         put tSlotF + 0 into tSlotF
         put tOwnF + 0 into tStateA["owner"][tSlotF]
      end repeat
   end if
   return tStateA
end heL2VoidNew

function heL2VoidShuffle pStateA, pPos, pBody
   -- apply one shuffleStep record (signer position pPos comes from the
   -- VERIFIED envelope, never from the body -- the body's pos must merely
   -- agree). Strict order (pos = applied + 1); an identical re-post of an
   -- applied step is "dup" (state unmoved -- rp1 redelivers), a DIFFERENT
   -- one is signed equivocation, named directly. The free public checks
   -- run per record: ck validity when present (required under dleq=1),
   -- then the whole-deck duplicate/validity scan (spec 7.3's free
   -- integrity check).
   local tBodyA, tStored, tExpect, tPosF, tCkF, tDeckF, tVerdict
   if pStateA["phase"] is "void" then
      return pStateA
   end if
   put pStateA["shufBody"][pPos] into tStored
   if tStored is not empty then
      if pBody is tStored then
         put "dup" into pStateA["last"]
         return pStateA
      end if
      return heL2VoidMark(pStateA, pPos, "void:step-equivocation:" & pPos)
   end if
   if pStateA["phase"] is not "shuffle" then
      return heL2VoidMark(pStateA, pPos, "void:step-phase")
   end if
   put pStateA["applied"] + 1 into tExpect
   if pPos is not tExpect then
      return heL2VoidMark(pStateA, pPos, "void:step-order:" & tExpect & "," & pPos)
   end if
   put pBody into tBodyA
   split tBodyA by comma and "="
   put tBodyA["pos"] into tPosF
   put tBodyA["ck"] into tCkF
   put tBodyA["deck"] into tDeckF
   if tPosF is not an integer or tDeckF is empty then
      return heL2VoidMark(pStateA, pPos, "void:body-format")
   end if
   if tPosF is not pPos then
      return heL2VoidMark(pStateA, pPos, "void:body-pos")
   end if
   if pStateA["dleq"] is "true" and tCkF is empty then
      return heL2VoidMark(pStateA, pPos, "void:ck-missing")
   end if
   if tCkF is not empty then
      put heL2PointOkHex(tCkF) into tVerdict
      if tVerdict is not "ok" then
         return heL2VoidMark(pStateA, pPos, tVerdict)
      end if
   end if
   replace "|" with comma in tDeckF
   put heL2DeckCheckHex(tDeckF) into tVerdict
   if tVerdict is not "ok" then
      return heL2VoidMark(pStateA, pPos, tVerdict)
   end if
   put tDeckF into pStateA["deckAt"][pPos]
   put tCkF into pStateA["ck"][pPos]
   put pBody into pStateA["shufBody"][pPos]
   put pPos into pStateA["applied"]
   put "applied" into pStateA["last"]
   if pPos is pStateA["count"] then
      put "deal" into pStateA["phase"]
   end if
   return pStateA
end heL2VoidShuffle

function heL2VoidUnmask pStateA, pPos, pBody
   -- apply one unmaskStep record to its slot's chain. Per-record refusals
   -- (format, validity, chain order, a bad or missing DLEQ proof under
   -- dleq=1) are named DIRECTLY; a completed public chain landing outside
   -- the card table voids with attribution DEFERRED to the audit -- only
   -- the reveals can say whose step lied (spec 7.3's void-and-audit rule).
   local tBodyA, tPosF, tSlotF, tValF, tProofF, tSlot, tStored, tCount
   local tChainN, tOwner, tNeed, tOrder, tStep, tExpect, tVerdict
   local tChainTxt, tFinalDeck, tPrevHex, tCkStored, tCardTxt
   if pStateA["phase"] is "void" then
      return pStateA
   end if
   put pBody into tBodyA
   split tBodyA by comma and "="
   put tBodyA["pos"] into tPosF
   put tBodyA["slot"] into tSlotF
   put tBodyA["val"] into tValF
   put tBodyA["proof"] into tProofF
   if tPosF is not an integer or tSlotF is not an integer or tValF is empty then
      return heL2VoidMark(pStateA, pPos, "void:body-format")
   end if
   if tPosF is not pPos then
      return heL2VoidMark(pStateA, pPos, "void:body-pos")
   end if
   put tSlotF + 0 into tSlot
   if tSlot < 1 or tSlot > 52 then
      return heL2VoidMark(pStateA, pPos, "void:slot-range")
   end if
   put pStateA["lastBody"][tSlot] into tStored
   if tStored is not empty and pBody is tStored then
      put "dup" into pStateA["last"]
      return pStateA
   end if
   if pStateA["phase"] is not "deal" then
      return heL2VoidMark(pStateA, pPos, "void:step-phase")
   end if
   put pStateA["count"] into tCount
   put pStateA["chainN"][tSlot] into tChainN
   if tChainN is empty then
      put 0 into tChainN
   end if
   put pStateA["owner"][tSlot] into tOwner
   if tOwner is empty then
      put 0 into tOwner
   end if
   if tOwner is 0 then
      put tCount into tNeed
   else
      put tCount - 1 into tNeed
   end if
   if tChainN >= tNeed then
      return heL2VoidMark(pStateA, pPos, "void:chain-done:" & tSlot)
   end if
   put heL2ChainOrder(tCount, tOwner) into tOrder
   set the itemDelimiter to comma
   put tChainN + 1 into tStep
   put item tStep of tOrder into tExpect
   if pPos is not tExpect then
      return heL2VoidMark(pStateA, pPos, \
            "void:chain-order:" & tSlot & ":" & tExpect & "," & pPos)
   end if
   put heL2PointOkHex(tValF) into tVerdict
   if tVerdict is not "ok" then
      return heL2VoidMark(pStateA, pPos, tVerdict)
   end if
   put pStateA["chain"][tSlot] into tChainTxt
   if tChainTxt is empty then
      put pStateA["deckAt"][tCount] into tFinalDeck
      put item tSlot of tFinalDeck into tChainTxt
   end if
   put item -1 of tChainTxt into tPrevHex
   if pStateA["dleq"] is "true" and tProofF is empty then
      return heL2VoidMark(pStateA, pPos, "void:proof-missing:" & tSlot)
   end if
   if tProofF is not empty then
      put pStateA["ck"][pPos] into tCkStored
      if tCkStored is empty then
         return heL2VoidMark(pStateA, pPos, "void:ck-missing:" & tSlot)
      end if
      put heL2DleqVerify(tCkStored, tValF, tPrevHex, tProofF) into tVerdict
      if tVerdict is not "ok" then
         return heL2VoidMark(pStateA, pPos, tVerdict & ":" & tSlot)
      end if
   end if
   put tChainTxt & comma & tValF into pStateA["chain"][tSlot]
   put tStep into pStateA["chainN"][tSlot]
   put pBody into pStateA["lastBody"][tSlot]
   put "applied" into pStateA["last"]
   if tStep is tNeed then
      if tOwner is 0 then
         put pStateA["chain"][tSlot] into tChainTxt
         put heL2PublicCardHex(tChainTxt, pStateA["base"]) into tCardTxt
         if tCardTxt begins with "card:" then
            put tCardTxt into pStateA["card"][tSlot]
         else
            return heL2VoidMark(pStateA, 0, tCardTxt & ":" & tSlot)
         end if
      else
         put "true" into pStateA["holeUp"][tSlot]
      end if
   end if
   return pStateA
end heL2VoidUnmask

function heL2VoidTimeout pStateA, pOwedPos
   -- the deal-phase timer expired with pOwedPos owing the next step (spec
   -- 9's timeout-in-dealing). PROVISIONALLY named: the mandatory audit
   -- keeps the staller's name only when every signed step re-verifies --
   -- an earlier bad signed step outranks the stall (spec 7.3 names the
   -- FIRST bad one).
   if pStateA["phase"] is "void" then
      return pStateA
   end if
   put pOwedPos into pStateA["stall"]
   return heL2VoidMark(pStateA, pOwedPos, "void:deal-timeout:" & pOwedPos)
end heL2VoidTimeout

function heL2VoidOutcome pStateA
   -- the 4d verdict line the orchestrator acts on. A void hand ALWAYS
   -- returns the bets and ALWAYS owes the full reveal (spec 7.3: the hand
   -- is void, so the reveal costs nothing; the config-signed forfeit for
   -- the named party is table policy, applied above this layer);
   -- named=audit defers attribution to heL2VoidAudit.
   local tNamed
   if pStateA["phase"] is not "void" then
      return pStateA["phase"]
   end if
   put pStateA["named"] into tNamed
   if tNamed > 0 then
      return "void|" & pStateA["why"] & "|named=" & tNamed & \
            "|bets-return|reveal-required"
   end if
   return "void|" & pStateA["why"] & "|named=audit|bets-return|reveal-required"
end heL2VoidOutcome

function heL2VoidAudit pStateA, pRevealsText
   -- the MANDATORY full-reveal audit, in the MANDATORY order: per
   -- contributor 1..count -- reveal present (refusing the audit makes the
   -- refuser the named party, spec 7.3), the ck binding when a ck was
   -- posted (a lying commitment key is caught here, before any algebra),
   -- the shuffle step re-verified from (k, sigma) -- then every opened
   -- chain in slot order, each step in chain order, re-verified from the
   -- stepper's revealed k. The FIRST bad signed step names the cheater; a
   -- recorded staller keeps the name only when everything signed
   -- re-verifies; a clean audit is the table agreeing to void. Reveals:
   -- one line per contributor, <pos> TAB <kHex> TAB <sigma comma-list>.
   local tLine, tPosF, tRkA, tRsA, tPosI, tCkStored, tInDeck, tOutDeck
   local tVerdict, tSlot, tChainN, tChainTxt, tOwner, tOrder, tStep
   local tInHex, tOutHex, tStepPos
   repeat for each line tLine in pRevealsText
      if tLine is empty then
         next repeat
      end if
      set the itemDelimiter to tab
      put item 1 of tLine into tPosF
      put item 2 of tLine into tRkA[tPosF]
      put item 3 of tLine into tRsA[tPosF]
   end repeat
   repeat with tPosI = 1 to pStateA["count"]
      if tRkA[tPosI] is empty then
         return "named=" & tPosI & "|void:audit-refused"
      end if
      put pStateA["ck"][tPosI] into tCkStored
      if tCkStored is not empty and heL2HasDleq() then
         -- (the KAT mirror always has the algebra; a pre-ABI-9 engine
         -- cannot compute k*B, so it skips the binding and still audits)
         if heL2CommitKeyHex(tRkA[tPosI]) is not tCkStored then
            return "named=" & tPosI & "|void:audit-ck-mismatch"
         end if
      end if
      put pStateA["deckAt"][tPosI - 1] into tInDeck
      put pStateA["deckAt"][tPosI] into tOutDeck
      put heL2RevealShuffleHex(tInDeck, tOutDeck, tRkA[tPosI], tRsA[tPosI]) \
            into tVerdict
      if tVerdict is not "ok" then
         return "named=" & tPosI & "|" & tVerdict
      end if
   end repeat
   repeat with tSlot = 1 to 52
      put pStateA["chainN"][tSlot] into tChainN
      if tChainN is empty or tChainN is 0 then
         next repeat
      end if
      put pStateA["chain"][tSlot] into tChainTxt
      put pStateA["owner"][tSlot] into tOwner
      if tOwner is empty then
         put 0 into tOwner
      end if
      put heL2ChainOrder(pStateA["count"], tOwner) into tOrder
      set the itemDelimiter to comma
      repeat with tStep = 1 to tChainN
         put item tStep of tChainTxt into tInHex
         put item tStep + 1 of tChainTxt into tOutHex
         put item tStep of tOrder into tStepPos
         put heL2RevealUnmaskHex(tInHex, tOutHex, tRkA[tStepPos]) into tVerdict
         if tVerdict is not "ok" then
            return "named=" & tStepPos & "|" & tVerdict & ":" & tSlot & ":" & tStep
         end if
      end repeat
   end repeat
   if pStateA["stall"] > 0 then
      return "named=" & pStateA["stall"] & "|" & pStateA["why"]
   end if
   return "named=0|audit-clean"
end heL2VoidAudit

--------------------------------------------------------------------------
-- Online transport (Phase 2a/2b, spec 3/4/5/10). Peers meet on the DHT via
-- a phantom swarm keyed by the table code, talk over rp1, and route every
-- game message through the host (a star topology, spec 4): a player signs a
-- content line and sends it to the host; the host assigns seq + prev,
-- countersigns, and rebroadcasts the sequenced wire; everyone verifies-or-
-- drops and folds it. The admission-token, envelope, and fold logic are pure
-- and KAT-pinned; the bt*/session/rp1 calls are seams that NEED AN OXT PASS.
--
-- gGame online keys: online session isHost tableIdHex infohashHex idPubHex
-- idSecData boxPubData boxSecData seqCounter chainHeadHex hostPubHex, plus
-- arrays peerPubA[peer]->pubHex, peerByPub[pubHex]->peer, admittedA[pubHex].
--------------------------------------------------------------------------

function heIdentitySeedHex
   -- persistent identity seed (32 bytes, hex), generated once and stored in a
   -- stack custom property; long-term keys only ever sign (spec 5)
   local tSeedHex
   put the uHeIdentitySeed of this stack into tSeedHex
   if the number of chars of tSeedHex is not 64 then
      if heHasSodium() then
         put heBin2HexS(sxRandomBytes(32)) into tSeedHex
      else
         put heHexId(64) into tSeedHex
      end if
      set the uHeIdentitySeed of this stack to tSeedHex
   end if
   return tSeedHex
end heIdentitySeedHex

command heIdentitySetup
   -- derive and cache the long-term ed25519 identity and a fresh per-table
   -- X25519 session box key (private hole-card lanes seal to the box key)
   local tSeedData, tSeedHex, tPub, tSec, tBoxPub, tBoxSec, tBoxErr
   put heIdentitySeedHex() into tSeedHex
   put heHex2BinD(tSeedHex) into tSeedData
   sxSignKeypairFromSeed tSeedData, tPub, tSec
   put heBin2HexS(tPub) into gGame["idPubHex"]
   put tSec into gGame["idSecData"]
   put tSeedHex into gGame["idSeedHex"]   -- the per-hand deal-seed PRF key
   put heFingerprintOf(tPub) into gGame["idFingerprint"]
   -- The per-table X25519 box key is for the FUTURE sealed hole-card lanes; the
   -- current lobby (ed25519 identity + admission tokens) never reads it. It is
   -- derived best-effort and GUARDED: sxBoxKeypairFromSeed is a SodiumXT Phase 4
   -- (public-key box) handler, and a build that ships the sign/hash surface but
   -- not the box surface yet makes it "can't find handler" -- which must not break
   -- a guest join (H4: an unbuilt/absent seam never breaks the working path). The
   -- signature is correct per SodiumXT docs/api-reference.md
   -- (sxBoxKeypairFromSeed pSeed, out rPub, out rSec); it simply may be absent.
   -- NB: the seed is hashed from a TEXT input (domain + seed hex), never a binary
   -- & of two Data values (H6 corollary).
   put empty into gGame["boxPubData"]
   put empty into gGame["boxSecData"]
   try
      sxBoxKeypairFromSeed heHash32(textEncode(kHeDomainSess & tSeedHex, "utf-8")), tBoxPub, tBoxSec
      put tBoxPub into gGame["boxPubData"]
      put tBoxSec into gGame["boxSecData"]
   catch tBoxErr
      -- box lane unavailable on this SodiumXT build; not needed by the lobby yet
   end try
end heIdentitySetup

function heAdmitTokenData pTableHex, pPubHex, pSecData, pRole
   -- signed admission claim (spec 5): sign over
   -- "HOLDEM-SESS-v1|<table>|<pub>|<role>", framed pubHex TAB role TAB sigHex,
   -- published in btRp1SetToken so peers drop strangers at handshake and a
   -- joining player adopts only a self-declared host (role "host")
   local tSigHex
   put heBin2HexS(heSignDetachedD(textEncode(kHeDomainSess & pTableHex & "|" & pPubHex & "|" & pRole, "utf-8"), pSecData)) into tSigHex
   return textEncode(pPubHex & tab & pRole & tab & tSigHex, "utf-8")
end heAdmitTokenData

function heAdmitTokenVerify pTokenData, pTableHex
   -- returns the admitted pubHex if the token is well-formed and its signature
   -- verifies, else "" (the peer is a stranger and is ignored)
   local tTok, tPubHex, tRole, tSigHex, tSaved
   put textDecode(pTokenData, "utf-8") into tTok
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   put item 1 of tTok into tPubHex
   put item 2 of tTok into tRole
   put item 3 of tTok into tSigHex
   set the itemDelimiter to tSaved
   -- a stranger's token is untrusted: reject malformed hex before decoding it
   -- (sxHex2Bin throws) -- 64-char pub and 128-char detached sig (H4)
   if not heIsHex(tPubHex, 64) or not heIsHex(tSigHex, 128) then
      return ""
   end if
   if heVerifyDetached(heHex2BinD(tSigHex), \
         textEncode(kHeDomainSess & pTableHex & "|" & tPubHex & "|" & tRole, "utf-8"), heHex2BinD(tPubHex)) then
      return tPubHex
   end if
   return ""
end heAdmitTokenVerify

function heAdmitTokenRole pTokenData
   -- the role field of a token ("host"/"player"), for host adoption
   local tTok, tRole, tSaved
   put textDecode(pTokenData, "utf-8") into tTok
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   put item 2 of tTok into tRole
   set the itemDelimiter to tSaved
   return tRole
end heAdmitTokenRole

function heRosterBody pMembersList
   -- canonical lobby-presence body (spec 9): each member as "pubHex:role",
   -- sorted ascending, comma-joined -- the exact mirror of roster_body in
   -- tools/protocol-kat.py. pMembersList is return-delimited "pubHex TAB role"
   -- lines; sorting makes every peer sign/verify identical bytes. All chunks
   -- are of plain locals (H6-safe); the body is hex-encoded into the envelope
   -- so its commas never reach the tab-framed wire.
   local tLine, tPubHex, tRoleTxt, tPairs, tSaved
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   put empty into tPairs
   repeat for each line tLine in pMembersList
      put item 1 of tLine into tPubHex
      put item 2 of tLine into tRoleTxt
      put tPubHex & ":" & tRoleTxt & return after tPairs
   end repeat
   set the itemDelimiter to tSaved
   if tPairs is not empty then
      delete char -1 of tPairs
   end if
   sort lines of tPairs
   replace return with comma in tPairs
   return tPairs
end heRosterBody

function heLobbyCfgBody
   -- the table cfg the host signs into the transcript at create time; a clean,
   -- canonical string (pinned as kKatLobbyCfgBody) so joiners verify it byte
   -- for byte. Level 0 is the online deal ladder rung this build targets.
   -- ante + stack joined the body in v0.17.0 (the online game needs the full
   -- stakes to fold deterministically on every client); the pinned constants
   -- in tools/protocol-kat.py were regenerated for the new bytes. Phase 3:
   -- level=1 IS the oracle marker (spec 7.2 is Level 1, the non-playing
   -- dealer) -- no new field, so a playing table's body stays byte-identical
   -- to the v0.17.0 pin, and a pre-oracle client refuses an oracle hand
   -- readably at its dealLevel gate instead of mis-folding the table.
   -- 2e liveness (v0.23.0): the TIMER LENGTHS join the body -- act= (act
   -- timer seconds), bank= (the one per-hand time-bank), miss= (consecutive
   -- timeouts before auto-sit-out) -- per spec 6's "timer lengths" in
   -- message zero. A pre-liveness client ignores keys it does not read
   -- (heNetCfgVal is name-keyed), so the extension is wire-compatible; the
   -- protocol-kat pins (lobby_cfg_body/lobby_head2) were regenerated for
   -- the new bytes, a documented consensus change (kHeHarnessV bumped).
   local tLevelTxt
   put "0" into tLevelTxt
   if gGame["oracleHost"] is "true" then
      put "1" into tLevelTxt
   end if
   return "v=1,level=" & tLevelTxt & ",sb=" & gGame["sb"] & ",bb=" & gGame["bb"] \
         & ",ante=" & gGame["ante"] & ",stack=" & gGame["startStack"] \
         & ",seats=" & kHeDefaultSeats & ",button=1" \
         & ",act=" & kHeDefaultActSecs & ",bank=" & kHeDefaultBankSecs \
         & ",miss=" & kHeDefaultMisses
end heLobbyCfgBody

function heReadableErr pErr
   -- pull the human-readable message out of a LiveCode execution-error struct
   -- (lines of errNo,line,col[,text]); a thrown extension error carries the real
   -- reason as the text field of one of those lines. Returns the first line's
   -- text that reads like a sentence, else the raw error unchanged.
   local tLine, tTxt
   set the itemDelimiter to comma
   repeat for each line tLine in pErr
      if the number of items of tLine >= 4 then
         put item 4 to -1 of tLine into tTxt
         if the number of chars of tTxt > 10 and tTxt contains space then
            return tTxt
         end if
      end if
   end repeat
   return pErr
end heReadableErr

--------------------------------------------------------------------------
-- Phase 2f: invites and the onion-table preliminaries (spec 10 as-built).
-- Pure where the harness needs them pure: the invite codec and the join
-- refusal take values and return values, so section 17 pins them headless.
--------------------------------------------------------------------------

function heHasOnion
   -- OnionXT presence, probed LIVE at each use. The layer is CARRIED in
   -- this stack since v0.25.2 (tools/sync-demo-embeds.py), so a false here
   -- means the embedded copy is damaged rather than a missed `start using`
   -- step - and the probe stays live rather than cached because live is
   -- how it fails CLOSED whatever the cause (the heKitReload lesson). A
   -- guarded oxVersion() call is the family probe (nocloud's qsHasOnion).
   -- Message-rate only, never per-frame.
   local tProbeErr, tVerTxt
   try
      put oxVersion() into tVerTxt
   catch tProbeErr
      return false
   end try
   return tVerTxt is not empty
end heHasOnion

function heOnionSeedHex pIdSeedHex, pTableHex, pModeTxt
   -- the onion-SERVICE seed (see kHeDomainOnion for the derivation's three
   -- properties: secret-keyed, per-table, deterministic). Hex text in and
   -- out; the only Data lives inside the sx* call (H6 corollary). Phase 3:
   -- an ORACLE table (pModeTxt "oracle") derives under its OWN domain tag
   -- (kHeDomainOracle), so the oracle address never collides with the same
   -- host's playing table on the same table id; any other mode (empty,
   -- "play") keeps the 2f playing-table derivation byte-identical. Both
   -- pinned in tools/protocol-kat.py (onion_service_seed /
   -- oracle_service_seed).
   if pModeTxt is "oracle" then
      return heHashDomHex(kHeDomainOracle, textEncode(pIdSeedHex & "|" & pTableHex, "utf-8"))
   end if
   return heHashDomHex(kHeDomainOnion, textEncode(pIdSeedHex & "|" & pTableHex, "utf-8"))
end heOnionSeedHex

function heInviteTxt
   -- the shareable invite for the CURRENT table (2f as-built): DHT tables
   -- keep the bare 64-hex code; an onion table appends "@" and the host's
   -- derived onion address, so one pasteable string carries the transport,
   -- the rendezvous, and -- because a v3 address IS the service's ed25519
   -- public key -- the host endpoint's identity.
   local tAddrTxt
   put gGame["onionAddrTxt"] into tAddrTxt
   if gGame["transport"] is "onion" and tAddrTxt is not empty then
      return gGame["tableIdHex"] & "@" & tAddrTxt
   end if
   return gGame["tableIdHex"]
end heInviteTxt

function heInviteParse pInviteTxt
   -- parse an invite into transport/table/onion (2f). A COMPATIBLE extension
   -- of the original invite: a bare 64-hex code stays the DHT invite; an
   -- onion invite is "<64hex>@<56-base32>.onion" -- ONE word, "@"-joined,
   -- deliberately NOT hex, so a pre-2f stack's `word 1` + heIsHex gate
   -- refuses the WHOLE invite with its readable message instead of silently
   -- joining a DHT table nobody announced (downgrade refusal by format).
   -- Structural validation only (pure, harness-pinned); OnionXT's checksum
   -- validator runs as a belt at join time. Case is normalized: an uppercase
   -- paste would otherwise bind a mismatching table id and every wire would
   -- drop as wrong-table. Returns an array: "err" (empty, or the readable
   -- refusal), "transport", "table", "onion".
   local tA, tTxt, tAtPos, tTableTxt, tAddrTxt, tCore, tI, tCh
   put empty into tA["err"]
   put empty into tA["transport"]
   put empty into tA["table"]
   put empty into tA["onion"]
   put word 1 of pInviteTxt into tTxt
   if tTxt is empty then
      put "Paste an invite code first." into tA["err"]
      return tA
   end if
   put toLower(tTxt) into tTxt
   put offset("@", tTxt) into tAtPos
   if tAtPos is 0 then
      if not heIsHex(tTxt, 64) then
         put "Invite code must be 64 hex characters (or 64hex@<address>.onion for an onion table)." into tA["err"]
         return tA
      end if
      put "rp1" into tA["transport"]
      put tTxt into tA["table"]
      return tA
   end if
   put char 1 to (tAtPos - 1) of tTxt into tTableTxt
   put char (tAtPos + 1) to -1 of tTxt into tAddrTxt
   if not heIsHex(tTableTxt, 64) then
      put "Onion invite: the part before the @ must be the 64-hex table code." into tA["err"]
      return tA
   end if
   if not (tAddrTxt ends with ".onion") then
      put "Onion invite: the part after the @ must be a .onion address." into tA["err"]
      return tA
   end if
   put char 1 to -7 of tAddrTxt into tCore
   if the number of chars of tCore is not 56 then
      put "Onion invite: a v3 onion address is 56 characters before .onion (got " \
            & the number of chars of tCore & ")." into tA["err"]
      return tA
   end if
   repeat with tI = 1 to 56
      put char tI of tCore into tCh
      if offset(tCh, "abcdefghijklmnopqrstuvwxyz234567") is 0 then
         put "Onion invite: the address carries a character no onion address can (" & tCh & ")." into tA["err"]
         return tA
      end if
   end repeat
   put "onion" into tA["transport"]
   put tTableTxt into tA["table"]
   put tAddrTxt into tA["onion"]
   return tA
end heInviteParse

function heJoinRefusal pInvA, pHasOnion
   -- the join-side fail-closed gate (2f), PURE so the harness drives both
   -- branches headlessly: OnionXT presence is a PARAMETER, not a probe. A
   -- malformed invite refuses with the parser's reason; an onion invite on
   -- a stack without OnionXT refuses OUTRIGHT -- never a silent downgrade
   -- to the DHT transport, so "onion table" keeps meaning what the host
   -- chose. Returns "" (join may proceed) or the readable refusal.
   local tErrTxt
   put pInvA["err"] into tErrTxt
   if tErrTxt is not empty then
      return tErrTxt
   end if
   if pInvA["transport"] is "onion" and pHasOnion is not true then
      return "This is an ONION table invite: it needs OnionXT and a running tor daemon. OnionXT is carried inside this stack, so this refusal means the embedded copy is damaged (re-download the stack, or run tools/sync-demo-embeds.py). There is no fallback transport -- ask the host for a DHT-table invite."
   end if
   return empty
end heJoinRefusal

command heNetStart
   -- start the table's transport and arm the poll drain. NEEDS AN OXT PASS.
   -- Requires tableIdHex + identity already set (heTableCreate/heTableJoin
   -- do that first). 2f: gGame["transport"] routes -- "onion" brings up the
   -- tor transport, anything else the TorrentXT session + rp1 below.
   local tSession, tRole, tErr, tRp1Err
   if gGame["online"] is "true" then
      exit heNetStart
   end if
   if gGame["transport"] is "onion" then
      heNetStartOnion
      exit heNetStart
   end if
   try
      put btStartSession() into tSession
   catch tErr
      -- btStartSession is the one bt* handler that throws, and the usual cause is
      -- an ABI mismatch between TorrentXT's bundled native library and its .lcb
      -- binding (reinstall/repackage TorrentXT so they match). Surface the
      -- readable reason, not the raw LiveCode error struct.
      heUISetStatus "TorrentXT session failed to start: " & heReadableErr(tErr) \
            & "  --  reinstall/rebuild TorrentXT so its native library matches its binding. Hotseat still works."
      exit heNetStart
   end try
   if tSession is 0 or tSession is empty then
      heUISetStatus "Network start failed: " & btLastError()
      exit heNetStart
   end if
   put tSession into gGame["session"]
   if gGame["isHost"] is "true" then
      put "host" into tRole
   else
      put "player" into tRole
   end if
   -- rp1 is TorrentXT's peer-wire messaging plugin (ABI v8+); a build that ships
   -- the session/DHT surface but not rp1 makes btRp1Enable "can't find handler".
   -- The online game needs rp1, so if the transport setup can't complete, tear the
   -- session back down and report it clearly rather than crash the join (H4/H1).
   try
      btSetBool tSession, "enable_dht", true
      btRp1Enable tSession
      btRp1SetToken tSession, heAdmitTokenData(gGame["tableIdHex"], gGame["idPubHex"], gGame["idSecData"], tRole)
   catch tRp1Err
      heUISetStatus "This TorrentXT build has no rp1 peer messaging (needs the rp1 plugin, ABI v8+): " \
            & tRp1Err & ".  Online is unavailable on this build; hotseat still works."
      try
         btStopSession tSession
      catch tErr
      end try
      put empty into gGame["session"]
      exit heNetStart
   end try
   put "true" into gGame["online"]
   send "heNetPollTick" to me in 250 milliseconds
end heNetStart

command heNetStop
   local tMsgLine, tKeyTxt, tCloseErr
   if gGame["online"] is not "true" then
      exit heNetStop
   end if
   put "false" into gGame["online"]
   -- cancel the outstanding poll tick before tearing the session down: the online
   -- flag alone let a stale tick (scheduled before the stop) revive itself, so a
   -- re-create/re-join forked a SECOND poll loop that never died (H2). Sweep our
   -- own poll send. (gotcha 5: pendingMessages is comma-delimited id,time,name,..)
   set the itemDelimiter to comma
   repeat for each line tMsgLine in the pendingMessages
      if item 3 of tMsgLine is "heNetPollTick" then
         cancel item 1 of tMsgLine
      end if
   end repeat
   if gGame["transport"] is "onion" then
      -- H1: close every stream this table owns (a peer's handle IS its
      -- stream here; oxCloseStream is idempotent, so the overlap between the
      -- maps is harmless) and DEL_ONION the service. The control connection
      -- deliberately STAYS up -- re-creating a table reuses it, and
      -- closeStack's oxShutdown is the final teardown. Every ox* touch is
      -- guarded (H8): a mid-session library unload must not wedge the stop.
      try
         repeat for each key tKeyTxt in gGame["peerPubA"]
            oxCloseStream tKeyTxt
         end repeat
      catch tCloseErr
      end try
      try
         repeat for each key tKeyTxt in gGame["oxSeenA"]
            oxCloseStream tKeyTxt
         end repeat
      catch tCloseErr
      end try
      try
         if gGame["oxStream"] is not empty then
            oxCloseStream gGame["oxStream"]
         end if
      catch tCloseErr
      end try
      try
         if gGame["oxService"] is not empty then
            oxRemoveService gGame["oxService"]
         end if
      catch tCloseErr
      end try
      put empty into gGame["oxService"]
      put empty into gGame["oxStream"]
      put empty into gGame["oxBufA"]
      put empty into gGame["oxSeenA"]
   else
      btStopSession gGame["session"]
   end if
end heNetStop

command heNetParkHotseat
   -- Going online CLOBBERS gGame["log"] (heTableCreate/heTableJoin empty it and
   -- refill it with signed wires), but the hotseat game is driven by paced timer
   -- sends that only gate on gGame["phase"]. Pressing Lobby -> Create/Join mid-hand
   -- therefore left heRevealStep / heRunoutStep / heSettleStep / heNextHandTick
   -- armed with their phase still matching: they would fire into the online table,
   -- append raw 4-field hotseat lines (settle, handStart, holeDeliver, bids...)
   -- into the signed wire log, and heNetReplayLogTo would then ship those junk
   -- lines to every joining peer as "w" frames. Park the hand first: sweep the
   -- paced sends and drop the phase to "idle" so any send that already escaped the
   -- sweep hits its own stale-guard and exits. The hand in progress is abandoned
   -- (its transcript is about to be replaced), which is what going online means.
   heCancelPacedSteps
   put "idle" into gGame["phase"]
   heDisableActions
   heUIClearCards
end heNetParkHotseat

command heNetJoinSwarm pIsHost
   -- add the phantom swarm on the table's rendezvous id, then announce (host)
   -- or discover (player) on the DHT (spec 10). The DHT carries zero game data.
   -- Only runs when heNetStart brought the transport fully up (online true), so a
   -- build that failed the rp1 setup never reaches these DHT calls; guarded anyway.
   local tSession, tSwarmErr
   if gGame["online"] is not "true" then
      exit heNetJoinSwarm
   end if
   if gGame["transport"] is "onion" then
      -- onion tables never touch the DHT: the invite carries the rendezvous
      -- (the host's onion address), and spec 10's "the DHT carries zero game
      -- data" becomes "the DHT carries nothing at all"
      exit heNetJoinSwarm
   end if
   put gGame["session"] into tSession
   try
      get btAddInfohash(tSession, gGame["infohashHex"], heTempPath())
      if pIsHost then
         btDhtAnnounce tSession, gGame["infohashHex"], 0
      else
         btDhtGetPeers tSession, gGame["infohashHex"]
      end if
   catch tSwarmErr
      heUISetStatus "DHT rendezvous unavailable on this TorrentXT build: " & tSwarmErr
   end try
end heNetJoinSwarm

function heTableInfohash pTableHex
   -- the DHT rendezvous id is the first 40 hex (20 bytes) of H(tableId) (spec 10)
   return char 1 to 40 of heHashHex(heHex2BinD(pTableHex))
end heTableInfohash

command heTableCreate
   -- become the host of a fresh table; the table code IS the invite (2f: an
   -- onion table's invite appends the derived onion address -- heInviteTxt).
   -- online play needs the crypto -- guard so a Sodium-less engine gets a
   -- friendly status, not a hard throw out of heIdentitySetup (H4/UX)
   local tTransport, tTableHex, tOnionSeedHex, tSvcPub, tSvcSec, tAddrTxt, tKeyErr
   if not heHasSodium() then
      heUISetStatus "Online tables need SodiumXT installed. You can still play hotseat."
      exit heTableCreate
   end if
   heCfgEnsure
   put gCfg["transport"] into tTransport
   -- ONION PRE-FLIGHT, before any teardown: every refusal below leaves a
   -- running hotseat game untouched (fail closed, the nocloud pattern; no
   -- silent fallback to the DHT transport -- the host chose onion).
   if tTransport is "onion" then
      if not heHasOnion() then
         heUISetStatus "Onion tables need OnionXT plus a locally running tor daemon (SOCKS 9050, control 9051). OnionXT is carried inside this stack - this refusal means the embedded copy is damaged (re-download, or run tools/sync-demo-embeds.py). No silent fallback -- switch Host over to DHT."
         exit heTableCreate
      end if
      -- the table id is minted EARLY so the onion address -- a pure function
      -- of identity seed + table id (kHeDomainOnion) -- can be derived and
      -- refused OFFLINE before anything is torn down. The v3 address IS the
      -- service's ed25519 public key: sxSignKeypairFromSeed and OnionXT's
      -- expanded-key publish path share ed25519's seed->pub derivation, and
      -- the published address is cross-checked against this one when the
      -- descriptor uploads (heNetOnionTick's "pub" state).
      put heBin2HexS(sxRandomBytes(32)) into tTableHex
      -- Phase 3: an oracle table derives its service seed under its own
      -- domain tag (heOnionSeedHex's third argument)
      put heOnionSeedHex(heIdentitySeedHex(), tTableHex, gCfg["hostMode"]) into tOnionSeedHex
      try
         sxSignKeypairFromSeed heHex2BinD(tOnionSeedHex), tSvcPub, tSvcSec
         put oxAddressFromPublicKey(tSvcPub) into tAddrTxt
      catch tKeyErr
         heUISetStatus "Onion address derivation failed: " & heReadableErr(tKeyErr)
         exit heTableCreate
      end try
      if not (tAddrTxt ends with ".onion") then
         -- oxAddressFromPublicKey surfaces its capability error verbatim:
         -- the offline checksum needs SodiumXT ABI 7+ (sxSha3_256)
         heUISetStatus "Onion tables need SodiumXT ABI 7+ for the offline onion address: " & tAddrTxt
         exit heTableCreate
      end if
   end if
   -- tear down any prior session first so a re-create starts a clean swarm
   heNetStop
   heNetParkHotseat
   heIdentitySetup
   if tTransport is "onion" then
      put tTableHex into gGame["tableIdHex"]
   else if heHasSodium() then
      put heBin2HexS(sxRandomBytes(32)) into gGame["tableIdHex"]
   else
      put heHexId(64) into gGame["tableIdHex"]
   end if
   put heTableInfohash(gGame["tableIdHex"]) into gGame["infohashHex"]
   put "true" into gGame["isHost"]
   -- Phase 3: bind the host MODE at create time (a Settings change mid-table
   -- must never flip a live table's deal level) -- "oracle" makes this host
   -- deal every hand and take no seat; the signed cfg carries it as level=1
   put empty into gGame["oracleHost"]
   if gCfg["hostMode"] is "oracle" then
      put "true" into gGame["oracleHost"]
   end if
   put gGame["idPubHex"] into gGame["hostPubHex"]
   put 0 into gGame["handNum"]
   put 0 into gGame["seqCounter"]
   put kHeGenesisPrev into gGame["chainHeadHex"]
   put 0 into gGame["lastSeq"]
   put empty into gGame["wireBuf"]
   put 0 into gGame["wireBufN"]
   put empty into gGame["peerPubA"]
   put empty into gGame["peerByPub"]
   put empty into gGame["admittedA"]
   put empty into gGame["roleByPub"]
   put empty into gGame["log"]
   put empty into gGame["netLog"]
   put 0 into gGame["syncCooldown"]
   -- the host must admit ITSELF so heHostRelay accepts the host's own actions
   put "true" into gGame["admittedA"][gGame["idPubHex"]]
   put "host" into gGame["roleByPub"][gGame["idPubHex"]]
   heNetGameInit
   put tTransport into gGame["transport"]
   heNetOnionReset
   if tTransport is "onion" then
      put tAddrTxt into gGame["onionAddrTxt"]
      put tOnionSeedHex into gGame["oxSeedHex"]
   end if
   heNetStart
   if gGame["online"] is not "true" then
      exit heTableCreate   -- transport unavailable; heNetStart set the status
   end if
   heNetJoinSwarm true
   -- seed the transcript with a signed table cfg (seq 1, from genesis); late
   -- joiners replay it and verify the host's key before anything else
   heNetSendAction "cfg", heLobbyCfgBody()
   if tTransport is "onion" then
      heUISetStatus "Onion table created -- publishing over tor (watch the Tor line). Share this invite: " & heInviteTxt()
   else
      heUISetStatus "Table created. Share this invite code: " & heInviteTxt()
   end if
end heTableCreate

command heTableJoin pCodeTxt
   -- join an existing table from its invite code. 2f: the INVITE names the
   -- transport (heInviteParse), so there is nothing to toggle on the join
   -- side -- and every refusal fires BEFORE any teardown, so a bad paste
   -- leaves a running hotseat game untouched.
   local tCode, tInvA, tRefusalTxt, tValidOk, tValidErr
   put heInviteParse(pCodeTxt) into tInvA
   put heJoinRefusal(tInvA, heHasOnion()) into tRefusalTxt
   if tRefusalTxt is not empty then
      heUISetStatus tRefusalTxt
      exit heTableJoin
   end if
   if not heHasSodium() then
      heUISetStatus "Online tables need SodiumXT installed. You can still play hotseat."
      exit heTableJoin
   end if
   put tInvA["table"] into tCode
   if tInvA["transport"] is "onion" then
      -- belt over the structural parse: OnionXT's own validator (checksum-
      -- checking when SodiumXT ships SHA3-256) refuses a corrupted paste
      -- HERE instead of after a 60 s dial timeout. Guarded (H8): the belt
      -- must never itself throw a join; the dial still authenticates the
      -- address either way (a v3 onion IS its key).
      put true into tValidOk
      try
         put oxIsValidAddress(tInvA["onion"]) into tValidOk
      catch tValidErr
         put true into tValidOk
      end try
      if tValidOk is not true then
         heUISetStatus "That onion invite's address does not validate (corrupted paste?). Ask the host to copy the invite again."
         exit heTableJoin
      end if
   end if
   -- tear down any prior session first so a re-join starts clean
   heNetStop
   heNetParkHotseat
   heIdentitySetup
   put tCode into gGame["tableIdHex"]
   put heTableInfohash(tCode) into gGame["infohashHex"]
   put "false" into gGame["isHost"]
   put empty into gGame["oracleHost"]
   put empty into gGame["hostPubHex"]
   put 0 into gGame["handNum"]
   put kHeGenesisPrev into gGame["chainHeadHex"]
   put 0 into gGame["lastSeq"]
   put empty into gGame["wireBuf"]
   put 0 into gGame["wireBufN"]
   put empty into gGame["peerPubA"]
   put empty into gGame["peerByPub"]
   put empty into gGame["admittedA"]
   put empty into gGame["roleByPub"]
   put empty into gGame["log"]
   put empty into gGame["netLog"]
   put 0 into gGame["syncCooldown"]
   -- admit ourselves as a player so the local roster shows our own seat
   put "true" into gGame["admittedA"][gGame["idPubHex"]]
   put "player" into gGame["roleByPub"][gGame["idPubHex"]]
   heNetGameInit
   put tInvA["transport"] into gGame["transport"]
   heNetOnionReset
   if tInvA["transport"] is "onion" then
      put tInvA["onion"] into gGame["onionAddrTxt"]
   end if
   heNetStart
   if gGame["online"] is not "true" then
      exit heTableJoin   -- transport unavailable; heNetStart set the status
   end if
   heNetJoinSwarm false
   if tInvA["transport"] is "onion" then
      heUISetStatus "Joining onion table " & char 1 to 12 of tCode & "... connecting through tor (watch the Tor line)."
   else
      heUISetStatus "Joining table " & char 1 to 12 of tCode & "... waiting for the host."
   end if
end heTableJoin

on heNetPollTick
   -- one poll drain per tick (H2): rp1 events for gameplay, plus btPoll to
   -- keep the engine's own event queue clear. Never per-frame. 2f: for an
   -- onion table the tick instead runs the tor transport's whole budget --
   -- the bring-up state machine plus the stream-buffer drain -- guarded the
   -- same way, and the re-arm below ALWAYS runs either way.
   local tEvents, tEv, tPollErr
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if gGame["online"] is not "true" then
      exit heNetPollTick
   end if
   -- age the resync debounce one tick (heNetRequestSync sets it to 8)
   if gGame["syncCooldown"] > 0 then
      subtract 1 from gGame["syncCooldown"]
   end if
   -- spec 9 host-loss watchdog (2e/Phase 3): one compare per tick when idle;
   -- guarded so a first-contact fault can never kill the poll loop (H4)
   try
      heNetHostLossCheck
   catch tPollErr
      put "poll   host-loss check threw: " & tPollErr & return after gGame["netLog"]
   end try
   -- 2e act timers (spec 8.1/9), both transports: the countdown + the
   -- host's timeout emission live on the SAME tick (H2), guarded so a
   -- first-contact fault can never kill the poll loop (H4)
   try
      heNetActTimerTick
   catch tPollErr
      put "poll   act-timer tick threw: " & tPollErr & return after gGame["netLog"]
   end try
   if gGame["transport"] is "onion" then
      try
         heNetOnionTick
      catch tPollErr
         put "poll   onion tick threw: " & tPollErr & return after gGame["netLog"]
      end try
      send "heNetPollTick" to me in 250 milliseconds
      exit heNetPollTick
   end if
   -- The DRAIN ITSELF has to be guarded too, not just the per-event dispatch: a
   -- throw out of btRp1Poll/btPoll (a torn-down or stale session handle, an
   -- extension-side fault) escaped this handler entirely, so the re-arm below never
   -- ran and the poll loop died silently -- online play just stopped receiving,
   -- with no error anywhere. Empty events on a failed drain, then carry on (H4).
   put empty into tEvents
   try
      put btRp1Poll(gGame["session"]) into tEvents
   catch tPollErr
      put "poll   btRp1Poll threw: " & tPollErr & return after gGame["netLog"]
   end try
   -- an inbound rp1 event is attacker-controlled: a single throwing dispatch must
   -- drop-and-log (H4), never abort the drain or -- worse -- skip the re-arm below
   -- and silently kill the poll loop (deep-dive transport). The re-arm always runs.
   repeat for each element tEv in tEvents
      try
         heNetOnRp1 tEv
      catch tPollErr
         put "poll   dropped a throwing rp1 event: " & tPollErr & return after gGame["netLog"]
      end try
   end repeat
   try
      get btPoll(gGame["session"])
   catch tPollErr
      put "poll   btPoll threw: " & tPollErr & return after gGame["netLog"]
   end try
   send "heNetPollTick" to me in 250 milliseconds
end heNetPollTick

command heNetOnRp1 pEvA
   -- dispatch one drained rp1 event (an array with name/peer/payload/token)
   switch pEvA["name"]
      case "rp1Handshake"
         heNetOnHandshake pEvA["peer"], pEvA["token"]
         break
      case "rp1Message"
         heNetOnMessage pEvA["peer"], pEvA["payload"]
         break
   end switch
end heNetOnRp1

command heNetOnHandshake pPeer, pTokenData, pFromSeq
   -- admit-or-drop (spec 5): a peer whose token does not verify against this
   -- table is ignored, before any game message is accepted from it.
   -- pFromSeq (2e, optional): the peer's self-named applied seq from an
   -- onion hello -- honored as a TRIM HINT on a RECONNECT only (a first
   -- join always gets the full log; a rebuilt client's mark is 0 = full).
   local tPubHex, tRoleTxt, tIsNew, tOldPeer, tReconnect, tPeersA, tHostShort
   put heAdmitTokenVerify(pTokenData, gGame["tableIdHex"]) into tPubHex
   if tPubHex is empty then
      put "drop   handshake from an unadmitted peer" & return after gGame["netLog"]
      heLobbyRefresh
      exit heNetOnHandshake
   end if
   put heAdmitTokenRole(pTokenData) into tRoleTxt
   put (gGame["admittedA"][tPubHex] is not "true") into tIsNew
   -- a known key handshaking on a NEW peer handle is a reconnect: it needs the
   -- transcript replayed too, not just first-time joiners (spec 9)
   put gGame["peerByPub"][tPubHex] into tOldPeer
   put (tOldPeer is not empty and tOldPeer is not pPeer) into tReconnect
   -- on reconnect, drop the stale handle so peerPubA holds only live peers and
   -- heNetBroadcast never sends to a dead handle (deep-dive transport). Delete via
   -- a plain local array (the supported form; avoids a nested-subscript delete).
   if tReconnect then
      put gGame["peerPubA"] into tPeersA
      delete variable tPeersA[tOldPeer]
      put tPeersA into gGame["peerPubA"]
   end if
   put tPubHex into gGame["peerPubA"][pPeer]
   put pPeer into gGame["peerByPub"][tPubHex]
   put "true" into gGame["admittedA"][tPubHex]
   put tRoleTxt into gGame["roleByPub"][tPubHex]
   -- a verified handshake is positive presence: stamp it like an applied wire
   -- (v0.24.0, F7 -- heNetPubIsLive). This is what makes a RECONNECTING peer
   -- immediately seatable again after its last wire went stale.
   put the milliseconds into gGame["seenMsByPub"][tPubHex]
   -- adopt as host only a peer whose token DECLARES role "host" -- the phantom
   -- swarm connects players to each other too, so "first peer" is not the host.
   -- Trust-on-first-use: pin the first host key and surface (do NOT silently
   -- swap to) any later, DIFFERENT host-declaring key -- attributable, and the
   -- seam where a real invite<->host binding will reject it outright. Full host
   -- election / host loss is spec 9 / a later increment.
   if gGame["isHost"] is not "true" and tRoleTxt is "host" then
      if gGame["hostPubHex"] is empty then
         put tPubHex into gGame["hostPubHex"]
      else if gGame["hostPubHex"] is not tPubHex then
         -- copy the trusted host key out before chunking it (H6: never chunk an
         -- array element directly)
         put gGame["hostPubHex"] into tHostShort
         put "WARN   ignored a second host-declaring key " & char 1 to 12 of tPubHex \
               & " (already trust " & char 1 to 12 of tHostShort & ")" & return after gGame["netLog"]
      end if
   end if
   if tIsNew then
      put "+peer  " & char 1 to 12 of tPubHex & "  (" & tRoleTxt & ")" & return after gGame["netLog"]
   end if
   -- host: catch a peer up on the transcript (spec 9 replay) on first join
   -- OR reconnect, then re-sign and broadcast the roster so presence agrees.
   -- 2e: a reconnecting peer that named its applied seq (the onion hello's
   -- trailing item; a redial) gets the TRIMMED tail -- dedup keeps either
   -- replay idempotent, and a first join always replays in full.
   if gGame["isHost"] is "true" and (tIsNew or tReconnect) then
      if tReconnect and pFromSeq is a number and pFromSeq > 0 then
         heNetReplayLogTo pPeer, pFromSeq
      else
         heNetReplayLogTo pPeer
      end if
      if tIsNew then
         heHostEmitRoster
      end if
   end if
   heLobbyRefresh
end heNetOnHandshake

command heNetOnMessage pPeer, pPayloadData
   -- payload kinds (tab-framed): "c" = a player's signed content line to the
   -- host; "w" = a host-relayed sequenced wire to everyone. Verify-or-drop.
   local tPayload, tKind, tRest, tSaved, tPeerPub
   put textDecode(pPayloadData, "utf-8") into tPayload
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   put item 1 of tPayload into tKind
   put item 2 to -1 of tPayload into tRest
   set the itemDelimiter to tSaved
   switch tKind
      case "c"
         if gGame["isHost"] is "true" then
            heHostRelay pPeer, tRest
         end if
         break
      case "w"
         heNetIngestWire tRest
         break
      case "h"
         -- 2f: the onion-stream hello. rp1 carries the signed admission
         -- token in its transport handshake event; an onion stream has no
         -- such event, so the token rides the stream's first wire line and
         -- lands here (tRest is the whole token, tabs included).
         heNetOnionHello pPeer, tRest
         break
      case "r!"
         -- the host announces a catch-up replay up to head seq (the frame's
         -- payload, already split off as tRest): suspend react emissions
         -- until our applied seq reaches it (see heNetReplayLogTo). Honored
         -- only from the HOST's live handle -- an unsigned control frame from
         -- anyone else could otherwise suppress a victim's emissions
         -- indefinitely (transport DoS).
         put gGame["hostPubHex"] into tPeerPub
         if pPeer is gGame["peerByPub"][tPeerPub] and tRest is a number \
               and tRest > gGame["lastSeq"] then
            -- v0.24.0: a marker announcing a head we ALREADY hold is not a
            -- catch-up at all -- every wire that follows it is a duplicate we
            -- shed by seq, so nothing would ever fold to clear the mark. It
            -- used to suspend our react emissions until the next LIVE wire,
            -- and since the turn clock now records whether it started under a
            -- replay, it would also have marked that wire's turn replayed and
            -- waived one deadline check for nothing. Only a real gap suspends.
            put tRest into gGame["catchUpTo"]
            put "catch  replay to seq " & tRest & " announced" & return after gGame["netLog"]
         end if
         break
      case "s?"
         -- a peer asks us (the host) to replay the transcript so it can catch
         -- up from a chain gap (spec 9). Only honor it from an admitted,
         -- connected peer, so an unknown socket cannot trigger a replay.
         -- 2e: the frame may carry the requester's APPLIED SEQ (a bare "s?"
         -- is the pre-2e form and still gets the full log): the replay is
         -- then TRIMMED to the wires past it, so a mid-hand client resumes
         -- from its last applied wire -- at worst the last street ckpt
         -- boundary -- instead of shedding the whole chain from genesis.
         -- The mark is only a trim hint from an already-admitted peer: a
         -- lie forward just starves the liar (dedup makes a later full
         -- replay safe), a lie backward costs bytes, never correctness.
         put gGame["peerPubA"][pPeer] into tPeerPub
         if gGame["isHost"] is "true" and tPeerPub is not empty then
            -- rate-limit replays PER PEER: at most one per ~2s, so a flood of "s?"
            -- cannot amplify into unbounded full-transcript replays (deep-dive DoS).
            -- Keyed by the peer's pubkey (stable across handle churn), timed off the
            -- engine clock so no per-tick decrement is needed.
            if gGame["replayMsByPub"][tPeerPub] is not empty \
                  and (the milliseconds - gGame["replayMsByPub"][tPeerPub]) < 2000 then
               exit heNetOnMessage
            end if
            put the milliseconds into gGame["replayMsByPub"][tPeerPub]
            if tRest is not a number then
               put 0 into tRest
            end if
            put "sync!  replaying transcript to " & char 1 to 8 of tPeerPub \
                  & " (from seq " & tRest & ")" & return after gGame["netLog"]
            heNetReplayLogTo pPeer, tRest
            heLobbyRefresh
         end if
         break
   end switch
end heNetOnMessage

command heHostRelay pPeer, pContentAndSig
   -- host path: take a player's (contentLine TAB senderSig), assign seq + prev,
   -- countersign, advance the chain, and broadcast the sequenced wire to all.
   -- The content's own sender signature is checked before it is relayed.
   local tContent, tSenderSig, tSaved, tFromHex, tEnvLine, tHostSig, tWire, tTypeTxt
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   -- contentLine is items 1..6, senderSig is item 7 of pContentAndSig
   put item 1 to 6 of pContentAndSig into tContent
   put item 7 of pContentAndSig into tSenderSig
   put item 4 of tContent into tFromHex
   put item 5 of tContent into tTypeTxt
   set the itemDelimiter to tSaved
   -- a player packet is untrusted: reject malformed hex before decoding it
   -- (sxHex2Bin throws) so a corrupt "c" frame cannot kill the host relay (H4)
   if not heIsHex(tFromHex, 64) or not heIsHex(tSenderSig, 128) then
      exit heHostRelay
   end if
   -- host-authority: cfg/roster are host-authored presence; never sequence and
   -- relay them for a non-host sender, so an admitted player cannot forge table
   -- config or roster through the relay (deep-dive transport). The host emits
   -- these from its own key (heNetSendAction uses gGame["idPubHex"]).
   if (tTypeTxt is "cfg" or tTypeTxt is "roster") and tFromHex is not gGame["hostPubHex"] then
      exit heHostRelay
   end if
   -- verify the sender actually signed this content (host cannot forge content)
   if not heVerifyDetached(heHex2BinD(tSenderSig), textEncode(tContent, "utf-8"), heHex2BinD(tFromHex)) then
      exit heHostRelay
   end if
   if gGame["admittedA"][tFromHex] is not "true" then
      exit heHostRelay
   end if
   add 1 to gGame["seqCounter"]
   put tContent & tab & tSenderSig & tab & gGame["seqCounter"] & tab & gGame["chainHeadHex"] into tEnvLine
   put heBin2HexS(heSignDetachedD(textEncode(tEnvLine, "utf-8"), gGame["idSecData"])) into tHostSig
   put tEnvLine & tab & tHostSig into tWire
   heNetBroadcast "w" & tab & tWire
   heNetIngestWire tWire
end heHostRelay

command heNetIngestWire pWire
   -- everyone's inbound path. rp1 is lossy AND redelivers/reorders wires, so a
   -- verified wire is classified by its host-signed seq against the last we
   -- applied (gGame["lastSeq"]), NOT by a bare prev==head test:
   --   seq <= lastSeq     : already applied -> drop SILENTLY. This is the fix
   --                        for the networked chain-break storm -- the host
   --                        re-broadcasts and rp1 redelivers constantly, and
   --                        treating every duplicate as a "chain gap" made the
   --                        client resync-loop forever and the game never start.
   --                        It also makes the full-log replay idempotent: a
   --                        caught-up client just sheds the replayed prefix.
   --   seq  = lastSeq + 1 : the expected next wire -> chain-check + apply, then
   --                        drain any buffered successors now in order.
   --   seq  > lastSeq + 1 : a real gap -> buffer it and ask the host to replay.
   -- Signatures/shape are verified FIRST, and the table/version binding is
   -- enforced BEFORE the seq is even read (a wire for another table must never
   -- touch the buffer or lastSeq), so a duplicate/reordered wire is judged by
   -- its seq, never mistaken for a signature failure. Never raises (H4).
   local tVerdict, tA, tSeq
   if gGame["lastSeq"] is not a number then
      put 0 into gGame["lastSeq"]   -- unset on old saves / hand-rolled contexts
   end if
   if gGame["wireBufN"] is not a number then
      put 0 into gGame["wireBufN"]
   end if
   put heEnvVerify(pWire, empty, gGame["hostPubHex"], empty) into tVerdict
   if tVerdict is not "ok" then
      -- drop and log; a bad/forged message is a real rejection, never a resync
      put tVerdict && char 1 to 24 of pWire & return after gGame["netLog"]
      heLobbyRefresh
      exit heNetIngestWire
   end if
   put heEnvWireParse(pWire) into tA
   -- bind the envelope to THIS table and protocol version before folding it. Both
   -- fields sit inside the host-signed span, but a receiver still has to ENFORCE
   -- them: otherwise a host-signed wire for another table, or a downgraded envelope
   -- version, would be accepted onto our chain (deep-dive transport). A mismatch is
   -- a hard drop, NOT a chain gap, so it never triggers a resync.
   if tA["table"] is not gGame["tableIdHex"] then
      put "drop:wrong-table " & char 1 to 24 of pWire & return after gGame["netLog"]
      heLobbyRefresh
      exit heNetIngestWire
   end if
   if tA["v"] is not kHeEnvV then
      put "drop:bad-version " & char 1 to 24 of pWire & return after gGame["netLog"]
      heLobbyRefresh
      exit heNetIngestWire
   end if
   put tA["seq"] into tSeq
   if tSeq is not a number then
      put "drop:bad-seq " & char 1 to 24 of pWire & return after gGame["netLog"]
      heLobbyRefresh
      exit heNetIngestWire
   end if
   if tSeq <= gGame["lastSeq"] then
      exit heNetIngestWire   -- duplicate / already applied: drop, no resync loop
   end if
   if tSeq > gGame["lastSeq"] + 1 then
      heNetBufferWire tSeq, pWire
      put "gap    seq " & tSeq & " held (need " & (gGame["lastSeq"] + 1) & ")" \
            & return after gGame["netLog"]
      heNetRequestSync
      heLobbyRefresh
      exit heNetIngestWire
   end if
   -- tSeq is exactly lastSeq+1: it must chain onto our head, or the host's stream
   -- is inconsistent (should not happen) -- ask for a replay rather than wedge.
   if tA["prev"] is not gGame["chainHeadHex"] then
      put "drop:chain-break" && char 1 to 24 of pWire & return after gGame["netLog"]
      heNetRequestSync
      heLobbyRefresh
      exit heNetIngestWire
   end if
   heNetApplyWire pWire, tA
   heNetDrainBuffer
   heLobbyRefresh
end heNetIngestWire

command heNetApplyWire pWire, pA
   -- apply one verified, in-order wire: advance the chain head, record the seq,
   -- append to the transcript, and fold presence bodies into the display. pA is
   -- a parsed wire (heEnvWireParse); its fields are copied into plain locals
   -- first, so heEnvBodyText and the log lines chunk only plain text (H6-safe).
   local tTypeTxt, tSeqTxt, tFromHex, tBodyHex
   put pA["type"] into tTypeTxt
   put pA["seq"] into tSeqTxt
   put pA["from"] into tFromHex
   put pA["bodyHex"] into tBodyHex
   put heChainNextHex(pWire) into gGame["chainHeadHex"]
   put tSeqTxt into gGame["lastSeq"]
   -- every applied wire is host-countersigned: the relay is alive, so the
   -- spec 9 host-loss watchdog rewinds (heNetHostLossCheck) -- and a
   -- completed onion redial's attempt counter resets with it (2e: proof the
   -- host answered is a host-signed wire applying, nothing weaker)
   put 0 into gGame["hostQuietTicks"]
   if gGame["oxRedialN"] > 0 then
      put 0 into gGame["oxRedialN"]
   end if
   -- v0.24.0 (F7): stamp when we last had positive evidence of this sender.
   -- It is the only liveness rp1 can offer (it surfaces no disconnect event),
   -- and heNetPubIsLive reads it so the host never seats a departed peer as a
   -- ghost. Per KEY, not per handle: a reconnect changes the handle.
   put the milliseconds into gGame["seenMsByPub"][tFromHex]
   put pWire & return after gGame["log"]
   put "ok     " & tTypeTxt & " seq " & tSeqTxt & return after gGame["netLog"]
   -- spec 6: an unknown "from" is never ACTED on -- no exceptions, including
   -- via the host. The relay refuses unadmitted senders, so a sequenced wire
   -- whose sender is neither the host nor in the host-signed roster can only
   -- mean a malicious or corrupted host stream. The chain still advances (the
   -- link is host-authentic and refusing it would wedge the table), but the
   -- body is marked and NOTHING folds from it -- the same accept-the-link,
   -- ignore-the-body treatment a non-host cfg gets. In-order apply guarantees
   -- the roster wire admitting a sender lands before that sender's first
   -- relayed action, so an honest stream never trips this.
   if tFromHex is not gGame["hostPubHex"] and not heRosterHasKey(tFromHex) then
      put "note   unrostered sender " & char 1 to 8 of tFromHex \
            & " -- body ignored (seq " & tSeqTxt & ")" & return after gGame["netLog"]
      exit heNetApplyWire
   end if
   -- lobby presence bodies drive the roster/cfg display; gameplay wires drive
   -- the betting engine (the deal increment). roster/cfg are HOST-authored
   -- presence (spec 9): fold them only when the wire's own sender is the host,
   -- so an admitted player cannot forge table config/roster by getting a
   -- content line relayed (the host relays any admitted sender's content).
   if tTypeTxt is "roster" or tTypeTxt is "cfg" then
      if tFromHex is gGame["hostPubHex"] then
         if tTypeTxt is "roster" then
            put heEnvBodyText(tBodyHex) into gGame["rosterBody"]
         else
            put heEnvBodyText(tBodyHex) into gGame["cfgBody"]
            -- adopt the signed stakes so every client folds the same game
            -- (the host's own values are identical; this is a no-op there)
            put heNetCfgVal("sb", gGame["sb"]) into gGame["sb"]
            put heNetCfgVal("bb", gGame["bb"]) into gGame["bb"]
            put heNetCfgVal("ante", 0) into gGame["ante"]
            put heNetCfgVal("stack", kHeDefaultStack) into gGame["startStack"]
         end if
         heNetGameReact
      else
         put "drop   non-host " & tTypeTxt & " body ignored" & return after gGame["netLog"]
      end if
      exit heNetApplyWire
   end if
   -- the online game vocabulary folds through its own dispatcher (authority
   -- checks per type live there); everything else is future/unknown -- the
   -- chain carries it, nothing acts on it
   if tTypeTxt is "join" or tTypeTxt is "sit" or tTypeTxt is "handStart" \
         or tTypeTxt is "dealLevel" or tTypeTxt is "seedCommit" or tTypeTxt is "seedSeal" \
         or tTypeTxt is "holeDeliver" or tTypeTxt is "board" or tTypeTxt is "bidAnte" \
         or tTypeTxt is "bidSB" or tTypeTxt is "bidBB" or tTypeTxt is "act" \
         or tTypeTxt is "seedReveal" or tTypeTxt is "settle" or tTypeTxt is "receipt" \
         or tTypeTxt is "audit" or tTypeTxt is "ckpt" or tTypeTxt is "show" \
         or tTypeTxt is "muck" or tTypeTxt is "stand" then
      heNetFoldGameWire tTypeTxt, tFromHex, heEnvBodyText(tBodyHex), pA["hand"]
   end if
end heNetApplyWire

function heRosterHasKey pPubHex
   -- TRUE when the host-signed roster body (heRosterBody format: "pub:role"
   -- comma-items) lists pPubHex as a member. Membership is judged on the pub
   -- field alone; an empty roster has no members (the host itself is exempted
   -- at the call site, so the pre-roster cfg wire still folds).
   local tRoster, tItem, tColonPos, tPub
   set the itemDelimiter to comma
   put gGame["rosterBody"] into tRoster
   repeat for each item tItem in tRoster
      put offset(":", tItem) into tColonPos
      if tColonPos > 0 then
         put char 1 to (tColonPos - 1) of tItem into tPub
      else
         put tItem into tPub
      end if
      if tPub is pPubHex then
         return true
      end if
   end repeat
   return false
end heRosterHasKey

command heNetBufferWire pSeq, pWire
   -- hold an out-of-order future wire until the gap before it fills. Bounded: a
   -- wire more than kHeWireBufMax ahead of what we have applied is left to the
   -- full-log replay, so a flood of far-future seqs cannot grow the buffer.
   if pSeq <= gGame["lastSeq"] + kHeWireBufMax and gGame["wireBuf"][pSeq] is empty then
      put pWire into gGame["wireBuf"][pSeq]
      add 1 to gGame["wireBufN"]
   end if
end heNetBufferWire

command heNetDrainBuffer
   -- after applying a wire, apply any buffered wires that are now consecutive.
   -- Each is emptied as it is applied; when none remain (wireBufN back to 0) the
   -- whole buffer is reset so emptied keys never accumulate across a long game.
   -- Buffered wires were signature-verified and table/version-bound at ingest;
   -- the prev link is re-checked here because the head has moved since.
   local tNext, tWire, tA
   repeat forever
      put gGame["lastSeq"] + 1 into tNext
      if gGame["wireBuf"][tNext] is empty then
         exit repeat
      end if
      put gGame["wireBuf"][tNext] into tWire
      put empty into gGame["wireBuf"][tNext]
      subtract 1 from gGame["wireBufN"]
      put heEnvWireParse(tWire) into tA
      if tA["prev"] is not gGame["chainHeadHex"] then
         exit repeat   -- a buffered wire that no longer chains: leave it for replay
      end if
      heNetApplyWire tWire, tA
   end repeat
   if gGame["wireBufN"] <= 0 then
      put empty into gGame["wireBuf"]
      put 0 into gGame["wireBufN"]
   end if
end heNetDrainBuffer

command heNetSendAction pTypeTxt, pBodyTxt
   -- a player emits a signed content line to the host (or, if we are the host,
   -- straight into the relay). The host sequences and countersigns it.
   local tContent, tSenderSig, tPacket
   put heEnvContentLine(gGame["tableIdHex"], gGame["handNum"], gGame["idPubHex"], pTypeTxt, pBodyTxt) into tContent
   put heEnvSenderSigHex(tContent, gGame["idSecData"]) into tSenderSig
   put tContent & tab & tSenderSig into tPacket
   if gGame["isHost"] is "true" then
      heHostRelay 0, tPacket
   else
      heNetSendToHost "c" & tab & tPacket
   end if
end heNetSendAction

command heNetSendToHost pPayloadTxt
   local tHostPeer
   -- netsim capture seam: the loopback harness has no rp1, so outbound
   -- payloads are collected in gGame["netOutbox"] for the sim to shuttle by
   -- hand. Off (empty) in production; the real send path below is untouched.
   if gGame["netCap"] is "true" then
      put pPayloadTxt & return after gGame["netOutbox"]
      exit heNetSendToHost
   end if
   put gGame["peerByPub"][gGame["hostPubHex"]] into tHostPeer
   if tHostPeer is empty then
      exit heNetSendToHost
   end if
   heNetTxTo tHostPeer, pPayloadTxt
end heNetSendToHost

command heNetRequestSync
   -- recover from a chain gap: ask the host to replay the transcript (spec 9)
   -- instead of wedging on drop:chain-break forever. Debounced by a tick
   -- cooldown so a burst of dropped wires -- or a lost request -- re-asks at
   -- most once every ~2 s, never floods the host. The host never self-syncs.
   if gGame["isHost"] is "true" then
      exit heNetRequestSync
   end if
   if gGame["syncCooldown"] > 0 then
      exit heNetRequestSync
   end if
   if gGame["hostPubHex"] is empty then
      exit heNetRequestSync
   end if
   put 8 into gGame["syncCooldown"]
   put "sync?  requested transcript replay (chain gap)" & return after gGame["netLog"]
   -- 2e: name our applied seq so the host can trim the replay to the tail
   -- we are actually missing (spec 9 "since your last ckpt", keyed by seq)
   heNetSendToHost "s?" & tab & gGame["lastSeq"]
end heNetRequestSync

command heNetBroadcast pPayloadTxt
   -- host sends to every admitted peer (star topology, spec 4). The netCap
   -- capture stays HERE (one captured copy per broadcast, not one per peer)
   -- so the loopback harnesses see exactly the frames they always did.
   local tPeer
   if gGame["netCap"] is "true" then
      put pPayloadTxt & return after gGame["netOutbox"]
      exit heNetBroadcast
   end if
   repeat for each key tPeer in gGame["peerPubA"]
      heNetTxTo tPeer, pPayloadTxt
   end repeat
end heNetBroadcast

command heNetSendWireTo pPeer, pWire
   -- targeted replay of one sequenced wire to a single peer (star topology).
   -- Same "w" framing as a broadcast so the receiver's heNetOnMessage path is
   -- identical whether the wire arrived live or as catch-up.
   if gGame["netCap"] is "true" then
      put "w" & tab & pWire & return after gGame["netOutbox"]
      exit heNetSendWireTo
   end if
   heNetTxTo pPeer, "w" & tab & pWire
end heNetSendWireTo

command heNetReplayLogTo pPeer, pFromSeq
   -- spec 9 reconnect seam: replay the signed wire log to a peer, in order,
   -- so it advances its chain and catches up. Turn-rate, not frame-rate; a
   -- lobby log is a few lines.
   -- The replay is PREFIXED with an "r!" catch-up marker carrying our head
   -- seq: the client suspends its react emissions until its applied seq
   -- reaches the mark, THEN reacts once against the complete transcript --
   -- without this, react fired after every replayed wire against a chain
   -- state that predates the client's own historical messages, re-emitting
   -- join/commit/seal/reveal for every hand replayed and polluting the live
   -- chain with host-sequenced duplicates (Codex review on PR #39). A lost
   -- marker degrades to the old noisy behavior; it can never wedge.
   -- 2e: pFromSeq (empty = 0 = everything) trims the replay to the wires
   -- PAST the requester's applied seq -- the resume-from-the-last-street
   -- half of the street-ckpt work. A reconnect handshake still replays in
   -- full (a rebuilt client has nothing); dedup keeps either idempotent.
   local tWireLine, tLog, tFromSeq, tSeqTxt, tSaved
   put pFromSeq into tFromSeq
   if tFromSeq is not a number then
      put 0 into tFromSeq
   end if
   if gGame["netCap"] is "true" then
      put "r!" & tab & gGame["lastSeq"] & return after gGame["netOutbox"]
   else
      heNetTxTo pPeer, "r!" & tab & gGame["lastSeq"]
   end if
   put gGame["log"] into tLog
   put the itemDelimiter into tSaved
   repeat for each line tWireLine in tLog
      if tWireLine is empty then
         next repeat
      end if
      if tFromSeq > 0 then
         -- the host-assigned seq is wire field 8 (gotcha 5: set the
         -- delimiter at each use; restored below)
         set the itemDelimiter to tab
         put item 8 of tWireLine into tSeqTxt
         set the itemDelimiter to tSaved
         if tSeqTxt is a number and tSeqTxt <= tFromSeq then
            next repeat
         end if
      end if
      heNetSendWireTo pPeer, tWireLine
   end repeat
   set the itemDelimiter to tSaved
end heNetReplayLogTo

command heHostEmitRoster
   -- host-only: re-sign and broadcast the current roster whenever the admitted
   -- set changes (spec 9 presence). Every client sorts the members identically
   -- (heRosterBody), so the signed bytes match everywhere.
   local tKeyPub, tRoleTxt, tMembers
   if gGame["isHost"] is not "true" then
      exit heHostEmitRoster
   end if
   put empty into tMembers
   repeat for each key tKeyPub in gGame["admittedA"]
      put gGame["roleByPub"][tKeyPub] into tRoleTxt
      if tRoleTxt is empty then
         put "player" into tRoleTxt
      end if
      put tKeyPub & tab & tRoleTxt & return after tMembers
   end repeat
   if tMembers is not empty then
      delete char -1 of tMembers
   end if
   heNetSendAction "roster", heRosterBody(tMembers)
end heHostEmitRoster

--------------------------------------------------------------------------
-- spec 9 host election (the 2e liveness slice Phase 3 leans on). ORACLE
-- LOSS IS HOST LOSS BY CONSTRUCTION: the oracle occupies the host role
-- (relay, sequencer, dealer) and merely holds no seat, so one detection +
-- election path serves both -- exactly the plan's "handles oracle loss
-- identically to host loss". The election is DETERMINISTIC (lowest pubkey
-- among the live seated players) so every client names the same successor
-- with zero round trips; the oracle, never seated, is never electable.
-- What this build does NOT do is the LIVE handover (the elected host
-- re-hosting, peers re-joining its table) -- that is the Phase 3 exit
-- gate's territory. Today the successor is NAMED and the client fails
-- closed with the recovery spelled out (the nocloud discipline).
--------------------------------------------------------------------------

function heElectHostOf pPubsLines
   -- deterministic host election (spec 9): the LOWEST pubkey among the
   -- candidate lines (64-hex, one per line). A text sort over equal-length
   -- lowercase hex IS byte order, so this matches protocol-kat's
   -- elected_host (min over the same strings). Pure: values in, value out.
   local tLines, tLineTxt
   put pPubsLines into tLines
   sort lines of tLines
   repeat for each line tLineTxt in tLines
      if tLineTxt is not empty then
         return tLineTxt
      end if
   end repeat
   return empty
end heElectHostOf

function heNetElectablePubs
   -- election candidates: LIVE seated players still holding chips, EXCLUDING
   -- the (lost) host key. An oracle host was never seated, so oracle tables
   -- need no special case here.
   -- "live seated" is spec 9's own wording and it means NOT SITTING OUT: a
   -- sat-out seat is dealt out at every boundary and times out instantly, so
   -- electing it hands the table to the one key guaranteed not to re-host --
   -- and because every client elects the same successor, that is a
   -- DETERMINISTIC table death rather than a divergence anything could
   -- notice. This used to scan seatedList itself and never looked at
   -- sitOutBy; it rides heNetSeatedWithChipsList now (v0.24.0's F10 scan --
   -- the last stray copy of it), filtered exactly the way heNetNextOccList
   -- filters it, so "who is still in" has ONE definition with three readers.
   -- WHY THIS FILTER IS CONSENSUS-SAFE, which is the whole reason it can be
   -- applied here at all: sitOutBy is derived from the TRANSCRIPT alone --
   -- a signed stand wire, or heNetTimeoutMiss counting host-authored timeout
   -- wires every client folds identically -- so every client computes the
   -- same candidate set with zero round trips, which is the property the
   -- election exists for. heNetPubIsLive would NOT be safe here: it answers
   -- from per-client observation (our own transport handle, our own
   -- last-heard stamp), so two clients can legitimately disagree and name
   -- two different successors. Presence gates SEATING (heNetSeatLateJoiners);
   -- only transcript-derived facts may gate an election.
   local tOut, tSeatNum, tPub, tChipList
   set the itemDelimiter to comma
   put empty into tOut
   put heNetSeatedWithChipsList() into tChipList
   repeat for each item tSeatNum in tChipList
      if gGame["sitOutBy"][tSeatNum] is not "true" then
         put gGame["pubBySeat"][tSeatNum] into tPub
         if tPub is not empty and tPub is not gGame["hostPubHex"] then
            put tPub & return after tOut
         end if
      end if
   end repeat
   return tOut
end heNetElectablePubs

command heNetHostLossCheck
   -- the spec 9 liveness watchdog, one compare per poll tick when idle:
   -- during PLAY, a client that sees no host-countersigned wire for
   -- kHeHostLossTicks ticks declares the host lost. Wire-silence is the
   -- only honest signal on rp1 (no disconnect events surface here); the
   -- onion transport ALSO gets positive stream-death (heNetOnionDead
   -- routes into heNetHostLost directly). The host never self-elects; an
   -- idle lobby (gameOn false) is legitimately silent and never trips.
   if gGame["online"] is not "true" or gGame["isHost"] is "true" then
      exit heNetHostLossCheck
   end if
   if gGame["gameOn"] is not "true" or gGame["hostLost"] is "true" then
      exit heNetHostLossCheck
   end if
   if gGame["hostQuietTicks"] is not a number then
      put 0 into gGame["hostQuietTicks"]
   end if
   add 1 to gGame["hostQuietTicks"]
   if gGame["hostQuietTicks"] > kHeHostLossTicks then
      heNetHostLost "no host wire for " & (kHeHostLossTicks div 4) & " s"
   end if
end heNetHostLossCheck

command heNetHostLost pWhyTxt
   -- spec 9 host loss (and ORACLE loss -- same role, same path). VOID the
   -- in-flight hand: bets that never reached a verified settle never moved
   -- gGame["stacksBy"], so the stacks already stand at the last receipt --
   -- "resumes from the last receipt" costs nothing here. Then name the
   -- deterministic successor and fail closed: the live handover is the
   -- Phase 3 exit gate, not something to fake with a guess.
   local tElected, tMsgTxt
   if gGame["hostLost"] is "true" then
      exit heNetHostLost
   end if
   put "true" into gGame["hostLost"]
   put heElectHostOf(heNetElectablePubs()) into tElected
   put tElected into gGame["electedHostPubHex"]
   put "idle" into gGame["phase"]
   put empty into gGame["oDeal"]
   put "false" into gGame["gameOn"]
   heDisableActions
   if tElected is empty then
      put "HOST LOST (" & pWhyTxt & ") -- no live seated player to elect. The table is over; stacks stand at the last receipt." into tMsgTxt
   else if tElected is gGame["idPubHex"] then
      put "HOST LOST (" & pWhyTxt & ") -- the in-flight hand is void; stacks stand at the last receipt. YOU are the elected host (lowest live key): Create a table and share the new invite." into tMsgTxt
   else
      put "HOST LOST (" & pWhyTxt & ") -- the in-flight hand is void; stacks stand at the last receipt. Elected host: " & char 1 to 12 of tElected & " -- join its new invite when it re-hosts." into tMsgTxt
   end if
   put "elect  " & tMsgTxt & return after gGame["netLog"]
   heUISetStatus tMsgTxt
   heHudMark
   heLobbyRefresh
end heNetHostLost

--------------------------------------------------------------------------
-- Phase 2f: the ONION transport (spec 10). The same envelopes, the same
-- relay, the same fold -- only the bytes ride OnionXT streams instead of
-- rp1. Assume-running tor on the stock ports (SOCKS 9050, control 9051 --
-- OnionXT's defaults; Tor Browser alone exposes no control port); fail
-- CLOSED with a readable reason at every step (the nocloud pattern), never
-- a silent fallback to the DHT transport. All protocol work happens on the
-- poll tick (H2): the OnionXT callbacks at the bottom of this section only
-- STASH bytes and flags. Every ox* call sits in its own try with a declared
-- catch local (H8). Verified statically; NEEDS a two-machine live-tor pass.
--------------------------------------------------------------------------

command heNetTxTo pPeer, pPayloadTxt
   -- THE one live byte-out seam (2f): every payload that used to end in a
   -- hard-coded btRp1Send routes here by the table's transport. Same frames
   -- either way; over an onion stream each payload goes out as ONE
   -- LF-terminated wire line (LF framing is safe by construction: every
   -- free-text field is hex-encoded into the frame, so no payload can carry
   -- an LF). The netCap branch keeps direct callers -- the hello path --
   -- loopback-testable; the four senders capture before reaching here.
   local tTxErr, tTxRes
   if gGame["netCap"] is "true" then
      put pPayloadTxt & return after gGame["netOutbox"]
      exit heNetTxTo
   end if
   if gGame["transport"] is "onion" then
      try
         -- LF as an explicit byte value (the OnionXT oxCrlf discipline: the
         -- wire terminator never depends on how the engine defines a
         -- line constant)
         oxWrite pPeer, textEncode(pPayloadTxt & numToChar(10), "utf-8")
         put the result into tTxRes
         if tTxRes is not empty then
            put "drop   onion write failed (stream " & pPeer & "): " & tTxRes \
                  & return after gGame["netLog"]
         end if
      catch tTxErr
         put "drop   onion write threw: " & tTxErr & return after gGame["netLog"]
      end try
      exit heNetTxTo
   end if
   get btRp1Send(gGame["session"], pPeer, textEncode(pPayloadTxt, "utf-8"))
end heNetTxTo

command heNetOnionReset
   -- fresh transport state for a create/join. Deliberately does NOT touch
   -- the control connection (it survives between tables; gOxCtlUp).
   put empty into gGame["oxState"]
   put 0 into gGame["oxTicks"]
   put empty into gGame["oxBufA"]
   put empty into gGame["oxSeenA"]
   put empty into gGame["oxDeadList"]
   put empty into gGame["oxCtlErr"]
   put empty into gGame["oxDialErr"]
   put empty into gGame["oxDialOpen"]
   put empty into gGame["oxFailTxt"]
   put empty into gGame["oxService"]
   put empty into gGame["oxStream"]
   put empty into gGame["oxSeedHex"]
   put empty into gGame["onionAddrTxt"]
   put -1 into gGame["oxProgShown"]
   -- 2e auto-redial state (bounded; heNetOnionRedialArm owns the schedule)
   put 0 into gGame["oxRedialN"]
   put 0 into gGame["oxRedialWait"]
   put empty into gGame["oxRedialProbe"]
end heNetOnionReset

command heNetStartOnion
   -- bring the tor transport up: register the OnionXT callbacks, ensure a
   -- control connection, arm the poll tick. The rest of the bring-up (auth,
   -- bootstrap, publish/dial) is asynchronous and lives in heNetOnionTick's
   -- watchdogged states.
   local tErr, tRes, tAuthTxt
   if gGame["online"] is "true" then
      exit heNetStartOnion
   end if
   if not heHasOnion() then
      -- belt: heTableCreate/heTableJoin already refused; a direct caller
      -- still fails closed with the same story
      heUISetStatus "The carried OnionXT layer did not answer its probe (damaged embed - re-download, or run tools/sync-demo-embeds.py). Onion table unavailable; hotseat still works."
      exit heNetStartOnion
   end if
   try
      oxSetCallbackOwner the long id of this stack
      oxSetStatusCallback "heOnionStatus"
      oxSetPeerCallback "heOnionPeer"
   catch tErr
      heUISetStatus "OnionXT callback setup failed: " & heReadableErr(tErr)
      exit heNetStartOnion
   end try
   put "false" into tAuthTxt
   try
      if oxIsControlAuthenticated() then
         put "true" into tAuthTxt
      end if
   catch tErr
   end try
   if tAuthTxt is not "true" then
      try
         -- clear any half-open control socket from an earlier failed attempt
         -- (oxConnectControl refuses a second concurrent connect; disconnect
         -- is idempotent), then connect. Auth completes asynchronously; the
         -- "ctl" state below watches it.
         oxDisconnectControl
         oxConnectControl
         put the result into tRes
      catch tErr
         heUISetStatus "Tor control connect threw: " & heReadableErr(tErr) & "  Hotseat still works."
         exit heNetStartOnion
      end try
      if tRes is not empty then
         heUISetStatus "Tor control connect refused: " & tRes & "  Hotseat still works."
         exit heNetStartOnion
      end if
   end if
   put "true" into gOxCtlUp
   put "ctl" into gGame["oxState"]
   put 0 into gGame["oxTicks"]
   put "true" into gGame["online"]
   send "heNetPollTick" to me in 250 milliseconds
   heLobbyRefresh
end heNetStartOnion

command heNetOnionTick
   -- the onion transport's per-tick budget (H2: ALL protocol work on the
   -- poll timer; the callbacks only stash). Steady state costs one compare
   -- per concern; the bring-up walks ctl -> boot -> pub|dial -> ready, each
   -- state watchdogged so no silent async wait can hang forever.
   local tStateTxt, tErr, tProg, tOkTxt, tAddrTxt, tStreamState
   heNetOnionDead
   heNetOnionDrain
   put gGame["oxState"] into tStateTxt
   if tStateTxt is "ready" or tStateTxt is empty or tStateTxt is "failed" then
      exit heNetOnionTick
   end if
   add 1 to gGame["oxTicks"]
   switch tStateTxt
      case "ctl"
         put "false" into tOkTxt
         try
            if oxIsControlAuthenticated() then
               put "true" into tOkTxt
            end if
         catch tErr
            heNetOnionFail "OnionXT went away mid-connect: " & tErr
            exit heNetOnionTick
         end try
         if tOkTxt is "true" then
            put "boot" into gGame["oxState"]
            put 0 into gGame["oxTicks"]
            heLobbyRefresh
            exit heNetOnionTick
         end if
         if gGame["oxCtlErr"] is not empty then
            -- the status callback stashed tor's real reason: fail fast with
            -- it instead of waiting out the deadline
            heNetOnionFail "No tor daemon reachable on 127.0.0.1:9051 (" & gGame["oxCtlErr"] \
                  & "). Start tor with ControlPort 9051 and cookie or password auth, then Create/Join again."
            exit heNetOnionTick
         end if
         if gGame["oxTicks"] > kHeOnionCtlTicks then
            heNetOnionFail "Tor control connect timed out. Is a tor daemon running with its control port enabled (torrc: ControlPort 9051 + CookieAuthentication 1)? Tor Browser alone exposes no control port."
         end if
         break
      case "boot"
         put -1 into tProg
         try
            put oxBootstrapProgress() into tProg
         catch tErr
            heNetOnionFail "OnionXT went away mid-bootstrap: " & tErr
            exit heNetOnionTick
         end try
         if tProg is 100 then
            -- hand off: the host publishes its deterministic service, a
            -- player dials the invite's address
            if gGame["isHost"] is "true" then
               heNetOnionPublish
            else
               heNetOnionDial
            end if
            exit heNetOnionTick
         end if
         -- status repaints on CHANGE only (the <= 4 Hz discipline)
         if tProg is not gGame["oxProgShown"] then
            put tProg into gGame["oxProgShown"]
            heLobbyRefresh
         end if
         if gGame["oxTicks"] > kHeOnionBootTicks then
            heNetOnionFail "Tor never finished bootstrapping (stuck at " & tProg \
                  & "%). Check the daemon's network access, then Create/Join again."
         end if
         break
      case "pub"
         put "false" into tOkTxt
         try
            if oxServiceIsReady(gGame["oxService"]) then
               put "true" into tOkTxt
            end if
         catch tErr
            heNetOnionFail "OnionXT went away mid-publish: " & tErr
            exit heNetOnionTick
         end try
         if tOkTxt is "true" then
            -- belt: the PUBLISHED address must be the derived one the invite
            -- carries; a drift here would hand out an invite nobody can dial
            put empty into tAddrTxt
            try
               put oxServiceAddress(gGame["oxService"]) into tAddrTxt
            catch tErr
            end try
            if tAddrTxt is not empty and tAddrTxt is not gGame["onionAddrTxt"] then
               heNetOnionFail "published onion address does not match the invite (derivation drift: " \
                     & tAddrTxt & " vs " & gGame["onionAddrTxt"] & ")"
               exit heNetOnionTick
            end if
            put "ready" into gGame["oxState"]
            heLobbyRefresh
            heUISetStatus "Onion table live. Share this invite: " & heInviteTxt()
            exit heNetOnionTick
         end if
         if gGame["oxTicks"] > kHeOnionPubTicks then
            heNetOnionFail "Publishing the table's onion service timed out (descriptor never uploaded). Try again -- a freshly bootstrapped tor can take a minute more."
         end if
         break
      case "dial"
         if gGame["oxDialErr"] is not empty then
            heNetOnionDialFail "Could not reach the host's onion: " & gGame["oxDialErr"] \
                  & "  Is the host's table still open?"
            exit heNetOnionTick
         end if
         put empty into tStreamState
         try
            put oxStreamState(gGame["oxStream"]) into tStreamState
         catch tErr
            -- v0.24.0: this exit is inside the DIAL state, which a redial
            -- also passes through, so it takes the redial-aware handler like
            -- every other dial failure. Fail-closed here would cancel the
            -- poll tick and with it the election watchdog (see
            -- heNetOnionDialFail); a gone OnionXT just exhausts the four
            -- bounded attempts instead, and the election concludes.
            heNetOnionDialFail "OnionXT went away mid-dial: " & tErr
            exit heNetOnionTick
         end try
         if gGame["oxDialOpen"] is "open" or tStreamState is "connected" then
            -- introduce ourselves: the admission token that rides rp1's
            -- handshake event rides the stream's first wire line here.
            -- 2e: the frame carries our APPLIED SEQ as a trailing item --
            -- heAdmitTokenVerify reads items 1..3 only, so an old host
            -- ignores it (full replay, dedup-shed) while a 2e host TRIMS
            -- its reconnect replay to the wires past the mark ("since your
            -- last ckpt", spec 9). A fresh joiner's mark is 0 = everything.
            heNetTxTo gGame["oxStream"], "h" & tab & textDecode( \
                  heAdmitTokenData(gGame["tableIdHex"], gGame["idPubHex"], gGame["idSecData"], "player"), "utf-8") \
                  & tab & gGame["lastSeq"]
            put "ready" into gGame["oxState"]
            heLobbyRefresh
            heUISetStatus "Connected to the host's onion -- waiting for the table."
            exit heNetOnionTick
         end if
         if tStreamState is "unknown" then
            -- the stream failed and OnionXT already forgot the handle; the
            -- stashed oxDialErr usually carries why (checked above) -- this
            -- is the catch-all
            heNetOnionDialFail "The tor stream to the host closed during the dial. Check the invite and Join again."
            exit heNetOnionTick
         end if
         -- a redial attempt gets a SHORT dial deadline (the watchdog is 60 s
         -- away and a hung SOCKS dial must not eat the whole recovery window)
         if gGame["oxRedialN"] > 0 then
            if gGame["oxTicks"] > kHeRedialDialTicks then
               heNetOnionDialFail "the redial dial deadline passed"
            end if
            exit heNetOnionTick
         end if
         if gGame["oxTicks"] > kHeOnionDialTicks then
            heNetOnionDialFail "Dialing the host's onion timed out. The host may be offline, or its descriptor not yet published -- try again in a minute."
         end if
         break
      case "redial"
         -- 2e auto-redial (spec 9): waiting out the backoff before the next
         -- attempt. Every step gates on hostLost -- if the 60 s wire-silence
         -- watchdog concluded the election first, the redial stands down and
         -- the transport closes without clobbering the election's status.
         if gGame["hostLost"] is "true" then
            heNetOnionRedialGiveup
            exit heNetOnionTick
         end if
         subtract 1 from gGame["oxRedialWait"]
         if gGame["oxRedialWait"] > 0 then
            break
         end if
         put "redial attempt " & gGame["oxRedialN"] & " of " & kHeRedialMax \
               & " -- dialing the host's onion again" & return after gGame["netLog"]
         if gGame["netCap"] is "true" then
            -- loopback harness: the dial itself needs a tor daemon; record
            -- that the attempt fired so the sim can assert the schedule
            put gGame["oxRedialN"] into gGame["oxRedialProbe"]
            break
         end if
         put empty into gGame["oxDialErr"]
         put empty into gGame["oxDialOpen"]
         heNetOnionDial
         break
   end switch
end heNetOnionTick

command heNetOnionRedialArm
   -- schedule the NEXT redial attempt after a lost host stream (2e, spec 9):
   -- bounded attempts, doubling backoff, never past the election. The
   -- watchdog keeps counting the whole time (a dead stream delivers no
   -- wires), so "the redial must not race the election" is structural: the
   -- election concludes on schedule and every redial step defers to it.
   if gGame["hostLost"] is "true" then
      heNetOnionRedialGiveup
      exit heNetOnionRedialArm
   end if
   if gGame["oxRedialN"] >= kHeRedialMax then
      -- exhausted with the host still gone: run the election NOW (the
      -- pre-redial path did exactly this on stream death -- exhaustion is
      -- the same positive signal, just retried), then stand down QUIETLY
      -- behind it. The watchdog would conclude the same way; this just
      -- never leaves a dead table election-less when the backoffs run out
      -- first. Only the no-election exit (below) fails closed with a
      -- status message of its own -- there is nothing there to overwrite.
      put "redial gave up after " & kHeRedialMax & " attempts" & return after gGame["netLog"]
      if gGame["gameOn"] is "true" then
         heNetHostLost "the tor stream to the host stayed dead through " \
               & kHeRedialMax & " redials"
         -- v0.24.0: heNetHostLost has just NAMED the elected successor on the
         -- status line, and that is the one message the player needs. The old
         -- code called heNetOnionFail two lines later, whose heUISetStatus
         -- overwrote it -- exactly what heNetOnionRedialGiveup's comment says
         -- must never happen. BOTH exits from the redial state are quiet now
         -- (one shape, one handler); the fail-CLOSED spelling below is only
         -- for the exit where no election ran, so no status is being lost.
         heNetOnionStandDown "Tor: host stream lost -- " & kHeRedialMax \
               & " redials failed, election concluded (see the status line)"
         exit heNetOnionRedialArm
      end if
      heNetOnionFail "Lost the tor stream to the host and " & kHeRedialMax \
            & " redials failed. Join again with the same invite (if a host was elected, the net feed names it)."
      exit heNetOnionRedialArm
   end if
   add 1 to gGame["oxRedialN"]
   put heRedialWaitTicks(gGame["oxRedialN"]) into gGame["oxRedialWait"]
   put "redial" into gGame["oxState"]
   put 0 into gGame["oxTicks"]
   put "redial host stream lost -- attempt " & gGame["oxRedialN"] & " in " \
         & (gGame["oxRedialWait"] div 4) & " s" & return after gGame["netLog"]
   heLobbyRefresh
end heNetOnionRedialArm

command heNetOnionRedialGiveup
   -- the election concluded while we were redialing: stand down QUIETLY --
   -- heNetHostLost already named the successor on the status line, and a
   -- heNetOnionFail here would overwrite exactly the message the player
   -- needs. Tear the transport down (H1) and keep the tor line honest.
   put "redial stood down -- the election concluded first" & return after gGame["netLog"]
   heNetOnionStandDown "Tor: host stream lost -- election concluded (see the status line)"
end heNetOnionRedialGiveup

command heNetOnionStandDown pTorLineTxt
   -- the QUIET exit from the redial state (v0.24.0): tear the transport down
   -- (H1) and keep the tor line honest, but NEVER touch the status line.
   -- Both ways out of a redial -- the watchdog election concluding first
   -- (heNetOnionRedialGiveup) and the attempts running out
   -- (heNetOnionRedialArm's exhaustion branch) -- reach here only AFTER
   -- heNetHostLost has named the elected successor there, and the two used to
   -- disagree: the giveup path was quiet, the exhaustion path called
   -- heNetOnionFail and clobbered the election's message with "Hotseat still
   -- works". One handler, one behaviour: the player always ends up seeing who
   -- was elected. heNetOnionFail stays the fail-CLOSED spelling for the paths
   -- where no election ran (join time, an idle table).
   put "failed" into gGame["oxState"]
   put pTorLineTxt into gGame["oxFailTxt"]
   if gGame["netCap"] is not "true" then
      heNetStop
   end if
   heLobbyRefresh
end heNetOnionStandDown

command heNetOnionDialFail pWhyTxt
   -- a dial failure means two DIFFERENT things depending on where we are, and
   -- v0.23.0 served both with one handler -- the F1 defect. At JOIN time it is
   -- fatal and heNetOnionFail (fail closed, "Join again") is right. MID-REDIAL
   -- it is just this ATTEMPT failing, and heNetOnionFail would be catastrophic:
   -- it calls heNetStop, which sets gGame["online"] to "false" and cancels the
   -- pending heNetPollTick -- and heNetHostLossCheck exits on its FIRST line
   -- when online is not "true", so the 60 s election watchdog would never
   -- conclude and attempts 2..4 would never fire. The bounded 4-attempt
   -- schedule collapsed to one, and the table was left with no host and no
   -- successor -- against this member's written contract that the election
   -- always concludes. So a redial-time failure re-arms the schedule instead:
   -- heNetOnionRedialArm owns every decision from here (it stands down quietly
   -- when the election already concluded, and runs the election ITSELF at
   -- exhaustion), and the transport comes down only when something has decided
   -- the table is over. Verified statically; needs an OXT pass (+ live tor).
   --
   -- This is the ONLY spelling of that fork. The first cut of the fix left
   -- three dial-state sites testing oxRedialN inline beside this handler --
   -- correct, but four copies of one rule, which is the exact shape that
   -- produced F1: a later edit fixes the copy it can see. Every dial-state
   -- failure calls here now, so the join-vs-redial decision has one home.
   if gGame["oxRedialN"] > 0 then
      put "tor    redial attempt " & gGame["oxRedialN"] & " failed: " & pWhyTxt \
            & return after gGame["netLog"]
      heNetOnionRedialArm
      exit heNetOnionDialFail
   end if
   heNetOnionFail pWhyTxt
end heNetOnionDialFail

function heRedialWaitTicks pAttemptN
   -- the redial backoff, PURE (H5) so the harness pins the schedule: attempt
   -- N waits kHeRedialBaseTicks * 2^(N-1) poll ticks (8/16/32/64 = 2/4/8/16
   -- s). Integer doubling, never a bit operator (H7).
   local tTicks, tStep
   put kHeRedialBaseTicks into tTicks
   put 1 into tStep
   repeat while tStep < pAttemptN
      put tTicks * 2 into tTicks
      add 1 to tStep
   end repeat
   return tTicks
end heRedialWaitTicks

command heNetOnionPublish
   -- host, at bootstrap-done: publish the deterministic service. The
   -- address was derived and shown at create time; oxServiceIsReady (the
   -- "pub" state) gates "live".
   local tSvc, tErr
   try
      oxCreateServiceFromSeed heHex2BinD(gGame["oxSeedHex"]), kHeOnionVirtPort, kHeOnionLocalPort
      put the result into tSvc
   catch tErr
      heNetOnionFail "creating the onion service threw: " & heReadableErr(tErr)
      exit heNetOnionPublish
   end try
   if tSvc is not an integer then
      -- a bind failure on the local forward port, a control refusal, or a
      -- missing SodiumXT expansion -- OnionXT's result says which
      heNetOnionFail "could not publish the onion service: " & tSvc
      exit heNetOnionPublish
   end if
   put tSvc into gGame["oxService"]
   put "pub" into gGame["oxState"]
   put 0 into gGame["oxTicks"]
   heLobbyRefresh
end heNetOnionPublish

command heNetOnionDial
   -- player, at bootstrap-done: SOCKS-dial the invite's onion. Completes
   -- asynchronously; the "dial" state watches for open/failed. Every
   -- SYNCHRONOUS failure below goes through heNetOnionDialFail, never
   -- heNetOnionFail directly (v0.24.0): this handler is also the redial's
   -- dialer, and tearing the transport down mid-redial cancels the poll tick
   -- that the election watchdog rides on -- see heNetOnionDialFail.
   local tStream, tErr, tCbRes
   try
      oxDial gGame["onionAddrTxt"], kHeOnionVirtPort
      put the result into tStream
   catch tErr
      heNetOnionDialFail "dialing the host's onion threw: " & heReadableErr(tErr)
      exit heNetOnionDial
   end try
   if tStream is not an integer then
      heNetOnionDialFail "could not dial the host's onion: " & tStream
      exit heNetOnionDial
   end if
   put tStream into gGame["oxStream"]
   try
      oxSetStreamCallback tStream, "heOnionStreamEvt"
      put the result into tCbRes
   catch tErr
      put tErr into tCbRes
   end try
   if tCbRes is not empty then
      heNetOnionDialFail "could not register the stream callback: " & tCbRes
      exit heNetOnionDial
   end if
   put "dial" into gGame["oxState"]
   put 0 into gGame["oxTicks"]
   heLobbyRefresh
end heNetOnionDial

command heNetOnionHello pPeer, pTokenTxt
   -- the onion-transport handshake: the SAME signed admission token that
   -- rides rp1's handshake event arrives as the stream's first wire line
   -- (the "h" frame). Verify-or-drop BEFORE any reply: a stranger's dial
   -- earns nothing, not even the host's identity. On the host, a verified
   -- hello is answered with OUR hello -- the stream is ordered, so the
   -- joiner adopts the host key before the replayed wires reach it -- and
   -- then the shared handshake path runs (admission, replay, roster),
   -- identical to rp1's. 2e: the frame may carry the sender's APPLIED SEQ
   -- as a fourth tab item (the redial resync mark, pinned as
   -- hello_trim_frame in protocol-kat) -- heAdmitTokenVerify reads items
   -- 1..3 only, so the extension is compatible both ways; the mark trims
   -- the host's reconnect replay to the wires past it (spec 9 "since your
   -- last ckpt"; a lie only starves the liar, dedup keeps any replay safe).
   local tPubHex, tFromSeq, tSaved
   put heAdmitTokenVerify(textEncode(pTokenTxt, "utf-8"), gGame["tableIdHex"]) into tPubHex
   if tPubHex is empty then
      put "drop   onion hello failed verification (stream " & pPeer & ")" & return after gGame["netLog"]
      heNetOnionCloseStream pPeer
      heLobbyRefresh
      exit heNetOnionHello
   end if
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   put item 4 of pTokenTxt into tFromSeq
   set the itemDelimiter to tSaved
   if tFromSeq is not a number then
      put 0 into tFromSeq
   end if
   if gGame["isHost"] is "true" then
      heNetTxTo pPeer, "h" & tab & textDecode( \
            heAdmitTokenData(gGame["tableIdHex"], gGame["idPubHex"], gGame["idSecData"], "host"), "utf-8")
   end if
   heNetOnHandshake pPeer, textEncode(pTokenTxt, "utf-8"), tFromSeq
end heNetOnionHello

command heNetOnionCloseStream pStream
   -- fail one stream closed and forget its buffer. netCap-guarded so the
   -- loopback harness can drive the refusal path with no OnionXT loaded.
   local tErr, tBufA
   if gGame["netCap"] is not "true" then
      try
         oxCloseStream pStream
      catch tErr
      end try
   end if
   -- delete via a plain local copy (the heNetOnHandshake reconnect pattern),
   -- and only when there IS an array: deleting a key of a never-filled
   -- (empty, non-array) store is the kind of edge that throws on strict OXT
   put gGame["oxBufA"] into tBufA
   if tBufA is an array then
      delete variable tBufA[pStream]
      put tBufA into gGame["oxBufA"]
   end if
   put gGame["oxSeenA"] into tBufA
   if tBufA is an array then
      delete variable tBufA[pStream]
      put tBufA into gGame["oxSeenA"]
   end if
end heNetOnionCloseStream

command heNetOnionDrain
   -- reassemble LF-framed wire lines from the per-stream byte buffers the
   -- stream callback fills, and dispatch each through the SAME router the
   -- rp1 events take (heNetOnMessage). Chunking is on a plain local copy of
   -- each element (H6), written back after.
   local tKeysTxt, tKey, tBuf, tNL, tLine, tDispErr
   if gGame["oxBufA"] is not an array then
      exit heNetOnionDrain
   end if
   put the keys of gGame["oxBufA"] into tKeysTxt
   repeat for each line tKey in tKeysTxt
      put gGame["oxBufA"][tKey] into tBuf
      if tBuf is empty then
         next repeat
      end if
      -- a peer streaming bytes with no line break is not speaking this
      -- protocol: fail the stream closed rather than grow forever (bounded,
      -- like the reorder buffer)
      if the number of chars of tBuf > kHeOnionBufMax then
         put "drop   oversized unframed buffer from stream " & tKey & return after gGame["netLog"]
         heNetOnionCloseStream tKey
         next repeat
      end if
      repeat forever
         put offset(numToChar(10), tBuf) into tNL
         if tNL is 0 then
            exit repeat
         end if
         put char 1 to (tNL - 1) of tBuf into tLine
         delete char 1 to tNL of tBuf
         if tLine is not empty then
            -- an inbound frame is attacker-controlled: one throwing dispatch
            -- drops-and-logs (H4), never aborts the drain
            try
               heNetOnMessage tKey, textEncode(tLine, "utf-8")
            catch tDispErr
               put "poll   dropped a throwing onion frame: " & tDispErr & return after gGame["netLog"]
            end try
         end if
      end repeat
      -- write the remainder back ONLY if the stream survived its own frames:
      -- a refused hello closes the stream mid-drain, and an unconditional
      -- write-back would resurrect the deleted buffer key as an orphan
      if tKey is among the keys of gGame["oxBufA"] then
         put tBuf into gGame["oxBufA"][tKey]
      end if
   end repeat
end heNetOnionDrain

command heNetOnionDead
   -- process stream deaths the callback recorded (poll-tick work, H2): drop
   -- the peer mappings; a PLAYER losing its host stream is offline -- 2e's
   -- liveness pass owes auto-reconnect, so today the honest answer is a
   -- fail-closed message naming the Join-again recovery.
   local tDead, tLine, tPub, tPeersA
   put gGame["oxDeadList"] into tDead
   if tDead is empty then
      exit heNetOnionDead
   end if
   put empty into gGame["oxDeadList"]
   repeat for each line tLine in tDead
      if tLine is empty then
         next repeat
      end if
      put gGame["peerPubA"][tLine] into tPub
      if tPub is not empty then
         put gGame["peerPubA"] into tPeersA
         delete variable tPeersA[tLine]
         put tPeersA into gGame["peerPubA"]
         if gGame["peerByPub"][tPub] is tLine then
            put empty into gGame["peerByPub"][tPub]
         end if
         put "-peer  " & char 1 to 12 of tPub & "  (stream closed)" & return after gGame["netLog"]
      end if
      heNetOnionCloseStream tLine
      if gGame["isHost"] is not "true" and tLine is gGame["oxStream"] then
         -- onion gives POSITIVE stream-death. 2e (v0.23.0): during play this
         -- now arms the bounded AUTO-REDIAL first -- the host's onion address
         -- is deterministic (spec 9: a restarted host keeps it), so redialing
         -- the same invite is exactly the recovery -- while the 60 s
         -- wire-silence watchdog keeps counting underneath; if the watchdog
         -- concludes first, the election proceeds and the redial stands down
         -- (heNetOnionRedialArm/heNetOnionTick gate on hostLost). Oracle
         -- tables take exactly this path too -- the oracle IS the host role.
         -- Outside play there is no hand to save: fail closed as before.
         if gGame["gameOn"] is "true" and gGame["hostLost"] is not "true" then
            put empty into gGame["oxStream"]
            heNetOnionRedialArm
            exit heNetOnionDead
         end if
         heNetOnionFail "Lost the tor stream to the host. Join again with the same invite to reconnect (if a host was elected, the net feed names it)."
         exit heNetOnionDead
      end if
   end repeat
   heLobbyRefresh
end heNetOnionDead

command heNetOnionFail pWhyTxt
   -- fail CLOSED with a readable reason (the nocloud pattern): tear the
   -- transport down, keep the reason on the tor line, never fall back to
   -- another transport silently.
   put "failed" into gGame["oxState"]
   put "Tor: FAILED -- " & pWhyTxt into gGame["oxFailTxt"]
   put "tor    " & pWhyTxt & return after gGame["netLog"]
   heNetStop
   heUISetStatus pWhyTxt & "  Hotseat still works."
   heLobbyRefresh
end heNetOnionFail

function heNetOnionStatusTxt
   -- the lobby's tor status line: the quickshare-pill states in holde-em
   -- spelling. Empty when the DHT transport is selected and no onion state
   -- lingers, so the line vanishes rather than nagging.
   local tStateTxt, tProg, tErr
   if gGame["transport"] is not "onion" \
         and not (gCfg["transport"] is "onion" and gGame["online"] is not "true") then
      return empty
   end if
   put gGame["oxState"] into tStateTxt
   if tStateTxt is "failed" then
      return gGame["oxFailTxt"]
   end if
   if not heHasOnion() then
      return "Tor: the carried OnionXT layer did not answer (damaged embed)"
   end if
   switch tStateTxt
      case "ctl"
         return "Tor: connecting to the control port (9051)..."
      case "boot"
         put 0 into tProg
         try
            put oxBootstrapProgress() into tProg
         catch tErr
         end try
         return "Tor: bootstrapping " & tProg & "%..."
      case "pub"
         return "Tor: publishing the table's onion address..."
      case "dial"
         return "Tor: connecting to the host's onion..."
      case "redial"
         return "Tor: host stream lost -- redial attempt " & gGame["oxRedialN"] \
               & " of " & kHeRedialMax & "..."
      case "ready"
         return "Tor: ready"
   end switch
   return "Tor: idle -- Create hosts an onion table; Join takes a 64hex@...onion invite"
end heNetOnionStatusTxt

on heOnionStatus pKind, pInfo
   -- OnionXT status callback: STASH only -- every reaction happens on the
   -- poll tick (H2). The control-error stash lets the "ctl" state fail fast
   -- with tor's real reason instead of waiting out the deadline.
   if gGame["transport"] is not "onion" then
      exit heOnionStatus
   end if
   if pKind is "control" and pInfo begins with "error" then
      put pInfo into gGame["oxCtlErr"]
   end if
end heOnionStatus

on heOnionPeer pStream, pService, pPeerHost
   -- a peer connected to our onion service (host side). Register the stream
   -- callback NOW -- OnionXT's dispatch is synchronous and it arms the
   -- first read right after this returns -- and note the stream so teardown
   -- can close it (H1) even if its hello never verifies. The peer stays a
   -- stranger until that hello does (heNetOnionHello).
   local tCbErr
   if gGame["online"] is not "true" or gGame["transport"] is not "onion" then
      exit heOnionPeer
   end if
   try
      oxSetStreamCallback pStream, "heOnionStreamEvt"
   catch tCbErr
      exit heOnionPeer
   end try
   put "true" into gGame["oxSeenA"][pStream]
end heOnionPeer

on heOnionStreamEvt pStream, pEvent, pData
   -- per-stream OnionXT events: STASH bytes and flags only; the poll tick
   -- does the protocol work (H2). pData is engine-socket Data -- decoded at
   -- this edge (payloads are ASCII by construction, hex-framed fields, so a
   -- chunk boundary can never split a multi-byte character). For "error"
   -- events pData is OnionXT's error TEXT.
   local tTxt
   if gGame["transport"] is not "onion" then
      exit heOnionStreamEvt
   end if
   switch pEvent
      case "data"
         put textDecode(pData, "utf-8") into tTxt
         put tTxt after gGame["oxBufA"][pStream]
         break
      case "open"
         if pStream is gGame["oxStream"] then
            put "open" into gGame["oxDialOpen"]
         end if
         break
      case "error"
         if pStream is gGame["oxStream"] then
            put pData into gGame["oxDialErr"]
         end if
         put pStream & return after gGame["oxDeadList"]
         break
      case "closed"
         put pStream & return after gGame["oxDeadList"]
         break
   end switch
end heOnionStreamEvt

--------------------------------------------------------------------------
-- the ONLINE game (Phase 2d): Level 0 play over the signed wire chain.
-- Every client folds the same wires into the same gGame["state"] the hotseat
-- UI already renders, and heNetGameReact then emits ONLY what OUR seat owes
-- next (a commit, a seal, a blind, a board if we deal this hand...). Every
-- emission is debounced by a per-hand sent-flag, so rp1 redelivery and the
-- catch-up replay can never double-send. None of the hotseat pacing timers
-- run online -- the network's turn-rate IS the pacing (spec 11).
-- Deal (spec 7.1, Level 0): dealer = the button seat. seedCommit from every
-- dealt seat -> seedSeal (the seed sealed to the dealer's session box pub,
-- kept ON the chain so the transcript stays self-contained) -> the dealer
-- derives the committed deck and emits sealed holeDeliver per seat -> blinds
-- and betting as self-signed wires through the SAME pure engine -> dealer
-- board wires -> at hand end every seat emits seedReveal, every client
-- re-derives deck/holes/ranks from the REVEALED seeds (nobody can lie about
-- a showdown), the host emits settle (verified by every client against its
-- own heSettleOf before folding), then receipt co-signatures (spec 8.3,
-- chained hand to hand) and per-client audit verdicts (spec 7.1 step 5).
--------------------------------------------------------------------------

command heNetGameInit
   -- reset the online-game store (heTableCreate/heTableJoin + netsim contexts).
   -- stacksBy is cleared deliberately: the parked hotseat table leaves its own
   -- stack numbers behind, and the sit fold seeds a seat's stack only when the
   -- slot is EMPTY -- online stacks must come from the signed cfg, never from
   -- a leftover hotseat game (Leave rebuilds the hotseat table anyway).
   put empty into gGame["boxByPub"]
   put empty into gGame["seatByPub"]
   put empty into gGame["pubBySeat"]
   put empty into gGame["seatedList"]
   put empty into gGame["stacksBy"]
   put 0 into gGame["lastBB"]
   put "false" into gGame["joinSent"]
   put "false" into gGame["gameOn"]
   put "true" into gGame["autoNext"]
   put empty into gGame["catchUpTo"]
   put kHeGenesisPrev into gGame["rcptHeadHex"]
   put empty into gGame["oDeal"]
   -- spec 9 host-loss election state (2e/Phase 3)
   put "false" into gGame["hostLost"]
   put 0 into gGame["hostQuietTicks"]
   put empty into gGame["electedHostPubHex"]
   -- 2e liveness: sit-out + consecutive-miss state (game-scoped; the
   -- per-hand bank lives under oDeal) and the act-timer's turn mark
   put empty into gGame["sitOutBy"]
   put empty into gGame["missCntBy"]
   put empty into gGame["turnKey"]
   put 0 into gGame["turnStartMs"]
   put "false" into gGame["timeoutSent"]
   put "false" into gGame["turnStale"]
   put empty into gGame["turnClockTxt"]
   -- v0.24.0: the engine-fold outcome the timeout/act folds read back
   -- (heNetEngineFold), and the "table parked for sit-outs" latch that makes
   -- the between-hands beat re-armable from any path (heNetHandKick)
   put "false" into gGame["foldApplied"]
   put "false" into gGame["handWait"]
   put empty into gGame["seenMsByPub"]
end heNetGameInit

command heNetHandReset
   -- per-hand deal store; runs when a handStart wire folds. Sent-flags are the
   -- redelivery/replay debounce for every emission this hand.
   put empty into gGame["oDeal"]
   put "false" into gGame["oDeal"]["commitSent"]
   put "false" into gGame["oDeal"]["sealSent"]
   put "false" into gGame["oDeal"]["holesSent"]
   put "false" into gGame["oDeal"]["anteSent"]
   put "false" into gGame["oDeal"]["sbSent"]
   put "false" into gGame["oDeal"]["bbSent"]
   put "false" into gGame["oDeal"]["revealSent"]
   put "false" into gGame["oDeal"]["settleSent"]
   put "false" into gGame["oDeal"]["receiptSent"]
   put "false" into gGame["oDeal"]["auditSent"]
   put "false" into gGame["oDeal"]["settleDone"]
   put "false" into gGame["oDeal"]["nextArmed"]
   put 0 into gGame["oDeal"]["commitN"]
   put 0 into gGame["oDeal"]["sealN"]
   put 0 into gGame["oDeal"]["holeN"]
   put 0 into gGame["oDeal"]["revealN"]
   put 0 into gGame["oDeal"]["receiptN"]
   put 0 into gGame["oDeal"]["dealerSeat"]
   put 0 into gGame["oDeal"]["dealCount"]
   put empty into gGame["oDeal"]["boardList"]
   put empty into gGame["oDeal"]["myHoles"]
   put empty into gGame["oDeal"]["mySeedHex"]
   -- 2e liveness: ONE time-bank per hand per seat (spec 8.1); the act
   -- timer's turn mark resets with the hand
   put empty into gGame["oDeal"]["bankUsedBy"]
   put empty into gGame["turnKey"]
   put 0 into gGame["turnStartMs"]
   put "false" into gGame["timeoutSent"]
   put "false" into gGame["turnStale"]
   put empty into gGame["turnClockTxt"]
end heNetHandReset

function heNetMySeat
   local tSeat
   put gGame["seatByPub"][gGame["idPubHex"]] into tSeat
   if tSeat is not a number then
      return 0
   end if
   return tSeat
end heNetMySeat

function heNetSeatPos pSeatNum
   -- a seat's CONTRIBUTOR position = its 1-based index in the hand's ascending
   -- occupied-seat list (sparse seats pack down to 1..count; the seed XOR and
   -- commit arrays are position-indexed, spec 7.1)
   local tOccList, tPos, tSeatNum
   set the itemDelimiter to comma
   put gGame["state"]["occ"] into tOccList
   put 0 into tPos
   repeat for each item tSeatNum in tOccList
      add 1 to tPos
      if tSeatNum is pSeatNum then
         return tPos
      end if
   end repeat
   return 0
end heNetSeatPos

function heNetSeatAtPos pPos
   local tOccList
   set the itemDelimiter to comma
   put gGame["state"]["occ"] into tOccList
   return item pPos of tOccList
end heNetSeatAtPos

--------------------------------------------------------------------------
-- Phase 3 (spec 7.2) seams: WHO deals, and WHO contributes shuffle
-- entropy. At Level 0 the dealer is the button seat; at Level 1 the dealer
-- is the ORACLE -- the host role with no seat -- named on the dealLevel
-- wire as level=1, dealer=0. The oracle contributes its own committed seed
-- at position dealCount+1 (players' entropy still commits the shuffle; the
-- oracle's seed was committed before it saw anyone's, so it cannot stack
-- -- and it holds no cards, so what it sees has no stake behind it).
--------------------------------------------------------------------------

function heNetOracleDeal
   -- TRUE when the folded dealLevel named the oracle as this hand's dealer
   return (gGame["oDeal"]["oracleDeal"] is "true")
end heNetOracleDeal

function heNetDealerPubHex
   -- the key that deals THIS hand: the oracle (host) at Level 1, the
   -- button seat's key at Level 0
   if heNetOracleDeal() then
      return gGame["hostPubHex"]
   end if
   return gGame["pubBySeat"][gGame["oDeal"]["dealerSeat"]]
end heNetDealerPubHex

function heNetWeDeal
   -- do WE run the dealer side of this hand?
   local tSeat
   if heNetOracleDeal() then
      return (gGame["isHost"] is "true")
   end if
   put heNetMySeat() into tSeat
   return (tSeat > 0 and tSeat is gGame["oDeal"]["dealerSeat"])
end heNetWeDeal

function heNetContribCount
   -- how many positions contribute commit/seal/reveal entropy this hand:
   -- every dealt seat, plus the oracle's extra position at Level 1
   local tCount
   put gGame["oDeal"]["dealCount"] into tCount
   if tCount is not a number then
      return 0
   end if
   if heNetOracleDeal() then
      return tCount + 1
   end if
   return tCount
end heNetContribCount

function heNetMyContribPos
   -- OUR contributor position: a seat's packed position; the dealing oracle
   -- takes dealCount+1; everyone else (a spectator, a pre-sit joiner) is 0
   local tSeat, tCount
   put heNetMySeat() into tSeat
   if tSeat > 0 then
      return heNetSeatPos(tSeat)
   end if
   if heNetOracleDeal() and gGame["isHost"] is "true" then
      put gGame["oDeal"]["dealCount"] into tCount
      if tCount is a number and tCount > 0 then
         return tCount + 1
      end if
   end if
   return 0
end heNetMyContribPos

function heNetContribPosOk pPos, pFromSeat, pFromHex
   -- a wire's contributor-position claim is trusted only when its SENDER
   -- owns the position: seats own their packed positions (seatByPub is the
   -- authority, never the body); the oracle -- the host key, dealing at
   -- Level 1 with no seat -- owns exactly position dealCount+1.
   local tCount
   if pPos is not a number then
      return false
   end if
   if pFromSeat > 0 then
      return (heNetSeatAtPos(pPos) is pFromSeat)
   end if
   if heNetOracleDeal() and pFromHex is gGame["hostPubHex"] then
      put gGame["oDeal"]["dealCount"] into tCount
      if tCount is a number and pPos is (tCount + 1) then
         return true
      end if
   end if
   return false
end heNetContribPosOk

--------------------------------------------------------------------------
-- 2e liveness (spec 8.1/9): act timers + the per-hand time-bank, sit-out,
-- and the host-authored TIMEOUT wires. The design in one paragraph: the
-- deadline needs no wire of its own -- the SIGNED cfg carries the timer
-- lengths (spec 6 message zero) and the turn-opening wire (already
-- host-countersigned, already in the street's flow) starts every client's
-- countdown identically -- so the only new wire surface is the timeout
-- itself: the EXISTING act/bid wire with seat=/timeout=/bank= marks,
-- authored by the HOST (the table's clock authority), verified by every
-- client (right verb, right amount, deadline genuinely passed on ITS OWN
-- clock within kHeActSkewSecs) and folded as the named seat's action --
-- so the transcript stays deterministic and replayable. The time-bank
-- auto-arms on the seat's FIRST would-be timeout each hand (a request
-- wire would race the timeout on a lossy transport) and its spend rides
-- the wire (bank=1), so bank state is transcript-derived consensus.
-- Sitting-out seats (a signed "stand", or kHeDefaultMisses consecutive
-- timeouts) time out INSTANTLY mid-hand and are dealt out at the next
-- hand boundary; a signed "sit" (seat only, no pub) re-enters next hand.
--------------------------------------------------------------------------

function heTimeoutVerbOf pStateA, pSeatNum
   -- the spec 9 expiry prescription, PURE (H5): check when the seat owes
   -- nothing this street, fold otherwise. Every client re-derives this and
   -- refuses a host timeout naming any other verb (a host may never fold a
   -- seat that could check).
   local tOwe
   put pStateA["betCur"] - pStateA["streetBy"][pSeatNum] into tOwe
   if tOwe > 0 then
      return "fold"
   end if
   return "check"
end heTimeoutVerbOf

function heTimeoutPostOf pStateA
   -- the pending FORCED post in the blinds phase, PURE (H5): antes first
   -- (lowest unposted occupied seat -- deterministic), then the SB, then
   -- the BB, each at exactly the amount the engine will accept
   -- (min(due, stack) -- heBetApply's own rule). Empty when nothing is
   -- owed or the phase is not blinds. This is what lets the host unwedge
   -- a hand whose seat went dark BEFORE its blind posted: the timeout bid
   -- posts it (spec 9's "auto ... posts" for a sitting-out seat).
   local tOccList, tSeatNum
   if pStateA["phase"] is not "blinds" then
      return empty
   end if
   set the itemDelimiter to comma
   if pStateA["ante"] > 0 then
      put pStateA["occ"] into tOccList
      repeat for each item tSeatNum in tOccList
         if pStateA["antePostedBy"][tSeatNum] is not "true" then
            return "bidAnte" & comma & tSeatNum & comma \
                  & min(pStateA["ante"], pStateA["stackBy"][tSeatNum])
         end if
      end repeat
   end if
   if pStateA["sbPosted"] is not "true" then
      return "bidSB" & comma & pStateA["sbSeat"] & comma \
            & min(pStateA["sb"], pStateA["stackBy"][pStateA["sbSeat"]])
   end if
   return "bidBB" & comma & pStateA["bbSeat"] & comma \
         & min(pStateA["bb"], pStateA["stackBy"][pStateA["bbSeat"]])
end heTimeoutPostOf

command heNetTurnMark
   -- (re)aim the act timer at whoever the folded engine state says is due:
   -- the acting seat, or -- once the deal is complete -- the next forced
   -- post in the blinds phase. Called after every fold that can move the
   -- action; the clock restarts only when the SUBJECT changes, so a
   -- redelivered wire never extends a deadline. All clients run this off
   -- the same wires, so every clock starts at the same wire (transport
   -- jitter apart -- kHeActSkewSecs is the tolerance).
   local tStateA, tKeyTxt, tPostTxt
   put gGame["state"] into tStateA
   put empty into tKeyTxt
   if tStateA["phase"] is "acting" and tStateA["toAct"] > 0 then
      -- v0.24.3, FOUND BY THE SECOND ENGINE RUN: the key carries the HAND
      -- AND STREET, because "the clock restarts only when the SUBJECT
      -- changes" was comparing a key that could not tell one street's turn
      -- from the next. heBetApply advances the street SYNCHRONOUSLY at the
      -- closing act, so when the seat that timed out closing a street is
      -- also first to act on the new one (heads-up postflop, exactly the
      -- sat-out seat's shape), the mark re-derived the identical
      -- "act,seat,0" key, kept the stale clock AND the stale timeoutSent
      -- latch, and the host could never emit the next timeout: the table
      -- stalled with hand 2 unsettled on every client. Items 1..3 keep
      -- their meaning (the tick parses only those); item 4 is purely the
      -- restart discriminator. turnKey never crosses the wire and every
      -- client derives it from the same folds, so this is not a consensus
      -- change. Mid-turn non-action folds (a ckpt) still re-derive the
      -- SAME key -- same hand, same street, same seat -- so a redelivered
      -- or interleaved wire still never extends a deadline.
      put "act" & comma & tStateA["toAct"] & comma & 0 & comma \
            & gGame["handNum"] & "-" & tStateA["street"] into tKeyTxt
   else if tStateA["phase"] is "blinds" \
         and gGame["oDeal"]["dealCount"] is a number \
         and gGame["oDeal"]["holeN"] >= gGame["oDeal"]["dealCount"] then
      -- the forced-post timer arms only once the deal is COMPLETE: a
      -- stalled L0 deal (a contributor never commits/seals) has no timeout
      -- prescription at Level 0 -- recorded, not invented; spec 9's
      -- deal-phase timeout is the L2 void-and-audit machine's
      put heTimeoutPostOf(tStateA) into tPostTxt
      if tPostTxt is not empty then
         -- the same discriminator on the post key, for the same reason --
         -- consecutive identical post keys cannot happen inside one hand
         -- (each post moves kind or seat), but hand N's last post and hand
         -- N+k's first could collide if the between-hands empty key ever
         -- stopped intervening, and item 4 costs nothing
         put tPostTxt & comma & gGame["handNum"] & "-blinds" into tKeyTxt
      end if
   end if
   if tKeyTxt is not gGame["turnKey"] then
      put tKeyTxt into gGame["turnKey"]
      heNetTurnClockStart
      if tKeyTxt is empty and gGame["turnClockTxt"] is not empty then
         put empty into gGame["turnClockTxt"]
         heHudMark
      end if
   end if
end heNetTurnMark

command heNetTurnClockStart
   -- start the CURRENT turn's interval on this client's own clock. One place
   -- (v0.24.0) because two callers need the same three decisions, and the
   -- third one is the F2 fix: whether this clock is a REPLAYED one.
   -- A client catching up by full replay folds the turn-opening wire NOW, so
   -- turnStartMs becomes "now" for a turn that opened minutes ago at every
   -- other node. When the host's live timeout wire then arrives -- past the
   -- replay's announced head, so the seq-keyed waiver in heNetTimeoutOk does
   -- NOT apply -- this client compares ~10 s elapsed against a 90 s limit and
   -- refuses it as premature. Every other node folded the seat; this one is
   -- one action behind FOREVER and every later wire engine-rejects out of
   -- turn, with no chain-level signal. So the clock REMEMBERS that it was
   -- started during catch-up, and heNetTimeoutOk waives the deadline for that
   -- turn ONLY -- the next live turn mark clears the flag, because a waiver
   -- that outlived its turn would let a rushing host fold a live seat early.
   put the milliseconds into gGame["turnStartMs"]
   put "false" into gGame["timeoutSent"]
   if gGame["catchUpTo"] is a number then
      put "true" into gGame["turnStale"]
   else
      put "false" into gGame["turnStale"]
   end if
end heNetTurnClockStart

command heNetTimeoutRearm
   -- a host timeout wire the ENGINE refused (heBetApply rejected it: a raced
   -- prescription, a stale seat) leaves turnKey untouched, so heNetTurnMark
   -- never runs -- and heNetTurnMark is the ONLY thing that clears
   -- timeoutSent. The host's own guard then exited on every later tick, it
   -- never re-emitted, the seat never acted and the table stalled SILENTLY:
   -- exactly the failure the timer exists to prevent (F3). Restart the
   -- interval instead. Every client folded the SAME refused wire, so every
   -- clock restarts on the same wire and the interval-on-one-clock property
   -- survives; the host re-emits one full act period later, which is a
   -- BOUNDED retry -- clearing the latch alone would have re-emitted the same
   -- refused wire at 4 Hz forever.
   heNetTurnClockStart
end heNetTimeoutRearm

function heNetTurnLimitSecs pSeatNum
   -- the CURRENT subject's full allowance in seconds: 0 for a sitting-out
   -- seat (it times out instantly -- spec 9's auto fold/post), else the
   -- cfg's act timer plus the one per-hand time-bank while unspent
   local tLimit
   if gGame["sitOutBy"][pSeatNum] is "true" then
      return 0
   end if
   put heNetCfgVal("act", kHeDefaultActSecs) into tLimit
   if gGame["oDeal"]["bankUsedBy"][pSeatNum] is not "true" then
      add heNetCfgVal("bank", kHeDefaultBankSecs) to tLimit
   end if
   return tLimit
end heNetTurnLimitSecs

command heNetActTimerTick
   -- the per-tick act-timer budget (H2: poll tick, never per-frame). Every
   -- client runs the countdown for the HUD (repaint only when the shown
   -- second changes -- well under the 4 Hz ceiling); the HOST additionally
   -- emits the signed timeout wire at expiry, once per turn (timeoutSent),
   -- with the bank flag that makes the spend transcript-visible.
   local tKeyTxt, tKindTxt, tSeatNum, tAmt, tLimit, tRemain, tShowTxt, tVerb
   local tBankTxt
   if gGame["online"] is not "true" or gGame["gameOn"] is not "true" \
         or gGame["hostLost"] is "true" then
      exit heNetActTimerTick
   end if
   put gGame["turnKey"] into tKeyTxt
   if tKeyTxt is empty then
      exit heNetActTimerTick
   end if
   set the itemDelimiter to comma
   put item 1 of tKeyTxt into tKindTxt
   put item 2 of tKeyTxt into tSeatNum
   put item 3 of tKeyTxt into tAmt
   put heNetTurnLimitSecs(tSeatNum) into tLimit
   put tLimit - ((the milliseconds - gGame["turnStartMs"]) div 1000) into tRemain
   if tRemain < 0 then
      put 0 into tRemain
   end if
   -- HUD: the acting seat's remaining seconds, on-change only (<= 1 Hz in
   -- practice; the blinds-phase post timer stays un-painted -- it exists to
   -- unwedge, not to pressure)
   put empty into tShowTxt
   if tKindTxt is "act" then
      put tRemain & "s" into tShowTxt
   end if
   if tShowTxt is not gGame["turnClockTxt"] then
      put tShowTxt into gGame["turnClockTxt"]
      heHudMark
   end if
   -- host: emit the timeout wire at expiry (the seat's bank rides as
   -- bank=1 exactly when this deadline included it)
   if gGame["isHost"] is not "true" or tRemain > 0 \
         or gGame["timeoutSent"] is "true" then
      exit heNetActTimerTick
   end if
   put "true" into gGame["timeoutSent"]
   if gGame["oDeal"]["bankUsedBy"][tSeatNum] is "true" \
         or gGame["sitOutBy"][tSeatNum] is "true" then
      put ",bank=0" into tBankTxt
   else
      put ",bank=1" into tBankTxt
   end if
   if tKindTxt is "act" then
      put heTimeoutVerbOf(gGame["state"], tSeatNum) into tVerb
      heNetSendAction "act", "verb=" & tVerb & ",amount=0,seat=" & tSeatNum \
            & ",timeout=1" & tBankTxt
   else
      heNetSendAction tKindTxt, "amount=" & tAmt & ",seat=" & tSeatNum \
            & ",timeout=1" & tBankTxt
   end if
end heNetActTimerTick

command heNetTimeoutMiss pSeatNum
   -- consecutive-miss bookkeeping after a folded timeout (spec 9: "seat
   -- goes to sit-out after (config) misses"). Derived from the transcript
   -- alone -- every client counts the same wires -- so the auto-sit-out is
   -- consensus, not a clock call.
   if gGame["missCntBy"][pSeatNum] is not a number then
      put 0 into gGame["missCntBy"][pSeatNum]
   end if
   add 1 to gGame["missCntBy"][pSeatNum]
   if gGame["missCntBy"][pSeatNum] >= heNetCfgVal("miss", kHeDefaultMisses) \
         and gGame["sitOutBy"][pSeatNum] is not "true" then
      put "true" into gGame["sitOutBy"][pSeatNum]
      put "sitout seat " & pSeatNum & " sits out after " \
            & gGame["missCntBy"][pSeatNum] & " missed turns" & return after gGame["netLog"]
      heHudMark
   end if
end heNetTimeoutMiss

function heNetTimeoutOk pBodyA, pSeatNum, pKindTxt, pAmt
   -- verify a host-authored timeout wire before folding it (every client,
   -- spec 9): the verb/amount must be EXACTLY the prescription our own
   -- engine state derives, the bank flag must match the transcript-derived
   -- bank state, and the deadline must genuinely have passed on OUR clock
   -- (kHeActSkewSecs tolerance; waived for a sitting-out seat -- the seat
   -- itself asked -- and during catch-up replay, where the live table
   -- already policed it). Returns empty when the wire folds, else the
   -- refusal reason (logged loudly: a rushing host is EVIDENCE).
   local tLimit, tElapsed, tPostTxt
   if pKindTxt is "act" then
      if pBodyA["verb"] is not heTimeoutVerbOf(gGame["state"], pSeatNum) \
            or pAmt is not 0 then
         return "wrong prescription (" & pBodyA["verb"] & ")"
      end if
   else
      put heTimeoutPostOf(gGame["state"]) into tPostTxt
      if tPostTxt is not (pKindTxt & comma & pSeatNum & comma & pAmt) then
         return "wrong forced post"
      end if
   end if
   if pBodyA["bank"] is "1" then
      if gGame["oDeal"]["bankUsedBy"][pSeatNum] is "true" \
            or gGame["sitOutBy"][pSeatNum] is "true" then
         return "bank already spent"
      end if
   else
      if gGame["oDeal"]["bankUsedBy"][pSeatNum] is not "true" \
            and gGame["sitOutBy"][pSeatNum] is not "true" then
         return "bank denied (unspent bank needs bank=1)"
      end if
   end if
   if gGame["sitOutBy"][pSeatNum] is "true" then
      return empty   -- instant by construction; no clock to check
   end if
   if gGame["catchUpTo"] is a number and gGame["lastSeq"] <= gGame["catchUpTo"] then
      return empty   -- historical: the live table policed the clock
   end if
   if gGame["turnStale"] is "true" then
      -- v0.24.0 (F2): THIS turn's clock was started while a replay was
      -- streaming, so it times the replay, not the table -- the turn really
      -- opened long before we heard about it. The wire's seq cannot express
      -- that (the live timeout arrives PAST the replay's head, so the waiver
      -- above never fires), and refusing it left this client one action
      -- behind for the rest of the session with nothing on the chain to say
      -- so. Waive the deadline for this turn only; heNetTurnClockStart clears
      -- the flag at the next live turn mark. The verb/amount and bank checks
      -- above still run -- those are transcript-deterministic, so a catching-
      -- up client polices them exactly as well as a live one.
      return empty
   end if
   put heNetTurnLimitSecs(pSeatNum) into tLimit
   put (the milliseconds - gGame["turnStartMs"]) div 1000 into tElapsed
   if tElapsed < tLimit - kHeActSkewSecs then
      return "deadline not passed (" & tElapsed & "s of " & tLimit & "s)"
   end if
   return empty
end heNetTimeoutOk

function heNetSeatedWithChipsList
   -- the seats that are SEATED and still hold chips, ascending. The base of
   -- the occupancy rule, factored out at v0.24.0 (F10): heNetHandKick had its
   -- own copy of this scan to tell an over table (one stack left) from a
   -- parked one, and the copy had already drifted -- it omitted nothing yet,
   -- but only heNetNextOccList was pinned by the harness, so a change to the
   -- rule could have silently held in one place and not the other. One
   -- definition, two readers.
   local tOut, tSeatNum, tSeatedList
   set the itemDelimiter to comma
   put gGame["seatedList"] into tSeatedList
   put empty into tOut
   repeat for each item tSeatNum in tSeatedList
      if gGame["stacksBy"][tSeatNum] > 0 then
         put tSeatNum & comma after tOut
      end if
   end repeat
   if tOut is not empty then
      delete char -1 of tOut
   end if
   return tOut
end heNetSeatedWithChipsList

function heNetNextOccList
   -- the seats the NEXT hand deals to: seated, holding chips, and not
   -- sitting out (spec 9: a sitting-out seat is dealt out until its signed
   -- return). One place, so the host's heNetHandKick and the harness pin
   -- the same rule -- and since v0.24.0 the "seated with chips" half is
   -- heNetSeatedWithChipsList, the same scan the parked-table test reads.
   local tOut, tSeatNum, tChipList
   set the itemDelimiter to comma
   put heNetSeatedWithChipsList() into tChipList
   put empty into tOut
   repeat for each item tSeatNum in tChipList
      if gGame["sitOutBy"][tSeatNum] is not "true" then
         put tSeatNum & comma after tOut
      end if
   end repeat
   if tOut is not empty then
      delete char -1 of tOut
   end if
   return tOut
end heNetNextOccList

function heNetPubIsLive pPubHex
   -- is this admitted key present RIGHT NOW? Answered from state we already
   -- keep -- no new wire, no new frame kind (v0.24.0, F7). heNetSeatLateJoiners
   -- used to seat every admitted key that had ever emitted a join wire, and a
   -- peer that joined and then closed its stack stays in boxByPub/admittedA
   -- forever: at the next hand boundary the ghost was handed the lowest empty
   -- seat and a full opening stack, timed out every turn until two misses sat
   -- it out, and held the seat for the rest of the session (seats are never
   -- released).
   -- The two signals, and exactly what each proves:
   --   * a CURRENT transport handle (peerByPub). On the ONION transport this
   --     is authoritative: stream death is a positive event and
   --     heNetOnionDead clears the mapping within a poll tick, so a closed
   --     stack stops being live immediately.
   --   * recency of the last wire or handshake from that key (seenMsByPub,
   --     stamped in heNetApplyWire and heNetOnHandshake). rp1 surfaces NO
   --     disconnect event -- wire-silence is the only honest signal it has,
   --     which is why the host-loss watchdog is built on silence too -- so on
   --     rp1 a handle alone would keep a departed peer "live" forever, i.e.
   --     would not fix the ghost at all.
   -- The rp1 window is deliberately generous (kHeSeatLiveSecs): a joined but
   -- unseated observer emits nothing on its own, so its stamp is usually just
   -- its join wire, and the boundary that would seat it is normally seconds
   -- to a couple of minutes later. An observer that has waited out the whole
   -- window is treated as gone and stays an observer -- a fail-SAFE guess
   -- (reconnecting re-stamps it), and the honest limit of what rp1 can prove.
   -- Verified statically; needs an OXT pass.
   local tSeenMs
   if pPubHex is gGame["idPubHex"] then
      return true   -- ourselves: the host running this check is present
   end if
   if gGame["peerByPub"][pPubHex] is empty then
      return false
   end if
   if gGame["transport"] is "onion" then
      return true
   end if
   put gGame["seenMsByPub"][pPubHex] into tSeenMs
   if tSeenMs is not a number then
      return false
   end if
   return ((the milliseconds - tSeenMs) <= (kHeSeatLiveSecs * 1000))
end heNetPubIsLive

command heNetSeatLateJoiners
   -- HOST, at each hand boundary (2e late-join, spec 9's reconnect family):
   -- any admitted key that has JOINED (bound a session box on-chain) but
   -- holds no seat is assigned the lowest empty seat, ascending-pubkey
   -- order (deterministic, like the game-start seating), up to the signed
   -- cfg's seat count -- each as a signed sit wire, so every client folds
   -- the same seating. No empty seat = the joiner stays an OBSERVER (it
   -- folds the whole game already; the replay machinery carried it here).
   -- v0.24.0 (F7): "has joined" is a HISTORICAL fact and was the only test --
   -- so a departed peer was seated as a ghost. Current liveness is now
   -- required (heNetPubIsLive, which carries what each transport can prove).
   -- OPEN DECISION, deliberately not invented here: a SPECTATOR (spec 4's
   -- read-only role) is still indistinguishable from a player at this point.
   -- The admission token has a role field, but every client this build can
   -- talk to sends "player" in it, so refusing on role would refuse real
   -- players; declaring spectator intent needs a wire/UI decision, and this
   -- change was scoped to introduce none. Recorded in CLAUDE.md and
   -- IMPLEMENTATION-PLAN.md.
   local tPubHex, tPubsTxt, tSeatNum, tMaxSeats
   if gGame["isHost"] is not "true" then
      exit heNetSeatLateJoiners
   end if
   put empty into tPubsTxt
   repeat for each key tPubHex in gGame["boxByPub"]
      if gGame["admittedA"][tPubHex] is "true" \
            and gGame["seatByPub"][tPubHex] is empty then
         if gGame["oracleHost"] is "true" and tPubHex is gGame["idPubHex"] then
            next repeat   -- the oracle never takes a seat
         end if
         if not heNetPubIsLive(tPubHex) then
            put "join   not seating " & char 1 to 8 of tPubHex \
                  & " -- joined but not present now" & return after gGame["netLog"]
            next repeat
         end if
         put tPubHex & return after tPubsTxt
      end if
   end repeat
   if tPubsTxt is empty then
      exit heNetSeatLateJoiners
   end if
   sort lines of tPubsTxt
   put heNetCfgVal("seats", kHeDefaultSeats) into tMaxSeats
   repeat for each line tPubHex in tPubsTxt
      if tPubHex is empty then
         next repeat
      end if
      repeat with tSeatNum = 1 to tMaxSeats
         if gGame["pubBySeat"][tSeatNum] is empty then
            put "join   seating late joiner " & char 1 to 8 of tPubHex \
                  & " at seat " & tSeatNum & return after gGame["netLog"]
            heNetSendAction "sit", "seat=" & tSeatNum & ",pub=" & tPubHex
            exit repeat
         end if
      end repeat
   end repeat
end heNetSeatLateJoiners

command heNetStartGame
   -- HOST only: seat everyone who has joined (published a session box pub) and
   -- kick off hand 1. Seats are assigned in ascending-pubkey order, so the
   -- assignment is deterministic and every client could re-derive it; the sit
   -- wires make it explicit and signed. Late joiners sit out until the sit-in
   -- flow arrives with liveness (2e).
   local tPubHex, tPubsTxt, tSeatNum, tJoinedN
   if gGame["online"] is not "true" or gGame["isHost"] is not "true" then
      exit heNetStartGame
   end if
   if gGame["gameOn"] is "true" then
      exit heNetStartGame
   end if
   put empty into tPubsTxt
   put 0 into tJoinedN
   repeat for each key tPubHex in gGame["boxByPub"]
      if gGame["admittedA"][tPubHex] is "true" then
         -- Phase 3: the ORACLE hosts and deals but never takes a seat --
         -- its join still bound a session box (the seedSeals seal to it)
         if gGame["oracleHost"] is "true" and tPubHex is gGame["idPubHex"] then
            next repeat
         end if
         put tPubHex & return after tPubsTxt
         add 1 to tJoinedN
      end if
   end repeat
   if tJoinedN < 2 then
      heUISetStatus "Need at least 2 joined players to start (have " & tJoinedN & ")."
      exit heNetStartGame
   end if
   if tJoinedN > kHeMaxSeats then
      heUISetStatus "Too many joined players for the table (" & tJoinedN & ")."
      exit heNetStartGame
   end if
   sort lines of tPubsTxt
   put 0 into tSeatNum
   repeat for each line tPubHex in tPubsTxt
      add 1 to tSeatNum
      heNetSendAction "sit", "seat=" & tSeatNum & ",pub=" & tPubHex
   end repeat
   heNetHandKick
end heNetStartGame

command heNetHandKick
   -- HOST only: open the next hand -- emit handStart (+ dealLevel naming the
   -- dealer = the button seat) for the seats that still have chips and are
   -- not sitting out (heNetNextOccList, the one shared rule). 2e: the hand
   -- boundary is ALSO where late joiners take empty seats (signed sit
   -- wires, deterministic order) and where a table short of live players
   -- WAITS instead of ending -- a sitting-out seat still holding chips is a
   -- player who can return, so the beat re-arms until one does.
   local tOccList, tButtonSeat, tCount, tStacksTxt
   local tChipCount
   if gGame["online"] is not "true" or gGame["isHost"] is not "true" then
      exit heNetHandKick
   end if
   -- clear the parked latch FIRST, before anything below emits (v0.24.0).
   -- Both heNetSeatLateJoiners and the handStart emission fold their own
   -- wires re-entrantly (heNetFoldGameWire ends in heNetGameReact), and
   -- react's unpark step reads this latch -- leaving it set while a kick is
   -- already in flight would let a nested react kick again and deal two
   -- hands. The park branch below sets it back on if the table stays short.
   put "false" into gGame["handWait"]
   heNetSeatLateJoiners
   set the itemDelimiter to comma
   put heNetNextOccList() into tOccList
   put the number of items of tOccList into tCount
   if tCount < 2 then
      -- fewer than 2 DEALT seats: distinguish an over table (one stack
      -- left) from a parked one (sitting-out players still hold chips).
      -- The scan is heNetSeatedWithChipsList (v0.24.0, F10) -- the same one
      -- heNetNextOccList filters, so the two can no longer drift.
      put the number of items of heNetSeatedWithChipsList() into tChipCount
      if tChipCount >= 2 then
         -- PARK the table and LATCH it (v0.24.0, F6). The latch is what makes
         -- the parked state re-armable no matter which path parked it: the
         -- between-hands beat used to require phase "between", which is true
         -- after a settle but NOT when the park came from heNetStartGame, so
         -- the beat died on its first firing and the table never dealt again
         -- however many players returned. heNetNextHandTick now accepts the
         -- latch, and heNetGameReact kicks the table the moment a signed sit
         -- return makes two seats dealable -- which is what actually heals a
         -- table parked with autoNext off, where no beat exists at all.
         put "true" into gGame["handWait"]
         heUISetStatus "Waiting for sitting-out players to return..."
         if gGame["autoNext"] is "true" then
            send "heNetNextHandTick" to me in hePaceMs("paceNext", kHeNextHandDelayMs) milliseconds
         end if
      else
         heUISetStatus "Game over -- one stack left."
      end if
      exit heNetHandKick
   end if
   put heScheduleButton(tOccList, gGame["lastBB"]) into tButtonSeat
   add 1 to gGame["handNum"]
   put tOccList into tStacksTxt
   replace comma with "|" in tStacksTxt
   heNetSendAction "handStart", "seats=" & tStacksTxt & ",button=" & tButtonSeat
   -- Phase 3: at Level 1 the ORACLE deals (dealer=0 -- no seat); at Level 0
   -- the dealer is the button seat (the L0 rotation). count stays the number
   -- of dealt SEATS either way; the oracle's extra entropy position is
   -- count+1 by convention (heNetContribCount).
   if gGame["oracleHost"] is "true" then
      heNetSendAction "dealLevel", "level=1,dealer=0,count=" & tCount
   else
      heNetSendAction "dealLevel", "level=0,dealer=" & tButtonSeat & ",count=" & tCount
   end if
end heNetHandKick

on heNetNextHandTick
   -- host's between-hands beat; guarded so a stale send can never double-kick.
   -- v0.24.0 (F6): a PARKED table (heNetHandKick found fewer than 2 dealable
   -- seats while 2+ stacks remain) counts as a legal state to fire in, whether
   -- it was parked from the between-hands pause or straight from
   -- heNetStartGame -- the phase-only guard let the re-armed beat die on its
   -- first firing in the second case, and the table could never resume.
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if gGame["online"] is not "true" or gGame["isHost"] is not "true" then
      exit heNetNextHandTick
   end if
   if gGame["phase"] is not "between" and gGame["handWait"] is not "true" then
      exit heNetNextHandTick
   end if
   heNetHandKick
end heNetNextHandTick

command heNetEngineFold pMsgType, pSeatNum, pAmount
   -- fold one gameplay message into the SAME pure engine the hotseat uses.
   -- No heLogAppend (online, gGame["log"] is the signed wire chain itself) and
   -- no paced hotseat scheduling -- consequences are wire-driven via react.
   -- v0.24.0: the outcome is RECORDED in gGame["foldApplied"] for the caller.
   -- heBetApply can refuse (out of turn, wrong amount, a raced prescription),
   -- and three call sites were writing consensus state -- the seat's one
   -- per-hand time-bank, its consecutive-miss count, and the reset of that
   -- count -- around a fold that might never have happened (F4/F5). A command
   -- cannot return a value to a statement-position caller, and `the result` is
   -- consumed by the next command (gotcha 27), so the flag is a store field:
   -- set on every path, read IMMEDIATELY by the caller, and inspectable by the
   -- harness. Nothing this handler calls afterwards folds again, so there is
   -- no nesting that could overwrite it before the caller looks.
   local tStateA, tVerb
   put "false" into gGame["foldApplied"]
   put heBetApply(gGame["state"], pMsgType, pSeatNum, pAmount) into tStateA
   if tStateA["err"] is not empty then
      put "drop   engine-rejected " & pMsgType && tStateA["err"] & return after gGame["netLog"]
      exit heNetEngineFold
   end if
   put tStateA into gGame["state"]
   put "true" into gGame["foldApplied"]
   if pMsgType is "act" then
      set the itemDelimiter to comma
      put item 1 of pAmount into tVerb
      heSndVerb tVerb
   end if
   -- mirror the engine phase into the table phase the HUD renders (the paced
   -- hotseat equivalents live in heReactToNotes; online is turn-rate)
   if tStateA["phase"] is "runout" then
      put "runout" into gGame["phase"]
   else if tStateA["phase"] is "showdown" or tStateA["phase"] is "handdone" then
      put "showdown" into gGame["phase"]
      -- 2e street ckpts: the wire that CLOSED the betting is the showdown
      -- boundary's transition wire -- record its head once (heNetApplyWire
      -- already advanced the chain before folding, so the head includes it;
      -- every client sees the same wire at the same seq, so every client
      -- records the same head)
      if gGame["oDeal"]["ckptHeadBy"]["showdown"] is empty then
         put gGame["chainHeadHex"] into gGame["oDeal"]["ckptHeadBy"]["showdown"]
      end if
   end if
   -- 2e act timers: every fold that can move the action re-aims the clock
   -- (the mark restarts only when the SUBJECT changes)
   heNetTurnMark
   heHudMark
end heNetEngineFold

command heNetFoldGameWire pTypeTxt, pFromHex, pBodyTxt, pHandTxt
   -- fold one verified, in-order, ROSTERED game wire into the client game
   -- store + engine. From-authority per type: sit/handStart/dealLevel/settle
   -- must be host-authored; holeDeliver/board must come from this hand's
   -- dealer; everything seat-scoped must come from the key that OWNS the seat
   -- (a seat claim in a body is never trusted over seatByPub). Anything
   -- malformed is a logged drop, never a throw (H4).
   local tBodyA, tSeat, tPos, tHex, tAmt, tVerb, tCardsTxt, tOneCard, tIdxList
   local tFromSeat, tDealerPub, tOccList, tCount, tStackAmt, tOpenErr, tOpenTxt
   local tDeltasTxt, tMineTxt, tHeadHex, tSigHex, tResultTxt, tPrevBad
   local tStreetName, tBoardHeld, tBoardN, tCkptHead
   set the itemDelimiter to comma
   put pBodyTxt into tBodyA
   split tBodyA by comma and "="
   put gGame["seatByPub"][pFromHex] into tFromSeat
   switch pTypeTxt

      case "join"
         -- spec 5 session binding: the signed contentLine covers table + from
         -- + box pub, which IS the binding tuple. Store the box lane.
         put tBodyA["box"] into tHex
         if heIsHex(tHex, 64) then
            put tHex into gGame["boxByPub"][pFromHex]
            put "join   " & char 1 to 8 of pFromHex & " bound a session box key" & return after gGame["netLog"]
         else
            put "drop   join with a malformed box key" & return after gGame["netLog"]
         end if
         break

      case "sit"
         -- two forms share the name (spec 6's fixed vocabulary): the
         -- HOST-authored assignment ("seat=N,pub=<64hex>"), and -- 2e -- a
         -- seat's OWN return from sit-out ("seat=N", no pub, from the key
         -- that already owns the seat): re-enters at the next hand boundary
         -- (heNetNextOccList reads sitOutBy; the host's next kick deals it).
         if tBodyA["pub"] is empty then
            put tBodyA["seat"] into tSeat
            if tFromSeat is 0 or tSeat is not tFromSeat then
               put "drop   sit-return for a seat the sender does not own" & return after gGame["netLog"]
               break
            end if
            put empty into gGame["sitOutBy"][tFromSeat]
            put 0 into gGame["missCntBy"][tFromSeat]
            put "sitout seat " & tFromSeat & " returns next hand" & return after gGame["netLog"]
            heHudMark
            break
         end if
         if pFromHex is not gGame["hostPubHex"] then
            put "drop   non-host sit ignored" & return after gGame["netLog"]
            break
         end if
         put tBodyA["seat"] into tSeat
         put tBodyA["pub"] into tHex
         if tSeat is not a number or tSeat < 1 or tSeat > kHeMaxSeats or not heIsHex(tHex, 64) then
            put "drop   malformed sit" & return after gGame["netLog"]
            break
         end if
         put tSeat into gGame["seatByPub"][tHex]
         put tHex into gGame["pubBySeat"][tSeat]
         put gGame["seatedList"] into tOccList
         if tSeat is not among the items of tOccList then
            if tOccList is empty then
               put tSeat into tOccList
            else
               put comma & tSeat after tOccList
            end if
            sort items of tOccList ascending numeric
            put tOccList into gGame["seatedList"]
         end if
         -- opening stack from the signed table cfg
         put heNetCfgVal("stack", kHeDefaultStack) into tStackAmt
         if gGame["stacksBy"][tSeat] is not a number then
            put tStackAmt into gGame["stacksBy"][tSeat]
         end if
         put "true" into gGame["gameOn"]
         if tHex is gGame["idPubHex"] then
            heUISetStatus "You are seated at seat " & tSeat & ". The game is starting."
         end if
         break

      case "handStart"
         if pFromHex is not gGame["hostPubHex"] then
            put "drop   non-host handStart ignored" & return after gGame["netLog"]
            break
         end if
         put tBodyA["seats"] into tOccList
         replace "|" with comma in tOccList
         put tBodyA["button"] into tSeat
         if tOccList is empty or tSeat is not a number then
            put "drop   malformed handStart" & return after gGame["netLog"]
            break
         end if
         heNetHandReset
         put pHandTxt into gGame["handNum"]
         put tSeat into gGame["buttonSeat"]
         put heBetNewHand(gGame["sb"], gGame["bb"], gGame["ante"], gGame["stacksBy"], \
               tOccList, tSeat) into gGame["state"]
         put gGame["state"]["bbSeat"] into gGame["lastBB"]
         put "hand" into gGame["phase"]
         heNetTurnMark
         heUIClearCards
         heHudMark
         put "hand   #" & pHandTxt & " begins (button seat " & tSeat & ")" & return after gGame["netLog"]
         break

      case "dealLevel"
         if pFromHex is not gGame["hostPubHex"] then
            put "drop   non-host dealLevel ignored" & return after gGame["netLog"]
            break
         end if
         -- level 0 = the button seat deals; level 1 = the ORACLE deals
         -- (Phase 3, spec 7.2: dealer=0, no seat). Anything else is refused
         -- readably -- which is ALSO how a pre-oracle client refuses an
         -- oracle table instead of mis-folding it (downgrade refusal).
         if tBodyA["level"] is not "0" and tBodyA["level"] is not "1" then
            put "drop   unsupported deal level " & tBodyA["level"] & return after gGame["netLog"]
            break
         end if
         put tBodyA["dealer"] into tSeat
         put tBodyA["count"] into tCount
         if tSeat is not a number or tCount is not a number then
            put "drop   malformed dealLevel" & return after gGame["netLog"]
            break
         end if
         if tBodyA["level"] is "1" and tSeat is not 0 then
            put "drop   level-1 dealLevel must name the oracle (dealer=0)" & return after gGame["netLog"]
            break
         end if
         put tSeat into gGame["oDeal"]["dealerSeat"]
         put tCount into gGame["oDeal"]["dealCount"]
         if tBodyA["level"] is "1" then
            put "true" into gGame["oDeal"]["oracleDeal"]
            put "deal   the ORACLE deals this hand (level 1; it holds no seat)" & return after gGame["netLog"]
         end if
         break

      case "seedCommit"
         -- position ownership via heNetContribPosOk: seats own their packed
         -- positions; the ORACLE (host, level 1, no seat) owns dealCount+1
         put tBodyA["pos"] into tPos
         put tBodyA["commit"] into tHex
         if not heIsHex(tHex, 64) or not heNetContribPosOk(tPos, tFromSeat, pFromHex) then
            put "drop   bad seedCommit" & return after gGame["netLog"]
            break
         end if
         if gGame["oDeal"]["commitsBy"][tPos] is empty then
            put tHex into gGame["oDeal"]["commitsBy"][tPos]
            add 1 to gGame["oDeal"]["commitN"]
         end if
         break

      case "seedSeal"
         put tBodyA["pos"] into tPos
         put tBodyA["sealed"] into tHex
         if tHex is empty or not heIsHex(tHex, 0) \
               or not heNetContribPosOk(tPos, tFromSeat, pFromHex) then
            put "drop   bad seedSeal" & return after gGame["netLog"]
            break
         end if
         if gGame["oDeal"]["sealsBy"][tPos] is empty then
            put tHex into gGame["oDeal"]["sealsBy"][tPos]
            add 1 to gGame["oDeal"]["sealN"]
         end if
         break

      case "holeDeliver"
         -- Phase 3: at level 1 the dealer key is the ORACLE's (host), no
         -- seat behind it -- heNetDealerPubHex names it either way
         put heNetDealerPubHex() into tDealerPub
         if pFromHex is not tDealerPub then
            put "drop   holeDeliver not from the dealer" & return after gGame["netLog"]
            break
         end if
         put tBodyA["seat"] into tSeat
         put tBodyA["sealed"] into tHex
         if tSeat is not a number or tHex is empty or not heIsHex(tHex, 0) then
            put "drop   malformed holeDeliver" & return after gGame["netLog"]
            break
         end if
         if gGame["oDeal"]["holeSealedBy"][tSeat] is empty then
            put tHex into gGame["oDeal"]["holeSealedBy"][tSeat]
            add 1 to gGame["oDeal"]["holeN"]
            -- 2e street ckpts: the LAST sealed delivery is the "deal"
            -- boundary's transition wire -- record its head once
            if gGame["oDeal"]["dealCount"] is a number \
                  and gGame["oDeal"]["holeN"] >= gGame["oDeal"]["dealCount"] \
                  and gGame["oDeal"]["ckptHeadBy"]["deal"] is empty then
               put gGame["chainHeadHex"] into gGame["oDeal"]["ckptHeadBy"]["deal"]
            end if
            -- 2e act timers: the completed deal is what ARMS the forced-post
            -- timer (heNetTurnMark gates the blinds subject on holeN)
            heNetTurnMark
         end if
         if tSeat is heNetMySeat() and gGame["oDeal"]["myHoles"] is empty then
            -- our private lane: open the sealed box with the session key (H4:
            -- a bad blob is a logged drop; the audit names the dealer later)
            try
               put textDecode(sxSealOpen(heHex2BinD(tHex), gGame["boxPubData"], \
                     gGame["boxSecData"]), "utf-8") into tOpenTxt
               if heIsCardList(tOpenTxt, 2) then
                  put tOpenTxt into gGame["oDeal"]["myHoles"]
                  heUISetStatus "Your cards: " & heCardName(item 1 of tOpenTxt) \
                        && heCardName(item 2 of tOpenTxt)
               else
                  put "drop   holeDeliver opened to garbage" & return after gGame["netLog"]
               end if
            catch tOpenErr
               put "drop   holeDeliver would not open" & return after gGame["netLog"]
            end try
         end if
         break

      case "stand"
         -- 2e sit-out (spec 9): a seat's OWN signed declaration, seat-scoped
         -- like show/muck. Effective immediately: the seat is dealt out at
         -- the next boundary (heNetNextOccList), and mid-hand its turns
         -- time out INSTANTLY (heNetTurnLimitSecs reads sitOutBy) -- the
         -- spec's auto check/fold, just without the wait.
         if tFromSeat is 0 then
            put "drop   stand from an unseated key" & return after gGame["netLog"]
            break
         end if
         put tBodyA["seat"] into tSeat
         if tSeat is not a number or tSeat is not tFromSeat then
            put "drop   stand for a seat the sender does not own" & return after gGame["netLog"]
            break
         end if
         if gGame["sitOutBy"][tFromSeat] is not "true" then
            put "true" into gGame["sitOutBy"][tFromSeat]
            put "sitout seat " & tFromSeat & " sits out (own request)" & return after gGame["netLog"]
            heHudMark
         end if
         break

      case "bidAnte"
      case "bidSB"
      case "bidBB"
         -- 2e: a HOST-authored timeout post ("amount=..,seat=N,timeout=1,
         -- bank=..") folds as seat N's forced bet once it verifies -- this
         -- is what unwedges a hand whose seat went dark before its blind
         -- posted (spec 9 "auto ... posts"). A pre-liveness client
         -- engine-rejects it visibly (wrong seat for the sender) and
         -- stalls where it always stalled -- never mis-folds.
         if tBodyA["timeout"] is "1" then
            if pFromHex is not gGame["hostPubHex"] then
               put "drop   non-host timeout ignored" & return after gGame["netLog"]
               break
            end if
            put tBodyA["seat"] into tSeat
            put tBodyA["amount"] into tAmt
            if tSeat is not a number or tAmt is not a number then
               put "drop   malformed timeout " & pTypeTxt & return after gGame["netLog"]
               break
            end if
            put heNetTimeoutOk(tBodyA, tSeat, pTypeTxt, tAmt) into tResultTxt
            if tResultTxt is not empty then
               put "TIMEOUT-REFUSED " & pTypeTxt & " seat " & tSeat & ": " \
                     & tResultTxt & return after gGame["netLog"]
               break
            end if
            put "t-out  seat " & tSeat & " timed out -- auto " & pTypeTxt & return after gGame["netLog"]
            heNetEngineFold pTypeTxt, tSeat, tAmt
            if gGame["foldApplied"] is "true" then
               -- v0.24.0 (F4): the bank spend and the miss count are CONSENSUS
               -- state, so they may only move for an action that actually
               -- applied. Writing them before the fold spent the seat's one
               -- per-hand time-bank and charged it a miss for a bet that never
               -- happened -- and since every client did it identically, the
               -- wrong state was consensus too, invisible as a divergence.
               -- Two of those miss counts sit the seat out for turns it was
               -- never given.
               if tBodyA["bank"] is "1" then
                  put "true" into gGame["oDeal"]["bankUsedBy"][tSeat]
               end if
               heNetTimeoutMiss tSeat
            else
               put "t-out  the engine refused that timeout -- interval re-armed" \
                     & return after gGame["netLog"]
               heNetTimeoutRearm
            end if
            break
         end if
         if tFromSeat is 0 then
            put "drop   bid from an unseated key" & return after gGame["netLog"]
            break
         end if
         put tBodyA["amount"] into tAmt
         heNetEngineFold pTypeTxt, tFromSeat, tAmt
         -- v0.24.2, FOUND BY THE FIRST ENGINE RUN OF THIS SECTION: a bid does
         -- NOT reset the miss count, because every wire that reaches here is a
         -- FORCED post -- a blind or an ante. A seat whose human walked away
         -- still posts them: that is what "forced" means, and the client does
         -- it without being asked. So resetting here wiped the counter at the
         -- top of EVERY hand and made the consecutive-miss auto-sit-out
         -- unreachable across hands -- which is the only span spec 9's
         -- "(config) missed turns" can mean. Observed: seat 1 timed out in
         -- hand 1 (miss 1), posted its blind in hand 2 (reset to 0), timed out
         -- again (miss 1), and never sat out; six section-20 checks failed on
         -- that one line and every one of them was right.
         -- Presence is a VOLUNTARY act, and the act case below is where the
         -- reset belongs (it already gates on foldApplied, F5, so an
         -- out-of-turn act the engine throws away cannot hold the count at
         -- zero either). No WIRE byte changes here, but the miss count is
         -- transcript-derived consensus, so every client must carry this
         -- together.
         break

      case "act"
         -- 2e: the HOST-authored timeout act -- the spec 9 expiry
         -- prescription (check-or-fold) as a field on the EXISTING act
         -- wire ("verb=..,amount=0,seat=N,timeout=1,bank=.."), never a new
         -- kind: verified (host authority, exact prescription, bank state,
         -- the deadline genuinely passed on OUR clock) and folded as seat
         -- N's action, so the transcript stays deterministic. A
         -- pre-liveness client engine-rejects it (out of turn for the
         -- host's seat) and stalls visibly -- except a host self-timeout,
         -- which folds identically to a voluntary check/fold there.
         if tBodyA["timeout"] is "1" then
            if pFromHex is not gGame["hostPubHex"] then
               put "drop   non-host timeout ignored" & return after gGame["netLog"]
               break
            end if
            put tBodyA["seat"] into tSeat
            put tBodyA["verb"] into tVerb
            if tSeat is not a number then
               put "drop   malformed timeout act" & return after gGame["netLog"]
               break
            end if
            put heNetTimeoutOk(tBodyA, tSeat, "act", 0) into tResultTxt
            if tResultTxt is not empty then
               put "TIMEOUT-REFUSED act seat " & tSeat & ": " & tResultTxt \
                     & return after gGame["netLog"]
               break
            end if
            put "t-out  seat " & tSeat & " timed out -- auto " & tVerb & return after gGame["netLog"]
            heNetEngineFold "act", tSeat, tVerb & comma & 0
            if gGame["foldApplied"] is "true" then
               -- F4, the act twin of the forced-post site above: bank and miss
               -- only move when the fold moved.
               if tBodyA["bank"] is "1" then
                  put "true" into gGame["oDeal"]["bankUsedBy"][tSeat]
               end if
               heNetTimeoutMiss tSeat
            else
               put "t-out  the engine refused that timeout -- interval re-armed" \
                     & return after gGame["netLog"]
               heNetTimeoutRearm
            end if
            break
         end if
         if tFromSeat is 0 then
            put "drop   act from an unseated key" & return after gGame["netLog"]
            break
         end if
         put tBodyA["verb"] into tVerb
         put tBodyA["amount"] into tAmt
         heNetEngineFold "act", tFromSeat, tVerb & comma & tAmt
         if gGame["foldApplied"] is "true" then
            put 0 into gGame["missCntBy"][tFromSeat]   -- a live act is presence (F5)
         end if
         break

      case "board"
         put heNetDealerPubHex() into tDealerPub
         if pFromHex is not tDealerPub then
            put "drop   board not from the dealer" & return after gGame["netLog"]
            break
         end if
         -- street-vs-count dedupe: a redelivered or reconnect-burst board wire
         -- must not append twice (a doubled flop would shift every later slot
         -- and corrupt the audit's board compare). Each street lands exactly
         -- once, in order.
         put tBodyA["street"] into tStreetName
         put gGame["oDeal"]["boardList"] into tBoardHeld
         put the number of items of tBoardHeld into tBoardN
         if not ((tStreetName is "flop" and tBoardN is 0) \
               or (tStreetName is "turn" and tBoardN is 3) \
               or (tStreetName is "river" and tBoardN is 4)) then
            put "drop   out-of-order/duplicate board (" & tStreetName & ")" & return after gGame["netLog"]
            break
         end if
         put tBodyA["cards"] into tCardsTxt
         replace "|" with comma in tCardsTxt
         put empty into tIdxList
         repeat for each item tOneCard in tCardsTxt
            put heCardIndex(tOneCard) & comma after tIdxList
         end repeat
         if tIdxList is not empty then
            delete char -1 of tIdxList
         end if
         if tStreetName is "flop" then
            if not heIsCardList(tIdxList, 3) then
               put "drop   malformed board" & return after gGame["netLog"]
               break
            end if
         else
            if not heIsCardList(tIdxList, 1) then
               put "drop   malformed board" & return after gGame["netLog"]
               break
            end if
         end if
         if gGame["oDeal"]["boardList"] is empty then
            put tIdxList into gGame["oDeal"]["boardList"]
         else
            put comma & tIdxList after gGame["oDeal"]["boardList"]
         end if
         heNetEngineFold "board", 0, 0
         heNetShowBoard
         -- 2e street ckpts: the accepted board wire IS its street's
         -- transition wire -- record the boundary head once
         if gGame["oDeal"]["ckptHeadBy"][tStreetName] is empty then
            put gGame["chainHeadHex"] into gGame["oDeal"]["ckptHeadBy"][tStreetName]
         end if
         break

      case "seedReveal"
         put tBodyA["pos"] into tPos
         put tBodyA["seed"] into tHex
         if not heIsHex(tHex, 64) or not heNetContribPosOk(tPos, tFromSeat, pFromHex) then
            put "drop   bad seedReveal" & return after gGame["netLog"]
            break
         end if
         -- the reveal must open the commitment made before the deal (spec 7.1)
         if heSeedCommitHex(tHex) is not gGame["oDeal"]["commitsBy"][tPos] then
            put "AUDIT  seedReveal pos " & tPos & " does not match its commit" & return after gGame["netLog"]
            break
         end if
         if gGame["oDeal"]["revealsBy"][tPos] is empty then
            put tHex into gGame["oDeal"]["revealsBy"][tPos]
            add 1 to gGame["oDeal"]["revealN"]
         end if
         break

      case "settle"
         if pFromHex is not gGame["hostPubHex"] then
            put "drop   non-host settle ignored" & return after gGame["netLog"]
            break
         end if
         if gGame["oDeal"]["settleDone"] is "true" then
            break
         end if
         put tBodyA["deltas"] into tDeltasTxt
         put heNetComputeSettleTxt() into tMineTxt
         if tMineTxt is empty then
            put "drop   settle before the reveals completed" & return after gGame["netLog"]
            break
         end if
         if tDeltasTxt is not tMineTxt then
            -- a host settle that disagrees with our own deterministic
            -- recomputation is refused outright -- deliberate: following it
            -- would mean following a provably wrong (or hostile) host
            put "SETTLE-MISMATCH host=" & tDeltasTxt & " ours=" & tMineTxt & return after gGame["netLog"]
            heUISetStatus "Settlement mismatch -- this hand is disputed. See the net feed."
            break
         end if
         heNetApplySettle tDeltasTxt
         break

      case "receipt"
         if tFromSeat is 0 then
            put "drop   receipt from an unseated key" & return after gGame["netLog"]
            break
         end if
         put tBodyA["head"] into tHeadHex
         put tBodyA["sig"] into tSigHex
         if not heIsHex(tHeadHex, 64) or not heIsHex(tSigHex, 128) \
               or tHeadHex is not gGame["rcptHeadHex"] \
               or not heReceiptSigVerify(tSigHex, tHeadHex, pFromHex) then
            put "drop   bad receipt from seat " & tFromSeat & return after gGame["netLog"]
            break
         end if
         if gGame["oDeal"]["receiptsBy"][tFromSeat] is empty then
            put tSigHex into gGame["oDeal"]["receiptsBy"][tFromSeat]
            add 1 to gGame["oDeal"]["receiptN"]
         end if
         if gGame["oDeal"]["receiptN"] >= gGame["oDeal"]["dealCount"] then
            put "rcpt   hand " & gGame["handNum"] & " receipt co-signed by all " \
                  & gGame["oDeal"]["receiptN"] & " seats" & return after gGame["netLog"]
         end if
         break

      case "audit"
         -- Phase 3: the ORACLE audits too (it witnessed the whole deal it
         -- ran); its verdict files under contributor slot 0, logged by name
         if tFromSeat is 0 and not (heNetOracleDeal() and pFromHex is gGame["hostPubHex"]) then
            put "drop   audit from an unseated key" & return after gGame["netLog"]
            break
         end if
         if tFromSeat is not a number then
            put 0 into tFromSeat   -- the oracle's verdict files under slot 0
         end if
         put tBodyA["result"] into tResultTxt
         if gGame["oDeal"]["auditsBy"][tFromSeat] is empty then
            put tResultTxt into gGame["oDeal"]["auditsBy"][tFromSeat]
         end if
         if tFromSeat is 0 then
            put "audit  oracle: " & tResultTxt & return after gGame["netLog"]
         else
            put "audit  seat " & tFromSeat & ": " & tResultTxt & return after gGame["netLog"]
         end if
         break

      case "ckpt"
         -- 2e street checkpoint (spec 6): a SEATED player's signature over
         -- the boundary head it observed. Verify-or-drop; then compare the
         -- named head against the one WE recorded at that boundary -- every
         -- client recorded the transition wire's head, so a verified ckpt
         -- naming a different one is host-fork EVIDENCE (attributable
         -- equivocation), logged loudly and never folded as agreement.
         if tFromSeat is 0 then
            put "drop   ckpt from an unseated key" & return after gGame["netLog"]
            break
         end if
         put tBodyA["street"] into tStreetName
         put tBodyA["head"] into tHeadHex
         put tBodyA["sig"] into tSigHex
         if tStreetName is not among the items of kHeCkptStreets \
               or not heIsHex(tHeadHex, 64) \
               or not heCkptVerify(tSigHex, tHeadHex, pFromHex) then
            put "drop   bad ckpt from seat " & tFromSeat & return after gGame["netLog"]
            break
         end if
         put gGame["oDeal"]["ckptHeadBy"][tStreetName] into tCkptHead
         if tCkptHead is not empty and tHeadHex is not tCkptHead then
            put "CKPT-FORK seat " & tFromSeat & " signed a different " & tStreetName \
                  & " head -- host equivocation evidence" & return after gGame["netLog"]
            break
         end if
         if gGame["oDeal"]["ckptsBy"][tStreetName & ":" & tFromSeat] is empty then
            put tSigHex into gGame["oDeal"]["ckptsBy"][tStreetName & ":" & tFromSeat]
         end if
         break

      case "show"
      case "muck"
         -- 2e showdown display choice (spec 6/8.1): first-class wires, but
         -- DISPLAY only by construction -- online ranks derive from the
         -- revealed seeds, so a muck hides nothing from the audit, only
         -- from the felt. Seat-scoped: the sender must own the seat it
         -- declares for.
         if tFromSeat is 0 then
            put "drop   " & pTypeTxt & " from an unseated key" & return after gGame["netLog"]
            break
         end if
         put tBodyA["seat"] into tSeat
         if tSeat is not a number or tSeat is not tFromSeat then
            put "drop   " & pTypeTxt & " for a seat the sender does not own" & return after gGame["netLog"]
            break
         end if
         if gGame["oDeal"]["showBy"][tFromSeat] is empty then
            put pTypeTxt into gGame["oDeal"]["showBy"][tFromSeat]
            if pTypeTxt is "show" then
               put "show   seat " & tFromSeat & " shows its hand" & return after gGame["netLog"]
               heNetShowSeat tFromSeat
            else
               put "muck   seat " & tFromSeat & " mucks (cards stay down)" & return after gGame["netLog"]
            end if
         end if
         break

   end switch
   heNetGameReact
end heNetFoldGameWire

function heNetCfgVal pKey, pDefault
   -- one numeric value out of the signed table cfg body ("k=v,k=v" text);
   -- copy-then-split keeps every chunk on a plain local (H6)
   local tBodyA, tVal
   set the itemDelimiter to comma
   put gGame["cfgBody"] into tBodyA
   split tBodyA by comma and "="
   put tBodyA[pKey] into tVal
   if tVal is not a number then
      return pDefault
   end if
   return tVal
end heNetCfgVal

command heNetGameReact
   -- the per-client reaction to the folded transcript: emit ONLY what our
   -- seat owes next, each emission behind a per-hand sent-flag so redelivery
   -- and replay never double-send. Runs after every applied wire.
   local tMySeat, tOccList, tStateA, tCount, tPos, tSeedHex, tSealedHex, tRndErr
   local tDealerSeat, tDealerPubHex, tDealerBoxHex, tBoardTxt, tBoardN, tStreetTxt
   local tDeltasTxt, tHeadHex, tSigHex, tResultTxt, tSealErr, tAllPosted, tSeatNum
   local tMyPubHex, tContribN, tCkStreet, tCkHead, tInList, tMyDelta, tChoiceTxt
   if gGame["online"] is not "true" then
      exit heNetGameReact
   end if
   -- CATCH-UP SUPPRESSION: while a host replay is streaming (announced by the
   -- "r!" marker), every mid-replay state is HISTORICAL -- reacting to it
   -- would re-emit join/commit/seal/reveal for every hand replayed and
   -- pollute the live chain with sequenced duplicates. Stay silent until our
   -- applied seq reaches the announced head, then react once against the
   -- complete transcript, where the presence guards see the whole truth.
   if gGame["catchUpTo"] is a number then
      if gGame["lastSeq"] < gGame["catchUpTo"] then
         exit heNetGameReact
      end if
      put empty into gGame["catchUpTo"]
   end if
   -- 1. bind our session box key once the roster lists us (spec 5): the signed
   -- contentLine over table + from + box IS the binding tuple. Presence-guarded
   -- (the transcript already carrying our box means a reconnect replay, not a
   -- first join).
   put gGame["idPubHex"] into tMyPubHex
   if gGame["joinSent"] is not "true" and gGame["boxPubData"] is not empty \
         and gGame["boxByPub"][tMyPubHex] is empty \
         and gGame["rosterBody"] contains tMyPubHex then
      put "true" into gGame["joinSent"]
      heNetSendAction "join", "box=" & heBin2HexS(gGame["boxPubData"])
   end if
   if gGame["gameOn"] is not "true" then
      exit heNetGameReact
   end if
   -- 1b. HOST: a table PARKED for sit-outs resumes the moment the transcript
   -- says two seats are dealable again (v0.24.0, F6). This is the half that
   -- actually heals the parked table: the sit-return fold only cleared
   -- sitOutBy/missCntBy, so with autoNext off (or after the between-hands
   -- beat had died on a park that came from heNetStartGame) the returning
   -- player saw Return succeed and the table simply never dealt again.
   -- Reacting is the house shape for this -- it runs after every applied
   -- wire, on the same pass that folded the return, so no timer has to be
   -- alive -- and the latch is its own debounce: heNetHandKick clears
   -- handWait as soon as it deals, and leaves it set if the table is still
   -- short, so this can never loop.
   if gGame["isHost"] is "true" and gGame["handWait"] is "true" then
      set the itemDelimiter to comma
      if the number of items of heNetNextOccList() >= 2 then
         put "hand   a returning player unparks the table" & return after gGame["netLog"]
         heNetHandKick
      end if
   end if
   put heNetMySeat() into tMySeat
   put gGame["oDeal"]["dealerSeat"] into tDealerSeat
   put gGame["oDeal"]["dealCount"] into tCount
   set the itemDelimiter to comma
   put gGame["state"]["occ"] into tOccList
   if tOccList is empty or tCount is not a number or tCount is 0 then
      exit heNetGameReact   -- no hand open, or dealLevel not folded yet
   end if
   -- Phase 3: tPos is our CONTRIBUTOR position (a seat's packed position;
   -- the dealing oracle takes the extra slot dealCount+1) and tContribN the
   -- number of contributors the commit/seal/reveal thresholds wait for
   put heNetMyContribPos() into tPos
   put heNetContribCount() into tContribN
   -- 2. our deal entropy (spec 7.1 step 1; freshness law, spec 5). The seed is
   -- DERIVED, not drawn: H(domain || idSeed || table || hand) -- secret-keyed
   -- and fresh per hand, but reconstructible, so a client that crashed and
   -- reconnected mid-hand re-derives the exact seed it committed and can
   -- still reveal at hand end (spec 9). The commit is only EMITTED when the
   -- transcript does not already carry it (presence guard: replay-proof) and
   -- this run has not just sent it (flag: redelivery debounce).
   if tPos > 0 and gGame["oDeal"]["mySeedHex"] is empty then
      try
         put heNetHandSeedHex() into tSeedHex
         put tSeedHex into gGame["oDeal"]["mySeedHex"]
      catch tRndErr
         put "ERROR  could not derive deal entropy" & return after gGame["netLog"]
      end try
   end if
   if tPos > 0 and gGame["oDeal"]["mySeedHex"] is not empty \
         and gGame["oDeal"]["commitSent"] is not "true" \
         and gGame["oDeal"]["commitsBy"][tPos] is empty then
      put "true" into gGame["oDeal"]["commitSent"]
      heNetSendAction "seedCommit", "pos=" & tPos & ",commit=" \
            & heSeedCommitHex(gGame["oDeal"]["mySeedHex"])
   end if
   -- 3. seal our seed to the dealer (spec 7.1 step 2) once every commit is in
   -- (committing BEFORE any seed travels is what stops the dealer stacking).
   -- At level 1 the dealer is the ORACLE: seats seal to its session box, and
   -- the oracle "seals to itself" too, so the transcript carries every
   -- contributor's seal uniformly and the counts stay simple.
   if tPos > 0 and gGame["oDeal"]["commitN"] >= tContribN \
         and gGame["oDeal"]["sealSent"] is not "true" \
         and gGame["oDeal"]["sealsBy"][tPos] is empty then
      put heNetDealerPubHex() into tDealerPubHex
      put gGame["boxByPub"][tDealerPubHex] into tDealerBoxHex
      if heIsHex(tDealerBoxHex, 64) then
         put "true" into gGame["oDeal"]["sealSent"]
         try
            put heBin2HexS(sxSeal(textEncode(gGame["oDeal"]["mySeedHex"], "utf-8"), \
                  heHex2BinD(tDealerBoxHex))) into tSealedHex
            heNetSendAction "seedSeal", "pos=" & tPos & ",sealed=" & tSealedHex
         catch tSealErr
            put "ERROR  could not seal the seed to the dealer" & return after gGame["netLog"]
         end try
      end if
   end if
   -- 4. we deal this hand: open the seals, verify, derive, deliver. Runs
   -- whenever the derived deck is missing -- covers the fresh deal AND a
   -- dealer that reconnected mid-hand (it re-opens the replayed seals and
   -- re-derives; per-seat delivery inside is presence-guarded, so seats the
   -- transcript already served are never re-sent). heNetWeDeal: the button
   -- seat at level 0, the seatless ORACLE at level 1.
   if heNetWeDeal() and gGame["oDeal"]["sealN"] >= tContribN \
         and gGame["oDeal"]["dealerDealA"] is not an array then
      heNetDealerDeal
   end if
   -- 5. blinds once every seat has its (sealed) holes. Antes first (dead
   -- money), then the SB, and the BB only after it SEES the SB fold -- so the
   -- two forced posts can never race in the relay's ordering. Seats only
   -- (tMySeat > 0): the oracle contributes entropy, never chips.
   if gGame["oDeal"]["holeN"] >= tCount and tPos > 0 and tMySeat > 0 then
      put gGame["state"] into tStateA
      if tStateA["phase"] is "blinds" then
         if gGame["ante"] > 0 and gGame["oDeal"]["anteSent"] is not "true" \
               and tStateA["antePostedBy"][tMySeat] is not "true" then
            put "true" into gGame["oDeal"]["anteSent"]
            heNetSendAction "bidAnte", "amount=" & min(gGame["ante"], tStateA["stackBy"][tMySeat])
         end if
         put "true" into tAllPosted
         if gGame["ante"] > 0 then
            repeat for each item tSeatNum in tOccList
               if tStateA["antePostedBy"][tSeatNum] is not "true" then
                  put "false" into tAllPosted
               end if
            end repeat
         end if
         if tAllPosted is "true" and tMySeat is tStateA["sbSeat"] \
               and tStateA["sbPosted"] is not "true" and gGame["oDeal"]["sbSent"] is not "true" then
            put "true" into gGame["oDeal"]["sbSent"]
            heNetSendAction "bidSB", "amount=" & min(tStateA["sb"], tStateA["stackBy"][tMySeat])
         end if
         if tStateA["sbPosted"] is "true" and tMySeat is tStateA["bbSeat"] \
               and gGame["oDeal"]["bbSent"] is not "true" then
            put "true" into gGame["oDeal"]["bbSent"]
            heNetSendAction "bidBB", "amount=" & min(tStateA["bb"], tStateA["stackBy"][tMySeat])
         end if
      end if
   end if
   -- 6. we deal this hand and a street is due (live close or runout)
   if heNetWeDeal() then
      put gGame["state"] into tStateA
      put gGame["oDeal"]["boardList"] into tBoardTxt
      put the number of items of tBoardTxt into tBoardN
      put empty into tStreetTxt
      if tStateA["phase"] is "acting" or tStateA["phase"] is "runout" then
         if tBoardN is 0 and (tStateA["street"] is not "preflop" or tStateA["phase"] is "runout") then
            put "flop" into tStreetTxt
         else if tBoardN is 3 and (tStateA["street"] is "turn" or tStateA["street"] is "river" \
               or tStateA["phase"] is "runout") then
            put "turn" into tStreetTxt
         else if tBoardN is 4 and (tStateA["street"] is "river" or tStateA["phase"] is "runout") then
            put "river" into tStreetTxt
         end if
      end if
      if tStreetTxt is not empty then
         heNetDealerBoard tStreetTxt
      end if
   end if
   -- 6b. street checkpoints (2e, spec 6): each SEATED client signs the head
   -- every recorded boundary produced -- the transition wire's head, so
   -- every honest ckpt for one boundary names the same bytes and a
   -- disagreement is fork evidence, not timing. One wire per street per
   -- seat, presence-guarded against the transcript like every emission.
   if tMySeat > 0 and tPos > 0 then
      set the itemDelimiter to comma   -- gotcha 5: set before every parse
      repeat for each item tCkStreet in kHeCkptStreets
         put gGame["oDeal"]["ckptHeadBy"][tCkStreet] into tCkHead
         if tCkHead is not empty \
               and gGame["oDeal"]["ckptSentBy"][tCkStreet] is not "true" \
               and gGame["oDeal"]["ckptsBy"][tCkStreet & ":" & tMySeat] is empty then
            put "true" into gGame["oDeal"]["ckptSentBy"][tCkStreet]
            heNetSendAction "ckpt", heCkptBodyTxt(tCkStreet, tCkHead, gGame["idSecData"])
         end if
      end repeat
   end if
   -- 7. the action display (wires do the state; this is only the prompt)
   put gGame["state"] into tStateA
   if tStateA["phase"] is "acting" then
      if tStateA["toAct"] is tMySeat then
         heUIPromptToAct
      else
         heDisableActions
         heUISetStatus "Waiting for seat " & tStateA["toAct"] & " to act..."
      end if
   end if
   -- 8. hand over: reveal our seed so everyone can audit (spec 7.1 step 5)
   if (tStateA["phase"] is "showdown" or tStateA["phase"] is "handdone") \
         and tPos > 0 and gGame["oDeal"]["revealSent"] is not "true" \
         and gGame["oDeal"]["revealsBy"][tPos] is empty \
         and gGame["oDeal"]["mySeedHex"] is not empty then
      put "true" into gGame["oDeal"]["revealSent"]
      heNetSendAction "seedReveal", "pos=" & tPos & ",seed=" & gGame["oDeal"]["mySeedHex"]
   end if
   -- 9. host: emit the settle once every seed is revealed (the oracle's own
   -- reveal included); every client will verify it against its own
   -- recomputation before folding it
   if gGame["isHost"] is "true" and gGame["oDeal"]["revealN"] >= tContribN \
         and gGame["oDeal"]["settleSent"] is not "true" \
         and (tStateA["phase"] is "showdown" or tStateA["phase"] is "handdone") then
      put heNetComputeSettleTxt() into tDeltasTxt
      if tDeltasTxt is not empty then
         put "true" into gGame["oDeal"]["settleSent"]
         heNetSendAction "settle", "deltas=" & tDeltasTxt
      end if
   end if
   -- 10. co-sign the settlement receipt (spec 8.3, chained hand to hand).
   -- SEATED players only: a receipt is the seats' multi-signature over the
   -- ledger; the stakeless oracle signs no receipts.
   if gGame["oDeal"]["settleDone"] is "true" and tPos > 0 and tMySeat > 0 \
         and gGame["oDeal"]["receiptSent"] is not "true" \
         and gGame["oDeal"]["receiptsBy"][tMySeat] is empty then
      put "true" into gGame["oDeal"]["receiptSent"]
      put gGame["rcptHeadHex"] into tHeadHex
      put heReceiptSigHex(tHeadHex, gGame["idSecData"]) into tSigHex
      heNetSendAction "receipt", "head=" & tHeadHex & ",sig=" & tSigHex
   end if
   -- 11. our audit verdict (spec 7.1 step 5)
   if gGame["oDeal"]["settleDone"] is "true" and tPos > 0 \
         and gGame["oDeal"]["auditSent"] is not "true" \
         and gGame["oDeal"]["auditsBy"][tMySeat] is empty then
      put "true" into gGame["oDeal"]["auditSent"]
      put heNetAuditHand() into tResultTxt
      heNetSendAction "audit", "result=" & tResultTxt
   end if
   -- 11b. show/muck (2e): our showdown display CHOICE, once the verified
   -- settle told us the outcome. As-built policy: a contested seat with a
   -- non-negative delta SHOWS (a claimed pot is a shown hand -- and at L0
   -- the seeds already proved it), a contested loser MUCKS, an uncontested
   -- winner MUCKS (a fold-win owes nobody a look), and a seat that folded
   -- earlier emits nothing (it already mucked face-down). Display only:
   -- ranks and settlement derive from the revealed seeds either way.
   if gGame["oDeal"]["settleDone"] is "true" and tMySeat > 0 \
         and gGame["oDeal"]["showSent"] is not "true" \
         and gGame["oDeal"]["showBy"][tMySeat] is empty then
      set the itemDelimiter to comma   -- gotcha 5: set before every parse
      put heBetInHandList(gGame["state"]) into tInList
      if tMySeat is among the items of tInList then
         put "true" into gGame["oDeal"]["showSent"]
         put heDeltaOfTxt(gGame["oDeal"]["settleDeltas"], tMySeat) into tMyDelta
         if heCountItems(tInList) > 1 and tMyDelta >= 0 then
            put "show" into tChoiceTxt
         else
            put "muck" into tChoiceTxt
         end if
         heNetSendAction tChoiceTxt, "seat=" & tMySeat
      end if
   end if
   -- 12. host: the between-hands beat, then the next hand deals itself
   if gGame["isHost"] is "true" and gGame["autoNext"] is "true" \
         and gGame["oDeal"]["settleDone"] is "true" \
         and gGame["oDeal"]["nextArmed"] is not "true" then
      put "true" into gGame["oDeal"]["nextArmed"]
      send "heNetNextHandTick" to me in hePaceMs("paceNext", kHeNextHandDelayMs) milliseconds
   end if
end heNetGameReact

command heNetDealerDeal
   -- we are this hand's dealer: open every sealed seed with our session key,
   -- verify each against its commitment (a mismatch aborts the deal, named),
   -- derive the committed deck, and send each seat its two hole cards sealed
   -- to ITS session key (spec 7.1 steps 3-4)
   local tPos, tCount, tSeedsA, tSealedHex, tSeedHex, tOpenErr, tBad
   local tDealA, tOccList, tSeatNum, tHolePair, tPeerPubHex, tPeerBoxHex
   local tSealErr, tSealedOut
   set the itemDelimiter to comma
   -- Phase 3: the loop runs over CONTRIBUTOR positions -- every seat plus,
   -- at level 1, the oracle's own seal at dealCount+1 (it opens its own box)
   put heNetContribCount() into tCount
   put "false" into tBad
   repeat with tPos = 1 to tCount
      put gGame["oDeal"]["sealsBy"][tPos] into tSealedHex
      put empty into tSeedHex
      try
         put textDecode(sxSealOpen(heHex2BinD(tSealedHex), gGame["boxPubData"], \
               gGame["boxSecData"]), "utf-8") into tSeedHex
      catch tOpenErr
         put empty into tSeedHex
      end try
      if not heIsHex(tSeedHex, 64) \
            or heSeedCommitHex(tSeedHex) is not gGame["oDeal"]["commitsBy"][tPos] then
         put "AUDIT  seal at pos " & tPos & " bad or commit-mismatched -- deal aborted" & return after gGame["netLog"]
         put "true" into tBad
      end if
      put tSeedHex into tSeedsA[tPos]
   end repeat
   if tBad is "true" then
      heUISetStatus "Deal aborted: a sealed seed failed its commitment. See the net feed."
      exit heNetDealerDeal
   end if
   put heNetDealFromSeeds(tSeedsA, tCount) into tDealA
   put tDealA into gGame["oDeal"]["dealerDealA"]
   put gGame["state"]["occ"] into tOccList
   repeat for each item tSeatNum in tOccList
      -- presence-guarded per seat: a reconnected dealer re-derives the deck
      -- above but never re-sends a delivery the transcript already carries
      if gGame["oDeal"]["holeSealedBy"][tSeatNum] is empty then
         put tDealA["holesBy"][tSeatNum] into tHolePair
         put gGame["pubBySeat"][tSeatNum] into tPeerPubHex
         put gGame["boxByPub"][tPeerPubHex] into tPeerBoxHex
         try
            put heBin2HexS(sxSeal(textEncode(tHolePair, "utf-8"), heHex2BinD(tPeerBoxHex))) into tSealedOut
            heNetSendAction "holeDeliver", "seat=" & tSeatNum & ",sealed=" & tSealedOut
         catch tSealErr
            put "ERROR  could not seal holes for seat " & tSeatNum & return after gGame["netLog"]
         end try
      end if
   end repeat
end heNetDealerDeal

function heNetHandSeedHex
   -- the per-hand deal seed: H(domain || idSeed || "|" || table || "|" ||
   -- hand), hex end to end through the standing crypto seams. Secret-keyed by
   -- the identity seed (it never leaves the machine), fresh per hand (the
   -- hand number is in the input, spec 5 freshness law), and DETERMINISTIC --
   -- a reconnecting client re-derives the exact seed it committed, so it can
   -- still seal and reveal after a crash (spec 9).
   return heHashDomHex(kHeDomainSeedP, textEncode(gGame["idSeedHex"] & "|" \
         & gGame["tableIdHex"] & "|" & gGame["handNum"], "utf-8"))
end heNetHandSeedHex

function heNetDealFromSeeds pSeedsA, pCount
   -- the committed keyed-stream deal (spec 7.1 step 3) from position-indexed
   -- seed hex: XOR -> stream key -> deck -> assignment. Same code whether the
   -- seeds came out of sealed boxes (dealer, at deal time) or public reveals
   -- (every client, at audit/settle time) -- which is the point: one pinned
   -- derivation, two moments.
   local tXorHex, tKeyData, tDeckList
   put heXorSeedsHex(pSeedsA, pCount) into tXorHex
   put heStreamKeyData(heHex2BinD(gGame["tableIdHex"]), gGame["handNum"], tXorHex) into tKeyData
   put heDeckFromStreamKey(tKeyData) into tDeckList
   return heDealAssign(tDeckList, gGame["state"]["occ"], gGame["buttonSeat"])
end heNetDealFromSeeds

command heNetDealerBoard pStreetTxt
   -- dealer: broadcast one street from the deck derived at deal time
   local tDealA, tIdxList, tNamesTxt, tOneCard
   set the itemDelimiter to comma
   put gGame["oDeal"]["dealerDealA"] into tDealA
   if tDealA is not an array then
      exit heNetDealerBoard
   end if
   switch pStreetTxt
      case "flop"
         put tDealA["flopList"] into tIdxList
         break
      case "turn"
         put tDealA["turnIx"] into tIdxList
         break
      case "river"
         put tDealA["riverIx"] into tIdxList
         break
      default
         exit heNetDealerBoard
   end switch
   put empty into tNamesTxt
   repeat for each item tOneCard in tIdxList
      put heCardName(tOneCard) & "|" after tNamesTxt
   end repeat
   if tNamesTxt is not empty then
      delete char -1 of tNamesTxt
   end if
   heNetSendAction "board", "street=" & pStreetTxt & ",cards=" & tNamesTxt
end heNetDealerBoard

function heNetRevealedDealA
   -- after every seed is revealed: re-derive the whole committed deal.
   -- Empty until the reveals are complete. Contributor positions, not
   -- seats: at level 1 the oracle's reveal at dealCount+1 is part of the
   -- XOR, so the audit covers it too.
   local tCount, tPos, tSeedsA, tSeedHex
   put heNetContribCount() into tCount
   if tCount is not a number or tCount is 0 then
      return empty
   end if
   if gGame["oDeal"]["revealN"] < tCount then
      return empty
   end if
   repeat with tPos = 1 to tCount
      put gGame["oDeal"]["revealsBy"][tPos] into tSeedHex
      put tSeedHex into tSeedsA[tPos]
   end repeat
   return heNetDealFromSeeds(tSeedsA, tCount)
end heNetRevealedDealA

function heNetComputeSettleTxt
   -- the deterministic settlement every client computes for itself: showdown
   -- ranks come from the REVEALED deck (a player cannot lie about its holes),
   -- deltas from the same pure heSettleOf the hotseat uses. Standard
   -- "seat:delta|..." format over the hand's occupied seats.
   local tDealA, tStateA, tRanksA, tDeltasA, tInList, tSeatNum, tHolePair
   local tSevenList, tOutTxt, tOccList
   set the itemDelimiter to comma
   put heNetRevealedDealA() into tDealA
   if tDealA is not an array then
      return empty
   end if
   put gGame["state"] into tStateA
   put heBetInHandList(tStateA) into tInList
   put empty into tRanksA
   if heCountItems(tInList) > 1 then
      repeat for each item tSeatNum in tInList
         put tDealA["holesBy"][tSeatNum] into tHolePair
         put tHolePair & comma & tDealA["flopList"] & comma & tDealA["turnIx"] \
               & comma & tDealA["riverIx"] into tSevenList
         put heEval7(tSevenList) into tRanksA[tSeatNum]
      end repeat
   end if
   put heSettleOf(tStateA, tRanksA) into tDeltasA
   put empty into tOutTxt
   put tStateA["occ"] into tOccList
   repeat for each item tSeatNum in tOccList
      put tSeatNum & ":" & tDeltasA[tSeatNum] & "|" after tOutTxt
   end repeat
   if tOutTxt is not empty then
      delete char -1 of tOutTxt
   end if
   return tOutTxt
end heNetComputeSettleTxt

command heNetApplySettle pDeltasTxt
   -- fold the verified settle: move the stacks, advance the receipt chain
   -- (spec 8.3: settleHash binds the deltas to the settle wire's own chain
   -- head; the receipt head chains hand to hand), show the showdown, and
   -- drop to the between-hands phase
   local tPairTxt, tSeatNum, tDeltaAmt, tDeltasCSV, tSettleHash, tColonPos
   set the itemDelimiter to "|"
   put empty into tDeltasCSV
   repeat for each item tPairTxt in pDeltasTxt
      put offset(":", tPairTxt) into tColonPos
      if tColonPos > 0 then
         put char 1 to (tColonPos - 1) of tPairTxt into tSeatNum
         put char (tColonPos + 1) to -1 of tPairTxt into tDeltaAmt
         if tSeatNum is a number and tDeltaAmt is a number then
            add tDeltaAmt to gGame["stacksBy"][tSeatNum]
         end if
         put tSeatNum & ":" & tDeltaAmt & comma after tDeltasCSV
      end if
   end repeat
   set the itemDelimiter to comma
   if tDeltasCSV is not empty then
      delete char -1 of tDeltasCSV
   end if
   put heSettleHashHex(tDeltasCSV, heHex2BinD(gGame["chainHeadHex"])) into tSettleHash
   put heReceiptHeadHex(tSettleHash, gGame["rcptHeadHex"]) into gGame["rcptHeadHex"]
   put "true" into gGame["oDeal"]["settleDone"]
   -- 2e show/muck: keep the verified deltas so the react engine can decide
   -- our display choice (winner shows, contested loser mucks)
   put pDeltasTxt into gGame["oDeal"]["settleDeltas"]
   put "between" into gGame["phase"]
   heNetShowdownShow
   heUISetStatus "Hand " & gGame["handNum"] & " settled: " & pDeltasTxt
   heHudMark
end heNetApplySettle

function heNetAuditHand
   -- our per-client audit verdict (spec 7.1 step 5): re-derive the committed
   -- deal from the reveals and check it against what we WITNESSED -- the
   -- commitments, the wired board, and OUR OWN delivered holes. (Another
   -- seat's sealed delivery can only be checked by that seat; its own audit
   -- covers it.)
   local tDealA, tMySeat, tMyHoles, tBoardTxt, tCommitsA, tSeedsA, tPos, tCount
   local tBoardN
   set the itemDelimiter to comma
   put heNetRevealedDealA() into tDealA
   if tDealA is not an array then
      return "fail:reveals-incomplete"
   end if
   put heNetMySeat() into tMySeat
   put gGame["oDeal"]["myHoles"] into tMyHoles
   if tMySeat > 0 and tMyHoles is not empty then
      put tMyHoles into tDealA["holesBy"][tMySeat]
   end if
   put gGame["oDeal"]["boardList"] into tBoardTxt
   put the number of items of tBoardTxt into tBoardN
   if tBoardN >= 3 then
      put item 1 to 3 of tBoardTxt into tDealA["flopList"]
   end if
   if tBoardN >= 4 then
      put item 4 of tBoardTxt into tDealA["turnIx"]
   end if
   if tBoardN >= 5 then
      put item 5 of tBoardTxt into tDealA["riverIx"]
   end if
   put heNetContribCount() into tCount
   repeat with tPos = 1 to tCount
      put gGame["oDeal"]["commitsBy"][tPos] into tCommitsA[tPos]
      put gGame["oDeal"]["revealsBy"][tPos] into tSeedsA[tPos]
   end repeat
   return heAuditDeal(heHex2BinD(gGame["tableIdHex"]), gGame["handNum"], tSeedsA, \
         tCommitsA, tCount, tDealA, gGame["state"]["occ"], gGame["buttonSeat"])
end heNetAuditHand

command heNetShowBoard
   -- render the wired board through the hotseat board display path
   local tBoardTxt, tBoardN
   set the itemDelimiter to comma
   put gGame["oDeal"]["boardList"] into tBoardTxt
   put the number of items of tBoardTxt into tBoardN
   if tBoardN >= 3 then
      heUIShowBoardStreet "flop", (item 1 to 3 of tBoardTxt)
   end if
   if tBoardN >= 4 then
      heUIShowBoardStreet "turn", (item 4 of tBoardTxt)
   end if
   if tBoardN >= 5 then
      heUIShowBoardStreet "river", (item 5 of tBoardTxt)
   end if
end heNetShowBoard

command heNetShowdownShow
   -- at settle time only OUR OWN cards go up (they were always ours to
   -- look at); every OTHER contested seat's cards appear when ITS show wire
   -- folds (heNetShowSeat) -- the 2e show/muck display choice made real. A
   -- mucked seat's cards simply never paint; the audit saw them anyway
   -- (ranks derive from the revealed seeds -- display, not correctness).
   local tMySeat, tMyHoles
   put heNetMySeat() into tMySeat
   put gGame["oDeal"]["myHoles"] into tMyHoles
   if tMySeat > 0 and tMyHoles is not empty then
      heUIShowHole tMySeat, tMyHoles
   end if
end heNetShowdownShow

command heNetShowSeat pSeatNum
   -- reveal ONE seat's cards on its folded show wire, derived from the
   -- revealed seeds (the transcript's truth, never the seat's claim)
   local tDealA, tHolePair
   set the itemDelimiter to comma
   put heNetRevealedDealA() into tDealA
   if tDealA is not an array then
      exit heNetShowSeat
   end if
   put tDealA["holesBy"][pSeatNum] into tHolePair
   if tHolePair is not empty then
      heUIShowHole pSeatNum, tHolePair
   end if
end heNetShowSeat

function heDeltaOfTxt pDeltasTxt, pSeatNum
   -- one seat's delta out of the settle body's "seat:delta|..." text; 0 when
   -- absent/malformed. Pure; every chunk is of a plain local (H6).
   local tPairTxt, tColonPos, tSeatTxt, tAmtTxt, tSaved
   put the itemDelimiter into tSaved
   set the itemDelimiter to "|"
   repeat for each item tPairTxt in pDeltasTxt
      put offset(":", tPairTxt) into tColonPos
      if tColonPos > 0 then
         put char 1 to (tColonPos - 1) of tPairTxt into tSeatTxt
         put char (tColonPos + 1) to -1 of tPairTxt into tAmtTxt
         if tSeatTxt is pSeatNum and tAmtTxt is a number then
            set the itemDelimiter to tSaved
            return tAmtTxt
         end if
      end if
   end repeat
   set the itemDelimiter to tSaved
   return 0
end heDeltaOfTxt

--------------------------------------------------------------------------
-- small pure utilities
--------------------------------------------------------------------------

function heTwoDigits pNum
   if pNum < 10 then
      return "0" & pNum
   end if
   return pNum
end heTwoDigits

function heCountItems pList
   set the itemDelimiter to comma
   if pList is empty then
      return 0
   end if
   return the number of items of pList
end heCountItems

function heNextInList pList, pEntry
   -- circular successor of pEntry in a comma list
   local tPos, tCount
   set the itemDelimiter to comma
   put the number of items of pList into tCount
   repeat with tPos = 1 to tCount
      if item tPos of pList is pEntry then
         if tPos is tCount then
            return item 1 of pList
         end if
         return item (tPos + 1) of pList
      end if
   end repeat
   return item 1 of pList
end heNextInList

function heRotateAfter pList, pEntry
   -- the list re-ordered to start just after pEntry (deal / action order)
   local tPos, tCount, tOut
   set the itemDelimiter to comma
   put the number of items of pList into tCount
   repeat with tPos = 1 to tCount
      if item tPos of pList is pEntry then
         if tPos is tCount then
            return pList
         end if
         put item (tPos + 1) to tCount of pList & comma & item 1 to tPos of pList into tOut
         return tOut
      end if
   end repeat
   return pList
end heRotateAfter

function heNextLiveAfterPos pLiveList, pPos
   -- next live seat strictly after physical position pPos, circular over the
   -- live seats -- works even when pPos itself is not live (a busted seat).
   -- pLiveList must be ascending.
   local tSeatNum
   set the itemDelimiter to comma
   repeat for each item tSeatNum in pLiveList
      if tSeatNum > pPos then
         return tSeatNum
      end if
   end repeat
   return item 1 of pLiveList
end heNextLiveAfterPos

function hePrevLiveBeforePos pLiveList, pPos
   -- previous live seat strictly before physical position pPos, circular
   local tSeatNum, tPrev
   set the itemDelimiter to comma
   put item -1 of pLiveList into tPrev
   repeat for each item tSeatNum in pLiveList
      if tSeatNum < pPos then
         put tSeatNum into tPrev
      end if
   end repeat
   return tPrev
end hePrevLiveBeforePos

function heScheduleButton pLiveList, pLastBB
   -- dead-button-aware blind schedule (TDA rule 10, simplified to always post
   -- a live small blind): the big blind ALWAYS advances to the next live seat
   -- clockwise from the previous big blind, so nobody posts it twice running
   -- and no live seat skips it across an elimination. Returns the button seat;
   -- heBetNewHand then derives SB = next live after button, BB = next after SB
   -- (heads-up: button IS the SB), which reproduces this schedule exactly.
   local tBB, tSB
   set the itemDelimiter to comma
   if pLastBB is 0 then
      return item 1 of pLiveList
   end if
   put heNextLiveAfterPos(pLiveList, pLastBB) into tBB
   put hePrevLiveBeforePos(pLiveList, tBB) into tSB
   if heCountItems(pLiveList) is 2 then
      return tSB
   end if
   return hePrevLiveBeforePos(pLiveList, tSB)
end heScheduleButton

function heHexId pLen
   -- a random lowercase-hex id built char by char (no binary, no FFI): a
   -- display/table handle only, not dealing- or key-related
   local tOut, tI
   put empty into tOut
   repeat pLen times
      put char (random(16)) of "0123456789abcdef" after tOut
   end repeat
   return tOut
end heHexId

--------------------------------------------------------------------------
-- cards (contract pinned in tools/evaluator-kat.py)
--------------------------------------------------------------------------

function heCardRankVal pIdx
   return (pIdx - 1) div 4 + 2
end heCardRankVal

function heCardSuitVal pIdx
   return (pIdx - 1) mod 4 + 1
end heCardSuitVal

function heCardName pIdx
   local tRankPos, tSuitPos
   put (pIdx - 1) div 4 + 1 into tRankPos
   put (pIdx - 1) mod 4 + 1 into tSuitPos
   return char tRankPos of kHeRankChars & char tSuitPos of kHeSuitChars
end heCardName

function heCardIndex pName
   local tRankVal, tSuitVal, tNameTxt
   put pName into tNameTxt
   put offset(char 1 of tNameTxt, kHeRankChars) + 1 into tRankVal
   put offset(char 2 of tNameTxt, kHeSuitChars) into tSuitVal
   return (tRankVal - 2) * 4 + tSuitVal
end heCardIndex

--------------------------------------------------------------------------
-- hand evaluator (spec 8.2) -- pure, pinned by tools/evaluator-kat.py.
-- Result: 12-char packed string, six 2-digit fields, category then five
-- tiebreak ranks; fixed width so plain numeric comparison orders hands.
--------------------------------------------------------------------------

function heRank5 pFive
   -- pFive: comma list of exactly five card indices
   local tRankList, tSuitList, tPos, tIdx, tFlush, tDistinct, tHighStraight
   local tCountA, tRankVal, tGroupLines, tSizes, tGRanks, tOut
   set the itemDelimiter to comma
   put empty into tRankList
   put empty into tSuitList
   repeat for each item tIdx in pFive
      put heCardRankVal(tIdx) & comma after tRankList
      put heCardSuitVal(tIdx) & comma after tSuitList
   end repeat
   delete char -1 of tRankList
   delete char -1 of tSuitList
   sort items of tRankList numeric descending

   -- flush: all five suits equal
   put true into tFlush
   repeat with tPos = 2 to 5
      if item tPos of tSuitList is not item 1 of tSuitList then
         put false into tFlush
      end if
   end repeat

   -- straight: five distinct ranks spanning 4, or the wheel (A-5-4-3-2)
   put empty into tDistinct
   repeat with tPos = 1 to 5
      if item tPos of tRankList is not among the items of tDistinct then
         put item tPos of tRankList & comma after tDistinct
      end if
   end repeat
   delete char -1 of tDistinct
   put 0 into tHighStraight
   if the number of items of tDistinct is 5 then
      if (item 1 of tDistinct) - (item 5 of tDistinct) is 4 then
         put item 1 of tDistinct into tHighStraight
      else if tDistinct is "14,5,4,3,2" then
         put 5 into tHighStraight
      end if
   end if

   if tFlush and tHighStraight > 0 then
      return "08" & heTwoDigits(tHighStraight) & "00000000"
   end if

   -- histogram: sort groups by (count, rank) descending in ONE pass. The sort
   -- key is PRECOMPUTED as item 1 (count * 100 + rank; rank <= 14 < 100, so
   -- count dominates and rank breaks ties), then we sort by that single field
   -- with the proven "by item 1 of each" form. So correctness depends neither
   -- on LiveCode's sort being stable NOR on an arithmetic sort-by expression --
   -- both are removed. Each line is "sortKey,count,rank" (frequencies +
   -- order-isomorphism pinned in tools/logic-fuzz.py).
   repeat with tPos = 1 to 5
      put item tPos of tRankList into tRankVal
      if tCountA[tRankVal] is empty then
         put 0 into tCountA[tRankVal]
      end if
      add 1 to tCountA[tRankVal]
   end repeat
   put empty into tGroupLines
   repeat for each key tRankVal in tCountA
      put (tCountA[tRankVal] * 100 + tRankVal) & comma & tCountA[tRankVal] & comma & tRankVal & return after tGroupLines
   end repeat
   delete char -1 of tGroupLines
   sort lines of tGroupLines numeric descending by item 1 of each
   put empty into tSizes
   put empty into tGRanks
   repeat for each line tOut in tGroupLines
      put item 2 of tOut & comma after tSizes
      put item 3 of tOut & comma after tGRanks
   end repeat
   delete char -1 of tSizes
   delete char -1 of tGRanks

   if item 1 of tSizes is 4 then
      return "07" & heTwoDigits(item 1 of tGRanks) & heTwoDigits(item 2 of tGRanks) & "000000"
   end if
   if item 1 of tSizes is 3 and item 2 of tSizes is 2 then
      return "06" & heTwoDigits(item 1 of tGRanks) & heTwoDigits(item 2 of tGRanks) & "000000"
   end if
   if tFlush then
      put "05" into tOut
      repeat with tPos = 1 to 5
         put heTwoDigits(item tPos of tRankList) after tOut
      end repeat
      return tOut
   end if
   if tHighStraight > 0 then
      return "04" & heTwoDigits(tHighStraight) & "00000000"
   end if
   if item 1 of tSizes is 3 then
      return "03" & heTwoDigits(item 1 of tGRanks) & heTwoDigits(item 2 of tGRanks) \
            & heTwoDigits(item 3 of tGRanks) & "0000"
   end if
   if item 1 of tSizes is 2 and item 2 of tSizes is 2 then
      return "02" & heTwoDigits(item 1 of tGRanks) & heTwoDigits(item 2 of tGRanks) \
            & heTwoDigits(item 3 of tGRanks) & "0000"
   end if
   if item 1 of tSizes is 2 then
      return "01" & heTwoDigits(item 1 of tGRanks) & heTwoDigits(item 2 of tGRanks) \
            & heTwoDigits(item 3 of tGRanks) & heTwoDigits(item 4 of tGRanks) & "00"
   end if
   put "00" into tOut
   repeat with tPos = 1 to 5
      put heTwoDigits(item tPos of tRankList) after tOut
   end repeat
   return tOut
end heRank5

function heEval7 pSeven
   -- best 5 of 7 by exhaustive 21-combination scan: the dumbest correct
   -- algorithm, identical to the CI mirror, nothing clever to get wrong
   local tSkipA, tSkipB, tPos, tFive, tRank, tBest
   set the itemDelimiter to comma
   put empty into tBest
   repeat with tSkipA = 1 to 6
      repeat with tSkipB = tSkipA + 1 to 7
         put empty into tFive
         repeat with tPos = 1 to 7
            if tPos is not tSkipA and tPos is not tSkipB then
               put item tPos of pSeven & comma after tFive
            end if
         end repeat
         delete char -1 of tFive
         put heRank5(tFive) into tRank
         if tBest is empty or tRank > tBest then
            put tRank into tBest
         end if
      end repeat
   end repeat
   return tBest
end heEval7

--------------------------------------------------------------------------
-- the deal: pure-integer PRNG shuffle (binary-free). Randomness law kept in
-- spirit -- CSPRNG entropy (sxRandomUniform) seeds it when SodiumXT is
-- present; engine time+random is a labelled practice fallback only.
--------------------------------------------------------------------------

function heFreshPrngState
   -- returns a MINSTD seed in 1..kHeRngMax
   local tSeed, tErr
   put 0 into tSeed
   if heHasSodium() then
      try
         repeat 3 times
            put (tSeed * 32768 + (sxRandomUniform(32768) mod 32768)) mod kHeRngMod into tSeed
         end repeat
      catch tErr
         put 0 into tSeed
      end try
   end if
   if tSeed <= 0 then
      -- practice entropy: engine time + random(), non-cryptographic
      put (the milliseconds) mod kHeRngMod into tSeed
      repeat 3 times
         put (tSeed * 131 + random(32768)) mod kHeRngMod into tSeed
      end repeat
   end if
   return (tSeed mod kHeRngMax) + 1
end heFreshPrngState

function heRngStep pState
   return (kHeRngMul * pState) mod kHeRngMod
end heRngStep

function heDrawInt pState, pRangeN
   -- uniform 1..pRangeN with rejection sampling (no modulo bias); returns
   -- "value,newState". Pure integer arithmetic, all products < 2^53.
   local tLimit, tS, tV
   put (kHeRngMax div pRangeN) * pRangeN into tLimit
   put pState into tS
   repeat forever
      put heRngStep(tS) into tS
      put tS - 1 into tV
      if tV < tLimit then
         return ((tV mod pRangeN) + 1) & comma & tS
      end if
   end repeat
end heDrawInt

function heShuffleDeck pState
   -- Fisher-Yates over deck[1..52]; deck 1 is the top, dealt first
   local tDeckA, tPos, tSwapPos, tDrawPair, tHold, tOut, tState
   set the itemDelimiter to comma
   repeat with tPos = 1 to 52
      put tPos into tDeckA[tPos]
   end repeat
   put pState into tState
   -- defensive: MINSTD has no 0 state (0 maps to 0 forever, and the -1 draw
   -- value under LiveCode's sign-of-dividend mod then yields swap position 0,
   -- corrupting the deck where the Python mirror would wrap to n). Every
   -- caller seeds via heFreshPrngState (already >= 1); clamp so a raw future
   -- caller cannot silently diverge from the mirror. Mirrored in
   -- tools/shuffle-kat.py.
   if tState is not a number or tState < 1 then
      put 1 into tState
   end if
   repeat with tPos = 52 down to 2
      put heDrawInt(tState, tPos) into tDrawPair
      put item 1 of tDrawPair into tSwapPos
      put item 2 of tDrawPair into tState
      put tDeckA[tPos] into tHold
      put tDeckA[tSwapPos] into tDeckA[tPos]
      put tHold into tDeckA[tSwapPos]
   end repeat
   put empty into tOut
   repeat with tPos = 1 to 52
      put tDeckA[tPos] & comma after tOut
   end repeat
   delete char -1 of tOut
   return tOut
end heShuffleDeck

function heDealAssign pDeckList, pOccupiedList, pButtonSeat
   -- fixed public consumption order (spec 7.3, adopted at every level):
   -- one card per occupied seat starting left of the button, two rounds,
   -- then burn, flop x3, burn, turn, burn, river
   local tOrder, tPos, tSeatNum, tOutA, tRound, tHoleTxt
   set the itemDelimiter to comma
   put heRotateAfter(pOccupiedList, pButtonSeat) into tOrder
   put 0 into tPos
   repeat with tRound = 1 to 2
      repeat for each item tSeatNum in tOrder
         add 1 to tPos
         put tOutA["holesBy"][tSeatNum] into tHoleTxt
         if tHoleTxt is empty then
            put item tPos of pDeckList into tOutA["holesBy"][tSeatNum]
         else
            put tHoleTxt & comma & item tPos of pDeckList into tOutA["holesBy"][tSeatNum]
         end if
      end repeat
   end repeat
   put item (tPos + 1) of pDeckList into tOutA["burnsList"]
   put item (tPos + 2) to (tPos + 4) of pDeckList into tOutA["flopList"]
   put tOutA["burnsList"] & comma & item (tPos + 5) of pDeckList into tOutA["burnsList"]
   put item (tPos + 6) of pDeckList into tOutA["turnIx"]
   put tOutA["burnsList"] & comma & item (tPos + 7) of pDeckList into tOutA["burnsList"]
   put item (tPos + 8) of pDeckList into tOutA["riverIx"]
   return tOutA
end heDealAssign

--------------------------------------------------------------------------
-- betting engine (spec 8.1) -- a pure state machine over transcript-shaped
-- messages. State travels as an array; heBetApply returns the next state
-- with "err" set (state otherwise unchanged) on any illegal message, and
-- "note" carrying events the shell reacts to ("advance:flop", "runout",
-- "showdown", "foldwin:3"). "actedBy" means "has acted since the last FULL
-- raise" -- the flag that makes under-raise all-ins not reopen betting.
--------------------------------------------------------------------------

function heBetNewHand pSB, pBB, pAnte, pStacksA, pOccupiedList, pButtonSeat
   local tStateA, tSeatNum, tCount
   set the itemDelimiter to comma
   put pSB into tStateA["sb"]
   put pBB into tStateA["bb"]
   put pAnte into tStateA["ante"]
   put pOccupiedList into tStateA["occ"]
   put pButtonSeat into tStateA["buttonSeat"]
   put "preflop" into tStateA["street"]
   put "blinds" into tStateA["phase"]
   put 0 into tStateA["toAct"]
   put 0 into tStateA["betCur"]
   put pBB into tStateA["raiseFull"]
   put 0 into tStateA["aggressor"]
   put 0 into tStateA["sdFirst"]
   put empty into tStateA["err"]
   put empty into tStateA["note"]
   repeat for each item tSeatNum in pOccupiedList
      put pStacksA[tSeatNum] into tStateA["stackBy"][tSeatNum]
      put 0 into tStateA["streetBy"][tSeatNum]
      put 0 into tStateA["handBy"][tSeatNum]
      put "false" into tStateA["foldedBy"][tSeatNum]
      put "false" into tStateA["allinBy"][tSeatNum]
      put "false" into tStateA["actedBy"][tSeatNum]
   end repeat
   put heCountItems(pOccupiedList) into tCount
   if tCount is 2 then
      -- heads-up: the button IS the small blind (spec 8.1)
      put pButtonSeat into tStateA["sbSeat"]
   else
      put heNextInList(pOccupiedList, pButtonSeat) into tStateA["sbSeat"]
   end if
   put heNextInList(pOccupiedList, tStateA["sbSeat"]) into tStateA["bbSeat"]
   return tStateA
end heBetNewHand

function heBetInHandList pStateA
   local tOut, tSeatNum
   set the itemDelimiter to comma
   put empty into tOut
   repeat for each item tSeatNum in pStateA["occ"]
      if pStateA["foldedBy"][tSeatNum] is "false" then
         put tSeatNum & comma after tOut
      end if
   end repeat
   delete char -1 of tOut
   return tOut
end heBetInHandList

function heBetSeatPending pStateA, pSeatNum
   -- a seat owes action if it is in hand, has chips, and either faces a
   -- bigger bet or has not acted since the last full raise
   if pStateA["foldedBy"][pSeatNum] is "true" then
      return false
   end if
   if pStateA["allinBy"][pSeatNum] is "true" then
      return false
   end if
   if pStateA["streetBy"][pSeatNum] < pStateA["betCur"] then
      return true
   end if
   return pStateA["actedBy"][pSeatNum] is "false"
end heBetSeatPending

function heBetNextPending pStateA, pAfterSeat
   local tOrder, tSeatNum
   set the itemDelimiter to comma
   put heRotateAfter(pStateA["occ"], pAfterSeat) into tOrder
   repeat for each item tSeatNum in tOrder
      if heBetSeatPending(pStateA, tSeatNum) then
         return tSeatNum
      end if
   end repeat
   return 0
end heBetNextPending

function heBetLiveCount pStateA
   -- in-hand seats that still have chips behind (can still bet)
   local tCount, tSeatNum
   set the itemDelimiter to comma
   put 0 into tCount
   repeat for each item tSeatNum in pStateA["occ"]
      if pStateA["foldedBy"][tSeatNum] is "false" and pStateA["allinBy"][tSeatNum] is "false" then
         add 1 to tCount
      end if
   end repeat
   return tCount
end heBetLiveCount

function heBetPay pStateA, pSeatNum, pAmount
   -- move pAmount from behind to the street; flags all-in at zero behind
   local tStateA
   put pStateA into tStateA
   subtract pAmount from tStateA["stackBy"][pSeatNum]
   add pAmount to tStateA["streetBy"][pSeatNum]
   add pAmount to tStateA["handBy"][pSeatNum]
   if tStateA["stackBy"][pSeatNum] is 0 then
      put "true" into tStateA["allinBy"][pSeatNum]
   end if
   return tStateA
end heBetPay

function heBetPayDead pStateA, pSeatNum, pAmount
   -- post dead money (antes): into the pot (handBy) only, NEVER the street bet,
   -- so an ante does not reduce what a seat still owes to call the blind. A seat
   -- short of the full ante posts what it has and is all-in for it (side-pot
   -- eligible up to its contribution, exactly like a short blind).
   local tStateA
   put pStateA into tStateA
   subtract pAmount from tStateA["stackBy"][pSeatNum]
   add pAmount to tStateA["handBy"][pSeatNum]
   if tStateA["stackBy"][pSeatNum] is 0 then
      put "true" into tStateA["allinBy"][pSeatNum]
   end if
   return tStateA
end heBetPayDead

function heBetFirstInHandAfter pStateA, pAfterSeat
   local tOrder, tSeatNum
   set the itemDelimiter to comma
   put heRotateAfter(pStateA["occ"], pAfterSeat) into tOrder
   repeat for each item tSeatNum in tOrder
      if pStateA["foldedBy"][tSeatNum] is "false" then
         return tSeatNum
      end if
   end repeat
   return 0
end heBetFirstInHandAfter

function heBetCloseStreet pStateA
   -- action closed: reset street bookkeeping and advance, or hand over
   local tStateA, tSeatNum
   set the itemDelimiter to comma
   put pStateA into tStateA
   -- remember who shows first if this closes the final betting round
   if tStateA["aggressor"] > 0 then
      put tStateA["aggressor"] into tStateA["sdFirst"]
   else
      put heBetFirstInHandAfter(tStateA, tStateA["buttonSeat"]) into tStateA["sdFirst"]
   end if
   repeat for each item tSeatNum in tStateA["occ"]
      put 0 into tStateA["streetBy"][tSeatNum]
      put "false" into tStateA["actedBy"][tSeatNum]
   end repeat
   put 0 into tStateA["betCur"]
   put tStateA["bb"] into tStateA["raiseFull"]
   put 0 into tStateA["aggressor"]
   if tStateA["street"] is "river" then
      put "showdown" into tStateA["phase"]
      put 0 into tStateA["toAct"]
      put "showdown" & return after tStateA["note"]
      return tStateA
   end if
   if heBetLiveCount(tStateA) <= 1 then
      -- nobody left who can bet: the board runs out with no more action
      put "runout" into tStateA["phase"]
      put 0 into tStateA["toAct"]
      put "runout" & return after tStateA["note"]
      return tStateA
   end if
   switch tStateA["street"]
      case "preflop"
         put "flop" into tStateA["street"]
         break
      case "flop"
         put "turn" into tStateA["street"]
         break
      case "turn"
         put "river" into tStateA["street"]
         break
   end switch
   put heBetNextPending(tStateA, tStateA["buttonSeat"]) into tStateA["toAct"]
   put "acting" into tStateA["phase"]
   put "advance:" & tStateA["street"] & return after tStateA["note"]
   return tStateA
end heBetCloseStreet

function heBetAfterAction pStateA, pSeatNum
   -- find the next actor after pSeatNum, or close the street
   local tStateA, tNextSeat
   put pStateA into tStateA
   put heBetNextPending(tStateA, pSeatNum) into tNextSeat
   if tNextSeat is 0 then
      return heBetCloseStreet(tStateA)
   end if
   put tNextSeat into tStateA["toAct"]
   return tStateA
end heBetAfterAction

function heBetApply pStateA, pMsgType, pSeatNum, pAmount
   -- THE transition function: every blind, action, and board message
   local tStateA, tOwe, tPay, tTargetAmt, tIncrement, tSeatNum, tIsAllin
   local tVerb, tAmt, tOccList
   set the itemDelimiter to comma
   put pStateA into tStateA
   put empty into tStateA["err"]
   put empty into tStateA["note"]

   switch pMsgType

      case "bidAnte"
         -- every seat posts the ante as dead money before the blinds; a seat
         -- short of the ante posts what it has (all-in for the ante)
         if tStateA["phase"] is not "blinds" then
            put "bidAnte-out-of-phase" into tStateA["err"]
            return tStateA
         end if
         -- replay-as-audit hardening: a seat outside the hand, or a REPEATED
         -- ante from the same seat, must be engine-rejected -- without these a
         -- hand-edited transcript replays an illegal posting sequence clean
         -- (and the foreign-seat case does arithmetic on an absent stack)
         put tStateA["occ"] into tOccList   -- copy before chunking (H6)
         if pSeatNum is not among the items of tOccList then
            put "bidAnte-wrong-seat" into tStateA["err"]
            return tStateA
         end if
         if tStateA["antePostedBy"][pSeatNum] is "true" then
            put "bidAnte-duplicate" into tStateA["err"]
            return tStateA
         end if
         put min(tStateA["ante"], tStateA["stackBy"][pSeatNum]) into tPay
         if pAmount is not tPay then
            put "bidAnte-wrong-amount" into tStateA["err"]
            return tStateA
         end if
         put heBetPayDead(tStateA, pSeatNum, tPay) into tStateA
         put "true" into tStateA["antePostedBy"][pSeatNum]
         return tStateA

      case "bidSB"
         if tStateA["phase"] is not "blinds" then
            put "bidSB-out-of-phase" into tStateA["err"]
            return tStateA
         end if
         if pSeatNum is not tStateA["sbSeat"] then
            put "bidSB-wrong-seat" into tStateA["err"]
            return tStateA
         end if
         -- phase stays "blinds" until the BB posts, so without this flag a
         -- transcript with two bidSB lines double-charged the small blind and
         -- still audited clean
         if tStateA["sbPosted"] is "true" then
            put "bidSB-duplicate" into tStateA["err"]
            return tStateA
         end if
         put min(tStateA["sb"], tStateA["stackBy"][pSeatNum]) into tPay
         if pAmount is not tPay then
            put "bidSB-wrong-amount" into tStateA["err"]
            return tStateA
         end if
         put heBetPay(tStateA, pSeatNum, tPay) into tStateA
         put "true" into tStateA["sbPosted"]
         return tStateA

      case "bidBB"
         if tStateA["phase"] is not "blinds" then
            put "bidBB-out-of-phase" into tStateA["err"]
            return tStateA
         end if
         if pSeatNum is not tStateA["bbSeat"] then
            put "bidBB-wrong-seat" into tStateA["err"]
            return tStateA
         end if
         put min(tStateA["bb"], tStateA["stackBy"][pSeatNum]) into tPay
         if pAmount is not tPay then
            put "bidBB-wrong-amount" into tStateA["err"]
            return tStateA
         end if
         put heBetPay(tStateA, pSeatNum, tPay) into tStateA
         -- the big blind is the opening bet even when posted short
         put tStateA["bb"] into tStateA["betCur"]
         put tStateA["bb"] into tStateA["raiseFull"]
         put "acting" into tStateA["phase"]
         put heBetAfterAction(tStateA, pSeatNum) into tStateA
         return tStateA

      case "board"
         -- board messages only move state during a runout; in normal play
         -- the engine advanced at street close and this is just the record
         if tStateA["phase"] is "runout" then
            switch tStateA["street"]
               case "preflop"
                  put "flop" into tStateA["street"]
                  break
               case "flop"
                  put "turn" into tStateA["street"]
                  break
               case "turn"
                  put "river" into tStateA["street"]
                  break
            end switch
            if tStateA["street"] is "river" then
               put "showdown" into tStateA["phase"]
               put "showdown" & return after tStateA["note"]
            end if
         end if
         return tStateA

      case "act"
         break

      default
         put "unknown-message:" & pMsgType into tStateA["err"]
         return tStateA
   end switch

   -- act messages: pAmount item 1 is the verb, item 2 the amount
   put item 1 of pAmount into tVerb
   put item 2 of pAmount into tAmt
   if tAmt is empty then
      put 0 into tAmt
   end if
   if tStateA["phase"] is not "acting" then
      put "act-out-of-phase" into tStateA["err"]
      return tStateA
   end if
   if pSeatNum is not tStateA["toAct"] then
      put "act-out-of-turn" into tStateA["err"]
      return tStateA
   end if

   switch tVerb

      case "fold"
         put "true" into tStateA["foldedBy"][pSeatNum]
         put "true" into tStateA["actedBy"][pSeatNum]
         if heCountItems(heBetInHandList(tStateA)) is 1 then
            put "handdone" into tStateA["phase"]
            put 0 into tStateA["toAct"]
            put "foldwin:" & heBetInHandList(tStateA) & return after tStateA["note"]
            return tStateA
         end if
         return heBetAfterAction(tStateA, pSeatNum)

      case "check"
         if tStateA["streetBy"][pSeatNum] < tStateA["betCur"] then
            put "check-facing-bet" into tStateA["err"]
            return tStateA
         end if
         put "true" into tStateA["actedBy"][pSeatNum]
         return heBetAfterAction(tStateA, pSeatNum)

      case "call"
         put tStateA["betCur"] - tStateA["streetBy"][pSeatNum] into tOwe
         if tOwe <= 0 then
            put "call-nothing-to-call" into tStateA["err"]
            return tStateA
         end if
         put min(tOwe, tStateA["stackBy"][pSeatNum]) into tPay
         if tAmt is not tPay then
            put "call-wrong-amount" into tStateA["err"]
            return tStateA
         end if
         put heBetPay(tStateA, pSeatNum, tPay) into tStateA
         put "true" into tStateA["actedBy"][pSeatNum]
         return heBetAfterAction(tStateA, pSeatNum)

      case "bet"
      case "raise"
      case "allin"
         -- unified aggressive path; "allin" resolves its own target
         if tVerb is "allin" then
            put tStateA["streetBy"][pSeatNum] + tStateA["stackBy"][pSeatNum] into tTargetAmt
            if tAmt is not tTargetAmt then
               put "allin-wrong-amount" into tStateA["err"]
               return tStateA
            end if
            if tTargetAmt <= tStateA["betCur"] then
               -- an all-in that cannot even match the bet is a call for less
               put heBetPay(tStateA, pSeatNum, tStateA["stackBy"][pSeatNum]) into tStateA
               put "true" into tStateA["actedBy"][pSeatNum]
               return heBetAfterAction(tStateA, pSeatNum)
            end if
         else
            put tAmt into tTargetAmt
            -- chips are integers and the amount arrives as TEXT (the UI box
            -- today, the wire in Phase 2). A non-number passes the string-
            -- fallback compares below and then THROWS in the arithmetic; a
            -- fractional target flows into heSettleOf's div/mod accounting,
            -- where a fractional remainder hands a whole chip to EVERY winner
            -- and mints chips -- and the replay audit re-derives the same
            -- wrong payout, so it stamps the minting hand clean. Reject both.
            if tTargetAmt is not a number or tTargetAmt is not trunc(tTargetAmt) then
               put "act-bad-amount" into tStateA["err"]
               return tStateA
            end if
            if tVerb is "bet" and tStateA["betCur"] > 0 then
               put "bet-facing-bet-use-raise" into tStateA["err"]
               return tStateA
            end if
            if tVerb is "raise" and tStateA["betCur"] is 0 then
               put "raise-nothing-to-raise-use-bet" into tStateA["err"]
               return tStateA
            end if
         end if
         if tTargetAmt <= tStateA["betCur"] then
            put "raise-not-above-bet" into tStateA["err"]
            return tStateA
         end if
         put tTargetAmt - tStateA["streetBy"][pSeatNum] into tPay
         if tPay > tStateA["stackBy"][pSeatNum] then
            put "raise-beyond-stack" into tStateA["err"]
            return tStateA
         end if
         put tPay is tStateA["stackBy"][pSeatNum] into tIsAllin
         put tTargetAmt - tStateA["betCur"] into tIncrement
         if tIncrement < tStateA["raiseFull"] and not tIsAllin then
            put "raise-below-minimum" into tStateA["err"]
            return tStateA
         end if
         if tStateA["actedBy"][pSeatNum] is "true" then
            -- betting was never reopened for this seat (an under-raise
            -- all-in happened since it acted): it may only call or fold
            put "raise-not-reopened" into tStateA["err"]
            return tStateA
         end if
         put heBetPay(tStateA, pSeatNum, tPay) into tStateA
         put tTargetAmt into tStateA["betCur"]
         put pSeatNum into tStateA["aggressor"]
         put "true" into tStateA["actedBy"][pSeatNum]
         if tIncrement >= tStateA["raiseFull"] then
            -- a FULL raise reopens action for everyone else
            put tIncrement into tStateA["raiseFull"]
            repeat for each item tSeatNum in tStateA["occ"]
               if tSeatNum is not pSeatNum then
                  put "false" into tStateA["actedBy"][tSeatNum]
               end if
            end repeat
         end if
         return heBetAfterAction(tStateA, pSeatNum)

      default
         put "unknown-verb:" & tVerb into tStateA["err"]
         return tStateA
   end switch
end heBetApply

function heBetLegal pStateA, pSeatNum
   -- for the UI: one action per line -- "fold", "check", "call N",
   -- "bet MIN MAX", "raise MINTO MAXTO", "allin N"
   local tOut, tOwe, tMinTo, tMaxTo
   put empty into tOut
   if pStateA["phase"] is not "acting" or pStateA["toAct"] is not pSeatNum then
      return tOut
   end if
   put pStateA["betCur"] - pStateA["streetBy"][pSeatNum] into tOwe
   put "fold" & return after tOut
   if tOwe <= 0 then
      put "check" & return after tOut
   else
      put "call " & min(tOwe, pStateA["stackBy"][pSeatNum]) & return after tOut
   end if
   put pStateA["streetBy"][pSeatNum] + pStateA["stackBy"][pSeatNum] into tMaxTo
   if pStateA["actedBy"][pSeatNum] is "false" and tMaxTo > pStateA["betCur"] then
      put min(pStateA["betCur"] + pStateA["raiseFull"], tMaxTo) into tMinTo
      if pStateA["betCur"] is 0 then
         put "bet " & tMinTo && tMaxTo & return after tOut
      else
         put "raise " & tMinTo && tMaxTo & return after tOut
      end if
   end if
   -- a shove above the bet is a raise: only legal if betting is (re)open
   -- for this seat; a shove at or under the bet is just a call for less
   if pStateA["actedBy"][pSeatNum] is "false" or tMaxTo <= pStateA["betCur"] then
      put "allin " & tMaxTo & return after tOut
   end if
   delete char -1 of tOut
   return tOut
end heBetLegal

function heShowdownOrderOf pStateA
   -- last aggressor of the final street first, then clockwise (spec 8.1)
   local tOut, tSeatNum, tOrder, tFirstSeat
   set the itemDelimiter to comma
   put pStateA["sdFirst"] into tFirstSeat
   if tFirstSeat is 0 or pStateA["foldedBy"][tFirstSeat] is "true" then
      put heBetFirstInHandAfter(pStateA, pStateA["buttonSeat"]) into tFirstSeat
   end if
   put tFirstSeat & comma & heRotateAfter(pStateA["occ"], tFirstSeat) into tOrder
   put empty into tOut
   repeat for each item tSeatNum in tOrder
      if pStateA["foldedBy"][tSeatNum] is "false" and tSeatNum is not among the items of tOut then
         put tSeatNum & comma after tOut
      end if
   end repeat
   delete char -1 of tOut
   return tOut
end heShowdownOrderOf

--------------------------------------------------------------------------
-- settlement (spec 8.3) -- deltas are a pure function of the transcript.
-- Layered side pots: each distinct all-in level is its own pot, awarded
-- independently; the odd chip goes to the first winner clockwise from the
-- button (pinned in tools/betting-kat.py).
--------------------------------------------------------------------------

function heSettleOf pStateA, pRanksA
   local tDeltasA, tSeatNum, tLevelsList, tLevelVal, tPrevLevel, tLayerAmt
   local tEligibleList, tBestRank, tWinnersList, tShare, tRemainder, tOrder
   local tContrib, tWinCount, tNoteTxt
   set the itemDelimiter to comma
   put empty into tNoteTxt
   repeat for each item tSeatNum in pStateA["occ"]
      put 0 into tDeltasA[tSeatNum]
      subtract pStateA["handBy"][tSeatNum] from tDeltasA[tSeatNum]
   end repeat

   -- distinct positive commitment levels, ascending
   put empty into tLevelsList
   repeat for each item tSeatNum in pStateA["occ"]
      if pStateA["handBy"][tSeatNum] > 0 and pStateA["handBy"][tSeatNum] is not among the items of tLevelsList then
         put pStateA["handBy"][tSeatNum] & comma after tLevelsList
      end if
   end repeat
   delete char -1 of tLevelsList
   sort items of tLevelsList numeric ascending

   put 0 into tPrevLevel
   repeat for each item tLevelVal in tLevelsList
      -- the layer pot: every seat contributes its slice of this level
      put 0 into tLayerAmt
      repeat for each item tSeatNum in pStateA["occ"]
         put min(pStateA["handBy"][tSeatNum], tLevelVal) - tPrevLevel into tContrib
         if tContrib > 0 then
            add tContrib to tLayerAmt
         end if
      end repeat
      -- eligible: unfolded seats fully covering this level
      put empty into tEligibleList
      repeat for each item tSeatNum in pStateA["occ"]
         if pStateA["foldedBy"][tSeatNum] is "false" and pStateA["handBy"][tSeatNum] >= tLevelVal then
            put tSeatNum & comma after tEligibleList
         end if
      end repeat
      delete char -1 of tEligibleList
      if tEligibleList is empty then
         repeat for each item tSeatNum in pStateA["occ"]
            put min(pStateA["handBy"][tSeatNum], tLevelVal) - tPrevLevel into tContrib
            if tContrib > 0 then
               add tContrib to tDeltasA[tSeatNum]
            end if
         end repeat
         put tLevelVal into tPrevLevel
         next repeat
      end if
      -- winners: best rank among the eligible
      put empty into tBestRank
      repeat for each item tSeatNum in tEligibleList
         if tBestRank is empty or pRanksA[tSeatNum] > tBestRank then
            put pRanksA[tSeatNum] into tBestRank
         end if
      end repeat
      put empty into tWinnersList
      repeat for each item tSeatNum in tEligibleList
         if pRanksA[tSeatNum] is tBestRank or heCountItems(tEligibleList) is 1 then
            put tSeatNum & comma after tWinnersList
         end if
      end repeat
      delete char -1 of tWinnersList
      put heCountItems(tWinnersList) into tWinCount
      put tLayerAmt div tWinCount into tShare
      put tLayerAmt mod tWinCount into tRemainder
      repeat for each item tSeatNum in tWinnersList
         add tShare to tDeltasA[tSeatNum]
      end repeat
      -- odd chips: first winner(s) clockwise from the button
      put heRotateAfter(pStateA["occ"], pStateA["buttonSeat"]) into tOrder
      repeat for each item tSeatNum in tOrder
         if tRemainder is 0 then
            exit repeat
         end if
         if tSeatNum is among the items of tWinnersList then
            add 1 to tDeltasA[tSeatNum]
            subtract 1 from tRemainder
         end if
      end repeat
      put "pot " & tLayerAmt & " to " & tWinnersList & return after tNoteTxt
      put tLevelVal into tPrevLevel
   end repeat
   put tNoteTxt into tDeltasA["note"]
   return tDeltasA
end heSettleOf

--------------------------------------------------------------------------
-- transcript -- plain-text bodies, no hashing/hex/binary. Hotseat actions
-- are appended to a local log and folded, exactly as network messages will
-- be (the Phase 2 seam). The signed canonical envelope is a Phase 2 item
-- (its bytes are specced + KAT-pinned in tools/protocol-kat.py).
--------------------------------------------------------------------------

function heLogLine pHandNum, pFromTxt, pTypeTxt, pBodyTxt
   -- tab-delimited; body is plain text (never contains a tab)
   return pHandNum & tab & pFromTxt & tab & pTypeTxt & tab & pBodyTxt
end heLogLine

function heLogField pLine, pIdx
   local tSaved, tOut
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   put item pIdx of pLine into tOut
   set the itemDelimiter to tSaved
   return tOut
end heLogField

command heLogAppend pTypeTxt, pFromTxt, pBodyTxt
   put heLogLine(gGame["handNum"], pFromTxt, pTypeTxt, pBodyTxt) & return after gGame["log"]
end heLogAppend

function heLogIsCleanHotseat pLogTxt
   -- true iff pLogTxt begins with a 4-field hotseat line whose type is "cfg" (not
   -- an online WIRE envelope, and not empty). The online lobby and the hotseat game
   -- share gGame["log"] but in two incompatible formats: a hotseat line is
   -- handNum TAB from TAB type TAB body (4 tab fields), while an online wire is a
   -- 10-field signed envelope whose 3rd field is the hand number, NOT the type. A
   -- hotseat History fold reads field 3 as the type and needs a hotseat "cfg" line
   -- (which carries sb/bb/ante AND per-seat stacks) to seed heBetNewHand. So when
   -- heTableCreate/heTableJoin has clobbered the log with a wire cfg (which carries
   -- no stacks), leaving the lobby to hotseat must start a fresh hotseat table.
   -- Pure (takes the log as a parameter) so it can be pinned in the harness.
   local tFirst, tSaved
   put line 1 of pLogTxt into tFirst
   if tFirst is empty then
      return false
   end if
   put the itemDelimiter into tSaved
   set the itemDelimiter to tab
   if the number of items of tFirst is 4 and item 3 of tFirst is "cfg" then
      set the itemDelimiter to tSaved
      return true
   end if
   set the itemDelimiter to tSaved
   return false
end heLogIsCleanHotseat

function heIsCardList pListTxt, pCount
   -- pure guard for the fold: TRUE only when pListTxt is exactly pCount
   -- comma-items, each a whole card index 1..52. Keeps a truncated or
   -- hand-edited transcript from feeding heEval7 short/garbage card lists
   -- (heCardRankVal on empty or non-numeric text throws). Mirrored in
   -- tools/fold-kat.py.
   local tItem
   set the itemDelimiter to comma
   if heCountItems(pListTxt) is not pCount then
      return false
   end if
   repeat for each item tItem in pListTxt
      if tItem is not a number then
         return false
      end if
      if tItem is not trunc(tItem) or tItem < 1 or tItem > 52 then
         return false
      end if
   end repeat
   return true
end heIsCardList

function heFoldTranscript pLogTxt
   -- pure fold: replay a transcript and RE-DERIVE everything (engine state,
   -- showdown ranks, settlements); logged settle lines are verified against
   -- the recomputation, so replay is also an audit. Returns "stacksBy"
   -- (array), "handNum", "trace" (per-hand deltas lines), "errors" (lines).
   local tOutA, tLogLine, tType, tBodyTxt, tBodyA, tStateA, tHaveHand
   local tSeatNum, tHolesA, tBoardList, tRanksA, tDeltasA, tDeltasTxt
   local tSevenList, tOccList, tButtonSeat, tSB, tBB, tAnte, tFromTxt, tStacksTxt
   local tPos, tCardTxt, tOneCard, tSettleBad
   local tHistLine, tBoardNames, tPotTotal, tWinnersTxt, tShownTxt, tHolePair, tAuditPart
   local tShowChoiceA, tShownPiece
   set the itemDelimiter to comma
   put 0 into tOutA["handNum"]
   put empty into tOutA["trace"]
   put empty into tOutA["errors"]
   put empty into tOutA["history"]
   put "false" into tHaveHand
   put empty into tBoardList

   repeat for each line tLogLine in pLogTxt
      if tLogLine is empty then
         next repeat
      end if
      put heLogField(tLogLine, 3) into tType
      put heLogField(tLogLine, 4) into tBodyTxt
      set the itemDelimiter to comma

      switch tType

         case "cfg"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put tBodyA["sb"] into tSB
            put tBodyA["bb"] into tBB
            put tBodyA["ante"] into tAnte    -- absent in pre-ante transcripts
            if tAnte is empty then
               put 0 into tAnte
            end if
            put tBodyA["seats"] into tOccList
            replace "|" with comma in tOccList
            put tBodyA["button"] into tButtonSeat
            put tBodyA["stacks"] into tStacksTxt
            replace "|" with comma in tStacksTxt
            put 0 into tPos
            repeat for each item tSeatNum in tOccList
               add 1 to tPos
               put item tPos of tStacksTxt into tOutA["stacksBy"][tSeatNum]
            end repeat
            break

         case "level"
            -- tournament level change: subsequent hands use these stakes/ante
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put tBodyA["sb"] into tSB
            put tBodyA["bb"] into tBB
            put tBodyA["ante"] into tAnte
            if tAnte is empty then
               put 0 into tAnte
            end if
            break

         case "handStart"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put tBodyA["seats"] into tOccList
            replace "|" with comma in tOccList
            put tBodyA["button"] into tButtonSeat
            put heBetNewHand(tSB, tBB, tAnte, tOutA["stacksBy"], tOccList, tButtonSeat) into tStateA
            put "true" into tHaveHand
            put empty into tHolesA
            put empty into tBoardList
            put empty into tRanksA
            put empty into tShowChoiceA
            put heLogField(tLogLine, 1) into tOutA["handNum"]
            break

         case "holeDeliver"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put tBodyA["cards"] into tCardTxt
            replace "|" with comma in tCardTxt
            put heCardIndex(item 1 of tCardTxt) & comma & heCardIndex(item 2 of tCardTxt) \
                  into tHolesA[tBodyA["seat"]]
            break

         case "board"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put tBodyA["cards"] into tCardTxt
            replace "|" with comma in tCardTxt
            repeat for each item tOneCard in tCardTxt
               if tBoardList is empty then
                  put heCardIndex(tOneCard) into tBoardList
               else
                  put tBoardList & comma & heCardIndex(tOneCard) into tBoardList
               end if
            end repeat
            put heBetApply(tStateA, "board", 0, 0) into tStateA
            break

         case "bidAnte"
         case "bidSB"
         case "bidBB"
         case "act"
            if tHaveHand is not "true" then
               put "action-before-hand" & return after tOutA["errors"]
               next repeat
            end if
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put heLogField(tLogLine, 2) into tFromTxt
            put char 5 to -1 of tFromTxt into tSeatNum
            if tType is "act" then
               put heBetApply(tStateA, "act", tSeatNum, tBodyA["verb"] & comma & tBodyA["amount"]) into tStateA
            else
               put heBetApply(tStateA, tType, tSeatNum, tBodyA["amount"]) into tStateA
            end if
            if tStateA["err"] is not empty then
               put "engine-rejected:" & tStateA["err"] & return after tOutA["errors"]
            end if
            break

         case "settle"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put empty into tRanksA
            if heCountItems(heBetInHandList(tStateA)) > 1 then
               -- drop-and-log (spec 16 posture): a contested showdown needs 5
               -- valid board cards and a valid hole pair per unfolded seat. A
               -- truncated or hand-edited transcript would otherwise feed
               -- heEval7 short/garbage card lists here and THROW mid-replay,
               -- killing the whole History fold on exactly the tampered input
               -- the audit exists to catch. Name it and skip this settle.
               put "false" into tSettleBad
               if not heIsCardList(tBoardList, 5) then
                  put "true" into tSettleBad
               end if
               repeat for each item tSeatNum in heBetInHandList(tStateA)
                  put tHolesA[tSeatNum] into tHolePair
                  if not heIsCardList(tHolePair, 2) then
                     put "true" into tSettleBad
                  end if
               end repeat
               if tSettleBad is "true" then
                  put "settle-bad-cards-hand-" & heLogField(tLogLine, 1) & return after tOutA["errors"]
                  break
               end if
               repeat for each item tSeatNum in heBetInHandList(tStateA)
                  put tHolesA[tSeatNum] & comma & tBoardList into tSevenList
                  put heEval7(tSevenList) into tRanksA[tSeatNum]
               end repeat
            end if
            put heSettleOf(tStateA, tRanksA) into tDeltasA
            put empty into tDeltasTxt
            repeat for each item tSeatNum in tStateA["occ"]
               put tSeatNum & ":" & tDeltasA[tSeatNum] & "|" after tDeltasTxt
            end repeat
            delete char -1 of tDeltasTxt
            if tBodyA["deltas"] is not tDeltasTxt then
               put "settle-mismatch-hand-" & heLogField(tLogLine, 1) & ":logged=" & tBodyA["deltas"] \
                     & ":computed=" & tDeltasTxt & return after tOutA["errors"]
            end if
            repeat for each item tSeatNum in tStateA["occ"]
               add tDeltasA[tSeatNum] to tOutA["stacksBy"][tSeatNum]
            end repeat
            put "hand " & heLogField(tLogLine, 1) & ": " & tDeltasTxt & return after tOutA["trace"]
            -- auditable hand-history line, folded from the transcript (which IS
            -- the record). "settle-verified" means the logged payout equalled the
            -- independent recomputation on this replay -- the audit, per hand.
            put empty into tBoardNames
            repeat for each item tOneCard in tBoardList
               put heCardName(tOneCard) & comma after tBoardNames
            end repeat
            if tBoardNames is not empty then
               delete char -1 of tBoardNames        -- trailing comma
               replace comma with space in tBoardNames
            end if
            -- THE AWARDED POT, NOT THE SUM OF COMMITMENTS (fixed 2026-08-17
            -- from a hotseat transcript). This used to be a plain
            -- `add handBy[seat] to tPotTotal`, which counts chips that were
            -- never in the pot: a bet nobody called is RETURNED, and the
            -- return is exactly what keeps the deltas correct. In a heads-up
            -- all-in it reads spectacularly wrong -- a 392 short stack called
            -- by a 2008 stack showed "pot 2400" for a pot of 784, inflated by
            -- the 1616 that went straight back. The money was always right;
            -- only this line lied, which is why settle-verified passed
            -- alongside it.
            -- The rule: a seat's chips enter the pot only up to the largest
            -- amount ANY OTHER seat committed. Equivalently, with h1 the
            -- highest commitment and h2 the second highest COUNTING TIES, a
            -- seat below h1 contributes all of it and a seat AT h1 contributes
            -- h2 -- so a normal called hand (two or more seats level at h1) is
            -- unchanged, and only a genuine uncalled excess is excluded.
            put heAwardedPot(tStateA["handBy"], tStateA["occ"]) into tPotTotal
            put empty into tWinnersTxt
            put empty into tShownTxt
            repeat for each item tSeatNum in tStateA["occ"]
               if tDeltasA[tSeatNum] > 0 then
                  put tSeatNum & comma after tWinnersTxt
               end if
               if tRanksA[tSeatNum] is not empty then
                  put tHolesA[tSeatNum] into tHolePair
                  put tSeatNum & "=" & heCardName(item 1 of tHolePair) && heCardName(item 2 of tHolePair) \
                        && heHandLabel(tRanksA[tSeatNum]) into tShownPiece
                  -- 2e show/muck: the audit knows every contested hand (the
                  -- seeds reveal it); a seat that DECLINED to show it at the
                  -- table is annotated, not hidden -- display choice, not
                  -- correctness (mirrored in tools/fold-kat.py)
                  if tShowChoiceA[tSeatNum] is "muck" then
                     put " (mucked)" after tShownPiece
                  end if
                  put tShownPiece & ", " after tShownTxt
               end if
            end repeat
            if tWinnersTxt is not empty then
               delete char -1 of tWinnersTxt
            end if
            if tShownTxt is not empty then
               delete char -1 of tShownTxt           -- trailing space, then...
               delete char -1 of tShownTxt           -- ...trailing comma (two proven deletes)
            end if
            put "hand " & heLogField(tLogLine, 1) & ": board " & tBoardNames \
                  & "; pot " & tPotTotal & "; winner seat " & tWinnersTxt into tHistLine
            if tShownTxt is not empty then
               put "; showdown " & tShownTxt after tHistLine
            end if
            put "; deltas " & tDeltasTxt into tAuditPart
            if tBodyA["deltas"] is tDeltasTxt then
               put tAuditPart & "; settle-verified" after tHistLine
            else
               put tAuditPart & "; settle-MISMATCH" after tHistLine
            end if
            put tHistLine & return after tOutA["history"]
            put "false" into tHaveHand
            break

         case "show"
         case "muck"
            -- 2e display choice, recorded ahead of the settle line (the
            -- online-log translator repositions them there); annotates the
            -- audited showdown, never changes it
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            if tBodyA["seat"] is a number then
               put tType into tShowChoiceA[tBodyA["seat"]]
            end if
            break

         case "chat"
            break

      end switch
   end repeat
   return tOutA
end heFoldTranscript

function heNetLogToHotseat pLogTxt
   -- ONLINE HISTORY FOLDING (2e; the 2d deferral): translate the signed
   -- wire chain into the 4-field hotseat-shaped transcript heFoldTranscript
   -- and heAuditDealsFromLog already fold, so History audits an ONLINE
   -- session through the exact same replay path as a hotseat one. PURE
   -- (H5): reads no gGame. The input chain was verified wire-by-wire on
   -- ingest (heEnvVerify); this is a format translation, not a second
   -- verification pass. The mapping:
   --   * the signed cfg's stakes + the sit wires' seats become the hotseat
   --     cfg line (stacks seed from the cfg's stack, as the live fold does),
   --     emitted once before the first handStart;
   --   * pubkey senders become "seatN" from-names (the fold parses the seat
   --     off them for bids and acts);
   --   * dealLevel gains table=<the envelope's table id> and the
   --     CONTRIBUTOR count (seats, plus the oracle's extra position at
   --     level 1) -- the range the deal audit re-derives over;
   --   * holeDeliver wires carry sealed boxes a reader cannot open, so the
   --     holes are RE-DERIVED from the revealed seeds (the same truth the
   --     live audit used) and emitted as plain card lines before the
   --     settle; a hand whose reveals never completed gets none, and its
   --     contested settle is then NAMED settle-bad-cards by the fold --
   --     honest, never invented;
   --   * show/muck reposition just AHEAD of their hand's settle (on the
   --     wire they follow it; the fold annotates the showdown they cover);
   --   * ckpt/receipt/audit/join/roster are not hotseat vocabulary -- the
   --     net feed carries their live verdicts.
   -- Returns empty when the log holds no translatable game (no handStart).
   -- Exercised end to end by the netplay loopback (section 15); the pieces
   -- it composes are each KAT-pinned (fold-kat, protocol-kat).
   local tA, tWireLine, tTypeTxt, tBodyTxt, tBodyA, tHandTxt, tFromSeat
   local tSeatByPubA, tStackAmt, tCfgSB, tCfgBB, tCfgAnte
   local tSeatsTxt, tStacksTxt, tSeatNum, tCfgDone, tOut, tFromTxt
   local tHandLines, tShowLines, tSettleLine, tTableHex, tHoleLines
   local tOccList, tButton, tContribN, tSeedsA, tRevealN, tHandNum
   local tPos, tDealErr, tDeckList, tDealA, tHolePair, tNamesTxt, tSeenHand
   set the itemDelimiter to comma
   put 1 into tCfgSB
   put 2 into tCfgBB
   put 0 into tCfgAnte
   put kHeDefaultStack into tStackAmt
   put "false" into tCfgDone
   put "false" into tSeenHand
   put empty into tOut
   put empty into tHandLines
   put empty into tShowLines
   put empty into tSettleLine
   put empty into tHoleLines
   put 0 into tRevealN
   put 0 into tContribN
   repeat for each line tWireLine in pLogTxt
      if tWireLine is empty then
         next repeat
      end if
      put heEnvWireParse(tWireLine) into tA
      if tA["hostSig"] is empty then
         next repeat   -- not a 10-field wire (a clobbered/foreign line)
      end if
      put tA["type"] into tTypeTxt
      put tA["hand"] into tHandTxt
      put heEnvBodyText(tA["bodyHex"]) into tBodyTxt
      put tSeatByPubA[tA["from"]] into tFromSeat
      set the itemDelimiter to comma
      switch tTypeTxt
         case "cfg"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            if tBodyA["sb"] is a number then
               put tBodyA["sb"] into tCfgSB
            end if
            if tBodyA["bb"] is a number then
               put tBodyA["bb"] into tCfgBB
            end if
            if tBodyA["ante"] is a number then
               put tBodyA["ante"] into tCfgAnte
            end if
            if tBodyA["stack"] is a number then
               put tBodyA["stack"] into tStackAmt
            end if
            break
         case "sit"
            -- the host ASSIGNMENT form only (seat=N,pub=...); a seat's own
            -- sit-return (2e, no pub) is liveness state, not seating -- its
            -- effect is already in the next handStart's seats
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            if tBodyA["seat"] is a number and tBodyA["pub"] is not empty then
               put tBodyA["seat"] into tSeatByPubA[tBodyA["pub"]]
            end if
            break
         case "handStart"
            -- flush the PREVIOUS hand first (its trailing show/muck wires
            -- land between its settle and this handStart)
            put heNetXlatFlush(tHandLines, tHoleLines, tShowLines, tSettleLine) after tOut
            put empty into tHandLines
            put empty into tShowLines
            put empty into tSettleLine
            put empty into tHoleLines
            put empty into tSeedsA
            put 0 into tRevealN
            put 0 into tContribN
            put "true" into tSeenHand
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put tBodyA["seats"] into tOccList
            replace "|" with comma in tOccList
            put tBodyA["button"] into tButton
            put tHandTxt into tHandNum
            if tCfgDone is not "true" then
               -- the one-time hotseat cfg: the sit wires' seats, each
               -- opening on the signed cfg's stack
               put "true" into tCfgDone
               put empty into tSeatsTxt
               put empty into tStacksTxt
               repeat for each item tSeatNum in tOccList
                  put tSeatNum & "|" after tSeatsTxt
                  put tStackAmt & "|" after tStacksTxt
               end repeat
               if tSeatsTxt is not empty then
                  delete char -1 of tSeatsTxt
                  delete char -1 of tStacksTxt
               end if
               put heLogLine(0, "table", "cfg", "sb=" & tCfgSB & ",bb=" & tCfgBB \
                     & ",ante=" & tCfgAnte & ",seats=" & tSeatsTxt \
                     & ",stacks=" & tStacksTxt & ",button=" & tButton) & return after tOut
            end if
            put heLogLine(tHandTxt, "table", "handStart", tBodyTxt) & return after tHandLines
            break
         case "dealLevel"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            put tBodyA["count"] into tContribN
            if tContribN is not a number then
               put 0 into tContribN
            end if
            if tBodyA["level"] is "1" then
               add 1 to tContribN   -- the oracle's entropy position
            end if
            put tA["table"] into tTableHex
            put heLogLine(tHandTxt, "table", "dealLevel", "level=" & tBodyA["level"] \
                  & ",table=" & tTableHex & ",count=" & tContribN) & return after tHandLines
            break
         case "seedCommit"
            put heLogLine(tHandTxt, heNetXlatFrom(tFromSeat), "seedCommit", tBodyTxt) \
                  & return after tHandLines
            break
         case "seedReveal"
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            if tBodyA["pos"] is a number and tSeedsA[tBodyA["pos"]] is empty then
               put tBodyA["seed"] into tSeedsA[tBodyA["pos"]]
               add 1 to tRevealN
            end if
            put heLogLine(tHandTxt, heNetXlatFrom(tFromSeat), "seedReveal", tBodyTxt) \
                  & return after tHandLines
            break
         case "board"
            put heLogLine(tHandTxt, "table", "board", tBodyTxt) & return after tHandLines
            break
         case "bidAnte"
         case "bidSB"
         case "bidBB"
         case "act"
            -- 2e: a HOST-authored timeout wire acts FOR the seat its body
            -- names (timeout=1,seat=N) -- attribute the translated line to
            -- THAT seat, or the fold would engine-reject it as the host
            -- seat's out-of-turn action (or the oracle's, which has none).
            -- The extra body keys ride along harmlessly (the fold reads
            -- verb/amount by name).
            put tBodyTxt into tBodyA
            split tBodyA by comma and "="
            if tBodyA["timeout"] is "1" and tBodyA["seat"] is a number then
               put heLogLine(tHandTxt, "seat" & tBodyA["seat"], tTypeTxt, tBodyTxt) \
                     & return after tHandLines
            else if tFromSeat is a number then
               put heLogLine(tHandTxt, "seat" & tFromSeat, tTypeTxt, tBodyTxt) \
                     & return after tHandLines
            end if
            break
         case "show"
         case "muck"
            put heLogLine(tHandTxt, heNetXlatFrom(tFromSeat), tTypeTxt, tBodyTxt) \
                  & return after tShowLines
            break
         case "settle"
            -- held back so the trailing show/muck wires can precede it;
            -- the holes re-derive HERE, while this hand's reveals are in
            -- scope (needs SodiumXT; guarded -- an incomplete or
            -- underivable hand honestly gets no hole lines)
            put heLogLine(tHandTxt, "table", "settle", tBodyTxt) into tSettleLine
            put empty into tHoleLines
            if heHasSodium() and tContribN > 0 and tRevealN >= tContribN then
               try
                  put heLevel0Deck(heHex2BinD(tTableHex), tHandNum, tSeedsA, tContribN) into tDeckList
                  put heDealAssign(tDeckList, tOccList, tButton) into tDealA
                  repeat for each item tSeatNum in tOccList
                     put tDealA["holesBy"][tSeatNum] into tHolePair
                     put heCardName(item 1 of tHolePair) & "|" & heCardName(item 2 of tHolePair) into tNamesTxt
                     put heLogLine(tHandNum, "table", "holeDeliver", "seat=" & tSeatNum \
                           & ",cards=" & tNamesTxt) & return after tHoleLines
                  end repeat
               catch tDealErr
                  put empty into tHoleLines
               end try
            end if
            break
      end switch
   end repeat
   put heNetXlatFlush(tHandLines, tHoleLines, tShowLines, tSettleLine) after tOut
   if tSeenHand is not "true" then
      return empty
   end if
   return tOut
end heNetLogToHotseat

function heNetXlatFrom pFromSeat
   -- translated from-name: a seated key is "seatN"; anything else (the
   -- host relay, the oracle) is "table" -- the fold only parses seats off
   -- bid/act lines, which always come from seats
   if pFromSeat is a number then
      return "seat" & pFromSeat
   end if
   return "table"
end heNetXlatFrom

function heNetXlatFlush pHandLines, pHoleLines, pShowLines, pSettleLine
   -- one translated hand, assembled in fold order: the play, the derived
   -- holes, the display choices, THEN the settle (the fold snapshots its
   -- history line at the settle, so everything it annotates must precede it)
   if pHandLines is empty and pSettleLine is empty then
      return empty
   end if
   return pHandLines & pHoleLines & pShowLines & pSettleLine & return
end heNetXlatFlush

--------------------------------------------------------------------------
-- hotseat shell -- the impure layer: owns gGame, appends to the log through
-- the engine (only accepted messages are logged), reacts to notes
--------------------------------------------------------------------------

command heCfgDefaults
   -- seed the persistent table configuration. Called once at openStack and any
   -- time gCfg is found empty; the settings panel (heApplyCfg) overwrites keys.
   put kHeDefaultStack into gCfg["startStack"]
   put kHeDefaultSB into gCfg["sb"]
   put kHeDefaultBB into gCfg["bb"]
   put kHeDefaultAnte into gCfg["ante"]
   put kHeDefaultSeats into gCfg["numSeats"]
   put "off" into gCfg["levelMode"]        -- "off" (cash) | "hands" | "time"
   put kHeDefaultLevels into gCfg["levels"]
   put kHeDefaultLevelEvery into gCfg["levelEvery"]      -- hands per level (hands mode)
   put kHeDefaultLevelMinutes into gCfg["levelMinutes"]  -- minutes per level (time mode)
   put "normal" into gCfg["speed"]          -- "fast" | "normal" | "slow"
   put "on" into gCfg["sounds"]             -- "on" | "off" (casino-audio SFX)
   put "rp1" into gCfg["transport"]         -- "rp1" (DHT swarm) | "onion" (Tor, 2f)
   put "play" into gCfg["hostMode"]         -- "play" | "oracle" (Phase 3 deck oracle)
end heCfgDefaults

command heCfgEnsure
   -- lazily fill gCfg so any entry point (a stale paste, a test) has a config
   if gCfg["numSeats"] is empty then
      heCfgDefaults
   end if
   -- 2f arrived after stacks in the wild had a saved gCfg: backfill the
   -- transport key alone so an upgraded stack keeps its other settings
   if gCfg["transport"] is empty then
      put "rp1" into gCfg["transport"]
   end if
   -- Phase 3 (v0.21.0): same backfill for the host mode
   if gCfg["hostMode"] is empty then
      put "play" into gCfg["hostMode"]
   end if
end heCfgEnsure

function heSpeedMult pSpeed
   -- fast deals in half the time, slow stretches the beats out
   switch pSpeed
      case "fast"
         return 0.5
      case "slow"
         return 1.6
   end switch
   return 1.0
end heSpeedMult

command heSpeedPace pSpeed
   -- scale the NORMAL-speed pacing constants into the live gGame["pace*"] values
   -- the schedule handlers read. trunc keeps them whole milliseconds.
   local tM
   put heSpeedMult(pSpeed) into tM
   put trunc(kHeNextHandDelayMs * tM) into gGame["paceNextHand"]
   put trunc(kHeStreetRevealMs * tM) into gGame["paceReveal"]
   put trunc(kHeRunoutStepMs * tM) into gGame["paceRunout"]
   put trunc(kHeShowdownHoldMs * tM) into gGame["paceShowdown"]
   put trunc(kHeFoldHoldMs * tM) into gGame["paceFold"]
end heSpeedPace

command heTableNew
   local tSeatNum, tErr
   -- H1: a fresh hotseat table while an online session is live must stop that
   -- session FIRST -- "put empty into gGame" below destroys the handle and the
   -- online flag, after which heNetStop is a no-op forever and the libtorrent
   -- session (with its poll loop already dead) outlives every teardown path,
   -- even closeStack. Reached via Settings -> Apply and the game-over
   -- auto-reset; Leave's own explicit heNetStop stays a harmless second call
   -- (it exits on the cleared flag).
   heNetStop
   heCfgEnsure
   put empty into gGame
   put gCfg["sb"] into gGame["sb"]
   put gCfg["bb"] into gGame["bb"]
   put gCfg["ante"] into gGame["ante"]
   put gCfg["startStack"] into gGame["startStack"]
   put gCfg["numSeats"] into gGame["numSeats"]
   put gCfg["levelMode"] into gGame["levelMode"]
   put gCfg["levels"] into gGame["levels"]
   put gCfg["levelEvery"] into gGame["levelEvery"]
   put gCfg["levelMinutes"] into gGame["levelMinutes"]
   put gCfg["speed"] into gGame["speed"]
   put 0 into gGame["curLevel"]
   put the milliseconds into gGame["tableStartMs"]   -- clock zero for time-based levels
   heSpeedPace gCfg["speed"]
   put 0 into gGame["handNum"]
   put 0 into gGame["buttonSeat"]
   put 0 into gGame["lastBB"]
   put "idle" into gGame["phase"]
   put empty into gGame["log"]
   -- seat 1..numSeats with the opening stack; unseated spots stay absent from
   -- stacksBy, so heSeatsAlive / the deal / settlement never touch them
   repeat with tSeatNum = 1 to gGame["numSeats"]
      put gCfg["startStack"] into gGame["stacksBy"][tSeatNum]
   end repeat
   put heHexId(16) into gGame["tableId"]
   -- a 32-byte crypto table id (hex) is the domain for the Level 0 committed
   -- deal (spec 7.1). Present only with SodiumXT; its absence makes heHandStart
   -- fall back to the labelled practice PRNG.
   put empty into gGame["tableIdHex"]
   if heHasSodium() then
      try
         put heBin2HexS(sxRandomBytes(32)) into gGame["tableIdHex"]
      catch tErr
         put empty into gGame["tableIdHex"]
      end try
   end if
   heLogAppend "cfg", "table", heCfgBody()
   heHudMark
end heTableNew

command heApplyCfg pStartStack, pSB, pBB, pAnte, pNumSeats, pLevelMode, pLevelEvery, pLevelMinutes, pSpeed
   -- the settings panel calls this with validated values, then heTableNew to
   -- start a fresh table on the new configuration. Kept separate so config
   -- persists across tables (gCfg) independent of live game state (gGame).
   heCfgEnsure
   put pStartStack into gCfg["startStack"]
   put pSB into gCfg["sb"]
   put pBB into gCfg["bb"]
   put pAnte into gCfg["ante"]
   put pNumSeats into gCfg["numSeats"]
   put pLevelMode into gCfg["levelMode"]
   put pLevelEvery into gCfg["levelEvery"]
   put pLevelMinutes into gCfg["levelMinutes"]
   put pSpeed into gCfg["speed"]
end heApplyCfg

function heCfgBody
   -- the table cfg logged to the transcript at create time. key=value pairs, so
   -- new keys (ante, level) are backward-compatible with heFoldTranscript's parse.
   local tSeatsTxt, tStacksTxt, tSeatNum
   put empty into tSeatsTxt
   put empty into tStacksTxt
   repeat with tSeatNum = 1 to gGame["numSeats"]
      put tSeatNum & "|" after tSeatsTxt
      put gGame["stacksBy"][tSeatNum] & "|" after tStacksTxt
   end repeat
   delete char -1 of tSeatsTxt
   delete char -1 of tStacksTxt
   return "sb=" & gGame["sb"] & ",bb=" & gGame["bb"] & ",ante=" & gGame["ante"] \
         & ",seats=" & tSeatsTxt & ",stacks=" & tStacksTxt & ",button=1" \
         & ",levelMode=" & gGame["levelMode"] & ",speed=" & gGame["speed"]
end heCfgBody

function heLevelFor pHandNum, pLevelsTxt, pHandsPerLevel
   -- tournament blind schedule: pLevelsTxt is "sb/bb/ante;sb/bb/ante;...". The
   -- active level advances every pHandsPerLevel hands (1-based) and clamps at the
   -- last level. Returns "sb,bb,ante". Pure -- KAT-pinned in betting-kat.py.
   local tEvery, tIdx
   put pHandsPerLevel into tEvery
   if tEvery < 1 then
      put 1 into tEvery
   end if
   put trunc((pHandNum - 1) / tEvery) + 1 into tIdx
   return heLevelForPeriod(tIdx, pLevelsTxt)
end heLevelFor

function heLevelForPeriod pPeriodIdx, pLevelsTxt
   -- return the "sb,bb,ante" for a 1-based period index, clamped to the last
   -- level. Shared by hand-count and (future) time-based schedules. Saves and
   -- restores the itemDelimiter so it never leaks ";" to the caller (gotcha 5).
   local tSaved, tLevels, tCount, tIdx, tLevel
   put the itemDelimiter into tSaved
   set the itemDelimiter to ";"
   put pLevelsTxt into tLevels
   put the number of items of tLevels into tCount
   if tCount < 1 then
      set the itemDelimiter to tSaved
      return "1,2,0"
   end if
   put pPeriodIdx into tIdx
   if tIdx > tCount then
      put tCount into tIdx
   end if
   if tIdx < 1 then
      put 1 into tIdx
   end if
   put item tIdx of tLevels into tLevel
   set the itemDelimiter to tSaved
   replace "/" with comma in tLevel
   return tLevel
end heLevelForPeriod

function heSeatsAlive
   local tOut, tSeatNum
   put empty into tOut
   repeat with tSeatNum = 1 to gGame["numSeats"]
      if gGame["stacksBy"][tSeatNum] > 0 then
         put tSeatNum & comma after tOut
      end if
   end repeat
   delete char -1 of tOut
   return tOut
end heSeatsAlive

function heLevelCount pLevelsTxt
   -- number of levels in a "sb/bb/ante;..." schedule (saves/restores delimiter)
   local tSaved, tTxt, tN
   put the itemDelimiter into tSaved
   set the itemDelimiter to ";"
   put pLevelsTxt into tTxt
   put the number of items of tTxt into tN
   set the itemDelimiter to tSaved
   return tN
end heLevelCount

command heApplyLevel
   -- set this hand's sb/bb/ante from the tournament schedule when one is active.
   -- The level's PERIOD index comes from hands played (levelMode "hands") or wall-
   -- clock minutes since the table opened (levelMode "time"); "off" holds fixed
   -- stakes. Logs a "level" line only when the index changes (curLevel tracks it).
   local tLvl, tIdx, tEvery, tElapsedMs, tPerMs, tCount
   switch gGame["levelMode"]
      case "hands"
         put gGame["levelEvery"] into tEvery
         if tEvery < 1 then
            put 1 into tEvery
         end if
         put trunc((gGame["handNum"] - 1) / tEvery) + 1 into tIdx
         break
      case "time"
         put gGame["levelMinutes"] into tEvery
         if tEvery < 1 then
            put 1 into tEvery
         end if
         put the milliseconds - gGame["tableStartMs"] into tElapsedMs
         put tEvery * 60000 into tPerMs
         put trunc(tElapsedMs / tPerMs) + 1 into tIdx
         break
      default
         exit heApplyLevel
   end switch
   -- clamp the index to the schedule so curLevel settles at the top (no log spam)
   put heLevelCount(gGame["levels"]) into tCount
   if tCount < 1 then
      exit heApplyLevel
   end if
   if tIdx > tCount then
      put tCount into tIdx
   end if
   if tIdx < 1 then
      put 1 into tIdx
   end if
   put heLevelForPeriod(tIdx, gGame["levels"]) into tLvl
   set the itemDelimiter to comma
   put item 1 of tLvl into gGame["sb"]
   put item 2 of tLvl into gGame["bb"]
   put item 3 of tLvl into gGame["ante"]
   if tIdx is not gGame["curLevel"] then
      put tIdx into gGame["curLevel"]
      heLogAppend "level", "table", "level=" & tIdx & ",sb=" & gGame["sb"] \
            & ",bb=" & gGame["bb"] & ",ante=" & gGame["ante"]
   end if
end heApplyLevel

command heHandStart
   local tOccList, tSeatNum, tDeckList, tDealA, tHolePair, tHoleNames
   local tSeatsTxt, tDealCount, tPos, tTableData, tSeedsA, tCommitsA, tDealErr
   set the itemDelimiter to comma
   -- only start from a settled table: "idle" (fresh/after clear) or "between"
   -- (result shown). Any active or animating phase (hand/reveal/runout/
   -- showdown) means a Deal click or a stale next-hand send must be ignored so
   -- a paced sequence is never interrupted or a hand double-dealt.
   if gGame["phase"] is not "idle" and gGame["phase"] is not "between" then
      exit heHandStart
   end if
   -- while ONLINE the hotseat engine must never run: gGame["log"] holds the
   -- signed wire chain, and heLogAppend'ing raw 4-field hotseat lines into it
   -- would be shipped to every joining peer as junk "w" frames by
   -- heNetReplayLogTo (the corruption heNetParkHotseat guards in the OTHER
   -- direction). Reachable because Settings/History dismiss the lobby overlay
   -- without restoring it, leaving the Deal button clickable. Online
   -- dealing arrives with the Phase 2 orchestration increment; until then the
   -- deal is a hotseat-only verb.
   if gGame["online"] is "true" then
      heUISetStatus "Online dealing is not wired yet -- press Leave for a hotseat game."
      exit heHandStart
   end if
   -- a Deal click during the "between" result-pause starts here while the prior
   -- hand's heNextHandTick is still pending; cancel any in-flight paced step so a
   -- stale timer cannot fire into this hand and auto-deal an unrequested one
   -- (deep-dive P1). The HUD/network poll loops are free-running and untouched.
   heCancelPacedSteps
   put heSeatsAlive() into tOccList
   if heCountItems(tOccList) < 2 then
      heUISetStatus "Game over -- one stack left. Starting a fresh table."
      heTableNew
      -- the finished game's board/hole cards are still painted (the pending
      -- heNextHandTick that would have cleared them was cancelled above, and
      -- no new deal follows to overwrite them) -- clear them with the reset
      heUIClearCards
      exit heHandStart
   end if
   add 1 to gGame["handNum"]
   -- tournament option: when a blind schedule is active, THIS hand's sb/bb/ante
   -- come from the level for the hand number (levels rise as hands are played).
   -- Logged only when the level actually changes so the transcript stays terse.
   heApplyLevel
   set the itemDelimiter to comma   -- heApplyLevel parses with ";" (gotcha 5)
   -- dead-button-aware schedule: the big blind advances to the next live seat
   -- each hand, so eliminations never double- or skip-charge a blind
   put heScheduleButton(tOccList, gGame["lastBB"]) into gGame["buttonSeat"]
   put tOccList into gGame["occ"]
   put "hand" into gGame["phase"]

   put tOccList into tSeatsTxt
   replace comma with "|" in tSeatsTxt
   heLogAppend "handStart", "table", "seats=" & tSeatsTxt & ",button=" & gGame["buttonSeat"]

   -- deal the deck. When SodiumXT is present, use the Level 0 COMMITTED
   -- keyed-stream shuffle (spec 7.1): a per-contributor seed is committed, then
   -- revealed, and the deck is a hash of the XOR of the seeds -- so the shuffle is
   -- fixed by the commitments and provably consistent with the revealed seeds on
   -- replay (tamper-evident). The whole crypto path is wrapped in a try, so ANY
   -- failure falls back to the labelled practice PRNG and the playable path can
   -- never break. NOTE seeds are generated LOCALLY here (one node holds them all --
   -- in hotseat, one human): this is the auditable, tamper-evident machinery, NOT
   -- an adversarial unstackability guarantee against a cheating dealer. That needs
   -- independent per-player seeds, each committed before any reveal, and arrives
   -- with online play (spec 7.1).
   put heCountItems(tOccList) into tDealCount
   put "practice" into gGame["dealMode"]
   put empty into gGame["dealSeedsA"]
   put empty into gGame["dealCommitsA"]
   if heHasSodium() and gGame["tableIdHex"] is not empty then
      try
         put heHex2BinD(gGame["tableIdHex"]) into tTableData
         put empty into tSeedsA
         put empty into tCommitsA
         put 0 into tPos
         repeat for each item tSeatNum in tOccList
            add 1 to tPos
            put heBin2HexS(sxRandomBytes(32)) into tSeedsA[tPos]
            put heSeedCommitHex(tSeedsA[tPos]) into tCommitsA[tPos]
         end repeat
         put heLevel0Deck(tTableData, gGame["handNum"], tSeedsA, tDealCount) into tDeckList
         put tSeedsA into gGame["dealSeedsA"]
         put tCommitsA into gGame["dealCommitsA"]
         put "level0" into gGame["dealMode"]
      catch tDealErr
         put "practice" into gGame["dealMode"]
      end try
   end if
   if gGame["dealMode"] is "practice" then
      put heShuffleDeck(heFreshPrngState()) into tDeckList
   end if
   put heDealAssign(tDeckList, tOccList, gGame["buttonSeat"]) into tDealA
   put tDeckList into tDealA["deckList"]
   put tDealCount into tDealA["seatCount"]
   put tDealA into gGame["deal"]

   -- record the deal provenance in the transcript so the deal is auditable on
   -- replay: the binding commit for each contributor, then the reveal. Anyone
   -- with the transcript can re-derive the deck and confirm it was not stacked
   -- (heAuditDealsFromLog / tools/fold-kat.py do exactly this).
   if gGame["dealMode"] is "level0" then
      heLogAppend "dealLevel", "table", "level=0,table=" & gGame["tableIdHex"] & ",count=" & tDealCount
      put 0 into tPos
      repeat for each item tSeatNum in tOccList
         add 1 to tPos
         heLogAppend "seedCommit", "seat" & tSeatNum, "pos=" & tPos & ",commit=" & gGame["dealCommitsA"][tPos]
      end repeat
      put 0 into tPos
      repeat for each item tSeatNum in tOccList
         add 1 to tPos
         heLogAppend "seedReveal", "seat" & tSeatNum, "pos=" & tPos & ",seed=" & gGame["dealSeedsA"][tPos]
      end repeat
   end if

   -- hole delivery (hotseat shows all; Phase 2 seals per seat)
   repeat for each item tSeatNum in tOccList
      put tDealA["holesBy"][tSeatNum] into tHolePair
      put heCardName(item 1 of tHolePair) & "|" & heCardName(item 2 of tHolePair) into tHoleNames
      heLogAppend "holeDeliver", "table", "seat=" & tSeatNum & ",cards=" & tHoleNames
   end repeat

   -- antes (if any) then blinds, all through the engine, then the table is live.
   -- Antes are dead money posted by every seat before the blinds; a bidAnte for
   -- each seat keeps them in the signed transcript so the fold can re-derive the
   -- pot (heFoldTranscript handles bidAnte the same as the engine).
   put heBetNewHand(gGame["sb"], gGame["bb"], gGame["ante"], gGame["stacksBy"], tOccList, gGame["buttonSeat"]) into gGame["state"]
   put gGame["state"]["bbSeat"] into gGame["lastBB"]
   if gGame["ante"] > 0 then
      repeat for each item tSeatNum in tOccList
         heEngineDo "bidAnte", tSeatNum, min(gGame["ante"], gGame["stacksBy"][tSeatNum])
      end repeat
   end if
   -- cap each blind by the seat's POST-ante engine stack, not the pre-ante
   -- bankroll gGame["stacksBy"]: the ante loop above already moved the antes into
   -- gGame["state"]["stackBy"] (via heBetPayDead), and heBetApply validates the
   -- blind against that post-ante stack. Using gGame["stacksBy"] here made a seat
   -- that is short AFTER its ante over-post the blind, so the engine rejected it
   -- with bidSB/bidBB-wrong-amount -- silently dropping the small blind or wedging
   -- the hand in tournament (ante) play (deep-dive P0).
   heEngineDo "bidSB", gGame["state"]["sbSeat"], min(gGame["sb"], gGame["state"]["stackBy"][gGame["state"]["sbSeat"]])
   heEngineDo "bidBB", gGame["state"]["bbSeat"], min(gGame["bb"], gGame["state"]["stackBy"][gGame["state"]["bbSeat"]])
   heUIHandStart
   heHudMark
   heUIPromptToAct
end heHandStart

command heEngineDo pMsgType, pSeatNum, pAmount
   -- one gate for every state transition: apply, then log ONLY if accepted
   local tStateA, tVerb
   put heBetApply(gGame["state"], pMsgType, pSeatNum, pAmount) into tStateA
   if tStateA["err"] is not empty then
      heUISetStatus "Rejected: " & tStateA["err"]
      exit heEngineDo
   end if
   put tStateA into gGame["state"]
   switch pMsgType
      case "bidAnte"
      case "bidSB"
      case "bidBB"
         heLogAppend pMsgType, "seat" & pSeatNum, "amount=" & pAmount
         break
      case "act"
         set the itemDelimiter to comma
         put item 1 of pAmount into tVerb
         heLogAppend "act", "seat" & pSeatNum, "verb=" & tVerb & ",amount=" & item 2 of pAmount
         -- SFX here, on the ACCEPTED path only (a rejected action exited above),
         -- so every action source -- buttons now, remote peers later -- sounds alike
         heSndVerb tVerb
         break
   end switch
   heReactToNotes
end heEngineDo

command heActionDo pSeatNum, pVerb, pAmount
   if gGame["phase"] is not "hand" then
      exit heActionDo
   end if
   heEngineDo "act", pSeatNum, pVerb & comma & pAmount
   heHudMark
   -- only prompt the next actor if the action stayed on the same street; a
   -- street close / runout / showdown handed off to a paced step that will
   -- prompt (or settle) on its own timer, and phase is no longer "hand".
   if gGame["phase"] is "hand" then
      heUIPromptToAct
   end if
end heActionDo

command heReactToNotes
   -- the engine transition is instant; its VISIBLE consequences are paced so a
   -- hand plays out like real dealing instead of flashing to the result. Each
   -- consequence hands off to a timer-driven step and returns; nothing here
   -- deals a card or settles synchronously. A single act produces at most one
   -- of these notes (a street close, a runout, or a showdown), so the first
   -- match wins and we stop.
   local tNoteLine, tNotesTxt
   put gGame["state"]["note"] into tNotesTxt
   repeat for each line tNoteLine in tNotesTxt
      set the itemDelimiter to comma
      switch item 1 of tNoteLine
         case "advance:flop"
            heScheduleReveal "flop"
            exit repeat
         case "advance:turn"
            heScheduleReveal "turn"
            exit repeat
         case "advance:river"
            heScheduleReveal "river"
            exit repeat
         case "runout"
            heScheduleRunout
            exit repeat
         case "showdown"
            heScheduleShowdown
            exit repeat
         default
            if tNoteLine begins with "foldwin:" then
               heScheduleShowdown
               exit repeat
            end if
      end switch
   end repeat
end heReactToNotes

command heCancelPacedSteps
   -- cancel any in-flight paced schedule send (reveal / runout / showdown /
   -- next-hand) so a stale timer from a prior hand can never fire into a later
   -- one. Only these hand-paced steps are swept; the free-running HUD and network
   -- poll loops (heHudTick / heNetPollTick) are deliberately left alone. Called at
   -- the top of heHandStart. (gotcha 5: pendingMessages is comma-delimited
   -- id,time,name,target -- set the delimiter before parsing.)
   local tMsgLine, tName
   set the itemDelimiter to comma
   repeat for each line tMsgLine in the pendingMessages
      put item 3 of tMsgLine into tName
      if tName is "heRevealStep" or tName is "heRunoutStep" \
            or tName is "heSettleStep" or tName is "heNextHandTick" then
         cancel item 1 of tMsgLine
      end if
   end repeat
end heCancelPacedSteps

command heScheduleReveal pStreetName
   -- betting closed and the next street is due: hold a beat with the buttons
   -- inert (the "reveal" phase is non-actionable), then land the board and
   -- reopen the action. gGame["state"] already advanced inside heBetApply;
   -- this only paces the visual reveal.
   put pStreetName into gGame["revealStreet"]
   put "reveal" into gGame["phase"]
   heHudMark
   send "heRevealStep" to me in hePaceMs("paceReveal", kHeStreetRevealMs) milliseconds
end heScheduleReveal

function hePaceMs pKey, pDefaultMs
   -- the speed-scaled beat for a schedule step, defaulting to the normal-speed
   -- constant if a hand somehow starts before heSpeedPace ran
   if gGame[pKey] is a number then
      return gGame[pKey]
   end if
   return pDefaultMs
end hePaceMs

on heRevealStep
   -- guarded against stale sends (playbook: defer world changes, then gate on
   -- our own phase lock so a Deal/new-hand cannot let a late reveal double-fire)
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if gGame["phase"] is not "reveal" then
      exit heRevealStep
   end if
   heDealBoard gGame["revealStreet"]
   put "hand" into gGame["phase"]
   heHudMark
   heUIPromptToAct
end heRevealStep

command heDealBoard pStreetName
   local tDealA, tCardsTxt, tIdxList, tIdx
   set the itemDelimiter to comma
   put gGame["deal"] into tDealA
   switch pStreetName
      case "flop"
         put tDealA["flopList"] into tIdxList
         break
      case "turn"
         put tDealA["turnIx"] into tIdxList
         break
      case "river"
         put tDealA["riverIx"] into tIdxList
         break
   end switch
   put empty into tCardsTxt
   repeat for each item tIdx in tIdxList
      put heCardName(tIdx) & "|" after tCardsTxt
   end repeat
   delete char -1 of tCardsTxt
   heLogAppend "board", "table", "street=" & pStreetName & ",cards=" & tCardsTxt
   heUIShowBoardStreet pStreetName, tIdxList
   heHudMark
end heDealBoard

command heScheduleRunout
   -- no more betting possible (all-in with at most one live better): run the
   -- remaining streets out ONE AT A TIME on a timer so the board comes like a
   -- real all-in, not all at once. heRunoutStep deals a street, advances the
   -- engine, and reschedules itself until the engine reaches showdown.
   put "runout" into gGame["phase"]
   heHudMark
   send "heRunoutStep" to me in hePaceMs("paceRunout", kHeRunoutStepMs) milliseconds
end heScheduleRunout

on heRunoutStep
   local tStateA
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if gGame["phase"] is not "runout" then
      exit heRunoutStep
   end if
   put gGame["state"] into tStateA
   if tStateA["phase"] is not "runout" then
      -- engine has dealt the last street: hold, then settle
      heScheduleShowdown
      exit heRunoutStep
   end if
   switch tStateA["street"]
      case "preflop"
         heDealBoard "flop"
         break
      case "flop"
         heDealBoard "turn"
         break
      case "turn"
         heDealBoard "river"
         break
      default
         heScheduleShowdown
         exit heRunoutStep
   end switch
   -- the board message advances the engine street by street (fold-determinism)
   put heBetApply(gGame["state"], "board", 0, 0) into gGame["state"]
   heHudMark
   send "heRunoutStep" to me in hePaceMs("paceRunout", kHeRunoutStepMs) milliseconds
end heRunoutStep

command heScheduleShowdown
   -- reveal the contested hands (or just hold on a fold-win), then settle after
   -- a beat so the result registers instead of the hand ending abruptly. The
   -- ranks needed by the settlement are stashed for heHandSettle.
   local tStateA, tRanksA, tSeatNum, tSevenList
   local tDealA, tInHandList, tBoardIdxList, tHoldMs
   set the itemDelimiter to comma
   put "showdown" into gGame["phase"]
   put gGame["state"] into tStateA
   put gGame["deal"] into tDealA
   put heBetInHandList(tStateA) into tInHandList
   put tDealA["flopList"] & comma & tDealA["turnIx"] & comma & tDealA["riverIx"] into tBoardIdxList
   put empty into tRanksA
   put hePaceMs("paceFold", kHeFoldHoldMs) into tHoldMs
   if heCountItems(tInHandList) > 1 then
      -- a contested showdown: reveal every shown hand and hold long enough to read it
      repeat for each item tSeatNum in tInHandList
         put tDealA["holesBy"][tSeatNum] & comma & tBoardIdxList into tSevenList
         put heEval7(tSevenList) into tRanksA[tSeatNum]
      end repeat
      heUIShowdownReveal tInHandList, tRanksA
      put hePaceMs("paceShowdown", kHeShowdownHoldMs) into tHoldMs
   end if
   put tRanksA into gGame["showdownRanks"]
   heHudMark
   send "heSettleStep" to me in tHoldMs milliseconds
end heScheduleShowdown

on heSettleStep
   -- guarded against stale sends: only the showdown we set up may settle
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if gGame["phase"] is not "showdown" then
      exit heSettleStep
   end if
   heHandSettle
end heSettleStep

command heHandSettle
   -- settle from the stashed showdown ranks, log the deltas, schedule next hand
   local tStateA, tRanksA, tSeatNum, tDeltasA, tDeltasTxt
   set the itemDelimiter to comma
   put gGame["state"] into tStateA
   put gGame["showdownRanks"] into tRanksA
   put heSettleOf(tStateA, tRanksA) into tDeltasA

   put empty into tDeltasTxt
   repeat for each item tSeatNum in tStateA["occ"]
      put tSeatNum & ":" & tDeltasA[tSeatNum] & "|" after tDeltasTxt
      add tDeltasA[tSeatNum] to gGame["stacksBy"][tSeatNum]
   end repeat
   delete char -1 of tDeltasTxt
   heLogAppend "settle", "table", "deltas=" & tDeltasTxt

   put "between" into gGame["phase"]
   heSndPlay "win"
   heUISetStatus "Hand " & gGame["handNum"] & " settled: " & tDeltasTxt
   heHudMark
   send "heNextHandTick" to me in hePaceMs("paceNextHand", kHeNextHandDelayMs) milliseconds
end heHandSettle

on heNextHandTick
   -- guarded against stale sends (playbook: defer world changes, then gate)
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if gGame["phase"] is not "between" then
      exit heNextHandTick
   end if
   put "idle" into gGame["phase"]
   heUIClearCards
   heHandStart
end heNextHandTick

--------------------------------------------------------------------------
-- UI: self-building chrome (family pattern). Two modes: "kit" needs Box2Dxt
-- Kit + an atlas path in uHeAtlasPath; "flat" is pure fields and always
-- works. All verified statically; needs an OXT pass.
--------------------------------------------------------------------------

function heHasKit
   -- the Box2Dxt Kit counts as present if its stack is loaded UNDER THAT NAME, or if
   -- its b2k* handlers are simply on the message path already -- merged into this stack's
   -- script, or hosted by a differently-named stack. b2kSheetFrames on an unknown sheet
   -- returns 0 without throwing when the handler exists; it throws "can't find handler"
   -- when the Kit is absent. (Probe cached in gHasKitChk; heKitReload clears it.)
   local tProbeErr
   if gHasKitChk is empty then
      put "false" into gHasKitChk
      if there is a stack "box2dxt-kit" then
         put "true" into gHasKitChk
      else
         try
            get b2kSheetFrames("__he_probe__")
            put "true" into gHasKitChk
         catch tProbeErr
         end try
      end if
   end if
   return gHasKitChk is "true"
end heHasKit

command heBuildTable
   local tSeatNum, tSpotTxt, tSpotX, tSpotY, tPos, tBetX, tBetY, tName
   set the defaultStack to the short name of this stack
   if there is a graphic "heFelt" and the uHeUIVersion of this stack is kUIVersion then
      -- the chrome persists in a SAVED stack but script locals do not: without
      -- re-deriving them here, a reopened stack had an empty gSlotCenter (so
      -- heKitTryInit -- and heKitReload after it -- pooled ZERO card sprites
      -- and kit mode was silently unrecoverable), stale avatar caches, and an
      -- unfitted logo. Rebuild the runtime state from the existing controls.
      heRehydrateChrome
      exit heBuildTable
   end if
   lock screen
   heWipeChrome
   set the uHeUIVersion of this stack to kUIVersion
   set the backgroundColor of this stack to "26,32,30"

   -- felt: a wooden rim behind, green oval-ish table on top
   create graphic "heFeltRim"
   set the style of graphic "heFeltRim" to "roundrect"
   set the roundRadius of graphic "heFeltRim" to 90
   set the rect of graphic "heFeltRim" to "32,40,992,532"
   set the backgroundColor of graphic "heFeltRim" to kHeFeltRim
   set the opaque of graphic "heFeltRim" to true
   create graphic "heFelt"
   set the style of graphic "heFelt" to "roundrect"
   set the roundRadius of graphic "heFelt" to 80
   set the rect of graphic "heFelt" to kHeFeltRect
   set the backgroundColor of graphic "heFelt" to kHeFeltColor
   set the opaque of graphic "heFelt" to true

   -- host table logo: a faint centred watermark, created HERE (before the pot and
   -- board) so it sits UNDERNEATH them and never hides a card or the pot. Hidden until
   -- the host picks one in Settings; heTableLogoRender loads it. NEEDS AN OXT PASS.
   create image "heTableLogo"
   set the rect of image "heTableLogo" to \
         (512 - kHeLogoBox div 2) & comma & (286 - kHeLogoBox div 2) & comma \
         & (512 + kHeLogoBox div 2) & comma & (286 + kHeLogoBox div 2)
   set the blendLevel of image "heTableLogo" to kHeLogoDim
   set the visible of image "heTableLogo" to false

   -- header + pot
   create field "heHeader"
   set the rect of field "heHeader" to "40,10,696,38"
   set the lockText of field "heHeader" to true
   set the textAlign of field "heHeader" to "center"
   set the textSize of field "heHeader" to 15
   set the textFont of field "heHeader" to "Helvetica"
   set the textColor of field "heHeader" to kHeGoldColor
   set the borderWidth of field "heHeader" to 0
   set the opaque of field "heHeader" to true
   set the backgroundColor of field "heHeader" to "26,32,30"

   create graphic "hePotChip"
   set the style of graphic "hePotChip" to "oval"
   set the rect of graphic "hePotChip" to "382,338,404,360"
   set the backgroundColor of graphic "hePotChip" to kHeGoldColor
   set the opaque of graphic "hePotChip" to true
   create field "hePot"
   set the rect of field "hePot" to "412,334,612,368"
   set the lockText of field "hePot" to true
   set the textAlign of field "hePot" to "center"
   set the textSize of field "hePot" to 20
   set the textColor of field "hePot" to kHeGoldColor
   set the opaque of field "hePot" to true
   set the backgroundColor of field "hePot" to kHeFeltColor
   set the borderWidth of field "hePot" to 0

   -- board slots
   repeat with tPos = 1 to 5
      heMakeCardSlot "heBoard" & tPos, kHeBoardX0 + (tPos - 1) * kHeBoardDX, kHeBoardY
   end repeat

   -- per-seat: panel, name, stack, badge, state, bet chip+amount, hole cards
   repeat with tSeatNum = 1 to kHeDefaultSeats
      set the itemDelimiter to ";"
      put item tSeatNum of kHeSeatSpots into tSpotTxt
      set the itemDelimiter to comma
      put item 1 of tSpotTxt into tSpotX
      put item 2 of tSpotTxt into tSpotY
      put item tSeatNum of kHeSeatNames into tName

      create graphic ("hePanel" & tSeatNum)
      set the style of graphic ("hePanel" & tSeatNum) to "roundrect"
      set the roundRadius of graphic ("hePanel" & tSeatNum) to 14
      set the rect of graphic ("hePanel" & tSeatNum) to \
            (tSpotX - 76) & comma & (tSpotY - 4) & comma & (tSpotX + 76) & comma & (tSpotY + 54)
      set the backgroundColor of graphic ("hePanel" & tSeatNum) to kHePanelColor
      set the opaque of graphic ("hePanel" & tSeatNum) to true
      -- acting-seat glow: a constant 2px outline whose colour is the ring (gold) when
      -- acting and the panel colour (so it vanishes) otherwise -- toggled in heSeatFace.
      set the lineSize of graphic ("hePanel" & tSeatNum) to 2
      set the foregroundColor of graphic ("hePanel" & tSeatNum) to kHePanelColor

      -- seat portrait at the left of the plate: disc + initial fallback + picked image.
      -- heSeatAvatarRender chooses which to show; click any of the three to re-pick.
      heMakeAvatar tSeatNum, tSpotX - 52, tSpotY + 25

      heMakeLabel "heSeatName" & tSeatNum, (tSpotX - 24) & comma & (tSpotY - 2) & comma & (tSpotX + 72) & comma & (tSpotY + 22), tName, kHeWhite, 14
      heMakeLabel "heSeatStack" & tSeatNum, (tSpotX - 24) & comma & (tSpotY + 24) & comma & (tSpotX + 72) & comma & (tSpotY + 50), "", kHeGoldColor, 15
      heMakeLabel "heSeatBadge" & tSeatNum, (tSpotX + 20) & comma & (tSpotY - 26) & comma & (tSpotX + 76) & comma & (tSpotY - 6), "", kHeInk, 11
      heMakeLabel "heSeatState" & tSeatNum, (tSpotX - 54) & comma & (tSpotY - 74) & comma & (tSpotX + 54) & comma & (tSpotY - 54), "", kHeGoldColor, 12

      put tSpotX + trunc((512 - tSpotX) * 0.42) into tBetX
      put tSpotY + trunc((286 - tSpotY) * 0.42) into tBetY
      create graphic ("heSeatChip" & tSeatNum)
      set the style of graphic ("heSeatChip" & tSeatNum) to "oval"
      set the rect of graphic ("heSeatChip" & tSeatNum) to \
            (tBetX - 11) & comma & (tBetY - 11) & comma & (tBetX + 11) & comma & (tBetY + 11)
      set the backgroundColor of graphic ("heSeatChip" & tSeatNum) to kHeChipColor
      set the opaque of graphic ("heSeatChip" & tSeatNum) to true
      set the visible of graphic ("heSeatChip" & tSeatNum) to false
      heMakeLabel "heSeatBet" & tSeatNum, (tBetX - 26) & comma & (tBetY + 12) & comma & (tBetX + 26) & comma & (tBetY + 30), "", kHeWhite, 12

      -- two hole cards straddling the seat centre; the offset scales with the card
      -- width (half a card + a small gap) so they never overlap as the size changes
      heMakeCardSlot "heHole" & tSeatNum & "a", tSpotX - (kHeCardW div 2 + 2), tSpotY - 40
      heMakeCardSlot "heHole" & tSeatNum & "b", tSpotX + (kHeCardW div 2 + 2), tSpotY - 40
   end repeat

   -- paint each seat portrait (custom image or coloured initial disc) + the host logo
   repeat with tSeatNum = 1 to kHeDefaultSeats
      heSeatAvatarRender tSeatNum
   end repeat
   heTableLogoRender

   create field "heDealerDisc"
   set the rect of field "heDealerDisc" to "0,0,26,26"
   set the lockText of field "heDealerDisc" to true
   set the textAlign of field "heDealerDisc" to "center"
   set the textSize of field "heDealerDisc" to 12
   set the textColor of field "heDealerDisc" to kHeInk
   set the backgroundColor of field "heDealerDisc" to kHeWhite
   set the text of field "heDealerDisc" to "D"
   set the visible of field "heDealerDisc" to false

   create field "heStatus"
   set the rect of field "heStatus" to "40,596,984,636"
   set the lockText of field "heStatus" to true
   set the textSize of field "heStatus" to 13
   set the opaque of field "heStatus" to true
   set the backgroundColor of field "heStatus" to "26,32,30"
   set the textColor of field "heStatus" to kHeWhite
   set the borderWidth of field "heStatus" to 0

   heMakeActionButton "heBtnFold", "Fold", 40
   heMakeActionButton "heBtnCheck", "Check", 120
   heMakeActionButton "heBtnCall", "Call", 200
   heMakeActionButton "heBtnBet", "Bet", 280
   heMakeActionButton "heBtnRaise", "Raise", 360
   heMakeActionButton "heBtnAllin", "All-in", 440
   create field "heAmount"
   set the rect of field "heAmount" to "528,560,600,584"
   set the textAlign of field "heAmount" to "center"
   set the text of field "heAmount" to "0"
   -- bet-sizing slider: drag to set the raise-to between the minimum legal raise and
   -- all-in; feeds the heAmount box (the Bet/Raise buttons read that). Sits in the thin
   -- margin above the action row. Shown only on a bet/raise turn (heUIPromptToAct).
   create scrollbar "heBetSlider"
   -- a scale, not a scrollbar: no arrow buttons, a draggable thumb on a track
   set the style of scrollbar "heBetSlider" to "scale"
   set the rect of scrollbar "heBetSlider" to "528,538,1004,554"
   set the visible of scrollbar "heBetSlider" to false
   heMakeActionButton "heBtnMin", "Min", 608
   heMakeActionButton "heBtnHalf", "1/2 Pot", 688
   heMakeActionButton "heBtnPot", "Pot", 768
   heMakeActionButton "heBtnDeal", "Deal", 848
   heMakeActionButton "heBtnOnline", "Lobby", 928
   create button "heBtnHistory"
   set the rect of button "heBtnHistory" to "892,8,980,36"
   set the label of button "heBtnHistory" to "History"
   create button "heBtnSettings"
   set the rect of button "heBtnSettings" to "792,8,884,36"
   set the label of button "heBtnSettings" to "Settings"
   -- 2e sit-out/return toggle (spec 9): our seat's own signed liveness
   -- wires; enabled only online with a seat (heHudRefresh keeps the face)
   create button "heBtnSitOut"
   set the rect of button "heBtnSitOut" to "704,8,784,36"
   set the label of button "heBtnSitOut" to "Sit out"

   heBuildLobby
   heBuildHistory
   heBuildSettings
   heKitTryInit
   unlock screen
end heBuildTable

command heRehydrateChrome
   -- a REOPENED saved stack keeps its built chrome and its uHeUIVersion, so
   -- heBuildTable's version-match exit skips the whole build -- but script
   -- locals (gSlotCenter, gUIMode, gCardSpr, the sheet suffixes, gAvatarOn)
   -- do NOT persist in a saved stack. Re-derive everything the skipped build
   -- would have set: slot centres from the existing controls' locs (a slot
   -- field's loc IS the centre heMakeCardSlot recorded), the avatar
   -- image-vs-initial caches, the logo fit, then the kit probe itself.
   local tSeatNum, tPos, tSlotName
   repeat with tPos = 1 to 5
      put "heBoard" & tPos into tSlotName
      if there is a field tSlotName then
         put the loc of field tSlotName into gSlotCenter[tSlotName]
      end if
   end repeat
   repeat with tSeatNum = 1 to kHeDefaultSeats
      put "heHole" & tSeatNum & "a" into tSlotName
      if there is a field tSlotName then
         put the loc of field tSlotName into gSlotCenter[tSlotName]
      end if
      put "heHole" & tSeatNum & "b" into tSlotName
      if there is a field tSlotName then
         put the loc of field tSlotName into gSlotCenter[tSlotName]
      end if
      heSeatAvatarRender tSeatNum
   end repeat
   heTableLogoRender
   heKitTryInit
end heRehydrateChrome

command heBuildLobby
   -- the online lobby overlay: Create/Join a table, watch peers connect over
   -- the DHT, and see every signed presence message verify or drop. Built
   -- hidden; heLobbyShow/heLobbyHide toggle it as one unit. NEEDS AN OXT PASS.
   create graphic "heLobbyBg"
   set the style of graphic "heLobbyBg" to "roundrect"
   set the roundRadius of graphic "heLobbyBg" to 16
   set the rect of graphic "heLobbyBg" to "192,84,832,556"
   set the backgroundColor of graphic "heLobbyBg" to "20,26,24"
   set the borderColor of graphic "heLobbyBg" to kHeGoldColor
   set the borderWidth of graphic "heLobbyBg" to 2
   set the opaque of graphic "heLobbyBg" to true

   heMakeLabel "heLobbyTitle", "212,94,812,124", \
         "holde-em online -- serverless table over the DHT", kHeGoldColor, 16
   -- the create row is FOUR buttons since v0.21.0 (kUIVersion 14): Create,
   -- the 2f transport toggle, the Phase 3 host-mode toggle, Join -- same
   -- row, same overlay, no window growth (since v0.23.0 the stack itself
   -- fits the suite's 720p budget; the overlays always sat above the fold)
   create button "heBtnCreate"
   set the rect of button "heBtnCreate" to "232,134,372,170"
   set the label of button "heBtnCreate" to "Create Table"
   create button "heBtnJoin"
   set the rect of button "heBtnJoin" to "662,134,792,170"
   set the label of button "heBtnJoin" to "Join Table"
   -- 2f: the transport the NEXT Create hosts over (a joiner's transport
   -- comes from the invite itself). DHT swarm is the default; Tor onion
   -- needs OnionXT + a running tor daemon and FAILS CLOSED without them.
   create button "heBtnTransport"
   set the rect of button "heBtnTransport" to "382,134,512,170"
   set the label of button "heBtnTransport" to "Host over: DHT"
   -- Phase 3: whether the NEXT Create hosts as a PLAYER (deals rotate, the
   -- host sits) or as the ORACLE (the host deals every hand and holds no
   -- seat -- spec 7.2 Level 1). Bound to the table at Create; joiners see
   -- the mode on the table line (the signed cfg's level=1).
   create button "heBtnHostMode"
   set the rect of button "heBtnHostMode" to "522,134,652,170"
   set the label of button "heBtnHostMode" to "Host: playing"

   heMakeLabel "heJoinLabel", "212,182,532,204", \
         "paste an invite code, then Join -- or Create to host", kHeWhite, 11
   -- 2f: the tor probe status line (the quickshare-pill states)
   heMakeLabel "heTorLine", "542,182,812,204", "", kHeGoldColor, 11
   create field "heJoinCode"
   set the rect of field "heJoinCode" to "232,208,712,238"
   set the lockText of field "heJoinCode" to false
   set the textSize of field "heJoinCode" to 12
   set the textAlign of field "heJoinCode" to "center"
   create button "heBtnCopyCode"
   set the rect of button "heBtnCopyCode" to "724,206,792,240"
   set the label of button "heBtnCopyCode" to "Copy"

   heMakeLabel "heLobbyId", "212,246,812,270", "", kHeWhite, 12
   heMakeLabel "heLobbyTable", "212,272,812,296", "", kHeGoldColor, 12
   heMakeLabel "heRosterHdr", "212,304,502,326", "Players at this table", kHeWhite, 12
   heMakeLabel "heNetHdr", "522,304,812,326", "Network activity (verify / drop)", kHeWhite, 12

   create field "heLobbyRoster"
   set the rect of field "heLobbyRoster" to "212,328,502,510"
   set the lockText of field "heLobbyRoster" to true
   set the textSize of field "heLobbyRoster" to 12
   set the opaque of field "heLobbyRoster" to true
   set the backgroundColor of field "heLobbyRoster" to "14,18,16"
   set the textColor of field "heLobbyRoster" to kHeWhite
   set the borderWidth of field "heLobbyRoster" to 0

   create field "heLobbyNet"
   set the rect of field "heLobbyNet" to "522,328,812,510"
   set the lockText of field "heLobbyNet" to true
   set the textSize of field "heLobbyNet" to 11
   set the opaque of field "heLobbyNet" to true
   set the backgroundColor of field "heLobbyNet" to "14,18,16"
   set the textColor of field "heLobbyNet" to "150,220,150"
   set the borderWidth of field "heLobbyNet" to 0

   create button "heBtnLeave"
   set the rect of button "heBtnLeave" to "232,516,472,548"
   set the label of button "heBtnLeave" to "Leave (play hotseat)"
   -- host-only: seats everyone who has joined and deals hand 1 (Phase 2d);
   -- heLobbyRefresh keeps it enabled only for a host with 2+ joined players
   create button "heBtnStartGame"
   set the rect of button "heBtnStartGame" to "492,516,732,548"
   set the label of button "heBtnStartGame" to "Start Game"

   heLobbyHide
end heBuildLobby

command heLobbyShow
   heHistHide
   heSettingsHide
   heLobbySetVisible true
   heLobbyRefresh
end heLobbyShow

command heLobbyHide
   heLobbySetVisible false
end heLobbyHide

command heLobbySetVisible pOn
   -- toggle the whole overlay by concrete type (by-name generic "control"
   -- references are not reliably valid in strict OXT; field/button/graphic are)
   local tFields, tButtons, tNm
   if there is a graphic "heLobbyBg" then
      set the visible of graphic "heLobbyBg" to pOn
   end if
   put "heLobbyTitle,heJoinLabel,heTorLine,heJoinCode,heLobbyId,heLobbyTable," \
         & "heRosterHdr,heNetHdr,heLobbyRoster,heLobbyNet" into tFields
   put "heBtnCreate,heBtnJoin,heBtnTransport,heBtnHostMode,heBtnCopyCode,heBtnLeave,heBtnStartGame" into tButtons
   set the itemDelimiter to comma
   repeat for each item tNm in tFields
      if there is a field tNm then
         set the visible of field tNm to pOn
      end if
   end repeat
   repeat for each item tNm in tButtons
      if there is a button tNm then
         set the visible of button tNm to pOn
      end if
   end repeat
end heLobbySetVisible

function heLobbyVisible
   if there is a graphic "heLobbyBg" then
      return the visible of graphic "heLobbyBg"
   end if
   return false
end heLobbyVisible

function heTransportLabel pMode
   -- the lobby toggle's face (2f)
   if pMode is "onion" then
      return "Host over: Tor"
   end if
   return "Host over: DHT"
end heTransportLabel

function heHostModeLabel pMode
   -- the Phase 3 host-mode toggle's face
   if pMode is "oracle" then
      return "Host: ORACLE"
   end if
   return "Host: playing"
end heHostModeLabel

command heHostModeCycle
   -- the lobby's host-mode toggle (Phase 3). Shapes the NEXT Create only --
   -- heTableCreate binds the mode into gGame["oracleHost"] and the signed
   -- cfg (level=1), so a live table's deal level can never flip mid-game.
   heCfgEnsure
   if gCfg["hostMode"] is "oracle" then
      put "play" into gCfg["hostMode"]
   else
      put "oracle" into gCfg["hostMode"]
   end if
   if there is a button "heBtnHostMode" then
      set the label of button "heBtnHostMode" to heHostModeLabel(gCfg["hostMode"])
   end if
   heLobbyRefresh
end heHostModeCycle

command heTransportCycle
   -- the lobby's transport toggle (2f). It shapes the NEXT Create only; a
   -- joiner's transport comes from the invite itself (heInviteParse), so
   -- there is nothing to toggle on the join side -- and an onion invite
   -- pasted into a stack without OnionXT fails closed in heJoinRefusal,
   -- never silently downgrades to the DHT.
   heCfgEnsure
   if gCfg["transport"] is "onion" then
      put "rp1" into gCfg["transport"]
   else
      put "onion" into gCfg["transport"]
   end if
   if there is a button "heBtnTransport" then
      set the label of button "heBtnTransport" to heTransportLabel(gCfg["transport"])
   end if
   heLobbyRefresh
end heTransportCycle

--------------------------------------------------------------------------
-- Settings overlay: the host configures the table (opening chips, blinds,
-- ante, player count, blind schedule, deal speed), then Apply starts a fresh
-- table on the new config. Built hidden; one unit like the lobby/history.
-- All verified statically; needs an OXT pass.
--------------------------------------------------------------------------

command heBuildSettings
   create graphic "heSetBg"
   set the style of graphic "heSetBg" to "roundrect"
   set the roundRadius of graphic "heSetBg" to 16
   set the rect of graphic "heSetBg" to "192,84,832,556"
   set the backgroundColor of graphic "heSetBg" to "20,26,24"
   set the borderColor of graphic "heSetBg" to kHeGoldColor
   set the borderWidth of graphic "heSetBg" to 2
   set the opaque of graphic "heSetBg" to true

   heMakeLabel "heSetTitle", "212,94,812,124", \
         "Table settings -- play the game you want", kHeGoldColor, 16
   heMakeLabel "heSetHint", "212,126,812,148", \
         "the host sets these; Apply starts a fresh table on the new config", kHeWhite, 11

   heMakeSettingRow "heSetStack", "Starting chips", 158
   heMakeSettingRow "heSetSB", "Small blind", 196
   heMakeSettingRow "heSetBB", "Big blind", 234
   heMakeSettingRow "heSetAnte", "Ante (0 for none)", 272
   heMakeSettingRow "heSetSeats", "Players (2-6)", 310

   heMakeLabel "heSetLevelLbl", "232,346,540,374", "Blinds", kHeWhite, 13
   create button "heBtnSetLevel"
   set the rect of button "heBtnSetLevel" to "560,344,792,376"
   set the label of button "heBtnSetLevel" to "Fixed (cash game)"

   -- interval row: meaning follows the blind mode (hands per level / minutes per
   -- level); ignored when blinds are fixed. Its label repaints with the mode.
   heMakeLabel "heSetIntervalLbl", "232,386,540,414", "Raise interval", kHeWhite, 13
   create field "heSetInterval"
   set the rect of field "heSetInterval" to "560,384,792,416"
   set the textAlign of field "heSetInterval" to "center"
   set the textSize of field "heSetInterval" to 14
   set the lockText of field "heSetInterval" to false

   heMakeLabel "heSetSpeedLbl", "232,426,540,454", "Deal speed", kHeWhite, 13
   create button "heBtnSetSpeed"
   set the rect of button "heBtnSetSpeed" to "560,424,792,456"
   set the label of button "heBtnSetSpeed" to "Normal"

   heMakeLabel "heSetLevelInfo", "212,462,540,492", \
         "a rising schedule turns the table into a tournament", kHeGoldColor, 11
   -- sound effects toggle (v0.16.0, Kenney Casino Audio); label follows gCfg["sounds"]
   create button "heBtnSetSounds"
   set the rect of button "heBtnSetSounds" to "560,460,792,492"
   set the label of button "heBtnSetSounds" to "Sounds: On"

   create button "heBtnSetApply"
   set the rect of button "heBtnSetApply" to "232,502,472,540"
   set the label of button "heBtnSetApply" to "Apply & New Table"
   create button "heBtnSetCancel"
   set the rect of button "heBtnSetCancel" to "592,502,792,540"
   set the label of button "heBtnSetCancel" to "Cancel"
   -- host picks a centre-table logo image (any format the engine reads); heTableLogoPick
   create button "heBtnSetLogo"
   set the rect of button "heBtnSetLogo" to "482,502,582,540"
   set the label of button "heBtnSetLogo" to "Table Logo"

   heSettingsHide
end heBuildSettings

command heMakeSettingRow pFieldName, pLabelTxt, pTopY
   heMakeLabel (pFieldName & "Lbl"), "232," & pTopY & ",540," & (pTopY + 28), pLabelTxt, kHeWhite, 13
   create field pFieldName
   set the rect of field pFieldName to "560," & (pTopY - 2) & ",792," & (pTopY + 30)
   set the textAlign of field pFieldName to "center"
   set the textSize of field pFieldName to 14
   set the lockText of field pFieldName to false
end heMakeSettingRow

command heSettingsShow
   heLobbyHide
   heHistHide
   heSettingsSetVisible true
   heSettingsRefresh
end heSettingsShow

command heSettingsHide
   heSettingsSetVisible false
end heSettingsHide

command heSettingsSetVisible pOn
   local tFields, tButtons, tNm
   set the itemDelimiter to comma
   if there is a graphic "heSetBg" then
      set the visible of graphic "heSetBg" to pOn
   end if
   put "heSetTitle,heSetHint,heSetLevelInfo,heSetStackLbl,heSetSBLbl,heSetBBLbl," \
         & "heSetAnteLbl,heSetSeatsLbl,heSetLevelLbl,heSetIntervalLbl,heSetSpeedLbl," \
         & "heSetStack,heSetSB,heSetBB,heSetAnte,heSetSeats,heSetInterval" into tFields
   put "heBtnSetLevel,heBtnSetSpeed,heBtnSetApply,heBtnSetCancel,heBtnSetLogo,heBtnSetSounds" into tButtons
   repeat for each item tNm in tFields
      if there is a field tNm then
         set the visible of field tNm to pOn
      end if
   end repeat
   repeat for each item tNm in tButtons
      if there is a button tNm then
         set the visible of button tNm to pOn
      end if
   end repeat
end heSettingsSetVisible

function heSettingsVisible
   if there is a graphic "heSetBg" then
      return the visible of graphic "heSetBg"
   end if
   return false
end heSettingsVisible

command heSettingsRefresh
   -- populate the fields/buttons from the persistent config
   heCfgEnsure
   if there is not a field "heSetStack" then
      exit heSettingsRefresh
   end if
   set the text of field "heSetStack" to gCfg["startStack"]
   set the text of field "heSetSB" to gCfg["sb"]
   set the text of field "heSetBB" to gCfg["bb"]
   set the text of field "heSetAnte" to gCfg["ante"]
   set the text of field "heSetSeats" to gCfg["numSeats"]
   set the label of button "heBtnSetLevel" to heSettingsLevelLabel(gCfg["levelMode"])
   set the label of button "heBtnSetSpeed" to heSettingsSpeedLabel(gCfg["speed"])
   set the label of button "heBtnSetSounds" to heSettingsSoundsLabel(gCfg["sounds"])
   heSettingsIntervalRefresh
end heSettingsRefresh

command heSettingsIntervalRefresh
   -- the interval field + its label follow the blind mode
   if there is not a field "heSetInterval" then
      exit heSettingsIntervalRefresh
   end if
   set the text of field "heSetIntervalLbl" to heSettingsIntervalLabel(gCfg["levelMode"])
   if gCfg["levelMode"] is "time" then
      set the text of field "heSetInterval" to gCfg["levelMinutes"]
   else
      set the text of field "heSetInterval" to gCfg["levelEvery"]
   end if
end heSettingsIntervalRefresh

command heSettingsIntervalStash
   -- read the interval field into the gCfg key for the CURRENT mode, so cycling
   -- the mode never discards what the host typed. A bad value is left for Apply
   -- to reject rather than silently overwriting the stored one.
   local tVal
   if there is not a field "heSetInterval" then
      exit heSettingsIntervalStash
   end if
   put word 1 of the text of field "heSetInterval" into tVal
   if not heSettingsNumOk(tVal, 1) then
      exit heSettingsIntervalStash
   end if
   if gCfg["levelMode"] is "time" then
      put tVal into gCfg["levelMinutes"]
   else
      put tVal into gCfg["levelEvery"]
   end if
end heSettingsIntervalStash

function heSettingsLevelLabel pMode
   switch pMode
      case "hands"
         return "Rising, by hands played"
      case "time"
         return "Rising, on a timer"
   end switch
   return "Fixed (cash game)"
end heSettingsLevelLabel

function heSettingsIntervalLabel pMode
   switch pMode
      case "hands"
         return "Hands per level"
      case "time"
         return "Minutes per level"
   end switch
   return "Raise interval (n/a for cash)"
end heSettingsIntervalLabel

function heSettingsSoundsLabel pMode
   if pMode is "off" then
      return "Sounds: Off"
   end if
   return "Sounds: On"
end heSettingsSoundsLabel

function heSettingsSpeedLabel pSpeed
   switch pSpeed
      case "fast"
         return "Fast"
      case "slow"
         return "Slow"
   end switch
   return "Normal"
end heSettingsSpeedLabel

command heSettingsCycle pWhich
   -- advance an enum choice and re-label its button (live on gCfg; number fields
   -- stage until Apply)
   heCfgEnsure
   switch pWhich
      case "level"
         -- off -> by hands -> on a timer -> off. Stash the current interval field
         -- back to the right gCfg key before switching, so cycling never loses it.
         heSettingsIntervalStash
         switch gCfg["levelMode"]
            case "off"
               put "hands" into gCfg["levelMode"]
               break
            case "hands"
               put "time" into gCfg["levelMode"]
               break
            default
               put "off" into gCfg["levelMode"]
         end switch
         set the label of button "heBtnSetLevel" to heSettingsLevelLabel(gCfg["levelMode"])
         heSettingsIntervalRefresh
         break
      case "speed"
         switch gCfg["speed"]
            case "normal"
               put "fast" into gCfg["speed"]
               break
            case "fast"
               put "slow" into gCfg["speed"]
               break
            default
               put "normal" into gCfg["speed"]
         end switch
         set the label of button "heBtnSetSpeed" to heSettingsSpeedLabel(gCfg["speed"])
         break
      case "sounds"
         if gCfg["sounds"] is "on" then
            put "off" into gCfg["sounds"]
         else
            put "on" into gCfg["sounds"]
         end if
         set the label of button "heBtnSetSounds" to heSettingsSoundsLabel(gCfg["sounds"])
         if gCfg["sounds"] is "on" then
            -- audible confirmation, which doubles as a live test of the play path
            heSndPlay "check"
         end if
         break
   end switch
end heSettingsCycle

command heSettingsApply
   -- validate the number fields, commit to the config, then start a fresh table
   local tStack, tSB, tBB, tAnte, tSeats, tInterval
   heSettingsIntervalStash
   put word 1 of the text of field "heSetStack" into tStack
   put word 1 of the text of field "heSetSB" into tSB
   put word 1 of the text of field "heSetBB" into tBB
   put word 1 of the text of field "heSetAnte" into tAnte
   put word 1 of the text of field "heSetSeats" into tSeats
   put word 1 of the text of field "heSetInterval" into tInterval
   if not heSettingsNumOk(tStack, 1) or not heSettingsNumOk(tSB, 0) \
         or not heSettingsNumOk(tBB, 1) or not heSettingsNumOk(tAnte, 0) \
         or not heSettingsNumOk(tSeats, kHeMinSeats) then
      heUISetStatus "Settings: every field must be a whole number (chips>=1, seats>=2)."
      exit heSettingsApply
   end if
   if (gCfg["levelMode"] is "hands" or gCfg["levelMode"] is "time") \
         and not heSettingsNumOk(tInterval, 1) then
      heUISetStatus "Settings: the blind interval must be a whole number of at least 1."
      exit heSettingsApply
   end if
   -- clamp / normalise: BB is at least the SB, seats within the layout
   if tBB < tSB then
      put tSB into tBB
   end if
   if tSeats > kHeMaxSeats then
      put kHeMaxSeats into tSeats
   end if
   if tSeats < kHeMinSeats then
      put kHeMinSeats into tSeats
   end if
   if tAnte >= tStack then
      heUISetStatus "Settings: the ante must be smaller than the starting stack."
      exit heSettingsApply
   end if
   heApplyCfg tStack, tSB, tBB, tAnte, tSeats, gCfg["levelMode"], \
         gCfg["levelEvery"], gCfg["levelMinutes"], gCfg["speed"]
   heSettingsHide
   heTableNew
   heUIClearCards
   heUISetStatus "New table: " & tSeats & " seats, " & tStack & " chips, blinds " \
         & tSB & "/" & tBB & ".  Press Deal."
end heSettingsApply

function heSettingsNumOk pVal, pMin
   -- a whole, non-negative number at least pMin
   if pVal is not a number then
      return false
   end if
   if pVal is not trunc(pVal) then
      return false
   end if
   return pVal >= pMin
end heSettingsNumOk

command heLobbyRefresh
   -- repaint identity, table line, roster, and the recent net activity from
   -- gGame -- called on every handshake and every ingested wire. No-op if the
   -- overlay is not built or not visible.
   local tRoleTxt, tKeyPub, tRoster, tSeatRole, tNet, tNetAll, tCount
   local tMyPub, tTableId, tOnlineTxt
   if not (there is a field "heLobbyRoster") then
      exit heLobbyRefresh
   end if
   if not heLobbyVisible() then
      exit heLobbyRefresh
   end if
   heCfgEnsure
   -- copy array elements to plain locals before chunking them (house gotcha H6)
   put gGame["idPubHex"] into tMyPub
   put gGame["tableIdHex"] into tTableId
   -- identity
   if gGame["idFingerprint"] is empty then
      set the text of field "heLobbyId" to "You: identity is generated when you Create or Join."
   else
      set the text of field "heLobbyId" to \
            "You: " & gGame["idFingerprint"] & "   key " & char 1 to 12 of tMyPub
   end if
   -- table / role / online line
   if gGame["online"] is "true" then
      if gGame["isHost"] is "true" then
         put "host" into tRoleTxt
      else
         put "player" into tRoleTxt
      end if
      if gGame["transport"] is "onion" then
         put "-- online over tor --" into tOnlineTxt
      else
         put "-- online --" into tOnlineTxt
      end if
      -- Phase 3: the signed cfg's level=1 marks an ORACLE table -- say so
      -- to every joiner (the host deals every hand and holds no seat)
      if heNetCfgVal("level", 0) is 1 then
         put "  ORACLE table: the host deals, holds no seat." after tOnlineTxt
      end if
      set the text of field "heLobbyTable" to \
            "Table " & char 1 to 16 of tTableId & "   role " & tRoleTxt & "   " & tOnlineTxt
   else
      set the text of field "heLobbyTable" to "Not connected. Create a table to host, or Join with a code."
   end if
   -- 2f: transport toggle label + the tor status line; Phase 3: host mode
   if there is a button "heBtnTransport" then
      set the label of button "heBtnTransport" to heTransportLabel(gCfg["transport"])
   end if
   if there is a button "heBtnHostMode" then
      set the label of button "heBtnHostMode" to heHostModeLabel(gCfg["hostMode"])
   end if
   if there is a field "heTorLine" then
      set the text of field "heTorLine" to heNetOnionStatusTxt()
   end if
   -- roster from the admitted set (+ roles); the host key is marked
   put empty into tRoster
   repeat for each key tKeyPub in gGame["admittedA"]
      put gGame["roleByPub"][tKeyPub] into tSeatRole
      if tSeatRole is empty then
         put "player" into tSeatRole
      end if
      if tKeyPub is gGame["idPubHex"] then
         put "* " after tRoster
      else
         put "  " after tRoster
      end if
      put char 1 to 12 of tKeyPub & "   " & tSeatRole & return after tRoster
   end repeat
   if tRoster is empty then
      put "(no one yet)" into tRoster
   end if
   set the text of field "heLobbyRoster" to tRoster
   -- last ~14 lines of network activity, newest at the bottom
   put gGame["netLog"] into tNetAll
   put the number of lines of tNetAll into tCount
   if tCount > 14 then
      put line (tCount - 13) to tCount of tNetAll into tNet
   else
      put tNetAll into tNet
   end if
   set the text of field "heLobbyNet" to tNet
   -- Start Game is the host's verb, once the table is live and the game is
   -- not already running (joined-player count is checked on the click)
   heEnableBtn "heBtnStartGame", (gGame["online"] is "true" \
         and gGame["isHost"] is "true" and gGame["gameOn"] is not "true")
end heLobbyRefresh

command heBuildHistory
   -- the hand-history overlay: the folded, re-verified transcript. Built
   -- hidden; heHistShow/heHistHide toggle it. NEEDS AN OXT PASS.
   create graphic "heHistBg"
   set the style of graphic "heHistBg" to "roundrect"
   set the roundRadius of graphic "heHistBg" to 16
   set the rect of graphic "heHistBg" to "192,84,832,556"
   set the backgroundColor of graphic "heHistBg" to "20,26,24"
   set the borderColor of graphic "heHistBg" to kHeGoldColor
   set the borderWidth of graphic "heHistBg" to 2
   set the opaque of graphic "heHistBg" to true

   heMakeLabel "heHistTitle", "212,94,812,124", \
         "hand history -- replayed from the transcript & re-verified", kHeGoldColor, 15
   heMakeLabel "heHistAudit", "212,128,812,150", "", kHeWhite, 12

   create field "heHistList"
   set the rect of field "heHistList" to "212,158,812,502"
   set the lockText of field "heHistList" to true
   set the textSize of field "heHistList" to 12
   set the opaque of field "heHistList" to true
   set the backgroundColor of field "heHistList" to "14,18,16"
   set the textColor of field "heHistList" to kHeWhite
   set the borderWidth of field "heHistList" to 0

   create button "heBtnHistVerify"
   set the rect of button "heBtnHistVerify" to "212,510,352,544"
   set the label of button "heBtnHistVerify" to "Re-verify"
   create button "heBtnHistExport"
   set the rect of button "heBtnHistExport" to "360,510,540,544"
   set the label of button "heBtnHistExport" to "Copy transcript"
   create button "heBtnHistClose"
   set the rect of button "heBtnHistClose" to "712,510,812,544"
   set the label of button "heBtnHistClose" to "Close"

   heHistHide
end heBuildHistory

command heHistShow
   heLobbyHide
   heSettingsHide
   heHistSetVisible true
   heHistRefresh
end heHistShow

command heHistHide
   heHistSetVisible false
end heHistHide

command heHistSetVisible pOn
   local tFields, tButtons, tNm
   if there is a graphic "heHistBg" then
      set the visible of graphic "heHistBg" to pOn
   end if
   put "heHistTitle,heHistAudit,heHistList" into tFields
   put "heBtnHistVerify,heBtnHistExport,heBtnHistClose" into tButtons
   set the itemDelimiter to comma
   repeat for each item tNm in tFields
      if there is a field tNm then
         set the visible of field tNm to pOn
      end if
   end repeat
   repeat for each item tNm in tButtons
      if there is a button tNm then
         set the visible of button tNm to pOn
      end if
   end repeat
end heHistSetVisible

function heHistVisible
   if there is a graphic "heHistBg" then
      return the visible of graphic "heHistBg"
   end if
   return false
end heHistVisible

command heHistRefresh
   -- fold the current transcript and show the per-hand history plus TWO audits:
   -- the settlement (the fold re-derives every payout and compares it to the
   -- logged one) and, for Level 0 hands, the DEAL (heAuditDealsFromLog
   -- re-derives the committed shuffle from the revealed seeds). An all-verified
   -- transcript is the legitimacy proof.
   local tFold, tHistTxt, tErrs, tAuditTxt, tDealAudit, tLogTxt
   local tXlatTxt, tSrcTxt
   if not (there is a field "heHistList") then
      exit heHistRefresh
   end if
   -- copy the transcript to a plain local before measuring/chunking it (H6)
   put gGame["log"] into tLogTxt
   put "hotseat transcript" into tSrcTxt
   -- The lobby and the hotseat game share gGame["log"] in two INCOMPATIBLE
   -- formats (heLogIsCleanHotseat spells out why). 2e: an ONLINE signed
   -- chain is no longer a dead end here -- heNetLogToHotseat translates it
   -- into the hotseat shape and the SAME fold + deal audit run over the
   -- translation ("the live audit verdicts land in the net feed" is over:
   -- History now folds online play too). A chain with no game in it (a
   -- lobby that never dealt) still gets the honest say-what-is-there text.
   if not heLogIsCleanHotseat(tLogTxt) then
      if tLogTxt is empty then
         set the text of field "heHistList" to \
               "No transcript yet. Play a hand (Deal), then re-open History."
         set the text of field "heHistAudit" to \
               "NOT AUDITED -- nothing to replay yet."
         set the textColor of field "heHistAudit" to kHeGoldColor
         exit heHistRefresh
      end if
      put heNetLogToHotseat(tLogTxt) into tXlatTxt
      if tXlatTxt is empty then
         set the text of field "heHistList" to \
               "This transcript is the ONLINE signed chain (" \
               & the number of lines of tLogTxt & " wires) with no dealt hands yet." & return \
               & "Every wire was signature- and chain-verified as it arrived. Play a" & return \
               & "hand and re-open History, or use Copy transcript to export the chain."
         set the text of field "heHistAudit" to \
               "NOT AUDITED HERE -- online chain (verified on ingest), no hands to replay."
         set the textColor of field "heHistAudit" to kHeGoldColor
         exit heHistRefresh
      end if
      put "online signed chain, translated (" \
            & the number of lines of tLogTxt & " wires)" into tSrcTxt
      put tXlatTxt into tLogTxt
   end if
   put heFoldTranscript(tLogTxt) into tFold
   put tFold["history"] into tHistTxt
   put tFold["errors"] into tErrs
   put heAuditDealsFromLog(tLogTxt) into tDealAudit
   if tHistTxt is empty then
      put "No completed hands yet. Play a hand (Deal), then re-open History." into tHistTxt
   end if
   set the text of field "heHistList" to "source: " & tSrcTxt & return & return \
         & tHistTxt & return & return \
         & "-- deal audit (commit-reveal shuffle) --" & return & tDealAudit
   if tErrs is empty then
      put "AUDIT PASSED -- every hand's settlement matched the independent replay." into tAuditTxt
      set the textColor of field "heHistAudit" to "150,220,150"
   else
      put "AUDIT FAILED -- " & line 1 of tErrs into tAuditTxt
      set the textColor of field "heHistAudit" to kHeRed
   end if
   set the text of field "heHistAudit" to tAuditTxt
end heHistRefresh

command heMakeLabel pName, pRect, pText, pColor, pSize
   create field pName
   set the rect of field pName to pRect
   set the lockText of field pName to true
   set the textAlign of field pName to "center"
   set the textSize of field pName to pSize
   set the textColor of field pName to pColor
   set the borderWidth of field pName to 0
   set the opaque of field pName to false
   set the text of field pName to pText
end heMakeLabel

command heWipeChrome
   local tPos
   repeat with tPos = the number of controls of card 1 down to 1
      if the short name of control tPos of card 1 begins with "he" then
         delete control tPos of card 1
      end if
   end repeat
end heWipeChrome

command heMakeCardSlot pSlotName, pCenterX, pCenterY
   create field pSlotName
   set the rect of field pSlotName to \
         (pCenterX - kHeCardW div 2) & comma & (pCenterY - kHeCardH div 2) & comma \
         & (pCenterX + kHeCardW div 2) & comma & (pCenterY + kHeCardH div 2)
   set the lockText of field pSlotName to true
   set the textAlign of field pSlotName to "center"
   set the textSize of field pSlotName to 22
   set the textStyle of field pSlotName to "bold"
   set the opaque of field pSlotName to true
   set the backgroundColor of field pSlotName to kHeWhite
   set the borderWidth of field pSlotName to 1
   set the borderColor of field pSlotName to "60,60,60"
   set the visible of field pSlotName to false
   -- remember the centre so heKitTryInit can pool a card sprite over this slot
   put pCenterX & comma & pCenterY into gSlotCenter[pSlotName]
end heMakeCardSlot

function heSuitGlyph pSuitVal
   -- built from codepoints so the source stays ASCII (no glyphs in the file)
   switch pSuitVal
      case 1
         return numToCodepoint(9827)  -- clubs
      case 2
         return numToCodepoint(9830)  -- diamonds
      case 3
         return numToCodepoint(9829)  -- hearts
      case 4
         return numToCodepoint(9824)  -- spades
   end switch
   return "?"
end heSuitGlyph

function heCardFace pIdx
   -- rank + suit glyph, e.g. A + spade; ten shows as "10"
   local tName, tRankCh, tRankTxt
   put heCardName(pIdx) into tName
   put char 1 of tName into tRankCh
   if tRankCh is "T" then
      put "10" into tRankTxt
   else
      put tRankCh into tRankTxt
   end if
   return tRankTxt & heSuitGlyph(heCardSuitVal(pIdx))
end heCardFace

function heKenneyFrame pIdx
   -- map an internal card id (1..52) to its Kenney "Playing Cards Pack" atlas frame
   -- BASE name (no extension), for kit-mode card art. heCardName gives rank+suit
   -- ("As","Ts","7c"); Kenney names frames card<Suit><Rank>: c->Clubs d->Diamonds
   -- h->Hearts s->Spades, ten as "10". So 52 (As) -> "cardSpadesA", Ts -> "cardSpades10".
   -- The vendored atlas (assets/cards/playingCards.xml, CC0) carries the ".png" suffix
   -- on its SubTexture names; whether Box2Dxt keeps or strips it on load is a
   -- per-sheet question (gotcha 24) resolved on the OXT pass. Pinned by tools/atlas-kat.py.
   local tName, tRankCh, tSuitCh, tSuitTxt, tRankTxt
   put heCardName(pIdx) into tName
   put char 1 of tName into tRankCh
   put char 2 of tName into tSuitCh
   switch tSuitCh
      case "c"
         put "Clubs" into tSuitTxt
         break
      case "d"
         put "Diamonds" into tSuitTxt
         break
      case "h"
         put "Hearts" into tSuitTxt
         break
      case "s"
         put "Spades" into tSuitTxt
         break
   end switch
   if tRankCh is "T" then
      put "10" into tRankTxt
   else
      put tRankCh into tRankTxt
   end if
   return "card" & tSuitTxt & tRankTxt
end heKenneyFrame

command heMakeActionButton pBtnName, pLabelTxt, pLeftX
   create button pBtnName
   set the rect of button pBtnName to pLeftX & ",556" & comma & (pLeftX + 76) & ",588"
   set the label of button pBtnName to pLabelTxt
end heMakeActionButton

--------------------------------------------------------------------------
-- v0.14.0 UI pack: seat avatars, host table logo, bet slider (all local).
-- Every path is guarded so a missing file or hidden control never breaks a
-- deal; the visual details (round crop, scale, blend, placement) are what an
-- OXT pass tunes. No image binary ever crosses into script (H3/H6): we only
-- ever set "the filename" of an image control to a plain path string.
--------------------------------------------------------------------------

command heMakeAvatar pSeatNum, pCx, pCy
   -- three stacked controls at (pCx,pCy): the disc, the initial fallback, the image
   local tRad, tRect
   put kHeAvatarSize div 2 into tRad
   put (pCx - tRad) & comma & (pCy - tRad) & comma & (pCx + tRad) & comma & (pCy + tRad) into tRect
   create graphic ("heSeatAv" & pSeatNum)
   set the style of graphic ("heSeatAv" & pSeatNum) to "oval"
   set the rect of graphic ("heSeatAv" & pSeatNum) to tRect
   set the opaque of graphic ("heSeatAv" & pSeatNum) to true
   set the lineSize of graphic ("heSeatAv" & pSeatNum) to 2
   set the foregroundColor of graphic ("heSeatAv" & pSeatNum) to kHeGoldColor
   heMakeLabel "heSeatAvTx" & pSeatNum, tRect, "", kHeWhite, 20
   set the textStyle of field ("heSeatAvTx" & pSeatNum) to "bold"
   create image ("heSeatAvImg" & pSeatNum)
   set the rect of image ("heSeatAvImg" & pSeatNum) to tRect
   set the visible of image ("heSeatAvImg" & pSeatNum) to false
end heMakeAvatar

command heSeatAvatarRender pSeatNum
   -- choose picked-image vs coloured-initial for one seat; caches the choice in
   -- gAvatarOn so heSeatChromeVisible (the 4Hz hot path) never reloads the file
   local tPath, tName, tInitial, tFill, tPaths, tLocTxt, tCx, tCy, tNatW, tNatH
   set the itemDelimiter to ";"
   put item pSeatNum of kHeAvatarFills into tFill
   set the itemDelimiter to comma
   if there is a graphic ("heSeatAv" & pSeatNum) then
      set the backgroundColor of graphic ("heSeatAv" & pSeatNum) to tFill
   end if
   put the uHeAvatarPaths of this stack into tPaths
   put line pSeatNum of tPaths into tPath
   if tPath is not empty and there is a file tPath then
      put "true" into gAvatarOn[pSeatNum]
      if there is an image ("heSeatAvImg" & pSeatNum) then
         -- setting the filename resets the control to the picture's natural size,
         -- so re-rect AFTER it -- aspect-fit inside the disc (formatWidth/Height are
         -- the loaded picture's natural pixels) so a non-square photo letterboxes
         -- on the coloured disc instead of stretching
         set the filename of image ("heSeatAvImg" & pSeatNum) to tPath
         if there is a graphic ("heSeatAv" & pSeatNum) then
            put the loc of graphic ("heSeatAv" & pSeatNum) into tLocTxt
            put item 1 of tLocTxt into tCx
            put item 2 of tLocTxt into tCy
            put the formatWidth of image ("heSeatAvImg" & pSeatNum) into tNatW
            put the formatHeight of image ("heSeatAvImg" & pSeatNum) into tNatH
            set the rect of image ("heSeatAvImg" & pSeatNum) to \
                  heFitRect(tNatW, tNatH, tCx, tCy, kHeAvatarSize)
         end if
         set the visible of image ("heSeatAvImg" & pSeatNum) to true
      end if
      if there is a field ("heSeatAvTx" & pSeatNum) then
         set the visible of field ("heSeatAvTx" & pSeatNum) to false
      end if
   else
      put "false" into gAvatarOn[pSeatNum]
      if there is an image ("heSeatAvImg" & pSeatNum) then
         set the visible of image ("heSeatAvImg" & pSeatNum) to false
      end if
      put item pSeatNum of kHeSeatNames into tName
      put toUpper(char 1 of tName) into tInitial
      if there is a field ("heSeatAvTx" & pSeatNum) then
         set the text of field ("heSeatAvTx" & pSeatNum) to tInitial
         set the visible of field ("heSeatAvTx" & pSeatNum) to true
      end if
   end if
end heSeatAvatarRender

command heSeatAvatarPick pSeatNum
   local tFile, tName, tPrompt, tPaths
   set the itemDelimiter to comma
   put item pSeatNum of kHeSeatNames into tName
   put "Choose an avatar image for " & tName into tPrompt
   answer file tPrompt with type "Images|png,jpg,jpeg,gif,bmp"
   put it into tFile
   if tFile is empty then
      exit heSeatAvatarPick   -- cancelled
   end if
   -- ONE uHeAvatarPaths property, line N = seat N's path (paths cannot contain a
   -- newline, so the line index is safe). A computed property NAME would need the
   -- parenthesised dynamic-property form, which is not portable xTalk -- H9.
   put the uHeAvatarPaths of this stack into tPaths
   put tFile into line pSeatNum of tPaths
   set the uHeAvatarPaths of this stack to tPaths
   heSeatAvatarRender pSeatNum
   heUISetStatus tName && "portrait updated."
end heSeatAvatarPick

command heTableLogoPick
   local tFile
   answer file "Choose a table logo image" with type "Images|png,jpg,jpeg,gif,bmp"
   put it into tFile
   if tFile is empty then
      exit heTableLogoPick   -- cancelled
   end if
   set the uHeTableLogoPath of this stack to tFile
   heTableLogoRender
   heUISetStatus "Table logo updated."
end heTableLogoPick

command heTableLogoRender
   local tPath, tNatW, tNatH
   if there is not an image "heTableLogo" then
      exit heTableLogoRender
   end if
   put the uHeTableLogoPath of this stack into tPath
   if tPath is not empty and there is a file tPath then
      -- filename first (it resets the control to the picture's natural size),
      -- then aspect-fit the rect into the logo box centred on the felt
      set the filename of image "heTableLogo" to tPath
      put the formatWidth of image "heTableLogo" into tNatW
      put the formatHeight of image "heTableLogo" into tNatH
      set the rect of image "heTableLogo" to heFitRect(tNatW, tNatH, 512, 286, kHeLogoBox)
      set the blendLevel of image "heTableLogo" to kHeLogoDim
      set the visible of image "heTableLogo" to true
   else
      set the visible of image "heTableLogo" to false
   end if
end heTableLogoRender

function heFitRect pNatW, pNatH, pCx, pCy, pBox
   -- the largest aspect-preserving rect that fits a pBox square centred on
   -- (pCx,pCy). Pure values-in/values-out (H5).
   -- Bad/missing natural sizes (image not loaded yet) fall back to the full box.
   -- WHAT "integer div" ACTUALLY BUYS, corrected 2026-08-17: it buys exact
   -- SYMMETRY about (pCx,pCy), not an exact width. The rect is built as
   -- centre -+ (t div 2), so its rendered size is 2 * (t div 2) -- one pixel
   -- SHORT whenever the fitted t is odd. That is deliberate now rather than
   -- merely true: the shrink-or-equal, symmetric-about-the-centre property is
   -- what tools/check-table-layout.py's exemption for BOTH callers rests on
   -- (it derives the built heSeatAv<N> / heTableLogo rects and argues this
   -- runtime re-fit can only ever shrink inside them), and an exact-width
   -- version would push one edge out to ceil(t/2) and weaken that argument
   -- for a pixel nobody can see on a blendLevel watermark. Pinned in harness
   -- section 21 -- both the symmetry and the one-pixel cost -- so the next
   -- person to want exact widths changes a checked fact, not a comment.
   local tW, tH
   if pNatW is not a number or pNatH is not a number or pNatW <= 0 or pNatH <= 0 then
      put pBox into tW
      put pBox into tH
   else if pNatW >= pNatH then
      put pBox into tW
      put round(pBox * pNatH / pNatW) into tH
   else
      put pBox into tH
      put round(pBox * pNatW / pNatH) into tW
   end if
   return (pCx - tW div 2) & comma & (pCy - tH div 2) & comma \
         & (pCx + tW div 2) & comma & (pCy + tH div 2)
end heFitRect

command heBetSliderShow pMinTo, pMaxTo
   if there is not a scrollbar "heBetSlider" then
      exit heBetSliderShow
   end if
   if pMaxTo <= pMinTo then
      -- nothing to slide (only an all-in is available): hide it
      set the visible of scrollbar "heBetSlider" to false
      exit heBetSliderShow
   end if
   set the startValue of scrollbar "heBetSlider" to pMinTo
   set the endValue of scrollbar "heBetSlider" to pMaxTo
   set the thumbPosition of scrollbar "heBetSlider" to pMinTo
   -- track clicks step by a big blind (page = 4 blinds), so keyboard-free sizing
   -- lands on natural amounts
   if gGame["bb"] is a number and gGame["bb"] > 0 then
      set the lineInc of scrollbar "heBetSlider" to gGame["bb"]
      set the pageInc of scrollbar "heBetSlider" to gGame["bb"] * 4
   end if
   set the visible of scrollbar "heBetSlider" to true
end heBetSliderShow

command heBetSliderHide
   if there is a scrollbar "heBetSlider" then
      set the visible of scrollbar "heBetSlider" to false
   end if
end heBetSliderHide

command heBetSliderSync
   -- move the thumb to match the amount box (after a Min/1/2/Pot button), clamped
   local tVal
   if there is not a scrollbar "heBetSlider" then
      exit heBetSliderSync
   end if
   if not the visible of scrollbar "heBetSlider" then
      exit heBetSliderSync
   end if
   put word 1 of the text of field "heAmount" into tVal
   if tVal is not a number then
      exit heBetSliderSync
   end if
   if tVal < the startValue of scrollbar "heBetSlider" then
      put the startValue of scrollbar "heBetSlider" into tVal
   end if
   if tVal > the endValue of scrollbar "heBetSlider" then
      put the endValue of scrollbar "heBetSlider" into tVal
   end if
   set the thumbPosition of scrollbar "heBetSlider" to tVal
end heBetSliderSync

on scrollbarDrag pNewPos
   -- the bet slider feeds the amount box live; any other scrollbar passes through
   if the short name of the target is "heBetSlider" then
      set the text of field "heAmount" to round(pNewPos)
      exit scrollbarDrag
   end if
   pass scrollbarDrag
end scrollbarDrag

-- track/step clicks on the scale: the engine moves the thumb as its DEFAULT
-- action, so these always pass, and the field syncs on a short deferred send
-- (after the default has landed) -- the house defer-out-of-dispatch pattern.
on scrollbarLineInc
   if the short name of the target is "heBetSlider" then
      send "heBetSliderFromThumb" to me in 30 milliseconds
   end if
   pass scrollbarLineInc
end scrollbarLineInc

on scrollbarLineDec
   if the short name of the target is "heBetSlider" then
      send "heBetSliderFromThumb" to me in 30 milliseconds
   end if
   pass scrollbarLineDec
end scrollbarLineDec

on scrollbarPageInc
   if the short name of the target is "heBetSlider" then
      send "heBetSliderFromThumb" to me in 30 milliseconds
   end if
   pass scrollbarPageInc
end scrollbarPageInc

on scrollbarPageDec
   if the short name of the target is "heBetSlider" then
      send "heBetSliderFromThumb" to me in 30 milliseconds
   end if
   pass scrollbarPageDec
end scrollbarPageDec

command heBetSliderFromThumb
   -- deferred: read wherever the engine left the thumb and mirror it into the
   -- amount box. Guarded against the slider having been hidden since the send.
   -- Delayed by `send`, so the defaultStack is whatever is current WHEN IT
   -- ARRIVES, not the stack that armed it. Unqualified control references
   -- below resolve against that, so pin it first (gate:
   -- tools/check-timer-stack-pin.py; the idiom is holde-em's, engine-proven).
   set the defaultStack to the short name of this stack
   if there is not a scrollbar "heBetSlider" then
      exit heBetSliderFromThumb
   end if
   if not the visible of scrollbar "heBetSlider" then
      exit heBetSliderFromThumb
   end if
   if there is a field "heAmount" then
      set the text of field "heAmount" to round(the thumbPosition of scrollbar "heBetSlider")
   end if
end heBetSliderFromThumb

--------------------------------------------------------------------------
-- v0.16.0 sounds: Kenney "Casino Audio" (CC0), vendored WAVs in assets/sounds
-- next to the saved stack (uHeSoundsPath overrides the folder). Import-once as
-- audioClips (clips persist inside a saved stack; the guard makes re-init and
-- re-open no-ops), play at message boundaries only (turn-rate -- never per
-- frame), and every engine call is guarded so a missing file or an engine
-- without audio support degrades to silence, never a broken deal.
-- All of it: verified statically; NEEDS AN OXT PASS.
--------------------------------------------------------------------------

function heSndFilesFor pKind
   -- game moment -> comma list of vendored files (2+ alternate via gSndTick).
   -- "shuffle" is vendored + mapped but not yet wired into the flow: it is 3 s
   -- long and would be cut off by the deal sound on the same beat; the deal-
   -- animation increment paces it before the first deal.
   switch pKind
      case "shuffle"
         return "cardShuffle.wav"
      case "deal"
         return "cardSlide1.wav,cardSlide2.wav"
      case "board"
         return "cardPlace1.wav,cardPlace2.wav"
      case "fold"
         return "cardShove1.wav"
      case "check"
         return "chipLay1.wav"
      case "chips"
         return "chipsHandle1.wav,chipsHandle2.wav"
      case "allin"
         return "chipsCollide1.wav"
      case "win"
         return "chipsStack1.wav"
   end switch
   return ""
end heSndFilesFor

command heSndVerb pVerb
   -- accepted-action funnel (called from heEngineDo): verb -> sound kind
   switch pVerb
      case "fold"
         heSndPlay "fold"
         break
      case "check"
         heSndPlay "check"
         break
      case "allin"
         heSndPlay "allin"
         break
      case "call"
      case "bet"
      case "raise"
         heSndPlay "chips"
         break
   end switch
end heSndVerb

command heSndTryInit
   -- import each vendored WAV as an audioClip, once. A clip already present
   -- (saved stack, or a prior init) is just marked playable. Failures mark the
   -- single file bad and move on -- one broken file never mutes the rest.
   local tFile, tFolder, tFull, tImpErr
   if gSndChk is "true" then
      exit heSndTryInit
   end if
   put "true" into gSndChk
   -- import lands in the defaultStack: pin it to THIS stack so a message-box
   -- call can never import the clips into whatever stack happens to be front
   set the defaultStack to the short name of this stack
   set the itemDelimiter to comma
   put the uHeSoundsPath of this stack into tFolder
   if tFolder is empty then
      put heStackFolder() into tFolder
      if tFolder is empty then
         exit heSndTryInit   -- unsaved stack, no override: stay silent
      end if
      put tFolder & "/assets/sounds" into tFolder
   end if
   repeat for each item tFile in kHeSoundFiles
      if there is an audioClip tFile then
         put "true" into gSndOk[tFile]
         next repeat
      end if
      put tFolder & "/" & tFile into tFull
      if there is not a file tFull then
         next repeat
      end if
      try
         import audioClip from file tFull
         -- some engines name the imported clip after the full path: normalise
         if there is not an audioClip tFile then
            set the name of audioClip (the number of audioClips of this stack) \
                  of this stack to tFile
         end if
         if there is an audioClip tFile then
            put "true" into gSndOk[tFile]
         end if
      catch tImpErr
         -- leave gSndOk[tFile] unset: this one stays silent, the rest still play
      end try
   end repeat
end heSndTryInit

command heSndPlay pKind
   -- the ONE playback gate: config toggle -> lazy init -> rotate -> guarded play
   local tList, tCount, tIdx, tFile, tPlayErr
   heCfgEnsure
   if gCfg["sounds"] is not "on" then
      exit heSndPlay
   end if
   heSndTryInit
   set the itemDelimiter to comma
   put heSndFilesFor(pKind) into tList
   if tList is empty then
      exit heSndPlay
   end if
   put the number of items of tList into tCount
   if gSndTick is not a number then
      put 0 into gSndTick
   end if
   add 1 to gSndTick
   put (gSndTick mod tCount) + 1 into tIdx
   put item tIdx of tList into tFile
   if gSndOk[tFile] is not "true" then
      exit heSndPlay
   end if
   try
      play audioClip tFile
   catch tPlayErr
      -- an engine without audio (or a hosed clip): mark it bad and stay silent
      put "false" into gSndOk[tFile]
   end try
end heSndPlay

command heProbeSounds
   -- message-box diagnostic (mirror of heProbeKit): what resolved, what loaded
   local tOut, tFile, tFolder, tFull
   set the itemDelimiter to comma
   put "holde-em sound probe  stack v" & kHeVersion & return into tOut
   put "sounds enabled (gCfg): " & gCfg["sounds"] & return after tOut
   put the uHeSoundsPath of this stack into tFolder
   if tFolder is empty then
      put heStackFolder() into tFolder
      if tFolder is empty then
         put "folder: stack UNSAVED and uHeSoundsPath unset -- save the stack" \
               & " with assets/sounds next to it, or set uHeSoundsPath" & return after tOut
      else
         put tFolder & "/assets/sounds" into tFolder
      end if
   end if
   put "folder: " & tFolder & return after tOut
   put "init ran: " & (gSndChk is "true") & return after tOut
   repeat for each item tFile in kHeSoundFiles
      put tFolder & "/" & tFile into tFull
      put tFile & "  file:" & (there is a file tFull) \
            & "  clip:" & (there is an audioClip tFile) \
            & "  ok:" & (gSndOk[tFile] is "true") & return after tOut
   end repeat
   put "run heSndReload after moving files or loading the pack" & return after tOut
   put tOut
end heProbeSounds

command heSndReload
   -- clear the cached init so the next play (or a probe after it) re-imports
   put empty into gSndChk
   put empty into gSndOk
   heSndTryInit
end heSndReload

function heStackFolder
   -- the folder that holds the SAVED stack file, so an assets/ folder sitting next
   -- to the stack is found automatically. Empty when the stack was pasted into the
   -- message box and never saved (there is no file to be relative to) -- then set
   -- uHeAtlasPath/uHeBacksPath by hand, or just save the stack once. LiveCode reports
   -- filenames with "/" separators on every platform, so item 1 to -2 is the folder.
   -- gotcha 5: the itemDelimiter is global mutable state, so it is saved and
   -- restored here. Leaving it as "/" (pre-v0.14.1) leaked a foreign delimiter out
   -- to every caller -- heKitTryInit's early exit on a missing atlas returned with
   -- it still set, and the next handler to chunk items without setting it first
   -- would have parsed with "/".
   local tFile, tSaved, tOut
   put the filename of this stack into tFile
   if tFile is empty then
      return ""
   end if
   put the itemDelimiter into tSaved
   set the itemDelimiter to "/"
   put item 1 to -2 of tFile into tOut
   set the itemDelimiter to tSaved
   return tOut
end heStackFolder

function heSwapExt pPath, pNewExt
   -- pPath with its trailing ".<ext>" replaced by pNewExt (e.g. ".xml"), so a .png
   -- atlas path yields its sibling TextureAtlas .xml. Copied to a local before the
   -- chunk (H6). A folder name containing a "." is a rare cosmetic edge, not a crash.
   -- saves/restores the itemDelimiter (gotcha 5) -- it used to leave it as "."
   local tBase, tSaved
   put pPath into tBase
   put the itemDelimiter into tSaved
   set the itemDelimiter to "."
   if the number of items of tBase > 1 then
      delete last item of tBase
   end if
   set the itemDelimiter to tSaved
   return tBase & pNewExt
end heSwapExt

command heKitTryInit
   local tIdx, tKitErr, tBacksErr, tPng, tXml, tBackPng, tBackXml, tDir
   local tSlot, tCtr, tSpr, tFrameW, tBackFrameW
   put "flat" into gUIMode
   put 0 into gAnimBusy
   put empty into gCardSpr
   put empty into gKitSuffix
   put empty into gKitBackSuffix
   put empty into gKitLastErr
   if not heHasKit() then
      exit heKitTryInit
   end if
   -- resolve the atlas PNG path. b2kSheetLoadAtlas takes the PNG (its sibling .xml is
   -- the optional 2nd arg). An explicit uHeAtlasPath/uHeBacksPath override wins (a .xml
   -- override is accepted and swapped to .png); otherwise default to assets/cards/ NEXT
   -- TO the saved stack -- so dropping the assets folder beside the stack just works.
   -- A pasted, unsaved stack has no folder, so it stays on the flat cards.
   put the uHeAtlasPath of this stack into tPng
   put the uHeBacksPath of this stack into tBackPng
   put heStackFolder() into tDir
   if tPng is empty and tDir is not empty then
      put tDir & "/assets/cards/playingCards.png" into tPng
   end if
   if tBackPng is empty and tDir is not empty then
      put tDir & "/assets/cards/playingCardBacks.png" into tBackPng
   end if
   if tPng ends with ".xml" then
      put heSwapExt(tPng, ".png") into tPng
   end if
   if tBackPng ends with ".xml" then
      put heSwapExt(tBackPng, ".png") into tBackPng
   end if
   if tPng is empty or there is not a file (tPng) then
      exit heKitTryInit
   end if
   put heSwapExt(tPng, ".xml") into tXml
   put heSwapExt(tBackPng, ".xml") into tBackXml
   try
      -- put the Kit's handlers on the message path IF it is a separately-loaded stack;
      -- if they are already here (merged in / differently-named host), skip it -- a
      -- start-using of a non-existent stack would throw and drop us back to flat.
      if there is a stack "box2dxt-kit" then
         start using stack "box2dxt-kit"
      end if
      set the itemDelimiter to comma
      -- persist the sheets: cards never change, so a saved stack carries the sliced
      -- art and any teardown reloads it as a no-op (Kit guidance).
      b2kSheetPersist true
      b2kSheetLoadAtlas "heCards", tPng, tXml
      -- Kenney frames are card<Suit><Rank>; some atlas loaders keep the ".png" on the
      -- frame key and some strip it (gotcha 24) -- ask the sheet which it is.
      if b2kSheetHasFrame("heCards", "cardSpadesA.png") then
         put ".png" into gKitSuffix
      else
         put empty into gKitSuffix
      end if
      -- scale the sheet so a Kenney card (140 px wide) displays at the slot width,
      -- then pre-warm every face (a lazy first slice costs ~250 ms mid-hand).
      put item 1 of b2kSheetFrameSize("heCards", "cardSpadesA" & gKitSuffix) into tFrameW
      if tFrameW is not a number or tFrameW is 0 then
         put 140 into tFrameW
      end if
      b2kSheetScale "heCards", kHeCardW / tFrameW
      repeat with tIdx = 1 to 52
         b2kSheetEnsureIcon "heCards", heKenneyFrame(tIdx) & gKitSuffix
      end repeat
      -- pool ONE bodiless sprite over each card slot (pooled at build, never mid-hand);
      -- heUIShowCardIn swaps its frame and shows it. Positioned at the slot centre.
      repeat for each key tSlot in gSlotCenter
         put gSlotCenter[tSlot] into tCtr
         b2kSpriteNew "heCards", heKenneyFrame(1) & gKitSuffix, item 1 of tCtr, item 2 of tCtr
         put the result into tSpr
         b2kSpriteMoveTo tSpr, item 1 of tCtr, item 2 of tCtr
         set the visible of tSpr to false
         put tSpr into gCardSpr[tSlot]
      end repeat
      -- the backs sheet (face-down cards): load + size + pre-warm the chosen back.
      -- Guarded so a missing/failed backs sheet never costs us the loaded faces.
      -- Suffix and frame width are probed PER SHEET (gotcha 24: frame-name
      -- conventions vary per sheet -- a custom uHeBacksPath atlas may keep or
      -- strip ".png" and carry a different card width than the faces sheet).
      try
         if tBackPng is not empty and there is a file (tBackPng) then
            b2kSheetLoadAtlas "heCardBacks", tBackPng, tBackXml
            if b2kSheetHasFrame("heCardBacks", kHeCardBackFrame & ".png") then
               put ".png" into gKitBackSuffix
            else
               put empty into gKitBackSuffix
            end if
            put item 1 of b2kSheetFrameSize("heCardBacks", kHeCardBackFrame & gKitBackSuffix) \
                  into tBackFrameW
            if tBackFrameW is not a number or tBackFrameW is 0 then
               put tFrameW into tBackFrameW
            end if
            b2kSheetScale "heCardBacks", kHeCardW / tBackFrameW
            b2kSheetEnsureIcon "heCardBacks", kHeCardBackFrame & gKitBackSuffix
         end if
      catch tBacksErr
      end try
      put "kit" into gUIMode
   catch tKitErr
      -- keep the reason: heProbeKit's whole job is naming the exact gap, and a
      -- silent drop to flat left it able to say only "kit mode is OFF"
      put tKitErr into gKitLastErr
      put "flat" into gUIMode
   end try
end heKitTryInit

command heProbeKit
   -- diagnostic (run in the message box): is kit-mode card art wired up? Does LIVE
   -- checks (not the cached heHasKit -- you may have just added the Kit), so it always
   -- reflects the current state. Names the exact gap and what to do about it.
   local tOut, tDir, tPng, tErr, tHasStack, tHandlers
   put "holde-em kit probe  stack v" & kHeVersion & return & return into tOut
   -- 1. is the Kit reachable? Two ways: a loaded stack named "box2dxt-kit" (the normal
   --    install), OR the b2k* handlers already on the message path.
   put (there is a stack "box2dxt-kit") into tHasStack
   put "false" into tHandlers
   -- b2kSheetFrames on an unknown sheet returns 0 (no throw) IF the Kit handlers are
   -- on the message path; if the Kit is absent the call throws "can't find handler".
   try
      get b2kSheetFrames("__he_probe__")
      put "true" into tHandlers
   catch tErr
   end try
   put "stack " & quote & "box2dxt-kit" & quote & " loaded: " & tHasStack & return after tOut
   put "b2k* handlers on the message path: " & tHandlers & return after tOut
   if tHasStack is false and tHandlers is false then
      put return & "==> The Box2Dxt Kit is NOT loaded. It is a SEPARATE stack named" & return after tOut
      put "    " & quote & "box2dxt-kit" & quote & " -- open its box2dxt-kit.livecodescript in OXT (File > Open" & return after tOut
      put "    Stack), do not paste it into this script. Then run heKitReload." & return after tOut
      put tOut
      return tOut
   end if
   -- 2. the atlas
   put the uHeAtlasPath of this stack into tPng
   if tPng is empty then
      put heStackFolder() into tDir
      if tDir is empty then
         put "atlas path: this stack is UNSAVED (no folder) and uHeAtlasPath is unset --" & return after tOut
         put "  save the stack to a file with assets/cards next to it, or set uHeAtlasPath." & return after tOut
      else
         put tDir & "/assets/cards/playingCards.png" into tPng
      end if
   end if
   if tPng is not empty then
      if tPng ends with ".xml" then
         put heSwapExt(tPng, ".png") into tPng
      end if
      put "atlas PNG: " & tPng & return after tOut
      put "  file exists: " & (there is a file (tPng)) & return after tOut
   end if
   -- 3. what the last heKitTryInit achieved
   put "current UI mode: " & gUIMode & "   frame suffix: '" & gKitSuffix & "'" & return after tOut
   put "card sprites pooled: " & the number of lines of the keys of gCardSpr & return after tOut
   try
      put "heCards frames loaded: " & b2kSheetFrames("heCards") after tOut
      put "   heCardBacks: " & b2kSheetFrames("heCardBacks") & return after tOut
   catch tErr
      put "sheets: not loaded yet" & return after tOut
   end try
   if gUIMode is not "kit" then
      -- the recorded reason the last init dropped to flat (self-diagnosing:
      -- without it this probe could only say OFF, never why)
      if gKitLastErr is not empty then
         put "last kit-init error: " & gKitLastErr & return after tOut
      end if
      put return & "==> kit mode is OFF. If the checks above look right, run heKitReload" & return after tOut
      put "    to (re)build the card sprites, then run heProbeKit again." & return after tOut
   else
      put return & "==> kit mode is ON. If cards still look flat, it is a sprite anchor/" & return after tOut
      put "    scale/z-order detail -- send me this probe output and a screenshot." & return after tOut
   end if
   put tOut
   return tOut
end heProbeKit

command heKitReload
   -- force a fresh Kit probe + card-sprite rebuild -- run this in the message box after
   -- loading the Box2Dxt Kit, saving the stack, or moving the assets. Clears the cached
   -- extension probe, removes any pooled sprites, then re-runs heKitTryInit and reports.
   local tSlot, tSpr, tRmErr
   put empty into gHasKitChk
   if gCardSpr is an array then
      repeat for each key tSlot in gCardSpr
         put gCardSpr[tSlot] into tSpr
         try
            b2kSpriteRemove tSpr
         catch tRmErr
         end try
      end repeat
   end if
   put empty into gCardSpr
   heKitTryInit
   heUIClearCards
   put "kit reload done -- UI mode is now: " & gUIMode & \
         "   (run heProbeKit for details)"
end heKitReload

on mouseUp
   local tWho, tSeatNum, tAmt, tCodeTxt
   put the short name of the target into tWho
   -- lobby routing first: these act whether or not the overlay is up
   switch tWho
      case "heBtnOnline"
         heLobbyShow
         exit mouseUp
      case "heBtnCreate"
         heTableCreate
         exit mouseUp
      case "heBtnJoin"
         put word 1 of the text of field "heJoinCode" into tCodeTxt
         heTableJoin tCodeTxt
         exit mouseUp
      case "heBtnTransport"
         heTransportCycle
         exit mouseUp
      case "heBtnHostMode"
         heHostModeCycle
         exit mouseUp
      case "heBtnCopyCode"
         -- the invite is only real once a table is HOSTED/JOINED: heTableNew
         -- also fills tableIdHex (the Level 0 deal domain) for every hotseat
         -- table when SodiumXT is present, so testing it for empty handed out
         -- a dead code nobody announces -- a joiner would wait forever.
         -- 2f: heInviteTxt appends the onion address for an onion table, so
         -- the copied string is the WHOLE invite either way.
         if gGame["online"] is not "true" or gGame["tableIdHex"] is empty then
            heUISetStatus "No online table yet -- Create one first."
         else
            set the clipboardData["text"] to heInviteTxt()
            heUISetStatus "Invite copied to the clipboard."
         end if
         exit mouseUp
      case "heBtnStartGame"
         heNetStartGame
         exit mouseUp
      case "heBtnLeave"
         heNetStop
         -- returning to hotseat: if the transcript was clobbered by an online
         -- create/join (it now leads with a signed WIRE, or was emptied), start a
         -- fresh hotseat table so gGame["log"] carries a real hotseat cfg (with
         -- stakes AND stacks) for the History fold. A clean in-progress hotseat
         -- game (log begins with a 4-field hotseat "cfg") is preserved -- so a
         -- peek at the lobby and back does not wipe a running game. (deep-dive:
         -- the lobby wire log and the hotseat transcript share gGame["log"].)
         if not heLogIsCleanHotseat(gGame["log"]) then
            heTableNew
         end if
         heLobbyHide
         heUISetStatus "Back to hotseat. Press Deal to play, or Lobby to go online."
         exit mouseUp
      case "heBtnHistory"
         heHistShow
         exit mouseUp
      case "heBtnHistVerify"
         heHistRefresh
         exit mouseUp
      case "heBtnHistExport"
         set the clipboardData["text"] to gGame["log"]
         heUISetStatus "Signed transcript copied -- the portable, replayable proof of every hand."
         exit mouseUp
      case "heBtnHistClose"
         heHistHide
         exit mouseUp
      case "heBtnReportClose"
         heReportHide
         exit mouseUp
      case "heBtnSettings"
         heSettingsShow
         exit mouseUp
      case "heBtnSetLevel"
         heSettingsCycle "level"
         exit mouseUp
      case "heBtnSetSpeed"
         heSettingsCycle "speed"
         exit mouseUp
      case "heBtnSetApply"
         heSettingsApply
         exit mouseUp
      case "heBtnSetCancel"
         heSettingsHide
         exit mouseUp
      case "heBtnSetLogo"
         heTableLogoPick
         exit mouseUp
      case "heBtnSetSounds"
         heSettingsCycle "sounds"
         exit mouseUp
      case "heBtnSitOut"
         -- 2e sit-out/return: our seat's own signed liveness wires (spec 9).
         -- "stand" sits us out (dealt out next hand; mid-hand our turns
         -- auto-fold instantly); "sit" (seat only, no pub) re-enters at the
         -- next hand boundary.
         if gGame["online"] is not "true" or heNetMySeat() is 0 then
            heUISetStatus "Sit out is an online, seated action."
            exit mouseUp
         end if
         if gGame["sitOutBy"][heNetMySeat()] is "true" then
            heNetSendAction "sit", "seat=" & heNetMySeat()
            heUISetStatus "Returning -- you are dealt in from the next hand."
         else
            heNetSendAction "stand", "seat=" & heNetMySeat()
            heUISetStatus "Sitting out -- you are dealt out from the next hand (mid-hand turns auto-fold)."
         end if
         exit mouseUp
   end switch
   -- while an overlay is up, the table/action buttons are inert
   if heLobbyVisible() or heHistVisible() or heSettingsVisible() then
      exit mouseUp
   end if
   -- clicking a seat portrait (disc, initial, or picked image) re-picks that avatar;
   -- allowed any time (not just on your turn), so route it before the phase gate
   if tWho begins with "heSeatAv" then
      put the last char of tWho into tSeatNum
      heSeatAvatarPick tSeatNum
      exit mouseUp
   end if
   if tWho is "heBtnDeal" then
      heHandStart
      exit mouseUp
   end if
   if gGame["phase"] is not "hand" then
      exit mouseUp
   end if
   put gGame["state"]["toAct"] into tSeatNum
   if tSeatNum is 0 then
      exit mouseUp
   end if
   -- quick-bet buttons only fill the amount box; the player still commits
   switch tWho
      case "heBtnMin"
         set the text of field "heAmount" to heQuickAmount(tSeatNum, "min")
         heBetSliderSync
         exit mouseUp
      case "heBtnHalf"
         set the text of field "heAmount" to heQuickAmount(tSeatNum, "half")
         heBetSliderSync
         exit mouseUp
      case "heBtnPot"
         set the text of field "heAmount" to heQuickAmount(tSeatNum, "pot")
         heBetSliderSync
         exit mouseUp
   end switch
   put word 1 of the text of field "heAmount" into tAmt
   if tAmt is not a number then
      put 0 into tAmt
   end if
   -- chips are integers: a typed "2.5" is a number, and a fractional wager
   -- would flow through heBetApply into heSettleOf's div/mod chip accounting,
   -- where a fractional remainder hands a whole chip to every winner and MINTS
   -- chips (conservation break that then audits clean, because the fold
   -- re-derives the same wrong payout). The engine now also rejects
   -- non-integers (act-bad-amount) as the Phase 2 wire backstop; this trunc
   -- keeps the local UX forgiving instead of surfacing a rejection.
   put trunc(tAmt) into tAmt
   -- ONLINE: an action is a signed wire, not a local engine call -- our own
   -- relayed wire folding back is what moves the state (spec 4: the game is a
   -- fold over the transcript). Only the seat to act may emit; the engine
   -- would reject anyone else's wire anyway.
   if gGame["online"] is "true" then
      if tSeatNum is not heNetMySeat() then
         exit mouseUp
      end if
      switch tWho
         case "heBtnFold"
            heNetSendAction "act", "verb=fold,amount=0"
            break
         case "heBtnCheck"
            heNetSendAction "act", "verb=check,amount=0"
            break
         case "heBtnCall"
            heNetSendAction "act", "verb=call,amount=" & heCallAmountFor(tSeatNum)
            break
         case "heBtnBet"
            heNetSendAction "act", "verb=bet,amount=" & tAmt
            break
         case "heBtnRaise"
            heNetSendAction "act", "verb=raise,amount=" & tAmt
            break
         case "heBtnAllin"
            heNetSendAction "act", "verb=allin,amount=" & \
                  (gGame["state"]["streetBy"][tSeatNum] + gGame["state"]["stackBy"][tSeatNum])
            break
      end switch
      exit mouseUp
   end if
   switch tWho
      case "heBtnFold"
         heActionDo tSeatNum, "fold", 0
         break
      case "heBtnCheck"
         heActionDo tSeatNum, "check", 0
         break
      case "heBtnCall"
         heActionDo tSeatNum, "call", heCallAmountFor(tSeatNum)
         break
      case "heBtnBet"
         heActionDo tSeatNum, "bet", tAmt
         break
      case "heBtnRaise"
         heActionDo tSeatNum, "raise", tAmt
         break
      case "heBtnAllin"
         heActionDo tSeatNum, "allin", \
               gGame["state"]["streetBy"][tSeatNum] + gGame["state"]["stackBy"][tSeatNum]
         break
   end switch
end mouseUp

function heCallAmountFor pSeatNum
   local tOwe
   put gGame["state"]["betCur"] - gGame["state"]["streetBy"][pSeatNum] into tOwe
   return min(tOwe, gGame["state"]["stackBy"][pSeatNum])
end heCallAmountFor

function heQuickAmount pSeatNum, pKind
   -- thin shell wrapper: the sizing itself is pure (heQuickAmountOf) so it is
   -- KAT-pinned in tools/betting-kat.py and the harness, not just eyeballed
   return heQuickAmountOf(gGame["state"], pSeatNum, pKind)
end heQuickAmount

function heQuickAmountOf pStateA, pSeatNum, pKind
   -- a convenience "raise to" amount, clamped to [minTo, maxTo]. PURE (H5):
   -- values in, value out, no UI reads -- pinned by tools/betting-kat.py.
   --
   -- The pot-limit definition (spec 8.1 sizing, the standard one): the maximum
   -- raise is "the pot AFTER you call" -- the money already committed plus the
   -- amount you must first put in to call -- and that is the raise INCREMENT,
   -- laid on top of the current bet. So
   --     raiseTo = betCur + potAfterCall,   potAfterCall = committed + owe
   -- and the chips the seat actually pushes are owe + potAfterCall.
   -- v0.14.1 fix: this used to read betCur + owe + potAfterCall, which counts
   -- the call TWICE (betCur already equals streetBy + owe). Facing a 2 into a
   -- pot of 3 it offered a raise to 9 where a pot-sized raise is 7 -- the Pot
   -- and 1/2 Pot buttons over-sized every raise made while facing a bet. With
   -- owe = 0 (opening a street) the extra term vanished, which is why the
   -- opening-bet case always looked right.
   local tOwe, tPotAfter, tMaxTo, tMinTo, tTo, tSeat
   set the itemDelimiter to comma
   put pStateA["betCur"] - pStateA["streetBy"][pSeatNum] into tOwe
   put 0 into tPotAfter
   repeat for each item tSeat in pStateA["occ"]
      add pStateA["handBy"][tSeat] to tPotAfter
   end repeat
   add tOwe to tPotAfter
   put pStateA["streetBy"][pSeatNum] + pStateA["stackBy"][pSeatNum] into tMaxTo
   put min(pStateA["betCur"] + pStateA["raiseFull"], tMaxTo) into tMinTo
   switch pKind
      case "half"
         put pStateA["betCur"] + (tPotAfter div 2) into tTo
         break
      case "pot"
         put pStateA["betCur"] + tPotAfter into tTo
         break
      default
         put tMinTo into tTo
   end switch
   if tTo < tMinTo then
      put tMinTo into tTo
   end if
   if tTo > tMaxTo then
      put tMaxTo into tTo
   end if
   return tTo
end heQuickAmountOf

command heUISetStatus pTxt
   -- keep the last status text in the store as well as on the felt (v0.24.0).
   -- The field is the display; the copy is what lets a headless harness pin
   -- WHICH message won when two writers race for this one line -- the F8
   -- defect was exactly such a race (the redial's fail-closed message
   -- overwriting the election's "Elected host: ..." two lines later), and it
   -- was unpinnable while the only record of it lived in a field.
   put pTxt into gGame["statusTxt"]
   if there is a field "heStatus" then
      set the text of field "heStatus" to pTxt
   end if
end heUISetStatus

command heUIPromptToAct
   local tSeatNum, tLegalTxt, tLine, tHasCheck, tHasCall, tHasBet, tHasRaise
   local tHasAllin, tCallAmt, tName, tMinTo, tMaxTo
   set the itemDelimiter to comma
   if gGame["phase"] is not "hand" then
      exit heUIPromptToAct
   end if
   put gGame["state"]["toAct"] into tSeatNum
   if tSeatNum is 0 then
      exit heUIPromptToAct
   end if
   -- online, the prompt is only ever OURS: another seat's turn shows as
   -- waiting (heNetGameReact disables the buttons and says who is up)
   if gGame["online"] is "true" and tSeatNum is not heNetMySeat() then
      heDisableActions
      exit heUIPromptToAct
   end if
   put heBetLegal(gGame["state"], tSeatNum) into tLegalTxt
   put false into tHasCheck
   put false into tHasCall
   put false into tHasBet
   put false into tHasRaise
   put false into tHasAllin
   put heCallAmountFor(tSeatNum) into tCallAmt
   repeat for each line tLine in tLegalTxt
      switch word 1 of tLine
         case "check"
            put true into tHasCheck
            break
         case "call"
            put true into tHasCall
            break
         case "bet"
            put true into tHasBet
            break
         case "raise"
            put true into tHasRaise
            break
         case "allin"
            put true into tHasAllin
            break
      end switch
   end repeat
   heEnableBtn "heBtnCheck", tHasCheck
   heEnableBtn "heBtnCall", tHasCall
   heEnableBtn "heBtnBet", tHasBet
   heEnableBtn "heBtnRaise", tHasRaise
   heEnableBtn "heBtnAllin", tHasAllin
   heEnableBtn "heBtnFold", true
   if there is a button "heBtnCall" then
      if tHasCall then
         set the label of button "heBtnCall" to "Call " & tCallAmt
      else
         set the label of button "heBtnCall" to "Call"
      end if
   end if
   -- seed the amount box with the minimum legal bet/raise-to, and arm the slider
   -- between that minimum and all-in (streetBy + stackBy). No bet/raise -> hide it.
   if (tHasBet or tHasRaise) and there is a field "heAmount" then
      put heQuickAmount(tSeatNum, "min") into tMinTo
      put gGame["state"]["streetBy"][tSeatNum] + gGame["state"]["stackBy"][tSeatNum] \
            into tMaxTo
      set the text of field "heAmount" to tMinTo
      heBetSliderShow tMinTo, tMaxTo
   else
      heBetSliderHide
   end if
   put item tSeatNum of kHeSeatNames into tName
   heUISetStatus tName & " to act  --  " & toUpper(gGame["state"]["street"]) \
         & ".  Pot " & heCurrentPot() & ".  To call: " & tCallAmt
end heUIPromptToAct

command heEnableBtn pBtnName, pOn
   if there is not a button pBtnName then
      exit heEnableBtn
   end if
   set the disabled of button pBtnName to not pOn
end heEnableBtn

command heDisableActions
   local tBtn
   set the itemDelimiter to comma
   repeat for each item tBtn in "heBtnFold,heBtnCheck,heBtnCall,heBtnBet,heBtnRaise,heBtnAllin,heBtnMin,heBtnHalf,heBtnPot"
      heEnableBtn tBtn, false
   end repeat
   if there is a button "heBtnCall" then
      set the label of button "heBtnCall" to "Call"
   end if
   heBetSliderHide
end heDisableActions

function heHandLive
   -- true while a dealt hand still owns gGame["state"]: the acting phase AND the
   -- paced beats that follow it (the board reveal, an all-in runout, the showdown
   -- hold). Everything the HUD reads out of the hand -- pot, chips behind, street
   -- bets, blind badges, FOLDED/ALL-IN -- is valid for ALL of these, and gating it
   -- on "hand" alone (pre-v0.14.1) blanked the table exactly when the hand was at
   -- its most dramatic: the pot read 0, every seat showed its pre-hand bankroll,
   -- and the folded/all-in markers vanished for the whole runout and showdown.
   -- "between" is NOT live: heHandSettle has already paid the deltas into
   -- gGame["stacksBy"], so the hand's handBy would double-count.
   switch gGame["phase"]
      case "hand"
      case "reveal"
      case "runout"
      case "showdown"
         return true
   end switch
   return false
end heHandLive

function heCurrentPot
   local tSeatNum, tPot
   set the itemDelimiter to comma
   put 0 into tPot
   if heHandLive() then
      repeat for each item tSeatNum in gGame["state"]["occ"]
         add gGame["state"]["handBy"][tSeatNum] to tPot
      end repeat
   end if
   return tPot
end heCurrentPot

command heHudMark
   put true into gHudDirty
end heHudMark

on heHudTick
   -- pin the stack: a `send ... in` tick has no defaultStack guarantee, and every
   -- control this reaches is named unqualified (OXT-ENGINE-NOTES 5.3)
   set the defaultStack to the short name of this stack
   if gHudTickOn is not true then
      exit heHudTick
   end if
   if gHudDirty is true then
      put false into gHudDirty
      heHudRefresh
   end if
   send "heHudTick" to me in kHeHudMs milliseconds
end heHudTick

command heHudRefresh
   local tSeatNum, tPotAmt, tSpotTxt, tSpotX, tSpotY, tHandBy, tInHand, tStreetBy
   local tActing, tSbSeat, tBbSeat, tBadge
   if there is not a field "hePot" then
      exit heHudRefresh
   end if
   set the itemDelimiter to comma
   put heCurrentPot() into tPotAmt
   set the text of field "hePot" to "POT  " & tPotAmt
   set the visible of graphic "hePotChip" to (tPotAmt > 0)
   set the text of field "heHeader" to heHeaderTxt()
   -- Deal is offered only from a settled table; during reveal/runout/showdown
   -- beats it stays inert so a click cannot cut a paced sequence short -- and
   -- never while online (the hotseat engine would corrupt the signed wire log;
   -- heHandStart carries the same gate as the backstop)
   heEnableBtn "heBtnDeal", ((gGame["phase"] is "idle" or gGame["phase"] is "between") \
         and gGame["online"] is not "true")
   -- 2e sit-out: our own seat's toggle -- live only online with a seat; its
   -- face follows our sit-out state (Sit out <-> Return)
   heEnableBtn "heBtnSitOut", (gGame["online"] is "true" and heNetMySeat() > 0)
   if there is a button "heBtnSitOut" then
      if gGame["online"] is "true" and gGame["sitOutBy"][heNetMySeat()] is "true" then
         set the label of button "heBtnSitOut" to "Return"
      else
         set the label of button "heBtnSitOut" to "Sit out"
      end if
   end if
   if gGame["phase"] is not "hand" then
      heDisableActions
   end if

   put 0 into tActing
   put 0 into tSbSeat
   put 0 into tBbSeat
   if heHandLive() then
      -- toAct is already 0 in the reveal/runout/showdown beats, so no seat glows
      -- during them; the blind badges stay up for the whole hand, as they should
      put gGame["state"]["toAct"] into tActing
      put gGame["state"]["sbSeat"] into tSbSeat
      put gGame["state"]["bbSeat"] into tBbSeat
   end if

   repeat with tSeatNum = 1 to kHeDefaultSeats
      -- tables smaller than the 6-spot layout hide their unused seats entirely
      if tSeatNum > gGame["numSeats"] then
         heSeatChromeVisible tSeatNum, false
         next repeat
      end if
      heSeatChromeVisible tSeatNum, true
      put heHandByOf(tSeatNum) into tHandBy
      -- chip TOTAL behind (always visible, even between hands)
      if gGame["stacksBy"][tSeatNum] is a number then
         set the text of field ("heSeatStack" & tSeatNum) to \
               (gGame["stacksBy"][tSeatNum] - tHandBy)
      end if
      -- bet in front this street
      put 0 into tStreetBy
      if heHandLive() and gGame["state"]["streetBy"][tSeatNum] is a number then
         put gGame["state"]["streetBy"][tSeatNum] into tStreetBy
      end if
      if tStreetBy > 0 then
         set the text of field ("heSeatBet" & tSeatNum) to tStreetBy
         set the visible of graphic ("heSeatChip" & tSeatNum) to true
      else
         set the text of field ("heSeatBet" & tSeatNum) to ""
         set the visible of graphic ("heSeatChip" & tSeatNum) to false
      end if
      -- role badge (D / SB / BB), acting highlight, folded / all-in state
      put "" into tBadge
      if tSeatNum is tSbSeat then
         put "SB" into tBadge
      end if
      if tSeatNum is tBbSeat then
         put "BB" into tBadge
      end if
      set the text of field ("heSeatBadge" & tSeatNum) to tBadge
      heSeatFace tSeatNum, (tSeatNum is tActing)
   end repeat

   -- dealer button disc
   if gGame["buttonSeat"] > 0 then
      set the itemDelimiter to ";"
      put item gGame["buttonSeat"] of kHeSeatSpots into tSpotTxt
      set the itemDelimiter to comma
      put item 1 of tSpotTxt into tSpotX
      put item 2 of tSpotTxt into tSpotY
      set the loc of field "heDealerDisc" to (tSpotX - 92) & comma & (tSpotY + 24)
      set the visible of field "heDealerDisc" to true
   else
      set the visible of field "heDealerDisc" to false
   end if
end heHudRefresh

command heSeatChromeVisible pSeatNum, pOn
   -- show or hide a whole seat's persistent chrome, so a table configured for
   -- fewer than the 6 layout spots does not display ghost seats
   local tCtl
   set the itemDelimiter to comma
   if there is a graphic ("hePanel" & pSeatNum) then
      set the visible of graphic ("hePanel" & pSeatNum) to pOn
   end if
   repeat for each item tCtl in "heSeatName,heSeatStack,heSeatBadge,heSeatState,heSeatBet"
      if there is a field (tCtl & pSeatNum) then
         set the visible of field (tCtl & pSeatNum) to pOn
      end if
   end repeat
   -- seat portrait: the disc always follows the seat; the image vs initial follows the
   -- cached gAvatarOn (set by heSeatAvatarRender) so this hot path never reloads a file
   if there is a graphic ("heSeatAv" & pSeatNum) then
      set the visible of graphic ("heSeatAv" & pSeatNum) to pOn
   end if
   if there is a field ("heSeatAvTx" & pSeatNum) then
      set the visible of field ("heSeatAvTx" & pSeatNum) to (pOn and gAvatarOn[pSeatNum] is not "true")
   end if
   if there is an image ("heSeatAvImg" & pSeatNum) then
      set the visible of image ("heSeatAvImg" & pSeatNum) to (pOn and gAvatarOn[pSeatNum] is "true")
   end if
   if not pOn then
      -- unseated: also drop the bet chip and any hole cards
      if there is a graphic ("heSeatChip" & pSeatNum) then
         set the visible of graphic ("heSeatChip" & pSeatNum) to false
      end if
      if there is a field ("heHole" & pSeatNum & "a") then
         set the visible of field ("heHole" & pSeatNum & "a") to false
         set the visible of field ("heHole" & pSeatNum & "b") to false
      end if
   end if
end heSeatChromeVisible

command heSeatFace pSeatNum, pActing
   -- panel colour + state label: acting (gold), folded (dim), all-in (gold text)
   local tState, tFolded, tAllin, tCurTxt, tLabelTxt
   put "false" into tFolded
   put "false" into tAllin
   if heHandLive() then
      put gGame["state"] into tState
      put tState["foldedBy"][pSeatNum] into tFolded
      put tState["allinBy"][pSeatNum] into tAllin
   end if
   if pActing then
      set the backgroundColor of graphic ("hePanel" & pSeatNum) to kHePanelActive
      set the foregroundColor of graphic ("hePanel" & pSeatNum) to kHeGlowColor
   else
      set the backgroundColor of graphic ("hePanel" & pSeatNum) to kHePanelColor
      set the foregroundColor of graphic ("hePanel" & pSeatNum) to kHePanelColor
   end if
   if there is not a field ("heSeatState" & pSeatNum) then
      exit heSeatFace
   end if
   -- a showdown WINNER badge outranks the folded/all-in state and must survive the
   -- repaints that follow: heUIShowdownReveal writes it, then the very next 4 Hz
   -- HUD tick used to wipe it (pre-v0.14.1 this handler cleared the state field
   -- outside phase "hand"), so the winner flashed for at most one tick. It stays
   -- up through the showdown hold and the between-hands result pause, and
   -- heUIClearCards clears it when the next hand is dealt.
   put the text of field ("heSeatState" & pSeatNum) into tCurTxt
   if tCurTxt is "WINNER" and (gGame["phase"] is "showdown" or gGame["phase"] is "between") then
      exit heSeatFace
   end if
   -- the label decision is pure (heSeatFaceLabel); this half only paints it.
   -- The two dim labels are the seat's "not playing" states; everything the
   -- plate says about a LIVE seat is gold (an empty label paints no text, so
   -- its colour never shows).
   put heSeatFaceLabel(pSeatNum, pActing, tFolded, tAllin) into tLabelTxt
   set the text of field ("heSeatState" & pSeatNum) to tLabelTxt
   if tLabelTxt is "FOLDED" or tLabelTxt is "SIT OUT" then
      set the textColor of field ("heSeatState" & pSeatNum) to "150,150,150"
   else
      set the textColor of field ("heSeatState" & pSeatNum) to kHeGoldColor
   end if
end heSeatFace

function heSeatFaceLabel pSeatNum, pActing, pFoldedTxt, pAllinTxt
   -- WHICH state label a seat plate shows, decided in one place with no UI
   -- read or write (v0.24.0) -- so the priority order is pinnable headlessly
   -- instead of only observable on a felt. The order IS the contract:
   --   FOLDED / ALL-IN   the engine's own verdict on the seat, first
   --   SIT OUT           the seat's STATUS, ahead of the countdown (F9): the
   --                     countdown branch used to win, so a sitting-out seat
   --                     whose turn came up painted "0s" -- and 0 is exactly
   --                     what heNetTurnLimitSecs returns FOR a sitting-out
   --                     seat, so the plate showed the reason for the label
   --                     as a stopwatch instead of the label.
   --   <n>s              the acting seat's remaining seconds (online only)
   --   empty             nothing to say
   if pFoldedTxt is "true" then
      return "FOLDED"
   end if
   if pAllinTxt is "true" then
      return "ALL-IN"
   end if
   if gGame["online"] is "true" and gGame["sitOutBy"][pSeatNum] is "true" then
      return "SIT OUT"
   end if
   if pActing and gGame["online"] is "true" and gGame["turnClockTxt"] is not empty then
      -- 2e act timer: painted only from the 4 Hz HUD tick, and
      -- heNetActTimerTick marks the HUD dirty only when the shown second
      -- CHANGES -- <= 1 Hz in practice.
      return gGame["turnClockTxt"]
   end if
   return empty
end heSeatFaceLabel

function heHeaderTxt
   local tTxt
   put "holde-em " & kHeVersion into tTxt
   if gGame["handNum"] > 0 then
      put "     Hand " & gGame["handNum"] after tTxt
   end if
   if heHandLive() then
      put "     " & toUpper(gGame["state"]["street"]) after tTxt
   end if
   put "     Blinds " & gGame["sb"] & "/" & gGame["bb"] after tTxt
   if gGame["ante"] > 0 then
      put "     Ante " & gGame["ante"] after tTxt
   end if
   if gGame["levelMode"] is not "off" and gGame["curLevel"] > 0 then
      put "     Level " & gGame["curLevel"] after tTxt
   end if
   return tTxt
end heHeaderTxt

function heHandByOf pSeatNum
   -- what this seat has committed to the LIVE hand, so the HUD can show chips
   -- BEHIND (bankroll - committed). Valid for every live phase; at "between" the
   -- deltas are already in gGame["stacksBy"] and this must read 0.
   if heHandLive() and gGame["state"]["handBy"][pSeatNum] is a number then
      return gGame["state"]["handBy"][pSeatNum]
   end if
   return 0
end heHandByOf

command heUIHandStart
   local tSeatNum, tDealA
   heUIClearCards
   put gGame["deal"] into tDealA
   set the itemDelimiter to comma
   repeat for each item tSeatNum in gGame["occ"]
      heUIShowHole tSeatNum, tDealA["holesBy"][tSeatNum]
   end repeat
   heSndPlay "deal"
   heUISetStatus "Hand " & gGame["handNum"] & " dealt -- blinds " & gGame["sb"] & "/" & gGame["bb"] & " posted."
end heUIHandStart

command heUIShowHole pSeatNum, pIdxPair
   local tSlotName, tPair
   set the itemDelimiter to comma
   put pIdxPair into tPair
   put "heHole" & pSeatNum & "a" into tSlotName
   heUIShowCardIn tSlotName, item 1 of tPair
   put "heHole" & pSeatNum & "b" into tSlotName
   heUIShowCardIn tSlotName, item 2 of tPair
end heUIShowHole

command heUIShowCardIn pSlotName, pIdx
   local tSpr, tShowErr
   -- kit mode: swap this slot's pooled sprite to the card's Kenney frame and show it,
   -- hiding the flat field beneath. Guarded so a kit hiccup falls back to the flat
   -- glyph card and never breaks the deal.
   if gUIMode is "kit" and gCardSpr[pSlotName] is not empty then
      try
         put gCardSpr[pSlotName] into tSpr
         b2kSpriteSetFrame tSpr, heKenneyFrame(pIdx) & gKitSuffix
         set the visible of tSpr to true
         if there is a field pSlotName then
            set the visible of field pSlotName to false
         end if
         exit heUIShowCardIn
      catch tShowErr
      end try
   end if
   if there is not a field pSlotName then
      exit heUIShowCardIn
   end if
   set the text of field pSlotName to heCardFace(pIdx)
   if heCardSuitVal(pIdx) is 2 or heCardSuitVal(pIdx) is 3 then
      set the textColor of field pSlotName to kHeRed
   else
      set the textColor of field pSlotName to kHeInk
   end if
   set the backgroundColor of field pSlotName to kHeWhite
   set the visible of field pSlotName to true
end heUIShowCardIn

command heUIShowBoardStreet pStreetName, pIdxList
   local tIdx, tPos
   set the itemDelimiter to comma
   switch pStreetName
      case "flop"
         put 1 into tPos
         break
      case "turn"
         put 4 into tPos
         break
      case "river"
         put 5 into tPos
         break
   end switch
   repeat for each item tIdx in pIdxList
      heUIShowCardIn "heBoard" & tPos, tIdx
      add 1 to tPos
   end repeat
   heSndPlay "board"
end heUIShowBoardStreet

command heUIShowdownReveal pInHandList, pRanksA
   local tSeatNum, tTxt, tName, tBest, tOrder
   set the itemDelimiter to comma
   put heShowdownOrderOf(gGame["state"]) into tOrder
   -- best rank among those who showed -> winner highlight
   put empty into tBest
   repeat for each item tSeatNum in pInHandList
      if tBest is empty or pRanksA[tSeatNum] > tBest then
         put pRanksA[tSeatNum] into tBest
      end if
   end repeat
   put "Showdown -- " into tTxt
   repeat for each item tSeatNum in tOrder
      put item tSeatNum of kHeSeatNames into tName
      put tName & " (" & heHandLabel(pRanksA[tSeatNum]) & ")   " after tTxt
      if pRanksA[tSeatNum] is tBest and there is a field ("heSeatState" & tSeatNum) then
         set the text of field ("heSeatState" & tSeatNum) to "WINNER"
         set the textColor of field ("heSeatState" & tSeatNum) to kHeGoldColor
      end if
   end repeat
   heUISetStatus tTxt
end heUIShowdownReveal

function heHandLabel pPacked
   -- turn a packed rank into a human category name for the status line
   local tCat
   put char 1 to 2 of pPacked into tCat
   switch tCat
      case "08"
         return "straight flush"
      case "07"
         return "four of a kind"
      case "06"
         return "full house"
      case "05"
         return "flush"
      case "04"
         return "straight"
      case "03"
         return "three of a kind"
      case "02"
         return "two pair"
      case "01"
         return "one pair"
      default
         return "high card"
   end switch
end heHandLabel

command heUIClearCards
   local tSeatNum, tPos, tSlot, tSpr
   -- kit mode: hide every pooled card sprite between hands
   if gUIMode is "kit" then
      repeat for each key tSlot in gCardSpr
         put gCardSpr[tSlot] into tSpr
         set the visible of tSpr to false
      end repeat
   end if
   repeat with tSeatNum = 1 to kHeDefaultSeats
      if there is a field ("heHole" & tSeatNum & "a") then
         set the visible of field ("heHole" & tSeatNum & "a") to false
         set the visible of field ("heHole" & tSeatNum & "b") to false
      end if
      if there is a field ("heSeatState" & tSeatNum) then
         set the text of field ("heSeatState" & tSeatNum) to ""
      end if
      if there is a field ("heSeatBet" & tSeatNum) then
         set the text of field ("heSeatBet" & tSeatNum) to ""
         set the visible of graphic ("heSeatChip" & tSeatNum) to false
      end if
      if there is a field ("heSeatBadge" & tSeatNum) then
         set the text of field ("heSeatBadge" & tSeatNum) to ""
      end if
      if there is a graphic ("hePanel" & tSeatNum) then
         set the backgroundColor of graphic ("hePanel" & tSeatNum) to kHePanelColor
         set the foregroundColor of graphic ("hePanel" & tSeatNum) to kHePanelColor
      end if
   end repeat
   repeat with tPos = 1 to 5
      if there is a field ("heBoard" & tPos) then
         set the visible of field ("heBoard" & tPos) to false
      end if
   end repeat
end heUIClearCards

on b2kFrame
   if gAnimBusy > 0 then
      -- reserved: deal-slide / flip chaining bookkeeping (OXT pass)
   end if
end b2kFrame

-- CARD-FLIP CHAINING IS NOT WIRED, and what stood here never wired it. This
-- file used to define `on b2kSpriteOnFinish pSpriteId` as a RECEIVER, holding
-- a per-sprite context lock (gFlipCtxA) for gotcha 19's double-fire guard.
-- b2kSpriteOnFinish is the Kit's SETTER: `b2kSpriteOnFinish pCtrl, pMessage`
-- records which message THIS game wants when a non-looping animation ends,
-- and the Kit then dispatches THAT REGISTERED NAME
-- (`dispatch sSprMsg[tRef] to sFrameObj with tRef, tAnim`) -- never the
-- literal "b2kSpriteOnFinish". So the handler could not fire whatever else
-- was true: it was dead the day it was written, it shadowed the setter for
-- any future caller, and in the suite paste (Kit + this stack as one script
-- layer) the two definitions collide outright.
-- REMOVED 2026-08-16 rather than renamed, because a renamed receiver would
-- still be dead in both directions: nothing here plays a non-looping
-- animation (b2kSpritePlay is called NOWHERE -- the pooled card slots swap
-- faces with b2kSpriteSetFrame), and nothing calls b2kFrameTarget, so the
-- Kit holds no object to dispatch a finish TO. Registering a message now
-- would only move the dead code, so the wiring is written down instead of
-- half-built. All three parts are required together, and the OXT pass owes
-- all three:
--   1. b2kFrameTarget me                          -- once, in heKitTryInit
--   2. b2kSpriteOnFinish tSpr, "heCardFlipDone"   -- per pooled sprite, at
--      pool time (the SETTER, called; not defined)
--   3. on heCardFlipDone pSpriteRef, pAnimName    -- the receiver, gated on
--      its own per-sprite context lock: gotcha 19 is real, a finish message
--      goes to whoever started the animation, and a stale one must not
--      double-fire a flip sequence. gAnimBusy/b2kFrame above is the other
--      half of that bookkeeping.

--------------------------------------------------------------------------
-- self-test harness (folded in -- run heRunSelftest in the message box).
-- Self-diagnosing asserts print what was OBSERVED. kHeHarnessV is in the
-- header; bump it on every engine-behavior change.
--------------------------------------------------------------------------

-- The harness's own script-level declarations -- gRpt/gPassN/gFailN/gSkipN,
-- the netplay loopback contexts, and every kKat* vector -- are HOISTED to
-- the declaration block at the top of this file. See the banner there for
-- why they cannot live here.

function heAwardedPot pHandBy, pOcc
   -- The pot that is actually AWARDED, which is NOT the sum of what everyone
   -- committed. A bet nobody called is RETURNED, so it never entered the pot.
   --
   -- Found 2026-08-17 in a hotseat transcript: a 392 all-in called by a 2008
   -- stack reported "pot 2400" for a pot of 784, inflated by exactly the 1616
   -- that went straight back. The DELTAS were right throughout - chips
   -- conserved, settle-verified passed - which is why every existing gate
   -- stayed green over a wrong number. This is a display defect, not a money
   -- one, and the distinction is worth keeping in the comment.
   --
   -- The rule: a seat's chips enter the pot only up to the largest amount ANY
   -- OTHER seat committed. With h1 the highest commitment and h2 the second
   -- highest COUNTING TIES, a seat below h1 contributes all of it and a seat
   -- AT h1 contributes h2. So a normally called hand - where two or more seats
   -- are level at h1, h2 = h1 - is unchanged, and only a genuine uncalled
   -- excess is excluded. That is why hands 1 and 2 of the transcript agreed
   -- with the old code and only the all-in hand did not.
   --
   -- Extracted rather than left inline so it can be PINNED: the shipped fold
   -- is a forty-line loop no assertion could reach.
   local tHiOne, tHiTwo, tAmt, tSeat, tTotal
   put 0 into tHiOne
   put 0 into tHiTwo
   repeat for each item tSeat in pOcc
      put pHandBy[tSeat] into tAmt
      if tAmt is empty then
         put 0 into tAmt
      end if
      if tAmt > tHiOne then
         put tHiOne into tHiTwo
         put tAmt into tHiOne
      else if tAmt > tHiTwo then
         put tAmt into tHiTwo
      end if
   end repeat
   put 0 into tTotal
   repeat for each item tSeat in pOcc
      put pHandBy[tSeat] into tAmt
      if tAmt is empty then
         put 0 into tAmt
      end if
      if tAmt < tHiOne then
         add tAmt to tTotal
      else
         add tHiTwo to tTotal
      end if
   end repeat
   return tTotal
end heAwardedPot

command heRunSelftest
   -- THE INTERACTIVE entry point: run everything, then deliver the report the
   -- way a maintainer sitting in front of the stack wants it (panel, clipboard,
   -- msg). heSelfTest, just below, is the QUIET one; both drive the SAME
   -- heTestRunAllSections, so the two can never end up testing different
   -- things -- two copies of the section list is exactly how one goes stale.
   heTestRunAllSections
   put return & "==== " & gPassN & " pass, " & gFailN & " fail, " & gSkipN & " skip ====" \
         & return after gRpt
   if gFailN > 0 then
      put "RESULT: FAILED" & return after gRpt
   else
      put "RESULT: green" & return after gRpt
   end if
   -- deliver the report where it can be READ WHOLE: the stack's own scrolling
   -- report panel (heReportShow) -- on OXT a put into the msg container lands
   -- silently in a CLOSED message-box palette, so the report seemed to vanish
   -- while the lobby's net field (the live wire feed) kept updating -- plus a
   -- full copy on the clipboard, made to be pasted back for review. (The msg
   -- CONTAINER token is "msg", not the prose "the message box" -- v0.17.2,
   -- gotcha 13's family -- but even the correct form displays nothing when
   -- the palette is closed, hence the panel.)
   put "(full report is also on the clipboard -- just paste it)" & return after gRpt
   set the clipboardData["text"] to gRpt
   put gRpt into msg
   heReportShow gRpt
   return gRpt
end heRunSelftest

function heSelfTest
   -- THE QUIET entry point: runs exactly what heRunSelftest runs and RETURNS
   -- the report as a value. It builds no control and touches no clipboard,
   -- which is what a harness folded into another paste has to be.
   --
   -- ONE HONEST EXCEPTION, corrected here at the 2026-08-16 suite fold rather
   -- than left as a claim that reads better than it is: this used to say "and
   -- no msg", and the LAST entry in heTestRunAllSections is heProbeSodium
   -- (section 21 when that was written; the 22nd entry since v0.24.4 put the
   -- pure-helpers section ahead of it, the 23rd since v0.25.0 added the
   -- leaf-tranche section too), whose last lines are
   -- `put return & tRpt after gRpt` and then a BARE `put tRpt` -- and a bare
   -- put writes to msg. That echo is deliberate and documented at its own site
   -- (running heProbeSodium standalone from the message box should print), and
   -- it is harmless in a host paste (the suite core never reads msg; nothing
   -- it owns is overwritten). The clipboard is the one that would have cost
   -- something, because the suite scaffold's Copy-results button lives there,
   -- and that one really is untouched. The line
   -- format is riptide's rsSelfTest, deliberately copied rather than invented.
   --
   -- Why heRunSelftest cannot be that entry point -- every reason below is a
   -- defect the moment it is forgotten, so they are written down rather than
   -- summarised as "it is interactive":
   --   * it BUILDS an 800x560 report overlay on the card (heReportShow). A
   --     suite paste has no holde-em card, and a stack that grew one would be
   --     a stack the harness silently redecorated.
   --   * it OVERWRITES clipboardData["text"], which is the suite scaffold's
   --     OWN Copy-results channel: the person who ran the suite harness and
   --     pressed Copy would paste holde-em's report instead of the suite's,
   --     and nothing would say so.
   --   * it writes to msg.
   --   * its summary reads "==== n pass, m fail, k skip ====", which the
   --     core's stSummaryCounts refuses ON PURPOSE -- the words are
   --     "pass"/"fail" rather than "passed"/"failed" and "====" is not a
   --     number -- so a fold that reused it would report this member as
   --     unreadable while its report was perfect. That exact failure cost the
   --     2026-08-09 engine pass two members; it is not a hypothetical.
   --
   -- THE FIRST LINE IS THE CONTRACT: exactly two numbers plus "passed" and
   -- "failed", in that order, and nothing else. One extra word and
   -- stSummaryCounts reads the line as prose and refuses it (which is the
   -- behaviour that makes the parse safe, not a bug to work around). So the
   -- skip count gets its own line, and the run's banner stays below the
   -- divider where it can never be mistaken for a summary.
   --
   -- Verified statically; needs an OXT pass.
   heTestRunAllSections
   -- leave no timer of ours running inside somebody else's paste
   heTestSweepNetTimers
   return gPassN && "passed," && gFailN && "failed" & return & \
         gSkipN && "skipped (absent optional extensions and engine-only paths -- see the log)" \
         & return & "----------------------------------------" & return & gRpt
end heSelfTest

command heTestRunAllSections
   -- The RUN, with no delivery attached: reset the counters, print the banner,
   -- drive every section under its guard. Factored out of heRunSelftest so the
   -- interactive report and the folded one execute one list, not two.
   put empty into gRpt
   put 0 into gPassN
   put 0 into gFailN
   put 0 into gSkipN
   put "holde-em self-test  stack v" & kHeVersion & "  harness v" & kHeHarnessV \
         & return & return after gRpt
   -- each section runs inside a guard so a first-contact runtime fault in one
   -- is reported (with its error) and the rest still run -- the harness never
   -- dies with an opaque "error in function handler", it tells you where
   heRunSection "heTestEvaluatorRun"
   heRunSection "heTestBettingRun"
   heRunSection "heTestAnteRun"
   heRunSection "heTestLevelRun"
   heRunSection "heTestLegalRun"
   heRunSection "heTestScheduleRun"
   heRunSection "heTestShuffleRun"
   heRunSection "heTestFoldRun"
   heRunSection "heTestCryptoRun"
   heRunSection "heTestReceiptRun"
   heRunSection "heTestDealRun"
   heRunSection "heTestDealOrderRun"
   heRunSection "heTestLobbyRun"
   heRunSection "heTestNetSim"
   heRunSection "heTestNetPlay"
   heRunSection "heTestLevel2Run"
   heRunSection "heTestOnionRun"
   heRunSection "heTestOracleRun"
   heRunSection "heTestLevel2VoidRun"
   heRunSection "heTestLivenessRun"
   heRunSection "heTestHelpersRun"
   heRunSection "heTestLeafRun"
   heRunSection "heTestLeafRun2"
   heRunSection "heProbeSodium"
end heTestRunAllSections

command heTestSweepNetTimers
   -- Cancel the network timers the harness itself armed. Several sections drive
   -- heNetHandKick (seven times) and heNetStartGame on SYNTHETIC online
   -- contexts, and those paths legitimately arm a send -- the between-hands
   -- beat is "send heNetNextHandTick ... in <pace> milliseconds". Standalone
   -- that is merely untidy: the tick finds gGame restored and exits on its own
   -- guard. Inside a suite paste it is not untidy at all -- it fires into
   -- somebody else's async phase, seconds after this member has already
   -- reported, from a handler no other member has heard of.
   --
   -- Swept BY PREFIX rather than by the names armed today, because a heNet*
   -- send added to a section later would otherwise ride back out of the
   -- harness silently, which is the whole class of bug this exists for. NOT
   -- the blanket "he" prefix closeStack uses: heHudTick and the paced hand
   -- steps belong to a REAL table, and stopping a maintainer's HUD because
   -- they ran the harness would be a new bug. (Running this against a LIVE
   -- online table is unsupported either way -- the sections swap gGame out
   -- from under it and restore it on the way past.)
   --
   -- gotcha 5: pendingMessages is comma-delimited id,time,name,target -- set
   -- the delimiter before parsing it.
   local tMsgLine
   set the itemDelimiter to comma
   repeat for each line tMsgLine in the pendingMessages
      if item 3 of tMsgLine begins with "heNet" then
         cancel item 1 of tMsgLine
      end if
   end repeat
end heTestSweepNetTimers

command heReportShow pTxt
   -- the harness report panel: a scrollable field the WHOLE report reads in,
   -- with a Close button. Built on first use (so it layers above every other
   -- overlay) and reused after; deliberately NOT part of heBuildTable, so it
   -- needs no kUIVersion bump and never exists until a report does.
   if there is not a field "heReportFld" then
      create graphic "heReportBg"
      set the style of graphic "heReportBg" to "roundrect"
      set the roundRadius of graphic "heReportBg" to 16
      set the rect of graphic "heReportBg" to "112,60,912,620"
      set the backgroundColor of graphic "heReportBg" to "20,26,24"
      set the borderColor of graphic "heReportBg" to kHeGoldColor
      set the borderWidth of graphic "heReportBg" to 2
      set the opaque of graphic "heReportBg" to true
      create field "heReportFld"
      set the rect of field "heReportFld" to "124,72,900,572"
      set the lockText of field "heReportFld" to true
      set the vScrollbar of field "heReportFld" to true
      set the textSize of field "heReportFld" to 11
      set the opaque of field "heReportFld" to true
      set the backgroundColor of field "heReportFld" to "14,18,16"
      set the textColor of field "heReportFld" to kHeWhite
      set the borderWidth of field "heReportFld" to 0
      create button "heBtnReportClose"
      set the rect of button "heBtnReportClose" to "812,580,900,612"
      set the label of button "heBtnReportClose" to "Close"
   end if
   set the text of field "heReportFld" to pTxt
   set the scroll of field "heReportFld" to 0
   show graphic "heReportBg"
   show field "heReportFld"
   show button "heBtnReportClose"
end heReportShow

command heReportHide
   if there is a field "heReportFld" then
      hide graphic "heReportBg"
      hide field "heReportFld"
      hide button "heBtnReportClose"
   end if
end heReportHide

command heRunSection pName
   -- run one test section under a guard: a runtime fault is caught, counted as a
   -- FAIL with its error text, and the remaining sections still run. Keeps a
   -- first-contact arithmetic error in a new section from aborting the harness.
   -- gGame is snapshotted around the section: several sections (netsim above
   -- all) swap gGame for a synthetic context and restore it on their LAST line,
   -- so a mid-section throw used to leave the user's REAL game replaced by the
   -- sim corpse (fake keys, online "true") -- the next Deal click acted on it.
   -- On a throw, the pre-section gGame comes back; a clean section keeps its
   -- own (already restored) state.
   local tErr, tGameSaved
   put gGame into tGameSaved
   try
      do pName
   catch tErr
      add 1 to gFailN
      put "FAIL  " & pName & " THREW: " & tErr & return after gRpt
      put tGameSaved into gGame
   end try
end heRunSection

command heTAssert pLabel, pObserved, pExpected
   if pObserved is pExpected then
      add 1 to gPassN
      put "PASS  " & pLabel & return after gRpt
   else
      add 1 to gFailN
      put "FAIL  " & pLabel & return after gRpt
      put "      observed: " & pObserved & return after gRpt
      put "      expected: " & pExpected & return after gRpt
   end if
end heTAssert

command heTContains pLabel, pObserved, pNeedle
   if pObserved contains pNeedle then
      add 1 to gPassN
      put "PASS  " & pLabel & return after gRpt
   else
      add 1 to gFailN
      put "FAIL  " & pLabel & return after gRpt
      put "      observed: " & pObserved & return after gRpt
      put "      expected to contain: " & pNeedle & return after gRpt
   end if
end heTContains

command heTSkip pLabel, pWhy
   add 1 to gSkipN
   put "SKIP  " & pLabel & " (" & pWhy & ")" & return after gRpt
end heTSkip

command heTestDealRun
   -- on-engine mirror of the Level 0 keyed-stream deal (spec 7.1), pinned in
   -- tools/protocol-kat.py. SKIPs without SodiumXT. Exercises the real
   -- commit-reveal dealing protocol the online game uses.
   local tSeedsA, tXorHex, tKeyData, tDeckList, tDealA, tCommitsA, tTableData
   local tDealLog, tHoles1, tHoles2, tHoles3, tFlopP, tAuditOut
   put return & "-- 11. Level 0 keyed-stream deal (spec 7.1, crypto path)" & return after gRpt
   if not heHasSodium() then
      heTSkip "deal: Level 0 keyed-stream", "SodiumXT not installed"
      exit heTestDealRun
   end if
   set the itemDelimiter to comma
   put kKatSeed1 into tSeedsA[1]
   put kKatSeed2 into tSeedsA[2]
   put kKatSeed3 into tSeedsA[3]
   heTAssert "deal: seeds XOR", heXorSeedsHex(tSeedsA, 3), kKatSeedsXor
   put heHex2BinD(kKatTableHex) into tTableData
   put heStreamKeyData(tTableData, 1, kKatSeedsXor) into tKeyData
   heTAssert "deal: stream key", heBin2HexS(tKeyData), kKatStreamKey
   put heDeckFromStreamKey(tKeyData) into tDeckList
   heTAssert "deal: full shuffled deck (52 cards)", heTNamesOf(tDeckList), kKatDeck
   put heDealAssign(tDeckList, "1,2,3", 1) into tDealA
   heTAssert "deal: hole cards seat 1", heTNamesOf(tDealA["holesBy"][1]), kKatHole1
   heTAssert "deal: hole cards seat 2", heTNamesOf(tDealA["holesBy"][2]), kKatHole2
   heTAssert "deal: hole cards seat 3", heTNamesOf(tDealA["holesBy"][3]), kKatHole3
   heTAssert "deal: flop", heTNamesOf(tDealA["flopList"]), kKatFlop
   heTAssert "deal: turn", heCardName(tDealA["turnIx"]), kKatTurn
   heTAssert "deal: river", heCardName(tDealA["riverIx"]), kKatRiver
   -- the burns were pinned in protocol-kat all along but never re-checked
   -- on-engine; a consumption-order drift would shift every later card
   heTAssert "deal: burn cards (KAT-pinned)", heTNamesOf(tDealA["burnsList"]), "Jd,9d,3d"
   -- end-of-hand audit: honest deal passes; a corrupted commit is named
   put heSeedCommitHex(kKatSeed1) into tCommitsA[1]
   put heSeedCommitHex(kKatSeed2) into tCommitsA[2]
   put heSeedCommitHex(kKatSeed3) into tCommitsA[3]
   heTAssert "deal: seed commitment 1", tCommitsA[1], kKatCommit1
   heTAssert "deal: audit passes the honest deal", \
         heAuditDeal(tTableData, 1, tSeedsA, tCommitsA, 3, tDealA, "1,2,3", 1), "pass"
   put kKatCommit1 into tCommitsA[2]
   heTAssert "deal: audit names a corrupted commit", \
         heAuditDeal(tTableData, 1, tSeedsA, tCommitsA, 3, tDealA, "1,2,3", 1), \
         "fail:commit-mismatch-position-2"

   -- audit-from-TRANSCRIPT (mirror of tools/fold-kat.py): build the canned
   -- Level 0 log heHandStart would write and confirm heAuditDealsFromLog
   -- re-derives the committed shuffle from the revealed seeds -- proving the
   -- played deal is verifiable by anyone with the transcript, and that a
   -- tampered revealed seed is caught.
   put kKatHole1 into tHoles1
   replace comma with "|" in tHoles1
   put kKatHole2 into tHoles2
   replace comma with "|" in tHoles2
   put kKatHole3 into tHoles3
   replace comma with "|" in tHoles3
   put kKatFlop into tFlopP
   replace comma with "|" in tFlopP
   put heLogLine(0, "table", "cfg", "sb=1,bb=2,seats=1|2|3,stacks=400|400|400,button=1") & return into tDealLog
   put heLogLine(1, "table", "handStart", "seats=1|2|3,button=1") & return after tDealLog
   put heLogLine(1, "table", "dealLevel", "level=0,table=" & kKatTableHex & ",count=3") & return after tDealLog
   put heLogLine(1, "seat1", "seedCommit", "pos=1,commit=" & kKatCommit1) & return after tDealLog
   put heLogLine(1, "seat2", "seedCommit", "pos=2,commit=" & kKatCommit2) & return after tDealLog
   put heLogLine(1, "seat3", "seedCommit", "pos=3,commit=" & kKatCommit3) & return after tDealLog
   put heLogLine(1, "seat1", "seedReveal", "pos=1,seed=" & kKatSeed1) & return after tDealLog
   put heLogLine(1, "seat2", "seedReveal", "pos=2,seed=" & kKatSeed2) & return after tDealLog
   put heLogLine(1, "seat3", "seedReveal", "pos=3,seed=" & kKatSeed3) & return after tDealLog
   put heLogLine(1, "table", "holeDeliver", "seat=1,cards=" & tHoles1) & return after tDealLog
   put heLogLine(1, "table", "holeDeliver", "seat=2,cards=" & tHoles2) & return after tDealLog
   put heLogLine(1, "table", "holeDeliver", "seat=3,cards=" & tHoles3) & return after tDealLog
   put heLogLine(1, "table", "board", "street=flop,cards=" & tFlopP) & return after tDealLog
   put heLogLine(1, "table", "board", "street=turn,cards=" & kKatTurn) & return after tDealLog
   put heLogLine(1, "table", "board", "street=river,cards=" & kKatRiver) & return after tDealLog
   put heLogLine(1, "table", "settle", "deltas=1:0|2:0|3:0") & return after tDealLog
   put heAuditDealsFromLog(tDealLog) into tAuditOut
   heTContains "deal: audit-from-transcript re-derives the committed shuffle", tAuditOut, "1/1 deals verified"
   heTContains "deal: audit-from-transcript marks the hand deal-verified", tAuditOut, "hand 1: deal-verified"
   replace ("pos=2,seed=" & kKatSeed2) with ("pos=2,seed=" & kKatSeed1) in tDealLog
   put heAuditDealsFromLog(tDealLog) into tAuditOut
   heTContains "deal: audit-from-transcript catches a tampered seed", tAuditOut, "deal-FAILED"
end heTestDealRun

function heTIdentityDeck
   -- deck 1..52 where each card's value IS its position, so a deal signature
   -- reads the card->seat mapping directly
   local tOut, tI
   put empty into tOut
   repeat with tI = 1 to 52
      put tI & comma after tOut
   end repeat
   delete char -1 of tOut
   return tOut
end heTIdentityDeck

function heTDealSig pDeckList, pOccList, pButton
   -- "seat=h1-h2;... flop=f-f-f turn=t river=r" from heDealAssign, matching
   -- tools/protocol-kat.py deal_signature over the identity deck (all chunks
   -- are of plain locals -- H6-safe)
   local tDealA, tSeatNum, tHole, tOut, tFlop
   set the itemDelimiter to comma
   put heDealAssign(pDeckList, pOccList, pButton) into tDealA
   put empty into tOut
   repeat for each item tSeatNum in pOccList
      put tDealA["holesBy"][tSeatNum] into tHole
      put tSeatNum & "=" & (item 1 of tHole) & "-" & (item 2 of tHole) & ";" after tOut
   end repeat
   delete char -1 of tOut
   put tDealA["flopList"] into tFlop
   put tOut & " flop=" & (item 1 of tFlop) & "-" & (item 2 of tFlop) & "-" & (item 3 of tFlop) \
         & " turn=" & tDealA["turnIx"] & " river=" & tDealA["riverIx"] into tOut
   return tOut
end heTDealSig

command heTestDealOrderRun
   -- pin the card->seat deal mapping (spec 7.1) for configs the main deal KAT
   -- never covers: button not first, non-contiguous seats, heads-up, full ring.
   -- On-engine mirror of tools/protocol-kat.py deal_orders (identity deck).
   local tDeck
   put return & "-- 12. deal order: card->seat mapping across seat configs" & return after gRpt
   put heTIdentityDeck() into tDeck
   heTAssert "deal-order: 3-handed, button 3 (button not first)", \
         heTDealSig(tDeck, "1,2,3", 3), "1=1-4;2=2-5;3=3-6 flop=8-9-10 turn=12 river=14"
   heTAssert "deal-order: non-contiguous seats 2,4,6 button 4", \
         heTDealSig(tDeck, "2,4,6", 4), "2=2-5;4=3-6;6=1-4 flop=8-9-10 turn=12 river=14"
   heTAssert "deal-order: heads-up 1,2 button 1", \
         heTDealSig(tDeck, "1,2", 1), "1=2-4;2=1-3 flop=6-7-8 turn=10 river=12"
   heTAssert "deal-order: heads-up non-contiguous 3,5 button 5", \
         heTDealSig(tDeck, "3,5", 5), "3=1-3;5=2-4 flop=6-7-8 turn=10 river=12"
   heTAssert "deal-order: full ring 1-6 button 4", \
         heTDealSig(tDeck, "1,2,3,4,5,6", 4), \
         "1=3-9;2=4-10;3=5-11;4=6-12;5=1-7;6=2-8 flop=14-15-16 turn=18 river=20"
end heTestDealOrderRun

command heTestLobbyRun
   -- on-engine mirror of the online lobby's signed-presence + reconnect path
   -- (spec 9), pinned in tools/protocol-kat.py. Two in-process identities:
   -- the host (idSeed1) opens a table and signs a cfg (seq 1, from genesis),
   -- then a roster (seq 2) once a player (idSeed2) has joined; a late joiner
   -- replays both from genesis and must land on kKatLobbyHead2. This checks
   -- the exact wires the transport carries, with no network. SKIPs w/o SodiumXT.
   local tPub, tSec, tHostPubHex, tContent, tWire1, tWire2, tWire3, tHead1, tHead2, tHead3
   local tMembers, tMembersRev, tRoster, tClientHead, tVerdict
   put return & "-- 13. Online lobby: signed presence + transcript replay (spec 9)" & return after gRpt
   if not heHasSodium() then
      heTSkip "lobby: signed presence + replay", "SodiumXT not installed"
      exit heTestLobbyRun
   end if
   set the itemDelimiter to comma

   -- canonical roster body: sorting (not input order) fixes the signed bytes
   put kKatIdPub1 & tab & "host" & return & kKatIdPub2 & tab & "player" into tMembers
   put kKatIdPub2 & tab & "player" & return & kKatIdPub1 & tab & "host" into tMembersRev
   put heRosterBody(tMembers) into tRoster
   heTAssert "lobby: canonical roster body", tRoster, kKatRosterBody
   heTAssert "lobby: roster body is order-independent", heRosterBody(tMembersRev), kKatRosterBody

   -- host builds the two presence wires (host is sender AND relay for presence)
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed1), tPub, tSec
   put heBin2HexS(tPub) into tHostPubHex
   put heEnvContentLine(kKatTableHex, 0, tHostPubHex, "cfg", kKatLobbyCfgBody) into tContent
   put heWireBuild(tContent, tSec, 1, kHeGenesisPrev, tSec) into tWire1
   put heChainNextHex(tWire1) into tHead1
   put heEnvContentLine(kKatTableHex, 0, tHostPubHex, "roster", tRoster) into tContent
   put heWireBuild(tContent, tSec, 2, tHead1, tSec) into tWire2
   put heChainNextHex(tWire2) into tHead2
   heTAssert "lobby: presence chain head after cfg+roster", tHead2, kKatLobbyHead2

   -- a joiner replays from genesis: cfg verifies at genesis, roster at head1
   heTAssert "lobby: joiner verifies the cfg wire (from genesis)", \
         heEnvVerify(tWire1, tHostPubHex, tHostPubHex, kHeGenesisPrev), "ok"
   heTAssert "lobby: joiner verifies the roster wire (chained)", \
         heEnvVerify(tWire2, tHostPubHex, tHostPubHex, tHead1), "ok"
   -- out-of-order replay is a chain break: the roster cannot land before the cfg
   heTAssert "lobby: roster before cfg is a chain break", \
         heEnvVerify(tWire2, tHostPubHex, tHostPubHex, kHeGenesisPrev), "drop:chain-break"

   -- resync recovery (spec 9): a client that ingested w1 then MISSED w2 wedges
   -- on w3 (drop:chain-break) -- but a full-log replay recovers it. Replayed w1
   -- drops (already have it), w2 lands on head1, w3 on head2: head reaches head3.
   -- This pins the recovery logic heNetRequestSync/heNetReplayLogTo rely on.
   put heEnvContentLine(kKatTableHex, 0, tHostPubHex, "roster", tRoster) into tContent
   put heWireBuild(tContent, tSec, 3, tHead2, tSec) into tWire3
   put heChainNextHex(tWire3) into tHead3
   put tHead1 into tClientHead
   -- w3 arrives with w2 still missing -> chain break, head does not move
   heTAssert "resync: gapped client drops the ahead-of-gap wire", \
         heEnvVerify(tWire3, tHostPubHex, tHostPubHex, tClientHead), "drop:chain-break"
   -- host replays the whole log; step the client head exactly as ingest would
   put heEnvVerify(tWire1, tHostPubHex, tHostPubHex, tClientHead) into tVerdict
   heTAssert "resync: replayed already-seen wire drops cleanly", tVerdict, "drop:chain-break"
   put heEnvVerify(tWire2, tHostPubHex, tHostPubHex, tClientHead) into tVerdict
   if tVerdict is "ok" then
      put heChainNextHex(tWire2) into tClientHead
   end if
   heTAssert "resync: missing wire now applies", tVerdict, "ok"
   put heEnvVerify(tWire3, tHostPubHex, tHostPubHex, tClientHead) into tVerdict
   if tVerdict is "ok" then
      put heChainNextHex(tWire3) into tClientHead
   end if
   heTAssert "resync: client recovers to the current chain head", tClientHead, tHead3
end heTestLobbyRun

command heTestNetSim
   -- single-machine LOOPBACK of the online message orchestration -- no rp1, no
   -- second machine. We drive the REAL stateful handlers (heHostRelay,
   -- heNetIngestWire) against gGame and route the bytes each side would send by
   -- hand, so seq-assignment, verify-or-drop, chain-advance, and resync recovery
   -- are proven on ONE machine before a networked OXT pass. btRp1Send is never
   -- reached (the host has no live peers, so heNetBroadcast is a no-op and the
   -- resync request finds no host peer). gGame is saved and restored so the sim
   -- never disturbs the live game. SKIPs without SodiumXT.
   local tSaved, tHostPub, tHostSec, tPlayPub, tPlaySec, tHostPubHex, tPlayPubHex
   local tCfgWire, tRosterWire, tActWire, tCfg2Wire, tHostLog, tContent, tSenderSig, tPacket
   local tHead1, tHead2, tHead3, tHead4, tBadPub, tBadSec, tBadPubHex, tGhostWire
   local tPriorCfg, tForgedWire, tPriorHead, tWrongTable, tWrongWire
   put return & "-- 14. Online orchestration loopback (single machine, no rp1)" & return after gRpt
   if not heHasSodium() then
      heTSkip "netsim: online orchestration", "SodiumXT not installed"
      exit heTestNetSim
   end if
   set the itemDelimiter to comma
   put gGame into tSaved

   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed1), tHostPub, tHostSec
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed2), tPlayPub, tPlaySec
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed3), tBadPub, tBadSec
   put heBin2HexS(tHostPub) into tHostPubHex
   put heBin2HexS(tPlayPub) into tPlayPubHex
   put heBin2HexS(tBadPub) into tBadPubHex

   -- ===== HOST context =====
   put empty into gGame
   put "true" into gGame["online"]
   put "true" into gGame["isHost"]
   put tHostPubHex into gGame["idPubHex"]
   put tHostSec into gGame["idSecData"]
   put tHostPubHex into gGame["hostPubHex"]
   put kKatTableHex into gGame["tableIdHex"]
   put 0 into gGame["handNum"]
   put 0 into gGame["seqCounter"]
   put 0 into gGame["syncCooldown"]
   put kHeGenesisPrev into gGame["chainHeadHex"]
   put 0 into gGame["lastSeq"]
   put empty into gGame["wireBuf"]
   put 0 into gGame["wireBufN"]
   put "true" into gGame["admittedA"][tHostPubHex]
   put "true" into gGame["admittedA"][tPlayPubHex]     -- as if the player already handshook
   put "host" into gGame["roleByPub"][tHostPubHex]
   put "player" into gGame["roleByPub"][tPlayPubHex]

   -- host emits a cfg (seq 1): heNetSendAction -> heHostRelay -> local ingest
   heNetSendAction "cfg", kKatLobbyCfgBody
   put gGame["log"] into tHostLog
   heTAssert "netsim: host relayed + logged its own cfg (seq 1)", the number of lines of tHostLog, 1
   put line 1 of tHostLog into tCfgWire
   put gGame["chainHeadHex"] into tHead1

   -- host publishes the roster (seq 2) through the REAL emitter, exactly as it
   -- does after every admission -- this is what makes the player's later action
   -- a ROSTERED sender on every client (the spec 6 unknown-from rule)
   heHostEmitRoster
   put gGame["log"] into tHostLog
   heTAssert "netsim: host emitted the roster (seq 2)", the number of lines of tHostLog, 2
   put line 2 of tHostLog into tRosterWire
   put gGame["chainHeadHex"] into tHead2

   -- a player's signed action arrives; the host relays it (seq 3). This is the
   -- real star-topology path minus the rp1 hop (peerPubA is empty, no broadcast).
   put heEnvContentLine(kKatTableHex, 0, tPlayPubHex, "act", "verb=check,amount=0") into tContent
   put heEnvSenderSigHex(tContent, tPlaySec) into tSenderSig
   put tContent & tab & tSenderSig into tPacket
   heHostRelay 0, tPacket
   put gGame["log"] into tHostLog
   heTAssert "netsim: host verified + relayed a player action (seq 3)", the number of lines of tHostLog, 3
   put line 3 of tHostLog into tActWire
   put gGame["chainHeadHex"] into tHead3

   -- host emits a fourth wire (a cfg refresh)
   heNetSendAction "cfg", kKatLobbyCfgBody
   put gGame["log"] into tHostLog
   put line 4 of tHostLog into tCfg2Wire
   put gGame["chainHeadHex"] into tHead4

   -- a validly-signed action from an UNADMITTED key must be dropped by the relay
   -- (admission is enforced, not just the signature) -- no new wire is produced
   put heEnvContentLine(kKatTableHex, 0, tBadPubHex, "act", "verb=bet,amount=99") into tContent
   put heEnvSenderSigHex(tContent, tBadSec) into tSenderSig
   put tContent & tab & tSenderSig into tPacket
   heHostRelay 0, tPacket
   put gGame["log"] into tHostLog
   heTAssert "netsim: host drops an unadmitted sender (no new wire)", the number of lines of tHostLog, 4

   -- ===== PLAYER context =====
   put empty into gGame
   put "true" into gGame["online"]
   put "false" into gGame["isHost"]
   put tPlayPubHex into gGame["idPubHex"]
   put tPlaySec into gGame["idSecData"]
   put tHostPubHex into gGame["hostPubHex"]
   put kKatTableHex into gGame["tableIdHex"]
   put 0 into gGame["syncCooldown"]
   put kHeGenesisPrev into gGame["chainHeadHex"]
   put 0 into gGame["lastSeq"]
   put empty into gGame["wireBuf"]
   put 0 into gGame["wireBufN"]

   -- player ingests the host cfg wire (seq 1) -> chain advances, cfg body stashed
   heNetIngestWire tCfgWire
   heTAssert "netsim: player accepts host cfg + advances chain to head1", gGame["chainHeadHex"], tHead1
   heTAssert "netsim: player stashed the cfg body", gGame["cfgBody"], kKatLobbyCfgBody
   heTAssert "netsim: player lastSeq is 1 after cfg", gGame["lastSeq"], 1

   -- the roster (seq 2) folds and now lists the player as a member
   heNetIngestWire tRosterWire
   heTAssert "netsim: player accepts the roster, chain at head2", gGame["chainHeadHex"], tHead2
   heTContains "netsim: the roster body lists the player", gGame["rosterBody"], tPlayPubHex

   -- REORDER: the player receives wire 4 (seq 4) BEFORE wire 3 -- rp1 reorders.
   -- It must be HELD (buffered), not dropped, and the chain must stay put.
   heNetIngestWire tCfg2Wire
   heTAssert "netsim: out-of-order future wire is held, chain unchanged", gGame["chainHeadHex"], tHead2
   heTAssert "netsim: the gap wire is buffered (not dropped)", gGame["wireBufN"], 1

   -- the missing wire 3 arrives: it applies (a rostered sender's action) AND the
   -- buffered wire 4 drains behind it, so the chain jumps straight to head4.
   heNetIngestWire tActWire
   heTAssert "netsim: filling the gap cascades the buffered wire to head4", gGame["chainHeadHex"], tHead4
   heTAssert "netsim: buffer emptied after the cascade", gGame["wireBufN"], 0

   -- DUPLICATES: rp1 redelivers wires constantly. An already-applied wire must be
   -- dropped SILENTLY -- no chain change, no resync -- or the client resync-loops
   -- forever and the game never starts (the actual networked bug this fixes).
   heNetIngestWire tCfgWire
   heTAssert "netsim: a duplicate cfg (seq 1) is dropped, chain unchanged", gGame["chainHeadHex"], tHead4
   heNetIngestWire tActWire
   heNetIngestWire tCfg2Wire
   heTAssert "netsim: duplicate wires 3 and 4 are dropped, chain stays head4", gGame["chainHeadHex"], tHead4
   heTAssert "netsim: lastSeq stays 4 through the duplicates", gGame["lastSeq"], 4

   -- spec 6 unknown-from (deep-dive transport): a host-SIGNED wire whose sender
   -- is not in the host-signed roster can only mean a corrupt host stream. The
   -- chain link is authentic so it advances (refusing it would wedge the
   -- table), but the body is marked and never folds.
   put heEnvContentLine(kKatTableHex, 0, tBadPubHex, "act", "verb=bet,amount=99") into tContent
   put heWireBuild(tContent, tBadSec, 5, gGame["chainHeadHex"], tHostSec) into tGhostWire
   heNetIngestWire tGhostWire
   heTAssert "netsim: an unrostered sender's wire still advances the chain (seq 5)", gGame["lastSeq"], 5
   heTContains "netsim: the unrostered sender is marked in the net feed", gGame["netLog"], "unrostered sender"

   -- host-authority on ingest (deep-dive [1]/[6]): a wire whose cfg content is
   -- authored by a NON-host key -- even if it is otherwise valid, host-signed,
   -- and from a ROSTERED member -- must NOT overwrite the cfg body. Build one
   -- from the player key and confirm the stashed cfg is untouched.
   put gGame["cfgBody"] into tPriorCfg
   put heEnvContentLine(kKatTableHex, 0, tPlayPubHex, "cfg", "v=1,level=0,sb=999,bb=999,seats=6,button=1") into tContent
   put heWireBuild(tContent, tPlaySec, 6, gGame["chainHeadHex"], tHostSec) into tForgedWire
   heNetIngestWire tForgedWire
   heTAssert "netsim: a non-host cfg body is not folded (host-authority)", gGame["cfgBody"], tPriorCfg

   -- table binding on ingest (deep-dive [4]/[5]): a host-signed wire for a DIFFERENT
   -- table is dropped and the chain does not advance.
   put gGame["chainHeadHex"] into tPriorHead
   put "1111111111111111111111111111111111111111111111111111111111111111" into tWrongTable
   put heEnvContentLine(tWrongTable, 0, tHostPubHex, "cfg", kKatLobbyCfgBody) into tContent
   put heWireBuild(tContent, tHostSec, 7, tPriorHead, tHostSec) into tWrongWire
   heNetIngestWire tWrongWire
   heTAssert "netsim: a wire for another table is dropped (chain unchanged)", gGame["chainHeadHex"], tPriorHead

   put tSaved into gGame
end heTestNetSim

command heTNetDeliver pPayloadTxt
   -- netplay loopback: deliver one captured rp1 payload into the CURRENT
   -- gGame context through the REAL message router, so control frames (the
   -- "r!" catch-up marker above all) take exactly the production path. Peer
   -- handle 0 is the loopback's stand-in for the counterparty's live handle.
   heNetOnMessage 0, textEncode(pPayloadTxt, "utf-8")
end heTNetDeliver

command heTNetPump
   -- shuttle captured payloads between the contexts until all go quiet.
   -- Player outboxes carry "c" frames to the host; the host outbox carries
   -- "w" broadcasts to EVERY player (heNetBroadcast captures ONE copy; the
   -- pump is the fan-out, exactly the star topology's shape). The second
   -- player context exists only in the oracle section (gTNetPlay2G is an
   -- array there; empty everywhere else, and the guards skip it).
   local tRound, tQuiet, tCarry, tLine
   repeat with tRound = 1 to 400
      put "true" into tQuiet
      put gTNetPlayG["netOutbox"] into tCarry
      put empty into gTNetPlayG["netOutbox"]
      if tCarry is not empty then
         put "false" into tQuiet
         put gTNetHostG into gGame
         repeat for each line tLine in tCarry
            if tLine is not empty then
               heTNetDeliver tLine
            end if
         end repeat
         put gGame into gTNetHostG
      end if
      if gTNetPlay2G is an array then
         put gTNetPlay2G["netOutbox"] into tCarry
         put empty into gTNetPlay2G["netOutbox"]
         if tCarry is not empty then
            put "false" into tQuiet
            put gTNetHostG into gGame
            repeat for each line tLine in tCarry
               if tLine is not empty then
                  heTNetDeliver tLine
               end if
            end repeat
            put gGame into gTNetHostG
         end if
      end if
      put gTNetHostG["netOutbox"] into tCarry
      put empty into gTNetHostG["netOutbox"]
      if tCarry is not empty then
         put "false" into tQuiet
         put gTNetPlayG into gGame
         repeat for each line tLine in tCarry
            if tLine is not empty then
               heTNetDeliver tLine
            end if
         end repeat
         put gGame into gTNetPlayG
         if gTNetPlay2G is an array then
            put gTNetPlay2G into gGame
            repeat for each line tLine in tCarry
               if tLine is not empty then
                  heTNetDeliver tLine
               end if
            end repeat
            put gGame into gTNetPlay2G
         end if
      end if
      if tQuiet is "true" then
         exit repeat
      end if
   end repeat
end heTNetPump

command heTNetAct pSeatNum, pBodyTxt
   -- emit an act from whichever context owns the seat, then pump to quiet
   local tMySeat
   put gTNetPlayG into gGame
   put heNetMySeat() into tMySeat
   if tMySeat is pSeatNum then
      heNetSendAction "act", pBodyTxt
      put gGame into gTNetPlayG
   else
      put gGame into gTNetPlayG
      put gTNetHostG into gGame
      heNetSendAction "act", pBodyTxt
      put gGame into gTNetHostG
   end if
   heTNetPump
end heTNetAct

command heTNetOracleAct pSeatNum, pBodyTxt
   -- oracle-table loopback: an act comes from whichever PLAYER context owns
   -- the seat -- the oracle host never acts (it has no seat to act from)
   local tMySeat
   put gTNetPlayG into gGame
   put heNetMySeat() into tMySeat
   put gGame into gTNetPlayG
   if tMySeat is pSeatNum then
      put gTNetPlayG into gGame
      heNetSendAction "act", pBodyTxt
      put gGame into gTNetPlayG
   else
      put gTNetPlay2G into gGame
      heNetSendAction "act", pBodyTxt
      put gGame into gTNetPlay2G
   end if
   heTNetPump
end heTNetOracleAct

command heTNetPlayCtx pIsHost, pPubHex, pSecData, pBoxPub, pBoxSec, pHostPubHex, pIdSeedHex
   -- one netplay context: the online keys + game store a create/join builds,
   -- with the capture seam on and the host's between-hands timer off
   put empty into gGame
   put "true" into gGame["online"]
   put pIsHost into gGame["isHost"]
   put pPubHex into gGame["idPubHex"]
   put pSecData into gGame["idSecData"]
   put pIdSeedHex into gGame["idSeedHex"]
   put pBoxPub into gGame["boxPubData"]
   put pBoxSec into gGame["boxSecData"]
   put pHostPubHex into gGame["hostPubHex"]
   put kKatTableHex into gGame["tableIdHex"]
   put 1 into gGame["sb"]
   put 2 into gGame["bb"]
   put 0 into gGame["ante"]
   put 400 into gGame["startStack"]
   put 0 into gGame["handNum"]
   put 0 into gGame["seqCounter"]
   put 0 into gGame["syncCooldown"]
   put kHeGenesisPrev into gGame["chainHeadHex"]
   put 0 into gGame["lastSeq"]
   put empty into gGame["wireBuf"]
   put 0 into gGame["wireBufN"]
   heNetGameInit
   put "false" into gGame["autoNext"]
   put "true" into gGame["netCap"]
   put empty into gGame["netOutbox"]
   -- the loopback's peer handle for the host is 0 (heTNetDeliver's stand-in),
   -- so the "r!" catch-up marker's from-the-host transport check passes
   put 0 into gGame["peerByPub"][pHostPubHex]
   put "idle" into gGame["phase"]
end heTNetPlayCtx

command heTestNetPlay
   -- a FULL online Level 0 hand, twice, on one machine: host + player contexts
   -- driving the REAL handlers end to end -- cfg/roster, join (session box
   -- binding), sit, handStart/dealLevel, seedCommit -> seedSeal -> sealed
   -- holeDeliver (real sxSeal roundtrips), blinds, betting, dealer board
   -- wires, seed reveals, the verified settle, receipt co-signatures, and
   -- per-client audits. Hand 1 is a scripted fold-win (deterministic deltas
   -- whatever the deck); hand 2 checks down to a showdown (the deck is real
   -- entropy, so the asserts there are invariants: conservation, agreement,
   -- clean audits). SKIPs without SodiumXT or without its box surface.
   local tSaved, tHostPub, tHostSec, tPlayPub, tPlaySec, tHostPubHex, tPlayPubHex
   local tHostBoxPub, tHostBoxSec, tPlayBoxPub, tPlayBoxSec, tBoxErr
   local tStateA, tSbSeat, tBbSeat, tStep, tSeat, tOwe, tBoardTxt, tRcptHand1
   local tSnapG, tEvil, tEvilC, tOffPub, tOffSec, tDlrSeat, tDlrPub, tDlrSec, tStackSnap
   local tSeqSnap, tXlatTxt, tXlatFold, tOutboxTxt
   put return & "-- 15. Online Level 0 hand, end to end (single-machine loopback)" & return after gRpt
   if not heHasSodium() then
      heTSkip "netplay: online hand", "SodiumXT not installed"
      exit heTestNetPlay
   end if
   set the itemDelimiter to comma
   put gGame into tSaved
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed1), tHostPub, tHostSec
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed2), tPlayPub, tPlaySec
   put heBin2HexS(tHostPub) into tHostPubHex
   put heBin2HexS(tPlayPub) into tPlayPubHex
   try
      sxBoxKeypairFromSeed heHash32(textEncode(kHeDomainSess & kKatIdSeed1, "utf-8")), \
            tHostBoxPub, tHostBoxSec
      sxBoxKeypairFromSeed heHash32(textEncode(kHeDomainSess & kKatIdSeed2, "utf-8")), \
            tPlayBoxPub, tPlayBoxSec
      get sxSeal(textEncode("probe", "utf-8"), tHostBoxPub)
   catch tBoxErr
      put tSaved into gGame
      heTSkip "netplay: online hand", "SodiumXT box surface not available"
      exit heTestNetPlay
   end try

   -- host context opens the table: signed cfg + roster, then its own join
   heTNetPlayCtx "true", tHostPubHex, tHostSec, tHostBoxPub, tHostBoxSec, tHostPubHex, kKatIdSeed1
   put "true" into gGame["admittedA"][tHostPubHex]
   put "true" into gGame["admittedA"][tPlayPubHex]
   put "host" into gGame["roleByPub"][tHostPubHex]
   put "player" into gGame["roleByPub"][tPlayPubHex]
   heNetSendAction "cfg", heLobbyCfgBody()
   heHostEmitRoster
   put gGame into gTNetHostG
   heTNetPlayCtx "false", tPlayPubHex, tPlaySec, tPlayBoxPub, tPlayBoxSec, tHostPubHex, kKatIdSeed2
   put gGame into gTNetPlayG
   heTNetPump
   heTAssert "netplay: both session box keys bound on-chain (host view)", \
         the number of lines of the keys of gTNetHostG["boxByPub"], 2
   heTAssert "netplay: both session box keys bound on-chain (player view)", \
         the number of lines of the keys of gTNetPlayG["boxByPub"], 2

   -- the host starts the game: sit wires + hand 1; the deal and the blinds
   -- then run themselves through the react engine on both sides
   put gTNetHostG into gGame
   heNetStartGame
   put gGame into gTNetHostG
   heTNetPump
   put gTNetPlayG["state"] into tStateA
   heTAssert "netplay: hand 1 dealt itself to the action (phase acting)", tStateA["phase"], "acting"
   heTAssert "netplay: both sides at the same chain head", \
         gTNetPlayG["chainHeadHex"], gTNetHostG["chainHeadHex"]
   heTAssert "netplay: the player's sealed holes opened", \
         (gTNetPlayG["oDeal"]["myHoles"] is not empty), "true"
   heTAssert "netplay: the host's sealed holes opened", \
         (gTNetHostG["oDeal"]["myHoles"] is not empty), "true"
   put tStateA["sbSeat"] into tSbSeat
   put tStateA["bbSeat"] into tBbSeat
   heTAssert "netplay: heads-up preflop action is on the button/SB", tStateA["toAct"], tSbSeat

   -- hand 1: the SB folds -> deterministic deltas (SB -1, BB +1) no matter
   -- what the committed deck was; then reveals/settle/receipts/audits flow
   heTNetAct tSbSeat, "verb=fold,amount=0"
   heTAssert "netplay: hand 1 settled on both sides", \
         gTNetPlayG["oDeal"]["settleDone"] & "/" & gTNetHostG["oDeal"]["settleDone"], "true/true"
   heTAssert "netplay: the folder paid its blind", gTNetPlayG["stacksBy"][tSbSeat], 399
   heTAssert "netplay: the winner collected it", gTNetPlayG["stacksBy"][tBbSeat], 401
   heTAssert "netplay: stacks agree across the wire", \
         gTNetPlayG["stacksBy"][tSbSeat] & "/" & gTNetPlayG["stacksBy"][tBbSeat], \
         gTNetHostG["stacksBy"][tSbSeat] & "/" & gTNetHostG["stacksBy"][tBbSeat]
   heTAssert "netplay: receipt heads agree and left genesis", \
         (gTNetPlayG["rcptHeadHex"] is gTNetHostG["rcptHeadHex"] \
         and gTNetPlayG["rcptHeadHex"] is not kHeGenesisPrev), "true"
   heTContains "netplay: the receipt is co-signed by both seats", \
         gTNetPlayG["netLog"], "receipt co-signed by all 2"
   heTContains "netplay: seat 1 audits the deal clean", gTNetPlayG["netLog"], "audit  seat 1: pass"
   heTContains "netplay: seat 2 audits the deal clean", gTNetPlayG["netLog"], "audit  seat 2: pass"
   put gTNetPlayG["rcptHeadHex"] into tRcptHand1

   -- hand 2: kicked by the host (the sim keeps autoNext off). Played to the
   -- flop, then the PLAYER CRASHES AND RECONNECTS mid-hand: its context is
   -- rebuilt from nothing but its keys and identity seed, the host replays
   -- the whole signed transcript (spec 9), and the rebuilt client must
   -- converge byte-for-byte AND keep playing -- the deterministic per-hand
   -- seed re-derives, the sealed holes re-open from the replayed wire, and
   -- the hand checks down to a showdown with the usual invariants (real
   -- entropy decides the winner): five board cards on the wire, chip
   -- conservation, agreement, a fresh receipt link, clean audits.
   put gTNetHostG into gGame
   heNetHandKick
   put gGame into gTNetHostG
   heTNetPump
   -- preflop: SB completes, BB checks -> the dealer wires the flop
   put gTNetPlayG["state"] into tStateA
   heTNetAct tStateA["toAct"], "verb=call,amount=1"
   put gTNetPlayG["state"] into tStateA
   heTNetAct tStateA["toAct"], "verb=check,amount=0"
   put gTNetPlayG["oDeal"]["boardList"] into tBoardTxt
   heTAssert "netplay: the flop is on the wire before the crash", the number of items of tBoardTxt, 3

   -- adversarial probe, mid-hand: an out-of-turn act -- host-signed and
   -- correctly sequenced, so it APPLIES to the chain -- must be ENGINE-
   -- rejected on fold (drop-and-log). Probes run on a THROWAWAY copy of the
   -- player context so the poisoned chain never leaks into the honest stream.
   put gTNetPlayG into tSnapG
   put gTNetPlayG into gGame
   put gGame["state"] into tStateA
   if tStateA["toAct"] is heNetMySeat() then
      put tHostPubHex into tOffPub
      put tHostSec into tOffSec
   else
      put tPlayPubHex into tOffPub
      put tPlaySec into tOffSec
   end if
   put heEnvContentLine(kKatTableHex, gGame["handNum"], tOffPub, "act", "verb=check,amount=0") into tEvilC
   put heWireBuild(tEvilC, tOffSec, gGame["lastSeq"] + 1, gGame["chainHeadHex"], tHostSec) into tEvil
   heNetIngestWire tEvil
   heTContains "netplay: an out-of-turn act is engine-rejected on fold", \
         gGame["netLog"], "engine-rejected act"
   put tSnapG into gTNetPlayG

   -- adversarial probe: a holeDeliver that will not OPEN (junk ciphertext,
   -- but host-signed and dealer-authored) is a logged drop, never a throw,
   -- and the holes stay unset
   put gTNetPlayG into tSnapG
   put gTNetPlayG into gGame
   put gGame["oDeal"]["dealerSeat"] into tDlrSeat
   put gGame["pubBySeat"][tDlrSeat] into tDlrPub
   if tDlrPub is tHostPubHex then
      put tHostSec into tDlrSec
   else
      put tPlaySec into tDlrSec
   end if
   put empty into gGame["oDeal"]["myHoles"]
   put empty into gGame["oDeal"]["holeSealedBy"][heNetMySeat()]
   put heEnvContentLine(kKatTableHex, gGame["handNum"], tDlrPub, "holeDeliver", \
         "seat=" & heNetMySeat() & ",sealed=deadbeef") into tEvilC
   put heWireBuild(tEvilC, tDlrSec, gGame["lastSeq"] + 1, gGame["chainHeadHex"], tHostSec) into tEvil
   heNetIngestWire tEvil
   heTContains "netplay: a junk sealed delivery is a logged drop", \
         gGame["netLog"], "would not open"
   heTAssert "netplay: the junk delivery leaves the holes unset", \
         (gGame["oDeal"]["myHoles"] is empty), "true"
   put tSnapG into gTNetPlayG

   -- RECONNECT: rebuild the player from nothing but its keys and identity
   -- seed, then the host replays the whole signed transcript into it. The
   -- replay must add ZERO new wires to the live chain -- the "r!" catch-up
   -- marker suppresses the rebuilt client's reactions until it is caught up,
   -- so mid-replay states never leak duplicate emissions (Codex, PR #39).
   put gTNetHostG["lastSeq"] into tSeqSnap
   heTNetPlayCtx "false", tPlayPubHex, tPlaySec, tPlayBoxPub, tPlayBoxSec, tHostPubHex, kKatIdSeed2
   put gGame into gTNetPlayG
   put gTNetHostG into gGame
   heNetReplayLogTo 0
   put gGame into gTNetHostG
   heTNetPump
   heTAssert "reconnect: the catch-up replay added ZERO wires to the chain", \
         gTNetHostG["lastSeq"], tSeqSnap
   heTAssert "reconnect: the rebuilt client reaches the host's chain head", \
         gTNetPlayG["chainHeadHex"], gTNetHostG["chainHeadHex"]
   heTAssert "reconnect: seat map and stacks recovered", \
         gTNetPlayG["stacksBy"][1] & "/" & gTNetPlayG["stacksBy"][2] & "/" & gTNetPlayG["seatByPub"][tPlayPubHex], \
         gTNetHostG["stacksBy"][1] & "/" & gTNetHostG["stacksBy"][2] & "/" & gTNetHostG["seatByPub"][tPlayPubHex]
   heTAssert "reconnect: the mid-hand street recovered", \
         gTNetPlayG["state"]["street"], gTNetHostG["state"]["street"]
   heTAssert "reconnect: the sealed holes re-opened from the replayed wire", \
         (gTNetPlayG["oDeal"]["myHoles"] is not empty), "true"

   -- ...and the hand keeps playing from the reconnected state: check it down
   repeat with tStep = 1 to 20
      put gTNetPlayG["state"] into tStateA
      if tStateA["phase"] is not "acting" then
         exit repeat
      end if
      put tStateA["toAct"] into tSeat
      put tStateA["betCur"] - tStateA["streetBy"][tSeat] into tOwe
      if tOwe > 0 then
         heTNetAct tSeat, "verb=call,amount=" & min(tOwe, tStateA["stackBy"][tSeat])
      else
         heTNetAct tSeat, "verb=check,amount=0"
      end if
   end repeat
   heTAssert "netplay: hand 2 settled on both sides", \
         gTNetPlayG["oDeal"]["settleDone"] & "/" & gTNetHostG["oDeal"]["settleDone"], "true/true"
   put gTNetPlayG["oDeal"]["boardList"] into tBoardTxt
   heTAssert "netplay: the dealer wired all five board cards", the number of items of tBoardTxt, 5
   heTAssert "netplay: chips conserved through the showdown", \
         gTNetPlayG["stacksBy"][1] + gTNetPlayG["stacksBy"][2], 800
   heTAssert "netplay: hand 2 stacks agree across the wire", \
         gTNetPlayG["stacksBy"][1] & "/" & gTNetPlayG["stacksBy"][2], \
         gTNetHostG["stacksBy"][1] & "/" & gTNetHostG["stacksBy"][2]
   heTAssert "netplay: the receipt chain advanced hand to hand", \
         (gTNetPlayG["rcptHeadHex"] is not tRcptHand1 \
         and gTNetPlayG["rcptHeadHex"] is gTNetHostG["rcptHeadHex"]), "true"
   heTAssert "netplay: both sides end at the same chain head", \
         gTNetPlayG["chainHeadHex"], gTNetHostG["chainHeadHex"]

   -- 2e STREET CKPTS: every boundary this checked-down hand crossed got a
   -- ckpt wire from BOTH seats, all naming the transition wire's head --
   -- which both contexts recorded identically (fork detection's premise)
   heTAssert "ckpt: both seats checkpointed the flop boundary", \
         (gTNetPlayG["oDeal"]["ckptsBy"]["flop:1"] is not empty \
         and gTNetPlayG["oDeal"]["ckptsBy"]["flop:2"] is not empty), "true"
   heTAssert "ckpt: river + showdown boundaries checkpointed too", \
         (gTNetPlayG["oDeal"]["ckptsBy"]["river:1"] is not empty \
         and gTNetPlayG["oDeal"]["ckptsBy"]["showdown:2"] is not empty), "true"
   heTAssert "ckpt: the recorded flop boundary heads agree across the wire", \
         gTNetPlayG["oDeal"]["ckptHeadBy"]["flop"], gTNetHostG["oDeal"]["ckptHeadBy"]["flop"]
   heTAssert "ckpt: no fork evidence on the honest stream", \
         (gTNetPlayG["netLog"] contains "CKPT-FORK"), "false"
   -- 2e SHOW/MUCK: both contested seats declared a display choice after the
   -- verified settle, and at least one SHOWS (a claimed pot is a shown
   -- hand; a chopped pot shows both) -- entropy decides which
   heTAssert "show/muck: both contested seats declared a display choice", \
         (gTNetPlayG["oDeal"]["showBy"][1] is not empty \
         and gTNetPlayG["oDeal"]["showBy"][2] is not empty), "true"
   heTContains "show/muck: at least one seat shows", \
         gTNetPlayG["oDeal"]["showBy"][1] & "/" & gTNetPlayG["oDeal"]["showBy"][2], "show"
   heTAssert "show/muck: the display choices agree across the wire", \
         gTNetPlayG["oDeal"]["showBy"][1] & "/" & gTNetPlayG["oDeal"]["showBy"][2], \
         gTNetHostG["oDeal"]["showBy"][1] & "/" & gTNetHostG["oDeal"]["showBy"][2]

   -- 2e TRIMMED RESYNC: a caught-up client's "s?" now names its applied
   -- seq, and the host's replay is the "r!" marker and NOTHING else (the
   -- spec 9 since-your-last-checkpoint replay, keyed by seq; the bare
   -- pre-2e "s?" still means a full replay). Driven through the real
   -- router; the outbox is inspected, not delivered.
   put gTNetPlayG["lastSeq"] into tSeqSnap
   put gTNetHostG into gGame
   put tPlayPubHex into gGame["peerPubA"][0]   -- the loopback handle, admitted
   put empty into gGame["netOutbox"]
   heNetOnMessage 0, textEncode("s?" & tab & tSeqSnap, "utf-8")
   -- copy the outbox to a plain local before chunking it (H6)
   put gGame["netOutbox"] into tOutboxTxt
   heTAssert "resync: a caught-up peer's trimmed replay is marker-only", \
         the number of lines of tOutboxTxt & "/" & char 1 to 3 of line 1 of tOutboxTxt, \
         "1/r!" & tab
   put empty into gGame["netOutbox"]
   put gGame into gTNetHostG

   -- 2e ONLINE HISTORY FOLDING: the signed chain translates to the hotseat
   -- shape and the SAME fold + deal audit run over it -- two settled hands,
   -- every settle re-verified, both committed shuffles re-derived
   put heNetLogToHotseat(gTNetHostG["log"]) into tXlatTxt
   put heFoldTranscript(tXlatTxt) into tXlatFold
   heTAssert "history: the translated chain folds two settled hands", \
         the number of lines of tXlatFold["history"], 2
   heTAssert "history: the translated fold reports zero errors", \
         (tXlatFold["errors"] is empty), "true"
   heTContains "history: the translated settles re-verify", \
         tXlatFold["history"], "settle-verified"
   heTAssert "history: the translated stacks match the live ones", \
         tXlatFold["stacksBy"][1] & "/" & tXlatFold["stacksBy"][2], \
         gTNetHostG["stacksBy"][1] & "/" & gTNetHostG["stacksBy"][2]
   heTContains "history: the deal audit re-derives both committed shuffles", \
         heAuditDealsFromLog(tXlatTxt), "2/2 deals verified"

   -- adversarial probe, post-hand: a seedReveal that does not open its
   -- commitment is NAMED and never stored (the commit check runs first)
   put gTNetPlayG into tSnapG
   put gTNetPlayG into gGame
   put gGame["pubBySeat"][heNetSeatAtPos(1)] into tOffPub
   if tOffPub is tHostPubHex then
      put tHostSec into tOffSec
   else
      put tPlaySec into tOffSec
   end if
   put heEnvContentLine(kKatTableHex, gGame["handNum"], tOffPub, "seedReveal", \
         "pos=1,seed=" & kKatSeed3) into tEvilC
   put heWireBuild(tEvilC, tOffSec, gGame["lastSeq"] + 1, gGame["chainHeadHex"], tHostSec) into tEvil
   heNetIngestWire tEvil
   heTContains "netplay: a reveal that breaks its commitment is named", \
         gGame["netLog"], "does not match its commit"
   put tSnapG into gTNetPlayG

   -- adversarial probe, post-hand: a host settle that LIES about the deltas
   -- is refused outright -- the client recomputes and never folds it
   put gTNetPlayG into tSnapG
   put gTNetPlayG into gGame
   put "false" into gGame["oDeal"]["settleDone"]
   put gGame["stacksBy"][1] into tStackSnap
   put heEnvContentLine(kKatTableHex, gGame["handNum"], tHostPubHex, "settle", \
         "deltas=1:400|2:-400") into tEvilC
   put heWireBuild(tEvilC, tHostSec, gGame["lastSeq"] + 1, gGame["chainHeadHex"], tHostSec) into tEvil
   heNetIngestWire tEvil
   heTContains "netplay: a lying host settle is refused", gGame["netLog"], "SETTLE-MISMATCH"
   heTAssert "netplay: the refused settle moved no chips", gGame["stacksBy"][1], tStackSnap
   heTAssert "netplay: the refused settle did not complete the hand", \
         gGame["oDeal"]["settleDone"], "false"
   put tSnapG into gTNetPlayG

   put empty into gTNetHostG
   put empty into gTNetPlayG
   put tSaved into gGame
end heTestNetPlay

command heTestCryptoRun
   -- on-engine mirror of tools/protocol-kat.py (spec 6 + 7.1 crypto). SKIPs
   -- cleanly without SodiumXT; all-green confirms the online transcript
   -- foundation runs on this engine with the corrected sxHash/sign calls.
   local tPub, tSec, tHostPub, tHostSec, tContent, tWire, tPrevHex, tChainData
   local tSenderSeeds, tHands, tTypes, tBodies, tSeq, tTampered
   put return & "-- 9. SodiumXT crypto: hash / identity / signed envelope (spec 6)" & return after gRpt
   if not heHasSodium() then
      heTSkip "crypto: all SodiumXT KATs", "SodiumXT not installed"
      exit heTestCryptoRun
   end if
   set the itemDelimiter to comma

   heTAssert "crypto: sxHash(empty,32) is BLAKE2b-256", heHashHex(textEncode("", "utf-8")), kKatHashEmpty
   heTAssert "crypto: domain-separated seed commit 1", \
         heHashDomHex(kHeDomainSeedC, heHex2BinD(kKatSeed1)), kKatCommit1
   heTAssert "crypto: domain-separated seed commit 2", \
         heHashDomHex(kHeDomainSeedC, heHex2BinD(kKatSeed2)), kKatCommit2
   heTAssert "crypto: domain-separated seed commit 3", \
         heHashDomHex(kHeDomainSeedC, heHex2BinD(kKatSeed3)), kKatCommit3

   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed1), tPub, tSec
   heTAssert "crypto: ed25519 identity pubkey from seed", heBin2HexS(tPub), kKatIdPub1

   -- the two TRUNCATIONS of that same digest, both one-liners and both
   -- unpinned until now. The infohash is the expensive one to get wrong: it
   -- is the spec 10 DHT rendezvous id, so an off-by-one in the chunk (or
   -- hashing the table id's HEX TEXT instead of its BYTES) does not fail
   -- anywhere -- it just puts two machines on two different DHT keys, and
   -- the whole multi-machine session is spent watching a lobby that never
   -- fills. Mirrored in protocol-kat as table_infohash / id_fingerprint1.
   heTAssert "crypto: the DHT rendezvous id is 40 hex of H(tableId bytes)", \
         heTableInfohash(kKatTableHex), kKatTableInfohash
   heTAssert "crypto: the display fingerprint is 8 hex of H(pubkey)", \
         heFingerprintOf(tPub), kKatIdFingerprint1

   put heEnvContentLine(kKatTableHex, 0, kKatIdPub1, "cfg", kKatCfgBody) into tContent
   heTAssert "crypto: canonical content-line bytes", \
         heBin2HexS(textEncode(tContent, "utf-8")), kKatEnv0ContentHex
   heTAssert "crypto: sender signature over the content line", \
         heEnvSenderSigHex(tContent, tSec), kKatEnv0SenderSig

   -- rebuild the six-envelope hash chain (host relay = identity 1)
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed1), tHostPub, tHostSec
   put kKatIdSeed1 & return & kKatIdSeed1 & return & kKatIdSeed2 & return \
         & kKatIdSeed3 & return & kKatIdSeed2 & return & kKatIdSeed3 into tSenderSeeds
   put "0,1,1,1,1,1" into tHands
   put "cfg,seedCommit,seedCommit,seedCommit,bidSB,bidBB" into tTypes
   put kKatCfgBody & return & kKatCommit1 & return & kKatCommit2 & return \
         & kKatCommit3 & return & "amount=1" & return & "amount=2" into tBodies
   put kHeGenesisPrev into tPrevHex
   repeat with tSeq = 1 to 6
      sxSignKeypairFromSeed heHex2BinD(line tSeq of tSenderSeeds), tPub, tSec
      put heEnvContentLine(kKatTableHex, item tSeq of tHands, heBin2HexS(tPub), \
            item tSeq of tTypes, line tSeq of tBodies) into tContent
      put heWireBuild(tContent, tSec, tSeq, tPrevHex, tHostSec) into tWire
      put heChainNextHex(tWire) into tPrevHex
      put heHex2BinD(tPrevHex) into tChainData
   end repeat
   heTAssert "crypto: six-envelope chain head", tPrevHex, kKatChainHead6
   heTAssert "crypto: settlement receipt hash", \
         heSettleHashHex("1:-4,2:8,3:-4", tChainData), kKatSettleHash

   -- verify-or-drop (spec 6): honest wire accepted, tampered body rejected
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed1), tPub, tSec
   put heEnvContentLine(kKatTableHex, 0, heBin2HexS(tPub), "cfg", kKatCfgBody) into tContent
   put heWireBuild(tContent, tSec, 1, kHeGenesisPrev, tSec) into tWire
   heTAssert "crypto: verify accepts an honest wire", \
         heEnvVerify(tWire, heBin2HexS(tPub), heBin2HexS(tPub), kHeGenesisPrev), "ok"
   put tWire into tTampered
   set the itemDelimiter to tab
   put heBin2HexS(textEncode("v=1,level=0,sb=9,bb=9,seats=3,button=1", "utf-8")) into item 6 of tTampered
   set the itemDelimiter to comma
   heTAssert "crypto: verify drops a tampered body", \
         heEnvVerify(tTampered, heBin2HexS(tPub), heBin2HexS(tPub), kHeGenesisPrev), "drop:bad-sender-sig"
   -- expect a DIFFERENT admitted key than the wire's actual signer
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed2), tHostPub, tHostSec
   heTAssert "crypto: verify drops an unknown sender", \
         heEnvVerify(tWire, heBin2HexS(tHostPub), heBin2HexS(tPub), kHeGenesisPrev), "drop:unknown-from"
   heTAssert "crypto: verify drops a chain break", \
         heEnvVerify(tWire, heBin2HexS(tPub), heBin2HexS(tPub), kKatChainHead6), "drop:chain-break"
   -- H4: a malformed (non-hex) field must DROP cleanly, never throw out of the
   -- poll loop. Corrupt the from-key to non-hex and confirm the verdict.
   put tWire into tTampered
   set the itemDelimiter to tab
   put "zznothexzz" into item 4 of tTampered
   set the itemDelimiter to comma
   heTAssert "crypto: verify drops a malformed hex field (no throw)", \
         heEnvVerify(tTampered, empty, heBin2HexS(tPub), kHeGenesisPrev), "drop:malformed"
   heTAssert "crypto: heIsHex rejects odd-length and non-hex", \
         heIsHex("abc", 0) & "," & heIsHex("zz", 0) & "," & heIsHex("ab", 0), "false,false,true"

   -- admission token (spec 5): host-role signature pinned, and the verify
   -- roundtrip returns the admitted pubkey for a good token, "" for a wrong
   -- table, and the role is recoverable for host adoption
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed1), tPub, tSec
   heTAssert "admit: host-token signature", \
         heBin2HexS(heSignDetachedD(textEncode(kHeDomainSess & kKatTableHex & "|" & kKatIdPub1 & "|host", "utf-8"), tSec)), \
         kKatAdmitSig
   heTAssert "admit: verify accepts a good token", \
         heAdmitTokenVerify(heAdmitTokenData(kKatTableHex, kKatIdPub1, tSec, "host"), kKatTableHex), kKatIdPub1
   heTAssert "admit: verify rejects a wrong-table token", \
         heAdmitTokenVerify(heAdmitTokenData(kKatTableHex, kKatIdPub1, tSec, "host"), kKatChainHead6), ""
   heTAssert "admit: role is recoverable", \
         heAdmitTokenRole(heAdmitTokenData(kKatTableHex, kKatIdPub1, tSec, "host")), "host"
end heTestCryptoRun

command heTestReceiptRun
   -- on-engine mirror of the host-trust hardening (spec 6 checkpoints + 8.3
   -- settlement receipts), pinned in tools/protocol-kat.py. Three players are
   -- simulated with the KAT identities, so the MULTI-PARTY signed ledger is
   -- verified on one machine. SKIPs without SodiumXT.
   local tPub1, tSec1, tPub2, tSec2, tPub3, tSec3, tSh2, tRh1, tRh2, tSig1, tSig2, tSig3
   local tContent, tWire, tHead
   put return & "-- 10. Host trust: checkpoints + multi-signed settlement receipts" & return after gRpt
   if not heHasSodium() then
      heTSkip "receipts: ckpt + settlement receipts", "SodiumXT not installed"
      exit heTestReceiptRun
   end if
   set the itemDelimiter to comma
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed1), tPub1, tSec1
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed2), tPub2, tSec2
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed3), tPub3, tSec3

   -- ckpt: a player signs the transcript head; a fork or a wrong signer fails
   heTAssert "ckpt: player signs the chain head", heCkptSigHex(kKatChainHead6, tSec2), kKatCkptSig
   heTAssert "ckpt: verify accepts the signer", \
         heCkptVerify(kKatCkptSig, kKatChainHead6, heBin2HexS(tPub2)), "true"
   heTAssert "ckpt: verify rejects a different signer", \
         heCkptVerify(kKatCkptSig, kKatChainHead6, heBin2HexS(tPub1)), "false"
   heTAssert "ckpt: verify rejects a forked (different) head", \
         heCkptVerify(kKatCkptSig, kKatRcptHead1, heBin2HexS(tPub2)), "false"

   -- 2e: the street ckpt WIRE (spec 6 as-built) -- the body codec and the
   -- three-wire seq 7..9 extension of the KAT transcript, chained exactly
   -- as tools/protocol-kat.py pins them (additive: heads 1..6 untouched)
   heTAssert "ckpt: canonical street-boundary body", \
         heCkptBodyTxt("flop", kKatChainHead6, tSec2), kKatCkptBody
   put heEnvContentLine(kKatTableHex, 1, heBin2HexS(tPub2), "ckpt", kKatCkptBody) into tContent
   put heWireBuild(tContent, tSec2, 7, kKatChainHead6, tSec1) into tWire
   put heChainNextHex(tWire) into tHead
   heTAssert "ckpt: the ckpt wire chains (head 7)", tHead, kKatCkptHead7
   put heEnvContentLine(kKatTableHex, 1, heBin2HexS(tPub2), "show", "seat=2") into tContent
   put heWireBuild(tContent, tSec2, 8, tHead, tSec1) into tWire
   put heChainNextHex(tWire) into tHead
   heTAssert "show: the show wire chains (head 8)", tHead, kKatShowHead8
   put heEnvContentLine(kKatTableHex, 1, heBin2HexS(tPub3), "muck", "seat=3") into tContent
   put heWireBuild(tContent, tSec3, 9, tHead, tSec1) into tWire
   heTAssert "muck: the muck wire chains (head 9)", heChainNextHex(tWire), kKatMuckHead9

   -- settlement receipt chain: hand 1 then hand 2, each receipt chained to the last
   put heSettleHashHex("1:2,2:-1,3:-1", heHex2BinD(kHeGenesisPrev)) into tSh2
   heTAssert "receipt: hand-2 settlement digest", tSh2, kKatSettleHash2
   put heReceiptHeadHex(kKatSettleHash, kHeGenesisPrev) into tRh1
   heTAssert "receipt: hand-1 receipt head (from genesis)", tRh1, kKatRcptHead1
   put heReceiptHeadHex(tSh2, tRh1) into tRh2
   heTAssert "receipt: hand-2 receipt head (chained to hand 1)", tRh2, kKatRcptHead2

   -- all three seated players sign the hand-2 receipt head
   put heReceiptSigHex(tRh2, tSec1) into tSig1
   put heReceiptSigHex(tRh2, tSec2) into tSig2
   put heReceiptSigHex(tRh2, tSec3) into tSig3
   heTAssert "receipt: player 1 signature", tSig1, kKatRcptSig1
   heTAssert "receipt: player 2 signature", tSig2, kKatRcptSig2
   heTAssert "receipt: player 3 signature", tSig3, kKatRcptSig3
   heTAssert "receipt: all three signatures verify (ledger multi-signed)", \
         heReceiptSigVerify(tSig1, tRh2, heBin2HexS(tPub1)) and \
         heReceiptSigVerify(tSig2, tRh2, heBin2HexS(tPub2)) and \
         heReceiptSigVerify(tSig3, tRh2, heBin2HexS(tPub3)), "true"
   -- a signature over the WRONG (rolled-back) head is rejected
   heTAssert "receipt: a signature over a rolled-back head is rejected", \
         heReceiptSigVerify(tSig1, tRh1, heBin2HexS(tPub1)), "false"
   -- a forged co-signer (player 3's sig checked against player 1's key) is rejected
   heTAssert "receipt: a forged co-signer is rejected", \
         heReceiptSigVerify(tSig3, tRh2, heBin2HexS(tPub1)), "false"
end heTestReceiptRun

command heTestLevel2Run
   -- Level 2 mental-poker COMPUTE algebra (spec 7.3, plan 4a-4c): the
   -- on-engine mirror of tools/protocol-kat.py's l2_* twins, which the
   -- file's independent RFC 9496 reference drives -- a green run here plus
   -- the green KAT pins engine, xTalk, and reference to one answer. SKIPs
   -- without SodiumXT, and SKIPs on a pre-ABI-8 build (no sxRistretto*
   -- surface: the first touch throws "can't find handler", the probe's
   -- catch is the detection, and no uncaught engine error can take the run
   -- -- the stMergeCounted lesson). Fixed scalars end to end; the ONLY
   -- fresh randomness is the closing roundtrip, which asserts an identity
   -- law, not a pinned value.
   local tBaseList, tDeck1, tDeck2, tDeck3, tChainTxt, tVal1, tVal2, tVal3
   local tHole0, tHole1, tHole2, tDupList, tBad2, tBad3, tPermBad
   local tTablePt, tRndK, tRndMask, tRndBack
   local tLoopDeck, tLoopPoint, tSrcPos, tCorruptList, tFirstSrc
   put return & "-- 16. Level 2 mental poker: ristretto255 deal algebra (spec 7.3)" & return after gRpt
   if not heHasSodium() then
      heTSkip "level2: ristretto255 deal algebra", "SodiumXT not installed"
      exit heTestLevel2Run
   end if
   if not heL2HasRistretto() then
      heTSkip "level2: ristretto255 deal algebra", "SodiumXT pre-ABI-8 (no sxRistretto* surface)"
      exit heTestLevel2Run
   end if
   set the itemDelimiter to comma
   -- 4a: the public card table, then a three-seat shuffle-mask round
   put heL2BaseDeckHex() into tBaseList
   heTAssert "level2: 52 base points (domain-separated hash-to-group)", tBaseList, kKatL2BaseDeck
   heTAssert "level2: base deck passes the free integrity check", heL2DeckCheckHex(tBaseList), "ok"
   heTAssert "level2: scalar inversion (k1^-1 mod L)", heL2ScalarInvertHex(kKatL2Scalar1), kKatL2Inv1
   put heL2MaskDeckHex(tBaseList, kKatL2Scalar1, kKatL2Perm1) into tDeck1
   heTAssert "level2: seat 1 shuffle-mask step (52 mults + sigma)", tDeck1, kKatL2Deck1
   -- the batch fast path vs the per-point fallback (plan 4f, 2026-08-23):
   -- on ABI 9 the deck call above took ONE sxRistrettoScalarMultBatch
   -- crossing; re-derive the same step through heL2MaskPointHex -- the
   -- fallback, verbatim -- and hold the two byte-for-byte on the fixed
   -- KAT scalars (deterministic end to end, no randomness). Below ABI 9
   -- there is only one path, so the agreement leg SKIPs by name.
   set the itemDelimiter to comma   -- gotcha 5: set before every parse
   if heL2HasDleq() then
      put empty into tLoopDeck
      repeat for each item tSrcPos in kKatL2Perm1
         put heL2MaskPointHex(kKatL2Scalar1, item tSrcPos of tBaseList) into tLoopPoint
         if tLoopDeck is empty then
            put tLoopPoint into tLoopDeck
         else
            put comma & tLoopPoint after tLoopDeck
         end if
      end repeat
      heTAssert "level2: batch fast path and per-point fallback agree byte-for-byte", \
            tLoopDeck, tDeck1
   else
      heTSkip "level2: batch-vs-fallback agreement", \
            "SodiumXT pre-ABI-9 (no batch surface; the per-point loop is the only path)"
   end if
   -- a corrupted point voids on EITHER path: the batch's atomic throw
   -- falls through to the loop, which names the first output position to
   -- meet it (sigma1's first source index), same as a pre-ABI-9 run
   put item 1 of kKatL2Perm1 into tFirstSrc
   put tBaseList into tCorruptList
   put kKatL2BadPoint into item tFirstSrc of tCorruptList
   heTAssert "level2: a corrupted point voids with its output position (both paths)", \
         heL2MaskDeckHex(tCorruptList, kKatL2Scalar1, kKatL2Perm1), "void:invalid-point:1"
   put heL2MaskDeckHex(tDeck1, kKatL2Scalar2, kKatL2Perm2) into tDeck2
   put heL2MaskDeckHex(tDeck2, kKatL2Scalar3, kKatL2Perm3) into tDeck3
   heTAssert "level2: three-seat masked table deck", tDeck3, kKatL2MaskedDeck
   heTAssert "level2: masked table deck all distinct", heL2DeckCheckHex(tDeck3), "ok"
   -- 4b: unmask chains -- a public card, then a hole card owned by seat 2
   put item 1 of tDeck3 into tTablePt
   put heL2MaskPointHex(kKatL2Inv1, tTablePt) into tVal1
   put heL2MaskPointHex(kKatL2Inv2, tVal1) into tVal2
   put heL2MaskPointHex(kKatL2Inv3, tVal2) into tVal3
   put tTablePt & comma & tVal1 & comma & tVal2 & comma & tVal3 into tChainTxt
   heTAssert "level2: public unmask chain values", tChainTxt, kKatL2PublicChain
   heTAssert "level2: public chain resolves to its card", \
         heL2PublicCardHex(tChainTxt, tBaseList), kKatL2PublicCard
   put item 2 of tDeck3 into tHole0
   put heL2MaskPointHex(kKatL2Inv1, tHole0) into tHole1
   put heL2MaskPointHex(kKatL2Inv3, tHole1) into tHole2
   heTAssert "level2: hole chain public part (owner's step absent)", \
         tHole0 & comma & tHole1 & comma & tHole2, kKatL2HoleChain
   heTAssert "level2: penultimate value hits no card (CDH-hidden)", \
         heL2CardOfPointHex(tHole2, tBaseList), 0
   heTAssert "level2: owner strips its mask and resolves the hole", \
         heL2HoleCardHex(kKatL2HoleChain, kKatL2Inv2, tBaseList), kKatL2HoleCard
   -- 4c: showdown -- the revealed (k2, sigma2) re-verifies seat 2's steps
   heTAssert "level2: reveal re-verifies the shuffle step", \
         heL2RevealShuffleHex(tDeck1, tDeck2, kKatL2Scalar2, kKatL2Perm2), "ok"
   heTAssert "level2: reveal re-verifies an unmask step", \
         heL2RevealUnmaskHex(tVal1, tVal2, kKatL2Scalar2), "ok"
   -- the void vocabulary: distinct, attributable refusals (all KAT-pinned)
   put tDeck3 into tDupList
   put item 1 of tDupList into item 2 of tDupList
   heTAssert "level2: duplicate points are publicly refused", \
         heL2DeckCheckHex(tDupList), "void:duplicate-point:1,2"
   heTAssert "level2: a wrong revealed scalar is named", \
         heL2RevealUnmaskHex(tVal1, tVal2, kKatL2Scalar3), "void:unmask-mismatch"
   heTAssert "level2: an invalid encoding mid-chain is named", \
         heL2PublicCardHex(tTablePt & comma & kKatL2BadPoint & comma & tVal2 & comma & tVal3, \
         tBaseList), "void:invalid-point:2"
   -- seat 2 applies the WRONG inverse mid-chain; seat 3 steps honestly
   -- after it -- the chain completes but lands outside the card table
   put heL2MaskPointHex(kKatL2Inv3, tVal1) into tBad2
   put heL2MaskPointHex(kKatL2Inv3, tBad2) into tBad3
   heTAssert "level2: a wrong-scalar chain lands outside the table", \
         heL2PublicCardHex(tTablePt & comma & tVal1 & comma & tBad2 & comma & tBad3, \
         tBaseList), "void:final-not-in-table"
   heTAssert "level2: the identity result is named", \
         heL2MaskPointHex(kKatL2Scalar1, kKatL2Identity), "void:identity-point"
   heTAssert "level2: an invalid mask target is named", \
         heL2MaskPointHex(kKatL2Scalar1, kKatL2BadPoint), "void:invalid-point"
   put kKatL2Perm1 into tPermBad
   put 0 into item 1 of tPermBad
   heTAssert "level2: a malformed permutation is named", \
         heL2MaskDeckHex(tBaseList, kKatL2Scalar1, tPermBad), "void:perm-format:1"
   -- fresh-randomness property (engine-only, deliberately unpinned): mask
   -- with a random scalar, unmask with its inverse, land exactly back
   put heL2ScalarRandomHex() into tRndK
   put heL2MaskPointHex(tRndK, item 3 of tBaseList) into tRndMask
   put heL2MaskPointHex(heL2ScalarInvertHex(tRndK), tRndMask) into tRndBack
   heTAssert "level2: random mask/unmask roundtrip", tRndBack, item 3 of tBaseList
end heTestLevel2Run

command heTestOnionRun
   -- Phase 2f's headless slice: everything an engine can pin WITHOUT a tor
   -- daemon or a second machine -- the invite codec round-trip on both
   -- transports (plus its refusal vectors), the pure heJoinRefusal
   -- downgrade-refusal gate (OnionXT presence is dependency-injected, so
   -- BOTH branches run on any engine), onion-seed derivation properties,
   -- the OnionXT address round-trip when the library is present, and the
   -- "h" hello handshake driven through the REAL message router on netCap
   -- loopback contexts (the netsim mold). The LIVE multi-hand onion table
   -- session is the engine-era exit gate and is SKIPped by name at the end.
   local tInvA, tInviteTxt, tSeedHex1, tSeedHex2, tAddrTxt, tOxErr, tRecovHex
   local tSaved, tHostPub, tHostSec, tPlayPub, tPlaySec, tHostPubHex, tPlayPubHex
   local tTokTxt, tHostTokTxt, tOutbox, tReplyTok
   put return & "-- 17. Onion tables (2f): invite codec + fail-closed + hello" & return after gRpt
   set the itemDelimiter to comma

   -- the invite codec: pure, no dependencies at all
   put heInviteParse(kKatTableHex) into tInvA
   heTAssert "invite: a bare 64-hex code parses as the DHT transport", \
         tInvA["transport"] & "/" & tInvA["table"] & "/" & tInvA["err"], "rp1/" & kKatTableHex & "/"
   put kKatTableHex & "@" & kKatOnionAddr into tInviteTxt
   put heInviteParse(tInviteTxt) into tInvA
   heTAssert "invite: table@address.onion parses as the onion transport", \
         tInvA["transport"] & "/" & tInvA["table"] & "/" & tInvA["onion"] & "/" & tInvA["err"], \
         "onion/" & kKatTableHex & "/" & kKatOnionAddr & "/"
   put heInviteParse(toUpper(tInviteTxt)) into tInvA
   heTAssert "invite: parsing normalizes case (an uppercase paste still binds the table)", \
         tInvA["table"] & "/" & tInvA["onion"], kKatTableHex & "/" & kKatOnionAddr
   -- the downgrade-refusal-BY-FORMAT property: one word, and not bare hex,
   -- so a pre-2f stack's `word 1` + heIsHex gate refuses the WHOLE invite
   heTAssert "invite: an onion invite is one word and NOT bare hex (a pre-2f stack fails closed)", \
         (the number of words of tInviteTxt) & "/" & heIsHex(tInviteTxt, 64), "1/false"
   put heInviteParse("abc123") into tInvA
   heTContains "invite: a short code is refused readably", tInvA["err"], "64 hex"
   put heInviteParse("zz" & char 3 to -1 of kKatTableHex & "@" & kKatOnionAddr) into tInvA
   heTContains "invite: a non-hex table part is refused readably", tInvA["err"], "table code"
   put heInviteParse(kKatTableHex & "@" & "1" & char 2 to -1 of kKatOnionAddr) into tInvA
   heTContains "invite: an address character outside base32 is refused", tInvA["err"], "character"
   put heInviteParse(kKatTableHex & "@" & char 2 to -1 of kKatOnionAddr) into tInvA
   heTContains "invite: a 55-char address core is refused", tInvA["err"], "56"
   put heInviteParse(kKatTableHex & "@" & char 1 to 56 of kKatOnionAddr) into tInvA
   heTContains "invite: a missing .onion suffix is refused", tInvA["err"], ".onion"
   put heInviteParse("") into tInvA
   heTContains "invite: an empty paste is refused readably", tInvA["err"], "Paste"

   -- the join-side fail-closed gate, both branches, on ANY engine (presence
   -- is a parameter -- the H5 shape)
   put heInviteParse(tInviteTxt) into tInvA
   heTContains "refusal: onion invite without OnionXT fails CLOSED (no silent downgrade)", \
         heJoinRefusal(tInvA, false), "OnionXT"
   heTAssert "refusal: onion invite with OnionXT present is admitted to the join path", \
         heJoinRefusal(tInvA, true), empty
   put heInviteParse("not-an-invite") into tInvA
   heTContains "refusal: a malformed invite carries the parser's reason", \
         heJoinRefusal(tInvA, true), "64 hex"

   -- the onion-service seed (spec 10 as-built): deterministic, identity-
   -- keyed, per-table. Needs SodiumXT (it is a domain-separated hash).
   if heHasSodium() then
      put heOnionSeedHex(kKatIdSeed1, kKatTableHex, empty) into tSeedHex1
      put heOnionSeedHex(kKatIdSeed1, kKatTableHex, empty) into tSeedHex2
      heTAssert "onion seed: deterministic (a restarted host re-derives its address)", tSeedHex1, tSeedHex2
      heTAssert "onion seed: 32 bytes of lowercase hex", heIsHex(tSeedHex1, 64), true
      put heOnionSeedHex(kKatIdSeed2, kKatTableHex, empty) into tSeedHex2
      heTAssert "onion seed: keyed by the host identity (another key, another address)", \
            tSeedHex1 is tSeedHex2, false
      put heOnionSeedHex(kKatIdSeed1, kKatSeed1, empty) into tSeedHex2
      heTAssert "onion seed: fresh per table (another table, another address)", \
            tSeedHex1 is tSeedHex2, false
   else
      heTSkip "onion seed: derivation properties", "SodiumXT not installed"
   end if

   -- the address round-trip through OnionXT's pure helpers (no daemon
   -- involved): a REAL checksummed address from a fixed pubkey rides the
   -- invite and decodes back to the same key -- the self-authenticating-
   -- rendezvous property the transport leans on.
   if heHasOnion() and heHasSodium() then
      put empty into tAddrTxt
      try
         put oxAddressFromPublicKey(heHex2BinD(kKatIdPub1)) into tAddrTxt
      catch tOxErr
         put tOxErr into tAddrTxt
      end try
      if tAddrTxt ends with ".onion" then
         heTAssert "onion addr: a v3 address is 62 chars with its .onion", \
               the number of chars of tAddrTxt, 62
         heTAssert "onion addr: OnionXT validates the derived address", \
               oxIsValidAddress(tAddrTxt), true
         put heInviteParse(kKatTableHex & "@" & tAddrTxt) into tInvA
         heTAssert "onion addr: a real derived address rides the invite round-trip", \
               tInvA["onion"] & "/" & tInvA["err"], tAddrTxt & "/"
         put heBin2HexS(oxPublicKeyFromAddress(tAddrTxt)) into tRecovHex
         heTAssert "onion addr: the address IS the pubkey (decode recovers it)", tRecovHex, kKatIdPub1
      else
         heTSkip "onion addr: derive + validate", "needs SodiumXT ABI 7 sxSha3_256 -- " & tAddrTxt
      end if
   else
      heTSkip "onion addr: derive + validate", "OnionXT (or SodiumXT) not loaded"
   end if

   -- the "h" hello handshake through the REAL router, netCap loopback (the
   -- netsim mold): a verified hello admits + replies + replays IN ORDER;
   -- garbage and wrong-table hellos earn nothing; the player adopts the
   -- host from its hello. gGame is swapped and restored (heRunSection's
   -- snapshot backstops a mid-section throw).
   if heHasSodium() then
      put gGame into tSaved
      sxSignKeypairFromSeed heHex2BinD(kKatIdSeed1), tHostPub, tHostSec
      sxSignKeypairFromSeed heHex2BinD(kKatIdSeed2), tPlayPub, tPlaySec
      put heBin2HexS(tHostPub) into tHostPubHex
      put heBin2HexS(tPlayPub) into tPlayPubHex
      -- HOST context with the capture seam on and one cfg wire on the chain
      put empty into gGame
      put "true" into gGame["online"]
      put "true" into gGame["isHost"]
      put tHostPubHex into gGame["idPubHex"]
      put tHostSec into gGame["idSecData"]
      put tHostPubHex into gGame["hostPubHex"]
      put kKatTableHex into gGame["tableIdHex"]
      put 0 into gGame["handNum"]
      put 0 into gGame["seqCounter"]
      put 0 into gGame["syncCooldown"]
      put kHeGenesisPrev into gGame["chainHeadHex"]
      put 0 into gGame["lastSeq"]
      put empty into gGame["wireBuf"]
      put 0 into gGame["wireBufN"]
      put "true" into gGame["netCap"]
      put empty into gGame["netOutbox"]
      put "true" into gGame["admittedA"][tHostPubHex]
      put "host" into gGame["roleByPub"][tHostPubHex]
      heNetSendAction "cfg", kKatLobbyCfgBody
      put empty into gGame["netOutbox"]   -- keep only the handshake's own output
      put textDecode(heAdmitTokenData(kKatTableHex, tPlayPubHex, tPlaySec, "player"), "utf-8") into tTokTxt
      heNetOnMessage 7, textEncode("h" & tab & tTokTxt, "utf-8")
      heTAssert "hello: a verified hello admits the peer", gGame["admittedA"][tPlayPubHex], "true"
      heTAssert "hello: the stream handle becomes the peer handle", gGame["peerPubA"][7], tPlayPubHex
      put gGame["netOutbox"] into tOutbox
      heTAssert "hello: the host answers with its own hello FIRST (ordered stream)", \
            char 1 to 2 of line 1 of tOutbox, "h" & tab
      set the itemDelimiter to tab
      put item 2 to -1 of line 1 of tOutbox into tReplyTok
      set the itemDelimiter to comma
      heTAssert "hello: the reply token verifies and names the host key", \
            heAdmitTokenVerify(textEncode(tReplyTok, "utf-8"), kKatTableHex), tHostPubHex
      heTAssert "hello: the reply token declares role host", \
            heAdmitTokenRole(textEncode(tReplyTok, "utf-8")), "host"
      heTAssert "hello: the r! catch-up marker follows the hello", \
            char 1 to 3 of line 2 of tOutbox, "r!" & tab
      heTContains "hello: the replay carries the signed cfg wire", tOutbox, "w" & tab
      -- an invalid hello earns NOTHING: no admit, no reply, a named drop
      put empty into gGame["netOutbox"]
      heNetOnMessage 9, textEncode("h" & tab & "garbage-token", "utf-8")
      heTAssert "hello: a garbage hello admits nothing", gGame["peerPubA"][9], empty
      heTAssert "hello: a garbage hello earns no reply", gGame["netOutbox"], empty
      heTContains "hello: the drop is named in the net feed", gGame["netLog"], "onion hello failed"
      -- a hello signed for ANOTHER table is a stranger here (the token binds
      -- the table id): refused identically
      put textDecode(heAdmitTokenData(kKatSeed1, tPlayPubHex, tPlaySec, "player"), "utf-8") into tTokTxt
      heNetOnMessage 11, textEncode("h" & tab & tTokTxt, "utf-8")
      heTAssert "hello: a wrong-table hello admits nothing", gGame["peerPubA"][11], empty
      -- PLAYER side: adopting the host from ITS hello over the dialed stream
      put empty into gGame
      put "true" into gGame["online"]
      put "false" into gGame["isHost"]
      put tPlayPubHex into gGame["idPubHex"]
      put tPlaySec into gGame["idSecData"]
      put empty into gGame["hostPubHex"]
      put kKatTableHex into gGame["tableIdHex"]
      put 0 into gGame["syncCooldown"]
      put "true" into gGame["netCap"]
      put empty into gGame["netOutbox"]
      put textDecode(heAdmitTokenData(kKatTableHex, tHostPubHex, tHostSec, "host"), "utf-8") into tHostTokTxt
      heNetOnMessage 3, textEncode("h" & tab & tHostTokTxt, "utf-8")
      heTAssert "hello: the player adopts the host key from the host hello", \
            gGame["hostPubHex"], tHostPubHex
      heTAssert "hello: the host's stream handle is pinned for sends", \
            gGame["peerByPub"][tHostPubHex], 3
      heTAssert "hello: the player answers no hello of its own (no ping-pong)", \
            gGame["netOutbox"], empty
      put tSaved into gGame
   else
      heTSkip "hello handshake loopback", "SodiumXT not installed"
   end if

   -- what only the real world can verify -- say so, by name (the honesty
   -- convention): the exit for 2f is a MULTI-HAND onion table session on
   -- two machines with a running tor daemon, plus the live probe states.
   heTSkip "onion: LIVE multi-hand table session over tor", \
         "two machines + a running tor daemon -- the 2f engine-era exit gate"
end heTestOnionRun

command heTestOracleRun
   -- Phase 3 deck oracle (spec 7.2), as far as a single engine can drive it:
   -- an oracle-hosted table on THREE loopback contexts (oracle + two
   -- players) through the REAL handlers -- the oracle deals sealed holes it
   -- can read but has no stake in, the no-seat invariant holds on every
   -- context, a fold-win hand settles with receipts co-signed by the SEATS
   -- only, the oracle's own entropy commits/reveals at position
   -- dealCount+1, and its audit verdict files as "oracle". Then the oracle
   -- goes SILENT mid-hand-2 and both players independently elect the same
   -- successor and void to the last receipt (spec 9 -- oracle loss IS host
   -- loss). The LIVE three-machine round is the exit gate, SKIPped by name.
   local tSaved, tOrcPub, tOrcSec, tP1Pub, tP1Sec, tP2Pub, tP2Sec
   local tOrcPubHex, tP1PubHex, tP2PubHex, tOrcBoxPub, tOrcBoxSec
   local tP1BoxPub, tP1BoxSec, tP2BoxPub, tP2BoxSec, tBoxErr
   local tStateA, tSbSeat, tBbSeat, tLoop, tElectTxt, tSeedA, tSeedB
   put return & "-- 18. Phase 3 deck oracle: no-seat host + election on oracle loss" & return after gRpt
   set the itemDelimiter to comma
   -- the pure pieces first: seed-domain separation + deterministic election
   if heHasSodium() then
      put heOnionSeedHex(kKatIdSeed1, kKatTableHex, empty) into tSeedA
      heTAssert "oracle: playing-table service seed (2f derivation, pinned)", tSeedA, kKatOnionSeed
      put heOnionSeedHex(kKatIdSeed1, kKatTableHex, "oracle") into tSeedB
      heTAssert "oracle: oracle-table service seed (kHeDomainOracle, pinned)", tSeedB, kKatOracleSeed
      heTAssert "oracle: the two domains never share an address seed", tSeedA is tSeedB, false
   else
      heTSkip "oracle: service-seed domain separation", "SodiumXT not installed"
   end if
   heTAssert "election: heElectHostOf picks the lowest pubkey (pinned)", \
         heElectHostOf(kKatIdPub1 & return & kKatIdPub2), kKatElectedHost
   heTAssert "election: candidate order never matters", \
         heElectHostOf(kKatIdPub2 & return & kKatIdPub1), kKatElectedHost
   if not heHasSodium() then
      heTSkip "oracle: hosted-table loopback + election", "SodiumXT not installed"
      exit heTestOracleRun
   end if
   put gGame into tSaved
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed1), tOrcPub, tOrcSec
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed2), tP1Pub, tP1Sec
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed3), tP2Pub, tP2Sec
   put heBin2HexS(tOrcPub) into tOrcPubHex
   put heBin2HexS(tP1Pub) into tP1PubHex
   put heBin2HexS(tP2Pub) into tP2PubHex
   try
      sxBoxKeypairFromSeed heHash32(textEncode(kHeDomainSess & kKatIdSeed1, "utf-8")), \
            tOrcBoxPub, tOrcBoxSec
      sxBoxKeypairFromSeed heHash32(textEncode(kHeDomainSess & kKatIdSeed2, "utf-8")), \
            tP1BoxPub, tP1BoxSec
      sxBoxKeypairFromSeed heHash32(textEncode(kHeDomainSess & kKatIdSeed3, "utf-8")), \
            tP2BoxPub, tP2BoxSec
      get sxSeal(textEncode("probe", "utf-8"), tOrcBoxPub)
   catch tBoxErr
      put tSaved into gGame
      heTSkip "oracle: hosted-table loopback + election", "SodiumXT box surface not available"
      exit heTestOracleRun
   end try

   -- ORACLE-HOST context: the host role with oracleHost bound, as
   -- heTableCreate binds it; the signed cfg carries level=1
   heTNetPlayCtx "true", tOrcPubHex, tOrcSec, tOrcBoxPub, tOrcBoxSec, tOrcPubHex, kKatIdSeed1
   put "true" into gGame["oracleHost"]
   put "true" into gGame["admittedA"][tOrcPubHex]
   put "true" into gGame["admittedA"][tP1PubHex]
   put "true" into gGame["admittedA"][tP2PubHex]
   put "host" into gGame["roleByPub"][tOrcPubHex]
   put "player" into gGame["roleByPub"][tP1PubHex]
   put "player" into gGame["roleByPub"][tP2PubHex]
   heTAssert "oracle: the signed cfg pins level=1 (the oracle marker)", \
         heLobbyCfgBody(), kKatLobbyCfgBodyOracle
   heNetSendAction "cfg", heLobbyCfgBody()
   heHostEmitRoster
   put gGame into gTNetHostG
   heTNetPlayCtx "false", tP1PubHex, tP1Sec, tP1BoxPub, tP1BoxSec, tOrcPubHex, kKatIdSeed2
   put gGame into gTNetPlayG
   heTNetPlayCtx "false", tP2PubHex, tP2Sec, tP2BoxPub, tP2BoxSec, tOrcPubHex, kKatIdSeed3
   put gGame into gTNetPlay2G
   heTNetPump
   heTAssert "oracle: all three session boxes bound on-chain (the oracle's too)", \
         the number of lines of the keys of gTNetHostG["boxByPub"], 3

   -- Start Game seats ONLY the players; hand 1 deals itself via the react
   -- engines on all three contexts
   put gTNetHostG into gGame
   heNetStartGame
   put gGame into gTNetHostG
   heTNetPump
   heTAssert "oracle: exactly the two players are seated", \
         the number of items of gTNetPlayG["seatedList"], 2
   heTAssert "oracle: the oracle holds NO seat (every view)", \
         gTNetHostG["seatByPub"][tOrcPubHex] & "/" & gTNetPlayG["seatByPub"][tOrcPubHex] \
         & "/" & gTNetPlay2G["seatByPub"][tOrcPubHex], "//"
   heTAssert "oracle: dealLevel names the oracle (level 1, dealer 0)", \
         gTNetPlayG["oDeal"]["oracleDeal"] & "/" & gTNetPlayG["oDeal"]["dealerSeat"], "true/0"
   heTAssert "oracle: three entropy contributors committed (2 seats + oracle)", \
         gTNetPlayG["oDeal"]["commitN"], 3
   put gTNetPlayG["state"] into tStateA
   heTAssert "oracle: hand 1 dealt itself to the action", tStateA["phase"], "acting"
   heTAssert "oracle: both players' sealed holes opened", \
         (gTNetPlayG["oDeal"]["myHoles"] is not empty \
         and gTNetPlay2G["oDeal"]["myHoles"] is not empty), "true"
   heTAssert "oracle: the oracle's own holes stay EMPTY (no seat, no cards)", \
         (gTNetHostG["oDeal"]["myHoles"] is empty), "true"
   heTAssert "oracle: hole deliveries cover exactly the seats", \
         gTNetHostG["oDeal"]["holeN"], 2
   heTAssert "oracle: every context at one chain head", \
         (gTNetPlayG["chainHeadHex"] is gTNetHostG["chainHeadHex"] \
         and gTNetPlay2G["chainHeadHex"] is gTNetHostG["chainHeadHex"]), "true"

   -- hand 1: the SB folds -> deterministic deltas; reveals (incl. the
   -- oracle's pos 3), the verified settle, seat-only receipts, three audits
   put tStateA["sbSeat"] into tSbSeat
   put tStateA["bbSeat"] into tBbSeat
   heTNetOracleAct tSbSeat, "verb=fold,amount=0"
   heTAssert "oracle: hand 1 settled on every context", \
         gTNetPlayG["oDeal"]["settleDone"] & "/" & gTNetPlay2G["oDeal"]["settleDone"] \
         & "/" & gTNetHostG["oDeal"]["settleDone"], "true/true/true"
   heTAssert "oracle: the oracle revealed its own seed (position 3)", \
         (gTNetPlayG["oDeal"]["revealsBy"][3] is not empty), "true"
   heTAssert "oracle: blinds moved only between the seats", \
         gTNetPlayG["stacksBy"][tSbSeat] & "/" & gTNetPlayG["stacksBy"][tBbSeat], "399/401"
   heTAssert "oracle: the oracle banks no stack (no seat in stacksBy)", \
         the number of lines of the keys of gTNetHostG["stacksBy"], 2
   heTContains "oracle: the receipt is co-signed by the SEATS alone", \
         gTNetPlayG["netLog"], "receipt co-signed by all 2"
   heTContains "oracle: seat 1 audits the oracle deal clean", gTNetPlayG["netLog"], "audit  seat 1: pass"
   heTContains "oracle: seat 2 audits the oracle deal clean", gTNetPlayG["netLog"], "audit  seat 2: pass"
   heTContains "oracle: the oracle's own audit files as oracle", \
         gTNetPlayG["netLog"], "audit  oracle: pass"
   heTAssert "oracle: the uncontested winner mucks (display choice)", \
         gTNetPlayG["oDeal"]["showBy"][tBbSeat], "muck"

   -- ELECTION ON ORACLE SILENCE: kick hand 2, reach the action, then the
   -- oracle says nothing more. Each player's watchdog trips independently;
   -- both must name the SAME successor and void to the last receipt.
   put gTNetHostG into gGame
   heNetHandKick
   put gGame into gTNetHostG
   heTNetPump
   put gTNetPlayG["state"] into tStateA
   heTAssert "oracle: hand 2 reached the action before the loss", tStateA["phase"], "acting"
   put heElectHostOf(tP1PubHex & return & tP2PubHex) into tElectTxt
   put gTNetPlayG into gGame
   repeat with tLoop = 1 to kHeHostLossTicks + 1
      heNetHostLossCheck
   end repeat
   put gGame into gTNetPlayG
   put gTNetPlay2G into gGame
   repeat with tLoop = 1 to kHeHostLossTicks + 1
      heNetHostLossCheck
   end repeat
   put gGame into gTNetPlay2G
   heTAssert "election: both clients declare the host lost", \
         gTNetPlayG["hostLost"] & "/" & gTNetPlay2G["hostLost"], "true/true"
   heTAssert "election: both clients name the SAME successor", \
         gTNetPlayG["electedHostPubHex"], gTNetPlay2G["electedHostPubHex"]
   heTAssert "election: the successor is the lowest live seated pubkey", \
         gTNetPlayG["electedHostPubHex"], tElectTxt
   heTAssert "election: the in-flight hand is VOID on both clients", \
         gTNetPlayG["phase"] & "/" & gTNetPlay2G["phase"], "idle/idle"
   heTAssert "election: stacks stand at the last receipt", \
         gTNetPlayG["stacksBy"][tSbSeat] & "/" & gTNetPlayG["stacksBy"][tBbSeat], "399/401"
   heTContains "election: the net feed names the loss and the successor", \
         gTNetPlayG["netLog"], "HOST LOST"

   put empty into gTNetHostG
   put empty into gTNetPlayG
   put empty into gTNetPlay2G
   put tSaved into gGame

   -- what only the real world can verify -- say so, by name (the honesty
   -- convention): Phase 3's exit is a THREE-MACHINE round.
   heTSkip "oracle: LIVE three-machine round (two players + a non-playing oracle)", \
         "the Phase 3 exit gate -- kill the oracle mid-hand, void + resume per spec 9"
   heTSkip "oracle: onion-hosted oracle service (kHeDomainOracle address) over tor", \
         "needs a running tor daemon + a second machine (+ live-tor honesty label)"
end heTestOracleRun

command heTestLevel2VoidRun
   -- Phase 4d void-and-audit + the spec 12.4 adversarial bots + Phase 5
   -- DLEQ: the on-engine mirror of protocol-kat's l2v_*/l0_*/l2_dleq_*
   -- scenario pins. Every bot's verdict string here is the SAME literal
   -- the Python twins pinned from the independent reference, so a green
   -- run pins engine, xTalk, and reference to one attribution answer.
   -- SKIPs without SodiumXT; the machine half SKIPs below ABI 8; the DLEQ
   -- half SKIPs by name below ABI 9 (the sx* DLEQ calls have never run on
   -- an engine -- this section IS their first-contact harness).
   local tSeedsA, tCommitsA, tTableData, tKeyData, tDeckList, tDealA, tStackA
   local tBase, tD1, tD2, tD3, tPipe1, tSh1, tC0, tV1, tV2, tV3
   local tH0, tW1, tW2, tBad2, tBad3, tRevTxt, tStA, tCardTxt, tHoleTxt
   local tDupDeck, tEqDeck, tLastTxt, tProof, tProofBad, tTampered
   local tStB, tStC, tStD
   put return & "-- 19. Level 2 void-and-audit + cheater bots (spec 7.3/12.4, plan 4d/4e; DLEQ 7.4)" & return after gRpt
   if not heHasSodium() then
      heTSkip "level2 void: machine + bots", "SodiumXT not installed"
      exit heTestLevel2VoidRun
   end if
   set the itemDelimiter to comma
   -- bot[deck-stacker], against LEVEL 0 (spec 12.4 lists it there): a
   -- dealer who deals cards the committed stream never produced, and one
   -- who re-chooses its seed after seeing the others -- the spec 7.1
   -- step 5 audit names each (pinned: l0_stacker_holes/l0_stacker_commit)
   put kKatSeed1 into tSeedsA[1]
   put kKatSeed2 into tSeedsA[2]
   put kKatSeed3 into tSeedsA[3]
   put heSeedCommitHex(kKatSeed1) into tCommitsA[1]
   put heSeedCommitHex(kKatSeed2) into tCommitsA[2]
   put heSeedCommitHex(kKatSeed3) into tCommitsA[3]
   put heHex2BinD(kKatTableHex) into tTableData
   put heStreamKeyData(tTableData, 1, kKatSeedsXor) into tKeyData
   put heDeckFromStreamKey(tKeyData) into tDeckList
   put heDealAssign(tDeckList, "1,2,3", 1) into tDealA
   put tDealA into tStackA
   put tDealA["holesBy"][2] into tStackA["holesBy"][1]
   put tDealA["holesBy"][1] into tStackA["holesBy"][2]
   heTAssert "bot[deck-stacker]: a stacked delivery is named (L0 audit)", \
         heAuditDeal(tTableData, 1, tSeedsA, tCommitsA, 3, tStackA, "1,2,3", 1), \
         "fail:hole-mismatch-seat-1"
   put kKatCommit2 into tCommitsA[1]
   heTAssert "bot[deck-stacker]: a re-chosen seed breaks its commit", \
         heAuditDeal(tTableData, 1, tSeedsA, tCommitsA, 3, tDealA, "1,2,3", 1), \
         "fail:commit-mismatch-position-1"
   if not heL2HasRistretto() then
      heTSkip "level2 void: machine + bots", "SodiumXT pre-ABI-8 (no sxRistretto* surface)"
      exit heTestLevel2VoidRun
   end if
   -- fixtures: the pinned base deck, the three-seat masked decks, and the
   -- pinned chain values (same constants section 16 verifies)
   put heL2BaseDeckHex() into tBase
   put heL2MaskDeckHex(tBase, kKatL2Scalar1, kKatL2Perm1) into tD1
   put heL2MaskDeckHex(tD1, kKatL2Scalar2, kKatL2Perm2) into tD2
   put heL2MaskDeckHex(tD2, kKatL2Scalar3, kKatL2Perm3) into tD3
   put item 1 of tD3 into tC0
   put heL2MaskPointHex(kKatL2Inv1, tC0) into tV1
   put heL2MaskPointHex(kKatL2Inv2, tV1) into tV2
   put heL2MaskPointHex(kKatL2Inv3, tV2) into tV3
   put item 2 of tD3 into tH0
   put heL2MaskPointHex(kKatL2Inv1, tH0) into tW1
   put heL2MaskPointHex(kKatL2Inv3, tW1) into tW2
   put "1" & tab & kKatL2Scalar1 & tab & kKatL2Perm1 & return & \
         "2" & tab & kKatL2Scalar2 & tab & kKatL2Perm2 & return & \
         "3" & tab & kKatL2Scalar3 & tab & kKatL2Perm3 into tRevTxt
   -- the PINNED record formats (spec 6 body conventions)
   put tD1 into tPipe1
   replace comma with "|" in tPipe1
   put heL2ShuffleBodyOf(1, empty, tD1) into tSh1
   heTAssert "4d: shuffleStep record format (pinned)", tSh1, \
         "pos=1,ck=,deck=" & tPipe1
   heTAssert "4d: unmaskStep record format (pinned)", \
         heL2UnmaskBodyOf(1, 1, tV1, empty), \
         "pos=1,slot=1,val=" & tV1 & ",proof="
   -- the honest table: shuffle -> deal, a public slot resolves its card, a
   -- hole slot completes without its owner's step, the audit comes back
   -- clean (a clean audit is the table agreeing to void)
   put heL2VoidNew(3, tBase, false, "2:2") into tStA
   put heL2VoidShuffle(tStA, 1, tSh1) into tStA
   put heL2VoidShuffle(tStA, 2, heL2ShuffleBodyOf(2, empty, tD2)) into tStA
   put heL2VoidShuffle(tStA, 3, heL2ShuffleBodyOf(3, empty, tD3)) into tStA
   heTAssert "4d: three honest shuffle steps reach the deal phase", \
         heL2VoidOutcome(tStA), "deal"
   put heL2VoidUnmask(tStA, 1, heL2UnmaskBodyOf(1, 1, tV1, empty)) into tStA
   put heL2VoidUnmask(tStA, 2, heL2UnmaskBodyOf(2, 1, tV2, empty)) into tStA
   put heL2VoidUnmask(tStA, 3, heL2UnmaskBodyOf(3, 1, tV3, empty)) into tStA
   put tStA["card"][1] into tCardTxt
   heTAssert "4d: a completed public chain resolves its card", tCardTxt, kKatL2PublicCard
   put heL2VoidUnmask(tStA, 1, heL2UnmaskBodyOf(1, 2, tW1, empty)) into tStA
   put heL2VoidUnmask(tStA, 3, heL2UnmaskBodyOf(3, 2, tW2, empty)) into tStA
   put tStA["holeUp"][2] into tHoleTxt
   heTAssert "4d: the hole chain completes without the owner's step", tHoleTxt, "true"
   heTAssert "4d: the honest table never voids", heL2VoidOutcome(tStA), "deal"
   heTAssert "4d: a clean audit names nobody", heL2VoidAudit(tStA, tRevTxt), \
         "named=0|audit-clean"
   -- bot[duplicate-point shuffler]: the free integrity check refuses the
   -- posted deck at once -- named directly, no audit needed
   put heL2VoidNew(3, tBase, false, empty) into tStA
   put heL2VoidShuffle(tStA, 1, tSh1) into tStA
   put tD2 into tDupDeck
   put item 1 of tDupDeck into item 2 of tDupDeck
   put heL2VoidShuffle(tStA, 2, heL2ShuffleBodyOf(2, empty, tDupDeck)) into tStA
   heTAssert "bot[duplicate-point shuffler]: refused at post time, named", \
         heL2VoidOutcome(tStA), \
         "void|void:duplicate-point:1,2|named=2|bets-return|reveal-required"
   -- bot[rollback replayer]: an identical re-post is a harmless dup (the
   -- state does not move -- rp1 redelivers); a DIFFERENT re-post for the
   -- applied position is signed equivocation, named directly
   put heL2VoidNew(3, tBase, false, empty) into tStA
   put heL2VoidShuffle(tStA, 1, tSh1) into tStA
   put heL2VoidShuffle(tStA, 2, heL2ShuffleBodyOf(2, empty, tD2)) into tStA
   put heL2VoidShuffle(tStA, 1, tSh1) into tStA
   put tStA["last"] & comma & tStA["applied"] into tLastTxt
   heTAssert "bot[rollback replayer]: an identical re-post is a harmless dup", \
         tLastTxt, "dup,2"
   put tD1 into tEqDeck
   put item 2 of tD1 into item 1 of tEqDeck
   put item 1 of tD1 into item 2 of tEqDeck
   put heL2VoidShuffle(tStA, 1, heL2ShuffleBodyOf(1, empty, tEqDeck)) into tStA
   heTAssert "bot[rollback replayer]: a DIFFERENT re-post is equivocation, named", \
         heL2VoidOutcome(tStA), \
         "void|void:step-equivocation:1|named=1|bets-return|reveal-required"
   -- bot[wrong-scalar unmasker], no DLEQ: every step individually
   -- well-formed, the chain completes OUTSIDE the table -> deferred
   -- attribution, and the mandatory reveal audit names seat 2's step
   put heL2VoidNew(3, tBase, false, empty) into tStA
   put heL2VoidShuffle(tStA, 1, tSh1) into tStA
   put heL2VoidShuffle(tStA, 2, heL2ShuffleBodyOf(2, empty, tD2)) into tStA
   put heL2VoidShuffle(tStA, 3, heL2ShuffleBodyOf(3, empty, tD3)) into tStA
   put heL2MaskPointHex(kKatL2Inv3, tV1) into tBad2
   put heL2MaskPointHex(kKatL2Inv3, tBad2) into tBad3
   put heL2VoidUnmask(tStA, 1, heL2UnmaskBodyOf(1, 1, tV1, empty)) into tStA
   put heL2VoidUnmask(tStA, 2, heL2UnmaskBodyOf(2, 1, tBad2, empty)) into tStA
   put heL2VoidUnmask(tStA, 3, heL2UnmaskBodyOf(3, 1, tBad3, empty)) into tStA
   heTAssert "bot[wrong-scalar unmasker]: chain lands outside the table -> audit", \
         heL2VoidOutcome(tStA), \
         "void|void:final-not-in-table:1|named=audit|bets-return|reveal-required"
   heTAssert "bot[wrong-scalar unmasker]: the reveal audit names seat 2's step", \
         heL2VoidAudit(tStA, tRevTxt), "named=2|void:unmask-mismatch:1:2"
   -- bot[deal staller]: provisionally named on the timeout; the audit
   -- re-verifies everything signed and keeps the staller's name
   put heL2VoidNew(3, tBase, false, empty) into tStA
   put heL2VoidShuffle(tStA, 1, tSh1) into tStA
   put heL2VoidShuffle(tStA, 2, heL2ShuffleBodyOf(2, empty, tD2)) into tStA
   put heL2VoidShuffle(tStA, 3, heL2ShuffleBodyOf(3, empty, tD3)) into tStA
   put heL2VoidUnmask(tStA, 1, heL2UnmaskBodyOf(1, 1, tV1, empty)) into tStA
   put heL2VoidTimeout(tStA, 2) into tStA
   heTAssert "bot[deal staller]: the timeout voids with the ower named", \
         heL2VoidOutcome(tStA), \
         "void|void:deal-timeout:2|named=2|bets-return|reveal-required"
   heTAssert "bot[deal staller]: the audit re-verifies all, keeps the name", \
         heL2VoidAudit(tStA, tRevTxt), "named=2|void:deal-timeout:2"
   -- Phase 5 DLEQ, behind its own probe: on a pre-ABI-9 SodiumXT the whole
   -- half SKIPs by name and the 4d machine above still ran on ABI 8
   if not heL2HasDleq() then
      heTSkip "phase5: DLEQ proofs + machine wiring", \
            "SodiumXT pre-ABI-9 (no DLEQ/batch surface)"
      exit heTestLevel2VoidRun
   end if
   heTAssert "dleq: commitment key ck1 = k1*B (pinned)", \
         heL2CommitKeyHex(kKatL2Scalar1), kKatL2Ck1
   heTAssert "dleq: commitment key ck2 = k2*B (pinned)", \
         heL2CommitKeyHex(kKatL2Scalar2), kKatL2Ck2
   put heL2DleqProve(kKatL2Scalar1, tV1, tC0) into tProof
   heTAssert "dleq: derandomized proof matches the reference (pinned)", \
         tProof, kKatL2DleqProof
   heTAssert "dleq: the honest proof verifies", \
         heL2DleqVerify(kKatL2Ck1, tV1, tC0, tProof), "ok"
   -- soundness, negatively: the honest PROCEDURE over a FALSE statement
   -- (the wrong-scalar unmasker's only available forgery) fails equation
   -- 2; a wrong secret, swapped points, and a tampered commitment all
   -- change the transcript and fail equation 1
   heTAssert "dleq: honest procedure over a FALSE statement fails (eq 2)", \
         heL2DleqVerify(kKatL2Ck2, tBad2, tV1, \
         heL2DleqProve(kKatL2Scalar2, tBad2, tV1)), "void:dleq-mismatch:2"
   heTAssert "dleq: a wrong secret cannot forge (eq 1)", \
         heL2DleqVerify(kKatL2Ck2, tV2, tV1, \
         heL2DleqProve(kKatL2Scalar3, tV2, tV1)), "void:dleq-mismatch:1"
   heTAssert "dleq: swapped points refuse", \
         heL2DleqVerify(kKatL2Ck1, tC0, tV1, tProof), "void:dleq-mismatch:1"
   put tV3 & char 65 to 192 of tProof into tTampered
   heTAssert "dleq: a tampered commitment changes the challenge", \
         heL2DleqVerify(kKatL2Ck1, tV1, tC0, tTampered), "void:dleq-mismatch:1"
   -- the proof wired into the unmaskStep record (spec 7.4's reserved
   -- field): on a dleq=1 machine an honest proof-carrying step applies,
   -- the wrong-scalar unmasker is refused INSTANTLY with direct
   -- attribution (no audit round -- "impossible rather than
   -- attributable"), and a missing proof is itself a named refusal
   put heL2VoidNew(3, tBase, true, "2:2") into tStB
   put heL2VoidShuffle(tStB, 1, heL2ShuffleBodyOf(1, kKatL2Ck1, tD1)) into tStB
   put heL2VoidShuffle(tStB, 2, heL2ShuffleBodyOf(2, kKatL2Ck2, tD2)) into tStB
   put heL2VoidShuffle(tStB, 3, heL2ShuffleBodyOf(3, kKatL2Ck3, tD3)) into tStB
   put heL2VoidUnmask(tStB, 1, heL2UnmaskBodyOf(1, 1, tV1, tProof)) into tStB
   put tStB["last"] into tLastTxt
   heTAssert "phase5: a proof-carrying honest step applies", tLastTxt, "applied"
   put heL2DleqProve(kKatL2Scalar2, tBad2, tV1) into tProofBad
   put heL2VoidUnmask(tStB, 2, heL2UnmaskBodyOf(2, 1, tBad2, tProofBad)) into tStB
   heTAssert "phase5: a wrong unmask is refused INSTANTLY, named -- no audit round", \
         heL2VoidOutcome(tStB), \
         "void|void:dleq-mismatch:2:1|named=2|bets-return|reveal-required"
   put heL2VoidNew(3, tBase, true, empty) into tStC
   put heL2VoidShuffle(tStC, 1, heL2ShuffleBodyOf(1, kKatL2Ck1, tD1)) into tStC
   put heL2VoidShuffle(tStC, 2, heL2ShuffleBodyOf(2, kKatL2Ck2, tD2)) into tStC
   put heL2VoidShuffle(tStC, 3, heL2ShuffleBodyOf(3, kKatL2Ck3, tD3)) into tStC
   put heL2VoidUnmask(tStC, 1, heL2UnmaskBodyOf(1, 1, tV1, empty)) into tStC
   heTAssert "phase5: a missing proof on a dleq table is itself named", \
         heL2VoidOutcome(tStC), \
         "void|void:proof-missing:1|named=1|bets-return|reveal-required"
   -- a lying commitment key (posted ck3, masked with k1) is caught by the
   -- audit's binding check, before any chain algebra runs
   put heL2VoidNew(3, tBase, true, empty) into tStD
   put heL2VoidShuffle(tStD, 1, heL2ShuffleBodyOf(1, kKatL2Ck3, tD1)) into tStD
   put heL2VoidShuffle(tStD, 2, heL2ShuffleBodyOf(2, kKatL2Ck2, tD2)) into tStD
   put heL2VoidShuffle(tStD, 3, heL2ShuffleBodyOf(3, kKatL2Ck3, tD3)) into tStD
   heTAssert "phase5: a lying commitment key is caught by the audit binding", \
         heL2VoidAudit(tStD, tRevTxt), "named=1|void:audit-ck-mismatch"
end heTestLevel2VoidRun

command heTestLivenessRun
   -- 2e liveness (spec 8.1/9): act timers + the per-hand time-bank,
   -- sit-out/return, late-join seating, and the onion auto-redial's
   -- ordering against the election watchdog. The pure prescriptions and
   -- the redial schedule run on ANY engine; the wire pins and the timed
   -- netsim hand need SodiumXT (+ its box surface); the LIVE legs -- a
   -- timed two-machine table on wall clocks, a real tor-stream loss --
   -- are SKIPped by name at the end (the honesty convention).
   local tSaved, tHostPub, tHostSec, tPlayPub, tPlaySec, tHostPubHex, tPlayPubHex
   local tHostBoxPub, tHostBoxSec, tPlayBoxPub, tPlayBoxSec, tBoxErr
   local tP3Pub, tP3Sec, tP3PubHex, tP3BoxPub, tP3BoxSec
   local tStateA, tSeat, tSeatX, tSeatY, tOwe, tVerb, tStep, tLoop
   local tContent, tWire, tHead, tTokTxt, tFrameTxt, tListTxt, tKeyA, tKeyB
   local tEvil, tEvilC, tSnapG, tHandBefore, tOutboxTxt, tWireN, tLineTxt
   local tSnapH, tBodyA, tSeatOther, tOtherPub, tOtherSec, tGhostPub, tLivePub
   put return & "-- 20. Liveness: act timers + time-bank, sit-out, late-join, redial" & return after gRpt
   set the itemDelimiter to comma

   -- the seat plate's label PRIORITY, pure (v0.24.0, F9). The countdown used
   -- to be tested before the sit-out label, so a sitting-out seat whose turn
   -- came up showed "0s" -- and 0 is precisely what heNetTurnLimitSecs returns
   -- for a sitting-out seat, so the plate rendered the reason for the label
   -- instead of the label. These four lines are the only ones in the pure half
   -- that touch the live store, so they snapshot and restore it.
   put gGame into tSaved
   put "true" into gGame["online"]
   put empty into gGame["sitOutBy"]
   put "12s" into gGame["turnClockTxt"]
   heTAssert "plate: an acting seat shows its countdown", \
         heSeatFaceLabel(1, true, "false", "false"), "12s"
   put "true" into gGame["sitOutBy"][1]
   heTAssert "plate: SIT OUT outranks the countdown on the acting seat", \
         heSeatFaceLabel(1, true, "false", "false"), "SIT OUT"
   heTAssert "plate: the engine's folded verdict outranks both", \
         heSeatFaceLabel(1, true, "true", "false"), "FOLDED"
   heTAssert "plate: all-in outranks the countdown too", \
         heSeatFaceLabel(1, true, "false", "true"), "ALL-IN"
   put tSaved into gGame

   -- the spec 9 expiry prescription, pure: check when nothing is owed,
   -- else fold (a host may never fold a seat that could check)
   put heTBlinds(heTNewHand(1, 2, "400,400,400", "1,2,3", 1)) into tStateA
   heTAssert "timer: an owing seat's expiry prescription is fold", \
         heTimeoutVerbOf(tStateA, tStateA["toAct"]), "fold"
   heTAssert "timer: the big blind's expiry prescription is check", \
         heTimeoutVerbOf(tStateA, tStateA["bbSeat"]), "check"
   -- the pending-forced-post prescription (blinds phase, engine amounts)
   put heTNewHand(1, 2, "400,400", "1,2", 1) into tStateA
   heTAssert "timer: the pending post names the SB first (engine amount)", \
         heTimeoutPostOf(tStateA), "bidSB,1,1"
   put heBetApply(tStateA, "bidSB", tStateA["sbSeat"], 1) into tStateA
   heTAssert "timer: then the BB at the engine's amount", \
         heTimeoutPostOf(tStateA), "bidBB,2,2"
   put heTNewHandAnte(1, 2, 1, "400,400,400", "1,2,3", 1) into tStateA
   heTAssert "timer: antes precede the blinds (lowest unposted seat)", \
         heTimeoutPostOf(tStateA), "bidAnte,1,1"
   put heTBlinds(heTNewHand(1, 2, "400,400", "1,2", 1)) into tStateA
   heTAssert "timer: no pending post once the betting opens", \
         heTimeoutPostOf(tStateA), empty
   -- the redial backoff schedule, pure and bounded (2/4/8/16 s in ticks;
   -- kHeRedialMax attempts -- the watchdog always concludes)
   put heRedialWaitTicks(1) & comma & heRedialWaitTicks(2) & comma \
         & heRedialWaitTicks(3) & comma & heRedialWaitTicks(4) into tListTxt
   heTAssert "redial: doubling backoff 8/16/32/64 poll ticks", tListTxt, "8,16,32,64"

   -- the ELECTION'S CANDIDATE SET, pure. heNetHostLost is driven twice below
   -- (and once in section 18), but both of those only ever assert that SOME
   -- successor was named -- so the filter inside heNetElectablePubs was
   -- invisible to a fully green run, which is how it shipped electing seats
   -- that are sitting out. Spec 9 elects among LIVE SEATED players: a sat-out
   -- seat is dealt out at every boundary and times out instantly, so handing
   -- it the table is a table death every client agrees on. Three seats, the
   -- lowest key sat out; the successor must move UP to the next key. Reads
   -- the live store, so it snapshots and restores it (the plate block above).
   put gGame into tSaved
   put "1,2,3" into gGame["seatedList"]
   put empty into gGame["sitOutBy"]
   put empty into gGame["stacksBy"]
   put empty into gGame["pubBySeat"]
   put 400 into gGame["stacksBy"][1]
   put 400 into gGame["stacksBy"][2]
   put 400 into gGame["stacksBy"][3]
   put kKatIdPub1 into gGame["pubBySeat"][1]
   put kKatIdPub2 into gGame["pubBySeat"][2]
   put kKatIdPub3 into gGame["pubBySeat"][3]
   put empty into gGame["hostPubHex"]   -- an ORACLE host: never seated, so nothing to exclude
   heTAssert "election: all three seats live elects the lowest key", \
         heElectHostOf(heNetElectablePubs()), kKatElectedHost
   put "true" into gGame["sitOutBy"][2]
   heTAssert "election: a SITTING-OUT seat is not electable (spec 9 live seats)", \
         heElectHostOf(heNetElectablePubs()), kKatElectedHostSitOut
   heTAssert "election: the sat-out key is gone from the candidate set entirely", \
         (heNetElectablePubs() contains kKatIdPub2), "false"
   -- the two filters it already had, re-pinned through the shared scan so a
   -- later edit cannot trade one for the other. Seat 2 is still sitting out
   -- here, so busting seat 3 leaves seat 1 as the only candidate and the
   -- successor moves again -- a filter that stopped working would leave the
   -- previous winner standing and this line would catch it.
   put 0 into gGame["stacksBy"][3]
   heTAssert "election: a busted seat is not electable either", \
         heElectHostOf(heNetElectablePubs()), kKatIdPub1
   put 400 into gGame["stacksBy"][3]
   put empty into gGame["sitOutBy"]
   put kKatIdPub2 into gGame["hostPubHex"]
   heTAssert "election: the lost host never elects itself", \
         heElectHostOf(heNetElectablePubs()), kKatElectedHostSitOut
   put tSaved into gGame

   if not heHasSodium() then
      heTSkip "liveness: wire pins + timed netsim hand", "SodiumXT not installed"
      heTSkip "liveness: LIVE timed table (two machines, wall clocks)", \
            "the 2e engine-era exit leg"
      heTSkip "redial: LIVE tor host-stream loss + redial", \
            "needs a running tor daemon + a second machine"
      exit heTestLivenessRun
   end if

   -- the seq 10..13 wire-format pins (protocol-kat's transcript extension)
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed1), tHostPub, tHostSec
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed2), tPlayPub, tPlaySec
   put heBin2HexS(tHostPub) into tHostPubHex
   put heBin2HexS(tPlayPub) into tPlayPubHex
   put heEnvContentLine(kKatTableHex, 1, tHostPubHex, "act", kKatTimeoutBody) into tContent
   put heWireBuild(tContent, tHostSec, 10, kKatMuckHead9, tHostSec) into tWire
   put heChainNextHex(tWire) into tHead
   heTAssert "timeout: the host timeout act chains (head 10)", tHead, kKatTimeoutHead10
   put heEnvContentLine(kKatTableHex, 1, tPlayPubHex, "stand", "seat=2") into tContent
   put heWireBuild(tContent, tPlaySec, 11, tHead, tHostSec) into tWire
   put heChainNextHex(tWire) into tHead
   heTAssert "stand: the sit-out wire chains (head 11)", tHead, kKatStandHead11
   put heEnvContentLine(kKatTableHex, 1, tPlayPubHex, "sit", "seat=2") into tContent
   put heWireBuild(tContent, tPlaySec, 12, tHead, tHostSec) into tWire
   put heChainNextHex(tWire) into tHead
   heTAssert "sit: the return wire chains (head 12)", tHead, kKatSitBackHead12
   put heEnvContentLine(kKatTableHex, 1, tHostPubHex, "bidBB", kKatTimeoutBidBody) into tContent
   put heWireBuild(tContent, tHostSec, 13, tHead, tHostSec) into tWire
   heTAssert "timeout: the host timeout bid chains (head 13)", \
         heChainNextHex(tWire), kKatTimeoutBidHead13
   -- the onion hello's trailing-seq trim frame: byte-pinned, and the extra
   -- item must not disturb the token's verification (old-host compatible)
   put textDecode(heAdmitTokenData(kKatTableHex, tPlayPubHex, tPlaySec, "player"), "utf-8") into tTokTxt
   put "h" & tab & tTokTxt & tab & 42 into tFrameTxt
   heTAssert "hello: the trim frame is byte-pinned", \
         heBin2HexS(textEncode(tFrameTxt, "utf-8")), kKatHelloTrimHex
   heTAssert "hello: the trailing seq does not disturb verification", \
         heAdmitTokenVerify(textEncode(tTokTxt & tab & 42, "utf-8"), kKatTableHex), tPlayPubHex

   try
      sxBoxKeypairFromSeed heHash32(textEncode(kHeDomainSess & kKatIdSeed1, "utf-8")), \
            tHostBoxPub, tHostBoxSec
      sxBoxKeypairFromSeed heHash32(textEncode(kHeDomainSess & kKatIdSeed2, "utf-8")), \
            tPlayBoxPub, tPlayBoxSec
      sxBoxKeypairFromSeed heHash32(textEncode(kHeDomainSess & kKatIdSeed3, "utf-8")), \
            tP3BoxPub, tP3BoxSec
      get sxSeal(textEncode("probe", "utf-8"), tHostBoxPub)
   catch tBoxErr
      heTSkip "liveness: timed netsim hand", "SodiumXT box surface not available"
      heTSkip "liveness: LIVE timed table (two machines, wall clocks)", \
            "the 2e engine-era exit leg"
      heTSkip "redial: LIVE tor host-stream loss + redial", \
            "needs a running tor daemon + a second machine"
      exit heTestLivenessRun
   end try
   sxSignKeypairFromSeed heHex2BinD(kKatIdSeed3), tP3Pub, tP3Sec
   put heBin2HexS(tP3Pub) into tP3PubHex
   put gGame into tSaved
   put empty into gTNetPlay2G

   -- ===== the timed netsim hand: host + player through the real handlers
   heTNetPlayCtx "true", tHostPubHex, tHostSec, tHostBoxPub, tHostBoxSec, tHostPubHex, kKatIdSeed1
   put "true" into gGame["admittedA"][tHostPubHex]
   put "true" into gGame["admittedA"][tPlayPubHex]
   put "host" into gGame["roleByPub"][tHostPubHex]
   put "player" into gGame["roleByPub"][tPlayPubHex]
   heNetSendAction "cfg", heLobbyCfgBody()
   heHostEmitRoster
   put gGame into gTNetHostG
   heTNetPlayCtx "false", tPlayPubHex, tPlaySec, tPlayBoxPub, tPlayBoxSec, tHostPubHex, kKatIdSeed2
   put gGame into gTNetPlayG
   heTNetPump
   put gTNetPlayG into gGame
   heTAssert "cfg: the signed cfg carries the timer lengths (act/bank/miss)", \
         heNetCfgVal("act", 0) & "/" & heNetCfgVal("bank", 0) & "/" & heNetCfgVal("miss", 0), \
         kHeDefaultActSecs & "/" & kHeDefaultBankSecs & "/" & kHeDefaultMisses
   put gGame into gTNetPlayG
   put gTNetHostG into gGame
   heNetStartGame
   put gGame into gTNetHostG
   heTNetPump
   put gTNetPlayG["state"] into tStateA
   heTAssert "timer: hand 1 dealt itself to the action", tStateA["phase"], "acting"
   put tStateA["toAct"] into tSeatX
   -- copy the turn keys out before chunking them (H6), and re-set the
   -- delimiter after the pump (gotcha 5)
   set the itemDelimiter to comma
   put gTNetPlayG["turnKey"] into tKeyA
   put gTNetHostG["turnKey"] into tKeyB
   heTAssert "timer: the turn mark aims at the acting seat (both sides)", \
         item 2 of tKeyA & "/" & item 2 of tKeyB, tSeatX & "/" & tSeatX

   -- a PREMATURE forged host timeout is refused by the player's own clock
   -- (throwaway copy; the honest stream never sees the poisoned chain)
   put gTNetPlayG into tSnapG
   put gTNetPlayG into gGame
   put heTimeoutVerbOf(gGame["state"], tSeatX) into tVerb
   put heEnvContentLine(kKatTableHex, gGame["handNum"], tHostPubHex, "act", \
         "verb=" & tVerb & ",amount=0,seat=" & tSeatX & ",timeout=1,bank=1") into tEvilC
   put heWireBuild(tEvilC, tHostSec, gGame["lastSeq"] + 1, gGame["chainHeadHex"], tHostSec) into tEvil
   heNetIngestWire tEvil
   heTContains "timer: a premature host timeout is refused + named", \
         gGame["netLog"], "TIMEOUT-REFUSED"
   heTAssert "timer: the refused timeout moved no action", gGame["state"]["toAct"], tSeatX
   put tSnapG into gTNetPlayG

   -- CATCH-UP CLOCKS (v0.24.0, F2). A client that learns of the turn from a
   -- REPLAY starts its clock now, for a turn that opened minutes ago
   -- everywhere else; the host's live timeout then arrives PAST the replay's
   -- announced head, so the seq-keyed waiver cannot fire, and the old code
   -- refused it as premature -- leaving that client one action behind for the
   -- rest of the session with nothing on the chain to say so. The waiver keys
   -- on the CLOCK now, and dies with its turn.
   put gTNetPlayG into gGame
   put empty into tBodyA
   put heTimeoutVerbOf(gGame["state"], tSeatX) into tBodyA["verb"]
   put "1" into tBodyA["bank"]
   -- ...and a marker for a head we already hold is not a catch-up at all: it
   -- would suspend react until the next live wire and mark THAT wire's turn
   -- clock replayed, waiving one deadline check for nothing.
   heTNetDeliver "r!" & tab & gGame["lastSeq"]
   heTAssert "catchup: a marker for a head we already hold does not suspend", \
         (gGame["catchUpTo"] is a number), "false"
   put gGame["lastSeq"] + 3 into gGame["catchUpTo"]   -- a replay is streaming
   put empty into gGame["turnKey"]                    -- so the next mark restarts
   heNetTurnMark
   heTAssert "catchup: a turn clock started during a replay is marked replayed", \
         gGame["turnStale"], "true"
   put empty into gGame["catchUpTo"]   -- the replay completed (react clears it)
   heTAssert "catchup: the live timeout past the replay is waived, not refused", \
         heNetTimeoutOk(tBodyA, tSeatX, "act", 0), empty
   put empty into gGame["turnKey"]
   heNetTurnMark                       -- a LIVE mark: the waiver must not survive
   heTAssert "catchup: the waiver dies with its turn (the next turn is policed)", \
         (heNetTimeoutOk(tBodyA, tSeatX, "act", 0) is not empty), "true"
   put tSnapG into gTNetPlayG

   -- AN ENGINE-REFUSED TIMEOUT (v0.24.0, F3 + F4). Forge a host timeout for
   -- the seat that is NOT to act: it passes every verification (right
   -- prescription for that seat, bank unspent, deadline genuinely passed on a
   -- backdated clock) and then heBetApply refuses it as out of turn. Nothing
   -- consensus may move on that: the seat keeps its one per-hand time-bank and
   -- its miss count, and the host's timeoutSent latch -- which only
   -- heNetTurnMark ever cleared, and heNetTurnMark does not run for a refused
   -- fold -- must not stay stuck, or the host never re-emits and the table
   -- stalls silently for the rest of the hand.
   put gTNetPlayG into gGame
   put empty into gGame["catchUpTo"]
   put "false" into gGame["turnStale"]
   put 3 - tSeatX into tSeatOther      -- heads-up: the seats are 1 and 2
   put 1 into gGame["missCntBy"][tSeatOther]
   put "true" into gGame["timeoutSent"]   -- as the emitting host would hold it
   put gGame["turnStartMs"] - ((kHeDefaultActSecs + kHeDefaultBankSecs + 1) * 1000) \
         into gGame["turnStartMs"]
   put heTimeoutVerbOf(gGame["state"], tSeatOther) into tVerb
   put heEnvContentLine(kKatTableHex, gGame["handNum"], tHostPubHex, "act", \
         "verb=" & tVerb & ",amount=0,seat=" & tSeatOther & ",timeout=1,bank=1") into tEvilC
   put heWireBuild(tEvilC, tHostSec, gGame["lastSeq"] + 1, gGame["chainHeadHex"], tHostSec) into tEvil
   heNetIngestWire tEvil
   heTContains "refused: an engine-rejected timeout is named in the feed", \
         gGame["netLog"], "engine refused that timeout"
   heTAssert "refused: it spends no time-bank and counts no miss", \
         gGame["oDeal"]["bankUsedBy"][tSeatOther] & "/" & gGame["missCntBy"][tSeatOther], "/1"
   heTAssert "refused: the timeout latch is cleared, so the host re-emits", \
         gGame["timeoutSent"], "false"
   -- ...and the twin on the LIVE path (F5): an out-of-turn act the engine
   -- throws away must not reset the seat's miss count, or a stalling client
   -- holds itself at zero misses forever and is never sat out.
   put 1 into gGame["missCntBy"][tSeatOther]
   put gGame["pubBySeat"][tSeatOther] into tOtherPub
   if tOtherPub is tPlayPubHex then
      put tPlaySec into tOtherSec
   else
      put tHostSec into tOtherSec
   end if
   put heEnvContentLine(kKatTableHex, gGame["handNum"], tOtherPub, "act", \
         "verb=check,amount=0") into tEvilC
   put heWireBuild(tEvilC, tOtherSec, gGame["lastSeq"] + 1, gGame["chainHeadHex"], tHostSec) into tEvil
   heNetIngestWire tEvil
   heTContains "refused: the out-of-turn act is engine-rejected", \
         gGame["netLog"], "engine-rejected act"
   heTAssert "refused: a rejected act does not reset the seat's miss count", \
         gGame["missCntBy"][tSeatOther], 1
   put tSnapG into gTNetPlayG

   -- expiry for real: backdate BOTH clocks past act+bank, tick the HOST --
   -- it emits the signed timeout (bank=1), both sides verify and fold it,
   -- and the fold-win hand settles itself through the react engines
   put gTNetHostG["turnStartMs"] - ((kHeDefaultActSecs + kHeDefaultBankSecs + 1) * 1000) \
         into gTNetHostG["turnStartMs"]
   put gTNetPlayG["turnStartMs"] - ((kHeDefaultActSecs + kHeDefaultBankSecs + 1) * 1000) \
         into gTNetPlayG["turnStartMs"]
   put gTNetHostG into gGame
   heNetActTimerTick
   put gGame into gTNetHostG
   heTNetPump
   heTContains "timer: the host emitted and both folded the timeout", \
         gTNetPlayG["netLog"], "t-out  seat " & tSeatX
   heTAssert "timer: the timeout consumed the seat's time-bank (both sides)", \
         gTNetPlayG["oDeal"]["bankUsedBy"][tSeatX] & "/" & gTNetHostG["oDeal"]["bankUsedBy"][tSeatX], \
         "true/true"
   heTAssert "timer: one recorded miss on the timed-out seat", \
         gTNetPlayG["missCntBy"][tSeatX] & "/" & gTNetHostG["missCntBy"][tSeatX], "1/1"
   heTAssert "timer: hand 1 settled on both sides after the timeout fold", \
         gTNetPlayG["oDeal"]["settleDone"] & "/" & gTNetHostG["oDeal"]["settleDone"], "true/true"

   -- hand 2: the OTHER seat opens voluntarily (a live act resets ITS miss
   -- count), then the hand-1 offender times out AGAIN -> second consecutive
   -- miss -> AUTO-SIT-OUT (transcript-derived, both sides agree); its later
   -- turns this hand time out INSTANTLY (no backdating) and the hand still
   -- reaches a clean settle
   put gTNetHostG into gGame
   heNetHandKick
   put gGame into gTNetHostG
   heTNetPump
   put gTNetPlayG["state"] into tStateA
   put tStateA["toAct"] into tSeatY
   heTAssert "sitout: the heads-up button alternated (a fresh clock subject)", \
         (tSeatY is not tSeatX), "true"
   put tStateA["betCur"] - tStateA["streetBy"][tSeatY] into tOwe
   heTNetAct tSeatY, "verb=call,amount=" & tOwe
   heTAssert "sitout: the action moved to the hand-1 offender", \
         gTNetPlayG["state"]["toAct"], tSeatX
   put gTNetHostG["turnStartMs"] - ((kHeDefaultActSecs + kHeDefaultBankSecs + 1) * 1000) \
         into gTNetHostG["turnStartMs"]
   put gTNetPlayG["turnStartMs"] - ((kHeDefaultActSecs + kHeDefaultBankSecs + 1) * 1000) \
         into gTNetPlayG["turnStartMs"]
   put gTNetHostG into gGame
   heNetActTimerTick
   put gGame into gTNetHostG
   heTNetPump
   heTContains "sitout: two consecutive misses sit the seat out (named)", \
         gTNetPlayG["netLog"], "sits out after 2 missed turns"
   heTAssert "sitout: both sides agree the seat sits out", \
         gTNetPlayG["sitOutBy"][tSeatX] & "/" & gTNetHostG["sitOutBy"][tSeatX], "true/true"
   -- drive hand 2 to its settle: the sat-out seat's turns are INSTANT host
   -- timeouts (limit 0 -- no backdating), the live seat checks through
   repeat with tStep = 1 to 30
      put gTNetPlayG["state"] into tStateA
      if tStateA["phase"] is not "acting" then
         exit repeat
      end if
      put tStateA["toAct"] into tSeat
      if gTNetPlayG["sitOutBy"][tSeat] is "true" then
         put gTNetHostG into gGame
         heNetActTimerTick
         put gGame into gTNetHostG
         heTNetPump
      else
         put tStateA["betCur"] - tStateA["streetBy"][tSeat] into tOwe
         if tOwe > 0 then
            heTNetAct tSeat, "verb=call,amount=" & min(tOwe, tStateA["stackBy"][tSeat])
         else
            heTNetAct tSeat, "verb=check,amount=0"
         end if
      end if
   end repeat
   heTAssert "sitout: hand 2 still settled cleanly around the sat-out seat", \
         gTNetPlayG["oDeal"]["settleDone"] & "/" & gTNetHostG["oDeal"]["settleDone"], "true/true"
   heTAssert "sitout: chips conserved through the instant timeouts", \
         gTNetPlayG["stacksBy"][1] + gTNetPlayG["stacksBy"][2], 800
   -- the next boundary deals the sat-out seat OUT -- and with only one live
   -- seat the table WAITS instead of declaring game over
   put gTNetHostG into gGame
   heTAssert "sitout: the next-hand occupants exclude the sat-out seat", \
         heNetNextOccList(), tSeatY
   -- F10: the "seated with chips" scan is ONE definition with two readers --
   -- heNetNextOccList filters it by sit-out, heNetHandKick counts it to tell
   -- an over table from a parked one. heNetHandKick used to carry its own
   -- copy, which only the second of those two rules was ever pinned against.
   heTAssert "sitout: one occupancy rule, two readers (chips vs chips-and-in)", \
         heNetSeatedWithChipsList() & "/" & heNetNextOccList(), \
         gGame["seatedList"] & "/" & tSeatY
   put gGame["handNum"] into tHandBefore
   heNetHandKick
   heTAssert "sitout: one live seat parks the table (no hand dealt)", \
         gGame["handNum"], tHandBefore
   heTAssert "sitout: the park is LATCHED so any path can re-arm the beat", \
         gGame["handWait"], "true"
   -- F6: the between-hands beat must fire from that latch whatever phase the
   -- table is in -- a park reached from heNetStartGame leaves the phase at
   -- "idle", and the old phase-only guard killed the re-armed beat on its
   -- first firing, so the table could never deal again however many players
   -- returned. Driven on a throwaway copy (it deals a whole hand).
   put gGame into tSnapH
   put "idle" into gGame["phase"]
   put empty into gGame["sitOutBy"]
   heNetNextHandTick
   heTAssert "sitout: the parked beat deals once seats return, in any phase", \
         (gGame["handNum"] > tHandBefore) & "/" & gGame["handWait"], "true/false"
   put tSnapH into gGame
   put gGame into gTNetHostG
   -- the voluntary form: the LIVE seat stands by its own signed wire, then
   -- returns -- both folds seat-scoped, both sides in agreement
   put gTNetPlayG into gGame
   if heNetMySeat() is tSeatY then
      heNetSendAction "stand", "seat=" & tSeatY
      put gGame into gTNetPlayG
   else
      put gGame into gTNetPlayG
      put gTNetHostG into gGame
      heNetSendAction "stand", "seat=" & tSeatY
      put gGame into gTNetHostG
   end if
   heTNetPump
   heTAssert "sitout: a seat's own stand wire folds on both sides", \
         gTNetPlayG["sitOutBy"][tSeatY] & "/" & gTNetHostG["sitOutBy"][tSeatY], "true/true"
   put gTNetPlayG into gGame
   if heNetMySeat() is tSeatY then
      heNetSendAction "sit", "seat=" & tSeatY
      put gGame into gTNetPlayG
   else
      put gGame into gTNetPlayG
      put gTNetHostG into gGame
      heNetSendAction "sit", "seat=" & tSeatY
      put gGame into gTNetHostG
   end if
   heTNetPump
   heTAssert "sitout: the return wire clears the state on both sides", \
         (gTNetPlayG["sitOutBy"][tSeatY] is not "true" \
         and gTNetHostG["sitOutBy"][tSeatY] is not "true"), "true"
   -- the auto-sat-out seat returns too (re-enters next hand)
   put gTNetPlayG into gGame
   if heNetMySeat() is tSeatX then
      heNetSendAction "sit", "seat=" & tSeatX
      put gGame into gTNetPlayG
   else
      put gGame into gTNetPlayG
      put gTNetHostG into gGame
      heNetSendAction "sit", "seat=" & tSeatX
      put gGame into gTNetHostG
   end if
   heTNetPump
   heTAssert "sitout: the auto-sat-out seat's return clears its misses", \
         gTNetPlayG["sitOutBy"][tSeatX] & "/" & gTNetPlayG["missCntBy"][tSeatX], "/0"
   -- F6, the half that actually heals a parked table: the RETURN unparks it.
   -- The sit-return fold used to clear sitOutBy and stop there, so with the
   -- beat off (or dead, above) the returning player saw Return succeed and the
   -- table simply never dealt again. The react engine now kicks the moment the
   -- folded transcript says two seats are dealable -- on the same pass that
   -- folded the return, so no timer has to be alive for it.
   heTAssert "sitout: the second return UNPARKS the table (a hand deals itself)", \
         (gTNetHostG["handNum"] > tHandBefore) & "/" & gTNetHostG["handWait"], "true/false"

   -- ===== LATE-JOIN: a third identity arrives mid-session -- full replay
   -- (the standing machinery), joins, and the host seats it at the next
   -- hand boundary; the joiner must reach the identical fold state
   put gTNetHostG into gGame
   put "true" into gGame["admittedA"][tP3PubHex]
   put "player" into gGame["roleByPub"][tP3PubHex]
   -- the transport handle a real rp1/onion handshake would have registered.
   -- The loopback pump delivers frames without one, and since v0.24.0 (F7)
   -- the boundary seats only keys that are PRESENT -- so the sim has to be
   -- as honest about presence as the transport is.
   put 3 into gGame["peerByPub"][tP3PubHex]
   put tP3PubHex into gGame["peerPubA"][3]
   heNetReplayLogTo 0
   heHostEmitRoster
   put gGame into gTNetHostG
   heTNetPlayCtx "false", tP3PubHex, tP3Sec, tP3BoxPub, tP3BoxSec, tHostPubHex, kKatIdSeed3
   put gGame into gTNetPlay2G
   heTNetPump
   heTAssert "latejoin: the replayed joiner reaches the host's chain head", \
         gTNetPlay2G["chainHeadHex"], gTNetHostG["chainHeadHex"]
   heTAssert "latejoin: the joiner bound its session box on-chain", \
         (gTNetHostG["boxByPub"][tP3PubHex] is not empty), "true"
   put gTNetHostG into gGame
   heNetHandKick
   put gGame into gTNetHostG
   heTNetPump
   heTAssert "latejoin: the host seats the joiner at the boundary (seat 3)", \
         gTNetPlay2G["seatByPub"][tP3PubHex] & "/" & gTNetHostG["seatByPub"][tP3PubHex], "3/3"
   heTAssert "latejoin: the joiner's stack seeds from the signed cfg", \
         gTNetPlay2G["stacksBy"][3], 400
   put gTNetPlay2G["state"] into tStateA
   heTAssert "latejoin: the next hand deals THREE seats", \
         the number of items of tStateA["occ"], 3
   heTAssert "latejoin: hand 3 dealt itself to the action everywhere", \
         tStateA["phase"] & "/" & gTNetPlayG["state"]["phase"], "acting/acting"
   -- check hand 3 down with three contexts, each acting from its own seat
   repeat with tStep = 1 to 40
      put gTNetHostG["state"] into tStateA
      if tStateA["phase"] is not "acting" then
         exit repeat
      end if
      put tStateA["toAct"] into tSeat
      put tStateA["betCur"] - tStateA["streetBy"][tSeat] into tOwe
      if tOwe > 0 then
         put "verb=call,amount=" & min(tOwe, tStateA["stackBy"][tSeat]) into tVerb
      else
         put "verb=check,amount=0" into tVerb
      end if
      put gTNetPlayG into gGame
      if heNetMySeat() is tSeat then
         heNetSendAction "act", tVerb
         put gGame into gTNetPlayG
      else
         put gGame into gTNetPlayG
         put gTNetPlay2G into gGame
         if heNetMySeat() is tSeat then
            heNetSendAction "act", tVerb
            put gGame into gTNetPlay2G
         else
            put gGame into gTNetPlay2G
            put gTNetHostG into gGame
            heNetSendAction "act", tVerb
            put gGame into gTNetHostG
         end if
      end if
      heTNetPump
   end repeat
   heTAssert "latejoin: hand 3 settles on every context", \
         gTNetPlayG["oDeal"]["settleDone"] & "/" & gTNetPlay2G["oDeal"]["settleDone"] \
         & "/" & gTNetHostG["oDeal"]["settleDone"], "true/true/true"
   heTAssert "latejoin: identical fold state (one chain head everywhere)", \
         (gTNetPlayG["chainHeadHex"] is gTNetHostG["chainHeadHex"] \
         and gTNetPlay2G["chainHeadHex"] is gTNetHostG["chainHeadHex"]), "true"
   heTAssert "latejoin: three-seat chips conserved and agreed", \
         gTNetPlay2G["stacksBy"][1] + gTNetPlay2G["stacksBy"][2] + gTNetPlay2G["stacksBy"][3] \
         & "/" & (gTNetPlay2G["stacksBy"][1] is gTNetHostG["stacksBy"][1]), "1200/true"
   -- GHOST SEATS (v0.24.0, F7): "has joined" is a historical fact, and it was
   -- the only test the boundary applied -- so a peer that joined and then
   -- closed its stack (still admitted, still in boxByPub: nothing ever clears
   -- those) was handed the lowest empty seat and a full opening stack, timed
   -- out every turn until two misses sat it out, and held that seat for the
   -- rest of the session, because seats are never released. Both keys below
   -- are fakes that never sign anything (the host signs the sit wires), and
   -- the whole probe runs on a throwaway copy of the host context.
   put gTNetHostG into gGame
   put gGame into tSnapH
   put heBin2HexS(heHash32(textEncode("ghost-key", "utf-8"))) into tGhostPub
   put heBin2HexS(heHash32(textEncode("present-key", "utf-8"))) into tLivePub
   put "true" into gGame["admittedA"][tGhostPub]
   put tGhostPub into gGame["boxByPub"][tGhostPub]
   put "true" into gGame["admittedA"][tLivePub]
   put tLivePub into gGame["boxByPub"][tLivePub]
   -- only the second one is PRESENT: a transport handle plus a fresh
   -- last-heard stamp (what an applied wire or a handshake leaves behind)
   put 11 into gGame["peerByPub"][tLivePub]
   put the milliseconds into gGame["seenMsByPub"][tLivePub]
   heNetSeatLateJoiners
   heTAssert "latejoin: a joined-but-gone key is NOT seated (no ghost seats)", \
         gGame["seatByPub"][tGhostPub], empty
   heTAssert "latejoin: a key that IS present still gets its seat", \
         (gGame["seatByPub"][tLivePub] is not empty), "true"
   heTContains "latejoin: the refusal is named in the net feed", \
         gGame["netLog"], "not seating"
   put tSnapH into gGame
   put gGame into gTNetHostG

   -- ===== the redial-vs-election ORDERING (netCap; the dial itself needs
   -- tor, so the attempt is probed): stream death arms the redial -- never
   -- an instant election -- the backoff doubles per attempt, a host wire
   -- applying resets the counter, and the 60 s watchdog's election always
   -- concludes with the redial standing down
   heTNetPlayCtx "false", tPlayPubHex, tPlaySec, tPlayBoxPub, tPlayBoxSec, tHostPubHex, kKatIdSeed2
   put "onion" into gGame["transport"]
   heNetOnionReset
   put "true" into gGame["gameOn"]
   put "ready" into gGame["oxState"]
   put 7 into gGame["oxStream"]
   put tHostPubHex into gGame["peerPubA"][7]
   put 7 into gGame["peerByPub"][tHostPubHex]
   put "1,2" into gGame["seatedList"]
   put 400 into gGame["stacksBy"][1]
   put 400 into gGame["stacksBy"][2]
   put tHostPubHex into gGame["pubBySeat"][1]
   put tPlayPubHex into gGame["pubBySeat"][2]
   put 7 & return into gGame["oxDeadList"]
   heNetOnionDead
   heTAssert "redial: stream death arms the redial, never an instant election", \
         gGame["hostLost"] & "/" & gGame["oxState"] & "/" & gGame["oxRedialN"], "false/redial/1"
   heTAssert "redial: attempt 1 waits the base backoff", gGame["oxRedialWait"], 8
   repeat with tLoop = 1 to 8
      heNetOnionTick
   end repeat
   heTAssert "redial: the attempt fires when the wait expires", gGame["oxRedialProbe"], 1
   heNetOnionRedialArm
   heTAssert "redial: a failed attempt doubles the backoff", \
         gGame["oxRedialN"] & "/" & gGame["oxRedialWait"], "2/16"
   -- F1: a DIAL failure mid-redial re-arms the schedule. It must never take
   -- the join-time fail-closed path: that calls heNetStop, which clears
   -- gGame["online"] and cancels the poll tick -- and heNetHostLossCheck exits
   -- on its first line when online is not "true", so the election watchdog
   -- would never conclude and attempts 2..4 would never fire. The bounded
   -- four-attempt schedule collapsed into one, with no host and no successor.
   heNetOnionDialFail "SOCKS refused (simulated)"
   heTAssert "redial: a mid-redial dial failure re-arms, never fails closed", \
         gGame["oxRedialN"] & "/" & gGame["oxState"] & "/" & gGame["online"], "3/redial/true"
   heTContains "redial: the failed attempt is named in the feed", \
         gGame["netLog"], "redial attempt 2 failed"
   heTAssert "redial: a re-armed schedule keeps the election pending", \
         gGame["hostLost"], "false"
   -- proof the host answered is a host-signed wire APPLYING: counter resets
   put heEnvContentLine(kKatTableHex, 0, tHostPubHex, "cfg", kKatLobbyCfgBody) into tContent
   put heWireBuild(tContent, tHostSec, 1, kHeGenesisPrev, tHostSec) into tWire
   heNetIngestWire tWire
   heTAssert "redial: a host wire applying resets the attempt counter", \
         gGame["oxRedialN"] & "/" & gGame["hostQuietTicks"], "0/0"
   -- ...but when the host stays gone, the WATCHDOG election concludes and
   -- the redial stands down without clobbering the election's message
   heNetOnionRedialArm
   put kHeHostLossTicks into gGame["hostQuietTicks"]
   heNetHostLossCheck
   heTAssert "redial: the watchdog election still concludes (successor named)", \
         gGame["hostLost"] & "/" & (gGame["electedHostPubHex"] is not empty), "true/true"
   heNetOnionTick
   heTAssert "redial: after the election the redial stands down", gGame["oxState"], "failed"
   heTContains "redial: the stand-down is named in the net feed", gGame["netLog"], "stood down"

   -- F8: the OTHER way out of the redial state -- the attempts running out --
   -- must behave the same way. It ran the election (which names the elected
   -- successor on the status line) and then called heNetOnionFail two lines
   -- later, whose own status write overwrote exactly that message: the player
   -- was told to "Join again" and never told WHO was elected. Both exits are
   -- the quiet stand-down now.
   heTNetPlayCtx "false", tPlayPubHex, tPlaySec, tPlayBoxPub, tPlayBoxSec, tHostPubHex, kKatIdSeed2
   put "onion" into gGame["transport"]
   heNetOnionReset
   put "true" into gGame["gameOn"]
   put "1,2" into gGame["seatedList"]
   put 400 into gGame["stacksBy"][1]
   put 400 into gGame["stacksBy"][2]
   put tHostPubHex into gGame["pubBySeat"][1]
   put tPlayPubHex into gGame["pubBySeat"][2]
   put kHeRedialMax into gGame["oxRedialN"]   -- the last attempt just failed
   heNetOnionRedialArm
   heTAssert "redial: exhaustion concludes the election itself", \
         gGame["hostLost"] & "/" & (gGame["electedHostPubHex"] is not empty), "true/true"
   heTContains "redial: the elected successor stays on the status line", \
         gGame["statusTxt"], "elected host"
   heTAssert "redial: the exhausted stand-down never clobbers that message", \
         (gGame["statusTxt"] contains "Hotseat still works"), "false"
   heTContains "redial: the tor line says the election concluded", \
         gGame["oxFailTxt"], "election concluded"

   -- the redial hello's trim mark, through the REAL router on the HOST:
   -- a reconnecting peer naming applied seq 2 of 3 gets marker + wire 3 only
   heTNetPlayCtx "true", tHostPubHex, tHostSec, tHostBoxPub, tHostBoxSec, tHostPubHex, kKatIdSeed1
   put "true" into gGame["admittedA"][tHostPubHex]
   put "true" into gGame["admittedA"][tPlayPubHex]
   put "host" into gGame["roleByPub"][tHostPubHex]
   put "player" into gGame["roleByPub"][tPlayPubHex]
   heNetSendAction "cfg", heLobbyCfgBody()
   heNetSendAction "chat", "hi=1"
   heNetSendAction "chat", "hi=2"
   put 5 into gGame["peerByPub"][tPlayPubHex]
   put tPlayPubHex into gGame["peerPubA"][5]
   put empty into gGame["netOutbox"]
   heNetOnMessage 9, textEncode("h" & tab & tTokTxt & tab & 2, "utf-8")
   put gGame["netOutbox"] into tOutboxTxt
   put 0 into tWireN
   repeat for each line tLineTxt in tOutboxTxt
      if char 1 to 2 of tLineTxt is "w" & tab then
         add 1 to tWireN
      end if
   end repeat
   heTAssert "redial: the hello's seq mark trims the reconnect replay to the tail", \
         tWireN & "/" & the number of lines of tOutboxTxt, "1/3"
   heTContains "redial: the trimmed replay still leads with the catch-up marker", \
         tOutboxTxt, "r!" & tab

   put empty into gTNetHostG
   put empty into gTNetPlayG
   put empty into gTNetPlay2G
   put tSaved into gGame

   -- what only the real world can verify -- say so, by name (the honesty
   -- convention): wall clocks, real latency, a real tor stream dying.
   heTSkip "liveness: LIVE timed table (act timer + time-bank on two machines, wall clocks)", \
         "the 2e engine-era exit leg -- let a seat time out for real"
   heTSkip "redial: LIVE tor host-stream loss + redial (trimmed resync)", \
         "needs a running tor daemon + a second machine, host killed and restarted"
end heTestLivenessRun

command heTestHelpersRun
   -- 21: the PURE LEAF HELPERS nothing else in this harness ever named.
   -- SHALLOW ON PURPOSE, and the banner says so: these are one-expression
   -- handlers whose whole risk is a chunk boundary, a comparison operator or
   -- a restored delimiter, so a value pin is exactly the right depth for
   -- them and nothing deeper is claimed. They are here because the suite's
   -- 2026-08-16 coverage measurement found 205 of this member's 379 public
   -- handlers named by no heTest*/heProbe* body at all, and a handler no
   -- test names is a handler whose next edit is unverified -- the same
   -- lesson box2dxt learned when 211 of its Kit's 313 turned out to run on
   -- every existing test and be asserted by none.
   -- Everything here is values-in/values-out (H5) and needs no extension,
   -- so this section never SKIPs as a whole; the one branch that reaches a
   -- bt* call probes for it and SKIPs by name.
   local tSaved, tRcTxt, tRcErr, tDelimTxt, tRectTxt
   put return & "-- 21. Pure helpers: leaf values nothing else pinned (shallow)" & return after gRpt
   set the itemDelimiter to comma

   -- heSwapExt: the atlas sibling-path swap. Its own comment makes three
   -- claims and every one of them is pinned here, because atlas-kat.py
   -- hardcodes BOTH sides of the .png/.xml pair and never models the swap --
   -- there is no Python mirror to lean on, so these come from the contract.
   heTAssert "helpers: heSwapExt swaps a trailing extension", \
         heSwapExt("/cards/playingCards.png", ".xml"), "/cards/playingCards.xml"
   heTAssert "helpers: heSwapExt appends when there is no extension", \
         heSwapExt("/cards/playingCards", ".xml"), "/cards/playingCards.xml"
   -- the documented cosmetic edge: a DOT IN A FOLDER NAME eats that segment,
   -- because the swap is item-based. Pinned rather than left as prose so the
   -- day someone makes it path-aware, they change a test and not a promise.
   heTAssert "helpers: heSwapExt's dotted-folder edge is cosmetic, not a crash", \
         heSwapExt("/a.b/cards", ".xml"), "/a.xml"
   -- gotcha 5: it sets the itemDelimiter to "." and MUST put it back. This
   -- line is the only thing that can catch that regression -- a leaked "."
   -- would corrupt the next comma-item read in whatever called it.
   put the itemDelimiter into tDelimTxt
   heTAssert "helpers: heSwapExt restores the itemDelimiter (gotcha 5)", tDelimTxt, comma

   -- heSettingsNumOk: the settings dialog's whole-number guard. Three
   -- separate refusals live in one handler, so each gets its own value.
   heTAssert "helpers: heSettingsNumOk accepts a whole number at the minimum", \
         heSettingsNumOk(2, 2), "true"
   heTAssert "helpers: heSettingsNumOk refuses below the minimum", \
         heSettingsNumOk(1, 2), "false"
   heTAssert "helpers: heSettingsNumOk refuses a fraction", \
         heSettingsNumOk(2.5, 2), "false"
   heTAssert "helpers: heSettingsNumOk refuses non-numeric text", \
         heSettingsNumOk("ten", 0), "false"
   heTAssert "helpers: heSettingsNumOk refuses empty (an untyped field)", \
         heSettingsNumOk(empty, 0), "false"
   heTAssert "helpers: heSettingsNumOk accepts zero at minimum zero", \
         heSettingsNumOk(0, 0), "true"

   -- heHandByOf: what the HUD subtracts to show chips BEHIND. Its contract
   -- has a sharp edge -- at "between" the deltas are ALREADY in stacksBy, so
   -- reading the hand's handBy there would double-count every settled bet --
   -- and that edge is the whole reason the handler exists rather than the
   -- array read. Reads the live store, so it snapshots and restores it.
   put gGame into tSaved
   put "hand" into gGame["phase"]
   put 25 into gGame["state"]["handBy"][2]
   heTAssert "helpers: heHandByOf reports a live seat's committed chips", \
         heHandByOf(2), 25
   heTAssert "helpers: heHandByOf reads 0 for a seat that has committed none", \
         heHandByOf(3), 0
   put "showdown" into gGame["phase"]
   heTAssert "helpers: the showdown hold is still a LIVE hand for the HUD", \
         heHandByOf(2), 25
   put "between" into gGame["phase"]
   heTAssert "helpers: heHandByOf reads 0 at between (stacksBy already paid)", \
         heHandByOf(2), 0
   put tSaved into gGame

   -- heRcTxt: the bt* return-code label the torrent probe prints. The ok and
   -- positive branches are pure; the NEGATIVE branch names btLastError, so
   -- it is probed for rather than assumed (this harness must run on an
   -- engine with no TorrentXT). The probe is named by DESCRIPTION and not by
   -- handler, deliberately: the suite fold's check 7d builds its reachable
   -- closure by over-approximation -- any he* name in a reachable body is an
   -- edge, comment or not -- and that probe opens a libtorrent session.
   heTAssert "helpers: heRcTxt reads an empty result as ok", heRcTxt(empty), "ok"
   heTAssert "helpers: heRcTxt reads 0 as ok", heRcTxt(0), "ok"
   heTAssert "helpers: heRcTxt labels a positive rc with its number", heRcTxt(3), "rc=3"
   try
      put heRcTxt(-1) into tRcTxt
   catch tRcErr
      put empty into tRcTxt
   end try
   if tRcTxt is empty then
      heTSkip "helpers: heRcTxt's failure branch", \
            "it names btLastError -- TorrentXT not installed"
   else
      heTContains "helpers: heRcTxt names the code on a negative rc", tRcTxt, "FAILED (-1)"
   end if

   -- heFitRect: the aspect-fit both the seat avatar and the table logo use.
   -- PINNED AS BUILT, and the interesting half is the LAST two lines. The
   -- returned width is 2 * (tW div 2), so an ODD fitted size renders one
   -- pixel short -- the handler's comment used to claim "integer div keeps
   -- it exact", which is false about the width and is corrected at its own
   -- site. It is pinned rather than fixed because the shrink-or-equal,
   -- exactly-symmetric-about-(pCx,pCy) rect is a property something else
   -- already leans on: tools/check-table-layout.py exempts BOTH callers on
   -- the written argument that heFitRect "can only ever shrink within" the
   -- built rect centred on that point, which an exact-width version would
   -- quietly weaken by pushing one edge to ceil(tW/2). One pixel on a
   -- blendLevel watermark is not worth an un-eyeballed geometry change in a
   -- layer whose confirming eye is still owed to the OXT pass.
   heTAssert "helpers: heFitRect letterboxes a wide picture inside the box", \
         heFitRect(100, 50, 512, 286, 240), "392,226,632,346"
   heTAssert "helpers: heFitRect pillarboxes a tall picture inside the box", \
         heFitRect(50, 100, 512, 286, 240), "452,166,572,406"
   heTAssert "helpers: heFitRect falls back to the full box on a bad size", \
         heFitRect(0, 0, 100, 100, 46), "77,77,123,123"
   heTAssert "helpers: heFitRect falls back to the full box on non-numeric", \
         heFitRect("x", 10, 100, 100, 46), "77,77,123,123"
   -- the odd case: a fitted height of round(46 * 63 / 100) = 29, built as
   -- 100 -+ 14, so the rect is dead-centred and 28 tall. Copied to a local
   -- before the chunk (H6, and heSwapExt's own precedent).
   put heFitRect(100, 63, 100, 100, 46) into tRectTxt
   heTAssert "helpers: heFitRect stays exactly symmetric about the centre", \
         tRectTxt, "77,86,123,114"
   heTAssert "helpers: ...which costs an odd fit ONE pixel (28 for a fitted 29)", \
         (item 4 of tRectTxt) - (item 2 of tRectTxt), 28

   -- heAwardedPot: the uncalled-bet rule, from the 2026-08-17 hotseat
   -- transcript. The three hands below ARE that session: two normal called
   -- hands the old sum-of-commitments got right, and the heads-up all-in it
   -- got wrong by exactly the returned excess.
   local tHandBy
   put empty into tHandBy
   put 16 into tHandBy[1]
   put 400 into tHandBy[2]
   put 12 into tHandBy[3]
   put 400 into tHandBy[4]
   put 6 into tHandBy[5]
   put 8 into tHandBy[6]
   heTAssert "pot: a fully called six-way hand is the sum of commitments (842)", \
         heAwardedPot(tHandBy, "1,2,3,4,5,6"), 842
   put empty into tHandBy
   put 384 into tHandBy[1]
   put 388 into tHandBy[3]
   put 394 into tHandBy[4]
   put 394 into tHandBy[5]
   put 0 into tHandBy[6]
   heTAssert "pot: two seats level at the top still sum whole (1560)", \
         heAwardedPot(tHandBy, "1,3,4,5,6"), 1560
   put empty into tHandBy
   put 2008 into tHandBy[4]
   put 392 into tHandBy[6]
   heTAssert "pot: a 392 all-in called by 2008 awards 784, NOT the 2400 committed", \
         heAwardedPot(tHandBy, "4,6"), 784
   put empty into tHandBy
   put 500 into tHandBy[1]
   heTAssert "pot: a lone seat's whole commitment is uncalled - the pot is 0", \
         heAwardedPot(tHandBy, "1"), 0
   heTAssert "pot: no seats is an empty pot, not an error", \
         heAwardedPot(tHandBy, empty), 0
end heTestHelpersRun

command heTestLeafRun
   -- 22: FIRST TRANCHE of the coverage worklist's no-test category -- the
   -- pure leaves the suite gate's own comment names as the place to start
   -- (heRank5, heCardRankVal, heCardSuitVal, heTwoDigits, heCountItems,
   -- heNextInList, heByteXor, heU32BEData, heHexId), plus heHandStart's
   -- refusal guards. SHALLOW ON PURPOSE and this banner says so (the
   -- box2dxt 211-handler precedent): a value pin per branch, claiming
   -- "this leaf computes what its contract says" and nothing deeper.
   -- heHandStart DEALS A HAND past its guards -- the deal arms the paced
   -- reveal/settle timers and drives the table UI, exactly what the fold
   -- record forbids a folded harness to do inside somebody else's paste --
   -- so this section exercises its PURE PRELUDE only: the phase guard and
   -- the online guard, both real exits asserted on real state, with
   -- "handNum unmoved" as the witness that no deal began. The dealt path
   -- itself stays with the hotseat OXT pass, where it runs on every hand.
   local tSaved, tHexTxt, tCh, tBadN, tData
   put return & "-- 22. Leaf tranche: no-test worklist, first pass (shallow)" & return after gRpt
   set the itemDelimiter to comma

   -- heCardRankVal / heCardSuitVal: the two halves of the card index
   -- convention (index 1..52: rank (i-1) div 4 + 2, suit (i-1) mod 4 + 1),
   -- pinned at both edges and one interior point each
   heTAssert "leaf: heCardRankVal of card 1 (2c) is 2", heCardRankVal(1), 2
   heTAssert "leaf: heCardRankVal of card 52 (As) is 14", heCardRankVal(52), 14
   heTAssert "leaf: heCardRankVal of card 23 (7h) is 7", heCardRankVal(23), 7
   heTAssert "leaf: heCardSuitVal of card 1 (2c) is 1 (clubs)", heCardSuitVal(1), 1
   heTAssert "leaf: heCardSuitVal of card 2 (2d) is 2 (diamonds)", heCardSuitVal(2), 2
   heTAssert "leaf: heCardSuitVal of card 52 (As) is 4 (spades)", heCardSuitVal(52), 4

   -- heTwoDigits: the evaluator's fixed-width field builder. The WIDTH is
   -- the contract (six 2-digit fields so plain numeric comparison orders
   -- hands), and `is` compares "09" and 9 as equal numbers, so the char
   -- count is asserted beside the value
   heTAssert "leaf: heTwoDigits pads a single digit", heTwoDigits(9), "09"
   heTAssert "leaf: heTwoDigits padded width is exactly 2 chars", \
         the number of chars of heTwoDigits(9), 2
   heTAssert "leaf: heTwoDigits leaves two digits alone", heTwoDigits(14), 14
   heTAssert "leaf: heTwoDigits pads zero to width 2", \
         the number of chars of heTwoDigits(0), 2

   -- heCountItems: the empty edge is the whole reason it exists (empty has
   -- one item to the engine, zero seats to a card game)
   heTAssert "leaf: heCountItems of empty is 0", heCountItems(empty), 0
   heTAssert "leaf: heCountItems of one entry", heCountItems("4"), 1
   heTAssert "leaf: heCountItems of six seats", heCountItems("1,2,3,4,5,6"), 6

   -- heNextInList: the circular successor the button rotation rides
   heTAssert "leaf: heNextInList steps forward", heNextInList("1,3,5", 3), 5
   heTAssert "leaf: heNextInList wraps at the end", heNextInList("1,3,5", 5), 1
   heTAssert "leaf: heNextInList of an absent entry falls to item 1", \
         heNextInList("1,3,5", 4), 1
   heTAssert "leaf: heNextInList of a lone seat is that seat", heNextInList("7", 7), 7

   -- heByteXor: the pure-integer XOR that keeps H7's no-bitwise law
   -- (bitXor throws double/binary on this engine, v0.4.1)
   heTAssert "leaf: heByteXor identity (x xor 0)", heByteXor(200, 0), 200
   heTAssert "leaf: heByteXor self-inverse (x xor x)", heByteXor(170, 170), 0
   heTAssert "leaf: heByteXor complement (170 xor 85)", heByteXor(170, 85), 255
   heTAssert "leaf: heByteXor of 1 and 2", heByteXor(1, 2), 3
   heTAssert "leaf: heByteXor passes 255 through", heByteXor(255, 0), 255

   -- heU32BEData: the 4-byte big-endian block counter fed into sxHash.
   -- Its output is ENGINE-built binary (numToByte), not FFI-bridged, so
   -- byteToNum over a plain local is the H6-corollary-safe read (coinxt's
   -- engine-passed idiom): each byte asserted, MSB first
   put heU32BEData(305419896) into tData
   heTAssert "leaf: heU32BEData byte 1 (MSB) of 305419896", byteToNum(byte 1 of tData), 18
   heTAssert "leaf: heU32BEData byte 2", byteToNum(byte 2 of tData), 52
   heTAssert "leaf: heU32BEData byte 3", byteToNum(byte 3 of tData), 86
   heTAssert "leaf: heU32BEData byte 4 (LSB)", byteToNum(byte 4 of tData), 120
   put heU32BEData(0) into tData
   heTAssert "leaf: heU32BEData of 0 is four zero bytes", \
         byteToNum(byte 1 of tData) + byteToNum(byte 2 of tData) \
         + byteToNum(byte 3 of tData) + byteToNum(byte 4 of tData), 0

   -- heHexId: random by design, so the DETERMINISTIC properties are the
   -- pin -- length and alphabet (lowercase by construction: it draws from
   -- a lowercase literal)
   put heHexId(64) into tHexTxt
   heTAssert "leaf: heHexId(64) is 64 chars", the number of chars of tHexTxt, 64
   put 0 into tBadN
   repeat for each char tCh in tHexTxt
      if offset(tCh, "0123456789abcdef") is 0 then
         add 1 to tBadN
      end if
   end repeat
   heTAssert "leaf: heHexId draws only hex chars", tBadN, 0
   heTAssert "leaf: heHexId(16) is 16 chars", the number of chars of heHexId(16), 16

   -- heRank5: the 5-card core under heEval7. Section 1 pins the 7-card
   -- surface exhaustively; nothing had ever named the 5-card entry
   -- itself. One vector per category boundary that matters, through the
   -- same heTIdxOf the evaluator section uses
   heTAssert "leaf: heRank5 royal flush", heRank5(heTIdxOf("As Ks Qs Js Ts")), "081400000000"
   heTAssert "leaf: heRank5 steel wheel (5-high straight flush)", \
         heRank5(heTIdxOf("Ah 2h 3h 4h 5h")), "080500000000"
   heTAssert "leaf: heRank5 quads with kicker", \
         heRank5(heTIdxOf("Qc Qd Qh Qs Ad")), "071214000000"
   heTAssert "leaf: heRank5 wheel straight mixed suits", \
         heRank5(heTIdxOf("Ad 2c 3h 4s 5d")), "040500000000"
   heTAssert "leaf: heRank5 high card reads all five kickers", \
         heRank5(heTIdxOf("Ac Kd Qh Js 9c")), "001413121109"

   -- heHandStart, GUARDS ONLY (the banner's reason): drive both refusal
   -- exits on a synthetic gGame and prove the deal did not begin
   put gGame into tSaved
   put empty into gGame
   put "hand" into gGame["phase"]
   put 7 into gGame["handNum"]
   heHandStart
   heTAssert "leaf: heHandStart refuses to deal over an active phase", gGame["handNum"], 7
   heTAssert "leaf: ...and leaves the phase standing", gGame["phase"], "hand"
   put "between" into gGame["phase"]
   put "true" into gGame["online"]
   heHandStart
   heTAssert "leaf: heHandStart refuses the hotseat deal while online", gGame["handNum"], 7
   heTContains "leaf: ...and says why on the status line", gGame["statusTxt"], "hotseat"
   put tSaved into gGame
end heTestLeafRun

command heTestLeafRun2
   -- 23: SECOND TRANCHE of the coverage worklist's no-test category,
   -- written 2026-08-27 so tonight's OXT pass carries it. SHALLOW ON
   -- PURPOSE and this banner says so (the section-22 precedent): a value
   -- pin per branch, claiming "this leaf computes what its contract says"
   -- and nothing deeper. Selection rule, same as 22: pure functions and
   -- handlers whose only state is gGame, driven on a SYNTHETIC gGame
   -- saved and restored around the block -- nothing here arms a timer,
   -- touches a control, plays a sound, or crosses an FFI.
   local tSaved, tA, tCaught, tErr, tContentExp, tEnvExp, tLine, tTxt
   put return & "-- 23. Leaf tranche 2: no-test worklist, second pass (shallow)" & return after gRpt
   set the itemDelimiter to comma

   -- heCardFace / heSuitGlyph / heKenneyFrame: the three card-face maps
   -- (status line, glyph, atlas frame), pinned at the corners and the
   -- ten (the one rank that renders as two chars)
   heTAssert "leaf2: heCardFace of 52 (As)", heCardFace(52), "A" & numToCodepoint(9824)
   heTAssert "leaf2: heCardFace of 36 (Ts) shows 10", heCardFace(36), "10" & numToCodepoint(9824)
   heTAssert "leaf2: heCardFace of 1 (2c)", heCardFace(1), "2" & numToCodepoint(9827)
   heTAssert "leaf2: heSuitGlyph 1 is clubs", heSuitGlyph(1), numToCodepoint(9827)
   heTAssert "leaf2: heSuitGlyph 2 is diamonds", heSuitGlyph(2), numToCodepoint(9830)
   heTAssert "leaf2: heSuitGlyph 3 is hearts", heSuitGlyph(3), numToCodepoint(9829)
   heTAssert "leaf2: heSuitGlyph 4 is spades", heSuitGlyph(4), numToCodepoint(9824)
   heTAssert "leaf2: heSuitGlyph out of range is the ? sentinel", heSuitGlyph(7), "?"
   heTAssert "leaf2: heKenneyFrame of 1 (2c)", heKenneyFrame(1), "cardClubs2"
   heTAssert "leaf2: heKenneyFrame of 36 (Ts) spells 10", heKenneyFrame(36), "cardSpades10"
   heTAssert "leaf2: heKenneyFrame of 52 (As)", heKenneyFrame(52), "cardSpadesA"

   -- heHandLabel: the packed-rank category names the status line prints
   heTAssert "leaf2: heHandLabel 08 is straight flush", heHandLabel("081400000000"), "straight flush"
   heTAssert "leaf2: heHandLabel 06 is full house", heHandLabel("060203000000"), "full house"
   heTAssert "leaf2: heHandLabel 04 is straight", heHandLabel("041400000000"), "straight"
   heTAssert "leaf2: heHandLabel 00 is high card", heHandLabel("001413121109"), "high card"

   -- heIsCardList: the transcript-fold guard, every refusal branch
   heTAssert "leaf2: heIsCardList accepts an exact list", heIsCardList("1,2,52", 3), true
   heTAssert "leaf2: heIsCardList refuses a short list", heIsCardList("1,2", 3), false
   heTAssert "leaf2: heIsCardList refuses card 0", heIsCardList("0,2,3", 3), false
   heTAssert "leaf2: heIsCardList refuses card 53", heIsCardList("53,2,3", 3), false
   heTAssert "leaf2: heIsCardList refuses a fraction", heIsCardList("2.5,3,4", 3), false
   heTAssert "leaf2: heIsCardList refuses non-numeric text", heIsCardList("x,2,3", 3), false

   -- the circular seat walkers under the button/blind schedule
   heTAssert "leaf2: heNextLiveAfterPos steps forward", heNextLiveAfterPos("1,3,5", 3), 5
   heTAssert "leaf2: heNextLiveAfterPos wraps", heNextLiveAfterPos("1,3,5", 5), 1
   heTAssert "leaf2: heNextLiveAfterPos from a busted position", heNextLiveAfterPos("1,3,5", 4), 5
   heTAssert "leaf2: hePrevLiveBeforePos steps back", hePrevLiveBeforePos("1,3,5", 3), 1
   heTAssert "leaf2: hePrevLiveBeforePos wraps", hePrevLiveBeforePos("1,3,5", 1), 5
   heTAssert "leaf2: hePrevLiveBeforePos from a busted position", hePrevLiveBeforePos("1,3,5", 4), 3
   heTAssert "leaf2: heRotateAfter reorders past the entry", heRotateAfter("1,3,5", 3), "5,1,3"
   heTAssert "leaf2: heRotateAfter of the last entry is unchanged", heRotateAfter("1,3,5", 5), "1,3,5"
   heTAssert "leaf2: heRotateAfter of an absent entry is unchanged", heRotateAfter("1,3,5", 4), "1,3,5"

   -- heSpeedMult / heDeltaOfTxt / heTempPath / heLogField / the labels
   heTAssert "leaf2: heSpeedMult fast halves", heSpeedMult("fast"), 0.5
   heTAssert "leaf2: heSpeedMult slow stretches", heSpeedMult("slow"), 1.6
   heTAssert "leaf2: heSpeedMult default is 1", heSpeedMult("normal"), 1.0
   heTAssert "leaf2: heDeltaOfTxt finds a negative delta", heDeltaOfTxt("1:25|3:-25", 3), -25
   heTAssert "leaf2: heDeltaOfTxt of an absent seat is 0", heDeltaOfTxt("1:25|3:-25", 5), 0
   heTAssert "leaf2: heDeltaOfTxt of malformed text is 0", heDeltaOfTxt("junk", 3), 0
   heTAssert "leaf2: heTempPath is the fixed scratch name", heTempPath(), "he_rendezvous"
   heTAssert "leaf2: heLogField picks a tab field", heLogField("a" & tab & "b" & tab & "c", 2), "b"
   heTAssert "leaf2: heTransportLabel onion", heTransportLabel("onion"), "Host over: Tor"
   heTAssert "leaf2: heTransportLabel default is DHT", heTransportLabel("dht"), "Host over: DHT"
   heTAssert "leaf2: heHostModeLabel oracle", heHostModeLabel("oracle"), "Host: ORACLE"
   heTAssert "leaf2: heHostModeLabel default is playing", heHostModeLabel("x"), "Host: playing"

   -- heDrawUniform: value+offset packing, rejection sampling, exhaustion
   heTAssert "leaf2: heDrawUniform draws 1 from a zero word", heDrawUniform("00000000", 1, 5), "1,9"
   heTAssert "leaf2: heDrawUniform rejects the biased top word", \
         heDrawUniform("ffffffff" & "00000003", 1, 5), "4,17"
   put "no throw" into tCaught
   try
      get heDrawUniform("00", 1, 5)
   catch tErr
      put tErr into tCaught
   end try
   heTContains "leaf2: heDrawUniform throws on an exhausted stream", tCaught, "he-stream-exhausted"

   -- heEnvWireParse: the 10-field wire split plus BOTH signed spans, and
   -- the caller's itemDelimiter restored (its stated contract)
   put "1" & tab & "TBLHEX" & tab & "7" & tab & "3" & tab & "act" & tab & "aabb" into tContentExp
   put tContentExp & tab & "SENDSIG" & tab & "9" & tab & "PREVHEX" into tEnvExp
   put tEnvExp & tab & "HOSTSIG" into tLine
   set the itemDelimiter to "|"
   put heEnvWireParse(tLine) into tA
   heTAssert "leaf2: heEnvWireParse restores the itemDelimiter", the itemDelimiter, "|"
   set the itemDelimiter to comma
   heTAssert "leaf2: heEnvWireParse from-seat field", tA["from"], 3
   heTAssert "leaf2: heEnvWireParse type field", tA["type"], "act"
   heTAssert "leaf2: heEnvWireParse bodyHex field", tA["bodyHex"], "aabb"
   heTAssert "leaf2: heEnvWireParse seq field", tA["seq"], 9
   heTAssert "leaf2: heEnvWireParse hostSig field", tA["hostSig"], "HOSTSIG"
   heTAssert "leaf2: heEnvWireParse contentLine is items 1-6", tA["contentLine"], tContentExp
   heTAssert "leaf2: heEnvWireParse envLine is items 1-9", tA["envLine"], tEnvExp

   -- the gGame-reading leaves, on a SYNTHETIC gGame (the section-22
   -- pattern): saved above the block, restored below it, no timer armed
   put gGame into tSaved
   put empty into gGame
   put 100 into gGame["state"]["betCur"]
   put 40 into gGame["state"]["streetBy"][3]
   put 1000 into gGame["state"]["stackBy"][3]
   put 0 into gGame["state"]["streetBy"][5]
   put 25 into gGame["state"]["stackBy"][5]
   heTAssert "leaf2: heCallAmountFor owes the difference", heCallAmountFor(3), 60
   heTAssert "leaf2: heCallAmountFor caps at the stack", heCallAmountFor(5), 25
   put "hand" into gGame["phase"]
   heTAssert "leaf2: heHandLive true in the acting phase", heHandLive(), true
   put "runout" into gGame["phase"]
   heTAssert "leaf2: heHandLive true through the runout", heHandLive(), true
   put "1,3" into gGame["state"]["occ"]
   put 50 into gGame["state"]["handBy"][1]
   put 70 into gGame["state"]["handBy"][3]
   heTAssert "leaf2: heCurrentPot sums the live hand", heCurrentPot(), 120
   put "between" into gGame["phase"]
   heTAssert "leaf2: heHandLive false between hands", heHandLive(), false
   heTAssert "leaf2: heCurrentPot is 0 between hands", heCurrentPot(), 0
   put 250 into gGame["paceDeal"]
   heTAssert "leaf2: hePaceMs reads the scaled beat", hePaceMs("paceDeal", 900), 250
   heTAssert "leaf2: hePaceMs falls back to the default", hePaceMs("paceNever", 900), 900
   put 4 into gGame["numSeats"]
   put 100 into gGame["stacksBy"][1]
   put 0 into gGame["stacksBy"][2]
   put 50 into gGame["stacksBy"][3]
   put 0 into gGame["stacksBy"][4]
   heTAssert "leaf2: heSeatsAlive lists funded seats", heSeatsAlive(), "1,3"
   put 0 into gGame["stacksBy"][1]
   put 0 into gGame["stacksBy"][3]
   heTAssert "leaf2: heSeatsAlive of a broke table is empty", heSeatsAlive(), empty
   put 3 into gGame["oDeal"]["dealCount"]
   heTAssert "leaf2: heNetContribCount is the dealt seats", heNetContribCount(), 3
   put "true" into gGame["oDeal"]["oracleDeal"]
   heTAssert "leaf2: heNetContribCount adds the oracle position", heNetContribCount(), 4
   put "x" into gGame["oDeal"]["dealCount"]
   heTAssert "leaf2: heNetContribCount of no deal is 0", heNetContribCount(), 0
   put "2,5,9" into gGame["state"]["occ"]
   heTAssert "leaf2: heNetSeatPos packs seat 5 to position 2", heNetSeatPos(5), 2
   heTAssert "leaf2: heNetSeatPos packs seat 9 to position 3", heNetSeatPos(9), 3
   heTAssert "leaf2: heNetSeatPos of an undealt seat is 0", heNetSeatPos(4), 0
   put "true" into gGame["sitOutBy"][2]
   heTAssert "leaf2: heNetTurnLimitSecs of a sat-out seat is 0", heNetTurnLimitSecs(2), 0
   put "act=12,bank=34" into gGame["cfgBody"]
   heTAssert "leaf2: heNetTurnLimitSecs adds the unspent bank", heNetTurnLimitSecs(3), 46
   put "true" into gGame["oDeal"]["bankUsedBy"][4]
   heTAssert "leaf2: heNetTurnLimitSecs after the bank is spent", heNetTurnLimitSecs(4), 12
   put empty into gGame["cfgBody"]
   heTAssert "leaf2: heNetTurnLimitSecs default is act+bank", heNetTurnLimitSecs(3), 90
   put 3 into gGame["handNum"]
   put "idle" into gGame["phase"]
   put 10 into gGame["sb"]
   put 20 into gGame["bb"]
   put 0 into gGame["ante"]
   put "off" into gGame["levelMode"]
   put 0 into gGame["curLevel"]
   put heHeaderTxt() into tTxt
   heTContains "leaf2: heHeaderTxt names the hand", tTxt, "Hand 3"
   heTContains "leaf2: heHeaderTxt names the blinds", tTxt, "Blinds 10/20"
   heTAssert "leaf2: heHeaderTxt omits a zero ante", offset("Ante", tTxt), 0
   put 25 into gGame["ante"]
   heTContains "leaf2: heHeaderTxt names a live ante", heHeaderTxt(), "Ante 25"
   put "AB12" into gGame["tableIdHex"]
   put "onion" into gGame["transport"]
   put "xyz.onion" into gGame["onionAddrTxt"]
   heTAssert "leaf2: heInviteTxt carries the onion endpoint", heInviteTxt(), "AB12@xyz.onion"
   put "dht" into gGame["transport"]
   heTAssert "leaf2: heInviteTxt is the bare code on DHT", heInviteTxt(), "AB12"
   put "onion" into gGame["transport"]
   put empty into gGame["onionAddrTxt"]
   heTAssert "leaf2: heInviteTxt falls back with no address", heInviteTxt(), "AB12"
   put 3 into gGame["handNum"]
   put empty into gGame["log"]
   heLogAppend "handStart", "table", "seats=1|3"
   heTAssert "leaf2: heLogAppend grows the log one line", the number of lines of gGame["log"], 1
   heTContains "leaf2: ...carrying the wire type", gGame["log"], "handStart"
   put tSaved into gGame
end heTestLeafRun2

function heTIdxOf pNamesTxt
   local tOut, tNameTxt, tNames
   set the itemDelimiter to comma
   put pNamesTxt into tNames
   replace comma with space in tNames
   put empty into tOut
   repeat for each word tNameTxt in tNames
      put heCardIndex(tNameTxt) & comma after tOut
   end repeat
   delete char -1 of tOut
   return tOut
end heTIdxOf

function heTNamesOf pIdxList
   local tOut, tIdx
   set the itemDelimiter to comma
   put empty into tOut
   repeat for each item tIdx in pIdxList
      put heCardName(tIdx) & comma after tOut
   end repeat
   delete char -1 of tOut
   return tOut
end heTNamesOf

function heTVectors
   local tVecs
   put empty into tVecs
   put "As Ks Qs Js Ts 2c 3d|081400000000|royal flush" & return after tVecs
   put "9h 8h 7h 6h 5h Ad Kc|080900000000|straight flush 9 high" & return after tVecs
   put "Ah 2h 3h 4h 5h Kd Qc|080500000000|wheel straight flush high=5" & return after tVecs
   put "Ah 2h 3h 4h 5h Kh Qh|080500000000|steel wheel not outranked by flush" & return after tVecs
   put "Qc Qd Qh Qs Ad 2c 3c|071214000000|quads with best kicker" & return after tVecs
   put "8c 8d 8h 8s Kd 2c 2d|070813000000|quads on board, kicker decides" & return after tVecs
   put "Ac Ad Ah Kc Kd Kh Qs|061413000000|boat over boat: two trips" & return after tVecs
   put "2c 2d 2h 3c 3d Ah Kh|060203000000|boat: low trips high pair" & return after tVecs
   put "9h 8h 6h 5h 2h 7c Td|050908060502|flush beats mixed straight" & return after tVecs
   put "Ah Qh Th 8h 6h 4h 2h|051412100806|flush best five of seven suited" & return after tVecs
   put "As Kd Qh Js Tc 2c 3d|041400000000|broadway straight" & return after tVecs
   put "As Kd Qh Js Tc 4h 5s|041400000000|board plays: same broadway" & return after tVecs
   put "Ad 2c 3h 4s 5d Kc Qh|040500000000|wheel straight mixed suits" & return after tVecs
   put "2c 3d 4h 5s 6c 7d 8h|040800000000|seven-card run picks best high" & return after tVecs
   put "8c 7d 6h 5s 4c 8d 4d|040800000000|straight through paired board" & return after tVecs
   put "Ac Kd Qh Js 9c 2d 3h|001413121109|A-K-Q-J-9 is no straight" & return after tVecs
   put "Ac Ad Ah Kc Qd 9s 2c|031413120000|trips with two kickers" & return after tVecs
   put "Ac Ad Kc Kd Qc Qd 2h|021413120000|two pair from three pairs" & return after tVecs
   put "9c 9d 8c 8d 2h 2s Ac|020908140000|two pair lone ace outkicks" & return after tVecs
   put "Jc Jd 4c 4d 9h 8s Ah|021104140000|plain two pair ace kicker" & return after tVecs
   put "Ac Ad Kc Qd 9s 5h 2c|011413120900|one pair three kickers" & return after tVecs
   put "7c 7d 7h 4c 4d 4h As|060704000000|full house from two trips low" & return after tVecs
   put "2c 2d 2h 2s Ac 7d 5h|070214000000|quads of deuces ace kicker" & return after tVecs
   put "Kh Jh Th 9h 8h 7h 2c|081100000000|six-card flush hides a J-high SF" & return after tVecs
   put "2c 3d 4h 5s 6c Ac Kd|040600000000|6-high straight chosen over the wheel" & return after tVecs
   put "Ac Ad Ah Kc Kd Qc Qd|061413000000|boat picks the higher of two pairs" & return after tVecs
   return tVecs
end heTVectors

command heTestEvaluatorRun
   local tVecLine, tExpect, tLabel, tIdxList, tBase, tPermLines, tPermLine
   local tPermuted, tPos, tResA, tPairI, tPairJ, tBad, tVecCount, tA, tBv
   put "-- 1. evaluator (spec 8.2)" & return after gRpt
   repeat for each line tVecLine in heTVectors()
      set the itemDelimiter to "|"
      put item 2 of tVecLine into tExpect
      put item 3 of tVecLine into tLabel
      put heTIdxOf(item 1 of tVecLine) into tIdxList
      heTAssert "eval: " & tLabel, heEval7(tIdxList), tExpect
   end repeat

   put "7,6,5,4,3,2,1" & return & "4,5,6,7,1,2,3" & return \
         & "2,4,6,1,3,5,7" & return & "5,1,7,3,6,2,4" into tPermLines
   put 0 into tBad
   repeat for each line tVecLine in heTVectors()
      set the itemDelimiter to "|"
      put heTIdxOf(item 1 of tVecLine) into tIdxList
      set the itemDelimiter to comma
      put heEval7(tIdxList) into tBase
      repeat for each line tPermLine in tPermLines
         put empty into tPermuted
         repeat for each item tPos in tPermLine
            put item tPos of tIdxList & comma after tPermuted
         end repeat
         delete char -1 of tPermuted
         if heEval7(tPermuted) is not tBase then
            add 1 to tBad
         end if
      end repeat
   end repeat
   heTAssert "eval: order independence (26 hands x 4 permutations)", tBad, 0

   put 0 into tPos
   repeat for each line tVecLine in heTVectors()
      set the itemDelimiter to "|"
      add 1 to tPos
      put heEval7(heTIdxOf(item 1 of tVecLine)) into tResA[tPos]
   end repeat
   put tPos into tVecCount
   put 0 into tBad
   repeat with tPairI = 1 to tVecCount - 1
      repeat with tPairJ = tPairI + 1 to tVecCount
         put tResA[tPairI] > tResA[tPairJ] into tA
         put tResA[tPairJ] > tResA[tPairI] into tBv
         if tResA[tPairI] is tResA[tPairJ] then
            if tA or tBv then
               add 1 to tBad
            end if
         else
            if tA is tBv then
               add 1 to tBad
            end if
         end if
      end repeat
   end repeat
   heTAssert "eval: antisymmetry over all vector pairs", tBad, 0
   -- leave the delimiter as the house default, not the "|" this section parses
   -- vectors with (gotcha 5: it is global state and the next section inherits it)
   set the itemDelimiter to comma
end heTestEvaluatorRun

function heTNewHand pSB, pBB, pStacksList, pOccList, pButtonSeat
   -- ante-free wrapper for the existing betting cases; heTNewHandAnte adds antes
   local tStacksA, tPos, tSeatNum
   set the itemDelimiter to comma
   put 0 into tPos
   repeat for each item tSeatNum in pOccList
      add 1 to tPos
      put item tPos of pStacksList into tStacksA[tSeatNum]
   end repeat
   return heBetNewHand(pSB, pBB, 0, tStacksA, pOccList, pButtonSeat)
end heTNewHand

function heTNewHandAnte pSB, pBB, pAnte, pStacksList, pOccList, pButtonSeat
   local tStacksA, tPos, tSeatNum
   set the itemDelimiter to comma
   put 0 into tPos
   repeat for each item tSeatNum in pOccList
      add 1 to tPos
      put item tPos of pStacksList into tStacksA[tSeatNum]
   end repeat
   return heBetNewHand(pSB, pBB, pAnte, tStacksA, pOccList, pButtonSeat)
end heTNewHandAnte

function heTBlinds pStateA
   local tStateA
   put heBetApply(pStateA, "bidSB", pStateA["sbSeat"], \
         min(pStateA["sb"], pStateA["stackBy"][pStateA["sbSeat"]])) into tStateA
   put heBetApply(tStateA, "bidBB", tStateA["bbSeat"], \
         min(tStateA["bb"], tStateA["stackBy"][tStateA["bbSeat"]])) into tStateA
   return tStateA
end heTBlinds

function heTAct pStateA, pSeatNum, pVerbAmt, pExpectErr, pLabel
   local tStateA
   put heBetApply(pStateA, "act", pSeatNum, pVerbAmt) into tStateA
   heTAssert pLabel, tStateA["err"], pExpectErr
   if tStateA["err"] is empty then
      return tStateA
   end if
   return pStateA
end heTAct

function heTDeltasTxt pDeltasA, pOccList
   local tOut, tSeatNum
   set the itemDelimiter to comma
   put empty into tOut
   repeat for each item tSeatNum in pOccList
      put tSeatNum & ":" & pDeltasA[tSeatNum] & "|" after tOut
   end repeat
   delete char -1 of tOut
   return tOut
end heTDeltasTxt

command heTestBettingRun
   local tStateA, tDeltasA, tRanksA
   put return & "-- 2. betting engine (spec 8.1) + settlement (8.3)" & return after gRpt
   set the itemDelimiter to comma

   put heTBlinds(heTNewHand(1, 2, "100,100,100", "1,2,3", 1)) into tStateA
   heTAssert "bet: preflop first to act is left of BB", tStateA["toAct"], 1
   put heTAct(tStateA, 1, "raise,3", "raise-below-minimum", "bet: raise under min rejected") into tStateA
   put heTAct(tStateA, 1, "raise,4", empty, "bet: min raise accepted") into tStateA
   put heTAct(tStateA, 2, "raise,5", "raise-below-minimum", "bet: re-raise under min rejected") into tStateA
   put heTAct(tStateA, 2, "raise,6", empty, "bet: re-raise at min accepted") into tStateA
   heTAssert "bet: raiseFull tracks the full raise", tStateA["raiseFull"], 2

   put heTBlinds(heTNewHand(1, 2, "100,13,100", "1,2,3", 1)) into tStateA
   put heTAct(tStateA, 1, "call,2", empty, "bet: limp accepted") into tStateA
   put heTAct(tStateA, 2, "call,1", empty, "bet: sb completes") into tStateA
   put heTAct(tStateA, 3, "check,0", empty, "bet: bb checks option") into tStateA
   heTAssert "bet: flop reached", tStateA["street"], "flop"
   put heTAct(tStateA, 2, "check,0", empty, "bet: flop check") into tStateA
   put heTAct(tStateA, 3, "bet,10", empty, "bet: flop bet 10") into tStateA
   put heTAct(tStateA, 1, "call,10", empty, "bet: flop call") into tStateA
   put heTAct(tStateA, 2, "allin,11", empty, "bet: under-raise all-in accepted") into tStateA
   heTAssert "bet: betCur moves to 11 on the under-raise", tStateA["betCur"], 11
   heTAssert "bet: raiseFull stays 10 after under-raise", tStateA["raiseFull"], 10
   put heTAct(tStateA, 3, "raise,25", "raise-not-reopened", "bet: bettor cannot re-raise under-raise") into tStateA
   put heTAct(tStateA, 3, "call,1", empty, "bet: bettor calls the extra") into tStateA
   put heTAct(tStateA, 1, "raise,25", "raise-not-reopened", "bet: caller cannot re-raise either") into tStateA
   put heTAct(tStateA, 1, "call,1", empty, "bet: caller calls the extra") into tStateA
   heTAssert "bet: street closes to turn", tStateA["street"], "turn"

   -- BB option: limps come back to the BB, who may RAISE its option, and the
   -- limpers must then respond (mirror of betting-kat case_bb_option -- the
   -- old harness only ever had the BB CHECK its option)
   put heTBlinds(heTNewHand(1, 2, "100,100,100", "1,2,3", 1)) into tStateA
   put heTAct(tStateA, 1, "call,2", empty, "opt: utg limps") into tStateA
   put heTAct(tStateA, 2, "call,1", empty, "opt: sb completes") into tStateA
   heTAssert "opt: action returns to the BB (option)", tStateA["toAct"], 3
   put heTAct(tStateA, 3, "raise,6", empty, "opt: BB raises its option") into tStateA
   heTAssert "opt: limpers must respond to the option raise", tStateA["toAct"], 1

   -- checked-around street + the out-of-turn rejection (mirror of betting-kat
   -- case_check_around -- the only out-of-turn pin, previously CI-only)
   put heTBlinds(heTNewHand(1, 2, "100,100,100", "1,2,3", 1)) into tStateA
   put heTAct(tStateA, 1, "call,2", empty, "chk: limp") into tStateA
   put heTAct(tStateA, 2, "call,1", empty, "chk: sb completes") into tStateA
   put heTAct(tStateA, 3, "check,0", empty, "chk: bb checks its option") into tStateA
   heTAssert "chk: flop opens on the sb", tStateA["toAct"], 2
   put heTAct(tStateA, 3, "check,0", "act-out-of-turn", "chk: acting out of turn is rejected") into tStateA
   put heTAct(tStateA, 2, "check,0", empty, "chk: flop check 1") into tStateA
   put heTAct(tStateA, 3, "check,0", empty, "chk: flop check 2") into tStateA
   put heTAct(tStateA, 1, "check,0", empty, "chk: flop check 3") into tStateA
   heTAssert "chk: a checked-around street advances", tStateA["street"], "turn"

   put heTBlinds(heTNewHand(1, 2, "100,50,20", "1,2,3", 1)) into tStateA
   put heTAct(tStateA, 1, "allin,100", empty, "pot: open shove") into tStateA
   put heTAct(tStateA, 2, "allin,50", empty, "pot: short call-allin") into tStateA
   put heTAct(tStateA, 3, "allin,20", empty, "pot: shorter call-allin") into tStateA
   heTAssert "pot: hand runs out", tStateA["phase"], "runout"
   put heBetApply(tStateA, "board", 0, 0) into tStateA
   put heBetApply(tStateA, "board", 0, 0) into tStateA
   put heBetApply(tStateA, "board", 0, 0) into tStateA
   heTAssert "pot: runout reaches showdown", tStateA["phase"], "showdown"
   put empty into tRanksA
   put "011413120900" into tRanksA[1]
   put "021104140000" into tRanksA[2]
   put "031413120000" into tRanksA[3]
   put heSettleOf(tStateA, tRanksA) into tDeltasA
   heTAssert "pot: main 60 to s3, side 60 to s2, 50 back to s1", \
         heTDeltasTxt(tDeltasA, tStateA["occ"]), "1:-50|2:10|3:40"

   put heTNewHand(1, 2, "100,100", "2,5", 2) into tStateA
   heTAssert "hu: button posts SB", tStateA["sbSeat"], 2
   heTAssert "hu: other seat posts BB", tStateA["bbSeat"], 5
   put heTBlinds(tStateA) into tStateA
   heTAssert "hu: button acts first preflop", tStateA["toAct"], 2
   put heTAct(tStateA, 2, "call,1", empty, "hu: button completes") into tStateA
   put heTAct(tStateA, 5, "check,0", empty, "hu: bb checks") into tStateA
   heTAssert "hu: non-button acts first postflop", tStateA["toAct"], 5

   put heTBlinds(heTNewHand(1, 2, "100,100", "1,2", 1)) into tStateA
   put heTAct(tStateA, 1, "raise,6", empty, "fw: open raise") into tStateA
   put heTAct(tStateA, 2, "fold,0", empty, "fw: fold") into tStateA
   heTAssert "fw: fold ends the hand", tStateA["phase"], "handdone"
   put empty into tRanksA
   put heSettleOf(tStateA, tRanksA) into tDeltasA
   heTAssert "fw: uncalled raise returned", heTDeltasTxt(tDeltasA, tStateA["occ"]), "1:2|2:-2"

   put heTBlinds(heTNewHand(1, 2, "100,100,100", "1,2,3", 1)) into tStateA
   put heTAct(tStateA, 1, "call,2", empty, "split: limp") into tStateA
   put heTAct(tStateA, 2, "call,1", empty, "split: sb completes") into tStateA
   put heTAct(tStateA, 3, "check,0", empty, "split: bb checks") into tStateA
   put heTAct(tStateA, 2, "bet,9", empty, "split: flop bet") into tStateA
   put heTAct(tStateA, 3, "call,9", empty, "split: flop call 1") into tStateA
   put heTAct(tStateA, 1, "call,9", empty, "split: flop call 2") into tStateA
   put heTAct(tStateA, 2, "check,0", empty, "split: turn check 1") into tStateA
   put heTAct(tStateA, 3, "check,0", empty, "split: turn check 2") into tStateA
   put heTAct(tStateA, 1, "check,0", empty, "split: turn check 3") into tStateA
   put heTAct(tStateA, 2, "check,0", empty, "split: river check") into tStateA
   put heTAct(tStateA, 3, "bet,2", empty, "split: river bet") into tStateA
   put heTAct(tStateA, 1, "call,2", empty, "split: river call 1") into tStateA
   put heTAct(tStateA, 2, "call,2", empty, "split: river call 2") into tStateA
   heTAssert "split: river aggressor shows first", heShowdownOrderOf(tStateA), "3,1,2"
   put empty into tRanksA
   put "041400000000" into tRanksA[1]
   put "041400000000" into tRanksA[2]
   put "011413120900" into tRanksA[3]
   put heSettleOf(tStateA, tRanksA) into tDeltasA
   heTAssert "split: odd chip to first winner after button", \
         heTDeltasTxt(tDeltasA, tStateA["occ"]), "1:6|2:7|3:-13"

   put heTNewHand(1, 2, "1,2", "4,6", 4) into tStateA
   put heBetApply(tStateA, "bidSB", 4, 1) into tStateA
   heTAssert "blind: short SB posts all-in", tStateA["allinBy"][4], "true"
   put heBetApply(tStateA, "bidBB", 6, 2) into tStateA
   heTAssert "blind: both blinds all-in -> runout", tStateA["phase"], "runout"
end heTestBettingRun

command heTestAnteRun
   -- antes are dead money: into the pot (handBy), NEVER the street bet, so a seat
   -- still owes the full blind. Mirror of betting-kat case_antes / conservation.
   local tStateA, tDeltasA, tRanksA, tSeatNum
   put return & "-- 3. antes (dead money) + chip conservation" & return after gRpt
   set the itemDelimiter to comma

   put heTNewHandAnte(1, 2, 1, "100,100,100", "1,2,3", 1) into tStateA
   repeat with tSeatNum = 1 to 3
      put heBetApply(tStateA, "bidAnte", tSeatNum, 1) into tStateA
   end repeat
   heTAssert "ante: dead money in the pot (s1 handBy)", tStateA["handBy"][1], 1
   heTAssert "ante: not on the street bet (s1 streetBy)", tStateA["streetBy"][1], 0
   put heTBlinds(tStateA) into tStateA
   heTAssert "ante: SB total = ante + small blind", tStateA["handBy"][2], 2
   heTAssert "ante: BB total = ante + big blind", tStateA["handBy"][3], 3
   put heTAct(tStateA, 1, "fold,0", empty, "ante: utg folds") into tStateA
   put heTAct(tStateA, 2, "fold,0", empty, "ante: sb folds") into tStateA
   heTAssert "ante: fold-around ends the hand", tStateA["phase"], "handdone"
   put empty into tRanksA
   put heSettleOf(tStateA, tRanksA) into tDeltasA
   heTAssert "ante: dead money folds into the winner's pot", \
         heTDeltasTxt(tDeltasA, tStateA["occ"]), "1:-1|2:-2|3:3"

   put heTNewHandAnte(1, 2, 5, "100,100,1", "1,2,3", 1) into tStateA
   repeat with tSeatNum = 1 to 3
      put heBetApply(tStateA, "bidAnte", tSeatNum, min(5, tStateA["stackBy"][tSeatNum])) into tStateA
   end repeat
   heTAssert "ante: short seat posts what it has", tStateA["handBy"][3], 1
   heTAssert "ante: short seat all-in for the ante", tStateA["allinBy"][3], "true"

   put heTNewHandAnte(5, 10, 2, "200,200,200", "1,2,3", 1) into tStateA
   repeat with tSeatNum = 1 to 3
      put heBetApply(tStateA, "bidAnte", tSeatNum, 2) into tStateA
   end repeat
   put heTBlinds(tStateA) into tStateA
   put heTAct(tStateA, 1, "allin,198", empty, "ante: s1 all-in 198") into tStateA
   put heTAct(tStateA, 2, "allin,198", empty, "ante: s2 all-in 198") into tStateA
   put heTAct(tStateA, 3, "allin,198", empty, "ante: s3 all-in 198") into tStateA
   heTAssert "ante: three-way all-in runs out", tStateA["phase"], "runout"
   put heBetApply(tStateA, "board", 0, 0) into tStateA
   put heBetApply(tStateA, "board", 0, 0) into tStateA
   put heBetApply(tStateA, "board", 0, 0) into tStateA
   put empty into tRanksA
   put "011413120900" into tRanksA[1]
   put "021104140000" into tRanksA[2]
   put "081400000000" into tRanksA[3]
   put heSettleOf(tStateA, tRanksA) into tDeltasA
   heTAssert "ante: winner scoops the 600 pot (each put in its whole 200)", \
         heTDeltasTxt(tDeltasA, tStateA["occ"]), "1:-200|2:-200|3:400"

   -- P0 regression pin (deep-dive): a blind-position seat that is short AFTER its
   -- ante must be posted from the POST-ante stack, which is exactly what heHandStart
   -- now caps by (gGame["state"]["stackBy"]). Seat 2 = SB, starts 55, ante 10 ->
   -- post-ante stack 45, so its all-in small blind is 45, not min(50, pre-ante 55).
   put heTNewHandAnte(50, 100, 10, "400,55,400", "1,2,3", 1) into tStateA
   repeat with tSeatNum = 1 to 3
      put heBetApply(tStateA, "bidAnte", tSeatNum, min(10, tStateA["stackBy"][tSeatNum])) into tStateA
   end repeat
   heTAssert "ante: short SB seat is short after its ante", tStateA["stackBy"][2], 45
   put heBetApply(tStateA, "bidSB", 2, min(50, tStateA["stackBy"][2])) into tStateA
   heTAssert "ante: short SB posts from the post-ante stack (heHandStart P0 fix)", tStateA["err"], empty
   heTAssert "ante: short SB is all-in for ante + short blind", tStateA["handBy"][2], 55
   -- and the OLD pre-ante cap (the bug the fix removes) is what the engine rejects:
   put heTNewHandAnte(50, 100, 10, "400,55,400", "1,2,3", 1) into tStateA
   repeat with tSeatNum = 1 to 3
      put heBetApply(tStateA, "bidAnte", tSeatNum, min(10, tStateA["stackBy"][tSeatNum])) into tStateA
   end repeat
   put heBetApply(tStateA, "bidSB", 2, min(50, 55)) into tStateA
   heTAssert "ante: a pre-ante blind cap is rejected (regression guard)", \
         tStateA["err"], "bidSB-wrong-amount"

   -- duplicate-post rejection (mirror of betting-kat case_duplicate_posts):
   -- phase stays "blinds" until the BB posts, so without the posted flags a
   -- transcript repeating a bidSB/bidAnte replayed clean AND audited clean
   put heTNewHandAnte(1, 2, 1, "100,100,100", "1,2,3", 1) into tStateA
   repeat with tSeatNum = 1 to 3
      put heBetApply(tStateA, "bidAnte", tSeatNum, 1) into tStateA
   end repeat
   put heBetApply(tStateA, "bidAnte", 1, 1) into tStateA
   heTAssert "ante: a repeated ante is rejected", tStateA["err"], "bidAnte-duplicate"
   put heBetApply(tStateA, "bidAnte", 4, 1) into tStateA
   heTAssert "ante: an ante from outside the hand is rejected", tStateA["err"], "bidAnte-wrong-seat"
   put heBetApply(tStateA, "bidSB", 2, 1) into tStateA
   heTAssert "ante: the first SB still posts clean", tStateA["err"], empty
   put heBetApply(tStateA, "bidSB", 2, 1) into tStateA
   heTAssert "ante: a repeated SB is rejected", tStateA["err"], "bidSB-duplicate"
end heTestAnteRun

command heTestLevelRun
   -- tournament blind schedule: pure level selection by hand number (heLevelFor).
   -- Mirror of betting-kat case_levels.
   local tLv
   put return & "-- 4. tournament blind levels (heLevelFor)" & return after gRpt
   put "1/2/0;2/4/0;3/6/0;5/10/0;10/20/0;15/30/0;25/50/0;50/100/10" into tLv
   heTAssert "level: hand 1 is level 1", heLevelFor(1, tLv, 8), "1,2,0"
   heTAssert "level: last hand of level 1", heLevelFor(8, tLv, 8), "1,2,0"
   heTAssert "level: first hand of level 2", heLevelFor(9, tLv, 8), "2,4,0"
   heTAssert "level: hand 20 is level 3", heLevelFor(20, tLv, 8), "3,6,0"
   heTAssert "level: hand 25 is level 4", heLevelFor(25, tLv, 8), "5,10,0"
   heTAssert "level: top level carries an ante", heLevelFor(57, tLv, 8), "50,100,10"
   heTAssert "level: clamps at the final level", heLevelFor(9999, tLv, 8), "50,100,10"
   heTAssert "level: every=1 advances each hand", heLevelFor(3, tLv, 1), "3,6,0"
   heTAssert "level: period 1 is level 1", heLevelForPeriod(1, tLv), "1,2,0"
   heTAssert "level: period 4 is level 4", heLevelForPeriod(4, tLv), "5,10,0"
   heTAssert "level: period clamps at the top", heLevelForPeriod(999, tLv), "50,100,10"
   heTAssert "level: count of the default schedule", heLevelCount(tLv), 8
end heTestLevelRun

function heTLegalAllAccepted pStateA, pSeatNum
   -- replay every line heBetLegal offers through heBetApply (the gate); returns
   -- "ok" iff all are accepted, else the first rejected action. bet/raise offer
   -- a MIN and a MAX (words 2 and 3) -- both must be accepted.
   local tMenu, tLine, tVerb, tRes
   put heBetLegal(pStateA, pSeatNum) into tMenu
   repeat for each line tLine in tMenu
      put word 1 of tLine into tVerb
      switch tVerb
         case "fold"
         case "check"
            put heBetApply(pStateA, "act", pSeatNum, tVerb & ",0") into tRes
            break
         case "call"
         case "allin"
            put heBetApply(pStateA, "act", pSeatNum, tVerb & comma & word 2 of tLine) into tRes
            break
         case "bet"
         case "raise"
            put heBetApply(pStateA, "act", pSeatNum, tVerb & comma & word 2 of tLine) into tRes
            if tRes["err"] is empty then
               put heBetApply(pStateA, "act", pSeatNum, tVerb & comma & word 3 of tLine) into tRes
            end if
            break
      end switch
      if tRes["err"] is not empty then
         return "rejected:" & tLine & "(" & tRes["err"] & ")"
      end if
   end repeat
   return "ok"
end heTLegalAllAccepted

command heTestLegalRun
   -- heBetLegal must offer exactly the actions heBetApply accepts (the gate).
   -- On-engine mirror of the legal-consistency fuzz in tools/logic-fuzz.py: for
   -- reachable states, every action heBetLegal offers is replayed through
   -- heBetApply and must be accepted. A bug here would show a player an illegal
   -- move or hide a legal one -- a fairness bug.
   local tStateA, tSeatNum
   put return & "-- 5. heBetLegal: every offered action is accepted (spec 8.1)" & return after gRpt
   set the itemDelimiter to comma
   -- preflop, 3-handed, 100 each, button 1: first-to-act faces the big blind
   put heTNewHand(1, 2, "100,100,100", "1,2,3", 1) into tStateA
   put heTBlinds(tStateA) into tStateA
   put tStateA["toAct"] into tSeatNum
   heTAssert "legal: preflop first-to-act menu is non-empty", \
         (heBetLegal(tStateA, tSeatNum) is not empty), "true"
   heTAssert "legal: every preflop action offered is accepted", \
         heTLegalAllAccepted(tStateA, tSeatNum), "ok"
   -- the next seat now faces a raise (re-raise decision)
   put heTAct(tStateA, tSeatNum, "raise,6", "", "legal: setup a raise to 6") into tStateA
   put tStateA["toAct"] into tSeatNum
   heTAssert "legal: every action offered facing a raise is accepted", \
         heTLegalAllAccepted(tStateA, tSeatNum), "ok"
   -- a short stack that cannot cover a full raise: menu still all-accepted
   put heTNewHand(1, 2, "3,100,100", "1,2,3", 1) into tStateA
   put heTBlinds(tStateA) into tStateA
   put tStateA["toAct"] into tSeatNum
   heTAssert "legal: short-stack menu is all accepted", \
         heTLegalAllAccepted(tStateA, tSeatNum), "ok"

   -- quick-bet sizing (heQuickAmountOf), mirror of betting-kat case_quick_amounts.
   -- v0.14.1 regression pin: FACING a bet, the pot raise-to must be
   -- betCur + (committed + owe) -- 2 + (3 + 2) = 7 with 1/2 blinds folded to the
   -- button. The old formula added the call a second time and offered 9.
   put heTNewHand(1, 2, "100,100,100", "1,2,3", 1) into tStateA
   put heTBlinds(tStateA) into tStateA
   heTAssert "quick: pot raise facing the BB is a true pot raise", \
         heQuickAmountOf(tStateA, 1, "pot"), 7
   heTAssert "quick: half-pot facing the BB", heQuickAmountOf(tStateA, 1, "half"), 4
   heTAssert "quick: min is the min legal raise-to", heQuickAmountOf(tStateA, 1, "min"), 4
   -- opening a street with nothing in front: a pot-sized BET is the pot itself
   -- (owe is 0 here, so this case never showed the bug -- it pins that the fix
   -- left it alone)
   put heTAct(tStateA, 1, "call,2", "", "quick: button calls") into tStateA
   put heTAct(tStateA, 2, "call,1", "", "quick: sb completes") into tStateA
   put heTAct(tStateA, 3, "check,0", "", "quick: bb checks to the flop") into tStateA
   heTAssert "quick: flop opened", tStateA["street"], "flop"
   heTAssert "quick: pot-sized opening bet is the pot", \
         heQuickAmountOf(tStateA, tStateA["toAct"], "pot"), 6
   heTAssert "quick: half-pot opening bet", \
         heQuickAmountOf(tStateA, tStateA["toAct"], "half"), 3
   -- clamped by the stack: a short seat's pot raise caps at all-in
   put heTNewHand(1, 2, "5,100,100", "1,2,3", 1) into tStateA
   put heTBlinds(tStateA) into tStateA
   heTAssert "quick: pot raise clamps to all-in on a short stack", \
         heQuickAmountOf(tStateA, 1, "pot"), 5

   -- integer-only wagers (mirror of betting-kat case_bad_amounts): a
   -- fractional target would mint chips in heSettleOf's div/mod accounting
   -- and a non-number would throw mid-arithmetic -- both engine-rejected
   put heTNewHand(1, 2, "100,100,100", "1,2,3", 1) into tStateA
   put heTBlinds(tStateA) into tStateA
   put heTAct(tStateA, 1, "raise,4.5", "act-bad-amount", "legal: fractional raise rejected") into tStateA
   put heTAct(tStateA, 1, "raise,abc", "act-bad-amount", "legal: non-numeric raise rejected") into tStateA
   put heTAct(tStateA, 1, "raise,4", empty, "legal: the integer raise still lands") into tStateA
end heTestLegalRun

function heTButtonSchedule pLiveList, pLastBB
   -- returns "button,SB,BB" the way the shell schedules a hand, via the pure
   -- heScheduleButton + heBetNewHand derivation
   local tBtn, tStateA, tStacksA, tSeatNum
   set the itemDelimiter to comma
   repeat for each item tSeatNum in pLiveList
      put 100 into tStacksA[tSeatNum]
   end repeat
   put heScheduleButton(pLiveList, pLastBB) into tBtn
   put heBetNewHand(1, 2, 0, tStacksA, pLiveList, tBtn) into tStateA
   return tBtn & comma & tStateA["sbSeat"] & comma & tStateA["bbSeat"]
end heTButtonSchedule

command heTestScheduleRun
   local tSeq, tLastBB, tRound, tOne
   set the itemDelimiter to comma
   put return & "-- 6. blind schedule (dead-button; TDA rule 10)" & return after gRpt
   -- 3-handed no-bust: button and BB each advance one seat per hand
   put empty into tSeq
   put 0 into tLastBB
   repeat with tRound = 1 to 4
      put heTButtonSchedule("1,2,3", tLastBB) into tOne
      put tOne & ";" after tSeq
      put item 3 of tOne into tLastBB
   end repeat
   delete char -1 of tSeq
   heTAssert "sched: 3-handed no-bust rotation", tSeq, "1,2,3;2,3,1;3,1,2;1,2,3"
   -- seat 1 busts after button=1/BB=3: heads-up must not post BB twice for seat 3
   heTAssert "sched: bust-to-HU no double BB", heTButtonSchedule("2,3", 3), "3,3,2"
   -- seats 2,3 bust after button=1/BB=3: BB advances to the survivor (seat 4)
   heTAssert "sched: double-bust BB advances to survivor", heTButtonSchedule("1,4,5,6", 3), "6,1,4"
end heTestScheduleRun

command heTestShuffleRun
   local tDeckList, tDealA, tPos, tSeenA, tDup, tSecond
   local tRangeN, tDrawPair, tDrawVal, tDrawState, tOutOfRange
   set the itemDelimiter to comma
   put return & "-- 7. integer shuffle (binary-free deal)" & return after gRpt

   heTAssert "draw: minstd step is deterministic", heRngStep(1), 16807
   heTAssert "draw: uniform in range returns value,state", item 1 of heDrawInt(1, 52) is a number, "true"
   -- draw bounds, actually checked: for every range 2..52, a chained draw
   -- lands in 1..n (mirror of shuffle-kat's range loop -- the old assert only
   -- checked "is a number", which a 0 or 53 would have passed)
   put 0 into tOutOfRange
   put 1 into tDrawState
   repeat with tRangeN = 2 to 52
      put heDrawInt(tDrawState, tRangeN) into tDrawPair
      put item 1 of tDrawPair into tDrawVal
      put item 2 of tDrawPair into tDrawState
      if tDrawVal < 1 or tDrawVal > tRangeN or tDrawVal is not trunc(tDrawVal) then
         add 1 to tOutOfRange
      end if
   end repeat
   heTAssert "draw: every chained draw lands in 1..n (n = 2..52)", tOutOfRange, 0

   -- pinned deck for a fixed seed (mirrored in tools; MINSTD from seed 1)
   put heShuffleDeck(1) into tDeckList
   heTAssert "shuffle: seed 1 matches the pinned deck", heTNamesOf(tDeckList), kKatSeed1Deck

   -- permutation property: all 52 present, none twice
   put 0 into tDup
   repeat with tPos = 1 to 52
      if tSeenA[item tPos of tDeckList] is "true" then
         add 1 to tDup
      end if
      put "true" into tSeenA[item tPos of tDeckList]
   end repeat
   heTAssert "shuffle: seed 1 deck is a permutation of 52", (tDup is 0) and (the number of items of tDeckList is 52), "true"

   -- determinism: same seed -> same deck
   put heShuffleDeck(20260712) into tSecond
   heTAssert "shuffle: same seed reproduces the deck", heShuffleDeck(20260712), tSecond

   -- deal assignment on the pinned deck (3 seats, button 1 -> order 2,3,1)
   put heDealAssign(tDeckList, "1,2,3", 1) into tDealA
   heTAssert "deal: seat 1 gets cards 3 and 6 off the top", \
         heTNamesOf(tDealA["holesBy"][1]), (heCardName(item 3 of tDeckList)) & comma & (heCardName(item 6 of tDeckList))
   heTAssert "deal: flop is deck 8-10 after two rounds + burn", \
         heTNamesOf(tDealA["flopList"]), \
         (heCardName(item 8 of tDeckList)) & comma & (heCardName(item 9 of tDeckList)) & comma & (heCardName(item 10 of tDeckList))

   -- keyed-stream shuffle CORE, cross-checked WITHOUT SodiumXT: feed the fixed
   -- synthetic hex stream (tools/protocol-kat.py SYNTH_STREAM) straight through
   -- the rejection-sampling draw + Fisher-Yates and compare to the pinned deck.
   -- This pins heDrawUniform (modulo-bias/off-by-one) + heShuffleFromStreamHex
   -- on every engine, even one with no crypto installed (that is exactly why
   -- SYNTH_STREAM exists -- it needs no hashing).
   heTAssert "shuffle: synthetic keyed-stream deck (no crypto)", \
         heTNamesOf(heShuffleFromStreamHex(kKatSynthStream)), kKatSynthDeck
end heTestShuffleRun

function heTKatLog pTamper
   -- canned hotseat session, plain-text transcript (binary-free): holes
   -- s1=3d5d s2=Ac5h s3=KcKh, board 3h2h5c4hTc; folds to 442/394/364
   local tLog
   put empty into tLog
   put heLogLine(0, "table", "cfg", "sb=1,bb=2,seats=1|2|3,stacks=400|400|400,button=1") & return after tLog
   put heLogLine(1, "table", "handStart", "seats=1|2|3,button=1") & return after tLog
   put heLogLine(1, "table", "holeDeliver", "seat=1,cards=3d|5d") & return after tLog
   put heLogLine(1, "table", "holeDeliver", "seat=2,cards=Ac|5h") & return after tLog
   put heLogLine(1, "table", "holeDeliver", "seat=3,cards=Kc|Kh") & return after tLog
   put heLogLine(1, "seat2", "bidSB", "amount=1") & return after tLog
   put heLogLine(1, "seat3", "bidBB", "amount=2") & return after tLog
   put heLogLine(1, "seat1", "act", "verb=raise,amount=6") & return after tLog
   put heLogLine(1, "seat2", "act", "verb=call,amount=5") & return after tLog
   if pTamper is "badact" then
      put heLogLine(1, "seat3", "act", "verb=call,amount=7") & return after tLog
   end if
   put heLogLine(1, "seat3", "act", "verb=call,amount=4") & return after tLog
   put heLogLine(1, "table", "board", "street=flop,cards=3h|2h|5c") & return after tLog
   put heLogLine(1, "seat2", "act", "verb=check,amount=0") & return after tLog
   put heLogLine(1, "seat3", "act", "verb=bet,amount=10") & return after tLog
   put heLogLine(1, "seat1", "act", "verb=call,amount=10") & return after tLog
   put heLogLine(1, "seat2", "act", "verb=fold,amount=0") & return after tLog
   put heLogLine(1, "table", "board", "street=turn,cards=4h") & return after tLog
   put heLogLine(1, "seat3", "act", "verb=check,amount=0") & return after tLog
   put heLogLine(1, "seat1", "act", "verb=check,amount=0") & return after tLog
   put heLogLine(1, "table", "board", "street=river,cards=Tc") & return after tLog
   put heLogLine(1, "seat3", "act", "verb=bet,amount=20") & return after tLog
   put heLogLine(1, "seat1", "act", "verb=call,amount=20") & return after tLog
   -- 2e display choice: the winner shows, the caller mucks its losing kings
   -- (annotated "(mucked)" in the history line; mirrored in fold-kat)
   put heLogLine(1, "seat1", "show", "seat=1") & return after tLog
   put heLogLine(1, "seat3", "muck", "seat=3") & return after tLog
   if pTamper is "settle" then
      put heLogLine(1, "table", "settle", "deltas=1:52|2:-16|3:-36") & return after tLog
   else
      put heLogLine(1, "table", "settle", "deltas=1:42|2:-6|3:-36") & return after tLog
   end if
   return tLog
end heTKatLog

function heTKatAnteLog
   -- canned ante session (mirror of fold-kat ante_transcript): 3-handed, ante
   -- 2 each, blinds 1/2, folds to the BB. Pot = 3 antes (6) + SB (1) + BB (2)
   -- = 9; the fold must re-derive the settle from the bidAnte lines alone --
   -- if it ignored antes the logged deltas would mismatch on replay.
   local tLog
   put empty into tLog
   put heLogLine(0, "table", "cfg", "sb=1,bb=2,ante=2,seats=1|2|3,stacks=400|400|400,button=1,levelMode=off,speed=normal") & return after tLog
   put heLogLine(1, "table", "handStart", "seats=1|2|3,button=1") & return after tLog
   put heLogLine(1, "table", "holeDeliver", "seat=1,cards=3d|5d") & return after tLog
   put heLogLine(1, "table", "holeDeliver", "seat=2,cards=Ac|5h") & return after tLog
   put heLogLine(1, "table", "holeDeliver", "seat=3,cards=Kc|Kh") & return after tLog
   put heLogLine(1, "seat1", "bidAnte", "amount=2") & return after tLog
   put heLogLine(1, "seat2", "bidAnte", "amount=2") & return after tLog
   put heLogLine(1, "seat3", "bidAnte", "amount=2") & return after tLog
   put heLogLine(1, "seat2", "bidSB", "amount=1") & return after tLog
   put heLogLine(1, "seat3", "bidBB", "amount=2") & return after tLog
   put heLogLine(1, "seat1", "act", "verb=fold,amount=0") & return after tLog
   put heLogLine(1, "seat2", "act", "verb=fold,amount=0") & return after tLog
   put heLogLine(1, "table", "settle", "deltas=1:-2|2:-3|3:5") & return after tLog
   return tLog
end heTKatAnteLog

function heTFoldTxt pFoldA
   return pFoldA["stacksBy"][1] & "/" & pFoldA["stacksBy"][2] & "/" & pFoldA["stacksBy"][3] \
         & " hand=" & pFoldA["handNum"] & " errs=[" & pFoldA["errors"] & "]"
end heTFoldTxt

command heTestFoldRun
   local tFoldA, tFoldB, tShortLog, tRiverLine
   put return & "-- 8. transcript fold: determinism + replay-as-audit" & return after gRpt
   put heFoldTranscript(heTKatLog(empty)) into tFoldA
   heTAssert "fold: canned session settles to the pinned stacks", \
         heTFoldTxt(tFoldA), "442/394/364 hand=1 errs=[]"
   put heFoldTranscript(heTKatLog(empty)) into tFoldB
   heTAssert "fold: folding twice is identical", heTFoldTxt(tFoldB), heTFoldTxt(tFoldA)
   heTContains "fold: per-hand trace recorded", tFoldA["trace"], "hand 1: 1:42|2:-6|3:-36"
   heTContains "history: board, pot, and winner recorded", tFoldA["history"], \
         "hand 1: board 3h 2h 5c 4h Tc; pot 78; winner seat 1"
   heTContains "history: showdown names the winning hand", tFoldA["history"], "1=3d 5d two pair"
   heTContains "history: showdown names the losing hand too", tFoldA["history"], "3=Kc Kh one pair"
   heTContains "history: a mucked hand is annotated, not hidden (2e)", \
         tFoldA["history"], "3=Kc Kh one pair (mucked)"
   heTContains "history: settlement marked verified on replay", tFoldA["history"], "settle-verified"
   put heFoldTranscript(heTKatLog("settle")) into tFoldA
   heTContains "history: tampered settle shows MISMATCH not verified", tFoldA["history"], "settle-MISMATCH"
   put heFoldTranscript(heTKatLog("settle")) into tFoldA
   heTContains "fold: tampered settle line is caught", tFoldA["errors"], "settle-mismatch"
   put heFoldTranscript(heTKatLog("badact")) into tFoldA
   heTContains "fold: wrong-amount action rejected on replay", tFoldA["errors"], "engine-rejected"

   -- a truncated transcript (river board line deleted before a contested
   -- settle) is NAMED and skipped, never a mid-audit throw (the heIsCardList
   -- guard; mirror of fold-kat's truncated-board case)
   put heTKatLog(empty) into tShortLog
   put heLogLine(1, "table", "board", "street=river,cards=Tc") into tRiverLine
   replace tRiverLine & return with empty in tShortLog
   put heFoldTranscript(tShortLog) into tFoldA
   heTContains "fold: a truncated board is named, not a crash", tFoldA["errors"], "settle-bad-cards"

   -- ante transcript (mirror of fold-kat ante_transcript): the settle is
   -- re-derived from the bidAnte lines alone
   put heFoldTranscript(heTKatAnteLog()) into tFoldA
   heTAssert "fold: ante session settles to the pinned stacks", \
         heTFoldTxt(tFoldA), "398/397/405 hand=1 errs=[]"
   heTContains "fold: ante settle verified on replay", tFoldA["history"], "settle-verified"

   -- deep-dive (OXT-pass finding): the online lobby and the hotseat game share
   -- gGame["log"] in two incompatible formats -- a 4-field hotseat line vs a
   -- 10-field signed wire. A hotseat log clobbered by an online create/join folds
   -- to pot 0 / settle-MISMATCH (no hotseat cfg -> no stakes/stacks). heBtnLeave
   -- now starts a fresh hotseat table whenever heLogIsCleanHotseat is false; pin
   -- its recognition of a clean hotseat log vs a wire-led / empty one.
   heTAssert "log: a hotseat cfg-led log is recognized as clean", \
         heLogIsCleanHotseat(heLogLine(0, "table", "cfg", "sb=1,bb=2,ante=0,seats=1|2,stacks=400|400,button=1") \
         & return & heLogLine(1, "table", "handStart", "seats=1|2,button=1")), true
   heTAssert "log: a wire-envelope-led log is NOT a clean hotseat log", \
         heLogIsCleanHotseat("1" & tab & "aa" & tab & "0" & tab & "bb" & tab & "cfg" & tab & "cc" \
         & tab & "dd" & tab & "1" & tab & "ee" & tab & "ff"), false
   heTAssert "log: an empty log is not a clean hotseat log", heLogIsCleanHotseat(empty), false
end heTestFoldRun
