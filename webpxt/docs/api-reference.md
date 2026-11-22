# webpxt API reference

The 26 public handlers, from the doc blocks in `src/webpxt.lcb` (the IDE dictionary reads the
same blocks; `tools/build-api-reference.py` writes this file from them, and its `--check` is a
gate). Read [getting-started.md](getting-started.md) first: it has the conventions, the limits and
worked examples for pictures and animations.

## The library

### `wpABIVersion`

`wpABIVersion() returns Integer`

Returns the ABI number of the native library that is loaded.

Returns: The ABI number; this binding needs 1.

### `wpLibraryVersion`

`wpLibraryVersion() returns String`

Returns the versions of the native library and of libwebp inside it.

Returns: Text such as "webpxt ABI 1; libwebp 1.6.0".

A good first call. It throws if the library on disk has a different ABI from this binding, which means the two come from different releases.

```
put wpLibraryVersion() into field "status"
```

### `wpLastError`

`wpLastError() returns String`

Returns why the last refused call was refused.

Returns: A short sentence, or empty if the last call worked.

A call given a damaged file or a bad argument returns empty, 0 or false; it never throws. This says what was wrong, in plain words. Every call that reads or writes a picture sets it, and clears it when it works.

```
put wpDecode(tFile) into tPicture
if tPicture is empty then answer "That file could not be read:" && wpLastError()
```

## Reading a picture

### `wpInfo`

`wpInfo(in pData as Data) returns Array`

Reads the size and kind of a WebP file without decoding it.

- pData: The bytes of a WebP file.

Returns: An array with the keys "width", "height", "alpha" (true if the file has transparency), "animated" (true for an animation), "frames" (1 for a still picture), "loops" (how many times an animation plays; 0 means for ever) and "compression" ("lossy", "lossless", or "mixed" when the file does not say or its frames differ). Empty if the data is not a WebP file.

Only the start of the file is read, so this is quick on a file of any size. Use it to test whether data is WebP at all, to size an image object before decoding, or to choose between `wpDecode` and `wpAnimOpen`.

```
put wpInfo(url ("binfile:" & tPath)) into tInfo
if tInfo is empty then
answer "Not a WebP file:" && wpLastError()
else
put tInfo["width"] & " x " & tInfo["height"] into field "size"
end if
```

### `wpDecode`

`wpDecode(in pData as Data) returns Array`

Decodes a WebP file into a picture.

- pData: The bytes of a WebP file.

Returns: A picture: an array with the keys "width", "height", "imageData" (4 bytes a pixel, as an image's imageData), "alphaData" (1 byte a pixel, as an image's alphaData) and "translucent" (true if any pixel is not fully solid). Empty if the file could not be read.

Give the image object the picture's width and height BEFORE setting its imageData: the engine reads the bytes against the image's current size. An animated file gives its first frame; read the rest with `wpAnimOpen`.

```
put wpDecode(url ("binfile:" & tPath)) into tPicture
if tPicture is not empty then
lock screen
set the width of image "photo" to tPicture["width"]
set the height of image "photo" to tPicture["height"]
set the imageData of image "photo" to tPicture["imageData"]
set the alphaData of image "photo" to tPicture["alphaData"]
unlock screen
end if
```

### `wpDecodeScaled`

`wpDecodeScaled(in pData as Data, in pWidth as Integer, in pHeight as Integer) returns Array`

Decodes a still WebP file straight to a given size.

- pData: The bytes of a WebP file.
- pWidth: The width wanted, in pixels, or 0 to work it out from pHeight and the picture's shape.
- pHeight: The height wanted, in pixels, or 0 to work it out from pWidth and the picture's shape.

Returns: A picture of that size, as `wpDecode` returns. Empty if the file could not be read or the size was refused.

The picture is scaled while it is decoded, which is faster than decoding and then resizing and never holds the full-size picture in memory. Give both sizes to stretch the picture to exactly that shape, or one size and 0 to keep its proportions. An animation is refused: open it with `wpAnimOpen`.

```
-- a thumbnail 160 pixels wide, whatever the photo's shape
put wpDecodeScaled(url ("binfile:" & tPath), 160, 0) into tThumb
```

## Writing a picture

### `wpEncode`

`wpEncode(in pImageData as Data, in pAlphaData as Data, in pWidth as Integer, in pHeight as Integer, in pQuality as Number) returns Data`

Writes a picture as a lossy WebP file.

- pImageData: The picture's colour, as an image's imageData: 4 bytes a pixel.
- pAlphaData: The picture's transparency, as an image's alphaData: 1 byte a pixel. Pass empty for a picture with no transparency.
- pWidth: The picture's width in pixels.
- pHeight: The picture's height in pixels.
- pQuality: From 0 (smallest file) to 100 (best picture). 75 to 85 suits photographs.

Returns: The bytes of a WebP file, or empty if the picture was refused.

Lossy WebP is for photographs and other pictures where a small file matters more than keeping every pixel exact: it is typically a quarter to a third smaller than a JPEG that looks the same, and unlike JPEG it keeps transparency. For screenshots, drawings and icons use `wpEncodeLossless`.

```
put wpEncode(the imageData of image "photo", the alphaData of image "photo", \
the width of image "photo", the height of image "photo", 80) into tFile
if tFile is empty then
answer wpLastError()
else
put tFile into url ("binfile:" & tPath)
end if
```

### `wpEncodeLossless`

`wpEncodeLossless(in pImageData as Data, in pAlphaData as Data, in pWidth as Integer, in pHeight as Integer) returns Data`

Writes a picture as a lossless WebP file.

- pImageData: The picture's colour, as an image's imageData: 4 bytes a pixel.
- pAlphaData: The picture's transparency, as an image's alphaData: 1 byte a pixel. Pass empty for a picture with no transparency.
- pWidth: The picture's width in pixels.
- pHeight: The picture's height in pixels.

Returns: The bytes of a WebP file, or empty if the picture was refused.

Every pixel comes back exactly as it went in, transparency included, as with PNG; the file is usually a quarter smaller than the PNG. Right for screenshots, drawings, icons and anything that will be edited again.

```
put wpEncodeLossless(the imageData of image "icon", the alphaData of image "icon", \
the width of image "icon", the height of image "icon") into url ("binfile:" & tPath)
```

### `wpEncodeAdvanced`

`wpEncodeAdvanced(in pImageData as Data, in pAlphaData as Data, in pWidth as Integer, in pHeight as Integer, in pQuality as Number, in pLossless as Boolean, in pEffort as Integer) returns Data`

Writes a picture as a WebP file, with every setting given.

- pImageData: The picture's colour, as an image's imageData: 4 bytes a pixel.
- pAlphaData: The picture's transparency, as an image's alphaData: 1 byte a pixel. Pass empty for a picture with no transparency.
- pWidth: The picture's width in pixels.
- pHeight: The picture's height in pixels.
- pQuality: From 0 to 100. For a lossy file, the picture's quality. For a lossless file the picture is always exact, and a higher number spends more time to make the file smaller.
- pLossless: True for a lossless file, false for a lossy one.
- pEffort: A whole number from 0 (fastest) to 6 (smallest file). `wpEncode` and `wpEncodeLossless` use 4.

Returns: The bytes of a WebP file, or empty if the picture was refused.

`wpEncode` and `wpEncodeLossless` are this call with the usual settings. A low effort is for when a picture must be written quickly, such as each frame of a capture; a high one for a file made once and downloaded many times.

```
-- the smallest lossless file, however long it takes
put wpEncodeAdvanced(tPixels, tAlpha, tWidth, tHeight, 100, true, 6) into tFile
```

## Reading an animation

### `wpAnimOpen`

`wpAnimOpen(in pData as Data) returns Integer`

Opens a WebP file for reading one frame at a time.

- pData: The bytes of a WebP file, animated or still.

Returns: A handle for the other wpAnim calls, or 0 if the file could not be read.

The file's bytes are copied, so the variable they came from can be reused. A still picture opens as an animation of one frame. Close the handle with `wpAnimClose` when the animation is no longer playing: each open animation holds its file and one full frame in memory, and at most 64 can be open at once. A file whose frames add up to more than 2147483647 milliseconds (about 24.8 days) is refused, because libwebp cannot time it; `wpDecode` still reads its first frame.

```
put wpAnimOpen(url ("binfile:" & tPath)) into sAnim
if sAnim is 0 then answer wpLastError()
```

### `wpAnimClose`

`wpAnimClose(in pAnim as Integer) returns nothing`

Closes an animation opened with wpAnimOpen and frees its memory.

- pAnim: The handle `wpAnimOpen` returned.

A handle that is already closed, or 0, does nothing.

### `wpAnimIsValid`

`wpAnimIsValid(in pAnim as Integer) returns Boolean`

Reports whether a handle is an open animation.

- pAnim: A handle `wpAnimOpen` returned.

Returns: True while the animation is open; false once it is closed, and for 0 or any number that was never a handle.

### `wpAnimWidth`

`wpAnimWidth(in pAnim as Integer) returns Integer`

Returns the width of an open animation, in pixels.

- pAnim: The handle `wpAnimOpen` returned.

Returns: The width of every frame; 0 for a closed handle.

### `wpAnimHeight`

`wpAnimHeight(in pAnim as Integer) returns Integer`

Returns the height of an open animation, in pixels.

- pAnim: The handle `wpAnimOpen` returned.

Returns: The height of every frame; 0 for a closed handle.

### `wpAnimFrameCount`

`wpAnimFrameCount(in pAnim as Integer) returns Integer`

Returns how many frames an open animation has.

- pAnim: The handle `wpAnimOpen` returned.

Returns: The number of frames; 0 for a closed handle.

### `wpAnimLoopCount`

`wpAnimLoopCount(in pAnim as Integer) returns Integer`

Returns how many times an animation asks to be played.

- pAnim: The handle `wpAnimOpen` returned.

Returns: The number of times; 0 means for ever. Also 0 for a closed handle.

The file only states a wish. Playing it that many times, with `wpAnimRewind` between, is up to the stack.

### `wpAnimNextFrame`

`wpAnimNextFrame(in pAnim as Integer) returns Array`

Decodes the next frame of an open animation.

- pAnim: The handle `wpAnimOpen` returned.

Returns: A picture, as `wpDecode` returns, with two more keys: "index" (the frame's number, from 1) and "duration" (how long to show it, in milliseconds). Empty after the last frame, or if the frame is damaged.

Every frame is the whole picture, already combined with the frames before it, so it is simply shown. After the last frame this returns empty and `wpLastError` is empty too; a damaged frame returns empty with an explanation.

```
on showNextFrame
local tFrame
put wpAnimNextFrame(sAnim) into tFrame
if tFrame is empty then
wpAnimRewind sAnim
put wpAnimNextFrame(sAnim) into tFrame
end if
if tFrame is empty then exit showNextFrame
set the imageData of image "anim" to tFrame["imageData"]
set the alphaData of image "anim" to tFrame["alphaData"]
send "showNextFrame" to me in tFrame["duration"] milliseconds
end showNextFrame
```

### `wpAnimRewind`

`wpAnimRewind(in pAnim as Integer) returns nothing`

Starts an open animation again from its first frame.

- pAnim: The handle `wpAnimOpen` returned.

The next `wpAnimNextFrame` returns frame 1. A closed handle does nothing.

### `wpAnimOpenCount`

`wpAnimOpenCount() returns Integer`

Returns how many animations are open.

Returns: The number of handles from `wpAnimOpen` not yet closed.

A stack that should have closed everything can check that this is 0.

## Writing an animation

### `wpAnimEncoderCreate`

`wpAnimEncoderCreate(in pWidth as Integer, in pHeight as Integer, in pLoops as Integer, in pQuality as Number, in pLossless as Boolean) returns Integer`

Starts writing an animated WebP file.

- pWidth: The width of every frame, in pixels.
- pHeight: The height of every frame, in pixels.
- pLoops: How many times the animation plays; 0 for ever.
- pQuality: From 0 to 100, as for `wpEncodeAdvanced`.
- pLossless: True for lossless frames, false for lossy ones.

Returns: A handle for the other wpAnimEncoder calls, or 0 if a setting was refused.

Add frames with `wpAnimEncoderAddFrame`, then `wpAnimEncoderFinish` returns the file. A writer that will not be finished is dropped with `wpAnimEncoderDiscard`. At most 64 can be open at once.

```
put wpAnimEncoderCreate(320, 240, 0, 80, false) into tWriter
repeat with i = 1 to 10
-- draw frame i into image "canvas", then:
get wpAnimEncoderAddFrame(tWriter, the imageData of image "canvas", empty, 100)
end repeat
put wpAnimEncoderFinish(tWriter) into url ("binfile:" & tPath)
```

### `wpAnimEncoderAddFrame`

`wpAnimEncoderAddFrame(in pWriter as Integer, in pImageData as Data, in pAlphaData as Data, in pDuration as Integer) returns Boolean`

Adds one frame to an animation being written.

- pWriter: The handle `wpAnimEncoderCreate` returned.
- pImageData: The frame's colour, as an image's imageData: 4 bytes a pixel.
- pAlphaData: The frame's transparency, as an image's alphaData: 1 byte a pixel. Pass empty for a frame with no transparency.
- pDuration: How long the frame shows, in milliseconds, from 1 to 600000.

Returns: True if the frame was added; false if it was refused.

The frame must be the animation's size exactly. Frames play in the order they are added. An animation holds at most 10000 frames and lasts at most 2147483647 milliseconds in all (about 24.8 days): a frame that would end it later is refused, and the frames before it are kept.

### `wpAnimEncoderIsValid`

`wpAnimEncoderIsValid(in pWriter as Integer) returns Boolean`

Reports whether a handle is an animation being written.

- pWriter: A handle `wpAnimEncoderCreate` returned.

Returns: True until the writer is finished or discarded; false after, and for 0 or any number that was never a handle.

### `wpAnimEncoderFrameCount`

`wpAnimEncoderFrameCount(in pWriter as Integer) returns Integer`

Returns how many frames an animation being written holds.

- pWriter: The handle `wpAnimEncoderCreate` returned.

Returns: The number of frames added so far; 0 for a finished handle.

### `wpAnimEncoderFinish`

`wpAnimEncoderFinish(in pWriter as Integer) returns Data`

Finishes an animation and returns it as a WebP file.

- pWriter: The handle `wpAnimEncoderCreate` returned.

Returns: The bytes of an animated WebP file, or empty if it could not be written (an animation with no frames, for one).

The handle is closed whatever the outcome: after this call it is no longer valid.

### `wpAnimEncoderDiscard`

`wpAnimEncoderDiscard(in pWriter as Integer) returns nothing`

Drops an animation being written, without writing it.

- pWriter: The handle `wpAnimEncoderCreate` returned.

Frees the frames added so far. A handle that is already finished or discarded, or 0, does nothing.

### `wpAnimEncoderOpenCount`

`wpAnimEncoderOpenCount() returns Integer`

Returns how many animations are being written.

Returns: The number of handles from `wpAnimEncoderCreate` not yet finished or discarded.
