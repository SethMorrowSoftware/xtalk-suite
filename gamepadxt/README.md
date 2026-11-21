# gamepadxt

**Game controllers - Xbox, PlayStation, Switch and most other pads - for OpenXTalk / the xTalk family.**

[SDL](https://github.com/libsdl-org/SDL) is the library most games read their controllers
with: it knows several hundred pads by name, gives them all one button layout, and handles
plugging and unplugging, rumble and lights. gamepadxt binds its gamepad part, and only that
part, behind the family's flat C shim and a thin LCB layer:

```
SDL 3 (pinned to a release commit, static, joystick parts only)     the controllers
   |- C shim   src/gamepad_shim.c  ->  gamepadxt.{so,dll,dylib}     (ABI: gpx_*, v1)
        |- LCB binding  src/gamepadxt.lcb     (org.openxtalk.library.gamepadxt; public gp*)
```

It reads controllers and nothing else: no window, no sound, no drawing. A stack keeps its own
window and its own loop, and asks gamepadxt what is held down.

## What it can do

- **One layout for every pad.** Buttons are named by where they are (`south`, `east`,
  `leftshoulder`, `dpup`, `start`, ...), so `south` is the bottom face button whether the pad
  prints A, a cross or B on it. `gpPadButtonLabel` gives the printed letter for prompts.
- **Sticks and triggers.** Each axis from -1 to 1 (triggers 0 to 1), or a whole stick as
  `"x,y"` with a round dead zone already taken out (`gpPadStick`).
- **Hot-plug.** Controllers arrive and leave while the stack runs; each is a pad handle, and
  `gpEvents` says `connected,<pad>` and `disconnected,<pad>`.
- **Events or state, whichever suits.** `gpPadButton` and `gpPadAxes` read what is held now;
  `gpEvents` lists what changed since the last read, one line each, so a quick tap between
  two frames is never missed.
- **Rumble and lights**, where the pad has them: two motors, trigger motors, an RGB light.
- **What a pad is.** Name, kind (`xboxone`, `ps5`, `switchpro`, ...), vendor and product
  numbers, player number, battery.
- **Mappings.** A pad SDL does not know can be taught with one line of text, or a whole
  `gamecontrollerdb.txt`.
- **Virtual pads.** `gpVirtualAttach` makes a pad in software that is a pad in every way:
  on-screen touch controls, replayed input, and tests with no controller in the room.
- **The family's rules.** Nothing runs on a foreign thread into script: nothing happens
  between two `gpPoll` calls (rule 1); the shim is C and validates every argument, and SDL's
  asserts are counted, not fatal (rule 2); results of several values cross as one short text
  (rule 3); every handle is a generation-tagged integer, and a stale one is a harmless no-op
  (rule 4).

## Quick taste

```livecodescript
local sX, sY

on openCard
   if gpStart() then send "readPads" to me in 16 milliseconds
end openCard

on readPads
   local tPad, tStick, tEvent
   get gpPoll()                                     -- read every controller once
   put gpPadAt(1) into tPad                         -- the first pad, or 0 for none
   put gpPadStick(tPad, "left") into tStick         -- "x,y", each -1 to 1; empty for no pad
   if tStick is not empty then
      add item 1 of tStick * 6 to sX
      add item 2 of tStick * 6 to sY
      set the loc of graphic "player" to round(sX), round(sY)
   end if
   repeat for each line tEvent in gpEvents()        -- what happened since the last read
      if tEvent ends with ",south,down" then jump
   end repeat
   send "readPads" to me in 16 milliseconds
end readPads

on closeCard
   gpStop
end closeCard
```

[docs/getting-started.md](docs/getting-started.md) carries on from there.

## See it: Gamepad Lab

[examples/gamepad-lab.livecodescript](examples/gamepad-lab.livecodescript) is one window that
shows all of it. Paste it into a new stack's script, close the stack and open it again: the
window builds itself and starts playing. Five showcases play in turn on a touch pad made in
software (every button, sticks and the dead zone, rumble with the light and player numbers,
a button remapped, a small game), each a few seconds of one thing, with a button each to play
it again. Plug a controller in and it takes over at once with a buzz and a green light; one
already plugged in takes over at its first press. Then everything reads that pad: its buttons
and sticks in the drawing, its events in the log, Rumble, the light and the player number set
on it, and its mapping, which can be changed in place. The mouse and the keys drive the touch
pad too. With no gamepadxt installed the window still opens, says so, and plays the showcases
as a recording.

## Status

Joined the suite on 2026-11-20. What has run, and where:

- **Natively**, on x86_64 Linux: the smoke test calls every export of the shim and checks
  what comes back, clean under ASan/UBSan with SDL's own asserts switched on; a random-call
  test (`tests/fuzz_test.c`) throws valid, stale and hostile arguments at every export. Both
  also pass as a 32-bit build and as WebAssembly under node. All of it drives SDL's virtual
  pads, so it proves the shim and SDL's gamepad layer, NOT any operating system's way of
  reading a real controller.
- **On an engine**, the same day: `tests/engine-selftest.lc` ran on OXT-Beyond's headless
  Linux server engine (9.7.1-OXT, x86_64) over a locally built library. It loaded the module,
  passed the ABI check, attached virtual pads, read buttons, sticks, events, rumble and
  lights back through the binding, and called every public handler once.
- **The demo window**, Gamepad Lab, the same day: `tests/demo-drive.livecodescript` drove it
  on OXT-Beyond's Linux desktop engine with no display, over a locally built library and
  virtual pads: it opened playing, played its five showcases through, took every control,
  greeted a pad plugged in mid-run, kept its own colours and every word inside its box, and
  put the library back as it found it. Then again with no gamepadxt, where it plays a recording. The native lane runs
  both on every change. No person has used it at a screen and no real controller has driven
  it.
- **Not yet:** no real controller has been read through it on any platform, no desktop IDE
  has loaded it, and no engine on Windows, macOS or the web has run it: on those it is
  verified statically; needs an OXT pass (with a controller plugged in). Only the web
  archive is committed under `src/code/` (2026-11-21); the suite's release-binaries
  dispatch lands the desktop libraries.
- **Not built for Android or iOS.** SDL reaches controllers there through its own Java or
  Objective-C application layer, which an OXT app does not have.

## Building and testing

```sh
cmake -S . -B build -DGAMEPADXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release && cmake --build build -j && (cd build && ctest)
cmake -S . -B build-asan -DGAMEPADXT_BUILD_TESTS=ON -DGAMEPADXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug && cmake --build build-asan -j && (cd build-asan && ctest)
bash tools/run-gates.sh
```

A C compiler and CMake 3.22 are all it needs, plus the udev headers on Linux (`libudev-dev`);
SDL is fetched at configure time. [docs/building.md](docs/building.md) has the details.

## Documentation

- [docs/getting-started.md](docs/getting-started.md) - the loop, the button and axis names,
  events, dead zones, virtual pads, and what differs between platforms.
- [docs/api-reference.md](docs/api-reference.md) - every `gp*` handler, generated from the
  binding's doc blocks.
- [docs/building.md](docs/building.md) - builds, sanitizers, the tests, the gates.
- [CLAUDE.md](CLAUDE.md) - rules and gotchas for anyone changing this member.

## License

MIT (see [LICENSE](LICENSE)). SDL is Sam Lantinga's and its contributors', under the zlib
license, and carries HIDAPI under a BSD-style one; both notices are in the same file.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

gamepadxt is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`gamepadxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/gamepadxt: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `gamepadxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port gamepadxt --ref pull/<n>/head`, keeping its
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

- `tools/check-livecodescript.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

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
