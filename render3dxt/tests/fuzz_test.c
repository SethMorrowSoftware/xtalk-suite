/*
 * fuzz_test.c - render3dxt's random-call test. EVERY export of the shim is in
 * the generated call table below (tools/check-smoke-coverage.py --write), and
 * this test calls them in a random order with arguments drawn to hurt: live
 * handles, stale ones, 0, negative numbers, NaN, infinities, huge values,
 * and text that is half a number list and half garbage, including random
 * OBJ text for fast_obj and random bytes for stb_image. Every few hundred
 * calls a live scene is rendered at a random size.
 *
 * It holds that no sequence of calls crashes, trips ASan/UBSan, or leaks
 * (the live counts return to where they started once everything made is
 * destroyed), and that every render of a valid scene returns exactly
 * w * h * 4 bytes. Usage: render3dxt_fuzz [seed [calls]]; with no seed it
 * runs seeds 1 to 3.
 */
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "test_assets.h"

/* >>> BEGIN SHIM DECLARATIONS (generated: tools/check-smoke-coverage.py --write) >>> */
extern int r3x_abi_version(void);
extern const char *r3x_library_version(void);
extern const char *r3x_last_error(void);
extern int r3x_text_length(const void *text);
extern const char *r3x_live_counts(void);
extern int r3x_texture_load(const char *path);
extern int r3x_texture_decode(const unsigned char *bytes, int length);
extern int r3x_texture_from_image_data(const unsigned char *bytes, int length, int width, int height);
extern int r3x_texture_checker(int size, int cells, double r1, double g1, double b1, double r2, double g2, double b2);
extern void r3x_texture_destroy(int texture);
extern int r3x_texture_is_valid(int texture);
extern int r3x_texture_width(int texture);
extern int r3x_texture_height(int texture);
extern void r3x_texture_set_smooth(int texture, int flag);
extern int r3x_texture_is_smooth(int texture);
extern void r3x_texture_set_repeat(int texture, int flag);
extern int r3x_texture_is_repeat(int texture);
extern int r3x_material_create(double r, double g, double b);
extern void r3x_material_destroy(int material);
extern int r3x_material_is_valid(int material);
extern void r3x_material_set_color(int material, double r, double g, double b);
extern const char *r3x_material_color(int material);
extern void r3x_material_set_texture(int material, int texture);
extern int r3x_material_texture(int material);
extern void r3x_material_set_specular(int material, double strength, double shininess);
extern const char *r3x_material_specular(int material);
extern void r3x_material_set_emissive(int material, double r, double g, double b);
extern void r3x_material_set_unlit(int material, int flag);
extern int r3x_material_is_unlit(int material);
extern void r3x_material_set_double_sided(int material, int flag);
extern int r3x_material_is_double_sided(int material);
extern void r3x_material_set_flat(int material, int flag);
extern int r3x_material_is_flat(int material);
extern void r3x_material_set_cutout(int material, int flag);
extern int r3x_material_is_cutout(int material);
extern void r3x_mesh_destroy(int mesh);
extern int r3x_mesh_is_valid(int mesh);
extern int r3x_mesh_vertex_count(int mesh);
extern int r3x_mesh_triangle_count(int mesh);
extern const char *r3x_mesh_bounds(int mesh);
extern int r3x_mesh_create(void);
extern int r3x_mesh_add_vertex(int mesh, double x, double y, double z, double nx, double ny, double nz, double u, double v);
extern int r3x_mesh_add_triangle(int mesh, int a, int b, int c, int slot);
extern void r3x_mesh_compute_normals(int mesh);
extern int r3x_mesh_slot_count(int mesh);
extern int r3x_mesh_slot_material(int mesh, int slot);
extern void r3x_mesh_set_slot_material(int mesh, int slot, int material);
extern const char *r3x_mesh_slot_name(int mesh, int slot);
extern const char *r3x_mesh_slot_texture_name(int mesh, int slot);
extern int r3x_mesh_box(double hx, double hy, double hz);
extern int r3x_mesh_plane(double hx, double hz, double uRepeat, double vRepeat);
extern int r3x_mesh_sphere(double radius, int slices, int stacks);
extern int r3x_mesh_cylinder(double radius, double halfHeight, int slices);
extern int r3x_mesh_capsule(double radius, double halfHeight, int slices, int stacks);
extern int r3x_mesh_from_triangles_text(const char *text);
extern int r3x_mesh_load_obj(const char *path);
extern int r3x_mesh_parse_obj(const char *objText, const char *mtlText);
extern int r3x_scene_create(void);
extern void r3x_scene_destroy(int scene);
extern int r3x_scene_is_valid(int scene);
extern void r3x_scene_set_background(int scene, double r, double g, double b);
extern const char *r3x_scene_background(int scene);
extern void r3x_scene_set_ambient(int scene, double r, double g, double b);
extern const char *r3x_scene_ambient(int scene);
extern void r3x_scene_set_fog(int scene, double r, double g, double b, double fogNear, double fogFar);
extern void r3x_scene_set_supersample(int scene, int n);
extern int r3x_scene_supersample(int scene);
extern void r3x_scene_set_camera(int scene, double ex, double ey, double ez, double tx, double ty, double tz, double fov);
extern void r3x_scene_set_camera_text(int scene, const char *text);
extern const char *r3x_scene_camera(int scene);
extern void r3x_scene_set_clip(int scene, double nearZ, double farZ);
extern const char *r3x_scene_clip(int scene);
extern const char *r3x_scene_project(int scene, int w, int h, double x, double y, double z);
extern const char *r3x_scene_ray(int scene, int w, int h, double px, double py);
extern int r3x_light_create_directional(int scene, double dx, double dy, double dz, double r, double g, double b, double intensity);
extern int r3x_light_create_point(int scene, double x, double y, double z, double r, double g, double b, double intensity, double range);
extern void r3x_light_destroy(int light);
extern int r3x_light_is_valid(int light);
extern int r3x_scene_light_count(int scene);
extern int r3x_scene_light(int scene, int index);
extern void r3x_light_set_color(int light, double r, double g, double b, double intensity);
extern const char *r3x_light_color(int light);
extern void r3x_light_set_direction(int light, double dx, double dy, double dz);
extern void r3x_light_set_position(int light, double x, double y, double z);
extern const char *r3x_light_vector(int light);
extern int r3x_light_kind(int light);
extern void r3x_light_set_enabled(int light, int flag);
extern int r3x_light_is_enabled(int light);
extern int r3x_node_create(int scene, int mesh);
extern void r3x_node_destroy(int node);
extern int r3x_node_is_valid(int node);
extern int r3x_node_scene(int node);
extern int r3x_scene_node_count(int scene);
extern int r3x_scene_node(int scene, int index);
extern void r3x_node_set_mesh(int node, int mesh);
extern int r3x_node_mesh(int node);
extern void r3x_node_set_material(int node, int material);
extern int r3x_node_material(int node);
extern void r3x_node_set_position(int node, double x, double y, double z);
extern void r3x_node_set_rotation(int node, double qx, double qy, double qz, double qw);
extern void r3x_node_set_transform(int node, double x, double y, double z, double qx, double qy, double qz, double qw);
extern void r3x_node_set_transform_text(int node, const char *text);
extern void r3x_node_set_scale(int node, double sx, double sy, double sz);
extern const char *r3x_node_position(int node);
extern const char *r3x_node_rotation(int node);
extern const char *r3x_node_scale(int node);
extern const char *r3x_node_transform(int node);
extern void r3x_node_set_visible(int node, int flag);
extern int r3x_node_is_visible(int node);
extern void r3x_node_set_tag(int node, int tag);
extern int r3x_node_tag(int node);
extern int r3x_scene_node_by_tag(int scene, int tag);
extern int r3x_scene_apply_moves(int scene, const char *text);
extern void r3x_set_thread_count(int n);
extern int r3x_thread_count(void);
extern int r3x_scene_render(int scene, int w, int h);
extern int r3x_scene_render_begin(int scene, int w, int h);
extern int r3x_scene_is_render_ready(int scene);
extern const unsigned char *r3x_scene_frame(int scene);
extern int r3x_scene_frame_length(int scene);
extern const char *r3x_scene_stats(int scene);
extern int r3x_scene_pick(int scene, int w, int h, double px, double py);
extern int r3x_scene_ray_cast(int scene, double ox, double oy, double oz, double dx, double dy, double dz);
extern const char *r3x_hit_text(void);
/* <<< END SHIM DECLARATIONS <<< */

static uint64_t g_rng;
static uint32_t rnd(void)
{
    g_rng ^= g_rng << 13; g_rng ^= g_rng >> 7; g_rng ^= g_rng << 17;
    return (uint32_t)(g_rng >> 16);
}
static int pick(int n) { return n > 0 ? (int)(rnd() % (uint32_t)n) : 0; }

/* the handles made so far (live or dead): the fuzz picks from these */
#define POOL 512
static int g_handles[POOL];
static int g_nh = 0;
static void remember(int h) { if (h > 0) g_handles[g_nh++ % POOL] = h; }

static int fz_int(void)
{
    switch (pick(10)) {
    case 0: return 0;
    case 1: return -1 - pick(5);
    case 2: return pick(4) + 1;
    case 3: return pick(64) + 1;
    case 4: return (int)rnd();
    case 5: return 0x7FFFFFFF;
    default: return g_nh ? g_handles[pick(g_nh < POOL ? g_nh : POOL)] : pick(3);
    }
}

static double fz_num(void)
{
    switch (pick(16)) {
    case 0: return 0;
    case 1: return NAN;
    case 2: return INFINITY;
    case 3: return -INFINITY;
    case 4: return 1e300;
    case 5: return -1e-300;
    case 6: return (double)pick(256);
    case 7: return 1e7;
    case 8: return -(double)pick(1000) / 10.0;
    default: return ((double)pick(20001) - 10000.0) / 1000.0;
    }
}

static char g_text[8192];
static const char *fz_text(void)
{
    int n = 0;
    switch (pick(6)) {
    case 0: return NULL;
    case 1: return "";
    case 2: { /* number lists, some lines short or long */
        int lines = pick(6) + 1;
        for (int l = 0; l < lines && n < 7000; l++) {
            int items = pick(11);
            for (int i = 0; i < items && n < 7000; i++)
                n += snprintf(g_text + n, sizeof g_text - (size_t)n, "%s%g", i ? "," : "",
                              pick(5) ? (double)pick(2000) / 100.0 - 10.0 : fz_num());
            g_text[n++] = pick(3) ? '\n' : '\r';
        }
        break;
    }
    case 3: { /* OBJ-ish */
        static const char *words[] = { "v ", "vt ", "vn ", "f ", "o ", "g ", "usemtl ", "mtllib ", "s ", "#",
                                       "newmtl ", "Kd ", "map_Kd ", "Ns ", "/", "-", " ", "1", "2", "3", "0.5",
                                       "\n", "\n", "-1", "99999", "nan", "1e40" };
        int k = pick(300);
        for (int i = 0; i < k && n < 8000; i++) {
            const char *w = words[pick((int)(sizeof words / sizeof words[0]))];
            size_t l = strlen(w);
            memcpy(g_text + n, w, l);
            n += (int)l;
        }
        break;
    }
    default: { /* bytes */
        int k = pick(200);
        for (int i = 0; i < k; i++) g_text[n++] = (char)(pick(255) + 1);
        break;
    }
    }
    g_text[n] = 0;
    return g_text;
}

static unsigned char g_bytes[4096];
static int g_blen = 0;
static const unsigned char *fz_bytes(void)
{
    static const unsigned char png_head[8] = { 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };
    g_blen = pick(5) == 0 ? 0 : pick((int)sizeof g_bytes);
    for (int i = 0; i < g_blen; i++) g_bytes[i] = (unsigned char)rnd();
    if (g_blen >= 8 && pick(2)) memcpy(g_bytes, png_head, 8);
    return pick(8) == 0 ? NULL : g_bytes;
}
static int fz_bytes_len(void) { return pick(10) == 0 ? -pick(5) : g_blen; }

static volatile uintptr_t g_sink;
static void fz_seen_int(int v) { remember(v); g_sink += (uintptr_t)v; }
static void fz_seen_num(double v) { g_sink += (uintptr_t)(v == v); }
static void fz_seen_ptr(const void *p) { g_sink += (uintptr_t)p; }

/* >>> BEGIN FUZZ CALLS (generated: tools/check-smoke-coverage.py --write) >>> */
static void fz_r3x_abi_version(void) { fz_seen_int(r3x_abi_version()); }
static void fz_r3x_library_version(void) { fz_seen_ptr((const void *)r3x_library_version()); }
static void fz_r3x_last_error(void) { fz_seen_ptr((const void *)r3x_last_error()); }
static void fz_r3x_text_length(void) { fz_seen_int(r3x_text_length((const void *)fz_text())); }
static void fz_r3x_live_counts(void) { fz_seen_ptr((const void *)r3x_live_counts()); }
static void fz_r3x_texture_load(void) { fz_seen_int(r3x_texture_load(fz_text())); }
static void fz_r3x_texture_decode(void) { fz_seen_int(r3x_texture_decode(fz_bytes(), fz_bytes_len())); }
static void fz_r3x_texture_from_image_data(void) { fz_seen_int(r3x_texture_from_image_data(fz_bytes(), fz_bytes_len(), fz_int(), fz_int())); }
static void fz_r3x_texture_checker(void) { fz_seen_int(r3x_texture_checker(fz_int(), fz_int(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num())); }
static void fz_r3x_texture_destroy(void) { r3x_texture_destroy(fz_int()); }
static void fz_r3x_texture_is_valid(void) { fz_seen_int(r3x_texture_is_valid(fz_int())); }
static void fz_r3x_texture_width(void) { fz_seen_int(r3x_texture_width(fz_int())); }
static void fz_r3x_texture_height(void) { fz_seen_int(r3x_texture_height(fz_int())); }
static void fz_r3x_texture_set_smooth(void) { r3x_texture_set_smooth(fz_int(), fz_int()); }
static void fz_r3x_texture_is_smooth(void) { fz_seen_int(r3x_texture_is_smooth(fz_int())); }
static void fz_r3x_texture_set_repeat(void) { r3x_texture_set_repeat(fz_int(), fz_int()); }
static void fz_r3x_texture_is_repeat(void) { fz_seen_int(r3x_texture_is_repeat(fz_int())); }
static void fz_r3x_material_create(void) { fz_seen_int(r3x_material_create(fz_num(), fz_num(), fz_num())); }
static void fz_r3x_material_destroy(void) { r3x_material_destroy(fz_int()); }
static void fz_r3x_material_is_valid(void) { fz_seen_int(r3x_material_is_valid(fz_int())); }
static void fz_r3x_material_set_color(void) { r3x_material_set_color(fz_int(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_material_color(void) { fz_seen_ptr((const void *)r3x_material_color(fz_int())); }
static void fz_r3x_material_set_texture(void) { r3x_material_set_texture(fz_int(), fz_int()); }
static void fz_r3x_material_texture(void) { fz_seen_int(r3x_material_texture(fz_int())); }
static void fz_r3x_material_set_specular(void) { r3x_material_set_specular(fz_int(), fz_num(), fz_num()); }
static void fz_r3x_material_specular(void) { fz_seen_ptr((const void *)r3x_material_specular(fz_int())); }
static void fz_r3x_material_set_emissive(void) { r3x_material_set_emissive(fz_int(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_material_set_unlit(void) { r3x_material_set_unlit(fz_int(), fz_int()); }
static void fz_r3x_material_is_unlit(void) { fz_seen_int(r3x_material_is_unlit(fz_int())); }
static void fz_r3x_material_set_double_sided(void) { r3x_material_set_double_sided(fz_int(), fz_int()); }
static void fz_r3x_material_is_double_sided(void) { fz_seen_int(r3x_material_is_double_sided(fz_int())); }
static void fz_r3x_material_set_flat(void) { r3x_material_set_flat(fz_int(), fz_int()); }
static void fz_r3x_material_is_flat(void) { fz_seen_int(r3x_material_is_flat(fz_int())); }
static void fz_r3x_material_set_cutout(void) { r3x_material_set_cutout(fz_int(), fz_int()); }
static void fz_r3x_material_is_cutout(void) { fz_seen_int(r3x_material_is_cutout(fz_int())); }
static void fz_r3x_mesh_destroy(void) { r3x_mesh_destroy(fz_int()); }
static void fz_r3x_mesh_is_valid(void) { fz_seen_int(r3x_mesh_is_valid(fz_int())); }
static void fz_r3x_mesh_vertex_count(void) { fz_seen_int(r3x_mesh_vertex_count(fz_int())); }
static void fz_r3x_mesh_triangle_count(void) { fz_seen_int(r3x_mesh_triangle_count(fz_int())); }
static void fz_r3x_mesh_bounds(void) { fz_seen_ptr((const void *)r3x_mesh_bounds(fz_int())); }
static void fz_r3x_mesh_create(void) { fz_seen_int(r3x_mesh_create()); }
static void fz_r3x_mesh_add_vertex(void) { fz_seen_int(r3x_mesh_add_vertex(fz_int(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num())); }
static void fz_r3x_mesh_add_triangle(void) { fz_seen_int(r3x_mesh_add_triangle(fz_int(), fz_int(), fz_int(), fz_int(), fz_int())); }
static void fz_r3x_mesh_compute_normals(void) { r3x_mesh_compute_normals(fz_int()); }
static void fz_r3x_mesh_slot_count(void) { fz_seen_int(r3x_mesh_slot_count(fz_int())); }
static void fz_r3x_mesh_slot_material(void) { fz_seen_int(r3x_mesh_slot_material(fz_int(), fz_int())); }
static void fz_r3x_mesh_set_slot_material(void) { r3x_mesh_set_slot_material(fz_int(), fz_int(), fz_int()); }
static void fz_r3x_mesh_slot_name(void) { fz_seen_ptr((const void *)r3x_mesh_slot_name(fz_int(), fz_int())); }
static void fz_r3x_mesh_slot_texture_name(void) { fz_seen_ptr((const void *)r3x_mesh_slot_texture_name(fz_int(), fz_int())); }
static void fz_r3x_mesh_box(void) { fz_seen_int(r3x_mesh_box(fz_num(), fz_num(), fz_num())); }
static void fz_r3x_mesh_plane(void) { fz_seen_int(r3x_mesh_plane(fz_num(), fz_num(), fz_num(), fz_num())); }
static void fz_r3x_mesh_sphere(void) { fz_seen_int(r3x_mesh_sphere(fz_num(), fz_int(), fz_int())); }
static void fz_r3x_mesh_cylinder(void) { fz_seen_int(r3x_mesh_cylinder(fz_num(), fz_num(), fz_int())); }
static void fz_r3x_mesh_capsule(void) { fz_seen_int(r3x_mesh_capsule(fz_num(), fz_num(), fz_int(), fz_int())); }
static void fz_r3x_mesh_from_triangles_text(void) { fz_seen_int(r3x_mesh_from_triangles_text(fz_text())); }
static void fz_r3x_mesh_load_obj(void) { fz_seen_int(r3x_mesh_load_obj(fz_text())); }
static void fz_r3x_mesh_parse_obj(void) { fz_seen_int(r3x_mesh_parse_obj(fz_text(), fz_text())); }
static void fz_r3x_scene_create(void) { fz_seen_int(r3x_scene_create()); }
static void fz_r3x_scene_destroy(void) { r3x_scene_destroy(fz_int()); }
static void fz_r3x_scene_is_valid(void) { fz_seen_int(r3x_scene_is_valid(fz_int())); }
static void fz_r3x_scene_set_background(void) { r3x_scene_set_background(fz_int(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_scene_background(void) { fz_seen_ptr((const void *)r3x_scene_background(fz_int())); }
static void fz_r3x_scene_set_ambient(void) { r3x_scene_set_ambient(fz_int(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_scene_ambient(void) { fz_seen_ptr((const void *)r3x_scene_ambient(fz_int())); }
static void fz_r3x_scene_set_fog(void) { r3x_scene_set_fog(fz_int(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_scene_set_supersample(void) { r3x_scene_set_supersample(fz_int(), fz_int()); }
static void fz_r3x_scene_supersample(void) { fz_seen_int(r3x_scene_supersample(fz_int())); }
static void fz_r3x_scene_set_camera(void) { r3x_scene_set_camera(fz_int(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_scene_set_camera_text(void) { r3x_scene_set_camera_text(fz_int(), fz_text()); }
static void fz_r3x_scene_camera(void) { fz_seen_ptr((const void *)r3x_scene_camera(fz_int())); }
static void fz_r3x_scene_set_clip(void) { r3x_scene_set_clip(fz_int(), fz_num(), fz_num()); }
static void fz_r3x_scene_clip(void) { fz_seen_ptr((const void *)r3x_scene_clip(fz_int())); }
static void fz_r3x_scene_project(void) { fz_seen_ptr((const void *)r3x_scene_project(fz_int(), fz_int(), fz_int(), fz_num(), fz_num(), fz_num())); }
static void fz_r3x_scene_ray(void) { fz_seen_ptr((const void *)r3x_scene_ray(fz_int(), fz_int(), fz_int(), fz_num(), fz_num())); }
static void fz_r3x_light_create_directional(void) { fz_seen_int(r3x_light_create_directional(fz_int(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num())); }
static void fz_r3x_light_create_point(void) { fz_seen_int(r3x_light_create_point(fz_int(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num())); }
static void fz_r3x_light_destroy(void) { r3x_light_destroy(fz_int()); }
static void fz_r3x_light_is_valid(void) { fz_seen_int(r3x_light_is_valid(fz_int())); }
static void fz_r3x_scene_light_count(void) { fz_seen_int(r3x_scene_light_count(fz_int())); }
static void fz_r3x_scene_light(void) { fz_seen_int(r3x_scene_light(fz_int(), fz_int())); }
static void fz_r3x_light_set_color(void) { r3x_light_set_color(fz_int(), fz_num(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_light_color(void) { fz_seen_ptr((const void *)r3x_light_color(fz_int())); }
static void fz_r3x_light_set_direction(void) { r3x_light_set_direction(fz_int(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_light_set_position(void) { r3x_light_set_position(fz_int(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_light_vector(void) { fz_seen_ptr((const void *)r3x_light_vector(fz_int())); }
static void fz_r3x_light_kind(void) { fz_seen_int(r3x_light_kind(fz_int())); }
static void fz_r3x_light_set_enabled(void) { r3x_light_set_enabled(fz_int(), fz_int()); }
static void fz_r3x_light_is_enabled(void) { fz_seen_int(r3x_light_is_enabled(fz_int())); }
static void fz_r3x_node_create(void) { fz_seen_int(r3x_node_create(fz_int(), fz_int())); }
static void fz_r3x_node_destroy(void) { r3x_node_destroy(fz_int()); }
static void fz_r3x_node_is_valid(void) { fz_seen_int(r3x_node_is_valid(fz_int())); }
static void fz_r3x_node_scene(void) { fz_seen_int(r3x_node_scene(fz_int())); }
static void fz_r3x_scene_node_count(void) { fz_seen_int(r3x_scene_node_count(fz_int())); }
static void fz_r3x_scene_node(void) { fz_seen_int(r3x_scene_node(fz_int(), fz_int())); }
static void fz_r3x_node_set_mesh(void) { r3x_node_set_mesh(fz_int(), fz_int()); }
static void fz_r3x_node_mesh(void) { fz_seen_int(r3x_node_mesh(fz_int())); }
static void fz_r3x_node_set_material(void) { r3x_node_set_material(fz_int(), fz_int()); }
static void fz_r3x_node_material(void) { fz_seen_int(r3x_node_material(fz_int())); }
static void fz_r3x_node_set_position(void) { r3x_node_set_position(fz_int(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_node_set_rotation(void) { r3x_node_set_rotation(fz_int(), fz_num(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_node_set_transform(void) { r3x_node_set_transform(fz_int(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_node_set_transform_text(void) { r3x_node_set_transform_text(fz_int(), fz_text()); }
static void fz_r3x_node_set_scale(void) { r3x_node_set_scale(fz_int(), fz_num(), fz_num(), fz_num()); }
static void fz_r3x_node_position(void) { fz_seen_ptr((const void *)r3x_node_position(fz_int())); }
static void fz_r3x_node_rotation(void) { fz_seen_ptr((const void *)r3x_node_rotation(fz_int())); }
static void fz_r3x_node_scale(void) { fz_seen_ptr((const void *)r3x_node_scale(fz_int())); }
static void fz_r3x_node_transform(void) { fz_seen_ptr((const void *)r3x_node_transform(fz_int())); }
static void fz_r3x_node_set_visible(void) { r3x_node_set_visible(fz_int(), fz_int()); }
static void fz_r3x_node_is_visible(void) { fz_seen_int(r3x_node_is_visible(fz_int())); }
static void fz_r3x_node_set_tag(void) { r3x_node_set_tag(fz_int(), fz_int()); }
static void fz_r3x_node_tag(void) { fz_seen_int(r3x_node_tag(fz_int())); }
static void fz_r3x_scene_node_by_tag(void) { fz_seen_int(r3x_scene_node_by_tag(fz_int(), fz_int())); }
static void fz_r3x_scene_apply_moves(void) { fz_seen_int(r3x_scene_apply_moves(fz_int(), fz_text())); }
static void fz_r3x_set_thread_count(void) { r3x_set_thread_count(fz_int()); }
static void fz_r3x_thread_count(void) { fz_seen_int(r3x_thread_count()); }
static void fz_r3x_scene_render(void) { fz_seen_int(r3x_scene_render(fz_int(), fz_int(), fz_int())); }
static void fz_r3x_scene_render_begin(void) { fz_seen_int(r3x_scene_render_begin(fz_int(), fz_int(), fz_int())); }
static void fz_r3x_scene_is_render_ready(void) { fz_seen_int(r3x_scene_is_render_ready(fz_int())); }
static void fz_r3x_scene_frame(void) { fz_seen_ptr((const void *)r3x_scene_frame(fz_int())); }
static void fz_r3x_scene_frame_length(void) { fz_seen_int(r3x_scene_frame_length(fz_int())); }
static void fz_r3x_scene_stats(void) { fz_seen_ptr((const void *)r3x_scene_stats(fz_int())); }
static void fz_r3x_scene_pick(void) { fz_seen_int(r3x_scene_pick(fz_int(), fz_int(), fz_int(), fz_num(), fz_num())); }
static void fz_r3x_scene_ray_cast(void) { fz_seen_int(r3x_scene_ray_cast(fz_int(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num(), fz_num())); }
static void fz_r3x_hit_text(void) { fz_seen_ptr((const void *)r3x_hit_text()); }
static void (*const k_fuzz_calls[])(void) = {
    fz_r3x_abi_version,
    fz_r3x_library_version,
    fz_r3x_last_error,
    fz_r3x_text_length,
    fz_r3x_live_counts,
    fz_r3x_texture_load,
    fz_r3x_texture_decode,
    fz_r3x_texture_from_image_data,
    fz_r3x_texture_checker,
    fz_r3x_texture_destroy,
    fz_r3x_texture_is_valid,
    fz_r3x_texture_width,
    fz_r3x_texture_height,
    fz_r3x_texture_set_smooth,
    fz_r3x_texture_is_smooth,
    fz_r3x_texture_set_repeat,
    fz_r3x_texture_is_repeat,
    fz_r3x_material_create,
    fz_r3x_material_destroy,
    fz_r3x_material_is_valid,
    fz_r3x_material_set_color,
    fz_r3x_material_color,
    fz_r3x_material_set_texture,
    fz_r3x_material_texture,
    fz_r3x_material_set_specular,
    fz_r3x_material_specular,
    fz_r3x_material_set_emissive,
    fz_r3x_material_set_unlit,
    fz_r3x_material_is_unlit,
    fz_r3x_material_set_double_sided,
    fz_r3x_material_is_double_sided,
    fz_r3x_material_set_flat,
    fz_r3x_material_is_flat,
    fz_r3x_material_set_cutout,
    fz_r3x_material_is_cutout,
    fz_r3x_mesh_destroy,
    fz_r3x_mesh_is_valid,
    fz_r3x_mesh_vertex_count,
    fz_r3x_mesh_triangle_count,
    fz_r3x_mesh_bounds,
    fz_r3x_mesh_create,
    fz_r3x_mesh_add_vertex,
    fz_r3x_mesh_add_triangle,
    fz_r3x_mesh_compute_normals,
    fz_r3x_mesh_slot_count,
    fz_r3x_mesh_slot_material,
    fz_r3x_mesh_set_slot_material,
    fz_r3x_mesh_slot_name,
    fz_r3x_mesh_slot_texture_name,
    fz_r3x_mesh_box,
    fz_r3x_mesh_plane,
    fz_r3x_mesh_sphere,
    fz_r3x_mesh_cylinder,
    fz_r3x_mesh_capsule,
    fz_r3x_mesh_from_triangles_text,
    fz_r3x_mesh_load_obj,
    fz_r3x_mesh_parse_obj,
    fz_r3x_scene_create,
    fz_r3x_scene_destroy,
    fz_r3x_scene_is_valid,
    fz_r3x_scene_set_background,
    fz_r3x_scene_background,
    fz_r3x_scene_set_ambient,
    fz_r3x_scene_ambient,
    fz_r3x_scene_set_fog,
    fz_r3x_scene_set_supersample,
    fz_r3x_scene_supersample,
    fz_r3x_scene_set_camera,
    fz_r3x_scene_set_camera_text,
    fz_r3x_scene_camera,
    fz_r3x_scene_set_clip,
    fz_r3x_scene_clip,
    fz_r3x_scene_project,
    fz_r3x_scene_ray,
    fz_r3x_light_create_directional,
    fz_r3x_light_create_point,
    fz_r3x_light_destroy,
    fz_r3x_light_is_valid,
    fz_r3x_scene_light_count,
    fz_r3x_scene_light,
    fz_r3x_light_set_color,
    fz_r3x_light_color,
    fz_r3x_light_set_direction,
    fz_r3x_light_set_position,
    fz_r3x_light_vector,
    fz_r3x_light_kind,
    fz_r3x_light_set_enabled,
    fz_r3x_light_is_enabled,
    fz_r3x_node_create,
    fz_r3x_node_destroy,
    fz_r3x_node_is_valid,
    fz_r3x_node_scene,
    fz_r3x_scene_node_count,
    fz_r3x_scene_node,
    fz_r3x_node_set_mesh,
    fz_r3x_node_mesh,
    fz_r3x_node_set_material,
    fz_r3x_node_material,
    fz_r3x_node_set_position,
    fz_r3x_node_set_rotation,
    fz_r3x_node_set_transform,
    fz_r3x_node_set_transform_text,
    fz_r3x_node_set_scale,
    fz_r3x_node_position,
    fz_r3x_node_rotation,
    fz_r3x_node_scale,
    fz_r3x_node_transform,
    fz_r3x_node_set_visible,
    fz_r3x_node_is_visible,
    fz_r3x_node_set_tag,
    fz_r3x_node_tag,
    fz_r3x_scene_node_by_tag,
    fz_r3x_scene_apply_moves,
    fz_r3x_set_thread_count,
    fz_r3x_thread_count,
    fz_r3x_scene_render,
    fz_r3x_scene_render_begin,
    fz_r3x_scene_is_render_ready,
    fz_r3x_scene_frame,
    fz_r3x_scene_frame_length,
    fz_r3x_scene_stats,
    fz_r3x_scene_pick,
    fz_r3x_scene_ray_cast,
    fz_r3x_hit_text,
};
static const char *const k_fuzz_names[] = {
    "r3x_abi_version",
    "r3x_library_version",
    "r3x_last_error",
    "r3x_text_length",
    "r3x_live_counts",
    "r3x_texture_load",
    "r3x_texture_decode",
    "r3x_texture_from_image_data",
    "r3x_texture_checker",
    "r3x_texture_destroy",
    "r3x_texture_is_valid",
    "r3x_texture_width",
    "r3x_texture_height",
    "r3x_texture_set_smooth",
    "r3x_texture_is_smooth",
    "r3x_texture_set_repeat",
    "r3x_texture_is_repeat",
    "r3x_material_create",
    "r3x_material_destroy",
    "r3x_material_is_valid",
    "r3x_material_set_color",
    "r3x_material_color",
    "r3x_material_set_texture",
    "r3x_material_texture",
    "r3x_material_set_specular",
    "r3x_material_specular",
    "r3x_material_set_emissive",
    "r3x_material_set_unlit",
    "r3x_material_is_unlit",
    "r3x_material_set_double_sided",
    "r3x_material_is_double_sided",
    "r3x_material_set_flat",
    "r3x_material_is_flat",
    "r3x_material_set_cutout",
    "r3x_material_is_cutout",
    "r3x_mesh_destroy",
    "r3x_mesh_is_valid",
    "r3x_mesh_vertex_count",
    "r3x_mesh_triangle_count",
    "r3x_mesh_bounds",
    "r3x_mesh_create",
    "r3x_mesh_add_vertex",
    "r3x_mesh_add_triangle",
    "r3x_mesh_compute_normals",
    "r3x_mesh_slot_count",
    "r3x_mesh_slot_material",
    "r3x_mesh_set_slot_material",
    "r3x_mesh_slot_name",
    "r3x_mesh_slot_texture_name",
    "r3x_mesh_box",
    "r3x_mesh_plane",
    "r3x_mesh_sphere",
    "r3x_mesh_cylinder",
    "r3x_mesh_capsule",
    "r3x_mesh_from_triangles_text",
    "r3x_mesh_load_obj",
    "r3x_mesh_parse_obj",
    "r3x_scene_create",
    "r3x_scene_destroy",
    "r3x_scene_is_valid",
    "r3x_scene_set_background",
    "r3x_scene_background",
    "r3x_scene_set_ambient",
    "r3x_scene_ambient",
    "r3x_scene_set_fog",
    "r3x_scene_set_supersample",
    "r3x_scene_supersample",
    "r3x_scene_set_camera",
    "r3x_scene_set_camera_text",
    "r3x_scene_camera",
    "r3x_scene_set_clip",
    "r3x_scene_clip",
    "r3x_scene_project",
    "r3x_scene_ray",
    "r3x_light_create_directional",
    "r3x_light_create_point",
    "r3x_light_destroy",
    "r3x_light_is_valid",
    "r3x_scene_light_count",
    "r3x_scene_light",
    "r3x_light_set_color",
    "r3x_light_color",
    "r3x_light_set_direction",
    "r3x_light_set_position",
    "r3x_light_vector",
    "r3x_light_kind",
    "r3x_light_set_enabled",
    "r3x_light_is_enabled",
    "r3x_node_create",
    "r3x_node_destroy",
    "r3x_node_is_valid",
    "r3x_node_scene",
    "r3x_scene_node_count",
    "r3x_scene_node",
    "r3x_node_set_mesh",
    "r3x_node_mesh",
    "r3x_node_set_material",
    "r3x_node_material",
    "r3x_node_set_position",
    "r3x_node_set_rotation",
    "r3x_node_set_transform",
    "r3x_node_set_transform_text",
    "r3x_node_set_scale",
    "r3x_node_position",
    "r3x_node_rotation",
    "r3x_node_scale",
    "r3x_node_transform",
    "r3x_node_set_visible",
    "r3x_node_is_visible",
    "r3x_node_set_tag",
    "r3x_node_tag",
    "r3x_scene_node_by_tag",
    "r3x_scene_apply_moves",
    "r3x_set_thread_count",
    "r3x_thread_count",
    "r3x_scene_render",
    "r3x_scene_render_begin",
    "r3x_scene_is_render_ready",
    "r3x_scene_frame",
    "r3x_scene_frame_length",
    "r3x_scene_stats",
    "r3x_scene_pick",
    "r3x_scene_ray_cast",
    "r3x_hit_text",
};
/* <<< END FUZZ CALLS <<< */

#define NCALLS ((int)(sizeof k_fuzz_calls / sizeof k_fuzz_calls[0]))

/* A small world to render: some valid objects, so calls have real targets. */
static void seed_world(void)
{
    int s = r3x_scene_create();
    remember(s);
    remember(r3x_mesh_box(0.5, 0.5, 0.5));
    remember(r3x_mesh_sphere(0.7, 12, 6));
    remember(r3x_mesh_load_obj(asset("cube.obj")));
    int t = r3x_texture_checker(16, 4, 255, 0, 0, 0, 0, 255);
    remember(t);
    int m = r3x_material_create(200, 200, 200);
    r3x_material_set_texture(m, t);
    remember(m);
    for (int i = 0; i < 6; i++) {
        int n = r3x_node_create(s, g_handles[1 + i % 3]);
        r3x_node_set_material(n, i % 2 ? m : 0);
        r3x_node_set_position(n, i - 3, 0, 0);
        r3x_node_set_tag(n, i + 1);
        remember(n);
    }
    remember(r3x_light_create_point(s, 0, 3, 3, 255, 255, 255, 1, 20));
}

static int run(uint64_t seed, int calls)
{
    g_rng = seed * 0x9E3779B97F4A7C15ull + 1;
    g_nh = 0;
    char base[128];
    snprintf(base, sizeof base, "%s", r3x_live_counts());
    seed_world();
    int bad = 0;
    for (int i = 0; i < calls; i++) {
        int c = pick(NCALLS);
        /* threads are global: keep the count small so a run stays quick */
        if (strcmp(k_fuzz_names[c], "r3x_set_thread_count") == 0) { r3x_set_thread_count(1 + pick(4)); continue; }
        k_fuzz_calls[c]();
        if (i % 300 == 0) {
            /* render every live scene at a random size and check the length */
            for (int k = 0; k < (g_nh < POOL ? g_nh : POOL); k++) {
                int h = g_handles[k];
                if (!r3x_scene_is_valid(h)) continue;
                int w = 1 + pick(96), hh = 1 + pick(64);
                int n = r3x_scene_render(h, w, hh);
                if (n != 0 && n != w * hh * 4) { printf("FAIL render returned %d for %dx%d\n", n, w, hh); bad++; }
                if (n == 0 && r3x_scene_supersample(h) * w <= 4096) {
                    printf("FAIL a valid scene refused %dx%d: %s\n", w, hh, r3x_last_error());
                    bad++;
                }
            }
        }
    }
    /* destroy everything that can be, then nothing may be left */
    for (int k = 0; k < (g_nh < POOL ? g_nh : POOL); k++) {
        int h = g_handles[k];
        r3x_scene_destroy(h);
        r3x_mesh_destroy(h);
        r3x_material_destroy(h);
        r3x_texture_destroy(h);
    }
    /* handles the pool overwrote: sweep the low slots of every table */
    for (int gen = 0; gen < 64; gen++)
        for (int slot = 1; slot <= 4096; slot++) {
            int h = (gen << 20) | slot;
            if (r3x_scene_is_valid(h)) r3x_scene_destroy(h);
            if (r3x_mesh_is_valid(h)) r3x_mesh_destroy(h);
            if (r3x_material_is_valid(h)) r3x_material_destroy(h);
            if (r3x_texture_is_valid(h)) r3x_texture_destroy(h);
        }
    if (strcmp(r3x_live_counts(), base) != 0) {
        printf("FAIL seed %llu: live counts %s, started at %s\n", (unsigned long long)seed, r3x_live_counts(), base);
        bad++;
    }
    printf("fuzz seed %llu: %d calls over %d exports, %s\n", (unsigned long long)seed, calls, NCALLS,
           bad ? "FAILED" : "clean");
    return bad;
}

int main(int argc, char **argv)
{
    int calls = argc > 2 ? atoi(argv[2]) : 20000;
    int bad = 0;
    if (!assets_write()) {
        printf("fuzz: FAILED - no folder to put the test's model and picture files in\n");
        return 1;
    }
    if (argc > 1) bad = run((uint64_t)strtoull(argv[1], NULL, 10), calls);
    else for (uint64_t s = 1; s <= 3; s++) bad += run(s, calls);
    assets_remove();
    return bad ? 1 : 0;
}
