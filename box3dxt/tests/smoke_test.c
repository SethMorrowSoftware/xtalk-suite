/*
 * smoke_test.c - the runtime test of the box3dxt shim.
 *
 * Links against the box3dxt library (or, for the web, the archive) and drives
 * the real Box3D engine through the same C entry points the LCB binding
 * calls. It proves what a compile cannot: that the engine simulates (gravity,
 * resting contact, every shape kind, every joint kind), that queries and
 * events report what happened, and that the guards make stale handles and
 * bad arguments harmless. Run under ASan/UBSan in CI (native-box3dxt.yml).
 *
 * EVERY export of src/box3d_shim.c is entered here: tools/check-smoke-coverage.py
 * holds the declaration block below to the shim's signatures and refuses an
 * export this file never calls.
 *
 * Enable with -DBOX3DXT_BUILD_TESTS=ON, then run `ctest` (or the binary).
 */
#include <locale.h>
#include <math.h>
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

/* Parse "a,b,c" into out[]; returns how many numbers it found. The parse is
 * by hand (digits and one '.'), so it reads the shim's text the same in any
 * locale - which is the property under test in test_locale(). */
static int parse(const char *text, double *out, int cap)
{
    int n = 0;
    const char *p = text;
    if (!p || !*p) return 0;
    while (*p && n < cap) {
        char *end = NULL;
        char buf[64];
        int k = 0;
        while (*p && *p != ',' && *p != '\n' && k < 63) buf[k++] = *p++;
        buf[k] = 0;
        /* strtod honours the locale; the shim always writes '.', so parse
         * the mantissa by hand to stay independent of it. */
        {
            double sign = 1.0, value = 0.0, scale = 1.0;
            int exp10 = 0, i = 0, seenDot = 0;
            if (buf[i] == '-') { sign = -1.0; i++; }
            for (; buf[i]; i++) {
                if (buf[i] >= '0' && buf[i] <= '9') {
                    value = value * 10.0 + (buf[i] - '0');
                    if (seenDot) scale *= 10.0;
                } else if (buf[i] == '.') {
                    seenDot = 1;
                } else if (buf[i] == 'e' || buf[i] == 'E') {
                    exp10 = (int)strtol(buf + i + 1, &end, 10);
                    break;
                } else {
                    return -1;          /* a ',' decimal point would land here */
                }
            }
            out[n++] = sign * (value / scale) * pow(10.0, exp10);
        }
        if (*p == ',' || *p == '\n') p++;
    }
    return n;
}

static void step(int w, int n)
{
    for (int i = 0; i < n; i++) b3x_world_step(w, 1.0 / 60.0, 4);
}

/* A world with a 40 x 1 x 40 static floor whose top is at y = 0. */
static int make_world(int *ground)
{
    int w = b3x_world_create(0, -10, 0, 1);
    int g = b3x_body_create(w, 0, 0, -0.5, 0);
    b3x_shape_add_box(g, 20, 0.5, 20, 0, 0.6, 0);
    if (ground) *ground = g;
    return w;
}

/* ------------------------------------------------------------------ */
static void test_library(void)
{
    double v[4];
    CHECK(b3x_abi_version() == 1, "abi %d", b3x_abi_version());
    CHECK(strncmp(b3x_library_version(), "box3dxt ABI 1; Box3D ", 21) == 0, "version '%s'", b3x_library_version());
    CHECK(b3x_has_avx2() == 0 || b3x_has_avx2() == 1, "has_avx2");
    CHECK(b3x_world_create(NAN, 0, 0, 1) == 0, "NaN gravity must refuse");
    CHECK(strlen(b3x_last_error()) > 0, "a refusal leaves an error text");
    int w = b3x_world_create(0, -10, 0, 1);
    CHECK(w > 0, "world");
    CHECK(strlen(b3x_last_error()) == 0, "a success clears the error: '%s'", b3x_last_error());
    CHECK(b3x_world_is_valid(w) == 1, "valid");
    CHECK(parse(b3x_world_gravity(w), v, 4) == 3 && near(v[1], -10, 1e-6), "gravity '%s'", b3x_world_gravity(w));
    b3x_world_set_gravity(w, 1, 2, 3);
    CHECK(parse(b3x_world_gravity(w), v, 4) == 3 && near(v[0], 1, 1e-6) && near(v[2], 3, 1e-6), "set gravity");
    b3x_world_set_gravity(w, INFINITY, 0, 0);
    CHECK(parse(b3x_world_gravity(w), v, 4) == 3 && near(v[0], 1, 1e-6), "infinite gravity is refused");

    b3x_world_enable_sleeping(w, 0);
    CHECK(b3x_world_is_sleeping_enabled(w) == 0, "sleep off");
    b3x_world_enable_sleeping(w, 1);
    CHECK(b3x_world_is_sleeping_enabled(w) == 1, "sleep on");
    b3x_world_enable_continuous(w, 0);
    CHECK(b3x_world_is_continuous_enabled(w) == 0, "continuous off");
    b3x_world_enable_continuous(w, 1);
    CHECK(b3x_world_is_continuous_enabled(w) == 1, "continuous on");
    b3x_world_set_restitution_threshold(w, 2.5);
    CHECK(near(b3x_world_restitution_threshold(w), 2.5, 1e-6), "restitution threshold");
    b3x_world_set_hit_event_threshold(w, 0.75);
    CHECK(near(b3x_world_hit_event_threshold(w), 0.75, 1e-6), "hit threshold");
    b3x_world_set_max_linear_speed(w, 123.0);
    CHECK(near(b3x_world_max_linear_speed(w), 123.0, 1e-3), "max speed");
    b3x_world_set_max_linear_speed(w, -1.0);
    CHECK(near(b3x_world_max_linear_speed(w), 123.0, 1e-3), "a negative max speed is refused");
    b3x_world_set_contact_tuning(w, 30, 10, 3);
    b3x_world_set_worker_count(w, 2);
    CHECK(b3x_world_worker_count(w) >= 1, "worker count %d", b3x_world_worker_count(w));
    b3x_world_set_worker_count(w, 1);
    CHECK(b3x_world_worker_count(w) == 1, "one worker");
    CHECK(b3x_world_body_count(w) == 0 && b3x_world_shape_count(w) == 0 && b3x_world_joint_count(w) == 0, "empty counts");
    b3x_world_step(w, 1.0 / 60.0, 4);
    CHECK(b3x_world_step_ms(w) >= 0.0, "step ms");
    CHECK(b3x_world_contact_count(w) == 0 && b3x_world_awake_body_count(w) == 0, "nothing in it");
    b3x_world_destroy(w);
    CHECK(b3x_world_is_valid(w) == 0, "destroyed");
    b3x_world_destroy(w);                 /* twice is harmless */
    b3x_world_step(w, 1.0 / 60.0, 4);     /* on a dead world: no-op */
    CHECK(b3x_world_gravity(w)[0] == 0, "a dead world answers empty");
    CHECK(b3x_world_worker_count(w) == 0, "a dead world has no workers");
    CHECK(b3x_world_bounds(w)[0] == 0, "a dead world has no bounds");
}

/* ------------------------------------------------------------------ */
static void test_falling_and_resting(void)
{
    double v[12];
    int ground;
    int w = make_world(&ground);
    int ball = b3x_body_create(w, 2, 0, 5, 0);
    int shape = b3x_shape_add_sphere(ball, 0, 0, 0, 0.5, 1.0, 0.6, 0.0);
    CHECK(ball > 0 && shape > 0, "ball %d shape %d", ball, shape);
    CHECK(b3x_body_type(ball) == 2 && b3x_body_type(ground) == 0, "types");
    CHECK(b3x_body_world(ball) == w, "body's world");
    CHECK(near(b3x_body_mass(ball), 4.0 / 3.0 * 3.14159265 * 0.125, 1e-3), "sphere mass %g", b3x_body_mass(ball));
    CHECK(near(b3x_body_y(ball), 5.0, 1e-6) && near(b3x_body_x(ball), 0, 1e-6) && near(b3x_body_z(ball), 0, 1e-6), "start");

    step(w, 30);
    double yFalling = b3x_body_y(ball);
    CHECK(yFalling < 5.0 && yFalling > 0.5, "falling: y %g", yFalling);
    CHECK(parse(b3x_body_velocity(ball), v, 12) == 3 && v[1] < -1.0, "falling velocity '%s'", b3x_body_velocity(ball));
    CHECK(b3x_body_speed(ball) > 1.0, "speed");
    CHECK(b3x_body_is_awake(ball) == 1, "awake while falling");
    CHECK(b3x_world_awake_body_count(w) >= 1, "awake count");

    step(w, 400);
    CHECK(near(b3x_body_y(ball), 0.5, 0.03), "resting on the floor: y %g", b3x_body_y(ball));
    CHECK(b3x_body_speed(ball) < 0.05, "at rest: speed %g", b3x_body_speed(ball));
    CHECK(b3x_body_is_awake(ball) == 0, "asleep at rest");
    CHECK(parse(b3x_body_position(ball), v, 12) == 3 && near(v[1], 0.5, 0.03), "position text '%s'", b3x_body_position(ball));
    CHECK(parse(b3x_body_rotation(ball), v, 12) == 4, "rotation text");
    CHECK(near(v[0] * v[0] + v[1] * v[1] + v[2] * v[2] + v[3] * v[3], 1.0, 1e-4), "unit quaternion");
    CHECK(parse(b3x_body_transform(ball), v, 12) == 7, "transform text");
    CHECK(parse(b3x_body_matrix(ball), v, 12) == 12 && near(v[10], 0.5, 0.03), "matrix text '%s'", b3x_body_matrix(ball));
    CHECK(b3x_world_body_count(w) == 2 && b3x_world_shape_count(w) == 2, "counts %d %d", b3x_world_body_count(w), b3x_world_shape_count(w));
    CHECK(parse(b3x_world_bounds(w), v, 12) == 6 && v[0] <= -19.9 && v[3] >= 19.9, "world bounds '%s'", b3x_world_bounds(w));
    CHECK(parse(b3x_body_aabb(ball), v, 12) == 6 && v[4] > v[1], "body aabb");

    /* touching list: the ball touches the ground and nothing else */
    b3x_body_set_awake(ball, 1);
    step(w, 2);
    CHECK(b3x_body_list_touching(ball) == 1 && b3x_list_item(1) == ground, "touching %d -> %d", b3x_list_count(), b3x_list_item(1));
    CHECK(b3x_list_item(0) == 0 && b3x_list_item(2) == 0, "list index out of range is 0");

    b3x_world_destroy(w);
}

/* ------------------------------------------------------------------ */
static void test_body_api(void)
{
    double v[12];
    int w = b3x_world_create(0, 0, 0, 1);          /* no gravity: clean numbers */
    int b = b3x_body_create(w, 2, 1, 2, 3);
    b3x_shape_add_box(b, 0.5, 0.5, 0.5, 1.0, 0.5, 0.0);
    CHECK(near(b3x_body_mass(b), 1.0, 1e-4), "unit cube mass %g", b3x_body_mass(b));
    CHECK(b3x_body_is_valid(b) == 1, "valid");

    /* bad creates */
    CHECK(b3x_body_create(w, 7, 0, 0, 0) == 0, "bad type refused");
    CHECK(b3x_body_create(w, 2, NAN, 0, 0) == 0, "NaN position refused");
    CHECK(b3x_body_create(0, 2, 0, 0, 0) == 0, "no world refused");
    CHECK(b3x_body_create_rotated(w, 2, 0, 0, 0, 0, 0, 0, 0) == 0, "zero quaternion refused");

    /* transform set/get; a non-unit quaternion is normalized, not refused */
    b3x_body_set_transform(b, 4, 5, 6, 0, 0, 2, 2);
    CHECK(parse(b3x_body_transform(b), v, 12) == 7 && near(v[0], 4, 1e-5) && near(v[2], 6, 1e-5), "set transform");
    CHECK(near(v[5], 0.70710678, 1e-4) && near(v[6], 0.70710678, 1e-4), "quaternion normalized: %g %g", v[5], v[6]);
    b3x_body_set_position(b, 1, 1, 1);
    CHECK(parse(b3x_body_transform(b), v, 12) == 7 && near(v[0], 1, 1e-5) && near(v[5], 0.70710678, 1e-4), "set position keeps rotation");
    b3x_body_set_rotation(b, 0, 0, 0, 1);
    CHECK(parse(b3x_body_transform(b), v, 12) == 7 && near(v[0], 1, 1e-5) && near(v[6], 1, 1e-5), "set rotation keeps position");
    b3x_body_set_transform(b, NAN, 0, 0, 0, 0, 0, 1);
    CHECK(near(b3x_body_x(b), 1, 1e-5), "NaN transform refused");

    /* a quarter turn about z: local x becomes world y */
    b3x_body_set_rotation(b, 0, 0, 0.70710678, 0.70710678);
    CHECK(parse(b3x_body_world_vector(b, 1, 0, 0), v, 12) == 3 && near(v[0], 0, 1e-4) && near(v[1], 1, 1e-4), "world vector '%s'", b3x_body_world_vector(b, 1, 0, 0));
    CHECK(parse(b3x_body_local_vector(b, 0, 1, 0), v, 12) == 3 && near(v[0], 1, 1e-4), "local vector");
    CHECK(parse(b3x_body_world_point(b, 1, 0, 0), v, 12) == 3 && near(v[0], 1, 1e-4) && near(v[1], 2, 1e-4), "world point");
    CHECK(parse(b3x_body_local_point(b, 1, 2, 1), v, 12) == 3 && near(v[0], 1, 1e-4) && near(v[1], 0, 1e-4), "local point");
    CHECK(parse(b3x_body_matrix(b), v, 12) == 12 && near(v[1], 1, 1e-4) && near(v[3], -1, 1e-4) && near(v[8], 1, 1e-4), "matrix columns '%s'", b3x_body_matrix(b));
    CHECK(parse(b3x_body_local_center(b), v, 12) == 3 && near(v[0], 0, 1e-5), "local centre");
    CHECK(parse(b3x_body_world_center(b), v, 12) == 3 && near(v[0], 1, 1e-5), "world centre");
    b3x_body_set_rotation(b, 0, 0, 0, 1);

    /* velocity, impulses, forces */
    b3x_body_set_velocity(b, 1, 2, 3);
    CHECK(parse(b3x_body_velocity(b), v, 12) == 3 && near(v[0], 1, 1e-5) && near(v[2], 3, 1e-5), "set velocity");
    b3x_body_set_angular_velocity(b, 0, 0, 2);
    CHECK(parse(b3x_body_angular_velocity(b), v, 12) == 3 && near(v[2], 2, 1e-5), "set angular velocity");
    CHECK(parse(b3x_body_point_velocity(b, 2, 1, 1), v, 12) == 3 && near(v[1], 2 + 2, 1e-4), "point velocity '%s'", b3x_body_point_velocity(b, 2, 1, 1));
    b3x_body_set_velocity(b, 0, 0, 0);
    b3x_body_set_angular_velocity(b, 0, 0, 0);
    b3x_body_apply_impulse_to_center(b, 3, 0, 0, 1);
    CHECK(parse(b3x_body_velocity(b), v, 12) == 3 && near(v[0], 3, 1e-4), "impulse / mass = velocity: %g", v[0]);
    b3x_body_set_velocity(b, 0, 0, 0);
    b3x_body_apply_impulse(b, 0, 1, 0, 1.5, 1, 1, 1);      /* off-centre: spins too */
    CHECK(parse(b3x_body_velocity(b), v, 12) == 3 && near(v[1], 1, 1e-4), "off-centre impulse moves");
    CHECK(parse(b3x_body_angular_velocity(b), v, 12) == 3 && fabs(v[2]) > 0.1, "off-centre impulse spins");
    b3x_body_set_velocity(b, 0, 0, 0);
    b3x_body_set_angular_velocity(b, 0, 0, 0);
    b3x_body_apply_angular_impulse(b, 0, 0, 1, 1);
    CHECK(parse(b3x_body_angular_velocity(b), v, 12) == 3 && v[2] > 0.1, "angular impulse");
    b3x_body_set_angular_velocity(b, 0, 0, 0);
    b3x_body_apply_force_to_center(b, 60, 0, 0, 1);
    b3x_world_step(w, 1.0 / 60.0, 4);
    CHECK(parse(b3x_body_velocity(b), v, 12) == 3 && near(v[0], 1.0, 0.02), "force * dt / mass: %g", v[0]);
    b3x_body_set_velocity(b, 0, 0, 0);
    b3x_body_apply_force(b, 0, 60, 0, b3x_body_x(b), b3x_body_y(b), b3x_body_z(b), 1);
    b3x_body_apply_torque(b, 0, 0, 10, 1);
    b3x_world_step(w, 1.0 / 60.0, 4);
    CHECK(parse(b3x_body_velocity(b), v, 12) == 3 && near(v[1], 1.0, 0.02), "force at a point");
    CHECK(parse(b3x_body_angular_velocity(b), v, 12) == 3 && v[2] > 0.1, "torque");
    b3x_body_apply_impulse_to_center(b, NAN, 0, 0, 1);
    CHECK(parse(b3x_body_velocity(b), v, 12) == 3 && near(v[1], 1.0, 0.02), "NaN impulse refused");

    /* scalar settings */
    b3x_body_set_linear_damping(b, 0.25);
    CHECK(near(b3x_body_linear_damping(b), 0.25, 1e-6), "linear damping");
    b3x_body_set_angular_damping(b, 0.5);
    CHECK(near(b3x_body_angular_damping(b), 0.5, 1e-6), "angular damping");
    b3x_body_set_linear_damping(b, -1);
    CHECK(near(b3x_body_linear_damping(b), 0.25, 1e-6), "negative damping refused");
    b3x_body_set_gravity_scale(b, -2.0);
    CHECK(near(b3x_body_gravity_scale(b), -2.0, 1e-6), "gravity scale");
    b3x_body_set_sleep_threshold(b, 0.125);
    CHECK(near(b3x_body_sleep_threshold(b), 0.125, 1e-6), "sleep threshold");
    b3x_body_enable_sleep(b, 0);
    CHECK(b3x_body_is_sleep_enabled(b) == 0, "sleep disabled");
    b3x_body_enable_sleep(b, 1);
    CHECK(b3x_body_is_sleep_enabled(b) == 1, "sleep enabled");
    b3x_body_set_bullet(b, 1);
    CHECK(b3x_body_is_bullet(b) == 1, "bullet");
    b3x_body_set_bullet(b, 0);
    CHECK(b3x_body_is_bullet(b) == 0, "not bullet");
    b3x_body_set_awake(b, 0);
    CHECK(b3x_body_is_awake(b) == 0, "put to sleep");
    b3x_body_set_awake(b, 1);
    CHECK(b3x_body_is_awake(b) == 1, "woken");
    b3x_body_disable(b);
    CHECK(b3x_body_is_enabled(b) == 0, "disabled");
    b3x_body_enable(b);
    CHECK(b3x_body_is_enabled(b) == 1, "enabled");
    b3x_body_enable_hit_events(b, 1);
    b3x_body_set_type(b, 1);
    CHECK(b3x_body_type(b) == 1, "now kinematic");
    b3x_body_set_type(b, 9);
    CHECK(b3x_body_type(b) == 1, "bad type refused");
    b3x_body_set_type(b, 2);
    b3x_body_apply_mass_from_shapes(b);
    CHECK(near(b3x_body_mass(b), 1.0, 1e-4), "mass from shapes");

    /* motion locks: with y locked, gravity cannot move the body in y */
    b3x_world_set_gravity(w, 0, -10, 0);
    b3x_body_set_gravity_scale(b, 1.0);
    b3x_body_set_linear_damping(b, 0);
    b3x_body_set_velocity(b, 0, 0, 0);
    b3x_body_set_angular_velocity(b, 0, 0, 0);
    b3x_body_set_motion_locks(b, 0, 1, 0, 0, 0, 0);
    CHECK(strcmp(b3x_body_motion_locks(b), "0,1,0,0,0,0") == 0, "locks text '%s'", b3x_body_motion_locks(b));
    double y0 = b3x_body_y(b);
    step(w, 30);
    CHECK(near(b3x_body_y(b), y0, 1e-3), "y locked: %g -> %g", y0, b3x_body_y(b));
    b3x_body_set_motion_locks(b, 0, 0, 0, 0, 0, 0);
    step(w, 30);
    CHECK(b3x_body_y(b) < y0 - 0.5, "unlocked: falls");
    b3x_world_set_gravity(w, 0, 0, 0);

    /* a kinematic body driven to a target */
    int k = b3x_body_create(w, 1, 0, 10, 0);
    b3x_shape_add_box(k, 0.5, 0.5, 0.5, 1.0, 0.5, 0.0);
    b3x_body_set_target_transform(k, 1, 10, 0, 0, 0, 0, 1, 1.0 / 60.0, 1);
    b3x_world_step(w, 1.0 / 60.0, 4);
    CHECK(near(b3x_body_x(k), 1.0, 0.01), "kinematic target reached: %g", b3x_body_x(k));
    b3x_body_set_target_transform(k, 2, 10, 0, 0, 0, 0, 1, 0.0, 1);     /* dt 0: refused */
    b3x_body_set_velocity(k, 0, 0, 0);

    /* shapes and joints lists */
    int s2 = b3x_shape_add_sphere(b, 0, 1, 0, 0.25, 1.0, 0.5, 0.0);
    CHECK(b3x_body_shape_count(b) == 2, "shape count");
    CHECK(b3x_body_list_shapes(b) == 2 && (b3x_list_item(1) == s2 || b3x_list_item(2) == s2), "shape list");
    int j = b3x_joint_weld(w, b, k, 0, 5, 0, 0);
    CHECK(b3x_body_joint_count(b) == 1, "joint count");
    CHECK(b3x_body_list_joints(b) == 1 && b3x_list_item(1) == j, "joint list");
    CHECK(b3x_body_list_shapes(0) == 0 && b3x_list_count() == 0, "a dead body lists nothing");

    /* destroying the body takes its shapes and joints with it */
    b3x_body_destroy(b);
    CHECK(b3x_body_is_valid(b) == 0, "body gone");
    CHECK(b3x_shape_is_valid(s2) == 0, "its shape handle is dead");
    CHECK(b3x_joint_is_valid(j) == 0, "its joint handle is dead");
    b3x_body_destroy(b);                                  /* twice is harmless */
    b3x_body_set_velocity(b, 1, 1, 1);
    CHECK(b3x_body_position(b)[0] == 0 && b3x_body_mass(b) == 0.0, "a dead body answers empty and 0");
    CHECK(b3x_body_matrix(b)[0] == 0 && b3x_body_motion_locks(b)[0] == 0, "dead body texts are empty");
    CHECK(b3x_body_world(b) == 0 && b3x_body_type(b) == 0, "dead body world / type");
    int b2 = b3x_body_create(w, 2, 0, 0, 0);
    CHECK(b2 != b, "a recycled slot gives a NEW handle (%d vs %d)", b2, b);
    CHECK(b3x_body_is_valid(b) == 0, "the old handle stays dead after the slot is reused");

    b3x_world_destroy(w);
    CHECK(b3x_body_is_valid(b2) == 0 && b3x_body_is_valid(k) == 0, "a world takes its bodies with it");
}

/* ------------------------------------------------------------------ */
/* Drop a small sphere on a body at (x, z) and return where it rests. */
static double rest_height_on(int w, double x, double z, double from)
{
    int ball = b3x_body_create(w, 2, x, from, z);
    b3x_shape_add_sphere(ball, 0, 0, 0, 0.25, 1.0, 0.8, 0.0);
    b3x_body_set_linear_damping(ball, 0.5);
    b3x_body_set_angular_damping(ball, 2.0);
    step(w, 420);
    double y = b3x_body_y(ball);
    b3x_body_destroy(ball);
    return y;
}

static void test_shapes(void)
{
    double v[12];
    int w = b3x_world_create(0, -10, 0, 1);
    int b = b3x_body_create(w, 2, 0, 50, 0);
    b3x_body_set_gravity_scale(b, 0);

    b3x_shape_options_reset();
    int sphere = b3x_shape_add_sphere(b, 0, 0, 0, 0.5, 2.0, 0.3, 0.1);
    int capsule = b3x_shape_add_capsule(b, 0, -0.5, 0, 0, 0.5, 0, 0.25, 1.0, 0.3, 0.1);
    int box = b3x_shape_add_box(b, 0.5, 0.25, 0.125, 1.0, 0.3, 0.1);
    int boxAt = b3x_shape_add_box_at(b, 0.5, 0.5, 0.5, 2, 0, 0, 0, 0, 0.3826834, 0.9238795, 1.0, 0.3, 0.1);
    int cyl = b3x_shape_add_cylinder(b, 1.0, 0.5, 12, 1.0, 0.3, 0.1);
    int cone = b3x_shape_add_cone(b, 1.0, 0.5, 0.05, 12, 1.0, 0.3, 0.1);
    CHECK(sphere && capsule && box && boxAt && cyl && cone, "primitives %d %d %d %d %d %d: %s",
          sphere, capsule, box, boxAt, cyl, cone, b3x_last_error());
    CHECK(b3x_shape_type(sphere) == 5 && b3x_shape_type(capsule) == 0 && b3x_shape_type(box) == 3, "shape types");
    CHECK(b3x_shape_type(cyl) == 3 && b3x_shape_type(cone) == 3, "cylinder and cone are hulls");
    CHECK(b3x_shape_body(sphere) == b, "shape's body");
    CHECK(b3x_shape_is_sensor(sphere) == 0, "not a sensor");

    /* the cylinder is centred: its box runs from -0.5 to 0.5 in y */
    b3x_body_set_transform(b, 0, 50, 0, 0, 0, 0, 1);
    CHECK(parse(b3x_shape_aabb(cyl), v, 12) == 6 && near(v[1], 49.5, 0.06) && near(v[4], 50.5, 0.06), "cylinder centred: '%s'", b3x_shape_aabb(cyl));
    CHECK(parse(b3x_shape_aabb(boxAt), v, 12) == 6 && v[0] > 1.0, "offset box sits at x = 2: '%s'", b3x_shape_aabb(boxAt));
    CHECK(parse(b3x_shape_closest_point(sphere, 10, 50, 0), v, 12) == 3 && near(v[0], 0.5, 0.01), "closest point on the sphere: '%s'", b3x_shape_closest_point(sphere, 10, 50, 0));

    /* a hull from points: a tetrahedron */
    b3x_geometry_begin();
    CHECK(b3x_geometry_add_point(0, 0, 0) == 1, "point 1");
    b3x_geometry_add_point(1, 0, 0);
    b3x_geometry_add_point(0, 1, 0);
    CHECK(b3x_shape_add_hull(b, 1, 0.3, 0) == 0, "3 points are not a hull");
    CHECK(strlen(b3x_last_error()) > 0, "and say why");
    b3x_geometry_add_point(0, 0, 1);
    CHECK(b3x_geometry_point_count() == 4, "4 points");
    CHECK(b3x_geometry_add_point(NAN, 0, 0) == 0 && b3x_geometry_point_count() == 4, "NaN point refused");
    int hull = b3x_shape_add_hull(b, 1.0, 0.3, 0.0);
    CHECK(hull > 0 && b3x_shape_type(hull) == 3, "hull %d: %s", hull, b3x_last_error());
    b3x_geometry_begin();
    for (int i = 0; i < 4; i++) b3x_geometry_add_point(i, 0, 0);
    CHECK(b3x_shape_add_hull(b, 1, 0.3, 0) == 0, "collinear points are not a hull");

    /* material and flags */
    CHECK(near(b3x_shape_density(sphere), 2.0, 1e-6) && near(b3x_shape_friction(sphere), 0.3, 1e-6) && near(b3x_shape_restitution(sphere), 0.1, 1e-6), "material read back");
    double m0 = b3x_body_mass(b);
    b3x_shape_set_density(sphere, 4.0, 1);
    CHECK(near(b3x_shape_density(sphere), 4.0, 1e-6) && b3x_body_mass(b) > m0, "density raises the mass");
    b3x_shape_set_friction(sphere, 0.9);
    CHECK(near(b3x_shape_friction(sphere), 0.9, 1e-6), "friction");
    b3x_shape_set_friction(sphere, -1);
    CHECK(near(b3x_shape_friction(sphere), 0.9, 1e-6), "negative friction refused");
    b3x_shape_set_restitution(sphere, 0.5);
    CHECK(near(b3x_shape_restitution(sphere), 0.5, 1e-6), "restitution");
    b3x_shape_set_rolling_resistance(sphere, 0.2);
    CHECK(near(b3x_shape_rolling_resistance(sphere), 0.2, 1e-6), "rolling resistance");
    b3x_shape_set_filter(sphere, 2, 5, -3);
    CHECK(strcmp(b3x_shape_filter(sphere), "2,5,-3") == 0, "filter text '%s'", b3x_shape_filter(sphere));
    b3x_shape_set_filter(sphere, -1, 5, 0);
    CHECK(strcmp(b3x_shape_filter(sphere), "2,5,-3") == 0, "negative filter bits refused");
    b3x_shape_set_filter(sphere, 1.5, 5, 0);
    CHECK(strcmp(b3x_shape_filter(sphere), "2,5,-3") == 0, "fractional filter bits refused");
    b3x_shape_enable_contact_events(sphere, 0);
    CHECK(b3x_shape_are_contact_events_enabled(sphere) == 0, "contact events off");
    b3x_shape_enable_contact_events(sphere, 1);
    CHECK(b3x_shape_are_contact_events_enabled(sphere) == 1, "contact events on");
    b3x_shape_enable_hit_events(sphere, 1);
    CHECK(b3x_shape_are_hit_events_enabled(sphere) == 1, "hit events on");
    b3x_shape_enable_sensor_events(sphere, 0);
    CHECK(b3x_shape_are_sensor_events_enabled(sphere) == 0, "sensor events off");

    /* options: sticky until reset */
    b3x_shape_options_set_sensor(1);
    b3x_shape_options_set_events(0, 1, 0);
    b3x_shape_options_set_filter(8, 16, 2);
    b3x_shape_options_set_rolling_resistance(0.3);
    int opt = b3x_shape_add_sphere(b, 5, 0, 0, 0.5, 1, 0.3, 0);
    CHECK(b3x_shape_is_sensor(opt) == 1, "option: sensor");
    CHECK(b3x_shape_are_contact_events_enabled(opt) == 0 && b3x_shape_are_hit_events_enabled(opt) == 1 && b3x_shape_are_sensor_events_enabled(opt) == 0, "option: events");
    CHECK(strcmp(b3x_shape_filter(opt), "8,16,2") == 0, "option: filter '%s'", b3x_shape_filter(opt));
    CHECK(near(b3x_shape_rolling_resistance(opt), 0.3, 1e-6), "option: rolling resistance");
    b3x_shape_options_reset();
    int plain = b3x_shape_add_sphere(b, 6, 0, 0, 0.5, 1, 0.3, 0);
    /* Box3D's defaults: solid, and every event kind OFF until asked for */
    CHECK(b3x_shape_is_sensor(plain) == 0 && b3x_shape_are_contact_events_enabled(plain) == 0 && b3x_shape_are_hit_events_enabled(plain) == 0 && b3x_shape_are_sensor_events_enabled(plain) == 0, "reset: defaults again");
    CHECK(strcmp(b3x_shape_filter(plain), "8,16,2") != 0 && near(b3x_shape_rolling_resistance(plain), 0.0, 1e-9), "reset: filter and rolling resistance too");

    /* refusals */
    CHECK(b3x_shape_add_sphere(b, 0, 0, 0, 0, 1, 0.3, 0) == 0, "radius 0 refused");
    CHECK(b3x_shape_add_sphere(b, 0, 0, 0, 0.5, -1, 0.3, 0) == 0, "negative density refused");
    CHECK(b3x_shape_add_sphere(0, 0, 0, 0, 0.5, 1, 0.3, 0) == 0, "no body refused");
    CHECK(b3x_shape_add_box(b, 0, 1, 1, 1, 0.3, 0) == 0, "flat box refused");
    CHECK(b3x_shape_add_box_at(b, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 1, 0.3, 0) == 0, "box with a zero quaternion refused");
    CHECK(b3x_shape_add_capsule(b, 0, 0, 0, 0, 0, 0, 0.25, 1, 0.3, 0) == 0, "zero-length capsule refused");
    CHECK(b3x_shape_add_cylinder(b, 1, 0.5, 2, 1, 0.3, 0) == 0, "2-sided cylinder refused");
    CHECK(b3x_shape_add_cone(b, 1, 0, 0, 12, 1, 0.3, 0) == 0, "cone with no radius refused");
    CHECK(b3x_shape_add_cone(b, 1, 0.5, 0, 12, 1, 0.3, 0) == 0 && b3x_shape_add_cone(b, 1, 0, 0.5, 12, 1, 0.3, 0) == 0, "a cone with one radius 0 is refused (Box3D asserts on it)");
    CHECK(b3x_shape_add_cone(b, 1, 0.5, 0.2, 3, 1, 0.3, 0) == 0 && b3x_shape_add_cone(b, 1, 0.5, 0.2, 33, 1, 0.3, 0) == 0, "cone sides out of 4..32 refused");
    CHECK(b3x_shape_add_mesh(b, 0.5, 0) == 0, "mesh on a dynamic body refused");
    CHECK(b3x_shape_add_height_field(b, 2, 2, 1, 1, 1, 0.5, 0) == 0, "height field on a dynamic body refused");

    /* destroy one */
    int n = b3x_body_shape_count(b);
    b3x_shape_destroy(plain, 1);
    CHECK(b3x_shape_is_valid(plain) == 0 && b3x_body_shape_count(b) == n - 1, "shape destroyed");
    b3x_shape_destroy(plain, 1);
    b3x_shape_set_friction(plain, 0.1);
    CHECK(b3x_shape_friction(plain) == 0.0 && b3x_shape_type(plain) == -1 && b3x_shape_body(plain) == 0, "a dead shape answers 0");
    CHECK(b3x_shape_aabb(plain)[0] == 0 && b3x_shape_filter(plain)[0] == 0, "dead shape texts are empty");
    b3x_body_destroy(b);

    /* a mesh: a 10 x 10 slab at y = 2 made of two triangles, facing up */
    int ground = b3x_body_create(w, 0, 0, 0, 0);
    b3x_geometry_begin();
    b3x_geometry_add_point(-5, 2, -5);
    b3x_geometry_add_point(5, 2, -5);
    b3x_geometry_add_point(5, 2, 5);
    b3x_geometry_add_point(-5, 2, 5);
    CHECK(b3x_geometry_add_triangle(1, 9, 2) == 1, "a triangle is recorded");
    CHECK(b3x_shape_add_mesh(ground, 0.8, 0) == 0, "a triangle naming point 9 of 4 is refused: %s", b3x_last_error());
    CHECK(b3x_geometry_add_triangle(0, 1, 2) == 0, "point number 0 refused");
    b3x_geometry_begin();
    b3x_geometry_add_point(-5, 2, -5);
    b3x_geometry_add_point(5, 2, -5);
    b3x_geometry_add_point(5, 2, 5);
    b3x_geometry_add_point(-5, 2, 5);
    b3x_geometry_add_triangle(1, 3, 2);
    b3x_geometry_add_triangle(1, 4, 3);
    int mesh = b3x_shape_add_mesh(ground, 0.8, 0.0);
    CHECK(mesh > 0 && b3x_shape_type(mesh) == 4, "mesh %d: %s", mesh, b3x_last_error());
    double y = rest_height_on(w, 0.3, 0.2, 4.0);
    CHECK(near(y, 2.25, 0.05), "a ball rests on the mesh at y %g (want 2.25)", y);

    /* a height field: 5 x 5 points, 2 apart, a ramp rising along x. Box3D
     * places it from its own origin; the test reads where from the AABB. */
    int terrain = b3x_body_create(w, 0, 30, 0, 0);
    b3x_geometry_begin();
    for (int z = 0; z < 5; z++)
        for (int x = 0; x < 5; x++) b3x_geometry_add_height(0.5 * x);
    CHECK(b3x_shape_add_height_field(terrain, 5, 4, 2, 1, 2, 0.8, 0) == 0, "25 heights are not 5 x 4");
    int field = b3x_shape_add_height_field(terrain, 5, 5, 2, 1, 2, 0.8, 0.0);
    CHECK(field > 0 && b3x_shape_type(field) == 2, "height field %d: %s", field, b3x_last_error());
    CHECK(parse(b3x_shape_aabb(field), v, 12) == 6, "field aabb");
    double fx = 0.5 * (v[0] + v[3]), fz = 0.5 * (v[2] + v[5]);
    CHECK(near(v[3] - v[0], 8.0, 0.2) && near(v[5] - v[2], 8.0, 0.2) && near(v[4] - v[1], 2.0, 0.2), "field size '%s'", b3x_shape_aabb(field));
    b3x_cast_ray_closest(w, fx, v[4] + 5, fz, 0, -20, 0);
    CHECK(b3x_hit_count() == 1 && b3x_hit_shape(1) == field, "a ray finds the field");
    double hv[3];
    CHECK(parse(b3x_hit_point(1), hv, 3) == 3 && near(hv[1], 0.5 * (v[1] + v[4]), 0.1), "mid-ramp height %g", hv[1]);

    /* destroying the mesh shape, then the world, frees the owned geometry
     * (ASan's leak check is the assertion) */
    b3x_shape_destroy(mesh, 0);
    CHECK(b3x_shape_is_valid(mesh) == 0, "mesh shape gone");
    b3x_world_destroy(w);
    CHECK(b3x_shape_is_valid(field) == 0, "the world took the height field");
}

/* ------------------------------------------------------------------ */
static void test_queries(void)
{
    double v[6];
    int ground;
    int w = make_world(&ground);
    int a = b3x_body_create(w, 0, 0, 3, 0);
    int sa = b3x_shape_add_box(a, 1, 0.5, 1, 1, 0.5, 0);      /* y 2.5 .. 3.5 */
    int bb = b3x_body_create(w, 0, 0, 6, 0);
    int sb = b3x_shape_add_sphere(bb, 0, 0, 0, 0.5, 1, 0.5, 0); /* y 5.5 .. 6.5 */
    b3x_world_step(w, 1.0 / 60.0, 4);
    b3x_query_reset_filter();

    /* straight down the y axis: sphere, then box, then floor */
    CHECK(b3x_cast_ray(w, 0, 10, 0, 0, -20, 0) == 3, "three hits, got %d", b3x_hit_count());
    CHECK(b3x_hit_shape(1) == sb && b3x_hit_shape(2) == sa, "nearest first: %d %d", b3x_hit_shape(1), b3x_hit_shape(2));
    CHECK(b3x_hit_body(1) == bb && b3x_hit_body(2) == a && b3x_hit_body(3) == ground, "hit bodies");
    CHECK(near(b3x_hit_fraction(1), 3.5 / 20.0, 1e-3) && near(b3x_hit_fraction(2), 6.5 / 20.0, 1e-3) && near(b3x_hit_fraction(3), 0.5, 1e-3),
          "fractions %g %g %g", b3x_hit_fraction(1), b3x_hit_fraction(2), b3x_hit_fraction(3));
    CHECK(parse(b3x_hit_point(1), v, 6) == 3 && near(v[1], 6.5, 1e-3), "hit point '%s'", b3x_hit_point(1));
    CHECK(parse(b3x_hit_normal(2), v, 6) == 3 && near(v[1], 1.0, 1e-3), "hit normal '%s'", b3x_hit_normal(2));
    CHECK(b3x_hit_shape(0) == 0 && b3x_hit_shape(4) == 0 && b3x_hit_fraction(9) == 0.0 && b3x_hit_point(9)[0] == 0 && b3x_hit_normal(0)[0] == 0 && b3x_hit_body(7) == 0, "hit index out of range");

    CHECK(b3x_cast_ray_closest(w, 0, 10, 0, 0, -20, 0) == 1 && b3x_hit_shape(1) == sb, "closest is the sphere");
    CHECK(b3x_cast_ray_closest(w, 30, 10, 30, 0, 5, 0) == 0 && b3x_hit_count() == 0, "a ray into the sky hits nothing");
    CHECK(b3x_cast_ray(w, 0, 10, 0, 0, 0, 0) == 0, "a zero-length ray is refused");
    CHECK(b3x_cast_ray(w, NAN, 10, 0, 0, -20, 0) == 0, "a NaN ray is refused");
    CHECK(b3x_cast_ray(0, 0, 10, 0, 0, -20, 0) == 0, "no world, no hits");

    /* a fat sphere swept down beside the box still catches its edge */
    CHECK(b3x_cast_ray(w, 1.3, 10, 0, 0, -8, 0) == 0, "a thin ray at x = 1.3 misses the box");
    CHECK(b3x_cast_sphere(w, 1.3, 10, 0, 0.5, 0, -8, 0) >= 1 && b3x_hit_shape(1) == sa, "a swept sphere hits it (%d)", b3x_hit_count());
    CHECK(b3x_cast_sphere(w, 1.3, 10, 0, 0, 0, -6, 0) == 0, "radius 0 refused");

    /* overlaps */
    CHECK(b3x_overlap_aabb(w, -0.2, 2.6, -0.2, 0.2, 3.4, 0.2) == 1 && b3x_list_item(1) == sa, "aabb overlap finds the box (%d)", b3x_list_count());
    CHECK(b3x_overlap_aabb(w, -0.2, 2.6, -0.2, 0.2, 6.0, 0.2) == 2, "a taller aabb finds two");
    CHECK(b3x_overlap_aabb(w, 1, 1, 1, 0, 0, 0) == 0, "an inside-out aabb is refused");
    CHECK(b3x_overlap_sphere(w, 0, 6, 0, 0.25) == 1 && b3x_list_item(1) == sb, "sphere overlap finds the sphere");
    CHECK(b3x_overlap_sphere(w, 0, 4.5, 0, 0.25) == 0, "nothing between them");
    CHECK(b3x_overlap_sphere(w, 0, 4.5, 0, -1) == 0, "negative radius refused");

    /* the query filter: give the sphere category 4, then ask for 2 only */
    b3x_shape_set_filter(sb, 4, 65535, 0);
    b3x_shape_set_filter(sa, 2, 65535, 0);
    b3x_query_set_filter(1, 2);
    CHECK(b3x_cast_ray_closest(w, 0, 10, 0, 0, -20, 0) == 1 && b3x_hit_shape(1) == sa, "the filter skips the sphere");
    b3x_query_set_filter(-1, 2);          /* refused: the filter stays */
    CHECK(b3x_cast_ray_closest(w, 0, 10, 0, 0, -20, 0) == 1 && b3x_hit_shape(1) == sa, "a bad filter is refused");
    b3x_query_reset_filter();
    CHECK(b3x_cast_ray_closest(w, 0, 10, 0, 0, -20, 0) == 1 && b3x_hit_shape(1) == sb, "reset: the sphere again");

    b3x_world_destroy(w);
}

/* ------------------------------------------------------------------ */
static void test_events(void)
{
    double v[9];
    int ground;
    int w = make_world(&ground);
    b3x_world_set_hit_event_threshold(w, 1.0);
    b3x_shape_options_reset();
    b3x_shape_options_set_events(1, 1, 1);
    int ball = b3x_body_create(w, 2, 0, 3, 0);
    int ballShape = b3x_shape_add_sphere(ball, 0, 0, 0, 0.5, 1.0, 0.5, 0.0);
    b3x_shape_options_reset();
    b3x_shape_list_sensor_visitors(ballShape);      /* not a sensor: empty */
    CHECK(b3x_list_count() == 0, "a solid shape has no visitors");

    int begins = 0, hits = 0, moves = 0, sawSleep = 0;
    double hitSpeed = 0;
    int beginA = 0, beginB = 0;
    for (int i = 0; i < 240; i++) {
        b3x_world_step(w, 1.0 / 60.0, 4);
        b3x_world_update_contact_events(w);
        if (b3x_contact_begin_count() > 0 && !begins) {
            begins = b3x_contact_begin_count();
            beginA = b3x_contact_begin_shape_a(1);
            beginB = b3x_contact_begin_shape_b(1);
        }
        if (b3x_contact_hit_count() > 0 && !hits) {
            hits = b3x_contact_hit_count();
            hitSpeed = b3x_contact_hit_speed(1);
            CHECK(b3x_contact_hit_shape_a(1) == ballShape || b3x_contact_hit_shape_b(1) == ballShape, "the hit names the ball");
            CHECK(parse(b3x_contact_hit_point(1), v, 9) == 3 && near(v[1], 0.0, 0.1), "hit point on the floor '%s'", b3x_contact_hit_point(1));
            CHECK(parse(b3x_contact_hit_normal(1), v, 9) == 3 && near(fabs(v[1]), 1.0, 0.05), "hit normal is vertical");
        }
        int n = b3x_world_update_moves(w);
        if (n > 0) {
            moves += n;
            CHECK(b3x_move_count() == n && b3x_move_body(1) == ball, "the ball moved");
            CHECK(parse(b3x_move_transform(1), v, 9) == 7 && near(v[1], b3x_body_y(ball), 1e-4), "move transform matches the body");
            const char *all = b3x_moves_text();
            double row[9];
            CHECK(parse(all, row, 9) == 9 && (int)row[0] == ball && near(row[2], b3x_body_y(ball), 1e-4), "moves text '%s'", all);
            if (b3x_move_fell_asleep(1)) sawSleep = 1;
        }
    }
    CHECK(begins == 1, "one begin-touch event, got %d", begins);
    CHECK((beginA == ballShape || beginB == ballShape) && beginA != beginB && beginA && beginB, "begin names both shapes: %d %d", beginA, beginB);
    CHECK(hits == 1 && hitSpeed > 5.0, "a hit event at speed %g", hitSpeed);
    CHECK(moves > 30, "move events arrived (%d)", moves);
    CHECK(sawSleep == 1, "the last move says the ball fell asleep");
    CHECK(b3x_world_update_moves(w) == 0 && b3x_moves_text()[0] == 0, "a sleeping world moves nothing");
    CHECK(b3x_move_body(1) == 0 && b3x_move_transform(1)[0] == 0 && b3x_move_fell_asleep(1) == 0, "move index out of range");

    /* lift the ball: an end-touch event */
    b3x_body_set_transform(ball, 0, 5, 0, 0, 0, 0, 1);
    b3x_body_set_gravity_scale(ball, 0);
    b3x_body_set_awake(ball, 1);
    int ends = 0;
    for (int i = 0; i < 10 && !ends; i++) {
        b3x_world_step(w, 1.0 / 60.0, 4);
        b3x_world_update_contact_events(w);
        ends = b3x_contact_end_count();
        if (ends) CHECK(b3x_contact_end_shape_a(1) == ballShape || b3x_contact_end_shape_b(1) == ballShape, "end names the ball");
    }
    CHECK(ends == 1, "one end-touch event, got %d", ends);
    CHECK(b3x_contact_begin_shape_a(99) == 0 && b3x_contact_begin_shape_b(0) == 0 && b3x_contact_end_shape_a(99) == 0 && b3x_contact_end_shape_b(99) == 0, "event index out of range");
    CHECK(b3x_contact_hit_shape_a(99) == 0 && b3x_contact_hit_shape_b(99) == 0 && b3x_contact_hit_speed(99) == 0.0 && b3x_contact_hit_point(99)[0] == 0 && b3x_contact_hit_normal(99)[0] == 0, "hit index out of range");

    /* a sensor: a big ghost sphere the ball is dropped through */
    int zone = b3x_body_create(w, 0, 10, 3, 0);
    b3x_shape_options_set_sensor(1);
    b3x_shape_options_set_events(0, 0, 1);      /* Box3D: off by default, even on a sensor */
    int zoneShape = b3x_shape_add_sphere(zone, 0, 0, 0, 1.0, 0, 0, 0);
    b3x_shape_options_reset();
    CHECK(b3x_shape_is_sensor(zoneShape) == 1, "the zone is a sensor");
    b3x_body_set_transform(ball, 10, 6, 0, 0, 0, 0, 1);
    b3x_body_set_gravity_scale(ball, 1);
    b3x_body_set_awake(ball, 1);
    int sBegin = 0, sEnd = 0, visitorsInside = 0;
    for (int i = 0; i < 240; i++) {
        b3x_world_step(w, 1.0 / 60.0, 4);
        b3x_world_update_sensor_events(w);
        if (b3x_sensor_begin_count() > 0) {
            sBegin++;
            CHECK(b3x_sensor_begin_sensor(1) == zoneShape && b3x_sensor_begin_visitor(1) == ballShape, "sensor begin names zone and ball");
        }
        if (sBegin && !sEnd && !visitorsInside) {
            if (b3x_shape_list_sensor_visitors(zoneShape) == 1 && b3x_list_item(1) == ballShape) visitorsInside = 1;
        }
        if (b3x_sensor_end_count() > 0) {
            sEnd++;
            CHECK(b3x_sensor_end_sensor(1) == zoneShape && b3x_sensor_end_visitor(1) == ballShape, "sensor end names zone and ball");
        }
    }
    CHECK(sBegin == 1 && sEnd == 1, "one sensor begin and one end (%d, %d)", sBegin, sEnd);
    CHECK(visitorsInside == 1, "the visitor list saw the ball inside");
    CHECK(b3x_sensor_begin_sensor(9) == 0 && b3x_sensor_begin_visitor(9) == 0 && b3x_sensor_end_sensor(9) == 0 && b3x_sensor_end_visitor(9) == 0, "sensor index out of range");
    CHECK(b3x_world_update_contact_events(0) == 0 && b3x_world_update_sensor_events(0) == 0 && b3x_world_update_moves(0) == 0 && b3x_world_update_joint_events(0) == 0, "a dead world has no events");

    /* an explosion pushes a resting ball away */
    b3x_body_set_transform(ball, 0, 0.5, 0, 0, 0, 0, 1);
    b3x_body_set_velocity(ball, 0, 0, 0);
    b3x_body_set_awake(ball, 1);
    b3x_world_explode(w, -1, 0.5, 0, 5, 1, 10);
    CHECK(parse(b3x_body_velocity(ball), v, 9) == 3 && v[0] > 0.5, "the blast pushes +x: '%s'", b3x_body_velocity(ball));
    b3x_world_explode(w, NAN, 0, 0, 5, 1, 10);     /* refused, harmless */

    b3x_world_destroy(w);
}

/* ------------------------------------------------------------------ */
/* >>> BEGIN JOINT FAMILY TABLE (generated: tools/check-smoke-coverage.py --write) >>> */
/* Derived from the shim: every scalar joint setter with its getter, every
 * enable flag with its reader, and every getter that has no setter. The
 * family number indexes the handles test_joint_families() is given:
 * revolute 0, prismatic 1, spherical 2, weld 3, distance 4, wheel 5, motor 6, parallel 7. */
typedef struct { const char *name; int family; void (*set)(int, double); double (*get)(int); } FloatPair;
typedef struct { const char *name; int family; void (*set)(int, int); int (*get)(int); } FlagPair;
typedef struct { const char *name; int family; double (*get)(int); } Getter;
static const FloatPair k_float_pairs[] = {
    { "b3x_revolute_set_spring_hertz", 0, b3x_revolute_set_spring_hertz, b3x_revolute_spring_hertz },
    { "b3x_revolute_set_spring_damping_ratio", 0, b3x_revolute_set_spring_damping_ratio, b3x_revolute_spring_damping_ratio },
    { "b3x_revolute_set_target_angle", 0, b3x_revolute_set_target_angle, b3x_revolute_target_angle },
    { "b3x_revolute_set_motor_speed", 0, b3x_revolute_set_motor_speed, b3x_revolute_motor_speed },
    { "b3x_revolute_set_max_motor_torque", 0, b3x_revolute_set_max_motor_torque, b3x_revolute_max_motor_torque },
    { "b3x_prismatic_set_spring_hertz", 1, b3x_prismatic_set_spring_hertz, b3x_prismatic_spring_hertz },
    { "b3x_prismatic_set_spring_damping_ratio", 1, b3x_prismatic_set_spring_damping_ratio, b3x_prismatic_spring_damping_ratio },
    { "b3x_prismatic_set_target_translation", 1, b3x_prismatic_set_target_translation, b3x_prismatic_target_translation },
    { "b3x_prismatic_set_motor_speed", 1, b3x_prismatic_set_motor_speed, b3x_prismatic_motor_speed },
    { "b3x_prismatic_set_max_motor_force", 1, b3x_prismatic_set_max_motor_force, b3x_prismatic_max_motor_force },
    { "b3x_spherical_set_cone_limit", 2, b3x_spherical_set_cone_limit, b3x_spherical_cone_limit },
    { "b3x_spherical_set_spring_hertz", 2, b3x_spherical_set_spring_hertz, b3x_spherical_spring_hertz },
    { "b3x_spherical_set_spring_damping_ratio", 2, b3x_spherical_set_spring_damping_ratio, b3x_spherical_spring_damping_ratio },
    { "b3x_spherical_set_max_motor_torque", 2, b3x_spherical_set_max_motor_torque, b3x_spherical_max_motor_torque },
    { "b3x_weld_set_linear_hertz", 3, b3x_weld_set_linear_hertz, b3x_weld_linear_hertz },
    { "b3x_weld_set_linear_damping_ratio", 3, b3x_weld_set_linear_damping_ratio, b3x_weld_linear_damping_ratio },
    { "b3x_weld_set_angular_hertz", 3, b3x_weld_set_angular_hertz, b3x_weld_angular_hertz },
    { "b3x_weld_set_angular_damping_ratio", 3, b3x_weld_set_angular_damping_ratio, b3x_weld_angular_damping_ratio },
    { "b3x_distance_set_length", 4, b3x_distance_set_length, b3x_distance_length },
    { "b3x_distance_set_spring_hertz", 4, b3x_distance_set_spring_hertz, b3x_distance_spring_hertz },
    { "b3x_distance_set_spring_damping_ratio", 4, b3x_distance_set_spring_damping_ratio, b3x_distance_spring_damping_ratio },
    { "b3x_distance_set_motor_speed", 4, b3x_distance_set_motor_speed, b3x_distance_motor_speed },
    { "b3x_distance_set_max_motor_force", 4, b3x_distance_set_max_motor_force, b3x_distance_max_motor_force },
    { "b3x_wheel_set_suspension_hertz", 5, b3x_wheel_set_suspension_hertz, b3x_wheel_suspension_hertz },
    { "b3x_wheel_set_suspension_damping_ratio", 5, b3x_wheel_set_suspension_damping_ratio, b3x_wheel_suspension_damping_ratio },
    { "b3x_wheel_set_spin_motor_speed", 5, b3x_wheel_set_spin_motor_speed, b3x_wheel_spin_motor_speed },
    { "b3x_wheel_set_max_spin_torque", 5, b3x_wheel_set_max_spin_torque, b3x_wheel_max_spin_torque },
    { "b3x_wheel_set_steering_hertz", 5, b3x_wheel_set_steering_hertz, b3x_wheel_steering_hertz },
    { "b3x_wheel_set_steering_damping_ratio", 5, b3x_wheel_set_steering_damping_ratio, b3x_wheel_steering_damping_ratio },
    { "b3x_wheel_set_max_steering_torque", 5, b3x_wheel_set_max_steering_torque, b3x_wheel_max_steering_torque },
    { "b3x_wheel_set_target_steering_angle", 5, b3x_wheel_set_target_steering_angle, b3x_wheel_target_steering_angle },
    { "b3x_motor_set_max_velocity_force", 6, b3x_motor_set_max_velocity_force, b3x_motor_max_velocity_force },
    { "b3x_motor_set_max_velocity_torque", 6, b3x_motor_set_max_velocity_torque, b3x_motor_max_velocity_torque },
    { "b3x_motor_set_linear_hertz", 6, b3x_motor_set_linear_hertz, b3x_motor_linear_hertz },
    { "b3x_motor_set_linear_damping_ratio", 6, b3x_motor_set_linear_damping_ratio, b3x_motor_linear_damping_ratio },
    { "b3x_motor_set_angular_hertz", 6, b3x_motor_set_angular_hertz, b3x_motor_angular_hertz },
    { "b3x_motor_set_angular_damping_ratio", 6, b3x_motor_set_angular_damping_ratio, b3x_motor_angular_damping_ratio },
    { "b3x_motor_set_max_spring_force", 6, b3x_motor_set_max_spring_force, b3x_motor_max_spring_force },
    { "b3x_motor_set_max_spring_torque", 6, b3x_motor_set_max_spring_torque, b3x_motor_max_spring_torque },
    { "b3x_parallel_set_spring_hertz", 7, b3x_parallel_set_spring_hertz, b3x_parallel_spring_hertz },
    { "b3x_parallel_set_spring_damping_ratio", 7, b3x_parallel_set_spring_damping_ratio, b3x_parallel_spring_damping_ratio },
    { "b3x_parallel_set_max_torque", 7, b3x_parallel_set_max_torque, b3x_parallel_max_torque },
};
static const FlagPair k_flag_pairs[] = {
    { "b3x_revolute_enable_spring", 0, b3x_revolute_enable_spring, b3x_revolute_is_spring_enabled },
    { "b3x_revolute_enable_limit", 0, b3x_revolute_enable_limit, b3x_revolute_is_limit_enabled },
    { "b3x_revolute_enable_motor", 0, b3x_revolute_enable_motor, b3x_revolute_is_motor_enabled },
    { "b3x_prismatic_enable_spring", 1, b3x_prismatic_enable_spring, b3x_prismatic_is_spring_enabled },
    { "b3x_prismatic_enable_limit", 1, b3x_prismatic_enable_limit, b3x_prismatic_is_limit_enabled },
    { "b3x_prismatic_enable_motor", 1, b3x_prismatic_enable_motor, b3x_prismatic_is_motor_enabled },
    { "b3x_spherical_enable_cone_limit", 2, b3x_spherical_enable_cone_limit, b3x_spherical_is_cone_limit_enabled },
    { "b3x_spherical_enable_twist_limit", 2, b3x_spherical_enable_twist_limit, b3x_spherical_is_twist_limit_enabled },
    { "b3x_spherical_enable_spring", 2, b3x_spherical_enable_spring, b3x_spherical_is_spring_enabled },
    { "b3x_spherical_enable_motor", 2, b3x_spherical_enable_motor, b3x_spherical_is_motor_enabled },
    { "b3x_distance_enable_spring", 4, b3x_distance_enable_spring, b3x_distance_is_spring_enabled },
    { "b3x_distance_enable_limit", 4, b3x_distance_enable_limit, b3x_distance_is_limit_enabled },
    { "b3x_distance_enable_motor", 4, b3x_distance_enable_motor, b3x_distance_is_motor_enabled },
    { "b3x_wheel_enable_suspension", 5, b3x_wheel_enable_suspension, b3x_wheel_is_suspension_enabled },
    { "b3x_wheel_enable_suspension_limit", 5, b3x_wheel_enable_suspension_limit, b3x_wheel_is_suspension_limit_enabled },
    { "b3x_wheel_enable_spin_motor", 5, b3x_wheel_enable_spin_motor, b3x_wheel_is_spin_motor_enabled },
    { "b3x_wheel_enable_steering", 5, b3x_wheel_enable_steering, b3x_wheel_is_steering_enabled },
    { "b3x_wheel_enable_steering_limit", 5, b3x_wheel_enable_steering_limit, b3x_wheel_is_steering_limit_enabled },
};
static const Getter k_getters[] = {
    { "b3x_revolute_angle", 0, b3x_revolute_angle },
    { "b3x_revolute_lower_limit", 0, b3x_revolute_lower_limit },
    { "b3x_revolute_upper_limit", 0, b3x_revolute_upper_limit },
    { "b3x_revolute_motor_torque", 0, b3x_revolute_motor_torque },
    { "b3x_prismatic_lower_limit", 1, b3x_prismatic_lower_limit },
    { "b3x_prismatic_upper_limit", 1, b3x_prismatic_upper_limit },
    { "b3x_prismatic_motor_force", 1, b3x_prismatic_motor_force },
    { "b3x_prismatic_translation", 1, b3x_prismatic_translation },
    { "b3x_prismatic_speed", 1, b3x_prismatic_speed },
    { "b3x_spherical_cone_angle", 2, b3x_spherical_cone_angle },
    { "b3x_spherical_lower_twist_limit", 2, b3x_spherical_lower_twist_limit },
    { "b3x_spherical_upper_twist_limit", 2, b3x_spherical_upper_twist_limit },
    { "b3x_spherical_twist_angle", 2, b3x_spherical_twist_angle },
    { "b3x_distance_min_length", 4, b3x_distance_min_length },
    { "b3x_distance_max_length", 4, b3x_distance_max_length },
    { "b3x_distance_current_length", 4, b3x_distance_current_length },
    { "b3x_distance_motor_force", 4, b3x_distance_motor_force },
    { "b3x_wheel_lower_suspension_limit", 5, b3x_wheel_lower_suspension_limit },
    { "b3x_wheel_upper_suspension_limit", 5, b3x_wheel_upper_suspension_limit },
    { "b3x_wheel_spin_speed", 5, b3x_wheel_spin_speed },
    { "b3x_wheel_spin_torque", 5, b3x_wheel_spin_torque },
    { "b3x_wheel_lower_steering_limit", 5, b3x_wheel_lower_steering_limit },
    { "b3x_wheel_upper_steering_limit", 5, b3x_wheel_upper_steering_limit },
    { "b3x_wheel_steering_angle", 5, b3x_wheel_steering_angle },
    { "b3x_wheel_steering_torque", 5, b3x_wheel_steering_torque },
};
/* <<< END JOINT FAMILY TABLE <<< */

static void test_joint_families(int revolute, int prismatic, int spherical, int weld,
                                int distance, int wheel, int motor, int parallel)
{
    int handles[8] = { revolute, prismatic, spherical, weld, distance, wheel, motor, parallel };
    int nf = (int)(sizeof(k_float_pairs) / sizeof(k_float_pairs[0]));
    for (int i = 0; i < nf; i++) {
        const FloatPair *p = &k_float_pairs[i];
        int j = handles[p->family];
        p->set(j, 0.375);
        CHECK(near(p->get(j), 0.375, 1e-5), "%s: set 0.375, read %g", p->name, p->get(j));
        p->set(j, NAN);
        CHECK(near(p->get(j), 0.375, 1e-5), "%s: NaN refused", p->name);
        /* on a joint of ANOTHER type: no effect, 0 back */
        int other = handles[(p->family + 1) % 8];
        p->set(other, 0.5);
        CHECK(p->get(other) == 0.0, "%s on another joint type reads 0", p->name);
        p->set(0, 0.5);
        CHECK(p->get(0) == 0.0, "%s on no joint reads 0", p->name);
    }
    int nb = (int)(sizeof(k_flag_pairs) / sizeof(k_flag_pairs[0]));
    for (int i = 0; i < nb; i++) {
        const FlagPair *p = &k_flag_pairs[i];
        int j = handles[p->family];
        p->set(j, 1);
        CHECK(p->get(j) == 1, "%s: on", p->name);
        p->set(j, 0);
        CHECK(p->get(j) == 0, "%s: off", p->name);
        int other = handles[(p->family + 1) % 8];
        p->set(other, 1);
        CHECK(p->get(other) == 0, "%s on another joint type reads 0", p->name);
    }
    int ng = (int)(sizeof(k_getters) / sizeof(k_getters[0]));
    for (int i = 0; i < ng; i++) {
        const Getter *g = &k_getters[i];
        double value = g->get(handles[g->family]);
        CHECK(isfinite(value), "%s is finite", g->name);
        CHECK(g->get(handles[(g->family + 1) % 8]) == 0.0 && g->get(0) == 0.0, "%s on another joint reads 0", g->name);
    }
}

static void test_joints(void)
{
    double v[12];
    int w = b3x_world_create(0, -10, 0, 1);
    int anchor = b3x_body_create(w, 0, 0, 10, 0);
    b3x_shape_add_box(anchor, 0.1, 0.1, 0.1, 0, 0.5, 0);

    /* refusals first */
    int lone = b3x_body_create(w, 2, 50, 0, 0);
    CHECK(b3x_joint_weld(w, lone, lone, 0, 0, 0, 0) == 0, "a joint needs two bodies");
    CHECK(b3x_joint_weld(w, lone, 0, 0, 0, 0, 0) == 0, "a joint needs live bodies");
    CHECK(b3x_joint_revolute(w, anchor, lone, 0, 0, 0, 0, 0, 0, 0) == 0, "a zero axis is refused: %s", b3x_last_error());
    int w2 = b3x_world_create(0, 0, 0, 1);
    int foreign = b3x_body_create(w2, 2, 0, 0, 0);
    CHECK(b3x_joint_weld(w, anchor, foreign, 0, 0, 0, 0) == 0, "bodies of two worlds cannot be joined");
    b3x_world_destroy(w2);
    b3x_body_destroy(lone);

    /* revolute: a pendulum about the z axis keeps its arm length */
    int bob = b3x_body_create(w, 2, 2, 10, 0);
    b3x_shape_add_sphere(bob, 0, 0, 0, 0.25, 1, 0.5, 0);
    int rev = b3x_joint_revolute(w, anchor, bob, 0, 10, 0, 0, 0, 1, 0);
    CHECK(rev > 0 && b3x_joint_type(rev) == 5, "revolute %d: %s", rev, b3x_last_error());
    CHECK(b3x_joint_body_a(rev) == anchor && b3x_joint_body_b(rev) == bob, "joint bodies");
    CHECK(b3x_joint_is_valid(rev) == 1, "valid");
    double lowest = 10;
    for (int i = 0; i < 120; i++) {
        b3x_world_step(w, 1.0 / 60.0, 4);
        double x = b3x_body_x(bob), y = b3x_body_y(bob) - 10.0;
        if (b3x_body_y(bob) < lowest) lowest = b3x_body_y(bob);
        if (i % 30 == 0) CHECK(near(sqrt(x * x + y * y), 2.0, 0.05), "arm length %g at step %d", sqrt(x * x + y * y), i);
        CHECK(near(b3x_body_z(bob), 0, 0.02), "the hinge keeps it in the plane: z %g", b3x_body_z(bob));
    }
    CHECK(lowest < 8.3, "it swung down: lowest y %g", lowest);
    CHECK(parse(b3x_joint_local_frame_a(rev), v, 12) == 7 && parse(b3x_joint_local_frame_b(rev), v, 12) == 7, "frames");
    CHECK(near(v[0], -2.0, 1e-3), "frame B sits at the pivot, 2 from the bob: %g", v[0]);
    CHECK(parse(b3x_joint_constraint_force(rev), v, 12) == 3 && (fabs(v[0]) + fabs(v[1])) > 0.1, "the hinge carries a force '%s'", b3x_joint_constraint_force(rev));
    CHECK(parse(b3x_joint_constraint_torque(rev), v, 12) == 3, "constraint torque text");
    CHECK(b3x_joint_linear_separation(rev) < 0.05 && b3x_joint_angular_separation(rev) < 0.05, "the hinge holds together");
    /* limits stop it; a motor drives it */
    b3x_revolute_set_limits(rev, -0.1, 0.1);
    CHECK(near(b3x_revolute_lower_limit(rev), -0.1, 1e-5) && near(b3x_revolute_upper_limit(rev), 0.1, 1e-5), "limits read back");
    b3x_revolute_set_limits(rev, 1, -1);
    CHECK(near(b3x_revolute_lower_limit(rev), -0.1, 1e-5), "inverted limits refused");
    b3x_revolute_enable_limit(rev, 0);
    b3x_revolute_enable_motor(rev, 1);
    b3x_revolute_set_max_motor_torque(rev, 1000);
    b3x_revolute_set_motor_speed(rev, 2.0);
    double a0 = b3x_revolute_angle(rev);
    step(w, 30);
    CHECK(fabs(b3x_revolute_angle(rev) - a0) > 0.5 || fabs(fabs(b3x_revolute_angle(rev) - a0) - 6.283) < 1.0, "the motor turns it: %g -> %g", a0, b3x_revolute_angle(rev));
    b3x_revolute_enable_motor(rev, 0);
    b3x_joint_set_collide_connected(rev, 1);
    CHECK(b3x_joint_collide_connected(rev) == 1, "collide connected");
    b3x_joint_wake_bodies(rev);

    /* prismatic along x: gravity cannot pull the slider down */
    int slider = b3x_body_create(w, 2, 0, 20, 5);
    b3x_shape_add_box(slider, 0.25, 0.25, 0.25, 1, 0.5, 0);
    int rail = b3x_body_create(w, 0, 0, 20, 5);
    int pri = b3x_joint_prismatic(w, rail, slider, 0, 20, 5, 1, 0, 0, 0);
    CHECK(pri > 0 && b3x_joint_type(pri) == 4, "prismatic");
    b3x_prismatic_enable_motor(pri, 1);
    b3x_prismatic_set_max_motor_force(pri, 1000);
    b3x_prismatic_set_motor_speed(pri, 1.0);
    step(w, 60);
    CHECK(near(b3x_body_y(slider), 20, 0.02) && near(b3x_body_z(slider), 5, 0.02), "the slider stays on its rail");
    CHECK(near(b3x_body_x(slider), 1.0, 0.1) && near(b3x_prismatic_translation(pri), 1.0, 0.1), "and travels 1 m in 1 s: x %g, translation %g", b3x_body_x(slider), b3x_prismatic_translation(pri));
    CHECK(near(b3x_prismatic_speed(pri), 1.0, 0.1), "prismatic speed %g", b3x_prismatic_speed(pri));
    b3x_prismatic_set_limits(pri, -0.5, 1.25);
    CHECK(near(b3x_prismatic_upper_limit(pri), 1.25, 1e-5), "prismatic limits");
    b3x_prismatic_enable_limit(pri, 1);
    step(w, 60);
    CHECK(b3x_body_x(slider) < 1.35, "the limit stops it at 1.25: x %g", b3x_body_x(slider));

    /* distance: a rod keeps two bodies 3 apart */
    int hang = b3x_body_create(w, 2, 20, 7, 0);
    b3x_shape_add_sphere(hang, 0, 0, 0, 0.25, 1, 0.5, 0);
    int post = b3x_body_create(w, 0, 20, 10, 0);
    int dist = b3x_joint_distance(w, post, hang, 20, 10, 0, 20, 7, 0, 0);
    CHECK(dist > 0 && b3x_joint_type(dist) == 1 && near(b3x_distance_length(dist), 3.0, 1e-4), "distance joint, length %g", b3x_distance_length(dist));
    step(w, 90);
    CHECK(near(b3x_body_y(hang), 7.0, 0.05) && near(b3x_distance_current_length(dist), 3.0, 0.05), "the rod holds: y %g", b3x_body_y(hang));
    b3x_distance_set_length_range(dist, 1, 5);
    CHECK(near(b3x_distance_min_length(dist), 1, 1e-5) && near(b3x_distance_max_length(dist), 5, 1e-5), "length range");
    b3x_distance_set_length_range(dist, 5, 1);
    CHECK(near(b3x_distance_min_length(dist), 1, 1e-5), "inverted range refused");

    /* weld: a welded block hangs where it was put */
    int block = b3x_body_create(w, 2, 30, 10, 0);
    b3x_shape_add_box(block, 0.25, 0.25, 0.25, 1, 0.5, 0);
    int wall = b3x_body_create(w, 0, 30, 11, 0);
    int weld = b3x_joint_weld(w, wall, block, 30, 10.5, 0, 0);
    CHECK(weld > 0 && b3x_joint_type(weld) == 7, "weld");
    step(w, 90);
    CHECK(near(b3x_body_y(block), 10.0, 0.05), "the weld holds: y %g", b3x_body_y(block));

    /* spherical: a ball-and-socket pendulum keeps its arm length in 3D */
    int orb = b3x_body_create(w, 2, 41, 10, 1);
    b3x_shape_add_sphere(orb, 0, 0, 0, 0.25, 1, 0.5, 0);
    int hook = b3x_body_create(w, 0, 40, 10, 0);
    int sph = b3x_joint_spherical(w, hook, orb, 40, 10, 0, 0, -1, 0, 0);
    CHECK(sph > 0 && b3x_joint_type(sph) == 6, "spherical");
    step(w, 90);
    {
        double dx = b3x_body_x(orb) - 40, dy = b3x_body_y(orb) - 10, dz = b3x_body_z(orb);
        CHECK(near(sqrt(dx * dx + dy * dy + dz * dz), sqrt(2.0), 0.05), "socket arm length %g", sqrt(dx * dx + dy * dy + dz * dz));
    }
    b3x_spherical_set_twist_limits(sph, -0.5, 0.5);
    CHECK(near(b3x_spherical_lower_twist_limit(sph), -0.5, 1e-5) && near(b3x_spherical_upper_twist_limit(sph), 0.5, 1e-5), "twist limits");
    b3x_spherical_set_motor_velocity(sph, 0, 1, 0);
    CHECK(parse(b3x_spherical_motor_velocity(sph), v, 12) == 3 && near(v[1], 1, 1e-5), "spherical motor velocity");
    CHECK(parse(b3x_spherical_motor_torque(sph), v, 12) == 3, "spherical motor torque text");
    b3x_spherical_set_target_rotation(sph, 0, 0, 1, 1);
    CHECK(parse(b3x_spherical_target_rotation(sph), v, 12) == 4 && near(v[2], 0.70710678, 1e-4), "target rotation normalized");

    /* wheel: a wheel under a held chassis spins about z when driven */
    int chassis = b3x_body_create(w, 0, 50, 10, 0);
    int tyre = b3x_body_create(w, 2, 50, 9, 0);
    b3x_shape_add_cylinder(tyre, 0.2, 0.4, 16, 1, 0.5, 0);
    int wheel = b3x_joint_wheel(w, chassis, tyre, 50, 9, 0, 0, 1, 0, 0, 0, 1, 0);
    CHECK(wheel > 0 && b3x_joint_type(wheel) == 8, "wheel: %s", b3x_last_error());
    CHECK(b3x_joint_wheel(w, chassis, tyre, 50, 9, 0, 0, 1, 0, 0, 1, 0, 0) == 0, "spin axis along the suspension refused");
    b3x_wheel_enable_spin_motor(wheel, 1);
    b3x_wheel_set_max_spin_torque(wheel, 100);
    b3x_wheel_set_spin_motor_speed(wheel, 5.0);
    step(w, 60);
    CHECK(parse(b3x_body_angular_velocity(tyre), v, 12) == 3 && near(fabs(v[2]), 5.0, 0.5), "the wheel spins about z at 5 rad/s: '%s'", b3x_body_angular_velocity(tyre));
    CHECK(near(fabs(b3x_wheel_spin_speed(wheel)), 5.0, 0.5), "spin speed %g", b3x_wheel_spin_speed(wheel));
    CHECK(near(b3x_body_x(tyre), 50, 0.05) && near(b3x_body_z(tyre), 0, 0.05), "and stays under the chassis");
    b3x_wheel_set_suspension_limits(wheel, -0.3, 0.3);
    CHECK(near(b3x_wheel_lower_suspension_limit(wheel), -0.3, 1e-5) && near(b3x_wheel_upper_suspension_limit(wheel), 0.3, 1e-5), "suspension limits");
    b3x_wheel_set_steering_limits(wheel, -0.6, 0.6);
    CHECK(near(b3x_wheel_lower_steering_limit(wheel), -0.6, 1e-5) && near(b3x_wheel_upper_steering_limit(wheel), 0.6, 1e-5), "steering limits");

    /* motor joint: holds a body against gravity, then drives it */
    int lift = b3x_body_create(w, 2, 60, 10, 0);
    b3x_shape_add_box(lift, 0.25, 0.25, 0.25, 1, 0.5, 0);
    int base = b3x_body_create(w, 0, 60, 10, 0);
    int mot = b3x_joint_motor(w, base, lift, 0);
    CHECK(mot > 0 && b3x_joint_type(mot) == 3, "motor joint");
    b3x_motor_set_max_velocity_force(mot, 1000);
    b3x_motor_set_max_velocity_torque(mot, 1000);
    b3x_motor_set_linear_velocity(mot, 0, 1, 0);
    CHECK(parse(b3x_motor_linear_velocity(mot), v, 12) == 3 && near(v[1], 1, 1e-5), "motor linear velocity");
    b3x_motor_set_angular_velocity(mot, 0, 0, 0);
    CHECK(parse(b3x_motor_angular_velocity(mot), v, 12) == 3 && near(v[2], 0, 1e-5), "motor angular velocity");
    step(w, 60);
    CHECK(near(b3x_body_y(lift), 11.0, 0.15), "the motor lifts it 1 m in 1 s against gravity: y %g", b3x_body_y(lift));

    /* parallel: a spring keeps a body's y axis upright */
    int top = b3x_body_create_rotated(w, 2, 70, 10, 0, 0.2588190, 0, 0, 0.9659258);   /* 30 degrees about x */
    b3x_shape_add_box(top, 0.25, 0.5, 0.25, 1, 0.5, 0);
    b3x_body_set_gravity_scale(top, 0);
    b3x_body_set_angular_damping(top, 2.0);
    int sky = b3x_body_create(w, 0, 70, 10, 0);
    int par = b3x_joint_parallel(w, sky, top, 0, 1, 0, 0);
    CHECK(par > 0 && b3x_joint_type(par) == 0, "parallel");
    b3x_parallel_set_spring_hertz(par, 4.0);
    b3x_parallel_set_spring_damping_ratio(par, 1.0);
    b3x_parallel_set_max_torque(par, 1000);
    CHECK(parse(b3x_body_world_vector(top, 0, 1, 0), v, 12) == 3 && v[1] < 0.9, "it starts tilted");
    step(w, 240);
    CHECK(parse(b3x_body_world_vector(top, 0, 1, 0), v, 12) == 3 && v[1] > 0.6, "the spring acts on the tilt: up.y %g", v[1]);

    /* filter joint: two overlapping boxes stop pushing each other apart */
    b3x_world_set_gravity(w, 0, 0, 0);
    int p1 = b3x_body_create(w, 2, 80, 10, 0);
    b3x_shape_add_box(p1, 0.5, 0.5, 0.5, 1, 0.5, 0);
    int p2 = b3x_body_create(w, 2, 80.5, 10, 0);
    b3x_shape_add_box(p2, 0.5, 0.5, 0.5, 1, 0.5, 0);
    int fil = b3x_joint_filter(w, p1, p2);
    CHECK(fil > 0 && b3x_joint_type(fil) == 2, "filter joint");
    step(w, 60);
    CHECK(near(b3x_body_x(p2) - b3x_body_x(p1), 0.5, 0.02), "filtered boxes stay overlapped: gap %g", b3x_body_x(p2) - b3x_body_x(p1));
    b3x_joint_destroy(fil, 1);
    CHECK(b3x_joint_is_valid(fil) == 0 && b3x_joint_type(fil) == -1, "filter joint destroyed");
    /* Box3D only looks for new pairs around a shape whose box left its fat
     * margin, so two boxes left where they were stay unaware of each other
     * (measured 2026-11-20: 60 steps, gap still 0.5). Moving one away and
     * back is the nudge. Documented in the API page. */
    step(w, 30);
    CHECK(near(b3x_body_x(p2) - b3x_body_x(p1), 0.5, 0.02), "untouched, they still overlap (Box3D's pair rule)");
    b3x_body_set_position(p2, 90, 10, 0);
    b3x_body_set_position(p2, 80.5, 10, 0);
    step(w, 60);
    CHECK(b3x_body_x(p2) - b3x_body_x(p1) > 0.9, "without it they are pushed apart: gap %g", b3x_body_x(p2) - b3x_body_x(p1));
    b3x_world_set_gravity(w, 0, -10, 0);

    /* joint events: a weld under a heavy load reports its force */
    b3x_joint_set_force_threshold(weld, 1.0);
    CHECK(near(b3x_joint_force_threshold(weld), 1.0, 1e-5), "force threshold");
    b3x_joint_set_torque_threshold(weld, 123.0);
    CHECK(near(b3x_joint_torque_threshold(weld), 123.0, 1e-3), "torque threshold");
    b3x_body_set_awake(block, 1);
    int sawEvent = 0;
    for (int i = 0; i < 30 && !sawEvent; i++) {
        b3x_world_step(w, 1.0 / 60.0, 4);
        b3x_body_set_awake(block, 1);
        if (b3x_world_update_joint_events(w) > 0) {
            for (int k = 1; k <= b3x_joint_event_count(); k++)
                if (b3x_joint_event_joint(k) == weld) sawEvent = 1;
        }
    }
    CHECK(sawEvent == 1, "the loaded weld raised a joint event");
    CHECK(b3x_joint_event_joint(0) == 0 && b3x_joint_event_joint(999) == 0, "joint event index out of range");

    /* frames can be moved */
    b3x_joint_set_local_frame_a(weld, 0, -1, 0, 0, 0, 0, 1);
    CHECK(parse(b3x_joint_local_frame_a(weld), v, 12) == 7 && near(v[1], -1, 1e-5), "frame A set");
    b3x_joint_set_local_frame_b(weld, 0, 0.25, 0, 0, 0, 0, 2);
    CHECK(parse(b3x_joint_local_frame_b(weld), v, 12) == 7 && near(v[1], 0.25, 1e-5) && near(v[6], 1, 1e-5), "frame B set, quaternion normalized");
    b3x_joint_set_local_frame_a(weld, NAN, 0, 0, 0, 0, 0, 1);
    CHECK(parse(b3x_joint_local_frame_a(weld), v, 12) == 7 && near(v[1], -1, 1e-5), "NaN frame refused");

    /* every scalar getter and setter, on its own joint and on the wrong one */
    test_joint_families(rev, pri, sph, weld, dist, wheel, mot, par);

    /* typed vector calls on the wrong joint type do nothing */
    b3x_motor_set_linear_velocity(rev, 1, 1, 1);
    CHECK(b3x_motor_linear_velocity(rev)[0] == 0 && b3x_motor_angular_velocity(rev)[0] == 0, "motor calls on a revolute do nothing");
    CHECK(b3x_spherical_motor_velocity(rev)[0] == 0 && b3x_spherical_motor_torque(rev)[0] == 0 && b3x_spherical_target_rotation(rev)[0] == 0, "spherical calls on a revolute do nothing");
    b3x_motor_set_angular_velocity(rev, 1, 1, 1);
    b3x_spherical_set_motor_velocity(rev, 1, 1, 1);
    b3x_spherical_set_target_rotation(rev, 0, 0, 0, 1);
    b3x_spherical_set_twist_limits(rev, -1, 1);
    b3x_prismatic_set_limits(rev, -1, 1);
    b3x_distance_set_length_range(rev, 1, 2);
    b3x_wheel_set_suspension_limits(rev, -1, 1);
    b3x_wheel_set_steering_limits(rev, -1, 1);
    b3x_revolute_set_limits(pri, -1, 1);
    CHECK(near(b3x_prismatic_upper_limit(pri), 0.375, 1e-5) || near(b3x_prismatic_upper_limit(pri), 1.25, 1e-5), "the prismatic limits were not touched by a revolute call");

    /* destroy; then everything on the dead handle is a no-op */
    b3x_joint_destroy(rev, 1);
    CHECK(b3x_joint_is_valid(rev) == 0, "revolute destroyed");
    b3x_joint_destroy(rev, 1);
    b3x_joint_set_collide_connected(rev, 1);
    b3x_joint_wake_bodies(rev);
    b3x_joint_set_force_threshold(rev, 1);
    b3x_joint_set_torque_threshold(rev, 1);
    b3x_joint_set_local_frame_b(rev, 0, 0, 0, 0, 0, 0, 1);
    CHECK(b3x_joint_body_a(rev) == 0 && b3x_joint_body_b(rev) == 0 && b3x_joint_collide_connected(rev) == 0, "a dead joint answers 0");
    CHECK(b3x_joint_local_frame_a(rev)[0] == 0 && b3x_joint_local_frame_b(rev)[0] == 0 && b3x_joint_constraint_force(rev)[0] == 0 && b3x_joint_constraint_torque(rev)[0] == 0, "dead joint texts are empty");
    CHECK(b3x_joint_linear_separation(rev) == 0.0 && b3x_joint_angular_separation(rev) == 0.0 && b3x_joint_force_threshold(rev) == 0.0 && b3x_joint_torque_threshold(rev) == 0.0, "dead joint numbers are 0");
    CHECK(b3x_revolute_angle(rev) == 0.0, "typed getter on a dead joint");
    CHECK(b3x_world_joint_count(w) >= 7, "joint count %d", b3x_world_joint_count(w));

    b3x_world_destroy(w);
    CHECK(b3x_joint_is_valid(weld) == 0 && b3x_joint_is_valid(wheel) == 0, "a world takes its joints with it");
}

/* ------------------------------------------------------------------ */
static void test_quaternions(void)
{
    double v[4], q[4];
    CHECK(parse(b3x_quat_from_axis_angle(0, 0, 5, 3.14159265 / 2), q, 4) == 4 && near(q[2], 0.70710678, 1e-5) && near(q[3], 0.70710678, 1e-5), "axis-angle (axis normalized)");
    CHECK(b3x_quat_from_axis_angle(0, 0, 0, 1)[0] == 0, "a zero axis is refused");
    CHECK(parse(b3x_quat_rotate(q[0], q[1], q[2], q[3], 1, 0, 0), v, 4) == 3 && near(v[0], 0, 1e-5) && near(v[1], 1, 1e-5), "rotate x by 90 about z gives y");
    CHECK(parse(b3x_quat_to_axis_angle(q[0], q[1], q[2], q[3]), v, 4) == 4 && near(v[2], 1, 1e-4) && near(v[3], 3.14159265 / 2, 1e-4), "back to axis-angle '%s'", b3x_quat_to_axis_angle(q[0], q[1], q[2], q[3]));
    /* two quarter turns about z make a half turn: x -> -x */
    CHECK(parse(b3x_quat_multiply(q[0], q[1], q[2], q[3], q[0], q[1], q[2], q[3]), v, 4) == 4, "multiply");
    double h[4] = { v[0], v[1], v[2], v[3] };
    CHECK(parse(b3x_quat_rotate(h[0], h[1], h[2], h[3], 1, 0, 0), v, 4) == 3 && near(v[0], -1, 1e-5), "half turn");
    /* euler: x then y then z. A quarter turn about x takes y to z; then a
     * quarter turn about z leaves z alone. */
    CHECK(parse(b3x_quat_from_euler(3.14159265 / 2, 0, 3.14159265 / 2), q, 4) == 4, "euler");
    CHECK(parse(b3x_quat_rotate(q[0], q[1], q[2], q[3], 0, 1, 0), v, 4) == 3 && near(v[2], 1, 1e-5), "euler order: y ends on z ('%s')", b3x_quat_rotate(q[0], q[1], q[2], q[3], 0, 1, 0));
    CHECK(b3x_quat_from_euler(NAN, 0, 0)[0] == 0 && b3x_quat_multiply(0, 0, 0, 0, 0, 0, 0, 1)[0] == 0 && b3x_quat_rotate(0, 0, 0, 0, 1, 0, 0)[0] == 0 && b3x_quat_to_axis_angle(0, 0, 0, 0)[0] == 0, "bad quaternions are refused");
}

/* ------------------------------------------------------------------ */
/* The text results use '.' whatever the locale: a German engine would
 * otherwise hand a script "1,5" as two items. Skips when the container has
 * no comma-decimal locale installed (and says so). */
static void test_locale(void)
{
    static const char *names[] = { "de_DE.UTF-8", "de_DE.utf8", "de_DE", "fr_FR.UTF-8", "fr_FR.utf8", "German_Germany", "German", NULL };
    const char *got = NULL;
    for (int i = 0; names[i] && !got; i++) got = setlocale(LC_NUMERIC, names[i]);
    if (!got) {
        printf("NOTE: no comma-decimal locale on this machine; the locale check ran in the C locale only\n");
    } else {
        char probe[32];
        snprintf(probe, sizeof probe, "%.1f", 1.5);
        if (probe[1] != ',') {
            printf("NOTE: locale %s prints '%s'; the locale check ran with a '.' locale only\n", got, probe);
        }
    }
    int w = b3x_world_create(0, -9.5, 0, 1);
    double v[3];
    const char *text = b3x_world_gravity(w);
    CHECK(strcmp(text, "0,-9.5,0") == 0, "gravity text under locale %s is '%s'", got ? got : "C", text);
    CHECK(parse(text, v, 3) == 3 && near(v[1], -9.5, 1e-9), "three items, not four");
    int b = b3x_body_create(w, 2, 1.25, 2.5, -3.75);
    CHECK(strcmp(b3x_body_position(b), "1.25,2.5,-3.75") == 0, "position text is '%s'", b3x_body_position(b));
    b3x_shape_add_sphere(b, 0, 0, 0, 0.5, 1, 0.5, 0);
    b3x_world_step(w, 1.0 / 60.0, 4);
    b3x_world_update_moves(w);
    CHECK(strchr(b3x_moves_text(), '.') != NULL && parse(b3x_moves_text(), v, 3) == 3, "moves text uses '.' too: '%s'", b3x_moves_text());
    b3x_world_destroy(w);
    setlocale(LC_NUMERIC, "C");
}

/* ------------------------------------------------------------------ */
/* Many bodies, many worlds, threads, and handle churn. */
static void test_stress(void)
{
    /* a pile of 300 boxes settles above the floor, on 1 worker and on 4 */
    double top[2] = { 0, 0 };
    for (int pass = 0; pass < 2; pass++) {
        int ground;
        int w = make_world(&ground);
        if (pass == 1) b3x_world_set_worker_count(w, 4);
        int bodies[300];
        for (int i = 0; i < 300; i++) {
            bodies[i] = b3x_body_create(w, 2, (i % 5) * 1.1 - 2.2, 1 + (i / 25) * 1.1, ((i / 5) % 5) * 1.1 - 2.2);
            b3x_shape_add_box(bodies[i], 0.5, 0.5, 0.5, 1.0, 0.6, 0.0);
        }
        step(w, 300);
        int below = 0, wild = 0;
        for (int i = 0; i < 300; i++) {
            double y = b3x_body_y(bodies[i]);
            if (y < 0.3) below++;
            if (!isfinite(y) || y > 40) wild++;
            if (y > top[pass]) top[pass] = y;
        }
        CHECK(below == 0, "pass %d: no box fell through the floor (%d did)", pass, below);
        CHECK(wild == 0, "pass %d: no box flew off (%d did)", pass, wild);
        CHECK(b3x_world_body_count(w) == 301 && b3x_world_contact_count(w) > 300, "pass %d: counts %d bodies, %d contacts", pass, b3x_world_body_count(w), b3x_world_contact_count(w));
        CHECK(b3x_world_update_moves(w) >= 0, "moves after a pile");
        b3x_world_destroy(w);
    }
    CHECK(top[0] > 5 && top[1] > 5, "the pile stands: top %g (1 worker), %g (4 workers)", top[0], top[1]);

    /* handle churn: create and destroy 5000 bodies; slots are reused and the
     * generation keeps every old handle dead */
    int w = b3x_world_create(0, -10, 0, 1);
    int first = b3x_body_create(w, 2, 0, 0, 0);
    b3x_body_destroy(first);
    int stale = 0;
    for (int i = 0; i < 5000; i++) {
        int b = b3x_body_create(w, 2, 0, 0, 0);
        int s = b3x_shape_add_sphere(b, 0, 0, 0, 0.5, 1, 0.5, 0);
        if (b3x_body_is_valid(first)) stale++;
        b3x_body_destroy(b);
        if (b3x_shape_is_valid(s)) stale++;
    }
    CHECK(stale == 0, "no stale handle ever came back to life (%d did)", stale);
    CHECK(b3x_world_body_count(w) == 0, "all gone");
    b3x_world_destroy(w);

    /* worlds: more than Box3D allows at once is refused, not a crash */
    int worlds[200], made = 0;
    for (int i = 0; i < 200; i++) {
        worlds[i] = b3x_world_create(0, -10, 0, 1);
        if (worlds[i]) made++;
    }
    CHECK(made >= 100 && made < 200, "Box3D's world limit is refused cleanly (%d made)", made);
    CHECK(strlen(b3x_last_error()) > 0, "and explained: %s", b3x_last_error());
    for (int i = 0; i < 200; i++) b3x_world_destroy(worlds[i]);
    int again = b3x_world_create(0, -10, 0, 1);
    CHECK(again > 0, "and worlds can be made again afterwards");
    b3x_world_destroy(again);
}

/* ------------------------------------------------------------------ */
/* The net: a scene Box3D itself drives to NaN (found by the fuzz test, cut
 * down to these calls). The bodies must be removed, the world must go on
 * working, and nothing may crash - under ASan this is the test that used to
 * end in a segfault inside the broad-phase tree. */
static int s_netAsserts = 0;
/* The stale move index (the shim's s_sleepUnsafe): the exact scene the fuzz
 * test minimised from seeds 14 and 65. Under asserts this aborted in
 * solver_set.c; in Release it wrote through a dead index. */
static void test_stale_sleep(void)
{
    int assertsBefore = b3x_assert_count();
    int w = b3x_world_create(0, -10, 0, 1);
    int ground = b3x_body_create(w, 0, 0, -1, 0);
    b3x_shape_add_box(ground, 30, 1, 30, 0, 0.6, 0);
    int other[4];
    for (int i = 0; i < 4; i++) {
        other[i] = b3x_body_create(w, 2, 3.0 * i, 3, 0);
        b3x_shape_add_sphere(other[i], 0, 0, 0, 0.5, 1, 0.5, 0);
    }
    int b = b3x_body_create(w, 2, -5, 3, 0);
    b3x_shape_add_sphere(b, 0, 0, 0, 0.5, 1, 0.5, 0);
    b3x_world_step(w, 1.0 / 60.0, 4);
    b3x_body_disable(b);
    b3x_body_destroy(other[0]);                 /* so the old index is past the new list */
    b3x_body_destroy(other[1]);
    b3x_body_destroy(other[2]);
    b3x_world_step(w, 1.0 / 60.0, 4);
    b3x_body_enable(b);
    b3x_body_set_awake(b, 0);
    CHECK(strlen(b3x_last_error()) > 0, "a sleep straight after an enable is refused with a reason");
    CHECK(b3x_body_is_awake(b), "and the body stays awake");
    b3x_body_set_awake(other[3], 0);
    CHECK(b3x_body_is_awake(other[3]), "the refusal covers the whole world (a sleep takes an island)");
    b3x_world_step(w, 1.0 / 60.0, 4);
    b3x_body_set_awake(b, 0);
    CHECK(!b3x_body_is_awake(b) && strlen(b3x_last_error()) == 0, "after one step the sleep goes through: '%s'", b3x_last_error());
    /* the same through a change of type: dynamic, static, step, dynamic */
    b3x_body_set_awake(b, 1);
    b3x_world_step(w, 1.0 / 60.0, 4);
    b3x_body_set_type(b, 0);
    b3x_world_step(w, 1.0 / 60.0, 4);
    b3x_body_set_type(b, 2);
    b3x_body_set_awake(b, 0);
    CHECK(b3x_body_is_awake(b) && strlen(b3x_last_error()) > 0, "a sleep straight after a type change is refused");
    b3x_body_set_type(b, 2);                    /* no change: raises nothing */
    b3x_world_step(w, 1.0 / 60.0, 4);
    b3x_body_set_type(b, 2);
    b3x_body_set_awake(b, 0);
    CHECK(!b3x_body_is_awake(b), "setting the type a body already has does not block a sleep");
    /* a new world is not marked by an old one's flag */
    b3x_body_enable(b);
    b3x_world_destroy(w);
    int w2 = b3x_world_create(0, -10, 0, 1);
    int c = b3x_body_create(w2, 2, 0, 3, 0);
    b3x_shape_add_sphere(c, 0, 0, 0, 0.5, 1, 0.5, 0);
    b3x_body_set_awake(c, 0);
    CHECK(!b3x_body_is_awake(c), "a new world starts with sleeping allowed");
    b3x_world_destroy(w2);
    CHECK(b3x_assert_count() == assertsBefore, "none of it tripped a Box3D assert (%d)", b3x_assert_count() - assertsBefore);
}

static void test_net(void)
{
    int assertsBefore = b3x_assert_count();
    int removedBefore = b3x_unstable_count();
    int w = b3x_world_create(0, -10, 0, 1);
    int ground = b3x_body_create(w, 0, 0, -1, 0);
    b3x_shape_add_box(ground, 30, 1, 30, 0, 0.6, 0);
    int a = b3x_body_create(w, 2, -1.5, 1.8, 0);            /* no shapes: no mass */
    int b = b3x_body_create(w, 2, 0, 2.6, 1);               /* no shapes: no mass */
    b3x_joint_prismatic(w, a, b, 0, 2.6, 1, 1, 0, 0, 0);
    int c = b3x_body_create(w, 2, 1.5, 3.4, -1);
    b3x_shape_add_cylinder(c, 0.6, 0.3, 10, 1, 0.5, 0);
    b3x_joint_spherical(w, b, c, 1.5, 3.4, -1, 0, 1, 0, 0);
    int d = b3x_body_create(w, 2, -3, 4.2, 0);
    b3x_shape_add_cone(d, 0.6, 0.3, 0.1, 8, 1, 0.5, 0);
    int weld = b3x_joint_weld(w, c, d, -3, 4.2, 0, 0);
    b3x_joint_set_local_frame_b(weld, -571.9967, 7.4235, 7.1205, -0.8195902, 0.1920151, 0.4956728, -0.2138003);
    int bystander = b3x_body_create(w, 2, 10, 3, 10);
    int bystanderShape = b3x_shape_add_sphere(bystander, 0, 0, 0, 0.5, 1, 0.5, 0);
    for (int i = 0; i < 120; i++) b3x_world_step(w, 1.0 / 60.0, 4);
    int removed = b3x_unstable_count() - removedBefore;
    if (removed > 0) {
        CHECK(!b3x_body_is_valid(c) || !b3x_body_is_valid(d), "the unstable bodies are gone");
        CHECK(!b3x_joint_is_valid(weld), "and their joint with them");
        CHECK(strstr(b3x_last_error(), "removed") != NULL || b3x_last_error()[0] == 0, "the removal is explained: '%s'", b3x_last_error());
    } else {
        /* a platform whose float rounding keeps this scene finite: nothing to
         * remove, and that is a pass too. Say so, so a log shows which ran. */
        printf("NOTE: the unstable scene stayed finite on this platform; the net was not exercised\n");
    }
    /* whatever happened, every body left is made of numbers ... */
    int handles[5] = { a, b, c, d, bystander };
    for (int i = 0; i < 5; i++) {
        if (!b3x_body_is_valid(handles[i])) continue;
        double v[7];
        CHECK(parse(b3x_body_transform(handles[i]), v, 7) == 7 && isfinite(b3x_body_speed(handles[i])) && isfinite(b3x_body_x(handles[i])), "body %d is still numbers", i);
    }
    /* ... the world still works: the bystander fell and rests on the floor */
    CHECK(b3x_body_is_valid(bystander) && b3x_shape_is_valid(bystanderShape), "an uninvolved body is untouched");
    CHECK(near(b3x_body_y(bystander), 0.5, 0.05), "and it rests on the floor: y %g", b3x_body_y(bystander));
    int fresh = b3x_body_create(w, 2, 0, 5, 0);
    CHECK(fresh > 0 && b3x_shape_add_box(fresh, 0.5, 0.5, 0.5, 1, 0.5, 0) > 0, "new bodies can be made after it");
    for (int i = 0; i < 120; i++) b3x_world_step(w, 1.0 / 60.0, 4);
    CHECK(near(b3x_body_y(fresh), 0.5, 0.05), "and they simulate: y %g", b3x_body_y(fresh));
    CHECK(b3x_cast_ray_closest(w, 0, 10, 0, 0, -20, 0) == 1, "and queries walk the tree");
    b3x_world_destroy(w);
    /* In an assert build Box3D's own "this vector is valid" asserts fire in
     * the step that goes unstable; they are this test's and no other's. */
    s_netAsserts = b3x_assert_count() - assertsBefore;
}

/* ------------------------------------------------------------------ */
/* A REAL MODEL (2026-11-20). Every shape above is a handful of points typed
 * by hand. This one is the Utah teapot (tests/models/teapot.obj, carried
 * here as tests/teapot_model.h): thousands of points and triangles, with
 * duplicate points along its patch seams, thin parts (the spout, the handle)
 * and curved ones - what a model exported from a 3D editor looks like.
 *
 * The oracle is not Box3D: brute_ray() intersects a ray with every triangle
 * itself (Moller-Trumbore, both faces), and the shim's answer has to agree. */
#include "teapot_model.h"

static void teapot_geometry(double scale, int withTriangles)
{
    b3x_geometry_begin();
    for (int i = 0; i < TEAPOT_POINT_COUNT; i++)
        b3x_geometry_add_point(scale * kTeapotPoints[i][0], scale * kTeapotPoints[i][1], scale * kTeapotPoints[i][2]);
    if (withTriangles)
        for (int i = 0; i < TEAPOT_TRIANGLE_COUNT; i++)
            b3x_geometry_add_triangle(kTeapotTriangles[i][0], kTeapotTriangles[i][1], kTeapotTriangles[i][2]);
}

/* The nearest hit of origin + t * d, t in [0, 1], over every triangle; -1
 * for none. In doubles, so it is the more exact of the two answers. */
static double brute_ray(double ox, double oy, double oz, double dx, double dy, double dz, int frontOnly)
{
    double best = -1.0;
    for (int i = 0; i < TEAPOT_TRIANGLE_COUNT; i++)
    {
        const float *a = kTeapotPoints[kTeapotTriangles[i][0] - 1];
        const float *b = kTeapotPoints[kTeapotTriangles[i][1] - 1];
        const float *c = kTeapotPoints[kTeapotTriangles[i][2] - 1];
        double e1x = b[0] - a[0], e1y = b[1] - a[1], e1z = b[2] - a[2];
        double e2x = c[0] - a[0], e2y = c[1] - a[1], e2z = c[2] - a[2];
        double px = dy * e2z - dz * e2y, py = dz * e2x - dx * e2z, pz = dx * e2y - dy * e2x;
        double det = e1x * px + e1y * py + e1z * pz;
        /* front faces only: Box3D's meshes are one-sided (see test_model) */
        if (frontOnly ? det < 1e-12 : fabs(det) < 1e-12) continue;
        double tx = ox - a[0], ty = oy - a[1], tz = oz - a[2];
        double u = (tx * px + ty * py + tz * pz) / det;
        if (u < 0.0 || u > 1.0) continue;
        double qx = ty * e1z - tz * e1y, qy = tz * e1x - tx * e1z, qz = tx * e1y - ty * e1x;
        double vv = (dx * qx + dy * qy + dz * qz) / det;
        if (vv < 0.0 || u + vv > 1.0) continue;
        double t = (e2x * qx + e2y * qy + e2z * qz) / det;
        if (t < 0.0 || t > 1.0) continue;
        if (best < 0.0 || t < best) best = t;
    }
    return best;
}

/* One ray, asked of the shim and of the oracle. A ray that grazes an edge of
 * the silhouette is one two honest implementations may call differently, so
 * the oracle is asked four more times a hair to each side: only a ray all
 * five agree on is compared (returns 1), the rest are counted as skipped. */
static int teapot_ray_agrees(int w, int mesh, double ox, double oy, double oz, double dx, double dy, double dz, int *bad)
{
    const double h = 2e-3;
    double t = brute_ray(ox, oy, oz, dx, dy, dz, 1);
    double len = sqrt(dx * dx + dy * dy + dz * dz);
    /* two directions across the ray to nudge along */
    double ax = dy, ay = -dx, az = 0;
    if (fabs(ax) + fabs(ay) < 1e-9) { ax = 0; ay = dz; az = -dy; }
    double al = sqrt(ax * ax + ay * ay + az * az);
    ax /= al; ay /= al; az /= al;
    double bx = dy * az - dz * ay, by = dz * ax - dx * az, bz = dx * ay - dy * ax;
    double bl = sqrt(bx * bx + by * by + bz * bz);
    bx /= bl; by /= bl; bz /= bl;
    for (int k = 0; k < 4; k++)
    {
        double sx = (k == 0 ? ax : k == 1 ? -ax : k == 2 ? bx : -bx) * h;
        double sy = (k == 0 ? ay : k == 1 ? -ay : k == 2 ? by : -by) * h;
        double sz = (k == 0 ? az : k == 1 ? -az : k == 2 ? bz : -bz) * h;
        double tk = brute_ray(ox + sx, oy + sy, oz + sz, dx, dy, dz, 1);
        if ((tk < 0) != (t < 0)) return 0;
        if (t >= 0 && fabs(tk - t) * len > 0.05) return 0;
    }
    int n = b3x_cast_ray_closest(w, ox, oy, oz, dx, dy, dz);
    if (n == 1 && b3x_hit_shape(1) != mesh) n = 0;   /* past the pot, into the floor */
    if (t < 0)
    {
        if (n != 0) { (*bad)++; printf("  ray from %g,%g,%g along %g,%g,%g: the shim hit, the oracle missed\n", ox, oy, oz, dx, dy, dz); }
        return 1;
    }
    if (n != 1 || b3x_hit_shape(1) != mesh || fabs(b3x_hit_fraction(1) - t) * len > 5e-3)
    {
        (*bad)++;
        printf("  ray from %g,%g,%g along %g,%g,%g: the shim says %d hit(s) at %g, the oracle %g\n",
               ox, oy, oz, dx, dy, dz, n, n ? b3x_hit_fraction(1) : -1.0, t);
    }
    return 1;
}

/* The lowest and highest point of the model, scaled, as body b carries it:
 * every point through the body's own transform (position, then quaternion
 * x,y,z,w). A shape's AABB cannot answer this: Box3D keeps it loose. */
static void teapot_span_y(int b, double scale, double *lo, double *hi)
{
    double t[12];
    *lo = 1e30; *hi = -1e30;
    if (parse(b3x_body_transform(b), t, 12) != 7) return;
    double qx = t[3], qy = t[4], qz = t[5], qw = t[6];
    for (int i = 0; i < TEAPOT_POINT_COUNT; i++)
    {
        double x = scale * kTeapotPoints[i][0], y = scale * kTeapotPoints[i][1], z = scale * kTeapotPoints[i][2];
        /* row 2 of the rotation matrix of a unit quaternion */
        double wy = 2 * (qx * qy + qw * qz) * x + (1 - 2 * (qx * qx + qz * qz)) * y + 2 * (qy * qz - qw * qx) * z + t[1];
        if (wy < *lo) *lo = wy;
        if (wy > *hi) *hi = wy;
    }
}

static void test_model(void)
{
    double v[12];
    int w = b3x_world_create(0, -10, 0, 1);
    b3x_shape_options_set_events(1, 0, 0);
    int ground = b3x_body_create(w, 0, 0, -0.5, 0);
    b3x_shape_add_box(ground, 20, 0.5, 20, 0, 0.6, 0);

    /* 1. the teapot as a static triangle mesh, at the size it was modelled */
    int pot = b3x_body_create(w, 0, 0, 0, 0);
    teapot_geometry(1.0, 1);
    CHECK(b3x_geometry_point_count() == TEAPOT_POINT_COUNT, "every point of the model was taken (%d)", b3x_geometry_point_count());
    int mesh = b3x_shape_add_mesh(pot, 0.6, 0.0);
    CHECK(mesh > 0 && b3x_shape_type(mesh) == 4, "the teapot is a mesh shape %d: %s", mesh, b3x_last_error());
    CHECK(parse(b3x_shape_aabb(mesh), v, 12) == 6 && near(v[0], -3.0, 0.03) && near(v[3], 3.434, 0.03) && near(v[1], 0.0, 0.03) &&
              near(v[4], 3.15, 0.03) && near(v[2], -2.0, 0.03) && near(v[5], 2.0, 0.03),
          "its bounding box is the model's: '%s'", b3x_shape_aabb(mesh));

    /* 2. rays against the oracle: a grid straight down, a grid along x, a
     * grid along a slanted direction. The offsets keep origins off the
     * model's symmetry planes, where every ray would graze a seam. */
    int compared = 0, skipped = 0, bad = 0, hits = 0;
    for (int ix = 0; ix < 15; ix++)
        for (int iz = 0; iz < 9; iz++)
        {
            double x = -3.4 + 0.487 * ix + 0.0131, z = -2.1 + 0.527 * iz + 0.0173;
            if (teapot_ray_agrees(w, mesh, x, 6.0, z, 0, -5.9, 0, &bad)) { compared++; if (brute_ray(x, 6.0, z, 0, -5.9, 0, 1) >= 0) hits++; }
            else skipped++;
        }
    for (int iy = 0; iy < 12; iy++)
        for (int iz = 0; iz < 9; iz++)
        {
            double y = 0.07 + 0.263 * iy, z = -2.1 + 0.527 * iz + 0.0173;
            if (teapot_ray_agrees(w, mesh, -6.0, y, z, 12.0, 0, 0, &bad)) { compared++; if (brute_ray(-6.0, y, z, 12.0, 0, 0, 1) >= 0) hits++; }
            else skipped++;
            if (teapot_ray_agrees(w, mesh, 5.0, y + 3.0, z - 4.0, -9.0, -4.1, 7.3, &bad)) { compared++; if (brute_ray(5.0, y + 3.0, z - 4.0, -9.0, -4.1, 7.3, 1) >= 0) hits++; }
            else skipped++;
        }
    CHECK(bad == 0, "%d of %d rays at the teapot disagree with a ray-triangle test done here", bad, compared);
    CHECK(compared >= 250 && hits >= 100 && compared - hits >= 50, "the ray grid is a real test: %d compared (%d hits), %d grazing rays skipped", compared, hits, skipped);

    /* A mesh is ONE-SIDED, which is why the oracle above counts front faces
     * only. Said once by name: from inside the pot, straight up, there is
     * nothing but the backs of the lid's triangles, and the ray leaves. */
    CHECK(brute_ray(0.0131, 1.0, 0.0173, 0, 10.0, 0, 0) >= 0 && brute_ray(0.0131, 1.0, 0.0173, 0, 10.0, 0, 1) < 0,
          "the oracle sees the lid from inside only when it counts back faces");
    CHECK(b3x_cast_ray_closest(w, 0.0131, 1.0, 0.0173, 0, 10.0, 0) == 0, "a ray from inside the pot passes out through its back faces");

    /* 3. things land ON it. A ball over the lid's knob must touch the mesh
     * where the oracle says the surface is, not fall through to the floor. */
    double top = 6.0 - 5.9 * brute_ray(0.0131, 6.0, 0.0173, 0, -5.9, 0, 1);
    CHECK(near(top, 3.15, 0.05), "the knob is the top of the model: %g", top);
    int ball = b3x_body_create(w, 2, 0.0131, 4.5, 0.0173);
    int ballShape = b3x_shape_add_sphere(ball, 0, 0, 0, 0.15, 1.0, 0.6, 0.0);
    int touched = 0;
    double touchY = 0;
    for (int i = 0; i < 120 && !touched; i++)
    {
        b3x_world_step(w, 1.0 / 60.0, 4);
        b3x_world_update_contact_events(w);
        for (int k = 1; k <= b3x_contact_begin_count(); k++)
        {
            int a = b3x_contact_begin_shape_a(k), b = b3x_contact_begin_shape_b(k);
            if ((a == mesh && b == ballShape) || (a == ballShape && b == mesh)) { touched = 1; touchY = b3x_body_y(ball); }
        }
    }
    CHECK(touched && near(touchY, top + 0.15, 0.12), "a ball touches the knob at y %g (the surface is at %g, its radius 0.15)", touchY, top);

    /* a rain of small balls over the whole pot: none may end below the
     * floor's top or stop being a number, whatever it rolled off */
    int rain[40];
    for (int i = 0; i < 40; i++)
    {
        rain[i] = b3x_body_create(w, 2, -3.0 + 0.16 * i + 0.011, 5.0 + 0.35 * (i % 7), -1.7 + 0.43 * (i % 9));
        b3x_shape_add_sphere(rain[i], 0, 0, 0, 0.12, 1.0, 0.5, 0.1);
        /* a ball rolls for ever on a flat floor, and this one is 40 m wide */
        b3x_body_set_linear_damping(rain[i], 0.5);
        b3x_body_set_angular_damping(rain[i], 2.0);
    }
    for (int i = 0; i < 900; i++) b3x_world_step(w, 1.0 / 60.0, 4);
    int below = 0, onPot = 0;
    for (int i = 0; i < 40; i++)
    {
        double y = b3x_body_y(rain[i]);
        if (!b3x_body_is_valid(rain[i]) || !(y > 0.12 - 0.02)) { below++; printf("  ball %d valid %d at %s\n", i, b3x_body_is_valid(rain[i]), b3x_body_position(rain[i])); }
        if (y > 0.4) onPot++;
    }
    CHECK(below == 0, "%d of 40 balls rained on the teapot went through it or the floor", below);
    CHECK(b3x_unstable_count() == 0, "the rain left nothing for the net to remove");
    printf("  (%d of 40 balls came to rest on the teapot itself)\n", onPot);

    /* 4. the same points as a convex HULL on a dynamic body: a teapot that
     * falls. Box3D reduces a hull to a budget of points, so the box is held
     * to the model's within a few percent, not to the last digit. */
    const double s = 0.3;
    int falling[5];
    int hulls[5];
    for (int i = 0; i < 5; i++)
    {
        falling[i] = b3x_body_create(w, 2, 8.0 + 0.2 * i, 1.0 + 1.6 * i, 8.0);
        teapot_geometry(s, 0);
        hulls[i] = b3x_shape_add_hull(falling[i], 1.0, 0.6, 0.0);
    }
    CHECK(hulls[0] > 0 && b3x_shape_type(hulls[0]) == 3, "the teapot's points make a hull %d: %s", hulls[0], b3x_last_error());
    CHECK(parse(b3x_shape_aabb(hulls[0]), v, 12) == 6 && near(v[3] - v[0], 6.434 * s, 0.1) && near(v[4] - v[1], 3.15 * s, 0.06) && near(v[5] - v[2], 4.0 * s, 0.06),
          "the hull is the size of the model: '%s'", b3x_shape_aabb(hulls[0]));
    /* a hull holds more than the pot (it fills the gap under the handle and
     * the spout) and less than its bounding box */
    double potVolume = 25.77 * s * s * s, boxVolume = 6.434 * 3.15 * 4.0 * s * s * s;
    CHECK(b3x_body_mass(falling[0]) > potVolume && b3x_body_mass(falling[0]) < boxVolume,
          "hull mass %g lies between the pot's volume %g and its box's %g", b3x_body_mass(falling[0]), potVolume, boxVolume);
    int steps = 0;
    while (steps < 1800)
    {
        b3x_world_step(w, 1.0 / 60.0, 4);
        steps++;
        int awake = 0;
        for (int i = 0; i < 5; i++) awake += b3x_body_is_awake(falling[i]);
        if (awake == 0) break;
    }
    int rested = 0;
    for (int i = 0; i < 5; i++)
    {
        double lo, hi;
        teapot_span_y(falling[i], s, &lo, &hi);
        /* On the floor: the lowest point of the MODEL may dip a few
         * centimetres under the floor's top, because what collides is the
         * simplified hull, and it lies just inside the model (measured:
         * up to 0.03 at this scale). Sunk or fallen through is far more. */
        if (hulls[i] > 0 && b3x_body_is_awake(falling[i]) == 0 && lo > -0.06 && hi < 4.0) rested++;
        else printf("  teapot %d: awake %d, its points span y %g to %g\n", i, b3x_body_is_awake(falling[i]), lo, hi);
        if (i == 0) CHECK(near(lo, 0.0, 0.06), "the first teapot sits on the floor: its lowest point is at y %g", lo);
    }
    CHECK(rested == 5, "%d of 5 falling teapots came to rest above the floor within %d steps", rested, steps);
    CHECK(b3x_unstable_count() == 0 && b3x_last_error()[0] == 0, "no body was removed and no call refused: '%s'", b3x_last_error());

    /* 5. the mesh is owned by its shape: destroy the pot, and a ray that
     * hit it finds only the floor */
    b3x_body_destroy(pot);
    CHECK(b3x_shape_is_valid(mesh) == 0, "the mesh went with its body");
    CHECK(b3x_cast_ray_closest(w, 1.0131, 6.0, 0.5173, 0, -7.0, 0) == 1 && b3x_hit_body(1) == ground, "a ray through where the pot stood reaches the floor");
    b3x_world_destroy(w);
}

/* ------------------------------------------------------------------ */
/* What b3x_last_error promises, pinned after the first IDE run (2026-11-20)
 * read the docs as promising more: a refused CREATE sets it, dead handle
 * included; a create that works clears it; a getter or an action handed a
 * dead handle is silent and leaves it as it was. */
static void test_last_error(void)
{
    int w = b3x_world_create(0, -10, 0, 1);
    int b = b3x_body_create(w, 2, 0, 1, 0);
    CHECK(b > 0 && b3x_last_error()[0] == 0, "a create that works leaves no error");
    CHECK(b3x_shape_add_sphere(b, 0, 0, 0, 0.0, 1, 0.5, 0) == 0 && b3x_last_error()[0] != 0, "a refused create says why: %s", b3x_last_error());
    char kept[160];
    snprintf(kept, sizeof kept, "%s", b3x_last_error());
    b3x_body_destroy(b);
    CHECK(b3x_body_position(b)[0] == 0 && b3x_body_y(b) == 0.0 && strcmp(b3x_last_error(), kept) == 0, "a getter on a dead body is silent: '%s'", b3x_last_error());
    b3x_body_set_position(b, 1, 2, 3);
    b3x_world_step(0, 1.0 / 60.0, 4);
    CHECK(strcmp(b3x_last_error(), kept) == 0, "an action on a dead handle is silent: '%s'", b3x_last_error());
    CHECK(b3x_shape_add_sphere(b, 0, 0, 0, 0.5, 1, 0.5, 0) == 0 && strcmp(b3x_last_error(), "not a body") == 0, "a create on a dead body says so: '%s'", b3x_last_error());
    CHECK(b3x_body_create(0, 2, 0, 0, 0) == 0 && strcmp(b3x_last_error(), "not a world") == 0, "a create in no world says so: '%s'", b3x_last_error());
    int again = b3x_body_create(w, 2, 0, 1, 0);
    CHECK(again > 0 && b3x_last_error()[0] == 0, "the next create that works clears it");
    b3x_world_destroy(w);
}

int main(void)
{
    test_library();
    test_falling_and_resting();
    test_body_api();
    test_shapes();
    test_queries();
    test_events();
    test_joints();
    test_quaternions();
    test_locale();
    test_stress();
    test_model();
    test_last_error();
    CHECK(b3x_text_length("") == 0 && b3x_text_length(NULL) == 0 && b3x_text_length(b3x_library_version()) == (int)strlen(b3x_library_version()),
          "the text length the binding copies by");
    int assertsElsewhere = b3x_assert_count();
    test_stale_sleep();
    test_net();
    /* In a build with Box3D's asserts on (Debug: the sanitizer lane), nothing
     * above may have tripped one: the scenes are sane and every refusal is
     * meant to stop in the shim, before Box3D sees the value. In a Release
     * build the asserts are compiled out and this reads 0 by construction. */
    CHECK(assertsElsewhere == 0, "%d Box3D assert(s) failed outside the net test; the last: %s", assertsElsewhere, b3x_assert_text());
    CHECK(b3x_assert_count() == assertsElsewhere + s_netAsserts, "the assert count adds up");
    CHECK(b3x_assert_count() != 0 || b3x_assert_text()[0] == 0, "no assert, no assert text");
    printf("box3dxt smoke test: %d passed, %d failed\n", s_pass, s_fail);
    return s_fail == 0 ? 0 : 1;
}
