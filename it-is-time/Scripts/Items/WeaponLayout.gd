@tool
class_name WeaponLayout
extends Resource

@export var display_name: String = "CustomWeapon"
@export var material: SampleMaterial = preload("res://Resources/Materials/TestMaterial.tres")
@export var cells: Array[Vector2i] = []
## Continuous grid coordinates: cell centers are integers, +Y points down in 2D.
@export var attachment: Vector2 = Vector2.ZERO
@export var attachment_is_set: bool = false
@export var rotation_radians: float = 0.0
@export var holder_name: StringName = &"Arm_R"
@export var sprite_visible: bool = true
@export var mesh_visible: bool = false

func validation_error() -> String:
	if cells.is_empty(): return "请先绘制材料。"
	if not attachment_is_set: return "请先放置握持点。"
	if material == null or material.get_display_texture() == null: return "材料必须包含贴图。"
	for value: float in [material.cell_size,material.mass_per_cell,material.collision_thickness]:
		if not is_finite(value) or value <= 0.0: return "材料尺寸、厚度和重量必须大于零。"
	if not is_finite(rotation_radians) or not is_finite(attachment.x) or not is_finite(attachment.y): return "旋转角度或握持坐标无效。"
	return ""

func center() -> Vector2:
	if cells.is_empty(): return Vector2.ZERO
	var low := cells[0]
	var high := low
	for cell: Vector2i in cells: low = low.min(cell); high = high.max(cell)
	return (Vector2(low)+Vector2(high))*0.5

func attachment_local() -> Vector3:
	var offset := (attachment-center())*material.cell_size
	return Vector3(offset.x,-offset.y,0)
