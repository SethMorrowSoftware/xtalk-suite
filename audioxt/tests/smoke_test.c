/*
 * smoke_test.c - the runtime test of audioxt's C shim (src/audio_shim.c).
 *
 * It is a CLIENT of the built library, exactly as the engine's FFI is: it
 * links audioxt.{so,dll,dylib} (or, for the web, the archive that would
 * ship) and calls the aux_* exports by name. Every export is entered at
 * least once; tools/check-smoke-coverage.py holds that, and holds the
 * declaration block below to the shim's own definitions.
 *
 * WHAT CAN BE HEARD IS NOT WHAT IS TESTED. A CI runner has no sound card, so
 * nearly everything here runs on an OFFLINE engine: the mixer is pulled by
 * aux_engine_render and the test measures the samples it gets back, which
 * is exact where listening would be a guess. Devices are tested through
 * miniaudio's "null" backend (device -1): a real device thread running in
 * real time, playing into nothing and recording silence. The machine's own
 * default playback device is opened once, and the test only REPORTS whether
 * that worked: a machine with no audio is not a failed build. The default
 * microphone is never opened (on a desktop that would raise a permission
 * prompt in the middle of a build).
 *
 * The web build runs this under node, where there is no audio system and no
 * thread: the device section is compiled out there, and says so.
 *
 * Exit status 0 and a last line "audioxt smoke: N checks, 0 failed" is a
 * pass; anything else is not.
 */
#if !defined(_WIN32)
    #define _POSIX_C_SOURCE 200809L     /* nanosleep */
#endif
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fixtures.h"

#if defined(_WIN32)
    #include <windows.h>
    static void sleep_ms(int ms) { Sleep((DWORD)ms); }
#else
    #include <time.h>
    static void sleep_ms(int ms)
    {
        struct timespec ts;
        ts.tv_sec = ms / 1000;
        ts.tv_nsec = (long)(ms % 1000) * 1000000L;
        nanosleep(&ts, NULL);
    }
#endif

/* >>> BEGIN SHIM DECLARATIONS (generated: tools/check-smoke-coverage.py --write) >>> */
/* 114 exports, in the shim's order. Plain declarations: the test is a client of
 * the built library, exactly as the engine's FFI is. */
extern int aux_abi_version(void);
extern const char*aux_library_version(void);
extern const char*aux_last_error(void);
extern int aux_text_length(const char*text);
extern const void*aux_out_pointer(void);
extern int aux_out_sample_rate(void);
extern int aux_out_channels(void);
extern const char*aux_backend_name(void);
extern int aux_device_scan(void);
extern int aux_playback_device_count(void);
extern const char*aux_playback_device_name(int index);
extern int aux_playback_device_is_default(int index);
extern int aux_capture_device_count(void);
extern const char*aux_capture_device_name(int index);
extern int aux_capture_device_is_default(int index);
extern int aux_engine_create(int device, int sampleRate, int channels);
extern int aux_engine_create_offline(int sampleRate, int channels);
extern void aux_engine_free(int engine);
extern int aux_engine_is_valid(int engine);
extern int aux_engine_is_offline(int engine);
extern void aux_engine_start(int engine);
extern void aux_engine_stop(int engine);
extern void aux_engine_set_volume(int engine, double volume);
extern double aux_engine_volume(int engine);
extern int aux_engine_sample_rate(int engine);
extern int aux_engine_channels(int engine);
extern double aux_engine_time(int engine);
extern int aux_engine_sound_count(int engine);
extern const char*aux_engine_device_name(int engine);
extern void aux_engine_stop_all(int engine);
extern const char*aux_engine_peak(int engine);
extern const char*aux_engine_waveform(int engine, int points);
extern int aux_engine_render(int engine, int frames, const char*format);
extern void aux_engine_set_listener_position(int engine, double x, double y, double z);
extern const char*aux_engine_listener_position(int engine);
extern void aux_engine_set_listener_direction(int engine, double x, double y, double z);
extern const char*aux_engine_listener_direction(int engine);
extern void aux_engine_set_listener_up(int engine, double x, double y, double z);
extern void aux_engine_set_listener_velocity(int engine, double x, double y, double z);
extern int aux_sound_load(int engine, const char*path, int stream);
extern int aux_sound_load_data(int engine, const void*bytes, int length, int stream);
extern int aux_sound_from_pcm(int engine, const void*bytes, int length, const char*format, int sampleRate, int channels);
extern int aux_sound_tone(int engine, const char*shape, double hertz, double amplitude);
extern int aux_sound_noise(int engine, const char*color, double amplitude);
extern int aux_sound_clone(int sound);
extern void aux_sound_free(int sound);
extern int aux_sound_is_valid(int sound);
extern int aux_sound_engine(int sound);
extern void aux_sound_start(int sound);
extern void aux_sound_start_at(int sound, double seconds);
extern void aux_sound_stop(int sound);
extern void aux_sound_stop_at(int sound, double seconds);
extern void aux_sound_stop_with_fade(int sound, double seconds);
extern void aux_sound_fade(int sound, double from, double to, double seconds);
extern int aux_sound_is_playing(int sound);
extern int aux_sound_at_end(int sound);
extern void aux_sound_seek(int sound, double seconds);
extern double aux_sound_position(int sound);
extern double aux_sound_length(int sound);
extern void aux_sound_set_volume(int sound, double volume);
extern double aux_sound_volume(int sound);
extern void aux_sound_set_pan(int sound, double pan);
extern double aux_sound_pan(int sound);
extern void aux_sound_set_pitch(int sound, double pitch);
extern double aux_sound_pitch(int sound);
extern void aux_sound_set_looping(int sound, int flag);
extern int aux_sound_is_looping(int sound);
extern void aux_sound_set_loop_range(int sound, double startSeconds, double endSeconds);
extern void aux_sound_set_frequency(int sound, double hertz);
extern void aux_sound_set_auto_free(int sound, int flag);
extern void aux_sound_set_group(int sound, int group);
extern int aux_sound_group(int sound);
extern void aux_sound_set_spatial(int sound, int flag);
extern int aux_sound_is_spatial(int sound);
extern void aux_sound_set_position(int sound, double x, double y, double z);
extern const char*aux_sound_position_xyz(int sound);
extern void aux_sound_set_velocity(int sound, double x, double y, double z);
extern void aux_sound_set_distance_range(int sound, double nearest, double farthest);
extern void aux_sound_set_rolloff(int sound, double rolloff);
extern void aux_sound_set_doppler(int sound, double factor);
extern int aux_group_create(int engine);
extern void aux_group_free(int group);
extern int aux_group_is_valid(int group);
extern void aux_group_set_volume(int group, double volume);
extern double aux_group_volume(int group);
extern void aux_group_set_pan(int group, double pan);
extern double aux_group_pan(int group);
extern void aux_group_set_pitch(int group, double pitch);
extern double aux_group_pitch(int group);
extern void aux_group_start(int group);
extern void aux_group_stop(int group);
extern int aux_poll_ended(void);
extern int aux_ended_sound(int index);
extern int aux_capture_open(int device, const char*format, int sampleRate, int channels, double bufferSeconds);
extern void aux_capture_close(int capture);
extern int aux_capture_is_valid(int capture);
extern int aux_capture_start(int capture);
extern void aux_capture_stop(int capture);
extern int aux_capture_is_running(int capture);
extern int aux_capture_available(int capture);
extern int aux_capture_read(int capture);
extern const char*aux_capture_format(int capture);
extern int aux_capture_sample_rate(int capture);
extern int aux_capture_channels(int capture);
extern const char*aux_capture_device_label(int capture);
extern int aux_capture_dropped(int capture);
extern double aux_capture_peak(int capture);
extern int aux_capture_record_start(int capture, const char*savePath);
extern double aux_capture_record_stop(int capture);
extern int aux_capture_is_recording(int capture);
extern int aux_decode_file(const char*path, const char*format, int sampleRate, int channels);
extern int aux_decode_data(const void*bytes, int length, const char*format, int sampleRate, int channels);
extern int aux_wav_encode(const void*bytes, int length, const char*format, int sampleRate, int channels);
extern void aux_shut_down(void);
/* <<< END SHIM DECLARATIONS <<< */

static int s_checks = 0;
static int s_failed = 0;

static void check_at(int ok, const char *what, int line)
{
    s_checks++;
    if (!ok) {
        s_failed++;
        printf("FAIL line %d: %s   (last error: \"%s\")\n", line, what, aux_last_error());
    }
}
#define CHECK(cond, what) check_at((cond) ? 1 : 0, what, __LINE__)

static int near(double a, double b, double tol) { return fabs(a - b) <= tol; }

/* The n-th comma-separated number of a text result. */
static double item(const char *text, int n)
{
    const char *p = text;
    for (int i = 1; i < n && p; i++) {
        p = strchr(p, ',');
        if (p) p++;
    }
    return p ? atof(p) : 0.0;
}

static int items(const char *text)
{
    int n = 1;
    if (text == NULL || text[0] == 0) return 0;
    for (const char *p = text; *p; p++) if (*p == ',') n++;
    return n;
}

/* The loudest f32 sample of each of two channels in the out buffer. */
static void out_peaks(int bytes, int channels, double *left, double *right)
{
    const float *f = (const float *)aux_out_pointer();
    int frames = bytes / (int)sizeof(float) / channels;
    *left = 0.0;
    *right = 0.0;
    for (int i = 0; i < frames; i++) {
        double l = fabs((double)f[i * channels]);
        double r = fabs((double)f[i * channels + (channels > 1 ? 1 : 0)]);
        if (l > *left) *left = l;
        if (r > *right) *right = r;
    }
}

/* Renders `frames` of an offline stereo engine and returns the louder side. */
static double render_peak(int engine, int frames)
{
    double l, r;
    int bytes = aux_engine_render(engine, frames, "f32");
    if (bytes <= 0) return -1.0;
    out_peaks(bytes, 2, &l, &r);
    return l > r ? l : r;
}

static int write_file(const char *path, const void *bytes, size_t n)
{
    FILE *f = fopen(path, "wb");
    if (!f) return 0;
    size_t w = fwrite(bytes, 1, n, f);
    fclose(f);
    return w == n;
}

/* A sine as s16 mono: the test's own source of truth for the file tests. */
#define TONE_RATE 8000
static short *make_tone(double seconds, double hertz, double amplitude, int *frames)
{
    int n = (int)(seconds * TONE_RATE);
    short *s = (short *)malloc((size_t)n * sizeof(short));
    for (int i = 0; i < n; i++)
        s[i] = (short)(amplitude * 32767.0 * sin(2.0 * 3.14159265358979323846 * hertz * i / TONE_RATE));
    *frames = n;
    return s;
}

static const char *k_wav_short = "audioxt-smoke-short.wav";
static const char *k_wav_long = "audioxt-smoke-long.wav";
static const char *k_wav_rec = "audioxt-smoke-recorded.wav";

/* ------------------------------------------------------------------ */
static void test_library(void)
{
    CHECK(aux_abi_version() == 1, "the ABI number is 1");
    const char *v = aux_library_version();
    CHECK(strstr(v, "audioxt ABI 1; miniaudio ") == v, "the version text names the ABI and miniaudio");
    CHECK(aux_text_length(v) == (int)strlen(v), "text_length measures a text result");
    CHECK(aux_text_length(NULL) == 0, "text_length of nothing is 0");
    CHECK(aux_last_error()[0] == 0, "no error before anything was refused");
    CHECK(aux_out_pointer() != NULL, "the out pointer is never NULL");
    CHECK(aux_out_sample_rate() == 0 && aux_out_channels() == 0, "the out buffer has no format before the first use");
}

/* A handle that never was, on every export that takes one: nothing crashes,
 * getters answer 0 or empty. */
static void test_stale(int h)
{
    aux_engine_free(h);
    CHECK(aux_engine_is_valid(h) == 0, "stale engine: not valid");
    CHECK(aux_engine_is_offline(h) == 0, "stale engine: not offline");
    aux_engine_start(h);
    aux_engine_stop(h);
    aux_engine_set_volume(h, 0.5);
    CHECK(aux_engine_volume(h) == 0.0, "stale engine: volume 0");
    CHECK(aux_engine_sample_rate(h) == 0 && aux_engine_channels(h) == 0, "stale engine: no format");
    CHECK(aux_engine_time(h) == 0.0, "stale engine: time 0");
    CHECK(aux_engine_sound_count(h) == 0, "stale engine: no sounds");
    CHECK(aux_engine_device_name(h)[0] == 0, "stale engine: no device name");
    aux_engine_stop_all(h);
    CHECK(aux_engine_peak(h)[0] == 0, "stale engine: empty peak");
    CHECK(aux_engine_waveform(h, 16)[0] == 0, "stale engine: empty waveform");
    CHECK(aux_engine_render(h, 100, "f32") == 0, "stale engine: renders nothing");
    aux_engine_set_listener_position(h, 1, 2, 3);
    aux_engine_set_listener_direction(h, 0, 0, -1);
    aux_engine_set_listener_up(h, 0, 1, 0);
    aux_engine_set_listener_velocity(h, 1, 0, 0);
    CHECK(aux_engine_listener_position(h)[0] == 0, "stale engine: empty listener position");
    CHECK(aux_engine_listener_direction(h)[0] == 0, "stale engine: empty listener direction");

    CHECK(aux_sound_load(h, k_wav_short, 0) == 0, "stale engine: loads nothing");
    CHECK(aux_sound_load_data(h, k_flac, (int)sizeof(k_flac), 0) == 0, "stale engine: loads no data");
    CHECK(aux_sound_from_pcm(h, k_flac, 64, "s16", 8000, 1) == 0, "stale engine: takes no samples");
    CHECK(aux_sound_tone(h, "sine", 440, 0.5) == 0, "stale engine: no tone");
    CHECK(aux_sound_noise(h, "white", 0.5) == 0, "stale engine: no noise");
    CHECK(aux_group_create(h) == 0, "stale engine: no group");

    CHECK(aux_sound_clone(h) == 0, "stale sound: no clone");
    aux_sound_free(h);
    CHECK(aux_sound_is_valid(h) == 0, "stale sound: not valid");
    CHECK(aux_sound_engine(h) == 0, "stale sound: no engine");
    aux_sound_start(h);
    aux_sound_start_at(h, 1.0);
    aux_sound_stop(h);
    aux_sound_stop_at(h, 1.0);
    aux_sound_stop_with_fade(h, 0.1);
    aux_sound_fade(h, 0, 1, 0.1);
    CHECK(aux_sound_is_playing(h) == 0 && aux_sound_at_end(h) == 0, "stale sound: not playing, not ended");
    aux_sound_seek(h, 0.1);
    CHECK(aux_sound_position(h) == 0.0 && aux_sound_length(h) == 0.0, "stale sound: no position, no length");
    aux_sound_set_volume(h, 0.5);
    aux_sound_set_pan(h, 0.5);
    aux_sound_set_pitch(h, 2.0);
    CHECK(aux_sound_volume(h) == 0.0 && aux_sound_pan(h) == 0.0 && aux_sound_pitch(h) == 0.0, "stale sound: 0 everywhere");
    aux_sound_set_looping(h, 1);
    CHECK(aux_sound_is_looping(h) == 0, "stale sound: not looping");
    aux_sound_set_loop_range(h, 0.0, 0.1);
    aux_sound_set_frequency(h, 220);
    aux_sound_set_auto_free(h, 1);
    aux_sound_set_group(h, 0);
    CHECK(aux_sound_group(h) == 0, "stale sound: no group");
    aux_sound_set_spatial(h, 1);
    CHECK(aux_sound_is_spatial(h) == 0, "stale sound: not spatial");
    aux_sound_set_position(h, 1, 2, 3);
    CHECK(aux_sound_position_xyz(h)[0] == 0, "stale sound: empty position");
    aux_sound_set_velocity(h, 1, 0, 0);
    aux_sound_set_distance_range(h, 1, 10);
    aux_sound_set_rolloff(h, 1);
    aux_sound_set_doppler(h, 1);

    aux_group_free(h);
    CHECK(aux_group_is_valid(h) == 0, "stale group: not valid");
    aux_group_set_volume(h, 0.5);
    aux_group_set_pan(h, 0.5);
    aux_group_set_pitch(h, 2.0);
    CHECK(aux_group_volume(h) == 0.0 && aux_group_pan(h) == 0.0 && aux_group_pitch(h) == 0.0, "stale group: 0 everywhere");
    aux_group_start(h);
    aux_group_stop(h);

    aux_capture_close(h);
    CHECK(aux_capture_is_valid(h) == 0, "stale capture: not valid");
    CHECK(aux_capture_start(h) == 0, "stale capture: does not start");
    aux_capture_stop(h);
    CHECK(aux_capture_is_running(h) == 0, "stale capture: not running");
    CHECK(aux_capture_available(h) == 0 && aux_capture_read(h) == 0, "stale capture: nothing to read");
    CHECK(aux_capture_format(h)[0] == 0, "stale capture: no format");
    CHECK(aux_capture_sample_rate(h) == 0 && aux_capture_channels(h) == 0, "stale capture: no rate, no channels");
    CHECK(aux_capture_device_label(h)[0] == 0, "stale capture: no device label");
    CHECK(aux_capture_dropped(h) == 0 && aux_capture_peak(h) == 0.0, "stale capture: nothing dropped, no peak");
    CHECK(aux_capture_record_start(h, k_wav_rec) == 0, "stale capture: records nothing");
    CHECK(aux_capture_record_stop(h) == 0.0, "stale capture: nothing recorded");
    CHECK(aux_capture_is_recording(h) == 0, "stale capture: not recording");
}

static void test_engine_and_tone(void)
{
    CHECK(aux_engine_create_offline(1, 2) == 0 && aux_last_error()[0] != 0, "an offline engine at 1 Hz is refused, with a reason");
    CHECK(aux_engine_create_offline(48000, 9) == 0, "nine channels are refused");
    CHECK(aux_engine_create_offline(0, 2) == 0, "an offline engine needs a rate");
    int e = aux_engine_create_offline(48000, 2);
    CHECK(e > 0 && aux_last_error()[0] == 0, "an offline engine is made, and the error is cleared");
    CHECK(aux_engine_is_valid(e) && aux_engine_is_offline(e), "it is valid and offline");
    CHECK(aux_engine_sample_rate(e) == 48000 && aux_engine_channels(e) == 2, "it has the rate and channels asked for");
    CHECK(aux_engine_device_name(e)[0] == 0, "an offline engine has no device name");
    CHECK(near(aux_engine_volume(e), 1.0, 1e-6), "its volume starts at 1");
    CHECK(aux_engine_time(e) == 0.0, "its clock starts at 0");

    CHECK(render_peak(e, 4800) == 0.0, "an engine with no sounds renders silence");
    CHECK(aux_out_sample_rate() == 48000 && aux_out_channels() == 2, "the out buffer says what the render was");
    CHECK(near(aux_engine_time(e), 0.1, 1e-9), "4800 frames at 48000 is a tenth of a second");
    CHECK(aux_engine_render(e, 0, "f32") == 0, "rendering 0 frames is refused");
    CHECK(aux_engine_render(e, 100, "f64") == 0, "an unknown format is refused");
    CHECK(aux_engine_render(e, 100, NULL) == 0, "a missing format is refused");
    CHECK(aux_engine_render(e, 100, "s16") == 100 * 2 * 2, "s16 is two bytes a sample");
    CHECK(aux_engine_render(e, 100, "u8") == 100 * 2 * 1, "u8 is one");
    CHECK(aux_engine_render(e, 100, "s24") == 100 * 2 * 3, "s24 is three");
    CHECK(aux_engine_render(e, 100, "s32") == 100 * 2 * 4, "s32 is four");

    CHECK(aux_sound_tone(e, "bell", 440, 0.5) == 0, "an unknown shape is refused");
    CHECK(aux_sound_tone(e, NULL, 440, 0.5) == 0, "a missing shape is refused");
    CHECK(aux_sound_tone(e, "sine", 0, 0.5) == 0, "0 Hz is refused");
    CHECK(aux_sound_tone(e, "sine", 440, 2.0) == 0, "an amplitude of 2 is refused");
    CHECK(aux_sound_tone(e, "sine", NAN, 0.5) == 0, "a frequency that is not a number is refused");
    int t = aux_sound_tone(e, "sine", 440, 0.5);
    CHECK(t > 0, "a sine tone is made");
    CHECK(aux_sound_is_valid(t) && aux_sound_engine(t) == e, "it is valid and knows its engine");
    CHECK(aux_engine_sound_count(e) == 1, "the engine counts one sound");
    CHECK(!aux_sound_is_playing(t), "a new sound is not playing");
    CHECK(render_peak(e, 4800) == 0.0, "and is not heard");
    CHECK(aux_sound_length(t) == 0.0, "a tone has no length");
    aux_sound_start(t);
    CHECK(aux_sound_is_playing(t), "started, it is playing");
    double p = render_peak(e, 4800);
    CHECK(near(p, 0.5, 0.01), "a 0.5 sine peaks at 0.5");
    const char *pk = aux_engine_peak(e);
    CHECK(items(pk) == 2 && near(item(pk, 1), 0.5, 0.01) && near(item(pk, 2), 0.5, 0.01), "the meter saw 0.5 on both sides");
    pk = aux_engine_peak(e);
    CHECK(item(pk, 1) == 0.0 && item(pk, 2) == 0.0, "reading the meter reset it");
    const char *w = aux_engine_waveform(e, 64);
    CHECK(items(w) == 64, "a 64-point waveform has 64 numbers");
    double wmax = 0.0;
    for (int i = 1; i <= 64; i++) if (fabs(item(w, i)) > wmax) wmax = fabs(item(w, i));
    CHECK(wmax > 0.2 && wmax <= 0.5001, "and they follow the sine");
    CHECK(aux_engine_waveform(e, 0)[0] == 0 && aux_engine_waveform(e, 4096)[0] == 0, "0 and 4096 points are refused");
    CHECK(items(aux_engine_waveform(e, 2048)) == 2048, "2048 points fit");

    /* volume, pan, pitch */
    aux_sound_set_volume(t, 0.5);
    CHECK(near(aux_sound_volume(t), 0.5, 1e-6), "the volume reads back");
    CHECK(near(render_peak(e, 4800), 0.25, 0.01), "half volume is half the peak");
    aux_sound_set_volume(t, -1);
    aux_sound_set_volume(t, NAN);
    aux_sound_set_volume(t, 1000);
    CHECK(near(aux_sound_volume(t), 0.5, 1e-6), "a negative, a NaN and a huge volume are refused");
    aux_sound_set_volume(t, 1.0);
    aux_sound_set_pan(t, 1.0);
    CHECK(near(aux_sound_pan(t), 1.0, 1e-6), "the pan reads back");
    {
        double l, r;
        int bytes = aux_engine_render(e, 4800, "f32");
        bytes = aux_engine_render(e, 4800, "f32");
        out_peaks(bytes, 2, &l, &r);
        CHECK(l < 0.01 && r > 0.3, "panned right, the left side is silent");
    }
    aux_sound_set_pan(t, 5);
    CHECK(near(aux_sound_pan(t), 1.0, 1e-6), "a pan of 5 is refused");
    aux_sound_set_pan(t, 0.0);
    aux_sound_set_pitch(t, 2.0);
    CHECK(near(aux_sound_pitch(t), 2.0, 1e-6), "the pitch reads back");
    aux_sound_set_pitch(t, 0.0);
    CHECK(near(aux_sound_pitch(t), 2.0, 1e-6), "a pitch of 0 is refused");
    aux_sound_set_pitch(t, 1.0);
    aux_sound_set_frequency(t, 880);
    aux_sound_set_frequency(t, -5);
    CHECK(render_peak(e, 4800) > 0.3, "a tone still sounds after its frequency changed");

    /* the engine's own volume, and stop */
    aux_engine_set_volume(e, 0.5);
    CHECK(near(aux_engine_volume(e), 0.5, 1e-6), "the engine volume reads back");
    render_peak(e, 4800);
    CHECK(near(render_peak(e, 4800), 0.25, 0.02), "and halves the mix");
    aux_engine_set_volume(e, -3);
    CHECK(near(aux_engine_volume(e), 0.5, 1e-6), "a negative engine volume is refused");
    aux_engine_set_volume(e, 1.0);
    aux_sound_stop(t);
    CHECK(!aux_sound_is_playing(t), "stopped, it is not playing");
    render_peak(e, 4800);
    CHECK(render_peak(e, 4800) == 0.0, "and not heard");
    aux_engine_start(e);
    aux_engine_stop(e);
    CHECK(aux_engine_is_valid(e), "start and stop do nothing to an offline engine");

    /* the other shapes, and noise */
    static const char *shapes[] = { "square", "triangle", "sawtooth" };
    for (int i = 0; i < 3; i++) {
        int s = aux_sound_tone(e, shapes[i], 220, 0.25);
        CHECK(s > 0, "another shape is made");
        aux_sound_start(s);
        CHECK(near(render_peak(e, 4800), 0.25, 0.03), "and peaks at its amplitude");
        aux_sound_free(s);
        CHECK(!aux_sound_is_valid(s), "freed, it is not valid");
    }
    static const char *colors[] = { "white", "pink" };
    for (int i = 0; i < 2; i++) {
        int s = aux_sound_noise(e, colors[i], 0.25);
        CHECK(s > 0, "noise is made");
        aux_sound_start(s);
        double np = render_peak(e, 4800);
        CHECK(np > 0.0 && np <= 0.2501, "and is heard, within its amplitude");
        aux_sound_set_frequency(s, 440);
        CHECK(strstr(aux_last_error(), "only a tone") != NULL, "noise has no frequency");
        aux_sound_free(s);
    }
    CHECK(aux_sound_noise(e, "brown", 0.25) == 0 && aux_sound_noise(e, NULL, 0.25) == 0, "an unknown colour is refused");
    CHECK(aux_sound_noise(e, "white", -1) == 0, "a negative amplitude is refused");
    CHECK(aux_sound_clone(t) == 0, "a tone cannot be cloned");
    aux_sound_set_loop_range(t, 0, 1);
    CHECK(strstr(aux_last_error(), "no loop range") != NULL, "a tone has no loop range");

    aux_engine_stop_all(e);
    aux_engine_free(e);
    CHECK(!aux_engine_is_valid(e) && !aux_sound_is_valid(t), "freeing the engine freed its sound");
}

/* The files the later tests load, and the decoders' round trips. */
static void test_codecs(void)
{
    int frames = 0, longFrames = 0;
    short *tone = make_tone(0.5, 440, 0.5, &frames);
    short *longTone = make_tone(3.0, 330, 0.5, &longFrames);

    CHECK(aux_wav_encode(tone, 0, "s16", TONE_RATE, 1) == 0, "encoding nothing is refused");
    CHECK(aux_wav_encode(NULL, 100, "s16", TONE_RATE, 1) == 0, "encoding from nowhere is refused");
    CHECK(aux_wav_encode(tone, frames * 2, "mp3", TONE_RATE, 1) == 0, "encoding to an unknown format is refused");
    CHECK(aux_wav_encode(tone, frames * 2, "s16", 100, 1) == 0, "a 100 Hz file is refused");
    CHECK(aux_wav_encode(tone, frames * 2, "s16", TONE_RATE, 0) == 0, "a file of no channels is refused");
    CHECK(aux_wav_encode(tone, 1, "s16", TONE_RATE, 1) == 0, "less than one frame is refused");
    int n = aux_wav_encode(tone, frames * 2, "s16", TONE_RATE, 1);
    CHECK(n == 44 + frames * 2, "a WAV file is its samples and a 44-byte header");
    const unsigned char *wav = (const unsigned char *)aux_out_pointer();
    CHECK(n > 12 && memcmp(wav, "RIFF", 4) == 0 && memcmp(wav + 8, "WAVE", 4) == 0, "and starts RIFF....WAVE");
    unsigned char *wavCopy = (unsigned char *)malloc((size_t)n);
    memcpy(wavCopy, wav, (size_t)n);
    CHECK(write_file(k_wav_short, wavCopy, (size_t)n), "the short file is written");

    int dn = aux_decode_data(wavCopy, n, "s16", 0, 0);
    CHECK(dn == frames * 2, "decoding the WAV gives the samples back");
    CHECK(dn == frames * 2 && memcmp(aux_out_pointer(), tone, (size_t)dn) == 0, "bit for bit");
    CHECK(aux_out_sample_rate() == TONE_RATE && aux_out_channels() == 1, "with the file's own rate and channels");
    /* the out buffer handed straight back in: the shim must copy first */
    n = aux_wav_encode(aux_out_pointer(), dn, "s16", TONE_RATE, 1);
    CHECK(n == 44 + frames * 2 && memcmp(aux_out_pointer(), wavCopy, (size_t)n) == 0, "encoding from the out buffer itself works");
    dn = aux_decode_data(aux_out_pointer(), n, "s16", 0, 0);
    CHECK(dn == frames * 2 && memcmp(aux_out_pointer(), tone, (size_t)dn) == 0, "and so does decoding from it");

    dn = aux_decode_file(k_wav_short, "f32", 16000, 2);
    CHECK(near(dn, frames * 2 * 2 * 4, 64), "decoding to f32 16000 stereo converts: twice the frames, two channels, four bytes");
    CHECK(aux_out_sample_rate() == 16000 && aux_out_channels() == 2, "and says so");
    {
        double l, r;
        out_peaks(dn, 2, &l, &r);
        CHECK(near(l, 0.5, 0.02) && near(r, 0.5, 0.02), "and the converted sound still peaks at 0.5");
    }
    CHECK(aux_decode_file("no-such-file.wav", "s16", 0, 0) == 0 && aux_last_error()[0] != 0, "a missing file is refused, with a reason");
    CHECK(aux_decode_file("", "s16", 0, 0) == 0 && aux_decode_file(NULL, "s16", 0, 0) == 0, "an empty path is refused");
    CHECK(aux_decode_file(k_wav_short, "s8", 0, 0) == 0, "an unknown format is refused");
    CHECK(aux_decode_file(k_wav_short, "s16", 5, 0) == 0, "a rate of 5 is refused");
    CHECK(aux_decode_file(k_wav_short, "s16", 0, 99) == 0, "99 channels are refused");
    CHECK(aux_decode_data(NULL, 10, "s16", 0, 0) == 0 && aux_decode_data(wavCopy, 0, "s16", 0, 0) == 0, "no data is refused");
    CHECK(aux_decode_data("this is not a sound file at all, not even nearly", 48, "s16", 0, 0) == 0, "data that is no sound file is refused");
    CHECK(aux_decode_data(wavCopy, 20, "s16", 0, 0) == 0, "half a header is refused");

    /* FLAC is lossless: the fixture is 2000 frames of a known sine. MP3 is
     * not, and pads: at least the frames, and about the right loudness. */
    dn = aux_decode_data(k_flac, (int)sizeof(k_flac), "s16", 0, 0);
    CHECK(dn == 2000 * 2, "the FLAC fixture decodes to its 2000 frames");
    CHECK(aux_out_sample_rate() == 8000 && aux_out_channels() == 1, "at 8000 Hz, mono");
    dn = aux_decode_data(k_mp3, (int)sizeof(k_mp3), "f32", 0, 0);
    CHECK(dn >= 2000 * 4 && dn < 6000 * 4, "the MP3 fixture decodes to its frames and some padding");
    {
        const float *f = (const float *)aux_out_pointer();
        double pk = 0.0;
        for (int i = 0; i < dn / 4; i++) if (fabs((double)f[i]) > pk) pk = fabs((double)f[i]);
        CHECK(pk > 0.05 && pk < 1.0, "and it is a sound, not silence and not noise at full scale");
    }
    /* A truncated file must be refused or decode short, never read past it. */
    for (int cut = 1; cut < (int)sizeof(k_flac); cut += 37) aux_decode_data(k_flac, cut, "s16", 0, 0);
    for (int cut = 1; cut < (int)sizeof(k_mp3); cut += 17) aux_decode_data(k_mp3, cut, "s16", 0, 0);
    CHECK(1, "truncated FLAC and MP3 data did not crash the decoders");

    n = aux_wav_encode(longTone, longFrames * 2, "s16", TONE_RATE, 1);
    CHECK(n == 44 + longFrames * 2 && write_file(k_wav_long, aux_out_pointer(), (size_t)n), "the long file is written");

    free(wavCopy);
    free(tone);
    free(longTone);
}

/* Renders in small steps until the sound has ended (or a second of trying
 * has passed: a stream is read ahead on another thread). Returns the
 * loudest sample heard. */
static double play_out(int engine, int sound, double seconds)
{
    double pk = 0.0;
    int steps = (int)(seconds * 48000.0 / 2400.0) + 400;
    for (int i = 0; i < steps && aux_sound_is_playing(sound) && !aux_sound_at_end(sound); i++) {
        double p = render_peak(engine, 2400);
        if (p > pk) pk = p;
        if (i > (int)(seconds * 20.0)) sleep_ms(2);
    }
    /* miniaudio marks the end in the block that reaches it and stops the
     * sound (and reports the end) in the NEXT block it mixes. */
    render_peak(engine, 480);
    return pk;
}

static void test_sounds(void)
{
    int e = aux_engine_create_offline(48000, 2);
    CHECK(e > 0, "an engine for the file tests");

    CHECK(aux_sound_load(e, "no-such-file.wav", 0) == 0 && aux_last_error()[0] != 0, "loading a missing file is refused, with a reason");
    CHECK(aux_sound_load(e, "no-such-file.wav", 1) == 0, "streaming a missing file is refused");
    CHECK(aux_sound_load(e, NULL, 0) == 0 && aux_sound_load(e, "", 0) == 0, "an empty path is refused");

    /* loaded whole */
    int s = aux_sound_load(e, k_wav_short, 0);
    CHECK(s > 0, "the short file loads whole");
    CHECK(near(aux_sound_length(s), 0.5, 0.01), "it is half a second long");
    CHECK(aux_sound_position(s) == 0.0, "it starts at 0");
    CHECK(aux_poll_ended() == 0, "nothing has ended yet");
    aux_sound_start(s);
    double pk = play_out(e, s, 0.5);
    CHECK(near(pk, 0.5, 0.05), "it plays, peaking at the file's 0.5");
    CHECK(aux_sound_at_end(s) && !aux_sound_is_playing(s), "then it is at its end and no longer playing");
    CHECK(aux_poll_ended() == 1 && aux_ended_sound(1) == s, "poll reports it ended, once");
    CHECK(aux_ended_sound(0) == 0 && aux_ended_sound(2) == 0, "outside the list there is no sound");
    CHECK(aux_poll_ended() == 0, "and not again");
    aux_sound_start(s);
    CHECK(aux_sound_is_playing(s) && !aux_sound_at_end(s), "an ended sound starts again from the beginning");
    render_peak(e, 4800);
    CHECK(aux_sound_position(s) > 0.05 && aux_sound_position(s) < 0.2, "its position follows the play");
    aux_sound_stop(s);
    double at = aux_sound_position(s);
    render_peak(e, 4800);
    CHECK(aux_sound_position(s) == at, "stopped, it keeps its place");
    aux_sound_seek(s, 0.25);
    CHECK(near(aux_sound_position(s), 0.25, 0.01), "seek moves it");
    aux_sound_seek(s, -1);
    CHECK(near(aux_sound_position(s), 0.25, 0.01), "a negative position is refused");

    /* clones: one set of samples, many players */
    int c1 = aux_sound_clone(s), c2 = aux_sound_clone(s);
    CHECK(c1 > 0 && c2 > 0 && c1 != c2 && c1 != s, "two clones, three handles");
    CHECK(near(aux_sound_length(c1), 0.5, 0.01), "a clone has the same length");
    CHECK(aux_engine_sound_count(e) == 3, "the engine counts three sounds");
    aux_sound_seek(s, 0);
    aux_sound_start(s);
    aux_sound_start(c1);
    aux_sound_start(c2);
    render_peak(e, 2400);
    CHECK(render_peak(e, 2400) > 0.9, "three at once are three times as loud (in phase)");
    aux_sound_stop(c1);
    aux_sound_set_volume(c2, 0.0);
    render_peak(e, 2400);
    CHECK(near(render_peak(e, 2400), 0.5, 0.06), "each clone has its own state");
    aux_sound_free(s);
    CHECK(!aux_sound_is_valid(s) && aux_sound_is_valid(c1), "freeing the original leaves its clones");
    aux_sound_set_volume(c2, 1.0);
    aux_sound_seek(c2, 0);
    CHECK(near(play_out(e, c2, 0.5), 0.5, 0.06), "and they still play");
    aux_sound_free(c1);
    aux_sound_free(c2);
    aux_poll_ended();

    /* streamed: three seconds, so the reader has to keep ahead */
    int st = aux_sound_load(e, k_wav_long, 1);
    CHECK(st > 0, "the long file opens as a stream");
    CHECK(near(aux_sound_length(st), 3.0, 0.01), "it is three seconds long");
    CHECK(aux_sound_clone(st) == 0, "a stream cannot be cloned");
    aux_sound_start(st);
    pk = play_out(e, st, 3.0);
    CHECK(near(pk, 0.5, 0.05), "it plays through");
    CHECK(aux_sound_at_end(st), "to its end");
    CHECK(aux_poll_ended() == 1 && aux_ended_sound(1) == st, "and poll reports it");
    aux_sound_free(st);

    /* from bytes, whole and streamed, FLAC and MP3 */
    CHECK(aux_sound_load_data(e, NULL, 100, 0) == 0 && aux_sound_load_data(e, k_flac, 0, 0) == 0, "no data is refused");
    CHECK(aux_sound_load_data(e, "certainly not a sound file, whatever else it is", 47, 0) == 0, "data that is no sound file is refused, whole");
    CHECK(aux_sound_load_data(e, "certainly not a sound file, whatever else it is", 47, 1) == 0, "and streamed");
    for (int stream = 0; stream <= 1; stream++) {
        int f = aux_sound_load_data(e, k_flac, (int)sizeof(k_flac), stream);
        CHECK(f > 0, "the FLAC bytes load");
        CHECK(near(aux_sound_length(f), 0.25, 0.01), "a quarter second");
        aux_sound_start(f);
        pk = play_out(e, f, 0.25);
        CHECK(pk > 0.05 && aux_sound_at_end(f), "and play to the end");
        CHECK((aux_sound_clone(f) > 0) == (stream == 0), "only the whole one can be cloned");
        int m = aux_sound_load_data(e, k_mp3, (int)sizeof(k_mp3), stream);
        CHECK(m > 0, "the MP3 bytes load");
        aux_sound_start(m);
        pk = play_out(e, m, 0.4);
        CHECK(pk > 0.05 && aux_sound_at_end(m), "and play to the end");
        aux_sound_free(f);
        aux_sound_free(m);
    }
    aux_poll_ended();

    /* raw samples, looping, the loop range */
    int frames = 0;
    short *tone = make_tone(0.2, 440, 0.5, &frames);
    CHECK(aux_sound_from_pcm(e, tone, frames * 2, "s17", TONE_RATE, 1) == 0, "an unknown format is refused");
    CHECK(aux_sound_from_pcm(e, tone, frames * 2, "s16", 1, 1) == 0, "a rate of 1 is refused");
    CHECK(aux_sound_from_pcm(e, tone, frames * 2, "s16", TONE_RATE, 0) == 0, "no channels are refused");
    CHECK(aux_sound_from_pcm(e, tone, 1, "s16", TONE_RATE, 1) == 0, "less than a frame is refused");
    CHECK(aux_sound_from_pcm(e, NULL, 100, "s16", TONE_RATE, 1) == 0, "no samples are refused");
    int p = aux_sound_from_pcm(e, tone, frames * 2 + 1, "s16", TONE_RATE, 1);
    CHECK(p > 0, "raw samples make a sound (an odd trailing byte ignored)");
    memset(tone, 0, (size_t)frames * 2);        /* the shim copied: ours can go */
    free(tone);
    CHECK(near(aux_sound_length(p), 0.2, 0.005), "a fifth of a second");
    aux_sound_set_looping(p, 1);
    CHECK(aux_sound_is_looping(p), "looping reads back");
    aux_sound_start(p);
    pk = 0.0;
    for (int i = 0; i < 20; i++) { double q = render_peak(e, 4800); if (q > pk) pk = q; }
    CHECK(near(pk, 0.5, 0.05) && aux_sound_is_playing(p) && !aux_sound_at_end(p), "two seconds on, a looping 0.2 s sound still plays");
    CHECK(aux_poll_ended() == 0, "and a looping sound never ends");
    aux_sound_set_loop_range(p, 0.05, 0.1);
    for (int i = 0; i < 10; i++) render_peak(e, 4800);
    CHECK(aux_sound_position(p) >= 0.049 && aux_sound_position(p) <= 0.101, "inside a loop range it stays inside");
    aux_sound_set_loop_range(p, 0.1, 0.05);
    CHECK(strstr(aux_last_error(), "loop range") != NULL, "a range that ends before it starts is refused");
    aux_sound_set_loop_range(p, 0, 0);
    aux_sound_set_looping(p, 0);
    CHECK(!aux_sound_is_looping(p), "looping turns off");
    play_out(e, p, 0.3);
    CHECK(aux_sound_at_end(p), "and then it ends");
    CHECK(aux_poll_ended() == 1, "and is reported");

    /* auto-free: play and forget */
    int a = aux_sound_clone(p);
    aux_sound_set_auto_free(a, 1);
    aux_sound_start(a);
    play_out(e, a, 0.3);
    CHECK(aux_sound_is_valid(a), "an auto-free sound lives until the poll");
    CHECK(aux_poll_ended() == 1 && aux_ended_sound(1) == a, "the poll reports it");
    CHECK(!aux_sound_is_valid(a), "and has freed it");
    aux_sound_free(p);

    aux_engine_free(e);
}

static void test_schedule_and_fades(void)
{
    int e = aux_engine_create_offline(48000, 2);
    int t = aux_sound_tone(e, "sine", 440, 0.5);
    double now = aux_engine_time(e);

    aux_sound_start_at(t, now + 0.1);
    CHECK(render_peak(e, 4800) == 0.0, "before its start time a scheduled sound is silent");
    CHECK(render_peak(e, 4800) > 0.3, "at its start time it sounds");
    now = aux_engine_time(e);
    aux_sound_stop_at(t, now + 0.1);
    CHECK(render_peak(e, 4800) > 0.3, "before its stop time it still sounds");
    CHECK(render_peak(e, 4800) == 0.0, "after it, silence");
    aux_sound_start(t);
    render_peak(e, 480);
    CHECK(render_peak(e, 4800) > 0.3, "a plain start after a scheduled stop plays again");
    aux_sound_start_at(t, -1);
    aux_sound_stop_at(t, NAN);
    CHECK(render_peak(e, 4800) > 0.3, "a negative or NaN time is refused and changes nothing");

    aux_sound_stop_with_fade(t, 0.1);
    double first = render_peak(e, 2400);
    double second = render_peak(e, 2400);
    CHECK(first > second && second < 0.3, "a fade-out gets quieter");
    render_peak(e, 4800);
    CHECK(render_peak(e, 4800) == 0.0, "and ends in silence");
    aux_sound_start(t);
    render_peak(e, 480);
    CHECK(render_peak(e, 4800) > 0.3, "a start after a fade-out is at full volume again");

    aux_sound_fade(t, 0.0, 1.0, 0.2);
    first = render_peak(e, 2400);
    render_peak(e, 4800);
    second = render_peak(e, 4800);
    CHECK(first < 0.2 && second > 0.4, "a fade-in gets louder");
    aux_sound_fade(t, -1, 0.5, 0.05);
    render_peak(e, 4800);
    CHECK(near(render_peak(e, 4800), 0.25, 0.02), "a fade from 'where it is' lands on its target");
    aux_sound_fade(t, -2, 1, 0.1);
    CHECK(strstr(aux_last_error(), "fade") != NULL, "a fade from -2 is refused");
    aux_sound_stop_with_fade(t, -1);
    CHECK(aux_sound_is_playing(t), "a negative fade length is refused");

    aux_engine_free(e);
}

static void test_groups_and_space(void)
{
    int e = aux_engine_create_offline(48000, 2);
    int other = aux_engine_create_offline(44100, 1);
    int t = aux_sound_tone(e, "sine", 440, 0.5);
    int g = aux_group_create(e);
    int og = aux_group_create(other);
    CHECK(g > 0 && og > 0 && aux_group_is_valid(g), "groups are made");
    CHECK(near(aux_group_volume(g), 1.0, 1e-6) && aux_group_pan(g) == 0.0 && near(aux_group_pitch(g), 1.0, 1e-6), "a group starts at volume 1, pan 0, pitch 1");
    aux_sound_start(t);
    aux_sound_set_group(t, og);
    CHECK(aux_sound_group(t) == 0 && strstr(aux_last_error(), "different engines") != NULL, "a group of another engine is refused");
    aux_sound_set_group(t, 12345);
    CHECK(aux_sound_group(t) == 0, "a group that does not exist is refused");
    aux_sound_set_group(t, g);
    CHECK(aux_sound_group(t) == g, "the sound joins the group");
    render_peak(e, 4800);
    CHECK(near(render_peak(e, 4800), 0.5, 0.02), "and is still heard");
    aux_group_set_volume(g, 0.5);
    CHECK(near(aux_group_volume(g), 0.5, 1e-6), "the group volume reads back");
    render_peak(e, 4800);
    CHECK(near(render_peak(e, 4800), 0.25, 0.02), "and halves its sounds");
    aux_group_set_volume(g, -1);
    CHECK(near(aux_group_volume(g), 0.5, 1e-6), "a negative group volume is refused");
    aux_group_set_volume(g, 1.0);
    aux_group_set_pan(g, -1.0);
    CHECK(near(aux_group_pan(g), -1.0, 1e-6), "the group pan reads back");
    {
        double l, r;
        int bytes = aux_engine_render(e, 4800, "f32");
        bytes = aux_engine_render(e, 4800, "f32");
        out_peaks(bytes, 2, &l, &r);
        CHECK(r < 0.01 && l > 0.3, "a group panned left silences the right");
    }
    aux_group_set_pan(g, 3);
    CHECK(near(aux_group_pan(g), -1.0, 1e-6), "a group pan of 3 is refused");
    aux_group_set_pan(g, 0.0);
    aux_group_set_pitch(g, 2.0);
    CHECK(near(aux_group_pitch(g), 2.0, 1e-6), "the group pitch reads back");
    aux_group_set_pitch(g, -1);
    CHECK(near(aux_group_pitch(g), 2.0, 1e-6), "a negative group pitch is refused");
    aux_group_set_pitch(g, 1.0);
    aux_group_stop(g);
    render_peak(e, 4800);
    CHECK(render_peak(e, 4800) == 0.0, "a stopped group is silent");
    CHECK(aux_sound_is_playing(t), "though its sound keeps its own state");
    aux_group_start(g);
    render_peak(e, 4800);
    CHECK(render_peak(e, 4800) > 0.3, "and started again it is heard");
    aux_group_set_volume(g, 0.0);
    aux_group_free(g);
    CHECK(!aux_group_is_valid(g) && aux_sound_group(t) == 0, "freeing the group returns its sound to the engine");
    render_peak(e, 4800);
    CHECK(near(render_peak(e, 4800), 0.5, 0.02), "where it is heard at full volume");
    g = aux_group_create(e);
    aux_sound_set_group(t, g);
    aux_sound_set_group(t, 0);
    CHECK(aux_sound_group(t) == 0, "group 0 is the engine itself");
    aux_engine_free(other);
    CHECK(!aux_group_is_valid(og), "freeing an engine frees its groups");

    /* 3D */
    CHECK(!aux_sound_is_spatial(t), "a sound starts without a place");
    aux_sound_set_position(t, 0, 0, -50);
    render_peak(e, 4800);
    CHECK(near(render_peak(e, 4800), 0.5, 0.02), "and its position changes nothing until it has one");
    aux_sound_set_spatial(t, 1);
    CHECK(aux_sound_is_spatial(t), "spatial reads back");
    aux_sound_set_position(t, 0, 0, -1);
    const char *pos = aux_sound_position_xyz(t);
    CHECK(items(pos) == 3 && item(pos, 1) == 0.0 && item(pos, 3) == -1.0, "the position reads back as x,y,z");
    render_peak(e, 9600);
    double nearPeak = render_peak(e, 4800);
    aux_sound_set_position(t, 0, 0, -50);
    render_peak(e, 9600);
    double farPeak = render_peak(e, 4800);
    /* straight ahead a placed sound is shared between the two sides: half each */
    CHECK(near(nearPeak, 0.25, 0.02) && farPeak < nearPeak * 0.05, "fifty metres away it is much quieter than at one");
    aux_sound_set_rolloff(t, 0.0);
    render_peak(e, 9600);
    CHECK(render_peak(e, 4800) > nearPeak * 0.8, "with no rolloff, distance does not matter");
    aux_sound_set_rolloff(t, 1.0);
    aux_sound_set_distance_range(t, 100, 1000);
    render_peak(e, 9600);
    CHECK(render_peak(e, 4800) > nearPeak * 0.8, "nor inside the nearest distance");
    aux_sound_set_distance_range(t, 10, 1);
    CHECK(strstr(aux_last_error(), "distance range") != NULL, "a farthest below the nearest is refused");
    aux_sound_set_rolloff(t, -1);
    aux_sound_set_doppler(t, -1);
    aux_sound_set_doppler(t, 1.0);
    aux_sound_set_velocity(t, 1, 0, 0);
    aux_sound_set_velocity(t, NAN, 0, 0);
    aux_sound_set_position(t, 1e9, 0, 0);
    CHECK(item(aux_sound_position_xyz(t), 3) == -50.0, "a position beyond a million is refused");

    aux_engine_set_listener_position(e, 1, 2, 3);
    const char *lp = aux_engine_listener_position(e);
    CHECK(items(lp) == 3 && item(lp, 1) == 1.0 && item(lp, 2) == 2.0 && item(lp, 3) == 3.0, "the listener position reads back");
    aux_engine_set_listener_position(e, NAN, 0, 0);
    CHECK(item(aux_engine_listener_position(e), 1) == 1.0, "a NaN listener position is refused");
    aux_engine_set_listener_direction(e, 1, 0, 0);
    CHECK(item(aux_engine_listener_direction(e), 1) == 1.0, "the listener direction reads back");
    aux_engine_set_listener_direction(e, 0, 0, 0);
    CHECK(item(aux_engine_listener_direction(e), 1) == 1.0, "a direction of all zeros is refused");
    aux_engine_set_listener_up(e, 0, 0, 1);
    aux_engine_set_listener_up(e, 0, 0, 0);
    aux_engine_set_listener_velocity(e, 0, 0, 1);
    aux_engine_set_listener_velocity(e, INFINITY, 0, 0);
    /* a sound to the listener's right is louder on the right */
    aux_engine_set_listener_position(e, 0, 0, 0);
    aux_engine_set_listener_direction(e, 0, 0, -1);
    aux_engine_set_listener_up(e, 0, 1, 0);
    aux_sound_set_distance_range(t, 1, 1000);
    aux_sound_set_position(t, 5, 0, 0);
    {
        double l, r;
        int bytes = aux_engine_render(e, 9600, "f32");
        bytes = aux_engine_render(e, 4800, "f32");
        out_peaks(bytes, 2, &l, &r);
        CHECK(r > l * 1.5 && r > 0.0, "a sound to the right is louder on the right");
    }
    aux_sound_set_spatial(t, 0);
    CHECK(!aux_sound_is_spatial(t), "spatial turns off");
    aux_engine_free(e);
}

/* Handles: a freed one stays dead through thousands of reuses of its slot. */
static void test_handles(void)
{
    int e = aux_engine_create_offline(22050, 1);
    short one[64];
    memset(one, 0, sizeof(one));
    int first = aux_sound_from_pcm(e, one, sizeof(one), "s16", 8000, 1);
    aux_sound_free(first);
    int alive = 0, repeats = 0;
    for (int i = 0; i < 6000; i++) {
        int h = aux_sound_from_pcm(e, one, sizeof(one), "s16", 8000, 1);
        if (h == first) repeats++;
        if (aux_sound_is_valid(first)) alive++;
        aux_sound_free(h);
    }
    CHECK(repeats == 0 && alive == 0, "6000 sounds later, the first handle was never reissued and never came alive");
    CHECK(aux_engine_sound_count(e) == 0, "and none are left");

    /* the engine limit is a refusal, and freeing makes room */
    int engines[40], made = 0;
    for (int i = 0; i < 40; i++) {
        int h = aux_engine_create_offline(8000, 1);
        if (h > 0) engines[made++] = h;
    }
    CHECK(made == 15, "sixteen engines at most (one was open already)");
    CHECK(strstr(aux_last_error(), "too many engines") != NULL, "and the refusal says so");
    for (int i = 0; i < made; i++) aux_engine_free(engines[i]);
    int again = aux_engine_create_offline(8000, 1);
    CHECK(again > 0, "freed, there is room again");
    aux_engine_free(again);
    aux_engine_free(e);
}

#if !defined(__EMSCRIPTEN__)
static void test_devices(void)
{
    int n = aux_device_scan();
    printf("INFO audio system: \"%s\"; %d device(s) found (%d playback, %d capture)\n",
           aux_backend_name(), n, aux_playback_device_count(), aux_capture_device_count());
    CHECK(n >= -1, "the scan answers");
    CHECK(n < 0 || n == aux_playback_device_count() + aux_capture_device_count(), "its total is the two lists");
    for (int i = 1; i <= aux_playback_device_count(); i++) {
        CHECK(aux_playback_device_name(i)[0] != 0, "a playback device has a name");
        CHECK(aux_playback_device_is_default(i) == 0 || aux_playback_device_is_default(i) == 1, "and is the default or is not");
    }
    for (int i = 1; i <= aux_capture_device_count(); i++) {
        CHECK(aux_capture_device_name(i)[0] != 0, "a capture device has a name");
        CHECK(aux_capture_device_is_default(i) == 0 || aux_capture_device_is_default(i) == 1, "and is the default or is not");
    }
    CHECK(aux_playback_device_name(0)[0] == 0 && aux_playback_device_name(9999)[0] == 0, "outside the list a playback device has no name");
    CHECK(aux_capture_device_name(0)[0] == 0 && aux_capture_device_name(9999)[0] == 0, "nor a capture device");
    CHECK(!aux_playback_device_is_default(0) && !aux_capture_device_is_default(9999), "and is not the default");
    CHECK(aux_engine_create(9999, 0, 0) == 0, "a playback device that is not in the list is refused");
    CHECK(aux_capture_open(9999, "s16", 16000, 1, 1.0) == 0, "and a capture device");
    CHECK(aux_engine_create(-1, 3, 2) == 0 && aux_engine_create(-1, 48000, 99) == 0, "a bad rate or channel count is refused");

    /* the machine's own default device: reported, never required */
    int real = aux_engine_create(0, 0, 0);
    if (real > 0) {
        printf("INFO default playback device opened: \"%s\", %d Hz, %d channel(s)\n",
               aux_engine_device_name(real), aux_engine_sample_rate(real), aux_engine_channels(real));
        aux_engine_free(real);
    } else {
        printf("INFO no default playback device here (%s)\n", aux_last_error());
    }

    /* the silent device: a real device thread, in real time */
    int e = aux_engine_create(-1, 48000, 2);
    CHECK(e > 0, "the silent device opens");
    if (e <= 0) return;
    CHECK(aux_engine_is_valid(e) && !aux_engine_is_offline(e), "it is a device engine");
    CHECK(aux_engine_sample_rate(e) == 48000 && aux_engine_channels(e) == 2, "with the format asked for");
    CHECK(aux_engine_render(e, 100, "f32") == 0 && strstr(aux_last_error(), "offline") != NULL, "a device engine cannot be rendered");
    int t = aux_sound_tone(e, "sine", 440, 0.5);
    aux_sound_start(t);
    sleep_ms(250);
    double clock = aux_engine_time(e);
    CHECK(clock > 0.05, "its clock runs by itself");
    const char *pk = aux_engine_peak(e);
    CHECK(near(item(pk, 1), 0.5, 0.02), "and its thread mixed the tone");
    CHECK(items(aux_engine_waveform(e, 32)) == 32, "the waveform is read while the device runs");
    aux_engine_stop(e);
    sleep_ms(60);
    double stopped = aux_engine_time(e);
    sleep_ms(120);
    CHECK(aux_engine_time(e) == stopped, "stopped, the clock stands still");
    aux_engine_start(e);
    sleep_ms(150);
    CHECK(aux_engine_time(e) > stopped, "started, it runs again");
    /* a sound ending on the device thread is seen by the poll */
    int s = aux_sound_load(e, k_wav_short, 0);
    aux_sound_set_auto_free(s, 1);
    aux_sound_start(s);
    int ended = 0;
    for (int i = 0; i < 100 && !ended; i++) { sleep_ms(20); ended = aux_poll_ended(); }
    CHECK(ended == 1 && aux_ended_sound(1) == s && !aux_sound_is_valid(s), "a sound that ended on the device thread is reported and freed");
    /* a stream on the device, freed while it plays */
    int st = aux_sound_load(e, k_wav_long, 1);
    aux_sound_start(st);
    sleep_ms(100);
    CHECK(aux_sound_position(st) > 0.0, "a stream plays on the device");
    aux_sound_free(st);
    aux_engine_free(e);
    CHECK(!aux_sound_is_valid(t), "freeing a running engine frees its playing sound");

    /* capture, on the silent device */
    CHECK(aux_capture_open(-1, "f64", 16000, 1, 1.0) == 0, "an unknown capture format is refused");
    CHECK(aux_capture_open(-1, NULL, 16000, 1, 1.0) == 0, "a missing capture format is refused");
    CHECK(aux_capture_open(-1, "s16", 100, 1, 1.0) == 0, "a capture rate of 100 is refused");
    CHECK(aux_capture_open(-1, "s16", 16000, 0, 1.0) == 0, "no channels are refused");
    CHECK(aux_capture_open(-1, "s16", 16000, 1, 0.0) == 0, "no buffer is refused");
    CHECK(aux_capture_open(-1, "s16", 16000, 1, NAN) == 0, "a NaN buffer is refused");
    CHECK(aux_capture_open(-1, "f32", 192000, 8, 600.0) == 0, "a buffer over 256 MB is refused");
    int c = aux_capture_open(-1, "s16", 16000, 1, 2.0);
    CHECK(c > 0, "the silent capture device opens");
    if (c <= 0) return;
    CHECK(aux_capture_is_valid(c) && !aux_capture_is_running(c), "open, not yet running");
    CHECK(strcmp(aux_capture_format(c), "s16") == 0 && aux_capture_sample_rate(c) == 16000 && aux_capture_channels(c) == 1,
          "it reports the format, rate and channels asked for");
    printf("INFO silent capture device label: \"%s\"\n", aux_capture_device_label(c));
    CHECK(aux_capture_available(c) == 0 && aux_capture_read(c) == 0, "nothing arrives before it starts");
    CHECK(aux_capture_start(c) == 1 && aux_capture_is_running(c), "it starts");
    CHECK(aux_capture_start(c) == 1, "starting twice is fine");
    CHECK(aux_capture_record_start(c, "") == 0, "recording to an empty path is refused");
    CHECK(aux_capture_record_start(c, "no-such-folder-audioxt/x.wav") == 0 && !aux_capture_is_recording(c), "and to a folder that does not exist");
    CHECK(aux_capture_record_start(c, k_wav_rec) == 1 && aux_capture_is_recording(c), "recording to a file begins");
    CHECK(aux_capture_record_start(c, k_wav_rec) == 0, "a second recording on the same capture is refused");
    sleep_ms(300);
    int avail = aux_capture_available(c);
    CHECK(avail > 0 && avail % 2 == 0, "frames arrive, in whole frames");
    int got = aux_capture_read(c);
    CHECK(got >= avail && got % 2 == 0, "read returns at least what was waiting");
    CHECK(aux_out_sample_rate() == 16000 && aux_out_channels() == 1, "the out buffer says what was read");
    {
        const unsigned char *b = (const unsigned char *)aux_out_pointer();
        int nonzero = 0;
        for (int i = 0; i < got; i++) if (b[i]) nonzero++;
        CHECK(nonzero == 0, "the silent device records silence");
    }
    CHECK(aux_capture_peak(c) == 0.0, "and its peak is 0");
    CHECK(aux_capture_dropped(c) == 0, "nothing was dropped");
    double secs = aux_capture_record_stop(c);
    CHECK(secs > 0.1 && !aux_capture_is_recording(c), "the recording stops, with its length");
    CHECK(aux_capture_record_stop(c) == 0.0, "stopping twice is fine");
    int dn = aux_decode_file(k_wav_rec, "s16", 0, 0);
    CHECK(near(dn, secs * 16000 * 2, 4) && aux_out_sample_rate() == 16000 && aux_out_channels() == 1,
          "the recorded file is a WAV of that length, in the capture's format");
    aux_capture_stop(c);
    CHECK(!aux_capture_is_running(c), "it stops");
    aux_capture_read(c);
    sleep_ms(80);
    CHECK(aux_capture_read(c) == 0, "stopped, nothing more arrives");
    aux_capture_close(c);
    CHECK(!aux_capture_is_valid(c), "closed, it is not valid");

    /* a script that does not read: the newest sound is dropped and counted */
    c = aux_capture_open(-1, "f32", 48000, 2, 0.1);
    CHECK(c > 0 && aux_capture_start(c) == 1, "a capture with a tenth of a second of buffer");
    sleep_ms(450);
    CHECK(aux_capture_dropped(c) > 0, "unread for longer than its buffer, it drops and counts");
    CHECK(aux_capture_available(c) <= (int)(0.1 * 48000) * 8, "and never holds more than its buffer");
    CHECK(aux_capture_record_start(c, k_wav_rec) == 1, "a recording left open");
    sleep_ms(60);
    aux_capture_close(c);
    CHECK(aux_decode_file(k_wav_rec, "f32", 0, 0) > 0 && aux_out_channels() == 2, "is finished by the close: the file is whole");

    /* the capture limit */
    int caps[20], made = 0;
    for (int i = 0; i < 20; i++) {
        int h = aux_capture_open(-1, "u8", 8000, 1, 0.1);
        if (h > 0) caps[made++] = h;
    }
    CHECK(made == 16 && strstr(aux_last_error(), "too many captures") != NULL, "sixteen captures at most");
    for (int i = 0; i < made; i++) aux_capture_close(caps[i]);
}
#endif

static void test_shutdown(void)
{
    int e = aux_engine_create_offline(48000, 2);
    int t = aux_sound_tone(e, "sine", 440, 0.5);
    int g = aux_group_create(e);
    aux_sound_start(t);
    render_peak(e, 480);
#if !defined(__EMSCRIPTEN__)
    int d = aux_engine_create(-1, 0, 0);
    int c = aux_capture_open(-1, "s16", 16000, 1, 0.5);
    aux_capture_start(c);
    aux_capture_record_start(c, k_wav_rec);
    int dt = aux_sound_tone(d, "square", 110, 0.1);
    aux_sound_start(dt);
    sleep_ms(50);
#endif
    aux_shut_down();
    CHECK(!aux_engine_is_valid(e) && !aux_sound_is_valid(t) && !aux_group_is_valid(g), "shutdown frees every engine, sound and group");
#if !defined(__EMSCRIPTEN__)
    CHECK(!aux_engine_is_valid(d) && !aux_capture_is_valid(c) && !aux_sound_is_valid(dt), "and every device");
    CHECK(aux_playback_device_count() == 0 && aux_capture_device_count() == 0, "and forgets the device lists");
#endif
    CHECK(aux_out_sample_rate() == 0 && aux_last_error()[0] == 0, "and the out buffer and the last error");
    aux_shut_down();
    CHECK(1, "a second shutdown is harmless");
    e = aux_engine_create_offline(48000, 2);
    CHECK(e > 0 && e != 0, "the library works again after a shutdown");
    t = aux_sound_tone(e, "sine", 440, 0.5);
    aux_sound_start(t);
    CHECK(near(render_peak(e, 4800), 0.5, 0.01), "and sounds as before");
    aux_shut_down();
}

int main(void)
{
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("%s\n", aux_library_version());
    test_library();
    test_codecs();
    test_stale(0);
    test_stale(-7);
    test_stale(12345678);
    test_engine_and_tone();
    test_sounds();
    test_schedule_and_fades();
    test_groups_and_space();
    test_handles();
#if !defined(__EMSCRIPTEN__)
    test_devices();
#else
    printf("INFO web build under node: no audio system and no thread, so the device and capture tests are not run here\n");
    /* Named so that every export is at least entered on this build too:
     * each must answer, and refuse, without an audio system behind it. */
    CHECK(aux_device_scan() >= -1, "the scan answers");
    aux_backend_name();
    CHECK(aux_playback_device_count() >= 0 && aux_capture_device_count() >= 0, "the device lists answer");
    aux_playback_device_name(1);
    aux_playback_device_is_default(1);
    aux_capture_device_name(1);
    aux_capture_device_is_default(1);
    {
        int e = aux_engine_create(-1, 48000, 2);
        if (e > 0) aux_engine_free(e);
        int c = aux_capture_open(-1, "s16", 16000, 1, 1.0);
        if (c > 0) aux_capture_close(c);
        CHECK(1, "asking for a device where there is none does not crash");
    }
#endif
    test_shutdown();
    remove(k_wav_short);
    remove(k_wav_long);
    remove(k_wav_rec);
    printf("audioxt smoke: %d checks, %d failed\n", s_checks, s_failed);
    return s_failed == 0 ? 0 : 1;
}
