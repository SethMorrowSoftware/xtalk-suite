/*
 * fuzz_test.c - random calls into every export of the box3dxt shim.
 *
 * The smoke test asks "does each call do what the page says". This one asks
 * the question a script author answers by accident: what happens when ANY
 * call is given ANY value, in any order - a dead handle, a body of another
 * world, NaN, infinity, 1e300, a joint call on the wrong joint type, a world
 * stepped between two halves of a setup. The contract of the binding is that
 * none of it can crash the host or poison a world:
 *
 *   - no call faults (the run is built with ASan/UBSan in CI, and in a Debug
 *     build Box3D's own asserts are live, so an argument the shim let through
 *     that Box3D rejects stops the run by name);
 *   - no text result is NULL, and none ever spells "nan" or "inf";
 *   - no number result is NaN or infinite.
 *
 * The call list is GENERATED from the shim's signatures (tools/check-smoke-
 * coverage.py --write fills the block below and the gate holds it), so a new
 * export is fuzzed the day it is written. Arguments are drawn by PARAMETER
 * NAME: `b` is usually a live body, sometimes a stale one, a shape, 0 or
 * noise; a double is usually a sane number and sometimes a hostile one.
 *
 * Deterministic: the generator is a fixed xorshift, so a seed that fails
 * here fails the same way everywhere (bar the platform's float rounding).
 *
 *     box3dxt_fuzz [seed [calls]]      default: seeds 1..3, 60000 calls each
 *     box3dxt_fuzz --replay FILE       make the calls of a trace again
 *     FUZZ_TRACE=1  print each call    FUZZ_AUDIT=1  check every body after each call
 */
#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* >>> BEGIN SHIM DECLARATIONS (generated: tools/check-smoke-coverage.py --write) >>> */
/* 380 exports, in the shim's order. Plain declarations: the test is a client of
 * the built library, exactly as the engine's FFI is. */
extern int b3x_abi_version(void);
extern const char*b3x_library_version(void);
extern const char*b3x_last_error(void);
extern int b3x_text_length(const char*text);
extern int b3x_assert_count(void);
extern const char*b3x_assert_text(void);
extern int b3x_has_avx2(void);
extern int b3x_world_create(double gx, double gy, double gz, int workers);
extern void b3x_world_destroy(int w);
extern int b3x_world_is_valid(int w);
extern int b3x_unstable_count(void);
extern void b3x_world_step(int w, double dt, int substeps);
extern void b3x_world_set_gravity(int w, double gx, double gy, double gz);
extern const char*b3x_world_gravity(int w);
extern void b3x_world_enable_sleeping(int w, int flag);
extern int b3x_world_is_sleeping_enabled(int w);
extern void b3x_world_enable_continuous(int w, int flag);
extern int b3x_world_is_continuous_enabled(int w);
extern void b3x_world_set_restitution_threshold(int w, double v);
extern double b3x_world_restitution_threshold(int w);
extern void b3x_world_set_hit_event_threshold(int w, double v);
extern double b3x_world_hit_event_threshold(int w);
extern void b3x_world_set_contact_tuning(int w, double hertz, double damping, double speed);
extern void b3x_world_set_max_linear_speed(int w, double v);
extern double b3x_world_max_linear_speed(int w);
extern void b3x_world_set_worker_count(int w, int workers);
extern int b3x_world_worker_count(int w);
extern int b3x_world_body_count(int w);
extern int b3x_world_shape_count(int w);
extern int b3x_world_joint_count(int w);
extern int b3x_world_contact_count(int w);
extern int b3x_world_awake_body_count(int w);
extern double b3x_world_step_ms(int w);
extern const char*b3x_world_bounds(int w);
extern void b3x_world_explode(int w, double x, double y, double z, double radius, double falloff, double impulse);
extern int b3x_body_create(int w, int type, double x, double y, double z);
extern int b3x_body_create_rotated(int w, int type, double x, double y, double z, double qx, double qy, double qz, double qw);
extern void b3x_body_destroy(int b);
extern int b3x_body_is_valid(int b);
extern int b3x_body_type(int b);
extern void b3x_body_set_type(int b, int type);
extern int b3x_body_world(int b);
extern const char*b3x_body_position(int b);
extern double b3x_body_x(int b);
extern double b3x_body_y(int b);
extern double b3x_body_z(int b);
extern const char*b3x_body_rotation(int b);
extern const char*b3x_body_transform(int b);
extern const char*b3x_body_matrix(int b);
extern void b3x_body_set_transform(int b, double x, double y, double z, double qx, double qy, double qz, double qw);
extern void b3x_body_set_position(int b, double x, double y, double z);
extern void b3x_body_set_rotation(int b, double qx, double qy, double qz, double qw);
extern void b3x_body_set_target_transform(int b, double x, double y, double z, double qx, double qy, double qz, double qw, double dt, int wake);
extern const char*b3x_body_velocity(int b);
extern const char*b3x_body_angular_velocity(int b);
extern double b3x_body_speed(int b);
extern void b3x_body_set_velocity(int b, double vx, double vy, double vz);
extern void b3x_body_set_angular_velocity(int b, double wx, double wy, double wz);
extern void b3x_body_apply_force(int b, double fx, double fy, double fz, double px, double py, double pz, int wake);
extern void b3x_body_apply_force_to_center(int b, double fx, double fy, double fz, int wake);
extern void b3x_body_apply_torque(int b, double tx, double ty, double tz, int wake);
extern void b3x_body_apply_impulse(int b, double ix, double iy, double iz, double px, double py, double pz, int wake);
extern void b3x_body_apply_impulse_to_center(int b, double ix, double iy, double iz, int wake);
extern void b3x_body_apply_angular_impulse(int b, double ix, double iy, double iz, int wake);
extern double b3x_body_mass(int b);
extern void b3x_body_apply_mass_from_shapes(int b);
extern const char*b3x_body_local_center(int b);
extern const char*b3x_body_world_center(int b);
extern const char*b3x_body_local_point(int b, double x, double y, double z);
extern const char*b3x_body_world_point(int b, double x, double y, double z);
extern const char*b3x_body_local_vector(int b, double x, double y, double z);
extern const char*b3x_body_world_vector(int b, double x, double y, double z);
extern const char*b3x_body_point_velocity(int b, double x, double y, double z);
extern void b3x_body_set_linear_damping(int b, double v);
extern double b3x_body_linear_damping(int b);
extern void b3x_body_set_angular_damping(int b, double v);
extern double b3x_body_angular_damping(int b);
extern void b3x_body_set_gravity_scale(int b, double v);
extern double b3x_body_gravity_scale(int b);
extern int b3x_body_is_awake(int b);
extern void b3x_body_set_awake(int b, int flag);
extern void b3x_body_enable_sleep(int b, int flag);
extern int b3x_body_is_sleep_enabled(int b);
extern void b3x_body_set_sleep_threshold(int b, double v);
extern double b3x_body_sleep_threshold(int b);
extern int b3x_body_is_enabled(int b);
extern void b3x_body_enable(int b);
extern void b3x_body_disable(int b);
extern void b3x_body_set_bullet(int b, int flag);
extern int b3x_body_is_bullet(int b);
extern void b3x_body_set_motion_locks(int b, int lx, int ly, int lz, int ax, int ay, int az);
extern const char*b3x_body_motion_locks(int b);
extern void b3x_body_enable_hit_events(int b, int flag);
extern const char*b3x_body_aabb(int b);
extern int b3x_body_shape_count(int b);
extern int b3x_body_joint_count(int b);
extern int b3x_list_count(void);
extern int b3x_list_item(int index);
extern int b3x_body_list_shapes(int b);
extern int b3x_body_list_joints(int b);
extern int b3x_body_list_touching(int b);
extern void b3x_shape_options_reset(void);
extern void b3x_shape_options_set_sensor(int flag);
extern void b3x_shape_options_set_events(int contact, int hit, int sensor);
extern void b3x_shape_options_set_filter(double category, double mask, int group);
extern void b3x_shape_options_set_rolling_resistance(double v);
extern void b3x_geometry_begin(void);
extern int b3x_geometry_add_point(double x, double y, double z);
extern int b3x_geometry_add_triangle(int p1, int p2, int p3);
extern int b3x_geometry_add_height(double h);
extern int b3x_geometry_point_count(void);
extern int b3x_shape_add_sphere(int b, double cx, double cy, double cz, double radius, double density, double friction, double restitution);
extern int b3x_shape_add_capsule(int b, double x1, double y1, double z1, double x2, double y2, double z2, double radius, double density, double friction, double restitution);
extern int b3x_shape_add_box(int b, double hx, double hy, double hz, double density, double friction, double restitution);
extern int b3x_shape_add_box_at(int b, double hx, double hy, double hz, double ox, double oy, double oz, double qx, double qy, double qz, double qw, double density, double friction, double restitution);
extern int b3x_shape_add_cylinder(int b, double height, double radius, int sides, double density, double friction, double restitution);
extern int b3x_shape_add_cone(int b, double height, double radius1, double radius2, int sides, double density, double friction, double restitution);
extern int b3x_shape_add_hull(int b, double density, double friction, double restitution);
extern int b3x_shape_add_mesh(int b, double friction, double restitution);
extern int b3x_shape_add_height_field(int b, int countX, int countZ, double sx, double sy, double sz, double friction, double restitution);
extern void b3x_shape_destroy(int s, int updateMass);
extern int b3x_shape_is_valid(int s);
extern int b3x_shape_type(int s);
extern int b3x_shape_body(int s);
extern int b3x_shape_is_sensor(int s);
extern void b3x_shape_set_density(int s, double v, int updateMass);
extern double b3x_shape_density(int s);
extern void b3x_shape_set_friction(int s, double v);
extern double b3x_shape_friction(int s);
extern void b3x_shape_set_restitution(int s, double v);
extern double b3x_shape_restitution(int s);
extern void b3x_shape_set_rolling_resistance(int s, double v);
extern double b3x_shape_rolling_resistance(int s);
extern void b3x_shape_set_filter(int s, double category, double mask, int group);
extern const char*b3x_shape_filter(int s);
extern void b3x_shape_enable_contact_events(int s, int flag);
extern int b3x_shape_are_contact_events_enabled(int s);
extern void b3x_shape_enable_hit_events(int s, int flag);
extern int b3x_shape_are_hit_events_enabled(int s);
extern void b3x_shape_enable_sensor_events(int s, int flag);
extern int b3x_shape_are_sensor_events_enabled(int s);
extern const char*b3x_shape_aabb(int s);
extern const char*b3x_shape_closest_point(int s, double x, double y, double z);
extern int b3x_shape_list_sensor_visitors(int s);
extern void b3x_query_set_filter(double category, double mask);
extern void b3x_query_reset_filter(void);
extern int b3x_cast_ray(int w, double ox, double oy, double oz, double dx, double dy, double dz);
extern int b3x_cast_ray_closest(int w, double ox, double oy, double oz, double dx, double dy, double dz);
extern int b3x_cast_sphere(int w, double ox, double oy, double oz, double radius, double dx, double dy, double dz);
extern int b3x_hit_count(void);
extern int b3x_hit_shape(int index);
extern int b3x_hit_body(int index);
extern double b3x_hit_fraction(int index);
extern const char*b3x_hit_point(int index);
extern const char*b3x_hit_normal(int index);
extern int b3x_overlap_aabb(int w, double lx, double ly, double lz, double ux, double uy, double uz);
extern int b3x_overlap_sphere(int w, double x, double y, double z, double radius);
extern int b3x_world_update_contact_events(int w);
extern int b3x_contact_begin_count(void);
extern int b3x_contact_begin_shape_a(int index);
extern int b3x_contact_begin_shape_b(int index);
extern int b3x_contact_end_count(void);
extern int b3x_contact_end_shape_a(int index);
extern int b3x_contact_end_shape_b(int index);
extern int b3x_contact_hit_count(void);
extern int b3x_contact_hit_shape_a(int index);
extern int b3x_contact_hit_shape_b(int index);
extern double b3x_contact_hit_speed(int index);
extern const char*b3x_contact_hit_point(int index);
extern const char*b3x_contact_hit_normal(int index);
extern int b3x_world_update_sensor_events(int w);
extern int b3x_sensor_begin_count(void);
extern int b3x_sensor_begin_sensor(int index);
extern int b3x_sensor_begin_visitor(int index);
extern int b3x_sensor_end_count(void);
extern int b3x_sensor_end_sensor(int index);
extern int b3x_sensor_end_visitor(int index);
extern int b3x_world_update_moves(int w);
extern int b3x_move_count(void);
extern int b3x_move_body(int index);
extern int b3x_move_fell_asleep(int index);
extern const char*b3x_move_transform(int index);
extern const char*b3x_moves_text(void);
extern int b3x_world_update_joint_events(int w);
extern int b3x_joint_event_count(void);
extern int b3x_joint_event_joint(int index);
extern const char*b3x_quat_from_axis_angle(double ax, double ay, double az, double radians);
extern const char*b3x_quat_from_euler(double rx, double ry, double rz);
extern const char*b3x_quat_multiply(double ax, double ay, double az, double aw, double bx, double by, double bz, double bw);
extern const char*b3x_quat_rotate(double qx, double qy, double qz, double qw, double x, double y, double z);
extern const char*b3x_quat_to_axis_angle(double qx, double qy, double qz, double qw);
extern int b3x_joint_revolute(int w, int ba, int bb, double px, double py, double pz, double ax, double ay, double az, int collide);
extern int b3x_joint_prismatic(int w, int ba, int bb, double px, double py, double pz, double ax, double ay, double az, int collide);
extern int b3x_joint_spherical(int w, int ba, int bb, double px, double py, double pz, double ax, double ay, double az, int collide);
extern int b3x_joint_weld(int w, int ba, int bb, double px, double py, double pz, int collide);
extern int b3x_joint_distance(int w, int ba, int bb, double ax, double ay, double az, double bx, double by, double bz, int collide);
extern int b3x_joint_wheel(int w, int ba, int bb, double px, double py, double pz, double ux, double uy, double uz, double sx, double sy, double sz, int collide);
extern int b3x_joint_motor(int w, int ba, int bb, int collide);
extern int b3x_joint_parallel(int w, int ba, int bb, double ax, double ay, double az, int collide);
extern int b3x_joint_filter(int w, int ba, int bb);
extern void b3x_joint_destroy(int j, int wake);
extern int b3x_joint_is_valid(int j);
extern int b3x_joint_type(int j);
extern int b3x_joint_body_a(int j);
extern int b3x_joint_body_b(int j);
extern void b3x_joint_set_collide_connected(int j, int flag);
extern int b3x_joint_collide_connected(int j);
extern void b3x_joint_wake_bodies(int j);
extern const char*b3x_joint_local_frame_a(int j);
extern const char*b3x_joint_local_frame_b(int j);
extern void b3x_joint_set_local_frame_a(int j, double x, double y, double z, double qx, double qy, double qz, double qw);
extern void b3x_joint_set_local_frame_b(int j, double x, double y, double z, double qx, double qy, double qz, double qw);
extern const char*b3x_joint_constraint_force(int j);
extern const char*b3x_joint_constraint_torque(int j);
extern double b3x_joint_linear_separation(int j);
extern double b3x_joint_angular_separation(int j);
extern void b3x_joint_set_force_threshold(int j, double v);
extern double b3x_joint_force_threshold(int j);
extern void b3x_joint_set_torque_threshold(int j, double v);
extern double b3x_joint_torque_threshold(int j);
extern void b3x_motor_set_linear_velocity(int j, double vx, double vy, double vz);
extern const char*b3x_motor_linear_velocity(int j);
extern void b3x_motor_set_angular_velocity(int j, double wx, double wy, double wz);
extern const char*b3x_motor_angular_velocity(int j);
extern void b3x_spherical_set_motor_velocity(int j, double wx, double wy, double wz);
extern const char*b3x_spherical_motor_velocity(int j);
extern const char*b3x_spherical_motor_torque(int j);
extern void b3x_spherical_set_target_rotation(int j, double qx, double qy, double qz, double qw);
extern const char*b3x_spherical_target_rotation(int j);
extern void b3x_revolute_set_limits(int j, double lower, double upper);
extern void b3x_prismatic_set_limits(int j, double lower, double upper);
extern void b3x_spherical_set_twist_limits(int j, double lower, double upper);
extern void b3x_distance_set_length_range(int j, double lower, double upper);
extern void b3x_wheel_set_suspension_limits(int j, double lower, double upper);
extern void b3x_wheel_set_steering_limits(int j, double lower, double upper);
extern void b3x_revolute_enable_spring(int j, int flag);
extern int b3x_revolute_is_spring_enabled(int j);
extern void b3x_revolute_set_spring_hertz(int j, double v);
extern double b3x_revolute_spring_hertz(int j);
extern void b3x_revolute_set_spring_damping_ratio(int j, double v);
extern double b3x_revolute_spring_damping_ratio(int j);
extern void b3x_revolute_set_target_angle(int j, double v);
extern double b3x_revolute_target_angle(int j);
extern double b3x_revolute_angle(int j);
extern void b3x_revolute_enable_limit(int j, int flag);
extern int b3x_revolute_is_limit_enabled(int j);
extern double b3x_revolute_lower_limit(int j);
extern double b3x_revolute_upper_limit(int j);
extern void b3x_revolute_enable_motor(int j, int flag);
extern int b3x_revolute_is_motor_enabled(int j);
extern void b3x_revolute_set_motor_speed(int j, double v);
extern double b3x_revolute_motor_speed(int j);
extern double b3x_revolute_motor_torque(int j);
extern void b3x_revolute_set_max_motor_torque(int j, double v);
extern double b3x_revolute_max_motor_torque(int j);
extern void b3x_prismatic_enable_spring(int j, int flag);
extern int b3x_prismatic_is_spring_enabled(int j);
extern void b3x_prismatic_set_spring_hertz(int j, double v);
extern double b3x_prismatic_spring_hertz(int j);
extern void b3x_prismatic_set_spring_damping_ratio(int j, double v);
extern double b3x_prismatic_spring_damping_ratio(int j);
extern void b3x_prismatic_set_target_translation(int j, double v);
extern double b3x_prismatic_target_translation(int j);
extern void b3x_prismatic_enable_limit(int j, int flag);
extern int b3x_prismatic_is_limit_enabled(int j);
extern double b3x_prismatic_lower_limit(int j);
extern double b3x_prismatic_upper_limit(int j);
extern void b3x_prismatic_enable_motor(int j, int flag);
extern int b3x_prismatic_is_motor_enabled(int j);
extern void b3x_prismatic_set_motor_speed(int j, double v);
extern double b3x_prismatic_motor_speed(int j);
extern void b3x_prismatic_set_max_motor_force(int j, double v);
extern double b3x_prismatic_max_motor_force(int j);
extern double b3x_prismatic_motor_force(int j);
extern double b3x_prismatic_translation(int j);
extern double b3x_prismatic_speed(int j);
extern void b3x_spherical_enable_cone_limit(int j, int flag);
extern int b3x_spherical_is_cone_limit_enabled(int j);
extern void b3x_spherical_set_cone_limit(int j, double v);
extern double b3x_spherical_cone_limit(int j);
extern double b3x_spherical_cone_angle(int j);
extern void b3x_spherical_enable_twist_limit(int j, int flag);
extern int b3x_spherical_is_twist_limit_enabled(int j);
extern double b3x_spherical_lower_twist_limit(int j);
extern double b3x_spherical_upper_twist_limit(int j);
extern double b3x_spherical_twist_angle(int j);
extern void b3x_spherical_enable_spring(int j, int flag);
extern int b3x_spherical_is_spring_enabled(int j);
extern void b3x_spherical_set_spring_hertz(int j, double v);
extern double b3x_spherical_spring_hertz(int j);
extern void b3x_spherical_set_spring_damping_ratio(int j, double v);
extern double b3x_spherical_spring_damping_ratio(int j);
extern void b3x_spherical_enable_motor(int j, int flag);
extern int b3x_spherical_is_motor_enabled(int j);
extern void b3x_spherical_set_max_motor_torque(int j, double v);
extern double b3x_spherical_max_motor_torque(int j);
extern void b3x_weld_set_linear_hertz(int j, double v);
extern double b3x_weld_linear_hertz(int j);
extern void b3x_weld_set_linear_damping_ratio(int j, double v);
extern double b3x_weld_linear_damping_ratio(int j);
extern void b3x_weld_set_angular_hertz(int j, double v);
extern double b3x_weld_angular_hertz(int j);
extern void b3x_weld_set_angular_damping_ratio(int j, double v);
extern double b3x_weld_angular_damping_ratio(int j);
extern void b3x_distance_set_length(int j, double v);
extern double b3x_distance_length(int j);
extern void b3x_distance_enable_spring(int j, int flag);
extern int b3x_distance_is_spring_enabled(int j);
extern void b3x_distance_set_spring_hertz(int j, double v);
extern double b3x_distance_spring_hertz(int j);
extern void b3x_distance_set_spring_damping_ratio(int j, double v);
extern double b3x_distance_spring_damping_ratio(int j);
extern void b3x_distance_enable_limit(int j, int flag);
extern int b3x_distance_is_limit_enabled(int j);
extern double b3x_distance_min_length(int j);
extern double b3x_distance_max_length(int j);
extern double b3x_distance_current_length(int j);
extern void b3x_distance_enable_motor(int j, int flag);
extern int b3x_distance_is_motor_enabled(int j);
extern void b3x_distance_set_motor_speed(int j, double v);
extern double b3x_distance_motor_speed(int j);
extern void b3x_distance_set_max_motor_force(int j, double v);
extern double b3x_distance_max_motor_force(int j);
extern double b3x_distance_motor_force(int j);
extern void b3x_wheel_enable_suspension(int j, int flag);
extern int b3x_wheel_is_suspension_enabled(int j);
extern void b3x_wheel_set_suspension_hertz(int j, double v);
extern double b3x_wheel_suspension_hertz(int j);
extern void b3x_wheel_set_suspension_damping_ratio(int j, double v);
extern double b3x_wheel_suspension_damping_ratio(int j);
extern void b3x_wheel_enable_suspension_limit(int j, int flag);
extern int b3x_wheel_is_suspension_limit_enabled(int j);
extern double b3x_wheel_lower_suspension_limit(int j);
extern double b3x_wheel_upper_suspension_limit(int j);
extern void b3x_wheel_enable_spin_motor(int j, int flag);
extern int b3x_wheel_is_spin_motor_enabled(int j);
extern void b3x_wheel_set_spin_motor_speed(int j, double v);
extern double b3x_wheel_spin_motor_speed(int j);
extern void b3x_wheel_set_max_spin_torque(int j, double v);
extern double b3x_wheel_max_spin_torque(int j);
extern double b3x_wheel_spin_speed(int j);
extern double b3x_wheel_spin_torque(int j);
extern void b3x_wheel_enable_steering(int j, int flag);
extern int b3x_wheel_is_steering_enabled(int j);
extern void b3x_wheel_set_steering_hertz(int j, double v);
extern double b3x_wheel_steering_hertz(int j);
extern void b3x_wheel_set_steering_damping_ratio(int j, double v);
extern double b3x_wheel_steering_damping_ratio(int j);
extern void b3x_wheel_set_max_steering_torque(int j, double v);
extern double b3x_wheel_max_steering_torque(int j);
extern void b3x_wheel_enable_steering_limit(int j, int flag);
extern int b3x_wheel_is_steering_limit_enabled(int j);
extern double b3x_wheel_lower_steering_limit(int j);
extern double b3x_wheel_upper_steering_limit(int j);
extern void b3x_wheel_set_target_steering_angle(int j, double v);
extern double b3x_wheel_target_steering_angle(int j);
extern double b3x_wheel_steering_angle(int j);
extern double b3x_wheel_steering_torque(int j);
extern void b3x_motor_set_max_velocity_force(int j, double v);
extern double b3x_motor_max_velocity_force(int j);
extern void b3x_motor_set_max_velocity_torque(int j, double v);
extern double b3x_motor_max_velocity_torque(int j);
extern void b3x_motor_set_linear_hertz(int j, double v);
extern double b3x_motor_linear_hertz(int j);
extern void b3x_motor_set_linear_damping_ratio(int j, double v);
extern double b3x_motor_linear_damping_ratio(int j);
extern void b3x_motor_set_angular_hertz(int j, double v);
extern double b3x_motor_angular_hertz(int j);
extern void b3x_motor_set_angular_damping_ratio(int j, double v);
extern double b3x_motor_angular_damping_ratio(int j);
extern void b3x_motor_set_max_spring_force(int j, double v);
extern double b3x_motor_max_spring_force(int j);
extern void b3x_motor_set_max_spring_torque(int j, double v);
extern double b3x_motor_max_spring_torque(int j);
extern void b3x_parallel_set_spring_hertz(int j, double v);
extern double b3x_parallel_spring_hertz(int j);
extern void b3x_parallel_set_spring_damping_ratio(int j, double v);
extern double b3x_parallel_spring_damping_ratio(int j);
extern void b3x_parallel_set_max_torque(int j, double v);
extern double b3x_parallel_max_torque(int j);
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
/* Handle pools: what the creators returned, dead handles included (a  */
/* destroyed body's handle stays in the pool, and that is the point).  */
/* ------------------------------------------------------------------ */
#define POOL_CAP 4096
typedef struct { int items[POOL_CAP]; int count; } Pool;
static Pool s_worlds, s_bodies, s_shapes, s_joints;

static void keep(Pool *p, int h)
{
    if (h <= 0) return;
    if (p->count < POOL_CAP) p->items[p->count++] = h;
    else p->items[below(POOL_CAP)] = h;
}
static int draw(Pool *own)
{
    int roll = below(100);
    if (roll < 84 && own->count > 0) {
        /* lean towards the newest handles: they are the live ones */
        int span = own->count < 24 || below(3) == 0 ? own->count : 24;
        return own->items[own->count - 1 - below(span)];
    }
    if (roll < 88) return 0;
    if (roll < 94) {
        Pool *others[4] = { &s_worlds, &s_bodies, &s_shapes, &s_joints };
        Pool *o = others[below(4)];
        return o->count ? o->items[below(o->count)] : -1;
    }
    if (roll < 97) return (int)rnd();               /* any bit pattern   */
    return below(2) ? -below(1000) : below(1 << 20); /* small or negative */
}
static int HW(void) { return draw(&s_worlds); }
static int HB(void) { return draw(&s_bodies); }
static int HS(void) { return draw(&s_shapes); }
static int HJ(void) { return draw(&s_joints); }

static int flag(void) { int r = below(20); return r < 9 ? 0 : r < 18 ? 1 : r == 18 ? -7 : 255; }
static int small(int lo, int hi)
{
    if (below(25) == 0) return below(2) ? -2147483647 - 1 : 2147483647;
    return lo + below(hi - lo + 1);
}

/* ------------------------------------------------------------------ */
/* Doubles: mostly numbers a scene would use, sometimes hostile ones.  */
/* ------------------------------------------------------------------ */
static double nasty(void)
{
    static const double k[] = { 1e38, -1e38, 3.5e38, 1e300, -1e300, 1e-300, 4.9e-324, 1e15, -1e15, 1e7, -1e7 };
    int r = below(15);
    if (r == 0) return NAN;
    if (r == 1) return INFINITY;
    if (r == 2) return -INFINITY;
    if (r == 3) return -0.0;
    return k[below((int)(sizeof(k) / sizeof(k[0])))];
}
static double D(void)
{
    int r = below(100);
    if (r < 55) return (unit() - 0.5) * 20.0;
    if (r < 75) return unit() * 2.0;
    if (r < 85) return 0.0;
    if (r < 92) return (unit() - 0.5) * 2000.0;
    return nasty();
}
/* a size, a density, a time: usually positive */
static double DP(void)
{
    int r = below(100);
    if (r < 80) return 0.05 + unit() * 2.0;
    if (r < 88) return 0.0;
    if (r < 94) return -unit();
    return nasty();
}
static double DT(void) { int r = below(40); return r < 36 ? 1.0 / 60.0 : r == 36 ? 0.0 : r == 37 ? 1.0 : nasty(); }
/* collision bits: whole numbers that fit a double exactly, and some that are not */
static double BITS(void)
{
    static const double k[] = { 1, 2, 4, 8, 65535, 4294967295.0, 9007199254740991.0, 0, 1.5, -1, 1e19 };
    return below(20) == 0 ? nasty() : k[below((int)(sizeof(k) / sizeof(k[0])))];
}
/* A quaternion is four arguments drawn one at a time: Q(0) rolls a new one,
 * unit most of the time, and Q(1..3) hand out the rest of it. */
static double s_quat[4];
static double Q(int part)
{
    if (part == 0) {
        int r = below(10);
        if (r < 7) {
            double len = 0;
            for (int i = 0; i < 4; i++) { s_quat[i] = unit() - 0.5; len += s_quat[i] * s_quat[i]; }
            len = sqrt(len);
            for (int i = 0; i < 4; i++) s_quat[i] = len > 0 ? s_quat[i] / len : (i == 3);
        } else if (r < 8) {
            s_quat[0] = s_quat[1] = s_quat[2] = 0; s_quat[3] = 1;
        } else {
            for (int i = 0; i < 4; i++) s_quat[i] = D();
        }
    }
    return s_quat[part];
}

/* ------------------------------------------------------------------ */
/* What every result must satisfy                                      */
/* ------------------------------------------------------------------ */
static int s_findings = 0;
static const char *s_current = "";
static void finding(const char *what, const char *detail)
{
    if (s_findings < 40) printf("FINDING %s: %s%s%s\n", s_current, what, detail ? ": " : "", detail ? detail : "");
    s_findings++;
}
static void text(const char *r)
{
    if (!r) { finding("a text result is NULL", NULL); return; }
    size_t n = strlen(r);                      /* ASan reads every byte */
    if (b3x_text_length(r) != (int)n) finding("b3x_text_length disagrees with the text", r);
    /* b3x_last_error and b3x_library_version are prose; every other text is
     * numbers, where "nan" or "inf" means a poisoned value crossed back. */
    if (strcmp(s_current, "b3x_last_error") == 0 || strcmp(s_current, "b3x_library_version") == 0
        || strcmp(s_current, "b3x_assert_text") == 0) return;
    if (n > 0 && (strstr(r, "nan") || strstr(r, "inf") || strstr(r, "NAN") || strstr(r, "INF")))
        finding("a text result carries a non-number", r);
}
static void number(double r)
{
    if (!isfinite(r)) finding("a number result is not finite", NULL);
}

/* FUZZ_TRACE=1 in the environment prints every call with its arguments
 * before it is made, so the last line of a run that died is the call that
 * killed it and the lines above are how the world got there. The trace is
 * also a program: `box3dxt_fuzz --replay FILE` makes the same calls again,
 * which is how a failure found on one machine is carried to another and how
 * a long one is cut down to the few calls that matter. */
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
 * argument rides as a double: an int fits one exactly. */
static void rp_0(const double *a) { (void)a; tr("b3x_abi_version", 0, a); s_lastInt = b3x_abi_version(); }
static void fz_0(void) { double a[1];  rp_0(a); }
static void rp_1(const double *a) { (void)a; tr("b3x_library_version", 0, a); text(b3x_library_version()); }
static void fz_1(void) { double a[1];  rp_1(a); }
static void rp_2(const double *a) { (void)a; tr("b3x_last_error", 0, a); text(b3x_last_error()); }
static void fz_2(void) { double a[1];  rp_2(a); }
static void rp_4(const double *a) { (void)a; tr("b3x_assert_count", 0, a); s_lastInt = b3x_assert_count(); }
static void fz_4(void) { double a[1];  rp_4(a); }
static void rp_5(const double *a) { (void)a; tr("b3x_assert_text", 0, a); text(b3x_assert_text()); }
static void fz_5(void) { double a[1];  rp_5(a); }
static void rp_6(const double *a) { (void)a; tr("b3x_has_avx2", 0, a); s_lastInt = b3x_has_avx2(); }
static void fz_6(void) { double a[1];  rp_6(a); }
static void rp_7(const double *a) { tr("b3x_world_create", 4, a); s_lastInt = b3x_world_create(a[0], a[1], a[2], (int)a[3]); keep(&s_worlds, s_lastInt); }
static void fz_7(void) { double a[4]; a[0] = D(); a[1] = D(); a[2] = D(); a[3] = small(-1, 5); rp_7(a); }
static void rp_8(const double *a) { tr("b3x_world_destroy", 1, a); b3x_world_destroy((int)a[0]); }
static void fz_8(void) { double a[1]; a[0] = HW(); rp_8(a); }
static void rp_9(const double *a) { tr("b3x_world_is_valid", 1, a); s_lastInt = b3x_world_is_valid((int)a[0]); }
static void fz_9(void) { double a[1]; a[0] = HW(); rp_9(a); }
static void rp_10(const double *a) { (void)a; tr("b3x_unstable_count", 0, a); s_lastInt = b3x_unstable_count(); }
static void fz_10(void) { double a[1];  rp_10(a); }
static void rp_11(const double *a) { tr("b3x_world_step", 3, a); b3x_world_step((int)a[0], a[1], (int)a[2]); }
static void fz_11(void) { double a[3]; a[0] = HW(); a[1] = DT(); a[2] = small(-1, 9); rp_11(a); }
static void rp_12(const double *a) { tr("b3x_world_set_gravity", 4, a); b3x_world_set_gravity((int)a[0], a[1], a[2], a[3]); }
static void fz_12(void) { double a[4]; a[0] = HW(); a[1] = D(); a[2] = D(); a[3] = D(); rp_12(a); }
static void rp_13(const double *a) { tr("b3x_world_gravity", 1, a); text(b3x_world_gravity((int)a[0])); }
static void fz_13(void) { double a[1]; a[0] = HW(); rp_13(a); }
static void rp_14(const double *a) { tr("b3x_world_enable_sleeping", 2, a); b3x_world_enable_sleeping((int)a[0], (int)a[1]); }
static void fz_14(void) { double a[2]; a[0] = HW(); a[1] = flag(); rp_14(a); }
static void rp_15(const double *a) { tr("b3x_world_is_sleeping_enabled", 1, a); s_lastInt = b3x_world_is_sleeping_enabled((int)a[0]); }
static void fz_15(void) { double a[1]; a[0] = HW(); rp_15(a); }
static void rp_16(const double *a) { tr("b3x_world_enable_continuous", 2, a); b3x_world_enable_continuous((int)a[0], (int)a[1]); }
static void fz_16(void) { double a[2]; a[0] = HW(); a[1] = flag(); rp_16(a); }
static void rp_17(const double *a) { tr("b3x_world_is_continuous_enabled", 1, a); s_lastInt = b3x_world_is_continuous_enabled((int)a[0]); }
static void fz_17(void) { double a[1]; a[0] = HW(); rp_17(a); }
static void rp_18(const double *a) { tr("b3x_world_set_restitution_threshold", 2, a); b3x_world_set_restitution_threshold((int)a[0], a[1]); }
static void fz_18(void) { double a[2]; a[0] = HW(); a[1] = D(); rp_18(a); }
static void rp_19(const double *a) { tr("b3x_world_restitution_threshold", 1, a); number(b3x_world_restitution_threshold((int)a[0])); }
static void fz_19(void) { double a[1]; a[0] = HW(); rp_19(a); }
static void rp_20(const double *a) { tr("b3x_world_set_hit_event_threshold", 2, a); b3x_world_set_hit_event_threshold((int)a[0], a[1]); }
static void fz_20(void) { double a[2]; a[0] = HW(); a[1] = D(); rp_20(a); }
static void rp_21(const double *a) { tr("b3x_world_hit_event_threshold", 1, a); number(b3x_world_hit_event_threshold((int)a[0])); }
static void fz_21(void) { double a[1]; a[0] = HW(); rp_21(a); }
static void rp_22(const double *a) { tr("b3x_world_set_contact_tuning", 4, a); b3x_world_set_contact_tuning((int)a[0], a[1], a[2], a[3]); }
static void fz_22(void) { double a[4]; a[0] = HW(); a[1] = DP(); a[2] = DP(); a[3] = D(); rp_22(a); }
static void rp_23(const double *a) { tr("b3x_world_set_max_linear_speed", 2, a); b3x_world_set_max_linear_speed((int)a[0], a[1]); }
static void fz_23(void) { double a[2]; a[0] = HW(); a[1] = D(); rp_23(a); }
static void rp_24(const double *a) { tr("b3x_world_max_linear_speed", 1, a); number(b3x_world_max_linear_speed((int)a[0])); }
static void fz_24(void) { double a[1]; a[0] = HW(); rp_24(a); }
static void rp_25(const double *a) { tr("b3x_world_set_worker_count", 2, a); b3x_world_set_worker_count((int)a[0], (int)a[1]); }
static void fz_25(void) { double a[2]; a[0] = HW(); a[1] = small(-1, 5); rp_25(a); }
static void rp_26(const double *a) { tr("b3x_world_worker_count", 1, a); s_lastInt = b3x_world_worker_count((int)a[0]); }
static void fz_26(void) { double a[1]; a[0] = HW(); rp_26(a); }
static void rp_27(const double *a) { tr("b3x_world_body_count", 1, a); s_lastInt = b3x_world_body_count((int)a[0]); }
static void fz_27(void) { double a[1]; a[0] = HW(); rp_27(a); }
static void rp_28(const double *a) { tr("b3x_world_shape_count", 1, a); s_lastInt = b3x_world_shape_count((int)a[0]); }
static void fz_28(void) { double a[1]; a[0] = HW(); rp_28(a); }
static void rp_29(const double *a) { tr("b3x_world_joint_count", 1, a); s_lastInt = b3x_world_joint_count((int)a[0]); }
static void fz_29(void) { double a[1]; a[0] = HW(); rp_29(a); }
static void rp_30(const double *a) { tr("b3x_world_contact_count", 1, a); s_lastInt = b3x_world_contact_count((int)a[0]); }
static void fz_30(void) { double a[1]; a[0] = HW(); rp_30(a); }
static void rp_31(const double *a) { tr("b3x_world_awake_body_count", 1, a); s_lastInt = b3x_world_awake_body_count((int)a[0]); }
static void fz_31(void) { double a[1]; a[0] = HW(); rp_31(a); }
static void rp_32(const double *a) { tr("b3x_world_step_ms", 1, a); number(b3x_world_step_ms((int)a[0])); }
static void fz_32(void) { double a[1]; a[0] = HW(); rp_32(a); }
static void rp_33(const double *a) { tr("b3x_world_bounds", 1, a); text(b3x_world_bounds((int)a[0])); }
static void fz_33(void) { double a[1]; a[0] = HW(); rp_33(a); }
static void rp_34(const double *a) { tr("b3x_world_explode", 7, a); b3x_world_explode((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6]); }
static void fz_34(void) { double a[7]; a[0] = HW(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = DP(); a[5] = D(); a[6] = D(); rp_34(a); }
static void rp_35(const double *a) { tr("b3x_body_create", 5, a); s_lastInt = b3x_body_create((int)a[0], (int)a[1], a[2], a[3], a[4]); keep(&s_bodies, s_lastInt); }
static void fz_35(void) { double a[5]; a[0] = HW(); a[1] = small(-1, 4); a[2] = D(); a[3] = D(); a[4] = D(); rp_35(a); }
static void rp_36(const double *a) { tr("b3x_body_create_rotated", 9, a); s_lastInt = b3x_body_create_rotated((int)a[0], (int)a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8]); keep(&s_bodies, s_lastInt); }
static void fz_36(void) { double a[9]; a[0] = HW(); a[1] = small(-1, 4); a[2] = D(); a[3] = D(); a[4] = D(); a[5] = Q(0); a[6] = Q(1); a[7] = Q(2); a[8] = Q(3); rp_36(a); }
static void rp_37(const double *a) { tr("b3x_body_destroy", 1, a); b3x_body_destroy((int)a[0]); }
static void fz_37(void) { double a[1]; a[0] = HB(); rp_37(a); }
static void rp_38(const double *a) { tr("b3x_body_is_valid", 1, a); s_lastInt = b3x_body_is_valid((int)a[0]); }
static void fz_38(void) { double a[1]; a[0] = HB(); rp_38(a); }
static void rp_39(const double *a) { tr("b3x_body_type", 1, a); s_lastInt = b3x_body_type((int)a[0]); }
static void fz_39(void) { double a[1]; a[0] = HB(); rp_39(a); }
static void rp_40(const double *a) { tr("b3x_body_set_type", 2, a); b3x_body_set_type((int)a[0], (int)a[1]); }
static void fz_40(void) { double a[2]; a[0] = HB(); a[1] = small(-1, 4); rp_40(a); }
static void rp_41(const double *a) { tr("b3x_body_world", 1, a); s_lastInt = b3x_body_world((int)a[0]); }
static void fz_41(void) { double a[1]; a[0] = HB(); rp_41(a); }
static void rp_42(const double *a) { tr("b3x_body_position", 1, a); text(b3x_body_position((int)a[0])); }
static void fz_42(void) { double a[1]; a[0] = HB(); rp_42(a); }
static void rp_43(const double *a) { tr("b3x_body_x", 1, a); number(b3x_body_x((int)a[0])); }
static void fz_43(void) { double a[1]; a[0] = HB(); rp_43(a); }
static void rp_44(const double *a) { tr("b3x_body_y", 1, a); number(b3x_body_y((int)a[0])); }
static void fz_44(void) { double a[1]; a[0] = HB(); rp_44(a); }
static void rp_45(const double *a) { tr("b3x_body_z", 1, a); number(b3x_body_z((int)a[0])); }
static void fz_45(void) { double a[1]; a[0] = HB(); rp_45(a); }
static void rp_46(const double *a) { tr("b3x_body_rotation", 1, a); text(b3x_body_rotation((int)a[0])); }
static void fz_46(void) { double a[1]; a[0] = HB(); rp_46(a); }
static void rp_47(const double *a) { tr("b3x_body_transform", 1, a); text(b3x_body_transform((int)a[0])); }
static void fz_47(void) { double a[1]; a[0] = HB(); rp_47(a); }
static void rp_48(const double *a) { tr("b3x_body_matrix", 1, a); text(b3x_body_matrix((int)a[0])); }
static void fz_48(void) { double a[1]; a[0] = HB(); rp_48(a); }
static void rp_49(const double *a) { tr("b3x_body_set_transform", 8, a); b3x_body_set_transform((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]); }
static void fz_49(void) { double a[8]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = Q(0); a[5] = Q(1); a[6] = Q(2); a[7] = Q(3); rp_49(a); }
static void rp_50(const double *a) { tr("b3x_body_set_position", 4, a); b3x_body_set_position((int)a[0], a[1], a[2], a[3]); }
static void fz_50(void) { double a[4]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); rp_50(a); }
static void rp_51(const double *a) { tr("b3x_body_set_rotation", 5, a); b3x_body_set_rotation((int)a[0], a[1], a[2], a[3], a[4]); }
static void fz_51(void) { double a[5]; a[0] = HB(); a[1] = Q(0); a[2] = Q(1); a[3] = Q(2); a[4] = Q(3); rp_51(a); }
static void rp_52(const double *a) { tr("b3x_body_set_target_transform", 10, a); b3x_body_set_target_transform((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], (int)a[9]); }
static void fz_52(void) { double a[10]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = Q(0); a[5] = Q(1); a[6] = Q(2); a[7] = Q(3); a[8] = DT(); a[9] = flag(); rp_52(a); }
static void rp_53(const double *a) { tr("b3x_body_velocity", 1, a); text(b3x_body_velocity((int)a[0])); }
static void fz_53(void) { double a[1]; a[0] = HB(); rp_53(a); }
static void rp_54(const double *a) { tr("b3x_body_angular_velocity", 1, a); text(b3x_body_angular_velocity((int)a[0])); }
static void fz_54(void) { double a[1]; a[0] = HB(); rp_54(a); }
static void rp_55(const double *a) { tr("b3x_body_speed", 1, a); number(b3x_body_speed((int)a[0])); }
static void fz_55(void) { double a[1]; a[0] = HB(); rp_55(a); }
static void rp_56(const double *a) { tr("b3x_body_set_velocity", 4, a); b3x_body_set_velocity((int)a[0], a[1], a[2], a[3]); }
static void fz_56(void) { double a[4]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); rp_56(a); }
static void rp_57(const double *a) { tr("b3x_body_set_angular_velocity", 4, a); b3x_body_set_angular_velocity((int)a[0], a[1], a[2], a[3]); }
static void fz_57(void) { double a[4]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); rp_57(a); }
static void rp_58(const double *a) { tr("b3x_body_apply_force", 8, a); b3x_body_apply_force((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6], (int)a[7]); }
static void fz_58(void) { double a[8]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = D(); a[7] = flag(); rp_58(a); }
static void rp_59(const double *a) { tr("b3x_body_apply_force_to_center", 5, a); b3x_body_apply_force_to_center((int)a[0], a[1], a[2], a[3], (int)a[4]); }
static void fz_59(void) { double a[5]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = flag(); rp_59(a); }
static void rp_60(const double *a) { tr("b3x_body_apply_torque", 5, a); b3x_body_apply_torque((int)a[0], a[1], a[2], a[3], (int)a[4]); }
static void fz_60(void) { double a[5]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = flag(); rp_60(a); }
static void rp_61(const double *a) { tr("b3x_body_apply_impulse", 8, a); b3x_body_apply_impulse((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6], (int)a[7]); }
static void fz_61(void) { double a[8]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = D(); a[7] = flag(); rp_61(a); }
static void rp_62(const double *a) { tr("b3x_body_apply_impulse_to_center", 5, a); b3x_body_apply_impulse_to_center((int)a[0], a[1], a[2], a[3], (int)a[4]); }
static void fz_62(void) { double a[5]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = flag(); rp_62(a); }
static void rp_63(const double *a) { tr("b3x_body_apply_angular_impulse", 5, a); b3x_body_apply_angular_impulse((int)a[0], a[1], a[2], a[3], (int)a[4]); }
static void fz_63(void) { double a[5]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = flag(); rp_63(a); }
static void rp_64(const double *a) { tr("b3x_body_mass", 1, a); number(b3x_body_mass((int)a[0])); }
static void fz_64(void) { double a[1]; a[0] = HB(); rp_64(a); }
static void rp_65(const double *a) { tr("b3x_body_apply_mass_from_shapes", 1, a); b3x_body_apply_mass_from_shapes((int)a[0]); }
static void fz_65(void) { double a[1]; a[0] = HB(); rp_65(a); }
static void rp_66(const double *a) { tr("b3x_body_local_center", 1, a); text(b3x_body_local_center((int)a[0])); }
static void fz_66(void) { double a[1]; a[0] = HB(); rp_66(a); }
static void rp_67(const double *a) { tr("b3x_body_world_center", 1, a); text(b3x_body_world_center((int)a[0])); }
static void fz_67(void) { double a[1]; a[0] = HB(); rp_67(a); }
static void rp_68(const double *a) { tr("b3x_body_local_point", 4, a); text(b3x_body_local_point((int)a[0], a[1], a[2], a[3])); }
static void fz_68(void) { double a[4]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); rp_68(a); }
static void rp_69(const double *a) { tr("b3x_body_world_point", 4, a); text(b3x_body_world_point((int)a[0], a[1], a[2], a[3])); }
static void fz_69(void) { double a[4]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); rp_69(a); }
static void rp_70(const double *a) { tr("b3x_body_local_vector", 4, a); text(b3x_body_local_vector((int)a[0], a[1], a[2], a[3])); }
static void fz_70(void) { double a[4]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); rp_70(a); }
static void rp_71(const double *a) { tr("b3x_body_world_vector", 4, a); text(b3x_body_world_vector((int)a[0], a[1], a[2], a[3])); }
static void fz_71(void) { double a[4]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); rp_71(a); }
static void rp_72(const double *a) { tr("b3x_body_point_velocity", 4, a); text(b3x_body_point_velocity((int)a[0], a[1], a[2], a[3])); }
static void fz_72(void) { double a[4]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); rp_72(a); }
static void rp_73(const double *a) { tr("b3x_body_set_linear_damping", 2, a); b3x_body_set_linear_damping((int)a[0], a[1]); }
static void fz_73(void) { double a[2]; a[0] = HB(); a[1] = D(); rp_73(a); }
static void rp_74(const double *a) { tr("b3x_body_linear_damping", 1, a); number(b3x_body_linear_damping((int)a[0])); }
static void fz_74(void) { double a[1]; a[0] = HB(); rp_74(a); }
static void rp_75(const double *a) { tr("b3x_body_set_angular_damping", 2, a); b3x_body_set_angular_damping((int)a[0], a[1]); }
static void fz_75(void) { double a[2]; a[0] = HB(); a[1] = D(); rp_75(a); }
static void rp_76(const double *a) { tr("b3x_body_angular_damping", 1, a); number(b3x_body_angular_damping((int)a[0])); }
static void fz_76(void) { double a[1]; a[0] = HB(); rp_76(a); }
static void rp_77(const double *a) { tr("b3x_body_set_gravity_scale", 2, a); b3x_body_set_gravity_scale((int)a[0], a[1]); }
static void fz_77(void) { double a[2]; a[0] = HB(); a[1] = D(); rp_77(a); }
static void rp_78(const double *a) { tr("b3x_body_gravity_scale", 1, a); number(b3x_body_gravity_scale((int)a[0])); }
static void fz_78(void) { double a[1]; a[0] = HB(); rp_78(a); }
static void rp_79(const double *a) { tr("b3x_body_is_awake", 1, a); s_lastInt = b3x_body_is_awake((int)a[0]); }
static void fz_79(void) { double a[1]; a[0] = HB(); rp_79(a); }
static void rp_80(const double *a) { tr("b3x_body_set_awake", 2, a); b3x_body_set_awake((int)a[0], (int)a[1]); }
static void fz_80(void) { double a[2]; a[0] = HB(); a[1] = flag(); rp_80(a); }
static void rp_81(const double *a) { tr("b3x_body_enable_sleep", 2, a); b3x_body_enable_sleep((int)a[0], (int)a[1]); }
static void fz_81(void) { double a[2]; a[0] = HB(); a[1] = flag(); rp_81(a); }
static void rp_82(const double *a) { tr("b3x_body_is_sleep_enabled", 1, a); s_lastInt = b3x_body_is_sleep_enabled((int)a[0]); }
static void fz_82(void) { double a[1]; a[0] = HB(); rp_82(a); }
static void rp_83(const double *a) { tr("b3x_body_set_sleep_threshold", 2, a); b3x_body_set_sleep_threshold((int)a[0], a[1]); }
static void fz_83(void) { double a[2]; a[0] = HB(); a[1] = D(); rp_83(a); }
static void rp_84(const double *a) { tr("b3x_body_sleep_threshold", 1, a); number(b3x_body_sleep_threshold((int)a[0])); }
static void fz_84(void) { double a[1]; a[0] = HB(); rp_84(a); }
static void rp_85(const double *a) { tr("b3x_body_is_enabled", 1, a); s_lastInt = b3x_body_is_enabled((int)a[0]); }
static void fz_85(void) { double a[1]; a[0] = HB(); rp_85(a); }
static void rp_86(const double *a) { tr("b3x_body_enable", 1, a); b3x_body_enable((int)a[0]); }
static void fz_86(void) { double a[1]; a[0] = HB(); rp_86(a); }
static void rp_87(const double *a) { tr("b3x_body_disable", 1, a); b3x_body_disable((int)a[0]); }
static void fz_87(void) { double a[1]; a[0] = HB(); rp_87(a); }
static void rp_88(const double *a) { tr("b3x_body_set_bullet", 2, a); b3x_body_set_bullet((int)a[0], (int)a[1]); }
static void fz_88(void) { double a[2]; a[0] = HB(); a[1] = flag(); rp_88(a); }
static void rp_89(const double *a) { tr("b3x_body_is_bullet", 1, a); s_lastInt = b3x_body_is_bullet((int)a[0]); }
static void fz_89(void) { double a[1]; a[0] = HB(); rp_89(a); }
static void rp_90(const double *a) { tr("b3x_body_set_motion_locks", 7, a); b3x_body_set_motion_locks((int)a[0], (int)a[1], (int)a[2], (int)a[3], (int)a[4], (int)a[5], (int)a[6]); }
static void fz_90(void) { double a[7]; a[0] = HB(); a[1] = flag(); a[2] = flag(); a[3] = flag(); a[4] = flag(); a[5] = flag(); a[6] = flag(); rp_90(a); }
static void rp_91(const double *a) { tr("b3x_body_motion_locks", 1, a); text(b3x_body_motion_locks((int)a[0])); }
static void fz_91(void) { double a[1]; a[0] = HB(); rp_91(a); }
static void rp_92(const double *a) { tr("b3x_body_enable_hit_events", 2, a); b3x_body_enable_hit_events((int)a[0], (int)a[1]); }
static void fz_92(void) { double a[2]; a[0] = HB(); a[1] = flag(); rp_92(a); }
static void rp_93(const double *a) { tr("b3x_body_aabb", 1, a); text(b3x_body_aabb((int)a[0])); }
static void fz_93(void) { double a[1]; a[0] = HB(); rp_93(a); }
static void rp_94(const double *a) { tr("b3x_body_shape_count", 1, a); s_lastInt = b3x_body_shape_count((int)a[0]); }
static void fz_94(void) { double a[1]; a[0] = HB(); rp_94(a); }
static void rp_95(const double *a) { tr("b3x_body_joint_count", 1, a); s_lastInt = b3x_body_joint_count((int)a[0]); }
static void fz_95(void) { double a[1]; a[0] = HB(); rp_95(a); }
static void rp_96(const double *a) { (void)a; tr("b3x_list_count", 0, a); s_lastInt = b3x_list_count(); }
static void fz_96(void) { double a[1];  rp_96(a); }
static void rp_97(const double *a) { tr("b3x_list_item", 1, a); s_lastInt = b3x_list_item((int)a[0]); }
static void fz_97(void) { double a[1]; a[0] = small(-1, 6); rp_97(a); }
static void rp_98(const double *a) { tr("b3x_body_list_shapes", 1, a); s_lastInt = b3x_body_list_shapes((int)a[0]); }
static void fz_98(void) { double a[1]; a[0] = HB(); rp_98(a); }
static void rp_99(const double *a) { tr("b3x_body_list_joints", 1, a); s_lastInt = b3x_body_list_joints((int)a[0]); }
static void fz_99(void) { double a[1]; a[0] = HB(); rp_99(a); }
static void rp_100(const double *a) { tr("b3x_body_list_touching", 1, a); s_lastInt = b3x_body_list_touching((int)a[0]); }
static void fz_100(void) { double a[1]; a[0] = HB(); rp_100(a); }
static void rp_101(const double *a) { (void)a; tr("b3x_shape_options_reset", 0, a); b3x_shape_options_reset(); }
static void fz_101(void) { double a[1];  rp_101(a); }
static void rp_102(const double *a) { tr("b3x_shape_options_set_sensor", 1, a); b3x_shape_options_set_sensor((int)a[0]); }
static void fz_102(void) { double a[1]; a[0] = flag(); rp_102(a); }
static void rp_103(const double *a) { tr("b3x_shape_options_set_events", 3, a); b3x_shape_options_set_events((int)a[0], (int)a[1], (int)a[2]); }
static void fz_103(void) { double a[3]; a[0] = flag(); a[1] = flag(); a[2] = flag(); rp_103(a); }
static void rp_104(const double *a) { tr("b3x_shape_options_set_filter", 3, a); b3x_shape_options_set_filter(a[0], a[1], (int)a[2]); }
static void fz_104(void) { double a[3]; a[0] = BITS(); a[1] = BITS(); a[2] = small(-3, 3); rp_104(a); }
static void rp_105(const double *a) { tr("b3x_shape_options_set_rolling_resistance", 1, a); b3x_shape_options_set_rolling_resistance(a[0]); }
static void fz_105(void) { double a[1]; a[0] = D(); rp_105(a); }
static void rp_106(const double *a) { (void)a; tr("b3x_geometry_begin", 0, a); b3x_geometry_begin(); }
static void fz_106(void) { double a[1];  rp_106(a); }
static void rp_107(const double *a) { tr("b3x_geometry_add_point", 3, a); s_lastInt = b3x_geometry_add_point(a[0], a[1], a[2]); }
static void fz_107(void) { double a[3]; a[0] = D(); a[1] = D(); a[2] = D(); rp_107(a); }
static void rp_108(const double *a) { tr("b3x_geometry_add_triangle", 3, a); s_lastInt = b3x_geometry_add_triangle((int)a[0], (int)a[1], (int)a[2]); }
static void fz_108(void) { double a[3]; a[0] = small(0, 9); a[1] = small(0, 9); a[2] = small(0, 9); rp_108(a); }
static void rp_109(const double *a) { tr("b3x_geometry_add_height", 1, a); s_lastInt = b3x_geometry_add_height(a[0]); }
static void fz_109(void) { double a[1]; a[0] = D(); rp_109(a); }
static void rp_110(const double *a) { (void)a; tr("b3x_geometry_point_count", 0, a); s_lastInt = b3x_geometry_point_count(); }
static void fz_110(void) { double a[1];  rp_110(a); }
static void rp_111(const double *a) { tr("b3x_shape_add_sphere", 8, a); s_lastInt = b3x_shape_add_sphere((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]); keep(&s_shapes, s_lastInt); }
static void fz_111(void) { double a[8]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = DP(); a[5] = DP(); a[6] = DP(); a[7] = DP(); rp_111(a); }
static void rp_112(const double *a) { tr("b3x_shape_add_capsule", 11, a); s_lastInt = b3x_shape_add_capsule((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10]); keep(&s_shapes, s_lastInt); }
static void fz_112(void) { double a[11]; a[0] = HB(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = D(); a[7] = DP(); a[8] = DP(); a[9] = DP(); a[10] = DP(); rp_112(a); }
static void rp_113(const double *a) { tr("b3x_shape_add_box", 7, a); s_lastInt = b3x_shape_add_box((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6]); keep(&s_shapes, s_lastInt); }
static void fz_113(void) { double a[7]; a[0] = HB(); a[1] = DP(); a[2] = DP(); a[3] = DP(); a[4] = DP(); a[5] = DP(); a[6] = DP(); rp_113(a); }
static void rp_114(const double *a) { tr("b3x_shape_add_box_at", 14, a); s_lastInt = b3x_shape_add_box_at((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13]); keep(&s_shapes, s_lastInt); }
static void fz_114(void) { double a[14]; a[0] = HB(); a[1] = DP(); a[2] = DP(); a[3] = DP(); a[4] = D(); a[5] = D(); a[6] = D(); a[7] = Q(0); a[8] = Q(1); a[9] = Q(2); a[10] = Q(3); a[11] = DP(); a[12] = DP(); a[13] = DP(); rp_114(a); }
static void rp_115(const double *a) { tr("b3x_shape_add_cylinder", 7, a); s_lastInt = b3x_shape_add_cylinder((int)a[0], a[1], a[2], (int)a[3], a[4], a[5], a[6]); keep(&s_shapes, s_lastInt); }
static void fz_115(void) { double a[7]; a[0] = HB(); a[1] = DP(); a[2] = DP(); a[3] = small(0, 34); a[4] = DP(); a[5] = DP(); a[6] = DP(); rp_115(a); }
static void rp_116(const double *a) { tr("b3x_shape_add_cone", 8, a); s_lastInt = b3x_shape_add_cone((int)a[0], a[1], a[2], a[3], (int)a[4], a[5], a[6], a[7]); keep(&s_shapes, s_lastInt); }
static void fz_116(void) { double a[8]; a[0] = HB(); a[1] = DP(); a[2] = DP(); a[3] = DP(); a[4] = small(0, 34); a[5] = DP(); a[6] = DP(); a[7] = DP(); rp_116(a); }
static void rp_117(const double *a) { tr("b3x_shape_add_hull", 4, a); s_lastInt = b3x_shape_add_hull((int)a[0], a[1], a[2], a[3]); keep(&s_shapes, s_lastInt); }
static void fz_117(void) { double a[4]; a[0] = HB(); a[1] = DP(); a[2] = DP(); a[3] = DP(); rp_117(a); }
static void rp_118(const double *a) { tr("b3x_shape_add_mesh", 3, a); s_lastInt = b3x_shape_add_mesh((int)a[0], a[1], a[2]); keep(&s_shapes, s_lastInt); }
static void fz_118(void) { double a[3]; a[0] = HB(); a[1] = DP(); a[2] = DP(); rp_118(a); }
static void rp_119(const double *a) { tr("b3x_shape_add_height_field", 8, a); s_lastInt = b3x_shape_add_height_field((int)a[0], (int)a[1], (int)a[2], a[3], a[4], a[5], a[6], a[7]); keep(&s_shapes, s_lastInt); }
static void fz_119(void) { double a[8]; a[0] = HB(); a[1] = small(0, 9); a[2] = small(0, 9); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = DP(); a[7] = DP(); rp_119(a); }
static void rp_120(const double *a) { tr("b3x_shape_destroy", 2, a); b3x_shape_destroy((int)a[0], (int)a[1]); }
static void fz_120(void) { double a[2]; a[0] = HS(); a[1] = flag(); rp_120(a); }
static void rp_121(const double *a) { tr("b3x_shape_is_valid", 1, a); s_lastInt = b3x_shape_is_valid((int)a[0]); }
static void fz_121(void) { double a[1]; a[0] = HS(); rp_121(a); }
static void rp_122(const double *a) { tr("b3x_shape_type", 1, a); s_lastInt = b3x_shape_type((int)a[0]); }
static void fz_122(void) { double a[1]; a[0] = HS(); rp_122(a); }
static void rp_123(const double *a) { tr("b3x_shape_body", 1, a); s_lastInt = b3x_shape_body((int)a[0]); }
static void fz_123(void) { double a[1]; a[0] = HS(); rp_123(a); }
static void rp_124(const double *a) { tr("b3x_shape_is_sensor", 1, a); s_lastInt = b3x_shape_is_sensor((int)a[0]); }
static void fz_124(void) { double a[1]; a[0] = HS(); rp_124(a); }
static void rp_125(const double *a) { tr("b3x_shape_set_density", 3, a); b3x_shape_set_density((int)a[0], a[1], (int)a[2]); }
static void fz_125(void) { double a[3]; a[0] = HS(); a[1] = D(); a[2] = flag(); rp_125(a); }
static void rp_126(const double *a) { tr("b3x_shape_density", 1, a); number(b3x_shape_density((int)a[0])); }
static void fz_126(void) { double a[1]; a[0] = HS(); rp_126(a); }
static void rp_127(const double *a) { tr("b3x_shape_set_friction", 2, a); b3x_shape_set_friction((int)a[0], a[1]); }
static void fz_127(void) { double a[2]; a[0] = HS(); a[1] = D(); rp_127(a); }
static void rp_128(const double *a) { tr("b3x_shape_friction", 1, a); number(b3x_shape_friction((int)a[0])); }
static void fz_128(void) { double a[1]; a[0] = HS(); rp_128(a); }
static void rp_129(const double *a) { tr("b3x_shape_set_restitution", 2, a); b3x_shape_set_restitution((int)a[0], a[1]); }
static void fz_129(void) { double a[2]; a[0] = HS(); a[1] = D(); rp_129(a); }
static void rp_130(const double *a) { tr("b3x_shape_restitution", 1, a); number(b3x_shape_restitution((int)a[0])); }
static void fz_130(void) { double a[1]; a[0] = HS(); rp_130(a); }
static void rp_131(const double *a) { tr("b3x_shape_set_rolling_resistance", 2, a); b3x_shape_set_rolling_resistance((int)a[0], a[1]); }
static void fz_131(void) { double a[2]; a[0] = HS(); a[1] = D(); rp_131(a); }
static void rp_132(const double *a) { tr("b3x_shape_rolling_resistance", 1, a); number(b3x_shape_rolling_resistance((int)a[0])); }
static void fz_132(void) { double a[1]; a[0] = HS(); rp_132(a); }
static void rp_133(const double *a) { tr("b3x_shape_set_filter", 4, a); b3x_shape_set_filter((int)a[0], a[1], a[2], (int)a[3]); }
static void fz_133(void) { double a[4]; a[0] = HS(); a[1] = BITS(); a[2] = BITS(); a[3] = small(-3, 3); rp_133(a); }
static void rp_134(const double *a) { tr("b3x_shape_filter", 1, a); text(b3x_shape_filter((int)a[0])); }
static void fz_134(void) { double a[1]; a[0] = HS(); rp_134(a); }
static void rp_135(const double *a) { tr("b3x_shape_enable_contact_events", 2, a); b3x_shape_enable_contact_events((int)a[0], (int)a[1]); }
static void fz_135(void) { double a[2]; a[0] = HS(); a[1] = flag(); rp_135(a); }
static void rp_136(const double *a) { tr("b3x_shape_are_contact_events_enabled", 1, a); s_lastInt = b3x_shape_are_contact_events_enabled((int)a[0]); }
static void fz_136(void) { double a[1]; a[0] = HS(); rp_136(a); }
static void rp_137(const double *a) { tr("b3x_shape_enable_hit_events", 2, a); b3x_shape_enable_hit_events((int)a[0], (int)a[1]); }
static void fz_137(void) { double a[2]; a[0] = HS(); a[1] = flag(); rp_137(a); }
static void rp_138(const double *a) { tr("b3x_shape_are_hit_events_enabled", 1, a); s_lastInt = b3x_shape_are_hit_events_enabled((int)a[0]); }
static void fz_138(void) { double a[1]; a[0] = HS(); rp_138(a); }
static void rp_139(const double *a) { tr("b3x_shape_enable_sensor_events", 2, a); b3x_shape_enable_sensor_events((int)a[0], (int)a[1]); }
static void fz_139(void) { double a[2]; a[0] = HS(); a[1] = flag(); rp_139(a); }
static void rp_140(const double *a) { tr("b3x_shape_are_sensor_events_enabled", 1, a); s_lastInt = b3x_shape_are_sensor_events_enabled((int)a[0]); }
static void fz_140(void) { double a[1]; a[0] = HS(); rp_140(a); }
static void rp_141(const double *a) { tr("b3x_shape_aabb", 1, a); text(b3x_shape_aabb((int)a[0])); }
static void fz_141(void) { double a[1]; a[0] = HS(); rp_141(a); }
static void rp_142(const double *a) { tr("b3x_shape_closest_point", 4, a); text(b3x_shape_closest_point((int)a[0], a[1], a[2], a[3])); }
static void fz_142(void) { double a[4]; a[0] = HS(); a[1] = D(); a[2] = D(); a[3] = D(); rp_142(a); }
static void rp_143(const double *a) { tr("b3x_shape_list_sensor_visitors", 1, a); s_lastInt = b3x_shape_list_sensor_visitors((int)a[0]); }
static void fz_143(void) { double a[1]; a[0] = HS(); rp_143(a); }
static void rp_144(const double *a) { tr("b3x_query_set_filter", 2, a); b3x_query_set_filter(a[0], a[1]); }
static void fz_144(void) { double a[2]; a[0] = BITS(); a[1] = BITS(); rp_144(a); }
static void rp_145(const double *a) { (void)a; tr("b3x_query_reset_filter", 0, a); b3x_query_reset_filter(); }
static void fz_145(void) { double a[1];  rp_145(a); }
static void rp_146(const double *a) { tr("b3x_cast_ray", 7, a); s_lastInt = b3x_cast_ray((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6]); }
static void fz_146(void) { double a[7]; a[0] = HW(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = D(); rp_146(a); }
static void rp_147(const double *a) { tr("b3x_cast_ray_closest", 7, a); s_lastInt = b3x_cast_ray_closest((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6]); }
static void fz_147(void) { double a[7]; a[0] = HW(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = D(); rp_147(a); }
static void rp_148(const double *a) { tr("b3x_cast_sphere", 8, a); s_lastInt = b3x_cast_sphere((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]); }
static void fz_148(void) { double a[8]; a[0] = HW(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = DP(); a[5] = D(); a[6] = D(); a[7] = D(); rp_148(a); }
static void rp_149(const double *a) { (void)a; tr("b3x_hit_count", 0, a); s_lastInt = b3x_hit_count(); }
static void fz_149(void) { double a[1];  rp_149(a); }
static void rp_150(const double *a) { tr("b3x_hit_shape", 1, a); s_lastInt = b3x_hit_shape((int)a[0]); }
static void fz_150(void) { double a[1]; a[0] = small(-1, 6); rp_150(a); }
static void rp_151(const double *a) { tr("b3x_hit_body", 1, a); s_lastInt = b3x_hit_body((int)a[0]); }
static void fz_151(void) { double a[1]; a[0] = small(-1, 6); rp_151(a); }
static void rp_152(const double *a) { tr("b3x_hit_fraction", 1, a); number(b3x_hit_fraction((int)a[0])); }
static void fz_152(void) { double a[1]; a[0] = small(-1, 6); rp_152(a); }
static void rp_153(const double *a) { tr("b3x_hit_point", 1, a); text(b3x_hit_point((int)a[0])); }
static void fz_153(void) { double a[1]; a[0] = small(-1, 6); rp_153(a); }
static void rp_154(const double *a) { tr("b3x_hit_normal", 1, a); text(b3x_hit_normal((int)a[0])); }
static void fz_154(void) { double a[1]; a[0] = small(-1, 6); rp_154(a); }
static void rp_155(const double *a) { tr("b3x_overlap_aabb", 7, a); s_lastInt = b3x_overlap_aabb((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6]); }
static void fz_155(void) { double a[7]; a[0] = HW(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = D(); rp_155(a); }
static void rp_156(const double *a) { tr("b3x_overlap_sphere", 5, a); s_lastInt = b3x_overlap_sphere((int)a[0], a[1], a[2], a[3], a[4]); }
static void fz_156(void) { double a[5]; a[0] = HW(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = DP(); rp_156(a); }
static void rp_157(const double *a) { tr("b3x_world_update_contact_events", 1, a); s_lastInt = b3x_world_update_contact_events((int)a[0]); }
static void fz_157(void) { double a[1]; a[0] = HW(); rp_157(a); }
static void rp_158(const double *a) { (void)a; tr("b3x_contact_begin_count", 0, a); s_lastInt = b3x_contact_begin_count(); }
static void fz_158(void) { double a[1];  rp_158(a); }
static void rp_159(const double *a) { tr("b3x_contact_begin_shape_a", 1, a); s_lastInt = b3x_contact_begin_shape_a((int)a[0]); }
static void fz_159(void) { double a[1]; a[0] = small(-1, 6); rp_159(a); }
static void rp_160(const double *a) { tr("b3x_contact_begin_shape_b", 1, a); s_lastInt = b3x_contact_begin_shape_b((int)a[0]); }
static void fz_160(void) { double a[1]; a[0] = small(-1, 6); rp_160(a); }
static void rp_161(const double *a) { (void)a; tr("b3x_contact_end_count", 0, a); s_lastInt = b3x_contact_end_count(); }
static void fz_161(void) { double a[1];  rp_161(a); }
static void rp_162(const double *a) { tr("b3x_contact_end_shape_a", 1, a); s_lastInt = b3x_contact_end_shape_a((int)a[0]); }
static void fz_162(void) { double a[1]; a[0] = small(-1, 6); rp_162(a); }
static void rp_163(const double *a) { tr("b3x_contact_end_shape_b", 1, a); s_lastInt = b3x_contact_end_shape_b((int)a[0]); }
static void fz_163(void) { double a[1]; a[0] = small(-1, 6); rp_163(a); }
static void rp_164(const double *a) { (void)a; tr("b3x_contact_hit_count", 0, a); s_lastInt = b3x_contact_hit_count(); }
static void fz_164(void) { double a[1];  rp_164(a); }
static void rp_165(const double *a) { tr("b3x_contact_hit_shape_a", 1, a); s_lastInt = b3x_contact_hit_shape_a((int)a[0]); }
static void fz_165(void) { double a[1]; a[0] = small(-1, 6); rp_165(a); }
static void rp_166(const double *a) { tr("b3x_contact_hit_shape_b", 1, a); s_lastInt = b3x_contact_hit_shape_b((int)a[0]); }
static void fz_166(void) { double a[1]; a[0] = small(-1, 6); rp_166(a); }
static void rp_167(const double *a) { tr("b3x_contact_hit_speed", 1, a); number(b3x_contact_hit_speed((int)a[0])); }
static void fz_167(void) { double a[1]; a[0] = small(-1, 6); rp_167(a); }
static void rp_168(const double *a) { tr("b3x_contact_hit_point", 1, a); text(b3x_contact_hit_point((int)a[0])); }
static void fz_168(void) { double a[1]; a[0] = small(-1, 6); rp_168(a); }
static void rp_169(const double *a) { tr("b3x_contact_hit_normal", 1, a); text(b3x_contact_hit_normal((int)a[0])); }
static void fz_169(void) { double a[1]; a[0] = small(-1, 6); rp_169(a); }
static void rp_170(const double *a) { tr("b3x_world_update_sensor_events", 1, a); s_lastInt = b3x_world_update_sensor_events((int)a[0]); }
static void fz_170(void) { double a[1]; a[0] = HW(); rp_170(a); }
static void rp_171(const double *a) { (void)a; tr("b3x_sensor_begin_count", 0, a); s_lastInt = b3x_sensor_begin_count(); }
static void fz_171(void) { double a[1];  rp_171(a); }
static void rp_172(const double *a) { tr("b3x_sensor_begin_sensor", 1, a); s_lastInt = b3x_sensor_begin_sensor((int)a[0]); }
static void fz_172(void) { double a[1]; a[0] = small(-1, 6); rp_172(a); }
static void rp_173(const double *a) { tr("b3x_sensor_begin_visitor", 1, a); s_lastInt = b3x_sensor_begin_visitor((int)a[0]); }
static void fz_173(void) { double a[1]; a[0] = small(-1, 6); rp_173(a); }
static void rp_174(const double *a) { (void)a; tr("b3x_sensor_end_count", 0, a); s_lastInt = b3x_sensor_end_count(); }
static void fz_174(void) { double a[1];  rp_174(a); }
static void rp_175(const double *a) { tr("b3x_sensor_end_sensor", 1, a); s_lastInt = b3x_sensor_end_sensor((int)a[0]); }
static void fz_175(void) { double a[1]; a[0] = small(-1, 6); rp_175(a); }
static void rp_176(const double *a) { tr("b3x_sensor_end_visitor", 1, a); s_lastInt = b3x_sensor_end_visitor((int)a[0]); }
static void fz_176(void) { double a[1]; a[0] = small(-1, 6); rp_176(a); }
static void rp_177(const double *a) { tr("b3x_world_update_moves", 1, a); s_lastInt = b3x_world_update_moves((int)a[0]); }
static void fz_177(void) { double a[1]; a[0] = HW(); rp_177(a); }
static void rp_178(const double *a) { (void)a; tr("b3x_move_count", 0, a); s_lastInt = b3x_move_count(); }
static void fz_178(void) { double a[1];  rp_178(a); }
static void rp_179(const double *a) { tr("b3x_move_body", 1, a); s_lastInt = b3x_move_body((int)a[0]); }
static void fz_179(void) { double a[1]; a[0] = small(-1, 6); rp_179(a); }
static void rp_180(const double *a) { tr("b3x_move_fell_asleep", 1, a); s_lastInt = b3x_move_fell_asleep((int)a[0]); }
static void fz_180(void) { double a[1]; a[0] = small(-1, 6); rp_180(a); }
static void rp_181(const double *a) { tr("b3x_move_transform", 1, a); text(b3x_move_transform((int)a[0])); }
static void fz_181(void) { double a[1]; a[0] = small(-1, 6); rp_181(a); }
static void rp_182(const double *a) { (void)a; tr("b3x_moves_text", 0, a); text(b3x_moves_text()); }
static void fz_182(void) { double a[1];  rp_182(a); }
static void rp_183(const double *a) { tr("b3x_world_update_joint_events", 1, a); s_lastInt = b3x_world_update_joint_events((int)a[0]); }
static void fz_183(void) { double a[1]; a[0] = HW(); rp_183(a); }
static void rp_184(const double *a) { (void)a; tr("b3x_joint_event_count", 0, a); s_lastInt = b3x_joint_event_count(); }
static void fz_184(void) { double a[1];  rp_184(a); }
static void rp_185(const double *a) { tr("b3x_joint_event_joint", 1, a); s_lastInt = b3x_joint_event_joint((int)a[0]); }
static void fz_185(void) { double a[1]; a[0] = small(-1, 6); rp_185(a); }
static void rp_186(const double *a) { tr("b3x_quat_from_axis_angle", 4, a); text(b3x_quat_from_axis_angle(a[0], a[1], a[2], a[3])); }
static void fz_186(void) { double a[4]; a[0] = D(); a[1] = D(); a[2] = D(); a[3] = D(); rp_186(a); }
static void rp_187(const double *a) { tr("b3x_quat_from_euler", 3, a); text(b3x_quat_from_euler(a[0], a[1], a[2])); }
static void fz_187(void) { double a[3]; a[0] = D(); a[1] = D(); a[2] = D(); rp_187(a); }
static void rp_188(const double *a) { tr("b3x_quat_multiply", 8, a); text(b3x_quat_multiply(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7])); }
static void fz_188(void) { double a[8]; a[0] = D(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = D(); a[7] = D(); rp_188(a); }
static void rp_189(const double *a) { tr("b3x_quat_rotate", 7, a); text(b3x_quat_rotate(a[0], a[1], a[2], a[3], a[4], a[5], a[6])); }
static void fz_189(void) { double a[7]; a[0] = Q(0); a[1] = Q(1); a[2] = Q(2); a[3] = Q(3); a[4] = D(); a[5] = D(); a[6] = D(); rp_189(a); }
static void rp_190(const double *a) { tr("b3x_quat_to_axis_angle", 4, a); text(b3x_quat_to_axis_angle(a[0], a[1], a[2], a[3])); }
static void fz_190(void) { double a[4]; a[0] = Q(0); a[1] = Q(1); a[2] = Q(2); a[3] = Q(3); rp_190(a); }
static void rp_191(const double *a) { tr("b3x_joint_revolute", 10, a); s_lastInt = b3x_joint_revolute((int)a[0], (int)a[1], (int)a[2], a[3], a[4], a[5], a[6], a[7], a[8], (int)a[9]); keep(&s_joints, s_lastInt); }
static void fz_191(void) { double a[10]; a[0] = HW(); a[1] = HB(); a[2] = HB(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = D(); a[7] = D(); a[8] = D(); a[9] = flag(); rp_191(a); }
static void rp_192(const double *a) { tr("b3x_joint_prismatic", 10, a); s_lastInt = b3x_joint_prismatic((int)a[0], (int)a[1], (int)a[2], a[3], a[4], a[5], a[6], a[7], a[8], (int)a[9]); keep(&s_joints, s_lastInt); }
static void fz_192(void) { double a[10]; a[0] = HW(); a[1] = HB(); a[2] = HB(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = D(); a[7] = D(); a[8] = D(); a[9] = flag(); rp_192(a); }
static void rp_193(const double *a) { tr("b3x_joint_spherical", 10, a); s_lastInt = b3x_joint_spherical((int)a[0], (int)a[1], (int)a[2], a[3], a[4], a[5], a[6], a[7], a[8], (int)a[9]); keep(&s_joints, s_lastInt); }
static void fz_193(void) { double a[10]; a[0] = HW(); a[1] = HB(); a[2] = HB(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = D(); a[7] = D(); a[8] = D(); a[9] = flag(); rp_193(a); }
static void rp_194(const double *a) { tr("b3x_joint_weld", 7, a); s_lastInt = b3x_joint_weld((int)a[0], (int)a[1], (int)a[2], a[3], a[4], a[5], (int)a[6]); keep(&s_joints, s_lastInt); }
static void fz_194(void) { double a[7]; a[0] = HW(); a[1] = HB(); a[2] = HB(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = flag(); rp_194(a); }
static void rp_195(const double *a) { tr("b3x_joint_distance", 10, a); s_lastInt = b3x_joint_distance((int)a[0], (int)a[1], (int)a[2], a[3], a[4], a[5], a[6], a[7], a[8], (int)a[9]); keep(&s_joints, s_lastInt); }
static void fz_195(void) { double a[10]; a[0] = HW(); a[1] = HB(); a[2] = HB(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = D(); a[7] = D(); a[8] = D(); a[9] = flag(); rp_195(a); }
static void rp_196(const double *a) { tr("b3x_joint_wheel", 13, a); s_lastInt = b3x_joint_wheel((int)a[0], (int)a[1], (int)a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], (int)a[12]); keep(&s_joints, s_lastInt); }
static void fz_196(void) { double a[13]; a[0] = HW(); a[1] = HB(); a[2] = HB(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = D(); a[7] = D(); a[8] = D(); a[9] = D(); a[10] = D(); a[11] = D(); a[12] = flag(); rp_196(a); }
static void rp_197(const double *a) { tr("b3x_joint_motor", 4, a); s_lastInt = b3x_joint_motor((int)a[0], (int)a[1], (int)a[2], (int)a[3]); keep(&s_joints, s_lastInt); }
static void fz_197(void) { double a[4]; a[0] = HW(); a[1] = HB(); a[2] = HB(); a[3] = flag(); rp_197(a); }
static void rp_198(const double *a) { tr("b3x_joint_parallel", 7, a); s_lastInt = b3x_joint_parallel((int)a[0], (int)a[1], (int)a[2], a[3], a[4], a[5], (int)a[6]); keep(&s_joints, s_lastInt); }
static void fz_198(void) { double a[7]; a[0] = HW(); a[1] = HB(); a[2] = HB(); a[3] = D(); a[4] = D(); a[5] = D(); a[6] = flag(); rp_198(a); }
static void rp_199(const double *a) { tr("b3x_joint_filter", 3, a); s_lastInt = b3x_joint_filter((int)a[0], (int)a[1], (int)a[2]); keep(&s_joints, s_lastInt); }
static void fz_199(void) { double a[3]; a[0] = HW(); a[1] = HB(); a[2] = HB(); rp_199(a); }
static void rp_200(const double *a) { tr("b3x_joint_destroy", 2, a); b3x_joint_destroy((int)a[0], (int)a[1]); }
static void fz_200(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_200(a); }
static void rp_201(const double *a) { tr("b3x_joint_is_valid", 1, a); s_lastInt = b3x_joint_is_valid((int)a[0]); }
static void fz_201(void) { double a[1]; a[0] = HJ(); rp_201(a); }
static void rp_202(const double *a) { tr("b3x_joint_type", 1, a); s_lastInt = b3x_joint_type((int)a[0]); }
static void fz_202(void) { double a[1]; a[0] = HJ(); rp_202(a); }
static void rp_203(const double *a) { tr("b3x_joint_body_a", 1, a); s_lastInt = b3x_joint_body_a((int)a[0]); }
static void fz_203(void) { double a[1]; a[0] = HJ(); rp_203(a); }
static void rp_204(const double *a) { tr("b3x_joint_body_b", 1, a); s_lastInt = b3x_joint_body_b((int)a[0]); }
static void fz_204(void) { double a[1]; a[0] = HJ(); rp_204(a); }
static void rp_205(const double *a) { tr("b3x_joint_set_collide_connected", 2, a); b3x_joint_set_collide_connected((int)a[0], (int)a[1]); }
static void fz_205(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_205(a); }
static void rp_206(const double *a) { tr("b3x_joint_collide_connected", 1, a); s_lastInt = b3x_joint_collide_connected((int)a[0]); }
static void fz_206(void) { double a[1]; a[0] = HJ(); rp_206(a); }
static void rp_207(const double *a) { tr("b3x_joint_wake_bodies", 1, a); b3x_joint_wake_bodies((int)a[0]); }
static void fz_207(void) { double a[1]; a[0] = HJ(); rp_207(a); }
static void rp_208(const double *a) { tr("b3x_joint_local_frame_a", 1, a); text(b3x_joint_local_frame_a((int)a[0])); }
static void fz_208(void) { double a[1]; a[0] = HJ(); rp_208(a); }
static void rp_209(const double *a) { tr("b3x_joint_local_frame_b", 1, a); text(b3x_joint_local_frame_b((int)a[0])); }
static void fz_209(void) { double a[1]; a[0] = HJ(); rp_209(a); }
static void rp_210(const double *a) { tr("b3x_joint_set_local_frame_a", 8, a); b3x_joint_set_local_frame_a((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]); }
static void fz_210(void) { double a[8]; a[0] = HJ(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = Q(0); a[5] = Q(1); a[6] = Q(2); a[7] = Q(3); rp_210(a); }
static void rp_211(const double *a) { tr("b3x_joint_set_local_frame_b", 8, a); b3x_joint_set_local_frame_b((int)a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7]); }
static void fz_211(void) { double a[8]; a[0] = HJ(); a[1] = D(); a[2] = D(); a[3] = D(); a[4] = Q(0); a[5] = Q(1); a[6] = Q(2); a[7] = Q(3); rp_211(a); }
static void rp_212(const double *a) { tr("b3x_joint_constraint_force", 1, a); text(b3x_joint_constraint_force((int)a[0])); }
static void fz_212(void) { double a[1]; a[0] = HJ(); rp_212(a); }
static void rp_213(const double *a) { tr("b3x_joint_constraint_torque", 1, a); text(b3x_joint_constraint_torque((int)a[0])); }
static void fz_213(void) { double a[1]; a[0] = HJ(); rp_213(a); }
static void rp_214(const double *a) { tr("b3x_joint_linear_separation", 1, a); number(b3x_joint_linear_separation((int)a[0])); }
static void fz_214(void) { double a[1]; a[0] = HJ(); rp_214(a); }
static void rp_215(const double *a) { tr("b3x_joint_angular_separation", 1, a); number(b3x_joint_angular_separation((int)a[0])); }
static void fz_215(void) { double a[1]; a[0] = HJ(); rp_215(a); }
static void rp_216(const double *a) { tr("b3x_joint_set_force_threshold", 2, a); b3x_joint_set_force_threshold((int)a[0], a[1]); }
static void fz_216(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_216(a); }
static void rp_217(const double *a) { tr("b3x_joint_force_threshold", 1, a); number(b3x_joint_force_threshold((int)a[0])); }
static void fz_217(void) { double a[1]; a[0] = HJ(); rp_217(a); }
static void rp_218(const double *a) { tr("b3x_joint_set_torque_threshold", 2, a); b3x_joint_set_torque_threshold((int)a[0], a[1]); }
static void fz_218(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_218(a); }
static void rp_219(const double *a) { tr("b3x_joint_torque_threshold", 1, a); number(b3x_joint_torque_threshold((int)a[0])); }
static void fz_219(void) { double a[1]; a[0] = HJ(); rp_219(a); }
static void rp_220(const double *a) { tr("b3x_motor_set_linear_velocity", 4, a); b3x_motor_set_linear_velocity((int)a[0], a[1], a[2], a[3]); }
static void fz_220(void) { double a[4]; a[0] = HJ(); a[1] = D(); a[2] = D(); a[3] = D(); rp_220(a); }
static void rp_221(const double *a) { tr("b3x_motor_linear_velocity", 1, a); text(b3x_motor_linear_velocity((int)a[0])); }
static void fz_221(void) { double a[1]; a[0] = HJ(); rp_221(a); }
static void rp_222(const double *a) { tr("b3x_motor_set_angular_velocity", 4, a); b3x_motor_set_angular_velocity((int)a[0], a[1], a[2], a[3]); }
static void fz_222(void) { double a[4]; a[0] = HJ(); a[1] = D(); a[2] = D(); a[3] = D(); rp_222(a); }
static void rp_223(const double *a) { tr("b3x_motor_angular_velocity", 1, a); text(b3x_motor_angular_velocity((int)a[0])); }
static void fz_223(void) { double a[1]; a[0] = HJ(); rp_223(a); }
static void rp_224(const double *a) { tr("b3x_spherical_set_motor_velocity", 4, a); b3x_spherical_set_motor_velocity((int)a[0], a[1], a[2], a[3]); }
static void fz_224(void) { double a[4]; a[0] = HJ(); a[1] = D(); a[2] = D(); a[3] = D(); rp_224(a); }
static void rp_225(const double *a) { tr("b3x_spherical_motor_velocity", 1, a); text(b3x_spherical_motor_velocity((int)a[0])); }
static void fz_225(void) { double a[1]; a[0] = HJ(); rp_225(a); }
static void rp_226(const double *a) { tr("b3x_spherical_motor_torque", 1, a); text(b3x_spherical_motor_torque((int)a[0])); }
static void fz_226(void) { double a[1]; a[0] = HJ(); rp_226(a); }
static void rp_227(const double *a) { tr("b3x_spherical_set_target_rotation", 5, a); b3x_spherical_set_target_rotation((int)a[0], a[1], a[2], a[3], a[4]); }
static void fz_227(void) { double a[5]; a[0] = HJ(); a[1] = Q(0); a[2] = Q(1); a[3] = Q(2); a[4] = Q(3); rp_227(a); }
static void rp_228(const double *a) { tr("b3x_spherical_target_rotation", 1, a); text(b3x_spherical_target_rotation((int)a[0])); }
static void fz_228(void) { double a[1]; a[0] = HJ(); rp_228(a); }
static void rp_229(const double *a) { tr("b3x_revolute_set_limits", 3, a); b3x_revolute_set_limits((int)a[0], a[1], a[2]); }
static void fz_229(void) { double a[3]; a[0] = HJ(); a[1] = D(); a[2] = D(); rp_229(a); }
static void rp_230(const double *a) { tr("b3x_prismatic_set_limits", 3, a); b3x_prismatic_set_limits((int)a[0], a[1], a[2]); }
static void fz_230(void) { double a[3]; a[0] = HJ(); a[1] = D(); a[2] = D(); rp_230(a); }
static void rp_231(const double *a) { tr("b3x_spherical_set_twist_limits", 3, a); b3x_spherical_set_twist_limits((int)a[0], a[1], a[2]); }
static void fz_231(void) { double a[3]; a[0] = HJ(); a[1] = D(); a[2] = D(); rp_231(a); }
static void rp_232(const double *a) { tr("b3x_distance_set_length_range", 3, a); b3x_distance_set_length_range((int)a[0], a[1], a[2]); }
static void fz_232(void) { double a[3]; a[0] = HJ(); a[1] = D(); a[2] = D(); rp_232(a); }
static void rp_233(const double *a) { tr("b3x_wheel_set_suspension_limits", 3, a); b3x_wheel_set_suspension_limits((int)a[0], a[1], a[2]); }
static void fz_233(void) { double a[3]; a[0] = HJ(); a[1] = D(); a[2] = D(); rp_233(a); }
static void rp_234(const double *a) { tr("b3x_wheel_set_steering_limits", 3, a); b3x_wheel_set_steering_limits((int)a[0], a[1], a[2]); }
static void fz_234(void) { double a[3]; a[0] = HJ(); a[1] = D(); a[2] = D(); rp_234(a); }
static void rp_235(const double *a) { tr("b3x_revolute_enable_spring", 2, a); b3x_revolute_enable_spring((int)a[0], (int)a[1]); }
static void fz_235(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_235(a); }
static void rp_236(const double *a) { tr("b3x_revolute_is_spring_enabled", 1, a); s_lastInt = b3x_revolute_is_spring_enabled((int)a[0]); }
static void fz_236(void) { double a[1]; a[0] = HJ(); rp_236(a); }
static void rp_237(const double *a) { tr("b3x_revolute_set_spring_hertz", 2, a); b3x_revolute_set_spring_hertz((int)a[0], a[1]); }
static void fz_237(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_237(a); }
static void rp_238(const double *a) { tr("b3x_revolute_spring_hertz", 1, a); number(b3x_revolute_spring_hertz((int)a[0])); }
static void fz_238(void) { double a[1]; a[0] = HJ(); rp_238(a); }
static void rp_239(const double *a) { tr("b3x_revolute_set_spring_damping_ratio", 2, a); b3x_revolute_set_spring_damping_ratio((int)a[0], a[1]); }
static void fz_239(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_239(a); }
static void rp_240(const double *a) { tr("b3x_revolute_spring_damping_ratio", 1, a); number(b3x_revolute_spring_damping_ratio((int)a[0])); }
static void fz_240(void) { double a[1]; a[0] = HJ(); rp_240(a); }
static void rp_241(const double *a) { tr("b3x_revolute_set_target_angle", 2, a); b3x_revolute_set_target_angle((int)a[0], a[1]); }
static void fz_241(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_241(a); }
static void rp_242(const double *a) { tr("b3x_revolute_target_angle", 1, a); number(b3x_revolute_target_angle((int)a[0])); }
static void fz_242(void) { double a[1]; a[0] = HJ(); rp_242(a); }
static void rp_243(const double *a) { tr("b3x_revolute_angle", 1, a); number(b3x_revolute_angle((int)a[0])); }
static void fz_243(void) { double a[1]; a[0] = HJ(); rp_243(a); }
static void rp_244(const double *a) { tr("b3x_revolute_enable_limit", 2, a); b3x_revolute_enable_limit((int)a[0], (int)a[1]); }
static void fz_244(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_244(a); }
static void rp_245(const double *a) { tr("b3x_revolute_is_limit_enabled", 1, a); s_lastInt = b3x_revolute_is_limit_enabled((int)a[0]); }
static void fz_245(void) { double a[1]; a[0] = HJ(); rp_245(a); }
static void rp_246(const double *a) { tr("b3x_revolute_lower_limit", 1, a); number(b3x_revolute_lower_limit((int)a[0])); }
static void fz_246(void) { double a[1]; a[0] = HJ(); rp_246(a); }
static void rp_247(const double *a) { tr("b3x_revolute_upper_limit", 1, a); number(b3x_revolute_upper_limit((int)a[0])); }
static void fz_247(void) { double a[1]; a[0] = HJ(); rp_247(a); }
static void rp_248(const double *a) { tr("b3x_revolute_enable_motor", 2, a); b3x_revolute_enable_motor((int)a[0], (int)a[1]); }
static void fz_248(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_248(a); }
static void rp_249(const double *a) { tr("b3x_revolute_is_motor_enabled", 1, a); s_lastInt = b3x_revolute_is_motor_enabled((int)a[0]); }
static void fz_249(void) { double a[1]; a[0] = HJ(); rp_249(a); }
static void rp_250(const double *a) { tr("b3x_revolute_set_motor_speed", 2, a); b3x_revolute_set_motor_speed((int)a[0], a[1]); }
static void fz_250(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_250(a); }
static void rp_251(const double *a) { tr("b3x_revolute_motor_speed", 1, a); number(b3x_revolute_motor_speed((int)a[0])); }
static void fz_251(void) { double a[1]; a[0] = HJ(); rp_251(a); }
static void rp_252(const double *a) { tr("b3x_revolute_motor_torque", 1, a); number(b3x_revolute_motor_torque((int)a[0])); }
static void fz_252(void) { double a[1]; a[0] = HJ(); rp_252(a); }
static void rp_253(const double *a) { tr("b3x_revolute_set_max_motor_torque", 2, a); b3x_revolute_set_max_motor_torque((int)a[0], a[1]); }
static void fz_253(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_253(a); }
static void rp_254(const double *a) { tr("b3x_revolute_max_motor_torque", 1, a); number(b3x_revolute_max_motor_torque((int)a[0])); }
static void fz_254(void) { double a[1]; a[0] = HJ(); rp_254(a); }
static void rp_255(const double *a) { tr("b3x_prismatic_enable_spring", 2, a); b3x_prismatic_enable_spring((int)a[0], (int)a[1]); }
static void fz_255(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_255(a); }
static void rp_256(const double *a) { tr("b3x_prismatic_is_spring_enabled", 1, a); s_lastInt = b3x_prismatic_is_spring_enabled((int)a[0]); }
static void fz_256(void) { double a[1]; a[0] = HJ(); rp_256(a); }
static void rp_257(const double *a) { tr("b3x_prismatic_set_spring_hertz", 2, a); b3x_prismatic_set_spring_hertz((int)a[0], a[1]); }
static void fz_257(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_257(a); }
static void rp_258(const double *a) { tr("b3x_prismatic_spring_hertz", 1, a); number(b3x_prismatic_spring_hertz((int)a[0])); }
static void fz_258(void) { double a[1]; a[0] = HJ(); rp_258(a); }
static void rp_259(const double *a) { tr("b3x_prismatic_set_spring_damping_ratio", 2, a); b3x_prismatic_set_spring_damping_ratio((int)a[0], a[1]); }
static void fz_259(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_259(a); }
static void rp_260(const double *a) { tr("b3x_prismatic_spring_damping_ratio", 1, a); number(b3x_prismatic_spring_damping_ratio((int)a[0])); }
static void fz_260(void) { double a[1]; a[0] = HJ(); rp_260(a); }
static void rp_261(const double *a) { tr("b3x_prismatic_set_target_translation", 2, a); b3x_prismatic_set_target_translation((int)a[0], a[1]); }
static void fz_261(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_261(a); }
static void rp_262(const double *a) { tr("b3x_prismatic_target_translation", 1, a); number(b3x_prismatic_target_translation((int)a[0])); }
static void fz_262(void) { double a[1]; a[0] = HJ(); rp_262(a); }
static void rp_263(const double *a) { tr("b3x_prismatic_enable_limit", 2, a); b3x_prismatic_enable_limit((int)a[0], (int)a[1]); }
static void fz_263(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_263(a); }
static void rp_264(const double *a) { tr("b3x_prismatic_is_limit_enabled", 1, a); s_lastInt = b3x_prismatic_is_limit_enabled((int)a[0]); }
static void fz_264(void) { double a[1]; a[0] = HJ(); rp_264(a); }
static void rp_265(const double *a) { tr("b3x_prismatic_lower_limit", 1, a); number(b3x_prismatic_lower_limit((int)a[0])); }
static void fz_265(void) { double a[1]; a[0] = HJ(); rp_265(a); }
static void rp_266(const double *a) { tr("b3x_prismatic_upper_limit", 1, a); number(b3x_prismatic_upper_limit((int)a[0])); }
static void fz_266(void) { double a[1]; a[0] = HJ(); rp_266(a); }
static void rp_267(const double *a) { tr("b3x_prismatic_enable_motor", 2, a); b3x_prismatic_enable_motor((int)a[0], (int)a[1]); }
static void fz_267(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_267(a); }
static void rp_268(const double *a) { tr("b3x_prismatic_is_motor_enabled", 1, a); s_lastInt = b3x_prismatic_is_motor_enabled((int)a[0]); }
static void fz_268(void) { double a[1]; a[0] = HJ(); rp_268(a); }
static void rp_269(const double *a) { tr("b3x_prismatic_set_motor_speed", 2, a); b3x_prismatic_set_motor_speed((int)a[0], a[1]); }
static void fz_269(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_269(a); }
static void rp_270(const double *a) { tr("b3x_prismatic_motor_speed", 1, a); number(b3x_prismatic_motor_speed((int)a[0])); }
static void fz_270(void) { double a[1]; a[0] = HJ(); rp_270(a); }
static void rp_271(const double *a) { tr("b3x_prismatic_set_max_motor_force", 2, a); b3x_prismatic_set_max_motor_force((int)a[0], a[1]); }
static void fz_271(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_271(a); }
static void rp_272(const double *a) { tr("b3x_prismatic_max_motor_force", 1, a); number(b3x_prismatic_max_motor_force((int)a[0])); }
static void fz_272(void) { double a[1]; a[0] = HJ(); rp_272(a); }
static void rp_273(const double *a) { tr("b3x_prismatic_motor_force", 1, a); number(b3x_prismatic_motor_force((int)a[0])); }
static void fz_273(void) { double a[1]; a[0] = HJ(); rp_273(a); }
static void rp_274(const double *a) { tr("b3x_prismatic_translation", 1, a); number(b3x_prismatic_translation((int)a[0])); }
static void fz_274(void) { double a[1]; a[0] = HJ(); rp_274(a); }
static void rp_275(const double *a) { tr("b3x_prismatic_speed", 1, a); number(b3x_prismatic_speed((int)a[0])); }
static void fz_275(void) { double a[1]; a[0] = HJ(); rp_275(a); }
static void rp_276(const double *a) { tr("b3x_spherical_enable_cone_limit", 2, a); b3x_spherical_enable_cone_limit((int)a[0], (int)a[1]); }
static void fz_276(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_276(a); }
static void rp_277(const double *a) { tr("b3x_spherical_is_cone_limit_enabled", 1, a); s_lastInt = b3x_spherical_is_cone_limit_enabled((int)a[0]); }
static void fz_277(void) { double a[1]; a[0] = HJ(); rp_277(a); }
static void rp_278(const double *a) { tr("b3x_spherical_set_cone_limit", 2, a); b3x_spherical_set_cone_limit((int)a[0], a[1]); }
static void fz_278(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_278(a); }
static void rp_279(const double *a) { tr("b3x_spherical_cone_limit", 1, a); number(b3x_spherical_cone_limit((int)a[0])); }
static void fz_279(void) { double a[1]; a[0] = HJ(); rp_279(a); }
static void rp_280(const double *a) { tr("b3x_spherical_cone_angle", 1, a); number(b3x_spherical_cone_angle((int)a[0])); }
static void fz_280(void) { double a[1]; a[0] = HJ(); rp_280(a); }
static void rp_281(const double *a) { tr("b3x_spherical_enable_twist_limit", 2, a); b3x_spherical_enable_twist_limit((int)a[0], (int)a[1]); }
static void fz_281(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_281(a); }
static void rp_282(const double *a) { tr("b3x_spherical_is_twist_limit_enabled", 1, a); s_lastInt = b3x_spherical_is_twist_limit_enabled((int)a[0]); }
static void fz_282(void) { double a[1]; a[0] = HJ(); rp_282(a); }
static void rp_283(const double *a) { tr("b3x_spherical_lower_twist_limit", 1, a); number(b3x_spherical_lower_twist_limit((int)a[0])); }
static void fz_283(void) { double a[1]; a[0] = HJ(); rp_283(a); }
static void rp_284(const double *a) { tr("b3x_spherical_upper_twist_limit", 1, a); number(b3x_spherical_upper_twist_limit((int)a[0])); }
static void fz_284(void) { double a[1]; a[0] = HJ(); rp_284(a); }
static void rp_285(const double *a) { tr("b3x_spherical_twist_angle", 1, a); number(b3x_spherical_twist_angle((int)a[0])); }
static void fz_285(void) { double a[1]; a[0] = HJ(); rp_285(a); }
static void rp_286(const double *a) { tr("b3x_spherical_enable_spring", 2, a); b3x_spherical_enable_spring((int)a[0], (int)a[1]); }
static void fz_286(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_286(a); }
static void rp_287(const double *a) { tr("b3x_spherical_is_spring_enabled", 1, a); s_lastInt = b3x_spherical_is_spring_enabled((int)a[0]); }
static void fz_287(void) { double a[1]; a[0] = HJ(); rp_287(a); }
static void rp_288(const double *a) { tr("b3x_spherical_set_spring_hertz", 2, a); b3x_spherical_set_spring_hertz((int)a[0], a[1]); }
static void fz_288(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_288(a); }
static void rp_289(const double *a) { tr("b3x_spherical_spring_hertz", 1, a); number(b3x_spherical_spring_hertz((int)a[0])); }
static void fz_289(void) { double a[1]; a[0] = HJ(); rp_289(a); }
static void rp_290(const double *a) { tr("b3x_spherical_set_spring_damping_ratio", 2, a); b3x_spherical_set_spring_damping_ratio((int)a[0], a[1]); }
static void fz_290(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_290(a); }
static void rp_291(const double *a) { tr("b3x_spherical_spring_damping_ratio", 1, a); number(b3x_spherical_spring_damping_ratio((int)a[0])); }
static void fz_291(void) { double a[1]; a[0] = HJ(); rp_291(a); }
static void rp_292(const double *a) { tr("b3x_spherical_enable_motor", 2, a); b3x_spherical_enable_motor((int)a[0], (int)a[1]); }
static void fz_292(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_292(a); }
static void rp_293(const double *a) { tr("b3x_spherical_is_motor_enabled", 1, a); s_lastInt = b3x_spherical_is_motor_enabled((int)a[0]); }
static void fz_293(void) { double a[1]; a[0] = HJ(); rp_293(a); }
static void rp_294(const double *a) { tr("b3x_spherical_set_max_motor_torque", 2, a); b3x_spherical_set_max_motor_torque((int)a[0], a[1]); }
static void fz_294(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_294(a); }
static void rp_295(const double *a) { tr("b3x_spherical_max_motor_torque", 1, a); number(b3x_spherical_max_motor_torque((int)a[0])); }
static void fz_295(void) { double a[1]; a[0] = HJ(); rp_295(a); }
static void rp_296(const double *a) { tr("b3x_weld_set_linear_hertz", 2, a); b3x_weld_set_linear_hertz((int)a[0], a[1]); }
static void fz_296(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_296(a); }
static void rp_297(const double *a) { tr("b3x_weld_linear_hertz", 1, a); number(b3x_weld_linear_hertz((int)a[0])); }
static void fz_297(void) { double a[1]; a[0] = HJ(); rp_297(a); }
static void rp_298(const double *a) { tr("b3x_weld_set_linear_damping_ratio", 2, a); b3x_weld_set_linear_damping_ratio((int)a[0], a[1]); }
static void fz_298(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_298(a); }
static void rp_299(const double *a) { tr("b3x_weld_linear_damping_ratio", 1, a); number(b3x_weld_linear_damping_ratio((int)a[0])); }
static void fz_299(void) { double a[1]; a[0] = HJ(); rp_299(a); }
static void rp_300(const double *a) { tr("b3x_weld_set_angular_hertz", 2, a); b3x_weld_set_angular_hertz((int)a[0], a[1]); }
static void fz_300(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_300(a); }
static void rp_301(const double *a) { tr("b3x_weld_angular_hertz", 1, a); number(b3x_weld_angular_hertz((int)a[0])); }
static void fz_301(void) { double a[1]; a[0] = HJ(); rp_301(a); }
static void rp_302(const double *a) { tr("b3x_weld_set_angular_damping_ratio", 2, a); b3x_weld_set_angular_damping_ratio((int)a[0], a[1]); }
static void fz_302(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_302(a); }
static void rp_303(const double *a) { tr("b3x_weld_angular_damping_ratio", 1, a); number(b3x_weld_angular_damping_ratio((int)a[0])); }
static void fz_303(void) { double a[1]; a[0] = HJ(); rp_303(a); }
static void rp_304(const double *a) { tr("b3x_distance_set_length", 2, a); b3x_distance_set_length((int)a[0], a[1]); }
static void fz_304(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_304(a); }
static void rp_305(const double *a) { tr("b3x_distance_length", 1, a); number(b3x_distance_length((int)a[0])); }
static void fz_305(void) { double a[1]; a[0] = HJ(); rp_305(a); }
static void rp_306(const double *a) { tr("b3x_distance_enable_spring", 2, a); b3x_distance_enable_spring((int)a[0], (int)a[1]); }
static void fz_306(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_306(a); }
static void rp_307(const double *a) { tr("b3x_distance_is_spring_enabled", 1, a); s_lastInt = b3x_distance_is_spring_enabled((int)a[0]); }
static void fz_307(void) { double a[1]; a[0] = HJ(); rp_307(a); }
static void rp_308(const double *a) { tr("b3x_distance_set_spring_hertz", 2, a); b3x_distance_set_spring_hertz((int)a[0], a[1]); }
static void fz_308(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_308(a); }
static void rp_309(const double *a) { tr("b3x_distance_spring_hertz", 1, a); number(b3x_distance_spring_hertz((int)a[0])); }
static void fz_309(void) { double a[1]; a[0] = HJ(); rp_309(a); }
static void rp_310(const double *a) { tr("b3x_distance_set_spring_damping_ratio", 2, a); b3x_distance_set_spring_damping_ratio((int)a[0], a[1]); }
static void fz_310(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_310(a); }
static void rp_311(const double *a) { tr("b3x_distance_spring_damping_ratio", 1, a); number(b3x_distance_spring_damping_ratio((int)a[0])); }
static void fz_311(void) { double a[1]; a[0] = HJ(); rp_311(a); }
static void rp_312(const double *a) { tr("b3x_distance_enable_limit", 2, a); b3x_distance_enable_limit((int)a[0], (int)a[1]); }
static void fz_312(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_312(a); }
static void rp_313(const double *a) { tr("b3x_distance_is_limit_enabled", 1, a); s_lastInt = b3x_distance_is_limit_enabled((int)a[0]); }
static void fz_313(void) { double a[1]; a[0] = HJ(); rp_313(a); }
static void rp_314(const double *a) { tr("b3x_distance_min_length", 1, a); number(b3x_distance_min_length((int)a[0])); }
static void fz_314(void) { double a[1]; a[0] = HJ(); rp_314(a); }
static void rp_315(const double *a) { tr("b3x_distance_max_length", 1, a); number(b3x_distance_max_length((int)a[0])); }
static void fz_315(void) { double a[1]; a[0] = HJ(); rp_315(a); }
static void rp_316(const double *a) { tr("b3x_distance_current_length", 1, a); number(b3x_distance_current_length((int)a[0])); }
static void fz_316(void) { double a[1]; a[0] = HJ(); rp_316(a); }
static void rp_317(const double *a) { tr("b3x_distance_enable_motor", 2, a); b3x_distance_enable_motor((int)a[0], (int)a[1]); }
static void fz_317(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_317(a); }
static void rp_318(const double *a) { tr("b3x_distance_is_motor_enabled", 1, a); s_lastInt = b3x_distance_is_motor_enabled((int)a[0]); }
static void fz_318(void) { double a[1]; a[0] = HJ(); rp_318(a); }
static void rp_319(const double *a) { tr("b3x_distance_set_motor_speed", 2, a); b3x_distance_set_motor_speed((int)a[0], a[1]); }
static void fz_319(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_319(a); }
static void rp_320(const double *a) { tr("b3x_distance_motor_speed", 1, a); number(b3x_distance_motor_speed((int)a[0])); }
static void fz_320(void) { double a[1]; a[0] = HJ(); rp_320(a); }
static void rp_321(const double *a) { tr("b3x_distance_set_max_motor_force", 2, a); b3x_distance_set_max_motor_force((int)a[0], a[1]); }
static void fz_321(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_321(a); }
static void rp_322(const double *a) { tr("b3x_distance_max_motor_force", 1, a); number(b3x_distance_max_motor_force((int)a[0])); }
static void fz_322(void) { double a[1]; a[0] = HJ(); rp_322(a); }
static void rp_323(const double *a) { tr("b3x_distance_motor_force", 1, a); number(b3x_distance_motor_force((int)a[0])); }
static void fz_323(void) { double a[1]; a[0] = HJ(); rp_323(a); }
static void rp_324(const double *a) { tr("b3x_wheel_enable_suspension", 2, a); b3x_wheel_enable_suspension((int)a[0], (int)a[1]); }
static void fz_324(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_324(a); }
static void rp_325(const double *a) { tr("b3x_wheel_is_suspension_enabled", 1, a); s_lastInt = b3x_wheel_is_suspension_enabled((int)a[0]); }
static void fz_325(void) { double a[1]; a[0] = HJ(); rp_325(a); }
static void rp_326(const double *a) { tr("b3x_wheel_set_suspension_hertz", 2, a); b3x_wheel_set_suspension_hertz((int)a[0], a[1]); }
static void fz_326(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_326(a); }
static void rp_327(const double *a) { tr("b3x_wheel_suspension_hertz", 1, a); number(b3x_wheel_suspension_hertz((int)a[0])); }
static void fz_327(void) { double a[1]; a[0] = HJ(); rp_327(a); }
static void rp_328(const double *a) { tr("b3x_wheel_set_suspension_damping_ratio", 2, a); b3x_wheel_set_suspension_damping_ratio((int)a[0], a[1]); }
static void fz_328(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_328(a); }
static void rp_329(const double *a) { tr("b3x_wheel_suspension_damping_ratio", 1, a); number(b3x_wheel_suspension_damping_ratio((int)a[0])); }
static void fz_329(void) { double a[1]; a[0] = HJ(); rp_329(a); }
static void rp_330(const double *a) { tr("b3x_wheel_enable_suspension_limit", 2, a); b3x_wheel_enable_suspension_limit((int)a[0], (int)a[1]); }
static void fz_330(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_330(a); }
static void rp_331(const double *a) { tr("b3x_wheel_is_suspension_limit_enabled", 1, a); s_lastInt = b3x_wheel_is_suspension_limit_enabled((int)a[0]); }
static void fz_331(void) { double a[1]; a[0] = HJ(); rp_331(a); }
static void rp_332(const double *a) { tr("b3x_wheel_lower_suspension_limit", 1, a); number(b3x_wheel_lower_suspension_limit((int)a[0])); }
static void fz_332(void) { double a[1]; a[0] = HJ(); rp_332(a); }
static void rp_333(const double *a) { tr("b3x_wheel_upper_suspension_limit", 1, a); number(b3x_wheel_upper_suspension_limit((int)a[0])); }
static void fz_333(void) { double a[1]; a[0] = HJ(); rp_333(a); }
static void rp_334(const double *a) { tr("b3x_wheel_enable_spin_motor", 2, a); b3x_wheel_enable_spin_motor((int)a[0], (int)a[1]); }
static void fz_334(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_334(a); }
static void rp_335(const double *a) { tr("b3x_wheel_is_spin_motor_enabled", 1, a); s_lastInt = b3x_wheel_is_spin_motor_enabled((int)a[0]); }
static void fz_335(void) { double a[1]; a[0] = HJ(); rp_335(a); }
static void rp_336(const double *a) { tr("b3x_wheel_set_spin_motor_speed", 2, a); b3x_wheel_set_spin_motor_speed((int)a[0], a[1]); }
static void fz_336(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_336(a); }
static void rp_337(const double *a) { tr("b3x_wheel_spin_motor_speed", 1, a); number(b3x_wheel_spin_motor_speed((int)a[0])); }
static void fz_337(void) { double a[1]; a[0] = HJ(); rp_337(a); }
static void rp_338(const double *a) { tr("b3x_wheel_set_max_spin_torque", 2, a); b3x_wheel_set_max_spin_torque((int)a[0], a[1]); }
static void fz_338(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_338(a); }
static void rp_339(const double *a) { tr("b3x_wheel_max_spin_torque", 1, a); number(b3x_wheel_max_spin_torque((int)a[0])); }
static void fz_339(void) { double a[1]; a[0] = HJ(); rp_339(a); }
static void rp_340(const double *a) { tr("b3x_wheel_spin_speed", 1, a); number(b3x_wheel_spin_speed((int)a[0])); }
static void fz_340(void) { double a[1]; a[0] = HJ(); rp_340(a); }
static void rp_341(const double *a) { tr("b3x_wheel_spin_torque", 1, a); number(b3x_wheel_spin_torque((int)a[0])); }
static void fz_341(void) { double a[1]; a[0] = HJ(); rp_341(a); }
static void rp_342(const double *a) { tr("b3x_wheel_enable_steering", 2, a); b3x_wheel_enable_steering((int)a[0], (int)a[1]); }
static void fz_342(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_342(a); }
static void rp_343(const double *a) { tr("b3x_wheel_is_steering_enabled", 1, a); s_lastInt = b3x_wheel_is_steering_enabled((int)a[0]); }
static void fz_343(void) { double a[1]; a[0] = HJ(); rp_343(a); }
static void rp_344(const double *a) { tr("b3x_wheel_set_steering_hertz", 2, a); b3x_wheel_set_steering_hertz((int)a[0], a[1]); }
static void fz_344(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_344(a); }
static void rp_345(const double *a) { tr("b3x_wheel_steering_hertz", 1, a); number(b3x_wheel_steering_hertz((int)a[0])); }
static void fz_345(void) { double a[1]; a[0] = HJ(); rp_345(a); }
static void rp_346(const double *a) { tr("b3x_wheel_set_steering_damping_ratio", 2, a); b3x_wheel_set_steering_damping_ratio((int)a[0], a[1]); }
static void fz_346(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_346(a); }
static void rp_347(const double *a) { tr("b3x_wheel_steering_damping_ratio", 1, a); number(b3x_wheel_steering_damping_ratio((int)a[0])); }
static void fz_347(void) { double a[1]; a[0] = HJ(); rp_347(a); }
static void rp_348(const double *a) { tr("b3x_wheel_set_max_steering_torque", 2, a); b3x_wheel_set_max_steering_torque((int)a[0], a[1]); }
static void fz_348(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_348(a); }
static void rp_349(const double *a) { tr("b3x_wheel_max_steering_torque", 1, a); number(b3x_wheel_max_steering_torque((int)a[0])); }
static void fz_349(void) { double a[1]; a[0] = HJ(); rp_349(a); }
static void rp_350(const double *a) { tr("b3x_wheel_enable_steering_limit", 2, a); b3x_wheel_enable_steering_limit((int)a[0], (int)a[1]); }
static void fz_350(void) { double a[2]; a[0] = HJ(); a[1] = flag(); rp_350(a); }
static void rp_351(const double *a) { tr("b3x_wheel_is_steering_limit_enabled", 1, a); s_lastInt = b3x_wheel_is_steering_limit_enabled((int)a[0]); }
static void fz_351(void) { double a[1]; a[0] = HJ(); rp_351(a); }
static void rp_352(const double *a) { tr("b3x_wheel_lower_steering_limit", 1, a); number(b3x_wheel_lower_steering_limit((int)a[0])); }
static void fz_352(void) { double a[1]; a[0] = HJ(); rp_352(a); }
static void rp_353(const double *a) { tr("b3x_wheel_upper_steering_limit", 1, a); number(b3x_wheel_upper_steering_limit((int)a[0])); }
static void fz_353(void) { double a[1]; a[0] = HJ(); rp_353(a); }
static void rp_354(const double *a) { tr("b3x_wheel_set_target_steering_angle", 2, a); b3x_wheel_set_target_steering_angle((int)a[0], a[1]); }
static void fz_354(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_354(a); }
static void rp_355(const double *a) { tr("b3x_wheel_target_steering_angle", 1, a); number(b3x_wheel_target_steering_angle((int)a[0])); }
static void fz_355(void) { double a[1]; a[0] = HJ(); rp_355(a); }
static void rp_356(const double *a) { tr("b3x_wheel_steering_angle", 1, a); number(b3x_wheel_steering_angle((int)a[0])); }
static void fz_356(void) { double a[1]; a[0] = HJ(); rp_356(a); }
static void rp_357(const double *a) { tr("b3x_wheel_steering_torque", 1, a); number(b3x_wheel_steering_torque((int)a[0])); }
static void fz_357(void) { double a[1]; a[0] = HJ(); rp_357(a); }
static void rp_358(const double *a) { tr("b3x_motor_set_max_velocity_force", 2, a); b3x_motor_set_max_velocity_force((int)a[0], a[1]); }
static void fz_358(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_358(a); }
static void rp_359(const double *a) { tr("b3x_motor_max_velocity_force", 1, a); number(b3x_motor_max_velocity_force((int)a[0])); }
static void fz_359(void) { double a[1]; a[0] = HJ(); rp_359(a); }
static void rp_360(const double *a) { tr("b3x_motor_set_max_velocity_torque", 2, a); b3x_motor_set_max_velocity_torque((int)a[0], a[1]); }
static void fz_360(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_360(a); }
static void rp_361(const double *a) { tr("b3x_motor_max_velocity_torque", 1, a); number(b3x_motor_max_velocity_torque((int)a[0])); }
static void fz_361(void) { double a[1]; a[0] = HJ(); rp_361(a); }
static void rp_362(const double *a) { tr("b3x_motor_set_linear_hertz", 2, a); b3x_motor_set_linear_hertz((int)a[0], a[1]); }
static void fz_362(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_362(a); }
static void rp_363(const double *a) { tr("b3x_motor_linear_hertz", 1, a); number(b3x_motor_linear_hertz((int)a[0])); }
static void fz_363(void) { double a[1]; a[0] = HJ(); rp_363(a); }
static void rp_364(const double *a) { tr("b3x_motor_set_linear_damping_ratio", 2, a); b3x_motor_set_linear_damping_ratio((int)a[0], a[1]); }
static void fz_364(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_364(a); }
static void rp_365(const double *a) { tr("b3x_motor_linear_damping_ratio", 1, a); number(b3x_motor_linear_damping_ratio((int)a[0])); }
static void fz_365(void) { double a[1]; a[0] = HJ(); rp_365(a); }
static void rp_366(const double *a) { tr("b3x_motor_set_angular_hertz", 2, a); b3x_motor_set_angular_hertz((int)a[0], a[1]); }
static void fz_366(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_366(a); }
static void rp_367(const double *a) { tr("b3x_motor_angular_hertz", 1, a); number(b3x_motor_angular_hertz((int)a[0])); }
static void fz_367(void) { double a[1]; a[0] = HJ(); rp_367(a); }
static void rp_368(const double *a) { tr("b3x_motor_set_angular_damping_ratio", 2, a); b3x_motor_set_angular_damping_ratio((int)a[0], a[1]); }
static void fz_368(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_368(a); }
static void rp_369(const double *a) { tr("b3x_motor_angular_damping_ratio", 1, a); number(b3x_motor_angular_damping_ratio((int)a[0])); }
static void fz_369(void) { double a[1]; a[0] = HJ(); rp_369(a); }
static void rp_370(const double *a) { tr("b3x_motor_set_max_spring_force", 2, a); b3x_motor_set_max_spring_force((int)a[0], a[1]); }
static void fz_370(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_370(a); }
static void rp_371(const double *a) { tr("b3x_motor_max_spring_force", 1, a); number(b3x_motor_max_spring_force((int)a[0])); }
static void fz_371(void) { double a[1]; a[0] = HJ(); rp_371(a); }
static void rp_372(const double *a) { tr("b3x_motor_set_max_spring_torque", 2, a); b3x_motor_set_max_spring_torque((int)a[0], a[1]); }
static void fz_372(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_372(a); }
static void rp_373(const double *a) { tr("b3x_motor_max_spring_torque", 1, a); number(b3x_motor_max_spring_torque((int)a[0])); }
static void fz_373(void) { double a[1]; a[0] = HJ(); rp_373(a); }
static void rp_374(const double *a) { tr("b3x_parallel_set_spring_hertz", 2, a); b3x_parallel_set_spring_hertz((int)a[0], a[1]); }
static void fz_374(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_374(a); }
static void rp_375(const double *a) { tr("b3x_parallel_spring_hertz", 1, a); number(b3x_parallel_spring_hertz((int)a[0])); }
static void fz_375(void) { double a[1]; a[0] = HJ(); rp_375(a); }
static void rp_376(const double *a) { tr("b3x_parallel_set_spring_damping_ratio", 2, a); b3x_parallel_set_spring_damping_ratio((int)a[0], a[1]); }
static void fz_376(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_376(a); }
static void rp_377(const double *a) { tr("b3x_parallel_spring_damping_ratio", 1, a); number(b3x_parallel_spring_damping_ratio((int)a[0])); }
static void fz_377(void) { double a[1]; a[0] = HJ(); rp_377(a); }
static void rp_378(const double *a) { tr("b3x_parallel_set_max_torque", 2, a); b3x_parallel_set_max_torque((int)a[0], a[1]); }
static void fz_378(void) { double a[2]; a[0] = HJ(); a[1] = D(); rp_378(a); }
static void rp_379(const double *a) { tr("b3x_parallel_max_torque", 1, a); number(b3x_parallel_max_torque((int)a[0])); }
static void fz_379(void) { double a[1]; a[0] = HJ(); rp_379(a); }
typedef struct { const char *name; int argc; void (*call)(void); void (*replay)(const double *); } FuzzCall;
static const FuzzCall k_fuzz[] = {
    { "b3x_abi_version", 0, fz_0, rp_0 },
    { "b3x_library_version", 0, fz_1, rp_1 },
    { "b3x_last_error", 0, fz_2, rp_2 },
    { "b3x_assert_count", 0, fz_4, rp_4 },
    { "b3x_assert_text", 0, fz_5, rp_5 },
    { "b3x_has_avx2", 0, fz_6, rp_6 },
    { "b3x_world_create", 4, fz_7, rp_7 },
    { "b3x_world_destroy", 1, fz_8, rp_8 },
    { "b3x_world_is_valid", 1, fz_9, rp_9 },
    { "b3x_unstable_count", 0, fz_10, rp_10 },
    { "b3x_world_step", 3, fz_11, rp_11 },
    { "b3x_world_set_gravity", 4, fz_12, rp_12 },
    { "b3x_world_gravity", 1, fz_13, rp_13 },
    { "b3x_world_enable_sleeping", 2, fz_14, rp_14 },
    { "b3x_world_is_sleeping_enabled", 1, fz_15, rp_15 },
    { "b3x_world_enable_continuous", 2, fz_16, rp_16 },
    { "b3x_world_is_continuous_enabled", 1, fz_17, rp_17 },
    { "b3x_world_set_restitution_threshold", 2, fz_18, rp_18 },
    { "b3x_world_restitution_threshold", 1, fz_19, rp_19 },
    { "b3x_world_set_hit_event_threshold", 2, fz_20, rp_20 },
    { "b3x_world_hit_event_threshold", 1, fz_21, rp_21 },
    { "b3x_world_set_contact_tuning", 4, fz_22, rp_22 },
    { "b3x_world_set_max_linear_speed", 2, fz_23, rp_23 },
    { "b3x_world_max_linear_speed", 1, fz_24, rp_24 },
    { "b3x_world_set_worker_count", 2, fz_25, rp_25 },
    { "b3x_world_worker_count", 1, fz_26, rp_26 },
    { "b3x_world_body_count", 1, fz_27, rp_27 },
    { "b3x_world_shape_count", 1, fz_28, rp_28 },
    { "b3x_world_joint_count", 1, fz_29, rp_29 },
    { "b3x_world_contact_count", 1, fz_30, rp_30 },
    { "b3x_world_awake_body_count", 1, fz_31, rp_31 },
    { "b3x_world_step_ms", 1, fz_32, rp_32 },
    { "b3x_world_bounds", 1, fz_33, rp_33 },
    { "b3x_world_explode", 7, fz_34, rp_34 },
    { "b3x_body_create", 5, fz_35, rp_35 },
    { "b3x_body_create_rotated", 9, fz_36, rp_36 },
    { "b3x_body_destroy", 1, fz_37, rp_37 },
    { "b3x_body_is_valid", 1, fz_38, rp_38 },
    { "b3x_body_type", 1, fz_39, rp_39 },
    { "b3x_body_set_type", 2, fz_40, rp_40 },
    { "b3x_body_world", 1, fz_41, rp_41 },
    { "b3x_body_position", 1, fz_42, rp_42 },
    { "b3x_body_x", 1, fz_43, rp_43 },
    { "b3x_body_y", 1, fz_44, rp_44 },
    { "b3x_body_z", 1, fz_45, rp_45 },
    { "b3x_body_rotation", 1, fz_46, rp_46 },
    { "b3x_body_transform", 1, fz_47, rp_47 },
    { "b3x_body_matrix", 1, fz_48, rp_48 },
    { "b3x_body_set_transform", 8, fz_49, rp_49 },
    { "b3x_body_set_position", 4, fz_50, rp_50 },
    { "b3x_body_set_rotation", 5, fz_51, rp_51 },
    { "b3x_body_set_target_transform", 10, fz_52, rp_52 },
    { "b3x_body_velocity", 1, fz_53, rp_53 },
    { "b3x_body_angular_velocity", 1, fz_54, rp_54 },
    { "b3x_body_speed", 1, fz_55, rp_55 },
    { "b3x_body_set_velocity", 4, fz_56, rp_56 },
    { "b3x_body_set_angular_velocity", 4, fz_57, rp_57 },
    { "b3x_body_apply_force", 8, fz_58, rp_58 },
    { "b3x_body_apply_force_to_center", 5, fz_59, rp_59 },
    { "b3x_body_apply_torque", 5, fz_60, rp_60 },
    { "b3x_body_apply_impulse", 8, fz_61, rp_61 },
    { "b3x_body_apply_impulse_to_center", 5, fz_62, rp_62 },
    { "b3x_body_apply_angular_impulse", 5, fz_63, rp_63 },
    { "b3x_body_mass", 1, fz_64, rp_64 },
    { "b3x_body_apply_mass_from_shapes", 1, fz_65, rp_65 },
    { "b3x_body_local_center", 1, fz_66, rp_66 },
    { "b3x_body_world_center", 1, fz_67, rp_67 },
    { "b3x_body_local_point", 4, fz_68, rp_68 },
    { "b3x_body_world_point", 4, fz_69, rp_69 },
    { "b3x_body_local_vector", 4, fz_70, rp_70 },
    { "b3x_body_world_vector", 4, fz_71, rp_71 },
    { "b3x_body_point_velocity", 4, fz_72, rp_72 },
    { "b3x_body_set_linear_damping", 2, fz_73, rp_73 },
    { "b3x_body_linear_damping", 1, fz_74, rp_74 },
    { "b3x_body_set_angular_damping", 2, fz_75, rp_75 },
    { "b3x_body_angular_damping", 1, fz_76, rp_76 },
    { "b3x_body_set_gravity_scale", 2, fz_77, rp_77 },
    { "b3x_body_gravity_scale", 1, fz_78, rp_78 },
    { "b3x_body_is_awake", 1, fz_79, rp_79 },
    { "b3x_body_set_awake", 2, fz_80, rp_80 },
    { "b3x_body_enable_sleep", 2, fz_81, rp_81 },
    { "b3x_body_is_sleep_enabled", 1, fz_82, rp_82 },
    { "b3x_body_set_sleep_threshold", 2, fz_83, rp_83 },
    { "b3x_body_sleep_threshold", 1, fz_84, rp_84 },
    { "b3x_body_is_enabled", 1, fz_85, rp_85 },
    { "b3x_body_enable", 1, fz_86, rp_86 },
    { "b3x_body_disable", 1, fz_87, rp_87 },
    { "b3x_body_set_bullet", 2, fz_88, rp_88 },
    { "b3x_body_is_bullet", 1, fz_89, rp_89 },
    { "b3x_body_set_motion_locks", 7, fz_90, rp_90 },
    { "b3x_body_motion_locks", 1, fz_91, rp_91 },
    { "b3x_body_enable_hit_events", 2, fz_92, rp_92 },
    { "b3x_body_aabb", 1, fz_93, rp_93 },
    { "b3x_body_shape_count", 1, fz_94, rp_94 },
    { "b3x_body_joint_count", 1, fz_95, rp_95 },
    { "b3x_list_count", 0, fz_96, rp_96 },
    { "b3x_list_item", 1, fz_97, rp_97 },
    { "b3x_body_list_shapes", 1, fz_98, rp_98 },
    { "b3x_body_list_joints", 1, fz_99, rp_99 },
    { "b3x_body_list_touching", 1, fz_100, rp_100 },
    { "b3x_shape_options_reset", 0, fz_101, rp_101 },
    { "b3x_shape_options_set_sensor", 1, fz_102, rp_102 },
    { "b3x_shape_options_set_events", 3, fz_103, rp_103 },
    { "b3x_shape_options_set_filter", 3, fz_104, rp_104 },
    { "b3x_shape_options_set_rolling_resistance", 1, fz_105, rp_105 },
    { "b3x_geometry_begin", 0, fz_106, rp_106 },
    { "b3x_geometry_add_point", 3, fz_107, rp_107 },
    { "b3x_geometry_add_triangle", 3, fz_108, rp_108 },
    { "b3x_geometry_add_height", 1, fz_109, rp_109 },
    { "b3x_geometry_point_count", 0, fz_110, rp_110 },
    { "b3x_shape_add_sphere", 8, fz_111, rp_111 },
    { "b3x_shape_add_capsule", 11, fz_112, rp_112 },
    { "b3x_shape_add_box", 7, fz_113, rp_113 },
    { "b3x_shape_add_box_at", 14, fz_114, rp_114 },
    { "b3x_shape_add_cylinder", 7, fz_115, rp_115 },
    { "b3x_shape_add_cone", 8, fz_116, rp_116 },
    { "b3x_shape_add_hull", 4, fz_117, rp_117 },
    { "b3x_shape_add_mesh", 3, fz_118, rp_118 },
    { "b3x_shape_add_height_field", 8, fz_119, rp_119 },
    { "b3x_shape_destroy", 2, fz_120, rp_120 },
    { "b3x_shape_is_valid", 1, fz_121, rp_121 },
    { "b3x_shape_type", 1, fz_122, rp_122 },
    { "b3x_shape_body", 1, fz_123, rp_123 },
    { "b3x_shape_is_sensor", 1, fz_124, rp_124 },
    { "b3x_shape_set_density", 3, fz_125, rp_125 },
    { "b3x_shape_density", 1, fz_126, rp_126 },
    { "b3x_shape_set_friction", 2, fz_127, rp_127 },
    { "b3x_shape_friction", 1, fz_128, rp_128 },
    { "b3x_shape_set_restitution", 2, fz_129, rp_129 },
    { "b3x_shape_restitution", 1, fz_130, rp_130 },
    { "b3x_shape_set_rolling_resistance", 2, fz_131, rp_131 },
    { "b3x_shape_rolling_resistance", 1, fz_132, rp_132 },
    { "b3x_shape_set_filter", 4, fz_133, rp_133 },
    { "b3x_shape_filter", 1, fz_134, rp_134 },
    { "b3x_shape_enable_contact_events", 2, fz_135, rp_135 },
    { "b3x_shape_are_contact_events_enabled", 1, fz_136, rp_136 },
    { "b3x_shape_enable_hit_events", 2, fz_137, rp_137 },
    { "b3x_shape_are_hit_events_enabled", 1, fz_138, rp_138 },
    { "b3x_shape_enable_sensor_events", 2, fz_139, rp_139 },
    { "b3x_shape_are_sensor_events_enabled", 1, fz_140, rp_140 },
    { "b3x_shape_aabb", 1, fz_141, rp_141 },
    { "b3x_shape_closest_point", 4, fz_142, rp_142 },
    { "b3x_shape_list_sensor_visitors", 1, fz_143, rp_143 },
    { "b3x_query_set_filter", 2, fz_144, rp_144 },
    { "b3x_query_reset_filter", 0, fz_145, rp_145 },
    { "b3x_cast_ray", 7, fz_146, rp_146 },
    { "b3x_cast_ray_closest", 7, fz_147, rp_147 },
    { "b3x_cast_sphere", 8, fz_148, rp_148 },
    { "b3x_hit_count", 0, fz_149, rp_149 },
    { "b3x_hit_shape", 1, fz_150, rp_150 },
    { "b3x_hit_body", 1, fz_151, rp_151 },
    { "b3x_hit_fraction", 1, fz_152, rp_152 },
    { "b3x_hit_point", 1, fz_153, rp_153 },
    { "b3x_hit_normal", 1, fz_154, rp_154 },
    { "b3x_overlap_aabb", 7, fz_155, rp_155 },
    { "b3x_overlap_sphere", 5, fz_156, rp_156 },
    { "b3x_world_update_contact_events", 1, fz_157, rp_157 },
    { "b3x_contact_begin_count", 0, fz_158, rp_158 },
    { "b3x_contact_begin_shape_a", 1, fz_159, rp_159 },
    { "b3x_contact_begin_shape_b", 1, fz_160, rp_160 },
    { "b3x_contact_end_count", 0, fz_161, rp_161 },
    { "b3x_contact_end_shape_a", 1, fz_162, rp_162 },
    { "b3x_contact_end_shape_b", 1, fz_163, rp_163 },
    { "b3x_contact_hit_count", 0, fz_164, rp_164 },
    { "b3x_contact_hit_shape_a", 1, fz_165, rp_165 },
    { "b3x_contact_hit_shape_b", 1, fz_166, rp_166 },
    { "b3x_contact_hit_speed", 1, fz_167, rp_167 },
    { "b3x_contact_hit_point", 1, fz_168, rp_168 },
    { "b3x_contact_hit_normal", 1, fz_169, rp_169 },
    { "b3x_world_update_sensor_events", 1, fz_170, rp_170 },
    { "b3x_sensor_begin_count", 0, fz_171, rp_171 },
    { "b3x_sensor_begin_sensor", 1, fz_172, rp_172 },
    { "b3x_sensor_begin_visitor", 1, fz_173, rp_173 },
    { "b3x_sensor_end_count", 0, fz_174, rp_174 },
    { "b3x_sensor_end_sensor", 1, fz_175, rp_175 },
    { "b3x_sensor_end_visitor", 1, fz_176, rp_176 },
    { "b3x_world_update_moves", 1, fz_177, rp_177 },
    { "b3x_move_count", 0, fz_178, rp_178 },
    { "b3x_move_body", 1, fz_179, rp_179 },
    { "b3x_move_fell_asleep", 1, fz_180, rp_180 },
    { "b3x_move_transform", 1, fz_181, rp_181 },
    { "b3x_moves_text", 0, fz_182, rp_182 },
    { "b3x_world_update_joint_events", 1, fz_183, rp_183 },
    { "b3x_joint_event_count", 0, fz_184, rp_184 },
    { "b3x_joint_event_joint", 1, fz_185, rp_185 },
    { "b3x_quat_from_axis_angle", 4, fz_186, rp_186 },
    { "b3x_quat_from_euler", 3, fz_187, rp_187 },
    { "b3x_quat_multiply", 8, fz_188, rp_188 },
    { "b3x_quat_rotate", 7, fz_189, rp_189 },
    { "b3x_quat_to_axis_angle", 4, fz_190, rp_190 },
    { "b3x_joint_revolute", 10, fz_191, rp_191 },
    { "b3x_joint_prismatic", 10, fz_192, rp_192 },
    { "b3x_joint_spherical", 10, fz_193, rp_193 },
    { "b3x_joint_weld", 7, fz_194, rp_194 },
    { "b3x_joint_distance", 10, fz_195, rp_195 },
    { "b3x_joint_wheel", 13, fz_196, rp_196 },
    { "b3x_joint_motor", 4, fz_197, rp_197 },
    { "b3x_joint_parallel", 7, fz_198, rp_198 },
    { "b3x_joint_filter", 3, fz_199, rp_199 },
    { "b3x_joint_destroy", 2, fz_200, rp_200 },
    { "b3x_joint_is_valid", 1, fz_201, rp_201 },
    { "b3x_joint_type", 1, fz_202, rp_202 },
    { "b3x_joint_body_a", 1, fz_203, rp_203 },
    { "b3x_joint_body_b", 1, fz_204, rp_204 },
    { "b3x_joint_set_collide_connected", 2, fz_205, rp_205 },
    { "b3x_joint_collide_connected", 1, fz_206, rp_206 },
    { "b3x_joint_wake_bodies", 1, fz_207, rp_207 },
    { "b3x_joint_local_frame_a", 1, fz_208, rp_208 },
    { "b3x_joint_local_frame_b", 1, fz_209, rp_209 },
    { "b3x_joint_set_local_frame_a", 8, fz_210, rp_210 },
    { "b3x_joint_set_local_frame_b", 8, fz_211, rp_211 },
    { "b3x_joint_constraint_force", 1, fz_212, rp_212 },
    { "b3x_joint_constraint_torque", 1, fz_213, rp_213 },
    { "b3x_joint_linear_separation", 1, fz_214, rp_214 },
    { "b3x_joint_angular_separation", 1, fz_215, rp_215 },
    { "b3x_joint_set_force_threshold", 2, fz_216, rp_216 },
    { "b3x_joint_force_threshold", 1, fz_217, rp_217 },
    { "b3x_joint_set_torque_threshold", 2, fz_218, rp_218 },
    { "b3x_joint_torque_threshold", 1, fz_219, rp_219 },
    { "b3x_motor_set_linear_velocity", 4, fz_220, rp_220 },
    { "b3x_motor_linear_velocity", 1, fz_221, rp_221 },
    { "b3x_motor_set_angular_velocity", 4, fz_222, rp_222 },
    { "b3x_motor_angular_velocity", 1, fz_223, rp_223 },
    { "b3x_spherical_set_motor_velocity", 4, fz_224, rp_224 },
    { "b3x_spherical_motor_velocity", 1, fz_225, rp_225 },
    { "b3x_spherical_motor_torque", 1, fz_226, rp_226 },
    { "b3x_spherical_set_target_rotation", 5, fz_227, rp_227 },
    { "b3x_spherical_target_rotation", 1, fz_228, rp_228 },
    { "b3x_revolute_set_limits", 3, fz_229, rp_229 },
    { "b3x_prismatic_set_limits", 3, fz_230, rp_230 },
    { "b3x_spherical_set_twist_limits", 3, fz_231, rp_231 },
    { "b3x_distance_set_length_range", 3, fz_232, rp_232 },
    { "b3x_wheel_set_suspension_limits", 3, fz_233, rp_233 },
    { "b3x_wheel_set_steering_limits", 3, fz_234, rp_234 },
    { "b3x_revolute_enable_spring", 2, fz_235, rp_235 },
    { "b3x_revolute_is_spring_enabled", 1, fz_236, rp_236 },
    { "b3x_revolute_set_spring_hertz", 2, fz_237, rp_237 },
    { "b3x_revolute_spring_hertz", 1, fz_238, rp_238 },
    { "b3x_revolute_set_spring_damping_ratio", 2, fz_239, rp_239 },
    { "b3x_revolute_spring_damping_ratio", 1, fz_240, rp_240 },
    { "b3x_revolute_set_target_angle", 2, fz_241, rp_241 },
    { "b3x_revolute_target_angle", 1, fz_242, rp_242 },
    { "b3x_revolute_angle", 1, fz_243, rp_243 },
    { "b3x_revolute_enable_limit", 2, fz_244, rp_244 },
    { "b3x_revolute_is_limit_enabled", 1, fz_245, rp_245 },
    { "b3x_revolute_lower_limit", 1, fz_246, rp_246 },
    { "b3x_revolute_upper_limit", 1, fz_247, rp_247 },
    { "b3x_revolute_enable_motor", 2, fz_248, rp_248 },
    { "b3x_revolute_is_motor_enabled", 1, fz_249, rp_249 },
    { "b3x_revolute_set_motor_speed", 2, fz_250, rp_250 },
    { "b3x_revolute_motor_speed", 1, fz_251, rp_251 },
    { "b3x_revolute_motor_torque", 1, fz_252, rp_252 },
    { "b3x_revolute_set_max_motor_torque", 2, fz_253, rp_253 },
    { "b3x_revolute_max_motor_torque", 1, fz_254, rp_254 },
    { "b3x_prismatic_enable_spring", 2, fz_255, rp_255 },
    { "b3x_prismatic_is_spring_enabled", 1, fz_256, rp_256 },
    { "b3x_prismatic_set_spring_hertz", 2, fz_257, rp_257 },
    { "b3x_prismatic_spring_hertz", 1, fz_258, rp_258 },
    { "b3x_prismatic_set_spring_damping_ratio", 2, fz_259, rp_259 },
    { "b3x_prismatic_spring_damping_ratio", 1, fz_260, rp_260 },
    { "b3x_prismatic_set_target_translation", 2, fz_261, rp_261 },
    { "b3x_prismatic_target_translation", 1, fz_262, rp_262 },
    { "b3x_prismatic_enable_limit", 2, fz_263, rp_263 },
    { "b3x_prismatic_is_limit_enabled", 1, fz_264, rp_264 },
    { "b3x_prismatic_lower_limit", 1, fz_265, rp_265 },
    { "b3x_prismatic_upper_limit", 1, fz_266, rp_266 },
    { "b3x_prismatic_enable_motor", 2, fz_267, rp_267 },
    { "b3x_prismatic_is_motor_enabled", 1, fz_268, rp_268 },
    { "b3x_prismatic_set_motor_speed", 2, fz_269, rp_269 },
    { "b3x_prismatic_motor_speed", 1, fz_270, rp_270 },
    { "b3x_prismatic_set_max_motor_force", 2, fz_271, rp_271 },
    { "b3x_prismatic_max_motor_force", 1, fz_272, rp_272 },
    { "b3x_prismatic_motor_force", 1, fz_273, rp_273 },
    { "b3x_prismatic_translation", 1, fz_274, rp_274 },
    { "b3x_prismatic_speed", 1, fz_275, rp_275 },
    { "b3x_spherical_enable_cone_limit", 2, fz_276, rp_276 },
    { "b3x_spherical_is_cone_limit_enabled", 1, fz_277, rp_277 },
    { "b3x_spherical_set_cone_limit", 2, fz_278, rp_278 },
    { "b3x_spherical_cone_limit", 1, fz_279, rp_279 },
    { "b3x_spherical_cone_angle", 1, fz_280, rp_280 },
    { "b3x_spherical_enable_twist_limit", 2, fz_281, rp_281 },
    { "b3x_spherical_is_twist_limit_enabled", 1, fz_282, rp_282 },
    { "b3x_spherical_lower_twist_limit", 1, fz_283, rp_283 },
    { "b3x_spherical_upper_twist_limit", 1, fz_284, rp_284 },
    { "b3x_spherical_twist_angle", 1, fz_285, rp_285 },
    { "b3x_spherical_enable_spring", 2, fz_286, rp_286 },
    { "b3x_spherical_is_spring_enabled", 1, fz_287, rp_287 },
    { "b3x_spherical_set_spring_hertz", 2, fz_288, rp_288 },
    { "b3x_spherical_spring_hertz", 1, fz_289, rp_289 },
    { "b3x_spherical_set_spring_damping_ratio", 2, fz_290, rp_290 },
    { "b3x_spherical_spring_damping_ratio", 1, fz_291, rp_291 },
    { "b3x_spherical_enable_motor", 2, fz_292, rp_292 },
    { "b3x_spherical_is_motor_enabled", 1, fz_293, rp_293 },
    { "b3x_spherical_set_max_motor_torque", 2, fz_294, rp_294 },
    { "b3x_spherical_max_motor_torque", 1, fz_295, rp_295 },
    { "b3x_weld_set_linear_hertz", 2, fz_296, rp_296 },
    { "b3x_weld_linear_hertz", 1, fz_297, rp_297 },
    { "b3x_weld_set_linear_damping_ratio", 2, fz_298, rp_298 },
    { "b3x_weld_linear_damping_ratio", 1, fz_299, rp_299 },
    { "b3x_weld_set_angular_hertz", 2, fz_300, rp_300 },
    { "b3x_weld_angular_hertz", 1, fz_301, rp_301 },
    { "b3x_weld_set_angular_damping_ratio", 2, fz_302, rp_302 },
    { "b3x_weld_angular_damping_ratio", 1, fz_303, rp_303 },
    { "b3x_distance_set_length", 2, fz_304, rp_304 },
    { "b3x_distance_length", 1, fz_305, rp_305 },
    { "b3x_distance_enable_spring", 2, fz_306, rp_306 },
    { "b3x_distance_is_spring_enabled", 1, fz_307, rp_307 },
    { "b3x_distance_set_spring_hertz", 2, fz_308, rp_308 },
    { "b3x_distance_spring_hertz", 1, fz_309, rp_309 },
    { "b3x_distance_set_spring_damping_ratio", 2, fz_310, rp_310 },
    { "b3x_distance_spring_damping_ratio", 1, fz_311, rp_311 },
    { "b3x_distance_enable_limit", 2, fz_312, rp_312 },
    { "b3x_distance_is_limit_enabled", 1, fz_313, rp_313 },
    { "b3x_distance_min_length", 1, fz_314, rp_314 },
    { "b3x_distance_max_length", 1, fz_315, rp_315 },
    { "b3x_distance_current_length", 1, fz_316, rp_316 },
    { "b3x_distance_enable_motor", 2, fz_317, rp_317 },
    { "b3x_distance_is_motor_enabled", 1, fz_318, rp_318 },
    { "b3x_distance_set_motor_speed", 2, fz_319, rp_319 },
    { "b3x_distance_motor_speed", 1, fz_320, rp_320 },
    { "b3x_distance_set_max_motor_force", 2, fz_321, rp_321 },
    { "b3x_distance_max_motor_force", 1, fz_322, rp_322 },
    { "b3x_distance_motor_force", 1, fz_323, rp_323 },
    { "b3x_wheel_enable_suspension", 2, fz_324, rp_324 },
    { "b3x_wheel_is_suspension_enabled", 1, fz_325, rp_325 },
    { "b3x_wheel_set_suspension_hertz", 2, fz_326, rp_326 },
    { "b3x_wheel_suspension_hertz", 1, fz_327, rp_327 },
    { "b3x_wheel_set_suspension_damping_ratio", 2, fz_328, rp_328 },
    { "b3x_wheel_suspension_damping_ratio", 1, fz_329, rp_329 },
    { "b3x_wheel_enable_suspension_limit", 2, fz_330, rp_330 },
    { "b3x_wheel_is_suspension_limit_enabled", 1, fz_331, rp_331 },
    { "b3x_wheel_lower_suspension_limit", 1, fz_332, rp_332 },
    { "b3x_wheel_upper_suspension_limit", 1, fz_333, rp_333 },
    { "b3x_wheel_enable_spin_motor", 2, fz_334, rp_334 },
    { "b3x_wheel_is_spin_motor_enabled", 1, fz_335, rp_335 },
    { "b3x_wheel_set_spin_motor_speed", 2, fz_336, rp_336 },
    { "b3x_wheel_spin_motor_speed", 1, fz_337, rp_337 },
    { "b3x_wheel_set_max_spin_torque", 2, fz_338, rp_338 },
    { "b3x_wheel_max_spin_torque", 1, fz_339, rp_339 },
    { "b3x_wheel_spin_speed", 1, fz_340, rp_340 },
    { "b3x_wheel_spin_torque", 1, fz_341, rp_341 },
    { "b3x_wheel_enable_steering", 2, fz_342, rp_342 },
    { "b3x_wheel_is_steering_enabled", 1, fz_343, rp_343 },
    { "b3x_wheel_set_steering_hertz", 2, fz_344, rp_344 },
    { "b3x_wheel_steering_hertz", 1, fz_345, rp_345 },
    { "b3x_wheel_set_steering_damping_ratio", 2, fz_346, rp_346 },
    { "b3x_wheel_steering_damping_ratio", 1, fz_347, rp_347 },
    { "b3x_wheel_set_max_steering_torque", 2, fz_348, rp_348 },
    { "b3x_wheel_max_steering_torque", 1, fz_349, rp_349 },
    { "b3x_wheel_enable_steering_limit", 2, fz_350, rp_350 },
    { "b3x_wheel_is_steering_limit_enabled", 1, fz_351, rp_351 },
    { "b3x_wheel_lower_steering_limit", 1, fz_352, rp_352 },
    { "b3x_wheel_upper_steering_limit", 1, fz_353, rp_353 },
    { "b3x_wheel_set_target_steering_angle", 2, fz_354, rp_354 },
    { "b3x_wheel_target_steering_angle", 1, fz_355, rp_355 },
    { "b3x_wheel_steering_angle", 1, fz_356, rp_356 },
    { "b3x_wheel_steering_torque", 1, fz_357, rp_357 },
    { "b3x_motor_set_max_velocity_force", 2, fz_358, rp_358 },
    { "b3x_motor_max_velocity_force", 1, fz_359, rp_359 },
    { "b3x_motor_set_max_velocity_torque", 2, fz_360, rp_360 },
    { "b3x_motor_max_velocity_torque", 1, fz_361, rp_361 },
    { "b3x_motor_set_linear_hertz", 2, fz_362, rp_362 },
    { "b3x_motor_linear_hertz", 1, fz_363, rp_363 },
    { "b3x_motor_set_linear_damping_ratio", 2, fz_364, rp_364 },
    { "b3x_motor_linear_damping_ratio", 1, fz_365, rp_365 },
    { "b3x_motor_set_angular_hertz", 2, fz_366, rp_366 },
    { "b3x_motor_angular_hertz", 1, fz_367, rp_367 },
    { "b3x_motor_set_angular_damping_ratio", 2, fz_368, rp_368 },
    { "b3x_motor_angular_damping_ratio", 1, fz_369, rp_369 },
    { "b3x_motor_set_max_spring_force", 2, fz_370, rp_370 },
    { "b3x_motor_max_spring_force", 1, fz_371, rp_371 },
    { "b3x_motor_set_max_spring_torque", 2, fz_372, rp_372 },
    { "b3x_motor_max_spring_torque", 1, fz_373, rp_373 },
    { "b3x_parallel_set_spring_hertz", 2, fz_374, rp_374 },
    { "b3x_parallel_spring_hertz", 1, fz_375, rp_375 },
    { "b3x_parallel_set_spring_damping_ratio", 2, fz_376, rp_376 },
    { "b3x_parallel_spring_damping_ratio", 1, fz_377, rp_377 },
    { "b3x_parallel_set_max_torque", 2, fz_378, rp_378 },
    { "b3x_parallel_max_torque", 1, fz_379, rp_379 },
};
/* <<< END FUZZ CALLS <<< */

/* ------------------------------------------------------------------ */
/* A scene to start from, so the random calls land on live things: a   */
/* floor, bodies of every shape kind, and one joint of every kind.     */
/* ------------------------------------------------------------------ */
static const FuzzCall *find_call(const char *name)
{
    int n = (int)(sizeof(k_fuzz) / sizeof(k_fuzz[0]));
    for (int i = 0; i < n; i++) if (strcmp(k_fuzz[i].name, name) == 0) return &k_fuzz[i];
    return NULL;
}
/* One call BY NAME, through the same thunk a random call uses, so the seed
 * scene is in the trace and a replay rebuilds it. Returns an int result. */
static int C(const char *name, int n, ...)
{
    double a[16] = { 0 };
    const FuzzCall *c = find_call(name);
    va_list ap;
    va_start(ap, n);
    for (int i = 0; i < n && i < 16; i++) a[i] = va_arg(ap, double);
    va_end(ap);
    if (!c || c->argc != n) { finding("the seed scene names a call the shim does not have, or miscounts it", name); return 0; }
    s_current = name;
    s_lastInt = 0;
    c->replay(a);
    return s_lastInt;
}
static void seed_scene(void)
{
    double w = C("b3x_world_create", 4, 0.0, -10.0, 0.0, (double)(1 + below(2)));
    double ground = C("b3x_body_create", 5, w, 0.0, 0.0, -1.0, 0.0);
    C("b3x_shape_add_box", 7, ground, 30.0, 1.0, 30.0, 0.0, 0.6, 0.0);
    double prev = ground;
    for (int i = 0; i < 14; i++) {
        double x = (i % 4) * 1.5 - 3, y = 1 + i * 0.8, z = (i % 3) - 1;
        double b = C("b3x_body_create", 5, w, 2.0, x, y, z);
        switch (i % 5) {
        case 0: C("b3x_shape_add_sphere", 8, b, 0.0, 0.0, 0.0, 0.4, 1.0, 0.5, 0.2); break;
        case 1: C("b3x_shape_add_box", 7, b, 0.4, 0.3, 0.5, 1.0, 0.5, 0.0); break;
        case 2: C("b3x_shape_add_capsule", 11, b, 0.0, -0.3, 0.0, 0.0, 0.3, 0.0, 0.25, 1.0, 0.5, 0.0); break;
        case 3: C("b3x_shape_add_cylinder", 7, b, 0.6, 0.3, 10.0, 1.0, 0.5, 0.0); break;
        default: C("b3x_shape_add_cone", 8, b, 0.6, 0.3, 0.1, 8.0, 1.0, 0.5, 0.0); break;
        }
        switch (i) {
        case 1: C("b3x_joint_revolute", 10, w, prev, b, x, y, z, 0.0, 0.0, 1.0, 0.0); break;
        case 2: C("b3x_joint_prismatic", 10, w, prev, b, x, y, z, 1.0, 0.0, 0.0, 0.0); break;
        case 3: C("b3x_joint_spherical", 10, w, prev, b, x, y, z, 0.0, 1.0, 0.0, 0.0); break;
        case 4: C("b3x_joint_weld", 7, w, prev, b, x, y, z, 0.0); break;
        case 5: C("b3x_joint_distance", 10, w, prev, b, x, y, z, x, y + 1, z, 1.0); break;
        case 6: C("b3x_joint_wheel", 13, w, prev, b, x, y, z, 0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 0.0); break;
        case 7: C("b3x_joint_motor", 4, w, prev, b, 1.0); break;
        case 8: C("b3x_joint_parallel", 7, w, prev, b, 0.0, 1.0, 0.0, 1.0); break;
        case 9: C("b3x_joint_filter", 3, w, prev, b); break;
        default: break;
        }
        prev = b;
    }
}

/* In a build with Box3D's asserts on, each one a call provokes is named once
 * (the shim counts them and carries on, as a Release build does). */
#define ASSERT_KINDS 64
static char s_assertSeen[ASSERT_KINDS][200];
static int s_assertKinds = 0, s_assertTotal = 0, s_assertNet = 0;
static void note_asserts(void)
{
    static int last = 0;
    int now = b3x_assert_count();
    if (now == last) return;
    /* One kind is not a fault of the binding: Box3D checking, inside a step,
     * that a body's velocity is still a number. A legal scene can fail that
     * (the smoke test's test_net builds one), the shim's net removes the
     * body when the step returns, and the audit below proves it did. They
     * are counted apart and do not fail the run. */
    if (strstr(b3x_assert_text(), "b3IsValidVec3( v )") || strstr(b3x_assert_text(), "b3IsValidVec3( w )")) {
        s_assertNet += now - last;
        last = now;
        return;
    }
    s_assertTotal += now - last;
    last = now;
    char line[200];
    snprintf(line, sizeof(line), "%s after %s", b3x_assert_text(), s_current);
    for (int i = 0; i < s_assertKinds; i++) if (strcmp(s_assertSeen[i], line) == 0) return;
    if (s_assertKinds < ASSERT_KINDS) {
        strcpy(s_assertSeen[s_assertKinds++], line);
        printf("ASSERT %s\n", line);
    }
}

/* Every body the pools know, asked whether it is still made of numbers.
 * Run every few hundred calls always, and after EVERY call with
 * FUZZ_AUDIT=1, which turns "a world went bad somewhere" into "this call
 * did it". */
static int s_audit = 0;
static int audit(void)
{
    const char *was = s_current;
    int bad = 0;
    double v[3];
    for (int i = 0; i < s_bodies.count && !bad; i++) {
        int b = s_bodies.items[i];
        if (!b3x_body_is_valid(b)) continue;
        const char *texts[3] = { b3x_body_transform(b), NULL, NULL };
        if (strstr(texts[0], "nan") || strstr(texts[0], "inf")) bad = b;
        v[0] = b3x_body_speed(b); v[1] = b3x_body_mass(b); v[2] = b3x_body_x(b);
        if (!isfinite(v[0]) || !isfinite(v[1]) || !isfinite(v[2])) bad = b;
        texts[1] = b3x_body_angular_velocity(b);
        if (strstr(texts[1], "nan") || strstr(texts[1], "inf")) bad = b;
    }
    if (bad) {
        /* the values go in the note: which number went is half the diagnosis */
        char note[320];
        snprintf(note, sizeof(note), "body %d is no longer made of numbers (speed %g, mass %g, awake %d, type %d, transform %.90s",
                 bad, b3x_body_speed(bad), b3x_body_mass(bad), b3x_body_is_awake(bad), b3x_body_type(bad), b3x_body_transform(bad));
        snprintf(note + strlen(note), sizeof(note) - strlen(note), ", spin %.60s)", b3x_body_angular_velocity(bad));
        s_current = was;
        finding(note, NULL);
    }
    s_current = was;
    return bad;
}

static int run(uint64_t seed, int calls)
{
    int before = s_findings;
    s_rng = seed * 0x9E3779B97F4A7C15ull + 1;
    s_worlds.count = s_bodies.count = s_shapes.count = s_joints.count = 0;
    int n = (int)(sizeof(k_fuzz) / sizeof(k_fuzz[0]));
    for (int i = 0; i < calls; i++) {
        /* A fresh scene now and then: the random calls destroy worlds, and a
         * run over nothing but dead handles tests one path forever. */
        if (i % 4000 == 0) seed_scene();
        const FuzzCall *c = &k_fuzz[below(n)];
        s_current = c->name;
        c->call();
        note_asserts();
        if ((s_audit || i % 500 == 499) && audit()) break;   /* a poisoned world: nothing after it means anything */
        /* step a world often: half of what is being tested is what a world
         * does AFTER the calls that were let through */
        if (i % 6 == 0 && s_worlds.count) {
            C("b3x_world_step", 3, (double)HW(), 1.0 / 60.0, (double)(1 + below(4)));
            note_asserts();
            if (s_audit && audit()) break;
        }
    }
    /* every world destroyed, by handle: twice over is harmless */
    s_current = "teardown";
    for (int pass = 0; pass < 2; pass++)
        for (int i = 0; i < s_worlds.count; i++) b3x_world_destroy(s_worlds.items[i]);
    /* The pool forgets handles once it is full, so a world may outlive it;
     * the 128-world cap must still let a new one be made after the sweep
     * unless one of those is holding a place. Not an assertion: a count. */
    printf("seed %llu: %d calls, %d findings\n", (unsigned long long)seed, calls, s_findings - before);
    return s_findings - before;
}

/* Make the calls a trace names, auditing after each one. */
static int replay(const char *path)
{
    FILE *f = fopen(path, "r");
    char line[1024];
    int made = 0;
    if (!f) { printf("cannot open %s\n", path); return 2; }
    s_audit = 1;
    while (fgets(line, sizeof(line), f)) {
        char *open = strchr(line, '(');
        double a[16] = { 0 };
        int n = 0;
        if (!open || strncmp(line, "b3x_", 4) != 0) continue;
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
        note_asserts();
        if (audit()) break;
    }
    fclose(f);
    printf("replayed %d calls: %d finding(s), %d Box3D assert(s)\n", made, s_findings, s_assertTotal);
    return s_findings || s_assertTotal ? 1 : 0;
}

int main(int argc, char **argv)
{
    int calls = 60000;
    s_trace = getenv("FUZZ_TRACE") != NULL;
    s_audit = getenv("FUZZ_AUDIT") != NULL;
    if (argc > 2 && strcmp(argv[1], "--replay") == 0) return replay(argv[2]);
    if (argc > 2) calls = atoi(argv[2]);
    if (argc > 1) {
        run((uint64_t)strtoull(argv[1], NULL, 10), calls);
    } else {
        for (uint64_t seed = 1; seed <= 3; seed++) run(seed, calls);
    }
    printf("box3dxt fuzz test: %d finding(s); %d Box3D assert(s) of %d kind(s)%s; the net removed %d unstable bodies"
           " (%d in-step asserts answered by it)\n", s_findings, s_assertTotal, s_assertKinds,
           s_assertTotal ? "" : " (0 is also what a build without asserts prints)", b3x_unstable_count(), s_assertNet);
    return s_findings || s_assertTotal ? 1 : 0;
}
