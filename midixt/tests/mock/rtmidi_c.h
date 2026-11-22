/*
 * tests/mock/rtmidi_c.h -- a MOCK of RtMidi's C API, just enough to compile and
 * drive midi_shim.c's OWN logic (the generation-tagged handle table, the batched
 * drain, the per-port stash, the port-name return-value handling and every
 * failure path) WITHOUT the real RtMidi.
 *
 * Why this exists: the real midi smoke test (tests/midi_smoke_test.c) links the
 * actual RtMidi and is correct, but on a headless runner it has no way to *inject*
 * inbound messages or make RtMidi fail -- so the trickiest, most regression-prone
 * code in the shim goes unexercised there. This mock models a controllable input
 * queue and RtMidi's failure behaviour so those paths run deterministically, on
 * every platform, under ASan/UBSan, and even where RtMidi cannot be fetched at
 * all. It is NOT a MIDI backend; it is a test double.
 *
 * It reproduces the RtMidi 6.0.0 behaviour the shim depends on (rtmidi_c.cpp and
 * RtMidi.cpp, read at the pinned tag):
 *   - rtmidi_get_port_name(bufOut != NULL) returns snprintf()'s count (the FULL
 *     name length, excluding the NUL) and does NOT modify *bufLen.
 *   - rtmidi_in_get_message pops destructively; if the message is larger than the
 *     caller buffer it sets *size to the real size and does NOT copy. When the
 *     read THROWS it returns -1, sets ok = false, leaves *size unchanged and the
 *     message stays queued.
 *   - a failed call sets ok = false and nothing ever sets it back (sticky).
 *   - rtmidi_get_port_count answers (unsigned)-1 when it throws.
 *   - a wrapper whose constructor threw has ok == false and a NULL internal
 *     object (a call on it would crash), and msg must never be read
 *     (use-after-free upstream).
 *   - the input queue holds queueSizeLimit - 1 messages (RtMidi's ring); a
 *     message that arrives when it is full is dropped (stderr only).
 *   - CoreMIDI and Windows MM drop a non-SysEx message longer than 3 bytes with
 *     a WARNING only: ok stays true and the send "succeeds".
 */
#ifndef MIDIXT_MOCK_RTMIDI_C_H
#define MIDIXT_MOCK_RTMIDI_C_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

/* Same values and order as RtMidi 6.0.0's enum. */
enum RtMidiApi {
    RTMIDI_API_UNSPECIFIED, RTMIDI_API_MACOSX_CORE, RTMIDI_API_LINUX_ALSA,
    RTMIDI_API_UNIX_JACK, RTMIDI_API_WINDOWS_MM, RTMIDI_API_RTMIDI_DUMMY,
    RTMIDI_API_WEB_MIDI_API, RTMIDI_API_WINDOWS_UWP, RTMIDI_API_ANDROID, RTMIDI_API_NUM
};

/* Same members as the real RtMidiWrapper (ptr/data/ok/msg). The shim reads
 * ->ptr and ->ok, sets ->ok back to true before a call it judges, and never
 * reads ->msg. The mock keeps its own per-wrapper state behind ->data. */
struct RtMidiWrapper { void *ptr; void *data; bool ok; const char *msg; };
typedef struct RtMidiWrapper *RtMidiPtr;
typedef struct RtMidiWrapper *RtMidiInPtr;
typedef struct RtMidiWrapper *RtMidiOutPtr;

/* ---- test-side controls (defined in tests/mock/rtmidi_mock.c) ---- */
extern int mock_backend_ok;     /* 0 => create returns a wrapper with ok=false  */
extern int mock_port_count;     /* what get_port_count reports                  */
extern int mock_oversize_next;  /* next get_message reports size > buffer (drop) */
void mock_queue_push(const unsigned char *msg, int len, double delta);
void mock_queue_clear(void);
/* The FFI-facing midimock_* controls (loopback, sent log, failure modes, ...)
 * are documented in rtmidi_mock.c; C callers may use them via these prototypes.
 * Exported from the mock shared library, so the declaration carries the same
 * linkage (MSVC C2375). */
#if defined(_WIN32)
    #define MIDIMOCK_API __declspec(dllexport)
#else
    #define MIDIMOCK_API __attribute__((visibility("default")))
#endif
MIDIMOCK_API void    midimock_reset(void);
MIDIMOCK_API void    midimock_set_loopback(int32_t on, int32_t delta_us);
MIDIMOCK_API int32_t midimock_sent_count(void);
MIDIMOCK_API int32_t midimock_sent_get(int32_t i, uint8_t *out, int32_t cap);
MIDIMOCK_API void    midimock_sent_clear(void);
MIDIMOCK_API int32_t midimock_live_wrappers(void);
MIDIMOCK_API void    midimock_set_api(int32_t api);
MIDIMOCK_API void    midimock_set_send_fail(int32_t on);
MIDIMOCK_API void    midimock_set_read_fail(int32_t on);
MIDIMOCK_API int32_t midimock_read_fail_calls(void);
MIDIMOCK_API void    midimock_set_count_fail(int32_t on);
MIDIMOCK_API void    midimock_set_open_fail(int32_t on);
MIDIMOCK_API void    midimock_set_backend_ok(int32_t ok);
MIDIMOCK_API int32_t midimock_queue_limit(void);
MIDIMOCK_API int32_t midimock_queue_depth(void);
MIDIMOCK_API int32_t midimock_push(const uint8_t *bytes, int32_t len, int32_t delta_us);
MIDIMOCK_API int32_t midimock_last_port_name(char *out, int32_t cap);
MIDIMOCK_API int32_t midimock_creates(void);

/* ---- the subset of the RtMidi C API the shim binds ---- */
RtMidiInPtr  rtmidi_in_create_default(void);
RtMidiInPtr  rtmidi_in_create(enum RtMidiApi api, const char *clientName, unsigned int queueSizeLimit);
RtMidiOutPtr rtmidi_out_create_default(void);
RtMidiOutPtr rtmidi_out_create(enum RtMidiApi api, const char *clientName);
void         rtmidi_open_port(RtMidiPtr, unsigned int, const char *);
void         rtmidi_open_virtual_port(RtMidiPtr, const char *);
void         rtmidi_close_port(RtMidiPtr);
unsigned int rtmidi_get_port_count(RtMidiPtr);
enum RtMidiApi rtmidi_in_get_current_api(RtMidiPtr);
enum RtMidiApi rtmidi_out_get_current_api(RtMidiPtr);
int          rtmidi_get_port_name(RtMidiPtr, unsigned int, char *, int *);
void         rtmidi_in_ignore_types(RtMidiInPtr, bool, bool, bool);
double       rtmidi_in_get_message(RtMidiInPtr, unsigned char *, size_t *);
int          rtmidi_out_send_message(RtMidiOutPtr, const unsigned char *, int);
void         rtmidi_in_free(RtMidiInPtr);
void         rtmidi_out_free(RtMidiOutPtr);

#endif /* MIDIXT_MOCK_RTMIDI_C_H */
