extends SceneTree
const CHARACTER = preload("res://Scenes/Creatures/Characters/Generate_Beast.tscn")
var failed := false
func check(value: bool, message: String) -> void:
	if not value:
		failed = true
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var ground := StaticBody3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(200, 1, 200)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	ground.add_child(collision)
	ground.position.y = -0.5
	root.add_child(ground)
	var actor := CHARACTER.instantiate()
	actor.generate_on_ready = false
	root.add_child(actor)
	var generator := actor.get_node("CreatureGenerator")
	generator.rear_leg_count = maxi((4) - 2, 0)
	generator.foreleg_count = mini((4), 2)
	generator.overall_scale = 1.0
	generator.unsymmetrie = 0.0
	generator.neck_number = 0

	generator._random.seed = 42
	check(actor.generate_creature(), "Generation failed")
	var controller := actor.get_node("GeneratedLegStepMovementController3D")
	controller.set_physics_process(false)
	actor.get_node("CreatureRecoveryStateMachine3D").set_physics_process(false)
	var parts: Array[RigidBody3D] = actor._get_physical_body_parts()
	for part: RigidBody3D in parts:
		part.freeze = true
		if part.get_meta("generated_role") == "Limb":
			check(PhysicalBodyPart3D.BodyPartTag.LegLimb in part.tags, "Every limb block needs LegLimb")
			check(part not in controller.get_leg_parts(), "Limb blocks must not be stepping feet")
		check(ground not in part.get_collision_exceptions(), "Ground must remain collidable")
	check(actor.get_internal_collision_diagnostics().missing_pairs == 0, "All pairs must ignore collision before physics")
	var foot: RigidBody3D = controller.get_leg_parts()[0]
	var chain: Dictionary = controller._chains[foot]
	for part: RigidBody3D in chain.bodies: part.global_position.y += 100.0
	var limb: RigidBody3D = chain.bodies[1]
	limb.global_basis = Basis.IDENTITY
	limb.global_position.y -= controller._get_foot_world_position(limb).y
	await physics_frame
	await physics_frame
	check(not controller.is_leg_grounded(foot), "Test sole must be airborne")
	check(controller._stance_chain_can_support(foot), "Grounded intermediate limb must support an airborne sole")
	var contact: Dictionary = controller._get_stance_chain_contact(foot)
	check(contact.get("body") == limb and contact.get("index") == 1, "Contact must identify the limb")
	# A knee contact changes ground-reaction loads only on proximal joints.
	var torso: RigidBody3D = chain.root
	torso.freeze = false
	controller._last_torso_response_force = Vector3.ZERO
	controller._update_stance_allocation(1.0)
	var distal_load: Vector3 = controller._stance_joint_loads[chain.joints[0]]
	var total_share := 0.0
	for share: float in controller._stance_support_weights.values(): total_share += share
	check(absf(total_share - 1.0) < 0.001, "Limb contacts must not duplicate a chain's weight share")
	controller._last_torso_response_force = -controller._gravity_acceleration() * controller._stance_total_mass
	controller._update_stance_allocation(1.0)
	check(controller._stance_joint_loads[chain.joints[0]].distance_to(distal_load) < 0.001, "A joint distal to knee contact must not carry the ground reaction")
	controller._last_torso_response_force = Vector3.ZERO
	torso.freeze = true
	controller.leg_limbs_can_support = false
	check(not controller._stance_chain_can_support(foot), "Limb support switch must work")
	controller.leg_limbs_can_support = true
	controller._active_leg = foot
	controller._step_state = controller.StepState.MOVING
	check(not controller._stance_chain_can_support(foot), "Stepping chains must release support")
	controller.cancel_step()
	controller._adhesion_release_time_remaining = 1.0
	check(not controller._stance_chain_can_support(foot), "Jump must release limb support")
	controller._adhesion_release_time_remaining = 0.0
	check(actor.get_internal_collision_diagnostics().missing_pairs == 0, "Physics activation must preserve every exception")
	chain.joints[0].queue_free()
	await process_frame
	await physics_frame
	check(actor.get_internal_collision_diagnostics().missing_pairs == 0, "Joint removal must not re-enable any internal collision")
	check(not controller._stance_chain_can_support(foot), "Broken joints must remove chain support")
	check(not controller.get_stance_support_diagnostics().is_empty(), "Diagnostics must tolerate deleted joints")
	generator._random.seed = 42
	check(actor.generate_creature(), "Regeneration failed")
	await physics_frame
	check(actor.get_internal_collision_diagnostics().missing_pairs == 0, "Regeneration must preserve complete collision filtering")
	if not failed: print("LEG_LIMB_SUPPORT_VALIDATION_PASSED")
	quit(1 if failed else 0)
