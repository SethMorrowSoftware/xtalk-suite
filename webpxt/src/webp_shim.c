/*
 * webp_shim.c
 * ----------------------------------------------------------------------------
 * The C shim of webpxt: libwebp (Google's WebP codec) behind a flat C ABI that
 * the xTalk Builder (LCB) foreign function interface can call, so OpenXTalk
 * and LiveCode-compatible engines can read and write WebP images, still and
 * animated. box3dxt/src/box3d_shim.c is this file's ancestor in the suite and
 * its conventions are kept:
 *
 *   - PIXELS CROSS IN THE ENGINE'S OWN LAYOUT. An image's `imageData` is four
 *     bytes a pixel, rows top to bottom: one unused byte, then red, green,
 *     blue. Its `alphaData` is one byte a pixel, 0 clear to 255 solid. A
 *     decode fills exactly those two buffers, and an encode reads them, so a
 *     script moves a picture with `set the imageData of image ...` and never
 *     reorders a byte. Colour is NOT premultiplied by alpha, on either side.
 *   - A RESULT IS HELD HERE AND COPIED OUT. A decode leaves its picture in one
 *     static slot (width, height, the two buffers); an encode leaves its file
 *     in another. The binding reads the sizes, copies the bytes into engine
 *     values and releases the slot. The next decode or encode replaces it.
 *     Script is single-threaded, so one slot of each kind is enough.
 *   - Text crosses as a pointer to a static buffer that the binding copies at
 *     once (as a Pointer through its textOf(), never as ZStringNative: the
 *     engine FREES a returned C string).
 *   - An open animation and an animation being written are HANDLES: positive
 *     ints, generation-tagged, 0 = invalid. A stale or never-created handle
 *     is a harmless no-op.
 *   - NOTHING THROWS. This is C: there is no exception to firewall. A refused
 *     call returns 0 and wpx_last_error() says why.
 *
 * Safety. A WebP file is untrusted input: every byte may be hostile. libwebp
 * is written for that (it is the decoder in Chrome and Android) and is fuzzed
 * upstream; this shim adds the checks that are its caller's: a length for
 * every buffer, exact sizes for pixel buffers before a byte is read, a cap on
 * how many pixels one decode may allocate (WPX_MAX_PIXELS), and no arithmetic
 * on a size that has not been range-checked first. tests/fuzz_test.c feeds it
 * damaged files under ASan/UBSan.
 *
 * Threads. libwebp is built without its worker threads, so nothing here runs
 * off the caller's thread and no callback exists to reach script (suite
 * rule 1).
 *
 * Build: compiled with libwebp into ONE shared library named "webpxt"
 * (webpxt.so / webpxt.dll / webpxt.dylib), or for the web into a static
 * archive. See CMakeLists.txt.
 * ----------------------------------------------------------------------------
 */

#include "webp/decode.h"
#include "webp/demux.h"
#include "webp/encode.h"
#include "webp/mux.h"

#include <limits.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
    #define WPX_API __declspec(dllexport)
#else
    #define WPX_API __attribute__((visibility("default")))
#endif

/* Bump when the exported ABI changes; src/webpxt.lcb's checkABI() names the
 * same number and refuses a library that answers another. */
#define WPX_ABI_VERSION 1

/* The most pixels one decode may produce: 2^26, an 8192 x 8192 picture, which
 * is 256 MB of imageData plus 64 MB of alphaData. A WebP header can claim
 * 16383 x 16383 in thirty bytes, and without a cap those thirty bytes would
 * ask this process for more than a gigabyte. A bigger picture is read with
 * wpx_decode_scaled, which scales while it decodes and never holds the full
 * size. */
#define WPX_MAX_PIXELS (1 << 26)

/* WebP's own limit on either side of a picture. */
#define WPX_MAX_SIDE 16383

/* Open animations, and animations being written, at one time. */
#define WPX_MAX_HANDLES 64

/* Frames one written animation may hold, and the longest one frame may show. */
#define WPX_MAX_FRAMES 10000
#define WPX_MAX_DURATION_MS 600000

/* The longest a whole animation may last, written or read: libwebp keeps a
 * frame's start in an int of milliseconds when it writes (the timestamp
 * wpx_animenc_add passes) and when it reads (the end time its decoder adds
 * each frame's duration to), so the last frame must end by INT_MAX, about
 * 24.8 days. The two limits above would allow 6,000,000,000. */
#define WPX_MAX_TOTAL_MS INT_MAX

/* ------------------------------------------------------------------ */
/* The last error, and the text buffer                                  */
/* ------------------------------------------------------------------ */
static char s_error[256] = "";
static char s_text[128] = "";

static void set_error(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    vsnprintf(s_error, sizeof s_error, format, args);
    va_end(args);
}

static void clear_error(void)
{
    s_error[0] = '\0';
}

static const char *status_text(VP8StatusCode status)
{
    switch (status) {
    case VP8_STATUS_OK: return "no error";
    case VP8_STATUS_OUT_OF_MEMORY: return "out of memory";
    case VP8_STATUS_INVALID_PARAM: return "an invalid parameter";
    case VP8_STATUS_BITSTREAM_ERROR: return "the data is not a valid WebP image";
    case VP8_STATUS_UNSUPPORTED_FEATURE: return "the file uses a WebP feature this library does not read";
    case VP8_STATUS_SUSPENDED: return "the decode was suspended";
    case VP8_STATUS_USER_ABORT: return "the decode was stopped";
    case VP8_STATUS_NOT_ENOUGH_DATA: return "the data ends before the image does (a truncated file)";
    default: return "an unknown decoder error";
    }
}

/* A refusal from the decoder, in words that fit the bytes: data that does
 * not even begin as a WebP file is "not WebP", whatever the decoder's own
 * status (to it, seven bytes of anything are "not enough data"). */
static void explain_decode(VP8StatusCode status, const uint8_t *data, int length)
{
    if (length < 12 || memcmp(data, "RIFF", 4) != 0 || memcmp(data + 8, "WEBP", 4) != 0) {
        set_error("the data is not a WebP image (it does not begin as one)");
        return;
    }
    set_error("%s", status_text(status));
}

static const char *encode_error_text(WebPEncodingError code)
{
    switch (code) {
    case VP8_ENC_OK: return "no error";
    case VP8_ENC_ERROR_OUT_OF_MEMORY: return "out of memory";
    case VP8_ENC_ERROR_BITSTREAM_OUT_OF_MEMORY: return "out of memory while writing the file";
    case VP8_ENC_ERROR_NULL_PARAMETER: return "a missing parameter";
    case VP8_ENC_ERROR_INVALID_CONFIGURATION: return "an invalid encoder setting";
    case VP8_ENC_ERROR_BAD_DIMENSION: return "a width or height WebP cannot hold";
    case VP8_ENC_ERROR_PARTITION0_OVERFLOW: return "the picture is too detailed for one lossy partition; lower the quality";
    case VP8_ENC_ERROR_PARTITION_OVERFLOW: return "the picture is too detailed for one lossy partition; lower the quality";
    case VP8_ENC_ERROR_BAD_WRITE: return "the file could not be written to memory";
    case VP8_ENC_ERROR_FILE_TOO_BIG: return "the file would pass 4 GB";
    case VP8_ENC_ERROR_USER_ABORT: return "the encode was stopped";
    default: return "an unknown encoder error";
    }
}

/* ------------------------------------------------------------------ */
/* The picture slot: what the last decode produced                      */
/* ------------------------------------------------------------------ */
typedef struct {
    uint8_t *pixels;        /* width * height * 4: unused, R, G, B      */
    uint8_t *alpha;         /* width * height                           */
    int width;
    int height;
    int translucent;        /* 1 when any alpha byte is below 255       */
} wpx_picture;

static wpx_picture s_picture = { NULL, NULL, 0, 0, 0 };

static void picture_release(void)
{
    free(s_picture.pixels);
    free(s_picture.alpha);
    s_picture.pixels = NULL;
    s_picture.alpha = NULL;
    s_picture.width = 0;
    s_picture.height = 0;
    s_picture.translucent = 0;
}

/* Room for a width x height picture, or 0 with the error set. Both sides are
 * 1..WPX_MAX_SIDE here, so the products below cannot overflow an int. */
static int picture_reserve(int width, int height)
{
    picture_release();
    if (width < 1 || height < 1 || width > WPX_MAX_SIDE || height > WPX_MAX_SIDE) {
        set_error("a picture of %d x %d cannot be held", width, height);
        return 0;
    }
    if ((int64_t)width * height > WPX_MAX_PIXELS) {
        set_error("the picture is %d x %d, over the limit of %d pixels for one decode; read it smaller with wpDecodeScaled",
                  width, height, WPX_MAX_PIXELS);
        return 0;
    }
    s_picture.pixels = (uint8_t *)malloc((size_t)width * (size_t)height * 4);
    s_picture.alpha = (uint8_t *)malloc((size_t)width * (size_t)height);
    if (s_picture.pixels == NULL || s_picture.alpha == NULL) {
        picture_release();
        set_error("out of memory for a picture of %d x %d", width, height);
        return 0;
    }
    s_picture.width = width;
    s_picture.height = height;
    return 1;
}

/* The slot holds A,R,G,B in `pixels` (as libwebp's MODE_ARGB wrote them):
 * move each A to the alpha plane and leave the engine's unused byte at 255.
 * (255, not 0: the dictionary calls the byte unused, and a reader that did
 * take it for alpha would then see a solid picture, not an invisible one.) */
static void picture_split_argb(void)
{
    size_t count = (size_t)s_picture.width * (size_t)s_picture.height;
    uint8_t *p = s_picture.pixels;
    int translucent = 0;
    for (size_t i = 0; i < count; i++) {
        uint8_t a = p[i * 4];
        s_picture.alpha[i] = a;
        if (a != 255) translucent = 1;
        p[i * 4] = 255;
    }
    s_picture.translucent = translucent;
}

/* Fill the slot from a canvas of R,G,B,A (what the animation decoder gives). */
static void picture_fill_rgba(const uint8_t *rgba)
{
    size_t count = (size_t)s_picture.width * (size_t)s_picture.height;
    uint8_t *p = s_picture.pixels;
    int translucent = 0;
    for (size_t i = 0; i < count; i++) {
        uint8_t a = rgba[i * 4 + 3];
        p[i * 4] = 255;
        p[i * 4 + 1] = rgba[i * 4];
        p[i * 4 + 2] = rgba[i * 4 + 1];
        p[i * 4 + 3] = rgba[i * 4 + 2];
        s_picture.alpha[i] = a;
        if (a != 255) translucent = 1;
    }
    s_picture.translucent = translucent;
}

/* ------------------------------------------------------------------ */
/* The output slot: what the last encode produced                       */
/* ------------------------------------------------------------------ */
static uint8_t *s_output = NULL;        /* libwebp's block: WebPFree     */
static int s_outputLength = 0;

static void output_release(void)
{
    if (s_output != NULL) WebPFree(s_output);
    s_output = NULL;
    s_outputLength = 0;
}

/* Take ownership of a block libwebp allocated. 0 with the error set when it
 * is empty or too long for the int the boundary carries. */
static int output_take(uint8_t *bytes, size_t length)
{
    output_release();
    if (bytes == NULL || length == 0) {
        if (bytes != NULL) WebPFree(bytes);
        set_error("the encoder produced no data");
        return 0;
    }
    if (length > (size_t)INT_MAX) {
        WebPFree(bytes);
        set_error("the encoded file is over 2 GB");
        return 0;
    }
    s_output = bytes;
    s_outputLength = (int)length;
    return s_outputLength;
}

/* ------------------------------------------------------------------ */
/* Handles. A handle is (generation << 8) | (slot + 1): the slot in the */
/* low byte, 23 bits of generation above it, always positive. Closing a */
/* slot bumps its generation, so an old handle stays dead after the     */
/* slot is used again. A slot whose generation would wrap is retired,   */
/* never reused (box3dxt's rule: a wrapped generation hands out the     */
/* bits of the first handle again, naming a stranger).                  */
/* ------------------------------------------------------------------ */
#define WPX_GEN_MAX 0x7FFFFF

typedef struct {
    WebPAnimDecoder *decoder;
    uint8_t *data;              /* our copy: the decoder reads it for life */
    WebPAnimInfo info;
    int index;                  /* frames decoded since the last rewind    */
    int lastTimestamp;          /* end time of the frame before, in ms     */
    int lastDuration;           /* how long the last decoded frame shows   */
    int used;
    int retired;
    int generation;
} wpx_reader;

typedef struct {
    WebPAnimEncoder *encoder;
    WebPConfig config;
    int width;
    int height;
    int timestamp;              /* where the next frame starts, in ms      */
    int frames;
    int used;
    int retired;
    int generation;
} wpx_writer;

static wpx_reader s_readers[WPX_MAX_HANDLES];
static wpx_writer s_writers[WPX_MAX_HANDLES];

static int handle_of(int slot, int generation)
{
    return (generation << 8) | (slot + 1);
}

static wpx_reader *reader_of(int handle)
{
    int slot;
    if (handle <= 0) return NULL;
    slot = (handle & 0xFF) - 1;
    if (slot < 0 || slot >= WPX_MAX_HANDLES) return NULL;
    if (!s_readers[slot].used || s_readers[slot].generation != (handle >> 8)) return NULL;
    return &s_readers[slot];
}

static wpx_writer *writer_of(int handle)
{
    int slot;
    if (handle <= 0) return NULL;
    slot = (handle & 0xFF) - 1;
    if (slot < 0 || slot >= WPX_MAX_HANDLES) return NULL;
    if (!s_writers[slot].used || s_writers[slot].generation != (handle >> 8)) return NULL;
    return &s_writers[slot];
}

static void reader_free(wpx_reader *reader)
{
    if (reader->decoder != NULL) WebPAnimDecoderDelete(reader->decoder);
    free(reader->data);
    reader->decoder = NULL;
    reader->data = NULL;
    reader->used = 0;
    if (reader->generation >= WPX_GEN_MAX) reader->retired = 1;
    else reader->generation++;
}

static void writer_free(wpx_writer *writer)
{
    if (writer->encoder != NULL) WebPAnimEncoderDelete(writer->encoder);
    writer->encoder = NULL;
    writer->used = 0;
    if (writer->generation >= WPX_GEN_MAX) writer->retired = 1;
    else writer->generation++;
}

/* ------------------------------------------------------------------ */
/* The library                                                          */
/* ------------------------------------------------------------------ */
WPX_API int wpx_abi_version(void)
{
    return WPX_ABI_VERSION;
}

/* "webpxt ABI 1; libwebp 1.6.0": the number is the linked decoder's own. */
WPX_API const char *wpx_library_version(void)
{
    int v = WebPGetDecoderVersion();
    snprintf(s_text, sizeof s_text, "webpxt ABI %d; libwebp %d.%d.%d",
             WPX_ABI_VERSION, (v >> 16) & 0xFF, (v >> 8) & 0xFF, v & 0xFF);
    return s_text;
}

/* Why the last refused call was refused; empty after a call that worked. */
WPX_API const char *wpx_last_error(void)
{
    return s_error;
}

/* The length of a text this library returned, for the binding's copy. */
WPX_API int wpx_text_length(const char *text)
{
    size_t n;
    if (text == NULL) return 0;
    n = strlen(text);
    return n > (size_t)INT_MAX ? INT_MAX : (int)n;
}

/* ------------------------------------------------------------------ */
/* Looking at a file without decoding it                                */
/* ------------------------------------------------------------------ */
static struct {
    int width, height, hasAlpha, animated, frames, loops, compression;
} s_info;

/* A buffer the caller says holds `length` bytes of a WebP file. */
static int input_ok(const uint8_t *data, int length)
{
    if (data == NULL || length <= 0) {
        set_error("no data: the WebP file is empty");
        return 0;
    }
    return 1;
}

/* Read the header of a WebP file: 1 and the wpx_info_* getters answer, or 0.
 * Nothing is decoded, so this is cheap on any size of file. */
WPX_API int wpx_info_read(const uint8_t *data, int length)
{
    WebPBitstreamFeatures features;
    VP8StatusCode status;
    memset(&s_info, 0, sizeof s_info);
    if (!input_ok(data, length)) return 0;
    status = WebPGetFeatures(data, (size_t)length, &features);
    if (status != VP8_STATUS_OK) {
        explain_decode(status, data, length);
        return 0;
    }
    s_info.width = features.width;
    s_info.height = features.height;
    s_info.hasAlpha = features.has_alpha ? 1 : 0;
    s_info.animated = features.has_animation ? 1 : 0;
    s_info.frames = 1;
    s_info.loops = 0;
    /* 1 lossy, 2 lossless, 0 mixed or not stated (an animation's frames may
     * each be either). */
    s_info.compression = features.format == 1 ? 1 : (features.format == 2 ? 2 : 0);
    if (features.has_animation) {
        WebPData whole;
        WebPDemuxer *demuxer;
        whole.bytes = data;
        whole.size = (size_t)length;
        demuxer = WebPDemux(&whole);
        if (demuxer == NULL) {
            memset(&s_info, 0, sizeof s_info);
            set_error("the animation's frames could not be read (a damaged or truncated file)");
            return 0;
        }
        s_info.width = (int)WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_WIDTH);
        s_info.height = (int)WebPDemuxGetI(demuxer, WEBP_FF_CANVAS_HEIGHT);
        s_info.frames = (int)WebPDemuxGetI(demuxer, WEBP_FF_FRAME_COUNT);
        s_info.loops = (int)WebPDemuxGetI(demuxer, WEBP_FF_LOOP_COUNT);
        WebPDemuxDelete(demuxer);
    }
    clear_error();
    return 1;
}

WPX_API int wpx_info_width(void) { return s_info.width; }
WPX_API int wpx_info_height(void) { return s_info.height; }
WPX_API int wpx_info_has_alpha(void) { return s_info.hasAlpha; }
WPX_API int wpx_info_is_animated(void) { return s_info.animated; }
WPX_API int wpx_info_frame_count(void) { return s_info.frames; }
WPX_API int wpx_info_loop_count(void) { return s_info.loops; }
WPX_API int wpx_info_compression(void) { return s_info.compression; }

/* ------------------------------------------------------------------ */
/* Decoding a picture                                                   */
/* ------------------------------------------------------------------ */

/* The first frame of an animation, composed on its canvas, into the slot. */
static int decode_first_frame(const uint8_t *data, int length)
{
    WebPAnimDecoderOptions options;
    WebPAnimDecoder *decoder;
    WebPAnimInfo info;
    WebPData whole;
    uint8_t *canvas = NULL;
    int timestamp = 0;
    int ok = 0;
    if (!WebPAnimDecoderOptionsInit(&options)) {
        set_error("libwebp's animation decoder is a different version than this library was built for");
        return 0;
    }
    options.color_mode = MODE_RGBA;
    options.use_threads = 0;
    whole.bytes = data;
    whole.size = (size_t)length;
    decoder = WebPAnimDecoderNew(&whole, &options);
    if (decoder == NULL) {
        set_error("the animation could not be read (a damaged or truncated file)");
        return 0;
    }
    if (!WebPAnimDecoderGetInfo(decoder, &info)) {
        set_error("the animation's size could not be read");
    } else if (info.canvas_width > WPX_MAX_SIDE || info.canvas_height > WPX_MAX_SIDE) {
        set_error("the animation's canvas is larger than WebP allows");
    } else if (picture_reserve((int)info.canvas_width, (int)info.canvas_height)) {
        if (WebPAnimDecoderHasMoreFrames(decoder) && WebPAnimDecoderGetNext(decoder, &canvas, &timestamp)
            && canvas != NULL) {
            picture_fill_rgba(canvas);
            ok = 1;
        } else {
            picture_release();
            set_error("the animation's first frame could not be decoded");
        }
    }
    WebPAnimDecoderDelete(decoder);
    return ok;
}

static int decode_into_slot(const uint8_t *data, int length, int wantWidth, int wantHeight, int scaled)
{
    WebPDecoderConfig config;
    VP8StatusCode status;
    int width, height;
    picture_release();
    if (!input_ok(data, length)) return 0;
    if (!WebPInitDecoderConfig(&config)) {
        set_error("libwebp's decoder is a different version than this library was built for");
        return 0;
    }
    status = WebPGetFeatures(data, (size_t)length, &config.input);
    if (status != VP8_STATUS_OK) {
        explain_decode(status, data, length);
        return 0;
    }
    if (config.input.has_animation) {
        if (scaled) {
            set_error("an animation cannot be scaled while it is decoded; open it with wpAnimOpen and scale the frames");
            return 0;
        }
        if (!decode_first_frame(data, length)) return 0;
        clear_error();
        return 1;
    }
    width = config.input.width;
    height = config.input.height;
    if (width < 1 || height < 1 || width > WPX_MAX_SIDE || height > WPX_MAX_SIDE) {
        set_error("the file states a size of %d x %d, which WebP cannot hold", width, height);
        return 0;
    }
    if (scaled) {
        if (wantWidth < 0 || wantHeight < 0 || (wantWidth == 0 && wantHeight == 0)
            || wantWidth > WPX_MAX_SIDE || wantHeight > WPX_MAX_SIDE) {
            set_error("a scaled size of %d x %d: give a width, a height or both, each from 1 to %d (0 keeps the shape)",
                      wantWidth, wantHeight, WPX_MAX_SIDE);
            return 0;
        }
        /* One side given: the other keeps the picture's shape, rounded, and
         * never below one pixel. */
        if (wantWidth == 0) {
            int64_t w = ((int64_t)width * wantHeight + height / 2) / height;
            wantWidth = w < 1 ? 1 : (w > WPX_MAX_SIDE ? WPX_MAX_SIDE : (int)w);
        } else if (wantHeight == 0) {
            int64_t h = ((int64_t)height * wantWidth + width / 2) / width;
            wantHeight = h < 1 ? 1 : (h > WPX_MAX_SIDE ? WPX_MAX_SIDE : (int)h);
        }
        if (wantWidth != width || wantHeight != height) {
            config.options.use_scaling = 1;
            config.options.scaled_width = wantWidth;
            config.options.scaled_height = wantHeight;
        }
        width = wantWidth;
        height = wantHeight;
    }
    if (!picture_reserve(width, height)) return 0;
    config.options.use_threads = 0;
    config.output.colorspace = MODE_ARGB;
    config.output.is_external_memory = 1;
    config.output.u.RGBA.rgba = s_picture.pixels;
    config.output.u.RGBA.stride = width * 4;
    config.output.u.RGBA.size = (size_t)width * (size_t)height * 4;
    status = WebPDecode(data, (size_t)length, &config);
    WebPFreeDecBuffer(&config.output);      /* external memory: frees nothing of ours */
    if (status != VP8_STATUS_OK) {
        picture_release();
        explain_decode(status, data, length);
        return 0;
    }
    picture_split_argb();
    clear_error();
    return 1;
}

/* Decode a WebP file at its own size into the picture slot: 1, or 0. An
 * animation gives its first frame. */
WPX_API int wpx_decode_image(const uint8_t *data, int length)
{
    return decode_into_slot(data, length, 0, 0, 0);
}

/* Decode a still WebP file straight to width x height (libwebp scales as it
 * decodes, so the full-size picture is never held). A 0 for one side keeps
 * the picture's shape. */
WPX_API int wpx_decode_scaled(const uint8_t *data, int length, int width, int height)
{
    return decode_into_slot(data, length, width, height, 1);
}

WPX_API int wpx_image_width(void) { return s_picture.width; }
WPX_API int wpx_image_height(void) { return s_picture.height; }
WPX_API int wpx_image_is_translucent(void) { return s_picture.translucent; }
WPX_API const uint8_t *wpx_image_pixels(void) { return s_picture.pixels; }
WPX_API const uint8_t *wpx_image_alpha(void) { return s_picture.alpha; }

WPX_API int wpx_image_pixels_length(void)
{
    return s_picture.pixels == NULL ? 0 : s_picture.width * s_picture.height * 4;
}

WPX_API int wpx_image_alpha_length(void)
{
    return s_picture.alpha == NULL ? 0 : s_picture.width * s_picture.height;
}

/* Free the picture slot. The binding calls this once it has its copies. */
WPX_API void wpx_image_release(void)
{
    picture_release();
}

/* ------------------------------------------------------------------ */
/* Encoding a picture                                                   */
/* ------------------------------------------------------------------ */

/* The checks every picture coming IN goes through, before a byte is read:
 * the size WebP can hold, and buffers of exactly the size that size means. */
static int pixels_ok(const uint8_t *pixels, int pixelsLength, const uint8_t *alpha, int alphaLength,
                     int width, int height)
{
    int64_t count;
    if (width < 1 || height < 1 || width > WPX_MAX_SIDE || height > WPX_MAX_SIDE) {
        set_error("a WebP picture is from 1 x 1 to %d x %d; this one is %d x %d",
                  WPX_MAX_SIDE, WPX_MAX_SIDE, width, height);
        return 0;
    }
    count = (int64_t)width * height;
    if (pixels == NULL || (int64_t)pixelsLength != count * 4) {
        set_error("the imageData is %d bytes; a %d x %d picture is %lld (4 a pixel)",
                  pixelsLength < 0 ? 0 : pixelsLength, width, height, (long long)(count * 4));
        return 0;
    }
    if (alphaLength != 0 && (alpha == NULL || (int64_t)alphaLength != count)) {
        set_error("the alphaData is %d bytes; a %d x %d picture is %lld (1 a pixel), or empty for a solid picture",
                  alphaLength < 0 ? 0 : alphaLength, width, height, (long long)count);
        return 0;
    }
    return 1;
}

/* quality 0..100 (a NaN fails both comparisons' complement), effort 0..6. */
static int settings_ok(double quality, int effort)
{
    if (!(quality >= 0.0 && quality <= 100.0)) {
        set_error("the quality is a number from 0 to 100");
        return 0;
    }
    if (effort < 0 || effort > 6) {
        set_error("the effort is a whole number from 0 (fastest) to 6 (smallest file)");
        return 0;
    }
    return 1;
}

static int config_make(WebPConfig *config, double quality, int lossless, int effort)
{
    if (!WebPConfigInit(config)) {
        set_error("libwebp's encoder is a different version than this library was built for");
        return 0;
    }
    config->quality = (float)quality;
    config->method = effort;
    config->thread_level = 0;
    if (lossless) {
        config->lossless = 1;
        /* Keep the colour under fully clear pixels, so lossless means the
         * bytes that went in come out, every one. */
        config->exact = 1;
    }
    if (!WebPValidateConfig(config)) {
        set_error("the encoder refused these settings");
        return 0;
    }
    return 1;
}

/* A WebPPicture holding the caller's picture as libwebp's 0xAARRGGBB words.
 * The caller frees it with WebPPictureFree. pixels_ok() has run. */
static int picture_import(WebPPicture *picture, const uint8_t *pixels, const uint8_t *alpha, int alphaLength,
                          int width, int height)
{
    if (!WebPPictureInit(picture)) {
        set_error("libwebp's encoder is a different version than this library was built for");
        return 0;
    }
    picture->use_argb = 1;
    picture->width = width;
    picture->height = height;
    if (!WebPPictureAlloc(picture)) {
        set_error("out of memory for a picture of %d x %d", width, height);
        return 0;
    }
    for (int y = 0; y < height; y++) {
        const uint8_t *row = pixels + (size_t)y * (size_t)width * 4;
        const uint8_t *alphaRow = alphaLength != 0 ? alpha + (size_t)y * (size_t)width : NULL;
        uint32_t *out = picture->argb + (size_t)y * (size_t)picture->argb_stride;
        for (int x = 0; x < width; x++) {
            uint32_t a = alphaRow != NULL ? alphaRow[x] : 255u;
            out[x] = (a << 24) | ((uint32_t)row[x * 4 + 1] << 16) | ((uint32_t)row[x * 4 + 2] << 8)
                     | (uint32_t)row[x * 4 + 3];
        }
    }
    return 1;
}

/* Encode one picture as a WebP file into the output slot. Returns the file's
 * length in bytes, or 0. `lossless` 0 writes the lossy format at `quality`
 * (0 smallest to 100 best); otherwise the lossless one, where `quality` only
 * trades time for size. An empty alpha (length 0) is a solid picture. */
WPX_API int wpx_encode_image(const uint8_t *pixels, int pixelsLength, const uint8_t *alpha, int alphaLength,
                       int width, int height, double quality, int lossless, int effort)
{
    WebPConfig config;
    WebPPicture picture;
    WebPMemoryWriter writer;
    int ok;
    output_release();
    if (!pixels_ok(pixels, pixelsLength, alpha, alphaLength, width, height)) return 0;
    if (!settings_ok(quality, effort)) return 0;
    if (!config_make(&config, quality, lossless, effort)) return 0;
    if (!picture_import(&picture, pixels, alpha, alphaLength, width, height)) return 0;
    WebPMemoryWriterInit(&writer);
    picture.writer = WebPMemoryWrite;
    picture.custom_ptr = &writer;
    ok = WebPEncode(&config, &picture);
    if (!ok) {
        set_error("%s", encode_error_text(picture.error_code));
        WebPPictureFree(&picture);
        WebPMemoryWriterClear(&writer);
        return 0;
    }
    WebPPictureFree(&picture);
    /* The writer's block becomes the output slot's. */
    if (!output_take(writer.mem, writer.size)) return 0;
    clear_error();
    return s_outputLength;
}

WPX_API const uint8_t *wpx_output_bytes(void) { return s_output; }
WPX_API int wpx_output_length(void) { return s_outputLength; }

/* Free the output slot. The binding calls this once it has its copy. */
WPX_API void wpx_output_release(void)
{
    output_release();
}

/* ------------------------------------------------------------------ */
/* Reading an animation, frame by frame                                 */
/* ------------------------------------------------------------------ */

/* Whether an animation's frames add up to WPX_MAX_TOTAL_MS or less. Each
 * duration is the file's 24-bit field, so the sum is kept in 64 bits and the
 * walk stops as soon as it is over. A file the demuxer cannot walk is left to
 * the decoder, which says what is wrong with it. */
static int durations_fit(const WebPAnimDecoder *decoder)
{
    const WebPDemuxer *demux = WebPAnimDecoderGetDemuxer(decoder);
    WebPIterator iter;
    int64_t total = 0;
    if (demux == NULL || !WebPDemuxGetFrame(demux, 1, &iter)) return 1;
    do {
        total += iter.duration;
    } while (total <= WPX_MAX_TOTAL_MS && WebPDemuxNextFrame(&iter));
    WebPDemuxReleaseIterator(&iter);
    return total <= WPX_MAX_TOTAL_MS;
}

/* Open a WebP file (animated, or a still, which is an animation of one
 * frame) for reading frame by frame. Returns a handle, or 0. The bytes are
 * copied: the caller's buffer need not outlive the call. */
WPX_API int wpx_anim_open(const uint8_t *data, int length)
{
    WebPAnimDecoderOptions options;
    WebPData whole;
    wpx_reader *reader = NULL;
    int slot;
    if (!input_ok(data, length)) return 0;
    for (slot = 0; slot < WPX_MAX_HANDLES; slot++) {
        if (!s_readers[slot].used && !s_readers[slot].retired) {
            reader = &s_readers[slot];
            break;
        }
    }
    if (reader == NULL) {
        set_error("%d animations are open already; close one with wpAnimClose", WPX_MAX_HANDLES);
        return 0;
    }
    if (!WebPAnimDecoderOptionsInit(&options)) {
        set_error("libwebp's animation decoder is a different version than this library was built for");
        return 0;
    }
    options.color_mode = MODE_RGBA;
    options.use_threads = 0;
    reader->data = (uint8_t *)malloc((size_t)length);
    if (reader->data == NULL) {
        set_error("out of memory for a file of %d bytes", length);
        return 0;
    }
    memcpy(reader->data, data, (size_t)length);
    whole.bytes = reader->data;
    whole.size = (size_t)length;
    reader->decoder = WebPAnimDecoderNew(&whole, &options);
    if (reader->decoder == NULL || !WebPAnimDecoderGetInfo(reader->decoder, &reader->info)) {
        if (reader->decoder != NULL) WebPAnimDecoderDelete(reader->decoder);
        reader->decoder = NULL;
        free(reader->data);
        reader->data = NULL;
        set_error("the data is not a WebP image this library can read (damaged, truncated, or not WebP)");
        return 0;
    }
    if (reader->info.canvas_width < 1 || reader->info.canvas_height < 1
        || reader->info.canvas_width > WPX_MAX_SIDE || reader->info.canvas_height > WPX_MAX_SIDE
        || (int64_t)reader->info.canvas_width * reader->info.canvas_height > WPX_MAX_PIXELS) {
        WebPAnimDecoderDelete(reader->decoder);
        reader->decoder = NULL;
        free(reader->data);
        reader->data = NULL;
        set_error("the animation's canvas is over the limit of %d pixels", WPX_MAX_PIXELS);
        return 0;
    }
    if (!durations_fit(reader->decoder)) {
        WebPAnimDecoderDelete(reader->decoder);
        reader->decoder = NULL;
        free(reader->data);
        reader->data = NULL;
        set_error("the animation's frames add up to more than %d milliseconds (about 24.8 days), which libwebp "
                  "cannot time", WPX_MAX_TOTAL_MS);
        return 0;
    }
    reader->index = 0;
    reader->lastTimestamp = 0;
    reader->lastDuration = 0;
    reader->used = 1;
    clear_error();
    return handle_of(slot, reader->generation);
}

/* Close an open animation. A stale or 0 handle does nothing. */
WPX_API void wpx_anim_close(int handle)
{
    wpx_reader *reader = reader_of(handle);
    if (reader != NULL) reader_free(reader);
}

WPX_API int wpx_anim_is_valid(int handle)
{
    return reader_of(handle) != NULL ? 1 : 0;
}

WPX_API int wpx_anim_width(int handle)
{
    wpx_reader *reader = reader_of(handle);
    return reader != NULL ? (int)reader->info.canvas_width : 0;
}

WPX_API int wpx_anim_height(int handle)
{
    wpx_reader *reader = reader_of(handle);
    return reader != NULL ? (int)reader->info.canvas_height : 0;
}

WPX_API int wpx_anim_frame_count(int handle)
{
    wpx_reader *reader = reader_of(handle);
    return reader != NULL ? (int)reader->info.frame_count : 0;
}

/* How many times the file asks to be played: 0 means for ever. */
WPX_API int wpx_anim_loop_count(int handle)
{
    wpx_reader *reader = reader_of(handle);
    return reader != NULL ? (int)reader->info.loop_count : 0;
}

/* Decode the next frame, composed on the whole canvas, into the picture
 * slot: 1, or 0 when the last frame has been read (the error stays empty)
 * or the frame is damaged (the error says so). */
WPX_API int wpx_anim_next(int handle)
{
    wpx_reader *reader = reader_of(handle);
    uint8_t *canvas = NULL;
    int timestamp = 0;
    picture_release();
    if (reader == NULL) {
        set_error("not an open animation (closed, or never opened)");
        return 0;
    }
    if (!WebPAnimDecoderHasMoreFrames(reader->decoder)) {
        clear_error();
        return 0;
    }
    if (!WebPAnimDecoderGetNext(reader->decoder, &canvas, &timestamp) || canvas == NULL) {
        set_error("frame %d of the animation could not be decoded (a damaged file)", reader->index + 1);
        return 0;
    }
    if (!picture_reserve((int)reader->info.canvas_width, (int)reader->info.canvas_height)) return 0;
    picture_fill_rgba(canvas);
    /* libwebp gives each frame's END time; the difference from the frame
     * before is how long this one shows. */
    reader->lastDuration = timestamp > reader->lastTimestamp ? timestamp - reader->lastTimestamp : 0;
    reader->lastTimestamp = timestamp;
    reader->index++;
    clear_error();
    return 1;
}

/* The 1-based number of the frame wpx_anim_next last decoded; 0 before any. */
WPX_API int wpx_anim_frame_index(int handle)
{
    wpx_reader *reader = reader_of(handle);
    return reader != NULL ? reader->index : 0;
}

/* How long that frame shows, in milliseconds. */
WPX_API int wpx_anim_frame_duration(int handle)
{
    wpx_reader *reader = reader_of(handle);
    return reader != NULL ? reader->lastDuration : 0;
}

/* Start again: the next wpx_anim_next decodes frame 1. */
WPX_API void wpx_anim_rewind(int handle)
{
    wpx_reader *reader = reader_of(handle);
    if (reader == NULL) return;
    WebPAnimDecoderReset(reader->decoder);
    reader->index = 0;
    reader->lastTimestamp = 0;
    reader->lastDuration = 0;
}

/* How many animations are open (a stack that forgot wpAnimClose can see it). */
WPX_API int wpx_anim_open_count(void)
{
    int count = 0;
    for (int slot = 0; slot < WPX_MAX_HANDLES; slot++) {
        if (s_readers[slot].used) count++;
    }
    return count;
}

/* ------------------------------------------------------------------ */
/* Writing an animation, frame by frame                                 */
/* ------------------------------------------------------------------ */

/* Start an animated WebP of width x height. `loops` is how many times it
 * plays (0 = for ever); quality, lossless and effort are wpx_encode_image's and
 * apply to every frame. Returns a handle, or 0. */
WPX_API int wpx_animenc_create(int width, int height, int loops, double quality, int lossless, int effort)
{
    WebPAnimEncoderOptions options;
    wpx_writer *writer = NULL;
    int slot;
    if (width < 1 || height < 1 || width > WPX_MAX_SIDE || height > WPX_MAX_SIDE) {
        set_error("a WebP animation is from 1 x 1 to %d x %d; this one is %d x %d",
                  WPX_MAX_SIDE, WPX_MAX_SIDE, width, height);
        return 0;
    }
    if (loops < 0 || loops > 65535) {
        set_error("the loop count is from 0 (for ever) to 65535");
        return 0;
    }
    if (!settings_ok(quality, effort)) return 0;
    for (slot = 0; slot < WPX_MAX_HANDLES; slot++) {
        if (!s_writers[slot].used && !s_writers[slot].retired) {
            writer = &s_writers[slot];
            break;
        }
    }
    if (writer == NULL) {
        set_error("%d animations are being written already; finish or discard one", WPX_MAX_HANDLES);
        return 0;
    }
    if (!config_make(&writer->config, quality, lossless, effort)) return 0;
    if (!WebPAnimEncoderOptionsInit(&options)) {
        set_error("libwebp's animation encoder is a different version than this library was built for");
        return 0;
    }
    options.anim_params.loop_count = loops;
    writer->encoder = WebPAnimEncoderNew(width, height, &options);
    if (writer->encoder == NULL) {
        set_error("out of memory for an animation of %d x %d", width, height);
        return 0;
    }
    writer->width = width;
    writer->height = height;
    writer->timestamp = 0;
    writer->frames = 0;
    writer->used = 1;
    clear_error();
    return handle_of(slot, writer->generation);
}

/* Add one frame, shown for `durationMs` milliseconds: 1, or 0. The picture
 * is the animation's size exactly. */
WPX_API int wpx_animenc_add(int handle, const uint8_t *pixels, int pixelsLength, const uint8_t *alpha,
                            int alphaLength, int durationMs)
{
    wpx_writer *writer = writer_of(handle);
    WebPPicture picture;
    int ok;
    if (writer == NULL) {
        set_error("not an animation being written (finished, discarded, or never created)");
        return 0;
    }
    if (durationMs < 1 || durationMs > WPX_MAX_DURATION_MS) {
        set_error("a frame shows for 1 to %d milliseconds", WPX_MAX_DURATION_MS);
        return 0;
    }
    if (writer->frames >= WPX_MAX_FRAMES) {
        set_error("an animation holds at most %d frames", WPX_MAX_FRAMES);
        return 0;
    }
    /* writer->timestamp is at most WPX_MAX_TOTAL_MS, so the subtraction
     * cannot overflow where the sum would have. */
    if (durationMs > WPX_MAX_TOTAL_MS - writer->timestamp) {
        set_error("an animation lasts at most %d milliseconds in all (about 24.8 days); its frames add up to %d so far",
                  WPX_MAX_TOTAL_MS, writer->timestamp);
        return 0;
    }
    if (!pixels_ok(pixels, pixelsLength, alpha, alphaLength, writer->width, writer->height)) return 0;
    if (!picture_import(&picture, pixels, alpha, alphaLength, writer->width, writer->height)) return 0;
    ok = WebPAnimEncoderAdd(writer->encoder, &picture, writer->timestamp, &writer->config);
    WebPPictureFree(&picture);
    if (!ok) {
        set_error("the frame could not be encoded: %s", WebPAnimEncoderGetError(writer->encoder));
        return 0;
    }
    writer->timestamp += durationMs;
    writer->frames++;
    clear_error();
    return 1;
}

WPX_API int wpx_animenc_is_valid(int handle)
{
    return writer_of(handle) != NULL ? 1 : 0;
}

WPX_API int wpx_animenc_frame_count(int handle)
{
    wpx_writer *writer = writer_of(handle);
    return writer != NULL ? writer->frames : 0;
}

/* Write the file into the output slot and close the handle, whatever the
 * outcome. Returns the file's length in bytes, or 0. */
WPX_API int wpx_animenc_finish(int handle)
{
    wpx_writer *writer = writer_of(handle);
    WebPData file;
    int ok;
    output_release();
    if (writer == NULL) {
        set_error("not an animation being written (finished, discarded, or never created)");
        return 0;
    }
    if (writer->frames < 1) {
        writer_free(writer);
        set_error("the animation has no frames");
        return 0;
    }
    WebPDataInit(&file);
    /* The closing call: a NULL frame at the time the last frame ends. */
    ok = WebPAnimEncoderAdd(writer->encoder, NULL, writer->timestamp, NULL)
         && WebPAnimEncoderAssemble(writer->encoder, &file);
    if (!ok) {
        set_error("the animation could not be written: %s", WebPAnimEncoderGetError(writer->encoder));
        WebPDataClear(&file);
        writer_free(writer);
        return 0;
    }
    writer_free(writer);
    /* WebPData's block is libwebp's (WebPFree), as the output slot expects. */
    if (!output_take((uint8_t *)file.bytes, file.size)) return 0;
    clear_error();
    return s_outputLength;
}

/* Drop an animation being written without writing it. A stale handle does
 * nothing. */
WPX_API void wpx_animenc_discard(int handle)
{
    wpx_writer *writer = writer_of(handle);
    if (writer != NULL) writer_free(writer);
}

WPX_API int wpx_animenc_open_count(void)
{
    int count = 0;
    for (int slot = 0; slot < WPX_MAX_HANDLES; slot++) {
        if (s_writers[slot].used) count++;
    }
    return count;
}
