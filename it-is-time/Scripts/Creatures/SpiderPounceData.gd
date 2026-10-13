@tool
extends "res://Scripts/Creatures/CreatureAttackData.gd"

@export var input_action: StringName = &"MouseLeft"
@export_group("Preparation")
@export_range(0.0, 2.0, 0.01) var pause_time := 0.15
@export_range(0.05, 3.0, 0.01) var rise_time := 0.5
@export_range(0.0, 0.5, 0.01) var preparation_pose_max_wait := 0.5
@export_range(0.0, 20.0, 0.5) var preparation_angle_tolerance_degrees := 5.0
@export_range(0.0, 0.2, 0.005) var preparation_position_tolerance_ratio := 0.04
@export_range(0.0, 30.0, 0.5) var front_pitch_degrees := 30.0
## Interior angle at the knee, measured toward the root and toward the toe.
@export_range(0.0, 180.0, 0.5) var front_leg_relative_angle_degrees := 150.0
@export_group("Leap")
## Distances follow the real Torso assembly; times follow sqrt(body scale).
@export_range(0.1, 20.0, 0.01) var reference_body_length := 3.28
@export_range(0.0, 5.0, 0.05) var minimum_distance_body_ratio := 0.5
@export_range(0.1, 10.0, 0.05) var maximum_distance_body_ratio := 6.0
@export_range(0.1, 5.0, 0.05) var preferred_distance_body_ratio := 1.8
@export_range(0.2, 2.0, 0.01) var flight_time := 1.2
@export_range(1.0, 50.0, 0.1) var maximum_launch_speed := 30.0
@export_range(0.0, 0.5, 0.01) var landing_standoff_body_ratio := 0.2
@export_range(0.0, 1.0, 0.01) var forward_sweep_ratio := 0.25
@export_range(0.1, 2.0, 0.01) var landing_timeout := 0.8
@export_group("Physical Tracking")
@export_range(1.0, 300.0, 1.0) var position_gain := 70.0
@export_range(1.0, 300.0, 1.0) var maximum_acceleration := 80.0
@export_range(1.0, 300.0, 1.0) var attitude_gain := 80.0
@export_range(0.05, 2.0, 0.01) var recovery_time := 0.35
@export_group("Damage")
@export_range(0.01, 20.0, 0.05) var impulse_multiplier := 4.0
@export_range(1.0, 2.0, 0.05) var hitbox_padding := 1.1

func _default_cooldown() -> float: return 2.0

func is_valid() -> bool:
	for value: float in [cooldown, pause_time, rise_time, preparation_pose_max_wait, preparation_angle_tolerance_degrees, preparation_position_tolerance_ratio, front_pitch_degrees, front_leg_relative_angle_degrees, reference_body_length, minimum_distance_body_ratio, maximum_distance_body_ratio, preferred_distance_body_ratio, flight_time, maximum_launch_speed, landing_standoff_body_ratio, forward_sweep_ratio, landing_timeout, position_gain, maximum_acceleration, attitude_gain, recovery_time, impulse_multiplier, hitbox_padding]:
		if not is_finite(value) or value < 0.0: return false
	return preparation_pose_max_wait <= 0.5 and front_leg_relative_angle_degrees <= 180.0 and reference_body_length > 0.0 and rise_time > 0.0 and maximum_distance_body_ratio > minimum_distance_body_ratio and flight_time > 0.0 and maximum_launch_speed > 0.0 and position_gain > 0.0 and maximum_acceleration > 0.0 and attitude_gain > 0.0 and recovery_time > 0.0 and hitbox_padding >= 1.0
