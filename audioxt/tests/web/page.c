/*
 * page.c - the web archive behind a handful of calls, for a real browser.
 *
 * tests/smoke_test.c and tests/fuzz_test.c run the archive under node, which
 * has no Web Audio: they prove the mixer, the decoders and every refusal.
 * What they cannot reach is the one thing a browser adds, a DEVICE: that
 * miniaudio's own JavaScript survived the relocatable link, finds Web Audio,
 * starts on the visitor's first click (the browser's rule) and pulls sound
 * out of the engine, and that a microphone delivers samples.
 * run-web-test.cjs drives this page in headless Chromium and reads these.
 *
 * It calls the shim's real exports and nothing else, as the engine will.
 */
#include <emscripten.h>
#include <stdlib.h>
#include <string.h>

extern int aux_abi_version(void);
extern const char *aux_last_error(void);
extern const char *aux_backend_name(void);
extern int aux_device_scan(void);
extern int aux_playback_device_count(void);
extern int aux_engine_create(int device, int sampleRate, int channels);
extern int aux_engine_sample_rate(int engine);
extern double aux_engine_time(int engine);
extern const char *aux_engine_peak(int engine);
extern int aux_sound_tone(int engine, const char *shape, double hertz, double amplitude);
extern void aux_sound_start(int sound);
extern int aux_sound_is_playing(int sound);
extern int aux_capture_open(int device, const char *format, int sampleRate, int channels, double bufferSeconds);
extern int aux_capture_start(int capture);
extern int aux_capture_available(int capture);
extern int aux_capture_read(int capture);
extern double aux_capture_peak(int capture);
extern int aux_engine_is_valid(int engine);
extern void aux_shut_down(void);

static int s_engine = 0, s_tone = 0, s_mic = 0;

EMSCRIPTEN_KEEPALIVE int w_abi(void) { return aux_abi_version(); }
EMSCRIPTEN_KEEPALIVE const char *w_error(void) { return aux_last_error(); }
EMSCRIPTEN_KEEPALIVE const char *w_backend(void) { return aux_backend_name(); }
EMSCRIPTEN_KEEPALIVE int w_scan(void) { return aux_device_scan(); }
EMSCRIPTEN_KEEPALIVE int w_playback_count(void) { return aux_playback_device_count(); }

/* The default device, and a tone started on it at once: BEFORE any click,
 * which is how a stack's openStack would do it. Returns the sample rate. */
EMSCRIPTEN_KEEPALIVE int w_start(void)
{
    s_engine = aux_engine_create(0, 0, 0);
    if (s_engine == 0) return 0;
    s_tone = aux_sound_tone(s_engine, "sine", 440.0, 0.2);
    aux_sound_start(s_tone);
    return aux_engine_sample_rate(s_engine);
}
EMSCRIPTEN_KEEPALIVE double w_time(void) { return aux_engine_time(s_engine); }
EMSCRIPTEN_KEEPALIVE double w_peak(void) { return atof(aux_engine_peak(s_engine)); }
EMSCRIPTEN_KEEPALIVE int w_playing(void) { return aux_sound_is_playing(s_tone); }

/* The default microphone, 16-bit mono at 16 kHz, started. Returns the handle. */
EMSCRIPTEN_KEEPALIVE int w_mic_start(void)
{
    s_mic = aux_capture_open(0, "s16", 16000, 1, 2.0);
    if (s_mic == 0) return 0;
    return aux_capture_start(s_mic) ? s_mic : 0;
}
EMSCRIPTEN_KEEPALIVE int w_mic_available(void) { return aux_capture_available(s_mic); }
EMSCRIPTEN_KEEPALIVE int w_mic_read(void) { return aux_capture_read(s_mic); }
EMSCRIPTEN_KEEPALIVE double w_mic_peak(void) { return aux_capture_peak(s_mic); }

/* For a page that cannot have Web Audio or a microphone (run-web-test.cjs
 * takes one away before the page loads): a device of each kind opened, as a
 * stack's script would. Each returns the handle, or 0 when it was refused
 * (w_error says why). There, miniaudio's own JavaScript would throw, and a
 * throw unwinds through the whole engine; the shim asks the page first. */
EMSCRIPTEN_KEEPALIVE int w_try_engine(void) { return aux_engine_create(0, 0, 0); }
EMSCRIPTEN_KEEPALIVE int w_try_mic(void) { return aux_capture_open(0, "s16", 16000, 1, 2.0); }

/* Returns 1 if everything was closed. */
EMSCRIPTEN_KEEPALIVE int w_stop(void)
{
    aux_shut_down();
    return aux_engine_is_valid(s_engine) ? 0 : 1;
}

int main(void) { return 0; }
