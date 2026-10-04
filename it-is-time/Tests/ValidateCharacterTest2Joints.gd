extends SceneTree

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var character: Node3D = load("res://Scenes/Creatures/Characters/Character_Test_2.tscn").instantiate()
	(character.get_node("Torso") as RigidBody3D).freeze = true
	(character.get_node("Leg_R") as RigidBody3D).freeze = true
	(character.get_node("Leg_L") as RigidBody3D).freeze = true
	(character.get_node("Arm_R") as RigidBody3D).freeze = true
	(character.get_node("Arm_L") as RigidBody3D).freeze = true
	(character.get_node("Head") as RigidBody3D).freeze = true
	root.add_child(character)
	await process_frame
	var torso := character.get_node("Torso") as RigidBody3D
	var leg_r := character.get_node("Leg_R") as RigidBody3D
	var leg_l := character.get_node("Leg_L") as RigidBody3D
	var joint_r := character.get_node("HipJoint_R") as Generic6DOFJoint3D
	var joint_l := character.get_node("HipJoint_L") as Generic6DOFJoint3D
	var shoulder_r := character.get_node("ShoulderJoint_R") as Generic6DOFJoint3D
	var shoulder_l := character.get_node("ShoulderJoint_L") as Generic6DOFJoint3D
	var neck := character.get_node("NeckJoint") as Generic6DOFJoint3D
	assert(joint_r.node_a == NodePath("../Torso"))
	assert(joint_r.node_b == NodePath("../Leg_R"))
	assert(joint_l.node_a == NodePath("../Torso"))
	assert(joint_l.node_b == NodePath("../Leg_L"))
	assert(shoulder_r.node_a == NodePath("../Torso"))
	assert(shoulder_r.node_b == NodePath("../Arm_R"))
	assert(shoulder_l.node_a == NodePath("../Torso"))
	assert(shoulder_l.node_b == NodePath("../Arm_L"))
	assert(neck.node_a == NodePath("../Torso"))
	assert(neck.node_b == NodePath("../Head"))
	assert(joint_r.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING))
	assert(joint_l.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING))
	var right_stiffness := joint_r.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS)
	var left_stiffness := joint_l.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS)
	var right_damping := joint_r.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING)
	var left_damping := joint_l.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING)
	assert(right_stiffness > 0.0 and is_equal_approx(right_stiffness, left_stiffness))
	assert(right_damping > 0.0 and is_equal_approx(right_damping, left_damping))
	for joint: Generic6DOFJoint3D in [joint_r, joint_l]:
		assert(is_equal_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), 0.5))
		assert(is_equal_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT), -0.5))
		assert(is_equal_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), 0.5))
		assert(is_equal_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT), -0.5))
		assert(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), 0.5))
		assert(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT), -0.5))
	for joint: Generic6DOFJoint3D in [shoulder_r, shoulder_l, neck]:
		assert(joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_SPRING))
		assert(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_STIFFNESS) > 0.0)
		assert(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_SPRING_DAMPING) > 0.0)
	assert(is_equal_approx(shoulder_r.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), 0.2))
	assert(is_equal_approx(shoulder_l.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), 0.2))
	assert(is_equal_approx(neck.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT), 0.15))
	assert(not torso.axis_lock_linear_z and not leg_r.axis_lock_linear_z and not leg_l.axis_lock_linear_z)
	assert(torso.axis_lock_angular_x and not torso.axis_lock_angular_y)
	assert(not leg_r.axis_lock_angular_y and not leg_l.axis_lock_angular_y)
	assert(character.get_node_or_null("PhysicalFacingController3D") != null)
	assert(leg_r.tags[0] == leg_r.BodyPartTag.Leg)
	assert(leg_l.tags[0] == leg_l.BodyPartTag.Leg)
	var movement_controller := character.get_node("LegStepMovementController3D")
	movement_controller._expand_hip_joint_for_step(
		leg_r,
		leg_r.global_position + Vector3.RIGHT * 1.0
	)
	assert(joint_r.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT) > 0.5)
	assert(is_equal_approx(
		joint_r.get_param_z(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),
		0.5
	))
	assert(is_equal_approx(
		joint_l.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),
		0.5
	))
	movement_controller.restore_base_hip_joint_limits()
	assert(is_equal_approx(
		joint_r.get_param_x(Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT),
		0.5
	))
	var leg_shape := leg_r.get_node("CollisionShape3D").shape as BoxShape3D
	assert(leg_shape.size.is_equal_approx(Vector3(
		leg_r.left_distance + leg_r.right_distance,
		leg_r.top_distance + leg_r.bottom_distance,
		leg_r.collision_thickness
	)))
	print("CHARACTER_TEST_2_JOINT_VALIDATION_PASSED")
	character.queue_free()
	quit()
