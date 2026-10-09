class_name ScenarioOccluder3D
extends StaticBody3D

@export var fade_speed: float = 8.0
var fade_amount: float = 1.0
var desired_fade: float = 1.0
var materials: Array[Material] = []
var original_colors: Array[Color] = []
var original_transparency: Array[int] = []

func _ready() -> void:
	add_to_group("scenario_occluder")
	_collect(self)
	if materials.is_empty():
		push_warning("Occluder has no supported StandardMaterial3D/paper ShaderMaterial")

func _collect(node: Node) -> void:
	if node is MeshInstance3D and node.mesh:
		var override_source: Material = node.material_override
		node.material_override = null
		for surface in node.mesh.get_surface_count():
			var source: Material = override_source if override_source else node.get_active_material(surface)
			if source is StandardMaterial3D or (source is ShaderMaterial and source.shader == preload("res://scenario_2_5d/visuals/paper.gdshader")):
				var copy: Material = source.duplicate()
				node.set_surface_override_material(surface, copy)
				materials.append(copy)
				original_colors.append(copy.albedo_color if copy is StandardMaterial3D else Color.WHITE)
				original_transparency.append(copy.transparency if copy is StandardMaterial3D else 0)
			else:
				node.set_surface_override_material(surface, source)
	for child in node.get_children():
		_collect(child)

func set_fade_amount(value: float) -> void:
	desired_fade = clampf(value, 0.05, 1.0)

func restore_fade() -> void:
	desired_fade = 1.0

func _process(delta: float) -> void:
	fade_amount = lerpf(fade_amount, desired_fade, 1.0 - exp(-fade_speed * delta))
	if absf(fade_amount - desired_fade) < 0.002:
		fade_amount = desired_fade
	for index in materials.size():
		var material := materials[index]
		if material is StandardMaterial3D:
			material.transparency = original_transparency[index] if fade_amount == 1.0 else BaseMaterial3D.TRANSPARENCY_ALPHA
			var color := original_colors[index]
			color.a *= fade_amount
			material.albedo_color = color
		else:
			material.set_shader_parameter("fade", fade_amount)
