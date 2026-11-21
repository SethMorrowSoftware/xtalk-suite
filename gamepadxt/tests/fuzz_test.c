/*
 * fuzz_test.c - random calls into every export of the gamepadxt shim.
 *
 * The smoke test asks "does each call do what the page says". This one asks
 * the question a script author answers by accident: what happens when ANY
 * call is given ANY value, in any order - a dead handle, a name that is not
 * a button, NULL, NaN, infinity, a rumble before the library is started, a
 * stop in the middle of everything. The contract of the binding is that none
 * of it can crash the host:
 *
 *   - no call faults (the run is built with ASan/UBSan in CI, with SDL's own
 *     assertions compiled in, and a failed assertion fails the run);
 *   - no text result is NULL, and its length is what gpx_text_length says;
 *   - no number result is NaN or infinite, and every axis the library
 *     reports is inside -1 to 1;
 *   - the pad table and the event queue stay inside their stated bounds,
 *     and a library that is not started holds no pad.
 *
 * The call list is GENERATED from the shim's signatures (tools/check-smoke-
 * coverage.py --write fills the block below and the gate holds it), so a new
 * export is fuzzed the day it is written. Arguments are drawn by PARAMETER
 * NAME: `pad` is usually a live pad, sometimes a stale one, 0 or noise;
 * `button` is usually a button name, sometimes an axis name, junk or NULL.
 * Every pad here is one of SDL's virtual pads (see tests/smoke_test.c).
 *
 * Deterministic: the generator is a fixed xorshift, so a seed that fails
 * here fails the same way everywhere.
 *
 *     gamepadxt_fuzz [seed [calls]]    default: seeds 1..3, 20000 calls each
 *     gamepadxt_fuzz --replay FILE     make the calls of a trace again
 *     FUZZ_TRACE=1  print each call before it is made
 */
#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* >>> BEGIN SHIM DECLARATIONS (generated: tools/check-smoke-coverage.py --write) >>> */
/* 55 exports, in the shim's order. Plain declarations: the test is a client of
 * the built library, exactly as the engine's FFI is. */
extern int gpx_abi_version(void);
extern const char*gpx_library_version(void);
extern const char*gpx_last_error(void);
extern int gpx_text_length(const char*text);
extern int gpx_assert_count(void);
extern int gpx_start(void);
extern void gpx_stop(void);
extern int gpx_is_started(void);
extern int gpx_poll(void);
extern int gpx_event_count(void);
extern const char*gpx_events(void);
extern int gpx_dropped_events(void);
extern void gpx_set_axis_events(double step);
extern double gpx_axis_events(void);
extern int gpx_pad_count(void);
extern int gpx_pad_at(int index);
extern const char*gpx_pads(void);
extern int gpx_pad_is_connected(int pad);
extern const char*gpx_pad_name(int pad);
extern const char*gpx_pad_type(int pad);
extern int gpx_pad_vendor(int pad);
extern int gpx_pad_product(int pad);
extern const char*gpx_pad_guid(int pad);
extern int gpx_pad_player(int pad);
extern int gpx_pad_set_player(int pad, int player);
extern int gpx_pad_is_virtual(int pad);
extern int gpx_pad_battery(int pad);
extern const char*gpx_pad_power(int pad);
extern const char*gpx_pad_mapping(int pad);
extern const char*gpx_button_names(void);
extern const char*gpx_axis_names(void);
extern int gpx_pad_button(int pad, const char*button);
extern int gpx_pad_has_button(int pad, const char*button);
extern const char*gpx_pad_buttons(int pad);
extern const char*gpx_pad_button_label(int pad, const char*button);
extern double gpx_pad_axis(int pad, const char*axis);
extern int gpx_pad_has_axis(int pad, const char*axis);
extern const char*gpx_pad_axes(int pad);
extern const char*gpx_pad_stick(int pad, const char*side);
extern void gpx_set_dead_zone(double zone);
extern double gpx_dead_zone(void);
extern int gpx_pad_has_rumble(int pad);
extern int gpx_pad_rumble(int pad, double low, double high, int milliseconds);
extern int gpx_pad_has_trigger_rumble(int pad);
extern int gpx_pad_rumble_triggers(int pad, double left, double right, int milliseconds);
extern int gpx_pad_has_led(int pad);
extern int gpx_pad_set_led(int pad, int red, int green, int blue);
extern int gpx_add_mapping(const char*mapping);
extern int gpx_add_mappings_from_file(const char*path);
extern int gpx_virtual_attach(const char*name);
extern void gpx_virtual_detach(int pad);
extern int gpx_virtual_set_button(int pad, const char*button, int down);
extern int gpx_virtual_set_axis(int pad, const char*axis, double value);
extern const char*gpx_virtual_rumble(int pad);
extern const char*gpx_virtual_led(int pad);
/* <<< END SHIM DECLARATIONS <<< */

/* ------------------------------------------------------------------ */
/* The generator                                                       */
/* ------------------------------------------------------------------ */
static uint64_t s_rng = 1;
static uint32_t rnd(void)
{
    s_rng ^= s_rng << 13;
    s_rng ^= s_rng >> 7;
    s_rng ^= s_rng << 17;
    return (uint32_t)(s_rng >> 16);
}
static int below(int n) { return n > 0 ? (int)(rnd() % (uint32_t)n) : 0; }
static double unit(void) { return (double)(rnd() & 0xFFFFFF) / (double)0x1000000; }

/* ------------------------------------------------------------------ */
/* The pad pool: what the creators returned, dead handles included (a  */
/* detached pad's handle stays in the pool, and that is the point).    */
/* ------------------------------------------------------------------ */
#define POOL_CAP 1024
typedef struct { int items[POOL_CAP]; int count; } Pool;
static Pool s_pads;

static void keep(Pool *p, int h)
{
    if (h <= 0) return;
    if (p->count < POOL_CAP) p->items[p->count++] = h;
    else p->items[below(POOL_CAP)] = h;
}
static int HP(void)
{
    int roll = below(100);
    if (roll < 86 && s_pads.count > 0) {
        /* lean towards the newest handles: they are the live ones */
        int span = s_pads.count < 12 || below(3) == 0 ? s_pads.count : 12;
        return s_pads.items[s_pads.count - 1 - below(span)];
    }
    if (roll < 90) return 0;
    if (roll < 96) return (int)rnd();                /* any bit pattern   */
    return below(2) ? -below(1000) : below(1 << 16); /* small or negative */
}
static int flag(void) { int r = below(20); return r < 9 ? 0 : r < 18 ? 1 : r == 18 ? -7 : 255; }
static int small(int lo, int hi)
{
    if (below(25) == 0) return below(2) ? -2147483647 - 1 : 2147483647;
    return lo + below(hi - lo + 1);
}

/* ------------------------------------------------------------------ */
/* Doubles: mostly what a stick or a strength would be, sometimes not. */
/* ------------------------------------------------------------------ */
static double D(void)
{
    static const double k[] = { 1e38, -1e38, 1e300, -1e300, 1e-300, 4.9e-324, 2.0, -2.0, 1.0000001, 65536.0 };
    int r = below(100);
    if (r < 45) return unit() * 2.0 - 1.0;
    if (r < 75) return unit();
    if (r < 82) return 0.0;
    if (r < 86) return 1.0;
    if (r < 89) return -1.0;
    if (r < 91) return NAN;
    if (r < 93) return below(2) ? INFINITY : -INFINITY;
    if (r < 94) return -0.0;
    return k[below((int)(sizeof(k) / sizeof(k[0])))];
}

/* ------------------------------------------------------------------ */
/* Text arguments ride in the trace as an INDEX into this table.       */
/* ------------------------------------------------------------------ */
#define FUZZ_FILE "gamepadxt-fuzz-mappings.txt"
static const char k_long[] =
    "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
    "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx";
static const char *const k_texts[] = {
    /*  0 */ NULL, "",
    /*  2 */ "south", "east", "west", "north", "back", "guide", "start", "leftstick", "rightstick",
             "leftshoulder", "rightshoulder", "dpup", "dpdown", "dpleft", "dpright", "misc1",
             "rightpaddle1", "leftpaddle1", "rightpaddle2", "leftpaddle2", "touchpad",
             "misc2", "misc3", "misc4", "misc5", "misc6",
    /* 28 */ "a", "b", "x", "y",
    /* 32 */ "leftx", "lefty", "rightx", "righty", "lefttrigger", "righttrigger",
    /* 38 */ "left", "right",
    /* 40 */ "nosuch", "SOUTH", "Left", " south", k_long,
    /* 45 */ "Fuzz Pad", "a,b\nc\t,", "\xff\xfe pad",
    /* 48 */ "03000000deadbeef0000cafe00000000,Fuzz Mapping,a:b0,b:b1,leftx:a0,lefty:a1,",
             "03000000deadbeef0000cafe00000000,Fuzz Mapping Again,a:b1,b:b0,",
             "not a mapping", ",,,,", "03000000deadbeef0000cafe00000000,x,a:b999999999,leftx:a-1,",
    /* 53 */ FUZZ_FILE, "no-such-directory/no-such-file.txt", ".",
};
#define N_TEXTS ((int)(sizeof(k_texts) / sizeof(k_texts[0])))
static const char *T(double index)
{
    int i = (int)index;
    return (i >= 0 && i < N_TEXTS) ? k_texts[i] : NULL;
}
/* a pick from [first, last] most of the time, anything in the table otherwise */
static double pick(int first, int last, int sure)
{
    return below(100) < sure ? first + below(last - first + 1) : below(N_TEXTS);
}
static double TB(void) { return below(10) == 0 ? pick(28, 31, 100) : pick(2, 27, 88); }   /* a button */
static double TA(void) { return pick(32, 37, 88); }                                       /* an axis   */
static double TS(void) { return pick(38, 39, 85); }                                       /* a side    */
static double TN(void) { return pick(45, 47, 70); }                                       /* a name    */
static double TM(void) { return pick(48, 52, 80); }                                       /* a mapping */
static double TF(void) { return pick(53, 55, 80); }                                       /* a path    */

/* ------------------------------------------------------------------ */
/* What every result must satisfy                                      */
/* ------------------------------------------------------------------ */
static int s_findings = 0;
static const char *s_current = "";
static void finding(const char *what, const char *detail)
{
    s_findings++;
    if (s_findings <= 40) printf("FINDING in %s: %s%s%s\n", s_current, what, detail ? ": " : "", detail ? detail : "");
}

/* every comma-separated number of a text is inside lo..hi */
static void numbers_in(const char *r, double lo, double hi)
{
    const char *p = r;
    while (*p) {
        char *end = NULL;
        double v = strtod(p, &end);
        if (end == p) { finding("a number text holds something that is not a number", r); return; }
        if (!(v >= lo && v <= hi)) { finding("a number text holds a value out of range", r); return; }
        p = end;
        if (*p == ',') p++;
        else if (*p) { finding("a number text is not comma-separated numbers", r); return; }
    }
}
static void text(const char *r)
{
    if (!r) { finding("a text result is NULL", NULL); return; }
    if (gpx_text_length(r) != (int)strlen(r)) finding("gpx_text_length disagrees with the text", r);
    if (strcmp(s_current, "gpx_pad_axes") == 0 || strcmp(s_current, "gpx_pad_stick") == 0) numbers_in(r, -1.0, 1.0);
    if (strcmp(s_current, "gpx_virtual_rumble") == 0) numbers_in(r, 0.0, 1.0);
    if (strcmp(s_current, "gpx_virtual_led") == 0) numbers_in(r, 0.0, 255.0);
}
static void number(double r)
{
    if (!isfinite(r)) finding("a number result is not finite", NULL);
    else if (r < -1.0 || r > 1.0) finding("a number result is outside -1 to 1", NULL);
}

/* FUZZ_TRACE=1 in the environment prints every call with its arguments
 * before it is made, so the last line of a run that died is the call that
 * killed it. The trace is also a program: `gamepadxt_fuzz --replay FILE`
 * makes the same calls again, which is how a failure found on one machine
 * is carried to another and how a long one is cut down. */
static int s_trace = 0;
static int s_lastInt = 0;
static void tr(const char *name, int n, const double *a)
{
    if (!s_trace) return;
    printf("%s(", name);
    for (int i = 0; i < n; i++) printf("%s%.17g", i ? ", " : "", a[i]);
    printf(")\n");
    fflush(stdout);
}

/* >>> BEGIN FUZZ CALLS (generated: tools/check-smoke-coverage.py --write) >>> */
/* Two thunks per export. fz_N draws the arguments, in order (C leaves the
 * order of argument evaluation open, and a run must be the same
 * everywhere), and hands them to rp_N, which traces and makes the call;
 * a replayed trace enters at rp_N with the numbers it read. Every
 * argument rides as a double: an int fits one exactly, and a text
 * argument rides as its index in the pool it was drawn from. */
static void rp_0(const double *a) { (void)a; tr("gpx_abi_version", 0, a); s_lastInt = gpx_abi_version(); }
static void fz_0(void) { double a[1];  rp_0(a); }
static void rp_1(const double *a) { (void)a; tr("gpx_library_version", 0, a); text(gpx_library_version()); }
static void fz_1(void) { double a[1];  rp_1(a); }
static void rp_2(const double *a) { (void)a; tr("gpx_last_error", 0, a); text(gpx_last_error()); }
static void fz_2(void) { double a[1];  rp_2(a); }
static void rp_4(const double *a) { (void)a; tr("gpx_assert_count", 0, a); s_lastInt = gpx_assert_count(); }
static void fz_4(void) { double a[1];  rp_4(a); }
static void rp_5(const double *a) { (void)a; tr("gpx_start", 0, a); s_lastInt = gpx_start(); }
static void fz_5(void) { double a[1];  rp_5(a); }
static void rp_6(const double *a) { (void)a; tr("gpx_stop", 0, a); gpx_stop(); }
static void fz_6(void) { double a[1];  rp_6(a); }
static void rp_7(const double *a) { (void)a; tr("gpx_is_started", 0, a); s_lastInt = gpx_is_started(); }
static void fz_7(void) { double a[1];  rp_7(a); }
static void rp_8(const double *a) { (void)a; tr("gpx_poll", 0, a); s_lastInt = gpx_poll(); }
static void fz_8(void) { double a[1];  rp_8(a); }
static void rp_9(const double *a) { (void)a; tr("gpx_event_count", 0, a); s_lastInt = gpx_event_count(); }
static void fz_9(void) { double a[1];  rp_9(a); }
static void rp_10(const double *a) { (void)a; tr("gpx_events", 0, a); text(gpx_events()); }
static void fz_10(void) { double a[1];  rp_10(a); }
static void rp_11(const double *a) { (void)a; tr("gpx_dropped_events", 0, a); s_lastInt = gpx_dropped_events(); }
static void fz_11(void) { double a[1];  rp_11(a); }
static void rp_12(const double *a) { tr("gpx_set_axis_events", 1, a); gpx_set_axis_events(a[0]); }
static void fz_12(void) { double a[1]; a[0] = D(); rp_12(a); }
static void rp_13(const double *a) { (void)a; tr("gpx_axis_events", 0, a); number(gpx_axis_events()); }
static void fz_13(void) { double a[1];  rp_13(a); }
static void rp_14(const double *a) { (void)a; tr("gpx_pad_count", 0, a); s_lastInt = gpx_pad_count(); }
static void fz_14(void) { double a[1];  rp_14(a); }
static void rp_15(const double *a) { tr("gpx_pad_at", 1, a); s_lastInt = gpx_pad_at((int)a[0]); keep(&s_pads, s_lastInt); }
static void fz_15(void) { double a[1]; a[0] = small(-1, 6); rp_15(a); }
static void rp_16(const double *a) { (void)a; tr("gpx_pads", 0, a); text(gpx_pads()); }
static void fz_16(void) { double a[1];  rp_16(a); }
static void rp_17(const double *a) { tr("gpx_pad_is_connected", 1, a); s_lastInt = gpx_pad_is_connected((int)a[0]); }
static void fz_17(void) { double a[1]; a[0] = HP(); rp_17(a); }
static void rp_18(const double *a) { tr("gpx_pad_name", 1, a); text(gpx_pad_name((int)a[0])); }
static void fz_18(void) { double a[1]; a[0] = HP(); rp_18(a); }
static void rp_19(const double *a) { tr("gpx_pad_type", 1, a); text(gpx_pad_type((int)a[0])); }
static void fz_19(void) { double a[1]; a[0] = HP(); rp_19(a); }
static void rp_20(const double *a) { tr("gpx_pad_vendor", 1, a); s_lastInt = gpx_pad_vendor((int)a[0]); }
static void fz_20(void) { double a[1]; a[0] = HP(); rp_20(a); }
static void rp_21(const double *a) { tr("gpx_pad_product", 1, a); s_lastInt = gpx_pad_product((int)a[0]); }
static void fz_21(void) { double a[1]; a[0] = HP(); rp_21(a); }
static void rp_22(const double *a) { tr("gpx_pad_guid", 1, a); text(gpx_pad_guid((int)a[0])); }
static void fz_22(void) { double a[1]; a[0] = HP(); rp_22(a); }
static void rp_23(const double *a) { tr("gpx_pad_player", 1, a); s_lastInt = gpx_pad_player((int)a[0]); }
static void fz_23(void) { double a[1]; a[0] = HP(); rp_23(a); }
static void rp_24(const double *a) { tr("gpx_pad_set_player", 2, a); s_lastInt = gpx_pad_set_player((int)a[0], (int)a[1]); }
static void fz_24(void) { double a[2]; a[0] = HP(); a[1] = small(-2, 17); rp_24(a); }
static void rp_25(const double *a) { tr("gpx_pad_is_virtual", 1, a); s_lastInt = gpx_pad_is_virtual((int)a[0]); }
static void fz_25(void) { double a[1]; a[0] = HP(); rp_25(a); }
static void rp_26(const double *a) { tr("gpx_pad_battery", 1, a); s_lastInt = gpx_pad_battery((int)a[0]); }
static void fz_26(void) { double a[1]; a[0] = HP(); rp_26(a); }
static void rp_27(const double *a) { tr("gpx_pad_power", 1, a); text(gpx_pad_power((int)a[0])); }
static void fz_27(void) { double a[1]; a[0] = HP(); rp_27(a); }
static void rp_28(const double *a) { tr("gpx_pad_mapping", 1, a); text(gpx_pad_mapping((int)a[0])); }
static void fz_28(void) { double a[1]; a[0] = HP(); rp_28(a); }
static void rp_29(const double *a) { (void)a; tr("gpx_button_names", 0, a); text(gpx_button_names()); }
static void fz_29(void) { double a[1];  rp_29(a); }
static void rp_30(const double *a) { (void)a; tr("gpx_axis_names", 0, a); text(gpx_axis_names()); }
static void fz_30(void) { double a[1];  rp_30(a); }
static void rp_31(const double *a) { tr("gpx_pad_button", 2, a); s_lastInt = gpx_pad_button((int)a[0], T(a[1])); }
static void fz_31(void) { double a[2]; a[0] = HP(); a[1] = TB(); rp_31(a); }
static void rp_32(const double *a) { tr("gpx_pad_has_button", 2, a); s_lastInt = gpx_pad_has_button((int)a[0], T(a[1])); }
static void fz_32(void) { double a[2]; a[0] = HP(); a[1] = TB(); rp_32(a); }
static void rp_33(const double *a) { tr("gpx_pad_buttons", 1, a); text(gpx_pad_buttons((int)a[0])); }
static void fz_33(void) { double a[1]; a[0] = HP(); rp_33(a); }
static void rp_34(const double *a) { tr("gpx_pad_button_label", 2, a); text(gpx_pad_button_label((int)a[0], T(a[1]))); }
static void fz_34(void) { double a[2]; a[0] = HP(); a[1] = TB(); rp_34(a); }
static void rp_35(const double *a) { tr("gpx_pad_axis", 2, a); number(gpx_pad_axis((int)a[0], T(a[1]))); }
static void fz_35(void) { double a[2]; a[0] = HP(); a[1] = TA(); rp_35(a); }
static void rp_36(const double *a) { tr("gpx_pad_has_axis", 2, a); s_lastInt = gpx_pad_has_axis((int)a[0], T(a[1])); }
static void fz_36(void) { double a[2]; a[0] = HP(); a[1] = TA(); rp_36(a); }
static void rp_37(const double *a) { tr("gpx_pad_axes", 1, a); text(gpx_pad_axes((int)a[0])); }
static void fz_37(void) { double a[1]; a[0] = HP(); rp_37(a); }
static void rp_38(const double *a) { tr("gpx_pad_stick", 2, a); text(gpx_pad_stick((int)a[0], T(a[1]))); }
static void fz_38(void) { double a[2]; a[0] = HP(); a[1] = TS(); rp_38(a); }
static void rp_39(const double *a) { tr("gpx_set_dead_zone", 1, a); gpx_set_dead_zone(a[0]); }
static void fz_39(void) { double a[1]; a[0] = D(); rp_39(a); }
static void rp_40(const double *a) { (void)a; tr("gpx_dead_zone", 0, a); number(gpx_dead_zone()); }
static void fz_40(void) { double a[1];  rp_40(a); }
static void rp_41(const double *a) { tr("gpx_pad_has_rumble", 1, a); s_lastInt = gpx_pad_has_rumble((int)a[0]); }
static void fz_41(void) { double a[1]; a[0] = HP(); rp_41(a); }
static void rp_42(const double *a) { tr("gpx_pad_rumble", 4, a); s_lastInt = gpx_pad_rumble((int)a[0], a[1], a[2], (int)a[3]); }
static void fz_42(void) { double a[4]; a[0] = HP(); a[1] = D(); a[2] = D(); a[3] = small(-1, 40); rp_42(a); }
static void rp_43(const double *a) { tr("gpx_pad_has_trigger_rumble", 1, a); s_lastInt = gpx_pad_has_trigger_rumble((int)a[0]); }
static void fz_43(void) { double a[1]; a[0] = HP(); rp_43(a); }
static void rp_44(const double *a) { tr("gpx_pad_rumble_triggers", 4, a); s_lastInt = gpx_pad_rumble_triggers((int)a[0], a[1], a[2], (int)a[3]); }
static void fz_44(void) { double a[4]; a[0] = HP(); a[1] = D(); a[2] = D(); a[3] = small(-1, 40); rp_44(a); }
static void rp_45(const double *a) { tr("gpx_pad_has_led", 1, a); s_lastInt = gpx_pad_has_led((int)a[0]); }
static void fz_45(void) { double a[1]; a[0] = HP(); rp_45(a); }
static void rp_46(const double *a) { tr("gpx_pad_set_led", 4, a); s_lastInt = gpx_pad_set_led((int)a[0], (int)a[1], (int)a[2], (int)a[3]); }
static void fz_46(void) { double a[4]; a[0] = HP(); a[1] = small(-1, 257); a[2] = small(-1, 257); a[3] = small(-1, 257); rp_46(a); }
static void rp_47(const double *a) { tr("gpx_add_mapping", 1, a); s_lastInt = gpx_add_mapping(T(a[0])); }
static void fz_47(void) { double a[1]; a[0] = TM(); rp_47(a); }
static void rp_48(const double *a) { tr("gpx_add_mappings_from_file", 1, a); s_lastInt = gpx_add_mappings_from_file(T(a[0])); }
static void fz_48(void) { double a[1]; a[0] = TF(); rp_48(a); }
static void rp_49(const double *a) { tr("gpx_virtual_attach", 1, a); s_lastInt = gpx_virtual_attach(T(a[0])); keep(&s_pads, s_lastInt); }
static void fz_49(void) { double a[1]; a[0] = TN(); rp_49(a); }
static void rp_50(const double *a) { tr("gpx_virtual_detach", 1, a); gpx_virtual_detach((int)a[0]); }
static void fz_50(void) { double a[1]; a[0] = HP(); rp_50(a); }
static void rp_51(const double *a) { tr("gpx_virtual_set_button", 3, a); s_lastInt = gpx_virtual_set_button((int)a[0], T(a[1]), (int)a[2]); }
static void fz_51(void) { double a[3]; a[0] = HP(); a[1] = TB(); a[2] = flag(); rp_51(a); }
static void rp_52(const double *a) { tr("gpx_virtual_set_axis", 3, a); s_lastInt = gpx_virtual_set_axis((int)a[0], T(a[1]), a[2]); }
static void fz_52(void) { double a[3]; a[0] = HP(); a[1] = TA(); a[2] = D(); rp_52(a); }
static void rp_53(const double *a) { tr("gpx_virtual_rumble", 1, a); text(gpx_virtual_rumble((int)a[0])); }
static void fz_53(void) { double a[1]; a[0] = HP(); rp_53(a); }
static void rp_54(const double *a) { tr("gpx_virtual_led", 1, a); text(gpx_virtual_led((int)a[0])); }
static void fz_54(void) { double a[1]; a[0] = HP(); rp_54(a); }
typedef struct { const char *name; int argc; void (*call)(void); void (*replay)(const double *); } FuzzCall;
static const FuzzCall k_fuzz[] = {
    { "gpx_abi_version", 0, fz_0, rp_0 },
    { "gpx_library_version", 0, fz_1, rp_1 },
    { "gpx_last_error", 0, fz_2, rp_2 },
    { "gpx_assert_count", 0, fz_4, rp_4 },
    { "gpx_start", 0, fz_5, rp_5 },
    { "gpx_stop", 0, fz_6, rp_6 },
    { "gpx_is_started", 0, fz_7, rp_7 },
    { "gpx_poll", 0, fz_8, rp_8 },
    { "gpx_event_count", 0, fz_9, rp_9 },
    { "gpx_events", 0, fz_10, rp_10 },
    { "gpx_dropped_events", 0, fz_11, rp_11 },
    { "gpx_set_axis_events", 1, fz_12, rp_12 },
    { "gpx_axis_events", 0, fz_13, rp_13 },
    { "gpx_pad_count", 0, fz_14, rp_14 },
    { "gpx_pad_at", 1, fz_15, rp_15 },
    { "gpx_pads", 0, fz_16, rp_16 },
    { "gpx_pad_is_connected", 1, fz_17, rp_17 },
    { "gpx_pad_name", 1, fz_18, rp_18 },
    { "gpx_pad_type", 1, fz_19, rp_19 },
    { "gpx_pad_vendor", 1, fz_20, rp_20 },
    { "gpx_pad_product", 1, fz_21, rp_21 },
    { "gpx_pad_guid", 1, fz_22, rp_22 },
    { "gpx_pad_player", 1, fz_23, rp_23 },
    { "gpx_pad_set_player", 2, fz_24, rp_24 },
    { "gpx_pad_is_virtual", 1, fz_25, rp_25 },
    { "gpx_pad_battery", 1, fz_26, rp_26 },
    { "gpx_pad_power", 1, fz_27, rp_27 },
    { "gpx_pad_mapping", 1, fz_28, rp_28 },
    { "gpx_button_names", 0, fz_29, rp_29 },
    { "gpx_axis_names", 0, fz_30, rp_30 },
    { "gpx_pad_button", 2, fz_31, rp_31 },
    { "gpx_pad_has_button", 2, fz_32, rp_32 },
    { "gpx_pad_buttons", 1, fz_33, rp_33 },
    { "gpx_pad_button_label", 2, fz_34, rp_34 },
    { "gpx_pad_axis", 2, fz_35, rp_35 },
    { "gpx_pad_has_axis", 2, fz_36, rp_36 },
    { "gpx_pad_axes", 1, fz_37, rp_37 },
    { "gpx_pad_stick", 2, fz_38, rp_38 },
    { "gpx_set_dead_zone", 1, fz_39, rp_39 },
    { "gpx_dead_zone", 0, fz_40, rp_40 },
    { "gpx_pad_has_rumble", 1, fz_41, rp_41 },
    { "gpx_pad_rumble", 4, fz_42, rp_42 },
    { "gpx_pad_has_trigger_rumble", 1, fz_43, rp_43 },
    { "gpx_pad_rumble_triggers", 4, fz_44, rp_44 },
    { "gpx_pad_has_led", 1, fz_45, rp_45 },
    { "gpx_pad_set_led", 4, fz_46, rp_46 },
    { "gpx_add_mapping", 1, fz_47, rp_47 },
    { "gpx_add_mappings_from_file", 1, fz_48, rp_48 },
    { "gpx_virtual_attach", 1, fz_49, rp_49 },
    { "gpx_virtual_detach", 1, fz_50, rp_50 },
    { "gpx_virtual_set_button", 3, fz_51, rp_51 },
    { "gpx_virtual_set_axis", 3, fz_52, rp_52 },
    { "gpx_virtual_rumble", 1, fz_53, rp_53 },
    { "gpx_virtual_led", 1, fz_54, rp_54 },
};
/* <<< END FUZZ CALLS <<< */

static const FuzzCall *find_call(const char *name)
{
    int n = (int)(sizeof(k_fuzz) / sizeof(k_fuzz[0]));
    for (int i = 0; i < n; i++) if (strcmp(k_fuzz[i].name, name) == 0) return &k_fuzz[i];
    return NULL;
}
/* One call BY NAME, through the same thunk a random call uses, so it is in
 * the trace and a replay makes it too. Returns an int result. */
static int C(const char *name, int n, ...)
{
    double a[16] = { 0 };
    const FuzzCall *c = find_call(name);
    va_list ap;
    va_start(ap, n);
    for (int i = 0; i < n && i < 16; i++) a[i] = va_arg(ap, double);
    va_end(ap);
    if (!c || c->argc != n) { finding("the test names a call the shim does not have, or miscounts it", name); return 0; }
    s_current = name;
    s_lastInt = 0;
    c->replay(a);
    return s_lastInt;
}

/* What must hold after ANY call. */
static void invariants(void)
{
    const char *was = s_current;
    int pads = gpx_pad_count();
    int started = gpx_is_started();
    if (pads < 0 || pads > 64) finding("the pad count left 0 to 64", NULL);
    if (!started && pads != 0) finding("a library that is not started holds a pad", NULL);
    if (gpx_event_count() < 0 || gpx_event_count() > 4096) finding("the event count left 0 to 4096", NULL);
    if (!started && gpx_event_count() != 0) finding("a library that is not started holds an event", NULL);
    if (gpx_assert_count() != 0) {
        static int told = 0;
        if (!told) { told = 1; finding("an SDL assertion failed", NULL); }
    }
    if (gpx_last_error() == NULL) finding("gpx_last_error is NULL", NULL);
    s_current = was;
}

static int run(uint64_t seed, int calls)
{
    int before = s_findings;
    int n = (int)(sizeof(k_fuzz) / sizeof(k_fuzz[0]));
    s_rng = seed * 0x9E3779B97F4A7C15ull + 1;
    s_pads.count = 0;
    for (int i = 0; i < calls; i++) {
        /* Mostly a started library with a few pads on it: random calls stop
         * it and detach them, and a run over nothing tests one path forever. */
        if (!gpx_is_started() && below(10) != 0) C("gpx_start", 0);
        if (i % 300 == 0 && gpx_is_started()) {
            for (int k = 0; k < 3; k++) C("gpx_virtual_attach", 1, 45.0);
        }
        const FuzzCall *c = &k_fuzz[below(n)];
        s_current = c->name;
        c->call();
        invariants();
        /* poll often: a button set by one call shows only after it */
        if (i % 4 == 0) { C("gpx_poll", 0); invariants(); }
    }
    /* every start given back, however many the run made */
    s_current = "teardown";
    for (int guard = 0; gpx_is_started() && guard < calls + 16; guard++) gpx_stop();
    if (gpx_is_started()) finding("the library would not stop", NULL);
    invariants();
    printf("seed %llu: %d calls, %d findings\n", (unsigned long long)seed, calls, s_findings - before);
    return s_findings - before;
}

/* Make the calls a trace names, checking the invariants after each one. */
static int replay(const char *path)
{
    FILE *f = fopen(path, "r");
    char line[1024];
    int made = 0;
    if (!f) { printf("cannot open %s\n", path); return 2; }
    while (fgets(line, sizeof(line), f)) {
        char *open = strchr(line, '(');
        double a[16] = { 0 };
        int n = 0;
        if (!open || strncmp(line, "gpx_", 4) != 0) continue;
        *open = 0;
        const FuzzCall *c = find_call(line);
        if (!c) continue;
        for (char *p = open + 1; *p && *p != ')' && n < 16; ) {
            char *end = p;
            a[n] = strtod(p, &end);
            if (end == p) break;
            n++;
            p = end;
            while (*p == ',' || *p == ' ') p++;
        }
        if (n != c->argc) continue;
        s_current = c->name;
        c->replay(a);
        made++;
        invariants();
    }
    fclose(f);
    while (gpx_is_started()) gpx_stop();
    printf("replayed %d calls: %d finding(s), %d SDL assertion(s)\n", made, s_findings, gpx_assert_count());
    return s_findings || gpx_assert_count() ? 1 : 0;
}

int main(int argc, char **argv)
{
    int calls = 20000;
    FILE *f = fopen(FUZZ_FILE, "w");
    if (f) {
        /* a mappings file for every platform a build exists for, and some noise */
        static const char *const k_platforms[] = { "Linux", "Windows", "Mac OS X", "Emscripten" };
        for (int i = 0; i < 4; i++)
            fprintf(f, "03000000deadbeef0000cafe0000%02xaa,Fuzz File,a:b0,b:b1,platform:%s,\n", i, k_platforms[i]);
        fputs("# comment\n\n,,,\nnot a mapping,platform:Linux,\n", f);
        fclose(f);
    }
    s_trace = getenv("FUZZ_TRACE") != NULL;
    if (argc > 2 && strcmp(argv[1], "--replay") == 0) return replay(argv[2]);
    if (argc > 2) calls = atoi(argv[2]);
    if (argc > 1) {
        run((uint64_t)strtoull(argv[1], NULL, 10), calls);
    } else {
        for (uint64_t seed = 1; seed <= 3; seed++) run(seed, calls);
    }
    remove(FUZZ_FILE);
    /* gpx_text_length is the one export the table cannot draw for: text()
     * calls it on every text result, and here on nothing at all. */
    if (gpx_text_length(NULL) != 0 || gpx_text_length("") != 0) finding("gpx_text_length of nothing is not 0", NULL);
    printf("gamepadxt fuzz test: %d finding(s); %d SDL assertion(s)%s; %d event(s) dropped by a full queue\n",
           s_findings, gpx_assert_count(),
           gpx_assert_count() ? "" : " (0 is also what a build without assertions prints)", gpx_dropped_events());
    return s_findings || gpx_assert_count() ? 1 : 0;
}
