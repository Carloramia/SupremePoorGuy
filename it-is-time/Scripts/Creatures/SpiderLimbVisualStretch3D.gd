@tool
extends RefCounted

## A render-only bridge between captured physics anchors. Never modifies scene resources,
## node transforms, collision shapes or joints; the server overrides are not serialized.
const STRETCH_SHADER = preload("res://Shaders/SpiderLimbVisualStretch.gdshader")
static var _mesh_cache: Dictionary = {}

var upper: PhysicalBodyPart3D
var root_body: PhysicalBodyPart3D
var tip_body: PhysicalBodyPart3D
var root_joint: Generic6DOFJoint3D
var tip_joint: Generic6DOFJoint3D
var visual: MeshInstance3D
var source_mesh: Mesh
var render_mesh: ArrayMesh
var materials: Array[ShaderMaterial] = []
var source_to_part: Transform3D
var source_root: Vector3
var source_tip: Vector3
var source_axis: Vector3
var source_length: float
var protected_length: float
var target_frame := Transform3D.IDENTITY
var target_length: float
var active := false
var _root_frame: Transform3D
var _tip_frame: Transform3D
var _root_depth: float
var _tip_depth: float
var _bounds: AABB
var _appearance_signatures: Array = []

func configure(part: PhysicalBodyPart3D, root_connection: Generic6DOFJoint3D, tip_connection: Generic6DOFJoint3D, cap_ratio: float) -> bool:
	upper = part
	root_joint = root_connection
	tip_joint = tip_connection
	visual = part.get_node_or_null("Model/PaperVolume") as MeshInstance3D
	if visual == null or visual.mesh == null: return false
	var root_data := _connection_frames(root_joint, part)
	var tip_data := _connection_frames(tip_joint, part)
	if root_data.is_empty() or tip_data.is_empty(): return false
	root_body = root_data.body
	tip_body = tip_data.body
	_root_frame = root_data.other_frame
	_tip_frame = tip_data.other_frame
	var marker_a := part.get_node_or_null("JointIn") as Node3D
	var marker_b := part.get_node_or_null("JointOut") as Node3D
	if marker_a == null or marker_b == null: return false
	var point_a: Vector3 = part.global_transform.affine_inverse() * marker_a.global_position
	var point_b: Vector3 = part.global_transform.affine_inverse() * marker_b.global_position
	var upper_anchor: Vector3 = root_data.upper_frame.origin
	source_root = point_a if point_a.distance_squared_to(upper_anchor) < point_b.distance_squared_to(upper_anchor) else point_b
	source_tip = point_b if source_root == point_a else point_a
	source_length = source_root.distance_to(source_tip)
	if source_length < 0.0001: return false
	source_axis = (source_tip - source_root) / source_length
	protected_length = source_length * clampf(cap_ratio, 0.01, 0.45)
	# Physics anchors lie on facing sheet surfaces, while hole markers lie in the
	# sheet's middle plane. Preserve that depth offset to avoid twisting the sheet.
	_root_depth = source_root.z - root_data.upper_frame.origin.z
	_tip_depth = source_tip.z - tip_data.upper_frame.origin.z
	source_to_part = part.global_transform.affine_inverse() * visual.global_transform
	source_mesh = visual.mesh
	for surface: int in source_mesh.get_surface_count():
		if not visual.get_active_material(surface) is StandardMaterial3D: return false
	render_mesh = _split_mesh(source_mesh, source_to_part, source_root, source_axis, source_length, protected_length)
	if render_mesh == null: return false
	_bounds = source_to_part * source_mesh.get_aabb()
	for surface: int in source_mesh.get_surface_count():
		var material := ShaderMaterial.new()
		material.shader = STRETCH_SHADER
		material.set_shader_parameter(&"source_to_part", source_to_part)
		material.set_shader_parameter(&"source_root", source_root)
		material.set_shader_parameter(&"source_axis", source_axis)
		material.set_shader_parameter(&"source_length", source_length)
		material.set_shader_parameter(&"protected_length", protected_length)
		materials.append(material)
		_appearance_signatures.append([])
	return true

static func _connection_frames(joint: Generic6DOFJoint3D, part: PhysicalBodyPart3D) -> Dictionary:
	if not is_instance_valid(joint) or joint.node_a.is_empty() or joint.node_b.is_empty(): return {}
	var a := joint.get_node_or_null(joint.node_a) as PhysicalBodyPart3D
	var b := joint.get_node_or_null(joint.node_b) as PhysicalBodyPart3D
	if a == null or b == null or (a != part and b != part): return {}
	if not joint.has_meta(&"generated_joint_frame_a") or not joint.has_meta(&"generated_joint_frame_b"): return {}
	return {"body": b if a == part else a,
		"upper_frame": joint.get_meta(&"generated_joint_frame_a" if a == part else &"generated_joint_frame_b"),
		"other_frame": joint.get_meta(&"generated_joint_frame_b" if a == part else &"generated_joint_frame_a")}

func geometry_is_current() -> bool:
	if not is_instance_valid(visual) or not is_instance_valid(upper) or visual.mesh != source_mesh: return false
	if not source_to_part.is_equal_approx(upper.global_transform.affine_inverse() * visual.global_transform): return false
	var a := upper.get_node_or_null("JointIn") as Node3D
	var b := upper.get_node_or_null("JointOut") as Node3D
	if a == null or b == null: return false
	var point_a: Vector3 = upper.global_transform.affine_inverse() * a.global_position
	var point_b: Vector3 = upper.global_transform.affine_inverse() * b.global_position
	return (point_a.is_equal_approx(source_root) and point_b.is_equal_approx(source_tip)) \
		or (point_a.is_equal_approx(source_tip) and point_b.is_equal_approx(source_root))

func update() -> void:
	if not is_instance_valid(visual) or not is_instance_valid(upper): return
	if not is_instance_valid(root_body) or not is_instance_valid(tip_body) or upper.is_broken or root_body.is_broken or tip_body.is_broken:
		restore()
		return
	if _connection_frames(root_joint, upper).is_empty() or _connection_frames(tip_joint, upper).is_empty():
		restore()
		return
	var depth_axis := upper.global_basis.z.normalized()
	var start: Vector3 = root_body.global_transform * _root_frame.origin + depth_axis * _root_depth
	var end: Vector3 = tip_body.global_transform * _tip_frame.origin + depth_axis * _tip_depth
	target_length = start.distance_to(end)
	# Two intact caps cannot fit in a shorter span. Fall back to the original
	# mesh instead of inverting its middle or shrinking the connecting holes.
	if target_length <= 2.0 * protected_length + 0.0001:
		restore()
		return
	var basis := upper.global_basis.orthonormalized()
	var rotation := Basis(Quaternion((basis * source_axis).normalized(), (end - start) / target_length)) * basis
	target_frame = Transform3D(rotation, start)
	var instance := visual.get_instance()
	if not active:
		RenderingServer.instance_set_base(instance, render_mesh.get_rid())
		active = true
	for surface: int in materials.size():
		var material := materials[surface]
		var original := visual.get_active_material(surface) as StandardMaterial3D
		if original == null:
			restore()
			return
		var signature := [original, original.albedo_texture, original.albedo_color, original.transparency, original.alpha_scissor_threshold]
		if signature != _appearance_signatures[surface]:
			material.set_shader_parameter(&"has_texture", original.albedo_texture != null)
			material.set_shader_parameter(&"albedo_texture", original.albedo_texture)
			material.set_shader_parameter(&"albedo_color", original.albedo_color)
			material.set_shader_parameter(&"alpha_cutoff", original.alpha_scissor_threshold if original.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR else 0.0)
			_appearance_signatures[surface] = signature
		material.set_shader_parameter(&"target_frame", target_frame)
		material.set_shader_parameter(&"target_length", target_length)
		RenderingServer.instance_set_surface_override_material(instance, surface, material.get_rid())
	# Shader deformation also needs a new culling box; it must not change the
	# MeshInstance's resource bounds, which generation/manual-layout code reads.
	var world_bounds := AABB(map_part_point(_bounds.position), Vector3.ZERO)
	for corner: int in 8:
		world_bounds = world_bounds.expand(map_part_point(_bounds.get_endpoint(corner)))
	RenderingServer.instance_set_custom_aabb(instance, visual.global_transform.affine_inverse() * world_bounds)

func map_part_point(point: Vector3) -> Vector3:
	var offset := point - source_root
	var distance_along := offset.dot(source_axis)
	var mapped := distance_along
	if distance_along >= source_length - protected_length:
		mapped += target_length - source_length
	elif distance_along > protected_length:
		mapped = protected_length + (distance_along - protected_length) * (target_length - 2.0 * protected_length) / (source_length - 2.0 * protected_length)
	return target_frame * (offset + source_axis * (mapped - distance_along))

func restore() -> void:
	if not active or not is_instance_valid(visual): return
	var instance := visual.get_instance()
	RenderingServer.instance_set_base(instance, visual.mesh.get_rid())
	for surface: int in visual.mesh.get_surface_count():
		var original := visual.get_surface_override_material(surface)
		RenderingServer.instance_set_surface_override_material(instance, surface, original.get_rid() if original != null else RID())
	RenderingServer.instance_set_custom_aabb(instance, visual.custom_aabb)
	active = false

static func _split_mesh(mesh: Mesh, transform: Transform3D, start: Vector3, axis: Vector3, length: float, cap: float) -> ArrayMesh:
	# Split once at the two cap boundaries, including the side walls. Without
	# these cuts, the four-vertex textured faces would stretch the end holes too.
	var plane_axis: Vector3 = transform.basis.transposed() * axis
	var plane_scale := plane_axis.length()
	plane_axis /= plane_scale
	var cuts := Vector2((start.dot(axis) + cap - transform.origin.dot(axis)) / plane_scale,
		(start.dot(axis) + length - cap - transform.origin.dot(axis)) / plane_scale)
	var key := str(mesh.get_rid()) + str(plane_axis) + str(cuts)
	if _mesh_cache.has(key):
		var cached := _mesh_cache[key].get_ref() as ArrayMesh
		if cached != null: return cached
	var result := ArrayMesh.new()
	for surface: int in mesh.get_surface_count():
		var source := mesh.surface_get_arrays(surface)
		var vertices := PackedVector3Array()
		var normals := PackedVector3Array()
		var uv := PackedVector2Array()
		var indices: PackedInt32Array = source[Mesh.ARRAY_INDEX]
		if indices.is_empty():
			for index: int in source[Mesh.ARRAY_VERTEX].size(): indices.append(index)
		for triangle: int in range(0, indices.size(), 3):
			var polygon: Array = []
			var p0: Vector3 = source[Mesh.ARRAY_VERTEX][indices[triangle]]
			var p1: Vector3 = source[Mesh.ARRAY_VERTEX][indices[triangle + 1]]
			var p2: Vector3 = source[Mesh.ARRAY_VERTEX][indices[triangle + 2]]
			var face_normal := (p2 - p0).cross(p1 - p0).normalized()
			for index: int in [indices[triangle], indices[triangle + 1], indices[triangle + 2]]:
				polygon.append({"point": source[Mesh.ARRAY_VERTEX][index],
					"normal": source[Mesh.ARRAY_NORMAL][index] if source[Mesh.ARRAY_NORMAL] != null else face_normal,
					"uv": source[Mesh.ARRAY_TEX_UV][index] if source[Mesh.ARRAY_TEX_UV] != null else Vector2.ZERO})
			for band: int in 3:
				var clipped: Array = polygon
				if band > 0: clipped = _clip(clipped, plane_axis, cuts[band - 1], true)
				if band < 2: clipped = _clip(clipped, plane_axis, cuts[band], false)
				for fan: int in range(1, clipped.size() - 1):
					for vertex: Dictionary in [clipped[0], clipped[fan], clipped[fan + 1]]:
						vertices.append(vertex.point)
						normals.append(vertex.normal)
						uv.append(vertex.uv)
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = vertices
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uv
		result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.surface_set_material(surface, mesh.surface_get_material(surface))
	_mesh_cache[key] = weakref(result)
	return result

static func _clip(polygon: Array, axis: Vector3, boundary: float, above: bool) -> Array:
	var result: Array = []
	if polygon.is_empty(): return result
	var previous: Dictionary = polygon.back()
	var previous_distance: float = previous.point.dot(axis) - boundary
	for current: Dictionary in polygon:
		var distance: float = current.point.dot(axis) - boundary
		var inside := distance >= 0.0 if above else distance <= 0.0
		var was_inside := previous_distance >= 0.0 if above else previous_distance <= 0.0
		if inside != was_inside:
			var weight := previous_distance / (previous_distance - distance)
			result.append({"point": previous.point.lerp(current.point, weight),
				"normal": previous.normal.lerp(current.normal, weight).normalized(), "uv": previous.uv.lerp(current.uv, weight)})
		if inside: result.append(current)
		previous = current
		previous_distance = distance
	return result
