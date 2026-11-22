/*
 * osc_vectors_test.c -- the shared OSC wire-format vectors, through the C shim.
 *
 * tests/vectors/osc.json is the single source of truth (proven against
 * clean-room spec encoders and python-osc by tests/vectors_reference_test.py).
 * tools/gen_vectors.py projects it into tests/vectors/vectors.h, which this test
 * walks: every message is BUILT through the same *_str entry points the LCB
 * binding uses and compared byte-for-byte, every message and bundle is PARSED
 * back, every pattern is MATCHED, and every malformed datagram must be a clean
 * error. The headless LCB suite asserts the same vectors through the binding.
 */
#include "osc_shim.h"
#include "vectors/vectors.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

static int g_pass = 0, g_fail = 0;
static void check(const char *what, const char *name, int ok) {
    if (ok) { g_pass++; return; }
    g_fail++;
    printf("  [FAIL] %s: %s\n", what, name);
}

static int hexval(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}
/* Decode hex into out (cap bytes); returns the byte count, or -1 if too big/bad. */
static int32_t unhex(const char *h, uint8_t *out, int32_t cap) {
    size_t n = strlen(h);
    if (n % 2 || (int32_t)(n / 2) > cap) return -1;
    for (size_t i = 0; i < n; i += 2) {
        int a = hexval(h[i]), b = hexval(h[i + 1]);
        if (a < 0 || b < 0) return -1;
        out[i / 2] = (uint8_t)(a * 16 + b);
    }
    return (int32_t)(n / 2);
}
static void tohex(const uint8_t *b, int32_t n, char *out) {
    static const char d[] = "0123456789abcdef";
    for (int32_t i = 0; i < n; i++) { out[2*i] = d[b[i] >> 4]; out[2*i+1] = d[b[i] & 15]; }
    out[2*n] = '\0';
}

static uint8_t g_buf[1 << 16], g_tmp[1 << 16];
static char g_hex[(1 << 17) + 1];

static void check_parse(const scv_osc_msg *m) {
    static uint8_t buf[1 << 16];
    int32_t len = unhex(m->hex, buf, sizeof buf);
    int32_t p = osc_parse(buf, len);
    check("parse handle", m->name, p != 0);
    char s[512];
    osc_address(p, s, sizeof s);
    check("parse address", m->name, strcmp(s, m->address) == 0);
    check("parse argc", m->name, osc_arg_count(p) == m->argc);
    for (int a = 0; a < m->argc && a < osc_arg_count(p); a++) {
        const scv_arg *g = &m->args[a];
        int32_t ok = 0;
        check("parse arg type", m->name, osc_arg_type(p, a) == g->type);
        switch (g->type) {
            case 'i': check("parse int32", m->name, osc_arg_int32(p, a, &ok) == (int32_t) strtol(g->value, NULL, 10)); break;
            case 'f': { double want = (double)(float) strtod(g->value, NULL);
                        check("parse float", m->name, fabs((double) osc_arg_float(p, a, &ok) - want) < 1e-9); break; }
            case 'd': check("parse double", m->name, osc_arg_double(p, a, &ok) == strtod(g->value, NULL)); break;
            case 'h': case 't': osc_arg_int64_str(p, a, s, sizeof s);
                      check("parse 64-bit as decimal", m->name, strcmp(s, g->value) == 0); break;
            case 's': osc_arg_string(p, a, s, sizeof s);
                      check("parse string", m->name, strcmp(s, g->value) == 0); break;
            case 'b': { int32_t bn = osc_arg_blob(p, a, g_tmp, sizeof g_tmp);
                        tohex(g_tmp, bn > 0 ? bn : 0, g_hex);
                        check("parse blob", m->name, strcmp(g_hex, g->value) == 0); break; }
            default: break;
        }
    }
    osc_parse_free(p);
}

/* Datagrams our encoder never emits -- e.g. a ',' hidden in the address padding,
 * which once desynchronized tinyosc's cursor from the validated layout (an OOB
 * blob read; the fuzz crash). They must parse by the spec's layout. */
static void test_parse_only(void) {
    for (int k = 0; k < SCV_COUNT(SCV_OSC_PARSE_ONLY); k++) check_parse(&SCV_OSC_PARSE_ONLY[k]);
}

static void test_build_and_parse(void) {
    for (int k = 0; k < SCV_COUNT(SCV_OSC_MESSAGES); k++) {
        const scv_osc_msg *m = &SCV_OSC_MESSAGES[k];
        int32_t h = osc_build_new(m->address);
        for (int a = 0; a < m->argc; a++) {
            const scv_arg *g = &m->args[a];
            switch (g->type) {
                case 'i': osc_build_add_int32_str(h, g->value); break;
                case 'f': osc_build_add_float_str(h, g->value); break;
                case 'd': osc_build_add_double_str(h, g->value); break;
                case 'h': osc_build_add_int64_str(h, g->value); break;
                case 't': osc_build_add_timetag_str(h, g->value); break;
                case 's': osc_build_add_string(h, g->value); break;
                case 'b': { int32_t n = unhex(g->value, g_tmp, sizeof g_tmp);
                            osc_build_add_blob(h, n > 0 ? g_tmp : NULL, n > 0 ? n : 0); break; }
                case 'T': osc_build_add_true(h); break;
                case 'F': osc_build_add_false(h); break;
                case 'N': osc_build_add_nil(h); break;
                case 'I': osc_build_add_impulse(h); break;
            }
        }
        int32_t n = osc_build_finish(h, g_buf, sizeof g_buf);
        osc_build_free(h);
        tohex(g_buf, n > 0 ? n : 0, g_hex);
        check("build bytes", m->name, n > 0 && strcmp(g_hex, m->hex) == 0);
        if (n <= 0 || strcmp(g_hex, m->hex) != 0)
            printf("         got  %s\n         want %s\n", g_hex, m->hex);

        /* parse the vector's own bytes (not ours) */
        int32_t len = unhex(m->hex, g_buf, sizeof g_buf);
        int32_t p = osc_parse(g_buf, len);
        check("parse handle", m->name, p != 0);
        char s[512];
        osc_address(p, s, sizeof s);
        check("parse address", m->name, strcmp(s, m->address) == 0);
        check("parse argc", m->name, osc_arg_count(p) == m->argc);
        for (int a = 0; a < m->argc && a < osc_arg_count(p); a++) {
            const scv_arg *g = &m->args[a];
            int32_t ok = 0;
            check("parse arg type", m->name, osc_arg_type(p, a) == g->type);
            switch (g->type) {
                case 'i': check("parse int32", m->name, osc_arg_int32(p, a, &ok) == (int32_t) strtol(g->value, NULL, 10)); break;
                case 'f': { double want = (double)(float) strtod(g->value, NULL);
                            check("parse float", m->name, fabs((double) osc_arg_float(p, a, &ok) - want) < 1e-9); break; }
                case 'd': check("parse double", m->name, osc_arg_double(p, a, &ok) == strtod(g->value, NULL)); break;
                case 'h': case 't': osc_arg_int64_str(p, a, s, sizeof s);
                          check("parse 64-bit as decimal", m->name, strcmp(s, g->value) == 0); break;
                case 's': osc_arg_string(p, a, s, sizeof s);
                          check("parse string", m->name, strcmp(s, g->value) == 0); break;
                case 'b': { int32_t bn = osc_arg_blob(p, a, g_tmp, sizeof g_tmp);
                            tohex(g_tmp, bn > 0 ? bn : 0, g_hex);
                            check("parse blob", m->name, strcmp(g_hex, g->value) == 0); break; }
                default: break;
            }
        }
        osc_parse_free(p);
    }
}

static void test_bundles(void) {
    for (int k = 0; k < SCV_COUNT(SCV_OSC_BUNDLES); k++) {
        const scv_osc_bundle *b = &SCV_OSC_BUNDLES[k];
        int32_t h = osc_bundle_new_str(b->timetag);
        for (int e = 0; e < b->count; e++) {
            int32_t n = unhex(b->elems[e], g_tmp, sizeof g_tmp);
            osc_bundle_add_message(h, g_tmp, n);
        }
        int32_t n = osc_bundle_finish(h, g_buf, sizeof g_buf);
        osc_bundle_free(h);
        tohex(g_buf, n > 0 ? n : 0, g_hex);
        check("bundle bytes", b->name, n > 0 && strcmp(g_hex, b->hex) == 0);
        int32_t len = unhex(b->hex, g_buf, sizeof g_buf);
        int32_t p = osc_parse(g_buf, len);
        char s[64];
        osc_bundle_timetag_str(p, s, sizeof s);
        check("bundle parses", b->name, p != 0 && osc_is_bundle(p) == 1);
        check("bundle timetag", b->name, strcmp(s, b->timetag) == 0);
        check("bundle count", b->name, osc_bundle_count(p) == b->count);
        osc_parse_free(p);
    }
}

static void test_matches(void) {
    for (int k = 0; k < SCV_COUNT(SCV_OSC_MATCHES); k++) {
        const scv_osc_match *m = &SCV_OSC_MATCHES[k];
        check("match", m->pattern, osc_match(m->pattern, m->address) == m->match);
    }
}

static void test_malformed(void) {
    for (int k = 0; k < SCV_COUNT(SCV_OSC_MALFORMED); k++) {
        const scv_named_hex *m = &SCV_OSC_MALFORMED[k];
        int32_t len = unhex(m->hex, g_buf, sizeof g_buf);
        int32_t p = osc_parse(len > 0 ? g_buf : NULL, len > 0 ? len : 0);
        char e[256];
        osc_last_error(e, sizeof e);
        check("malformed rejected", m->name, p == 0);
        check("malformed sets an error", m->name, e[0] != '\0');
        if (p) osc_parse_free(p);
    }
}

int main(void) {
    test_build_and_parse();
    test_parse_only();
    test_bundles();
    test_matches();
    test_malformed();
    printf("osc vectors: %d passed, %d failed\n", g_pass, g_fail);
    /* a floor, so a vectors.h that silently lost its tables cannot pass */
    if (g_pass < 200) { printf("FAIL: only %d checks ran (floor 200)\n", g_pass); return 1; }
    return g_fail == 0 ? 0 : 1;
}
