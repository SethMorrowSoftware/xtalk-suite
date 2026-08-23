# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working in the
dataChannelXT member of the xtalk-suite monorepo (`datachannelxt/`).

> Read `docs/architecture.md` for the design and `docs/api-reference.md` for the
> surface. This file is the operational as-built record and the hard-won-lesson
> list, in the same spirit as the `CLAUDE.md` files in the sibling extensions
> TorrentXT, Box2Dxt, and ShowControl. The original plan lives in the suite's
> `docs/NEXT-EXTENSIONS-PLAN.md` Part IV ("libdatachannel — THE HARD ONE").

## What this is

**DataChannelXT** brings **WebRTC data channels** to OpenXTalk (OXT) / the xTalk
family: browser-interoperable, NAT-traversing (ICE/STUN/TURN), real-time P2P
messaging — reliable and unreliable modes — from xTalk script.

It is a binding to **libdatachannel** (C++17, MPL-2.0; vendored libjuice for ICE +
usrsctp for SCTP; DTLS via the system OpenSSL), wrapped behind a flat `extern "C"`
shim, with a thin LCB layer on top:

```
libdatachannel + libjuice + usrsctp (+ OpenSSL)   owns the network threads
   |- C++ shim     src/datachannel_shim.cpp  ->  datachannelxt.{so,dll,dylib}  (ABI: dcx_*)
        |- LCB binding  src/datachannel.lcb       (library org.openxtalk.library.datachannel; public dc*)
             |- script helpers  examples/datachannel-helpers.livecodescript  (the poll dispatcher)
```

The native library ships **bundled inside the extension** under
`src/code/<arch>-<platform>/datachannelxt.{so,dll,dylib}` (bare token, no `lib`
prefix; platform-ids `x86_64-linux` / `x86-linux` / `x86_64-win32` / `x86-win32` /
`universal-mac`, architecture first, Windows `-win32` for both bitnesses).

## The three rules that make this safe

1. **Never call an LCB handler from a libdatachannel (foreign) thread.** This is
   the family's rule 1 at its WORST CASE: libdatachannel fires every callback
   (descriptions, candidates, states, opens, messages) from its own worker
   threads. Every callback body in the shim does exactly one thing: take the one
   state mutex, push an owned copy of the event onto the bounded queue, release.
   `dcPoll` (`dcx_poll`) — the engine's single script thread, on a timer — drains
   that queue as a record list. **The mutex-guarded queue is the single most
   important correctness structure in this binding**, and the ThreadSanitizer CI
   lane exists to police it.
2. **The exception firewall — in BOTH directions.** Every `dcx_*` entry point is
   wrapped in the `DCX_GUARD_*` macros (a throw becomes a recorded error, never an
   unwind across `extern "C"` into the engine). And every CALLBACK body is wrapped
   in its own `try/catch(...)` so nothing we do (a `bad_alloc` copying a payload)
   can unwind back into libdatachannel's thread either.
3. **Payload across the FFI is allowed HERE by design — but bounded.** A data-
   channel message IS the payload. The budget is `DCX_MAX_MESSAGE` (60 000 bytes)
   both ways: sends over it are refused loudly (`DCX_ERR_TOO_LARGE`), never
   truncated or split silently; the shim advertises the cap in the SCTP
   negotiation so a compliant remote never exceeds it inbound; a misbehaving
   remote's oversized message is dropped WHOLE with an error event. Bulk transfer
   belongs to TorrentXT.

## THE LOCK DISCIPLINE (the lesson that cost a gdb session)

`rtcDeletePeerConnection` / `rtcDelete` **block until in-flight callbacks return**,
and our callbacks block briefly on the state mutex `g_mu`. Two consequences,
both load-bearing:

- **Never call an `rtc*` function while holding `g_mu`.** Entry points lock →
  validate/copy what they need → UNLOCK → call `rtc*`. An entry point that held
  the mutex across an rtc call could deadlock against a callback thread waiting
  for that same mutex (ABBA with libdatachannel's own locks — we watched it
  under gdb). Callbacks may call cheap rtc getters/setters (they are already on
  the rtc thread) but take `g_mu` only for the enqueue/table touch.
- **Clear every callback BEFORE every delete** (`clear_peer_callbacks` /
  `clear_channel_callbacks`). libdatachannel's C layer (capi.cpp) drops the
  object's LAST reference while holding its own global map mutex; the destructor
  of a still-connecting PeerConnection then fires the state callback inline,
  whose wrapper calls `getUserPointer`, which re-takes that same non-recursive
  mutex — **a self-deadlock inside the dependency**, reproduced under gdb at
  `rtcCleanup`. With our callbacks nulled first there is nothing to fire, and
  the nulling itself synchronizes with (joins) any invocation already running.
  This guard lives in `dcx_peer_free`, `dcx_channel_free`, and `dcx_cleanup` —
  keep it when adding any new teardown path.

## Event-ordering guarantees (pinned by the smoke test)

- **`E_CHANNEL_INCOMING` always precedes that channel's `E_CHANNEL_OPEN`.** The
  incoming event is enqueued in the SAME locked section that births the handle,
  BEFORE the open callback is wired and BEFORE the already-open fallback check.
  (The first implementation announced OPEN first when libdatachannel delivered
  an already-open channel — the app cannot know the handle yet at that point.
  The smoke test now pins the order.)
- The drain never reorders and never drops an event it accepted; events that
  name a since-freed handle are discarded AT DRAIN TIME (the app freed the
  handle — it declared it no longer cares). The queue is bounded (a safety
  valve for apps that stop polling): overflow sheds the NEWEST events, counts
  them, and reports the count in `E_QUEUE_OVERFLOW` once the backlog drains.
  The test invariant is **conservation**: delivered + reported-shed == sent.

## Commands

**Native shim + C++ tests** (the layer with the automated test suite):
```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DDATACHANNELXT_BUILD_TESTS=ON
cmake --build build --parallel
ctest --test-dir build --output-on-failure   # record_handle_test + datachannel_smoke_test
```
CMake acquires libdatachannel by FetchContent (pinned `GIT_TAG`, v0.24.5) with its
vendored submodules; DTLS from the system OpenSSL (`libssl-dev` / brew `openssl@3`
/ vcpkg). The dependency build is minutes, not the hours Boost/libtorrent cost
TorrentXT.

**The sanitizer lanes** — the `DATACHANNELXT_SANITIZE` knob is a STRING and
GLOBAL, injected before FetchContent so the whole static stack (libdatachannel,
libjuice, usrsctp) is instrumented too; per-target flags would leave the
dependency uninstrumented and TSan would false-positive on its internals:
```sh
cmake -S . -B build-asan -DDATACHANNELXT_BUILD_TESTS=ON -DDATACHANNELXT_SANITIZE=address
cmake -S . -B build-tsan -DDATACHANNELXT_BUILD_TESTS=ON -DDATACHANNELXT_SANITIZE=thread
# TSan run needs the suppressions file (usrsctp-internal races ONLY — scope rule inside):
TSAN_OPTIONS="halt_on_error=1:suppressions=$PWD/tests/tsan-suppressions.txt" \
  ./build-tsan/datachannel_smoke_test
```
gcc only (clang's sanitizer runtimes are not installed in this environment).
`address` and `thread` are mutually exclusive builds. **A shim change is only
"done" once the smoke test is green in BOTH lanes.** The TSan suppressions file
may only ever name races wholly inside a vendored dependency; a report with a
`datachannel_shim.cpp` frame among the RACING ACCESSES is ours and must be fixed.

**Record-schema golden test** (pure reference, runs anywhere):
```sh
python3 tests/record_golden_test.py
```

**Static gates for the script layer** (no headless OXT exists — catch what is
statically catchable):
```sh
python3 tools/check-livecodescript.py
python3 tools/check-record-registry.py    # registries + ABI sync + size budget
```
**Do not claim runtime behaviour you cannot observe** — say "verified statically;
needs an OXT pass" and let a human run `tests/datachannel-selftest.livecodescript`.

**THE ASYNC LOOPBACK IS NO LONGER STATIC (2026-08-15).** The member's own
harness ran STANDALONE on a real engine, green end to end — including the
`loopback: create + negotiate (async)` section that the suite harness
deliberately does NOT fold in (the core drives its own loopback there, and two
state machines in one process would race for the event handlers). That closes
the last static half of this member's selftest, the same way enetxt's closed on
2026-08-13. What it actually proved, beyond "it connected":

- the negotiation is real WebRTC, not a shortcut — the local description is a
  genuine SDP **carrying candidates**, peer A describes itself as the **offer**
  and peer B as the **answer**, and `dcGatheringState` reaches complete (2) on
  **both** peers with a selected candidate pair exposing a `localCandidate`;
- the channel surface holds live: a stream id is assigned, the negotiated max
  message is > 0, `dcBufferedAmount` is >= 0, and
  `dcSetBufferedLowThreshold` returns 0 **on a live channel** (the stale-handle
  path was already covered);
- payload integrity both ways: `dcSendText` arrives intact and `dcSendData`
  arrives **byte-for-byte including an embedded NUL** — the case a
  length-unaware string copy would silently truncate;
- `dcCreateChannelEx` round-trips both its label and its protocol, and a
  **cap-sized send** returns 0.

Still open for this member: browser interop (a real Chrome/Firefox peer) and a
call across two networks with actual NAT traversal. Loopback exercises ICE's
machinery but never leaves the host.

## FFI / C-ABI conventions (carried from the family, unchanged)

- **Handles are positive 32-bit ints** (`0` = invalid), generation-tagged, one
  table for peers and one for channels; a stale handle is a harmless no-op.
  libdatachannel's own C-API ints are NOT generation-tagged (a recycled id would
  alias), so they are never exposed — the shim maps rtc id <-> our handle, and
  events carry OUR ids, re-validated at drain.
- **Reals cross as `double`, booleans as `int` (0/1).** Exported symbols keep the
  stable `dcx_` prefix — never rename them; the `.lcb` binds reference the strings.
- **Byte buffers cross as `Pointer` + `CInt` length — an LCB `Data` does NOT
  auto-bridge to a `void*`.** Out-buffers use MCMemoryAllocate + bytes-written /
  `-needed` grow-and-retry; in-buffers pass `MCDataGetBytePtr`. `<builtin>`
  handlers carry no leading `_` (they resolve by name).
- **There is no 64-bit foreign int** (nothing in this surface needs one; the rule
  stands for additions — decimal `ZStringUTF8` strings).
- **Short strings cross as `ZStringUTF8`** (SDP, candidates, labels, errors).
- **The getter `-1` caveat**: `dcx_peer_state` / `dcx_gathering_state` /
  `dcx_channel_stream_id` / `dcx_buffered_amount` / `dcx_channel_max_message`
  return **-1** for "no value / bad handle" because 0 is a REAL value for each.
- **Bump `DCX_ABI_VERSION`** on any ABI change; `_checkABI()` throws on skew and
  `check-record-registry.py` enforces the header/.lcb match statically.
- **The record schema** is byte-identical to TorrentXT's (`[count:u16]` then
  `[fieldId:u8][type:u8][len:u16][bytes]`, big-endian; drain entries
  `[type:u16][bodyLen:u16][kvrecord]`). Registries are dcx's own and APPEND-ONLY;
  `record_golden_test.py` + `record_handle_test.cpp` pin the same literal bytes.
- **Adding a handler:** `dcx_*` in the shim (validate handle; `DCX_GUARD_*`; obey
  the lock discipline) -> `private foreign handler` + public `dc*` wrapper in the
  `.lcb` -> **check the new public name collides with no name `_eventName` can
  return** (and, adding an EVENT, that its name collides with no public `dc*`
  handler - see gotcha 11; the suite gate `../tools/check-lcb-call-types.py`
  enforces it) -> MSVC .def list in CMakeLists -> bump ABI if changed ->
  smoke-test assertion -> rebuild + `tools/package-extension.py` in the same
  change.

## C++ gotchas (paid for, again, this session)

1. **THE MACRO-COMMA TRAP struck again.** `std::vector<int> a, b, c;` at the top
   level of a `DCX_GUARD_*` body split the macro's arguments ("passed 3
   arguments"). One declaration per line inside guard macros — the preprocessor
   protects commas inside parentheses only.
2. **`*/` inside a C comment ends it** — twice: a comment narrating `rtcDelete*/
   rtcCleanup` and one narrating `PS_*/GS_*` both terminated early and turned
   prose into code. Spell it "rtcDelete and rtcCleanup" / "PS_ and GS_".
3. **libdatachannel buffer getters count the NUL** (`copyAndReturn` returns
   `size+1`, probe with NULL first); our ABI hides that (+1 never crosses).
4. **`rtcSendMessage(id, data, size)`: `size >= 0` is binary, `size < 0` is a
   NUL-terminated TEXT message** — the text/binary distinction a browser peer
   sees. `dcx_send_text` passes -1; don't "fix" it.
5. **Message callbacks with no callback set are buffered and FLUSHED when one is
   set** (`Channel::onMessage -> flushPendingMessages`), which is what makes the
   wiring window in `register_channel` lossless. Verified in the pinned tag's
   source; re-verify on a version bump.
6. **An IPv6-less container prints `juice: UDP socket creation failed, errno=97`**
   (EAFNOSUPPORT) and then works over IPv4 — harmless noise, not a failure.

## LiveCodeScript / LCB / OXT gotchas (carried; OXT is stricter than LiveCode)

> **Engine BEHAVIOUR - as opposed to the conventions below - is collected in
> [`docs/OXT-ENGINE-NOTES.md`](../docs/OXT-ENGINE-NOTES.md)**, with the verbatim
> symptom, what each one broke, and whether a gate now holds it. Keep
> member-specific gotchas here; put anything the ENGINE does there, so there is
> one authoritative list instead of six that drift.


1. **No smart/curly quotes anywhere** — they fail OXT compilation; ASCII only.
2. **Avoid names whose full spelling lowercases to a reserved token** (the `tExt`
   == `text` class); the static checker flags them.
3. **Prefixes:** `t` handler-local, `p` parameter, `s` script-local, `k` constant.
   Public API `dcPascalCase`; C ABI `dcx_snake_case`.
4. **Constants must be literal and declared before first use.**
5. **`unsafe ... end unsafe` brackets every foreign call**; ALL declarations at
   the top of a handler.
6. **Commands report via `the result`; functions return a value.**
7. `itemDelimiter` is global mutable state — set immediately before use.
8. **`dcPoll` is the ONE buffer call whose return is a COUNT, not bytes** (same
   as TorrentXT's `btPoll`); the walker reads the leading u16 and each entry's
   bodyLen, so the unused buffer tail is never touched.
9. **`ZStringUTF8` MEASURES WITH `strlen`, so a NUL is a terminator, not a
   character.** `dcSendText` takes a String and the foreign decl passes it as
   `ZStringUTF8`; `dcx_send_text` then does `std::strlen(text)`. An embedded
   NUL therefore truncates the message AND shrinks what the budget check
   measures - and the shim cannot detect either, because by the time it holds
   a `const char *` the evidence is gone. The refusal has to live in the
   `.lcb`, which still has a length: `dcSendText` encodes to UTF-8 and rejects
   a zero byte with `kErrInvalidArg` (-3) before the `unsafe` block, clearing
   the shim's last-error rather than letting `dcLastError` answer for an
   unrelated failure. Anything that can carry a NUL is BINARY: send it with
   `dcSendData`, whose length crosses explicitly (and which delivered an
   embedded NUL byte-for-byte on the 2026-08-15 pass). Added 2026-08-17;
   verified statically, needs an OXT pass.
10. **LCB idioms do not exist in LiveCode Script** (cost an OXT compile error in
   the selftest): `{}` is valid LCB but NOT LCS (no array literals at all); a
   function result cannot be subscripted in LCS (`f(x)["k"]` - put it in a
   local first); a bare `is empty` on a whole ARRAY is vacuously true (arrays
   stringify to empty) - count `the keys of` a variable instead; string
   literals have NO escape syntax (`"\0"` is two ordinary characters - build
   binary with `numToByte`); and `is` is case-INsensitive, so byte-exact Data
   comparison needs `set the caseSensitive to true` first. The checker now
   flags the first two statically (`LCS_ANTIPATTERNS`).
11. **AN EVENT NAME MAY NEVER EQUAL A PUBLIC `dc*` HANDLER NAME.** The names
   `_eventName` returns share ONE xTalk message namespace with every public
   handler this module exports, because a DISPATCHED name resolves exactly
   like a called one. When the two collide the LIBRARY handler wins and the
   app's `on <name>` is never reached - not "sometimes", never. Observed
   2026-08-18 (Linux) on `dcLocalDescription`, which was simultaneously the
   emitted event name and the public getter
   `dcLocalDescription(in pPeer as Integer)`: the dispatch landed in the
   getter with the event Array and threw "cannot convert value", and because
   the poll pump died silently the throw was read as a DRAIN failure for two
   passes. See [`docs/OXT-ENGINE-NOTES.md`](../docs/OXT-ENGINE-NOTES.md) 6.7
   for the verbatim symptom and how long it hid. **When they collide, rename
   the EVENT, not the getter** - the getter is exercised by the harness and
   the event demonstrably was not, so the event is the side with nothing to
   lose. The suite gate `../tools/check-lcb-call-types.py` (check 4, run from
   the suite root by `tools/build-all.sh --gates`) refuses any future
   collision, so this is now caught statically rather than on an engine.
   **The transition shim, and its removal condition:**
   `examples/datachannel-helpers.livecodescript` maps the legacy
   `dcLocalDescription` name onto the `...Ready` spelling as it drains, so an
   app runs against an extension packaged BEFORE 2026-08-18 without a
   reinstall; sites that COMPARE `tEvent["name"]` accept both spellings
   (`tests/datachannel-selftest.livecodescript:405-408`). The shim comes out
   when no supported build emits the old name.

## The single-threaded performance playbook (carried)

- **One FFI round-trip per poll** — `dcPoll` drains everything; never one call
  per event. Poll at 16-33 ms for real-time feel; the interval is a latency
  knob, never a correctness knob (the queue buffers between drains, bounded).
- **Reuse the persistent buffers** (`sDrainPtr`/`sScratchPtr`) — never rebuild
  per poll. UI text <= ~4 Hz and only on change.
- **Backpressure, not blasting:** check `dcBufferedAmount`, arm
  `dcSetBufferedLowThreshold`, stop sending until `dcBufferedLow`.

## The WebRTC model in one paragraph (what every demo must convey)

Everything is asynchronous and **signaling is the app's job**: create a peer,
create a channel (auto-negotiation makes the offer), ship each
`dcLocalDescriptionReady` / `dcLocalCandidate` event's payload to the far peer over
ANY existing channel (TorrentXT DHT, copy/paste, a server), feed the far side's
into `dcSetRemoteDescription` / `dcAddRemoteCandidate`, and wait for
`dcChannelOpen`. Non-trickle variant: wait for `dcGatheringStateChange` ==
complete, then ship `dcLocalDescription(peer)` as ONE blob (it then contains the
candidates). The loopback demo is the four-line proof; TURN is the fallback when
both NATs are hostile (credentials ride in the ICE-server URI — they are secrets
in ordinary memory, same caveat as the family's other secrets).

## The flagship demo (datachannel-dht-chat) - decisions that must hold

`examples/datachannel-dht-chat.livecodescript` pairs this extension with
TorrentXT: BEP44 mutable items carry the WebRTC handshake, then the chat rides
the direct channel. Its load-bearing decisions:

1. **The room code IS the keypair seed.** `btDhtKeypair` is deterministic on a
   64-hex seed, so the code is a shared write-capability for one DHT mailbox
   (both sides sign with the same key; salts "wx-o"/"wx-a" split the slots).
   Codes are minted fresh per Host click, so they are single-use and stale DHT
   leftovers can never belong to the current room. Document (not solve) that
   whoever knows a code can read the SDP blobs (they contain IPs).
2. **Non-trickle only.** A DHT round-trip is seconds; trickling candidates
   through it would be absurd. Publish ONE blob per side after
   `dcGatheringStateChange` == complete.
3. **The 1000-byte BEP44 budget** forces a wire format: head item
   `"DXC1" & kind & rest`, kind "D" = zlib(body) inline, kind "C" = comma list
   of 40-hex immutable-chunk targets (content-addressed = free integrity;
   republish lands on the same targets). Body = `nonce LF type LF sdp`; split
   on the FIRST TWO LFs only - the SDP is full of line breaks.
4. **The nonce pairs answer to offer.** Both sides dedup/reject on it, which
   is what makes Reconnect-under-the-same-code safe while stale items float
   around the DHT for hours. Seq also rises, but the nonce is the simpler,
   role-symmetric guard.
5. **The folder stays standalone.** The demo depends on TorrentXT's EXTENSION,
   never its example files - the bt poll loop is inlined (a dozen lines), and
   both extensions are probed at startup with guarded calls that fail closed
   (the family's SodiumXT probe pattern).
6. **One standing timer chain per loop**, armed once at start, rescheduling
   first and no-oping by phase. Arming chains per user action (Host/Join/
   Reconnect) stacks duplicates that double every poll and republish.

## The engine finding that cost an OXT session (2026-08-09)

**`dcCleanup()` does not compile.** Pasted into a real engine, the suite self-test
died on that line, and because a `.livecodescript` compiles as ONE unit it took
the whole file with it.

The rule: **a zero-argument call in STATEMENT position must be written BARE.** A
statement that starts with an identifier is parsed as a COMMAND, and what follows
is its argument - so `dcCleanup()` hands the command the expression `()`, and
`()` is not an expression.

Three things made this survive review for as long as it did, and they are the
reusable part:

1. **The one-argument spelling is FINE.** `dcFreePeer(sPeerA)` works, because
   `(sPeerA)` genuinely is an expression. So the broken line looks exactly like
   the working line next to it. `datachannel-loopback.livecodescript` had
   `dcStopPolling` (correct, bare) and `dcCleanup()` (broken) on CONSECUTIVE
   LINES.
2. **In EXPRESSION position the parens are required.** `dcCleanup() is 0` in an
   assertion is correct. Same eight characters, opposite verdicts, decided
   entirely by what is to the left of them.
3. **LiveCode BUILDER allows it.** `sPrepare()` as a statement appears ~90 times
   across `sodium.lcb` and `coinxt.lcb` on paths that have run green on an
   engine. So "we do this everywhere" was true and irrelevant: `.lcb` and
   `.livecodescript` are different languages.

This member was the only one with the bug, at four sites (`datachannel-loopback`
37, `datachannel-dht-chat` 310 and 365, `datachannel-selftest` 380) - and
enetxt's harness header had already written the lesson down ("zero-argument
calls BARE in statement position"). All six copies of
`check-livecodescript.py` now refuse it, `.livecodescript` only, and each copy
was tested against the bug, against all three working forms, and against a
`.lcb`.

[Annotated 2026-08-19; the sentence above is left as it was written. Both of
its present-tense halves have been overtaken, and the second one by this
section's own lesson. The COUNT was right on the day - six extensions were
the only members carrying a checker - but the copies had by then drifted into
TWO independent implementations, and they were UNIFIED on 2026-08-12
(ae629fb) into one carrying the union of both lineages' checks: seven
members at that commit, and every member folded in since carries the same
bytes. Measured today: ten copies (box2dxt, coinxt, datachannelxt, enetxt,
holde-em, nocloud, onionxt, riptide, sodiumxt, torrentxt), byte-identical,
with tools/check-checker-drift.py failing the build on any divergence - so
the number is a property of the tree now rather than of this sentence, and
that is why the suite root's copy of this narrative states none. The
ATTESTATION is the sharper correction. "Each copy was tested" was a one-time
claim about a run nobody could re-execute, which is the same shape as the
comment the meta-lesson below is about. It is not an attestation any more:
the fixtures for this bug and for all three legal forms - the bare statement
call, the expression-position call, and the .lcb spelling - are COMMITTED in
tools/test-checker.py and run against every copy in the gate set on every
build (75 fixtures x 10 copies = 750 runs today). Shipped is not run applies
to a gate's evidence exactly as it applies to the code the gate reads.]

**The meta-lesson, which is worse than the bug.** The suite harness carried a
comment asserting that both spellings were fine, reasoning that datachannelxt
shipped the parenthesised form so it must work. Shipped is not run: this
member's own harness had never been run on an engine, so the "attestation" was
circular. Do not promote an unexecuted line to evidence, in either direction.

## Git / workflow

- Develop on the per-task branch; commit there; draft PR if none exists.
- A `.lcb` change is only "done" once `tools/check-livecodescript.py` AND
  `tools/check-record-registry.py` pass - both member-local - AND once the
  SUITE gate `../tools/check-lcb-call-types.py` passes, which is not a member
  tool and is run from the suite root by `tools/build-all.sh --gates`: it types
  the script -> `.lcb` boundary argument by argument and refuses an event name
  that collides with a public handler. A shim change is done once the smoke test is
  green under ASan/UBSan AND TSan; an ABI change once `DCX_ABI_VERSION` +
  `kABIVersion` moved together.
- A native-library change is only "done" once `tools/package-extension.py` has
  refreshed the committed `src/code/<arch>-<platform>/` binary in the same
  change (CI rebuilds and tests the full matrix; binaries land on main).
- **Match the surrounding style** — comment the *why*, densely.

## As-built note, 2026-08-23: the poll dispatcher's script-locals carry the member stem

`examples/datachannel-helpers.livecodescript` renamed its four script-locals
(`sPolling` and friends became `sDcPolling` / `sDcPollTarget` /
`sDcPollInterval` / `sDcPollNote`), because the enet helper layer
declared the SAME four names and two libraries sharing a column-0 name can
never be co-embedded into one paste-and-run file - `sPolling` is the exact
name that already reached an engine once as a demo-vs-helper collision
(root `docs/OXT-ENGINE-NOTES.md` 1.6). Behavior-neutral standalone
(script-locals are file-scoped) and no carrier reads them directly
(measured: every demo and the selftest go through the `dcPoll*` handlers),
but the embedded copies changed, so every carrier was regenerated and the
rename is verified statically pending the next OXT re-pass. The suite's
`tools/check-cross-library-names.py` now holds all library names disjoint
so this class cannot recur.
