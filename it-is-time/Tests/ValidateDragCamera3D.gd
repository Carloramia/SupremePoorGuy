extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var target := Node3D.new()
	root.add_child(target)
	target.global_position = Vector3(3.0, 2.0, -4.0)
	var rig: Node3D = load("res://Scenes/Camera/DragCamera3D.tscn").instantiate()
	rig.follow_target = target
	root.add_child(rig)
	await process_frame
	assert(rig.get_camera() is Camera3D)
	assert(rig.global_position.is_equal_approx(target.global_position))
	target.global_position = Vector3(-5.0, 1.5, 8.0)
	rig._process(0.0)
	assert(rig.global_position.is_equal_approx(target.global_position))
	target.global_position.y = 9.25
	rig._process(0.0)
	assert(is_equal_approx(rig.global_position.y, 9.25))
	assert(is_equal_approx(rig.get_distance(), 10.0))
	rig.set_distance(5000.0)
	assert(is_equal_approx(rig.get_distance(), rig.maximum_distance))
	rig.set_distance(10.0)
	var start_rotation: Vector3 = rig.rotation
	rig._orbit(Vector2.ONE)
	assert(not rig.rotation.is_equal_approx(start_rotation))
	print("DRAG_CAMERA_VALIDATION_PASSED")
	rig.queue_free()
	target.queue_free()
	quit()
