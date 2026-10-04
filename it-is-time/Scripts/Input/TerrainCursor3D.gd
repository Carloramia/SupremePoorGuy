class_name TerrainCursor3D
extends Node3D

var _control_perf := preload("res://Scripts/Debug/ControlPerformanceStats.gd").new()

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

signal selection_changed(character: Node3D)

@export_group("Character Selection")
@export var selection_enabled: bool = true
@export var controlled_character: Node3D
@export var selectable_character_group: StringName = &"physical_characters_3d"
@export_range(0.0, 10.0, 0.05, "or_greater") var selection_snap_margin: float = 0.75
@export_range(0.0, 10.0, 0.05, "or_greater") var selection_release_margin: float = 0.5
@export_range(1.0, 3.0, 0.01) var selected_radius_multiplier: float = 1.1
@export var selected_color: Color = Color(1.0, 0.08, 0.05, 0.95)
@export_range(0.02, 1.0, 0.01) var selection_search_interval: float = 0.1

@export_group("Control")
@export var input_enabled: bool = true
@export_range(0.001, 1.0, 0.001, "or_greater") var cursor_sensitivity: float = 0.025
@export_range(0.0, 1000.0, 0.5, "or_greater") var maximum_anchor_distance: float = 30.0
@export var movement_anchor: Node3D
@export var follow_anchor_translation: bool = true
@export var ignore_motion_while_orbiting: bool = true

@export_group("Ground Detection")
@export_flags_3d_physics var terrain_collision_mask: int = 1
@export var terrain_group: StringName = &"navigation_source"
@export_range(0.1, 1000.0, 0.1, "or_greater") var probe_height: float = 30.0
@export_range(0.1, 2000.0, 0.1, "or_greater") var probe_depth: float = 100.0
@export_range(0.0, 1.0, 0.001, "or_greater") var surface_offset: float = 0.03
@export_range(1, 64, 1) var maximum_probe_exclusions: int = 16

@export_group("Smoothing")
@export_range(0.0, 100.0, 0.1, "or_greater") var position_smoothing: float = 20.0
@export_range(0.0, 100.0, 0.1, "or_greater") var normal_smoothing: float = 16.0

var _selected_character: Node3D
var _selected_ground_position: Vector3 = Vector3.ZERO
var _charge_follow_target: Node3D
var _charge_follow_center: Vector2 = Vector2.ZERO
var _selection_search_elapsed: float = INF
var _cursor_visuals: Array[Dictionary] = []

var _pending_mouse_motion: Vector2 = Vector2.ZERO
var _desired_horizontal_position: Vector2 = Vector2.ZERO
var _has_desired_position: bool = false
var _has_ground_hit: bool = false
var _gameplay_cursor_active: bool = false
var _orbiting_camera: bool = false
var _last_anchor: Node3D
var _last_anchor_position: Vector3 = Vector3.ZERO

func _ready() -> void:
	_control_perf.register(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	_resolve_movement_anchor()
	_initialize_selection_visuals()
	_reset_desired_position()
	_set_gameplay_cursor_active(input_enabled and not _is_external_interface_open())

func _exit_tree() -> void:
	if DisplayServer.get_name() != "headless" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _process(_delta: float) -> void:
	var should_be_active := input_enabled and not _is_external_interface_open()
	if should_be_active != _gameplay_cursor_active:
		_set_gameplay_cursor_active(should_be_active)

func _physics_process(delta: float) -> void:
	var started: int = _control_perf.start()
	_perf_impl__physics_process(delta)
	_control_perf.finish(&"cursor_physics", started)

func _perf_impl__physics_process(delta: float) -> void:
	_update_anchor_translation()
	if not _gameplay_cursor_active:
		return
	var camera := get_viewport().get_camera_3d()
	if not is_instance_valid(camera):
		visible = false
		return
	if not _pending_mouse_motion.is_zero_approx():
		var world_motion := get_camera_plane_motion(_pending_mouse_motion, camera)
		_desired_horizontal_position += Vector2(world_motion.x, world_motion.z)
		_pending_mouse_motion = Vector2.ZERO
		_clamp_to_anchor()
	_update_ground_transform(camera, delta)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_RIGHT:
			_orbiting_camera = button_event.pressed
		return
	if (
		event is InputEventMouseMotion
		and _gameplay_cursor_active
		and not _is_external_interface_open()
		and (not ignore_motion_while_orbiting or not _orbiting_camera)
	):
		var motion := (event as InputEventMouseMotion).relative
		if _dispatch_charge_angle_drag(motion):
			return
		_pending_mouse_motion += motion

## All charging Arms receive the same drag; do not consume input when none accepts it.
func _dispatch_charge_angle_drag(motion: Vector2) -> bool:
	if not _charge_input_pressed():
		return false
	var target := get_selected_character()
	if target == null or get_tree().paused:
		return false
	var accepted := false
	for controller: Node in get_tree().get_nodes_in_group(&"limb_swing_controllers"):
		if controller.has_method("adjust_charge_swing_angle"):
			accepted = bool(controller.call("adjust_charge_swing_angle", self, target, motion)) or accepted
	return accepted

func get_camera_plane_motion(mouse_delta: Vector2, camera: Camera3D) -> Vector3:
	if not is_instance_valid(camera):
		return Vector3.ZERO
	var forward := -camera.global_basis.z
	forward.y = 0.0
	if forward.is_zero_approx():
		forward = Vector3.FORWARD
	else:
		forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	return (
		forward * -mouse_delta.y
		+ right * mouse_delta.x
	) * cursor_sensitivity

func set_cursor_world_position(world_position: Vector3) -> void:
	_update_anchor_translation()
	_desired_horizontal_position = Vector2(world_position.x, world_position.z)
	_has_desired_position = true
	_clamp_to_anchor()

func _update_anchor_translation() -> void:
	_resolve_movement_anchor()
	var following_target := _update_charge_target_follow()
	if not is_instance_valid(movement_anchor):
		_last_anchor = null
		return
	var anchor_position := movement_anchor.global_position
	var translated := false
	if movement_anchor == _last_anchor and follow_anchor_translation and not following_target:
		var displacement := anchor_position - _last_anchor_position
		displacement.y = 0.0
		translated = not displacement.is_zero_approx()
		_desired_horizontal_position += Vector2(displacement.x, displacement.z)
		if get_selected_character() == null:
			global_position += displacement
	_last_anchor = movement_anchor
	_last_anchor_position = anchor_position
	if translated:
		_clamp_to_anchor()

func is_gameplay_cursor_active() -> bool:
	return _gameplay_cursor_active

func get_selected_character() -> Node3D:
	return _selected_character if is_instance_valid(_selected_character) else null

func get_mouse_ground_position() -> Vector3:
	_update_anchor_translation()
	return Vector3(_desired_horizontal_position.x, global_position.y, _desired_horizontal_position.y)

func get_target_ground_position() -> Vector3:
	# Outside charging, target movement changes only the selected visual position.
	if get_selected_character() != null and _gameplay_cursor_active:
		return _selected_ground_position
	_update_anchor_translation()
	return Vector3(_desired_horizontal_position.x, global_position.y, _desired_horizontal_position.y)

func has_valid_ground_position() -> bool:
	return _has_ground_hit

func _set_gameplay_cursor_active(active: bool) -> void:
	_gameplay_cursor_active = active
	if not active:
		_set_selected_character(null)
	_selection_search_elapsed = INF
	_pending_mouse_motion = Vector2.ZERO
	_orbiting_camera = false
	visible = active and _has_ground_hit
	if DisplayServer.get_name() == "headless":
		return
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE

func _reset_desired_position() -> void:
	if not is_instance_valid(movement_anchor):
		return
	_desired_horizontal_position = Vector2(
		movement_anchor.global_position.x,
		movement_anchor.global_position.z
	)
	_has_desired_position = true
	_last_anchor = movement_anchor
	_last_anchor_position = movement_anchor.global_position

func _resolve_movement_anchor() -> void:
	if is_instance_valid(movement_anchor):
		return
	movement_anchor = get_tree().get_first_node_in_group(&"npc_navigation_target") as Node3D

func _clamp_to_anchor() -> void:
	if is_instance_valid(_charge_follow_target) or maximum_anchor_distance <= 0.0 or not is_instance_valid(movement_anchor):
		return
	var anchor_position := Vector2(
		movement_anchor.global_position.x,
		movement_anchor.global_position.z
	)
	var offset := _desired_horizontal_position - anchor_position
	if offset.length() > maximum_anchor_distance:
		_desired_horizontal_position = anchor_position + offset.normalized() * maximum_anchor_distance

func _update_ground_transform(camera: Camera3D, delta: float) -> void:
	if not _has_desired_position or get_world_3d() == null:
		visible = false
		return
	var selection := _update_character_selection(delta)
	var display_position := _desired_horizontal_position
	var reference_y := global_position.y
	if not selection.is_empty():
		var center: Vector3 = selection.center
		display_position = Vector2(center.x, center.z)
		reference_y = maxf(reference_y, center.y)
	if is_instance_valid(movement_anchor):
		reference_y = maxf(reference_y, movement_anchor.global_position.y)
	var ray_from := Vector3(
		display_position.x,
		reference_y + probe_height,
		display_position.y
	)
	var result := _find_terrain_hit(ray_from, ray_from + Vector3.DOWN * probe_depth)
	if result.is_empty():
		_has_ground_hit = false
		_set_selected_character(null)
		visible = false
		return
	var surface_normal: Vector3 = result.get(&"normal", Vector3.UP)
	surface_normal = surface_normal.normalized()
	var target_position: Vector3 = result.get(&"position", Vector3.ZERO)
	target_position += surface_normal * surface_offset
	_selected_ground_position = target_position
	var target_basis := _get_surface_basis(surface_normal, camera)
	if not _has_ground_hit or get_selected_character() != null:
		global_transform = Transform3D(target_basis, target_position)
		_has_ground_hit = true
	else:
		var position_weight := _smoothing_weight(position_smoothing, delta)
		var normal_weight := _smoothing_weight(normal_smoothing, delta)
		var smoothed_position := global_position.lerp(target_position, position_weight)
		var current_rotation := global_basis.get_rotation_quaternion()
		var target_rotation := target_basis.get_rotation_quaternion()
		var smoothed_basis := Basis(current_rotation.slerp(target_rotation, normal_weight))
		global_transform = Transform3D(smoothed_basis, smoothed_position)
	visible = true

func _initialize_selection_visuals() -> void:
	for child: Node in get_children():
		if not child is MeshInstance3D:
			continue
		var visual := child as MeshInstance3D
		if visual.mesh == null or not visual.get_active_material(0) is StandardMaterial3D:
			continue
		var material := visual.get_active_material(0).duplicate() as StandardMaterial3D
		visual.material_override = material
		_cursor_visuals.append({"node": visual, "material": material,
			"scale": visual.scale, "color": material.albedo_color, "emission": material.emission})

func _set_selected_character(character: Node3D) -> void:
	var changed := _selected_character != character
	_selected_character = character
	_update_charge_target_follow()
	if character == null:
		_update_selection_visuals(1.0, false)
	if changed:
		selection_changed.emit(character)

func _update_selection_visuals(size_multiplier: float, selected: bool) -> void:
	for entry: Dictionary in _cursor_visuals:
		var visual: MeshInstance3D = entry.node
		var material: StandardMaterial3D = entry.material
		var original_scale: Vector3 = entry.scale
		visual.scale = original_scale * Vector3(size_multiplier, 1.0, size_multiplier)
		if selected:
			var color := selected_color
			color.a = (entry.color as Color).a
			material.albedo_color = color
			material.emission = Color(selected_color.r, selected_color.g, selected_color.b)
		else:
			material.albedo_color = entry.color
			material.emission = entry.emission

func _is_selectable_character(character: Node3D) -> bool:
	if not is_instance_valid(character) or character.is_queued_for_deletion() or not character.is_visible_in_tree():
		return false
	if character == controlled_character:
		return false
	return not is_instance_valid(movement_anchor) or (character != movement_anchor and not character.is_ancestor_of(movement_anchor))

func _get_character_projection(character: Node3D) -> Dictionary:
	var started: int = _control_perf.start()
	var result: Dictionary = _perf_impl__get_character_projection(character)
	_control_perf.finish(&"projection", started)
	return result

func _perf_impl__get_character_projection(character: Node3D) -> Dictionary:
	if not _is_selectable_character(character):
		return {}
	var found := false
	var bounds := AABB()
	var shapes := character.find_children("*", "CollisionShape3D", true, false)
	_control_perf.count(&"projection_shapes_found", shapes.size())
	for node: Node in shapes:
		var collision := node as CollisionShape3D
		if collision.disabled or collision.shape == null:
			continue
		var body := collision.get_parent()
		while body != character and body != null and not body is CollisionObject3D:
			body = body.get_parent()
		if not body is PhysicalBodyPart3D or (body as PhysicalBodyPart3D).is_broken:
			continue
		_control_perf.count(&"projection_shapes_used")
		_control_perf.count(&"projection_corners", 8)
		var local_bounds := collision.shape.get_debug_mesh().get_aabb()
		for corner: int in 8:
			var point := collision.global_transform * local_bounds.get_endpoint(corner)
			if not found:
				bounds = AABB(point, Vector3.ZERO)
				found = true
			else:
				bounds = bounds.expand(point)
	if not found:
		return {}
	var center := bounds.get_center()
	# The ground ring encloses the horizontal footprint, including rotated/scaled shapes.
	var radius := Vector2(bounds.size.x, bounds.size.z).length() * 0.5
	return {"center": center, "radius": maxf(radius, 0.5)}

## Preserve the real mouse offset by translating it with the selected character while charging.
func _update_charge_target_follow() -> bool:
	var pressed := _charge_input_pressed()
	if not _gameplay_cursor_active or not selection_enabled or not pressed:
		_charge_follow_target = null
		return false
	var target := get_selected_character()
	var projection := _get_character_projection(target)
	if projection.is_empty():
		_charge_follow_target = null
		return false
	var center: Vector3 = projection.center
	var horizontal_center := Vector2(center.x, center.z)
	if _charge_follow_target == target:
		_desired_horizontal_position += horizontal_center - _charge_follow_center
	_charge_follow_target = target
	_charge_follow_center = horizontal_center
	return true

func _update_character_selection(delta: float) -> Dictionary:
	var started: int = _control_perf.start()
	var result: Dictionary = _perf_impl__update_character_selection(delta)
	_control_perf.finish(&"selection", started)
	return result

func _perf_impl__update_character_selection(delta: float) -> Dictionary:
	_update_charge_target_follow()
	_selection_search_elapsed += delta
	if not selection_enabled:
		_set_selected_character(null)
		return {}
	if get_selected_character() != null:
		var current := _get_character_projection(_selected_character)
		if not current.is_empty():
			var center: Vector3 = current.center
			var distance := _desired_horizontal_position.distance_to(Vector2(center.x, center.z))
			if distance <= float(current.radius) + selection_snap_margin + selection_release_margin:
				_update_selection_visuals(float(current.radius) * selected_radius_multiplier / 0.5, true)
				return current
		_set_selected_character(null)
		_selection_search_elapsed = INF
	if _selection_search_elapsed < selection_search_interval:
		return {}
	_selection_search_elapsed = 0.0
	var nearest: Node3D
	var nearest_projection := {}
	var nearest_distance := INF
	_control_perf.count(&"selection_searches")
	for node: Node in get_tree().get_nodes_in_group(selectable_character_group):
		_control_perf.count(&"selection_candidates")
		if not node is Node3D:
			continue
		var projection := _get_character_projection(node as Node3D)
		if projection.is_empty():
			continue
		var center: Vector3 = projection.center
		var distance := _desired_horizontal_position.distance_to(Vector2(center.x, center.z))
		if distance <= float(projection.radius) + selection_snap_margin and distance < nearest_distance:
			nearest = node as Node3D
			nearest_projection = projection
			nearest_distance = distance
	if nearest != null:
		_set_selected_character(nearest)
		_update_selection_visuals(float(nearest_projection.radius) * selected_radius_multiplier / 0.5, true)
	return nearest_projection

func _find_terrain_hit(ray_from: Vector3, ray_to: Vector3) -> Dictionary:
	var started: int = _control_perf.start()
	var result: Dictionary = _perf_impl__find_terrain_hit(ray_from, ray_to)
	_control_perf.finish(&"terrain_probe", started)
	return result

func _perf_impl__find_terrain_hit(ray_from: Vector3, ray_to: Vector3) -> Dictionary:
	var excluded: Array[RID] = []
	for _attempt: int in range(maximum_probe_exclusions):
		var query := PhysicsRayQueryParameters3D.create(
			ray_from,
			ray_to,
			terrain_collision_mask,
			excluded
		)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		_control_perf.count(&"terrain_ray_queries")
		var result := get_world_3d().direct_space_state.intersect_ray(query)
		if result.is_empty():
			return {}
		var collider := result.get(&"collider") as Node
		if (
			collider is StaticBody3D
			or (collider != null and not terrain_group.is_empty() and collider.is_in_group(terrain_group))
		):
			return result
		if collider is CollisionObject3D:
			excluded.append((collider as CollisionObject3D).get_rid())
		else:
			return {}
	return {}

func _get_surface_basis(surface_normal: Vector3, camera: Camera3D) -> Basis:
	var surface_forward := (-camera.global_basis.z).slide(surface_normal)
	if surface_forward.is_zero_approx():
		surface_forward = Vector3.FORWARD.slide(surface_normal)
	if surface_forward.is_zero_approx():
		surface_forward = Vector3.RIGHT.slide(surface_normal)
	surface_forward = surface_forward.normalized()
	var basis_z := -surface_forward
	var basis_x := surface_normal.cross(basis_z).normalized()
	return Basis(basis_x, surface_normal, basis_z).orthonormalized()

func _smoothing_weight(speed: float, delta: float) -> float:
	return 1.0 if speed <= 0.0 else 1.0 - exp(-speed * maxf(delta, 0.0))

func _is_external_interface_open() -> bool:
	for node: Node in get_tree().get_nodes_in_group(&"ui_interface_2d"):
		if node is CanvasLayer and (node as CanvasLayer).visible and not node.is_queued_for_deletion():
			return true
	var console := get_tree().root.get_node_or_null("RuntimeConsole")
	return console != null and console.has_method("is_console_open") and bool(console.call("is_console_open"))

func _charge_input_pressed() -> bool:
	var source := PLAYER_CONTEXT.controller(self)
	if source != null: return source.is_gameplay_action_pressed(&"MouseLeft")
	return InputMap.has_action(&"MouseLeft") and Input.is_action_pressed(&"MouseLeft")

func bind_control_target(character: Node3D, anchor: Node3D, follow_translation: bool) -> void:
	controlled_character = character
	movement_anchor = anchor
	follow_anchor_translation = follow_translation
	_last_anchor = null
	_charge_follow_target = null
	_set_selected_character(null)
	_pending_mouse_motion = Vector2.ZERO
	_reset_desired_position()

func get_actual_ground_position() -> Vector3:
	var desired := get_mouse_ground_position()
	var from := desired + Vector3.UP * probe_height
	var hit := _find_terrain_hit(from, from + Vector3.DOWN * probe_depth)
	return Vector3(hit.position) + Vector3(hit.normal) * surface_offset if not hit.is_empty() else desired

func set_control_performance_tracking_enabled(enabled: bool) -> void:
	_control_perf.set_enabled(enabled)

func consume_control_performance_stats() -> Dictionary:
	return _control_perf.consume()
