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

**Do not promote an entry between classes without a dated run.** An unexecuted
line is not evidence in either direction - that is the "shipped is not run"
lesson the root `CLAUDE.md` records, and it applies to this file first.

---

## 1. Parsing and scope

### 1.1 A second `script "Name"` line silently breaks declaration scope
**OBSERVED 2026-08-17.** A demo whose stack script contained its own
`script "EnetLanChat"` on line 1 and an embedded library's `script "enetHelpers"`
200 lines down threw, from a handler 700 lines below both:

```
Chunk: error in object expression
uiStatus "Hosting on port" && kEcPort && "-" && the number of keys of sPeers ...
```

`local sPeers` was declared plainly above that handler. The second script-name
line put everything after it outside the scope the first file's declarations
were in, so `sPeers` resolved as an undeclared name (see 2.1), and
`the number of keys of` a *string* is a chunk expression against a non-object.

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

---

## 2. Evaluation

### 2.1 An undeclared name evaluates to the literal text of its own name
**OBSERVED, repeatedly, and this is the single most expensive behaviour in this
file.** It does not error. `sPeers` becomes the string `"sPeers"`, and the
failure surfaces far downstream wearing someone else's clothes:

- as `add "cx1sPassed" to sPassed` -> "error in source expression" (1.2);
- as a digest compared against the string `"cx1kBip39Mnemonic"` -> a tidy FAIL
  that reads like a real library defect;
- as `the number of keys of "sPeers"` -> `Chunk: error in object expression`
  (1.1).

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
in onionxt, scheduled as runbook S2 item 2. **See trap 5.3.1:** it defaults to
the same ports a system tor already holds.

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
