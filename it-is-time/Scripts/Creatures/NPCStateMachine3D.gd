extends Node3D

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")
const BEHAVIOR = preload("res://Scripts/Creatures/NPCBehaviorData.gd")
const ATTACK = preload("res://Scripts/Creatures/NPCAttackData.gd")

signal state_changed(previous_state: State, current_state: State)

enum State { IDLE, MOVE_TO_TARGET, ATTACK, WAITING }
@export var enabled: bool = true
@export var behavior: BEHAVIOR
var _enemy: Node3D
var _scan_elapsed := 0.0
var _attack_elapsed := 0.0
var _attack_retry := 0.0
var _active_attack: ATTACK
var _attack_receiver: Node
var _cooldowns: Dictionary = {}
var _manual_command := false
var _character_enabled := true
var _attack_block_reason: StringName = &"none"
var _distance_attack: ATTACK
var _distance_error: float = 0.0
var _attack_predictions: Array[Dictionary] = []
var _prediction_distance_sample := -1
var _navigation_arrival_distance: float = 0.75

@export_group("State")
@export var initial_state: State = State.IDLE
@export var auto_start_when_target_exists: bool = true
@export var use_fast_movement: bool = false

@export_group("Navigation")
@export var target_path: NodePath
@export var target_group: StringName = &"npc_navigation_target"
@export var auto_find_target_by_group: bool = true
@export var navigation_origin_path: NodePath = NodePath("../Torso")
@export_range(0.05, 20.0, 0.05, "or_greater") var arrival_distance: float = 0.75
@export var refresh_target_each_physics_frame: bool = true
@export_range(0.01, 10.0, 0.01, "or_greater") var target_repath_distance: float = 0.25

@export_group("Debug")
@export var debug_logging_enabled: bool = false
@export_range(0.1, 10.0, 0.1, "or_greater") var debug_log_interval: float = 0.5

var current_state: State = State.IDLE
var _target: Node3D
var _navigation_origin: Node3D
var _requested_target_position: Vector3
var _has_requested_target: bool = false
var _debug_elapsed: float = 0.0
var _performance_tracking_enabled: bool = false
var _performance_physics_frames: int = 0
var _performance_target_refreshes: int = 0
var _performance_repaths: int = 0
var _performance_map_projections: int = 0
var _performance_total_usec: int = 0
var _performance_max_usec: int = 0

@onready var navigation_agent: NavigationAgent3D = $NavigationAgent3D

func _ready() -> void:
	_navigation_arrival_distance = navigation_agent.target_desired_distance
	add_to_group(&"npc_state_machines")
	var runtime_console := get_tree().root.get_node_or_null("RuntimeConsole")
	if (
		runtime_console != null
		and runtime_console.has_method("is_npc_diagnostic_tracking_enabled")
		and bool(runtime_console.call("is_npc_diagnostic_tracking_enabled"))
	):
		debug_logging_enabled = true
	_navigation_origin = get_node_or_null(navigation_origin_path) as Node3D
	_target = get_node_or_null(target_path) as Node3D
	if not is_instance_valid(_target) and auto_find_target_by_group:
		_target = get_tree().get_first_node_in_group(target_group) as Node3D
	current_state = initial_state
	call_deferred("_initialize_navigation")

func _physics_process(delta: float) -> void:
	if not enabled or not _character_enabled or PLAYER_CONTEXT.controlled_character(self) == get_parent():
		_cancel_attack()
		change_state(State.IDLE)
		return
	var started_usec := Time.get_ticks_usec() if _performance_tracking_enabled else 0
	if behavior != null and not _manual_command:
		_update_combat(delta)
	elif auto_find_target_by_group and target_path.is_empty() and PLAYER_CONTEXT.controller(self) != null:
		var player_anchor := PLAYER_CONTEXT.anchor(self)
		if player_anchor != _target: move_to_node(player_anchor)
	_sync_navigation_origin()
	_update_debug_log(delta)
	if current_state == State.MOVE_TO_TARGET:
		if is_instance_valid(_target) and refresh_target_each_physics_frame and (behavior == null or _manual_command):
			if _performance_tracking_enabled:
				_performance_target_refreshes += 1
			_set_agent_target(_target.global_position)
		if not _has_requested_target:
			change_state(State.IDLE)
		elif (behavior == null or _manual_command) and _horizontal_distance_to(_requested_target_position) <= arrival_distance:
			change_state(State.IDLE)
	if _performance_tracking_enabled:
		var elapsed_usec := Time.get_ticks_usec() - started_usec
		_performance_physics_frames += 1
		_performance_total_usec += elapsed_usec
		_performance_max_usec = maxi(_performance_max_usec, elapsed_usec)

func _initialize_navigation() -> void:
	_sync_navigation_origin()
	if behavior != null: return
	if is_instance_valid(_target):
		_set_agent_target(_target.global_position)
		if auto_start_when_target_exists:
			change_state(State.MOVE_TO_TARGET)
	elif current_state == State.MOVE_TO_TARGET and not _has_requested_target:
		change_state(State.IDLE)

func change_state(next_state: State) -> void:
	if current_state == next_state:
		return
	var previous_state := current_state
	current_state = next_state
	state_changed.emit(previous_state, current_state)
	_log_state_event(&"transition", {"from":State.keys()[previous_state],"to":State.keys()[current_state]})

func _log_state_event(event: StringName, details: Dictionary = {}) -> void:
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	if debug_logging_enabled or (console != null and console.is_npc_state_tracking_enabled(self)):
		print("[npc_state] event=",event," npc_path=",get_parent().get_path()," npc_id=",get_parent().get_instance_id()," state=",State.keys()[current_state]," details=",details)

func get_navigation_motion_diagnostics() -> Dictionary:
	var path := navigation_agent.get_current_navigation_path()
	var index := navigation_agent.get_current_navigation_path_index()
	var next_point := path[clampi(index, 0, path.size()-1)] if not path.is_empty() else _get_navigation_origin_position()
	return {"path": path, "path_index": index, "next_point": next_point,
		"next_direction": (next_point - _get_navigation_origin_position()).slide(Vector3.UP).normalized(),
		"enemy_direction": (_enemy_position(_enemy) - _get_navigation_origin_position()).slide(Vector3.UP).normalized() if is_instance_valid(_enemy) else Vector3.ZERO}

func get_state_diagnostics() -> Dictionary:
	var cooldowns: Dictionary = {}
	for attack: ATTACK in _cooldowns: cooldowns[str(attack.action_id)+":"+str(attack.get_instance_id())] = _cooldowns[attack]
	var disabled_reason := "none"
	if not enabled: disabled_reason = "component_disabled"
	elif not _character_enabled: disabled_reason = "character_disabled"
	elif PLAYER_CONTEXT.controlled_character(self) == get_parent(): disabled_reason = "player_controlled"
	var nav_ready := _navigation_map_is_ready()
	return {"npc_path":str(get_parent().get_path()),"npc_id":get_parent().get_instance_id(),"state_machine_path":str(get_path()),"state":State.keys()[current_state],"disabled_reason":disabled_reason,"manual_command":_manual_command,"enemy":str(_enemy.get_path()) if is_instance_valid(_enemy) else "none","has_requested_target":_has_requested_target,"position":_get_navigation_origin_position(),"target":_requested_target_position,"navigation_ready":nav_ready,"path_points":navigation_agent.get_current_navigation_path().size(),"navigation_finished":navigation_agent.is_navigation_finished() if nav_ready else true,"target_reachable":navigation_agent.is_target_reachable() if nav_ready else false,"active_attack":_active_attack.action_id if _active_attack != null else &"none","attack_elapsed":_attack_elapsed,"attack_block_reason":_attack_block_reason,"cooldowns":cooldowns}

func move_to_node(target: Node3D) -> void:
	_cancel_attack()
	_manual_command = true
	_target = target
	if is_instance_valid(_target):
		_set_agent_target(_target.global_position)
		change_state(State.MOVE_TO_TARGET)

func move_to_position(target_position: Vector3) -> void:
	_cancel_attack()
	_manual_command = true
	_target = null
	_set_agent_target(target_position)
	change_state(State.MOVE_TO_TARGET)

func stop() -> void:
	_cancel_attack()
	_manual_command = true
	_enemy = null
	_has_requested_target = false
	change_state(State.IDLE)

func resume_autonomous() -> void:
	_manual_command = false
	_scan_elapsed = 0.0

func get_movement_direction() -> Vector3:
	if not enabled or not _character_enabled: return Vector3.ZERO
	var walking_attack := current_state == State.ATTACK and _active_attack != null and _active_attack.allow_movement
	if walking_attack and _distance_attack != null and absf(_distance_error) <= _distance_attack.distance_tolerance: return Vector3.ZERO
	if (current_state != State.MOVE_TO_TARGET and not walking_attack) or not _has_requested_target:
		return Vector3.ZERO
	if not _navigation_map_is_ready() or navigation_agent.is_navigation_finished():
		return Vector3.ZERO
	var origin := _get_navigation_origin_position()
	var next_position := navigation_agent.get_next_path_position()
	var direction := next_position - origin
	direction.y = 0.0
	if direction.is_zero_approx():
		direction = _requested_target_position - origin
		direction.y = 0.0
	return direction.normalized() if not direction.is_zero_approx() else Vector3.ZERO

func is_fast_movement_requested() -> bool:
	return current_state == State.MOVE_TO_TARGET and use_fast_movement

func set_diagnostic_logging_enabled(enabled: bool) -> void:
	debug_logging_enabled = enabled
	_debug_elapsed = debug_log_interval if enabled else 0.0

func _set_agent_target(target_position: Vector3) -> void:
	# Navigation must not stop outside the attack's distance tolerance.
	navigation_agent.target_desired_distance = maxf(minf(_navigation_arrival_distance, _distance_attack.distance_tolerance*0.5),0.01) if behavior != null and not _manual_command and _distance_attack != null else _navigation_arrival_distance
	var navigation_target := _project_to_navigation_map(target_position)
	var should_repath := (
		not _has_requested_target
		or navigation_agent.target_position.distance_to(navigation_target) >= target_repath_distance
	)
	_requested_target_position = navigation_target
	_has_requested_target = true
	if should_repath:
		if _performance_tracking_enabled:
			_performance_repaths += 1
		navigation_agent.target_position = navigation_target

func _sync_navigation_origin() -> void:
	if not is_instance_valid(_navigation_origin) and get_parent().has_method("get_combat_anchor"):
		_navigation_origin = get_parent().get_combat_anchor()
	if is_instance_valid(_navigation_origin):
		global_position = _project_to_navigation_map(_navigation_origin.global_position)

func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value:
		_cancel_attack()
		change_state(State.IDLE)

func _is_enemy(actor: Node) -> bool:
	return get_parent().has_method("get_faction_id") and is_instance_valid(actor) and actor != get_parent() and not actor.is_queued_for_deletion() and actor.has_method("get_faction_id") and actor.has_method("is_combat_alive") and actor.is_combat_alive() and actor.get_faction_id() != get_parent().get_faction_id()

func is_jump_requested() -> bool: return false

func get_generated_facing_direction(_delta: float) -> Vector3:
	if not enabled or not _character_enabled or not _is_enemy(_enemy): return Vector3.ZERO
	return (_enemy_position(_enemy)-_get_navigation_origin_position()).slide(Vector3.UP).normalized()

func _enemy_position(actor: Node3D) -> Vector3:
	return _enemy_torso(actor).global_position

func _enemy_torso(actor: Node3D) -> Node3D:
	if actor.has_method("get_nearest_combat_torso"):
		return actor.get_nearest_combat_torso(_get_navigation_origin_position())
	return actor.get_combat_anchor()

func _available_attacks() -> Array[ATTACK]:
	var result: Array[ATTACK] = []
	if behavior == null: return result
	for attack: ATTACK in behavior.attacks:
		if attack == null or not attack.enabled or attack.maximum_range < attack.minimum_range or attack.selection_weight <= 0.0: continue
		var receiver := get_parent().get_node_or_null(attack.receiver_path)
		if receiver == null or not receiver.has_method("try_start_npc_attack") or not receiver.has_method("is_npc_attack_active") or not receiver.has_method("cancel_npc_attack"): continue
		if receiver.has_method("has_npc_attack") and not receiver.has_npc_attack(attack.action_id): continue
		result.append(attack)
	return result

func _preferred_attack_distance(attack: ATTACK) -> float:
	var desired := attack.preferred_distance if attack.preferred_distance >= 0.0 else behavior.preferred_distance
	# Keep the stop band inside the legal attack interval.
	var margin := minf(attack.distance_tolerance, (attack.maximum_range-attack.minimum_range)*0.5)
	if _prediction_distance_sample >= 0:
		return lerpf(attack.minimum_range+margin,attack.maximum_range-margin,float(_prediction_distance_sample%5)/4.0)
	return clampf(desired, attack.minimum_range+margin, attack.maximum_range-margin)

func _plan_attack_distance(distance: float, attacks: Array[ATTACK]) -> bool:
	_distance_attack = _active_attack
	if _distance_attack == null:
		var best := INF
		var ready_exists := false
		for attack: ATTACK in attacks:
			if float(_cooldowns.get(attack,0.0)) <= 0.0: ready_exists = true
		for attack: ATTACK in attacks:
			if ready_exists and float(_cooldowns.get(attack,0.0)) > 0.0: continue
			var cost := absf(distance-_preferred_attack_distance(attack))
			if cost < best:
				best = cost
				_distance_attack = attack
	_distance_error = 0.0
	if _distance_attack == null: return false
	var desired := _preferred_attack_distance(_distance_attack)
	_distance_error = distance-desired
	var tolerance := minf(_distance_attack.distance_tolerance, (_distance_attack.maximum_range-_distance_attack.minimum_range)*0.5)
	if absf(_distance_error) <= tolerance: return false
	var away := (_get_navigation_origin_position()-_target.global_position).slide(Vector3.UP).normalized()
	if away.is_zero_approx(): away = Vector3.LEFT
	_set_agent_target(_target.global_position + away*desired)
	return true

func get_attack_range_diagnostics() -> Dictionary:
	var ranges: Array[Dictionary] = []
	var distance := _horizontal_distance_to(_target.global_position) if is_instance_valid(_target) else -1.0
	var inside := false
	for attack: ATTACK in _available_attacks():
		if distance >= attack.minimum_range and distance <= attack.maximum_range: inside = true
		ranges.append({"action":attack.action_id,"minimum":attack.minimum_range,"maximum":attack.maximum_range,
			"preferred":_preferred_attack_distance(attack),"cooldown":float(_cooldowns.get(attack,0.0))})
	return {"ranges":ranges,"predictions":_attack_predictions,"target_part":str(_target.get_path()) if is_instance_valid(_target) else "none",
		"distance":distance,"inside_attack_range":inside,
		"distance_attack":_distance_attack.action_id if _distance_attack != null else &"none","distance_error":_distance_error}

func _visible(actor: Node3D, target_part: Node3D = null) -> bool:
	if not behavior.require_line_of_sight: return true
	var excluded: Array[RID] = []
	for character: Node3D in [get_parent(), actor]:
		for body: Node in character.find_children("*", "PhysicsBody3D", true, false): excluded.append(body.get_rid())
	var point := target_part.global_position if is_instance_valid(target_part) else _enemy_position(actor)
	var query := PhysicsRayQueryParameters3D.create(_get_navigation_origin_position(), point, behavior.obstacle_mask, excluded)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _update_combat(delta: float) -> void:
	for key in _cooldowns: _cooldowns[key] = maxf(float(_cooldowns[key])-delta, 0.0)
	_attack_retry = maxf(_attack_retry-delta,0.0)
	_scan_elapsed -= delta
	if not _is_enemy(_enemy) or (is_instance_valid(_enemy) and _horizontal_distance_to(_enemy_position(_enemy)) > behavior.disengage_radius):
		if is_instance_valid(_enemy): _log_state_event(&"target_lost",{"target":str(_enemy.get_path()),"reason":"dead_friendly_or_out_of_range"})
		_cancel_attack()
		_enemy = null
		_prediction_distance_sample = -1
		_attack_predictions.clear()
		_target = null
		_has_requested_target = false
	if _scan_elapsed <= 0.0:
		_scan_elapsed = maxf(behavior.scan_interval,0.05)
		if current_state != State.ATTACK and behavior.auto_find_enemies:
			var best := behavior.detection_radius
			var candidate: Node3D
			var attack_candidate: Node3D
			var best_attack_distance := INF
			var attacks_for_scan := _available_attacks()
			for actor: Node in get_tree().get_nodes_in_group(&"physical_characters_3d"):
				if not _is_enemy(actor): continue
				var distance := _horizontal_distance_to(_enemy_position(actor))
				if distance > behavior.detection_radius or absf(_enemy_position(actor).y-_get_navigation_origin_position().y) > behavior.maximum_vertical_difference or not _visible(actor): continue
				if distance <= best:
					candidate = actor
					best = distance
				for attack: ATTACK in attacks_for_scan:
					if float(_cooldowns.get(attack,0.0)) <= 0.0 and distance >= attack.minimum_range and distance <= attack.maximum_range and distance < best_attack_distance:
						attack_candidate = actor
						best_attack_distance = distance
			var previous := _enemy
			if attack_candidate != null: _enemy = attack_candidate
			elif _enemy == null: _enemy = candidate
			if _enemy != previous: _prediction_distance_sample = -1
			if _enemy != previous and _enemy != null: _log_state_event(&"target_acquired",{"target":str(_enemy.get_path()),"target_part":str(_enemy_torso(_enemy).get_path()),"distance":_horizontal_distance_to(_enemy_position(_enemy))})
			if debug_logging_enabled: print("[npc_combat] npc=",get_parent().name," target=",_enemy.name if _enemy != null else &"none")
	if _enemy == null:
		_attack_block_reason = &"no_enemy"
		_distance_attack = null
		_distance_error = 0.0
		change_state(State.IDLE)
		return
	if current_state != State.ATTACK or not is_instance_valid(_target) or _target.get("is_broken") == true:
		if current_state == State.ATTACK: _cancel_attack(); change_state(State.WAITING)
		_target = _enemy_torso(_enemy)
	var distance := _horizontal_distance_to(_target.global_position)
	var attacks := _available_attacks()
	var reposition := _plan_attack_distance(distance, attacks)
	if current_state == State.ATTACK:
		_attack_elapsed += delta
		if not is_instance_valid(_attack_receiver) or not _attack_receiver.is_npc_attack_active() or _attack_elapsed >= _active_attack.maximum_duration:
			_cancel_attack()
			change_state(State.WAITING)
		return
	if _attack_retry <= 0.0:
		if _try_attack(distance): return
		if _attack_block_reason == &"prediction_misses" and not reposition:
			_prediction_distance_sample += 1
			reposition = _plan_attack_distance(distance,attacks)
	change_state(State.MOVE_TO_TARGET if reposition else State.WAITING)

func _predict_attack(attack: ATTACK, target: Node3D) -> Dictionary:
	if not attack.prediction_enabled: return {"hit":true,"reason":&"prediction_disabled","confidence":1.0}
	var receiver := get_parent().get_node_or_null(attack.receiver_path)
	if receiver == null or not receiver.has_method("predict_npc_attack"): return {"hit":false,"reason":&"receiver_has_no_prediction"}
	var started := Time.get_ticks_usec()
	var result: Dictionary = receiver.predict_npc_attack(attack.action_id,target,attack.charge_time,attack.prediction_samples,attack.prediction_margin)
	result["duration_usec"] = Time.get_ticks_usec()-started
	return result

func _attack_target_candidates() -> Array[Node3D]:
	var result: Array[Node3D] = []
	if _enemy.has_method("_get_physical_body_parts"):
		for part: RigidBody3D in _enemy._get_physical_body_parts():
			if not part.is_broken and 0 in part.tags: result.append(part)
	var origin := _get_navigation_origin_position()
	result.sort_custom(func(a: Node3D,b: Node3D) -> bool: return origin.distance_squared_to(a.global_position)<origin.distance_squared_to(b.global_position))
	if result.is_empty(): result.append(_enemy_torso(_enemy))
	if result.size()>4: result.resize(4)
	return result

func _try_attack(_distance: float) -> bool:
	_attack_block_reason = &"none"
	_attack_retry = maxf(behavior.scan_interval,0.05)
	_attack_predictions.clear()
	var choices: Array[Dictionary] = []
	var weight := 0.0
	var targets := _attack_target_candidates()
	for attack: ATTACK in _available_attacks():
		if float(_cooldowns.get(attack,0.0)) > 0.0: continue
		for target: Node3D in targets:
			var distance := _horizontal_distance_to(target.global_position)
			if distance < attack.minimum_range or distance > attack.maximum_range or absf(target.global_position.y-_get_navigation_origin_position().y)>behavior.maximum_vertical_difference or not _visible(_enemy,target): continue
			var prediction := _predict_attack(attack,target)
			var row := prediction.duplicate()
			row["attack"] = attack.action_id
			row["target_part"] = str(target.get_path())
			_attack_predictions.append(row)
			if not prediction.get("hit",false): continue
			var score := attack.selection_weight*clampf(float(prediction.get("confidence",1.0)),0.01,1.0)
			choices.append({"attack":attack,"target":target,"weight":score})
			weight += score
			break
	if choices.is_empty() or weight <= 0.0:
		_attack_block_reason = &"prediction_misses" if not _attack_predictions.is_empty() else &"range_cooldown_or_receiver"
		if not _attack_predictions.is_empty(): _log_state_event(&"attack_prediction",{"results":_attack_predictions})
		return false
	var roll := randf()*weight
	var choice: Dictionary = choices[-1]
	for candidate: Dictionary in choices:
		roll -= float(candidate.weight)
		if roll <= 0.0:
			choice = candidate
			break
	var selected: ATTACK = choice.attack
	var prediction := _predict_attack(selected,choice.target)
	if not prediction.get("hit",false):
		_attack_block_reason = &"prediction_recheck_failed"
		return false
	_target = choice.target
	var distance := _horizontal_distance_to(_target.global_position)
	_log_state_event(&"attack_prediction",{"attack":selected.action_id,"target_part":str(_target.get_path()),"result":prediction})
	var receiver := get_parent().get_node(selected.receiver_path)
	if not receiver.try_start_npc_attack(selected.action_id,_target,selected.charge_time):
		_attack_block_reason = &"receiver_rejected"
		_log_state_event(&"attack_rejected",{"attack":selected.action_id,"receiver":str(receiver.get_path()),"distance":distance})
		return false
	_active_attack = selected
	_prediction_distance_sample = -1
	_attack_receiver = receiver
	_attack_elapsed = 0.0
	_cooldowns[selected] = selected.cooldown
	change_state(State.ATTACK)
	_log_state_event(&"attack_started",{"attack":selected.action_id,"target":str(_enemy.get_path()),"target_part":str(_target.get_path()),"distance":distance})
	if debug_logging_enabled: print("[npc_combat] npc=",get_parent().name," attack=",selected.action_id," distance=",distance)
	return true

func _cancel_attack() -> void:
	if _active_attack != null:
		_log_state_event(&"attack_ended",{"attack":_active_attack.action_id,"elapsed":_attack_elapsed,"receiver_active":is_instance_valid(_attack_receiver) and _attack_receiver.is_npc_attack_active()})
	if is_instance_valid(_attack_receiver): _attack_receiver.cancel_npc_attack()
	_attack_receiver = null
	_active_attack = null
	_attack_elapsed = 0.0

func _get_navigation_origin_position() -> Vector3:
	return _navigation_origin.global_position if is_instance_valid(_navigation_origin) else global_position

func _horizontal_distance_to(target_position: Vector3) -> float:
	var offset := target_position - _get_navigation_origin_position()
	offset.y = 0.0
	return offset.length()

func _navigation_map_is_ready() -> bool:
	var navigation_map := navigation_agent.get_navigation_map()
	return (
		navigation_map.is_valid()
		and NavigationServer3D.map_get_iteration_id(navigation_map) > 0
		and not NavigationServer3D.map_get_regions(navigation_map).is_empty()
	)

func _project_to_navigation_map(world_position: Vector3) -> Vector3:
	if not _navigation_map_is_ready():
		return world_position
	if _performance_tracking_enabled:
		_performance_map_projections += 1
	return NavigationServer3D.map_get_closest_point(
		navigation_agent.get_navigation_map(),
		world_position
	)

func set_performance_tracking_enabled(enabled: bool) -> void:
	_performance_tracking_enabled = enabled
	_reset_performance_stats()

func is_performance_tracking_enabled() -> bool:
	return _performance_tracking_enabled

func consume_performance_stats() -> Dictionary:
	var result := {
		&"physics_frames": _performance_physics_frames,
		&"target_refreshes": _performance_target_refreshes,
		&"repaths": _performance_repaths,
		&"map_projections": _performance_map_projections,
		&"total_usec": _performance_total_usec,
		&"max_usec": _performance_max_usec,
	}
	_reset_performance_stats()
	return result

func _reset_performance_stats() -> void:
	_performance_physics_frames = 0
	_performance_target_refreshes = 0
	_performance_repaths = 0
	_performance_map_projections = 0
	_performance_total_usec = 0
	_performance_max_usec = 0

func _update_debug_log(delta: float) -> void:
	if not debug_logging_enabled:
		return
	_debug_elapsed += delta
	if _debug_elapsed < debug_log_interval:
		return
	_debug_elapsed = 0.0
	var origin := _get_navigation_origin_position()
	var source_target := _target.global_position if is_instance_valid(_target) else _requested_target_position
	var path := navigation_agent.get_current_navigation_path()
	var path_index := navigation_agent.get_current_navigation_path_index()
	var next_path_position := (
		path[clampi(path_index, 0, path.size() - 1)]
		if not path.is_empty()
		else origin
	)
	var movement_direction := next_path_position - origin
	movement_direction.y = 0.0
	if movement_direction.is_zero_approx():
		movement_direction = _requested_target_position - origin
		movement_direction.y = 0.0
	if not movement_direction.is_zero_approx():
		movement_direction = movement_direction.normalized()
	print(
		"[npc_navigation] npc=", get_parent().name,
		" state=", State.keys()[current_state],
		" map_iteration=", NavigationServer3D.map_get_iteration_id(navigation_agent.get_navigation_map()),
		" agent_position=", global_position,
		" origin_position=", origin,
		" source_target=", source_target,
		" projected_target=", _requested_target_position,
		" next_path_position=", next_path_position,
		" movement_direction=", movement_direction,
		" distance_to_next=", _horizontal_distance_from(origin, next_path_position),
		" distance_to_target=", _horizontal_distance_from(origin, _requested_target_position),
		" path_index=", path_index,
		" path_points=", path.size(),
		" finished=", navigation_agent.is_navigation_finished(),
		" reachable=", navigation_agent.is_target_reachable()
	)

func _horizontal_distance_from(from: Vector3, to: Vector3) -> float:
	var offset := to - from
	offset.y = 0.0
	return offset.length()
