extends Resource

@export var enabled: bool = true
@export var input_action: StringName = &"MouseLeft"
@export_group("Target")
## Downward angle from the horizontal plane; positive angles point below the Head.
@export_range(0.0,90.0,0.5) var minimum_depression_angle_degrees: float = 15.0
@export_range(0.0,90.0,0.5) var maximum_depression_angle_degrees: float = 90.0
## Angle to the world X axis line (both +X and -X), measured in the XZ plane.
@export_range(0.0,90.0,0.5) var maximum_horizontal_angle_degrees: float = 30.0
@export_range(0.0,200.0,0.1,"or_greater") var minimum_target_distance: float = 0.1
@export_range(0.1,200.0,0.5,"or_greater") var maximum_target_distance: float = 40.0
@export_flags_3d_physics var obstacle_mask: int = 1
@export_group("Aiming")
@export_range(0.0,5.0,0.05) var aiming_ascent_speed: float = 0.5
@export_range(0.0,5.0,0.05) var minimum_aiming_time: float = 0.8
@export_range(0.1,20.0,0.1) var maximum_aiming_time: float = 6.0
@export_range(0.5,45.0,0.5) var head_alignment_tolerance_degrees: float = 10.0
@export_range(0.5,45.0,0.5) var wing_fold_tolerance_degrees: float = 15.0
@export_range(1.0,10.0,0.1) var aiming_wing_motor_force_multiplier: float = 4.0
@export_range(0.01,5.0,0.05) var aiming_maximum_angular_speed: float = 0.7
@export_range(0.0,1.0,0.01) var aiming_confirmation_time: float = 0.15
@export_group("Dive")
## Cone dimensions relative to generated Head dimensions; no independent rigid body mass.
@export_range(0.05, 3.0, 0.05, "or_greater") var weapon_length_ratio: float = 0.8
@export_range(0.05, 2.0, 0.05, "or_greater") var weapon_radius_ratio: float = 0.5
@export_range(0.05,3.0,0.05) var fold_time: float = 0.8
@export_range(0.1,50.0,0.1,"or_greater") var dive_speed: float = 18.0
@export_range(0.1,30.0,0.1) var velocity_response: float = 5.0
@export_range(1.0,300.0,1.0) var maximum_acceleration: float = 60.0
@export_range(0.0,1.0,0.05) var dive_gravity_compensation: float = 0.0
@export_range(0.0,1.0,0.05) var target_lead_time: float = 0.2
@export_range(0.1,10.0,0.1) var maximum_dive_time: float = 4.0
@export_range(0.0,100.0,0.1) var pose_strength: float = 30.0
@export_range(0.0,50.0,0.1) var pose_damping: float = 10.0
@export_group("Pull Up")
@export_range(0.1,20.0,0.1) var pull_up_speed: float = 5.0
@export_range(0.1,5.0,0.05) var pull_up_time: float = 0.8
@export_range(0.1,100.0,0.1) var maximum_pull_up_velocity_change: float = 30.0
@export_range(0.0,20.0,0.1) var cooldown: float = 2.5

func is_valid() -> bool:
	if not is_finite(weapon_length_ratio) or weapon_length_ratio <= 0.0 or not is_finite(weapon_radius_ratio) or weapon_radius_ratio <= 0.0: return false
	for value: float in [aiming_wing_motor_force_multiplier,aiming_ascent_speed,minimum_aiming_time,maximum_aiming_time,head_alignment_tolerance_degrees,wing_fold_tolerance_degrees,aiming_maximum_angular_speed,aiming_confirmation_time,minimum_depression_angle_degrees,maximum_depression_angle_degrees,maximum_horizontal_angle_degrees,minimum_target_distance,maximum_target_distance,fold_time,dive_speed,velocity_response,maximum_acceleration,dive_gravity_compensation,target_lead_time,maximum_dive_time,pose_strength,pose_damping,pull_up_speed,pull_up_time,maximum_pull_up_velocity_change,cooldown]:
		if not is_finite(value) or value<0.0: return false
	return maximum_aiming_time>=maxf(minimum_aiming_time,fold_time) and maximum_aiming_time>0.0 and head_alignment_tolerance_degrees<=180.0 and wing_fold_tolerance_degrees<=180.0 and minimum_depression_angle_degrees<=maximum_depression_angle_degrees and maximum_depression_angle_degrees<=90.0 and maximum_horizontal_angle_degrees<=90.0 and minimum_target_distance<=maximum_target_distance and maximum_target_distance>0.0 and fold_time>0.0 and dive_speed>0.0 and maximum_acceleration>0.0 and maximum_dive_time>0.0 and pull_up_time>0.0

## Evaluate actual Head-to-target geometry, independently of faction and obstacle checks.
func evaluate_target_geometry(origin: Vector3, target: Vector3) -> Dictionary:
	var result := {"hit":false,"reason":&"invalid_geometry"}
	if not is_valid() or not origin.is_finite() or not target.is_finite(): return result
	var difference := target-origin
	var distance := difference.length()
	if not is_finite(distance) or distance<=0.000001: return result
	var horizontal_distance := Vector2(difference.x,difference.z).length()
	var depression := rad_to_deg(atan2(-difference.y,horizontal_distance))
	# Exactly vertical dives have no horizontal deviation to reject.
	var horizontal_angle := rad_to_deg(atan2(absf(difference.z),absf(difference.x))) if horizontal_distance>0.000001 else 0.0
	result["distance"] = distance
	result["depression_angle_degrees"] = depression
	result["horizontal_angle_degrees"] = horizontal_angle
	if distance<minimum_target_distance-0.00001 or distance>maximum_target_distance+0.00001:
		result.reason = &"out_of_range"
	elif depression<minimum_depression_angle_degrees-0.00001 or depression>maximum_depression_angle_degrees+0.00001:
		result.reason = &"depression_angle"
	elif horizontal_angle>maximum_horizontal_angle_degrees+0.00001:
		result.reason = &"horizontal_angle"
	else:
		result.hit = true
		result.reason = &"eligible_geometry"
	return result
