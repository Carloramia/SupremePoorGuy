extends CanvasLayer

## Full-screen blur used behind modal interfaces.
@export_range(0.0, 8.0, 0.1) var blur_strength: float = 3.0:
	set(value):
		blur_strength = value
		_update_material()

@export var dim_color: Color = Color(0.08, 0.09, 0.10, 0.42):
	set(value):
		dim_color = value
		_update_material()

@onready var _overlay: ColorRect = $Overlay

func _ready() -> void:
	_update_material()

func show_mask() -> void:
	show()

func hide_mask() -> void:
	hide()

func _update_material() -> void:
	if not is_instance_valid(_overlay):
		return
	var shader_material := _overlay.material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter(&"blur_strength", blur_strength)
	shader_material.set_shader_parameter(&"dim_color", dim_color)
