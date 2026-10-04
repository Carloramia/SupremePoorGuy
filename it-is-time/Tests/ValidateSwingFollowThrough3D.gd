extends SceneTree
func _initialize() -> void:
	call_deferred("_validate")
func _validate() -> void:
	var character := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	root.add_child(character)
	for node: Node in character.find_children("*", "RigidBody3D", true, false):
		(node as RigidBody3D).freeze = true
	var controller := character.get_node("LimbSwingController3D") as LimbSwingController3D
	var arm := character.get_node("Arm_R") as PhysicalBodyPart3D
	var joint := character.get_node("ShoulderJoint_R") as Generic6DOFJoint3D
	var preset := arm.arm_swing_bindings[0].swing_preset.duplicate() as LimbSwingPresetBase
	arm.arm_swing_bindings[0].swing_preset = preset
	preset.swing_duration = 0.1
	preset.follow_through_ratio = 2.0
	preset.minimum_follow_through_time = 0.15
	controller.refresh_arm_bindings()
	assert(controller.begin_charge(0))
	controller.add_charge_time(0, 0.5)
	var state: Dictionary = controller._states[0].members[0]
	controller.release_charge(0)
	assert(is_equal_approx(state.attack_tuning.follow_time, 0.2))
	var fixed_axis: Vector3 = state.release_axis_world
	assert(not bool(joint.get("angular_limit_x/enabled")))
	assert(not bool(joint.get("angular_limit_y/enabled")))
	# Edits to a shared preset must not change an attack already released.
	preset.swing_duration = 0.5
	preset.follow_through_ratio = 10.0
	controller._physics_process(0.11)
	assert(state.mode == LimbSwingController3D.SwingState.FOLLOW_THROUGH)
	assert(is_equal_approx(state.time_remaining, 0.19))
	assert(controller._active_damage_swings == 1)
	arm.rotation = Vector3(0.0, 0.3, 0.0)
	assert(controller._get_member_axis_world(state).is_equal_approx(fixed_axis))
	controller._physics_process(0.2)
	assert(state.mode == LimbSwingController3D.SwingState.RECOVERING)
	assert(controller._active_damage_swings == 0)
	assert(not bool(joint.get("angular_limit_y/enabled")))
	arm.rotation = Vector3.ZERO
	controller._physics_process(0.4)
	assert(state.mode == LimbSwingController3D.SwingState.COOLDOWN)
	assert(bool(joint.get("angular_limit_x/enabled")))
	assert(bool(joint.get("angular_limit_y/enabled")))
	assert(bool(joint.get("angular_spring_z/enabled")))
	controller._cancel_all_members()
	preset.swing_duration = 0.1
	preset.follow_through_ratio = 2.0
	# Real oblique swing: stable release plane after the mouse is released.
	arm.freeze = false
	var cursor: Node = load("res://Scenes/Input/TerrainCursor3D.tscn").instantiate()
	root.add_child(cursor)
	controller.terrain_cursor = cursor
	var target := Node3D.new()
	root.add_child(target)
	cursor._set_selected_character(target)
	cursor._selected_ground_position = Vector3(8, 0, -8)
	Input.action_press("MouseLeft")
	controller.begin_charge(0)
	for frame in range(90):
		await physics_frame
	Input.action_release("MouseLeft")
	controller.release_charge(0)
	fixed_axis = state.release_axis_world
	var max_plane_error := 0.0
	for frame in range(15):
		await physics_frame
		var current := (arm.global_basis * (state.release_axis_body_local as Vector3)).normalized()
		max_plane_error = maxf(max_plane_error, acos(clampf(current.dot(fixed_axis), -1, 1)))
	assert(state.mode in [LimbSwingController3D.SwingState.SWINGING, LimbSwingController3D.SwingState.FOLLOW_THROUGH])
	assert(not bool(joint.get("angular_limit_y/enabled")))
	print("FOLLOW_THROUGH_PHYSICS plane_error_deg=%.2f" % rad_to_deg(max_plane_error))
	if max_plane_error > deg_to_rad(20):
		push_error("Oblique swing plane drifted excessively")
		quit(1)
		return
	for frame in range(100):
		await physics_frame
	assert(state.mode == LimbSwingController3D.SwingState.IDLE)
	assert(state.snapshot.is_empty() and state.release_joint_snapshot.is_empty())
	# Cancellation during follow through must balance damage bookkeeping and restore constraints.
	arm.freeze = true
	controller.begin_charge(0)
	controller.add_charge_time(0, 0.5)
	controller.release_charge(0)
	controller._physics_process(0.11)
	controller._cancel_all_members()
	assert(controller._active_damage_swings == 0)
	assert(bool(joint.get("angular_limit_y/enabled")))
	print("SWING_FOLLOW_THROUGH_3D_VALIDATION_PASSED")
	quit()
