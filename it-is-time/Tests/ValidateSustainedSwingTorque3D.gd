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
	var preset := arm.arm_swing_bindings[0].swing_preset.duplicate() as LimbSwingPresetBase
	arm.arm_swing_bindings[0].swing_preset = preset
	preset.swing_duration = 0.1
	preset.follow_through_ratio = 2.0
	preset.minimum_follow_through_time = 0.15
	preset.sustained_swing_enabled = true
	preset.sustained_swing_torque = 40.0
	preset.sustained_swing_duration = 0.22
	controller.refresh_arm_bindings()
	var state: Dictionary = controller._states[0].members[0]
	controller.begin_charge(0)
	controller.add_charge_time(0, 0.5)
	controller.release_charge(0)
	assert(is_equal_approx(controller._get_sustained_swing_torque(state).length(), 40.0))
	assert(controller._get_sustained_swing_torque(state).dot(state.release_axis_world) < 0.0)
	preset.sustained_swing_torque = 1000.0
	preset.sustained_swing_duration = 10.0
	controller._physics_process(0.12)
	assert(state.mode == LimbSwingController3D.SwingState.FOLLOW_THROUGH)
	assert(is_equal_approx(controller._get_sustained_swing_torque(state).length(), 40.0))
	controller._physics_process(0.11)
	assert(state.mode == LimbSwingController3D.SwingState.FOLLOW_THROUGH)
	assert(controller._get_sustained_swing_torque(state).is_zero_approx())
	controller._cancel_all_members()
	assert(controller._active_damage_swings == 0)
	preset.sustained_swing_duration = 0.6
	controller.begin_charge(0)
	controller.add_charge_time(0, 0.5)
	controller.release_charge(0)
	assert(is_equal_approx(state.attack_tuning.follow_time, 0.5))
	controller._physics_process(0.59)
	assert(state.mode == LimbSwingController3D.SwingState.FOLLOW_THROUGH)
	controller._physics_process(0.02)
	assert(state.mode == LimbSwingController3D.SwingState.RECOVERING)
	assert(controller._get_sustained_swing_torque(state).is_zero_approx())
	controller._cancel_all_members()
	preset.sustained_swing_enabled = false
	controller.begin_charge(0)
	controller.add_charge_time(0, 0.5)
	controller.release_charge(0)
	assert(controller._get_sustained_swing_torque(state).is_zero_approx())
	assert(is_equal_approx(state.attack_tuning.follow_time, 0.2))
	controller._cancel_all_members()
	# Prove that sustained torque alone accelerates the physical Arm.
	preset.sustained_swing_enabled = true
	preset.sustained_swing_torque = 4.0
	preset.sustained_swing_duration = 0.2
	preset.minimum_swing_torque = 0.0
	preset.maximum_swing_torque = 0.0
	preset.direction_hold_stiffness = 0.0
	preset.direction_hold_damping = 0.0
	arm.freeze = false
	arm.gravity_scale = 0.0
	arm.angular_velocity = Vector3.ZERO
	controller.begin_charge(0)
	controller.add_charge_time(0, 0.5)
	controller.release_charge(0)
	controller.set_physics_process(true)
	for frame in range(6):
		await physics_frame
	print("SUSTAINED_TORQUE_PHYSICS angular_velocity=%s" % arm.angular_velocity)
	if arm.angular_velocity.z >= -0.5:
		push_error("Sustained torque did not accelerate the Arm in the swing direction")
		quit(1)
		return
	controller._cancel_all_members()
	assert(controller._get_sustained_swing_torque(state).is_zero_approx())
	print("SUSTAINED_SWING_TORQUE_3D_VALIDATION_PASSED")
	quit()
