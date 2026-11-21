# Building audioxt

## Dependencies

CMake 3.22+, a C17 compiler, and network access on the first configure: `miniaudio.h` is
fetched from its repository at the commit `CMakeLists.txt` pins and held to a SHA-256. To
build with no network, put that exact file in a folder and pass
`-DAUDIOXT_MINIAUDIO_DIR=<folder>` (it is held to the same hash).

Nothing else is needed on any platform, and in particular no audio library or header:
miniaudio finds the system's audio at RUN time (PulseAudio and ALSA on Linux, WASAPI on
Windows, Core Audio on macOS, AAudio and OpenSL ES on Android). So the library builds on a
machine with no audio installed and loads on one with no sound card.

## Build and test

```sh
cmake -S . -B build -DAUDIOXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
(cd build && ctest --output-on-failure)
```

That makes `build/audioxt.so` (`.dylib`, `.dll`) and runs two tests. Neither needs a sound
card: devices are miniaudio's silent null device, which runs a real device thread.

- `smoke` (`tests/smoke_test.c`) calls every export of the shim and checks the results.
- `fuzz` (`tests/fuzz_test.c`) makes random calls with valid, stale and hostile arguments.
  `audioxt_fuzz <seed> <calls>` runs one seed; `AUDIOXT_FUZZ_TRACE=1` prints each call.

A machine with no sound card prints `ALSA lib ...` lines on stderr during the device scan.
They are ALSA's own and mean only that it found no card.

Under the sanitizers (a shim change is done when these are green):

```sh
cmake -S . -B build-asan -DAUDIOXT_BUILD_TESTS=ON -DAUDIOXT_SANITIZE=address
cmake --build build-asan -j && (cd build-asan && ctest --output-on-failure)

cmake -S . -B build-tsan -DAUDIOXT_BUILD_TESTS=ON -DAUDIOXT_SANITIZE=thread
cmake --build build-tsan -j
TSAN_OPTIONS="suppressions=$PWD/tests/tsan.supp" build-tsan/audioxt_smoke
```

`tests/tsan.supp` names one unsynchronised float inside miniaudio and says why.

## The web (wasm32-emscripten)

```sh
emcmake cmake -S . -B build-web -DAUDIOXT_BUILD_TESTS=ON
cmake --build build-web -j && (cd build-web && ctest --output-on-failure)
node tests/web/run-web-test.cjs build-web
```

A browser loads no library, so the web build is a static archive, `audioxt.a`, for
OXT-Beyond's web engine to link in: the shim with miniaudio inside it, and a generated table
of the symbols the binding names (`audioxt_web_exports`). The two C tests run against that
archive under node, which has no Web Audio: they cover the mixer, the decoders and every
refusal. `tests/web/run-web-test.cjs` covers the device: it opens `tests/web/page.c` (the
archive behind a few calls) in headless Chromium through Playwright, clicks once, and checks
that the clock runs, the meter reads the tone and Chromium's fake microphone delivers
samples. It then takes away, on fresh pages, what miniaudio's own JavaScript takes for
granted (the microphone API, which a page served over plain http lacks, and the
AudioContext): the shim must refuse with a reason where miniaudio would have thrown through
the whole engine. Last, pages that open the device at load, before any gesture, show it held
silent until a key press, a mouse button or a click, and still held after Escape (no
gesture); the test never calls into those pages, because in Playwright a `page.evaluate`
counts as a gesture. No web engine has linked the archive yet.

## The engine self-test

`tests/engine-selftest.lc` runs on OXT-Beyond's headless server engine over a built library:

```sh
lc-compile -Werror --modulepath <engine>/modules/lci --modulepath out --output out/audioxt.lcm src/audioxt.lcb
LC_ALL=C.UTF-8 server-community tests/engine-selftest.lc out/audioxt.lcm build/audioxt
```

The second argument is the library's path without its extension. It prints PASS and FAIL
lines and a `SUMMARY passed failed` line, and exits non-zero on any failure. In the C locale
the engine cannot create a file with a non-ASCII name, so that one check prints
`INFO SKIPPED`; run it with a UTF-8 locale. Part of it is generated: a sweep that calls every
public handler once (`tools/check-lcb-signatures.py --write`).

## The gates

```sh
bash tools/run-gates.sh
```

`tools/run-gates.sh` is the member's whole compiler-free list. After changing the shim's
exports, run `python3 tools/check-smoke-coverage.py --write` (the tests' declaration blocks and
the fuzz table) and `python3 tools/check-lcb-signatures.py --write` (the engine sweep); after
changing a doc block, `python3 tools/build-api-reference.py`.

## Release libraries

None are committed yet. They come from the suite's `release-binaries.yml` dispatch, never from
a developer's machine.
