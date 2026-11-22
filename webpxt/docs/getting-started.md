# Getting started with webpxt

webpxt reads and writes WebP images. This page is what to know before the
[API reference](api-reference.md).

## The conventions

- **A file is data.** A `.webp` file is the bytes `url ("binfile:" & tPath)` reads, or what
  came back from a web request. Nothing here opens a file by its path.
- **A picture is an array.** `wpDecode` returns an array with `width`, `height`, `imageData`
  and `alphaData`: the last two are exactly what an image object's properties of those names
  hold, so you set them and you are done. It also has `translucent`, true when any pixel is
  not fully opaque.
- **Every parameter is typed.** A number parameter must be given a number: empty is an engine
  error at the call, before webpxt sees it. Pass 0, not empty. A picture's `alphaData` may be
  empty, which means fully opaque.
- **Nothing throws.** A file that is damaged, or not WebP at all, is an ordinary event: the
  call returns empty (or 0, or false) and `wpLastError()` says why. The one exception is a
  native library from a different release than the binding: the first call throws and names
  the ABI it needs.

## Showing a WebP file

```livecodescript
on showWebP pPath
   local tPicture
   put wpDecode(url ("binfile:" & pPath)) into tPicture
   if tPicture is empty then
      answer "Could not read that picture:" && wpLastError()
      exit showWebP
   end if
   lock screen
   set the width of image "photo" to tPicture["width"]
   set the height of image "photo" to tPicture["height"]
   set the imageData of image "photo" to tPicture["imageData"]
   set the alphaData of image "photo" to tPicture["alphaData"]
   unlock screen
end showWebP
```

Set the image's width and height BEFORE its imageData: the engine reads the data as rows of
the image's current width.

For a list of thumbnails, do not decode every file at full size. `wpInfo(tFile)` reads the
size from the first few bytes, and `wpDecodeScaled(tFile, 160, 0)` decodes straight to 160
pixels wide (0 keeps the shape).

## Saving one

```livecodescript
put wpEncode(the imageData of image "photo", the alphaData of image "photo", \
      the width of image "photo", the height of image "photo", 80) into url ("binfile:" & tPath)
```

- `wpEncode(..., quality)` is lossy, like JPEG: 75 to 85 suits photographs, and the file is
  usually a quarter to a third smaller than a JPEG that looks the same.
- `wpEncodeLossless(...)` keeps every pixel, like PNG, and is usually smaller than the PNG.
  Use it for screenshots, drawings and anything with text.
- `wpEncodeAdvanced(..., quality, lossless, effort)` adds the effort, 0 (fastest) to 6
  (smallest file); the other two use 4.

Transparency is kept by all three. Pass `empty` for the alphaData of a picture with none.

## Animations

Reading: open, then ask for frames until one comes back empty.

```livecodescript
local sAnim

on playWebP pFile
   put wpAnimOpen(pFile) into sAnim
   if sAnim is 0 then exit playWebP
   nextWebPFrame
end playWebP

on nextWebPFrame
   local tFrame
   put wpAnimNextFrame(sAnim) into tFrame
   if tFrame is empty then
      wpAnimRewind sAnim                       -- play it again
      put wpAnimNextFrame(sAnim) into tFrame
   end if
   set the imageData of image "photo" to tFrame["imageData"]
   set the alphaData of image "photo" to tFrame["alphaData"]
   send "nextWebPFrame" to me in tFrame["duration"] milliseconds
end nextWebPFrame

on closeCard
   wpAnimClose sAnim
end closeCard
```

Each frame is the whole picture as it should be shown (the file's partial frames are already
composed), with `index` and `duration` in milliseconds beside the usual keys. An animation
stays open, holding its file, until `wpAnimClose`: close it when the card closes.
`wpAnimOpenCount()` says how many are open, which is how to find a leak.

Writing: create a writer, add pictures of that size, finish.

```livecodescript
put wpAnimEncoderCreate(320, 240, 0, 80, false) into tWriter      -- width, height, loops (0 = forever), quality, lossless
repeat for each element tPicture in tPictures
   get wpAnimEncoderAddFrame(tWriter, tPicture["imageData"], tPicture["alphaData"], 100)   -- shown for 100 ms
end repeat
put wpAnimEncoderFinish(tWriter) into url ("binfile:" & tPath)
```

`wpAnimEncoderFinish` closes the writer. To give up on one, `wpAnimEncoderDiscard`.

## The limits

| What | Limit |
|---|---|
| One picture | 16383 pixels a side (the format's own limit), and 67,108,864 pixels in all (8192 x 8192) |
| Animations open at once | 64, and 64 being written |
| Frames in a written animation | 10,000 |
| One frame's duration | 1 to 600,000 ms |
| A whole animation, written or read | 2,147,483,647 ms in all (about 24.8 days) |
| Quality | 0 to 100 |
| Effort | 0 to 6 |

A picture of 8192 x 8192 is 256 MB of imageData, so the limit that matters first is usually
memory. Anything over a limit is refused with a sentence in `wpLastError()`; nothing is
clipped quietly.
