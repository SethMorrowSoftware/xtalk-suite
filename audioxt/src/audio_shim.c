/*
 * audio_shim.c
 * ----------------------------------------------------------------------------
 * The C shim of audioxt: miniaudio (David Reid's single-header audio library,
 * public domain or MIT-0) behind a flat C ABI that the xTalk Builder (LCB)
 * foreign function interface can call, so OpenXTalk and LiveCode-compatible
 * engines can mix many sounds at once, stream long files, decode WAV, FLAC
 * and MP3, and record from a microphone, the same way on every platform.
 * box3dxt/src/box3d_shim.c is this file's ancestor and its conventions are
 * kept:
 *
 *   - Every object (an engine, a sound, a group, a capture) lives in a
 *     shim-side handle table and crosses as a positive 32-bit int (0 =
 *     invalid). Handles are generation-tagged: a handle stays dead after its
 *     object is freed even once the table slot is recycled.
 *   - Every real crosses as `double` and every boolean as `int`. Every time
 *     is in SECONDS.
 *   - A result that is more than one number crosses as TEXT: comma-separated
 *     items, written with a "." decimal point whatever the process locale
 *     says. The pointer returned is to a static buffer; the binding copies
 *     it at once (as a Pointer through its textOf(), never as ZStringNative:
 *     the engine FREES a returned C string).
 *   - BYTES OUT (microphone samples, a decoded file, a rendered mix, a WAV
 *     file) are left in ONE buffer this library owns, and the call returns
 *     their count. The binding copies them out with aux_out_pointer() before
 *     it makes another call. BYTES IN cross as a pointer and a length, and
 *     are COPIED here before the call returns: nothing keeps a pointer into
 *     the engine's memory.
 *
 * Threads (suite rule 1). miniaudio runs its own audio thread per device,
 * and a job thread per engine that reads streamed files. Neither ever calls
 * script. What they share with the script thread is small and explicit:
 *   - a sound that reaches its end sets ONE atomic flag in its own heap
 *     block; aux_poll_ended() collects the flags on the script thread;
 *   - the mixer's output meter (a peak pair and a short ring of samples) is
 *     written under a spinlock held for a few hundred nanoseconds;
 *   - a capture device's thread writes into a single-producer,
 *     single-consumer ring that the script thread drains, and writes a WAV
 *     file under a mutex when one is being recorded.
 * Everything else is miniaudio's own engine API, which is safe to call from
 * the script thread while the audio thread mixes.
 *
 * Safety. Every export validates its handles and arguments before it calls
 * miniaudio. A stale or never-created handle is a harmless no-op (getters
 * return 0 or empty), a non-finite or out-of-range number refuses the call,
 * and aux_last_error() says why. Nothing here throws, aborts or prints.
 *
 * Additive only. This library never touches the engine's own `play`
 * command, its player object or its sound channels: it opens its own device.
 *
 * Build: compiled with miniaudio into ONE shared library named "audioxt"
 * (audioxt.so / audioxt.dll / audioxt.dylib), or for the web into a static
 * archive. See CMakeLists.txt.
 * ----------------------------------------------------------------------------
 */

/* What of miniaudio is compiled in. JACK is left out on purpose: asking a
 * machine for a JACK server can START one, which is not something a sound
 * effect in a stack should do. PulseAudio and ALSA cover Linux, and both
 * are found at run time (dlopen), so the library links against neither. */
#define MA_NO_JACK
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#if defined(__EMSCRIPTEN__)
    #include <emscripten.h>
#endif
#include <locale.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
    #define LC_API __declspec(dllexport)
#else
    #define LC_API __attribute__((visibility("default")))
#endif

/* Bump when the exported ABI changes; src/audioxt.lcb's checkABI() names the
 * same number and refuses a library that answers another. */
#define AUX_ABI_VERSION 1

/* ------------------------------------------------------------------ */
/* Limits. Each is a refusal with a sentence, never a crash.           */
/* ------------------------------------------------------------------ */
#define AUX_MIN_RATE        8000
#define AUX_MAX_RATE        192000
#define AUX_MAX_CHANNELS    8
#define AUX_MAX_BYTES       (256 * 1024 * 1024)   /* one buffer, in or out   */
#define AUX_MAX_VOLUME      100.0                 /* 100 times = +40 dB      */
#define AUX_MIN_PITCH       0.01
#define AUX_MAX_PITCH       100.0
#define AUX_MAX_TIME        (60.0 * 60.0 * 24.0 * 365.0)  /* a year, seconds */
#define AUX_MAX_COORD       1.0e6
#define AUX_MAX_DEVICES     64
#define AUX_SCOPE_FRAMES    2048
#define AUX_MAX_ENGINES     16
#define AUX_MAX_CAPTURES    16
#define AUX_MAX_SOUNDS      65536
#define AUX_MAX_GROUPS      1024

/* ------------------------------------------------------------------ */
/* The handle table: pointers to heap objects behind generation-tagged */
/* ints. A handle packs an 11-bit generation above a 20-bit slot       */
/* number (slot + 1), so a stale handle stays DEAD after its slot is   */
/* recycled. A slot whose generation would wrap is retired, never      */
/* reused (box3dxt's lesson: the 2048th reuse of one slot would hand   */
/* out the bits of the first handle again).                            */
/* ------------------------------------------------------------------ */
#define AUX_H_SLOT_BITS 20
#define AUX_H_SLOT_MASK 0xFFFFF
#define AUX_H_GEN_MASK  0x7FF

typedef struct {
    void          **item;
    unsigned short *gen;
    int             cap;       /* slots allocated                    */
    int             count;     /* slots ever handed out              */
    int            *freeList;
    int             freeCap;
    int             freeCount;
    int             live;      /* objects alive now                  */
    int             limit;     /* most objects alive at once         */
} aux_table;

static int tbl_slot(const aux_table *t, int h)
{
    if (h <= 0) return -1;
    int idx = (h & AUX_H_SLOT_MASK) - 1;
    unsigned gen = ((unsigned)h >> AUX_H_SLOT_BITS) & AUX_H_GEN_MASK;
    if (idx < 0 || idx >= t->count) return -1;
    if (t->item[idx] == NULL || t->gen[idx] != gen) return -1;
    return idx;
}

static void *tbl_get(const aux_table *t, int h)
{
    int idx = tbl_slot(t, h);
    return idx < 0 ? NULL : t->item[idx];
}

/* Returns the new handle, or 0 (full, or out of memory). */
static int tbl_add(aux_table *t, void *p)
{
    int idx = -1;
    if (p == NULL || t->live >= t->limit) return 0;
    /* The free list is made big enough for every slot HERE, so that
     * tbl_remove can never fail: a remove that could not record its slot
     * would have to leak it or lie about it. */
    if (t->freeCount > 0) {
        idx = t->freeList[--t->freeCount];
    } else {
        if (t->count >= AUX_H_SLOT_MASK - 1) return 0;
        if (t->count >= t->cap) {
            int nc = t->cap ? t->cap * 2 : 32;
            void **ni = (void **)realloc(t->item, (size_t)nc * sizeof(void *));
            if (!ni) return 0;
            t->item = ni;
            unsigned short *ng = (unsigned short *)realloc(t->gen, (size_t)nc * sizeof(unsigned short));
            if (!ng) return 0;
            t->gen = ng;
            int *nf = (int *)realloc(t->freeList, (size_t)nc * sizeof(int));
            if (!nf) return 0;
            t->freeList = nf;
            t->freeCap = nc;
            memset(t->item + t->cap, 0, (size_t)(nc - t->cap) * sizeof(void *));
            memset(t->gen + t->cap, 0, (size_t)(nc - t->cap) * sizeof(unsigned short));
            t->cap = nc;
        }
        idx = t->count++;
    }
    t->item[idx] = p;
    t->live++;
    return (int)(((unsigned)t->gen[idx] << AUX_H_SLOT_BITS) | (unsigned)(idx + 1));
}

static void tbl_remove(aux_table *t, int h)
{
    int idx = tbl_slot(t, h);
    if (idx < 0) return;
    t->item[idx] = NULL;
    t->live--;
    if (t->gen[idx] >= AUX_H_GEN_MASK) return;          /* retired */
    t->gen[idx] = (unsigned short)(t->gen[idx] + 1);
    t->freeList[t->freeCount++] = idx;
}

/* ------------------------------------------------------------------ */
/* The objects                                                         */
/* ------------------------------------------------------------------ */

/* Bytes a sound plays from, owned here and shared by a sound and its
 * clones. miniaudio's resource manager is told about them by NAME and does
 * not copy them, so they are freed only when the last sound over them is. */
typedef struct {
    void  *data;
    size_t size;
    int    refs;
    int    registered;           /* the resource manager knows the name */
    char   name[40];
} aux_blob;

typedef struct {
    ma_engine   engine;
    /* A group nothing is ever routed through. miniaudio's mixer reads no
     * frames at all, and so does not advance its clock, while NOTHING is
     * attached to it (measured 2026-11-20: an empty engine rendered 0 of
     * 4800 frames). With this attached an engine always mixes: silence is
     * frames too, and aux_engine_time is a clock from the first moment. */
    ma_sound_group keepAlive;
    int         handle;
    int         offline;         /* no device: aux_engine_render pulls  */
    ma_uint32   channels;
    ma_uint32   sampleRate;
    char        deviceName[MA_MAX_DEVICE_NAME_LENGTH + 1];
    /* the output meter, written by the audio thread under meterLock    */
    ma_spinlock meterLock;
    float       peak[2];
    float       scope[AUX_SCOPE_FRAMES];
    ma_uint32   scopeAt;
} aux_engine;

enum { AUX_KIND_FILE = 1, AUX_KIND_STREAM, AUX_KIND_DATA, AUX_KIND_DATA_STREAM,
       AUX_KIND_PCM, AUX_KIND_TONE, AUX_KIND_NOISE };

typedef struct {
    ma_sound     sound;
    int          handle;
    int          engine;         /* its engine's handle                 */
    int          group;          /* its group's handle, or 0            */
    int          kind;
    int          cloneable;
    int          autoFree;
    int          stopArmed;      /* a stop time or fade-out is pending  */
    aux_blob    *blob;
    ma_decoder  *decoder;        /* AUX_KIND_DATA_STREAM                */
    ma_waveform *wave;           /* AUX_KIND_TONE                       */
    ma_noise    *noise;          /* AUX_KIND_NOISE                      */
    /* Set by the audio thread when the sound reaches its end; taken by
     * aux_poll_ended on the script thread. The one thing the two share. */
    MA_ATOMIC(4, ma_uint32) ended;
} aux_sound;

typedef struct {
    ma_sound_group group;
    int            handle;
    int            engine;
} aux_group;

typedef struct {
    ma_device   device;
    ma_pcm_rb   ring;
    int         handle;
    ma_format   format;
    ma_uint32   channels;
    ma_uint32   sampleRate;
    ma_uint32   bytesPerFrame;
    char        deviceName[MA_MAX_DEVICE_NAME_LENGTH + 1];
    MA_ATOMIC(4, ma_uint32) dropped;     /* frames the ring had no room for */
    ma_spinlock peakLock;
    float       peak;
    ma_mutex    fileLock;                /* guards encoder and recording    */
    ma_encoder *encoder;                 /* a heap block: an encoder holds a
                                          * pointer to itself, so it is never
                                          * copied or moved                  */
    int         recording;
    ma_uint64   recordedFrames;
} aux_capture;

static aux_table s_engines  = { NULL, NULL, 0, 0, NULL, 0, 0, 0, AUX_MAX_ENGINES };
static aux_table s_sounds   = { NULL, NULL, 0, 0, NULL, 0, 0, 0, AUX_MAX_SOUNDS };
static aux_table s_groups   = { NULL, NULL, 0, 0, NULL, 0, 0, 0, AUX_MAX_GROUPS };
static aux_table s_captures = { NULL, NULL, 0, 0, NULL, 0, 0, 0, AUX_MAX_CAPTURES };

/* ------------------------------------------------------------------ */
/* The last refusal, for auLastError(). A sentence, or "".             */
/* ------------------------------------------------------------------ */
static char s_errorText[256];
static const char *s_error = "";

static int fail(const char *why) { s_error = why; return 0; }
static void ok_clear(void) { s_error = ""; }

/* "could not open the file: No such file or directory" */
static int fail_ma(const char *what, ma_result r)
{
    snprintf(s_errorText, sizeof(s_errorText), "%s: %s", what, ma_result_description(r));
    s_error = s_errorText;
    return 0;
}

/* ------------------------------------------------------------------ */
/* Argument checks                                                     */
/* ------------------------------------------------------------------ */
static int fin(double v) { return isfinite(v) ? 1 : 0; }
static int in_range(double v, double lo, double hi) { return fin(v) && v >= lo && v <= hi; }
static int coord_ok(double x, double y, double z)
{
    return in_range(x, -AUX_MAX_COORD, AUX_MAX_COORD) && in_range(y, -AUX_MAX_COORD, AUX_MAX_COORD)
        && in_range(z, -AUX_MAX_COORD, AUX_MAX_COORD);
}

/* The five sample formats, by the names scripts use. */
static ma_format format_of(const char *name)
{
    if (name == NULL) return ma_format_unknown;
    if (strcmp(name, "u8") == 0)  return ma_format_u8;
    if (strcmp(name, "s16") == 0) return ma_format_s16;
    if (strcmp(name, "s24") == 0) return ma_format_s24;
    if (strcmp(name, "s32") == 0) return ma_format_s32;
    if (strcmp(name, "f32") == 0) return ma_format_f32;
    return ma_format_unknown;
}

static const char *format_name(ma_format f)
{
    switch (f) {
        case ma_format_u8:  return "u8";
        case ma_format_s16: return "s16";
        case ma_format_s24: return "s24";
        case ma_format_s32: return "s32";
        case ma_format_f32: return "f32";
        default:            return "";
    }
}

/* ------------------------------------------------------------------ */
/* Text results                                                        */
/* ------------------------------------------------------------------ */
static char s_text[512];
/* The waveform has a buffer of its own: 2048 numbers do not fit s_text. */
static char s_wave[AUX_SCOPE_FRAMES * 12 + 16];

/* One number as text with a "." decimal point in every locale (an engine
 * built on GTK calls setlocale(), and a "1,5" would be two items). Returns
 * the length written (never more than cap - 1). */
static int num_text(char *out, int cap, double v, const char *fmt)
{
    if (!isfinite(v)) v = 0.0;
    int n = snprintf(out, (size_t)cap, fmt, v);
    if (n < 0) { out[0] = '0'; out[1] = 0; return 1; }
    if (n >= cap) n = cap - 1;
    const struct lconv *lc = localeconv();
    const char *dp = lc ? lc->decimal_point : NULL;
    if (dp && dp[0] && strcmp(dp, ".") != 0) {
        char *q = strstr(out, dp);
        if (q) {
            size_t dl = strlen(dp);
            *q = '.';
            memmove(q + 1, q + dl, strlen(q + dl) + 1);
            n = (int)strlen(out);
        }
    }
    return n;
}

static const char *text_of(const double *v, int n)
{
    int at = 0;
    s_text[0] = 0;
    for (int i = 0; i < n; i++) {
        if (at > (int)sizeof(s_text) - 40) break;
        if (i) s_text[at++] = ',';
        at += num_text(s_text + at, (int)sizeof(s_text) - at, v[i], "%.9g");
    }
    s_text[at] = 0;
    return s_text;
}

static const char *text_vec(ma_vec3f v)
{
    double d[3] = { v.x, v.y, v.z };
    return text_of(d, 3);
}

static const char *text_copy(const char *s)
{
    snprintf(s_text, sizeof(s_text), "%s", s ? s : "");
    return s_text;
}

static const char *text_empty(void) { s_text[0] = 0; return s_text; }

/* ------------------------------------------------------------------ */
/* The out buffer: the one place bytes leave from.                     */
/* ------------------------------------------------------------------ */
static unsigned char *s_out = NULL;
static size_t         s_outCap = 0;
static int            s_outRate = 0;
static int            s_outChannels = 0;

static int out_reserve(size_t bytes)
{
    if (bytes > (size_t)AUX_MAX_BYTES) return 0;
    if (bytes <= s_outCap) return 1;
    size_t nc = s_outCap ? s_outCap : 65536;
    while (nc < bytes) nc *= 2;
    unsigned char *nb = (unsigned char *)realloc(s_out, nc);
    if (!nb) return 0;
    s_out = nb;
    s_outCap = nc;
    return 1;
}

/* ------------------------------------------------------------------ */
/* Paths. Script hands a path as UTF-8; Windows wants UTF-16.          */
/* ------------------------------------------------------------------ */
#if defined(_WIN32)
static wchar_t *wide_path(const char *utf8)
{
    int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t *w = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
    if (!w) return NULL;
    if (MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8, -1, w, n) <= 0) { free(w); return NULL; }
    return w;
}
#endif

static int path_ok(const char *path)
{
    if (path == NULL || path[0] == 0) return fail("the path is empty");
    if (strlen(path) > 4096) return fail("the path is too long");
    /* miniaudio 0.11.26 reads one byte past the end of a path whose last
     * character is a dot when it looks for the file's extension
     * (ma_path_extension steps over the dot and then over the terminator;
     * met by tests/fuzz_test.c under ASan, 2026-11-20, with the path ".").
     * No sound file is named that way, so such a path is refused here. */
    if (path[strlen(path) - 1] == '.') return fail("a path cannot end in a dot");
    return 1;
}

static ma_result sound_init_file(ma_engine *e, const char *path, ma_uint32 flags, ma_sound *s)
{
#if defined(_WIN32)
    wchar_t *w = wide_path(path);
    if (!w) return MA_INVALID_ARGS;
    ma_result r = ma_sound_init_from_file_w(e, w, flags, NULL, NULL, s);
    free(w);
    return r;
#else
    return ma_sound_init_from_file(e, path, flags, NULL, NULL, s);
#endif
}

static ma_result decoder_init_path(const char *path, const ma_decoder_config *cfg, ma_decoder *d)
{
#if defined(_WIN32)
    wchar_t *w = wide_path(path);
    if (!w) return MA_INVALID_ARGS;
    ma_result r = ma_decoder_init_file_w(w, cfg, d);
    free(w);
    return r;
#else
    return ma_decoder_init_file(path, cfg, d);
#endif
}

static ma_result encoder_init_path(const char *path, const ma_encoder_config *cfg, ma_encoder *enc)
{
#if defined(_WIN32)
    wchar_t *w = wide_path(path);
    if (!w) return MA_INVALID_ARGS;
    ma_result r = ma_encoder_init_file_w(w, cfg, enc);
    free(w);
    return r;
#else
    return ma_encoder_init_file(path, cfg, enc);
#endif
}

/* ------------------------------------------------------------------ */
/* The device contexts. One for the machine's real audio system, made  */
/* the first time anything asks about a device, and one for miniaudio's */
/* "null" backend: a device that plays into nothing and records        */
/* silence, in real time. The null device is what a machine with no    */
/* sound card (a CI runner, a server) can still open, and device -1    */
/* names it everywhere a device index is taken.                        */
/* ------------------------------------------------------------------ */
static ma_context s_ctx;
static int        s_ctxState = 0;        /* 0 not tried, 1 ready, -1 failed */
static ma_context s_nullCtx;
static int        s_nullCtxState = 0;

static ma_context *real_context(void)
{
    if (s_ctxState == 0) {
        ma_context_config cfg = ma_context_config_init();
        s_ctxState = ma_context_init(NULL, 0, &cfg, &s_ctx) == MA_SUCCESS ? 1 : -1;
    }
    return s_ctxState == 1 ? &s_ctx : NULL;
}

static ma_context *null_context(void)
{
    if (s_nullCtxState == 0) {
        ma_backend backends[1] = { ma_backend_null };
        ma_context_config cfg = ma_context_config_init();
        s_nullCtxState = ma_context_init(backends, 1, &cfg, &s_nullCtx) == MA_SUCCESS ? 1 : -1;
    }
    return s_nullCtxState == 1 ? &s_nullCtx : NULL;
}

/* The device lists, as the last aux_device_scan found them. */
typedef struct {
    ma_device_id id;
    char         name[MA_MAX_DEVICE_NAME_LENGTH + 1];
    int          isDefault;
} aux_device_row;

static aux_device_row s_playback[AUX_MAX_DEVICES];
static int            s_playbackCount = 0;
static aux_device_row s_capture[AUX_MAX_DEVICES];
static int            s_captureCount = 0;

static void rows_fill(aux_device_row *rows, int *count, const ma_device_info *infos, ma_uint32 n)
{
    *count = 0;
    for (ma_uint32 i = 0; i < n && *count < AUX_MAX_DEVICES; i++) {
        aux_device_row *row = &rows[*count];
        row->id = infos[i].id;
        snprintf(row->name, sizeof(row->name), "%s", infos[i].name);
        row->isDefault = infos[i].isDefault ? 1 : 0;
        (*count)++;
    }
}

#if defined(__EMSCRIPTEN__)
/* THE WEB: ASK THE PAGE BEFORE MINIAUDIO DOES. miniaudio opens a Web Audio
 * device with JavaScript it carries (EM_ASM) that takes two things for
 * granted, and a JavaScript throw there does not come back as an error: it
 * unwinds through every WebAssembly frame above it, the web engine's main
 * loop included, and the engine stops (the web IDE with it). So both are
 * asked here first, inside a try, and the call is refused with a reason:
 *
 *   - new AudioContext() and its createScriptProcessor, which a browser
 *     with no Web Audio for the page refuses by throwing. Asked ONCE per
 *     page (a context is made and closed at once, as miniaudio's own
 *     device-info query does, inside its own try): a context per open
 *     would count against the few that some browsers allow at a time.
 *   - navigator.mediaDevices.getUserMedia, for a microphone. A browser
 *     offers it only in a secure context (https, or this computer), so a
 *     page served over plain http has no navigator.mediaDevices at all,
 *     and miniaudio calls getUserMedia on it.
 *
 * What is left is asynchronous and miniaudio already catches it: a refused
 * microphone permission rejects a promise, logged, and the capture simply
 * delivers nothing. tests/web/run-web-test.cjs takes both away and holds
 * the refusals.
 *
 * A device opened before the visitor's first gesture is held silent by the
 * browser until a gesture lets it resume. miniaudio resumes its started
 * devices on the first click or touchend only, so a stack played from the
 * keyboard stayed silent until something was clicked, and a button held
 * down was silent until it was let go. Once its checks pass, this also
 * listens (once per page, in the capture phase, never stopping the event)
 * for a key or mouse button going down and resumes miniaudio's started
 * devices then; the first resume that succeeds removes the listener, since
 * a page that has had a gesture keeps it and miniaudio's own start resumes
 * a device from then on. A key that is no gesture (Escape) leaves the
 * resume pending, which the browser settles at the next real one. */
static int web_device_ok(int capture)
{
    int why = EM_ASM_INT({
        try {
            if (typeof window === 'undefined') return 1;
            if (window.__audioxtWebAudio === undefined) {
                var probe = 0;
                try {
                    var C = window.AudioContext || window.webkitAudioContext;
                    if (!C) {
                        probe = 1;
                    } else {
                        var c = new C();
                        if (typeof c.createScriptProcessor !== 'function') probe = 1;
                        if (typeof c.close === 'function') c.close();
                    }
                } catch (e) {
                    probe = 1;
                }
                window.__audioxtWebAudio = probe;
            }
            if (window.__audioxtWebAudio !== 0) return 1;
            if ($0 && !(typeof navigator !== 'undefined' && navigator.mediaDevices &&
                        typeof navigator.mediaDevices.getUserMedia === 'function')) return 2;
            /* No comma may stand outside parentheses in an EM_ASM block (the
               preprocessor would split the macro's arguments there). */
            if (window.__audioxtUnlock === undefined && typeof document !== 'undefined') {
                window.__audioxtUnlock = function () {
                    try {
                        var ma = window.miniaudio;
                        if (!ma || !ma.devices || !ma.device_state) return;
                        for (var i = 0; i < ma.devices.length; ++i) {
                            var d = ma.devices[i];
                            if (d != null && d.webaudio != null && d.state === ma.device_state.started &&
                                d.webaudio.state === 'suspended')
                                d.webaudio.resume().then(function () {
                                    document.removeEventListener('keydown', window.__audioxtUnlock, true);
                                    document.removeEventListener('mousedown', window.__audioxtUnlock, true);
                                }, function () {});
                        }
                    } catch (e) {
                    }
                };
                document.addEventListener('keydown', window.__audioxtUnlock, true);
                document.addEventListener('mousedown', window.__audioxtUnlock, true);
            }
            return 0;
        } catch (e) {
            return 1;
        }
    }, capture);
    if (why == 2)
        return fail("this page cannot reach a microphone: a browser offers one only to a page served over https or from this computer");
    if (why != 0)
        return fail("this browser has no Web Audio for this page");
    return 1;
}

/* THE WEB: A LONGER BUFFER, WHEN THE PAGE ASKS FOR ONE. miniaudio plays a
 * Web Audio device through a ScriptProcessorNode, whose callback runs on
 * the page's main thread, the thread the web engine runs on. Its buffer
 * is some 33 ms rounded up to a power of two (2048 frames at 44.1 kHz,
 * 46 ms), so a frame of a game that holds the thread longer than that
 * leaves the callback late and the sound crackles. An AudioWorklet would
 * not wait on the page, but needs a cross-origin isolated page, which a
 * stack player in a sandboxed frame is not. So a page may ask for a longer
 * buffer, at the cost of as much more latency, BEFORE it opens an engine:
 *     do "window.audioxtWebBuffer = 80" as "JavaScript"
 * (milliseconds, 10 to 400; miniaudio rounds the frames up to a power of
 * two, so 80 is 4096 frames at 44.1 kHz, 93 ms). Unset, zero or not a
 * number, an engine opens as it always did. Off the web there is no such
 * page and nothing changes. tests/web/run-web-test.cjs holds both. */
static ma_uint32 web_buffer_ms(void)
{
    int ms = EM_ASM_INT({
        try {
            if (typeof window === 'undefined') return 0;
            var v = Number(window.audioxtWebBuffer);
            if (!isFinite(v) || v <= 0) return 0;
            return Math.round(v);
        } catch (e) {
            return 0;
        }
    });
    if (ms <= 0) return 0;
    if (ms < 10) ms = 10;
    if (ms > 400) ms = 400;
    return (ma_uint32)ms;
}
#endif

/* Which context and device id a device index names. Returns 0 (refused,
 * the error set) or 1; *id is NULL for "the default device". */
static int device_pick(int device, int capture, ma_context **ctx, ma_device_id **id)
{
    *id = NULL;
    if (device == -1) {
        *ctx = null_context();
        if (*ctx == NULL) return fail("the silent test device is not available here");
        return 1;
    }
    *ctx = real_context();
    if (*ctx == NULL) return fail("this machine has no audio system the library can use");
#if defined(__EMSCRIPTEN__)
    if (!web_device_ok(capture)) return 0;
#endif
    if (device == 0) return 1;
    int count = capture ? s_captureCount : s_playbackCount;
    if (device < 1 || device > count) return fail("no such device (scan first; devices are numbered from 1)");
    *id = capture ? &s_capture[device - 1].id : &s_playback[device - 1].id;
    return 1;
}

/* ------------------------------------------------------------------ */
/* The library                                                         */
/* ------------------------------------------------------------------ */
LC_API int aux_abi_version(void) { return AUX_ABI_VERSION; }

/* "audioxt ABI 1; miniaudio 0.11.26" */
LC_API const char *aux_library_version(void)
{
    snprintf(s_text, sizeof(s_text), "audioxt ABI %d; miniaudio %s", AUX_ABI_VERSION, ma_version_string());
    return s_text;
}

LC_API const char *aux_last_error(void) { return s_error; }

/* HOW TEXT CROSSES. Every text result is a pointer to a buffer this library
 * owns, valid until the next call. The binding declares such a result a
 * Pointer and the engine copies the bytes out with its own
 * MCStringCreateWithBytes, for which it needs the length: this. One of the
 * two exports with no public handler over it. */
LC_API int aux_text_length(const char *text) { return text ? (int)strlen(text) : 0; }

/* HOW BYTES CROSS. A call that produces bytes returns their count and
 * leaves them here; the binding copies that many from this pointer at once.
 * The other export with no public handler over it. */
LC_API const void *aux_out_pointer(void) { return s_out ? (const void *)s_out : (const void *)""; }

/* The sample rate and channel count of the bytes the last decode or render
 * left in the out buffer (0 before the first). */
LC_API int aux_out_sample_rate(void) { return s_outRate; }
LC_API int aux_out_channels(void) { return s_outChannels; }

/* The name of the audio system in use ("WASAPI", "Core Audio",
 * "PulseAudio", "ALSA", "AAudio", "Web Audio", ...), or "" if there is none. */
LC_API const char *aux_backend_name(void)
{
    ma_context *ctx = real_context();
    if (ctx == NULL) return text_empty();
    return text_copy(ma_get_backend_name(ctx->backend));
}

/* ------------------------------------------------------------------ */
/* Devices                                                             */
/* ------------------------------------------------------------------ */

/* Asks the audio system for its devices and keeps the two lists. Returns
 * how many it found in all (0 is a real answer), or -1 if there is no audio
 * system to ask. Device numbers handed to aux_engine_create and
 * aux_capture_open index THESE lists, so scan before choosing. */
LC_API int aux_device_scan(void)
{
    ma_context *ctx = real_context();
    ma_device_info *play = NULL, *cap = NULL;
    ma_uint32 nPlay = 0, nCap = 0;
    s_playbackCount = 0;
    s_captureCount = 0;
    if (ctx == NULL) { fail("this machine has no audio system the library can use"); return -1; }
    ma_result r = ma_context_get_devices(ctx, &play, &nPlay, &cap, &nCap);
    if (r != MA_SUCCESS) { fail_ma("could not list the devices", r); return -1; }
    rows_fill(s_playback, &s_playbackCount, play, nPlay);
    rows_fill(s_capture, &s_captureCount, cap, nCap);
    ok_clear();
    return s_playbackCount + s_captureCount;
}

LC_API int aux_playback_device_count(void) { return s_playbackCount; }

LC_API const char *aux_playback_device_name(int index)
{
    if (index < 1 || index > s_playbackCount) return text_empty();
    return text_copy(s_playback[index - 1].name);
}

LC_API int aux_playback_device_is_default(int index)
{
    if (index < 1 || index > s_playbackCount) return 0;
    return s_playback[index - 1].isDefault;
}

LC_API int aux_capture_device_count(void) { return s_captureCount; }

LC_API const char *aux_capture_device_name(int index)
{
    if (index < 1 || index > s_captureCount) return text_empty();
    return text_copy(s_capture[index - 1].name);
}

LC_API int aux_capture_device_is_default(int index)
{
    if (index < 1 || index > s_captureCount) return 0;
    return s_capture[index - 1].isDefault;
}

/* ------------------------------------------------------------------ */
/* Engines                                                             */
/* ------------------------------------------------------------------ */

/* Runs on the AUDIO thread (or inside aux_engine_render), after every block
 * the engine mixes: the peak of each of the first two channels since the
 * last read, and the newest samples (as mono) for a waveform display. */
static void on_engine_process(void *user, float *frames, ma_uint64 frameCount)
{
    aux_engine *e = (aux_engine *)user;
    ma_uint32 ch = e->channels;
    if (ch == 0 || frames == NULL) return;
    ma_spinlock_lock(&e->meterLock);
    for (ma_uint64 i = 0; i < frameCount; i++) {
        float l = frames[i * ch];
        float r = ch > 1 ? frames[i * ch + 1] : l;
        float al = l < 0 ? -l : l;
        float ar = r < 0 ? -r : r;
        if (al > e->peak[0]) e->peak[0] = al;
        if (ar > e->peak[1]) e->peak[1] = ar;
        e->scope[e->scopeAt] = (l + r) * 0.5f;
        e->scopeAt = (e->scopeAt + 1) % AUX_SCOPE_FRAMES;
    }
    ma_spinlock_unlock(&e->meterLock);
}

static int engine_make(int offline, int device, int sampleRate, int channels)
{
    ma_context *ctx = NULL;
    ma_device_id *id = NULL;
    if (sampleRate != 0 && (sampleRate < AUX_MIN_RATE || sampleRate > AUX_MAX_RATE))
        return fail("the sample rate must be 0 (the device's own) or 8000 to 192000");
    if (channels < 0 || channels > AUX_MAX_CHANNELS)
        return fail("the channel count must be 0 (the device's own) or 1 to 8");
    if (offline && (sampleRate == 0 || channels == 0))
        return fail("an offline engine needs a sample rate and a channel count");
    if (s_engines.live >= s_engines.limit) return fail("too many engines are open (16 at most)");
    if (!offline && !device_pick(device, 0, &ctx, &id)) return 0;

    aux_engine *e = (aux_engine *)calloc(1, sizeof(aux_engine));
    if (!e) return fail("out of memory");
    ma_engine_config cfg = ma_engine_config_init();
    cfg.listenerCount = 1;
    cfg.sampleRate = (ma_uint32)sampleRate;
    cfg.channels = (ma_uint32)channels;
    cfg.onProcess = on_engine_process;
    cfg.pProcessUserData = e;
    /* The device is started HERE, below, once this block is complete: an
     * engine that starts itself has its audio thread reading e->channels
     * while this thread is still writing it (ThreadSanitizer, 2026-11-20). */
    cfg.noAutoStart = MA_TRUE;
    if (offline) {
        cfg.noDevice = MA_TRUE;
    } else {
        cfg.pContext = ctx;
        cfg.pPlaybackDeviceID = id;
#if defined(__EMSCRIPTEN__)
        cfg.periodSizeInMilliseconds = web_buffer_ms();
#endif
    }
    ma_result r = ma_engine_init(&cfg, &e->engine);
    if (r != MA_SUCCESS) {
        free(e);
        return fail_ma(offline ? "could not make the engine" : "could not open the playback device", r);
    }
    r = ma_sound_group_init(&e->engine, MA_SOUND_FLAG_NO_SPATIALIZATION, NULL, &e->keepAlive);
    if (r != MA_SUCCESS) {
        ma_engine_uninit(&e->engine);
        free(e);
        return fail_ma("could not make the engine", r);
    }
    e->offline = offline;
    e->channels = ma_engine_get_channels(&e->engine);
    e->sampleRate = ma_engine_get_sample_rate(&e->engine);
    if (!offline) {
        ma_device *dev = ma_engine_get_device(&e->engine);
        if (dev) ma_device_get_name(dev, ma_device_type_playback, e->deviceName, sizeof(e->deviceName), NULL);
    }
    int h = tbl_add(&s_engines, e);
    if (h == 0) {
        ma_sound_group_uninit(&e->keepAlive);
        ma_engine_uninit(&e->engine);
        free(e);
        return fail("out of memory");
    }
    e->handle = h;
    if (!offline) {
        r = ma_engine_start(&e->engine);
        if (r != MA_SUCCESS) {
            tbl_remove(&s_engines, h);
            ma_sound_group_uninit(&e->keepAlive);
            ma_engine_uninit(&e->engine);
            free(e);
            return fail_ma("could not start the playback device", r);
        }
    }
    ok_clear();
    return h;
}

/* Opens a playback device and starts mixing into it. device: 0 the default
 * device, 1..n a device of the last aux_device_scan, -1 the silent test
 * device. sampleRate and channels: 0 takes the device's own. */
LC_API int aux_engine_create(int device, int sampleRate, int channels)
{
    return engine_make(0, device, sampleRate, channels);
}

/* An engine with no device: nothing is heard, and aux_engine_render pulls
 * the mix as bytes. For rendering a mix to a file, and for tests. */
LC_API int aux_engine_create_offline(int sampleRate, int channels)
{
    return engine_make(1, 0, sampleRate, channels);
}

static aux_engine *engine_of(int h) { return (aux_engine *)tbl_get(&s_engines, h); }

/* Where there are no threads (the web build), nobody reads a streamed file
 * ahead unless somebody runs the resource manager's jobs. miniaudio does
 * that itself from a device's callback; an offline engine has no callback,
 * so aux_engine_render and aux_poll_ended do it here. A no-op everywhere else. */
static void pump_jobs(aux_engine *e)
{
    ma_resource_manager *rm = ma_engine_get_resource_manager(&e->engine);
    if (rm == NULL || (rm->config.flags & MA_RESOURCE_MANAGER_FLAG_NO_THREADING) == 0) return;
    for (int i = 0; i < 64; i++) {
        if (ma_resource_manager_process_next_job(rm) != MA_SUCCESS) break;
    }
}
static aux_sound *sound_of(int h) { return (aux_sound *)tbl_get(&s_sounds, h); }
static aux_group *group_of(int h) { return (aux_group *)tbl_get(&s_groups, h); }
static aux_capture *capture_of(int h) { return (aux_capture *)tbl_get(&s_captures, h); }

static void blob_release(aux_engine *e, aux_blob *b)
{
    if (b == NULL) return;
    if (--b->refs > 0) return;
    if (b->registered && e != NULL)
        ma_resource_manager_unregister_data(ma_engine_get_resource_manager(&e->engine), b->name);
    free(b->data);
    free(b);
}

/* Frees one sound. The order matters: the sound leaves the mix first
 * (ma_sound_uninit returns only once the audio thread is done with it), and
 * only then is what it was reading from let go. */
static void sound_destroy(aux_sound *s)
{
    aux_engine *e = engine_of(s->engine);
    tbl_remove(&s_sounds, s->handle);
    ma_sound_uninit(&s->sound);
    if (s->decoder) { ma_decoder_uninit(s->decoder); free(s->decoder); }
    if (s->wave) { ma_waveform_uninit(s->wave); free(s->wave); }
    if (s->noise) { ma_noise_uninit(s->noise, NULL); free(s->noise); }
    blob_release(e, s->blob);
    free(s);
}

static void group_destroy(aux_group *g)
{
    aux_engine *e = engine_of(g->engine);
    /* A sound still routed through the group goes back to the engine's own
     * output: freeing a group must not silence what was playing in it. */
    for (int i = 0; i < s_sounds.count; i++) {
        aux_sound *s = (aux_sound *)s_sounds.item[i];
        if (s && s->group == g->handle) {
            s->group = 0;
            if (e) ma_node_attach_output_bus(&s->sound, 0, ma_engine_get_endpoint(&e->engine), 0);
        }
    }
    tbl_remove(&s_groups, g->handle);
    ma_sound_group_uninit(&g->group);
    free(g);
}

/* Closes an engine and frees every sound and group made on it. */
LC_API void aux_engine_free(int engine)
{
    aux_engine *e = engine_of(engine);
    if (!e) return;
    if (!e->offline) ma_engine_stop(&e->engine);
    for (int i = 0; i < s_sounds.count; i++) {
        aux_sound *s = (aux_sound *)s_sounds.item[i];
        if (s && s->engine == engine) sound_destroy(s);
    }
    for (int i = 0; i < s_groups.count; i++) {
        aux_group *g = (aux_group *)s_groups.item[i];
        if (g && g->engine == engine) group_destroy(g);
    }
    ma_sound_group_uninit(&e->keepAlive);
    ma_engine_uninit(&e->engine);
    tbl_remove(&s_engines, engine);
    free(e);
}

LC_API int aux_engine_is_valid(int engine) { return engine_of(engine) ? 1 : 0; }
LC_API int aux_engine_is_offline(int engine) { aux_engine *e = engine_of(engine); return e ? e->offline : 0; }

/* Resumes a device that aux_engine_stop paused. Sounds keep their places. */
LC_API void aux_engine_start(int engine)
{
    aux_engine *e = engine_of(engine);
    if (e && !e->offline) ma_engine_start(&e->engine);
}

/* Pauses the device: nothing is heard and the engine's clock stands still. */
LC_API void aux_engine_stop(int engine)
{
    aux_engine *e = engine_of(engine);
    if (e && !e->offline) ma_engine_stop(&e->engine);
}

LC_API void aux_engine_set_volume(int engine, double volume)
{
    aux_engine *e = engine_of(engine);
    if (!e) return;
    if (!in_range(volume, 0.0, AUX_MAX_VOLUME)) { fail("the volume must be 0 to 100 (1 is unchanged)"); return; }
    ma_engine_set_volume(&e->engine, (float)volume);
}

LC_API double aux_engine_volume(int engine)
{
    aux_engine *e = engine_of(engine);
    return e ? (double)ma_engine_get_volume(&e->engine) : 0.0;
}

LC_API int aux_engine_sample_rate(int engine) { aux_engine *e = engine_of(engine); return e ? (int)e->sampleRate : 0; }
LC_API int aux_engine_channels(int engine) { aux_engine *e = engine_of(engine); return e ? (int)e->channels : 0; }

/* The engine's clock: seconds of sound mixed since it was created. It is
 * what aux_sound_start_at and aux_sound_stop_at are measured against. */
LC_API double aux_engine_time(int engine)
{
    aux_engine *e = engine_of(engine);
    if (!e || e->sampleRate == 0) return 0.0;
    return (double)ma_engine_get_time_in_pcm_frames(&e->engine) / (double)e->sampleRate;
}

LC_API int aux_engine_sound_count(int engine)
{
    int n = 0;
    if (!engine_of(engine)) return 0;
    for (int i = 0; i < s_sounds.count; i++) {
        aux_sound *s = (aux_sound *)s_sounds.item[i];
        if (s && s->engine == engine) n++;
    }
    return n;
}

LC_API const char *aux_engine_device_name(int engine)
{
    aux_engine *e = engine_of(engine);
    return e ? text_copy(e->deviceName) : text_empty();
}

/* Stops every sound of the engine where it is. */
LC_API void aux_engine_stop_all(int engine)
{
    if (!engine_of(engine)) return;
    for (int i = 0; i < s_sounds.count; i++) {
        aux_sound *s = (aux_sound *)s_sounds.item[i];
        if (s && s->engine == engine) ma_sound_stop(&s->sound);
    }
}

/* "left,right": the loudest sample of each side since the last call, 0 to 1
 * (above 1 the output is clipping). Reading resets it. */
LC_API const char *aux_engine_peak(int engine)
{
    aux_engine *e = engine_of(engine);
    double v[2] = { 0.0, 0.0 };
    if (!e) return text_empty();
    ma_spinlock_lock(&e->meterLock);
    v[0] = e->peak[0];
    v[1] = e->peak[1];
    e->peak[0] = 0.0f;
    e->peak[1] = 0.0f;
    ma_spinlock_unlock(&e->meterLock);
    return text_of(v, 2);
}

/* `points` samples, -1 to 1, comma-separated, spread evenly over the newest
 * 2048 frames the engine mixed (left and right averaged), oldest first: what
 * an oscilloscope display draws. */
LC_API const char *aux_engine_waveform(int engine, int points)
{
    static float snap[AUX_SCOPE_FRAMES];
    aux_engine *e = engine_of(engine);
    ma_uint32 start;
    int at = 0;
    s_wave[0] = 0;
    if (!e) return s_wave;
    if (points < 1 || points > AUX_SCOPE_FRAMES) { fail("the point count must be 1 to 2048"); return s_wave; }
    ma_spinlock_lock(&e->meterLock);
    memcpy(snap, e->scope, sizeof(snap));
    start = e->scopeAt;
    ma_spinlock_unlock(&e->meterLock);
    for (int i = 0; i < points; i++) {
        ma_uint32 k = (ma_uint32)(((ma_uint64)i * AUX_SCOPE_FRAMES) / (ma_uint32)points);
        if (i) s_wave[at++] = ',';
        at += num_text(s_wave + at, (int)sizeof(s_wave) - at, snap[(start + k) % AUX_SCOPE_FRAMES], "%.4f");
    }
    s_wave[at] = 0;
    return s_wave;
}

/* An offline engine only: mixes the next `frames` frames and leaves them in
 * the out buffer in `format`. Returns the byte count, 0 if refused. */
LC_API int aux_engine_render(int engine, int frames, const char *format)
{
    aux_engine *e = engine_of(engine);
    ma_format fmt = format_of(format);
    if (!e) return 0;
    if (!e->offline) return fail("only an offline engine can be rendered (a device engine plays by itself)");
    if (fmt == ma_format_unknown) return fail("the format must be u8, s16, s24, s32 or f32");
    if (frames < 1) return fail("the frame count must be 1 or more");
    size_t floatBytes = (size_t)frames * e->channels * sizeof(float);
    if (floatBytes > (size_t)AUX_MAX_BYTES || !out_reserve(floatBytes)) return fail("that many frames do not fit one buffer");
    ma_uint64 got = 0;
    pump_jobs(e);
    ma_result r = ma_engine_read_pcm_frames(&e->engine, s_out, (ma_uint64)frames, &got);
    if (r != MA_SUCCESS) return fail_ma("could not render", r);
    /* Every format is the same size as f32 or smaller, and conversion walks
     * forward, so it is done in place. */
    if (fmt != ma_format_f32)
        ma_pcm_convert(s_out, fmt, s_out, ma_format_f32, got * e->channels, ma_dither_mode_none);
    s_outRate = (int)e->sampleRate;
    s_outChannels = (int)e->channels;
    ok_clear();
    return (int)(got * e->channels * ma_get_bytes_per_sample(fmt));
}

/* ---- the listener: where 3D sounds are heard from ---- */
LC_API void aux_engine_set_listener_position(int engine, double x, double y, double z)
{
    aux_engine *e = engine_of(engine);
    if (!e) return;
    if (!coord_ok(x, y, z)) { fail("a coordinate is not a number, or is beyond a million"); return; }
    ma_engine_listener_set_position(&e->engine, 0, (float)x, (float)y, (float)z);
}

LC_API const char *aux_engine_listener_position(int engine)
{
    aux_engine *e = engine_of(engine);
    return e ? text_vec(ma_engine_listener_get_position(&e->engine, 0)) : text_empty();
}

/* The way the listener faces. Not (0,0,0). The default is (0,0,-1). */
LC_API void aux_engine_set_listener_direction(int engine, double x, double y, double z)
{
    aux_engine *e = engine_of(engine);
    if (!e) return;
    if (!coord_ok(x, y, z) || (x == 0.0 && y == 0.0 && z == 0.0)) { fail("a direction needs three numbers, not all 0"); return; }
    ma_engine_listener_set_direction(&e->engine, 0, (float)x, (float)y, (float)z);
}

LC_API const char *aux_engine_listener_direction(int engine)
{
    aux_engine *e = engine_of(engine);
    return e ? text_vec(ma_engine_listener_get_direction(&e->engine, 0)) : text_empty();
}

/* Which way is up for the listener. Not (0,0,0). The default is (0,1,0). */
LC_API void aux_engine_set_listener_up(int engine, double x, double y, double z)
{
    aux_engine *e = engine_of(engine);
    if (!e) return;
    if (!coord_ok(x, y, z) || (x == 0.0 && y == 0.0 && z == 0.0)) { fail("a direction needs three numbers, not all 0"); return; }
    ma_engine_listener_set_world_up(&e->engine, 0, (float)x, (float)y, (float)z);
}

/* The listener's velocity, for the Doppler effect only: it moves nothing. */
LC_API void aux_engine_set_listener_velocity(int engine, double x, double y, double z)
{
    aux_engine *e = engine_of(engine);
    if (!e) return;
    if (!coord_ok(x, y, z)) { fail("a coordinate is not a number, or is beyond a million"); return; }
    ma_engine_listener_set_velocity(&e->engine, 0, (float)x, (float)y, (float)z);
}

/* ------------------------------------------------------------------ */
/* Sounds                                                              */
/* ------------------------------------------------------------------ */

/* Runs on the AUDIO thread when a sound reaches its end. One atomic store
 * into the sound's own block and nothing else (suite rule 1). The block
 * outlives the call: sound_destroy frees it only after ma_sound_uninit has
 * taken the sound out of the mix. */
static void on_sound_end(void *user, ma_sound *sound)
{
    aux_sound *s = (aux_sound *)user;
    (void)sound;
    ma_atomic_exchange_32(&s->ended, 1);
}

/* Sounds start with 3D positioning OFF, so that pan means pan and a sound
 * nobody positioned is not attenuated by where the listener happens to be;
 * aux_sound_set_spatial turns it on for the sounds that want it. */
#define AUX_SOUND_FLAGS (MA_SOUND_FLAG_NO_SPATIALIZATION)

static aux_sound *sound_alloc(int engine, int kind)
{
    if (s_sounds.live >= s_sounds.limit) { fail("too many sounds are loaded (65536 at most)"); return NULL; }
    aux_sound *s = (aux_sound *)calloc(1, sizeof(aux_sound));
    if (!s) { fail("out of memory"); return NULL; }
    s->engine = engine;
    s->kind = kind;
    return s;
}

/* The sound is initialised: give it a handle and its end callback. */
static int sound_finish(aux_sound *s)
{
    int h = tbl_add(&s_sounds, s);
    if (h == 0) {
        aux_engine *e = engine_of(s->engine);
        ma_sound_uninit(&s->sound);
        if (s->decoder) { ma_decoder_uninit(s->decoder); free(s->decoder); }
        if (s->wave) { ma_waveform_uninit(s->wave); free(s->wave); }
        if (s->noise) { ma_noise_uninit(s->noise, NULL); free(s->noise); }
        blob_release(e, s->blob);
        free(s);
        return fail("out of memory");
    }
    s->handle = h;
    ma_sound_set_end_callback(&s->sound, on_sound_end, s);
    ok_clear();
    return h;
}

static unsigned s_blobSerial = 0;

static aux_blob *blob_copy(const void *bytes, size_t length)
{
    aux_blob *b = (aux_blob *)calloc(1, sizeof(aux_blob));
    if (!b) return NULL;
    b->data = malloc(length ? length : 1);
    if (!b->data) { free(b); return NULL; }
    memcpy(b->data, bytes, length);
    b->size = length;
    b->refs = 1;
    /* A name no file path can be: a path never starts with a NUL-free
     * "audioxt:" on any platform a stack would be opened from, and the
     * serial makes each unique for the life of the process. */
    snprintf(b->name, sizeof(b->name), "audioxt:mem:%u", ++s_blobSerial);
    return b;
}

/* Loads a sound file (WAV, FLAC or MP3). stream 0: decoded whole into
 * memory now, which suits short sounds played often. stream 1: decoded a
 * little at a time while it plays, which suits music. */
LC_API int aux_sound_load(int engine, const char *path, int stream)
{
    aux_engine *e = engine_of(engine);
    if (!e) return fail("no such engine");
    if (!path_ok(path)) return 0;
    aux_sound *s = sound_alloc(engine, stream ? AUX_KIND_STREAM : AUX_KIND_FILE);
    if (!s) return 0;
    ma_uint32 flags = AUX_SOUND_FLAGS | (stream ? MA_SOUND_FLAG_STREAM : MA_SOUND_FLAG_DECODE);
    ma_result r = sound_init_file(&e->engine, path, flags, &s->sound);
    if (r != MA_SUCCESS) { free(s); return fail_ma("could not load the sound file", r); }
    s->cloneable = stream ? 0 : 1;
    return sound_finish(s);
}

/* The same, from the bytes of a sound file (a custom property, a download).
 * The bytes are copied. */
LC_API int aux_sound_load_data(int engine, const void *bytes, int length, int stream)
{
    aux_engine *e = engine_of(engine);
    if (!e) return fail("no such engine");
    if (bytes == NULL || length <= 0) return fail("the data is empty");
    if (length > AUX_MAX_BYTES) return fail("the data is larger than 256 MB");
    aux_sound *s = sound_alloc(engine, stream ? AUX_KIND_DATA_STREAM : AUX_KIND_DATA);
    if (!s) return 0;
    s->blob = blob_copy(bytes, (size_t)length);
    if (!s->blob) { free(s); return fail("out of memory"); }
    ma_result r;
    if (stream) {
        s->decoder = (ma_decoder *)calloc(1, sizeof(ma_decoder));
        if (!s->decoder) { blob_release(e, s->blob); free(s); return fail("out of memory"); }
        ma_decoder_config dc = ma_decoder_config_init(ma_format_f32, 0, 0);
        r = ma_decoder_init_memory(s->blob->data, s->blob->size, &dc, s->decoder);
        if (r != MA_SUCCESS) {
            free(s->decoder); blob_release(e, s->blob); free(s);
            return fail_ma("the data is not a sound file this library reads", r);
        }
        r = ma_sound_init_from_data_source(&e->engine, s->decoder, AUX_SOUND_FLAGS, NULL, &s->sound);
        if (r != MA_SUCCESS) {
            ma_decoder_uninit(s->decoder); free(s->decoder); blob_release(e, s->blob); free(s);
            return fail_ma("could not make the sound", r);
        }
    } else {
        ma_resource_manager *rm = ma_engine_get_resource_manager(&e->engine);
        r = ma_resource_manager_register_encoded_data(rm, s->blob->name, s->blob->data, s->blob->size);
        if (r != MA_SUCCESS) { blob_release(e, s->blob); free(s); return fail_ma("could not take the data", r); }
        s->blob->registered = 1;
        r = ma_sound_init_from_file(&e->engine, s->blob->name, AUX_SOUND_FLAGS | MA_SOUND_FLAG_DECODE, NULL, NULL, &s->sound);
        if (r != MA_SUCCESS) {
            blob_release(e, s->blob); free(s);
            return fail_ma("the data is not a sound file this library reads", r);
        }
        s->cloneable = 1;
    }
    return sound_finish(s);
}

/* A sound from raw samples: interleaved, little-endian, in one of the five
 * formats. The bytes are copied; a trailing part of a frame is ignored. */
LC_API int aux_sound_from_pcm(int engine, const void *bytes, int length, const char *format, int sampleRate, int channels)
{
    aux_engine *e = engine_of(engine);
    ma_format fmt = format_of(format);
    if (!e) return fail("no such engine");
    if (fmt == ma_format_unknown) return fail("the format must be u8, s16, s24, s32 or f32");
    if (sampleRate < AUX_MIN_RATE || sampleRate > AUX_MAX_RATE) return fail("the sample rate must be 8000 to 192000");
    if (channels < 1 || channels > AUX_MAX_CHANNELS) return fail("the channel count must be 1 to 8");
    if (bytes == NULL || length <= 0) return fail("the data is empty");
    if (length > AUX_MAX_BYTES) return fail("the data is larger than 256 MB");
    ma_uint32 bpf = ma_get_bytes_per_frame(fmt, (ma_uint32)channels);
    ma_uint64 frameCount = (ma_uint64)length / bpf;
    if (frameCount == 0) return fail("the data is shorter than one frame");
    aux_sound *s = sound_alloc(engine, AUX_KIND_PCM);
    if (!s) return 0;
    s->blob = blob_copy(bytes, (size_t)(frameCount * bpf));
    if (!s->blob) { free(s); return fail("out of memory"); }
    ma_resource_manager *rm = ma_engine_get_resource_manager(&e->engine);
    ma_result r = ma_resource_manager_register_decoded_data(rm, s->blob->name, s->blob->data, frameCount, fmt,
                                                            (ma_uint32)channels, (ma_uint32)sampleRate);
    if (r != MA_SUCCESS) { blob_release(e, s->blob); free(s); return fail_ma("could not take the samples", r); }
    s->blob->registered = 1;
    r = ma_sound_init_from_file(&e->engine, s->blob->name, AUX_SOUND_FLAGS, NULL, NULL, &s->sound);
    if (r != MA_SUCCESS) { blob_release(e, s->blob); free(s); return fail_ma("could not make the sound", r); }
    s->cloneable = 1;
    return sound_finish(s);
}

/* A tone that never ends: "sine", "square", "triangle" or "sawtooth". */
LC_API int aux_sound_tone(int engine, const char *shape, double hertz, double amplitude)
{
    aux_engine *e = engine_of(engine);
    ma_waveform_type type;
    if (!e) return fail("no such engine");
    if (shape == NULL) return fail("the shape must be sine, square, triangle or sawtooth");
    if (strcmp(shape, "sine") == 0) type = ma_waveform_type_sine;
    else if (strcmp(shape, "square") == 0) type = ma_waveform_type_square;
    else if (strcmp(shape, "triangle") == 0) type = ma_waveform_type_triangle;
    else if (strcmp(shape, "sawtooth") == 0) type = ma_waveform_type_sawtooth;
    else return fail("the shape must be sine, square, triangle or sawtooth");
    if (!in_range(hertz, 1.0, 96000.0)) return fail("the frequency must be 1 to 96000");
    if (!in_range(amplitude, 0.0, 1.0)) return fail("the amplitude must be 0 to 1");
    aux_sound *s = sound_alloc(engine, AUX_KIND_TONE);
    if (!s) return 0;
    s->wave = (ma_waveform *)calloc(1, sizeof(ma_waveform));
    if (!s->wave) { free(s); return fail("out of memory"); }
    ma_waveform_config wc = ma_waveform_config_init(ma_format_f32, e->channels, e->sampleRate, type, amplitude, hertz);
    ma_result r = ma_waveform_init(&wc, s->wave);
    if (r != MA_SUCCESS) { free(s->wave); free(s); return fail_ma("could not make the tone", r); }
    r = ma_sound_init_from_data_source(&e->engine, s->wave, AUX_SOUND_FLAGS, NULL, &s->sound);
    if (r != MA_SUCCESS) { ma_waveform_uninit(s->wave); free(s->wave); free(s); return fail_ma("could not make the sound", r); }
    return sound_finish(s);
}

/* Noise that never ends: "white" or "pink". (miniaudio also has a brown
 * noise, but its samples wander far past the amplitude asked for: 1.34 for
 * 0.25, measured 2026-11-20. A sound that clips at a quarter volume is not
 * offered.) */
LC_API int aux_sound_noise(int engine, const char *color, double amplitude)
{
    aux_engine *e = engine_of(engine);
    ma_noise_type type;
    if (!e) return fail("no such engine");
    if (color == NULL) return fail("the colour must be white or pink");
    if (strcmp(color, "white") == 0) type = ma_noise_type_white;
    else if (strcmp(color, "pink") == 0) type = ma_noise_type_pink;
    else return fail("the colour must be white or pink");
    if (!in_range(amplitude, 0.0, 1.0)) return fail("the amplitude must be 0 to 1");
    aux_sound *s = sound_alloc(engine, AUX_KIND_NOISE);
    if (!s) return 0;
    s->noise = (ma_noise *)calloc(1, sizeof(ma_noise));
    if (!s->noise) { free(s); return fail("out of memory"); }
    ma_noise_config nc = ma_noise_config_init(ma_format_f32, e->channels, type, 0, amplitude);
    ma_result r = ma_noise_init(&nc, NULL, s->noise);
    if (r != MA_SUCCESS) { free(s->noise); free(s); return fail_ma("could not make the noise", r); }
    r = ma_sound_init_from_data_source(&e->engine, s->noise, AUX_SOUND_FLAGS, NULL, &s->sound);
    if (r != MA_SUCCESS) { ma_noise_uninit(s->noise, NULL); free(s->noise); free(s); return fail_ma("could not make the sound", r); }
    return sound_finish(s);
}

/* Another sound over the same samples, with its own volume, place and
 * playing state: how one loaded effect is played many times at once. Only a
 * sound that was loaded whole (not a stream, a tone or noise) can be cloned. */
LC_API int aux_sound_clone(int sound)
{
    aux_sound *src = sound_of(sound);
    if (!src) return fail("no such sound");
    aux_engine *e = engine_of(src->engine);
    if (!e) return fail("no such engine");
    if (!src->cloneable) return fail("only a sound loaded whole can be cloned (not a stream, a tone or noise)");
    aux_sound *s = sound_alloc(src->engine, src->kind);
    if (!s) return 0;
    ma_result r = ma_sound_init_copy(&e->engine, &src->sound, AUX_SOUND_FLAGS, NULL, &s->sound);
    if (r != MA_SUCCESS) { free(s); return fail_ma("could not clone the sound", r); }
    s->cloneable = 1;
    s->blob = src->blob;
    if (s->blob) s->blob->refs++;
    return sound_finish(s);
}

LC_API void aux_sound_free(int sound)
{
    aux_sound *s = sound_of(sound);
    if (s) sound_destroy(s);
}

LC_API int aux_sound_is_valid(int sound) { return sound_of(sound) ? 1 : 0; }
LC_API int aux_sound_engine(int sound) { aux_sound *s = sound_of(sound); return s ? s->engine : 0; }

/* A stop time or a fade-out left by an earlier stop would silence the next
 * start, so starting clears them. */
static void sound_disarm(aux_sound *s)
{
    if (s->stopArmed) {
        ma_sound_reset_stop_time_and_fade(&s->sound);
        s->stopArmed = 0;
    }
}

/* Plays the sound from where it is; from the beginning if it had ended. */
LC_API void aux_sound_start(int sound)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    sound_disarm(s);
    ma_sound_reset_start_time(&s->sound);
    ma_sound_start(&s->sound);
}

/* Starts the sound when the engine's clock (aux_engine_time) reaches
 * `seconds`, to the exact sample: how notes are placed on a beat. */
LC_API void aux_sound_start_at(int sound, double seconds)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    aux_engine *e = engine_of(s->engine);
    if (!e) return;
    if (!in_range(seconds, 0.0, AUX_MAX_TIME)) { fail("the time must be 0 or more seconds"); return; }
    sound_disarm(s);
    ma_sound_set_start_time_in_pcm_frames(&s->sound, (ma_uint64)(seconds * (double)e->sampleRate));
    ma_sound_start(&s->sound);
}

/* Stops the sound where it is; aux_sound_start carries on from there. */
LC_API void aux_sound_stop(int sound)
{
    aux_sound *s = sound_of(sound);
    if (s) ma_sound_stop(&s->sound);
}

/* Stops the sound when the engine's clock reaches `seconds`. */
LC_API void aux_sound_stop_at(int sound, double seconds)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    aux_engine *e = engine_of(s->engine);
    if (!e) return;
    if (!in_range(seconds, 0.0, AUX_MAX_TIME)) { fail("the time must be 0 or more seconds"); return; }
    ma_sound_set_stop_time_in_pcm_frames(&s->sound, (ma_uint64)(seconds * (double)e->sampleRate));
    s->stopArmed = 1;
}

/* Fades the sound out over `seconds` and then stops it. */
LC_API void aux_sound_stop_with_fade(int sound, double seconds)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    if (!in_range(seconds, 0.0, 3600.0)) { fail("the fade must be 0 to 3600 seconds"); return; }
    ma_sound_stop_with_fade_in_milliseconds(&s->sound, (ma_uint64)(seconds * 1000.0));
    s->stopArmed = 1;
}

/* Moves the sound's volume from one level to another over `seconds`,
 * starting now. A `from` of -1 means "from where it is now". The fade
 * multiplies the sound's own volume; it does not replace it. */
LC_API void aux_sound_fade(int sound, double from, double to, double seconds)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    if (!(from == -1.0 || in_range(from, 0.0, AUX_MAX_VOLUME)) || !in_range(to, 0.0, AUX_MAX_VOLUME)
        || !in_range(seconds, 0.0, 3600.0)) {
        fail("a fade needs volumes of 0 to 100 (or -1 for the current one) and 0 to 3600 seconds");
        return;
    }
    ma_sound_set_fade_in_milliseconds(&s->sound, (float)from, (float)to, (ma_uint64)(seconds * 1000.0));
}

LC_API int aux_sound_is_playing(int sound)
{
    aux_sound *s = sound_of(sound);
    return (s && ma_sound_is_playing(&s->sound)) ? 1 : 0;
}

LC_API int aux_sound_at_end(int sound)
{
    aux_sound *s = sound_of(sound);
    return (s && ma_sound_at_end(&s->sound)) ? 1 : 0;
}

/* Moves the playing position to `seconds` from the start. */
LC_API void aux_sound_seek(int sound, double seconds)
{
    aux_sound *s = sound_of(sound);
    ma_uint32 rate = 0;
    if (!s) return;
    if (!in_range(seconds, 0.0, AUX_MAX_TIME)) { fail("the position must be 0 or more seconds"); return; }
    if (ma_sound_get_data_format(&s->sound, NULL, NULL, &rate, NULL, 0) != MA_SUCCESS || rate == 0) return;
    ma_result r = ma_sound_seek_to_pcm_frame(&s->sound, (ma_uint64)(seconds * (double)rate));
    if (r != MA_SUCCESS) fail_ma("could not move to that position", r);
}

LC_API double aux_sound_position(int sound)
{
    aux_sound *s = sound_of(sound);
    float v = 0.0f;
    if (!s) return 0.0;
    if (ma_sound_get_cursor_in_seconds(&s->sound, &v) != MA_SUCCESS) return 0.0;
    return fin(v) ? (double)v : 0.0;
}

/* The length in seconds; 0 for a tone or noise, which have no end. */
LC_API double aux_sound_length(int sound)
{
    aux_sound *s = sound_of(sound);
    float v = 0.0f;
    if (!s || s->kind == AUX_KIND_TONE || s->kind == AUX_KIND_NOISE) return 0.0;
    if (ma_sound_get_length_in_seconds(&s->sound, &v) != MA_SUCCESS) return 0.0;
    return fin(v) ? (double)v : 0.0;
}

LC_API void aux_sound_set_volume(int sound, double volume)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    if (!in_range(volume, 0.0, AUX_MAX_VOLUME)) { fail("the volume must be 0 to 100 (1 is unchanged)"); return; }
    ma_sound_set_volume(&s->sound, (float)volume);
}

LC_API double aux_sound_volume(int sound)
{
    aux_sound *s = sound_of(sound);
    return s ? (double)ma_sound_get_volume(&s->sound) : 0.0;
}

/* -1 is all the way left, 0 the middle, 1 all the way right. */
LC_API void aux_sound_set_pan(int sound, double pan)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    if (!in_range(pan, -1.0, 1.0)) { fail("the pan must be -1 (left) to 1 (right)"); return; }
    ma_sound_set_pan(&s->sound, (float)pan);
}

LC_API double aux_sound_pan(int sound)
{
    aux_sound *s = sound_of(sound);
    return s ? (double)ma_sound_get_pan(&s->sound) : 0.0;
}

/* 1 is the recorded pitch, 2 an octave up (and twice as fast), 0.5 an
 * octave down. */
LC_API void aux_sound_set_pitch(int sound, double pitch)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    if (!in_range(pitch, AUX_MIN_PITCH, AUX_MAX_PITCH)) { fail("the pitch must be 0.01 to 100 (1 is unchanged)"); return; }
    ma_sound_set_pitch(&s->sound, (float)pitch);
}

LC_API double aux_sound_pitch(int sound)
{
    aux_sound *s = sound_of(sound);
    return s ? (double)ma_sound_get_pitch(&s->sound) : 0.0;
}

LC_API void aux_sound_set_looping(int sound, int flag)
{
    aux_sound *s = sound_of(sound);
    if (s) ma_sound_set_looping(&s->sound, flag ? MA_TRUE : MA_FALSE);
}

LC_API int aux_sound_is_looping(int sound)
{
    aux_sound *s = sound_of(sound);
    return (s && ma_sound_is_looping(&s->sound)) ? 1 : 0;
}

/* The part of the sound a loop repeats, in seconds from its start. An end
 * of 0 means "to the end of the sound". Looping itself is
 * aux_sound_set_looping. Not for a tone or noise. */
LC_API void aux_sound_set_loop_range(int sound, double startSeconds, double endSeconds)
{
    aux_sound *s = sound_of(sound);
    ma_uint32 rate = 0;
    if (!s) return;
    if (s->kind == AUX_KIND_TONE || s->kind == AUX_KIND_NOISE) { fail("a tone or noise has no loop range"); return; }
    if (!in_range(startSeconds, 0.0, AUX_MAX_TIME) || !in_range(endSeconds, 0.0, AUX_MAX_TIME)
        || (endSeconds != 0.0 && endSeconds <= startSeconds)) {
        fail("a loop range needs a start of 0 or more and an end after it (or 0 for the end of the sound)");
        return;
    }
    if (ma_sound_get_data_format(&s->sound, NULL, NULL, &rate, NULL, 0) != MA_SUCCESS || rate == 0) return;
    ma_uint64 begin = (ma_uint64)(startSeconds * (double)rate);
    ma_uint64 end = endSeconds == 0.0 ? ~(ma_uint64)0 : (ma_uint64)(endSeconds * (double)rate);
    ma_result r = ma_data_source_set_loop_point_in_pcm_frames(ma_sound_get_data_source(&s->sound), begin, end);
    if (r != MA_SUCCESS) fail_ma("could not set the loop range", r);
}

/* The frequency of a tone made by aux_sound_tone, changed while it plays. */
LC_API void aux_sound_set_frequency(int sound, double hertz)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    if (s->kind != AUX_KIND_TONE) { fail("only a tone has a frequency"); return; }
    if (!in_range(hertz, 1.0, 96000.0)) { fail("the frequency must be 1 to 96000"); return; }
    ma_waveform_set_frequency(s->wave, hertz);
}

/* A sound marked this way is freed by the aux_poll_ended that reports its end:
 * play it and forget it. */
LC_API void aux_sound_set_auto_free(int sound, int flag)
{
    aux_sound *s = sound_of(sound);
    if (s) s->autoFree = flag ? 1 : 0;
}

/* Routes the sound through a group (aux_group_create), or with 0 straight
 * to the engine's output again. */
LC_API void aux_sound_set_group(int sound, int group)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    aux_engine *e = engine_of(s->engine);
    if (!e) return;
    if (group == 0) {
        ma_node_attach_output_bus(&s->sound, 0, ma_engine_get_endpoint(&e->engine), 0);
        s->group = 0;
        return;
    }
    aux_group *g = group_of(group);
    if (!g) { fail("no such group"); return; }
    if (g->engine != s->engine) { fail("the sound and the group belong to different engines"); return; }
    ma_node_attach_output_bus(&s->sound, 0, &g->group, 0);
    s->group = group;
}

LC_API int aux_sound_group(int sound) { aux_sound *s = sound_of(sound); return s ? s->group : 0; }

/* ---- 3D: a sound with a place, heard from the engine's listener ---- */
LC_API void aux_sound_set_spatial(int sound, int flag)
{
    aux_sound *s = sound_of(sound);
    if (s) ma_sound_set_spatialization_enabled(&s->sound, flag ? MA_TRUE : MA_FALSE);
}

LC_API int aux_sound_is_spatial(int sound)
{
    aux_sound *s = sound_of(sound);
    return (s && ma_sound_is_spatialization_enabled(&s->sound)) ? 1 : 0;
}

LC_API void aux_sound_set_position(int sound, double x, double y, double z)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    if (!coord_ok(x, y, z)) { fail("a coordinate is not a number, or is beyond a million"); return; }
    ma_sound_set_position(&s->sound, (float)x, (float)y, (float)z);
}

LC_API const char *aux_sound_position_xyz(int sound)
{
    aux_sound *s = sound_of(sound);
    return s ? text_vec(ma_sound_get_position(&s->sound)) : text_empty();
}

/* The sound's velocity, for the Doppler effect only: it moves nothing. */
LC_API void aux_sound_set_velocity(int sound, double x, double y, double z)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    if (!coord_ok(x, y, z)) { fail("a coordinate is not a number, or is beyond a million"); return; }
    ma_sound_set_velocity(&s->sound, (float)x, (float)y, (float)z);
}

/* Nearer than `nearest` the sound is at full volume; beyond `farthest` it
 * gets no quieter. */
LC_API void aux_sound_set_distance_range(int sound, double nearest, double farthest)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    if (!in_range(nearest, 0.001, AUX_MAX_COORD) || !in_range(farthest, 0.001, AUX_MAX_COORD) || farthest < nearest) {
        fail("a distance range needs a nearest of 0.001 or more and a farthest not below it");
        return;
    }
    ma_sound_set_min_distance(&s->sound, (float)nearest);
    ma_sound_set_max_distance(&s->sound, (float)farthest);
}

/* How fast the sound fades with distance: 1 is natural, 0 not at all. */
LC_API void aux_sound_set_rolloff(int sound, double rolloff)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    if (!in_range(rolloff, 0.0, 100.0)) { fail("the rolloff must be 0 to 100 (1 is natural)"); return; }
    ma_sound_set_rolloff(&s->sound, (float)rolloff);
}

/* How strong the Doppler effect is: 1 is natural, 0 turns it off. */
LC_API void aux_sound_set_doppler(int sound, double factor)
{
    aux_sound *s = sound_of(sound);
    if (!s) return;
    if (!in_range(factor, 0.0, 100.0)) { fail("the Doppler factor must be 0 to 100 (1 is natural)"); return; }
    ma_sound_set_doppler_factor(&s->sound, (float)factor);
}

/* ------------------------------------------------------------------ */
/* Groups: several sounds behind one volume ("music", "effects").      */
/* ------------------------------------------------------------------ */
LC_API int aux_group_create(int engine)
{
    aux_engine *e = engine_of(engine);
    if (!e) return fail("no such engine");
    if (s_groups.live >= s_groups.limit) return fail("too many groups (1024 at most)");
    aux_group *g = (aux_group *)calloc(1, sizeof(aux_group));
    if (!g) return fail("out of memory");
    ma_result r = ma_sound_group_init(&e->engine, AUX_SOUND_FLAGS, NULL, &g->group);
    if (r != MA_SUCCESS) { free(g); return fail_ma("could not make the group", r); }
    g->engine = engine;
    int h = tbl_add(&s_groups, g);
    if (h == 0) { ma_sound_group_uninit(&g->group); free(g); return fail("out of memory"); }
    g->handle = h;
    ok_clear();
    return h;
}

/* Frees a group. Its sounds are not freed: they play straight to the
 * engine's output again. */
LC_API void aux_group_free(int group)
{
    aux_group *g = group_of(group);
    if (g) group_destroy(g);
}

LC_API int aux_group_is_valid(int group) { return group_of(group) ? 1 : 0; }

LC_API void aux_group_set_volume(int group, double volume)
{
    aux_group *g = group_of(group);
    if (!g) return;
    if (!in_range(volume, 0.0, AUX_MAX_VOLUME)) { fail("the volume must be 0 to 100 (1 is unchanged)"); return; }
    ma_sound_group_set_volume(&g->group, (float)volume);
}

LC_API double aux_group_volume(int group)
{
    aux_group *g = group_of(group);
    return g ? (double)ma_sound_group_get_volume(&g->group) : 0.0;
}

LC_API void aux_group_set_pan(int group, double pan)
{
    aux_group *g = group_of(group);
    if (!g) return;
    if (!in_range(pan, -1.0, 1.0)) { fail("the pan must be -1 (left) to 1 (right)"); return; }
    ma_sound_group_set_pan(&g->group, (float)pan);
}

LC_API double aux_group_pan(int group)
{
    aux_group *g = group_of(group);
    return g ? (double)ma_sound_group_get_pan(&g->group) : 0.0;
}

LC_API void aux_group_set_pitch(int group, double pitch)
{
    aux_group *g = group_of(group);
    if (!g) return;
    if (!in_range(pitch, AUX_MIN_PITCH, AUX_MAX_PITCH)) { fail("the pitch must be 0.01 to 100 (1 is unchanged)"); return; }
    ma_sound_group_set_pitch(&g->group, (float)pitch);
}

LC_API double aux_group_pitch(int group)
{
    aux_group *g = group_of(group);
    return g ? (double)ma_sound_group_get_pitch(&g->group) : 0.0;
}

/* Lets the group's sounds be heard again after aux_group_stop. */
LC_API void aux_group_start(int group)
{
    aux_group *g = group_of(group);
    if (g) ma_sound_group_start(&g->group);
}

/* Silences the group: its sounds keep their own playing state, and are
 * heard again from aux_group_start. */
LC_API void aux_group_stop(int group)
{
    aux_group *g = group_of(group);
    if (g) ma_sound_group_stop(&g->group);
}

/* ------------------------------------------------------------------ */
/* Events: which sounds have ended. Polled, never called (rule 1).     */
/* ------------------------------------------------------------------ */
static int *s_ended = NULL;
static int  s_endedCap = 0;
static int  s_endedCount = 0;

/* Collects every sound that reached its end since the last poll, frees the
 * ones marked auto-free, and returns how many there were. Read them with
 * aux_ended_sound(1..n). A looping sound never ends; a stopped one has not
 * ended. */
LC_API int aux_poll_ended(void)
{
    s_endedCount = 0;
    for (int i = 0; i < s_engines.count; i++) {
        aux_engine *e = (aux_engine *)s_engines.item[i];
        if (e) pump_jobs(e);
    }
    for (int i = 0; i < s_sounds.count; i++) {
        aux_sound *s = (aux_sound *)s_sounds.item[i];
        if (!s) continue;
        if (ma_atomic_exchange_32(&s->ended, 0) == 0) continue;
        if (s_endedCount >= s_endedCap) {
            int nc = s_endedCap ? s_endedCap * 2 : 64;
            int *ne = (int *)realloc(s_ended, (size_t)nc * sizeof(int));
            if (!ne) {
                /* No room to report it: put the flag back for the next poll. */
                ma_atomic_exchange_32(&s->ended, 1);
                break;
            }
            s_ended = ne;
            s_endedCap = nc;
        }
        s_ended[s_endedCount++] = s->handle;
        if (s->autoFree) sound_destroy(s);
    }
    return s_endedCount;
}

/* The handle of the index-th sound the last aux_poll_ended found (from 1). An
 * auto-freed sound's handle is still returned, so a script can tell which
 * one it was; it is no longer valid. */
LC_API int aux_ended_sound(int index)
{
    if (index < 1 || index > s_endedCount) return 0;
    return s_ended[index - 1];
}

/* ------------------------------------------------------------------ */
/* Capture: the microphone                                             */
/* ------------------------------------------------------------------ */
static float sample_abs(ma_format fmt, const ma_uint8 *p)
{
    switch (fmt) {
        case ma_format_u8:  { float v = ((float)p[0] - 128.0f) / 128.0f; return v < 0 ? -v : v; }
        case ma_format_s16: { ma_int16 v; memcpy(&v, p, 2); float f = (float)v / 32768.0f; return f < 0 ? -f : f; }
        case ma_format_s24: {
            ma_int32 v = (ma_int32)(((ma_uint32)p[0] << 8) | ((ma_uint32)p[1] << 16) | ((ma_uint32)p[2] << 24)) >> 8;
            float f = (float)v / 8388608.0f; return f < 0 ? -f : f;
        }
        case ma_format_s32: { ma_int32 v; memcpy(&v, p, 4); float f = (float)((double)v / 2147483648.0); return f < 0 ? -f : f; }
        case ma_format_f32: { float v; memcpy(&v, p, 4); if (!(v == v)) return 0.0f; return v < 0 ? -v : v; }
        default: return 0.0f;
    }
}

/* Runs on the CAPTURE thread. It copies what arrived into the ring (what
 * does not fit is counted and dropped: the newest sound, so that what a
 * slow script reads is still continuous), keeps the peak, and appends to
 * the WAV file when one is being recorded. It calls nothing of the engine. */
static void on_capture(ma_device *device, void *output, const void *input, ma_uint32 frameCount)
{
    aux_capture *c = (aux_capture *)device->pUserData;
    const ma_uint8 *src = (const ma_uint8 *)input;
    (void)output;
    if (c == NULL || src == NULL || frameCount == 0) return;

    float peak = 0.0f;
    ma_uint32 bps = c->bytesPerFrame / c->channels;
    ma_uint32 samples = frameCount * c->channels;
    for (ma_uint32 i = 0; i < samples; i++) {
        float a = sample_abs(c->format, src + (size_t)i * bps);
        if (a > peak) peak = a;
    }
    ma_spinlock_lock(&c->peakLock);
    if (peak > c->peak) c->peak = peak;
    ma_spinlock_unlock(&c->peakLock);

    ma_uint32 left = frameCount;
    const ma_uint8 *at = src;
    while (left > 0) {
        ma_uint32 n = left;
        void *dst = NULL;
        if (ma_pcm_rb_acquire_write(&c->ring, &n, &dst) != MA_SUCCESS || n == 0) break;
        memcpy(dst, at, (size_t)n * c->bytesPerFrame);
        ma_pcm_rb_commit_write(&c->ring, n);
        at += (size_t)n * c->bytesPerFrame;
        left -= n;
    }
    if (left > 0) ma_atomic_fetch_add_32(&c->dropped, left);

    ma_mutex_lock(&c->fileLock);
    if (c->recording) {
        ma_uint64 wrote = 0;
        ma_encoder_write_pcm_frames(c->encoder, src, frameCount, &wrote);
        c->recordedFrames += wrote;
    }
    ma_mutex_unlock(&c->fileLock);
}

/* Opens a microphone (or any input). device: 0 the default, 1..n a capture
 * device of the last aux_device_scan, -1 the silent test device. The
 * samples arrive in exactly the format, rate and channel count asked for
 * (miniaudio converts). bufferSeconds is how much sound is kept for a
 * script that has not read yet; beyond it the newest sound is dropped and
 * counted. Recording does not begin until aux_capture_start. */
LC_API int aux_capture_open(int device, const char *format, int sampleRate, int channels, double bufferSeconds)
{
    ma_context *ctx = NULL;
    ma_device_id *id = NULL;
    ma_format fmt = format_of(format);
    if (fmt == ma_format_unknown) return fail("the format must be u8, s16, s24, s32 or f32");
    if (sampleRate < AUX_MIN_RATE || sampleRate > AUX_MAX_RATE) return fail("the sample rate must be 8000 to 192000");
    if (channels < 1 || channels > AUX_MAX_CHANNELS) return fail("the channel count must be 1 to 8");
    if (!in_range(bufferSeconds, 0.1, 600.0)) return fail("the buffer must hold 0.1 to 600 seconds");
    if (s_captures.live >= s_captures.limit) return fail("too many captures are open (16 at most)");
    ma_uint32 bpf = ma_get_bytes_per_frame(fmt, (ma_uint32)channels);
    double ringFrames = bufferSeconds * (double)sampleRate;
    if (ringFrames * (double)bpf > (double)AUX_MAX_BYTES) return fail("that buffer would be larger than 256 MB");
    if (!device_pick(device, 1, &ctx, &id)) return 0;

    aux_capture *c = (aux_capture *)calloc(1, sizeof(aux_capture));
    if (!c) return fail("out of memory");
    c->format = fmt;
    c->channels = (ma_uint32)channels;
    c->sampleRate = (ma_uint32)sampleRate;
    c->bytesPerFrame = bpf;
    if (ma_pcm_rb_init(fmt, (ma_uint32)channels, (ma_uint32)ringFrames, NULL, NULL, &c->ring) != MA_SUCCESS) {
        free(c);
        return fail("out of memory");
    }
    if (ma_mutex_init(&c->fileLock) != MA_SUCCESS) {
        ma_pcm_rb_uninit(&c->ring);
        free(c);
        return fail("out of memory");
    }
    ma_device_config cfg = ma_device_config_init(ma_device_type_capture);
    cfg.capture.pDeviceID = id;
    cfg.capture.format = fmt;
    cfg.capture.channels = (ma_uint32)channels;
    cfg.sampleRate = (ma_uint32)sampleRate;
    cfg.dataCallback = on_capture;
    cfg.pUserData = c;
    ma_result r = ma_device_init(ctx, &cfg, &c->device);
    if (r != MA_SUCCESS) {
        ma_mutex_uninit(&c->fileLock);
        ma_pcm_rb_uninit(&c->ring);
        free(c);
        return fail_ma("could not open the capture device", r);
    }
    ma_device_get_name(&c->device, ma_device_type_capture, c->deviceName, sizeof(c->deviceName), NULL);
    int h = tbl_add(&s_captures, c);
    if (h == 0) {
        ma_device_uninit(&c->device);
        ma_mutex_uninit(&c->fileLock);
        ma_pcm_rb_uninit(&c->ring);
        free(c);
        return fail("out of memory");
    }
    c->handle = h;
    ok_clear();
    return h;
}

static void capture_destroy(aux_capture *c)
{
    tbl_remove(&s_captures, c->handle);
    /* The device first: after ma_device_uninit its thread is gone, so the
     * file and the ring can be closed with nobody else looking. */
    ma_device_uninit(&c->device);
    if (c->recording) { ma_encoder_uninit(c->encoder); free(c->encoder); c->encoder = NULL; c->recording = 0; }
    ma_mutex_uninit(&c->fileLock);
    ma_pcm_rb_uninit(&c->ring);
    free(c);
}

/* Closes the device. A WAV file being recorded is finished and closed. */
LC_API void aux_capture_close(int capture)
{
    aux_capture *c = capture_of(capture);
    if (c) capture_destroy(c);
}

LC_API int aux_capture_is_valid(int capture) { return capture_of(capture) ? 1 : 0; }

/* Returns 1 if the device is now running, 0 if it could not be started. */
LC_API int aux_capture_start(int capture)
{
    aux_capture *c = capture_of(capture);
    if (!c) return 0;
    if (ma_device_is_started(&c->device)) return 1;
    ma_result r = ma_device_start(&c->device);
    if (r != MA_SUCCESS) return fail_ma("could not start the capture device", r);
    return 1;
}

LC_API void aux_capture_stop(int capture)
{
    aux_capture *c = capture_of(capture);
    if (c && ma_device_is_started(&c->device)) ma_device_stop(&c->device);
}

LC_API int aux_capture_is_running(int capture)
{
    aux_capture *c = capture_of(capture);
    return (c && ma_device_is_started(&c->device)) ? 1 : 0;
}

/* Bytes waiting to be read (whole frames). */
LC_API int aux_capture_available(int capture)
{
    aux_capture *c = capture_of(capture);
    if (!c) return 0;
    return (int)(ma_pcm_rb_available_read(&c->ring) * c->bytesPerFrame);
}

/* Moves everything that has arrived since the last read into the out
 * buffer and returns its byte count (0 when nothing has). */
LC_API int aux_capture_read(int capture)
{
    aux_capture *c = capture_of(capture);
    size_t total = 0;
    if (!c) return 0;
    ma_uint32 avail = ma_pcm_rb_available_read(&c->ring);
    if (avail == 0) return 0;
    if (!out_reserve((size_t)avail * c->bytesPerFrame)) return fail("out of memory");
    ma_uint32 left = avail;
    while (left > 0) {
        ma_uint32 n = left;
        void *src = NULL;
        if (ma_pcm_rb_acquire_read(&c->ring, &n, &src) != MA_SUCCESS || n == 0) break;
        memcpy(s_out + total, src, (size_t)n * c->bytesPerFrame);
        ma_pcm_rb_commit_read(&c->ring, n);
        total += (size_t)n * c->bytesPerFrame;
        left -= n;
    }
    s_outRate = (int)c->sampleRate;
    s_outChannels = (int)c->channels;
    return (int)total;
}

LC_API const char *aux_capture_format(int capture)
{
    aux_capture *c = capture_of(capture);
    return c ? text_copy(format_name(c->format)) : text_empty();
}

LC_API int aux_capture_sample_rate(int capture) { aux_capture *c = capture_of(capture); return c ? (int)c->sampleRate : 0; }
LC_API int aux_capture_channels(int capture) { aux_capture *c = capture_of(capture); return c ? (int)c->channels : 0; }

LC_API const char *aux_capture_device_label(int capture)
{
    aux_capture *c = capture_of(capture);
    return c ? text_copy(c->deviceName) : text_empty();
}

/* Frames dropped because the script did not read in time, since the device
 * was opened. */
LC_API int aux_capture_dropped(int capture)
{
    aux_capture *c = capture_of(capture);
    if (!c) return 0;
    ma_uint32 d = ma_atomic_load_32(&c->dropped);
    return d > 0x7FFFFFFFu ? 0x7FFFFFFF : (int)d;
}

/* The loudest sample since the last call, 0 to 1: an input level meter.
 * Reading resets it. */
LC_API double aux_capture_peak(int capture)
{
    aux_capture *c = capture_of(capture);
    float v;
    if (!c) return 0.0;
    ma_spinlock_lock(&c->peakLock);
    v = c->peak;
    c->peak = 0.0f;
    ma_spinlock_unlock(&c->peakLock);
    return (double)v;
}

/* Begins writing everything the device hears to a WAV file, in the
 * capture's own format, until aux_capture_record_stop or the device is
 * closed. Reading with aux_capture_read goes on working beside it. */
LC_API int aux_capture_record_start(int capture, const char *savePath)
{
    aux_capture *c = capture_of(capture);
    if (!c) return fail("no such capture");
    if (!path_ok(savePath)) return 0;
    if (c->recording) return fail("this capture is already recording to a file");
    ma_encoder_config cfg = ma_encoder_config_init(ma_encoding_format_wav, c->format, c->channels, c->sampleRate);
    /* The encoder is opened OUTSIDE the lock (opening a file can take a
     * while and the capture thread must not wait on it), in a block of its
     * own, and only the pointer is handed over under the lock. Never by
     * value: the smoke test's first run (2026-11-20, ASan) caught a copied
     * encoder writing through a pointer to the copy it was made from. */
    ma_encoder *spare = (ma_encoder *)calloc(1, sizeof(ma_encoder));
    if (!spare) return fail("out of memory");
    ma_result r = encoder_init_path(savePath, &cfg, spare);
    if (r != MA_SUCCESS) { free(spare); return fail_ma("could not create the file", r); }
    ma_mutex_lock(&c->fileLock);
    c->encoder = spare;
    c->recordedFrames = 0;
    c->recording = 1;
    ma_mutex_unlock(&c->fileLock);
    ok_clear();
    return 1;
}

/* Finishes the WAV file. Returns the seconds of sound written to it. */
LC_API double aux_capture_record_stop(int capture)
{
    aux_capture *c = capture_of(capture);
    ma_encoder *done;
    ma_uint64 frames;
    if (!c || !c->recording) return 0.0;
    ma_mutex_lock(&c->fileLock);
    done = c->encoder;
    c->encoder = NULL;
    frames = c->recordedFrames;
    c->recording = 0;
    ma_mutex_unlock(&c->fileLock);
    ma_encoder_uninit(done);
    free(done);
    return (double)frames / (double)c->sampleRate;
}

LC_API int aux_capture_is_recording(int capture)
{
    aux_capture *c = capture_of(capture);
    return (c && c->recording) ? 1 : 0;
}

/* ------------------------------------------------------------------ */
/* Decoding and encoding without a device                              */
/* ------------------------------------------------------------------ */

/* Reads a whole decoder into the out buffer. */
static int decode_all(ma_decoder *d)
{
    ma_uint32 bpf = ma_get_bytes_per_frame(d->outputFormat, d->outputChannels);
    size_t total = 0;
    if (bpf == 0) return fail("the sound has no format");
    for (;;) {
        ma_uint64 got = 0;
        size_t want = 65536;
        if (total + want * bpf > (size_t)AUX_MAX_BYTES) return fail("the decoded sound is larger than 256 MB");
        if (!out_reserve(total + want * bpf)) return fail("out of memory");
        ma_result r = ma_decoder_read_pcm_frames(d, s_out + total, want, &got);
        total += (size_t)got * bpf;
        if (r != MA_SUCCESS || got == 0) break;
    }
    s_outRate = (int)d->outputSampleRate;
    s_outChannels = (int)d->outputChannels;
    ok_clear();
    return (int)total;
}

static int decode_args(const char *format, int sampleRate, int channels, ma_format *fmt)
{
    *fmt = format_of(format);
    if (*fmt == ma_format_unknown) return fail("the format must be u8, s16, s24, s32 or f32");
    if (sampleRate != 0 && (sampleRate < AUX_MIN_RATE || sampleRate > AUX_MAX_RATE))
        return fail("the sample rate must be 0 (the file's own) or 8000 to 192000");
    if (channels < 0 || channels > AUX_MAX_CHANNELS) return fail("the channel count must be 0 (the file's own) or 1 to 8");
    return 1;
}

/* Decodes a whole sound file into the out buffer as raw samples in
 * `format`. sampleRate and channels: 0 keeps the file's own, another value
 * converts. Returns the byte count; aux_out_sample_rate and
 * aux_out_channels then say what the samples are. */
LC_API int aux_decode_file(const char *path, const char *format, int sampleRate, int channels)
{
    ma_format fmt;
    ma_decoder d;
    if (!path_ok(path)) return 0;
    if (!decode_args(format, sampleRate, channels, &fmt)) return 0;
    ma_decoder_config cfg = ma_decoder_config_init(fmt, (ma_uint32)channels, (ma_uint32)sampleRate);
    ma_result r = decoder_init_path(path, &cfg, &d);
    if (r != MA_SUCCESS) return fail_ma("could not read the sound file", r);
    int n = decode_all(&d);
    ma_decoder_uninit(&d);
    return n;
}

/* The same, from the bytes of a sound file. */
LC_API int aux_decode_data(const void *bytes, int length, const char *format, int sampleRate, int channels)
{
    ma_format fmt;
    ma_decoder d;
    if (bytes == NULL || length <= 0) return fail("the data is empty");
    if (!decode_args(format, sampleRate, channels, &fmt)) return 0;
    /* The out buffer is where the result goes, and a caller may hand back
     * bytes that came from it: decode from a copy. */
    void *copy = malloc((size_t)length);
    if (!copy) return fail("out of memory");
    memcpy(copy, bytes, (size_t)length);
    ma_decoder_config cfg = ma_decoder_config_init(fmt, (ma_uint32)channels, (ma_uint32)sampleRate);
    ma_result r = ma_decoder_init_memory(copy, (size_t)length, &cfg, &d);
    if (r != MA_SUCCESS) { free(copy); return fail_ma("the data is not a sound file this library reads", r); }
    int n = decode_all(&d);
    ma_decoder_uninit(&d);
    free(copy);
    return n;
}

/* The WAV encoder writes to memory through these two: the file is built in
 * a buffer of its own and then moved to the out buffer. */
typedef struct {
    unsigned char *data;
    size_t size, cap, at;
} aux_membuf;

static ma_result mem_write(ma_encoder *enc, const void *bytes, size_t count, size_t *written)
{
    aux_membuf *m = (aux_membuf *)enc->pUserData;
    if (written) *written = 0;
    if (m->at + count > (size_t)AUX_MAX_BYTES) return MA_OUT_OF_MEMORY;
    if (m->at + count > m->cap) {
        size_t nc = m->cap ? m->cap : 65536;
        while (nc < m->at + count) nc *= 2;
        unsigned char *nb = (unsigned char *)realloc(m->data, nc);
        if (!nb) return MA_OUT_OF_MEMORY;
        m->data = nb;
        m->cap = nc;
    }
    memcpy(m->data + m->at, bytes, count);
    m->at += count;
    if (m->at > m->size) m->size = m->at;
    if (written) *written = count;
    return MA_SUCCESS;
}

static ma_result mem_seek(ma_encoder *enc, ma_int64 offset, ma_seek_origin origin)
{
    aux_membuf *m = (aux_membuf *)enc->pUserData;
    ma_int64 base = origin == ma_seek_origin_start ? 0 : origin == ma_seek_origin_current ? (ma_int64)m->at : (ma_int64)m->size;
    ma_int64 to = base + offset;
    if (to < 0 || to > (ma_int64)m->size) return MA_BAD_SEEK;
    m->at = (size_t)to;
    return MA_SUCCESS;
}

/* Wraps raw samples as a WAV file, left in the out buffer: what a script
 * writes to disk to save a recording or a rendered mix. Returns the byte
 * count of the file. */
LC_API int aux_wav_encode(const void *bytes, int length, const char *format, int sampleRate, int channels)
{
    ma_format fmt = format_of(format);
    aux_membuf m = { NULL, 0, 0, 0 };
    ma_encoder enc;
    if (fmt == ma_format_unknown) return fail("the format must be u8, s16, s24, s32 or f32");
    if (sampleRate < AUX_MIN_RATE || sampleRate > AUX_MAX_RATE) return fail("the sample rate must be 8000 to 192000");
    if (channels < 1 || channels > AUX_MAX_CHANNELS) return fail("the channel count must be 1 to 8");
    if (bytes == NULL || length <= 0) return fail("the data is empty");
    ma_uint32 bpf = ma_get_bytes_per_frame(fmt, (ma_uint32)channels);
    ma_uint64 frames = (ma_uint64)length / bpf;
    if (frames == 0) return fail("the data is shorter than one frame");
    ma_encoder_config cfg = ma_encoder_config_init(ma_encoding_format_wav, fmt, (ma_uint32)channels, (ma_uint32)sampleRate);
    ma_result r = ma_encoder_init(mem_write, mem_seek, &m, &cfg, &enc);
    if (r != MA_SUCCESS) { free(m.data); return fail_ma("could not make the WAV file", r); }
    r = ma_encoder_write_pcm_frames(&enc, bytes, frames, NULL);
    ma_encoder_uninit(&enc);
    if (r != MA_SUCCESS) { free(m.data); return fail_ma("could not make the WAV file", r); }
    if (!out_reserve(m.size)) { free(m.data); return fail("out of memory"); }
    memcpy(s_out, m.data, m.size);
    free(m.data);
    s_outRate = sampleRate;
    s_outChannels = channels;
    ok_clear();
    return (int)m.size;
}

/* ------------------------------------------------------------------ */
/* Teardown                                                            */
/* ------------------------------------------------------------------ */

/* Closes every capture and engine (and so frees every sound and group) and
 * lets the audio system go. Safe to call twice, and the library works again
 * afterwards: the next call that needs a device opens the audio system
 * afresh. A stack calls it on closeStack. */
LC_API void aux_shut_down(void)
{
    for (int i = 0; i < s_captures.count; i++) {
        aux_capture *c = (aux_capture *)s_captures.item[i];
        if (c) capture_destroy(c);
    }
    for (int i = 0; i < s_engines.count; i++) {
        aux_engine *e = (aux_engine *)s_engines.item[i];
        if (e) aux_engine_free(e->handle);
    }
    if (s_ctxState == 1) ma_context_uninit(&s_ctx);
    s_ctxState = 0;
    if (s_nullCtxState == 1) ma_context_uninit(&s_nullCtx);
    s_nullCtxState = 0;
    s_playbackCount = 0;
    s_captureCount = 0;
    s_endedCount = 0;
    free(s_out);
    s_out = NULL;
    s_outCap = 0;
    s_outRate = 0;
    s_outChannels = 0;
    ok_clear();
}
