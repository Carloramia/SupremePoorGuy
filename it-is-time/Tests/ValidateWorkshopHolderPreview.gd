extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character := load(
		"res://Scenes/Creatures/Characters/Character_Test_2.tscn"
	).instantiate() as Node3D
	root.add_child(character)
	for body_name: StringName in [&"Torso", &"Leg_R", &"Leg_L", &"Arm_R", &"Arm_L", &"Head"]:
		(character.get_node(NodePath(body_name)) as RigidBody3D).freeze = true

	var workshop := load(
		"res://Scenes/Workshop/Playerworkshop.tscn"
	).instantiate() as CanvasLayer
	root.add_child(workshop)
	await process_frame
	var right_panel := workshop.get_node("WorkshopRightpanel")
	right_panel.select_holder(0)
	var socket_screen_position := Vector2(400.0, 400.0)
	assert(workshop.place_attachment_at_screen_position(socket_screen_position))
	var preview := workshop.get_node("AttachmentPreview") as Sprite2D
	var marker := workshop.get_node("AttachmentPointMarker") as Node2D
	var preview_pixel_size := preview.texture.get_size() * preview.scale
	assert(preview_pixel_size.is_equal_approx(Vector2(120.2, 120.2)))
	var socket := character.get_node("Arm_R/ItemSocket3D") as Marker3D
	var expected_center_offset := Vector2(-socket.position.x, socket.position.y) * 100.0
	assert(preview.position.is_equal_approx(socket_screen_position + expected_center_offset))
	assert(marker.position.is_equal_approx(socket_screen_position))
	assert(marker.visible)
	assert(is_zero_approx(preview.rotation))
	assert(is_zero_approx(marker.rotation))
	print("WORKSHOP_HOLDER_PREVIEW_VALIDATION_PASSED")
	workshop.queue_free()
	character.queue_free()
	quit()
