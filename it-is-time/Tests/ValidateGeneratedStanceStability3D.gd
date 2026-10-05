extends SceneTree

const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Creature_Test.tscn")
var failed: bool = false

func check(condition: bool, message: String) -> void:
	if not condition:
		failed = true
		push_error(message)

func _initialize() -> void:
	call_deferred("_validate")

func _validate() -> void:
	var ground := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var character := CHARACTER.instantiate()
	character.generate_on_ready = false
	root.add_child(character)
	var generator := character.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((4) - 2, 0)
	generator.foreleg_count = mini((4), 2)
	generator.unsymmetrie = 0.0
	generator.overall_scale = 1.0
	generator.neck_number = 0

	generator._random.seed = 42
	check(character.generate_creature(), "Generation failed")
	var controller := character.get_node("GeneratedLegStepMovementController3D")
	controller.set_physics_process(false)
	var foot: RigidBody3D = controller.get_leg_parts()[0]
	var chain: Dictionary = controller._chains[foot]
	var collision_shape: CollisionShape3D = controller._find_leg_collision_shape(foot)
	var foot_basis := foot.global_basis
	foot.global_basis = Basis(Vector3.RIGHT, PI * 0.5)
	var expected_bottom: float = collision_shape.global_position.y - collision_shape.shape.size.z * 0.5
	check(absf(controller._get_foot_world_position(foot).y - expected_bottom) < 0.001, "Rolled feet must use the gravity-facing box extent")
	foot.global_basis = foot_basis
	var child: RigidBody3D = chain.bodies[1]
	var parent_body: RigidBody3D = chain.bodies[2]
	var rest: Quaternion = chain.rest_rotations[1]
	check(controller._calculate_stance_torque(child, parent_body, rest).length() < 0.001, "Rest pose should not produce torque")
	var child_basis := child.global_basis
	var parent_basis := parent_body.global_basis
	child.global_basis = Basis(Vector3.UP, 0.2) * child_basis
	var torque: Vector3 = controller._calculate_stance_torque(child, parent_body, rest)
	check(torque.dot(Vector3.UP) < 0.0, "Torque should oppose pose deformation")
	check(torque.length() <= controller.maximum_stance_torque + 0.001, "Torque cap exceeded")
	controller.refresh_physics_query_cache()
	chain = controller._chains[foot]
	check(absf(rest.dot(chain.rest_rotations[1])) > 0.9999, "Refreshing a deformed chain must preserve the generated rest pose")
	controller.set_physics_process(false)
	var yaw := Basis(Vector3.UP, 0.7)
	child.global_basis = yaw * child_basis
	parent_body.global_basis = yaw * parent_basis
	check(controller._calculate_stance_torque(child, parent_body, rest).length() < 0.001, "Common yaw must not be resisted")
	child.global_basis = child_basis
	parent_body.global_basis = parent_basis
	child.angular_velocity = Vector3.RIGHT
	check(controller._calculate_stance_torque(child, parent_body, rest).x < 0.0, "Damping should oppose relative velocity")
	child.angular_velocity = Vector3.ZERO
	# Place feet at their true ground-contact height without needing the full gait to settle.
	for leg: RigidBody3D in controller.get_leg_parts():
		leg.global_position.y = leg.get_meta(&"generated_size").y * 0.5
	await physics_frame
	await physics_frame
	var leg_count := 0
	var foreleg_count := 0
	for leg: RigidBody3D in controller.get_leg_parts():
		var leg_chain: Dictionary = controller._chains[leg]
		check(leg_chain.rest_rotations.size() == leg_chain.joints.size(), "Every joint needs a rest rotation")
		if 4 in leg.tags:
			foreleg_count += 1
			check(leg_chain.joints.size() == 3, "ForeLeg must include both Limb blocks")
		else:
			leg_count += 1
			check(leg_chain.joints.size() == 4, "Leg must include all three Limb blocks")
	check(leg_count > 0 and foreleg_count > 0, "Test must cover Leg and ForeLeg")
	check(controller._stance_chain_can_support(foot), "Grounded idle leg should support")
	controller._update_stance_allocation(1.0)
	var total_share := 0.0
	for share: float in controller._stance_support_weights.values(): total_share += share
	check(absf(total_share - 1.0) < 0.001, "Actual support forces must preserve total weight")
	check(controller._stance_total_mass > 0.0 and controller._stance_center_of_mass.is_finite(), "Body mass and COM must be available")
	check(controller._stance_joint_loads.size() > 0, "Leg chains must receive per-joint load estimates")
	var tested_joint: Generic6DOFJoint3D = chain.joints[-1]
	var original_load: Vector3 = controller._stance_joint_loads[tested_joint]
	var contact: Vector3 = controller._get_surface_below_leg(foot, controller.ground_probe_distance).position
	var total_weight: Vector3 = -controller._gravity_acceleration() * controller._stance_total_mass
	var share: float = controller._stance_support_weights[foot]
	var smoothing_time: float = controller.support_load_smoothing_time
	controller.support_load_smoothing_time = 0.0
	controller._last_torso_response_force = total_weight
	controller._update_stance_allocation(1.0)
	var expected_delta := (contact - tested_joint.global_position).cross(total_weight * share)
	check((controller._stance_joint_loads[tested_joint] - original_load).distance_to(expected_delta) < 0.001, "Existing Torso support must not be counted twice in joint load estimates")
	controller.support_load_smoothing_time = smoothing_time
	controller._last_torso_response_force = Vector3.ZERO
	controller._update_stance_allocation(1.0)
	controller._apply_stance_stabilization(0.05)
	check(float(chain.stance_weight) > 0.0 and float(chain.stance_weight) < 1.0, "Landing must fade in")
	controller._active_leg = foot
	controller._step_state = controller.StepState.MOVING
	controller._apply_stance_stabilization(0.05)
	check(is_zero_approx(chain.stance_weight), "Stepping chain must release stance torque")
	check(not controller._stance_support_weights.has(foot), "Stepping foot must leave support allocation immediately")
	controller.cancel_step()
	controller._adhesion_release_time_remaining = 0.5
	check(not controller._stance_chain_can_support(foot), "Jump release must disable stance")
	controller._adhesion_release_time_remaining = 0.0
	controller.stabilize_stance_limbs = false
	check(not controller._stance_chain_can_support(foot), "Inspector switch must disable stance")
	controller.stabilize_stance_limbs = true
	foot.global_position.y += 20.0
	await physics_frame
	check(not controller._stance_chain_can_support(foot), "Airborne leg must not stabilize")
	# Support allocation must preserve total load and shift it toward the COM.
	var contacts: Array[Vector3] = [Vector3(-1, 0, 0), Vector3(1, 0, 0)]
	var weights: PackedFloat64Array = controller._solve_stance_support_weights(contacts, Vector3(0.5, 1, 0), Vector3.UP)
	check(absf(weights[0] + weights[1] - 1.0) < 0.0001, "Support shares must sum to one")
	check(absf(weights[1] - 0.75) < 0.01, "Support shares must follow the COM")
	weights = controller._solve_stance_support_weights(contacts, Vector3(3, 1, 0), Vector3.UP)
	check(weights[0] >= 0.0 and weights[1] >= 0.0 and weights[1] > 0.99, "Outside-support COM must not request negative support")
	contacts = [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
	weights = controller._solve_stance_support_weights(contacts, Vector3.ZERO, Vector3.UP)
	check(absf(weights[0] - 1.0 / 3.0) < 0.001, "Coincident supports must remain finite and balanced")
	# Load compensation must survive a tiny pose acceleration limit unchanged.
	child.global_basis = child_basis
	parent_body.global_basis = parent_basis
	child.angular_velocity = Vector3.ZERO
	parent_body.angular_velocity = Vector3.ZERO
	controller.maximum_stance_acceleration = 0.0
	var static_load := Vector3(2000, 0, -1000)
	var compensation: Vector3 = controller._calculate_allocated_stance_torque(child, parent_body, rest, static_load, 1.0)
	check(compensation.is_equal_approx(static_load), "Pose acceleration limit must not attenuate gravity compensation")
	controller.maximum_stance_acceleration = 40.0
	# Limits must survive both mass/inertia scaling and the final fade-in multiplier.
	child.mass = 100.0
	parent_body.mass = 100.0
	var load := Vector3(500, 100, -300)
	controller.maximum_stance_torque = 7.0
	var allocated: Vector3 = controller._calculate_allocated_stance_torque(child, parent_body, rest, load, 0.5)
	check(allocated.is_finite() and allocated.length() <= 7.0001, "Final torque limit must apply after all scaling")
	check(controller._calculate_allocated_stance_torque(child, parent_body, rest, load, 0.0).is_zero_approx(), "Released support must produce zero torque")
	controller.scale_response_by_torso_mass = true
	controller.response_reference_mass = 0.01
	controller.maximum_torso_force = 3000.0
	check(controller._get_torso_response_force_limit(550.0) >= 550.0 * 9.8, "Heavy Torso feedback cap must cover its weight")
	check(controller._get_torso_response_force_limit(100000.0) <= controller.maximum_mass_scaled_torso_force, "Mass-scaled feedback must keep its safety cap")
	controller.mass_scaled_torso_force_limit = false
	controller.maximum_torso_force = 3.0
	controller.torso_movement_force_requires_leg_support = false
	controller._apply_torso_response()
	check(controller._last_torso_response_force.length() <= 3.0 * controller._get_configured_movement_scale() + 0.001, "Torso force cap must survive mass scaling")
	# Adhesion must pull toward the surface and damp lift-off without kicking a falling foot upward.
	var hit := {"position": controller._get_foot_world_position(foot), "normal": Vector3.UP}
	foot.linear_velocity = Vector3.ZERO
	var base_pull: Vector3 = controller._calculate_leg_adhesion_force(foot, hit, 1.0)
	check(base_pull.y < 0.0, "Idle adhesion must pull downward")
	foot.linear_velocity = Vector3.UP * 2.0
	var moving_pull: Vector3 = controller._calculate_leg_adhesion_force(foot, hit, 1.0)
	check(moving_pull.y < base_pull.y, "Adhesion must resist lift-off velocity")
	foot.linear_velocity = Vector3.DOWN * 100.0
	check(controller._calculate_leg_adhesion_force(foot, hit, 1.0).y <= 0.0, "Adhesion must never push a falling foot upward")
	foot.linear_velocity = Vector3.UP * 10000.0
	check(controller._calculate_leg_adhesion_force(foot, hit, 1.0).length() <= controller.maximum_foot_adhesion_force + 0.001, "Adhesion must obey its force cap")
	foot.linear_velocity = Vector3.ZERO
	var alignment_basis := foot.global_basis
	foot.global_basis = Basis.IDENTITY
	foot.angular_velocity = Vector3.UP * 5.0
	check(controller._calculate_foot_alignment_torque(foot, Vector3.UP).length() < 0.001, "Foot alignment must allow yaw")
	foot.angular_velocity = Vector3.ZERO
	foot.global_basis = Basis(Vector3.RIGHT, 0.2)
	var alignment: Vector3 = controller._calculate_foot_alignment_torque(foot, Vector3.UP)
	check(alignment.x < 0.0 and alignment.length() <= controller.maximum_foot_alignment_torque + 0.001, "Alignment must oppose tilt within its torque cap")
	foot.global_basis = alignment_basis
	controller._adhesion_release_time_remaining = 1.0
	controller.update_leg_surface_adhesion()
	check(controller._adhesion_forces.is_empty() and controller._foot_alignment_torques.is_empty(), "Jump release must disable pull and alignment")
	controller._adhesion_release_time_remaining = 0.0
	var intermediate: PhysicalBodyPart3D = chain.bodies[1]
	intermediate.break_part(null)
	check(not controller._stance_chain_can_support(foot), "Broken chain must not stabilize")
	character.queue_free()
	ground.queue_free()
	await process_frame
	if not failed: print("GENERATED_STANCE_STABILITY_VALIDATION_PASSED")
	quit(1 if failed else 0)
