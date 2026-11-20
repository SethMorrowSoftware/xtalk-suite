/*
 * render3d_shim.c
 * ----------------------------------------------------------------------------
 * render3dxt: a textured 3D software renderer for OpenXTalk (OXT) and the
 * xTalk family, behind a flat C ABI that the xTalk Builder (LCB) foreign
 * function interface can call.
 *
 * WHAT IT IS FOR. A stack has no GPU context and no 3D drawing of its own,
 * and drawing thousands of triangles from script is far too slow (measured
 * on box3dxt's first script-drawn demo, 2026-11-20). So the whole frame is
 * drawn HERE, natively, into a block of pixels in the engine's imageData
 * layout, and the binding hands that block back in ONE call:
 *
 *     set the imageData of image "View" to r3SceneRender(sScene, 640, 480)
 *
 * The renderer is a scanline-free half-space rasterizer: a depth buffer,
 * perspective-correct texture coordinates, per-vertex (Gouraud) lighting
 * from directional and point lights with Blinn-Phong highlights, linear fog,
 * clipping at the near plane, back-face culling, and optional supersampling
 * for smooth edges. Model files are read by fast_obj (OBJ + MTL) and textures
 * by stb_image (PNG, JPEG, BMP, TGA); see render3d_thirdparty.c.
 *
 * THE CONTRACT WITH box3dxt (agreed with that member on 2026-11-20), so one
 * scene simulated by Box3D draws the same in either renderer from the same
 * numbers:
 *   - y is up, distances are metres, right-handed.
 *   - A transform is position plus quaternion, the text "x,y,z,qx,qy,qz,qw"
 *     that b3BodyTransform and b3MoveTransform return; r3SceneApplyMoves
 *     takes b3MovesText() whole ("body,x,y,z,qx,qy,qz,qw,fellAsleep" lines)
 *     and moves every node tagged with that body.
 *   - The camera is eye, target and VERTICAL field of view in degrees (5 to
 *     150); up is world +y, or world -z when the view is within about 2.6
 *     degrees of vertical (|forward.y| > 0.999), which gives the usual map
 *     view looking straight down. "ex,ey,ez,tx,ty,tz,fov" is the text of
 *     b3RenderCamera() and of r3SceneCamera(), and either renderer takes it.
 *   - The near plane is 0.05 m; there is no far plane unless one is set.
 *     "Depth" is metres along the view axis, not along the ray.
 *   - Picture coordinates are continuous, 0-based, origin at the top-left
 *     corner, y down; a pixel's centre is at +0.5. Aspect = width / height.
 *   - Pixels are 4 bytes, 0,R,G,B, rows from the top (imageData).
 *   - A light's direction is the way its light TRAVELS.
 *
 * Conventions kept from the suite's other C shims (box3dxt's is the model):
 *   - Every object is an integer handle, generation-tagged (0 = invalid). A
 *     stale or never-created handle is a harmless no-op: getters answer 0 or
 *     empty and actions do nothing.
 *   - Every real crosses as `double`, every boolean as `int`.
 *   - A result of several numbers crosses as TEXT with a "." decimal point
 *     in every locale, in a static buffer the binding copies at once.
 *   - Every number that comes in is checked (finite, within a stated range)
 *     before it is used. A refused call answers 0 or empty and
 *     r3x_last_error() says why.
 *   - No callback ever reaches script, and the renderer starts no thread.
 *
 * Build: compiled with stb_image and fast_obj into ONE shared library named
 * "render3dxt" (render3dxt.so / .dll / .dylib), or for the web into a static
 * archive. See CMakeLists.txt.
 * ----------------------------------------------------------------------------
 */

#include "stb_image.h"
#include "fast_obj.h"

#include <locale.h>
#include <math.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
    #include <windows.h>
    #define LC_API __declspec(dllexport)
#else
    #include <pthread.h>
    #include <time.h>
    #include <unistd.h>
    #define LC_API __attribute__((visibility("default")))
#endif

/* Bump when the exported ABI changes; src/render3dxt.lcb's checkABI() names
 * the same number and refuses a library that answers another. */
#define R3X_ABI_VERSION 1
#define R3X_VERSION_TEXT "0.1.0"

/* ------------------------------------------------------------------ */
/* Limits. Every size that allocates is bounded, so no argument can    */
/* ask for more memory than a frame of a large window needs.           */
/* ------------------------------------------------------------------ */
#define R3X_MAX_SIDE        4096        /* an output picture, each way   */
#define R3X_MAX_PIXELS      (4096 * 4096) /* supersampled buffer, total */
#define R3X_MAX_SUPERSAMPLE 4
#define R3X_MAX_TEXTURE     8192        /* a texture, each way           */
#define R3X_MAX_VERTICES    4000000     /* one mesh                      */
#define R3X_MAX_TRIANGLES   4000000     /* one mesh                      */
#define R3X_MAX_SLOTS       1024        /* material slots of one mesh    */
#define R3X_MAX_LIGHTS      8           /* lights of one scene           */
#define R3X_MAX_SEGMENTS    256         /* a primitive's tessellation    */
#define R3X_MAX_VALUE       1.0e7       /* any coordinate, metres        */
#define R3X_MIN_SIZE        1.0e-4      /* a primitive's dimension       */
#define R3X_MAX_SIZE        1.0e5
#define R3X_DEFAULT_NEAR    0.05
#define R3X_UP_FALLBACK     0.999       /* |forward.y| above: up is -z   */

/* ------------------------------------------------------------------ */
/* Generic handle tables (box3dxt's, unchanged). Handles are positive  */
/* ints; 0 == invalid. Each packs an 11-bit generation above a 20-bit  */
/* slot number (slot + 1), so a stale handle stays DEAD after its slot */
/* is recycled, and a slot whose generation would wrap is retired.     */
/* ------------------------------------------------------------------ */
#define R3X_H_SLOT_BITS 20
#define R3X_H_SLOT_MASK 0xFFFFF
#define R3X_H_GEN_MASK  0x7FF
#define R3X_H_MAX_SLOTS (R3X_H_SLOT_MASK - 1)

#define DEFINE_TABLE(NAME, TYPE)                                              \
    static TYPE *NAME##_arr = NULL;                                           \
    static unsigned char  *NAME##_used = NULL;                                \
    static unsigned short *NAME##_gen = NULL;                                 \
    static int   NAME##_cap = 0;                                              \
    static int   NAME##_cnt = 0;                                              \
    static int   NAME##_live = 0;                                             \
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
        return (int)(((unsigned)NAME##_gen[idx] << R3X_H_SLOT_BITS)           \
                     | (unsigned)(idx + 1));                                  \
    }                                                                         \
    static int NAME##_slot_of(int h) {                                        \
        if (h <= 0) return -1;                                                \
        int idx = (h & R3X_H_SLOT_MASK) - 1;                                  \
        unsigned gen = ((unsigned)h >> R3X_H_SLOT_BITS) & R3X_H_GEN_MASK;     \
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
            if (NAME##_cnt >= R3X_H_MAX_SLOTS) return 0;                      \
            if (NAME##_cnt >= NAME##_cap) {                                   \
                int nc = NAME##_cap ? NAME##_cap * 2 : 64;                    \
                if (!NAME##_grow_slots(nc)) return 0;                         \
            }                                                                 \
            idx = NAME##_cnt++;                                               \
        }                                                                     \
        NAME##_arr[idx] = v;                                                  \
        NAME##_used[idx] = 1;                                                 \
        NAME##_live++;                                                        \
        return NAME##_encode(idx);                                            \
    }                                                                         \
    static TYPE NAME##_get(int h) {                                           \
        int idx = NAME##_slot_of(h);                                          \
        if (idx < 0) return NULL;                                             \
        return NAME##_arr[idx];                                               \
    }                                                                         \
    static int NAME##_free_handle(int h) {                                    \
        int idx = NAME##_slot_of(h);                                          \
        if (idx < 0) return 0;                                                \
        if (NAME##_freeCnt >= NAME##_freeCap) {                               \
            int nc = NAME##_freeCap ? NAME##_freeCap * 2 : 64;                \
            int *nf = (int *)realloc(NAME##_free, (size_t)nc * sizeof(int));  \
            if (!nf) return 0;                                                \
            NAME##_free = nf; NAME##_freeCap = nc;                            \
        }                                                                     \
        NAME##_arr[idx] = NULL;                                               \
        NAME##_used[idx] = 0;                                                 \
        NAME##_live--;                                                        \
        if (NAME##_gen[idx] >= R3X_H_GEN_MASK) return 1; /* retired */       \
        NAME##_gen[idx] = (unsigned short)(NAME##_gen[idx] + 1);              \
        NAME##_free[NAME##_freeCnt++] = idx;                                  \
        return 1;                                                             \
    }

/* ------------------------------------------------------------------ */
/* The objects                                                         */
/* ------------------------------------------------------------------ */
typedef struct Texture {
    int w, h;
    uint32_t *px;          /* 0xAARRGGBB, rows from the top              */
    int smooth;            /* 1 bilinear, 0 nearest                      */
    int repeat;            /* 1 wrap, 0 clamp to the edge                */
    int owner;             /* the mesh that loaded it, or 0              */
    int pow2;              /* 1 if w and h are both powers of two         */
} Texture;

typedef struct Material {
    float kd[3];           /* base colour, 0..1                          */
    float ke[3];           /* emitted colour, 0..1                       */
    float ks;              /* highlight strength, 0..1                   */
    float shininess;       /* highlight exponent, 1..1000                */
    int texture;           /* texture handle or 0                        */
    int unlit, twoSided, flat, cutout;
    int owner;             /* the mesh that made it, or 0                */
} Material;

typedef struct Mesh {
    int nv, capv;
    float *pos, *nrm, *uv;           /* 3, 3, 2 per vertex              */
    int nt, capt;
    int *tri;                        /* 3 per triangle, 0-based          */
    int *triSlot;                    /* 1 per triangle, 0-based slot     */
    int nslots;
    int *slotMat;                    /* material handle per slot (0 ok)  */
    char **slotName;                 /* OBJ material name, or NULL       */
    char **slotTexName;              /* its map_Kd as written, or NULL   */
    float bmin[3], bmax[3];
    int boundsDirty;
    int *ownedTex; int nOwnedTex;
} Mesh;

typedef struct Node {
    int scene;
    int listIndex;                   /* where it sits in its scene's list */
    int mesh;
    int material;                    /* override, or 0                   */
    double pos[3];
    double rot[4];                   /* qx qy qz qw, unit                */
    double scale[3];
    int visible;
    int tag;
} Node;

#define R3X_LIGHT_DIRECTIONAL 0
#define R3X_LIGHT_POINT       1
typedef struct Light {
    int scene;
    int kind;
    double v[3];                     /* travel direction (unit) or position */
    double color[3];                 /* 0..1                             */
    double intensity;
    double range;                    /* point light: 0 = no limit        */
    int enabled;
} Light;

typedef struct Scene {
    double bg[3], ambient[3];
    int fogOn; double fogColor[3], fogNear, fogFar;
    double eye[3], target[3], fov, nearZ, farZ;   /* farZ 0 = none */
    int ss;
    int *nodes; int nodeCount, nodeCap;
    int lights[R3X_MAX_LIGHTS]; int lightCount;
    unsigned char *frame; size_t frameCap; int frameLen;
    uint32_t *color; float *depth; size_t bufCap;
    int statTris; double statPixels; double statMs;
} Scene;

DEFINE_TABLE(scenes, Scene *)
DEFINE_TABLE(nodes, Node *)
DEFINE_TABLE(meshes, Mesh *)
DEFINE_TABLE(materials, Material *)
DEFINE_TABLE(textures, Texture *)
DEFINE_TABLE(lights, Light *)

/* ------------------------------------------------------------------ */
/* The last refusal, for r3LastError(). A short fixed text, or "".     */
/* ------------------------------------------------------------------ */
static const char *s_error = "";
static int fail(const char *why) { s_error = why; return 0; }
static void ok_clear(void) { s_error = ""; }

static const char *k_bad_handle = "render3dxt: that handle is not alive";
static const char *k_bad_number = "render3dxt: a number is not finite or out of range";
static const char *k_no_memory  = "render3dxt: out of memory";

/* ------------------------------------------------------------------ */
/* Argument checks (the envelope)                                      */
/* ------------------------------------------------------------------ */
static int fin(double v) { return isfinite(v) && fabs(v) <= R3X_MAX_VALUE; }
static int fin3(double a, double b, double c) { return fin(a) && fin(b) && fin(c); }
static int size_ok(double v) { return isfinite(v) && v >= R3X_MIN_SIZE && v <= R3X_MAX_SIZE; }
static int byte_ok(double v) { return isfinite(v) && v >= 0.0 && v <= 255.0; }
static int rgb_ok(double r, double g, double b) { return byte_ok(r) && byte_ok(g) && byte_ok(b); }
static int unit_ok(double v) { return isfinite(v) && v >= 0.0 && v <= 1.0; }

static float clampf(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

/* A quaternion in: finite, not near zero, normalised here. */
static int quat_in(double x, double y, double z, double w, double out[4])
{
    if (!(isfinite(x) && isfinite(y) && isfinite(z) && isfinite(w))) return 0;
    if (fabs(x) > 1e6 || fabs(y) > 1e6 || fabs(z) > 1e6 || fabs(w) > 1e6) return 0;
    double n = sqrt(x * x + y * y + z * z + w * w);
    if (!(n > 1e-9)) return 0;
    out[0] = x / n; out[1] = y / n; out[2] = z / n; out[3] = w / n;
    return 1;
}

/* A direction in: finite, not near zero, normalised here. */
static int dir_in(double x, double y, double z, double out[3])
{
    if (!fin3(x, y, z)) return 0;
    double n = sqrt(x * x + y * y + z * z);
    if (!(n > 1e-9)) return 0;
    out[0] = x / n; out[1] = y / n; out[2] = z / n;
    return 1;
}

/* ------------------------------------------------------------------ */
/* Text results                                                        */
/* ------------------------------------------------------------------ */
static char s_text[1024];

/* One number as text with a "." decimal point in every locale. */
static int num_text(char *out, int cap, double v)
{
    if (!isfinite(v)) v = 0.0;
    if (v == 0.0) v = 0.0;            /* no "-0" */
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
static const char *text_empty(void) { s_text[0] = 0; return s_text; }
static const char *text_str(const char *s)
{
    if (!s) return text_empty();
    size_t n = strlen(s);
    if (n >= sizeof(s_text)) n = sizeof(s_text) - 1;
    memcpy(s_text, s, n);
    s_text[n] = 0;
    return s_text;
}

/* ------------------------------------------------------------------ */
/* Text arguments: numbers read with a "." decimal point whatever the  */
/* locale (strtod obeys setlocale, and a GTK engine calls it). Items   */
/* are separated by commas; spaces and tabs around them are ignored.   */
/* ------------------------------------------------------------------ */
static int parse_num(const char **pp, const char *end, double *out)
{
    const char *p = *pp;
    while (p < end && (*p == ' ' || *p == '\t')) p++;
    int neg = 0;
    if (p < end && (*p == '-' || *p == '+')) { neg = (*p == '-'); p++; }
    double mant = 0.0;
    int digits = 0, scale = 0;
    while (p < end && *p >= '0' && *p <= '9') {
        if (digits < 18) mant = mant * 10.0 + (*p - '0'); else scale++;
        digits++; p++;
    }
    if (p < end && *p == '.') {
        p++;
        while (p < end && *p >= '0' && *p <= '9') {
            if (digits < 18) { mant = mant * 10.0 + (*p - '0'); scale--; }
            digits++; p++;
        }
    }
    if (digits == 0) return 0;
    if (p < end && (*p == 'e' || *p == 'E')) {
        const char *q = p + 1;
        int eneg = 0, e = 0, ed = 0;
        if (q < end && (*q == '-' || *q == '+')) { eneg = (*q == '-'); q++; }
        while (q < end && *q >= '0' && *q <= '9') {
            if (e < 10000) e = e * 10 + (*q - '0');
            ed++; q++;
        }
        if (ed) { scale += eneg ? -e : e; p = q; }
    }
    while (p < end && (*p == ' ' || *p == '\t')) p++;
    if (scale > 400) scale = 400;
    if (scale < -400) scale = -400;
    double v = mant * pow(10.0, (double)scale);
    *out = neg ? -v : v;
    *pp = p;
    return 1;
}

/* Up to `max` comma-separated numbers from [p, end). Returns how many were
 * read, or -1 if an item is not a number. */
static int parse_items(const char *p, const char *end, double *out, int max)
{
    int n = 0;
    while (p < end) {
        if (n >= max) return n;
        if (!parse_num(&p, end, &out[n])) return -1;
        n++;
        if (p < end) {
            if (*p != ',') return -1;
            p++;
        }
    }
    return n;
}

/* ------------------------------------------------------------------ */
/* Milliseconds, for the frame statistics.                             */
/* ------------------------------------------------------------------ */
static double now_ms(void)
{
#if defined(_WIN32)
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart * 1000.0 / (double)f.QuadPart;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec * 1000.0 + (double)ts.tv_nsec / 1.0e6;
#endif
}

/* ------------------------------------------------------------------ */
/* Library                                                             */
/* ------------------------------------------------------------------ */
LC_API int r3x_abi_version(void) { return R3X_ABI_VERSION; }

LC_API const char *r3x_library_version(void)
{
    snprintf(s_text, sizeof(s_text),
             "render3dxt %s ABI %d; stb_image 2.34; fast_obj 1.3",
             R3X_VERSION_TEXT, R3X_ABI_VERSION);
    return s_text;
}

LC_API const char *r3x_last_error(void) { return s_error; }

/* HOW TEXT CROSSES (box3dxt's rule 3). Every text result is a pointer to a
 * buffer this library owns, valid until the next call. The binding declares
 * it a Pointer, never ZStringNative (the engine frees a returned C string),
 * and copies it with the engine's string builder, which needs the length:
 * this. It takes a plain pointer, not a C string: what the binding hands it
 * is the Pointer another export returned. The one export with no public
 * handler over it. */
LC_API int r3x_text_length(const void *text) { return text ? (int)strlen((const char *)text) : 0; }

/* How many objects of each kind are alive, as text:
 * "scenes,nodes,meshes,materials,textures,lights". For leak checks. */
LC_API const char *r3x_live_counts(void)
{
    double d[6] = { scenes_live, nodes_live, meshes_live,
                    materials_live, textures_live, lights_live };
    return text_of(d, 6);
}

/* ================================================================== */
/* Textures                                                            */
/* ================================================================== */
static int texture_adopt(uint32_t *px, int w, int h, int owner)
{
    Texture *t = (Texture *)calloc(1, sizeof(Texture));
    if (!t) { free(px); return fail(k_no_memory); }
    t->w = w; t->h = h; t->px = px; t->smooth = 1; t->repeat = 1; t->owner = owner;
    t->pow2 = ((w & (w - 1)) == 0 && (h & (h - 1)) == 0) ? 1 : 0;
    int hd = textures_add(t);
    if (!hd) { free(px); free(t); return fail(k_no_memory); }
    return hd;
}

/* stb_image's RGBA bytes into the renderer's 0xAARRGGBB words. */
static int texture_from_rgba(unsigned char *rgba, int w, int h, int owner)
{
    if (!rgba) return fail("render3dxt: the picture could not be decoded");
    if (w < 1 || h < 1 || w > R3X_MAX_TEXTURE || h > R3X_MAX_TEXTURE) {
        stbi_image_free(rgba);
        return fail("render3dxt: a texture must be 1 to 8192 pixels each way");
    }
    uint32_t *px = (uint32_t *)malloc((size_t)w * (size_t)h * 4);
    if (!px) { stbi_image_free(rgba); return fail(k_no_memory); }
    size_t n = (size_t)w * (size_t)h;
    for (size_t i = 0; i < n; i++) {
        const unsigned char *s = rgba + i * 4;
        px[i] = ((uint32_t)s[3] << 24) | ((uint32_t)s[0] << 16) |
                ((uint32_t)s[1] << 8) | (uint32_t)s[2];
    }
    stbi_image_free(rgba);
    return texture_adopt(px, w, h, owner);
}

static int texture_load_path(const char *path, int owner)
{
    if (!path || !path[0]) return fail("render3dxt: no file name");
    int w = 0, h = 0, c = 0;
    unsigned char *rgba = stbi_load(path, &w, &h, &c, 4);
    if (!rgba) return fail("render3dxt: the texture file could not be read or decoded");
    return texture_from_rgba(rgba, w, h, owner);
}

LC_API int r3x_texture_load(const char *path)
{
    ok_clear();
    return texture_load_path(path, 0);
}

LC_API int r3x_texture_decode(const unsigned char *bytes, int length)
{
    ok_clear();
    if (!bytes || length <= 0) return fail("render3dxt: no bytes to decode");
    int w = 0, h = 0, c = 0;
    unsigned char *rgba = stbi_load_from_memory(bytes, length, &w, &h, &c, 4);
    return texture_from_rgba(rgba, w, h, 0);
}

/* From an image's imageData: 4 bytes a pixel, 0,R,G,B, rows from the top.
 * The first byte of each pixel is NOT alpha (an image keeps that in its
 * alphaData), so the texture is opaque. */
LC_API int r3x_texture_from_image_data(const unsigned char *bytes, int length, int width, int height)
{
    ok_clear();
    if (width < 1 || height < 1 || width > R3X_MAX_TEXTURE || height > R3X_MAX_TEXTURE)
        return fail("render3dxt: a texture must be 1 to 8192 pixels each way");
    size_t need = (size_t)width * (size_t)height * 4;
    if (!bytes || length < 0 || (size_t)length < need)
        return fail("render3dxt: the imageData is shorter than width * height * 4 bytes");
    uint32_t *px = (uint32_t *)malloc(need);
    if (!px) return fail(k_no_memory);
    size_t n = (size_t)width * (size_t)height;
    for (size_t i = 0; i < n; i++) {
        const unsigned char *s = bytes + i * 4;
        px[i] = 0xFF000000u | ((uint32_t)s[1] << 16) | ((uint32_t)s[2] << 8) | (uint32_t)s[3];
    }
    return texture_adopt(px, width, height, 0);
}

/* A checkerboard, for scenes that have no picture files. */
LC_API int r3x_texture_checker(int size, int cells, double r1, double g1, double b1,
                               double r2, double g2, double b2)
{
    ok_clear();
    if (size < 2 || size > 2048) return fail("render3dxt: a checker is 2 to 2048 pixels");
    if (cells < 1 || cells > size) return fail("render3dxt: a checker has 1 to size cells");
    if (!rgb_ok(r1, g1, b1) || !rgb_ok(r2, g2, b2)) return fail(k_bad_number);
    uint32_t c1 = 0xFF000000u | ((uint32_t)r1 << 16) | ((uint32_t)g1 << 8) | (uint32_t)b1;
    uint32_t c2 = 0xFF000000u | ((uint32_t)r2 << 16) | ((uint32_t)g2 << 8) | (uint32_t)b2;
    uint32_t *px = (uint32_t *)malloc((size_t)size * (size_t)size * 4);
    if (!px) return fail(k_no_memory);
    for (int y = 0; y < size; y++)
        for (int x = 0; x < size; x++) {
            int cx = x * cells / size, cy = y * cells / size;
            px[(size_t)y * (size_t)size + (size_t)x] = ((cx + cy) & 1) ? c2 : c1;
        }
    return texture_adopt(px, size, size, 0);
}

static void texture_release(int h)
{
    Texture *t = textures_get(h);
    if (!t) return;
    free(t->px);
    free(t);
    textures_free_handle(h);
}

LC_API void r3x_texture_destroy(int texture)
{
    ok_clear();
    Texture *t = textures_get(texture);
    if (!t) { fail(k_bad_handle); return; }
    /* A texture a mesh loaded is the mesh's; destroying it here is allowed,
     * and the mesh forgets it so that it is not freed twice. */
    if (t->owner) {
        Mesh *m = meshes_get(t->owner);
        if (m) for (int i = 0; i < m->nOwnedTex; i++)
            if (m->ownedTex[i] == texture) m->ownedTex[i] = 0;
    }
    texture_release(texture);
}

LC_API int r3x_texture_is_valid(int texture) { return textures_get(texture) ? 1 : 0; }
LC_API int r3x_texture_width(int texture) { Texture *t = textures_get(texture); return t ? t->w : 0; }
LC_API int r3x_texture_height(int texture) { Texture *t = textures_get(texture); return t ? t->h : 0; }

LC_API void r3x_texture_set_smooth(int texture, int flag)
{
    Texture *t = textures_get(texture);
    if (t) t->smooth = flag ? 1 : 0;
}
LC_API int r3x_texture_is_smooth(int texture) { Texture *t = textures_get(texture); return t ? t->smooth : 0; }

LC_API void r3x_texture_set_repeat(int texture, int flag)
{
    Texture *t = textures_get(texture);
    if (t) t->repeat = flag ? 1 : 0;
}
LC_API int r3x_texture_is_repeat(int texture) { Texture *t = textures_get(texture); return t ? t->repeat : 0; }

/* ================================================================== */
/* Materials                                                           */
/* ================================================================== */
static int material_new(double r, double g, double b, int owner)
{
    Material *m = (Material *)calloc(1, sizeof(Material));
    if (!m) return fail(k_no_memory);
    m->kd[0] = (float)(r / 255.0); m->kd[1] = (float)(g / 255.0); m->kd[2] = (float)(b / 255.0);
    m->ks = 0.0f; m->shininess = 32.0f; m->owner = owner;
    int h = materials_add(m);
    if (!h) { free(m); return fail(k_no_memory); }
    return h;
}

LC_API int r3x_material_create(double r, double g, double b)
{
    ok_clear();
    if (!rgb_ok(r, g, b)) return fail(k_bad_number);
    return material_new(r, g, b, 0);
}

static void material_release(int h)
{
    Material *m = materials_get(h);
    if (!m) return;
    free(m);
    materials_free_handle(h);
}

LC_API void r3x_material_destroy(int material)
{
    ok_clear();
    if (!materials_get(material)) { fail(k_bad_handle); return; }
    material_release(material);
}

LC_API int r3x_material_is_valid(int material) { return materials_get(material) ? 1 : 0; }

LC_API void r3x_material_set_color(int material, double r, double g, double b)
{
    ok_clear();
    Material *m = materials_get(material);
    if (!m) { fail(k_bad_handle); return; }
    if (!rgb_ok(r, g, b)) { fail(k_bad_number); return; }
    m->kd[0] = (float)(r / 255.0); m->kd[1] = (float)(g / 255.0); m->kd[2] = (float)(b / 255.0);
}

/* "r,g,b", 0 to 255 */
LC_API const char *r3x_material_color(int material)
{
    Material *m = materials_get(material);
    if (!m) return text_empty();
    double d[3] = { floor(m->kd[0] * 255.0 + 0.5), floor(m->kd[1] * 255.0 + 0.5),
                    floor(m->kd[2] * 255.0 + 0.5) };
    return text_of(d, 3);
}

LC_API void r3x_material_set_texture(int material, int texture)
{
    ok_clear();
    Material *m = materials_get(material);
    if (!m) { fail(k_bad_handle); return; }
    if (texture != 0 && !textures_get(texture)) { fail(k_bad_handle); return; }
    m->texture = texture;
}

LC_API int r3x_material_texture(int material)
{
    Material *m = materials_get(material);
    if (!m) return 0;
    return textures_get(m->texture) ? m->texture : 0;
}

LC_API void r3x_material_set_specular(int material, double strength, double shininess)
{
    ok_clear();
    Material *m = materials_get(material);
    if (!m) { fail(k_bad_handle); return; }
    if (!unit_ok(strength) || !isfinite(shininess) || shininess < 1.0 || shininess > 1000.0) {
        fail(k_bad_number); return;
    }
    m->ks = (float)strength; m->shininess = (float)shininess;
}

/* "strength,shininess" */
LC_API const char *r3x_material_specular(int material)
{
    Material *m = materials_get(material);
    if (!m) return text_empty();
    double d[2] = { m->ks, m->shininess };
    return text_of(d, 2);
}

LC_API void r3x_material_set_emissive(int material, double r, double g, double b)
{
    ok_clear();
    Material *m = materials_get(material);
    if (!m) { fail(k_bad_handle); return; }
    if (!rgb_ok(r, g, b)) { fail(k_bad_number); return; }
    m->ke[0] = (float)(r / 255.0); m->ke[1] = (float)(g / 255.0); m->ke[2] = (float)(b / 255.0);
}

LC_API void r3x_material_set_unlit(int material, int flag)
{ Material *m = materials_get(material); if (m) m->unlit = flag ? 1 : 0; }
LC_API int r3x_material_is_unlit(int material)
{ Material *m = materials_get(material); return m ? m->unlit : 0; }
LC_API void r3x_material_set_double_sided(int material, int flag)
{ Material *m = materials_get(material); if (m) m->twoSided = flag ? 1 : 0; }
LC_API int r3x_material_is_double_sided(int material)
{ Material *m = materials_get(material); return m ? m->twoSided : 0; }
LC_API void r3x_material_set_flat(int material, int flag)
{ Material *m = materials_get(material); if (m) m->flat = flag ? 1 : 0; }
LC_API int r3x_material_is_flat(int material)
{ Material *m = materials_get(material); return m ? m->flat : 0; }
LC_API void r3x_material_set_cutout(int material, int flag)
{ Material *m = materials_get(material); if (m) m->cutout = flag ? 1 : 0; }
LC_API int r3x_material_is_cutout(int material)
{ Material *m = materials_get(material); return m ? m->cutout : 0; }

/* ================================================================== */
/* Meshes                                                              */
/* ================================================================== */
static Mesh *mesh_alloc(void)
{
    Mesh *m = (Mesh *)calloc(1, sizeof(Mesh));
    if (!m) return NULL;
    m->boundsDirty = 1;
    m->nslots = 1;
    m->slotMat = (int *)calloc(1, sizeof(int));
    m->slotName = (char **)calloc(1, sizeof(char *));
    m->slotTexName = (char **)calloc(1, sizeof(char *));
    if (!m->slotMat || !m->slotName || !m->slotTexName) {
        free(m->slotMat); free(m->slotName); free(m->slotTexName); free(m);
        return NULL;
    }
    return m;
}

static void mesh_free_data(Mesh *m)
{
    if (!m) return;
    free(m->pos); free(m->nrm); free(m->uv);
    free(m->tri); free(m->triSlot);
    for (int i = 0; i < m->nslots; i++) {
        if (m->slotName) free(m->slotName[i]);
        if (m->slotTexName) free(m->slotTexName[i]);
    }
    free(m->slotMat); free(m->slotName); free(m->slotTexName);
    free(m->ownedTex);
    free(m);
}

static int mesh_reserve_vertices(Mesh *m, int need)
{
    if (need > R3X_MAX_VERTICES) return fail("render3dxt: a mesh holds at most 4000000 vertices");
    if (need <= m->capv) return 1;
    int nc = m->capv ? m->capv : 64;
    while (nc < need) nc = (nc > R3X_MAX_VERTICES / 2) ? R3X_MAX_VERTICES : nc * 2;
    float *p = (float *)realloc(m->pos, (size_t)nc * 3 * sizeof(float));
    if (!p) return fail(k_no_memory);
    m->pos = p;
    float *n = (float *)realloc(m->nrm, (size_t)nc * 3 * sizeof(float));
    if (!n) return fail(k_no_memory);
    m->nrm = n;
    float *u = (float *)realloc(m->uv, (size_t)nc * 2 * sizeof(float));
    if (!u) return fail(k_no_memory);
    m->uv = u;
    m->capv = nc;
    return 1;
}

static int mesh_reserve_triangles(Mesh *m, int need)
{
    if (need > R3X_MAX_TRIANGLES) return fail("render3dxt: a mesh holds at most 4000000 triangles");
    if (need <= m->capt) return 1;
    int nc = m->capt ? m->capt : 64;
    while (nc < need) nc = (nc > R3X_MAX_TRIANGLES / 2) ? R3X_MAX_TRIANGLES : nc * 2;
    int *t = (int *)realloc(m->tri, (size_t)nc * 3 * sizeof(int));
    if (!t) return fail(k_no_memory);
    m->tri = t;
    int *s = (int *)realloc(m->triSlot, (size_t)nc * sizeof(int));
    if (!s) return fail(k_no_memory);
    m->triSlot = s;
    m->capt = nc;
    return 1;
}

static int mesh_reserve_slots(Mesh *m, int need)
{
    if (need > R3X_MAX_SLOTS) return fail("render3dxt: a mesh has at most 1024 material slots");
    if (need <= m->nslots) return 1;
    int *a = (int *)realloc(m->slotMat, (size_t)need * sizeof(int));
    if (!a) return fail(k_no_memory);
    m->slotMat = a;
    char **b = (char **)realloc(m->slotName, (size_t)need * sizeof(char *));
    if (!b) return fail(k_no_memory);
    m->slotName = b;
    char **c = (char **)realloc(m->slotTexName, (size_t)need * sizeof(char *));
    if (!c) return fail(k_no_memory);
    m->slotTexName = c;
    for (int i = m->nslots; i < need; i++) { a[i] = 0; b[i] = NULL; c[i] = NULL; }
    m->nslots = need;
    return 1;
}

static int mesh_push_vertex(Mesh *m, float x, float y, float z, float nx, float ny, float nz,
                            float u, float v)
{
    if (!mesh_reserve_vertices(m, m->nv + 1)) return -1;
    int i = m->nv++;
    m->pos[i * 3] = x; m->pos[i * 3 + 1] = y; m->pos[i * 3 + 2] = z;
    m->nrm[i * 3] = nx; m->nrm[i * 3 + 1] = ny; m->nrm[i * 3 + 2] = nz;
    m->uv[i * 2] = u; m->uv[i * 2 + 1] = v;
    m->boundsDirty = 1;
    return i;
}

static int mesh_push_triangle(Mesh *m, int a, int b, int c, int slot)
{
    if (!mesh_reserve_triangles(m, m->nt + 1)) return 0;
    int i = m->nt++;
    m->tri[i * 3] = a; m->tri[i * 3 + 1] = b; m->tri[i * 3 + 2] = c;
    m->triSlot[i] = slot;
    return 1;
}

static void mesh_bounds(Mesh *m)
{
    if (!m->boundsDirty) return;
    if (m->nv == 0) {
        for (int k = 0; k < 3; k++) { m->bmin[k] = 0; m->bmax[k] = 0; }
    } else {
        for (int k = 0; k < 3; k++) { m->bmin[k] = m->pos[k]; m->bmax[k] = m->pos[k]; }
        for (int i = 1; i < m->nv; i++)
            for (int k = 0; k < 3; k++) {
                float v = m->pos[i * 3 + k];
                if (v < m->bmin[k]) m->bmin[k] = v;
                if (v > m->bmax[k]) m->bmax[k] = v;
            }
    }
    m->boundsDirty = 0;
}

/* Smooth normals from the triangles: area-weighted, per vertex index. A
 * vertex no triangle uses keeps (0,1,0). */
static void mesh_smooth_normals(Mesh *m)
{
    if (m->nv == 0) return;
    memset(m->nrm, 0, (size_t)m->nv * 3 * sizeof(float));
    for (int t = 0; t < m->nt; t++) {
        int a = m->tri[t * 3], b = m->tri[t * 3 + 1], c = m->tri[t * 3 + 2];
        const float *pa = m->pos + a * 3, *pb = m->pos + b * 3, *pc = m->pos + c * 3;
        float e1[3] = { pb[0] - pa[0], pb[1] - pa[1], pb[2] - pa[2] };
        float e2[3] = { pc[0] - pa[0], pc[1] - pa[1], pc[2] - pa[2] };
        float n[3] = { e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2],
                       e1[0] * e2[1] - e1[1] * e2[0] };
        for (int k = 0; k < 3; k++) {
            m->nrm[a * 3 + k] += n[k]; m->nrm[b * 3 + k] += n[k]; m->nrm[c * 3 + k] += n[k];
        }
    }
    for (int i = 0; i < m->nv; i++) {
        float *n = m->nrm + i * 3;
        float l = sqrtf(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
        if (l > 1e-20f && isfinite(l)) { n[0] /= l; n[1] /= l; n[2] /= l; }
        else { n[0] = 0; n[1] = 1; n[2] = 0; }
    }
}

static int mesh_register(Mesh *m)
{
    int h = meshes_add(m);
    if (!h) { mesh_free_data(m); return fail(k_no_memory); }
    return h;
}

/* Frees a mesh, and the materials and textures it made for itself (an OBJ's
 * MTL). Anything the script made stays. */
static void mesh_release(int h)
{
    Mesh *m = meshes_get(h);
    if (!m) return;
    for (int i = 0; i < m->nslots; i++) {
        Material *mat = materials_get(m->slotMat[i]);
        if (mat && mat->owner == h) material_release(m->slotMat[i]);
    }
    for (int i = 0; i < m->nOwnedTex; i++) {
        Texture *t = textures_get(m->ownedTex[i]);
        if (t && t->owner == h) texture_release(m->ownedTex[i]);
    }
    mesh_free_data(m);
    meshes_free_handle(h);
}

LC_API void r3x_mesh_destroy(int mesh)
{
    ok_clear();
    if (!meshes_get(mesh)) { fail(k_bad_handle); return; }
    mesh_release(mesh);
}

LC_API int r3x_mesh_is_valid(int mesh) { return meshes_get(mesh) ? 1 : 0; }
LC_API int r3x_mesh_vertex_count(int mesh) { Mesh *m = meshes_get(mesh); return m ? m->nv : 0; }
LC_API int r3x_mesh_triangle_count(int mesh) { Mesh *m = meshes_get(mesh); return m ? m->nt : 0; }

/* "minx,miny,minz,maxx,maxy,maxz" in the mesh's own frame */
LC_API const char *r3x_mesh_bounds(int mesh)
{
    Mesh *m = meshes_get(mesh);
    if (!m) return text_empty();
    mesh_bounds(m);
    double d[6] = { m->bmin[0], m->bmin[1], m->bmin[2], m->bmax[0], m->bmax[1], m->bmax[2] };
    return text_of(d, 6);
}

/* An empty mesh, filled from script with r3MeshAddVertex and
 * r3MeshAddTriangle. */
LC_API int r3x_mesh_create(void)
{
    ok_clear();
    Mesh *m = mesh_alloc();
    if (!m) return fail(k_no_memory);
    return mesh_register(m);
}

/* Returns the new vertex's index, counted from 1, or 0. */
LC_API int r3x_mesh_add_vertex(int mesh, double x, double y, double z,
                               double nx, double ny, double nz, double u, double v)
{
    ok_clear();
    Mesh *m = meshes_get(mesh);
    if (!m) return fail(k_bad_handle);
    if (!fin3(x, y, z) || !fin3(nx, ny, nz) || !fin(u) || !fin(v)) return fail(k_bad_number);
    double n[3] = { 0, 1, 0 };
    if (!dir_in(nx, ny, nz, n)) { n[0] = 0; n[1] = 1; n[2] = 0; }
    int i = mesh_push_vertex(m, (float)x, (float)y, (float)z,
                             (float)n[0], (float)n[1], (float)n[2], (float)u, (float)v);
    return i < 0 ? 0 : i + 1;
}

/* a, b, c are vertex indices counted from 1, counter-clockwise seen from the
 * front; slot is the material slot, counted from 1 (slots are added as
 * needed). Returns the triangle count, or 0. */
LC_API int r3x_mesh_add_triangle(int mesh, int a, int b, int c, int slot)
{
    ok_clear();
    Mesh *m = meshes_get(mesh);
    if (!m) return fail(k_bad_handle);
    if (a < 1 || b < 1 || c < 1 || a > m->nv || b > m->nv || c > m->nv)
        return fail("render3dxt: a triangle names a vertex that does not exist");
    if (slot < 1 || slot > R3X_MAX_SLOTS) return fail("render3dxt: a slot is 1 to 1024");
    if (!mesh_reserve_slots(m, slot)) return 0;
    if (!mesh_push_triangle(m, a - 1, b - 1, c - 1, slot - 1)) return 0;
    return m->nt;
}

LC_API void r3x_mesh_compute_normals(int mesh)
{
    ok_clear();
    Mesh *m = meshes_get(mesh);
    if (!m) { fail(k_bad_handle); return; }
    mesh_smooth_normals(m);
}

LC_API int r3x_mesh_slot_count(int mesh) { Mesh *m = meshes_get(mesh); return m ? m->nslots : 0; }

LC_API int r3x_mesh_slot_material(int mesh, int slot)
{
    Mesh *m = meshes_get(mesh);
    if (!m || slot < 1 || slot > m->nslots) return 0;
    int h = m->slotMat[slot - 1];
    return materials_get(h) ? h : 0;
}

LC_API void r3x_mesh_set_slot_material(int mesh, int slot, int material)
{
    ok_clear();
    Mesh *m = meshes_get(mesh);
    if (!m) { fail(k_bad_handle); return; }
    if (slot < 1 || slot > R3X_MAX_SLOTS) { fail("render3dxt: a slot is 1 to 1024"); return; }
    if (material != 0 && !materials_get(material)) { fail(k_bad_handle); return; }
    if (!mesh_reserve_slots(m, slot)) return;
    m->slotMat[slot - 1] = material;
}

LC_API const char *r3x_mesh_slot_name(int mesh, int slot)
{
    Mesh *m = meshes_get(mesh);
    if (!m || slot < 1 || slot > m->nslots) return text_empty();
    return text_str(m->slotName[slot - 1]);
}

LC_API const char *r3x_mesh_slot_texture_name(int mesh, int slot)
{
    Mesh *m = meshes_get(mesh);
    if (!m || slot < 1 || slot > m->nslots) return text_empty();
    return text_str(m->slotTexName[slot - 1]);
}

/* ------------------------------------------------------------------ */
/* Primitives. Every one is centred on its own origin with y up, the   */
/* way box3dxt's shapes are, so a node at a body's transform covers    */
/* the body's shape: a box takes half-extents, a capsule and a         */
/* cylinder stand along y. Texture coordinates run 0..1 over each face */
/* with (0,0) at the TOP-LEFT of the texture.                          */
/* ------------------------------------------------------------------ */
static int box_face(Mesh *m, const float c[3], const float ax[3], const float ay[3], const float n[3])
{
    /* corners: c - ax + ay (top-left of the texture), going round */
    float p[4][3];
    static const float su[4] = { -1, 1, 1, -1 };
    static const float sv[4] = { 1, 1, -1, -1 };
    int base = m->nv;
    for (int i = 0; i < 4; i++) {
        for (int k = 0; k < 3; k++) p[i][k] = c[k] + su[i] * ax[k] + sv[i] * ay[k];
        float u = (su[i] + 1) * 0.5f, v = (1 - sv[i]) * 0.5f;
        if (mesh_push_vertex(m, p[i][0], p[i][1], p[i][2], n[0], n[1], n[2], u, v) < 0) return 0;
    }
    if (!mesh_push_triangle(m, base, base + 3, base + 2, 0)) return 0;
    if (!mesh_push_triangle(m, base, base + 2, base + 1, 0)) return 0;
    return 1;
}

LC_API int r3x_mesh_box(double hx, double hy, double hz)
{
    ok_clear();
    if (!size_ok(hx) || !size_ok(hy) || !size_ok(hz)) return fail(k_bad_number);
    Mesh *m = mesh_alloc();
    if (!m) return fail(k_no_memory);
    float x = (float)hx, y = (float)hy, z = (float)hz;
    /* each face: centre, the texture's right (u) axis, its up axis, normal;
     * chosen so that (u, up, normal) is right-handed and the triangles wind
     * counter-clockwise seen from outside */
    const float F[6][4][3] = {
        { { 0, 0, z }, { x, 0, 0 }, { 0, y, 0 }, { 0, 0, 1 } },     /* +z */
        { { 0, 0, -z }, { -x, 0, 0 }, { 0, y, 0 }, { 0, 0, -1 } },  /* -z */
        { { x, 0, 0 }, { 0, 0, -z }, { 0, y, 0 }, { 1, 0, 0 } },    /* +x */
        { { -x, 0, 0 }, { 0, 0, z }, { 0, y, 0 }, { -1, 0, 0 } },   /* -x */
        { { 0, y, 0 }, { x, 0, 0 }, { 0, 0, -z }, { 0, 1, 0 } },    /* +y */
        { { 0, -y, 0 }, { x, 0, 0 }, { 0, 0, z }, { 0, -1, 0 } },   /* -y */
    };
    for (int f = 0; f < 6; f++)
        if (!box_face(m, F[f][0], F[f][1], F[f][2], F[f][3])) { mesh_free_data(m); return 0; }
    return mesh_register(m);
}

/* A plane facing +y, hx by hz half-extents, the texture repeated
 * uRepeat x vRepeat times across it. */
LC_API int r3x_mesh_plane(double hx, double hz, double uRepeat, double vRepeat)
{
    ok_clear();
    if (!size_ok(hx) || !size_ok(hz)) return fail(k_bad_number);
    if (!isfinite(uRepeat) || !isfinite(vRepeat) || uRepeat <= 0 || vRepeat <= 0 ||
        uRepeat > 10000 || vRepeat > 10000) return fail(k_bad_number);
    Mesh *m = mesh_alloc();
    if (!m) return fail(k_no_memory);
    float x = (float)hx, z = (float)hz, ur = (float)uRepeat, vr = (float)vRepeat;
    int ok = mesh_push_vertex(m, -x, 0, -z, 0, 1, 0, 0, 0) >= 0 &&
             mesh_push_vertex(m, x, 0, -z, 0, 1, 0, ur, 0) >= 0 &&
             mesh_push_vertex(m, x, 0, z, 0, 1, 0, ur, vr) >= 0 &&
             mesh_push_vertex(m, -x, 0, z, 0, 1, 0, 0, vr) >= 0 &&
             mesh_push_triangle(m, 0, 3, 2, 0) && mesh_push_triangle(m, 0, 2, 1, 0);
    if (!ok) { mesh_free_data(m); return 0; }
    return mesh_register(m);
}

/* A ring of `slices` + 1 vertices at height y and radius r (the seam is
 * doubled so the texture wraps once around). */
static int ring(Mesh *m, int slices, float r, float y, float ny, float v)
{
    for (int i = 0; i <= slices; i++) {
        float a = (float)(2.0 * 3.14159265358979323846 * i / slices);
        float c = cosf(a), s = sinf(a);
        float nl = sqrtf(1.0f - ny * ny);
        if (mesh_push_vertex(m, r * c, y, -r * s, nl * c, ny, -nl * s,
                             (float)i / (float)slices, v) < 0) return -1;
    }
    return m->nv - (slices + 1);
}

static int join_rings(Mesh *m, int a, int b, int slices)
{
    /* ring a above ring b; counter-clockwise seen from outside */
    for (int i = 0; i < slices; i++) {
        if (!mesh_push_triangle(m, a + i, b + i, b + i + 1, 0)) return 0;
        if (!mesh_push_triangle(m, a + i, b + i + 1, a + i + 1, 0)) return 0;
    }
    return 1;
}

static int seg_ok(int slices, int stacks)
{
    return slices >= 3 && slices <= R3X_MAX_SEGMENTS && stacks >= 2 && stacks <= R3X_MAX_SEGMENTS;
}

/* A sphere of radius r: slices round the y axis, stacks pole to pole. */
LC_API int r3x_mesh_sphere(double radius, int slices, int stacks)
{
    ok_clear();
    if (!size_ok(radius)) return fail(k_bad_number);
    if (!seg_ok(slices, stacks)) return fail("render3dxt: slices are 3 to 256 and stacks 2 to 256");
    Mesh *m = mesh_alloc();
    if (!m) return fail(k_no_memory);
    float r = (float)radius;
    int prev = -1;
    for (int j = 0; j <= stacks; j++) {
        float phi = (float)(3.14159265358979323846 * j / stacks);   /* 0 at the top */
        float ny = cosf(phi);
        int cur = ring(m, slices, r * sinf(phi), r * ny, ny, (float)j / (float)stacks);
        if (cur < 0 || (prev >= 0 && !join_rings(m, prev, cur, slices))) { mesh_free_data(m); return 0; }
        prev = cur;
    }
    return mesh_register(m);
}

/* A disc closing a cylinder end, facing +y (up = 1) or -y. */
static int cap_disc(Mesh *m, int slices, float r, float y, int up)
{
    float ny = up ? 1.0f : -1.0f;
    int centre = mesh_push_vertex(m, 0, y, 0, 0, ny, 0, 0.5f, 0.5f);
    if (centre < 0) return 0;
    int first = m->nv;
    for (int i = 0; i <= slices; i++) {
        float a = (float)(2.0 * 3.14159265358979323846 * i / slices);
        float c = cosf(a), s = sinf(a);
        if (mesh_push_vertex(m, r * c, y, -r * s, 0, ny, 0, 0.5f + 0.5f * c, 0.5f + 0.5f * s) < 0)
            return 0;
    }
    for (int i = 0; i < slices; i++) {
        int ok = up ? mesh_push_triangle(m, centre, first + i, first + i + 1, 0)
                    : mesh_push_triangle(m, centre, first + i + 1, first + i, 0);
        if (!ok) return 0;
    }
    return 1;
}

/* A cylinder standing along y, from -halfHeight to +halfHeight, closed. */
LC_API int r3x_mesh_cylinder(double radius, double halfHeight, int slices)
{
    ok_clear();
    if (!size_ok(radius) || !size_ok(halfHeight)) return fail(k_bad_number);
    if (!seg_ok(slices, 2)) return fail("render3dxt: slices are 3 to 256");
    Mesh *m = mesh_alloc();
    if (!m) return fail(k_no_memory);
    float r = (float)radius, h = (float)halfHeight;
    int top = ring(m, slices, r, h, 0, 0);
    int bot = top < 0 ? -1 : ring(m, slices, r, -h, 0, 1);
    if (bot < 0 || !join_rings(m, top, bot, slices) ||
        !cap_disc(m, slices, r, h, 1) || !cap_disc(m, slices, r, -h, 0)) {
        mesh_free_data(m); return 0;
    }
    return mesh_register(m);
}

/* A capsule along y: the segment from -halfHeight to +halfHeight, swept by
 * a sphere of the radius (Box3D's capsule with its centres on the y axis).
 * stacks is per hemisphere. */
LC_API int r3x_mesh_capsule(double radius, double halfHeight, int slices, int stacks)
{
    ok_clear();
    if (!size_ok(radius) || !size_ok(halfHeight)) return fail(k_bad_number);
    if (!seg_ok(slices, stacks)) return fail("render3dxt: slices are 3 to 256 and stacks 2 to 256");
    Mesh *m = mesh_alloc();
    if (!m) return fail(k_no_memory);
    float r = (float)radius, h = (float)halfHeight;
    /* rows: the top hemisphere pole to equator (at +h), then the bottom one
     * equator (at -h) to pole; the two equators joined are the straight side */
    int rows = 2 * stacks + 2, prev = -1;
    for (int j = 0; j < rows; j++) {
        int top = j <= stacks;
        int k = top ? j : j - 1;                 /* 0..2*stacks */
        float phi = (float)(3.14159265358979323846 * 0.5 * k / stacks);
        float ny = cosf(phi);
        if (k == stacks) ny = 0;                 /* the equator, exactly */
        float rr = k == stacks ? r : r * sinf(phi);
        int cur = ring(m, slices, rr, r * ny + (top ? h : -h), ny, (float)j / (float)(rows - 1));
        if (cur < 0 || (prev >= 0 && !join_rings(m, prev, cur, slices))) { mesh_free_data(m); return 0; }
        prev = cur;
    }
    return mesh_register(m);
}

/* ------------------------------------------------------------------ */
/* A mesh from triangle text: one line per triangle,                   */
/* "x1,y1,z1,x2,y2,z2,x3,y3,z3", counter-clockwise seen from outside.  */
/* The form box3dxt's b3ShapeTrianglesText gives. Normals are flat;    */
/* texture coordinates are planar, one repeat per metre, taken across  */
/* the triangle's dominant axis. A line that is not nine numbers is a  */
/* refusal (naming the line), never a silent skip.                     */
/* ------------------------------------------------------------------ */
static void planar_uv(const float n[3], const float p[3], float *u, float *v)
{
    float ax = fabsf(n[0]), ay = fabsf(n[1]), az = fabsf(n[2]);
    if (ay >= ax && ay >= az) { *u = p[0]; *v = n[1] > 0 ? p[2] : -p[2]; }
    else if (ax >= az) { *u = n[0] > 0 ? -p[2] : p[2]; *v = -p[1]; }
    else { *u = n[2] > 0 ? p[0] : -p[0]; *v = -p[1]; }
}

static char s_lineError[96];

LC_API int r3x_mesh_from_triangles_text(const char *text)
{
    ok_clear();
    if (!text) return fail("render3dxt: no text");
    Mesh *m = mesh_alloc();
    if (!m) return fail(k_no_memory);
    const char *p = text;
    int line = 0;
    while (*p) {
        const char *e = p;
        while (*e && *e != '\n' && *e != '\r') e++;
        line++;
        const char *q = p;
        while (q < e && (*q == ' ' || *q == '\t')) q++;
        if (q < e) {
            double d[10];
            int n = parse_items(p, e, d, 10);
            int good = (n == 9);
            for (int i = 0; good && i < 9; i++) good = fin(d[i]);
            if (!good) {
                snprintf(s_lineError, sizeof(s_lineError),
                         "render3dxt: triangle line %d is not nine numbers", line);
                mesh_free_data(m);
                return fail(s_lineError);
            }
            float P[3][3];
            for (int i = 0; i < 9; i++) P[i / 3][i % 3] = (float)d[i];
            float e1[3] = { P[1][0] - P[0][0], P[1][1] - P[0][1], P[1][2] - P[0][2] };
            float e2[3] = { P[2][0] - P[0][0], P[2][1] - P[0][1], P[2][2] - P[0][2] };
            float nn[3] = { e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2],
                            e1[0] * e2[1] - e1[1] * e2[0] };
            float l = sqrtf(nn[0] * nn[0] + nn[1] * nn[1] + nn[2] * nn[2]);
            if (l > 1e-30f && isfinite(l)) { nn[0] /= l; nn[1] /= l; nn[2] /= l; }
            else { nn[0] = 0; nn[1] = 1; nn[2] = 0; }
            int base = m->nv;
            for (int i = 0; i < 3; i++) {
                float u, v;
                planar_uv(nn, P[i], &u, &v);
                if (mesh_push_vertex(m, P[i][0], P[i][1], P[i][2], nn[0], nn[1], nn[2], u, v) < 0) {
                    mesh_free_data(m); return 0;
                }
            }
            if (!mesh_push_triangle(m, base, base + 1, base + 2, 0)) { mesh_free_data(m); return 0; }
        }
        p = e;
        while (*p == '\n' || *p == '\r') p++;
    }
    if (m->nt == 0) { mesh_free_data(m); return fail("render3dxt: the text holds no triangle"); }
    return mesh_register(m);
}

/* ------------------------------------------------------------------ */
/* OBJ models, through fast_obj.                                       */
/* ------------------------------------------------------------------ */
typedef struct MemFile { const char *data; size_t len, at; } MemFile;
typedef struct ObjSource {
    int fromText;
    MemFile obj, mtl;
    int opened;
} ObjSource;

static FILE *fopen_utf8(const char *path)
{
#if defined(_WIN32)
    int n = MultiByteToWideChar(CP_UTF8, 0, path, -1, NULL, 0);
    if (n <= 0) return NULL;
    wchar_t *w = (wchar_t *)malloc((size_t)n * sizeof(wchar_t));
    if (!w) return NULL;
    MultiByteToWideChar(CP_UTF8, 0, path, -1, w, n);
    FILE *f = _wfopen(w, L"rb");
    free(w);
    return f;
#else
    return fopen(path, "rb");
#endif
}

static void *src_open(const char *path, void *ud)
{
    ObjSource *s = (ObjSource *)ud;
    if (!s->fromText) return path ? (void *)fopen_utf8(path) : NULL;
    /* text mode: the first open is the OBJ, any later one (an mtllib) is
     * the MTL text, if one was given */
    MemFile *f = NULL;
    if (s->opened == 0) f = &s->obj;
    else if (s->mtl.data && s->mtl.len) f = &s->mtl;
    s->opened++;
    if (!f) return NULL;
    f->at = 0;
    return f;
}
static void src_close(void *file, void *ud)
{
    ObjSource *s = (ObjSource *)ud;
    if (!s->fromText && file) fclose((FILE *)file);
}
static size_t src_read(void *file, void *dst, size_t bytes, void *ud)
{
    ObjSource *s = (ObjSource *)ud;
    if (!s->fromText) return fread(dst, 1, bytes, (FILE *)file);
    MemFile *f = (MemFile *)file;
    size_t left = f->len - f->at;
    if (bytes > left) bytes = left;
    memcpy(dst, f->data + f->at, bytes);
    f->at += bytes;
    return bytes;
}
static unsigned long src_size(void *file, void *ud)
{
    ObjSource *s = (ObjSource *)ud;
    if (!s->fromText) {
        FILE *f = (FILE *)file;
        long p = ftell(f);
        if (p < 0 || fseek(f, 0, SEEK_END) != 0) return 0;
        long n = ftell(f);
        if (fseek(f, p, SEEK_SET) != 0 || n < 0) return 0;
        return (unsigned long)n;
    }
    return (unsigned long)((MemFile *)file)->len;
}

static char *dup_str(const char *s)
{
    if (!s) return NULL;
    size_t n = strlen(s);
    char *d = (char *)malloc(n + 1);
    if (d) memcpy(d, s, n + 1);
    return d;
}

static int owned_tex_push(Mesh *m, int tex)
{
    int *p = (int *)realloc(m->ownedTex, (size_t)(m->nOwnedTex + 1) * sizeof(int));
    if (!p) return 0;
    m->ownedTex = p;
    m->ownedTex[m->nOwnedTex++] = tex;
    return 1;
}

/* fast_obj's mesh -> ours. fast_obj checks no index, so every one is held
 * to its array here before it is read; a face that names a vertex that does
 * not exist is a refusal of the whole file (a model with holes in it is not
 * the model its author meant). */
static int build_from_obj(fastObjMesh *o, int loadTextures)
{
    if (o->face_count == 0) return fail("render3dxt: the model has no faces");
    /* count triangles first, so the limits are checked before anything grows */
    unsigned long long ntri = 0, at = 0;
    for (unsigned int f = 0; f < o->face_count; f++) {
        unsigned int fv = o->face_vertices[f];
        if (fv >= 3) ntri += fv - 2;
        at += fv;
        if (at > o->index_count) return fail("render3dxt: the model's faces overrun its indices");
    }
    if (ntri == 0) return fail("render3dxt: the model has no faces");
    if (ntri > R3X_MAX_TRIANGLES || ntri * 3 > R3X_MAX_VERTICES)
        return fail("render3dxt: the model has too many triangles (at most 1333333)");
    for (unsigned int i = 0; i < o->index_count; i++) {
        fastObjIndex ix = o->indices[i];
        if (ix.p == 0 || ix.p >= o->position_count || ix.t >= o->texcoord_count ||
            ix.n >= o->normal_count)
            return fail("render3dxt: a face of the model names a vertex that does not exist");
    }
    for (unsigned int i = 1; i < o->position_count; i++)
        for (int k = 0; k < 3; k++)
            if (!fin(o->positions[i * 3 + k])) return fail("render3dxt: the model has a coordinate out of range");

    /* smooth normals per POSITION, for faces whose corners carry none */
    float *acc = (float *)calloc((size_t)o->position_count * 3, sizeof(float));
    if (!acc) return fail(k_no_memory);
    at = 0;
    for (unsigned int f = 0; f < o->face_count; f++) {
        unsigned int fv = o->face_vertices[f];
        for (unsigned int k = 1; k + 1 < fv; k++) {
            unsigned int ia[3] = { o->indices[at].p, o->indices[at + k].p, o->indices[at + k + 1].p };
            const float *a = o->positions + ia[0] * 3, *b = o->positions + ia[1] * 3,
                        *c = o->positions + ia[2] * 3;
            float e1[3] = { b[0] - a[0], b[1] - a[1], b[2] - a[2] };
            float e2[3] = { c[0] - a[0], c[1] - a[1], c[2] - a[2] };
            float n[3] = { e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2],
                           e1[0] * e2[1] - e1[1] * e2[0] };
            for (int j = 0; j < 3; j++)
                for (int q = 0; q < 3; q++) acc[ia[j] * 3 + q] += n[q];
        }
        at += fv;
    }

    Mesh *m = mesh_alloc();
    if (!m) { free(acc); return fail(k_no_memory); }
    int nslots = o->material_count > 0 ? (int)o->material_count : 1;
    if (nslots > R3X_MAX_SLOTS || !mesh_reserve_slots(m, nslots) ||
        !mesh_reserve_vertices(m, (int)(ntri * 3)) || !mesh_reserve_triangles(m, (int)ntri)) {
        free(acc); mesh_free_data(m);
        return fail(nslots > R3X_MAX_SLOTS ? "render3dxt: the model has more than 1024 materials" : k_no_memory);
    }
    at = 0;
    for (unsigned int f = 0; f < o->face_count; f++) {
        unsigned int fv = o->face_vertices[f];
        unsigned int fm = o->face_materials ? o->face_materials[f] : 0;
        int slot = (o->material_count > 0 && fm < o->material_count) ? (int)fm : 0;
        for (unsigned int k = 1; k + 1 < fv; k++) {
            unsigned int c3[3] = { (unsigned)at, (unsigned)(at + k), (unsigned)(at + k + 1) };
            int base = m->nv;
            for (int j = 0; j < 3; j++) {
                fastObjIndex ix = o->indices[c3[j]];
                const float *p = o->positions + ix.p * 3;
                float n[3];
                if (ix.n) {
                    const float *nn = o->normals + ix.n * 3;
                    n[0] = nn[0]; n[1] = nn[1]; n[2] = nn[2];
                } else {
                    n[0] = acc[ix.p * 3]; n[1] = acc[ix.p * 3 + 1]; n[2] = acc[ix.p * 3 + 2];
                }
                float l = sqrtf(n[0] * n[0] + n[1] * n[1] + n[2] * n[2]);
                if (l > 1e-20f && isfinite(l)) { n[0] /= l; n[1] /= l; n[2] /= l; }
                else { n[0] = 0; n[1] = 1; n[2] = 0; }
                float u = 0, v = 0;
                if (ix.t) {
                    u = o->texcoords[ix.t * 2];
                    v = 1.0f - o->texcoords[ix.t * 2 + 1];   /* OBJ's v runs up */
                    if (!isfinite(u) || fabsf(u) > 1e6f) u = 0;
                    if (!isfinite(v) || fabsf(v) > 1e6f) v = 0;
                }
                mesh_push_vertex(m, p[0], p[1], p[2], n[0], n[1], n[2], u, v);
            }
            mesh_push_triangle(m, base, base + 1, base + 2, slot);
        }
        at += fv;
    }
    free(acc);

    int h = mesh_register(m);
    if (!h) return 0;

    /* materials: one per MTL material, owned by the mesh */
    for (unsigned int i = 0; i < o->material_count && (int)i < nslots; i++) {
        const fastObjMaterial *om = &o->materials[i];
        int mh = material_new(0, 0, 0, h);
        Material *mat = materials_get(mh);
        if (!mat) { mesh_release(h); return fail(k_no_memory); }
        for (int k = 0; k < 3; k++) {
            mat->kd[k] = clampf(isfinite(om->Kd[k]) ? om->Kd[k] : 1.0f, 0, 1);
            mat->ke[k] = clampf(isfinite(om->Ke[k]) ? om->Ke[k] : 0.0f, 0, 1);
        }
        float ks = (om->Ks[0] + om->Ks[1] + om->Ks[2]) / 3.0f;
        mat->ks = clampf(isfinite(ks) ? ks : 0.0f, 0, 1);
        mat->shininess = clampf(isfinite(om->Ns) && om->Ns >= 1.0f ? om->Ns : 32.0f, 1, 1000);
        m->slotMat[i] = mh;
        m->slotName[i] = dup_str(om->name);
        if (om->map_Kd > 0 && om->map_Kd < o->texture_count) {
            const fastObjTexture *t = &o->textures[om->map_Kd];
            m->slotTexName[i] = dup_str(t->name);
            if (loadTextures && t->path) {
                /* the same file used by several materials is loaded once */
                int tex = 0;
                for (unsigned int j = 0; j < i && !tex; j++) {
                    if (o->materials[j].map_Kd == om->map_Kd) tex = r3x_material_texture(m->slotMat[j]);
                }
                if (!tex) {
                    tex = texture_load_path(t->path, h);
                    if (tex && !owned_tex_push(m, tex)) { texture_release(tex); tex = 0; }
                }
                mat->texture = tex;
                if (tex) {
                    /* a textured material shows the texture's own colours
                     * unless the MTL tinted it on purpose */
                    if (mat->kd[0] == 0 && mat->kd[1] == 0 && mat->kd[2] == 0)
                        mat->kd[0] = mat->kd[1] = mat->kd[2] = 1;
                }
            }
        }
    }
    ok_clear();
    return h;
}

/* An OBJ file and the MTL files it names, with their diffuse textures
 * (map_Kd), which stb_image decodes. A texture that cannot be read leaves
 * that material untextured: the model still loads. */
LC_API int r3x_mesh_load_obj(const char *path)
{
    ok_clear();
    if (!path || !path[0]) return fail("render3dxt: no file name");
    ObjSource src;
    memset(&src, 0, sizeof src);
    fastObjCallbacks cb = { src_open, src_close, src_read, src_size };
    fastObjMesh *o = fast_obj_read_with_callbacks(path, &cb, &src);
    if (!o) return fail("render3dxt: the model file could not be read");
    int h = build_from_obj(o, 1);
    fast_obj_destroy(o);
    return h;
}

/* An OBJ given as text, with an MTL as text (or empty). Nothing is read
 * from a disk, so it works where there is none (the web); textures are
 * then set by script, by slot: r3MeshSlotTextureName says which picture
 * each material asked for. */
LC_API int r3x_mesh_parse_obj(const char *objText, const char *mtlText)
{
    ok_clear();
    if (!objText || !objText[0]) return fail("render3dxt: no model text");
    ObjSource src;
    memset(&src, 0, sizeof src);
    src.fromText = 1;
    src.obj.data = objText; src.obj.len = strlen(objText);
    if (mtlText) { src.mtl.data = mtlText; src.mtl.len = strlen(mtlText); }
    fastObjCallbacks cb = { src_open, src_close, src_read, src_size };
    fastObjMesh *o = fast_obj_read_with_callbacks("model.obj", &cb, &src);
    if (!o) return fail("render3dxt: the model text could not be read");
    int h = build_from_obj(o, 0);
    fast_obj_destroy(o);
    return h;
}

/* ================================================================== */
/* Scenes, the camera and lights                                       */
/* ================================================================== */
LC_API int r3x_light_create_directional(int scene, double dx, double dy, double dz,
                                        double r, double g, double b, double intensity);

LC_API int r3x_scene_create(void)
{
    ok_clear();
    Scene *s = (Scene *)calloc(1, sizeof(Scene));
    if (!s) return fail(k_no_memory);
    s->bg[0] = 0.12; s->bg[1] = 0.13; s->bg[2] = 0.16;
    s->ambient[0] = s->ambient[1] = s->ambient[2] = 0.25;
    s->eye[0] = 0; s->eye[1] = 2; s->eye[2] = 8;
    s->target[0] = 0; s->target[1] = 0; s->target[2] = 0;
    s->fov = 50; s->nearZ = R3X_DEFAULT_NEAR; s->farZ = 0;
    s->ss = 1;
    int h = scenes_add(s);
    if (!h) { free(s); return fail(k_no_memory); }
    /* the light box3dxt's renderer starts with, so a scene looks the same in
     * both before anybody sets one */
    r3x_light_create_directional(h, -0.37, -0.74, -0.56, 255, 255, 255, 1.0);
    ok_clear();
    return h;
}

static void node_release(int h);
static void light_release(int h);

LC_API void r3x_scene_destroy(int scene)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) { fail(k_bad_handle); return; }
    while (s->nodeCount > 0) node_release(s->nodes[s->nodeCount - 1]);
    while (s->lightCount > 0) light_release(s->lights[s->lightCount - 1]);
    free(s->nodes); free(s->frame); free(s->color); free(s->depth);
    free(s);
    scenes_free_handle(scene);
}

LC_API int r3x_scene_is_valid(int scene) { return scenes_get(scene) ? 1 : 0; }

static const char *text_rgb(const double c[3])
{
    double d[3] = { floor(c[0] * 255 + 0.5), floor(c[1] * 255 + 0.5), floor(c[2] * 255 + 0.5) };
    return text_of(d, 3);
}

LC_API void r3x_scene_set_background(int scene, double r, double g, double b)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) { fail(k_bad_handle); return; }
    if (!rgb_ok(r, g, b)) { fail(k_bad_number); return; }
    s->bg[0] = r / 255; s->bg[1] = g / 255; s->bg[2] = b / 255;
}
LC_API const char *r3x_scene_background(int scene)
{ Scene *s = scenes_get(scene); return s ? text_rgb(s->bg) : text_empty(); }

LC_API void r3x_scene_set_ambient(int scene, double r, double g, double b)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) { fail(k_bad_handle); return; }
    if (!rgb_ok(r, g, b)) { fail(k_bad_number); return; }
    s->ambient[0] = r / 255; s->ambient[1] = g / 255; s->ambient[2] = b / 255;
}
LC_API const char *r3x_scene_ambient(int scene)
{ Scene *s = scenes_get(scene); return s ? text_rgb(s->ambient) : text_empty(); }

/* Linear fog by depth: none nearer than fogNear, all fog colour from fogFar.
 * A fogFar of 0 turns fog off. */
LC_API void r3x_scene_set_fog(int scene, double r, double g, double b, double fogNear, double fogFar)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) { fail(k_bad_handle); return; }
    if (!rgb_ok(r, g, b) || !fin(fogNear) || !fin(fogFar) || fogNear < 0) { fail(k_bad_number); return; }
    if (fogFar == 0) { s->fogOn = 0; return; }
    if (fogFar <= fogNear) { fail("render3dxt: fog must end farther than it starts"); return; }
    s->fogOn = 1;
    s->fogColor[0] = r / 255; s->fogColor[1] = g / 255; s->fogColor[2] = b / 255;
    s->fogNear = fogNear; s->fogFar = fogFar;
}

/* Smooth edges: each pixel is the average of n x n samples (1 to 4). */
LC_API void r3x_scene_set_supersample(int scene, int n)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) { fail(k_bad_handle); return; }
    if (n < 1 || n > R3X_MAX_SUPERSAMPLE) { fail("render3dxt: supersampling is 1 to 4"); return; }
    s->ss = n;
}
LC_API int r3x_scene_supersample(int scene) { Scene *s = scenes_get(scene); return s ? s->ss : 0; }

static int camera_ok(double ex, double ey, double ez, double tx, double ty, double tz, double fov)
{
    if (!fin3(ex, ey, ez) || !fin3(tx, ty, tz)) return fail(k_bad_number);
    if (!isfinite(fov) || fov < 5.0 || fov > 150.0)
        return fail("render3dxt: the field of view is 5 to 150 degrees");
    double d = sqrt((tx - ex) * (tx - ex) + (ty - ey) * (ty - ey) + (tz - ez) * (tz - ez));
    if (!(d > 1e-6)) return fail("render3dxt: the camera's eye and target are the same point");
    return 1;
}

LC_API void r3x_scene_set_camera(int scene, double ex, double ey, double ez,
                                 double tx, double ty, double tz, double fov)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) { fail(k_bad_handle); return; }
    if (!camera_ok(ex, ey, ez, tx, ty, tz, fov)) return;
    s->eye[0] = ex; s->eye[1] = ey; s->eye[2] = ez;
    s->target[0] = tx; s->target[1] = ty; s->target[2] = tz;
    s->fov = fov;
}

/* "ex,ey,ez,tx,ty,tz,fov": b3RenderCamera()'s text, taken whole. */
LC_API void r3x_scene_set_camera_text(int scene, const char *text)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) { fail(k_bad_handle); return; }
    double d[8];
    int n = text ? parse_items(text, text + strlen(text), d, 8) : -1;
    if (n != 7) { fail("render3dxt: a camera is seven numbers, ex,ey,ez,tx,ty,tz,fov"); return; }
    r3x_scene_set_camera(scene, d[0], d[1], d[2], d[3], d[4], d[5], d[6]);
}

LC_API const char *r3x_scene_camera(int scene)
{
    Scene *s = scenes_get(scene);
    if (!s) return text_empty();
    double d[7] = { s->eye[0], s->eye[1], s->eye[2], s->target[0], s->target[1], s->target[2], s->fov };
    return text_of(d, 7);
}

/* The near plane (metres, 0.001 up) and the far one (0 = none). */
LC_API void r3x_scene_set_clip(int scene, double nearZ, double farZ)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) { fail(k_bad_handle); return; }
    if (!fin(nearZ) || !fin(farZ) || nearZ < 0.001 || farZ < 0) { fail(k_bad_number); return; }
    if (farZ != 0 && farZ <= nearZ) { fail("render3dxt: the far plane must be beyond the near one"); return; }
    s->nearZ = nearZ; s->farZ = farZ;
}
LC_API const char *r3x_scene_clip(int scene)
{
    Scene *s = scenes_get(scene);
    if (!s) return text_empty();
    double d[2] = { s->nearZ, s->farZ };
    return text_of(d, 2);
}

/* The camera's frame: forward f, right r, up u (box3dxt's, exactly). */
typedef struct CamFrame { double eye[3], f[3], r[3], u[3], tanH; } CamFrame;
static void cam_frame(const Scene *s, CamFrame *c)
{
    double f[3] = { s->target[0] - s->eye[0], s->target[1] - s->eye[1], s->target[2] - s->eye[2] };
    double l = sqrt(f[0] * f[0] + f[1] * f[1] + f[2] * f[2]);
    if (!(l > 0)) { f[0] = 0; f[1] = 0; f[2] = -1; l = 1; }
    for (int k = 0; k < 3; k++) { f[k] /= l; c->eye[k] = s->eye[k]; c->f[k] = f[k]; }
    double up[3] = { 0, 1, 0 };
    if (fabs(f[1]) > R3X_UP_FALLBACK) { up[0] = 0; up[1] = 0; up[2] = -1; }
    double r[3] = { f[1] * up[2] - f[2] * up[1], f[2] * up[0] - f[0] * up[2], f[0] * up[1] - f[1] * up[0] };
    double rl = sqrt(r[0] * r[0] + r[1] * r[1] + r[2] * r[2]);
    for (int k = 0; k < 3; k++) c->r[k] = r[k] / rl;
    c->u[0] = c->r[1] * f[2] - c->r[2] * f[1];
    c->u[1] = c->r[2] * f[0] - c->r[0] * f[2];
    c->u[2] = c->r[0] * f[1] - c->r[1] * f[0];
    c->tanH = tan(s->fov * 3.14159265358979323846 / 360.0);
}

static int view_ok(int w, int h)
{
    if (w < 1 || h < 1 || w > R3X_MAX_SIDE || h > R3X_MAX_SIDE)
        return fail("render3dxt: a picture is 1 to 4096 pixels each way");
    return 1;
}

/* Where a world point lands in a w x h picture: "px,py,depth", or empty if
 * it is nearer than the near plane. */
LC_API const char *r3x_scene_project(int scene, int w, int h, double x, double y, double z)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) { fail(k_bad_handle); return text_empty(); }
    if (!view_ok(w, h) || !fin3(x, y, z)) { if (!*s_error) fail(k_bad_number); return text_empty(); }
    CamFrame c;
    cam_frame(s, &c);
    double d[3] = { x - c.eye[0], y - c.eye[1], z - c.eye[2] };
    double depth = d[0] * c.f[0] + d[1] * c.f[1] + d[2] * c.f[2];
    if (depth < s->nearZ) return text_empty();
    double vx = d[0] * c.r[0] + d[1] * c.r[1] + d[2] * c.r[2];
    double vy = d[0] * c.u[0] + d[1] * c.u[1] + d[2] * c.u[2];
    double aspect = (double)w / (double)h;
    double out[3] = { (vx / (depth * c.tanH * aspect) * 0.5 + 0.5) * w,
                      (0.5 - vy / (depth * c.tanH) * 0.5) * h, depth };
    return text_of(out, 3);
}

/* The ray through picture point (px, py): "ox,oy,oz,dx,dy,dz", origin the
 * eye, direction a unit vector. */
static void scene_ray(const Scene *s, int w, int h, double px, double py, double o[3], double d[3])
{
    CamFrame c;
    cam_frame(s, &c);
    double aspect = (double)w / (double)h;
    double nx = (px / w) * 2.0 - 1.0, ny = 1.0 - (py / h) * 2.0;
    for (int k = 0; k < 3; k++) {
        o[k] = c.eye[k];
        d[k] = c.f[k] + c.r[k] * nx * c.tanH * aspect + c.u[k] * ny * c.tanH;
    }
    double l = sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
    for (int k = 0; k < 3; k++) d[k] /= l;
}

LC_API const char *r3x_scene_ray(int scene, int w, int h, double px, double py)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) { fail(k_bad_handle); return text_empty(); }
    if (!view_ok(w, h)) return text_empty();
    if (!fin(px) || !fin(py)) { fail(k_bad_number); return text_empty(); }
    double o[3], d[3];
    scene_ray(s, w, h, px, py, o, d);
    double out[6] = { o[0], o[1], o[2], d[0], d[1], d[2] };
    return text_of(out, 6);
}

/* ------------------------------------------------------------------ */
/* Lights                                                              */
/* ------------------------------------------------------------------ */
static int light_add(int scene, Light *L)
{
    Scene *s = scenes_get(scene);
    if (!s) { free(L); return fail(k_bad_handle); }
    if (s->lightCount >= R3X_MAX_LIGHTS) { free(L); return fail("render3dxt: a scene has at most 8 lights"); }
    int h = lights_add(L);
    if (!h) { free(L); return fail(k_no_memory); }
    L->scene = scene;
    s->lights[s->lightCount++] = h;
    return h;
}

static int color_in(double r, double g, double b, double intensity, double out[3])
{
    if (!rgb_ok(r, g, b) || !isfinite(intensity) || intensity < 0 || intensity > 100) return 0;
    out[0] = r / 255; out[1] = g / 255; out[2] = b / 255;
    return 1;
}

/* A light from infinitely far away, travelling in direction (dx,dy,dz). */
LC_API int r3x_light_create_directional(int scene, double dx, double dy, double dz,
                                        double r, double g, double b, double intensity)
{
    ok_clear();
    if (!scenes_get(scene)) return fail(k_bad_handle);
    Light *L = (Light *)calloc(1, sizeof(Light));
    if (!L) return fail(k_no_memory);
    if (!dir_in(dx, dy, dz, L->v) || !color_in(r, g, b, intensity, L->color)) {
        free(L); return fail(k_bad_number);
    }
    L->kind = R3X_LIGHT_DIRECTIONAL; L->intensity = intensity; L->enabled = 1;
    return light_add(scene, L);
}

/* A light at a point, fading to nothing at `range` metres (0 = no limit,
 * fading with the square of the distance instead). */
LC_API int r3x_light_create_point(int scene, double x, double y, double z,
                                  double r, double g, double b, double intensity, double range)
{
    ok_clear();
    if (!scenes_get(scene)) return fail(k_bad_handle);
    Light *L = (Light *)calloc(1, sizeof(Light));
    if (!L) return fail(k_no_memory);
    if (!fin3(x, y, z) || !color_in(r, g, b, intensity, L->color) || !fin(range) || range < 0) {
        free(L); return fail(k_bad_number);
    }
    L->kind = R3X_LIGHT_POINT; L->v[0] = x; L->v[1] = y; L->v[2] = z;
    L->intensity = intensity; L->range = range; L->enabled = 1;
    return light_add(scene, L);
}

static void light_release(int h)
{
    Light *L = lights_get(h);
    if (!L) return;
    Scene *s = scenes_get(L->scene);
    if (s) {
        for (int i = 0; i < s->lightCount; i++)
            if (s->lights[i] == h) {
                memmove(s->lights + i, s->lights + i + 1, (size_t)(s->lightCount - i - 1) * sizeof(int));
                s->lightCount--;
                break;
            }
    }
    free(L);
    lights_free_handle(h);
}

LC_API void r3x_light_destroy(int light)
{
    ok_clear();
    if (!lights_get(light)) { fail(k_bad_handle); return; }
    light_release(light);
}
LC_API int r3x_light_is_valid(int light) { return lights_get(light) ? 1 : 0; }

LC_API int r3x_scene_light_count(int scene) { Scene *s = scenes_get(scene); return s ? s->lightCount : 0; }
LC_API int r3x_scene_light(int scene, int index)
{
    Scene *s = scenes_get(scene);
    if (!s || index < 1 || index > s->lightCount) return 0;
    return s->lights[index - 1];
}

LC_API void r3x_light_set_color(int light, double r, double g, double b, double intensity)
{
    ok_clear();
    Light *L = lights_get(light);
    if (!L) { fail(k_bad_handle); return; }
    double c[3];
    if (!color_in(r, g, b, intensity, c)) { fail(k_bad_number); return; }
    memcpy(L->color, c, sizeof c);
    L->intensity = intensity;
}

/* "r,g,b,intensity" */
LC_API const char *r3x_light_color(int light)
{
    Light *L = lights_get(light);
    if (!L) return text_empty();
    double d[4] = { floor(L->color[0] * 255 + 0.5), floor(L->color[1] * 255 + 0.5),
                    floor(L->color[2] * 255 + 0.5), L->intensity };
    return text_of(d, 4);
}

LC_API void r3x_light_set_direction(int light, double dx, double dy, double dz)
{
    ok_clear();
    Light *L = lights_get(light);
    if (!L) { fail(k_bad_handle); return; }
    if (L->kind != R3X_LIGHT_DIRECTIONAL) { fail("render3dxt: only a directional light has a direction"); return; }
    double v[3];
    if (!dir_in(dx, dy, dz, v)) { fail(k_bad_number); return; }
    memcpy(L->v, v, sizeof v);
}

LC_API void r3x_light_set_position(int light, double x, double y, double z)
{
    ok_clear();
    Light *L = lights_get(light);
    if (!L) { fail(k_bad_handle); return; }
    if (L->kind != R3X_LIGHT_POINT) { fail("render3dxt: only a point light has a position"); return; }
    if (!fin3(x, y, z)) { fail(k_bad_number); return; }
    L->v[0] = x; L->v[1] = y; L->v[2] = z;
}

/* The direction (directional) or the position (point), "x,y,z". */
LC_API const char *r3x_light_vector(int light)
{
    Light *L = lights_get(light);
    return L ? text_of(L->v, 3) : text_empty();
}

LC_API int r3x_light_kind(int light) { Light *L = lights_get(light); return L ? L->kind + 1 : 0; }

LC_API void r3x_light_set_enabled(int light, int flag)
{ Light *L = lights_get(light); if (L) L->enabled = flag ? 1 : 0; }
LC_API int r3x_light_is_enabled(int light)
{ Light *L = lights_get(light); return L ? L->enabled : 0; }

/* ================================================================== */
/* Nodes: a mesh placed in a scene                                     */
/* ================================================================== */
LC_API int r3x_node_create(int scene, int mesh)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) return fail(k_bad_handle);
    if (mesh != 0 && !meshes_get(mesh)) return fail(k_bad_handle);
    if (s->nodeCount >= s->nodeCap) {
        int nc = s->nodeCap ? s->nodeCap * 2 : 64;
        int *p = (int *)realloc(s->nodes, (size_t)nc * sizeof(int));
        if (!p) return fail(k_no_memory);
        s->nodes = p; s->nodeCap = nc;
    }
    Node *n = (Node *)calloc(1, sizeof(Node));
    if (!n) return fail(k_no_memory);
    n->scene = scene; n->mesh = mesh; n->rot[3] = 1;
    n->scale[0] = n->scale[1] = n->scale[2] = 1; n->visible = 1;
    int h = nodes_add(n);
    if (!h) { free(n); return fail(k_no_memory); }
    n->listIndex = s->nodeCount;
    s->nodes[s->nodeCount++] = h;
    return h;
}

static void node_release(int h)
{
    Node *n = nodes_get(h);
    if (!n) return;
    Scene *s = scenes_get(n->scene);
    if (s && n->listIndex < s->nodeCount && s->nodes[n->listIndex] == h) {
        int last = s->nodes[--s->nodeCount];
        if (last != h) {
            s->nodes[n->listIndex] = last;
            Node *ln = nodes_get(last);
            if (ln) ln->listIndex = n->listIndex;
        }
    }
    free(n);
    nodes_free_handle(h);
}

LC_API void r3x_node_destroy(int node)
{
    ok_clear();
    if (!nodes_get(node)) { fail(k_bad_handle); return; }
    node_release(node);
}

LC_API int r3x_node_is_valid(int node) { return nodes_get(node) ? 1 : 0; }
LC_API int r3x_node_scene(int node) { Node *n = nodes_get(node); return n ? n->scene : 0; }
LC_API int r3x_scene_node_count(int scene) { Scene *s = scenes_get(scene); return s ? s->nodeCount : 0; }
LC_API int r3x_scene_node(int scene, int index)
{
    Scene *s = scenes_get(scene);
    if (!s || index < 1 || index > s->nodeCount) return 0;
    return s->nodes[index - 1];
}

LC_API void r3x_node_set_mesh(int node, int mesh)
{
    ok_clear();
    Node *n = nodes_get(node);
    if (!n) { fail(k_bad_handle); return; }
    if (mesh != 0 && !meshes_get(mesh)) { fail(k_bad_handle); return; }
    n->mesh = mesh;
}
LC_API int r3x_node_mesh(int node)
{
    Node *n = nodes_get(node);
    return (n && meshes_get(n->mesh)) ? n->mesh : 0;
}

/* A material for every triangle of the node, in place of the mesh's own
 * (0 goes back to the mesh's). */
LC_API void r3x_node_set_material(int node, int material)
{
    ok_clear();
    Node *n = nodes_get(node);
    if (!n) { fail(k_bad_handle); return; }
    if (material != 0 && !materials_get(material)) { fail(k_bad_handle); return; }
    n->material = material;
}
LC_API int r3x_node_material(int node)
{
    Node *n = nodes_get(node);
    return (n && materials_get(n->material)) ? n->material : 0;
}

LC_API void r3x_node_set_position(int node, double x, double y, double z)
{
    ok_clear();
    Node *n = nodes_get(node);
    if (!n) { fail(k_bad_handle); return; }
    if (!fin3(x, y, z)) { fail(k_bad_number); return; }
    n->pos[0] = x; n->pos[1] = y; n->pos[2] = z;
}

LC_API void r3x_node_set_rotation(int node, double qx, double qy, double qz, double qw)
{
    ok_clear();
    Node *n = nodes_get(node);
    if (!n) { fail(k_bad_handle); return; }
    double q[4];
    if (!quat_in(qx, qy, qz, qw, q)) { fail(k_bad_number); return; }
    memcpy(n->rot, q, sizeof q);
}

LC_API void r3x_node_set_transform(int node, double x, double y, double z,
                                   double qx, double qy, double qz, double qw)
{
    ok_clear();
    Node *n = nodes_get(node);
    if (!n) { fail(k_bad_handle); return; }
    double q[4];
    if (!fin3(x, y, z) || !quat_in(qx, qy, qz, qw, q)) { fail(k_bad_number); return; }
    n->pos[0] = x; n->pos[1] = y; n->pos[2] = z;
    memcpy(n->rot, q, sizeof q);
}

/* "x,y,z,qx,qy,qz,qw": b3BodyTransform's text, taken whole. */
LC_API void r3x_node_set_transform_text(int node, const char *text)
{
    ok_clear();
    if (!nodes_get(node)) { fail(k_bad_handle); return; }
    double d[8];
    int n = text ? parse_items(text, text + strlen(text), d, 8) : -1;
    if (n != 7) { fail("render3dxt: a transform is seven numbers, x,y,z,qx,qy,qz,qw"); return; }
    r3x_node_set_transform(node, d[0], d[1], d[2], d[3], d[4], d[5], d[6]);
}

LC_API void r3x_node_set_scale(int node, double sx, double sy, double sz)
{
    ok_clear();
    Node *n = nodes_get(node);
    if (!n) { fail(k_bad_handle); return; }
    if (!size_ok(fabs(sx)) || !size_ok(fabs(sy)) || !size_ok(fabs(sz))) { fail(k_bad_number); return; }
    n->scale[0] = sx; n->scale[1] = sy; n->scale[2] = sz;
}

LC_API const char *r3x_node_position(int node)
{ Node *n = nodes_get(node); return n ? text_of(n->pos, 3) : text_empty(); }
LC_API const char *r3x_node_rotation(int node)
{ Node *n = nodes_get(node); return n ? text_of(n->rot, 4) : text_empty(); }
LC_API const char *r3x_node_scale(int node)
{ Node *n = nodes_get(node); return n ? text_of(n->scale, 3) : text_empty(); }
LC_API const char *r3x_node_transform(int node)
{
    Node *n = nodes_get(node);
    if (!n) return text_empty();
    double d[7] = { n->pos[0], n->pos[1], n->pos[2], n->rot[0], n->rot[1], n->rot[2], n->rot[3] };
    return text_of(d, 7);
}

LC_API void r3x_node_set_visible(int node, int flag)
{ Node *n = nodes_get(node); if (n) n->visible = flag ? 1 : 0; }
LC_API int r3x_node_is_visible(int node)
{ Node *n = nodes_get(node); return n ? n->visible : 0; }

/* A number of the script's choosing, normally the box3dxt body the node
 * draws: r3SceneApplyMoves moves the nodes whose tag is a moved body. */
LC_API void r3x_node_set_tag(int node, int tag)
{ Node *n = nodes_get(node); if (n) n->tag = tag; }
LC_API int r3x_node_tag(int node)
{ Node *n = nodes_get(node); return n ? n->tag : 0; }

/* The first node of a scene with that tag, or 0. */
LC_API int r3x_scene_node_by_tag(int scene, int tag)
{
    Scene *s = scenes_get(scene);
    if (!s || tag == 0) return 0;
    for (int i = 0; i < s->nodeCount; i++) {
        Node *n = nodes_get(s->nodes[i]);
        if (n && n->tag == tag) return s->nodes[i];
    }
    return 0;
}

/* b3MovesText() whole: lines "body,x,y,z,qx,qy,qz,qw[,fellAsleep]". Every
 * node of the scene tagged with a line's body takes that transform. Lines
 * whose body no node is tagged with are skipped (a body may have nothing
 * drawn for it); a line that is not a transform is a refusal that names
 * it, and the lines before it stay applied. Returns how many nodes moved. */
LC_API int r3x_scene_apply_moves(int scene, const char *text)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) return fail(k_bad_handle);
    if (!text) return 0;
    /* a small open-addressed table from tag to the first node in a chain */
    int cap = 16;
    while (cap < s->nodeCount * 2) cap *= 2;
    int *keys = (int *)malloc((size_t)cap * sizeof(int));
    int *head = (int *)malloc((size_t)cap * sizeof(int));
    int *next = (int *)malloc((size_t)(s->nodeCount + 1) * sizeof(int));
    if (!keys || !head || !next) { free(keys); free(head); free(next); return fail(k_no_memory); }
    for (int i = 0; i < cap; i++) { keys[i] = 0; head[i] = -1; }
    for (int i = 0; i < s->nodeCount; i++) {
        Node *n = nodes_get(s->nodes[i]);
        next[i] = -1;
        if (!n || n->tag == 0) continue;
        unsigned hsh = ((unsigned)n->tag * 2654435761u) & (unsigned)(cap - 1);
        while (keys[hsh] != 0 && keys[hsh] != n->tag) hsh = (hsh + 1) & (unsigned)(cap - 1);
        keys[hsh] = n->tag;
        next[i] = head[hsh];
        head[hsh] = i;
    }
    int moved = 0, line = 0;
    const char *p = text;
    while (*p) {
        const char *e = p;
        while (*e && *e != '\n' && *e != '\r') e++;
        line++;
        const char *q = p;
        while (q < e && (*q == ' ' || *q == '\t')) q++;
        if (q < e) {
            double d[10];
            int n = parse_items(p, e, d, 10);
            double rq[4];
            if ((n != 8 && n != 9) || !isfinite(d[0]) || d[0] != floor(d[0]) ||
                d[0] < -2147483647.0 || d[0] > 2147483647.0 ||
                !fin3(d[1], d[2], d[3]) || !quat_in(d[4], d[5], d[6], d[7], rq)) {
                snprintf(s_lineError, sizeof(s_lineError),
                         "render3dxt: move line %d is not body,x,y,z,qx,qy,qz,qw", line);
                free(keys); free(head); free(next);
                fail(s_lineError);
                return moved;
            }
            int tag = (int)d[0];
            if (tag != 0) {
                unsigned hsh = ((unsigned)tag * 2654435761u) & (unsigned)(cap - 1);
                while (keys[hsh] != 0 && keys[hsh] != tag) hsh = (hsh + 1) & (unsigned)(cap - 1);
                if (keys[hsh] == tag) {
                    for (int i = head[hsh]; i >= 0; i = next[i]) {
                        Node *nd = nodes_get(s->nodes[i]);
                        if (!nd) continue;
                        nd->pos[0] = d[1]; nd->pos[1] = d[2]; nd->pos[2] = d[3];
                        memcpy(nd->rot, rq, sizeof rq);
                        moved++;
                    }
                }
            }
        }
        p = e;
        while (*p == '\n' || *p == '\r') p++;
    }
    free(keys); free(head); free(next);
    return moved;
}

/* ================================================================== */
/* Rendering                                                           */
/* ================================================================== */
/* Rotation matrix of a unit quaternion (row-major). */
static void quat_matrix(const double q[4], double m[9])
{
    double x = q[0], y = q[1], z = q[2], w = q[3];
    m[0] = 1 - 2 * (y * y + z * z); m[1] = 2 * (x * y - z * w);     m[2] = 2 * (x * z + y * w);
    m[3] = 2 * (x * y + z * w);     m[4] = 1 - 2 * (x * x + z * z); m[5] = 2 * (y * z - x * w);
    m[6] = 2 * (x * z - y * w);     m[7] = 2 * (y * z + x * w);     m[8] = 1 - 2 * (x * x + y * y);
}

/* Per-vertex scratch, reused frame to frame. */
static float *s_vw = NULL;     /* world position, 3 per vertex          */
static float *s_vn = NULL;     /* world normal, 3                        */
static float *s_vv = NULL;     /* view x, y, depth, 3                    */
static float *s_lit = NULL;    /* cached light: diffuse 3, specular 3    */
static int *s_litKey = NULL;   /* which material/side the cache is for   */
static int s_scratchCap = 0;

static int scratch_reserve(int n)
{
    if (n <= s_scratchCap) return 1;
    int nc = s_scratchCap ? s_scratchCap : 1024;
    while (nc < n) nc *= 2;
    float *a = (float *)realloc(s_vw, (size_t)nc * 3 * sizeof(float)); if (!a) return 0; s_vw = a;
    a = (float *)realloc(s_vn, (size_t)nc * 3 * sizeof(float)); if (!a) return 0; s_vn = a;
    a = (float *)realloc(s_vv, (size_t)nc * 3 * sizeof(float)); if (!a) return 0; s_vv = a;
    a = (float *)realloc(s_lit, (size_t)nc * 6 * sizeof(float)); if (!a) return 0; s_lit = a;
    int *k = (int *)realloc(s_litKey, (size_t)nc * sizeof(int)); if (!k) return 0; s_litKey = k;
    s_scratchCap = nc;
    return 1;
}

/* What the rasterizer needs to know about the lights, in world space. */
typedef struct LightW { int kind; float v[3]; float c[3]; float range; } LightW;
typedef struct Frame {
    int W, H;
    uint32_t *color; float *depth;
    float invFar;                 /* 1/far, or 0 */
    float amb[3];
    LightW L[R3X_MAX_LIGHTS]; int nL;
    float eye[3];
    int fogOn; float fogC[3], fogN, fogF;
    double tris, pixels;
    /* the two whole-picture steps, done band by band beside the drawing */
    uint32_t bg; int cleared;     /* the background; 1 once every band has it */
    unsigned char *out;           /* the picture a script gets, w x h x 4     */
    int outW, outH, ss;
} Frame;

/* Gouraud lighting at one point: diffuse into d, highlight into sp. */
static void shade_vertex(const Frame *fr, const Material *mat, const float P[3], const float N[3],
                         float d[3], float sp[3])
{
    d[0] = fr->amb[0]; d[1] = fr->amb[1]; d[2] = fr->amb[2];
    sp[0] = sp[1] = sp[2] = 0;
    float ks = mat ? mat->ks : 0.0f, shin = mat ? mat->shininess : 32.0f;
    float V[3] = { fr->eye[0] - P[0], fr->eye[1] - P[1], fr->eye[2] - P[2] };
    float vl = sqrtf(V[0] * V[0] + V[1] * V[1] + V[2] * V[2]);
    if (vl > 0) { V[0] /= vl; V[1] /= vl; V[2] /= vl; }
    for (int i = 0; i < fr->nL; i++) {
        const LightW *L = &fr->L[i];
        float Ld[3], att = 1.0f;
        if (L->kind == R3X_LIGHT_DIRECTIONAL) {
            Ld[0] = -L->v[0]; Ld[1] = -L->v[1]; Ld[2] = -L->v[2];
        } else {
            Ld[0] = L->v[0] - P[0]; Ld[1] = L->v[1] - P[1]; Ld[2] = L->v[2] - P[2];
            float dist = sqrtf(Ld[0] * Ld[0] + Ld[1] * Ld[1] + Ld[2] * Ld[2]);
            if (dist < 1e-6f) continue;
            Ld[0] /= dist; Ld[1] /= dist; Ld[2] /= dist;
            if (L->range > 0) {
                float f = 1.0f - dist / L->range;
                if (f <= 0) continue;
                att = f * f;
            } else {
                att = 1.0f / (1.0f + dist * dist);
            }
        }
        float ndl = N[0] * Ld[0] + N[1] * Ld[1] + N[2] * Ld[2];
        if (ndl <= 0) continue;
        float k = ndl * att;
        d[0] += L->c[0] * k; d[1] += L->c[1] * k; d[2] += L->c[2] * k;
        if (ks > 0) {
            float Hh[3] = { Ld[0] + V[0], Ld[1] + V[1], Ld[2] + V[2] };
            float hl = sqrtf(Hh[0] * Hh[0] + Hh[1] * Hh[1] + Hh[2] * Hh[2]);
            if (hl > 0) {
                float ndh = (N[0] * Hh[0] + N[1] * Hh[1] + N[2] * Hh[2]) / hl;
                if (ndh > 0) {
                    float sv = powf(ndh, shin) * ks * att;
                    sp[0] += L->c[0] * sv; sp[1] += L->c[1] * sv; sp[2] += L->c[2] * sv;
                }
            }
        }
    }
}

/* A vertex on its way to the screen. */
typedef struct CV {
    float x, y, z;        /* view: right, up, depth (metres, > 0 in front) */
    float u, v;
    float d[3], s[3];
    float fog;
} CV;

static CV cv_lerp(const CV *a, const CV *b, float t)
{
    CV r;
    const float *pa = (const float *)a, *pb = (const float *)b;
    float *pr = (float *)&r;
    for (size_t i = 0; i < sizeof(CV) / sizeof(float); i++) pr[i] = pa[i] + (pb[i] - pa[i]) * t;
    return r;
}

/* A vertex on the screen: position, 1/depth, and attributes times 1/depth. */
typedef struct SV {
    float sx, sy, iw;
    float u, v, d[3], s[3], fog;
} SV;

typedef struct DrawState {
    const Material *mat;
    const Texture *tex;
    float kd[3], ke[3];
} DrawState;

/* Two 0xAARRGGBB colours blended, t from 0 (all a) to 256 (all b): two
 * multiplies for four channels. */
static inline uint32_t lerp8(uint32_t a, uint32_t b, uint32_t t)
{
    uint32_t rb = ((((a & 0x00FF00FFu) * (256u - t)) + ((b & 0x00FF00FFu) * t)) >> 8) & 0x00FF00FFu;
    uint32_t ag = ((((a >> 8) & 0x00FF00FFu) * (256u - t)) + (((b >> 8) & 0x00FF00FFu) * t)) & 0xFF00FF00u;
    return rb | ag;
}

/* A texture coordinate far outside the picture (or not a number), brought
 * to 0..1 the slow way. Rare: tex_sample takes it only beyond +-64. */
static float tex_fold(float u, int rep)
{
    if (!(u > -1e6f && u < 1e6f)) return 0;
    if (!rep) return u < 0 ? 0.0f : 1.0f;
    u -= floorf(u);
    return (u >= 0 && u < 1.0f) ? u : 0.0f;
}

/* One texel, 0xAARRGGBB. This runs once per pixel drawn, so it has no
 * division and no libm call (the first version wrapped with % four times a
 * sample and was most of a frame), and its two common cases work in fixed
 * point, 8 fractional bits a texel (measured 2026-11-20: bilinear from 26 ns
 * a pixel to under half that):
 *   - a repeating texture whose sides are powers of two wraps with a mask;
 *   - a clamped texture of any size clamps the integers.
 * A repeating texture of any other size keeps the float path. Every
 * conversion to int is of a value already held in range. */
static inline uint32_t tex_sample(const Texture *t, float u, float v)
{
    const int w = t->w, h = t->h, rep = t->repeat;
    if (!(u > -64.0f && u < 64.0f)) u = tex_fold(u, rep);
    if (!(v > -64.0f && v < 64.0f)) v = tex_fold(v, rep);
    if (rep && t->pow2) {
        /* +65 keeps the value positive, so truncation is floor; at most
         * 129 * 8192 * 256 < 2^31 */
        int fx = (int)(((double)u + 65.0) * (double)(w * 256));
        int fy = (int)(((double)v + 65.0) * (double)(h * 256));
        if (!t->smooth) return t->px[(size_t)((fy >> 8) & (h - 1)) * (size_t)w + (size_t)((fx >> 8) & (w - 1))];
        fx -= 128; fy -= 128;                  /* a texel's centre is at its middle */
        int x0 = (fx >> 8) & (w - 1), y0 = (fy >> 8) & (h - 1);
        int x1 = (x0 + 1) & (w - 1), y1 = (y0 + 1) & (h - 1);
        const uint32_t *r0 = t->px + (size_t)y0 * (size_t)w, *r1 = t->px + (size_t)y1 * (size_t)w;
        uint32_t wx = (uint32_t)(fx & 255), wy = (uint32_t)(fy & 255);
        return lerp8(lerp8(r0[x0], r0[x1], wx), lerp8(r1[x0], r1[x1], wx), wy);
    }
    if (!rep) {
        u = u < 0 ? 0 : (u > 1 ? 1 : u);
        v = v < 0 ? 0 : (v > 1 ? 1 : v);
        int fx = (int)((double)u * (double)(w * 256)), fy = (int)((double)v * (double)(h * 256));
        if (!t->smooth) {
            int x = fx >> 8, y = fy >> 8;
            if (x >= w) x = w - 1;
            if (y >= h) y = h - 1;
            return t->px[(size_t)y * (size_t)w + (size_t)x];
        }
        fx += 128; fy += 128;                  /* +256 (kept positive) - 128 (the half texel) */
        int x0 = (fx >> 8) - 1, y0 = (fy >> 8) - 1;
        int x1 = x0 + 1, y1 = y0 + 1;
        if (x0 < 0) x0 = 0;
        if (y0 < 0) y0 = 0;
        if (x1 >= w) x1 = w - 1;
        if (y1 >= h) y1 = h - 1;
        if (x0 >= w) x0 = w - 1;
        if (y0 >= h) y0 = h - 1;
        const uint32_t *r0 = t->px + (size_t)y0 * (size_t)w, *r1 = t->px + (size_t)y1 * (size_t)w;
        uint32_t wx = (uint32_t)(fx & 255), wy = (uint32_t)(fy & 255);
        return lerp8(lerp8(r0[x0], r0[x1], wx), lerp8(r1[x0], r1[x1], wx), wy);
    }
    /* repeating, and a side that is not a power of two */
    u -= (float)(int)u; if (u < 0) u += 1.0f;
    v -= (float)(int)v; if (v < 0) v += 1.0f;
    float fx = u * (float)w, fy = v * (float)h;
    if (!t->smooth) {
        int x = (int)fx, y = (int)fy;
        if (x >= w) x = w - 1;
        if (y >= h) y = h - 1;
        return t->px[(size_t)y * (size_t)w + (size_t)x];
    }
    fx -= 0.5f; fy -= 0.5f;                    /* now -0.5 .. size - 0.5 */
    int x0 = (int)(fx + 1.0f) - 1, y0 = (int)(fy + 1.0f) - 1;
    uint32_t wx = (uint32_t)((fx - (float)x0) * 256.0f), wy = (uint32_t)((fy - (float)y0) * 256.0f);
    if (wx > 256u) wx = 256u;
    if (wy > 256u) wy = 256u;
    int x1 = x0 + 1, y1 = y0 + 1;
    if (x0 < 0) x0 = w - 1;
    if (y0 < 0) y0 = h - 1;
    if (x1 >= w) x1 = 0;
    if (y1 >= h) y1 = 0;
    if (x0 >= w) x0 = w - 1;
    if (y0 >= h) y0 = h - 1;
    const uint32_t *r0 = t->px + (size_t)y0 * (size_t)w, *r1 = t->px + (size_t)y1 * (size_t)w;
    return lerp8(lerp8(r0[x0], r0[x1], wx), lerp8(r1[x0], r1[x1], wx), wy);
}

static inline uint32_t pack_rgb(float r, float g, float b)
{
    int R = (int)(clampf(r, 0, 1) * 255.0f + 0.5f);
    int G = (int)(clampf(g, 0, 1) * 255.0f + 0.5f);
    int B = (int)(clampf(b, 0, 1) * 255.0f + 0.5f);
    return ((uint32_t)R << 16) | ((uint32_t)G << 8) | (uint32_t)B;
}

/* The fill rule: a pixel centre exactly on an edge belongs to the triangle
 * only if the edge is a top or a left one, so two triangles that share an
 * edge never both draw a pixel and never both leave it. */
static inline int top_left(float ax, float ay, float bx, float by)
{
    float ex = bx - ax, ey = by - ay;
    return (ey < 0) || (ey == 0 && ex > 0);
}

/* A triangle ready to fill: oriented, with its pixel bounds. */
typedef struct TriJob {
    SV a, b, c;
    DrawState ds;
    float inv;                 /* 1 / (twice the area) */
    int x0, x1, y0, y1;        /* inclusive, inside the picture */
    unsigned char tl0, tl1, tl2;
} TriJob;

/* Orients and bounds a triangle. Returns 0 if nothing of it can be drawn. */
static int job_setup(const Frame *fr, TriJob *j)
{
    float area = (j->b.sx - j->a.sx) * (j->c.sy - j->a.sy) - (j->b.sy - j->a.sy) * (j->c.sx - j->a.sx);
    if (!(fabsf(area) > 1e-12f)) return 0;
    if (area < 0) { SV t = j->b; j->b = j->c; j->c = t; area = -area; }
    const SV *a = &j->a, *b = &j->b, *c = &j->c;
    float minx = a->sx < b->sx ? a->sx : b->sx, maxx = a->sx > b->sx ? a->sx : b->sx;
    float miny = a->sy < b->sy ? a->sy : b->sy, maxy = a->sy > b->sy ? a->sy : b->sy;
    if (c->sx < minx) minx = c->sx;
    if (c->sx > maxx) maxx = c->sx;
    if (c->sy < miny) miny = c->sy;
    if (c->sy > maxy) maxy = c->sy;
    if (!(maxx >= 0 && maxy >= 0 && minx < (float)fr->W && miny < (float)fr->H)) return 0;
    /* clamped in float BEFORE the conversion: a float out of int's range
     * converted to int is undefined behaviour. Truncation is floor here
     * (nothing is negative after the clamp), and a pixel centre is at +0.5,
     * so floor(min) and floor(max) bound every centre inside. */
    j->x0 = (int)clampf(minx, 0, (float)(fr->W - 1));
    j->x1 = (int)clampf(maxx, 0, (float)(fr->W - 1));
    j->y0 = (int)clampf(miny, 0, (float)(fr->H - 1));
    j->y1 = (int)clampf(maxy, 0, (float)(fr->H - 1));
    j->inv = 1.0f / area;
    j->tl0 = (unsigned char)top_left(b->sx, b->sy, c->sx, c->sy);
    j->tl1 = (unsigned char)top_left(c->sx, c->sy, a->sx, a->sy);
    j->tl2 = (unsigned char)top_left(a->sx, a->sy, b->sx, b->sy);
    return 1;
}

/* Fills the rows of a triangle that lie in [ylo, yhi). */
static void raster_triangle(const Frame *fr, const TriJob *j, int ylo, int yhi, double *pixels)
{
    int y0 = j->y0 < ylo ? ylo : j->y0, y1 = j->y1 > yhi - 1 ? yhi - 1 : j->y1;
    if (y0 > y1) return;
    const SV a = j->a, b = j->b, c = j->c;
    const DrawState *ds = &j->ds;
    const int x0 = j->x0, x1 = j->x1;
    /* edge functions: w0 opposite a (edge b->c), w1 opposite b, w2 opposite
     * c; each grows by its A for one pixel to the right */
    const float A0 = b.sy - c.sy, A1 = c.sy - a.sy, A2 = a.sy - b.sy;
    const int tl0 = j->tl0, tl1 = j->tl1, tl2 = j->tl2;
    const float inv = j->inv;
    const Material *mat = ds->mat;
    const Texture *tex = ds->tex;
    const int unlit = mat ? mat->unlit : 0, cutout = mat ? mat->cutout : 0;
    const int fogOn = fr->fogOn;
    const float invFar = fr->invFar;
    const float k255 = 1.0f / 255.0f;
    double written = 0;

    /* Every interpolated quantity is a plane over the picture: its value is
     * l0*pa + l1*pb + l2*pc with l = w * inv and w linear in x, so one pixel
     * to the right adds a constant. Ten of them (1/depth, then u, v, light,
     * highlight and fog, each already divided by depth) step with ten adds a
     * pixel in place of thirty multiplies (measured 2026-11-20). The start of
     * each row's run is computed in full, so a row's values depend only on
     * the row: the picture is the same whichever thread draws it. */
    enum { Q_IW, Q_U, Q_V, Q_D0, Q_D1, Q_D2, Q_S0, Q_S1, Q_S2, Q_FOG, Q_N };
    const float qa[Q_N] = { a.iw, a.u, a.v, a.d[0], a.d[1], a.d[2], a.s[0], a.s[1], a.s[2], a.fog };
    const float qb[Q_N] = { b.iw, b.u, b.v, b.d[0], b.d[1], b.d[2], b.s[0], b.s[1], b.s[2], b.fog };
    const float qc[Q_N] = { c.iw, c.u, c.v, c.d[0], c.d[1], c.d[2], c.s[0], c.s[1], c.s[2], c.fog };
    float step[Q_N];
    for (int k = 0; k < Q_N; k++) step[k] = (A0 * qa[k] + A1 * qb[k] + A2 * qc[k]) * inv;

    for (int y = y0; y <= y1; y++) {
        float py = (float)y + 0.5f, px = (float)x0 + 0.5f;
        float w0 = (b.sx - px) * (c.sy - py) - (b.sy - py) * (c.sx - px);
        float w1 = (c.sx - px) * (a.sy - py) - (c.sy - py) * (a.sx - px);
        float w2 = (a.sx - px) * (b.sy - py) - (a.sy - py) * (b.sx - px);
        float *drow = fr->depth + (size_t)y * (size_t)fr->W;
        uint32_t *crow = fr->color + (size_t)y * (size_t)fr->W;
        int x = x0;
        /* skip to the first pixel inside */
        for (; x <= x1; x++, w0 += A0, w1 += A1, w2 += A2) {
            if (!(w0 < 0 || w1 < 0 || w2 < 0 ||
                  (w0 == 0 && !tl0) || (w1 == 0 && !tl1) || (w2 == 0 && !tl2))) break;
        }
        if (x > x1) continue;
        float q[Q_N];
        {
            float l0 = w0 * inv, l1 = w1 * inv, l2 = w2 * inv;
            for (int k = 0; k < Q_N; k++) q[k] = l0 * qa[k] + l1 * qb[k] + l2 * qc[k];
        }
        for (; x <= x1; x++, w0 += A0, w1 += A1, w2 += A2) {
            /* a triangle is convex: once a row has left it, it is over */
            if (w0 < 0 || w1 < 0 || w2 < 0 ||
                (w0 == 0 && !tl0) || (w1 == 0 && !tl1) || (w2 == 0 && !tl2)) break;
            float iw = q[Q_IW];
            if (iw > drow[x] && iw >= invFar && iw > 0) {
                float z = 1.0f / iw;
                float r = ds->kd[0], g = ds->kd[1], bb = ds->kd[2];
                int keep = 1;
                if (tex) {
                    uint32_t t4 = tex_sample(tex, q[Q_U] * z, q[Q_V] * z);
                    if (cutout && (t4 >> 24) < 128u) keep = 0;
                    r *= (float)((t4 >> 16) & 255u) * k255;
                    g *= (float)((t4 >> 8) & 255u) * k255;
                    bb *= (float)(t4 & 255u) * k255;
                }
                if (keep) {
                    if (!unlit) {
                        r = r * (q[Q_D0] * z) + q[Q_S0] * z;
                        g = g * (q[Q_D1] * z) + q[Q_S1] * z;
                        bb = bb * (q[Q_D2] * z) + q[Q_S2] * z;
                    }
                    r += ds->ke[0]; g += ds->ke[1]; bb += ds->ke[2];
                    if (fogOn) {
                        float f = clampf(q[Q_FOG] * z, 0, 1);
                        r += (fr->fogC[0] - r) * f; g += (fr->fogC[1] - g) * f; bb += (fr->fogC[2] - bb) * f;
                    }
                    drow[x] = iw;
                    crow[x] = pack_rgb(r, g, bb);
                    written += 1;
                }
            }
            for (int k = 0; k < Q_N; k++) q[k] += step[k];
        }
    }
    *pixels += written;
}

static SV to_screen(const Frame *fr, const CV *v, double tanH, double aspect)
{
    SV s;
    float iw = 1.0f / v->z;
    s.sx = (float)(((double)v->x / ((double)v->z * tanH * aspect) * 0.5 + 0.5) * fr->W);
    s.sy = (float)((0.5 - (double)v->y / ((double)v->z * tanH) * 0.5) * fr->H);
    s.iw = iw;
    s.u = v->u * iw; s.v = v->v * iw;
    for (int k = 0; k < 3; k++) { s.d[k] = v->d[k] * iw; s.s[k] = v->s[k] * iw; }
    s.fog = v->fog * iw;
    return s;
}

/* ------------------------------------------------------------------ */
/* Drawing in parallel. Triangles are set up (transformed, lit,        */
/* clipped, projected) on the calling thread, in order, into a queue;  */
/* when the queue fills, and at the end of the frame, the picture is   */
/* cut into horizontal bands, several a thread, and the threads take   */
/* bands one at a time until none is left. A band is cleared, drawn    */
/* (every queued triangle, in queue order) and brought down to the     */
/* picture's size by the ONE thread that took it, so no pixel is ever  */
/* written by two threads, and within a band the order is the          */
/* single-threaded order: the picture is the same, byte for byte,      */
/* whatever the thread count and whichever thread took which band      */
/* (the smoke test holds that; TSan runs it).                          */
/* Every thread is joined before the render call returns: nothing      */
/* runs while script does (suite rule 1).                              */
/* ------------------------------------------------------------------ */
#define R3X_QUEUE 32768
#define R3X_MAX_THREADS 16

static TriJob *s_queue = NULL;
static int s_queued = 0;
static int s_threads = 0;          /* 0 = not chosen yet */

static int cpu_count(void)
{
#if defined(__EMSCRIPTEN__)
    return 1;
#elif defined(_WIN32)
    SYSTEM_INFO si;
    GetSystemInfo(&si);
    return (int)si.dwNumberOfProcessors;
#else
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n > 0 ? (int)n : 1;
#endif
}

/* How many threads draw a frame: 1 to 16. Every count gives the same
 * picture; more is faster on a large picture with many triangles. */
LC_API void r3x_set_thread_count(int n)
{
    ok_clear();
    if (n < 1 || n > R3X_MAX_THREADS) { fail("render3dxt: threads are 1 to 16"); return; }
#if defined(__EMSCRIPTEN__)
    n = 1;   /* the web build has no threads */
#endif
    s_threads = n;
}
LC_API int r3x_thread_count(void)
{
    if (s_threads == 0) {
        int n = cpu_count();
        s_threads = n < 1 ? 1 : (n > 8 ? 8 : n);
    }
    return s_threads;
}

/* One pass over the picture: the bands, and what is done to each. */
typedef struct Pass {
    Frame *fr;
    int nb, rows;              /* how many bands, and the rows in each        */
    int clear, resolve;        /* besides drawing what is queued              */
#if defined(_WIN32)
    volatile LONG next;        /* the next band nobody has taken              */
#else
    int next;
#endif
} Pass;
typedef struct Worker { Pass *p; double pixels; } Worker;

/* The next band, or one past the last. Atomic: threads take bands as they
 * finish, so a thread whose bands were empty sky goes on to help with the
 * crowded ones (equal shares of rows, the first version, left one thread
 * with most of the work: measured 2026-11-20). */
static int take_band(Pass *p)
{
#if defined(__EMSCRIPTEN__)
    return p->next++;
#elif defined(_WIN32)
    return (int)InterlockedIncrement(&p->next) - 1;
#else
    return __atomic_fetch_add(&p->next, 1, __ATOMIC_RELAXED);
#endif
}

/* Rows [ylo, yhi) of the samples, averaged ss x ss into the picture's rows
 * and laid out as imageData wants them (0,R,G,B). ylo and yhi are multiples
 * of ss. */
static void resolve_rows(const Frame *fr, int ylo, int yhi)
{
    const int ss = fr->ss, w = fr->outW;
    const size_t W = (size_t)fr->W;
    if (ss == 1) {
        const uint32_t *src = fr->color + (size_t)ylo * W;
        unsigned char *o = fr->out + (size_t)ylo * W * 4;
        size_t n = (size_t)(yhi - ylo) * W;
        for (size_t i = 0; i < n; i++) {
            uint32_t c = src[i];
            o[i * 4] = 0;
            o[i * 4 + 1] = (unsigned char)(c >> 16);
            o[i * 4 + 2] = (unsigned char)(c >> 8);
            o[i * 4 + 3] = (unsigned char)c;
        }
        return;
    }
    const unsigned div = (unsigned)(ss * ss);
    for (int y = ylo / ss; y < yhi / ss; y++) {
        unsigned char *o = fr->out + (size_t)y * (size_t)w * 4;
        for (int x = 0; x < w; x++, o += 4) {
            unsigned r = 0, g = 0, b = 0;
            for (int sy = 0; sy < ss; sy++) {
                const uint32_t *src = fr->color + ((size_t)y * ss + sy) * W + (size_t)x * ss;
                for (int sx = 0; sx < ss; sx++) {
                    uint32_t c = src[sx];
                    r += (c >> 16) & 255; g += (c >> 8) & 255; b += c & 255;
                }
            }
            o[0] = 0;
            o[1] = (unsigned char)((r + div / 2) / div);
            o[2] = (unsigned char)((g + div / 2) / div);
            o[3] = (unsigned char)((b + div / 2) / div);
        }
    }
}

/* One thread's share of a pass: bands, one at a time, until none is left.
 * A band is cleared, drawn and resolved by the one thread that took it, in
 * that order, and every queued triangle is drawn in queue order: so the
 * picture does not depend on which thread took which band, or on how many
 * threads there are. */
static void work(Worker *wk)
{
    Pass *p = wk->p;
    const Frame *fr = p->fr;
    for (;;) {
        int i = take_band(p);
        if (i >= p->nb) return;
        int ylo = i * p->rows, yhi = ylo + p->rows;
        if (yhi > fr->H) yhi = fr->H;
        if (p->clear) {
            uint32_t *c = fr->color + (size_t)ylo * (size_t)fr->W;
            float *d = fr->depth + (size_t)ylo * (size_t)fr->W;
            size_t n = (size_t)(yhi - ylo) * (size_t)fr->W;
            const uint32_t bg = fr->bg;
            for (size_t k = 0; k < n; k++) c[k] = bg;
            memset(d, 0, n * sizeof(float));      /* 0 is "nothing drawn": 1/depth of infinitely far */
        }
        for (int k = 0; k < s_queued; k++) {
            const TriJob *j = &s_queue[k];
            if (j->y1 < ylo || j->y0 >= yhi) continue;
            raster_triangle(fr, j, ylo, yhi, &wk->pixels);
        }
        if (p->resolve) resolve_rows(fr, ylo, yhi);
    }
}

#if defined(_WIN32)
static DWORD WINAPI work_main(LPVOID p) { work((Worker *)p); return 0; }
#elif !defined(__EMSCRIPTEN__)
static void *work_main(void *p) { work((Worker *)p); return NULL; }
#endif

/* Draws what is queued. The first pass of a frame also clears the picture,
 * and the last (pLast) also resolves it. */
static void flush_queue(Frame *fr, int pLast)
{
    Pass pass;
    pass.fr = fr;
    pass.clear = !fr->cleared;
    pass.resolve = pLast;
    pass.next = 0;
    if (!pass.clear && !pass.resolve && s_queued == 0) return;
    int nt = r3x_thread_count();
    /* a share thinner than 16 rows costs more to start than it saves */
    if (nt > fr->H / 16) nt = fr->H / 16;
    if (nt < 1) nt = 1;
    /* several bands a thread, so that the crowded parts of a picture are
     * shared out; a band is a whole number of output rows (ss sample rows) */
    int rows = fr->H / (nt * 6);
    if (rows < 8) rows = 8;
    rows = (rows + fr->ss - 1) / fr->ss * fr->ss;
    pass.rows = rows;
    pass.nb = (fr->H + rows - 1) / rows;
    Worker wk[R3X_MAX_THREADS];
    for (int i = 0; i < nt; i++) { wk[i].p = &pass; wk[i].pixels = 0; }
#if defined(__EMSCRIPTEN__)
    work(&wk[0]);
#else
#if defined(_WIN32)
    HANDLE th[R3X_MAX_THREADS];
#else
    pthread_t th[R3X_MAX_THREADS];
#endif
    int started[R3X_MAX_THREADS] = { 0 };
    for (int i = 1; i < nt; i++) {
#if defined(_WIN32)
        th[i] = CreateThread(NULL, 0, work_main, &wk[i], 0, NULL);
        started[i] = th[i] != NULL;
#else
        started[i] = pthread_create(&th[i], NULL, work_main, &wk[i]) == 0;
#endif
    }
    /* this thread works too, and goes on until no band is left: a thread
     * that could not be started costs time, never a band */
    work(&wk[0]);
    for (int i = 1; i < nt; i++) {
        if (!started[i]) continue;
#if defined(_WIN32)
        WaitForSingleObject(th[i], INFINITE);
        CloseHandle(th[i]);
#else
        pthread_join(th[i], NULL);
#endif
    }
#endif
    for (int i = 0; i < nt; i++) fr->pixels += wk[i].pixels;
    fr->cleared = 1;
    s_queued = 0;
}

static void queue_triangle(Frame *fr, const DrawState *ds, const SV *a, const SV *b, const SV *c)
{
    if (!s_queue) {
        s_queue = (TriJob *)malloc(sizeof(TriJob) * R3X_QUEUE);
        if (!s_queue) {
            /* no queue to be had: draw it at once, on this thread (the
             * picture cleared first, if this is the frame's first triangle) */
            TriJob one;
            if (!fr->cleared) flush_queue(fr, 0);
            one.a = *a; one.b = *b; one.c = *c; one.ds = *ds;
            if (job_setup(fr, &one)) { raster_triangle(fr, &one, 0, fr->H, &fr->pixels); fr->tris += 1; }
            return;
        }
    }
    TriJob *j = &s_queue[s_queued];
    j->a = *a; j->b = *b; j->c = *c; j->ds = *ds;
    if (!job_setup(fr, j)) return;      /* off the picture, or no area */
    s_queued++;
    fr->tris += 1;
    if (s_queued == R3X_QUEUE) flush_queue(fr, 0);
}

/* Clip a triangle at the near plane (depth >= nearZ), then draw the one or
 * two triangles left. */
static void clip_and_draw(Frame *fr, const DrawState *ds, const CV *in, float nearZ,
                          double tanH, double aspect)
{
    CV poly[4];
    int n = 0;
    for (int i = 0; i < 3; i++) {
        const CV *p = &in[i], *q = &in[(i + 1) % 3];
        int pin = p->z >= nearZ, qin = q->z >= nearZ;
        if (pin) poly[n++] = *p;
        if (pin != qin) {
            float t = (nearZ - p->z) / (q->z - p->z);
            poly[n] = cv_lerp(p, q, t);
            poly[n].z = nearZ;
            n++;
        }
    }
    if (n < 3) return;
    SV s[4];
    for (int i = 0; i < n; i++) s[i] = to_screen(fr, &poly[i], tanH, aspect);
    queue_triangle(fr, ds, &s[0], &s[1], &s[2]);
    if (n == 4) queue_triangle(fr, ds, &s[0], &s[2], &s[3]);
}

static void draw_node(Frame *fr, const Scene *sc, const CamFrame *cam, const Node *nd, double aspect)
{
    Mesh *m = meshes_get(nd->mesh);
    if (!m || m->nt == 0 || !scratch_reserve(m->nv)) return;
    double R[9];
    quat_matrix(nd->rot, R);
    const double *S = nd->scale, *T = nd->pos;
    /* normals go through R * S^-1 */
    double inv[3] = { 1.0 / S[0], 1.0 / S[1], 1.0 / S[2] };
    /* a mirror (an odd number of negative scales) turns the winding over */
    int mirrored = (S[0] < 0) ^ (S[1] < 0) ^ (S[2] < 0);
    for (int i = 0; i < m->nv; i++) {
        const float *p = m->pos + i * 3, *n = m->nrm + i * 3;
        double lx = p[0] * S[0], ly = p[1] * S[1], lz = p[2] * S[2];
        double wx = R[0] * lx + R[1] * ly + R[2] * lz + T[0];
        double wy = R[3] * lx + R[4] * ly + R[5] * lz + T[1];
        double wz = R[6] * lx + R[7] * ly + R[8] * lz + T[2];
        s_vw[i * 3] = (float)wx; s_vw[i * 3 + 1] = (float)wy; s_vw[i * 3 + 2] = (float)wz;
        double nx = n[0] * inv[0], ny = n[1] * inv[1], nz = n[2] * inv[2];
        double mx = R[0] * nx + R[1] * ny + R[2] * nz;
        double my = R[3] * nx + R[4] * ny + R[5] * nz;
        double mz = R[6] * nx + R[7] * ny + R[8] * nz;
        double nl = sqrt(mx * mx + my * my + mz * mz);
        if (nl > 0) { mx /= nl; my /= nl; mz /= nl; }
        s_vn[i * 3] = (float)mx; s_vn[i * 3 + 1] = (float)my; s_vn[i * 3 + 2] = (float)mz;
        double dx = wx - cam->eye[0], dy = wy - cam->eye[1], dz = wz - cam->eye[2];
        s_vv[i * 3] = (float)(dx * cam->r[0] + dy * cam->r[1] + dz * cam->r[2]);
        s_vv[i * 3 + 1] = (float)(dx * cam->u[0] + dy * cam->u[1] + dz * cam->u[2]);
        s_vv[i * 3 + 2] = (float)(dx * cam->f[0] + dy * cam->f[1] + dz * cam->f[2]);
        s_litKey[i] = -1;
    }
    float nearZ = (float)sc->nearZ;
    for (int t = 0; t < m->nt; t++) {
        const int *ti = m->tri + t * 3;
        int ia = ti[0], ib = ti[1], ic = ti[2];
        /* entirely behind the near plane: nothing to draw */
        if (s_vv[ia * 3 + 2] < nearZ && s_vv[ib * 3 + 2] < nearZ && s_vv[ic * 3 + 2] < nearZ) continue;
        int slot = m->triSlot[t];
        int mh = nd->material ? nd->material : (slot < m->nslots ? m->slotMat[slot] : 0);
        const Material *mat = materials_get(mh);
        if (!mat) mh = 0;
        const float *A = s_vw + ia * 3, *B = s_vw + ib * 3, *C = s_vw + ic * 3;
        float e1[3] = { B[0] - A[0], B[1] - A[1], B[2] - A[2] };
        float e2[3] = { C[0] - A[0], C[1] - A[1], C[2] - A[2] };
        float fn[3] = { e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2],
                        e1[0] * e2[1] - e1[1] * e2[0] };
        if (mirrored) { fn[0] = -fn[0]; fn[1] = -fn[1]; fn[2] = -fn[2]; }
        float toEye = fn[0] * (fr->eye[0] - A[0]) + fn[1] * (fr->eye[1] - A[1]) + fn[2] * (fr->eye[2] - A[2]);
        int back = !(toEye > 0);
        int twoSided = mat ? mat->twoSided : 0;
        if (back && !twoSided) continue;
        int flat = mat ? mat->flat : 0;
        DrawState ds;
        ds.mat = mat;
        ds.tex = mat ? textures_get(mat->texture) : NULL;
        for (int k = 0; k < 3; k++) {
            ds.kd[k] = mat ? mat->kd[k] : 1.0f;
            ds.ke[k] = mat ? mat->ke[k] : 0.0f;
        }
        float fl = sqrtf(fn[0] * fn[0] + fn[1] * fn[1] + fn[2] * fn[2]);
        if (fl > 0) { fn[0] /= fl; fn[1] /= fl; fn[2] /= fl; }
        if (back) { fn[0] = -fn[0]; fn[1] = -fn[1]; fn[2] = -fn[2]; }
        CV cv[3];
        int idx3[3] = { ia, ib, ic };
        for (int j = 0; j < 3; j++) {
            int vi = idx3[j];
            CV *v = &cv[j];
            v->x = s_vv[vi * 3]; v->y = s_vv[vi * 3 + 1]; v->z = s_vv[vi * 3 + 2];
            v->u = m->uv[vi * 2]; v->v = m->uv[vi * 2 + 1];
            if (mat && mat->unlit) {
                v->d[0] = v->d[1] = v->d[2] = 1; v->s[0] = v->s[1] = v->s[2] = 0;
            } else if (flat) {
                shade_vertex(fr, mat, s_vw + vi * 3, fn, v->d, v->s);
            } else {
                int key = mh * 2 + back;
                float *lit = s_lit + (size_t)vi * 6;
                if (s_litKey[vi] != key) {
                    float N[3] = { s_vn[vi * 3], s_vn[vi * 3 + 1], s_vn[vi * 3 + 2] };
                    if (back) { N[0] = -N[0]; N[1] = -N[1]; N[2] = -N[2]; }
                    shade_vertex(fr, mat, s_vw + vi * 3, N, lit, lit + 3);
                    s_litKey[vi] = key;
                }
                memcpy(v->d, lit, 3 * sizeof(float));
                memcpy(v->s, lit + 3, 3 * sizeof(float));
            }
            v->fog = fr->fogOn ? clampf((v->z - fr->fogN) / (fr->fogF - fr->fogN), 0, 1) : 0;
        }
        clip_and_draw(fr, &ds, cv, nearZ, cam->tanH, aspect);
    }
}

static int frame_reserve(Scene *s, size_t pixels, size_t outBytes)
{
    if (pixels > s->bufCap) {
        uint32_t *c = (uint32_t *)realloc(s->color, pixels * sizeof(uint32_t));
        if (!c) return fail(k_no_memory);
        s->color = c;
        float *d = (float *)realloc(s->depth, pixels * sizeof(float));
        if (!d) return fail(k_no_memory);
        s->depth = d;
        s->bufCap = pixels;
    }
    if (outBytes > s->frameCap) {
        unsigned char *f = (unsigned char *)realloc(s->frame, outBytes);
        if (!f) return fail(k_no_memory);
        s->frame = f;
        s->frameCap = outBytes;
    }
    return 1;
}

/* Draws the scene into a w x h picture held by the scene, in imageData's
 * layout (0,R,G,B per pixel, rows from the top). Returns the byte count,
 * w * h * 4, or 0 if refused. r3x_scene_frame is the pointer to it. */
LC_API int r3x_scene_render(int scene, int w, int h)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    if (!s) return fail(k_bad_handle);
    if (!view_ok(w, h)) return 0;
    int ss = s->ss;
    size_t W = (size_t)w * (size_t)ss, H = (size_t)h * (size_t)ss;
    if (W * H > (size_t)R3X_MAX_PIXELS) {
        return fail("render3dxt: the picture times the supersampling is more than 4096 x 4096");
    }
    size_t outBytes = (size_t)w * (size_t)h * 4;
    if (!frame_reserve(s, W * H, outBytes)) return 0;
    double t0 = now_ms();

    Frame fr;
    memset(&fr, 0, sizeof fr);
    fr.W = (int)W; fr.H = (int)H; fr.color = s->color; fr.depth = s->depth;
    fr.invFar = s->farZ > 0 ? (float)(1.0 / s->farZ) : 0.0f;
    for (int k = 0; k < 3; k++) {
        fr.amb[k] = (float)s->ambient[k];
        fr.eye[k] = (float)s->eye[k];
        fr.fogC[k] = (float)s->fogColor[k];
    }
    fr.fogOn = s->fogOn; fr.fogN = (float)s->fogNear; fr.fogF = (float)s->fogFar;
    for (int i = 0; i < s->lightCount; i++) {
        Light *L = lights_get(s->lights[i]);
        if (!L || !L->enabled || L->intensity <= 0) continue;
        LightW *lw = &fr.L[fr.nL++];
        lw->kind = L->kind;
        for (int k = 0; k < 3; k++) { lw->v[k] = (float)L->v[k]; lw->c[k] = (float)(L->color[k] * L->intensity); }
        lw->range = (float)L->range;
    }

    /* cleared, drawn and brought down to w x h (averaging ss x ss samples,
     * into imageData's layout) band by band, by the threads that draw */
    fr.bg = pack_rgb((float)s->bg[0], (float)s->bg[1], (float)s->bg[2]);
    fr.cleared = 0;
    fr.out = s->frame; fr.outW = w; fr.outH = h; fr.ss = ss;

    CamFrame cam;
    cam_frame(s, &cam);
    double aspect = (double)w / (double)h;
    for (int i = 0; i < s->nodeCount; i++) {
        Node *nd = nodes_get(s->nodes[i]);
        if (nd && nd->visible) draw_node(&fr, s, &cam, nd, aspect);
    }
    flush_queue(&fr, 1);
    s->frameLen = (int)outBytes;
    s->statTris = (int)fr.tris;
    s->statPixels = fr.pixels;
    s->statMs = now_ms() - t0;
    return (int)outBytes;
}

/* The last picture r3x_scene_render made for this scene (valid until the
 * next render of the scene or its destruction), or NULL. */
LC_API const unsigned char *r3x_scene_frame(int scene)
{
    Scene *s = scenes_get(scene);
    return (s && s->frameLen > 0) ? s->frame : NULL;
}
LC_API int r3x_scene_frame_length(int scene)
{
    Scene *s = scenes_get(scene);
    return s ? s->frameLen : 0;
}

/* "triangles,pixels,milliseconds" of the last render: triangles that reached
 * the rasterizer, pixels written, time taken. */
LC_API const char *r3x_scene_stats(int scene)
{
    Scene *s = scenes_get(scene);
    if (!s) return text_empty();
    double d[3] = { s->statTris, s->statPixels, floor(s->statMs * 1000.0 + 0.5) / 1000.0 };
    return text_of(d, 3);
}

/* ================================================================== */
/* Picking                                                             */
/* ================================================================== */
static double s_hit[5];   /* x, y, z, distance, triangle (1-based) */
static int s_hitNode = 0;

/* The nearest visible node a ray meets, both faces counted. */
static int ray_cast(Scene *s, const double o[3], const double d[3])
{
    s_hitNode = 0;
    double best = 1e300;
    int bestTri = 0;
    for (int i = 0; i < s->nodeCount; i++) {
        Node *nd = nodes_get(s->nodes[i]);
        if (!nd || !nd->visible) continue;
        Mesh *m = meshes_get(nd->mesh);
        if (!m || m->nt == 0) continue;
        double R[9];
        quat_matrix(nd->rot, R);
        /* into the mesh's frame: S^-1 R^T (p - T); the ray parameter is kept */
        double po[3] = { o[0] - nd->pos[0], o[1] - nd->pos[1], o[2] - nd->pos[2] };
        double lo[3], ld[3];
        for (int k = 0; k < 3; k++) {
            lo[k] = (R[k] * po[0] + R[3 + k] * po[1] + R[6 + k] * po[2]) / nd->scale[k];
            ld[k] = (R[k] * d[0] + R[3 + k] * d[1] + R[6 + k] * d[2]) / nd->scale[k];
        }
        /* the bounds first (slab test) */
        mesh_bounds(m);
        double tmin = 0, tmax = best;
        int miss = 0;
        for (int k = 0; k < 3 && !miss; k++) {
            if (fabs(ld[k]) < 1e-300) {
                if (lo[k] < m->bmin[k] || lo[k] > m->bmax[k]) miss = 1;
            } else {
                double t1 = (m->bmin[k] - lo[k]) / ld[k], t2 = (m->bmax[k] - lo[k]) / ld[k];
                if (t1 > t2) { double t = t1; t1 = t2; t2 = t; }
                if (t1 > tmin) tmin = t1;
                if (t2 < tmax) tmax = t2;
                if (tmin > tmax) miss = 1;
            }
        }
        if (miss) continue;
        for (int t = 0; t < m->nt; t++) {
            const float *A = m->pos + m->tri[t * 3] * 3, *B = m->pos + m->tri[t * 3 + 1] * 3,
                        *C = m->pos + m->tri[t * 3 + 2] * 3;
            double e1[3] = { B[0] - A[0], B[1] - A[1], B[2] - A[2] };
            double e2[3] = { C[0] - A[0], C[1] - A[1], C[2] - A[2] };
            double pv[3] = { ld[1] * e2[2] - ld[2] * e2[1], ld[2] * e2[0] - ld[0] * e2[2],
                             ld[0] * e2[1] - ld[1] * e2[0] };
            double det = e1[0] * pv[0] + e1[1] * pv[1] + e1[2] * pv[2];
            if (fabs(det) < 1e-18) continue;
            double id = 1.0 / det;
            double tv[3] = { lo[0] - A[0], lo[1] - A[1], lo[2] - A[2] };
            double u = (tv[0] * pv[0] + tv[1] * pv[1] + tv[2] * pv[2]) * id;
            if (u < 0 || u > 1) continue;
            double qv[3] = { tv[1] * e1[2] - tv[2] * e1[1], tv[2] * e1[0] - tv[0] * e1[2],
                             tv[0] * e1[1] - tv[1] * e1[0] };
            double v = (ld[0] * qv[0] + ld[1] * qv[1] + ld[2] * qv[2]) * id;
            if (v < 0 || u + v > 1) continue;
            double tt = (e2[0] * qv[0] + e2[1] * qv[1] + e2[2] * qv[2]) * id;
            if (tt > 1e-9 && tt < best) { best = tt; s_hitNode = s->nodes[i]; bestTri = t + 1; }
        }
    }
    if (s_hitNode) {
        for (int k = 0; k < 3; k++) s_hit[k] = o[k] + d[k] * best;
        s_hit[3] = best; s_hit[4] = bestTri;
    }
    return s_hitNode;
}

/* The node under picture point (px, py) of a w x h picture, or 0. */
LC_API int r3x_scene_pick(int scene, int w, int h, double px, double py)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    s_hitNode = 0;
    if (!s) return fail(k_bad_handle);
    if (!view_ok(w, h)) return 0;
    if (!fin(px) || !fin(py)) return fail(k_bad_number);
    double o[3], d[3];
    scene_ray(s, w, h, px, py, o, d);
    return ray_cast(s, o, d);
}

/* The nearest node a world ray meets, or 0. The direction need not be unit
 * length; distances are measured along the unit direction. */
LC_API int r3x_scene_ray_cast(int scene, double ox, double oy, double oz,
                              double dx, double dy, double dz)
{
    ok_clear();
    Scene *s = scenes_get(scene);
    s_hitNode = 0;
    if (!s) return fail(k_bad_handle);
    double o[3] = { ox, oy, oz }, d[3];
    if (!fin3(ox, oy, oz) || !dir_in(dx, dy, dz, d)) return fail(k_bad_number);
    return ray_cast(s, o, d);
}

/* Where the last pick or ray cast hit: "x,y,z,distance,triangle", or empty
 * if it hit nothing. */
LC_API const char *r3x_hit_text(void)
{
    if (!s_hitNode) return text_empty();
    return text_of(s_hit, 5);
}
