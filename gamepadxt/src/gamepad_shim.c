/*
 * gamepad_shim.c
 * ----------------------------------------------------------------------------
 * The C shim of gamepadxt: SDL3's gamepad subsystem (zlib licence) behind a
 * flat C ABI that the xTalk Builder (LCB) foreign function interface can
 * call, so OpenXTalk and LiveCode-compatible engines can read game
 * controllers: Xbox, PlayStation, Switch and the many pads SDL's mapping
 * database knows, all with ONE button layout. box3dxt/src/box3d_shim.c is
 * this file's ancestor and its conventions are kept:
 *
 *   - A connected pad crosses as a positive 32-bit int (0 = invalid) from a
 *     shim-side table. Handles are generation-tagged: the handle of a pad
 *     that was unplugged stays dead after its slot is given to another pad.
 *   - Every real crosses as `double`, every boolean as `int`.
 *   - A button or an axis is named by TEXT ("south", "leftx"): a script
 *     reads better with names than with numbers, and a name this shim does
 *     not know is simply a refused call.
 *   - A result of several values (the six axes, the pressed buttons, the
 *     pending events) crosses as TEXT, comma-separated items (events: one a
 *     line). Numbers are written with a "." whatever the process locale says.
 *     The pointer returned is to a buffer this file owns; the binding copies
 *     it at once (as a Pointer through its textOf(), never as ZStringNative:
 *     the engine FREES a returned C string) and script is single-threaded.
 *
 * Pump or nothing (suite rule 1). SDL reads devices only inside gpx_poll(),
 * which the script calls from a timer. SDL's own threads (device discovery on
 * Windows, a HID reader for some pads) never reach this file: it registers no
 * event watch, and the only callbacks it hands SDL are the log and assert
 * hooks (which count and return) and the virtual pad's rumble and light
 * hooks, which SDL calls inside our own calls. Events are copied out of
 * SDL's queue by gpx_poll() and read by gpx_events().
 *
 * A guest in someone else's process. SDL is written to own an application;
 * here it is a library inside an engine that owns the window, the message
 * loop, the signals and the console. So before SDL starts: no signal
 * handlers, no change to the system timer period, no log output, no assert
 * dialog. This file never calls SDL_PumpEvents (on Windows that would run the
 * engine's message loop from inside a script call): it calls
 * SDL_UpdateGamepads, which reads devices and nothing else. SDL's video,
 * audio and every other subsystem are compiled out (CMakeLists.txt).
 *
 * Safety. Every export validates first: a stale or never-created handle is a
 * harmless no-op (getters return 0 or empty), a NULL or unknown name, a
 * number that is not finite or a call made before gpx_start() refuses the
 * call, and gpx_last_error() says why.
 *
 * Build: compiled with SDL3 into ONE shared library named "gamepadxt"
 * (gamepadxt.so / gamepadxt.dll / gamepadxt.dylib), or for the web into a
 * static archive. See CMakeLists.txt.
 * ----------------------------------------------------------------------------
 */

#include <SDL3/SDL.h>

#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
    #define LC_API __declspec(dllexport)
#else
    #define LC_API __attribute__((visibility("default")))
#endif

/* Bump when the exported ABI changes; src/gamepadxt.lcb's checkABI() names
 * the same number and refuses a library that answers another. */
#define GPX_ABI_VERSION 1

/* ------------------------------------------------------------------ */
/* Limits. Each is a stated bound, not a guess at what SDL tolerates.  */
/* ------------------------------------------------------------------ */
#define GPX_MAX_PADS        64      /* pads open at once                */
#define GPX_MAX_EVENTS      4096    /* events held between two drains   */
#define GPX_MAX_RUMBLE_MS   60000   /* one rumble call, at most a minute */
#define GPX_MAX_MAPPING     8192    /* bytes of one mapping line        */
#define GPX_MAX_PATH        4096    /* bytes of a mappings file path    */
#define GPX_MAX_NAME        64      /* bytes of a virtual pad's name    */
#define GPX_NUM_BUTTONS     26      /* == SDL_GAMEPAD_BUTTON_COUNT      */
#define GPX_NUM_AXES        6       /* == SDL_GAMEPAD_AXIS_COUNT        */

SDL_COMPILE_TIME_ASSERT(gpx_buttons, GPX_NUM_BUTTONS == SDL_GAMEPAD_BUTTON_COUNT);
SDL_COMPILE_TIME_ASSERT(gpx_axes, GPX_NUM_AXES == SDL_GAMEPAD_AXIS_COUNT);

/* ------------------------------------------------------------------ */
/* Names. The shim's own, in SDL's enum order, so an index IS the SDL  */
/* value. Buttons are named by POSITION ("south" is the bottom face    */
/* button whatever is printed on it): SDL's own mapping names call     */
/* that button "a", which is wrong on a Nintendo pad, where A is on    */
/* the right. gpx_pad_button_label() gives the printed letter.         */
/* ------------------------------------------------------------------ */
static const char *const k_buttons[GPX_NUM_BUTTONS] = {
    "south", "east", "west", "north", "back", "guide", "start",
    "leftstick", "rightstick", "leftshoulder", "rightshoulder",
    "dpup", "dpdown", "dpleft", "dpright", "misc1",
    "rightpaddle1", "leftpaddle1", "rightpaddle2", "leftpaddle2",
    "touchpad", "misc2", "misc3", "misc4", "misc5", "misc6"
};
static const char *const k_axes[GPX_NUM_AXES] = {
    "leftx", "lefty", "rightx", "righty", "lefttrigger", "righttrigger"
};
/* "An index IS the SDL value" is a claim about SDL's header, and no test on
 * virtual pads could see it break (they would set and read the same wrong
 * position). So the compiler holds it: an SDL bump that reorders or grows
 * either enum fails HERE, not on somebody's controller. */
#define GPX_STATIC_ASSERT(name, cond) typedef char gpx_assert_##name[(cond) ? 1 : -1]
GPX_STATIC_ASSERT(button_count, SDL_GAMEPAD_BUTTON_COUNT == GPX_NUM_BUTTONS);
GPX_STATIC_ASSERT(axis_count, SDL_GAMEPAD_AXIS_COUNT == GPX_NUM_AXES);
GPX_STATIC_ASSERT(south, SDL_GAMEPAD_BUTTON_SOUTH == 0 && SDL_GAMEPAD_BUTTON_NORTH == 3);
GPX_STATIC_ASSERT(middle, SDL_GAMEPAD_BUTTON_BACK == 4 && SDL_GAMEPAD_BUTTON_GUIDE == 5 && SDL_GAMEPAD_BUTTON_START == 6);
GPX_STATIC_ASSERT(sticks, SDL_GAMEPAD_BUTTON_LEFT_STICK == 7 && SDL_GAMEPAD_BUTTON_RIGHT_SHOULDER == 10);
GPX_STATIC_ASSERT(dpad, SDL_GAMEPAD_BUTTON_DPAD_UP == 11 && SDL_GAMEPAD_BUTTON_DPAD_RIGHT == 14);
GPX_STATIC_ASSERT(paddles, SDL_GAMEPAD_BUTTON_MISC1 == 15 && SDL_GAMEPAD_BUTTON_RIGHT_PADDLE1 == 16
                           && SDL_GAMEPAD_BUTTON_LEFT_PADDLE1 == 17 && SDL_GAMEPAD_BUTTON_LEFT_PADDLE2 == 19);
GPX_STATIC_ASSERT(tail, SDL_GAMEPAD_BUTTON_TOUCHPAD == 20 && SDL_GAMEPAD_BUTTON_MISC6 == 25);
GPX_STATIC_ASSERT(axes, SDL_GAMEPAD_AXIS_LEFTX == 0 && SDL_GAMEPAD_AXIS_RIGHTY == 3
                        && SDL_GAMEPAD_AXIS_LEFT_TRIGGER == 4 && SDL_GAMEPAD_AXIS_RIGHT_TRIGGER == 5);
/* The Xbox letters, accepted on the way IN only, as the positions they have
 * on an Xbox pad. Nothing this shim returns ever uses them. */
static const struct { const char *alias; int button; } k_aliases[] = {
    { "a", SDL_GAMEPAD_BUTTON_SOUTH }, { "b", SDL_GAMEPAD_BUTTON_EAST },
    { "x", SDL_GAMEPAD_BUTTON_WEST },  { "y", SDL_GAMEPAD_BUTTON_NORTH },
};

/* ------------------------------------------------------------------ */
/* State.                                                              */
/* ------------------------------------------------------------------ */
typedef struct {
    int           used;
    int           retired;      /* its generation ran out: never reused  */
    unsigned      gen;          /* 1 .. GPX_GEN_MAX                      */
    SDL_Gamepad  *pad;
    SDL_JoystickID id;
    int           isVirtual;
    /* what a virtual pad was last told (the rumble and light hooks) */
    int           vLow, vHigh, vLeft, vRight;      /* 0..65535 */
    int           vRed, vGreen, vBlue;             /* 0..255   */
    /* one bit per button a virtual pad was told about since SDL last read
     * it (see gpx_virtual_set_button) */
    unsigned      vUnread;
    /* the axis values last put in the event queue, for gpx_set_axis_events */
    int           sent[GPX_NUM_AXES];
} Pad;

/* A handle packs the generation above the slot number (slot + 1): 8 bits of
 * slot, 22 of generation, so it is positive and fits the FFI's 32-bit int. */
#define GPX_SLOT_BITS 8
#define GPX_SLOT_MASK 0xFF
#define GPX_GEN_MAX   0x3FFFFF

enum { EV_CONNECTED, EV_DISCONNECTED, EV_BUTTON, EV_AXIS };
typedef struct { int kind; int handle; int code; int value; } Event;

static Pad    s_pads[GPX_MAX_PADS];
static int    s_refs = 0;               /* gpx_start() calls not yet stopped */
static int    s_asserts = 0;
static int    s_dropped = 0;
static double s_deadZone = 0.15;
static int    s_axisStep = 0;           /* 0 = no axis events; else 1..32767 */
static Event  s_events[GPX_MAX_EVENTS];
static int    s_eventHead = 0;          /* index of the oldest */
static int    s_eventCount = 0;
static char   s_error[256] = "";
static char   s_small[512];             /* short text results */
static char  *s_big = NULL;             /* long text results (events, mappings) */
static size_t s_bigCap = 0;

static void set_error(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(s_error, sizeof(s_error), fmt, ap);
    va_end(ap);
}

static void clear_error(void) { s_error[0] = '\0'; }

/* SDL's message for the call that just failed, behind our own words. */
static void set_sdl_error(const char *what)
{
    const char *why = SDL_GetError();
    set_error("%s: %s", what, (why && why[0]) ? why : "SDL gave no reason");
}

/* ---- handles ---- */
static int handle_of(int slot)
{
    return (int)((s_pads[slot].gen << GPX_SLOT_BITS) | (unsigned)(slot + 1));
}

/* handle -> slot, or -1 if stale / never created */
static int slot_of(int h)
{
    int slot;
    unsigned gen;
    if (h <= 0) return -1;
    slot = (h & GPX_SLOT_MASK) - 1;
    gen = (unsigned)h >> GPX_SLOT_BITS;
    if (slot < 0 || slot >= GPX_MAX_PADS) return -1;
    if (!s_pads[slot].used || s_pads[slot].gen != gen) return -1;
    return slot;
}

/* A slot for a new pad, or -1 when all are taken. The slot's generation was
 * advanced when it was last freed, so the handle is one never handed out. */
static int slot_take(void)
{
    int i;
    for (i = 0; i < GPX_MAX_PADS; i++) {
        Pad *p = &s_pads[i];
        if (!p->used && !p->retired) {
            unsigned gen = p->gen ? p->gen : 1;
            memset(p, 0, sizeof(*p));
            p->gen = gen;
            p->used = 1;
            return i;
        }
    }
    return -1;
}

static void slot_free(int slot)
{
    Pad *p = &s_pads[slot];
    p->used = 0;
    p->pad = NULL;
    p->id = 0;
    p->isVirtual = 0;
    if (p->gen >= GPX_GEN_MAX) p->retired = 1;   /* never wrap: a stale handle must stay dead */
    else p->gen++;
}

static int slot_of_id(SDL_JoystickID id)
{
    int i;
    for (i = 0; i < GPX_MAX_PADS; i++) {
        if (s_pads[i].used && s_pads[i].id == id) return i;
    }
    return -1;
}

/* The pad behind a handle, or NULL with the reason recorded. */
static Pad *pad_of(int h)
{
    int slot;
    if (s_refs <= 0) { set_error("gamepadxt is not started"); return NULL; }
    slot = slot_of(h);
    if (slot < 0) { set_error("no such pad (it was disconnected, or the handle was never valid)"); return NULL; }
    clear_error();
    return &s_pads[slot];
}

/* ---- names ---- */
static int same_word(const char *a, const char *b)
{
    for (; *a && *b; a++, b++) {
        char ca = *a, cb = *b;
        if (ca >= 'A' && ca <= 'Z') ca = (char)(ca - 'A' + 'a');
        if (cb >= 'A' && cb <= 'Z') cb = (char)(cb - 'A' + 'a');
        if (ca != cb) return 0;
    }
    return *a == '\0' && *b == '\0';
}

static int button_of(const char *name)
{
    int i;
    if (!name) return -1;
    for (i = 0; i < GPX_NUM_BUTTONS; i++) {
        if (same_word(name, k_buttons[i])) return i;
    }
    for (i = 0; i < (int)(sizeof(k_aliases) / sizeof(k_aliases[0])); i++) {
        if (same_word(name, k_aliases[i].alias)) return k_aliases[i].button;
    }
    return -1;
}

static int axis_of(const char *name)
{
    int i;
    if (!name) return -1;
    for (i = 0; i < GPX_NUM_AXES; i++) {
        if (same_word(name, k_axes[i])) return i;
    }
    return -1;
}

static int is_trigger(int axis)
{
    return axis == SDL_GAMEPAD_AXIS_LEFT_TRIGGER || axis == SDL_GAMEPAD_AXIS_RIGHT_TRIGGER;
}

/* SDL's 16-bit axis as -1..1 (a stick) or 0..1 (a trigger). -32768 is -1. */
static double unit_of(int raw)
{
    double v = (double)raw / 32767.0;
    if (v < -1.0) v = -1.0;
    if (v > 1.0) v = 1.0;
    return v;
}

/* ---- text ---- */

/* Appends v to out with at most four decimals and no trailing zeros, with a
 * "." in every locale (printf's %f follows the locale, and an engine built on
 * GTK sets one: "0,5" would be two items). Returns the characters written. */
static int put_number(char *out, size_t cap, double v)
{
    long scaled;
    int n = 0;
    char digits[8];
    if (!(v == v)) v = 0.0;
    if (v > 1000000.0) v = 1000000.0;
    if (v < -1000000.0) v = -1000000.0;
    scaled = (long)(v < 0 ? -(v * 10000.0 - 0.5) : (v * 10000.0 + 0.5));
    if (cap < 24) return 0;
    if (v < 0 && scaled != 0) out[n++] = '-';
    n += snprintf(out + n, cap - (size_t)n, "%ld", scaled / 10000);
    snprintf(digits, sizeof(digits), "%04ld", scaled % 10000);
    if (scaled % 10000 != 0) {
        int last = 3;
        int i;
        while (last > 0 && digits[last] == '0') last--;
        out[n++] = '.';
        for (i = 0; i <= last; i++) out[n++] = digits[i];
    }
    out[n] = '\0';
    return n;
}

/* Room for `need` bytes in the long-result buffer, or 0. */
static int big_reserve(size_t need)
{
    char *nb;
    size_t cap;
    if (need <= s_bigCap) return 1;
    cap = s_bigCap ? s_bigCap : 1024;
    while (cap < need) cap *= 2;
    nb = (char *)realloc(s_big, cap);
    if (!nb) return 0;
    s_big = nb;
    s_bigCap = cap;
    return 1;
}

/* A copy of text in the long-result buffer ("" if there is no memory). */
static const char *big_text(const char *text)
{
    size_t n = text ? strlen(text) : 0;
    if (!big_reserve(n + 1)) return "";
    memcpy(s_big, text ? text : "", n);
    s_big[n] = '\0';
    return s_big;
}

static const char *small_text(const char *text)
{
    snprintf(s_small, sizeof(s_small), "%s", text ? text : "");
    return s_small;
}

/* ---- events ---- */
static void push_event(int kind, int handle, int code, int value)
{
    Event *e;
    if (s_eventCount == GPX_MAX_EVENTS) {
        /* A script that polls and never drains: the OLDEST goes, so what is
         * read is recent, and the loss is counted (gpx_dropped_events). */
        s_eventHead = (s_eventHead + 1) % GPX_MAX_EVENTS;
        s_eventCount--;
        s_dropped++;
    }
    e = &s_events[(s_eventHead + s_eventCount) % GPX_MAX_EVENTS];
    e->kind = kind;
    e->handle = handle;
    e->code = code;
    e->value = value;
    s_eventCount++;
}

/* ---- SDL's hooks: count, never print, never stop the host ---- */
static void SDLCALL quiet_log(void *userdata, int category, SDL_LogPriority priority, const char *message)
{
    (void)userdata; (void)category; (void)priority; (void)message;
}

static SDL_AssertState SDLCALL count_assert(const SDL_AssertData *data, void *userdata)
{
    (void)data; (void)userdata;
    s_asserts++;
    return SDL_ASSERTION_IGNORE;
}

/* ---- a virtual pad's hooks: SDL calls them inside our own calls ---- */
static Pad *virtual_of(void *userdata)
{
    int slot = (int)(intptr_t)userdata - 1;
    if (slot < 0 || slot >= GPX_MAX_PADS) return NULL;
    if (!s_pads[slot].used || !s_pads[slot].isVirtual) return NULL;
    return &s_pads[slot];
}

static bool SDLCALL virtual_rumble(void *userdata, Uint16 low, Uint16 high)
{
    Pad *p = virtual_of(userdata);
    if (!p) return false;
    p->vLow = low;
    p->vHigh = high;
    return true;
}

static bool SDLCALL virtual_rumble_triggers(void *userdata, Uint16 left, Uint16 right)
{
    Pad *p = virtual_of(userdata);
    if (!p) return false;
    p->vLeft = left;
    p->vRight = right;
    return true;
}

static bool SDLCALL virtual_led(void *userdata, Uint8 red, Uint8 green, Uint8 blue)
{
    Pad *p = virtual_of(userdata);
    if (!p) return false;
    p->vRed = red;
    p->vGreen = green;
    p->vBlue = blue;
    return true;
}

/* ---- opening and closing ---- */

/* Opens the pad SDL calls `id` into `slot` (already taken) and queues its
 * "connected". Returns the handle, or 0 with the slot given back. */
static int open_into(int slot, SDL_JoystickID id, int isVirtual)
{
    Pad *p = &s_pads[slot];
    int i;
    p->pad = SDL_OpenGamepad(id);
    if (!p->pad) {
        set_sdl_error("could not open the pad");
        slot_free(slot);
        return 0;
    }
    p->id = id;
    p->isVirtual = isVirtual;
    p->vUnread = 0;
    for (i = 0; i < GPX_NUM_AXES; i++) p->sent[i] = 0;
    push_event(EV_CONNECTED, handle_of(slot), 0, 0);
    return handle_of(slot);
}

static void close_slot(int slot, int queue)
{
    Pad *p = &s_pads[slot];
    int handle = handle_of(slot);
    if (p->pad) SDL_CloseGamepad(p->pad);
    p->pad = NULL;
    if (queue) push_event(EV_DISCONNECTED, handle, 0, 0);
    slot_free(slot);
}

/* Empties SDL's queue: pads that came and went, buttons, and (if asked for)
 * axes go into ours; everything else SDL queued is discarded, so its queue
 * never grows inside a process that does not otherwise read it. */
static void drain_sdl(void);

/* Has SDL read every device and hands the shim what happened. The one place
 * SDL_UpdateGamepads is called once started, so that "SDL has now read the
 * virtual pads" is recorded wherever it happens. */
static void read_devices(void)
{
    int i;
    SDL_UpdateGamepads();
    for (i = 0; i < GPX_MAX_PADS; i++) s_pads[i].vUnread = 0;
    drain_sdl();
}

static void drain_sdl(void)
{
    SDL_Event batch[32];
    int n, i, slot;
    while ((n = SDL_PeepEvents(batch, 32, SDL_GETEVENT, SDL_EVENT_FIRST, SDL_EVENT_LAST)) > 0) {
        for (i = 0; i < n; i++) {
            const SDL_Event *e = &batch[i];
            switch (e->type) {
            case SDL_EVENT_GAMEPAD_ADDED:
                if (slot_of_id(e->gdevice.which) >= 0) break;      /* a virtual pad we opened ourselves */
                slot = slot_take();
                if (slot < 0) break;                               /* GPX_MAX_PADS are open */
                (void)open_into(slot, e->gdevice.which, 0);
                break;
            case SDL_EVENT_GAMEPAD_REMOVED:
                slot = slot_of_id(e->gdevice.which);
                if (slot >= 0) close_slot(slot, 1);
                break;
            case SDL_EVENT_GAMEPAD_BUTTON_DOWN:
            case SDL_EVENT_GAMEPAD_BUTTON_UP:
                slot = slot_of_id(e->gbutton.which);
                if (slot >= 0 && e->gbutton.button < GPX_NUM_BUTTONS) {
                    push_event(EV_BUTTON, handle_of(slot), e->gbutton.button, e->gbutton.down ? 1 : 0);
                }
                break;
            case SDL_EVENT_GAMEPAD_AXIS_MOTION:
                slot = slot_of_id(e->gaxis.which);
                if (slot >= 0 && s_axisStep <= 0 && e->gaxis.axis < GPX_NUM_AXES) {
                    /* Off: keep the baseline moving all the same, so that
                     * turning events on later reports movement from where
                     * the stick IS, not from where it was when the pad was
                     * opened (a stick returned to centre said nothing). */
                    s_pads[slot].sent[e->gaxis.axis] = e->gaxis.value;
                } else if (slot >= 0 && e->gaxis.axis < GPX_NUM_AXES) {
                    int now = e->gaxis.value;
                    int was = s_pads[slot].sent[e->gaxis.axis];
                    int moved = now > was ? now - was : was - now;
                    /* Coming to rest at the centre or an end is always
                     * reported, so a script that follows events alone never
                     * holds a stale last step. */
                    int rest = (now == 0 || now >= 32767 || now <= -32767) && now != was;
                    if (moved >= s_axisStep || rest) {
                        s_pads[slot].sent[e->gaxis.axis] = now;
                        push_event(EV_AXIS, handle_of(slot), e->gaxis.axis, now);
                    }
                }
                break;
            default:
                break;
            }
        }
    }
}

/* ================================================================== */
/* The library                                                         */
/* ================================================================== */

LC_API int gpx_abi_version(void) { return GPX_ABI_VERSION; }

/* "SDL 3.4.20": the SDL this library was BUILT from and is running. */
LC_API const char *gpx_library_version(void)
{
    int v = SDL_GetVersion();
    snprintf(s_small, sizeof(s_small), "SDL %d.%d.%d",
             SDL_VERSIONNUM_MAJOR(v), SDL_VERSIONNUM_MINOR(v), SDL_VERSIONNUM_MICRO(v));
    return s_small;
}

/* Why the last call was refused; empty after one that was not. */
LC_API const char *gpx_last_error(void) { return s_error; }

/* The length of a text result, for the binding's textOf(): the engine's
 * string builder wants a byte count and LCB cannot walk a C string. */
LC_API int gpx_text_length(const char *text) { return text ? (int)strlen(text) : 0; }

/* How many of SDL's internal assertions have failed since the library was
 * loaded. Always 0 in a release build (they are compiled out); the tests
 * run a build that has them and fail on any other number. */
LC_API int gpx_assert_count(void) { return s_asserts; }

/* ================================================================== */
/* Starting and stopping                                               */
/* ================================================================== */

/* Starts SDL's gamepad subsystem and opens every pad already connected.
 * COUNTED: each successful start needs its own gpx_stop(), and the library
 * shuts down at the last one, so two stacks in one engine do not stop each
 * other. Returns 1, or 0 with gpx_last_error() set. */
LC_API int gpx_start(void)
{
    if (s_refs > 0) {
        s_refs++;
        clear_error();
        return 1;
    }
    /* Before SDL_Init, all of it: see "A guest in someone else's process". */
    SDL_SetLogOutputFunction(quiet_log, NULL);
    SDL_SetAssertionHandler(count_assert, NULL);
    SDL_SetHint(SDL_HINT_NO_SIGNAL_HANDLERS, "1");
    SDL_SetHint(SDL_HINT_TIMER_RESOLUTION, "0");
    /* SDL has no window here, so "in the background" has no meaning to it;
     * said out loud so a later SDL default cannot change what a pad does. */
    SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
    /* Devices are read by gpx_poll() and by nothing else. */
    SDL_SetHint(SDL_HINT_AUTO_UPDATE_JOYSTICKS, "0");
    if (!SDL_Init(SDL_INIT_GAMEPAD)) {
        set_sdl_error("could not start SDL's gamepad subsystem");
        SDL_Quit();
        return 0;
    }
    s_refs = 1;
    s_eventHead = 0;
    s_eventCount = 0;
    /* SDL queued an "added" for each pad it found while starting. */
    SDL_UpdateGamepads();
    drain_sdl();
    clear_error();
    return 1;
}

/* Gives back one gpx_start(). At the last one every pad is closed (every
 * handle goes stale), pending events are discarded and SDL shuts down. A
 * stop with nothing started does nothing. */
LC_API void gpx_stop(void)
{
    int i;
    clear_error();
    if (s_refs <= 0) return;
    if (--s_refs > 0) return;
    for (i = 0; i < GPX_MAX_PADS; i++) {
        if (s_pads[i].used) {
            int wasVirtual = s_pads[i].isVirtual;
            SDL_JoystickID id = s_pads[i].id;
            close_slot(i, 0);
            if (wasVirtual) SDL_DetachVirtualJoystick(id);
        }
    }
    s_eventHead = 0;
    s_eventCount = 0;
    SDL_Quit();
}

LC_API int gpx_is_started(void) { return s_refs > 0 ? 1 : 0; }

/* ================================================================== */
/* The pump and the events                                             */
/* ================================================================== */

/* Reads every device once: new pads are opened, unplugged ones closed, and
 * button presses queued. Call it from a timer (every 16 to 33 ms for a
 * game). Returns the number of events waiting for gpx_events(). */
LC_API int gpx_poll(void)
{
    if (s_refs <= 0) { set_error("gamepadxt is not started"); return 0; }
    clear_error();
    read_devices();
    return s_eventCount;
}

LC_API int gpx_event_count(void) { return s_eventCount; }

/* Every waiting event, oldest first, one a line, and the queue is emptied:
 *     connected,<pad>
 *     disconnected,<pad>
 *     button,<pad>,<name>,down     (or up)
 *     axis,<pad>,<name>,<value>    (only after gpx_set_axis_events)
 * Empty when nothing is waiting. */
LC_API const char *gpx_events(void)
{
    size_t at = 0;
    int i;
    clear_error();
    /* the longest line: "disconnected," + 10 digits, or an axis line */
    if (!big_reserve((size_t)s_eventCount * 64 + 1)) {
        set_error("out of memory");
        return "";
    }
    s_big[0] = '\0';
    for (i = 0; i < s_eventCount; i++) {
        const Event *e = &s_events[(s_eventHead + i) % GPX_MAX_EVENTS];
        if (i > 0) s_big[at++] = '\n';
        switch (e->kind) {
        case EV_CONNECTED:
            at += (size_t)snprintf(s_big + at, 64, "connected,%d", e->handle);
            break;
        case EV_DISCONNECTED:
            at += (size_t)snprintf(s_big + at, 64, "disconnected,%d", e->handle);
            break;
        case EV_BUTTON:
            at += (size_t)snprintf(s_big + at, 64, "button,%d,%s,%s", e->handle,
                                   k_buttons[e->code], e->value ? "down" : "up");
            break;
        default:
            at += (size_t)snprintf(s_big + at, 40, "axis,%d,%s,", e->handle, k_axes[e->code]);
            at += (size_t)put_number(s_big + at, 24, unit_of(e->value));
            break;
        }
    }
    s_eventHead = 0;
    s_eventCount = 0;
    return s_big;
}

/* How many events were discarded because GPX_MAX_EVENTS were already
 * waiting (a script that polls and never reads), since the library loaded. */
LC_API int gpx_dropped_events(void) { return s_dropped; }

/* Axis events are OFF by default (step 0): a stick in motion would queue an
 * event every poll, and a game reads sticks with gpx_pad_axes instead. A
 * step of 0.01 to 1 turns them on: an axis is reported when it has moved at
 * least that far since it was last reported, and always when it comes to
 * rest at 0 or at an end. Out of range or not a number: refused. */
LC_API void gpx_set_axis_events(double step)
{
    if (!(step == step) || step < 0.0 || step > 1.0 || (step > 0.0 && step < 0.01)) {
        set_error("the axis event step must be 0 (off) or 0.01 to 1");
        return;
    }
    clear_error();
    s_axisStep = (int)(step * 32767.0 + 0.5);
}

LC_API double gpx_axis_events(void) { return (double)s_axisStep / 32767.0; }

/* ================================================================== */
/* The pads                                                            */
/* ================================================================== */

LC_API int gpx_pad_count(void)
{
    int i, n = 0;
    for (i = 0; i < GPX_MAX_PADS; i++) n += s_pads[i].used ? 1 : 0;
    return n;
}

/* The handle of the index-th connected pad (1-based), or 0. */
LC_API int gpx_pad_at(int index)
{
    int i, n = 0;
    for (i = 0; i < GPX_MAX_PADS; i++) {
        if (s_pads[i].used && ++n == index) return handle_of(i);
    }
    return 0;
}

/* The handles of every connected pad, comma-separated; empty for none. */
LC_API const char *gpx_pads(void)
{
    size_t at = 0;
    int i;
    if (!big_reserve((size_t)GPX_MAX_PADS * 12 + 1)) return "";
    s_big[0] = '\0';
    for (i = 0; i < GPX_MAX_PADS; i++) {
        if (!s_pads[i].used) continue;
        at += (size_t)snprintf(s_big + at, 13, "%s%d", at ? "," : "", handle_of(i));
    }
    return s_big;
}

/* 1 while the handle names a pad that is open and still plugged in. */
LC_API int gpx_pad_is_connected(int pad)
{
    int slot = slot_of(pad);
    if (s_refs <= 0 || slot < 0) return 0;
    return SDL_GamepadConnected(s_pads[slot].pad) ? 1 : 0;
}

LC_API const char *gpx_pad_name(int pad)
{
    Pad *p = pad_of(pad);
    return p ? small_text(SDL_GetGamepadName(p->pad)) : "";
}

/* What kind of pad: unknown, standard, xbox360, xboxone, ps3, ps4, ps5,
 * switchpro, joyconleft, joyconright, joyconpair, gamecube or steam. */
LC_API const char *gpx_pad_type(int pad)
{
    Pad *p = pad_of(pad);
    const char *name;
    if (!p) return "";
    name = SDL_GetGamepadStringForType(SDL_GetGamepadType(p->pad));
    return small_text(name ? name : "unknown");
}

/* The USB vendor and product numbers, 0 when the system does not say. */
LC_API int gpx_pad_vendor(int pad)
{
    Pad *p = pad_of(pad);
    return p ? (int)SDL_GetGamepadVendor(p->pad) : 0;
}

LC_API int gpx_pad_product(int pad)
{
    Pad *p = pad_of(pad);
    return p ? (int)SDL_GetGamepadProduct(p->pad) : 0;
}

/* The 32 hex digits SDL's mapping database knows this model by. */
LC_API const char *gpx_pad_guid(int pad)
{
    Pad *p = pad_of(pad);
    SDL_Joystick *joystick;
    if (!p) return "";
    joystick = SDL_GetGamepadJoystick(p->pad);
    if (!joystick) return "";
    SDL_GUIDToString(SDL_GetJoystickGUID(joystick), s_small, (int)sizeof(s_small));
    return s_small;
}

/* The player number the pad shows on its lights (0 is the first player), or
 * -1 when it has none. */
LC_API int gpx_pad_player(int pad)
{
    Pad *p = pad_of(pad);
    return p ? SDL_GetGamepadPlayerIndex(p->pad) : -1;
}

/* Sets the player number, 0 to 15, or -1 for none. Returns 1 if the pad
 * took it. */
LC_API int gpx_pad_set_player(int pad, int player)
{
    Pad *p = pad_of(pad);
    if (!p) return 0;
    if (player < -1 || player > 15) { set_error("a player number is -1 (none) or 0 to 15"); return 0; }
    if (!SDL_SetGamepadPlayerIndex(p->pad, player)) { set_sdl_error("the pad did not take the player number"); return 0; }
    return 1;
}

LC_API int gpx_pad_is_virtual(int pad)
{
    Pad *p = pad_of(pad);
    return (p && p->isVirtual) ? 1 : 0;
}

/* The battery, 0 to 100, or -1 when the pad does not report one. */
LC_API int gpx_pad_battery(int pad)
{
    Pad *p = pad_of(pad);
    int percent = -1;
    if (!p) return -1;
    (void)SDL_GetGamepadPowerInfo(p->pad, &percent);
    if (percent < 0 || percent > 100) return -1;
    return percent;
}

/* unknown, onbattery, nobattery (wired), charging, charged or error. */
LC_API const char *gpx_pad_power(int pad)
{
    Pad *p = pad_of(pad);
    if (!p) return "";
    switch (SDL_GetGamepadPowerInfo(p->pad, NULL)) {
    case SDL_POWERSTATE_ON_BATTERY: return "onbattery";
    case SDL_POWERSTATE_NO_BATTERY: return "nobattery";
    case SDL_POWERSTATE_CHARGING:   return "charging";
    case SDL_POWERSTATE_CHARGED:    return "charged";
    case SDL_POWERSTATE_ERROR:      return "error";
    default:                        return "unknown";
    }
}

/* The mapping line SDL uses for this pad (SDL_GameControllerDB's format),
 * empty when it has none. */
LC_API const char *gpx_pad_mapping(int pad)
{
    Pad *p = pad_of(pad);
    char *mapping;
    const char *out;
    if (!p) return "";
    mapping = SDL_GetGamepadMapping(p->pad);
    out = big_text(mapping);
    SDL_free(mapping);
    return out;
}

/* ================================================================== */
/* Buttons, sticks and triggers                                        */
/* ================================================================== */

/* The button names this library uses, comma-separated, in SDL's order. */
LC_API const char *gpx_button_names(void)
{
    size_t at = 0;
    int i;
    if (!big_reserve((size_t)GPX_NUM_BUTTONS * 16 + 1)) return "";
    for (i = 0; i < GPX_NUM_BUTTONS; i++) {
        at += (size_t)snprintf(s_big + at, 16, "%s%s", i ? "," : "", k_buttons[i]);
    }
    return s_big;
}

LC_API const char *gpx_axis_names(void)
{
    size_t at = 0;
    int i;
    if (!big_reserve((size_t)GPX_NUM_AXES * 16 + 1)) return "";
    for (i = 0; i < GPX_NUM_AXES; i++) {
        at += (size_t)snprintf(s_big + at, 16, "%s%s", i ? "," : "", k_axes[i]);
    }
    return s_big;
}

/* 1 while the named button is held. As of the last gpx_poll(). */
LC_API int gpx_pad_button(int pad, const char *button)
{
    Pad *p = pad_of(pad);
    int b = button_of(button);
    if (!p) return 0;
    if (b < 0) { set_error("no such button name"); return 0; }
    return SDL_GetGamepadButton(p->pad, (SDL_GamepadButton)b) ? 1 : 0;
}

/* 1 if this pad HAS the named button (a Joy-Con has no right stick). */
LC_API int gpx_pad_has_button(int pad, const char *button)
{
    Pad *p = pad_of(pad);
    int b = button_of(button);
    if (!p) return 0;
    if (b < 0) { set_error("no such button name"); return 0; }
    return SDL_GamepadHasButton(p->pad, (SDL_GamepadButton)b) ? 1 : 0;
}

/* The names of the buttons held now, comma-separated; empty for none. */
LC_API const char *gpx_pad_buttons(int pad)
{
    Pad *p = pad_of(pad);
    size_t at = 0;
    int i;
    if (!p) return "";
    if (!big_reserve((size_t)GPX_NUM_BUTTONS * 16 + 1)) return "";
    s_big[0] = '\0';
    for (i = 0; i < GPX_NUM_BUTTONS; i++) {
        if (!SDL_GetGamepadButton(p->pad, (SDL_GamepadButton)i)) continue;
        at += (size_t)snprintf(s_big + at, 16, "%s%s", at ? "," : "", k_buttons[i]);
    }
    return s_big;
}

/* What is PRINTED on a face button of this pad: a, b, x, y, cross, circle,
 * square or triangle; empty for any other button. */
LC_API const char *gpx_pad_button_label(int pad, const char *button)
{
    Pad *p = pad_of(pad);
    int b = button_of(button);
    if (!p) return "";
    if (b < 0) { set_error("no such button name"); return ""; }
    switch (SDL_GetGamepadButtonLabel(p->pad, (SDL_GamepadButton)b)) {
    case SDL_GAMEPAD_BUTTON_LABEL_A:        return "a";
    case SDL_GAMEPAD_BUTTON_LABEL_B:        return "b";
    case SDL_GAMEPAD_BUTTON_LABEL_X:        return "x";
    case SDL_GAMEPAD_BUTTON_LABEL_Y:        return "y";
    case SDL_GAMEPAD_BUTTON_LABEL_CROSS:    return "cross";
    case SDL_GAMEPAD_BUTTON_LABEL_CIRCLE:   return "circle";
    case SDL_GAMEPAD_BUTTON_LABEL_SQUARE:   return "square";
    case SDL_GAMEPAD_BUTTON_LABEL_TRIANGLE: return "triangle";
    default:                                return "";
    }
}

/* One axis, exactly as the pad reports it: a stick -1 to 1 (left and up are
 * negative), a trigger 0 to 1. No dead zone: see gpx_pad_stick. */
LC_API double gpx_pad_axis(int pad, const char *axis)
{
    Pad *p = pad_of(pad);
    int a = axis_of(axis);
    if (!p) return 0.0;
    if (a < 0) { set_error("no such axis name"); return 0.0; }
    return unit_of(SDL_GetGamepadAxis(p->pad, (SDL_GamepadAxis)a));
}

LC_API int gpx_pad_has_axis(int pad, const char *axis)
{
    Pad *p = pad_of(pad);
    int a = axis_of(axis);
    if (!p) return 0;
    if (a < 0) { set_error("no such axis name"); return 0; }
    return SDL_GamepadHasAxis(p->pad, (SDL_GamepadAxis)a) ? 1 : 0;
}

/* All six axes in one call: leftx,lefty,rightx,righty,lefttrigger,
 * righttrigger. Raw, like gpx_pad_axis. */
LC_API const char *gpx_pad_axes(int pad)
{
    Pad *p = pad_of(pad);
    int i, at = 0;
    if (!p) return "";
    for (i = 0; i < GPX_NUM_AXES; i++) {
        if (i) s_small[at++] = ',';
        at += put_number(s_small + at, sizeof(s_small) - (size_t)at,
                         unit_of(SDL_GetGamepadAxis(p->pad, (SDL_GamepadAxis)i)));
    }
    return s_small;
}

/* A whole stick, "x,y", with the dead zone taken out: inside the zone it is
 * 0,0, and outside it the reading is rescaled so it still runs smoothly from
 * 0 at the zone's edge to 1 at full tilt. The zone is ROUND (measured on the
 * stick's distance from centre, not per axis), so a diagonal is not cut
 * short. side is "left" or "right". */
LC_API const char *gpx_pad_stick(int pad, const char *side)
{
    Pad *p = pad_of(pad);
    double x, y, mag, scale;
    int ax, at;
    if (!p) return "";
    if (side && same_word(side, "left")) ax = SDL_GAMEPAD_AXIS_LEFTX;
    else if (side && same_word(side, "right")) ax = SDL_GAMEPAD_AXIS_RIGHTX;
    else { set_error("a stick is \"left\" or \"right\""); return ""; }
    x = unit_of(SDL_GetGamepadAxis(p->pad, (SDL_GamepadAxis)ax));
    y = unit_of(SDL_GetGamepadAxis(p->pad, (SDL_GamepadAxis)(ax + 1)));
    mag = sqrt(x * x + y * y);
    if (mag <= s_deadZone || mag <= 0.0) {
        x = 0.0;
        y = 0.0;
    } else {
        double out = (mag - s_deadZone) / (1.0 - s_deadZone);
        if (out > 1.0) out = 1.0;       /* a corner of the square reaches past the circle */
        scale = out / mag;
        x *= scale;
        y *= scale;
    }
    at = put_number(s_small, sizeof(s_small), x);
    s_small[at++] = ',';
    (void)put_number(s_small + at, sizeof(s_small) - (size_t)at, y);
    return s_small;
}

/* The dead zone gpx_pad_stick takes out, 0 to 0.9 of full tilt. It starts at
 * 0.15. Out of range or not a number: refused. */
LC_API void gpx_set_dead_zone(double zone)
{
    if (!(zone == zone) || zone < 0.0 || zone > 0.9) {
        set_error("the dead zone is 0 to 0.9");
        return;
    }
    clear_error();
    s_deadZone = zone;
}

LC_API double gpx_dead_zone(void) { return s_deadZone; }

/* ================================================================== */
/* Rumble and lights                                                   */
/* ================================================================== */

static int strength_ok(double v) { return v == v && v >= 0.0 && v <= 1.0; }

LC_API int gpx_pad_has_rumble(int pad)
{
    Pad *p = pad_of(pad);
    if (!p) return 0;
    return SDL_GetBooleanProperty(SDL_GetGamepadProperties(p->pad), SDL_PROP_GAMEPAD_CAP_RUMBLE_BOOLEAN, false) ? 1 : 0;
}

/* Shakes the pad: low is the heavy (left) motor and high the light (right)
 * one, each 0 to 1, for milliseconds (1 to 60000). A new call replaces the
 * one before; strengths of 0 stop it. Returns 1 if the pad took it, 0 if it
 * cannot rumble or an argument was refused. */
LC_API int gpx_pad_rumble(int pad, double low, double high, int milliseconds)
{
    Pad *p = pad_of(pad);
    if (!p) return 0;
    if (!strength_ok(low) || !strength_ok(high)) { set_error("a rumble strength is 0 to 1"); return 0; }
    if (milliseconds < 0 || milliseconds > GPX_MAX_RUMBLE_MS) { set_error("a rumble lasts 0 to 60000 milliseconds"); return 0; }
    if (!SDL_RumbleGamepad(p->pad, (Uint16)(low * 65535.0 + 0.5), (Uint16)(high * 65535.0 + 0.5), (Uint32)milliseconds)) {
        set_sdl_error("the pad did not rumble");
        return 0;
    }
    return 1;
}

LC_API int gpx_pad_has_trigger_rumble(int pad)
{
    Pad *p = pad_of(pad);
    if (!p) return 0;
    return SDL_GetBooleanProperty(SDL_GetGamepadProperties(p->pad), SDL_PROP_GAMEPAD_CAP_TRIGGER_RUMBLE_BOOLEAN, false) ? 1 : 0;
}

/* The motors inside the triggers (Xbox One and later pads). */
LC_API int gpx_pad_rumble_triggers(int pad, double left, double right, int milliseconds)
{
    Pad *p = pad_of(pad);
    if (!p) return 0;
    if (!strength_ok(left) || !strength_ok(right)) { set_error("a rumble strength is 0 to 1"); return 0; }
    if (milliseconds < 0 || milliseconds > GPX_MAX_RUMBLE_MS) { set_error("a rumble lasts 0 to 60000 milliseconds"); return 0; }
    if (!SDL_RumbleGamepadTriggers(p->pad, (Uint16)(left * 65535.0 + 0.5), (Uint16)(right * 65535.0 + 0.5), (Uint32)milliseconds)) {
        set_sdl_error("the pad's triggers did not rumble");
        return 0;
    }
    return 1;
}

LC_API int gpx_pad_has_led(int pad)
{
    Pad *p = pad_of(pad);
    if (!p) return 0;
    return SDL_GetBooleanProperty(SDL_GetGamepadProperties(p->pad), SDL_PROP_GAMEPAD_CAP_RGB_LED_BOOLEAN, false) ? 1 : 0;
}

/* Sets the pad's light bar (PS4, PS5), each colour 0 to 255. */
LC_API int gpx_pad_set_led(int pad, int red, int green, int blue)
{
    Pad *p = pad_of(pad);
    if (!p) return 0;
    if (red < 0 || red > 255 || green < 0 || green > 255 || blue < 0 || blue > 255) {
        set_error("a colour is 0 to 255");
        return 0;
    }
    if (!SDL_SetGamepadLED(p->pad, (Uint8)red, (Uint8)green, (Uint8)blue)) {
        set_sdl_error("the pad has no light to set");
        return 0;
    }
    return 1;
}

/* ================================================================== */
/* Mappings                                                            */
/* ================================================================== */

/* Teaches SDL a pad it does not know, or corrects one: a line in
 * SDL_GameControllerDB's format. Returns 1 added, 0 replaced an existing
 * one, -1 refused. */
LC_API int gpx_add_mapping(const char *mapping)
{
    int r;
    if (s_refs <= 0) { set_error("gamepadxt is not started"); return -1; }
    if (!mapping || !mapping[0]) { set_error("the mapping is empty"); return -1; }
    if (strlen(mapping) > GPX_MAX_MAPPING) { set_error("the mapping is longer than 8192 bytes"); return -1; }
    r = SDL_AddGamepadMapping(mapping);
    if (r < 0) { set_sdl_error("the mapping was refused"); return -1; }
    clear_error();
    return r;
}

/* Loads a whole gamecontrollerdb.txt. Returns how many mappings were added,
 * or -1 if the file could not be read. */
LC_API int gpx_add_mappings_from_file(const char *path)
{
    int r;
    if (s_refs <= 0) { set_error("gamepadxt is not started"); return -1; }
    if (!path || !path[0]) { set_error("the path is empty"); return -1; }
    if (strlen(path) > GPX_MAX_PATH) { set_error("the path is longer than 4096 bytes"); return -1; }
    r = SDL_AddGamepadMappingsFromFile(path);
    if (r < 0) { set_sdl_error("the mappings file could not be read"); return -1; }
    clear_error();
    return r;
}

/* ================================================================== */
/* Virtual pads: a pad with no hardware, driven by calls. For on-screen */
/* controls, replays and tests. A virtual pad is a pad in every other   */
/* way: it is in gpx_pads(), it queues events, it answers every getter. */
/* ================================================================== */

/* Attaches a virtual pad with every button and all six axes. Returns its
 * handle (its "connected" event is queued), or 0. */
LC_API int gpx_virtual_attach(const char *name)
{
    SDL_VirtualJoystickDesc desc;
    SDL_JoystickID id;
    char label[GPX_MAX_NAME + 1];
    int slot, handle;
    size_t i;
    if (s_refs <= 0) { set_error("gamepadxt is not started"); return 0; }
    if (!name || !name[0]) name = "Virtual Gamepad";
    if (strlen(name) > GPX_MAX_NAME) { set_error("a virtual pad's name is at most 64 bytes"); return 0; }
    /* The name goes into a mapping line, where a comma ends a field. */
    for (i = 0; name[i]; i++) {
        unsigned char c = (unsigned char)name[i];
        label[i] = (c < 32 || c == ',' || c == 127) ? ' ' : (char)c;
    }
    label[i] = '\0';
    slot = slot_take();
    if (slot < 0) { set_error("64 pads are already open"); return 0; }

    SDL_INIT_INTERFACE(&desc);
    desc.type = SDL_JOYSTICK_TYPE_GAMEPAD;
    desc.naxes = GPX_NUM_AXES;
    desc.nbuttons = GPX_NUM_BUTTONS;
    /* Every button and axis, so SDL's virtual mapping numbers them exactly
     * as its own enums do: joystick button N is gamepad button N. */
    desc.button_mask = (Uint32)((1u << GPX_NUM_BUTTONS) - 1u);
    desc.axis_mask = (Uint32)((1u << GPX_NUM_AXES) - 1u);
    desc.name = label;
    desc.userdata = (void *)(intptr_t)(slot + 1);
    desc.Rumble = virtual_rumble;
    desc.RumbleTriggers = virtual_rumble_triggers;
    desc.SetLED = virtual_led;
    /* Marked before SDL sees it: SDL may call a hook while attaching. */
    s_pads[slot].isVirtual = 1;
    id = SDL_AttachVirtualJoystick(&desc);
    if (!id) {
        set_sdl_error("could not attach a virtual pad");
        slot_free(slot);
        return 0;
    }
    handle = open_into(slot, id, 1);
    if (!handle) {
        SDL_DetachVirtualJoystick(id);
        return 0;
    }
    /* A trigger at rest is the bottom of its axis, not the middle. */
    {
        SDL_Joystick *joystick = SDL_GetGamepadJoystick(s_pads[slot].pad);
        if (joystick) {
            SDL_SetJoystickVirtualAxis(joystick, SDL_GAMEPAD_AXIS_LEFT_TRIGGER, SDL_MIN_SINT16);
            SDL_SetJoystickVirtualAxis(joystick, SDL_GAMEPAD_AXIS_RIGHT_TRIGGER, SDL_MIN_SINT16);
        }
    }
    clear_error();
    return handle;
}

/* The virtual pad behind a handle, or NULL with the reason recorded. */
static Pad *virtual_pad_of(int h)
{
    Pad *p = pad_of(h);
    if (!p) return NULL;
    if (!p->isVirtual) { set_error("that pad is not a virtual pad"); return NULL; }
    return p;
}

/* Detaches a virtual pad: its "disconnected" is queued and its handle goes
 * stale. A real pad is refused (unplug it instead). */
LC_API void gpx_virtual_detach(int pad)
{
    Pad *p = virtual_pad_of(pad);
    SDL_JoystickID id;
    if (!p) return;
    id = p->id;
    close_slot((int)(p - s_pads), 1);
    SDL_DetachVirtualJoystick(id);
}

/* Presses (1) or releases (0) a button of a virtual pad. It shows at the
 * next gpx_poll(), as a real press would. Returns 1 if it was taken.
 *
 * A TAP BETWEEN TWO POLLS IS KEPT. SDL's virtual pad holds one pending state
 * a button, not a list of changes: a press and a release set before SDL next
 * read the pad left it "up" and no event at all, so a quick tap on an
 * on-screen button, or two steps of a replay in one frame, vanished. So a
 * second change to a button SDL has not read yet has SDL read the pads first
 * (the earlier change becomes its event, in order), and only then is set. */
LC_API int gpx_virtual_set_button(int pad, const char *button, int down)
{
    Pad *p = virtual_pad_of(pad);
    int b = button_of(button);
    SDL_Joystick *joystick;
    if (!p) return 0;
    if (b < 0) { set_error("no such button name"); return 0; }
    if (p->vUnread & (1u << b)) {
        read_devices();
        /* reading can close a pad (its device left): look the handle up again */
        p = virtual_pad_of(pad);
        if (!p) return 0;
    }
    joystick = SDL_GetGamepadJoystick(p->pad);
    if (joystick) p->vUnread |= (1u << b);
    if (!joystick || !SDL_SetJoystickVirtualButton(joystick, b, down ? true : false)) {
        set_sdl_error("the virtual pad did not take the button");
        return 0;
    }
    return 1;
}

/* Moves an axis of a virtual pad: a stick -1 to 1, a trigger 0 to 1. It
 * shows at the next gpx_poll(). Returns 1 if it was taken. */
LC_API int gpx_virtual_set_axis(int pad, const char *axis, double value)
{
    Pad *p = virtual_pad_of(pad);
    int a = axis_of(axis);
    SDL_Joystick *joystick;
    long raw;
    if (!p) return 0;
    if (a < 0) { set_error("no such axis name"); return 0; }
    if (!(value == value)) { set_error("an axis value must be a number"); return 0; }
    if (is_trigger(a)) {
        if (value < 0.0 || value > 1.0) { set_error("a trigger is 0 to 1"); return 0; }
        /* the joystick axis runs its whole range; SDL halves it for the pad */
        raw = (long)floor(value * 65535.0 + 0.5) - 32768;
    } else {
        if (value < -1.0 || value > 1.0) { set_error("a stick axis is -1 to 1"); return 0; }
        raw = (long)floor(value * 32767.0 + 0.5);
    }
    joystick = SDL_GetGamepadJoystick(p->pad);
    if (!joystick || !SDL_SetJoystickVirtualAxis(joystick, a, (Sint16)raw)) {
        set_sdl_error("the virtual pad did not take the axis");
        return 0;
    }
    return 1;
}

/* What a virtual pad was last told to rumble at: "low,high,left,right",
 * each 0 to 1 (the two motors, then the two triggers). So a game's rumble
 * can be seen with no pad in the room. */
LC_API const char *gpx_virtual_rumble(int pad)
{
    Pad *p = virtual_pad_of(pad);
    int at = 0, i;
    int v[4];
    if (!p) return "";
    v[0] = p->vLow; v[1] = p->vHigh; v[2] = p->vLeft; v[3] = p->vRight;
    for (i = 0; i < 4; i++) {
        if (i) s_small[at++] = ',';
        at += put_number(s_small + at, sizeof(s_small) - (size_t)at, (double)v[i] / 65535.0);
    }
    return s_small;
}

/* The colour a virtual pad's light was last set to: "red,green,blue". */
LC_API const char *gpx_virtual_led(int pad)
{
    Pad *p = virtual_pad_of(pad);
    if (!p) return "";
    snprintf(s_small, sizeof(s_small), "%d,%d,%d", p->vRed, p->vGreen, p->vBlue);
    return s_small;
}
