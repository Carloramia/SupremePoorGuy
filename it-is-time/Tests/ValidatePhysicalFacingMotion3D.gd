extends SceneTree

class TestInputSource extends Node:
	func get_movement_direction() -> Vector3:
		return Vector3(Input.get_action_strength("Right") - Input.get_action_strength("Left"), 0.0, Input.get_action_strength("Down") - Input.get_action_strength("Up")).normalized()
	func is_jump_requested() -> bool: return Input.is_action_just_pressed("Space")
	func is_fast_requested() -> bool: return Input.is_action_pressed("Shift")

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var ground := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(100.0, 1.0, 100.0)
	collider.shape = shape
	ground.add_child(collider)
	ground.position.y = -0.5
	root.add_child(ground)
	var character := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	root.add_child(character)
	for node: Node in character.find_children("*", "RigidBody3D", true, false):
		var body := node as RigidBody3D
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
	var movement: Node = character.get_node("LegStepMovementController3D")
	var source := TestInputSource.new()
	root.add_child(source)
	movement.command_source = source
	var controller: Node = character.get_node("PhysicalFacingController3D")
	var completions := {"count": 0}
	controller.turn_completed.connect(func(_facing: int) -> void: completions.count += 1)
	var torso := character.get_node("Torso") as RigidBody3D
	var initial_right: Vector3 = controller.get_right_reference()
	for _frame: int in 120:
		await physics_frame
	var start_position := torso.global_position
	Input.action_press("Right")
	assert(controller.request_facing(1))
	assert(movement.input_enabled)
	var stepping_legs: Array[StringName] = []
	var highest_leg_y: float = 0.0
	for _frame: int in 360:
		if _frame == 60:
			Input.action_release("Right")
			Input.action_press("Left")
		if _frame == 90:
			Input.action_release("Left")
		await physics_frame
		if _frame < 90:
			assert(controller.get_facing() == 1)
			assert(movement.input_enabled)
		if _frame == 59:
			assert(torso.global_position.x > start_position.x + 0.1)
		var active_leg: RigidBody3D = movement.get_active_leg()
		if active_leg != null:
			highest_leg_y = maxf(highest_leg_y, active_leg.global_position.y)
			if stepping_legs.is_empty() or stepping_legs[-1] != active_leg.name:
				stepping_legs.append(active_leg.name)
	var final_right := torso.global_basis.x.slide(Vector3.UP).normalized()
	assert(final_right.dot(-initial_right) > 0.98)
	assert(not controller.is_turning())
	assert(completions.count == 1)
	assert(movement.input_enabled)
	assert(absf(torso.angular_velocity.y) < 0.25)
	assert(stepping_legs.size() >= 2)
	assert(stepping_legs[0] != stepping_legs[1])
	assert(highest_leg_y > 1.0)
	Input.action_press("Up")
	Input.action_press("Shift")
	assert(controller.request_facing(0))
	assert(movement.input_enabled)
	for _frame: int in 720:
		if _frame == 60:
			Input.action_release("Up")
			Input.action_release("Shift")
		await physics_frame
		if _frame < 60:
			assert(controller.get_facing() == 0)
			assert(movement.input_enabled)
	final_right = torso.global_basis.x.slide(Vector3.UP).normalized()
	assert(final_right.dot(initial_right) > 0.98)
	assert(not controller.is_turning())
	assert(completions.count == 2)
	assert(movement.input_enabled)
	assert(absf(torso.angular_velocity.y) < 0.25)
	print("PHYSICAL_FACING_MOTION_3D_VALIDATION_PASSED")
	character.queue_free()
	ground.queue_free()
	quit()
