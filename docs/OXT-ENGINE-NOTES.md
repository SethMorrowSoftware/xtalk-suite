# OXT-ENGINE-NOTES.md - what the engine actually does

Every entry is a fact about the OpenXTalk engine that cost this project
something to learn: the symptom verbatim, what it broke, the rule, and the gate
(if any) that holds it. OXT cannot compile or run `.livecodescript` or `.lcb`
headlessly, so every gate here stands in for a compiler; this file lists what
no stand-in predicted. Entry NUMBERS are stable and cited across the tree
("engine notes 5.3"): never renumber, merge or delete one; a resolved entry
stays as a stub (6.6).

## THE EVIDENCE RULE

Each entry carries a class, and the class is the point:

- **OBSERVED** - seen on a real engine, on a dated run.
- **INFERRED** - derived from an observed failure, not directly seen; weaker.
- **DOCUMENTED** - from the LiveCode/OXT reference (or engine source), never
  confirmed here. A claim, not a fact.
- **UNEVIDENCED** (added 2026-08-19) - a rule kept for HYGIENE, with no engine
  observation and no reference behind it.

**Do not promote an entry between classes without a dated run**; an unexecuted
line is not evidence in either direction. **Dates** are those of the COMMIT
that recorded an entry (UTC): the session behind 1.7, 5.3, 6.4, 6.5 and 6.7 ran
2026-08-18 20:54 to 2026-08-19 01:27 UTC, so one evening carries both dates.
6.8 is the exception, dated by the run.

## 1. Parsing and scope

### 1.1 A second `script "Name"` line inside an assembled script
**UNEVIDENCED** (filed OBSERVED 2026-08-17, then INFERRED; reclassified
2026-08-19). It was blamed for enet-lan-chat's
`Chunk: error in object expression` (a demo with its own `script "EnetLanChat"`
and an embedded `script "enetHelpers"`), which was really the argument spelling
(1.7, commit 61c14ea); the companion `sPolling` error was a duplicate
declaration (1.6, commit de91770). No dated run separates the two mechanisms.
**Rule:** exactly one `script "..."` line per script, as its first line; strip
it from every embedded part. It stands on structure alone: a script-name line
inside a fragment names a stack that is not there.
**Gate:** `tools/sync-demo-embeds.py` strips it (`strip_script_header`) and
asserts none survived.

### 1.2 Script-level declarations resolve by LEXICAL POSITION
**OBSERVED** on the folded-harness engine passes (the root record carries no
date, so none is asserted). `add pPassed to sPassed` in `stMergeCounted` died
with `add: error in source expression`: the handler sat about a thousand lines
ABOVE the `local` it read, so the name was undeclared there (2.1); 106 folded
declarations were below their first reader. Declared is not in scope.
**Rule:** a script-level `local`/`constant` sits above every handler that reads
it; generators hoist. **Gate:** `tools/check-suite-selftest.py`.

### 1.3 Constants must be literal, and declared before first use
**OBSERVED** (the 1.2 failure class). A forward-referenced constant evaluates
to nothing rather than erroring. **Gate:** `check_constants_before_use`, both
dialects.

### 1.4 Smart quotes fail compilation anywhere, including comments
**OBSERVED.** U+201C/201D/2018/2019 break the compile even inside a comment or
a string. ASCII `"` and `'` only. **Gate:** the static checker enforces zero.

### 1.5 A prefixed name whose full spelling IS a reserved token is the token
**OBSERVED.** `tExt` (a `t`-prefixed "extension") lowercases to `text`, the
keyword: it compiles and silently misbehaves. **Gate:** the `k`/`p`/`s`/`t`
shadow-trap check.

### 1.6 Two script-level declarations of one name is a HARD compile error
**OBSERVED 2026-08-18**, on `datachannel-dht-chat` once it was made
self-contained:

    stack "Untitled 1": compilation error at line 291 (local: name shadows
    another variable or constant) near "sPolling", char 1

The demo and the embedded `datachannel-helpers` each declared `local sPolling`
(two different flags), and the embed put both in one script. The counterpart
to 2.1: a missing declaration is silent, a duplicate stops the compile at paste
time.
**Rule:** when a script is assembled from more than one source (an embed, a
fold, a paste), the union of column-0 `local`/`constant` names must be unique.
Rename at the source; never merge two declarations.
**Gate:** `tools/sync-demo-embeds.py` refuses a colliding embed,
`tools/build-suite-selftest.py` prefixes every folded name, and
`tools/test-demo-embeds.py` pins the trailing-comment blind spot that let this
one reach an engine (`tools/check-cross-library-names.py` holds the library
corpus disjoint).

### 1.7 `the number of keys of X` does not parse
**OBSERVED 2026-08-18** (filed as `1.5b`, the number commit 61c14ea cites;
renumbered 2026-08-19). enet-lan-chat's once-a-second dashboard:

    Chunk: error in object expression
    Line: uiStatus "Hosting on port" && kEcPort && "-" && the number of keys of sPeers && "peer(s)", "ok"

`keys` is not a CHUNK, so the engine reads `keys of sPeers` as an OBJECT
expression and fails. Correct: `the number of lines of the keys of sPeers`.
Both spellings coexisted: the correct one in 15 files (three of them
engine-green harnesses), the broken one in 9 places across 3 demos no run had
reached. **Lesson:** two idioms for one job, one with evidence and one without,
are worth hunting for deliberately.
**Gate:** the unified `check-livecodescript.py` antipattern set,
fixture-tested in `tools/test-checker.py` against both spellings.

## 2. Evaluation

### 2.1 An undeclared name evaluates to the literal text of its own name
**OBSERVED**, repeatedly; the single most expensive behaviour in this file. No
error: `sPeers` becomes the string `"sPeers"`, and the failure surfaces far
downstream in someone else's clothes - as `add "cx1sPassed" to sPassed` ->
`error in source expression` (1.2), or as a digest compared against the string
`"cx1kBip39Mnemonic"` -> a tidy FAIL that reads like a real library defect.
**Does NOT mean** that a chunk or object error is evidence of an undeclared name:
1.7 fails identically on a declared array, and reading it as this sent the tree
after the wrong mechanism (1.1).
**Rule:** declare every name. **Gate:** several, including the
undeclared-constant and catch-variable checks.

### 2.2 The engine ignores ONE trailing delimiter when counting items
**OBSERVED 2026-08-10**, the single red line of that pass.
`the number of items of "m/"` is 1, so `cxHdDerivePath(tNode, "m/")` returned
the node unchanged instead of throwing: a fail-OPEN in a derivation path.
**Rule:** never infer "no trailing empty component" from an item count; check the string.

### 2.3 `itemDelimiter` and `lineDelimiter` are global mutable state
**OBSERVED** (several times, in shipped code). A handler that sets one and
returns without restoring it corrupts every later parse in unrelated code; the
symptom is always "item 1 returned the whole list". **Rule:** save, set,
restore, around the NARROWEST span that needs it.

### 2.4 Every number is an IEEE double, so integers are exact only to 2^53
**DOCUMENTED** (LiveCode's numeric model; runbook row P is the five-minute
probe that would promote it, and it has not run on OXT). An accumulator is
exact while |v| <= 9007199254740992 and silently ROUNDS above: an 8-byte
`byteToNum` of 2^64-1 answers `1.8446744073709552e+19`, with no error and no
flag - the 2.1 class, a plausible wrong answer. Since 2026-09-08 the family
interpreter (`coinxt/tools/lcs-interp.py`, byte-identical in `nostrxt/tools/`)
REFUSES any integer past the exact range; before that it computed at Python's
arbitrary precision, looser than the engine.
**Rule:** never accumulate past 2^53. Split into bytes, hex or decimal digits
(coinxt's no-bignum discipline), and bound every wide decoder at its parse
site, because after the arithmetic nothing is left to detect.

### 2.5 `and` and `or` evaluate BOTH operands - there is no short-circuit
**DOCUMENTED** for the rule itself (runbook row P(b) is the probe that would
promote or disprove it); the family interpreter models it (`p_or` evaluates the
right operand unconditionally) and coinxt had hit it at eight sites. A type
guard cannot share an expression with what it guards; the damage depends on the
second operand. A **COMPARISON** (`X < 1`, X non-numeric) silently folds to a
TEXT comparison and answers something (the interpreter refuses: stricter).
**ARITHMETIC** (`X + 0`) is a hard `error in source expression` (the 2.1 class,
OBSERVED): in a never-throw library, an uncaught error in the app. Found in
nostrxt on 2026-09-09 at three sites of the form
`if not nxIsDigits(X) or X + 0 <op> ...`, one (`nxJsonPathNode`) reachable from
relay bytes, so one malformed relay message was an uncaught throw; coinxt's
record has the same shape five times (trap 21 of `coinxt/CLAUDE.md` names the
guard predicates it uses now).
**Rule:** nest the guard: `if not guard(X) then refuse` as its own `if`, then
the arithmetic or comparison.

### 2.6 `the number of <chunks> of X & Y` counts X alone - the target is a factor
**OBSERVED**, via a holde-em netplay assertion green on two engine runs:

    the number of lines of tOutboxTxt & "/" & char 1 to 3 of line 1 of tOutboxTxt

equals `"1/r!" & tab` in the suite paste on 2026-08-20 (Windows x86_64,
holde-em 543/0) and 2026-08-24 (584/0). The count binds to `tOutboxTxt` and the
rest is concatenated onto the number, the everyday
`put the number of lines of tList & " lines"`. It broke the model, not the
engine: the family interpreter bound the other way until 2026-09-11 (holde-em's
execution gate read `2` where the engine read `1/r!`); the September
"chunk-binding trap" rewrites in coinxt and nocloud were findings of that
model, harmless, and stay.
**Not settled:** arithmetic after the target (`the number of chars of X + 1`,
assumed to bind the same way) and the field-name form `field "x" & tKind`.

### 2.7 Array KEYS fold case: `tA["A"]` and `tA["a"]` are ONE element
**OBSERVED 2026-09-15**: archivext's member harness (`axSelfTest`) on the
user's OXT (platform and version not recorded; 357 passed, 2 failed, 0 skipped;
363/0/0 after the fixes; archivext left for its own repository on 2026-09-21,
the record stays here). The assertion

    axtCheck axJsonType(tDoc, "A") is "missing", "keys are case-sensitive"

against a document whose only key was `a` answered the `a` node:
`"A" is among the keys of tArray` is true and `tArray["A"]` reads it.
`the caseSensitive` (default false) governs array KEYS as well as `is` /
`contains` / `offset` (coinxt's disciplines record the comparison half). It
broke a JSON reader whose "keys looked up exactly" contract was false from the
day it shipped.
**Rule:** never use an array as an exact-string index. Keep the original keys
in a numbered list and compare byte-exact (nostrxt's `nxStrEqExact`), or fold
on purpose and say so where the array is declared. Numeric keys are unaffected.
**Gate:** the model, since 2026-09-24. The family interpreter
(`coinxt/tools/lcs-interp.py`, twinned in `nostrxt/`) folds keys too, so every
execution gate runs on this rule, pinned in tier 0 of coinxt's
`check-script-vectors.py`. Its two choices are the model's, not observations:
the FIRST spelling written is the one kept, and `the caseSensitive` is a LOCAL
property (the LiveCode dictionary's scope) governing keys only. A model gate
sees a collision only where a vector drives two spellings: riptide's LAN keys
are still undriven.
**Does NOT mean:** `the keys of` still returns each key's ORIGINAL spelling, so
a scan over the keys is exact; only the subscript lookup folds.

## 3. Control flow

### 3.1 `repeat with i = A to B step N` does not honour the step
**OBSERVED** by an operator at an engine after every gate was green (the
checker's record carries no date). `i` walked one at a time, so `cxHexDecode`
read one character past the pairs and threw `not a hex digit` over VALID input.
**Rule:** `repeat while` with an explicit `add N to i`.
**Gate:** `check_engine_hostile_constructs`. It was the only occurrence in the
suite: a construct nobody else uses is a construct nobody else has proved.

### 3.2 `throw` from inside a `catch` block does not reach the caller
**OBSERVED**, same run as 3.1. The handler falls through and returns whatever
its result variable holds. Nine `itemDelimiter` guards did this; one was
`cxMnemonicValidate`, so a MISTYPED seed phrase was reported VALID.
**Rule:** capture the error in a local, close the `try`, throw after `end try`.
**Does NOT mean:** `return` inside a catch is FINE and engine-proven (onionxt's
`oxSodiumHasSha3`, same run). **Gate:** `check_engine_hostile_constructs`.

### 3.3 A zero-argument call in STATEMENT position must be written bare
**OBSERVED 2026-08-09.** A statement starting with an identifier parses as a
COMMAND, so `dcCleanup()` hands it the expression `()`, which is not one; a
`.livecodescript` compiles as one unit, so that line killed the whole
4,400-line suite paste. **Does NOT mean:** the one-argument
`dcFreePeer(sPeerA)` is correct; in EXPRESSION position (`dcCleanup() is 0`)
the parens are REQUIRED; LiveCode Builder allows `sPrepare()` as a statement
(~90 times in the `.lcb` files, engine-proven).
**Gate:** `check_zero_arg_statement_calls`, `.livecodescript` only.

### 3.4 `Function: error in function handler` with the hint = the function's NAME means "no live handler in the message path"
**DOCUMENTED 2026-09-15**, from the engine source (livecode `develop-9.6`
`engine/src/exec-keywords.cpp`, `object.cpp`; OXT's error tables are
byte-identical), read after archivext's first engine report:

    Type    Function: error in function handler
    Object  Untitled 3
    Line    axtCheck axVersion() begins with "ArchiveXT", "..."
    Hint    axVersion

The engine found no live handler named `axVersion` on the message path and
appended EE-0219 with the name as the hint (a fault INSIDE the function would
show its own error first). The dialog cannot separate two causes: the library
was never put in use, or its script is DEAD - scripts parse lazily on first
message (`MCObject::parsescript`), and a parse failure sends an unhandled
`scriptParsingError` with nothing in `the executionError`. `start using` parses
eagerly and throws EE-0845 `start: script of specified stack won't compile`.
**Rule:** treat it as "not loaded" first: `put the stacksInUse`;
`put <lib>Version()` (a string proves loaded AND parsed);
`set the script of stack "x" to the script of stack "x"` then `put the result`
(empty means it compiles, else the parse error's number, line, column, token).
Ask for the dialog's verbatim text ("bad syntax" was a paraphrase). archivext's
next run, library in use, compiled whole and ran 357 checks (2.7).
**Does NOT mean:** a COMMAND called with `()` throws the same EE-0219 at the
call site (holde-em's `heProbeSodium()`, v0.10.x; the unified checker's check
16 flags it), so check the callee's kind first.

## 4. The FFI boundary (LCB <-> C)

Marshalling bets placed before any engine existed; all **OBSERVED**, dated by
first proof.

| Behaviour | First proven | Note |
|---|---|---|
| `UIntSize` works as a foreign RETURN type | 2026-08-08 | the documented fallback was never needed |
| `MCDataGetBytePtr` marshals an EMPTY `Data` through a plain `Pointer` | 2026-08-08 | for an empty INPUT |
| A C `int` flag marshals (33 vs 65 came back distinct) | 2026-08-10 | |
| `Boolean` returns work in both directions | 2026-08-10 | `cxVerify` answered true and false |
| An EMPTY `Data` reaches the shim as length 0 in an **OPTIONAL argument** slot | **2026-08-17** | an empty INPUT was proven 2026-08-08; an optional argument only on this run |
| A three-argument foreign call shape marshals | 2026-08-17 | `cxSchnorrSign` |
| An array return reads back by name | 2026-08-17 | `cxTaprootTweak` |

**Rule for `.lcb`:** every foreign call inside `unsafe ... end unsafe`, and all
declarations at the TOP of the handler - a nested `local` has broken
whole-script compilation.

## 5. Controls and the UI

### 5.1 A polygon graphic does not resize by setting its height
**OBSERVED 2026-08-17** (box2dxt engine run 5). A polygon's rect is DERIVED
from its points, so `b2kPlayerDuckSet` ("resize the control, then reshape")
rebuilt the physics capsule at FULL height: the player wedged against a wall
while every assert passed, because they read `sPlayHalfH`, not the control. The
re-point also pads the rect by the pen margin, +2px per rebuild (50, 52, 54).
**Rule:** re-point a polygon to resize it; capture canonical dimensions BEFORE
the first draw pads the rect. **Lesson:** an assertion that reads your own
bookkeeping is not a measurement.

### 5.2 Window lifetime hooks differ by stack shape
**OBSERVED.** box2dxt's games hang their window off the CARD hooks
(`openCard`/`closeCard`, `b2kTeardown` from `closeCard`), so a grep for
`on closeStack` wrongly reports them without teardown (it did on 2026-08-17).

### 5.3 An unqualified control resolves against THE DEFAULTSTACK
**DOCUMENTED** (filed OBSERVED 2026-08-18, corrected 2026-08-19). The throw it
was filed on, `Chunk: error in object expression` (Hint: `ecDashOnce`,
REPEATEDLY), was 1.7's argument, evaluated in the CALLER before `uiStatus` was
reached (the pin landed a commit earlier and did not stop it). No dated engine
observation stands behind this entry; the rule is documented behaviour.
`put pText into field "uiStatus"` resolves against the defaultStack, not the
stack whose script is running. Inside `openStack` those coincide (why every
startup status line worked); a handler arriving by DELAYED DELIVERY
(`send ... in`, an engine socket or URL callback, a library dispatch) has no
such guarantee. With another stack in front the write lands elsewhere or
resolves to nothing, and a guarded site (`if there is a field "uiStatus"`)
would fail SILENTLY.
**Rule:** pin the stack at the delayed entry point:
`set the defaultStack to the short name of this stack`.
**Gate:** `tools/check-timer-stack-pin.py`, a closure over same-file handlers
plus the ui* kit master that stops at any handler already pinning (since
2026-08-20: 40 unpinned chains in 15 files, all pinned at their entry points).
Since 2026-09-09 its entry set covers all three delivery classes: `send ... in`
targets, engine socket/URL callbacks (`with message "X"`, `socketError` /
`socketClosed` / `socketTimeout`) and library-dispatched callbacks
(`oxSetStreamCallback`, `nxrSetCallback`, `oxhRoute` and friends), 24 more
chains in 9 files. 298 delayed handlers across 37 files on 2026-09-23 (it
prints the live count); `tools/test-timer-stack-pin.py` (2026-09-10) refuses a
scan that finds nothing. **To promote:** one deliberate run (a second stack in
front, a `send ... in` handler writing an unqualified field), with its own date.
**Near miss, 2026-08-20:** two Windows suite pastes ending mid-CROSS-section
were diagnosed as an `stShow` first-tick throw; the third run, same build,
completed 1981/0/1 (the first two were early copies). A mechanism that explains
a symptom is not an observation of it.

### 5.4 `the playLoudness` does not read back exactly on every platform
**OBSERVED**, on box2dxt's harness:

| Run | Asked | Read back | Verdict |
|---|---|---|---|
| Windows x86_64 (NT 10.0, OXT 9.6.3), 2026-08-17 | 73 | 73 | the exactness assert green |
| Linux, 2026-08-18 (harness v29) | 73 | not 73 (the assert printed no value) | FAIL |
| Win32, 2026-08-20 (harness v30) | 24, 73 | 24, 73 | EXACT |
| Linux, 2026-08-21 (harness v30) | 24, 73 | **0, 0** | write-only: a constant 0 |

It broke v29's exactness assert on Linux, then v30's replacement ORDER assert
(a high write reads back above a low one) on a healthy Linux engine.
**Rule:** `playLoudness` is a REQUEST, not a register: set it and move on, and
never compare against or compute from the readback, not even its ordering (v31
asserts only that it is READABLE). **Lesson:** every assertion must print the
value it saw; a check that fails on a healthy engine is worse than none.

### 5.5 A script-only stack file opened from disk does not build its GUI
**OBSERVED 2026-08-14** (OXT; primary record: the dated maintainer note in
`start-here.livecodescript`'s header). A `.livecodescript` file is TEXT:
`File > Open Stack` on it, or `go` to the file, loads the script and silently
builds no window, so a demo looks broken rather than unopened (`README.md` and
the launcher's own header taught `File > Open Stack` until 2026-08-27).
**What works:** runbook section 3.1's ritual, the only shape any engine pass
here has used - `File > New Mainstack`, `Object > Stack Script`, paste, Apply,
then CLOSE and REOPEN; `start-here.livecodescript`'s Open button automates it.
**OBSERVED 2026-08-27** (two launcher reports): **`create` OPENS the stack it
makes, so a later `go` to it is a raise that fires no open messages** (the
reopen is the load-bearing half of the ritual). Round one: the launcher's
empty-card nudge did `send "openStack"`, and on the six box2dxt games (card
hooks only, no `openStack` handler) that send was an EXECUTION ERROR, which
killed the launch handler before the reveal, so their windows stayed
invisible. Round two, with the nudge DISPATCHED (`dispatch` does not error on
a message nobody handles), the games opened as EMPTY windows that built only
after a close and reopen by hand: the launcher's `go` had never fired an open
message, and the stack-hook demos had only ever been built by the nudge's
hand-dispatch. Also observed: `dispatch "openCard" to card 1 of stack X` ran
no handler while a dispatch `to stack X` runs its script's. The launcher now
parks a freshly created, still-scriptless stack CLOSED, sets its script and
`go invisible`s it (a genuine open, so the engine fires preOpen/open for both
lifecycle families); a stack-targeted nudge (5.3 pin), dispatched and never
sent, stays as the belt. The `go invisible stack` spelling rides the
launcher's "needs an OXT pass" label.
**Does NOT mean:** loading a script-only file into the MESSAGE PATH is fine
(`start using stack "<name>"`, no window expected; `onionxt/docs/10-usage-guide.md`
is the worked example), as are `put sxSelfTest()` / `put oxSelfTest()`.
**Gate:** none. Grep for `Open Stack` and `as a stack` in `*.md` and
`*.livecodescript`; the legitimate hits are the library case and box2dxt's
`dist/INSTALL.md` (a real binary `.oxtstack`).

### 5.6 Unqualified `there is a <control>` answers for the CURRENT CARD only
**OBSERVED 2026-08-29** (OXT). On a green five-card boot of
`riptide/examples/riptide-social.livecodescript` (v11: all five cards built,
every capability true), the boot self-check printed

    FAIL  all 98 controls this script names exist (missing: raAnonEntries,...)

reporting all 63 controls on cards 2-5 missing, because `raScRun` runs with
card 1 current (primary record: the v11 boot record in `riptide/CLAUDE.md`, 9
passed, 1 failed, 0 skipped). With no card qualifier, `there is a field "x"`
(or button, graphic) asks about the current card of the defaultStack: 5.3 is
WHICH STACK, this is WHICH CARD.
**Held by:** the carried demo-selfcheck block's `scMissing` (master
`tools/demo-selfcheck.livecodescript`) walks every card with card-qualified
`there is` since 2026-08-29. Any other unqualified `there is` on a multi-card
stack is a per-site judgement: right for the current card, a bug for
"anywhere in this stack".

### 5.7 An IMAGE object takes fetched bytes, and a refusal keeps the rect it already had
**OBSERVED 2026-09-20** (OXT 9.6.3, Windows x86_64 NT 10.0), from the pasted
log of archivext's gallery demo (`archivext/examples/archive-gallery.livecodescript`,
now in the archivext repository), all through its handler `agSetPicture`:

- **`set the text of image X to <bytes>` takes a fetched JPEG**: 10,066 bytes
  came back `180x124`, 1,180,947 bytes `1988x1367` (libURL, a script variable
  and the image object, end to end). `the width`/`the height`, read with
  `the lockLocation` false right after, are the picture's natural size.
- **A REFUSAL KEEPS THE CONTROL EXACTLY AS IT WAS**: non-picture bytes answered
  `684x358`, the control's own rect (`32,100,716,458`) - no throw, no blank, no
  0. The run's one red line. So box2dxt's `b2kSheetSourceFromFile`
  width-under-2 test is valid only on a freshly CREATED control (no rect yet).

**Rule / fix idiom:** clear the content, force the control to 1px and unlock
its location BEFORE setting the bytes; assert both directions (a known
four-pixel PNG taken, non-picture bytes refused).
**Not settled:** what a refusal does to `the text of image`, whether an image
ever throws, progressive JPEG. WebP and AVIF are DOCUMENTED unsupported.

### 5.8 A player can open a stream, report a duration, advance its clock, and be SILENT
**OBSERVED 2026-09-20** (OXT 9.6.3, Windows x86_64 NT 10.0, the same gallery
log). Three archive.org MP3 streams handed to a player as `https://` URLs all
opened (`set the filename` left `the result` empty, non-zero `the duration`,
`playStarted` for two, `the currentTime` up ~6 s after 6 s). Nothing was heard.

    play check: duration 10623320000, currentTime 60337007

A timeScale of 10,000,000 (100 ns units, a 1,062 s chapter) is INFERRED until
a run prints `the timeScale` beside it. **Rule:** a player's own properties
cannot distinguish playing from running-and-silent. The suspect, UNCONFIRMED:
neither demo ever set `the playLoudness` (5.4).
**Second observation (twice, morning and evening 2026-09-20): the FIRST
`playStarted` of a session is not seen; later ones are.** Setting the "this
player is mine" state before `start player` did not change it; the remaining
hypothesis is that play one also CREATED the player in the same handler. Rule
either way: **establish the state a message will be judged against BEFORE
issuing the command that can send it.**
**Unsettled** (now the archivext repository's): whether the player opens
`https` at all (Windows' DirectShow URL source is documented for http only);
the http retry has never run.

### 5.9 A player refuses an h.264 MP4 from a LOCAL FILE, with a verbatim reason
**OBSERVED 2026-09-20** (OXT 9.6.3, Windows x86_64):

    play: https://dn800208.us.archive.org/0/items/TheGhoul/TheGhoul_1933.mp4
          (h.264, 408.79 MB, chose TheGhoul_1933.mp4) on Win32 NT 10.0
    the player refused the stream at once: could not create movie reference
    the player refused the downloaded file as well: could not create movie reference

`could not create movie reference` is what `set the filename of player` leaves
in `the result`: a synchronous, named refusal; the same for a 386 MB MPEG4. MP3
opened in the same session (5.8), so the CONTAINER is the wall, not the scheme
or the redirect; it cost a 408 MB download to learn. `launch document` opened
the file outside, the one media path with an older engine record (riptide,
2026-08-15).
**Rule:** once a LOCAL file of a container has been refused, never download
another of that suffix; run any cheap discriminator (the http retry) first.

### 5.10 A blocking `put URL` while an async `load URL` is in flight: the async one times out, and its error headers belong to the other request
**OBSERVED 2026-09-20** (same session, libURL 1.2.0). An async `load URL`
search was in flight when the Live probe ran blocking `put URL` legs; it ended
at the 60 s watchdog:

    request 1 (gallery) failed: the URL library said timeout for
    https://archive.org/advancedsearch.php?...&rows=192&page=1&output=json:
    socket timeout archive.org:443|6925 [headers: HTTP/1.1 200 OK | ... |
    Onion-Location: https://archive...onion/metadata/arkivkopia.se-digmus-mha-MILIF.007916 ]

The socket got a **200** and then stalled, and the quoted headers are **the
other request's** (the `Onion-Location` names the `/metadata/` URL the blocking
leg had fetched): 6.9's `libURLLastRHHeaders` rule, at the moment a reader most
trusts a header block. Causation is **UNEVIDENCED** (one observation, a large
192-row async response, no control run).
**Rule:** do not block while an app's own requests are out; an error that
quotes headers must say, in its own text, that they may be another request's.

## 6. Sockets and processes

### 6.1 `socketTimeout` REPEATS while a read or write is pending
**DOCUMENTED** (LiveCode reference), relied on in shipped code: fatal only in a
handshake; on a connected stream it is an idle read and must be ignored, or a
working connection tears itself down.

### 6.2 An engine socket id is not a parseable address
**OBSERVED 2026-08-17** (offline fixtures, green in that day's suite pass on
Windows x86_64, OXT 9.6.3; the live inbound half is still owed, an S2 onionxt
leg recording a raw accepted socket id). Splitting on `:` and taking item 1
yields EMPTY for a bare IPv6 id like `::1:54321`, and a loopback guard that
treats an empty host as loopback FAILS OPEN.
**Rule:** parse by shape: a bracketed group first, else up to the LAST colon.

### 6.3 A launched child process needs `__OwningControllerProcess` to die with you
**DOCUMENTED**, used by `oxLaunchTor` so a spawned tor exits with the app. The
launch path has never run on an engine: one of onionxt's open VERIFY items
(item 8 of the still-VERIFY list in `onionxt/CLAUDE.md`; runbook row 4;
`tests/suite-closing-pass.livecodescript` leg F). It defaults
to the ports a system tor holds: runbook trap 5.3.1 (not this file's 5.3).

### 6.4 An EMPTY value into a typed `.lcb` parameter is "type conversion error"
**OBSERVED 2026-08-18** (Linux), twice, from two different demos: LCB refusing
a value that will not convert to a declared parameter type. Every public
`.lcb` handler declares its types and none has an optional parameter (630 when
filed; the gate prints today's count). In `enet-lan-chat`:

    enHostDestroy sHost          -- enHostDestroy(in pHost as Integer)
    put empty into sHost         -- ...one line later

ENet delivers a disconnect per peer (and one for a failed connect), so the
SECOND disconnect passed empty to an `Integer`: a throw, not a no-op, which
killed the poll chain and left the demo silently dead.
**Rule:** empty is not an `Integer`, `Real`, `Number` or `Boolean`: guard every
handle, above all on teardown and in harnesses (a throw costs the WHOLE run).
**Gate:** `tools/check-lcb-call-types.py` (arity, emptied handles, event keys
`_fieldKey` cannot return); it found this plus eight teardown paths that would
have turned a clean skip into a dead run.

### 6.5 An LCB error's LINE NUMBER resolves against the source tree on disk
**OBSERVED 2026-08-18.**

    LCB Error   cannot convert value
    LCB File    .../datachannelxt/src/datachannel.lcb
    LCB Line    234

The line is read from the source the IDE can see, not necessarily the source
the installed extension was compiled from; ten lines of drift (234 vs 244)
moves this report from `if sDrainCap < pNeed then` to `if not tOk then`.
**Rule:** confirm the installed extension was packaged from the checkout being
read before reasoning from its line numbers; a visible behaviour is the cheap
proof (`dcSendText` refusing an embedded NUL with -3 needs the `kErrInvalidArg`
build). A stale cached remote ref (`origin/main`) misled this entry's first
draft.

### 6.6 RESOLVED by 6.7: the datachannel poll failure
**OBSERVED 2026-08-18** (Linux, hosting a chat in
`datachannelxt/examples/datachannel-dht-chat.livecodescript`; a second report
from Windows):

    execution error at line 178 (call: type conversion error), char 1

Line 178 is the poll dispatcher's `dispatch tName to sPollTarget with tEvent`.
Three causes produce that line indistinguishably (the dispatch refusing its
arguments, the target no longer resolving, a throw inside the handler it
reached). The pump now reports `dcPoll failed on drain #N` and
`dispatch of <name> failed` distinctly; the next run printed the DISPATCH form,
which 6.7 explains. Why the Windows report named `datachannel.lcb` line 234
(`if sDrainCap < pNeed then`) stays unexplained.
**Rule:** an engine session's whole output is its error messages: name the
value, the target and the operation (see also 5.4).

### 6.7 An event name and a handler name share ONE namespace
**OBSERVED 2026-08-18**, closing 6.6:

    Event dispatch problem: dispatch of dcLocalDescription failed: 899,258,1

DataChannelXT exports the getter `dcLocalDescription(in pPeer as Integer)`; a
dispatched message resolves exactly like a call, so dispatching the EVENT
reached the getter with the event Array. An unhandled dispatch is not an error,
so it hid: `datachannel-loopback`'s `on dcLocalDescription` never fired once,
`datachannelxt/docs/getting-started.md` taught the same shape, and the suite
harness stayed green because it compares `tEvent["name"]` and never dispatches.
**Rule:** a dispatched event name must never equal a public handler name in the
emitting module; when they collide, rename the EVENT. **Gate:**
`tools/check-lcb-call-types.py` check 4, over every module's `_eventName`, the
historical case pinned in `tools/test-lcb-call-types.py`.

### 6.8 `open secure socket` works, and that is NOT the same as "TLS verifies"
**OBSERVED 2026-08-24** (Windows x86_64, OXT 9.6.3; dated by the RUN, not the
commit a day later), the suite's first secure socket.
`nostrxt/src/nostr-relay.livecodescript`'s `nxrConnect` secure branch against a
public Nostr relay:

    connecting to wss://nos.lol (handle 1)
    relay 1: open
    identity ready: npub154kp062... / signed event 33f9b9a3...
    nxEventVerify: the event verifies / published a4a3fe9d... / ok a4a3fe9d...: true

Settled: `open secure socket to <host:port> with message <name>` exists,
connects asynchronously and fires its message like the plain form; persistent
`read from socket ... with message` plus `write to socket` carry an RFC 6455
byte stream over it.
**Does NOT mean TLS verifies.** Success against a good host is consistent with
both "verified the chain" and "verified nothing", and no bad certificate has
been offered. Unmeasured: refusal of an invalid or self-signed certificate, the
root store, the hostname check, `the sslCertificates`, SNI, TLS versions, and
how a failure is delivered (`socketError` is assumed). Treat code that would be
unsafe under "no verification" as unsafe. The plain `ws://` branch of the same
handler has never run. **Gate:** none possible headlessly; only a deliberately
bad certificate can move this entry (`nostrxt/docs/07-capabilities-required.md`
gap #2; `VERIFY (on-engine)` at the call site).

### 6.9 The Internet library (libURL) speaks https, delivers chunked bodies whole, and keeps the LAST reply's headers
**OBSERVED 2026-09-15/16** (the user's OXT engine, libURL 1.2.0; platform not
recorded), from archivext's demo (now in its own repository). Not the suite's
first libURL contact: coinxt's wallet recorded its Esplora-over-clearnet
transport (`load URL ... with message`, https to blockstream.info) on an
engine on 2026-09-02, as a reported testnet receive and then firing on both
chains in a pasted log (`coinxt/CLAUDE.md`, the 2026-09-02 entries). What the
archivext runs add:

- **`load URL "https://..." with message` and `put URL "https://..."` both
  work** (async: a 400, then a watchdog timeout on one broad query; blocking:
  three HTTP 200s with real JSON, each with `Server: nginx/1.31.3` and
  `Strict-Transport-Security`). The 6.8 caveat applies: no bad certificate has
  been offered to libURL.
- **A `Transfer-Encoding: chunked` body arrives whole**: 196,716 bytes through
  `put URL`, one JSON document; no reply carried `Content-Length`.
- **`libURLLastRHHeaders()` is the last reply RECEIVED, not the last request
  MADE**: after an unanswered request it still carried the previous reply's
  `Onion-Location`, so headers beside a failure quote an earlier success (5.10).
- **A second load of a URL still loading is refused** (`the result`:
  `URL is currently loading`); a load whose watchdog gave up is STILL loading,
  so the next request fails instantly and reads like a site error.
  `unload URL` cancels it (DOCUMENTED; the refusal was seen once, before the
  unload landed).
- **`libURLSetCustomHTTPHeaders` replaces the whole default header set**
  (DOCUMENTED); `httpHeaders` ADDS. The one request using it drew the 400,
  INFERRED as the cause at best (the query also timed out without it).
- **The async success path delivers (2026-09-16)**: four
  `load URL ... with message "axUrlDone"` requests across three families each
  reached the handler with the URL matching its request, so correlation by URL,
  the `cached` status, `URL x` for the body and `unload URL` after it held on a
  reply that ARRIVED; an empty result page came back as a normal reply.
- **Some archive.org queries answer in under a second** (17,098,672 hits for
  `mediatype:(movies OR video OR television)`) **and others go silent for 30
  s** (the same OR-ed with 26 `identifier:` terms in a `mediatype:collection`
  clause). That is the site, but a 30 s silence looks like an engine fault
  without a watchdog and a cheaper second request.

**Gate:** none possible headlessly. The narrowed questions (a bad certificate;
`unload` freeing the URL; the async `item` kind) moved with archivext.

## 7. How to add to this file

Add an entry with the next free number in its section (never reuse or
renumber one), carrying: (1) **the symptom verbatim**, error text included - it
is what the next person searches for; (2) **what it cost** or broke; (3) **an
honest evidence class** with the run's date; (4) **the gate** that holds it,
if any, so a reader knows whether they are protected or merely warned; (5)
**what it does NOT mean** - the neighbouring construct that is fine (`return`
in a catch, the one-argument call form); omitting it turns a rule into
superstition. Member-specific gotchas stay in that member's `CLAUDE.md`; this
file is for behaviour of the ENGINE, which is the same everywhere.
