# REMAINING-WORK.md — the suite's consolidated punch list

**Compiled 2026-08-15** from a full-tree audit at commit `2d49729`, then revised
the same day for the holde-em fold (`159a5a3`, the standalone hold-em repository
folded home as the tenth member at v0.18.0). Every item cites the file that
establishes it; each member's own `README.md` / `CLAUDE.md` stays the authority
for its layer — this document is an INDEX of the open work, not a second ledger.
Per the honesty convention it applies to itself: this is a dated, point-in-time
audit. When an item closes, strike it here in the same change (the truth-sync
discipline), and when this file's date grows old, re-audit or retire it rather
than trust it.

**CORRECTION (2026-08-15, wave 4): "exhausted" was true at this document's
ITEM granularity, not absolutely.** With sparse OXT access the right lens is
"what can the tree gain headlessly", and under it more remains: the ladder
continues below the audited items (Hold'em 2e-remainder + Phase 3 oracle;
the SodiumXT DLEQ/batch surface as ABI 9; then 4d/4e's pure adversarial
harness and Phase 5's DLEQ proofs), the 720p re-layout is designable
statically with only the confirming eye left to the engine, and preparation
multiplies engine time (the runbook's sparse-access session plan; decision
briefs for the E section). Wave 4 is executing these; strikes land per
chunk.

**THE ENGINE-FREE COLUMN WAS DECLARED EXHAUSTED (2026-08-15, waves 1-3) - see the correction above.** Between the
morning audit and this line, everything in this document that could be
finished without an OXT engine, a second machine, a Tor daemon, a Mac, or an
owner decision WAS finished, committed chunk by chunk with its gates green:
the holde-em fold; SodiumXT ABI 8 (ristretto255, four binaries rebuilt);
coinxt WIF; nocloud's redirect hole and ETag/304 dedup; the family template
sync + drift gate; Model C for DHT-Channels (plan Phases 0/2/3); the ONIONXT
Phase 4 docs; riptide's onion serving, phase-6 sync payload, phase-5 typing
lane, and profileMeta; holde-em's Level 2 deal algebra (4a-4c) and 2f onion
tables; the checker union (checks 13-21, 78 latent traps fixed fleet-wide,
the idioms gate retired); the hygiene sweep; and the consolidation path
sweep. Every one of those builds is "verified statically" with machine proof
(KATs, goldens, mirrors, fixtures, coverage 393/411) and is listed in its
member's own ledger with exactly what its engine pass owes. What remains in
this file is now ONLY: the B-section verification backlog (the runbook's
sessions), the macOS/release lanes (C), the harness-fold integrations that
themselves want an engine in the same change (C.2, C.4), the E-section owner
decisions, and the A-section items that are genuinely engine-era or
owner-gated (the 720p re-layout, Schnorr/Taproot, cnx_memzero's ABI ripple,
nocloud Phase 3's contract questions, box2dxt's polish passes, and Hold'em's
2e-remainder/3/4d-f/5).

**WAVES 4-5 CLOSED THE LADDER (2026-08-16).** After the correction above,
wave 4 landed the sparse-access session plan (the runbook's new opening
section: the whole backlog as five resource-keyed sessions, ~5 x 3h + two
platform boxes), SodiumXT ABI 9 (the DLEQ/batch algebra, four binaries),
and holde-em's 2e remainder + Phase 3 oracle; wave 5 landed holde-em 4d/4e
+ the Phase 5 DLEQ proofs (a wrong unmask step is now refused instantly,
soundness pinned three ways), riptide's channel-2 settlement (a pointer
record at the proven torrent rail - the design, recorded), nocloud Phase 3
(:param routes built against the recorded contract questions), and
docs/OPEN-DECISIONS.md (21 owner briefs, most-blocking first - it found
five open decisions this file's E section missed and two E entries already
decided). Suite coverage 401/419; protocol-kat 105 pins; the full gate set
green. The headless ladder is now at its TRUE ceiling: what remains needs
an engine (the runbook's S1-S4 sessions), a platform box (S5), a human
(Phase 5's hostile review + soak), or an owner's five minutes on a brief.

**THE LAST THREE HEADLESS ITEMS CLOSED (2026-08-16, commits `55f9130` and
`6372cc8`).** A re-ask after the waves-4-5 banner found three items that were
still genuinely finishable without an engine, two of them owed by earlier
banners: Hold'em's 2e LIVENESS remainder (the act-timer/time-bank/sit-out/
late-join/redial list the v0.21.0 change recorded as open - now built to
spec 9 with the timer lengths riding the signed cfg, timeouts as fields on
the existing act/bid wires so a pre-liveness client fails visibly rather
than downgrading, transcript-derived bank state, and the onion redial
ordered under the election watchdog; protocol-kat 114 pins, harness
section 20, v0.23.0), the 720p RE-LAYOUT this document's correction
promised (1024x640 by rect arithmetic - 51 rects in budget, 43-rect
disjointness set pairwise disjoint - and the `check-stack-size.py` SKIP
entry REMOVED, so the gate now holds holde-em like every other stack; the
confirming eye is the OXT pass's), and coinxt's cnx_memzero (ABI 5, every
`.lcb` allocation wiped before free, a real throw-path leak fixed en
route, all four non-mac binaries rebuilt with the Windows-bar deviation
RECORDED in the member's CLAUDE.md). Items A.3 and A.12 are struck below;
A.1 is rewritten to its as-built state. The ceiling claim of the previous
banner now holds without residue: everything left in this file needs an
engine, a second machine, a Tor daemon, a platform box, a human review,
or an owner decision.

**A REVIEW OF THAT WORK FOUND 14 DEFECTS, AND ALL 14 ARE FIXED (2026-08-16,
commits `510f904` .. `1a2c9c1`).** The banners above record what was BUILT; this
one records what reading it found, because a punch list that only ever grows
green is not being read. A code review of the day's own pull request returned
thirteen findings, and CI had already caught a fourteenth. Ten were in the
Hold'em liveness layer written hours earlier - including two that made its
written contracts false (a mid-redial dial failure cancelled the election
watchdog, so the election could never conclude; and a client that caught up by
full replay diverged permanently, which the KNOWN EDGE note claimed a reconnect
would heal). A cluster of four shared one root cause worth naming: consensus
state was written around a fold that can refuse, and since every client folds
identically, that wrote WRONG CONSENSUS rather than a divergence any transcript
check could detect. The other four were coinxt's export gate silently
fail-opening for exactly the Windows DLLs it is the only check for, a wipe error
that could displace a real status, CI asserting a hardcoded ABI that the memzero
bump invalidated, and this document's own overstated claim about
`check-stack-size.py`.

Three things were done that the findings did not ask for, because the review
exposed the SHAPE of the problem rather than one instance: sodiumxt's committed
binaries are now EXECUTED in CI against published RFC 9496 vectors (they never
had been, and they are what the Level 2 deal binds to); the runbook's ABI
numbers were swept current and its inventory extended through wave 5, since a
tester following it faithfully would have skipped everything built in the last
two days; and the 720p arithmetic became a committed gate instead of an
attestation. Full detail in each member's ledger.

**THE FIRST OWNER DECISION CAME BACK, AND IT WAS A BUILD (2026-08-16, commit
`affdf1c`).** D-01 - the most-blocking of the 21 briefs - was decided "vendor
it", and coinxt shipped BIP-340 Schnorr and the BIP-341 Taproot tweak the same
day at ABI 6, closing A.10. Two things are worth carrying out of it. First, the
brief NAMED THE WRONG LIBRARY: it said `secp256k1-zkp` because coinxt's own
notes did, and nobody checked until the work started - upstream
bitcoin-core/secp256k1 carries the modules BIP-340 needs, so the decision was
cheaper than the brief priced it (the canonical library instead of a fork, and
no second build system, since coinxt vendors by copying pinned sources).
A brief is only as good as its evidence, and this one inherited an assumption
rather than testing it. Second, the brief's own RECOMMENDATION - hold the
deferral - lost, correctly: it argued from timing ("no consumer needs Taproot
spends today"), and timing is the owner's to weigh, not the suite's. Both are
recorded in D-01 rather than tidied away.

**THE SELF-TEST NOW REACHES 76% MORE OF THE SUITE (2026-08-16, commit
`ef73172`).** Asked to make the self-test "test as much as it possible can", the
audit found the limit was not depth inside sections but WHICH MEMBERS FOLD AT
ALL: seven did, and box2dxt's 7000-line harness sat unfolded, so the suite paste
had never touched a line of the physics or game-Kit surface. Folding it took
coverage **411/429 -> 724/742**. Two things came out of it worth carrying: a
latent paste-time bug (the harness carries a verbatim copy of the b2k Kit, so a
naive fold would have defined 313 handlers twice - found here rather than on an
engine), and a coverage ratchet that failed at 103/313 because many Kit handlers
RUN on every test while no test writes their name down. **holde-em folded the
SAME DAY** (commit `7f55839`) — the sentence that stood here said it "remains
unfolded pending five named blockers", and all five were cleared hours later;
it is the ninth harness, at 380 folded handlers. nocloud has no script harness
and is correctly out of scope.

**The short version — REWRITTEN 2026-08-17, and every claim it used to make was
stale.** It said one big build was unstarted (Model C) — Model C is built, 629
onion/Tor references in the Channels stack. It said a code layer was missing from
a Riptide phase (onion serving) — `rsAnonFeedPage`, `rsAnonPrekeyBody` and
`rsAnonAcceptDm` all exist. It said holde-em's oracle and mental-poker phases were
open — Phase 3, the 4a-4e Level 2 layer and Phase 5's DLEQ proofs all shipped.

What is actually true now: **nothing large is unstarted.** What is BUILT waits on
the runbook's five resource-keyed sessions (S1 one machine; S2 plus a tor daemon;
S3 two machines; S4 two machines plus tor; S5 a Mac or a Windows box); the macOS
binaries stopped being a release gap on 2026-08-27, when release run 12 landed
every member's universal dylib, leaving the mac ENGINE pass as ordinary S5 work. What remains HEADLESS is no longer
unbuilt features but **measurement**: two layers ship with no ratchet at all
(box2dxt's raw `.lcb`, holde-em's `he*` surface), and the gates that report on
the rest have been found overstating twice in two days. See
`docs/HEADLESS-BACKLOG-2026-08-17.md`, which is the live index for that work;
this file stays the ledger.

> **Annotated 2026-08-19, not rewritten** (the paragraph above is dated
> 2026-08-17 and was written before commit `0a298c5` landed the same day).
> "Two layers ship with no ratchet at all" is now one and a half: holde-em's
> `he*` surface HAS a ratchet - built, measuring, and ADVISORY rather than
> armed, see C.4 - while box2dxt's raw `.lcb` script side is still genuinely
> unratcheted. Its C side is no longer unmeasured either; gcov puts the smoke
> test at 53 -> 194 of 370 exports entered. *(2026-08-23: 370 of 370 -
> entered, not exhausted; box2dxt/CLAUDE.md carries the dated record.)*

---

**SUPERSEDED AGAIN 2026-08-24 - the record grew by a fifth and stayed green.**
A Windows x86_64 pass (OXT 9.6.3, NT 10.0) ran the current paste end to end:
**2,373 passed, 0 failed, 3 skipped, 2,376 total** - the three skips all
deliberate and explained in the report (nostrxt's relay layer twice, which is
not in the paste by design, and onionxt's private oxh* layer, which lives in
the demo). First engine contact for: the WHOLE nostrxt member (274/274 - every
engine-semantics pin the headless interpreter models, confirmed on the real
engine), coinxt's BIP-341 section (all 12 checks: both sighash paths, the
tree, the control block, the refusals), sodiumxt's ABI-10 sxChaCha20IetfXor
(7/7 - and on Windows, which is also the mingw-cross x86_64 DLL's first
execution proof at ABI 10), holde-em's Level-2 batch mask fast path ("batch
fast path and per-point fallback agree byte-for-byte") at harness v42
(584/0), and riptide's kind-C chunked-post rail and BTXO receive path
(391/0). The ABI-10 preflight ran first and did its job - all six members
LOADED at expected ABIs. The same day the nostrxt DEMO opened green (boot self-check 9/9,
first open ever) and ran its LIVE leg: a real TLS websocket to wss://nos.lol,
a kind-1 note signed, published, and the relay's ok-true received - the relay
layer's connect/publish path is live-proven; its REQ/subscribe receive leg,
the two-machine legs, the live-tor legs, and this paste generation on Linux
remain open.

**SUPERSEDED 2026-08-20 - the record is now a WHOLE-RUN one.** A Windows pass
that day finished the suite paste end to end: **1,981 passed, 0 failed, 1
skipped, 1,982 total**, of which **1,868 are folded member checks** (sodiumxt
99, onionxt 61, coinxt 278, torrentxt 101, enetxt 34, datachannelxt 39, box2dxt
375, riptide 338, holde-em 543). Two things make it a different KIND of result
rather than a bigger number. It reached the end: both live loopbacks negotiated
and delivered, the 60000-byte budget was checked on both transports, SCTP
cleared its 16 KiB floor, and teardown released the ENet hosts, the WebRTC peers
and THE libtorrent session. And it settled runbook row 13 - riptide's phase-6
LAN sync records, the phase-7 serving seams, and all three `rsBytesAreUtf8`
checks that were RED on 2026-08-15. The `1 skipped` is not a miscount: riptide's
2 and holde-em's 5 are printed on a second line their own harnesses word as
prose, which `stMergeReturned` deliberately refuses to parse (its comment says
why); onionxt's 1 is inline and merges. The 2026-08-17 record below is kept
verbatim as the dated account of the fold's first compile.

**THE 2026-08-17 ENGINE PASS: THE LARGEST GREEN RUN THIS PROJECT HAS HAD.**
Windows x86_64, NT 10.0, OXT 9.6.3. **1,836 folded member checks, ZERO
failures, 7 skips** - every skip a live-transport or daemon leg no single
machine can run. The previous best was 617 folded checks (2026-08-13), so this
is roughly a threefold increase, and it is the first run in which every one of
the nine folded harnesses was green at once. All six packaged extensions loaded
at exactly the ABI their guard expects.

Per member: holde-em 538, box2dxt 374, riptide 338, coinxt 278, torrentxt 101,
sodiumxt 99, onionxt 61, datachannelxt 26, enetxt 21.

**What it closed, all of it shipped between 08-15 and 08-17 and never before
run:** coinxt's BIP-340 Schnorr and BIP-341 Taproot tweak (ABI 6), coinxt WIF,
`cnx_memzero`'s `.lcb` call sites, and SodiumXT's ristretto255 at both ABI 8 and
ABI 9. Every marshalling question `coinxt/CLAUDE.md` recorded as owed came back
answered, including the one never proven before: an EMPTY `Data` reaching the
shim as length 0 in an OPTIONAL argument slot.

**It also confirmed all five defects fixed by READING earlier the same day**,
each by the check written for it - onionxt's loopback fail-open (`the guard
refuses an empty host (it used to accept one)`), torrentxt's three destructive
refusal legs plus `btAddMagnet`, datachannelxt's embedded-NUL refusal and exact
error codes, box2dxt's duck rebuild keeping its collision filter, and holde-em's
election skipping a sitting-out seat. **And one the new coverage ratchet found
hours before the run**: `heHandStart` had survived only inside a test LABEL, and
its real check passes.

`tests/preflight.livecodescript`, written that day and never executed, ran first
and did its job: six LOADED rows in about a minute.

**What it did NOT close**, and this list is the honest remainder: the 7 skips
(riptide's anon onion create + serving; holde-em's live onion table,
three-machine oracle round, onion-hosted oracle, live timed table, live tor
redial), every two-machine leg (S3/S4), the Tor evening (S2), the macOS and
Windows-package gaps (S5/C.1), and the async loopbacks that stay deliberately
unfolded. Section B's live legs are untouched by this run except where struck
below.

---

**THE 2026-08-18 LINUX PASS: THE FIRST RUN THIS PROJECT HAS HAD ON LINUX, AND
IT PAID FOR ITSELF IN DEMOS RATHER THAN IN HARNESS CHECKS.** Named for where it
started, not for where it ended: a SECOND report came back from Windows the same
day, and `docs/OXT-ENGINE-NOTES.md` 6.6 carries both - including the fact that
the Windows narrowing (`Narrowed 2026-08-18 (second report, Windows)`, which
moved the datachannel throw out of the dispatch and into `_ensureDrain`) **did
not hold**; 6.7 closed the entry with the dispatch after all, and the narrowing
is left in place as the reasoning of the day rather than struck, because an
inference from an LCB line number is exactly the kind of evidence this file
teaches you to date and keep.

**No suite-wide check total is recorded in any commit from this run, so none is
quoted here.** What IS recorded is one member's: box2dxt's own harness went
**373/374 at v29** - the run's only failure, per commit `597ce0c` - having been
374/374 on Windows x86_64 the day before, which is the figure the 08-17 banner
above carries. The check was the harness being wrong about the engine, not the
Kit: `the playLoudness` does not read back exactly on every platform
(OXT-ENGINE-NOTES 5.4). It is now two self-diagnosing assertions plus a printed
observation, and **harness v30 has one assertion MORE than v29**, so a v30 total
is not comparable to the v29 374/374 figure - and no v30 total has been observed
on any platform.

**What the run found is best named by ENTRY rather than by count**, because a
count of it has been wrong twice: the session reported three demo symptoms, the
tree files four defects behind them, and a fifth entry filed from this pass was
reclassified the following day and is no longer one. The four, all carrying
OBSERVED evidence and all in `docs/OXT-ENGINE-NOTES.md` - three runtime, one a
compile error met at paste time - are: **1.7**, `the
number of keys of X` does not parse - `keys` is not a chunk, so the engine reads
`keys of X` as an OBJECT expression - nine occurrences across `enet-lan-chat`,
`riptide-social` and `torrent-rp1-chat`, every one on a path no engine run had
ever reached, while the correct spelling already stood in fifteen files including
three harnesses that had run green; **1.6**, two script-level declarations of one
name is a HARD compile error, found the moment the demos began carrying their own
libraries and a demo's `local sPolling` met the helper's; **6.4**, an EMPTY value
into a typed `.lcb` parameter is a THROW and not a no-op - `enet-lan-chat`'s
teardown handing empty to `enHostDestroy(in pHost as Integer)`, which killed the
poll chain and left the demo silently dead; and **6.7**, an event name and a
handler name share ONE xTalk message namespace - the datachannel root cause, in
which the emitted event `dcLocalDescription` collided with the public getter of
the same name, so `datachannel-loopback`'s `on dcLocalDescription` had never
fired once since the day it was written and `getting-started.md` taught the same
unreachable shape (the EVENT is renamed to `dcLocalDescriptionReady`; the pump
maps the legacy name so an app built against an older package still works).
**5.3 is deliberately NOT in that list**: it was filed OBSERVED from this pass
and CORRECTED to DOCUMENTED on 2026-08-19, because its throw was traced to the
argument evaluated at the call site - which is entry 1.7's defect, in the caller,
never reaching the handler the entry blamed.

Each of the four has a NEW gate, which is the point of recording the pass here at
all: the unified checker's LCS antipattern set (1.7, fixtures for both
spellings), `tools/test-demo-embeds.py` and `tools/sync-demo-embeds.py`'s
collision detector (1.6), `tools/check-lcb-call-types.py` (6.4) and its check 4
(6.7, which refuses any future event-name/handler-name collision).
`tools/check-timer-stack-pin.py` landed in the same sweep and pinned 71 delayed
handlers across 26 files.

**The fixes are verified statically; they need an OXT pass.** Every one of them
was written after the run and none has been re-run on an engine, so nothing here
upgrades a demo's label: B.1's tick-sheet rows stay unticked, and this banner
records what the engine SHOWED, not that the repairs work.

---

## A. Unbuilt phases and features (16)

> **2026-08-15 wave-1 closures (commits `0a1f79d`, `4029e50`, and the WIF
> commit):** item 11 (coinxt WIF) SHIPPED statically - cxWifEncode/Decode,
> vectors derived from the independent reference and anchored to the Bitcoin
> wiki's published string, 272 script-vector checks executing the shipped
> file, mutation-tested, coverage 80/80 - needs its OXT pass. Item 15 (the
> token-mount redirect hole) FIXED and golden-mirrored. Item 14 (the
> ETag/304 duplication) FACTORED into one golden-pinned helper; the Tor
> keep-alive half stays an owner decision. Section D's item 4 (the family
> template) also closed - synced and drift-gated.


Code that does not exist yet: planned phases, designed-but-unshipped surfaces,
and one functional hole.

1. **Hold'em: the open phases — ~~2e remainder, 2f, 3~~, 4, 5** (was large;
   rewritten 2026-08-16 to its as-built state). Everything statically
   buildable is BUILT, at v0.23.0: all of 2e (checkpoints, show/muck,
   online History, host election, and — closing the last recorded slice —
   act timers/time-bank/sit-out/late-join/onion-redial, commit `6372cc8`),
   2f onion tables, the Phase 3 deck oracle, the 4a-4e Level 2 layer
   (compute + void-and-audit + the five cheater bots, every attack
   detected and attributed), and Phase 5's DLEQ proofs (a wrong unmask
   step refused instantly on a dleq=1 table). Genuinely remaining, and
   none of it headless: Phase 4f (deal-time budget measurement and the
   played-hand Level 2 wiring — engine-era by definition), the live exit
   gates (multi-machine rp1 session, two-machine onion table + tor, the
   three-machine oracle round, the timed liveness session), and Phase 5's
   hostile review + soak (human-era). The Level-0 cheating-dealer caveat
   closed in design when online play carried independent per-player seeds;
   its live confirmation rides the multi-machine pass.
   — `holde-em/IMPLEMENTATION-PLAN.md`, `holde-em/README.md` (Status),
   `holde-em/CLAUDE.md` (fold record + contracts)

2. **~~SodiumXT ristretto255 surface (Workstream U)~~ SHIPPED statically
   2026-08-15** (SodiumXT ABI 8: the five sxRistretto* handlers, no sxHash512
   needed, KATs cross-checked between libsodium and the independent RFC 9496
   reference now in `holde-em/tools/protocol-kat.py`, all four non-mac
   binaries rebuilt). Remaining from this item: the handlers' first OXT pass
   (**CLOSED 2026-08-17**: both the ABI-8 and the ABI-9 ristretto sections ran
   green in the Windows engine pass - the mask/unmask roundtrip, the batch over
   three points, the DLEQ-shaped `k*(P+Q) == k*P + k*Q` identity, and the
   failure the batch API exists to get right: one bad point fails the whole
   batch, NAMING index 2 of 3. What remains from this item is only the recorded
   Phase 5 follow-ons. The old text said they were engine-unexercised, the
   section SKIPping on a pre-ABI-8
   package), the Windows engine re-proof of the mingw cross-built DLLs, and
   the recorded Phase 5 follow-ons (ScalarMultBatch, point add/sub, base
   mult for DLEQ).
   — `sodiumxt/CLAUDE.md` ABI table, `holde-em/IMPLEMENTATION-PLAN.md` (Workstream U)

3. **~~Hold'em table 720p re-layout (1024x690 -> height <= 640)~~ SHIPPED
   statically 2026-08-16** (commit `6372cc8`: 1024x640, the layout reclaimed
   coherently rather than squeezed — felt 48..524, pot line below the board,
   re-rhythmed bottom rows — verified by rect ARITHMETIC: 51 control rects
   in budget, the 43-rect disjointness set pairwise disjoint; the SKIP entry
   is REMOVED from `tools/check-stack-size.py`).
   **That sentence overstated its gate, and a review caught it the same day**:
   `check-stack-size.py` reads ONE number per stack and never looks at a
   control, so removing the SKIP restored a window check and pinned none of
   the arithmetic above - which had come from a scratchpad script run once
   and never committed. It is a gate now: `holde-em/tools/check-table-layout.py`
   (2026-08-16) re-derives every control rect from the builders on every push.
   It also corrected the numbers: "51 rects" were 51 SET-THE-RECT SITES, which
   build **159 controls** (152 in the disjointness set, 5635 pairs), so the
   original "43-rect" figure was never reproducible from the source. Two
   further corrections recorded en route:
   this item's "quick-bet row (y 688)" was a misread (688 was a button's x;
   the real overage was the status line plus the 690 height), and the
   original "needing an OXT eye, not a number trim" was half right — the
   re-layout was designable by arithmetic; only the confirming EYE (nothing
   clipped, the felt still reads) is the OXT pass's.
   — `holde-em/src/holdem.livecodescript` (kHeStackRect, kUIVersion 15)

4. **~~ONIONXT integration plan Phases 2-3: Model C for DHT-Channels~~ BUILT
   2026-08-15; struck 2026-08-17.** This entry's own evidence is what falsified
   it: it said `torrent-dht-channels.livecodescript` "contains zero onion/Tor
   references", and that file now matches **629** of them, with Model C built
   from `chOnionServiceFor` / `chAnonFeedText` / `chOnionServeRequest` /
   `chOnionPublishFile` / `chOnionDownload`. The plan's §10 carries dated
   "As-built (built 2026-08-15)" blockquotes for Phases 2 and 3. **What remains
   is verification, not code**, and it is already counted in section B: register
   items #31-#33 need a tor daemon (#31) and two machines plus tor (#32, #33).
   — `docs/ONIONXT-INTEGRATION-PLAN.md` §6, §10, §12.3

5. **~~ONIONXT plan Phase 4 docs~~ SHIPPED; struck 2026-08-17.** All three
   exist: `docs/anon-transport.md`, `docs/anon-transport-threat-model.md`, and
   `docs/anon-transport-onboarding.md`. **The PHASE does not close with them**,
   and that distinction is kept rather than tidied: its exit gate is a fresh
   user completing the walkthrough on each of macOS, Windows and Linux, which is
   section C/E work needing three platform boxes and a human.
   — `docs/ONIONXT-INTEGRATION-PLAN.md` §13

6. **~~Riptide spec 8.2/8.3 onion transport serving~~ BUILT; struck
   2026-08-17.** `rsAnonFeedPage`, `rsAnonPrekeyBody` and `rsAnonAcceptDm` all
   exist in `riptide/src/riptide.livecodescript`, and the demo registers all
   three routes. The live half stays open as B.4 (phase 7 over Tor, two
   machines).
   — `riptide/src/riptide.livecodescript`, `docs/RIPTIDE-SOCIAL-SPEC.md` §8.2/8.3

7. **~~Riptide phase 6's actual sync payload~~ BUILT; struck 2026-08-17.** The
   RSL1 record builders and the LAN sync receive path exist. **One defect found
   in that layer on 2026-08-17 and fixed the same day** (C6 of the headless
   backlog): the demo keyed six sync arrays by the ENET PEER rather than the
   signing DEVICE, so on a joiner every relayed record from every device landed
   in one slot and other devices never appeared in the Devices panel at all —
   violating a contract `riptide/src/riptide.livecodescript` states in its own
   words ("apply only a seq strictly above the last one applied for that
   device"). The two-machine runbook has ONE non-host device and structurally
   could not have reached it.
   — `docs/RIPTIDE-SOCIAL-SPEC.md` §6, `riptide/src/riptide.livecodescript`

8. **~~Riptide phase-5 typing presence~~ BUILT; struck 2026-08-17.** The
   typing lane exists in the demo (`raDmTypingTick` and its four call sites).
   Its live confirmation rides B.4's phase-5 two-machine pass.
   — `docs/RIPTIDE-SOCIAL-SPEC.md` §5

9. **~~Riptide profileMeta has a PUBLISHER and a PARSER but NO READER~~
   BUILT; struck 2026-08-23.** The demo-side reader now fetches the
   profileMeta target and shows the display name, which was the half this
   entry said remained. (Original entry kept below as the record; small;
   rewritten 2026-08-17, not struck then — the original said "the demo never
   populates it", and that half is now false). `raPost` publishes the
   display-name blob through `rsPublishImmutable` and passes the target to
   `rsBuildHead`, with a non-fatal refusal path; `rsBuildHead`'s parse writes
   `tHead["profileMetaTarget"]`; one harness assertion pins it. **Nothing
   anywhere fetches that target and shows the name**, which is the entire point
   of the field (spec 4.1: "so a reader can show a name without parsing the
   head's own name field out of band"). Demo-side wiring only, and now the
   smaller half of the job.
   — `riptide/examples/riptide-social.livecodescript` ("the head's profileMeta names a display-name blob")

10. **~~coinxt Schnorr/BIP-340 + the Taproot tweak~~ SHIPPED statically
    2026-08-16** (commit `affdf1c`, coinxt ABI 6). The blocking decision
    (D-01) was DECIDED "vendor it", and the library this item named was
    wrong: upstream **bitcoin-core/secp256k1** carries schnorrsig and
    extrakeys in-tree, so the zkp fork was never needed, and coinxt's
    copy-pinned-sources model meant no second build system. 58 files
    hash-verified against the pin; all 19 published BIP-340 vectors (10
    negative) and all 14 BIP-341 wallet vectors drive it. `cxBtcAddressP2TR`
    is deliberately UNCHANGED - making it tweak would turn every existing
    correct call into a permanently unspendable double tweak - so the full
    BIP-341 path is a separately named handler. **Remaining from this item:**
    the script layer's OXT pass, the Windows DLLs' execution proof (both
    already counted in section B), and one genuine gap now recorded in
    coinxt's docs rather than assumed - there is NO BIP-341 sighash builder;
    coinxt signs a sighash it is handed and cannot compute one. **(That gap
    CLOSED 2026-08-23: `cxBtcSighashTaproot` ships the full BIP-341 SigMsg -
    every type incl. the ANYONECANPAY forms and the tapleaf extension - plus
    `cxTapLeafHash` / `cxTapBranchHash` / `cxTapControlBlock` for script-path
    spending, pure script over the ABI 6 surface, pinned to the published
    wallet vectors headlessly; needs its OXT pass. coinxt is 94 handlers now.)**
    — `coinxt/CLAUDE.md` (the dated rule-change entry), `coinxt/SPEC.md` 2.1

11. **~~coinxt WIF encode/decode~~ SHIPPED 2026-08-15; struck 2026-08-17.**
    `cxWifEncode` / `cxWifDecode` ship, mainnet and testnet, with the 0x01
    compressed marker and a fail-closed decode. The wave-1 banner at the top of
    this section recorded the ship; the ENTRY was left reading present-tense
    open, which is the inverse pathology this document warns about — a shipped
    item listed as blocked spends engine minutes. Its OXT pass is counted in B.8.
    — `coinxt/src/coinxt.livecodescript` ("cxWifEncode")

12. **~~coinxt cnx_memzero export~~ SHIPPED statically 2026-08-16** (commit
    `55f9130`: ABI 5, the export a thin wrap of the already-vendored
    trezor-crypto memzero; every `.lcb` allocation now wiped before free —
    unconditionally, because per-site secrecy classification fails open
    when wrong — and the audit fixed a real throw-path leak in the old
    sFinish; all four non-mac binaries rebuilt, the Windows DLLs' below-bar
    static-checks-only state RECORDED in `coinxt/CLAUDE.md`, superseded by
    the next release-binaries dispatch). Remaining from this item: the
    `.lcb` call sites' OXT pass and the DLLs' Windows execution proof —
    both already counted in section B's backlog, not new items.
    — `coinxt/CLAUDE.md` (as-built entry), `coinxt/src/coinxt.lcb`

13. **~~nocloud HTTP-host Phase 3: per-route streaming/params~~ BUILT
    2026-08-16; struck 2026-08-17.** The `:param` matcher ships and the routes
    stream through the shared bounded pump. The §4 endpoint MENU it enables
    stays an owner call (E.5 / D-02).
    — `nocloud/docs/http-server-deep-dive.md`

14. **~~nocloud residual Phase-2 duplication~~ FACTORED; struck 2026-08-17.**
    The ETag/304 branch and head assembly are one golden-pinned helper
    (`qsHttpFileHead`), reached by both transports. The Tor keep-alive half was
    always an owner decision and stays one (E.5).
    — `nocloud/src/nocloudquickshare.livecodescript` ("qsHttpFileHead")

15. **~~nocloud token-mount redirect hole~~ FIXED 2026-08-15; struck
    2026-08-17.** Redirects are re-prefixed server-side by `qsMountLocation`,
    golden-mirrored. **This entry also named a handler that has never existed
    anywhere in the tree** (`qsRebaseLocation`) — recorded rather than quietly
    corrected, because a citation nobody can resolve is how a punch-list item
    survives past its fix.
    — `nocloud/src/nocloudquickshare.livecodescript` ("qsMountLocation")

16. **box2dxt platformer polish plan §9 passes** (medium). Scene composition
    (each biome deliberately dressed), audio + UX/chrome sweep, code/repo
    cleanup + packaging proof, cosmetic transition-card tuning. (The
    feel/facing/scale half is engine work — B.5.)
    — `box2dxt/docs/platformer-polish-plan.md` §3-§7, §9

## B. Verification backlog (12)

Built and statically verified; pending under the honesty convention.
`docs/OXT-PASS-RUNBOOK.md` scripts nearly all of it.

1. **Fleet-wide OXT re-pass of every kit-converted demo** (large). Every demo
   converted 2026-08-14 reads "UI unified 2026-08-14; needs an OXT re-pass";
   ~20 runnable stacks carry a live label; every DEMOS tick-sheet row except
   riptide-social is unchecked. The runbook says to start here.
   **CHEAPER SINCE 2026-08-20:** eleven of those stacks now print a boot
   self-check on open, so this item's output is a pasteable block per demo
   rather than a judgement per demo. That does not close the item - a
   self-check proves the stack builds, its libraries answer and its timer can
   write, not that the demo DOES what it demonstrates - but it turns the
   unrecordable half into a record. The non-adopters and why are listed beside
   the runbook's step-2 table.
   — `docs/OXT-PASS-RUNBOOK.md:101-124,1186-1196`

2. **Suite closing pass legs B-E (two machines)** (medium). enet LAN chat;
   torrent seed/leech + resume across an OXT restart; rp1 chat over a DHT
   rendezvous; dc chat signalled over the real DHT. Leg A closed 2026-08-15.
   — `tests/suite-closing-pass.livecodescript:3-36`, runbook tick sheet

3. **The Tor evening** (medium). Runbook items 4 + 5 and closing-pass leg F:
   Mode B oxLaunchTor (onionxt's one remaining VERIFY), the live onion echo
   that closes the seven live-daemon coverage exemptions, the QuickShare
   Model C behavioural run, nocloud's Tor path, the two-instance onion round
   trip, the negative paths, then the §12.3 register ticks and label flips.
   — `docs/OXT-PASS-RUNBOOK.md:174-175,852-874`, `docs/ONIONXT-INTEGRATION-PLAN.md` §12.3

4. **Riptide phases 5-7 live passes** (large). The phase-5 call has NEVER
   executed (two machines, two networks); phase-6 live admission; phase-7
   persona over Tor (also blocked on A.6). Plus the phase-3 mid-download
   nuance and one engine re-run of the post-00:46 harness additions
   (LAN-welcome, 8.3 crypto).
   — `riptide/CLAUDE.md:35-57`, `riptide/docs/two-machine-runbook.md`

5. **box2dxt member-wide re-pass + platform verdicts** (large). The fold's
   ~1550-fix sweep re-opened the whole member; macOS/Linux verdicts (risk R1)
   - Linux now has its FIRST data point, 2026-08-18: the member harness ran
   373/374 at v29, its one failure a harness assumption about `playLoudness`
   rather than a Kit defect, so the member-wide re-pass and a v30 total are
   still owed on BOTH platforms - and the polish plan's feel/facing/scale pass
   (incl. L7's vertical camera) ride the same sessions.
   — `box2dxt/CLAUDE.md:72-74`, `box2dxt/plan.md:46-47`

6. **datachannelxt browser interop + two-network NAT call** (medium). The
   member's two explicitly-open residuals; no session has ever left the host.
   — `datachannelxt/CLAUDE.md:162-164`

7. **torrentxt's four never-run plan gates** (medium). Real-swarm interop
   (legal ISO + hash), resume across a real restart, packaged fresh-install
   per platform, the destructive-handler manual pass.
   — `torrentxt/docs/archive/TorrentXT-IMPLEMENTATION-PLAN.md:480-513`

8. **coinxt demo pass + live testnet broadcast** (medium). The phase-6 demo's
   engine pass, and the one bar left before "broadcastable": a CoinXT-built
   transaction accepted on a live testnet in each of the four families.
   — `coinxt/examples/coinxt-demo.livecodescript:14-18`, `coinxt/IMPLEMENTATION-PLAN.md:235`

9. **nocloud: the 68-item pass checklist at zero ticks + whole-stack re-pass**
   (large). **The four "checklist gaps" this entry listed are all closed as of
   2026-08-17, and three of them were already closed when the entry was
   written** - re-verified against the file rather than the entry:
   - "no ETag/304 section" - the Conditional GET item has been in section 4
     since 2026-08-15.
   - "no redirect-under-token-mount test" - section 1 carries the
     `GET /<token>/go/gallery` -> `Location: /<token>/gallery` re-prefix test,
     also since 2026-08-15.
   - "no items for the webapp's runtime claims" - the service worker, Range
     seeking and `pushState` routing items were ADDED 2026-08-17, alongside
     the two `HEAD` fixes; the checklist grew 59 -> 68 in the same pass.
   What survives intact is the part that needs an engine: **zero of the 68 are
   ticked**, and the whole-stack re-pass has never run. That is runbook S1
   row S (web-link half) and S2 item 7 (Tor half), and both budgets are now
   light for the longer list.
   — `nocloud/docs/oxt-pass-checklist.md` ("Conditional GET (shared head builder, 2026-08-15)")

10. **Suite-root stacks: start-here, ui-kit v2 assembly, closing-pass stack**
    (small). Each carries its own "verified statically" label; cheap
    single-machine opens.
    — `start-here.livecodescript:42-45`, `tools/ui-kit.livecodescript:59`

11. **holde-em's pending passes** (medium). The Phase 2d multi-machine pass
    ("two machines, one invite code" — netsim-pinned, never crossed real
    machines); the Phase 1 exit (a full 6-seat hotseat session in OXT, plus
    the 1d animation polish left for that pass); and a re-pass of
    heXorSeedsHex / heDeckFromStreamKey, which the fold rewrote after the
    unified checker found the stepped-pair-walk and throw-in-catch traps —
    that pass should also establish whether earlier on-engine Level 0 runs
    dealt from the stepped or 1-stepped stream (the Python KATs pin the
    correct semantics).
    — `holde-em/IMPLEMENTATION-PLAN.md` (Phase 1 exit, 2d status),
    `holde-em/CLAUDE.md` (fold record)

12. **onionxt's four inline on-engine hypotheses** (small). The
    duplicate-local-port refusal, oxGuessService's socket-id format,
    stale-socket-close tolerance, the topStack default callback owner.
    — `onionxt/src/onionxt.livecodescript:1018,1140,1713,1744`

## C. Release and CI (7)

1. **~~macOS universal binaries~~ CLOSED 2026-08-27 by release run 12**, the
   first `release-binaries.yml` dispatch to reach its commit stage: first-ever
   universal dylibs landed for torrentxt, enetxt, datachannelxt and coinxt,
   sodiumxt's refreshed from the hand-lipo'd ABI 6 to ABI 10, every one a
   genuine two-slice Mach-O (built by the 2026-08-23 lanes: both slices
   cross-compiled or two-slice-lipo'd, `lipo -archs` asserted at birth, arm64
   tested natively and x86_64 under Rosetta 2, coinxt's KATs driven through
   both slices, unsigned per the accepted 2026-08-23 decision) and read by
   `check-binary-freshness.py` on every push. Getting there took runs 5-11
   discovering one real defect each (perl modules, the ASan runtime, the
   `ships` deadlock, enetxt's unfiltered mac export table, a commit allowlist
   that could not spell box2dxt). Still open: notarization only (credentials
   CI does not hold), and the mac ENGINE pass - no OXT engine has loaded any
   of the six dylibs yet.
   — `.github/workflows/release-binaries.yml` (the header), `sodiumxt/CLAUDE.md:54-59`

2. **~~box2dxt as the eighth folded harness member~~ SHIPPED statically
   2026-08-16** (commit `ef73172`). Suite coverage **411/429 -> 724/742**;
   the paste is 20,616 lines, 928 handlers, 8 folded harnesses, 4 embedded
   script layers. The item's own list is done (returned-report entry, Member
   row, b2k in the coverage gate) plus three mechanisms nobody had costed:
   box2dxt is the first member whose harness is a paste-and-run STACK, and
   its verbatim copy of the b2k Kit had to be CUT and the Kit embedded once,
   or all 313 Kit handlers would have been defined twice - a compile error
   first met on a real engine, which is exactly the scarce resource this
   work protects. "Close what the coverage gate demands" turned out to be
   **210 handlers**: 13 new sections took the Kit to 313/313 with zero
   exemptions. **NOT closed, and recorded as an open item beside the gate
   row rather than pretended away:** `box2dxt/src/box2dxt.lcb`'s 376 public
   `b2*` handlers, of which the Kit names 132 and **244 are named by no
   script anywhere in the member**. That layer is a 1:1 binding driven by
   `smoke_test.c` under ASan in CI; 375 blind assertions against a
   foreign-bound API would most likely hand the next OXT session a pile of
   test bugs instead of defects.
   — `box2dxt/CLAUDE.md` (fold record), `tools/check-suite-coverage.py`
   (the measurement beside the row)

3. **box2dxt into the release assembly lane** (medium; **scope HALVED
   2026-08-17**). ~~release-binaries.yml and install-release-binaries.py both
   omit it~~ - the installer half landed (one token, verification-only, inert
   until a lane exists, pinned by `--selftest`), and the "teach it box2dxt's
   package layout" cost every doc quoted was never real: the layout was already
   the family layout. Only **release-binaries.yml** omits it now; needs the docker-run job
   ported or an owner-decided glibc-floor raise. "A deliberate release-lane
   pass, not a drive-by."
   — `box2dxt/CLAUDE.md:34-47`

4. **holde-em into the suite selftest ~~and coverage gate~~ — SPLIT
   2026-08-17; ~~the selftest half is DONE, the coverage half is not~~ BOTH
   HALVES BUILT, and what survives is one decision: whether to ARM the
   coverage row.**
   - ~~Suite selftest~~ **DONE 2026-08-16** (commit `7f55839`): holde-em is the
     ninth folded harness and `check-suite-selftest.py` reports
     `holde-em=380`. Its fold needed only `drop_extra` plus one `@PREFIX@`
     rewrite, because its game and its harness are the SAME FILE and both
     sides rename together.
   - ~~Coverage gate — STILL OPEN~~ **BUILT 2026-08-17** (commit `0a298c5`),
     and ADVISORY - not yet armed as a floor. ~~The member is folded but NOT
     ratcheted, so its surface is in no numerator. Measured 2026-08-17: 379
     public `he*` handlers, 174 named by a `heTest*`/`heProbe*` body, 205
     named by nothing. (The 163 quoted elsewhere in this file is stale — the
     harness grew.)~~ Superseded, and not a like-for-like comparison: that
     count asked which handlers were NAMED by any test-shaped body, the gate
     asks which are named by a body REACHABLE from `heSelfTest`, and the
     denominator has moved too (329 game handlers on 08-17, 330 today). ~~What
     is missing is a way to scan the harness REGION of a single-file member;
     the graph walk itself already exists as `check-suite-selftest.py`'s check
     7d and should be lifted rather than rewritten.~~ As built,
     `tools/check-suite-coverage.py` splits the one file at its selftest
     boundary (`HOLDEM_BOUNDARY_RE` matches `command heRunSelftest`) into a
     GAME region and a HARNESS region and asks the coverage question across
     the cut - a boundary LINE where the embedded script layers use sentinels,
     because a single-file member has no sentinel to cut on.
     **Measured 2026-08-19 by `python3 tools/check-suite-coverage.py`** - a
     gate run, not an engine run: **121/330 exercised in the GAME region**
     (120 named by a body reachable from `heSelfTest`, +1 dispatched by name
     through `heRunSection`, which the coverage convention's literal-blanking
     cannot see); **209 named by nothing that runs**, split 20 live-transport
     / 9 engine-media / 41 host-window / 139 no-test; the HARNESS region is 51
     handlers, 48 reachable from `heSelfTest`, 3 interactive-delivery by
     design.
     **What is still open is the arming.** The row prints in both modes so CI
     records the number and does not fail the build. Armed absolutely it would
     fail on 209 today; armed as a FLOOR - no NEW gaps - it would fail on 0,
     which is the honest next step and the one worth taking. The gate prints
     both figures itself, so neither has to be re-derived to act on this.
   — `holde-em/CLAUDE.md` (fold record), `tools/build-suite-selftest.py`,
   `tools/check-suite-coverage.py`

5. **torrentxt portable-Linux lane never dispatched** (small). The committed
   x86_64 .so still carries the glibc-2.38 floor until one release-binaries
   dispatch re-commits from the wired manylinux_2_28 lane.
   — `torrentxt/docs/building.md:126-162`

6. **coinxt per-push CI is Linux-only** (medium). Windows only at manual
   release dispatch; macOS untried. Per-push lanes, or a written decision the
   dispatch path is permanent.
   — `.github/workflows/native-coinxt.yml:23-37`

7. **Inert member workflows carry stale pre-suite behavior, ungated** (small).
   coinxt's still describes the abandoned repo split; torrentxt's would
   auto-commit binaries if a mirror ran it; the three hand-kept copies of
   build config have a written mirror-by-hand obligation and no drift check.
   — `coinxt/.github/workflows/ci.yml:10-12`, `release-binaries.yml:106-114`

## D. Label and doc hygiene (9)

> **2026-08-15 hygiene sweep (commit `fa03fac`, after `7977ffb`/`f6e7b20`):**
> closed headlessly - item 1's label halves (sodiumxt, coinxt, riptide,
> box2dxt, onionxt all flipped to their recorded passes), item 2's NAMED
> citations (box2dxt badge, riptide example paths, suite-gates.yml header,
> coinxt ci.yml pre-split text), items 3, 6, 8, and 9 in full, and item 7's
> inline marks (ship-or-strike SHA3-512 is now an owner call, E-class).
> Still standing in this section: the broad member-root-relative path sweep
> (the rest of item 2), the family template (item 4), and the checker union
> (item 5).


1. **~~Stale honesty labels lagging recorded passes — one sync pass~~
   CLOSED; struck 2026-08-23 after re-reading every named file rather than
   the entry** (the rows-8/9 lesson a third time - stated precisely: FOUR of
   the five named halves were already closed in the tree, and the fifth was
   closed by the same change that struck this entry, not found closed).
   sodium.lcb's header records the retired caveat and the 2026-08-10/12
   passes; sodium-tests reads "Engine-verified through ABI 9"; coinxt's
   phase-5 STATUS records both bars met with only the live-broadcast bar
   unclaimed; riptide's header records the phase-3/4 two-machine closures;
   and the platformer's slice-3 comments were corrected to SHIPPED in this
   change (dated in place, recorded in box2dxt's CHANGELOG).
   (Original entry kept as the record, medium).
   `sodiumxt/src/sodium.lcb:10-20` + `sodium-tests:18` (closed by the 71-check
   2026-08-12 pass); `coinxt/src/coinxt.livecodescript:1976-1979` phase-5
   STATUS (engine + decoder bars met); `riptide/src/riptide.livecodescript:21-29`
   phases 3-4 (closed 2026-08-15) plus the demo's "phases 5-7 are NOT here"
   scope block; onionxt's "SHA3-256 (deferred)" UI strings for a shipped gap
   (fix requires regenerating both standalones + the suite harness);
   box2dxt platformer's "remaining slice 3" comments for shipped slices.
   The convention only works if labels flip both ways. (The onionxt
   "SHA3-256 (deferred)" strings were fixed 2026-08-15, standalones and the
   suite harness regenerated; the rest of this item stands.)

2. **The tracked consolidation path-rewrite pass** (medium). Docs moved
   verbatim still cite member-root-relative paths; includes box2dxt's README
   badge, riptide/examples/README's runbook path, and suite-gates.yml's
   "tracked follow-up" header for a port that shipped.
   — root `CLAUDE.md` cross-reference caveat
   (CLOSED 2026-08-15: the sweep ran - full-tree inventory of every `*.md`,
   the misleading navigation references fixed or annotated, and both caveats
   - root `CLAUDE.md` and `docs/README.md` - rewritten to record the
   residual convention: a member's own docs stay member-root-relative, and
   dated records keep their original pre-suite spellings.)

3. **nocloud CONTRIBUTING still describes the standalone repo** (small). Names
   only the two member gates; the suite gate set has walked the directory
   since the fold. A contributor following it verbatim misses all of that.
   — `nocloud/CONTRIBUTING.md:5-15,32-58,127-135`
   (CLOSED 2026-08-15 in the hygiene sweep: CONTRIBUTING opens with the fold
   preamble and names the suite gates as item 3 of its workflow.)

4. **The family engineering template is stale and ungated** (medium).
   `onionxt/templates/CLAUDE.md` (+ byte-identical coinxt twin): its checker
   section describes the retired pre-unification rule set; shipped-is-not-run,
   coverage-overstatement, and the carried-block conventions never flowed in;
   post-2026-08-13 gotchas (textDecode-is-lossy, stale-the-result,
   dangling-else, the falsified step-loop scale claim) are absent; no drift
   gate or master. Hoist one master with a drift gate, then sync.
   — `onionxt/templates/CLAUDE.md`, `coinxt/MIGRATION.md:105-109`

5. **Union the eight holde-em idiom checks into the unified checker** (medium).
   (Replaces the resolved stale-seed-checker item — the fold removed
   `docs/holde-em/` and registered the member's unified copy.)
   `holde-em/tools/check-holdem-idioms.py` survives because eight checks with
   shipped-defect provenance (chunk-of-array H6, bitwise H7, engine-token
   names, undeclared catch vars, command-with-parens, dynamic property names,
   message-box prose, never-declared k-constants) have no unified counterpart.
   The 2026-08-12 precedent says they belong in the ONE checker, propagated to
   all ten members with fixtures — a deliberate pass, since each firing on
   another member's code is itself a latent-bug find; then retire the idioms
   gate.
   — `holde-em/tools/check-holdem-idioms.py` docstring, root `CLAUDE.md`
   checker-unification passage
   (CLOSED 2026-08-15: the union shipped - the eight checks are the unified
   checker's docstring checks 13-21, fixture-tested in every member copy,
   with two ports narrowed and H6 refused on fleet engine evidence - and
   `check-holdem-idioms.py` is retired; holde-em/CLAUDE.md's fold record
   carries the detail.)

6. **~~nocloud doc surface lagging the newest features~~ CLOSED 2026-08-23**
   (the D.6 sweep): SECURITY.md's contact names GitHub private vulnerability
   reporting as the working default; sw.js's header corrects its own stale
   "can never serve a stale file" claim and records the out-of-band-edit
   caveat; the webapp docs and demo cover `.qsroutes.json`, `config.json`
   and conditional GET (weak ETag / 304), labeled "verified statically +
   golden-pinned; needs an OXT pass"; CONTRIBUTING's mirror table is
   reconciled. (Original entry kept as the record, medium). SECURITY.md's
   unfilled contact placeholder and missing .qsroutes.json model bullet;
   CONTRIBUTING's half-stale golden-mirror table; webapp docs/demo omitting
   .qsroutes.json, config.json, ETag/304; sw.js's now-conditionally-wrong
   "can never serve a stale file" claim.
   — `nocloud/SECURITY.md:8,18-98`, `nocloud/webapp/sw.js:6-8`

7. **coinxt SPEC/README claim SHA3-512; only SHA3-256 exists, unmarked**
   (small). Ship it (sha3.c already vendors it) or mark the two mentions.
   — `coinxt/SPEC.md:33` vs `:164`

8. **~~torrentxt api-reference "fields not yet populated" reconcile~~ ALREADY
   CLOSED IN THE TREE; struck 2026-08-23 after re-reading the file rather than
   the entry** (the same lesson as row 9 below). `torrentxt/docs/api-reference.md:10-16`
   has carried the close since 2026-08-15: "that gap has closed (audited
   2026-08-15: every field id registered in `src/btx_record.h` is written by
   `src/torrent_shim.cpp`)", with one deliberate surviving caveat about a
   libtorrent-omitted counter. The row outlived the work by eight days.

9. **~~Two riptide gate scripts want hardening~~ FALSE ON BOTH HALVES; struck
   2026-08-17 after re-reading the files rather than the entry.**
   `check-selftest-vectors.py` does NOT silently skip — its comment states the
   opposite rule and its code enforces it ("any `constant k` line the regex
   cannot decompose is a LOUD failure, never a skip"), naming the
   parsed-vs-checked hole as the thing it refuses. And `check-docs-style.py`'s
   SCOPE docstring DOES name riptide, in a list of exactly the four members
   that declare the no-dash rule. Both were presumably fixed without striking
   the entry.
   — `riptide/tools/check-selftest-vectors.py` ("a LOUD failure, never a skip"),
   `riptide/tools/check-docs-style.py` ("SCOPE, precisely")

## E. Open decisions and roadmap (10)

Recorded owner calls and explicitly-uncommitted future work; each wants either
execution or a written resolution.

1. **ONIONXT plan §14: five reserved decisions.** Tor delivery; large-file
   warn-vs-block + threshold; which .onion-derivability claim ships; sign-off
   on positioning copy; Channels serve-map durability.
   — `docs/ONIONXT-INTEGRATION-PLAN.md:1704-1731`
2. **onionxt docs/09: five design questions** (+ subverted-tor detection
   investment). — `onionxt/docs/09-open-questions.md:12-39`
3. **Riptide feed retention** — the one unresolved spec-§12 decision (follower
   republish of followed heads). — `docs/RIPTIDE-SOCIAL-SPEC.md:637-640`
4. **sodiumxt Windows libsodium pin** — vcpkg baseline, pinned source on
   Windows, or record the KAT-guarded status quo.
   — `sodiumxt/docs/building.md:177-184`
5. **nocloud mtime probe + Phases 4-5 endpoints** — the engine finding gates
   the real conditional-GET validator; the endpoint menu waits on the §8
   priority questions and Phase 3. — `nocloud/docs/oxt-pass-checklist.md:80-83`
6. **oxtkit/ shared native scaffolding: execute or retire.** Never extracted;
   the native C scaffolding remains N copies with no drift gate.
   — `docs/NEXT-EXTENSIONS-PLAN.md:596-613`
7. **Channels brainstorm menu + flagged SodiumXT helpers** (ed25519->X25519,
   k-of-n secret sharing). Roadmap only.
   — `docs/SODIUM-TORRENT-CHANNELS-BRAINSTORM.md`
8. **coinxt SLIP-39 scope; decoder acceptance as an optional CI lane.**
   — `coinxt/SPEC.md:35`, `coinxt/CLAUDE.md:886-891`
9. **box2dxt's recorded open calls.** Suite-kit chrome exemptions (keep or
   convert); dormant b2kScene*/enemy-pattern promotions; Wave 8 builder
   cross-pollination; streamed music; multi-player keying; snake-audit
   extension; parallax parked on art.
   — `box2dxt/plan.md`, `tools/check-ui-kit-drift.py:64-92`
10. **Recorded optional milestones.** torrentxt's Phase-5 dashboard widget
    (out of v1 by decision); datachannelxt's media tracks (optional, NO_MEDIA).
    — `torrentxt/docs/archive/TorrentXT-IMPLEMENTATION-PLAN.md:514-519`,
    `datachannelxt/docs/architecture.md:106-114`

---

**Permanent, structural exemptions** (recorded, not actionable): onionxt's 11
engine-socket-callback coverage exemptions (only the engine can mint a socket
id); release-binaries.yml's manual dispatch (rule 5: a committed binary traces
to a human decision); the harness scaffold's non-adoption of the UI kit
(written exemption). The 7 live-daemon exemptions retire with the Tor evening
(B.3).
