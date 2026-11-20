/*
 * box3d_shim.c
 * ----------------------------------------------------------------------------
 * The C shim of box3dxt: Box3D (Erin Catto's 3D rigid-body engine, the sibling
 * of Box2D v3) behind a flat C ABI that the xTalk Builder (LCB) foreign
 * function interface can call, so OpenXTalk and LiveCode-compatible engines
 * can run a real 3D physics engine. box2dxt/src/box2d_lc.c is this file's
 * ancestor and its conventions are kept:
 *
 *   - Box3D ids (b3WorldId, b3BodyId, b3ShapeId, b3JointId) are small structs
 *     passed BY VALUE, and the LCB FFI has no 64-bit integer. So every id
 *     lives in a shim-side handle table and crosses as a positive 32-bit int
 *     (0 = invalid). Handles are generation-tagged: a handle stays dead after
 *     its object is destroyed even once the table slot is recycled.
 *   - Every real crosses as `double` (xTalk numbers are doubles) and is cast
 *     to and from Box3D's `float` here. Every boolean crosses as `int`.
 *   - A result that is more than one number (a position, a quaternion, a
 *     hit) crosses as TEXT: comma-separated items, which is what a script
 *     wants anyway (`item 2 of b3BodyPosition(tBody)`). The text is written
 *     with a "." decimal point whatever the process locale says, because an
 *     engine built on GTK calls setlocale() and a "1,5" would be two items.
 *     The pointer returned is to a static buffer; the binding copies it at
 *     once (as a Pointer through its textOf(), never as ZStringNative: the
 *     engine FREES a returned C string) and script is single-threaded.
 *   - A list (ray hits, overlaps, contact and sensor events, body moves) is
 *     taken as a SNAPSHOT by one call and read back by index. Indices are
 *     1-based on this side too, so the binding passes them through.
 *
 * Safety. Box3D checks its inputs with assertions, and a release build has
 * none: a NaN, a zero quaternion or a stale id would corrupt the world
 * silently. So every export validates here first. A stale or never-created
 * handle is a harmless no-op (getters return 0 or empty), a non-finite or
 * out-of-range argument refuses the call, and a joint call made on a joint
 * of another type does nothing. No callback ever reaches script: Box3D's own
 * worker threads run only inside b3World_Step, which returns before the call
 * does (suite rule 1).
 *
 * Geometry ownership. Box3D CLONES spheres, capsules and convex hulls into
 * the world, so those are built, handed over and freed here in one call. It
 * does NOT clone a triangle mesh or a height field: the shape keeps a pointer.
 * The shim therefore owns that data per shape slot and frees it only after
 * the shape is gone (destroyed by name, with its body, or with its world).
 *
 * Build: compiled with Box3D into ONE shared library named "box3dxt"
 * (box3dxt.so / box3dxt.dll / box3dxt.dylib), or for the web into a static
 * archive. See CMakeLists.txt.
 * ----------------------------------------------------------------------------
 */

#include "box3d/box3d.h"

#include <locale.h>
#include <math.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
    #define LC_API __declspec(dllexport)
#else
    #define LC_API __attribute__((visibility("default")))
#endif

/* Bump when the exported ABI changes; src/box3dxt.lcb's checkABI() names the
 * same number and refuses a library that answers another. */
#define B3X_ABI_VERSION 1

/* ------------------------------------------------------------------ */
/* Generic handle tables (box2dxt's, with one change: see below).      */
/* Handles are positive ints; 0 == null/invalid. Each packs an 11-bit  */
/* generation above a 20-bit slot number (slot + 1), so a stale handle */
/* stays DEAD after its slot is recycled.                              */
/*                                                                     */
/* The change: a slot whose generation would WRAP is retired, never    */
/* reused. With box2dxt's table the 2048th reuse of one slot hands out */
/* the bits of the first handle again, and a script that kept that     */
/* handle finds it alive and naming a stranger (the smoke test's churn */
/* of 5000 bodies met it twice, 2026-11-20). Retiring costs one slot   */
/* (a few bytes) per 2047 handles and the table holds a million.       */
/* ------------------------------------------------------------------ */
#define B3X_H_SLOT_BITS 20
#define B3X_H_SLOT_MASK 0xFFFFF            /* low 20 bits: slot + 1     */
#define B3X_H_GEN_MASK  0x7FF              /* 11 bits of generation     */
#define B3X_H_MAX_SLOTS (B3X_H_SLOT_MASK - 1)

#define DEFINE_TABLE(NAME, TYPE)                                              \
    static TYPE *NAME##_arr = NULL;                                           \
    static unsigned char  *NAME##_used = NULL;                                \
    static unsigned short *NAME##_gen = NULL;                                 \
    static int   NAME##_cap = 0;                                              \
    static int   NAME##_cnt = 0;                                              \
    static int  *NAME##_free = NULL;                                          \
    static int   NAME##_freeCap = 0;                                          \
    static int   NAME##_freeCnt = 0;                                          \
    static int NAME##_grow_slots(int nc) {                                    \
        TYPE *na = (TYPE *)realloc(NAME##_arr, (size_t)nc * sizeof(TYPE));    \
        if (!na) return 0;                                                    \
        NAME##_arr = na;                                                      \
        unsigned char *nu = (unsigned char *)realloc(NAME##_used,             \
                                                     (size_t)nc);             \
        if (!nu) return 0;                                                    \
        NAME##_used = nu;                                                     \
        unsigned short *ng = (unsigned short *)realloc(NAME##_gen,            \
                                            (size_t)nc * sizeof(short));      \
        if (!ng) return 0;                                                    \
        NAME##_gen = ng;                                                      \
        memset(NAME##_used + NAME##_cap, 0, (size_t)(nc - NAME##_cap));       \
        memset(NAME##_gen + NAME##_cap, 0,                                    \
               (size_t)(nc - NAME##_cap) * sizeof(short));                    \
        NAME##_cap = nc;                                                      \
        return 1;                                                             \
    }                                                                         \
    static int NAME##_encode(int idx) {                                       \
        return (int)(((unsigned)NAME##_gen[idx] << B3X_H_SLOT_BITS)            \
                     | (unsigned)(idx + 1));                                  \
    }                                                                         \
    /* handle -> slot index, or -1 if stale / never created */               \
    static int NAME##_slot_of(int h) {                                        \
        if (h <= 0) return -1;                                                \
        int idx = (h & B3X_H_SLOT_MASK) - 1;                                   \
        unsigned gen = ((unsigned)h >> B3X_H_SLOT_BITS) & B3X_H_GEN_MASK;       \
        if (idx < 0 || idx >= NAME##_cnt) return -1;                          \
        if (!NAME##_used[idx] || NAME##_gen[idx] != gen) return -1;           \
        return idx;                                                           \
    }                                                                         \
    static int NAME##_add(TYPE v) {                                           \
        int idx;                                                              \
        if (NAME##_freeCnt > 0) {                                             \
            do {                                                              \
                idx = NAME##_free[--NAME##_freeCnt];                          \
            } while (NAME##_freeCnt > 0 && NAME##_used[idx]);                 \
            if (NAME##_used[idx]) idx = -1;                                   \
        } else {                                                              \
            idx = -1;                                                         \
        }                                                                     \
        if (idx < 0) {                                                        \
            if (NAME##_cnt >= B3X_H_MAX_SLOTS) return 0;                       \
            if (NAME##_cnt >= NAME##_cap) {                                   \
                int nc = NAME##_cap ? NAME##_cap * 2 : 64;                    \
                if (!NAME##_grow_slots(nc)) return 0;                         \
            }                                                                 \
            idx = NAME##_cnt++;                                               \
        }                                                                     \
        NAME##_arr[idx] = v;                                                  \
        NAME##_used[idx] = 1;                                                 \
        return NAME##_encode(idx);                                            \
    }                                                                         \
    static TYPE NAME##_get(int h) {                                           \
        int idx = NAME##_slot_of(h);                                          \
        if (idx < 0) { TYPE z; memset(&z, 0, sizeof z); return z; }           \
        return NAME##_arr[idx];                                               \
    }                                                                         \
    static int NAME##_free_slot(int idx) {                                    \
        if (idx < 0 || idx >= NAME##_cnt || !NAME##_used[idx]) return 0;      \
        if (NAME##_freeCnt >= NAME##_freeCap) {                               \
            int nc = NAME##_freeCap ? NAME##_freeCap * 2 : 64;                \
            int *nf = (int *)realloc(NAME##_free, (size_t)nc * sizeof(int));  \
            if (!nf) return 0;                                                \
            NAME##_free = nf; NAME##_freeCap = nc;                            \
        }                                                                     \
        { TYPE z; memset(&z, 0, sizeof z); NAME##_arr[idx] = z; }             \
        NAME##_used[idx] = 0;                                                 \
        if (NAME##_gen[idx] >= B3X_H_GEN_MASK) return 1; /* retired */       \
        NAME##_gen[idx] = (unsigned short)(NAME##_gen[idx] + 1);              \
        NAME##_free[NAME##_freeCnt++] = idx;                                  \
        return 1;                                                             \
    }                                                                         \
    static int NAME##_free_handle(int h) {                                    \
        return NAME##_free_slot(NAME##_slot_of(h));                          \
    }

DEFINE_TABLE(worlds, b3WorldId)
DEFINE_TABLE(bodies, b3BodyId)
DEFINE_TABLE(shapes, b3ShapeId)
DEFINE_TABLE(joints, b3JointId)

/* integer handle <-> Box3D userData (void*) round-trip */
static void *h2ud(int h)   { return (void *)(intptr_t)h; }
static int   ud2h(void *p) { return (int)(intptr_t)p; }

/* ------------------------------------------------------------------ */
/* The last refusal, for b3LastError(). A short fixed text, or "".     */
/* ------------------------------------------------------------------ */
static const char *s_error = "";
static int fail(const char *why) { s_error = why; return 0; }
static void ok_clear(void) { s_error = ""; }

/* ------------------------------------------------------------------ */
/* Argument checks                                                     */
/* ------------------------------------------------------------------ */
/* THE ENVELOPE. Box3D computes in float and trusts its caller: a value that
 * is finite on the way in can still square, cube or divide its way to
 * infinity inside the solver, infinity becomes NaN at the next subtraction,
 * a NaN transform becomes a NaN bounding box, and a NaN box corrupts the
 * broad-phase tree, which is a crash in the HOST some steps later with
 * nothing in the script to point at (met by tests/fuzz_test.c, 2026-11-20:
 * a segfault inside b3Body_SetTransform, thousands of calls after the value
 * that caused it). So no number reaches Box3D unless it is inside a range
 * where that cannot start. The ranges are far outside anything a scene
 * uses and are named in the API page; a value outside one is refused like
 * any other bad argument (the call does nothing, b3LastError says why).
 *
 *   any number                 |v| <= 1e9
 *   a size, a radius, a length 0.001 .. 10000   (1 mm to 10 km)
 *   a point inside a shape     |v| <= 10000
 *   a density                  0 .. 1e6
 *   a spring frequency (Hz)    0 .. 10000
 *   a damping ratio            0 .. 1000
 *   a position in the world    Box3D's own limit (100 km from the origin)
 */
#define B3X_MAX_VALUE   1.0e9
#define B3X_MIN_SIZE    1.0e-3
#define B3X_MAX_SIZE    1.0e4
#define B3X_MAX_DENSITY 1.0e6
#define B3X_MAX_HERTZ   1.0e4
#define B3X_MAX_RATIO   1.0e3
static int fin(double v) { return isfinite(v) && fabs(v) <= B3X_MAX_VALUE; }
static int fin3(double a, double b, double c) { return fin(a) && fin(b) && fin(c); }
static int nonneg(double v) { return fin(v) && v >= 0.0; }
/* Above 0 AS A FLOAT with room to spare: 1e-300 is positive and casts to 0. */
static int positive(double v) { return fin(v) && v >= 1.0e-6; }
static int size_ok(double v) { return isfinite(v) && v >= B3X_MIN_SIZE && v <= B3X_MAX_SIZE; }
static int local_ok(double v) { return isfinite(v) && fabs(v) <= B3X_MAX_SIZE; }
static int hertz_ok(double v) { return isfinite(v) && v >= 0.0 && v <= B3X_MAX_HERTZ; }
static int ratio_ok(double v) { return isfinite(v) && v >= 0.0 && v <= B3X_MAX_RATIO; }

static b3Vec3 v3(double x, double y, double z)
{
    b3Vec3 v;
    v.x = (float)x; v.y = (float)y; v.z = (float)z;
    return v;
}

/* A position: finite and inside the range Box3D accepts (B3_HUGE). */
static int pos_in(double x, double y, double z, b3Pos *out)
{
    if (!fin3(x, y, z)) return 0;
    b3Pos p = b3ToPos(v3(x, y, z));
    if (!b3IsValidPosition(p)) return 0;
    *out = p;
    return 1;
}

/* A point in a shape's own space (see the envelope). */
static int local_in(double x, double y, double z, b3Vec3 *out)
{
    if (!local_ok(x) || !local_ok(y) || !local_ok(z)) return 0;
    *out = v3(x, y, z);
    return 1;
}

static int vec_in(double x, double y, double z, b3Vec3 *out)
{
    if (!fin3(x, y, z)) return 0;
    b3Vec3 v = v3(x, y, z);
    if (!b3IsValidVec3(v)) return 0;
    *out = v;
    return 1;
}

/* A direction: a vector with a length, returned normalized. */
static int dir_in(double x, double y, double z, b3Vec3 *out)
{
    if (!fin3(x, y, z)) return 0;
    double len = sqrt(x * x + y * y + z * z);
    if (!(len > 1.0e-6) || !isfinite(len)) return 0;
    *out = v3(x / len, y / len, z / len);
    return 1;
}

/* A rotation: any quaternion with a length, returned normalized. Script
 * arithmetic drifts, so a unit quaternion is made here and not demanded. */
static int quat_in(double x, double y, double z, double w, b3Quat *out)
{
    if (!fin3(x, y, z) || !fin(w)) return 0;
    double len = sqrt(x * x + y * y + z * z + w * w);
    if (!(len > 1.0e-6) || !isfinite(len)) return 0;
    b3Quat q;
    q.v = v3(x / len, y / len, z / len);
    q.s = (float)(w / len);
    if (!b3IsValidQuat(q)) return 0;
    *out = q;
    return 1;
}

/* Filter bits arrive as doubles; converting a negative or out-of-range value
 * to an unsigned type is undefined behaviour in C, so range-check first.
 * Doubles carry integers exactly up to 2^53, so 53 of Box3D's 64 category
 * bits are usable from script. */
#define B3X_FILTER_BITS_MAX 9007199254740991.0   /* 2^53 - 1 */
static int bits_ok(double v) { return isfinite(v) && v >= 0.0 && v <= B3X_FILTER_BITS_MAX && v == floor(v); }

/* ------------------------------------------------------------------ */
/* Handle -> id, validated twice: by the table's generation and by     */
/* Box3D's own.                                                        */
/* ------------------------------------------------------------------ */
static int same_world(b3WorldId a, b3WorldId b)
{
    return a.index1 == b.index1 && a.generation == b.generation;
}
static int world_ok(int h, b3WorldId *out)
{
    if (worlds_slot_of(h) < 0) return 0;
    b3WorldId id = worlds_get(h);
    if (!b3World_IsValid(id)) return 0;
    *out = id;
    return 1;
}
static int body_ok(int h, b3BodyId *out)
{
    if (bodies_slot_of(h) < 0) return 0;
    b3BodyId id = bodies_get(h);
    if (!b3Body_IsValid(id)) return 0;
    *out = id;
    return 1;
}
static int shape_ok(int h, b3ShapeId *out)
{
    if (shapes_slot_of(h) < 0) return 0;
    b3ShapeId id = shapes_get(h);
    if (!b3Shape_IsValid(id)) return 0;
    *out = id;
    return 1;
}
static int joint_ok(int h, b3JointId *out)
{
    if (joints_slot_of(h) < 0) return 0;
    b3JointId id = joints_get(h);
    if (!b3Joint_IsValid(id)) return 0;
    *out = id;
    return 1;
}
/* A joint of one type. Box3D keeps the types in a union and only asserts the
 * tag, so a typed call on another type must stop here. */
static int joint_typed(int h, b3JointType type, b3JointId *out)
{
    b3JointId id;
    if (!joint_ok(h, &id)) return 0;
    if (b3Joint_GetType(id) != type) return 0;
    *out = id;
    return 1;
}

static int shape_handle_of(b3ShapeId s)
{
    if (!b3Shape_IsValid(s)) return 0;
    int h = ud2h(b3Shape_GetUserData(s));
    return shapes_slot_of(h) >= 0 ? h : 0;
}
static int body_handle_of(b3BodyId b)
{
    if (!b3Body_IsValid(b)) return 0;
    int h = ud2h(b3Body_GetUserData(b));
    return bodies_slot_of(h) >= 0 ? h : 0;
}
static int joint_handle_of(b3JointId j)
{
    if (!b3Joint_IsValid(j)) return 0;
    int h = ud2h(b3Joint_GetUserData(j));
    return joints_slot_of(h) >= 0 ? h : 0;
}
static int body_handle_of_shape(b3ShapeId s)
{
    if (!b3Shape_IsValid(s)) return 0;
    return body_handle_of(b3Shape_GetBody(s));
}

/* ------------------------------------------------------------------ */
/* Geometry a shape does not own: a mesh or a height field, kept per   */
/* shape SLOT and freed when the slot is released.                     */
/* ------------------------------------------------------------------ */
#define B3X_OWNED_NONE   0
#define B3X_OWNED_MESH   1
#define B3X_OWNED_HEIGHT 2
static void **s_owned = NULL;
static unsigned char *s_ownedKind = NULL;
static int s_ownedCap = 0;

static int owned_reserve(int slot)
{
    if (slot < s_ownedCap) return 1;
    int nc = s_ownedCap ? s_ownedCap : 64;
    while (nc <= slot) nc *= 2;
    void **np = (void **)realloc(s_owned, (size_t)nc * sizeof(void *));
    if (!np) return 0;
    s_owned = np;
    unsigned char *nk = (unsigned char *)realloc(s_ownedKind, (size_t)nc);
    if (!nk) return 0;
    s_ownedKind = nk;
    memset(s_owned + s_ownedCap, 0, (size_t)(nc - s_ownedCap) * sizeof(void *));
    memset(s_ownedKind + s_ownedCap, 0, (size_t)(nc - s_ownedCap));
    s_ownedCap = nc;
    return 1;
}
static void owned_free(void *data, int kind)
{
    if (!data) return;
    if (kind == B3X_OWNED_MESH) b3DestroyMesh((b3MeshData *)data);
    else if (kind == B3X_OWNED_HEIGHT) b3DestroyHeightField((b3HeightFieldData *)data);
}
/* Release a shape's table slot and whatever it owned. Call only once Box3D
 * has destroyed the shape: it reads the mesh until then. */
static void shape_release_slot(int slot)
{
    if (slot < 0) return;
    if (slot < s_ownedCap && s_owned[slot]) {
        owned_free(s_owned[slot], s_ownedKind[slot]);
        s_owned[slot] = NULL;
        s_ownedKind[slot] = B3X_OWNED_NONE;
    }
    shapes_free_slot(slot);
}

/* Retire every handle whose Box3D id died with a parent (a world or a body
 * destroys its children implicitly). Keeps stale handles dead, lets their
 * slots be reused, and frees the geometry of shapes that are gone. */
static void retire_dead_handles(void)
{
    for (int i = 0; i < bodies_cnt; i++)
        if (bodies_used[i] && !b3Body_IsValid(bodies_arr[i])) bodies_free_slot(i);
    for (int i = 0; i < shapes_cnt; i++)
        if (shapes_used[i] && !b3Shape_IsValid(shapes_arr[i])) shape_release_slot(i);
    for (int i = 0; i < joints_cnt; i++)
        if (joints_used[i] && !b3Joint_IsValid(joints_arr[i])) joints_free_slot(i);
}

/* ------------------------------------------------------------------ */
/* Text results                                                        */
/* ------------------------------------------------------------------ */
static char s_text[512];

/* One number as text with a "." decimal point in every locale. Returns the
 * length written (never more than cap - 1). */
static int num_text(char *out, int cap, double v)
{
    if (!isfinite(v)) v = 0.0;
    int n = snprintf(out, (size_t)cap, "%.9g", v);
    if (n < 0) { out[0] = '0'; out[1] = 0; return 1; }
    if (n >= cap) n = cap - 1;
    const struct lconv *lc = localeconv();
    const char *dp = lc ? lc->decimal_point : NULL;
    if (dp && dp[0] && strcmp(dp, ".") != 0) {
        char *q = strstr(out, dp);
        if (q) {
            size_t dl = strlen(dp);
            *q = '.';
            memmove(q + 1, q + dl, strlen(q + dl) + 1);
            n = (int)strlen(out);
        }
    }
    return n;
}

/* n numbers, comma-separated, into the shared buffer. */
static const char *text_of(const double *v, int n)
{
    int at = 0;
    s_text[0] = 0;
    for (int i = 0; i < n; i++) {
        if (at > (int)sizeof(s_text) - 40) break;
        if (i) s_text[at++] = ',';
        at += num_text(s_text + at, (int)sizeof(s_text) - at, v[i]);
    }
    s_text[at] = 0;
    return s_text;
}
static const char *text_vec(b3Vec3 v)
{
    double d[3] = { v.x, v.y, v.z };
    return text_of(d, 3);
}
static const char *text_pos(b3Pos p) { return text_vec(b3ToVec3(p)); }
static const char *text_quat(b3Quat q)
{
    double d[4] = { q.v.x, q.v.y, q.v.z, q.s };
    return text_of(d, 4);
}
static const char *text_empty(void) { s_text[0] = 0; return s_text; }

/* A growable text buffer for the lists that have no fixed size. */
static char *s_big = NULL;
static int s_bigCap = 0;
static int big_reserve(int need)
{
    if (need <= s_bigCap) return 1;
    int nc = s_bigCap ? s_bigCap : 4096;
    while (nc < need) nc *= 2;
    char *p = (char *)realloc(s_big, (size_t)nc);
    if (!p) return 0;
    s_big = p;
    s_bigCap = nc;
    return 1;
}

/* ------------------------------------------------------------------ */
/* Library                                                             */
/* ------------------------------------------------------------------ */
LC_API int b3x_abi_version(void) { return B3X_ABI_VERSION; }

/* "box3dxt ABI 1; Box3D 0.2.0" (the numbers are what b3GetVersion answers) */
LC_API const char *b3x_library_version(void)
{
    b3Version v = b3GetVersion();
    snprintf(s_text, sizeof(s_text), "box3dxt ABI %d; Box3D %d.%d.%d",
             B3X_ABI_VERSION, v.major, v.minor, v.revision);
    return s_text;
}

LC_API const char *b3x_last_error(void) { return s_error; }

/* HOW TEXT CROSSES. Every text result is a pointer to a buffer this library
 * owns, valid until the next call. The binding must NOT declare such a
 * result as a C string (ZStringNative): the engine takes a returned C string
 * as its own and frees it, which is free() on a static buffer and the death
 * of the host (met on the first engine run, 2026-11-20: "free(): invalid
 * pointer"). It is declared a Pointer instead, and the engine copies the
 * bytes out with its own MCStringCreateWithBytes, for which it needs the
 * length: this. The one export with no public handler over it. */
LC_API int b3x_text_length(const char *text) { return text ? (int)strlen(text) : 0; }

/* ------------------------------------------------------------------ */
/* Box3D's two voices, both taken away from the host's console.        */
/*                                                                     */
/* Box3D logs with printf and, in a build with its asserts on, stops   */
/* the process at a breakpoint instruction. Neither is acceptable in   */
/* an extension: the host is somebody's IDE with unsaved work. So the  */
/* log is swallowed, and a failed assert is COUNTED and execution goes */
/* on, exactly as it does in the shipped Release build, where the      */
/* asserts are compiled out. The count is what the tests read: the     */
/* smoke test demands 0 in an assert build (nothing a sane scene does  */
/* trips one), and the fuzz test names each one it provokes.           */
/* A worker thread can fail an assert, hence the lock and the atomics. */
/* ------------------------------------------------------------------ */
#if defined(_MSC_VER)
    #include <intrin.h>
    static volatile long s_assertCount = 0;
    static volatile long s_assertLock = 0;
    #define B3X_COUNT_ASSERT() _InterlockedIncrement(&s_assertCount)
    #define B3X_LOCK()   while (_InterlockedExchange(&s_assertLock, 1)) { }
    #define B3X_UNLOCK() _InterlockedExchange(&s_assertLock, 0)
    #define B3X_ASSERTS() ((int)s_assertCount)
#else
    static int s_assertCount = 0;
    static char s_assertLock = 0;
    #define B3X_COUNT_ASSERT() __atomic_add_fetch(&s_assertCount, 1, __ATOMIC_SEQ_CST)
    #define B3X_LOCK()   while (__atomic_test_and_set(&s_assertLock, __ATOMIC_ACQUIRE)) { }
    #define B3X_UNLOCK() __atomic_clear(&s_assertLock, __ATOMIC_RELEASE)
    #define B3X_ASSERTS() __atomic_load_n(&s_assertCount, __ATOMIC_SEQ_CST)
#endif
static char s_assertText[160] = "";
static char s_assertCopy[160] = "";

static int on_assert(const char *condition, const char *fileName, int lineNumber)
{
    /* the file's own name, not the build machine's path to it */
    const char *base = fileName ? fileName : "";
    for (const char *p = base; *p; p++) if (*p == '/' || *p == '\\') base = p + 1;
    B3X_COUNT_ASSERT();
    B3X_LOCK();
    snprintf(s_assertText, sizeof(s_assertText), "%s (%s:%d)", condition ? condition : "", base, lineNumber);
    B3X_UNLOCK();
    return 0;                                   /* 0: do not break, carry on */
}
static void on_log(const char *message) { (void)message; }

static void install_hooks(void)
{
    static int done = 0;
    if (done) return;
    done = 1;
    b3SetAssertFcn(on_assert);
    b3SetLogFcn(on_log);
}

/* How many Box3D asserts have failed since the library loaded. Always 0 in
 * a shipped build (Release compiles them out); for people building the
 * library with asserts on, and for the tests. */
LC_API int b3x_assert_count(void) { return B3X_ASSERTS(); }
/* The last failed assert, "condition (file:line)", or "". */
LC_API const char *b3x_assert_text(void)
{
    B3X_LOCK();
    memcpy(s_assertCopy, s_assertText, sizeof(s_assertCopy));
    B3X_UNLOCK();
    return s_assertCopy;
}

/* 1 when this build's wide solver can use AVX2 on this CPU (x86-64 only;
 * chosen at run time, so one library serves every x86-64 machine). */
LC_API int b3x_has_avx2(void) { return b3IsAVX2Available() ? 1 : 0; }

/* ------------------------------------------------------------------ */
/* THE MASS BUDGET. A body's inertia is summed in float and inverted through
 * its determinant, the product of three inertias: one shape a few hundred
 * metres across at the density of water is enough to send that to infinity,
 * and a body with a NaN inertia poisons its world at the next step (see the
 * envelope). Two checks, because neither is enough alone:
 *
 *   before: a shape for a MOVING body is weighed with Box3D's own mass
 *     functions and refused over the budget. A static body is not weighed
 *     (a 20 km floor at density 1 is an ordinary thing to write);
 *   after: whenever a body's mass was recomputed, it is read back, and a
 *     mass that is not finite undoes the call that caused it. This is the
 *     one that covers a static body turned dynamic and many heavy shapes
 *     adding up.
 */
#define B3X_MASS_BUDGET 1.0e10
static const char *k_too_heavy =
    "too big or too heavy for a moving body (its inertia would overflow): lower the density or make it smaller";

static int mass_fits(b3BodyId body, b3MassData md)
{
    if (b3Body_GetType(body) != b3_dynamicBody) return 1;
    const float *e = &md.inertia.cx.x;
    double biggest = 0.0;
    for (int i = 0; i < 9; i++) {
        if (!isfinite(e[i])) return 0;
        if (fabs((double)e[i]) > biggest) biggest = fabs((double)e[i]);
    }
    double m = (double)md.mass;
    double c2 = (double)md.center.x * md.center.x + (double)md.center.y * md.center.y + (double)md.center.z * md.center.z;
    if (!isfinite(m) || !isfinite(c2)) return 0;
    return m <= B3X_MASS_BUDGET && biggest + m * c2 <= B3X_MASS_BUDGET;
}

static int body_mass_sane(b3BodyId body)
{
    b3MassData md = b3Body_GetMassData(body);
    const float *e = &md.inertia.cx.x;
    for (int i = 0; i < 9; i++) if (!isfinite(e[i])) return 0;
    return isfinite(md.mass) && isfinite(md.center.x) && isfinite(md.center.y) && isfinite(md.center.z);
}

/* ------------------------------------------------------------------ */
/* World                                                               */
/* ------------------------------------------------------------------ */
static int s_worldsLive = 0;

/* THE STALE MOVE INDEX. Each step, Box3D gives every awake body an index
 * into that step's list of moved bodies, and a forced sleep
 * (b3Body_SetAwake false) writes "fell asleep" through the index of every
 * body in the island. A body that LEAVES the awake set without sleeping
 * (b3Body_Disable, or a change of type to static) keeps its index, and when
 * it comes back (b3Body_Enable, a change of type) the index still points
 * into a list that has been rebuilt since: the wrong body's record, or past
 * the end (met by tests/fuzz_test.c, 2026-11-20, seeds 14 and 65: step,
 * disable, step, enable, sleep). The next step renews every awake body's
 * index, so the answer is one flag per world: raised by an enable or a type
 * change, lowered by a step, and while it is up a forced sleep in that
 * world is refused with a reason. Per world, not per body, because the
 * sleep takes the whole island and a joint can put the returned body in
 * somebody else's. Indexed by Box3D's own world index (1..B3_MAX_WORLDS). */
static unsigned char s_sleepUnsafe[B3_MAX_WORLDS + 1];
static void sleep_unsafe_set(b3WorldId wid, int flag)
{
    if (wid.index1 >= 1 && wid.index1 <= B3_MAX_WORLDS) s_sleepUnsafe[wid.index1] = (unsigned char)flag;
}
static int sleep_unsafe(b3WorldId wid)
{
    return wid.index1 >= 1 && wid.index1 <= B3_MAX_WORLDS && s_sleepUnsafe[wid.index1];
}
LC_API int b3x_world_create(double gx, double gy, double gz, int workers)
{
    b3Vec3 g;
    install_hooks();
    if (!vec_in(gx, gy, gz, &g)) return fail("gravity is not a finite vector");
    b3WorldDef wd = b3DefaultWorldDef();
    wd.gravity = g;
    if (workers < 1) workers = 1;
    if (workers > B3_MAX_WORKERS) workers = B3_MAX_WORKERS;
#if defined(__EMSCRIPTEN__)
    /* The web build has no threads: Box3D would fail to start its pool. */
    workers = 1;
#endif
    wd.workerCount = (uint32_t)workers;
    /* Refuse the 129th world here: Box3D refuses it too, but by printing to
     * stdout, and an extension must never write to the host's console. */
    if (s_worldsLive >= B3_MAX_WORLDS) return fail("too many worlds at once (Box3D allows 128)");
    b3WorldId id = b3CreateWorld(&wd);
    sleep_unsafe_set(id, 0);    /* a new world in a reused Box3D slot */
    if (!b3World_IsValid(id)) return fail("Box3D could not create a world (the limit is 128 at once)");
    int h = worlds_add(id);
    if (!h) { b3DestroyWorld(id); return fail("out of world handles"); }
    s_worldsLive++;
    ok_clear();
    return h;
}

LC_API void b3x_world_destroy(int w)
{
    b3WorldId id;
    if (!world_ok(w, &id)) { if (worlds_free_handle(w)) s_worldsLive--; return; }
    b3DestroyWorld(id);
    if (worlds_free_handle(w)) s_worldsLive--;
    retire_dead_handles();
}

LC_API int b3x_world_is_valid(int w) { b3WorldId id; return world_ok(w, &id); }

/* THE NET. The envelope keeps bad numbers out; this catches the ones Box3D
 * makes by itself. A legal scene can still blow up in the solver (measured
 * 2026-11-20 by tests/fuzz_test.c: a weld whose frame sits 570 m from a
 * chain of dynamic bodies that have no shapes, so no mass, goes NaN in
 * three steps). Box3D logs "unstable" and carries on, and a body made of
 * NaN then corrupts the broad-phase tree: the host dies at some later,
 * unrelated call. So after every step each body that moved is looked at,
 * and one whose position, rotation or velocity is no longer a number is
 * DESTROYED, with its shapes and joints. Destroying is the safe removal: it
 * unlinks the body from the tree by structure and never reads its numbers.
 * The script finds the handle dead (b3BodyIsValid), b3LastError says what
 * happened and b3UnstableCount counts it.
 */
static int s_unstable = 0;
static b3BodyId *s_bad = NULL;
static int s_badCap = 0;

static int float3_ok(b3Vec3 v) { return isfinite(v.x) && isfinite(v.y) && isfinite(v.z); }
/* A velocity is "gone" before it is NaN: fuzz seed 17 (2026-11-20) left a
 * body spinning at 6e21 rad/s with a linear velocity whose LENGTH overflowed
 * a float (b3BodySpeed answered inf) while every component was still finite,
 * so a test for NaN alone let it stand one step short of poisoning the
 * broad-phase. The bound is the envelope's own (1e9): nothing a script may
 * hand in is larger, so nothing honest is removed by it. */
static int velocity_ok(b3Vec3 v)
{
    return float3_ok(v) && fabsf(v.x) <= 1.0e9f && fabsf(v.y) <= 1.0e9f && fabsf(v.z) <= 1.0e9f;
}

static void sweep_unstable(b3WorldId id)
{
    b3BodyEvents ev = b3World_GetBodyEvents(id);
    int bad = 0;
    for (int i = 0; i < ev.moveCount; i++) {
        const b3BodyMoveEvent *e = &ev.moveEvents[i];
        b3Vec3 p = b3ToVec3(e->transform.p);
        int ok = float3_ok(p) && float3_ok(e->transform.q.v) && isfinite(e->transform.q.s)
                 && b3Body_IsValid(e->bodyId)
                 && velocity_ok(b3Body_GetLinearVelocity(e->bodyId))
                 && velocity_ok(b3Body_GetAngularVelocity(e->bodyId));
        if (ok || !b3Body_IsValid(e->bodyId)) continue;
        if (bad >= s_badCap) {
            int nc = s_badCap ? s_badCap * 2 : 16;
            b3BodyId *nb = (b3BodyId *)realloc(s_bad, (size_t)nc * sizeof(b3BodyId));
            if (!nb) break;                      /* the rest are caught next step */
            s_bad = nb; s_badCap = nc;
        }
        s_bad[bad++] = e->bodyId;
    }
    if (!bad) return;
    /* collected first: destroying a body invalidates the event array */
    for (int i = 0; i < bad; i++)
        if (b3Body_IsValid(s_bad[i])) { b3DestroyBody(s_bad[i]); s_unstable++; }
    retire_dead_handles();
    fail("a body's motion stopped being a number (an unstable joint or a body with no mass); it was removed");
}

/* How many bodies the net has removed since the library loaded. */
LC_API int b3x_unstable_count(void) { return s_unstable; }

LC_API void b3x_world_step(int w, double dt, int substeps)
{
    b3WorldId id;
    if (!world_ok(w, &id)) return;
    /* A step of no time is refused, not passed on. Box3D empties its list of
     * moved bodies at the start of every step but, with dt 0, never refills
     * it, and each body keeps its index into the old list; the next forced
     * sleep (b3BodySetAwake false) then writes through that index, outside
     * the list (met by tests/fuzz_test.c, 2026-11-20: an assert in
     * solver_set.c, a heap write in a Release build). */
    if (!isfinite(dt) || dt < 1.0e-6 || dt > 1.0) return;
    if (substeps < 1) substeps = 1;
    if (substeps > 64) substeps = 64;
    b3World_Step(id, (float)dt, substeps);
    sleep_unsafe_set(id, 0);    /* every awake body's move index is new again */
    sweep_unstable(id);
}

LC_API void b3x_world_set_gravity(int w, double gx, double gy, double gz)
{
    b3WorldId id; b3Vec3 g;
    if (!world_ok(w, &id) || !vec_in(gx, gy, gz, &g)) return;
    b3World_SetGravity(id, g);
}
LC_API const char *b3x_world_gravity(int w)
{
    b3WorldId id;
    if (!world_ok(w, &id)) return text_empty();
    return text_vec(b3World_GetGravity(id));
}
LC_API void b3x_world_enable_sleeping(int w, int flag)
{
    b3WorldId id;
    if (world_ok(w, &id)) b3World_EnableSleeping(id, flag != 0);
}
LC_API int b3x_world_is_sleeping_enabled(int w)
{
    b3WorldId id;
    return world_ok(w, &id) && b3World_IsSleepingEnabled(id) ? 1 : 0;
}
LC_API void b3x_world_enable_continuous(int w, int flag)
{
    b3WorldId id;
    if (world_ok(w, &id)) b3World_EnableContinuous(id, flag != 0);
}
LC_API int b3x_world_is_continuous_enabled(int w)
{
    b3WorldId id;
    return world_ok(w, &id) && b3World_IsContinuousEnabled(id) ? 1 : 0;
}
LC_API void b3x_world_set_restitution_threshold(int w, double v)
{
    b3WorldId id;
    if (world_ok(w, &id) && nonneg(v)) b3World_SetRestitutionThreshold(id, (float)v);
}
LC_API double b3x_world_restitution_threshold(int w)
{
    b3WorldId id;
    return world_ok(w, &id) ? (double)b3World_GetRestitutionThreshold(id) : 0.0;
}
LC_API void b3x_world_set_hit_event_threshold(int w, double v)
{
    b3WorldId id;
    if (world_ok(w, &id) && nonneg(v)) b3World_SetHitEventThreshold(id, (float)v);
}
LC_API double b3x_world_hit_event_threshold(int w)
{
    b3WorldId id;
    return world_ok(w, &id) ? (double)b3World_GetHitEventThreshold(id) : 0.0;
}
LC_API void b3x_world_set_contact_tuning(int w, double hertz, double damping, double speed)
{
    b3WorldId id;
    if (!world_ok(w, &id) || !hertz_ok(hertz) || !ratio_ok(damping) || !nonneg(speed)) return;
    b3World_SetContactTuning(id, (float)hertz, (float)damping, (float)speed);
}
LC_API void b3x_world_set_max_linear_speed(int w, double v)
{
    b3WorldId id;
    if (world_ok(w, &id) && positive(v)) b3World_SetMaximumLinearSpeed(id, (float)v);
}
LC_API double b3x_world_max_linear_speed(int w)
{
    b3WorldId id;
    return world_ok(w, &id) ? (double)b3World_GetMaximumLinearSpeed(id) : 0.0;
}
LC_API void b3x_world_set_worker_count(int w, int workers)
{
    b3WorldId id;
    if (!world_ok(w, &id)) return;
    if (workers < 1) workers = 1;
    if (workers > B3_MAX_WORKERS) workers = B3_MAX_WORKERS;
#if defined(__EMSCRIPTEN__)
    workers = 1;
#endif
    b3World_SetWorkerCount(id, workers);
}
LC_API int b3x_world_worker_count(int w)
{
    b3WorldId id;
    return world_ok(w, &id) ? b3World_GetWorkerCount(id) : 0;
}
LC_API int b3x_world_body_count(int w)
{
    b3WorldId id;
    return world_ok(w, &id) ? b3World_GetCounters(id).bodyCount : 0;
}
LC_API int b3x_world_shape_count(int w)
{
    b3WorldId id;
    return world_ok(w, &id) ? b3World_GetCounters(id).shapeCount : 0;
}
LC_API int b3x_world_joint_count(int w)
{
    b3WorldId id;
    return world_ok(w, &id) ? b3World_GetCounters(id).jointCount : 0;
}
LC_API int b3x_world_contact_count(int w)
{
    b3WorldId id;
    return world_ok(w, &id) ? b3World_GetCounters(id).contactCount : 0;
}
LC_API int b3x_world_awake_body_count(int w)
{
    b3WorldId id;
    return world_ok(w, &id) ? b3World_GetAwakeBodyCount(id) : 0;
}
/* The last step's time in milliseconds, as Box3D measured it. */
LC_API double b3x_world_step_ms(int w)
{
    b3WorldId id;
    return world_ok(w, &id) ? (double)b3World_GetProfile(id).step : 0.0;
}
/* "lx,ly,lz,ux,uy,uz": the box around everything in the world. */
LC_API const char *b3x_world_bounds(int w)
{
    b3WorldId id;
    if (!world_ok(w, &id)) return text_empty();
    b3AABB a = b3World_GetBounds(id);
    double d[6] = { a.lowerBound.x, a.lowerBound.y, a.lowerBound.z,
                    a.upperBound.x, a.upperBound.y, a.upperBound.z };
    return text_of(d, 6);
}
LC_API void b3x_world_explode(int w, double x, double y, double z, double radius, double falloff, double impulse)
{
    b3WorldId id; b3Pos p;
    if (!world_ok(w, &id) || !pos_in(x, y, z, &p)) return;
    if (!nonneg(radius) || !nonneg(falloff) || !fin(impulse)) return;
    b3ExplosionDef d = b3DefaultExplosionDef();
    d.position = p;
    d.radius = (float)radius;
    d.falloff = (float)falloff;
    d.impulsePerArea = (float)impulse;
    b3World_Explode(id, &d);
}

/* ------------------------------------------------------------------ */
/* Bodies                                                              */
/* ------------------------------------------------------------------ */
static int body_create_at(int w, int type, b3Pos p, b3Quat q)
{
    b3WorldId wid;
    if (!world_ok(w, &wid)) return fail("not a world");
    if (type < 0 || type > 2) return fail("body type is 0 (static), 1 (kinematic) or 2 (dynamic)");
    b3BodyDef bd = b3DefaultBodyDef();
    bd.type = (b3BodyType)type;
    bd.position = p;
    bd.rotation = q;
    b3BodyId id = b3CreateBody(wid, &bd);
    if (!b3Body_IsValid(id)) return fail("Box3D could not create the body");
    int h = bodies_add(id);
    if (!h) { b3DestroyBody(id); return fail("out of body handles"); }
    b3Body_SetUserData(id, h2ud(h));
    ok_clear();
    return h;
}

LC_API int b3x_body_create(int w, int type, double x, double y, double z)
{
    b3Pos p;
    if (!pos_in(x, y, z, &p)) return fail("position is not a finite point in range");
    return body_create_at(w, type, p, b3Quat_identity);
}

LC_API int b3x_body_create_rotated(int w, int type, double x, double y, double z,
                                   double qx, double qy, double qz, double qw)
{
    b3Pos p; b3Quat q;
    if (!pos_in(x, y, z, &p)) return fail("position is not a finite point in range");
    if (!quat_in(qx, qy, qz, qw, &q)) return fail("rotation is not a quaternion");
    return body_create_at(w, type, p, q);
}

LC_API void b3x_body_destroy(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) { bodies_free_handle(b); return; }
    /* The body takes its shapes and joints with it. Their handles are read
     * first (the ids are dead afterwards) and released after, so a mesh is
     * freed only once nothing reads it. */
    int ns = b3Body_GetShapeCount(id);
    int nj = b3Body_GetJointCount(id);
    int *hs = NULL;
    int total = 0;
    if (ns + nj > 0) hs = (int *)malloc((size_t)(ns + nj) * sizeof(int));
    if (hs) {
        if (ns > 0) {
            b3ShapeId *sa = (b3ShapeId *)malloc((size_t)ns * sizeof(b3ShapeId));
            if (sa) {
                int got = b3Body_GetShapes(id, sa, ns);
                for (int i = 0; i < got; i++) hs[total++] = shape_handle_of(sa[i]);
                free(sa);
            }
        }
        int shapeEnd = total;
        if (nj > 0) {
            b3JointId *ja = (b3JointId *)malloc((size_t)nj * sizeof(b3JointId));
            if (ja) {
                int got = b3Body_GetJoints(id, ja, nj);
                for (int i = 0; i < got; i++) hs[total++] = joint_handle_of(ja[i]);
                free(ja);
            }
        }
        b3DestroyBody(id);
        for (int i = 0; i < shapeEnd; i++) shape_release_slot(shapes_slot_of(hs[i]));
        for (int i = shapeEnd; i < total; i++) joints_free_handle(hs[i]);
        free(hs);
        bodies_free_handle(b);
        /* An allocation that failed above left some unread: sweep. */
        if (total != ns + nj) retire_dead_handles();
        return;
    }
    b3DestroyBody(id);
    bodies_free_handle(b);
    retire_dead_handles();
}

LC_API int b3x_body_is_valid(int b) { b3BodyId id; return body_ok(b, &id); }

LC_API int b3x_body_type(int b)
{
    b3BodyId id;
    return body_ok(b, &id) ? (int)b3Body_GetType(id) : 0;
}
LC_API void b3x_body_set_type(int b, int type)
{
    b3BodyId id;
    if (!body_ok(b, &id) || type < 0 || type > 2) return;
    b3BodyType was = b3Body_GetType(id);
    if ((b3BodyType)type == was) return;
    sleep_unsafe_set(b3Body_GetWorld(id), 1);   /* the stale move index */
    b3Body_SetType(id, (b3BodyType)type);
    /* A static body's shapes were never weighed (the mass budget): if they
     * are too heavy to move, it stays what it was. */
    if (!body_mass_sane(id)) { b3Body_SetType(id, was); fail(k_too_heavy); }
}
LC_API int b3x_body_world(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return 0;
    b3WorldId wid = b3Body_GetWorld(id);
    for (int i = 0; i < worlds_cnt; i++)
        if (worlds_used[i] && same_world(worlds_arr[i], wid)) return worlds_encode(i);
    return 0;
}

LC_API const char *b3x_body_position(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return text_empty();
    return text_pos(b3Body_GetPosition(id));
}
LC_API double b3x_body_x(int b)
{
    b3BodyId id;
    return body_ok(b, &id) ? (double)b3ToVec3(b3Body_GetPosition(id)).x : 0.0;
}
LC_API double b3x_body_y(int b)
{
    b3BodyId id;
    return body_ok(b, &id) ? (double)b3ToVec3(b3Body_GetPosition(id)).y : 0.0;
}
LC_API double b3x_body_z(int b)
{
    b3BodyId id;
    return body_ok(b, &id) ? (double)b3ToVec3(b3Body_GetPosition(id)).z : 0.0;
}
/* "qx,qy,qz,qw" */
LC_API const char *b3x_body_rotation(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return text_empty();
    return text_quat(b3Body_GetRotation(id));
}
/* "x,y,z,qx,qy,qz,qw" */
LC_API const char *b3x_body_transform(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return text_empty();
    b3Vec3 p = b3ToVec3(b3Body_GetPosition(id));
    b3Quat q = b3Body_GetRotation(id);
    double d[7] = { p.x, p.y, p.z, q.v.x, q.v.y, q.v.z, q.s };
    return text_of(d, 7);
}
/* The rotation as a matrix and the position, 12 items: the body's local x
 * axis in world space (3), its y axis (3), its z axis (3), its position (3).
 * A local point (a,b,c) is at  a * xaxis + b * yaxis + c * zaxis + position,
 * which a script can evaluate for many points with plain arithmetic. */
LC_API const char *b3x_body_matrix(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return text_empty();
    b3Vec3 p = b3ToVec3(b3Body_GetPosition(id));
    b3Quat q = b3Body_GetRotation(id);
    b3Vec3 cx = b3RotateVector(q, v3(1, 0, 0));
    b3Vec3 cy = b3RotateVector(q, v3(0, 1, 0));
    b3Vec3 cz = b3RotateVector(q, v3(0, 0, 1));
    double d[12] = { cx.x, cx.y, cx.z, cy.x, cy.y, cy.z, cz.x, cz.y, cz.z, p.x, p.y, p.z };
    return text_of(d, 12);
}

LC_API void b3x_body_set_transform(int b, double x, double y, double z,
                                   double qx, double qy, double qz, double qw)
{
    b3BodyId id; b3Pos p; b3Quat q;
    if (!body_ok(b, &id) || !pos_in(x, y, z, &p) || !quat_in(qx, qy, qz, qw, &q)) return;
    b3Body_SetTransform(id, p, q);
}
LC_API void b3x_body_set_position(int b, double x, double y, double z)
{
    b3BodyId id; b3Pos p;
    if (!body_ok(b, &id) || !pos_in(x, y, z, &p)) return;
    b3Body_SetTransform(id, p, b3Body_GetRotation(id));
}
LC_API void b3x_body_set_rotation(int b, double qx, double qy, double qz, double qw)
{
    b3BodyId id; b3Quat q;
    if (!body_ok(b, &id) || !quat_in(qx, qy, qz, qw, &q)) return;
    b3Body_SetTransform(id, b3Body_GetPosition(id), q);
}
/* For a kinematic body: the velocity that reaches this transform in dt. */
LC_API void b3x_body_set_target_transform(int b, double x, double y, double z,
                                          double qx, double qy, double qz, double qw,
                                          double dt, int wake)
{
    b3BodyId id; b3WorldTransform t;
    if (!body_ok(b, &id) || !pos_in(x, y, z, &t.p) || !quat_in(qx, qy, qz, qw, &t.q)) return;
    if (!positive(dt)) return;
    b3Body_SetTargetTransform(id, t, (float)dt, wake != 0);
}

LC_API const char *b3x_body_velocity(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return text_empty();
    return text_vec(b3Body_GetLinearVelocity(id));
}
LC_API const char *b3x_body_angular_velocity(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return text_empty();
    return text_vec(b3Body_GetAngularVelocity(id));
}
LC_API double b3x_body_speed(int b)
{
    b3BodyId id;
    return body_ok(b, &id) ? (double)b3Length(b3Body_GetLinearVelocity(id)) : 0.0;
}
LC_API void b3x_body_set_velocity(int b, double vx, double vy, double vz)
{
    b3BodyId id; b3Vec3 v;
    if (!body_ok(b, &id) || !vec_in(vx, vy, vz, &v)) return;
    b3Body_SetLinearVelocity(id, v);
}
LC_API void b3x_body_set_angular_velocity(int b, double wx, double wy, double wz)
{
    b3BodyId id; b3Vec3 v;
    if (!body_ok(b, &id) || !vec_in(wx, wy, wz, &v)) return;
    b3Body_SetAngularVelocity(id, v);
}

LC_API void b3x_body_apply_force(int b, double fx, double fy, double fz,
                                 double px, double py, double pz, int wake)
{
    b3BodyId id; b3Vec3 f; b3Pos p;
    if (!body_ok(b, &id) || !vec_in(fx, fy, fz, &f) || !pos_in(px, py, pz, &p)) return;
    b3Body_ApplyForce(id, f, p, wake != 0);
}
LC_API void b3x_body_apply_force_to_center(int b, double fx, double fy, double fz, int wake)
{
    b3BodyId id; b3Vec3 f;
    if (!body_ok(b, &id) || !vec_in(fx, fy, fz, &f)) return;
    b3Body_ApplyForceToCenter(id, f, wake != 0);
}
LC_API void b3x_body_apply_torque(int b, double tx, double ty, double tz, int wake)
{
    b3BodyId id; b3Vec3 t;
    if (!body_ok(b, &id) || !vec_in(tx, ty, tz, &t)) return;
    b3Body_ApplyTorque(id, t, wake != 0);
}
LC_API void b3x_body_apply_impulse(int b, double ix, double iy, double iz,
                                   double px, double py, double pz, int wake)
{
    b3BodyId id; b3Vec3 imp; b3Pos p;
    if (!body_ok(b, &id) || !vec_in(ix, iy, iz, &imp) || !pos_in(px, py, pz, &p)) return;
    b3Body_ApplyLinearImpulse(id, imp, p, wake != 0);
}
LC_API void b3x_body_apply_impulse_to_center(int b, double ix, double iy, double iz, int wake)
{
    b3BodyId id; b3Vec3 imp;
    if (!body_ok(b, &id) || !vec_in(ix, iy, iz, &imp)) return;
    b3Body_ApplyLinearImpulseToCenter(id, imp, wake != 0);
}
LC_API void b3x_body_apply_angular_impulse(int b, double ix, double iy, double iz, int wake)
{
    b3BodyId id; b3Vec3 imp;
    if (!body_ok(b, &id) || !vec_in(ix, iy, iz, &imp)) return;
    b3Body_ApplyAngularImpulse(id, imp, wake != 0);
}

LC_API double b3x_body_mass(int b)
{
    b3BodyId id;
    return body_ok(b, &id) ? (double)b3Body_GetMass(id) : 0.0;
}
LC_API void b3x_body_apply_mass_from_shapes(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return;
    b3Body_ApplyMassFromShapes(id);
    /* Last resort of the mass budget: densities set one by one with the
     * update put off can add up past it. A body whose mass cannot be
     * computed is made static, which is the one state that needs none. */
    if (!body_mass_sane(id)) { b3Body_SetType(id, b3_staticBody); fail(k_too_heavy); }
}
LC_API const char *b3x_body_local_center(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return text_empty();
    return text_vec(b3Body_GetLocalCenter(id));
}
LC_API const char *b3x_body_world_center(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return text_empty();
    return text_pos(b3Body_GetWorldCenter(id));
}
LC_API const char *b3x_body_local_point(int b, double x, double y, double z)
{
    b3BodyId id; b3Pos p;
    if (!body_ok(b, &id) || !pos_in(x, y, z, &p)) return text_empty();
    return text_vec(b3Body_GetLocalPoint(id, p));
}
LC_API const char *b3x_body_world_point(int b, double x, double y, double z)
{
    b3BodyId id; b3Vec3 v;
    if (!body_ok(b, &id) || !vec_in(x, y, z, &v)) return text_empty();
    return text_pos(b3Body_GetWorldPoint(id, v));
}
LC_API const char *b3x_body_local_vector(int b, double x, double y, double z)
{
    b3BodyId id; b3Vec3 v;
    if (!body_ok(b, &id) || !vec_in(x, y, z, &v)) return text_empty();
    return text_vec(b3Body_GetLocalVector(id, v));
}
LC_API const char *b3x_body_world_vector(int b, double x, double y, double z)
{
    b3BodyId id; b3Vec3 v;
    if (!body_ok(b, &id) || !vec_in(x, y, z, &v)) return text_empty();
    return text_vec(b3Body_GetWorldVector(id, v));
}
LC_API const char *b3x_body_point_velocity(int b, double x, double y, double z)
{
    b3BodyId id; b3Pos p;
    if (!body_ok(b, &id) || !pos_in(x, y, z, &p)) return text_empty();
    return text_vec(b3Body_GetWorldPointVelocity(id, p));
}

LC_API void b3x_body_set_linear_damping(int b, double v)
{
    b3BodyId id;
    if (body_ok(b, &id) && nonneg(v)) b3Body_SetLinearDamping(id, (float)v);
}
LC_API double b3x_body_linear_damping(int b)
{
    b3BodyId id;
    return body_ok(b, &id) ? (double)b3Body_GetLinearDamping(id) : 0.0;
}
LC_API void b3x_body_set_angular_damping(int b, double v)
{
    b3BodyId id;
    if (body_ok(b, &id) && nonneg(v)) b3Body_SetAngularDamping(id, (float)v);
}
LC_API double b3x_body_angular_damping(int b)
{
    b3BodyId id;
    return body_ok(b, &id) ? (double)b3Body_GetAngularDamping(id) : 0.0;
}
LC_API void b3x_body_set_gravity_scale(int b, double v)
{
    b3BodyId id;
    if (body_ok(b, &id) && fin(v)) b3Body_SetGravityScale(id, (float)v);
}
LC_API double b3x_body_gravity_scale(int b)
{
    b3BodyId id;
    return body_ok(b, &id) ? (double)b3Body_GetGravityScale(id) : 0.0;
}
LC_API int b3x_body_is_awake(int b)
{
    b3BodyId id;
    return body_ok(b, &id) && b3Body_IsAwake(id) ? 1 : 0;
}
LC_API void b3x_body_set_awake(int b, int flag)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return;
    if (!flag && sleep_unsafe(b3Body_GetWorld(id))) {
        /* the stale move index: see s_sleepUnsafe */
        fail("step the world once before putting a body to sleep after b3BodyEnable or b3BodySetType");
        return;
    }
    b3Body_SetAwake(id, flag != 0);
    ok_clear();
}
LC_API void b3x_body_enable_sleep(int b, int flag)
{
    b3BodyId id;
    if (body_ok(b, &id)) b3Body_EnableSleep(id, flag != 0);
}
LC_API int b3x_body_is_sleep_enabled(int b)
{
    b3BodyId id;
    return body_ok(b, &id) && b3Body_IsSleepEnabled(id) ? 1 : 0;
}
LC_API void b3x_body_set_sleep_threshold(int b, double v)
{
    b3BodyId id;
    if (body_ok(b, &id) && nonneg(v)) b3Body_SetSleepThreshold(id, (float)v);
}
LC_API double b3x_body_sleep_threshold(int b)
{
    b3BodyId id;
    return body_ok(b, &id) ? (double)b3Body_GetSleepThreshold(id) : 0.0;
}
LC_API int b3x_body_is_enabled(int b)
{
    b3BodyId id;
    return body_ok(b, &id) && b3Body_IsEnabled(id) ? 1 : 0;
}
LC_API void b3x_body_enable(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return;
    sleep_unsafe_set(b3Body_GetWorld(id), 1);   /* the stale move index */
    b3Body_Enable(id);
}
LC_API void b3x_body_disable(int b)
{
    b3BodyId id;
    if (body_ok(b, &id)) b3Body_Disable(id);
}
LC_API void b3x_body_set_bullet(int b, int flag)
{
    b3BodyId id;
    if (body_ok(b, &id)) b3Body_SetBullet(id, flag != 0);
}
LC_API int b3x_body_is_bullet(int b)
{
    b3BodyId id;
    return body_ok(b, &id) && b3Body_IsBullet(id) ? 1 : 0;
}
/* Lock motion along or about the world axes (1 = locked). */
LC_API void b3x_body_set_motion_locks(int b, int lx, int ly, int lz, int ax, int ay, int az)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return;
    b3MotionLocks m;
    m.linearX = lx != 0; m.linearY = ly != 0; m.linearZ = lz != 0;
    m.angularX = ax != 0; m.angularY = ay != 0; m.angularZ = az != 0;
    b3Body_SetMotionLocks(id, m);
    /* Box3D leaves a sleeping body asleep here, so a body unlocked while it
     * rests would hang in the air until something else woke it. */
    b3Body_SetAwake(id, true);
}
/* "lx,ly,lz,ax,ay,az", each 0 or 1 */
LC_API const char *b3x_body_motion_locks(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return text_empty();
    b3MotionLocks m = b3Body_GetMotionLocks(id);
    double d[6] = { m.linearX, m.linearY, m.linearZ, m.angularX, m.angularY, m.angularZ };
    return text_of(d, 6);
}
LC_API void b3x_body_enable_hit_events(int b, int flag)
{
    b3BodyId id;
    if (body_ok(b, &id)) b3Body_EnableHitEvents(id, flag != 0);
}
/* "lx,ly,lz,ux,uy,uz": the box around the body's shapes. */
LC_API const char *b3x_body_aabb(int b)
{
    b3BodyId id;
    if (!body_ok(b, &id)) return text_empty();
    b3AABB a = b3Body_ComputeAABB(id);
    double d[6] = { a.lowerBound.x, a.lowerBound.y, a.lowerBound.z,
                    a.upperBound.x, a.upperBound.y, a.upperBound.z };
    return text_of(d, 6);
}
LC_API int b3x_body_shape_count(int b)
{
    b3BodyId id;
    return body_ok(b, &id) ? b3Body_GetShapeCount(id) : 0;
}
LC_API int b3x_body_joint_count(int b)
{
    b3BodyId id;
    return body_ok(b, &id) ? b3Body_GetJointCount(id) : 0;
}

/* ------------------------------------------------------------------ */
/* A list of handles: the shapes or joints of a body, the visitors of  */
/* a sensor, the shapes touching a body. One list, refilled by each    */
/* call that makes one, read by 1-based index.                         */
/* ------------------------------------------------------------------ */
static int *s_list = NULL;
static int s_listCap = 0;
static int s_listCnt = 0;
static int list_reserve(int n)
{
    if (n <= s_listCap) return 1;
    int nc = s_listCap ? s_listCap : 64;
    while (nc < n) nc *= 2;
    int *p = (int *)realloc(s_list, (size_t)nc * sizeof(int));
    if (!p) return 0;
    s_list = p;
    s_listCap = nc;
    return 1;
}
LC_API int b3x_list_count(void) { return s_listCnt; }
LC_API int b3x_list_item(int index)
{
    return (index >= 1 && index <= s_listCnt) ? s_list[index - 1] : 0;
}

LC_API int b3x_body_list_shapes(int b)
{
    b3BodyId id;
    s_listCnt = 0;
    if (!body_ok(b, &id)) return 0;
    int n = b3Body_GetShapeCount(id);
    if (n <= 0 || !list_reserve(n)) return 0;
    b3ShapeId *sa = (b3ShapeId *)malloc((size_t)n * sizeof(b3ShapeId));
    if (!sa) return 0;
    int got = b3Body_GetShapes(id, sa, n);
    for (int i = 0; i < got; i++) {
        int h = shape_handle_of(sa[i]);
        if (h) s_list[s_listCnt++] = h;
    }
    free(sa);
    return s_listCnt;
}
LC_API int b3x_body_list_joints(int b)
{
    b3BodyId id;
    s_listCnt = 0;
    if (!body_ok(b, &id)) return 0;
    int n = b3Body_GetJointCount(id);
    if (n <= 0 || !list_reserve(n)) return 0;
    b3JointId *ja = (b3JointId *)malloc((size_t)n * sizeof(b3JointId));
    if (!ja) return 0;
    int got = b3Body_GetJoints(id, ja, n);
    for (int i = 0; i < got; i++) {
        int h = joint_handle_of(ja[i]);
        if (h) s_list[s_listCnt++] = h;
    }
    free(ja);
    return s_listCnt;
}
/* The BODIES this body is touching right now (each once). */
LC_API int b3x_body_list_touching(int b)
{
    b3BodyId id;
    s_listCnt = 0;
    if (!body_ok(b, &id)) return 0;
    int n = b3Body_GetContactCapacity(id);
    if (n <= 0 || !list_reserve(n)) return 0;
    b3ContactData *cd = (b3ContactData *)malloc((size_t)n * sizeof(b3ContactData));
    if (!cd) return 0;
    int got = b3Body_GetContactData(id, cd, n);
    for (int i = 0; i < got; i++) {
        int ha = body_handle_of_shape(cd[i].shapeIdA);
        int hb = body_handle_of_shape(cd[i].shapeIdB);
        int other = (ha == b) ? hb : ha;
        if (!other) continue;
        int seen = 0;
        for (int k = 0; k < s_listCnt; k++)
            if (s_list[k] == other) { seen = 1; break; }
        if (!seen) s_list[s_listCnt++] = other;
    }
    free(cd);
    return s_listCnt;
}

/* ------------------------------------------------------------------ */
/* Shape options: what the NEXT shapes are made with, beyond the three */
/* numbers every creator takes. Sticky until reset.                    */
/* ------------------------------------------------------------------ */
static struct {
    int ready;
    int sensor, contactEvents, hitEvents, sensorEvents;
    int hasFilter;
    double category, mask;
    int group;
    double rolling;
} s_opt;

static void opt_reset(void)
{
    b3ShapeDef d = b3DefaultShapeDef();
    s_opt.ready = 1;
    s_opt.sensor = d.isSensor ? 1 : 0;
    s_opt.contactEvents = d.enableContactEvents ? 1 : 0;
    s_opt.hitEvents = d.enableHitEvents ? 1 : 0;
    s_opt.sensorEvents = d.enableSensorEvents ? 1 : 0;
    s_opt.hasFilter = 0;
    s_opt.category = 0; s_opt.mask = 0; s_opt.group = 0;
    s_opt.rolling = (double)d.baseMaterial.rollingResistance;
}
LC_API void b3x_shape_options_reset(void) { opt_reset(); }
LC_API void b3x_shape_options_set_sensor(int flag)
{
    if (!s_opt.ready) opt_reset();
    s_opt.sensor = flag != 0;
}
LC_API void b3x_shape_options_set_events(int contact, int hit, int sensor)
{
    if (!s_opt.ready) opt_reset();
    s_opt.contactEvents = contact != 0;
    s_opt.hitEvents = hit != 0;
    s_opt.sensorEvents = sensor != 0;
}
LC_API void b3x_shape_options_set_filter(double category, double mask, int group)
{
    if (!s_opt.ready) opt_reset();
    if (!bits_ok(category) || !bits_ok(mask)) return;
    s_opt.hasFilter = 1;
    s_opt.category = category; s_opt.mask = mask; s_opt.group = group;
}
LC_API void b3x_shape_options_set_rolling_resistance(double v)
{
    if (!s_opt.ready) opt_reset();
    if (nonneg(v)) s_opt.rolling = v;
}

static int def_in(b3ShapeDef *d, double density, double friction, double restitution)
{
    if (!s_opt.ready) opt_reset();
    if (!nonneg(density) || density > B3X_MAX_DENSITY || !nonneg(friction) || !nonneg(restitution)) return 0;
    *d = b3DefaultShapeDef();
    d->density = (float)density;
    d->baseMaterial.friction = (float)friction;
    d->baseMaterial.restitution = (float)restitution;
    d->baseMaterial.rollingResistance = (float)s_opt.rolling;
    d->isSensor = s_opt.sensor != 0;
    d->enableContactEvents = s_opt.contactEvents != 0;
    d->enableHitEvents = s_opt.hitEvents != 0;
    d->enableSensorEvents = s_opt.sensorEvents != 0;
    if (s_opt.hasFilter) {
        d->filter.categoryBits = (uint64_t)s_opt.category;
        d->filter.maskBits = (uint64_t)s_opt.mask;
        d->filter.groupIndex = s_opt.group;
    }
    return 1;
}

/* Give a new shape its handle (or destroy it when the table is full). */
static int shape_adopt(b3ShapeId id)
{
    if (!b3Shape_IsValid(id)) return fail("Box3D could not create the shape");
    if (!body_mass_sane(b3Shape_GetBody(id))) { b3DestroyShape(id, true); return fail(k_too_heavy); }
    int h = shapes_add(id);
    if (!h) { b3DestroyShape(id, true); return fail("out of shape handles"); }
    if (!owned_reserve(shapes_slot_of(h))) {
        b3DestroyShape(id, true);
        shapes_free_handle(h);
        return fail("out of memory");
    }
    b3Shape_SetUserData(id, h2ud(h));
    ok_clear();
    return h;
}

/* ------------------------------------------------------------------ */
/* The geometry buffers a hull, a mesh and a height field are built    */
/* from: points, triangles (1-based point numbers) and heights.        */
/* ------------------------------------------------------------------ */
static b3Vec3 *s_pts = NULL;
static int s_ptsCap = 0, s_ptsCnt = 0;
static int32_t *s_tris = NULL;
static int s_trisCap = 0, s_trisCnt = 0;      /* counted in indices */
static float *s_vals = NULL;
static int s_valsCap = 0, s_valsCnt = 0;
#define B3X_MAX_BUFFER 4000000

LC_API void b3x_geometry_begin(void)
{
    s_ptsCnt = 0;
    s_trisCnt = 0;
    s_valsCnt = 0;
}
LC_API int b3x_geometry_add_point(double x, double y, double z)
{
    b3Vec3 v;
    if (!local_in(x, y, z, &v)) return 0;
    if (s_ptsCnt >= B3X_MAX_BUFFER) return 0;
    if (s_ptsCnt >= s_ptsCap) {
        int nc = s_ptsCap ? s_ptsCap * 2 : 256;
        b3Vec3 *p = (b3Vec3 *)realloc(s_pts, (size_t)nc * sizeof(b3Vec3));
        if (!p) return 0;
        s_pts = p; s_ptsCap = nc;
    }
    s_pts[s_ptsCnt++] = v;
    return s_ptsCnt;
}
/* One triangle, by 1-based point numbers, counter-clockwise from outside. */
LC_API int b3x_geometry_add_triangle(int p1, int p2, int p3)
{
    if (p1 < 1 || p2 < 1 || p3 < 1) return 0;
    if (s_trisCnt + 3 > B3X_MAX_BUFFER) return 0;
    if (s_trisCnt + 3 > s_trisCap) {
        int nc = s_trisCap ? s_trisCap * 2 : 768;
        int32_t *p = (int32_t *)realloc(s_tris, (size_t)nc * sizeof(int32_t));
        if (!p) return 0;
        s_tris = p; s_trisCap = nc;
    }
    s_tris[s_trisCnt++] = p1 - 1;
    s_tris[s_trisCnt++] = p2 - 1;
    s_tris[s_trisCnt++] = p3 - 1;
    return s_trisCnt / 3;
}
LC_API int b3x_geometry_add_height(double h)
{
    if (!local_ok(h)) return 0;
    if (s_valsCnt >= B3X_MAX_BUFFER) return 0;
    if (s_valsCnt >= s_valsCap) {
        int nc = s_valsCap ? s_valsCap * 2 : 1024;
        float *p = (float *)realloc(s_vals, (size_t)nc * sizeof(float));
        if (!p) return 0;
        s_vals = p; s_valsCap = nc;
    }
    s_vals[s_valsCnt++] = (float)h;
    return s_valsCnt;
}
LC_API int b3x_geometry_point_count(void) { return s_ptsCnt; }

/* ------------------------------------------------------------------ */
/* Shapes                                                              */
/* ------------------------------------------------------------------ */
LC_API int b3x_shape_add_sphere(int b, double cx, double cy, double cz, double radius,
                                double density, double friction, double restitution)
{
    b3BodyId id; b3ShapeDef d; b3Sphere s;
    if (!body_ok(b, &id)) return fail("not a body");
    if (!local_in(cx, cy, cz, &s.center) || !size_ok(radius)) return fail("sphere needs a centre within 10000 and a radius from 0.001 to 10000");
    if (!def_in(&d, density, friction, restitution)) return fail("density, friction and restitution must be 0 or more");
    s.radius = (float)radius;
    if (!mass_fits(id, b3ComputeSphereMass(&s, d.density))) return fail(k_too_heavy);
    return shape_adopt(b3CreateSphereShape(id, &d, &s));
}

LC_API int b3x_shape_add_capsule(int b, double x1, double y1, double z1,
                                 double x2, double y2, double z2, double radius,
                                 double density, double friction, double restitution)
{
    b3BodyId id; b3ShapeDef d; b3Capsule c;
    if (!body_ok(b, &id)) return fail("not a body");
    if (!local_in(x1, y1, z1, &c.center1) || !local_in(x2, y2, z2, &c.center2) || !size_ok(radius))
        return fail("capsule needs two centres within 10000 and a radius from 0.001 to 10000");
    if (b3Length(b3Sub(c.center2, c.center1)) < B3_MIN_CAPSULE_LENGTH)
        return fail("capsule centres are too close: use a sphere");
    if (!def_in(&d, density, friction, restitution)) return fail("density, friction and restitution must be 0 or more");
    c.radius = (float)radius;
    if (!mass_fits(id, b3ComputeCapsuleMass(&c, d.density))) return fail(k_too_heavy);
    return shape_adopt(b3CreateCapsuleShape(id, &d, &c));
}

LC_API int b3x_shape_add_box(int b, double hx, double hy, double hz,
                             double density, double friction, double restitution)
{
    b3BodyId id; b3ShapeDef d;
    if (!body_ok(b, &id)) return fail("not a body");
    if (!size_ok(hx) || !size_ok(hy) || !size_ok(hz)) return fail("box half-sizes must be from 0.001 to 10000");
    if (!def_in(&d, density, friction, restitution)) return fail("density, friction and restitution must be 0 or more");
    b3BoxHull box = b3MakeBoxHull((float)hx, (float)hy, (float)hz);
    if (!mass_fits(id, b3ComputeHullMass(&box.base, d.density))) return fail(k_too_heavy);
    return shape_adopt(b3CreateHullShape(id, &d, &box.base));
}

/* A box placed and turned inside its body. */
LC_API int b3x_shape_add_box_at(int b, double hx, double hy, double hz,
                                double ox, double oy, double oz,
                                double qx, double qy, double qz, double qw,
                                double density, double friction, double restitution)
{
    b3BodyId id; b3ShapeDef d; b3Transform t;
    if (!body_ok(b, &id)) return fail("not a body");
    if (!size_ok(hx) || !size_ok(hy) || !size_ok(hz)) return fail("box half-sizes must be from 0.001 to 10000");
    if (!local_in(ox, oy, oz, &t.p) || !quat_in(qx, qy, qz, qw, &t.q)) return fail("box offset (within 10000) or rotation is not valid");
    if (!def_in(&d, density, friction, restitution)) return fail("density, friction and restitution must be 0 or more");
    b3BoxHull box = b3MakeTransformedBoxHull((float)hx, (float)hy, (float)hz, t);
    if (!mass_fits(id, b3ComputeHullMass(&box.base, d.density))) return fail(k_too_heavy);
    return shape_adopt(b3CreateHullShape(id, &d, &box.base));
}

LC_API int b3x_shape_add_cylinder(int b, double height, double radius, int sides,
                                  double density, double friction, double restitution)
{
    b3BodyId id; b3ShapeDef d;
    if (!body_ok(b, &id)) return fail("not a body");
    if (!size_ok(height) || !size_ok(radius)) return fail("cylinder height and radius must be from 0.001 to 10000");
    if (sides < 3 || sides > 32) return fail("cylinder sides must be 3 to 32");
    if (!def_in(&d, density, friction, restitution)) return fail("density, friction and restitution must be 0 or more");
    /* yOffset centres it: Box3D builds the cylinder from y = offset up. */
    b3HullData *hull = b3CreateCylinder((float)height, (float)radius, (float)(-0.5 * height), sides);
    if (!hull) return fail("Box3D could not build the cylinder");
    if (!mass_fits(id, b3ComputeHullMass(hull, d.density))) { b3DestroyHull(hull); return fail(k_too_heavy); }
    b3ShapeId sid = b3CreateHullShape(id, &d, hull);
    b3DestroyHull(hull);
    return shape_adopt(sid);
}

LC_API int b3x_shape_add_cone(int b, double height, double radius1, double radius2, int sides,
                              double density, double friction, double restitution)
{
    b3BodyId id; b3ShapeDef d;
    if (!body_ok(b, &id)) return fail("not a body");
    /* Box3D asserts BOTH radii above 0 and 4 to 32 sides (hull.c): it builds
     * a truncated cone, and a release build given 0 would build a hull with
     * a ring of coincident points. A point is a small radius. */
    if (!size_ok(height) || !size_ok(radius1) || !size_ok(radius2))
        return fail("cone height and both radii must be from 0.001 to 10000 (use a small radius for a point)");
    if (sides < 4 || sides > 32) return fail("cone sides must be 4 to 32");
    if (!def_in(&d, density, friction, restitution)) return fail("density, friction and restitution must be 0 or more");
    b3HullData *hull = b3CreateCone((float)height, (float)radius1, (float)radius2, sides);
    if (!hull) return fail("Box3D could not build the cone");
    if (!mass_fits(id, b3ComputeHullMass(hull, d.density))) { b3DestroyHull(hull); return fail(k_too_heavy); }
    b3ShapeId sid = b3CreateHullShape(id, &d, hull);
    b3DestroyHull(hull);
    return shape_adopt(sid);
}

/* The convex hull of the points added since b3x_geometry_begin. */
LC_API int b3x_shape_add_hull(int b, double density, double friction, double restitution)
{
    b3BodyId id; b3ShapeDef d;
    if (!body_ok(b, &id)) return fail("not a body");
    if (s_ptsCnt < 4) return fail("a hull needs at least 4 points");
    if (!def_in(&d, density, friction, restitution)) return fail("density, friction and restitution must be 0 or more");
    b3HullData *hull = b3CreateHull(s_pts, s_ptsCnt, B3_MAX_HULL_VERTICES);
    if (!hull) return fail("Box3D could not build a hull from those points (flat, or too complex)");
    if (!mass_fits(id, b3ComputeHullMass(hull, d.density))) { b3DestroyHull(hull); return fail(k_too_heavy); }
    b3ShapeId sid = b3CreateHullShape(id, &d, hull);
    b3DestroyHull(hull);
    return shape_adopt(sid);
}

/* A triangle mesh from the points and triangles added since
 * b3x_geometry_begin. Box3D collides a mesh only on a STATIC body. */
LC_API int b3x_shape_add_mesh(int b, double friction, double restitution)
{
    b3BodyId id; b3ShapeDef d;
    if (!body_ok(b, &id)) return fail("not a body");
    if (b3Body_GetType(id) != b3_staticBody) return fail("a mesh needs a static body");
    int triangles = s_trisCnt / 3;
    if (s_ptsCnt < 3 || triangles < 1) return fail("a mesh needs at least 3 points and 1 triangle");
    for (int i = 0; i < s_trisCnt; i++)
        if (s_tris[i] < 0 || s_tris[i] >= s_ptsCnt) return fail("a triangle names a point that was not added");
    if (!def_in(&d, 0.0, friction, restitution)) return fail("friction and restitution must be 0 or more");
    b3MeshDef md;
    memset(&md, 0, sizeof md);
    md.vertices = s_pts;
    md.stride = sizeof(b3Vec3);
    md.indices = s_tris;
    md.materialIndices = NULL;
    md.vertexCount = s_ptsCnt;
    md.triangleCount = triangles;
    md.weldVertices = false;
    md.useMedianSplit = false;
    md.identifyEdges = true;
    md.clockWiseWinding = false;
    b3MeshData *mesh = b3CreateMesh(&md, NULL, 0);
    if (!mesh) return fail("Box3D could not build the mesh");
    b3ShapeId sid = b3CreateMeshShape(id, &d, mesh, v3(1, 1, 1));
    if (!b3Shape_IsValid(sid)) { b3DestroyMesh(mesh); return fail("Box3D could not create the shape"); }
    int h = shape_adopt(sid);
    if (!h) { b3DestroyMesh(mesh); return 0; }
    int slot = shapes_slot_of(h);
    s_owned[slot] = mesh;
    s_ownedKind[slot] = B3X_OWNED_MESH;
    return h;
}

/* A height field: countX by countZ heights added since b3x_geometry_begin,
 * row by row along x, spaced sx and sz apart, heights multiplied by sy.
 * Static bodies only. */
LC_API int b3x_shape_add_height_field(int b, int countX, int countZ,
                                      double sx, double sy, double sz,
                                      double friction, double restitution)
{
    b3BodyId id; b3ShapeDef d;
    if (!body_ok(b, &id)) return fail("not a body");
    if (b3Body_GetType(id) != b3_staticBody) return fail("a height field needs a static body");
    if (countX < 2 || countZ < 2 || countX > 4096 || countZ > 4096) return fail("a height field is 2 to 4096 points each way");
    if (s_valsCnt != countX * countZ) return fail("the heights added do not number countX * countZ");
    if (!size_ok(sx) || !size_ok(sy) || !size_ok(sz)) return fail("height field scales must be from 0.001 to 10000");
    /* the whole field inside the world Box3D accepts (100 km) */
    if ((countX - 1) * sx > 1.0e5 || (countZ - 1) * sz > 1.0e5) return fail("the height field is wider than 100000");
    if (!def_in(&d, 0.0, friction, restitution)) return fail("friction and restitution must be 0 or more");
    float lo = s_vals[0], hi = s_vals[0];
    for (int i = 1; i < s_valsCnt; i++) {
        if (s_vals[i] < lo) lo = s_vals[i];
        if (s_vals[i] > hi) hi = s_vals[i];
    }
    if (!(hi > lo)) hi = lo + 1.0f;      /* a flat field still needs a range */
    b3HeightFieldDef hd;
    memset(&hd, 0, sizeof hd);
    hd.heights = s_vals;
    hd.materialIndices = NULL;
    hd.scale = v3(sx, sy, sz);
    hd.countX = countX;
    hd.countZ = countZ;
    hd.globalMinimumHeight = lo;
    hd.globalMaximumHeight = hi;
    hd.clockwiseWinding = false;
    b3HeightFieldData *field = b3CreateHeightField(&hd);
    if (!field) return fail("Box3D could not build the height field");
    b3ShapeId sid = b3CreateHeightFieldShape(id, &d, field);
    if (!b3Shape_IsValid(sid)) { b3DestroyHeightField(field); return fail("Box3D could not create the shape"); }
    int h = shape_adopt(sid);
    if (!h) { b3DestroyHeightField(field); return 0; }
    int slot = shapes_slot_of(h);
    s_owned[slot] = field;
    s_ownedKind[slot] = B3X_OWNED_HEIGHT;
    return h;
}

LC_API void b3x_shape_destroy(int s, int updateMass)
{
    b3ShapeId id;
    int slot = shapes_slot_of(s);
    if (slot < 0) return;
    if (shape_ok(s, &id)) b3DestroyShape(id, updateMass != 0);
    shape_release_slot(slot);
}
LC_API int b3x_shape_is_valid(int s) { b3ShapeId id; return shape_ok(s, &id); }
/* 0 capsule, 1 compound, 2 height field, 3 hull, 4 mesh, 5 sphere; -1 = none */
LC_API int b3x_shape_type(int s)
{
    b3ShapeId id;
    return shape_ok(s, &id) ? (int)b3Shape_GetType(id) : -1;
}
LC_API int b3x_shape_body(int s)
{
    b3ShapeId id;
    return shape_ok(s, &id) ? body_handle_of(b3Shape_GetBody(id)) : 0;
}
LC_API int b3x_shape_is_sensor(int s)
{
    b3ShapeId id;
    return shape_ok(s, &id) && b3Shape_IsSensor(id) ? 1 : 0;
}
LC_API void b3x_shape_set_density(int s, double v, int updateMass)
{
    b3ShapeId id;
    if (!shape_ok(s, &id) || !nonneg(v) || v > B3X_MAX_DENSITY) return;
    float was = b3Shape_GetDensity(id);
    b3BodyId body = b3Shape_GetBody(id);
    /* Weigh it at the new density before the body sees it (the mass budget). */
    b3Shape_SetDensity(id, (float)v, false);
    if (!mass_fits(body, b3Shape_ComputeMassData(id))) { b3Shape_SetDensity(id, was, false); fail(k_too_heavy); return; }
    if (updateMass) {
        b3Body_ApplyMassFromShapes(body);
        if (!body_mass_sane(body)) {
            b3Shape_SetDensity(id, was, false);
            b3Body_ApplyMassFromShapes(body);
            fail(k_too_heavy);
        }
    }
}
LC_API double b3x_shape_density(int s)
{
    b3ShapeId id;
    return shape_ok(s, &id) ? (double)b3Shape_GetDensity(id) : 0.0;
}
LC_API void b3x_shape_set_friction(int s, double v)
{
    b3ShapeId id;
    if (shape_ok(s, &id) && nonneg(v)) b3Shape_SetFriction(id, (float)v);
}
LC_API double b3x_shape_friction(int s)
{
    b3ShapeId id;
    return shape_ok(s, &id) ? (double)b3Shape_GetFriction(id) : 0.0;
}
LC_API void b3x_shape_set_restitution(int s, double v)
{
    b3ShapeId id;
    if (shape_ok(s, &id) && nonneg(v)) b3Shape_SetRestitution(id, (float)v);
}
LC_API double b3x_shape_restitution(int s)
{
    b3ShapeId id;
    return shape_ok(s, &id) ? (double)b3Shape_GetRestitution(id) : 0.0;
}
LC_API void b3x_shape_set_rolling_resistance(int s, double v)
{
    b3ShapeId id;
    if (!shape_ok(s, &id) || !nonneg(v)) return;
    b3SurfaceMaterial m = b3Shape_GetSurfaceMaterial(id);
    m.rollingResistance = (float)v;
    b3Shape_SetSurfaceMaterial(id, m);
}
LC_API double b3x_shape_rolling_resistance(int s)
{
    b3ShapeId id;
    return shape_ok(s, &id) ? (double)b3Shape_GetSurfaceMaterial(id).rollingResistance : 0.0;
}
LC_API void b3x_shape_set_filter(int s, double category, double mask, int group)
{
    b3ShapeId id;
    if (!shape_ok(s, &id) || !bits_ok(category) || !bits_ok(mask)) return;
    b3Filter f = b3Shape_GetFilter(id);
    f.categoryBits = (uint64_t)category;
    f.maskBits = (uint64_t)mask;
    f.groupIndex = group;
    b3Shape_SetFilter(id, f, true);
}
/* "category,mask,group". Bits above 2^53 do not survive as numbers. */
LC_API const char *b3x_shape_filter(int s)
{
    b3ShapeId id;
    if (!shape_ok(s, &id)) return text_empty();
    b3Filter f = b3Shape_GetFilter(id);
    snprintf(s_text, sizeof(s_text), "%llu,%llu,%d",
             (unsigned long long)f.categoryBits, (unsigned long long)f.maskBits, f.groupIndex);
    return s_text;
}
LC_API void b3x_shape_enable_contact_events(int s, int flag)
{
    b3ShapeId id;
    if (shape_ok(s, &id)) b3Shape_EnableContactEvents(id, flag != 0);
}
LC_API int b3x_shape_are_contact_events_enabled(int s)
{
    b3ShapeId id;
    return shape_ok(s, &id) && b3Shape_AreContactEventsEnabled(id) ? 1 : 0;
}
LC_API void b3x_shape_enable_hit_events(int s, int flag)
{
    b3ShapeId id;
    if (shape_ok(s, &id)) b3Shape_EnableHitEvents(id, flag != 0);
}
LC_API int b3x_shape_are_hit_events_enabled(int s)
{
    b3ShapeId id;
    return shape_ok(s, &id) && b3Shape_AreHitEventsEnabled(id) ? 1 : 0;
}
LC_API void b3x_shape_enable_sensor_events(int s, int flag)
{
    b3ShapeId id;
    if (shape_ok(s, &id)) b3Shape_EnableSensorEvents(id, flag != 0);
}
LC_API int b3x_shape_are_sensor_events_enabled(int s)
{
    b3ShapeId id;
    return shape_ok(s, &id) && b3Shape_AreSensorEventsEnabled(id) ? 1 : 0;
}
LC_API const char *b3x_shape_aabb(int s)
{
    b3ShapeId id;
    if (!shape_ok(s, &id)) return text_empty();
    b3AABB a = b3Shape_GetAABB(id);
    double d[6] = { a.lowerBound.x, a.lowerBound.y, a.lowerBound.z,
                    a.upperBound.x, a.upperBound.y, a.upperBound.z };
    return text_of(d, 6);
}
LC_API const char *b3x_shape_closest_point(int s, double x, double y, double z)
{
    b3ShapeId id; b3Vec3 v;
    if (!shape_ok(s, &id) || !vec_in(x, y, z, &v)) return text_empty();
    return text_vec(b3Shape_GetClosestPoint(id, v));
}
/* The shapes inside a sensor right now, into the handle list. */
LC_API int b3x_shape_list_sensor_visitors(int s)
{
    b3ShapeId id;
    s_listCnt = 0;
    if (!shape_ok(s, &id) || !b3Shape_IsSensor(id)) return 0;
    int n = b3Shape_GetSensorCapacity(id);
    if (n <= 0 || !list_reserve(n)) return 0;
    b3ShapeId *va = (b3ShapeId *)malloc((size_t)n * sizeof(b3ShapeId));
    if (!va) return 0;
    int got = b3Shape_GetSensorData(id, va, n);
    for (int i = 0; i < got; i++) {
        int h = shape_handle_of(va[i]);
        if (h) s_list[s_listCnt++] = h;
    }
    free(va);
    return s_listCnt;
}

/* ------------------------------------------------------------------ */
/* Queries. One filter, sticky until reset, applies to every query.    */
/* ------------------------------------------------------------------ */
typedef struct {
    int shape;
    float px, py, pz, nx, ny, nz, fraction;
} B3xHit;
static B3xHit *s_hits = NULL;
static int s_hitsCap = 0, s_hitsCnt = 0;
static int s_hitsFailed = 0;
static int s_qfReady = 0;
static b3QueryFilter s_qf;

static b3QueryFilter query_filter(void)
{
    if (!s_qfReady) { s_qf = b3DefaultQueryFilter(); s_qfReady = 1; }
    return s_qf;
}
LC_API void b3x_query_set_filter(double category, double mask)
{
    if (!bits_ok(category) || !bits_ok(mask)) return;
    (void)query_filter();
    s_qf.categoryBits = (uint64_t)category;
    s_qf.maskBits = (uint64_t)mask;
}
LC_API void b3x_query_reset_filter(void) { s_qf = b3DefaultQueryFilter(); s_qfReady = 1; }

static void hit_push(b3ShapeId shapeId, b3Pos point, b3Vec3 normal, float fraction)
{
    int h = shape_handle_of(shapeId);
    if (!h) return;
    if (s_hitsCnt >= s_hitsCap) {
        int nc = s_hitsCap ? s_hitsCap * 2 : 64;
        B3xHit *p = (B3xHit *)realloc(s_hits, (size_t)nc * sizeof(B3xHit));
        if (!p) { s_hitsFailed = 1; return; }
        s_hits = p; s_hitsCap = nc;
    }
    b3Vec3 pt = b3ToVec3(point);
    B3xHit *hit = &s_hits[s_hitsCnt++];
    hit->shape = h;
    hit->px = pt.x; hit->py = pt.y; hit->pz = pt.z;
    hit->nx = normal.x; hit->ny = normal.y; hit->nz = normal.z;
    hit->fraction = fraction;
}
static float cast_all_cb(b3ShapeId shapeId, b3Pos point, b3Vec3 normal, float fraction,
                         uint64_t userMaterialId, int triangleIndex, int childIndex, void *context)
{
    (void)userMaterialId; (void)triangleIndex; (void)childIndex; (void)context;
    hit_push(shapeId, point, normal, fraction);
    return 1.0f;                       /* keep going: collect every hit */
}
static int hit_compare(const void *a, const void *b)
{
    float fa = ((const B3xHit *)a)->fraction, fb = ((const B3xHit *)b)->fraction;
    return (fa > fb) - (fa < fb);
}

/* Cast a ray from (ox,oy,oz) along the translation (dx,dy,dz). Every shape
 * it crosses becomes a hit, nearest first. Returns the count. */
LC_API int b3x_cast_ray(int w, double ox, double oy, double oz, double dx, double dy, double dz)
{
    b3WorldId id; b3Pos o; b3Vec3 d;
    s_hitsCnt = 0; s_hitsFailed = 0;
    if (!world_ok(w, &id) || !pos_in(ox, oy, oz, &o) || !vec_in(dx, dy, dz, &d)) return 0;
    if (!(b3Length(d) > 0.0f)) return 0;
    b3World_CastRay(id, o, d, query_filter(), cast_all_cb, NULL);
    if (s_hitsCnt > 1) qsort(s_hits, (size_t)s_hitsCnt, sizeof(B3xHit), hit_compare);
    return s_hitsCnt;
}
/* The same, keeping only the nearest hit (cheaper). Returns 1 or 0. */
LC_API int b3x_cast_ray_closest(int w, double ox, double oy, double oz, double dx, double dy, double dz)
{
    b3WorldId id; b3Pos o; b3Vec3 d;
    s_hitsCnt = 0; s_hitsFailed = 0;
    if (!world_ok(w, &id) || !pos_in(ox, oy, oz, &o) || !vec_in(dx, dy, dz, &d)) return 0;
    if (!(b3Length(d) > 0.0f)) return 0;
    b3RayResult r = b3World_CastRayClosest(id, o, d, query_filter());
    if (!r.hit) return 0;
    hit_push(r.shapeId, r.point, r.normal, r.fraction);
    return s_hitsCnt;
}
/* Sweep a sphere of the given radius from (ox,oy,oz) along (dx,dy,dz). */
LC_API int b3x_cast_sphere(int w, double ox, double oy, double oz, double radius,
                           double dx, double dy, double dz)
{
    b3WorldId id; b3Pos o; b3Vec3 d;
    s_hitsCnt = 0; s_hitsFailed = 0;
    if (!world_ok(w, &id) || !pos_in(ox, oy, oz, &o) || !vec_in(dx, dy, dz, &d)) return 0;
    if (!positive(radius)) return 0;
    b3Vec3 centre = v3(0, 0, 0);
    b3ShapeProxy proxy;
    proxy.points = &centre;
    proxy.count = 1;
    proxy.radius = (float)radius;
    b3World_CastShape(id, o, &proxy, d, query_filter(), cast_all_cb, NULL);
    if (s_hitsCnt > 1) qsort(s_hits, (size_t)s_hitsCnt, sizeof(B3xHit), hit_compare);
    return s_hitsCnt;
}
LC_API int b3x_hit_count(void) { return s_hitsCnt; }
LC_API int b3x_hit_shape(int index)
{
    return (index >= 1 && index <= s_hitsCnt) ? s_hits[index - 1].shape : 0;
}
LC_API int b3x_hit_body(int index)
{
    if (index < 1 || index > s_hitsCnt) return 0;
    b3ShapeId id;
    return shape_ok(s_hits[index - 1].shape, &id) ? body_handle_of(b3Shape_GetBody(id)) : 0;
}
LC_API double b3x_hit_fraction(int index)
{
    return (index >= 1 && index <= s_hitsCnt) ? (double)s_hits[index - 1].fraction : 0.0;
}
LC_API const char *b3x_hit_point(int index)
{
    if (index < 1 || index > s_hitsCnt) return text_empty();
    const B3xHit *h = &s_hits[index - 1];
    return text_vec(v3(h->px, h->py, h->pz));
}
LC_API const char *b3x_hit_normal(int index)
{
    if (index < 1 || index > s_hitsCnt) return text_empty();
    const B3xHit *h = &s_hits[index - 1];
    return text_vec(v3(h->nx, h->ny, h->nz));
}

static bool overlap_cb(b3ShapeId shapeId, void *context)
{
    (void)context;
    int h = shape_handle_of(shapeId);
    if (!h) return true;
    if (!list_reserve(s_listCnt + 1)) return false;
    s_list[s_listCnt++] = h;
    return true;
}
/* The shapes whose bounding boxes touch this box, into the handle list. */
LC_API int b3x_overlap_aabb(int w, double lx, double ly, double lz, double ux, double uy, double uz)
{
    b3WorldId id; b3AABB a;
    s_listCnt = 0;
    if (!world_ok(w, &id) || !vec_in(lx, ly, lz, &a.lowerBound) || !vec_in(ux, uy, uz, &a.upperBound)) return 0;
    if (!(ux >= lx && uy >= ly && uz >= lz)) return 0;
    b3World_OverlapAABB(id, a, query_filter(), overlap_cb, NULL);
    return s_listCnt;
}
/* The shapes a sphere really overlaps, into the handle list. */
LC_API int b3x_overlap_sphere(int w, double x, double y, double z, double radius)
{
    b3WorldId id; b3Pos o;
    s_listCnt = 0;
    if (!world_ok(w, &id) || !pos_in(x, y, z, &o) || !positive(radius)) return 0;
    b3Vec3 centre = v3(0, 0, 0);
    b3ShapeProxy proxy;
    proxy.points = &centre;
    proxy.count = 1;
    proxy.radius = (float)radius;
    b3World_OverlapShape(id, o, &proxy, query_filter(), overlap_cb, NULL);
    return s_listCnt;
}

/* ------------------------------------------------------------------ */
/* Events: snapshots of what the last step produced. Box3D's arrays    */
/* are only valid until the next step, so each update call copies.     */
/* ------------------------------------------------------------------ */
typedef struct { int a, b; } B3xPair;
typedef struct { int a, b; float px, py, pz, nx, ny, nz, speed; } B3xHitEvent;
typedef struct { int body; float x, y, z, qx, qy, qz, qw; int asleep; } B3xMove;

static B3xPair *s_begin = NULL, *s_end = NULL, *s_senBegin = NULL, *s_senEnd = NULL;
static int s_beginCap = 0, s_endCap = 0, s_senBeginCap = 0, s_senEndCap = 0;
static int s_beginCnt = 0, s_endCnt = 0, s_senBeginCnt = 0, s_senEndCnt = 0;
static B3xHitEvent *s_hitEv = NULL;
static int s_hitEvCap = 0, s_hitEvCnt = 0;
static B3xMove *s_moves = NULL;
static int s_movesCap = 0, s_movesCnt = 0;
static int *s_jointEv = NULL;
static int s_jointEvCap = 0, s_jointEvCnt = 0;

static int pairs_reserve(B3xPair **arr, int *cap, int n)
{
    if (n <= *cap) return 1;
    int nc = *cap ? *cap : 64;
    while (nc < n) nc *= 2;
    B3xPair *p = (B3xPair *)realloc(*arr, (size_t)nc * sizeof(B3xPair));
    if (!p) return 0;
    *arr = p;
    *cap = nc;
    return 1;
}

/* Copy the last step's contact events. Returns begin + end + hit counts. */
LC_API int b3x_world_update_contact_events(int w)
{
    b3WorldId id;
    s_beginCnt = s_endCnt = s_hitEvCnt = 0;
    if (!world_ok(w, &id)) return 0;
    b3ContactEvents ev = b3World_GetContactEvents(id);
    if (ev.beginCount > 0 && pairs_reserve(&s_begin, &s_beginCap, ev.beginCount)) {
        for (int i = 0; i < ev.beginCount; i++) {
            s_begin[s_beginCnt].a = shape_handle_of(ev.beginEvents[i].shapeIdA);
            s_begin[s_beginCnt].b = shape_handle_of(ev.beginEvents[i].shapeIdB);
            s_beginCnt++;
        }
    }
    if (ev.endCount > 0 && pairs_reserve(&s_end, &s_endCap, ev.endCount)) {
        for (int i = 0; i < ev.endCount; i++) {
            /* An end event may name a shape that was just destroyed: 0 then. */
            s_end[s_endCnt].a = shape_handle_of(ev.endEvents[i].shapeIdA);
            s_end[s_endCnt].b = shape_handle_of(ev.endEvents[i].shapeIdB);
            s_endCnt++;
        }
    }
    if (ev.hitCount > 0) {
        if (ev.hitCount > s_hitEvCap) {
            int nc = s_hitEvCap ? s_hitEvCap : 64;
            while (nc < ev.hitCount) nc *= 2;
            B3xHitEvent *p = (B3xHitEvent *)realloc(s_hitEv, (size_t)nc * sizeof(B3xHitEvent));
            if (p) { s_hitEv = p; s_hitEvCap = nc; }
        }
        if (ev.hitCount <= s_hitEvCap) {
            for (int i = 0; i < ev.hitCount; i++) {
                const b3ContactHitEvent *e = &ev.hitEvents[i];
                b3Vec3 pt = b3ToVec3(e->point);
                B3xHitEvent *o = &s_hitEv[s_hitEvCnt++];
                o->a = shape_handle_of(e->shapeIdA);
                o->b = shape_handle_of(e->shapeIdB);
                o->px = pt.x; o->py = pt.y; o->pz = pt.z;
                o->nx = e->normal.x; o->ny = e->normal.y; o->nz = e->normal.z;
                o->speed = e->approachSpeed;
            }
        }
    }
    return s_beginCnt + s_endCnt + s_hitEvCnt;
}
LC_API int b3x_contact_begin_count(void) { return s_beginCnt; }
LC_API int b3x_contact_begin_shape_a(int index) { return (index >= 1 && index <= s_beginCnt) ? s_begin[index - 1].a : 0; }
LC_API int b3x_contact_begin_shape_b(int index) { return (index >= 1 && index <= s_beginCnt) ? s_begin[index - 1].b : 0; }
LC_API int b3x_contact_end_count(void) { return s_endCnt; }
LC_API int b3x_contact_end_shape_a(int index) { return (index >= 1 && index <= s_endCnt) ? s_end[index - 1].a : 0; }
LC_API int b3x_contact_end_shape_b(int index) { return (index >= 1 && index <= s_endCnt) ? s_end[index - 1].b : 0; }
LC_API int b3x_contact_hit_count(void) { return s_hitEvCnt; }
LC_API int b3x_contact_hit_shape_a(int index) { return (index >= 1 && index <= s_hitEvCnt) ? s_hitEv[index - 1].a : 0; }
LC_API int b3x_contact_hit_shape_b(int index) { return (index >= 1 && index <= s_hitEvCnt) ? s_hitEv[index - 1].b : 0; }
LC_API double b3x_contact_hit_speed(int index) { return (index >= 1 && index <= s_hitEvCnt) ? (double)s_hitEv[index - 1].speed : 0.0; }
LC_API const char *b3x_contact_hit_point(int index)
{
    if (index < 1 || index > s_hitEvCnt) return text_empty();
    const B3xHitEvent *e = &s_hitEv[index - 1];
    return text_vec(v3(e->px, e->py, e->pz));
}
LC_API const char *b3x_contact_hit_normal(int index)
{
    if (index < 1 || index > s_hitEvCnt) return text_empty();
    const B3xHitEvent *e = &s_hitEv[index - 1];
    return text_vec(v3(e->nx, e->ny, e->nz));
}

/* Copy the last step's sensor events. Returns begin + end counts. */
LC_API int b3x_world_update_sensor_events(int w)
{
    b3WorldId id;
    s_senBeginCnt = s_senEndCnt = 0;
    if (!world_ok(w, &id)) return 0;
    b3SensorEvents ev = b3World_GetSensorEvents(id);
    if (ev.beginCount > 0 && pairs_reserve(&s_senBegin, &s_senBeginCap, ev.beginCount)) {
        for (int i = 0; i < ev.beginCount; i++) {
            s_senBegin[s_senBeginCnt].a = shape_handle_of(ev.beginEvents[i].sensorShapeId);
            s_senBegin[s_senBeginCnt].b = shape_handle_of(ev.beginEvents[i].visitorShapeId);
            s_senBeginCnt++;
        }
    }
    if (ev.endCount > 0 && pairs_reserve(&s_senEnd, &s_senEndCap, ev.endCount)) {
        for (int i = 0; i < ev.endCount; i++) {
            s_senEnd[s_senEndCnt].a = shape_handle_of(ev.endEvents[i].sensorShapeId);
            s_senEnd[s_senEndCnt].b = shape_handle_of(ev.endEvents[i].visitorShapeId);
            s_senEndCnt++;
        }
    }
    return s_senBeginCnt + s_senEndCnt;
}
LC_API int b3x_sensor_begin_count(void) { return s_senBeginCnt; }
LC_API int b3x_sensor_begin_sensor(int index) { return (index >= 1 && index <= s_senBeginCnt) ? s_senBegin[index - 1].a : 0; }
LC_API int b3x_sensor_begin_visitor(int index) { return (index >= 1 && index <= s_senBeginCnt) ? s_senBegin[index - 1].b : 0; }
LC_API int b3x_sensor_end_count(void) { return s_senEndCnt; }
LC_API int b3x_sensor_end_sensor(int index) { return (index >= 1 && index <= s_senEndCnt) ? s_senEnd[index - 1].a : 0; }
LC_API int b3x_sensor_end_visitor(int index) { return (index >= 1 && index <= s_senEndCnt) ? s_senEnd[index - 1].b : 0; }

/* Copy the bodies the last step MOVED (a sleeping or static body is not in
 * the list, which is what makes it cheap to draw from). Returns the count. */
LC_API int b3x_world_update_moves(int w)
{
    b3WorldId id;
    s_movesCnt = 0;
    if (!world_ok(w, &id)) return 0;
    b3BodyEvents ev = b3World_GetBodyEvents(id);
    if (ev.moveCount <= 0) return 0;
    if (ev.moveCount > s_movesCap) {
        int nc = s_movesCap ? s_movesCap : 64;
        while (nc < ev.moveCount) nc *= 2;
        B3xMove *p = (B3xMove *)realloc(s_moves, (size_t)nc * sizeof(B3xMove));
        if (!p) return 0;
        s_moves = p; s_movesCap = nc;
    }
    for (int i = 0; i < ev.moveCount; i++) {
        const b3BodyMoveEvent *e = &ev.moveEvents[i];
        int h = ud2h(e->userData);
        if (bodies_slot_of(h) < 0) continue;
        b3Vec3 p = b3ToVec3(e->transform.p);
        B3xMove *m = &s_moves[s_movesCnt++];
        m->body = h;
        m->x = p.x; m->y = p.y; m->z = p.z;
        m->qx = e->transform.q.v.x; m->qy = e->transform.q.v.y; m->qz = e->transform.q.v.z;
        m->qw = e->transform.q.s;
        m->asleep = e->fellAsleep ? 1 : 0;
    }
    return s_movesCnt;
}
LC_API int b3x_move_count(void) { return s_movesCnt; }
LC_API int b3x_move_body(int index) { return (index >= 1 && index <= s_movesCnt) ? s_moves[index - 1].body : 0; }
LC_API int b3x_move_fell_asleep(int index) { return (index >= 1 && index <= s_movesCnt) ? s_moves[index - 1].asleep : 0; }
/* "x,y,z,qx,qy,qz,qw" */
LC_API const char *b3x_move_transform(int index)
{
    if (index < 1 || index > s_movesCnt) return text_empty();
    const B3xMove *m = &s_moves[index - 1];
    double d[7] = { m->x, m->y, m->z, m->qx, m->qy, m->qz, m->qw };
    return text_of(d, 7);
}
/* Every move in one text, one line per body:
 * "body,x,y,z,qx,qy,qz,qw,fellAsleep". One call for a whole frame. */
LC_API const char *b3x_moves_text(void)
{
    if (!big_reserve(s_movesCnt * 150 + 16)) return text_empty();
    int at = 0;
    for (int i = 0; i < s_movesCnt; i++) {
        const B3xMove *m = &s_moves[i];
        double d[7] = { m->x, m->y, m->z, m->qx, m->qy, m->qz, m->qw };
        if (i) s_big[at++] = '\n';
        at += snprintf(s_big + at, (size_t)(s_bigCap - at), "%d", m->body);
        for (int k = 0; k < 7; k++) {
            s_big[at++] = ',';
            at += num_text(s_big + at, s_bigCap - at, d[k]);
        }
        at += snprintf(s_big + at, (size_t)(s_bigCap - at), ",%d", m->asleep);
    }
    s_big[at] = 0;
    return s_big;
}

/* Copy the joints whose force or torque passed their threshold last step. */
LC_API int b3x_world_update_joint_events(int w)
{
    b3WorldId id;
    s_jointEvCnt = 0;
    if (!world_ok(w, &id)) return 0;
    b3JointEvents ev = b3World_GetJointEvents(id);
    if (ev.count <= 0) return 0;
    if (ev.count > s_jointEvCap) {
        int nc = s_jointEvCap ? s_jointEvCap : 64;
        while (nc < ev.count) nc *= 2;
        int *p = (int *)realloc(s_jointEv, (size_t)nc * sizeof(int));
        if (!p) return 0;
        s_jointEv = p; s_jointEvCap = nc;
    }
    for (int i = 0; i < ev.count; i++) {
        int h = joint_handle_of(ev.jointEvents[i].jointId);
        if (h) s_jointEv[s_jointEvCnt++] = h;
    }
    return s_jointEvCnt;
}
LC_API int b3x_joint_event_count(void) { return s_jointEvCnt; }
LC_API int b3x_joint_event_joint(int index) { return (index >= 1 && index <= s_jointEvCnt) ? s_jointEv[index - 1] : 0; }

/* ------------------------------------------------------------------ */
/* Quaternion helpers, so a script need not carry the algebra.         */
/* ------------------------------------------------------------------ */
/* "qx,qy,qz,qw" for a turn of `radians` about an axis. */
LC_API const char *b3x_quat_from_axis_angle(double ax, double ay, double az, double radians)
{
    b3Vec3 axis;
    if (!dir_in(ax, ay, az, &axis) || !fin(radians)) return text_empty();
    return text_quat(b3MakeQuatFromAxisAngle(axis, (float)radians));
}
/* Turn about x, then y, then z (world axes), in radians. */
LC_API const char *b3x_quat_from_euler(double rx, double ry, double rz)
{
    if (!fin3(rx, ry, rz)) return text_empty();
    b3Quat qx = b3MakeQuatFromAxisAngle(v3(1, 0, 0), (float)rx);
    b3Quat qy = b3MakeQuatFromAxisAngle(v3(0, 1, 0), (float)ry);
    b3Quat qz = b3MakeQuatFromAxisAngle(v3(0, 0, 1), (float)rz);
    return text_quat(b3NormalizeQuat(b3MulQuat(qz, b3MulQuat(qy, qx))));
}
/* a then... the product a * b: apply b first, then a. */
LC_API const char *b3x_quat_multiply(double ax, double ay, double az, double aw,
                                     double bx, double by, double bz, double bw)
{
    b3Quat a, b;
    if (!quat_in(ax, ay, az, aw, &a) || !quat_in(bx, by, bz, bw, &b)) return text_empty();
    return text_quat(b3NormalizeQuat(b3MulQuat(a, b)));
}
LC_API const char *b3x_quat_rotate(double qx, double qy, double qz, double qw,
                                   double x, double y, double z)
{
    b3Quat q; b3Vec3 v;
    if (!quat_in(qx, qy, qz, qw, &q) || !vec_in(x, y, z, &v)) return text_empty();
    return text_vec(b3RotateVector(q, v));
}
/* "ax,ay,az,radians" */
LC_API const char *b3x_quat_to_axis_angle(double qx, double qy, double qz, double qw)
{
    b3Quat q;
    if (!quat_in(qx, qy, qz, qw, &q)) return text_empty();
    float radians = 0.0f;
    b3Vec3 axis = b3GetAxisAngle(&radians, q);
    double d[4] = { axis.x, axis.y, axis.z, radians };
    return text_of(d, 4);
}

/* ------------------------------------------------------------------ */
/* Joints. Creators take WORLD points and axes and work out each       */
/* body's local frame, so a script places a hinge where it sees it.    */
/* ------------------------------------------------------------------ */
/* The world rotation whose z axis is `zAxis` (and any x, y around it). */
static b3Quat quat_z_to(b3Vec3 zAxis)
{
    return b3ComputeQuatBetweenUnitVectors(v3(0, 0, 1), zAxis);
}
static b3Quat quat_x_to(b3Vec3 xAxis)
{
    return b3ComputeQuatBetweenUnitVectors(v3(1, 0, 0), xAxis);
}
/* A world frame (point, rotation) as seen from a body. */
static b3Transform local_frame(b3BodyId body, b3Pos point, b3Quat worldQ)
{
    b3Transform t;
    t.p = b3Body_GetLocalPoint(body, point);
    t.q = b3NormalizeQuat(b3InvMulQuat(b3Body_GetRotation(body), worldQ));
    return t;
}
static int joint_bodies(int w, int ba, int bb, b3WorldId *wid, b3BodyId *a, b3BodyId *b)
{
    if (!world_ok(w, wid)) return fail("not a world");
    if (!body_ok(ba, a) || !body_ok(bb, b)) return fail("not a body");
    if (ba == bb) return fail("a joint needs two different bodies");
    b3WorldId wa = b3Body_GetWorld(*a), wb = b3Body_GetWorld(*b);
    if (!same_world(wa, *wid) || !same_world(wb, *wid)) return fail("the bodies are not in that world");
    return 1;
}
static void joint_base(b3JointDef *base, b3BodyId a, b3BodyId b, b3Pos point, b3Quat worldQ, int collide)
{
    base->bodyIdA = a;
    base->bodyIdB = b;
    base->localFrameA = local_frame(a, point, worldQ);
    base->localFrameB = local_frame(b, point, worldQ);
    base->collideConnected = collide != 0;
}
static int joint_adopt(b3JointId id)
{
    if (!b3Joint_IsValid(id)) return fail("Box3D could not create the joint");
    int h = joints_add(id);
    if (!h) { b3DestroyJoint(id, true); return fail("out of joint handles"); }
    b3Joint_SetUserData(id, h2ud(h));
    ok_clear();
    return h;
}

/* A hinge at a world point, turning about a world axis. */
LC_API int b3x_joint_revolute(int w, int ba, int bb, double px, double py, double pz,
                              double ax, double ay, double az, int collide)
{
    b3WorldId wid; b3BodyId a, b; b3Pos p; b3Vec3 axis;
    if (!joint_bodies(w, ba, bb, &wid, &a, &b)) return 0;
    if (!pos_in(px, py, pz, &p) || !dir_in(ax, ay, az, &axis)) return fail("the pivot or the axis is not valid");
    b3RevoluteJointDef d = b3DefaultRevoluteJointDef();
    joint_base(&d.base, a, b, p, quat_z_to(axis), collide);
    return joint_adopt(b3CreateRevoluteJoint(wid, &d));
}
/* A slider through a world point, along a world axis. */
LC_API int b3x_joint_prismatic(int w, int ba, int bb, double px, double py, double pz,
                               double ax, double ay, double az, int collide)
{
    b3WorldId wid; b3BodyId a, b; b3Pos p; b3Vec3 axis;
    if (!joint_bodies(w, ba, bb, &wid, &a, &b)) return 0;
    if (!pos_in(px, py, pz, &p) || !dir_in(ax, ay, az, &axis)) return fail("the point or the axis is not valid");
    b3PrismaticJointDef d = b3DefaultPrismaticJointDef();
    joint_base(&d.base, a, b, p, quat_x_to(axis), collide);
    return joint_adopt(b3CreatePrismaticJoint(wid, &d));
}
/* A ball and socket at a world point. The axis is the one the cone and
 * twist limits are measured about. */
LC_API int b3x_joint_spherical(int w, int ba, int bb, double px, double py, double pz,
                               double ax, double ay, double az, int collide)
{
    b3WorldId wid; b3BodyId a, b; b3Pos p; b3Vec3 axis;
    if (!joint_bodies(w, ba, bb, &wid, &a, &b)) return 0;
    if (!pos_in(px, py, pz, &p) || !dir_in(ax, ay, az, &axis)) return fail("the pivot or the axis is not valid");
    b3SphericalJointDef d = b3DefaultSphericalJointDef();
    joint_base(&d.base, a, b, p, quat_z_to(axis), collide);
    return joint_adopt(b3CreateSphericalJoint(wid, &d));
}
/* Glue two bodies together as they stand, about a world point. */
LC_API int b3x_joint_weld(int w, int ba, int bb, double px, double py, double pz, int collide)
{
    b3WorldId wid; b3BodyId a, b; b3Pos p;
    if (!joint_bodies(w, ba, bb, &wid, &a, &b)) return 0;
    if (!pos_in(px, py, pz, &p)) return fail("the point is not valid");
    b3WeldJointDef d = b3DefaultWeldJointDef();
    joint_base(&d.base, a, b, p, b3Quat_identity, collide);
    return joint_adopt(b3CreateWeldJoint(wid, &d));
}
/* A rod (or, with a spring, a rope) between a world point on each body. */
LC_API int b3x_joint_distance(int w, int ba, int bb, double ax, double ay, double az,
                              double bx, double by, double bz, int collide)
{
    b3WorldId wid; b3BodyId a, b; b3Pos pa, pb;
    if (!joint_bodies(w, ba, bb, &wid, &a, &b)) return 0;
    if (!pos_in(ax, ay, az, &pa) || !pos_in(bx, by, bz, &pb)) return fail("an anchor is not valid");
    b3DistanceJointDef d = b3DefaultDistanceJointDef();
    d.base.bodyIdA = a;
    d.base.bodyIdB = b;
    d.base.localFrameA.p = b3Body_GetLocalPoint(a, pa);
    d.base.localFrameA.q = b3Quat_identity;
    d.base.localFrameB.p = b3Body_GetLocalPoint(b, pb);
    d.base.localFrameB.q = b3Quat_identity;
    d.base.collideConnected = collide != 0;
    float len = b3Length(b3SubPos(pb, pa));
    if (len < B3_LINEAR_SLOP) len = B3_LINEAR_SLOP;
    d.length = len;
    d.minLength = len;
    d.maxLength = len;
    return joint_adopt(b3CreateDistanceJoint(wid, &d));
}
/* A wheel: body A is the chassis, body B the wheel. The wheel spins about
 * the spin axis and travels (and steers) along the suspension axis. */
LC_API int b3x_joint_wheel(int w, int ba, int bb, double px, double py, double pz,
                           double ux, double uy, double uz,
                           double sx, double sy, double sz, int collide)
{
    b3WorldId wid; b3BodyId a, b; b3Pos p; b3Vec3 up, spin;
    if (!joint_bodies(w, ba, bb, &wid, &a, &b)) return 0;
    if (!pos_in(px, py, pz, &p) || !dir_in(ux, uy, uz, &up) || !dir_in(sx, sy, sz, &spin))
        return fail("the point or an axis is not valid");
    /* One frame for both bodies: x = suspension, z = spin made square to it. */
    b3Vec3 z = b3Sub(spin, b3MulSV(b3Dot(spin, up), up));
    float zl = b3Length(z);
    if (zl < 1.0e-4f) return fail("the spin axis must not be along the suspension axis");
    z = b3MulSV(1.0f / zl, z);
    b3Matrix3 m;
    m.cx = up;
    m.cy = b3Cross(z, up);
    m.cz = z;
    b3Quat q = b3NormalizeQuat(b3MakeQuatFromMatrix(&m));
    b3WheelJointDef d = b3DefaultWheelJointDef();
    joint_base(&d.base, a, b, p, q, collide);
    return joint_adopt(b3CreateWheelJoint(wid, &d));
}
/* Drive body B's velocity relative to body A (0 holds it still). */
LC_API int b3x_joint_motor(int w, int ba, int bb, int collide)
{
    b3WorldId wid; b3BodyId a, b;
    if (!joint_bodies(w, ba, bb, &wid, &a, &b)) return 0;
    b3MotorJointDef d = b3DefaultMotorJointDef();
    d.base.bodyIdA = a;
    d.base.bodyIdB = b;
    d.base.collideConnected = collide != 0;
    return joint_adopt(b3CreateMotorJoint(wid, &d));
}
/* Keep a world axis of body B parallel to the same axis of body A, with a
 * spring: what holds a character upright. */
LC_API int b3x_joint_parallel(int w, int ba, int bb, double ax, double ay, double az, int collide)
{
    b3WorldId wid; b3BodyId a, b; b3Vec3 axis;
    if (!joint_bodies(w, ba, bb, &wid, &a, &b)) return 0;
    if (!dir_in(ax, ay, az, &axis)) return fail("the axis is not valid");
    b3ParallelJointDef d = b3DefaultParallelJointDef();
    joint_base(&d.base, a, b, b3Body_GetPosition(b), quat_z_to(axis), collide);
    return joint_adopt(b3CreateParallelJoint(wid, &d));
}
/* Stop two bodies colliding with each other, and nothing else. */
LC_API int b3x_joint_filter(int w, int ba, int bb)
{
    b3WorldId wid; b3BodyId a, b;
    if (!joint_bodies(w, ba, bb, &wid, &a, &b)) return 0;
    b3FilterJointDef d = b3DefaultFilterJointDef();
    d.base.bodyIdA = a;
    d.base.bodyIdB = b;
    return joint_adopt(b3CreateFilterJoint(wid, &d));
}

LC_API void b3x_joint_destroy(int j, int wake)
{
    b3JointId id;
    if (joint_ok(j, &id)) b3DestroyJoint(id, wake != 0);
    joints_free_handle(j);
}
LC_API int b3x_joint_is_valid(int j) { b3JointId id; return joint_ok(j, &id); }
/* 0 parallel, 1 distance, 2 filter, 3 motor, 4 prismatic, 5 revolute,
 * 6 spherical, 7 weld, 8 wheel; -1 = none */
LC_API int b3x_joint_type(int j)
{
    b3JointId id;
    return joint_ok(j, &id) ? (int)b3Joint_GetType(id) : -1;
}
LC_API int b3x_joint_body_a(int j)
{
    b3JointId id;
    return joint_ok(j, &id) ? body_handle_of(b3Joint_GetBodyA(id)) : 0;
}
LC_API int b3x_joint_body_b(int j)
{
    b3JointId id;
    return joint_ok(j, &id) ? body_handle_of(b3Joint_GetBodyB(id)) : 0;
}
LC_API void b3x_joint_set_collide_connected(int j, int flag)
{
    b3JointId id;
    if (joint_ok(j, &id)) b3Joint_SetCollideConnected(id, flag != 0);
}
LC_API int b3x_joint_collide_connected(int j)
{
    b3JointId id;
    return joint_ok(j, &id) && b3Joint_GetCollideConnected(id) ? 1 : 0;
}
LC_API void b3x_joint_wake_bodies(int j)
{
    b3JointId id;
    if (joint_ok(j, &id)) b3Joint_WakeBodies(id);
}
/* "x,y,z,qx,qy,qz,qw": the joint's frame in body A's (or B's) space. */
LC_API const char *b3x_joint_local_frame_a(int j)
{
    b3JointId id;
    if (!joint_ok(j, &id)) return text_empty();
    b3Transform t = b3Joint_GetLocalFrameA(id);
    double d[7] = { t.p.x, t.p.y, t.p.z, t.q.v.x, t.q.v.y, t.q.v.z, t.q.s };
    return text_of(d, 7);
}
LC_API const char *b3x_joint_local_frame_b(int j)
{
    b3JointId id;
    if (!joint_ok(j, &id)) return text_empty();
    b3Transform t = b3Joint_GetLocalFrameB(id);
    double d[7] = { t.p.x, t.p.y, t.p.z, t.q.v.x, t.q.v.y, t.q.v.z, t.q.s };
    return text_of(d, 7);
}
LC_API void b3x_joint_set_local_frame_a(int j, double x, double y, double z,
                                        double qx, double qy, double qz, double qw)
{
    b3JointId id; b3Transform t;
    if (!joint_ok(j, &id) || !vec_in(x, y, z, &t.p) || !quat_in(qx, qy, qz, qw, &t.q)) return;
    b3Joint_SetLocalFrameA(id, t);
}
LC_API void b3x_joint_set_local_frame_b(int j, double x, double y, double z,
                                        double qx, double qy, double qz, double qw)
{
    b3JointId id; b3Transform t;
    if (!joint_ok(j, &id) || !vec_in(x, y, z, &t.p) || !quat_in(qx, qy, qz, qw, &t.q)) return;
    b3Joint_SetLocalFrameB(id, t);
}
/* The force and torque the joint is applying, as vectors. */
LC_API const char *b3x_joint_constraint_force(int j)
{
    b3JointId id;
    if (!joint_ok(j, &id)) return text_empty();
    return text_vec(b3Joint_GetConstraintForce(id));
}
LC_API const char *b3x_joint_constraint_torque(int j)
{
    b3JointId id;
    if (!joint_ok(j, &id)) return text_empty();
    return text_vec(b3Joint_GetConstraintTorque(id));
}
LC_API double b3x_joint_linear_separation(int j)
{
    b3JointId id;
    /* Box3D has not written this for a wheel joint yet (a "todo" that
     * asserts in joint.c): 0 until it has. */
    if (!joint_ok(j, &id) || b3Joint_GetType(id) == b3_wheelJoint) return 0.0;
    return (double)b3Joint_GetLinearSeparation(id);
}
LC_API double b3x_joint_angular_separation(int j)
{
    b3JointId id;
    if (!joint_ok(j, &id) || b3Joint_GetType(id) == b3_wheelJoint) return 0.0;   /* as above */
    return (double)b3Joint_GetAngularSeparation(id);
}
/* A joint event fires when the joint's force or torque passes these. */
LC_API void b3x_joint_set_force_threshold(int j, double v)
{
    b3JointId id;
    if (joint_ok(j, &id) && nonneg(v)) b3Joint_SetForceThreshold(id, (float)v);
}
LC_API double b3x_joint_force_threshold(int j)
{
    b3JointId id;
    return joint_ok(j, &id) ? (double)b3Joint_GetForceThreshold(id) : 0.0;
}
LC_API void b3x_joint_set_torque_threshold(int j, double v)
{
    b3JointId id;
    if (joint_ok(j, &id) && nonneg(v)) b3Joint_SetTorqueThreshold(id, (float)v);
}
LC_API double b3x_joint_torque_threshold(int j)
{
    b3JointId id;
    return joint_ok(j, &id) ? (double)b3Joint_GetTorqueThreshold(id) : 0.0;
}

/* Vector-valued joint settings (the scalar ones are the families below). */
LC_API void b3x_motor_set_linear_velocity(int j, double vx, double vy, double vz)
{
    b3JointId id; b3Vec3 v;
    if (!joint_typed(j, b3_motorJoint, &id) || !vec_in(vx, vy, vz, &v)) return;
    b3MotorJoint_SetLinearVelocity(id, v);
}
LC_API const char *b3x_motor_linear_velocity(int j)
{
    b3JointId id;
    if (!joint_typed(j, b3_motorJoint, &id)) return text_empty();
    return text_vec(b3MotorJoint_GetLinearVelocity(id));
}
LC_API void b3x_motor_set_angular_velocity(int j, double wx, double wy, double wz)
{
    b3JointId id; b3Vec3 v;
    if (!joint_typed(j, b3_motorJoint, &id) || !vec_in(wx, wy, wz, &v)) return;
    b3MotorJoint_SetAngularVelocity(id, v);
}
LC_API const char *b3x_motor_angular_velocity(int j)
{
    b3JointId id;
    if (!joint_typed(j, b3_motorJoint, &id)) return text_empty();
    return text_vec(b3MotorJoint_GetAngularVelocity(id));
}
LC_API void b3x_spherical_set_motor_velocity(int j, double wx, double wy, double wz)
{
    b3JointId id; b3Vec3 v;
    if (!joint_typed(j, b3_sphericalJoint, &id) || !vec_in(wx, wy, wz, &v)) return;
    b3SphericalJoint_SetMotorVelocity(id, v);
}
LC_API const char *b3x_spherical_motor_velocity(int j)
{
    b3JointId id;
    if (!joint_typed(j, b3_sphericalJoint, &id)) return text_empty();
    return text_vec(b3SphericalJoint_GetMotorVelocity(id));
}
LC_API const char *b3x_spherical_motor_torque(int j)
{
    b3JointId id;
    if (!joint_typed(j, b3_sphericalJoint, &id)) return text_empty();
    return text_vec(b3SphericalJoint_GetMotorTorque(id));
}
LC_API void b3x_spherical_set_target_rotation(int j, double qx, double qy, double qz, double qw)
{
    b3JointId id; b3Quat q;
    if (!joint_typed(j, b3_sphericalJoint, &id) || !quat_in(qx, qy, qz, qw, &q)) return;
    b3SphericalJoint_SetTargetRotation(id, q);
}
LC_API const char *b3x_spherical_target_rotation(int j)
{
    b3JointId id;
    if (!joint_typed(j, b3_sphericalJoint, &id)) return text_empty();
    return text_quat(b3SphericalJoint_GetTargetRotation(id));
}
/* Two-number settings: limits and ranges. lower must not exceed upper. */
LC_API void b3x_revolute_set_limits(int j, double lower, double upper)
{
    b3JointId id;
    if (!joint_typed(j, b3_revoluteJoint, &id) || !fin(lower) || !fin(upper) || lower > upper) return;
    b3RevoluteJoint_SetLimits(id, (float)lower, (float)upper);
}
LC_API void b3x_prismatic_set_limits(int j, double lower, double upper)
{
    b3JointId id;
    if (!joint_typed(j, b3_prismaticJoint, &id) || !fin(lower) || !fin(upper) || lower > upper) return;
    b3PrismaticJoint_SetLimits(id, (float)lower, (float)upper);
}
LC_API void b3x_spherical_set_twist_limits(int j, double lower, double upper)
{
    b3JointId id;
    if (!joint_typed(j, b3_sphericalJoint, &id) || !fin(lower) || !fin(upper) || lower > upper) return;
    b3SphericalJoint_SetTwistLimits(id, (float)lower, (float)upper);
}
LC_API void b3x_distance_set_length_range(int j, double lower, double upper)
{
    b3JointId id;
    if (!joint_typed(j, b3_distanceJoint, &id) || !nonneg(lower) || !nonneg(upper) || lower > upper) return;
    b3DistanceJoint_SetLengthRange(id, (float)lower, (float)upper);
}
LC_API void b3x_wheel_set_suspension_limits(int j, double lower, double upper)
{
    b3JointId id;
    if (!joint_typed(j, b3_wheelJoint, &id) || !fin(lower) || !fin(upper) || lower > upper) return;
    b3WheelJoint_SetSuspensionLimits(id, (float)lower, (float)upper);
}
LC_API void b3x_wheel_set_steering_limits(int j, double lower, double upper)
{
    b3JointId id;
    if (!joint_typed(j, b3_wheelJoint, &id) || !fin(lower) || !fin(upper) || lower > upper) return;
    b3WheelJoint_SetSteeringLimits(id, (float)lower, (float)upper);
}

/* ------------------------------------------------------------------ */
/* The scalar joint families: one getter or setter per Box3D call,     */
/* each stopped by joint_typed() on a joint of another type.           */
/* ------------------------------------------------------------------ */
/* ---- revolute joint ---- */
LC_API void b3x_revolute_enable_spring(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_revoluteJoint, &id)) b3RevoluteJoint_EnableSpring(id, flag != 0);
}
LC_API int b3x_revolute_is_spring_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_revoluteJoint, &id) && b3RevoluteJoint_IsSpringEnabled(id) ? 1 : 0;
}
LC_API void b3x_revolute_set_spring_hertz(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_revoluteJoint, &id) && hertz_ok(v)) b3RevoluteJoint_SetSpringHertz(id, (float)v);
}
LC_API double b3x_revolute_spring_hertz(int j)
{
    b3JointId id;
    return joint_typed(j, b3_revoluteJoint, &id) ? (double)b3RevoluteJoint_GetSpringHertz(id) : 0.0;
}
LC_API void b3x_revolute_set_spring_damping_ratio(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_revoluteJoint, &id) && ratio_ok(v)) b3RevoluteJoint_SetSpringDampingRatio(id, (float)v);
}
LC_API double b3x_revolute_spring_damping_ratio(int j)
{
    b3JointId id;
    return joint_typed(j, b3_revoluteJoint, &id) ? (double)b3RevoluteJoint_GetSpringDampingRatio(id) : 0.0;
}
LC_API void b3x_revolute_set_target_angle(int j, double v)
{
    b3JointId id;
    /* Box3D takes the spring's target only within one half turn each way. */
    if (joint_typed(j, b3_revoluteJoint, &id) && isfinite(v) && v >= -(double)B3_PI && v <= (double)B3_PI)
        b3RevoluteJoint_SetTargetAngle(id, (float)v);
}
LC_API double b3x_revolute_target_angle(int j)
{
    b3JointId id;
    return joint_typed(j, b3_revoluteJoint, &id) ? (double)b3RevoluteJoint_GetTargetAngle(id) : 0.0;
}
LC_API double b3x_revolute_angle(int j)
{
    b3JointId id;
    return joint_typed(j, b3_revoluteJoint, &id) ? (double)b3RevoluteJoint_GetAngle(id) : 0.0;
}
LC_API void b3x_revolute_enable_limit(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_revoluteJoint, &id)) b3RevoluteJoint_EnableLimit(id, flag != 0);
}
LC_API int b3x_revolute_is_limit_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_revoluteJoint, &id) && b3RevoluteJoint_IsLimitEnabled(id) ? 1 : 0;
}
LC_API double b3x_revolute_lower_limit(int j)
{
    b3JointId id;
    return joint_typed(j, b3_revoluteJoint, &id) ? (double)b3RevoluteJoint_GetLowerLimit(id) : 0.0;
}
LC_API double b3x_revolute_upper_limit(int j)
{
    b3JointId id;
    return joint_typed(j, b3_revoluteJoint, &id) ? (double)b3RevoluteJoint_GetUpperLimit(id) : 0.0;
}
LC_API void b3x_revolute_enable_motor(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_revoluteJoint, &id)) b3RevoluteJoint_EnableMotor(id, flag != 0);
}
LC_API int b3x_revolute_is_motor_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_revoluteJoint, &id) && b3RevoluteJoint_IsMotorEnabled(id) ? 1 : 0;
}
LC_API void b3x_revolute_set_motor_speed(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_revoluteJoint, &id) && fin(v)) b3RevoluteJoint_SetMotorSpeed(id, (float)v);
}
LC_API double b3x_revolute_motor_speed(int j)
{
    b3JointId id;
    return joint_typed(j, b3_revoluteJoint, &id) ? (double)b3RevoluteJoint_GetMotorSpeed(id) : 0.0;
}
LC_API double b3x_revolute_motor_torque(int j)
{
    b3JointId id;
    return joint_typed(j, b3_revoluteJoint, &id) ? (double)b3RevoluteJoint_GetMotorTorque(id) : 0.0;
}
LC_API void b3x_revolute_set_max_motor_torque(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_revoluteJoint, &id) && nonneg(v)) b3RevoluteJoint_SetMaxMotorTorque(id, (float)v);
}
LC_API double b3x_revolute_max_motor_torque(int j)
{
    b3JointId id;
    return joint_typed(j, b3_revoluteJoint, &id) ? (double)b3RevoluteJoint_GetMaxMotorTorque(id) : 0.0;
}

/* ---- prismatic joint ---- */
LC_API void b3x_prismatic_enable_spring(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_prismaticJoint, &id)) b3PrismaticJoint_EnableSpring(id, flag != 0);
}
LC_API int b3x_prismatic_is_spring_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) && b3PrismaticJoint_IsSpringEnabled(id) ? 1 : 0;
}
LC_API void b3x_prismatic_set_spring_hertz(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_prismaticJoint, &id) && hertz_ok(v)) b3PrismaticJoint_SetSpringHertz(id, (float)v);
}
LC_API double b3x_prismatic_spring_hertz(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) ? (double)b3PrismaticJoint_GetSpringHertz(id) : 0.0;
}
LC_API void b3x_prismatic_set_spring_damping_ratio(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_prismaticJoint, &id) && ratio_ok(v)) b3PrismaticJoint_SetSpringDampingRatio(id, (float)v);
}
LC_API double b3x_prismatic_spring_damping_ratio(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) ? (double)b3PrismaticJoint_GetSpringDampingRatio(id) : 0.0;
}
LC_API void b3x_prismatic_set_target_translation(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_prismaticJoint, &id) && fin(v)) b3PrismaticJoint_SetTargetTranslation(id, (float)v);
}
LC_API double b3x_prismatic_target_translation(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) ? (double)b3PrismaticJoint_GetTargetTranslation(id) : 0.0;
}
LC_API void b3x_prismatic_enable_limit(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_prismaticJoint, &id)) b3PrismaticJoint_EnableLimit(id, flag != 0);
}
LC_API int b3x_prismatic_is_limit_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) && b3PrismaticJoint_IsLimitEnabled(id) ? 1 : 0;
}
LC_API double b3x_prismatic_lower_limit(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) ? (double)b3PrismaticJoint_GetLowerLimit(id) : 0.0;
}
LC_API double b3x_prismatic_upper_limit(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) ? (double)b3PrismaticJoint_GetUpperLimit(id) : 0.0;
}
LC_API void b3x_prismatic_enable_motor(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_prismaticJoint, &id)) b3PrismaticJoint_EnableMotor(id, flag != 0);
}
LC_API int b3x_prismatic_is_motor_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) && b3PrismaticJoint_IsMotorEnabled(id) ? 1 : 0;
}
LC_API void b3x_prismatic_set_motor_speed(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_prismaticJoint, &id) && fin(v)) b3PrismaticJoint_SetMotorSpeed(id, (float)v);
}
LC_API double b3x_prismatic_motor_speed(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) ? (double)b3PrismaticJoint_GetMotorSpeed(id) : 0.0;
}
LC_API void b3x_prismatic_set_max_motor_force(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_prismaticJoint, &id) && nonneg(v)) b3PrismaticJoint_SetMaxMotorForce(id, (float)v);
}
LC_API double b3x_prismatic_max_motor_force(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) ? (double)b3PrismaticJoint_GetMaxMotorForce(id) : 0.0;
}
LC_API double b3x_prismatic_motor_force(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) ? (double)b3PrismaticJoint_GetMotorForce(id) : 0.0;
}
LC_API double b3x_prismatic_translation(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) ? (double)b3PrismaticJoint_GetTranslation(id) : 0.0;
}
LC_API double b3x_prismatic_speed(int j)
{
    b3JointId id;
    return joint_typed(j, b3_prismaticJoint, &id) ? (double)b3PrismaticJoint_GetSpeed(id) : 0.0;
}

/* ---- spherical joint ---- */
LC_API void b3x_spherical_enable_cone_limit(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_sphericalJoint, &id)) b3SphericalJoint_EnableConeLimit(id, flag != 0);
}
LC_API int b3x_spherical_is_cone_limit_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_sphericalJoint, &id) && b3SphericalJoint_IsConeLimitEnabled(id) ? 1 : 0;
}
LC_API void b3x_spherical_set_cone_limit(int j, double v)
{
    b3JointId id;
    /* Box3D takes a cone half-angle of 0 to a quarter turn. */
    if (joint_typed(j, b3_sphericalJoint, &id) && isfinite(v) && v >= 0.0 && v <= 0.5 * (double)B3_PI)
        b3SphericalJoint_SetConeLimit(id, (float)v);
}
LC_API double b3x_spherical_cone_limit(int j)
{
    b3JointId id;
    return joint_typed(j, b3_sphericalJoint, &id) ? (double)b3SphericalJoint_GetConeLimit(id) : 0.0;
}
LC_API double b3x_spherical_cone_angle(int j)
{
    b3JointId id;
    return joint_typed(j, b3_sphericalJoint, &id) ? (double)b3SphericalJoint_GetConeAngle(id) : 0.0;
}
LC_API void b3x_spherical_enable_twist_limit(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_sphericalJoint, &id)) b3SphericalJoint_EnableTwistLimit(id, flag != 0);
}
LC_API int b3x_spherical_is_twist_limit_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_sphericalJoint, &id) && b3SphericalJoint_IsTwistLimitEnabled(id) ? 1 : 0;
}
LC_API double b3x_spherical_lower_twist_limit(int j)
{
    b3JointId id;
    return joint_typed(j, b3_sphericalJoint, &id) ? (double)b3SphericalJoint_GetLowerTwistLimit(id) : 0.0;
}
LC_API double b3x_spherical_upper_twist_limit(int j)
{
    b3JointId id;
    return joint_typed(j, b3_sphericalJoint, &id) ? (double)b3SphericalJoint_GetUpperTwistLimit(id) : 0.0;
}
LC_API double b3x_spherical_twist_angle(int j)
{
    b3JointId id;
    return joint_typed(j, b3_sphericalJoint, &id) ? (double)b3SphericalJoint_GetTwistAngle(id) : 0.0;
}
LC_API void b3x_spherical_enable_spring(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_sphericalJoint, &id)) b3SphericalJoint_EnableSpring(id, flag != 0);
}
LC_API int b3x_spherical_is_spring_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_sphericalJoint, &id) && b3SphericalJoint_IsSpringEnabled(id) ? 1 : 0;
}
LC_API void b3x_spherical_set_spring_hertz(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_sphericalJoint, &id) && hertz_ok(v)) b3SphericalJoint_SetSpringHertz(id, (float)v);
}
LC_API double b3x_spherical_spring_hertz(int j)
{
    b3JointId id;
    return joint_typed(j, b3_sphericalJoint, &id) ? (double)b3SphericalJoint_GetSpringHertz(id) : 0.0;
}
LC_API void b3x_spherical_set_spring_damping_ratio(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_sphericalJoint, &id) && ratio_ok(v)) b3SphericalJoint_SetSpringDampingRatio(id, (float)v);
}
LC_API double b3x_spherical_spring_damping_ratio(int j)
{
    b3JointId id;
    return joint_typed(j, b3_sphericalJoint, &id) ? (double)b3SphericalJoint_GetSpringDampingRatio(id) : 0.0;
}
LC_API void b3x_spherical_enable_motor(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_sphericalJoint, &id)) b3SphericalJoint_EnableMotor(id, flag != 0);
}
LC_API int b3x_spherical_is_motor_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_sphericalJoint, &id) && b3SphericalJoint_IsMotorEnabled(id) ? 1 : 0;
}
LC_API void b3x_spherical_set_max_motor_torque(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_sphericalJoint, &id) && nonneg(v)) b3SphericalJoint_SetMaxMotorTorque(id, (float)v);
}
LC_API double b3x_spherical_max_motor_torque(int j)
{
    b3JointId id;
    return joint_typed(j, b3_sphericalJoint, &id) ? (double)b3SphericalJoint_GetMaxMotorTorque(id) : 0.0;
}

/* ---- weld joint ---- */
LC_API void b3x_weld_set_linear_hertz(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_weldJoint, &id) && hertz_ok(v)) b3WeldJoint_SetLinearHertz(id, (float)v);
}
LC_API double b3x_weld_linear_hertz(int j)
{
    b3JointId id;
    return joint_typed(j, b3_weldJoint, &id) ? (double)b3WeldJoint_GetLinearHertz(id) : 0.0;
}
LC_API void b3x_weld_set_linear_damping_ratio(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_weldJoint, &id) && ratio_ok(v)) b3WeldJoint_SetLinearDampingRatio(id, (float)v);
}
LC_API double b3x_weld_linear_damping_ratio(int j)
{
    b3JointId id;
    return joint_typed(j, b3_weldJoint, &id) ? (double)b3WeldJoint_GetLinearDampingRatio(id) : 0.0;
}
LC_API void b3x_weld_set_angular_hertz(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_weldJoint, &id) && hertz_ok(v)) b3WeldJoint_SetAngularHertz(id, (float)v);
}
LC_API double b3x_weld_angular_hertz(int j)
{
    b3JointId id;
    return joint_typed(j, b3_weldJoint, &id) ? (double)b3WeldJoint_GetAngularHertz(id) : 0.0;
}
LC_API void b3x_weld_set_angular_damping_ratio(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_weldJoint, &id) && ratio_ok(v)) b3WeldJoint_SetAngularDampingRatio(id, (float)v);
}
LC_API double b3x_weld_angular_damping_ratio(int j)
{
    b3JointId id;
    return joint_typed(j, b3_weldJoint, &id) ? (double)b3WeldJoint_GetAngularDampingRatio(id) : 0.0;
}

/* ---- distance joint ---- */
LC_API void b3x_distance_set_length(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_distanceJoint, &id) && positive(v)) b3DistanceJoint_SetLength(id, (float)v);
}
LC_API double b3x_distance_length(int j)
{
    b3JointId id;
    return joint_typed(j, b3_distanceJoint, &id) ? (double)b3DistanceJoint_GetLength(id) : 0.0;
}
LC_API void b3x_distance_enable_spring(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_distanceJoint, &id)) b3DistanceJoint_EnableSpring(id, flag != 0);
}
LC_API int b3x_distance_is_spring_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_distanceJoint, &id) && b3DistanceJoint_IsSpringEnabled(id) ? 1 : 0;
}
LC_API void b3x_distance_set_spring_hertz(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_distanceJoint, &id) && hertz_ok(v)) b3DistanceJoint_SetSpringHertz(id, (float)v);
}
LC_API double b3x_distance_spring_hertz(int j)
{
    b3JointId id;
    return joint_typed(j, b3_distanceJoint, &id) ? (double)b3DistanceJoint_GetSpringHertz(id) : 0.0;
}
LC_API void b3x_distance_set_spring_damping_ratio(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_distanceJoint, &id) && ratio_ok(v)) b3DistanceJoint_SetSpringDampingRatio(id, (float)v);
}
LC_API double b3x_distance_spring_damping_ratio(int j)
{
    b3JointId id;
    return joint_typed(j, b3_distanceJoint, &id) ? (double)b3DistanceJoint_GetSpringDampingRatio(id) : 0.0;
}
LC_API void b3x_distance_enable_limit(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_distanceJoint, &id)) b3DistanceJoint_EnableLimit(id, flag != 0);
}
LC_API int b3x_distance_is_limit_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_distanceJoint, &id) && b3DistanceJoint_IsLimitEnabled(id) ? 1 : 0;
}
LC_API double b3x_distance_min_length(int j)
{
    b3JointId id;
    return joint_typed(j, b3_distanceJoint, &id) ? (double)b3DistanceJoint_GetMinLength(id) : 0.0;
}
LC_API double b3x_distance_max_length(int j)
{
    b3JointId id;
    return joint_typed(j, b3_distanceJoint, &id) ? (double)b3DistanceJoint_GetMaxLength(id) : 0.0;
}
LC_API double b3x_distance_current_length(int j)
{
    b3JointId id;
    return joint_typed(j, b3_distanceJoint, &id) ? (double)b3DistanceJoint_GetCurrentLength(id) : 0.0;
}
LC_API void b3x_distance_enable_motor(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_distanceJoint, &id)) b3DistanceJoint_EnableMotor(id, flag != 0);
}
LC_API int b3x_distance_is_motor_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_distanceJoint, &id) && b3DistanceJoint_IsMotorEnabled(id) ? 1 : 0;
}
LC_API void b3x_distance_set_motor_speed(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_distanceJoint, &id) && fin(v)) b3DistanceJoint_SetMotorSpeed(id, (float)v);
}
LC_API double b3x_distance_motor_speed(int j)
{
    b3JointId id;
    return joint_typed(j, b3_distanceJoint, &id) ? (double)b3DistanceJoint_GetMotorSpeed(id) : 0.0;
}
LC_API void b3x_distance_set_max_motor_force(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_distanceJoint, &id) && nonneg(v)) b3DistanceJoint_SetMaxMotorForce(id, (float)v);
}
LC_API double b3x_distance_max_motor_force(int j)
{
    b3JointId id;
    return joint_typed(j, b3_distanceJoint, &id) ? (double)b3DistanceJoint_GetMaxMotorForce(id) : 0.0;
}
LC_API double b3x_distance_motor_force(int j)
{
    b3JointId id;
    return joint_typed(j, b3_distanceJoint, &id) ? (double)b3DistanceJoint_GetMotorForce(id) : 0.0;
}

/* ---- wheel joint ---- */
LC_API void b3x_wheel_enable_suspension(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id)) b3WheelJoint_EnableSuspension(id, flag != 0);
}
LC_API int b3x_wheel_is_suspension_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) && b3WheelJoint_IsSuspensionEnabled(id) ? 1 : 0;
}
LC_API void b3x_wheel_set_suspension_hertz(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id) && hertz_ok(v)) b3WheelJoint_SetSuspensionHertz(id, (float)v);
}
LC_API double b3x_wheel_suspension_hertz(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetSuspensionHertz(id) : 0.0;
}
LC_API void b3x_wheel_set_suspension_damping_ratio(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id) && ratio_ok(v)) b3WheelJoint_SetSuspensionDampingRatio(id, (float)v);
}
LC_API double b3x_wheel_suspension_damping_ratio(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetSuspensionDampingRatio(id) : 0.0;
}
LC_API void b3x_wheel_enable_suspension_limit(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id)) b3WheelJoint_EnableSuspensionLimit(id, flag != 0);
}
LC_API int b3x_wheel_is_suspension_limit_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) && b3WheelJoint_IsSuspensionLimitEnabled(id) ? 1 : 0;
}
LC_API double b3x_wheel_lower_suspension_limit(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetLowerSuspensionLimit(id) : 0.0;
}
LC_API double b3x_wheel_upper_suspension_limit(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetUpperSuspensionLimit(id) : 0.0;
}
LC_API void b3x_wheel_enable_spin_motor(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id)) b3WheelJoint_EnableSpinMotor(id, flag != 0);
}
LC_API int b3x_wheel_is_spin_motor_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) && b3WheelJoint_IsSpinMotorEnabled(id) ? 1 : 0;
}
LC_API void b3x_wheel_set_spin_motor_speed(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id) && fin(v)) b3WheelJoint_SetSpinMotorSpeed(id, (float)v);
}
LC_API double b3x_wheel_spin_motor_speed(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetSpinMotorSpeed(id) : 0.0;
}
LC_API void b3x_wheel_set_max_spin_torque(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id) && nonneg(v)) b3WheelJoint_SetMaxSpinTorque(id, (float)v);
}
LC_API double b3x_wheel_max_spin_torque(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetMaxSpinTorque(id) : 0.0;
}
LC_API double b3x_wheel_spin_speed(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetSpinSpeed(id) : 0.0;
}
LC_API double b3x_wheel_spin_torque(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetSpinTorque(id) : 0.0;
}
LC_API void b3x_wheel_enable_steering(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id)) b3WheelJoint_EnableSteering(id, flag != 0);
}
LC_API int b3x_wheel_is_steering_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) && b3WheelJoint_IsSteeringEnabled(id) ? 1 : 0;
}
LC_API void b3x_wheel_set_steering_hertz(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id) && hertz_ok(v)) b3WheelJoint_SetSteeringHertz(id, (float)v);
}
LC_API double b3x_wheel_steering_hertz(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetSteeringHertz(id) : 0.0;
}
LC_API void b3x_wheel_set_steering_damping_ratio(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id) && ratio_ok(v)) b3WheelJoint_SetSteeringDampingRatio(id, (float)v);
}
LC_API double b3x_wheel_steering_damping_ratio(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetSteeringDampingRatio(id) : 0.0;
}
LC_API void b3x_wheel_set_max_steering_torque(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id) && nonneg(v)) b3WheelJoint_SetMaxSteeringTorque(id, (float)v);
}
LC_API double b3x_wheel_max_steering_torque(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetMaxSteeringTorque(id) : 0.0;
}
LC_API void b3x_wheel_enable_steering_limit(int j, int flag)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id)) b3WheelJoint_EnableSteeringLimit(id, flag != 0);
}
LC_API int b3x_wheel_is_steering_limit_enabled(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) && b3WheelJoint_IsSteeringLimitEnabled(id) ? 1 : 0;
}
LC_API double b3x_wheel_lower_steering_limit(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetLowerSteeringLimit(id) : 0.0;
}
LC_API double b3x_wheel_upper_steering_limit(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetUpperSteeringLimit(id) : 0.0;
}
LC_API void b3x_wheel_set_target_steering_angle(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_wheelJoint, &id) && fin(v)) b3WheelJoint_SetTargetSteeringAngle(id, (float)v);
}
LC_API double b3x_wheel_target_steering_angle(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetTargetSteeringAngle(id) : 0.0;
}
LC_API double b3x_wheel_steering_angle(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetSteeringAngle(id) : 0.0;
}
LC_API double b3x_wheel_steering_torque(int j)
{
    b3JointId id;
    return joint_typed(j, b3_wheelJoint, &id) ? (double)b3WheelJoint_GetSteeringTorque(id) : 0.0;
}

/* ---- motor joint ---- */
LC_API void b3x_motor_set_max_velocity_force(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_motorJoint, &id) && nonneg(v)) b3MotorJoint_SetMaxVelocityForce(id, (float)v);
}
LC_API double b3x_motor_max_velocity_force(int j)
{
    b3JointId id;
    return joint_typed(j, b3_motorJoint, &id) ? (double)b3MotorJoint_GetMaxVelocityForce(id) : 0.0;
}
LC_API void b3x_motor_set_max_velocity_torque(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_motorJoint, &id) && nonneg(v)) b3MotorJoint_SetMaxVelocityTorque(id, (float)v);
}
LC_API double b3x_motor_max_velocity_torque(int j)
{
    b3JointId id;
    return joint_typed(j, b3_motorJoint, &id) ? (double)b3MotorJoint_GetMaxVelocityTorque(id) : 0.0;
}
LC_API void b3x_motor_set_linear_hertz(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_motorJoint, &id) && hertz_ok(v)) b3MotorJoint_SetLinearHertz(id, (float)v);
}
LC_API double b3x_motor_linear_hertz(int j)
{
    b3JointId id;
    return joint_typed(j, b3_motorJoint, &id) ? (double)b3MotorJoint_GetLinearHertz(id) : 0.0;
}
LC_API void b3x_motor_set_linear_damping_ratio(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_motorJoint, &id) && ratio_ok(v)) b3MotorJoint_SetLinearDampingRatio(id, (float)v);
}
LC_API double b3x_motor_linear_damping_ratio(int j)
{
    b3JointId id;
    return joint_typed(j, b3_motorJoint, &id) ? (double)b3MotorJoint_GetLinearDampingRatio(id) : 0.0;
}
LC_API void b3x_motor_set_angular_hertz(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_motorJoint, &id) && hertz_ok(v)) b3MotorJoint_SetAngularHertz(id, (float)v);
}
LC_API double b3x_motor_angular_hertz(int j)
{
    b3JointId id;
    return joint_typed(j, b3_motorJoint, &id) ? (double)b3MotorJoint_GetAngularHertz(id) : 0.0;
}
LC_API void b3x_motor_set_angular_damping_ratio(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_motorJoint, &id) && ratio_ok(v)) b3MotorJoint_SetAngularDampingRatio(id, (float)v);
}
LC_API double b3x_motor_angular_damping_ratio(int j)
{
    b3JointId id;
    return joint_typed(j, b3_motorJoint, &id) ? (double)b3MotorJoint_GetAngularDampingRatio(id) : 0.0;
}
LC_API void b3x_motor_set_max_spring_force(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_motorJoint, &id) && nonneg(v)) b3MotorJoint_SetMaxSpringForce(id, (float)v);
}
LC_API double b3x_motor_max_spring_force(int j)
{
    b3JointId id;
    return joint_typed(j, b3_motorJoint, &id) ? (double)b3MotorJoint_GetMaxSpringForce(id) : 0.0;
}
LC_API void b3x_motor_set_max_spring_torque(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_motorJoint, &id) && nonneg(v)) b3MotorJoint_SetMaxSpringTorque(id, (float)v);
}
LC_API double b3x_motor_max_spring_torque(int j)
{
    b3JointId id;
    return joint_typed(j, b3_motorJoint, &id) ? (double)b3MotorJoint_GetMaxSpringTorque(id) : 0.0;
}

/* ---- parallel joint ---- */
LC_API void b3x_parallel_set_spring_hertz(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_parallelJoint, &id) && hertz_ok(v)) b3ParallelJoint_SetSpringHertz(id, (float)v);
}
LC_API double b3x_parallel_spring_hertz(int j)
{
    b3JointId id;
    return joint_typed(j, b3_parallelJoint, &id) ? (double)b3ParallelJoint_GetSpringHertz(id) : 0.0;
}
LC_API void b3x_parallel_set_spring_damping_ratio(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_parallelJoint, &id) && ratio_ok(v)) b3ParallelJoint_SetSpringDampingRatio(id, (float)v);
}
LC_API double b3x_parallel_spring_damping_ratio(int j)
{
    b3JointId id;
    return joint_typed(j, b3_parallelJoint, &id) ? (double)b3ParallelJoint_GetSpringDampingRatio(id) : 0.0;
}
LC_API void b3x_parallel_set_max_torque(int j, double v)
{
    b3JointId id;
    if (joint_typed(j, b3_parallelJoint, &id) && nonneg(v)) b3ParallelJoint_SetMaxTorque(id, (float)v);
}
LC_API double b3x_parallel_max_torque(int j)
{
    b3JointId id;
    return joint_typed(j, b3_parallelJoint, &id) ? (double)b3ParallelJoint_GetMaxTorque(id) : 0.0;
}
