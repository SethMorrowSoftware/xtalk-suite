# Native binding playbook

How to wrap a native C/C++ library for OpenXTalk (OXT) the way this suite's
native members do; every item was paid for by one of them. Engine behaviour is
`docs/OXT-ENGINE-NOTES.md` (cited here by note number), the cross-member rules
are the root `CLAUDE.md`, and each member's `CLAUDE.md` is its as-built record.
Until 2026-09-23 this was Part I of docs/NEXT-EXTENSIONS-PLAN.md; its executed
Parts II-V (II libsodium, III ENet, IV libdatachannel, V sequencing and risk),
cited by part number in enetxt and datachannelxt source comments, are in git
history, and their lessons are sections 11-13.

## 1. The house pattern

```
native library (C or C++)                         owns its own work
  -> flat extern "C" shim   src/<lib>_shim.{c,cpp} -> <lib>.{so,dll,dylib} (ABI: pfx_*)
     -> LCB binding         src/<lib>.lcb           (org.openxtalk.library.<lib>)
        -> script helpers   examples/<lib>-helpers.livecodescript (poll dispatcher)
```

Public `Xx*` wrappers hide handles, pre-size buffers and walk records.

## 2. The three rules, by library shape

1. **Never call an LCB or script handler from a foreign thread.** Inbound
   activity rides a queue that script poll-drains on a timer.

   | Shape | Example | What rule 1 costs |
   |---|---|---|
   | Pure functions | libsodium | Nothing: no threads, no events, no poll. |
   | Pump-driven | ENet | Threadless, but nothing progresses unless you pump, so the poll loop is the heartbeat and its interval is the latency floor. |
   | Foreign-thread callbacks | libdatachannel | The worst case. A callback may only lock a mutex, push a typed event (our handle id plus a COPY of the payload) and unlock: no engine call, no script, no allocation that can throw. `dcPoll` drains on the script thread. |

2. **The exception firewall.** A throw crossing `extern "C"` takes the engine
   down, so every entry point is `try { ... } catch (...) { set_error(...);
   return <error>; }`, even over a C library (our own allocations can throw
   `std::bad_alloc`). Make it a macro so it is structural.
3. **Payload across the FFI is domain-specific.** For TorrentXT, gigabytes never
   cross. Where the payload IS the data (a plaintext, a game message), keep what
   crosses KB-scale, send bulk to TorrentXT, and document a size budget.

## 3. `.livecodescript` gotchas

**Engine behaviour:** ASCII only, comments included (note 1.4); an undeclared
name evaluates to its own spelling (2.1); declarations resolve by lexical
position (1.2); constants are literal and declared first (1.3);
`itemDelimiter`/`lineDelimiter` are global, so set them right before each use
and restore (2.3); `repeat with` ignores `step` (3.1); `throw` inside `catch` is
lost (3.2); a zero-argument statement call is bare, `dcCleanup` not
`dcCleanup()` (3.3); a prefixed stem can be a token, `tExt` (1.5); a
script-only stack file opened from disk builds no GUI (5.5); a timer-driven
dispatcher resolves unqualified controls by the defaultStack: pin it (5.3).

**House idioms:** `repeat with x = 1 to n`, never `from`; `the round of X`;
commands report through `the result` (`btAddMagnet s, uri, path` then
`put the result into tH`), functions return (`put btTorrentStatus(tH) into a`);
`textEncode`/`textDecode` with `"UTF-8"`; `put X into url ("binfile:" & tPath)`;
`uXxx` custom properties persist; self-building stacks are idempotent
(`if there is a field ...`) and build inside `lock screen`/`unlock screen`.

## 4. `.lcb` gotchas (stricter)

- `unsafe ... end unsafe` around EVERY foreign call; every declaration at the TOP
  of the handler, since a nested one broke whole-script compilation (engine notes
  section 4); constants literal and declared first (1.3).
- No `repeat for each line`: count with `repeat with i from 1 up to n`
  (`repeat for each element` works on a bridged list), and have the shim return
  a list of records rather than newline-joined text.
- `private foreign handler _pfx_name(in p as CInt, ...) returns CInt binds to "c:<lib>>pfx_name!cdecl"`.
  **Never rename an exported symbol**: the compiled `.lcb` binds by the string.
  `<builtin>` handlers (`MCMemoryAllocate`, `MCMemoryDeallocate`,
  `MCDataGetBytePtr`, `MCDataCreateWithBytes`, `MCStringDecode`) resolve by name,
  with no leading underscore.
- Booleans cross as `CInt` 0/1 (convert parameters, return `tR is not 0`);
  `ZStringUTF8` is for short NUL-terminated strings.
- Parameters are typed and never optional: an EMPTY value into
  `in pHost as Integer` is a runtime "type conversion error" (6.4), and
  `tools/check-lcb-call-types.py` walks every call across the boundary.
- Prefixes `t`/`p`/`s`/`k` (local, parameter, script, constant), avoiding stems
  that are engine tokens (1.5); public `XxPascalCase`, C `pfx_snake_case`.

## 5. The FFI marshalling contract

- **A `Data` does NOT auto-bridge to a C `Pointer`**; passing one raises
  `expected type pointer`. The two proven shapes:
  - **OUT** (the shim fills it): `MCMemoryAllocate` a block, pass the `Pointer`
    and its capacity; the shim returns bytes-written, or `-needed` if too small;
    grow and retry ONCE; copy back the written bytes with
    `MCDataCreateWithBytes`. Reuse a persistent buffer (`sXxxPtr`/`sXxxCap`),
    never reallocating per poll.
  - **IN** (the app supplies it): `MCDataGetBytePtr(theData)` plus its length.
- Scalars: int and bool `CInt`, real `double` (dated in engine notes section 4).
  **There is no 64-bit foreign int**: 64-bit values, offsets and hashes ride as
  decimal or hex `ZStringUTF8` (script numbers are doubles, note 2.4).
- Never return a library-owned `const char*` of unknown lifetime; return `""`,
  never `NULL`.
- **Getters and actions are separate families**, so a small `-needed` is never
  read as an error. Getters: bytes-written / `-needed` / `0` on a bad handle.
  Actions: `0` ok, negative error. Where `0` is a valid value (a queue position),
  the getter returns `-1` for "no value / bad handle", documented.
- **How failure reaches script is per library**, in its api-reference: the
  event-style bindings (torrentxt, enetxt, datachannelxt) return 0/empty or a
  negative code and throw only on ABI skew or a failed allocation; sodiumxt
  throws `<handler>: <last error>`. Every ABI guard's throw text contains `ABI `
  (`tools/build-preflight.py` classifies on it).

## 6. Handles and the record codec (reuse verbatim)

- **Handles** are positive 32-bit ints, a generation counter above a slot index,
  one validated table per object kind. Freeing bumps the generation, so a stale,
  removed or never-created handle is a harmless no-op (getters 0/empty, actions
  an error), never a crash or an alias. The table is one implementation in three
  shims, held byte-identical by `tools/check-shim-scaffold-drift.py`: copy it
  (that gate is why the planned shared `oxtkit/` library was retired 2026-08-27,
  `docs/OPEN-DECISIONS.md` D-14).
- **A library's own ids are not handles.** libdatachannel's rtc ints are not
  generation-tagged; map them to ours inside the shim, never expose them.
- **Record codec:** `kvrecord := [count:u16] then [fieldId:u8][type:u8][len:u16][bytes]`
  repeated, all framing big-endian, `type` 0 int (ASCII), 1 real (ASCII), 2 utf8,
  3 raw, 4 hex; lists are `[count:u16] then [bodyLen:u16][kvrecord]*`. ONE
  fieldId/alert registry in a shared header, mirrored as `k*` constants in the
  LCB and held by the member's `tools/check-record-registry.py`.
- **The drain never drops a record**: an oversized one is stashed and emitted on
  the next call.

## 7. Lifecycle, the poll-drain and events

- **No deterministic LCB unload hook.** Expose an explicit, idempotent teardown
  (`XxStopSession`/`XxClose`/`XxCleanup`), a no-op on a stale handle, that the
  app MUST call (on `closeStack`, say).
- **Global init once on load** (`sodium_init`: 0 ok, 1 already, -1 refuse to
  operate). Refuse a second session only for a genuinely single-instance
  library: libtorrent yes, ENet no.
- **The poll-drain:** one timer tick, one FFI round trip, ALL pending events as a
  record list, a dispatcher fanning them out. The interval is a latency/CPU knob,
  not a correctness knob: 16-33 ms for real-time, none for synchronous crypto.
  Callbacks can fire after a delete, so queue ids, not pointers, and validate.
- **An event name may not equal a public handler name** (one namespace, engine
  note 6.7): the `dcLocalDescription` event reached the same-named getter for
  months (now `dcLocalDescriptionReady`); `check-lcb-call-types.py` check 4.

## 8. Single-thread performance

Script, the FFI and rendering share ONE interpreted thread. Costs, in order:
interpreter ops, FFI round trips, property-set redraws. So: one FFI round trip
per poll (a batched drain, one-call snapshots); persistent buffers in hot paths;
one clock read per pass; UI text at most about 4 Hz and only on change.

## 9. C, C++ and build traps

- **The macro-comma trap.** A top-level comma in a function-like guard macro
  splits its arguments (only parentheses protect commas): `std::array<char, 32>`
  inside `BTX_GUARD_*({ ... })` failed with "macro passed 2 arguments". Use a
  file-scope alias, extra parentheses, or declare it outside the macro.
- Third-party headers are system headers (`-isystem`), so `-Wall -Wextra` stays
  about our code. **Pin every dependency and stand up the platform matrix in
  phase 0**: the dependency build is the real risk, not the binding.
- **Export only the `pfx_*` ABI.** A statically linked dependency inherits the
  library's public visibility, and `-fvisibility=hidden` on our target never
  reaches it. Filter at link time: `src/<lib>.map` as a version script (ELF),
  `-exported_symbols_list` derived from it (Mach-O), a `.def` (Windows).
- **Sanitizers are gcc ASan/UBSan** (clang's ASan runtime is not installed). A
  threaded library adds TSan, with the sanitize switch GLOBAL and set before the
  dependency is fetched (`DATACHANNELXT_SANITIZE`): per-target flags leave the
  dependency bare and TSan false-positives on its internals.

## 10. Toolchain and process

- **ABI sync.** `PFX_ABI_VERSION` equals the LCB's `kABIVersion`; a private ABI
  guard throws on skew instead of crashing at first use; bump it on ANY
  exported-surface change: a new symbol, a changed signature, or a new record
  fieldId/alert (the registry is append-only). Held by the member's `check-record-registry.py`,
  `tools/build-preflight.py` and `tools/check-binary-freshness.py` (every bind is
  an export of the COMMITTED library, the export closure where the build has
  one, and `pfx_abi_version()` returns the header's number), with
  `tools/check-lcb-signatures.py` holding each bind's types to its C definition.
- **Binaries ship per platform** at `src/code/<arch>-<platform>/<lib>.{so,dll,dylib}`:
  bare token, no `lib` prefix, architecture first; ids `x86_64-linux`,
  `x86-linux`, `x86_64-win32`, `x86-win32`, `universal-mac`. A `universal-mac`
  dylib carries both slices: `macos-15` runners are arm64-only, so build both,
  assert `lipo -archs`, and test x86_64 under Rosetta 2
  (`tools/install-release-binaries.py` refuses a thin Mach-O).
- **A native change is done when the committed binary is refreshed** (root
  `CLAUDE.md` rule 5). The per-push `native-<member>.yml` lanes upload artifacts
  and NEVER commit; `release-binaries.yml` (manual dispatch) builds every native
  member, installs, runs the gates and commits.
- **A new binding joins the suite** by the departure list in
  `docs/MEMBER-REPO-SPLIT.md` section 8 run in reverse, plus the native tables
  (the three gates above, a root `native-<member>.yml`, `release-binaries.yml`).
- **Static gates run anywhere; the OXT pass cannot be skipped.** A `.lcb` cannot
  be compiled or run headlessly, so a self-test stack on a real engine is the
  only validation of the BINDING: until then, "verified statically; needs an OXT
  pass".

## 11. Lessons by library shape

- **libsodium.** An OXT `Data` is not locked memory: zero transient buffers
  C-side (`sodium_memzero`), keep secrets short-lived, document what cannot be
  protected. Argon2 `sensitive` can block the thread for seconds: `interactive`
  in a UI. Expose exact size constants (MAC 16, nonce 24, signature 64).
- **ENet.** Loop `enet_host_service(host, &e, 0)` until it returns 0, every tick.
  `enet_packet_create` copies (never `NO_ALLOCATE`); the host owns a sent packet;
  on receive copy the bytes THEN `enet_packet_destroy`. Channels are fixed at
  create; `enet_address_set_host` may block on DNS; many hosts per process.
- **libdatachannel.** `rtcInit`/`rtcCleanup` are process-global. TURN
  credentials are secrets. Signaling is out of band and can ride TorrentXT's
  BEP44 DHT. Data channels only, media off the FFI; surface `bufferedAmount` and
  its low-threshold event for backpressure. Dependencies are pinned and linked
  statically except OpenSSL (`datachannelxt/docs/building.md`). libjuice alone
  (ICE only, MPL-2.0) is a lighter middle ground between ENet and WebRTC.

## 12. Licenses and risks

Permissive licenses only (libsodium ISC, ENet MIT, libdatachannel/libjuice
MPL-2.0 at the pinned tag, libtorrent BSD-3), so static-link-and-ship stays
clean; avoid GPL cores such as most of FFmpeg. Attributions: the root `LICENSE`.
Risks and their answers: the dependency build (phase-0 matrix, pinned
versions); foreign-thread races (mutex queue, ids not pointers, TSan); no unload
hook (idempotent teardown, the `closeStack` contract); payload creep (a size
budget, bulk to TorrentXT); secrets in non-secure memory (C-side memzero,
short-lived, honest docs); ABI drift (section 10); a license surprise (check the
pinned tag); blocking the single thread (presets, heavy work off a timer).

## 13. Definition of done (per binding)

The C smoke test green under gcc ASan/UBSan (plus TSan if threaded); every
static gate green, ABI sync included; platform binaries committed through
`release-binaries.yml`; a self-test stack over the public surface, folded into
the suite paste by `tools/build-suite-selftest.py` (`check-suite-coverage.py`
then fails on an untested public handler); getting-started, api-reference and a
member `CLAUDE.md`; and the section 10 honesty label until an engine run.
