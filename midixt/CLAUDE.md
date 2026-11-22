# CLAUDE.md

Guidance for Claude Code in the midixt member of the xtalk-suite monorepo (`midixt/`). Where
anything disagrees, the code and this file win.

## What this is

**midixt** is realtime MIDI for OXT: RtMidi 6.0.0 (MIT, fetched as source at the commit its
tag names, compiled from its two files with the platform's backend: ALSA, CoreMIDI or
Windows MM) -> the C shim `src/midi_shim.c` (exports `midi_*`, **ABI 2**: `MIDI_ABI_VERSION`
in `src/midi_shim.h` equals the literal in `checkABI()` of the binding) -> ONE library
`midixt.{so,dll,dylib}` (bare token) -> the LCB binding `src/midi.lcb`
(`org.openxtalk.library.midi`, public `midi*`). `examples/midi-helpers.livecodescript` is the
poll dispatcher most stacks use; `examples/midi-selftest.livecodescript` the in-OXT
self-test.

`examples/midi-stage.livecodescript` is the showcase (2026-11-21, by Seth Morrow): OXT-Beyond's dark look
(EXEMPT from the suite's UI kit by the owner's request), a player and a stage joined by a virtual port, a loopback driver's pair, or, with neither, `midiDecode`. It CARRIES
`examples/midi-helpers.livecodescript` between the embed markers: edit the helper, then run the suite's
`tools/sync-demo-embeds.py`, never the copy. Its tests: `tests/lcs/demo_test.livecodescript` over the mock (the stage draws only what arrives, against the mock's log of what left) and `demo_hw_test.livecodescript` over the real library. It builds its window with messages locked, then centres it: built unlocked it held
OXT-Beyond 0.2.8-dp.1's IDE on Windows for 81 s as it opened (each scripted create and rename
ran the IDE's script, the suite's engine note 5.15), and a size set keeps a new stack's centre (5.18), so it
opened 390 px past the screen's left edge (2026-11-21). `TestTheWindowIsBuiltQuietly` and
`TestTheWindowOpensCentredOnTheScreen` failed against that build. Built so, it opened there in
3.0 s, without midixt, wholly on the screen (the same day). Its loop stops itself at its next
frame once its stack is closed, so a close made with messages locked, which sends no closeStack,
cannot leave it running unseen in the IDE's memory with its ports open (after each close there a
frame was still queued; `TestAClosedWindowStopsItsShow`), and a Windows pass of that fix found
nothing queued after either kind of close (the same day).

It is the MIDI third of ShowControl (Seth Morrow Software's OSC, MIDI and Art-Net
extensions), which joined the suite on 2026-11-21 as oscxt, midixt and artnetxt. The library
id, every public handler, the `midi_` export prefix, ABI 2, the helper's handler names and
the dispatcher's messages are ShowControl's, unchanged, so an installed ShowControl `midi`
extension upgrades in place and its stacks keep working. Only the library's file name moved
(`midi` -> `midixt`), with the binding that names it.

## The rules

1. **Never call script from a foreign thread.** RtMidi's input thread fills RtMidi's queue;
   script drains it with `midiPoll` on a timer. No callback is ever registered with RtMidi.
2. **Nothing crosses the boundary but values.** The shim is C over RtMidi's C API, which
   catches every C++ exception itself and reports it in the wrapper's `ok`. So the shim
   judges every call by `ok`, and sets `ok` back to true before a call it judges: RtMidi
   never resets it, so one failure would otherwise taint every later call on that wrapper.
3. **Payload stays out of script.** A poll drains up to 256 messages in ONE foreign call into
   one block, records `[2-byte length BE][bytes][4-byte delta-us BE]`, which the binding
   walks; it never crosses per message.
4. **Generation-tagged integer handles.** A stale or recycled handle is a harmless no-op
   that says why in `midiLastError()` (a send: "not an open output port"; a poll: "not an
   open input port").
5. **The last error is the last fallible call's.** Every export that can fail clears it on
   entry; a success leaves it empty (the docs promise that, and ShowControl's never cleared).
6. **Done means:** a shim change is green in ctest under `-DMIDIXT_SANITIZE=address`; a
   binding change passes `tools/run-lcb-tests.py`; a Script change passes
   `tools/run-lcs-tests.py`; all pass `bash tools/run-gates.sh`. New behaviour gets a test in
   the matching layer, a fix the test that would have caught it: every midixt fix below
   failed its test against ShowControl's code first.

## RtMidi 6.0.0, as the shim relies on it (read at the pinned commit)

- A wrapper whose constructor threw has `ok == false` and a NULL object: a call on it
  crashes. Its `msg` points into a freed exception: never read it (ASan-confirmed).
- `rtmidi_get_port_count` answers `(unsigned)-1` when it throws. ShowControl returned that as
  -1 ports and kept the failed enumerator cached for good.
- `rtmidi_in_get_message` that throws returns -1, leaves `*size` alone and the message
  queued. ShowControl took the untouched size for a giant message and read again: an endless
  loop on the engine's main thread. The drain now stops; the next poll retries.
- The input queue defaults to 100 (99 usable) and drops what arrives when it is full. The
  shim asks for 1024 (`MIDI_IN_QUEUE_LIMIT`).
- CoreMIDI and Windows MM drop a non-SysEx message longer than 3 bytes with a WARNING only:
  `ok` stays true. The shim refuses those sends itself, with a reason. Windows MM "opens" a
  virtual port and sends nowhere: the shim refuses virtual ports on Windows MM and the dummy
  backend.
- Port names: RtMidi's Windows MM names are already UTF-8. Names cross the boundary only
  through caller buffers, never as a returned C string.

## As built

- **RtMidi's own CMake does not run** (CMakeLists.txt says why): it would export every class
  (`RTMIDI_EXPORT`), add JACK whenever the build machine has its headers, and add `-Werror`
  to Debug builds. A pin bump that adds an upstream source file fails at link, on purpose.
- **Portable and closed:** `src/midixt.map` exports `midi_*` only (macOS derives its list
  from the same pattern); `MIDIXT_STATIC_RUNTIME` (ON) gives the static MSVC runtime and
  static libstdc++/libgcc on Linux. The suite's `check-binary-freshness.py` holds the exports
  of every committed library (a mock's `midimock_*` among them would fail it), and runs again in
  `release-binaries.yml` after `install-release-binaries.py` writes a new one.
- **No Android library:** RtMidi's Android backend needs API 29 and JNI; the suite's floor is
  API 21. CMake refuses an Android configure.
- **The per-input stash** (65535 bytes, allocated at open) carries a message that does not
  fit the caller's drain block to the next drain: a popped message is never dropped. The
  binding's block (2 + 65535 + 4) always fits one, so the stash's drop path is unreachable
  from LCB.
- **The two port listers stay.** Counting and naming ports needs an RtMidi instance: the
  shim makes one per direction on first use and keeps it for the life of the process (one
  whose backend failed is made again). ALSA lists them as two clients with no port, "RtMidi
  Input Client" and "RtMidi Output Client", after every port has closed: two such clients
  stayed in the IDE on the maintainer's Linux PC after MIDI Stage closed (2026-11-22).
  Nothing can connect to a client with no port.
- **`midiLoadNativeLibError` keeps its reason**, read from `dlerror()` when
  `midiLoadNativeLib` fails. ShowControl's read it when asked, and the engine binds a
  foreign handler on its first call, which ate the pending error: the first answer was
  always empty (engine note 6.19; `TestLoadNativeLibErrorIsKept`).
- **Virtual ports without a name** get "ShowControl In" / "ShowControl Out", the RtMidi
  clients "RtMidi Input Client" / "RtMidi Output Client": the names ShowControl's ports have
  always shown, so a DAW's saved routing still finds them.
- **The mock** (`tests/mock/`) reproduces each behaviour above, so the C, LCB and Script
  suites drive every failure path with no MIDI service. It is built as `build/mock/midixt.*`
  under the shipped name and must never ship (`tools/package-extension.py` refuses it;
  `tests/package_extension_test.py`).

## The helper's listener (examples/midi-helpers.livecodescript)

`scMidiStartListening pHandle, pIntervalMs, pTarget` polls one input on a `send ... in`
timer and dispatches `scNoteOn`, `scNoteOff`, `scMidiCC`, `scProgramChange`, `scPitchBend`
and `scMidiOther`. Each input has its own entry (interval, target, generation); every timer
message carries its generation, so a stopped or replaced chain dies at its next tick and a
restart never stacks a second timer. A handle below 1 starts nothing (`the result` says
why); a port closed under it stops its own timer. A handler that throws stops that input's
listener, as ShowControl's did, and the error is re-thrown after `end try` (a throw inside
`catch` never reaches the caller on OXT). Dispatch is `dispatch ... with`, never a built
`send` string: a message string splits its parameters on commas.

## Gotchas

1. **A `Data` does not bridge to a foreign `Pointer`.** Sends pass `MCDataGetBytePtr`; the
   drain fills a raw `MCMemoryAllocate` block copied back with `MCDataCreateWithBytes`.
2. **Never return a `ZString` from a foreign handler**: the engine frees it (engine note
   6.18; the checker's check 24 refuses the form). Names and the last error come back
   through caller buffers (bytes written, or `-needed`); `dlerror()`'s text as a
   `Pointer`, copied at once.
3. **A NUL cannot cross as a `ZString`**: the engine throws "cannot export char U+0000". The
   binding checks names first and answers 0 with a reason; ShowControl's threw.
4. **An all-lowercase LCB name warns, and the Extension Builder compiles with `-Werror`**
   (`_close`, `i`): every name here has an inner capital or underscore.
5. **Empty into an `Integer` parameter throws at the call; a fraction is not refused**: LCB's
   `Integer` is `Number`, and the engine cuts 60.6 to 60 where it becomes a byte (engine
   notes 6.4 and 6.17). The helper never passes either.
6. **The mock has ONE queue for every input**: a test that needs to know which input drained
   a message polls by hand (`helpers_test` does).

## Status

Verified natively on x86_64 Linux (the mock tests under ASan/UBSan; the real library's smoke
test on its no-service path) and on OXT-Beyond's headless engine (9.7.1-OXT, Linux x86_64,
2026-11-21): the LCB suite under lc-run, and the Script suite in the standalone engine with
`-ui`, over locally built libraries, and both again on 2026-11-22 over the committed
`x86_64-linux` library. Its six desktop libraries were committed that day (release run
44985328988), and the maintainer's two PCs installed it over them (the suite's runbook,
section 8). On Linux, OXT-Beyond 0.2.8-dp.2's IDE loaded it and the self-test passed in the
standalone engine with every check run (38), its Tier 3 loopback through an ALSA virtual
port among them: the first MIDI service on the record to carry its messages. On Windows,
0.2.8-dp.1's IDE compiled the binding and loaded it, `midiVersion()` answered 2 and listed
the GS Wavetable synth, and the self-test passed (29; 2 skipped, Windows MM having no
virtual ports). The showcase opened hidden on both and left no port and nothing queued when
closed; on Linux it offered for Sound the port that reads its own cable, fixed the same day
(`mdsReads`). It had opened without midixt in 0.2.8-dp.1's IDE on Windows (2026-11-21) and
said what was missing; that run found the two faults above. No message through CoreMIDI,
Windows MM or a MIDI keyboard is on the record, and no engine has loaded the mac, 32-bit or
ARM libraries: verified statically; needs an OXT pass. Open work is in the suite's
`docs/WORK-PLAN.md`.
