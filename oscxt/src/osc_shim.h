/*
 * osc_shim.h
 * ----------------------------------------------------------------------------
 * Public C ABI of the ShowControl OSC shim: a thin, FFI-friendly layer over
 * tinyosc (ISC) that LiveCode Builder (LCB) binds to. Part of ShowControl for
 * OpenXTalk (OXT) / the xTalk family (also compatible with LiveCode 9.6.3+).
 *
 * Why a shim exists even though tinyosc is already C (CLAUDE.md, "As built"):
 *   - tinyosc's WRITE API (tosc_writeMessage) is variadic (C varargs), which the
 *     LCB FFI cannot bind. The shim replaces it with a non-variadic, incremental
 *     builder: open a builder handle, add typed args one call at a time, finish.
 *   - tinyosc's READ API is cursor-based (tosc_getNext*) and, critically, does
 *     NOT bounds-check. The shim PRE-SCANS each datagram once, with full bounds
 *     checking, into an indexed model so the script can random-access arguments
 *     by position -- and so a malformed datagram is a clean error, not a crash.
 *
 * FFI conventions (mirrored from the proven Box2Dxt design):
 *   - Opaque objects (builders, parsed messages) cross the boundary as a
 *     positive 32-bit int handle; 0 means null/invalid. Handles are
 *     generation-tagged, so a stale handle stays a harmless no-op after its slot
 *     is recycled. Treat them as opaque.
 *     NOTE: the three handle kinds -- message builders (osc_build_*), bundle
 *     builders (osc_bundle_*), and parsed messages (osc_parse / osc_arg_* /
 *     osc_*_free) -- live in SEPARATE tables that each start numbering at 1, so a
 *     value is only meaningful to the kind that issued it. A handle is validated
 *     against its own table, so crossing kinds is never memory-unsafe (it is a
 *     harmless no-op / 0-return), but it IS a logic error: pass each handle only
 *     to functions of its own kind. The LCB binding keeps them in separate
 *     variables and never mixes them.
 *   - Byte buffers cross as a (pointer, length) pair: the caller (LCB) passes a
 *     pointer to its bytes and an int length. The shim NEVER returns a
 *     library-owned `const char*` (a known engine-crash footgun); every string /
 *     byte result is written into a CALLER-allocated buffer and the byte count
 *     is returned (or -needed when the buffer is too small).
 *   - Numbers cross as int32 / int64 / float / double; booleans as int (0/1).
 *
 * The exported symbols use the stable `osc_` prefix; never rename them (the .lcb
 * binding strings reference these names).
 * ----------------------------------------------------------------------------
 */
#ifndef SHOWCONTROL_OSC_SHIM_H
#define SHOWCONTROL_OSC_SHIM_H

#include <stdint.h>

#if defined(_WIN32)
    #define OSC_API __declspec(dllexport)
#else
    #define OSC_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Bump whenever the exported ABI changes so the .lcb can sanity-check.
 * v2: added osc_build_add_int32_str / _float_str / _double_str (numeric build args
 *     cross as decimal strings; the engine hands script numbers to a foreign `any`
 *     as strings and LCB will not coerce a decimal string to Number). */
#define OSC_ABI_VERSION 2

OSC_API int32_t  osc_abi_version(void);

/* ---- Building (replaces tinyosc's variadic writer) ----------------------- */
/* Open a builder for an address. Returns a handle (>0), or 0 on failure
 * (e.g. NULL/over-long address). Args are appended in order; serialize with
 * osc_build_finish; always release with osc_build_free. */
OSC_API int32_t  osc_build_new(const char *address /*utf8, nul-terminated*/);
OSC_API int32_t  osc_build_add_int32  (int32_t h, int32_t v);
OSC_API int32_t  osc_build_add_int64  (int32_t h, int64_t v);
OSC_API int32_t  osc_build_add_float  (int32_t h, float v);
OSC_API int32_t  osc_build_add_double (int32_t h, double v);
OSC_API int32_t  osc_build_add_string (int32_t h, const char *v /*utf8*/);
OSC_API int32_t  osc_build_add_blob   (int32_t h, const uint8_t *data, int32_t len);
OSC_API int32_t  osc_build_add_true   (int32_t h);
OSC_API int32_t  osc_build_add_false  (int32_t h);
OSC_API int32_t  osc_build_add_nil    (int32_t h);
OSC_API int32_t  osc_build_add_impulse(int32_t h);
OSC_API int32_t  osc_build_add_timetag(int32_t h, uint64_t ntp);
/* 64-bit-as-decimal-string entry points. The target xTalk engine (9.6.3) has no
 * 64-bit foreign integer type, so the LCB layer carries int64 / uint64 across
 * the boundary as a decimal string (script numbers are doubles -- a 64-bit int
 * is naturally a string there anyway). */
OSC_API int32_t  osc_build_add_int64_str  (int32_t h, const char *dec);
OSC_API int32_t  osc_build_add_timetag_str(int32_t h, const char *dec);
/* int32 / float / double as decimal strings too (ABI 2). The engine passes script
 * numbers to a foreign `any` as strings and LCB will not coerce a decimal string
 * to its Number type, so the .lcb stringifies every numeric arg and we parse here. */
OSC_API int32_t  osc_build_add_int32_str  (int32_t h, const char *dec);
OSC_API int32_t  osc_build_add_float_str  (int32_t h, const char *dec);
OSC_API int32_t  osc_build_add_double_str (int32_t h, const char *dec);
/* Serialize the OSC message into the caller buffer. Returns bytes written, or
 * -needed (negative) if out_cap is too small (call again with a bigger buffer),
 * or 0 on a bad handle. Does not free the builder. */
OSC_API int32_t  osc_build_finish(int32_t h, uint8_t *out, int32_t out_cap);
OSC_API void     osc_build_free(int32_t h);

/* ---- Bundles ------------------------------------------------------------- */
/* Open a bundle builder with a timetag (NTP-64; 1 == "immediately"). */
OSC_API int32_t  osc_bundle_new(uint64_t timetag);
/* Same, with the timetag as a decimal string (the LCB entry point; no 64-bit
 * foreign int). "1" / "immediately"-style callers pass "1". */
OSC_API int32_t  osc_bundle_new_str(const char *dec);
/* Append a finished message (its serialized bytes) as a bundle element. */
OSC_API int32_t  osc_bundle_add_message(int32_t bundle_h, const uint8_t *msg, int32_t len);
OSC_API int32_t  osc_bundle_finish(int32_t bundle_h, uint8_t *out, int32_t out_cap);
OSC_API void     osc_bundle_free(int32_t bundle_h);

/* ---- Parsing (bounds-checked indexed model over tinyosc) ----------------- */
/* Parse a datagram into a parsed-message handle (>0), or 0 on malformed input
 * (sets the last error). Handles plain messages and bundles. Always release
 * with osc_parse_free; freeing a bundle frees its sub-messages too. */
OSC_API int32_t  osc_parse(const uint8_t *data, int32_t len);
OSC_API int32_t  osc_is_bundle(int32_t h);                 /* 1 / 0 */
OSC_API uint64_t osc_bundle_timetag(int32_t h);
OSC_API int32_t  osc_bundle_count(int32_t h);              /* sub-messages */
OSC_API int32_t  osc_bundle_message(int32_t h, int32_t i); /* sub-message handle, or 0 */
/* Address / type-tag: written into the caller buffer (utf8, nul-terminated when
 * it fits). Returns the string length (excluding nul), or -needed if too small. */
OSC_API int32_t  osc_address(int32_t h, char *out, int32_t out_cap);
OSC_API int32_t  osc_typetag(int32_t h, char *out, int32_t out_cap); /* e.g. "fsi" */
OSC_API int32_t  osc_arg_count(int32_t h);
OSC_API int32_t  osc_arg_type(int32_t h, int32_t i); /* the type char, or 0 if out of range */
/* Numeric getters: *ok (out, may be NULL) is set 1 on success, 0 on a type
 * mismatch / bad index / bad handle. Value is coerced where lossless. */
OSC_API int32_t  osc_arg_int32 (int32_t h, int32_t i, int32_t *ok);
OSC_API int64_t  osc_arg_int64 (int32_t h, int32_t i, int32_t *ok);
OSC_API float    osc_arg_float (int32_t h, int32_t i, int32_t *ok);
OSC_API double   osc_arg_double(int32_t h, int32_t i, int32_t *ok);
OSC_API uint64_t osc_arg_timetag(int32_t h, int32_t i, int32_t *ok);
/* String / blob: copied into the caller buffer. Returns the byte length, or
 * -needed if too small, or -1 on a type mismatch / bad index. */
OSC_API int32_t  osc_arg_string(int32_t h, int32_t i, char *out, int32_t out_cap);
OSC_API int32_t  osc_arg_blob  (int32_t h, int32_t i, uint8_t *out, int32_t out_cap);
/* 64-bit getters as decimal strings (see the build_*_str rationale). Return the
 * string length, -needed if too small, or -1 on a type mismatch / bad index. */
OSC_API int32_t  osc_arg_int64_str   (int32_t h, int32_t i, char *out, int32_t out_cap);
OSC_API int32_t  osc_bundle_timetag_str(int32_t h, char *out, int32_t out_cap);
OSC_API void     osc_parse_free(int32_t h);

/* ---- C-side convenience string accessors (NOT for LCB) ------------------
 * These return a pointer to memory with a defined lifetime (the parsed-message
 * model owns it until osc_parse_free; the error/int64 strings are module statics).
 * That is fine for a C caller, but they MUST NOT be bound from LCB as `returns
 * ZStringUTF8`: the engine wraps a returned ZString in a foreign value whose
 * finalizer free()s the pointer (libscript module-foreign.cpp, __cbuffer_finalize).
 * Freeing a static crashes the engine; freeing a model pointer double-frees it at
 * osc_parse_free. The headless lc-run suite crashed on exactly this, so the LCB
 * binding now uses the caller-buffer getters above (osc_address, osc_typetag,
 * osc_arg_string, osc_arg_int64_str, osc_bundle_timetag_str, osc_last_error), and
 * tools/check-livecodescript.py refuses any `returns ZString*` binding. These stay
 * exported only so the ABI surface is unchanged. Return "" (never NULL). */
OSC_API const char *osc_address_str(int32_t h);
OSC_API const char *osc_typetag_str(int32_t h);
OSC_API const char *osc_error_str(void);
/* An OSC string argument, pointing inside the parsed buffer. "" on a type
 * mismatch / bad index (use osc_arg_blob for binary). Valid until osc_parse_free. */
OSC_API const char *osc_arg_string_z(int32_t h, int32_t i);
/* 64-bit reads (decimal) via a per-call static buffer, valid until the next call.
 * "" on a type mismatch / bad index. */
OSC_API const char *osc_arg_int64_z(int32_t h, int32_t i);
OSC_API const char *osc_bundle_timetag_z(int32_t h);

/* ---- Address pattern matching (OSC 1.0: ? * [ ] { } ) -------------------- */
OSC_API int32_t  osc_match(const char *pattern /*utf8*/, const char *address /*utf8*/);

/* ---- Diagnostics --------------------------------------------------------- */
/* Copy the last error string into the caller buffer (nul-terminated when it
 * fits). Returns its length, or -needed if too small. Cleared on success paths. */
OSC_API int32_t  osc_last_error(char *out, int32_t out_cap);

#ifdef __cplusplus
}
#endif

#endif /* SHOWCONTROL_OSC_SHIM_H */
