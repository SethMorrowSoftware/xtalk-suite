# Building webpxt

## Dependencies

CMake 3.22+, a C compiler, and network access on the first configure: libwebp is fetched from
its repository at the commit `CMakeLists.txt` pins (`WEBPXT_LIBWEBP_COMMIT`, the v1.6.0 tag).
To build with no network, clone libwebp yourself, check that commit out and pass
`-DFETCHCONTENT_SOURCE_DIR_LIBWEBP=<path>`. Nothing else is needed on any platform: only
libwebp's libraries are built (no command-line tool, so no libpng, libjpeg or giflib), and
they need nothing but the C library.

## Build and test

```sh
cmake -S . -B build -DWEBPXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
(cd build && ctest --output-on-failure)
```

That makes `build/webpxt.so` (`.dylib`, `.dll`) and runs two tests:

- `smoke` (`tests/smoke_test.c`) calls every export of the shim and checks the results:
  lossless round trips byte for byte, a known file's pixels, scaling, animations, and every
  refusal.
- `fuzz` (`tests/fuzz_test.c`) damages real files and makes random calls.
  `webpxt_fuzz <seed> <iterations>` runs one seed.

Under the sanitizers (a shim change is done when this is green):

```sh
cmake -S . -B build-asan -DWEBPXT_BUILD_TESTS=ON -DWEBPXT_SANITIZE=address
cmake --build build-asan -j && (cd build-asan && ctest --output-on-failure)
```

The sanitizers cover libwebp too, not only the shim: a bad read inside the codec on a damaged
file is what the lane is for.

## 32-bit x86

`-DCMAKE_C_FLAGS=-m32` (with gcc's multilib installed) builds the 32-bit library.

## The web (wasm32-emscripten)

```sh
emcmake cmake -S . -B build-web -DWEBPXT_BUILD_TESTS=ON
cmake --build build-web -j && (cd build-web && ctest --output-on-failure)
```

A browser loads no library, so the web build is a static archive, `webpxt.a`, for
OXT-Beyond's web engine to link in: the shim, libwebp, and a generated table of the symbols
the binding names (`webpxt_web_exports`). The two tests run against that archive under node.
No web engine has linked it yet.

## The engine self-test

`tests/engine-selftest.lc` runs on OXT-Beyond's headless server engine over a built library:

```sh
lc-compile -Werror --modulepath <engine>/modules/lci --modulepath out --output out/webpxt.lcm src/webpxt.lcb
server-community tests/engine-selftest.lc out/webpxt.lcm build/webpxt
```

The second argument is the library's path without its extension. It prints PASS and FAIL
lines and a `SUMMARY passed failed` line, and exits non-zero on any failure.

## The gates

```sh
bash tools/run-gates.sh
```

`tools/run-gates.sh` is the member's whole compiler-free list. After changing a doc block,
run `python3 tools/build-api-reference.py`. After changing what the encoder writes for the
known picture (a libwebp bump), run `build/webpxt_smoke --write-known > tests/known_file.inc`
and read the diff: the file's bytes may change, the pixels must not.

## Release libraries

The desktop and Android libraries come from the suite's `release-binaries.yml` dispatch, never
from a developer's machine. The web archive is the exception every member shares: it is built
by hand with the Emscripten version OXT-Beyond's web engine is built with (6.0.12), placed in
`src/code/wasm32-emscripten/` by the build, and committed with its `MANIFEST.sha256` line.

On macOS, `-DCMAKE_OSX_ARCHITECTURES="arm64;x86_64"` builds each architecture on its own
(libwebp picks its SIMD files per architecture when it is configured) and joins them with
`lipo` into `build/webpxt.dylib`; the tests are joined the same way, so
`arch -x86_64 build/webpxt_smoke` runs the Intel half.
