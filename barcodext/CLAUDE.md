# CLAUDE.md

Guidance for Claude Code in the barcodext member of the xtalk-suite monorepo (`barcodext/`).
Where anything disagrees, the code and this file win.

## What this is

**barcodext** binds zxing-cpp (the C++ barcode reader and writer, Apache-2.0, C++20) for OXT:
zxing-cpp (static, FetchContent, pinned to the COMMIT of its v3.1.1 tag in `CMakeLists.txt`,
with its one submodule, the Zint backend its writer is built on) -> the C++ shim
`src/barcode_shim.cpp` (exports `bcx_*`, **ABI 1**: `BCX_ABI_VERSION` there equals the
literal in `checkABI()` of the binding) -> ONE library `barcodext.{so,dll,dylib}` (bare
token), or `barcodext.a` for the web -> the LCB binding `src/barcodext.lcb`
(`org.openxtalk.library.barcodext`, public `bc*`). box3dxt is its template; webpxt is its
sibling, written the same day.

## The rules

1. **Never call script from a foreign thread.** Nothing here leaves the caller's thread and
   no callback exists.
2. **The exception firewall.** zxing-cpp throws. Every export's body runs inside `guarded()`,
   which turns any exception into a refused call. A new export that is not a one-line getter
   of a plain static goes inside it.
3. **The firewall is not enough: zxing-cpp can end the process without throwing to it.** Its
   create-option accessors are declared `noexcept` and parse on every call, so a number they
   cannot parse calls `std::terminate`. `creator_options_clean()` therefore checks the options
   text against its own grammar and REBUILDS it; zxing-cpp never sees the caller's text. A
   new create option is added there, with a refusal case in the smoke test. Do not pass a
   caller's text through "to let the library decide".
4. **Results are held in the shim and copied out.** A read fills the results list, a create
   the symbol slot and a render the picture slot; the binding copies them into engine values
   and releases them in the same handler. Text returns are `Pointer`, copied by `textOf()`
   with the length `bcx_text_length` reports (a barcode's text may hold a zero byte). NEVER
   `ZStringNative`: the engine frees a returned C string.
5. **A picture is untrusted, and so is the text to encode.** The caps are in the shim, by
   name: `BCX_MAX_PIXELS` in, `BCX_MAX_RENDER` and `BCX_MAX_SCALE` out, `BCX_MAX_CONTENT`,
   `BCX_MAX_ARGUMENT`. zxing-cpp is handed a view of the pixels that carries their length.
6. **Pixels are the engine's.** `imageData` is 4 bytes a pixel (an unused byte, then red,
   green, blue), which is zxing-cpp's `ARGB` with an alpha it never reads.
7. **Done means:** a shim change is green in `smoke` AND `fuzz` under
   `-DBARCODEXT_SANITIZE=address`; a binding change passes `lc-compile -Werror` and
   `tests/engine-selftest.lc` on the server engine; both pass `bash tools/run-gates.sh`. An
   ABI change bumps `BCX_ABI_VERSION` and the two literals in `checkABI()` together
   (`tools/check-shim-coverage.py` compares the three). Native-library changes refresh the
   committed binaries through the suite's `release-binaries.yml`; `native-barcodext.yml`
   never commits.

## Generated text: edit the source, then regenerate

| What | Written by |
|---|---|
| `docs/api-reference.md` | `tools/build-api-reference.py` |

A new export is: the shim function, its line in `tests/bcx_exports.h` and a CALL in
`tests/smoke_test.cpp`, a bind and a public handler with a doc block in the binding, and a
line in the engine self-test's `sweepEveryHandler`. `tools/check-shim-coverage.py` refuses
any of those missing.

## What zxing-cpp 3.1.1 does (OBSERVED 2026-11-20; the smoke test's table pins each)

- **Kind names have spaces and hyphens**: "QR Code", "EAN-13", "Code 128", "Data Matrix".
  The parser is forgiving ("qrcode", "ean13", "QR-Code"); what a read REPORTS is the spaced
  spelling. Kinds in a list are separated by commas.
- **A UPC-A is an EAN-13 with a leading 0** unless the read asks for "UPC-A", and its text is
  13 digits either way. A UPC-E's text is the 13-digit number it stands for; the eight
  digits are the extra fact "UPCE".
- **Variants are created under their own name and read under their family's**: ITF-14 as
  ITF, Compact PDF417 as PDF417, QR Code Model 2 as QR Code, Aztec Rune as Aztec, DataBar
  Stacked Omni as DataBar Stacked.
- **Telepen Numeric and Telepen Alpha are the same bars**: a read of every kind says Alpha.
- **ISBN** is created (an EAN-13 starting 978 or 979) and read as EAN-13; a read asked for
  "ISBN" alone finds nothing.
- **EAN-2 and EAN-5 are add-ons**: created alone, read only beside an EAN or UPC symbol and
  only with the option `addon=read` or `addon=require`.
- **ecLevel is case-sensitive** ("H", not "h"), and `gs1` content must start with an
  application identifier.

## Gotchas

1. **The sanitizer lane builds with NDEBUG.** zxing-cpp's own `assert` in `Pattern.h` (ToInt)
   overflows a signed int on the first picture read. What ships is a Release build, where the
   assert is compiled out; the lane tests what ships.
2. **zxing-cpp's objects are compiled `-fwrapv`.** Its readers do arithmetic on an INT_MIN
   "no bar here" marker (the PDF417 readers, on a damaged picture). The results are thrown
   away, but the overflow is undefined; `-fwrapv` defines it. Found by the fuzz test.
3. **The web build needs `-fexceptions`**, the model OXT-Beyond's web engine is linked for.
   Without it `catch` is compiled out and the firewall is not there.
4. **Linux links libstdc++ statically** and `src/barcodext.map` hides it: the library has no
   C++ runtime dependency and exports only `bcx_*`. Not under the sanitizer.
5. **An all-lowercase LCB name warns, and the Extension Builder runs `-Werror`**: a private
   foreign handler is `_read_image`, never `_read` (so the export is `bcx_read_image`).
6. **`the empty array` and `the empty list` are refused by the static gate**: write `{}`
   and `[]`.
7. **Two text returns in one C expression is a use-after-free**: every text result shares one
   static buffer. The binding copies at once; a C caller (a test) must too.

## Status

Verified natively (smoke and fuzz, ASan/UBSan, 64-bit, 32-bit and wasm under node) and on the
headless Linux server engine (`tests/engine-selftest.lc`, 2026-11-20, a locally built library).
Every picture read so far was drawn by the library's own writer: no camera photograph. No
desktop IDE and no other platform's engine has loaded it: verified statically; needs an OXT
pass. Release libraries were committed on 2026-11-21 (six desktop platforms, four Android ABIs,
run 44846691681), beside the web archive (`src/code/wasm32-emscripten/`, built by hand with
Emscripten 6.0.12 the same day); the engine self-test passed over the committed `x86_64-linux`
library that day too (80 checks, none failed), and no engine has loaded the other committed
libraries yet. Open work is in the suite's `docs/WORK-PLAN.md`.
