/*
 * midi_shim.c
 * ----------------------------------------------------------------------------
 * The C shim of midixt, the xTalk suite's MIDI member (born as the MIDI third
 * of ShowControl for OpenXTalk): a thin, FFI-friendly layer over RtMidi's C API
 * (rtmidi_c.h) for xTalk Builder (LCB). Output is request/response; input is
 * RtMidi's internal FIFO plus POLLING (no callbacks into LCB, suite rule 1).
 * RtMidi instance pointers stay inside; script gets an integer handle,
 * validated before every use (a stale handle is a harmless no-op).
 *
 * Build: compiled with RtMidi into ONE shared library named after the member,
 * "midixt" (midixt.so / midixt.dylib / midixt.dll, no "lib" prefix). See
 * CMakeLists.txt. The exported C ABI keeps its stable "midi_" prefix.
 *
 * What RtMidi 6.0.0's C wrapper does, which every function below is written
 * against (build/_deps/rtmidi-src/rtmidi_c.cpp; tests/mock/rtmidi_mock.c
 * reproduces each point, and tests/midi_mock_smoke_test.c pins the shim's
 * answer to it):
 *   - A failed call sets the wrapper's `ok` to false and NEVER sets it back:
 *     `ok` says "some call on this wrapper once failed", not "the last call
 *     failed". So the shim sets `ok` back to true before every call whose
 *     outcome it judges, and reads it straight after.
 *   - `msg` points into a thrown exception's string that is freed when the
 *     catch block ends: reading it is a use-after-free. Never read.
 *   - A constructor that throws leaves a wrapper with ok == false and a NULL
 *     object: any call on it dereferences NULL. Such a wrapper is only freed.
 *   - rtmidi_get_port_count() answers (unsigned)-1 when it throws.
 *   - rtmidi_in_get_message() returns -1 and leaves *size UNCHANGED when it
 *     throws, and the message it was popping stays queued, so the next call
 *     fails the same way: a drain that read only *size looped for ever.
 *   - A WARNING is not an error: RtMidi prints it to stderr and carries on,
 *     with `ok` still true. CoreMIDI and Windows MM drop a non-SysEx message
 *     longer than three bytes that way, and Windows MM "opens" a virtual port
 *     that sends nowhere. The shim refuses both itself, with a reason.
 * ----------------------------------------------------------------------------
 */

#include "midi_shim.h"
#include "rtmidi_c.h"

#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

/* How many inbound messages RtMidi may hold between two polls. RtMidi's own
 * default (100, i.e. 99 usable slots) drops the rest of a burst with nothing
 * but a line on stderr ("message queue limit reached"): a fader sweep from a
 * fast controller, or a sequencer playing through a virtual port, fills 99
 * slots between two 50 ms polls. 1024 slots cost RtMidi about 32 KB per open
 * input and absorb any burst the 256-messages-per-poll drain can keep up
 * with. */
#define MIDI_IN_QUEUE_LIMIT 1024

/* RtMidi's own default client names, kept: other MIDI software lists our ports
 * under them, and a saved connection names them. */
#define MIDI_IN_CLIENT  "RtMidi Input Client"
#define MIDI_OUT_CLIENT "RtMidi Output Client"
/* The port names a script sees in other software: the local port RtMidi
 * creates to connect to a device, and a virtual port opened with no name.
 * ShowControl's names, kept for the same reason. */
#define MIDI_IN_PORT_NAME  "ShowControl In"
#define MIDI_OUT_PORT_NAME "ShowControl Out"

/* ===================================================================== */
/* Last-error string + caller-buffer copy helper (shared conventions).    */
/* ===================================================================== */
/* The error of the LAST fallible call (count, open, send, drain): cleared when
 * one starts, set when it fails, so midiLastError() never reports an earlier
 * call's failure after a later call succeeded (docs: "empty when the last
 * fallible call succeeded"; ShowControl's shim never cleared it). Getters
 * (names, the ABI, the error itself), close and ignore leave it alone. */
static char g_err[256];
static void err_clear(void) { g_err[0] = '\0'; }
static void err_set(const char *m) {
    if (!m) { g_err[0] = '\0'; return; }
    size_t n = strlen(m);
    if (n >= sizeof g_err) n = sizeof g_err - 1;
    memcpy(g_err, m, n);
    g_err[n] = '\0';
}
static int32_t copy_str(const char *s, char *out, int32_t cap) {
    int32_t n = (int32_t) strlen(s);
    if (!out || cap <= 0 || n + 1 > cap) {
        if (out && cap > 0) out[0] = '\0';
        return -(n + 1);
    }
    memcpy(out, s, (size_t) n + 1);
    return n;
}
static void be16_store(uint8_t *p, uint16_t v) { p[0]=(uint8_t)(v>>8); p[1]=(uint8_t)v; }
static void be32_store(uint8_t *p, uint32_t v) {
    p[0]=(uint8_t)(v>>24); p[1]=(uint8_t)(v>>16); p[2]=(uint8_t)(v>>8); p[3]=(uint8_t)v;
}

/* ===================================================================== */
/* Handle table for open ports (generation-tagged; same scheme as OSC).   */
/* ===================================================================== */
#define H_SLOT_BITS 23
#define H_SLOT_MASK 0x7FFFFF
#define H_GEN_MASK  0xFF

typedef struct {
    RtMidiPtr ptr;
    int       is_input;
    enum RtMidiApi api;   /* the backend this port runs on (send's length rule) */
    /* one-message stash so a full output buffer never drops a popped message */
    uint8_t  *stash;
    int32_t   stash_len;
    uint32_t  stash_delta_us;
    int       has_stash;
} midi_port;

static midi_port    *g_arr  = NULL;
static unsigned char *g_used = NULL;
static unsigned char *g_gen  = NULL;
static int g_cap = 0, g_cnt = 0;
static int *g_free = NULL; static int g_freeCap = 0, g_freeCnt = 0;

static int tbl_grow(int nc) {
    midi_port *na = (midi_port*) realloc(g_arr, (size_t)nc * sizeof(midi_port));
    if (!na) { return 0; }
    g_arr = na;
    unsigned char *nu = (unsigned char*) realloc(g_used, (size_t)nc);
    if (!nu) { return 0; }
    g_used = nu;
    unsigned char *ng = (unsigned char*) realloc(g_gen, (size_t)nc);
    if (!ng) { return 0; }
    g_gen = ng;
    memset(g_used + g_cap, 0, (size_t)(nc - g_cap));
    memset(g_gen  + g_cap, 0, (size_t)(nc - g_cap));
    g_cap = nc; return 1;
}
static int tbl_slot(int h) {
    if (h <= 0) return -1;
    int idx = (h & H_SLOT_MASK) - 1;
    unsigned gen = ((unsigned)h >> H_SLOT_BITS) & H_GEN_MASK;
    if (idx < 0 || idx >= g_cnt) return -1;
    if (!g_used[idx] || g_gen[idx] != gen) return -1;
    return idx;
}
static int tbl_add(midi_port v) {
    int idx = -1;
    if (g_freeCnt > 0) idx = g_free[--g_freeCnt];
    if (idx < 0) {
        if (g_cnt >= H_SLOT_MASK - 1) return 0;
        if (g_cnt >= g_cap) { int nc = g_cap ? g_cap*2 : 16; if (!tbl_grow(nc)) return 0; }
        idx = g_cnt++;
    }
    g_arr[idx] = v; g_used[idx] = 1;
    return (int)(((unsigned)g_gen[idx] << H_SLOT_BITS) | (unsigned)(idx + 1));
}
static midi_port *tbl_get(int h) { int i = tbl_slot(h); return i < 0 ? NULL : &g_arr[i]; }
static void tbl_release(int h) {
    int idx = tbl_slot(h);
    if (idx < 0) return;
    g_used[idx] = 0;
    g_gen[idx] = (unsigned char)((g_gen[idx] + 1) & H_GEN_MASK);
    if (g_freeCnt >= g_freeCap) {
        int nc = g_freeCap ? g_freeCap*2 : 16;
        int *nf = (int*) realloc(g_free, (size_t)nc * sizeof(int));
        if (nf) { g_free = nf; g_freeCap = nc; }
    }
    if (g_freeCnt < g_freeCap) g_free[g_freeCnt++] = idx;
}

/* ===================================================================== */
/* Lazy persistent enumerators (counting / naming ports needs an instance) */
/* ===================================================================== */
/* One instance per direction, made on first use and kept. One whose backend
 * failed to start (NULL object) is freed and made again on the next call, so a
 * MIDI service that comes up after the first enumeration is seen; ShowControl
 * kept the failed one for the life of the process. */
static RtMidiInPtr  g_enum_in  = NULL;
static RtMidiOutPtr g_enum_out = NULL;

static RtMidiPtr enumerator(int is_input) {
    RtMidiPtr *slot = is_input ? &g_enum_in : &g_enum_out;
    if (*slot && !(*slot)->ptr) {
        if (is_input) rtmidi_in_free(*slot); else rtmidi_out_free(*slot);
        *slot = NULL;
    }
    if (!*slot)
        *slot = is_input ? (RtMidiPtr) rtmidi_in_create_default()
                         : (RtMidiPtr) rtmidi_out_create_default();
    if (!*slot || !(*slot)->ptr) return NULL;   /* no backend (kept for the retry above) */
    (*slot)->ok = true;                         /* judge the next call alone */
    return *slot;
}

/* ===================================================================== */
MIDI_API int32_t midi_abi_version(void) { return MIDI_ABI_VERSION; }

static int32_t port_count(int is_input) {
    err_clear();
    RtMidiPtr d = enumerator(is_input);
    if (!d) {
        err_set(is_input ? "midi: no MIDI input backend" : "midi: no MIDI output backend");
        return 0;
    }
    unsigned int n = rtmidi_get_port_count(d);
    if (!d->ok || n > (unsigned int) INT32_MAX) {
        /* RtMidi answers (unsigned)-1 when the count throws: ShowControl handed
         * that on as -1 ports. */
        err_set("midi: could not count the MIDI ports");
        return 0;
    }
    return (int32_t) n;
}
MIDI_API int32_t midi_in_count(void)  { return port_count(1); }
MIDI_API int32_t midi_out_count(void) { return port_count(0); }

static int32_t port_name(int is_input, int32_t index, char *out, int32_t cap) {
    if (index < 0) { if (out && cap > 0) out[0] = '\0'; return 0; }
    RtMidiPtr d = enumerator(is_input);
    if (!d) { if (out && cap > 0) out[0] = '\0'; return 0; }
    /* RtMidi 6.0.0's rtmidi_get_port_name(bufOut != NULL) returns snprintf()'s
       count -- the full name length, excluding the NUL -- and does NOT modify
       *bufLen. (Only the bufOut == NULL query path writes *bufLen, and we always
       pass a buffer.) So we trust the RETURN value, never the in/out length. */
    int blen = cap;
    char tmp[256];
    char *dst = (cap > 0 && out) ? out : tmp;
    if (dst == tmp) blen = (int) sizeof tmp;
    int rc = rtmidi_get_port_name(d, (unsigned)index, dst, &blen);
    if (rc < 0 || !d->ok) { if (out && cap > 0) out[0] = '\0'; return 0; }
    if (dst == out) {
        /* snprintf wrote min(rc, cap-1) chars + a NUL; rc is the full length. */
        if (rc >= cap) { out[cap-1] = '\0'; return -(rc + 1); }  /* truncated: need rc+1 */
        out[rc] = '\0';   /* snprintf already terminated here; keep it explicit */
        return rc;
    }
    /* No caller buffer: report the size needed (a name longer than tmp was cut
     * by snprintf, so ask by the full length rc, never by strlen(tmp)). */
    return -(rc + 1);
}
MIDI_API int32_t midi_in_name(int32_t index, char *out, int32_t cap) {
    return port_name(1, index, out, cap);
}
MIDI_API int32_t midi_out_name(int32_t index, char *out, int32_t cap) {
    return port_name(0, index, out, cap);
}

/* ---- open / close -------------------------------------------------------- */
static void free_device(int is_input, RtMidiPtr d) {
    if (is_input) rtmidi_in_free(d); else rtmidi_out_free(d);
}

static int32_t open_port(int is_input, int32_t portIndex, const char *vname) {
    err_clear();
    RtMidiPtr d = is_input
        ? (RtMidiPtr) rtmidi_in_create(RTMIDI_API_UNSPECIFIED, MIDI_IN_CLIENT, MIDI_IN_QUEUE_LIMIT)
        : (RtMidiPtr) rtmidi_out_create(RTMIDI_API_UNSPECIFIED, MIDI_OUT_CLIENT);
    if (!d) { err_set("midi: could not create RtMidi instance"); return 0; }
    if (!d->ok || !d->ptr) {
        err_set("midi: backend init failed (no MIDI service available?)");
        free_device(is_input, d);
        return 0;
    }
    enum RtMidiApi api = is_input ? rtmidi_in_get_current_api(d) : rtmidi_out_get_current_api(d);
    if (vname) {
        /* Windows MM (and RtMidi's dummy API) cannot create virtual ports, but
         * RtMidi only raises a WARNING for it: `ok` stays true and the caller
         * gets a live-looking handle that silently sends nowhere. Refuse it up
         * front with a reason the script can show (0 + midiLastError). */
        if (api == RTMIDI_API_WINDOWS_MM || api == RTMIDI_API_RTMIDI_DUMMY) {
            err_set("midi: this MIDI backend has no virtual ports (on Windows use a loopback driver such as loopMIDI)");
            free_device(is_input, d);
            return 0;
        }
        d->ok = true;
        rtmidi_open_virtual_port(d, vname);
    } else {
        d->ok = true;
        unsigned count = rtmidi_get_port_count(d);
        if (!d->ok) {
            err_set("midi: could not count the MIDI ports");
            free_device(is_input, d);
            return 0;
        }
        if (portIndex < 0 || (unsigned)portIndex >= count) {
            err_set("midi: port index out of range");
            free_device(is_input, d);
            return 0;
        }
        rtmidi_open_port(d, (unsigned)portIndex, is_input ? MIDI_IN_PORT_NAME : MIDI_OUT_PORT_NAME);
    }
    if (!d->ok) {
        err_set("midi: open port failed");   /* d->msg is unsafe to read (see top) */
        free_device(is_input, d);
        return 0;
    }
    midi_port mp; memset(&mp, 0, sizeof mp);
    mp.ptr = d; mp.is_input = is_input; mp.api = api;
    if (is_input) {
        /* Pre-allocate the drain stash up front, sized to the largest message the
         * 2-byte record length can carry (65535 B). The drain hot path then NEVER
         * mallocs, so a buffer-full stash can never drop a popped message on OOM. */
        mp.stash = (uint8_t*) malloc(65535);
        if (!mp.stash) {
            err_set("midi: out of memory");
            free_device(is_input, d);
            return 0;
        }
    }
    int32_t h = tbl_add(mp);
    if (!h) {
        err_set("midi: handle table full");
        free(mp.stash);   /* NULL for outputs; the input stash if we got one */
        free_device(is_input, d);
        return 0;
    }
    return h;
}

MIDI_API int32_t midi_in_open(int32_t portIndex)  { return open_port(1, portIndex, NULL); }
MIDI_API int32_t midi_out_open(int32_t portIndex) { return open_port(0, portIndex, NULL); }
/* A virtual port with no name (NULL, or "" from a script) takes the default
 * name: ShowControl created a port named "" that other software lists as a
 * blank line. */
MIDI_API int32_t midi_in_open_virtual(const char *name) {
    return open_port(1, -1, (name && *name) ? name : MIDI_IN_PORT_NAME);
}
MIDI_API int32_t midi_out_open_virtual(const char *name) {
    return open_port(0, -1, (name && *name) ? name : MIDI_OUT_PORT_NAME);
}

MIDI_API void midi_close(int32_t handle) {
    midi_port *mp = tbl_get(handle);
    if (!mp) return;
    if (mp->ptr) {
        rtmidi_close_port(mp->ptr);
        free_device(mp->is_input, mp->ptr);
    }
    free(mp->stash);
    tbl_release(handle);
}

/* ---- input config & drain ------------------------------------------------ */
MIDI_API void midi_in_ignore(int32_t handle, int32_t sysex, int32_t timing, int32_t sense) {
    midi_port *mp = tbl_get(handle);
    if (!mp || !mp->is_input || !mp->ptr) return;
    rtmidi_in_ignore_types(mp->ptr, sysex != 0, timing != 0, sense != 0);
}

/* Append one record [2B len][bytes][4B delta-us] to out at *pos if it fits.
 * Returns 1 if written, 0 if it does not fit. */
static int emit_record(uint8_t *out, int32_t out_cap, int32_t *pos,
                       const uint8_t *bytes, int32_t len, uint32_t delta_us) {
    int32_t need = 2 + len + 4;
    if (*pos + need > out_cap) return 0;
    be16_store(out + *pos, (uint16_t) len); *pos += 2;
    memcpy(out + *pos, bytes, (size_t) len); *pos += len;
    be32_store(out + *pos, delta_us); *pos += 4;
    return 1;
}

/* The drain itself. Returns the record count and reports the bytes written via
 * *bytes_out, so both public entry points share one implementation. */
static int32_t drain_impl(int32_t handle, uint8_t *out, int32_t out_cap, int32_t max_msgs,
                          int32_t *bytes_out) {
    *bytes_out = 0;
    err_clear();
    midi_port *mp = tbl_get(handle);
    if (!mp || !mp->is_input || !mp->ptr) {
        /* Still a harmless no-op (rule 4), but it says why, as a send on a stale
         * handle does: a poll loop left running after midiClose can see that
         * its port is gone (examples/midi-helpers stops its timer on it). */
        err_set("midi: not an open input port");
        return 0;
    }
    if (!out) return 0;

    int32_t pos = 0, count = 0;
    static unsigned char tmp[65536];   /* single-threaded LCB caller -> static ok */

    /* 1. flush a stashed message from a previous (buffer-full) drain first.
     * pos is 0 here, so a failure means the record is structurally larger than
     * out_cap and can NEVER fit -- drop it (with a diagnostic) rather than
     * returning 0 forever and wedging the port until midiClose. With the LCB
     * binding's kDrainCap >= the max record size (2 + 65535 + 4) this drop path
     * is unreachable; it is defense-in-depth for any smaller caller buffer.
     * Gated on max_msgs > 0 so a caller asking for 0 messages gets 0 (and keeps
     * its stash for next time) -- the return count never exceeds max_msgs. */
    if (mp->has_stash && max_msgs > 0) {
        int wrote = emit_record(out, out_cap, &pos, mp->stash, mp->stash_len, mp->stash_delta_us);
        mp->has_stash = 0;        /* mark empty; keep the buffer (freed only at close) */
        if (wrote) {
            count++;
        } else {
            err_set("midi: dropped an inbound message larger than the drain buffer");
        }
    }

    /* 2. drain RtMidi's FIFO */
    while (count < max_msgs) {
        size_t sz = sizeof tmp;
        mp->ptr->ok = true;                       /* judge this read alone */
        double delta = rtmidi_in_get_message(mp->ptr, tmp, &sz);
        if (!mp->ptr->ok) {
            /* The read threw: RtMidi left *size alone and the message queued,
             * so reading again fails again. ShowControl took the untouched
             * size for a giant message, skipped it and read again: an endless
             * loop on the engine's main thread. Stop; the next poll retries. */
            err_set("midi: reading the MIDI input queue failed");
            break;
        }
        if (sz == 0) break;                       /* queue empty */
        if (sz > 65535) {                         /* SysEx beyond the 2-byte record length */
            /* RtMidi already popped it; the [2B len] record format cannot carry it,
             * so it is dropped. Note it (don't wedge). Real-world SysEx is far smaller. */
            err_set("midi: dropped an inbound message larger than 65535 bytes");
            continue;
        }
        if (!(delta >= 0)) delta = 0;     /* clamp negative AND NaN (NaN fails every compare) */
        double us = delta * 1.0e6;
        /* Guard the double->uint32 conversion: out-of-range/NaN float-to-int is UB
         * (float-cast-overflow). RtMidi's delta is a finite, non-negative duration,
         * so this only ever clamps a pathological value -- defence in depth. */
        uint32_t delta_us = (us >= 4294967295.0) ? 4294967295u : (uint32_t) us;
        if (!emit_record(out, out_cap, &pos, tmp, (int32_t) sz, delta_us)) {
            /* doesn't fit this drain: stash into the per-port buffer (pre-allocated
             * at open, capacity 65535 >= sz) so the next drain delivers it. No malloc
             * here means this can never fail and never drop the popped message. */
            memcpy(mp->stash, tmp, sz);
            mp->stash_len = (int32_t) sz;
            mp->stash_delta_us = delta_us;
            mp->has_stash = 1;
            break;
        }
        count++;
    }
    *bytes_out = pos;
    return count;
}

MIDI_API int32_t midi_in_drain(int32_t handle, uint8_t *out, int32_t out_cap, int32_t max_msgs) {
    int32_t bytes;
    return drain_impl(handle, out, out_cap, max_msgs, &bytes);
}

/* Same drain, but returns the BYTES written (records are self-delimiting). The
 * LCB binding needs the byte length, not the count: it drains into a raw engine
 * block (a Data does not bridge to a Pointer) and must copy exactly the written
 * bytes back out with MCDataCreateWithBytes. ABI 2. */
MIDI_API int32_t midi_in_drain_bytes(int32_t handle, uint8_t *out, int32_t out_cap, int32_t max_msgs) {
    int32_t bytes;
    (void) drain_impl(handle, out, out_cap, max_msgs, &bytes);
    return bytes;
}

/* ---- output -------------------------------------------------------------- */
MIDI_API int32_t midi_out_send(int32_t handle, const uint8_t *data, int32_t len) {
    err_clear();
    midi_port *mp = tbl_get(handle);
    if (!mp || mp->is_input || !mp->ptr) {
        err_set("midi: not an open output port");
        return 0;
    }
    if (!data || len <= 0) {
        err_set("midi: nothing to send (the message is empty)");
        return 0;
    }
    /* CoreMIDI and Windows MM send one message at a time and drop a non-SysEx
     * message longer than three bytes with only a WARNING (RtMidi.cpp,
     * MidiOutCore/MidiOutWinMM::sendMessage), so it was reported as sent. ALSA
     * splits such a byte stream into its messages and sends them all, so it is
     * left alone there. */
    if ((mp->api == RTMIDI_API_MACOSX_CORE || mp->api == RTMIDI_API_WINDOWS_MM)
            && data[0] != 0xF0 && len > 3) {
        err_set("midi: this MIDI backend sends one message at a time: a message that is not SysEx must be 1 to 3 bytes");
        return 0;
    }
    mp->ptr->ok = true;      /* RtMidi never resets it: one failed send made every later one "fail" */
    int rc = rtmidi_out_send_message(mp->ptr, data, len);
    if (rc < 0 || !mp->ptr->ok) {
        err_set("midi: send failed");        /* d->msg is unsafe to read (see top) */
        return 0;
    }
    return 1;
}

/* ---- diagnostics --------------------------------------------------------- */
MIDI_API int32_t midi_last_error(char *out, int32_t out_cap) {
    return copy_str(g_err, out, out_cap);
}

static char g_name[256];
MIDI_API const char *midi_in_name_str(int32_t index) {
    g_name[0] = '\0';
    port_name(1, index, g_name, (int32_t) sizeof g_name);
    return g_name;
}
MIDI_API const char *midi_out_name_str(int32_t index) {
    g_name[0] = '\0';
    port_name(0, index, g_name, (int32_t) sizeof g_name);
    return g_name;
}
MIDI_API const char *midi_error_str(void) { return g_err; }
