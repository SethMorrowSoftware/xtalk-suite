/*
 * smoke_test.c - the runtime test of the webpxt shim.
 *
 * Links against the webpxt library (or, for the web, the archive) and drives
 * libwebp through the same C entry points the LCB binding calls. It proves
 * what a compile cannot: that a picture written lossless comes back byte for
 * byte, that a lossy one comes back close, that sizes, alpha, scaling and
 * animations are reported as they are, and that the guards make bad buffers,
 * damaged files and stale handles harmless. Run under ASan/UBSan in CI
 * (native-webpxt.yml).
 *
 * EVERY export of src/webp_shim.c is called here: tools/check-shim-coverage.py
 * refuses an export this file never calls.
 *
 * Enable with -DWEBPXT_BUILD_TESTS=ON, then run `ctest` (or the binary).
 */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* The shim's exports, declared as the engine's FFI sees them: plain C. */
extern int wpx_abi_version(void);
extern const char *wpx_library_version(void);
extern const char *wpx_last_error(void);
extern int wpx_text_length(const char *text);
extern int wpx_info_read(const uint8_t *data, int length);
extern int wpx_info_width(void);
extern int wpx_info_height(void);
extern int wpx_info_has_alpha(void);
extern int wpx_info_is_animated(void);
extern int wpx_info_frame_count(void);
extern int wpx_info_loop_count(void);
extern int wpx_info_compression(void);
extern int wpx_decode_image(const uint8_t *data, int length);
extern int wpx_decode_scaled(const uint8_t *data, int length, int width, int height);
extern int wpx_image_width(void);
extern int wpx_image_height(void);
extern int wpx_image_is_translucent(void);
extern const uint8_t *wpx_image_pixels(void);
extern const uint8_t *wpx_image_alpha(void);
extern int wpx_image_pixels_length(void);
extern int wpx_image_alpha_length(void);
extern void wpx_image_release(void);
extern int wpx_encode_image(const uint8_t *pixels, int pixelsLength, const uint8_t *alpha, int alphaLength,
                      int width, int height, double quality, int lossless, int effort);
extern const uint8_t *wpx_output_bytes(void);
extern int wpx_output_length(void);
extern void wpx_output_release(void);
extern int wpx_anim_open(const uint8_t *data, int length);
extern void wpx_anim_close(int handle);
extern int wpx_anim_is_valid(int handle);
extern int wpx_anim_width(int handle);
extern int wpx_anim_height(int handle);
extern int wpx_anim_frame_count(int handle);
extern int wpx_anim_loop_count(int handle);
extern int wpx_anim_next(int handle);
extern int wpx_anim_frame_index(int handle);
extern int wpx_anim_frame_duration(int handle);
extern void wpx_anim_rewind(int handle);
extern int wpx_anim_open_count(void);
extern int wpx_animenc_create(int width, int height, int loops, double quality, int lossless, int effort);
extern int wpx_animenc_add(int handle, const uint8_t *pixels, int pixelsLength, const uint8_t *alpha,
                           int alphaLength, int durationMs);
extern int wpx_animenc_is_valid(int handle);
extern int wpx_animenc_frame_count(int handle);
extern int wpx_animenc_finish(int handle);
extern void wpx_animenc_discard(int handle);
extern int wpx_animenc_open_count(void);

static int s_checks = 0;
static int s_failed = 0;

#define CHECK(cond, ...)                                                      \
    do {                                                                      \
        s_checks++;                                                           \
        if (!(cond)) {                                                        \
            s_failed++;                                                       \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);                       \
            printf(__VA_ARGS__);                                              \
            printf(" [last error: %s]\n", wpx_last_error());                  \
        }                                                                     \
    } while (0)

/* A picture in the engine's layout. `kind` 0 is a smooth gradient (what a
 * lossy codec is good at), 1 is hard-edged blocks and noise. */
typedef struct {
    int width, height;
    uint8_t *pixels;        /* width * height * 4: unused, R, G, B */
    uint8_t *alpha;         /* width * height                      */
} picture;

static uint32_t s_rng = 0x9E3779B9u;

static uint32_t rnd(void)
{
    s_rng ^= s_rng << 13;
    s_rng ^= s_rng >> 17;
    s_rng ^= s_rng << 5;
    return s_rng;
}

static picture picture_make(int width, int height, int kind, int withAlpha)
{
    picture p;
    p.width = width;
    p.height = height;
    p.pixels = (uint8_t *)malloc((size_t)width * (size_t)height * 4);
    p.alpha = (uint8_t *)malloc((size_t)width * (size_t)height);
    if (p.pixels == NULL || p.alpha == NULL) {
        printf("FAIL out of memory in the test itself\n");
        exit(2);
    }
    for (int y = 0; y < height; y++) {
        for (int x = 0; x < width; x++) {
            size_t i = (size_t)y * (size_t)width + (size_t)x;
            uint8_t r, g, b, a;
            if (kind == 0) {
                r = (uint8_t)(x * 255 / (width > 1 ? width - 1 : 1));
                g = (uint8_t)(y * 255 / (height > 1 ? height - 1 : 1));
                b = (uint8_t)((x + y) * 255 / (width + height));
            } else {
                uint32_t v = rnd();
                r = (uint8_t)(((x / 4) % 2) ? 250 : (v & 0xFF));
                g = (uint8_t)(((y / 4) % 2) ? 5 : ((v >> 8) & 0xFF));
                b = (uint8_t)((v >> 16) & 0xFF);
            }
            /* Alpha: clear on the left edge (with colour under it, which a
             * lossless file must keep), solid on the right, a ramp between. */
            a = withAlpha ? (uint8_t)(x == 0 ? 0 : (x >= width - 2 ? 255 : x * 255 / width)) : 255;
            p.pixels[i * 4] = 0;            /* what the engine documents for the unused byte */
            p.pixels[i * 4 + 1] = r;
            p.pixels[i * 4 + 2] = g;
            p.pixels[i * 4 + 3] = b;
            p.alpha[i] = a;
        }
    }
    return p;
}

static void picture_free(picture *p)
{
    free(p->pixels);
    free(p->alpha);
    p->pixels = NULL;
    p->alpha = NULL;
}

/* A copy of the output slot, so a test can keep a file across calls. */
typedef struct {
    uint8_t *bytes;
    int length;
} blob;

static blob output_copy(void)
{
    blob b;
    b.length = wpx_output_length();
    b.bytes = (uint8_t *)malloc(b.length > 0 ? (size_t)b.length : 1);
    if (b.bytes == NULL) {
        printf("FAIL out of memory in the test itself\n");
        exit(2);
    }
    if (b.length > 0) memcpy(b.bytes, wpx_output_bytes(), (size_t)b.length);
    return b;
}

/* The decoded picture slot against `p`: colour compared where `everywhere`
 * or the pixel is not fully clear. Returns the count of differing pixels. */
static long slot_differs(const picture *p, int everywhere)
{
    const uint8_t *pixels = wpx_image_pixels();
    const uint8_t *alpha = wpx_image_alpha();
    long differing = 0;
    size_t count = (size_t)p->width * (size_t)p->height;
    if (pixels == NULL || alpha == NULL) return -1;
    if (wpx_image_width() != p->width || wpx_image_height() != p->height) return -2;
    for (size_t i = 0; i < count; i++) {
        int same = alpha[i] == p->alpha[i] && pixels[i * 4] == 255;
        if (same && (everywhere || p->alpha[i] != 0)) {
            same = pixels[i * 4 + 1] == p->pixels[i * 4 + 1] && pixels[i * 4 + 2] == p->pixels[i * 4 + 2]
                   && pixels[i * 4 + 3] == p->pixels[i * 4 + 3];
        }
        if (!same) differing++;
    }
    return differing;
}

/* Mean absolute colour error of the slot against `p`, over R, G and B. */
static double slot_error(const picture *p)
{
    const uint8_t *pixels = wpx_image_pixels();
    double sum = 0.0;
    size_t count = (size_t)p->width * (size_t)p->height;
    if (pixels == NULL || wpx_image_width() != p->width || wpx_image_height() != p->height) return 1e9;
    for (size_t i = 0; i < count; i++) {
        for (int c = 1; c <= 3; c++) sum += fabs((double)pixels[i * 4 + c] - (double)p->pixels[i * 4 + c]);
    }
    return sum / ((double)count * 3.0);
}

static int pixels_bytes(const picture *p) { return p->width * p->height * 4; }
static int alpha_bytes(const picture *p) { return p->width * p->height; }

/* ------------------------------------------------------------------ */
static void test_library(void)
{
    const char *version = wpx_library_version();
    CHECK(wpx_abi_version() == 1, "ABI is %d", wpx_abi_version());
    CHECK(strncmp(version, "webpxt ABI 1; libwebp 1.6.", 26) == 0, "version text '%s'", version);
    CHECK(wpx_text_length(version) == (int)strlen(version), "text length %d", wpx_text_length(version));
    CHECK(wpx_text_length(NULL) == 0, "text length of NULL");
    CHECK(wpx_last_error()[0] == '\0', "an error before any call: '%s'", wpx_last_error());
    CHECK(wpx_image_pixels() == NULL && wpx_image_pixels_length() == 0 && wpx_image_alpha() == NULL
          && wpx_image_alpha_length() == 0 && wpx_image_width() == 0 && wpx_image_height() == 0
          && wpx_image_is_translucent() == 0, "the picture slot is empty before a decode");
    CHECK(wpx_output_bytes() == NULL && wpx_output_length() == 0, "the output slot is empty before an encode");
}

static void test_lossless(void)
{
    picture p = picture_make(64, 48, 1, 1);
    blob file;
    int n = wpx_encode_image(p.pixels, pixels_bytes(&p), p.alpha, alpha_bytes(&p), 64, 48, 75, 1, 4);
    CHECK(n > 0 && n == wpx_output_length(), "lossless encode gave %d", n);
    CHECK(wpx_last_error()[0] == '\0', "an error after a good encode");
    file = output_copy();
    CHECK(file.length > 12 && memcmp(file.bytes, "RIFF", 4) == 0 && memcmp(file.bytes + 8, "WEBP", 4) == 0,
          "the file does not start RIFF....WEBP");
    wpx_output_release();
    CHECK(wpx_output_bytes() == NULL && wpx_output_length() == 0, "release empties the output slot");

    CHECK(wpx_info_read(file.bytes, file.length) == 1, "info of a lossless file");
    CHECK(wpx_info_width() == 64 && wpx_info_height() == 48, "info size %d x %d", wpx_info_width(), wpx_info_height());
    CHECK(wpx_info_has_alpha() == 1 && wpx_info_is_animated() == 0 && wpx_info_frame_count() == 1
          && wpx_info_loop_count() == 0 && wpx_info_compression() == 2,
          "info flags %d %d %d %d %d", wpx_info_has_alpha(), wpx_info_is_animated(), wpx_info_frame_count(),
          wpx_info_loop_count(), wpx_info_compression());

    CHECK(wpx_decode_image(file.bytes, file.length) == 1, "decode of a lossless file");
    CHECK(wpx_image_pixels_length() == 64 * 48 * 4 && wpx_image_alpha_length() == 64 * 48,
          "buffer lengths %d %d", wpx_image_pixels_length(), wpx_image_alpha_length());
    /* Everywhere: a lossless file keeps the colour under clear pixels too. */
    CHECK(slot_differs(&p, 1) == 0, "lossless round trip: %ld pixels differ", slot_differs(&p, 1));
    CHECK(wpx_image_is_translucent() == 1, "a picture with alpha reads as translucent");
    wpx_image_release();
    CHECK(wpx_image_pixels() == NULL && wpx_image_alpha() == NULL && wpx_image_width() == 0
          && wpx_image_pixels_length() == 0, "release empties the picture slot");
    free(file.bytes);
    picture_free(&p);

    /* No alpha given: a solid picture, and the file says so. */
    p = picture_make(33, 17, 1, 0);
    n = wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, 0, 33, 17, 100, 1, 6);
    CHECK(n > 0, "lossless encode with no alpha");
    file = output_copy();
    CHECK(wpx_info_read(file.bytes, file.length) == 1 && wpx_info_has_alpha() == 0 && wpx_info_width() == 33
          && wpx_info_height() == 17, "info of a solid file");
    CHECK(wpx_decode_image(file.bytes, file.length) == 1 && slot_differs(&p, 1) == 0,
          "solid lossless round trip (odd size)");
    CHECK(wpx_image_is_translucent() == 0, "a solid picture is not translucent");
    free(file.bytes);
    picture_free(&p);

    /* The smallest picture there is. */
    p = picture_make(1, 1, 1, 1);
    p.alpha[0] = 128;
    n = wpx_encode_image(p.pixels, 4, p.alpha, 1, 1, 1, 50, 1, 0);
    CHECK(n > 0, "a 1 x 1 picture encodes");
    file = output_copy();
    CHECK(wpx_decode_image(file.bytes, file.length) == 1 && slot_differs(&p, 1) == 0, "a 1 x 1 picture round trips");
    free(file.bytes);
    picture_free(&p);
}

static void test_lossy(void)
{
    picture p = picture_make(128, 96, 0, 0);
    blob good, small;
    int n = wpx_encode_image(p.pixels, pixels_bytes(&p), p.alpha, alpha_bytes(&p), 128, 96, 95, 0, 4);
    CHECK(n > 0, "lossy encode at 95");
    good = output_copy();
    n = wpx_encode_image(p.pixels, pixels_bytes(&p), p.alpha, alpha_bytes(&p), 128, 96, 10, 0, 4);
    CHECK(n > 0, "lossy encode at 10");
    small = output_copy();
    CHECK(small.length < good.length, "quality 10 (%d bytes) is not smaller than quality 95 (%d)",
          small.length, good.length);
    CHECK(wpx_info_read(good.bytes, good.length) == 1 && wpx_info_compression() == 1 && wpx_info_has_alpha() == 0,
          "info of a lossy file");
    CHECK(wpx_decode_image(good.bytes, good.length) == 1, "decode of a lossy file");
    CHECK(slot_error(&p) < 4.0, "lossy at 95: mean error %.2f", slot_error(&p));
    CHECK(wpx_image_is_translucent() == 0, "an all-solid alpha is not translucent");
    CHECK(wpx_decode_image(small.bytes, small.length) == 1 && slot_error(&p) < 20.0, "lossy at 10: mean error %.2f",
          slot_error(&p));
    free(good.bytes);
    free(small.bytes);
    picture_free(&p);

    /* Lossy with alpha: the alpha plane is kept exactly, colour roughly. */
    p = picture_make(80, 60, 0, 1);
    n = wpx_encode_image(p.pixels, pixels_bytes(&p), p.alpha, alpha_bytes(&p), 80, 60, 90, 0, 2);
    CHECK(n > 0, "lossy encode with alpha");
    good = output_copy();
    CHECK(wpx_info_read(good.bytes, good.length) == 1 && wpx_info_has_alpha() == 1, "a lossy file with alpha says so");
    CHECK(wpx_decode_image(good.bytes, good.length) == 1, "decode of a lossy file with alpha");
    {
        const uint8_t *alpha = wpx_image_alpha();
        int same = alpha != NULL && wpx_image_alpha_length() == alpha_bytes(&p)
                   && memcmp(alpha, p.alpha, (size_t)alpha_bytes(&p)) == 0;
        CHECK(same, "lossy keeps the alpha plane exactly");
    }
    free(good.bytes);
    picture_free(&p);

    /* Every effort level gives a file that decodes. */
    p = picture_make(40, 40, 1, 0);
    for (int effort = 0; effort <= 6; effort++) {
        n = wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, 0, 40, 40, 60, 0, effort);
        CHECK(n > 0 && wpx_decode_image(wpx_output_bytes(), wpx_output_length()) == 1 && wpx_image_width() == 40,
              "effort %d", effort);
    }
    picture_free(&p);
}

static void test_scaled(void)
{
    picture p = picture_make(128, 96, 0, 1);
    blob file;
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), p.alpha, alpha_bytes(&p), 128, 96, 80, 0, 4) > 0, "encode");
    file = output_copy();
    CHECK(wpx_decode_scaled(file.bytes, file.length, 64, 48) == 1 && wpx_image_width() == 64
          && wpx_image_height() == 48 && wpx_image_pixels_length() == 64 * 48 * 4
          && wpx_image_alpha_length() == 64 * 48, "scaled to 64 x 48 gave %d x %d", wpx_image_width(),
          wpx_image_height());
    CHECK(wpx_decode_scaled(file.bytes, file.length, 32, 0) == 1 && wpx_image_width() == 32
          && wpx_image_height() == 24, "a width alone keeps the shape: %d x %d", wpx_image_width(),
          wpx_image_height());
    CHECK(wpx_decode_scaled(file.bytes, file.length, 0, 48) == 1 && wpx_image_width() == 64
          && wpx_image_height() == 48, "a height alone keeps the shape: %d x %d", wpx_image_width(),
          wpx_image_height());
    CHECK(wpx_decode_scaled(file.bytes, file.length, 256, 192) == 1 && wpx_image_width() == 256, "scaling up");
    CHECK(wpx_decode_scaled(file.bytes, file.length, 128, 96) == 1 && wpx_image_width() == 128, "the same size");
    CHECK(wpx_decode_scaled(file.bytes, file.length, 1, 0) == 1 && wpx_image_width() == 1
          && wpx_image_height() == 1, "a side never rounds to nothing: %d x %d", wpx_image_width(),
          wpx_image_height());
    CHECK(wpx_decode_scaled(file.bytes, file.length, 0, 0) == 0 && wpx_last_error()[0] != '\0'
          && wpx_image_pixels() == NULL, "0 x 0 is refused");
    CHECK(wpx_decode_scaled(file.bytes, file.length, -4, 10) == 0, "a negative side is refused");
    CHECK(wpx_decode_scaled(file.bytes, file.length, 16384, 10) == 0, "a side over WebP's limit is refused");
    free(file.bytes);
    picture_free(&p);
}

static void test_refusals(void)
{
    picture p = picture_make(16, 16, 1, 1);
    uint8_t junk[64];
    blob file;
    for (int i = 0; i < 64; i++) junk[i] = (uint8_t)(i * 37 + 11);

    CHECK(wpx_info_read(NULL, 10) == 0 && wpx_last_error()[0] != '\0', "info of NULL");
    CHECK(wpx_info_read(junk, 0) == 0 && wpx_info_read(junk, -5) == 0, "info of no bytes");
    CHECK(wpx_info_read(junk, 64) == 0 && wpx_info_width() == 0, "info of junk");
    CHECK(wpx_decode_image(NULL, 10) == 0 && wpx_decode_image(junk, 0) == 0 && wpx_decode_image(junk, 64) == 0
          && wpx_image_pixels() == NULL, "decode of nothing and of junk");
    CHECK(wpx_anim_open(NULL, 10) == 0 && wpx_anim_open(junk, 0) == 0 && wpx_anim_open(junk, 64) == 0,
          "open of nothing and of junk");

    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), p.alpha, alpha_bytes(&p), 16, 16, 75, 1, 4) > 0, "encode");
    file = output_copy();
    /* A truncated file: every shorter length is refused, none crashes. */
    for (int cut = 0; cut < file.length; cut++) {
        if (wpx_decode_image(file.bytes, cut) != 0) {
            CHECK(0, "a file cut to %d of %d bytes decoded", cut, file.length);
            break;
        }
    }
    CHECK(wpx_last_error()[0] != '\0', "a truncated file leaves an explanation");
    free(file.bytes);

    /* Buffers of the wrong size are refused before a byte is read. */
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p) - 1, NULL, 0, 16, 16, 75, 0, 4) == 0, "imageData one byte short");
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, 0, 16, 17, 75, 0, 4) == 0, "a height the bytes do not match");
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), p.alpha, alpha_bytes(&p) - 1, 16, 16, 75, 0, 4) == 0,
          "alphaData one byte short");
    CHECK(wpx_encode_image(NULL, pixels_bytes(&p), NULL, 0, 16, 16, 75, 0, 4) == 0, "NULL imageData");
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, alpha_bytes(&p), 16, 16, 75, 0, 4) == 0,
          "NULL alphaData with a length");
    CHECK(wpx_encode_image(p.pixels, 0, NULL, 0, 0, 0, 75, 0, 4) == 0, "a 0 x 0 picture");
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, 0, 16384, 1, 75, 0, 4) == 0, "a side over WebP's limit");
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, 0, -16, -16, 75, 0, 4) == 0, "negative sides");
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, 0, 16, 16, -1, 0, 4) == 0, "quality below 0");
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, 0, 16, 16, 100.5, 0, 4) == 0, "quality over 100");
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, 0, 16, 16, NAN, 0, 4) == 0, "quality not a number");
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, 0, 16, 16, 75, 0, 7) == 0, "effort over 6");
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, 0, 16, 16, 75, 0, -1) == 0, "effort below 0");
    CHECK(wpx_last_error()[0] != '\0' && wpx_output_bytes() == NULL && wpx_output_length() == 0,
          "a refused encode leaves an explanation and no output");
    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, 0, 16, 16, 75, 0, 4) > 0 && wpx_last_error()[0] == '\0',
          "a good call clears the error");
    picture_free(&p);
}

/* A file whose header claims more pixels than one decode may hold. Thirty
 * bytes: a lossless header stating 8192 x 8193, and no picture behind it. */
static void test_pixel_cap(void)
{
    uint8_t file[30];
    uint32_t bits = (8192u - 1u) | ((8193u - 1u) << 14);       /* 14 bits each, no alpha, version 0 */
    memset(file, 0, sizeof file);
    memcpy(file, "RIFF", 4);
    file[4] = 22;                                               /* the RIFF payload: 30 - 8 */
    memcpy(file + 8, "WEBPVP8L", 8);
    file[16] = 10;                                              /* the chunk's payload */
    file[20] = 0x2F;                                            /* the lossless signature */
    file[21] = (uint8_t)(bits & 0xFF);
    file[22] = (uint8_t)((bits >> 8) & 0xFF);
    file[23] = (uint8_t)((bits >> 16) & 0xFF);
    file[24] = (uint8_t)((bits >> 24) & 0xFF);
    CHECK(wpx_info_read(file, 30) == 1 && wpx_info_width() == 8192 && wpx_info_height() == 8193,
          "the header reads as %d x %d", wpx_info_width(), wpx_info_height());
    CHECK(wpx_decode_image(file, 30) == 0 && strstr(wpx_last_error(), "over the limit") != NULL,
          "a decode over the pixel limit is refused by name: '%s'", wpx_last_error());
    CHECK(wpx_image_pixels() == NULL, "and allocates nothing");
    /* Scaled, the size is allowed; the picture is missing, so it still fails. */
    CHECK(wpx_decode_scaled(file, 30, 16, 16) == 0 && wpx_image_pixels() == NULL,
          "a scaled decode of a header with no picture fails cleanly");
}

static void test_animation(void)
{
    picture frames[4];
    int durations[4] = { 100, 200, 50, 70 };
    blob file;
    int writer, reader, n, i;

    for (i = 0; i < 4; i++) frames[i] = picture_make(40, 30, 1, i % 2);
    writer = wpx_animenc_create(40, 30, 3, 75, 1, 4);
    CHECK(writer > 0 && wpx_animenc_is_valid(writer) == 1 && wpx_animenc_open_count() == 1,
          "an animation writer: %d", writer);
    CHECK(wpx_animenc_frame_count(writer) == 0, "no frames yet");
    for (i = 0; i < 4; i++) {
        CHECK(wpx_animenc_add(writer, frames[i].pixels, pixels_bytes(&frames[i]), frames[i].alpha,
                              alpha_bytes(&frames[i]), durations[i]) == 1, "frame %d added", i + 1);
    }
    CHECK(wpx_animenc_frame_count(writer) == 4, "four frames counted");
    /* Refusals leave the writer usable. */
    CHECK(wpx_animenc_add(writer, frames[0].pixels, pixels_bytes(&frames[0]) - 4, NULL, 0, 100) == 0,
          "a frame of the wrong size is refused");
    CHECK(wpx_animenc_add(writer, frames[0].pixels, pixels_bytes(&frames[0]), NULL, 0, 0) == 0,
          "a frame shown for 0 ms is refused");
    CHECK(wpx_animenc_add(writer, frames[0].pixels, pixels_bytes(&frames[0]), NULL, 0, 600001) == 0,
          "a frame shown for over ten minutes is refused");
    CHECK(wpx_animenc_frame_count(writer) == 4 && wpx_animenc_is_valid(writer) == 1, "still four frames");
    n = wpx_animenc_finish(writer);
    CHECK(n > 0 && n == wpx_output_length(), "the animation is written: %d bytes", n);
    file = output_copy();
    CHECK(wpx_animenc_is_valid(writer) == 0 && wpx_animenc_open_count() == 0, "finish closes the writer");
    CHECK(wpx_animenc_finish(writer) == 0 && wpx_animenc_add(writer, frames[0].pixels, pixels_bytes(&frames[0]),
                                                             NULL, 0, 100) == 0
          && wpx_animenc_frame_count(writer) == 0, "a finished writer is dead");

    CHECK(wpx_info_read(file.bytes, file.length) == 1 && wpx_info_is_animated() == 1 && wpx_info_frame_count() == 4
          && wpx_info_loop_count() == 3 && wpx_info_width() == 40 && wpx_info_height() == 30,
          "info of the animation: animated %d frames %d loops %d size %d x %d", wpx_info_is_animated(),
          wpx_info_frame_count(), wpx_info_loop_count(), wpx_info_width(), wpx_info_height());

    reader = wpx_anim_open(file.bytes, file.length);
    CHECK(reader > 0 && wpx_anim_is_valid(reader) == 1 && wpx_anim_open_count() == 1, "the animation opens");
    CHECK(wpx_anim_width(reader) == 40 && wpx_anim_height(reader) == 30 && wpx_anim_frame_count(reader) == 4
          && wpx_anim_loop_count(reader) == 3, "its size, frames and loops");
    CHECK(wpx_anim_frame_index(reader) == 0 && wpx_anim_frame_duration(reader) == 0, "nothing decoded yet");
    for (int pass = 0; pass < 2; pass++) {
        for (i = 0; i < 4; i++) {
            CHECK(wpx_anim_next(reader) == 1, "pass %d frame %d decodes", pass, i + 1);
            CHECK(wpx_anim_frame_index(reader) == i + 1 && wpx_anim_frame_duration(reader) == durations[i],
                  "frame %d: index %d, %d ms", i + 1, wpx_anim_frame_index(reader), wpx_anim_frame_duration(reader));
            /* Each frame replaces the canvas here, so what comes back is the
             * frame that went in (colour compared where it can be seen). */
            CHECK(slot_differs(&frames[i], 0) == 0, "frame %d: %ld pixels differ", i + 1,
                  slot_differs(&frames[i], 0));
        }
        CHECK(wpx_anim_next(reader) == 0 && wpx_last_error()[0] == '\0' && wpx_image_pixels() == NULL,
              "after the last frame: 0, no error, no picture");
        wpx_anim_rewind(reader);
        CHECK(wpx_anim_frame_index(reader) == 0, "rewound");
    }
    /* The file's bytes were copied at open: the reader does not need ours. */
    {
        blob copy = file;
        copy.bytes = (uint8_t *)malloc((size_t)file.length);
        memcpy(copy.bytes, file.bytes, (size_t)file.length);
        memset(file.bytes, 0xAA, (size_t)file.length);
        CHECK(wpx_anim_next(reader) == 1 && slot_differs(&frames[0], 0) == 0,
              "the reader keeps its own copy of the file");
        free(file.bytes);
        file = copy;
    }
    wpx_anim_close(reader);
    CHECK(wpx_anim_is_valid(reader) == 0 && wpx_anim_open_count() == 0, "closed");
    /* A dead handle: getters 0, actions nothing. */
    wpx_anim_close(reader);
    wpx_anim_rewind(reader);
    CHECK(wpx_anim_next(reader) == 0 && wpx_last_error()[0] != '\0', "next on a closed animation is refused");
    CHECK(wpx_anim_width(reader) == 0 && wpx_anim_height(reader) == 0 && wpx_anim_frame_count(reader) == 0
          && wpx_anim_loop_count(reader) == 0 && wpx_anim_frame_index(reader) == 0
          && wpx_anim_frame_duration(reader) == 0, "getters on a closed animation read 0");
    CHECK(wpx_anim_is_valid(0) == 0 && wpx_anim_is_valid(-1) == 0 && wpx_anim_is_valid(0x7FFFFFFF) == 0,
          "0, negative and never-issued handles are invalid");

    /* A plain decode of an animation gives its first frame; a scaled one is refused. */
    CHECK(wpx_decode_image(file.bytes, file.length) == 1 && slot_differs(&frames[0], 0) == 0,
          "decode of an animation is its first frame");
    CHECK(wpx_decode_scaled(file.bytes, file.length, 20, 15) == 0 && strstr(wpx_last_error(), "wpAnimOpen") != NULL,
          "a scaled decode of an animation is refused and says what to use");
    free(file.bytes);

    /* A still picture opens as an animation of one frame. */
    CHECK(wpx_encode_image(frames[1].pixels, pixels_bytes(&frames[1]), frames[1].alpha, alpha_bytes(&frames[1]),
                     40, 30, 75, 1, 4) > 0, "a still");
    file = output_copy();
    reader = wpx_anim_open(file.bytes, file.length);
    CHECK(reader > 0 && wpx_anim_frame_count(reader) == 1 && wpx_anim_next(reader) == 1
          && slot_differs(&frames[1], 0) == 0 && wpx_anim_next(reader) == 0, "a still is one frame");
    wpx_anim_close(reader);
    free(file.bytes);

    /* A lossy animation: frames come back close, in order. */
    writer = wpx_animenc_create(40, 30, 0, 90, 0, 2);
    for (i = 0; i < 3; i++) {
        picture smooth = picture_make(40, 30, 0, 0);
        for (int k = 0; k < 40 * 30; k++) smooth.pixels[k * 4 + 1] = (uint8_t)(i * 100);
        CHECK(wpx_animenc_add(writer, smooth.pixels, pixels_bytes(&smooth), NULL, 0, 40) == 1, "lossy frame %d", i);
        picture_free(&smooth);
    }
    CHECK(wpx_animenc_finish(writer) > 0, "a lossy animation is written");
    file = output_copy();
    reader = wpx_anim_open(file.bytes, file.length);
    CHECK(reader > 0 && wpx_anim_loop_count(reader) == 0 && wpx_anim_frame_count(reader) == 3, "it opens, looping for ever");
    for (i = 0; i < 3; i++) {
        int red = -1;
        if (wpx_anim_next(reader) == 1) red = wpx_image_pixels()[(15 * 40 + 20) * 4 + 1];
        CHECK(red >= i * 100 - 12 && red <= i * 100 + 12, "lossy frame %d: red %d", i, red);
    }
    wpx_anim_close(reader);
    free(file.bytes);

    for (i = 0; i < 4; i++) picture_free(&frames[i]);
}

static void test_handles(void)
{
    picture p = picture_make(8, 8, 1, 0);
    blob file;
    int handles[64];
    int i, again, writer;

    CHECK(wpx_encode_image(p.pixels, pixels_bytes(&p), NULL, 0, 8, 8, 75, 1, 0) > 0, "encode");
    file = output_copy();

    /* Sixty-four readers, and not one more. */
    for (i = 0; i < 64; i++) handles[i] = wpx_anim_open(file.bytes, file.length);
    CHECK(handles[63] > 0 && wpx_anim_open_count() == 64, "64 animations open");
    CHECK(wpx_anim_open(file.bytes, file.length) == 0 && strstr(wpx_last_error(), "wpAnimClose") != NULL,
          "the 65th is refused and says what to do");
    wpx_anim_close(handles[10]);
    again = wpx_anim_open(file.bytes, file.length);
    CHECK(again > 0 && again != handles[10] && wpx_anim_is_valid(handles[10]) == 0 && wpx_anim_is_valid(again) == 1,
          "a reused slot gives a new handle and the old one stays dead");
    handles[10] = again;
    for (i = 0; i < 64; i++) wpx_anim_close(handles[i]);
    CHECK(wpx_anim_open_count() == 0, "all closed");
    /* Churn one slot far past a small generation counter: every old handle
     * stays dead. */
    again = 0;
    for (i = 0; i < 3000; i++) {
        int h = wpx_anim_open(file.bytes, file.length);
        if (h <= 0 || (again != 0 && wpx_anim_is_valid(again))) {
            CHECK(0, "churn %d: handle %d, previous still valid", i, h);
            break;
        }
        wpx_anim_close(h);
        again = h;
    }
    CHECK(wpx_anim_open_count() == 0, "churn leaves nothing open");

    /* The same for writers. */
    for (i = 0; i < 64; i++) handles[i] = wpx_animenc_create(8, 8, 0, 75, 0, 0);
    CHECK(handles[63] > 0 && wpx_animenc_open_count() == 64, "64 writers");
    CHECK(wpx_animenc_create(8, 8, 0, 75, 0, 0) == 0, "the 65th writer is refused");
    for (i = 0; i < 64; i++) wpx_animenc_discard(handles[i]);
    CHECK(wpx_animenc_open_count() == 0 && wpx_animenc_is_valid(handles[0]) == 0, "all discarded");
    wpx_animenc_discard(handles[0]);
    wpx_animenc_discard(0);

    /* Writer refusals. */
    CHECK(wpx_animenc_create(0, 8, 0, 75, 0, 0) == 0 && wpx_animenc_create(8, 16384, 0, 75, 0, 0) == 0,
          "a writer of a size WebP cannot hold");
    CHECK(wpx_animenc_create(8, 8, -1, 75, 0, 0) == 0 && wpx_animenc_create(8, 8, 65536, 75, 0, 0) == 0,
          "a loop count out of range");
    CHECK(wpx_animenc_create(8, 8, 0, 101, 0, 0) == 0 && wpx_animenc_create(8, 8, 0, 75, 0, 9) == 0,
          "writer settings out of range");
    writer = wpx_animenc_create(8, 8, 0, 75, 0, 0);
    CHECK(writer > 0 && wpx_animenc_finish(writer) == 0 && strstr(wpx_last_error(), "no frames") != NULL
          && wpx_animenc_is_valid(writer) == 0 && wpx_animenc_open_count() == 0,
          "finishing with no frames is refused and closes the writer");
    /* A reader handle is not a writer handle, and the other way round. */
    writer = wpx_animenc_create(8, 8, 0, 75, 0, 0);
    again = wpx_anim_open(file.bytes, file.length);
    CHECK(wpx_anim_next(writer) == 0 || writer == again, "a writer handle does not read");
    wpx_animenc_discard(writer);
    wpx_anim_close(again);
    CHECK(wpx_anim_open_count() == 0 && wpx_animenc_open_count() == 0, "nothing left open");
    free(file.bytes);
    picture_free(&p);
}

/* A file written once and kept here: the same bytes must decode to the same
 * picture on every platform and compiler this library is built for. (Written
 * by this test's own encoder, libwebp 1.6.0, on 2026-11-20: a 3 x 2 lossless
 * picture with one clear pixel.) */
static void test_known_file(void)
{
#include "known_file.inc"
    CHECK(wpx_decode_image(k_known_file, (int)sizeof k_known_file) == 1, "the known file decodes");
    CHECK(wpx_image_width() == 3 && wpx_image_height() == 2, "it is 3 x 2");
    CHECK(wpx_image_pixels_length() == (int)sizeof k_known_pixels
          && memcmp(wpx_image_pixels(), k_known_pixels, sizeof k_known_pixels) == 0, "its pixels are the recorded ones");
    CHECK(wpx_image_alpha_length() == (int)sizeof k_known_alpha
          && memcmp(wpx_image_alpha(), k_known_alpha, sizeof k_known_alpha) == 0, "its alpha is the recorded one");
}

int main(int argc, char **argv)
{
    /* `--write-known` prints tests/known_file.inc (see test_known_file). */
    if (argc > 1 && strcmp(argv[1], "--write-known") == 0) {
        static const uint8_t pixels[24] = {
            0, 255, 0, 0,   0, 0, 255, 0,   0, 0, 0, 255,
            0, 12, 34, 56,  0, 255, 255, 255,  0, 0, 0, 0,
        };
        static const uint8_t alpha[6] = { 255, 128, 0, 255, 1, 254 };
        int n = wpx_encode_image(pixels, 24, alpha, 6, 3, 2, 100, 1, 6);
        if (n <= 0 || wpx_decode_image(wpx_output_bytes(), n) != 1) return 1;
        printf("/* GENERATED by `webpxt_smoke --write-known`. Do not edit. */\n");
        printf("static const uint8_t k_known_file[%d] = {", n);
        for (int i = 0; i < n; i++) printf("%s%u,", i % 16 == 0 ? "\n    " : " ", wpx_output_bytes()[i]);
        printf("\n};\nstatic const uint8_t k_known_pixels[24] = {");
        for (int i = 0; i < 24; i++) printf("%s%u,", i % 12 == 0 ? "\n    " : " ", wpx_image_pixels()[i]);
        printf("\n};\nstatic const uint8_t k_known_alpha[6] = {\n   ");
        for (int i = 0; i < 6; i++) printf(" %u,", wpx_image_alpha()[i]);
        printf("\n};\n");
        return 0;
    }
    test_library();
    test_lossless();
    test_lossy();
    test_scaled();
    test_refusals();
    test_pixel_cap();
    test_animation();
    test_handles();
    test_known_file();
    wpx_image_release();
    wpx_output_release();
    printf("webpxt smoke: %d checks, %d failed (%s)\n", s_checks, s_failed, wpx_library_version());
    return s_failed == 0 ? 0 : 1;
}
