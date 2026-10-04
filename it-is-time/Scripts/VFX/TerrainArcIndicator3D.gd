class_name TerrainArcIndicator3D
extends Node3D

var _control_perf := preload("res://Scripts/Debug/ControlPerformanceStats.gd").new()

const PLAYER_CONTEXT = preload("res://Scripts/Player/PlayerControlContext.gd")

@export_group("Targets")
@export var movement_anchor: Node3D
@export var terrain_cursor: Node3D

@export_group("Arc")
@export_range(0.1, 100.0, 0.1, "or_greater") var radius: float = 2.0
@export_range(1.0, 359.0, 1.0) var arc_angle_degrees: float = 100.0
@export_range(0.01, 10.0, 0.01, "or_greater") var arc_width: float = 0.12
@export_range(0.01, 10.0, 0.01, "or_greater") var glow_width: float = 0.36
@export_range(3, 256, 1) var segment_count: int = 48

@export_group("Ground Detection")
@export_flags_3d_physics var terrain_collision_mask: int = 1
@export var terrain_group: StringName = &"navigation_source"
@export_range(0.1, 1000.0, 0.1, "or_greater") var probe_height: float = 30.0
@export_range(0.1, 2000.0, 0.1, "or_greater") var probe_depth: float = 100.0
@export_range(0.0, 1.0, 0.001, "or_greater") var surface_offset: float = 0.04
@export_range(1, 64, 1) var maximum_probe_exclusions: int = 16

@export_group("Smoothing")
@export_range(0.0, 100.0, 0.1, "or_greater") var position_smoothing: float = 20.0
@export_range(0.0, 100.0, 0.1, "or_greater") var direction_smoothing: float = 18.0

@onready var _ring: MeshInstance3D = $Ring
@onready var _glow: MeshInstance3D = $Glow

var _has_ground_projection: bool = false
var _last_direction: Vector3 = Vector3.FORWARD

func _ready() -> void:
	_control_perf.register(self)
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group(&"terrain_arc_indicator_3d")
	_resolve_targets()
	_rebuild_arc_meshes()
	visible = false

func _physics_process(delta: float) -> void:
	var started: int = _control_perf.start()
	_perf_impl__physics_process(delta)
	_control_perf.finish(&"arc_physics", started)

func _perf_impl__physics_process(delta: float) -> void:
	_resolve_targets()
	if not _should_be_visible() or get_world_3d() == null:
		_has_ground_projection = false
		visible = false
		return
	var anchor_position := movement_anchor.global_position
	var ray_from := anchor_position + Vector3.UP * probe_height
	var hit := _find_terrain_hit(ray_from, ray_from + Vector3.DOWN * probe_depth)
	if hit.is_empty():
		_has_ground_projection = false
		visible = false
		return
	var surface_normal: Vector3 = hit.get(&"normal", Vector3.UP)
	surface_normal = surface_normal.normalized()
	var projected_center: Vector3 = hit.get(&"position", anchor_position)
	projected_center += surface_normal * surface_offset
	var cursor_direction := terrain_cursor.global_position - projected_center
	cursor_direction = cursor_direction.slide(surface_normal)
	if cursor_direction.is_zero_approx():
		cursor_direction = _last_direction.slide(surface_normal)
	if cursor_direction.is_zero_approx():
		cursor_direction = Vector3.FORWARD.slide(surface_normal)
	cursor_direction = cursor_direction.normalized()
	_last_direction = cursor_direction
	var target_basis := _basis_from_direction(cursor_direction, surface_normal)
	if not _has_ground_projection:
		global_transform = Transform3D(target_basis, projected_center)
		_has_ground_projection = true
	else:
		var position_weight := _smoothing_weight(position_smoothing, delta)
		var direction_weight := _smoothing_weight(direction_smoothing, delta)
		var smoothed_position := global_position.lerp(projected_center, position_weight)
		var smoothed_rotation := global_basis.get_rotation_quaternion().slerp(
			target_basis.get_rotation_quaternion(),
			direction_weight
		)
		global_transform = Transform3D(Basis(smoothed_rotation), smoothed_position)
	visible = true

func get_facing_direction() -> Vector3:
	return -global_basis.z.normalized()

func has_valid_ground_projection() -> bool:
	return _has_ground_projection

func rebuild_arc_meshes() -> void:
	if not is_node_ready():
		return
	_rebuild_arc_meshes()

func _rebuild_arc_meshes() -> void:
	_ring.mesh = _create_arc_mesh(arc_width)
	_glow.mesh = _create_arc_mesh(maxf(glow_width, arc_width))

func _create_arc_mesh(width: float) -> ArrayMesh:
	var safe_segments := maxi(segment_count, 3)
	var half_angle := deg_to_rad(clampf(arc_angle_degrees, 1.0, 359.0)) * 0.5
	var inner_radius := maxf(radius - width * 0.5, 0.001)
	var outer_radius := maxf(radius + width * 0.5, inner_radius + 0.001)
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for index: int in range(safe_segments + 1):
		var ratio := float(index) / float(safe_segments)
		var angle := lerpf(-half_angle, half_angle, ratio)
		var radial := Vector3(sin(angle), 0.0, -cos(angle))
		vertices.append(radial * inner_radius)
		vertices.append(radial * outer_radius)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
		uvs.append(Vector2(ratio, 0.0))
		uvs.append(Vector2(ratio, 1.0))
	for index: int in range(safe_segments):
		var base := index * 2
		indices.append_array(PackedInt32Array([
			base,
			base + 2,
			base + 1,
			base + 1,
			base + 2,
			base + 3,
		]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

func _basis_from_direction(direction: Vector3, surface_normal: Vector3) -> Basis:
	var basis_z := -direction.normalized()
	var basis_x := surface_normal.cross(basis_z).normalized()
	return Basis(basis_x, surface_normal, basis_z).orthonormalized()

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

func _resolve_targets() -> void:
	if PLAYER_CONTEXT.controller(self) != null:
		movement_anchor = PLAYER_CONTEXT.anchor(self)
	if not is_instance_valid(movement_anchor):
		movement_anchor = get_tree().get_first_node_in_group(&"npc_navigation_target") as Node3D
	if not is_instance_valid(terrain_cursor):
		terrain_cursor = get_tree().get_first_node_in_group(&"terrain_cursor_3d") as Node3D

func _should_be_visible() -> bool:
	if PLAYER_CONTEXT.controller(self) != null and PLAYER_CONTEXT.controlled_character(self) == null: return false
	if not is_instance_valid(movement_anchor) or not is_instance_valid(terrain_cursor):
		return false
	if terrain_cursor.has_method("is_gameplay_cursor_active"):
		if not bool(terrain_cursor.call("is_gameplay_cursor_active")):
			return false
	if terrain_cursor.has_method("has_valid_ground_position"):
		if not bool(terrain_cursor.call("has_valid_ground_position")):
			return false
	return terrain_cursor.visible

func _smoothing_weight(speed: float, delta: float) -> float:
	return 1.0 if speed <= 0.0 else 1.0 - exp(-speed * maxf(delta, 0.0))

func set_control_performance_tracking_enabled(enabled: bool) -> void:
	_control_perf.set_enabled(enabled)

func consume_control_performance_stats() -> Dictionary:
	return _control_perf.consume()
