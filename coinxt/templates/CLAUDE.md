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

House style: no em-dashes (use hyphens, commas, colons, parentheses). ASCII only in `.lcb` /
`.livecodescript`, even in comments and strings. Comment the *why*, densely; match the surrounding
style.

---

## 1. The toolchain reality (read this first)

- **There is no headless way to compile or run `.lcb` / `.livecodescript`.** OXT/LiveCode is a GUI
  runtime. You cannot prove a script compiles from the command line. So the honest status of any script
  change you have not run on the engine is exactly: **"designed and statically reasoned; needs an
  on-engine pass."** Say that. Do NOT claim a handler "works" until it has actually run on a real engine.
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
It checks every `.lcb` / `.livecodescript` for:
- **smart/curly quotes** (U+2018/2019/201C/201D) and **em/en dashes** - the quotes FAIL OXT compilation;
  ASCII `"` and `'` only.
- **block balance** - handler / `if` / `repeat` / `unsafe` / `try` (and `library`/`module`/`widget`) each
  open a block that must be closed by the matching `end`. A single-line `if X then <do>` does NOT open a
  block; only `if X then` with nothing after `then` does. A stray or missing `end` mis-scopes everything
  after it.
- **constants declared before first use** - OXT resolves a constant by lexical position; a forward
  reference silently evaluates to `nothing`.
- **the prefixed-token-shadow trap** - a `t/p/s/k`-prefixed name whose full spelling lowercases to a
  reserved token (the classic `tExt` == `text`, `tOp` == `top`).
- **`put ... into ... after`** malformation (a `put` takes `into` OR `after`/`before`, never both).
- (`.lcb` only) missing `use com.livecode.foreign` when a foreign type is used, and `textEncode` /
  `textDecode` used inside an LCB module (they are livecodescript-only).

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
  property names like `textFont`, which are legitimately CamelCase when you set the property).
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
3. **`does not` is not a valid construction.** There is no `does not end with` / `does not contain`.
   Negate the whole comparison: `not (tHost ends with ".onion")`, `not (x is in y)`.
4. **`is a <type>` accepts only** number / integer / boolean / point / rect / date / color. There is NO
   `is a string`. To sniff bytes or text, check length / content, not a type.
5. **`itemDelimiter` / `lineDelimiter` are global mutable state.** Set them immediately before the parse
   that needs them and RESTORE them afterward, because other code assumes the defaults (`item` = comma,
   `line` = lf). CRLF protocols: `set the lineDelimiter to crlf` right where you parse, then restore.
6. **The empty string `is in` every string** (and is a prefix/suffix of every string). Guard any
   trim/scan loop with an explicit non-empty check, or it never terminates / over-matches.
7. **Constants must be literal and declared before first use** (see section 3).
8. **Commands report via `the result`; functions return a value.** Pick ONE API shape per operation and
   hold it: a command that must both signal success/failure and yield a handle returns the handle through
   `the result` on success and an error STRING on failure (so callers test `the result is an integer`);
   a pure query is a function that returns its value. Do not mix.
9. **Socket / control ids are the engine's, not yours.** `open socket to host` and `accept connections`
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

Family demos build the entire UI in `preOpenStack` so no manual IDE work is needed. The traps:

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
- **Ship a demo and a pure offline self-test harness**, formatted like the family (a `sPass`/`sFail`
  counter, KAT sections, capability-gated sections that SKIP rather than FAIL when an optional dependency
  is absent). Wire behaviour that needs a live peer can only be integration-tested on the engine; say so.

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
