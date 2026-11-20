# Building barcodext

## Dependencies

CMake 3.22+, a C++20 compiler (gcc 11, clang 14, Visual Studio 2022 or newer) and network
access on the first configure: zxing-cpp is fetched from its repository at the commit
`CMakeLists.txt` pins (`BARCODEXT_ZXING_COMMIT`, the v3.1.1 tag), with its one submodule
(Zint, which its writer is built on). To build with no network, clone zxing-cpp yourself with
`--recurse-submodules`, check that commit out and pass
`-DFETCHCONTENT_SOURCE_DIR_ZXING=<path>`. Nothing else is needed on any platform.

## Build and test

```sh
cmake -S . -B build -DBARCODEXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
(cd build && ctest --output-on-failure)
```

That makes `build/barcodext.so` (`.dylib`, `.dll`) and runs two tests:

- `smoke` (`tests/smoke_test.cpp`) calls every export of the shim and checks the results: a
  barcode of every kind the library writes is made, drawn and read back; barcodes are read
  turned, mirrored, inverted and side by side; every read and create option; every refusal.
- `fuzz` (`tests/fuzz_test.cpp`) damages the pictures and makes random calls.
  `barcodext_fuzz <seed> <iterations>` runs one seed.

Under the sanitizers (a shim change is done when this is green):

```sh
cmake -S . -B build-asan -DBARCODEXT_BUILD_TESTS=ON -DBARCODEXT_SANITIZE=address
cmake --build build-asan -j && (cd build-asan && ctest --output-on-failure)
```

The sanitizers cover zxing-cpp too, not only the shim. Two things about that build are
deliberate. It defines `NDEBUG`, as the Release build that ships does: one of zxing-cpp's own
asserts overflows. And zxing-cpp's objects are compiled `-fwrapv` in EVERY build: its readers
do arithmetic on an INT_MIN marker, which `-fwrapv` makes defined. `CMakeLists.txt` says
where each was found.

On Linux the library carries its own C++ runtime (`-static-libstdc++`) and exports only
`bcx_*`, so it loads on a system whose libstdc++ is older than the build machine's.

## 32-bit x86

`-DCMAKE_C_FLAGS=-m32 -DCMAKE_CXX_FLAGS=-m32` (with gcc's multilib installed) builds the 32-bit
library.

## The web (wasm32-emscripten)

```sh
emcmake cmake -S . -B build-web -DBARCODEXT_BUILD_TESTS=ON
cmake --build build-web -j && (cd build-web && ctest --output-on-failure)
```

A browser loads no library, so the web build is a static archive, `barcodext.a`, for
OXT-Beyond's web engine to link in: the shim, zxing-cpp, and a generated table of the
symbols the binding names (`barcodext_web_exports`). The two tests run against that archive under node.
It is compiled with
`-fexceptions`, the exception model OXT-Beyond's web engine is linked for: zxing-cpp throws,
and without it the shim's `catch` would be compiled out. No web engine has linked it yet.

## The engine self-test

`tests/engine-selftest.lc` runs on OXT-Beyond's headless server engine over a built library:

```sh
lc-compile -Werror --modulepath <engine>/modules/lci --modulepath out --output out/barcodext.lcm src/barcodext.lcb
server-community tests/engine-selftest.lc out/barcodext.lcm build/barcodext
```

The second argument is the library's path without its extension. It prints PASS and FAIL
lines and a `SUMMARY passed failed` line, and exits non-zero on any failure.

## The gates

```sh
bash tools/run-gates.sh
```

`tools/run-gates.sh` is the member's whole compiler-free list. After changing a doc block,
run `python3 tools/build-api-reference.py`.

## Release libraries

None are committed yet. They come from the suite's `release-binaries.yml` dispatch, never from
a developer's machine.
