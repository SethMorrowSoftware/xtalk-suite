# Getting started with xlsxt

xlsxt writes Excel workbooks (`.xlsx` files) from a stack and reads them back. This page is
what to know before the [API reference](api-reference.md).

## The conventions

- **Rows and columns are numbers, starting at 1.** Row 1, column 1 is cell A1; row 3, column
  2 is B3. `xlCellName(3, 2)` gives `B3` and `xlColumnName(28)` gives `AB` when you need
  Excel's letters, for a formula say.
- **Handles are integers.** A workbook, sheet, format, chart or reader is a number; 0 is
  "none". A handle to something closed is refused by every call, harmlessly: getters answer 0
  or empty, actions do nothing. Closing a workbook closes everything in it.
- **Every parameter is typed.** A number parameter must be given a number: empty is an
  engine error at the call, before xlsxt sees it. Where a call takes a format and you have
  none, pass 0.
- **Nothing throws.** A call with a bad argument does nothing, returns 0 or empty, and
  `xlLastError()` says why. A workbook also counts its refused calls, so a script can write
  ten thousand cells and ask once at the end: `xlWorkbookErrorCount(tBook)` and
  `xlWorkbookFirstError(tBook)`. The one exception is a native library from a different
  release than the binding: the first call throws and names the ABI it needs.
- **Text is Unicode.** Anything a field can hold can go into a cell and comes back the same.

## Writing a workbook

```livecodescript
on writeReport
   local tBook, tSheet, tHead, tMoney, tRow
   put xlWorkbookNew(specialFolderPath("documents") & "/sales.xlsx") into tBook
   put xlWorkbookAddSheet(tBook, "Sales") into tSheet

   put xlWorkbookAddFormat(tBook) into tHead
   xlFormatSetBold tHead, true
   xlFormatSetBackgroundColor tHead, "#DDEBF7"
   put xlWorkbookAddFormat(tBook) into tMoney
   xlFormatSetNumberFormat tMoney, "#,##0.00"

   xlSheetWriteText tSheet, 1, 1, "Month", tHead
   xlSheetWriteText tSheet, 1, 2, "Total", tHead
   put 1 into tRow
   repeat for each line tLine in field "months"       -- "January" & tab & "1250.5"
      add 1 to tRow
      xlSheetWriteText tSheet, tRow, 1, item 1 of tLine, 0
      xlSheetWriteNumber tSheet, tRow, 2, item 2 of tLine, tMoney
   end repeat
   xlSheetWriteFormula tSheet, tRow + 1, 2, "=SUM(B2:B" & tRow & ")", tMoney
   xlSheetSetColumns tSheet, 1, 1, 18, 0             -- column A, 18 characters wide
   xlSheetFreeze tSheet, 1, 0                        -- keep the heading row in view

   if not xlWorkbookClose(tBook) then answer "Could not save:" && xlLastError()
end writeReport
```

(That loop wants `set the itemDelimiter to tab` first.) Four things to know:

1. **The file is written by `xlWorkbookClose`.** Until then nothing is on disk, and after it
   the workbook's handles are dead. `xlWorkbookDiscard` closes without writing.
2. **A format belongs to its workbook** and can be used on any number of cells. Make one for
   each look you need (heading, money, date), not one per cell.
3. **A workbook being written cannot be read or changed back.** There is no "get the cell I
   just wrote", and an existing file cannot be edited in place: read it, then write a new one.
4. **Formulas are stored, not calculated.** Excel calculates them when it opens the file.
   A program that does not (a quick-look viewer, or xlsxt's own reader) sees 0 unless you
   give the result yourself with `xlSheetWriteFormulaValue`.

### A whole table in one call

`xlSheetWriteGrid` takes text with tabs between cells and returns between rows, which is what
a table field or a tab-delimited file already is:

```livecodescript
get xlSheetWriteGrid(tSheet, 1, 1, the text of field "table", "numbers", 0)
```

The mode decides what a cell becomes. `"text"` writes every cell as text. `"numbers"` writes
a cell that reads as a number as a number: digits with an optional sign, decimal point and
exponent, at most 15 digits, and no leading zero, so a postcode, a phone number or a card
number stays text. `"formulas"` does that and also writes a cell beginning with `=` as a
formula; do not use it for text typed by strangers.

### Dates and times

A date in a spreadsheet is a number, the days since the end of 1899 with the time as a
fraction, shown as a date because of its cell's format.

```livecodescript
xlSheetWriteDate tSheet, 2, 1, xlDateToSerial(2026, 11, 20, 0, 0, 0), 0       -- a date
xlSheetWriteDate tSheet, 3, 1, xlSecondsToSerial(the seconds), 0              -- now (UTC)
```

With 0 for the format, `xlSheetWriteDate` picks `yyyy-mm-dd`, `yyyy-mm-dd hh:mm:ss` or
`hh:mm:ss` from the number. To choose, give a format whose number format is a date code:
`xlFormatSetNumberFormat tDate, "d mmm yyyy"`. `xlSecondsToSerial` takes seconds since 1970
as `the seconds` gives them, which is UTC: add your offset first if you want local time.

### Charts and pictures

```livecodescript
put xlWorkbookAddChart(tBook, "column") into tChart
get xlChartAddSeries(tChart, xlRangeFormula("Sales", 2, 1, 13, 1), xlRangeFormula("Sales", 2, 2, 13, 2))
xlChartSetTitle tChart, "Sales by month"
xlSheetInsertChart tSheet, 2, 4, tChart, 1, 1        -- top left corner at D2, full size

xlSheetInsertImage tSheet, 20, 1, tLogoPath, 0.5, 0.5   -- a PNG, JPEG, GIF or BMP file, half size
```

A chart draws cells of the workbook, named as range formulas; `xlRangeFormula` writes them
from row and column numbers. A picture is read from its file when the workbook is closed, so
the file must still be there then.

## Reading a workbook

```livecodescript
on readReport pPath
   local tReader, tSheet, tRow
   put xlReadOpen(pPath) into tReader
   if tReader is 0 then
      answer xlLastError()
      exit readReport
   end if
   repeat with tSheet = 1 to xlReadSheetCount(tReader)
      put xlReadSheetName(tReader, tSheet) & ":" && xlReadRowCount(tReader, tSheet) && "rows" & return after field "log"
   end repeat
   put xlReadGrid(tReader, 1, 1, 1, 0, 0) into field "table"      -- sheet 1, everything
   put xlReadCell(tReader, 1, 2, 1) into field "first"            -- sheet 1, row 2, column 1
   xlReadClose tReader
end readReport
```

- **`xlReadCell` returns what the cell means**: text as text; a number to all its digits
  with a `.` decimal point (not rounded as the cell's format would show it); a date as
  `2026-11-20`, a time as `14:30:00`, or both; `true` or `false`; an error such as
  `#DIV/0!`. `xlReadCellValue` is the same but leaves a date as its serial number,
  `xlReadCellKind` says which of those it is, and `xlReadCellFormula` gives the formula.
- **`xlReadGrid` is the fast way.** One call returns a block as tab- and return-delimited
  text; 0 for the last row or column means "to the end". Inside a cell a tab comes back as a
  space and a line break as a vertical tab (`numToChar(11)`), so rows and cells stay put.
- **A sheet is loaded when first read** and kept until another sheet of the same reader is
  read, so read one sheet fully before moving to the next. `xlReadLoad` loads one on purpose
  and says whether it could.
- **Sheets are numbered from 1** in the order of their tabs; `xlReadSheetNumber` finds one
  by name.

### What the reader does not bring back

It reads the DATA of a workbook: values, formulas, number formats, merged blocks, sheet
names and whether a sheet is hidden. It does not report fonts, colours, borders, column
widths, charts, pictures, comments or data validation. It does not calculate: a formula
cell gives the result stored in the file, which is whatever the program that saved it last
calculated. Where Excel shares one formula between a run of cells, only the first holds the
text. It cannot open the old `.xls` format or a workbook encrypted with a password, and
says so.

## The limits every call is held to

Excel's own, and a few of xlsxt's so that a file from a stranger cannot exhaust the machine.
A call outside them is refused and `xlLastError()` says which.

| What | Limit |
|---|---|
| Rows, columns | 1,048,576 rows, 16,384 columns (Excel's grid) |
| Text in one cell | 32,767 characters |
| A formula | 8,192 characters |
| A sheet name | 31 characters, none of `[ ] : * ? / \`, unique in the workbook |
| A name, title or number format | 255 bytes |
| A file path | 4,096 bytes |
| One `xlSheetWriteGrid` text | 64 MB |
| Reading: sheets in a file | 4,096 |
| Reading: cells of one sheet | 10,000,000 |
| Reading: one XML part of the file, unpacked | 1 GB |
| Reading: one text result (a grid) | 512 MB |

## Good to know

- **Big files.** Writing keeps the workbook in memory until it is closed, about the size of
  what you wrote. A hundred thousand rows is fine; millions of cells want memory to match.
- **Temporary files.** Closing a workbook writes its parts to temporary files first.
  `xlSetTempFolder` chooses the folder when the system's own is not writable.
- **Sheet protection is not encryption.** `xlSheetProtect` stops accidental edits in Excel;
  anyone can read the file.
- **Text that looks like a formula.** `xlSheetWriteText` always writes text, even text that
  begins with `=`. Only `xlSheetWriteFormula` and the grid's `"formulas"` mode write a
  formula, so data typed by other people cannot become one by accident.
