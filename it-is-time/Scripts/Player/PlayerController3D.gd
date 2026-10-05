extends Node3D

var _control_perf := preload("res://Scripts/Debug/ControlPerformanceStats.gd").new()

signal controlled_character_changed(character: Node3D)
signal wheel_action_requested(action: StringName, character: Node3D)

@export var initial_character: Node3D
@export var camera_rig: Node3D
@export var terrain_cursor: TerrainCursor3D
@export var wheel_action: StringName = &"QPressed"
@export var additional_options: Array[ControllerWheelOption] = []
@export var right_action: StringName = &"Right"
@export var left_action: StringName = &"Left"
@export var up_action: StringName = &"Up"
@export var down_action: StringName = &"Down"
@export var jump_action: StringName = &"Space"
@export var fast_action: StringName = &"Shift"
@export var diagnostic_logging: bool = true

@export_group("Generated Facing")
@export_range(1.0, 179.0, 1.0) var generated_facing_sector_degrees: float = 120.0
@export_range(0.0, 10.0, 0.01) var generated_facing_dead_zone: float = 0.5
@export_range(0.0, 1.0, 0.01) var generated_facing_confirmation_time: float = 0.1
@onready var wheel: CanvasLayer = $ControllerRadialMenu
var _generated_right := Vector3.RIGHT
var _generated_left := false
var _generated_facing_candidate_time := 0.0

var _character: Node3D
var _movement: Node
var _level: Node
var _wheel_target: Node3D
var _ai_snapshot: Array[Dictionary] = []
var _blocked_actions: Dictionary = {}
var _direction: Vector3 = Vector3.ZERO
var _jump: bool = false
var _fast: bool = false
var _was_blocked: bool = false

func _ready() -> void:
	_control_perf.register(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = -100
	process_physics_priority = -100
	add_to_group(&"player_controller_3d")
	_level = self
	while _level.get_parent() != get_tree().root:
		_level = _level.get_parent()
	if initial_character == null: initial_character = get_parent() as Node3D
	if _level == initial_character: _level = get_tree().root
	wheel.option_chosen.connect(_on_wheel_option)
	call_deferred("_initialize_controller")

func _initialize_controller() -> void:
	if terrain_cursor == null:
		terrain_cursor = get_tree().get_first_node_in_group(&"terrain_cursor_3d") as TerrainCursor3D
	if is_instance_valid(camera_rig): camera_rig.follow_target = self
	if not attach_character(initial_character): detach_character()

func get_controlled_character() -> Node3D:
	return _character if is_instance_valid(_character) else null

func is_attached() -> bool:
	return get_controlled_character() != null

func get_control_anchor() -> Node3D:
	var anchor := _find_torso(get_controlled_character())
	return anchor if anchor != null else self

func _find_movement(character: Node3D) -> Node:
	var started: int = _control_perf.start()
	var result: Node = _perf_impl__find_movement(character)
	_control_perf.finish(&"movement_lookup", started)
	return result

func _perf_impl__find_movement(character: Node3D) -> Node:
	if not is_instance_valid(character): return null
	var descendants := character.find_children("*", "", true, false)
	_control_perf.count(&"movement_lookup_nodes", descendants.size())
	for component: Node in descendants:
		if component.has_method("get_leg_parts") and component.has_method("cancel_step"):
			return component
	return null

func _find_torso(character: Node3D) -> RigidBody3D:
	var started: int = _control_perf.start()
	var result: RigidBody3D = _perf_impl__find_torso(character)
	_control_perf.finish(&"anchor_lookup", started)
	return result

func _perf_impl__find_torso(character: Node3D) -> RigidBody3D:
	if not is_instance_valid(character): return null
	var movement := _find_movement(character)
	if movement != null:
		var reference := movement.get_node_or_null(movement.torso_path) as RigidBody3D
		if reference != null and not (reference is PhysicalBodyPart3D and reference.is_broken): return reference
	var largest: RigidBody3D
	for node: Node in character.find_children("*", "PhysicalBodyPart3D", true, false):
		var part := node as PhysicalBodyPart3D
		if part.is_broken or 0 not in part.tags: continue
		if largest == null or part.mass > largest.mass: largest = part
	return largest

func can_attach_character(character: Node3D) -> bool:
	if not is_instance_valid(character) or character.is_queued_for_deletion(): return false
	var damage := character.get_node_or_null("CharacterDamageController3D")
	if damage != null and damage.is_character_disabled(): return false
	return _find_movement(character) != null and _find_torso(character) != null

func attach_character(character: Node3D) -> bool:
	var started: int = _control_perf.start()
	var result: bool = _perf_impl_attach_character(character)
	_control_perf.finish(&"attach", started)
	return result

func _perf_impl_attach_character(character: Node3D) -> bool:
	if not can_attach_character(character): return false
	if character == get_controlled_character(): return true
	_release_character()
	_character = character
	_movement = _find_movement(character)
	_movement.command_source = self
	_generated_right = character.global_basis.x.slide(Vector3.UP).normalized()
	_generated_left = false
	_generated_facing_candidate_time = 0.0
	for node: Node in character.find_children("*", "", true, false):
		if node.is_in_group(&"npc_state_machines"):
			_ai_snapshot.append({"node": node, "physics": node.is_physics_processing(), "process": node.is_processing()})
			node.set_physics_process(false)
			node.set_process(false)
	if get_parent() != character: reparent(character, true)
	global_position = get_control_anchor().global_position
	global_basis = Basis.IDENTITY
	_block_held_attacks()
	if terrain_cursor != null:
		terrain_cursor.bind_control_target(character, get_control_anchor(), true)
	_update_arc()
	controlled_character_changed.emit(character)
	_log("attached", character)
	return true

func detach_character() -> void:
	var departing := get_controlled_character()
	var location := global_position
	_release_character()
	if get_parent() != _level: reparent(_level, true)
	global_position = location
	global_basis = Basis.IDENTITY
	if terrain_cursor != null:
		terrain_cursor.bind_control_target(null, self, false)
		terrain_cursor.set_cursor_world_position(location)
	_update_arc()
	controlled_character_changed.emit(null)
	_log("detached", departing)

func _release_character() -> void:
	_clear_commands_and_actions()
	if is_instance_valid(_movement):
		_movement.command_source = null
		_movement.cancel_step(&"player_detached")
		_movement.set_turn_planning_active(false)
	for snapshot: Dictionary in _ai_snapshot:
		var node: Node = snapshot.node
		if is_instance_valid(node) and (not is_instance_valid(_character) or _character.get_node_or_null("CharacterDamageController3D") == null or not _character.get_node("CharacterDamageController3D").is_character_disabled()):
			node.set_process(snapshot.process)
			node.set_physics_process(snapshot.physics)
	_ai_snapshot.clear()
	_character = null
	_movement = null

func _block_held_attacks() -> void:
	_blocked_actions.clear()
	for action: StringName in InputMap.get_actions():
		if Input.is_action_pressed(action): _blocked_actions[action] = true

func _clear_commands_and_actions() -> void:
	_direction = Vector3.ZERO
	_jump = false
	_fast = false
	if is_instance_valid(_movement): _movement.cancel_step(&"player_input_suspended")
	if is_instance_valid(_character):
		for node: Node in _character.find_children("*", "", true, false):
			if node.has_method("cancel_player_actions"): node.cancel_player_actions()
	_block_held_attacks()

func _external_interface_open() -> bool:
	var started: int = _control_perf.start()
	var result: bool = _perf_impl__external_interface_open()
	_control_perf.finish(&"ui_lookup", started)
	return result

func _perf_impl__external_interface_open() -> bool:
	if get_tree().paused: return true
	for node: Node in get_tree().get_nodes_in_group(&"ui_interface_2d"):
		if node != wheel and node is CanvasLayer and node.visible and not node.is_queued_for_deletion(): return true
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	return console != null and console.is_console_open()

func gameplay_input_allowed() -> bool:
	return is_attached() and not wheel.visible and not _external_interface_open()

func is_gameplay_action_pressed(action: StringName) -> bool:
	return gameplay_input_allowed() and not _blocked_actions.has(action) and Input.is_action_pressed(action)

func get_movement_direction() -> Vector3:
	return _direction if gameplay_input_allowed() else Vector3.ZERO

## Generated bodies own their physical turn planner; this supplies only a heading command.
func get_generated_facing_direction(delta: float) -> Vector3:
	if not gameplay_input_allowed() or terrain_cursor == null:
		_generated_facing_candidate_time = 0.0
		return Vector3.ZERO
	var center := get_control_anchor().global_position
	if _movement != null and _movement.has_method("get_torso_parts"):
		var weighted := Vector3.ZERO
		var mass := 0.0
		for body: RigidBody3D in _movement.get_torso_parts():
			if body is PhysicalBodyPart3D and body.is_broken: continue
			weighted += body.global_position * body.mass
			mass += body.mass
		if mass > 0.0: center = weighted / mass
	var direction := (terrain_cursor.get_target_ground_position() - center).slide(Vector3.UP)
	var opposite := _generated_right if _generated_left else -_generated_right
	var threshold := cos(deg_to_rad(generated_facing_sector_degrees * 0.5))
	if direction.length() > generated_facing_dead_zone and direction.normalized().dot(opposite) >= threshold:
		_generated_facing_candidate_time += delta
		if _generated_facing_candidate_time >= generated_facing_confirmation_time:
			_generated_left = not _generated_left
			_generated_facing_candidate_time = 0.0
	else:
		_generated_facing_candidate_time = 0.0
	return -_generated_right if _generated_left else _generated_right

func is_jump_requested() -> bool:
	return _jump and gameplay_input_allowed()

func is_fast_requested() -> bool:
	return _fast and gameplay_input_allowed()

func _process(_delta: float) -> void:
	var started: int = _control_perf.start()
	_perf_impl__process(_delta)
	_control_perf.finish(&"controller_process", started)

func _perf_impl__process(_delta: float) -> void:
	if wheel.visible and _external_interface_open(): close_wheel(false)
	var blocked := not gameplay_input_allowed()
	if blocked and not _was_blocked: _clear_commands_and_actions()
	_was_blocked = blocked
	if is_attached():
		if not can_attach_character(_character):
			detach_character()
		else:
			global_position = get_control_anchor().global_position
			global_basis = Basis.IDENTITY
			if terrain_cursor != null: terrain_cursor.movement_anchor = get_control_anchor()
	_update_arc()

func _physics_process(_delta: float) -> void:
	var started: int = _control_perf.start()
	_perf_impl__physics_process(_delta)
	_control_perf.finish(&"controller_physics", started)

func _perf_impl__physics_process(_delta: float) -> void:
	for action: StringName in _blocked_actions.keys():
		if not Input.is_action_pressed(action): _blocked_actions.erase(action)
	_direction = Vector3.ZERO
	_jump = false
	_fast = false
	if gameplay_input_allowed():
		_direction = Vector3(Input.get_action_strength(right_action) - Input.get_action_strength(left_action), 0, Input.get_action_strength(down_action) - Input.get_action_strength(up_action)).normalized()
		_jump = Input.is_action_just_pressed(jump_action) and not _blocked_actions.has(jump_action)
		_fast = Input.is_action_pressed(fast_action)
	elif not is_attached() and not wheel.visible and not _external_interface_open() and terrain_cursor != null:
		global_position = terrain_cursor.get_actual_ground_position()

func _input(event: InputEvent) -> void:
	if event.is_action_pressed(wheel_action) and not event.is_echo():
		if not _external_interface_open():
			open_wheel()
			get_viewport().set_input_as_handled()
	elif event.is_action_released(wheel_action) and wheel.visible:
		wheel.hovered_index = wheel.pick_at(get_viewport().get_mouse_position())
		close_wheel(true)
		get_viewport().set_input_as_handled()
	elif wheel.visible and (event is InputEventMouseMotion or event is InputEventMouseButton):
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not gameplay_input_allowed() or event.is_echo(): return
	var inventory := _character.get_node_or_null("InventoryController3D")
	if inventory == null: return
	if event.is_action_pressed(inventory.pickup_action):
		inventory.try_pick_up_nearest_item()
		get_viewport().set_input_as_handled()
	for index: int in range(mini(inventory.capacity, inventory.slot_actions.size())):
		if event.is_action_pressed(inventory.slot_actions[index]):
			inventory.select_slot(index)
			get_viewport().set_input_as_handled()
			break

func open_wheel() -> bool:
	var started: int = _control_perf.start()
	var result: bool = _perf_impl_open_wheel()
	_control_perf.finish(&"wheel_open", started)
	return result

func _perf_impl_open_wheel() -> bool:
	if wheel.visible or _external_interface_open(): return false
	var camera := get_viewport().get_camera_3d()
	var location := get_control_anchor().global_position if is_attached() else (terrain_cursor.global_position if terrain_cursor != null else global_position)
	if camera == null or camera.is_position_behind(location): return false
	_wheel_target = terrain_cursor.get_selected_character() if terrain_cursor != null else null
	var option := ControllerWheelOption.new()
	option.display_name = "弹出" if is_attached() else "接入"
	option.action = &"detach" if is_attached() else &"attach"
	option.enabled = is_attached() or _can_attach_snap_target(_wheel_target)
	var entries: Array[ControllerWheelOption] = [option]
	for extra: ControllerWheelOption in additional_options:
		if extra != null: entries.append(extra)
	_clear_commands_and_actions()
	if is_instance_valid(camera_rig) and camera_rig.has_method("cancel_orbit"):
		camera_rig.cancel_orbit()
	wheel.open_at(camera.unproject_position(location), entries)
	if terrain_cursor != null: terrain_cursor._set_gameplay_cursor_active(false)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().warp_mouse(wheel.screen_center)
	return true

func close_wheel(commit: bool = false) -> void:
	wheel.close_menu(commit and not _external_interface_open())
	if terrain_cursor != null:
		terrain_cursor._set_gameplay_cursor_active(terrain_cursor.input_enabled and not _external_interface_open())
	_block_held_attacks()

func _can_attach_snap_target(character: Node3D) -> bool:
	if not can_attach_character(character) or terrain_cursor == null: return false
	var projection: Dictionary = terrain_cursor._get_character_projection(character)
	if projection.is_empty(): return false
	var center: Vector3 = projection.center
	var radius: float = projection.radius + terrain_cursor.selection_snap_margin + terrain_cursor.selection_release_margin
	return Vector2(global_position.x, global_position.z).distance_to(Vector2(center.x, center.z)) <= radius

func _on_wheel_option(action: StringName) -> void:
	match action:
		&"detach":
			if is_attached(): detach_character()
		&"attach":
			if not is_attached() and _can_attach_snap_target(_wheel_target): attach_character(_wheel_target)
		_:
			wheel_action_requested.emit(action, get_controlled_character())

func _update_arc() -> void:
	for arc: Node in get_tree().get_nodes_in_group(&"terrain_arc_indicator_3d"):
		arc.movement_anchor = get_control_anchor()
		arc.terrain_cursor = terrain_cursor

func _log(event: String, character: Node3D) -> void:
	if diagnostic_logging: print("[player_controller] event=%s character=%s position=%s" % [event, character.name if is_instance_valid(character) else &"none", global_position])

func set_character_control_enabled(enabled: bool) -> void:
	if not enabled:
		close_wheel(false)
		detach_character()

func set_control_performance_tracking_enabled(enabled: bool) -> void:
	_control_perf.set_enabled(enabled)

func consume_control_performance_stats() -> Dictionary:
	return _control_perf.consume()
