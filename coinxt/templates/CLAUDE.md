# CLAUDE.md - portable xTalk / LiveCode / LCB engineering guide

> **What this file is.** A reusable, project-agnostic `CLAUDE.md` for any OpenXTalk (OXT) / LiveCode /
> LCB library or app. It is the accumulated, hard-won knowledge of the xTalk family (Box2Dxt,
> ShowControl, TorrentXT, SodiumXT, OnionXT, and their kin): the engine idiosyncrasies, the
> compiler traps, the operators that look like functions, the FFI landmines, and the workflow that keeps
> a script honest when there is no headless compiler to catch you. Most of these were paid for in full,
> on the engine, one confusing failure at a time. They are collected here so no future project pays for
> the same lesson twice.
>
> **How to adopt it.** Copy this file to the ROOT of a new xTalk/LCB project as `CLAUDE.md`. Then add a
> short project-specific header at the top ("## What this is", the architecture sketch, the project's own
> rules), and DELETE nothing from the generic sections below unless it is genuinely inapplicable. The
> generic sections are the safety net.
>
> **This is a LIVING document. KEEP ADDING TO IT.** Every time the engine bites you with a new gotcha,
> a new reserved word, an operator that is secretly a function (or vice versa), a UI property that does
> not behave, or an FFI marshalling surprise, RECORD IT HERE IMMEDIATELY: the symptom you saw, the root
> cause, and the fix. Where the trap is statically detectable, also add it to the static gate (a new
> reserved word to the checker's `RESERVED` set, or a new check). The value of this file is proportional
> to how faithfully it is updated. A lesson learned and not written down will be paid for again.
>
> **Master/copy convention (since 2026-08-15).** This template is itself a carried family document:
> byte-identical copies live in every suite member that ships it (today
> `onionxt/templates/CLAUDE.md` and `coinxt/templates/CLAUDE.md`), and the suite gate
> `tools/check-checker-drift.py` FAILS the build if the copies differ. Edit one copy and copy it
> byte-identically to the others in the same change; never patch one copy alone.
> **Last synced to the family's lessons: 2026-08-15.**

House style: no em-dashes (use hyphens, commas, colons, parentheses). ASCII only in `.lcb` /
`.livecodescript`, even in comments and strings. Comment the *why*, densely; match the surrounding
style.

---

## 1. The toolchain reality (read this first)

- **There is no headless way to compile or run `.lcb` / `.livecodescript`.** OXT/LiveCode is a GUI
  runtime. You cannot prove a script compiles from the command line. So the honest status of any script
  change you have not run on the engine is exactly: **"designed and statically reasoned; needs an
  on-engine pass."** Say that. Do NOT claim a handler "works" until it has actually run on a real engine.
- **Shipped is not run, and an unexecuted line is not evidence - in either direction.** Never cite
  shipped-but-unrun code as precedent ("the sibling ships this spelling, so the engine must accept it"
  is circular when the sibling's copy has never run on an engine), and never trust a comment's claim
  about engine behaviour that no test has ever exercised. The canonical recurrence is riptide's
  textDecode failure: six shipped parsers carried the comment "textDecode throws on malformed UTF-8",
  it does not (see the gotcha log), and the first inputs that ever touched the path found it. An
  attestation is only worth keeping once it becomes a COMMITTED FIXTURE that runs in the gate set
  (the checker's fixtures in `tools/test-checker.py` are this rule applied to the checker itself).
- **The static gate is the only automated safety net the script layer gets.** Run it on every change
  (`tools/check-livecodescript.py`, section 3). It catches a specific, growing set of traps that the
  engine would otherwise punish with a compile error or, worse, silent misbehaviour. Passing it is
  necessary, never sufficient.
- **A whole `.livecodescript` compiles as one unit.** A syntax error in one handler breaks the WHOLE
  script, and the engine often reports it at the first line it tries to run, NOT at the real error. When
  "it broke" at a line that looks fine, suspect a compile error elsewhere in the same script and re-run
  the static gate.
- **Version skew wastes hours.** When the user reports an error at a line number that does not match your
  copy, you are looking at different versions of the file (an unmerged branch, an old paste, a stale
  checkout). Reconcile the exact bytes before debugging the symptom.

## 2. Golden rules

1. **Default to script; reach for native (LCB/C) last.** The engine already has sockets, files,
   processes, string/binary ops, and a full UI. Only add an LCB or C helper for a narrow pure-compute job
   that script genuinely does badly (fast binary framing, a hash, a big-integer step), and only after an
   on-engine pass shows script is too slow or too awkward. Every native line adds a build matrix, an ABI
   surface, and a bundling problem.
2. **Compose, do not reinvent.** If a sibling library already does the crypto / physics / codec, call it
   (section 10). Add no cryptography of your own, ever.
3. **Comment the WHY, densely.** The engine's idioms are subtle; a comment that says what the byte
   sequence IS, or why this is a command and not a function, saves the next reader an on-engine cycle.
4. **Fail closed.** A wire error, a short read, a closed socket, a non-zero reply code, a missing
   capability: return cleanly to the caller and tear the resource down. Never fall back silently to an
   unsafe path.
5. **Own the lifecycle.** There is no deterministic unload hook. Everything you open (socket, file,
   process, service, listener, handle) gets an explicit, idempotent close, and the app frees what it
   opened (for example on `closeStack`). Make every teardown safe to call twice.

## 3. House style and the static gate

**Run this on every script change** (it is the only automated safety net):
```sh
python3 tools/check-livecodescript.py
```
**The checker is ONE unified tool, kept byte-identical in every member of the suite.** The family
learned this the expensive way: the per-member copies drifted into two independent implementations,
each with real checks the other lacked (one copy did not know `switch`, reported phantom imbalances
in dispatchers, and would have hidden a real one). The copies are unified now; the suite gate
`tools/check-checker-drift.py` FAILS the build if any copy's bytes differ, and
`tools/test-checker.py` fixture-tests every rule in every copy. **To adopt it, copy any member's
CURRENT copy TOGETHER WITH `tools/test-checker.py` and its fixtures** - the fixtures are what keep a
rule honest when you extend it (an attestation must become a committed fixture, section 1).

Its twelve check families, and the engine lesson each encodes:

1. **ASCII only.** Smart/curly quotes (U+2018/2019/201C/201D) fail OXT compilation outright; en/em
   dashes break house style; any other non-ASCII byte is reported, and a non-UTF-8 file is refused.
2. **Unterminated strings and `/*` block comments** (lexer-level).
3. **Balanced blocks, matched by kind and dialect** - handler / `if` / `repeat` (plus `unsafe` in
   `.lcb`; `switch` / `try` in `.livecodescript`), and an LCB `library`/`module`/`widget` closed by
   its matching `end`, with line numbers. A single-line `if X then <do>` opens NO block; a stray or
   missing `end` mis-scopes everything after it.
4. **Constants declared before first use, BOTH dialects** - OXT resolves a constant by lexical
   position; a forward reference silently evaluates to nothing. The WRONG dialect's constant
   spelling (`constant k is ...` in `.livecodescript`, `constant k = ...` in `.lcb`) is refused
   outright, because a mis-spelled declaration is INVISIBLE to the before-use check - a fail-open
   in the gate itself, found 2026-08-13 (see the gotcha log).
5. **Declarations at the top of a handler, `.lcb` ONLY** - a nested `variable` has broken whole-LCB
   compilation. Deliberately NOT enforced for `.livecodescript`, where mid-handler `local` is legal
   and stands in engine-passed code; there the top-of-handler habit is a style convention.
6. **The prefixed-token-shadow trap** (section 4) - a `t/p/s/k`-prefixed name whose full spelling
   lowercases to a reserved token (the classic `tExt` == `text`, `tOp` == `top`). Both dialects.
7. **`does not begin/end with` / `does not contain`** - not xTalk; the parser errors on `does`.
8. **A zero-argument call written `foo()` in STATEMENT position** (`.livecodescript` only; LCB
   allows it) - see section 5 item 9.
9. **Engine-hostile constructs that COMPILE and silently do the wrong thing** (`.livecodescript`
   only): `repeat with ... step N` and `throw` inside a `catch` block - see section 5 items 10-11.
10. **LCB-only checks:** a foreign type used without `use com.livecode.foreign`; `textEncode` /
    `textDecode` inside a module (they are livecodescript-only); `the empty list` / `the empty
    array` (LCB wants the literals `[]` / `{}`); an all-lowercase `variable` name.
11. **LCS-only checks:** braces (LCB array literals leaking into script) and subscripting a
    function result (`f(x)["k"]` does not parse).
12. **`put X into Y after Z`** malformation (a `put` takes `into` OR `after`/`before`, never both).

It is a lexer-level checker, not a compiler: it errs toward NOT raising false positives, so passing
it is necessary, never sufficient.

A prose gate (`tools/check-docs-style.py`) enforces the same no-dash / no-curly-quote rule on `.md`.

**"Done" means:** the static gate passes AND the change has had (or is clearly flagged as needing) an
on-engine pass. Keep both gates green in CI on every push / PR.

## 4. Naming and the prefixed-token-shadow trap

- **Prefix conventions:** `t` = handler-local, `p` = parameter, `s` = script/module-local, `k` =
  constant. Public API is `<stem>PascalCase`; a C ABI (if any) is `<stem>_snake_case`. Choose a short
  public stem that is NOT a reserved word and does not read as the framework name.
- **The trap:** a prefixed name whose full spelling IS a reserved token gets parsed as the KEYWORD, not
  your variable. `tExt` is literally `text`; `tOp` is literally `top` (an object property); `tItem` is
  `item`. It compiles and silently misbehaves. The static checker flags any `t/p/s/k`-initial name that
  lowercases to a known reserved token - but the reserved set is only as complete as you have made it.
  When the engine surprises you with one, ADD IT to the checker's `RESERVED` set (only ATOMIC short
  tokens: `top`, `time`, `size`, `style`, `stack`, `scroll`, `point`, `script`, ...; not compound
  property names like `textFont`, which are legitimately CamelCase when you set the property) - in
  EVERY member's copy, with a fixture in `tools/test-checker.py`; the drift gate holds the copies
  byte-identical (section 3).
- **Watch reserved COMMANDS too:** `tSend` shadows `send`; use `tSender`. `tSort` shadows `sort`.

## 5. livecodescript language gotchas

1. **No smart/curly quotes anywhere**, even in a comment or string: they fail OXT compilation. ASCII only.
2. **Single-line vs block `if`.** `if C then return X` (statement after `then`) is a complete single-line
   statement and opens NO block - do not add `end if`. Chaining single-line branches
   (`if ... then return` / `else if ... then return` / `end if`) confuses both the static gate and some
   engine parsers; prefer the multi-line BLOCK form with the body on its own line:
   ```
   if C then
      return X
   else if D then
      return Y
   end if
   ```
   And the DANGLING-ELSE trap: a single-line `if C then <stmt>` may legally take an `else`, so a
   BARE `else` on the next line (nothing after it) binds to that single-line `if`; its `end if` then
   closes the WRONG block, the outer `if` stays open, and OXT reports "missing end if" at the
   handler's end, far from the cause. Chains with the statement ON the else line
   (`if c then s1` / `else s2`) are fine. GATE status, honestly: the unified checker treats a bare
   `else` as a continuation and does NOT flag this; the only tool that currently does is holde-em's
   member idiom gate (`holde-em/tools/check-holdem-idioms.py`). Until that check is ported into the
   unified checker, the multi-line block form above is your defence.
3. **`does not` is not a valid construction.** There is no `does not end with` / `does not contain`.
   Negate the whole comparison: `not (tHost ends with ".onion")`, `not (x is in y)`.
4. **`is a <type>` accepts only** number / integer / boolean / point / rect / date / color. There is NO
   `is a string`. To sniff bytes or text, check length / content, not a type.
5. **`itemDelimiter` / `lineDelimiter` are global mutable state.** Set them immediately before the parse
   that needs them and RESTORE them afterward, because other code assumes the defaults (`item` = comma,
   `line` = lf). CRLF protocols: `set the lineDelimiter to crlf` right where you parse, then restore.
6. **The empty string `is in` every string** (and is a prefix/suffix of every string). Guard any
   trim/scan loop with an explicit non-empty check, or it never terminates / over-matches.
7. **Constants must be literal and declared before first use** (see section 3). **The same
   lexical-position rule applies to script-level `local`s**, and it fails far more quietly:
   an out-of-scope name is not an error, LiveCodeScript evaluates it to the LITERAL TEXT of
   its own name. So a handler above the declaration reads the string `"sPassed"`, everything
   keeps running, and the first arithmetic on it dies somewhere else entirely
   (`add: error in source expression`). Declare every script-level name ABOVE every handler,
   and be careful when CONCATENATING two files: each may be correct alone and wrong joined,
   because file A's handlers now sit above file B's declarations. Cost an OXT session in
   2026-08-09, in a generated harness where 106 declarations had landed below the first
   handler. A checker that proves a name is DECLARED does not prove it is IN SCOPE.
8. **Commands report via `the result`; functions return a value.** Pick ONE API shape per operation and
   hold it: a command that must both signal success/failure and yield a handle returns the handle through
   `the result` on success and an error STRING on failure (so callers test `the result is an integer`);
   a pure query is a function that returns its value. Do not mix. And treat `the result` as
   IMMEDIATELY perishable: it is consumed by the NEXT command, so capture it into a local on the
   very next line after any command whose result you need, before calling anything else - several
   past family bugs were a stale `the result` read after an intervening call (the box2dxt lesson).
9. **A ZERO-ARGUMENT call in STATEMENT position must be written BARE.** `dcCleanup` yes,
   `dcCleanup()` no. A statement that starts with an identifier is parsed as a COMMAND and what
   follows is its argument list, so the parenthesised spelling hands the command the expression
   `()` - and `()` is not an expression. It is a compile error, and since a whole
   `.livecodescript` compiles as one unit it takes the ENTIRE FILE with it (section 1),
   usually reported at some unrelated line. Three traps around it, all of them real:
   - **One argument is FINE.** `dcFreePeer(sPeerA)` compiles, because `(sPeerA)` IS an
     expression. So the broken line looks identical in shape to the working line beside it -
     one shipped example had `dcStopPolling` and `dcCleanup()` on CONSECUTIVE lines.
   - **In EXPRESSION position the parens are REQUIRED.** `if dcCleanup() is 0 then` is correct.
     Same characters, opposite verdict, decided entirely by what is to the left.
   - **LiveCode BUILDER allows it.** `sPrepare()` as a bare statement is valid `.lcb` and appears
     ~90 times across two engine-verified modules in this family. `.lcb` and `.livecodescript`
     are different languages; do not carry the idiom across.
   Cost an OXT session in 2026-08-09. Every member's `check-livecodescript.py` now refuses it,
   `.livecodescript` only.
10. **`throw` from INSIDE a `catch` block does not reach the caller.** The handler falls
   through to whatever follows the `try` and returns its result variable, which is
   usually EMPTY - so a guard that catches, cleans up, and re-throws silently converts
   "this input is invalid" into "here is an empty answer". Capture the error into a
   local, close the try, and throw AFTER `end try`:
   `put false into tFailed` / `catch tError` -> `put true into tFailed` +
   `put tError into tFailure` / after `end try`: `if tFailed then throw tFailure`.
   **`return` inside a catch is FINE** and is engine-proven (onionxt's
   `oxSodiumHasSha3`); do not over-generalise this into "avoid catch". Cost a
   money-library fail-open on 2026-08-09: nine itemDelimiter guards did it, and one of
   them was a mnemonic validator whose Inner reaches `return false` only via its catch,
   so an invalid seed phrase was reported VALID. The holde-em fold (2026-08-15) found a
   recurrence in that member's deck-derivation path. GATE: every checker copy refuses a
   `throw` inside a `catch` (`.livecodescript` only; docstring check 9); `return` inside
   a catch stays legal.
11. **`repeat with i = A to B step N` does not honour the increment.** i walks one at a
   time. Use `repeat while` with an explicit `add N to i`. Found the same day it cost a
   money library: a hex decoder rejected valid input with its own "not a hex digit"
   error, i.e. the library blaming the caller's data. And it was NOT a one-off, however
   rare it first looked: the box2dxt fold (2026-08-14) found 29 more `step` loops in
   that one member (every tile loop would have walked 1px at a time, placing 64x the
   tiles), and the holde-em fold (2026-08-15) found one in its DEAL path (a seed-XOR
   walking hex pairs with `step 2` would have XORed overlapping pairs into a
   wrong-but-internally-consistent deck). Assume any `step` loop you meet is broken.
   GATE: every checker copy refuses `repeat with ... step` (`.livecodescript` only;
   docstring check 9).
12. **Socket / control ids are the engine's, not yours.** `open socket to host` and `accept connections`
   name sockets by their `host:port` string (with a numeric or `|`-suffix for multiples). Store the EXACT
   id the engine hands you and use it verbatim in `read` / `write` / `close`; never reconstruct it.

## 6. Operators that look like functions (and vice versa)

This category causes "double binary operator" / "bad expression" compile errors that read as nonsense.

- **`bitAnd` / `bitOr` / `bitXor` / `bitNot` are OPERATORS, not functions.** Write `x bitAnd y`, NOT
  `bitAnd(x, y)`. (This bites the ed25519 scalar clamp and any bit-twiddling.)
- **`div` and `mod` are OPERATORS** (`x div y`, `x mod y`). Some OXT parsers additionally choke on them
  inside a larger compound expression; when in doubt, factor the division/modulo into its own statement
  or a tiny helper.
- **`^` (power) is rejected by some OXT parsers inside a compound expression** ("double binary
  operator"). Factor it out into its own statement or a helper (for example a `pow2(n)` function) rather
  than embedding `2 ^ n` in a bigger expression.
- **`binaryEncode` / `binaryDecode` are FUNCTIONS that FILL an output variable and RETURN a count.**
  `binaryDecode` does not return the decoded value: `get binaryDecode("H*", pData, tHex)` then read
  `tHex`. Using it as if it returned the value silently gives you the count.
- **`numToByte` / `byteToNum`** for a single binary byte; **`numToChar` / `charToNum`** for a codepoint.
  Keep them straight: on a binary path you want the byte pair.

When an arithmetic or bitwise line fails to compile for no visible reason, suspect this section first:
break the expression into single-operator statements and it usually compiles.

## 7. Binary vs text discipline

- **`byte`, not `char` / `line` / `word`, on binary data.** `char` / `line` / `word` are Unicode- and
  delimiter-aware and WILL mangle bytes. Build with `numToByte` / `binaryEncode`, parse with `byteToNum`
  / `binaryDecode`, index with `byte x to y of`. Keep `the useUnicode` and encoding assumptions entirely
  out of the binary path.
- **Frame every message by length.** A socket read can return SHORT. Reassemble until you have exactly
  the number of bytes the protocol says the next field is. For line protocols, read until the delimiter
  and remember any "more lines follow" vs "last line" convention.
- **`textEncode` / `textDecode` are livecodescript-only** (NOT available inside an LCB module). Convert
  text<->Data in the script layer; pass `Data` across the FFI boundary.

## 8. The asynchronous, single-thread, event-driven model

The engine runs script, the FFI, and rendering on ONE interpreted thread, and the outside world does not
wait for it.

- **Never block the interpreter thread on I/O.** A socket connect, read, accept, a process, a long
  compute: drive each as a STATE MACHINE via `open socket ... with message`,
  `read from socket ... with message`, `accept connections on port ... with message`. Do not busy-wait;
  do not `wait ... with messages` in a loop where a callback would do.
- **`open socket` and `accept` are asynchronous, and failures arrive as MESSAGES, not thrown errors.** A
  connection failure calls `socketError <id>, <errorString>`; a clean close calls `socketClosed <id>`; a
  stalled handshake calls `socketTimeout <id>` (which REPEATS every interval while a read/write is
  pending, so it is only fatal during a handshake). Wire ALL of them. Treat a peer that vanishes
  mid-handshake as an ordinary path, not a crash.
- **Set a timeout around every handshake** (`the socketTimeoutInterval` or an explicit timer). A server
  that accepts the TCP connection and then stalls is common. On timeout, close and surface a clean error.
- **Quote the callback message name:** `... with message "onData"` and `send "handler" to ...`. Match the
  handler's parameter arity to what the engine/dispatcher passes.
- **Coalesce UI updates to <= ~4 Hz.** High-frequency events (progress, streaming bytes) should update a
  field at a throttled rate, not on every event.
- **Loopback only for local services.** Bind local listeners and connect local helpers on `127.0.0.1`;
  never `0.0.0.0` or a routable interface, unless the design explicitly requires it.

## 9. Callbacks, dispatch, and the message path

- **`dispatch` semantics:** `dispatch [function] "name" to <target> with a, b, c` sets `it` to
  `"handled"` / `"unhandled"` / `"passed"`, and puts the handler's RETURN VALUE in `the result`. Use `it`
  to detect an absent handler and `the result` for the value.
- **PRIVATE handlers are UNREACHABLE via the message path.** A handler invoked through `with message`,
  `send`, or `dispatch` (every socket callback, timer callback, and app callback) MUST be public. A
  `private command`/`private function` used as a callback silently never fires. (Paid for on-engine.)
- **Set an explicit callback owner** (`the long id of me`) rather than relying on `the topStack`, which is
  usually but not always the app's stack.
- **Late binding is a feature.** Calling a handler that is not loaded raises a CATCHABLE execution error
  (or `dispatch` reports `"unhandled"`). Lean on this for capability-gating (section 10).

## 10. Composition and capability-gating

- **Call a composed library's primitive DIRECTLY, wrapped in `try/catch`.** If the primitive is absent
  (the sibling library is not loaded, or is an older ABI), the call raises a catchable error; degrade to
  a clear `"needs <lib> <fn>"` message or a safe fallback. This is cleaner than `dispatch function`,
  whose `it` / `the result` semantics around a missing handler are murky. Return the value unambiguously.
  ```
  local tOut
  try
     put sxSomePrimitive(pIn) into tOut
  catch tErr
     return "MyLib: needs SodiumXT sxSomePrimitive (requires ABI >= N)"
  end try
  ```
- **Probe capabilities with tiny benign calls** and advertise them (a `...Info` function returning a
  flags array), so a caller can negotiate and fall back VISIBLY rather than silently.
- **Require a minimum ABI** for the paths that need it, and say so in the README and docs. Split work that
  needs a new upstream primitive: the upstream library ships the primitive first (with its own ABI bump
  and tests), then you compose it.

## 11. Building the UI in script (no IDE design step)

Family demos build the entire UI in `preOpenStack` so no manual IDE work is needed - but since
2026-08-14 a demo does NOT start from scratch. **The family look is ONE carried kit:**
`tools/ui-kit.livecodescript` at the suite root (v2, the "card look": chrome with a semantic status
line, white rounded panels on a cool page, mono data surfaces, the honesty footer). An adopting
stack embeds the kit block VERBATIM between its marker lines, so every demo stays a single
paste-and-run file, and the suite gate `tools/check-ui-kit-drift.py` holds every copy
byte-identical, refuses unregistered carriers, and refuses any window-building stack that neither
adopts the kit nor carries a written exemption - "every demo is a kit adopter" is a property of the
tree, not of one cleanup pass. A look change edits the MASTER and re-carries; it is never patched
inside an adopter. Start a new demo from the master (a standalone adopter copies the master file,
and ideally that gate with it). The traps below are the WHY behind how the kit is built, and they
still apply to any control you create beside it:

- **There is NO reparenting.** LiveCode has no `set the owner` to move a control into a group. Create
  controls on the card (`create field "x"`, `create button "y"`, `create graphic "z"`), track each
  logical group's membership in a script-local table, and SHOW/HIDE by name to switch "tabs" / panels.
- **`set the textFont` reads a comma as `fontname,language`** (a Unicode language tag), NOT a CSS-style
  fallback list. `"Courier New,Courier,monospace"` is misparsed. Use a SINGLE font name (`"Courier"` is
  the portable monospace).
- **`set the opaque of field to true`** to make its `backgroundColor` actually fill; a non-opaque field
  shows whatever is behind it, so a set backgroundColor appears to do nothing.
- **Auto-scroll a growing log field:** `set the scroll of field "log" to the formattedHeight of field
  "log"` (the formattedHeight is the full content height; the engine clamps to the max).
- **`set the enabled of <control> to <boolean>`** greys a control AND stops it receiving mouse messages -
  ideal for gating a flow (a disabled button that cannot be clicked tells the user what is not yet valid).
- **Reference any control generically with `control "name"`** - it resolves across types (button / field
  / graphic), which is what you want when toggling a mixed group's visibility.
- **A single `mouseUp` router + a "prefix:role" naming scheme** dispatches every click: parse
  `the short name of the target`, split on the delimiter, route by prefix. Disabled controls never reach
  it.
- These object-creation calls (`create ...`, `set the <prop> ...`, show/hide, scroll, enable) still need
  an on-engine pass exactly like the rest of the script.

## 12. FFI / C-ABI conventions (apply ONLY if you add a native shim)

The single most expensive thing the family has learned. Change nothing here without a very good reason.

- **Byte buffers cross as `Pointer` + `CInt` length. An LCB `Data` does NOT auto-bridge to `void*`** (it
  marshals as an opaque `MCDataRef`). An OUT buffer is a raw block from the engine `<builtin>`
  `MCMemoryAllocate`, passed as a real `Pointer`; the shim returns bytes-written, or `-needed` (negative
  required size) when the block is too small, and the LCB layer reallocates, retries, and copies back with
  `MCDataCreateWithBytes`. An IN buffer passes `MCDataGetBytePtr(theData)` plus its length.
- **`MCMemoryAllocate`'s size is C `size_t`, so it marshals as `UIntSize`, NOT `CUInt`.** A 4-byte int
  into an 8-byte size slot on a 64-bit build corrupts the heap.
- **There is no 64-bit foreign int.** Values that can exceed 2^31 cross as decimal `ZStringUTF8` strings,
  parsed in the shim. **Reals cross as `double`, booleans as `int` (0/1).**
- **Never RETURN a bridged C string** (`ZStringUTF8` / `NativeCString`) from a foreign handler: the engine
  adopts the returned pointer and later `free()`s it, so a static or library-owned return is
  free()-on-static, heap corruption on the first call. Fill a caller buffer and return length / `-needed`.
- **Pass a null pointer only through an `optional Pointer`** parameter; a plain `Pointer` rejects
  `nothing`.
- **Exported C ABI symbols keep a stable prefix and are never renamed once shipped** (the `.lcb`
  `binds to` strings reference them by name; a rename is a silent bind failure at load). `<builtin>`
  handlers resolve by name, so no leading underscore.
- **Bump the ABI version on any ABI change**, and have the `.lcb` `checkABI()` throw a clear "reinstall
  the extension" error on skew rather than corrupt memory on first use. Expose every length constant from
  the shim as a FUNCTION; never hardcode a size in LCB.
- **`unsafe ... end unsafe` brackets every foreign call**, and keep all `local` declarations at the TOP of
  the handler (a nested `local` has broken whole-script compilation).
- **`use com.livecode.foreign`** whenever a foreign type is named, or it will not be declared at compile.

## 13. Handles and long-lived state

- **Script-side state is the norm.** Track open resources in script-local tables keyed by a small integer
  or the engine's id. A stale, closed, or unknown id must be a CLEAN no-op / error, never a crash.
  Provide an explicit, idempotent free for each, and free-what-you-open (no deterministic unload hook),
  for example on `closeStack`.
- **If state ever moves into a C shim,** use a generation-tagged handle table: positive 32-bit ints, `0`
  invalid, a stale or recycled handle a clean error, an explicit idempotent free. Do not round-trip a raw
  pointer or an opaque struct through script.

## 14. Testing and conformance

- **Pin pure-compute paths with known-answer vectors (KATs) in a portable language** (Python is the family
  choice). VERIFY every vector INDEPENDENTLY (against a reference implementation / stdlib) BEFORE pinning
  it, so the KAT proves the script, not the other way around.
- **Write the negative paths first** - bad input, a stalled peer, a wrong credential, a double close, a
  vanished mid-handshake peer. These are the security- and robustness-relevant tests.
- **Ship a demo and a pure offline self-test harness - and start the harness from the ONE carried
  scaffold**, `tools/harness-scaffold.livecodescript` at the suite root: the selftest window, the
  pass/fail/skip counters, and the assertion plumbing (a Copy-results button, SKIP as a first-class
  outcome so a capability-gated section skips rather than fails when an optional dependency is
  absent, per-line result paint, per-section failure isolation), carried byte-identical into every
  family harness and held there by `tools/check-harness-scaffold-drift.py`. Harnesses are
  deliberately NOT ui-kit adopters (a second 300-line block would bloat every paste); the scaffold
  matches the kit's look BY VALUE, and the kit gate's exemption list records exactly that. Wire
  behaviour that needs a live peer can only be integration-tested on the engine; say so.
- **Measure whether the harness actually CALLS every public handler.** "The generated file is
  current" and "the assembly is structurally sound" are gates that stay green about a harness that
  never touches the new code, and nobody re-asks "is this thorough?" of a harness thousands of
  lines long. When the family first measured reach, 31 public handlers had never been called -
  including the single child-key-derivation step a whole HD-wallet layer loops over. A handler the
  harness genuinely cannot reach (an engine-minted socket callback id, a live daemon) gets a
  WRITTEN per-handler exemption with its reason, and the coverage gate fails both on a new
  unexercised handler and on a stale excuse, so a renamed handler cannot leave a permanent
  exemption behind. It is a floor, not a ceiling: "called by name" is not "tested well".
- **A gate must report the honest checked-vs-input split, never a parsed count.** A vector gate
  that printed "66 harness constants re-derived" was counting the constants it had PARSED, not the
  ones it had CHECKED; two constants added in the very change that found this sailed through it. A
  gate that overstates its coverage is worse than no gate, because it answers the question nobody
  asks twice. Fail on anything neither checked nor listed as an input with a written reason, and
  print the honest split.

## 15. Git and workflow

- **Develop on a per-task branch** (for example `claude/...`); commit there and open a DRAFT PR if none
  exists. Do NOT push to `main` without explicit permission.
- **A script change is "done"** once the static gate passes AND it has had (or is clearly flagged as
  needing) an on-engine pass. A feature is "done" once its end-to-end round trip runs on the engine.
- **A change touching a C shim** bumps its ABI version and `checkABI()` in the SAME change; if it bundles
  a native binary, it refreshes the committed binary and a `MANIFEST.sha256` in the same change.
- **A change needing a new upstream primitive is split:** the upstream library lands the primitive first
  (own ABI bump + tests), then this project composes it.
- **No em-dashes** in committed prose or code comments (house style). Match the surrounding comment
  density and idiom.

## 16. The living-gotcha log (APPEND as you learn)

Record every new engine surprise here the moment you confirm it on the engine, in this shape:

```
- SYMPTOM: what you saw (the exact error text or the wrong behaviour).
  CAUSE:   why the engine did that.
  FIX:     the correct idiom, with a one-line example.
  GATE:    (if statically detectable) the checker rule / reserved word you added.
```

Seed entries (confirmed on-engine in the family; keep them, add to them):

- SYMPTOM: "tOp is a synonym for top" compile error on a variable named `tOp`.
  CAUSE:   `tOp` lowercases to `top`, an object property; the engine parsed the keyword.
  FIX:     rename the stem (`tReplyOp`). GATE: `top` is in the checker's `RESERVED` set.
- SYMPTOM: "double binary operator" on a line using `bitAnd(x, y)` or `2 ^ n` in a compound expression.
  CAUSE:   `bitAnd`/`bitOr` are OPERATORS not functions; `^` is rejected inside a compound expression.
  FIX:     `x bitAnd y`; factor `^` into a `pow2(n)` helper or its own statement.
- SYMPTOM: `binaryDecode(...)` "returned" a number instead of the decoded bytes.
  CAUSE:   `binaryDecode` is a function that FILLS an output var and returns a COUNT.
  FIX:     `get binaryDecode("H*", pData, tHex)` then use `tHex`.
- SYMPTOM: "bad expression" on `accept connections on <port> with message onPeer`.
  CAUSE:   missing `port` keyword and unquoted message name.
  FIX:     `accept connections on port pLocalPort with message "onPeer"`.
- SYMPTOM: a socket / app callback handler silently never fires.
  CAUSE:   it was `private`; private handlers are unreachable via the message path.
  FIX:     make every `with message` / `send` / `dispatch` target a PUBLIC handler.
- SYMPTOM: a monospace field renders in the default proportional font.
  CAUSE:   `set the textFont` read the comma-list as `fontname,language`.
  FIX:     use a single font name, e.g. `"Courier"`.
- SYMPTOM: a field's set `backgroundColor` appears to do nothing.
  CAUSE:   the field was not opaque.
  FIX:     `set the opaque of field "x" to true`.
- SYMPTOM: a refused local connection surfaces as "Error 10061 on socket" (Windows).
  CAUSE:   `WSAECONNREFUSED` - nothing is listening on that port.
  FIX:     it is an environment issue (service not running / wrong port), handled by the `socketError`
           path; surface it cleanly, do not treat it as a crash.
- SYMPTOM: a compile-time "bad factor" error on a line reading `the detailedFiles`.
  CAUSE:   OXT does not accept `the detailedFiles` as a factor (a LiveCode/OXT divergence).
  FIX:     use `the files` (and `the folders`) and fetch any per-file detail separately.
- SYMPTOM: a local listener "works" (no error raised) but every connection to it dies; with an onion
           service in front, every visit returns an empty response.
  CAUSE:   `accept connections on port N` failed to bind (Windows 10013 WSAEACCES: a reserved port
           range under Hyper-V/WSL2/Docker; 10048 WSAEADDRINUSE: already in use) and reported it ONLY
           via `the result`, which was never checked.
  FIX:     check `the result` immediately after `accept connections` and fail closed; surface the
           error so the user can pick another local port.
- SYMPTOM: a line parsed from `read from socket ... until crlf` fails equality/suffix comparisons
           that look obviously correct.
  CAUSE:   the engine returns the trailing delimiter WITH the data.
  FIX:     strip the line ending before parsing (a tiny shared helper, e.g. `stripLineEnd`).
- SYMPTOM: uncertainty whether a no-quantifier `read from socket s with message` waits for EOF.
  CAUSE:   confirmed on-engine: it streams whatever bytes are available, chunk by chunk, as they
           arrive; it does NOT block until the peer closes.
  FIX:     treat it as a streaming read and reassemble/frame by length or delimiter yourself.
- SYMPTOM: a validator that must refuse a string ENDING with the delimiter accepts it instead - a
           fail-open, because the per-chunk check inside the loop never runs for the empty last chunk.
  CAUSE:   confirmed on-engine (2026-08-10): the engine ignores ONE trailing delimiter when it counts
           chunks - "m," is one item ("a,," is two), "a\n" is one line - so a split-then-iterate never
           sees a trailing empty. A headless model that counts with a bare split() sees one MORE chunk
           than the engine and reports the very check that never runs as passing.
  FIX:     refuse a trailing separator explicitly, BEFORE splitting, while it is still visible; and
           make any interpreter/model of chunk counting copy the engine's rule, not the language the
           model is written in.
- SYMPTOM: constants written `constant kFoo is 1` in a `.livecodescript` fail to compile on the
  engine, in a file every static gate passed.
  CAUSE:   `is` is the LiveCode BUILDER constant spelling; LiveCode SCRIPT declares
           `constant kFoo = 1`. Editing the two dialects side by side makes the slip natural (it
           has happened repeatedly), and the checker's constants-before-use rule only RECOGNIZED
           the correct spelling per dialect - so the wrong form was not flagged, it was invisible
           to the rule that should have caught its consequences: a fail-open in the gate itself.
  FIX:     write `=` in `.livecodescript` and `is` in `.lcb`. All checker copies now refuse the
           wrong dialect's spelling in BOTH directions (fixture-tested in tools/test-checker.py),
           so the slip is a gate failure instead of an engine discovery.
- SYMPTOM: a parser that wraps textDecode(tBytes, "UTF-8") in try/catch accepts malformed UTF-8
           anyway, handing back mangled text where it meant to refuse; the catch never runs.
  CAUSE:   confirmed on-engine (2026-08-15): textDecode(..., "UTF-8") on OXT is LOSSY and never
           throws - invalid bytes decode to replacement characters and the call returns a
           non-empty string, so every try guard around a decode is inert. Six shipped parsers
           carried the comment "textDecode throws on malformed UTF-8"; no test had ever fed the
           path malformed bytes, so the attestation was unexercised and wrong (shipped is not
           run, section 1).
  FIX:     validate by ROUND TRIP - decode, re-encode with textEncode, and require the bytes to
           reproduce exactly (only valid UTF-8 does); keep an inner try as belt-and-suspenders
           for any engine that does throw (riptide's rsBytesAreUtf8 is the family reference).
           Never trust a decode to throw.
  GATE:    none in the static checker today; the round-trip helper plus a malformed-bytes test
           per parser is the defence.
