# Building box3dxt

## Dependencies

CMake 3.22+, a C17 compiler, and network access on the first configure: Box3D is fetched
from its repository at the commit `CMakeLists.txt` pins (`BOX3DXT_BOX3D_COMMIT`). To build
with no network, clone Box3D yourself, check that commit out and pass
`-DFETCHCONTENT_SOURCE_DIR_BOX3D=<path>`. Nothing else is needed on any platform: Box3D has no
dependencies of its own.

## Build and test

```sh
cmake -S . -B build -DBOX3DXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
(cd build && ctest --output-on-failure)
```

That makes `build/box3dxt.so` (`.dylib`, `.dll`) and runs two tests:

- `smoke` (`tests/smoke_test.c`) calls every export of the shim and checks the results.
- `fuzz` (`tests/fuzz_test.c`) makes random calls with valid, stale and hostile arguments
  and audits the worlds. `box3dxt_fuzz <seed> <calls>` runs one seed; `FUZZ_TRACE=1` prints
  each call, `FUZZ_AUDIT=1` audits after every call, and `--replay <file>` re-runs a trace.

Under the sanitizers, in a Debug build so that Box3D's own asserts are compiled in (a shim
change is done when this is green):

```sh
cmake -S . -B build-asan -DBOX3DXT_BUILD_TESTS=ON -DBOX3DXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug
cmake --build build-asan -j && (cd build-asan && ctest --output-on-failure)
```

Box3D compiles its asserts into Debug and RelWithDebInfo builds and out of Release. The shim
installs an assert handler that counts and continues, so an assert is a test failure with a
message, never an abort.

## 32-bit x86

`-DCMAKE_C_FLAGS=-m32` (with gcc's multilib installed) builds the 32-bit library. The CMake
file adds `-msse2 -mfpmath=sse` there: Box3D's own determinism test fails on x87 arithmetic.

## The web (wasm32-emscripten)

```sh
emcmake cmake -S . -B build-web -DBOX3DXT_BUILD_TESTS=ON
cmake --build build-web -j && (cd build-web && ctest --output-on-failure)
```

A browser loads no library, so the web build is a static archive, `box3dxt.a`, for
OXT-Beyond's web engine to link in: the shim, Box3D, and a generated table of the symbols the
binding names (`box3dxt_web_exports`). The two tests run against that archive under node. It
is built scalar and single-threaded. No web engine has linked it yet.

## The engine self-test

`tests/engine-selftest.lc` runs on OXT-Beyond's headless server engine over a built library:

```sh
lc-compile -Werror --modulepath <engine>/modules/lci --modulepath out --output out/box3dxt.lcm src/box3dxt.lcb
server-community tests/engine-selftest.lc out/box3dxt.lcm build/box3dxt "$PWD/tests/models/teapot.obj"
```

The second argument is the library's path without its extension; the third is the model
its last scene loads, by its full path. It prints PASS and FAIL
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
