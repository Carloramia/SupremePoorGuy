extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character := load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate() as Node3D
	root.add_child(character)
	for body_name: StringName in [&"Torso", &"Leg_R", &"Leg_L", &"Arm_R", &"Arm_L", &"Head"]:
		(character.get_node(NodePath(body_name)) as RigidBody3D).freeze = true
	var controller := character.get_node("LimbSwingController3D") as LimbSwingController3D
	var group := controller.control_groups[0]
	var arm_r := character.get_node("Arm_R") as PhysicalBodyPart3D
	var arm_l := character.get_node("Arm_L") as PhysicalBodyPart3D
	assert(group.group_name == &"PrimaryArm")
	assert(group.input_action == &"MouseLeft")
	assert(arm_r.arm_swing_bindings.size() == 1)
	var primary_binding := arm_r.arm_swing_bindings[0]
	assert(primary_binding.control_group_name == &"PrimaryArm")
	assert(primary_binding.swing_preset.resource_path == "res://Resources/Combat/PrimaryArmSwing.tres")
	assert(controller.get_group_member_count(0) == 1)
	var preset := primary_binding.swing_preset.duplicate() as LimbSwingPresetBase
	primary_binding.swing_preset = preset
	var left_binding := ArmSwingBinding.new()
	left_binding.control_group_name = &"PrimaryArm"
	left_binding.swing_preset = preset
	arm_l.arm_swing_bindings.append(left_binding)
	controller.refresh_arm_bindings()
	controller.set_diagnostic_logging_enabled(true)
	assert(controller.get_group_member_count(0) == 2)
	var test_load := RigidBody3D.new()
	test_load.name = "DiagnosticHeavyWeapon"
	test_load.mass = 12.0
	test_load.freeze = true
	character.add_child(test_load)
	test_load.global_position = arm_r.global_position + Vector3(1.0, -1.0, 0.0)
	var test_equipment_joint := Generic6DOFJoint3D.new()
	test_equipment_joint.name = "DiagnosticEquipmentJoint"
	character.add_child(test_equipment_joint)
	test_equipment_joint.node_a = test_equipment_joint.get_path_to(arm_r)
	test_equipment_joint.node_b = test_equipment_joint.get_path_to(test_load)

	var joint := character.get_node("ShoulderJoint_R") as Generic6DOFJoint3D
	var shoulder_l := character.get_node("ShoulderJoint_L") as Generic6DOFJoint3D
	var original_lower: float = joint.get("angular_limit_z/lower_angle")
	var original_upper: float = joint.get("angular_limit_z/upper_angle")
	var original_enabled: bool = joint.get("angular_spring_z/enabled")
	var original_stiffness: float = joint.get("angular_spring_z/stiffness")
	var original_damping: float = joint.get("angular_spring_z/damping")
	var original_equilibrium: float = joint.get("angular_spring_z/equilibrium_point")
	# Joint3D's scene node does not follow the live physics anchor. Simulate the
	# stale-node offset observed after the character has fallen from spawn height.
	joint.global_position += Vector3(10.0, 10.0, 0.0)
	assert(controller._get_anti_gravity_rotation_sign(
		arm_r,
		joint,
		joint.global_basis.z.normalized(),
		Vector3.DOWN
	) < 0.0)

	assert(controller.begin_charge(0))
	assert(controller.get_group_state(0) == LimbSwingController3D.SwingState.CHARGING)
	var direction_snapshot: Dictionary = controller._states[0].members[0].snapshot
	assert(direction_snapshot.has(&"signed_sine"))
	assert(direction_snapshot.has(&"combined_signed_sine"))
	assert(is_equal_approx(float(direction_snapshot.attached_mass), 12.0))
	assert(float(direction_snapshot.signed_sine) > 0.0)
	assert(float(direction_snapshot.world_lift_sign) > 0.0)
	assert(direction_snapshot.anchor_position.distance_to(joint.global_position) > 9.0)
	assert(is_equal_approx(
		float(joint.get("angular_spring_z/equilibrium_point")),
		deg_to_rad(-preset.lift_angle_degrees)
	))
	assert(controller._get_anti_gravity_rotation_sign(arm_l, shoulder_l, shoulder_l.global_basis.z.normalized(), Vector3.DOWN) < 0.0)
	controller.add_charge_time(0, 0.1)
	assert(controller.release_charge(0))
	assert(controller.get_group_state(0) == LimbSwingController3D.SwingState.IDLE)
	_assert_joint_restored(joint, original_lower, original_upper, original_enabled, original_stiffness, original_damping, original_equilibrium)

	assert(controller.begin_charge(0))
	controller.add_charge_time(0, 0.825)
	assert(controller.release_charge(0))
	assert(controller.get_group_state(0) == LimbSwingController3D.SwingState.SWINGING)
	var expected_charge_ratio := clampf(
		(0.825 - preset.minimum_charge_time)
		/ maxf(preset.maximum_charge_time - preset.minimum_charge_time, 0.001),
		0.0,
		1.0
	)
	var expected_torque := lerpf(
		preset.minimum_swing_torque,
		preset.maximum_swing_torque,
		expected_charge_ratio
	)
	assert(is_equal_approx(controller.get_group_swing_torque(0), expected_torque))
	controller._physics_process(preset.swing_duration + 0.01)
	assert(controller.get_group_state(0) == LimbSwingController3D.SwingState.SWINGING)
	# Sustained torque can outlast follow-through; advance through the real recovery phase.
	for tick: int in range(1000):
		controller._physics_process(0.01)
		var recovered := true
		for member: Dictionary in controller._states[0].members:
			if int(member.mode) != LimbSwingController3D.SwingState.COOLDOWN: recovered = false
		if recovered: break
	assert(controller.get_group_state(0) == LimbSwingController3D.SwingState.COOLDOWN)
	_assert_joint_restored(joint, original_lower, original_upper, original_enabled, original_stiffness, original_damping, original_equilibrium)
	controller._physics_process(preset.cooldown_duration + 0.01)
	assert(controller.get_group_state(0) == LimbSwingController3D.SwingState.IDLE)

	# One Arm can be registered to multiple groups. An active group owns the
	# physical joint until it returns to idle, preventing conflicting writes.
	var secondary_group := SwingControlGroup.new()
	secondary_group.group_name = &"SecondaryArm"
	secondary_group.input_action = &"MouseLeft"
	controller.control_groups.append(secondary_group)
	var secondary_binding := ArmSwingBinding.new()
	secondary_binding.control_group_name = &"SecondaryArm"
	secondary_binding.swing_preset = preset
	arm_r.arm_swing_bindings.append(secondary_binding)
	controller.refresh_arm_bindings()
	assert(controller.get_group_member_count(0) == 2)
	assert(controller.get_group_member_count(1) == 1)
	assert(controller.begin_charge(0))
	assert(not controller.begin_charge(1))
	assert(controller.release_charge(0))
	assert(controller.begin_charge(1))
	var secondary_snapshot: Dictionary = controller._states[1].members[0].snapshot
	assert(float(secondary_snapshot.world_lift_sign) > 0.0)
	assert(secondary_snapshot.anchor_position.distance_to(joint.global_position) > 9.0)
	assert(controller.release_charge(1))

	print("LIMB_SWING_CONTROLLER_3D_VALIDATION_PASSED")
	character.queue_free()
	quit()

func _assert_joint_restored(
	joint: Generic6DOFJoint3D,
	lower: float,
	upper: float,
	enabled: bool,
	stiffness: float,
	damping: float,
	equilibrium: float
) -> void:
	assert(is_equal_approx(float(joint.get("angular_limit_z/lower_angle")), lower))
	assert(is_equal_approx(float(joint.get("angular_limit_z/upper_angle")), upper))
	assert(bool(joint.get("angular_spring_z/enabled")) == enabled)
	assert(is_equal_approx(float(joint.get("angular_spring_z/stiffness")), stiffness))
	assert(is_equal_approx(float(joint.get("angular_spring_z/damping")), damping))
	assert(is_equal_approx(float(joint.get("angular_spring_z/equilibrium_point")), equilibrium))
