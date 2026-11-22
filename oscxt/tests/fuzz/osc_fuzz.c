/*
 * osc_fuzz.c -- fuzz the OSC parser: untrusted network bytes in, no crash out.
 *
 * osc_parse() is the one oscxt entry point that eats bytes straight off the
 * network, and the shim's whole safety story (validate_message's bounds-safe
 * pre-scan, whose proven offsets are the only ones the decoder reads) is only
 * as good as the inputs it has seen. ShowControl's CHANGELOG records an
 * earlier 5M-datagram adversarial run; this file makes that a standing,
 * repeatable gate.
 *
 * Two ways to build it:
 *   * libFuzzer (coverage-guided; native-oscxt.yml's fuzz job, clang), from
 *     the member root:
 *       clang -g -O1 -fsanitize=fuzzer,address,undefined -DOSCXT_LIBFUZZER \
 *             -D_DEFAULT_SOURCE -Isrc -Isrc/third_party/tinyosc -Itests \
 *             src/osc_shim.c src/third_party/tinyosc/tinyosc.c tests/fuzz/osc_fuzz.c
 *       ./a.out -max_total_time=60
 *   * standalone (any compiler, MSVC included; registered with ctest as
 *     osc_fuzz): a deterministic mutation fuzzer seeded from the shared vectors
 *     (tests/vectors/vectors.h). Same seed -> same inputs, so a failure always
 *     reproduces. Under the ASan/UBSan CI build every iteration is checked.
 *       osc_fuzz [iterations] [seed]          (defaults: 200000, 1)
 *       osc_fuzz --replay FILE                (one input: a dumped or libFuzzer crash file)
 *     With OSC_FUZZ_DUMP_AT=N in the environment, iteration N's input is written
 *     to osc-fuzz-N.bin before it runs -- bisect the count to the first crash,
 *     dump it, then --replay it under a debugger.
 *
 * Every parse that succeeds is then walked through EVERY getter -- strings via
 * both the caller-buffer and the convenience forms, blobs, 64-bit decimals,
 * nested bundles -- because an OOB read hides in the accessors as easily as in
 * the parser.
 */
#include "osc_shim.h"
#include "vectors/vectors.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void walk(int32_t h, int depth) {
    static char s[4096];
    static uint8_t b[1 << 16];
    if (!h || depth > 70) return;
    if (osc_is_bundle(h)) {
        osc_bundle_timetag_str(h, s, sizeof s);
        (void) osc_bundle_timetag_z(h);
        int32_t n = osc_bundle_count(h);
        for (int32_t i = 0; i < n; i++) walk(osc_bundle_message(h, i), depth + 1);
        return;
    }
    osc_address(h, s, sizeof s);
    osc_typetag(h, s, sizeof s);
    (void) osc_address_str(h);
    (void) osc_typetag_str(h);
    int32_t argc = osc_arg_count(h);
    for (int32_t i = -1; i <= argc; i++) {        /* include out-of-range indices */
        int32_t ok;
        (void) osc_arg_type(h, i);
        (void) osc_arg_int32(h, i, &ok);
        (void) osc_arg_int64(h, i, &ok);
        (void) osc_arg_float(h, i, &ok);
        (void) osc_arg_double(h, i, &ok);
        (void) osc_arg_timetag(h, i, &ok);
        osc_arg_string(h, i, s, sizeof s);
        osc_arg_string(h, i, s, 1);              /* the too-small path */
        osc_arg_int64_str(h, i, s, sizeof s);
        (void) osc_arg_string_z(h, i);
        (void) osc_arg_int64_z(h, i);
        osc_arg_blob(h, i, b, sizeof b);
        osc_arg_blob(h, i, NULL, 0);
    }
}

static void one_input(const uint8_t *data, size_t size) {
    if (size > (1u << 20)) return;
    int32_t h = osc_parse(data, (int32_t) size);
    walk(h, 0);
    osc_parse_free(h);
    osc_parse_free(h);                            /* a stale handle must be a no-op */
    /* The address-pattern matcher eats network strings too: split the input
     * into two bounded NUL-terminated strings and match them both ways. */
    char p[256], a[256];
    size_t half = size / 2;
    size_t pl = half < sizeof p - 1 ? half : sizeof p - 1;
    size_t al = (size - half) < sizeof a - 1 ? (size - half) : sizeof a - 1;
    memcpy(p, data, pl); p[pl] = '\0';
    memcpy(a, data + half, al); a[al] = '\0';
    (void) osc_match(p, a);
    (void) osc_match(a, p);
}

#ifdef OSCXT_LIBFUZZER

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
    one_input(data, size);
    return 0;
}

#else /* standalone deterministic mutation fuzzer */

static uint64_t g_rng;
static uint32_t rnd(void) {                       /* xorshift64*: fixed seed -> fixed stream */
    g_rng ^= g_rng >> 12; g_rng ^= g_rng << 25; g_rng ^= g_rng >> 27;
    return (uint32_t)((g_rng * 2685821657736338717ULL) >> 32);
}

#define MAXSEEDS 128
static uint8_t *g_seed[MAXSEEDS];
static size_t   g_seedlen[MAXSEEDS];
static int      g_nseeds = 0;

static int hexval(char c) {
    return (c >= '0' && c <= '9') ? c - '0' : (c >= 'a' && c <= 'f') ? c - 'a' + 10 : -1;
}
static void add_seed_hex(const char *h) {
    if (g_nseeds >= MAXSEEDS) return;
    size_t n = strlen(h) / 2;
    uint8_t *b = (uint8_t *) malloc(n ? n : 1);
    for (size_t i = 0; i < n; i++) b[i] = (uint8_t)(hexval(h[2*i]) * 16 + hexval(h[2*i+1]));
    g_seed[g_nseeds] = b; g_seedlen[g_nseeds] = n; g_nseeds++;
}

static size_t mutate(uint8_t *buf, size_t len, size_t cap) {
    int rounds = 1 + (int)(rnd() % 6);
    for (int r = 0; r < rounds; r++) {
        uint32_t op = rnd() % 9;
        size_t pos = len ? rnd() % len : 0;
        switch (op) {
            case 0: if (len) buf[pos] ^= (uint8_t)(1u << (rnd() % 8)); break;           /* bit flip */
            case 1: if (len) buf[pos] = (uint8_t) rnd(); break;                         /* byte set */
            case 2: if (len) buf[pos] = (uint8_t)("\0/,#ifsbhdtTFNI[]{}*?!-"[rnd() % 23]); break;
            case 3: if (len < cap) { memmove(buf + pos + 1, buf + pos, len - pos); buf[pos] = (uint8_t) rnd(); len++; } break;
            case 4: if (len) { memmove(buf + pos, buf + pos + 1, len - pos - 1); len--; } break;
            case 5: len = len ? rnd() % (len + 1) : 0; break;                          /* truncate */
            case 6: if (len >= 4) {                                                    /* hostile size field */
                        static const uint32_t ev[] = { 0, 1, 3, 4, 0x7fffffffu, 0x80000000u, 0xffffffffu, 0x7ffffffcu, 0x10000u };
                        size_t at = (rnd() % (len / 4)) * 4; uint32_t v = ev[rnd() % 9];
                        buf[at] = (uint8_t)(v >> 24); buf[at+1] = (uint8_t)(v >> 16); buf[at+2] = (uint8_t)(v >> 8); buf[at+3] = (uint8_t) v;
                    } break;
            case 7: { int s = (int)(rnd() % g_nseeds); size_t n = g_seedlen[s];         /* splice another seed */
                      if (len + n <= cap) { memcpy(buf + len, g_seed[s], n); len += n; } } break;
            case 8: len &= ~(size_t) 3; break;                                          /* realign to 4 */
        }
    }
    return len;
}

static int replay(const char *path) {
    FILE *f = fopen(path, "rb");
    if (!f) { printf("cannot open %s\n", path); return 2; }
    static uint8_t b[1 << 20];
    size_t n = fread(b, 1, sizeof b, f);
    fclose(f);
    one_input(b, n);
    printf("replayed %zu bytes from %s -- no crash\n", n, path);
    return 0;
}

int main(int argc, char **argv) {
    if (argc > 2 && strcmp(argv[1], "--replay") == 0) return replay(argv[2]);
    long iters = argc > 1 ? atol(argv[1]) : 200000;
    const char *dump_env = getenv("OSC_FUZZ_DUMP_AT");
    long dump_at = dump_env ? atol(dump_env) : -1;
    g_rng = (uint64_t)(argc > 2 ? atoll(argv[2]) : 1) * 0x9E3779B97F4A7C15ULL + 1;
    for (int k = 0; k < SCV_COUNT(SCV_OSC_MESSAGES); k++) add_seed_hex(SCV_OSC_MESSAGES[k].hex);
    for (int k = 0; k < SCV_COUNT(SCV_OSC_BUNDLES); k++)  add_seed_hex(SCV_OSC_BUNDLES[k].hex);
    for (int k = 0; k < SCV_COUNT(SCV_OSC_MALFORMED); k++) add_seed_hex(SCV_OSC_MALFORMED[k].hex);

    static uint8_t buf[1 << 17];
    long parsed = 0;
    for (long i = 0; i < iters; i++) {
        int s = (int)(rnd() % g_nseeds);
        size_t len = g_seedlen[s];
        memcpy(buf, g_seed[s], len);
        len = mutate(buf, len, sizeof buf);
        if (i + 1 == dump_at) {
            char name[64];
            snprintf(name, sizeof name, "osc-fuzz-%ld.bin", dump_at);
            FILE *f = fopen(name, "wb");
            if (f) { fwrite(buf, 1, len, f); fclose(f); printf("dumped iteration %ld (%zu bytes) to %s\n", dump_at, len, name); }
            fflush(stdout);
        }
        int32_t h = osc_parse(buf, (int32_t) len);
        if (h) parsed++;
        osc_parse_free(h);
        one_input(buf, len);
    }
    /* the seeds themselves must still parse/reject exactly as the vectors say */
    for (int k = 0; k < SCV_COUNT(SCV_OSC_MESSAGES); k++) {
        int32_t h = osc_parse(g_seed[k], (int32_t) g_seedlen[k]);
        if (!h) { printf("FAIL: vector message %d no longer parses\n", k); return 1; }
        osc_parse_free(h);
    }
    printf("osc fuzz: %ld mutated datagrams (%ld parsed, %ld rejected cleanly), %d seeds -- no crash\n",
           iters, parsed, iters - parsed, g_nseeds);
    for (int k = 0; k < g_nseeds; k++) free(g_seed[k]);
    return 0;
}

#endif
