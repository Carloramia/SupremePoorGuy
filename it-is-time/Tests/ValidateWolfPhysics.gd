extends SceneTree

func _initialize() -> void: call_deferred("run")

func check(actor: Node) -> void:
	var action = actor.get_node("CreatureActionController3D")
	assert(not action.enabled and action.actions.is_empty())
	assert(not action.has_npc_attack(&"foreleg_stomp"))
	assert(not action.has_input_action(&"MouseLeft"))
	var state_machine := actor.get_node_or_null("NPCStateMachine3D")
	if state_machine != null:
		assert(state_machine.attack_execution_enabled)
		assert(state_machine.behavior.attacks.size() == 2)
		assert(state_machine._available_attacks().size() == 2)
		for attack in state_machine._available_attacks():
			assert(attack.action_id in [&"wolf_pounce",&"wolf_bite"])
	var movement = actor.get_node("GeneratedLegStepMovementController3D")
	assert(movement.get_script().resource_path == "res://Scripts/Creatures/WolfLegStepMovementController3D.gd")
	var reference_count := 0
	var thigh_reference: Quaternion
	for foot: RigidBody3D in movement._chains:
		if foot.name == &"Leg_1": thigh_reference = movement._chains[foot].bodies[3].global_basis.orthonormalized().get_rotation_quaternion()
	for foot: RigidBody3D in movement._chains:
		var chain: Dictionary = movement._chains[foot]
		for joint: Generic6DOFJoint3D in chain.joints:
			var foreleg: bool = movement._has_body_tag(foot,movement.FORELEG_TAG)
			var protected_elbow: bool = actor.wolf_physics.foreleg_anti_reverse_enabled and joint.has_meta(&"wolf_elbow_z_limits")
			assert(joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT) == (protected_elbow or not foreleg or not actor.wolf_physics.foreleg_z_rotation_unlimited))
		if foot.name in [&"Leg_1",&"Leg_2"]:
			assert(chain.has("wolf_natural_pose"))
			var reference: Dictionary = chain.wolf_natural_pose
			assert(reference.thigh_rotation.is_equal_approx(thigh_reference))
			assert(reference.knee_angle_degrees>=79.99 and reference.knee_angle_degrees<=90.01)
			assert(reference.subtorso_x_error<0.01)
			assert(not reference.active_restoring_torque)
			assert(is_equal_approx(movement._get_passive_limb_damping(foot),actor.wolf_physics.hind_limb_hinge_damping))
			reference_count += 1
		else: assert(not chain.has("wolf_natural_pose"))
	assert(reference_count==2)
	assert(movement.foot_joint_yaw_lock_enabled and movement.action_heading_hold_enabled)
	assert(movement.slow_gait_data.resource_path == "res://Resources/Movement/WolfWalk.tres")
	assert(movement.independent_torso_height_support)
	assert(movement.sub_torso_support_enabled and movement.support_foot_lock_enabled and movement.surface_adhesion_enabled)
	assert(is_equal_approx(movement.sub_torso_weight_share, 1.0))
	assert(movement.auxiliary_support_weight_limit > 1.0)
	for foot: RigidBody3D in movement._chains:
		var chain: Dictionary = movement._chains[foot]
		var hip: Generic6DOFJoint3D = chain.joints.back()
		for axis: String in ["x", "y", "z"]:
			assert(hip.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_LIMIT))
			assert(is_zero_approx(hip.call("get_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_LOWER_LIMIT)))
			assert(is_zero_approx(hip.call("get_param_" + axis, Generic6DOFJoint3D.PARAM_LINEAR_UPPER_LIMIT)))
			assert(not hip.call("get_flag_" + axis, Generic6DOFJoint3D.FLAG_ENABLE_LINEAR_SPRING))
		assert(foot.get_node("CollisionShape3D").shape != null)
	actor.apply_grounded_standing_pose(movement, 0.016)
	assert(actor.get_standing_pose_diagnostics().is_empty())
	var container = actor.get_node("GeneratedParts")
	for body in container.get_children():
		if body is PhysicalBodyPart3D and PhysicalBodyPart3D.BodyPartTag.LegLimb in body.tags:
			assert(body.ignore_limb_terrain == not actor.wolf_physics.limb_terrain_collisions_enabled)
	var original_mass: float = container.get_node("SubTorso_Leg_1").mass
	actor._configure_wolf_physics(container)
	for foot: RigidBody3D in movement._chains:
		if movement._has_body_tag(foot,movement.FORELEG_TAG):
			for joint: Generic6DOFJoint3D in movement._chains[foot].joints:
				var protected_elbow: bool = actor.wolf_physics.foreleg_anti_reverse_enabled and joint.has_meta(&"wolf_elbow_z_limits")
				assert(joint.get_flag_z(Generic6DOFJoint3D.FLAG_ENABLE_ANGULAR_LIMIT) == (protected_elbow or not actor.wolf_physics.foreleg_z_rotation_unlimited))
	assert(is_equal_approx(original_mass, container.get_node("SubTorso_Leg_1").mass))
	for support in container.get_children():
		if support is RigidBody3D and str(support.name).begins_with("SubTorso"):
			assert(support.mass >= 0.15)
	for joint in container.get_node("Joints").get_children():
		if not joint is Generic6DOFJoint3D or not joint.has_meta("authored_walk_limits"): continue
		var limits: Vector3 = joint.get_meta("authored_walk_limits")
		assert(is_zero_approx(joint.get_param_y(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT)))
		assert(is_equal_approx(joint.get_param_x(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), limits.x))
		if joint.has_meta(&"wolf_bend_z_limits"):
			var elbow: Vector2 = joint.get_meta(&"wolf_bend_z_limits")
			assert(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_LOWER_LIMIT),elbow.x))
			assert(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT),elbow.y))
			continue
		assert(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), limits.z))
	var feet: Array[RigidBody3D] = []
	feet.append(container.get_node("ForeLeg_1"))
	actor.set_limb_action_limits(feet, true)
	assert(not actor._action_joint_limits.is_empty())
	for joint in actor._action_joint_limits:
		assert(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), deg_to_rad(75.0)))
	actor.set_limb_action_limits(feet, false)
	assert(actor._action_joint_limits.is_empty())
	for joint in container.get_node("Joints").get_children():
		if joint.has_meta("authored_walk_limits"):
			if joint.has_meta(&"wolf_bend_z_limits"): continue
			var limits: Vector3 = joint.get_meta("authored_walk_limits")
			assert(is_equal_approx(joint.get_param_z(Generic6DOFJoint3D.PARAM_ANGULAR_UPPER_LIMIT), limits.z))
	movement.recovery_control_active = true
	actor.apply_grounded_standing_pose(movement, 0.016)
	assert(actor.get_standing_pose_diagnostics().is_empty())
	movement.recovery_control_active = false

func run() -> void:
	for scene in ["Generate_Wolf", "Generate_Wolf_NPC"]:
		var actor = load("res://Scenes/Creatures/Characters/" + scene + ".tscn").instantiate()
		root.add_child(actor)
		var transforms = {}
		for part in actor.get_node("GeneratedParts").get_children():
			if part is RigidBody3D: transforms[str(part.name)] = part.transform
		check(actor)
		for repeat in 2:
			assert(actor.generate_creature())
			check(actor)
			for name in transforms:
				assert(actor.get_node("GeneratedParts/" + name).transform.is_equal_approx(transforms[name]), name)
		actor.free()
	print("PASS: Wolf/NPC saved and regenerated physics, unchanged SubTorso positions and all body poses, action limits and recovery exclusion.")
	quit()
