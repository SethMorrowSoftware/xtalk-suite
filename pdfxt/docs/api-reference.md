# pdfxt API reference

The 34 public handlers, from the doc blocks in `src/pdfxt.lcb` (the IDE dictionary reads the
same blocks; `tools/build-api-reference.py` writes this file from them, and its `--check` is a
gate). Read [getting-started.md](getting-started.md) first: it has how pages, characters and
coordinates are counted, the limits every call is held to, and what a failed call looks like.

## The library

### `pdfABIVersion`

`pdfABIVersion() returns Integer`

Returns the ABI number of the native library that is loaded.

Returns: The ABI number; this binding needs 1.

### `pdfLibraryVersion`

`pdfLibraryVersion() returns String`

Returns the versions of the native library and of the PDFium it was built for.

Returns: Text such as "pdfxt ABI 1; PDFium chromium/8165".

It throws if the library on disk has a different ABI from this binding, which means the two come from different releases. It does not load PDFium: `pdfIsLoaded` says whether that has happened.

```
put pdfLibraryVersion() into field "status"
```

### `pdfLastError`

`pdfLastError() returns String`

Returns why the last refused call was refused.

Returns: A short sentence, or empty if the last call that could be refused was not.

A call that cannot do what it was asked does nothing and returns 0 or empty; it never throws. This says what was wrong: a file that is not a PDF, a password that is needed, a page that is not there, a drawing that is too large, or the PDFium library missing from beside pdfxt.

### `pdfLoad`

`pdfLoad(in pFolder as String) returns Boolean`

Loads the PDFium library now, and says whether it is ready.

- pFolder: A folder that holds the PDFium library, or empty for the folder pdfxt itself is in.

Returns: True if PDFium is loaded and ready; false if not, and `pdfLastError` says where it was looked for.

You rarely need this: every call that needs PDFium loads it on first use from the folder pdfxt is in. Call it with empty to find out early whether PDFium is there (to tell the user, before they pick a file), or with a folder if you keep the PDFium library somewhere else. Once PDFium is loaded it stays loaded and pFolder is ignored.

```
if not pdfLoad(empty) then answer pdfLastError()
```

### `pdfIsLoaded`

`pdfIsLoaded() returns Boolean`

Says whether the PDFium library is loaded and running.

Returns: True once any call has loaded it; false before that and after `pdfShutdown`.

### `pdfShutdown`

`pdfShutdown() returns nothing`

Closes every document and shuts PDFium down.

Call it when your stack closes, since nothing else tells the library that you are done. It is safe to call twice, or when nothing was ever opened. Every document handle is dead afterwards. The next `pdfOpen` starts PDFium again.

```
on closeStack
pdfShutdown
end closeStack
```

## Opening and closing

### `pdfOpen`

`pdfOpen(in pPath as String, in pPassword as String) returns Integer`

Opens a PDF file.

- pPath: The path of a PDF file.
- pPassword: The document's password, or empty if it has none.

Returns: A document handle, or 0 if the file could not be opened (`pdfLastError` says why).

The file stays open, and is read as pages are asked for, until `pdfClose`: a large document opens at once and costs little memory. A file larger than 2 GB is refused. PDFium loads on the first call. It throws only if the native library has a different ABI from this binding.

```
put pdfOpen(specialFolderPath("documents") & "/manual.pdf", empty) into tDoc
if tDoc is 0 then answer pdfLastError()
```

### `pdfOpenData`

`pdfOpenData(in pData as Data, in pPassword as String) returns Integer`

Opens a PDF held in memory.

- pData: The bytes of a PDF file.
- pPassword: The document's password, or empty if it has none.

Returns: A document handle, or 0 if the bytes are not a PDF that can be opened (`pdfLastError` says why).

For a PDF that came from somewhere other than a file: a download, a database, a custom property. The library keeps its own copy of the bytes until `pdfClose`, so the variable you passed can be reused at once.

```
put pdfOpenData(url ("binfile:" & tPath), empty) into tDoc
```

### `pdfClose`

`pdfClose(in pDocument as Integer) returns nothing`

Closes a document and frees what it holds.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.

The handle is dead afterwards; using it again is harmless. Closing a handle that is not open does nothing.

### `pdfCloseAll`

`pdfCloseAll() returns Integer`

Closes every open document.

Returns: How many documents were open.

### `pdfOpenCount`

`pdfOpenCount() returns Integer`

Returns how many documents are open.

Returns: The count. At most 4095 can be open at once.

### `pdfIsOpen`

`pdfIsOpen(in pDocument as Integer) returns Boolean`

Says whether a number is the handle of an open document.

- pDocument: A number that may be a document handle.

Returns: True if it is; false for 0, for a closed handle, and for any other number.

## The document

### `pdfPageCount`

`pdfPageCount(in pDocument as Integer) returns Integer`

Returns how many pages a document has.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.

Returns: The number of pages, or 0 for a handle that is not open.

### `pdfFileVersion`

`pdfFileVersion(in pDocument as Integer) returns Integer`

Returns the PDF version a file says it is.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.

Returns: The version times ten: 14 for PDF 1.4, 17 for PDF 1.7. 0 if the file does not say.

### `pdfPermissions`

`pdfPermissions(in pDocument as Integer) returns Number`

Returns what a protected document allows.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.

Returns: The permission bits of the PDF specification as one number. 4294967295 means everything is allowed.

Bit 3 (value 4) is printing, bit 4 (8) changing the document, bit 5 (16) copying text, bit 6 (32) adding notes. Test one with the bitAnd operator. These are the document's wishes: this library does not enforce them, and reads text and draws pages either way.

```
put ((pdfPermissions(tDoc) bitAnd 16) is not 0) into tMayCopy
```

### `pdfMetadata`

`pdfMetadata(in pDocument as Integer, in pTag as String) returns String`

Returns one entry of a document's information.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pTag: Which entry: Title, Author, Subject, Keywords, Creator, Producer, CreationDate or ModDate.

Returns: The entry's text, or empty if the document has none.

Dates come as the file wrote them, usually like "D:20261120153000Z".

```
put pdfMetadata(tDoc, "Title") into field "title"
```

### `pdfPageLabel`

`pdfPageLabel(in pDocument as Integer, in pPage as Integer) returns String`

Returns the label a page is known by.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.

Returns: The label, such as "iv" or "A-3", or empty if the document gives the page none.

A book whose preface is numbered i, ii, iii has labels that differ from its page numbers. Show the label to people; pass the page number to this library.

### `pdfPageSize`

`pdfPageSize(in pDocument as Integer, in pPage as Integer) returns String`

Returns the size of a page.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.

Returns: The width and height in points as text, "612,792", or empty if there is no such page.

A point is 1/72 inch, so 612,792 is US Letter and 595,842 is A4. The size is of the page as it is displayed: a page the document turns on its side reports its turned size. This does not load the page, so it is quick to ask of every page of a long document.

```
put item 1 of pdfPageSize(tDoc, 1) * 2 into tWidth -- twice life size
```

### `pdfPageWidth`

`pdfPageWidth(in pDocument as Integer, in pPage as Integer) returns Number`

Returns the width of a page.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.

Returns: The width in points as displayed, or 0 if there is no such page.

### `pdfPageHeight`

`pdfPageHeight(in pDocument as Integer, in pPage as Integer) returns Number`

Returns the height of a page.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.

Returns: The height in points as displayed, or 0 if there is no such page.

### `pdfPageRotation`

`pdfPageRotation(in pDocument as Integer, in pPage as Integer) returns Integer`

Returns how far the document turns a page for display.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.

Returns: 0, 90, 180 or 270 degrees clockwise.

Every other call here already allows for it: sizes, drawings and rectangles are all of the page as displayed. This is for a viewer that wants to say so.

## Drawing pages

### `pdfRenderPage`

`pdfRenderPage(in pDocument as Integer, in pPage as Integer, in pWidth as Integer, in pHeight as Integer, in pFlags as Integer) returns Data`

Draws a whole page as the imageData of an image.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.
- pWidth: The width of the drawing in pixels, 1 to 16384.
- pHeight: The height of the drawing in pixels, 1 to 16384.
- pFlags: 0 for a plain drawing, or a sum of: 1 draw annotations and form fields, 2 text sharpened for an LCD screen, 8 gray, 2048 as for print, 4096 / 8192 / 16384 no smoothing of text / images / lines.

Returns: pWidth x pHeight x 4 bytes in the engine's imageData order, or empty if the page could not be drawn (`pdfLastError` says why).

The page is stretched to exactly pWidth by pHeight, on white paper, so keep the page's own proportions (`pdfPageSize`). Size the image first, then set its imageData. A drawing may hold at most 40 million pixels. For one step that needs no image of the right size, use `pdfRenderPageBMP`.

```
put pdfPageWidth(tDoc, 1) * 2 into tW
put pdfPageHeight(tDoc, 1) * 2 into tH
set the width of image "page" to tW
set the height of image "page" to tH
set the imageData of image "page" to pdfRenderPage(tDoc, 1, tW, tH, 0)
```

### `pdfRenderPageRegion`

`pdfRenderPageRegion(in pDocument as Integer, in pPage as Integer, in pZoomWidth as Integer, in pZoomHeight as Integer, in pLeft as Integer, in pTop as Integer, in pWidth as Integer, in pHeight as Integer, in pFlags as Integer) returns Data`

Draws part of a page, at any zoom, as the imageData of an image.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.
- pZoomWidth: The width in pixels the WHOLE page would have at this zoom, 1 to 1000000.
- pZoomHeight: The height in pixels the whole page would have at this zoom, 1 to 1000000.
- pLeft: The left edge of the part wanted, in pixels of the zoomed page.
- pTop: The top edge of the part wanted, in pixels of the zoomed page.
- pWidth: The width of the part wanted in pixels, 1 to 16384.
- pHeight: The height of the part wanted in pixels, 1 to 16384.
- pFlags: 0 for a plain drawing, or a sum of: 1 draw annotations and form fields, 2 text sharpened for an LCD screen, 8 gray, 2048 as for print, 4096 / 8192 / 16384 no smoothing of text / images / lines.

Returns: pWidth x pHeight x 4 bytes in the engine's imageData order, or empty if it could not be drawn.

What a viewer uses when zoomed in: say how large the whole page would be, and which window of it you can see, and only that window is drawn. Memory and time follow the window, not the zoom. A window that reaches past the page's edge is white there.

### `pdfRenderPageBMP`

`pdfRenderPageBMP(in pDocument as Integer, in pPage as Integer, in pWidth as Integer, in pHeight as Integer, in pFlags as Integer) returns Data`

Draws a whole page as a BMP picture file.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.
- pWidth: The width of the drawing in pixels, 1 to 16384.
- pHeight: The height of the drawing in pixels, 1 to 16384.
- pFlags: 0 for a plain drawing, or a sum of: 1 draw annotations and form fields, 2 text sharpened for an LCD screen, 8 gray, 2048 as for print, 4096 / 8192 / 16384 no smoothing of text / images / lines.

Returns: The bytes of a BMP file, or empty if the page could not be drawn (`pdfLastError` says why).

The simplest way to show a page: the bytes are a complete picture, so an image takes them as its text and sizes itself. They can also be written to a file as they are.

```
set the text of image "page" to pdfRenderPageBMP(tDoc, 1, 612, 792, 0)
```

## Text

### `pdfPageCharCount`

`pdfPageCharCount(in pDocument as Integer, in pPage as Integer) returns Integer`

Returns how many characters of text a page has.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.

Returns: The count, or 0.

Characters are counted as PDFium counts them, and the break between two lines counts as two. The numbers `pdfPageSearch` returns and `pdfPageTextRange` takes are positions in this count.

### `pdfPageText`

`pdfPageText(in pDocument as Integer, in pPage as Integer) returns String`

Returns all the text of a page.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.

Returns: The text in reading order, one line of the page to a line, or empty.

A scanned page is a picture and has no text. Text comes out in the order the document stores it, which for most documents is reading order.

```
put pdfPageText(tDoc, 1) into field "text"
```

### `pdfPageTextRange`

`pdfPageTextRange(in pDocument as Integer, in pPage as Integer, in pStart as Integer, in pCount as Integer) returns String`

Returns part of the text of a page.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.
- pStart: The position of the first character wanted; 1 is the first on the page.
- pCount: How many characters.

Returns: The characters, or empty. A range that runs past the end stops at the end.

### `pdfPageTextInRect`

`pdfPageTextInRect(in pDocument as Integer, in pPage as Integer, in pLeft as Number, in pTop as Number, in pRight as Number, in pBottom as Number) returns String`

Returns the text inside a rectangle of a page.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.
- pLeft: The left edge, in points from the left of the page.
- pTop: The top edge, in points from the top of the page.
- pRight: The right edge.
- pBottom: The bottom edge.

Returns: The text, or empty.

What a viewer copies when the user drags out a box. The rectangle is in points from the top left of the page as displayed: divide a pixel position by your zoom.

### `pdfPageCharBox`

`pdfPageCharBox(in pDocument as Integer, in pPage as Integer, in pIndex as Integer) returns String`

Returns where one character is on its page.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.
- pIndex: The position of the character; 1 is the first on the page.

Returns: Its rectangle as text, "left,top,right,bottom" in points from the top left of the page, or empty.

### `pdfPageCharAt`

`pdfPageCharAt(in pDocument as Integer, in pPage as Integer, in pX as Number, in pY as Number, in pTolerance as Number) returns Integer`

Returns which character is at a point of a page.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.
- pX: Points from the left of the page.
- pY: Points from the top of the page.
- pTolerance: How far from a character still counts, in points.

Returns: The character's position, or 0 if none is that near.

What a viewer asks when the user clicks on text.

### `pdfPageSearch`

`pdfPageSearch(in pDocument as Integer, in pPage as Integer, in pNeedle as String, in pFlags as Integer) returns String`

Finds every place some text occurs on a page.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.
- pNeedle: The text to find.
- pFlags: 0, or a sum of: 1 capitals must match, 2 whole words only.

Returns: One line for each match in reading order, "start,count": the position of its first character and how many characters it covers. Empty if there is none.

Pass a match to `pdfPageTextRects` to learn where to draw a highlight.

```
repeat for each line tMatch in pdfPageSearch(tDoc, tPage, "invoice", 0)
put pdfPageTextRects(tDoc, tPage, item 1 of tMatch, item 2 of tMatch) & return after tRects
end repeat
```

### `pdfPageTextRects`

`pdfPageTextRects(in pDocument as Integer, in pPage as Integer, in pStart as Integer, in pCount as Integer) returns String`

Returns the rectangles a run of text covers.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.
- pStart: The position of the first character; 1 is the first on the page.
- pCount: How many characters.

Returns: One line for each rectangle, "left,top,right,bottom" in points from the top left of the page. Empty if there is no such text.

A run within one line covers one rectangle; a run that wraps covers one for each line. Multiply by your zoom and draw them to highlight the text.

## Outline and links

### `pdfOutline`

`pdfOutline(in pDocument as Integer) returns String`

Returns a document's outline: its bookmarks.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.

Returns: One line for each entry in reading order: its level, a tab, the page it leads to, a tab, its title. Empty if the document has no outline.

Level 1 is a top entry, 2 an entry inside it, and so on. The page is 0 for an entry that leads nowhere in this document. At most 100000 entries, 64 levels deep, are returned.

```
set the itemDelimiter to tab
repeat for each line tEntry in pdfOutline(tDoc)
put item 3 of tEntry && "- page" && item 2 of tEntry & return after tList
end repeat
```

### `pdfPageLinks`

`pdfPageLinks(in pDocument as Integer, in pPage as Integer) returns String`

Returns the links on a page.

- pDocument: A document handle from `pdfOpen` or `pdfOpenData`.
- pPage: The page number; 1 is the first page.

Returns: One line for each link: its rectangle "left,top,right,bottom" in points from the top left of the page, a tab, the page it leads to, a tab, its web address. Empty if the page has none.

A link inside the document has a page and no address; a web link has an address and page 0. The address is what the document says, written by a stranger: show it to the user before opening it.
