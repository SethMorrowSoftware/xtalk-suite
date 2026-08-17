# HEADLESS-BACKLOG-2026-08-17.md - what is still buildable before the next OXT pass

**Compiled 2026-08-17** from a full-tree survey at commit `c5b531a`, the day
after the five box2dxt/holde-em engine runs. It answers one question:
**what can be built or improved with no engine, no tor daemon, no second
machine, no platform box, and no owner decision?**

Per the honesty convention it applies to itself. This is a dated,
point-in-time audit and an INDEX, not a second ledger: each member's own
docs stay the authority for its layer, and `docs/REMAINING-WORK.md` stays
the punch list. When an item here closes, strike it here in the same change;
when this file's date grows old, re-audit rather than trust it.

**Method, stated so the numbers can be disbelieved precisely.** Eight
domain surveys, each adversarially re-verified against the tree, produced 95
candidates; 41 items survived dedup. Every figure below was re-measured
during the compile. Findings are marked **[M]** where they were measured
directly in this session and **[S]** where they come from the survey and
were spot-checked but not independently re-derived. The distinction matters:
this repo has twice paid for a gate that reported what it had parsed as what
it had checked.

---

## WHAT CLOSED THE SAME DAY THIS WAS COMPILED (2026-08-17)

This file was compiled in the morning and most of its C and D sections were
built in the afternoon, by eight agents working on disjoint file sets with the
whole gate suite green at the end. Recording it here rather than rewriting the
41 entries, because **the entries are the evidence for the numbers below** and
striking them would delete the reasoning.

**Closed: C1-C6, C8-C16, C19-C21, B1, B3, B6, D1-D3, D6-D8, D11-D13, D15.**
Highlights, each with the measurement rather than the adjective:

- **The two gates that were lying are fixed and gated.** `check-handler-calls`
  could not see 2,476 lines of nocloud (fixed, +42 handlers, 12 fixtures);
  `check-suite-coverage` counted a SKIP NOTE as coverage (fixed by writing the
  four missing checks, not by exempting them - torrentxt 85/85, zero
  exemptions).
- **`cross-member-test.py` now runs in CI at all.** It ran in ZERO lanes and
  printed "every cross-member invariant holds (measured natively, not
  reasoned)" after skipping three of four legs.
- **box2dxt's C ABI, this file's "biggest genuinely-open measurement hole", is
  half closed and now MEASURED BY GCOV: 53 -> 194 of 370 exports entered.**
  Section F's "60 of 370" was itself a grep artifact - it counted the `extern`
  DECLARATION block, and six exports sat there declared and never called, so
  every prior count of that harness's reach included six functions nothing ran.
  A declaration is not a call. `check-lcb-signatures.py` (370 binds vs 370
  definitions, return type, arity, every parameter) is wired into the gate set.
- **Three real defects with a security or consensus edge:** onionxt's
  `oxHostOfSocket` FAILED OPEN on a bare IPv6 socket id (item 1 parsed empty,
  and `oxHostIsLoopback` accepts empty) on a guard its own comment calls
  security-critical; riptide keyed six LAN sync arrays by the enet peer rather
  than the signing device, so on a joiner other devices never appeared at all;
  holde-em's host election could elect a sitting-out seat, a deterministic
  table-death in the one layer whose written contract is that the election
  always concludes.

**WAVE 2 CLOSED MOST OF WHAT THAT SENTENCE LISTED (later the same day):
C7, C17, C18, C22, B2, B5, D5, D10.** Five new gates, all landing green and all
mutation-tested rather than attested:

- **C7, the holde-em ratchet - the largest item here - is BUILT and ADVISORY.**
  It splits the one 15k-line file at its selftest boundary into a GAME region
  and a HARNESS region and asks the coverage question across the cut:
  **120/329 exercised, 209 named by nothing that runs.** The denominator is
  **380** public `he*` handlers (329 game + 51 harness), not the 379 four
  documents quoted. It prints without failing, but every property that would
  make its number a lie IS enforced - and that mattered immediately: a mutation
  test found an unterminated `/*` closing on a stray `*/` inside an ordinary
  line comment, swallowing 2,200 lines and taking 69 handlers out of the
  denominator, turning the row GREEN at 66/260. The floor catches it.
- **C18, binary freshness:** 24 committed libraries, 636 distinct `.lcb` binds,
  2,544 bind-vs-export resolutions, **18 ABI constants decoded straight out of
  committed machine code** (PE as well as ELF, so the Windows DLLs stop being
  skips), 6 of them confirmed by loading the library and calling the function.
  MANIFEST.sha256 proves a blob is unchanged; this proves it still matches its
  source.
- **C17 amended a decision brief rather than just adding a gate.** D-14 said the
  shim scaffolding "must NOT be byte-identical, so byte-unification is not even
  the right goal". Measured: true of the record codecs (275/198/202 lines, three
  registries), **false of the handle table, which normalises to 89 code lines
  and ONE digest in all three members**. Suite rule 4 IS that header, three
  times.
- **C22** gave onionxt's skips a counter and the merge path a floor - the last
  place in the paste where a member could quietly test a third less than it
  claims while the one summary line read green.
- **B2** replaced the runbook's hand-typed five-probe PREREQ with a generated
  one-paste preflight stack whose six expected-ABI numbers are read from the C
  shims, so an ABI skew is found at minute two instead of minute fifteen.

**Still open: all of section A, B4, B7, D4, D9, D14, and every one of section
E.** Section A is now the bulk of what remains, and it is genuine feature work
rather than measurement.

---

## THE FOURTH EXHAUSTION BANNER, AND WHY IT KEEPS FAILING

`docs/REMAINING-WORK.md` carries three banners declaring the headless column
exhausted, each refuted by a later re-ask. This is the fourth data point in
the same direction, and it has a cause worth naming rather than apologising
for:

> **This tree's rate of change outruns its rate of self-description.** Five
> engine runs landed on 2026-08-16/17 and closed real work. Nothing that
> *describes* the tree was swept afterwards. Within hours the runbook
> carried nine wrong facts, the punch list fifteen false-open entries, the
> decisions file twelve drifted citations - and the suite's only
> cross-member name-resolution gate was silently blind to a third of one
> member while printing `OK`.

The reading is not "we keep failing to be exhaustive." It is that
**descriptions rot and checks do not**, so the highest-ranked items below are
the ones that convert a description into a check. Each retires a class rather
than an instance. After they land, the honest answer to "is there headless
work left" gets meaningfully cheaper to compute.

---

## CLOSED IN THIS AUDIT

**C1 - `check-handler-calls.py` could not see a third of nocloud, and said
OK** (commit `395b267`). **[M]** Found, fixed, and gated during the compile.
`strip_noise()` ran four rules in four separate passes and the ordering was
wrong in both directions at once: a `--` line comment merely MENTIONING a
route glob (`/_qs/*`) OPENED a phantom block comment, and an HTTP header
string carrying `Content-Range: bytes */` CLOSED one. In
`nocloud/src/nocloudquickshare.livecodescript` both fired - two phantom
blocks swallowed **2,476 of 7,541 lines (33%)**, the second running to
end-of-file. Cost: **42 handler names** missing from the "does this name
exist?" set that is the gate's entire reason to exist, every call in that
third unscanned, and - because `check_file` numbers the lines it is handed -
every reported line number after the first phantom open shifted by up to
2,476. The same root cause had a fourth face: `--` or `//` INSIDE a string
truncated the line, so `heTSkip "... sxSha3_256 -- " & tX` leaked its own
message text into the candidate set as a phantom call.

Fixed with one character-wise walk that knows which construct it is inside,
and pinned by `tools/test-handler-calls.py` (12 fixtures, wired into
`build-all.sh`). Driven against the pre-fix scanner **6 fixtures fire and so
do all three pipeline checks** - the root lesson is that a gate must be
exercised the way the build runs it, not the way its docstring reads, so the
last check runs the real collector over the real tree. `4592 -> 4634`
handlers known. No call in the tree was actually dangling: this was
structural blindness, not a hidden dead call.

---

## A. BUILD NOW - substantial unbuilt slices

**A1. Batch the Level 2 mask step: 312 FFI crossings -> ~56** - holde-em,
medium. **[S]** `heL2MaskDeckHex` (`holdem.livecodescript:2366-2402`) masks
52 points one at a time through `heL2MaskPointHex`, six FFI crossings each;
the batch handler that exists to fix this has one caller. Add a fast path
behind `heL2HasDleq()` calling `sxRistrettoScalarMultBatch`
(`sodiumxt/src/sodium.lcb:1839`), keeping the per-point loop as fallback the
way the DLEQ verify at :2773 is gated. Fix the two wrong figures in the same
commit (the comment at :2367-2368 and `IMPLEMENTATION-PLAN.md:437-438` both
say 52). *Buys:* turns phase 4f from "spend a session measuring a hitch"
into "confirm a fix", and gives `sxRistrettoScalarMultBatch` its first real
caller.

**A2. Chunked-post rail: producer + reassembling walker** - riptide, medium.
**[S]** `rsBuildPostChunked` (`riptide.livecodescript:809`) and the kind-C
parse branch (:950-977) both exist; nothing produces or reassembles one. The
demo renders `tPost["text"]` with no kind branch, so a kind-C post displays
as a **verified post with blank text** - the worst failure shape, because
`authorSig` passes. Pin first (`build_post_chunked` at
`riptide/tools/riptide_reference.py:532` is referenced by nothing), then
build. Kind C is the ONLY unpinned riptide wire format.

**A3. BTXO receive path: frame parser + stream reassembler** - riptide,
medium. **[S]** Four `rsBtxo*` handlers, all builders; no frame parser and no
length-prefix state machine, and `rsBtxoParseHeader` refuses unless the
caller already knows the header's length, so a stream reader cannot find the
boundary. Port caps from nocloud's working reference rather than re-deriving.
*Buys:* the scarce live-Tor slot spends its minutes on reachability instead
of parser bugs.

**A4. Pin the Channels BTXC/BTXF wire in `onion_frame_golden.py`** -
torrentxt, medium. **[S]** `ONIONXT-INTEGRATION-PLAN.md:1645-1646` requires
it; the golden contains neither token. `chSafeLeaf` is a separate
implementation from the pinned `qsSafeLeaf`, so it is genuinely unpinned.
This layer is scheduled for S2 item 4 and S4 items 1-2 - the two scarcest
session types. A framing bug caught by a golden costs minutes; the same bug
on a two-machine Tor session costs the session.

**A5. Property-fuzz the Level 2 void-and-audit attribution machine** -
holde-em, medium. **[S]** The highest-consequence pure logic in the project -
naming a cheater from signed records - is covered by a hand transcription
plus 15 pinned keys over six fixed situations, while every other pure layer
has an independent second opinion. Assert: an honest transcript never voids;
a voided hand names exactly one contributor; the named one is the injected
one. **State in the docstring that it exercises the twin, not the shipped
xTalk.** *Buys:* attribution bugs are the class an engine session cannot
find, because the engine runs the same six scenarios.

**A6. Pin the wire bodies `protocol-kat.py` never touches** - holde-em,
medium. **[S]** Ten of the 20 types in the vocabulary at
`holdem.livecodescript:4244-4250` have zero occurrences as a quoted wire type
in `protocol-kat.py`. The whole deal-delivery half of the protocol can change
format with all 114 pins green. Add a COVERAGE assertion parsing the type
list out of the source so a new type cannot arrive unpinned.

---

## B. ENGINE-PASS PREP - multiplies scarce engine minutes

**B1. Runbook truth sweep** - docs, small. **[M for the two spot-checked
rows, S for the table]** The single highest engine-minute return in the
survey. Measured discrepancies include:

| runbook says | measured |
|---|---|
| coverage :667-674 -> 377/395, no box2dxt row | gate -> **724/742** |
| :531/:988/:1018 coinxt "ABI 5"/"ABI 4" | `coinxt/native/coinxt.c:105` -> **6** |
| :55, :1406 `kHeVersion 0.20.0` | `holdem.livecodescript:980` -> **0.24.3** |
| :699 "~430 KB" | `wc -c` -> **1,583,595** |
| :734 "all seven member harnesses" | **nine** folded |
| row 15 :356 holde-em "STILL NOT in the suite paste - run it as its own paste" | the paste carries **380** `he1*` handlers |

Row 15 alone costs an OXT launch in a sheet budgeting 12 minutes per row.
**Rewrite it rather than delete it** - the standalone paste is still wanted
for S1 item 4's hotseat play, which check 7d deliberately keeps unreachable
in the fold. Add tick rows for inventory 25-32; six never-marshalled surfaces
currently have no box to tick, so they get skipped.

**B2. One-paste engine preflight stack** - suite, medium. **[S]** The
runbook's PREREQ block is a hand-typed five-probe list. All six ABI constants
are machine-readable (`sodium_shim.h:53`, `coinxt.c:105`, `btx_abi.h:50`,
`enx_abi.h:21`, `dcx_abi.h:61`, `box2d_lc.c:56`). Emit
`tests/preflight.livecodescript` printing one found-vs-expected table.
**Share the constant extractor with C18** or the suite gains a seventh place
these numbers rot. *Buys:* moves install failures from minute fifteen of a
sixty-minute session to minute two.

**B3. Adaptive dispatcher cadence** - riptide, small. **[S]**
`RIPTIDE-SOCIAL-SPEC.md:559-561` names ~33 ms during a live session;
`riptide-social.livecodescript:119` is `constant kPollMs = 250`. Phases 5 and
6 are the main events of S3 and both are judged by feel; running that session
at 7.5x the designed interval risks a slot spent chasing sluggishness that is
a constant in the source. **Gate the repaint trio behind a timestamp** - a
straight fast tier would raise them from 4 Hz to 30 Hz.

**B4. Wire `enPeerStatus` into the Devices panel** - riptide, small. **[S]**
Spec :360-362 promises a live RTT/loss readout; the handler exists
(`enet.lcb:672`); grep across riptide returns zero hits. Sequence after C6.
*Buys:* turns "the draft was slow" into a report line.

**B5. Raise the Taproot fail-closed assertions** - coinxt, small. **[S]**
`coin-selftest.livecodescript:1339-1343` refuses through `stThrows2`, whose
body discards the message; the headless gate was upgraded away from exactly
that on 2026-08-16 after a mutation SURVIVED. Add `stThrowsText` -
**declaring `local tError`**, which the existing three do not; check 15 of the
unified checker requires a referenced catch variable to be declared.
*Buys:* makes an on-engine green mean what the headless green means.

**B6. Write the missing nocloud OXT-pass checklist items** - nocloud, small.
**[S]** §7 has three items and asks nobody to observe the service worker's
secure-context registration, the Range-seek claims, or SPA URLs. Measured
**59** unticked items, 0 ticked - `REMAINING-WORK.md:360`'s "48-item" is
wrong. This file is the script for S1 row S and S2 item 7; items that do not
exist do not get run.

**B7. Apply `btSetPieceDeadline` on the sequential media fetch** - riptide,
small. **[S]** Note the correction: it is *per piece* and `rsMediaFetch`'s
path is `btAddMagnet` - no metadata, no piece table - so a one-liner there
would set deadlines on pieces that do not exist. Add a separate handler
called once metadata arrives.

---

## C. DEFECTS AND GATE GAPS - fix before an engine run is spent on them

**C2. ~~The coverage gate counts a SKIP NOTE as coverage~~ FIXED 2026-08-17** -
suite tools, small. **[M]** `check-suite-coverage.py`'s hit scan was a bare
word-boundary regex over text that still contained string literals, so a handler
counted as exercised if a test LABEL spelled its name. It fired in the worst
direction available: torrentxt's harness ends with a section headed "not
auto-checked - confirm by hand", and the gate was accepting those notes - whose
content is that the handlers are NOT exercised - as proof that they were.

> **THE NUMBER WAS MEASURED THREE TIMES AND CAME OUT DIFFERENT EVERY TIME, AND
> THE TRAIL IS THE POINT.** The survey said five handlers, 719/742. This document
> said three, 721/742, with a blockquote "correcting" the survey. The fix
> measured **four, 720/742**. All three disagreed because each measured a
> DIFFERENT TEXT: the gate scans the harness with the embedded library spans CUT,
> and `btAddMagnet`'s only real call lives inside the cut riptide embed - so it
> looks covered before the cut and is a note after it. `cxBech32EncodeValues` is
> literal-only too and survives only via the dispatch carve-out. Both earlier
> counts, including this file's own correction of the survey, were right about
> one handler and wrong about the other. Measuring "the file" is not measuring
> "what the gate reads".

**Resolved by closing the gaps rather than exempting them, which changed the
answer again.** Three exemptions were written first and then REMOVED: the shims
check the handle or session FIRST and return an error code before anything
destructive runs, so every one of the four has a refusal leg that is safe,
offline and deterministic. `btMoveStorage(999999, ...)` returns -2 having moved
nothing; `btAddTorrentWithResume` on garbage returns 0 with "invalid resume
data" from the ec-overload. Writing the note's prose into `UNTESTABLE` would
have installed, as a considered decision, a paraphrase of the very sentence that
caused the bug. All four now have real checks. **torrentxt is 85/85 with zero
exemptions and the suite is back to 724/742 - the same number it advertised
before, true for the first time.**

**C3. Wire box2dxt's four written-but-unrun checks into `build-all.sh`** -
box2dxt, small. **[S, all four executed by the surveyor]**
`tools/build-all.sh:32` omits box2dxt from `CMAKE_MEMBERS`;
`grep -rn sync-embedded-kit tools/ .github/` returns **five prose mentions
and zero invocations**, while the tool itself asserts "CI fails until
sync-embedded-kit.py is re-run", and three files claim the C ABI runs under
ASan in build-all.sh. All four pass today. Cost: one word plus three `if`
blocks. *Buys:* the stale-embedded-Kit failure currently surfaces at **paste
time on an engine** - the scarce resource - and `check-ui-kit-drift.py`
grants box2dxt an exemption on the strength of a gate nobody runs.

**C4. nocloud: HEAD misses the route table and is answered by the SPA
fallback** - nocloud, small. **[S]** `HEAD /_qs/info` returns index.html at
200 with text/html, while `qsHttpAllow` unconditionally advertises
`GET, HEAD, OPTIONS`. Both transports share the path. A probe for a JSON
endpoint that returns an HTML page at 200 is exactly the class of answer that
burns a session chasing a phantom.

**C5. `qsFsSendText` sends a body on HEAD over Tor; its clearweb twin does
not** - nocloud, small. **[S]** Every non-file Tor reply ships its body in
answer to a HEAD. Write it up as wasted onion bandwidth plus a spec
violation, **not** a framing desync - the Tor path is close-per-response.

**C6. Key the LAN sync state by the signing device, not the enet peer** -
riptide, medium. **[S]** `raLanSyncReceive` keys six arrays by `pPeer`, but on
a joiner `sLanDevices` is written at exactly one place - **one key** - so
every relayed record from every device lands in one slot, and the sequence
guard compares interleaved counters. `raLanPaintDevices` iterates
`sLanDevices`, so on a joiner other devices never appear at all. The library
contract is already written at `riptide.livecodescript:2507` ("only a seq
strictly above the last one applied **for that device**"). **The existing
two-machine runbook has one non-host device and structurally cannot reach
this**; the first 3-device session produces silently wrong state with nothing
logged.

**C7. Harness-region coverage scanner for holde-em** - holde-em, medium.
**[M on the counts, S on the design]** Root `CLAUDE.md` records this as OPEN,
saying it needs "a way to scan the harness REGION of a single-file member,
which nothing in this suite has." Two corrections make it cheaper: the graph
walk already exists at `tools/check-suite-selftest.py:286-330` (check 7d) -
lift it; and the region is mechanically delimitable from
`command heRunSelftest` (`holdem.livecodescript:12076`) to EOF.

Measured here: **379 public `he*` handlers, 174 named by a
`heTest*`/`heProbe*` body, 205 named by nothing.** The doc's quoted 163 is
stale (the harness grew), and three surveyors produced three different
closure numbers under three different string conventions. **Do not inherit a
number - compute one under C2's convention, and commit measurement-only
first** so the honest figure is recorded before the ratchet bites. *Buys:*
the box2dxt precedent is the whole argument - running that ratchet found 211
of 313 Kit handlers unnamed by any test, and the five engine runs that
followed found four real Kit defects.

**C8. Close the ~15 pure holde-em handlers no test reaches** - holde-em,
small. **[S]** Two matter: `heTableInfohash` (:3636) is the spec-10 DHT
rendezvous id, and `heFingerprintOf` (:1529) is the display handle. Also
`heFitRect` (:10694) returns width `2*(tW div 2)` - one pixel short for odd
widths - while its own comment claims "integer div keeps it exact". **Decide
that pixel explicitly.** *Buys:* a silent off-by-one in a rendezvous id costs
a whole multi-machine session.

**C9. `heNetElectablePubs` elects sitting-out seats** - holde-em, small.
**[S]** `holdem.livecodescript:4486-4503` filters on seated + stack>0 +
not-host and never checks `sitOutBy`, against the spec's "lowest pubkey among
live **seated** players". Determinism holds by the code's own words - the
auto-sit-out is derived from the transcript alone. The handler IS reachable,
so what is untested is the **filter**: the defect is invisible to a *passing*
run. Retires a deterministic table-death path in the one layer whose written
contract is that the election always concludes.

**C10. `rsMediaCreate` leaks `itemDelimiter` as `/` for the session** -
riptide, small. **[S]** Set at `riptide.livecodescript:1446`; none of the
seven exits restore it. The demo already carries two point patches, one
quoting the observed symptom. An engine pass reports this as a mystery ("the
media list showed one entry"), not as a delimiter.

**C11-C16.** Small, well-cited, in the transports and crypto members:
`*FormatBytes` itemDelimiter twins in three carried helpers; `dcStartPolling`
missing enetxt's re-arm guard; `b2kPlayerDuckSet`/`StandUp` dropping the
shape's collision filter; **`oxHostOfSocket` breaking the loopback guard in
both directions** - for a bare IPv6 id item 1 is *empty* and
`oxHostIsLoopback` **accepts** it, a fail-open on a guard its own comment
calls security-critical; `dcSendText` truncating at the first embedded NUL
against an ABI header promising nothing is silently truncated; and
datachannelxt's negative assertions sitting at `< 0` where its sibling
asserts exact codes.

**C17. Handle-table drift gate for the three C++ shims** - medium. **[S]**
`OPEN-DECISIONS.md` D-14 says verbatim that the shim scaffolding "must NOT be
byte-identical, so byte-unification is not even the right goal." For the
handle table that is **false**: preprocessed and prefix-normalised, the three
headers are 89 code lines each and **hash identically**. The record codecs
genuinely diverge. No gate reads native code at all. Scope a gate to the
handle table alone so it pre-empts none of D-14's options, and amend the brief
- a brief decided on an untested assumption is D-01's recorded lesson.

**C18. Suite-level binary freshness gate** - suite, medium. **[S]** Only
coinxt has one. `nm -D` on each committed x86_64-linux ELF against that
member's `binds to` set resolves fully today (sodiumxt 91/91, torrentxt
78/78, enetxt 22/22, datachannelxt 32/32, box2dxt 370/370, coinxt 43/43).
MANIFEST.sha256 proves a blob is *unchanged*; nothing proves it still matches
its source. **One suite-level tool with a per-member table**, not six carried
copies. *Buys:* a MinGW build that lost an export currently reaches a user as
a load-time bind failure.

**C19. `.lcb`-to-C signature gate for box2dxt's 370 foreign bindings** -
small. **[S]** 370 binds against 370 `LC_API` definitions, 0 mismatches
today, nothing compares them; a mismatch surfaces at run time on an engine.
~35 lines, sub-second.

**C20. `cross-member-test.py` runs in zero CI lanes and prints green after
skipping 3 of 4 invariants** - suite, small. **[M]** Verified: the only call
site is `tools/build-all.sh:297`, **below** the `GATES_ONLY` exit at :259, and
both CI invocations (`suite-gates.yml:53`, `release-binaries.yml:625`) pass
`--gates`. Run with no shims built it prints "SKIP the ed25519 and BEP44
checks" then "**every cross-member invariant holds (measured natively, not
reasoned)**" and exits 0 - against its own docstring claiming CI says so on
every push. *Buys:* a silent regression in the sodiumxt/libtorrent ed25519
agreement would mint DHT mailboxes addressed to keys their owner cannot sign
for, and nothing would catch it until a human sat at an engine.

**C21. Put the repo-root and `tools/` scripts through the static gate** -
suite, small. **[S]** `ROOT_SCRIPTS` covers only `tests/`, and the member loop
walks only member dirs - so `start-here.livecodescript`,
`tools/ui-kit.livecodescript` and `tools/harness-scaffold.livecodescript` are
read by no static gate. Running the unified checker by hand,
**`harness-scaffold.livecodescript` fails with three undeclared-constant
findings**. Rule 5 says the static gate is law for script, and the two files
copied verbatim into 15 demos and 5 harnesses have never been through it. A
defect in a master is a defect in 15 files at once.

**C22. Give `stMergeReturned` a skip channel and a floor** - suite/onionxt,
medium. **[S]** onionxt's six skip sites touch no counter, and the core merges
onionxt through a parser with **no skip parameter**, so its skips can never
reach the summary. Removes the last place in the suite paste where an engine
run reads green while a member quietly tested less than it claims - and every
session's whole output is one verdict.

---

## D. DOC TRUTH - cheap, and the honesty convention stops working without it

**D1. `REMAINING-WORK.md` sweep - 15 false-open entries.** **[S]** Ten
section-A items are shipped and written present-tense-open (A.4 Model C: 629
onion/Tor matches in the Channels stack; A.5 all three anon-transport docs;
A.6, A.7, A.8, A.9, A.11, A.13, A.14, A.15). One cited handler,
`qsRebaseLocation`, **does not exist anywhere in the tree**. C.4 must be
*split* (its suite-selftest half is done - the gate prints `holde-em=380`;
its coverage-gate half is C7), and A.9 *rewritten* rather than struck
(`profileMetaTarget` has a parse and one assertion and **no reader
anywhere**). *Buys:* this is the index the next headless pass starts from,
and a shipped item listed as blocked is currently spending engine minutes.

**D2. Re-anchor `OPEN-DECISIONS.md`'s citations** - medium. **[S]** 54 unique
`path:line` citations, **12 confirmed mis-lands**, four into
`REMAINING-WORK.md` alone. The file's preamble attests every citation was
"re-verified against the tree on the compile date," which is now false.
Replace `file:line` with `file` plus a quoted anchor phrase and add a ~40-line
gate. The file's premise is "an owner can act on it in five minutes"; a
citation into unrelated prose ends that, and D-01's own lesson is that a brief
is only as good as its evidence.

**D3-D15.** `EXTENSIONS-OVERVIEW.md` claims 384/402 against 724/742 and
coinxt "80 handlers, ABI 4" against 90 and ABI 6, and has no holde-em section;
box2dxt's "374 foreign declarations" is **373** (`grep -c` counted prose) in
three files; the coinxt harness header says HD wallets and mnemonics "are
phase 4 and do not exist yet" while the file ships all four suites;
`SPEC.md:159` names `cxSeckeyValidate` for a handler shipped as
`cxSeckeyIsValid`; the anon-transport sign-off packet still calls the
Channels layer "a parallel workstream" the plan records as built; and
riptide's §9.3 attestation claims `rsPersonaAllows` guards "every
send/publish branch" when 16 transport sites are unguarded - **but that one
must be corrected as an attestation, not built as a runtime fix**, because
there is no active-persona state in the demo and 16 more calls would be 16
more compile-time constants that can never refuse.

---

## E. NOT NOW - and what each waits on

| Item | Waits on |
|---|---|
| Hold'em phase 4f deal-time budget, live exit gates | an engine; multi-machine |
| Hold'em phase 5 hostile review + soak | a human |
| Riptide phases 5-7 live passes | two machines, two networks; tor |
| The Tor evening (7 live-daemon exemptions, Mode B) | a tor daemon |
| Suite closing pass legs B-E | two machines |
| macOS universal binaries; torrentxt notarization | a Mac; credentials |
| coinxt Windows execution proof; sodiumxt mingw re-proof | a Windows box |
| box2dxt release lane glibc floor | an owner decision |
| nocloud §8 priority questions; Riptide feed retention | an owner decision |
| The 20 kit-converted demo re-opens | an engine (cheap, single-machine) |

---

## F. WHERE THE TREE IS HONESTLY NEAR ITS CEILING - and where it is not

**Near it, and not padded:**

- **enetxt and datachannelxt script layers.** 23/23 and 31/31 with zero
  exemptions, both with a shipped C harness under ASan. The four items found
  are all small and all listed. What remains is the async loopbacks, which
  root `CLAUDE.md` deliberately excludes from the fold because two state
  machines race for the event handlers - an engine, not a keyboard.
- **riptide's wire-format pinning.** 40 of 66 constants re-derived, every
  format covered except kind C (A2). After that pin lands there is nothing
  left to pin in that layer.

**Emphatically not near it, each with a measured number:**

- **box2dxt's C ABI: 60 of 370 exports executed.** `smoke_test.c` names 60;
  **310 are never executed**. The doc's argument for leaving this layer alone
  is explicitly about *script* assertions "with no engine to run them on" -
  **which does not transfer to a C harness**. This is the suite's biggest
  genuinely-open measurement hole and the only large one needing **no scarce
  resource at all**. It is not in section A only because C3 must land first;
  it should be the first thing promoted when it does.
- **holde-em's 379-handler surface**, unratcheted (C7): **174 named by a
  test, 205 by nothing**.
- **nocloud**: nothing anywhere executes a line of its shipped script, and
  until commit `395b267` its gate was blind to a third of it.
- **onionxt at 27/45**, the suite's only member with exemptions - and D12
  shows those exemptions currently claim more than they know.

---

## THE THREE TO DO FIRST

1. **C2 + C7 together** - decide the string convention once, stop the
   coverage gate counting prose, then compute holde-em's honest number under
   it. Two gates that currently overstate become two that do not.
2. **B1** - the runbook sweep. Highest engine-minute return in the survey:
   row 15 alone costs an OXT launch, and six never-marshalled surfaces have
   no box to tick.
3. **C3, then box2dxt's C ABI** - one word and three `if` blocks converts
   four written attestations into executed tests, and unblocks the largest
   headless measurement hole in the tree.
