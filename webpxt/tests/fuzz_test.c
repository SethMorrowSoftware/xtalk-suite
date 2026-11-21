/*
 * fuzz_test.c - damaged files and random calls against the webpxt shim.
 *
 * A WebP file is whatever a stranger sent. This test makes real files with
 * the library's own encoder (still and animated, lossy and lossless, with
 * and without alpha), damages them (flipped bytes, cut tails, spliced
 * halves, runs overwritten) and hands each to every reading export; between
 * files it calls every other export with arguments drawn at random,
 * including handles that were never issued. What it holds:
 *
 *   - nothing crashes, reads out of bounds or leaks (the lane runs it under
 *     ASan/UBSan, where each of those ends the run);
 *   - a decode that says 1 left a picture whose buffers are exactly the
 *     size its width and height mean, and every byte of them is readable;
 *   - a refused call left an explanation;
 *   - at the end nothing is open and both result slots are empty.
 *
 *     webpxt_fuzz [seed [iterations]]      one seed
 *     webpxt_fuzz                          seeds 1 to 3, 1500 iterations each
 *
 * The same seed gives the same run on every platform (its own generator, no
 * rand()).
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

extern const char *wpx_library_version(void);
extern const char *wpx_last_error(void);
extern int wpx_info_read(const uint8_t *data, int length);
extern int wpx_info_width(void);
extern int wpx_info_height(void);
extern int wpx_info_frame_count(void);
extern int wpx_decode_image(const uint8_t *data, int length);
extern int wpx_decode_scaled(const uint8_t *data, int length, int width, int height);
extern int wpx_image_width(void);
extern int wpx_image_height(void);
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

static uint32_t s_rng;

static uint32_t rnd(void)
{
    s_rng ^= s_rng << 13;
    s_rng ^= s_rng >> 17;
    s_rng ^= s_rng << 5;
    return s_rng;
}

static int rnd_in(int low, int high)        /* inclusive */
{
    return low + (int)(rnd() % (uint32_t)(high - low + 1));
}

static void fail(const char *what, long iteration)
{
    printf("FAIL webpxt fuzz: %s (iteration %ld) [last error: %s]\n", what, iteration, wpx_last_error());
    exit(1);
}

#define SEEDS 6
#define SEED_MAX 65536
static uint8_t s_seed[SEEDS][SEED_MAX];
static int s_seedLength[SEEDS];

static uint8_t s_pixels[96 * 96 * 4];
static uint8_t s_alpha[96 * 96];

static void noise_picture(int width, int height)
{
    for (int i = 0; i < width * height; i++) {
        uint32_t v = rnd();
        s_pixels[i * 4] = 0;
        s_pixels[i * 4 + 1] = (uint8_t)(v & 0xFF);
        s_pixels[i * 4 + 2] = (uint8_t)((i % width) * 3);
        s_pixels[i * 4 + 3] = (uint8_t)((v >> 16) & 0xFF);
        s_alpha[i] = (uint8_t)((v >> 24) | (i % 3 == 0 ? 0xFF : 0));
    }
}

static void keep_output(int which, long iteration)
{
    int n = wpx_output_length();
    if (n <= 0 || n > SEED_MAX) fail("a seed file could not be made", iteration);
    memcpy(s_seed[which], wpx_output_bytes(), (size_t)n);
    s_seedLength[which] = n;
}

/* The files that get damaged: made fresh for each seed. */
static void make_seeds(void)
{
    int writer;
    noise_picture(48, 32);
    if (wpx_encode_image(s_pixels, 48 * 32 * 4, s_alpha, 48 * 32, 48, 32, 70, 0, 2) <= 0) fail("seed 0", -1);
    keep_output(0, -1);
    if (wpx_encode_image(s_pixels, 48 * 32 * 4, NULL, 0, 48, 32, 40, 0, 0) <= 0) fail("seed 1", -1);
    keep_output(1, -1);
    noise_picture(24, 24);
    if (wpx_encode_image(s_pixels, 24 * 24 * 4, s_alpha, 24 * 24, 24, 24, 50, 1, 2) <= 0) fail("seed 2", -1);
    keep_output(2, -1);
    if (wpx_encode_image(s_pixels, 24 * 24 * 4, NULL, 0, 24, 24, 50, 1, 0) <= 0) fail("seed 3", -1);
    keep_output(3, -1);
    for (int kind = 0; kind < 2; kind++) {
        writer = wpx_animenc_create(20, 16, kind, 60, kind, 1);
        for (int frame = 0; frame < 4; frame++) {
            noise_picture(20, 16);
            if (wpx_animenc_add(writer, s_pixels, 20 * 16 * 4, frame % 2 ? s_alpha : NULL, frame % 2 ? 20 * 16 : 0,
                                rnd_in(1, 500)) != 1) fail("seed animation frame", -1);
        }
        if (wpx_animenc_finish(writer) <= 0) fail("seed animation", -1);
        keep_output(4 + kind, -1);
    }
}

static uint8_t s_file[SEED_MAX + 64];

static int damaged_file(void)
{
    int which = rnd_in(0, SEEDS - 1);
    int length = s_seedLength[which];
    memcpy(s_file, s_seed[which], (size_t)length);
    switch (rnd_in(0, 6)) {
    case 0:     /* a few flipped bits */
        for (int k = rnd_in(1, 8); k > 0; k--) s_file[rnd_in(0, length - 1)] ^= (uint8_t)(1u << rnd_in(0, 7));
        break;
    case 1:     /* a few bytes replaced */
        for (int k = rnd_in(1, 12); k > 0; k--) s_file[rnd_in(0, length - 1)] = (uint8_t)rnd();
        break;
    case 2:     /* cut short */
        length = rnd_in(0, length);
        break;
    case 3: {   /* a run overwritten with one value */
        int at = rnd_in(0, length - 1);
        int run = rnd_in(1, 64);
        uint8_t value = (uint8_t)(rnd_in(0, 3) == 0 ? 0xFF : rnd());
        for (int k = 0; k < run && at + k < length; k++) s_file[at + k] = value;
        break;
    }
    case 4: {   /* the tail of another file spliced on */
        int other = rnd_in(0, SEEDS - 1);
        int at = rnd_in(0, length);
        int from = rnd_in(0, s_seedLength[other]);
        int take = s_seedLength[other] - from;
        if (at + take > SEED_MAX) take = SEED_MAX - at;
        memcpy(s_file + at, s_seed[other] + from, (size_t)take);
        length = at + take;
        break;
    }
    case 5:     /* damage in the first 40 bytes, where the sizes are */
        for (int k = rnd_in(1, 4); k > 0; k--) s_file[rnd_in(0, length < 40 ? length - 1 : 39)] = (uint8_t)rnd();
        break;
    default:    /* left whole: the readers must also keep working */
        break;
    }
    return length;
}

/* A decode said 1: the slot must be what its size says, and readable. */
static void audit_picture(long iteration)
{
    int width = wpx_image_width();
    int height = wpx_image_height();
    const uint8_t *pixels = wpx_image_pixels();
    const uint8_t *alpha = wpx_image_alpha();
    unsigned sum = 0;
    if (width < 1 || height < 1 || width > 16383 || height > 16383) fail("a decoded size out of range", iteration);
    if (pixels == NULL || alpha == NULL) fail("a decode said 1 and left no buffer", iteration);
    if (wpx_image_pixels_length() != width * height * 4 || wpx_image_alpha_length() != width * height)
        fail("buffer lengths that do not match the size", iteration);
    for (int i = 0; i < width * height * 4; i++) sum += pixels[i];
    for (int i = 0; i < width * height; i++) sum += alpha[i];
    (void)sum;
}

static void read_everything(const uint8_t *file, int length, long iteration)
{
    int reader;
    if (wpx_info_read(file, length) == 0 && wpx_last_error()[0] == '\0' && length > 0)
        fail("info refused a file and left no explanation", iteration);
    if (wpx_decode_image(file, length) == 1) audit_picture(iteration);
    else if (wpx_last_error()[0] == '\0') fail("decode refused a file and left no explanation", iteration);
    if (wpx_decode_scaled(file, length, rnd_in(-2, 120), rnd_in(-2, 120)) == 1) audit_picture(iteration);
    reader = wpx_anim_open(file, length);
    if (reader != 0) {
        int frames = wpx_anim_frame_count(reader);
        if (wpx_anim_width(reader) < 1 || wpx_anim_height(reader) < 1) fail("an open animation with no size", iteration);
        for (int k = 0; k < 12 && k <= frames; k++) {
            if (wpx_anim_next(reader) == 1) {
                audit_picture(iteration);
                if (wpx_anim_frame_index(reader) < 1 || wpx_anim_frame_duration(reader) < 0)
                    fail("a decoded frame with no index", iteration);
            }
            if (rnd_in(0, 9) == 0) wpx_anim_rewind(reader);
        }
        (void)wpx_anim_loop_count(reader);
        wpx_anim_close(reader);
        if (wpx_anim_is_valid(reader)) fail("a closed animation is still valid", iteration);
    }
}

/* Any export, any argument. Sizes are kept small so the run is fast; the
 * buffers passed are always at least as long as the LENGTH passed, which is
 * the one promise the binding makes. */
static void random_call(long iteration)
{
    int width = rnd_in(-1, 40);
    int height = rnd_in(-1, 40);
    int handle = rnd_in(0, 4) == 0 ? (int)rnd() : rnd_in(-1, 600);
    int pixelsLength = rnd_in(0, 3) == 0 ? rnd_in(0, 96 * 96 * 4) : width * height * 4;
    int alphaLength = rnd_in(0, 2) == 0 ? 0 : (rnd_in(0, 3) == 0 ? rnd_in(0, 96 * 96) : width * height);
    double quality = rnd_in(0, 9) == 0 ? (double)rnd_in(-50, 200) : (double)rnd_in(0, 100);
    int effort = rnd_in(0, 9) == 0 ? rnd_in(-3, 9) : rnd_in(0, 3);
    if (pixelsLength < 0) pixelsLength = 0;
    if (alphaLength < 0) alphaLength = 0;
    switch (rnd_in(0, 7)) {
    case 0:
        if (wpx_encode_image(s_pixels, pixelsLength, s_alpha, alphaLength, width, height, quality, rnd_in(0, 1), effort) > 0) {
            if (wpx_decode_image(wpx_output_bytes(), wpx_output_length()) != 1) fail("a file just written does not decode", iteration);
            audit_picture(iteration);
            if (wpx_image_width() != width || wpx_image_height() != height) fail("a round trip changed the size", iteration);
        }
        break;
    case 1: {
        int writer = wpx_animenc_create(width, height, rnd_in(-1, 5), quality, rnd_in(0, 1), effort);
        if (writer != 0) {
            int frames = rnd_in(0, 3);
            for (int k = 0; k < frames; k++) {
                (void)wpx_animenc_add(writer, s_pixels, pixelsLength, s_alpha, alphaLength, rnd_in(-1, 300));
            }
            if (rnd_in(0, 3) == 0) {
                wpx_animenc_discard(writer);
            } else if (wpx_animenc_finish(writer) > 0) {
                read_everything(wpx_output_bytes(), wpx_output_length(), iteration);
            }
            if (wpx_animenc_is_valid(writer)) fail("a finished writer is still valid", iteration);
        }
        break;
    }
    case 2:
        (void)wpx_anim_next(handle);
        (void)wpx_anim_width(handle);
        (void)wpx_anim_height(handle);
        (void)wpx_anim_frame_count(handle);
        (void)wpx_anim_loop_count(handle);
        (void)wpx_anim_frame_index(handle);
        (void)wpx_anim_frame_duration(handle);
        wpx_anim_rewind(handle);
        wpx_anim_close(handle);
        break;
    case 3:
        (void)wpx_animenc_add(handle, s_pixels, pixelsLength, s_alpha, alphaLength, 50);
        (void)wpx_animenc_frame_count(handle);
        (void)wpx_animenc_finish(handle);
        wpx_animenc_discard(handle);
        break;
    case 4:
        wpx_image_release();
        wpx_output_release();
        if (wpx_image_pixels() != NULL || wpx_output_bytes() != NULL) fail("a released slot is not empty", iteration);
        break;
    case 5:
        (void)wpx_info_width();
        (void)wpx_info_height();
        (void)wpx_info_frame_count();
        break;
    default:
        break;
    }
}

static void run_seed(uint32_t seed, long iterations)
{
    s_rng = seed * 2654435761u + 0x9E3779B9u;
    if (s_rng == 0) s_rng = 1;
    make_seeds();
    for (long i = 0; i < iterations; i++) {
        int length = damaged_file();
        read_everything(s_file, length, i);
        random_call(i);
    }
    wpx_image_release();
    wpx_output_release();
    if (wpx_anim_open_count() != 0 || wpx_animenc_open_count() != 0) fail("something was left open", iterations);
    printf("webpxt fuzz: seed %u, %ld iterations, clean\n", (unsigned)seed, iterations);
}

int main(int argc, char **argv)
{
    long iterations = 1500;
    if (argc > 2) iterations = strtol(argv[2], NULL, 10);
    if (iterations < 1) iterations = 1;
    if (argc > 1) {
        run_seed((uint32_t)strtoul(argv[1], NULL, 10), iterations);
    } else {
        for (uint32_t seed = 1; seed <= 3; seed++) run_seed(seed, iterations);
    }
    printf("webpxt fuzz: clean (%s)\n", wpx_library_version());
    return 0;
}
