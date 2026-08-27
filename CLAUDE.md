# CLAUDE.md — xTalk Suite

This file guides Claude Code (claude.ai/code) when working in the **suite**
(the monorepo root). It is intentionally thin: **each member owns its own
`CLAUDE.md`**, and that member file is the authority for its layer. When you
work inside `sodiumxt/`, `torrentxt/`, `enetxt/`, `datachannelxt/`, `onionxt/`,
or `coinxt/`, **read that member's `CLAUDE.md` first** — it carries the hard-won
lessons for that binding. This file records only what is true across all of
them and what the consolidation changed.

## What this repo is

The OpenXTalk library suite: eight sibling extensions for OXT / the xTalk family,
each a thin binding over a proven native library (or, for OnionXT, pure
LiveCodeScript over a local Tor daemon), consolidated into one repository so
they release, version, and interoperate as a suite. This monorepo is the
**source of truth**; the former standalone repositories (SodiumXT, OnionXT,
dataChannelXT, and the TorrentXT repo that once vendored enetxt/ and
datachannelxt/ as subfolders) become mirrors. Development happens here.

```
openxtalk-libraries/
  README.md            the suite front door + the honest release matrix
  start-here.livecodescript
                       the RUNNABLE front door: open it in OXT for a
                       clickable directory of every demo/harness stack by
                       repo-relative path (launches them in place; each
                       stack now CARRIES the libraries it needs, so no
                       helper is put in use first - the registry gate
                       prints "no row advertises a helper it already
                       carries"); a kit adopter, held
                       true to the tree by tools/check-launcher-registry.py
  CLAUDE.md            this file
  LICENSE              MIT + third-party attributions for every bundled lib
  docs/                CROSS-CUTTING documents (span >1 member)
  tools/build-all.sh   walk every buildable member
  .github/workflows/   the CI that runs: suite-gates + a native matrix per
                       member (member .github dirs are inert here)
  sodiumxt/  torrentxt/  enetxt/  datachannelxt/  onionxt/  coinxt/
  nostrxt/             the Nostr member, added 2026-08-23: pure LiveCodeScript
                       over coinxt (BIP-340, sha256, ECDH) and sodiumxt
                       (randomness); NIP-01 events with an OWNED canonical
                       serializer, NIP-19 bech32/TLV (uncapped, the NIP's own
                       waiver), the NIP-44 v2 construction COMPLETE since
                       2026-08-23 over sodiumxt ABI 10's sxChaCha20IetfXor
                       (its docs/07 request, shipped the same day; the seam
                       still fails closed on an older installed sodiumxt),
                       and a websocket relay client SPLIT into
                       a second file so the suite paste never carries a
                       second socketError definition; FIRST ENGINE PASS
                       2026-08-24 (Windows x86_64, OXT 9.6.3): 274/274 in
                       the suite paste, zero failures - every
                       interpreter-modeled engine-semantics pin held; the
                       relay layer's 2 skips are deliberate (not in the
                       paste) and still need their live pass
  box2dxt/             the family ANCESTOR, folded home 2026-08-14: Box2D v3
                       physics + the pure-script b2k game Kit (sprites, input,
                       camera); its checker was the oldest pre-unification
                       lineage, replaced in the fold; its examples are GAMES,
                       exempt from the ui-kit gate with written reasons; its
                       selftest became the EIGHTH folded member and its Kit the
                       fourth embedded script layer on 2026-08-16; the fold
                       record is in its CLAUDE.md
  riptide/             the capstone APP (not an extension): Riptide Social,
                       implementing docs/RIPTIDE-SOCIAL-SPEC.md phase by
                       phase in pure script; structured like a member so the
                       gate machinery walks it; has its own CLAUDE.md
  nocloud/             a SHIPPED APP (not an extension): No Cloud Quick Share,
                       one stack over torrentxt (+ optional sodiumxt/onionxt),
                       folded in from its standalone repo 2026-08-13 (that
                       repo becomes a mirror, like the other pre-suite repos);
                       member-shaped so the gates walk it; its checker copy
                       was replaced with the unified one in the fold commit;
                       has its own CLAUDE.md
  holde-em/            the second capstone APP: serverless Texas Hold'em over
                       torrentxt/sodiumxt (+ box2dxt Kit art, optional
                       onionxt), one paste-and-run stack, folded home
                       2026-08-15 at v0.18.0 (hotseat + online play built;
                       oracle and mental-poker phases open); its checker was
                       replaced with the unified copy (two real deal-path
                       traps fixed in the fold) and its old lineage checks
                       were UNIONED into that checker 2026-08-15 (docstring
                       13-21; the idiom gate file is retired); seven KAT
                       mirrors + an independent-reference fuzz ride
                       build-all; the fold record is in its CLAUDE.md - which
                       also carries the 2026-08-16 assessment that named the
                       five pieces of missing fold machinery and the one real
                       defect keeping its harness OUT of the suite paste, and
                       then the record of the fold itself once all six were
                       cleared: it is the NINTH member harness since
                       2026-08-16, and the only one whose fold carries a whole
                       APPLICATION, because its game and its tests are one
                       file
```

Each member stays a **self-contained extension**: its own `CMakeLists.txt` /
`build.sh`, `src/`, `tests/`, `tools/`, `docs/`, and the bundled per-platform
native library under `src/code/<arch>-<platform>/`. Nothing about a member's
internal layout changed in the move — it was copied in verbatim from its
tracked files (via `git archive`, so no build artifacts came along).

## The rules that hold across every member

These are summarized in `README.md`; the operational point for editing is:

1. **Never call an xTalk handler from a foreign thread** — events poll-drain on
   a timer; no callback runs script.
2. **The exception firewall** — every `extern "C"` body is
   `try { … } catch (...) { set_error; return err; }`; nothing crosses the FFI.
3. **Payload avoids the FFI into script** where the design allows; only small
   status records and events cross.
4. **Generation-tagged integer handles**, validated before use — a stale handle
   is a harmless no-op.
5. **The static gate is law for script.** Every member carries
   `tools/check-livecodescript.py` (ASCII only; the `k`/`p`/`s`/`t`
   token-shadow trap; literal constants before first use, both dialects;
   declarations at handler top in `.lcb` - measured, NOT enforced for
   `.livecodescript`, where mid-handler `local` is legal and stands in
   engine-passed code; `unsafe` around foreign calls; block balance including
   `switch`; the zero-arg-statement-call and throw-in-catch refusals; and the
   per-dialect antipattern sets). The copies are UNIFIED and byte-identical:
   `tools/check-checker-drift.py` fails the build if any copy differs, and
   `tools/test-checker.py` fixture-tests every rule in every copy. A
   `.lcb`/`.livecodescript` change is not "done" until that gate passes; a
   shim change is not "done" until the member's smoke test passes under
   ASan/UBSan; a native-library change is not "done" until the member's
   committed `src/code/<arch>-<platform>/` binary is refreshed in the same
   change.
6. **The honesty convention** — "verified statically; needs an OXT pass"
   (Tor: "+ live-Tor pass") for anything not observed on a real engine.

> **Engine BEHAVIOUR - as opposed to the conventions above - is collected in
> [`docs/OXT-ENGINE-NOTES.md`](docs/OXT-ENGINE-NOTES.md)**, with the verbatim
> symptom, what each one broke, and whether a gate now holds it. That file is
> where the four member gotcha sections already point, and this root file holds
> engine lessons of exactly that class - the `dcCleanup()` statement call, the
> DECLARED-is-not-IN-SCOPE fold, the undeclared name that evaluates to its own
> spelling - so read it as the authoritative list and treat the accounts below
> as the dated stories behind particular entries. Anything the ENGINE does goes
> there; what belongs here is what is true across the members.

**Demo UI is ONE carried kit, and adoption is enforced (v2, 2026-08-14).**
`tools/ui-kit.livecodescript` is the master for the family look. v1 was the
flat style; **v2 is the "card look"** absorbed from its best implementations
rather than invented (nocloud's tokens/panels/soft shadows/measured labels/
platform mono/pill, dht-channels' section dividers, torrent-client's copy
flash) — chrome with a semantic status line, white rounded panels on a cool
page, mono data surfaces, the honesty footer. Adopting stacks embed the
block verbatim between its marker lines (each demo stays a single
paste-and-run file), and `tools/check-ui-kit-drift.py`, in the gate set,
holds every copy byte-identical, refuses unregistered carriers, **and
refuses any window-building stack that neither adopts nor carries a written
exemption** — so "every demo is a kit adopter" is a property of the tree,
not of one cleanup pass. A look change edits the master and re-carries; it
is never patched inside an adopter. The 2026-08-14 fleet pass converted
every demo (the members' examples, both apps' stacks) and paired each
conversion with that stack's audit fixes (validated create/connect returns
with last-errors surfaced, watchdogs on silent async waits, fail-closed
probes, guarded teardown) — so every converted stack's honesty label reads
"UI unified 2026-08-14; needs an OXT re-pass" regardless of its earlier
evidence.

**Every demo prints its own record, from a FOURTH carried block (2026-08-20).**
`tools/demo-selfcheck.livecodescript` is the master for the boot self-check that
thirteen runnable stacks now run on open, held byte-identical by
`tools/check-demo-selfcheck-drift.py` in the gate set (it prints the live count;
this sentence is the kind of hand-copied number this file warns about, so trust
the gate, not the word). It exists because a demo
pass produced a human judgement - "the window built, it looked right" - and no
honesty label can quote that, which made the fleet-wide demo re-pass the most
expensive engine time in the project and the least recoverable. The block owns
the counters, the PASS/FAIL/SKIP lines, the completeness trailer and the
delayed-write probe; a demo owns only its assertions, one handler, and one line
in `openStack` (or `preOpenStack` - three demos define no `openStack` at all).
The gate refuses four things, and the fourth is the one a copy-paste rollout
actually produces: a demo that carries the block, ships the plumbing, and
reports nothing because it never calls `scBegin` or never reaches its run
handler. It was made a carried block from the START rather than after the
drift, which is the one lesson the three blocks above were each taught the
expensive way.

Two things about it generalise. **The control list is DERIVED from each source,
not hand-picked** - and getting that derivation right took three passes, each
failing the same way: matching only `field "x"` references missed five of
datachannel-loopback's eight (it reaches both logs through a variable, so the
kit's builder calls had to be matched too); a single-prefix filter dropped all
26 of onionxt-demo's `about:`/`dial:`/`svc:` names; and with the filter gone,
four demos gained a control named `x`, scraped out of the comment explaining the
first bug. Comments are cut now by a scanner that tracks string state, because
the usual noise-stripper blanks literals and the literals are what this scan
reads - the third time in one session that comment-vs-literal handling silently
changed an answer. **And the block fails LOUD but passes QUIET**: `scFinish`
paints the status line only when something failed, because a green demo's own
"Ready ..." line is the more useful thing to be reading and a red one's log may
be on a tab nobody has clicked.

**The five pasteable harnesses share ONE carried scaffold (2026-08-14).**
`tools/harness-scaffold.livecodescript` is the master for the selftest
window + counters + assertion plumbing (Copy results, SKIP as a first-class
outcome, per-line result paint, per-section failure isolation), carried
byte-identical into the four member selftests and the suite core with
`tools/check-harness-scaffold-drift.py` in the gate set. Since 2026-08-20 it
also owns **the report's own completeness marker**, and the reason is the
house failure shape one level out from the code: the report is a LIVE surface
re-rendered every 33 ms tick, so a run still in its async loopbacks simply
STOPS growing - at whatever section the pump had reached, with no marker - and
reads exactly like a hang. A fully green Windows pass came back that way on
2026-08-19, ending mid-CROSS-section, and nothing in the pasted text could
tell an early Copy from a stalled pump. Every render now goes through
`stReportText()`, which appends a `RUN NOT FINISHED` trailer until
`stReportDone`; `Copy results` carries that trailer onto the clipboard, says
so in its dialog, and takes the counts with it (they live in a second field
and the runbook used to teach a message-box incantation to fetch them by
hand). The deadline is 40s, so "it looks finished" is the normal state of a
run that is not. It settled its own question on first use: the next paste
came back CARRYING the trailer, and the run after it - same build, allowed to
finish - completed **1981/0/1** through both live loopbacks, teardown and the
summary. All three truncated reports were early copies; nothing was ever wrong
with the pump, and the mid-diagnosis guess that a first-tick throw had killed
the timer chain was wrong. What that guess left behind is still worth having and
is recorded honestly as precautionary: `stShow`/`stPaint` now pin the
defaultStack, `stPump`'s render is contained so a lost render can never cost the
run, and `tools/check-timer-stack-pin.py` walks a real same-file closure instead
of one hard-coded callee list - which found **40 unpinned timer chains across 15
files**, every demo's own log/refresh helper reached from its poll tick. That
class IS engine-observed (enet-lan-chat's `ecDashOnce`, 2026-08-18); these 40
are not, and the gate's docstring says so. The fold machinery
keeps its split: the generator drops the scaffold's window half from folded
members and stubs `stShow`/`stPaint`; the counters and plumbing fold in and
run, and `stMergeCounted` now carries member skip counts into the suite
totals. Harnesses are deliberately NOT kit adopters (a second 300-line
block would bloat every paste); the scaffold matches the kit's look BY
VALUE, and the kit gate's exemption list records exactly that.

**Every demo carries the libraries it needs, and the ORDER is load-bearing
(2026-08-17).** `tools/sync-demo-embeds.py` is the third carried-block family
here, and it works like the two above: the master is
`<member>/src/*.livecodescript` - still the single source of truth and the right
dependency for a real project - a verbatim copy lives between sentinels in each
shipped demo, and `--check` is in the gate set and fails the build when a copy
drifts. FIFTEEN demos carry a library today (the gate prints the count; take it
from there, not from here); nobody hand-edits inside the sentinels.
The point is that `start using stack "coinxt"` is a wiring step most readers
meet as an error message, so a demo stays ONE file you paste and open. **The
embed goes ABOVE the demo's own code** (below its `script "..."` line and its
header prose, which is what a reader opened the file for) **and the providers go
in dependency order within it**, because OXT resolves script-level `constant` and
`local` by lexical position - the same rule the 106-declaration fold recorded
below cost an engine pass to learn, and it fails the same way, as a tidy wrong
answer rather than an error. **Collisions are refused, never merged**: a demo and
a library defining the same handler or the same column-0 declaration would not
compile, and the maintainer meets that at PASTE time on an engine, so the tool
names both sides and stops. Unlike the ui-kit gate it does not scan the tree - it
is registry-driven, and a demo it does not list is a demo it does not see - so
the one non-embed is recorded in `NOT_EMBEDDED` with its reason
(torrent-quickshare's real `socketError`/`socketClosed`/`socketTimeout` bodies
that pass through to OnionXT's copies; merging two live bodies is a behaviour
change to an inbound path with no engine pass). Two couplings are easy to break
by tidying, and both are in the tool with the reason: the embed banner must NOT
say "GENERATED - do not edit", because `check-ui-kit-drift.py` and
`check-harness-scaffold-drift.py` SKIP any file whose first 4000 characters
contain that phrase and these demos are only PARTLY generated - bannering them
would silently switch UI-kit drift checking off for every one; and a provider's
leading `script "..."` line is stripped before embedding, because a second
script-name line mid-file puts everything after it outside the demo's own
declaration scope. This replaced `onionxt/tools/build-standalone.py` and both
generated `*-standalone` twins: embedding in place leaves one file to open rather
than a source and a launchable copy of it.

**And the engine's OWN names needed a second answer (2026-08-24).** The gate above
holds every LIBRARY name disjoint, which is what makes co-embedding safe - but three
names can never be made disjoint, because they are the ENGINE's: `socketError`,
`socketClosed`, `socketTimeout`. Every socket library declares all three, no script
can define one twice, and an embed builds exactly one script. That is why OnionXT
could not go inside an app that runs its own sockets, and why nocloud shipped with a
manual `start using stack "onionxt"` step. The fix is a SPLIT, not a merge: onionxt
and nostrxt's relay layer now keep their logic in named functions (`oxSocketError`,
`nxrSocketError`, ...) that answer one question - *was that socket mine, and did I
handle it?* - with the `on socket*` handlers reduced to dispatch. An embedder drops
the three thin wrappers (`tools/sync-demo-embeds.py`'s `DROP_HANDLERS`, keyed by
(app, library) PAIR and never by library, because the five carriers that define no
socket handlers of their own would be left with nothing listening - a silent hang)
and calls the named function where it would otherwise `pass`. No logic is copied, so
nothing can go stale, and both halves are asserted: the embedder must define the
handler it drops, and the library must still define the named replacement. nocloud
is the first app to carry OnionXT this way. The "false for a socket that is not
ours" contract is pinned offline in both members' harnesses, because getting it
wrong is a hang rather than an error.

**One name, one library, suite-wide (2026-08-23).** The interoperability the
suite advertises - any libraries co-loaded, any pair co-embedded into one
paste - puts every library's names into ONE namespace, and until 2026-08-23 no
gate looked ACROSS libraries: `check-duplicate-declarations.py` is per-file by
design, and the embed tools compare only the combinations actually registered.
Measured the day nostrxt landed, the gap was real twice over: the enet and
datachannel helper layers shared four script-local names (`sPolling` among
them, the name that already reached an engine once as 1.6's collision), and
TWO libraries defined the engine's socket messages with only one passing
foreign sockets on - onionxt's own copies swallowed them, which co-loaded with
nostrxt's relay layer is the silent-hang rule onionxt itself documents for
apps. Both fixed; `tools/check-cross-library-names.py` now holds the whole
library corpus disjoint (handlers public and private, column-0 declarations,
the engine messages' `pass` discipline, and a public-prefix ratchet that
catches the NEXT collision before a second claimant exists), and
`tools/test-cross-library-names.py` mutation-proves each check by editing a
real corpus file in place and expecting the gate to fire - exercised the way
the build runs it, per this file's own mutation-test lesson. Stack-shaped
files (demos, harnesses, the apps) are deliberately out of that corpus, with
the reason written in the gate's docstring.

**The gate added on 2026-08-26, and the rot it is standing in for.**
`tools/check-doc-status-consistency.py` (with `tools/test-doc-status-consistency.py`
pinning both directions) refuses a BLANKET "nothing here has run on an engine"
that is not followed, in the same paragraph, by the dated record that closed it.
It exists because nostrxt's first engine pass (2026-08-24, 274/274) was written
into five documents and not into the other seven, so the member spent two days
asserting both that its core was engine-proven and that nothing in it had ever
met an engine - and two SUITE documents carried the same stranded sentence, one
of them four lines under its own bullet recording the pass. **This is the
honesty convention failing in the UNDERSTATING direction, which is why it went
unnoticed**: that direction feels safe, and it is not. The convention's whole
value is that a label is worth reading, and a label saying "unproven" over 274
green checks teaches a reader to skip labels - after which the ones that matter
stop working too. The rule turns on DIRECTION and nothing else: a negative
followed by "...until 2026-08-24, when the first engine pass ran green" is a
RECORD and passes; a negative with the dated positive only BEFORE it is a
sentence that survived an edit which should have removed it, and fails. Scoped
negatives ("the receive leg has not run on an engine") are invisible to it, and
must be - they are what the convention REQUIRES. Both of its regressions were
introduced while fixing the other (an em-dash bridge that flagged holde-em's
correctly-scoped DLEQ claim; then a newline ban that blinded it to coinxt's
hard-wrapped one), so the fixtures pin both and `build-all.sh` runs the fixture
suite BEFORE the gate: a gate that has gone blind reports OK, and the
discriminating test is what makes the OK mean anything.

**The gates added on 2026-08-17/18, and what each one is standing in for.** All
of them document behaviour already recorded in `docs/OXT-ENGINE-NOTES.md`; none
of them has been through an engine pass of its own, and none upgrades an honesty
label. **`tools/check-lcb-call-types.py`** (with `tools/test-lcb-call-types.py`
proving its fixtures still discriminate) walks the script -> `.lcb` boundary
argument by argument, because that boundary is TYPED and none of the 630 public
`.lcb` handlers has an optional parameter: an empty value into `in pHost as
Integer` is a hard runtime error, not a no-op (engine notes 6.4), which is how
`enet-lan-chat`'s unguarded `enHostDestroy` killed its own poll chain, and how
eight teardown paths in the folded harnesses would have taken the whole
~1900-check paste down on a setup that should merely have SKIPPED. Its check 4 asks a
different question on the same data and is the one that found a shipped defect:
an event name and a handler name share ONE xTalk message namespace (engine notes
6.7), so dispatching the event `dcLocalDescription` reached the public getter
`dcLocalDescription(in pPeer as Integer)` with the event Array - which is why
`datachannel-loopback`'s `on dcLocalDescription` had never fired once since the
day it was written, and why `datachannelxt/docs/getting-started.md` taught the
same unreachable shape. **`tools/check-timer-stack-pin.py`** holds the rule that
an unqualified control reference inside a delayed handler resolves against THE
DEFAULTSTACK, not the stack whose script is running (engine notes 5.3): inside `openStack` those
are the same object, which is exactly why every demo's startup status line always
worked and every `send ... in` status line did not. The kit half of the fix lives
in the ui-kit MASTER (`uiStatus`, `uiCopyFlashReset`) and is re-carried, never
patched in an adopter. **The gate was widened on 2026-08-20 from one hop to a
real closure** - same-file callees plus the kit, stopping at any handler that
already pins, because below a pin the defaultStack is set - and the widening is
the lesson: asking only "does this call an unpinned `ui*` handler?" was a check
for the bug already found. As a closure it named 40 unpinned timer chains across
15 files, every demo's own log/refresh/status helper reached from its poll tick;
all 33 distinct handlers are pinned at the timer ENTRY POINT, where one line
covers everything downstream. **`tools/sync-demo-embeds.py` / `tools/test-demo-embeds.py`** are the
paragraph above; the fixtures exist because that tool's collision detector
shipped blind - it required the remainder of a declaration line to be a bare
identifier, so a `local` with a trailing comment was invisible to it and a
duplicate `local sPolling` reached an engine as a hard compile error.
**`tools/build-preflight.py`** generates `tests/preflight.livecodescript`, the
one-paste "can this machine run the pass at all?" stack, rather than letting
anyone hand-copy its six expected ABI numbers: those are C macros in the members'
shims, and a hand-copied number goes stale SILENTLY at the next bump, which is
the failure this file already records for every other copied constant. Extracting
them buys three cross-checks free - the C macro against the `.lcb` binding
literal, every ABI guard's throw text actually containing `ABI `, and the macOS
sodiumxt-skew sentence quoted from `sodiumxt/CLAUDE.md` rather than paraphrased.
Four older suite gates had never been named here either, and each is worth
knowing before you push: `check-handler-calls.py` (with `test-handler-calls.py`)
proves every handler CALLED across a member boundary actually exists, the gate
that would have caught the shipped example calling `sxHashKey`;
`check-shim-scaffold-drift.py` holds the one handle table that lives in three C++
shims, so rule 4 does not get quietly weaker in two members;
`check-binary-freshness.py` is the automated half of rule 5, catching a shim that
gained, lost or renamed an export without its committed library being rebuilt;
and `check-stack-size.py` reads each stack's own window size and holds it inside
the family's 720p budget, because the two-machine passes happen on whatever
hardware is in the room and a section below the bottom edge is a leg that does
not get closed.

## The unified self-test is GENERATED

`tests/suite-selftest.livecodescript` is the one script a maintainer pastes into
an OXT stack to exercise the whole suite, and it is **built, not written**:

```sh
python3 tools/build-suite-selftest.py            # rebuild after touching any harness
python3 tools/build-suite-selftest.py --check    # in the gate set
python3 tools/check-suite-selftest.py            # the checks a compiler would make
python3 tools/check-suite-coverage.py            # does it actually reach the suite?
```

Those four are the harness's own gates, not the whole set. **The authoritative
list of suite-level gates is the `== suite: tools/...` block in
`tools/build-all.sh`**, and `tools/build-all.sh --gates` runs that block plus
every member's own `run_gates` walk, compiler-free - the same set
`suite-gates.yml` runs on every push. Read the script when you want to know what
will fail, because it is the thing that runs. Deliberately no count is written
here: a number would be true the day it was measured and false the next time a
gate lands, silently, which is the same failure this file records for
hand-copied ABI numbers and for the coinxt constant gate that reported what it
had parsed as what it had checked. Do not build the list by globbing `tools/*.py`
either. **The example this sentence used to give has expired, and how it expired
is the better argument.** It read: `check-doc-anchors.py` sits there invoked by
nothing, so a glob would name a gate that does not run. That tool was wired into
the suite gate block on 2026-08-19 and today every one of the 33 files in
`tools/` is invoked by `build-all.sh` - so the glob would now be accidentally
right, which is worse than being wrong, because nothing would tell you when it
stopped being. The durable reason stands: those 33 are not 33 GATES. Ten are
fixture tests (`test-*.py`), four are generators and installers
(`build-suite-selftest.py`, `build-preflight.py`, `sync-demo-embeds.py`,
`install-release-binaries.py`) that WRITE the tree rather than judging it, and a
glob would silently adopt whatever lands in the directory next. Read the script.
The paragraphs above and below name only the gates whose WHY needs prose.

It is assembled from `tests/suite-selftest.core.livecodescript` (hand-maintained:
the UI, the probe, the runner, and the cross-member sections) plus **every
member's own deep self-test** (TEN since 2026-08-23, when nostrxt joined: the
seven extensions,
riptide's harness — which now spans phases 1-4, 6, and 7 plus the spec-8.3
sealed-anon-DM crypto — box2dxt's, and holde-em's, folded in with each one's
names prefixed), plus — since 2026-08-10 — **the pure-script LIBRARIES themselves**,
`coinxt/src/coinxt.livecodescript`, `onionxt/src/onionxt.livecodescript`,
(since 2026-08-11) `riptide/src/riptide.livecodescript` and (since 2026-08-16)
`box2dxt/src/box2dxt-kit.livecodescript`,
embedded VERBATIM (no prefixing: the tests must call them by their real names).
The embed exists because the old "two `start using` lines" setup step cost a
real engine pass: a fresh harness ran against a stale in-memory coinxt stack
and reported exactly the failures whose fix was already merged. One paste now
carries the code its tests test, and `--check` pins both to one tree - which
also means **a script-layer edit is not done until every carrier of that layer
is re-run**, exactly like a member-harness edit. Since 2026-08-17 there are TWO:
`python3 tools/build-suite-selftest.py` for the suite paste, and
`python3 tools/sync-demo-embeds.py` for the demos, which carry these same
libraries verbatim between sentinels so a demo is one paste-and-run file (10
demos in its REGISTRY; onionxt's layer alone is in five of them). Both
`--check`s are in the gate set, so skipping one fails the build rather than
shipping a demo that runs last week's library - but the build failing is the
backstop, not the instruction. **The two carrier sets overlap and neither
contains the other**: `box2dxt/src/box2dxt-kit.livecodescript` is in the paste
and in no demo (its second carrier is `box2dxt/tools/sync-embedded-kit.py`,
below), while `onionxt/src/onion-httpd.livecodescript` is in three demos and
deliberately NOT in the paste - it is an app over the `ox*` surface, not part of
it, and `check-suite-coverage.py` measures that surface against
`src/onionxt.livecodescript` only. Edit the member file, not any generated copy.

Eight things about it are worth knowing before you touch it:

- **The embedded libraries sit between sentinel lines, and the coverage gate
  depends on them.** A library's body names nearly its whole own API
  (`cxMnemonicToSeed` calls `cxMnemonicNormalize`; the socket dispatchers name
  every callback), and none of those mentions is a test. So
  `check-suite-coverage.py` CUTS the `GENERATED EMBED` spans before it scans
  for calls — measured uncut, it reported a fake 309/309 with the 18
  live-daemon/engine-event exemptions silently absorbed — and it FAILS, rather
  than falling back, on a harness with no spans to cut. The sentinel format is
  a contract between the generator and that gate; change both together. The
  generator also refuses to write an assembly where any handler or
  script-level declaration is defined twice, because the embedded layers are
  unprefixed and a script-level duplicate would make two units silently share
  one variable.

- **BOX2DXT IS THE ODD FOLD, and it needed three mechanisms nothing else did
  (2026-08-16).** Its harness is a paste-and-run STACK, not a test file. It
  carries a verbatim copy of the b2k Kit between sentinels (its own
  `tools/sync-embedded-kit.py` owns that region), so the generator CUTS that
  copy (`strip_spans`) and embeds the Kit ONCE, from `src/`, as a fourth script
  layer — otherwise all 313 `b2k*` handlers would be defined twice, which is a
  compile error the maintainer meets at paste time, on an engine. It hangs its
  window off the CARD hooks rather than the stack ones, so `openCard`,
  `closeCard` and its own `buildStUI` join the drop set (`drop_extra`). And
  three of the names it defines — `b2kFell`, `b2kSensorEnter`, `b2kContact` —
  are message RECEIVERS the embedded Kit dispatches BY LITERAL NAME, so they
  are the one exception to the prefixing rule below (`keep_names`): a
  `b21b2kFell` would simply never be dispatched to, and the three checks that
  prove the Kit's message path works would report zero events and read like a
  defect in the dispatcher. All three mechanisms assert their inputs still
  exist, so a rename in the member harness fails the build instead of silently
  leaving a stale exemption behind.

- **HOLDE-EM IS THE OTHER ODD FOLD, and it needed almost none of that
  (2026-08-16).** It is the second paste-and-run stack, but it differs in the
  one way that decides the shape: **its game and its harness are THE SAME
  FILE**, so there is nothing to embed and the whole 15k-line application
  folds in PREFIXED alongside the tests that drive it. That is safe for the
  reason the verbatim embeds exist to work around — the layers stay unprefixed
  because their tests live in a DIFFERENT file and must reach them by their
  real names, and here both sides are renamed together. Measured: of 6950
  string literals in code, `rename()` touches 45, every one a message name
  armed by `send`/dispatched by `do` or prose in a test label; all 165
  `constant` values are byte-identical in the output, and un-prefixing the
  folded section diffs against the source, minus its dropped chrome, to ONE
  hunk. Verbatim would have been the wrong call twice over: 389 unprefixed
  handlers into a paste already carrying 928, and — decisively — its
  `on b2kFrame` would have started receiving the embedded Kit's frame messages
  during box2dxt's deterministic hand-stepping, because box2dxt's harness
  registers `b2kFrameTarget the long id of me` and in the paste that is the
  same stack. Its row therefore uses only `drop_extra` (nine handlers of stack
  chrome, `preOpenStack` first — it sets this stack's rect, so left in it
  would silently resize the suite's window to 1024x640) and ONE rewrite: the
  harness's own pending-message sweep, which matches `begins with "heNet"` and
  so would have matched NOTHING once every message it arms was prefixed —
  **a fragment of a name is not a name, and nothing renames it**. That rewrite
  is what `@PREFIX@` is for (the post-rename placeholder beside
  `@CORESESSION@`), and it widens the sweep to the member prefix because this
  harness also arms four non-`heNet` paced-hand steps whose next-hand tick
  would otherwise fire into the core's async loopback phase and deal a hand.
- **The namespacing is TOTAL.** All five `.livecodescript` harnesses define
  `stAssert`, `stRun`, `stBuild` and `sTotal`, so every name a member file
  defines is prefixed - including its own scaffolding and its own counters. Not
  because deduplicating would be hard, but because the scaffolding is not
  actually identical (`stRepeatByte` has three implementations that disagree at
  `pCount = 0`) and because a folded harness must behave here exactly as it does
  standalone. The core reads each member's counters afterwards and merges them.
- **Two things are deliberately NOT folded in**, and both are checked: the ENet
  and DataChannel **async loopbacks** (the core already drives a real loopback on
  both transports, and two state machines in one process race for the event
  handlers), and TorrentXT's own `btStartSession` (one session per process, so
  the fold rewrites it to reuse the core's). `check-suite-selftest.py` fails if
  either regresses, and if `en1stCleanup`/`dc1stCleanup` ever become reachable -
  they call `enDeinitialize`/`dcCleanup`, which would pull the transport out from
  under the core's loopback.
- **holde-em's live game is the third, and it is checked by REACHABILITY
  rather than by absence (2026-08-16)** - because a fold that carries a whole
  application carries everything that application can do, whether the harness
  calls it or not. `check-suite-selftest.py`'s check 7d computes the closure
  from `he1heSelfTest` (an over-approximation on purpose: any `he1*` name in a
  reachable body is an edge, so it can name a path that never runs but cannot
  miss one) and refuses a build where `heNetStart` (`btStartSession` - a
  SECOND libtorrent session), `heRunSelftest` (overlay + clipboard + `msg`),
  `heBuildTable`, `heReportShow` or `heKitTryInit` (a b2k world colliding with the
  one box2dxt hand-steps) becomes reachable. **The `bt1stCleanup` hazard here
  is subtler than the enetxt/datachannelxt one and worth carrying:**
  `heNetStop` IS reachable and DOES call `btStopSession gGame["session"]`.
  What makes that harmless is that `gGame["session"]` is written only by
  `heNetStart`, which is not - so the folded run can only ever hand it an
  empty handle. Both halves are checked; the argument is not left as prose.
  7d also holds a property rather than a list - the closure creates no
  control, deletes none, never resizes or retitles the stack and never touches
  `clipboardData`, which is the half that survives a rename - and refuses a
  pending-message sweep that is not by the member prefix. Check 7e refuses any
  of the nine dropped chrome handlers reappearing.
- **CORRECTED 2026-08-16, the same day it was written: a declaration below the
  first handler is NOT dropped, and the gate that claimed to refuse it cannot
  fire.** The paragraph that stood here said `split_handlers` returns only the
  LEADING run of non-handler lines, so a `local` or `constant` between two
  handlers was silently dropped, and that `assert_no_declaration_dropped` now
  refuses that shape "mutation-tested". Measured against the code instead of the
  docstring: `split_handlers` appends EVERY top-level non-handler line wherever
  it sits, so such declarations are collected and hoisted correctly, and the
  guard's two counts are equal by construction on every real source. It can only
  fire on a column-0 declaration written INSIDE a handler body — a narrow and
  genuine case, and the only thing it actually guards.
  **How the false claim survived a mutation test is the lesson.** The test drove
  the FUNCTION with a hand-built preamble matching its docstring, and it refused
  correctly. It was never driven through the PIPELINE, which never produces that
  input. Component verified, system claimed — the same shape as coinxt's
  constant gate reporting the constants it had parsed as the ones it had
  checked. When a gate is added, exercise it the way the build will, not the way
  its docstring describes. The `81 of 188` figure quoted here came from the same
  misreading and is not a real hazard count.
- **A missing declaration is SILENT, which is why there is a checker.** OXT
  cannot compile a `.livecodescript` headlessly, and LiveCodeScript evaluates an
  undeclared name as the literal text of its own name - so a fold that dropped
  `constant kBip39Mnemonic` would not error, it would compare a digest against
  the string `"cx1kBip39Mnemonic"` and report a tidy FAIL that reads like a real
  library defect. That bug was real in the first version of the generator;
  `check-suite-selftest.py` is what found it, and it is mutation-tested.

Folding those harnesses in also surfaced a **latent bug in one copy of the static
gate**. The family keeps a copy of `check-livecodescript.py` per member, and they
had drifted: **sodiumxt's copy did not know `switch`/`end switch`**, so it read
`end switch` as closing a HANDLER, reported two phantom problems in enetxt's and
datachannelxt's event dispatchers, and would have hidden any real imbalance
inside them. The other five copies already handled it, by two different
implementations - measured later, the "drift" was in fact TWO independent
checkers (one lineage in sodiumxt/onionxt/coinxt/riptide, another in
torrentxt/enetxt/datachannelxt), each with real checks the other lacked. **The
copies are UNIFIED now (2026-08-12)**: one implementation carrying the union of
both lineages' checks, byte-identical in every member that carries one - seven
at unification, TEN today, because nocloud (2026-08-13), box2dxt (2026-08-14)
and holde-em (2026-08-15) each carried the unified copy in on its own fold -
with `tools/check-checker-drift.py` failing the build on any divergence and
`tools/test-checker.py` fixture-testing every rule in every copy - so "a fix
applied to one copy is not applied to the suite" is no longer a state the tree
can quietly be in. The self-containment survives: each member still ships its
own copy; the gate just proves the copies are the same tool.

**The first engine pass of the folded harness found what no gate could
(2026-08-09), and it was one line: `dcCleanup()`.** A zero-argument call in
STATEMENT position must be written BARE - a statement starting with an
identifier is parsed as a COMMAND, so the parenthesised spelling hands it the
expression `()`, which is not an expression. A `.livecodescript` compiles as one
unit, so that single line took the whole 4400-line paste with it. What makes it
worth recording rather than just fixing is why it was invisible: the
ONE-argument spelling `dcFreePeer(sPeerA)` is correct (`(sPeerA)` IS an
expression), so the broken line is visually identical to the working one beside
it - `datachannel-loopback` had `dcStopPolling` and `dcCleanup()` on consecutive
lines; in EXPRESSION position (`dcCleanup() is 0`) the parens are REQUIRED, same
characters, opposite verdict; and LiveCode **Builder** allows `sPrepare()` as a
statement, which `sodium.lcb` and `coinxt.lcb` do ~90 times on engine-verified
paths, so "we do this everywhere" was true and irrelevant. All checker copies
refuse it, `.livecodescript` only - and the "each copy tested against the bug,
all three legal forms, and a `.lcb`" attestation this paragraph used to make is
no longer an attestation: those fixtures are COMMITTED in
`tools/test-checker.py` and run against every copy in the gate set, which is
what the shipped-is-not-run lesson below says an attestation must become.

**The second engine error was the generator's, and it is the more instructive
one: DECLARED is not IN SCOPE.** `add pPassed to sPassed` died with
`add: error in source expression`, from `stMergeCounted`. Nothing was wrong with
any member harness. Each one declares its locals above its own handlers, which
is the house pattern in all six - but the FOLD placed coinxt's section about a
thousand lines BELOW the core's `stRunMemberHarnesses`, and that is the handler
that reads `cx1sPassed` to merge the totals. **OXT resolves a script-level name
by lexical position**, a rule this repo already had written down for `constant`
and which turns out to hold for `local` too, so the read saw an undeclared name.
LiveCodeScript does not error on one: it evaluates it to the literal text of its
own name, so the engine tried `add "cx1sPassed" to sPassed`. The generator now
hoists every folded declaration above the first handler, through a second marker
in the core; **106 declarations were below it**, so the counters were merely the
first to do arithmetic on one.

Two things about the gates here are worth carrying. `check-suite-selftest.py`
already proved every folded name was DECLARED - that check passed throughout,
because declared and in-scope are different questions and only the first is
visible to a grep. And `stMergeCounted` did the `add` on trust while
`stMergeReturned`, ten lines above it, had validated its counts since the day it
was written, on the reasoning that a parse can fail but a script local cannot.
The asymmetry is the bug: an uncaught engine error takes the WHOLE run, so six
harnesses' worth of results were lost to one line that could not name the member
it came from. Both paths validate now, and a bad counter is a reported failure
that prints what it got.

**The meta-lesson is the expensive one: shipped is not run.** The suite harness
carried a comment asserting both spellings were fine, reasoning that
datachannelxt shipped the parenthesised form so the engine must accept it. But
datachannelxt's own harness had never been run on an engine, so the attestation
was circular - and the comment even said "this harness has run neither", which
should have been the tell. An unexecuted line is not evidence, in either
direction. The honesty convention already covers this; it just has to be applied
to the code we are citing as precedent, not only to the code we are writing.

**"Current" and "structurally sound" are not "complete", and only the first two had
a gate.** `--check` proves the pasteable file is what the sources produce;
`check-suite-selftest.py` proves the merge holds together. Neither one looks at
whether the harness *reaches* anything, so a member could ship a public handler,
never test it, and both stay green about a file that does not touch the new code.
That gap is invisible from the inside: the harness was ~4400 lines running ~580
checks when this was learned (36143 lines as of 2026-08-20, and the lesson still holds - and it landed again on
2026-08-16, when box2dxt joined the gate and **211 of its Kit's 313 public
handlers turned out never to have been named by a test**, many of them handlers
that RUN on every existing test through `b2kStepOnce`),
and nobody re-asks "is this thorough?" after a number that size. When it was
first measured, **31 public handlers had never been called** - including coinxt's
`cxHdDeriveChild` (the single CKD step the whole HD layer loops over) and both ABI-4
tweak exports, which are what make an xpub watch-only wallet agree with its xprv.
Thirteen were closed by adding checks to the member harnesses; the other eighteen are
all onionxt's and now carry a written per-handler reason in
`tools/check-suite-coverage.py` - eleven **engine socket callbacks** (the engine
supplies a socket id no harness can mint) and seven that need a **live tor daemon**.
The gate fails on a new unexercised handler AND on a stale excuse, so a renamed
handler cannot leave a permanent exemption behind it. It is a floor, not a ceiling:
"called by name" is not "tested well", and depth stays the member vector gates' job.
Box2dxt's 211 were closed the same way, by 13 new sections in its own harness that
say in their banner that they are shallow; the member is at 313/313 with zero
exemptions, and the suite total was **847/861** when this sentence was last
re-measured, on 2026-08-26 (it read 724/742 until nostrxt folded in 2026-08-23
at 101/101 with zero exemptions - the same change that closed four of onionxt's
old excuses - then 830/844 with sodiumxt's ABI-10 handler the same day, and
841/855 later that day when coinxt's four BIP-341 handlers and riptide's
pre-OXT-pass wirings folded in). **Do not trust that ratio; run
`python3 tools/check-suite-coverage.py`, which prints it.** Every number in this
paragraph was correct on the day it was written and silently wrong afterwards -
which is this file's own recorded failure mode for hand-copied counts, landing
on the paragraph that documents the ratchet. TWO layers are NOT in that
ratchet, and each says so beside the `MEMBERS` list with its numbers, because
"we did not measure it" and "we measured it and a row would lie" are different
admissions:

- **box2dxt's raw `b2*` `.lcb` binding** - 376 public handlers over **373**
  foreign declarations (370 binding into the member's own library; the "374"
  that stood here was a `grep -c` counting one line of prose), of which **245
  are named by no script anywhere in that member** - 245 and not 244, which this
  paragraph said until 2026-08-19. Both numbers are real and they differ by the
  measuring CONVENTION: the gate strips comments and blanks string literals
  before it looks (`tools/check-suite-coverage.py`), which is 131 named / 245
  unnamed; counting raw tokens instead finds one more name in a comment or a
  literal, giving 132 / 244. `box2dxt/CLAUDE.md` carries the same pair with that
  explanation; the root file had the other half of it and no annotation, which is
  how one number can be wrong in two places for a reason nobody wrote down. Ratcheting the SCRIPT side
  would mean ~375 assertions written blind against a foreign-bound API in one
  pass, so it stays open.
  **The C side is no longer unmeasured, and the numbers moved a long way on
  2026-08-17.** `box2dxt/tests/smoke_test.c` runs in `build-all.sh` (Release)
  and under ASan/UBSan in `native-box2dxt.yml`'s sanitize job - a lane that did
  not exist that morning - and gcov says it entered **194 of the 370 LC_API
  exports**, up from **53**. The old figure quoted for it was 60, and 60 was a
  grep artifact: it counted b2lc_* tokens including the file's `extern`
  DECLARATION block, and six exports sat in that block declared and never
  called, so every count of what the smoke test reached had been counting them
  as covered. **A declaration is not a call** - this file's own
  shipped-is-not-run lesson, one level down in the toolchain.
  **RE-MEASURED 2026-08-23, and the answer is 370 of 370: no LC_API export of
  the shim is dark.** The next slice named in box2dxt's CLAUDE.md landed - the
  176 remaining exports across three more fixture worlds, 304 checks green
  under Release ctest and the sanitize lane's ASan/UBSan flags, gcov-dated by
  the same gcov-not-grep convention. Read it as ENTERED, not exhausted: the
  sweep's assertions are deliberately shallow and say so in their banner, and
  gcov puts LINE coverage inside the shim at ~92% with the remainder being
  guard and allocation-failure branches. The fold record is box2dxt's. Signatures across
  the boundary are now gated too (`box2dxt/tools/check-lcb-signatures.py`: 370
  binds vs 370 definitions, return type, arity, and every parameter type).
- **holde-em's `he*` surface** - **MEASURED 2026-08-17, re-measured 2026-08-19;
  the mechanism this paragraph said did not exist now exists.** The old text
  said a row would read **0/379** or **379/379**, that only **163/379** were
  named by a test, and that the honest number was "not one this gate can
  compute". Every figure in that sentence is superseded, including the
  denominator: the file defines **381** public `he*` handlers, **330 game + 51
  harness**, not 379. The 2026-08-17 measurement read 380 (329 game); what moved
  it is `heAwardedPot`, the uncalled-bet rule added later that same day in
  07bbf4f, and it is instructive that the drift was SILENT - a new game handler
  that arrives with its own test enters numerator and denominator together, so
  every ratio here still looked right while every absolute number had gone
  stale.

  The gate splits the ONE file into a GAME region and a HARNESS region at its
  selftest boundary - the same move as the embedded-span cut, done with a
  boundary line instead of a sentinel - and asks its own question across the
  cut. Re-measured 2026-08-26: **130/330 game handlers are named by a body
  REACHABLE from the selftest entry point**, +1 dispatched by name = **131/330
  exercised, 199 named by nothing that runs** (20 live-transport, 9
  engine-media, 41 host-window, 129 simply untested). It read 120/121/209/139
  when this paragraph was first written on 2026-08-19; the gate prints the
  current split and is the authority. The unrestricted closure that
  `check-suite-selftest.py` check 7d computes over the same graph scored 265/330
  on 2026-08-19 - a figure no gate prints, so treat it as a dated measurement -
  and refusing that inflation is exactly why the row has its own stopping rule.

  **TWO STRING CONVENTIONS, DELIBERATELY DIFFERENT, and the difference is two
  names.** Reachability KEEPS literals, because this harness arms its sections
  as `heRunSection "heTestFoldRun"` -> `do pName`, so a literal is how a section
  is WIRED. Coverage BLANKS them, because a literal is a label until proven
  otherwise. Measured, exactly two names differ and they are one of each kind:
  `heProbeSodium` survives only inside `heRunSection "heProbeSodium"`, which IS
  the call; `heHandStart` - the hotseat hand opener - survives only inside a
  test LABEL and is a genuine gap. The blanking convention was load-bearing on
  its first use, as its docstring predicted.

  The row is **ADVISORY**: it prints in both modes so CI records the number, and
  does not fail the build. What IS enforced is everything that would make the
  printed number a lie - a unique boundary, test-shaped names below it,
  parseable blocks, reachability of every harness handler bar the three
  interactive ones, and a denominator floor. That floor is not decoration: a
  mutation test found that an unterminated `/*` closes on a stray `*/` inside an
  ordinary line comment, swallowing 2,200 lines and taking 69 public handlers
  out of the denominator - the row went GREEN at 66/260, every number smaller
  and wrong.

box2dxt's script-side row is still OPEN. holde-em's is measured AND armed: the
floor landed 2026-08-19 (the gate's own "ARMED AS A FLOOR" record), so a NEW
gap, a promoted entry or a stale excuse fails the build; what remains open
there is paying the recorded no-test debt down, not preventing drift. (This
sentence said "the honest next step is arming it" until 2026-08-23, four days
after the arming - the description-rots-checks-do-not lesson, again.)

The same shape of hole was in **coinxt's own constant gate**, found while fixing this
one: `check-selftest-vectors.py` re-derived an explicit list and then printed
"66 harness constants re-derived" - a count of the constants it had PARSED, not the
ones it had CHECKED. Two constants added in this very change sailed through it. A gate
that overstates its coverage is worse than no gate, because it answers the question
nobody asks twice. It now fails on any `k*` constant that is neither re-derived nor
listed as an input with a reason, and reports the honest split.

It stayed invisible because of how the two gate layers overlapped. Each member's
own checker reads that member's tree, so enetxt's switch statements were always
checked - by enetxt's checker, which handled them. Separately, the repo-root
`tests/` directory used to run through EVERY member's checker in turn; it held
only the suite harness, which had no `switch` in it, so sodiumxt's gap was never
reached until the fold put enetxt's and datachannelxt's switch-based dispatchers
in front of the one checker that could not parse them. (Since the unification,
that seven-way cross-run is one run: the copies are byte-identical, the drift
gate proves it, and `build-all.sh` runs the root scripts through a single copy.)

## Docs: member vs. suite

- **Member docs** live in `<member>/docs/` and describe that one extension
  (its api-reference, architecture, building, getting-started).
- **Suite docs** live in the top-level `docs/` and span more than one member.
  `docs/README.md` indexes every one of them with its scope and a one-line
  description; this file names only the two that are operational rather than
  descriptive, because an engine session starts with both.
  `docs/OXT-PASS-RUNBOOK.md` is what to do: what is still unproven and why, the
  install order, the run order shortest-feedback-first, and which honesty labels
  each result flips - read it before sitting down at an engine.
  `docs/OXT-ENGINE-NOTES.md` is what the engine actually does, with each entry
  marked OBSERVED, INFERRED, DOCUMENTED or UNEVIDENCED, because the class is the point - read
  it before an engine session and add to it after one. Everything else - the
  roadmap, the Tor-transport integration plan, the capstone specs, the dated
  audits - is catalogued in `docs/README.md` rather than duplicated here, so
  this paragraph does not go stale the next time a document lands.

> **Cross-reference caveat (consolidation debt; swept 2026-08-15).** Members
> and suite docs were moved verbatim, so internal path references read as if
> each project were its own repo root. The tracked path-rewrite pass ran
> 2026-08-15: the references that actually misled - suite docs citing member
> files bare, standalone GitHub URLs where an in-tree path serves, claims
> about docs that have since moved - were fixed or annotated. What
> deliberately remains, and is not a bug: a member's own docs cite paths
> relative to THAT member's root (`examples/foo` inside `box2dxt/docs/` means
> `box2dxt/examples/foo`) - each member's own convention, still true on its
> standalone mirror - and dated records (fold notes, changelogs, plans,
> quoted engine reports) keep their original pre-suite spellings.

## Building & CI

- `tools/build-all.sh` configures, builds, and tests each member that has a
  `CMakeLists.txt` (sodiumxt, torrentxt, enetxt, datachannelxt, and — since
  2026-08-17 — box2dxt, which was walked only by the compiler-free loop before
  that, while three places in the tree cited its C harness as that layer's
  cover — with each
  member's `<MEMBER>_BUILD_TESTS` enabled and `ctest --no-tests=error`, so "no
  tests registered" can never pass silently), runs coinxt's
  `native/build.sh asan` self-test and KAT harness, and runs every member's
  static gates (script checker, docs style, golden vectors, record registries,
  KATs, embedded-Kit freshness, and the MANIFEST.sha256 integrity checks).
  OnionXT is pure script — nothing to compile. Suite-level, after the per-member
  walk, it also proves the GENERATED copies have not drifted from their sources:
  the pasteable harness (`tools/build-suite-selftest.py --check`) and the script
  libraries each demo carries inside itself (`tools/sync-demo-embeds.py --check`,
  with `tools/test-demo-embeds.py --mutate` run first so a blind collision
  detector cannot pass as a clean one). The second of those is what replaced
  onionxt's per-member `build-standalone.py`, retired 2026-08-17 along with the
  two generated twins it emitted - which is why "standalone freshness" no longer
  appears in the per-member list above.
- Build under **gcc** with `-fsanitize=address,undefined` while iterating on any
  shim (clang's ASan runtime is not installed in this environment). Treat every
  native-library header as a **system header** (`-isystem`) so its warnings do
  not pollute the suite's `-Wall -Wextra`.
- CI lives at the repository root, in two layers. `suite-gates.yml` runs every
  member's compiler-free gates on every push (the set `build-all.sh --gates`
  runs), and then uploads a **`suite-selftest` artifact** - the pasteable harness,
  the coverage report, and the runbook - so the person doing an engine pass can
  download the file instead of cloning. It does NOT generate the harness there:
  `--check` already failed the build if the committed copy were stale, so the tree
  copy is the built copy, and generating it in CI would let the artifact and the
  repository drift with only the artifact current. `native-<member>.yml` runs that member's full 5-platform native matrix
  and its sanitizer lanes, scoped by `paths:` so only the touched member
  builds, on pull requests, pushes to `main`, and on demand. The native lanes
  upload each built library as an **artifact** and never commit one: they fire on
  every push, so a commit step there would land binaries nobody asked for on
  somebody else's change. `release-binaries.yml` is the manual assembly step over
  the top: one `workflow_dispatch` builds ALL SIX members that ship committed
  binaries, for every platform it can (30 build jobs since 2026-08-23: box2dxt
  joined - closing the omission this paragraph used to record as having no
  recorded reason - and ALL SIX members gained macOS lanes; the paragraph said "20
  jobs: five members x four platforms" until that day and "every member" until
  2026-08-19), asserts each artifact, then installs each library into its member's
  `src/code/<platform-id>/`, refreshes the manifests, runs the whole gate set,
  and commits (`commit_mode`: `branch` / `pr` / `none`). That still satisfies
  rule 5, whose point is that a committed binary traces to a human decision - the
  decision is the person pressing "Run workflow". The verification is the same
  code either way, because the job runs `tools/install-release-binaries.py`
  rather than reimplementing it. **The macOS lanes (2026-08-23: sodiumxt,
  coinxt, enetxt, box2dxt) build genuinely UNIVERSAL dylibs**, dissolving the
  trap that kept macOS out of CI: `macos-15` runners are arm64-only, so a plain
  build emits a thin dylib into `universal-mac` and would have regressed
  sodiumxt's genuine two-architecture binary into one that fails on every Intel
  Mac. The lanes cross-compile both slices in one pass
  (`CMAKE_OSX_ARCHITECTURES`; a multi-arch `CC` for coinxt's build.sh), assert
  `lipo -archs` carries both at birth, run the arm64 tests natively and the
  x86_64 slice under Rosetta 2, and ship UNSIGNED in the distribution sense
  (the linker's automatic ad-hoc signature; no notarization). The installer
  refuses a thin Mach-O AND a fat container missing a slice, so a regressed
  lane or a hand-assembled bundle cannot land either. torrentxt and
  datachannelxt cannot single-pass a universal build (a static
  libtorrent+Boost+OpenSSL stack; system-OpenSSL DTLS), so they ride a
  separate two-slice-lipo job added later the same day: per-arch builds of
  the PINNED OpenSSL, each thin slice built and tested (arm64 native, x86_64
  under Rosetta), `lipo -create`, the same both-slices assertion - skippable
  deliberately via the `mac_lipo` dispatch input on a first run. What no
  lane does anywhere is notarize (credentials CI does not hold). **THE FIRST
  DISPATCH RAN 2026-08-26 (run 5) AND ALL SIX MAC LANES WENT GREEN** - the four
  single-pass universal builds and both two-slice-lipo jobs, on their first
  execution ever, so the lanes are proven to build. **No mac binary is
  committed even so**, and the reason is worth carrying: one unrelated lane
  failed (`torrentxt x86_64-linux`, on a missing Perl module in the manylinux
  image), and the bundle/commit stage is gated on the WHOLE matrix - so 29
  green artifacts, the six mac ones included, were discarded. That gating is
  correct for a release (a bundle missing a member's binary is not a release),
  and the cost of it is a full re-dispatch. It took three more: run 10 cleared
  every build lane and died at the post-install gate on a real defect it was
  right about (enetxt's mac dylib leaked 70 upstream ENet symbols - the third
  member with the mac export gap, fixed the same night), run 11 cleared the
  gate too and died in the Commit step's own allowlist (`[a-z]+xt` cannot
  match a member with a digit in its name, and box2dxt's paths were the first
  ever staged there), and **RUN 12 (2026-08-27) WENT END TO END**: the first
  dispatch to reach its commit stage, landing the first universal-mac dylibs
  for torrentxt, enetxt, datachannelxt and coinxt, refreshing sodiumxt's from
  the hand-lipo'd ABI 6 to ABI 10, and rebuilding every Linux/Windows binary -
  after which torrentxt's ELF export-closure leg switched ON (the rebuilt .so
  exports btx_* plus the test hooks, not 5419 statically-linked symbols) and
  sodiumxt's MAC_KNOWN_STALE allowance deleted itself by design. Nor does the workflow claim an
  unexecuted artifact works, which is why the coinxt Windows lane's output is
  driven through the published vectors on a Windows runner before it is
  bundled - and the coinxt mac lane drives BOTH slices through the same
  vectors on the runner that built them. The per-member `.github/workflows/` files are kept
  for when a member is worked on in isolation, but **GitHub Actions runs only
  the root workflows in a monorepo**, so they do not fire here.

## Git / workflow

Develop on a per-task branch; commit there; open a **draft PR** if none exists.
Match the surrounding style of whichever member you are in — this codebase
comments the *why*, densely; mirror that. A member's own `CLAUDE.md` may add
stricter, member-specific rules; when it does, it wins for that member.
