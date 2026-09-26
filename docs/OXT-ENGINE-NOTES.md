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

### 1.8 `the detailedFiles` is a compile-time "bad factor"
**OBSERVED, undated**: the family's living-gotcha log (`onionxt/templates/CLAUDE.md` section 16, byte-identical in `coinxt/templates/`), whose seed entries are "confirmed on-engine in the family" from before the suite existed; this tree has carried them since its assembly (327235a, 2026-08-07) and no run date survives, so none is asserted. Promoted here 2026-09-24. A line reading `the detailedFiles` fails to
compile with a "bad factor" error: OXT does not accept it as a factor (the
log calls it a LiveCode/OXT divergence; no LiveCode run is recorded here).
**Rule:** use `the files` (and `the folders`) and fetch any per-file detail
separately. **Gate:** none (no tree file uses it).
**Does NOT mean:** `the files` and `the folders` are fine.

### 1.9 A bitwise call `bitAnd(x, y)`, or `^` inside a compound expression, is "double binary operator"
**OBSERVED, undated**: the family's living-gotcha log (`onionxt/templates/CLAUDE.md` section 16, byte-identical in `coinxt/templates/`), whose seed entries are "confirmed on-engine in the family" from before the suite existed; this tree has carried them since its assembly (327235a, 2026-08-07) and no run date survives, so none is asserted. Promoted here 2026-09-24; the call form was hit again as holde-em's H7
(`bitXor` threw at v0.4.1, in that repository's pre-fold passes, recorded in
`holde-em/CLAUDE.md`). `bitAnd` / `bitOr` / `bitXor` / `bitNot` are OPERATORS
in LiveCodeScript, so the function-call spelling reads as two operators in a
row; `2 ^ n` inside a larger expression drew the same "double binary operator"
(or "bad expression") on some parsers.
**Rule:** `x bitAnd y`; factor a power into its own statement or a `pow2(n)`
helper. **Gate:** the unified checker's check 13 refuses the two-argument call
form (fixture-tested in `tools/test-checker.py`); nothing gates `^`.
**Does NOT mean:** the OPERATOR form is fine and engine-passed across box2dxt,
nocloud, torrentxt and sodiumxt's examples (`a bitXor b`,
`tM bitAnd (bitNot 255)`); holde-em's no-bitwise-at-all rule is that member's
own law.

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
**Superseded in part, OBSERVED 2026-09-24 (Windows) and 2026-09-25 (Linux);
read the counterpoint and its settlements below first:** on both engines the
itemDelimiter is HANDLER-LOCAL in both directions (the lineDelimiter was not
probed on either). The rule stands; the title's cross-handler claim does not,
for the itemDelimiter, and the number is kept because the tree cites it.
**OBSERVED** (several times, in shipped code). A handler that sets one and
returns without restoring it corrupts every later parse in unrelated code; the
symptom is always "item 1 returned the whole list". **Rule:** save, set,
restore, around the NARROWEST span that needs it.
**Counterpoint, DOCUMENTED (added 2026-09-24):** the LiveCode dictionary
(`docs/dictionary/property/itemDelimiter.lcdoc`, livecode `develop`) says the
opposite of this entry's title: `itemDelimiter` "is a local property", "reset
to comma when the current handler finishes executing", and "setting it in one
handler does not affect its value in other handlers it calls". This entry's
observations are undated and name no handler pair, so they may have been a
delimiter left set for the REST of one handler, which both readings agree is a
leak. Neither side has a dated run that separates them. box2dxt's harness v32
(`stTestCallerDelimiter`, 2026-09-24) prints both halves - whether a caller's
tab reaches a called handler, and whether a callee's comma leaks back - so its
first engine run settles it: record the answer here, and reclassify this entry
only then. The rule holds under both readings, which is why nothing changes
until it does.
**Settled for Windows, OBSERVED 2026-09-24** (the D-23 suite paste's first
run, box2dxt harness v32 folded in, 385/0; runbook section 8; a 64-bit OXT by
the maintainer's account; the same two lines again on 2026-09-25): both halves
printed the dictionary's answer. "a caller's tab does NOT reach a called
handler on Win32 (it saw comma)", and "a Kit call left its caller's delimiter
alone on Win32 (tab in, tab out)". So on that engine an itemDelimiter set in
one handler is invisible to the handlers it calls and cannot leak back out of
them: the title's "global" is WRONG there for the itemDelimiter. The probe
reads only `the itemDelimiter`; the lineDelimiter, which the dictionary
describes the same way, was not probed. This entry's undated observations
(platforms unknown) were most likely the leak that both readings share - a
delimiter left set for the rest of ONE handler, reaching a later parse in the
same handler. macOS has not run the probe (Linux has, below); the
dictionary's claim is platform-independent, so the expectation is the same
answer everywhere, not yet the evidence.
**Settled for Linux too, OBSERVED 2026-09-25** (the D-23 suite paste on a
Linux engine, box2dxt harness v32 folded in, 385/0; runbook section 8; 64-bit
Kubuntu 24.04 and "the latest" OXT by the maintainer's account, its version
not given): the same two lines, "a caller's tab does NOT reach a called
handler on Linux (it saw comma)" and "a Kit call left its caller's delimiter
alone on Linux (tab in, tab out)". Two platforms now read the dictionary's
answer for the itemDelimiter, both directions; the lineDelimiter is still
unprobed on any engine, and macOS has not run the probe.
**What changes:** the reason, not the rule. Save, set, restore still guards
the rest of the handler that set the delimiter, which is where every
remaining hazard lives, and it costs nothing where it is redundant. What no
longer holds is "an unrestored delimiter corrupts its caller" - many member
comments and the carried templates' gotcha still say it, and that wording is
open work (WORK-PLAN suite-wide), not a defect: nothing that restores a
delimiter is wrong for doing so. **Does NOT mean:** a handler may leave a
delimiter set and then parse something else itself.

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
site, because after the arithmetic nothing is left to detect - and decide
that bound on exact integers, not against a quotient: on 2026-09-24 an engine
let 2^53 + 1 through a quotient-form bound that IEEE arithmetic refuses (2.10).

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
sees a collision only where a vector drives two spellings. riptide's LAN keys
were the concrete case: driven through the folded model on 2026-09-24, the
pre-fix demo dropped a draft from "phone" after one from "Phone" as a replay,
silently. The same day its demo re-keyed per-device state by the name's UTF-8
bytes in hex (`raLanDevKey`), a key no fold can merge, and `check-demo-boot`'s
`drive_lan_keys` drives both spellings.
**Does NOT mean:** `the keys of` still returns each key's ORIGINAL spelling, so
a scan over the keys is exact; only the subscript lookup folds.

### 2.8 `textDecode(x, "UTF-8")` is LOSSY and does not throw
**OBSERVED 2026-08-15** (a suite paste, platform not recorded; commit
1d8a39b): riptide's phase 4-7 compute ran green except three checks that fed
malformed UTF-8 to a name parser. Six parsers guarded their decode with a
`try` commented "textDecode throws on malformed UTF-8"; it returned
replacement characters and a non-empty string instead, so every one of those
guards was inert and the three authenticated parsers would have handed back a
mangled name where they meant to refuse. Recorded as riptide's trap 4
(`riptide/CLAUDE.md` ("is LOSSY (OBSERVED 2026-08-15)")); promoted here
2026-09-24.
**Rule:** validate by ROUND TRIP - decode, re-encode, require identical bytes
(riptide's `rsBytesAreUtf8`); keep an inner `try` only for an engine that does
throw. **Gate:** none static; riptide's harness feeds the malformed vectors.
**Does NOT mean:** valid UTF-8 round-trips exactly; only the refusal is
missing.

### 2.9 `binaryDecode` returns a COUNT, not the decoded value
**OBSERVED, undated**: the family's living-gotcha log (`onionxt/templates/CLAUDE.md` section 16, byte-identical in `coinxt/templates/`), whose seed entries are "confirmed on-engine in the family" from before the suite existed; this tree has carried them since its assembly (327235a, 2026-08-07) and no run date survives, so none is asserted. Promoted here 2026-09-24. `binaryDecode(...)` "returned" a number where
the decoded bytes were expected: it FILLS its output variables and returns how
many it filled (`binaryEncode` is the function that returns data).
**Rule:** `get binaryDecode("H*", pData, tHex)`, then read `tHex`. **Gate:**
none.
**Does NOT mean:** `binaryEncode` returns its result like any function.

### 2.10 A comparison of two nearly-equal numbers is not decided the IEEE way: a bound checked against a QUOTIENT lets the value through
**OBSERVED 2026-09-24** (Windows, the D-23 suite paste's first run; runbook
section 8): riptide's `rsReadBEu64` refused a u64 past 2^53 with
`if tHi > (9007199254740992 - tLo) / 4294967296 then return empty`. For the
first unrepresentable value, 2^53 + 1 (`tHi` = 2097152, `tLo` = 1), IEEE
double arithmetic answers `2097152 > 2097151.99999999976716935...` TRUE, and
so did the family interpreter, so every headless gate was green. On the engine
the record PARSED, and the harness check "a seq of 2^53 + 1 is REFUSED (the
first unrepresentable value)" went red while its neighbours (2^53 itself
parses, and comes back exact; an all-ones u64 is refused) passed. The two
operands differ by about 2.3e-10: 1.1e-16 of their size.
**OBSERVED 2026-09-24, the second run (a fresh stack, the paste regenerated at
21aaa61): the comparison treats nearly-equal numbers as equal.** The fixed harness prints
four probes that pure IEEE answers `true,true,true,true`, and the engine read
`true,false,false,false`: `1 + 1e-7 > 1` true, but `1 + 2^-51 > 1` false,
`2097152 > (2^53 - 1) / 2^32` false (the old bound itself) and
`1 + 23 * 2^-52 > 1 + 22 * 2^-52` false. The three that read false compare exact
doubles, so it is how the engine decides a comparison, not its arithmetic.
That reading fitted three families of rule (a relative tolerance, an absolute
one, a decimal round trip), and nostrxt's "since excludes older events"
(`1700000000 < 1700000001`, green in the same run) capped a relative one below
5.9e-10.
**OBSERVED 2026-09-24, the third run (10:10 PM local, a fresh stack, the paste
as regenerated at b34f7b0): the tolerance is RELATIVE, between 8 and 16
DBL_EPSILON.** The harness's second probe line read `true,false,16,16`:
`1e-10 > 0` true (no absolute tolerance of that size), `2^30 + 2^-21 > 2^30`
false (two ulps, 2 DBL_EPSILON of their size, called equal), and the smallest
step the engine tells apart is 16 ulps both at 1 and at 8, where an ulp is 8
times larger: 1 + 8 ulps compares equal to 1, 1 + 16 ulps does not, and the
step scales with the size. Only the relative family predicted that reading (an
absolute rule reads `false,true,K,K/8`, a decimal round trip
`true,false,K,K/8`).
**DOCUMENTED 2026-09-25, from the engine source**, which names the constant
inside that bracket: `engine/src/exec-logic.cpp` (`MCLogicIsEqualTo`,
`MCLogicCompareTo`; byte-identical in OXT's own tree,
github.com/OpenXTalk-org/OpenXTalk-Community-DPE `master`, and in livecode
`develop-9.6`) calls two unequal numbers EQUAL when
`|a - b| / min(|a|, |b|) < MC_EPSILON`, or, when the smaller magnitude is
itself below MC_EPSILON, when `|a - b| < MC_EPSILON`; `engine/src/sysdefs.h`
defines `MC_EPSILON` as `DBL_EPSILON * 10.0` (about 2.2e-15) in both trees.
That rule reproduces all eight readings of the two probe lines and the first
run's accept. It governs every numeric `=`, `is`, `<>`, `is not`, `<`, `<=`,
`>` and `>=` whenever both operands convert to numbers, number-like TEXT
included (2.11). The maintainer's binary was not inspected, so the 10 was the
source's until the Linux and Windows runs below read it off an engine.
**OBSERVED 2026-09-25, on Linux and then on Windows (the D-23 suite paste, the
first two recorded readings of the harness's third probe line; runbook section
8; both a 64-bit OXT by the maintainer's account, Linux on Kubuntu 24.04 with
"the latest" OXT, the Windows OXT build not stated): the constant is 10
DBL_EPSILON, to the digit.** On Linux the first two probe lines read exactly as
on 2026-09-24's Windows runs (`true,false,false,false` and `true,false,16,16`),
and the third read `true,true,false,true,false,true,true,false`, the engine
source's predicted reading item for item (exact IEEE comparison would read
items 3 to 8 `true,true,true,true,false,false`). The Windows run the same day
printed all three lines character for character the same:
- items 7-8: `450359962737050 is 450359962737051` true, and
  `450359962737049 is 450359962737050` false. Under the source's form (the gap
  over the SMALLER operand), the constant lies above 1 / 450359962737050 and at
  most 1 / 450359962737049, that is between 10 - 8.9e-15 and 10 + 1.3e-14
  DBL_EPSILON; 10 DBL_EPSILON is 1 / 450359962737049.6, between the two. A
  constant of 9 DBL_EPSILON reads the pair `false,false`, and one of 11 or 16
  reads `true,true`;
- items 5-6: `2^49 < 2^49 + 1` false (1 apart is 8 DBL_EPSILON of their size:
  equal) and `2^48 < 2^48 + 1` true (16 DBL_EPSILON: told apart);
- items 3-4: `1e-15 > 0` false and `1e-14 > 0` true, the absolute branch near
  zero, its threshold between the two (the source's is 2.2e-15);
- items 1-2 read how text becomes a number (2.11).
So on both platforms the rule's shape (relative above the near-zero branch,
absolute within it) and its constant are OBSERVED at every point the three
lines probe; between those points, and for the comparison operators no line
uses, the rule stays the source's (DOCUMENTED) and what follows from it
INFERRED (below). On Windows the 2026-09-24 runs had bracketed the relative
tolerance between 8 and 16 DBL_EPSILON, and until the third line ran there
the 10 was INFERRED from the source and from Linux; it is now read off that
engine too. macOS has not run any probe line.
**What follows** (INFERRED from the rule, bar the two points marked, which the
third probe line read directly on Linux and on Windows):
- Two INTEGERS one apart compare EQUAL from N = 450,359,962,737,050 (2^52 / 10,
  about 2^48.7; OBSERVED on both at that N and one below it, and at 2^49 and
  2^48), and d apart from about d x 4.5e14; below that every integer
  comparison is exact. Nothing the tree compares honestly lives up there
  (millisecond clocks sit near 1.7e12; satoshi amounts blur within a few sats
  only past 4.5 million BTC; riptide's seqs start at 0 or at the seconds), but
  a wire integer an attacker picks can (riptide/CLAUDE.md trap 9).
- Near zero the tolerance is absolute: anything within 2.2e-15 of 0 equals 0
  (OBSERVED on Linux and Windows: 1e-15 equals 0, 1e-14 does not).
- A verdict that rests on a sub-integer gap fails at ANY size. coinxt's wallet
  decoders bounded their accumulators as riptide did
  (`tValue > (9007199254740992 - tByte) / 256`): a margin of 0.0039 at 3.5e13,
  safe from an absolute tolerance, and under the relative rule the engine has,
  exactly as broken as riptide's.
**Rule:** decide a bound with exact INTEGERS that differ by at least 1 at a
modest magnitude (below 2^48 at the very least) - compare the two u32 halves,
or the leading bytes - and never against a quotient, a product past 2^53, or
any value whose verdict hangs on a sub-integer difference. A wide integer that
must be ORDERED exactly (a seq, an amount past 4.5e14) is compared on its
halves too. A bound that only works in exact arithmetic is a bound the engine
may not enforce. Both sites were rewritten that way on 2026-09-24: riptide's
refused 2^53 + 1 on the engine in the second run, and again on Linux and on
Windows on 2026-09-25; coinxt's (the wallet, which the paste does not carry) is
verified statically; needs an OXT pass.
**Gate:** riptide's harness checks the u64 bound from both sides (2^53 parses,
2^53 + 1 is refused), which is how an engine run caught it, and prints the
three probe lines above. Headlessly, the interpreter itself compares the IEEE
way, so two gates replay the bounds under the ENGINE'S RULE and two candidates
the probes ruled out, kept as margin (an absolute 1e-6 tolerance, a
15-significant-digit round trip). Each model is first proven to reproduce the
engine's accept through the old line, and the engine's rule to read the
fourteen recorded numeric probe answers through the interpreter (the first two
lines, and the third line's items 3 to 8; its items 1-2 are a text parse the
interpreter does not model) while each margin model misreads one:
`riptide/tools/check-script-vectors.py` (tier 1c, plus a static scan refusing
a library comparison against a quotient) and
`coinxt/tools/check-wallet-vectors.py` (tier 4). They settle the rewritten
bounds' LOGIC. No gate yet refuses a comparison that falls INSIDE the
tolerance anywhere else in the tree (docs/WORK-PLAN.md).
**Does NOT mean:** integer arithmetic below 2^53 is inexact (it is exact:
2.4), or that comparing small integers is unreliable. A verdict that rests on
a difference below 10 DBL_EPSILON of the operands is, and for two integers one
apart that begins at 4.5e14.

### 2.11 `is` compares two number-like TEXTS as numbers, so hex digests and tokens can compare equal when their bytes differ
**DOCUMENTED 2026-09-25, from the engine source; two of its claims OBSERVED
the same day on Linux and on Windows (below), the rest still DOCUMENTED.**
`MCLogicIsEqualTo` and `MCLogicCompareTo` (`engine/src/exec-logic.cpp`, the
code 2.10 cites) first try to turn BOTH operands into numbers, and when both
turn, compare them as numbers by 2.10's rule; only otherwise do they compare
text. Text becomes a number through `MCU_strtor8`
(`libfoundation/src/foundation-typeconvert.cpp`): an integer parse, then C
`strtod` over up to 384 characters, with no range check. So:
- `"1e5" is "100000"` and `"0012" is "12"` are true;
- any two texts that overflow a double are both +inf, so `"1e999" is "2e999"`
  is true;
- `set the caseSensitive to true` changes none of this: case matters only on
  the text path, which two number-like operands never reach. Data values go
  through the same parse.
**OBSERVED 2026-09-25, on Linux and then on Windows** (the D-23 suite paste,
both a 64-bit OXT by the maintainer's account; runbook section 8): riptide's
third probe line read `"1e999" is "2e999"` TRUE and `"1e5" is "100000"` TRUE
on both, where the text path answers false for both. So two texts that
overflow a double compare equal, and exponent-form text compares as a number.
Nothing else here has run: `"0012" is "12"`, a leading `+` or whitespace, the
`inf` and `nan` spellings, the 384-character limit and the `caseSensitive`
claim stay DOCUMENTED, and macOS has not run the line.
holde-em's `heHexEq` pins, green in the same runs, name bare `is`'s answer only
in their labels ("bare is: equal on the engine") and assert the helper's, so
they observe the fix, not this parse.
A lowercase hex string is number-like when it is all digits, or digits, one
`e`, digits. Among random 64-character digests that is rare (about 1 in 10^12),
but a value an ATTACKER chooses can be number-like on purpose, and a digest
whose preimage the attacker grinds needs about 2^41 tries. coinxt met the idea
first as a hazard, never as a failure: its "discipline 3" moved the
Base58Check checksum off `is` ("has not been observed to collide on this
surface") and its harness compares hex with `("h" & pA) is ("h" & pB)`.
**What it put at risk, and the fixes** (a read-only sweep, 2026-09-25; the
costs computed, not demonstrated). holde-em's audit compared a seed commitment
that came off the wire with `is not` against the hash of the revealed seed, so
a dealer who committed a number-like value and held seeds whose hashes were
number-like too passed the audit with whichever seed it liked; its chain-head
checks had the same shape. quickshare's capability gate
(`if tTok is not sCwToken`, 32 hex characters, in nocloud and in torrentxt's
torrent-quickshare) admitted `/1e999/` on the one share in about 1.2 million
whose token overflows, and datachannel-dht-chat's 8-hex answer nonces
overflowed about 1 time in 120 each. All were fixed the same day: holde-em
(v0.25.4, harness 46) compares every hex identifier through `heHexEq` (40
sites; its 64-zero genesis head had compared equal to "0"), and the other two
prefix a letter at the comparison. holde-em's half first ran on an engine on
2026-09-25 (the suite paste on Linux, then on Windows: its `heHexEq` and
near-integer pins green at v0.25.5 / harness 47, 751/0/5 both times). The
quickshare and dht-chat fixes, which the paste does not carry: verified
statically; needs an OXT pass.
The same parse makes INDEX aliases, and an array key keeps the raw text:
holde-em checked a wire position as a NUMBER but stored and counted it under
its raw spelling, so "03", "3.0", "+3", " 3" and "3e0" were position 3 to the
check and five new positions to the count, and a dealer could fake "every
commitment is in" and grind its own seed after the others'. The interpreter
reads the first three forms as numbers too, so that half was visible
headlessly; the rest is inferred from `MCU_strtol` and `strtod`. v0.25.5
(harness 47, 2026-09-25) accepts only canonical digit text for every wire
index (`heCanonIdx`), keys and compares by it, walks its counts over the
hand's own range, and binds every per-hand wire to the open hand. Its harness
pins (`heCanonIdx` refusing every alias of 3, the alias and stale-wire attacks
of section 15, the walked counts) ran green on an engine on 2026-09-25 (the
same two runs, Linux and Windows); on a live wire between machines the fix is
verified statically; needs an OXT pass (runbook row 18).
**Rule:** never compare a hex digest, a token, a key or any identifier with
bare `is`, `is not`, `=` or `<>`. Prefix a letter to both sides (no number
parse accepts `h1e5`), adding `set the caseSensitive to true` where case is
part of the value (hex digits are not: `heHexEq` lowercases both sides), or
compare byte by byte (coinxt's `cxCompareBytes`, nostrxt's `nxCtEqualHex`).
riptide's "compare kinds by BYTE, never `is`" is the same rule, met from the
case side.
**Gate:** none yet (docs/WORK-PLAN.md suite-wide #18 proposes a static rule,
#19 an interpreter that knows the parse). The family interpreter's `_eq`
treats only `-?\d+(\.\d+)?` as a number, so it reads every exponent-form
pair as text and no headless gate sees this class; holde-em's harness pins
the genesis head against "0", the one number-like pair the interpreter does
read as numbers. riptide's harness prints `"1e999" is "2e999"` and `"1e5" is "100000"` in its
third probe line (2026-09-25), which read the parse on Linux and on Windows
the same day (above): a printed diagnostic, not a check, so a different
reading on another engine would print, not fail.

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

### 3.5 A PRIVATE handler is unreachable through `with message`, `send` and `dispatch`
**OBSERVED, undated**: the family's living-gotcha log (`onionxt/templates/CLAUDE.md` section 16, byte-identical in `coinxt/templates/`), whose seed entries are "confirmed on-engine in the family" from before the suite existed; this tree has carried them since its assembly (327235a, 2026-08-07) and no run date survives, so none is asserted. Promoted here 2026-09-24. A socket or app callback handler silently never
fired: it was `private`, and the message path (`... with message "x"`,
`send "x" to ...`, `dispatch "x" to ...`) delivers only to public handlers.
Nothing errors; the callback just never arrives.
**Rule:** every `with message` / `send` / `dispatch` target is a PUBLIC
handler (quote its name). **Gate:** none checks visibility at the target.
**Does NOT mean:** a private handler called DIRECTLY by name from the same
script is fine.

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
| Win32, 2026-09-24 (harness v32, the suite paste; a 64-bit OXT by the maintainer's account) | 24, 73 | 24, 73 | EXACT, printed as a note |
| Linux, 2026-09-25 (harness v32, the suite paste; 64-bit Kubuntu 24.04 by the maintainer's account) | 24, 73 | **0, 0** | write-only again, printed as a note: "readback does NOT track the write on Linux" |
| Win32, 2026-09-25 (harness v32, the suite paste; the same 64-bit machine as 2026-09-24, by the maintainer's account) | 24, 73 | 24, 73 | EXACT again, printed as a note: "playLoudness readback is EXACT on Win32" |

It broke v29's exactness assert on Linux, then v30's replacement ORDER assert
(a high write reads back above a low one) on a healthy Linux engine. Since v31
the harness asserts only that the value is readable and prints the readback,
so the 2026-09-25 Linux reading, the same constant 0 as 2026-08-21's, was a
note on a green run, not a FAIL. The same day's Windows run read back exact
under the same harness and paste, both engines 64-bit: the split follows the
platform, not the date, the harness or the bitness (INFERRED: each platform's
readings come from one machine per run, never two side by side, so the
platform is not yet told apart from the machine and its audio stack).
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

### 5.11 `go card "X" of me`, `field ... of card ... of me` and `card 1 of me` are rejected
**OBSERVED 2026-08-15** (a maintainer's report from an engine, commit
36ee117; the error text was not recorded): riptide's multi-card demo
conversion wrote card navigation and cross-card references as `... of me` at
48 sites, and the engine refused them. Recorded as riptide's trap 2
(`riptide/CLAUDE.md` ("Card navigation (OXT report 2026-08-15, 48 sites)"));
promoted here 2026-09-24. Every other demo in the family was single-card, so
the tree held no engine-proven multi-card idiom to copy.
**Rule:** `go to card "X"` / `go to card 1`; plain `field "X" of card "Y"`
inside one stack; `set the name of this card to ...` right after
`create card`. **Gate:** none - the checker passed all 48 sites, and no rule
was added because nothing could execute one (commit 36ee117 says why).
**Does NOT mean:** `send "raPoll" to me in N milliseconds` is correct and
engine-proven (a message target, not an object reference).

### 5.12 A comma in `textFont` means `fontname,language`
**OBSERVED, undated**: the family's living-gotcha log (`onionxt/templates/CLAUDE.md` section 16, byte-identical in `coinxt/templates/`), whose seed entries are "confirmed on-engine in the family" from before the suite existed; this tree has carried them since its assembly (327235a, 2026-08-07) and no run date survives, so none is asserted. Promoted here 2026-09-24. A monospace field rendered in the default
proportional font: `set the textFont` read a CSS-style comma list as a font
name plus a Unicode language tag.
**Rule:** one font name, e.g. `"Courier"`. **Gate:** none.

### 5.13 A field's `backgroundColor` shows only when the field is opaque
**OBSERVED, undated**: the family's living-gotcha log (`onionxt/templates/CLAUDE.md` section 16, byte-identical in `coinxt/templates/`), whose seed entries are "confirmed on-engine in the family" from before the suite existed; this tree has carried them since its assembly (327235a, 2026-08-07) and no run date survives, so none is asserted. Promoted here 2026-09-24. Setting a field's `backgroundColor` appeared to
do nothing: the field was not opaque.
**Rule:** `set the opaque of field "x" to true` before relying on its fill.
**Gate:** none; the UI kit master (`tools/ui-kit.livecodescript`) sets it
where it fills a field.

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

### 6.10 `read from socket ... until crlf` returns the CRLF with the data
**OBSERVED, undated**: the family's living-gotcha log (`onionxt/templates/CLAUDE.md` section 16, byte-identical in `coinxt/templates/`), whose seed entries are "confirmed on-engine in the family" from before the suite existed; this tree has carried them since its assembly (327235a, 2026-08-07) and no run date survives, so none is asserted. Promoted here 2026-09-24. A line read with `until crlf` failed equality
and suffix comparisons that looked obviously correct: the engine returns the
delimiter as part of the data.
**Rule:** strip the line ending before parsing (one shared helper).
**Gate:** none.

### 6.11 A `read from socket` with no quantifier STREAMS
**OBSERVED, undated**: the family's living-gotcha log (`onionxt/templates/CLAUDE.md` section 16, byte-identical in `coinxt/templates/`), whose seed entries are "confirmed on-engine in the family" from before the suite existed; this tree has carried them since its assembly (327235a, 2026-08-07) and no run date survives, so none is asserted. Promoted here 2026-09-24. `read from socket s with message "x"` with no
`until` / `for` delivers whatever bytes are available, chunk by chunk, as they
arrive; it does NOT wait for the peer to close.
**Rule:** treat it as a streaming read and frame by length or delimiter
yourself. **Gate:** none.

### 6.12 A failed `accept connections` bind shows ONLY in `the result`
**OBSERVED, undated**: the family's living-gotcha log (`onionxt/templates/CLAUDE.md` section 16, byte-identical in `coinxt/templates/`), whose seed entries are "confirmed on-engine in the family" from before the suite existed; this tree has carried them since its assembly (327235a, 2026-08-07) and no run date survives, so none is asserted. Promoted here 2026-09-24. A local listener "worked" (nothing thrown) and
every connection to it died; behind an onion service, every visit returned an
empty response. The bind had failed (Windows 10013 WSAEACCES, a port range
reserved under Hyper-V / WSL2 / Docker; 10048 WSAEADDRINUSE, in use) and said
so only in `the result`, which was never read.
**Rule:** read `the result` immediately after `accept connections on port N
with message "x"` and fail closed with a reason that lets the user pick
another port. **Gate:** none.

### 6.13 A refused connection on Windows arrives as "Error 10061 on socket" through `socketError`
**OBSERVED, undated**: the family's living-gotcha log (`onionxt/templates/CLAUDE.md` section 16, byte-identical in `coinxt/templates/`), whose seed entries are "confirmed on-engine in the family" from before the suite existed; this tree has carried them since its assembly (327235a, 2026-08-07) and no run date survives, so none is asserted. Promoted here 2026-09-24; onionxt's ledger lists `socketError` reaching
the library and failing closed on 10061 and 10013 among its confirmed engine
facts (`onionxt/CLAUDE.md`, item 7). WSAECONNREFUSED: nothing listens on
that port.
**Rule:** an environment condition (service not running, wrong port) handled
on the `socketError` path: surface it cleanly, never treat it as a crash.
**Gate:** none. The engine owns the `socketError` name (the root CLAUDE.md's
engine socket names).

### 6.14 `open file ... for write` TRUNCATES, per the reference and the engine source; the tree has said it does not
**DOCUMENTED 2026-09-24**, against a claim the tree carries as fact. The
LiveCode dictionary (`docs/dictionary/command/open-file.lcdoc`, livecode
`develop`) says write mode "replaces the file's contents from the starting
point to the end of the file" and warns that LiveCode "will erase them even if
you do not write to the file after opening it". The engine source agrees:
`engine/src/dsklnx.cpp` and `dskmac.cpp` open write mode with
`fopen(path, IO_WRITE_MODE)`, which is `"wb"` / `"w"` (C truncates to length
zero), and `dskw32.cpp` maps `kMCOpenFileModeWrite` to `CREATE_ALWAYS`
(Windows truncates an existing file). OXT's own file layer was not read; it
forks LiveCode 9.6.
The OPPOSITE claim - "`open file ... for binary write` does NOT truncate in
this engine (it overwrites from offset 0 and leaves any longer tail in
place)" - stands in two save paths' comments (`qsEditWriteRoute` in
`nocloud/src/nocloudquickshare.livecodescript` and
`torrentxt/examples/torrent-quickshare.livecodescript`) and was repeated in
OPEN-DECISIONS' blockchain summary. It is **UNEVIDENCED**: no dated run, no
reference; it arrived with the suite's assembly (327235a, 2026-08-07) from a
pre-suite repository. nocloud's own append route calls the same write route
the one that "creates/truncates". The house safe-write it motivated,
delete-then-recreate, is correct under either reading, which is why nothing
has broken.
**Rule:** do not rely on either behaviour for correctness. Delete first (the
house form) or, better, write a sibling temporary file and `rename` it over the
target, and read `the result` after each step. Neither in-place form is
crash-safe: a process that dies between the open and the last write leaves an
empty (truncating) or missing (delete-first) file either way; only the rename
form keeps the old bytes until the new ones are whole.
**Gate:** none. **Probe** (runbook S1, the work plan's optional measurements):
write 10 bytes to a scratch file, `open file f for binary write`, write 3
bytes, `close file f`, then `put the number of bytes of URL ("binfile:" & f)`:
3 means the reference holds (promote this entry to OBSERVED and correct the two
comments), 10 means the tree's claim holds for this engine (record it here as
a divergence).
**Does NOT mean:** `for update` (`"r+b"`, no truncation: writes land at the
position and keep the bytes beyond them) or `for append` (writes at the end).

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
