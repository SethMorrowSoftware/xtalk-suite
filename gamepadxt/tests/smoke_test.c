/*
 * smoke_test.c - the runtime test of the gamepadxt shim.
 *
 * Links against the gamepadxt library (or, for the web, the archive) and
 * drives the real SDL through the same C entry points the LCB binding calls.
 * It needs no controller: every pad here is one of SDL's VIRTUAL pads, which
 * travel the same road a real one does from SDL's joystick layer up (the
 * mapping, the gamepad state, the event queue, rumble and lights). What a
 * virtual pad does NOT exercise is the operating system's device backends;
 * those are SDL's own, and need a pad in a hand (docs/getting-started.md).
 *
 * A machine that does have controllers attached must still pass, so nothing
 * below assumes the pad count starts at 0.
 *
 * EVERY export of src/gamepad_shim.c is entered here: tools/check-smoke-coverage.py
 * holds the declaration block below to the shim's signatures and refuses an
 * export this file never calls. Run under ASan/UBSan in CI
 * (native-gamepadxt.yml), in a build with SDL's assertions compiled in.
 *
 * Enable with -DGAMEPADXT_BUILD_TESTS=ON, then run `ctest` (or the binary).
 */
#include <locale.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

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

#ifndef GPX_EXPECT_SDL
#define GPX_EXPECT_SDL ""
#endif

static int s_pass = 0, s_fail = 0;
#define CHECK(cond, ...)                                                      \
    do {                                                                      \
        if (cond) { s_pass++; }                                               \
        else {                                                                \
            s_fail++;                                                         \
            printf("FAIL %s:%d: ", __FILE__, __LINE__);                       \
            printf(__VA_ARGS__);                                              \
            printf("\n");                                                     \
        }                                                                     \
    } while (0)

static int near(double a, double b, double tol) { return fabs(a - b) <= tol; }

/* The shim's text results share buffers: a second call overwrites the first.
 * The binding copies at once; so does the test, into one of eight slots. */
static const char *keep(const char *text)
{
    static char slots[8][8192];
    static int next = 0;
    char *slot = slots[next++ & 7];
    snprintf(slot, sizeof(slots[0]), "%s", text ? text : "(null)");
    return slot;
}

/* Parse "a,b,c" into out[]; returns how many numbers it found, or -1 on a
 * character that is not part of a plain number. By hand (digits and one
 * '.'), so it reads the shim's text the same in any locale - the property
 * under test in test_locale(). */
static int parse(const char *text, double *out, int cap)
{
    int n = 0;
    const char *p = text;
    if (!p || !*p) return 0;
    while (*p && n < cap) {
        double sign = 1.0, value = 0.0, scale = 1.0;
        int seenDot = 0, digits = 0;
        if (*p == '-') { sign = -1.0; p++; }
        for (; *p && *p != ','; p++) {
            if (*p >= '0' && *p <= '9') {
                value = value * 10.0 + (*p - '0');
                if (seenDot) scale *= 10.0;
                digits++;
            } else if (*p == '.' && !seenDot) {
                seenDot = 1;
            } else {
                return -1;
            }
        }
        if (!digits) return -1;
        out[n++] = sign * value / scale;
        if (*p == ',') p++;
    }
    return n;
}

/* Lets real time pass without a platform sleep call: clock() is CPU time on
 * POSIX and wall time on Windows, and a busy loop advances both. */
static void wait_ms(int ms)
{
    clock_t until = clock() + (clock_t)((double)ms * CLOCKS_PER_SEC / 1000.0);
    while (clock() < until) { }
}

/* 1 if `line` is one whole line of `text`. */
static int has_line(const char *text, const char *line)
{
    size_t n = strlen(line);
    const char *p = text;
    while (p && *p) {
        const char *end = strchr(p, '\n');
        size_t len = end ? (size_t)(end - p) : strlen(p);
        if (len == n && memcmp(p, line, n) == 0) return 1;
        p = end ? end + 1 : NULL;
    }
    return 0;
}

static int count_lines(const char *text)
{
    int n = 0;
    if (!text || !*text) return 0;
    for (n = 1; *text; text++) n += (*text == '\n');
    return n;
}

/* 1 if `item` is one whole comma-separated item of `text`. */
static int has_item(const char *text, const char *item)
{
    size_t n = strlen(item);
    const char *p = text;
    while (p && *p) {
        const char *end = strchr(p, ',');
        size_t len = end ? (size_t)(end - p) : strlen(p);
        if (len == n && memcmp(p, item, n) == 0) return 1;
        p = end ? end + 1 : NULL;
    }
    return 0;
}

static const char *line_of(const char *fmt, int pad, const char *a, const char *b)
{
    static char line[128];
    snprintf(line, sizeof(line), fmt, pad, a, b);
    return line;
}

static const char *const k_buttons[26] = {
    "south", "east", "west", "north", "back", "guide", "start",
    "leftstick", "rightstick", "leftshoulder", "rightshoulder",
    "dpup", "dpdown", "dpleft", "dpright", "misc1",
    "rightpaddle1", "leftpaddle1", "rightpaddle2", "leftpaddle2",
    "touchpad", "misc2", "misc3", "misc4", "misc5", "misc6"
};
static const char *const k_axes[6] = { "leftx", "lefty", "rightx", "righty", "lefttrigger", "righttrigger" };

/* ------------------------------------------------------------------ */
static void test_library(void)
{
    CHECK(gpx_abi_version() == 1, "ABI %d", gpx_abi_version());
    CHECK(strncmp(gpx_library_version(), "SDL 3.", 6) == 0, "library version: %s", gpx_library_version());
    /* The build names the SDL it pinned; the library must be that one. */
    if (GPX_EXPECT_SDL[0]) {
        CHECK(strcmp(gpx_library_version(), GPX_EXPECT_SDL) == 0, "built for %s, running %s",
              GPX_EXPECT_SDL, gpx_library_version());
    }
    CHECK(gpx_text_length("") == 0 && gpx_text_length(NULL) == 0, "text length of nothing");
    CHECK(gpx_text_length(gpx_library_version()) == (int)strlen(gpx_library_version()), "text length of a result");
    CHECK(gpx_assert_count() == 0, "no SDL assertion before anything ran");
}

/* Nothing works before gpx_start(), and nothing crashes either. */
static void test_before_start(void)
{
    CHECK(gpx_is_started() == 0, "not started at load");
    CHECK(gpx_poll() == 0 && strstr(gpx_last_error(), "not started"), "poll before start: %s", gpx_last_error());
    CHECK(gpx_event_count() == 0 && gpx_events()[0] == 0, "no events before start");
    CHECK(gpx_pad_count() == 0 && gpx_pad_at(1) == 0 && gpx_pads()[0] == 0, "no pads before start");
    CHECK(gpx_virtual_attach("early") == 0 && strstr(gpx_last_error(), "not started"), "attach before start");
    CHECK(gpx_add_mapping("x") == -1 && gpx_add_mappings_from_file("x") == -1, "mappings before start");
    CHECK(gpx_pad_name(257)[0] == 0 && gpx_pad_button(257, "south") == 0 && gpx_pad_axis(257, "leftx") == 0.0,
          "getters before start");
    CHECK(gpx_pad_is_connected(257) == 0, "nothing is connected before start");
    gpx_stop();                                     /* a stop with nothing started */
    CHECK(gpx_is_started() == 0 && gpx_last_error()[0] == 0, "a stray stop is a quiet no-op");
}

/* Starts are counted. */
static void test_counting(void)
{
    CHECK(gpx_start() == 1, "start: %s", gpx_last_error());
    CHECK(gpx_is_started() == 1 && gpx_last_error()[0] == 0, "started");
    CHECK(gpx_start() == 1, "a second start");
    gpx_stop();
    CHECK(gpx_is_started() == 1, "one stop of two starts leaves it running");
    CHECK(gpx_poll() >= 0 && gpx_last_error()[0] == 0, "still polls");
    gpx_stop();
    CHECK(gpx_is_started() == 0, "the last stop stops it");
    CHECK(gpx_start() == 1, "it starts again after a full stop: %s", gpx_last_error());
    (void)gpx_events();                             /* whatever real pads announced */
}

/* A virtual pad is a pad: listed, described, counted. Returns its handle. */
static int test_attach(int base)
{
    int pad = gpx_virtual_attach("Smoke Pad");
    const char *guid, *mapping, *power;
    char want[64];
    int i, battery;
    CHECK(pad > 0, "attach: %s", gpx_last_error());
    CHECK(gpx_pad_count() == base + 1, "pad count %d, was %d", gpx_pad_count(), base);
    snprintf(want, sizeof(want), "connected,%d", pad);
    CHECK(gpx_event_count() >= 1, "its arrival is an event");
    CHECK(has_line(keep(gpx_events()), want), "the connected event names it");
    CHECK(gpx_event_count() == 0 && gpx_events()[0] == 0, "reading the events empties the queue");
    CHECK(gpx_poll() == 0, "SDL's own announcement of a pad we opened is not a second event (%s)", keep(gpx_events()));
    snprintf(want, sizeof(want), "%d", pad);
    CHECK(has_item(keep(gpx_pads()), want), "gpx_pads lists it: %s", gpx_pads());
    for (i = 1; i <= base + 1 && gpx_pad_at(i) != pad; i++) { }
    CHECK(i <= base + 1, "gpx_pad_at reaches it");
    CHECK(gpx_pad_at(0) == 0 && gpx_pad_at(base + 2) == 0 && gpx_pad_at(-1) == 0, "gpx_pad_at out of range is 0");
    CHECK(gpx_pad_is_connected(pad) == 1 && gpx_pad_is_virtual(pad) == 1, "connected and virtual");
    CHECK(strcmp(gpx_pad_name(pad), "Smoke Pad") == 0, "name: %s", gpx_pad_name(pad));
    CHECK(strcmp(gpx_pad_type(pad), "standard") == 0, "type: %s", gpx_pad_type(pad));
    guid = keep(gpx_pad_guid(pad));
    CHECK(strlen(guid) == 32 && strspn(guid, "0123456789abcdef") == 32, "guid: %s", guid);
    CHECK(gpx_pad_vendor(pad) >= 0 && gpx_pad_vendor(pad) <= 65535, "vendor %d", gpx_pad_vendor(pad));
    CHECK(gpx_pad_product(pad) >= 0 && gpx_pad_product(pad) <= 65535, "product %d", gpx_pad_product(pad));
    mapping = keep(gpx_pad_mapping(pad));
    CHECK(strstr(mapping, "leftx:a0") && strstr(mapping, "a:b0") && strncmp(mapping, guid, 32) == 0,
          "mapping: %s", mapping);
    battery = gpx_pad_battery(pad);
    CHECK(battery >= -1 && battery <= 100, "battery %d", battery);
    power = keep(gpx_pad_power(pad));
    CHECK(has_item("unknown,onbattery,nobattery,charging,charged,error", power), "power: %s", power);
    /* the player number */
    CHECK(gpx_pad_player(pad) >= -1, "player %d", gpx_pad_player(pad));
    CHECK(gpx_pad_set_player(pad, 3) == 1 && gpx_pad_player(pad) == 3, "player set to 3, reads %d (%s)",
          gpx_pad_player(pad), gpx_last_error());
    CHECK(gpx_pad_set_player(pad, 16) == 0 && gpx_pad_set_player(pad, -2) == 0 && gpx_pad_player(pad) == 3,
          "a player number out of range is refused");
    CHECK(gpx_pad_set_player(pad, -1) == 1 && gpx_pad_player(pad) == -1, "player cleared");
    /* a name with a comma or a control character cannot break the mapping line */
    {
        int odd = gpx_virtual_attach("a,b\tc");
        CHECK(odd > 0 && strcmp(gpx_pad_name(odd), "a b c") == 0, "an awkward name: %s", gpx_pad_name(odd));
        gpx_virtual_detach(odd);
        odd = gpx_virtual_attach("");
        CHECK(odd > 0 && strcmp(gpx_pad_name(odd), "Virtual Gamepad") == 0, "an empty name: %s", gpx_pad_name(odd));
        gpx_virtual_detach(odd);
        odd = gpx_virtual_attach(NULL);
        CHECK(odd > 0, "a NULL name");
        gpx_virtual_detach(odd);
        CHECK(gpx_virtual_attach("0123456789012345678901234567890123456789012345678901234567890123456789") == 0,
              "a name over 64 bytes is refused");
        (void)gpx_poll();
        (void)gpx_events();
    }
    return pad;
}

static void test_buttons(int pad)
{
    const char *names = keep(gpx_button_names());
    const char *events;
    int i;
    for (i = 0; i < 26; i++) CHECK(has_item(names, k_buttons[i]), "gpx_button_names has %s", k_buttons[i]);
    CHECK(count_lines(names) == 1 && strlen(names) > 200, "one line of names");
    CHECK(gpx_pad_buttons(pad)[0] == 0, "nothing held to begin with: %s", gpx_pad_buttons(pad));

    /* every button, one at a time: state, event, list, release */
    for (i = 0; i < 26; i++) {
        const char *b = k_buttons[i];
        CHECK(gpx_pad_has_button(pad, b) == 1, "the virtual pad has %s", b);
        CHECK(gpx_pad_button(pad, b) == 0, "%s is up", b);
        CHECK(gpx_virtual_set_button(pad, b, 1) == 1, "press %s: %s", b, gpx_last_error());
        CHECK(gpx_pad_button(pad, b) == 0, "%s shows only at the next poll", b);
        CHECK(gpx_poll() == 1, "one event for one press of %s (%d)", b, gpx_event_count());
        CHECK(gpx_pad_button(pad, b) == 1, "%s is down", b);
        CHECK(strcmp(gpx_pad_buttons(pad), b) == 0, "held: %s", gpx_pad_buttons(pad));
        events = keep(gpx_events());
        CHECK(strcmp(events, line_of("button,%d,%s,%s", pad, b, "down")) == 0, "event: %s", events);
        CHECK(gpx_virtual_set_button(pad, b, 0) == 1, "release %s", b);
        if (strcmp(b, "guide") == 0) {
            /* SDL holds back the EVENT of a guide release until a quarter of
             * a second after the press (so a tap too short for a system
             * overlay to see is still seen by it). The state reads up at once. */
            { int n = gpx_poll(); CHECK(n == 0 && gpx_pad_button(pad, b) == 0, "a guide release event is held back (%d events, held %d)", n, gpx_pad_button(pad, b)); }
            wait_ms(400);
        }
        CHECK(gpx_poll() == 1, "the release of %s is one event (%d)", b, gpx_event_count());
        events = keep(gpx_events());
        CHECK(strcmp(events, line_of("button,%d,%s,%s", pad, b, "up")) == 0, "event: %s", events);
        CHECK(gpx_pad_button(pad, b) == 0, "%s is up again", b);
    }

    /* several at once, in SDL's order; any non-zero is "down" */
    gpx_virtual_set_button(pad, "start", 1);
    gpx_virtual_set_button(pad, "south", 255);
    gpx_virtual_set_button(pad, "dpleft", -1);
    CHECK(gpx_poll() == 3, "three presses, three events (%d)", gpx_event_count());
    CHECK(strcmp(gpx_pad_buttons(pad), "south,start,dpleft") == 0, "held: %s", gpx_pad_buttons(pad));
    CHECK(count_lines(keep(gpx_events())) == 3, "three lines");
    gpx_virtual_set_button(pad, "start", 0);
    gpx_virtual_set_button(pad, "south", 0);
    gpx_virtual_set_button(pad, "dpleft", 0);
    CHECK(gpx_poll() == 3 && gpx_pad_buttons(pad)[0] == 0, "all released");
    (void)gpx_events();

    /* the Xbox letters are accepted as positions; any letter case */
    gpx_virtual_set_button(pad, "a", 1);
    (void)gpx_poll();
    CHECK(gpx_pad_button(pad, "south") == 1 && gpx_pad_button(pad, "A") == 1 && gpx_pad_button(pad, "SOUTH") == 1,
          "a is south, in any case");
    CHECK(has_line(keep(gpx_events()), line_of("button,%d,%s,%s", pad, "south", "down")), "events use the position name");
    gpx_virtual_set_button(pad, "South", 0);
    gpx_virtual_set_button(pad, "y", 1);
    (void)gpx_poll();
    CHECK(gpx_pad_button(pad, "north") == 1 && gpx_pad_button(pad, "b") == 0 && gpx_pad_button(pad, "x") == 0,
          "y is north");
    gpx_virtual_set_button(pad, "north", 0);
    (void)gpx_poll();
    (void)gpx_events();

    /* names that are not buttons */
    CHECK(gpx_pad_button(pad, "nosuch") == 0 && strstr(gpx_last_error(), "no such button"), "unknown button: %s", gpx_last_error());
    CHECK(gpx_pad_button(pad, NULL) == 0 && gpx_pad_button(pad, "") == 0 && gpx_pad_button(pad, "leftx") == 0,
          "NULL, empty and an axis name are not buttons");
    CHECK(gpx_pad_has_button(pad, "south ") == 0 && gpx_virtual_set_button(pad, "sou", 1) == 0, "near misses are refused");
    CHECK(gpx_pad_button(pad, "south") == 0 && gpx_last_error()[0] == 0, "a good call clears the error");

    /* printed labels: a standard pad is lettered like an Xbox pad */
    CHECK(strcmp(gpx_pad_button_label(pad, "south"), "a") == 0, "south label: %s", gpx_pad_button_label(pad, "south"));
    CHECK(strcmp(gpx_pad_button_label(pad, "east"), "b") == 0, "east label");
    CHECK(strcmp(gpx_pad_button_label(pad, "west"), "x") == 0, "west label");
    CHECK(strcmp(gpx_pad_button_label(pad, "north"), "y") == 0, "north label");
    CHECK(gpx_pad_button_label(pad, "start")[0] == 0 && gpx_pad_button_label(pad, "nosuch")[0] == 0
          && gpx_pad_button_label(pad, NULL)[0] == 0, "no label off the face buttons");
}

static void test_axes(int pad)
{
    const char *names = keep(gpx_axis_names());
    double v[8];
    int i;
    CHECK(strcmp(names, "leftx,lefty,rightx,righty,lefttrigger,righttrigger") == 0, "axis names: %s", names);
    (void)gpx_poll();
    CHECK(strcmp(gpx_pad_axes(pad), "0,0,0,0,0,0") == 0, "at rest: %s", gpx_pad_axes(pad));
    for (i = 0; i < 6; i++) CHECK(gpx_pad_has_axis(pad, k_axes[i]) == 1, "the virtual pad has %s", k_axes[i]);

    /* sticks: -1 to 1 */
    for (i = 0; i < 4; i++) {
        const char *a = k_axes[i];
        CHECK(gpx_virtual_set_axis(pad, a, 0.5) == 1, "set %s: %s", a, gpx_last_error());
        (void)gpx_poll();
        CHECK(near(gpx_pad_axis(pad, a), 0.5, 0.0001), "%s reads %g", a, gpx_pad_axis(pad, a));
        gpx_virtual_set_axis(pad, a, -1.0);
        (void)gpx_poll();
        CHECK(gpx_pad_axis(pad, a) == -1.0, "%s at its end reads %g", a, gpx_pad_axis(pad, a));
        gpx_virtual_set_axis(pad, a, 1.0);
        (void)gpx_poll();
        CHECK(gpx_pad_axis(pad, a) == 1.0, "%s at its other end reads %g", a, gpx_pad_axis(pad, a));
        gpx_virtual_set_axis(pad, a, 0.0);
        (void)gpx_poll();
        CHECK(gpx_pad_axis(pad, a) == 0.0, "%s back at rest reads %g", a, gpx_pad_axis(pad, a));
        CHECK(gpx_virtual_set_axis(pad, a, 1.01) == 0 && gpx_virtual_set_axis(pad, a, -1.01) == 0,
              "%s past its ends is refused", a);
    }
    /* triggers: 0 to 1 */
    for (i = 4; i < 6; i++) {
        const char *a = k_axes[i];
        gpx_virtual_set_axis(pad, a, 0.75);
        (void)gpx_poll();
        CHECK(near(gpx_pad_axis(pad, a), 0.75, 0.0001), "%s reads %g", a, gpx_pad_axis(pad, a));
        gpx_virtual_set_axis(pad, a, 1.0);
        (void)gpx_poll();
        CHECK(gpx_pad_axis(pad, a) == 1.0, "%s full reads %g", a, gpx_pad_axis(pad, a));
        CHECK(gpx_virtual_set_axis(pad, a, -0.1) == 0 && gpx_virtual_set_axis(pad, a, 1.5) == 0,
              "%s outside 0 to 1 is refused", a);
        gpx_virtual_set_axis(pad, a, 0.0);
        (void)gpx_poll();
        CHECK(gpx_pad_axis(pad, a) == 0.0, "%s released reads %g", a, gpx_pad_axis(pad, a));
    }
    CHECK(gpx_virtual_set_axis(pad, "leftx", NAN) == 0 && gpx_virtual_set_axis(pad, "leftx", INFINITY) == 0,
          "not-a-number and infinity are refused");
    CHECK(gpx_virtual_set_axis(pad, "south", 0.5) == 0 && gpx_virtual_set_axis(pad, NULL, 0.5) == 0
          && gpx_pad_axis(pad, "nosuch") == 0.0 && gpx_pad_has_axis(pad, "") == 0, "names that are not axes");

    /* all six in one call, in order */
    gpx_virtual_set_axis(pad, "leftx", 0.25);
    gpx_virtual_set_axis(pad, "lefty", -0.5);
    gpx_virtual_set_axis(pad, "rightx", 1.0);
    gpx_virtual_set_axis(pad, "righty", -1.0);
    gpx_virtual_set_axis(pad, "lefttrigger", 0.5);
    gpx_virtual_set_axis(pad, "righttrigger", 1.0);
    (void)gpx_poll();
    CHECK(parse(keep(gpx_pad_axes(pad)), v, 8) == 6, "six numbers: %s", gpx_pad_axes(pad));
    CHECK(near(v[0], 0.25, 0.0002) && near(v[1], -0.5, 0.0002) && v[2] == 1.0 && v[3] == -1.0
          && near(v[4], 0.5, 0.0002) && v[5] == 1.0, "the six axes: %s", gpx_pad_axes(pad));
    for (i = 0; i < 6; i++) gpx_virtual_set_axis(pad, k_axes[i], 0.0);
    (void)gpx_poll();
    CHECK(gpx_events()[0] == 0, "axis motion queues nothing unless asked: %s", gpx_events());
}

static void stick_at(int pad, double x, double y)
{
    gpx_virtual_set_axis(pad, "leftx", x);
    gpx_virtual_set_axis(pad, "lefty", y);
    gpx_virtual_set_axis(pad, "rightx", y);
    gpx_virtual_set_axis(pad, "righty", x);
    (void)gpx_poll();
}

static void test_stick(int pad)
{
    double v[4];
    CHECK(near(gpx_dead_zone(), 0.15, 1e-12), "the dead zone starts at 0.15 (%g)", gpx_dead_zone());
    stick_at(pad, 0.0, 0.0);
    CHECK(strcmp(gpx_pad_stick(pad, "left"), "0,0") == 0, "at rest: %s", gpx_pad_stick(pad, "left"));
    stick_at(pad, 0.1, -0.1);
    CHECK(strcmp(gpx_pad_stick(pad, "left"), "0,0") == 0, "inside the zone: %s", gpx_pad_stick(pad, "left"));
    CHECK(gpx_pad_axis(pad, "leftx") != 0.0, "the raw axis still reads");
    stick_at(pad, 1.0, 0.0);
    CHECK(strcmp(gpx_pad_stick(pad, "left"), "1,0") == 0, "full right: %s", gpx_pad_stick(pad, "left"));
    CHECK(strcmp(gpx_pad_stick(pad, "RIGHT"), "0,1") == 0, "the right stick is the other pair: %s", gpx_pad_stick(pad, "right"));
    stick_at(pad, 0.575, 0.0);                      /* (0.575 - 0.15) / 0.85 = 0.5 */
    CHECK(parse(keep(gpx_pad_stick(pad, "left")), v, 4) == 2 && near(v[0], 0.5, 0.001) && v[1] == 0.0,
          "rescaled from the zone's edge: %s", gpx_pad_stick(pad, "left"));
    stick_at(pad, -1.0, -1.0);                      /* a corner: longer than 1, cut to 1 */
    CHECK(parse(keep(gpx_pad_stick(pad, "left")), v, 4) == 2 && near(v[0], -0.7071, 0.001) && near(v[1], -0.7071, 0.001),
          "a corner is a unit diagonal: %s", gpx_pad_stick(pad, "left"));
    stick_at(pad, 0.12, 0.12);                      /* 0.17 from centre: outside a ROUND zone of 0.15 */
    CHECK(parse(keep(gpx_pad_stick(pad, "left")), v, 4) == 2 && v[0] > 0.0 && v[0] < 0.05 && near(v[0], v[1], 1e-9),
          "the zone is round: %s", gpx_pad_stick(pad, "left"));

    gpx_set_dead_zone(0.0);
    CHECK(gpx_dead_zone() == 0.0 && gpx_last_error()[0] == 0, "no dead zone");
    stick_at(pad, 0.1, 0.0);
    CHECK(parse(keep(gpx_pad_stick(pad, "left")), v, 4) == 2 && near(v[0], 0.1, 0.001), "raw with no zone: %s", gpx_pad_stick(pad, "left"));
    gpx_set_dead_zone(0.9);
    CHECK(gpx_dead_zone() == 0.9, "the widest zone");
    stick_at(pad, 0.89, 0.0);
    CHECK(strcmp(gpx_pad_stick(pad, "left"), "0,0") == 0, "inside the widest zone");
    gpx_set_dead_zone(0.91);
    CHECK(gpx_dead_zone() == 0.9 && strstr(gpx_last_error(), "dead zone"), "over 0.9 is refused: %s", gpx_last_error());
    gpx_set_dead_zone(-0.1);
    gpx_set_dead_zone(NAN);
    gpx_set_dead_zone(INFINITY);
    CHECK(gpx_dead_zone() == 0.9, "negative, not-a-number and infinity are refused");
    gpx_set_dead_zone(0.15);

    CHECK(gpx_pad_stick(pad, "middle")[0] == 0 && strstr(gpx_last_error(), "left"), "a stick is left or right: %s", gpx_last_error());
    CHECK(gpx_pad_stick(pad, NULL)[0] == 0 && gpx_pad_stick(pad, "")[0] == 0, "NULL and empty sides");
    stick_at(pad, 0.0, 0.0);
}

static void test_axis_events(int pad)
{
    const char *events;
    char want[64];
    CHECK(gpx_axis_events() == 0.0, "axis events start off");
    /* Moved while events are off, then switched on: the step is measured
     * from where the stick IS. (The baseline once stayed at the value the
     * pad was opened with, so this return to centre said nothing.) */
    gpx_virtual_set_axis(pad, "leftx", 1.0);
    CHECK(gpx_poll() == 0, "no axis event while they are off");
    gpx_set_axis_events(0.1);
    gpx_virtual_set_axis(pad, "leftx", 0.0);
    CHECK(gpx_poll() == 1, "back to centre after switching on is one event (%d)", gpx_event_count());
    snprintf(want, sizeof(want), "axis,%d,leftx,0", pad);
    CHECK(strcmp(keep(gpx_events()), want) == 0, "and it reads 0");
    gpx_set_axis_events(0);
    gpx_set_axis_events(0.1);
    CHECK(near(gpx_axis_events(), 0.1, 0.0001) && gpx_last_error()[0] == 0, "step 0.1 reads %g", gpx_axis_events());
    gpx_virtual_set_axis(pad, "leftx", 0.5);
    CHECK(gpx_poll() == 1, "a move of half the travel is one event (%d)", gpx_event_count());
    events = keep(gpx_events());
    snprintf(want, sizeof(want), "axis,%d,leftx,0.5", pad);
    CHECK(strcmp(events, want) == 0, "event: %s", events);
    gpx_virtual_set_axis(pad, "leftx", 0.55);
    CHECK(gpx_poll() == 0, "a move under the step is no event");
    gpx_virtual_set_axis(pad, "leftx", 0.61);
    CHECK(gpx_poll() == 1, "the step is measured from the last REPORT");
    (void)gpx_events();
    gpx_virtual_set_axis(pad, "leftx", 0.02);
    CHECK(gpx_poll() == 1, "a big move back");
    (void)gpx_events();
    gpx_virtual_set_axis(pad, "leftx", 0.0);
    CHECK(gpx_poll() == 1, "coming to rest is always reported, however small the move");
    snprintf(want, sizeof(want), "axis,%d,leftx,0", pad);
    CHECK(strcmp(keep(gpx_events()), want) == 0, "the rest event");
    gpx_virtual_set_axis(pad, "righttrigger", 1.0);
    CHECK(gpx_poll() == 1, "a trigger");
    snprintf(want, sizeof(want), "axis,%d,righttrigger,1", pad);
    CHECK(strcmp(keep(gpx_events()), want) == 0, "the trigger event");
    gpx_virtual_set_axis(pad, "righttrigger", 0.0);
    (void)gpx_poll();
    (void)gpx_events();

    gpx_set_axis_events(0.001);
    CHECK(near(gpx_axis_events(), 0.1, 0.0001) && strstr(gpx_last_error(), "step"), "under 0.01 is refused: %s", gpx_last_error());
    gpx_set_axis_events(1.5);
    gpx_set_axis_events(-0.5);
    gpx_set_axis_events(NAN);
    CHECK(near(gpx_axis_events(), 0.1, 0.0001), "over 1, negative and not-a-number are refused");
    gpx_set_axis_events(1.0);
    CHECK(gpx_axis_events() == 1.0, "a step of the whole travel");
    gpx_set_axis_events(0.0);
    CHECK(gpx_axis_events() == 0.0, "off again");
    gpx_virtual_set_axis(pad, "leftx", 1.0);
    CHECK(gpx_poll() == 0, "and silent");
    gpx_virtual_set_axis(pad, "leftx", 0.0);
    (void)gpx_poll();
}

static void test_rumble_and_light(int pad)
{
    CHECK(gpx_pad_has_rumble(pad) == 1 && gpx_pad_has_trigger_rumble(pad) == 1, "a virtual pad reports both rumbles");
    CHECK(strcmp(gpx_virtual_rumble(pad), "0,0,0,0") == 0, "quiet to begin with: %s", gpx_virtual_rumble(pad));
    CHECK(gpx_pad_rumble(pad, 0.5, 1.0, 500) == 1, "rumble: %s", gpx_last_error());
    {
        double v[4];
        CHECK(parse(keep(gpx_virtual_rumble(pad)), v, 4) == 4 && near(v[0], 0.5, 0.001) && v[1] == 1.0 && v[2] == 0.0,
              "the pad was told: %s", gpx_virtual_rumble(pad));
    }
    CHECK(gpx_pad_rumble(pad, 0.0, 0.0, 0) == 1 && strncmp(gpx_virtual_rumble(pad), "0,0,", 4) == 0,
          "strengths of 0 stop it: %s", gpx_virtual_rumble(pad));
    CHECK(gpx_pad_rumble(pad, 1.1, 0.0, 10) == 0 && gpx_pad_rumble(pad, 0.0, -0.1, 10) == 0
          && gpx_pad_rumble(pad, NAN, 0.0, 10) == 0, "a strength outside 0 to 1 is refused");
    CHECK(gpx_pad_rumble(pad, 0.5, 0.5, -1) == 0 && gpx_pad_rumble(pad, 0.5, 0.5, 60001) == 0
          && strstr(gpx_last_error(), "60000"), "a time outside 0 to 60000 is refused: %s", gpx_last_error());
    CHECK(strncmp(gpx_virtual_rumble(pad), "0,0,", 4) == 0, "a refused rumble reached nothing");

    CHECK(gpx_pad_rumble_triggers(pad, 0.25, 0.75, 200) == 1, "trigger rumble: %s", gpx_last_error());
    {
        double v[4];
        CHECK(parse(keep(gpx_virtual_rumble(pad)), v, 4) == 4 && near(v[2], 0.25, 0.001) && near(v[3], 0.75, 0.001),
              "the triggers were told: %s", gpx_virtual_rumble(pad));
    }
    CHECK(gpx_pad_rumble_triggers(pad, 0.0, 0.0, 0) == 1, "triggers stopped");
    CHECK(gpx_pad_rumble_triggers(pad, 2.0, 0.0, 10) == 0 && gpx_pad_rumble_triggers(pad, 0.0, 0.0, -5) == 0,
          "trigger rumble out of range is refused");

    CHECK(gpx_pad_has_led(pad) == 1, "a virtual pad reports a light");
    CHECK(strcmp(gpx_virtual_led(pad), "0,0,0") == 0, "dark to begin with");
    CHECK(gpx_pad_set_led(pad, 10, 128, 255) == 1 && strcmp(gpx_virtual_led(pad), "10,128,255") == 0,
          "the light: %s (%s)", gpx_virtual_led(pad), gpx_last_error());
    CHECK(gpx_pad_set_led(pad, 256, 0, 0) == 0 && gpx_pad_set_led(pad, 0, -1, 0) == 0 && gpx_pad_set_led(pad, 0, 0, 1000) == 0
          && strcmp(gpx_virtual_led(pad), "10,128,255") == 0, "a colour outside 0 to 255 is refused");
}

static void test_mappings(void)
{
    /* A made-up device nobody owns, so adding it changes no real pad. */
    static const char k_map[] = "03000000deadbeef0000cafe00000000,Smoke Mapping,a:b0,b:b1,leftx:a0,lefty:a1,";
    static const char k_file[] = "gamepadxt-smoke-mappings.txt";
    static char huge[9000];
    FILE *f;
    CHECK(gpx_add_mapping(k_map) == 1, "a new mapping: %s", gpx_last_error());
    CHECK(gpx_add_mapping(k_map) == 0, "the same mapping again replaces");
    CHECK(gpx_add_mapping("") == -1 && gpx_add_mapping(NULL) == -1, "empty and NULL are refused");
    CHECK(gpx_add_mapping("not a mapping") == -1 && gpx_last_error()[0] != 0, "a line that is no mapping: %s", gpx_last_error());
    memset(huge, 'x', sizeof(huge) - 1);
    CHECK(gpx_add_mapping(huge) == -1 && strstr(gpx_last_error(), "8192"), "a mapping over 8192 bytes: %s", gpx_last_error());

    CHECK(gpx_add_mappings_from_file("no-such-directory/no-such-file.txt") == -1 && gpx_last_error()[0] != 0,
          "a file that is not there: %s", gpx_last_error());
    CHECK(gpx_add_mappings_from_file("") == -1 && gpx_add_mappings_from_file(NULL) == -1, "empty and NULL paths");
    CHECK(gpx_add_mappings_from_file(huge) == -1, "a path over 4096 bytes");
    f = fopen(k_file, "w");
    CHECK(f != NULL, "the test can write %s here", k_file);
    if (f) {
        /* A file's lines are per platform, as gamecontrollerdb.txt's are: SDL
         * takes the ones that name the platform it runs on and skips the
         * rest, a line that names none included. Two for each platform a
         * build of this library exists for, so exactly two are taken. */
        static const char *const k_platforms[] = { "Linux", "Windows", "Mac OS X", "Emscripten" };
        int i;
        fputs("# a comment line, as gamecontrollerdb.txt has\n", f);
        fputs("03000000deadbeef0000cafe000000ff,Smoke No Platform,a:b0,b:b1,\n", f);
        for (i = 0; i < 4; i++) {
            fprintf(f, "03000000deadbeef0000cafe0000%02x01,Smoke File One,a:b0,b:b1,platform:%s,\n", i, k_platforms[i]);
            fprintf(f, "03000000deadbeef0000cafe0000%02x02,Smoke File Two,a:b1,b:b0,platform:%s,\n", i, k_platforms[i]);
        }
        fclose(f);
        CHECK(gpx_add_mappings_from_file(k_file) == 2, "two mappings from a file (%s)", gpx_last_error());
        CHECK(gpx_add_mappings_from_file(k_file) == 0, "and none of them new the second time");
        remove(k_file);
    }
}

/* The decimal point is "." whatever the process locale says. */
static void test_locale(int pad)
{
    static const char *const k_locales[] = { "de_DE.UTF-8", "de_DE", "fr_FR.UTF-8", "German_Germany", "de-DE" };
    const char *got = NULL;
    double v[8];
    size_t i;
    for (i = 0; i < sizeof(k_locales) / sizeof(k_locales[0]) && !got; i++) got = setlocale(LC_ALL, k_locales[i]);
    gpx_virtual_set_axis(pad, "leftx", 0.5);
    gpx_virtual_set_axis(pad, "lefttrigger", 0.25);
    (void)gpx_poll();
    CHECK(parse(keep(gpx_pad_axes(pad)), v, 8) == 6 && near(v[0], 0.5, 0.0002) && near(v[4], 0.25, 0.0002),
          "axes under locale %s: %s", got ? got : "(none of the comma locales is installed)", gpx_pad_axes(pad));
    CHECK(parse(keep(gpx_pad_stick(pad, "left")), v, 8) == 2, "stick under that locale: %s", gpx_pad_stick(pad, "left"));
    CHECK(gpx_pad_rumble(pad, 0.5, 0.5, 10) == 1 && parse(keep(gpx_virtual_rumble(pad)), v, 8) == 4,
          "rumble text under that locale: %s", gpx_virtual_rumble(pad));
    (void)gpx_pad_rumble(pad, 0.0, 0.0, 0);
    setlocale(LC_ALL, "C");
    gpx_virtual_set_axis(pad, "leftx", 0.0);
    gpx_virtual_set_axis(pad, "lefttrigger", 0.0);
    (void)gpx_poll();
    (void)gpx_events();
}

/* A handle that no longer names a pad is harmless, and never comes back. */
static void test_stale(int base)
{
    int pad = gpx_virtual_attach("Stale");
    int other, i, reused = 0;
    char want[64];
    (void)gpx_events();
    gpx_virtual_detach(pad);
    snprintf(want, sizeof(want), "disconnected,%d", pad);
    CHECK(has_line(keep(gpx_events()), want), "the detach is an event");
    CHECK(gpx_pad_count() == base, "the count is back to %d (%d)", base, gpx_pad_count());
    CHECK(gpx_poll() == 0, "SDL's own removal of a pad we closed is not a second event");

    CHECK(gpx_pad_is_connected(pad) == 0 && gpx_pad_is_virtual(pad) == 0, "not connected, not virtual");
    CHECK(strstr(gpx_last_error(), "no such pad"), "the reason: %s", gpx_last_error());
    CHECK(gpx_pad_name(pad)[0] == 0 && gpx_pad_type(pad)[0] == 0 && gpx_pad_guid(pad)[0] == 0
          && gpx_pad_mapping(pad)[0] == 0 && gpx_pad_power(pad)[0] == 0, "text getters are empty");
    CHECK(gpx_pad_vendor(pad) == 0 && gpx_pad_product(pad) == 0 && gpx_pad_player(pad) == -1
          && gpx_pad_battery(pad) == -1, "number getters are 0 or -1");
    CHECK(gpx_pad_button(pad, "south") == 0 && gpx_pad_has_button(pad, "south") == 0 && gpx_pad_buttons(pad)[0] == 0
          && gpx_pad_button_label(pad, "south")[0] == 0, "buttons");
    CHECK(gpx_pad_axis(pad, "leftx") == 0.0 && gpx_pad_has_axis(pad, "leftx") == 0 && gpx_pad_axes(pad)[0] == 0
          && gpx_pad_stick(pad, "left")[0] == 0, "axes");
    CHECK(gpx_pad_has_rumble(pad) == 0 && gpx_pad_rumble(pad, 1, 1, 100) == 0 && gpx_pad_has_trigger_rumble(pad) == 0
          && gpx_pad_rumble_triggers(pad, 1, 1, 100) == 0 && gpx_pad_has_led(pad) == 0
          && gpx_pad_set_led(pad, 1, 2, 3) == 0 && gpx_pad_set_player(pad, 1) == 0, "actions do nothing");
    CHECK(gpx_virtual_set_button(pad, "south", 1) == 0 && gpx_virtual_set_axis(pad, "leftx", 1) == 0
          && gpx_virtual_rumble(pad)[0] == 0 && gpx_virtual_led(pad)[0] == 0, "virtual calls do nothing");
    gpx_virtual_detach(pad);                        /* twice */
    gpx_virtual_detach(0);
    gpx_virtual_detach(-1);
    gpx_virtual_detach(2147483647);
    CHECK(gpx_pad_count() == base && gpx_event_count() == 0, "detaching nothing changes nothing");

    /* the slot is reused; the old handle is not */
    other = gpx_virtual_attach("Reuser");
    CHECK(other > 0 && other != pad, "a new pad gets a new handle (%d, was %d)", other, pad);
    CHECK((other & 0xFF) == (pad & 0xFF), "in the old one's slot");
    CHECK(gpx_pad_is_connected(pad) == 0 && gpx_pad_name(pad)[0] == 0, "and the old handle does not name the newcomer");
    gpx_virtual_detach(other);
    for (i = 0; i < 300; i++) {
        int h = gpx_virtual_attach("Churn");
        if (h == pad || h == other || h <= 0) reused++;
        gpx_virtual_detach(h);
        if (i % 50 == 0) { (void)gpx_poll(); (void)gpx_events(); }
    }
    CHECK(reused == 0, "300 pads through one slot never repeat a handle");
    (void)gpx_poll();
    (void)gpx_events();
    CHECK(gpx_pad_count() == base, "all gone");
}

/* 64 pads at once, and the 65th refused. */
static void test_capacity(int base)
{
    static int pads[80];
    int n = 0, i, h;
    while (n < 80 && (h = gpx_virtual_attach("Many")) > 0) pads[n++] = h;
    CHECK(n == 64 - base, "%d virtual pads beside %d others fill the table", n, base);
    CHECK(strstr(gpx_last_error(), "64"), "the refusal says why: %s", gpx_last_error());
    CHECK(gpx_pad_count() == 64, "64 pads");
    CHECK(count_lines(keep(gpx_events())) >= n, "each one announced");
    for (i = 0; i < n; i++) gpx_virtual_set_button(pads[i], "south", 1);
    CHECK(gpx_poll() == n, "every one of them is read (%d events)", gpx_event_count());
    (void)gpx_events();
    for (i = 0; i < n; i++) CHECK(gpx_pad_button(pads[i], "south") == 1, "pad %d holds south", i);
    for (i = 0; i < n; i++) gpx_virtual_detach(pads[i]);
    (void)gpx_poll();
    (void)gpx_events();
    CHECK(gpx_pad_count() == base, "all detached");
    h = gpx_virtual_attach("After");
    CHECK(h > 0, "and there is room again");
    gpx_virtual_detach(h);
    (void)gpx_events();
}

/* A script that polls and never reads: the queue is bounded, the newest
 * events are kept and the loss is counted. */
static void test_overflow(int pad)
{
    int before = gpx_dropped_events();
    int i, n;
    const char *events, *last;
    (void)gpx_events();
    for (i = 0; i < 2500; i++) {
        gpx_virtual_set_button(pad, "east", 1);
        (void)gpx_poll();
        gpx_virtual_set_button(pad, "east", 0);
        (void)gpx_poll();
    }
    gpx_virtual_set_button(pad, "start", 1);
    (void)gpx_poll();
    CHECK(gpx_event_count() == 4096, "the queue holds 4096 (%d)", gpx_event_count());
    CHECK(gpx_dropped_events() - before == 5001 - 4096, "and counts the %d it let go (%d)", 5001 - 4096,
          gpx_dropped_events() - before);
    events = gpx_events();
    n = count_lines(events);
    last = strrchr(events, '\n');
    CHECK(n == 4096, "4096 lines came back (%d)", n);
    CHECK(last && strcmp(last + 1, line_of("button,%d,%s,%s", pad, "start", "down")) == 0, "the newest is the last line");
    CHECK(gpx_event_count() == 0, "and the queue is empty");
    gpx_virtual_set_button(pad, "start", 0);
    (void)gpx_poll();
    (void)gpx_events();
}

/* The last stop closes everything. */
static void test_stop(int pad)
{
    int second = gpx_virtual_attach("Second");
    CHECK(second > 0, "a second pad");
    gpx_virtual_set_button(pad, "south", 1);
    (void)gpx_poll();
    gpx_stop();
    CHECK(gpx_is_started() == 0, "stopped");
    CHECK(gpx_pad_count() == 0 && gpx_pads()[0] == 0 && gpx_event_count() == 0, "no pads, no events");
    CHECK(gpx_pad_is_connected(pad) == 0 && gpx_pad_is_connected(second) == 0 && gpx_pad_button(pad, "south") == 0,
          "every handle is stale");
    CHECK(gpx_start() == 1, "start again: %s", gpx_last_error());
    CHECK(gpx_pad_is_connected(pad) == 0 && gpx_pad_name(second)[0] == 0, "and they stay stale after a restart");
    second = gpx_virtual_attach("Third");
    CHECK(second > 0 && second != pad && gpx_pad_button(second, "south") == 0, "a pad of the new session starts clean");
    gpx_stop();
    CHECK(gpx_is_started() == 0, "stopped for good");
}

int main(void)
{
    int base, pad;
    test_library();
    test_before_start();
    test_counting();
    base = gpx_pad_count();                         /* real pads on this machine, if any */
    pad = test_attach(base);
    test_buttons(pad);
    test_axes(pad);
    test_stick(pad);
    test_axis_events(pad);
    test_rumble_and_light(pad);
    test_mappings();
    test_locale(pad);
    test_stale(base + 1);
    test_capacity(base + 1);
    test_overflow(pad);
    test_stop(pad);
    /* In a build with SDL's assertions on (the sanitizer lane), nothing above
     * may have tripped one: every refusal is meant to stop in the shim. In a
     * release build they are compiled out and this reads 0 by construction. */
    CHECK(gpx_assert_count() == 0, "%d SDL assertion(s) failed", gpx_assert_count());
    printf("gamepadxt smoke test: %d passed, %d failed\n", s_pass, s_fail);
    return s_fail == 0 ? 0 : 1;
}
