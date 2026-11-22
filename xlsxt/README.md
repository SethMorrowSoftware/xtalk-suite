# xlsxt

**Excel spreadsheets - reading and writing .xlsx files - for OpenXTalk / the xTalk family.**

xlsxt lets a stack write a real Excel workbook and read one back, with no copy of Excel and
no other program on the machine. Writing is [libxlsxwriter](https://github.com/jmcnamara/libxlsxwriter),
John McNamara's C library (BSD 2-Clause); reading is a small reader of xlsxt's own over
[zlib](https://github.com/madler/zlib)'s minizip and [Expat](https://github.com/libexpat/libexpat).
All of it sits behind the family's flat C shim and a thin LCB layer:

```
libxlsxwriter + zlib + Expat (each pinned to a commit, static)
   |- C shim   src/xlsx_shim.c  ->  xlsxt.{so,dll,dylib}     (ABI: xlx_*, v1)
        |- LCB binding  src/xlsxt.lcb     (org.openxtalk.library.xlsxt; public xl*)
```

## What it can do

- **Write workbooks.** Any number of sheets; text, numbers, formulas, true/false, dates and
  times, links and cell notes; a whole tab-delimited table in one call.
- **Make them look right.** Fonts, colours, borders, alignment, wrapping and number formats;
  column widths and row heights; merged cells; frozen panes; an autofilter; drop-down lists;
  pictures (PNG, JPEG, GIF, BMP); page setup, headers and footers for printing.
- **Charts.** Column, bar, line, area, pie, doughnut, scatter and radar charts drawn from the
  workbook's own cells, with titles, axis ranges and legends.
- **Read workbooks.** Files written by Excel, LibreOffice, Numbers or Google Sheets: sheet
  names, cell values, dates as dates, formulas with their stored results, number formats and
  merged blocks; one cell at a time, or a whole block as tab-delimited text in one call.
- **The family's rules.** No thread is started and no callback reaches script (rule 1); the
  shim is C, validates before it calls anything and cannot throw across the boundary (rule
  2); a whole table crosses as one text, not a call per cell (rule 3); every workbook, sheet,
  format, chart and reader is a generation-tagged integer handle, and a stale one is a
  harmless no-op (rule 4).

What it does not do: change an existing file in place (read it, then write a new one), read
the old `.xls` format or a workbook encrypted with a password, or bring back a file's fonts,
colours, charts and pictures when reading (it reads the data). It does not calculate
formulas: Excel does that when it opens the file.

## Quick taste

```livecodescript
on exportTable
   local tBook, tSheet, tBold
   put xlWorkbookNew(specialFolderPath("documents") & "/report.xlsx") into tBook
   put xlWorkbookAddSheet(tBook, "Sales") into tSheet
   put xlWorkbookAddFormat(tBook) into tBold
   xlFormatSetBold tBold, true
   get xlSheetWriteGrid(tSheet, 1, 1, the text of field "table", "numbers", 0)  -- tabs and returns
   xlSheetSetRow tSheet, 1, 18, tBold                                           -- the heading row
   xlSheetWriteFormula tSheet, 10, 2, "=SUM(B2:B9)", tBold
   if not xlWorkbookClose(tBook) then answer "Could not save:" && xlLastError()
end exportTable

on importTable pPath
   local tReader
   put xlReadOpen(pPath) into tReader
   if tReader is 0 then
      answer xlLastError()
      exit importTable
   end if
   put xlReadGrid(tReader, 1, 1, 1, 0, 0) into field "table"                    -- the whole first sheet
   xlReadClose tReader
end importTable
```

[docs/getting-started.md](docs/getting-started.md) carries on from there.

## Status

Joined the suite on 2026-11-20. What has run, and where:

- **Natively**, on x86_64 Linux: the smoke test calls every export of the shim, writes
  workbooks and reads them back, and reads files it builds part by part the way other
  programs write them, clean under ASan/UBSan; a random-call test (`tests/fuzz_test.c`)
  throws valid, stale and hostile arguments at every export and feeds the reader thousands of
  damaged files. Both also pass as a 32-bit build and as WebAssembly under node.
- **On an engine**, the same day: `tests/engine-selftest.lc` ran on OXT-Beyond's headless
  Linux server engine (9.7.1-OXT, x86_64) over a locally built library. It loaded the module,
  passed the ABI check, wrote a workbook with formats, a table, a chart and a picture, read it
  back (text outside ASCII included) and called every public handler once.
- **In the IDE on Windows**, 2026-11-21, on the maintainer's PC (64-bit OXT-Beyond, its
  version not recorded): the binding compiled by the IDE's own lc-compile, over the
  `x86_64-win32` DLL of the native lane's run 44845807163 (not the release library). It
  loaded and named its versions; the engine self-test, run in the IDE as a script-only stack,
  passed 64 and failed 0; the demo's window built and its own checks passed 39/0. Under
  Windows' dark theme the demo's table and every tick box's words were white on white. The
  demo was rebuilt the same day, and the new window ran on that PC readable throughout
  (below).
- **In a browser**, 2026-11-21: the committed web archive, linked into OXT-Beyond's web
  engine by that repository's pull request 605, ran the `xlsx` step of its web IDE check
  (run 44847676839) in headless Chromium, Firefox and WebKit. `xlLibraryVersion()`
  answered; a workbook with a table, a formula, a date, a boolean, text outside ASCII and a
  chart was written to the engine's in-memory file system and read back; a file that is no
  workbook was refused; nothing was left open. The other handlers have not run in a browser.
  Pull request 605 did not merge: OXT-Beyond 0.2.8-dp.2.1 builds xlsxt in instead (its pull
  request 620, merged 2026-11-22, pinned to 9ebbd6e), and that pull request's check passed
  the same step in the three browsers (run 44955451513).
- **In an Android app**, 2026-11-21: the same pull request put the committed
  `x86_64-android` library in OXT-Beyond's Android check app (run 44955451306). On an
  Android 13 x86_64 emulator and an Android 16 one with 16 KB pages, `xlLibraryVersion()`
  answered `xlsxt ABI 1; libxlsxwriter 1.2.4; zlib 1.4; Expat 2.10.0`, and the app's test
  passed: a workbook written in the app's documents folder with no temporary folder set (on
  Android the library then makes its temporary files beside the workbook), checked to be a
  zip, and read back cell for cell and as one grid (text outside ASCII and on two lines,
  0.1 + 0.2 to its last digit, a formula with its result, a date in its format, a yes), with
  nothing left open. The same test passed that day on OXT-Beyond 0.2.8-dp.2's Linux
  standalone engine, headless, over the committed `x86_64-linux` library.
- **The demo stack, Spreadsheet Studio**, `examples/xlsxt-demo.livecodescript` (paste it
  into a stack's script and reopen the stack; `examples/build-demo-stack.livecodescript`
  saves it as a stack file). It opens playing a tour of four scenes that write real
  workbooks and read them back while you watch: a sheet that fills itself and gets its
  colours, money format, frozen heading and chart; formulas, today's date and a true-or-false
  cell; all fifteen kinds of chart; ten thousand cells, timed. Each scene ends by saying
  whether every cell came back the same. Its other tabs are the workbench: a table in one
  call, formats, formulas and dates, charts, page setup and pictures, a reader for any
  `.xlsx`, and one button that checks all of it. It wears OXT-Beyond's dark look, with every
  colour named by the stack, so no system theme can leave its words white on white (the
  Windows fault above). It was rebuilt so on 2026-11-21, after the Windows run, and
  `tests/demo-drive.livecodescript` drives the new window on OXT-Beyond's Linux desktop
  engine (that day, a locally built library, headless and under xvfb): it opens playing,
  each scene and the whole tour ends with every cell matched and nothing left open, leaving
  mid-scene or in the tour's pause between two scenes stops it cleanly, every tab's workbook
  is made and read back, a tick box and a cell are clicked, and its own checks are green.
  The native lane repeats that on every change. The same day the new window ran on the
  maintainer's Windows PC (64-bit OXT-Beyond under its dark theme, the saved stack file,
  over the lane-built DLL above): it
  opened at 960 x 640 already playing, the tour played all four scenes, About's checks
  passed 39/0, and every word was readable. The one fault it showed, the ten-thousand-cell
  scene's last column cutting a five-digit number to four, was fixed that day; the drive
  now measures every cell a scene shows against its column, and the fix is checked on
  Linux only. On macOS and in a browser the new window is verified statically; needs an
  OXT pass.
- **Not yet:** no engine on macOS or on an ARM Android has run it, and no desktop IDE but
  the Windows one above: on macOS, on an ARM Android and in an IDE on Linux, it is verified
  statically; needs an OXT pass. No file it wrote has been opened in Excel itself on the
  record: what is checked is that the library's own reader reads them and that their parts
  are the ones libxlsxwriter writes. The release libraries committed under `src/code/` on
  2026-11-21 (six desktop platforms, four Android ABIs) were tested where they were built,
  and two of them have run on an engine, the `x86_64-android` and `x86_64-linux` ones
  (above); the Windows run used the native lane's DLL.

## Building and testing

```sh
cmake -S . -B build -DXLSXT_BUILD_TESTS=ON -DCMAKE_BUILD_TYPE=Release && cmake --build build -j && (cd build && ctest)
cmake -S . -B build-asan -DXLSXT_BUILD_TESTS=ON -DXLSXT_SANITIZE=address -DCMAKE_BUILD_TYPE=Debug && cmake --build build-asan -j && (cd build-asan && ctest)
bash tools/run-gates.sh
```

A C11 compiler and CMake 3.22 are all it needs; the three libraries are fetched at configure
time. [docs/building.md](docs/building.md) has the details.

## Documentation

- [docs/getting-started.md](docs/getting-started.md) - writing a file, reading one, dates,
  the limits, what the reader does not bring back.
- [docs/api-reference.md](docs/api-reference.md) - every `xl*` handler, generated from the
  binding's doc blocks.
- [docs/building.md](docs/building.md) - builds, sanitizers, the tests, the gates.
- [CLAUDE.md](CLAUDE.md) - rules and gotchas for anyone changing this member.

## License

MIT (see [LICENSE](LICENSE)). libxlsxwriter is BSD 2-Clause, zlib is under the zlib license
and Expat is MIT; [THIRD-PARTY-LICENSES.md](THIRD-PARTY-LICENSES.md) carries their notices and
those of the smaller pieces inside libxlsxwriter.

<!-- ==== SUITE RELATIONSHIP BEGIN (generated by tools/sync-member-readmes.py in the xTalk suite from tools/member-registry.py and the carried-copy registries; do not edit inside the markers) ==== -->

## Relationship to the xTalk suite

xlsxt is developed in the **xTalk suite** monorepo at https://github.com/SethMorrowSoftware/xtalk-suite, as its
`xlsxt/` member, and PUBLISHED from there into this repository,
https://github.com/SethMorrowSoftware/xlsxt: once a change lands on the suite's `main` and
the suite's gates pass, the suite's `tools/publish-members.py` replays it
here as a commit carrying a `Suite-Commit:` trailer that names the suite
commit it came from. The suite is the source of truth; this repository is
its published copy, one commit for each change to `xlsxt/` that landed on
the suite's `main`.

**Contributing.** Please open issues and pull requests at the suite. A pull
request opened here is not lost - the suite brings it home with
`python3 tools/publish-members.py port xlsxt --ref pull/<n>/head`, keeping its
author - but a commit made here directly holds up the next publish until
it has been ported, because publishing never overwrites work it did not
write. The suite's `docs/MEMBER-REPO-SPLIT.md` is the whole workflow.

**Suite-level paths cited from here.** This member's `CLAUDE.md` and
`docs/` cite files that live at the suite root, not in this tree:
`docs/OXT-ENGINE-NOTES.md` (engine behaviour, the authoritative list),
`docs/OXT-PASS-RUNBOOK.md`, `tools/build-all.sh`,
`tests/suite-selftest.livecodescript` and the suite-level `docs/`
index. Read them at `https://github.com/SethMorrowSoftware/xtalk-suite/blob/main/<path>`. A path of the
form `../<member>/...` names a sibling member of the suite; each has its
own repository, listed in `tools/member-registry.py` there.

**Sibling members this member's gates need beside it.** None: `bash
tools/run-gates.sh` (this member's own gate list, the one CI runs)
needs nothing but this checkout and Python 3.

**Carried copies inside this member, and where their masters are.**
Every runnable stack here is one paste-and-run file, so it carries what
it needs verbatim between marker lines. The masters, and the drift gates
that hold every copy byte-identical to them, live in the suite and do
not travel with this member; refresh a copy from the suite (the marker
lines name the master) rather than editing inside the markers.

- The demo UI kit (`tools/ui-kit.livecodescript`; gate `tools/check-ui-kit-drift.py`) in `examples/xlsxt-demo.livecodescript`.
- `tools/check-livecodescript.py`: byte-identical copies of the family's unified tooling, held identical across members by the suite's `tools/check-checker-drift.py` and fixture-tested there by `tools/test-checker.py`.

**What this repository cannot check on its own.** The suite-wide gates -
cross-library name disjointness (`tools/check-cross-library-names.py`),
the carried-copy drift gates above, embed freshness, the cross-member
handler-call and typed-boundary checks (`tools/check-handler-calls.py`,
`tools/check-lcb-call-types.py`), the timer-pin closure, and the suite
paste's coverage ratchet (`tools/check-suite-coverage.py`) - run only in
the suite. `tools/run-gates.sh` here is this member's own list, and the
suite's `tools/build-all.sh` runs that same script, so the two cannot
disagree about what this member's gates are.

<!-- ==== SUITE RELATIONSHIP END ==== -->
