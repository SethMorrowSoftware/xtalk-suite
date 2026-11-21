# Building render3dxt

## Dependencies

CMake 3.22+, a C11 compiler, and network access on the first configure: stb_image and
fast_obj are fetched from their repositories at the commits `CMakeLists.txt` pins
(`RENDER3DXT_STB_COMMIT`, `RENDER3DXT_FAST_OBJ_COMMIT`). To build with no network, clone
each yourself, check that commit out and pass `-DFETCHCONTENT_SOURCE_DIR_STB=<path>` and
`-DFETCHCONTENT_SOURCE_DIR_FAST_OBJ=<path>`. Nothing else is needed on any platform; the
drawing threads are the system's own (pthreads, or Win32 threads).

## Build and test

```sh
cmake -S . -B build -DRENDER3DXT_BUILD_TESTS=ON
cmake --build build -j
(cd build && ctest --output-on-failure)
```

A configure with no build type is a Release one (a renderer built without optimisation is
ten times slower). That makes `build/render3dxt.so` (`.dylib`, `.dll`) and runs two tests:

- `smoke` (`tests/smoke_test.c`) calls every export of the shim and checks the pictures by
  reading pixels back. Its last line counts the checks.
- `fuzz` (`tests/fuzz_test.c`) makes random calls with valid, stale and hostile arguments.
  `render3dxt_fuzz <seed> <calls>` runs one seed.

Both carry the model and picture files of `tests/assets/` inside them
(`tests/test_assets.h`, generated) and write them to a scratch folder for the run, so they
run from any folder and on a device with no checkout.

Under the sanitizers (a shim change is done when these are green):

```sh
cmake -S . -B build-asan -DRENDER3DXT_BUILD_TESTS=ON -DRENDER3DXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug
cmake --build build-asan -j && (cd build-asan && ctest --output-on-failure)
cmake -S . -B build-tsan -DRENDER3DXT_BUILD_TESTS=ON -DRENDER3DXT_SANITIZE=thread -DCMAKE_BUILD_TYPE=RelWithDebInfo
cmake --build build-tsan -j && (cd build-tsan && ctest --output-on-failure)
```

`address` is ASan with UBSan; `thread` is TSan, for the drawing threads.

## 32-bit x86

`-DCMAKE_C_FLAGS=-m32` (with gcc's multilib installed) builds the 32-bit library. The CMake
file adds `-msse2 -mfpmath=sse` there, so a scene rounds as it does on 64-bit.

## The web (wasm32-emscripten)

```sh
emcmake cmake -S . -B build-web -DRENDER3DXT_BUILD_TESTS=ON
cmake --build build-web -j && (cd build-web && ctest --output-on-failure)
```

A browser loads no library, so the web build is a static archive, `render3dxt.a`, for
OXT-Beyond's web engine to link in: the shim, the two readers, and a generated table of the
symbols the binding names (`render3dxt_web_exports`). The two tests run against that archive
under node. It draws on one thread. One web engine has linked it: a local build of OXT-Beyond's
(2026-11-21, not a released engine), where the demo and OXT-Beyond's Render3D Tour played in
Chromium. That was the archive as first committed; it was rebuilt the same way with a fix to
how a model's materials are freed (457c244), after the tree before the fix had rebuilt the
committed archive byte for byte.

## The engine tests

Three scripts run on OXT-Beyond's headless server engine over built libraries:

```sh
lc-compile -Werror --modulepath <engine>/modules/lci --modulepath out --output out/render3dxt.lcm src/render3dxt.lcb
server-community tests/engine-selftest.lc out/render3dxt.lcm build/render3dxt
server-community tests/engine-interop.lc out/render3dxt.lcm build/render3dxt <box3dxt.lcm> <box3dxt library>
server-community tests/engine-demo.lc examples/render3d-physics-demo.livecodescript out/render3dxt.lcm build/render3dxt <box3dxt.lcm> <box3dxt library>
```

A library argument is the library's path without its extension. `engine-selftest.lc` is run
from the member root (it reads `tests/assets/` by path). Each prints PASS and FAIL lines and
a `SUMMARY passed failed` line, and exits non-zero on any failure.

- `engine-selftest.lc`: the binding alone. Part of it is generated: a sweep that calls every
  public handler once (`tools/check-lcb-signatures.py --write`).
- `engine-interop.lc`: box3dxt beside it. A Box3D simulation is drawn, and the picture is
  checked against where Box3D says the bodies are. It needs a built box3dxt, which the suite
  has beside this member; a render3dxt repository on its own does not run it.
- `engine-demo.lc`: the demo stack, opened and driven by message. Run without the two
  box3dxt arguments, it opens the demo with box3dxt missing and checks that it says so.

## The gates

```sh
bash tools/run-gates.sh
```

`tools/run-gates.sh` is the member's whole compiler-free list. After changing the shim's
exports, run `python3 tools/check-smoke-coverage.py --write` (the tests' declaration blocks
and the fuzz table) and `python3 tools/check-lcb-signatures.py --write` (the engine sweep);
after changing a doc block, `python3 tools/build-api-reference.py`; after changing a file
in `tests/assets/`, `python3 tools/build-test-assets.py`.

## Release libraries

The libraries under `src/code/` for the desktop platforms and Android come from the suite's
`release-binaries.yml` dispatch, never from a developer's machine (first on 2026-11-21). The web
archive is the exception, as it is for every member: that workflow does not build it, so it
is built as above with the Emscripten version OXT-Beyond pins (6.0.12) and committed with its
`MANIFEST.sha256` line.
