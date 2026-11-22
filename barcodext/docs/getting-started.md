# Getting started with barcodext

barcodext reads barcodes and QR codes out of pictures, and makes them. This page is what to
know before the [API reference](api-reference.md).

## The conventions

- **A picture is an image's pixels.** A read takes `the imageData of image ...` with the
  image's width and height. A created barcode comes back as an array with `width`, `height`
  and `imageData`, ready to set on an image object.
- **A kind of barcode is named in text**: "QR Code", "EAN-13", "Code 128", "Data Matrix".
  The spelling is forgiving ("qrcode" and "ean13" work); `bcFormats()` lists every kind that
  can be read and `bcWritableFormats()` every kind that can be made. Several kinds are
  written with commas between: "EAN-13,UPC-A".
- **Every parameter is typed.** A number parameter must be given a number: empty is an engine
  error at the call, before barcodext sees it. Pass 0, not empty.
- **Nothing throws.** A picture with no barcode in it, a kind that does not exist, content a
  kind cannot hold: each is an ordinary event. The call returns empty and `bcLastError()`
  says why. A read that simply finds nothing returns an empty list and leaves
  `bcLastError()` empty too, which is how to tell "none found" from "refused". The one
  exception is a native library from a different release than the binding: the first call
  throws and names the ABI it needs.

## Reading

The shortest form returns the text of the first barcode found:

```livecodescript
put bcReadText(the imageData of image "photo", the width of image "photo", the height of image "photo") into field "scanned"
```

`bcRead` returns every barcode, each as an array:

```livecodescript
put bcRead(the imageData of image "photo", the width of image "photo", the height of image "photo") into tFound
repeat for each element tBarcode in tFound
   put tBarcode["format"] && tBarcode["text"] && "at" && tBarcode["position"] & return after field "log"
end repeat
```

| Key | What it holds |
|---|---|
| `text` | what the barcode says |
| `format` | its kind, such as "QR Code" |
| `bytes` | the content as binary data, nothing decoded |
| `position` | its four corners, from the top left clockwise: `x1,y1,x2,y2,x3,y3,x4,y4` |
| `orientation` | how far it is turned, in degrees |
| `contentType` | "Text", "Binary", "Mixed", "GS1", "ISO15434" or "UnknownECI" |
| `valid`, `error` | true and empty for a good barcode |
| `mirrored`, `inverted` | read as a mirror image, or light on dark |
| `ecLevel`, `version` | a 2D code's error-correction level and size |
| `symbologyId`, `extra` | the standard's identifier, and every further fact as JSON |

**Name the kinds when you know them.** `bcReadFormats(..., "QR Code")` is faster than looking
for everything, and it cannot mistake a picture's texture for a kind you never use. It also
settles two cases a read of every kind cannot: a UPC-A is reported as an EAN-13 with a
leading 0 unless you ask for "UPC-A", and a Telepen Numeric as Telepen Alpha unless you ask
for "Telepen Numeric".

`bcReadAdvanced` adds read options, words with commas between:

| Option | Effect |
|---|---|
| `fast` | spend less time; a blurred or tiny barcode may be missed |
| `max=N` | stop after N barcodes |
| `pure` | the picture is one clean, upright, computer-made barcode |
| `noRotate`, `noInvert`, `noDownscale` | skip turned, light-on-dark, or scaled-down attempts |
| `errors` | also return barcodes that failed their check, with `valid` false |
| `checksum` | check the optional check digit of Code 39 and ITF |
| `addon=ignore`, `read`, `require` | the 2 or 5 digit add-on beside an EAN or UPC |
| `text=hri`, `plain`, `eci`, `escaped`, `hex` | how `text` is written |
| `binarizer=local`, `global`, `fixed`, `bool` | how grey becomes black and white |
| `lines=N` | scan lines a linear barcode must be seen on |
| `gray` | the data is one byte a pixel, not imageData |

For a live camera, read each frame with `"fast,max=1"` and the kinds you expect.

## Making

```livecodescript
put bcCreate("https://openxtalk.org/", "QR Code", 6) into tPicture
set the width of image "code" to tPicture["width"]
set the height of image "code" to tPicture["height"]
set the imageData of image "code" to tPicture["imageData"]
```

The last parameter is the scale: how many pixels the smallest bar or square is. The
picture's size follows from the content and the scale, so set the image's width and height
from the array BEFORE its imageData. The picture is black on white with the empty margin the
kind needs.

Each kind has rules about its content, and content that breaks them is refused with the
reason in `bcLastError()`:

| Kind | Content |
|---|---|
| QR Code, Data Matrix, Aztec, PDF417 | any text; binary data with `bcCreateFromData` |
| EAN-13 | up to 12 digits (the check digit is added), or 13 with a correct one |
| EAN-8, UPC-A, UPC-E | up to 7, 11 and 7 digits, or one more with a correct check digit |
| Code 128 | text in ASCII or Latin-1 |
| Code 39 | capitals, digits and `- . $ / + %` and space (small letters become capitals) |
| ITF | digits (an odd count gets a leading 0) |
| Codabar | digits and `- $ : / . +`, with a start and a stop letter A to D |

A number shorter than its kind's length is filled with zeros on the left, as the standards
say. (Observed with zxing-cpp 3.1.1 on 2026-11-20.)

`bcCreateAdvanced` adds create options (`ecLevel=H` for a QR Code that survives a logo over
its middle, `version=N`, `gs1`, `forceSquare`, `columns=N`, `rows=N`, `eci=UTF-8`,
`dataMask=N`, `readerInit`), whether to leave the margin, and whether to print the content
under a linear barcode. `bcCreateSVG` returns the barcode as SVG text, which prints sharp at
any size. `bcCreateMatrix` returns rows of 1 and 0 for a stack that draws its own squares.

## The limits

| What | Limit |
|---|---|
| A picture to read | 32767 pixels a side, and 67,108,864 pixels in all (8192 x 8192) |
| Barcodes returned by one read | 255 |
| Scale of a created barcode | 1 to 64 pixels |
| A created picture | 16,777,216 pixels (4096 x 4096) |
| Content of one created barcode | 8192 bytes (each kind's own limit is lower) |
| A kinds or options text | 1024 characters |

Anything over a limit is refused with a sentence in `bcLastError()`; nothing is clipped
quietly.

## Good pictures

A reader finds a barcode when it can tell bars from background. What helps, in order: the
barcode filling a fair part of the picture (the smallest bar at least two pixels wide), even
light, and a sharp focus. A large photo of a small barcode reads better cropped than scaled
down by hand: the reader already tries smaller copies of the picture itself.
