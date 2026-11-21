/*
 * smoke_test.c - render3dxt's native test: every export of the shim is
 * CALLED here (tools/check-smoke-coverage.py holds that), and what is drawn
 * is checked by reading pixels back, not by trusting a return value.
 *
 * It runs from anywhere: the model and picture files of tests/assets/ travel
 * inside it (tests/test_assets.h, generated) and are put on disk in a scratch
 * folder for the run. Exit status 0 is a pass; the last line says how many checks
 * ran. Under -DRENDER3DXT_SANITIZE=address every check also runs under
 * ASan/UBSan, and under =thread the parallel drawing runs under TSan.
 */
#include <math.h>
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

static int g_checks = 0, g_failed = 0;

#define CHECK(cond, ...) do { g_checks++; if (!(cond)) { g_failed++; \
    printf("FAIL %s:%d: ", __FILE__, __LINE__); printf(__VA_ARGS__); printf("\n"); } } while (0)

static char g_copy[1024];
static const char *cp(const char *s) { snprintf(g_copy, sizeof g_copy, "%s", s ? s : "(null)"); return g_copy; }

/* item n (from 1) of a comma list, as a number */
static double item(const char *s, int n)
{
    const char *p = s;
    for (int i = 1; i < n && p; i++) { p = strchr(p, ','); if (p) p++; }
    return p ? atof(p) : NAN;
}

static int near(double a, double b, double tol) { return fabs(a - b) <= tol; }

typedef struct RGB { int r, g, b; } RGB;
static RGB px(int scene, int w, int x, int y)
{
    const unsigned char *f = r3x_scene_frame(scene);
    RGB c = { -1, -1, -1 };
    if (!f) return c;
    const unsigned char *p = f + ((size_t)y * w + x) * 4;
    c.r = p[1]; c.g = p[2]; c.b = p[3];
    return c;
}
static int is_rgb(RGB c, int r, int g, int b, int tol)
{
    return abs(c.r - r) <= tol && abs(c.g - g) <= tol && abs(c.b - b) <= tol;
}

static unsigned char *read_file(const char *path, int *len)
{
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    unsigned char *b = (unsigned char *)malloc((size_t)n + 1);
    if (b && fread(b, 1, (size_t)n, f) != (size_t)n) { free(b); b = NULL; }
    fclose(f);
    if (b) { b[n] = 0; *len = (int)n; }
    return b;
}

/* A scene with one unlit box of a colour, seen from +z. */
static int unlit_material(int r, int g, int b)
{
    int m = r3x_material_create(r, g, b);
    r3x_material_set_unlit(m, 1);
    return m;
}

static void test_library(void)
{
    CHECK(r3x_abi_version() == 1, "ABI %d", r3x_abi_version());
    const char *v = r3x_library_version();
    CHECK(strstr(v, "render3dxt") && strstr(v, "ABI 1"), "version %s", v);
    CHECK(r3x_text_length(v) == (int)strlen(v), "text length");
    CHECK(r3x_text_length(NULL) == 0, "text length of NULL");
    r3x_scene_destroy(0);
    CHECK(strstr(r3x_last_error(), "not alive") != NULL, "error after a stale destroy: %s", r3x_last_error());
    CHECK(r3x_scene_create() > 0, "a scene");
    CHECK(r3x_last_error()[0] == 0, "error cleared by a good call");
    CHECK(item(r3x_live_counts(), 1) >= 1, "live counts %s", r3x_live_counts());
    r3x_set_thread_count(0);
    CHECK(r3x_last_error()[0] != 0, "0 threads refused");
    r3x_set_thread_count(17);
    CHECK(r3x_last_error()[0] != 0, "17 threads refused");
    r3x_set_thread_count(3);
#if defined(__EMSCRIPTEN__)
    /* the web build has no threads: any accepted number draws on one */
    CHECK(r3x_thread_count() == 1, "threads %d on the web", r3x_thread_count());
#else
    CHECK(r3x_thread_count() == 3, "threads %d", r3x_thread_count());
#endif
}

static void test_scene_defaults(void)
{
    int s = r3x_scene_create();
    CHECK(r3x_scene_is_valid(s), "valid");
    CHECK(strcmp(r3x_scene_background(s), "31,33,41") == 0, "background %s", cp(r3x_scene_background(s)));
    CHECK(strcmp(r3x_scene_ambient(s), "64,64,64") == 0, "ambient %s", cp(r3x_scene_ambient(s)));
    CHECK(strcmp(r3x_scene_camera(s), "0,2,8,0,0,0,50") == 0, "camera %s", cp(r3x_scene_camera(s)));
    CHECK(strcmp(r3x_scene_clip(s), "0.05,0") == 0, "clip %s", cp(r3x_scene_clip(s)));
    CHECK(r3x_scene_supersample(s) == 1, "supersample");
    CHECK(r3x_scene_light_count(s) == 1, "one light to start");
    int L = r3x_scene_light(s, 1);
    CHECK(r3x_light_is_valid(L) && r3x_light_kind(L) == 1, "a directional light");
    CHECK(near(item(r3x_light_vector(L), 2), -0.74 / sqrt(0.37 * 0.37 + 0.74 * 0.74 + 0.56 * 0.56), 1e-6),
          "box3dxt's default light direction %s", cp(r3x_light_vector(L)));
    CHECK(strcmp(r3x_light_color(L), "255,255,255,1") == 0, "light colour %s", cp(r3x_light_color(L)));
    CHECK(r3x_light_is_enabled(L), "enabled");
    CHECK(r3x_scene_light(s, 2) == 0 && r3x_scene_light(s, 0) == 0, "light index out of range");

    /* an empty scene is all background, byte 0 of every pixel 0 */
    int n = r3x_scene_render(s, 8, 6);
    CHECK(n == 8 * 6 * 4 && r3x_scene_frame_length(s) == n, "frame length %d", n);
    const unsigned char *f = r3x_scene_frame(s);
    int allbg = 1;
    for (int i = 0; i < 48; i++)
        if (f[i * 4] != 0 || f[i * 4 + 1] != 31 || f[i * 4 + 2] != 33 || f[i * 4 + 3] != 41) allbg = 0;
    CHECK(allbg, "empty scene is background");
    CHECK(item(r3x_scene_stats(s), 1) == 0, "no triangles %s", cp(r3x_scene_stats(s)));

    r3x_scene_set_background(s, 10, 20, 30);
    CHECK(strcmp(r3x_scene_background(s), "10,20,30") == 0, "background set");
    r3x_scene_set_background(s, 256, 0, 0);
    CHECK(r3x_last_error()[0] && strcmp(r3x_scene_background(s), "10,20,30") == 0, "256 refused");
    r3x_scene_set_ambient(s, 1, 2, 3);
    CHECK(strcmp(r3x_scene_ambient(s), "1,2,3") == 0, "ambient set");
    r3x_scene_set_ambient(s, NAN, 0, 0);
    CHECK(r3x_last_error()[0], "NaN refused");

    CHECK(r3x_scene_render(s, 0, 10) == 0 && r3x_last_error()[0], "width 0 refused");
    CHECK(r3x_scene_render(s, 4097, 10) == 0, "width 4097 refused");
    r3x_scene_set_supersample(s, 4);
    CHECK(r3x_scene_render(s, 4096, 4096) == 0 && strstr(r3x_last_error(), "supersampling"),
          "a 16384^2 buffer refused: %s", r3x_last_error());
    r3x_scene_set_supersample(s, 5);
    CHECK(r3x_last_error()[0] && r3x_scene_supersample(s) == 4, "supersample 5 refused");
    r3x_scene_destroy(s);
    CHECK(!r3x_scene_is_valid(s) && !r3x_light_is_valid(L), "scene and its light gone");
}

static void test_camera_contract(void)
{
    int s = r3x_scene_create();
    r3x_scene_set_camera(s, 0, 0, 5, 0, 0, 0, 60);
    CHECK(strcmp(r3x_scene_camera(s), "0,0,5,0,0,0,60") == 0, "camera %s", cp(r3x_scene_camera(s)));
    /* the target projects to the centre, at its depth */
    const char *p = r3x_scene_project(s, 200, 100, 0, 0, 0);
    CHECK(near(item(p, 1), 100, 1e-6) && near(item(p, 2), 50, 1e-6) && near(item(p, 3), 5, 1e-9), "centre %s", cp(p));
    /* +x to the right, +y up (picture y down) */
    p = r3x_scene_project(s, 200, 100, 1, 1, 0);
    CHECK(item(p, 1) > 100 && item(p, 2) < 50, "right and up %s", cp(p));
    /* a point at the top edge of a 60 degree view, 5 m away */
    double top = 5 * tan(30 * 3.14159265358979323846 / 180);
    p = r3x_scene_project(s, 200, 100, 0, top, 0);
    CHECK(near(item(p, 2), 0, 1e-6), "top edge %s", cp(p));
    /* behind the near plane: empty */
    CHECK(r3x_scene_project(s, 200, 100, 0, 0, 4.99)[0] == 0, "nearer than the near plane");
    CHECK(r3x_scene_project(s, 200, 100, 0, 0, 6)[0] == 0, "behind the eye");
    /* the ray through a projected point comes back to it */
    double P[3] = { 0.7, -0.4, -1.3 };
    p = r3x_scene_project(s, 200, 100, P[0], P[1], P[2]);
    double sx = item(p, 1), sy = item(p, 2);
    const char *r = r3x_scene_ray(s, 200, 100, sx, sy);
    double o[3] = { item(r, 1), item(r, 2), item(r, 3) }, d[3] = { item(r, 4), item(r, 5), item(r, 6) };
    CHECK(near(d[0] * d[0] + d[1] * d[1] + d[2] * d[2], 1, 1e-6), "unit direction %s", cp(r));
    double t = (P[2] - o[2]) / d[2];
    CHECK(near(o[0] + d[0] * t, P[0], 1e-6) && near(o[1] + d[1] * t, P[1], 1e-6), "round trip");
    /* the up fallback: looking straight down, x is right and -z is UP the picture */
    r3x_scene_set_camera(s, 0, 10, 0, 0, 0, 0, 60);
    p = r3x_scene_project(s, 100, 100, 1, 0, 0);
    CHECK(item(p, 1) > 50 && near(item(p, 2), 50, 1e-6), "down: +x right %s", cp(p));
    p = r3x_scene_project(s, 100, 100, 0, 0, -1);
    CHECK(item(p, 2) < 50 && near(item(p, 1), 50, 1e-6), "down: -z up %s", cp(p));
    /* camera as text, b3RenderCamera()'s form */
    r3x_scene_set_camera_text(s, " 1 , 2 ,3,4,5,6.5,45 ");
    CHECK(strcmp(r3x_scene_camera(s), "1,2,3,4,5,6.5,45") == 0, "camera text %s", cp(r3x_scene_camera(s)));
    r3x_scene_set_camera_text(s, "1,2,3,4,5,6");
    CHECK(r3x_last_error()[0] && strcmp(r3x_scene_camera(s), "1,2,3,4,5,6.5,45") == 0, "six items refused");
    r3x_scene_set_camera(s, 1, 1, 1, 1, 1, 1, 50);
    CHECK(strstr(r3x_last_error(), "same point") != NULL, "eye = target refused");
    r3x_scene_set_camera(s, 0, 0, 5, 0, 0, 0, 4);
    CHECK(r3x_last_error()[0], "fov 4 refused");
    r3x_scene_set_camera(s, 0, 0, 5, 0, 0, 0, 151);
    CHECK(r3x_last_error()[0], "fov 151 refused");
    r3x_scene_set_clip(s, 0.5, 100);
    CHECK(strcmp(r3x_scene_clip(s), "0.5,100") == 0, "clip");
    r3x_scene_set_clip(s, 2, 1);
    CHECK(r3x_last_error()[0], "far before near refused");
    CHECK(r3x_scene_ray(s, 0, 10, 1, 1)[0] == 0, "ray in a 0-wide picture refused");
    CHECK(r3x_scene_project(0, 10, 10, 0, 0, 0)[0] == 0, "project on a stale scene");
    r3x_scene_destroy(s);
}

static void test_draw_and_depth(void)
{
    int s = r3x_scene_create();
    r3x_scene_set_camera(s, 0, 0, 5, 0, 0, 0, 50);
    int box = r3x_mesh_box(0.5, 0.5, 0.5);
    CHECK(r3x_mesh_vertex_count(box) == 24 && r3x_mesh_triangle_count(box) == 12, "box %d %d",
          r3x_mesh_vertex_count(box), r3x_mesh_triangle_count(box));
    CHECK(strcmp(r3x_mesh_bounds(box), "-0.5,-0.5,-0.5,0.5,0.5,0.5") == 0, "bounds %s", cp(r3x_mesh_bounds(box)));
    int red = unlit_material(255, 0, 0), green = unlit_material(0, 255, 0);
    int far = r3x_node_create(s, box);
    r3x_node_set_material(far, red);
    r3x_node_set_position(far, 0, 0, -2);
    r3x_scene_render(s, 64, 48);
    CHECK(is_rgb(px(s, 64, 32, 24), 255, 0, 0, 0), "red box at the centre");
    CHECK(is_rgb(px(s, 64, 1, 1), 31, 33, 41, 0), "background at the corner");
    /* a nearer green box, created SECOND: the depth test, not the order */
    int nearN = r3x_node_create(s, box);
    r3x_node_set_material(nearN, green);
    r3x_node_set_position(nearN, 0, 0, 1);
    r3x_scene_render(s, 64, 48);
    CHECK(is_rgb(px(s, 64, 32, 24), 0, 255, 0, 0), "near box wins");
    r3x_node_set_position(nearN, 0, 0, -4);
    r3x_scene_render(s, 64, 48);
    CHECK(is_rgb(px(s, 64, 32, 24), 255, 0, 0, 0), "now it is behind");
    CHECK(item(r3x_scene_stats(s), 1) >= 2 && item(r3x_scene_stats(s), 2) > 0, "stats %s", cp(r3x_scene_stats(s)));
    /* hidden nodes are not drawn and not picked */
    r3x_node_set_visible(far, 0);
    CHECK(!r3x_node_is_visible(far), "hidden");
    r3x_scene_render(s, 64, 48);
    CHECK(is_rgb(px(s, 64, 32, 24), 0, 255, 0, 0), "the far one shows once the near is hidden");
    r3x_node_set_visible(far, 1);
    /* picking: the red box's front face is 4.5 m from the eye at z = 5 */
    CHECK(r3x_scene_pick(s, 64, 48, 32, 24) == far, "pick the box");
    const char *h = r3x_hit_text();
    CHECK(near(item(h, 4), 6.5, 1e-5), "hit distance %s", cp(h));
    CHECK(near(item(h, 3), -1.5, 1e-5), "hit z %s", cp(h));
    CHECK(item(h, 5) >= 1, "hit triangle");
    CHECK(r3x_scene_pick(s, 64, 48, 1, 1) == 0 && r3x_hit_text()[0] == 0, "pick nothing");
    CHECK(r3x_scene_ray_cast(s, 0, 0, -10, 0, 0, 1) == nearN, "a ray from behind meets the far-away green first");
    CHECK(r3x_scene_ray_cast(s, 0, 0, 10, 0, 0, 0) == 0 && r3x_last_error()[0], "zero direction refused");
    CHECK(r3x_scene_pick(s, 64, 48, NAN, 1) == 0, "NaN pick refused");
    /* the far plane cuts what is beyond it */
    r3x_scene_set_clip(s, 0.05, 7);
    r3x_scene_render(s, 64, 48);
    CHECK(is_rgb(px(s, 64, 32, 24), 255, 0, 0, 0), "red within 7 m");
    r3x_scene_set_clip(s, 0.05, 5);
    r3x_scene_render(s, 64, 48);
    CHECK(is_rgb(px(s, 64, 32, 24), 31, 33, 41, 0), "beyond the far plane is not drawn");
    r3x_scene_set_clip(s, 0.05, 0);
    /* node getters and setters */
    CHECK(r3x_node_scene(far) == s && r3x_node_mesh(far) == box && r3x_node_material(far) == red, "node getters");
    CHECK(r3x_scene_node_count(s) == 2 && r3x_scene_node(s, 1) == far && r3x_scene_node(s, 3) == 0, "node list");
    r3x_node_set_mesh(far, 0);
    CHECK(r3x_node_mesh(far) == 0, "no mesh");
    r3x_node_set_mesh(far, 12345);
    CHECK(r3x_last_error()[0] && r3x_node_mesh(far) == 0, "stale mesh refused");
    r3x_node_set_mesh(far, box);
    r3x_node_set_material(far, 999);
    CHECK(r3x_last_error()[0] && r3x_node_material(far) == red, "stale material refused");
    r3x_node_set_rotation(far, 0, 0, 0, 0);
    CHECK(r3x_last_error()[0], "zero quaternion refused");
    r3x_node_set_rotation(far, 0, 0, 0, 2);
    CHECK(strcmp(r3x_node_rotation(far), "0,0,0,1") == 0, "quaternion normalised %s", cp(r3x_node_rotation(far)));
    r3x_node_set_scale(far, 2, 3, 4);
    CHECK(strcmp(r3x_node_scale(far), "2,3,4") == 0, "scale");
    r3x_node_set_scale(far, 0, 1, 1);
    CHECK(r3x_last_error()[0], "zero scale refused");
    /* a mirror (negative scale) still draws its outside */
    r3x_node_set_scale(far, -1, 1, 1);
    r3x_node_set_position(nearN, 0, 5, 0);
    r3x_scene_render(s, 64, 48);
    CHECK(is_rgb(px(s, 64, 32, 24), 255, 0, 0, 0), "mirrored box drawn");
    CHECK(strcmp(r3x_node_position(far), "0,0,-2") == 0, "position %s", cp(r3x_node_position(far)));
    r3x_node_set_position(far, INFINITY, 0, 0);
    CHECK(r3x_last_error()[0] && strcmp(r3x_node_position(far), "0,0,-2") == 0, "infinity refused");
    r3x_node_destroy(nearN);
    CHECK(!r3x_node_is_valid(nearN) && r3x_scene_node_count(s) == 1, "node destroyed");
    r3x_node_destroy(nearN);
    CHECK(r3x_last_error()[0], "twice is a harmless refusal");
    /* destroying the mesh leaves the node drawing nothing */
    r3x_mesh_destroy(box);
    CHECK(!r3x_mesh_is_valid(box) && r3x_node_mesh(far) == 0, "mesh gone");
    r3x_scene_render(s, 64, 48);
    CHECK(is_rgb(px(s, 64, 32, 24), 31, 33, 41, 0), "nothing drawn");
    r3x_material_destroy(red);
    r3x_material_destroy(green);
    CHECK(!r3x_material_is_valid(red), "material gone");
    r3x_scene_destroy(s);
    CHECK(!r3x_node_is_valid(far), "nodes go with their scene");
}

static void test_transforms_and_moves(void)
{
    int s = r3x_scene_create();
    int box = r3x_mesh_box(0.25, 0.25, 0.25);
    int a = r3x_node_create(s, box), b = r3x_node_create(s, box), c = r3x_node_create(s, box);
    r3x_node_set_tag(a, 7);
    r3x_node_set_tag(b, 7);
    r3x_node_set_tag(c, 9);
    CHECK(r3x_node_tag(c) == 9 && r3x_scene_node_by_tag(s, 9) == c && r3x_scene_node_by_tag(s, 8) == 0, "tags");
    /* b3MovesText's lines, an unknown body included */
    int n = r3x_scene_apply_moves(s, "7,1,2,3,0,0,0,1,0\n5,9,9,9,0,0,0,1,1\r\n9,-1,0.5,2,0,0.70710678,0,0.70710678,1\n");
    CHECK(n == 3 && r3x_last_error()[0] == 0, "three nodes moved: %d %s", n, r3x_last_error());
    CHECK(strcmp(r3x_node_transform(a), "1,2,3,0,0,0,1") == 0, "a %s", cp(r3x_node_transform(a)));
    CHECK(strcmp(r3x_node_position(b), "1,2,3") == 0, "b moves with a");
    CHECK(near(item(r3x_node_transform(c), 5), 0.70710678, 1e-6), "c rotated %s", cp(r3x_node_transform(c)));
    /* without the asleep flag too (b3MoveTransform's 7 numbers, with a body) */
    n = r3x_scene_apply_moves(s, "9,0,0,0,0,0,0,1");
    CHECK(n == 1, "eight items accepted");
    n = r3x_scene_apply_moves(s, "7,0,0,0,0,0,0,1\n7,x,0,0,0,0,0,1\n9,4,4,4,0,0,0,1");
    CHECK(n == 2 && strstr(r3x_last_error(), "line 2") != NULL, "line 2 refused, line 1 kept: %d %s", n, r3x_last_error());
    CHECK(strcmp(r3x_node_position(c), "0,0,0") == 0, "lines after the bad one are not applied");
    n = r3x_scene_apply_moves(s, "7,1,1,1,0,0,0,0");
    CHECK(n == 0 && r3x_last_error()[0], "a zero quaternion is not a transform");
    CHECK(r3x_scene_apply_moves(s, "") == 0 && r3x_scene_apply_moves(0, "7,1,1,1,0,0,0,1") == 0, "empty and stale");
    /* transform text, b3BodyTransform's form */
    r3x_node_set_transform_text(a, "0.5,0.25,-1,0,0,0,1");
    CHECK(strcmp(r3x_node_transform(a), "0.5,0.25,-1,0,0,0,1") == 0, "transform text");
    r3x_node_set_transform_text(a, "1,2,3");
    CHECK(r3x_last_error()[0], "three items refused");
    r3x_node_set_transform(a, 1, 2, 3, 0, 0, 0, 1);
    CHECK(strcmp(r3x_node_transform(a), "1,2,3,0,0,0,1") == 0, "transform");
    /* a quarter turn about y carries the box's +x face to -z: picked from -z */
    int m = r3x_material_create(200, 0, 0);
    int lone = r3x_scene_create();
    int q = r3x_node_create(lone, box);
    r3x_node_set_material(q, m);
    r3x_node_set_transform(q, 3, 0, 0, 0, 0.70710678, 0, 0.70710678);
    CHECK(r3x_scene_ray_cast(lone, 3, 0, -5, 0, 0, 1) == q && near(item(r3x_hit_text(), 3), -0.25, 1e-5),
          "rotated box hit at z = -0.25: %s", cp(r3x_hit_text()));
    /* 2000 bodies in one call */
    int many = r3x_scene_create();
    char *text = (char *)malloc(2000 * 64);
    int at = 0;
    for (int i = 1; i <= 2000; i++) {
        int nd = r3x_node_create(many, box);
        r3x_node_set_tag(nd, 1000 + i);
        at += sprintf(text + at, "%d,%d,0,0,0,0,0,1,0\n", 1000 + i, i);
    }
    CHECK(r3x_scene_apply_moves(many, text) == 2000, "2000 moved");
    CHECK(strcmp(r3x_node_position(r3x_scene_node_by_tag(many, 2500)), "1500,0,0") == 0, "body 2500 at x 1500");
    free(text);
    r3x_scene_destroy(many);
    r3x_scene_destroy(lone);
    r3x_material_destroy(m);
    r3x_mesh_destroy(box);
    r3x_scene_destroy(s);
}

static void test_textures(void)
{
    int t = r3x_texture_load(asset("quadrants.png"));
    CHECK(r3x_texture_is_valid(t) && r3x_texture_width(t) == 4 && r3x_texture_height(t) == 4,
          "loaded %d %s", t, r3x_last_error());
    CHECK(r3x_texture_is_smooth(t) && r3x_texture_is_repeat(t), "smooth and repeat by default");
    r3x_texture_set_smooth(t, 0);
    r3x_texture_set_repeat(t, 0);
    CHECK(!r3x_texture_is_smooth(t) && !r3x_texture_is_repeat(t), "flags");
    CHECK(r3x_texture_load(asset("no-such-file.png")) == 0 && r3x_last_error()[0], "missing file refused");
    CHECK(r3x_texture_load(asset("broken.png")) == 0, "broken file refused");
    CHECK(r3x_texture_load("") == 0 && r3x_texture_load(NULL) == 0, "no name refused");
    int len = 0;
    unsigned char *bytes = read_file(asset("quadrants.png"), &len);
    CHECK(bytes != NULL, "read the png");
    int t2 = r3x_texture_decode(bytes, len);
    CHECK(r3x_texture_width(t2) == 4, "decoded from bytes");
    CHECK(r3x_texture_decode(bytes, 10) == 0, "a truncated picture refused");
    CHECK(r3x_texture_decode(NULL, 0) == 0, "nothing refused");
    free(bytes);
    /* imageData: 0,R,G,B a pixel; a 2x1 of blue then yellow */
    unsigned char id[8] = { 0, 0, 0, 255, 0, 255, 255, 0 };
    int t3 = r3x_texture_from_image_data(id, 8, 2, 1);
    CHECK(r3x_texture_width(t3) == 2 && r3x_texture_height(t3) == 1, "from imageData");
    CHECK(r3x_texture_from_image_data(id, 7, 2, 1) == 0, "short imageData refused");
    CHECK(r3x_texture_from_image_data(id, 8, 0, 1) == 0, "0 wide refused");
    int t4 = r3x_texture_checker(64, 8, 255, 255, 255, 0, 0, 0);
    CHECK(r3x_texture_width(t4) == 64, "checker");
    CHECK(r3x_texture_checker(64, 65, 0, 0, 0, 0, 0, 0) == 0 && r3x_texture_checker(1, 1, 0, 0, 0, 0, 0, 0) == 0,
          "bad checkers refused");

    /* the quadrants on a plane seen from straight above, unlit, nearest:
     * (0,0) is the texture's top-left, which a plane puts at -x,-z, the top
     * of the picture when looking down */
    int s = r3x_scene_create();
    r3x_scene_set_camera(s, 0, 10, 0, 0, 0, 0, 40);
    int plane = r3x_mesh_plane(3, 3, 1, 1);
    int m = r3x_material_create(255, 255, 255);
    r3x_material_set_unlit(m, 1);
    r3x_material_set_texture(m, t);
    CHECK(r3x_material_texture(m) == t, "material texture");
    int nd = r3x_node_create(s, plane);
    r3x_node_set_material(nd, m);
    r3x_scene_render(s, 100, 100);
    CHECK(is_rgb(px(s, 100, 35, 35), 255, 0, 0, 0), "top-left red");
    CHECK(is_rgb(px(s, 100, 65, 35), 0, 255, 0, 0), "top-right green");
    CHECK(is_rgb(px(s, 100, 35, 65), 0, 0, 255, 0), "bottom-left blue");
    CHECK(is_rgb(px(s, 100, 65, 65), 255, 255, 255, 0), "bottom-right white");
    /* the material colour tints the texture */
    r3x_material_set_color(m, 128, 255, 255);
    CHECK(strcmp(r3x_material_color(m), "128,255,255") == 0, "colour");
    r3x_scene_render(s, 100, 100);
    CHECK(is_rgb(px(s, 100, 65, 65), 128, 255, 255, 1), "tinted white");
    r3x_material_set_color(m, 255, 255, 255);
    /* smooth sampling blends across the quadrant border */
    r3x_texture_set_smooth(t, 1);
    r3x_scene_render(s, 100, 100);
    RGB mid = px(s, 100, 50, 35);
    CHECK(mid.r > 20 && mid.g > 20, "bilinear blend red/green at the border %d %d %d", mid.r, mid.g, mid.b);
    /* the imageData texture: blue on the left, yellow on the right */
    r3x_material_set_texture(m, t3);
    r3x_texture_set_smooth(t3, 0);
    r3x_scene_render(s, 100, 100);
    CHECK(is_rgb(px(s, 100, 30, 50), 0, 0, 255, 0) && is_rgb(px(s, 100, 70, 50), 255, 255, 0, 0), "imageData order");
    /* destroying a texture in use: the material forgets it, harmlessly */
    r3x_texture_destroy(t3);
    CHECK(r3x_material_texture(m) == 0, "dead texture reads as none");
    r3x_scene_render(s, 100, 100);
    CHECK(is_rgb(px(s, 100, 30, 50), 255, 255, 255, 0), "drawn untextured");
    r3x_material_set_texture(m, 54321);
    CHECK(r3x_last_error()[0], "stale texture refused");
    /* cutout: the transparent half shows what is behind */
    int cut = r3x_texture_load(asset("cutout.png"));
    r3x_texture_set_smooth(cut, 0);
    r3x_material_set_texture(m, cut);
    r3x_material_set_cutout(m, 1);
    CHECK(r3x_material_is_cutout(m), "cutout");
    r3x_scene_set_background(s, 0, 0, 0);
    r3x_scene_render(s, 100, 100);
    CHECK(is_rgb(px(s, 100, 30, 50), 255, 255, 0, 0) && is_rgb(px(s, 100, 70, 50), 0, 0, 0, 0), "cut out");
    r3x_material_set_cutout(m, 0);
    r3x_scene_render(s, 100, 100);
    CHECK(is_rgb(px(s, 100, 70, 50), 0, 0, 0, 0), "without cutout the clear texel's colour (black) is drawn");
    r3x_scene_destroy(s);
    r3x_material_destroy(m);
    r3x_mesh_destroy(plane);
    r3x_texture_destroy(t);
    r3x_texture_destroy(t2);
    r3x_texture_destroy(t4);
    r3x_texture_destroy(cut);
    CHECK(!r3x_texture_is_valid(t) && r3x_texture_width(t) == 0, "texture gone");
}

/* The texture sampler has three paths (a repeating texture with power-of-two
 * sides, a clamped one of any size, a repeating one of any other size), each
 * with a nearest and a smooth half. One picture of six distinct texels goes
 * through all of them, at 4x2 and at 3x2 texels, laid once and laid twice
 * across a plane, and every texel is looked for at its own centre. */
static int texel_seen(int s, double wx, double wz, const unsigned char *rgb, int tol)
{
    const char *at = r3x_scene_project(s, 240, 240, wx, 0, wz);
    return is_rgb(px(s, 240, (int)item(at, 1), (int)item(at, 2)), rgb[0], rgb[1], rgb[2], tol);
}

static void test_texture_paths(void)
{
    static const unsigned char k_colors[8][3] = {
        { 255, 0, 0 }, { 0, 255, 0 }, { 0, 0, 255 }, { 255, 255, 0 },
        { 255, 0, 255 }, { 0, 255, 255 }, { 255, 255, 255 }, { 90, 90, 90 } };
    int s = r3x_scene_create();
    r3x_scene_set_camera(s, 0, 10, 0, 0, 0, 0, 40);
    int m = r3x_material_create(255, 255, 255);
    r3x_material_set_unlit(m, 1);
    int once = r3x_mesh_plane(3, 3, 1, 1), twice = r3x_mesh_plane(3, 3, 2, 2);
    int nd = r3x_node_create(s, once);
    r3x_node_set_material(nd, m);
    for (int tw = 3; tw <= 4; tw++) {
        const int th = 2;
        unsigned char id[4 * 2 * 4];
        for (int i = 0; i < tw * th; i++) {
            id[i * 4] = 0; id[i * 4 + 1] = k_colors[i][0]; id[i * 4 + 2] = k_colors[i][1]; id[i * 4 + 3] = k_colors[i][2];
        }
        int t = r3x_texture_from_image_data(id, tw * th * 4, tw, th);
        r3x_material_set_texture(m, t);
        for (int mode = 0; mode < 4; mode++) {
            int rep = mode & 1, smooth = mode >> 1;
            r3x_texture_set_repeat(t, rep);
            r3x_texture_set_smooth(t, smooth);
            /* laid once: texel (i,j) is centred at its own place on the 6 m plane */
            r3x_node_set_mesh(nd, once);
            r3x_scene_render(s, 240, 240);
            int good = 0;
            for (int j = 0; j < th; j++) {
                for (int i = 0; i < tw; i++)
                    good += texel_seen(s, -3 + (i + 0.5) * 6.0 / tw, -3 + (j + 0.5) * 6.0 / th, k_colors[j * tw + i], smooth ? 12 : 0);
            }
            CHECK(good == tw * th, "%dx%d texels, repeat %d smooth %d, laid once: %d of %d texels in place",
                  tw, th, rep, smooth, good, tw * th);
            /* laid twice each way: repeating, every texel is there four
             * times; clamped, the first copy is whole and the rest is its
             * last column and row drawn out */
            r3x_node_set_mesh(nd, twice);
            r3x_scene_render(s, 240, 240);
            good = 0;
            int want = 0;
            for (int cy = 0; cy < 2; cy++) {
                for (int cx = 0; cx < 2; cx++) {
                    for (int j = 0; j < th; j++) {
                        for (int i = 0; i < tw; i++) {
                            int si = i, sj = j;
                            if (!rep && cx) si = tw - 1;
                            if (!rep && cy) sj = th - 1;
                            want++;
                            good += texel_seen(s, -3 + (cx * tw + i + 0.5) * 3.0 / tw, -3 + (cy * th + j + 0.5) * 3.0 / th,
                                               k_colors[sj * tw + si], smooth ? 12 : 0);
                        }
                    }
                }
            }
            CHECK(good == want, "%dx%d texels, repeat %d smooth %d, laid twice: %d of %d texels in place",
                  tw, th, rep, smooth, good, want);
        }
        /* a coordinate thousands of repeats out still lands on a texel, and
         * the picture is the same from any thread count */
        r3x_texture_set_repeat(t, 1);
        r3x_texture_set_smooth(t, 1);
        int far = r3x_mesh_plane(3, 3, 5000, 5000);
        r3x_node_set_mesh(nd, far);
        CHECK(r3x_scene_render(s, 240, 240) == 240 * 240 * 4, "five thousand repeats drawn");
        r3x_mesh_destroy(far);
        r3x_texture_destroy(t);
    }
    r3x_scene_destroy(s);
    r3x_material_destroy(m);
    r3x_mesh_destroy(once);
    r3x_mesh_destroy(twice);
}

static void test_obj(void)
{
    int cube = r3x_mesh_load_obj(asset("cube.obj"));
    CHECK(cube > 0, "cube.obj %s", r3x_last_error());
    CHECK(r3x_mesh_triangle_count(cube) == 12 && r3x_mesh_vertex_count(cube) == 36, "12 triangles");
    CHECK(r3x_mesh_slot_count(cube) == 2, "two materials");
    CHECK(strcmp(r3x_mesh_slot_name(cube, 1), "front") == 0 && strcmp(r3x_mesh_slot_name(cube, 2), "rest") == 0,
          "slot names");
    CHECK(strcmp(r3x_mesh_slot_texture_name(cube, 1), "quadrants.png") == 0, "texture name %s",
          cp(r3x_mesh_slot_texture_name(cube, 1)));
    CHECK(r3x_mesh_slot_texture_name(cube, 2)[0] == 0 && r3x_mesh_slot_name(cube, 3)[0] == 0, "no texture, no slot 3");
    int front = r3x_mesh_slot_material(cube, 1), rest = r3x_mesh_slot_material(cube, 2);
    CHECK(r3x_material_is_valid(front) && r3x_material_texture(front) > 0, "the MTL's texture was loaded");
    CHECK(strcmp(r3x_material_color(rest), "51,102,204") == 0, "Kd %s", cp(r3x_material_color(rest)));
    CHECK(near(item(r3x_material_specular(rest), 1), 0.5, 1e-6) && near(item(r3x_material_specular(rest), 2), 64, 1e-6),
          "Ks and Ns %s", cp(r3x_material_specular(rest)));
    CHECK(strcmp(r3x_mesh_bounds(cube), "-0.5,-0.5,-0.5,0.5,0.5,0.5") == 0, "bounds");
    int tex = r3x_material_texture(front);
    r3x_texture_set_smooth(tex, 0);
    r3x_material_set_unlit(front, 1);
    CHECK(r3x_material_is_unlit(front), "unlit");
    int s = r3x_scene_create();
    r3x_scene_set_camera(s, 0, 0, 3, 0, 0, 0, 50);
    int nd = r3x_node_create(s, cube);
    r3x_scene_render(s, 100, 100);
    CHECK(is_rgb(px(s, 100, 40, 40), 255, 0, 0, 0), "front face top-left red (OBJ v flipped)");
    CHECK(is_rgb(px(s, 100, 60, 40), 0, 255, 0, 0), "top-right green");
    CHECK(is_rgb(px(s, 100, 40, 60), 0, 0, 255, 0), "bottom-left blue");
    /* turned to show the +x face: the "rest" material, lit */
    r3x_node_set_rotation(nd, 0, -0.70710678, 0, 0.70710678);
    r3x_scene_render(s, 100, 100);
    RGB side = px(s, 100, 50, 50);
    CHECK(side.b > side.r && side.b > side.g && side.b < 255, "lit blue side %d %d %d", side.r, side.g, side.b);
    /* the slot can be given another material, and back */
    int red = r3x_material_create(255, 0, 0);
    r3x_material_set_unlit(red, 1);
    r3x_mesh_set_slot_material(cube, 2, red);
    r3x_scene_render(s, 100, 100);
    CHECK(is_rgb(px(s, 100, 50, 50), 255, 0, 0, 0), "slot material replaced");
    r3x_mesh_set_slot_material(cube, 2, rest);
    r3x_mesh_set_slot_material(cube, 1025, red);
    CHECK(r3x_last_error()[0], "slot 1025 refused");
    /* destroying the mesh takes the materials and texture it loaded, not ours */
    r3x_mesh_destroy(cube);
    CHECK(!r3x_material_is_valid(front) && !r3x_material_is_valid(rest) && !r3x_texture_is_valid(tex),
          "the model's own materials and texture go with it");
    CHECK(r3x_material_is_valid(red), "ours stays");
    r3x_material_destroy(red);

    /* ... and from wherever the script has moved them: slot 1 given none,
     * slot 2 ours, slot 2's own moved to a new slot 3 and put on a node */
    int c4 = r3x_mesh_load_obj(asset("cube.obj"));
    int front4 = r3x_mesh_slot_material(c4, 1), rest4 = r3x_mesh_slot_material(c4, 2);
    int tex4 = r3x_material_texture(front4);
    int green = r3x_material_create(0, 255, 0);
    char counts[128];
    snprintf(counts, sizeof counts, "%s", r3x_live_counts());
    r3x_mesh_set_slot_material(c4, 1, 0);
    r3x_mesh_set_slot_material(c4, 2, green);
    r3x_mesh_set_slot_material(c4, 3, rest4);
    CHECK(r3x_mesh_slot_count(c4) == 3 && r3x_mesh_slot_material(c4, 3) == rest4, "moved to slot 3");
    int nd4 = r3x_node_create(s, c4);
    r3x_node_set_material(nd4, rest4);
    r3x_scene_render(s, 100, 100);
    r3x_mesh_destroy(c4);
    CHECK(!r3x_material_is_valid(front4) && !r3x_material_is_valid(rest4) && !r3x_texture_is_valid(tex4),
          "the model's own materials and texture go with it from any slot");
    CHECK(r3x_material_is_valid(green), "ours stays again");
    CHECK(item(r3x_live_counts(), 4) == item(counts, 4) - 2 && item(r3x_live_counts(), 5) == item(counts, 5) - 1,
          "two materials and a texture fewer: %s, was %s", cp(r3x_live_counts()), counts);
    r3x_scene_render(s, 100, 100); /* a node naming them draws nothing, harmlessly */
    /* the script may destroy one first: the mesh forgets it, and a material
     * made after it (which may reuse its place in the table) stays */
    int c5 = r3x_mesh_load_obj(asset("cube.obj"));
    int front5 = r3x_mesh_slot_material(c5, 1), rest5 = r3x_mesh_slot_material(c5, 2);
    r3x_material_destroy(front5);
    CHECK(!r3x_material_is_valid(front5) && r3x_mesh_slot_material(c5, 1) == 0, "the script destroyed it");
    int after = r3x_material_create(1, 2, 3);
    r3x_mesh_destroy(c5);
    CHECK(!r3x_material_is_valid(rest5) && r3x_material_is_valid(after), "only what is still the mesh's goes");
    r3x_material_destroy(after);
    r3x_material_destroy(green);

    /* from text: the MTL as text too, no texture loaded (no disk) */
    int olen = 0, mlen = 0;
    char *obj = (char *)read_file(asset("cube.obj"), &olen);
    char *mtl = (char *)read_file(asset("cube.mtl"), &mlen);
    int c2 = r3x_mesh_parse_obj(obj, mtl);
    CHECK(c2 > 0 && r3x_mesh_triangle_count(c2) == 12 && r3x_mesh_slot_count(c2) == 2, "parsed %s", r3x_last_error());
    CHECK(r3x_material_texture(r3x_mesh_slot_material(c2, 1)) == 0, "no texture read from text");
    CHECK(strcmp(r3x_mesh_slot_texture_name(c2, 1), "quadrants.png") == 0, "but its name is known");
    int c3 = r3x_mesh_parse_obj(obj, "");
    CHECK(c3 > 0 && r3x_mesh_slot_count(c3) == 2, "without the MTL: fallback materials %d", r3x_mesh_slot_count(c3));
    r3x_mesh_destroy(c2);
    r3x_mesh_destroy(c3);
    free(obj); free(mtl);
    /* a quad, a pentagon (fan-triangulated), negative indices, no normals */
    int poly = r3x_mesh_parse_obj("v 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nv -1 0.5 0\nf 1 2 3 4\nf -5 -4 -3 -2 -1\n", NULL);
    CHECK(r3x_mesh_triangle_count(poly) == 5, "2 + 3 triangles: %d %s", r3x_mesh_triangle_count(poly), r3x_last_error());
    r3x_mesh_destroy(poly);
    CHECK(r3x_mesh_load_obj(asset("bad-index.obj")) == 0 && strstr(r3x_last_error(), "does not exist"),
          "a bad index refused: %s", r3x_last_error());
    CHECK(r3x_mesh_parse_obj("f 1 2 3\n", NULL) == 0, "faces without vertices refused");
    CHECK(r3x_mesh_parse_obj("v 1 2 3\n", NULL) == 0, "no faces refused");
    CHECK(r3x_mesh_parse_obj("v 100000000 0 0\nv 0 0 0\nv 0 1 0\nf 1 2 3\n", NULL) == 0, "a huge coordinate refused");
    CHECK(r3x_mesh_load_obj(asset("none.obj")) == 0 && r3x_mesh_load_obj("") == 0, "missing file refused");
    CHECK(r3x_mesh_parse_obj("", NULL) == 0 && r3x_mesh_parse_obj(NULL, NULL) == 0, "empty text refused");
    r3x_scene_destroy(s);
}

static void test_meshes(void)
{
    int sp = r3x_mesh_sphere(1, 16, 8);
    CHECK(r3x_mesh_triangle_count(sp) == 16 * 8 * 2, "sphere %d", r3x_mesh_triangle_count(sp));
    CHECK(near(item(r3x_mesh_bounds(sp), 5), 1, 1e-6), "sphere top at 1");
    int cy = r3x_mesh_cylinder(0.5, 1, 12);
    CHECK(near(item(r3x_mesh_bounds(cy), 2), -1, 1e-6) && near(item(r3x_mesh_bounds(cy), 5), 1, 1e-6), "cylinder %s",
          cp(r3x_mesh_bounds(cy)));
    int ca = r3x_mesh_capsule(0.5, 1, 12, 6);
    CHECK(near(item(r3x_mesh_bounds(ca), 2), -1.5, 1e-6) && near(item(r3x_mesh_bounds(ca), 5), 1.5, 1e-6),
          "capsule from -1.5 to 1.5 %s", cp(r3x_mesh_bounds(ca)));
    int pl = r3x_mesh_plane(2, 3, 4, 6);
    CHECK(strcmp(r3x_mesh_bounds(pl), "-2,0,-3,2,0,3") == 0, "plane %s", cp(r3x_mesh_bounds(pl)));
    CHECK(r3x_mesh_sphere(1, 2, 8) == 0 && r3x_mesh_sphere(1, 257, 8) == 0 && r3x_mesh_sphere(0, 8, 8) == 0,
          "bad spheres refused");
    CHECK(r3x_mesh_box(NAN, 1, 1) == 0 && r3x_mesh_box(1e6, 1, 1) == 0, "bad boxes refused");
    CHECK(r3x_mesh_plane(1, 1, 0, 1) == 0 && r3x_mesh_cylinder(1, 0, 8) == 0 && r3x_mesh_capsule(1, 1, 8, 1) == 0,
          "bad shapes refused");
    /* every primitive is closed and faces out: seen from six sides, each
     * covers the centre of the picture with its front faces */
    int prims[4] = { sp, cy, ca, r3x_mesh_box(0.5, 0.5, 0.5) };
    int s = r3x_scene_create();
    int m = r3x_material_create(255, 255, 255);
    r3x_material_set_unlit(m, 1);
    int nd = r3x_node_create(s, sp);
    r3x_node_set_material(nd, m);
    const double eyes[6][3] = { { 0, 0, 6 }, { 0, 0, -6 }, { 6, 0, 0 }, { -6, 0, 0 }, { 0, 6, 0 }, { 0, -6, 0 } };
    for (int i = 0; i < 4; i++) {
        r3x_node_set_mesh(nd, prims[i]);
        for (int e = 0; e < 6; e++) {
            r3x_scene_set_camera(s, eyes[e][0], eyes[e][1], eyes[e][2], 0, 0, 0, 50);
            r3x_scene_render(s, 40, 40);
            CHECK(is_rgb(px(s, 40, 20, 20), 255, 255, 255, 0), "primitive %d from side %d", i, e);
        }
    }
    /* a mesh built from script, and from triangle text */
    int mm = r3x_mesh_create();
    CHECK(r3x_mesh_add_vertex(mm, -1, -1, 0, 0, 0, 1, 0, 1) == 1, "vertex 1");
    CHECK(r3x_mesh_add_vertex(mm, 1, -1, 0, 0, 0, 0, 1, 1) == 2, "vertex 2 (zero normal accepted)");
    CHECK(r3x_mesh_add_vertex(mm, 0, 1, 0, 0, 0, 1, 0.5, 0) == 3, "vertex 3");
    CHECK(r3x_mesh_add_vertex(mm, NAN, 0, 0, 0, 0, 1, 0, 0) == 0, "NaN vertex refused");
    CHECK(r3x_mesh_add_triangle(mm, 1, 2, 3, 2) == 1 && r3x_mesh_slot_count(mm) == 2, "triangle in slot 2");
    CHECK(r3x_mesh_add_triangle(mm, 1, 2, 4, 1) == 0 && r3x_mesh_add_triangle(mm, 0, 1, 2, 1) == 0, "bad indices refused");
    CHECK(r3x_mesh_add_triangle(mm, 1, 2, 3, 0) == 0, "slot 0 refused");
    r3x_mesh_compute_normals(mm);
    r3x_node_set_mesh(nd, mm);
    r3x_scene_set_camera(s, 0, 0, 5, 0, 0, 0, 50);
    r3x_scene_render(s, 40, 40);
    CHECK(is_rgb(px(s, 40, 20, 22), 255, 255, 255, 0), "script mesh drawn");
    int tm = r3x_mesh_from_triangles_text("-1,-1,0, 1,-1,0, 0,1,0\n\n  \n0,0,1,1,0,1,0,1,1\n");
    CHECK(r3x_mesh_triangle_count(tm) == 2, "two triangles from text %s", r3x_last_error());
    CHECK(r3x_mesh_from_triangles_text("1,2,3\n") == 0 && strstr(r3x_last_error(), "line 1"), "short line refused");
    CHECK(r3x_mesh_from_triangles_text("") == 0 && r3x_mesh_from_triangles_text(NULL) == 0, "nothing refused");
    CHECK(r3x_mesh_from_triangles_text("0,0,0,1,0,0,0,1,0\n1,2,3,4,5,6,7,8,nan\n") == 0 && strstr(r3x_last_error(), "line 2"),
          "nan refused");
    r3x_node_set_mesh(nd, tm);
    r3x_scene_render(s, 40, 40);
    CHECK(is_rgb(px(s, 40, 20, 22), 255, 255, 255, 0), "text mesh drawn");
    /* the stale mesh calls */
    r3x_mesh_destroy(tm);
    CHECK(r3x_mesh_add_vertex(tm, 0, 0, 0, 0, 1, 0, 0, 0) == 0 && r3x_mesh_vertex_count(tm) == 0 &&
          r3x_mesh_bounds(tm)[0] == 0 && r3x_mesh_slot_count(tm) == 0 && r3x_mesh_slot_material(tm, 1) == 0,
          "stale mesh harmless");
    r3x_mesh_compute_normals(tm);
    r3x_mesh_set_slot_material(tm, 1, 0);
    r3x_scene_destroy(s);
    for (int i = 0; i < 4; i++) r3x_mesh_destroy(prims[i]);
    r3x_mesh_destroy(pl);
    r3x_mesh_destroy(mm);
    r3x_material_destroy(m);
}

static double brightness(int s, int w, int x, int y) { RGB c = px(s, w, x, y); return c.r + c.g + c.b; }

static void test_lighting(void)
{
    int s = r3x_scene_create();
    r3x_scene_set_camera(s, 0, 0, 5, 0, 0, 0, 50);
    int box = r3x_mesh_box(1, 1, 0.1);
    int m = r3x_material_create(200, 200, 200);
    int nd = r3x_node_create(s, box);
    r3x_node_set_material(nd, m);
    int L = r3x_scene_light(s, 1);
    /* a light straight at the face is brighter than one at a slant */
    r3x_light_set_direction(L, 0, 0, -1);
    r3x_scene_render(s, 40, 40);
    double head = brightness(s, 40, 20, 20);
    r3x_light_set_direction(L, 0, -1, -1);
    r3x_scene_render(s, 40, 40);
    double slant = brightness(s, 40, 20, 20);
    CHECK(head > slant, "head-on %g > slant %g", head, slant);
    /* behind the face: ambient only */
    r3x_light_set_direction(L, 0, 0, 1);
    r3x_scene_render(s, 40, 40);
    CHECK(is_rgb(px(s, 40, 20, 20), 50, 50, 50, 1), "ambient only");
    r3x_light_set_direction(L, 0, 0, 0);
    CHECK(r3x_last_error()[0], "zero direction refused");
    r3x_light_set_direction(L, 0, 0, -1);
    r3x_light_set_enabled(L, 0);
    CHECK(!r3x_light_is_enabled(L), "disabled");
    r3x_scene_render(s, 40, 40);
    CHECK(is_rgb(px(s, 40, 20, 20), 50, 50, 50, 1), "disabled light gives nothing");
    r3x_light_set_enabled(L, 1);
    r3x_light_set_color(L, 255, 0, 0, 1);
    CHECK(strcmp(r3x_light_color(L), "255,0,0,1") == 0, "light colour");
    r3x_scene_render(s, 40, 40);
    RGB c = px(s, 40, 20, 20);
    CHECK(c.r > c.g + 100 && c.g == c.b, "red light %d %d %d", c.r, c.g, c.b);
    r3x_light_set_color(L, 255, 255, 255, 101);
    CHECK(r3x_last_error()[0], "intensity 101 refused");
    r3x_light_set_position(L, 0, 0, 0);
    CHECK(r3x_last_error()[0], "a directional light has no position");
    r3x_light_destroy(L);
    CHECK(r3x_scene_light_count(s) == 0 && !r3x_light_is_valid(L), "light destroyed");
    /* a point light: near the face brighter than far, and out of range dark */
    int P = r3x_light_create_point(s, 0, 0, 1, 255, 255, 255, 1, 10);
    CHECK(r3x_light_kind(P) == 2 && strcmp(r3x_light_vector(P), "0,0,1") == 0, "point light");
    r3x_scene_render(s, 40, 40);
    double close = brightness(s, 40, 20, 20);
    r3x_light_set_position(P, 0, 0, 5);
    r3x_scene_render(s, 40, 40);
    double away = brightness(s, 40, 20, 20);
    CHECK(close > away, "closer is brighter %g %g", close, away);
    r3x_light_set_position(P, 0, 0, 20);
    r3x_scene_render(s, 40, 40);
    CHECK(is_rgb(px(s, 40, 20, 20), 50, 50, 50, 1), "beyond its range");
    r3x_light_set_direction(P, 0, 0, 1);
    CHECK(r3x_last_error()[0], "a point light has no direction");
    int P2 = r3x_light_create_point(s, 0, 0, 3, 255, 255, 255, 1, 0);
    r3x_scene_render(s, 40, 40);
    CHECK(brightness(s, 40, 20, 20) > 150, "no range: inverse square");
    r3x_light_destroy(P2);
    /* highlights: a shiny material is brighter at the mirror angle */
    r3x_light_set_position(P, 0, 0, 3);
    r3x_scene_render(s, 40, 40);
    double dull = brightness(s, 40, 20, 20);
    r3x_material_set_specular(m, 1, 16);
    r3x_scene_render(s, 40, 40);
    CHECK(brightness(s, 40, 20, 20) > dull, "specular highlight");
    r3x_material_set_specular(m, 2, 16);
    CHECK(r3x_last_error()[0], "strength 2 refused");
    r3x_material_set_specular(m, 0, 16);
    /* emissive adds light of its own */
    r3x_light_set_enabled(P, 0);
    r3x_scene_set_ambient(s, 0, 0, 0);
    r3x_material_set_emissive(m, 0, 0, 100);
    r3x_scene_render(s, 40, 40);
    CHECK(is_rgb(px(s, 40, 20, 20), 0, 0, 100, 1), "emissive");
    r3x_material_set_emissive(m, 0, 0, 0);
    r3x_light_set_enabled(P, 1);
    r3x_scene_set_ambient(s, 64, 64, 64);
    /* nine lights: the ninth refused */
    for (int i = 0; i < 7; i++) CHECK(r3x_light_create_directional(s, 0, -1, 0, 10, 10, 10, 0.1) > 0, "light %d", i);
    CHECK(r3x_light_create_directional(s, 0, -1, 0, 10, 10, 10, 0.1) == 0 && strstr(r3x_last_error(), "8 lights"),
          "the ninth refused");
    CHECK(r3x_light_create_point(0, 0, 0, 0, 1, 1, 1, 1, 0) == 0, "stale scene refused");
    CHECK(r3x_light_create_point(s, 0, 0, 0, 1, 1, 1, 1, -1) == 0, "negative range refused");
    /* flat and double-sided */
    r3x_material_set_flat(m, 1);
    CHECK(r3x_material_is_flat(m), "flat");
    r3x_scene_render(s, 40, 40);
    r3x_material_set_flat(m, 0);
    int quad = r3x_mesh_plane(1, 1, 1, 1);
    r3x_node_set_mesh(nd, quad);
    r3x_node_set_rotation(nd, -0.70710678, 0, 0, 0.70710678);  /* plane faces -z now */
    r3x_scene_render(s, 40, 40);
    CHECK(is_rgb(px(s, 40, 20, 20), 31, 33, 41, 0), "a back face is culled");
    r3x_material_set_double_sided(m, 1);
    CHECK(r3x_material_is_double_sided(m), "double-sided");
    r3x_scene_render(s, 40, 40);
    CHECK(!is_rgb(px(s, 40, 20, 20), 31, 33, 41, 0), "and drawn when double-sided");
    r3x_scene_destroy(s);
    r3x_mesh_destroy(box);
    r3x_mesh_destroy(quad);
    r3x_material_destroy(m);
}

static void test_fog_supersample_threads(void)
{
    int s = r3x_scene_create();
    r3x_scene_set_camera(s, 0, 0, 10, 0, 0, 0, 50);
    int box = r3x_mesh_box(1, 1, 1);
    int m = unlit_material(255, 255, 255);
    int nd = r3x_node_create(s, box);
    r3x_node_set_material(nd, m);
    r3x_scene_set_fog(s, 0, 0, 255, 1, 5);
    r3x_scene_render(s, 40, 40);
    CHECK(is_rgb(px(s, 40, 20, 20), 0, 0, 255, 0), "all fog beyond its end");
    r3x_scene_set_fog(s, 0, 0, 255, 8, 10);
    r3x_scene_render(s, 40, 40);
    RGB f = px(s, 40, 20, 20);
    CHECK(f.r > 100 && f.r < 200 && f.b == 255, "half fog %d %d %d", f.r, f.g, f.b);
    r3x_scene_set_fog(s, 0, 0, 0, 5, 1);
    CHECK(r3x_last_error()[0], "fog ending before it starts refused");
    r3x_scene_set_fog(s, 0, 0, 0, 0, 0);
    r3x_scene_render(s, 40, 40);
    CHECK(is_rgb(px(s, 40, 20, 20), 255, 255, 255, 0), "fog off");
    /* supersampling: the inside is the same colour, an edge pixel is a blend */
    r3x_scene_set_supersample(s, 4);
    r3x_scene_render(s, 40, 40);
    CHECK(is_rgb(px(s, 40, 20, 20), 255, 255, 255, 0), "inside unchanged");
    int blended = 0;
    for (int x = 0; x < 40; x++) {
        RGB c = px(s, 40, x, 20);
        if (c.r > 40 && c.r < 240) blended++;
    }
    CHECK(blended >= 2, "edges blended (%d)", blended);
    r3x_scene_set_supersample(s, 1);
    /* the same picture on 1 thread and on 8: byte for byte */
    int tex = r3x_texture_checker(128, 8, 250, 120, 30, 20, 60, 200);
    int lit = r3x_material_create(255, 255, 255);
    r3x_material_set_texture(lit, tex);
    r3x_material_set_specular(lit, 0.6, 24);
    int sp = r3x_mesh_sphere(1.5, 48, 24);
    r3x_node_set_mesh(nd, sp);
    r3x_node_set_material(nd, lit);
    r3x_node_set_rotation(nd, 0.2, 0.3, 0.1, 0.9);
    r3x_light_create_point(s, 2, 2, 3, 255, 240, 200, 2, 20);
    for (int i = 0; i < 30; i++) {
        int k = r3x_node_create(s, box);
        r3x_node_set_material(k, lit);
        r3x_node_set_position(k, (i % 6) - 2.5, (i / 6) - 2, -2 - i * 0.1);
        r3x_node_set_scale(k, 0.3, 0.3, 0.3);
    }
    r3x_scene_set_supersample(s, 2);
    r3x_set_thread_count(1);
    int n = r3x_scene_render(s, 320, 240);
    unsigned char *one = (unsigned char *)malloc((size_t)n);
    memcpy(one, r3x_scene_frame(s), (size_t)n);
    int same = 1;
    for (int t = 2; t <= 16; t *= 2) {
        r3x_set_thread_count(t);
        r3x_scene_render(s, 320, 240);
        if (memcmp(one, r3x_scene_frame(s), (size_t)n) != 0) { same = 0; printf("threads %d differ\n", t); }
    }
    CHECK(same, "every thread count draws the same picture");
    free(one);
    r3x_scene_destroy(s);
    r3x_mesh_destroy(box);
    r3x_mesh_destroy(sp);
    r3x_material_destroy(m);
    r3x_material_destroy(lit);
    r3x_texture_destroy(tex);
}

/* A picture begun (r3x_scene_render_begin) is the picture r3x_scene_render
 * draws, byte for byte; nothing a script does while it is drawing can reach
 * it, and nothing it reads can be freed under it. */
static void test_background(void)
{
    int s = r3x_scene_create();
    r3x_scene_set_camera(s, 0, 0, 10, 0, 0, 0, 50);
    r3x_scene_set_background(s, 10, 20, 30);
    r3x_scene_set_supersample(s, 2);
    int tex = r3x_texture_checker(128, 8, 250, 120, 30, 20, 60, 200);
    int lit = r3x_material_create(255, 255, 255);
    r3x_material_set_texture(lit, tex);
    r3x_material_set_double_sided(lit, 1);
    int sp = r3x_mesh_sphere(1.5, 48, 24);
    int box = r3x_mesh_box(1, 1, 1);
    int nd = r3x_node_create(s, sp);
    r3x_node_set_material(nd, lit);
    for (int i = 0; i < 20; i++) {
        int k = r3x_node_create(s, box);
        r3x_node_set_material(k, lit);
        r3x_node_set_position(k, (i % 5) - 2, (i / 5) - 1.5, -3);
        r3x_node_set_scale(k, 0.4, 0.4, 0.4);
    }
    CHECK(r3x_scene_is_render_ready(s) == 1, "nothing begun: ready");
    int n = r3x_scene_render(s, 320, 240);
    unsigned char *want = (unsigned char *)malloc((size_t)n);
    memcpy(want, r3x_scene_frame(s), (size_t)n);
    double wantTris = item(r3x_scene_stats(s), 1);
    int same = 1, counted = 1, lengths = 1;
    for (int t = 1; t <= 8; t *= 2) {
        r3x_set_thread_count(t);
        int got = r3x_scene_render_begin(s, 320, 240);
        if (got != n) lengths = 0;
        /* never waits, and is 0 or 1 */
        int r = r3x_scene_is_render_ready(s);
        if (r != 0 && r != 1) lengths = 0;
        const unsigned char *f = r3x_scene_frame(s);          /* waits */
        if (!f || memcmp(want, f, (size_t)n) != 0) { same = 0; printf("begun on %d threads differs\n", t); }
        if (r3x_scene_is_render_ready(s) != 1) lengths = 0;
        if (r3x_scene_frame_length(s) != n) lengths = 0;
        if (item(r3x_scene_stats(s), 1) != wantTris) counted = 0;
    }
    CHECK(same, "a picture begun is the picture drawn at once");
    CHECK(lengths, "begin returns the byte count, and the picture is ready once taken");
    CHECK(counted, "a picture begun counts its triangles");

    /* what changes after the begin belongs to the next picture */
    r3x_scene_render_begin(s, 320, 240);
    r3x_scene_set_background(s, 200, 0, 0);
    r3x_node_set_position(nd, 50, 0, 0);
    CHECK(memcmp(want, r3x_scene_frame(s), (size_t)n) == 0, "a change after the begin is not in that picture");
    r3x_scene_render_begin(s, 320, 240);
    CHECK(is_rgb(px(s, 320, 2, 2), 200, 0, 0, 0), "and is in the next");
    r3x_scene_set_background(s, 10, 20, 30);
    r3x_node_set_position(nd, 0, 0, 0);

    /* a second begin waits for the first; a render does too */
    r3x_scene_render_begin(s, 320, 240);
    r3x_scene_render_begin(s, 160, 120);
    CHECK(r3x_scene_frame_length(s) == 160 * 120 * 4, "the second begin's picture is the one kept");
    r3x_scene_render_begin(s, 160, 120);
    r3x_scene_render(s, 320, 240);
    CHECK(memcmp(want, r3x_scene_frame(s), (size_t)n) == 0, "a render after a begin draws its own picture");

    /* more triangles than the queue holds: the earlier passes are drawn in
     * the call and only the last is left to the background */
    int big = r3x_mesh_sphere(1.5, 256, 128);
    int bn = r3x_node_create(s, big);
    r3x_node_set_material(bn, lit);
    r3x_node_set_position(bn, 0, 0, 2);
    int n2 = r3x_scene_render(s, 320, 240);
    unsigned char *want2 = (unsigned char *)malloc((size_t)n2);
    memcpy(want2, r3x_scene_frame(s), (size_t)n2);
    CHECK(item(r3x_scene_stats(s), 1) > 32768, "more triangles than one queue (%d)", (int)item(r3x_scene_stats(s), 1));
    r3x_scene_render_begin(s, 320, 240);
    CHECK(memcmp(want2, r3x_scene_frame(s), (size_t)n2) == 0, "the same picture over several passes");
    free(want2);

    /* refusals, and a scene with nothing in it */
    CHECK(r3x_scene_render_begin(0, 320, 240) == 0 && r3x_last_error()[0], "begin on no scene refused");
    CHECK(r3x_scene_render_begin(s, 0, 240) == 0 && r3x_last_error()[0], "begin with no width refused");
    CHECK(r3x_scene_is_render_ready(0) == 1 && r3x_scene_is_render_ready(-5) == 1, "no scene: nothing drawing");
    int e = r3x_scene_create();
    CHECK(r3x_scene_render_begin(e, 64, 64) == 64 * 64 * 4 && r3x_scene_frame(e) != NULL, "an empty scene begun");
    r3x_scene_destroy(e);

    /* everything the threads read, destroyed while they draw: each call
     * waits, so this is safe (ASan and TSan run it) */
    r3x_scene_render_begin(s, 320, 240);
    r3x_texture_destroy(tex);
    r3x_scene_render_begin(s, 320, 240);
    r3x_material_destroy(lit);
    r3x_scene_render_begin(s, 320, 240);
    r3x_mesh_destroy(sp);
    r3x_scene_render_begin(s, 320, 240);
    r3x_set_thread_count(3);
    r3x_scene_render_begin(s, 320, 240);
    r3x_scene_destroy(s);
    CHECK(r3x_scene_is_render_ready(s) == 1 && r3x_scene_frame(s) == NULL, "a scene destroyed while drawing");
    r3x_mesh_destroy(box);
    r3x_mesh_destroy(big);
    free(want);
}

static void test_edges_and_clipping(void)
{
    /* a plane of two triangles filling part of the picture exactly: no pixel
     * along the shared diagonal is missed */
    int s = r3x_scene_create();
    r3x_scene_set_camera(s, 0, 10, 0, 0, 0, 0, 90);
    int pl = r3x_mesh_plane(5, 5, 1, 1);
    int m = unlit_material(255, 255, 255);
    int nd = r3x_node_create(s, pl);
    r3x_node_set_material(nd, m);
    r3x_scene_render(s, 64, 64);
    int holes = 0;
    for (int y = 17; y < 47; y++)
        for (int x = 17; x < 47; x++)
            if (!is_rgb(px(s, 64, x, y), 255, 255, 255, 0)) holes++;
    CHECK(holes == 0, "no gaps along the shared edge (%d)", holes);
    /* the camera inside a double-sided box: every triangle crosses or meets
     * the near plane somewhere, and the picture is full */
    int box = r3x_mesh_box(2, 2, 2);
    r3x_node_set_mesh(nd, box);
    r3x_material_set_double_sided(m, 1);
    r3x_scene_set_camera(s, 0.3, 0.2, 0.1, 5, 1, -3, 100);
    r3x_scene_render(s, 64, 64);
    int bg = 0;
    for (int y = 0; y < 64; y++)
        for (int x = 0; x < 64; x++)
            if (is_rgb(px(s, 64, x, y), 31, 33, 41, 0)) bg++;
    CHECK(bg == 0, "inside a box, every pixel is a wall (%d background)", bg);
    /* a triangle crossing the near plane and reaching far behind the eye */
    r3x_material_set_double_sided(m, 0);
    int big = r3x_mesh_from_triangles_text("-1000,-1,1000, 1000,-1,1000, 0,-1,-1000\n");
    r3x_node_set_mesh(nd, big);
    r3x_scene_set_camera(s, 0, 0, 0, 0, 0, -1, 60);
    r3x_scene_render(s, 64, 64);
    CHECK(is_rgb(px(s, 64, 32, 60), 255, 255, 255, 0) && is_rgb(px(s, 64, 32, 10), 31, 33, 41, 0),
          "a floor clipped at the near plane");
    /* coordinates far off the picture still draw only what is on it */
    r3x_node_set_scale(nd, 10000, 1, 10000);
    r3x_scene_render(s, 64, 64);
    CHECK(is_rgb(px(s, 64, 32, 60), 255, 255, 255, 0), "huge floor");
    r3x_scene_destroy(s);
    r3x_mesh_destroy(pl);
    r3x_mesh_destroy(box);
    r3x_mesh_destroy(big);
    r3x_material_destroy(m);
}

static void test_stale_handles(void)
{
    /* every getter on handle 0 and on a dead handle answers 0 or empty */
    int handles[2] = { 0, 0 };
    int s = r3x_scene_create(), mesh = r3x_mesh_box(1, 1, 1), mat = r3x_material_create(1, 2, 3);
    int tex = r3x_texture_checker(8, 2, 0, 0, 0, 1, 1, 1);
    int nd = r3x_node_create(s, mesh), L = r3x_light_create_point(s, 0, 0, 0, 1, 1, 1, 1, 0);
    r3x_node_destroy(nd); r3x_light_destroy(L); r3x_texture_destroy(tex);
    r3x_material_destroy(mat); r3x_mesh_destroy(mesh); r3x_scene_destroy(s);
    handles[1] = s;
    for (int i = 0; i < 2; i++) {
        int h = handles[i];
        CHECK(r3x_scene_background(h)[0] == 0 && r3x_scene_ambient(h)[0] == 0 && r3x_scene_camera(h)[0] == 0 &&
              r3x_scene_clip(h)[0] == 0 && r3x_scene_stats(h)[0] == 0 && r3x_scene_frame(h) == NULL &&
              r3x_scene_frame_length(h) == 0 && r3x_scene_supersample(h) == 0 && r3x_scene_node_count(h) == 0 &&
              r3x_scene_light_count(h) == 0 && r3x_scene_node_by_tag(h, 1) == 0 && r3x_scene_render(h, 4, 4) == 0,
              "stale scene");
        r3x_scene_set_fog(h, 0, 0, 0, 0, 0);
        r3x_scene_set_supersample(h, 2);
        r3x_scene_set_clip(h, 1, 2);
        r3x_scene_set_camera(h, 0, 0, 1, 0, 0, 0, 50);
        r3x_scene_set_camera_text(h, "0,0,1,0,0,0,50");
        r3x_scene_set_background(h, 0, 0, 0);
        r3x_scene_set_ambient(h, 0, 0, 0);
        CHECK(r3x_scene_pick(h, 4, 4, 1, 1) == 0 && r3x_scene_ray_cast(h, 0, 0, 0, 0, 0, 1) == 0 &&
              r3x_scene_ray(h, 4, 4, 1, 1)[0] == 0 && r3x_scene_node(h, 1) == 0 && r3x_scene_light(h, 1) == 0,
              "stale scene queries");
        CHECK(r3x_node_create(h, 0) == 0, "no node in a stale scene");
        r3x_node_set_visible(nd, 1); r3x_node_set_tag(nd, 1); r3x_node_set_scale(nd, 1, 1, 1);
        r3x_node_set_position(nd, 0, 0, 0); r3x_node_set_rotation(nd, 0, 0, 0, 1);
        r3x_node_set_transform(nd, 0, 0, 0, 0, 0, 0, 1); r3x_node_set_transform_text(nd, "0,0,0,0,0,0,1");
        r3x_node_set_mesh(nd, 0); r3x_node_set_material(nd, 0);
        CHECK(r3x_node_is_valid(nd) == 0 && r3x_node_tag(nd) == 0 && r3x_node_is_visible(nd) == 0 &&
              r3x_node_transform(nd)[0] == 0 && r3x_node_position(nd)[0] == 0 && r3x_node_rotation(nd)[0] == 0 &&
              r3x_node_scale(nd)[0] == 0 && r3x_node_scene(nd) == 0 && r3x_node_mesh(nd) == 0 &&
              r3x_node_material(nd) == 0, "stale node");
        r3x_light_set_color(L, 1, 1, 1, 1); r3x_light_set_position(L, 0, 0, 0);
        r3x_light_set_direction(L, 0, -1, 0); r3x_light_set_enabled(L, 1);
        CHECK(r3x_light_is_enabled(L) == 0 && r3x_light_kind(L) == 0 && r3x_light_color(L)[0] == 0 &&
              r3x_light_vector(L)[0] == 0, "stale light");
        r3x_material_set_color(mat, 1, 1, 1); r3x_material_set_texture(mat, 0); r3x_material_set_unlit(mat, 1);
        r3x_material_set_flat(mat, 1); r3x_material_set_cutout(mat, 1); r3x_material_set_double_sided(mat, 1);
        r3x_material_set_specular(mat, 1, 2); r3x_material_set_emissive(mat, 1, 1, 1);
        CHECK(r3x_material_color(mat)[0] == 0 && r3x_material_specular(mat)[0] == 0 && r3x_material_texture(mat) == 0 &&
              r3x_material_is_unlit(mat) == 0 && r3x_material_is_flat(mat) == 0 && r3x_material_is_cutout(mat) == 0 &&
              r3x_material_is_double_sided(mat) == 0, "stale material");
        r3x_texture_set_smooth(tex, 1); r3x_texture_set_repeat(tex, 1);
        CHECK(r3x_texture_is_smooth(tex) == 0 && r3x_texture_is_repeat(tex) == 0 && r3x_texture_height(tex) == 0,
              "stale texture");
        CHECK(r3x_mesh_triangle_count(mesh) == 0 && r3x_mesh_slot_name(mesh, 1)[0] == 0 &&
              r3x_mesh_slot_texture_name(mesh, 1)[0] == 0 && r3x_mesh_add_triangle(mesh, 1, 1, 1, 1) == 0,
              "stale mesh");
        r3x_texture_destroy(tex); r3x_material_destroy(mat); r3x_light_destroy(L);
        r3x_mesh_destroy(mesh); r3x_node_destroy(nd);
        nd = 0; L = 0; tex = 0; mat = 0; mesh = 0;
    }
    /* churn: a slot reused 3000 times never brings an old handle back */
    int first = r3x_material_create(0, 0, 0);
    r3x_material_destroy(first);
    int alive_again = 0;
    for (int i = 0; i < 3000; i++) {
        int h = r3x_material_create(0, 0, 0);
        if (r3x_material_is_valid(first)) alive_again = 1;
        r3x_material_destroy(h);
    }
    CHECK(!alive_again, "a dead handle stays dead through 3000 reuses");
}

static void test_speed(void)
{
    /* not a pass/fail line (machines differ): the number, for the log */
    int s = r3x_scene_create();
    r3x_scene_set_camera(s, 0, 3, 9, 0, 0, 0, 50);
    int tex = r3x_texture_checker(256, 16, 230, 230, 230, 40, 90, 160);
    int m = r3x_material_create(255, 255, 255);
    r3x_material_set_texture(m, tex);
    r3x_material_set_specular(m, 0.4, 32);
    int sp = r3x_mesh_sphere(0.5, 32, 16);
    for (int i = 0; i < 100; i++) {
        int nd = r3x_node_create(s, sp);
        r3x_node_set_material(nd, m);
        r3x_node_set_position(nd, (i % 10) - 4.5, 0, -(i / 10) + 2);
    }
    r3x_set_thread_count(1);
    r3x_scene_render(s, 640, 480);
    double one = item(r3x_scene_stats(s), 3);
    r3x_set_thread_count(8);
    r3x_scene_render(s, 640, 480);
    double eight = item(r3x_scene_stats(s), 3);
    printf("speed: 640x480, %d triangles: %.2f ms on 1 thread, %.2f ms on %d\n",
           (int)item(r3x_scene_stats(s), 1), one, eight, r3x_thread_count());
    CHECK(one > 0 && eight > 0, "timed");
    r3x_scene_destroy(s);
    r3x_mesh_destroy(sp);
    r3x_material_destroy(m);
    r3x_texture_destroy(tex);
}

int main(void)
{
    const char *before;
    if (!assets_write()) {
        printf("FAIL no folder to put the test's model and picture files in\n");
        printf("smoke: 0 checks, 1 failed\n");
        return 1;
    }
    test_library();
    char base[128];
    snprintf(base, sizeof base, "%s", r3x_live_counts());
    test_scene_defaults();
    test_camera_contract();
    test_draw_and_depth();
    test_transforms_and_moves();
    test_textures();
    test_texture_paths();
    test_obj();
    test_meshes();
    test_lighting();
    test_fog_supersample_threads();
    test_background();
    test_edges_and_clipping();
    test_stale_handles();
    test_speed();
    before = r3x_live_counts();
    CHECK(strcmp(before, base) == 0, "nothing leaked: %s, was %s", before, base);
    assets_remove();
    printf("smoke: %d checks, %d failed\n", g_checks, g_failed);
    return g_failed ? 1 : 0;
}
