# midixt

**Realtime MIDI for OpenXTalk / the xTalk family (and LiveCode 9.6.3+).**

midixt lets a stack list the MIDI ports a machine has, open them, send notes, controllers,
program changes, pitch bends and SysEx, and receive whatever arrives, decoded. It is
[RtMidi](https://github.com/thestk/rtmidi), Gary P. Scavone's C++ library (MIT), over each
system's own MIDI service (ALSA on Linux, CoreMIDI on macOS, Windows MM on Windows), behind
the family's flat C shim and a thin LCB layer:

```
RtMidi 6.0.0 (pinned commit, static; ALSA / CoreMIDI / Windows MM)
   |- C shim   src/midi_shim.c  ->  midixt.{so,dll,dylib}     (ABI: midi_*, v2)
        |- LCB binding  src/midi.lcb     (org.openxtalk.library.midi; public midi*)
             |- examples/midi-helpers.livecodescript   (the poll dispatcher)
```

It is the MIDI third of ShowControl, which joined the suite on 2026-11-21 as **oscxt**
(Open Sound Control), **midixt** and **artnetxt** (Art-Net lighting). The library id, every
handler and the helper's messages are ShowControl's, so a stack written for ShowControl's
`midi` extension keeps working.

## What it can do

- **List and open ports**: every input and output the system knows, by position; virtual
  ports of your own on macOS and Linux that other programs see as devices.
- **Send**: notes, controllers, program changes, channel pressure and pitch bends by name,
  and any bytes (SysEx included) with `midiSend`.
- **Receive**: `midiPoll` returns everything that arrived since the last call, oldest first,
  each message decoded (kind, channel, data bytes, the 14-bit bend) with its raw bytes and
  its timing. The helper script runs the poll for you and calls `on scNoteOn`,
  `on scMidiCC` and the rest in your stack.
- **The family's rules.** No callback ever reaches script (rule 1): RtMidi queues what
  arrives, with its timing, and a timer drains it, so a slow timer adds delay but loses
  nothing. The shim is C over RtMidi's C API and judges every call by its result (rule 2);
  one poll drains a whole batch in one call (rule 3); every port is a generation-tagged
  integer handle, and a stale one is a harmless no-op that says why (rule 4).

What it does not do: MIDI files, MIDI 2.0, timing or sequencing of its own (send on your own
timer), Android (RtMidi's Android backend needs API 29; the suite's floor is 21), or
virtual ports on Windows (use a loopback driver such as loopMIDI).

## Quick taste

```livecodescript
-- with examples/midi-helpers.livecodescript pasted into the stack script
local sIn, sOut

on openCard
   put midiOpenInput(0) into sIn               -- the first input midiInputPorts lists
   put midiOpenOutput(0) into sOut
   if sIn is 0 or sOut is 0 then answer "MIDI:" && midiLastError()
   scMidiStartListening sIn
end openCard

on scNoteOn pChannel, pNote, pVelocity
   midiNoteOn sOut, pChannel, pNote + 12, pVelocity   -- echo it an octave up
end scNoteOn

on scNoteOff pChannel, pNote, pVelocity
   midiNoteOff sOut, pChannel, pNote + 12, pVelocity
end scNoteOff

on closeCard
   scMidiStopListening
   midiClose sIn
   midiClose sOut
end closeCard
```

[docs/getting-started.md](docs/getting-started.md) carries on from there.

## The showcase: MIDI Stage

`examples/midi-stage.livecodescript` (by Seth Morrow) is a player and a stage in one
window. It opens straight into motion and plays five scenes by itself: an arpeggio, chords
struck soft and hard, eight knobs, a pitch bend and drums with program changes. The stage
draws ONLY what arrives: a piano roll, a keyboard, the knobs, the wheels, the program and a
light per channel. On macOS and Linux the messages travel through a virtual port the stack
makes, "MIDI Stage", and back through the system's MIDI service; on Windows a loopMIDI
port carries them, and without one the stage reads each message with `midiDecode` and
says so. Press Sound to hear it through the Microsoft GS Wavetable Synth on Windows (or the
first output that is neither a cable nor a program's input); a keyboard plugged in plays in blue. It carries its helper script, so it is one file: open it from the suite's `start-here.livecodescript`, or paste the whole file into a new stack's script, apply, then close the stack and open it again. It needs the midixt extension installed; without it the window still opens and says what is missing.

Its engine tests passed on 2026-11-21 in OXT-Beyond's headless engine (Linux x86_64):
`tests/lcs/demo_test.livecodescript` over the mock MIDI library (the stage draws only what
arrives, checked byte for byte against the mock's log of what left) and
`demo_hw_test.livecodescript` over the real one (with no MIDI service there, it decoded and
said why). The same day it opened in OXT-Beyond 0.2.8-dp.1's IDE on Windows without midixt
installed, drew its window and said what was missing. That run found the window opening
with its left 390 pixels off the screen and the IDE held for 81 seconds as it opened; both
were fixed the same day: it now builds its window with messages locked and centres it.
Built so, it opened there that afternoon in 3 seconds, wholly on the screen. Closing its
window stops the show, by a close made with messages locked too: after each close in that
IDE a frame of its loop was still queued, and it now stops itself once its stack is closed,
which a second Windows pass saw the same day. On 2026-11-22, with midixt installed, it
opened hidden in the IDE on the maintainer's Linux PC, made its virtual port and found it
again through ALSA, and on the Windows PC named the GS Wavetable synth for Sound. Those
runs found two faults, each fixed the same day with a test that failed first: on Linux it
offered for Sound the port that reads its own cable, and it threw when opened again after
a close made while it played over the cable. Built from both fixes, it opened, closed and
opened again on both PCs with no error, and left nothing queued and no port behind.
Left playing ten seconds on Linux, it read back through ALSA all 86 messages its player
sent, 3 ms from send to stage on average: its first messages through a MIDI service on the
record. Nobody has watched or heard it, and no cable through CoreMIDI or a loopMIDI port
is on the record: its look, its Sound and those cables are verified statically; need an
OXT pass.

## Status

Joined the suite on 2026-11-21. What has run, and where:

- **Natively**, on x86_64 Linux: the shim over a controllable RtMidi double
  (`tests/midi_mock_smoke_test.c`: the drain, the stash, the queue, and every way RtMidi
  6.0.0 fails), clean under ASan/UBSan, and the real library's smoke test on its no-service
  path. Every fix midixt made to ShowControl's code has a test that failed against it.
- **On an engine**, the same day, OXT-Beyond's headless engine (9.7.1-OXT, Linux x86_64),
  over locally built libraries: the LCB suite under lc-run (the binding over the double and
  over the real library), and the Script suite in the standalone engine with `-ui` (the
  Script-to-LCB boundary, the helper's listener with real timers, and the shipped
  self-test); on 2026-11-22 both again over the committed `x86_64-linux` library.
- **Committed libraries:** the six desktop ones under `src/code/`, from the suite's
  release-binaries dispatch of 2026-11-22. No Android library: RtMidi's Android backend
  needs API 29.
- **In an IDE**, 2026-11-22, over the committed libraries: on Linux, OXT-Beyond 0.2.8-dp.2
  loaded it as an installed extension, and the shipped self-test passed in the standalone
  engine with every check run, its loopback through an ALSA virtual port among them; on
  Windows, 0.2.8-dp.1 compiled the binding and loaded it, `midiVersion()` answered 2 and the
  self-test passed (29 checks; Windows MM has no virtual ports, so 2 skipped).
- **Not yet:** a message through CoreMIDI, Windows MM or a MIDI keyboard on the record, and
  a Mac: there it is verified statically; needs an OXT pass.

## Building and testing

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DMIDIXT_BUILD_TESTS=ON && cmake --build build && ctest --test-dir build
python3 tools/run-lcb-tests.py --oxt-bin <OXT bin folder> --build-dir build
python3 tools/run-lcs-tests.py --oxt-bin <OXT bin folder> --build-dir build
bash tools/run-gates.sh
```

Linux needs `libasound2-dev`; RtMidi is fetched at configure time.
[docs/building.md](docs/building.md) has the details.

## Documentation

- [docs/getting-started.md](docs/getting-started.md) - install, receive (with the helper and
  by hand), send, virtual ports, the self-test, troubleshooting.
- [docs/api-reference.md](docs/api-reference.md) - every `midi*` handler, generated from the
  binding's doc blocks.
- [docs/building.md](docs/building.md) - builds, sanitizers, the four test layers, the gates.
- [CLAUDE.md](CLAUDE.md) - rules and gotchas for anyone changing this member.

## License

MIT (see [LICENSE](LICENSE)). RtMidi is MIT, with a request (not a condition) that changes
be sent upstream; [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) carries its notice.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

midixt is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`midixt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/midixt: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `midixt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port midixt --ref pull/<n>/head`, keeping its
author - but a commit made here directly holds up the next publish until
it has been ported, because publishing never overwrites work it did not
write. The suite's `docs/MEMBER-REPO-SPLIT.md` is the whole workflow.

**Suite-level paths cited from here.** This member's `CLAUDE.md` and
`docs/` cite files that live at the suite root, not in this tree:
`docs/OXT-ENGINE-NOTES.md` (engine behaviour, the authoritative list),
`docs/OXT-PASS-RUNBOOK.md`, `tools/build-all.sh`,
`tests/suite-selftest.livecodescript` and the suite-level `docs/`
index. Read them at `https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/<path>`. A path of the
form `../<member>/...` names a sibling member of the suite; each has its
own repository, listed in `tools/member-registry.py` there.

**Sibling members this member's gates need beside it.** None: `bash
tools/run-gates.sh` (this member's own gate list, the one CI runs)
needs nothing but this checkout and Python 3.

**Carried copies inside this member, and where their masters are.**
Every runnable stack here is one paste-and-run file, so it carries what
it needs verbatim between marker lines. The masters, and the drift gates
that hold every copy byte-identical to them, live in the suite and do
not travel with this member; refresh a copy from the suite (the marker
lines name the master) rather than editing inside the markers.

- This member's own library, embedded into its own stacks by the same tool so each is one file to paste: `examples/midi-stage.livecodescript` carries `examples/midi-helpers.livecodescript`.
- `tools/build-api-reference.py`, `tools/check-livecodescript.py`, `tools/run-lcb-tests.py`, `tools/run-lcs-tests.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

**What this repository cannot check on its own.** The suite-wide gates -
cross-library name disjointness (`tools/check-cross-library-names.py`),
the carried-copy drift gates above, embed freshness, the cross-member
handler-call and typed-boundary checks (`tools/check-handler-calls.py`,
`tools/check-lcb-call-types.py`), the timer-pin closure, and the suite
paste's coverage ratchet (`tools/check-suite-coverage.py`) - run only in
the suite. `tools/run-gates.sh` here is this member's own list, and the
suite's `tools/build-all.sh` runs that same script, so the two cannot
disagree about what this member's gates are.

<!-- ==== SUITE RELATIONSHIP END ==== -->
