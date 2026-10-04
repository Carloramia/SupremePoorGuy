extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200.0, 1.0, 200.0)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var characters: Array[Node3D] = []
	for scene: String in ["Character_Test_2", "Character_Test_NPC"]:
		var character := load("res://Scenes/Creatures/Characters/" + scene + ".tscn").instantiate() as Node3D
		character.position.x = 10.0 * characters.size()
		for body: Node in character.find_children("*", "RigidBody3D", true, false):
			(body as RigidBody3D).freeze = true
		root.add_child(character)
		characters.append(character)
	for _frame: int in 3:
		await physics_frame
	var cursor: Node = load("res://Scenes/Input/TerrainCursor3D.tscn").instantiate()
	cursor.movement_anchor = characters[0].get_node("Torso")
	cursor.position_smoothing = 0.0
	root.add_child(cursor)
	cursor.set_cursor_world_position(Vector3.ZERO)
	cursor._update_ground_transform(camera, 0.2)
	assert(cursor.get_selected_character() == null, "Controlled character must not be selected")
	var projection: Dictionary = cursor._get_character_projection(characters[1])
	var center: Vector3 = projection.center
	var mouse_position := center + Vector3(0.6, 0.0, 0.0)
	cursor.set_cursor_world_position(mouse_position)
	cursor._update_ground_transform(camera, 0.2)
	assert(cursor.get_selected_character() == characters[1])
	assert(is_equal_approx(cursor.global_position.x, center.x))
	assert(is_equal_approx(cursor.global_position.z, center.z))
	assert(is_equal_approx(cursor.get_mouse_ground_position().x, mouse_position.x))
	assert(is_equal_approx(cursor.get_target_ground_position().x, center.x))
	var ring := cursor.get_node("Ring") as MeshInstance3D
	var material := ring.material_override as StandardMaterial3D
	assert(material.albedo_color.r > 0.9 and material.albedo_color.g < 0.2)
	assert(ring.scale.x * 0.5 > float(projection.radius))
	characters[1].position.x += 0.4
	center.x += 0.4
	cursor._update_ground_transform(camera, 0.2)
	assert(is_equal_approx(cursor.global_position.x, center.x), "Selected ring must follow a moving target")
	assert(is_equal_approx(cursor.get_mouse_ground_position().x, mouse_position.x), "Target movement must not overwrite the mouse target")
	var other_cursor: Node = load("res://Scenes/Input/TerrainCursor3D.tscn").instantiate()
	other_cursor.input_enabled = false
	root.add_child(other_cursor)
	var other_material: StandardMaterial3D = other_cursor.get_node("Ring").material_override
	assert(other_material.albedo_color.g > 0.8, "Cursor materials must not be shared")
	# Retain selection in the release margin, then restore size/color on leaving it.
	cursor.set_cursor_world_position(center + Vector3.RIGHT * (float(projection.radius) + cursor.selection_snap_margin + 0.2))
	cursor._update_ground_transform(camera, 0.2)
	assert(cursor.get_selected_character() == characters[1])
	cursor.set_cursor_world_position(center + Vector3.RIGHT * (float(projection.radius) + cursor.selection_snap_margin + cursor.selection_release_margin + 2.0))
	cursor._update_ground_transform(camera, 0.2)
	assert(cursor.get_selected_character() == null)
	assert(ring.scale.is_equal_approx(Vector3.ONE))
	assert(material.albedo_color.g > 0.8)
	cursor.set_cursor_world_position(mouse_position)
	cursor._update_ground_transform(camera, 0.2)
	assert(cursor.get_selected_character() == characters[1])
	characters[1].queue_free()
	await process_frame
	cursor._update_ground_transform(camera, 0.2)
	assert(cursor.get_selected_character() == null, "Deleted targets must be released safely")
	print("TERRAIN_CURSOR_SELECTION_3D_VALIDATION_PASSED")
	quit()
