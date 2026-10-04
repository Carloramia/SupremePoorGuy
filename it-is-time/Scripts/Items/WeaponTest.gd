extends "res://Scripts/Items/SampleWeapon3D.gd"

@export_custom(PROPERTY_HINT_RESOURCE_TYPE, "SampleMaterial")
var default_material: Resource = preload("res://Resources/Materials/TestMaterial.tres")

var material_cell_size: float:
	get:
		return default_material.cell_size
var collision_thickness: float:
	get:
		return default_material.collision_thickness
var mass_per_cell: float:
	get:
		return default_material.mass_per_cell

var _material_cells: Array[Vector2i] = []

func build_from_material_cells(
	cells: Array[Vector2i],
	connection_canvas_position: Vector2 = Vector2.ZERO,
	connection_grid_position: Vector2 = Vector2.ZERO,
	built_item_rotation: float = 0.0,
	holder_name: StringName = &"Arm_R",
	connection_is_set: bool = false
) -> void:
	_temporary_item_image = null
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
		_add_material_cell(cell, local_position, default_material)
	mass = maxf(mass_per_cell * _material_cells.size(), 0.01)
	if connection_is_set:
		var attachment_local := Vector3(
			(connection_grid_position.x - center.x) * material_cell_size,
			-(connection_grid_position.y - center.y) * material_cell_size,
			0.0
		)
		configure_attachment(
			connection_canvas_position,
			attachment_local,
			built_item_rotation,
			holder_name
		)
		print(
			("[weapon_attachment] canvas=%s grid=%s material_center=%s local=%s "
			+ "rotation_deg=%.3f holder=%s cell_size=%.3f")
			% [
				connection_canvas_position,
				connection_grid_position,
				center,
				attachment_local,
				rad_to_deg(built_item_rotation),
				holder_name,
				material_cell_size,
			]
		)

func get_material_cells() -> Array[Vector2i]:
	return _material_cells.duplicate()

func get_generated_collision_count() -> int:
	var count: int = 0
	for child: Node in get_children():
		if child is CollisionShape3D:
			count += 1
	return count

func _add_material_cell(
	cell: Vector2i,
	local_position: Vector3,
	material_data: Resource
) -> void:
	var texture: Texture2D = material_data.get_display_texture()
	var sprite := Sprite3D.new()
	sprite.name = "Material_%d_%d" % [cell.x, cell.y]
	sprite.texture = texture
	sprite.pixel_size = material_data.cell_size / maxf(texture.get_width(), 1.0)
	sprite.position = local_position
	sprite.visible = sprite_visible
	add_child(sprite)
	var collision := CollisionShape3D.new()
	collision.name = "Collision_%d_%d" % [cell.x, cell.y]
	var shape := BoxShape3D.new()
	shape.size = Vector3(
		material_data.cell_size,
		material_data.cell_size,
		material_data.collision_thickness
	)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MaterialMesh_%d_%d" % [cell.x, cell.y]
	var box_mesh := BoxMesh.new()
	box_mesh.size = shape.size
	var mesh_material := StandardMaterial3D.new()
	mesh_material.albedo_texture = texture
	box_mesh.material = mesh_material
	mesh_instance.mesh = box_mesh
	mesh_instance.position = local_position
	mesh_instance.visible = mesh_visible
	add_child(mesh_instance)
	collision.shape = shape
	collision.position = local_position
	add_child(collision)

func _clear_generated_cells() -> void:
	for child: Node in get_children():
		remove_child(child)
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

