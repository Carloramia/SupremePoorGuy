@tool
class_name SampleMaterial
extends Resource

@export_group("Identity")
@export var material_id: StringName = &"Material"
@export var display_name: String = "Material"
@export var icon: Texture2D
@export var sprite_texture: Texture2D

@export_group("Physical Properties")
@export_range(0.01, 10.0, 0.01, "or_greater") var cell_size: float = 0.64
@export_range(0.01, 100.0, 0.01, "or_greater") var mass_per_cell: float = 0.25
@export_range(0.01, 10.0, 0.01, "or_greater") var collision_thickness: float = 0.2

func get_display_texture() -> Texture2D:
	return sprite_texture if sprite_texture != null else icon

