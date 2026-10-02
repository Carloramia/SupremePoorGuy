@tool
extends Node3D

@export_group("BodyPart Edges")
## Distances from the sprite's local origin, in Godot 3D units.
@export_range(0.001, 100.0, 0.01, "or_greater") var left_distance: float = 1.28
@export_range(0.001, 100.0, 0.01, "or_greater") var right_distance: float = 1.28
@export_range(0.001, 100.0, 0.01, "or_greater") var top_distance: float = 1.28
@export_range(0.001, 100.0, 0.01, "or_greater") var bottom_distance: float = 1.28

const OUTLINE_SHADER: Shader = preload("res://Shaders/BodyPartOutline.gdshader")
const MIN_EDGE_DISTANCE: float = 0.001
var _materials: Dictionary[Sprite3D, ShaderMaterial] = {}

func get_outline_edge_distances() -> Vector4:
	return Vector4(
		maxf(left_distance, MIN_EDGE_DISTANCE),
		maxf(right_distance, MIN_EDGE_DISTANCE),
		maxf(top_distance, MIN_EDGE_DISTANCE),
		maxf(bottom_distance, MIN_EDGE_DISTANCE)
	)

func _process(_delta: float) -> void:
	_sync_root_name()

	_update_children(self)
	for sprite: Sprite3D in _materials.keys():
		if not is_instance_valid(sprite):
			_materials.erase(sprite)

func _update_children(parent_node: Node) -> void:
	for child: Node in parent_node.get_children():
		if child is Sprite3D and child.name == &"BodyPart":
			var sprite := child as Sprite3D
			if not _materials.has(sprite):
				var material := ShaderMaterial.new()
				material.shader = OUTLINE_SHADER
				_materials[sprite] = material
				sprite.material_override = material
			var material: ShaderMaterial = _materials[sprite]
			material.set_shader_parameter(&"sprite_texture", sprite.texture)
			material.set_shader_parameter(&"sprite_axis", sprite.axis)
			var safe_left: float = maxf(left_distance, MIN_EDGE_DISTANCE)
			var safe_right: float = maxf(right_distance, MIN_EDGE_DISTANCE)
			var safe_top: float = maxf(top_distance, MIN_EDGE_DISTANCE)
			var safe_bottom: float = maxf(bottom_distance, MIN_EDGE_DISTANCE)
			var edge_distances := Vector4.ZERO
			edge_distances.x = safe_left
			edge_distances.y = safe_right
			edge_distances.z = safe_top
			edge_distances.w = safe_bottom
			material.set_shader_parameter(&"edge_distances", edge_distances)
			# The shader can extend beyond the Sprite3D's original bounds.
			var bounds_width: float = left_distance + right_distance
			var bounds_height: float = top_distance + bottom_distance
			sprite.extra_cull_margin = maxf(bounds_width, bounds_height)
		_update_children(child)

func _sync_root_name() -> void:
	if Engine.is_editor_hint():
		if get_tree().edited_scene_root != self:
			return

	if scene_file_path.is_empty():
		return

	var file_name := scene_file_path.get_file().get_basename()

	if file_name == "_SampleBodyParts":
		return

	if str(name) != file_name:
		set(&"name", file_name)
