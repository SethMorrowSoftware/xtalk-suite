/*
 * osc_shim.c
 * ----------------------------------------------------------------------------
 * The C shim at the heart of ShowControl's OSC extension: an FFI-friendly layer
 * over tinyosc (ISC) for xTalk Builder (LCB), so OpenXTalk / LiveCode-compatible
 * engines can build and parse Open Sound Control messages. Transport (the UDP
 * socket) is owned by the script side -- this shim is a pure, stateless-ish
 * codec (CLAUDE.md, "As built").
 *
 * Two tinyosc problems this shim solves:
 *   1. The write API is variadic -> replaced here with an incremental builder.
 *   2. The read API is cursor-based AND unchecked -> replaced here with a single
 *      BOUNDS-CHECKED pre-scan into an indexed model, so malformed datagrams are
 *      a clean error, never an out-of-bounds read. (We still lean on tinyosc for
 *      the value decode once the structure is proven safe.)
 *
 * Safety: every handle is validated (generation-tagged table) before use, so a
 * stale/0 handle is a harmless no-op. No library-owned `const char*` ever
 * crosses the boundary; all string/byte results fill a caller buffer.
 *
 * Build: compiled together with tinyosc into ONE shared library named after
 * the member, "oscxt" (oscxt.so / oscxt.dylib / oscxt.dll, no "lib" prefix).
 * See CMakeLists.txt.
 * ----------------------------------------------------------------------------
 */

#include "osc_shim.h"
#include "tinyosc.h"

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <inttypes.h>
#include <stdio.h>
#include <locale.h>
#if defined(__APPLE__)
#include <xlocale.h>       /* newlocale / uselocale / LC_NUMERIC_MASK */
#endif

/* Read a decimal number the way every xTalk engine WRITES one: with a ".".
 * strtod() honours LC_NUMERIC, and an engine that leaves LC_NUMERIC at the
 * user's locale makes it read "0.5" as 0 (and "1.5" as 1) on a machine whose
 * decimal mark is a comma: engines before OXT-Beyond's own fix did exactly
 * that on Linux, and on a Mac started from a terminal (OXT-Beyond's
 * engine/src/dsklnx.cpp and dskmac.cpp now pin LC_NUMERIC to "C" for this
 * reason; LiveCode 9.6.3 and OXT 9.7 do not). So the shim parses in the "C"
 * locale whatever the process's locale is: a "0,5" is read as 0 everywhere,
 * as it already was on every machine with a "." locale. tests/osc_smoke_test.c
 * proves it under a comma locale. */
static double strtod_c(const char *s) {
#if defined(_WIN32)
    static _locale_t c_loc = NULL;
    if (!c_loc) c_loc = _create_locale(LC_NUMERIC, "C");
    if (c_loc) return _strtod_l(s, NULL, c_loc);
    return strtod(s, NULL);
#else
    static locale_t c_loc = (locale_t) 0;
    if (!c_loc) c_loc = newlocale(LC_NUMERIC_MASK, "C", (locale_t) 0);
    if (c_loc) {
        locale_t old = uselocale(c_loc);
        double v = strtod(s, NULL);
        if (old) uselocale(old);
        return v;
    }
    return strtod(s, NULL);
#endif
}

/* ===================================================================== */
/* Last-error string (module-global; the LCB layer exposes oscLastError). */
/* ===================================================================== */
static char g_err[256];

static void err_clear(void) { g_err[0] = '\0'; }
static void err_set(const char *m) {
    if (!m) { g_err[0] = '\0'; return; }
    size_t n = strlen(m);
    if (n >= sizeof g_err) n = sizeof g_err - 1;
    memcpy(g_err, m, n);
    g_err[n] = '\0';
}

/* Copy a NUL-terminated string into a caller buffer using the project-wide
 * convention: return the length (excluding NUL); -needed if it does not fit;
 * always NUL-terminate when at least one byte of room exists. */
static int32_t copy_str(const char *s, char *out, int32_t cap) {
    int32_t n = (int32_t) strlen(s);
    if (!out || cap <= 0) return -(n + 1);
    if (n + 1 > cap) {
        if (cap > 0) out[0] = '\0';
        return -(n + 1);
    }
    memcpy(out, s, (size_t) n + 1);
    return n;
}

/* ===================================================================== */
/* Portable big-endian store/load (OSC is network byte order throughout).  */
/* ===================================================================== */
static void be32_store(uint8_t *p, uint32_t v) {
    p[0] = (uint8_t)(v >> 24); p[1] = (uint8_t)(v >> 16);
    p[2] = (uint8_t)(v >> 8);  p[3] = (uint8_t)v;
}
static void be64_store(uint8_t *p, uint64_t v) {
    be32_store(p, (uint32_t)(v >> 32));
    be32_store(p + 4, (uint32_t)v);
}
static uint32_t be32_load(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16)
         | ((uint32_t)p[2] << 8)  | (uint32_t)p[3];
}
static uint64_t be64_load(const uint8_t *p) {
    return ((uint64_t)be32_load(p) << 32) | (uint64_t)be32_load(p + 4);
}
static int32_t pad4(int32_t n) { return (n + 3) & ~3; }
/* The same in int64, for size sums that are checked against INT32_MAX AFTER
 * the padding: pad4(INT32_MAX) itself overflows int32. */
static int64_t pad4_64(int64_t n) { return (n + 3) & ~(int64_t)3; }

/* The longest address, string or blob one builder takes. It keeps every size
 * the builders add (+1 NUL, +3 padding, +4 length prefix, +16 bundle header)
 * inside int32 however the arithmetic is ordered; a datagram is at most 64 KB,
 * so nothing real comes near it. */
#define OSC_MAX_FIELD (INT32_MAX - 64)

/* ===================================================================== */
/* Generic generation-tagged handle table (compact form of Box2Dxt's).    */
/* Handle packs an 8-bit generation above a 23-bit slot+1 (never 0).      */
/* ===================================================================== */
#define H_SLOT_BITS 23
#define H_SLOT_MASK 0x7FFFFF
#define H_GEN_MASK  0xFF

#define DEFINE_PTR_TABLE(NAME, TYPE)                                          \
    static TYPE         **NAME##_arr  = NULL;                                 \
    static unsigned char *NAME##_used = NULL;                                 \
    static unsigned char *NAME##_gen  = NULL;                                 \
    static int NAME##_cap = 0, NAME##_cnt = 0;                                \
    static int *NAME##_free = NULL; static int NAME##_freeCap=0,NAME##_freeCnt=0;\
    static int NAME##_grow(int nc) {                                          \
        TYPE **na = (TYPE**)realloc(NAME##_arr, (size_t)nc*sizeof(TYPE*));    \
        if(!na) { return 0; } NAME##_arr = na;                                    \
        unsigned char *nu=(unsigned char*)realloc(NAME##_used,(size_t)nc);    \
        if(!nu) { return 0; } NAME##_used = nu;                                   \
        unsigned char *ng=(unsigned char*)realloc(NAME##_gen,(size_t)nc);     \
        if(!ng) { return 0; } NAME##_gen = ng;                                    \
        memset(NAME##_used+NAME##_cap,0,(size_t)(nc-NAME##_cap));             \
        memset(NAME##_gen +NAME##_cap,0,(size_t)(nc-NAME##_cap));             \
        NAME##_cap = nc; return 1;                                            \
    }                                                                         \
    static int NAME##_encode(int idx){                                        \
        return (int)(((unsigned)NAME##_gen[idx]<<H_SLOT_BITS)|(unsigned)(idx+1));\
    }                                                                         \
    static int NAME##_slot(int h){                                            \
        if(h<=0) return -1;                                                   \
        int idx=(h & H_SLOT_MASK)-1;                                          \
        unsigned gen=((unsigned)h>>H_SLOT_BITS)&H_GEN_MASK;                   \
        if(idx<0||idx>=NAME##_cnt) return -1;                                 \
        if(!NAME##_used[idx]||NAME##_gen[idx]!=gen) return -1;                \
        return idx;                                                           \
    }                                                                         \
    static int NAME##_add(TYPE *v){                                           \
        int idx=-1;                                                           \
        if(NAME##_freeCnt>0) idx=NAME##_free[--NAME##_freeCnt];               \
        if(idx<0){                                                            \
            if(NAME##_cnt>=H_SLOT_MASK-1) return 0;                           \
            if(NAME##_cnt>=NAME##_cap){                                       \
                int nc=NAME##_cap?NAME##_cap*2:32;                            \
                if(!NAME##_grow(nc)) return 0;                                \
            }                                                                 \
            idx=NAME##_cnt++;                                                 \
        }                                                                     \
        NAME##_arr[idx]=v; NAME##_used[idx]=1;                                \
        return NAME##_encode(idx);                                            \
    }                                                                         \
    static TYPE *NAME##_get(int h){                                           \
        int idx=NAME##_slot(h); return idx<0?NULL:NAME##_arr[idx];           \
    }                                                                         \
    static int NAME##_release(int h){                                        \
        int idx=NAME##_slot(h); if(idx<0) return 0;                          \
        NAME##_arr[idx]=NULL; NAME##_used[idx]=0;                            \
        NAME##_gen[idx]=(unsigned char)((NAME##_gen[idx]+1)&H_GEN_MASK);      \
        if(NAME##_freeCnt>=NAME##_freeCap){                                   \
            int nc=NAME##_freeCap?NAME##_freeCap*2:32;                        \
            int *nf=(int*)realloc(NAME##_free,(size_t)nc*sizeof(int));        \
            if(nf){NAME##_free=nf;NAME##_freeCap=nc;}                         \
        }                                                                     \
        if(NAME##_freeCnt<NAME##_freeCap) NAME##_free[NAME##_freeCnt++]=idx;  \
        return 1;                                                             \
    }

/* ===================================================================== */
/* Builder model                                                          */
/* ===================================================================== */
typedef struct {
    char    type;            /* OSC type tag char */
    int64_t i;               /* i/h/t integer payloads */
    double  d;               /* f/d float payloads (stored wide, narrowed at write) */
    uint8_t *bytes;          /* s (with NUL) / b payload, owned */
    int32_t  blen;           /* byte length of `bytes` for blob; strlen for string */
} build_arg;

typedef struct {
    char       *address;     /* owned, NUL-terminated */
    build_arg  *args;
    int32_t     count, cap;
    int         ok;          /* 0 once an append failed (OOM / bad input) */
} builder;

DEFINE_PTR_TABLE(builders, builder)

static builder *builder_of(int32_t h) { return builders_get(h); }

static int builder_reserve(builder *b) {
    if (b->count >= b->cap) {
        int32_t nc = b->cap ? b->cap * 2 : 8;
        build_arg *na = (build_arg*) realloc(b->args, (size_t)nc * sizeof(build_arg));
        if (!na) { b->ok = 0; return 0; }
        b->args = na; b->cap = nc;
    }
    return 1;
}

OSC_API int32_t osc_build_new(const char *address) {
    err_clear();
    if (!address) { err_set("oscBuildMessage: nil address"); return 0; }
    size_t n = strlen(address);
    if (n > (size_t) OSC_MAX_FIELD) { err_set("oscBuildMessage: address too long"); return 0; }
    builder *b = (builder*) calloc(1, sizeof(builder));
    if (!b) { err_set("out of memory"); return 0; }
    b->address = (char*) malloc(n + 1);
    if (!b->address) { free(b); err_set("out of memory"); return 0; }
    memcpy(b->address, address, n + 1);
    b->ok = 1;
    int32_t h = builders_add(b);
    if (!h) { free(b->address); free(b); err_set("handle table full"); return 0; }
    return h;
}

static int32_t build_scalar(int32_t h, char type, int64_t i, double d) {
    builder *b = builder_of(h);
    if (!b) return 0;
    if (!builder_reserve(b)) return 0;
    build_arg *a = &b->args[b->count++];
    memset(a, 0, sizeof *a);
    a->type = type; a->i = i; a->d = d;
    return 1;
}

OSC_API int32_t osc_build_add_int32 (int32_t h, int32_t v){ return build_scalar(h,'i',v,0); }
OSC_API int32_t osc_build_add_int64 (int32_t h, int64_t v){ return build_scalar(h,'h',v,0); }
OSC_API int32_t osc_build_add_float (int32_t h, float v)  { return build_scalar(h,'f',0,(double)v); }
OSC_API int32_t osc_build_add_double(int32_t h, double v) { return build_scalar(h,'d',0,v); }
OSC_API int32_t osc_build_add_true   (int32_t h){ return build_scalar(h,'T',0,0); }
OSC_API int32_t osc_build_add_false  (int32_t h){ return build_scalar(h,'F',0,0); }
OSC_API int32_t osc_build_add_nil    (int32_t h){ return build_scalar(h,'N',0,0); }
OSC_API int32_t osc_build_add_impulse(int32_t h){ return build_scalar(h,'I',0,0); }
OSC_API int32_t osc_build_add_timetag(int32_t h, uint64_t ntp){ return build_scalar(h,'t',(int64_t)ntp,0); }

OSC_API int32_t osc_build_add_int64_str(int32_t h, const char *dec) {
    int64_t v = dec ? (int64_t) strtoll(dec, NULL, 10) : 0;
    return build_scalar(h, 'h', v, 0);
}
/* int32 / float / double also cross as decimal strings. The xTalk engine passes
 * script numbers into a foreign `any` as their STRING form, and LCB will not
 * coerce a decimal string ("0.5") to its Number type on assignment -- so the .lcb
 * stringifies every numeric value and we parse it here, exactly as for int64. */
/* Text outside the int32 range CLAMPS to it, on every platform. This used
 * strtol, whose C long is 32 bits on Windows and 32-bit Linux (where it
 * saturated) but 64 bits on 64-bit Linux and macOS (where the cast then
 * wrapped): "3000000000" sent 2147483647 from one machine and -1294967296
 * from another. strtoll is 64 bits everywhere, and clamping keeps the result
 * those 32-bit-long platforms always gave, the one osc_arg_int32 gives for an
 * out-of-range float. Text that is not a whole number reads as strtoll reads
 * it, as before: "2.7" is 2, "abc" is 0. */
OSC_API int32_t osc_build_add_int32_str(int32_t h, const char *dec) {
    long long v = dec ? strtoll(dec, NULL, 10) : 0;
    if (v > INT32_MAX) v = INT32_MAX;
    else if (v < INT32_MIN) v = INT32_MIN;
    return build_scalar(h, 'i', (int64_t) v, 0);
}
OSC_API int32_t osc_build_add_float_str(int32_t h, const char *dec) {
    double v = dec ? strtod_c(dec) : 0.0;
    return build_scalar(h, 'f', 0, v);
}
OSC_API int32_t osc_build_add_double_str(int32_t h, const char *dec) {
    double v = dec ? strtod_c(dec) : 0.0;
    return build_scalar(h, 'd', 0, v);
}
OSC_API int32_t osc_build_add_timetag_str(int32_t h, const char *dec) {
    uint64_t v = dec ? (uint64_t) strtoull(dec, NULL, 10) : 0;
    return build_scalar(h, 't', (int64_t) v, 0);
}

OSC_API int32_t osc_build_add_string(int32_t h, const char *v) {
    builder *b = builder_of(h);
    if (!b) return 0;
    if (!v) v = "";
    size_t sn = strlen(v);
    if (sn > (size_t) OSC_MAX_FIELD) { b->ok = 0; return 0; }
    if (!builder_reserve(b)) return 0;
    build_arg *a = &b->args[b->count++];
    memset(a, 0, sizeof *a);
    a->type = 's';
    int32_t n = (int32_t) sn;
    a->bytes = (uint8_t*) malloc((size_t)n + 1);
    if (!a->bytes) { b->count--; b->ok = 0; return 0; }
    memcpy(a->bytes, v, (size_t)n + 1);
    a->blen = n;
    return 1;
}

OSC_API int32_t osc_build_add_blob(int32_t h, const uint8_t *data, int32_t len) {
    builder *b = builder_of(h);
    if (!b) return 0;
    if (len < 0) len = 0;
    if (len > OSC_MAX_FIELD) { b->ok = 0; return 0; }
    if (!builder_reserve(b)) return 0;
    build_arg *a = &b->args[b->count++];
    memset(a, 0, sizeof *a);
    a->type = 'b';
    a->bytes = (uint8_t*) malloc((size_t)(len > 0 ? len : 1));
    if (!a->bytes) { b->count--; b->ok = 0; return 0; }
    if (len > 0 && data) memcpy(a->bytes, data, (size_t)len);
    a->blen = len;
    return 1;
}

/* Compute the exact serialized size of the current builder, or -1 on bad model
 * (unknown type, or a total that would overflow int32). Accumulate in int64 so a
 * pathological pile of args cannot wrap the running sum and make osc_build_finish's
 * `out_cap < need` test pass against a too-small buffer. */
static int32_t builder_size(builder *b) {
    int64_t sz = pad4_64((int64_t) strlen(b->address) + 1);   /* address + NUL, padded */
    sz += pad4_64((int64_t) b->count + 2);                     /* ',' + tags + NUL, padded */
    for (int32_t k = 0; k < b->count; k++) {
        build_arg *a = &b->args[k];
        switch (a->type) {
            case 'i': case 'f': sz += 4; break;
            case 'h': case 'd': case 't': sz += 8; break;
            case 's': sz += pad4_64((int64_t) a->blen + 1); break;
            case 'b': sz += 4 + pad4_64(a->blen); break;
            case 'T': case 'F': case 'N': case 'I': break;
            default: return -1;
        }
        if (sz > INT32_MAX) return -1;
    }
    return (int32_t) sz;
}

OSC_API int32_t osc_build_finish(int32_t h, uint8_t *out, int32_t out_cap) {
    err_clear();
    builder *b = builder_of(h);
    if (!b) { err_set("oscBuildMessage: bad builder handle"); return 0; }
    if (!b->ok) { err_set("oscBuildMessage: builder in error state (OOM?)"); return 0; }
    int32_t need = builder_size(b);
    if (need < 0) { err_set("oscBuildMessage: bad argument type"); return 0; }
    if (!out || out_cap < need) return -need;

    memset(out, 0, (size_t)need);
    int32_t i = 0;
    int32_t alen = (int32_t) strlen(b->address);
    memcpy(out + i, b->address, (size_t)alen);
    i = pad4(alen + 1);

    out[i++] = ',';
    for (int32_t k = 0; k < b->count; k++) out[i++] = (uint8_t) b->args[k].type;
    /* The type-tag string MUST be NUL-terminated, then padded to a multiple of 4.
     * pad4(i+1) (not pad4(i)) guarantees at least one NUL even when ','+tags is
     * itself a multiple of 4 (i.e. argCount % 4 == 3); the memset above already
     * zeroed the padding. The old pad4(i) left a 3/7/11/...-arg message with NO
     * type-tag terminator, so the args ran into the tag region and it failed to
     * parse. builder_size already reserves pad4(count+2), so this never overruns. */
    i = pad4(i + 1);

    for (int32_t k = 0; k < b->count; k++) {
        build_arg *a = &b->args[k];
        switch (a->type) {
            case 'i': be32_store(out + i, (uint32_t)(int32_t)a->i); i += 4; break;
            case 'h': be64_store(out + i, (uint64_t)a->i); i += 8; break;
            case 't': be64_store(out + i, (uint64_t)a->i); i += 8; break;
            case 'f': { float f = (float)a->d; uint32_t bits; memcpy(&bits,&f,4);
                        be32_store(out + i, bits); i += 4; break; }
            case 'd': { double dd = a->d; uint64_t bits; memcpy(&bits,&dd,8);
                        be64_store(out + i, bits); i += 8; break; }
            case 's': { memcpy(out + i, a->bytes, (size_t)a->blen);
                        i = pad4(i + a->blen + 1); break; }
            case 'b': { be32_store(out + i, (uint32_t)a->blen); i += 4;
                        if (a->blen) memcpy(out + i, a->bytes, (size_t)a->blen);
                        i = pad4(i + a->blen); break; }
            default: break; /* T F N I: tag only */
        }
    }
    return need;
}

static void builder_destroy(builder *b) {
    if (!b) return;
    for (int32_t k = 0; k < b->count; k++) free(b->args[k].bytes);
    free(b->args); free(b->address); free(b);
}

OSC_API void osc_build_free(int32_t h) {
    builder *b = builder_of(h);
    if (b) { builders_release(h); builder_destroy(b); }
}

/* ===================================================================== */
/* Bundle builder: a growable byte buffer assembled from finished messages.*/
/* ===================================================================== */
typedef struct {
    uint8_t *buf;
    int32_t  len, cap;
    uint64_t timetag;
    int      ok;
} bundle_builder;

DEFINE_PTR_TABLE(bundles, bundle_builder)

static int bundle_reserve(bundle_builder *b, int32_t extra) {
    /* All size math in int64 so a hostile/huge `extra` cannot overflow int32 and
     * wrap the capacity test (which would skip the realloc and let the caller
     * write past the buffer). The capacity stays a sane int32. */
    if (extra < 0) { b->ok = 0; return 0; }
    int64_t need = (int64_t) b->len + extra;
    if (need > INT32_MAX) { b->ok = 0; return 0; }
    if (need > b->cap) {
        int64_t nc = b->cap ? (int64_t) b->cap * 2 : 64;
        while (nc < need) nc *= 2;
        if (nc > INT32_MAX) nc = INT32_MAX;
        uint8_t *nb = (uint8_t*) realloc(b->buf, (size_t)nc);
        if (!nb) { b->ok = 0; return 0; }
        b->buf = nb; b->cap = (int32_t) nc;
    }
    return 1;
}

OSC_API int32_t osc_bundle_new(uint64_t timetag) {
    err_clear();
    bundle_builder *b = (bundle_builder*) calloc(1, sizeof(bundle_builder));
    if (!b) { err_set("out of memory"); return 0; }
    b->timetag = timetag; b->ok = 1;
    int32_t h = bundles_add(b);
    if (!h) { free(b); err_set("handle table full"); return 0; }
    return h;
}
OSC_API int32_t osc_bundle_new_str(const char *dec) {
    uint64_t t = (dec && dec[0]) ? (uint64_t) strtoull(dec, NULL, 10) : 1u;
    return osc_bundle_new(t);
}

OSC_API int32_t osc_bundle_add_message(int32_t h, const uint8_t *msg, int32_t len) {
    bundle_builder *b = bundles_get(h);
    if (!b) return 0;
    if (len < 0 || !msg) { b->ok = 0; return 0; }
    /* Bound the element so 4+len (the size prefix + payload) and the running total
     * cannot overflow int32. Without this, a len near INT32_MAX wraps 4+len negative,
     * the reserve is skipped, and the memcpy below writes through an unsized buffer.
     * The bound leaves room for osc_bundle_finish's 16-byte header too: at
     * INT32_MAX it let b->len reach a size where `16 + b->len` wrapped negative,
     * and a caller's buffer then passed the `out_cap < need` test and was
     * overrun by the header and every element. */
    if ((int64_t) b->len + 4 + len > (int64_t) INT32_MAX - 16) {
        b->ok = 0; err_set("oscBuildBundle: bundle too large"); return 0;
    }
    if (!bundle_reserve(b, 4 + len)) return 0;
    be32_store(b->buf + b->len, (uint32_t)len);   /* element size prefix */
    b->len += 4;
    memcpy(b->buf + b->len, msg, (size_t)len);
    b->len += len;
    return 1;
}

OSC_API int32_t osc_bundle_finish(int32_t h, uint8_t *out, int32_t out_cap) {
    err_clear();
    bundle_builder *b = bundles_get(h);
    if (!b) { err_set("oscBuildBundle: bad handle"); return 0; }
    if (!b->ok) { err_set("oscBuildBundle: bundle in error state"); return 0; }
    int32_t need = 16 + b->len;                   /* "#bundle\0" + timetag + elements */
    if (!out || out_cap < need) return -need;
    memcpy(out, "#bundle", 7); out[7] = '\0';
    be64_store(out + 8, b->timetag);
    if (b->len) memcpy(out + 16, b->buf, (size_t)b->len);
    return need;
}

OSC_API void osc_bundle_free(int32_t h) {
    bundle_builder *b = bundles_get(h);
    if (b) { bundles_release(h); free(b->buf); free(b); }
}

/* ===================================================================== */
/* Parsed model: a bounds-checked indexed view of a datagram.             */
/* ===================================================================== */
typedef struct {
    char     type;
    int64_t  i;        /* i/h/t */
    double   d;        /* f/d */
    int32_t  off;      /* s/b: offset into owned `data` */
    int32_t  len;      /* s/b: byte length (string excludes the NUL) */
} parsed_arg;

typedef struct parsed_msg {
    int          is_bundle;
    uint64_t     timetag;
    /* message: */
    uint8_t     *data;        /* owned copy of this message's bytes */
    int32_t      data_len;
    char        *address;     /* points into data */
    char        *typetag;     /* malloc'd "fsi" (no comma), NUL-terminated */
    parsed_arg  *args;
    int32_t      argc;
    /* bundle: */
    int32_t     *children;    /* handles of sub-messages */
    int32_t      child_count;
} parsed_msg;

DEFINE_PTR_TABLE(parsed, parsed_msg)

/* Forward decls */
/* Cap bundle nesting. Each level recurses parse_depth->parse_bundle_bytes->
 * parse_depth (and parsed_destroy frees recursively), so an unbounded nest is a
 * stack-overflow DoS from a single datagram. 64 is far beyond any real bundle. */
#define OSC_MAX_BUNDLE_DEPTH 64
static int32_t parse_depth(const uint8_t *data, int32_t len, int depth);
static int32_t parse_message_bytes(const uint8_t *data, int32_t len);
static int32_t parse_bundle_bytes(const uint8_t *data, int32_t len, int depth);
static void parsed_destroy(int32_t h);

/* Internal dispatch carrying the bundle-nesting depth. osc_parse is the public
 * entry that resets the error state and starts the recursion at depth 0. */
static int32_t parse_depth(const uint8_t *data, int32_t len, int depth) {
    if (!data || len < 4) { err_set("oscParse: datagram too short"); return 0; }
    if (len & 3) { err_set("oscParse: length not a multiple of 4"); return 0; }
    if (len >= 8 && memcmp(data, "#bundle", 7) == 0 && data[7] == '\0')
        return parse_bundle_bytes(data, len, depth);
    if (data[0] != '/') { err_set("oscParse: address must start with '/'"); return 0; }
    return parse_message_bytes(data, len);
}

OSC_API int32_t osc_parse(const uint8_t *data, int32_t len) {
    err_clear();
    return parse_depth(data, len, 0);
}

/* ---------------------------------------------------------------------------
 * Bounds-safe VALIDATOR. tinyosc's cursor reader (tosc_getNext*) does NOT
 * bounds-check, which is unacceptable for untrusted network input. So before
 * we let tinyosc touch a datagram we prove, here, that every field lies inside
 * `len`. On success it reports the type-tag span so the caller can size its
 * model; tinyosc then does the actual decode over already-proven-safe bytes.
 * Returns 0 on success (filling the tt_start, ntags and arg_pos outs), else -1.
 * ------------------------------------------------------------------------- */
static int validate_message(const uint8_t *data, int32_t len,
                            int32_t *tt_start, int32_t *ntags, int32_t *arg_pos) {
    int32_t i = 0;
    while (i < len && data[i] != '\0') i++;                 /* address NUL */
    if (i >= len) { err_set("oscParse: address not terminated"); return -1; }
    i = pad4(i + 1);
    if (i >= len || data[i] != ',') { err_set("oscParse: missing type tag"); return -1; }
    int32_t ts = i + 1, j = ts;
    while (j < len && data[j] != '\0') j++;                 /* type tag NUL */
    if (j >= len) { err_set("oscParse: type tag not terminated"); return -1; }
    int32_t nt = j - ts;
    int32_t p = pad4(j + 1);
    if (p > len) { err_set("oscParse: truncated after type tag"); return -1; }

    for (int32_t k = 0; k < nt; k++) {
        switch (data[ts + k]) {
            case 'i': case 'f':
                if (4 > len - p) { goto trunc; } p += 4; break;   /* len-p>=0; avoids p+4 overflow */
            case 'h': case 't': case 'd':
                if (8 > len - p) { goto trunc; } p += 8; break;
            case 's': {
                int32_t s = p;
                while (p < len && data[p] != '\0') p++;
                if (p >= len) goto trunc;
                p = pad4(p + 1);
                if (p > len) goto trunc;
                (void) s; break; }
            case 'b': {
                if (4 > len - p) goto trunc;
                int32_t bl = (int32_t) be32_load(data + p);
                /* len-p-4 >= 0 (just checked 4 <= len-p), so this can't overflow;
                 * the old `p + 4 + bl > len` overflows int32 for bl near INT32_MAX
                 * and ACCEPTS the blob -> a 2GB OOB read on the 32-bit targets. */
                if (bl < 0 || bl > len - p - 4) goto trunc;
                p = pad4(p + 4 + bl);
                if (p > len) goto trunc;
                break; }
            case 'T': case 'F': case 'N': case 'I':
                break;
            default:
                err_set("oscParse: unknown type tag"); return -1;
        }
    }
    *tt_start = ts; *ntags = nt; *arg_pos = pad4(j + 1);
    return 0;
trunc:
    err_set("oscParse: truncated / malformed argument data");
    return -1;
}

/* Validate, then DECODE through tinyosc into the indexed model. */
static int32_t parse_message_bytes(const uint8_t *data, int32_t len) {
    int32_t tt_start = 0, ntags = 0, arg_pos = 0;
    if (validate_message(data, len, &tt_start, &ntags, &arg_pos) != 0)
        return 0;

    parsed_msg *m = (parsed_msg*) calloc(1, sizeof(parsed_msg));
    if (!m) { err_set("out of memory"); return 0; }
    m->data = (uint8_t*) malloc((size_t)len);
    m->typetag = (char*) malloc((size_t)ntags + 1);
    m->args = ntags ? (parsed_arg*) calloc((size_t)ntags, sizeof(parsed_arg)) : NULL;
    if (!m->data || !m->typetag || (ntags && !m->args)) {
        free(m->data); free(m->typetag); free(m->args); free(m);
        err_set("out of memory"); return 0;
    }
    memcpy(m->data, data, (size_t)len);
    m->data_len = len;
    m->address = (char*) m->data;
    memcpy(m->typetag, data + tt_start, (size_t)ntags);
    m->typetag[ntags] = '\0';

    /* Decode every value at the offsets validate_message PROVED -- never through
     * tinyosc's cursor. tinyosc's tosc_parseMessage locates the type tag by
     * scanning for the first ',' after the address NUL, so a ',' hidden in the
     * address PADDING (OSC says those bytes are NUL; a hostile sender need not
     * comply) puts tinyosc's argument cursor inside the type-tag string. The old
     * code then read values from tinyosc's offsets while trusting OUR validated
     * layout: a blob length landed on garbage and osc_arg_blob read out of
     * bounds -- a remote crash from one 72-byte datagram, found by
     * tests/fuzz/osc_fuzz.c (seed 7, iteration 360207) and pinned in the vectors.
     * One parser, one interpretation: walk the same offsets the validator did. */
    {
        int32_t p = arg_pos;
        for (int32_t k = 0; k < ntags; k++) {
            char t = m->typetag[k];
            parsed_arg *a = &m->args[k];
            const uint8_t *q = m->data + p;
            a->type = t;
            switch (t) {
                case 'i': a->i = (int32_t) be32_load(q); p += 4; break;
                case 'f': { uint32_t bits = be32_load(q); float f;
                            memcpy(&f, &bits, 4); a->d = (double) f; p += 4; break; }
                case 'h': a->i = (int64_t) be64_load(q); p += 8; break;
                case 't': a->i = (int64_t) be64_load(q); p += 8; break;
                case 'd': { uint64_t bits = be64_load(q); double d;
                            memcpy(&d, &bits, 8); a->d = d; p += 8; break; }
                case 's': {
                    /* validate_message proved a NUL inside the datagram */
                    a->off = p;
                    a->len = (int32_t) strlen((const char *) q);
                    p = pad4(p + a->len + 1);
                    break; }
                case 'b': {
                    int32_t bl = (int32_t) be32_load(q);   /* proved 0 <= bl <= len-p-4 */
                    a->off = p + 4;
                    a->len = bl;
                    p = pad4(p + 4 + bl);
                    break; }
                default: break; /* T F N I carry no bytes */
            }
        }
    }
    m->argc = ntags;
    m->is_bundle = 0;

    int32_t h = parsed_add(m);
    if (!h) { free(m->data); free(m->typetag); free(m->args); free(m);
              err_set("handle table full"); return 0; }
    return h;
}

/* Validate + index a bundle, recursing into its elements. */
static int32_t parse_bundle_bytes(const uint8_t *data, int32_t len, int depth) {
    if (depth >= OSC_MAX_BUNDLE_DEPTH) { err_set("oscParse: bundle nesting too deep"); return 0; }
    if (len < 16) { err_set("oscParse: bundle too short"); return 0; }
    parsed_msg *m = (parsed_msg*) calloc(1, sizeof(parsed_msg));
    if (!m) { err_set("out of memory"); return 0; }
    m->is_bundle = 1;
    m->timetag = be64_load(data + 8);

    int32_t cap = 0;
    int32_t p = 16;
    while (p <= len - 4) {                            /* len>=16, so len-4>=12; p<=len holds */
        int32_t elen = (int32_t) be32_load(data + p);
        p += 4;
        /* p <= len here, so len-p >= 0. The old `p + elen > len` overflows int32
         * for an attacker-chosen huge elen and ACCEPTS the element -> heap OOB read
         * in the recursive parse. Compare as elen > len-p to avoid the overflow. */
        if (elen < 0 || elen > len - p) { err_set("oscParse: bad bundle element size"); goto bad; }
        int32_t child = parse_depth(data + p, elen, depth + 1);   /* recurse, depth-capped */
        if (!child) goto bad;                          /* err already set */
        if (m->child_count >= cap) {
            int32_t nc = cap ? cap * 2 : 4;
            int32_t *nn = (int32_t*) realloc(m->children, (size_t)nc * sizeof(int32_t));
            if (!nn) { osc_parse_free(child); err_set("out of memory"); goto bad; }
            m->children = nn; cap = nc;
        }
        m->children[m->child_count++] = child;
        p += elen;
    }
    {
        int32_t h = parsed_add(m);
        if (!h) { err_set("handle table full"); goto bad; }
        return h;
    }
bad:
    for (int32_t k = 0; k < m->child_count; k++) osc_parse_free(m->children[k]);
    free(m->children); free(m);
    return 0;
}

OSC_API int32_t osc_is_bundle(int32_t h) {
    parsed_msg *m = parsed_get(h); return m ? m->is_bundle : 0;
}
OSC_API uint64_t osc_bundle_timetag(int32_t h) {
    parsed_msg *m = parsed_get(h); return (m && m->is_bundle) ? m->timetag : 0;
}
OSC_API int32_t osc_bundle_count(int32_t h) {
    parsed_msg *m = parsed_get(h); return (m && m->is_bundle) ? m->child_count : 0;
}
OSC_API int32_t osc_bundle_message(int32_t h, int32_t i) {
    parsed_msg *m = parsed_get(h);
    if (!m || !m->is_bundle || i < 0 || i >= m->child_count) return 0;
    return m->children[i];
}

OSC_API int32_t osc_address(int32_t h, char *out, int32_t out_cap) {
    parsed_msg *m = parsed_get(h);
    if (!m || m->is_bundle || !m->address) { if (out && out_cap>0) out[0]='\0'; return 0; }
    return copy_str(m->address, out, out_cap);
}
OSC_API int32_t osc_typetag(int32_t h, char *out, int32_t out_cap) {
    parsed_msg *m = parsed_get(h);
    if (!m || m->is_bundle || !m->typetag) { if (out && out_cap>0) out[0]='\0'; return 0; }
    return copy_str(m->typetag, out, out_cap);
}
OSC_API int32_t osc_arg_count(int32_t h) {
    parsed_msg *m = parsed_get(h); return (m && !m->is_bundle) ? m->argc : 0;
}
OSC_API int32_t osc_arg_type(int32_t h, int32_t i) {
    parsed_msg *m = parsed_get(h);
    if (!m || m->is_bundle || i < 0 || i >= m->argc) return 0;
    return (int32_t)(unsigned char) m->args[i].type;
}

static parsed_arg *arg_at(int32_t h, int32_t i) {
    parsed_msg *m = parsed_get(h);
    if (!m || m->is_bundle || i < 0 || i >= m->argc) return NULL;
    return &m->args[i];
}

/* Saturating double->int32. A parsed OSC float/double comes off the network, so a
 * value outside the int32 range is expected, not exceptional -- and the bare cast
 * `(int32_t)d` for such a value is UNDEFINED BEHAVIOUR in C (C11 6.3.1.4), which a
 * float-cast-overflow build flags and which can trap or be miscompiled on some
 * targets. Clamp to the int32 range (NaN -> 0) so the coercion is always defined.
 * INT32_MIN/MAX are exactly representable as double, so the bounds are exact. */
static int32_t d_to_i32(double d) {
    if (d != d) return 0;                       /* NaN */
    if (d >= 2147483647.0)  return 2147483647;  /* INT32_MAX */
    if (d <= -2147483648.0) return -2147483647 - 1; /* INT32_MIN (no 2147483648 literal) */
    return (int32_t) d;
}

OSC_API int32_t osc_arg_int32(int32_t h, int32_t i, int32_t *ok) {
    parsed_arg *a = arg_at(h, i);
    if (a && (a->type=='i' || a->type=='h')) { if(ok)*ok=1; return (int32_t)a->i; }
    if (a && (a->type=='f' || a->type=='d')) { if(ok)*ok=1; return d_to_i32(a->d); }
    if (ok) { *ok = 0; } return 0;
}
OSC_API int64_t osc_arg_int64(int32_t h, int32_t i, int32_t *ok) {
    parsed_arg *a = arg_at(h, i);
    if (a && (a->type=='i' || a->type=='h' || a->type=='t')) { if(ok)*ok=1; return a->i; }
    if (ok) { *ok = 0; } return 0;
}
OSC_API float osc_arg_float(int32_t h, int32_t i, int32_t *ok) {
    parsed_arg *a = arg_at(h, i);
    if (a && (a->type=='f' || a->type=='d')) { if(ok)*ok=1; return (float)a->d; }
    if (a && (a->type=='i' || a->type=='h')) { if(ok)*ok=1; return (float)a->i; }
    if (ok) { *ok = 0; } return 0.0f;
}
OSC_API double osc_arg_double(int32_t h, int32_t i, int32_t *ok) {
    parsed_arg *a = arg_at(h, i);
    if (a && (a->type=='f' || a->type=='d')) { if(ok)*ok=1; return a->d; }
    if (a && (a->type=='i' || a->type=='h')) { if(ok)*ok=1; return (double)a->i; }
    if (ok) { *ok = 0; } return 0.0;
}
OSC_API uint64_t osc_arg_timetag(int32_t h, int32_t i, int32_t *ok) {
    parsed_arg *a = arg_at(h, i);
    if (a && (a->type=='t' || a->type=='h')) { if(ok)*ok=1; return (uint64_t)a->i; }
    if (ok) { *ok = 0; } return 0;
}
OSC_API int32_t osc_arg_string(int32_t h, int32_t i, char *out, int32_t out_cap) {
    parsed_arg *a = arg_at(h, i);
    parsed_msg *m = parsed_get(h);
    if (!a || a->type != 's') return -1;
    int32_t n = a->len;
    if (!out || out_cap < n + 1) {
        if (out && out_cap > 0) out[0] = '\0';   /* match copy_str: NUL-terminate on too-small */
        return -(n + 1);
    }
    memcpy(out, m->data + a->off, (size_t)n);
    out[n] = '\0';
    return n;
}
OSC_API int32_t osc_arg_blob(int32_t h, int32_t i, uint8_t *out, int32_t out_cap) {
    parsed_arg *a = arg_at(h, i);
    parsed_msg *m = parsed_get(h);
    if (!a || a->type != 'b') return -1;
    int32_t n = a->len;
    if (!out || out_cap < n) return -n;
    if (n) memcpy(out, m->data + a->off, (size_t)n);
    return n;
}

OSC_API int32_t osc_arg_int64_str(int32_t h, int32_t i, char *out, int32_t out_cap) {
    parsed_arg *a = arg_at(h, i);
    if (!a || (a->type != 'h' && a->type != 'i' && a->type != 't')) return -1;
    char tmp[24];
    /* A timetag ('t') is UNSIGNED NTP-64; int64 ('h') / int32 ('i') are signed.
     * Every NTP timetag since ~1968 has the top bit set, so formatting a "now"
     * value as signed would read back as a large negative number. */
    if (a->type == 't') snprintf(tmp, sizeof tmp, "%" PRIu64, (uint64_t) a->i);
    else                snprintf(tmp, sizeof tmp, "%" PRId64, a->i);
    return copy_str(tmp, out, out_cap);
}
OSC_API int32_t osc_bundle_timetag_str(int32_t h, char *out, int32_t out_cap) {
    parsed_msg *m = parsed_get(h);
    if (!m || !m->is_bundle) return -1;
    char tmp[24];
    snprintf(tmp, sizeof tmp, "%" PRIu64, m->timetag);
    return copy_str(tmp, out, out_cap);
}

static void parsed_destroy(int32_t h) {
    parsed_msg *m = parsed_get(h);
    if (!m) return;
    parsed_release(h);
    for (int32_t k = 0; k < m->child_count; k++) parsed_destroy(m->children[k]);
    free(m->children);
    free(m->args);
    free(m->typetag);
    free(m->data);
    free(m);
}
OSC_API void osc_parse_free(int32_t h) { parsed_destroy(h); }

/* ===================================================================== */
/* OSC 1.0 address pattern matching: ? * [ ] [!] [a-z] { , }              */
/* Reference grammar from the OSC 1.0 spec, recursive matcher.            */
/* ===================================================================== */
/* ReDoS guard: the recursive '*' matcher is exponential for patterns with several
 * stars (a hostile address/pattern hangs the engine's run loop). Bound the total
 * step count -- generous for any real OSC address, fatal to a pathological one.
 * The engine is single-threaded (the project's no-callback rule), so a module
 * global reset per osc_match call is safe. */
static long g_match_steps = 0;
/* Stack guard: the step budget bounds the WORK, not the DEPTH. Each '*' and
 * each '{...}' along a path recurses once, and "{,}" consumes no address
 * characters, so one 64 KB datagram carrying "{,}{,}{,}..." as its address
 * (the incoming address is the PATTERN in an OSC server) recursed ~21,000
 * frames deep: a segfault on a 1 MB stack, which is a Windows main thread's.
 * No real pattern nests 256 wildcards. */
#define OSC_MATCH_MAX_DEPTH 256
static int match_here(const char *p, const char *s, int depth);

/* match a [ ... ] character class at p (p points just after '[') against s[0] */
static int match_class(const char **pp, char c) {
    const char *p = *pp;
    int negate = 0, matched = 0;
    if (*p == '!') { negate = 1; p++; }
    while (*p && *p != ']') {
        if (p[1] == '-' && p[2] && p[2] != ']') {
            char lo = p[0], hi = p[2];
            if ((unsigned char)c >= (unsigned char)lo && (unsigned char)c <= (unsigned char)hi) matched = 1;
            p += 3;
        } else {
            if (*p == c) matched = 1;
            p++;
        }
    }
    if (*p == ']') p++;
    *pp = p;
    return negate ? !matched : matched;
}

/* match a { a, bb, ccc } alternation at p (p points just after '{') */
static int match_alt(const char *p, const char *s, const char **p_after, int depth) {
    /* find the matching close brace to know where the pattern resumes */
    const char *q = p; int open = 1;
    while (*q && open) { if (*q=='{') open++; else if (*q=='}') open--; if (open) q++; }
    const char *after = (*q == '}') ? q + 1 : q;   /* pattern continues after '}' */
    *p_after = after;

    const char *opt = p;
    while (opt < q) {
        const char *e = opt;
        while (e < q && *e != ',') e++;
        int32_t L = (int32_t)(e - opt);
        if (strncmp(s, opt, (size_t)L) == 0 && match_here(after, s + L, depth + 1)) return 1;
        opt = (e < q) ? e + 1 : e;
    }
    return 0;
}

static int match_here(const char *p, const char *s, int depth) {
    if (--g_match_steps < 0) return 0;        /* ReDoS guard (see g_match_steps) */
    if (depth > OSC_MATCH_MAX_DEPTH) return 0; /* stack guard (see OSC_MATCH_MAX_DEPTH) */
    while (*p) {
        if (*p == '?') {
            if (*s == '\0' || *s == '/') return 0;
            p++; s++;
        } else if (*p == '*') {
            p++;
            while (*p == '*') p++;            /* collapse a run of '*' (a**b == a*b) */
            if (*p == '\0') {                 /* trailing star: match to end of segment */
                while (*s && *s != '/') s++;
                return *s == '\0';
            }
            for (;;) {
                if (match_here(p, s, depth + 1)) return 1;
                if (*s == '\0' || *s == '/') return 0;
                s++;
            }
        } else if (*p == '[') {
            p++;
            if (*s == '\0' || *s == '/') return 0;
            if (!match_class(&p, *s)) return 0;
            s++;
        } else if (*p == '{') {
            const char *after;
            return match_alt(p + 1, s, &after, depth);
        } else {
            if (*p != *s) return 0;
            p++; s++;
        }
    }
    return *s == '\0';
}

OSC_API int32_t osc_match(const char *pattern, const char *address) {
    if (!pattern || !address) return 0;
    g_match_steps = 2000000;   /* see g_match_steps; real matches use a few hundred */
    return match_here(pattern, address, 0) ? 1 : 0;
}

/* ---- ZStringUTF8 convenience accessors (model-owned lifetime) ---------- */
OSC_API const char *osc_address_str(int32_t h) {
    parsed_msg *m = parsed_get(h);
    return (m && !m->is_bundle && m->address) ? m->address : "";
}
OSC_API const char *osc_typetag_str(int32_t h) {
    parsed_msg *m = parsed_get(h);
    return (m && !m->is_bundle && m->typetag) ? m->typetag : "";
}
OSC_API const char *osc_error_str(void) { return g_err; }
OSC_API const char *osc_arg_string_z(int32_t h, int32_t i) {
    parsed_arg *a = arg_at(h, i);
    parsed_msg *m = parsed_get(h);
    if (!a || a->type != 's' || !m) return "";
    return (const char*)(m->data + a->off);   /* NUL-terminated in the buffer */
}
OSC_API const char *osc_arg_int64_z(int32_t h, int32_t i) {
    static char z[24];
    parsed_arg *a = arg_at(h, i);
    if (!a || (a->type != 'h' && a->type != 'i' && a->type != 't')) return "";
    /* timetag ('t') is unsigned -- see osc_arg_int64_str */
    if (a->type == 't') snprintf(z, sizeof z, "%" PRIu64, (uint64_t) a->i);
    else                snprintf(z, sizeof z, "%" PRId64, a->i);
    return z;
}
OSC_API const char *osc_bundle_timetag_z(int32_t h) {
    static char z[24];
    parsed_msg *m = parsed_get(h);
    if (!m || !m->is_bundle) return "";
    snprintf(z, sizeof z, "%" PRIu64, m->timetag);
    return z;
}

/* ===================================================================== */
OSC_API int32_t osc_abi_version(void) { return OSC_ABI_VERSION; }

OSC_API int32_t osc_last_error(char *out, int32_t out_cap) {
    return copy_str(g_err, out, out_cap);
}
