# Building and testing midixt

You do not need any of this to USE midixt: the libraries ship inside the extension
(`src/code/<arch>-<platform>/`), landed by the suite's `release-binaries.yml`. This is for
changing it.

## What builds

ONE shared library, `midixt.{so,dll,dylib}` under its bare name (no `lib` prefix): the C
shim `src/midi_shim.c` and RtMidi 6.0.0, compiled together. RtMidi is fetched by CMake as
source at the commit its 6.0.0 tag names, and only its two files are compiled
(`RtMidi.cpp`, `rtmidi_c.cpp`); its own CMake is not run, because it exports every class,
adds a JACK dependency whenever the build machine has JACK's headers, and turns warnings
into errors in Debug builds. RtMidi picks the platform's MIDI service at compile time:

| Platform | Service | What the build needs |
|---|---|---|
| Linux | ALSA (`__LINUX_ALSA__`) | `libasound2-dev` (Debian, Ubuntu) or `alsa-lib-devel` (Fedora, RHEL); the library loads the system's `libasound.so.2` |
| macOS | CoreMIDI (`__MACOSX_CORE__`) | Xcode's command line tools |
| Windows | Windows MM (`__WINDOWS_MM__`) | Visual Studio 2019 or later |
| Android | none | refused at configure: RtMidi's Android backend needs API 29 and JNI, and the suite's Android floor is API 21 |
| Web (`wasm32-emscripten`) | the browser's Web MIDI, through `src/midi_web.c` | Emscripten 6.0.12; none of RtMidi's sources is compiled |

The shipped library exports `midi_*` and nothing else (`src/midixt.map` for GNU ld; the same
pattern for ld64), and carries its C and C++ runtimes inside it (`MIDIXT_STATIC_RUNTIME`, ON
by default: the static MSVC runtime on Windows, static libstdc++ and libgcc on Linux), so it
loads on a machine that has nothing but the system and the engine.

**The web archive** (`src/code/wasm32-emscripten/midixt.a`) is what OXT-Beyond's web engine
links in: ONE wasm object (`emcc -r`) holding the same shim over `src/midi_web.c`, midixt's
own Web MIDI layer, and `midixt_web_exports()`, the table of every `midi_*` the binding
binds, which CMake generates from `src/midi.lcb` (the engine finds the library through it).
RtMidi 6.0.0 has a Web MIDI backend, but a poll can never read from it (its input reaches
only a callback, and the shim registers none: rule 1), so `src/midi_web.c` implements the
part of RtMidi's C API the shim calls, its header comment says how, and the shim is
unchanged but for two things only the web build compiles: a virtual port is refused before
the browser is asked, and a failure carries the browser's reason after the shim's words.
The desktop libraries are built from the same shim, byte for byte as before.

## Build

A C17 and C++11 compiler and CMake 3.22:

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release -DMIDIXT_BUILD_TESTS=ON
cmake --build build --config Release
ctest --test-dir build --build-config Release --output-on-failure --no-tests=error
```

Under the sanitizers (gcc on Linux; the sanitizer build uses the shared runtime):

```sh
cmake -S . -B build-asan -DCMAKE_BUILD_TYPE=Debug -DMIDIXT_BUILD_TESTS=ON -DMIDIXT_SANITIZE=address
cmake --build build-asan && ctest --test-dir build-asan --output-on-failure
```

The web archive, with Emscripten 6.0.12 activated (`emsdk activate 6.0.12`) and node on the
PATH; the build copies the archive into `src/code/wasm32-emscripten/` unless
`-DMIDIXT_PLACE_IN_SRC=OFF`, and the same sources build the same bytes in any folder:

```sh
emcmake cmake -S . -B build-web -DMIDIXT_BUILD_TESTS=ON
cmake --build build-web && ctest --test-dir build-web --output-on-failure
```

## The tests

Everything runs headless, with no MIDI hardware and no MIDI service.

| Layer | What | How |
|---|---|---|
| C, real library | `tests/midi_smoke_test.c`: the real library over this machine's service, written to pass with or without one | ctest `midi_smoke` |
| C, mock | `tests/midi_mock_smoke_test.c`: the shim over `tests/mock/rtmidi_mock.c`, a controllable RtMidi double: the drain, the stash, the queue, and every way RtMidi 6.0.0 fails | ctest `midi_mock_smoke` |
| C, web | `tests/midi_web_test.c` under node, linked against the web archive itself, over `tests/web/fake-web-midi.js`, a stand-in for the browser's Web MIDI: five pages, one each with no Web MIDI, a refusal, a frame that does not allow MIDI, a question never answered, and MIDI granted (ports listed and opened, a loop cable, timing, the filters, the queue's limit, the browser's own refusals and their words, a port that went away, an open the browser refused) | the web build's ctest, `midi_web_*` |
| LCB | `tests/lcb/*.lcb` under lc-run: the real binding over the MOCK library (and `midi_hw_test` over the real one), plus the vectors module generated from `tests/vectors/midi.json` | `python3 tools/run-lcb-tests.py --oxt-bin <OXT bin folder> --build-dir build` |
| Script, in the engine | `tests/lcs/*.livecodescript` in the standalone engine with `-ui`: the Script-to-LCB boundary, the shipped helper's listener, the shipped self-test | `python3 tools/run-lcs-tests.py --oxt-bin <OXT bin folder> --build-dir build` |
| Static | the gates, compiler-free | `bash tools/run-gates.sh` |

The test build also makes the MOCK library, the shim over the RtMidi double, as
`build/mock/midixt.*` under the same bare name: a drop-in for the shipped library plus the
`midimock_*` controls (inject messages, loop outputs back to inputs, make RtMidi fail). The
LCB and Script suites load it to run the whole stack with no MIDI service. It must never
ship: `tools/package-extension.py` never picks it from a build folder and refuses a library
that exports `midimock_*` (`tests/package_extension_test.py` holds that).

**What the stand-in cannot show.** `fake-web-midi.js` does what a browser's Web MIDI does for
the calls midixt makes, and checks a send's bytes as Chrome does; it is a test double, not a
browser. A browser's own question to the person, the devices it lists and their names, its
timing, and what it does with a port another program holds are not in it: the web build is
verified statically and against the stand-in; needs a pass in a browser. A failing scene
fails twice over: by node's exit status and by its printed FAIL lines (ctest's
`FAIL_REGULAR_EXPRESSION`), because a main that has slept under Asyncify returns into
nothing, and before both, every scene of a layer broken on purpose passed.

The OXT folder for the two runners is any OXT build folder holding `lc-compile`, `lc-run` and
the standalone engine, or an OXT-Beyond `*-binaries` release archive unpacked; `$OXT_BIN`
works too. `MIDIXT_REQUIRE_ALL=1` turns every skip of the runners into a failure, and
`MIDIXT_REQUIRE_SERVICE=1` makes `selftest_hw_test` fail unless the self-test's loopback
through the real MIDI service ran (set it where ALSA's sequencer or CoreMIDI is there).

**Done means:** a shim change is green in ctest under `-DMIDIXT_SANITIZE=address`; a binding
change passes `run-lcb-tests.py` (lc-compile `-Werror`, as the Extension Builder compiles);
a Script change passes `run-lcs-tests.py`; all of them pass `bash tools/run-gates.sh`. New
behaviour gets a test in the matching layer, and a fix the test that would have caught it.

## The API reference is generated

`docs/api-reference.md` is written from the binding's `/** */` doc blocks by
`python3 tools/build-api-reference.py`; its `--check` is a gate. Edit the doc block, then
regenerate.

## Refreshing the committed libraries

The libraries under `src/code/` are committed only by the suite's `release-binaries.yml`, a
manual dispatch (pressing Run is the human decision the suite's rule 5 asks for); it builds
every platform, checks each library's name, format, architecture and exports, and refreshes
`src/code/MANIFEST.sha256`. The web archive is the exception, as every member's is: that
workflow builds none, so it is built by hand as above (the member's `web` CI job builds and
tests the same thing on every change) and committed with its line in the manifest. `tools/package-extension.py --build-dir build` copies a local
build into the tree for a test of your own; do not commit what it writes.

## Bumping the ABI

`MIDI_ABI_VERSION` in `src/midi_shim.h` and the literal in `checkABI()` of `src/midi.lcb`
move together, on any change to an export's name, arguments or meaning. The binding then
refuses a library of another ABI with a clear error instead of crashing on its first call.
