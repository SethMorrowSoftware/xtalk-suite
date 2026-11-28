# audioxt

**Sound - many sounds at once, streamed music, tones, 3D and the microphone - for OpenXTalk /
the xTalk family.**

[miniaudio](https://miniaud.io) is David Reid's audio library: one C header that plays and
records on every desktop, Android and the web, mixes any number of sounds with low delay,
and decodes WAV, FLAC and MP3 itself. It is public domain (or MIT No Attribution). audioxt
binds it behind the family's flat C shim and a thin LCB layer:

```
miniaudio (one header, pinned to a commit and a SHA-256)        the audio engine
   |- C shim   src/audio_shim.c  ->  audioxt.{so,dll,dylib}     (ABI: aux_*, v1)
        |- LCB binding  src/audioxt.lcb     (org.openxtalk.library.audioxt; public au*)
```

It is a second way to make sound, beside the engine's own. The `play` command, the player
object and every stack that uses them work exactly as they did: audioxt opens its own device
and touches nothing of theirs.

## What it can do

- **Many sounds at once.** An engine is a mixer on one sound device; every sound has its own
  volume, pan and pitch, and one loaded effect can be played any number of times at once
  (`auSoundClone`).
- **Music and effects.** A sound is decoded whole into memory (effects that must start at
  once) or streamed from disk while it plays (music), from a WAV, FLAC or MP3 file or from
  the bytes of one held in a custom property.
- **Exact timing.** Sounds start and stop on the mixer's own sample clock
  (`auSoundStartAt`), so a beat does not drift with the script's timers. Fades, loops and
  loop ranges are done by the mixer.
- **Groups.** One volume, pan and pitch for many sounds: a music slider and an effects slider.
- **3D.** A sound can have a place and a velocity, heard from a listener: distance, direction
  and Doppler.
- **Made sound.** Sine, square, triangle and sawtooth tones, white and pink noise, and sounds
  built from raw samples a script computed.
- **The microphone.** Opened in the format asked for; read as samples on a timer, or written
  straight to a WAV file with no script in between.
- **The samples themselves.** Decode a file to raw samples, wrap samples as a WAV file,
  render a whole mix offline as fast as the computer can, read a level meter and an
  oscilloscope trace.
- **The family's rules.** miniaudio's threads never call script (rule 1): a stack asks which
  sounds ended (`auPollEnded`). Every export validates before it calls miniaudio and none
  can throw across the boundary (rule 2). Results of several numbers cross as one short text
  (rule 3). Every handle is a generation-tagged integer, and a stale one is a harmless no-op
  (rule 4).

## See it first

`examples/audioxt-demo.livecodescript` is **Sound Stage**, a dark stage that opens playing:
a beat started on the mixer's own clock, a sound that circles your head and flies past, a
synth gliding through its four shapes into a chord, a tape mixed in script, written as a WAV
file and streamed back, and your microphone heard and played back, with a live oscilloscope
and level meters under every scene and one button that runs every check of the window.
Paste it into a stack's script and reopen the stack, or make a stack file of it with
`examples/build-demo-stack.livecodescript` and open that. It needs nothing but the
extension: every sound is made in script, and without a sound device or the extension it
says so plainly.

## Quick taste

```livecodescript
local sEngine, sMusic, sClick

on openStack
   put auEngineCreate(0, 0, 0) into sEngine                    -- the default device, its own format
   put auSoundLoad(sEngine, specialFolderPath("resources") & "/theme.mp3", true) into sMusic
   auSoundSetLooping sMusic, true
   auSoundFade sMusic, 0, 1, 2                                 -- fade in over two seconds
   auSoundStart sMusic
   put auSoundLoad(sEngine, specialFolderPath("resources") & "/click.wav", false) into sClick
end openStack

on mouseUp
   local tShot
   put auSoundClone(sClick) into tShot                         -- so clicks can overlap
   auSoundSetAutoFree tShot, true
   auSoundStart tShot
   get auPollEnded()                                           -- frees the clicks that finished
end mouseUp

on closeStack
   auShutDown
end closeStack
```

[docs/getting-started.md](docs/getting-started.md) carries on from there.

## Status

Joined the suite on 2026-11-20. What has run, and where:

- **Natively**, on x86_64 Linux: the smoke test calls every export of the shim and checks what
  comes back (a WAV round trip bit for bit, FLAC and MP3 decoded, sounds played to their end
  through an offline mixer and through miniaudio's silent device, a microphone recorded to a
  file), clean under ASan/UBSan and under TSan; a random-call test (`tests/fuzz_test.c`)
  throws valid, stale and hostile arguments at every export. Both also pass as WebAssembly
  under node.
- **On an engine**, the same day: `tests/engine-selftest.lc` ran on OXT-Beyond's headless
  Linux server engine (9.7.1-OXT, x86_64) over a locally built library. It loaded the module,
  passed the ABI check, rendered a tone and measured it, sent binary data both ways,
  loaded files by path (one with a name that is not ASCII), played and recorded through the
  silent device, and called every public handler once.
- **In a browser**, the same day: the web archive, called from C as the web engine will call
  it, opened Web Audio in headless Chromium, played a tone after one click and recorded from
  Chromium's fake microphone (`tests/web/`).
- **A longer web buffer**, 2026-11-28 (0.1.1): a page that sets `window.audioxtWebBuffer`
  (milliseconds) before it makes an engine gets a buffer that long or longer, so a stack that
  holds the page for a long frame is not heard to crackle. In headless Chromium a page that
  asked for 80 ms got 4096 frames, and one that asked for nothing kept 2048
  (`tests/web/run-web-test.cjs`, 38 checks). No web engine has linked this archive yet:
  verified statically; needs an OXT pass.
- **In the IDE on Windows**, 2026-11-21: on the maintainer's PC, in their installed 64-bit
  OXT-Beyond (its version not recorded), the binding compiled with that install's
  `lc-compile` over a CI-built `x86_64-win32` DLL (the native lane's build of 7dcbb41) loaded
  and answered `audioxt ABI 1; miniaudio 0.11.26` on WASAPI, and `tests/engine-selftest.lc`,
  run inside the IDE as a script-only stack, passed 89 and failed 0.
- **The demo**, Sound Stage, on 2026-11-21: `tests/demo-drive.livecodescript` drove it on
  OXT-Beyond's Linux desktop engine (9.7.1-OXT) over a locally built library, with no sound
  card (so through the silent device, as the window itself chooses), headless and in a
  window: every scene played and checked at its moments, its own checks green, every field
  and button with its own colours, no words cut off; and without the extension the window
  said so and survived every click. The native lane repeats that on every change. The same
  day it played in the IDE on the maintainer's Windows PC (OXT-Beyond 0.2.8-dp.1) through a
  real sound device: its status line named the device at 48,000 Hz and 2 channels, the beat
  played, the oscilloscope drew and both meters moved. Nobody listened, so that is the demo's
  own report. It opened off the screen there, and took 59 s to open; both were fixed the same
  day (the window built with messages locked and placed on the screen when it opens), and in
  that release's IDE on Linux the fixed stack file opened in 0.14 s, against 1.8 s before.
  Back on the Windows PC the fixed demo opened in 796 ms, at 160,60 inside the screen's
  working area, the beat machine playing by its meters (a stack made in that IDE with the
  builder's steps and the fixed script, its SHA-256 checked: the file itself could not be
  copied there).
- **On OXT-Beyond's web engine**, 2026-11-22: OXT-Beyond 0.2.8-dp.2.1's web Stack Player,
  whose engine links the committed web archive (pinned there by SHA-256), played Sound Stage
  in headless Chromium, in a play page made as the community stacks gallery makes one (a
  frame with no `allow-same-origin` and no microphone). Its status line read `audioxt ABI 1;
  miniaudio 0.11.26 | playing through Default Playback Device, 44,100 Hz, 2 channels`; before
  the first click the browser held the sound, and after it every scene of Play all ran, the
  oscilloscope and both meters moving. Nobody listened. The microphone scene, refused a
  microphone by the page, showed its reason for one frame, and its status line was cut off
  at its end; both were fixed the same day, and in that player the fixed stack showed the
  reason for four seconds and the whole line.
- **Not yet:** nobody has HEARD it: the runs above played through the silent device,
  rendered into memory or, for the demo on Windows and in the browser, played through a
  real device with nobody listening. No engine on macOS or Android has run it: on those it
  is verified statically; needs an OXT pass. The libraries committed under `src/code/` on
  2026-11-21 (six desktop platforms, four Android ABIs, a web archive) were tested where
  they were built; of them, the `x86_64-linux` one (OXT-Beyond 0.2.8-dp.1's desktop engine
  and IDE, running the demo, 2026-11-21) and the web archive (0.2.8-dp.2.1's web engine,
  2026-11-22) have been loaded by an engine.

## Building and testing

```sh
cmake -S . -B build -DAUDIOXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release && cmake --build build -j && (cd build && ctest)
cmake -S . -B build-asan -DAUDIOXT_BUILD_TESTS=ON -DAUDIOXT_SANITIZE=address && cmake --build build-asan -j && (cd build-asan && ctest)
bash tools/run-gates.sh
```

A C17 compiler and CMake 3.22 are all it needs; `miniaudio.h` is fetched at configure time and
no audio library or header has to be installed. [docs/building.md](docs/building.md) has the
details.

## Documentation

- [examples/audioxt-demo.livecodescript](examples/audioxt-demo.livecodescript) - Sound
  Stage, the showcase: each scene's code is one capability, written to be read.
- [docs/getting-started.md](docs/getting-started.md) - engines and sounds, the timer that
  polls, the microphone, the limits, the rules that decide whether a sound is heard.
- [docs/api-reference.md](docs/api-reference.md) - every `au*` handler, generated from the
  binding's doc blocks.
- [docs/building.md](docs/building.md) - builds, sanitizers, the tests, the gates.
- [CLAUDE.md](CLAUDE.md) - rules and gotchas for anyone changing this member.

## License

MIT (see [LICENSE](LICENSE)). miniaudio is David Reid's, public domain or MIT No Attribution;
its notice is in the same file.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

audioxt is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`audioxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/audioxt: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `audioxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port audioxt --ref pull/<n>/head`, keeping its
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
