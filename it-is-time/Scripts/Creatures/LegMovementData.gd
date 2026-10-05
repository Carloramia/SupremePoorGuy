class_name LegMovementData
extends Resource
## Shared configuration only; all per-character timers and states stay in the controller.
@export_group("Automatic Motion")
## Derive gait and drive gains from speed, turning speed and cadence cap; manual groups are fallback settings.
@export var automatic_motion: bool = false
## Generated gait: target speed and total cadence determine cycle displacement;
## measured Torso speed and leg reach determine flight, capacity and touchdown braking.
## With Gallop enabled, manual Gallop numbers are fallback values for legacy gait.
@export var speed_based_gait: bool = true
@export_range(0.0, 30.0, 0.05, "or_greater") var target_speed: float = 1.5
## Desired whole-character turn rate, degrees per second; physical support can reduce it.
@export_range(0.0, 180.0, 0.5, "or_greater") var turning_speed_degrees: float = 10.0
## Reference total step frequency for generated automatic speed-based walking.
## It plans duration/stride, but reach-limit events decide when feet actually start.
## Other controllers and pure turning retain the frequency admission limit. Zero is unlimited.
@export_range(0.0, 60.0, 0.1, "or_greater") var maximum_step_frequency: float = 6.0

@export_group("Gallop")
## Generated creatures can use bounded airborne assistance when walking cannot meet target_speed.
@export var gallop_enabled: bool = false
@export_range(0.0, 1.0, 0.05) var gallop_maximum_stepping_ratio: float = 0.75
@export_range(0, 10, 1) var gallop_minimum_support_feet: int = 0
## Permit zero stance feet during a recent-ground window, unless minimum_support_feet is positive.
@export var gallop_allow_all_feet_airborne: bool = true
## Feet in one launch group; every start is charged against the total cadence budget.
@export_range(1, 10, 1) var gallop_step_group_size: int = 2
## Confirm slow terrain contact before restoring a fixed stance.
@export_range(0.01, 0.5, 0.01) var gallop_landing_confirmation: float = 0.06
## Follow only during early swing, with a bounded correction in addition to prediction.
@export_range(0.1, 0.9, 0.01) var gallop_target_freeze_progress: float = 0.55
@export_range(0.0, 0.5, 0.01) var gallop_target_follow_length_ratio: float = 0.10
## Tangential speed must fall below this before touchdown becomes a fixed stance.
@export_range(0.05, 2.0, 0.05) var gallop_touchdown_speed_limit: float = 0.35
## Ground-authorized takeoff pulse, at most once per half gait cycle. Zero disables hopping.
@export_range(0.0, 2.0, 0.05) var gallop_takeoff_velocity: float = 1.6
@export_range(0.05, 0.5, 0.01) var gallop_airborne_duration: float = 0.22
## Hard ceiling for speed-gait contact memory, including landing confirmation.
@export_range(0.05, 1.5, 0.01) var gallop_maximum_airborne_duration: float = 0.85
@export_range(0.0, 1.0, 0.01) var gallop_airborne_drive_ratio: float = 0.65
## Fraction of segment weight, never full gravity cancellation in air.
@export_range(0.0, 0.9, 0.01) var gallop_airborne_support_ratio: float = 0.45
@export_range(0.0, 1.0, 0.01) var gallop_landing_prediction_ratio: float = 0.5

@export_group("Stride")
@export var use_limb_length_ratios: bool = false
@export_range(0.01, 20.0, 0.01, "or_greater") var step_distance: float = 0.35
@export_range(0.01, 1.0, 0.01) var stride_length_ratio: float = 0.12
@export_range(0.0, 10.0, 0.01, "or_greater") var step_height: float = 0.25
@export_range(0.0, 1.0, 0.01) var lift_length_ratio: float = 0.1
@export_group("Timing")
## Total step starts per second, not cycles per foot. Support and landing may reduce actual frequency.
@export_range(0.1, 30.0, 0.1) var step_frequency: float = 2.0
@export_range(0.01, 5.0, 0.01) var swing_duration: float = 0.35
@export_group("Support")
@export_range(0.0, 1.0, 0.01) var maximum_stepping_ratio: float = 0.5
## Zero removes the additional absolute cap. One preserves sequential walking.
@export_range(0, 10, 1) var maximum_simultaneous_steps: int = 1
@export_range(0, 10, 1) var minimum_support_feet: int = 1
@export_group("Landing")
@export_range(0.001, 1.0, 0.001) var landing_tolerance: float = 0.18
@export_range(0.01, 5.0, 0.01) var landing_timeout: float = 1.0

func is_valid() -> bool:
	if not is_finite(maximum_stepping_ratio) or maximum_stepping_ratio < 0.0 or maximum_stepping_ratio > 1.0 or maximum_simultaneous_steps < 0 or minimum_support_feet < 0: return false
	for value: float in [gallop_target_freeze_progress, gallop_target_follow_length_ratio, gallop_touchdown_speed_limit, gallop_maximum_stepping_ratio, gallop_landing_confirmation, gallop_takeoff_velocity, gallop_airborne_duration, gallop_airborne_drive_ratio, gallop_airborne_support_ratio, gallop_landing_prediction_ratio]:
		if not is_finite(value): return false
	if gallop_maximum_stepping_ratio < 0.0 or gallop_maximum_stepping_ratio > 1.0 or gallop_minimum_support_feet < 0 or gallop_step_group_size < 1 or gallop_landing_confirmation <= 0.0 or gallop_landing_confirmation > 0.5: return false
	if gallop_target_freeze_progress < 0.1 or gallop_target_freeze_progress > 0.9 or gallop_target_follow_length_ratio < 0.0 or gallop_target_follow_length_ratio > 0.5 or gallop_touchdown_speed_limit < 0.05 or gallop_touchdown_speed_limit > 2.0: return false
	if not is_finite(gallop_maximum_airborne_duration) or gallop_maximum_airborne_duration < gallop_airborne_duration or gallop_maximum_airborne_duration > 1.5: return false
	if gallop_takeoff_velocity < 0.0 or gallop_takeoff_velocity > 2.0: return false
	if gallop_airborne_duration <= 0.0 or gallop_airborne_duration > 0.5 or gallop_airborne_drive_ratio < 0.0 or gallop_airborne_drive_ratio > 1.0 or gallop_airborne_support_ratio < 0.0 or gallop_airborne_support_ratio > 0.9 or gallop_landing_prediction_ratio < 0.0 or gallop_landing_prediction_ratio > 1.0: return false
	if automatic_motion:
		return is_finite(target_speed) and target_speed >= 0.0 and is_finite(turning_speed_degrees) and turning_speed_degrees >= 0.0 and is_finite(maximum_step_frequency) and maximum_step_frequency >= 0.0
	for value: float in [step_distance, step_frequency, swing_duration, landing_tolerance, landing_timeout]:
		if not is_finite(value) or value <= 0.0: return false
	for value: float in [stride_length_ratio, step_height, lift_length_ratio, maximum_stepping_ratio]:
		if not is_finite(value) or value < 0.0: return false
	return maximum_stepping_ratio <= 1.0 and maximum_simultaneous_steps >= 0 and minimum_support_feet >= 0

func calculate_support_capacity(foot_count: int) -> int:
	var capacity := mini(floori(foot_count * maximum_stepping_ratio), maxi(0, foot_count - maxi(minimum_support_feet, 1)))
	if maximum_simultaneous_steps > 0: capacity = mini(capacity, maximum_simultaneous_steps)
	return maxi(capacity, 0)

func calculate_gallop_capacity(foot_count: int, airborne_window: bool = false) -> int:
	var reserved := maxi(gallop_minimum_support_feet,0 if gallop_allow_all_feet_airborne else 1)
	var available := maxi(foot_count-reserved,0)
	if airborne_window and gallop_allow_all_feet_airborne: return available
	return mini(ceili(foot_count*gallop_maximum_stepping_ratio),available)

## Pure calculation: never mutate shared resources for a particular creature.
func calculate_motion_profile(length: float, radius: float, foot_count: int, shared_length: float = -1.0) -> Dictionary:
	length = maxf(length, 0.1)
	radius = maxf(radius, length * 0.25)
	var count := maxi(foot_count, 1)
	var support_capacity := calculate_support_capacity(foot_count)
	# All feet share a stride/cycle selected using the shortest supporting chain.
	var reference := minf(length, shared_length) if shared_length > 0.0 else length
	var maximum_stride := reference * 0.5
	var preferred_stride := reference * 0.4
	var minimum_swing := 0.06
	var landing_reserve := 0.02
	var cycle := preferred_stride / maxf(target_speed, 0.01)
	if maximum_step_frequency > 0.0: cycle = maxf(cycle, count / maximum_step_frequency)
	cycle = maxf(cycle, count * (minimum_swing + landing_reserve) / maxf(support_capacity, 1.0))
	var stride := minf(target_speed * cycle, maximum_stride)
	var effective_speed := stride / cycle if support_capacity > 0 else 0.0
	# Leave 20% of concurrent occupancy for contact confirmation and scheduling jitter.
	var available := cycle * float(support_capacity) / count
	var swing := clampf(minf(available * 0.8, available - landing_reserve), minimum_swing, 0.35)
	var lift := clampf(reference * 0.035 + stride * 0.04, 0.03, reference * 0.10)
	var gain := clampf(16.0 / (swing * swing), 20.0, 4000.0)
	var required_acceleration := 8.0 * maxf(stride, lift) / (swing * swing) + 9.8
	var acceleration := clampf(required_acceleration, 30.0, 2000.0)
	var omega := deg_to_rad(turning_speed_degrees)
	var angle := minf(20.0, rad_to_deg(length * 0.15 / radius))
	angle = clampf(minf(angle, turning_speed_degrees * 0.25 * maxi(foot_count, 1)), 2.0, 20.0)
	if maximum_step_frequency > 0.0:
		angle = clampf(turning_speed_degrees / maximum_step_frequency, angle, 20.0)
	var turn_duration := clampf(angle / maxf(turning_speed_degrees * maxi(foot_count, 1), 0.01), 0.12, 0.6)
	return {"length": length, "radius": radius, "target_speed": target_speed, "turning_speed_degrees": turning_speed_degrees, "maximum_step_frequency": maximum_step_frequency,
		"reachable_speed": effective_speed, "speed_limited": effective_speed + 0.001 < target_speed, "planning_reference_length": reference, "maximum_stride": maximum_stride, "support_capacity": support_capacity, "landing_reserve": landing_reserve, "total_frequency": count / cycle if target_speed > 0.0 and support_capacity > 0 else 0.0, "limiting_reason": "cadence_or_stride_limit" if effective_speed + 0.001 < target_speed else "none", "stride": stride, "cycle": cycle, "frequency": 1.0 / cycle if target_speed > 0.0 and support_capacity > 0 else 0.0, "swing_duration": swing, "lift": lift,
		"landing_tolerance": clampf(length * 0.015, 0.03, 0.15), "landing_timeout": maxf(0.2, swing * 2.0),
		"position_gain": gain, "velocity_gain": 2.0 * sqrt(gain),
		"step_acceleration": acceleration, "required_step_acceleration": required_acceleration, "drive_acceleration_limited": required_acceleration > acceleration,
		"contact_gain": clampf(2.0 + target_speed, 2.0, 12.0), "contact_acceleration": clampf(target_speed * 2.0, 2.0, 12.0),
		"turn_step_angle": angle, "turn_step_duration": turn_duration, "turn_lift": lift,
		"turn_lead": angle, "turn_timeout": maxf(30.0, 720.0 / maxf(turning_speed_degrees, 1.0)),
		"turn_gain": clampf(16.0 * omega / maxf(deg_to_rad(30.0), 0.01), 4.0, 64.0),
		"turn_damping": 2.0 * sqrt(clampf(16.0 * omega / maxf(deg_to_rad(30.0), 0.01), 4.0, 64.0)),
		"turn_acceleration": clampf(radius * omega * 4.0, 2.0, 20.0),
		"turn_traction_gain": clampf(4.0 + omega * 8.0, 4.0, 20.0), "turn_traction_damping": 4.0,
		"replan_cooldown": minf(swing * 0.5, 0.15)}

## Pure per-foot timing; required stride is world displacement between touchdowns,
## not an extension of a leg. Runtime terrain checks still constrain every landing.
func calculate_speed_gait_profile(length: float, foot_count: int, actual_speed: float, support_distance: float, capacity: int) -> Dictionary:
	if foot_count <= 0 or capacity <= 0 or target_speed <= 0.0: return {"enabled": false}
	var count := maxi(foot_count,1)
	var desired_frequency := count * target_speed / maxf(length*0.4,0.05)
	var frequency := minf(desired_frequency,maximum_step_frequency) if maximum_step_frequency > 0.0 else desired_frequency
	var cadence_frequency := frequency
	frequency = minf(frequency,float(capacity)/(0.15+gallop_landing_confirmation))
	if frequency <= 0.001: return {"enabled": false}
	var cycle := count / frequency
	var confirmation := gallop_landing_confirmation
	var minimum_air := 0.15
	var maximum_air := maxf(minimum_air,cycle * clampf(float(capacity)/count,0.0,1.0) - confirmation)
	# Starting from rest uses a small target-derived planning floor. Actual speed
	# remains separately reported; this avoids division by zero and zero-time swings.
	var planning_speed := maxf(actual_speed,maxf(target_speed*0.25,0.05))
	var stance := maxf(support_distance,0.0) / planning_speed
	var air := clampf(cycle-stance-confirmation,minimum_air,maximum_air)
	return {"enabled": true,"total_frequency": frequency,"cycle": cycle,"required_stride": target_speed*cycle,
		"frequency_limited_by_occupancy": frequency+0.001 < cadence_frequency,"actual_speed": actual_speed,"planning_speed": planning_speed,"support_distance": support_distance,
		"raw_stance_time": stance,"stance_duration": maxf(cycle-air-confirmation,0.0),"air_duration": air,
		"landing_reserve": confirmation,"air_duration_limited": cycle-stance-confirmation > maximum_air,
		"walking_stride_limit": length*0.5,"requires_flight": target_speed*cycle > length*0.5}

## Automatic flight budget uses only speed/cadence, measured geometry and velocity.
## capacity is a safety ceiling, not the manual stepping ratio.
func calculate_adaptive_flight_profile(length: float, foot_count: int, actual_speed: float, support_distance: float, capacity: int, observed_landing_time: float = 0.0) -> Dictionary:
	if target_speed<=0 or foot_count<=0 or capacity<=0: return {"enabled": false}
	length = maxf(length,0.1)
	var count := maxi(foot_count,1)
	var desired_frequency := count*target_speed/maxf(length*0.4,0.05)
	if maximum_step_frequency>0: desired_frequency = minf(desired_frequency,maximum_step_frequency)
	var nominal_cycle := count/maxf(desired_frequency,0.001)
	var confirmation := clampf(0.25/maxf(desired_frequency,0.01),0.03,0.08)
	# Preserve measured landing time; a stuck foot cannot make the budget grow without bound.
	var reserve := maxf(confirmation,clampf(observed_landing_time,0.0,2.0))
	var budget_speed := maxf(actual_speed,target_speed)
	var stance := maxf(support_distance,0.0)/maxf(budget_speed,0.05)
	# Reference cadence sizes the swing. Measured landing latency is diagnostic;
	# it must never squeeze the next swing into a violent catch-up motion.
	var base_air := maxf(nominal_cycle*0.6,0.35)
	var requested_air := base_air*1.12
	var geometric_air_limit := maxf(0.15,sqrt(8.0*length*0.35/9.8))
	var air := minf(requested_air,geometric_air_limit)
	var added_air := maxf(air-minf(base_air,geometric_air_limit),0.0)
	# Frequency is a motion reference only. Support admission is handled by the controller.
	var frequency := desired_frequency
	var cycle := count/maxf(frequency,0.001)
	var required_capacity := clampi(ceili(frequency*(air+confirmation+0.02)-0.000001),1,capacity)
	var drive_acceleration := clampf(target_speed*2.0,2.0,12.0)
	var prediction_speed := minf(budget_speed,maxf(actual_speed,0.0)+drive_acceleration*air*0.5)
	# Clearance depends on geometry and speed, not the square of flight duration.
	# These are controlled swings, not ballistic jumps.
	var speed_ratio := clampf(target_speed/sqrt(9.8*length),0.0,1.0)
	var lift := length*lerpf(0.045,0.12,speed_ratio)
	var covered := maxf(support_distance,0.0)+budget_speed*air
	return {"enabled": true,"automatic_flight": true,"total_frequency": frequency,"cycle": cycle,"required_stride": target_speed*cycle,
		"nominal_frequency": desired_frequency,"nominal_cycle": nominal_cycle,
		"actual_speed": actual_speed,"planning_speed": prediction_speed,"budget_speed": budget_speed,"support_distance": support_distance,
		"raw_stance_time": stance,"stance_duration": maxf(cycle-air-reserve,0),"base_air_duration": base_air,"air_margin": added_air,
		"air_duration": air,"requested_air_duration": requested_air,
		"landing_reserve": reserve,"landing_confirmation": confirmation,"observed_landing_time": observed_landing_time,"air_duration_limited": requested_air>geometric_air_limit+0.001,"walking_stride_limit": length*0.5,
		"requires_flight": target_speed*cycle>length*0.5,"required_capacity": required_capacity,"maximum_capacity": capacity,
		"covered_stride": covered,"distance_deficit": maxf(target_speed*cycle-covered,0.0),"lift": lift,
		"lease_duration": minf(2.0,air+confirmation+0.12),"brake_time": clampf(air*0.2,0.08,0.18),
		"touchdown_speed_limit": clampf(target_speed*0.15,0.3,1.5)}
