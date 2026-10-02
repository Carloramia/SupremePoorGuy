extends RigidBody3D

const TEST_MATERIAL_TEXTURE: Texture2D = preload("res://Assets/2DResources/Samples/WhiteCube.png")

@export_range(0.05, 10.0, 0.05, "or_greater") var material_cell_size: float = 0.64
@export_range(0.01, 10.0, 0.01, "or_greater") var collision_thickness: float = 0.2
@export_range(0.01, 100.0, 0.01, "or_greater") var mass_per_cell: float = 0.25

var _material_cells: Array[Vector2i] = []

func build_from_material_cells(cells: Array[Vector2i]) -> void:
	_clear_generated_cells()
	_material_cells = cells.duplicate()
	if _material_cells.is_empty():
		return
	var bounds := _calculate_cell_bounds(_material_cells)
	var center := (Vector2(bounds.position) + Vector2(bounds.end - Vector2i.ONE)) * 0.5
	for cell: Vector2i in _material_cells:
		var local_position := Vector3(
			(float(cell.x) - center.x) * material_cell_size,
			-(float(cell.y) - center.y) * material_cell_size,
			0.0
		)
		_add_material_cell(cell, local_position)
	mass = maxf(mass_per_cell * _material_cells.size(), 0.01)

func get_material_cells() -> Array[Vector2i]:
	return _material_cells.duplicate()

func get_generated_collision_count() -> int:
	var count: int = 0
	for child: Node in get_children():
		if child is CollisionShape3D:
			count += 1
	return count

func _add_material_cell(cell: Vector2i, local_position: Vector3) -> void:
	var sprite := Sprite3D.new()
	sprite.name = "Material_%d_%d" % [cell.x, cell.y]
	sprite.texture = TEST_MATERIAL_TEXTURE
	sprite.pixel_size = material_cell_size / maxf(TEST_MATERIAL_TEXTURE.get_width(), 1.0)
	sprite.position = local_position
	add_child(sprite)
	var collision := CollisionShape3D.new()
	collision.name = "Collision_%d_%d" % [cell.x, cell.y]
	var shape := BoxShape3D.new()
	shape.size = Vector3(material_cell_size, material_cell_size, collision_thickness)
	collision.shape = shape
	collision.position = local_position
	add_child(collision)

func _clear_generated_cells() -> void:
	for child: Node in get_children():
		child.queue_free()

func _calculate_cell_bounds(cells: Array[Vector2i]) -> Rect2i:
	var minimum := cells[0]
	var maximum := cells[0]
	for cell: Vector2i in cells:
		minimum.x = mini(minimum.x, cell.x)
		minimum.y = mini(minimum.y, cell.y)
		maximum.x = maxi(maximum.x, cell.x)
		maximum.y = maxi(maximum.y, cell.y)
	return Rect2i(minimum, maximum - minimum + Vector2i.ONE)

