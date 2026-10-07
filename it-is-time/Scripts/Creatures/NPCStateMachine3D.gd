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
var _attack_gate_rejections: Array[Dictionary] = []
var _prediction_distance_sample := -1
var _navigation_arrival_distance: float = 0.75
var _last_navigation_request: Vector3
var _last_navigation_map: RID
var _last_navigation_iteration: int = -1
var _collision_stop_frame := -1
var _collision_stop_target: Node3D
var _collision_stop_distance := 0.0

@export_group("State")
@export var initial_state: State = State.IDLE
@export var auto_start_when_target_exists: bool = true
@export var use_fast_movement: bool = false

@export_group("Humanoid Combat Positioning")
## Keep body facing on world +/-X; align attack lanes by walking along Z.
@export var humanoid_xz_positioning: bool = false
@export_range(0.01, 5.0, 0.01) var attack_z_tolerance: float = 0.5
@export_range(0.0, 2.0, 0.01) var facing_x_dead_zone: float = 0.1
@export_range(0.0, 2.0, 0.01) var body_clearance: float = 0.25
@export var include_limbs_and_equipment_in_standoff: bool = true
## Outside the alignment band, only a successful hit prediction permits an attack.
@export_range(0.01, 5.0, 0.01) var predicted_attack_z_tolerance: float = 1.5
@export_range(0.1, 10.0, 0.1) var approach_slowdown_distance: float = 2.0
@export_range(0.1, 50.0, 0.1) var approach_braking_acceleration: float = 8.0

@export_group("Friendly Avoidance")
@export var friendly_avoidance_enabled: bool = true
@export_range(0.05, 1.0, 0.01) var friendly_scan_interval: float = 0.15
@export_range(0.5, 20.0, 0.1) var friendly_detection_radius: float = 6.0
@export_range(0.1, 10.0, 0.1) var friendly_clearance: float = 2.5
@export_range(0.0, 2.0, 0.05) var friendly_steering_strength: float = 1.0
@export_range(0.0, 2.0, 0.05) var friendly_lookahead_seconds: float = 0.5
@export_range(0.1, 3.0, 0.05) var friendly_approach_spacing: float = 0.8

var _friendly_scan_elapsed: float = 0.0
var _friendly_neighbors: Array[Node3D] = []
var _friendly_steering: Vector3 = Vector3.ZERO
var _friendly_approach_offset: float = 0.0

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
	_update_friendly_neighbors(delta)
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
	if current_state != State.MOVE_TO_TARGET: _friendly_steering = Vector3.ZERO
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
	var flight := get_parent().get_node_or_null("BirdFlightController3D")
	if flight != null and flight.is_airborne():
		# Airborne navigation follows the combat destination on XZ, not ground mesh paths.
		return (_requested_target_position-_get_navigation_origin_position()).slide(Vector3.UP).normalized()
	if not _navigation_map_is_ready() or navigation_agent.is_navigation_finished():
		return Vector3.ZERO
	var origin := _get_navigation_origin_position()
	var next_position := navigation_agent.get_next_path_position()
	var direction := next_position - origin
	direction.y = 0.0
	if direction.is_zero_approx():
		direction = _requested_target_position - origin
		direction.y = 0.0
	return _apply_friendly_avoidance(direction.normalized()) if not direction.is_zero_approx() else Vector3.ZERO

func _is_friendly(actor: Variant) -> bool:
	if not is_instance_valid(actor) or not actor is Node3D or not actor.is_inside_tree() or actor.is_queued_for_deletion() or actor == get_parent(): return false
	return actor.get_world_3d() == get_world_3d() and actor.has_method("get_faction_id") and get_parent().has_method("get_faction_id") and actor.get_faction_id() == get_parent().get_faction_id() and actor.has_method("is_combat_alive") and actor.is_combat_alive()

func _update_friendly_neighbors(delta: float) -> void:
	_friendly_scan_elapsed -= delta
	if not friendly_avoidance_enabled:
		_friendly_neighbors.clear()
		_friendly_approach_offset = 0.0
		_friendly_steering = Vector3.ZERO
		return
	if _friendly_scan_elapsed > 0.0: return
	_friendly_scan_elapsed = friendly_scan_interval
	_friendly_neighbors.clear()
	var origin := _get_navigation_origin_position()
	for actor: Node in get_tree().get_nodes_in_group(&"physical_characters_3d"):
		if not _is_friendly(actor): continue
		var point := _enemy_position(actor)
		if absf(point.y-origin.y) > friendly_clearance: continue
		if point.slide(Vector3.UP).distance_to(origin.slide(Vector3.UP)) <= friendly_detection_radius:
			_friendly_neighbors.append(actor)
	# Deterministic ranks keep allies approaching the same enemy on separate Z lanes.
	# Only peers on our side of the enemy compete; facing still uses the enemy's X.
	if current_state == State.ATTACK: return
	_friendly_approach_offset = 0.0
	if not humanoid_xz_positioning or _manual_command or not is_instance_valid(_enemy): return
	var rank := 0
	var target_x := _enemy_position(_enemy).x
	for machine: Node in get_tree().get_nodes_in_group(&"npc_state_machines"):
		if machine == self or not _is_friendly(machine.get_parent()): continue
		if not machine.enabled or not machine._character_enabled or not machine.humanoid_xz_positioning or machine._manual_command or machine._enemy != _enemy: continue
		if signf(machine._get_navigation_origin_position().x-target_x) != signf(origin.x-target_x): continue
		if machine.get_instance_id() < get_instance_id(): rank += 1
	if rank > 0:
		_friendly_approach_offset = ceilf(float(rank)/2.0) * friendly_approach_spacing * (1.0 if rank % 2 == 1 else -1.0)

func _apply_friendly_avoidance(direction: Vector3) -> Vector3:
	_friendly_steering = Vector3.ZERO
	# Keep charged swings and their follow-through independent of crowd steering.
	if not friendly_avoidance_enabled or current_state != State.MOVE_TO_TARGET or direction.is_zero_approx(): return direction
	var origin := _get_navigation_origin_position()
	var lateral := direction.cross(Vector3.UP).normalized()
	var obstruction := 0.0
	for actor: Node3D in _friendly_neighbors:
		if not _is_friendly(actor): continue
		var anchor := _enemy_torso(actor)
		var relative := (anchor.global_position-origin).slide(Vector3.UP)
		var distance := relative.length()
		var predicted := relative
		if anchor is RigidBody3D and _navigation_origin is RigidBody3D:
			predicted += ((anchor as RigidBody3D).linear_velocity-(_navigation_origin as RigidBody3D).linear_velocity).slide(Vector3.UP) * friendly_lookahead_seconds
		var closest := minf(distance,predicted.length())
		if closest >= friendly_clearance or relative.dot(direction) < -friendly_clearance * 0.5: continue
		var side := -signf(relative.dot(lateral))
		if absf(relative.dot(lateral)) < 0.15:
			# Both movers pass on their right; coincident bodies use an ID tie-break.
			side = 1.0 if distance > 0.1 or get_parent().get_instance_id() < actor.get_instance_id() else -1.0
		var weight := 1.0-clampf(closest/friendly_clearance,0.0,1.0)
		_friendly_steering += lateral * side * weight
		obstruction = maxf(obstruction,weight)
	_friendly_steering = _friendly_steering.limit_length(1.0) * friendly_steering_strength
	return (direction * maxf(0.25,1.0-obstruction) + _friendly_steering).normalized()

func get_friendly_avoidance_diagnostics() -> Dictionary:
	return {"npc_path":str(get_parent().get_path()),"enabled":friendly_avoidance_enabled,"neighbors":_friendly_neighbors.size(),"steering":_friendly_steering,"approach_z_offset":_friendly_approach_offset,"scan_interval":friendly_scan_interval,"suppressed_for_attack":current_state == State.ATTACK}

func is_fast_movement_requested() -> bool:
	return current_state == State.MOVE_TO_TARGET and use_fast_movement

func get_npc_movement_speed_scale(full_speed: float) -> float:
	if not humanoid_xz_positioning or _manual_command: return 1.0
	if not enabled or not _character_enabled or current_state != State.MOVE_TO_TARGET or not _has_requested_target: return 0.0
	var remaining := (_requested_target_position-_get_navigation_origin_position()).slide(Vector3.UP).length()
	var braking_speed := sqrt(2.0 * approach_braking_acceleration * remaining)
	return clampf(minf(remaining / approach_slowdown_distance, braking_speed / maxf(full_speed,0.001)),0.0,1.0)

func set_diagnostic_logging_enabled(enabled: bool) -> void:
	debug_logging_enabled = enabled
	_debug_elapsed = debug_log_interval if enabled else 0.0

func _set_agent_target(target_position: Vector3) -> void:
	# Navigation must not stop outside the attack's distance tolerance.
	navigation_agent.target_desired_distance = maxf(minf(_navigation_arrival_distance, _distance_attack.distance_tolerance*0.5),0.01) if behavior != null and not _manual_command and _distance_attack != null else _navigation_arrival_distance
	if humanoid_xz_positioning and behavior != null and not _manual_command:
		navigation_agent.target_desired_distance = minf(navigation_agent.target_desired_distance, maxf(attack_z_tolerance * 0.5, 0.005))
	var map := navigation_agent.get_navigation_map()
	var iteration := NavigationServer3D.map_get_iteration_id(map) if map.is_valid() else 0
	# Keep the current projection while the requested destination is within the existing repath tolerance.
	if _has_requested_target and map == _last_navigation_map and iteration == _last_navigation_iteration and _last_navigation_request.distance_to(target_position) < maxf(target_repath_distance, 0.000001): return
	_last_navigation_request = target_position
	_last_navigation_map = map
	_last_navigation_iteration = iteration
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
	var origin := _get_navigation_origin_position()
	if is_instance_valid(_navigation_origin) and _navigation_origin.is_inside_tree():
		var flight := get_parent().get_node_or_null("BirdFlightController3D")
		# Airborne direction uses the physical origin; ground-map projection is only needed for a detour.
		global_position = origin if flight != null and flight.is_airborne() else _project_to_navigation_map(origin)

func set_character_control_enabled(value: bool) -> void:
	_character_enabled = value
	if not value:
		_cancel_attack()
		change_state(State.IDLE)

func _is_enemy(actor: Variant) -> bool:
	# Group membership spans the SceneTree, including independent SubViewport worlds.
	if not is_instance_valid(actor) or not actor is Node3D or not actor.is_inside_tree() or actor.get_world_3d() != get_world_3d(): return false
	return get_parent().has_method("get_faction_id") and is_instance_valid(actor) and actor != get_parent() and not actor.is_queued_for_deletion() and actor.has_method("get_faction_id") and actor.has_method("is_combat_alive") and actor.is_combat_alive() and actor.get_faction_id() != get_parent().get_faction_id()

func is_jump_requested() -> bool: return false

func get_generated_facing_direction(_delta: float) -> Vector3:
	if not enabled or not _character_enabled or not _is_enemy(_enemy): return Vector3.ZERO
	return (_enemy_position(_enemy)-_get_navigation_origin_position()).slide(Vector3.UP).normalized()

func get_npc_body_facing_direction() -> Vector3:
	if not humanoid_xz_positioning: return get_generated_facing_direction(0.0)
	if not enabled or not _character_enabled or not _is_enemy(_enemy): return Vector3.ZERO
	var target := _target if is_instance_valid(_target) and _target.get("is_broken") != true else _enemy_torso(_enemy)
	var dx := target.global_position.x - _get_navigation_origin_position().x
	return Vector3.RIGHT * signf(dx) if absf(dx) > facing_x_dead_zone else Vector3.ZERO

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

func _attack_in_range(attack: ATTACK, target: Node3D, horizontal_distance: float) -> bool:
	var receiver := get_parent().get_node_or_null(attack.receiver_path)
	if receiver != null and receiver.has_method("is_npc_target_in_attack_range"):
		return receiver.is_npc_target_in_attack_range(attack.action_id,target)
	return horizontal_distance>=attack.minimum_range and horizontal_distance<=_attack_maximum_range(attack,target)

func _attack_maximum_range(attack: ATTACK, target: Node3D) -> float:
	var receiver := get_parent().get_node_or_null(attack.receiver_path)
	if humanoid_xz_positioning and attack.prediction_enabled and is_instance_valid(target) and receiver != null and receiver.has_method("get_npc_attack_maximum_range"):
		return maxf(attack.maximum_range, receiver.get_npc_attack_maximum_range(attack.action_id,target))
	return attack.maximum_range

func _preferred_attack_distance(attack: ATTACK) -> float:
	var desired := attack.preferred_distance if attack.preferred_distance >= 0.0 else behavior.preferred_distance
	# Keep the stop band inside the legal attack interval.
	var margin := minf(attack.distance_tolerance, (attack.maximum_range-attack.minimum_range)*0.5)
	var minimum := attack.minimum_range + margin
	if humanoid_xz_positioning: minimum = maxf(minimum, _minimum_body_standoff() + margin)
	var maximum := _attack_maximum_range(attack,_target) - margin
	# An impossible attack range must never make the character push into another body.
	if minimum > maximum: return minimum
	if humanoid_xz_positioning and include_limbs_and_equipment_in_standoff:
		# Limb/weapon envelopes can overlap the attack range. Approach its far
		# edge instead of making the attack unreachable or overriding prediction.
		minimum = maxf(minimum, minf(_minimum_character_standoff() + margin, maximum))
	if _prediction_distance_sample >= 0:
		return lerpf(minimum,maximum,float(_prediction_distance_sample%5)/4.0)
	return clampf(desired, minimum, maximum)

func _body_x_reach(body: Node3D, direction: float) -> float:
	var reach := 0.0
	for child: Node in body.get_children():
		if not child is CollisionShape3D or child.disabled or child.shape == null: continue
		var bounds: AABB = AABB(-child.shape.size * 0.5, child.shape.size) if child.shape is BoxShape3D else child.shape.get_debug_mesh().get_aabb()
		var half := bounds.size * 0.5
		var pose: Transform3D = child.global_transform
		var center: Vector3 = pose * bounds.get_center()
		var extent := absf(pose.basis.x.x)*half.x + absf(pose.basis.y.x)*half.y + absf(pose.basis.z.x)*half.z
		reach = maxf(reach, direction*(center.x-body.global_position.x)+extent)
	return reach

func _minimum_body_standoff() -> float:
	if not is_instance_valid(_target): return 0.0
	var actor := get_parent()
	var own: Node3D = actor.get_nearest_combat_torso(_target.global_position) if actor.has_method("get_nearest_combat_torso") else _navigation_origin
	if not is_instance_valid(own): return 0.0
	var side := signf(_target.global_position.x-own.global_position.x)
	if is_zero_approx(side): side = 1.0
	return _body_x_reach(own,side) + _body_x_reach(_target,-side) + body_clearance

func _character_x_reach(actor: Node3D, anchor: Node3D, side: float) -> float:
	var reach := _body_x_reach(anchor, side)
	if actor.has_method("_get_physical_body_parts"):
		for body: RigidBody3D in actor._get_physical_body_parts():
			if body is PhysicalBodyPart3D and body.is_broken: continue
			reach = maxf(reach, side * (body.global_position.x - anchor.global_position.x) + _body_x_reach(body, side))
	var inventory := actor.get_node_or_null("InventoryController3D")
	if inventory != null and inventory.has_method("get_equipped_item"):
		var item: Node3D = inventory.get_equipped_item()
		if is_instance_valid(item):
			reach = maxf(reach, side * (item.global_position.x - anchor.global_position.x) + _body_x_reach(item, side))
	return reach

func _minimum_character_standoff() -> float:
	if not is_instance_valid(_target) or not is_instance_valid(_enemy): return _minimum_body_standoff()
	var frame := Engine.get_physics_frames()
	if _collision_stop_frame == frame and _collision_stop_target == _target: return _collision_stop_distance
	var actor := get_parent()
	var own: Node3D = actor.get_nearest_combat_torso(_target.global_position) if actor.has_method("get_nearest_combat_torso") else _navigation_origin
	if not is_instance_valid(own): return _minimum_body_standoff()
	var side := signf(_target.global_position.x - own.global_position.x)
	if is_zero_approx(side): side = 1.0
	_collision_stop_distance = _character_x_reach(actor, own, side) + _character_x_reach(_enemy, _target, -side) + body_clearance
	_collision_stop_frame = frame
	_collision_stop_target = _target
	return _collision_stop_distance

func _target_z_attack_ready(attack: ATTACK, target: Node3D) -> bool:
	if not humanoid_xz_positioning: return true
	var limit := maxf(attack_z_tolerance,predicted_attack_z_tolerance) if attack.prediction_enabled else attack_z_tolerance
	return absf(target.global_position.z-_get_navigation_origin_position().z) <= limit

func _plan_attack_distance(distance: float, attacks: Array[ATTACK]) -> bool:
	if humanoid_xz_positioning and is_instance_valid(_target):
		distance = absf(_target.global_position.x - _get_navigation_origin_position().x)
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
	if humanoid_xz_positioning:
		var origin := _get_navigation_origin_position()
		var target_position := _target.global_position
		var lane_limit := maxf(0.0,(predicted_attack_z_tolerance if _distance_attack.prediction_enabled else attack_z_tolerance)-0.1)
		target_position.z += clampf(_friendly_approach_offset,-lane_limit,lane_limit) if friendly_avoidance_enabled else 0.0
		var z_error := target_position.z - origin.z
		if absf(_distance_error) <= tolerance and absf(z_error) <= attack_z_tolerance: return false
		var goal := origin
		# Within the X stop band, move only along Z rather than orbiting the enemy.
		if absf(_distance_error) > tolerance:
			var side := signf(origin.x - target_position.x)
			if is_zero_approx(side): side = -1.0
			goal.x = target_position.x + side * desired
		goal.z = target_position.z
		_set_agent_target(goal)
		return true
	if absf(_distance_error) <= tolerance: return false
	var away := (_get_navigation_origin_position()-_target.global_position).slide(Vector3.UP).normalized()
	if away.is_zero_approx(): away = Vector3.LEFT
	_set_agent_target(_target.global_position + away*desired)
	return true

func get_attack_range_diagnostics() -> Dictionary:
	var ranges: Array[Dictionary] = []
	var facing := get_parent().get_node_or_null("PhysicalFacingController3D")
	var alignment := {}
	if facing != null and facing.has_method("is_npc_facing_ready"):
		alignment = {"ready":facing.is_npc_facing_ready(get_npc_body_facing_direction()), "turning":facing.is_turning(), "error_degrees":rad_to_deg(facing.get_turn_angle_error()), "attack_tolerance":facing.npc_attack_angle_tolerance}
	var distance := _horizontal_distance_to(_target.global_position) if is_instance_valid(_target) else -1.0
	var inside := false
	for attack: ATTACK in _available_attacks():
		if is_instance_valid(_target) and _attack_in_range(attack,_target,distance): inside = true
		ranges.append({"action":attack.action_id,"minimum":attack.minimum_range,"maximum":_attack_maximum_range(attack,_target),"configured_maximum":attack.maximum_range,
			"preferred":_preferred_attack_distance(attack),"cooldown":float(_cooldowns.get(attack,0.0))})
	return {"ranges":ranges,"predictions":_attack_predictions,"gate_rejections":_attack_gate_rejections,"body_alignment":alignment,"target_part":str(_target.get_path()) if is_instance_valid(_target) else "none",
		"minimum_body_standoff":_minimum_body_standoff() if humanoid_xz_positioning else 0.0,
		"limb_equipment_standoff":_minimum_character_standoff() if humanoid_xz_positioning else 0.0,
		"collision_envelope_exceeds_attack_range":humanoid_xz_positioning and _distance_attack != null and _minimum_character_standoff() > _attack_maximum_range(_distance_attack,_target),
		"predicted_z_tolerance":predicted_attack_z_tolerance,
		"humanoid_xz_positioning":humanoid_xz_positioning,"z_error":_target.global_position.z-_get_navigation_origin_position().z if is_instance_valid(_target) else 0.0,"z_tolerance":attack_z_tolerance,
		"distance":distance,"inside_attack_range":inside,
		"distance_attack":_distance_attack.action_id if _distance_attack != null else &"none","distance_error":_distance_error}

func _visible(actor: Node3D, target_part: Node3D = null) -> bool:
	if not behavior.require_line_of_sight: return true
	var excluded: Array[RID] = []
	for character: Node3D in [get_parent(), actor]:
		if character.has_method("get_physical_body_rids"):
			excluded.append_array(character.get_physical_body_rids())
		else:
			for body: Node in character.find_children("*", "PhysicsBody3D", true, false): excluded.append(body.get_rid())
	var point := target_part.global_position if is_instance_valid(target_part) else _enemy_position(actor)
	var query := PhysicsRayQueryParameters3D.create(_get_navigation_origin_position(), point, behavior.obstacle_mask, excluded)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _update_combat(delta: float) -> void:
	for key in _cooldowns: _cooldowns[key] = maxf(float(_cooldowns[key])-delta, 0.0)
	_attack_retry = maxf(_attack_retry-delta,0.0)
	_scan_elapsed -= delta
	if not _is_enemy(_enemy):
		if is_instance_valid(_enemy): _log_state_event(&"target_lost",{"target":str(_enemy.get_path()),"reason":"dead_friendly_removed_or_other_world"})
		_cancel_attack()
		_enemy = null
		_prediction_distance_sample = -1
		_attack_predictions.clear()
		_target = null
		_has_requested_target = false
	if _scan_elapsed <= 0.0:
		_scan_elapsed = maxf(behavior.scan_interval,0.05)
		if current_state != State.ATTACK and behavior.auto_find_enemies:
			var best := INF
			var candidate: Node3D
			var attack_candidate: Node3D
			var best_attack_distance := INF
			var attacks_for_scan := _available_attacks()
			for actor: Node in get_tree().get_nodes_in_group(&"physical_characters_3d"):
				if not _is_enemy(actor): continue
				var distance := _horizontal_distance_to(_enemy_position(actor))
				# Perception is scene-wide; height, walls and range restrict attacks, not awareness.
				if distance <= best:
					candidate = actor
					best = distance
				for attack: ATTACK in attacks_for_scan:
					if float(_cooldowns.get(attack,0.0)) <= 0.0 and _attack_in_range(attack,_enemy_torso(actor),distance) and distance < best_attack_distance:
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
	_attack_gate_rejections.clear()
	if humanoid_xz_positioning and is_instance_valid(_target) and absf(_target.global_position.z-_get_navigation_origin_position().z) > maxf(attack_z_tolerance,predicted_attack_z_tolerance):
		_attack_block_reason = &"z_alignment_pending"
		return false
	var facing := get_parent().get_node_or_null("PhysicalFacingController3D")
	if facing != null and facing.has_method("is_npc_facing_ready") and not facing.is_npc_facing_ready(get_npc_body_facing_direction()):
		_attack_block_reason = &"body_turn_pending"
		return false
	var choices: Array[Dictionary] = []
	var weight := 0.0
	var targets := _attack_target_candidates()
	var available := _available_attacks()
	if available.is_empty():
		_attack_block_reason = &"no_usable_attack"
		return false
	for attack: ATTACK in available:
		if float(_cooldowns.get(attack,0.0)) > 0.0:
			_attack_gate_rejections.append({"attack":attack.action_id,"reason":&"cooldown"})
			continue
		for target: Node3D in targets:
			if not _target_z_attack_ready(attack,target):
				_attack_gate_rejections.append({"attack":attack.action_id,"target":str(target.get_path()),"reason":&"z_alignment_pending"})
				continue
			var distance := _horizontal_distance_to(target.global_position)
			var rejection: StringName = &""
			if not _attack_in_range(attack,target,distance): rejection = &"out_of_range"
			elif absf(target.global_position.y-_get_navigation_origin_position().y)>behavior.maximum_vertical_difference: rejection = &"vertical_difference"
			elif not _visible(_enemy,target): rejection = &"line_of_sight_blocked"
			if rejection != &"":
				_attack_gate_rejections.append({"attack":attack.action_id,"target":str(target.get_path()),"reason":rejection,"distance":distance,"maximum":_attack_maximum_range(attack,target)})
				continue
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
		_attack_block_reason = &"prediction_misses" if not _attack_predictions.is_empty() else (_attack_gate_rejections[0].reason if not _attack_gate_rejections.is_empty() else &"range_cooldown_or_receiver")
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
	# Regeneration removes the old Torso before the next navigation tick.
	if not is_instance_valid(_navigation_origin) or not _navigation_origin.is_inside_tree() or _navigation_origin.is_queued_for_deletion():
		_navigation_origin = get_node_or_null(navigation_origin_path) as Node3D
		if (not is_instance_valid(_navigation_origin) or not _navigation_origin.is_inside_tree() or _navigation_origin.is_queued_for_deletion()) and get_parent().has_method("get_combat_anchor"):
			_navigation_origin = get_parent().get_combat_anchor()
	return _navigation_origin.global_position if is_instance_valid(_navigation_origin) and _navigation_origin.is_inside_tree() else global_position

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
