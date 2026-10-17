@tool
extends "res://Scripts/Creatures/CreatureAttackData.gd"

@export_group("Attack Joint Limits")
## Raised Torso/Head Z bending only; never narrows a wider standing limit.
@export_range(0.0, 90.0, 0.5) var attack_bend_limit_degrees: float = 45.0
## Return toward standing limits only as the actual and requested poses permit.
@export_range(1.0, 360.0, 1.0, "or_greater") var bend_restore_speed_degrees: float = 60.0

@export_group("Preparation")
@export_range(0.1, 3.0, 0.05) var preparation_time: float = 0.7
@export_range(0.0, 3.0, 0.05) var preparation_extra_wait: float = 1.0
## Pre-commit facing update interval; preparation and lunge use a single locked world point.
@export_range(0.05, 0.5, 0.01) var positioning_update_interval: float = 0.1
## Legacy serialized value; prediction misses no longer cancel an accepted attack.
@export_storage var prediction_retry_grace: float = 0.2
## Fractions of the raised chain length, measured from the authored pose.
@export_range(0.0, 0.3, 0.01) var lift_ratio: float = 0.06
@export_range(0.0, 0.3, 0.01) var retract_ratio: float = 0.03
## Preserve root-side S curvature: links in this fraction use 30% of their saved bend range.
## The first root joint can still bow the whole raised chain toward a low target.
@export_range(0.0, 0.6, 0.05) var preserved_root_ratio: float = 0.3
@export_range(1.0, 45.0, 1.0) var aim_tolerance_degrees: float = 15.0
@export_range(5.0, 75.0, 1.0) var jaw_open_degrees: float = 40.0

@export_group("Lunge")
## Reference length of the raised chain; times/speeds scale with sqrt(actual/reference).
@export_range(0.1, 100.0, 0.1) var reference_chain_length: float = 25.0
## Reference Head extension speed; the supporting belly receives no lunge propulsion.
@export_range(0.1, 100.0, 0.1) var burst_speed: float = 16.0
@export_range(0.1, 3.0, 0.05) var lunge_time: float = 1.5
## Speed up the raised-chain extension from a fixed supporting root.
@export_range(1.0, 3.0, 0.05) var head_extension_speed_multiplier: float = 1.5
## Bounded physical catch-up after the planned pose has finished extending.
@export_range(0.0, 2.0, 0.05) var lunge_extra_wait: float = 0.5
## Mouth overshoot beyond the predicted target, as a fraction of Head X size.
@export_range(0.0, 0.5, 0.01) var extension_ratio: float = 0.15
## Acceleration cap for pre-attack braking and fixed ground support.
@export_range(0.1, 300.0, 1.0) var maximum_acceleration: float = 100.0
## Ground support uses half this response time, with critical damping.
@export_range(0.03, 1.0, 0.01) var burst_response_time: float = 0.1

@export_group("Pose And Recovery")
@export_range(0.1, 300.0, 1.0) var maximum_pose_acceleration: float = 140.0
@export_range(0.1, 200.0, 1.0) var maximum_angular_acceleration: float = 60.0
@export_range(0.1, 100.0, 0.5) var angular_strength: float = 45.0
@export_range(0.1, 50.0, 0.1) var angular_damping: float = 12.0
@export_range(0.05, 1.0, 0.01) var jaw_close_time: float = 0.18
@export_range(0.1, 5.0, 0.1) var recovery_time: float = 1.2
@export_range(0.0, 10.0, 0.1) var recovery_extra_wait: float = 2.0

@export_group("Damage")
## Head-local box axes; visual aiming reads the fitted mouth markers separately.
@export var damage_box_ratio: Vector3 = Vector3(0.45, 0.35, 1.3)
@export var damage_center_ratio: Vector3 = Vector3(0.35, -0.12, 0.0)
@export_range(0.01, 10.0, 0.05) var impulse_multiplier: float = 2.0

func _default_cooldown() -> float: return 2.8

func is_valid() -> bool:
	for value: float in [preparation_time, reference_chain_length, burst_speed, lunge_time,
		maximum_acceleration, burst_response_time, maximum_pose_acceleration, maximum_angular_acceleration, angular_strength, angular_damping,
		jaw_close_time, recovery_time, impulse_multiplier, positioning_update_interval, bend_restore_speed_degrees]:
		if not is_finite(value) or value <= 0.0: return false
	for value: float in [cooldown, preparation_extra_wait, lunge_extra_wait, recovery_extra_wait, lift_ratio, retract_ratio, extension_ratio]:
		if not is_finite(value) or value < 0.0: return false
	return positioning_update_interval >= 0.05 and positioning_update_interval <= 0.5 \
		and is_finite(attack_bend_limit_degrees) and attack_bend_limit_degrees >= 0.0 and attack_bend_limit_degrees <= 90.0 \
		and is_finite(head_extension_speed_multiplier) and head_extension_speed_multiplier >= 1.0 and head_extension_speed_multiplier <= 3.0 \
		and is_finite(preserved_root_ratio) and preserved_root_ratio >= 0.0 and preserved_root_ratio <= 0.6 \
		and is_finite(jaw_open_degrees) and jaw_open_degrees > 0.0 and jaw_open_degrees <= 75.0 \
		and is_finite(aim_tolerance_degrees) and aim_tolerance_degrees > 0.0 and aim_tolerance_degrees <= 45.0 \
		and damage_box_ratio.is_finite() and damage_box_ratio.x > 0.0 and damage_box_ratio.y > 0.0 and damage_box_ratio.z > 0.0 \
		and damage_center_ratio.is_finite()
