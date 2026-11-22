# Building xlsxt

## Dependencies

CMake 3.22+, a C11 compiler, and network access on the first configure: libxlsxwriter, zlib
and Expat are fetched from their repositories at the commits `CMakeLists.txt` pins. To build
with no network, clone each yourself, check its pinned commit out and pass
`-DFETCHCONTENT_SOURCE_DIR_LIBXLSXWRITER=<path>`, `-DFETCHCONTENT_SOURCE_DIR_ZLIB=<path>` and
`-DFETCHCONTENT_SOURCE_DIR_EXPAT=<path>`. Nothing else is needed on any platform: no system
zlib is used, even where there is one.

The three libraries are compiled by xlsxt's own `CMakeLists.txt` from a stated list of their
source files; their own build files do not run. The file says why for each.

## Build and test

```sh
cmake -S . -B build -DXLSXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
(cd build && ctest --output-on-failure)
```

That makes `build/xlsxt.so` (`.dylib`, `.dll`) and runs two tests:

- `smoke` (`tests/smoke_test.c`) calls every export of the shim, writes workbooks and reads
  them back, and reads files it builds part by part with `tests/test_zip.h`, the way programs
  other than libxlsxwriter write them, some of them wrong on purpose.
- `fuzz` (`tests/fuzz_test.c`) makes random calls with valid, stale and hostile arguments,
  then damages good files three ways (whole files, single XML parts, the zip's own
  structure) and reads every cell of whatever still opens. `xlsxt_fuzz <seed> <calls>` runs
  one seed; `FUZZ_TRACE=1` prints each call and `--replay <file>` re-runs a trace.

Both write their files in the directory they are run from, under names beginning
`xlsxt-smoke-` and `xlsxt-fuzz-`, and remove them when they pass.

Under the sanitizers (a shim change is done when this is green):

```sh
cmake -S . -B build-asan -DXLSXT_BUILD_TESTS=ON -DXLSXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug
cmake --build build-asan -j && (cd build-asan && ctest --output-on-failure)
```

The sanitizer flags reach the three libraries too, so a bad read inside one of them that the
shim caused is reported.

## 32-bit x86

`-DCMAKE_C_FLAGS=-m32` (with gcc's multilib installed) builds the 32-bit library. Nothing
else changes.

## The web (wasm32-emscripten)

```sh
emcmake cmake -S . -B build-web -DXLSXT_BUILD_TESTS=ON
cmake --build build-web -j && (cd build-web && ctest --output-on-failure)
python3 tools/check-web-names.py --archive build-web/xlsxt.a --nm "$EMSDK/upstream/bin/llvm-nm"
```

A browser loads no library, so the web build is a static archive, `xlsxt.a`, for
OXT-Beyond's web engine to link in: the shim, the three libraries, and a generated table of
the symbols the binding names (`xlsxt_web_exports`). The two tests run against that archive
under node.

The engine it is linked into has a zlib of its own, so in this build every global name of
the three libraries is renamed to `xlxw_<name>` by `src/xlsx_web_names.h`, and the last
command above fails if the archive defines any global that is not `xlx_*`, `xlxw_*` or the
table. After bumping a pin, rewrite the header from a native build:

```sh
python3 tools/check-web-names.py --write --from build/libxlsxt_deps.a
```

OXT-Beyond's web engine first linked the archive in that repository's pull request 605
(2026-11-21), whose web IDE check wrote a workbook and read it back in Chromium, Firefox and
WebKit. That pull request did not merge; OXT-Beyond 0.2.8-dp.2.1 links the archive instead
(its pull request 620, merged 2026-11-22, pinned to 9ebbd6e), and the same check passed there.
In a browser a workbook is written to, and read from, the engine's in-memory file system.

## The engine self-test

`tests/engine-selftest.lc` runs on OXT-Beyond's headless server engine over a built library:

```sh
lc-compile -Werror --modulepath <engine>/modules/lci --modulepath out --output out/xlsxt.lcm src/xlsxt.lcb
server-community tests/engine-selftest.lc out/xlsxt.lcm build/xlsxt
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
changing a doc block, `python3 tools/build-api-reference.py`. After bumping a pin, change the
version in `CMakeLists.txt`'s table, `THIRD-PARTY-LICENSES.md`, the smoke test and the
binding's example together: `tools/check-pins.py` names whichever was missed, and with
`--source build/_deps` it also reads the fetched sources.

## Release libraries

The libraries under `src/code/` for the desktop platforms and Android come from the suite's
`release-binaries.yml` dispatch, never from a developer's machine (first on 2026-11-21). The
web archive is the exception, as it is for every member: that workflow does not build it, so
it is built as above with the Emscripten version OXT-Beyond pins (6.0.12) and committed with
its `MANIFEST.sha256` line.
