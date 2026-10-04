extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var cursor: Node3D = load("res://Scenes/Input/TerrainCursor3D.tscn").instantiate()
	cursor.input_enabled = false
	root.add_child(cursor)
	assert(cursor.process_mode == Node.PROCESS_MODE_ALWAYS)
	assert(cursor.get_node_or_null("Ring") is MeshInstance3D)
	assert(cursor.get_node_or_null("Glow") is MeshInstance3D)
	var camera := Camera3D.new()
	root.add_child(camera)
	var motion: Vector3 = cursor.get_camera_plane_motion(Vector2(10.0, -20.0), camera)
	assert(motion.x > 0.0)
	assert(motion.z < 0.0)
	assert(is_zero_approx(motion.y))
	var anchor := Node3D.new()
	root.add_child(anchor)
	cursor.movement_anchor = anchor
	cursor.set_cursor_world_position(Vector3(4.0, 0.0, 2.0))
	cursor.global_position = Vector3(4.0, 1.0, 2.0)
	anchor.position += Vector3(3.0, 5.0, -2.0)
	cursor._physics_process(0.0)
	assert(cursor.global_position.is_equal_approx(Vector3(7.0, 1.0, 0.0)))
	anchor.rotation.y = PI
	cursor._physics_process(0.0)
	assert(cursor.global_position.is_equal_approx(Vector3(7.0, 1.0, 0.0)))

	var level := load("res://Scenes/Levels/TestLevel.tscn").instantiate() as Node3D
	root.add_child(level)
	var level_cursor: Node3D = level.get_node("TerrainCursor3D") as Node3D
	assert(level_cursor != null)
	assert(level_cursor.movement_anchor == level.get_node("Flat/CharacterTest2/Torso"))
	await physics_frame
	await physics_frame
	assert(level_cursor.has_valid_ground_position())
	var blocking_interface := CanvasLayer.new()
	blocking_interface.add_to_group(&"ui_interface_2d")
	root.add_child(blocking_interface)
	level_cursor._process(0.0)
	assert(not level_cursor.is_gameplay_cursor_active())
	blocking_interface.queue_free()
	await process_frame
	level_cursor._process(0.0)
	assert(level_cursor.is_gameplay_cursor_active())
	print("TERRAIN_CURSOR_3D_VALIDATION_PASSED")
	level.queue_free()
	cursor.queue_free()
	camera.queue_free()
	anchor.queue_free()
	quit()
