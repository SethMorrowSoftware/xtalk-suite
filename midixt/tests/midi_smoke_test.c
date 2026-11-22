/*
 * midi_smoke_test.c -- runtime smoke test for midixt's MIDI shim over the REAL RtMidi.
 *
 * Drives the same C entry points the LCB binding calls. MIDI is hardware- and
 * OS-service-dependent, so this test is written to pass in BOTH environments:
 *   - a runner WITH a working backend (ALSA seq / CoreMIDI / WinMM): it opens
 *     virtual ports, sends, drains, and closes for real;
 *   - a bare/headless runner with NO backend: every call must fail CLEANLY
 *     (error set, 0 returned) and never crash.
 * In all cases the handle-safety guards (stale/0 handle = no-op) are exercised.
 *
 * The behaviour that needs injected input or a failing RtMidi is
 * tests/midi_mock_smoke_test.c's.
 *
 * Enable with -DMIDIXT_BUILD_TESTS=ON, then run `ctest`.
 */
#include "midi_shim.h"

#include <stdio.h>
#include <string.h>

static int g_pass = 0, g_fail = 0;
static void check(const char *name, int ok) {
    printf("  [%s] %s\n", ok ? "PASS" : "FAIL", name);
    if (ok) g_pass++; else g_fail++;
}

int main(void) {
    printf("midi ABI version = %d\n", midi_abi_version());
    check("ABI version is 2", midi_abi_version() == 2);

    /* Enumeration must never crash; counts are >= 0 whether or not a backend
       and ports exist. */
    int32_t nin = midi_in_count();
    int32_t nout = midi_out_count();
    printf("  input ports = %d, output ports = %d\n", nin, nout);
    check("input count is non-negative", nin >= 0);
    check("output count is non-negative", nout >= 0);

    char nm[256];
    /* Naming an out-of-range port is a clean no-op, not a crash. */
    midi_in_name(99999, nm, sizeof nm);
    check("out-of-range port name is a no-op", 1);

    /* If real ports exist, fetching name 0 should yield a non-empty string. */
    if (nin > 0) {
        int32_t L = midi_in_name(0, nm, sizeof nm);
        check("input port 0 has a name", L > 0 && nm[0] != '\0');
        printf("    in[0] = \"%s\"\n", nm);
    }

    /* Virtual output: works on ALSA/CoreMIDI; unavailable on Windows WinMM and
       headless boxes. We assert the SAFETY contract (valid result, no crash,
       clean post-close behavior), not platform-specific send success -- real
       MIDI I/O is the self-test's Tier 3 where a MIDI service runs
       (docs/getting-started.md, "The self-test"). */
    /* An out-of-range open fails with a reason on every machine. */
    check("out-of-range output open is 0", midi_out_open(99999) == 0);
    { char e[256]; midi_last_error(e, sizeof e);
      check("  and says why", e[0] != '\0'); }

    int32_t out = midi_out_open_virtual("midixt Test Out");
    if (out != 0) {
        check("opened a virtual output", 1);
        uint8_t noteOn[3]  = {0x90, 60, 100};   /* ch1 note on  */
        int32_t s1 = midi_out_send(out, noteOn, 3);
        check("send returns a valid result (0 or 1)", s1 == 0 || s1 == 1);
        check("send zero-length is rejected", midi_out_send(out, noteOn, 0) == 0);
        midi_close(out);
        check("closed virtual output", 1);
        /* using the handle after close is a harmless no-op */
        check("send after close is a no-op", midi_out_send(out, noteOn, 3) == 0);
    } else {
        char err[256]; midi_last_error(err, sizeof err);
        printf("    (no virtual output here: %s)\n", err);
        check("failed virtual output sets an error", err[0] != '\0');
    }

    /* Virtual input + drain: drain of an idle/unconnected input is 0, not a crash. */
    int32_t in = midi_in_open_virtual("midixt Test In");
    if (in != 0) {
        check("opened a virtual input", 1);
        midi_in_ignore(in, 1, 1, 1);            /* ignore sysex/timing/sense */
        uint8_t buf[4096];
        int32_t n = midi_in_drain(in, buf, sizeof buf, 64);
        check("drain of idle input returns 0", n == 0);
        midi_close(in);
        check("closed virtual input", 1);
        check("drain after close is a no-op", midi_in_drain(in, buf, sizeof buf, 64) == 0);
    } else {
        check("virtual input open failed cleanly (no backend)", 1);
    }

    /* Stale / never-created handles are harmless no-ops everywhere. */
    uint8_t b[3] = {0x90, 60, 100};
    uint8_t big[256];
    check("drain on stale handle is 0", midi_in_drain(123456, big, sizeof big, 16) == 0);
    check("send on stale handle is 0",  midi_out_send(123456, b, 3) == 0);
    { char e[256]; midi_last_error(e, sizeof e);
      check("  and says why", strstr(e, "not an open output port") != NULL); }
    midi_in_ignore(123456, 1, 0, 0);            /* must not crash */
    midi_close(123456);                          /* must not crash */
    check("stale-handle ops did not crash", 1);

    printf("\n%d passed, %d failed\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
