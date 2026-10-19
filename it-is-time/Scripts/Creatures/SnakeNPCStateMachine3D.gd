extends "res://Scripts/Creatures/NPCStateMachine3D.gd"

var _snake_reposition_pending := false
var _reposition_target: Node3D
var _reposition_distance := -1.0
var _reposition_elapsed := 0.0
var _reposition_stalled := 0.0
var _reposition_best_error := INF
var _reposition_timeout := 0.0
var _waiting_for_support := false
var _lane_alignment_active := false
var _lane_alignment: Dictionary = {}

func _clear_reposition() -> void:
	_reposition_target = null
	_reposition_distance = -1.0
	_snake_reposition_pending = false
	_reposition_elapsed = 0.0
	_reposition_stalled = 0.0
	_reposition_timeout = 0.0

func _cancel_attack() -> void:
	_clear_reposition()
	_lane_alignment_active = false
	_lane_alignment.clear()
	super._cancel_attack()
	if current_state == State.ATTACK: change_state(State.WAITING)

func _preferred_attack_distance(attack: ATTACK) -> float:
	if _reposition_distance >= 0.0 and _reposition_target == _target: return _reposition_distance
	return super._preferred_attack_distance(attack)

func _attack_approach(attack: ATTACK) -> Dictionary:
	var approach := super._attack_approach(attack)
	if not generated_x_axis_facing or approach.is_empty(): return approach
	var previous := _lane_alignment_active
	_lane_alignment_active = absf(approach.z_error) > float(approach.z_tolerance)*(0.5 if previous else 1.0)
	_lane_alignment = approach.duplicate()
	_lane_alignment["aligning"] = _lane_alignment_active
	if _lane_alignment_active:
		approach.z_tolerance *= 0.5
	else:
		approach.z_error = 0.0
		approach.goal.z = _get_navigation_origin_position().z
	if previous != _lane_alignment_active: _log_state_event(&"snake_lane_alignment",_lane_alignment)
	return approach

func _predict_attack(attack: ATTACK, target: Node3D) -> Dictionary:
	var result := super._predict_attack(attack,target)
	_waiting_for_support = result.get("reason") == &"no_ground_support"
	if not result.get("hit",false) and result.get("reason") in [&"snake_sweep_misses",&"outside_fixed_root_reach"]:
		_snake_reposition_pending = true
	return result

func _available_attacks() -> Array[ATTACK]:
	# Disabled attacks must not reserve their range and stop ordinary pursuit.
	if attack_execution_enabled: return super._available_attacks()
	var unavailable: Array[ATTACK] = []
	return unavailable

func _update_combat(delta: float) -> void:
	if _reposition_distance >= 0.0:
		_reposition_elapsed += delta
		_reposition_stalled += delta
		if not is_instance_valid(_reposition_target) or _reposition_target != _target or not attack_execution_enabled or current_state == State.ATTACK:
			_clear_reposition()
	# A killed/despawned victim must not interrupt the physical recovery pose halfway through.
	if current_state == State.ATTACK and _active_attack != null and is_instance_valid(_attack_receiver) and _attack_receiver.is_npc_attack_active():
		_lane_alignment_active = false
		if not _lane_alignment.is_empty(): _lane_alignment["aligning"] = false
		_advance_active_attack(delta)
		return
	super._update_combat(delta)

## Retain faction selection, repathing and friendly avoidance when attacks are unavailable.
func _plan_attack_distance(distance: float, attacks: Array[ATTACK]) -> bool:
	if not attacks.is_empty():
		var receiver := get_parent().get_node("SnakeBiteAttackController3D")
		if generated_x_axis_facing:
			distance = absf(_target.global_position.x-_get_navigation_origin_position().x)
			if _lane_alignment_active: _snake_reposition_pending = false
		if _waiting_for_support and receiver._grounded_belly_count() == 0 and receiver.is_npc_target_in_attack_range(attacks[0].action_id,_target):
			_clear_reposition()
			_distance_attack = attacks[0]
			_distance_error = 0.0
			return false
		_waiting_for_support = false
		if _reposition_distance >= 0.0 and _reposition_target != _target: _clear_reposition()
		var error := absf(distance-_reposition_distance)
		var tolerance := _attack_distance_tolerance(attacks[0])
		var stall_time := maxf(behavior.scan_interval*3.0,0.8)
		var finished: StringName = &""
		if _reposition_distance >= 0.0:
			if error < _reposition_best_error-tolerance*0.25:
				_reposition_best_error = error
				_reposition_stalled = 0.0
			if error <= tolerance: finished = &"arrived"
			elif _reposition_stalled >= stall_time: finished = &"stalled"
			elif _reposition_elapsed >= _reposition_timeout: finished = &"timeout"
			if finished != &"":
				_log_state_event(&"snake_reposition_finished",{"reason":finished,"distance":_reposition_distance,"error":error,"elapsed":_reposition_elapsed})
				_reposition_distance = -1.0
		if _snake_reposition_pending and _reposition_distance < 0.0:
			# Finish trying one station before repeated prediction misses select another.
			_snake_reposition_pending = false
			_prediction_distance_sample += 1
			_reposition_target = _target
			_reposition_distance = super._preferred_attack_distance(attacks[0])
			_reposition_elapsed = 0.0
			_reposition_stalled = 0.0
			_reposition_best_error = absf(distance-_reposition_distance)
			var movement := get_parent().get_node("SnakeMovementController3D")
			_reposition_timeout = clampf(_reposition_best_error/maxf(movement.motion_data.target_speed,0.1)*2.0+stall_time,stall_time,6.0)
			_log_state_event(&"snake_reposition",{"sample":_prediction_distance_sample,"distance":_reposition_distance,"timeout":_reposition_timeout})
		return super._plan_attack_distance(distance, attacks)
	_clear_reposition()
	_lane_alignment_active = false
	_lane_alignment.clear()
	return super._plan_attack_distance(distance, attacks)

func get_npc_movement_speed_scale(full_speed: float) -> float:
	if generated_x_axis_facing and not _manual_command:
		return super.get_npc_movement_speed_scale(full_speed)
	if _reposition_distance < 0.0 or _manual_command: return super.get_npc_movement_speed_scale(full_speed)
	var remaining := maxf(absf(_distance_error)-_attack_distance_tolerance(_distance_attack)*0.5,0.0)
	var braking_speed := sqrt(2.0*approach_braking_acceleration*remaining)
	return clampf(minf(remaining/approach_slowdown_distance,braking_speed/maxf(full_speed,0.001)),0.0,1.0)

func get_state_diagnostics() -> Dictionary:
	var result := super.get_state_diagnostics()
	result.merge({"snake_reposition_distance":_reposition_distance,"snake_reposition_elapsed":_reposition_elapsed,
		"snake_reposition_stalled":_reposition_stalled,"snake_reposition_timeout":_reposition_timeout,"snake_lane_alignment":_lane_alignment})
	return result
