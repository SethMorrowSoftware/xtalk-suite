/*
 * tests/mock/rtmidi_mock.c -- the controllable RtMidi test double behind
 * tests/mock/rtmidi_c.h. It is compiled into two things:
 *
 *   1. midi_mock_smoke (C): midi_shim.c + this file, driven from C through the
 *      mock_* globals/functions.
 *   2. the MOCK midixt shared library (CMake target midixt_mock, OUTPUT_NAME
 *      "midixt", emitted under <build>/mock/): midi_shim.c + this file, a drop-in
 *      for the real midixt.{so,dll,dylib}. The headless LCB suite
 *      (tests/lcb/midi_test.lcb, run by tools/run-lcb-tests.py under lc-run) and
 *      the engine suite (tests/lcs/) load it in place of the real library, so the
 *      WHOLE MIDI stack -- the .lcb binding, the FFI marshalling, the shim's
 *      handle table / drain / stash -- runs end to end with NO MIDI hardware, no
 *      OS MIDI service, and no loopMIDI/IAC/aconnect.
 *
 * Beyond injecting inbound messages it models a VIRTUAL CABLE: with loopback on,
 * every message an output port sends is queued as inbound for the input side, so
 * midiNoteOn -> midiPoll round-trips exactly as it would through a software MIDI
 * loopback. Every send is also recorded in a log, so a test can assert the exact
 * bytes the convenience senders produced (status nibble, 7-bit clamping, ...).
 * And it fails the way RtMidi 6.0.0 fails (rtmidi_c.h lists how), on demand.
 *
 * The midimock_* functions are the FFI-facing controls (exported, cdecl, scalar
 * and pointer+length arguments only) -- LCB binds them as "c:midixt>midimock_*".
 * They exist ONLY in the mock library; the shipped midixt library never has them
 * (tools/package-extension.py refuses a library that exports one).
 *
 * Single-threaded by design (the LCB caller is single-threaded), like the shim.
 */
#include "rtmidi_c.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ---- knobs (also read/written directly by the C smoke test) ---- */
int mock_backend_ok    = 1;
int mock_port_count    = 2;
int mock_oversize_next = 0;

static int    g_loopback       = 0;     /* outbound sends re-enter as inbound */
static double g_loopback_delta = 0.0;   /* delta (s) stamped on looped-back msgs */
static int    g_live_wrappers  = 0;     /* created - freed: a leak check for close */
static int    g_creates        = 0;     /* every create call, failed ones too */
static int    g_send_fail      = 0;     /* sends throw until switched off */
static int    g_read_fail      = 0;     /* reads throw until switched off */
static int    g_read_fail_calls = 0;    /* failed reads since the last reset */
static int    g_count_fail     = 0;     /* port counts throw until switched off */
static int    g_open_fail      = 0;     /* port opens throw until switched off */
static char   g_last_port_name[256];    /* the name the last open asked for */
/* Which backend the mock impersonates. ALSA by default (virtual ports work);
 * set to RTMIDI_API_WINDOWS_MM to exercise the "no virtual ports" refusal. */
static enum RtMidiApi g_api    = RTMIDI_API_LINUX_ALSA;

/* A caller that reads in a loop and never notices failures would spin for ever
 * on a failing read (ShowControl's drain did). After this many failed reads in a
 * row the mock stops failing, so such a caller returns and the test can count
 * how many reads it made. */
#define READ_FAIL_VALVE 10000

/* Per-wrapper state, behind ->data. */
typedef struct { int is_input; unsigned int queue_limit; int open; } mock_dev;

/* ---- inbound FIFO (heap-backed; a popped slot's bytes are freed) ---- */
#define QCAP 4096
typedef struct { unsigned char *b; int len; double delta; } qmsg;
static qmsg q[QCAP];
static int  q_head = 0, q_tail = 0;
/* RtMidi's ring holds queueSizeLimit - 1 messages: the limit of the input that
 * has a port open (the last one opened), or the mock's own capacity when none
 * has. */
static mock_dev *g_queue_owner = NULL;

static int q_depth(void) { return (q_tail - q_head + QCAP) % QCAP; }
static int q_room(void) {
    int cap = QCAP - 1;
    if (g_queue_owner && g_queue_owner->queue_limit > 0
            && (int) g_queue_owner->queue_limit - 1 < cap)
        cap = (int) g_queue_owner->queue_limit - 1;
    return cap - q_depth();
}

void mock_queue_clear(void) {
    while (q_head != q_tail) { free(q[q_head].b); q[q_head].b = NULL; q_head = (q_head + 1) % QCAP; }
    q_head = q_tail = 0;
}
static int q_push(const unsigned char *msg, int len, double delta) {
    if (len < 0) return 0;
    if (q_room() <= 0) return 0;                        /* full: dropped, as RtMidi does */
    unsigned char *b = (unsigned char *) malloc((size_t)(len > 0 ? len : 1));
    if (!b) return 0;
    if (len > 0) memcpy(b, msg, (size_t) len);
    q[q_tail].b = b; q[q_tail].len = len; q[q_tail].delta = delta;
    q_tail = (q_tail + 1) % QCAP;
    return 1;
}
void mock_queue_push(const unsigned char *msg, int len, double delta) { (void) q_push(msg, len, delta); }

/* ---- sent-message log ---- */
#define SENTCAP 4096
typedef struct { unsigned char *b; int len; } smsg;
static smsg sent[SENTCAP];
static int  sent_count = 0;

static void sent_clear(void) {
    for (int i = 0; i < sent_count; i++) { free(sent[i].b); sent[i].b = NULL; }
    sent_count = 0;
}
static void sent_record(const unsigned char *data, int len) {
    if (sent_count >= SENTCAP || len <= 0) return;
    unsigned char *b = (unsigned char *) malloc((size_t) len);
    if (!b) return;
    memcpy(b, data, (size_t) len);
    sent[sent_count].b = b; sent[sent_count].len = len; sent_count++;
}

/* ===================== the RtMidi C API subset ===================== */
static struct RtMidiWrapper *make_wrapper(int is_input, unsigned int queue_limit) {
    struct RtMidiWrapper *w = (struct RtMidiWrapper *) calloc(1, sizeof *w);
    if (!w) return NULL;
    mock_dev *dev = (mock_dev *) calloc(1, sizeof *dev);
    if (!dev) { free(w); return NULL; }
    dev->is_input = is_input;
    dev->queue_limit = queue_limit;
    w->data = dev;
    w->ok  = mock_backend_ok ? true : false;
    w->ptr = mock_backend_ok ? (void *) w : NULL;   /* NULL internal object when !ok */
    w->msg = mock_backend_ok ? "" : "freed by the time you read it";
    g_live_wrappers++;
    g_creates++;
    return w;
}
static mock_dev *dev_of(RtMidiPtr d) { return d ? (mock_dev *) d->data : NULL; }

/* RtMidiIn's default queue limit is 100 (RtMidi.h). */
RtMidiInPtr  rtmidi_in_create_default(void)  { return make_wrapper(1, 100); }
RtMidiInPtr  rtmidi_in_create(enum RtMidiApi api, const char *clientName, unsigned int queueSizeLimit) {
    (void) api; (void) clientName;
    return make_wrapper(1, queueSizeLimit);
}
RtMidiOutPtr rtmidi_out_create_default(void) { return make_wrapper(0, 0); }
RtMidiOutPtr rtmidi_out_create(enum RtMidiApi api, const char *clientName) {
    (void) api; (void) clientName;
    return make_wrapper(0, 0);
}

static void open_common(RtMidiPtr d, const char *n) {
    if (g_open_fail) { d->ok = false; return; }
    snprintf(g_last_port_name, sizeof g_last_port_name, "%s", n ? n : "");
    mock_dev *dev = dev_of(d);
    if (dev) {
        dev->open = 1;
        if (dev->is_input) g_queue_owner = dev;
    }
}
void rtmidi_open_port(RtMidiPtr d, unsigned int p, const char *n) { (void)p; open_common(d, n); }
void rtmidi_open_virtual_port(RtMidiPtr d, const char *n) { open_common(d, n); }
void rtmidi_close_port(RtMidiPtr d) {
    mock_dev *dev = dev_of(d);
    if (dev) {
        dev->open = 0;
        if (g_queue_owner == dev) g_queue_owner = NULL;
    }
}
unsigned int rtmidi_get_port_count(RtMidiPtr d) {
    if (g_count_fail) { d->ok = false; return (unsigned int) -1; }
    return (unsigned) mock_port_count;
}
enum RtMidiApi rtmidi_in_get_current_api(RtMidiPtr d)  { (void)d; return g_api; }
enum RtMidiApi rtmidi_out_get_current_api(RtMidiPtr d) { (void)d; return g_api; }

/* RtMidi 6.0.0: with bufOut != NULL returns snprintf's count (full length), never
 * writes *bufLen. The shim must trust the RETURN value, not *bufLen. */
int rtmidi_get_port_name(RtMidiPtr d, unsigned int p, char *buf, int *buflen) {
    (void)d;
    char name[64];
    snprintf(name, sizeof name, "MockPort-%u-aLongishName", p);
    if (buf && buflen && *buflen > 0) return snprintf(buf, (size_t) *buflen, "%s", name);
    return (int) strlen(name);
}
void rtmidi_in_ignore_types(RtMidiInPtr d, bool a, bool b, bool c) { (void)d; (void)a; (void)b; (void)c; }

double rtmidi_in_get_message(RtMidiInPtr d, unsigned char *message, size_t *size) {
    if (g_read_fail) {
        /* RtMidi: the exception is caught, ok = false, -1 returned, *size left
         * alone and the message left at the front of the queue. */
        g_read_fail_calls++;
        if (g_read_fail_calls >= READ_FAIL_VALVE) g_read_fail = 0;
        d->ok = false;
        return -1;
    }
    if (q_head == q_tail) { *size = 0; return 0.0; }       /* queue empty */
    qmsg m = q[q_head];
    q[q_head].b = NULL;
    q_head = (q_head + 1) % QCAP;                          /* destructive pop */
    double delta = m.delta;
    size_t real = (size_t) m.len;
    if (mock_oversize_next) { mock_oversize_next = 0; free(m.b); *size = 70000; return delta; }
    if (real <= *size) memcpy(message, m.b, real);         /* else no copy (RtMidi behavior) */
    free(m.b);
    *size = real;
    return delta;
}
int rtmidi_out_send_message(RtMidiOutPtr d, const unsigned char *data, int len) {
    if (!d || !d->ptr) return -1;     /* the real one would dereference NULL */
    if (g_send_fail) { d->ok = false; return -1; }   /* RtMidi: caught, ok = false, sticky */
    if (len <= 0) return 0;           /* RtMidi warns (CoreMIDI, WinMM) or sends nothing (ALSA) */
    if ((g_api == RTMIDI_API_MACOSX_CORE || g_api == RTMIDI_API_WINDOWS_MM)
            && data[0] != 0xF0 && len > 3)
        return 0;                     /* a WARNING only: not sent, ok stays true */
    sent_record(data, len);
    if (g_loopback) (void) q_push(data, len, g_loopback_delta);
    return 0;
}
static void free_wrapper(struct RtMidiWrapper *d) {
    if (!d) return;
    mock_dev *dev = dev_of(d);
    if (dev && g_queue_owner == dev) g_queue_owner = NULL;
    free(dev);
    g_live_wrappers--;
    free(d);
}
void rtmidi_in_free(RtMidiInPtr d)   { free_wrapper(d); }
void rtmidi_out_free(RtMidiOutPtr d) { free_wrapper(d); }

/* ===================== FFI-facing controls (mock library only) ===================== */
/* Reset every knob and drain both logs. Port count/backend back to defaults.
 * Note: the shim caches its enumerators (created once), so they count as live. */
MIDIMOCK_API void midimock_reset(void) {
    mock_queue_clear();
    sent_clear();
    mock_backend_ok = 1;
    mock_port_count = 2;
    mock_oversize_next = 0;
    g_loopback = 0;
    g_loopback_delta = 0.0;
    g_send_fail = 0;
    g_read_fail = 0;
    g_read_fail_calls = 0;
    g_count_fail = 0;
    g_open_fail = 0;
    g_last_port_name[0] = '\0';
    g_api = RTMIDI_API_LINUX_ALSA;
}
MIDIMOCK_API int32_t midimock_is_mock(void) { return 1; }
MIDIMOCK_API void midimock_set_backend_ok(int32_t ok)   { mock_backend_ok = ok ? 1 : 0; }
MIDIMOCK_API void midimock_set_port_count(int32_t n)    { mock_port_count = n < 0 ? 0 : n; }
MIDIMOCK_API void midimock_set_oversize_next(int32_t on){ mock_oversize_next = on ? 1 : 0; }
MIDIMOCK_API void midimock_set_send_fail(int32_t on)    { g_send_fail = on ? 1 : 0; }
/* Make reads throw (see READ_FAIL_VALVE); switching it on restarts the count. */
MIDIMOCK_API void midimock_set_read_fail(int32_t on) {
    g_read_fail = on ? 1 : 0;
    if (on) g_read_fail_calls = 0;
}
MIDIMOCK_API int32_t midimock_read_fail_calls(void)     { return g_read_fail_calls; }
MIDIMOCK_API void midimock_set_count_fail(int32_t on)   { g_count_fail = on ? 1 : 0; }
MIDIMOCK_API void midimock_set_open_fail(int32_t on)    { g_open_fail = on ? 1 : 0; }
/* Impersonate a backend by RtMidiApi number (4 = Windows MM, 2 = ALSA, 1 = CoreMIDI). */
MIDIMOCK_API void midimock_set_api(int32_t api) {
    g_api = (api > RTMIDI_API_UNSPECIFIED && api < RTMIDI_API_NUM) ? (enum RtMidiApi) api : RTMIDI_API_LINUX_ALSA;
}
/* Delta is passed in MICROSECONDS (an integer crosses the FFI exactly). */
MIDIMOCK_API void midimock_set_loopback(int32_t on, int32_t delta_us) {
    g_loopback = on ? 1 : 0;
    g_loopback_delta = (delta_us < 0 ? 0 : delta_us) / 1.0e6;
}
/* Inject one inbound message; returns 1 if queued, 0 if the queue is full (the
 * message is then dropped, as RtMidi drops it). */
MIDIMOCK_API int32_t midimock_push(const uint8_t *bytes, int32_t len, int32_t delta_us) {
    return q_push(bytes, len, (delta_us < 0 ? 0 : delta_us) / 1.0e6);
}
MIDIMOCK_API int32_t midimock_queue_depth(void) { return q_depth(); }
/* The queue size limit RtMidi was given for the open input (0: none open). */
MIDIMOCK_API int32_t midimock_queue_limit(void) {
    return g_queue_owner ? (int32_t) g_queue_owner->queue_limit : 0;
}
MIDIMOCK_API int32_t midimock_sent_count(void)  { return sent_count; }
/* Copy sent message i (0-based) into out; returns its length, -needed if out is
 * too small, and 0 if i is out of range (a 0-length message can never be sent,
 * so 0 is unambiguous -- -1 would not be: it is also -needed for a 1-byte msg). */
MIDIMOCK_API int32_t midimock_sent_get(int32_t i, uint8_t *out, int32_t cap) {
    if (i < 0 || i >= sent_count) return 0;
    int32_t n = sent[i].len;
    if (!out || cap < n) return -n;
    memcpy(out, sent[i].b, (size_t) n);
    return n;
}
/* The port name the last open (real or virtual) asked RtMidi for: its length,
 * or -needed when out is too small. */
MIDIMOCK_API int32_t midimock_last_port_name(char *out, int32_t cap) {
    int32_t n = (int32_t) strlen(g_last_port_name);
    if (!out || cap < n + 1) return -(n + 1);
    memcpy(out, g_last_port_name, (size_t) n + 1);
    return n;
}
MIDIMOCK_API void    midimock_sent_clear(void)     { sent_clear(); }
MIDIMOCK_API int32_t midimock_live_wrappers(void)  { return g_live_wrappers; }
MIDIMOCK_API int32_t midimock_creates(void)        { return g_creates; }
