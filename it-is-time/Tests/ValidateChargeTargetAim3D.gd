extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	for node: Node in character.find_children("*", "RigidBody3D", true, false):
		(node as RigidBody3D).freeze = true
	root.add_child(character)
	var controller: Node = character.get_node("LimbSwingController3D")
	var arm := character.get_node("Arm_R") as RigidBody3D
	var joint := character.get_node("ShoulderJoint_R") as Generic6DOFJoint3D
	var cursor: Node = load("res://Scenes/Input/TerrainCursor3D.tscn").instantiate()
	root.add_child(cursor)
	controller.terrain_cursor = cursor
	var target := Node3D.new()
	target.name = "AimTarget"
	root.add_child(target)
	cursor._set_selected_character(target)
	cursor._selected_ground_position = Vector3(2.0, 0.0, -10.0)
	var original_limit: bool = joint.get("angular_limit_y/enabled")
	assert(controller.begin_charge(0))
	var state: Dictionary = controller._states[0].members[0]
	var aim: Dictionary = controller._calculate_target_aim(state, cursor._selected_ground_position)
	assert(aim.torque.y > 0.0 and is_zero_approx(aim.torque.x) and is_zero_approx(aim.torque.z))
	assert(aim.torque.length() <= state.preset.maximum_target_aim_torque)
	controller._apply_charge_target_aim(0, state, 0.1)
	assert(not bool(joint.get("angular_limit_y/enabled")))
	var opposite: Dictionary = controller._calculate_target_aim(state, Vector3(2.0, 0.0, 10.0))
	assert(opposite.torque.y < 0.0)
	cursor._set_selected_character(null)
	controller._apply_charge_target_aim(0, state, 0.1)
	assert((state.aim_joint_snapshot as Dictionary).is_empty())
	assert(bool(joint.get("angular_limit_y/enabled")) == original_limit)
	cursor._set_selected_character(target)
	controller._apply_charge_target_aim(0, state, 0.1)
	var axis_before: Vector3 = controller._get_member_axis_world(state)
	arm.rotation.y = PI * 0.5
	var axis_after: Vector3 = controller._get_member_axis_world(state)
	assert(axis_after.dot(axis_before) < 0.1, "Swing plane must follow aimed Arm heading")
	controller.add_charge_time(0, 0.5)
	controller.release_charge(0)
	assert(not (state.aim_joint_snapshot as Dictionary).is_empty(), "Keep yaw available during the released swing")
	controller._physics_process(2.0)
	assert((state.aim_joint_snapshot as Dictionary).is_empty())
	assert(bool(joint.get("angular_limit_y/enabled")) == original_limit)
	controller._cancel_all_members()
	arm.rotation = Vector3.ZERO
	arm.angular_velocity = Vector3.ZERO
	arm.freeze = false
	Input.action_press("MouseLeft")
	assert(controller.begin_charge(0))
	var initial_error: float = absf(controller._calculate_target_aim(state, cursor._selected_ground_position).error)
	for frame in range(90):
		await physics_frame
	var final_error: float = absf(controller._calculate_target_aim(state, cursor._selected_ground_position).error)
	Input.action_release("MouseLeft")
	controller._cancel_all_members()
	print("TARGET_AIM_PHYSICS initial_error_deg=%.2f final_error_deg=%.2f" % [rad_to_deg(initial_error), rad_to_deg(final_error)])
	if final_error >= initial_error * 0.75:
		push_error("Arm did not turn toward selected target in physics simulation")
		quit(1)
		return
	print("CHARGE_TARGET_AIM_3D_VALIDATION_PASSED")
	quit()
