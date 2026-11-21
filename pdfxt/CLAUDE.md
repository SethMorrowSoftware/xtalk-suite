# CLAUDE.md

Guidance for Claude Code in the pdfxt member of the xtalk-suite monorepo (`pdfxt/`). Where
anything disagrees, the code and this file win.

## What this is

**pdfxt** binds PDFium (Chromium's PDF engine; BSD 3-clause and Apache 2.0) for OXT, read-only:
open, draw, text, search, outline, links. PDFium is NOT built here and NOT linked: a PREBUILT
shared library, one release of bblanchon/pdfium-binaries pinned by SHA-256 in `src/pdfium.pin`,
ships as a SECOND file beside the shim (`pdfium.{so,dll,dylib}`) -> the C shim
`src/pdfium_shim.c` (exports `pdx_*`, **ABI 1**: `PDX_ABI_VERSION` there equals the literal in
`checkABI()` of the binding) loads it at run time from its own folder -> `pdfxt.{so,dll,dylib}`
(bare token) -> the LCB binding `src/pdfxt.lcb` (`org.openxtalk.library.pdfxt`, public `pdf*`).
box3dxt is the member this one was shaped on.

## The rules

1. **Never call script from a foreign thread.** The shim starts no thread and registers no
   callback that reaches script; PDFium is called on the caller's thread only.
2. **Nothing crosses the boundary but values.** The shim is C: there is no exception to
   firewall. What stands in its place: every export validates its handle, page and arguments
   before it calls PDFium, and nothing throws but the binding's ABI check. A refusal is 0 or
   empty plus `pdx_last_error`.
3. **Text and bytes cross as a Pointer to a buffer the shim owns.** A text result is measured
   with `pdx_text_length` and copied by `textOf()`; a drawing by `pdx_data_length` and
   `dataOf()`, which releases it. NEVER `ZStringNative` for a return: the engine frees a
   returned C string, and freeing a static buffer killed box3dxt's first engine run. Text IN is
   `ZStringUTF8` (a path or a search word is not native text). The signature gate holds all of
   it.
4. **Generation-tagged integer handles** for documents, validated before use. A slot whose
   generation would wrap is retired, never reused. Pages and text pages are NOT handles: a
   page is a number, loaded and closed inside the call that names it.
5. **PDFium is one file among two, and the pin is what ships.** `src/pdfium.pin` is the only
   place a hash or the release is decided; the CMake build, `tools/package-extension.py` and
   the suite's installer read it, and `tools/check-pdfium-pin.py` holds the prose to it. The
   library is copied byte for byte and never stripped, patched or re-signed. A new PDFium
   function goes in `PDX_SYMBOLS` (resolved by name, typed from the pinned header) and is
   refused at load if the library lacks it.
6. **A PDF is a stranger's file.** Every size that comes from one is bounded before memory is
   asked for (`PDX_MAX_*`), every count is clamped, every string is copied with its length. No
   JavaScript runs (the pinned build has no V8). A link's address is data: the docs tell the
   stack to show it before opening it, and nothing here opens anything.
7. **Coordinates are points from the TOP LEFT of the page as displayed**, 1-based pages and
   characters. Every rectangle and point goes through `FPDF_PageToDevice` /
   `FPDF_DeviceToPage` so rotation is handled once, by PDFium.
8. **Names are mechanical.** `pdx_page_count` is bound as `_pdx_page_count` and wrapped by
   `pdfPageCount`; nothing is renamed by hand (`tools/check-lcb-signatures.py`, fixture
   `tools/test-lcb-signatures.py`).
9. **Done means:** a shim change is green in `smoke` under `-DPDFXT_SANITIZE=address
   -DCMAKE_BUILD_TYPE=Debug`; a binding change passes `lc-compile -Werror` and
   `tests/engine-selftest.lc` on the server engine; a change to
   `examples/pdfxt-demo.livecodescript` passes `tests/demo-drive.livecodescript` on the
   desktop engine with `-ui` (its header has the command); all pass
   `bash tools/run-gates.sh`. An ABI change bumps `PDX_ABI_VERSION` and the two literals in
   `checkABI()` together.
   Native-library changes refresh the committed binaries through the suite's
   `release-binaries.yml`; `native-pdfxt.yml` never commits.

## Generated text: edit the source, then regenerate

| What | Written by |
|---|---|
| the declaration block of `tests/smoke_test.c` | `tools/check-smoke-coverage.py --write` |
| `sweepEveryHandler` in `tests/engine-selftest.lc` | `tools/check-lcb-signatures.py --write` |
| `docs/api-reference.md` | `tools/build-api-reference.py` |
| `tests/fixtures/*.pdf` and `tests/fixtures.h` | `tools/build-test-pdfs.py` |
| the SAMPLE PDFS block of `examples/pdfxt-demo.livecodescript` (the rest is hand-written) | `tools/build-test-pdfs.py` |

## As built

- **One text buffer, one bytes buffer, one error text**, all static: the next call of the same
  kind overwrites them. The binding copies at once, so script never sees that; a C caller must
  copy before it asks again. Numbers are printed with a `.` in every locale.
- **`pdx_text_length` measures either the text buffer or the error text**, by pointer; any
  other pointer measures 0.
- **A drawing is converted in place** from PDFium's BGRx to the engine's `imageData` order (a
  zero byte, then red, green, blue), on white.
- **`pdx_open` keeps the file open** and PDFium reads it through a callback; `pdx_open_data`
  keeps its own copy of the bytes. Both live until `pdx_close`.
- **Linux loads PDFium with `RTLD_DEEPBIND`** (it exports its own FreeType and calls it
  through the PLT); sanitizer builds define `PDX_NO_DEEPBIND` because ASan refuses the flag.
- **The floors are PDFium's builders'**: macOS 13.0, Android API 23, glibc 2.16. The shim
  itself builds at the suite's floors, so on an older system it loads and refuses with a
  reason. On Android the smoke test skips its PDFium checks only when the device is below API
  23 AND the load failed, and says so in its summary.
- **Only `pdx_*` is exported**: `src/pdfxt.map` for GNU ld and the same pattern for ld64.
- **No web build**: the prebuilt wasm archive is a whole Emscripten program, not a library an
  engine can link. `CMakeLists.txt` refuses Emscripten with that sentence.

## Gotchas

1. **An all-lowercase LCB handler or variable name warns**, and the Extension Builder runs
   `-Werror`: a foreign handler is `_pdx_load`, never `_load`; the helper is `asInt`.
2. **`bitAnd` is an operator in script** (`a bitAnd b`), not a function.
3. **A line break in a page's text is TWO characters** (CR LF) in PDFium's count, so a range
   that spans lines is longer than it looks.
4. **`FPDF_InitLibraryWithConfig` and `FPDF_DestroyLibrary` are process-wide.** `pdx_shutdown`
   closes every document first; after it the next call loads PDFium again.
5. **Handle bits**: 12 bits of slot+1, 11 of generation. `PDX_MAX_DOCS` is 4095, not 4096:
   slot+1 = 4096 would collide with the generation's first bit (found by the smoke test).

6. **PDFium is opened by full path only, never by bare name.** Android has a system
   `libpdfium.so` of its own; `dlopen("libpdfium.so")` finds it, and it is another build. The
   first Android 6.0 emulator run (2026-11-20) caught a bare-name fallback doing exactly that.

## Status

Verified natively (smoke, ASan/UBSan, x86_64 Linux; and the smoke test on every platform
it ships for by `native-pdfxt.yml`, run 44840908920, 2026-11-21: six desktop rows, the mac
x86_64 slice under Rosetta, and the Android 6.0 emulator for both x86 ABIs, the ARM ABIs built,
not run) and on the headless Linux server engine (`tests/engine-selftest.lc`, 2026-11-20, a
locally built library). The demo stack (`examples/pdfxt-demo.livecodescript`, the suite UI kit)
is driven on the Linux desktop engine without a display by `tests/demo-drive.livecodescript`
(2026-11-21), and by the native lane on every change; no person has used its window. A click
or a drag on the page is driven through the handlers the demo's mouse handlers call
(`pvClickAt`, `pvSelectBox`), since no pointer moves there. The Windows IDE loaded it on
2026-11-21 (the maintainer's 64-bit OXT-Beyond, CI's `x86_64-win32` library): the engine
self-test passed 64 checks and failed its 2 first-load checks, which cannot hold once PDFium
has been loaded in the process (pdfxt had been used in that session first; loading and
shutting down first reproduces the two on Linux; a fresh-session run is owed). No IDE on Linux
or a Mac and no engine on macOS or Android has loaded it: verified statically; needs an OXT
pass. No binaries are committed yet. Open work is in the suite's `docs/WORK-PLAN.md`.
