# Building gamepadxt

## Dependencies

CMake 3.22+, a C compiler, and network access on the first configure: SDL is fetched from its
repository at the release commit `CMakeLists.txt` pins (`GAMEPADXT_SDL_COMMIT`). To build with
no network, clone SDL yourself, check that commit out and pass
`-DFETCHCONTENT_SOURCE_DIR_SDL3=<path>`.

On Linux the udev headers are needed too (`libudev-dev` on Debian and Ubuntu, `systemd-devel`
on Fedora and the manylinux images): with them SDL sees a controller the moment it is plugged
in. The configure stops without them; `-DGAMEPADXT_ALLOW_NO_UDEV=ON` builds anyway, for a
library that polls instead. Windows and macOS need nothing beyond their SDKs.

SDL is built with everything but its joystick, haptic and HIDAPI parts switched off: no video,
no audio, no window. The options are all in `CMakeLists.txt`.

## Build and test

```sh
cmake -S . -B build -DGAMEPADXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
(cd build && ctest --output-on-failure)
```

That makes `build/gamepadxt.so` (`.dylib`, `.dll`) and runs two tests:

- `smoke` (`tests/smoke_test.c`) calls every export of the shim and checks the results.
- `fuzz` (`tests/fuzz_test.c`) makes random calls with valid, stale and hostile arguments
  and checks the library's invariants as it goes. `gamepadxt_fuzz <seed> <calls>` runs one seed; `FUZZ_TRACE=1` prints
  each call and `--replay <file>` re-runs a trace.

Both drive SDL's virtual pads, so they need no controller and no permission to read one. For
the same reason they prove the shim and SDL's gamepad layer, not the operating system's way
of reading a real pad.

Under the sanitizers, in a Debug build so that SDL's own asserts are compiled in (a shim
change is done when this is green):

```sh
cmake -S . -B build-asan -DGAMEPADXT_BUILD_TESTS=ON -DGAMEPADXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug
cmake --build build-asan -j && (cd build-asan && ctest --output-on-failure)
```

SDL's asserts are on in a Debug or sanitizer build and off in Release. The shim installs an
assertion handler that counts and continues, so an assert is a test failure with a message,
never an abort or a dialog.

## 32-bit x86

`-DCMAKE_C_FLAGS=-m32` (with gcc's multilib and the 32-bit udev package, `libudev-dev:i386`,
installed) builds the 32-bit library.

## The web (wasm32-emscripten)

```sh
emcmake cmake -S . -B build-web -DGAMEPADXT_BUILD_TESTS=ON
cmake --build build-web -j && (cd build-web && ctest --output-on-failure)
```

A browser loads no library, so the web build is a static archive, `gamepadxt.a`, for
OXT-Beyond's web engine to link in: the shim, SDL, and a generated table of the symbols the
binding names (`gamepadxt_web_exports`). There SDL reads the browser's Gamepad API. The two
tests run against that archive under node, where no such API exists and only virtual pads
do. No web engine has linked it yet.

## The engine self-test

`tests/engine-selftest.lc` runs on OXT-Beyond's headless server engine over a built library:

```sh
lc-compile -Werror --modulepath <engine>/modules/lci --modulepath out --output out/gamepadxt.lcm src/gamepadxt.lcb
server-community tests/engine-selftest.lc out/gamepadxt.lcm build/gamepadxt
```

The second argument is the library's path without its extension. It prints PASS and FAIL
lines and a `SUMMARY passed failed` line, and exits non-zero on any failure. Part of it is
generated: a sweep that calls every public handler once (`tools/check-lcb-signatures.py
--write`).

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
