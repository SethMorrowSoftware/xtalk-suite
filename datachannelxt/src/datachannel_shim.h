/* datachannel_shim.h — the C ABI surface of the DataChannelXT native library.
 *
 * This header exists for two consumers only:
 *
 *   1. datachannel_shim.cpp, which #includes it to keep its definitions and the
 *      frozen contract in dcx_abi.h in lock-step (every `dcx_*` body in the
 *      .cpp is the definition of a declaration that ultimately comes from
 *      dcx_abi.h).
 *   2. tests/datachannel_smoke_test.cpp, which #includes it to call the same
 *      exported symbols the LCB layer will call — the test exercises the REAL
 *      ABI, not a private copy of it.
 *
 * The authoritative, byte-for-byte contract is dcx_abi.h; this header just
 * re-exports it and adds the few INTERNAL test hooks the smoke test needs to
 * force conditions it cannot reach through the public surface alone (tripping
 * the exception firewall; shrinking the bounded queue to prove the overflow
 * path). Those hooks are namespaced under `dcx::test` and are NOT part of the
 * FFI — the .lcb never sees them, and they exist purely so CI can prove the
 * safety invariants. (Same shape as TorrentXT's torrent_shim.h.)
 */
#ifndef DATACHANNEL_SHIM_H
#define DATACHANNEL_SHIM_H

/* The frozen ABI contract — the full `extern "C"` dcx_* surface the shim
 * implements and the LCB binding declares. */
#include "dcx_abi.h"

#ifdef __cplusplus

/* ------------------------------------------------------------------ test hooks
 *
 * INTERNAL ONLY. C++ linkage, in dcx::test, so they can never be mistaken for
 * part of the flat FFI. DCX_API: exported with default visibility so the smoke
 * test, which links the built shared library, can resolve them under
 * -fvisibility=hidden. Add a hook only when a safety invariant genuinely
 * cannot be observed through the public ABI. */
namespace dcx {
namespace test {

/* Runs a body that always throws, through the SAME firewall macro every real
 * entry point uses. Returns the error code the firewall produced (expected
 * DCX_ERR_EXCEPTION) and leaves the module-static last-error populated,
 * exactly as a real throw would. */
DCX_API int force_throw(void);

/* Live entries in the peer / channel handle tables, so the smoke test can
 * assert create/free bookkeeping without poking module statics. */
DCX_API int live_peer_count(void);
DCX_API int live_channel_count(void);

/* Number of events currently waiting in the inbound queue (drained by
 * dcx_poll), and the count of events shed by the bounded-queue safety valve
 * since the last E_QUEUE_OVERFLOW report. */
DCX_API int queue_depth(void);
DCX_API long long dropped_count(void);

/* Shrink (or restore) the bounded queue's caps so the overflow safety valve is
 * reachable in a test without generating millions of events. Passing 0 for
 * either value restores that cap's default. TEST ONLY — the production caps
 * are compile-time constants documented in docs/architecture.md. */
DCX_API void set_queue_caps(int maxEvents, long long maxBytes);

#ifdef DCX_TEST_SEAMS
/* ------------------------------------------------------------- test seams
 *
 * Defined ONLY in the test-only `datachannelxt_seams` library (built from this
 * same shim with DCX_TEST_SEAMS; CMakeLists), never in the shipped
 * `datachannelxt`, so neither its exports nor its ABI change. They reach
 * cb_data_channel's two orphan exits (C++ gotcha 7), which no public call can
 * reach on demand; tests/orphan_channel_test.cpp drives them. */

/* The next `n` remote-initiated channels find their peer already freed. */
DCX_API void seam_forget_next_peer(int n);

/* The next `n` remote-initiated channels find the handle table full
 * (register_channel's early return; channels this side creates are not
 * counted). */
DCX_API void seam_refuse_next_inbound(int n);

/* Orphaned rtc channel ids parked for reap_orphan_channels (the next dcx_poll
 * or dcx_cleanup), and the i-th of them (0 when out of range). */
DCX_API int seam_orphans_pending(void);
DCX_API int seam_pending_orphan(int i);

/* 1 while libdatachannel still holds rtc channel id `rtcId`, else 0. */
DCX_API int seam_rtc_channel_alive(int rtcId);
#endif /* DCX_TEST_SEAMS */

}  // namespace test
}  // namespace dcx

#endif /* __cplusplus */

#endif /* DATACHANNEL_SHIM_H */
