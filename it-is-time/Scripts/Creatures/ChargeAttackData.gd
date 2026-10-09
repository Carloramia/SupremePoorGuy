class_name ChargeAttackData
extends Resource
@export var enabled: bool = true
@export_range(0.01, 5.0, 0.01) var z_tolerance: float = 0.3
@export_range(0.1, 30.0, 0.1) var starting_speed: float = 2.0
@export_range(0.1, 60.0, 0.1) var maximum_speed: float = 12.0
@export_range(0.1, 60.0, 0.1) var acceleration: float = 5.0
@export_range(0.1, 60.0, 0.1) var deceleration: float = 8.0
@export_range(0.1, 60.0, 0.1) var velocity_gain: float = 6.0
@export_range(0.1, 100.0, 0.1) var maximum_acceleration: float = 25.0
## Budget acceleration against all intact, moving character parts.
@export var use_total_load_mass: bool = true
@export var compensate_linear_damping: bool = true
@export_group("Charge Head Posture")
@export var lower_head_enabled: bool = true
## Positive magnitude tilts local +X downward around the Torso's local +Z.
@export_range(0.0, 60.0, 1.0) var head_lower_angle_degrees: float = 15.0
@export_range(0.05, 2.0, 0.05) var head_lower_transition_time: float = 0.3
@export_group("Charge Touchdown")
## Ground braking is separate from end-of-charge deceleration.
@export_range(0.04, 0.5, 0.01) var touchdown_stop_time: float = 0.12
## Apply ground braking briefly; completing a step does not require stopping.
@export_range(0.0, 0.5, 0.01) var touchdown_brake_duration: float = 0.12
## Extra braking budget for joint traction and discrete physics updates.
@export_range(1.0, 3.0, 0.05) var touchdown_brake_margin: float = 1.25
@export_range(10.0, 2000.0, 10.0, "or_greater") var touchdown_maximum_acceleration: float = 600.0
@export_group("")
@export_range(0.0, 5.0, 0.1) var pass_margin: float = 0.5
@export_range(0.1, 30.0, 0.1) var alignment_timeout: float = 8.0
## Extra timeout slack added to estimated travel time, not a fixed distance cap.
@export_range(0.1, 30.0, 0.1) var maximum_charge_time: float = 8.0
@export_range(0.1, 10.0, 0.1) var maximum_braking_time: float = 3.0
@export_range(0.1, 10.0, 0.1) var stuck_timeout: float = 1.0
## Allow all feet to step using a bounded flight lease from real ground contact.
@export var allow_all_feet_airborne: bool = true
@export_range(0.0, 3.0, 0.1) var airborne_timeout: float = 0.5
@export_range(0.0, 20.0, 0.1) var cooldown: float = 5.0
@export_range(0.1, 3.0, 0.05) var weapon_length_ratio: float = 0.8
@export_range(0.1, 2.0, 0.05) var weapon_radius_ratio: float = 0.45
@export_flags_3d_physics var obstacle_mask: int = 1
@export_range(0.01, 5.0, 0.01) var navigation_endpoint_tolerance: float = 0.2
@export_range(0.1, 10.0, 0.1) var navigation_projection_tolerance: float = 2.0
func is_valid() -> bool:
	for value: float in [head_lower_angle_degrees,head_lower_transition_time,touchdown_brake_margin,touchdown_brake_duration,touchdown_stop_time,touchdown_maximum_acceleration,z_tolerance,starting_speed,maximum_speed,acceleration,deceleration,velocity_gain,maximum_acceleration,pass_margin,alignment_timeout,maximum_charge_time,maximum_braking_time,stuck_timeout,airborne_timeout,cooldown,weapon_length_ratio,weapon_radius_ratio,navigation_endpoint_tolerance,navigation_projection_tolerance]:
		if not is_finite(value) or value < 0.0: return false
	if head_lower_angle_degrees > 60.0 or head_lower_transition_time < 0.05: return false
	return touchdown_brake_margin >= 1.0 and touchdown_stop_time >= 0.04 and touchdown_maximum_acceleration > 0.0 and maximum_speed >= starting_speed and starting_speed > 0.0 and acceleration > 0.0 and deceleration > 0.0 and velocity_gain > 0.0 and maximum_acceleration > 0.0 and alignment_timeout > 0.0 and maximum_charge_time > 0.0 and maximum_braking_time > 0.0 and stuck_timeout > 0.0 and z_tolerance > 0.0 and weapon_length_ratio > 0.0 and weapon_radius_ratio > 0.0 and navigation_endpoint_tolerance > 0.0 and navigation_projection_tolerance > 0.0

func get_minimum_distance() -> float:
	return maxf(maximum_speed * maximum_speed - starting_speed * starting_speed, 0.0) / (2.0 * maxf(acceleration, 0.000001))

func get_travel_time(distance: float) -> float:
	var ramp_distance := get_minimum_distance()
	if distance <= ramp_distance:
		return (sqrt(starting_speed * starting_speed + 2.0 * acceleration * maxf(distance, 0.0)) - starting_speed) / acceleration
	return (maximum_speed - starting_speed) / acceleration + (distance - ramp_distance) / maximum_speed
