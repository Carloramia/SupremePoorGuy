extends Node3D

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

signal state_changed(previous_state: State, current_state: State)

enum State { IDLE, MOVE_TO_TARGET }

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
	var started_usec := Time.get_ticks_usec() if _performance_tracking_enabled else 0
	if auto_find_target_by_group and target_path.is_empty() and PLAYER_CONTEXT.controller(self) != null:
		var player_anchor := PLAYER_CONTEXT.anchor(self)
		if player_anchor != _target: move_to_node(player_anchor)
	_sync_navigation_origin()
	_update_debug_log(delta)
	if current_state == State.MOVE_TO_TARGET:
		if is_instance_valid(_target) and refresh_target_each_physics_frame:
			if _performance_tracking_enabled:
				_performance_target_refreshes += 1
			_set_agent_target(_target.global_position)
		if not _has_requested_target:
			change_state(State.IDLE)
		elif _horizontal_distance_to(_requested_target_position) <= arrival_distance:
			change_state(State.IDLE)
	if _performance_tracking_enabled:
		var elapsed_usec := Time.get_ticks_usec() - started_usec
		_performance_physics_frames += 1
		_performance_total_usec += elapsed_usec
		_performance_max_usec = maxi(_performance_max_usec, elapsed_usec)

func _initialize_navigation() -> void:
	_sync_navigation_origin()
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

func move_to_node(target: Node3D) -> void:
	_target = target
	if is_instance_valid(_target):
		_set_agent_target(_target.global_position)
		change_state(State.MOVE_TO_TARGET)

func move_to_position(target_position: Vector3) -> void:
	_target = null
	_set_agent_target(target_position)
	change_state(State.MOVE_TO_TARGET)

func stop() -> void:
	_has_requested_target = false
	change_state(State.IDLE)

func get_movement_direction() -> Vector3:
	if current_state != State.MOVE_TO_TARGET or not _has_requested_target:
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
	if is_instance_valid(_navigation_origin):
		global_position = _project_to_navigation_map(_navigation_origin.global_position)

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
