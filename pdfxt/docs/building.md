# Building pdfxt

## Dependencies

CMake 3.22+, a C11 compiler, and network access on the first configure. PDFium is NOT built
here: the build fetches the prebuilt archive for its platform from
[pdfium-binaries](https://github.com/bblanchon/pdfium-binaries) release `chromium/8165` and
refuses one whose SHA-256 is not the one `src/pdfium.pin` names, then checks the library inside
it the same way. To build with no network, unpack that archive yourself and pass
`-DPDFXT_PDFIUM_DIR=<the folder that holds include/ and lib/ or bin/>`; the library is still
held to the pin.

## Build and test

```sh
cmake -S . -B build -DPDFXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
(cd build && ctest --output-on-failure)
```

That makes `build/pdfxt.so` (`.dylib`, `.dll`), copies PDFium beside it as `build/pdfium.so`,
and runs `smoke` (`tests/smoke_test.c`), which calls every export of the shim and checks the
results. The test carries its two PDFs inside itself (`tests/fixtures.h`), so it needs no file
beside it, which is how the same program runs on an Android emulator.

Under the sanitizers (a shim change is done when this is green):

```sh
cmake -S . -B build-asan -DPDFXT_BUILD_TESTS=ON -DPDFXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug
cmake --build build-asan -j && (cd build-asan && ctest --output-on-failure)
```

The sanitizers watch the shim and the test. PDFium is the prebuilt library and is not
instrumented; what ASan sees of it is every buffer the shim hands it and takes back.

## How the shim finds PDFium

The shim does not link PDFium. On first use it loads `pdfium.<ext>` from the folder the shim
itself was loaded from (or the folder given to `pdfLoad`) and resolves the functions it uses by
name; if one is missing the load is refused and `pdfLastError()` names it. The function
pointers take their types from the pinned headers, so a signature that changes when the pin
moves is a compile error here, not a crash on an engine.

On Linux the load uses `RTLD_DEEPBIND`: PDFium exports its own copy of FreeType and calls it
through the dynamic linker, so without that flag a FreeType the host already loaded would be
used in its place. Sanitizer builds leave the flag out (ASan cannot work with it), which is
safe there because the test loads no other FreeType.

## The test PDFs

`tests/fixtures/basic.pdf` and `tests/fixtures/locked.pdf` are WRITTEN by
`tools/build-test-pdfs.py`, byte for byte the same on every run, and `tests/fixtures.h` is the
same bytes as C arrays. After changing that tool, run it; `--check` (a gate) fails if the
committed files are not what it writes.

## The engine self-test

`tests/engine-selftest.lc` runs on OXT-Beyond's headless server engine over a built library:

```sh
lc-compile -Werror --modulepath <engine>/modules/lci --modulepath out --output out/pdfxt.lcm src/pdfxt.lcb
server-community tests/engine-selftest.lc out/pdfxt.lcm build/pdfxt tests/fixtures
```

The second argument is the library's path without its extension (PDFium must be beside it),
the third the folder of the test PDFs. It prints PASS and FAIL lines and a `SUMMARY passed
failed` line, and exits non-zero on any failure. Part of it is generated: a sweep that calls
every public handler once (`tools/check-lcb-signatures.py --write`).

## The gates

```sh
bash tools/run-gates.sh
```

`tools/run-gates.sh` is the member's whole compiler-free list. After changing the shim's
exports, run `python3 tools/check-smoke-coverage.py --write` (the test's declaration block) and
`python3 tools/check-lcb-signatures.py --write` (the engine sweep); after changing a doc block,
`python3 tools/build-api-reference.py`.

## Moving the PDFium pin

Change the release and every row of `src/pdfium.pin` together (the hashes of the new archives
and of the library inside each), build and test on every platform, and read the new archives'
`licenses/` folder against `THIRD-PARTY-LICENSES.md`. `tools/check-pdfium-pin.py` holds this
page, the README and the licence page to the release the pin names.

## Release libraries

None are committed yet. They come from the suite's `release-binaries.yml` dispatch, never from
a developer's machine: two files for each platform, `pdfxt` built there and `pdfium` copied
unchanged from the pinned archive. `tools/package-extension.py` lands both or neither, and
refuses a PDFium that is not the pinned one.
