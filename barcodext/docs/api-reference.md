# barcodext API reference

The 14 public handlers, from the doc blocks in `src/barcodext.lcb` (the IDE dictionary reads the
same blocks; `tools/build-api-reference.py` writes this file from them, and its `--check` is a
gate). Read [getting-started.md](getting-started.md) first: it has the conventions, the limits and
worked examples for reading and for making barcodes.

## The library

### `bcABIVersion`

`bcABIVersion() returns Integer`

Returns the ABI number of the native library that is loaded.

Returns: The ABI number; this binding needs 1.

### `bcLibraryVersion`

`bcLibraryVersion() returns String`

Returns the versions of the native library and of zxing-cpp inside it.

Returns: Text such as "barcodext ABI 1; zxing-cpp 3.1.1".

A good first call. It throws if the library on disk has a different ABI from this binding, which means the two come from different releases.

```
put bcLibraryVersion() into field "status"
```

### `bcLastError`

`bcLastError() returns String`

Returns why the last call was refused.

Returns: A sentence, or empty when the last call worked.

No handler of this library throws on a bad picture or a bad argument. A refused call returns empty and leaves its reason here. A read that finds no barcode is not a refusal: its list is empty and so is this.

```
put bcCreate("hello", "EAN-13", 3) into tPicture
if tPicture is empty then answer bcLastError()
```

### `bcFormats`

`bcFormats() returns String`

Returns the kinds of barcode this library can read.

Returns: The names, with commas between: "Code 39,Code 128,EAN-13,QR Code,..."

A name from this list is what `bcRead` reports as a barcode's "format" and what `bcReadFormats` takes to narrow a read. The list also holds family names ("EAN/UPC", "DataBar") that stand for all their members.

```
put bcFormats() into tKinds
replace comma with return in tKinds
put tKinds into field "kinds"
```

### `bcWritableFormats`

`bcWritableFormats() returns String`

Returns the kinds of barcode this library can create.

Returns: The names, with commas between.

A name from this list is what `bcCreate` takes as the kind to make.

```
if "Data Matrix" is among the items of bcWritableFormats() then
put bcCreate("part 4711", "Data Matrix", 6) into tPicture
end if
```

## Reading

### `bcRead`

`bcRead(in pImageData as Data, in pWidth as Integer, in pHeight as Integer) returns List`

Finds every barcode in a picture.

- pImageData: The picture's pixels: the imageData of an image object.
- pWidth: The picture's width in pixels.
- pHeight: The picture's height in pixels.

Returns: A list with one array for each barcode found. It is empty when there is none, and when the call was refused (then `bcLastError` says why).

Looks for every kind of barcode, upright or turned, dark on light or light on dark. Each barcode found is an array with these keys:

```
put bcRead(the imageData of image "photo", the width of image "photo", the height of image "photo") into tFound
repeat for each element tBarcode in tFound
put tBarcode["format"] & ": " & tBarcode["text"] & return after field "log"
end repeat
```

### `bcReadFormats`

`bcReadFormats(in pImageData as Data, in pWidth as Integer, in pHeight as Integer, in pFormats as String) returns List`

Finds the barcodes of the kinds you name in a picture.

- pImageData: The picture's pixels: the imageData of an image object.
- pWidth: The picture's width in pixels.
- pHeight: The picture's height in pixels.
- pFormats: The kinds to look for, with commas between, such as "QR Code" or "EAN-13,UPC-A". Empty looks for every kind.

Returns: A list with one array for each barcode found, as `bcRead` returns.

Naming the kinds makes a read faster and stops a picture's texture being taken for a kind you never use. The names are those of `bcFormats`; "qrcode" and "ean13" spell the same kinds. A name the library does not know refuses the call.

```
put bcReadFormats(the imageData of image "ticket", 640, 480, "QR Code,Aztec") into tFound
if the number of elements in tFound is 0 then answer "No ticket code found."
```

### `bcReadAdvanced`

`bcReadAdvanced(in pImageData as Data, in pWidth as Integer, in pHeight as Integer, in pFormats as String, in pOptions as String) returns List`

Finds barcodes in a picture, with every choice the reader has.

- pImageData: The picture's pixels: the imageData of an image object, or with the option "gray" one byte for each pixel.
- pWidth: The picture's width in pixels.
- pHeight: The picture's height in pixels.
- pFormats: The kinds to look for, with commas between. Empty looks for every kind.
- pOptions: Read options, with commas between. Empty uses the thorough defaults.

Returns: A list with one array for each barcode found, as `bcRead` returns.

The options are words with commas between, in any case:

```
-- every frame of a camera: fast, one barcode is enough
put bcReadAdvanced(tPixels, tWidth, tHeight, "QR Code", "fast,max=1") into tFound
```

### `bcReadText`

`bcReadText(in pImageData as Data, in pWidth as Integer, in pHeight as Integer) returns String`

Returns the text of the first barcode found in a picture.

- pImageData: The picture's pixels: the imageData of an image object.
- pWidth: The picture's width in pixels.
- pHeight: The picture's height in pixels.

Returns: The barcode's text, or empty when no barcode was found.

The shortest way to scan one barcode. It looks for every kind and returns only the text of one. Use `bcRead` to learn the kind, to get several barcodes, or to get binary content.

```
put bcReadText(the imageData of image "photo", the width of image "photo", the height of image "photo") into field "scanned"
```

## Creating

### `bcCreate`

`bcCreate(in pText as String, in pFormat as String, in pScale as Integer) returns Array`

Makes a barcode as a picture.

- pText: What the barcode should say.
- pFormat: The kind to make, such as "QR Code", "EAN-13" or "Code 128".
- pScale: The size of the smallest bar or square in pixels, from 1 to 64.

Returns: An array with the keys "width", "height" and "imageData", or an empty array when the call was refused (then `bcLastError` says why).

The picture is black on white with the empty margin the kind needs to be read (its quiet zone). Its size follows from the content and pScale; set the image object to that size before setting its imageData.

```
put bcCreate("https://openxtalk.org/", "QR Code", 6) into tPicture
create image "code"
set the width of image "code" to tPicture["width"]
set the height of image "code" to tPicture["height"]
set the imageData of image "code" to tPicture["imageData"]
```

### `bcCreateAdvanced`

`bcCreateAdvanced(in pText as String, in pFormat as String, in pOptions as String, in pScale as Integer, in pQuietZone as Boolean, in pShowText as Boolean) returns Array`

Makes a barcode as a picture, with every choice the writer has.

- pText: What the barcode should say.
- pFormat: The kind to make, such as "QR Code", "EAN-13" or "Code 128".
- pOptions: Create options, with commas between. Empty uses the defaults.
- pScale: The size of the smallest bar or square in pixels, from 1 to 64.
- pQuietZone: True to leave the empty margin the kind needs around it.
- pShowText: True to print the content under a linear barcode.

Returns: An array with the keys "width", "height" and "imageData", or an empty array when the call was refused.

The create options are words with commas between:

```
-- a product barcode with its digits printed under it
put bcCreateAdvanced("5901234123457", "EAN-13", "", 3, true, true) into tPicture
```

### `bcCreateFromData`

`bcCreateFromData(in pData as Data, in pFormat as String, in pOptions as String, in pScale as Integer) returns Array`

Makes a barcode that holds binary data, as a picture.

- pData: The bytes the barcode should hold.
- pFormat: The kind to make. Only some kinds hold binary data: QR Code, Data Matrix, Aztec and PDF417 do.
- pOptions: Create options, with commas between, as `bcCreateAdvanced` takes. Empty uses the defaults.
- pScale: The size of the smallest bar or square in pixels, from 1 to 64.

Returns: An array with the keys "width", "height" and "imageData", or an empty array when the call was refused.

The bytes are stored as they are, with no character set applied. Read them back from the "bytes" key of what `bcRead` returns.

```
put bcCreateFromData(tKeyBytes, "QR Code", "", 6) into tPicture
```

### `bcCreateSVG`

`bcCreateSVG(in pText as String, in pFormat as String, in pOptions as String, in pShowText as Boolean) returns String`

Makes a barcode as SVG text.

- pText: What the barcode should say.
- pFormat: The kind to make, such as "QR Code" or "EAN-13".
- pOptions: Create options, with commas between, as `bcCreateAdvanced` takes. Empty uses the defaults.
- pShowText: True to print the content under a linear barcode.

Returns: An SVG document as text, or empty when the call was refused.

SVG is a drawing, not pixels, so it prints sharp at any size. Use it for labels and documents; use `bcCreate` for a picture to show in a stack.

```
put bcCreateSVG("5901234123457", "EAN-13", "", true) into url ("file:" & tFolder & "/label.svg")
```

### `bcCreateMatrix`

`bcCreateMatrix(in pText as String, in pFormat as String, in pOptions as String) returns String`

Makes a barcode as rows of 1 and 0, for a stack that draws its own.

- pText: What the barcode should say.
- pFormat: The kind to make, such as "QR Code".
- pOptions: Create options, with commas between, as `bcCreateAdvanced` takes. Empty uses the defaults.

Returns: Text with one line for each row of the barcode, "1" for a dark square and "0" for a light one, or empty when the call was refused.

There is no margin around the rows: leave the kind's quiet zone yourself when you draw them (four squares for a QR Code). A linear barcode comes back as many identical rows.

```
put bcCreateMatrix("hello", "QR Code", "") into tRows
put the number of lines in tRows into tSize -- 21 for the smallest QR Code
```
