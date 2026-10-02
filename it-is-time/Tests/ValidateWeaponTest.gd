extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var weapon := load("res://Scenes/Items/Weapon_Test.tscn").instantiate() as RigidBody3D
	root.add_child(weapon)
	weapon.freeze = true
	var cells: Array[Vector2i] = [Vector2i(2, 3), Vector2i(3, 3), Vector2i(3, 4)]
	weapon.build_from_material_cells(cells)
	assert(weapon.get_material_cells() == cells)
	assert(weapon.get_generated_collision_count() == cells.size())
	var sprite_count: int = 0
	for child: Node in weapon.get_children():
		if child is Sprite3D:
			sprite_count += 1
		elif child is CollisionShape3D:
			var shape := (child as CollisionShape3D).shape as BoxShape3D
			assert(shape.size.is_equal_approx(Vector3(
				weapon.material_cell_size,
				weapon.material_cell_size,
				weapon.collision_thickness
			)))
	assert(sprite_count == cells.size())
	assert(is_equal_approx(weapon.mass, weapon.mass_per_cell * cells.size()))
	print("WEAPON_TEST_VALIDATION_PASSED")
	weapon.queue_free()
	quit()
