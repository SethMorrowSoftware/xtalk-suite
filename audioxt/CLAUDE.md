# CLAUDE.md

Guidance for Claude Code in the audioxt member of the xtalk-suite monorepo (`audioxt/`). Where
anything disagrees, the code and this file win.

## What this is

**audioxt** binds miniaudio (David Reid's single-header audio library, public domain or MIT-0)
for OXT: `miniaudio.h` (ONE file, fetched at an exact commit and held to a SHA-256 in
`CMakeLists.txt`) -> the C shim `src/audio_shim.c`, which compiles miniaudio into itself
(exports `aux_*`, **ABI 1**: `AUX_ABI_VERSION` there equals the literal in `checkABI()` of the
binding) -> ONE library `audioxt.{so,dll,dylib}` (bare token), or `audioxt.a` for the web ->
the LCB binding `src/audioxt.lcb` (`org.openxtalk.library.audioxt`, public `au*`). box3dxt is
its ancestor; read that member's CLAUDE.md for the reasons behind the shared shape.

**Additive only.** Nothing here touches the engine's `play` command, its player object or its
sound channels: the library opens its own device. A change that would alter what an existing
stack hears is out of bounds.

## The rules

1. **Never call script from a foreign thread.** miniaudio runs an audio thread per device and
   a job thread per engine; neither reaches script. A sound's end sets one atomic flag that
   `aux_poll_ended` collects on the script thread; the meter is written under a spinlock; a
   capture's thread fills a single-producer, single-consumer ring and (under a mutex) a WAV
   file. A new thing shared with those threads is named in the shim's header comment and run
   under TSan (`-DAUDIOXT_SANITIZE=thread`).
2. **Nothing crosses the boundary but values.** The shim is C: there is no exception to
   firewall. Every export validates its handles and arguments before it calls miniaudio, and
   nothing prints, aborts or throws. A refused call returns 0 or empty and sets
   `aux_last_error`.
3. **Text out is a Pointer, text in is ZStringUTF8.** Several numbers cross as one text
   (`"x,y,z"`) in a static buffer; the binding declares those returns `Pointer` and copies
   them with `textOf()`. NEVER `ZStringNative` (the engine frees a returned C string).
   `aux_text_length` is handed such a pointer back, so ITS parameter is `Pointer`, not
   `ZStringUTF8`: the first engine run of this binding (2026-11-20) failed on exactly that,
   and the signature gate refuses it since.
4. **Bytes out stay in ONE buffer the shim owns** (`aux_out_pointer`); the call returns the
   count and `dataOf()` copies at once. **Bytes in are copied by the shim before it
   returns**: nothing keeps a pointer into the engine's memory. The wrappers that return
   `Data` are exactly `DATA_OUT` in `tools/check-lcb-signatures.py`.
5. **Generation-tagged integer handles**, validated before use. A slot whose generation
   would wrap is retired, never reused.
6. **Names are mechanical.** `aux_sound_set_volume` is bound as `_sound_set_volume` and
   wrapped by `auSoundSetVolume`; nothing is renamed by hand (`tools/check-lcb-signatures.py`,
   fixture `tools/test-lcb-signatures.py`). An export needs at least two words after `aux_`:
   `lc-compile -Werror` refuses an all-lowercase handler name, which is why the calls are
   `aux_poll_ended` and `aux_shut_down`.
7. **Done means:** a shim change is green in `smoke` AND `fuzz` under
   `-DAUDIOXT_SANITIZE=address`, and `smoke` under `-DAUDIOXT_SANITIZE=thread`; a binding
   change passes `lc-compile -Werror` and `tests/engine-selftest.lc` on the server engine;
   a change the web can see passes `tests/web/run-web-test.cjs`; a demo change passes
   `tests/demo-drive.livecodescript` on the desktop engine, with the extension and without
   it (`AUDIOXT_LCM` empty); all pass `bash tools/run-gates.sh`. An ABI change bumps
   `AUX_ABI_VERSION` and the two literals in `checkABI()` together. Native-library changes
   refresh the committed binaries through the suite's `release-binaries.yml`;
   `native-audioxt.yml` never commits.

## Generated text: edit the source, then regenerate

| What | Written by |
|---|---|
| the declaration blocks of both C tests, the fuzz call table | `tools/check-smoke-coverage.py --write` |
| `sweepEveryHandler` in `tests/engine-selftest.lc` | `tools/check-lcb-signatures.py --write` |
| `docs/api-reference.md` | `tools/build-api-reference.py` |

## As built

- **An engine with no sound mixes nothing and its clock stands still** in miniaudio, so each
  engine holds a hidden, silent group (`keepAlive`) that keeps the graph running.
- **A sound's end is seen in the block AFTER the one that reached it.** Tests render one more
  block before they poll.
- **An engine is created stopped and started last** (`noAutoStart`, then `ma_engine_start`):
  started first, the audio thread read the shim's struct while it was being filled (TSan).
- **A WAV encoder is heap-allocated**: `ma_encoder` holds a pointer to itself and cannot be
  copied by value (ASan, stack-use-after-return).
- **Device -1 is miniaudio's null backend**: a real device thread on a real clock, no sound
  card. It is what the tests and the engine self-test play and record through. It does not
  exist in the web build.
- **The web build has no threads** (`MA_NO_THREADING` is implied by Emscripten without
  pthreads): the resource manager's jobs are pumped by `pump_jobs()` from `aux_poll_ended`
  and `aux_engine_render`. Web Audio is reached through a ScriptProcessorNode on the main
  thread; the AudioWorklet path would need flags on the ENGINE's link line.
- **On the web the shim asks the page before miniaudio does** (`web_device_ok`): miniaudio's
  JavaScript calls `new AudioContext()` and `navigator.mediaDevices.getUserMedia` as if both
  were there, and a JavaScript throw unwinds through every WebAssembly frame above it, the
  web engine's main loop included. A page with no Web Audio refuses every device, and one
  with no microphone API (a page served over plain http has none) refuses a capture, each
  with a reason. Found linking the archive the way the web engine does (2026-11-21).
- **A key press or a mouse button starts a held web device**: a browser holds a device opened
  before the visitor's first gesture, and miniaudio resumes it on a click or a touchend only.
  The shim adds one capture-phase listener per page for `keydown` and `mousedown` that
  resumes miniaudio's started devices and removes itself after the first resume that
  succeeds. Escape is no gesture: its resume stays pending until a real one.
- **JACK is compiled out** (`MA_NO_JACK`): asking for a JACK server can start one.
- **No Ogg Vorbis.** miniaudio decodes it only through stb_vorbis, which is not in the header
  and has a history of memory-safety reports; WAV, FLAC and MP3 are miniaudio's own.
- **No brown noise**: miniaudio's wanders to 1.34 at amplitude 0.25 (measured).
- **Only `aux_*` is exported**: `src/audioxt.map` for GNU ld and the same pattern for ld64.

## The demo

`examples/audioxt-demo.livecodescript` (Sound Stage) wears OXT-Beyond's showcase look, which
the owner asked of every new extension's demo (2026-11-21), not the suite's light UI kit
(the suite's `check-ui-kit-drift.py` exempts it, naming the drive): a dark stage, the
header with OXT-Beyond's name, the demo's, one line on what it does and "by Seth Morrow";
straight into motion on open; scenes of 5 to 15 seconds; ONE timer, the screen locked per
frame and nothing waiting; long work a piece a frame with its progress shown. Every field
and button gets its own text and background colours (a system in dark mode gives a control
with none white text, seen on Windows), and no control is a system tick box, menu or
slider. The drive checks those, that no words are cut off (in Linux's font, which is wider
than Windows'), and every scene at its moments. With `AUDIOXT_SHOTS=<folder>` and a display
it saves a picture of each moment: copy the drive to `Toolset/home.rev` in the windowed
engine's working folder and run the engine with no arguments (`export snapshot` needs a
window; `-ui` has none).

The window is built with messages locked, and the lock is then RESTORED, not lifted (the
stack builder calls the build with messages locked already): an IDE answers every control a
script makes, names or deletes (engine note 5.15), and built with messages on, Sound Stage's
stack file froze OXT-Beyond 0.2.8-dp.1's IDE on Windows for 59 s (2026-11-21; built locked, it
opened there in 796 ms the same day). Its `preOpenStack` then places the window on a working
screen, title bar included, on the desktop only (`adPlaceWindow`; in a browser the Stack Player
lays the page out): sized round the engine's first centre, the file opened at -320,-140 there
(engine note 5.17), and `examples/build-demo-stack.livecodescript` now saves it at 160,60. The
drive holds both: an ear in front of every object hears no create, name or delete during the
build (the old build sent 520), and in a windowed engine the window opens on the screen.

## Gotchas

1. **A path ending in `.` is refused by the shim** (`path_ok`): miniaudio's
   `ma_path_extension` reads one byte past such a path (found by the fuzz test under ASan).
2. **The server engine cannot create a file with a non-ASCII name in the C locale**, so
   `tests/engine-selftest.lc` prints `INFO SKIPPED ...` there; the native lane runs it with
   `LC_ALL=C.UTF-8` and refuses a run that skipped.
3. **The mixer works in floats**: 16-bit samples played through an engine come back within
   one step, not bit for bit. `auDecodeData` of `auWAVEncode` IS bit for bit (no mixer).
4. **ALSA prints to stderr** when a machine has no sound card (`ALSA lib ... cannot find card
   '0'`). It is ALSA's own handler, process-global, so the shim does not replace it.
5. **TSan needs `tests/tsan.supp`** for one unsynchronised float inside miniaudio (the pan);
   the file says why. Nothing of the shim is suppressed.
6. **The sweep must not open device 0**, the machine's real sound device: `SWEEP_ARGS` in the
   signature gate passes -1 to `auEngineCreate`, and the fixture test holds that.

## Status

Verified natively (smoke and fuzz, ASan/UBSan and TSan, x86_64 Linux; wasm under node), on
the headless Linux server engine (`tests/engine-selftest.lc`, 2026-11-20, a locally built
library, through the silent device), in headless Chromium (`tests/web/`, the archive called
from C) and in the IDE on Windows (2026-11-21, the maintainer's 64-bit OXT-Beyond: a CI-built
`x86_64-win32` DLL loaded on WASAPI and `tests/engine-selftest.lc`, run as a script-only
stack, passed 89 and failed 0). No engine on macOS, Android or the web has loaded it, and
nobody has HEARD it: verified statically; needs an OXT pass. The demo ran on the Linux desktop engine
through the silent device, headless and in a window (`tests/demo-drive.livecodescript`,
2026-11-21). The same day it played in the IDE on the maintainer's Windows PC (0.2.8-dp.1)
through a real sound device, by its own status line, meters and oscilloscope (nobody
listened), and opened off the screen and in 59 s there; both were fixed that day: the
fixed stack opened in 0.14 s in that release's IDE on Linux, against 1.8 s before, and in
796 ms back on that Windows PC, on the screen, the beat playing by its meters. Release
libraries were committed on 2026-11-21 (six desktop platforms and four Android ABIs from the
suite's release run; the web archive, Emscripten 6.0.12, built separately). The `x86_64-linux`
one was loaded that day by OXT-Beyond 0.2.8-dp.1's desktop engine (the drive) and its IDE
(Sound Stage opened there); no engine has loaded the others yet. Open work is in the suite's
`docs/WORK-PLAN.md`.
