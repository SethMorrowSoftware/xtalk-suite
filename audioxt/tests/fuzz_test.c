/*
 * fuzz_test.c - the random-call test of audioxt's C shim (src/audio_shim.c).
 *
 * The smoke test calls every export the way a careful script would. This
 * one calls them the way a broken script, a typo or a half-finished stack
 * does: any export, in any order, with handles that are live, freed, of
 * the wrong kind or never issued, numbers that are zero, negative, huge,
 * infinite or not numbers at all, texts that are missing or misspelt, and
 * sound data that is whole, truncated, empty or not sound. The claim it
 * holds is the shim's first one: NOTHING a script passes can crash the
 * host. Under ASan/UBSan (the sanitize lane) a wild read, a use after
 * free, a leak or an overflow is a failed run, not a lucky one.
 *
 * It is deterministic: the same seed makes the same calls with the same
 * arguments on every platform (its own generator, never rand()), so a seed
 * that fails is a seed to run again under a debugger. Set AUDIOXT_FUZZ_TRACE
 * to print each call before it is made; the last line printed is the call
 * that died.
 *
 *     fuzz_test                 seeds 1 to 3, 20000 calls each
 *     fuzz_test SEED [CALLS]    one seed
 *
 * Devices: only the silent test device (-1) and indices that do not exist
 * are ever asked for, so a run opens no real sound card and no microphone.
 * The call table is GENERATED from the shim's exports
 * (tools/check-smoke-coverage.py --write), so a new export is fuzzed the
 * day it is written.
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fixtures.h"

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

/* ---- the generator: xorshift64*, the same numbers everywhere ---- */
static unsigned long long s_state = 1;
static unsigned long long next_u64(void)
{
    s_state ^= s_state >> 12;
    s_state ^= s_state << 25;
    s_state ^= s_state >> 27;
    return s_state * 2685821657736338717ULL;
}
static int below(int n) { return n <= 0 ? 0 : (int)((next_u64() >> 16) % (unsigned long long)n); }
static int small(int lo, int hi) { return lo + below(hi - lo + 1); }
static int flag(void) { return below(2); }
static double unit(void) { return (double)(next_u64() >> 11) / 9007199254740992.0; }

/* ---- handle pools: what creators returned, live or long dead ---- */
typedef struct { int h[64]; int n; } Pool;
static Pool s_engines, s_sounds, s_groups, s_captures;
static int s_lastInt = 0;

static void keep(Pool *p, int h)
{
    if (h <= 0) return;
    if (p->n < 64) p->h[p->n++] = h;
    else p->h[below(64)] = h;
}

/* Mostly a handle this pool was given (it may be stale by now, which is
 * the point); sometimes one of another kind, sometimes garbage. */
static int draw(Pool *own)
{
    int r = below(20);
    if (r < 15 && own->n > 0) return own->h[below(own->n)];
    if (r == 15) return 0;
    if (r == 16) return -small(1, 100000);
    if (r == 17) return (int)(next_u64() & 0x7FFFFFFF);
    Pool *other = r == 18 ? &s_sounds : &s_engines;
    return other->n > 0 ? other->h[below(other->n)] : small(1, 70);
}
static int HE(void) { return draw(&s_engines); }
static int HS(void) { return draw(&s_sounds); }
static int HG(void) { return draw(&s_groups); }
static int HC(void) { return draw(&s_captures); }

/* Never 0 (the machine's default device) and never 1..n of a scan: a fuzz
 * run must not open somebody's sound card or microphone. */
static int DEV(void)
{
    static const int k[] = { -1, -1, -1, -1, 9999, -2, 100000 };
    return k[below(7)];
}
static int RATE(void)
{
    static const int k[] = { 0, 8000, 16000, 22050, 44100, 48000, 48000, 96000, 7, -1, 999999 };
    return k[below(11)];
}
static int CH(void)
{
    static const int k[] = { 1, 2, 1, 2, 2, 0, 6, 8, 9, -1 };
    return k[below(10)];
}

/* A number: usually sane, sometimes at an edge, sometimes not a number. */
static double D(void)
{
    switch (below(14)) {
        case 0: return 0.0;
        case 1: return 1.0;
        case 2: return -1.0;
        case 3: return NAN;
        case 4: return INFINITY;
        case 5: return -INFINITY;
        case 6: return 1e300;
        case 7: return -1e300;
        case 8: return 1e-300;
        case 9: return unit() * 2000000.0 - 1000000.0;
        default: return unit() * 20.0 - 10.0;
    }
}
static double T(void)
{
    switch (below(10)) {
        case 0: return NAN;
        case 1: return -1.0;
        case 2: return 1e12;
        case 3: return 0.0;
        default: return unit() * 2.0;
    }
}
static double V(void)
{
    switch (below(10)) {
        case 0: return NAN;
        case 1: return -1.0;
        case 2: return 1000.0;
        case 3: return 0.0;
        default: return unit();
    }
}
static double HZ(void)
{
    switch (below(8)) {
        case 0: return NAN;
        case 1: return 0.0;
        case 2: return 1e9;
        default: return 20.0 + unit() * 4000.0;
    }
}
static double BUF(void)
{
    static const double k[] = { 0.1, 0.1, 0.25, 0.5, 0.0, -1.0, 700.0 };
    int i = below(8);
    return i == 7 ? NAN : k[i];
}

static const char *k_fuzz_wav = "audioxt-fuzz-tone.wav";
static const char *k_fuzz_out = "audioxt-fuzz-recorded.wav";

static const char *FMT(void)
{
    static const char *k[] = { "u8", "s16", "s24", "s32", "f32", "s16", "f32", "", "S16", "f64", "s16 ", NULL };
    return k[below(12)];
}
static const char *PATH(void)
{
    static const char *k[] = { NULL, "", "no-such-file.wav", ".", "/", "audioxt-fuzz-tone.wav", "audioxt-fuzz-tone.wav",
                               "audioxt-fuzz-tone.wav", "audioxt:mem:1", "audioxt:mem:2", "\xff\xfe\xfd" };
    return k[below(11)];
}
static const char *SAVE(void)
{
    static const char *k[] = { NULL, "", "audioxt-fuzz-recorded.wav", "audioxt-fuzz-recorded.wav",
                               "no-such-folder-audioxt/x.wav", "." };
    return k[below(6)];
}
static const char *SHAPE(void)
{
    static const char *k[] = { "sine", "square", "triangle", "sawtooth", "sine", "", "Sine", NULL };
    return k[below(8)];
}
static const char *COLOR(void)
{
    static const char *k[] = { "white", "pink", "white", "brown", "", NULL };
    return k[below(6)];
}

/* ---- the byte buffers a call may be handed ---- */
static unsigned char s_wav[44 + 8000];      /* a whole WAV file, made in main */
static int           s_wavSize = 0;
static unsigned char s_pcm[4096];           /* raw samples                    */
static unsigned char s_junk[512];           /* not sound                      */
static unsigned char s_cut[1024];           /* a file cut short, per draw     */
static int           s_cutSize = 0;

enum { BLOB_WAV, BLOB_FLAC, BLOB_MP3, BLOB_PCM, BLOB_JUNK, BLOB_CUT, BLOB_NULL, BLOB_OUT, BLOB_KINDS };
static int s_blobLength = 0;
/* How many bytes the out buffer holds now: set by bytes_out, and 0 again
 * after a shutdown, which frees the buffer. */
static int s_outBytes = 0;

static int blob_pick(void)
{
    int k = below(BLOB_KINDS + 3);
    if (k >= BLOB_KINDS) k = BLOB_WAV;
    switch (k) {
        case BLOB_WAV:  s_blobLength = s_wavSize; break;
        case BLOB_FLAC: s_blobLength = (int)sizeof(k_flac); break;
        case BLOB_MP3:  s_blobLength = (int)sizeof(k_mp3); break;
        case BLOB_PCM:  s_blobLength = small(1, (int)sizeof(s_pcm)); break;
        case BLOB_JUNK: s_blobLength = small(1, (int)sizeof(s_junk)); break;
        case BLOB_CUT: {
            const unsigned char *src = flag() ? k_flac : k_mp3;
            int whole = src == k_flac ? (int)sizeof(k_flac) : (int)sizeof(k_mp3);
            s_cutSize = small(1, whole < (int)sizeof(s_cut) ? whole : (int)sizeof(s_cut));
            memcpy(s_cut, src, (size_t)s_cutSize);
            /* and sometimes a flipped byte: a damaged file, not only a short one */
            if (flag()) s_cut[below(s_cutSize)] ^= (unsigned char)(1 << below(8));
            s_blobLength = s_cutSize;
            break;
        }
        case BLOB_NULL: s_blobLength = small(0, 100); break;
        case BLOB_OUT:  s_blobLength = s_outBytes < 4096 ? s_outBytes : 4096; break;
    }
    /* now and then a length that is wrong on purpose: 0 or negative (never
     * longer than the buffer: that would be the TEST reading out of bounds) */
    if (below(12) == 0) s_blobLength = flag() ? 0 : -small(1, 1000);
    return k;
}
static const void *blob_bytes(int k)
{
    switch (k) {
        case BLOB_WAV:  return s_wav;
        case BLOB_FLAC: return k_flac;
        case BLOB_MP3:  return k_mp3;
        case BLOB_PCM:  return s_pcm;
        case BLOB_JUNK: return s_junk;
        case BLOB_CUT:  return s_cut;
        case BLOB_OUT:  return s_blobLength > 0 ? aux_out_pointer() : NULL;
        default:        return NULL;
    }
}
static int blob_length(int k) { (void)k; return s_blobLength; }

/* ---- what is done with a result ---- */
static int s_trace = 0;
static unsigned long long s_calls = 0, s_texts = 0, s_bytes = 0;
static double s_sink = 0.0;
static int s_bad = 0;

static void trace(const char *name)
{
    s_calls++;
    if (s_trace) { printf("%s\n", name); fflush(stdout); }
}

/* Every text result is measured and read to its end: a pointer to nowhere
 * is a crash here, where it can be seen. */
static void text(const char *t)
{
    if (t == NULL) { printf("FAIL a text result was NULL\n"); s_bad++; return; }
    int n = aux_text_length(t);
    for (int i = 0; i < n; i++) s_sink += (double)t[i];
    s_texts++;
}

/* A number that came back must be a number. */
static void number(double v)
{
    if (!isfinite(v)) { printf("FAIL a number result was not finite\n"); s_bad++; }
    s_sink += v;
}

/* A byte count that came back is read back, every byte of it. */
static void bytes_out(int n)
{
    s_lastInt = n;
    s_outBytes = n > 0 ? n : s_outBytes;
    if (n < 0) { printf("FAIL a byte count was negative\n"); s_bad++; return; }
    const unsigned char *p = (const unsigned char *)aux_out_pointer();
    unsigned sum = 0;
    for (int i = 0; i < n; i++) sum += p[i];
    s_sink += (double)sum;
    s_bytes += (unsigned long long)n;
}

/* >>> BEGIN FUZZ CALLS (generated: tools/check-smoke-coverage.py --write) >>> */
/* One thunk per export: it draws the arguments, in order (C leaves the
 * order of argument evaluation open, and a run must be the same
 * everywhere), names itself for the trace and makes the call. */
static void fz_0(void) { trace("aux_abi_version"); s_lastInt = aux_abi_version(); }
static void fz_1(void) { trace("aux_library_version"); text(aux_library_version()); }
static void fz_2(void) { trace("aux_last_error"); text(aux_last_error()); }
static void fz_5(void) { trace("aux_out_sample_rate"); s_lastInt = aux_out_sample_rate(); }
static void fz_6(void) { trace("aux_out_channels"); s_lastInt = aux_out_channels(); }
static void fz_7(void) { trace("aux_backend_name"); text(aux_backend_name()); }
static void fz_8(void) { trace("aux_device_scan"); s_lastInt = aux_device_scan(); }
static void fz_9(void) { trace("aux_playback_device_count"); s_lastInt = aux_playback_device_count(); }
static void fz_10(void) { int a0 = small(-1, 6); trace("aux_playback_device_name"); text(aux_playback_device_name(a0)); }
static void fz_11(void) { int a0 = small(-1, 6); trace("aux_playback_device_is_default"); s_lastInt = aux_playback_device_is_default(a0); }
static void fz_12(void) { trace("aux_capture_device_count"); s_lastInt = aux_capture_device_count(); }
static void fz_13(void) { int a0 = small(-1, 6); trace("aux_capture_device_name"); text(aux_capture_device_name(a0)); }
static void fz_14(void) { int a0 = small(-1, 6); trace("aux_capture_device_is_default"); s_lastInt = aux_capture_device_is_default(a0); }
static void fz_15(void) { int a0 = DEV(); int a1 = RATE(); int a2 = CH(); trace("aux_engine_create"); s_lastInt = aux_engine_create(a0, a1, a2); keep(&s_engines, s_lastInt); }
static void fz_16(void) { int a0 = RATE(); int a1 = CH(); trace("aux_engine_create_offline"); s_lastInt = aux_engine_create_offline(a0, a1); keep(&s_engines, s_lastInt); }
static void fz_17(void) { int a0 = HE(); trace("aux_engine_free"); aux_engine_free(a0); }
static void fz_18(void) { int a0 = HE(); trace("aux_engine_is_valid"); s_lastInt = aux_engine_is_valid(a0); }
static void fz_19(void) { int a0 = HE(); trace("aux_engine_is_offline"); s_lastInt = aux_engine_is_offline(a0); }
static void fz_20(void) { int a0 = HE(); trace("aux_engine_start"); aux_engine_start(a0); }
static void fz_21(void) { int a0 = HE(); trace("aux_engine_stop"); aux_engine_stop(a0); }
static void fz_22(void) { int a0 = HE(); double a1 = V(); trace("aux_engine_set_volume"); aux_engine_set_volume(a0, a1); }
static void fz_23(void) { int a0 = HE(); trace("aux_engine_volume"); number(aux_engine_volume(a0)); }
static void fz_24(void) { int a0 = HE(); trace("aux_engine_sample_rate"); s_lastInt = aux_engine_sample_rate(a0); }
static void fz_25(void) { int a0 = HE(); trace("aux_engine_channels"); s_lastInt = aux_engine_channels(a0); }
static void fz_26(void) { int a0 = HE(); trace("aux_engine_time"); number(aux_engine_time(a0)); }
static void fz_27(void) { int a0 = HE(); trace("aux_engine_sound_count"); s_lastInt = aux_engine_sound_count(a0); }
static void fz_28(void) { int a0 = HE(); trace("aux_engine_device_name"); text(aux_engine_device_name(a0)); }
static void fz_29(void) { int a0 = HE(); trace("aux_engine_stop_all"); aux_engine_stop_all(a0); }
static void fz_30(void) { int a0 = HE(); trace("aux_engine_peak"); text(aux_engine_peak(a0)); }
static void fz_31(void) { int a0 = HE(); int a1 = small(-2, 2100); trace("aux_engine_waveform"); text(aux_engine_waveform(a0, a1)); }
static void fz_32(void) { int a0 = HE(); int a1 = small(-5, 3000); const char *a2 = FMT(); trace("aux_engine_render"); bytes_out(aux_engine_render(a0, a1, a2)); }
static void fz_33(void) { int a0 = HE(); double a1 = D(); double a2 = D(); double a3 = D(); trace("aux_engine_set_listener_position"); aux_engine_set_listener_position(a0, a1, a2, a3); }
static void fz_34(void) { int a0 = HE(); trace("aux_engine_listener_position"); text(aux_engine_listener_position(a0)); }
static void fz_35(void) { int a0 = HE(); double a1 = D(); double a2 = D(); double a3 = D(); trace("aux_engine_set_listener_direction"); aux_engine_set_listener_direction(a0, a1, a2, a3); }
static void fz_36(void) { int a0 = HE(); trace("aux_engine_listener_direction"); text(aux_engine_listener_direction(a0)); }
static void fz_37(void) { int a0 = HE(); double a1 = D(); double a2 = D(); double a3 = D(); trace("aux_engine_set_listener_up"); aux_engine_set_listener_up(a0, a1, a2, a3); }
static void fz_38(void) { int a0 = HE(); double a1 = D(); double a2 = D(); double a3 = D(); trace("aux_engine_set_listener_velocity"); aux_engine_set_listener_velocity(a0, a1, a2, a3); }
static void fz_39(void) { int a0 = HE(); const char *a1 = PATH(); int a2 = flag(); trace("aux_sound_load"); s_lastInt = aux_sound_load(a0, a1, a2); keep(&s_sounds, s_lastInt); }
static void fz_40(void) { int a0 = HE(); int k = blob_pick(); const void *a1 = blob_bytes(k); int a2 = blob_length(k); int a3 = flag(); trace("aux_sound_load_data"); s_lastInt = aux_sound_load_data(a0, a1, a2, a3); keep(&s_sounds, s_lastInt); }
static void fz_41(void) { int a0 = HE(); int k = blob_pick(); const void *a1 = blob_bytes(k); int a2 = blob_length(k); const char *a3 = FMT(); int a4 = RATE(); int a5 = CH(); trace("aux_sound_from_pcm"); s_lastInt = aux_sound_from_pcm(a0, a1, a2, a3, a4, a5); keep(&s_sounds, s_lastInt); }
static void fz_42(void) { int a0 = HE(); const char *a1 = SHAPE(); double a2 = HZ(); double a3 = V(); trace("aux_sound_tone"); s_lastInt = aux_sound_tone(a0, a1, a2, a3); keep(&s_sounds, s_lastInt); }
static void fz_43(void) { int a0 = HE(); const char *a1 = COLOR(); double a2 = V(); trace("aux_sound_noise"); s_lastInt = aux_sound_noise(a0, a1, a2); keep(&s_sounds, s_lastInt); }
static void fz_44(void) { int a0 = HS(); trace("aux_sound_clone"); s_lastInt = aux_sound_clone(a0); keep(&s_sounds, s_lastInt); }
static void fz_45(void) { int a0 = HS(); trace("aux_sound_free"); aux_sound_free(a0); }
static void fz_46(void) { int a0 = HS(); trace("aux_sound_is_valid"); s_lastInt = aux_sound_is_valid(a0); }
static void fz_47(void) { int a0 = HS(); trace("aux_sound_engine"); s_lastInt = aux_sound_engine(a0); }
static void fz_48(void) { int a0 = HS(); trace("aux_sound_start"); aux_sound_start(a0); }
static void fz_49(void) { int a0 = HS(); double a1 = T(); trace("aux_sound_start_at"); aux_sound_start_at(a0, a1); }
static void fz_50(void) { int a0 = HS(); trace("aux_sound_stop"); aux_sound_stop(a0); }
static void fz_51(void) { int a0 = HS(); double a1 = T(); trace("aux_sound_stop_at"); aux_sound_stop_at(a0, a1); }
static void fz_52(void) { int a0 = HS(); double a1 = T(); trace("aux_sound_stop_with_fade"); aux_sound_stop_with_fade(a0, a1); }
static void fz_53(void) { int a0 = HS(); double a1 = V(); double a2 = V(); double a3 = T(); trace("aux_sound_fade"); aux_sound_fade(a0, a1, a2, a3); }
static void fz_54(void) { int a0 = HS(); trace("aux_sound_is_playing"); s_lastInt = aux_sound_is_playing(a0); }
static void fz_55(void) { int a0 = HS(); trace("aux_sound_at_end"); s_lastInt = aux_sound_at_end(a0); }
static void fz_56(void) { int a0 = HS(); double a1 = T(); trace("aux_sound_seek"); aux_sound_seek(a0, a1); }
static void fz_57(void) { int a0 = HS(); trace("aux_sound_position"); number(aux_sound_position(a0)); }
static void fz_58(void) { int a0 = HS(); trace("aux_sound_length"); number(aux_sound_length(a0)); }
static void fz_59(void) { int a0 = HS(); double a1 = V(); trace("aux_sound_set_volume"); aux_sound_set_volume(a0, a1); }
static void fz_60(void) { int a0 = HS(); trace("aux_sound_volume"); number(aux_sound_volume(a0)); }
static void fz_61(void) { int a0 = HS(); double a1 = V(); trace("aux_sound_set_pan"); aux_sound_set_pan(a0, a1); }
static void fz_62(void) { int a0 = HS(); trace("aux_sound_pan"); number(aux_sound_pan(a0)); }
static void fz_63(void) { int a0 = HS(); double a1 = D(); trace("aux_sound_set_pitch"); aux_sound_set_pitch(a0, a1); }
static void fz_64(void) { int a0 = HS(); trace("aux_sound_pitch"); number(aux_sound_pitch(a0)); }
static void fz_65(void) { int a0 = HS(); int a1 = flag(); trace("aux_sound_set_looping"); aux_sound_set_looping(a0, a1); }
static void fz_66(void) { int a0 = HS(); trace("aux_sound_is_looping"); s_lastInt = aux_sound_is_looping(a0); }
static void fz_67(void) { int a0 = HS(); double a1 = T(); double a2 = T(); trace("aux_sound_set_loop_range"); aux_sound_set_loop_range(a0, a1, a2); }
static void fz_68(void) { int a0 = HS(); double a1 = HZ(); trace("aux_sound_set_frequency"); aux_sound_set_frequency(a0, a1); }
static void fz_69(void) { int a0 = HS(); int a1 = flag(); trace("aux_sound_set_auto_free"); aux_sound_set_auto_free(a0, a1); }
static void fz_70(void) { int a0 = HS(); int a1 = HG(); trace("aux_sound_set_group"); aux_sound_set_group(a0, a1); }
static void fz_71(void) { int a0 = HS(); trace("aux_sound_group"); s_lastInt = aux_sound_group(a0); }
static void fz_72(void) { int a0 = HS(); int a1 = flag(); trace("aux_sound_set_spatial"); aux_sound_set_spatial(a0, a1); }
static void fz_73(void) { int a0 = HS(); trace("aux_sound_is_spatial"); s_lastInt = aux_sound_is_spatial(a0); }
static void fz_74(void) { int a0 = HS(); double a1 = D(); double a2 = D(); double a3 = D(); trace("aux_sound_set_position"); aux_sound_set_position(a0, a1, a2, a3); }
static void fz_75(void) { int a0 = HS(); trace("aux_sound_position_xyz"); text(aux_sound_position_xyz(a0)); }
static void fz_76(void) { int a0 = HS(); double a1 = D(); double a2 = D(); double a3 = D(); trace("aux_sound_set_velocity"); aux_sound_set_velocity(a0, a1, a2, a3); }
static void fz_77(void) { int a0 = HS(); double a1 = D(); double a2 = D(); trace("aux_sound_set_distance_range"); aux_sound_set_distance_range(a0, a1, a2); }
static void fz_78(void) { int a0 = HS(); double a1 = D(); trace("aux_sound_set_rolloff"); aux_sound_set_rolloff(a0, a1); }
static void fz_79(void) { int a0 = HS(); double a1 = D(); trace("aux_sound_set_doppler"); aux_sound_set_doppler(a0, a1); }
static void fz_80(void) { int a0 = HE(); trace("aux_group_create"); s_lastInt = aux_group_create(a0); keep(&s_groups, s_lastInt); }
static void fz_81(void) { int a0 = HG(); trace("aux_group_free"); aux_group_free(a0); }
static void fz_82(void) { int a0 = HG(); trace("aux_group_is_valid"); s_lastInt = aux_group_is_valid(a0); }
static void fz_83(void) { int a0 = HG(); double a1 = V(); trace("aux_group_set_volume"); aux_group_set_volume(a0, a1); }
static void fz_84(void) { int a0 = HG(); trace("aux_group_volume"); number(aux_group_volume(a0)); }
static void fz_85(void) { int a0 = HG(); double a1 = V(); trace("aux_group_set_pan"); aux_group_set_pan(a0, a1); }
static void fz_86(void) { int a0 = HG(); trace("aux_group_pan"); number(aux_group_pan(a0)); }
static void fz_87(void) { int a0 = HG(); double a1 = D(); trace("aux_group_set_pitch"); aux_group_set_pitch(a0, a1); }
static void fz_88(void) { int a0 = HG(); trace("aux_group_pitch"); number(aux_group_pitch(a0)); }
static void fz_89(void) { int a0 = HG(); trace("aux_group_start"); aux_group_start(a0); }
static void fz_90(void) { int a0 = HG(); trace("aux_group_stop"); aux_group_stop(a0); }
static void fz_91(void) { trace("aux_poll_ended"); s_lastInt = aux_poll_ended(); }
static void fz_92(void) { int a0 = small(-1, 6); trace("aux_ended_sound"); s_lastInt = aux_ended_sound(a0); }
static void fz_93(void) { int a0 = DEV(); const char *a1 = FMT(); int a2 = RATE(); int a3 = CH(); double a4 = BUF(); trace("aux_capture_open"); s_lastInt = aux_capture_open(a0, a1, a2, a3, a4); keep(&s_captures, s_lastInt); }
static void fz_94(void) { int a0 = HC(); trace("aux_capture_close"); aux_capture_close(a0); }
static void fz_95(void) { int a0 = HC(); trace("aux_capture_is_valid"); s_lastInt = aux_capture_is_valid(a0); }
static void fz_96(void) { int a0 = HC(); trace("aux_capture_start"); s_lastInt = aux_capture_start(a0); }
static void fz_97(void) { int a0 = HC(); trace("aux_capture_stop"); aux_capture_stop(a0); }
static void fz_98(void) { int a0 = HC(); trace("aux_capture_is_running"); s_lastInt = aux_capture_is_running(a0); }
static void fz_99(void) { int a0 = HC(); trace("aux_capture_available"); s_lastInt = aux_capture_available(a0); }
static void fz_100(void) { int a0 = HC(); trace("aux_capture_read"); bytes_out(aux_capture_read(a0)); }
static void fz_101(void) { int a0 = HC(); trace("aux_capture_format"); text(aux_capture_format(a0)); }
static void fz_102(void) { int a0 = HC(); trace("aux_capture_sample_rate"); s_lastInt = aux_capture_sample_rate(a0); }
static void fz_103(void) { int a0 = HC(); trace("aux_capture_channels"); s_lastInt = aux_capture_channels(a0); }
static void fz_104(void) { int a0 = HC(); trace("aux_capture_device_label"); text(aux_capture_device_label(a0)); }
static void fz_105(void) { int a0 = HC(); trace("aux_capture_dropped"); s_lastInt = aux_capture_dropped(a0); }
static void fz_106(void) { int a0 = HC(); trace("aux_capture_peak"); number(aux_capture_peak(a0)); }
static void fz_107(void) { int a0 = HC(); const char *a1 = SAVE(); trace("aux_capture_record_start"); s_lastInt = aux_capture_record_start(a0, a1); }
static void fz_108(void) { int a0 = HC(); trace("aux_capture_record_stop"); number(aux_capture_record_stop(a0)); }
static void fz_109(void) { int a0 = HC(); trace("aux_capture_is_recording"); s_lastInt = aux_capture_is_recording(a0); }
static void fz_110(void) { const char *a0 = PATH(); const char *a1 = FMT(); int a2 = RATE(); int a3 = CH(); trace("aux_decode_file"); bytes_out(aux_decode_file(a0, a1, a2, a3)); }
static void fz_111(void) { int k = blob_pick(); const void *a0 = blob_bytes(k); int a1 = blob_length(k); const char *a2 = FMT(); int a3 = RATE(); int a4 = CH(); trace("aux_decode_data"); bytes_out(aux_decode_data(a0, a1, a2, a3, a4)); }
static void fz_112(void) { int k = blob_pick(); const void *a0 = blob_bytes(k); int a1 = blob_length(k); const char *a2 = FMT(); int a3 = RATE(); int a4 = CH(); trace("aux_wav_encode"); bytes_out(aux_wav_encode(a0, a1, a2, a3, a4)); }
static void fz_113(void) { trace("aux_shut_down"); aux_shut_down(); }
typedef struct { const char *name; void (*call)(void); } FuzzCall;
static const FuzzCall k_fuzz[] = {
    { "aux_abi_version", fz_0 },
    { "aux_library_version", fz_1 },
    { "aux_last_error", fz_2 },
    { "aux_out_sample_rate", fz_5 },
    { "aux_out_channels", fz_6 },
    { "aux_backend_name", fz_7 },
    { "aux_device_scan", fz_8 },
    { "aux_playback_device_count", fz_9 },
    { "aux_playback_device_name", fz_10 },
    { "aux_playback_device_is_default", fz_11 },
    { "aux_capture_device_count", fz_12 },
    { "aux_capture_device_name", fz_13 },
    { "aux_capture_device_is_default", fz_14 },
    { "aux_engine_create", fz_15 },
    { "aux_engine_create_offline", fz_16 },
    { "aux_engine_free", fz_17 },
    { "aux_engine_is_valid", fz_18 },
    { "aux_engine_is_offline", fz_19 },
    { "aux_engine_start", fz_20 },
    { "aux_engine_stop", fz_21 },
    { "aux_engine_set_volume", fz_22 },
    { "aux_engine_volume", fz_23 },
    { "aux_engine_sample_rate", fz_24 },
    { "aux_engine_channels", fz_25 },
    { "aux_engine_time", fz_26 },
    { "aux_engine_sound_count", fz_27 },
    { "aux_engine_device_name", fz_28 },
    { "aux_engine_stop_all", fz_29 },
    { "aux_engine_peak", fz_30 },
    { "aux_engine_waveform", fz_31 },
    { "aux_engine_render", fz_32 },
    { "aux_engine_set_listener_position", fz_33 },
    { "aux_engine_listener_position", fz_34 },
    { "aux_engine_set_listener_direction", fz_35 },
    { "aux_engine_listener_direction", fz_36 },
    { "aux_engine_set_listener_up", fz_37 },
    { "aux_engine_set_listener_velocity", fz_38 },
    { "aux_sound_load", fz_39 },
    { "aux_sound_load_data", fz_40 },
    { "aux_sound_from_pcm", fz_41 },
    { "aux_sound_tone", fz_42 },
    { "aux_sound_noise", fz_43 },
    { "aux_sound_clone", fz_44 },
    { "aux_sound_free", fz_45 },
    { "aux_sound_is_valid", fz_46 },
    { "aux_sound_engine", fz_47 },
    { "aux_sound_start", fz_48 },
    { "aux_sound_start_at", fz_49 },
    { "aux_sound_stop", fz_50 },
    { "aux_sound_stop_at", fz_51 },
    { "aux_sound_stop_with_fade", fz_52 },
    { "aux_sound_fade", fz_53 },
    { "aux_sound_is_playing", fz_54 },
    { "aux_sound_at_end", fz_55 },
    { "aux_sound_seek", fz_56 },
    { "aux_sound_position", fz_57 },
    { "aux_sound_length", fz_58 },
    { "aux_sound_set_volume", fz_59 },
    { "aux_sound_volume", fz_60 },
    { "aux_sound_set_pan", fz_61 },
    { "aux_sound_pan", fz_62 },
    { "aux_sound_set_pitch", fz_63 },
    { "aux_sound_pitch", fz_64 },
    { "aux_sound_set_looping", fz_65 },
    { "aux_sound_is_looping", fz_66 },
    { "aux_sound_set_loop_range", fz_67 },
    { "aux_sound_set_frequency", fz_68 },
    { "aux_sound_set_auto_free", fz_69 },
    { "aux_sound_set_group", fz_70 },
    { "aux_sound_group", fz_71 },
    { "aux_sound_set_spatial", fz_72 },
    { "aux_sound_is_spatial", fz_73 },
    { "aux_sound_set_position", fz_74 },
    { "aux_sound_position_xyz", fz_75 },
    { "aux_sound_set_velocity", fz_76 },
    { "aux_sound_set_distance_range", fz_77 },
    { "aux_sound_set_rolloff", fz_78 },
    { "aux_sound_set_doppler", fz_79 },
    { "aux_group_create", fz_80 },
    { "aux_group_free", fz_81 },
    { "aux_group_is_valid", fz_82 },
    { "aux_group_set_volume", fz_83 },
    { "aux_group_volume", fz_84 },
    { "aux_group_set_pan", fz_85 },
    { "aux_group_pan", fz_86 },
    { "aux_group_set_pitch", fz_87 },
    { "aux_group_pitch", fz_88 },
    { "aux_group_start", fz_89 },
    { "aux_group_stop", fz_90 },
    { "aux_poll_ended", fz_91 },
    { "aux_ended_sound", fz_92 },
    { "aux_capture_open", fz_93 },
    { "aux_capture_close", fz_94 },
    { "aux_capture_is_valid", fz_95 },
    { "aux_capture_start", fz_96 },
    { "aux_capture_stop", fz_97 },
    { "aux_capture_is_running", fz_98 },
    { "aux_capture_available", fz_99 },
    { "aux_capture_read", fz_100 },
    { "aux_capture_format", fz_101 },
    { "aux_capture_sample_rate", fz_102 },
    { "aux_capture_channels", fz_103 },
    { "aux_capture_device_label", fz_104 },
    { "aux_capture_dropped", fz_105 },
    { "aux_capture_peak", fz_106 },
    { "aux_capture_record_start", fz_107 },
    { "aux_capture_record_stop", fz_108 },
    { "aux_capture_is_recording", fz_109 },
    { "aux_decode_file", fz_110 },
    { "aux_decode_data", fz_111 },
    { "aux_wav_encode", fz_112 },
    { "aux_shut_down", fz_113 },
};
/* <<< END FUZZ CALLS <<< */

#define FUZZ_COUNT ((int)(sizeof(k_fuzz) / sizeof(k_fuzz[0])))

static int run_seed(unsigned long long seed, int calls)
{
    s_state = seed * 0x9E3779B97F4A7C15ULL + 1;
    memset(&s_engines, 0, sizeof(s_engines));
    memset(&s_sounds, 0, sizeof(s_sounds));
    memset(&s_groups, 0, sizeof(s_groups));
    memset(&s_captures, 0, sizeof(s_captures));
    s_bad = 0;
    for (int i = 0; i < calls; i++) {
        const FuzzCall *c = &k_fuzz[below(FUZZ_COUNT)];
        /* A shutdown empties everything, so it is taken one time in twenty
         * that it is drawn: often enough to be tested hard, rarely enough
         * that engines live long enough to be played with. A device engine
         * is drawn far more often than it should be opened (each is a real
         * thread started and stopped), so those are thinned the same way. */
        if (strcmp(c->name, "aux_shut_down") == 0 && below(20) != 0) continue;
        if ((strcmp(c->name, "aux_engine_create") == 0 || strcmp(c->name, "aux_capture_open") == 0) && below(4) != 0) continue;
        c->call();
        if (strcmp(c->name, "aux_shut_down") == 0) s_outBytes = 0;
    }
    aux_shut_down();
    /* after a shutdown nothing a pool holds may be alive */
    int alive = 0;
    for (int i = 0; i < s_engines.n; i++) alive += aux_engine_is_valid(s_engines.h[i]);
    for (int i = 0; i < s_sounds.n; i++) alive += aux_sound_is_valid(s_sounds.h[i]);
    for (int i = 0; i < s_groups.n; i++) alive += aux_group_is_valid(s_groups.h[i]);
    for (int i = 0; i < s_captures.n; i++) alive += aux_capture_is_valid(s_captures.h[i]);
    if (alive) { printf("FAIL seed %llu: %d handle(s) alive after shutdown\n", seed, alive); s_bad++; }
    return s_bad;
}

int main(int argc, char **argv)
{
    unsigned long long first = 1, last = 3;
    int calls = 20000, bad = 0;
    setvbuf(stdout, NULL, _IONBF, 0);
    s_trace = getenv("AUDIOXT_FUZZ_TRACE") != NULL;
    if (argc > 1) { first = last = strtoull(argv[1], NULL, 10); }
    if (argc > 2) calls = atoi(argv[2]);

    /* the fixtures the draws use */
    for (size_t i = 0; i < sizeof(s_pcm) / 2; i++) {
        short v = (short)(8000.0 * sin((double)i * 0.3));
        memcpy(s_pcm + i * 2, &v, 2);
    }
    for (size_t i = 0; i < sizeof(s_junk); i++) s_junk[i] = (unsigned char)(i * 37 + 11);
    s_wavSize = aux_wav_encode(s_pcm, (int)sizeof(s_pcm), "s16", 8000, 1);
    if (s_wavSize <= 0 || s_wavSize > (int)sizeof(s_wav)) { printf("FAIL could not make the WAV fixture\n"); return 1; }
    memcpy(s_wav, aux_out_pointer(), (size_t)s_wavSize);
    FILE *f = fopen(k_fuzz_wav, "wb");
    if (!f || fwrite(s_wav, 1, (size_t)s_wavSize, f) != (size_t)s_wavSize) { printf("FAIL could not write the WAV fixture\n"); return 1; }
    fclose(f);

    for (unsigned long long seed = first; seed <= last; seed++) {
        int b = run_seed(seed, calls);
        printf("seed %llu: %d calls drawn, %s\n", seed, calls, b ? "FAILED" : "ok");
        bad += b;
    }
    remove(k_fuzz_wav);
    remove(k_fuzz_out);
    printf("audioxt fuzz: %llu calls over %d exports, %llu text results and %llu bytes read back, %d failed\n",
           s_calls, FUZZ_COUNT, s_texts, s_bytes, bad);
    return bad == 0 ? 0 : 1;
}
