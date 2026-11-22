# CLAUDE.md

Guidance for Claude Code in the oscxt member of the xtalk-suite monorepo (`oscxt/`). Where
anything disagrees, the code and this file win.

## What this is

**oscxt** is Open Sound Control for OXT: tinyosc (ISC, vendored in
`src/third_party/tinyosc/`) -> the C shim `src/osc_shim.c` (exports `osc_*`, **ABI 2**:
`OSC_ABI_VERSION` in `src/osc_shim.h` equals the literal in `checkABI()` of the binding) ->
ONE library `oscxt.{so,dll,dylib}` (bare token) -> the LCB binding `src/osc.lcb`
(`org.openxtalk.library.osc`, public `osc*`). It is a codec only: transport is the
script's own UDP sockets, so nothing here opens a socket, starts a thread or calls back.
`examples/osc-helpers.livecodescript` holds the sending and routing helpers;
`examples/osc-selftest.livecodescript` the in-OXT self-test.

`examples/osc-show-surface.livecodescript` is the showcase (2026-11-21, by Seth Morrow): OXT-Beyond's dark look
(EXEMPT from the suite's UI kit by the owner's request), a surface and a virtual rig over real UDP on 127.0.0.1, ports 9000 to 9009. It CARRIES
`examples/osc-helpers.livecodescript` between the embed markers: edit the helper, then run the suite's
`tools/sync-demo-embeds.py`, never the copy. Its tests: `tests/lcs/demo_test.livecodescript` (opened as start-here opens it; each scene against an oracle written in the test). It builds its window with messages locked, then centres it: built unlocked it held
OXT-Beyond 0.2.8-dp.1's IDE on Windows for 42 s as it opened (each scripted create and rename
ran the IDE's script, the suite's engine note 5.15), and a size set keeps a new stack's centre (5.18), so it
opened 390 px past the screen's left edge (2026-11-21). `TestTheWindowIsBuiltQuietly` and
`TestTheWindowOpensCentredOnTheScreen` failed against that build. Built so, it opened there in
1.7 s, without oscxt, wholly on the screen (the same day). Its loop stops itself at its next
frame once its stack is closed, so a close made with messages locked, which sends no closeStack,
cannot leave it running unseen in the IDE's memory with its port open (after each close there a
frame was still queued; `TestAClosedWindowStopsItsShow`), and a Windows pass of that fix found
nothing queued after either kind of close. Its stop also closes the name the engine lists for
each sender the rig heard, which closing the listener leaves listed (the suite's engine note
6.21: one more name per open, here on Linux and in the Art-Net showcase on Windows; the same
test, strengthened, failed first).

It is the OSC third of ShowControl (Seth Morrow Software's OSC, MIDI and Art-Net
extensions), which joined the suite on 2026-11-21 as oscxt, midixt and artnetxt. The library
id, every public handler, the `osc_` export prefix, ABI 2 and the helpers' names are
ShowControl's, unchanged, so an installed ShowControl `osc` extension upgrades in place.
Only the library's file name moved (`osc` -> `oscxt`), with the binding that names it.

## The rules

1. **Never call script from a foreign thread.** There is no thread: datagrams arrive through
   the engine's own `accept datagram connections ... with message`.
2. **Nothing crosses the boundary but values.** The shim is C over C; every export
   validates its handles and arguments before it touches tinyosc.
3. **Bytes from the network are untrusted.** `osc_parse` pre-scans each datagram once, with
   full bounds checking, into an indexed model, and decodes ONLY at the offsets that scan
   proved. Never read through tinyosc's cursor (`tosc_getNext*`): it finds the type tag by
   scanning for the first `,` after the address NUL, so a `,` hidden in the address padding
   desynchronised it from the validator's layout, a remote out-of-bounds blob read from one
   72-byte datagram (ShowControl's fuzzer found it). A change on the parse path passes the
   fuzzer under ASan/UBSan.
4. **Generation-tagged integer handles** for builders and parsed messages; a stale one is a
   harmless no-op. Script never sees one: every public handler brackets new, use and free.
5. **Done means:** a shim change is green in ctest under `-DOSCXT_SANITIZE=address`, the
   fuzzer included; a binding change passes `tools/run-lcb-tests.py`; a Script change passes
   `tools/run-lcs-tests.py`; all pass `bash tools/run-gates.sh`. A wire-format change starts
   in `tests/vectors/osc.json`. New behaviour gets a test, a fix the test that would have
   caught it.

## As built

- **Numbers cross exactly.** The binding turns a script number into text itself
  (`wholeNumberText` and friends), or passes a real straight through as `CFloat` /
  `CDouble`. LCB's `formatted as string` writes a real with `%g`, six significant digits:
  ShowControl's binding sent `i` 1234567.0 as 1, `d` 1/3 as 0.333333 and `s` 1234567.0 as
  "1.23457e+06".
- **int64 and timetags are decimal text** both ways: the engine (9.6.3) has no 64-bit
  foreign integer type.
- **Text into the shim is read in the C locale** (`strtod_c`): under a comma locale plain
  `strtod("0.5")` is 0.
- **int32 text out of range clamps** on every platform; ShowControl's wrapped on 64-bit
  Linux and macOS (`long` is 64 bits there: "3000000000" sent -1294967296) and saturated on
  Windows.
- **Every size is computed in 64 bits** and each field is capped below `INT32_MAX`, so no
  argument can wrap a length; a bundle element near 2 GB is refused, not wrapped.
- **`oscMatch` has a recursion limit** (`OSC_MATCH_MAX_DEPTH`, 256): a pattern too deeply
  nested to check is no match, never a stack overflow. `osc_smoke` runs it on a small-stack
  thread to prove it.
- **Refusals say why.** The binding decides some refusals itself (an unknown type code, a
  value missing, a NUL, a blob that is not binary data) and keeps its own reason, which
  `oscLastError()` prefers; ShowControl's returned empty with the error empty too.
- **tinyosc's `<endian.h>` use needs `-D_DEFAULT_SOURCE`** (CMake sets it), and Windows
  links `ws2_32` for `ntohl`.
- **`oscLoadNativeLibError` keeps its reason**, read from `dlerror()` when
  `oscLoadNativeLib` fails. ShowControl's read it when asked, and the engine binds a
  foreign handler on its first call, which ate the pending error: the first answer was
  always empty (engine note 6.19; `TestLoadNativeLibErrorIsKept`).

## The helpers (examples/osc-helpers.livecodescript)

`scEnsureDatagramSocket`, `scAddArg`, `scOscSend`, `socketReceived`, `scOscRoute` and
`scLooksLikeOsc`, ShowControl's names and behaviour. The engine calls a datagram message
with (sender, data, socket), in that order (engine `opensslsocket.cpp`); `socketReceived`
still recognises a packet in the first parameter for callers wired the old way round.
`write ... to socket "h:p"` sends NOTHING unless `h:p` was opened (the result is "socket is
not open"), so `scOscSend` opens it first.

## Gotchas

1. **A `Data` does not bridge to a foreign `Pointer`**: inputs pass `MCDataGetBytePtr`;
   outputs fill a reusable `MCMemoryAllocate` block copied back with `MCDataCreateWithBytes`.
   Only `dataPtr`, `ensureScratch` and `scratchToData` touch raw pointers.
2. **Never return a `ZString` from a foreign handler**: the engine frees it
   (`oscLastError()` crashed the VM on ShowControl's first lc-run; engine note 6.18; no
   gate refuses the form yet). Strings come back through caller buffers
   (bytes written, or `-needed`); `dlerror()`'s text as a `Pointer`, copied at once.
3. **A NUL cannot cross as a `ZString`**: the engine throws "cannot export char U+0000".
   The binding checks first and refuses quietly.
4. **LiveCode Script has no `[...]` list literal**: script builds args by assignment
   (`scAddArg`), as a FLAT list of type, value pairs; a nested Script array does not arrive
   in LCB as a list of lists.
5. **An all-lowercase LCB name warns, and the Extension Builder compiles with `-Werror`.**
6. **An accepted datagram socket is named by its port alone** (`close socket "9000"`), and
   delivers each datagram as its own message: nothing needs a `read`.
7. **It also lists one socket per sender it hears** (`127.0.0.1:41273`, on the listener's
   descriptor), and closing the listener leaves that name listed, with an engine thread
   spinning a whole core on Linux (the suite's engine note 6.21). The showcase's
   `osdStop` and the self-test's `oscStopSelfTest` close each sender's name first, held by
   `TestAClosedWindowStopsItsShow` and `TestShippedSelfTestTier2`; the test runner closes
   whatever a test left listed before its engine quits (`scCloseLeftSockets`, held by
   `TestTheRunnerClosesWhatARunLeftListed`), because at quit the engine frees its sockets
   while that thread may still be reading them.

## Status

Verified natively on x86_64 Linux (smoke, vectors and the fuzzer under ASan/UBSan, 23
million fuzz inputs clean on 2026-11-21) and on OXT-Beyond's headless engine (9.7.1-OXT,
Linux x86_64, 2026-11-21): the LCB suite under lc-run, and the Script suite in the
standalone engine with `-ui`, real UDP and the interop peer included, over a locally built
library. No desktop IDE and no Windows, macOS or Android engine has loaded it: verified
statically; needs an OXT pass. Its showcase has opened without it in OXT-Beyond 0.2.8-dp.1's
IDE on Windows (2026-11-21): it said what was missing, and that run found the two faults
above. No libraries are committed yet. Open work is in the suite's `docs/WORK-PLAN.md`.
