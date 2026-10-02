extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character: Node3D = load("res://Scenes/Creatures/Characters/Character_Test_Controlled.tscn").instantiate()
	root.add_child(character)
	await process_frame
	await physics_frame
	var skeleton: Skeleton3D = character.get_node("Character_Test_Skeleton/骨架/Skeleton3D")
	for attachment in skeleton.get_children():
		if attachment is BoneAttachment3D:
			assert(skeleton.find_bone(attachment.bone_name) >= 0,
				"Missing attachment bone: %s" % attachment.bone_name)
	var animation_player: AnimationPlayer = character.get_node("Character_Test_Skeleton/AnimationPlayer")
	var animation_root := animation_player.get_node(animation_player.root_node)
	for animation_name in [&"Idle", &"Walk"]:
		assert(animation_player.has_animation(animation_name))
		var animation := animation_player.get_animation(animation_name)
		for track_index in animation.get_track_count():
			var track_path := animation.track_get_path(track_index)
			var node_path := NodePath(str(track_path).get_slice(":", 0))
			assert(animation_root.get_node_or_null(node_path) != null,
				"Invalid animation track target: %s" % track_path)
	var state_machine: AnimationTree = character.get_node("Character_Test_Skeleton/AnimationTree")
	assert(state_machine.get_current_state() == &"Idle")
	character.global_position.x += 1.0
	state_machine._physics_process(0.1)
	assert(state_machine.get_current_state() == &"Walk")
	state_machine._physics_process(0.1)
	assert(state_machine.get_current_state() == &"Idle")
	print("CHARACTER_ANIMATION_STATE_MACHINE_VALIDATION_PASSED")
	character.queue_free()
	quit()
