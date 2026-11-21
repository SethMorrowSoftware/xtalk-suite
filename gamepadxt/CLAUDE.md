# CLAUDE.md

Guidance for Claude Code in the gamepadxt member of the xtalk-suite monorepo (`gamepadxt/`).
Where anything disagrees, the code and this file win.

## What this is

**gamepadxt** binds SDL 3's gamepad subsystem (zlib license) for OXT: SDL (static,
FetchContent, pinned to a release COMMIT in `CMakeLists.txt`, built with everything but the
joystick, haptic and HIDAPI parts switched off) -> the C shim `src/gamepad_shim.c` (exports
`gpx_*`, **ABI 1**: `GPX_ABI_VERSION` there equals the literal in `checkABI()` of the
binding) -> ONE library `gamepadxt.{so,dll,dylib}` (bare token), or `gamepadxt.a` for the web
-> the LCB binding `src/gamepadxt.lcb` (`org.openxtalk.library.gamepadxt`, public `gp*`).
box3dxt is the member its shape was taken from.

## The rules

1. **Never call script from a foreign thread.** Nothing reaches script at all: a script calls
   `gpPoll` from a timer and reads `gpEvents`. SDL's own threads (Windows raw input and
   hot-plug, the HIDAPI rumble thread) never leave SDL; the shim registers no callback but
   the virtual pads' rumble and light hooks, which run inside the shim's own calls.
2. **SDL is a guest in somebody else's process.** The engine owns the window, the message
   loop and the signals. So, before `SDL_Init`: no signal handlers, no timer-resolution
   change, background input on (SDL has no window to be "focused" in), and the shim NEVER
   calls `SDL_PumpEvents`: it calls `SDL_UpdateGamepads` and takes its events with
   `SDL_PeepEvents`, discarding whatever else SDL queued. Only the JOYSTICK, GAMEPAD and
   HAPTIC subsystems are ever initialised. SDL's log is silenced and its assertion handler
   replaced (counted by `gpx_assert_count`, never an abort or a dialog).
3. **Several values cross as one text**, in a static buffer returned as a `const char *`.
   The binding declares those returns `Pointer` and copies them with `textOf()`. NEVER
   `ZStringNative` or `ZStringUTF8` as a RETURN: the engine frees a returned C string, and
   freeing a static buffer kills the engine. Text ARGUMENTS are `ZStringUTF8`, which the
   engine builds and frees itself. The signature gate holds both.
4. **Generation-tagged integer handles**, validated before use. A pad's handle dies when its
   controller is unplugged; a slot whose generation would wrap is retired, never reused.
5. **Every argument is checked in the shim**: a NULL or unknown name, a number that is not
   finite or out of its stated range, a stale handle. A refused call returns 0 or empty and
   sets `gpx_last_error`; nothing throws but the binding's ABI check.
6. **Names are mechanical.** `gpx_pad_set_player` is bound as `_gpx_pad_set_player` and
   wrapped by `gpPadSetPlayer` (the tokens `abi`, `guid` and `led` are upper-cased); nothing
   is renamed by hand (`tools/check-lcb-signatures.py`, fixture
   `tools/test-lcb-signatures.py`).
7. **Additive only.** A released handler keeps its name, its parameters and what it returns;
   an event line keeps its shape. New things get new names.
8. **Done means:** a shim change is green in `smoke` AND `fuzz` under
   `-DGAMEPADXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug` (Debug so SDL's asserts are in);
   a binding change passes `lc-compile -Werror` and `tests/engine-selftest.lc` on the server
   engine; both pass `bash tools/run-gates.sh`. An ABI change bumps `GPX_ABI_VERSION` and
   the two literals in `checkABI()` together. Native-library changes refresh the committed
   binaries through the suite's `release-binaries.yml`; `native-gamepadxt.yml` never commits.

## Generated text: edit the source, then regenerate

| What | Written by |
|---|---|
| the declaration blocks of both C tests, the fuzz call table | `tools/check-smoke-coverage.py --write` |
| `sweepEveryHandler` in `tests/engine-selftest.lc` | `tools/check-lcb-signatures.py --write` |
| `docs/api-reference.md` | `tools/build-api-reference.py` |

## As built

- **Text results share ONE static buffer**: the next text call overwrites it. The binding
  copies at once; a C caller must copy before it asks again. Numbers are printed with a `.`
  in every locale, to four decimals.
- **Starts are counted** (`gpx_start` / `gpx_stop`), so two stacks do not stop each other.
  The last stop closes every pad and `SDL_Quit`s the subsystems.
- **The event queue holds 4096 lines**; when full the OLDEST goes and `gpx_dropped_events`
  counts it. At most 64 pads are open at once.
- **Axis events are off by default** (a stick at rest jitters): `gpx_set_axis_events(step)`
  turns them on, the step measured from the last value REPORTED. The baseline follows the
  stick while events are off, and coming to rest at the centre or an end is always reported.
- **SDL holds back the guide button's release EVENT for 250 ms** after its press (some pads
  send the two together). The state (`gpx_pad_button`) reads up at once.
- **`SDL_AddGamepadMappingsFromFile` takes only lines whose `platform:` field names this
  system**; a line with no platform field is skipped too. `gpx_add_mapping` takes any line.
- **SDL's dynamic API stays on**: its jump table keeps all of the cut-down SDL in the link,
  which is why the library is about 2.4 MB stripped and why `--gc-sections` gains nothing.
  It also means the `SDL3_DYNAMIC_API` environment variable can point SDL at another build,
  as it can for every SDL program.
- **Linux needs libudev at BUILD time** (hot-plug and device names without it are a polling
  fallback): the configure fails without the header unless `-DGAMEPADXT_ALLOW_NO_UDEV=ON`.
  At run time SDL loads `libudev.so.1` itself and works without it.
- **The web build** reads the browser's Gamepad API, which shows a controller to a page only
  after a button on it is pressed. Under node (the tests) there is no such API and only
  virtual pads exist.
- **Only `gpx_*` is exported**: `src/gamepadxt.map` for GNU ld, the same pattern for ld64.
- **No Android, no iOS**: SDL needs its own Java activity or UIKit delegate there. The
  packager names no Android id and the suite's `tools/build-android.sh` does not build it.

## Gotchas

1. **A one-word all-lowercase LCB name warns, and the Extension Builder runs `-Werror`**: a
   foreign handler named `_start` or `_pads` does not compile. That is why the foreign name
   carries the whole symbol (`_gpx_start`), and why the helper is `asInt`.
2. **Virtual pads test the shim, not the OS.** A green run says nothing about evdev,
   XInput, GameInput or IOKit. Only a real controller on a real engine does.
3. **Button and axis positions equal SDL's enum values**: the shim's name tables are in
   that order and the virtual pad is attached with every button and axis, so index == enum.
   No test on virtual pads could see that break, so the shim holds it with compile-time
   asserts beside the tables.
4. **`SDL_UNIX_CONSOLE_BUILD=ON`** is what lets SDL configure with no X11 or Wayland.
5. **The demo window keeps its own colours, so it draws its own scroll bars.** The engine
   draws a field's scroll bar light whatever the field's colours (suite engine note 5.16), so
   Gamepad Lab's log and mapping box have none: the wheel arrives as `rawKeyDown` 65308 and
   65309 and `glWheel` scrolls them, and `glScrollMark` draws a thin bar. A mapping has no
   space but in the pad's name and the engine breaks a line only at a space, so the box shows
   a space after each comma and `glMappingRead` takes them out again.
   `tests/demo-drive.livecodescript` refuses a field with a scroll bar, words cut off at any
   box's edge and a colour pair under 4.5 to 1: it stands in for the UI kit's gate, which
   exempts the demo (`tools/check-ui-kit-drift.py` in the suite).
6. **A stack the drive creates is already open** (suite engine note 5.5): `go` to it sends
   no opening message, so the drive closes it and goes to it again, as a person does after
   pasting.

## Status

Verified natively (smoke and fuzz over virtual pads, ASan/UBSan, 64-bit, 32-bit and wasm
under node) and on the headless Linux server engine (`tests/engine-selftest.lc`, 2026-11-20,
a locally built library). The demo window, `examples/gamepad-lab.livecodescript`, ran on the
Linux desktop engine with no display (`tests/demo-drive.livecodescript`, 2026-11-21: every
showcase and control, a pad plugged in mid-run, with the library and without). No real
controller, no desktop IDE and no other platform's engine has run it: verified statically;
needs an OXT pass. Only the web archive is committed
(`src/code/wasm32-emscripten/`, 2026-11-21); the desktop libraries are not yet. Open work
is in the suite's `docs/WORK-PLAN.md`.
