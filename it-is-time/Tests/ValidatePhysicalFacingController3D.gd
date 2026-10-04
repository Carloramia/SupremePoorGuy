extends SceneTree

const FacingControllerScript := preload("res://Scripts/Creatures/PhysicalFacingController3D.gd")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	for node: Node in character.find_children("*", "RigidBody3D", true, false):
		(node as RigidBody3D).freeze = true
	root.add_child(character)
	await process_frame
	var torso := character.get_node("Torso") as RigidBody3D
	var movement := character.get_node("LegStepMovementController3D")
	var controller: Node = character.get_node("PhysicalFacingController3D")
	assert(controller.get_facing() == FacingControllerScript.FacingDirection.RIGHT)
	assert(not controller.is_turning())
	assert(not torso.axis_lock_angular_y)
	assert(controller.is_direction_in_facing_sector(Vector3.RIGHT, FacingControllerScript.FacingDirection.RIGHT))
	assert(controller.is_direction_in_facing_sector(Vector3.LEFT, FacingControllerScript.FacingDirection.LEFT))
	assert(not controller.is_direction_in_facing_sector(Vector3.FORWARD, FacingControllerScript.FacingDirection.LEFT))
	assert(controller.request_facing(FacingControllerScript.FacingDirection.LEFT))
	assert(controller.is_turning())
	assert(movement.input_enabled)
	assert(not controller.has_method("calculate_turn_torque"))
	assert(controller.request_facing(FacingControllerScript.FacingDirection.RIGHT))
	# Crossing the +/-180 degree boundary must retain continuous physical progress.
	torso.rotation.y = deg_to_rad(179.0)
	controller._update_continuous_yaw()
	var yaw_before: float = controller._unwrapped_yaw
	torso.rotation.y = deg_to_rad(-179.0)
	controller._update_continuous_yaw()
	assert(is_equal_approx(rad_to_deg(controller._unwrapped_yaw - yaw_before), 2.0))
	assert(not controller.is_direction_in_facing_sector(Vector3.LEFT * 0.1, FacingControllerScript.FacingDirection.LEFT))
	character.queue_free()
	await process_frame
	var level := load("res://Scenes/Levels/TestLevel.tscn").instantiate() as Node3D
	for node: Node in level.find_children("*", "RigidBody3D", true, false):
		(node as RigidBody3D).freeze = true
	root.add_child(level)
	var level_character: Node3D = level.get_node("Flat/CharacterTest2")
	var level_torso := level_character.get_node("Torso") as RigidBody3D
	var level_controller: Node = level_character.get_node("PhysicalFacingController3D")
	var cursor: Node3D = level.get_node("TerrainCursor3D")
	cursor.set_cursor_world_position(
		level_torso.global_position - level_controller.get_right_reference() * 5.0
	)
	for _frame: int in 12:
		await physics_frame
	assert(level_controller.get_facing() == FacingControllerScript.FacingDirection.LEFT)
	assert(level_controller.is_turning())
	# Near-center mouse movement retains the target; reversing requires confirmation.
	cursor.set_cursor_world_position(level_torso.global_position)
	for _frame: int in 12:
		await physics_frame
	assert(level_controller.get_facing() == FacingControllerScript.FacingDirection.LEFT)
	cursor.set_cursor_world_position(level_torso.global_position + level_controller.get_right_reference() * 5.0)
	for _frame: int in 3:
		await physics_frame
	assert(level_controller.get_facing() == FacingControllerScript.FacingDirection.LEFT)
	for _frame: int in 10:
		await physics_frame
	assert(level_controller.get_facing() == FacingControllerScript.FacingDirection.RIGHT)
	var level_movement: Node = level_character.get_node("LegStepMovementController3D")
	assert(level_controller.request_facing(FacingControllerScript.FacingDirection.LEFT))
	assert(is_equal_approx(level_movement.surface_adhesion_force, 80.0))
	level_controller._update_turn_watchdog(level_controller.maximum_turn_duration + 0.1)
	assert(not level_controller.is_turning())
	assert(level_movement.input_enabled)
	assert(is_equal_approx(level_movement.surface_adhesion_force, 80.0))
	print("PHYSICAL_FACING_CONTROLLER_3D_VALIDATION_PASSED")
	level.queue_free()
	quit()
