/*
 * midi_mock_smoke_test.c -- exercises midi_shim.c's OWN logic against a MOCK of
 * RtMidi (tests/mock/rtmidi_c.h), so the trickiest, most regression-prone code in
 * the shim runs DETERMINISTICALLY, on every platform, under ASan/UBSan -- without
 * the real RtMidi and without any MIDI hardware.
 *
 * The real smoke test (midi_smoke_test.c) links actual RtMidi but, being unable to
 * inject inbound messages or make RtMidi fail on a headless runner, cannot cover:
 *   - the batched drain producing the [2B len BE][bytes][4B delta-us BE] records,
 *   - the per-port stash that guarantees "never drop a popped message" when the
 *     caller buffer fills mid-drain,
 *   - the max-SysEx (65535 B) record and the oversize (>65535) drop,
 *   - the port-name return-value handling (full length via the return value),
 *   - every way RtMidi 6.0.0 fails (rtmidi_c.h lists them) and the shim's answer.
 * This test does, by driving a controllable mock.
 *
 * The sections marked "midixt fix" each failed against ShowControl's shim (the
 * code midixt was born from): the failure is named in the section.
 *
 * Built as its own executable that compiles midi_shim.c against the mock header
 * (NOT linked to RtMidi). Enabled with -DMIDIXT_BUILD_TESTS=ON; run via ctest.
 */
#include "rtmidi_c.h"      /* the MOCK header on tests/mock (see CMakeLists) */
#include "midi_shim.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* ===================== test harness ===================== */
static int g_pass = 0, g_fail = 0;
static void check(const char *name, int ok) {
    printf("  [%s] %s\n", ok ? "PASS" : "FAIL", name);
    if (ok) g_pass++; else g_fail++;
}
static const char *last_error(void) {
    static char e[256];
    midi_last_error(e, sizeof e);
    return e;
}

/* Decode the drain buffer exactly as midi.lcb's midiPoll does -- validates the
 * record wire format end to end. */
static void decode_records(const unsigned char *buf, int n_records,
                           int *lens, unsigned char msgs[][70000], uint32_t *deltas) {
    int pos = 0;
    for (int k = 0; k < n_records; k++) {
        int len = buf[pos] * 256 + buf[pos + 1]; pos += 2;
        lens[k] = len;
        for (int i = 0; i < len; i++) msgs[k][i] = buf[pos + i];
        pos += len;
        deltas[k] = ((uint32_t) buf[pos] << 24) | ((uint32_t) buf[pos+1] << 16)
                  | ((uint32_t) buf[pos+2] << 8) | (uint32_t) buf[pos+3];
        pos += 4;
    }
}

#define KDRAINCAP 65541   /* the LCB binding's drain buffer size */
static unsigned char out[KDRAINCAP];

/* ---- midixt fix: a backend that is down at the first enumeration ----------
 * ShowControl cached the failed enumerator for the life of the process, so a
 * MIDI service that came up later was never seen: midi_in_count stayed 0. Must
 * run FIRST, before anything has made an enumerator. */
static void test_enumerator_retry(void) {
    printf("enumerator retry\n");
    mock_backend_ok = 0;
    check("no backend: in_count is 0", midi_in_count() == 0);
    check("  with a reason", strstr(last_error(), "backend") != NULL);
    mock_backend_ok = 1;
    check("backend up: the failed enumerator is retried (2 ports)", midi_in_count() == 2);
    check("  and that success cleared the error", last_error()[0] == '\0');
}

/* ---- midixt fix: a port count that throws ----------------------------------
 * RtMidi answers (unsigned)-1 and sets the sticky ok = false: ShowControl
 * returned -1 ports, then "no MIDI input backend" for ever after. */
static void test_count_failure(void) {
    printf("count failure\n");
    midimock_set_count_fail(1);
    check("a failing count is 0, never -1", midi_in_count() == 0);
    check("  with a reason", strstr(last_error(), "could not count") != NULL);
    midimock_set_count_fail(0);
    check("the next count works again (ok is not sticky here)", midi_in_count() == 2);
    check("output count too", midi_out_count() == 2);
}

static void test_names(void) {
    printf("port names\n");
    char nm[256];
    check("port name length > 0", midi_in_name(0, nm, sizeof nm) > 0);
    check("port name content", strcmp(nm, "MockPort-0-aLongishName") == 0);
    char tiny[8];
    int t = midi_in_name(0, tiny, sizeof tiny);
    check("tiny buffer reports truncation (negative)", t < 0);
    check("  asking for the full length + NUL", t == -(int) (strlen("MockPort-0-aLongishName") + 1));
    check("tiny buffer is NUL-terminated", tiny[7] == '\0');
    check("no buffer asks for the full length + NUL",
          midi_in_name(0, NULL, 0) == -(int) (strlen("MockPort-0-aLongishName") + 1));
    check("a negative index is an empty name", midi_in_name(-1, nm, sizeof nm) == 0 && nm[0] == '\0');
}

static void test_drain(int32_t in) {
    printf("drain\n");
    check("drain of empty queue -> 0", midi_in_drain(in, out, KDRAINCAP, 256) == 0);

    /* three messages: verify bytes and the microsecond delta conversion */
    mock_queue_clear();
    { unsigned char m1[3]={0x90,60,100}, m2[3]={0xB0,7,64}, m3[2]={0xC0,5};
      mock_queue_push(m1,3,0.001); mock_queue_push(m2,3,0.0005); mock_queue_push(m3,2,0.0);
      int n = midi_in_drain(in, out, KDRAINCAP, 256);
      check("drained 3 records", n == 3);
      int lens[8]; static unsigned char msgs[8][70000]; uint32_t d[8];
      decode_records(out, n, lens, msgs, d);
      check("rec0 bytes + 1000us", lens[0]==3 && msgs[0][0]==0x90 && msgs[0][2]==100 && d[0]==1000);
      check("rec1 bytes + 500us",  lens[1]==3 && msgs[1][0]==0xB0 && d[1]==500);
      check("rec2 len 2 + 0us",    lens[2]==2 && msgs[2][0]==0xC0 && d[2]==0); }

    /* max_msgs cap: 5 queued, ask 2, then 3 remain */
    mock_queue_clear();
    for (int i=0;i<5;i++){ unsigned char b[1]={0xF8}; mock_queue_push(b,1,0.0); }
    check("cap honored (2)", midi_in_drain(in, out, KDRAINCAP, 2) == 2);
    check("remaining drained (3)", midi_in_drain(in, out, KDRAINCAP, 256) == 3);

    /* STASH: a record that doesn't fit a small buffer is stashed, not dropped,
     * and emitted next drain -- no loss, no duplication, delta preserved. */
    mock_queue_clear();
    { unsigned char big[100]; memset(big,0x7F,sizeof big); big[0]=0xF0; big[99]=0xF7;
      unsigned char sm[3]={0x90,1,2};
      mock_queue_push(big,100,0.002); mock_queue_push(sm,3,0.001);
      unsigned char tinyout[64];
      check("first drain emits 0 (big stashed)", midi_in_drain(in, tinyout, sizeof tinyout, 256) == 0);
      int n2 = midi_in_drain(in, out, KDRAINCAP, 256);
      check("second drain emits 2 (stash + small)", n2 == 2);
      int lens[8]; static unsigned char msgs[8][70000]; uint32_t d[8];
      decode_records(out, n2, lens, msgs, d);
      check("flushed stash is the big msg", lens[0]==100 && msgs[0][0]==0xF0 && msgs[0][99]==0xF7);
      check("stash delta preserved (2000us)", d[0]==2000);
      check("then the small msg", lens[1]==3 && msgs[1][0]==0x90);
      check("queue now empty", midi_in_drain(in, out, KDRAINCAP, 256) == 0); }

    /* max_msgs == 0 returns 0 and PRESERVES a pending stash (return never exceeds
     * max_msgs). */
    mock_queue_clear();
    { unsigned char big[100]; memset(big,0x7F,sizeof big); big[0]=0xF0;
      unsigned char sm[2]={0x90,1};
      mock_queue_push(big,100,0.0); mock_queue_push(sm,2,0.0);
      unsigned char to[64];
      midi_in_drain(in, to, sizeof to, 256);            /* stashes big */
      check("max_msgs=0 returns 0", midi_in_drain(in, out, KDRAINCAP, 0) == 0);
      check("stash preserved across the 0-drain", midi_in_drain(in, out, KDRAINCAP, 256) == 2); }

    /* max SysEx (65535) fits exactly in kDrainCap (2+65535+4) */
    mock_queue_clear();
    { static unsigned char sx[65535]; sx[0]=0xF0; sx[65534]=0xF7;
      mock_queue_push(sx, 65535, 0.0);
      int nn = midi_in_drain(in, out, KDRAINCAP, 256);
      check("max 65535B SysEx -> one record", nn == 1);
      int lens[2]; static unsigned char msgs[2][70000]; uint32_t d[2];
      decode_records(out, nn, lens, msgs, d);
      check("record length is exactly 65535", lens[0] == 65535); }

    /* oversize (>65535) is skipped (un-representable), no crash, no wedge */
    mock_queue_clear();
    mock_oversize_next = 1;
    { unsigned char b[1]={0xF8}; mock_queue_push(b,1,0.0); mock_queue_push(b,1,0.0); }
    check("oversize skipped; next msg still delivered", midi_in_drain(in, out, KDRAINCAP, 256) == 1);
    check("oversize drop set an error", strstr(last_error(), "dropped") != NULL);
    check("the next drain clears it", midi_in_drain(in, out, KDRAINCAP, 256) == 0 && last_error()[0] == '\0');

    /* midi_in_drain_bytes (ABI 2): the same drain, returning BYTES written --
     * what the LCB binding uses to copy exactly the written bytes back out. */
    mock_queue_clear();
    { unsigned char m1[3]={0x90,60,100}, m2[2]={0xC0,5};
      mock_queue_push(m1,3,0.0); mock_queue_push(m2,2,0.0);
      int32_t nb = midi_in_drain_bytes(in, out, KDRAINCAP, 256);
      check("drain_bytes = (2+3+4) + (2+2+4) = 17", nb == 17);
      check("drain_bytes of empty queue -> 0", midi_in_drain_bytes(in, out, KDRAINCAP, 256) == 0); }
}

/* ---- midixt fix: a read that throws -----------------------------------------
 * RtMidi leaves *size untouched and the message queued. ShowControl's drain took
 * the untouched size for a giant message, skipped it and read again: one call
 * per loop turn, for ever (the mock lets it out after READ_FAIL_VALVE reads). */
static void test_read_failure(int32_t in) {
    printf("read failure\n");
    mock_queue_clear();
    { unsigned char m[3]={0x90,60,100}; mock_queue_push(m,3,0.0); }
    midimock_set_read_fail(1);
    int n = midi_in_drain(in, out, KDRAINCAP, 256);
    check("a throwing read ends the drain (0 records)", n == 0);
    check("  after ONE read, not a loop", midimock_read_fail_calls() == 1);
    check("  with a reason", strstr(last_error(), "reading the MIDI input queue failed") != NULL);
    midimock_set_read_fail(0);
    check("the queued message is delivered by the next drain", midi_in_drain(in, out, KDRAINCAP, 256) == 1);
}

/* ---- midixt fix: RtMidi's default queue of 100 --------------------------------
 * ShowControl opened inputs with RtMidi's default queue (99 usable slots), so a
 * burst of more than 99 messages between two polls was cut short, silently. */
static void test_queue_limit(int32_t in) {
    printf("queue limit\n");
    (void) in;
    check("inputs open with a 1024-message queue", midimock_queue_limit() == 1024);
    mock_queue_clear();
    int queued = 0;
    for (int i = 0; i < 500; i++) {
        unsigned char m[3] = {0xB0, (unsigned char)(i % 128), 1};
        queued += midimock_push(m, 3, 0);
    }
    check("a 500-message burst is held whole", queued == 500 && midimock_queue_depth() == 500);
    int got = 0;
    for (int k = 0; k < 4; k++) got += midi_in_drain(in, out, KDRAINCAP, 256);
    check("and drained whole (256 + 244)", got == 500);
}

/* ---- midixt fix: one failed send made every later send "fail" ----------------
 * RtMidi's ok is sticky and ShowControl judged each send by it. */
static void test_sticky_send(void) {
    printf("sticky send\n");
    int32_t o = midi_out_open_virtual("sticky out");
    unsigned char nn[3] = {0x90, 60, 100};
    midimock_sent_clear();
    midimock_set_send_fail(1);
    check("a failing send returns 0", midi_out_send(o, nn, 3) == 0);
    check("  with a reason", strstr(last_error(), "send failed") != NULL);
    midimock_set_send_fail(0);
    check("the next send succeeds (1)", midi_out_send(o, nn, 3) == 1);
    check("  and says so: no error left", last_error()[0] == '\0');
    check("  and the bytes went out", midimock_sent_count() == 1);
    midi_close(o);
}

/* ---- midixt fix: the errors ShowControl never set ----------------------------- */
static void test_send_refusals(void) {
    printf("send refusals\n");
    unsigned char nn[3] = {0x90, 60, 100};
    check("send on a stale handle -> 0", midi_out_send(999999, nn, 3) == 0);
    check("  with a reason", strstr(last_error(), "not an open output port") != NULL);
    int32_t o = midi_out_open_virtual("refusals");
    check("an empty send -> 0", midi_out_send(o, nn, 0) == 0);
    check("  with a reason", strstr(last_error(), "nothing to send") != NULL);
    check("a NULL send -> 0", midi_out_send(o, NULL, 3) == 0);
    int32_t in = midi_in_open_virtual("not an output");
    check("send on an INPUT handle -> 0", midi_out_send(in, nn, 3) == 0);
    check("  with a reason", strstr(last_error(), "not an open output port") != NULL);
    midi_close(in);
    midi_close(o);
}

/* ---- midixt: a poll of a port that is not an open input says so ---------------
 * ShowControl returned 0 with no reason, so a poll timer left running after
 * midiClose could never tell that its port was gone. */
static void test_drain_refusals(void) {
    printf("drain refusals\n");
    check("a drain of a stale handle -> 0", midi_in_drain(999999, out, KDRAINCAP, 256) == 0);
    check("  with a reason", strstr(last_error(), "not an open input port") != NULL);
    int32_t o = midi_out_open_virtual("not an input");
    check("a drain of an OUTPUT handle -> 0", midi_in_drain_bytes(o, out, KDRAINCAP, 256) == 0);
    check("  with a reason", strstr(last_error(), "not an open input port") != NULL);
    int32_t in = midi_in_open_virtual("open input");
    check("a drain of an open, empty input -> 0", midi_in_drain(in, out, KDRAINCAP, 256) == 0);
    check("  and no error", last_error()[0] == '\0');
    midi_close(in);
    check("the same handle after midi_close -> 0", midi_in_drain(in, out, KDRAINCAP, 256) == 0);
    check("  with a reason", strstr(last_error(), "not an open input port") != NULL);
    midi_close(o);
}

/* ---- midixt fix: CoreMIDI and Windows MM send one message at a time ------------
 * A 6-byte stream of two note-ons is sent whole by ALSA, but CoreMIDI and
 * Windows MM drop it with only a warning: ShowControl reported it sent. */
static void test_one_message_backends(void) {
    printf("one-message backends\n");
    unsigned char two[6] = {0x90, 60, 100, 0x90, 64, 100};
    unsigned char sx[6] = {0xF0, 0x7E, 0x7F, 0x06, 0x01, 0xF7};
    int apis[2] = {RTMIDI_API_WINDOWS_MM, RTMIDI_API_MACOSX_CORE};
    for (int k = 0; k < 2; k++) {
        midimock_set_api(apis[k]);
        int32_t o = midi_out_open(0);
        midimock_sent_clear();
        check(k == 0 ? "WinMM: a 6-byte non-SysEx send is refused (0)" : "CoreMIDI: a 6-byte non-SysEx send is refused (0)",
              midi_out_send(o, two, 6) == 0);
        check("  with a reason", strstr(last_error(), "one message at a time") != NULL);
        check("  SysEx of any length still goes", midi_out_send(o, sx, 6) == 1 && midimock_sent_count() == 1);
        check("  a 3-byte message still goes", midi_out_send(o, two, 3) == 1 && midimock_sent_count() == 2);
        midi_close(o);
    }
    midimock_set_api(RTMIDI_API_LINUX_ALSA);
    int32_t o = midi_out_open_virtual("alsa");
    midimock_sent_clear();
    check("ALSA: the same 6 bytes are sent (ALSA splits them)", midi_out_send(o, two, 6) == 1 && midimock_sent_count() == 1);
    midi_close(o);
}

/* ---- midixt fix: errors are the LAST fallible call's -------------------------- */
static void test_error_is_the_last_calls(void) {
    printf("last error\n");
    check("an out-of-range open fails", midi_out_open(99) == 0);
    check("  with a reason", strstr(last_error(), "out of range") != NULL);
    int32_t o = midi_out_open(0);
    check("a later open succeeds", o != 0);
    check("  and the old error is gone (docs: empty when the last call succeeded)", last_error()[0] == '\0');
    midi_close(o);
}

/* ---- midixt fix: a virtual port with no name ----------------------------------- */
static void test_virtual_names(void) {
    printf("virtual names\n");
    char nm[256];
    int32_t h = midi_in_open_virtual("");
    check("an empty name still opens", h != 0);
    midimock_last_port_name(nm, sizeof nm);
    check("  under the default name, not a blank one", strcmp(nm, "ShowControl In") == 0);
    midi_close(h);
    h = midi_out_open_virtual(NULL);
    midimock_last_port_name(nm, sizeof nm);
    check("NULL takes the default output name", h != 0 && strcmp(nm, "ShowControl Out") == 0);
    midi_close(h);
    h = midi_out_open_virtual("Stage Left");
    midimock_last_port_name(nm, sizeof nm);
    check("a given name is used as given", h != 0 && strcmp(nm, "Stage Left") == 0);
    midi_close(h);
}

static void test_open_failures(void) {
    printf("open failures\n");
    int live = midimock_live_wrappers();
    midimock_set_open_fail(1);
    check("an open that throws -> 0", midi_out_open_virtual("x") == 0);
    check("  with a reason", strstr(last_error(), "open port failed") != NULL);
    check("an input open that throws -> 0", midi_in_open(0) == 0);
    midimock_set_open_fail(0);
    check("  and nothing leaked", midimock_live_wrappers() == live);
    midimock_set_count_fail(1);
    check("a hardware open whose count throws -> 0", midi_in_open(0) == 0);
    check("  with a reason", strstr(last_error(), "could not count") != NULL);
    midimock_set_count_fail(0);
    check("  and nothing leaked", midimock_live_wrappers() == live);
}

int main(void) {
    printf("midi ABI = %d\n", midi_abi_version());
    check("ABI is 2", midi_abi_version() == 2);

    test_enumerator_retry();          /* first: no enumerator may exist yet */
    test_count_failure();
    test_names();
    /* the shim's cached enumerators stay alive for the process; everything opened
     * after this point must be freed again by midi_close */
    const int live_base = midimock_live_wrappers();

    int32_t in = midi_in_open_virtual("test");
    check("opened a virtual input", in != 0);
    test_drain(in);
    test_read_failure(in);
    test_queue_limit(in);

    /* virtual cable: with loopback on, an output's sends arrive on the input side,
     * and every send is logged byte-for-byte. */
    mock_queue_clear();
    midimock_set_loopback(1, 250);
    { int32_t o = midi_out_open_virtual("loop out");
      unsigned char nn[3]={0x91,64,127};
      check("loopback: send ok", midi_out_send(o, nn, 3) == 1);
      check("loopback: send logged", midimock_sent_count() >= 1);
      unsigned char got[8]; int32_t gl = midimock_sent_get(midimock_sent_count()-1, got, sizeof got);
      check("loopback: logged bytes exact", gl == 3 && got[0]==0x91 && got[1]==64 && got[2]==127);
      int n = midi_in_drain(in, out, KDRAINCAP, 256);
      int lens[2]; static unsigned char msgs[2][70000]; uint32_t d[2];
      decode_records(out, n, lens, msgs, d);
      check("loopback: arrives on the input", n == 1 && lens[0] == 3 && msgs[0][0] == 0x91);
      check("loopback: stamped delta (250us)", n == 1 && d[0] == 250);
      midi_close(o); }
    midimock_set_loopback(0, 0);

    midi_close(in);
    check("drain after close -> 0", midi_in_drain(in, out, KDRAINCAP, 256) == 0);

    /* stale-handle safety */
    check("drain on stale handle -> 0", midi_in_drain(999999, out, KDRAINCAP, 256) == 0);

    test_sticky_send();
    test_send_refusals();
    test_drain_refusals();
    test_one_message_backends();
    test_error_is_the_last_calls();
    test_virtual_names();
    test_open_failures();

    /* headless backend: a freshly opened port fails cleanly (open_port makes a
     * fresh instance each call, so this is independent of the cached enumerator). */
    mock_backend_ok = 0;
    check("no-backend open fails cleanly", midi_in_open(0) == 0);
    check("failed open set an error", last_error()[0] != '\0');
    mock_backend_ok = 1;

    /* Windows MM has no virtual ports and RtMidi only WARNS: the shim must refuse
     * (0 + error) rather than return a handle that silently sends nowhere. */
    midimock_set_api(RTMIDI_API_WINDOWS_MM);
    check("WinMM: virtual output refused", midi_out_open_virtual("v") == 0);
    check("WinMM: refusal names loopMIDI", strstr(last_error(), "loopMIDI") != NULL);
    check("WinMM: virtual input refused", midi_in_open_virtual("v") == 0);
    { int32_t h = midi_out_open(0); check("WinMM: hardware port still opens", h != 0); midi_close(h); }
    midimock_set_api(RTMIDI_API_LINUX_ALSA);

    /* every port this test opened was freed by midi_close (only the shim's cached
     * enumerators, counted in live_base, stay alive) */
    check("no leaked RtMidi instances", midimock_live_wrappers() == live_base);

    mock_queue_clear();
    printf("\n%d passed, %d failed\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
