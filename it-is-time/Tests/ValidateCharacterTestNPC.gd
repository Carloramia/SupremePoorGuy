extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character: Node3D = load("res://Scenes/Creatures/Characters/Character_Test_NPC.tscn").instantiate()
	for body_name: StringName in [&"Torso", &"Leg_R", &"Leg_L", &"Arm_R", &"Arm_L", &"Head"]:
		(character.get_node(NodePath(body_name)) as RigidBody3D).freeze = true
	root.add_child(character)
	await process_frame
	var state_machine := character.get_node("NPCStateMachine3D")
	var movement_controller := character.get_node("NPCLegStepMovementController3D")
	assert(state_machine.get("current_state") == state_machine.State.IDLE)
	assert(movement_controller.get("_state_machine") == state_machine)
	assert(movement_controller.get_input_movement_direction().is_zero_approx())
	assert(not state_machine.is_fast_movement_requested())
	assert(not movement_controller.is_fast_speed_active())
	assert(movement_controller.get_current_speed_preset_name() == "SLOW")
	state_machine.move_to_position(Vector3(5.0, 0.0, 0.0))
	await physics_frame
	assert(state_machine.get("current_state") == state_machine.State.MOVE_TO_TARGET)
	assert(not state_machine.is_fast_movement_requested())
	assert(not movement_controller.is_fast_speed_active())
	assert(movement_controller.get_current_speed_preset_name() == "SLOW")
	# Without a NavigationRegion in this isolated test, the controller must wait instead of walking directly.
	assert(movement_controller.get_input_movement_direction().is_zero_approx())
	state_machine.stop()
	assert(movement_controller.get_input_movement_direction().is_zero_approx())
	assert(character.has_node("ShoulderJoint_R"))
	assert(character.has_node("ShoulderJoint_L"))
	assert(character.has_node("NeckJoint"))
	print("CHARACTER_TEST_NPC_VALIDATION_PASSED")
	character.queue_free()
	quit()
