extends "res://Scripts/Creatures/NPCStateMachine3D.gd"

## The generated Human turns through its feet; do not add a competing Torso turn motor.
@export_range(1.0, 90.0, 1.0) var attack_facing_tolerance_degrees: float = 15.0
@export_range(20.0, 120.0, 1.0) var movement_turn_pause_degrees: float = 45.0
@export_range(0.0, 1.0, 0.01) var movement_turn_confirmation_time: float = 0.2
var _human_turn_hold := false
var _human_turn_settled := 0.0

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _manual_command or get_npc_body_facing_direction().is_zero_approx():
		_human_turn_hold = false
		_human_turn_settled = 0.0
		return
	var error := absf(_body_facing_error())
	var movement := get_parent().get_node("GeneratedLegStepMovementController3D")
	if movement._turn_command_pending and error > deg_to_rad(maxf(movement_turn_pause_degrees, attack_facing_tolerance_degrees+5.0)):
		_human_turn_hold = true
		_human_turn_settled = 0.0
	elif _human_turn_hold:
		var settled: bool = error <= deg_to_rad(attack_facing_tolerance_degrees) and absf(movement._get_physical_yaw_rate()) < deg_to_rad(15.0)
		_human_turn_settled = _human_turn_settled+delta if settled else 0.0
		if _human_turn_settled >= movement_turn_confirmation_time: _human_turn_hold = false

func _body_facing_error() -> float:
	var movement := get_parent().get_node_or_null("GeneratedLegStepMovementController3D")
	var direction := get_npc_body_facing_direction()
	if movement == null or direction.is_zero_approx(): return 0.0
	return wrapf(atan2(-direction.z, direction.x)-movement._get_physical_heading_yaw(), -PI, PI)

func _body_facing_ready() -> bool:
	return absf(_body_facing_error()) <= deg_to_rad(attack_facing_tolerance_degrees)

func get_movement_direction() -> Vector3:
	if not _manual_command and _human_turn_hold: return Vector3.ZERO
	return super.get_movement_direction()

func get_state_diagnostics() -> Dictionary:
	var result := super.get_state_diagnostics()
	result["human_turn_gate"] = {"holding":_human_turn_hold, "error_degrees":rad_to_deg(_body_facing_error()), "settled_time":_human_turn_settled}
	return result

func _try_attack(distance: float) -> bool:
	if not _body_facing_ready():
		_attack_block_reason = &"body_turn_pending"
		return false
	return super._try_attack(distance)
