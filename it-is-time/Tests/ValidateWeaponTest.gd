extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var weapon := load("res://Scenes/Items/Weapon_Test.tscn").instantiate() as RigidBody3D
	root.add_child(weapon)
	# The user's inherited scene may choose Mesh by default; isolate this Sprite test.
	weapon.sprite_visible = true
	weapon.mesh_visible = false
	assert(weapon is SampleItem3D)
	assert(weapon.can_be_picked_up)
	weapon.freeze = true
	var cells: Array[Vector2i] = [Vector2i(2, 3), Vector2i(3, 3), Vector2i(3, 4)]
	weapon.build_from_material_cells(
		cells,
		Vector2(160.0, 224.0),
		Vector2(2.0, 3.0),
		PI * 0.5,
		&"Arm_R",
		true
	)
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
	assert(weapon.has_attachment_point)
	assert(weapon.attachment_canvas_position.is_equal_approx(Vector2(160.0, 224.0)))
	assert(weapon.attachment_local_position.is_equal_approx(Vector3(-0.32, 0.32, 0.0)))
	assert(is_equal_approx(weapon.item_rotation, PI * 0.5))
	weapon.visible = false
	var hidden_preview := weapon.duplicate(Node.DUPLICATE_USE_INSTANTIATION) as Node3D
	assert(not hidden_preview.visible)
	weapon._prepare_preview_tree(hidden_preview, true)
	assert(hidden_preview.visible, "An inventory-hidden item must be visible in its icon preview")
	hidden_preview.free()
	var transparent_image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	transparent_image.fill(Color.TRANSPARENT)
	assert(not weapon._image_has_visible_pixels(transparent_image))
	transparent_image.set_pixel(2, 2, Color.WHITE)
	assert(weapon._image_has_visible_pixels(transparent_image))
	var generated_icon: Texture2D = await weapon.create_item_image()
	assert(generated_icon != null, "An item without an assigned 2D image must generate a temporary image")
	assert(weapon.sprite_visible and not weapon.mesh_visible)
	var original_mass: float = weapon.mass
	var original_attachment: Vector3 = weapon.attachment_local_position
	var meshes := weapon.find_children("*", "MeshInstance3D", true, false)
	assert(meshes.size() == cells.size())
	for node: Node in meshes:
		var mesh_instance := node as MeshInstance3D
		assert(not mesh_instance.visible)
		var collision_name := str(mesh_instance.name).replace("MaterialMesh_", "Collision_")
		var collision := weapon.get_node(collision_name) as CollisionShape3D
		assert((mesh_instance.mesh as BoxMesh).size.is_equal_approx((collision.shape as BoxShape3D).size))
		assert(mesh_instance.position.is_equal_approx(collision.position))
		assert((mesh_instance.mesh.material as StandardMaterial3D).albedo_texture != null)
	weapon.sprite_visible = false
	weapon.mesh_visible = true
	assert(weapon._temporary_item_image == null, "Changing visuals must invalidate the temporary icon")
	for child: Node in weapon.get_children():
		if child is Sprite3D:
			assert(not child.visible)
		elif child is MeshInstance3D:
			assert(child.visible)
	assert(is_equal_approx(weapon.mass, original_mass))
	assert(weapon.attachment_local_position.is_equal_approx(original_attachment))
	assert(weapon.get_generated_collision_count() == cells.size())
	var mesh_icon: Texture2D = await weapon.create_item_image()
	assert(mesh_icon != null)
	weapon.mesh_visible = false
	assert(not meshes[0].visible)
	weapon.sprite_visible = true
	assert(weapon.get_child(0).visible)
	weapon.mesh_visible = true
	assert(meshes[0].visible)
	# Inspector presets set before generation must also work after rebuilding.
	weapon.sprite_visible = false
	weapon.build_from_material_cells(cells)
	assert(weapon.get_generated_collision_count() == cells.size())
	for child: Node in weapon.get_children():
		if child is Sprite3D:
			assert(not child.visible)
		elif child is MeshInstance3D:
			assert(child.visible)
	var base_item := load("res://Scenes/Items/_SampleItem.tscn").instantiate() as SampleItem3D
	base_item.sprite_visible = false
	base_item.mesh_visible = true
	root.add_child(base_item)
	var authored_sprite := Sprite3D.new()
	base_item.add_child(authored_sprite)
	var authored_mesh := MeshInstance3D.new()
	base_item.add_child(authored_mesh)
	assert(not authored_sprite.visible and authored_mesh.visible)
	base_item.mesh_visible = false
	assert(not authored_mesh.visible)
	base_item.queue_free()
	print("WEAPON_TEST_VALIDATION_PASSED")
	weapon.queue_free()
	quit()
