# Getting started with pdfxt

pdfxt opens PDF files and gives a stack three things from them: pictures of their pages, their
text, and the ways to move around in them. This page is the handful of facts every call rests
on; [api-reference.md](api-reference.md) lists every handler.

## How things are counted

- **A document is a number.** `pdfOpen` returns a handle; 0 means it did not open. Keep the
  handle, pass it to every other call, and give it to `pdfClose` when you are done. A handle
  that was closed, or never existed, is safe to pass anywhere: getters return 0 or empty and
  actions do nothing.
- **A page is its number, and the first page is 1.** So is a character of a page.
- **Lengths are points.** A point is 1/72 inch: US Letter is 612 by 792. `pdfPageSize` returns
  "width,height" as the page is shown, so a page the file says to turn sideways comes back
  already turned.
- **Positions are measured from the top left of the page**, x to the right and y down, like a
  card. (PDF itself measures from the bottom left; pdfxt turns every rectangle and point over
  for you, rotation included.) To put a rectangle on your image, multiply by pixels per point.
- **A rectangle is "left,top,right,bottom".**

## Nothing throws; ask why

A call that cannot do what it was asked returns 0 or empty and does nothing. `pdfLastError()`
then says why in a short sentence: not a PDF, a password is needed, no such page, a drawing
that is too large, PDFium missing. The one exception is a pdfxt library on disk from a
different release than the binding, which throws on the first call.

```livecodescript
put pdfOpen(tPath, empty) into tDoc
if tDoc is 0 then
   if pdfLastError() contains "password" then
      ask password "This PDF is protected. Its password:"
      if it is not empty then put pdfOpen(tPath, it) into tDoc
   end if
end if
if tDoc is 0 then answer pdfLastError()
```

## Drawing a page

The short way: a BMP picture, which an image takes as its text and sizes itself to.

```livecodescript
on showPage pPage
   local tScale, tW, tH
   put 1.5 into tScale                                         -- pixels per point
   put round(pdfPageWidth(sDoc, pPage) * tScale) into tW
   put round(pdfPageHeight(sDoc, pPage) * tScale) into tH
   set the text of image "page" to pdfRenderPageBMP(sDoc, pPage, tW, tH, 0)
end showPage
```

The other way hands back raw pixels in the engine's `imageData` order, for an image you have
already sized, which is what you want when you draw often:

```livecodescript
set the width of image "page" to tW
set the height of image "page" to tH
set the imageData of image "page" to pdfRenderPage(sDoc, pPage, tW, tH, 0)
```

The page is stretched to exactly the width and height you give, so keep its proportions. For a
viewer zoomed far in, `pdfRenderPageRegion` draws only the window you can see: you say how
large the whole page would be at that zoom and which part of it you want.

The last argument is a sum of flags: 0 for a plain drawing, 1 to draw annotations and form
fields too, 8 for gray, 2048 as for print.

## Text, search and highlighting

```livecodescript
put pdfPageText(sDoc, 3) into field "text"

-- every place "invoice" appears on page 3: lines of "start,count"
repeat for each line tHit in pdfPageSearch(sDoc, 3, "invoice", 0)
   -- the rectangles that cover it, one per line, in points from the top left
   repeat for each line tRect in pdfPageTextRects(sDoc, 3, item 1 of tHit, item 2 of tHit)
      -- item 1 * tScale, item 2 * tScale, ... is where to draw the highlight on image "page"
   end repeat
end repeat
```

`pdfPageCharAt` answers "which character is under this point", and `pdfPageTextInRect` "what
text is inside this rectangle": the two halves of selecting text with the mouse. Search flags:
1 matches case, 2 whole words only.

A page that is a scan has no text: `pdfPageCharCount` is 0. pdfxt does no OCR.

## Finding your way

`pdfOutline` returns the bookmarks, one line each: level, tab, page, tab, title.
`pdfPageLinks` returns a page's links: rectangle, tab, page, tab, web address. A link inside
the document has a page; a web link has an address. **An address comes from the file, written
by whoever made it: show it before you open it.**

`pdfPageLabel` is the name a page goes by ("iv", "A-3"); show it to people, and keep passing
the page number to pdfxt.

## Limits every call is held to

| What | Limit |
|---|---|
| documents open at once | 4095 |
| a file | 2 GB |
| one side of a drawing | 16384 pixels |
| a whole drawing | 40 million pixels (160 MB of imageData) |
| the zoomed page of `pdfRenderPageRegion` | 1000000 pixels a side |
| one text result | 64 MB |
| the outline | 100000 entries, 64 levels deep |

Past a limit the call is refused with a reason; nothing is cut short silently except the
outline, which stops at its limits.

## What a PDF may ask, and what pdfxt does

`pdfPermissions` reports what a protected document allows (printing, copying, changing). They
are the document's wishes: pdfxt does not enforce them. It runs no JavaScript from a PDF, opens
no network connection, and never writes to the file.

## Shipping a stack

The standalone builder copies the extension's two libraries, `pdfxt` and `pdfium`, into the
app. PDFium needs macOS 13, Android 6.0 or glibc 2.16; on an older system `pdfLoad(empty)`
returns false and you can say so before the user picks a file:

```livecodescript
if not pdfLoad(empty) then answer "PDF support is not available here:" && pdfLastError()
```
