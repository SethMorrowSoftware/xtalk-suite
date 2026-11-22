/*
 * midi_shim.h
 * ----------------------------------------------------------------------------
 * Public C ABI of midixt's MIDI shim: an FFI-friendly layer over RtMidi's C API
 * (rtmidi_c.h) for xTalk Builder (LCB). midixt is the xTalk suite's MIDI member
 * (born as the MIDI third of ShowControl for OpenXTalk), for OpenXTalk (OXT) /
 * the xTalk family and compatible with LiveCode 9.6.3+.
 *
 * The decisive design rule (suite rule 1): we never call an LCB handler from a
 * C callback. RtMidi keeps an internal FIFO when no callback is registered, so
 * we POLL it from script on a timer and DRAIN the queue. Because RtMidi buffers
 * and delta-time-stamps every message, message integrity and timing survive
 * jittery poll cadence; only added latency scales with the poll interval.
 *
 * FFI conventions (mirrored from Box2Dxt):
 *   - RtMidi instance pointers stay INSIDE the shim; script sees a positive
 *     32-bit int handle (0 = invalid), generation-tagged and validated before
 *     use, so a stale handle is a harmless no-op.
 *   - Names and the last-error string are written into CALLER buffers; the shim
 *     never returns a library-owned `const char*` to LCB.
 *   - midi_in_drain batches every queued message into ONE caller buffer per poll
 *     (one FFI round-trip per tick instead of one per message).
 *   - The last error belongs to the last FALLIBLE call (count, open, send,
 *     drain): each one clears it as it starts and sets it if it fails.
 *
 * Drain record format (concatenated; midi_in_drain returns the record count):
 *     [2 bytes: byteLen, big-endian]
 *     [byteLen bytes: the raw MIDI message]
 *     [4 bytes: delta-time in MICROSECONDS since the previous message, big-endian]
 * A 2-byte length carries SysEx up to 65535 bytes; the LCB layer walks records
 * with simple byte arithmetic (no float unpacking needed).
 * ----------------------------------------------------------------------------
 */
#ifndef MIDIXT_MIDI_SHIM_H
#define MIDIXT_MIDI_SHIM_H

#include <stdint.h>

#if defined(_WIN32)
    #define MIDI_API __declspec(dllexport)
#else
    #define MIDI_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* ABI 2: added midi_in_drain_bytes (the LCB binding drains through it). */
#define MIDI_ABI_VERSION 2

MIDI_API int32_t  midi_abi_version(void);

/* ---- Enumeration --------------------------------------------------------- */
/* The number of ports; 0 (and a last error) when no MIDI backend is running. */
MIDI_API int32_t  midi_in_count(void);
MIDI_API int32_t  midi_out_count(void);
/* Port name into the caller buffer; returns length, or -needed if too small. */
MIDI_API int32_t  midi_in_name(int32_t index, char *out, int32_t out_cap);
MIDI_API int32_t  midi_out_name(int32_t index, char *out, int32_t out_cap);

/* ---- Open / close (return a handle > 0, or 0 on failure) ----------------- */
/* A virtual port with no name (NULL or "") is named "ShowControl In" / "Out". */
MIDI_API int32_t  midi_in_open(int32_t portIndex);
MIDI_API int32_t  midi_out_open(int32_t portIndex);
MIDI_API int32_t  midi_in_open_virtual(const char *name);   /* macOS / Linux */
MIDI_API int32_t  midi_out_open_virtual(const char *name);  /* macOS / Linux */
MIDI_API void     midi_close(int32_t handle);

/* ---- Input config & draining -------------------------------------------- */
MIDI_API void     midi_in_ignore(int32_t handle, int32_t sysex, int32_t timing, int32_t sense);
/* Drain up to max_msgs queued messages into `out` (see record format above).
 * Returns the number of records written. A message that does not fit is stashed
 * and emitted on the next call, so messages are never dropped -- EXCEPT one that
 * is structurally larger than out_cap itself (cannot happen with the LCB binding,
 * whose buffer is sized to the maximum record), which is dropped with a last-error
 * set rather than wedging the port forever. Returns 0 when the queue is empty (and
 * 0 on a bad/non-input handle). */
MIDI_API int32_t  midi_in_drain(int32_t handle, uint8_t *out, int32_t out_cap, int32_t max_msgs);
/* Identical drain, but returns the number of BYTES written to `out` (0 when the
 * queue is empty or the handle is bad). Records are self-delimiting, so the
 * caller walks them by length. This is the entry point the LCB binding uses. */
MIDI_API int32_t  midi_in_drain_bytes(int32_t handle, uint8_t *out, int32_t out_cap, int32_t max_msgs);

/* ---- Output -------------------------------------------------------------- */
/* Send raw MIDI bytes. Returns 1 on success, 0 (and a last error) on failure, a
 * bad handle, an empty message, or -- on CoreMIDI and Windows MM, which send
 * one message at a time -- a non-SysEx message longer than 3 bytes. */
MIDI_API int32_t  midi_out_send(int32_t handle, const uint8_t *data, int32_t len);

/* ---- Diagnostics --------------------------------------------------------- */
MIDI_API int32_t  midi_last_error(char *out, int32_t out_cap);

/* C-side convenience accessors returning a module-static buffer (valid until the
 * next call; "" never NULL). DO NOT bind these from LCB as `returns ZStringUTF8`:
 * the engine wraps a returned ZString in a foreign value whose finalizer free()s
 * the pointer, so a static buffer crashes it (confirmed under lc-run). The LCB
 * binding uses the caller-buffer midi_in_name / midi_out_name / midi_last_error.
 * Kept only so the exported symbol set (and older C callers) stay stable. */
MIDI_API const char *midi_in_name_str(int32_t index);
MIDI_API const char *midi_out_name_str(int32_t index);
MIDI_API const char *midi_error_str(void);

#ifdef __cplusplus
}
#endif

#endif /* MIDIXT_MIDI_SHIM_H */
