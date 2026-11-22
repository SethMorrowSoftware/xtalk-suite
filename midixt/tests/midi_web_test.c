/*
 * tests/midi_web_test.c -- the web build's test (wasm32-emscripten), run by
 * node. Linked against the ARCHIVE that ships (src/code/wasm32-emscripten/
 * midixt.a, built by CMakeLists.txt's web branch), so what is tested is the
 * committed file: the shim over src/midi_web.c, through the same midi_* calls
 * the binding makes. node has no Web MIDI, so tests/web/fake-web-midi.js
 * stands in for the browser's (it says what it does and does not do); each
 * scene is one run, a fresh page:
 *
 *   node midi_web_test.js none|refused|framed|pending|granted
 *
 *   none     no Web MIDI: every count is 0 and says so (and says when the
 *            page is not secure), opens refuse, stale handles stay harmless;
 *            the ABI and the table the engine finds the library through
 *   refused  the first call asks, with SysEx; the refusal is said, and stands:
 *            nothing asks again, and a virtual port never asks at all
 *   framed   a frame whose permissions policy leaves MIDI out: refused at
 *            once, nothing asked
 *   pending  an unanswered question: counts are 0 and say so, asked once
 *   granted  ports listed and named (a disconnected one left out), opened,
 *            a message out and back through a loop cable, its time, the
 *            filters, several messages in one send, a send the browser
 *            refuses and why, a port that went away, an open the browser
 *            refused, the queue's limit, a message too big for a record, two
 *            handles on one input, a close that lets the device go, and a
 *            browser that throws
 *
 * Asyncify (the link) lets the test wait for the browser's answer, a promise,
 * between two calls, as a script waits on its timer.
 */
#include "midi_shim.h"

#include <emscripten.h>

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int g_failures = 0;
static int g_checks = 0;

#define CHECK(cond)                                                      \
    do {                                                                 \
        ++g_checks;                                                      \
        if (cond) {                                                      \
            printf("ok    %s\n", #cond);                                 \
        } else {                                                         \
            printf("FAIL  %s  (line %d; last error: %s)\n", #cond,       \
                   __LINE__, last_error());                              \
            ++g_failures;                                                \
        }                                                                \
    } while (0)

/* ---- what the shim says ------------------------------------------------- */

static const char *last_error(void) {
    static char buf[512];
    int32_t n = midi_last_error(buf, (int32_t) sizeof buf);
    if (n < 0) buf[0] = '\0';
    return buf;
}
static int error_says(const char *words) { return strstr(last_error(), words) != NULL; }
static int error_empty(void) { return last_error()[0] == '\0'; }

static int in_name_is(int32_t i, const char *want) {
    char buf[64];
    int32_t n = midi_in_name(i, buf, (int32_t) sizeof buf);
    return n == (int32_t) strlen(want) && strcmp(buf, want) == 0;
}
static int out_name_is(int32_t i, const char *want) {
    char buf[64];
    int32_t n = midi_out_name(i, buf, (int32_t) sizeof buf);
    return n == (int32_t) strlen(want) && strcmp(buf, want) == 0;
}

/* ---- the drain's records ------------------------------------------------ */

typedef struct { uint8_t bytes[8]; int len; uint32_t delta_us; } record;

static uint8_t g_block[2 + 65535 + 4];

/* Drain one input into recs (at most cap of them kept); returns the count. */
static int drain(int32_t h, record *recs, int cap) {
    int32_t bytes = midi_in_drain_bytes(h, g_block, (int32_t) sizeof g_block, 256);
    int count = 0, at = 0;
    while (at + 6 <= bytes) {
        int len = (g_block[at] << 8) | g_block[at + 1];
        if (count < cap) {
            recs[count].len = len;
            memcpy(recs[count].bytes, g_block + at + 2, len < 8 ? (size_t) len : 8);
            const uint8_t *d = g_block + at + 2 + len;
            recs[count].delta_us = ((uint32_t) d[0] << 24) | ((uint32_t) d[1] << 16)
                                 | ((uint32_t) d[2] << 8) | (uint32_t) d[3];
        }
        at += 2 + len + 4;
        count++;
    }
    return count;
}
static int is_bytes(const record *r, const uint8_t *want, int len) {
    return r->len == len && memcmp(r->bytes, want, (size_t) len) == 0;
}

/* ---- the stand-in browser (tests/web/fake-web-midi.js) ------------------ */

static void install(int scene) { EM_ASM({ midixtFake.install($0); }, scene); }
static int asks(void) { return EM_ASM_INT({ return midixtFake.asks; }); }
static int asked_sysex(void) {
    return EM_ASM_INT({ return (midixtFake.options && midixtFake.options.sysex === true) ? 1 : 0; });
}
static int sent_count(void) { return EM_ASM_INT({ return midixtFake.sent.length; }); }
static int listeners(int input) {
    return EM_ASM_INT({ return midixtFake.inputs[$0].listeners.length; }, input);
}
static int closes(void) { return EM_ASM_INT({ return midixtFake.closes; }); }
/* The keyboard (input 1) plays: one message, at a time in ms the test gives */
static void play3(int b0, int b1, int b2, double at_ms) {
    EM_ASM({ midixtFake.inputs[1].receive([$0, $1, $2], $3); }, b0, b1, b2, at_ms);
}
static void play1(int b0, double at_ms) {
    EM_ASM({ midixtFake.inputs[1].receive([$0], $1); }, b0, at_ms);
}

/* The browser answers on its own event loop: let it */
static void let_the_browser_run(void) { emscripten_sleep(20); }

/* ---- the table the engine finds the library through --------------------- */

struct midixt_web_export { const char *symbol; void *address; };
const struct midixt_web_export *midixt_web_exports(void);

static void *table_address(const char *symbol) {
    const struct midixt_web_export *t = midixt_web_exports();
    for (; t && t->symbol; t++)
        if (strcmp(t->symbol, symbol) == 0) return t->address;
    return NULL;
}

/* ======================================================================== */

static void scene_none(void) {
    install(0);
    CHECK(midi_abi_version() == MIDI_ABI_VERSION);
    /* the table names what the binding binds, at the functions themselves */
    CHECK(table_address("midi_abi_version") == (void *) midi_abi_version);
    CHECK(table_address("midi_in_drain_bytes") == (void *) midi_in_drain_bytes);
    CHECK(table_address("midi_out_send") == (void *) midi_out_send);
    CHECK(table_address("midi_last_error") == (void *) midi_last_error);
    CHECK(table_address("midimock_reset") == NULL);

    CHECK(midi_in_count() == 0);
    CHECK(error_says("midi: no MIDI input backend: this browser has no Web MIDI"));
    CHECK(midi_out_count() == 0);
    CHECK(error_says("midi: no MIDI output backend: this browser has no Web MIDI"));
    CHECK(midi_in_open(0) == 0);
    CHECK(error_says("backend init failed") && error_says("this browser has no Web MIDI"));
    CHECK(midi_out_open(0) == 0);
    CHECK(midi_out_open_virtual("midixt") == 0);
    CHECK(error_says("midi: a web page has no virtual ports"));

    /* a page that is not secure is told why it has no Web MIDI */
    EM_ASM({ globalThis.isSecureContext = false; });
    CHECK(midi_in_count() == 0);
    CHECK(error_says("only to a secure page (https)"));
    EM_ASM({ delete globalThis.isSecureContext; });

    /* names of nothing, stale handles: harmless, and they say why */
    char buf[16] = "x";
    CHECK(midi_in_name(0, buf, (int32_t) sizeof buf) == 0 && buf[0] == '\0');
    CHECK(midi_out_name(-1, buf, (int32_t) sizeof buf) == 0);
    uint8_t on[3] = {0x90, 60, 100};
    CHECK(midi_out_send(12345, on, 3) == 0);
    CHECK(error_says("midi: not an open output port"));
    CHECK(midi_in_drain_bytes(12345, g_block, (int32_t) sizeof g_block, 256) == 0);
    CHECK(error_says("midi: not an open input port"));
    midi_close(12345);
    midi_in_ignore(12345, 0, 0, 0);

    /* nothing was ever asked of a browser that cannot be asked */
    CHECK(asks() == 0);
}

static void scene_refused(void) {
    install(1);
    CHECK(midi_in_count() == 0);
    CHECK(error_says("asked the browser whether this page may use MIDI"));
    CHECK(asks() == 1 && asked_sysex());
    CHECK(midi_out_count() == 0);
    CHECK(error_says("has not yet answered"));
    CHECK(asks() == 1);
    let_the_browser_run();
    CHECK(midi_in_count() == 0);
    CHECK(error_says("the browser refused this page MIDI (NotAllowedError: The person said no.)"));
    CHECK(midi_in_open(0) == 0);
    CHECK(error_says("midi: backend init failed (no MIDI service available?): the browser refused"));
    CHECK(midi_out_open_virtual("midixt") == 0);
    CHECK(error_says("no virtual ports"));
    let_the_browser_run();
    CHECK(midi_out_count() == 0);
    CHECK(error_says("refused"));
    /* the refusal stands: asked once, for the life of the page */
    CHECK(asks() == 1);
}

static void scene_framed(void) {
    install(2);
    CHECK(midi_in_count() == 0);
    CHECK(error_says("this page may not use MIDI: the frame it is shown in does not allow it"));
    CHECK(midi_out_open(0) == 0);
    CHECK(error_says("does not allow it"));
    let_the_browser_run();
    CHECK(midi_out_count() == 0);
    CHECK(asks() == 0);
}

static void scene_pending(void) {
    install(3);
    CHECK(midi_in_count() == 0);
    CHECK(error_says("asked the browser"));
    let_the_browser_run();
    CHECK(midi_in_count() == 0);
    CHECK(error_says("has not yet answered whether this page may use MIDI"));
    CHECK(midi_in_open(0) == 0);
    CHECK(asks() == 1);
}

static void scene_granted(void) {
    record r[8];
    install(4);

    /* asked once, with SysEx; the ports appear with the answer */
    CHECK(midi_in_count() == 0);
    CHECK(asks() == 1 && asked_sysex());
    let_the_browser_run();
    CHECK(midi_in_count() == 3);          /* the unplugged pad is not offered */
    CHECK(error_empty());
    CHECK(midi_out_count() == 2);
    CHECK(asks() == 1);

    /* names, by position, and the caller-buffer rules */
    CHECK(in_name_is(0, "Loop Cable"));
    CHECK(in_name_is(1, "Fake Keyboard"));
    CHECK(in_name_is(2, "Busy Port"));
    CHECK(out_name_is(0, "Loop Cable"));
    CHECK(out_name_is(1, "Fake Synth"));
    char small[4];
    CHECK(midi_in_name(1, small, (int32_t) sizeof small) == -(int32_t) (strlen("Fake Keyboard") + 1));
    CHECK(midi_in_name(1, NULL, 0) == -(int32_t) (strlen("Fake Keyboard") + 1));
    CHECK(midi_in_name(3, small, (int32_t) sizeof small) == 0 && small[0] == '\0');

    /* no virtual ports, and the index is checked */
    CHECK(midi_in_open_virtual("") == 0 && error_says("no virtual ports"));
    CHECK(midi_in_open(3) == 0 && error_says("midi: port index out of range"));
    CHECK(midi_out_open(2) == 0 && error_says("midi: port index out of range"));

    /* the cable: a message out, and back through the input */
    int32_t out = midi_out_open(0);
    int32_t in = midi_in_open(0);
    CHECK(out > 0 && in > 0 && error_empty());
    CHECK(listeners(0) == 1);
    uint8_t on[3] = {0x90, 60, 100};
    CHECK(midi_out_send(out, on, 3) == 1 && error_empty());
    CHECK(sent_count() == 1);
    CHECK(drain(in, r, 8) == 0);          /* not yet: the browser delivers later */
    let_the_browser_run();
    CHECK(drain(in, r, 8) == 1 && is_bytes(&r[0], on, 3) && r[0].delta_us == 0);
    CHECK(error_empty());

    /* several messages in one send, each its own record */
    uint8_t two[6] = {0x90, 64, 90, 0x80, 64, 0};
    CHECK(midi_out_send(out, two, 6) == 1);
    let_the_browser_run();
    CHECK(drain(in, r, 8) == 2 && is_bytes(&r[0], two, 3) && is_bytes(&r[1], two + 3, 3));

    /* SysEx goes out; the input drops it until it is let through (RtMidi's
     * default ignores SysEx, time and sensing) */
    uint8_t sx[5] = {0xF0, 0x7D, 0x01, 0x02, 0xF7};
    CHECK(midi_out_send(out, sx, 5) == 1);
    let_the_browser_run();
    CHECK(drain(in, r, 8) == 0);
    midi_in_ignore(in, 0, 1, 1);
    CHECK(midi_out_send(out, sx, 5) == 1);
    let_the_browser_run();
    CHECK(drain(in, r, 8) == 1 && is_bytes(&r[0], sx, 5));

    /* bytes the browser refuses: refused, with the browser's words */
    uint8_t stray[2] = {64, 100};
    CHECK(midi_out_send(out, stray, 2) == 0);
    CHECK(error_says("midi: send failed: TypeError: ") && error_says("Running status is not allowed"));
    uint8_t cut[2] = {0x90, 60};
    CHECK(midi_out_send(out, cut, 2) == 0 && error_says("incomplete"));
    CHECK(midi_out_send(out, on, 3) == 1 && error_empty());   /* and the next send is judged alone */
    let_the_browser_run();
    CHECK(drain(in, r, 8) == 1);
    /* the shim's own refusals come first, as on a desktop */
    CHECK(midi_out_send(out, NULL, 0) == 0 && error_says("midi: nothing to send"));
    CHECK(midi_out_send(in, on, 3) == 0 && error_says("midi: not an open output port"));

    /* time: seconds between the messages a port took, the first 0; what the
     * filters drop does not count */
    int32_t keys = midi_in_open(1);
    CHECK(keys > 0);
    play3(0x90, 60, 100, 1000.0);
    play3(0x80, 60, 0, 1250.5);
    play1(0xF8, 1300.0);                  /* clock: dropped */
    play1(0xFE, 1301.0);                  /* active sensing: dropped */
    play3(0xF1, 0x20, 0, 1302.0);         /* time code: dropped (its two bytes, and a pad) */
    play3(0xB0, 7, 100, 1400.0);
    CHECK(drain(keys, r, 8) == 3);
    CHECK(r[0].delta_us == 0 && r[1].delta_us == 250500 && r[2].delta_us == 149500);
    midi_in_ignore(keys, 0, 0, 0);
    play1(0xF8, 1500.0);
    play1(0xFE, 1500.25);
    CHECK(drain(keys, r, 8) == 2 && r[0].bytes[0] == 0xF8 && r[0].delta_us == 100000
          && r[1].bytes[0] == 0xFE && r[1].delta_us == 250);

    /* two handles on one input: each gets every message */
    int32_t keys2 = midi_in_open(1);
    CHECK(keys2 > 0 && listeners(1) == 2);
    play3(0x90, 61, 99, 1600.0);
    CHECK(drain(keys, r, 8) == 1 && drain(keys2, r, 8) == 1);

    /* the queue holds 1023 (RtMidi's ring, one short of the 1024 the shim
     * asks for); what arrives on a full queue is dropped */
    int i, total = 0, n;
    for (i = 0; i < 1100; i++) play3(0x90, i % 128, 1, 2000.0 + i);
    while ((n = drain(keys, r, 8)) > 0) total += n;
    CHECK(total == 1023);
    while (drain(keys2, r, 8) > 0) {}

    /* a message bigger than a record carries: popped, said, never wedged */
    midi_in_ignore(keys, 0, 1, 1);
    EM_ASM({
        var big = new Array(70000).fill(1);
        big[0] = 0xF0; big[big.length - 1] = 0xF7;
        midixtFake.inputs[1].receive(big, 3000.0);
    });
    play3(0x90, 62, 80, 3001.0);
    CHECK(drain(keys, r, 8) == 1 && r[0].bytes[0] == 0x90);
    CHECK(error_says("dropped an inbound message larger than 65535 bytes"));
    CHECK(drain(keys, r, 8) == 0 && error_empty());

    /* close: the listener goes; the last close lets the device go */
    int closed_before = closes();
    midi_close(keys);
    CHECK(listeners(1) == 1 && closes() == closed_before);
    midi_close(keys2);
    CHECK(listeners(1) == 0 && closes() == closed_before + 1);
    play3(0x90, 63, 70, 4000.0);
    CHECK(drain(keys, r, 8) == 0 && error_says("midi: not an open input port"));
    midi_close(keys);                     /* a second close: harmless */

    /* an input the browser could not open: said at every poll until it is
     * closed (a listener that ignores the first must not go quiet after it) */
    int32_t busy = midi_in_open(2);
    CHECK(busy > 0);
    let_the_browser_run();
    CHECK(drain(busy, r, 8) == 0);
    CHECK(error_says("midi: reading the MIDI input queue failed: the browser could not open Busy Port (InvalidAccessError: The port is in use by another program.)"));
    CHECK(drain(busy, r, 8) == 0 && error_says("the browser could not open Busy Port"));
    midi_close(busy);
    CHECK(drain(busy, r, 8) == 0 && error_says("midi: not an open input port"));

    /* an output the browser could not open: every send says why, and nothing
     * is handed to the browser */
    EM_ASM({ midixtFake.outputs[1].refuseOpen = new DOMException("The synth is asleep.", "InvalidAccessError"); });
    int32_t asleep = midi_out_open(1);
    CHECK(asleep > 0);
    let_the_browser_run();
    int sent_before = sent_count();
    CHECK(midi_out_send(asleep, on, 3) == 0 && error_says("midi: send failed: the browser could not open Fake Synth (InvalidAccessError: The synth is asleep.)"));
    CHECK(midi_out_send(asleep, on, 3) == 0 && error_says("the browser could not open Fake Synth"));
    CHECK(sent_count() == sent_before);
    midi_close(asleep);
    EM_ASM({ midixtFake.outputs[1].refuseOpen = null; });

    /* an output that went away: its sends fail, and say so */
    int32_t synth = midi_out_open(1);
    CHECK(synth > 0 && midi_out_send(synth, on, 3) == 1);
    EM_ASM({ midixtFake.outputs[1].state = "disconnected"; });
    CHECK(midi_out_send(synth, on, 3) == 0 && error_says("InvalidStateError"));
    CHECK(midi_out_count() == 1);         /* and it is no longer offered */
    midi_close(synth);

    /* a browser that throws while listing: a refused count, not a dead engine */
    EM_ASM({ midixtFake.throwOnList = true; });
    CHECK(midi_in_count() == 0);
    CHECK(error_says("midi: could not count the MIDI ports: Error: the device list went away"));
    CHECK(midi_in_count() == 3 && error_empty());

    /* the cable still works after all that, and closes cleanly */
    CHECK(midi_out_send(out, on, 3) == 1);
    let_the_browser_run();
    CHECK(drain(in, r, 8) == 1 && is_bytes(&r[0], on, 3));
    midi_close(in);
    midi_close(out);
    CHECK(listeners(0) == 0);
    CHECK(midi_out_send(out, on, 3) == 0 && error_says("midi: not an open output port"));
    CHECK(asks() == 1);
}

int main(int argc, char **argv) {
    const char *scene = argc > 1 ? argv[1] : "";
    if (strcmp(scene, "none") == 0) scene_none();
    else if (strcmp(scene, "refused") == 0) scene_refused();
    else if (strcmp(scene, "framed") == 0) scene_framed();
    else if (strcmp(scene, "pending") == 0) scene_pending();
    else if (strcmp(scene, "granted") == 0) scene_granted();
    else {
        printf("usage: node midi_web_test.js none|refused|framed|pending|granted\n");
        return 2;
    }
    printf("%s: %d checks, %d failed\n", scene, g_checks, g_failures);
    /* exit(), not return: a main that has slept (Asyncify) returns into
     * nothing under node, so its value never became the exit status and every
     * failing run exited 0. A layer broken on purpose found it: the scene
     * printed its FAIL lines and ctest passed all five. exit() with
     * -sEXIT_RUNTIME=1 (the link) reaches the process; ctest's
     * FAIL_REGULAR_EXPRESSION holds the printed verdict too. */
    exit(g_failures ? 1 : 0);
}
