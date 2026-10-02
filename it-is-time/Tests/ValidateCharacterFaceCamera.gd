extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character: Node3D = load("res://Scenes/Creatures/Characters/Character_Test.tscn").instantiate()
	root.add_child(character)
	var camera_rig: Node3D = load("res://Scenes/Camera/DragCamera3D.tscn").instantiate()
	root.add_child(camera_rig)
	camera_rig.global_position = Vector3(7.0, 3.0, 5.0)
	camera_rig.rotation.y = 0.7
	await process_frame
	character._process(0.0)
	var camera: Camera3D = camera_rig.get_camera()
	var expected_direction := camera.global_basis.z
	expected_direction.y = 0.0
	expected_direction = expected_direction.normalized()
	var model_front := character.global_basis.z.normalized()
	assert(model_front.dot(expected_direction) > 0.999)
	print("CHARACTER_FACE_CAMERA_VALIDATION_PASSED")
	character.queue_free()
	camera_rig.queue_free()
	quit()
