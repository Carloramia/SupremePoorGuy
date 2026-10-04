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
	# Select midway through charging, not only at the initial button press.
	cursor.set_cursor_world_position(Vector3(50.0, 0.0, 0.0))
	cursor._update_ground_transform(camera, 0.2)
	assert(cursor.get_selected_character() == null)
	Input.action_press("MouseLeft")
	cursor.set_cursor_world_position(center + Vector3(0.25, 0.0, 0.3))
	cursor._update_ground_transform(camera, 0.2)
	assert(cursor.get_selected_character() == characters[1])
	var before: Vector3 = cursor.get_mouse_ground_position()
	characters[1].position += Vector3(40.0, 0.0, -4.0)
	cursor._update_ground_transform(camera, 0.2)
	var after: Vector3 = cursor.get_mouse_ground_position()
	assert(Vector2(after.x - before.x, after.z - before.z).is_equal_approx(Vector2(40.0, -4.0)))
	assert(cursor.get_selected_character() == characters[1], "Target movement must not break selection during charging")
	# Player movement must not be applied on top of target movement.
	(cursor.movement_anchor as Node3D).position.x += 3.0
	assert(is_equal_approx(cursor.get_mouse_ground_position().x, after.x))
	# Repeated reads must not duplicate the displacement.
	assert(cursor.get_mouse_ground_position().is_equal_approx(after))
	Input.action_release("MouseLeft")
	cursor._update_ground_transform(camera, 0.2)
	characters[1].position.x += 0.2
	cursor._update_ground_transform(camera, 0.2)
	assert(is_equal_approx(cursor.get_mouse_ground_position().x, after.x), "Release must stop following at the current real position")
	Input.action_press("MouseLeft")
	cursor._update_ground_transform(camera, 0.2)
	cursor._set_gameplay_cursor_active(false)
	assert(cursor._charge_follow_target == null, "Opening UI must cancel follow")
	Input.action_release("MouseLeft")
	cursor._set_gameplay_cursor_active(true)
	cursor.set_cursor_world_position((cursor._get_character_projection(characters[1]) as Dictionary).center)
	cursor._update_ground_transform(camera, 0.2)
	Input.action_press("MouseLeft")
	cursor._update_ground_transform(camera, 0.2)
	characters[1].queue_free()
	await process_frame
	cursor._update_ground_transform(camera, 0.2)
	assert(cursor.get_selected_character() == null and cursor._charge_follow_target == null)
	Input.action_release("MouseLeft")
	print("TERRAIN_CURSOR_CHARGE_FOLLOW_3D_VALIDATION_PASSED")
	quit()
