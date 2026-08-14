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

    printf("\n==== %d passed, %d failed ====\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
