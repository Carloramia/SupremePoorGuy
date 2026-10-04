extends SceneTree
func _initialize() -> void:
	call_deferred("_validate")
func _validate() -> void:
	var character := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	root.add_child(character)
	for node: Node in character.find_children("*", "RigidBody3D", true, false):
		(node as RigidBody3D).freeze = true
	var controller := character.get_node("LimbSwingController3D") as LimbSwingController3D
	controller.set_physics_process(false)
	var arm := character.get_node("Arm_R") as PhysicalBodyPart3D
	var joint := character.get_node("ShoulderJoint_R") as Generic6DOFJoint3D
	var preset := arm.arm_swing_bindings[0].swing_preset.duplicate() as LimbSwingPresetBase
	arm.arm_swing_bindings[0].swing_preset = preset
	var left_binding := ArmSwingBinding.new()
	left_binding.swing_preset = preset
	(character.get_node("Arm_L") as PhysicalBodyPart3D).arm_swing_bindings.append(left_binding)
	controller.refresh_arm_bindings()
	var cursor := load("res://Scenes/Input/TerrainCursor3D.tscn").instantiate() as TerrainCursor3D
	root.add_child(cursor)
	cursor.controlled_character = character
	controller.terrain_cursor = cursor
	var target := Node3D.new()
	root.add_child(target)
	cursor._set_selected_character(target)
	cursor._selected_ground_position = Vector3(10, 0, 0)
	Input.action_press("MouseLeft")
	assert(not cursor._dispatch_charge_angle_drag(Vector2(100, 0)), "Idle Arms must not consume drag")
	controller.begin_charge(0)
	var state: Dictionary = controller._states[0].members[0]
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(225, 0)
	cursor._input(event)
	assert(is_equal_approx(state.charge_bank_angle, PI * 0.5))
	assert(is_equal_approx(controller._states[0].members[1].charge_bank_angle, PI * 0.5), "All charging Arms must receive the same drag")
	assert(cursor._pending_mouse_motion.is_zero_approx(), "Dragging a charged Arm must not move the cursor out of selection")
	assert(not bool(joint.get("angular_limit_x/enabled")))
	var target_basis := controller._get_charge_bank_target_basis(state, cursor._selected_ground_position)
	assert(target_basis.z.dot(Vector3.DOWN) > 0.99, "A 90 degree bank must turn a vertical cut into a horizontal cut")
	cursor._dispatch_charge_angle_drag(Vector2(-450, 0))
	assert(is_equal_approx(state.charge_bank_angle, -PI * 0.5))
	cursor._dispatch_charge_angle_drag(Vector2(5000, 0))
	assert(is_equal_approx(state.charge_bank_angle, PI))
	preset.charge_angle_drag_enabled = false
	assert(not cursor._dispatch_charge_angle_drag(Vector2(10, 0)))
	preset.charge_angle_drag_enabled = true
	cursor._set_selected_character(null)
	controller._apply_charge_target_aim(0, state, 0.02)
	assert(not state.charge_bank_active and is_zero_approx(state.charge_bank_angle))
	assert(bool(joint.get("angular_limit_x/enabled")))
	controller._cancel_all_members()
	# The next attack starts with a fresh angle and reaches the requested pose via torque.
	cursor._set_selected_character(target)
	controller.begin_charge(0)
	assert(is_zero_approx(state.charge_bank_angle))
	cursor._dispatch_charge_angle_drag(Vector2(225, 0))
	arm.freeze = false
	controller.set_physics_process(true)
	for frame in range(120):
		await physics_frame
	target_basis = controller._get_charge_bank_target_basis(state, cursor._selected_ground_position)
	var error := (target_basis.get_rotation_quaternion() * arm.global_basis.orthonormalized().get_rotation_quaternion().inverse()).get_angle()
	error = minf(error, TAU - error)
	print("CHARGE_ANGLE_DRAG_PHYSICS angle_error_deg=%.2f plane_normal=%s" % [rad_to_deg(error), arm.global_basis.z])
	if error > deg_to_rad(20):
		push_error("Arm failed to reach the dragged charge angle")
		Input.action_release("MouseLeft")
		quit(1)
		return
	Input.action_release("MouseLeft")
	controller.release_charge(0)
	var release_axis: Vector3 = state.release_axis_world
	assert(release_axis.dot(Vector3.DOWN) > 0.8)
	assert(not cursor._dispatch_charge_angle_drag(Vector2(-100, 0)))
	for frame in range(10):
		await physics_frame
	assert(controller._get_member_axis_world(state).is_equal_approx(release_axis), "Release must preserve the dragged swing plane")
	controller._cancel_all_members()
	assert(bool(joint.get("angular_limit_x/enabled")) and bool(joint.get("angular_limit_y/enabled")))
	assert(state.release_joint_snapshot.is_empty())
	print("CHARGE_ANGLE_DRAG_3D_VALIDATION_PASSED")
	quit()
