# CLAUDE.md

Guidance for Claude Code in the xlsxt member of the xtalk-suite monorepo (`xlsxt/`). Where
anything disagrees, the code and this file win.

## What this is

**xlsxt** reads and writes Excel `.xlsx` files for OXT. libxlsxwriter (the writer, BSD-2),
zlib with its `contrib/minizip`, and Expat (static, FetchContent, each pinned to the COMMIT
its release tag names) -> the C shim `src/xlsx_shim.c` (exports `xlx_*`, **ABI 1**:
`XLX_ABI_VERSION` there equals the literal in `checkABI()` of the binding) -> ONE library
`xlsxt.{so,dll,dylib}` (bare token), or `xlsxt.a` for the web -> the LCB binding
`src/xlsxt.lcb` (`org.openxtalk.library.xlsxt`, public `xl*`). The READER is the shim's own
code (libxlsxwriter only writes): minizip opens the zip, Expat parses each part. box3dxt is
its ancestor; read that member's CLAUDE.md for the reasons behind the shared shape.

## The rules

1. **Never call script from a foreign thread.** Nothing here starts a thread or registers a
   callback that reaches script.
2. **Nothing crosses the boundary but values.** The shim is C: there is no exception to
   firewall. Every export validates its handles and arguments before it calls a library, and
   libxlsxwriter's stderr warnings are switched off (`src/quiet/R.h`): a refused call is a
   return value and `xlx_last_error()`, never a line on the host's console.
3. **A table crosses as one text.** `xlx_sheet_write_grid` and `xlx_read_grid` carry tabs and
   returns; a text result is a `const char *` into a buffer the shim owns, which the binding
   declares `Pointer` and copies with `textOf()`. NEVER a `ZString` return: the engine frees
   a returned C string (box3dxt's first engine run died of it). Text goes IN as
   `ZStringUTF8`. The signature gate refuses anything else.
4. **Generation-tagged integer handles, with a KIND.** Three bits of every handle say what
   it is (workbook, sheet, format, chart, reader), so a sheet handle handed where a format is
   expected is refused: before the kind bits, the first sheet and the first format of a
   workbook were both handle 1. Closing a workbook kills the handles of everything in it.
5. **The reader trusts nothing in a file.** Files come from strangers. Every size is bounded
   (the `XLX_MAX_*` table at the top of the shim; docs/getting-started.md prints it), a part
   is inflated in pieces and never by its declared size, a DOCTYPE is refused (so no entity
   can expand), a cell reference outside Excel's grid is refused, and a sheet that failed to
   load is remembered as failed and not parsed again. A new thing read from a file gets a
   bound, and a damaged file that got through gets a named case in the smoke test.
6. **The writer does not trust libxlsxwriter with its caller either.** It accepts things that
   make a file Excel calls corrupt or reads differently: text that is not UTF-8, a link that
   is "just words", a defined name Excel refuses, `_x0041_` in a cell (Excel reads it as
   "A": the shim escapes it). Each has a guard in the shim and a case in the smoke test.
7. **Names are mechanical.** `xlx_sheet_write_number` is bound as `_sheet_write_number` and
   wrapped by `xlSheetWriteNumber`; nothing is renamed by hand
   (`tools/check-lcb-signatures.py`, fixture `tools/test-lcb-signatures.py`).
8. **Rows, columns, sheets and series are 1-based** on every public surface, the shim's
   included; libxlsxwriter's are 0-based and the shim converts at the call.
9. **Done means:** a shim change is green in `smoke` AND `fuzz` under
   `-DXLSXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug`; a binding change passes
   `lc-compile -Werror` and `tests/engine-selftest.lc` on the server engine; a change to
   `examples/xlsxt-demo.livecodescript` passes `tests/demo-drive.livecodescript` on the
   desktop engine with `-ui` (its header has the command); all pass
   `bash tools/run-gates.sh`. An ABI change bumps `XLX_ABI_VERSION` and the two literals in
   `checkABI()` together. Native-library changes refresh the committed binaries through the
   suite's `release-binaries.yml`; `native-xlsxt.yml` never commits.

## Generated text: edit the source, then regenerate

| What | Written by |
|---|---|
| the declaration blocks of both C tests, the fuzz call table | `tools/check-smoke-coverage.py --write` |
| `sweepEveryHandler` in `tests/engine-selftest.lc` | `tools/check-lcb-signatures.py --write` |
| `docs/api-reference.md` | `tools/build-api-reference.py` |
| `src/xlsx_web_names.h` | `tools/check-web-names.py --write --from <native build>/libxlsxt_deps.a` |

## As built

- **None of the three libraries' own CMake files runs.** They are fetched as source and
  compiled from a stated list of files (`CMakeLists.txt` says why for each). A pin bump that
  adds an upstream source file fails at configure or link, on purpose.
- **zlib's minizip, not libxlsxwriter's 2010 copy** (`USE_SYSTEM_MINIZIP` with the include
  path pointed at the pinned zlib's `contrib`).
- **`emyg_dtoa()` is the shim's.** libxlsxwriter's bundled `emyg_dtoa.c` reads past the end
  of a table for some small numbers (UBSan, on 1e-7), and without `USE_DTOA_LIBRARY` it
  prints numbers with `printf`, which writes `1,5` in a comma locale. So the switch is on,
  the bundled file is not compiled, and the shim defines the one function.
- **Every zlib name is `z_`-prefixed** (`Z_PREFIX`) on every platform, and for the web every
  global name of all three libraries is renamed `xlxw_*` by `src/xlsx_web_names.h`: the
  web archive is linked into an engine that has a zlib of its own. The desktop libraries
  export only `xlx_*` (`src/xlsxt.map` for GNU ld, the same pattern for ld64).
- **Text results share one buffer the shim owns**, grown as needed: the next text call
  overwrites it. The binding copies at once; a C caller must copy before it asks again.
- **A workbook is written when it is CLOSED**, through temporary files (`xlSetTempFolder`
  chooses where; the default is the system's).
- **Dates are serial numbers** in the 1900 system, Excel's leap-year bug included; the reader
  honours a file's 1904 flag.
- **Windows paths** are UTF-8 on the boundary and converted to wide paths inside.

## Gotchas

1. **An all-lowercase LCB handler or variable name warns** (it could collide with a future
   keyword), and the Extension Builder runs `-Werror`: the helper is `asInt`.
2. **A number parameter given empty is an engine error at the call**, before xlsxt sees it
   (the boundary is typed). Pass 0 for "no format".
3. **`USE_R_LANG` is not about R.** It is libxlsxwriter's only switch for "do not print to
   stderr"; `src/quiet/R.h` answers the header it then includes. `tools/check-pins.py
   --source` holds that upstream reads the switch in one place only.
4. **`tests/test_zip.h` writes STORED zips on purpose**, so a test can state an XML part
   byte for byte, damaged ones included. Deflate is covered by every round trip through
   libxlsxwriter.
5. **The fuzz test writes real files** in its working directory, under names of its own
   (`xlsxt-fuzz-*`); a path argument drawn from the hostile strings is never one that could
   create a file elsewhere.

## Status

Verified natively (smoke and fuzz, ASan/UBSan, 64-bit, 32-bit and wasm under node) and on the
headless Linux server engine (`tests/engine-selftest.lc`, 2026-11-20, a locally built
library). No desktop IDE and no other platform's engine has loaded it: verified statically;
needs an OXT pass. The demo stack (`examples/xlsxt-demo.livecodescript`, the suite UI kit)
is driven on the Linux desktop engine without a display by `tests/demo-drive.livecodescript`
(2026-11-21); no person has used its window. Its builders read the window's fields through
`xdTyped` and `xdTicked`, which fall back to defaults, so `xdCheckAll` is the same code with
or without a window. No file it wrote has been opened in Excel on the record (openpyxl read
the demo's complete workbook on 2026-11-21: its chart, picture, drop-down list, protection,
frozen row, filter, defined name, link and note were all there). The web archive is
committed; the desktop and Android libraries come from the release-binaries dispatch. Open work is in the suite's `docs/WORK-PLAN.md`.
