extends Node
## Read attack-owned volumes only; meshes live in each source's viewport/world.
const ACTIVE_COLOR := Color(1.0,0.15,0.1,0.9)
const INACTIVE_COLOR := Color(1.0,0.7,0.1,0.7)
var enabled := false
var _meshes: Dictionary = {}
var _active_material: StandardMaterial3D
var _inactive_material: StandardMaterial3D

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	_active_material = _material(ACTIVE_COLOR)
	_inactive_material = _material(INACTIVE_COLOR)
	set_process(enabled)

func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color = color
	material.no_depth_test = true
	material.render_priority = 127
	return material

func set_enabled(value: bool) -> void:
	enabled = value
	set_process(value)
	if value: _process(0.0)
	else: _clear()

func _process(_delta: float) -> void:
	var seen := {}
	for source: Node in get_tree().get_nodes_in_group(&"damage_components"):
		if source.is_queued_for_deletion() or not source.has_method("get_attack_debug_shapes"): continue
		var volumes: Array = source.get_attack_debug_shapes()
		for index: int in volumes.size():
			var volume: Dictionary = volumes[index]
			var shape: Shape3D = volume.shape
			if shape == null: continue
			var key := "%d:%d" % [source.get_instance_id(),index]
			seen[key] = true
			var instance: MeshInstance3D = _meshes.get(key)
			if not is_instance_valid(instance):
				instance = MeshInstance3D.new()
				instance.name = "AttackCollisionOutline"
				instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				instance.ignore_occlusion_culling = true
				instance.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
				source.get_viewport().add_child(instance)
				_meshes[key] = instance
			elif instance.get_viewport() != source.get_viewport():
				instance.reparent(source.get_viewport())
			var geometry := shape.get_debug_mesh()
			if not instance.has_meta(&"attack_debug_geometry") or instance.get_meta(&"attack_debug_geometry") != geometry:
				instance.mesh = _wire_mesh(geometry)
				instance.set_meta(&"attack_debug_geometry",geometry)
			instance.global_transform = volume.transform
			instance.material_override = _active_material if volume.active else _inactive_material
	for key: String in _meshes.keys():
		if seen.has(key): continue
		if is_instance_valid(_meshes[key]): _meshes[key].free()
		_meshes.erase(key)

func _wire_mesh(geometry: ArrayMesh) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	# Godot's debug mesh also contains filled surfaces, which would obscure the creature.
	for index: int in geometry.get_surface_count():
		if geometry.surface_get_primitive_type(index) == Mesh.PRIMITIVE_LINES:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES,geometry.surface_get_arrays(index))
	return mesh

func _clear() -> void:
	for instance: Variant in _meshes.values():
		if is_instance_valid(instance): instance.free()
	_meshes.clear()

func _exit_tree() -> void: _clear()
