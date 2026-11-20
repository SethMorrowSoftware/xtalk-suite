# CLAUDE.md

Guidance for Claude Code in the webpxt member of the xtalk-suite monorepo (`webpxt/`). Where
anything disagrees, the code and this file win.

## What this is

**webpxt** binds libwebp (Google's WebP codec, BSD 3-Clause, C) for OXT: libwebp (static,
FetchContent, pinned to the COMMIT of its v1.6.0 tag in `CMakeLists.txt`) -> the C shim
`src/webp_shim.c` (exports `wpx_*`, **ABI 1**: `WPX_ABI_VERSION` there equals the literal in
`checkABI()` of the binding) -> ONE library `webpxt.{so,dll,dylib}` (bare token), or
`webpxt.a` for the web -> the LCB binding `src/webpxt.lcb` (`org.openxtalk.library.webpxt`,
public `wp*`). box3dxt is its template; barcodext is its sibling, written the same day.

## The rules

1. **Never call script from a foreign thread.** libwebp is built with `WEBP_USE_THREAD OFF`;
   nothing here leaves the caller's thread and no callback exists.
2. **Nothing crosses the boundary but values.** The shim is C: there is no exception to
   firewall. Every export checks its buffers' lengths against the stated size before it reads
   a byte, and a refused call returns 0 with `wpx_last_error()` set.
3. **Results are held in the shim and copied out.** A decode fills the picture slot, an encode
   the output slot; the binding copies them into engine values and releases the slot in the
   same handler. Text returns are `Pointer`, copied by `textOf()`. NEVER `ZStringNative`: the
   engine frees a returned C string.
4. **Generation-tagged integer handles** for an open animation and for an animation being
   written, validated before use; a stale or 0 handle is a harmless no-op.
5. **A file is untrusted.** The caps are in the shim, by name: `WPX_MAX_PIXELS` (2^26 for one
   picture), `WPX_MAX_SIDE` (16383, the format's own), the frame and duration limits of the
   animation writer. A new export that takes a file or a size goes through them, and gets a
   refusal case in `tests/smoke_test.c`.
6. **Pixels are the engine's.** `imageData` is 4 bytes a pixel (an unused byte, then red,
   green, blue); `alphaData` is 1. The shim writes 255 into the unused byte and never reads
   it. Do not "fix" the order to RGBA: the reason this member exists is that a script reorders
   nothing.
7. **Done means:** a shim change is green in `smoke` AND `fuzz` under
   `-DWEBPXT_SANITIZE=address`; a binding change passes `lc-compile -Werror` and
   `tests/engine-selftest.lc` on the server engine; both pass `bash tools/run-gates.sh`. An
   ABI change bumps `WPX_ABI_VERSION` and the two literals in `checkABI()` together
   (`tools/check-shim-coverage.py` compares the three). Native-library changes refresh the
   committed binaries through the suite's `release-binaries.yml`; `native-webpxt.yml` never
   commits.

## Generated text: edit the source, then regenerate

| What | Written by |
|---|---|
| `tests/known_file.inc` | `webpxt_smoke --write-known > tests/known_file.inc` |
| `docs/api-reference.md` | `tools/build-api-reference.py` |

A new export is: the shim function, its `extern` line and a CALL in `tests/smoke_test.c`, a
bind and a public handler with a doc block in the binding, and a line in the engine
self-test's `sweepEveryHandler`. `tools/check-shim-coverage.py` refuses any of those missing.

## Gotchas

1. **An all-lowercase LCB name warns, and the Extension Builder runs `-Werror`**: a private
   foreign handler is `_decode_image`, never `_decode` (so the export is `wpx_decode_image`).
2. **`the empty array` and `the empty list` are refused by the static gate**: write `{}`
   and `[]`.
3. **An empty Data has no pointer.** `pointerOf()` gives the shim a valid pointer with a
   length of 0; the shim never reads through a pointer whose length is 0.
4. **Lossless is exact**: the encoder is told to keep the colour of fully transparent pixels
   (`config.exact`), so a picture comes back byte for byte, alpha 0 included.
5. **`wpx_animenc_finish` releases the output slot before it fills it**: a caller must copy
   the bytes before it calls any encode again (the binding does).
6. **The web archive holds libwebp's four libraries in one relocatable object**; the order on
   the `emcc -r` line is the static link order (mux, demux, webp, sharpyuv).

## Status

Verified natively (smoke and fuzz, ASan/UBSan, 64-bit, 32-bit and wasm under node) and on the
headless Linux server engine (`tests/engine-selftest.lc`, 2026-11-20, a locally built
library). No desktop IDE and no other platform's engine has loaded it: verified statically;
needs an OXT pass. No binaries are committed yet. Open work is in the suite's
`docs/WORK-PLAN.md`.
