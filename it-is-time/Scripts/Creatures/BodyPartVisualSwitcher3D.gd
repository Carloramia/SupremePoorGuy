@tool
extends RefCounted

var current_state: StringName = &""
var _target: MeshInstance3D
var _original: Dictionary = {}
var _state_transform := Transform3D.IDENTITY
var _anchor_position: Variant
var _mesh_anchor := Vector3.ZERO

func is_target(node: MeshInstance3D) -> bool:
	return not _original.is_empty() and is_instance_valid(_target) and node == _target

func source_mesh(node: MeshInstance3D) -> Mesh:
	return _original.mesh if is_target(node) else node.mesh

func update_base_transform(pose: Transform3D) -> void:
	_original.transform = pose
	_apply_transform()

func update_paper_depth(depth: float) -> void:
	var pose: Transform3D = _original.transform
	pose.basis.z = pose.basis.z.normalized() * depth
	update_base_transform(pose)

func apply(state: BodyPartVisualState3D, target: MeshInstance3D, anchor_position: Variant = null) -> bool:
	if state == null or state.mesh == null or not is_instance_valid(target): return false
	if state.mesh.get_surface_count()==0 or not state.mesh.get_aabb().size.is_finite(): return false
	if not state.visual_transform.is_finite() or is_zero_approx(state.visual_transform.basis.determinant()): return false
	if not _original.is_empty() and _target != target: restore()
	if _original.is_empty():
		var surfaces: Array[Material] = []
		if target.mesh != null:
			for index: int in target.mesh.get_surface_count(): surfaces.append(target.get_surface_override_material(index))
		_original = {"mesh":target.mesh, "transform":target.transform, "material":target.material_override, "surfaces":surfaces}
		_target = target
	_clear_surface_overrides()
	_target.mesh = state.mesh
	_target.material_override = state.material_override
	_state_transform = state.visual_transform
	_anchor_position = anchor_position
	_mesh_anchor = state.mesh_anchor
	_apply_transform()
	current_state = state.state_name
	return true

func restore() -> void:
	if is_instance_valid(_target) and not _original.is_empty():
		_clear_surface_overrides()
		_target.mesh = _original.mesh
		_target.transform = _original.transform
		_target.material_override = _original.material
		for index: int in _original.surfaces.size(): _target.set_surface_override_material(index,_original.surfaces[index])
	_original.clear()
	_target = null
	current_state = &""
	_state_transform = Transform3D.IDENTITY
	_anchor_position = null
	_mesh_anchor = Vector3.ZERO

func _apply_transform() -> void:
	var pose := Transform3D(_original.transform) * _state_transform
	if _anchor_position != null: pose.origin = Vector3(_anchor_position) - pose.basis * _mesh_anchor
	_target.transform = pose

func _clear_surface_overrides() -> void:
	if _target.mesh == null: return
	for index: int in _target.mesh.get_surface_count(): _target.set_surface_override_material(index,null)
