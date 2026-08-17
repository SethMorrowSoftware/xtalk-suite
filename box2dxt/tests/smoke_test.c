/*
 * smoke_test.c — runtime smoke test for the box2dxt shim.
 *
 * Links directly against the box2dxt shared library and drives the real Box2D
 * engine through the same C entry points the xTalk Builder (LCB) binding calls.
 * This proves the engine actually simulates (gravity, collision, sleeping,
 * joints, queries, contact events) and that the handle-validity guards make
 * stale handles harmless — none of which a compile check alone can show.
 *
 * Enable with -DBOX2DXT_BUILD_TESTS=ON, then run `ctest` (or run the binary).
 */
#include <stdio.h>
#include <math.h>

/* ---- shim entry points (must match box2d_lc.c signatures) ---- */
extern int    b2lc_abi_version(void);
extern int    b2lc_world_create(double, double, int, int);
extern int    b2lc_world_create_threaded(double, double, int, int, int);
extern int    b2lc_world_thread_count(int);
extern void   b2lc_world_destroy(int);
extern void   b2lc_world_step(int, double, int);
extern int    b2lc_body_create(int, int, double, double, double, int, int);
extern void   b2lc_body_destroy(int);
extern void   b2lc_shape_destroy(int);
extern double b2lc_body_x(int);
extern double b2lc_body_y(int);
extern void   b2lc_body_set_transform(int, double, double, double);
extern double b2lc_body_mass(int);
extern int    b2lc_body_is_awake(int);
extern int    b2lc_body_at_point(int, double, double);
extern int    b2lc_shape_add_box(int, double, double, double, double, double);
extern int    b2lc_shape_add_capsule(int, double, double, double, double, double, double, double, double);
extern int    b2lc_shape_add_segment(int, double, double, double, double, double, double);
extern int    b2lc_joint_revolute(int, int, int, double, double, double, double, int);
extern int    b2lc_joint_distance(int, int, int, double, double, double, double, double, int);
extern int    b2lc_joint_weld(int, int, int, double, double, double, double, double, int);
extern int    b2lc_joint_prismatic(int, int, int, double, double, double, double, double, double, double, int);
extern int    b2lc_joint_wheel(int, int, int, double, double, double, double, double, double, int);
extern int    b2lc_joint_mouse(int, int, int, double, double, double, double, double);
extern void   b2lc_mouse_set_target(int, double, double);
extern int    b2lc_cast_ray_closest(int, double, double, double, double);
extern int    b2lc_ray_body(void);
extern double b2lc_ray_y(void);
extern int    b2lc_contacts_update(int);
extern int    b2lc_contact_begin_count(void);
extern int    b2lc_contact_begin_a(int);
extern int    b2lc_contact_begin_b(int);

/* ---- ABI v3 entry points exercised below ---- */
extern void   b2lc_shapedef_set_sensor(int);
extern void   b2lc_shapedef_set_enable_sensor_events(int);
extern void   b2lc_shapedef_set_filter(double, double, int);
extern int    b2lc_sensors_update(int);
extern int    b2lc_sensor_begin_count(void);
extern int    b2lc_sensor_begin_sensor(int);
extern int    b2lc_sensor_begin_visitor(int);
extern int    b2lc_joint_motor(int, int, int, double, double, double, double, double, double, int);
extern int    b2lc_query_raycast_all(int, double, double, double, double);
extern int    b2lc_query_count(void);
extern int    b2lc_query_body(int);
extern double b2lc_query_fraction(int);
extern void   b2lc_world_explode(int, double, double, double, double, double);
extern int    b2lc_bodies_update(int);
extern int    b2lc_body_move_count(void);
extern int    b2lc_body_move_body(int);
extern double b2lc_body_move_y(int);
extern void   b2lc_body_mass_data_update(int);
extern double b2lc_md_mass(void);
extern void   b2lc_body_set_mass_data(int, double, double, double, double);
extern void   b2lc_body_apply_mass_from_shapes(int);
extern void   b2lc_chain_begin(void);
extern void   b2lc_chain_add_point(double, double);
extern int    b2lc_chain_create(int, int, double, double);
extern int    b2lc_chain_segment_count(int);
extern int    b2lc_chain_segment_at(int);
extern int    b2lc_shape_add_circle(int, double, double, double, double, double, double);
extern double b2lc_body_vx(int);

/* ---- the body + shape accessor sweep (see the block in main) ----
   These declarations are GENERATED from the LC_API definitions in
   src/box2d_lc.c rather than typed out: a hand-written extern that
   disagrees with the definition is undefined behaviour the linker will
   not catch, and there are 134 of them here. tools/check-lcb-signatures.py
   holds the .lcb's foreign declarations to the same definitions. */
extern double b2lc_aabb_lower_x(void);
extern double b2lc_aabb_lower_y(void);
extern double b2lc_aabb_upper_x(void);
extern double b2lc_aabb_upper_y(void);
extern void   b2lc_body_aabb_update(int);
extern double b2lc_body_angle(int);
extern double b2lc_body_angular_damping(int);
extern void   b2lc_body_apply_angular_impulse(int, double, int);
extern void   b2lc_body_apply_force(int, double, double, int);
extern void   b2lc_body_apply_force_at(int, double, double, double, double, int);
extern void   b2lc_body_apply_impulse(int, double, double, int);
extern void   b2lc_body_apply_impulse_at(int, double, double, double, double, int);
extern void   b2lc_body_apply_torque(int, double, int);
extern void   b2lc_body_disable(int);
extern void   b2lc_body_enable(int);
extern void   b2lc_body_enable_contact_events(int, int);
extern void   b2lc_body_enable_hit_events(int, int);
extern void   b2lc_body_enable_sleep(int, int);
extern double b2lc_body_gravity_scale(int);
extern int    b2lc_body_is_bullet(int);
extern int    b2lc_body_is_enabled(int);
extern int    b2lc_body_is_fixed_rotation(int);
extern int    b2lc_body_is_sleep_enabled(int);
extern int    b2lc_body_joint_at(int);
extern int    b2lc_body_joint_count(int);
extern double b2lc_body_linear_damping(int);
extern double b2lc_body_local_center_x(int);
extern double b2lc_body_local_center_y(int);
extern double b2lc_body_local_point_velocity_x(int, double, double);
extern double b2lc_body_local_point_velocity_y(int, double, double);
extern double b2lc_body_local_point_x(int, double, double);
extern double b2lc_body_local_point_y(int, double, double);
extern double b2lc_body_local_vector_x(int, double, double);
extern double b2lc_body_local_vector_y(int, double, double);
extern double b2lc_body_move_angle(int);
extern int    b2lc_body_move_asleep(int);
extern double b2lc_body_move_x(int);
extern double b2lc_body_omega(int);
extern double b2lc_body_rotational_inertia(int);
extern void   b2lc_body_set_angular_damping(int, double);
extern void   b2lc_body_set_angular_velocity(int, double);
extern void   b2lc_body_set_awake(int, int);
extern void   b2lc_body_set_bullet(int, int);
extern void   b2lc_body_set_fixed_rotation(int, int);
extern void   b2lc_body_set_gravity_scale(int, double);
extern void   b2lc_body_set_linear_damping(int, double);
extern void   b2lc_body_set_sleep_threshold(int, double);
extern void   b2lc_body_set_target_transform(int, double, double, double, double);
extern void   b2lc_body_set_type(int, int);
extern void   b2lc_body_set_velocity(int, double, double);
extern int    b2lc_body_shape_at(int);
extern int    b2lc_body_shape_count(int);
extern int    b2lc_body_type(int);
extern double b2lc_body_vy(int);
extern double b2lc_body_world_center_x(int);
extern double b2lc_body_world_center_y(int);
extern double b2lc_body_world_point_velocity_x(int, double, double);
extern double b2lc_body_world_point_velocity_y(int, double, double);
extern double b2lc_body_world_point_x(int, double, double);
extern double b2lc_body_world_point_y(int, double, double);
extern double b2lc_body_world_vector_x(int, double, double);
extern double b2lc_body_world_vector_y(int, double, double);
extern double b2lc_md_center_x(void);
extern double b2lc_md_center_y(void);
extern double b2lc_md_inertia(void);
extern void   b2lc_poly_add(double, double);
extern void   b2lc_poly_begin(void);
extern void   b2lc_shape_aabb_update(int);
extern int    b2lc_shape_add_polygon(int, double, double, double);
extern int    b2lc_shape_are_contact_events_enabled(int);
extern int    b2lc_shape_are_hit_events_enabled(int);
extern int    b2lc_shape_are_sensor_events_enabled(int);
extern int    b2lc_shape_body(int);
extern double b2lc_shape_capsule_radius(void);
extern void   b2lc_shape_capsule_update(int);
extern double b2lc_shape_capsule_x1(void);
extern double b2lc_shape_capsule_x2(void);
extern double b2lc_shape_capsule_y1(void);
extern double b2lc_shape_capsule_y2(void);
extern double b2lc_shape_circle_radius(void);
extern void   b2lc_shape_circle_update(int);
extern double b2lc_shape_circle_x(void);
extern double b2lc_shape_circle_y(void);
extern double b2lc_shape_closest_point_x(int, double, double);
extern double b2lc_shape_closest_point_y(int, double, double);
extern double b2lc_shape_density(int);
extern void   b2lc_shape_enable_contact_events(int, int);
extern void   b2lc_shape_enable_hit_events(int, int);
extern void   b2lc_shape_enable_presolve_events(int, int);
extern void   b2lc_shape_enable_sensor_events(int, int);
extern double b2lc_shape_filter_category(int);
extern int    b2lc_shape_filter_group(int);
extern double b2lc_shape_filter_mask(int);
extern double b2lc_shape_friction(int);
extern int    b2lc_shape_is_sensor(int);
extern void   b2lc_shape_mass_data_update(int);
extern int    b2lc_shape_material_id(int);
extern int    b2lc_shape_polygon_count(void);
extern double b2lc_shape_polygon_radius(void);
extern int    b2lc_shape_polygon_update(int);
extern double b2lc_shape_polygon_vx(int);
extern double b2lc_shape_polygon_vy(int);
extern double b2lc_shape_ray_fraction(void);
extern double b2lc_shape_ray_normal_x(void);
extern double b2lc_shape_ray_normal_y(void);
extern double b2lc_shape_ray_x(void);
extern double b2lc_shape_ray_y(void);
extern int    b2lc_shape_raycast(int, double, double, double, double);
extern double b2lc_shape_restitution(int);
extern void   b2lc_shape_segment_update(int);
extern double b2lc_shape_segment_x1(void);
extern double b2lc_shape_segment_x2(void);
extern double b2lc_shape_segment_y1(void);
extern double b2lc_shape_segment_y2(void);
extern int    b2lc_shape_sensor_capacity(int);
extern int    b2lc_shape_sensor_overlap_at(int);
extern int    b2lc_shape_sensor_overlap_count(void);
extern int    b2lc_shape_sensor_overlaps_update(int);
extern void   b2lc_shape_set_capsule(int, double, double, double, double, double);
extern void   b2lc_shape_set_circle(int, double, double, double);
extern void   b2lc_shape_set_density(int, double);
extern void   b2lc_shape_set_filter(int, double, double, int);
extern void   b2lc_shape_set_friction(int, double);
extern void   b2lc_shape_set_material_id(int, int);
extern void   b2lc_shape_set_polygon(int);
extern void   b2lc_shape_set_restitution(int, double);
extern void   b2lc_shape_set_segment(int, double, double, double, double);
extern int    b2lc_shape_test_point(int, double, double);
extern int    b2lc_shape_type(int);
extern void   b2lc_shapedef_reset(void);
extern void   b2lc_shapedef_set_enable_contact_events(int);
extern void   b2lc_shapedef_set_enable_hit_events(int);
extern void   b2lc_shapedef_set_enable_presolve_events(int);
extern void   b2lc_shapedef_set_material_id(int);

static int g_pass = 0, g_fail = 0;
static void check(const char *name, int ok) {
    printf("  [%s] %s\n", ok ? "PASS" : "FAIL", name);
    if (ok) g_pass++; else g_fail++;
}

int main(void) {
    printf("box2dxt ABI version = %d\n", b2lc_abi_version());
    check("ABI version is 4", b2lc_abi_version() == 4);

    /* Threaded world: exercise the optional native task pool end-to-end. Creating
       it spawns worker threads; stepping a POPULATED world drives enqueueTask/
       finishTask so the workers actually run solver tasks -- each on its own fixed,
       collision-free worker index -- and finishTask must synchronise before the
       getters below read back. A clean fall+settle (finite, no tunneling) means the
       pool simulates like the single-threaded path and tears down without deadlock.
       Worker count clamps to online CPUs, so a 1-core host just runs single-threaded;
       the >= 1 assertion and the simulation both hold either way. */
    int tw = b2lc_world_create_threaded(0.0, -10.0, 1, 1, 4);
    check("threaded world creates", tw > 0);
    check("threaded world reports at least one worker", b2lc_world_thread_count(tw) >= 1);
    int tg = b2lc_body_create(tw, 0, 0.0, 0.0, 0.0, 0, 0);
    b2lc_shape_add_segment(tg, -20.0, 0.0, 20.0, 0.0, 0.6, 0.0);
    int tboxes[24];
    for (int i = 0; i < 24; i++) {
        tboxes[i] = b2lc_body_create(tw, 2, -6.0 + 0.5 * i, 5.0 + 0.2 * i, 0.0, 0, 0);
        b2lc_shape_add_box(tboxes[i], 0.25, 0.25, 1.0, 0.6, 0.0);
    }
    double twy0 = b2lc_body_y(tboxes[0]);
    for (int i = 0; i < 120; i++) b2lc_world_step(tw, 1.0 / 60.0, 4);
    double twy1 = b2lc_body_y(tboxes[0]);
    printf("threaded box fell from y=%.3f to y=%.3f\n", twy0, twy1);
    check("threaded step simulates (bodies fell under gravity)", twy1 < twy0 - 1.0);
    check("threaded bodies settled cleanly (no NaN/tunneling)", twy1 > 0.0 && twy1 < 5.0);
    b2lc_world_destroy(tw);   /* joins worker threads; must not hang or crash */

    int w = b2lc_world_create(0.0, -10.0, 1, 1);   /* gravity, sleep + CCD on */
    check("world handle valid", w > 0);

    /* destroy paths are intentionally idempotent at the ABI boundary: stale or
       double-destroyed handles must remain harmless and must not poison future
       handle allocation. */
    int tmp = b2lc_body_create(w, 2, -8.0, 2.0, 0.0, 0, 0);
    int tmpShape = b2lc_shape_add_box(tmp, 0.25, 0.25, 1.0, 0.3, 0.0);
    check("temporary body+shape created", tmp > 0 && tmpShape > 0);
    b2lc_body_destroy(tmp);
    b2lc_body_destroy(tmp);
    b2lc_shape_destroy(tmpShape);
    check("destroyed body getter is harmless", fabs(b2lc_body_y(tmp)) < 0.0001);
    int tmp2 = b2lc_body_create(w, 2, -7.0, 2.0, 0.0, 0, 0);
    check("handle allocation still works after double destroy", tmp2 > 0);
    /* generation check: tmp2 recycles tmp's table slot, but the stale handle
       must stay dead instead of aliasing the new body (handles carry a
       generation tag precisely so reuse cannot resurrect old references). */
    check("recycled slot does not resurrect the stale handle",
          tmp != tmp2 && fabs(b2lc_body_x(tmp)) < 0.0001 && fabs(b2lc_body_x(tmp2) - (-7.0)) < 0.0001);
    b2lc_body_set_transform(tmp, 5.0, 5.0, 0.0);   /* must no-op, not move tmp2 */
    check("setter on stale handle cannot touch the slot's new owner",
          fabs(b2lc_body_x(tmp2) - (-7.0)) < 0.0001);
    b2lc_body_destroy(tmp2);

    /* ground: a flat segment at y=0 spanning x=[-10,10] (tests b2AddSegment) */
    int ground = b2lc_body_create(w, 0, 0.0, 0.0, 0.0, 0, 0);
    b2lc_shape_add_segment(ground, -10.0, 0.0, 10.0, 0.0, 0.6, 0.0);
    check("ground body valid", ground > 0);

    /* a dynamic box dropped from y=5 */
    int box = b2lc_body_create(w, 2, 0.0, 5.0, 0.0, 0, 0);
    b2lc_shape_add_box(box, 0.5, 0.5, 1.0, 0.6, 0.0);
    check("box body valid", box > 0);
    check("box mass is ~1.0 (density*area)", fabs(b2lc_body_mass(box) - 1.0) < 0.05);

    /* a capsule body, just to exercise capsule creation */
    int cap = b2lc_body_create(w, 2, 4.0, 5.0, 0.0, 0, 0);
    check("capsule shape created", b2lc_shape_add_capsule(cap, -0.4, 0.0, 0.4, 0.0, 0.25, 1.0, 0.5, 0.0) > 0);

    double y0 = b2lc_body_y(box);
    int sawContact = 0;
    for (int i = 0; i < 120; i++) {                /* 2 seconds */
        b2lc_world_step(w, 1.0 / 60.0, 4);
        int n = b2lc_contacts_update(w);
        for (int k = 0; k < n; k++) {
            int a = b2lc_contact_begin_a(k), b = b2lc_contact_begin_b(k);
            if ((a == box && b == ground) || (a == ground && b == box)) sawContact = 1;
        }
    }
    double y1 = b2lc_body_y(box);
    printf("box fell from y=%.3f to y=%.3f\n", y0, y1);
    check("box fell under gravity", y1 < y0 - 1.0);
    check("box settled on ground (~0.5, not through it)", fabs(y1 - 0.5) < 0.15);
    check("begin-touch contact event reported box<->ground", sawContact == 1);
    check("box went to sleep after settling", b2lc_body_is_awake(box) == 0);

    /* ray cast straight down through the box */
    int hit = b2lc_cast_ray_closest(w, 0.0, 5.0, 0.0, -5.0);
    check("ray cast reports a hit", hit == 1);
    check("ray cast returns the box handle", b2lc_ray_body() == box);
    check("ray hit point sits on top of box (~1.0)", fabs(b2lc_ray_y() - 1.0) < 0.2);

    /* point pick */
    check("point pick inside box returns box", b2lc_body_at_point(w, 0.0, 0.5) == box);
    check("point pick in empty space returns 0", b2lc_body_at_point(w, 8.0, 3.0) == 0);

    /* validity guards: stale/destroyed handles must be harmless, not crash */
    int doomed = b2lc_body_create(w, 2, 3.0, 3.0, 0.0, 0, 0);
    b2lc_body_destroy(doomed);
    check("getter on destroyed body returns 0 (no crash)", b2lc_body_x(doomed) == 0.0);
    b2lc_body_destroy(doomed);                     /* double-destroy: must be safe */
    b2lc_body_at_point(w, 999.0, 999.0);           /* nonsense query: safe */
    b2lc_world_step(w, 1.0 / 60.0, 4);
    check("simulation survives use-after-destroy", 1);

    /* revolute pendulum should swing down */
    int anchor = b2lc_body_create(w, 0, -4.0, 4.0, 0.0, 0, 0);
    int bar = b2lc_body_create(w, 2, -3.0, 4.0, 0.0, 0, 0);
    b2lc_shape_add_box(bar, 1.0, 0.15, 1.0, 0.4, 0.1);
    check("revolute joint created", b2lc_joint_revolute(w, anchor, bar, 0.0, 0.0, -1.0, 0.0, 0) > 0);
    double barY0 = b2lc_body_y(bar);
    for (int i = 0; i < 60; i++) b2lc_world_step(w, 1.0 / 60.0, 4);
    check("pendulum swings down under gravity", b2lc_body_y(bar) < barY0);

    /* a distance joint between two free bodies should hold them apart */
    int p = b2lc_body_create(w, 2, -8.0, 8.0, 0.0, 0, 0);
    int q = b2lc_body_create(w, 2, -6.0, 8.0, 0.0, 0, 0);
    b2lc_shape_add_box(p, 0.3, 0.3, 1.0, 0.3, 0.0);
    b2lc_shape_add_box(q, 0.3, 0.3, 1.0, 0.3, 0.0);
    check("distance joint created", b2lc_joint_distance(w, p, q, 0.0, 0.0, 0.0, 0.0, 2.0, 0) > 0);
    check("weld joint created", b2lc_joint_weld(w, p, q, 0.0, 0.0, 0.0, 0.0, 0.0, 0) > 0);
    check("prismatic joint created", b2lc_joint_prismatic(w, p, q, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0) > 0);
    check("wheel joint created", b2lc_joint_wheel(w, p, q, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0) > 0);

    /* mouse joint drags a dynamic body toward a target (anchored to a static body) */
    int anchor2 = b2lc_body_create(w, 0, 0.0, 12.0, 0.0, 0, 0);
    int dragged = b2lc_body_create(w, 2, 0.0, 12.0, 0.0, 0, 0);
    b2lc_shape_add_box(dragged, 0.3, 0.3, 1.0, 0.3, 0.0);
    int mj = b2lc_joint_mouse(w, anchor2, dragged, 0.0, 12.0, 5.0, 0.7, 1000.0);
    check("mouse joint created", mj > 0);
    b2lc_mouse_set_target(mj, 3.0, 12.0);      /* pull right */
    for (int i = 0; i < 30; i++) b2lc_world_step(w, 1.0 / 60.0, 4);
    check("mouse joint pulls body toward target", b2lc_body_x(dragged) > 0.2);

    b2lc_world_destroy(w);
    check("world destroyed cleanly", 1);
    check("world destroy retires child body handles", fabs(b2lc_body_y(box)) < 0.0001);

    /* ================= ABI v3 features (isolated world) ================= */
    int w2 = b2lc_world_create(0.0, -10.0, 1, 1);
    check("v3 world created", w2 > 0);

    /* sensors: a static sensor box; a dynamic circle falls THROUGH it and
       triggers a begin-touch sensor event (events need BOTH shapes enabled). */
    int senBody = b2lc_body_create(w2, 0, 0.0, 0.0, 0.0, 0, 0);
    b2lc_shapedef_set_sensor(1);
    b2lc_shapedef_set_enable_sensor_events(1);
    int sensorShape = b2lc_shape_add_box(senBody, 1.0, 0.2, 0.0, 0.0, 0.0);
    check("sensor shape created", sensorShape > 0);
    int visitor = b2lc_body_create(w2, 2, 0.0, 3.0, 0.0, 0, 0);
    b2lc_shapedef_set_enable_sensor_events(1);
    b2lc_shape_add_circle(visitor, 0.0, 0.0, 0.25, 1.0, 0.0, 0.0);
    int sawSensor = 0;
    for (int i = 0; i < 120; i++) {
        b2lc_world_step(w2, 1.0 / 60.0, 4);
        int sn = b2lc_sensors_update(w2);
        for (int k = 0; k < sn; k++)
            if (b2lc_sensor_begin_sensor(k) == sensorShape && b2lc_sensor_begin_visitor(k) > 0) sawSensor = 1;
    }
    check("sensor begin-touch fires when a body enters the sensor", sawSensor == 1);

    /* collision filtering: two boxes at the same spot with mutually-exclusive
       category/mask never generate a contact between them. */
    int fA = b2lc_body_create(w2, 2, 5.0, 1.0, 0.0, 0, 1);
    b2lc_shapedef_set_filter(1.0, 1.0, 0);
    b2lc_shape_add_box(fA, 0.5, 0.5, 1.0, 0.3, 0.0);
    int fB = b2lc_body_create(w2, 2, 5.0, 1.0, 0.0, 0, 1);
    b2lc_shapedef_set_filter(2.0, 2.0, 0);
    b2lc_shape_add_box(fB, 0.5, 0.5, 1.0, 0.3, 0.0);
    int filteredContact = 0;
    for (int i = 0; i < 60; i++) {
        b2lc_world_step(w2, 1.0 / 60.0, 4);
        int cn = b2lc_contacts_update(w2);
        for (int k = 0; k < cn; k++) {
            int a = b2lc_contact_begin_a(k), bb = b2lc_contact_begin_b(k);
            if ((a == fA && bb == fB) || (a == fB && bb == fA)) filteredContact = 1;
        }
    }
    check("filtered boxes never collide (category/mask)", filteredContact == 0);

    /* chain ground (points ordered right-to-left so the solid side faces up)
       catches a falling box; an open 4-point chain has 3 segments. */
    int chainBody = b2lc_body_create(w2, 0, 0.0, -5.0, 0.0, 0, 0);
    b2lc_chain_begin();
    b2lc_chain_add_point(12.0, 0.0);
    b2lc_chain_add_point(7.0, 0.0);
    b2lc_chain_add_point(3.0, 0.0);
    b2lc_chain_add_point(-3.0, 0.0);
    b2lc_chain_add_point(-7.0, 0.0);
    b2lc_chain_add_point(-12.0, 0.0);
    int chain = b2lc_chain_create(chainBody, 0, 0.8, 0.0);
    check("chain created", chain > 0);
    /* a non-loop chain treats its first & last points as ghost vertices, so an
       n-point open chain yields n-3 collidable segments (6 -> 3). */
    check("open 6-point chain has 3 collidable segments", b2lc_chain_segment_count(chain) == 3);
    check("chain segment exposes a shape handle", b2lc_chain_segment_at(0) > 0);
    int chainBox = b2lc_body_create(w2, 2, 0.0, -2.0, 0.0, 0, 0);
    b2lc_shape_add_box(chainBox, 0.5, 0.5, 1.0, 0.5, 0.0);
    for (int i = 0; i < 180; i++) b2lc_world_step(w2, 1.0 / 60.0, 4);
    check("box dropped on a chain doesn't fall through", b2lc_body_y(chainBox) > -6.0);

    /* motor joint drives a dynamic body toward a linear offset from an anchor */
    int mAnchor = b2lc_body_create(w2, 0, -20.0, 0.0, 0.0, 0, 0);
    int mBody = b2lc_body_create(w2, 2, -20.0, 0.0, 0.0, 0, 1);
    b2lc_shape_add_box(mBody, 0.3, 0.3, 1.0, 0.3, 0.0);
    int motor = b2lc_joint_motor(w2, mAnchor, mBody, 3.0, 0.0, 0.0, 10000.0, 10000.0, 0.3, 0);
    check("motor joint created", motor > 0);
    double mx0 = b2lc_body_x(mBody);
    for (int i = 0; i < 120; i++) b2lc_world_step(w2, 1.0 / 60.0, 4);
    check("motor joint moved body toward its linear offset", b2lc_body_x(mBody) > mx0 + 1.0);

    /* ray-cast-all returns every shape along the ray, sorted near->far */
    int rc1 = b2lc_body_create(w2, 0, 30.0, 1.0, 0.0, 0, 0); b2lc_shape_add_box(rc1, 0.5, 0.5, 0.0, 0.0, 0.0);
    int rc2 = b2lc_body_create(w2, 0, 30.0, 3.0, 0.0, 0, 0); b2lc_shape_add_box(rc2, 0.5, 0.5, 0.0, 0.0, 0.0);
    int rc3 = b2lc_body_create(w2, 0, 30.0, 5.0, 0.0, 0, 0); b2lc_shape_add_box(rc3, 0.5, 0.5, 0.0, 0.0, 0.0);
    int nhits = b2lc_query_raycast_all(w2, 30.0, -1.0, 30.0, 7.0);
    check("ray-cast-all hit all three stacked boxes", nhits == 3);
    int sorted = 1;
    for (int k = 1; k < nhits; k++) if (b2lc_query_fraction(k) < b2lc_query_fraction(k - 1)) sorted = 0;
    check("ray-cast-all hits are sorted by fraction", sorted == 1);

    /* native explosion scatters nearby dynamic bodies outward */
    int ex1 = b2lc_body_create(w2, 2, 49.0, 0.0, 0.0, 0, 0); b2lc_shape_add_circle(ex1, 0, 0, 0.3, 1.0, 0.3, 0.0);
    int ex2 = b2lc_body_create(w2, 2, 51.0, 0.0, 0.0, 0, 0); b2lc_shape_add_circle(ex2, 0, 0, 0.3, 1.0, 0.3, 0.0);
    b2lc_world_explode(w2, 50.0, 0.0, 5.0, 1.0, 20.0);
    double ex1x0 = b2lc_body_x(ex1), ex2x0 = b2lc_body_x(ex2);
    for (int i = 0; i < 10; i++) b2lc_world_step(w2, 1.0 / 60.0, 4);
    check("explosion pushes the left body further left",  b2lc_body_x(ex1) < ex1x0);
    check("explosion pushes the right body further right", b2lc_body_x(ex2) > ex2x0);

    /* body-move events report the bodies that moved this step */
    int mv = b2lc_body_create(w2, 2, 70.0, 10.0, 0.0, 0, 0);
    b2lc_shape_add_box(mv, 0.5, 0.5, 1.0, 0.3, 0.0);
    b2lc_world_step(w2, 1.0 / 60.0, 4);
    int mvcount = b2lc_bodies_update(w2);
    int sawMove = 0;
    for (int k = 0; k < mvcount; k++) if (b2lc_body_move_body(k) == mv) sawMove = 1;
    check("body-move events report a falling body", sawMove == 1);

    /* mass data: read computed, set explicit, then recompute from shapes */
    int massBody = b2lc_body_create(w2, 2, 80.0, 0.0, 0.0, 0, 0);
    b2lc_shape_add_box(massBody, 0.5, 0.5, 1.0, 0.3, 0.0);
    b2lc_body_mass_data_update(massBody);
    check("mass-data update reads ~1kg", fabs(b2lc_md_mass() - 1.0) < 0.05);
    b2lc_body_set_mass_data(massBody, 5.0, 0.0, 0.0, 1.0);
    b2lc_body_mass_data_update(massBody);
    check("set-mass-data sticks", fabs(b2lc_md_mass() - 5.0) < 0.01);
    b2lc_body_apply_mass_from_shapes(massBody);
    b2lc_body_mass_data_update(massBody);
    check("apply-mass-from-shapes restores computed mass", fabs(b2lc_md_mass() - 1.0) < 0.05);

    b2lc_world_destroy(w2);
    check("v3 world destroyed cleanly", 1);


    /* ============ the body + shape accessor sweep (isolated world) ============
       Added 2026-08-17. Everything above this line is BEHAVIOUR: it drives the
       engine and asserts what the physics did. This block is a COVERAGE sweep of
       the shim's two biggest exported surfaces -- every b2lc_body_* and
       b2lc_shape_* entry point, plus the four readback registers they fill (the
       AABB stash, the mass-data stash, the polygon point builder and the one-shot
       shape def).

       Why it exists: 60 of the shim's 370 LC_API exports had ever been executed,
       and the recorded reason for leaving this layer alone is about SCRIPT
       assertions "with no engine to run them on" -- which does not transfer to a
       C harness that compiles and runs in the build. An unexecuted export is not
       evidence, in either direction (root CLAUDE.md, "shipped is not run"), and
       here there was nothing scarce standing in the way.

       These assertions are deliberately SHALLOW next to the behaviour tests
       above: what each one holds is "this export links, takes these arguments,
       and reports the documented shape". Every getter is checked against a value
       this test WROTE, never against a default the engine happens to hand back --
       a getter asserted against a default passes just as well when it is wired to
       the wrong field. An export that earns a real lesson should GRADUATE up into
       a behaviour section of its own. */
    int w3 = b2lc_world_create(0.0, -10.0, 1, 1);
    check("accessor-sweep world created", w3 > 0);

    /* --- body: type and the boolean flag pairs ------------------------------ */
    int ab = b2lc_body_create(w3, 2, 1.0, 2.0, 0.5, 0, 0);
    int as = b2lc_shape_add_box(ab, 0.5, 0.5, 1.0, 0.3, 0.1);
    check("sweep body + box shape created", ab > 0 && as > 0);
    check("body_type reports dynamic", b2lc_body_type(ab) == 2);
    check("body_angle reads back the creation angle", fabs(b2lc_body_angle(ab) - 0.5) < 1e-4);
    b2lc_body_set_type(ab, 1);
    check("body_set_type switches to kinematic", b2lc_body_type(ab) == 1);
    b2lc_body_set_type(ab, 2);
    check("body_set_type switches back to dynamic", b2lc_body_type(ab) == 2);
    b2lc_body_set_bullet(ab, 1);
    check("body_is_bullet sees set_bullet(1)", b2lc_body_is_bullet(ab) == 1);
    b2lc_body_set_bullet(ab, 0);
    check("body_is_bullet sees set_bullet(0)", b2lc_body_is_bullet(ab) == 0);
    b2lc_body_set_fixed_rotation(ab, 1);
    check("body_is_fixed_rotation sees set_fixed_rotation(1)", b2lc_body_is_fixed_rotation(ab) == 1);
    b2lc_body_set_fixed_rotation(ab, 0);
    check("body_is_fixed_rotation sees set_fixed_rotation(0)", b2lc_body_is_fixed_rotation(ab) == 0);
    b2lc_body_enable_sleep(ab, 0);
    check("body_is_sleep_enabled sees enable_sleep(0)", b2lc_body_is_sleep_enabled(ab) == 0);
    b2lc_body_enable_sleep(ab, 1);
    check("body_is_sleep_enabled sees enable_sleep(1)", b2lc_body_is_sleep_enabled(ab) == 1);
    b2lc_body_disable(ab);
    check("body_is_enabled sees body_disable", b2lc_body_is_enabled(ab) == 0);
    b2lc_body_enable(ab);
    check("body_is_enabled sees body_enable", b2lc_body_is_enabled(ab) == 1);

    /* --- body: damping, gravity scale, sleep threshold ---------------------- */
    b2lc_body_set_linear_damping(ab, 0.25);
    check("linear damping round-trips", fabs(b2lc_body_linear_damping(ab) - 0.25) < 1e-5);
    b2lc_body_set_angular_damping(ab, 0.75);
    check("angular damping round-trips", fabs(b2lc_body_angular_damping(ab) - 0.75) < 1e-5);
    b2lc_body_set_gravity_scale(ab, 0.5);
    check("gravity scale round-trips", fabs(b2lc_body_gravity_scale(ab) - 0.5) < 1e-5);
    b2lc_body_set_linear_damping(ab, 0.0);
    b2lc_body_set_angular_damping(ab, 0.0);
    b2lc_body_set_gravity_scale(ab, 1.0);
    /* the sleep threshold has no exported getter; what is assertable from out
       here is that the write is accepted and leaves the body simulating */
    b2lc_body_set_sleep_threshold(ab, 0.01);
    check("sleep-threshold write leaves the body valid", b2lc_body_type(ab) == 2);

    /* --- body: velocity, spin, and the whole force/impulse family ----------- */
    b2lc_body_set_velocity(ab, 3.0, -4.0);
    check("body_vx/vy read back set_velocity",
          fabs(b2lc_body_vx(ab) - 3.0) < 1e-5 && fabs(b2lc_body_vy(ab) + 4.0) < 1e-5);
    b2lc_body_set_angular_velocity(ab, 2.0);
    check("body_omega reads back set_angular_velocity", fabs(b2lc_body_omega(ab) - 2.0) < 1e-5);
    b2lc_body_set_velocity(ab, 0.0, 0.0);
    b2lc_body_set_angular_velocity(ab, 0.0);
    /* the box is 1x1 at density 1, so mass is 1 and an impulse of 2 is a dv of 2 */
    b2lc_body_apply_impulse(ab, 2.0, 0.0, 1);
    check("apply_impulse changes velocity by impulse/mass", fabs(b2lc_body_vx(ab) - 2.0) < 0.05);
    b2lc_body_set_velocity(ab, 0.0, 0.0);
    b2lc_body_set_angular_velocity(ab, 0.0);
    b2lc_body_apply_angular_impulse(ab, 0.1, 1);
    check("apply_angular_impulse spins the body", b2lc_body_omega(ab) > 0.0);
    b2lc_body_set_angular_velocity(ab, 0.0);
    b2lc_body_apply_torque(ab, 5.0, 1);
    b2lc_world_step(w3, 1.0 / 60.0, 4);
    check("apply_torque spins the body over a step", b2lc_body_omega(ab) > 0.0);
    b2lc_body_set_velocity(ab, 0.0, 0.0);
    b2lc_body_set_angular_velocity(ab, 0.0);
    /* 60N on a 1kg body for 1/60s is a dv of 1 (gravity only touches vy) */
    b2lc_body_apply_force(ab, 60.0, 0.0, 1);
    b2lc_world_step(w3, 1.0 / 60.0, 4);
    check("apply_force accelerates the body", fabs(b2lc_body_vx(ab) - 1.0) < 0.05);
    b2lc_body_set_velocity(ab, 0.0, 0.0);
    b2lc_body_set_angular_velocity(ab, 0.0);
    /* the *_at forms take a world application point: off the centre of mass they
       must produce spin as well as push -- that torque arm is the whole
       difference between them and the centre-applied pair above */
    b2lc_body_apply_force_at(ab, 0.0, 60.0, b2lc_body_x(ab) + 0.5, b2lc_body_y(ab), 1);
    b2lc_world_step(w3, 1.0 / 60.0, 4);
    check("apply_force_at off the centre spins as well as pushes",
          b2lc_body_omega(ab) != 0.0 && b2lc_body_vy(ab) > 0.0);
    b2lc_body_set_velocity(ab, 0.0, 0.0);
    b2lc_body_set_angular_velocity(ab, 0.0);
    b2lc_body_apply_impulse_at(ab, 0.0, 1.0, b2lc_body_x(ab) + 0.5, b2lc_body_y(ab), 1);
    check("apply_impulse_at off the centre spins as well as pushes",
          b2lc_body_omega(ab) != 0.0 && b2lc_body_vy(ab) > 0.0);

    /* --- body: centres of mass, inertia, and the four transform helpers ----- */
    b2lc_body_set_transform(ab, 10.0, 20.0, 0.0);
    b2lc_body_set_velocity(ab, 0.0, 0.0);
    b2lc_body_set_angular_velocity(ab, 0.0);
    check("world_center follows the transform",
          fabs(b2lc_body_world_center_x(ab) - 10.0) < 1e-4 &&
          fabs(b2lc_body_world_center_y(ab) - 20.0) < 1e-4);
    check("local_center of a centred box is its own origin",
          fabs(b2lc_body_local_center_x(ab)) < 1e-4 && fabs(b2lc_body_local_center_y(ab)) < 1e-4);
    /* I = m(w^2 + h^2)/12 for a 1x1 box of mass 1 */
    check("rotational_inertia of a 1x1 unit-density box is ~1/6",
          fabs(b2lc_body_rotational_inertia(ab) - (1.0 / 6.0)) < 0.01);
    check("world_point maps a local offset into world space",
          fabs(b2lc_body_world_point_x(ab, 0.5, 0.0) - 10.5) < 1e-4 &&
          fabs(b2lc_body_world_point_y(ab, 0.5, 0.0) - 20.0) < 1e-4);
    check("local_point is world_point's inverse",
          fabs(b2lc_body_local_point_x(ab, 10.5, 20.0) - 0.5) < 1e-4 &&
          fabs(b2lc_body_local_point_y(ab, 10.5, 20.0)) < 1e-4);
    b2lc_body_set_transform(ab, 10.0, 20.0, 1.5707963);          /* +90 degrees */
    check("world_vector rotates a local direction and ignores position",
          fabs(b2lc_body_world_vector_x(ab, 1.0, 0.0)) < 1e-3 &&
          fabs(b2lc_body_world_vector_y(ab, 1.0, 0.0) - 1.0) < 1e-3);
    check("local_vector is world_vector's inverse",
          fabs(b2lc_body_local_vector_x(ab, 0.0, 1.0) - 1.0) < 1e-3 &&
          fabs(b2lc_body_local_vector_y(ab, 0.0, 1.0)) < 1e-3);
    b2lc_body_set_transform(ab, 10.0, 20.0, 0.0);
    b2lc_body_set_velocity(ab, 1.0, 0.0);
    b2lc_body_set_angular_velocity(ab, 0.0);
    check("world_point_velocity of a purely translating body is its velocity",
          fabs(b2lc_body_world_point_velocity_x(ab, 10.5, 20.0) - 1.0) < 1e-4 &&
          fabs(b2lc_body_world_point_velocity_y(ab, 10.5, 20.0)) < 1e-4);
    check("local_point_velocity agrees with the world-space reading",
          fabs(b2lc_body_local_point_velocity_x(ab, 0.5, 0.0) - 1.0) < 1e-4 &&
          fabs(b2lc_body_local_point_velocity_y(ab, 0.5, 0.0)) < 1e-4);
    b2lc_body_set_velocity(ab, 0.0, 0.0);

    /* --- body: the AABB and mass-data readback registers -------------------- */
    b2lc_body_aabb_update(ab);
    check("body AABB brackets the 1x1 box at (10,20)",
          b2lc_aabb_lower_x() < 9.6 && b2lc_aabb_upper_x() > 10.4 &&
          b2lc_aabb_lower_y() < 19.6 && b2lc_aabb_upper_y() > 20.4);
    b2lc_body_mass_data_update(ab);
    check("body mass data reports the box's mass and its local centre",
          fabs(b2lc_md_mass() - 1.0) < 0.05 &&
          fabs(b2lc_md_center_x()) < 1e-4 && fabs(b2lc_md_center_y()) < 1e-4 &&
          b2lc_md_inertia() > 0.0);

    /* --- body: shape and joint enumeration (snapshot, then index) ----------- */
    check("body_shape_count counts the one shape on the sweep body", b2lc_body_shape_count(ab) == 1);
    check("body_shape_at returns the handle we created", b2lc_body_shape_at(0) == as);
    check("body_shape_at out of range is 0, not a stale entry", b2lc_body_shape_at(9) == 0);
    int jb1 = b2lc_body_create(w3, 0, 100.0, 0.0, 0.0, 0, 0);
    int jb2 = b2lc_body_create(w3, 2, 101.0, 0.0, 0.0, 0, 0);
    b2lc_shape_add_box(jb2, 0.3, 0.3, 1.0, 0.3, 0.0);
    int jj = b2lc_joint_distance(w3, jb1, jb2, 0.0, 0.0, 0.0, 0.0, 1.0, 0);
    check("body_joint_count sees the joint on the body", b2lc_body_joint_count(jb2) == 1);
    check("body_joint_at returns the joint handle", b2lc_body_joint_at(0) == jj);
    check("body_joint_at out of range is 0", b2lc_body_joint_at(5) == 0);

    /* --- body: the move-event register's remaining fields -------------------
       x and y come as a pair and only y was ever read; angle and asleep had
       never been touched at all, and a mis-wired angle field is invisible to a
       test that only checks the body handle. */
    int mvb = b2lc_body_create(w3, 2, 120.0, 10.0, 0.0, 0, 0);
    b2lc_shape_add_box(mvb, 0.4, 0.4, 1.0, 0.3, 0.0);
    b2lc_body_set_angular_velocity(mvb, 3.0);
    b2lc_world_step(w3, 1.0 / 60.0, 4);
    int mvn = b2lc_bodies_update(w3), mvi = -1;
    for (int k = 0; k < mvn; k++) if (b2lc_body_move_body(k) == mvb) mvi = k;
    check("the spinning body appears in the move-event buffer", mvi >= 0);
    check("its move event carries x, angle and the sleep flag",
          mvi >= 0 && fabs(b2lc_body_move_x(mvi) - 120.0) < 0.1 &&
          b2lc_body_move_angle(mvi) > 0.0 && b2lc_body_move_asleep(mvi) == 0);
    /* body_move_count and body_move_y are two of SIX exports this harness had
       DECLARED in its extern block and never called -- found by gcov while
       measuring this sweep, and worth recording because every grep-based count
       of "exports the smoke test reaches" had been counting them. A declaration
       is not a call; it is the suite's "shipped is not run" lesson one level
       down. Each of the six is the count-or-field twin of an accessor already
       driven here, so each is asserted against what its twin returned. */
    check("body_move_count agrees with the bodies_update return", b2lc_body_move_count() == mvn);
    check("body_move_y carries the same y the body getter reports",
          mvi >= 0 && fabs(b2lc_body_move_y(mvi) - b2lc_body_y(mvb)) < 1e-4);

    /* --- body: the kinematic mover -----------------------------------------
       set_target_transform writes the velocity that lands the body on the target
       after ONE step of the given length, so the velocity is assertable before
       the step is taken and the arrival after it. */
    int kb = b2lc_body_create(w3, 1, 140.0, 0.0, 0.0, 0, 0);
    b2lc_shape_add_box(kb, 0.3, 0.3, 1.0, 0.3, 0.0);
    b2lc_body_set_target_transform(kb, 141.0, 0.0, 0.0, 1.0 / 60.0);
    check("set_target_transform writes the velocity that reaches the target",
          fabs(b2lc_body_vx(kb) - 60.0) < 1.0);
    b2lc_world_step(w3, 1.0 / 60.0, 4);
    check("the kinematic body arrives on its target", fabs(b2lc_body_x(kb) - 141.0) < 0.05);
    b2lc_body_set_velocity(kb, 0.0, 0.0);

    /* --- body: the BODY-level event switches -------------------------------
       They gate every shape on the body at once. Two facts have to compose for
       this to be assertable at all, and the first draft got the second wrong:
       fill_shape_def turns enableContactEvents ON for every shape the shim
       creates (so b2ContactsUpdate works out of the box), and Box2D ORs the two
       shapes' flags when it builds the contact. So silencing ONE body cannot
       silence a contact with a default-built shape -- the switch is only visible
       with both sides off, and re-enabling either side alone brings it back.
       The other half of the fixture is proving the landing HAPPENED while the
       events stayed silent; without it "no event" and "no collision" read the
       same. */
    int ecG = b2lc_body_create(w3, 0, 180.0, 0.0, 0.0, 0, 0);
    /* shape geometry is LOCAL to its body -- the first draft of this fixture
       wrote the segment's endpoints in world coordinates, put the ground at
       x 358..362 and let the box fall past it forever, and BOTH assertions
       below still passed: no contact event (nothing was there to touch) and
       y < 1.0 (it was at -400). Hence the local span here and the landing
       assertion pinned to the resting height rather than to "below the start". */
    b2lc_shape_add_segment(ecG, -2.0, 0.0, 2.0, 0.0, 0.6, 0.0);
    int ecB = b2lc_body_create(w3, 2, 180.0, 2.0, 0.0, 0, 0);
    b2lc_shape_add_box(ecB, 0.3, 0.3, 1.0, 0.3, 0.0);
    b2lc_body_enable_contact_events(ecG, 0);
    b2lc_body_enable_contact_events(ecB, 0);
    b2lc_body_enable_hit_events(ecB, 1);
    int ecSeen = 0;
    for (int i = 0; i < 150; i++) {
        b2lc_world_step(w3, 1.0 / 60.0, 4);
        int cn = b2lc_contacts_update(w3);
        for (int k = 0; k < cn; k++)
            if (b2lc_contact_begin_a(k) == ecB || b2lc_contact_begin_b(k) == ecB) ecSeen = 1;
    }
    check("body_enable_contact_events(0) on BOTH bodies silences the landing", ecSeen == 0);
    check("...and the body really did land ON the ground, so that silence is the switch",
          fabs(b2lc_body_y(ecB) - 0.3) < 0.05);
    b2lc_body_enable_contact_events(ecB, 1);   /* one side is enough: the flags OR */
    b2lc_body_set_transform(ecB, 180.0, 2.0, 0.0);
    b2lc_body_set_velocity(ecB, 0.0, 0.0);
    b2lc_body_set_awake(ecB, 1);
    ecSeen = 0;
    int ecCountOk = 1;
    for (int i = 0; i < 150; i++) {
        b2lc_world_step(w3, 1.0 / 60.0, 4);
        int cn = b2lc_contacts_update(w3);
        /* the register and the return are two readings of one number, and only
           the return had ever been read (see the six-declared-never-called note
           above); a step that disagrees is a mis-sized buffer */
        if (b2lc_contact_begin_count() != cn) ecCountOk = 0;
        for (int k = 0; k < cn; k++)
            if (b2lc_contact_begin_a(k) == ecB || b2lc_contact_begin_b(k) == ecB) ecSeen = 1;
    }
    check("re-enabling ONE side restores the landing event", ecSeen == 1);
    check("contact_begin_count agrees with the contacts_update return on every step",
          ecCountOk == 1);

    /* --- shape: identity, material and filter ------------------------------- */
    int mb = b2lc_body_create(w3, 0, 200.0, 0.0, 0.0, 0, 0);
    int ms = b2lc_shape_add_box(mb, 0.5, 0.5, 1.0, 0.3, 0.1);
    check("shape_body maps the shape back to its body handle", b2lc_shape_body(ms) == mb);
    check("shape_type reports polygon (3) for a box", b2lc_shape_type(ms) == 3);
    check("shape_is_sensor is false for a solid shape", b2lc_shape_is_sensor(ms) == 0);
    check("density/friction/restitution read back what add_box was given",
          fabs(b2lc_shape_density(ms) - 1.0) < 1e-5 &&
          fabs(b2lc_shape_friction(ms) - 0.3) < 1e-5 &&
          fabs(b2lc_shape_restitution(ms) - 0.1) < 1e-5);
    b2lc_shape_set_density(ms, 2.0);
    b2lc_shape_set_friction(ms, 0.9);
    b2lc_shape_set_restitution(ms, 0.4);
    check("the three material setters round-trip through their getters",
          fabs(b2lc_shape_density(ms) - 2.0) < 1e-5 &&
          fabs(b2lc_shape_friction(ms) - 0.9) < 1e-5 &&
          fabs(b2lc_shape_restitution(ms) - 0.4) < 1e-5);
    b2lc_shape_set_material_id(ms, 77);
    check("material id round-trips", b2lc_shape_material_id(ms) == 77);
    b2lc_shape_set_filter(ms, 4.0, 12.0, -3);
    check("shape filter round-trips category, mask and group",
          b2lc_shape_filter_category(ms) == 4.0 && b2lc_shape_filter_mask(ms) == 12.0 &&
          b2lc_shape_filter_group(ms) == -3);
    /* THE 2^53 DOUBLE GUARD, pinned from the C side. Box2D's filter bits are
       uint64 and a DEFAULT mask reads back as 2^64-1, which is above what a
       double carries exactly -- so the shim refuses the WHOLE call rather than
       write a rounded value. That silent refusal is what made b2kSetCategory a
       no-op until the Kit learned to clamp every readback (the ghost-layer
       defect, engine run 5); this is the behaviour the clamp is written against. */
    b2lc_shape_set_filter(ms, 18446744073709551615.0, 12.0, -3);
    check("set_filter refuses bits above the 2^53 guard, leaving the filter intact",
          b2lc_shape_filter_category(ms) == 4.0);

    /* --- shape: the event flag pairs ---------------------------------------- */
    b2lc_shape_enable_sensor_events(ms, 1);
    check("sensor-event flag round-trips on", b2lc_shape_are_sensor_events_enabled(ms) == 1);
    b2lc_shape_enable_sensor_events(ms, 0);
    check("sensor-event flag round-trips off", b2lc_shape_are_sensor_events_enabled(ms) == 0);
    b2lc_shape_enable_contact_events(ms, 0);
    check("contact-event flag round-trips off", b2lc_shape_are_contact_events_enabled(ms) == 0);
    b2lc_shape_enable_contact_events(ms, 1);
    check("contact-event flag round-trips on", b2lc_shape_are_contact_events_enabled(ms) == 1);
    b2lc_shape_enable_hit_events(ms, 1);
    check("hit-event flag round-trips on", b2lc_shape_are_hit_events_enabled(ms) == 1);
    b2lc_shape_enable_hit_events(ms, 0);
    check("hit-event flag round-trips off", b2lc_shape_are_hit_events_enabled(ms) == 0);
    /* pre-solve has no exported getter (there is no b2Shape_ArePreSolveEventsEnabled) */
    b2lc_shape_enable_presolve_events(ms, 1);
    check("presolve-event write leaves the shape valid", b2lc_shape_type(ms) == 3);

    /* --- shape: one geometry readback register per shape kind --------------- */
    int gb = b2lc_body_create(w3, 0, 220.0, 0.0, 0.0, 0, 0);
    int gcir = b2lc_shape_add_circle(gb, 0.25, -0.5, 0.75, 1.0, 0.2, 0.0);
    b2lc_shape_circle_update(gcir);
    check("circle geometry reads back its centre and radius",
          fabs(b2lc_shape_circle_x() - 0.25) < 1e-5 && fabs(b2lc_shape_circle_y() + 0.5) < 1e-5 &&
          fabs(b2lc_shape_circle_radius() - 0.75) < 1e-5);
    int gcap = b2lc_shape_add_capsule(gb, -1.0, 0.5, 1.0, -0.5, 0.3, 1.0, 0.2, 0.0);
    b2lc_shape_capsule_update(gcap);
    check("capsule geometry reads back both centres and the radius",
          fabs(b2lc_shape_capsule_x1() + 1.0) < 1e-5 && fabs(b2lc_shape_capsule_y1() - 0.5) < 1e-5 &&
          fabs(b2lc_shape_capsule_x2() - 1.0) < 1e-5 && fabs(b2lc_shape_capsule_y2() + 0.5) < 1e-5 &&
          fabs(b2lc_shape_capsule_radius() - 0.3) < 1e-5);
    int gseg = b2lc_shape_add_segment(gb, -2.0, 1.0, 2.0, 1.5, 0.5, 0.0);
    b2lc_shape_segment_update(gseg);
    check("segment geometry reads back both endpoints",
          fabs(b2lc_shape_segment_x1() + 2.0) < 1e-5 && fabs(b2lc_shape_segment_y1() - 1.0) < 1e-5 &&
          fabs(b2lc_shape_segment_x2() - 2.0) < 1e-5 && fabs(b2lc_shape_segment_y2() - 1.5) < 1e-5);
    /* the readback registers are shared and kind-checked: asking a circle for its
       capsule must zero the register, not answer the last capsule's numbers --
       the same stale-entry hazard the Kit's event readers were count-guarded for */
    b2lc_shape_capsule_update(gcir);
    check("a kind-mismatched geometry read clears the register",
          b2lc_shape_capsule_radius() == 0.0 && b2lc_shape_capsule_x1() == 0.0);

    /* --- shape: the polygon point builder ----------------------------------- */
    b2lc_poly_begin();
    b2lc_poly_add(-0.5, -0.5);
    b2lc_poly_add(0.5, -0.5);
    b2lc_poly_add(0.5, 0.5);
    b2lc_poly_add(-0.5, 0.5);
    int gpoly = b2lc_shape_add_polygon(gb, 1.0, 0.3, 0.0);
    check("add_polygon builds a shape from the accumulated points", gpoly > 0);
    check("polygon_update reports the four vertices", b2lc_shape_polygon_update(gpoly) == 4);
    check("polygon_count agrees with the update", b2lc_shape_polygon_count() == 4);
    check("a hull polygon has no rounding radius", fabs(b2lc_shape_polygon_radius()) < 1e-6);
    /* b2ComputeHull is free to reorder, so assert the SET of corners, not the
       order they came back in */
    int pcorners = 0;
    for (int k = 0; k < b2lc_shape_polygon_count(); k++)
        if (fabs(fabs(b2lc_shape_polygon_vx(k)) - 0.5) < 1e-5 &&
            fabs(fabs(b2lc_shape_polygon_vy(k)) - 0.5) < 1e-5) pcorners++;
    check("the polygon's vertices are the four unit-square corners", pcorners == 4);
    check("polygon_vx/vy out of range are 0", b2lc_shape_polygon_vx(99) == 0.0 && b2lc_shape_polygon_vy(-1) == 0.0);

    /* --- shape: the geometry SETTERS ---------------------------------------
       Each one replaces a shape's geometry in place, INCLUDING its kind, which
       is what makes shape_type the assertion that proves the write landed. */
    int sb = b2lc_body_create(w3, 0, 240.0, 0.0, 0.0, 0, 0);
    int sh = b2lc_shape_add_circle(sb, 0.0, 0.0, 0.5, 1.0, 0.2, 0.0);
    b2lc_shape_set_circle(sh, 1.0, 2.0, 0.9);
    b2lc_shape_circle_update(sh);
    check("set_circle updates the circle in place",
          b2lc_shape_type(sh) == 0 && fabs(b2lc_shape_circle_x() - 1.0) < 1e-5 &&
          fabs(b2lc_shape_circle_y() - 2.0) < 1e-5 && fabs(b2lc_shape_circle_radius() - 0.9) < 1e-5);
    b2lc_shape_set_capsule(sh, -1.0, 0.0, 1.0, 0.0, 0.2);
    b2lc_shape_capsule_update(sh);
    check("set_capsule turns the shape into a capsule",
          b2lc_shape_type(sh) == 1 && fabs(b2lc_shape_capsule_radius() - 0.2) < 1e-5);
    b2lc_shape_set_segment(sh, -3.0, 0.0, 3.0, 0.0);
    b2lc_shape_segment_update(sh);
    check("set_segment turns the shape into a segment",
          b2lc_shape_type(sh) == 2 && fabs(b2lc_shape_segment_x2() - 3.0) < 1e-5);
    b2lc_poly_begin();
    b2lc_poly_add(-0.4, -0.4);
    b2lc_poly_add(0.4, -0.4);
    b2lc_poly_add(0.0, 0.6);
    b2lc_shape_set_polygon(sh);
    check("set_polygon turns the shape into a three-point polygon",
          b2lc_shape_type(sh) == 3 && b2lc_shape_polygon_update(sh) == 3);
    /* the builder's own guard: fewer than three points must leave the shape
       alone rather than hand b2ComputeHull a degenerate outline */
    b2lc_poly_begin();
    b2lc_poly_add(0.0, 0.0);
    b2lc_shape_set_polygon(sh);
    check("set_polygon refuses a degenerate outline", b2lc_shape_polygon_update(sh) == 3);

    /* --- the one-shot shape def: applied, consumed, and resettable ---------- */
    b2lc_shapedef_set_enable_contact_events(0);
    b2lc_shapedef_set_enable_hit_events(1);
    b2lc_shapedef_set_material_id(42);
    int dsh = b2lc_shape_add_box(sb, 0.2, 0.2, 1.0, 0.2, 0.0);
    check("shapedef one-shots land on the next shape created",
          b2lc_shape_are_contact_events_enabled(dsh) == 0 &&
          b2lc_shape_are_hit_events_enabled(dsh) == 1 &&
          b2lc_shape_material_id(dsh) == 42);
    int dsh2 = b2lc_shape_add_box(sb, 0.2, 0.2, 1.0, 0.2, 0.0);
    check("shapedef one-shots are CONSUMED, not sticky",
          b2lc_shape_are_contact_events_enabled(dsh2) == 1 &&
          b2lc_shape_are_hit_events_enabled(dsh2) == 0 &&
          b2lc_shape_material_id(dsh2) == 0);
    b2lc_shapedef_set_sensor(1);
    b2lc_shapedef_set_enable_presolve_events(1);
    b2lc_shapedef_reset();
    int dsh3 = b2lc_shape_add_box(sb, 0.2, 0.2, 1.0, 0.2, 0.0);
    check("shapedef_reset drops the pending one-shots", b2lc_shape_is_sensor(dsh3) == 0);

    /* --- shape: ray cast, AABB, closest point, mass data, point test -------- */
    int rb = b2lc_body_create(w3, 0, 280.0, 0.0, 0.0, 0, 0);
    int rs = b2lc_shape_add_box(rb, 1.0, 1.0, 1.0, 0.3, 0.0);
    check("a per-shape ray hits the box from the left",
          b2lc_shape_raycast(rs, 276.0, 0.0, 284.0, 0.0) == 1);
    check("the hit point is the box's left face",
          fabs(b2lc_shape_ray_x() - 279.0) < 1e-3 && fabs(b2lc_shape_ray_y()) < 1e-3);
    check("the hit normal points back along the ray",
          b2lc_shape_ray_normal_x() < -0.9 && fabs(b2lc_shape_ray_normal_y()) < 1e-3);
    check("the fraction is the distance travelled over the ray's length",
          fabs(b2lc_shape_ray_fraction() - 3.0 / 8.0) < 1e-3);
    check("a ray that never reaches the shape reports no hit",
          b2lc_shape_raycast(rs, 276.0, 40.0, 284.0, 40.0) == 0);
    check("a missed ray CLEARS the readback register (no stale hit)",
          b2lc_shape_ray_fraction() == 0.0 && b2lc_shape_ray_x() == 0.0);
    b2lc_shape_aabb_update(rs);
    check("shape AABB brackets the 2x2 box",
          b2lc_aabb_lower_x() < 279.1 && b2lc_aabb_upper_x() > 280.9 &&
          b2lc_aabb_lower_y() < -0.9 && b2lc_aabb_upper_y() > 0.9);
    check("closest point to a target outside the box sits on its face",
          fabs(b2lc_shape_closest_point_x(rs, 285.0, 0.0) - 281.0) < 1e-3 &&
          fabs(b2lc_shape_closest_point_y(rs, 285.0, 0.0)) < 1e-3);
    b2lc_shape_mass_data_update(rs);
    check("shape mass data reports the 2x2 unit-density box's 4kg",
          fabs(b2lc_md_mass() - 4.0) < 0.05);
    check("shape test_point is true inside and false outside",
          b2lc_shape_test_point(rs, 280.0, 0.0) == 1 && b2lc_shape_test_point(rs, 290.0, 0.0) == 0);
    /* the last two of the six declared-never-called exports: the WORLD ray
       query's count register and its body field, both twins of the fraction
       accessor the harness already drives */
    int rcn = b2lc_query_raycast_all(w3, 280.0, -4.0, 280.0, 4.0);
    check("query_count agrees with the raycast_all return", b2lc_query_count() == rcn);
    int qsaw = 0;
    for (int k = 0; k < rcn; k++) if (b2lc_query_body(k) == rb) qsaw = 1;
    check("query_body names the box the ray crossed", rcn > 0 && qsaw == 1);

    /* --- shape: sensor overlap POLLING (the non-event way to read a sensor) - */
    int senB2 = b2lc_body_create(w3, 0, 300.0, 0.0, 0.0, 0, 0);
    b2lc_shapedef_set_sensor(1);
    b2lc_shapedef_set_enable_sensor_events(1);
    int senS2 = b2lc_shape_add_box(senB2, 1.0, 1.0, 0.0, 0.0, 0.0);
    check("the sensor shape reports itself as a sensor", b2lc_shape_is_sensor(senS2) == 1);
    int visB2 = b2lc_body_create(w3, 2, 300.0, 0.0, 0.0, 0, 1);
    b2lc_shapedef_set_enable_sensor_events(1);
    int visS2 = b2lc_shape_add_circle(visB2, 0.0, 0.0, 0.2, 1.0, 0.0, 0.0);
    b2lc_body_set_gravity_scale(visB2, 0.0);      /* park it inside the sensor */
    int snOk = 1, snSeen = 0;
    for (int i = 0; i < 8; i++) {
        b2lc_world_step(w3, 1.0 / 60.0, 4);
        int sn = b2lc_sensors_update(w3);
        if (b2lc_sensor_begin_count() != sn) snOk = 0;
        if (sn > 0) snSeen = 1;
    }
    check("sensor_begin_count agrees with the sensors_update return on every step", snOk == 1);
    check("a shape created INSIDE a sensor still reports an entry", snSeen == 1);
    check("sensor capacity counts room for the overlapping shape",
          b2lc_shape_sensor_capacity(senS2) >= 1);
    check("the overlap poll finds a visitor", b2lc_shape_sensor_overlaps_update(senS2) >= 1);
    check("overlap_count agrees with the update", b2lc_shape_sensor_overlap_count() >= 1);
    int sawOv = 0;
    for (int k = 0; k < b2lc_shape_sensor_overlap_count(); k++)
        if (b2lc_shape_sensor_overlap_at(k) == visS2) sawOv = 1;
    check("overlap_at names the visitor's shape handle", sawOv == 1);
    check("overlap_at out of range is 0", b2lc_shape_sensor_overlap_at(999) == 0);

    b2lc_world_destroy(w3);
    check("accessor-sweep world destroyed cleanly", 1);

    printf("\n==== %d passed, %d failed ====\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
