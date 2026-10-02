extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character: Node3D = load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate()
	root.add_child(character)
	await process_frame
	var torso := character.get_node("Torso") as RigidBody3D
	var controller := torso.get_node("TorsoBalanceController3D")
	assert(controller.get_controlled_body() == torso)
	assert(controller.calculate_balance_torque(0.3, 0.0) < 0.0)
	assert(controller.calculate_balance_torque(-0.3, 0.0) > 0.0)
	assert(absf(controller.calculate_balance_torque(PI, 0.0)) <= controller.maximum_balance_torque)
	print("TORSO_BALANCE_CONTROLLER_VALIDATION_PASSED")
	character.queue_free()
	quit()
