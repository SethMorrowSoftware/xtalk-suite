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
- **Not yet:** no desktop IDE has loaded it, and no engine on Windows, macOS, Android or the
  web has run it: on those it is verified statically; needs an OXT pass. No file it wrote has
  been opened in Excel itself on the record: what is checked is that the library's own reader
  reads them and that their parts are the ones libxlsxwriter writes. No library is committed
  under `src/code/` yet; the suite's release-binaries dispatch lands them.

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
