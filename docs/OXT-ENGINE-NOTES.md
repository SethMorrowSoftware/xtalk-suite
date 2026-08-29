# OXT-ENGINE-NOTES.md - what the engine actually does

**Every entry here is a fact about the OpenXTalk engine that cost this project
something to learn.** Not style, not convention, not what the language reference
says: observed behaviour, with how we found out and what it broke.

The suite exists because OXT has no headless way to compile or run
`.livecodescript` or `.lcb`. Every gate in this tree is a stand-in for a
compiler we cannot run, and this file is the list of things no stand-in
predicted. It is the most expensive knowledge the project owns, because most of
it was paid for in engine sessions - the one resource that does not scale.

## THE EVIDENCE RULE

Each entry carries a class, and the class is the point:

- **OBSERVED** - seen on a real engine, on a dated run. This is knowledge.
- **INFERRED** - derived from an observed failure but not directly seen. Usable,
  and explicitly weaker.
- **DOCUMENTED** - from the LiveCode/OXT language reference, never confirmed
  here. Treat as a claim, not a fact: this tree has been wrong about a
  documented behaviour before.
- **UNEVIDENCED** - a rule this tree keeps for HYGIENE, with no engine
  observation and no reference behind it. The weakest class, added 2026-08-19
  because entry 1.1 needed it and the other three all lied about it: its
  observed failure was later re-attributed to a different mechanism (1.6), so
  OBSERVED was gone; INFERRED requires an observed failure to derive from, and
  there was no longer one; and nobody has checked whether the reference says
  anything, so DOCUMENTED would be a second guess dressed as a citation. An
  entry sits here when the RULE is worth keeping on its own argument and the
  ENGINE BEHAVIOUR is simply unknown.

**Do not promote an entry between classes without a dated run.** An unexecuted
line is not evidence in either direction - that is the "shipped is not run"
lesson the root `CLAUDE.md` records, and it applies to this file first.

**A note on the dates in this file, because one session produced two of them.**
Entries are dated by the COMMIT that recorded them, which is UTC. The debugging
session that produced 1.7, 5.3, 6.4, 6.5 and 6.7 ran across UTC midnight - its
commits are stamped 2026-08-18 20:54 through 2026-08-19 01:27 - so entries from
one continuous evening carry both dates. That is not two sessions and not a
contradiction; it is the clock the commits use. When an entry's date matters,
correlate it with the commit hash the entry names rather than with another
entry's date.

---

## 1. Parsing and scope

### 1.1 A second `script "Name"` line silently breaks declaration scope
**UNEVIDENCED** (filed OBSERVED 2026-08-17, then INFERRED, until the note below). A demo whose
stack script contained its own `script "EnetLanChat"` on line 1 and an embedded
library's `script "enetHelpers"` 200 lines down threw, from a handler 700 lines
below both:

```
Chunk: error in object expression
uiStatus "Hosting on port" && kEcPort && "-" && the number of keys of sPeers ...
```

`local sPeers` was declared plainly above that handler. The second script-name
line put everything after it outside the scope the first file's declarations
were in, so `sPeers` resolved as an undeclared name (see 2.1), and
`the number of keys of` a *string* is a chunk expression against a non-object.

**SUPERSEDED 2026-08-19 - the symptom above was not this.** The quoted error was
traced on 2026-08-18 to the ARGUMENT SPELLING, not to scope: `keys` is not a
chunk, so `the number of keys of X` fails whether or not X is declared (1.7,
commit 61c14ea). The header had already been stripped from this demo in
`b9fa4b3` - at that commit `enetxt/examples/enet-lan-chat.livecodescript` has
exactly one `script "..."` line and the dashboard still reads
`the number of keys of sPeers` - and the same error on the same line recurred
afterwards, cleared only by the rewrite to
`the number of lines of the keys of X`. The companion attribution made at the
time, that datachannel-dht-chat's `sPolling` compile error had the same cause,
was superseded by 1.6 (commit `de91770`): that error was a duplicate
`local sPolling`, which survived the header strip and was still present at both
declaration sites afterwards. So nothing observable changed when the second
script line came off, and no dated run distinguishes this mechanism from the
spelling bug. That is why the class is not OBSERVED - and because the
failure it was inferred from was later attributed elsewhere, the inference rests
on nothing observed either, which is what UNEVIDENCED exists to say out loud. Only a deliberate run would settle it, and that
run would get its own date.

**The rule survives on hygiene, not on knowledge, and it should be read that
way.** A `script "..."` line is a stack-NAME marker, meaningful only when the
file IS its own stack. Inside an embedded fragment it names a stack that is not
there, so it is wrong whatever the engine does with it. That argument needs no
engine pass, which is exactly why the gate stays: the strip is correct on
structure alone, and this entry no longer claims to know what happens if you
skip it.

**Rule:** exactly one `script "..."` line per script, and it is the first line.
When concatenating sources, strip the header from every part but the first.
**Gate:** `tools/sync-demo-embeds.py` strips it and asserts none survived.

### 1.2 Script-level declarations resolve by LEXICAL POSITION
**OBSERVED** on the folded-harness engine passes (the second engine error of
that sequence; the root `CLAUDE.md` records the finding but not a date, so none
is asserted here). `add pPassed to sPassed` died with
`add: error in source expression` because the handler doing the arithmetic sat
about a thousand lines ABOVE the `local` it read. Declared is not in scope:
only the first question is visible to a grep, and 106 declarations were below
their first reader.

**Rule:** a script-level `local`/`constant` must appear above every handler that
reads it. Generators must hoist. **Gate:** `tools/check-suite-selftest.py`.

### 1.3 Constants must be literal, and declared before first use
**OBSERVED** (same class of failure as 1.2). A forward-referenced constant
evaluates to nothing rather than erroring.
**Gate:** `check_constants_before_use`, both dialects.

### 1.4 Smart quotes fail compilation anywhere, including comments
**OBSERVED.** U+201C/201D/2018/2019 break the compile even inside a comment or a
string. ASCII `"` and `'` only. **Gate:** the static checker enforces zero.

### 1.5 A prefixed name whose full spelling IS a reserved token is the token
**OBSERVED.** `tExt` (a `t`-prefixed name for "extension") lowercases to `text`,
so xTalk evaluates the keyword, not your variable. It compiles and silently
misbehaves. **Gate:** the `k`/`p`/`s`/`t` shadow-trap check.

### 1.6 Two script-level declarations of one name is a HARD compile error
**OBSERVED 2026-08-18**, on `datachannel-dht-chat` after it was made
self-contained:

```
stack "Untitled 1": compilation error at line 291 (local: name shadows
another variable or constant) near "sPolling", char 1
```

The demo declared `local sPolling` for its own timer, and so did
`datachannel-helpers` for the dc poll chain. Before the embed those were two
`local`s in two different STACKS and nothing collided; carrying the helper into
the demo put both in one script. Two genuinely different flags, one name.

This is the useful counterpart to 2.1: a *missing* declaration is silent and
produces a plausible wrong answer, while a *duplicate* one is loud and stops
the compile at paste time. Loud is better, but it still costs an engine pass to
find, which is why it is gated rather than left to the engine.

**Rule:** when any script is assembled from more than one source - an embed, a
fold, a paste - the union of column-0 `local`/`constant` names must be unique.
Rename at the source; never merge two declarations.
**Gate:** `tools/sync-demo-embeds.py` refuses to write a colliding embed, and
`tools/build-suite-selftest.py` prefixes every folded name for the same reason.
Both gates are only as good as their name parser - see the note in
`tools/test-demo-embeds.py` about the version of this one that could not see a
declaration carrying a trailing comment, which is how the error above reached
an engine at all.

### 1.7 `the number of keys of X` does not parse
**OBSERVED 2026-08-18.** enet-lan-chat's dashboard, once a second:

```
Chunk: error in object expression
Line: uiStatus "Hosting on port" && kEcPort && "-" && the number of keys of sPeers && "peer(s)", "ok"
```

`keys` is not a CHUNK, so `the number of keys of sPeers` is not a count - the
engine reads `keys of sPeers` as an OBJECT expression and fails to resolve it.
The correct spelling is `the number of lines of the keys of sPeers`.

**Why this survived so long, and why it is filed as a lesson rather than a
typo.** BOTH spellings were in the tree at once. Measured at the commit that
fixed it, the correct one was in fifteen files - eight distinct sources once the
box2dxt Kit's line and its six carried copies are counted once and the generated
`tests/suite-selftest.livecodescript` is set aside - and three of those files are
harnesses that have run green on an engine; the broken one was in nine places
across three demos, every one of them on a path no engine run had ever reached.
Nothing distinguished them to a reader, and nothing checked them. That shape -
two idioms for one job, one carrying evidence and one not - is worth looking for
deliberately, because the tree cannot tell you which is which and a green gate
will not either.

**Gate:** the unified `check-livecodescript.py` antipattern set, fixture-tested
in `tools/test-checker.py` against both spellings.

(Filed as `1.5b` on the day it was written, which is the number commit `61c14ea`
cites. Renumbered to 1.7 on 2026-08-19 so section 1 ascends: a letter suffix is
for an entry that must sit BEFORE a later-numbered neighbour, and this one has
no such constraint. 1.6 keeps its number, because `de91770` cites it.)

---

## 2. Evaluation

### 2.1 An undeclared name evaluates to the literal text of its own name
**OBSERVED, repeatedly, and this is the single most expensive behaviour in this
file.** It does not error. `sPeers` becomes the string `"sPeers"`, and the
failure surfaces far downstream wearing someone else's clothes:

- as `add "cx1sPassed" to sPassed` -> "error in source expression" (1.2);
- as a digest compared against the string `"cx1kBip39Mnemonic"` -> a tidy FAIL
  that reads like a real library defect.

**The inverse does NOT hold, and a third bullet here asserted that it did.** It
read `the number of keys of "sPeers"` -> `Chunk: error in object expression`,
offered as a demonstration of this behaviour. It is not one: that expression
fails identically with a properly declared array, because `keys` is not a chunk
(1.7). A chunk or object error says only that something in the expression did
not resolve; it is not by itself evidence of an undeclared name, and reading it
as one is what sent this tree after the wrong mechanism, twice, for two days
(1.1). The bullet is gone rather than re-pointed - 2.1 keeps its OBSERVED class
on the two above, which are independently evidenced.

**Rule:** every name declared, always. There is no compiler to catch this and
the runtime will not either. **Gate:** several, including the undeclared-constant
and catch-variable checks.

### 2.2 The engine ignores ONE trailing delimiter when counting items
**OBSERVED 2026-08-10 - the single red line of that pass.**
`cxHdDerivePath(tNode, "m/")` returned the node unchanged instead of throwing:
`the number of items of "m/"` is 1, not 2, so the malformed path looked like a
bare `m`. A fail-OPEN in a derivation path, found only because a human read the
one red line in an otherwise green run.

**Rule:** never infer "there is no trailing empty component" from an item count.
Check the string.

### 2.3 `itemDelimiter` and `lineDelimiter` are global mutable state
**OBSERVED** (several times, in shipped code). A handler that sets one and
returns without restoring it corrupts every parse that follows, in unrelated
code, until something else sets it. The observed symptom is always the same
shape: "item 1 returned the whole list".

**Rule:** save, set, restore - around the NARROWEST span that needs it.

---

## 3. Control flow

### 3.1 `repeat with i = A to B step N` does not honour the step
**OBSERVED** by an operator at an engine, after every gate in the repo went
green. (The checker records the finding and its cost but not a date; none is
asserted here.) `i` walked one at a time. In `cxHexDecode` that made the final pass read
one character past the pairs, get empty, and throw "not a hex digit" over VALID
input - the library accusing the caller's data of corruption in the exact words
it reserves for real corruption.

**Rule:** use `repeat while` with an explicit `add N to i`.
**Gate:** `check_engine_hostile_constructs`. There was exactly ONE occurrence in
the whole suite, which is why it had never been in front of an engine: **a
construct nobody else uses is a construct nobody else has proved.**

### 3.2 `throw` from inside a `catch` block does not reach the caller
**OBSERVED**, same run as 3.1. The handler falls through and returns whatever
its result variable holds - usually empty. Nine `itemDelimiter` guards did this,
and one was `cxMnemonicValidate`, whose inner reaches `return false` only via
its own catch: **a mistyped seed phrase was reported VALID.**

**Rule:** capture the error in a local, close the `try`, throw after `end try`.
**`return` inside a catch is FINE and engine-proven** (onionxt's
`oxSodiumHasSha3` does it on a path that same run exercised) - only `throw` is
affected.

### 3.3 A zero-argument call in STATEMENT position must be written bare
**OBSERVED 2026-08-09**, and it took a 4,400-line paste with it. A statement
starting with an identifier parses as a COMMAND, so `dcCleanup()` hands it the
expression `()`, which is not an expression. `.livecodescript` compiles as one
unit, so one line killed the whole file.

What makes it worth carrying is why it was invisible: the ONE-argument spelling
`dcFreePeer(sPeerA)` is correct, so the broken line looked identical to the
working one beside it; in EXPRESSION position (`dcCleanup() is 0`) the parens
are REQUIRED, same characters, opposite verdict; and LiveCode **Builder** allows
`sPrepare()` as a statement, which the `.lcb` files do ~90 times on
engine-proven paths. "We do this everywhere" was true and irrelevant.

**Gate:** `check_zero_arg_statement_calls`, `.livecodescript` only.

---

## 4. The FFI boundary (LCB <-> C)

These are the marshalling bets the suite had to place before any engine existed.
All are **OBSERVED**; the dates are when each was first proven.

| Behaviour | First proven | Note |
|---|---|---|
| `UIntSize` works as a foreign RETURN type | 2026-08-08 | the documented fallback was never needed |
| `MCDataGetBytePtr` marshals an EMPTY `Data` through a plain `Pointer` | 2026-08-08 | for an empty INPUT |
| A C `int` flag marshals (33 vs 65 came back distinct) | 2026-08-10 | |
| `Boolean` returns work in both directions | 2026-08-10 | `cxVerify` answered true and false |
| An EMPTY `Data` reaches the shim as length 0 in an **OPTIONAL argument** slot | **2026-08-17** | proven for an empty INPUT in 2026-08-08, never for an optional argument until this run |
| A three-argument foreign call shape marshals | 2026-08-17 | `cxSchnorrSign` |
| An array return reads back by name | 2026-08-17 | `cxTaprootTweak` |

**Rule for `.lcb`:** every foreign call inside `unsafe ... end unsafe`, and all
declarations at the TOP of the handler - a nested `local` has broken whole-script
compilation.

---

## 5. Controls and the UI

### 5.1 A polygon graphic does not resize by setting its height
**OBSERVED 2026-08-17, box2dxt engine run 5.** A polygon graphic's rect is
DERIVED from its points, so `b2kPlayerDuckSet`'s "resize the control, then
reshape" rebuilt the physics capsule at FULL height every time. The player
wedged against a wall while every existing assert passed, because they read the
bookkeeping variable (`sPlayHalfH`) rather than measuring the control.

A second effect compounded it: the drawer's re-point pads the rect by the pen
margin, so each rebuild grew the control by 2px (measured 50 -> 52 -> 54).

**Rule:** re-point a polygon to resize it. Capture canonical dimensions BEFORE
the first draw pads the rect, and never re-read a padded rect as truth.
**Lesson beyond the bug:** an assertion that reads your own bookkeeping is not a
measurement.

### 5.2 Window lifetime hooks differ by stack shape
**OBSERVED.** box2dxt's games hang their window off the CARD hooks
(`openCard`/`closeCard`) rather than the stack ones, and tear down via
`b2kTeardown` from `closeCard`. A tree-wide audit that greps for `on closeStack`
will report them as having no teardown, wrongly - which happened on 2026-08-17.

### 5.3 An unqualified control resolves against THE DEFAULTSTACK
**DOCUMENTED** (filed OBSERVED 2026-08-18 until the correction below).
enet-lan-chat's once-a-second dashboard threw, from inside the UI kit's
`uiStatus`:

```
Chunk: error in object expression        (Hint: ecDashOnce, REPEATEDLY)
```

**CORRECTED 2026-08-19.** This throw was traced the same session to the ARGUMENT
evaluated at the `ecDashOnce` call site - `the number of keys of sPeers`, entry
1.7 - which is evaluated in the CALLER and so never reached `uiStatus`. The
commit that fixed it says so in as many words, and the pin landed one commit
earlier without stopping it. This entry has no dated engine observation behind
it. DOCUMENTED is therefore the honest class: the resolution rule below is
documented `defaultStack` behaviour, not something this tree has watched fail.
It is not INFERRED either - INFERRED needs an observed failure to derive from,
and the only failure ever offered here belongs to another entry.

`put pText into field "uiStatus"` resolves `field "uiStatus"` against **the
defaultStack**, not against the stack whose script is running. Inside
`openStack` those are the same object, which is why every demo's STARTUP status
line has always worked and why this had never been seen. A handler arriving
from `send ... in` has no such guarantee: with another stack in front, the
write lands on the wrong stack or resolves to nothing.

**The quiet half is a CONDITIONAL, and this entry used to state it as an
outcome.** It said datachannel-dht-chat had the same fault and never threw,
because it guards with `if there is a field "uiStatus"` - two outcomes of one
mechanism. Neither half of that holds. dht-chat never carried the broken
argument, so it had no fault to hide; and the guard credited to the kit was not
in the kit, because before `db0f9e3` the master's `uiStatus` had no existence
check at all (`git show 1dad0e1:tools/ui-kit.livecodescript`). The guard is
dht-chat's OWN wrapper `wxSetStatus`, in
`datachannelxt/examples/datachannel-dht-chat.livecodescript`, which calls into
the kit only `if there is a field "uiStatus"`. What survives is the shape of the
hazard, in the tense it belongs in: a guarded call site WOULD fail silently if
the defaultStack diverged - the status line simply stops updating, on the exact
path a person is least likely to report. A guard would convert this bug from
loud to invisible, which is an argument for a gate rather than for more guards.

**Rule:** a handler that can arrive from a delayed message must pin the stack
before touching an unqualified control:

```
set the defaultStack to the short name of this stack
```

**Gate:** `tools/check-timer-stack-pin.py` - every `send ... to me in` target,
and everything REACHABLE from it: a closure over the handlers defined in the
same file, plus the ui* kit master, stopping at any handler that already pins
(below a pin the defaultStack is set, so following through would name a hazard
that cannot happen). 75 delayed handlers across 26 files today.

**WIDENED 2026-08-20, and the widening is the point.** Until then it asked one
question - "does this armed handler call an unpinned ui* handler?" - which is a
check for the bug already found, since the ui-kit fix had closed exactly that
hop. It knew about ONE carried block and never asked the same question about
anything else, including the other one: the suite core's `stPump` is armed by
`send "stPump" to me in 33 milliseconds` and calls `stShow`, which writes
`field "stResults"` unqualified; the gate read stPump's own body, found no
control reference, checked the kit list, and passed. As a closure it found **40
unpinned timer chains across 15 files** - every demo's own log / refresh /
status helper, reached from its poll or dashboard tick. All 33 distinct
handlers are pinned now, at the timer entry point, which is where the ambiguity
starts and where one line covers everything downstream.

Those 40 are STATIC findings, like the three (`pfCardFadeStep`,
`sgCardFadeStep`, `heBetSliderFromThumb`) the narrower gate had found before
them - not observed failures. Nothing above argues against the pin: it is
cheap, harmless, and defensible on documented engine semantics. Only the
evidence label changed. Putting this entry back at OBSERVED costs one
deliberate run - open a second stack in front and let a `send ... in` handler
write an unqualified `field "uiStatus"` - and that run gets its own date.

**A near miss worth recording, because it is how this entry could have gone
wrong a second time.** On 2026-08-20 two Windows pastes of the suite harness
ended mid-CROSS-section, and a first-tick throw in `stShow` fitted the evidence
exactly: the report would freeze at precisely the last synchronous render,
which is what both looked like. That diagnosis was written up as fact and was
wrong - the third run, same build, completed 1981/0/1 through both loopbacks,
teardown and the summary; the first two were copied before the async half
finished. A mechanism that explains the symptom is not an observation of it,
which is the same distinction the 2026-08-19 correction above turns on.

### 5.4 `the playLoudness` does not read back exactly on every platform
**OBSERVED 2026-08-18 on LINUX.** box2dxt's harness did

```
b2kSoundVolume 73        -- set the playLoudness to round(clamp(73,0,100))
stAssert "playLoudness readback", (the playLoudness is 73)
```

and the assertion was FALSE. The identical check had been green on Windows
x86_64 (NT 10.0, OXT 9.6.3) the day before. **What the value actually was is
not known** - the check reported nothing but its own name, so a scarce engine
session yielded "some number is not 73". The harness now probes two points and
prints both, so the next pass on any platform reports the scale instead of
re-asking; do not promote a mechanism into this entry until it does.

**ANSWERED, BOTH PLATFORMS.** The two-point probe was written to make the next
pass report the scale instead of re-asking, and it did.

| Platform | asked 24 | asked 73 | verdict |
|---|---|---|---|
| Win32 (2026-08-20, harness v30) | 24 | 73 | EXACT |
| Linux (2026-08-21, harness v30) | **0** | **0** | **write-only: readback is a constant 0** |

So the mechanism is no longer unknown. On Linux `the playLoudness` does not
report what was written to it at all - not a different scale, not rounding: a
constant. The 2026-08-18 failure was never "some number is not 73"; it was
**zero**, and one line of probe output settled what a whole engine session could
not.

**IT ALSO KILLED THE ASSERTION THAT REPLACED THE FIRST ONE, which is the part
worth carrying.** v30 stopped asserting exactness and asserted ORDER instead -
a high write must read back above a low one - reasoning that this still catches
an engine that ignores writes. Linux ignores writes here, is not broken, and the
Kit never reads the value back, so v30 went red on a healthy platform. The
replacement assertion was better than the original and still wrong, for the same
underlying reason: it treated a readback as a channel. **v31 asserts only that
the property is READABLE and reports the rest.** A check that fails on a healthy
engine is worse than no check - the next reader has to re-derive that it is
noise, and the run stops being trustworthy at a glance.

**Rule:** `playLoudness` is a request, not a register. Set it and move on; do
not read it back and compare against what you wrote, and do not compute from it.
**Not even the ordering** - that was this entry's rule until 2026-08-21, and
Linux disproved it. There is NO property of the readback to rely on; treat the
write as fire-and-forget.

**The wider lesson is about assertions, not audio.** Every other check in that
section names the value it saw - `(got 200)`, `(hScroll 1120)`, `(owner:
b2kcam_view)` - and this one did not, which is exactly the check that went red
on a platform nobody had run before. An assertion's failure message is the
whole product of an engine pass. Write it as though the run costs a day,
because it does.

### 5.5 A script-only stack file opened from disk does not build its GUI

**OBSERVED** (OXT, 2026-08-14; the primary record is the dated maintainer note
in `start-here.livecodescript`'s own header). A `.livecodescript` file is TEXT.
`File > Open Stack` on one - or `go` to the file - loads the script and stops
there: **going to the file does not produce a built window**. A demo that
builds its whole UI in `preOpenStack` / `openStack` therefore looks broken
rather than unopened, and the engine says nothing at all, which is what makes
this expensive - the reader concludes the DEMO is defective and stops.

**What works** is the ritual `OXT-PASS-RUNBOOK.md` 3.1 spells out, and it is
the only shape any engine pass in this tree has ever used: `File > New
Mainstack`, `Object > Stack Script`, paste the whole file, Apply, then CLOSE
and REOPEN the window. `start-here.livecodescript`'s Open button automates
exactly that - create a host stack, park it CLOSED, set its script, `go` to
it (the close-and-reopen half is load-bearing; the second block of this note
is the expensive proof) - which is why
the launcher can open a demo that the reader could not have opened by
double-clicking the same file.

**What it does NOT mean.** Getting a script-only file into the MESSAGE PATH is
fine and is how the pure-script layers are wired by hand: load it and
`start using stack "<name>"`, expecting no window, because there is none to
build (`onionxt/docs/10-usage-guide.md` section 2 is the worked example). Same
for the two function-shaped harnesses - `put sxSelfTest()`, `put oxSelfTest()`
from the message box. The rule is about the GUI BUILD, not about loading a
script.

**What it cost.** Nothing in an engine session: it cost the front door. The
suite's own entry point taught the wrong ritual on both ends - `README.md`
step 3 said to open `start-here.livecodescript` with `File > Open Stack`, and
that file's header said the same thing FOUR LINES ABOVE the paragraph
documenting this exact behaviour and implementing the workaround. A first-time
reader following the README got a launcher that never built its window, from
the one file whose entire job is making the demos easy to run. Corrected
2026-08-27 in `README.md`, `CLAUDE.md`, `start-here.livecodescript` (header
and its `slProbe` status line), `datachannelxt/README.md`, and four demo
headers that offered "open it as a stack" as an alternative to pasting.

**No gate holds this**, and it is prose in the places a reader starts from, so
it can drift back silently. The cheap check is a grep for `Open Stack` and
`as a stack` across `*.md` and `*.livecodescript`; what it should find is the
library case above and box2dxt's `dist/INSTALL.md`, which opens a real
`.oxtstack` binary stack and is not this rule.

**`create` OPENS the stack it makes, so a later `go` to it is a raise that
fires no open messages at all** - OBSERVED (OXT, 2026-08-27) through the
launcher, over two engine reports, and this paragraph's first version drew
the WRONG conclusion from the first report; the correction is kept in place
of it rather than beside it because the wrong model lived here for under an
hour. Round one: none of the six box2dxt games (card hooks only, no
openStack) launched, while every stack-hook demo did, and the old
empty-card nudge's `send "openStack"` was an execution error on the games -
which killed the launch handler before the reveal, so their windows stayed
invisible. That round was read here as "the ritual delivers stack messages
but not card ones". Round two falsified it: with the nudge made throw-proof
(dispatch) and widened to all four messages, the games' windows opened and
stayed EMPTY, and closing and reopening one BY HAND built it. So no open
message had ever fired from the launcher's `go` at all - the host stack was
already open from the `create` - and the stack-hook demos had only ever
been built by the nudge's hand-dispatch, which works aimed at a STACK and
reached nothing aimed at a card: `dispatch "openCard" to card 1 of stack X`
ran no handler, while the same dispatch `to stack X` runs its script's
(the second observation this note carries). The launcher now parks a
freshly prepared stack CLOSED - while still scriptless, so no handler can
run - and `go invisible`s it: a genuine open, the engine fires the full
preOpen/open sequence for both lifecycle families itself, and the
hand-nudge (dispatched, stack-targeted, defaultStack pinned per 5.3)
remains only as the belt. The close-then-reopen half is exactly the
maintainer's observed repair, automated; `go invisible stack` as a spelling
rides the same needs-an-OXT-pass label as the launcher around it.

### 5.6 Unqualified `there is a <control>` answers for the CURRENT CARD only

**OBSERVED** (OXT, 2026-08-29; the primary record is riptide-social's pasted
boot self-check, quoted in `docs/OXT-PASS-RUNBOOK.md` row 35's annotation). On
a green five-card boot of `riptide/examples/riptide-social.livecodescript` -
"all five cards were built" PASS, every rail probing true - the self-check's
control sweep reported **all 63 controls that live on cards 2-5 as missing**,
and none of card 1's, because `raScRun` runs with card 1 current:

    FAIL  all 98 controls this script names exist (missing: raAnonEntries,...)

So `there is a field "x"` / `there is a button "x"` / `there is a graphic "x"`
with no card qualifier is a question about the current card of the
defaultStack, NOT about the stack. This was the modeled reading in
`riptide/tools/check-demo-boot.py` (its header carried it as an unsettled
question until this record settled it), and it is the same resolution family
as 5.3 - the qualifier rule there is about WHICH STACK, this one is about
WHICH CARD.

**Held by**: the carried demo-selfcheck block's `scMissing` walks every card
of the stack with card-qualified `there is` since 2026-08-29 (master
`tools/demo-selfcheck.livecodescript`, re-carried to every adopter); on a
single-card demo the walk is one card, exactly the old behaviour. Any OTHER
unqualified `there is a <control>` on a multi-card stack remains a per-site
judgement: it is correct when the answer is genuinely about the current card,
and a bug when it means "anywhere in this stack".

---

## 6. Sockets and processes

### 6.1 `socketTimeout` REPEATS while a read or write is pending
**DOCUMENTED** (LiveCode reference) and relied on in shipped code: it is only
fatal during a handshake. On a connected stream it is just an idle read and must
be ignored, or a working connection tears itself down.

### 6.2 An engine socket id is not a parseable address
**OBSERVED 2026-08-17** (offline fixtures; the live inbound path is still
pending an S2 pass). Splitting a socket id on `:` and taking item 1 yields
EMPTY for a bare IPv6 id like `::1:54321`, and a loopback guard that treats an
empty host as loopback then FAILS OPEN. Parse by shape: strip a bracketed
group first, else take everything up to the LAST colon.

### 6.3 A launched child process needs `__OwningControllerProcess` to die with you
**DOCUMENTED**, used by `oxLaunchTor` so a spawned tor exits with the app. The
launch path itself has never run on an engine - it is the one remaining VERIFY
in onionxt, scheduled as runbook S2 item 2. **See runbook trap 5.3.1** - that
is `docs/OXT-PASS-RUNBOOK.md`, not a subsection of this file's 5.3 - it defaults
to the same ports a system tor already holds.

### 6.4 An EMPTY value into a typed `.lcb` parameter is "type conversion error"
**OBSERVED 2026-08-18 on Linux**, twice, from two different demos.

`"type conversion error"` is **LiveCode Builder's** error for a value that will
not convert to a declared parameter type. Every public `.lcb` handler in this
suite declares its parameter types and **none of the 630 has an optional
parameter**, so every one of them is a place a script can hand the engine
something it must refuse - at runtime, on a GUI engine, in front of a person.

The confirmed instance is `enet-lan-chat`:

```
enHostDestroy sHost          -- enHostDestroy(in pHost as Integer)
put empty into sHost         -- ...one line later
```

`enetDisconnect` empties the handle it just used, so the SECOND disconnect
(ENet delivers one per peer, and a failed connect produces one of its own)
passed **empty** to an `Integer` parameter. Not a no-op - a throw, which killed
the poll chain and left the demo silently dead. The same file guards `sHost`
this way in ten other places.

**Rule:** empty is not a value for `Integer`, `Real`, `Number` or `Boolean`.
Guard any handle before passing it, especially on a teardown path, and
especially in a harness - an uncaught throw at teardown costs the WHOLE run,
not the section.

**Gate:** `tools/check-lcb-call-types.py` checks the script-to-`.lcb` boundary
argument by argument - arity, emptied handles, and event keys the module's own
`_fieldKey` cannot return. It found the defect above plus eight teardown paths
where a setup that never ran would have turned a clean skip into a dead run.

### 6.5 An LCB error's LINE NUMBER resolves against the source tree on disk
**OBSERVED 2026-08-18.** An LCB failure reports like this:

```
LCB Error   cannot convert value
LCB File    .../datachannelxt/src/datachannel.lcb
LCB Line    234
```

The line is read from the **source file the IDE can see**, which is not
necessarily the source the **installed extension was compiled from**. Ten
lines of drift between two checkouts (this file's 234 and 244) moves this
report from `if sDrainCap < pNeed then` to `if not tOk then` - two different
statements, two different bugs, one identical error text.

**Rule:** before reasoning from an LCB line number, confirm the installed
extension was packaged from the checkout being read. A behaviour visible in the
run is the cheapest proof - `dcSendText refuses an embedded NUL with -3` only
passes on a build carrying `kErrInvalidArg`.

**How this entry was written is itself the caution.** It first asserted that
this tree's two branches DID differ by nine lines there, and that was wrong: it
came from diffing against a stale `origin/main` fetched before the branch was
merged. Re-fetched, the file is byte-identical on both, and line 234 is
unambiguous. A cached remote ref is a stale source too.

### 6.6 RESOLVED by 6.7: the datachannel poll failure
**OBSERVED 2026-08-18 on Linux**, hosting a chat in
`datachannelxt/examples/datachannel-dht-chat.livecodescript`. 6.4 explains
the ENet demo's failure completely; this one is NOT yet explained, because
the gate that found the ENet defect reports the datachannel demo clean.

**Narrowed 2026-08-18 (second report, Windows):** the throw is not in the
dispatch at all - it is inside `dcPoll`, in `_ensureDrain`, before any handler
is reached. The first wrap guarded only the dispatch, because the dispatch line
was what the first report named; guarding only the half you have been shown is
how one diagnostic costs two passes. Both the drain and the dispatch are
guarded now, in the ENet pump as well. What is still unknown is WHICH value
will not convert, and 6.5 is why the line number alone cannot settle it:

```
execution error at line 178 (call: type conversion error), char 1
```

Line 178 is the poll dispatcher's `dispatch tName to sPollTarget with tEvent`.

**This entry names a symptom, not a cause, and it is filed that way on
purpose.** Three different bugs produce exactly this line - the dispatch
itself refusing its arguments, the target no longer resolving, or a THROW
inside a handler the dispatch reached - and the message distinguishes none of
them. The obvious suspect is already ruled out: `dispatch <name> to <obj> with
<array>` is engine-proven elsewhere in this suite, where `onion-httpd` routes
an array of parsed headers that way and serves real pages through Tor.

Do not promote this entry to a mechanism until a run reports one. The
dispatcher in `datachannel-helpers.livecodescript` now isolates each event,
keeps the timer chain alive, and records the first failure with the event's
name for `dcPollLastError()`; both demos that carry it surface that line in
their own log. The next occurrence should arrive with the event named.

**CLOSED 2026-08-18 by 6.7, and the narrowing above did not hold.** The next
occurrence arrived with the event named, exactly as this entry asked: the pump
reports a drain failure and a dispatch failure distinctly
(`dcPoll failed on drain #N` versus `dispatch of <name> failed`), and what the
run printed was the DISPATCH form. So the drain completed, and the throw was the
dispatch - not `_ensureDrain`. Read the paragraphs above as the reasoning of the
day rather than as findings: the instruction not to promote a mechanism was
satisfied by 6.7, and the `_ensureDrain` location was an inference from an LCB
line number, superseded by an observation. Why the second report named
`datachannel.lcb` line 234 - which is `if sDrainCap < pNeed then` on this tree,
and where no revision of that file has ever placed `dcLocalDescription` - is
still not established, and is left here as an unexplained observation rather
than promoted into a second mechanism.

**The general rule this is the second example of in two days** (see 5.4): an
engine session's entire output is its error messages. A bare statement plus a
phrase costs another session; a message that names the value, the target and
the operation usually costs none.

### 6.7 An event name and a handler name share ONE namespace
**OBSERVED 2026-08-18, and it closes 6.6.** The demo's own log, once the poll
pump was made to report instead of die:

```
Event dispatch problem: dispatch of dcLocalDescription failed: 899,258,1
```

Line 258 is `dispatch tName to tTarget with tEvent`. The demo defines no
`on dcLocalDescription` - but **DataChannelXT exports one**:
`dcLocalDescription(in pPeer as Integer)`, the getter for the current local
SDP. xTalk resolves a dispatched message exactly like a call, through the same
single namespace, so the dispatch reached the LIBRARY handler and handed it the
event Array where it wanted an Integer.

**The part worth carrying is how long it hid.** An unhandled dispatch is not an
error, so a colliding name looks exactly like "no handler here" until the
colliding handler happens to be strict about its arguments.
`datachannel-loopback` shipped `on dcLocalDescription` from the day it was
written and it **never fired once**; `docs/getting-started.md` taught the same
shape; and the suite harness stayed green throughout because it compares
`tEvent["name"]` in an if/else and never dispatches at all. Every layer agreed,
and every layer was testing something else.

**Rule:** a dispatched event name may never equal a public handler name in the
module that emits it. When they collide, rename the EVENT - the getter is
exercised, the event demonstrably is not.
**Gate:** `tools/check-lcb-call-types.py` check 4, over every `_eventName`
return in every module, with the historical case pinned in its test.

### 6.8 `open secure socket` works, and that is NOT the same as "TLS verifies"
**OBSERVED 2026-08-24** (Windows x86_64, OXT 9.6.3), the suite's FIRST secure
socket of any kind. (Dated by the RUN, not by the commit that recorded it a day
later - the rest of the tree calls this "the 2026-08-24 pass" and an entry that
disagreed with every file citing it would be worse than the small exception. See
the note on dates above.) `nostrxt/src/nostr-relay.livecodescript`'s `nxrConnect`
ran its secure branch against a public Nostr relay:

```
connecting to wss://nos.lol (handle 1)
relay 1: open
identity ready: npub154kp062...
signed event 33f9b9a3...
nxEventVerify: the event verifies
published a4a3fe9d...
ok a4a3fe9d...: true
```
(The maintainer's report, elided only where it carried key material.)

What that settles, and it is worth having because the form was a total unknown
the day before: `open secure socket to <host:port> with message <name>` EXISTS,
connects asynchronously and fires its message the way the plain form does; and
the persistent no-quantifier `read from socket ... with message` plus
`write to socket` carry a real byte stream over it - enough for an RFC 6455
upgrade, masked client frames, and the relay's replies read back chunk by chunk.
Before this, `open secure socket` appeared in no other member and this file had
no TLS entry at all.

**What it does NOT mean, which is the whole reason this entry is worded the way
it is.** Nobody offered this engine a certificate they had any reason to doubt,
and that is the only honest way to put it: calling the peer certificate "valid"
would be circular, since whether it was checked is precisely the open question -
if the engine verifies nothing, a bad certificate would have connected too. A
connection succeeding against an ordinary public host is equally consistent with
"the engine verified the chain" and with "the engine verified nothing"; the two
hypotheses predict the identical observation, so this run cannot separate them.
**Nothing has yet deliberately offered this engine a bad certificate.**

Still unmeasured: whether an invalid or
self-signed certificate is refused, against which root store, whether the
HOSTNAME is checked, what `the sslCertificates` does here, whether SNI is sent
(shared-hosting relays need it), which TLS versions negotiate, and how a TLS
failure is delivered - the code assumes a `socketError` message, as with the
plain form, and nothing failed, so that assumption is still untested.

Do not promote this entry on the strength of another successful connection to a
good host; only a deliberately bad certificate can move it. Until then, treat
any code that would be unsafe under "no verification" as unsafe.

**Related, and mildly counter-intuitive:** the ws:// (plain) branch of the same
handler has still never run. The secure path is currently the better-evidenced
of the two, which inverts the advice several documents used to give.
**Gate:** none, and none is possible headlessly - this is an engine measurement.
The narrowed question is carried in `nostrxt/docs/07-capabilities-required.md`
gap #2 and flagged `VERIFY (on-engine)` at the call site.

---

## 7. How to add to this file

When an engine run teaches you something:

1. **Write the symptom verbatim**, including the error text. The symptom is what
   the next person will search for; our own entries were found that way.
2. **Say what it cost.** "Took a 4,400-line paste" and "reported a valid seed
   phrase as invalid" are why these entries get read.
3. **Mark the evidence class honestly.** If you inferred it, say INFERRED.
4. **Name the gate** if one now holds it, so a reader knows whether they are
   protected or merely warned.
5. **Record what it does NOT mean.** Half the entries above have a neighbouring
   construct that is fine (`return` in a catch, the one-argument call form), and
   omitting that turns a rule into superstition.

Member-specific gotchas stay in that member's `CLAUDE.md`. This file is for
behaviour of the ENGINE, which is the same everywhere and therefore worth one
authoritative list.
