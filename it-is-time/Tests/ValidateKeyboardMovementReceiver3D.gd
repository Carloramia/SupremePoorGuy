extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var target := Node3D.new()
	root.add_child(target)
	var camera_rig := Node3D.new()
	target.add_child(camera_rig)
	var first_camera := Camera3D.new()
	camera_rig.add_child(first_camera)
	var receiver: Node = load("res://Scenes/Input/KeyboardMovementReceiver3D.tscn").instantiate()
	receiver.break_on_ready = false
	receiver.break_on_first_movement = false
	target.add_child(receiver)
	await process_frame
	assert(receiver.get_camera() == first_camera)
	var start := target.global_position
	receiver._move_parent(1.0, 1.0)
	assert(target.global_position.x > start.x)
	var moved_right := target.global_position
	receiver._move_parent(-1.0, 1.0)
	assert(target.global_position.is_equal_approx(start))
	assert(not moved_right.is_equal_approx(start))
	Input.action_press(&"Right")
	receiver._physics_process(1.0)
	Input.action_release(&"Right")
	assert(target.global_position.x > start.x)
	print("KEYBOARD_MOVEMENT_RECEIVER_VALIDATION_PASSED")
	target.queue_free()
	quit()
