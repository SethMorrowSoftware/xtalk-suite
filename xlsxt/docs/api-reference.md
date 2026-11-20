# xlsxt API reference

The 121 public handlers, from the doc blocks in `src/xlsxt.lcb` (the IDE dictionary reads the
same blocks; `tools/build-api-reference.py` writes this file from them, and its `--check` is a
gate). Read [getting-started.md](getting-started.md) first: it has a whole file written and one
read, the limits every call is held to, and what the reader does not bring back.

## The library

### `xlABIVersion`

`xlABIVersion() returns Integer`

Returns the ABI number of the native library that is loaded.

Returns: The ABI number; this binding needs 1.

### `xlLibraryVersion`

`xlLibraryVersion() returns String`

Returns the versions of the native library and of the libraries inside it.

Returns: Text such as "xlsxt ABI 1; libxlsxwriter 1.2.4; zlib 1.4; Expat 2.10.0".

It throws if the library on disk has a different ABI from this binding, which means the two come from different releases.

```
put xlLibraryVersion() into field "status"
```

### `xlLastError`

`xlLastError() returns String`

Returns why the last call was refused.

Returns: A short sentence, or empty if the last call was not refused.

A call given something it cannot use does nothing and returns 0 or empty; it never throws. This says what was wrong. Nearly every call clears it first, so ask straight after the call in question. A workbook also counts its own refusals: see `xlWorkbookErrorCount`.

```
put xlReadOpen(tPath) into tReader
if tReader is 0 then answer xlLastError()
```

### `xlSetTempFolder`

`xlSetTempFolder(in pFolder as String) returns nothing`

Chooses the folder that temporary files are made in while a workbook is written.

- pFolder: The path of a folder that exists and can be written to, or empty for the system's own temporary folder.

A workbook is assembled from temporary files when it is closed. The system's temporary folder is used unless this names another; a folder that cannot be used is passed over, not an error. It applies to workbooks made afterwards. On Android, where there is no shared temporary folder, the folder of the workbook itself is used unless this is set.

```
xlSetTempFolder specialFolderPath("temporary")
```

### `xlTempFolder`

`xlTempFolder() returns String`

Returns the folder chosen with xlSetTempFolder.

Returns: The path, or empty if none was chosen.

## Cell names and dates

### `xlColumnName`

`xlColumnName(in pColumn as Integer) returns String`

Returns the letters of a column.

- pColumn: The number of the column, 1 to 16384.

Returns: The letters: "A" for 1, "Z" for 26, "AA" for 27, "XFD" for 16384. Empty for a number outside that range.

```
put xlColumnName(28) -- AB
```

### `xlCellName`

`xlCellName(in pRow as Integer, in pColumn as Integer) returns String`

Returns the name of a cell.

- pRow: The row, 1 to 1048576.
- pColumn: The column, 1 to 16384.

Returns: The name, such as "B3" for row 3, column 2. Empty if the cell is outside the grid.

```
put xlCellName(3, 2) -- B3
```

### `xlRangeName`

`xlRangeName(in pFirstRow as Integer, in pFirstColumn as Integer, in pLastRow as Integer, in pLastColumn as Integer) returns String`

Returns the name of a range of cells.

- pFirstRow: The first row of the range; 1 is the first row.
- pFirstColumn: The first column of the range; 1 is column A.
- pLastRow: The last row of the range.
- pLastColumn: The last column of the range.

Returns: The name, such as "A1:B3". Empty if it is not a range inside the grid, first cell above and left of the last.

```
put xlRangeName(1, 1, 3, 2) -- A1:B3
```

### `xlRangeFormula`

`xlRangeFormula(in pSheetName as String, in pFirstRow as Integer, in pFirstColumn as Integer, in pLastRow as Integer, in pLastColumn as Integer) returns String`

Returns a range written the way a chart series or a defined name wants it.

- pSheetName: The name of the sheet the cells are on.
- pFirstRow: The first row of the range; 1 is the first row.
- pFirstColumn: The first column of the range; 1 is column A.
- pLastRow: The last row of the range.
- pLastColumn: The last column of the range.

Returns: A formula such as "=Sheet1!$A$2:$A$7". Empty if the name is empty or the range is not one.

A sheet name that holds a space or other punctuation is put in single quotes, as Excel requires. Use the result with `xlChartAddSeries` and `xlWorkbookDefineName`.

```
put xlRangeFormula("Sales", 2, 2, 7, 2) into tValues -- =Sales!$B$2:$B$7
```

### `xlCellRow`

`xlCellRow(in pName as String) returns Integer`

Returns the row of a cell name.

- pName: A cell name such as "B3" or "$B$3", in any letter case.

Returns: The row; 3 for B3. 0 if the text is not a cell name.

```
put xlCellRow("B3") -- 3
```

### `xlCellColumn`

`xlCellColumn(in pName as String) returns Integer`

Returns the column of a cell name.

- pName: A cell name such as "B3" or "$B$3", in any letter case.

Returns: The column; 2 for B3. 0 if the text is not a cell name.

```
put xlCellColumn("AB12") -- 28
```

### `xlDateToSerial`

`xlDateToSerial(in pYear as Integer, in pMonth as Integer, in pDay as Integer, in pHour as Integer, in pMinute as Integer, in pSecond as Number) returns Number`

Returns the number Excel uses for a date and time.

- pYear: The year, 1900 to 9999. Pass 0 for year, month and day to get a time of day alone.
- pMonth: The month, 1 to 12.
- pDay: The day of the month.
- pHour: The hour, 0 to 23.
- pMinute: The minute, 0 to 59.
- pSecond: The seconds, 0 up to 60; fractions are kept.

Returns: The serial: whole days counted from the start of 1900, plus the time as a fraction of a day. -1 if it is not a real date.

Excel stores a date as a number and shows it as a date because of the cell's format. Excel also believes 1900 was a leap year; this follows it, so the numbers agree with what Excel shows. Write the result with `xlSheetWriteDate`.

```
xlSheetWriteDate tSheet, 2, 1, xlDateToSerial(2026, 11, 20, 0, 0, 0), 0
```

### `xlSerialToDate`

`xlSerialToDate(in pSerial as Number) returns String`

Returns the date and time that a serial number stands for.

- pSerial: A date serial, 0 up to 2958466 (the end of the year 9999).

Returns: Text in the form "2026-11-20 14:30:00". Empty if the number is not a date serial.

The reverse of `xlDateToSerial`. Serial 60 comes back as 1900-02-29, the day Excel invented.

```
put xlSerialToDate(45292.5) -- 2024-01-01 12:00:00
```

### `xlSecondsToSerial`

`xlSecondsToSerial(in pSeconds as Number) returns Number`

Converts a count of seconds, such as the seconds, to a date serial.

- pSeconds: Seconds counted from the start of 1970, as the seconds returns.

Returns: The serial. -1 if the date falls outside 1900 to 9999.

No time zone is applied: a serial has none. The seconds counts in universal time, so add your offset first if the sheet should show local time.

```
xlSheetWriteDate tSheet, 1, 1, xlSecondsToSerial(the seconds), 0
```

### `xlSerialToSeconds`

`xlSerialToSeconds(in pSerial as Number) returns Number`

Converts a date serial to seconds counted from the start of 1970.

- pSerial: A date serial, 0 up to 2958466.

Returns: The seconds, rounded to a whole second. 0 if the number is not a date serial.

```
put xlSerialToSeconds(xlReadCellNumber(tReader, 1, 2, 1)) into tSeconds
convert tSeconds to long date
```

## Workbooks: writing a file

### `xlWorkbookCount`

`xlWorkbookCount() returns Integer`

Returns how many workbooks are open for writing.

Returns: The count.

A workbook stays open, holding memory, until `xlWorkbookClose` or `xlWorkbookDiscard`. A count that keeps growing means a script is not closing what it makes.

### `xlWorkbookNew`

`xlWorkbookNew(in pPath as String) returns Integer`

Starts a new workbook that will be saved as an .xlsx file.

- pPath: The full path of the file to write, usually ending .xlsx. A file already there is replaced when the workbook is closed.

Returns: A workbook handle, or 0 if the path cannot be used.

Nothing is written to disk until `xlWorkbookClose`. Add sheets with `xlWorkbookAddSheet`, fill them with the xlSheetWrite calls, then close. It throws if the native library has a different ABI from this binding.

```
put xlWorkbookNew(specialFolderPath("documents") & "/report.xlsx") into tBook
put xlWorkbookAddSheet(tBook, "Sales") into tSheet
xlSheetWriteText tSheet, 1, 1, "Month", 0
xlSheetWriteNumber tSheet, 2, 1, 1250.5, 0
if not xlWorkbookClose(tBook) then answer xlLastError()
```

### `xlWorkbookIsValid`

`xlWorkbookIsValid(in pBook as Integer) returns Boolean`

Reports whether a handle names an open workbook.

- pBook: A workbook handle from `xlWorkbookNew`.

Returns: True for a workbook that is open for writing.

### `xlWorkbookClose`

`xlWorkbookClose(in pBook as Integer) returns Boolean`

Writes the workbook to its file and closes it.

- pBook: A workbook handle from `xlWorkbookNew`.

Returns: True if the file was written. False if it could not be (the folder is missing, the disk is full, a picture has gone); `xlLastError` says why.

The workbook and every sheet, format and chart of it are gone afterwards, whether or not the file could be written, and their handles go dead. To keep a file from being written at all, use `xlWorkbookDiscard`.

```
if not xlWorkbookClose(tBook) then answer "Could not save:" && xlLastError()
```

### `xlWorkbookDiscard`

`xlWorkbookDiscard(in pBook as Integer) returns nothing`

Closes a workbook without writing its file.

- pBook: A workbook handle from `xlWorkbookNew`.

Everything made in the workbook is thrown away and its handles go dead. No file is written and a file already at the path is left alone.

### `xlWorkbookErrorCount`

`xlWorkbookErrorCount(in pBook as Integer) returns Integer`

Returns how many calls on a workbook have been refused.

- pBook: A workbook handle from `xlWorkbookNew`.

Returns: The count; 0 if every call so far was accepted.

Calls on the workbook's sheets, formats and charts count too. A script can write ten thousand cells and ask once, before closing, instead of checking `xlLastError` after each.

```
if xlWorkbookErrorCount(tBook) > 0 then answer xlWorkbookFirstError(tBook)
```

### `xlWorkbookFirstError`

`xlWorkbookFirstError(in pBook as Integer) returns String`

Returns why the first refused call on a workbook was refused.

- pBook: A workbook handle from `xlWorkbookNew`.

Returns: A short sentence, or empty if no call has been refused.

### `xlWorkbookSheetCount`

`xlWorkbookSheetCount(in pBook as Integer) returns Integer`

Returns how many sheets a workbook has so far.

- pBook: A workbook handle from `xlWorkbookNew`.

Returns: The count.

### `xlWorkbookAddSheet`

`xlWorkbookAddSheet(in pBook as Integer, in pName as String) returns Integer`

Adds a sheet to a workbook.

- pBook: A workbook handle from `xlWorkbookNew`.
- pName: The name on the sheet's tab, or empty for Excel's own "Sheet1", "Sheet2" and so on. At most 31 characters, none of [ ] : * ? / \, no apostrophe at either end, and not a name already used.

Returns: A sheet handle, or 0 if the name was refused.

Sheets appear in the file in the order they are added. A workbook closed with no sheet at all is given one empty sheet, because a workbook must have one.

```
put xlWorkbookAddSheet(tBook, "Sales") into tSheet
```

### `xlWorkbookAddFormat`

`xlWorkbookAddFormat(in pBook as Integer) returns Integer`

Makes a cell format: a font, colours, borders, a number format.

- pBook: A workbook handle from `xlWorkbookNew`.

Returns: A format handle, or 0.

A new format changes nothing until the xlFormatSet calls say what it is. Pass it to any call that writes a cell. A format is shared and not copied: changing it changes every cell written with it, before or after. It belongs to its workbook and cannot be used in another.

```
put xlWorkbookAddFormat(tBook) into tHeading
xlFormatSetBold tHeading, true
xlFormatSetBackgroundColor tHeading, "silver"
xlSheetWriteText tSheet, 1, 1, "Month", tHeading
```

### `xlWorkbookAddChart`

`xlWorkbookAddChart(in pBook as Integer, in pKind as String) returns Integer`

Makes a chart.

- pBook: A workbook handle from `xlWorkbookNew`.
- pKind: The kind of chart: column, bar, line or area (each also with " stacked" or " percent" after it, as in "column stacked"), pie, doughnut, scatter, scatter lines, scatter smooth, radar or radar markers.

Returns: A chart handle, or 0 if the kind is not one of those.

A chart shows cells of the workbook. Give it at least one series with `xlChartAddSeries`, then put it on a sheet with `xlSheetInsertChart`. A chart never placed on a sheet is left out of the file.

```
put xlWorkbookAddChart(tBook, "column") into tChart
get xlChartAddSeries(tChart, xlRangeFormula("Sales", 2, 1, 7, 1), xlRangeFormula("Sales", 2, 2, 7, 2))
xlChartSetTitle tChart, "Sales by month"
xlSheetInsertChart tSheet, 2, 5, tChart, 1, 1
```

### `xlWorkbookSetProperty`

`xlWorkbookSetProperty(in pBook as Integer, in pName as String, in pValue as String) returns nothing`

Sets one of the document properties Excel shows under File, Info.

- pBook: A workbook handle from `xlWorkbookNew`.
- pName: Which property: title, subject, author, manager, company, category, keywords, comments or status.
- pValue: The text of the property, or empty to clear it.

```
xlWorkbookSetProperty tBook, "author", "Accounts"
```

### `xlWorkbookDefineName`

`xlWorkbookDefineName(in pBook as Integer, in pName as String, in pFormula as String) returns nothing`

Gives a name to a cell, a range or a formula, for use in other formulas.

- pBook: A workbook handle from `xlWorkbookNew`.
- pName: The name, such as "Rate". Put a sheet name and an exclamation mark first ("Sales!Total") for a name that belongs to one sheet. It starts with a letter or underscore and cannot be the name of a cell.
- pFormula: What the name stands for, such as "=Sales!$B$1"; `xlRangeFormula` writes one. At most 127 bytes.

```
xlWorkbookDefineName tBook, "Rate", "=Sales!$B$1"
xlSheetWriteFormula tSheet, 3, 3, "=B3*Rate", 0
```

## Formats

### `xlFormatIsValid`

`xlFormatIsValid(in pFormat as Integer) returns Boolean`

Reports whether a handle names a format of an open workbook.

- pFormat: A format handle from `xlWorkbookAddFormat`.

Returns: True for a live format.

### `xlFormatSetBold`

`xlFormatSetBold(in pFormat as Integer, in pFlag as Boolean) returns nothing`

Makes a format bold, or not.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pFlag: True for bold.

### `xlFormatSetItalic`

`xlFormatSetItalic(in pFormat as Integer, in pFlag as Boolean) returns nothing`

Makes a format italic, or not.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pFlag: True for italic.

### `xlFormatSetStrikeout`

`xlFormatSetStrikeout(in pFormat as Integer, in pFlag as Boolean) returns nothing`

Strikes the text of a format through, or not.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pFlag: True to strike the text through.

### `xlFormatSetUnderline`

`xlFormatSetUnderline(in pFormat as Integer, in pStyle as String) returns nothing`

Sets how a format underlines text.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pStyle: none, single, double, single accounting or double accounting.

### `xlFormatSetScript`

`xlFormatSetScript(in pFormat as Integer, in pStyle as String) returns nothing`

Raises or lowers the text of a format.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pStyle: none, superscript or subscript.

### `xlFormatSetFontName`

`xlFormatSetFontName(in pFormat as Integer, in pName as String) returns nothing`

Sets the font of a format.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pName: The name of the font, such as "Arial". Excel substitutes another if the reader's computer does not have it.

```
xlFormatSetFontName tFormat, "Courier New"
```

### `xlFormatSetFontSize`

`xlFormatSetFontSize(in pFormat as Integer, in pSize as Number) returns nothing`

Sets the font size of a format.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pSize: The size in points, 1 to 409. Excel's usual size is 11.

### `xlFormatSetFontColor`

`xlFormatSetFontColor(in pFormat as Integer, in pColor as String) returns nothing`

Sets the colour of the text of a format.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pColor: A colour: "#RRGGBB", "r,g,b" with each part 0 to 255, or a basic colour name such as red, navy or silver.

```
xlFormatSetFontColor tFormat, "#C00000"
```

### `xlFormatSetBackgroundColor`

`xlFormatSetBackgroundColor(in pFormat as Integer, in pColor as String) returns nothing`

Fills the cells of a format with a colour.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pColor: A colour: "#RRGGBB", "r,g,b" with each part 0 to 255, or a basic colour name such as red, navy or silver.

```
xlFormatSetBackgroundColor tFormat, "255,242,204"
```

### `xlFormatSetNumberFormat`

`xlFormatSetNumberFormat(in pFormat as Integer, in pCode as String) returns nothing`

Sets how a format shows numbers and dates.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pCode: An Excel number format code, such as "0.00", "#,##0", "0%", "yyyy-mm-dd" or "@" for text.

The code is Excel's own, the one its Format Cells dialog shows under Custom. A date is a number with a date code: see `xlSheetWriteDate`.

```
xlFormatSetNumberFormat tMoney, "#,##0.00"
```

### `xlFormatSetAlign`

`xlFormatSetAlign(in pFormat as Integer, in pAlignment as String) returns nothing`

Sets how a format places text across the cell.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pAlignment: general, left, center, right, fill, justify, center across or distributed.

### `xlFormatSetVerticalAlign`

`xlFormatSetVerticalAlign(in pFormat as Integer, in pAlignment as String) returns nothing`

Sets how a format places text up and down the cell.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pAlignment: top, middle, bottom, justify or distributed.

### `xlFormatSetTextWrap`

`xlFormatSetTextWrap(in pFormat as Integer, in pFlag as Boolean) returns nothing`

Lets long text wrap onto more lines inside the cell, or not.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pFlag: True to wrap.

A cell whose text holds line breaks shows them only when its format wraps.

### `xlFormatSetShrink`

`xlFormatSetShrink(in pFormat as Integer, in pFlag as Boolean) returns nothing`

Shrinks text to fit the width of the cell, or not.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pFlag: True to shrink.

### `xlFormatSetRotation`

`xlFormatSetRotation(in pFormat as Integer, in pDegrees as Integer) returns nothing`

Turns the text of a format.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pDegrees: The angle, -90 to 90, or 270 for letters stacked top to bottom.

### `xlFormatSetIndent`

`xlFormatSetIndent(in pFormat as Integer, in pLevel as Integer) returns nothing`

Indents the text of a format.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pLevel: How far, 0 to 250; each step is about one character.

### `xlFormatSetBorder`

`xlFormatSetBorder(in pFormat as Integer, in pStyle as String) returns nothing`

Draws a border on all four sides of the cells of a format.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pStyle: The kind of line: none, thin, medium, thick, dashed, dotted, double, hair, medium dashed, dash dot, medium dash dot, dash dot dot, medium dash dot dot or slant dash dot.

```
xlFormatSetBorder tFormat, "thin"
```

### `xlFormatSetBorderSide`

`xlFormatSetBorderSide(in pFormat as Integer, in pSide as String, in pStyle as String) returns nothing`

Draws a border on one side of the cells of a format.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pSide: left, right, top or bottom.
- pStyle: The kind of line: none, thin, medium, thick, dashed, dotted, double, hair, medium dashed, dash dot, medium dash dot, dash dot dot, medium dash dot dot or slant dash dot.

```
xlFormatSetBorderSide tTotals, "top", "double"
```

### `xlFormatSetBorderColor`

`xlFormatSetBorderColor(in pFormat as Integer, in pColor as String) returns nothing`

Sets the colour of the borders of a format.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pColor: A colour: "#RRGGBB", "r,g,b" with each part 0 to 255, or a basic colour name such as red, navy or silver.

### `xlFormatSetLocked`

`xlFormatSetLocked(in pFormat as Integer, in pFlag as Boolean) returns nothing`

Says whether cells of a format can be edited once the sheet is protected.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pFlag: True (the default) to lock the cells; false to leave them editable.

It matters only on a sheet protected with `xlSheetProtect`: there every cell is locked unless its format says otherwise.

### `xlFormatSetFormulaHidden`

`xlFormatSetFormulaHidden(in pFormat as Integer, in pFlag as Boolean) returns nothing`

Hides the formulas of cells of a format once the sheet is protected.

- pFormat: A format handle from `xlWorkbookAddFormat`.
- pFlag: True to hide the formula; the result still shows.

It matters only on a sheet protected with `xlSheetProtect`.

## Sheets: cells

### `xlSheetIsValid`

`xlSheetIsValid(in pSheet as Integer) returns Boolean`

Reports whether a handle names a sheet of an open workbook.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.

Returns: True for a live sheet.

### `xlSheetName`

`xlSheetName(in pSheet as Integer) returns String`

Returns the name of a sheet.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.

Returns: The name on the sheet's tab. Empty for a handle that is not a sheet.

Useful when the sheet was added with an empty name and Excel's own was used: `xlRangeFormula` needs the name.

### `xlSheetWriteNumber`

`xlSheetWriteNumber(in pSheet as Integer, in pRow as Integer, in pColumn as Integer, in pNumber as Number, in pFormat as Integer) returns nothing`

Writes a number into a cell.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.
- pNumber: The number.
- pFormat: A format handle from `xlWorkbookAddFormat`, or 0 for no format.

The cell holds the number itself, to all its digits; a format decides how many of them show.

```
xlSheetWriteNumber tSheet, 2, 2, 1250.5, 0
```

### `xlSheetWriteText`

`xlSheetWriteText(in pSheet as Integer, in pRow as Integer, in pColumn as Integer, in pText as String, in pFormat as Integer) returns nothing`

Writes text into a cell.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.
- pText: The text, at most 32767 characters. A return inside it is a line break in the cell.
- pFormat: A format handle from `xlWorkbookAddFormat`, or 0 for no format.

The cell holds text even when the text looks like a number: "007" stays 007. Empty text writes nothing. Use `xlSheetWriteNumber` for a number that should add up.

```
xlSheetWriteText tSheet, 1, 1, "Month", tHeading
```

### `xlSheetWriteFormula`

`xlSheetWriteFormula(in pSheet as Integer, in pRow as Integer, in pColumn as Integer, in pFormula as String, in pFormat as Integer) returns nothing`

Writes a formula into a cell.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.
- pFormula: The formula as it is typed in Excel, in English and with commas between arguments, such as "=SUM(B2:B7)".
- pFormat: A format handle from `xlWorkbookAddFormat`, or 0 for no format.

This library does not calculate. Excel, LibreOffice and Numbers work the result out when they open the file; a viewer that does not calculate, and this library's own reading calls, see 0. Use `xlSheetWriteFormulaValue` to store a result with the formula.

```
xlSheetWriteFormula tSheet, 8, 2, "=SUM(B2:B7)", 0
```

### `xlSheetWriteFormulaValue`

`xlSheetWriteFormulaValue(in pSheet as Integer, in pRow as Integer, in pColumn as Integer, in pFormula as String, in pValue as Number, in pFormat as Integer) returns nothing`

Writes a formula into a cell, along with the result to show before it is calculated.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.
- pFormula: The formula, such as "=B2*C2".
- pValue: The result to store with it.
- pFormat: A format handle from `xlWorkbookAddFormat`, or 0 for no format.

For files that will be read by programs that do not calculate formulas. A spreadsheet program replaces the stored result with its own when it opens the file.

```
xlSheetWriteFormulaValue tSheet, 2, 4, "=B2*C2", tQty * tPrice, 0
```

### `xlSheetWriteBoolean`

`xlSheetWriteBoolean(in pSheet as Integer, in pRow as Integer, in pColumn as Integer, in pFlag as Boolean, in pFormat as Integer) returns nothing`

Writes TRUE or FALSE into a cell.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.
- pFlag: The value.
- pFormat: A format handle from `xlWorkbookAddFormat`, or 0 for no format.

### `xlSheetWriteBlank`

`xlSheetWriteBlank(in pSheet as Integer, in pRow as Integer, in pColumn as Integer, in pFormat as Integer) returns nothing`

Gives an empty cell a format.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.
- pFormat: A format handle from `xlWorkbookAddFormat`. With 0 there is nothing to write and nothing is written.

For a border or a fill on a cell that holds no value.

### `xlSheetWriteDate`

`xlSheetWriteDate(in pSheet as Integer, in pRow as Integer, in pColumn as Integer, in pSerial as Number, in pFormat as Integer) returns nothing`

Writes a date, a time or both into a cell.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.
- pSerial: The date as a serial number, from `xlDateToSerial` or `xlSecondsToSerial`.
- pFormat: A format handle whose number format is a date code, or 0 to have one chosen: "yyyy-mm-dd" for a date, "yyyy-mm-dd hh:mm:ss" for a date and time, "hh:mm:ss" for a time alone.

A date in a spreadsheet is a number that a format shows as a date. This writes the number and makes sure there is such a format.

```
xlSheetWriteDate tSheet, 2, 1, xlDateToSerial(2026, 11, 20, 0, 0, 0), 0
```

### `xlSheetWriteLink`

`xlSheetWriteLink(in pSheet as Integer, in pRow as Integer, in pColumn as Integer, in pUrl as String, in pText as String, in pFormat as Integer) returns nothing`

Writes a link into a cell.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.
- pUrl: Where the link goes. It begins http://, https://, ftp://, file://, or "mailto:", or "internal:" followed by a cell of this workbook ("internal:Sales!A1"), or "external:" followed by another file.
- pText: What the cell shows, or empty to show the link itself.
- pFormat: A format handle, or 0 for the usual blue underlined link.

```
xlSheetWriteLink tSheet, 1, 4, "https://openxtalk.org", "OpenXTalk", 0
```

### `xlSheetWriteComment`

`xlSheetWriteComment(in pSheet as Integer, in pRow as Integer, in pColumn as Integer, in pText as String) returns nothing`

Attaches a note to a cell.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.
- pText: The text of the note.

The note appears when the pointer rests on the cell, which shows a small mark in its corner.

### `xlSheetWriteGrid`

`xlSheetWriteGrid(in pSheet as Integer, in pRow as Integer, in pColumn as Integer, in pText as String, in pMode as String, in pFormat as Integer) returns Integer`

Writes a whole table of cells from one text.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row of the top left cell of the table.
- pColumn: The column of the top left cell of the table.
- pText: The table: rows separated by returns, cells within a row by tabs.
- pMode: "text" to write every cell as text; "numbers" to write a cell that reads as a number as a number; "formulas" to do that and also write a cell that begins with = as a formula.
- pFormat: A format handle for every cell written, or 0 for none.

Returns: The number of cells written. An empty cell is skipped and not counted.

This is the quick way to put a tab-delimited field, or the lines of a file, onto a sheet. In the "numbers" and "formulas" modes, a number is digits with an optional sign, decimal point and exponent, at most 15 digits and no leading zero, so a postcode, a phone number or a card number stays text. A vertical tab (numToChar(11)) inside a cell becomes a line break. A cell that cannot be written (text that is not valid, or a table that runs off the edge of the sheet) is skipped and counted in `xlWorkbookErrorCount`; the rest is still written. `xlReadGrid` returns the same shape.

```
put xlSheetWriteGrid(tSheet, 1, 1, the text of field "table", "numbers", 0) into tCount
```

## Sheets: layout

### `xlSheetSetColumns`

`xlSheetSetColumns(in pSheet as Integer, in pFirstColumn as Integer, in pLastColumn as Integer, in pWidth as Number, in pFormat as Integer) returns nothing`

Sets the width of one or more columns, and their format.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pFirstColumn: The first column; 1 is column A.
- pLastColumn: The last column; the same number for one column.
- pWidth: The width in Excel's units, about one digit of the usual font each, 0 to 255. Excel's own width is 8.43.
- pFormat: A format handle for cells of these columns that have none of their own, or 0.

```
xlSheetSetColumns tSheet, 1, 1, 24, 0
```

### `xlSheetHideColumns`

`xlSheetHideColumns(in pSheet as Integer, in pFirstColumn as Integer, in pLastColumn as Integer) returns nothing`

Hides one or more columns.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pFirstColumn: The first column; 1 is column A.
- pLastColumn: The last column.

### `xlSheetSetRow`

`xlSheetSetRow(in pSheet as Integer, in pRow as Integer, in pHeight as Number, in pFormat as Integer) returns nothing`

Sets the height of a row, and its format.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row; 1 is the first.
- pHeight: The height in points, 0 to 409. Excel's own height is 15.
- pFormat: A format handle for cells of this row that have none of their own, or 0.

### `xlSheetHideRow`

`xlSheetHideRow(in pSheet as Integer, in pRow as Integer) returns nothing`

Hides a row.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row; 1 is the first.

### `xlSheetMerge`

`xlSheetMerge(in pSheet as Integer, in pFirstRow as Integer, in pFirstColumn as Integer, in pLastRow as Integer, in pLastColumn as Integer, in pText as String, in pFormat as Integer) returns nothing`

Merges a block of cells into one and writes text into it.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pFirstRow: The first row of the range; 1 is the first row.
- pFirstColumn: The first column of the range; 1 is column A.
- pLastRow: The last row of the range.
- pLastColumn: The last column of the range.
- pText: The text the merged cell holds, or empty.
- pFormat: A format handle for the merged cell, or 0. Centred text is the usual choice.

The block must be two cells or more.

```
xlSheetMerge tSheet, 1, 1, 1, 4, "Quarterly report", tTitleFormat
```

### `xlSheetFreeze`

`xlSheetFreeze(in pSheet as Integer, in pRows as Integer, in pColumns as Integer) returns nothing`

Keeps the top rows and left columns in view while the rest of the sheet scrolls.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRows: How many rows to keep at the top; 0 for none.
- pColumns: How many columns to keep at the left; 0 for none.

```
xlSheetFreeze tSheet, 1, 0 -- a heading row that stays put
```

### `xlSheetAutofilter`

`xlSheetAutofilter(in pSheet as Integer, in pFirstRow as Integer, in pFirstColumn as Integer, in pLastRow as Integer, in pLastColumn as Integer) returns nothing`

Puts filter buttons on the heading row of a range.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pFirstRow: The heading row of the range.
- pFirstColumn: The first column of the range; 1 is column A.
- pLastRow: The last row of the range.
- pLastColumn: The last column of the range.

The reader of the file can then sort and filter the rows below the headings. No row is hidden by this call.

```
xlSheetAutofilter tSheet, 1, 1, 200, 4
```

### `xlSheetValidateList`

`xlSheetValidateList(in pSheet as Integer, in pFirstRow as Integer, in pFirstColumn as Integer, in pLastRow as Integer, in pLastColumn as Integer, in pItems as String) returns nothing`

Gives every cell of a range a drop-down list of allowed values.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pFirstRow: The first row of the range; 1 is the first row.
- pFirstColumn: The first column of the range; 1 is column A.
- pLastRow: The last row of the range.
- pLastColumn: The last column of the range.
- pItems: The allowed values, separated by commas; at most 255 bytes in all.

```
xlSheetValidateList tSheet, 2, 3, 200, 3, "open,closed,pending"
```

### `xlSheetInsertImage`

`xlSheetInsertImage(in pSheet as Integer, in pRow as Integer, in pColumn as Integer, in pPath as String, in pXScale as Number, in pYScale as Number) returns nothing`

Puts a picture on a sheet.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row of the cell under the picture's top left corner.
- pColumn: The column of that cell.
- pPath: The full path of a PNG, JPEG, GIF or BMP file.
- pXScale: How wide to draw it: 1 for full size, 0.5 for half.
- pYScale: How tall to draw it: 1 for full size.

The picture floats over the cells; it is not inside one. The file is read again when the workbook is closed, so it must still be there then.

```
xlSheetInsertImage tSheet, 1, 6, tLogoPath, 0.5, 0.5
```

## Sheets: the page and the view

### `xlSheetSetLandscape`

`xlSheetSetLandscape(in pSheet as Integer, in pFlag as Boolean) returns nothing`

Sets whether a sheet prints sideways.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pFlag: True for landscape, false for portrait.

### `xlSheetSetPaper`

`xlSheetSetPaper(in pSheet as Integer, in pPaper as Integer) returns nothing`

Sets the paper a sheet prints on.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pPaper: Excel's paper number: 1 Letter, 5 Legal, 8 A3, 9 A4, 11 A5; 0 for the printer's own.

### `xlSheetSetMargins`

`xlSheetSetMargins(in pSheet as Integer, in pLeft as Number, in pRight as Number, in pTop as Number, in pBottom as Number) returns nothing`

Sets the margins a sheet prints with.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pLeft: The left margin in inches.
- pRight: The right margin in inches.
- pTop: The top margin in inches.
- pBottom: The bottom margin in inches.

### `xlSheetFitToPages`

`xlSheetFitToPages(in pSheet as Integer, in pWide as Integer, in pTall as Integer) returns nothing`

Shrinks a sheet's print to fit a number of pages.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pWide: How many pages across; 0 for as many as it takes.
- pTall: How many pages down; 0 for as many as it takes.

```
xlSheetFitToPages tSheet, 1, 0 -- one page wide, however long
```

### `xlSheetSetHeader`

`xlSheetSetHeader(in pSheet as Integer, in pText as String) returns nothing`

Sets the text printed at the top of every page of a sheet.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pText: The header, at most 255 bytes, using Excel's codes: &L, &C and &R start the left, centre and right parts; &P is the page number, &N the page count, &D the date, &F the file name, &A the sheet name.

```
xlSheetSetHeader tSheet, "&LSales&RPage &P of &N"
```

### `xlSheetSetFooter`

`xlSheetSetFooter(in pSheet as Integer, in pText as String) returns nothing`

Sets the text printed at the bottom of every page of a sheet.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pText: The footer, with the same codes as `xlSheetSetHeader`.

### `xlSheetRepeatRows`

`xlSheetRepeatRows(in pSheet as Integer, in pFirstRow as Integer, in pLastRow as Integer) returns nothing`

Prints a run of rows again at the top of every page.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pFirstRow: The first row to repeat; 1 is the first row.
- pLastRow: The last row to repeat.

### `xlSheetPrintArea`

`xlSheetPrintArea(in pSheet as Integer, in pFirstRow as Integer, in pFirstColumn as Integer, in pLastRow as Integer, in pLastColumn as Integer) returns nothing`

Limits what prints to one range of a sheet.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pFirstRow: The first row of the range; 1 is the first row.
- pFirstColumn: The first column of the range; 1 is column A.
- pLastRow: The last row of the range.
- pLastColumn: The last column of the range.

### `xlSheetSetZoom`

`xlSheetSetZoom(in pSheet as Integer, in pPercent as Integer) returns nothing`

Sets how far a sheet is zoomed when the file opens.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pPercent: The zoom, 10 to 400; 100 is full size.

### `xlSheetShowGridlines`

`xlSheetShowGridlines(in pSheet as Integer, in pScreenFlag as Boolean, in pPrintFlag as Boolean) returns nothing`

Shows or hides the grey lines between cells.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pScreenFlag: True to show them on screen.
- pPrintFlag: True to print them.

### `xlSheetSetTabColor`

`xlSheetSetTabColor(in pSheet as Integer, in pColor as String) returns nothing`

Colours the tab of a sheet.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pColor: A colour: "#RRGGBB", "r,g,b" with each part 0 to 255, or a basic colour name such as red, navy or silver.

### `xlSheetActivate`

`xlSheetActivate(in pSheet as Integer) returns nothing`

Makes this the sheet that shows when the file opens.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.

### `xlSheetHide`

`xlSheetHide(in pSheet as Integer) returns nothing`

Hides a sheet.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.

The reader of the file can bring it back from Excel's sheet menu. The sheet shown when the file opens (the first, unless `xlSheetActivate` chose another) cannot be hidden.

### `xlSheetProtect`

`xlSheetProtect(in pSheet as Integer, in pPassword as String) returns nothing`

Stops a sheet's cells from being edited.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pPassword: A password to ask for before the protection can be removed, or empty for none.

Every cell is locked unless its format was unlocked with `xlFormatSetLocked`. This is a guard against accidents, not security: the file is not encrypted and the password is easy to remove.

## Charts

### `xlChartIsValid`

`xlChartIsValid(in pChart as Integer) returns Boolean`

Reports whether a handle names a chart of an open workbook.

- pChart: A chart handle from `xlWorkbookAddChart`.

Returns: True for a live chart.

### `xlChartSeriesCount`

`xlChartSeriesCount(in pChart as Integer) returns Integer`

Returns how many series a chart has.

- pChart: A chart handle from `xlWorkbookAddChart`.

Returns: The count.

### `xlChartAddSeries`

`xlChartAddSeries(in pChart as Integer, in pCategories as String, in pValues as String) returns Integer`

Adds a series, a set of values to plot, to a chart.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pCategories: The cells that hold the labels along the bottom, as a range formula such as "=Sales!$A$2:$A$7", or empty to number the points. A scatter chart needs them: they are its x values.
- pValues: The cells that hold the numbers to plot, as a range formula such as "=Sales!$B$2:$B$7".

Returns: The number of the new series, counting from 1, or 0 if it was refused.

`xlRangeFormula` writes the formulas from row and column numbers. The chart reads the cells when the file is opened, so the cells can be written before or after this call.

```
get xlChartAddSeries(tChart, xlRangeFormula("Sales", 2, 1, 7, 1), xlRangeFormula("Sales", 2, 2, 7, 2))
```

### `xlChartSeriesSetName`

`xlChartSeriesSetName(in pChart as Integer, in pSeries as Integer, in pName as String) returns nothing`

Names a series; the name shows in the chart's legend.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pSeries: The number of the series, as `xlChartAddSeries` returned it; 1 is the first.
- pName: The name, or a formula such as "=Sales!$B$1" to take it from a cell.

### `xlChartSeriesSetColor`

`xlChartSeriesSetColor(in pChart as Integer, in pSeries as Integer, in pColor as String) returns nothing`

Sets the colour a series is drawn in.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pSeries: The number of the series, as `xlChartAddSeries` returned it; 1 is the first.
- pColor: A colour: "#RRGGBB", "r,g,b" with each part 0 to 255, or a basic colour name such as red, navy or silver.

### `xlChartSeriesSetLabels`

`xlChartSeriesSetLabels(in pChart as Integer, in pSeries as Integer, in pFlag as Boolean) returns nothing`

Shows each point's value beside it, or not.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pSeries: The number of the series, as `xlChartAddSeries` returned it; 1 is the first.
- pFlag: True to show the values.

### `xlChartSeriesSetSmooth`

`xlChartSeriesSetSmooth(in pChart as Integer, in pSeries as Integer, in pFlag as Boolean) returns nothing`

Draws the line of a series as a smooth curve, or not.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pSeries: The number of the series, as `xlChartAddSeries` returned it; 1 is the first.
- pFlag: True for a curve. It has an effect on line and scatter charts.

### `xlChartSeriesSetMarker`

`xlChartSeriesSetMarker(in pChart as Integer, in pSeries as Integer, in pKind as String) returns nothing`

Sets the mark drawn at each point of a series.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pSeries: The number of the series, as `xlChartAddSeries` returned it; 1 is the first.
- pKind: automatic, none, square, diamond, triangle, x, star, circle, short dash or long dash.

### `xlChartSetTitle`

`xlChartSetTitle(in pChart as Integer, in pTitle as String) returns nothing`

Sets the title of a chart.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pTitle: The title, a formula such as "=Sales!$A$1" to take it from a cell, or empty for no title.

### `xlChartSetAxisTitle`

`xlChartSetAxisTitle(in pChart as Integer, in pAxis as String, in pTitle as String) returns nothing`

Sets the title of an axis of a chart.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pAxis: "x" for the axis along the bottom or "y" for the axis up the side.
- pTitle: The title, or a formula such as "=Sales!$B$1" to take it from a cell.

```
xlChartSetAxisTitle tChart, "y", "Sales (thousands)"
```

### `xlChartSetAxisRange`

`xlChartSetAxisRange(in pChart as Integer, in pAxis as String, in pMinimum as Number, in pMaximum as Number) returns nothing`

Sets the lowest and highest values an axis shows.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pAxis: "x" for the axis along the bottom or "y" for the axis up the side.
- pMinimum: The lowest value.
- pMaximum: The highest value; above the lowest.

Only an axis of values has a range: the y axis of most charts, and both axes of a scatter chart. On an axis of labels the call is refused.

### `xlChartSetAxisNumberFormat`

`xlChartSetAxisNumberFormat(in pChart as Integer, in pAxis as String, in pCode as String) returns nothing`

Sets how the numbers along an axis are shown.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pAxis: "x" for the axis along the bottom or "y" for the axis up the side.
- pCode: An Excel number format code, such as "#,##0" or "0%".

### `xlChartSetAxisGridlines`

`xlChartSetAxisGridlines(in pChart as Integer, in pAxis as String, in pFlag as Boolean) returns nothing`

Shows or hides the lines a chart draws across from an axis.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pAxis: "x" for the axis along the bottom or "y" for the axis up the side.
- pFlag: True to show them.

### `xlChartSetLegend`

`xlChartSetLegend(in pChart as Integer, in pPosition as String) returns nothing`

Places the legend of a chart, or removes it.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pPosition: none, right, left, top, bottom or top right.

### `xlChartSetStyle`

`xlChartSetStyle(in pChart as Integer, in pStyle as Integer) returns nothing`

Gives a chart one of Excel's built-in looks.

- pChart: A chart handle from `xlWorkbookAddChart`.
- pStyle: The number of the style, 1 to 48, as Excel's Chart Styles gallery counts them.

### `xlSheetInsertChart`

`xlSheetInsertChart(in pSheet as Integer, in pRow as Integer, in pColumn as Integer, in pChart as Integer, in pXScale as Number, in pYScale as Number) returns nothing`

Puts a chart on a sheet.

- pSheet: A sheet handle from `xlWorkbookAddSheet`.
- pRow: The row of the cell under the chart's top left corner.
- pColumn: The column of that cell.
- pChart: A chart handle from `xlWorkbookAddChart`.
- pXScale: How wide to draw it: 1 for the usual size.
- pYScale: How tall to draw it: 1 for the usual size.

The chart needs at least one series first, and goes on one sheet, once; make another chart for a second copy.

```
xlSheetInsertChart tSheet, 2, 6, tChart, 1.5, 1
```

## Reading a file

### `xlReadCount`

`xlReadCount() returns Integer`

Returns how many files are open for reading.

Returns: The count.

A file stays open until `xlReadClose`. A count that keeps growing means a script is not closing what it opens.

### `xlReadOpen`

`xlReadOpen(in pPath as String) returns Integer`

Opens an .xlsx file for reading.

- pPath: The full path of the file.

Returns: A reader handle, or 0 if the file cannot be opened or is not an .xlsx workbook; `xlLastError` says which.

This reads the list of sheets; a sheet's cells are read the first time they are asked for. The file is not changed and cannot be changed through the reader. The older .xls format and workbooks encrypted with a password are not read. It throws if the native library has a different ABI from this binding.

```
put xlReadOpen(tPath) into tReader
if tReader is 0 then
answer xlLastError()
exit mouseUp
end if
put xlReadGrid(tReader, 1, 1, 1, 0, 0) into field "table"
xlReadClose tReader
```

### `xlReadClose`

`xlReadClose(in pReader as Integer) returns nothing`

Closes a file opened with xlReadOpen.

- pReader: A reader handle from `xlReadOpen`.

The handle goes dead and the memory the file's cells took is given back.

### `xlReadIsValid`

`xlReadIsValid(in pReader as Integer) returns Boolean`

Reports whether a handle names a file that is open for reading.

- pReader: A reader handle from `xlReadOpen`.

Returns: True for an open reader.

### `xlReadSheetCount`

`xlReadSheetCount(in pReader as Integer) returns Integer`

Returns how many sheets a file has.

- pReader: A reader handle from `xlReadOpen`.

Returns: The count; 0 for a handle that is not a reader.

### `xlReadSheetName`

`xlReadSheetName(in pReader as Integer, in pSheet as Integer) returns String`

Returns the name of a sheet of a file.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.

Returns: The name on the sheet's tab. Empty if there is no such sheet.

```
repeat with i = 1 to xlReadSheetCount(tReader)
put xlReadSheetName(tReader, i) & return after tNames
end repeat
```

### `xlReadSheetNumber`

`xlReadSheetNumber(in pReader as Integer, in pName as String) returns Integer`

Finds a sheet of a file by its name.

- pReader: A reader handle from `xlReadOpen`.
- pName: The name on the sheet's tab; letter case does not matter.

Returns: The number of the sheet, or 0 if the file has no sheet of that name.

```
put xlReadSheetNumber(tReader, "Sales") into tSheet
```

### `xlReadSheetIsHidden`

`xlReadSheetIsHidden(in pReader as Integer, in pSheet as Integer) returns Boolean`

Reports whether a sheet of a file is hidden.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.

Returns: True for a hidden sheet.

### `xlReadUses1904`

`xlReadUses1904(in pReader as Integer) returns Boolean`

Reports whether a file counts its dates from 1904.

- pReader: A reader handle from `xlReadOpen`.

Returns: True for a file that counts from 1904, as some written on older Macs do.

The reading calls already allow for it when they show a date. It matters only to a script that does its own arithmetic on the serial numbers from `xlReadCellNumber`: in such a file serial 0 is the first day of 1904.

### `xlReadLoad`

`xlReadLoad(in pReader as Integer, in pSheet as Integer) returns Boolean`

Reads a sheet's cells into memory and reports whether that worked.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.

Returns: True if the sheet was read. False if it is damaged or missing; `xlLastError` says why.

Every other reading call does this itself when it needs to, so calling it is optional. Calling it first tells a damaged sheet apart from an empty one. One sheet is held at a time: asking for another lets the first go, and coming back reads it again.

```
if not xlReadLoad(tReader, 1) then answer xlLastError()
```

### `xlReadRowCount`

`xlReadRowCount(in pReader as Integer, in pSheet as Integer) returns Integer`

Returns the number of the last row of a sheet that holds anything.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.

Returns: The row number; 0 for an empty sheet.

### `xlReadColumnCount`

`xlReadColumnCount(in pReader as Integer, in pSheet as Integer) returns Integer`

Returns the number of the last column of a sheet that holds anything.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.

Returns: The column number; 0 for an empty sheet.

### `xlReadCell`

`xlReadCell(in pReader as Integer, in pSheet as Integer, in pRow as Integer, in pColumn as Integer) returns String`

Returns what a cell shows.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.

Returns: The cell's text; a number as plain digits with a "." decimal point; a date as "2026-11-20", a time as "14:30:00", or both; "true" or "false"; an error such as "#DIV/0!". Empty for an empty cell.

A number comes back to all its digits, not rounded as its format would show it. For a formula cell this is the result stored in the file. Use `xlReadCellValue` to get a date as its serial number instead, and `xlReadGrid` to read many cells in one call.

```
put xlReadCell(tReader, 1, 2, 1) into tName
```

### `xlReadCellValue`

`xlReadCellValue(in pReader as Integer, in pSheet as Integer, in pRow as Integer, in pColumn as Integer) returns String`

Returns what a cell holds, with a date left as its number.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.

Returns: As `xlReadCell`, except that a date or time comes back as its serial number.

### `xlReadCellNumber`

`xlReadCellNumber(in pReader as Integer, in pSheet as Integer, in pRow as Integer, in pColumn as Integer) returns Number`

Returns the number a cell holds.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.

Returns: The number; a date's serial number; 1 or 0 for true or false. 0 for an empty cell or one that holds text.

### `xlReadCellKind`

`xlReadCellKind(in pReader as Integer, in pSheet as Integer, in pRow as Integer, in pColumn as Integer) returns String`

Returns what kind of value a cell holds.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.

Returns: "empty", "number", "date", "text", "boolean" or "error".

A date is a number whose format shows it as a date or a time.

### `xlReadCellFormula`

`xlReadCellFormula(in pReader as Integer, in pSheet as Integer, in pRow as Integer, in pColumn as Integer) returns String`

Returns the formula of a cell.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.

Returns: The formula with its = sign, such as "=SUM(B2:B7)". Empty for a cell with no formula.

Where Excel shares one formula between a run of cells, only the first of them holds the text.

### `xlReadCellFormat`

`xlReadCellFormat(in pReader as Integer, in pSheet as Integer, in pRow as Integer, in pColumn as Integer) returns String`

Returns the number format of a cell.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.
- pRow: The row of the cell; 1 is the first row.
- pColumn: The column of the cell; 1 is column A.

Returns: The Excel format code, such as "General", "0.00" or "yyyy-mm-dd". Empty for an empty cell.

### `xlReadGrid`

`xlReadGrid(in pReader as Integer, in pSheet as Integer, in pFirstRow as Integer, in pFirstColumn as Integer, in pLastRow as Integer, in pLastColumn as Integer) returns String`

Returns a block of cells as one text.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.
- pFirstRow: The first row to return; 1 is the first row.
- pFirstColumn: The first column to return; 1 is column A.
- pLastRow: The last row to return, or 0 for the last row that holds anything.
- pLastColumn: The last column to return, or 0 for all of them.

Returns: The cells, rows separated by returns and cells within a row by tabs, each as `xlReadCell` would return it.

The fastest way to read a sheet: one call for the block, then the item and line chunks, or split, to take it apart. Each row stops at its own last cell, and an empty row is an empty line. Inside a cell a tab comes back as a space and a line break as a vertical tab (numToChar(11)), so that the rows and cells stay where they are. `xlSheetWriteGrid` takes the same shape.

```
put xlReadGrid(tReader, 1, 1, 1, 0, 0) into field "table" -- the whole first sheet
```

### `xlReadMerged`

`xlReadMerged(in pReader as Integer, in pSheet as Integer) returns String`

Returns the merged blocks of a sheet.

- pReader: A reader handle from `xlReadOpen`.
- pSheet: The number of the sheet; 1 is the first.

Returns: One range such as "A1:C1" per line. Empty if the sheet has none.

The value of a merged block is in its top left cell; the others are empty.
