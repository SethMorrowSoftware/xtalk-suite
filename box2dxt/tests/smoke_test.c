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

/* ---- the world/joint/query/chain/event-register sweep (2026-08-23) ----
   Like the block above, these declarations are GENERATED from the LC_API
   definitions in src/box2d_lc.c rather than typed out (176 of them; the
   same UB-the-linker-cannot-catch reasoning applies). They cover the
   families gcov measured as never entered on 2026-08-17: world tuning/info/
   profile/counters, the closest-ray and query readback registers, contact
   end + hit events, sensor end events, chain accessors, and the whole
   per-kind joint accessor surface. See the sweep block in main. */
extern void   b2lc_chain_destroy(int);
extern double b2lc_chain_friction(int);
extern int    b2lc_chain_is_valid(int);
extern double b2lc_chain_restitution(int);
extern void   b2lc_chain_set_friction(int, double);
extern void   b2lc_chain_set_restitution(int, double);
extern int    b2lc_contact_end_a(int);
extern int    b2lc_contact_end_b(int);
extern int    b2lc_contact_end_count(void);
extern int    b2lc_contact_hit_a(int);
extern int    b2lc_contact_hit_b(int);
extern int    b2lc_contact_hit_count(void);
extern double b2lc_contact_hit_nx(int);
extern double b2lc_contact_hit_ny(int);
extern double b2lc_contact_hit_speed(int);
extern double b2lc_contact_hit_x(int);
extern double b2lc_contact_hit_y(int);
extern double b2lc_distance_current_length(int);
extern void   b2lc_distance_enable_motor(int, int);
extern void   b2lc_distance_enable_spring(int, int, double, double);
extern int    b2lc_distance_is_limit_enabled(int);
extern int    b2lc_distance_is_motor_enabled(int);
extern int    b2lc_distance_is_spring_enabled(int);
extern double b2lc_distance_length(int);
extern double b2lc_distance_max_length(int);
extern double b2lc_distance_max_motor_force(int);
extern double b2lc_distance_min_length(int);
extern double b2lc_distance_motor_force(int);
extern double b2lc_distance_motor_speed(int);
extern void   b2lc_distance_set_length(int, double);
extern void   b2lc_distance_set_length_range(int, double, double);
extern void   b2lc_distance_set_max_motor_force(int, double);
extern void   b2lc_distance_set_motor_speed(int, double);
extern double b2lc_distance_spring_damping(int);
extern double b2lc_distance_spring_hertz(int);
extern int    b2lc_joint_body_a(int);
extern int    b2lc_joint_body_b(int);
extern double b2lc_joint_constraint_force_x(int);
extern double b2lc_joint_constraint_force_y(int);
extern double b2lc_joint_constraint_torque(int);
extern void   b2lc_joint_destroy(int);
extern int    b2lc_joint_filter(int, int, int);
extern int    b2lc_joint_get_collide_connected(int);
extern double b2lc_joint_local_anchor_a_x(int);
extern double b2lc_joint_local_anchor_a_y(int);
extern double b2lc_joint_local_anchor_b_x(int);
extern double b2lc_joint_local_anchor_b_y(int);
extern void   b2lc_joint_set_collide_connected(int, int);
extern int    b2lc_joint_type(int);
extern void   b2lc_joint_wake_bodies(int);
extern double b2lc_motor_angular_offset(int);
extern double b2lc_motor_correction_factor(int);
extern double b2lc_motor_linear_offset_x(int);
extern double b2lc_motor_linear_offset_y(int);
extern double b2lc_motor_max_force(int);
extern double b2lc_motor_max_torque(int);
extern void   b2lc_motor_set_angular_offset(int, double);
extern void   b2lc_motor_set_correction_factor(int, double);
extern void   b2lc_motor_set_linear_offset(int, double, double);
extern void   b2lc_motor_set_max_force(int, double);
extern void   b2lc_motor_set_max_torque(int, double);
extern double b2lc_mouse_max_force(int);
extern void   b2lc_mouse_set_max_force(int, double);
extern void   b2lc_mouse_set_spring_damping(int, double);
extern void   b2lc_mouse_set_spring_hertz(int, double);
extern double b2lc_mouse_spring_damping(int);
extern double b2lc_mouse_spring_hertz(int);
extern double b2lc_mouse_target_x(int);
extern double b2lc_mouse_target_y(int);
extern void   b2lc_prismatic_enable_limit(int, int, double, double);
extern void   b2lc_prismatic_enable_motor(int, int, double, double);
extern void   b2lc_prismatic_enable_spring(int, int);
extern int    b2lc_prismatic_is_limit_enabled(int);
extern int    b2lc_prismatic_is_motor_enabled(int);
extern int    b2lc_prismatic_is_spring_enabled(int);
extern double b2lc_prismatic_lower_limit(int);
extern double b2lc_prismatic_max_motor_force(int);
extern double b2lc_prismatic_motor_force(int);
extern double b2lc_prismatic_motor_speed(int);
extern void   b2lc_prismatic_set_motor_speed(int, double);
extern void   b2lc_prismatic_set_spring_damping(int, double);
extern void   b2lc_prismatic_set_spring_hertz(int, double);
extern double b2lc_prismatic_speed(int);
extern double b2lc_prismatic_spring_damping(int);
extern double b2lc_prismatic_spring_hertz(int);
extern double b2lc_prismatic_translation(int);
extern double b2lc_prismatic_upper_limit(int);
extern double b2lc_query_normal_x(int);
extern double b2lc_query_normal_y(int);
extern int    b2lc_query_overlap_aabb(int, double, double, double, double);
extern int    b2lc_query_overlap_circle(int, double, double, double);
extern int    b2lc_query_overlap_point(int, double, double);
extern int    b2lc_query_overlap_shape(int, double);
extern int    b2lc_query_shape(int);
extern int    b2lc_query_shapecast(int, double, double, double);
extern double b2lc_query_x(int);
extern double b2lc_query_y(int);
extern double b2lc_ray_fraction(void);
extern double b2lc_ray_normal_x(void);
extern double b2lc_ray_normal_y(void);
extern int    b2lc_ray_shape(void);
extern double b2lc_ray_x(void);
extern double b2lc_revolute_angle(int);
extern void   b2lc_revolute_enable_limit(int, int, double, double);
extern void   b2lc_revolute_enable_motor(int, int, double, double);
extern void   b2lc_revolute_enable_spring(int, int);
extern int    b2lc_revolute_is_limit_enabled(int);
extern int    b2lc_revolute_is_motor_enabled(int);
extern int    b2lc_revolute_is_spring_enabled(int);
extern double b2lc_revolute_lower_limit(int);
extern double b2lc_revolute_max_motor_torque(int);
extern double b2lc_revolute_motor_speed(int);
extern double b2lc_revolute_motor_torque(int);
extern void   b2lc_revolute_set_max_motor_torque(int, double);
extern void   b2lc_revolute_set_motor_speed(int, double);
extern void   b2lc_revolute_set_spring_damping(int, double);
extern void   b2lc_revolute_set_spring_hertz(int, double);
extern double b2lc_revolute_spring_damping(int);
extern double b2lc_revolute_spring_hertz(int);
extern double b2lc_revolute_upper_limit(int);
extern int    b2lc_sensor_end_count(void);
extern int    b2lc_sensor_end_sensor(int);
extern int    b2lc_sensor_end_visitor(int);
extern double b2lc_weld_angular_damping(int);
extern double b2lc_weld_angular_hertz(int);
extern double b2lc_weld_linear_damping(int);
extern double b2lc_weld_linear_hertz(int);
extern double b2lc_weld_reference_angle(int);
extern void   b2lc_weld_set_reference_angle(int, double);
extern void   b2lc_weld_set_stiffness(int, double, double, double, double);
extern void   b2lc_wheel_enable_limit(int, int);
extern void   b2lc_wheel_enable_motor(int, int, double, double);
extern void   b2lc_wheel_enable_spring(int, int, double, double);
extern int    b2lc_wheel_is_limit_enabled(int);
extern int    b2lc_wheel_is_motor_enabled(int);
extern int    b2lc_wheel_is_spring_enabled(int);
extern double b2lc_wheel_lower_limit(int);
extern double b2lc_wheel_max_motor_torque(int);
extern double b2lc_wheel_motor_speed(int);
extern double b2lc_wheel_motor_torque(int);
extern void   b2lc_wheel_set_limits(int, double, double);
extern double b2lc_wheel_spring_damping(int);
extern double b2lc_wheel_spring_hertz(int);
extern double b2lc_wheel_upper_limit(int);
extern int    b2lc_world_awake_body_count(int);
extern int    b2lc_world_count_bodies(void);
extern int    b2lc_world_count_contacts(void);
extern int    b2lc_world_count_islands(void);
extern int    b2lc_world_count_joints(void);
extern int    b2lc_world_count_shapes(void);
extern void   b2lc_world_counters_update(int);
extern void   b2lc_world_enable_continuous(int, int);
extern void   b2lc_world_enable_sleeping(int, int);
extern void   b2lc_world_enable_speculative(int, int);
extern void   b2lc_world_enable_warm_starting(int, int);
extern double b2lc_world_gravity_x(int);
extern double b2lc_world_gravity_y(int);
extern double b2lc_world_hit_event_threshold(int);
extern int    b2lc_world_is_continuous_enabled(int);
extern int    b2lc_world_is_sleeping_enabled(int);
extern int    b2lc_world_is_warm_starting(int);
extern double b2lc_world_maximum_linear_speed(int);
extern double b2lc_world_profile_collide(void);
extern double b2lc_world_profile_pairs(void);
extern double b2lc_world_profile_refit(void);
extern double b2lc_world_profile_sensors(void);
extern double b2lc_world_profile_solve(void);
extern double b2lc_world_profile_step(void);
extern void   b2lc_world_profile_update(int);
extern double b2lc_world_restitution_threshold(int);
extern void   b2lc_world_set_contact_tuning(int, double, double, double);
extern void   b2lc_world_set_gravity(int, double, double);
extern void   b2lc_world_set_hit_event_threshold(int, double);
extern void   b2lc_world_set_joint_tuning(int, double, double);
extern void   b2lc_world_set_maximum_linear_speed(int, double);
extern void   b2lc_world_set_restitution_threshold(int, double);

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


    /* ====== the world/joint/query/chain/event-register sweep (3 worlds) ======
       Added 2026-08-23. Same charter as the 2026-08-17 body+shape sweep above:
       gcov (2026-08-17) measured 194 of the shim's 370 LC_API exports entered,
       and the 176 still dark were the world, joint, query, mouse, chain and
       contact/sensor-register families -- every one an ordinary C entry point,
       so nothing scarce stands in the way of executing all of them. These
       assertions are deliberately SHALLOW next to the behaviour tests at the
       top of the file: each holds "this export links, takes these arguments,
       and reports the documented shape", getters are checked against values
       this test WROTE (or against arithmetic pinned in a comment), and an
       export that earns a real lesson should GRADUATE into a behaviour section.
       Three worlds keep the fixtures independent: w4 for world tuning/info,
       w5 for rays/queries/events/chains (region-separated on x), w6 for the
       per-kind joint surfaces. */

    /* --- world: tuning setters and their getters ---------------------------- */
    int w4 = b2lc_world_create(0.0, -10.0, 1, 1);
    check("tuning world created", w4 > 0);
    b2lc_world_set_gravity(w4, 1.5, -3.25);
    check("set_gravity round-trips through both gravity getters",
          fabs(b2lc_world_gravity_x(w4) - 1.5) < 1e-5 &&
          fabs(b2lc_world_gravity_y(w4) + 3.25) < 1e-5);
    b2lc_world_set_gravity(w4, 0.0, -10.0);        /* restore for the fixture below */
    b2lc_world_enable_sleeping(w4, 0);
    check("is_sleeping_enabled sees enable_sleeping(0)", b2lc_world_is_sleeping_enabled(w4) == 0);
    b2lc_world_enable_sleeping(w4, 1);
    check("is_sleeping_enabled sees enable_sleeping(1)", b2lc_world_is_sleeping_enabled(w4) == 1);
    b2lc_world_enable_continuous(w4, 0);
    check("is_continuous_enabled sees enable_continuous(0)", b2lc_world_is_continuous_enabled(w4) == 0);
    b2lc_world_enable_continuous(w4, 1);
    check("is_continuous_enabled sees enable_continuous(1)", b2lc_world_is_continuous_enabled(w4) == 1);
    b2lc_world_enable_warm_starting(w4, 0);
    check("is_warm_starting sees enable_warm_starting(0)", b2lc_world_is_warm_starting(w4) == 0);
    b2lc_world_enable_warm_starting(w4, 1);        /* leave ON: off degrades the solver */
    check("is_warm_starting sees enable_warm_starting(1)", b2lc_world_is_warm_starting(w4) == 1);
    b2lc_world_set_restitution_threshold(w4, 0.5);
    check("restitution threshold round-trips", fabs(b2lc_world_restitution_threshold(w4) - 0.5) < 1e-5);
    b2lc_world_set_hit_event_threshold(w4, 2.5);
    check("hit-event threshold round-trips", fabs(b2lc_world_hit_event_threshold(w4) - 2.5) < 1e-5);
    b2lc_world_set_maximum_linear_speed(w4, 50.0);
    check("maximum linear speed round-trips", fabs(b2lc_world_maximum_linear_speed(w4) - 50.0) < 1e-5);
    /* speculative margin and the two tuning packs have no exported getters
       (mirroring the presolve-flag precedent above); what is assertable from
       out here is that the writes are accepted and the world still simulates
       -- the settle assertion below is that proof, so these writes stay sane
       rather than exotic. */
    b2lc_world_enable_speculative(w4, 0);
    b2lc_world_enable_speculative(w4, 1);
    b2lc_world_set_contact_tuning(w4, 45.0, 8.0, 3.0);
    b2lc_world_set_joint_tuning(w4, 60.0, 5.0);

    /* --- world: info, counters and the profile registers --------------------
       A known census: ONE static ground + TWO dynamic boxes + ONE joint, so
       every counter below is asserted against what this test built, not
       against whatever the engine happens to hold. */
    int cwG = b2lc_body_create(w4, 0, 0.0, 0.0, 0.0, 0, 0);
    b2lc_shape_add_segment(cwG, -6.0, 0.0, 6.0, 0.0, 0.6, 0.0);
    int cw1 = b2lc_body_create(w4, 2, -1.0, 3.0, 0.0, 0, 0);
    b2lc_shape_add_box(cw1, 0.5, 0.5, 1.0, 0.4, 0.0);
    int cw2 = b2lc_body_create(w4, 2, 1.0, 3.0, 0.0, 0, 0);
    b2lc_shape_add_box(cw2, 0.5, 0.5, 1.0, 0.4, 0.0);
    b2lc_joint_distance(w4, cw1, cw2, 0.0, 0.0, 0.0, 0.0, 2.0, 0);
    /* dynamic bodies spawn awake; the static ground is never awake, so the
       count is exactly the two boxes */
    check("awake_body_count counts the two fresh dynamic bodies",
          b2lc_world_awake_body_count(w4) == 2);
    for (int i = 0; i < 120; i++) b2lc_world_step(w4, 1.0 / 60.0, 4);
    check("the tuned world still lands its boxes (tuning writes were sane)",
          fabs(b2lc_body_y(cw1) - 0.5) < 0.1 && fabs(b2lc_body_y(cw2) - 0.5) < 0.1);
    /* wake the pair and take one more step so the counters see live islands
       and the profile's last-step numbers come from a step that did work */
    b2lc_body_apply_impulse(cw1, 0.0, 1.0, 1);
    b2lc_world_step(w4, 1.0 / 60.0, 4);
    b2lc_world_counters_update(w4);
    check("count_bodies reports the built census", b2lc_world_count_bodies() == 3);
    check("count_shapes reports the built census", b2lc_world_count_shapes() == 3);
    check("count_joints reports the one joint", b2lc_world_count_joints() == 1);
    check("count_contacts sees the boxes resting on the ground", b2lc_world_count_contacts() >= 1);
    check("count_islands sees at least one island", b2lc_world_count_islands() >= 1);
    b2lc_world_profile_update(w4);
    /* the profile is the LAST step's timings in milliseconds; the step above
       solved a live island, and the monotonic clock is sub-microsecond, so
       the step total is strictly positive while every phase must simply be a
       defined non-negative number */
    check("profile_step is positive after a working step", b2lc_world_profile_step() > 0.0);
    check("the six profile phases read as non-negative numbers",
          b2lc_world_profile_pairs() >= 0.0 && b2lc_world_profile_collide() >= 0.0 &&
          b2lc_world_profile_solve() >= 0.0 && b2lc_world_profile_refit() >= 0.0 &&
          b2lc_world_profile_sensors() >= 0.0 && b2lc_world_profile_step() < 1e6);
    b2lc_world_destroy(w4);
    /* stale-world getters are harmless, and the two snapshot updaters ZERO
       their registers on an invalid handle rather than leaving last week's
       numbers behind (the same stale-register law as the geometry readers) */
    check("gravity getter on a destroyed world is 0", b2lc_world_gravity_x(w4) == 0.0);
    check("awake_body_count on a destroyed world is 0", b2lc_world_awake_body_count(w4) == 0);
    b2lc_world_counters_update(w4);
    check("counters_update on a destroyed world clears the census", b2lc_world_count_bodies() == 0);
    b2lc_world_profile_update(w4);
    check("profile_update on a destroyed world clears the timings", b2lc_world_profile_step() == 0.0);

    /* --- closest-ray readback registers (w5, region x=500) ------------------ */
    int w5 = b2lc_world_create(0.0, -10.0, 1, 1);
    check("query/event world created", w5 > 0);
    int rayB = b2lc_body_create(w5, 0, 500.0, 0.0, 0.0, 0, 0);
    int rayS = b2lc_shape_add_box(rayB, 1.0, 1.0, 1.0, 0.3, 0.0);
    /* a 2x2 box at (500,0); ray from (496,0) to (504,0) meets its left face at
       x=499: fraction 3/8 of the 8m ray, normal pointing back along the ray */
    check("closest ray hits the box", b2lc_cast_ray_closest(w5, 496.0, 0.0, 504.0, 0.0) == 1);
    check("ray_shape names the shape the ray hit", b2lc_ray_shape() == rayS);
    check("ray_x is the left face", fabs(b2lc_ray_x() - 499.0) < 1e-3);
    check("ray normal points back along the ray",
          b2lc_ray_normal_x() < -0.9 && fabs(b2lc_ray_normal_y()) < 1e-3);
    check("ray fraction is distance over ray length", fabs(b2lc_ray_fraction() - 3.0 / 8.0) < 1e-3);
    check("a missed closest ray CLEARS the registers (no stale hit)",
          b2lc_cast_ray_closest(w5, 496.0, 40.0, 504.0, 40.0) == 0 &&
          b2lc_ray_shape() == 0 && b2lc_ray_x() == 0.0 && b2lc_ray_fraction() == 0.0);

    /* --- the world query family (w5, regions x=520 and x=540) ---------------
       Known geometry again: a three-box stack at x=520 and one lone box at
       x=540, all static, so every count and every row is checkable. */
    int qs1 = b2lc_body_create(w5, 0, 520.0, 1.0, 0.0, 0, 0); b2lc_shape_add_box(qs1, 0.5, 0.5, 0.0, 0.0, 0.0);
    int qs2 = b2lc_body_create(w5, 0, 520.0, 3.0, 0.0, 0, 0); b2lc_shape_add_box(qs2, 0.5, 0.5, 0.0, 0.0, 0.0);
    int qs3 = b2lc_body_create(w5, 0, 520.0, 5.0, 0.0, 0, 0); b2lc_shape_add_box(qs3, 0.5, 0.5, 0.0, 0.0, 0.0);
    int qLone = b2lc_body_create(w5, 0, 540.0, 0.0, 0.0, 0, 0);
    b2lc_shape_add_box(qLone, 0.5, 0.5, 0.0, 0.0, 0.0);
    int qn = b2lc_query_overlap_aabb(w5, 519.0, 0.0, 521.0, 6.0);
    check("overlap_aabb finds exactly the three stacked boxes", qn == 3);
    int qSawAll = 0;
    for (int k = 0; k < qn; k++) {
        int qb = b2lc_query_body(k);
        if (qb == qs1) qSawAll |= 1;
        if (qb == qs2) qSawAll |= 2;
        if (qb == qs3) qSawAll |= 4;
        if (b2lc_query_shape(k) == 0) qSawAll = 0;   /* every row carries its shape handle */
    }
    check("overlap rows name all three bodies and their shapes", qSawAll == 7);
    qn = b2lc_query_overlap_point(w5, 540.0, 0.2);
    check("overlap_point inside the lone box returns exactly it",
          qn == 1 && b2lc_query_body(0) == qLone);
    /* overlap_point stashes the QUERY point into the row, so x/y are values
       this test wrote rather than defaults */
    check("the overlap_point row carries the query point",
          fabs(b2lc_query_x(0) - 540.0) < 1e-5 && fabs(b2lc_query_y(0) - 0.2) < 1e-5);
    check("overlap_point in empty space returns nothing", b2lc_query_overlap_point(w5, 560.0, 0.0) == 0);
    /* circle centred 1.5 above the lone box's top face, radius 1.6: reaches it */
    qn = b2lc_query_overlap_circle(w5, 540.0, 2.0, 1.6);
    check("overlap_circle reaches down to the lone box", qn == 1 && b2lc_query_body(0) == qLone);
    /* proxy = a fat segment (two poly points + radius) hovering over the box;
       its surface reaches y=0.4, below the box top at 0.5 */
    b2lc_poly_begin();
    b2lc_poly_add(539.7, 1.2);
    b2lc_poly_add(540.3, 1.2);
    qn = b2lc_query_overlap_shape(w5, 0.8);
    check("overlap_shape (poly-builder proxy) reaches the lone box",
          qn == 1 && b2lc_query_body(0) == qLone);
    /* shape cast: a radius-0.5 circle proxy (one poly point) swept 10m right
       from (535,0); its surface meets the box's left face (x=539.5) after the
       CENTRE travels 4m, so the fraction is 0.4 */
    b2lc_poly_begin();
    b2lc_poly_add(535.0, 0.0);
    qn = b2lc_query_shapecast(w5, 0.5, 10.0, 0.0);
    check("shapecast hits the lone box", qn == 1 && b2lc_query_body(0) == qLone);
    check("shapecast fraction is centre-travel over sweep length",
          fabs(b2lc_query_fraction(0) - 0.4) < 0.05);
    check("shapecast reports the contact point and its face normal",
          fabs(b2lc_query_x(0) - 539.5) < 0.1 && b2lc_query_normal_x(0) < -0.9);
    /* ray up through the stack: first row is the lowest box's bottom face at
       y=0.5, i.e. fraction (0.5+1)/8, its normal pointing back down the ray */
    qn = b2lc_query_raycast_all(w5, 520.0, -1.0, 520.0, 7.0);
    check("upward raycast_all crosses all three stacked boxes", qn == 3);
    check("the first row is the lowest bottom face with a downward normal",
          fabs(b2lc_query_y(0) - 0.5) < 0.05 &&
          fabs(b2lc_query_fraction(0) - 1.5 / 8.0) < 0.01 &&
          b2lc_query_normal_y(0) < -0.9 && fabs(b2lc_query_normal_x(0)) < 0.1);

    /* --- contact END + HIT event registers (w5, region x=560) ---------------
       A box dropped 3.7m onto a segment: the landing arrives ~8.6 m/s, far
       above the default 1 m/s hit threshold, so the SAME step that begins the
       touch reports a hit event with the impact point, normal and speed. The
       teleport afterwards separates the pair, which is what an end-touch
       event is. (Segment endpoints are LOCAL to the ground body -- the
       world-coordinates trap recorded at the body-level event fixture above.) */
    int ehG = b2lc_body_create(w5, 0, 560.0, 0.0, 0.0, 0, 0);
    int ehGS = b2lc_shape_add_segment(ehG, -3.0, 0.0, 3.0, 0.0, 0.6, 0.0);
    int ehB = b2lc_body_create(w5, 2, 560.0, 4.0, 0.0, 0, 0);
    int ehBS = b2lc_shape_add_box(ehB, 0.3, 0.3, 1.0, 0.3, 0.0);
    b2lc_shape_enable_hit_events(ehGS, 1);
    b2lc_shape_enable_hit_events(ehBS, 1);
    int ehSawHit = 0, ehPairOk = 0;
    double ehSpeed = 0.0, ehNy = 0.0, ehPx = 0.0, ehPy = 0.0;
    for (int i = 0; i < 150 && !ehSawHit; i++) {
        b2lc_world_step(w5, 1.0 / 60.0, 4);
        b2lc_contacts_update(w5);
        if (b2lc_contact_hit_count() > 0) {
            ehSawHit = 1;
            int ha = b2lc_contact_hit_a(0), hb = b2lc_contact_hit_b(0);
            ehPairOk = (ha == ehB && hb == ehG) || (ha == ehG && hb == ehB);
            ehSpeed = b2lc_contact_hit_speed(0);
            ehNy = b2lc_contact_hit_ny(0);
            ehPx = b2lc_contact_hit_x(0);
            ehPy = b2lc_contact_hit_y(0);
        }
    }
    check("the hard landing reports a hit event", ehSawHit == 1);
    check("the hit names the box<->ground pair", ehPairOk == 1);
    check("the hit's approach speed clears the world threshold", ehSpeed > 1.0);
    check("the hit normal is vertical (a floor landing)", fabs(ehNy) > 0.9 && fabs(b2lc_contact_hit_nx(0)) < 0.3);
    check("the hit point sits where the box landed", fabs(ehPx - 560.0) < 1.0 && fabs(ehPy) < 0.5);
    b2lc_body_set_transform(ehB, 560.0, 20.0, 0.0);   /* separate the touching pair */
    b2lc_body_set_awake(ehB, 1);
    int ehSawEnd = 0;
    for (int i = 0; i < 5 && !ehSawEnd; i++) {
        b2lc_world_step(w5, 1.0 / 60.0, 4);
        b2lc_contacts_update(w5);
        if (b2lc_contact_end_count() > 0) {
            int ea = b2lc_contact_end_a(0), eb = b2lc_contact_end_b(0);
            if ((ea == ehB && eb == ehG) || (ea == ehG && eb == ehB)) ehSawEnd = 1;
        }
    }
    check("teleporting the box away reports an end-touch for the pair", ehSawEnd == 1);
    b2lc_body_destroy(ehB);   /* stop the re-fall from spamming later fixtures */

    /* --- sensor END events (w5, region x=600) ------------------------------- */
    int seB = b2lc_body_create(w5, 0, 600.0, 0.0, 0.0, 0, 0);
    b2lc_shapedef_set_sensor(1);
    b2lc_shapedef_set_enable_sensor_events(1);
    int seS = b2lc_shape_add_box(seB, 1.0, 0.5, 0.0, 0.0, 0.0);
    int seV = b2lc_body_create(w5, 2, 600.0, 0.0, 0.0, 0, 0);
    b2lc_shapedef_set_enable_sensor_events(1);
    int seVS = b2lc_shape_add_circle(seV, 0.0, 0.0, 0.2, 1.0, 0.0, 0.0);
    b2lc_body_set_gravity_scale(seV, 0.0);            /* park the visitor inside */
    int seSawBegin = 0;
    for (int i = 0; i < 8 && !seSawBegin; i++) {
        b2lc_world_step(w5, 1.0 / 60.0, 4);
        if (b2lc_sensors_update(w5) > 0 &&
            b2lc_sensor_begin_sensor(0) == seS && b2lc_sensor_begin_visitor(0) == seVS)
            seSawBegin = 1;
    }
    check("the parked visitor begins the sensor overlap", seSawBegin == 1);
    b2lc_body_set_transform(seV, 612.0, 0.0, 0.0);    /* leave the sensor */
    b2lc_body_set_awake(seV, 1);
    int seSawEnd = 0;
    for (int i = 0; i < 8 && !seSawEnd; i++) {
        b2lc_world_step(w5, 1.0 / 60.0, 4);
        b2lc_sensors_update(w5);
        if (b2lc_sensor_end_count() > 0 &&
            b2lc_sensor_end_sensor(0) == seS && b2lc_sensor_end_visitor(0) == seVS)
            seSawEnd = 1;
    }
    check("teleporting the visitor out reports the sensor end pair", seSawEnd == 1);

    /* --- chain accessors + destroy (w5, region x=650) ----------------------- */
    int chB = b2lc_body_create(w5, 0, 650.0, -5.0, 0.0, 0, 0);
    b2lc_chain_begin();
    b2lc_chain_add_point(12.0, 0.0);
    b2lc_chain_add_point(7.0, 0.0);
    b2lc_chain_add_point(3.0, 0.0);
    b2lc_chain_add_point(-3.0, 0.0);
    b2lc_chain_add_point(-7.0, 0.0);
    b2lc_chain_add_point(-12.0, 0.0);
    int ch = b2lc_chain_create(chB, 0, 0.8, 0.0);
    check("accessor chain created and valid", ch > 0 && b2lc_chain_is_valid(ch) == 1);
    b2lc_chain_set_friction(ch, 0.33);
    check("chain friction round-trips", fabs(b2lc_chain_friction(ch) - 0.33) < 1e-5);
    b2lc_chain_set_restitution(ch, 0.25);
    check("chain restitution round-trips", fabs(b2lc_chain_restitution(ch) - 0.25) < 1e-5);
    int chSegN = b2lc_chain_segment_count(ch);
    int chSeg0 = b2lc_chain_segment_at(0);
    check("the 6-point open chain still reports its 3 segments", chSegN == 3 && chSeg0 > 0);
    b2lc_chain_destroy(ch);
    check("a destroyed chain reads invalid with zeroed accessors",
          b2lc_chain_is_valid(ch) == 0 && b2lc_chain_friction(ch) == 0.0 &&
          b2lc_chain_segment_count(ch) == 0);
    check("destroying the chain retires its segment shape handles",
          b2lc_shape_body(chSeg0) == 0);
    b2lc_chain_destroy(ch);                        /* double-destroy: must be safe */
    b2lc_world_step(w5, 1.0 / 60.0, 4);
    check("simulation survives chain double-destroy", 1);
    b2lc_world_destroy(w5);
    check("query/event world destroyed cleanly", 1);

    /* --- generic joint surface (w6, region x=0) -----------------------------
       Joint type codes are pinned from Box2D v3.1.0's b2JointType enum
       (include/box2d/types.h): distance=0, filter=1, motor=2, mouse=3,
       prismatic=4, revolute=5, weld=6, wheel=7. The bob is centred ON its
       pivot (anchor B deliberately 0,0 -- written, not defaulted) so it HANGS
       instead of swinging and the constraint force is just its weight. */
    int w6 = b2lc_world_create(0.0, -10.0, 1, 1);
    check("joint world created", w6 > 0);
    int gjA = b2lc_body_create(w6, 0, 0.0, 10.0, 0.0, 0, 0);
    int gjB = b2lc_body_create(w6, 2, 0.25, 10.5, 0.0, 0, 0);
    b2lc_shape_add_box(gjB, 0.3, 0.3, 1.0, 0.3, 0.0);   /* 0.36 kg */
    b2lc_body_enable_sleep(gjB, 0);   /* a slept joint would read stale forces */
    int gj = b2lc_joint_revolute(w6, gjA, gjB, 0.25, 0.5, 0.0, 0.0, 0);
    check("generic-surface revolute created", gj > 0);
    check("joint_type reports revolute (5)", b2lc_joint_type(gj) == 5);
    check("joint_body_a/b return the two body handles",
          b2lc_joint_body_a(gj) == gjA && b2lc_joint_body_b(gj) == gjB);
    check("local anchors read back what the constructor was given",
          fabs(b2lc_joint_local_anchor_a_x(gj) - 0.25) < 1e-5 &&
          fabs(b2lc_joint_local_anchor_a_y(gj) - 0.5) < 1e-5 &&
          fabs(b2lc_joint_local_anchor_b_x(gj)) < 1e-5 &&
          fabs(b2lc_joint_local_anchor_b_y(gj)) < 1e-5);
    check("collide-connected defaults off", b2lc_joint_get_collide_connected(gj) == 0);
    b2lc_joint_set_collide_connected(gj, 1);
    check("set_collide_connected(1) reads back", b2lc_joint_get_collide_connected(gj) == 1);
    b2lc_joint_set_collide_connected(gj, 0);
    b2lc_body_set_awake(gjB, 0);
    check("the bob can be put to sleep by hand", b2lc_body_is_awake(gjB) == 0);
    b2lc_joint_wake_bodies(gj);
    check("joint_wake_bodies wakes the bob", b2lc_body_is_awake(gjB) == 1);
    for (int i = 0; i < 90; i++) b2lc_world_step(w6, 1.0 / 60.0, 4);
    /* the pivot carries the hanging bob: |F| ~ m*g = 3.6 N; a free pivot
       carries next to no torque, so the torque assertion is only "a defined
       number came back", which is all this register can promise here */
    {
        double cfx = b2lc_joint_constraint_force_x(gj), cfy = b2lc_joint_constraint_force_y(gj);
        double cmag = sqrt(cfx * cfx + cfy * cfy);
        check("the pivot's constraint force carries the bob's weight", cmag > 1.0 && cmag < 20.0);
        check("constraint torque of a free pivot reads as a small number",
              fabs(b2lc_joint_constraint_torque(gj)) < 10.0);
    }
    b2lc_joint_destroy(gj);
    check("a destroyed revolute reads type 0, not 5 (handle retired)", b2lc_joint_type(gj) == 0);
    check("the bob no longer counts a joint", b2lc_body_joint_count(gjB) == 0);
    b2lc_joint_destroy(gj);                        /* double-destroy: must be safe */
    b2lc_world_step(w6, 1.0 / 60.0, 4);
    check("simulation survives joint double-destroy", 1);

    /* --- filter joint (w6, region x=10) ------------------------------------- */
    int fjA = b2lc_body_create(w6, 2, 10.0, 10.0, 0.0, 0, 0);
    b2lc_shape_add_box(fjA, 0.5, 0.5, 1.0, 0.3, 0.0);
    int fjB = b2lc_body_create(w6, 2, 10.0, 10.0, 0.0, 0, 0);
    b2lc_shape_add_box(fjB, 0.5, 0.5, 1.0, 0.3, 0.0);
    b2lc_body_set_gravity_scale(fjA, 0.0);
    b2lc_body_set_gravity_scale(fjB, 0.0);
    int fj = b2lc_joint_filter(w6, fjA, fjB);
    check("filter joint created", fj > 0);
    check("joint_type reports filter (1)", b2lc_joint_type(fj) == 1);
    int fjTouched = 0;
    for (int i = 0; i < 30; i++) {
        b2lc_world_step(w6, 1.0 / 60.0, 4);
        int cn = b2lc_contacts_update(w6);
        for (int k = 0; k < cn; k++) {
            int a = b2lc_contact_begin_a(k), bb = b2lc_contact_begin_b(k);
            if ((a == fjA && bb == fjB) || (a == fjB && bb == fjA)) fjTouched = 1;
        }
    }
    check("filter-jointed coincident boxes never begin a contact", fjTouched == 0);

    /* --- revolute joint: granular get/set (w6, region x=20) ----------------- */
    int rvA = b2lc_body_create(w6, 0, 20.0, 10.0, 0.0, 0, 0);
    int rvB = b2lc_body_create(w6, 2, 21.0, 10.0, 0.0, 0, 0);
    b2lc_shape_add_box(rvB, 0.4, 0.1, 1.0, 0.3, 0.0);   /* 0.16 kg bar, arm 1m */
    b2lc_body_enable_sleep(rvB, 0);
    b2lc_body_set_angular_damping(rvB, 1.0);   /* settle onto the limit, not bounce */
    int rv = b2lc_joint_revolute(w6, rvA, rvB, 0.0, 0.0, -1.0, 0.0, 0);
    check("granular revolute created", rv > 0);
    b2lc_revolute_enable_spring(rv, 1);
    check("revolute spring flag round-trips on", b2lc_revolute_is_spring_enabled(rv) == 1);
    b2lc_revolute_set_spring_hertz(rv, 4.5);
    check("revolute spring hertz round-trips", fabs(b2lc_revolute_spring_hertz(rv) - 4.5) < 1e-5);
    b2lc_revolute_set_spring_damping(rv, 0.6);
    check("revolute spring damping round-trips", fabs(b2lc_revolute_spring_damping(rv) - 0.6) < 1e-5);
    b2lc_revolute_enable_spring(rv, 0);
    check("revolute spring flag round-trips off", b2lc_revolute_is_spring_enabled(rv) == 0);
    b2lc_revolute_enable_limit(rv, 1, -0.3, 0.5);
    check("revolute limit flag + bounds round-trip",
          b2lc_revolute_is_limit_enabled(rv) == 1 &&
          fabs(b2lc_revolute_lower_limit(rv) + 0.3) < 1e-5 &&
          fabs(b2lc_revolute_upper_limit(rv) - 0.5) < 1e-5);
    b2lc_revolute_enable_motor(rv, 1, 1.5, 50.0);
    check("revolute motor flag + speed + max torque round-trip",
          b2lc_revolute_is_motor_enabled(rv) == 1 &&
          fabs(b2lc_revolute_motor_speed(rv) - 1.5) < 1e-5 &&
          fabs(b2lc_revolute_max_motor_torque(rv) - 50.0) < 1e-5);
    b2lc_revolute_set_motor_speed(rv, 0.0);
    check("set_motor_speed(0) makes the motor a brake", b2lc_revolute_motor_speed(rv) == 0.0);
    b2lc_revolute_set_max_motor_torque(rv, 80.0);
    check("set_max_motor_torque round-trips", fabs(b2lc_revolute_max_motor_torque(rv) - 80.0) < 1e-5);
    /* the speed-0 motor holds the horizontal bar against its 1.6 Nm gravity
       torque, so the meter must show real torque and the angle must not fall */
    for (int i = 0; i < 60; i++) b2lc_world_step(w6, 1.0 / 60.0, 4);
    check("the braking motor holds the bar horizontal", fabs(b2lc_revolute_angle(rv)) < 0.1);
    check("motor_torque shows the load the brake carries", fabs(b2lc_revolute_motor_torque(rv)) > 0.2);
    b2lc_revolute_enable_motor(rv, 0, 0.0, 0.0);
    check("revolute motor flag round-trips off", b2lc_revolute_is_motor_enabled(rv) == 0);
    /* released, gravity swings the bar down until the lower limit stops it */
    for (int i = 0; i < 180; i++) b2lc_world_step(w6, 1.0 / 60.0, 4);
    check("the released bar rests on the lower limit",
          fabs(b2lc_revolute_angle(rv) + 0.3) < 0.05);

    /* --- prismatic joint: granular get/set (w6, region x=30) ---------------- */
    int prA = b2lc_body_create(w6, 0, 30.0, 10.0, 0.0, 0, 0);
    int prB = b2lc_body_create(w6, 2, 30.0, 10.0, 0.0, 0, 0);
    b2lc_shape_add_box(prB, 0.3, 0.3, 1.0, 0.3, 0.0);   /* 0.36 kg slider */
    b2lc_body_enable_sleep(prB, 0);
    b2lc_body_set_linear_damping(prB, 1.0);
    int pr = b2lc_joint_prismatic(w6, prA, prB, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0);
    check("granular prismatic created (vertical axis)", pr > 0);
    check("joint_type reports prismatic (4)", b2lc_joint_type(pr) == 4);
    b2lc_prismatic_enable_spring(pr, 1);
    check("prismatic spring flag round-trips on", b2lc_prismatic_is_spring_enabled(pr) == 1);
    b2lc_prismatic_set_spring_hertz(pr, 3.0);
    check("prismatic spring hertz round-trips", fabs(b2lc_prismatic_spring_hertz(pr) - 3.0) < 1e-5);
    b2lc_prismatic_set_spring_damping(pr, 0.4);
    check("prismatic spring damping round-trips", fabs(b2lc_prismatic_spring_damping(pr) - 0.4) < 1e-5);
    b2lc_prismatic_enable_spring(pr, 0);
    check("prismatic spring flag round-trips off", b2lc_prismatic_is_spring_enabled(pr) == 0);
    b2lc_prismatic_enable_limit(pr, 1, -0.5, 0.5);
    check("prismatic limit flag + bounds round-trip",
          b2lc_prismatic_is_limit_enabled(pr) == 1 &&
          fabs(b2lc_prismatic_lower_limit(pr) + 0.5) < 1e-5 &&
          fabs(b2lc_prismatic_upper_limit(pr) - 0.5) < 1e-5);
    b2lc_prismatic_enable_motor(pr, 1, 2.0, 100.0);
    check("prismatic motor flag + speed + max force round-trip",
          b2lc_prismatic_is_motor_enabled(pr) == 1 &&
          fabs(b2lc_prismatic_motor_speed(pr) - 2.0) < 1e-5 &&
          fabs(b2lc_prismatic_max_motor_force(pr) - 100.0) < 1e-5);
    b2lc_prismatic_set_motor_speed(pr, 0.0);
    check("prismatic set_motor_speed round-trips", b2lc_prismatic_motor_speed(pr) == 0.0);
    /* the speed-0 motor holds the slider against its 3.6 N weight */
    for (int i = 0; i < 60; i++) b2lc_world_step(w6, 1.0 / 60.0, 4);
    check("the braking motor holds the slider in place", fabs(b2lc_prismatic_translation(pr)) < 0.05);
    check("motor_force shows the weight the brake carries", fabs(b2lc_prismatic_motor_force(pr)) > 1.0);
    b2lc_prismatic_enable_motor(pr, 0, 0.0, 0.0);
    check("prismatic motor flag round-trips off", b2lc_prismatic_is_motor_enabled(pr) == 0);
    for (int i = 0; i < 6; i++) b2lc_world_step(w6, 1.0 / 60.0, 4);
    check("the released slider is falling along the axis", b2lc_prismatic_speed(pr) < -0.2);
    for (int i = 0; i < 150; i++) b2lc_world_step(w6, 1.0 / 60.0, 4);
    check("the released slider rests on the lower limit",
          fabs(b2lc_prismatic_translation(pr) + 0.5) < 0.05);

    /* --- distance joint: granular get/set (w6, region x=40) ----------------- */
    int diA = b2lc_body_create(w6, 0, 40.0, 12.0, 0.0, 0, 0);
    int diB = b2lc_body_create(w6, 2, 40.0, 10.0, 0.0, 0, 0);
    b2lc_shape_add_box(diB, 0.25, 0.25, 1.0, 0.3, 0.0);   /* 0.25 kg bob */
    b2lc_body_enable_sleep(diB, 0);
    int di = b2lc_joint_distance(w6, diA, diB, 0.0, 0.0, 0.0, 0.0, 2.0, 0);
    check("granular distance joint created", di > 0);
    check("distance_length reads the constructed length", fabs(b2lc_distance_length(di) - 2.0) < 1e-5);
    b2lc_distance_set_length(di, 2.5);
    check("set_length round-trips", fabs(b2lc_distance_length(di) - 2.5) < 1e-5);
    b2lc_distance_set_length_range(di, 1.0, 3.0);
    check("set_length_range enables the limit and stores both bounds",
          b2lc_distance_is_limit_enabled(di) == 1 &&
          fabs(b2lc_distance_min_length(di) - 1.0) < 1e-5 &&
          fabs(b2lc_distance_max_length(di) - 3.0) < 1e-5);
    b2lc_distance_enable_spring(di, 1, 1.5, 0.25);
    check("distance spring flag + hertz + damping round-trip",
          b2lc_distance_is_spring_enabled(di) == 1 &&
          fabs(b2lc_distance_spring_hertz(di) - 1.5) < 1e-5 &&
          fabs(b2lc_distance_spring_damping(di) - 0.25) < 1e-5);
    b2lc_distance_enable_motor(di, 1);
    check("distance motor flag round-trips on", b2lc_distance_is_motor_enabled(di) == 1);
    b2lc_distance_set_motor_speed(di, 0.5);
    check("distance motor speed round-trips", fabs(b2lc_distance_motor_speed(di) - 0.5) < 1e-5);
    b2lc_distance_set_max_motor_force(di, 100.0);
    check("distance max motor force round-trips", fabs(b2lc_distance_max_motor_force(di) - 100.0) < 1e-5);
    b2lc_distance_set_motor_speed(di, 0.0);
    /* Box2D v3.1 solves the distance MOTOR only in soft (spring) mode, and a
       0-hertz spring contributes no force of its own -- so with the spring
       "on" at 0 Hz the speed-0 motor alone carries the hanging bob. A speed
       brake holds the CURRENT separation (2.0m, where the bob spawned), not
       the 2.5m rest length; the meter must show the bob's 2.5 N weight. */
    b2lc_distance_enable_spring(di, 1, 0.0, 0.0);
    for (int i = 0; i < 90; i++) b2lc_world_step(w6, 1.0 / 60.0, 4);
    check("the braking distance motor holds the spawn separation",
          fabs(b2lc_distance_current_length(di) - 2.0) < 0.15);
    check("distance motor_force shows the bob's weight", fabs(b2lc_distance_motor_force(di)) > 1.0);

    /* --- weld joint: granular get/set (w6, region x=50) --------------------- */
    int weA = b2lc_body_create(w6, 2, 50.0, 10.0, 0.0, 0, 0);
    b2lc_shape_add_box(weA, 0.3, 0.3, 1.0, 0.3, 0.0);
    int weB = b2lc_body_create(w6, 2, 51.0, 10.0, 0.0, 0, 0);
    b2lc_shape_add_box(weB, 0.3, 0.3, 1.0, 0.3, 0.0);
    b2lc_body_set_gravity_scale(weA, 0.0);
    b2lc_body_set_gravity_scale(weB, 0.0);
    int we = b2lc_joint_weld(w6, weA, weB, 0.0, 0.0, -1.0, 0.0, 0.25, 0);
    check("granular weld created", we > 0);
    check("joint_type reports weld (6)", b2lc_joint_type(we) == 6);
    check("weld reference angle reads the constructed value",
          fabs(b2lc_weld_reference_angle(we) - 0.25) < 1e-5);
    b2lc_weld_set_reference_angle(we, 0.1);
    check("set_reference_angle round-trips", fabs(b2lc_weld_reference_angle(we) - 0.1) < 1e-5);
    b2lc_weld_set_stiffness(we, 3.0, 0.5, 4.0, 0.8);
    check("weld stiffness pack round-trips through all four getters",
          fabs(b2lc_weld_linear_hertz(we) - 3.0) < 1e-5 &&
          fabs(b2lc_weld_linear_damping(we) - 0.5) < 1e-5 &&
          fabs(b2lc_weld_angular_hertz(we) - 4.0) < 1e-5 &&
          fabs(b2lc_weld_angular_damping(we) - 0.8) < 1e-5);

    /* --- wheel joint: granular get/set (w6, region x=60) -------------------- */
    int whA = b2lc_body_create(w6, 0, 60.0, 10.0, 0.0, 0, 0);
    int whB = b2lc_body_create(w6, 2, 60.0, 10.0, 0.0, 0, 0);
    b2lc_shape_add_circle(whB, 0.0, 0.0, 0.3, 1.0, 0.3, 0.0);
    b2lc_body_set_gravity_scale(whB, 0.0);
    /* angular damping is the motor's LOAD: an unloaded wheel reaches its motor
       speed inside the first step and the torque meter then reads ~0 (measured
       before this fixture landed), so the damped steady state -- where the
       motor re-supplies the damping loss every step -- is what makes the meter
       assertable at all */
    b2lc_body_set_angular_damping(whB, 5.0);
    int wh = b2lc_joint_wheel(w6, whA, whB, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0);
    check("granular wheel created", wh > 0);
    check("joint_type reports wheel (7)", b2lc_joint_type(wh) == 7);
    b2lc_wheel_enable_spring(wh, 1, 4.0, 0.7);
    check("wheel spring flag + hertz + damping round-trip",
          b2lc_wheel_is_spring_enabled(wh) == 1 &&
          fabs(b2lc_wheel_spring_hertz(wh) - 4.0) < 1e-5 &&
          fabs(b2lc_wheel_spring_damping(wh) - 0.7) < 1e-5);
    b2lc_wheel_enable_limit(wh, 1);
    check("wheel limit flag round-trips on", b2lc_wheel_is_limit_enabled(wh) == 1);
    b2lc_wheel_set_limits(wh, -0.25, 0.25);
    check("wheel set_limits round-trips both bounds",
          fabs(b2lc_wheel_lower_limit(wh) + 0.25) < 1e-5 &&
          fabs(b2lc_wheel_upper_limit(wh) - 0.25) < 1e-5);
    b2lc_wheel_enable_motor(wh, 1, 5.0, 20.0);
    check("wheel motor flag + speed + max torque round-trip",
          b2lc_wheel_is_motor_enabled(wh) == 1 &&
          fabs(b2lc_wheel_motor_speed(wh) - 5.0) < 1e-5 &&
          fabs(b2lc_wheel_max_motor_torque(wh) - 20.0) < 1e-5);
    /* after a second of steps the damped wheel must be turning near its
       5 rad/s motor speed (the motor working end-to-end, read off the BODY)
       while the torque meter shows the sustained effort against the damping
       (measured 0.31 Nm at this inertia and damping) */
    for (int i = 0; i < 60; i++) b2lc_world_step(w6, 1.0 / 60.0, 4);
    check("the wheel spins near its motor speed", b2lc_body_omega(whB) > 2.0);
    check("wheel motor_torque shows the sustained effort against its load",
          fabs(b2lc_wheel_motor_torque(wh)) > 0.05);

    /* --- motor joint: granular get/set (w6, region x=70) -------------------- */
    int moA = b2lc_body_create(w6, 0, 70.0, 10.0, 0.0, 0, 0);
    int moB = b2lc_body_create(w6, 2, 70.0, 10.0, 0.0, 0, 0);
    b2lc_shape_add_box(moB, 0.3, 0.3, 1.0, 0.3, 0.0);
    b2lc_body_set_gravity_scale(moB, 0.0);
    int mo = b2lc_joint_motor(w6, moA, moB, 0.0, 0.0, 0.0, 100.0, 50.0, 0.3, 0);
    check("granular motor joint created", mo > 0);
    check("joint_type reports motor (2)", b2lc_joint_type(mo) == 2);
    b2lc_motor_set_linear_offset(mo, 2.0, 1.0);
    check("motor linear offset round-trips",
          fabs(b2lc_motor_linear_offset_x(mo) - 2.0) < 1e-5 &&
          fabs(b2lc_motor_linear_offset_y(mo) - 1.0) < 1e-5);
    b2lc_motor_set_angular_offset(mo, 0.3);
    check("motor angular offset round-trips", fabs(b2lc_motor_angular_offset(mo) - 0.3) < 1e-5);
    b2lc_motor_set_max_force(mo, 500.0);
    check("motor max force round-trips", fabs(b2lc_motor_max_force(mo) - 500.0) < 1e-5);
    b2lc_motor_set_max_torque(mo, 80.0);
    check("motor max torque round-trips", fabs(b2lc_motor_max_torque(mo) - 80.0) < 1e-5);
    b2lc_motor_set_correction_factor(mo, 0.5);
    check("motor correction factor round-trips", fabs(b2lc_motor_correction_factor(mo) - 0.5) < 1e-5);

    /* --- mouse joint: granular get/set (w6, region x=80) -------------------- */
    int muA = b2lc_body_create(w6, 0, 80.0, 10.0, 0.0, 0, 0);
    int muB = b2lc_body_create(w6, 2, 80.0, 10.0, 0.0, 0, 0);
    b2lc_shape_add_box(muB, 0.3, 0.3, 1.0, 0.3, 0.0);
    int mu = b2lc_joint_mouse(w6, muA, muB, 80.0, 10.0, 5.0, 0.7, 900.0);
    check("granular mouse joint created", mu > 0);
    check("joint_type reports mouse (3)", b2lc_joint_type(mu) == 3);
    check("mouse target reads the constructed point",
          fabs(b2lc_mouse_target_x(mu) - 80.0) < 1e-5 &&
          fabs(b2lc_mouse_target_y(mu) - 10.0) < 1e-5);
    b2lc_mouse_set_target(mu, 82.5, 11.0);
    check("mouse set_target round-trips through both getters",
          fabs(b2lc_mouse_target_x(mu) - 82.5) < 1e-5 &&
          fabs(b2lc_mouse_target_y(mu) - 11.0) < 1e-5);
    b2lc_mouse_set_spring_hertz(mu, 6.0);
    check("mouse spring hertz round-trips", fabs(b2lc_mouse_spring_hertz(mu) - 6.0) < 1e-5);
    b2lc_mouse_set_spring_damping(mu, 0.9);
    check("mouse spring damping round-trips", fabs(b2lc_mouse_spring_damping(mu) - 0.9) < 1e-5);
    b2lc_mouse_set_max_force(mu, 750.0);
    check("mouse max force round-trips", fabs(b2lc_mouse_max_force(mu) - 750.0) < 1e-5);

    b2lc_world_destroy(w6);
    check("joint world destroyed cleanly", 1);
    /* world destroy retires every child joint with the bodies: the per-kind
       getters must answer 0 off a dead handle, never reach into freed state */
    check("world destroy leaves the joint-family getters harmless",
          b2lc_distance_length(di) == 0.0 && b2lc_mouse_max_force(mu) == 0.0 &&
          b2lc_wheel_spring_hertz(wh) == 0.0 && b2lc_revolute_angle(rv) == 0.0 &&
          b2lc_joint_type(mo) == 0);

    printf("\n==== %d passed, %d failed ====\n", g_pass, g_fail);
    return g_fail == 0 ? 0 : 1;
}
