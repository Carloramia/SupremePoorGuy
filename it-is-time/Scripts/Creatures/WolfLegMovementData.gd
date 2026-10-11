extends "res://Scripts/Creatures/LegMovementData.gd"

@export_group("Wolf Heading Correction")
@export var world_rotation_constraints_enabled: bool = false
@export var limb_plane_stabilization_enabled: bool = true
@export_range(0.0, 1000.0, 1.0) var limb_plane_strength: float = 100.0
@export_range(0.0, 100.0, 0.5) var limb_plane_damping: float = 20.0
@export_range(0.0, 1000.0, 1.0) var limb_plane_maximum_acceleration: float = 80.0
## Torque cap at overall_scale=1; scales with rotational inertia (scale^5).
@export_range(0.0, 10000.0, 1.0) var limb_plane_maximum_torque: float = 200.0
@export_range(0.1, 10.0, 0.1) var foot_plane_lock_degrees: float = 1.5
@export_range(1.0, 30.0, 0.5) var foot_plane_unlock_degrees: float = 6.0
@export_range(0.0, 1.0, 0.01) var foot_plane_lock_confirmation: float = 0.15
@export_range(0.0, 1.0, 0.01) var foot_plane_unlock_confirmation: float = 0.12
@export_range(5.0, 90.0, 1.0) var deliberate_turn_entry_degrees: float = 30.0
@export_range(1.0, 45.0, 1.0) var deliberate_turn_exit_degrees: float = 10.0
@export_range(0.1, 10.0, 0.1) var heading_correction_gain: float = 2.0
@export_range(0.1, 20.0, 0.1) var heading_correction_damping: float = 4.0
@export_range(1.0, 45.0, 1.0) var heading_correction_speed_degrees: float = 10.0
@export_range(1.0, 180.0, 1.0) var heading_correction_acceleration_degrees: float = 30.0

func calculate_heading_correction(error: float, actual_rate: float, limit_rate: float) -> Dictionary:
	var acceleration_limit := deg_to_rad(heading_correction_acceleration_degrees)
	var rate_limit := minf(maxf(limit_rate, 0.0), deg_to_rad(heading_correction_speed_degrees))
	rate_limit = minf(rate_limit, sqrt(2.0 * acceleration_limit * absf(error)))
	var requested := clampf(error * heading_correction_gain, -rate_limit, rate_limit)
	return {"mode": "heading_correction", "requested_rate": requested, "acceleration": clampf((requested - actual_rate) * heading_correction_damping, -acceleration_limit, acceleration_limit)}

@export_group("Wolf Step Stability")
@export_range(0.15, 1.0, 0.01) var minimum_safe_swing_time: float = 0.35
@export_range(10.0, 300.0, 1.0) var maximum_tracking_acceleration: float = 120.0
@export_range(20.0, 300.0, 1.0) var maximum_tracking_gain: float = 120.0
@export_range(0.02, 0.3, 0.01) var contact_brake_time: float = 0.08
@export_range(10.0, 200.0, 1.0) var maximum_contact_brake_acceleration: float = 60.0
@export_range(0.0, 0.3, 0.01) var distance_lift_ratio: float = 0.08
@export_range(0.05, 0.3, 0.01) var maximum_lift_length_ratio: float = 0.15
@export_range(0.02, 0.5, 0.01) var touchdown_target_tolerance_ratio: float = 0.15
@export_range(0.0, 60.0, 1.0) var liftoff_assist_acceleration: float = 20.0
## Upward tracking is allocated before horizontal pursuit, within the total force cap.
@export_range(20.0, 300.0, 1.0) var vertical_tracking_gain: float = 120.0
@export_range(0.1, 1.0, 0.05) var minimum_recovery_stride_ratio: float = 0.4
@export_range(0.0, 0.5, 0.05) var recovery_stride_reduction: float = 0.2
@export_range(0.0, 0.5, 0.05) var recovery_time_increase: float = 0.15
@export_range(0.0, 3.0, 0.05) var maximum_catch_up_extension: float = 1.0
@export_range(0.05, 2.0, 0.05) var touchdown_descent_speed: float = 0.35
@export_range(0.0, 0.1, 0.005) var touchdown_press_depth: float = 0.03
@export_range(0.0, 0.08, 0.005) var wolf_touchdown_pin_initial_slack: float = 0.005
@export_range(0.0, 0.2, 0.01) var wolf_touchdown_pin_transition_time: float = 0.02

@export_group("Wolf Automatic Gallop")
@export var automatic_gallop_enabled: bool = true
@export_range(0.01, 0.5, 0.01) var gallop_entry_speed_deficit: float = 0.05
@export_range(0.0, 0.5, 0.01) var gallop_exit_speed_deficit: float = 0.02
@export_range(0.0, 2.0, 0.05) var gallop_entry_confirmation: float = 0.2
@export_range(0.0, 3.0, 0.05) var gallop_exit_confirmation: float = 0.6
@export_range(0.0, 1.0, 0.05) var minimum_automatic_gallop_intensity: float = 0.25
## Temporarily release the support budget when a planted leg is holding the body back.
@export var traction_gallop_enabled: bool = true
@export_range(0.1, 3.0, 0.05) var traction_gallop_hold_time: float = 0.8
@export_range(0.0, 1.0, 0.05) var traction_gallop_intensity: float = 0.5

func recovery_stride_scale(attempts: int) -> float:
	return maxf(minimum_recovery_stride_ratio, pow(1.0 - recovery_stride_reduction, maxi(attempts, 0)))

func allocate_tracking_force(requested: Vector3, up: Vector3, limit: float) -> Dictionary:
	var vertical := clampf(requested.dot(up), -limit, limit)
	var horizontal_limit := sqrt(maxf(limit * limit - vertical * vertical, 0.0))
	var horizontal := requested.slide(up).limit_length(horizontal_limit)
	return {"force": up * vertical + horizontal, "vertical_force": vertical, "horizontal_limit": horizontal_limit}

func catch_up_deadline(elapsed: float, duration: float, distance: float, relative_speed: float, previous: float) -> float:
	var reserve := maxf(safe_swing_time(distance, 0.0, 0.0), distance / maxf(relative_speed, 0.5))
	return minf(duration * 2.0 + maximum_catch_up_extension, maxf(previous, elapsed + reserve))

func safe_swing_time(distance: float, height: float, nominal: float) -> float:
	# Hinge resistance and solver delay need margin over the ideal acceleration envelope.
	return maxf(maxf(nominal, minimum_safe_swing_time), sqrt(8.0 * maxf(distance, height) / maxf(maximum_tracking_acceleration - 9.8, 1.0)) * 1.2)

func stabilize_profile(original: Dictionary, stance_distance: float, foot_count: int, observed: float) -> Dictionary:
	var profile := original.duplicate()
	var stride := minf(float(profile.stride), maxf(stance_distance, 0.01))
	var swing := safe_swing_time(stride, float(profile.lift), float(profile.swing_duration))
	var occupied := maxf(swing + 0.12 + contact_brake_time + 0.04, observed * 1.1)
	var capacity := maxi(int(profile.support_capacity), 1)
	var cycle := maxf(float(profile.cycle), foot_count * occupied / capacity)
	var stance_time := maxf(cycle - occupied, 0.01)
	# Only the planted part of the cycle consumes the structural stance interval.
	profile.reachable_speed = minf(target_speed, stance_distance / stance_time)
	profile.speed_limited = float(profile.reachable_speed) + 0.001 < target_speed
	profile.limiting_reason = "wolf_safe_step_and_support_budget" if profile.speed_limited else "none"
	profile.stride = stride
	profile.cycle = cycle
	profile.frequency = 1.0 / cycle
	profile.total_frequency = foot_count / cycle
	profile.swing_duration = swing
	profile.position_gain = minf(16.0 / (swing * swing), maximum_tracking_gain)
	profile.velocity_gain = 2.0 * sqrt(float(profile.position_gain))
	profile.step_acceleration = maximum_tracking_acceleration
	profile.landing_timeout = maxf(0.5, swing)
	profile["wolf_occupied_duration"] = occupied
	profile["wolf_observed_duration"] = observed
	profile["wolf_stance_distance"] = stance_distance
	profile["wolf_stance_duration"] = stance_time
	return profile

@export_group("Automatic Motion")
## Wolf only: maximum forward/backward foot distance from its SubTorso projection,
## expressed as a fraction of this leg's initial chain length.
@export_range(0.01, 1.0, 0.01) var maximum_foot_extension_ratio: float = 0.25
## World units along the requested travel direction; positive moves forelegs forward.
@export_range(0.0, 10.0, 0.01, "or_greater") var foreleg_stride_forward_offset: float = 0.2
## World units opposite the requested travel direction; positive moves hind legs backward.
@export_range(0.0, 10.0, 0.01, "or_greater") var hindleg_stride_backward_offset: float = 0.2

@export_group("Wolf Traction Recovery")
@export var traction_recovery_enabled: bool = true
## Estimated resisting force as a fraction of the supported weight, not measured joint force.
@export_range(0.01, 1.0, 0.01) var traction_weight_threshold: float = 0.08
@export_range(0.01, 1.0, 0.01) var traction_confirmation_time: float = 0.18
@export_range(0.01, 1.0, 0.01) var traction_step_cooldown: float = 0.25
